using Gtk;
using GLib;
using Singularity.Widgets;

namespace Singularity.Apps {

    public class WriteTemplateThumbnailer : Object {
        public const int PAGE_WIDTH = 600;
        public const int PAGE_HEIGHT = 800;
        public const int THUMB_WIDTH = 300;
        public const int THUMB_HEIGHT = 400;
        private const string VERSION = "1";

        public delegate void Ready(Gdk.Texture? texture);

        private class Job {
            public string key;
            public string html;
            public GLib.GenericArray<ReadyHolder> waiters = new GLib.GenericArray<ReadyHolder>();
        }

        private class ReadyHolder {
            public Ready cb;
            public ReadyHolder(owned Ready cb) { this.cb = (owned) cb; }
        }

        private static WriteTemplateThumbnailer? _instance = null;
        private HashTable<string, Gdk.Texture> _memory = new HashTable<string, Gdk.Texture>(str_hash, str_equal);
        private GLib.Queue<Job> _queue = new GLib.Queue<Job>();
        private HashTable<string, Job> _pending = new HashTable<string, Job>(str_hash, str_equal);
        private WebKit.WebView? _view = null;
        private Job? _current = null;
        private uint _timeout_id = 0;

        public static WriteTemplateThumbnailer get_default() {
            if (_instance == null) {
                _instance = new WriteTemplateThumbnailer();
                prune.begin();
            }
            return _instance;
        }

        private static async void prune() {
            var dir = GLib.File.new_for_path(cache_dir());
            int64 cutoff = new GLib.DateTime.now_utc().add_days(-30).to_unix();
            try {
                var en = yield dir.enumerate_children_async("standard::name,time::modified",
                                                            FileQueryInfoFlags.NONE, Priority.LOW, null);
                GLib.List<FileInfo> infos;
                while ((infos = yield en.next_files_async(64, Priority.LOW, null)) != null) {
                    foreach (var info in infos) {
                        var mtime = info.get_modification_date_time();
                        if (mtime != null && mtime.to_unix() < cutoff && info.get_name().has_suffix(".png"))
                            yield dir.get_child(info.get_name()).delete_async(Priority.LOW, null);
                    }
                }
            } catch (Error e) {
            }
        }

        public static bool dark_scheme() {
            var gs = Gtk.Settings.get_default();
            return gs != null && gs.gtk_application_prefer_dark_theme;
        }

        public static string cache_dir() {
            return GLib.Path.build_filename(GLib.Environment.get_user_cache_dir(), "singularity-write", "thumbnails");
        }

        public void request(string body, owned Ready cb) {
            bool dark = dark_scheme();
            string accent = Singularity.Style.StyleManager.get_default().accent_hex;
            string key = GLib.Checksum.compute_for_string(ChecksumType.SHA256,
                "%s\n%s\n%s\n%s".printf(VERSION, dark ? "dark" : "light", accent, body));
            var hit = _memory.lookup(key);
            if (hit != null) { cb(hit); return; }
            string path = GLib.Path.build_filename(cache_dir(), key + ".png");
            if (GLib.FileUtils.test(path, FileTest.EXISTS)) {
                try {
                    var tex = Gdk.Texture.from_filename(path);
                    _memory.insert(key, tex);
                    cb(tex);
                    return;
                } catch (Error e) {
                }
            }
            var job = _pending.lookup(key);
            if (job == null) {
                job = new Job();
                job.key = key;
                job.html = page_html(body, accent, dark);
                _pending.insert(key, job);
                _queue.push_tail(job);
            }
            job.waiters.add(new ReadyHolder((owned) cb));
            if (_current == null) next();
        }

        private string page_html(string body, string accent, bool dark) {
            string html = new Markdown.Parser().to_full_html(body, accent, dark);
            string page = "html{width:%dpx;height:%dpx;overflow:hidden}body{max-width:none;margin:0;padding:44px 52px;font-size:17px;box-sizing:border-box;min-height:%dpx}h1{margin-top:0}"
                .printf(PAGE_WIDTH, PAGE_HEIGHT, PAGE_HEIGHT);
            return html.replace("</style>", page + "</style>");
        }

