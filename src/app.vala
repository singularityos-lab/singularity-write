using Gtk;
using Gdk;
using GLib;
using WebKit;
using Singularity;
using Singularity.Widgets;

namespace Singularity.Apps {

    public class WriteApp : Singularity.Application {

        // UI
        private WriteWindow main_window;
        private Singularity.Widgets.ToolBar toolbar { get { return main_window.toolbar; } }
        private Singularity.Widgets.PageCanvas  page_canvas;
        private Singularity.Widgets.FloatingFormatBar format_bar;
        private Singularity.Widgets.FindReplaceBar    find_bar;
        private Singularity.Widgets.StyleChooser      style_chooser;
        private Gtk.Entry       _font_entry;
        private Gtk.SpinButton  _size_spin;
        private bool            _font_ctrl_updating = false;

        private Gtk.TextView   text_view;
        private Gtk.TextBuffer text_buffer;
        private Gtk.ScrolledWindow doc_scroll;
        private Box   outline_box;
        private Label word_count_label;
        private Singularity.Widgets.IconButton _export_btn;

        // Layout stack (ODT vs Markdown)
        private Gtk.Stack _layout_stack;
        private Gtk.Revealer _sidebar_revealer;

        // Tags
        private Gtk.TextTag tag_bold;
        private Gtk.TextTag tag_italic;
        private Gtk.TextTag tag_underline;
        private Gtk.TextTag tag_strike;
        private Gtk.TextTag tag_h1;
        private Gtk.TextTag tag_h2;
        private Gtk.TextTag tag_h3;
        private Gtk.TextTag tag_h4;
        private Gtk.TextTag tag_body;
        private Gtk.TextTag tag_quote;
        private Gtk.TextTag tag_code;
        private Gtk.TextTag tag_link;
        private Gtk.TextTag tag_bullet;
        private Gtk.TextTag tag_numbered;

        // State
        private GLib.File?    current_file = null;
        private Gtk.Box?      _recent_list_box = null;
        private bool          modified     = false;
        private GLib.Settings settings;
        private uint          autosave_id  = 0;
        private int           footnote_num = 0;
        private bool          _updating_sel = false;
        private bool          _format_bar_updating = false;

        // Word-like UX state
        private bool          _auto_format_lock  = false;
        private int           _last_home_line    = -1;
        private bool          _smart_quotes_on   = true;
        private string        _last_search_query = "";
        private Gtk.TextTag   tag_hr;

        // Markdown mode
        private bool          _is_markdown    = false;
        private bool          _md_ui_built    = false;
        private uint          _md_update_timer = 0;
        private GtkSource.View _md_source_view;   // R page - GtkSource for syntax highlight
        private GtkSource.View _md_source_view_s; // S page - same buffer as R
        private GtkSource.Buffer _md_buffer;
        private Widget        _md_mode_switcher_widget;
        private WebKit.WebView _md_preview_s;  // S page preview
        private WebKit.WebView _md_preview_v;  // V page preview (separate - can't share)
        private Gtk.Stack      _md_stack;
        private Widget _md_mode_switcher;


        public WriteApp() {
            Object(application_id: "dev.sinty.write",
                   flags: ApplicationFlags.HANDLES_OPEN);
        }

        protected override void activate() {
            setup_styles();
            settings = load_settings ();
            build_ui();
            settings.changed["md-color-scheme"].connect(update_md_color_scheme);
            show_start_page();
            main_window.present();
            main_window.close_request.connect(on_close_request);
        }

        protected override void open(GLib.File[] files, string hint) {
            setup_styles();
            settings = load_settings ();
            build_ui();
            settings.changed["md-color-scheme"].connect(update_md_color_scheme);
            if (files.length > 0) {
                main_window.flat = false;
                toolbar.visible = true;
                do_open(files[0]);
            } else {
                show_start_page();
            }
            main_window.present();
            main_window.close_request.connect(on_close_request);
        }

        private GLib.Settings load_settings () {
            var src = SettingsSchemaSource.get_default ();
            if (src != null && src.lookup ("dev.sinty.write", true) != null)
                return new GLib.Settings ("dev.sinty.write");
            try {
                string exe = GLib.FileUtils.read_link ("/proc/self/exe");
                var data_dir = GLib.File.new_for_path (exe)
                    .get_parent ().get_child ("data");
                if (data_dir.get_child ("gschemas.compiled").query_exists ()) {
                    var cs = new SettingsSchemaSource.from_directory (
                        data_dir.get_path (), src, true);
                    var schema = cs.lookup ("dev.sinty.write", true);
                    if (schema != null)
                        return new GLib.Settings.full (schema, null, null);
                }
            } catch (Error e) {}
            return new GLib.Settings ("dev.sinty.write");
        }

        private bool on_close_request() {
            if (autosave_id != 0) { Source.remove(autosave_id); autosave_id = 0; }
            if (!modified) return false;
            bool is_unsaved_new = (current_file == null);
            var dlg = new Singularity.Widgets.ConfirmDialog((Gtk.Application)this,
                "Save Changes?", "dialog-warning-symbolic",
                is_unsaved_new
                    ? "This document has never been saved. Save it first, or discard changes."
                    : "You have unsaved changes.",
                "Discard & Close", Singularity.Widgets.ConfirmDialog.ActionStyle.DESTRUCTIVE);
            if (!is_unsaved_new)
                dlg.set_secondary("Save", Singularity.Widgets.ConfirmDialog.ActionStyle.SUGGESTED);
            dlg.transient_for = main_window;
            dlg.response.connect((r) => {
                if (r == Singularity.Widgets.ConfirmDialog.Response.CANCEL) return;
                if (r == Singularity.Widgets.ConfirmDialog.Response.SECONDARY) on_save();
                modified = false;
                main_window.close();
            });
            dlg.present();
            return true;
        }

        // Build UI

        private void build_ui() {
            main_window = new WriteWindow((Gtk.Application)this);

            // App menubar (used by Singularity global menu and standalone mode)
            var menu = new GLib.Menu();
            var file_menu = new GLib.Menu();
            file_menu.append("Settings", "app.settings");
            file_menu.append("Quit", "app.quit");
            menu.append_submenu("File", file_menu);
            set_menubar(menu);

            // App-level actions
            var act_quit = new SimpleAction("quit", null);
            act_quit.activate.connect(() => quit());
            add_action(act_quit);
            var act_settings = new SimpleAction("settings", null);
            act_settings.activate.connect(() => {
                try {
                    Singularity.Shell.ShellService shell = GLib.Bus.get_proxy_sync(
                        GLib.BusType.SESSION, "dev.sinty.desktop", "/dev/sinty/Shell");
                    shell.open_settings("apps");
                } catch (Error e) {
                    warning("Failed to open settings: %s", e.message);
                }
            });
            add_action(act_settings);

            setup_text_buffer();
            build_toolbar();
            build_layout();
            setup_keyboard();
            setup_autosave();
        }

        private void setup_text_buffer() {
            text_buffer = new Gtk.TextBuffer(null);
            text_buffer.enable_undo = true;

            tag_bold      = text_buffer.create_tag("bold",      "weight",      700);
            tag_italic    = text_buffer.create_tag("italic",    "style",       Pango.Style.ITALIC);
            tag_underline = text_buffer.create_tag("underline", "underline",   Pango.Underline.SINGLE);
            tag_strike    = text_buffer.create_tag("strikethrough", "strikethrough", true);

            tag_h1 = text_buffer.create_tag("h1",
                "weight", 700, "scale", 2.0,
                "pixels-above-lines", 14, "pixels-below-lines", 6);
            tag_h2 = text_buffer.create_tag("h2",
                "weight", 700, "scale", 1.6,
                "pixels-above-lines", 10, "pixels-below-lines", 4);
            tag_h3 = text_buffer.create_tag("h3",
                "weight", 700, "scale", 1.3,
                "pixels-above-lines", 8, "pixels-below-lines", 3);
            tag_h4 = text_buffer.create_tag("h4",
                "weight", 600, "scale", 1.1,
                "pixels-above-lines", 6, "pixels-below-lines", 2);
            tag_body = text_buffer.create_tag("body",
                "scale", 1.0, "weight", 400);
            tag_quote = text_buffer.create_tag("quote",
                "style", Pango.Style.ITALIC,
                "left-margin", 32,
                "foreground", "#999999");
            tag_code = text_buffer.create_tag("code",
                "family", "Monospace",
                "scale", 0.92);
            tag_link = text_buffer.create_tag("link",
                "foreground", "#5599ff",
                "underline", Pango.Underline.SINGLE);
            tag_bullet = text_buffer.create_tag("bullet",
                "left-margin", 28, "indent", -14,
                "pixels-above-lines", 1, "pixels-below-lines", 1);
            tag_numbered = text_buffer.create_tag("numbered",
                "left-margin", 32, "indent", -18,
                "pixels-above-lines", 1, "pixels-below-lines", 1);
            tag_hr = text_buffer.create_tag("hr",
                "foreground", "#999999", "scale", 0.7,
                "justification", Gtk.Justification.CENTER,
                "pixels-above-lines", 6, "pixels-below-lines", 6);

            _smart_quotes_on = settings.get_boolean("smart-quotes");

            text_buffer.changed.connect(on_buffer_changed);
            text_buffer.mark_set.connect(on_mark_set);
            // apply_tag / remove_tag do NOT emit changed - connect separately so
            // heading style changes update the outline without a full text edit.
            text_buffer.apply_tag.connect((tag, start, end) => {
                GLib.Idle.add(() => { update_outline(); return GLib.Source.REMOVE; });
            });
            text_buffer.remove_tag.connect((tag, start, end) => {
                GLib.Idle.add(() => { update_outline(); return GLib.Source.REMOVE; });
            });
        }

