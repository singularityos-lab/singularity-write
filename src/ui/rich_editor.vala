using Gtk;
using Write;

namespace Singularity.Apps {

    public class WriteRichEditor : Gtk.Box {
        public Write.Document doc;
        public Write.Editor ed;
        public WriteDocView view;
        public WriteRibbon fbar;
        public WriteRuler ruler;
        public Gtk.Revealer ruler_rev;
        public Gtk.ScrolledWindow scroller;
        public Gtk.Revealer right_rev;
        public Gtk.Stack right_stack;
        public Gtk.Label status_page;
        public Gtk.Label status_words;
        public Gtk.Label status_lang;
        public Gtk.Label status_track;
        public Gtk.Scale zoom_scale;
        public Gtk.Label zoom_label;
        public WriteNavigationPane nav;
        public WriteCommentsPane comments_pane;
        public WriteReviewPane review_pane;
        public WriteStylesPane styles_pane;
        public WriteCheckPane check_pane;
        public GLib.File? file = null;
        public Write.FileFormat format = Write.FileFormat.DOCX;
        public bool modified = false;
        public weak Gtk.Window window;
        public weak Gtk.Application app;
        public GLib.Settings? settings = null;
        public Write.DataSource? merge_ds = null;
        public int merge_index = 0;
        public bool merge_preview = false;
        public bool recording = false;
        public Gee.ArrayList<string> macro_steps = new Gee.ArrayList<string>();
        public CharProps? painter_props = null;
        public ParaProps? painter_para = null;
        public string painter_style = "Normal";
        private bool syncing = false;
        private uint status_id = 0;
        public string recovery_id;

        public signal void title_changed();
        public signal void toast(string text);
        public signal void state_changed();

        public WriteRichEditor(Gtk.Window window, Gtk.Application app, GLib.Settings? settings) {
            Object(orientation: Orientation.VERTICAL, spacing: 0);
            this.window = window;
            this.app = app;
            this.settings = settings;
            recovery_id = Uuid.string_random();
            add_css_class("write-rich");
            Singularity.Widgets.apply_view_edge(this);
            fbar = new WriteRibbon();
            fbar.action.connect((n, p) => run(n, p));
            fbar.color_menu.set_builder((m) => WriteDialogs.fill_color_menu(this, false, m));
            fbar.highlight_menu.set_builder((m) => WriteDialogs.fill_color_menu(this, true, m));
            append(fbar);
            ruler = new WriteRuler();
            ruler_rev = new Gtk.Revealer();
            ruler_rev.child = ruler;
            ruler_rev.reveal_child = settings == null || settings.get_boolean("show-ruler");
            append(ruler_rev);
            var middle = new Box(Orientation.HORIZONTAL, 0);
            middle.vexpand = true;
            view = new WriteDocView();
            ruler.view = view;
            scroller = new Gtk.ScrolledWindow();
            scroller.hexpand = true;
            scroller.vexpand = true;
            scroller.child = view;
            middle.append(scroller);
            right_stack = new Gtk.Stack();
            right_stack.width_request = 300;
            right_rev = new Gtk.Revealer();
            right_rev.transition_type = RevealerTransitionType.SLIDE_LEFT;
            right_rev.child = right_stack;
            right_rev.reveal_child = false;
            right_rev.hexpand = false;
            middle.append(right_rev);
            append(middle);
            append(clipped(build_status()));
            nav = new WriteNavigationPane(this);
            comments_pane = new WriteCommentsPane(this);
            nav.add_page("comments", comments_pane, comments_pane.bar);
            review_pane = new WriteReviewPane(this);
            nav.add_page("review", review_pane, review_pane.bar);
            nav.map.connect(() => {
                sidebar_on = true;
                nav.refresh();
                state_changed();
            });
            nav.unmap.connect(() => {
                sidebar_on = false;
                state_changed();
            });
            state_changed.connect(() => fbar.sync_view(this));
            styles_pane = new WriteStylesPane(this);
            right_stack.add_named(styles_pane, "styles");
            check_pane = new WriteCheckPane(this);
            right_stack.add_named(check_pane, "check");
            view.selection_changed.connect(on_selection);
            view.changed.connect(on_changed);
            view.layout_changed.connect(() => {
                ruler.queue_draw();
                schedule_status();
            });
            view.zoom_changed.connect(() => {
                syncing = true;
                zoom_scale.set_value(view.zoom * 100);
                zoom_label.label = "%d%%".printf((int) Math.round(view.zoom * 100));
                syncing = false;
                ruler.queue_draw();
                fbar.sync_view(this);
            });
            view.context_menu.connect(on_context_menu);
            view.edit_equation.connect((e) => edit_equation.begin(e));
            view.edit_object.connect((it) => {
                if (it is Write.ChartRun) WriteDialogs.chart(this, (Write.ChartRun) it);
                else if (it is ImageRun || it is ShapeRun) WriteDialogs.object_properties(this, (FloatingInline) it);
            });
            view.open_link.connect(follow_link);
            view.comment_activated.connect((id) => {
                show_right("comments");
                comments_pane.focus_comment(id);
            });
            view.region_changed.connect(() => state_changed());
            view.typed.connect((t) => {
                if (recording) macro_steps.add("text:" + t);
            });
            scroller.vadjustment.value_changed.connect(schedule_status);
            ruler.indents_changed.connect((l, f, r) => {
                ed.checkpoint(_("Indent"));
                ed.format_paragraphs((p) => {
                    p.props.ind_left = l;
                    p.props.ind_first = f;
                    p.props.ind_right = r;
                });
            });
            ruler.margins_changed.connect((l, r) => {
                ed.checkpoint(_("Margins"));
                var s = doc.section_for(ed.focus.para);
                if (l >= 0) s.margin_left = l;
                if (r >= 0) s.margin_right = r;
                touch_all();
            });
            ruler.tab_added.connect((pos) => {
                ed.checkpoint(_("Tab Stop"));
                ed.format_paragraphs((p) => {
                    var pp = doc.styles.resolve_para(p);
                    var tabs = new Gee.ArrayList<TabStop>();
                    if (pp.tabs != null) foreach (var t in pp.tabs) tabs.add(t.copy());
                    tabs.add(new TabStop(pos));
                    tabs.sort((a, b) => a.pos < b.pos ? -1 : 1);
                    p.props.tabs = tabs;
                });
            });
            ruler.tab_removed.connect((i) => {
                ed.checkpoint(_("Tab Stop"));
                ed.format_paragraphs((p) => {
                    var pp = doc.styles.resolve_para(p);
                    if (pp.tabs == null || i >= pp.tabs.size) return;
                    var tabs = new Gee.ArrayList<TabStop>();
                    foreach (var t in pp.tabs) tabs.add(t.copy());
                    var clear = tabs[i].copy();
                    clear.align = TabAlign.CLEAR;
                    tabs.remove_at(i);
                    p.props.tabs = tabs;
                });
            });
            ruler.tab_moved.connect((i, pos) => {
                ed.checkpoint(_("Tab Stop"));
                ed.format_paragraphs((p) => {
                    var pp = doc.styles.resolve_para(p);
                    if (pp.tabs == null || i >= pp.tabs.size) return;
                    var tabs = new Gee.ArrayList<TabStop>();
                    foreach (var t in pp.tabs) tabs.add(t.copy());
                    tabs[i].pos = pos;
                    p.props.tabs = tabs;
                });
            });
            var drop = new Gtk.DropTarget(typeof(Gdk.FileList), Gdk.DragAction.COPY);
            drop.drop.connect((val, x, y) => {
                var fl = (Gdk.FileList) val.get_boxed();
                foreach (var f in fl.get_files()) {
                    string n = (f.get_basename() ?? "").down();
                    if (n.has_suffix(".png") || n.has_suffix(".jpg") || n.has_suffix(".jpeg") || n.has_suffix(".gif") || n.has_suffix(".svg") || n.has_suffix(".webp")) insert_picture_file(f);
                }
                return true;
            });
            view.add_controller(drop);
            load_settings();
            set_document(Write.Document.create_blank());
        }