        private void next() {
            _current = _queue.pop_head();
            if (_current == null) return;
            if (_view == null) {
                _view = (WebKit.WebView) Object.new(typeof(WebKit.WebView),
                    "web-context", new WebKit.WebContext(),
                    "network-session", new WebKit.NetworkSession.ephemeral());
                _view.load_changed.connect(on_load_changed);
            }
            _timeout_id = GLib.Timeout.add_seconds(8, () => {
                _timeout_id = 0;
                finish(null);
                return GLib.Source.REMOVE;
            });
            _view.load_html(_current.html, null);
        }

        private void on_load_changed(WebKit.LoadEvent ev) {
            if (ev != WebKit.LoadEvent.FINISHED || _current == null) return;
            var job = _current;
            _view.get_snapshot.begin(WebKit.SnapshotRegion.FULL_DOCUMENT, WebKit.SnapshotOptions.NONE, null, (o, r) => {
                if (job != _current) return;
                Gdk.Texture? result = null;
                try {
                    var shot = _view.get_snapshot.end(r);
                    result = store(job.key, shot);
                } catch (Error e) {
                    warning("Template thumbnail failed: %s", e.message);
                }
                finish(result);
            });
        }

        private Gdk.Texture? store(string key, Gdk.Texture shot) throws Error {
            var stream = new MemoryInputStream.from_bytes(shot.save_to_png_bytes());
            var full = new Gdk.Pixbuf.from_stream(stream);
            int h = int.min(full.height, full.width * PAGE_HEIGHT / PAGE_WIDTH);
            var page = new Gdk.Pixbuf.subpixbuf(full, 0, 0, full.width, h);
            var scaled = page.scale_simple(THUMB_WIDTH, THUMB_HEIGHT, Gdk.InterpType.HYPER);
            GLib.DirUtils.create_with_parents(cache_dir(), 0755);
            string path = GLib.Path.build_filename(cache_dir(), key + ".png");
            scaled.save(path, "png");
            var tex = Gdk.Texture.from_filename(path);
            _memory.insert(key, tex);
            return tex;
        }

        private void finish(Gdk.Texture? tex) {
            if (_timeout_id != 0) { GLib.Source.remove(_timeout_id); _timeout_id = 0; }
            var job = _current;
            _current = null;
            if (job != null) {
                _pending.remove(job.key);
                for (int i = 0; i < job.waiters.length; i++) job.waiters[i].cb(tex);
            }
            GLib.Idle.add(() => {
                if (_current == null) next();
                return GLib.Source.REMOVE;
            });
        }
    }

    public class WriteTemplateThumb : Widget {
        private int _w;
        private int _h;
        private Gdk.Paintable? _paintable = null;

        public Gdk.Paintable? paintable {
            get { return _paintable; }
            set { _paintable = value; queue_draw(); }
        }

        public WriteTemplateThumb(int width, int height) {
            _w = width;
            _h = height;
            add_css_class("write-template-thumb");
            overflow = Overflow.HIDDEN;
        }

        public override SizeRequestMode get_request_mode() {
            return SizeRequestMode.CONSTANT_SIZE;
        }

        public override void measure(Orientation orientation, int for_size, out int minimum, out int natural,
                                     out int minimum_baseline, out int natural_baseline) {
            minimum = natural = orientation == Orientation.HORIZONTAL ? _w : _h;
            minimum_baseline = natural_baseline = -1;
        }

        public override void snapshot(Snapshot snapshot) {
            if (_paintable == null) return;
            _paintable.snapshot(snapshot, get_width(), get_height());
        }
    }

    public class WriteTemplateGallery : Box {
        public signal void chosen(WriteTemplate template);
        public signal void rename_requested(WriteTemplate template);
        public signal void delete_requested(WriteTemplate template);

        public int card_width { get; construct; }
        public int builtin_limit { get; construct; }
        public int columns { get; construct; }
        public bool grouped { get; construct; }