        private void build_toolbar() {
            toolbar.is_static = false;

            // File actions
            var new_btn  = new Singularity.Widgets.IconButton("document-new-symbolic",  "New (Ctrl+N)");
            var open_btn = new Singularity.Widgets.IconButton("document-open-symbolic",  "Open (Ctrl+O)");
            var save_btn = new Singularity.Widgets.IconButton("document-save-symbolic",  "Save (Ctrl+S)");
            _export_btn = new Singularity.Widgets.IconButton("document-send-symbolic", "Export / Print…");
            var export_btn = _export_btn;
            new_btn.clicked.connect(on_new);
            open_btn.clicked.connect(on_open);
            save_btn.clicked.connect(on_save);
            export_btn.clicked.connect(on_export);
            toolbar.pack_start(new_btn);
            toolbar.pack_start(open_btn);
            toolbar.pack_start(save_btn);
            toolbar.pack_start(export_btn);

            var sep1 = new Separator(Orientation.VERTICAL);
            sep1.margin_top = 8; sep1.margin_bottom = 8;
            toolbar.pack_start(sep1);

            // Outline sidebar toggle
            var sidebar_btn = new Singularity.Widgets.IconButton("sidebar-show-symbolic", "Toggle Outline");
            sidebar_btn.clicked.connect(() => {
                _sidebar_revealer.reveal_child = !_sidebar_revealer.reveal_child;
            });
            toolbar.pack_start(sidebar_btn);

            var sep2 = new Separator(Orientation.VERTICAL);
            sep2.margin_top = 8; sep2.margin_bottom = 8;
            toolbar.pack_start(sep2);

            // Insert popover: single button opens popover with all insert options
            var insert_popover = new Popover();
            insert_popover.has_arrow = false;

            var insert_box = new Box(Orientation.VERTICAL, 2);
            insert_box.margin_top = 4;
            insert_box.margin_bottom = 4;
            insert_box.margin_start = 4;
            insert_box.margin_end = 4;

            string[] insert_icons  = { "view-list-bullet-symbolic", "view-list-ordered-symbolic", "x-office-spreadsheet-symbolic", "insert-image-symbolic", "insert-link-symbolic", "format-indent-more-symbolic" };
            string[] insert_labels = { "Bullet List", "Numbered List", "Table", "Image", "Link", "Footnote" };
            string[] insert_ids    = { "bullet", "numbered", "table", "image", "link", "footnote" };

            for (int ii = 0; ii < insert_icons.length; ii++) {
                var row = new Box(Orientation.HORIZONTAL, 8);
                row.margin_top = 2; row.margin_bottom = 2;
                row.margin_start = 4; row.margin_end = 8;
                var ico = new Image.from_icon_name(insert_icons[ii]);
                ico.pixel_size = 16;
                var lbl = new Label(insert_labels[ii]);
                lbl.halign = Align.START;
                row.append(ico);
                row.append(lbl);
                var ibtn = new Button();
                ibtn.set_child(row);
                ibtn.has_frame = false;
                ibtn.add_css_class("singularity-button");
                string captured_id = insert_ids[ii];
                ibtn.clicked.connect(() => {
                    insert_popover.popdown();
                    switch (captured_id) {
                        case "bullet":   apply_list_style(true);    text_view.grab_focus(); break;
                        case "numbered": apply_list_style(false);   text_view.grab_focus(); break;
                        case "table":    on_insert_table();   break;
                        case "image":    on_insert_image();   break;
                        case "link":     on_link_requested(); break;
                        case "footnote": on_insert_footnote(); break;
                    }
                });
                insert_box.append(ibtn);
            }
            insert_popover.set_child(insert_box);

            var insert_btn = new MenuButton();
            insert_btn.icon_name = "list-add-symbolic";
            insert_btn.tooltip_text = "Insert";
            insert_btn.has_frame = false;
            insert_btn.add_css_class("singularity-button");
            insert_btn.set_popover(insert_popover);
            toolbar.pack_start(insert_btn);

            // Right side
            var find_btn = new Singularity.Widgets.IconButton("edit-find-symbolic", "Find & Replace (Ctrl+F)");
            find_btn.clicked.connect(() => find_bar.open_find());

            word_count_label = new Label("0 words");
            word_count_label.add_css_class("dim-label");
            word_count_label.add_css_class("caption");

            // Close document button on the right - goes back to start page
            var close_doc_btn = new Singularity.Widgets.IconButton("go-previous-symbolic", "Back to Start (close document)");
            close_doc_btn.clicked.connect(on_close_document);

            toolbar.pack_end(find_btn);
            toolbar.pack_end(word_count_label);
            toolbar.pack_end(close_doc_btn);

            // ODT style chooser + font family + size (center title widget)
            style_chooser = new Singularity.Widgets.StyleChooser();
            style_chooser.style_selected.connect(on_style_selected);

            _font_entry = new Entry();
            _font_entry.placeholder_text = "Font";
            _font_entry.width_chars = 16;
            _font_entry.tooltip_text = "Font Family";
            // EntryCompletion for system fonts (populated lazily after realize)
            var completion = new EntryCompletion();
            var font_store = new Gtk.ListStore(1, typeof(string));
            completion.set_model(font_store);
            completion.set_text_column(0);
            completion.inline_completion = true;
            _font_entry.set_completion(completion);
            _font_entry.realize.connect_after(() => {
                Pango.FontFamily[] fam_list;
                _font_entry.get_pango_context().list_families(out fam_list);
                foreach (var fam in fam_list) {
                    Gtk.TreeIter it;
                    font_store.append(out it);
                    font_store.set(it, 0, fam.get_name());
                }
            });
            _font_entry.activate.connect(() => {
                if (_font_ctrl_updating) return;
                string fname = _font_entry.text.strip();
                if (fname == "") return;
                Gtk.TextIter s, e;
                if (!text_buffer.get_selection_bounds(out s, out e)) return;
                var desc = new Pango.FontDescription();
                desc.set_family(fname);
                desc.set_size((int)(_size_spin.value * Pango.SCALE));
                apply_font_desc(desc);
                text_view.grab_focus();
            });

            var adj = new Adjustment(12, 6, 96, 1, 4, 0);
            _size_spin = new SpinButton(adj, 1, 0);
            _size_spin.width_chars = 4;
            _size_spin.tooltip_text = "Font Size";
            _size_spin.value_changed.connect(() => {
                if (_font_ctrl_updating) return;
                string fname = _font_entry.text.strip();
                if (fname == "") return;
                Gtk.TextIter s, e;
                if (!text_buffer.get_selection_bounds(out s, out e)) return;
                var desc = new Pango.FontDescription();
                desc.set_family(fname);
                desc.set_size((int)(_size_spin.value * Pango.SCALE));
                apply_font_desc(desc);
            });

            var font_sep = new Separator(Orientation.VERTICAL);
            font_sep.margin_top = 6; font_sep.margin_bottom = 6; font_sep.margin_start = 4; font_sep.margin_end = 4;
            var title_box = new Box(Orientation.HORIZONTAL, 4);
            _font_title_box = title_box;
            title_box.valign = Align.CENTER;
            title_box.append(style_chooser);
            title_box.append(font_sep);
            title_box.append(_font_entry);
            title_box.append(_size_spin);
            toolbar.set_title_widget(title_box);
        }

        private const double DOC_MM_TO_PX = 3.7795275591;

        private void apply_doc_margins(double left_mm, double right_mm) {
            int left_px  = (int)(left_mm  * DOC_MM_TO_PX);
            int right_px = (int)(right_mm * DOC_MM_TO_PX);
            int tb_px    = (int)(25.4 * DOC_MM_TO_PX); // 1 inch top/bottom
            text_view.left_margin   = left_px;
            text_view.right_margin  = right_px;
            text_view.top_margin    = tb_px;
            text_view.bottom_margin = tb_px;
        }

        private void build_layout() {
            var root = main_window.root;
            var content_hbox = main_window.content_hbox;

            // TextView
            text_view = new Gtk.TextView.with_buffer(text_buffer);
            text_view.wrap_mode     = WrapMode.WORD_CHAR;
            text_view.hexpand       = true;
            text_view.vexpand       = true;
            text_view.pixels_above_lines = 2;
            text_view.pixels_below_lines = 2;
            text_view.add_css_class("write-doc-text");
            setup_text_context_menu();

            // PageCanvas
            page_canvas = new Singularity.Widgets.PageCanvas();
            page_canvas.left_margin_mm  = settings.get_double("left-margin-mm");
            page_canvas.right_margin_mm = settings.get_double("right-margin-mm");
            page_canvas.set_content_widget(text_view);
            apply_doc_margins(page_canvas.left_margin_mm, page_canvas.right_margin_mm);
            
            page_canvas.margins_changed.connect((l, r) => {
                apply_doc_margins(l, r);
                settings.set_double("left-margin-mm",  l);
                settings.set_double("right-margin-mm", r);
            });

            // FloatingFormatBar - parented to doc_scroll after it is created below
            format_bar = new Singularity.Widgets.FloatingFormatBar();
            format_bar.format_toggled.connect(on_format_toggled);
            format_bar.color_changed.connect(on_color_changed);
            format_bar.link_requested.connect(on_link_requested);
            format_bar.alignment_changed.connect((just) => {
                Gtk.TextIter s, e;
                text_buffer.get_iter_at_mark(out s, text_buffer.get_insert());
                text_buffer.get_iter_at_mark(out e, text_buffer.get_insert());
                s.set_line_offset(0);
                if (!e.ends_line()) e.forward_to_line_end();
                text_view.set_justification(just);
            });

            // Outline sidebar
            var outline_header = new Label("Outline");
            outline_header.add_css_class("write-outline-header");
            outline_header.halign = Align.START;
            outline_header.margin_start = 12;
            outline_header.margin_top   = 10;
            outline_header.margin_bottom = 6;

            outline_box = new Box(Orientation.VERTICAL, 0);
            outline_box.add_css_class("write-outline-list");
            var outline_scroll = new ScrolledWindow();
            outline_scroll.vexpand = true;
            outline_scroll.set_policy(PolicyType.NEVER, PolicyType.AUTOMATIC);
            outline_scroll.set_child(outline_box);

            var left_panel = new Box(Orientation.VERTICAL, 0);
            left_panel.add_css_class("write-sidebar");
            left_panel.set_size_request(180, -1);
            left_panel.append(outline_header);
            left_panel.append(outline_scroll);

            _sidebar_revealer = new Revealer();
            _sidebar_revealer.transition_type = RevealerTransitionType.SLIDE_RIGHT;
            _sidebar_revealer.set_child(left_panel);
            _sidebar_revealer.reveal_child = false;  // hidden by default - toggle via toolbar

            doc_scroll = new ScrolledWindow();
            doc_scroll.hexpand = true;
            doc_scroll.vexpand = true;
            // Wrap page_canvas in a box with a spacer so content starts below the floating toolbar
            var odt_wrap = new Box(Orientation.VERTICAL, 0);
            odt_wrap.hexpand = true;
            odt_wrap.vexpand = true;
            odt_wrap.append(new Singularity.Widgets.ToolbarSpacer.with_height(54));
            odt_wrap.append(page_canvas);
            doc_scroll.set_child(odt_wrap);

            // Parent format bar to doc_scroll to avoid scroll-on-popup
            format_bar.set_parent(doc_scroll);

            // FindReplaceBar
            find_bar = new Singularity.Widgets.FindReplaceBar();
            find_bar.find_next.connect((q) => { _last_search_query = q; do_find_forward(q); });
            find_bar.find_prev.connect((q) => { _last_search_query = q; do_find_backward(q); });
            find_bar.replace_one.connect(do_replace_one);
            find_bar.replace_all.connect(do_replace_all);
            find_bar.closed.connect(() => {
                find_bar.reveal_child = false;
                text_view.grab_focus();
            });

            // Layout stack: "odt" = doc_scroll only (sidebar moved to shared wrapper below)
            _layout_stack = new Gtk.Stack();
            _layout_stack.hexpand = true;
            _layout_stack.vexpand = true;
            _layout_stack.transition_type = Gtk.StackTransitionType.CROSSFADE;
            _layout_stack.transition_duration = 150;
            _layout_stack.add_named(doc_scroll, "odt");
            build_start_page(); // adds "start" to _layout_stack

            // Shared sidebar+content wrapper - sidebar visible in both ODT and MD modes
            var _sidebar_sep = new Separator(Orientation.VERTICAL);
            _sidebar_sep.visible = false;
            _sidebar_revealer.notify["child-revealed"].connect(() => {
                _sidebar_sep.visible = _sidebar_revealer.child_revealed;
            });
            _sidebar_revealer.notify["reveal-child"].connect(() => {
                if (_sidebar_revealer.reveal_child) _sidebar_sep.visible = true;
            });

            content_hbox.append(_sidebar_revealer);
            content_hbox.append(_sidebar_sep);
            content_hbox.append(_layout_stack);

            root.append(content_hbox);
            root.append(find_bar);

            main_window.set_content(root);
        }


        private void build_start_page() {
            var wp = new Singularity.Widgets.WelcomePage();
            wp.app_icon_name = "dev.sinty.write";
            wp.title = "Write";
            wp.subtitle = "Write notes in Markdown, read PDFs alongside";
            wp.show_close_button = false;

            wp.add_action(
                "text-x-generic-symbolic",
                "New Markdown Note",
                "Plain-text format with live\npreview and R/S/V editing modes.",
                () => {
                    _is_markdown = true;
                    enter_markdown_mode();
                    _md_buffer.set_text("", -1);
                    current_file = null;
                    modified = false;
                    footnote_num = 0;
                    update_title();
                    main_window.flat = false;
                    toolbar.visible = true;
                    _layout_stack.visible_child_name = "markdown";
                }
            );
            wp.add_action(
                "document-open-symbolic",
                "Open Markdown",
                "Open an existing .md or .markdown\nfile from disk.",
                () => { on_open_with_kind("md"); }
            );
            wp.add_action(
                "document-open-symbolic",
                "Open PDF",
                "Read a PDF in the paginated\nviewer with floating controls.",
                () => { on_open_with_kind("pdf"); }
            );

            // Recent section
            var recent_wrap = new Box(Orientation.VERTICAL, 12);

            var recent_section_lbl = new Label("Recent");
            recent_section_lbl.add_css_class("title-2");
            recent_section_lbl.halign = Align.START;

            var recent_list = new Box(Orientation.VERTICAL, 2);
            recent_list.add_css_class("write-recent-list");
            _recent_list_box = recent_list;
            refresh_recent_list(recent_list);

            recent_wrap.append(recent_section_lbl);
            recent_wrap.append(recent_list);
            wp.set_extra_widget(recent_wrap);

            _layout_stack.add_named(wp, "start");
        }