        private static Gtk.Widget clipped(Gtk.Widget w) {
            var sw = new Gtk.ScrolledWindow();
            sw.hscrollbar_policy = PolicyType.EXTERNAL;
            sw.vscrollbar_policy = PolicyType.NEVER;
            sw.propagate_natural_height = true;
            sw.child = w;
            return sw;
        }

        private void load_settings() {
            if (settings == null) return;
            var schema = settings.settings_schema;
            if (schema.has_key("author-name")) {
                string a = settings.get_string("author-name");
                if (a != "") author_override = a;
            }
            if (schema.has_key("spell-as-you-type")) view.spell_enabled = settings.get_boolean("spell-as-you-type");
            if (schema.has_key("grammar-as-you-type")) view.grammar_enabled = settings.get_boolean("grammar-as-you-type");
            if (schema.has_key("measure-metric")) ruler.metric = settings.get_boolean("measure-metric");
            if (schema.has_key("show-formatting-marks")) view.opts.formatting_marks = settings.get_boolean("show-formatting-marks");
        }

        public string? author_override = null;

        public signal void scripts_found();

        public void set_document(Write.Document d) {
            doc_scripts = null;
            doc = d;
            ed = new Write.Editor(d);
            if (author_override != null) ed.author = author_override;
            view.filename = file != null ? file.get_basename() : "";
            view.set_document(d, ed);
            ed.undo.changed.connect(() => state_changed());
            fbar.set_styles(d);
            modified = false;
            merge_ds = null;
            merge_preview = false;
            if (d.merge_source != null && FileUtils.test(d.merge_source, FileTest.EXISTS)) {
                try {
                    merge_ds = Write.DataSource.load(d.merge_source);
                } catch (Error e) {
                }
            }
            apply_protection();
            nav.refresh();
            comments_pane.refresh();
            review_pane.refresh();
            styles_pane.refresh();
            on_selection();
            title_changed();
            state_changed();
            ChartSupport.prepare_all(doc);
            EquationSupport.render_all.begin(doc, () => {
                view.relayout_now();
                return false;
            });
        }

        public void apply_protection() {
            var k = doc.protection.enforced ? doc.protection.kind : ProtectKind.NONE;
            if (k == ProtectKind.TRACKED) doc.track_changes = true;
            fbar.set_editable(k != ProtectKind.READ_ONLY && k != ProtectKind.COMMENTS && k != ProtectKind.FORMS);
        }

        public bool editable() {
            return view.can_edit();
        }