        private uint _generation = 0;

        public WriteTemplateGallery(int card_width, int columns, int builtin_limit = -1, bool grouped = false) {
            Object(orientation: Orientation.VERTICAL, spacing: 18, card_width: card_width,
                   columns: columns, builtin_limit: builtin_limit, grouped: grouped);
        }

        construct {
            add_css_class("write-template-gallery");
            WriteTemplates.get_default().changed.connect(refresh);
            var gs = Gtk.Settings.get_default();
            if (gs != null) gs.notify["gtk-application-prefer-dark-theme"].connect(refresh);
            Singularity.Style.StyleManager.get_default().notify["accent-hex"].connect(refresh);
            refresh();
        }

        public void refresh() {
            _generation++;
            Widget? child;
            while ((child = get_first_child()) != null) remove(child);
            var builtin = WriteTemplates.builtin();
            var mine = WriteTemplates.get_default().user_templates();
            var first = new Gee.ArrayList<WriteTemplate>();
            int n = 0;
            foreach (var t in builtin) {
                if (builtin_limit >= 0 && n >= builtin_limit) break;
                first.add(t);
                n++;
            }
            append(section(_("Templates"), grouped ? _("Placeholders such as the date and your name are filled in for you") : null, first));
            if (mine.size > 0)
                append(section(_("Your Templates"), grouped ? _("Right-click a template to rename or delete it") : null, mine));
        }

        private Widget section(string title, string? description, Gee.ArrayList<WriteTemplate> items) {
            var flow = new FlowBox();
            flow.selection_mode = SelectionMode.NONE;
            flow.homogeneous = true;
            flow.min_children_per_line = int.min(2, columns);
            flow.max_children_per_line = columns;
            flow.column_spacing = 10;
            flow.row_spacing = 10;
            flow.add_css_class("write-template-flow");
            foreach (var t in items) {
                var cell = new FlowBoxChild();
                cell.focusable = false;
                cell.child = card(t);
                flow.append(cell);
            }
            var box = new Box(Orientation.VERTICAL, grouped ? 4 : 12);
            var lbl = new Label(title);
            lbl.add_css_class(grouped ? "title-4" : "title-2");
            lbl.halign = Align.START;
            box.append(lbl);
            if (description != null) {
                var sub = new Label(description);
                sub.add_css_class("dim-label");
                sub.halign = Align.START;
                sub.xalign = 0;
                sub.wrap = true;
                sub.margin_bottom = 8;
                box.append(sub);
            }
            box.append(flow);
            return box;
        }

        private Widget card(WriteTemplate t) {
            var btn = new Button();
            btn.add_css_class("flat");
            btn.add_css_class("write-template-card");
            btn.tooltip_text = t.description;
            btn.valign = Align.START;
            btn.halign = Align.START;
            var box = new Box(Orientation.VERTICAL, 4);
            var pic = new WriteTemplateThumb(card_width, card_width * WriteTemplateThumbnailer.PAGE_HEIGHT / WriteTemplateThumbnailer.PAGE_WIDTH);
            pic.halign = Align.START;
            pic.margin_bottom = 4;
            box.append(pic);
            var name = new Label(t.name);
            name.add_css_class("heading");
            name.xalign = 0;
            name.ellipsize = Pango.EllipsizeMode.END;
            name.max_width_chars = 1;
            box.append(name);
            var desc = new Label(t.description);
            desc.add_css_class("caption");
            desc.add_css_class("dim-label");
            desc.xalign = 0;
            desc.wrap = true;
            desc.wrap_mode = Pango.WrapMode.WORD_CHAR;
            desc.lines = 2;
            desc.ellipsize = Pango.EllipsizeMode.END;
            desc.max_width_chars = 1;
            desc.width_request = card_width;
            desc.valign = Align.START;
            box.append(desc);
            box.set_size_request(card_width, -1);
            btn.child = box;
            btn.update_property(Gtk.AccessibleProperty.LABEL, t.name, Gtk.AccessibleProperty.DESCRIPTION, t.description, -1);
            uint gen = _generation;
            string body = WriteTemplates.get_default().preview_text(t);
            WriteTemplateThumbnailer.get_default().request(body, (tex) => {
                if (gen != _generation || tex == null) return;
                pic.paintable = tex;
            });
            btn.clicked.connect(() => chosen(t));
            if (t.removable) {
                var click = new GestureClick();
                click.button = Gdk.BUTTON_SECONDARY;
                click.pressed.connect((n_press, x, y) => {
                    click.set_state(EventSequenceState.CLAIMED);
                    show_menu(btn, t, x, y);
                });
                btn.add_controller(click);
                var press = new GestureLongPress();
                press.pressed.connect((x, y) => show_menu(btn, t, x, y));
                btn.add_controller(press);
                var keys = new EventControllerKey();
                keys.key_pressed.connect((kv, kc, state) => {
                    if (kv == Gdk.Key.Menu || (kv == Gdk.Key.F10 && (state & Gdk.ModifierType.SHIFT_MASK) != 0)) {
                        show_menu(btn, t, btn.get_width() / 2.0, btn.get_height() / 2.0);
                        return true;
                    }
                    if (kv == Gdk.Key.Delete) { delete_requested(t); return true; }
                    if (kv == Gdk.Key.F2) { rename_requested(t); return true; }
                    return false;
                });
                btn.add_controller(keys);
            }
            return btn;
        }