        private void add_to_recent(GLib.File file) {
            string uri = file.get_uri();
            string[] current = settings.get_strv("recent-files");
            string[] updated = { uri };
            int count = 1;
            foreach (string u in current) {
                if (u == uri) continue;
                if (count >= 20) break;
                updated += u;
                count++;
            }
            settings.set_strv("recent-files", updated);
        }

        private void refresh_recent_list(Box list) {
            // Clear
            while (list.get_first_child() != null)
                list.remove(list.get_first_child());

            string[] uris = settings.get_strv("recent-files");
            int shown = 0;
            foreach (string uri in uris) {
                if (shown >= 10) break;
                var f = GLib.File.new_for_uri(uri);
                if (!f.query_exists()) continue;
                shown++;

                string path = f.get_path() ?? uri;
                string fname = f.get_basename() ?? uri;
                string fpath = path.replace(GLib.Environment.get_home_dir(), "~");
                bool is_md = uri.has_suffix(".md") || uri.has_suffix(".markdown");

                // Get file modification time
                string date_str = "";
                try {
                    var info = f.query_info(GLib.FileAttribute.TIME_MODIFIED,
                                            GLib.FileQueryInfoFlags.NONE);
                    var mtime = info.get_modification_date_time();
                    if (mtime != null) date_str = format_recent_date(mtime);
                } catch {}

                var row = new Button();
                row.has_frame = false;
                row.add_css_class("write-recent-row");

                var row_box = new Box(Orientation.HORIZONTAL, 12);
                row_box.margin_top = 8; row_box.margin_bottom = 8;
                row_box.margin_start = 12; row_box.margin_end = 12;

                var row_icon = new Image.from_icon_name(
                    is_md ? "text-x-generic-symbolic" : "x-office-document-symbolic");
                row_icon.pixel_size = 20;

                var row_text = new Box(Orientation.VERTICAL, 2);
                row_text.hexpand = true;
                var row_name = new Label(fname);
                row_name.halign = Align.START;
                row_name.ellipsize = Pango.EllipsizeMode.END;
                var row_path = new Label(fpath);
                row_path.halign = Align.START;
                row_path.add_css_class("dim-label");
                row_path.add_css_class("caption");
                row_path.ellipsize = Pango.EllipsizeMode.MIDDLE;

                var row_date = new Label(date_str);
                row_date.add_css_class("dim-label");
                row_date.add_css_class("caption");
                row_date.valign = Align.CENTER;

                row_text.append(row_name);
                row_text.append(row_path);
                row_box.append(row_icon);
                row_box.append(row_text);
                row_box.append(row_date);
                row.set_child(row_box);

                string captured_uri = uri;
                row.clicked.connect(() => {
                    do_open(GLib.File.new_for_uri(captured_uri));
                });
                list.append(row);
            }

            if (shown == 0) {
                var empty = new Label("No recent documents");
                empty.add_css_class("dim-label");
                empty.margin_top = 16;
                list.append(empty);
            }
        }

        private string format_recent_date(GLib.DateTime dt) {
            var now = new GLib.DateTime.now_local();
            var diff = now.difference(dt);
            if (diff < GLib.TimeSpan.DAY)        return "Today";
            if (diff < 2 * GLib.TimeSpan.DAY)    return "Yesterday";
            if (diff < 7 * GLib.TimeSpan.DAY)    return dt.format("%A");
            return dt.format("%d %b %Y");
        }

        private void show_start_page() {
            main_window.flat = true;
            toolbar.visible = false;
            toolbar.is_static = false;
            page_canvas.show_ruler(false);
            if (_recent_list_box != null)
                refresh_recent_list(_recent_list_box);
            _layout_stack.visible_child_name = "start";
        }

        private void setup_text_context_menu() {
            var click = new GestureClick();
            click.button = 3;
            click.pressed.connect((n, x, y) => {
                var menu = new Singularity.Widgets.ContextMenu(text_view);
                menu.add_item("Cut",   "edit-cut-symbolic",   () => Signal.emit_by_name(text_view, "cut-clipboard"));
                menu.add_item("Copy",  "edit-copy-symbolic",  () => Signal.emit_by_name(text_view, "copy-clipboard"));
                menu.add_item("Paste", "edit-paste-symbolic", () => Signal.emit_by_name(text_view, "paste-clipboard"));
                menu.add_separator();
                menu.add_item("Insert Table…",    "x-office-spreadsheet-symbolic", on_insert_table);
                menu.add_item("Insert Image…",    "insert-image-symbolic",         on_insert_image);
                menu.add_item("Insert Footnote",  "format-indent-more-symbolic",   on_insert_footnote);
                var rect = Gdk.Rectangle() { x = (int)x, y = (int)y, width = 1, height = 1 };
                menu.set_pointing_to(rect);
                menu.popup();
            });
            text_view.add_controller(click);
        }

        private void setup_keyboard() {
            // Global shortcuts on main_window
            var kc = new EventControllerKey();
            kc.key_pressed.connect((kv, kc2, state) => {
                bool ctrl  = (state & ModifierType.CONTROL_MASK) != 0;
                bool shift = (state & ModifierType.SHIFT_MASK)   != 0;
                if (ctrl) {
                    // Ctrl+Shift+Space, non-breaking space
                    if (kv == Key.space && shift) {
                        Gtk.TextIter cur;
                        text_buffer.get_iter_at_mark(out cur, text_buffer.get_insert());
                        text_buffer.begin_user_action();
                        text_buffer.insert(ref cur, "\u00A0", -1);
                        text_buffer.end_user_action();
                        return true;
                    }
                    switch (kv) {
                        case Key.z:
                            if (shift) text_buffer.redo(); else text_buffer.undo();
                            return true;
                        case Key.y: text_buffer.redo(); return true;
                        case Key.Return: {
                            Gtk.TextIter cur;
                            text_buffer.get_iter_at_mark(out cur, text_buffer.get_insert());
                            text_buffer.begin_user_action();
                            text_buffer.insert(ref cur, "\f", -1);
                            text_buffer.end_user_action();
                            return true;
                        }
                        case Key.b: apply_inline("bold");          return true;
                        case Key.i: apply_inline("italic");        return true;
                        case Key.u: apply_inline("underline");     return true;
                        case Key.a:
                            text_view.select_all(true);
                            text_view.grab_focus();
                            return true;
                        case Key.s: on_save();                     return true;
                        case Key.n: on_new();                      return true;
                        case Key.o: on_open();                     return true;
                        case Key.f: find_bar.open_find();          return true;
                        case Key.h: find_bar.open_replace();       return true;
                    }
                }
                if (kv == Key.F3) {
                    if (shift) {
                        if (_last_search_query != "") do_find_backward(_last_search_query);
                        else find_bar.open_find();
                    } else {
                        if (_last_search_query != "") do_find_forward(_last_search_query);
                        else find_bar.open_find();
                    }
                    return true;
                }
                if (kv == Key.Escape) {
                    if (find_bar.reveal_child) {
                        find_bar.reveal_child = false;
                        text_view.grab_focus();
                        return true;
                    }
                }
                return false;
            });
            ((Gtk.Widget)main_window).add_controller(kc);

            // Text-view capture handler (intercepts before GTK default)
            var tv_kc = new EventControllerKey();
            tv_kc.propagation_phase = PropagationPhase.CAPTURE;
            tv_kc.key_pressed.connect((kv, kc2, state) => {
                bool ctrl  = (state & ModifierType.CONTROL_MASK) != 0;
                bool shift = (state & ModifierType.SHIFT_MASK)   != 0;

                // Ctrl+Backspace / Ctrl+Delete – word deletion
                if (ctrl && kv == Key.BackSpace) { delete_word_backward(); return true; }
                if (ctrl && kv == Key.Delete)    { delete_word_forward();  return true; }

                // Smart Home
                if (!ctrl && kv == Key.Home) return handle_smart_home(shift);

                // Smart Enter
                if (!ctrl && !shift && (kv == Key.Return || kv == Key.KP_Enter))
                    return handle_enter();

                // Auto-format trigger on Space
                if (!ctrl && !shift && kv == Key.space)
                    if (try_auto_format_line()) return true;

                // Smart quotes
                if (!ctrl && !shift && _smart_quotes_on) {
                    if (kv == Key.quotedbl)   return handle_smart_quote('"');
                    if (kv == Key.apostrophe) return handle_smart_quote('\'');
                }

                // Reset smart-home tracker on any non-Home key
                if (kv != Key.Home) _last_home_line = -1;
                return false;
            });
            text_view.add_controller(tv_kc);
        }

        private void setup_autosave() {
            int interval = settings.get_int("autosave-interval");
            if (interval > 0) {
                autosave_id = GLib.Timeout.add_seconds(interval, () => {
                    if (modified && current_file != null) do_save(current_file);
                    return GLib.Source.CONTINUE;
                });
            }
        }

        // Markdown mode setup

        private void setup_markdown_mode() {
            if (_md_ui_built) return;
            _md_ui_built = true;

            // GtkSource buffer with Markdown language for syntax highlighting
            var lm = GtkSource.LanguageManager.get_default();
            var lang = lm.get_language("markdown");
            _md_buffer = new GtkSource.Buffer.with_language(lang);
            _md_buffer.changed.connect(on_md_source_changed);
            update_md_color_scheme();

            _md_source_view   = make_md_sourceview();   // R page view
            _md_source_view_s = make_md_sourceview();   // S page view (same buffer)
            var s_view        = _md_source_view_s;

            // Two separate WebViews - GTK4 widgets can only have one parent
            _md_preview_s = make_md_webview();
            _md_preview_v = make_md_webview();

            // R page: full-bleed editor (internal top padding pushes content
            // below the floating toolbar, no external spacer).
            var r_scroll = new ScrolledWindow();
            r_scroll.hexpand = true; r_scroll.vexpand = true;
            r_scroll.set_child(_md_source_view);

            // S page: paned source | preview
            var md_paned = new Gtk.Paned(Orientation.HORIZONTAL);
            md_paned.hexpand = true; md_paned.vexpand = true;
            md_paned.wide_handle = false;
            var s_source_scroll = new ScrolledWindow();
            s_source_scroll.hexpand = true; s_source_scroll.vexpand = true;
            s_source_scroll.set_child(s_view);
            md_paned.set_start_child(s_source_scroll);
            md_paned.set_end_child(_md_preview_s);
            md_paned.position = 480;

            // V page: preview only
            var v_box = new Box(Orientation.VERTICAL, 0);
            v_box.hexpand = true; v_box.vexpand = true;
            v_box.append(_md_preview_v);

            // Mode stack
            _md_stack = new Gtk.Stack();
            _md_stack.transition_type = Gtk.StackTransitionType.NONE;
            _md_stack.hexpand = true; _md_stack.vexpand = true;
            _md_stack.add_titled(r_scroll,  "R", "R");
            _md_stack.add_titled(md_paned,  "S", "S");
            _md_stack.add_titled(v_box,     "V", "V");
            _md_stack.visible_child_name = "S";

            // Compact inline R/S/V switcher (fits toolbar height without bloat)
            _md_mode_switcher = build_md_switcher();

            _layout_stack.add_named(_md_stack, "markdown");
        }

        private GtkSource.View make_md_sourceview() {
            return new Singularity.Widgets.SourceView(_md_buffer);
        }

        private WebKit.WebView make_md_webview() {
            var wv = new WebKit.WebView();
            wv.hexpand = true;
            wv.vexpand = true;
            return wv;
        }