        private Gtk.Widget build_status() {
            var bar = new Box(Orientation.HORIZONTAL, 12);
            bar.add_css_class("write-statusbar");
            bar.margin_start = 10;
            bar.margin_end = 10;
            bar.margin_top = 2;
            bar.margin_bottom = 2;
            status_page = new Label("");
            status_page.add_css_class("caption");
            var pb = new Gtk.Button();
            pb.child = status_page;
            pb.add_css_class("flat");
            pb.tooltip_text = _("Go to page");
            pb.clicked.connect(() => WriteDialogs.go_to(this));
            bar.append(pb);
            status_words = new Label("");
            status_words.add_css_class("caption");
            var wb = new Gtk.Button();
            wb.child = status_words;
            wb.add_css_class("flat");
            wb.tooltip_text = _("Word count");
            wb.clicked.connect(() => WriteDialogs.word_count(this));
            bar.append(wb);
            status_lang = new Label("");
            status_lang.add_css_class("caption");
            var lb = new Gtk.Button();
            lb.child = status_lang;
            lb.add_css_class("flat");
            lb.tooltip_text = _("Proofing language");
            lb.clicked.connect(() => WriteDialogs.language(this));
            bar.append(lb);
            status_track = new Label("");
            status_track.add_css_class("caption");
            bar.append(status_track);
            var spacer = new Box(Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            bar.append(spacer);
            var modes = new Singularity.Widgets.BubbleSwitcher();
            modes.add_option("read", _("Read"));
            modes.add_option("print", _("Print Layout"));
            modes.add_option("web", _("Web Layout"));
            modes.add_option("outline", _("Outline"));
            modes.set_active("print");
            modes.selected.connect((n) => {
                if (syncing) return;
                run("view", new Variant.string(n));
            });
            view_switch = modes;
            bar.append(modes);
            var zo = new Gtk.Button.from_icon_name("zoom-out-symbolic");
            zo.add_css_class("flat");
            zo.tooltip_text = _("Zoom out");
            zo.clicked.connect(() => view.set_zoom(view.zoom / 1.1));
            bar.append(zo);
            zoom_scale = new Gtk.Scale.with_range(Orientation.HORIZONTAL, 10, 500, 5);
            zoom_scale.width_request = 120;
            zoom_scale.draw_value = false;
            zoom_scale.set_value(100);
            zoom_scale.add_mark(100, PositionType.BOTTOM, null);
            zoom_scale.value_changed.connect(() => {
                if (syncing) return;
                view.set_zoom(zoom_scale.get_value() / 100.0);
            });
            bar.append(zoom_scale);
            var zi = new Gtk.Button.from_icon_name("zoom-in-symbolic");
            zi.add_css_class("flat");
            zi.tooltip_text = _("Zoom in");
            zi.clicked.connect(() => view.set_zoom(view.zoom * 1.1));
            bar.append(zi);
            zoom_label = new Label("100%");
            zoom_label.add_css_class("caption");
            zoom_label.add_css_class("numeric");
            zoom_label.width_chars = 5;
            var zb = new Gtk.Button();
            var zbox = new Box(Orientation.HORIZONTAL, 4);
            zbox.append(zoom_label);
            var zarrow = new Image.from_icon_name("pan-down-symbolic");
            zarrow.pixel_size = 12;
            zbox.append(zarrow);
            zb.child = zbox;
            zb.add_css_class("flat");
            zb.tooltip_text = _("Zoom");
            zb.clicked.connect(() => WriteRibbon.popup_menu(zb, (m) => {
                foreach (string z in new string[] { "50", "75", "100", "125", "150", "200" }) {
                    string zz = z;
                    m.add_item(zz + "%", null, () => run("zoom", new Variant.string(zz)));
                }
                m.add_separator();
                m.add_item(_("Page Width"), null, () => run("zoom", new Variant.string("width")));
                m.add_item(_("Whole Page"), null, () => run("zoom", new Variant.string("page")));
            }));
            bar.append(zb);
            return bar;
        }

        public Singularity.Widgets.BubbleSwitcher view_switch;

        private void schedule_status() {
            if (status_id != 0) return;
            status_id = Timeout.add(120, () => {
                status_id = 0;
                update_status();
                return Source.REMOVE;
            });
        }

        public void update_status() {
            if (view.lay == null) return;
            int pg = view.visible_page();
            int cur = pg;
            var lb = view.line_for(ed.focus);
            if (lb != null) cur = lb.page;
            int total = view.lay.pages.size;
            string num = cur < total ? view.lay.pages[cur].number_text : "";
            if (view.mode == ViewMode.WEB) status_page.label = _("Web Layout");
            else if (view.mode == ViewMode.OUTLINE) status_page.label = _("Outline");
            else if (view.mode == ViewMode.DRAFT) status_page.label = _("Draft");
            else status_page.label = _("Page %d of %d").printf(cur + 1, total) + (num != (cur + 1).to_string() ? " (%s)".printf(num) : "");
            var st = Write.Stats.compute(doc, false);
            if (ed.has_selection) {
                int sel = Write.Stats.count_words(ed.selected_text());
                status_words.label = ngettext("%d of %d word", "%d of %d words", st.words).printf(sel, st.words);
            } else {
                status_words.label = ngettext("%d word", "%d words", st.words).printf(st.words);
            }
            var c = doc.styles.resolve_char(ed.focus.para, ed.focus.para.props_at(ed.focus.offset));
            string lang = Write.Hyphenator.default_lang();
            if (doc.lang != "") lang = doc.lang;
            if (c.lang != null) lang = c.lang;
            status_lang.label = lang.replace("_", "-");
            string prot = "";
            if (doc.protection.enforced) {
                switch (doc.protection.kind) {
                    case ProtectKind.READ_ONLY: prot = _("Read-only"); break;
                    case ProtectKind.COMMENTS: prot = _("Comments only"); break;
                    case ProtectKind.TRACKED: prot = _("Tracked changes only"); break;
                    case ProtectKind.FORMS: prot = _("Filling in forms"); break;
                    default: break;
                }
            }
            string track = doc.track_changes ? _("Track Changes: On") : "";
            if (recording) track = (track != "" ? track + "  " : "") + _("Recording macro");
            if (merge_preview && merge_ds != null) track = (track != "" ? track + "  " : "") + _("Record %d of %d").printf(merge_index + 1, merge_ds.records.size);
            if (Dictation.active()) track = (track != "" ? track + "  " : "") + _("Dictating");
            string stl = prot;
            if (track != "") stl = stl != "" ? stl + "  " + track : track;
            if (live != null) {
                var names = new Gee.ArrayList<string>();
                foreach (var peer in live.peers.values) names.add(peer.name);
                string lv = names.size == 0 ? _("Live: waiting for others") : _("Live with %s").printf(string.joinv(", ", names.to_array()));
                stl = stl != "" ? stl + "  " + lv : lv;
            }
            status_track.label = stl;
        }

        private void on_selection() {
            schedule_presence();
            if (painter_props != null && ed.has_selection && fbar.painter.active) {
                var cp = painter_props;
                var pp = painter_para;
                string st = painter_style;
                ed.checkpoint(_("Format Painter"));
                ed.format_chars((c) => {
                    var link = c.link;
                    c.overlay(cp);
                    c.link = link;
                });
                if (pp != null) ed.format_paragraphs((p) => {
                    p.style = st;
                    p.props = pp.copy();
                });
                if (!painter_sticky) {
                    painter_props = null;
                    fbar.set_painter(false);
                }
            }
            fbar.sync(doc, ed, view.pending);
            schedule_status();
            ruler.queue_draw();
            nav.highlight_current();
            state_changed();
        }

        public bool painter_sticky = false;

        public WriteLiveSession? live = null;
        public Write.LiveDoc? live_doc = null;
        private uint live_publish_id = 0;
        private uint live_presence_id = 0;
        private bool live_applying = false;
        public signal void live_changed();

        private void live_attach(WriteLiveSession s) {
            live = s;
            live.packet.connect(on_live_packet);
            live.peers_changed.connect(() => {
                sync_remote_carets();
                live_changed();
                update_status();
            });
            live.state_requested.connect(() => {
                live_flush();
                live.publish_state(live_doc.full_state(doc));
            });
            live.ended.connect((reason) => {
                toast(reason);
                stop_live();
            });
            live_changed();
            update_status();
        }

        public void start_live_host() throws Error {
            stop_live();
            live_doc = new Write.LiveDoc("host");
            var s = new WriteLiveSession(ed.author);
            live_doc.peer_id = s.my_id;
            s.host(live_doc.full_state(doc));
            live_attach(s);
            send_presence();
        }

        public async void join_live(string link) throws Error {
            stop_live();
            var s = new WriteLiveSession(ed.author);
            live_doc = new Write.LiveDoc(s.my_id);
            live_attach(s);
            yield s.join(link);
            send_presence();
        }

        public void start_live_folder(string dir, bool create) throws Error {
            stop_live();
            var s = new WriteLiveSession(ed.author);
            live_doc = new Write.LiveDoc(s.my_id);
            live_attach(s);
            s.start_folder(dir, create ? live_doc.full_state(doc) : null);
            send_presence();
        }

        public void stop_live() {
            if (live_publish_id != 0) {
                Source.remove(live_publish_id);
                live_publish_id = 0;
            }
            if (live != null) live.leave();
            live = null;
            live_doc = null;
            view.remote.clear();
            view.queue_draw();
            live_changed();
            update_status();
        }

        private bool first_packet = true;

        private void on_live_packet(Write.LivePacket p) {
            if (live_doc == null) return;
            var f = Write.LiveDoc.position_of(doc, ed.focus);
            var a = Write.LiveDoc.position_of(doc, ed.anchor);
            live_applying = true;
            bool joining = first_packet && live.mode != WriteLiveSession.Mode.HOST;
            first_packet = false;
            if (joining) {
                doc.body.items.clear();
            }
            bool changed = live_doc.apply(doc, p);
            if (joining) {
                for (int i = doc.body.size - 1; i >= 0; i--) if (!p.order.contains(doc.body[i].uid)) doc.body.items.remove_at(i);
                if (doc.body.size == 0) doc.body.add(new Paragraph());
                live_doc.mark_synced(doc);
            }
            if (changed) {
                ed.undo.undo_list.clear();
                ed.undo.redo_list.clear();
                var nf = f != null ? Write.LiveDoc.resolve(doc, f) : null;
                var na = a != null ? Write.LiveDoc.resolve(doc, a) : null;
                if (nf == null) nf = new Pos(doc.body.first_paragraph() ?? new Paragraph(), 0);
                ed.select(na ?? nf, nf);
                ed.changed();
                fbar.set_styles(doc);
                if (p.who != "" && !joining) view.remote_edit_by = p.who;
            }
            live_applying = false;
            sync_remote_carets();
        }

        private void live_flush() {
            if (live == null || live_doc == null) return;
            var p = live_doc.collect(doc);
            if (p != null) live.send(p);
        }

        private void schedule_live_publish() {
            if (live == null || live_applying) return;
            if (live_publish_id != 0) Source.remove(live_publish_id);
            live_publish_id = Timeout.add(250, () => {
                live_publish_id = 0;
                live_flush();
                return false;
            });
        }

        private void send_presence() {
            if (live == null || live_doc == null) return;
            live_doc.assign_uids(doc);
            live.presence(Write.LiveDoc.position_of(doc, ed.focus), ed.has_selection ? Write.LiveDoc.position_of(doc, ed.anchor) : null);
        }

        private void schedule_presence() {
            if (live == null || live_presence_id != 0) return;
            live_presence_id = Timeout.add(150, () => {
                live_presence_id = 0;
                send_presence();
                return false;
            });
        }

        private void sync_remote_carets() {
            view.remote.clear();
            if (live != null) {
                foreach (var peer in live.peers.values) {
                    if (peer.focus == null) continue;
                    var rc = new RemoteCaret();
                    rc.name = peer.name;
                    rc.color = peer.color;
                    rc.focus = peer.focus;
                    rc.anchor = peer.anchor;
                    view.remote.add(rc);
                }
            }
            view.queue_draw();
        }

        private void on_changed() {
            schedule_live_publish();
            schedule_change_script();
            if (!modified) {
                modified = true;
                title_changed();
            }
            view.pending = null;
            nav.schedule_refresh();
            if (sidebar_shown()) {
                string vis = nav.page;
                if (vis == "comments") comments_pane.refresh();
                else if (vis == "review") review_pane.refresh();
            }
            fbar.sync(doc, ed, view.pending);
            schedule_status();
            state_changed();
        }

        public void touch_all() {
            foreach (var p in Story.all(doc)) p.touch();
            ed.changed();
        }

        private bool sidebar_on = false;

        public bool sidebar_shown() {
            return sidebar_on;
        }

        public string sidebar_page() {
            return nav.page;
        }

        public void show_left(bool show) {
            var w = window as Singularity.Widgets.Window;
            sidebar_on = show;
            if (w != null) w.set_sidebar_visible(show);
            if (settings != null) settings.set_boolean("show-outline", show);
            if (show) nav.refresh();
            state_changed();
        }

        public void show_right(string name) {
            if (name == "comments" || name == "review") {
                if (sidebar_shown() && nav.page == name) {
                    show_left(false);
                    return;
                }
                show_left(true);
                nav.show_page(name);
                return;
            }
            if (right_rev.reveal_child && right_stack.visible_child_name == name) {
                right_rev.reveal_child = false;
            right_rev.hexpand = false;
                state_changed();
                return;
            }
            right_stack.visible_child_name = name;
            right_rev.reveal_child = true;
            switch (name) {
                case "comments": comments_pane.refresh(); break;
                case "review": review_pane.refresh(); break;
                case "styles": styles_pane.refresh(); break;
                default: break;
            }
            state_changed();
        }

        public string title() {
            string n;
            if (file != null) n = file.get_basename();
            else if (doc.meta.title != "") n = doc.meta.title;
            else n = _("Untitled Document");
            return n;
        }

        private void follow_link(string url) {
            if (url.has_prefix("#")) {
                string name = url.substring(1);
                foreach (var p in Story.all(doc)) foreach (var i in p.inlines) if (i is Mark && ((Mark) i).kind == MarkKind.BOOKMARK_START && ((Mark) i).name == name) {
                    view.scroll_to_para(p);
                    return;
                }
                return;
            }
            try {
                AppInfo.launch_default_for_uri(url.contains("://") || url.has_prefix("mailto:") ? url : "https://" + url, null);
            } catch (Error e) {
                toast(e.message);
            }
        }

        public async void edit_equation(Write.EquationRun e) {
            if (!EquationSupport.available()) {
                WriteDialogs.equation_text(this, e);
                return;
            }
            ed.checkpoint(_("Edit Equation"));
            if (yield EquationSupport.edit(e, window)) {
                var p = find_para_of(e);
                var c = p != null ? doc.styles.resolve_char(p, e.props) : new CharProps();
                e.preview = null;
                yield EquationSupport.render(e, c.size > 0 ? c.size : 11);
                if (p != null) p.touch();
                ed.changed();
            }
        }

        public Paragraph? find_para_of(Inline item) {
            foreach (var p in Story.all(doc)) if (p.inlines.contains(item)) return p;
            return null;
        }

        public async void insert_equation_run(Write.EquationRun e) {
            ed.checkpoint(_("Insert Equation"));
            var c = doc.styles.resolve_char(ed.focus.para, ed.props_for_insert());
            yield EquationSupport.render(e, c.size > 0 ? c.size : 11);
            if (e.display) {
                if (!ed.focus.para.is_empty()) ed.split_paragraph();
                ed.format_paragraphs((p) => p.props.align = Write.Align.CENTER);
            }
            ed.insert_inline(e);
        }

        public async void insert_equation(bool display) {
            var e = new Write.EquationRun("");
            e.display = display;
            if (!EquationSupport.available()) {
                WriteDialogs.equation_text(this, e, true);
                return;
            }
            if (!(yield EquationSupport.edit(e, window))) return;
            ed.checkpoint(_("Insert Equation"));
            var c = doc.styles.resolve_char(ed.focus.para, ed.props_for_insert());
            yield EquationSupport.render(e, c.size > 0 ? c.size : 11);
            if (display) {
                if (!ed.focus.para.is_empty()) ed.split_paragraph();
                ed.format_paragraphs((p) => p.props.align = Write.Align.CENTER);
            }
            ed.insert_inline(e);
        }

        public void insert_picture_file(GLib.File f) {
            try {
                uint8[] data;
                FileUtils.get_data(f.get_path(), out data);
                var bytes = new Bytes(data);
                var img = new ImageRun(bytes, ImageRun.sniff(data));
                int w, h;
                Write.HtmlReader.natural_size(bytes, out w, out h);
                double maxw = doc.section_for(ed.focus.para).column_width();
                double pw = w > 0 ? w * 0.75 : 200;
                double ph = h > 0 ? h * 0.75 : 150;
                if (pw > maxw) {
                    ph = ph * maxw / pw;
                    pw = maxw;
                }
                img.width = pw;
                img.height = ph;
                img.name = f.get_basename();
                ed.checkpoint(_("Insert Picture"));
                ed.insert_inline(img);
            } catch (Error e) {
                toast(e.message);
            }
        }

        public void insert_shape(ShapeKind kind) {
            var s = new ShapeRun(kind);
            s.wrap = Wrap.SQUARE;
            s.width = kind == ShapeKind.LINE ? 144 : (kind == ShapeKind.TEXT_BOX ? 180 : 108);
            s.height = kind == ShapeKind.LINE ? 0.1 : (kind == ShapeKind.TEXT_BOX ? 72 : 72);
            s.hrel = HRel.COLUMN;
            s.vrel = VRel.PARAGRAPH;
            s.hoff = 100;
            s.voff = 0;
            if (kind == ShapeKind.TEXT_BOX) {
                s.fill = "#ffffff";
                s.text.add(new Paragraph.with_text(_("Text")));
            } else {
                s.fill = "#4472c4";
                s.stroke = "#2f528f";
            }
            ed.checkpoint(_("Insert Shape"));
            ed.insert_inline(s);
        }

        public void insert_wordart(string text) {
            var s = new ShapeRun(ShapeKind.TEXT_BOX);
            s.wordart = true;
            s.fill = null;
            s.stroke = null;
            s.width = 300;
            s.height = 70;
            s.wrap = Wrap.TOP_BOTTOM;
            s.halign = HAlignObj.CENTER;
            var c = new CharProps();
            c.size = 40;
            c.bold = Tri.ON;
            c.color = "#2f5496";
            c.shadow = Tri.ON;
            c.font = "Liberation Sans";
            var p = new Paragraph.with_text(text, "Normal", c);
            p.props.align = Write.Align.CENTER;
            s.text.add(p);
            ed.checkpoint(_("Insert WordArt"));
            ed.insert_inline(s);
        }

        public void insert_note(NoteKind kind) {
            var n = new Note(kind);
            var p = new Paragraph(kind == NoteKind.FOOTNOTE ? "FootnoteText" : "EndnoteText");
            n.blocks.add(p);
            var r = new NoteRef(n);
            var c = ed.props_for_insert();
            c.style = kind == NoteKind.FOOTNOTE ? "FootnoteReference" : "EndnoteReference";
            r.props = c;
            ed.checkpoint(kind == NoteKind.FOOTNOTE ? _("Insert Footnote") : _("Insert Endnote"));
            ed.insert_inline(r);
            view.relayout_now();
            ed.set_caret(new Pos(p, 0));
        }

        public void insert_comment() {
            if (doc.protection.enforced && doc.protection.kind == ProtectKind.READ_ONLY) return;
            ed.checkpoint(_("New Comment"));
            string id = doc.next_id().to_string();
            while (doc.find_comment(id) != null) id = doc.next_id().to_string();
            var c = new Comment(id, ed.author);
            c.blocks.add(new Paragraph("CommentText"));
            doc.comments.add(c);
            Pos a, b;
            ed.ordered(out a, out b);
            if (!ed.has_selection) {
                int s, e;
                ed.word_at(a, out s, out e);
                a = new Pos(a.para, s);
                b = new Pos(a.para, e);
            }
            int bi = b.para.split_at(b.offset);
            b.para.inlines.insert(bi, new Mark(MarkKind.COMMENT_END, id));
            int ai = a.para.split_at(a.offset);
            a.para.inlines.insert(ai, new Mark(MarkKind.COMMENT_START, id));
            a.para.touch();
            b.para.touch();
            ed.changed();
            show_right("comments");
            comments_pane.refresh();
            comments_pane.focus_comment(id, true);
        }

        public void delete_comment(string id) {
            ed.checkpoint(_("Delete Comment"));
            foreach (var p in Story.all(doc)) {
                for (int i = p.inlines.size - 1; i >= 0; i--) {
                    var m = p.inlines[i] as Mark;
                    if (m != null && (m.kind == MarkKind.COMMENT_START || m.kind == MarkKind.COMMENT_END) && m.name == id) {
                        p.inlines.remove_at(i);
                        p.touch();
                    }
                }
            }
            for (int i = doc.comments.size - 1; i >= 0; i--) {
                if (doc.comments[i].id == id || doc.comments[i].parent_id == id) doc.comments.remove_at(i);
            }
            ed.changed();
            comments_pane.refresh();
        }

        public Gee.ArrayList<string> comment_order() {
            var ids = new Gee.ArrayList<string>();
            foreach (var p in Story.paragraphs(doc.body)) foreach (var i in p.inlines) if (i is Mark && ((Mark) i).kind == MarkKind.COMMENT_START) ids.add(((Mark) i).name);
            return ids;
        }

        public void goto_comment(string id) {
            foreach (var p in Story.all(doc)) {
                int off = 0;
                foreach (var i in p.inlines) {
                    if (i is Mark && ((Mark) i).kind == MarkKind.COMMENT_START && ((Mark) i).name == id) {
                        ed.set_caret(new Pos(p, off));
                        view.active_comment = id;
                        view.queue_draw();
                        return;
                    }
                    off += i.length;
                }
            }
        }

        public void goto_revision(int dir) {
            var list = Review.collect(doc);
            if (list.size == 0) {
                toast(_("There are no tracked changes."));
                return;
            }
            var order = Story.paragraphs(doc.body);
            int cur_i = order.index_of(ed.focus.para);
            RevisionRef? target = null;
            foreach (var r in (dir > 0 ? list : reversed(list))) {
                int ri = order.index_of(r.para);
                if (dir > 0 ? (ri > cur_i || (ri == cur_i && r.offset > ed.focus.offset)) : (ri < cur_i || (ri == cur_i && r.offset < ed.focus.offset - 1))) {
                    target = r;
                    break;
                }
            }
            if (target == null) target = dir > 0 ? list[0] : list[list.size - 1];
            int len = target.item != null ? target.item.length : 0;
            ed.select(new Pos(target.para, target.offset), new Pos(target.para, target.offset + len));
            review_pane.refresh();
        }

        private Gee.ArrayList<RevisionRef> reversed(Gee.ArrayList<RevisionRef> l) {
            var r = new Gee.ArrayList<RevisionRef>();
            for (int i = l.size - 1; i >= 0; i--) r.add(l[i]);
            return r;
        }

        public void resolve_current(bool accept) {
            Pos a, b;
            ed.ordered(out a, out b);
            ed.checkpoint(accept ? _("Accept Change") : _("Reject Change"));
            int count = 0;
            foreach (var r in Review.collect(doc)) {
                int cmp1 = Story.compare(doc, a, new Pos(r.para, r.offset + (r.item != null ? r.item.length : 0)));
                int cmp2 = Story.compare(doc, new Pos(r.para, r.offset), b);
                bool inside = ed.has_selection ? (cmp1 <= 0 && cmp2 <= 0) : (r.para == a.para && a.offset >= r.offset && a.offset <= r.offset + (r.item != null ? r.item.length : 0));
                if (!inside) continue;
                Review.resolve(doc, r, accept);
                count++;
            }
            if (count == 0) {
                goto_revision(1);
                return;
            }
            ed.set_caret(new Pos(a.para, int.min(a.offset, a.para.length)));
            ed.changed();
            goto_revision(1);
        }

        public void update_fields() {
            var lay = view.lay;
            var up = new FieldUpdater(doc, (p) => {
                if (lay == null) return 1;
                int pi = lay.page_of(p);
                return pi >= 0 && pi < lay.pages.size ? lay.pages[pi].number : 1;
            });
            up.filename = file != null ? file.get_basename() : "";
            up.filepath = file != null ? (file.get_path() ?? "") : "";
            up.update_all();
            view.relayout_now();
            lay = view.lay;
            up.update_all();
            foreach (var p in Story.all(doc)) p.touch();
            ed.changed();
        }

        private void on_context_menu(double x, double y) {
            var menu = new Singularity.Widgets.ContextMenu(view);
            var sr = view.spell_at(ed.focus);
            if (sr != null && !ed.has_selection) {
                var p = ed.focus.para;
                string word = usub(p.text(), sr.start, sr.end);
                string[] sugg = sr.grammar && sr.issue != null ? sr.issue.suggestions : Singularity.Text.SpellChecker.get_default().suggest(word, 5);
                if (sr.grammar && sr.issue != null) menu.add_item(sr.issue.message, "dialog-information-symbolic", () => {});
                foreach (string s in sugg) {
                    string rep = s;
                    int st = sr.start, en = sr.end;
                    menu.add_item(rep == "" ? _("(delete)") : rep, "tools-check-spelling-symbolic", () => {
                        ed.checkpoint(_("Spelling"));
                        var props = p.props_at(st + 1);
                        ed.select(new Pos(p, st), new Pos(p, en));
                        ed.delete_selection();
                        if (rep != "") ed.insert_text(rep, props);
                    });
                }
                if (!sr.grammar) {
                    menu.add_item(_("Ignore All"), "edit-clear-symbolic", () => {
                        view.ignored.add(word);
                        view.refresh_spelling();
                    });
                    menu.add_item(_("Add to Dictionary"), "list-add-symbolic", () => {
                        Singularity.Text.SpellChecker.get_default().add_to_dictionary(word);
                        view.refresh_spelling();
                    });
                    menu.add_item(_("Synonyms\u2026"), "accessories-dictionary-symbolic", () => WriteDialogs.thesaurus(this, word));
                }
                menu.add_separator();
            }
            if (view.selected_obj != null) {
                var it = view.selected_obj.item;
                if (it is ImageRun || it is ShapeRun) {
                    menu.add_item(_("Picture and Wrapping\u2026"), "image-x-generic-symbolic", () => WriteDialogs.object_properties(this, (FloatingInline) it));
                    menu.add_item(_("Alt Text\u2026"), "preferences-desktop-accessibility-symbolic", () => WriteDialogs.alt_text(this, (FloatingInline) it));
                    if (it is ImageRun) menu.add_item(_("Crop"), "edit-cut-symbolic", () => {
                        view.crop_mode = true;
                        view.queue_draw();
                    });
                    menu.add_item(_("Insert Caption\u2026"), "insert-text-symbolic", () => WriteDialogs.caption(this));
                }
                if (it is EquationRun) menu.add_item(_("Edit Equation"), "accessories-calculator-symbolic", () => edit_equation.begin((EquationRun) it));
                menu.add_separator();
            }
            menu.add_item(_("Cut"), "edit-cut-symbolic", () => run("cut", null));
            menu.add_item(_("Copy"), "edit-copy-symbolic", () => run("copy", null));
            menu.add_item(_("Paste"), "edit-paste-symbolic", () => run("paste", null));
            menu.add_item(_("Paste as Plain Text"), "edit-paste-symbolic", () => run("paste-text", null));
            menu.add_separator();
            var link_item = ed.focus.para.inline_at(ed.focus.offset);
            if (link_item != null && link_item.props.link != null) {
                string url = link_item.props.link;
                menu.add_item(_("Open Link"), "web-browser-symbolic", () => follow_link(url));
                menu.add_item(_("Edit Link\u2026"), "insert-link-symbolic", () => run("link", null));
                menu.add_item(_("Remove Link"), "edit-clear-symbolic", () => run("remove-link", null));
                menu.add_separator();
            }
            if (ed.cell_at(ed.focus) != null) {
                menu.add_item(_("Insert Row Above"), "list-add-symbolic", () => run("table-op", new Variant.string("row-above")));
                menu.add_item(_("Insert Row Below"), "list-add-symbolic", () => run("table-op", new Variant.string("row-below")));
                menu.add_item(_("Insert Column Left"), "list-add-symbolic", () => run("table-op", new Variant.string("col-left")));
                menu.add_item(_("Insert Column Right"), "list-add-symbolic", () => run("table-op", new Variant.string("col-right")));
                menu.add_item(_("Delete Row"), "list-remove-symbolic", () => run("table-op", new Variant.string("delete-row")));
                menu.add_item(_("Delete Column"), "list-remove-symbolic", () => run("table-op", new Variant.string("delete-col")));
                menu.add_item(_("Merge With Right Cell"), "view-dual-symbolic", () => run("table-op", new Variant.string("merge-right")));
                menu.add_item(_("Merge With Cell Below"), "view-dual-symbolic", () => run("table-op", new Variant.string("merge-down")));
                menu.add_item(_("Split Cell"), "view-dual-symbolic", () => run("table-op", new Variant.string("split")));
                menu.add_item(_("Table Properties\u2026"), "document-properties-symbolic", () => run("table-properties", null));
                menu.add_separator();
            }
            menu.add_item(_("Font\u2026"), "font-x-generic-symbolic", () => run("font-dialog", null));
            menu.add_item(_("Paragraph\u2026"), "format-justify-left-symbolic", () => run("paragraph-dialog", null));
            menu.add_item(_("New Comment"), "mail-message-new-symbolic", () => run("new-comment", null));
            menu.add_item(_("Link\u2026"), "insert-link-symbolic", () => run("link", null));
            if (Review.collect(doc).size > 0) {
                menu.add_separator();
                menu.add_item(_("Accept Change"), "object-select-symbolic", () => resolve_current(true));
                menu.add_item(_("Reject Change"), "edit-undo-symbolic", () => resolve_current(false));
            }
            var r = Gdk.Rectangle() { x = (int) x, y = (int) y, width = 1, height = 1 };
            menu.set_pointing_to(r);
            menu.closed.connect(() => menu.unparent());
            menu.popup();
        }

        public void copy_to_clipboard(bool cut) {
            if (!ed.has_selection) return;
            var frag = ed.copy_selection();
            var fd = new Write.Document();
            fd.styles = doc.styles.copy();
            fd.numbering = doc.numbering.copy();
            fd.sources = doc.sources;
            foreach (var b in frag.items) fd.body.add(b);
            fd.final_section = doc.final_section.copy();
            var providers = new Gdk.ContentProvider[0];
            try {
                var docx = DocxWriter.save(fd);
                providers += new Gdk.ContentProvider.for_bytes("application/x-singularity-write", new Bytes(docx));
                providers += new Gdk.ContentProvider.for_bytes("application/vnd.openxmlformats-officedocument.wordprocessingml.document", new Bytes(docx));
            } catch (Error e) {
            }
            string html = HtmlWriter.save(fd);
            providers += new Gdk.ContentProvider.for_bytes("text/html", new Bytes(html.data));
            providers += new Gdk.ContentProvider.for_bytes("text/rtf", new Bytes(RtfWriter.save(fd)));
            string text = ed.selected_text();
            providers += new Gdk.ContentProvider.for_value(text);
            if (view.selected_obj != null && view.selected_obj.item is ImageRun) {
                var img = (ImageRun) view.selected_obj.item;
                providers += new Gdk.ContentProvider.for_bytes(img.mime, img.data);
            }
            get_clipboard().set_content(new Gdk.ContentProvider.union(providers));
            if (cut && editable()) {
                ed.checkpoint(_("Cut"));
                ed.delete_selection();
            }
        }

        public async void paste(string mode) {
            if (!editable()) return;
            var cb = get_clipboard();
            var formats = cb.get_formats();
            string[] prefer;
            if (mode == "text") prefer = { "text/plain;charset=utf-8", "text/plain" };
            else if (mode == "picture") prefer = { "image/png", "image/jpeg" };
            else prefer = { "application/x-singularity-write", "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "text/html", "text/rtf", "image/png", "image/jpeg", "text/plain;charset=utf-8", "text/plain" };
            string? chosen = null;
            foreach (string m in prefer) if (formats.contain_mime_type(m)) {
                chosen = m;
                break;
            }
            if (chosen == null) {
                try {
                    string? t = yield cb.read_text_async(null);
                    if (t != null) {
                        ed.checkpoint(_("Paste"));
                        ed.insert_text(t);
                    }
                } catch (Error e) {
                }
                return;
            }
            try {
                string out_mime;
                var stream = yield cb.read_async({ chosen }, Priority.DEFAULT, null, out out_mime);
                var mem = new MemoryOutputStream.resizable();
                yield mem.splice_async(stream, OutputStreamSpliceFlags.CLOSE_SOURCE | OutputStreamSpliceFlags.CLOSE_TARGET, Priority.DEFAULT, null);
                var data = mem.steal_as_bytes();
                ed.checkpoint(_("Paste"));
                if (chosen.has_prefix("image/")) {
                    var img = new ImageRun(data, ImageRun.sniff(data.get_data()));
                    int w, h;
                    Write.HtmlReader.natural_size(data, out w, out h);
                    img.width = w > 0 ? double.min(w * 0.75, 450) : 200;
                    img.height = h > 0 ? img.width * h / double.max(1, w) : 150;
                    ed.insert_inline(img);
                    return;
                }
                if (chosen.has_prefix("text/plain")) {
                    var sb = new StringBuilder();
                    sb.append_len((string) data.get_data(), (ssize_t) data.get_size());
                    ed.insert_text(sb.str.make_valid());
                    return;
                }
                Write.Document src;
                if (chosen == "text/html") {
                    var sb = new StringBuilder();
                    sb.append_len((string) data.get_data(), (ssize_t) data.get_size());
                    src = HtmlReader.load(sb.str.make_valid(), null);
                } else if (chosen == "text/rtf") {
                    src = RtfReader.load(data.get_data());
                } else {
                    src = DocxReader.load(data.get_data());
                }
                if (mode != "merge") {
                    foreach (var s in src.styles.list) if (doc.styles.get(s.id) == null) doc.styles.add(s.copy());
                }
                var nums = doc.numbering.merge(src.numbering);
                foreach (var p in Story.paragraphs(src.body)) {
                    if (p.props.num_id > 0 && nums.has_key(p.props.num_id)) p.props.num_id = nums[p.props.num_id];
                }
                if (mode == "merge") {
                    foreach (var p in Story.paragraphs(src.body)) {
                        p.style = ed.focus.para.style;
                        foreach (var i in p.inlines) {
                            var keep = new CharProps();
                            keep.bold = i.props.bold;
                            keep.italic = i.props.italic;
                            keep.underline = i.props.underline;
                            keep.link = i.props.link;
                            i.props = keep;
                        }
                    }
                }
                ed.insert_blocks(src.body, true);
            } catch (Error e) {
                toast(_("Could not paste: %s").printf(e.message));
            }
        }

        public void set_view_mode(string mode) {
            ViewMode m = ViewMode.PRINT;
            switch (mode) {
                case "web": m = ViewMode.WEB; break;
                case "read": m = ViewMode.READ; break;
                case "outline": m = ViewMode.OUTLINE; break;
                case "draft": m = ViewMode.DRAFT; break;
                default: m = ViewMode.PRINT; break;
            }
            view.read_only = m == ViewMode.READ;
            view.set_mode(m);
            if (m == ViewMode.READ) {
                view.fit_page = true;
                view.relayout_now();
            } else {
                view.fit_page = false;
            }
            fbar.visible = m != ViewMode.READ;
            ruler_rev.visible = m == ViewMode.PRINT;
            syncing = true;
            view_switch.set_active(mode == "draft" ? "print" : mode);
            syncing = false;
            state_changed();
        }

        public void set_zoom_named(string z) {
            if (z == "width") {
                view.fit_width = true;
                view.fit_page = false;
                view.relayout_now();
            } else if (z == "page") {
                view.fit_page = true;
                view.fit_width = false;
                view.relayout_now();
            } else {
                view.set_zoom(double.parse(z) / 100.0);
            }
        }

        public void run(string name, Variant? param) {
            if (recording && name != "macro-record" && name != "macro-run" && name != "macros") macro_steps.add("action:%s:%s".printf(name, param != null ? param.print(true) : ""));
            WriteActions.run(this, name, param);
            if (name != "undo" && name != "redo") fbar.sync(doc, ed, view.pending);
        }

        private Write.ScriptRunner? doc_scripts = null;
        private bool scripts_running = false;
        private uint change_script_id = 0;

        private Write.ScriptRunner make_runner() {
            var runner = new Write.ScriptRunner(doc, ed);
            runner.set_message((t) => toast(t));
            runner.set_action((n, p) => {
                if (!(n in WriteActions.names())) return false;
                Variant? v = null;
                if (p != null) v = WriteActions.is_double(n) ? new Variant.double(double.parse(p)) : new Variant.string(p);
                WriteActions.run(this, n, v);
                return true;
            });
            return runner;
        }

        public string run_script(string source) {
            if (scripts_running) return _("A script is already running.");
            scripts_running = true;
            ed.checkpoint(_("Run Script"));
            var runner = make_runner();
            string res;
            try {
                runner.run(source);
                res = runner.output.size > 0 ? string.joinv("\n", runner.output.to_array()) : _("The script finished.");
            } catch (Write.ScriptError e) {
                res = e.message;
                toast(e.message);
            }
            if (runner.changed) {
                touch_all();
                ed.changed();
            }
            scripts_running = false;
            return res;
        }

        public void load_document_scripts(bool trusted) {
            doc_scripts = null;
            if (!trusted) return;
            var runner = make_runner();
            bool any = false;
            foreach (string m in doc.macros) {
                if (!m.has_prefix("script:")) continue;
                try {
                    runner.run(m.substring(m.index_of_char('\n') + 1).replace("\r", ""));
                    any = true;
                } catch (Write.ScriptError e) {
                    toast(e.message);
                }
            }
            if (any && runner.handlers.size > 0) doc_scripts = runner;
        }

        public bool has_document_scripts() {
            foreach (string m in doc.macros) if (m.has_prefix("script:")) return true;
            return false;
        }

        public void fire_script_event(string ev) {
            if (doc_scripts == null || scripts_running || !doc_scripts.handlers.has_key(ev)) return;
            scripts_running = true;
            doc_scripts.changed = false;
            try {
                doc_scripts.fire(ev);
            } catch (Write.ScriptError e) {
                toast(e.message);
            }
            if (doc_scripts.changed) {
                touch_all();
                ed.changed();
            }
            scripts_running = false;
        }

        private void schedule_change_script() {
            if (doc_scripts == null || scripts_running || !doc_scripts.handlers.has_key("change")) return;
            if (change_script_id != 0) Source.remove(change_script_id);
            change_script_id = Timeout.add(800, () => {
                change_script_id = 0;
                fire_script_event("change");
                return false;
            });
        }

        public void play_macro(string body) {
            foreach (string line in body.split("\n")) {
                if (line.has_prefix("text:")) {
                    ed.checkpoint(_("Macro"), true);
                    ed.insert_text(line.substring(5), view.pending ?? ed.props_for_insert());
                } else if (line.has_prefix("action:")) {
                    string rest = line.substring(7);
                    int c = rest.index_of_char(':');
                    string n = c >= 0 ? rest.substring(0, c) : rest;
                    string ps = c >= 0 ? rest.substring(c + 1) : "";
                    Variant? v = null;
                    if (ps != "") {
                        try {
                            v = Variant.parse(null, ps);
                        } catch (Error e) {
                        }
                    }
                    WriteActions.run(this, n, v);
                }
            }
        }
    }
}