        private void show_menu(Widget anchor, WriteTemplate t, double x, double y) {
            var menu = new Singularity.Widgets.ContextMenu(anchor);
            menu.add_item(_("Rename…"), "document-edit-symbolic", () => rename_requested(t));
            menu.add_item(_("Delete"), "user-trash-symbolic", () => delete_requested(t));
            var rect = Gdk.Rectangle() { x = (int) x, y = (int) y, width = 1, height = 1 };
            menu.set_pointing_to(rect);
            menu.closed.connect(() => menu.unparent());
            menu.popup();
        }
    }

    public class WriteTemplateDialogs : Object {

        public delegate void Chosen(WriteTemplate template);
        private delegate void Thunk();

        private static AppDialog make(Gtk.Application app, Gtk.Window parent, string title, int width, int height) {
            var dlg = new AppDialog(app, true);
            dlg.set_title(title);
            dlg.transient_for = parent;
            dlg.set_default_size(width, height);
            return dlg;
        }

        private static Box footer(AppDialog dlg) {
            var bar = new Box(Orientation.HORIZONTAL, 8);
            bar.margin_start = bar.margin_end = 18;
            bar.margin_bottom = 16;
            bar.margin_top = 4;
            var spacer = new Box(Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            bar.append(spacer);
            bar.append(dlg.add_cancel_button());
            dlg.content_box.append(bar);
            return bar;
        }

        public static void choose(Gtk.Application app, Gtk.Window parent, owned Chosen cb) {
            var dlg = make(app, parent, _("New from Template"), 760, 720);
            var scroll = new ScrolledWindow();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.vexpand = true;
            var gallery = new WriteTemplateGallery(138, 4, -1, true);
            gallery.margin_start = gallery.margin_end = 18;
            gallery.margin_top = 6;
            gallery.margin_bottom = 12;
            gallery.chosen.connect((t) => {
                dlg.close();
                cb(t);
            });
            gallery.rename_requested.connect((t) => rename(app, dlg, t));
            gallery.delete_requested.connect((t) => confirm_delete(app, dlg, t));
            scroll.child = gallery;
            dlg.content_box.append(scroll);
            footer(dlg);
            dlg.open_dialog();
        }

        public static void save_as(Gtk.Application app, Gtk.Window parent, string body, string suggested,
                                   owned Chosen? done = null) {
            var dlg = make(app, parent, _("Save as Template"), 440, 0);
            var box = new Box(Orientation.VERTICAL, 14);
            box.margin_start = box.margin_end = 18;
            box.margin_top = 6;
            box.margin_bottom = 8;
            var g = new PreferencesGroup(_("Template"),
                _("Use {{date}}, {{time}}, {{user}} and {{title}} to fill in details when a document is created"));
            var name = new EntryRow(_("Name"));
            name.text = suggested;
            g.add_row(name);
            box.append(g);
            var hint = new Label("");
            hint.add_css_class("caption");
            hint.add_css_class("dim-label");
            hint.xalign = 0;
            hint.wrap = true;
            box.append(hint);
            dlg.content_box.append(box);
            var bar = footer(dlg);
            var ok = new Button.with_label(_("Save"));
            ok.add_css_class("suggested-action");
            bar.append(ok);
            var store = WriteTemplates.get_default();
            Thunk update = () => {
                string n = WriteTemplates.safe_name(name.text);
                ok.sensitive = n != "";
                bool exists = n != "" && store.file_for_name(n).query_exists();
                hint.label = exists ? _("A template with this name already exists and will be replaced")
                                    : _("Saved in %s").printf(WriteTemplates.user_dir().replace(GLib.Environment.get_home_dir(), "~"));
                ok.label = exists ? _("Replace") : _("Save");
            };
            name.entry_changed.connect(() => update());
            update();
            Thunk commit = () => {
                if (!ok.sensitive) return;
                try {
                    var f = store.save(name.text, body);
                    dlg.close();
                    if (done != null) {
                        var t = store.find("user:" + f.get_path());
                        if (t != null) done(t);
                    }
                } catch (Error e) {
                    hint.label = e.message;
                }
            };
            ok.clicked.connect(() => commit());
            name.entry_activated.connect(() => commit());
            dlg.open_dialog();
            name.grab_focus();
        }

        public static void rename(Gtk.Application app, Gtk.Window parent, WriteTemplate t) {
            var dlg = new ConfirmDialog(app, _("Rename Template"), "text-x-generic-template", null,
                                        _("Rename"), ConfirmDialog.ActionStyle.SUGGESTED);
            dlg.transient_for = parent;
            var entry = new Entry();
            entry.text = t.name;
            entry.hexpand = true;
            entry.activates_default = false;
            ContextMenu.attach_editable(entry);
            var err = new Label("");
            err.add_css_class("caption");
            err.add_css_class("error");
            err.visible = false;
            err.wrap = true;
            dlg.custom_area.append(entry);
            dlg.custom_area.append(err);
            entry.changed.connect(() => {
                dlg.primary_sensitive = WriteTemplates.safe_name(entry.text) != "";
                err.visible = false;
            });
            dlg.response.connect((r) => {
                if (r != ConfirmDialog.Response.PRIMARY) return;
                try {
                    WriteTemplates.get_default().rename(t, entry.text);
                } catch (Error e) {
                    var msg = new ConfirmDialog.message(app, _("Could Not Rename Template"), "dialog-error", e.message);
                    msg.transient_for = parent;
                    msg.present();
                }
            });
            entry.activate.connect(() => {
                if (!dlg.primary_sensitive) return;
                dlg.response(ConfirmDialog.Response.PRIMARY);
                dlg.close();
            });
            dlg.present();
            entry.grab_focus();
            entry.select_region(0, -1);
        }

        public static void confirm_delete(Gtk.Application app, Gtk.Window parent, WriteTemplate t) {
            string where = t.kind == WriteTemplateKind.FOLDER
                ? _("The file will be moved from your Templates folder to the trash.")
                : _("The template will be moved to the trash.");
            var dlg = new ConfirmDialog(app, _("Delete “%s”?").printf(t.name), "user-trash-full", where,
                                        _("Delete"), ConfirmDialog.ActionStyle.DESTRUCTIVE);
            dlg.transient_for = parent;
            dlg.response.connect((r) => {
                if (r != ConfirmDialog.Response.PRIMARY) return;
                try {
                    WriteTemplates.get_default().remove(t);
                } catch (Error e) {
                    var msg = new ConfirmDialog.message(app, _("Could Not Delete Template"), "dialog-error", e.message);
                    msg.transient_for = parent;
                    msg.present();
                }
            });
            dlg.present();
        }
    }
}