        private void update_md_color_scheme() {
            if (_md_buffer == null) return;
            string scheme_id = settings != null ? settings.get_string("md-color-scheme") : "classic";
            if (scheme_id == "") scheme_id = "classic";

            // Check if it's a TerminalThemes-style theme (auto, onedark, etc.)
            var sinty_theme = Singularity.Core.TerminalThemes.get_by_id(scheme_id);
            if (sinty_theme != null) {
                var xml = Singularity.Core.TerminalThemes.get_source_scheme_xml(sinty_theme.id);
                if (xml != null) {
                    try {
                        var sm = GtkSource.StyleSchemeManager.get_default();
                        sm.append_search_path(GLib.Path.build_filename(
                            GLib.Environment.get_user_cache_dir(), "singularity", "schemes"));
                        var cache_dir = GLib.Path.build_filename(
                            GLib.Environment.get_user_cache_dir(), "singularity", "schemes");
                        DirUtils.create_with_parents(cache_dir, 0755);
                        var scheme_path = GLib.Path.build_filename(cache_dir, scheme_id + ".xml");
                        FileUtils.set_contents(scheme_path, xml);
                        var custom_dir = GLib.Path.build_filename(
                            GLib.Environment.get_user_data_dir(), "gtksourceview-5", "styles");
                        DirUtils.create_with_parents(custom_dir, 0755);
                        sm.force_rescan();
                        var scheme = sm.get_scheme(scheme_id);
                        if (scheme != null) {
                            _md_buffer.style_scheme = scheme;
                            return;
                        }
                    } catch (Error e) {
                        warning("WriteApp: failed to apply theme %s: %s", scheme_id, e.message);
                    }
                }
            }

            var sm = GtkSource.StyleSchemeManager.get_default();
            var scheme = sm.get_scheme(scheme_id);
            if (scheme == null) scheme = sm.get_scheme("classic");
            if (scheme != null) _md_buffer.style_scheme = scheme;
        }

        private Widget build_md_switcher() {
            var ctrl = new Singularity.Widgets.SegmentedControl(_md_stack);

            _md_stack.notify["visible-child-name"].connect(() => {
                string cur = _md_stack.visible_child_name;
                if (cur == "R" || cur == "S") {
                    GLib.Idle.add(() => {
                        _md_source_view?.grab_focus();
                        return GLib.Source.REMOVE;
                    });
                }
            });
            return ctrl;
        }

        private void enter_markdown_mode() {
            setup_markdown_mode();
            _layout_stack.visible_child_name = "markdown";
            toolbar.set_title_widget(_md_mode_switcher);
            _md_mode_switcher.halign = Align.CENTER;
            GLib.Idle.add(() => { update_outline(); return GLib.Source.REMOVE; });
        }

        private void exit_markdown_mode() {
            _layout_stack.visible_child_name = "odt";
            toolbar.set_title_widget(_font_title_box);
        }

        private Gtk.Box? _font_title_box;

        private void on_md_source_changed() {
            mark_modified();
            update_word_count();
            if (_md_update_timer != 0) {
                GLib.Source.remove(_md_update_timer);
                _md_update_timer = 0;
            }
            _md_update_timer = GLib.Timeout.add(400, () => {
                _md_update_timer = 0;
                update_md_preview();
                update_outline();
                return GLib.Source.REMOVE;
            });
        }

        private void update_md_preview() {
            if (_md_preview_s == null && _md_preview_v == null) return;
            string md_text = _md_buffer.text;
            var parser = new Markdown.Parser();
            string html = parser.to_full_html(md_text);
            if (_md_preview_s != null) _md_preview_s.load_html(html, null);
            if (_md_preview_v != null) _md_preview_v.load_html(html, null);
        }

        // Buffer signals

        private void on_buffer_changed() {
            mark_modified();
            update_word_count();
            GLib.Idle.add(() => { update_outline(); return GLib.Source.REMOVE; });
            if (!_auto_format_lock) {
                _auto_format_lock = true;
                do_autocorrect();
                _auto_format_lock = false;
            }
        }

        private void on_mark_set(Gtk.TextIter loc, Gtk.TextMark mark) {
            if (mark != text_buffer.get_insert()) return;
            if (_format_bar_updating) return;
            // Don't show format bar when the find bar (or anything other than
            // the text view / an already-visible format bar) has keyboard focus.
            if (!text_view.has_focus && !format_bar.visible) return;
            _format_bar_updating = true;
            GLib.Idle.add(() => {
                update_format_bar();
                update_style_chooser();
                _format_bar_updating = false;
                return GLib.Source.REMOVE;
            });
        }

        private void update_format_bar() {
            Gtk.TextIter s, e;
            if (!text_buffer.get_selection_bounds(out s, out e)) {
                format_bar.popdown();
                return;
            }
            Gdk.Rectangle iter_rect;
            text_view.get_iter_location(s, out iter_rect);
            Gdk.Rectangle vis;
            text_view.get_visible_rect(out vis);
            // Convert from buffer coords, text_view widget coords
            int wx = iter_rect.x - vis.x;
            int wy = iter_rect.y - vis.y;
            // Translate from text_view widget coords, doc_scroll coords
            double px, py;
            text_view.translate_coordinates(doc_scroll, wx, wy, out px, out py);

            _updating_sel = true;
            format_bar.set_format_state("bold",          s.has_tag(tag_bold));
            format_bar.set_format_state("italic",        s.has_tag(tag_italic));
            format_bar.set_format_state("underline",     s.has_tag(tag_underline));
            format_bar.set_format_state("strikethrough", s.has_tag(tag_strike));
            format_bar.set_alignment(text_view.get_justification());
            _updating_sel = false;

            var rect = Gdk.Rectangle() {
                x = (int)px, y = (int)py,
                width = iter_rect.width > 0 ? iter_rect.width : 1,
                height = iter_rect.height
            };
            format_bar.show_at_rect(rect);
            // Return focus to text_view - GTK4 Popover.popup() grabs focus by
            // default; the Idle ensures it runs after GTK has processed the popup.
            GLib.Idle.add(() => { text_view.grab_focus(); return GLib.Source.REMOVE; });
        }

        private void update_style_chooser() {
            Gtk.TextIter it;
            text_buffer.get_iter_at_mark(out it, text_buffer.get_insert());
            if      (it.has_tag(tag_h1))    style_chooser.set_current_style("h1");
            else if (it.has_tag(tag_h2))    style_chooser.set_current_style("h2");
            else if (it.has_tag(tag_h3))    style_chooser.set_current_style("h3");
            else if (it.has_tag(tag_h4))    style_chooser.set_current_style("h4");
            else if (it.has_tag(tag_quote)) style_chooser.set_current_style("quote");
            else if (it.has_tag(tag_code))  style_chooser.set_current_style("code");
            else                             style_chooser.set_current_style("body");
            // Update font family/size controls
            update_font_controls(it);
        }

        private void update_font_controls(Gtk.TextIter it) {
            if (_font_entry == null || _size_spin == null) return;
            _font_ctrl_updating = true;
            string? family = null;
            double size_pt = 12.0;
            // Walk tags at cursor to find a font tag
            var tags = it.get_tags();
            foreach (var tag in tags) {
                if (tag.family_set) family = tag.family;
                if (tag.size_set) size_pt = tag.size_points;
            }
            if (family != null) _font_entry.text = family;
            else _font_entry.text = "";
            _size_spin.value = size_pt > 0 ? size_pt : 12.0;
            _font_ctrl_updating = false;
        }

        private void update_word_count() {
            string txt = _is_markdown ? _md_buffer.text : text_buffer.text;
            if (txt.strip() == "") { word_count_label.label = "0 words"; return; }
            int cnt = 0;
            foreach (var w in txt.split_set(" \t\n\r"))
                if (w.strip() != "") cnt++;
            word_count_label.label = "%d word%s".printf(cnt, cnt == 1 ? "" : "s");
        }

        private void update_outline() {
            while (outline_box.get_first_child() != null)
                outline_box.remove(outline_box.get_first_child());

            if (_is_markdown) {
                // Parse # / ## / ### headings from the MD buffer
                string[] lines = _md_buffer.text.split("\n");
                foreach (string raw in lines) {
                    string line = raw.strip();
                    int level = 0;
                    if      (line.has_prefix("#### ")) { level = 4; line = line.substring(5); }
                    else if (line.has_prefix("### "))  { level = 3; line = line.substring(4); }
                    else if (line.has_prefix("## "))   { level = 2; line = line.substring(3); }
                    else if (line.has_prefix("# "))    { level = 1; line = line.substring(2); }
                    if (level == 0) continue;
                    line = line.strip();
                    if (line == "") continue;
                    int indent = (level - 1) * 12;
                    var row_lbl = new Label(line);
                    row_lbl.xalign = 0;
                    row_lbl.halign = Align.START;
                    row_lbl.ellipsize = Pango.EllipsizeMode.END;
                    var row = new Button();
                    row.set_child(row_lbl);
                    row.has_frame = false;
                    row.halign = Align.FILL;
                    row.add_css_class("write-outline-row");
                    row.add_css_class("write-outline-h%d".printf(level));
                    row.margin_start = indent;
                    outline_box.append(row);
                }
                return;
            }

            Gtk.TextIter it;
            text_buffer.get_start_iter(out it);

            while (!it.is_end()) {
                Gtk.TextTag? ht = null;
                string hid = "";
                int indent = 0;
                if      (it.has_tag(tag_h1)) { ht = tag_h1; hid = "h1"; indent = 0; }
                else if (it.has_tag(tag_h2)) { ht = tag_h2; hid = "h2"; indent = 12; }
                else if (it.has_tag(tag_h3)) { ht = tag_h3; hid = "h3"; indent = 22; }
                else if (it.has_tag(tag_h4)) { ht = tag_h4; hid = "h4"; indent = 30; }

                if (ht != null) {
                    Gtk.TextIter end = it;
                    end.forward_to_tag_toggle(ht);
                    string txt = text_buffer.get_text(it, end, false).strip();
                    if (txt != "") {
                        var row_lbl = new Label(txt);
                        row_lbl.xalign = 0;
                        row_lbl.halign = Align.START;
                        var row = new Button();
                        row.set_child(row_lbl);
                        row.has_frame = false;
                        row.halign = Align.FILL;
                        row.add_css_class("write-outline-row");
                        row.add_css_class("write-outline-" + hid);
                        row.margin_start = indent;
                        Gtk.TextIter snap = it;
                        row.clicked.connect(() => {
                            text_buffer.place_cursor(snap);
                            text_view.scroll_to_mark(text_buffer.get_insert(), 0.1, true, 0, 0.3);
                        });
                        outline_box.append(row);
                    }
                    it = end;
                } else {
                    it.forward_char();
                }
            }
        }

        // Formatting

        private void apply_inline(string tag_name) {
            Gtk.TextIter s, e;
            if (!text_buffer.get_selection_bounds(out s, out e)) return;
            var tag = text_buffer.tag_table.lookup(tag_name);
            if (tag == null) return;

            bool all = true;
            Gtk.TextIter c = s;
            while (c.compare(e) < 0) {
                if (!c.has_tag(tag)) { all = false; break; }
                c.forward_char();
            }
            text_buffer.begin_user_action();
            if (all) text_buffer.remove_tag(tag, s, e);
            else     text_buffer.apply_tag(tag, s, e);
            text_buffer.end_user_action();
        }

        private void apply_para_style(string style_id) {
            Gtk.TextIter s, e;
            bool has_sel = text_buffer.get_selection_bounds(out s, out e);
            if (!has_sel) {
                text_buffer.get_iter_at_mark(out s, text_buffer.get_insert());
                e = s;
            }
            s.set_line_offset(0);
            if (!e.ends_line()) e.forward_to_line_end();

            Gtk.TextTag[] style_tags = { tag_h1, tag_h2, tag_h3, tag_h4, tag_body,
                                          tag_quote, tag_code, tag_bullet, tag_numbered };

            if (style_id == "bullet" || style_id == "numbered") {
                apply_list_style(style_id == "bullet");
                return;
            }

            text_buffer.begin_user_action();
            // Strip any list prefixes first
            strip_list_prefixes(s, e);
            // Re-fetch iters after text mutation
            text_buffer.get_selection_bounds(out s, out e);
            s.set_line_offset(0);
            if (!e.ends_line()) e.forward_to_line_end();
            foreach (var t in style_tags) text_buffer.remove_tag(t, s, e);
            var nt = text_buffer.tag_table.lookup(style_id);
            if (nt != null) text_buffer.apply_tag(nt, s, e);
            text_buffer.end_user_action();
        }

        // Strip "• " or "N. " prefixes from each line in [s, e]

        private void strip_list_prefixes(Gtk.TextIter s, Gtk.TextIter e) {
            int start_line = s.get_line();
            int end_line   = e.get_line();
            // Walk lines in reverse to keep iters valid
            for (int ln = end_line; ln >= start_line; ln--) {
                Gtk.TextIter line_start;
                text_buffer.get_iter_at_line(out line_start, ln);
                Gtk.TextIter line_end = line_start;
                line_end.forward_to_line_end();
                string line = text_buffer.get_text(line_start, line_end, false);
                // Match "• " (bullet) or "N. " (numbered)
                if (line.has_prefix("• ")) {
                    var del_end = line_start;
                    del_end.forward_chars(2); // "• " is 2 Vala chars but "•" is 3 bytes
                    // Forward by the byte-length-aware char count
                    Gtk.TextIter del_s = line_start;
                    del_s.forward_chars(0);
                    // Use byte-safe deletion: delete "• " = bullet(3 bytes) + space(1 byte)
                    var mark = text_buffer.get_insert();
                    Gtk.TextIter bs = line_start;
                    Gtk.TextIter be = line_start;
                    be.forward_chars(2); // GTK iter counts Unicode chars
                    text_buffer.delete(ref bs, ref be);
                } else {
                    // Match "N. " pattern
                    var re = new GLib.Regex("^\\d+\\.\\s");
                    GLib.MatchInfo mi;
                    if (re.match(line, 0, out mi)) {
                        string matched = mi.fetch(0);
                        Gtk.TextIter bs = line_start;
                        Gtk.TextIter be = line_start;
                        be.forward_chars(matched.char_count());
                        text_buffer.delete(ref bs, ref be);
                    }
                }
            }
        }

        private void apply_list_style(bool is_bullet) {
            Gtk.TextIter s, e;
            bool has_sel = text_buffer.get_selection_bounds(out s, out e);
            if (!has_sel) {
                text_buffer.get_iter_at_mark(out s, text_buffer.get_insert());
                e = s;
            }
            int start_line = s.get_line();
            int end_line   = e.get_line();

            text_buffer.begin_user_action();
            // Strip existing list prefixes first
            Gtk.TextIter rs = s, re = e;
            strip_list_prefixes(rs, re);

            // Re-fetch range
            text_buffer.get_iter_at_line(out s, start_line);
            text_buffer.get_iter_at_line(out e, end_line);
            if (!e.ends_line()) e.forward_to_line_end();

            // Remove all para style tags
            Gtk.TextTag[] style_tags = { tag_h1, tag_h2, tag_h3, tag_h4, tag_body,
                                          tag_quote, tag_code, tag_bullet, tag_numbered };
            foreach (var t in style_tags) text_buffer.remove_tag(t, s, e);

            // Insert prefixes per line (forward order)
            int line_count = end_line - start_line + 1;
            for (int i = 0; i < line_count; i++) {
                int ln = start_line + i;
                Gtk.TextIter ins;
                text_buffer.get_iter_at_line(out ins, ln);
                string prefix = is_bullet ? "• " : "%d. ".printf(i + 1);
                text_buffer.insert(ref ins, prefix, -1);
            }

            // Re-fetch range to apply tag
            text_buffer.get_iter_at_line(out s, start_line);
            text_buffer.get_iter_at_line(out e, end_line);
            if (!e.ends_line()) e.forward_to_line_end();
            var list_tag = is_bullet ? tag_bullet : tag_numbered;
            text_buffer.apply_tag(list_tag, s, e);
            text_buffer.end_user_action();
        }

        private void on_style_selected(string id, string name) {
            apply_para_style(id);
            text_view.grab_focus();
        }

        private void on_format_toggled(string fmt, bool active) {
            if (_updating_sel) return;
            apply_inline(fmt);
        }

        private void on_color_changed(string kind, RGBA color) {
            Gtk.TextIter s, e;
            if (!text_buffer.get_selection_bounds(out s, out e)) return;
            string hex = "#%02x%02x%02x".printf(
                (int)(color.red * 255), (int)(color.green * 255), (int)(color.blue * 255));
            string tname = (kind == "text" ? "fg-" : "bg-") + hex;
            var tag = text_buffer.tag_table.lookup(tname);
            if (tag == null) {
                if (kind == "text") tag = text_buffer.create_tag(tname, "foreground", hex);
                else                tag = text_buffer.create_tag(tname, "background", hex);
            }
            text_buffer.begin_user_action();
            text_buffer.apply_tag(tag, s, e);
            text_buffer.end_user_action();
        }

        private void apply_font_desc(Pango.FontDescription desc) {
            Gtk.TextIter s, e;
            if (!text_buffer.get_selection_bounds(out s, out e)) return;
            
            string family = desc.get_family();
            int size = desc.get_size();
            bool is_absolute = desc.get_size_is_absolute();
            
            string tname = "font-" + family + "-" + size.to_string();
            var tag = text_buffer.tag_table.lookup(tname);
            if (tag == null) {
                tag = text_buffer.create_tag(tname);
                tag.family = family;
                if (is_absolute) tag.size = size;
                else tag.size_points = (double)size / Pango.SCALE;
            }
            
            text_buffer.begin_user_action();
            text_buffer.apply_tag(tag, s, e);
            text_buffer.end_user_action();
        }

        private void on_link_requested() {
            Gtk.TextIter s, e;
            if (!text_buffer.get_selection_bounds(out s, out e)) return;

            var dialog = new Singularity.Widgets.AppDialog((Gtk.Application)this, true);
            dialog.set_title("Insert Link");
            dialog.transient_for = main_window;
            dialog.set_default_size(360, 130);

            var box = new Box(Orientation.VERTICAL, 8);
            box.margin_start = 16; box.margin_end = 16;
            box.margin_top = 10;  box.margin_bottom = 12;

            var url = new Entry();
            url.placeholder_text = "https://…";
            url.hexpand = true;

            var btns = new Box(Orientation.HORIZONTAL, 8);
            btns.halign = Align.END;
            var ok = new Button.with_label("Insert");
            ok.add_css_class("suggested-action");
            var cancel = new Button.with_label("Cancel");
            cancel.clicked.connect(() => dialog.close());
            ok.clicked.connect(() => {
                if (url.text.strip() != "")
                    text_buffer.apply_tag(tag_link, s, e);
                dialog.close();
            });
            btns.append(cancel);
            btns.append(ok);
            box.append(new Label("URL:"));
            box.append(url);
            box.append(btns);
            dialog.content_box.append(box);
            dialog.present();
            url.grab_focus();
        }

        // Insert objects

        private void on_insert_table() {
            var dialog = new Singularity.Widgets.AppDialog((Gtk.Application)this, true);
            dialog.set_title("Insert Table");
            dialog.transient_for = main_window;
            dialog.set_default_size(260, 155);

            var grid = new Grid();
            grid.column_spacing = 12; grid.row_spacing = 8;
            grid.margin_start = 16; grid.margin_end = 16;
            grid.margin_top = 12;   grid.margin_bottom = 12;

            var rows_spin = new SpinButton.with_range(1, 30, 1);
            rows_spin.value = 3;
            var cols_spin = new SpinButton.with_range(1, 12, 1);
            cols_spin.value = 3;

            grid.attach(new Label("Rows:"),    0, 0); grid.attach(rows_spin, 1, 0);
            grid.attach(new Label("Columns:"), 0, 1); grid.attach(cols_spin, 1, 1);

            var btns = new Box(Orientation.HORIZONTAL, 8);
            btns.halign = Align.END;
            var cancel = new Button.with_label("Cancel");
            cancel.clicked.connect(() => dialog.close());
            var insert = new Button.with_label("Insert");
            insert.add_css_class("suggested-action");
            insert.clicked.connect(() => {
                int r = (int)rows_spin.value;
                int c = (int)cols_spin.value;
                dialog.close();
                do_insert_table(r, c);
            });
            btns.append(cancel);
            btns.append(insert);
            grid.attach(btns, 0, 2, 2, 1);

            dialog.content_box.append(grid);
            dialog.present();
        }

        private void do_insert_table(int rows, int cols) {
            Gtk.TextIter cursor;
            text_buffer.get_iter_at_mark(out cursor, text_buffer.get_insert());
            if (!cursor.starts_line()) {
                text_buffer.insert(ref cursor, "\n", -1);
                text_buffer.get_iter_at_mark(out cursor, text_buffer.get_insert());
            }
            var anchor = text_buffer.create_child_anchor(cursor);
            text_buffer.insert(ref cursor, "\n", -1);

            var tbl = new Grid();
            tbl.add_css_class("write-table");
            tbl.column_homogeneous = true;
            tbl.row_spacing = 0; tbl.column_spacing = 0;
            for (int r = 0; r < rows; r++) {
                for (int c = 0; c < cols; c++) {
                    var cell = new Gtk.TextView();
                    cell.wrap_mode = WrapMode.WORD_CHAR;
                    cell.add_css_class("write-table-cell");
                    if (r == 0) cell.add_css_class("write-table-header");
                    cell.set_size_request(90, 32);
                    tbl.attach(cell, c, r, 1, 1);
                }
            }
            text_view.add_child_at_anchor(tbl, anchor);
            tbl.show();
        }

        private void on_insert_image() {
            var fd = new FileDialog();
            fd.title = "Insert Image";
            var filter = new FileFilter();
            filter.name = "Images";
            filter.add_mime_type("image/png");
            filter.add_mime_type("image/jpeg");
            filter.add_mime_type("image/webp");
            filter.add_mime_type("image/gif");
            filter.add_mime_type("image/svg+xml");
            var flist = new GLib.ListStore(typeof(FileFilter));
            flist.append(filter);
            fd.filters = flist;
            fd.open.begin(main_window, null, (o, r) => {
                try { do_insert_image(fd.open.end(r)); } catch {}
            });
        }

        private void do_insert_image(GLib.File file) {
            Gtk.TextIter cursor;
            text_buffer.get_iter_at_mark(out cursor, text_buffer.get_insert());
            if (!cursor.starts_line()) {
                text_buffer.insert(ref cursor, "\n", -1);
                text_buffer.get_iter_at_mark(out cursor, text_buffer.get_insert());
            }
            var anchor = text_buffer.create_child_anchor(cursor);
            text_buffer.insert(ref cursor, "\n", -1);

            var pic = new Gtk.Picture.for_file(file);
            pic.add_css_class("write-image");
            pic.content_fit = ContentFit.SCALE_DOWN;
            pic.set_size_request(400, -1);
            text_view.add_child_at_anchor(pic, anchor);
            pic.show();
        }

        private void on_insert_footnote() {
            footnote_num++;
            int fn = footnote_num;
            Gtk.TextIter cursor;
            text_buffer.get_iter_at_mark(out cursor, text_buffer.get_insert());
            var anchor = text_buffer.create_child_anchor(cursor);

            var btn = new Button.with_label("[%d]".printf(fn));
            btn.has_frame = false;
            btn.add_css_class("write-footnote-anchor");
            btn.tooltip_text = "Footnote %d - click to edit".printf(fn);

            var pop = new Popover();
            pop.set_parent(btn);
            var fn_box = new Box(Orientation.VERTICAL, 8);
            fn_box.margin_start = 10; fn_box.margin_end = 10;
            fn_box.margin_top = 8;    fn_box.margin_bottom = 8;
            fn_box.append(new Label("Footnote %d".printf(fn)));
            var fn_tv = new Gtk.TextView();
            fn_tv.wrap_mode = WrapMode.WORD_CHAR;
            fn_tv.set_size_request(280, 72);
            fn_tv.add_css_class("write-footnote-editor");
            var fn_scroll = new ScrolledWindow();
            fn_scroll.set_child(fn_tv);
            fn_scroll.set_size_request(280, 72);
            fn_box.append(fn_scroll);
            pop.set_child(fn_box);
            btn.clicked.connect(() => pop.popup());

            text_view.add_child_at_anchor(btn, anchor);
            btn.show();
        }

        // Find & Replace

        private void do_find_forward(string q) { _last_search_query = q; do_find(q, true); }
        private void do_find_backward(string q) { _last_search_query = q; do_find(q, false); }

        private Gtk.TextBuffer active_buffer() {
            return _is_markdown && _md_ui_built ? (Gtk.TextBuffer) _md_buffer : (Gtk.TextBuffer) text_buffer;
        }
        private Gtk.TextView active_view() {
            if (!_is_markdown || !_md_ui_built) return text_view;
            if (_md_stack != null && _md_stack.visible_child_name == "S" && _md_source_view_s != null)
                return _md_source_view_s;
            return _md_source_view;
        }

        private void do_find(string q, bool fwd) {
            if (q == "") return;
            var buf  = active_buffer();
            var view = active_view();
            Gtk.TextIter start, ms, me;
            buf.get_iter_at_mark(out start, buf.get_insert());
            if (fwd) start.forward_char(); else start.backward_char();
            bool found;
            var flags = Gtk.TextSearchFlags.CASE_INSENSITIVE | Gtk.TextSearchFlags.TEXT_ONLY;
            if (fwd) {
                found = start.forward_search(q, flags, out ms, out me, null);
                if (!found) {
                    buf.get_start_iter(out start);
                    found = start.forward_search(q, flags, out ms, out me, null);
                }
            } else {
                found = start.backward_search(q, flags, out ms, out me, null);
                if (!found) {
                    buf.get_end_iter(out start);
                    found = start.backward_search(q, flags, out ms, out me, null);
                }
            }
            if (found) {
                buf.select_range(ms, me);
                view.scroll_to_mark(buf.get_insert(), 0.1, true, 0, 0.5);
            }
            count_matches(q);
        }

        private void count_matches(string q) {
            if (q == "") { find_bar.set_match_info(0, 0); return; }
            var buf = active_buffer();
            Gtk.TextIter it, ms, me, cursor;
            buf.get_start_iter(out it);
            buf.get_iter_at_mark(out cursor, buf.get_insert());
            int total = 0, cur = 0;
            var flags = Gtk.TextSearchFlags.CASE_INSENSITIVE | Gtk.TextSearchFlags.TEXT_ONLY;
            while (it.forward_search(q, flags, out ms, out me, null)) {
                total++;
                if (ms.compare(cursor) <= 0) cur = total;
                it = me;
            }
            find_bar.set_match_info(cur, total);
        }

        private void do_replace_one(string q, string rep) {
            var buf = active_buffer();
            Gtk.TextIter s, e;
            if (buf.get_selection_bounds(out s, out e)) {
                string sel = buf.get_text(s, e, false);
                if (sel.casefold() == q.casefold()) {
                    buf.begin_user_action();
                    buf.delete(ref s, ref e);
                    buf.insert(ref s, rep, -1);
                    buf.end_user_action();
                }
            }
            do_find_forward(q);
        }

        private void do_replace_all(string q, string rep) {
            if (q == "") return;
            var buf = active_buffer();
            Gtk.TextIter it, ms, me;
            buf.get_start_iter(out it);
            var flags = Gtk.TextSearchFlags.CASE_INSENSITIVE | Gtk.TextSearchFlags.TEXT_ONLY;
            int cnt = 0;
            buf.begin_user_action();
            while (it.forward_search(q, flags, out ms, out me, null)) {
                buf.delete(ref ms, ref me);
                buf.insert(ref ms, rep, -1);
                it = ms;
                it.forward_chars(rep.length);
                cnt++;
            }
            buf.end_user_action();
            find_bar.set_match_info(cnt, 0);
        }

        // File operations

        private void mark_modified() {
            if (!modified) { modified = true; update_title(); }
        }

        private void update_title() {
            string n = current_file != null ? current_file.get_basename() : "Untitled";
            if (n.has_suffix(".odt")) n = n[0:n.length - 4];
            if (n.has_suffix(".md"))  n = n[0:n.length - 3];
            string full = modified ? n + " *" : n;
            toolbar.set_title(full);
            main_window.title = n;
        }

        private void new_document() {
            current_file = null;
            text_buffer.set_text("", 0);
            modified = false;
            main_window.flat = false;
            toolbar.visible = true;
            _layout_stack.visible_child_name = "odt";
            page_canvas.show_ruler(true);
            update_title();
            update_word_count();
            update_outline();
        }

        private void on_new() {
            new_document();
        }

        private void on_close_document() {
            if (!modified) {
                show_start_page();
                return;
            }
            var dlg = new Singularity.Widgets.AppDialog((Gtk.Application)this, true);
            dlg.set_title("Close Document?");
            dlg.transient_for = main_window;
            dlg.set_default_size(320, 140);
            var box = new Box(Orientation.VERTICAL, 8);
            box.margin_start = 16; box.margin_end = 16;
            box.margin_top = 10; box.margin_bottom = 12;
            var lbl = new Label("You have unsaved changes.\nThey will be lost if you close now.");
            lbl.wrap = true;
            lbl.xalign = 0f;
            var btns = new Box(Orientation.HORIZONTAL, 8);
            btns.halign = Align.END;
            var cancel_btn = new Button.with_label("Cancel");
            cancel_btn.clicked.connect(() => dlg.close());
            var close_btn2 = new Button.with_label("Close Without Saving");
            close_btn2.add_css_class("destructive-action");
            close_btn2.clicked.connect(() => {
                dlg.close();
                modified = false;
                show_start_page();
            });
            btns.append(cancel_btn);
            btns.append(close_btn2);
            box.append(lbl);
            box.append(btns);
            dlg.content_box.append(box);
            dlg.present();
        }

        private void on_open() { on_open_with_kind("all"); }

        private void on_open_with_kind(string kind) {
            var fd = new FileDialog();
            fd.title = (kind == "pdf") ? "Open PDF" : "Open Document";

            var filter_md = new FileFilter();
            filter_md.name = "Markdown Documents";
            filter_md.add_pattern("*.md");
            filter_md.add_pattern("*.markdown");

            var filter_pdf = new FileFilter();
            filter_pdf.name = "PDF Documents";
            filter_pdf.add_pattern("*.pdf");

            var filter_all = new FileFilter();
            filter_all.name = "All Supported";
            filter_all.add_pattern("*.md");
            filter_all.add_pattern("*.markdown");
            filter_all.add_pattern("*.pdf");

            var flist = new GLib.ListStore(typeof(FileFilter));
            if (kind == "md") {
                flist.append(filter_md);
            } else if (kind == "pdf") {
                flist.append(filter_pdf);
            } else {
                flist.append(filter_all);
                flist.append(filter_md);
                flist.append(filter_pdf);
            }
            fd.filters = flist;
            fd.open.begin(main_window, null, (o, r) => {
                try {
                    var file = fd.open.end(r);
                    if (file != null) do_open(file);
                } catch (Error e) {
                    warning("on_open: FileDialog.open failed: %s", e.message);
                }
            });
        }

        private void do_open(GLib.File file) {
            string path = file.get_path();
            if (path == null) return;
            string lp = path.down();
            if (lp.has_suffix(".pdf")) {
                do_open_pdf(file);
                return;
            }
            do_open_markdown(file);
        }

        // PDF viewer

        private Pdf.Viewer? _pdf_viewer = null;
        private Singularity.Widgets.HoverControls? _pdf_host = null;
        private bool _is_pdf = false;

        private void do_open_pdf(GLib.File file) {
            if (_is_markdown) {
                _is_markdown = false;
                exit_markdown_mode();
            }

            if (_pdf_viewer == null) {
                _pdf_viewer = new Pdf.Viewer();
                _pdf_host   = new Singularity.Widgets.HoverControls();
                _pdf_host.set_content(_pdf_viewer);

                var grip_btn = new Button();
                grip_btn.add_css_class("flat");
                grip_btn.set_size_request(28, 28);
                grip_btn.tooltip_text = "Drag Window";
                var grip_icon = new Image.from_icon_name("list-drag-handle-symbolic");
                grip_icon.pixel_size = 14;
                grip_btn.set_child(grip_icon);
                var grip_drag = new Gtk.GestureDrag();
                grip_drag.drag_begin.connect((x, y) => {
                    var win = (Gtk.Window) grip_btn.get_native();
                    if (win == null) return;
                    var surface = win.get_surface();
                    if (surface is Gdk.Toplevel) {
                        ((Gdk.Toplevel) surface).begin_move(
                            grip_drag.get_device(), 1, x, y, Gdk.CURRENT_TIME);
                    }
                });
                grip_btn.add_controller(grip_drag);
                _pdf_host.add_control(grip_btn);

                var close_btn = new Button.from_icon_name("window-close-symbolic");
                var back_btn = new Button.from_icon_name("go-previous-symbolic");
                back_btn.tooltip_text = "Back to start";
                back_btn.clicked.connect(() => {
                    exit_pdf_mode();
                    show_start_page();
                });
                _pdf_host.add_control(back_btn);

                close_btn.tooltip_text = "Close Window";
                close_btn.clicked.connect(() => {
                    main_window.close();
                });
                _pdf_host.add_control(close_btn);

                _layout_stack.add_named(_pdf_host, "pdf");
            }
            if (!_pdf_viewer.load(file.get_path())) {
                warning("do_open_pdf: load failed");
                return;
            }
            _is_pdf       = true;
            current_file  = file;
            add_to_recent(file);
            modified                = false;
            main_window.show_close  = false;
            main_window.flat        = true;
            toolbar.visible         = false;
            page_canvas.show_ruler(false);
            _layout_stack.visible_child_name = "pdf";
            update_title();
        }

        private void exit_pdf_mode() {
            _is_pdf                 = false;
            main_window.show_close  = true;
            toolbar.visible         = true;
            main_window.flat = false;
        }

        private void do_open_markdown(GLib.File file) {
            string contents = "";
            try {
                FileUtils.get_contents(file.get_path(), out contents);
            } catch (Error e) {
                warning("do_open_markdown: %s", e.message);
                return;
            }
            _is_markdown = true;
            enter_markdown_mode();
            _md_buffer.set_text(contents, -1);
            current_file = file;
            add_to_recent(file);
            modified = false;
            update_title();
            // Trigger initial preview render
            GLib.Idle.add(() => { update_md_preview(); return GLib.Source.REMOVE; });
        }

        private void on_save() {
            if (_is_pdf) return;
            if (current_file == null) on_save_as();
            else do_save(current_file);
        }

        private void on_save_as() {
            if (_is_pdf) return;
            var fd = new FileDialog();
            fd.title = "Save Document";
            fd.initial_name = _is_markdown ? "Untitled.md" : "Untitled.md";
            fd.save.begin(main_window, null, (o, r) => {
                try {
                    var file = fd.save.end(r);
                    string path = file.get_path();
                    if (_is_markdown) {
                        if (!path.has_suffix(".md")) path += ".md";
                    } else {
                        if (!path.has_suffix(".odt")) path += ".odt";
                    }
                    var f = GLib.File.new_for_path(path);
                    do_save(f);
                    current_file = f;
                    add_to_recent(f);
                    modified = false;
                    update_title();
                } catch {}
            });
        }

        private void do_save(GLib.File file) {
            if (_is_pdf) return;
            string md_text = _is_markdown ? _md_buffer.text : text_buffer.text;
            try {
                FileUtils.set_contents(file.get_path(), md_text);
                modified = false;
                update_title();
            } catch (Error e) {
                warning("do_save: %s", e.message);
            }
        }

        // Export / Print

        private void on_export() {
            if (_is_pdf) return;
            bool has_pandoc = GLib.Environment.find_program_in_path("pandoc") != null;

            // Show a simple export menu anchored under the export button.
            var pop = new Gtk.Popover();
            pop.has_arrow = true;
            pop.set_parent(_export_btn != null ? (Widget) _export_btn : (Widget) toolbar);

            var box = new Box(Orientation.VERTICAL, 2);
            box.margin_top = 4; box.margin_bottom = 4;
            box.margin_start = 4; box.margin_end = 4;

            void add_row(string icon, string label, bool sensitive, owned GLib.Func<Button> cb) {
                var row = new Button();
                row.has_frame = false;
                row.add_css_class("flat");
                row.sensitive = sensitive;
                var r_box = new Box(Orientation.HORIZONTAL, 10);
                r_box.margin_start = 4; r_box.margin_end = 8;
                r_box.margin_top = 4; r_box.margin_bottom = 4;
                var img = new Image.from_icon_name(icon);
                img.pixel_size = 16;
                var lbl = new Label(label);
                lbl.halign = Align.START;
                r_box.append(img);
                r_box.append(lbl);
                row.set_child(r_box);
                row.clicked.connect(() => { pop.popdown(); cb(row); });
                box.append(row);
            }

            add_row("document-send-symbolic", "Export as PDF" + (has_pandoc ? "" : " (print dialog)"), true, (b) => {
                if (has_pandoc) export_md_via_pandoc.begin();
                else export_via_print_dialog();
            });
            add_row("text-x-generic-symbolic", "Save copy as Markdown…", true, (b) => export_save_md_copy());
            add_row("printer-symbolic", "Print…", true, (b) => export_via_print_dialog());

            pop.set_child(box);
            pop.popup();
        }

        private void export_via_print_dialog() {
            var op = new Gtk.PrintOperation();
            op.n_pages = 1;
            op.draw_page.connect((ctx, page_nr) => {
                var cr = ctx.get_cairo_context();
                string content = _is_markdown ? _md_buffer.text : text_buffer.text;
                cr.set_source_rgb(0, 0, 0);
                cr.move_to(20, 20);
                var layout = Pango.cairo_create_layout(cr);
                layout.set_text(content, -1);
                layout.set_width((int)((ctx.get_width() - 40) * Pango.SCALE));
                layout.set_wrap(Pango.WrapMode.WORD_CHAR);
                Pango.cairo_show_layout(cr, layout);
            });
            try {
                op.run(Gtk.PrintOperationAction.PRINT_DIALOG, main_window);
            } catch (Error e) {
                warning("Print error: %s", e.message);
            }
        }

        private void export_save_odt_copy() {
            var fd = new FileDialog();
            fd.title = "Save ODT Copy";
            fd.initial_name = current_file != null
                ? GLib.Path.get_basename(current_file.get_path())
                : "Untitled.odt";
            fd.save.begin(main_window, null, (o, r) => {
                try {
                    var dest = fd.save.end(r);
                    var odt = new Odt.Document();
                    odt.save(dest.get_path(), text_buffer);
                } catch {}
            });
        }

        private void export_save_md_copy() {
            var fd = new FileDialog();
            fd.title = "Save Markdown Copy";
            fd.initial_name = current_file != null
                ? GLib.Path.get_basename(current_file.get_path())
                : "Untitled.md";
            fd.save.begin(main_window, null, (o, r) => {
                try {
                    var dest = fd.save.end(r);
                    FileUtils.set_contents(dest.get_path(), _md_buffer.text);
                } catch {}
            });
        }

        private async void export_odt_via_soffice() {
            // Save to temp ODT, convert to PDF with soffice
            string tmp_dir = GLib.DirUtils.make_tmp("singularity-write-XXXXXX");
            string tmp_odt = GLib.Path.build_filename(tmp_dir, "export.odt");
            var tmp_file = GLib.File.new_for_path(tmp_odt);
            var odt = new Odt.Document();
            if (!odt.save(tmp_odt, text_buffer)) {
                warning("Export: failed to save temporary ODT");
                GLib.DirUtils.remove(tmp_dir);
                return;
            }
            string converter = GLib.Environment.find_program_in_path("soffice") != null
                ? "soffice" : "libreoffice";
            try {
                var proc = new GLib.Subprocess.newv(
                    { converter, "--headless", "--convert-to", "pdf", "--outdir", tmp_dir, tmp_odt },
                    GLib.SubprocessFlags.NONE);
                yield proc.wait_async();
                string pdf_path = GLib.Path.build_filename(tmp_dir, "export.pdf");
                if (GLib.FileUtils.test(pdf_path, GLib.FileTest.EXISTS)) {
                    var fd = new FileDialog();
                    fd.title = "Save PDF As";
                    fd.initial_name = current_file != null
                        ? GLib.Path.get_basename(current_file.get_path()).replace(".odt", ".pdf")
                        : "Untitled.pdf";
                    fd.save.begin(main_window, null, (o, r) => {
                        try {
                            var dest = fd.save.end(r);
                            string dest_path = dest.get_path();
                            if (!dest_path.has_suffix(".pdf")) dest_path += ".pdf";
                            GLib.FileUtils.rename(pdf_path, dest_path);
                        } catch {}
                        try { GLib.DirUtils.remove(tmp_dir); } catch {}
                    });
                } else {
                    warning("Export: soffice did not produce PDF");
                }
            } catch (Error e) {
                warning("Export via soffice: %s", e.message);
            }
        }

        private async void export_md_via_pandoc() {
            // Save to temp MD, convert to PDF with pandoc
            string tmp_dir = GLib.DirUtils.make_tmp("singularity-write-XXXXXX");
            string tmp_md  = GLib.Path.build_filename(tmp_dir, "export.md");
            try {
                FileUtils.set_contents(tmp_md, _md_buffer.text);
                string tmp_pdf = GLib.Path.build_filename(tmp_dir, "export.pdf");
                var proc = new GLib.Subprocess.newv(
                    { "pandoc", tmp_md, "-o", tmp_pdf },
                    GLib.SubprocessFlags.NONE);
                yield proc.wait_async();
                if (GLib.FileUtils.test(tmp_pdf, GLib.FileTest.EXISTS)) {
                    var fd = new FileDialog();
                    fd.title = "Save PDF As";
                    fd.initial_name = current_file != null
                        ? GLib.Path.get_basename(current_file.get_path()).replace(".md", ".pdf")
                        : "Untitled.pdf";
                    fd.save.begin(main_window, null, (o, r) => {
                        try {
                            var dest = fd.save.end(r);
                            string dest_path = dest.get_path();
                            if (!dest_path.has_suffix(".pdf")) dest_path += ".pdf";
                            GLib.FileUtils.rename(tmp_pdf, dest_path);
                        } catch {}
                        try { GLib.DirUtils.remove(tmp_dir); } catch {}
                    });
                }
            } catch (Error e) {
                warning("Export via pandoc: %s", e.message);
            }
        }



        private bool handle_enter() {
            Gtk.TextIter cursor;
            text_buffer.get_iter_at_mark(out cursor, text_buffer.get_insert());

            Gtk.TextIter line_start = cursor;
            line_start.set_line_offset(0);
            Gtk.TextIter line_end = cursor;
            if (!line_end.ends_line()) line_end.forward_to_line_end();
            string line_text = text_buffer.get_text(line_start, line_end, false);

            bool in_heading  = cursor.has_tag(tag_h1) || cursor.has_tag(tag_h2) ||
                               cursor.has_tag(tag_h3) || cursor.has_tag(tag_h4);
            bool in_bullet   = cursor.has_tag(tag_bullet);
            bool in_numbered = cursor.has_tag(tag_numbered);
            bool in_quote    = cursor.has_tag(tag_quote);

            // Horizontal rule: "---" + Enter
            if (line_text.strip() == "---") {
                text_buffer.begin_user_action();
                Gtk.TextIter ls = line_start, le = line_end;
                text_buffer.delete(ref ls, ref le);
                string hr_text = "────────────────────────────────────────";
                Gtk.TextIter ins;
                text_buffer.get_iter_at_mark(out ins, text_buffer.get_insert());
                text_buffer.insert(ref ins, hr_text, -1);
                Gtk.TextIter hs, he;
                text_buffer.get_iter_at_mark(out hs, text_buffer.get_insert());
                he = hs;
                hs.set_line_offset(0);
                if (!he.ends_line()) he.forward_to_line_end();
                text_buffer.apply_tag(tag_hr, hs, he);
                text_buffer.insert_at_cursor("\n", -1);
                text_buffer.end_user_action();
                return true;
            }

            // Bullet list
            if (in_bullet && line_text.has_prefix("• ")) {
                string content = line_text.substring("• ".length);
                if (content.strip() == "") {
                    // Empty bullet, exit list
                    text_buffer.begin_user_action();
                    Gtk.TextIter ls, le;
                    text_buffer.get_iter_at_mark(out ls, text_buffer.get_insert());
                    ls.set_line_offset(0);
                    le = ls;
                    le.forward_to_line_end();
                    text_buffer.delete(ref ls, ref le);
                    Gtk.TextIter cur2;
                    text_buffer.get_iter_at_mark(out cur2, text_buffer.get_insert());
                    text_buffer.remove_tag(tag_bullet,   cur2, cur2);
                    text_buffer.remove_tag(tag_numbered, cur2, cur2);
                    text_buffer.apply_tag(tag_body,      cur2, cur2);
                    text_buffer.end_user_action();
                    return true;
                }
                // Has content, continue bullet
                text_buffer.begin_user_action();
                text_buffer.insert_at_cursor("\n• ", -1);
                Gtk.TextIter nc;
                text_buffer.get_iter_at_mark(out nc, text_buffer.get_insert());
                Gtk.TextIter ns = nc; ns.set_line_offset(0);
                Gtk.TextIter ne = nc; if (!ne.ends_line()) ne.forward_to_line_end();
                text_buffer.remove_tag(tag_numbered, ns, ne);
                text_buffer.apply_tag(tag_bullet,    ns, ne);
                text_buffer.end_user_action();
                return true;
            }

            // Numbered list
            if (in_numbered) {
                var re_num = new GLib.Regex("^(\\d+)\\.\\s");
                GLib.MatchInfo mi;
                if (re_num.match(line_text, 0, out mi)) {
                    int num        = int.parse(mi.fetch(1));
                    string matched = mi.fetch(0);
                    string content = line_text.substring(matched.length);
                    if (content.strip() == "") {
                        // Empty numbered, exit list
                        text_buffer.begin_user_action();
                        Gtk.TextIter ls, le;
                        text_buffer.get_iter_at_mark(out ls, text_buffer.get_insert());
                        ls.set_line_offset(0);
                        le = ls;
                        le.forward_to_line_end();
                        text_buffer.delete(ref ls, ref le);
                        Gtk.TextIter cur2;
                        text_buffer.get_iter_at_mark(out cur2, text_buffer.get_insert());
                        text_buffer.remove_tag(tag_bullet,   cur2, cur2);
                        text_buffer.remove_tag(tag_numbered, cur2, cur2);
                        text_buffer.apply_tag(tag_body,      cur2, cur2);
                        text_buffer.end_user_action();
                        return true;
                    }
                    // Has content, continue with incremented number
                    string next_prefix = "\n%d. ".printf(num + 1);
                    text_buffer.begin_user_action();
                    text_buffer.insert_at_cursor(next_prefix, -1);
                    Gtk.TextIter nc;
                    text_buffer.get_iter_at_mark(out nc, text_buffer.get_insert());
                    Gtk.TextIter ns = nc; ns.set_line_offset(0);
                    Gtk.TextIter ne = nc; if (!ne.ends_line()) ne.forward_to_line_end();
                    text_buffer.remove_tag(tag_bullet,  ns, ne);
                    text_buffer.apply_tag(tag_numbered, ns, ne);
                    text_buffer.end_user_action();
                    return true;
                }
            }

            // Heading, body
            if (in_heading) {
                text_buffer.begin_user_action();
                text_buffer.insert_at_cursor("\n", -1);
                Gtk.TextIter nc;
                text_buffer.get_iter_at_mark(out nc, text_buffer.get_insert());
                Gtk.TextIter ns = nc; ns.set_line_offset(0);
                Gtk.TextIter ne = nc; if (!ne.ends_line()) ne.forward_to_line_end();
                text_buffer.remove_tag(tag_h1,  ns, ne);
                text_buffer.remove_tag(tag_h2,  ns, ne);
                text_buffer.remove_tag(tag_h3,  ns, ne);
                text_buffer.remove_tag(tag_h4,  ns, ne);
                text_buffer.apply_tag(tag_body, ns, ne);
                text_buffer.end_user_action();
                return true;
            }

            // Quote: empty line, exit
            if (in_quote && line_text.strip() == "") {
                text_buffer.begin_user_action();
                Gtk.TextIter cur2;
                text_buffer.get_iter_at_mark(out cur2, text_buffer.get_insert());
                Gtk.TextIter ls = cur2; ls.set_line_offset(0);
                Gtk.TextIter le = ls;  if (!le.ends_line()) le.forward_to_line_end();
                text_buffer.remove_tag(tag_quote, ls, le);
                text_buffer.apply_tag(tag_body,   ls, le);
                text_buffer.end_user_action();
                return true;
            }

            return false;
        }

        // Markdown-like triggers at line start when Space is pressed.

        private bool try_auto_format_line() {
            Gtk.TextIter cursor;
            text_buffer.get_iter_at_mark(out cursor, text_buffer.get_insert());
            Gtk.TextIter ls = cursor;
            ls.set_line_offset(0);
            string prefix = text_buffer.get_text(ls, cursor, false);

            string[] heading_triggers = { "#", "##", "###" };
            string[] heading_styles   = { "h1", "h2", "h3" };

            if (prefix == "*" || prefix == "-") {
                _auto_format_lock = true;
                text_buffer.begin_user_action();
                Gtk.TextIter s = ls, e = cursor;
                text_buffer.delete(ref s, ref e);
                apply_list_style(true);
                // Advance cursor past the inserted "• " (2 Unicode chars)
                Gtk.TextIter nc;
                text_buffer.get_iter_at_mark(out nc, text_buffer.get_insert());
                nc.forward_chars(2);
                text_buffer.place_cursor(nc);
                text_buffer.end_user_action();
                _auto_format_lock = false;
                return true;
            }

            if (prefix == "1.") {
                _auto_format_lock = true;
                text_buffer.begin_user_action();
                Gtk.TextIter s = ls, e = cursor;
                text_buffer.delete(ref s, ref e);
                apply_list_style(false);
                // Advance cursor past "1. " (3 chars)
                Gtk.TextIter nc;
                text_buffer.get_iter_at_mark(out nc, text_buffer.get_insert());
                nc.forward_chars(3);
                text_buffer.place_cursor(nc);
                text_buffer.end_user_action();
                _auto_format_lock = false;
                return true;
            }

            // Longest-match first for heading hashes
            for (int hi = heading_triggers.length - 1; hi >= 0; hi--) {
                if (prefix == heading_triggers[hi]) {
                    _auto_format_lock = true;
                    text_buffer.begin_user_action();
                    Gtk.TextIter s = ls, e = cursor;
                    text_buffer.delete(ref s, ref e);
                    apply_para_style(heading_styles[hi]);
                    text_buffer.end_user_action();
                    _auto_format_lock = false;
                    return true;
                }
            }

            if (prefix == ">") {
                _auto_format_lock = true;
                text_buffer.begin_user_action();
                Gtk.TextIter s = ls, e = cursor;
                text_buffer.delete(ref s, ref e);
                apply_para_style("quote");
                text_buffer.end_user_action();
                _auto_format_lock = false;
                return true;
            }

            return false;
        }

        // Autocorrect: replaces typographic symbols after space is inserted.

        private void do_autocorrect() {
            Gtk.TextIter cursor;
            text_buffer.get_iter_at_mark(out cursor, text_buffer.get_insert());
            if (cursor.get_offset() == 0) return;

            // Only trigger when last char in buffer is a space
            Gtk.TextIter prev = cursor;
            prev.backward_char();
            unichar last_ch = prev.get_char();
            if (last_ch != ' ' && last_ch != '\n') return;

            Gtk.TextIter ls = prev;
            ls.set_line_offset(0);
            string before = text_buffer.get_text(ls, prev, false);
            if (before == "") return;

            string[] pats = { "--", "...", "(c)", "(C)", "(r)", "(R)", "(tm)", "(TM)",
                              "1/2", "1/4", "3/4" };
            string[] reps = { "-", "…", "©", "©", "®", "®", "™", "™",
                              "½", "¼", "¾" };

            for (int i = 0; i < pats.length; i++) {
                if (before.has_suffix(pats[i])) {
                    int nchars = pats[i].char_count();
                    Gtk.TextIter del_s = prev;
                    del_s.backward_chars(nchars);
                    Gtk.TextIter del_e = prev;
                    text_buffer.begin_user_action();
                    text_buffer.delete(ref del_s, ref del_e);
                    text_buffer.insert(ref del_s, reps[i], -1);
                    text_buffer.end_user_action();
                    return;
                }
            }
        }

        // Smart Home: first press, first non-whitespace; second, absolute start.

        private bool handle_smart_home(bool shift) {
            Gtk.TextIter cursor;
            text_buffer.get_iter_at_mark(out cursor, text_buffer.get_insert());
            int current_line = cursor.get_line();

            Gtk.TextIter abs_start = cursor;
            abs_start.set_line_offset(0);

            Gtk.TextIter first_nws = abs_start;
            while (!first_nws.ends_line() && first_nws.get_char().isspace())
                first_nws.forward_char();

            int nws_offset    = first_nws.get_line_offset();
            int cursor_offset = cursor.get_line_offset();

            bool go_abs = (_last_home_line == current_line && cursor_offset == nws_offset);
            Gtk.TextIter target = go_abs ? abs_start : first_nws;

            if (shift)
                text_buffer.move_mark(text_buffer.get_insert(), target);
            else
                text_buffer.place_cursor(target);

            _last_home_line = go_abs ? -1 : current_line;
            text_view.scroll_to_mark(text_buffer.get_insert(), 0.0, false, 0, 0);
            return true;
        }

        // Smart quotes: context-aware typographic open/close substitution.

        private bool handle_smart_quote(unichar raw) {
            Gtk.TextIter cursor;
            text_buffer.get_iter_at_mark(out cursor, text_buffer.get_insert());

            bool is_opening = true;
            if (cursor.get_offset() > 0) {
                Gtk.TextIter prev = cursor;
                prev.backward_char();
                unichar pc = prev.get_char();
                if (pc.isalnum() || pc == ')' || pc == ']' ||
                    pc == '"'    || pc == '\u201D' ||
                    pc == '\''   || pc == '\u2019')
                    is_opening = false;
            }

            string rep = (raw == '"')
                ? (is_opening ? "\u201C" : "\u201D")
                : (is_opening ? "\u2018" : "\u2019");

            text_buffer.begin_user_action();
            text_buffer.insert_at_cursor(rep, -1);
            text_buffer.end_user_action();
            return true;
        }

        // Ctrl+Backspace: delete word before cursor.

        private void delete_word_backward() {
            Gtk.TextIter cursor;
            text_buffer.get_iter_at_mark(out cursor, text_buffer.get_insert());
            Gtk.TextIter ws = cursor;
            if (!ws.is_start()) ws.backward_word_start();
            if (ws.compare(cursor) < 0) {
                text_buffer.begin_user_action();
                text_buffer.delete(ref ws, ref cursor);
                text_buffer.end_user_action();
            }
        }

        // Ctrl+Delete: delete word after cursor.

        private void delete_word_forward() {
            Gtk.TextIter cursor;
            text_buffer.get_iter_at_mark(out cursor, text_buffer.get_insert());
            Gtk.TextIter we = cursor;
            if (!we.is_end()) we.forward_word_end();
            while (!we.is_end() && we.get_char() == ' ')
                we.forward_char();
            if (we.compare(cursor) > 0) {
                text_buffer.begin_user_action();
                text_buffer.delete(ref cursor, ref we);
                text_buffer.end_user_action();
            }
        }

        private void setup_styles() {
            var provider = new Gtk.CssProvider();
            provider.load_from_data(WRITE_CSS.data);
            Gtk.StyleContext.add_provider_for_display(
                Gdk.Display.get_default(), provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
        }

        private const string WRITE_CSS = """
/* Ruler */
.write-ruler {
    background-color: @surface_bg;
    border-top: 1px solid alpha(@text_color, 0.05);
    border-bottom: 1px solid alpha(@text_color, 0.07);
    min-height: 22px;
}

/* Page Canvas */
.write-page-canvas {
    background-color: @surface_mid;
}
.write-canvas-outer {
    background-color: @surface_mid;
    padding: 0;
}
.write-page {
    background-color: @text_color;
    color: @surface_dim;
    border-radius: 2px;
    box-shadow: 0 4px 32px alpha(@shadow_color, 0.6), 0 1px 4px alpha(@shadow_color, 0.4);
}

/* Document text view */
.write-doc-text {
    background-color: transparent;
    color: @surface_dim;
    font-size: 12pt;
    font-family: "Liberation Serif", "Georgia", serif;
    caret-color: @link_active_color;
}
.write-doc-text text {
    background-color: transparent;
    color: @surface_dim;
}
.write-doc-text selection {
    background-color: alpha(@accent_color, 0.25);
}

/* Floating format bar */
.write-format-bar {
    background-color: @surface_raised;
    border: 1px solid alpha(@text_color, 0.12);
    border-radius: 8px;
    box-shadow: 0 4px 18px alpha(@shadow_color, 0.55);
    padding: 0;
}
.write-format-bar > * {
    padding: 0;
}

/* Find/Replace bar */
.write-find-bar {
    background-color: transparent;
}
.write-find-bar-inner {
    background-color: @surface_bg;
    border-top: 1px solid alpha(@text_color, 0.08);
    padding: 2px 0;
}

/* Outline sidebar */
.write-sidebar {
    background-color: @surface_bg;
    border-right: 1px solid alpha(@text_color, 0.07);
    min-width: 160px;
}
.write-outline-header {
    font-size: 10px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: alpha(@fg_color, 0.45);
}
.write-outline-list button.write-outline-row {
    border-radius: 4px;
    margin: 1px 6px;
    padding: 3px 8px;
    font-size: 11px;
    color: alpha(@fg_color, 0.75);
}
.write-outline-list button.write-outline-row:hover {
    background-color: alpha(@text_color, 0.08);
    color: @fg_color;
}
.write-outline-h1 { font-weight: 700; }
.write-outline-h2 { font-weight: 600; }
.write-outline-h3 { font-weight: 500; }
.write-outline-h4 { font-weight: 400; }

/* Style chooser */
.style-chooser {
    min-width: 120px;
}
.style-chooser-list {
    padding: 4px 0;
    min-width: 160px;
}
.style-chooser-list button.style-chooser-item {
    border-radius: 4px;
    margin: 1px 4px;
    padding: 5px 10px;
}
.style-chooser-list button.style-item-h1 { font-size: 18px; font-weight: 700; }
.style-chooser-list button.style-item-h2 { font-size: 15px; font-weight: 700; }
.style-chooser-list button.style-item-h3 { font-size: 13px; font-weight: 600; }
.style-chooser-list button.style-item-h4 { font-size: 12px; font-weight: 600; }
.style-chooser-list button.style-item-quote { font-style: italic; color: alpha(@text_color, 0.6); }
.style-chooser-list button.style-item-code  { font-family: monospace; font-size: 11px; }

/* Color picker button */
.color-picker-button {
    padding: 3px;
    min-width: 28px;
    min-height: 28px;
}

/* Tables */
.write-table {
    border: 1px solid alpha(@shadow_color, 0.2);
    margin: 4px 0;
}
.write-table-cell {
    border: 1px solid alpha(@shadow_color, 0.15);
    padding: 2px 4px;
    min-width: 80px;
    min-height: 28px;
    background-color: @text_color;
    color: @surface_dim;
}
.write-table-header {
    background-color: #f0ece0;
    font-weight: 600;
}

/* Images */
.write-image {
    display: block;
    margin: 6px 0;
}

/* Footnotes */
.write-footnote-anchor {
    font-size: 9px;
    padding: 0 2px;
    min-height: 0;
    vertical-align: super;
    color: @link_active_color;
}
.write-footnote-editor {
    background-color: @text_color;
    color: @surface_dim;
    font-size: 11px;
    padding: 4px;
}

/* Write start page */
.write-start-page {
    background-color: @window_bg_color;
}
.write-start-card {
    border-radius: 12px;
    border: 1px solid alpha(@borders, 0.5);
    background-color: alpha(@card_bg_color, 0.6);
    transition: background-color 0.12s ease, border-color 0.12s ease;
    min-width: 200px;
}
.write-start-card:hover {
    background-color: @card_bg_color;
    border-color: alpha(@accent_color, 0.5);
}
.write-start-card:active {
    background-color: mix(@card_bg_color, @accent_color, 0.08);
}
.write-recent-list {
    border-radius: 10px;
    border: 1px solid alpha(@borders, 0.4);
    overflow: hidden;
}
.write-recent-row {
    border-radius: 0;
    background-color: transparent;
    transition: background-color 0.1s ease;
}
.write-recent-row:hover {
    background-color: alpha(@accent_color, 0.08);
}
.write-recent-row + .write-recent-row {
    border-top: 1px solid alpha(@borders, 0.3);
}

""";

    }
}
