using Gtk;
using Gdk;
using GLib;
using WebKit;
using Singularity;
using Singularity.Widgets;

namespace Singularity.Apps {

    public class WriteApp : Singularity.Application {

        public delegate void Done();

        private WriteWindow main_window;
        private Singularity.Widgets.ToolBar toolbar { get { return main_window.toolbar; } }
        private Singularity.Widgets.FindReplaceBar find_bar;
        private Box outline_box;
        private Widget _md_outline_empty;
        private Label word_count_label;

        private Gtk.Stack _layout_stack;
        private WriteRichEditor _rich;

        private GLib.File? current_file = null;
        private Gtk.Box? _recent_list_box = null;
        private Gtk.Box? _recovered_box = null;
        private bool modified = false;
        private GLib.Settings settings;
        private uint autosave_id = 0;
        private string _last_search_query = "";

        private bool _is_markdown = false;
        private bool _md_ui_built = false;
        private uint _md_update_timer = 0;
        private GtkSource.View _md_source_view;
        private GtkSource.View _md_source_view_s;
        private GtkSource.Buffer _md_buffer;
        private WebKit.WebView _md_preview_s;
        private WebKit.WebView _md_preview_v;
        private Gtk.Stack _md_preview_stack_s;
        private Gtk.Stack _md_preview_stack_v;
        private Gtk.Stack _md_stack;

        private bool _pending_new_note = false;
        private bool _pending_new_document = false;
        private bool _pending_template_gallery = false;
        private string? _suggested_name = null;
        private WriteTemplateGallery? _start_gallery = null;

        public WriteApp() {
            Object(application_id: "dev.sinty.write",
                   flags: ApplicationFlags.HANDLES_OPEN);
            add_main_option("new-note", 0, OptionFlags.NONE, OptionArg.NONE,
                            _("Start a new Markdown note"), null);
            add_main_option("new-document", 0, OptionFlags.NONE, OptionArg.NONE,
                            _("Start a new document"), null);
            add_main_option("new-from-template", 0, OptionFlags.NONE, OptionArg.NONE,
                            _("Choose a template for a new document"), null);
        }

        protected override int handle_local_options(VariantDict options) {
            bool from_template = options.contains("new-from-template");
            bool new_doc = options.contains("new-document");
            if (!options.contains("new-note") && !from_template && !new_doc) return -1;
            try {
                register(null);
            } catch (Error e) {
                return -1;
            }
            if (get_is_remote()) {
                activate();
                activate_action(from_template ? "new-from-template" : (new_doc ? "new" : "new-markdown"), null);
                return 0;
            }
            _pending_new_note = !from_template && !new_doc;
            _pending_new_document = new_doc;
            _pending_template_gallery = from_template;
            return -1;
        }

        private bool present_existing() {
            var existing = get_active_window() as WriteWindow;
            if (existing == null) return false;
            existing.present();
            return true;
        }

        private void build_window() {
            Gtk.IconTheme.get_for_display(Gdk.Display.get_default()).add_resource_path("/dev/sinty/write/icons");
            setup_styles();
            settings = load_settings();
            build_ui();
            settings.changed["md-color-scheme"].connect(update_md_color_scheme);
            main_window.close_request.connect(on_close_request);
        }

        protected override void activate() {
            if (present_existing()) return;
            build_window();
            if (_pending_new_note) {
                _pending_new_note = false;
                new_markdown_note();
            } else if (_pending_new_document) {
                _pending_new_document = false;
                new_document();
            } else {
                show_start_page();
            }
            main_window.present();
            if (_pending_template_gallery) {
                _pending_template_gallery = false;
                if (main_window.is_active) {
                    activate_action("new-from-template", null);
                } else {
                    ulong handler = 0;
                    handler = main_window.notify["is-active"].connect(() => {
                        if (!main_window.is_active) return;
                        main_window.disconnect(handler);
                        activate_action("new-from-template", null);
                    });
                }
            }
        }

        protected override void open(GLib.File[] files, string hint) {
            bool existing = present_existing();
            if (!existing) build_window();
            if (files.length > 0) {
                do_open(files[0]);
            } else if (!existing) {
                show_start_page();
            }
            main_window.present();
        }

        public void open_document(GLib.File file) {
            GLib.File[] files = { file };
            open(files, "");
        }

        private GLib.Settings load_settings() {
            var src = SettingsSchemaSource.get_default();
            if (src != null && src.lookup("dev.sinty.write", true) != null)
                return new GLib.Settings("dev.sinty.write");
            try {
                string exe = GLib.FileUtils.read_link("/proc/self/exe");
                var data_dir = GLib.File.new_for_path(exe).get_parent().get_child("data");
                if (data_dir.get_child("gschemas.compiled").query_exists()) {
                    var cs = new SettingsSchemaSource.from_directory(data_dir.get_path(), src, true);
                    var schema = cs.lookup("dev.sinty.write", true);
                    if (schema != null)
                        return new GLib.Settings.full(schema, null, null);
                }
            } catch (Error e) {}
            return new GLib.Settings("dev.sinty.write");
        }

        private string layout() {
            return _layout_stack != null ? (_layout_stack.visible_child_name ?? "start") : "start";
        }

        private bool in_rich() {
            return layout() == "rich";
        }

        private bool in_markdown() {
            return layout() == "markdown";
        }

        private bool doc_modified() {
            if (in_rich()) return _rich.modified;
            if (in_markdown()) return modified;
            return false;
        }

        private void toast(string text) {
            main_window.add_toast(new Singularity.Widgets.Toast(text));
        }

        private void guard_unsaved(owned Done next) {
            if (!doc_modified()) {
                next();
                return;
            }
            var dlg = new Singularity.Widgets.ConfirmDialog((Gtk.Application) this,
                _("Save Changes?"), "dialog-warning-symbolic",
                _("The current document has unsaved changes."),
                _("Discard"), Singularity.Widgets.ConfirmDialog.ActionStyle.DESTRUCTIVE);
            dlg.set_secondary(_("Save"), Singularity.Widgets.ConfirmDialog.ActionStyle.SUGGESTED);
            dlg.transient_for = main_window;
            dlg.response.connect((r) => {
                if (r == Singularity.Widgets.ConfirmDialog.Response.CANCEL) return;
                if (r == Singularity.Widgets.ConfirmDialog.Response.SECONDARY) {
                    save_current(() => next());
                    return;
                }
                if (in_rich()) WriteFiles.clear_recovery(_rich);
                next();
            });
            dlg.present();
        }

        private bool on_close_request() {
            if (!doc_modified()) {
                if (autosave_id != 0) {
                    Source.remove(autosave_id);
                    autosave_id = 0;
                }
                return false;
            }
            guard_unsaved(() => {
                _rich.modified = false;
                modified = false;
                main_window.close();
            });
            return true;
        }

        private void build_ui() {
            main_window = new WriteWindow((Gtk.Application) this);
            _rich = new WriteRichEditor(main_window, this, settings);
            _rich.title_changed.connect(update_title);
            _rich.toast.connect((t) => toast(t));
            _rich.state_changed.connect(sync_actions);
            setup_doc_actions();
            setup_menubar();
            build_toolbar();
            build_layout();
            setup_keyboard();
            setup_autosave();
            if (Environment.get_variable("WRITE_DEBUG_SIZES") != null) GLib.Timeout.add(int.parse(Environment.get_variable("WRITE_DEBUG_SIZES")) * 1000, () => {
                dump_sizes(main_window, 0);
                return false;
            });
        }

        private void dump_sizes(Widget w, int depth) {
            if (depth > 30) return;
            int mn, nt, a, b;
            w.measure(Orientation.HORIZONTAL, -1, out mn, out nt, out a, out b);
            int mh, nh;
            w.measure(Orientation.VERTICAL, w.get_width(), out mh, out nh, out a, out b);
            printerr("%s%s min=%d nat=%d alloc=%dx%d vmin=%d vnat=%d vis=%s\n", string.nfill(depth * 2, ' '), w.get_type().name(), mn, nt, w.get_width(), w.get_height(), mh, nh, w.get_mapped().to_string());
            for (var c = w.get_first_child(); c != null; c = c.get_next_sibling()) dump_sizes(c, depth + 1);
        }

        private void setup_doc_actions() {
            var link_state = new SimpleAction.stateful("live-link", null, new Variant.string(""));
            add_action(link_state);
            _rich.live_changed.connect(() => {
                link_state.set_state(new Variant.string(_rich.live != null ? _rich.live.link : ""));
            });
            foreach (string n in WriteActions.names()) {
                SimpleAction act;
                if (WriteActions.with_param(n)) act = new SimpleAction("doc-" + n, VariantType.STRING);
                else if (WriteActions.is_double(n)) act = new SimpleAction("doc-" + n, VariantType.DOUBLE);
                else act = new SimpleAction("doc-" + n, null);
                string name = n;
                act.activate.connect((v) => {
                    if (!in_rich()) return;
                    _rich.run(name, v);
                });
                add_action(act);
            }
            string[,] accels = {
                { "app.doc-bold", "<Control>b" },
                { "app.doc-italic", "<Control>i" },
                { "app.doc-underline", "<Control>u" },
                { "app.doc-double-underline", "<Control><Shift>d" },
                { "app.doc-superscript", "<Control><Shift>plus" },
                { "app.doc-subscript", "<Control>equal" },
                { "app.doc-smallcaps", "<Control><Shift>k" },
                { "app.doc-allcaps", "<Control><Shift>a" },
                { "app.doc-grow-font", "<Control><Shift>greater" },
                { "app.doc-shrink-font", "<Control><Shift>less" },
                { "app.doc-clear-formatting", "<Control>space" },
                { "app.doc-font-dialog", "<Control>d" },
                { "app.doc-align::left", "<Control>l" },
                { "app.doc-align::center", "<Control>e" },
                { "app.doc-align::right", "<Control>r" },
                { "app.doc-align::justify", "<Control>j" },
                { "app.doc-line-spacing::1", "<Control>1" },
                { "app.doc-line-spacing::1.5", "<Control>5" },
                { "app.doc-line-spacing::2", "<Control>2" },
                { "app.doc-indent-more", "<Control>m" },
                { "app.doc-indent-less", "<Control><Shift>m" },
                { "app.doc-bullets", "<Control><Shift>l" },
                { "app.doc-style::Normal", "<Control><Shift>n" },
                { "app.doc-style::Heading1", "<Control><Alt>1" },
                { "app.doc-style::Heading2", "<Control><Alt>2" },
                { "app.doc-style::Heading3", "<Control><Alt>3" },
                { "app.doc-styles-pane", "<Control><Alt><Shift>s" },
                { "app.doc-change-case::toggle", "<Shift>F3" },
                { "app.doc-page-break", "<Control>Return" },
                { "app.doc-column-break", "<Control><Shift>Return" },
                { "app.doc-equation", "<Alt>equal" },
                { "app.doc-footnote", "<Control><Alt>f" },
                { "app.doc-endnote", "<Control><Alt>d" },
                { "app.doc-new-comment", "<Control><Alt>m" },
                { "app.doc-link", "<Control>k" },
                { "app.doc-index-entry", "<Alt><Shift>x" },
                { "app.doc-spelling", "F7" },
                { "app.doc-thesaurus", "<Shift>F7" },
                { "app.doc-word-count", "<Control><Shift>g" },
                { "app.doc-track-changes", "<Control><Shift>e" },
                { "app.doc-update-fields", "F9" },
                { "app.doc-marks", "<Control><Shift>asterisk" },
                { "app.doc-navigation", "<Control><Alt>n" },
                { "app.doc-zoom-in", "<Control>plus" },
                { "app.doc-zoom-out", "<Control>minus" },
                { "app.doc-zoom::100", "<Control>0" },
                { "app.doc-paste-text", "<Control><Shift>v" },
                { "app.doc-paste-special", "<Control><Alt>v" },
                { "app.doc-goto", "<Control>g" },
                { "app.doc-format-painter", "<Control><Shift>c" },
                { "app.doc-reveal-formatting", "<Shift>F1" },
                { "app.doc-view::outline", "<Control><Alt>o" },
                { "app.doc-view::print", "<Control><Alt>p" },
                { "app.doc-view::draft", "<Control><Alt>r" },
                { "app.doc-read-aloud", "<Control><Alt>space" }
            };
            for (int i = 0; i < accels.length[0]; i++) set_accels_for_action(accels[i, 0], { accels[i, 1] });
        }

        private GLib.Menu _recent_menu = new GLib.Menu();

        private static GLib.Menu section(string[,] items) {
            var m = new GLib.Menu();
            for (int i = 0; i < items.length[0]; i++) m.append(items[i, 0], items[i, 1]);
            return m;
        }

        private static GLib.Menu menu_of(GLib.Menu[] sections) {
            var m = new GLib.Menu();
            foreach (var s in sections) m.append_section(null, s);
            return m;
        }

        private void setup_menubar() {
            var menu = new GLib.Menu();

            var f1 = section({
                { _("New Document"), "app.new" },
                { _("New Markdown Note"), "app.new-markdown" },
                { _("New from Template…"), "app.new-from-template" },
                { _("Open…"), "app.open" },
                { _("Open from Online Account…"), "app.open-online" }
            });
            f1.append_submenu(_("Open Recent"), _recent_menu);
            var export_menu = section({
                { _("Word Document (.docx)…"), "app.export::docx" },
                { _("OpenDocument Text (.odt)…"), "app.export::odt" },
                { _("Rich Text Format (.rtf)…"), "app.export::rtf" },
                { _("PDF…"), "app.export::pdf" },
                { _("Web Page (.html)…"), "app.export::html" },
                { _("Markdown (.md)…"), "app.export::md" },
                { _("EPUB Book (.epub)…"), "app.export::epub" },
                { _("Plain Text (.txt)…"), "app.export::txt" }
            });
            var f2 = section({
                { _("Save"), "app.save" },
                { _("Save As…"), "app.save-as" },
                { _("Save to Online Account…"), "app.save-online" },
                { _("Save as Template…"), "app.save-as-template" }
            });
            f2.append_submenu(_("Export"), export_menu);
            var f3 = section({
                { _("Version History…"), "app.doc-versions" },
                { _("Properties…"), "app.doc-properties" },
                { _("Restrict Editing…"), "app.doc-protect" }
            });
            var f4 = section({
                { _("Page Setup…"), "app.page-setup" },
                { _("Print…"), "app.print" },
                { _("Share…"), "app.share" }
            });
            var f5 = section({
                { _("Close Document"), "app.close-document" },
                { _("Close Window"), "win.close" },
                { _("Quit"), "app.quit" }
            });
            menu.append_submenu(_("File"), menu_of({ f1, f2, f3, f4, f5 }));

            menu.append_submenu(_("Edit"), menu_of({
                section({ { _("Undo"), "app.undo" }, { _("Redo"), "app.redo" } }),
                section({
                    { _("Cut"), "app.cut" },
                    { _("Copy"), "app.copy" },
                    { _("Paste"), "app.paste" },
                    { _("Paste as Plain Text"), "app.doc-paste-text" },
                    { _("Paste Special…"), "app.doc-paste-special" },
                    { _("Select All"), "app.select-all" }
                }),
                section({
                    { _("Find"), "app.find" },
                    { _("Find and Replace"), "app.find-replace" },
                    { _("Find Next"), "app.find-next" },
                    { _("Find Previous"), "app.find-previous" },
                    { _("Go To…"), "app.doc-goto" }
                }),
                section({ { _("Format Painter"), "app.doc-format-painter" } }),
                section({ { _("Settings"), "app.settings" } })
            }));

            var zoom = section({
                { _("Zoom In"), "app.doc-zoom-in" },
                { _("Zoom Out"), "app.doc-zoom-out" },
                { _("Actual Size"), "app.doc-zoom::100" },
                { _("Page Width"), "app.doc-zoom::width" },
                { _("Whole Page"), "app.doc-zoom::page" }
            });
            var v4 = new GLib.Menu();
            v4.append_submenu(_("Zoom"), zoom);
            v4.append(_("Fullscreen"), "app.fullscreen");
            menu.append_submenu(_("View"), menu_of({
                section({
                    { _("Print Layout"), "app.doc-view::print" },
                    { _("Web Layout"), "app.doc-view::web" },
                    { _("Draft"), "app.doc-view::draft" },
                    { _("Outline"), "app.doc-view::outline" },
                    { _("Read Mode"), "app.doc-view::read" }
                }),
                section({
                    { _("Markdown Source"), "app.md-view::R" },
                    { _("Markdown Split"), "app.md-view::S" },
                    { _("Markdown Preview"), "app.md-view::V" }
                }),
                section({
                    { _("Navigation Pane"), "app.doc-navigation" },
                    { _("Markdown Outline"), "app.outline" },
                    { _("Styles Pane"), "app.doc-styles-pane" },
                    { _("Comments Pane"), "app.doc-comments-pane" },
                    { _("Review Pane"), "app.doc-review-pane" },
                    { _("Ruler"), "app.doc-ruler" },
                    { _("Formatting Marks"), "app.doc-marks" }
                }),
                v4
            }));

            var breaks = section({
                { _("Page Break"), "app.doc-page-break" },
                { _("Column Break"), "app.doc-column-break" },
                { _("Section Break (Next Page)"), "app.doc-section-break::next" },
                { _("Section Break (Continuous)"), "app.doc-section-break::continuous" },
                { _("Section Break (Even Page)"), "app.doc-section-break::even" },
                { _("Section Break (Odd Page)"), "app.doc-section-break::odd" }
            });
            var shapes = section({
                { _("Rectangle"), "app.doc-shape::rect" },
                { _("Rounded Rectangle"), "app.doc-shape::round" },
                { _("Ellipse"), "app.doc-shape::ellipse" },
                { _("Triangle"), "app.doc-shape::triangle" },
                { _("Line"), "app.doc-shape::line" },
                { _("Arrow"), "app.doc-shape::arrow" }
            });
            var pagenum = section({
                { _("Top of Page…"), "app.doc-page-number::header" },
                { _("Bottom of Page…"), "app.doc-page-number::footer" }
            });
            var forms = section({
                { _("Check Box"), "app.doc-checkbox-field" },
                { _("Text Field"), "app.doc-text-field" },
                { _("Drop-Down List"), "app.doc-dropdown-field" }
            });
            var i1 = new GLib.Menu();
            i1.append_submenu(_("Break"), breaks);
            var i2 = section({
                { _("Table…"), "app.doc-table-dialog" },
                { _("Picture…"), "app.doc-picture" }
            });
            i2.append_submenu(_("Shape"), shapes);
            var i2b = section({
                { _("Text Box"), "app.doc-textbox" },
                { _("WordArt…"), "app.doc-wordart" },
                { _("Chart…"), "app.doc-chart" },
                { _("Update Linked Charts"), "app.doc-update-charts" },
                { _("Equation"), "app.doc-equation" },
                { _("Inline Equation"), "app.doc-equation-inline" },
                { _("Equation Gallery\u2026"), "app.doc-equation-gallery" },
                { _("Symbol…"), "app.doc-symbol" }
            });
            var i3 = section({
                { _("Link…"), "app.doc-link" },
                { _("Bookmark…"), "app.doc-bookmark" },
                { _("Cross-reference…"), "app.doc-cross-reference" },
                { _("Comment"), "app.doc-new-comment" }
            });
            var i4 = section({
                { _("Header"), "app.doc-header" },
                { _("Footer"), "app.doc-footer" }
            });
            i4.append_submenu(_("Page Number"), pagenum);
            var i5 = section({
                { _("Date and Time…"), "app.doc-date-time" },
                { _("Field…"), "app.doc-field" },
                { _("Text from File…"), "app.doc-insert-file" },
                { _("Drop Cap…"), "app.doc-dropcap" },
                { _("Watermark…"), "app.doc-watermark" }
            });
            i5.append_submenu(_("Form Field"), forms);
            menu.append_submenu(_("Insert"), menu_of({ i1, i2, i2b, i3, i4, i5 }));

            var fcase = section({
                { _("Sentence case."), "app.doc-change-case::sentence" },
                { _("lowercase"), "app.doc-change-case::lower" },
                { _("UPPERCASE"), "app.doc-change-case::upper" },
                { _("Capitalize Each Word"), "app.doc-change-case::title" },
                { _("tOGGLE cASE"), "app.doc-change-case::toggle" }
            });
            var falign = section({
                { _("Align Left"), "app.doc-align::left" },
                { _("Center"), "app.doc-align::center" },
                { _("Align Right"), "app.doc-align::right" },
                { _("Justify"), "app.doc-align::justify" }
            });
            var fspacing = section({
                { "1.0", "app.doc-line-spacing::1" },
                { "1.15", "app.doc-line-spacing::1.15" },
                { "1.5", "app.doc-line-spacing::1.5" },
                { "2.0", "app.doc-line-spacing::2" },
                { _("Add Space Before Paragraph"), "app.doc-space-before" },
                { _("Add Space After Paragraph"), "app.doc-space-after" }
            });
            var fstyles = section({
                { _("Normal"), "app.doc-style::Normal" },
                { _("Title"), "app.doc-style::Title" },
                { _("Subtitle"), "app.doc-style::Subtitle" },
                { _("Heading 1"), "app.doc-style::Heading1" },
                { _("Heading 2"), "app.doc-style::Heading2" },
                { _("Heading 3"), "app.doc-style::Heading3" },
                { _("Quote"), "app.doc-style::Quote" },
                { _("No Spacing"), "app.doc-style::NoSpacing" }
            });
            fstyles.append_section(null, section({
                { _("Styles Pane"), "app.doc-styles-pane" },
                { _("New Style…"), "app.doc-new-style" },
                { _("Modify Style…"), "app.doc-modify-style" },
                { _("Import Styles…"), "app.doc-manage-styles" }
            }));
            var fsets = section({
                { _("Classic"), "app.doc-style-set::classic" },
                { _("Modern"), "app.doc-style-set::modern" },
                { _("Elegant"), "app.doc-style-set::elegant" },
                { _("Minimal"), "app.doc-style-set::minimal" },
                { _("Technical"), "app.doc-style-set::technical" }
            });
            var forient = section({
                { _("Portrait"), "app.doc-orientation::portrait" },
                { _("Landscape"), "app.doc-orientation::landscape" }
            });
            var fm1 = section({
                { _("Font…"), "app.doc-font-dialog" },
                { _("Paragraph…"), "app.doc-paragraph-dialog" }
            });
            var fm2 = section({
                { _("Bold"), "app.doc-bold" },
                { _("Italic"), "app.doc-italic" },
                { _("Underline"), "app.doc-underline" },
                { _("Double Underline"), "app.doc-double-underline" },
                { _("Strikethrough"), "app.doc-strike" },
                { _("Double Strikethrough"), "app.doc-dstrike" },
                { _("Superscript"), "app.doc-superscript" },
                { _("Subscript"), "app.doc-subscript" },
                { _("Small Caps"), "app.doc-smallcaps" },
                { _("All Caps"), "app.doc-allcaps" },
                { _("Grow Font"), "app.doc-grow-font" },
                { _("Shrink Font"), "app.doc-shrink-font" }
            });
            fm2.append_submenu(_("Change Case"), fcase);
            var fm3 = section({
                { _("Text Color…"), "app.doc-text-color-menu" },
                { _("Highlight Color…"), "app.doc-highlight-menu" },
                { _("Clear Formatting"), "app.doc-clear-formatting" }
            });
            var fm4 = new GLib.Menu();
            fm4.append_submenu(_("Alignment"), falign);
            fm4.append_submenu(_("Line and Paragraph Spacing"), fspacing);
            fm4.append(_("Increase Indent"), "app.doc-indent-more");
            fm4.append(_("Decrease Indent"), "app.doc-indent-less");
            fm4.append(_("Bullets"), "app.doc-bullets");
            fm4.append(_("Numbering"), "app.doc-numbering");
            fm4.append(_("Lists…"), "app.doc-multilevel");
            fm4.append(_("Restart Numbering"), "app.doc-restart-numbering");
            var fm5 = new GLib.Menu();
            fm5.append_submenu(_("Styles"), fstyles);
            fm5.append_submenu(_("Style Set"), fsets);
            var fm6 = section({
                { _("Columns…"), "app.doc-columns" },
                { _("Borders and Shading…"), "app.doc-borders" },
                { _("Page Color…"), "app.doc-page-color" },
                { _("Page Borders…"), "app.doc-page-borders" }
            });
            fm6.append_submenu(_("Orientation"), forient);
            fm6.append(_("Reveal Formatting"), "app.doc-reveal-formatting");
            menu.append_submenu(_("Format"), menu_of({ fm1, fm2, fm3, fm4, fm5, fm6 }));

            var tstyles = section({
                { _("Table Grid"), "app.doc-table-style::TableGrid" },
                { _("Plain Table"), "app.doc-table-style::PlainTable" },
                { _("Grid Table Light"), "app.doc-table-style::GridTableLight" },
                { _("Grid Table Accent"), "app.doc-table-style::GridTableAccent" }
            });
            var t3 = section({
                { _("Sort…"), "app.doc-table-sort" },
                { _("Formula…"), "app.doc-table-formula" },
                { _("Table Properties…"), "app.doc-table-properties" }
            });
            t3.append_submenu(_("Table Style"), tstyles);
            menu.append_submenu(_("Table"), menu_of({
                section({ { _("Insert Table…"), "app.doc-table-dialog" } }),
                section({
                    { _("Insert Row Above"), "app.doc-table-op::row-above" },
                    { _("Insert Row Below"), "app.doc-table-op::row-below" },
                    { _("Insert Column Left"), "app.doc-table-op::col-left" },
                    { _("Insert Column Right"), "app.doc-table-op::col-right" },
                    { _("Delete Row"), "app.doc-table-op::delete-row" },
                    { _("Delete Column"), "app.doc-table-op::delete-col" },
                    { _("Delete Table"), "app.doc-table-op::delete-table" }
                }),
                section({
                    { _("Merge With Right Cell"), "app.doc-table-op::merge-right" },
                    { _("Merge With Cell Below"), "app.doc-table-op::merge-down" },
                    { _("Split Cell"), "app.doc-table-op::split" },
                    { _("Distribute Columns Evenly"), "app.doc-table-op::distribute" },
                    { _("Repeat Header Row"), "app.doc-table-op::header-row" }
                }),
                t3,
                section({
                    { _("Convert Text to Table…"), "app.doc-text-to-table" },
                    { _("Convert Table to Text"), "app.doc-table-to-text" }
                })
            }));

            var bibstyles = section({
                { "APA", "app.doc-bib-style::APA" },
                { "MLA", "app.doc-bib-style::MLA" },
                { "Chicago", "app.doc-bib-style::Chicago" },
                { "IEEE", "app.doc-bib-style::IEEE" },
                { "Harvard", "app.doc-bib-style::Harvard" }
            });
            var r3 = section({
                { _("Insert Citation…"), "app.doc-citation" },
                { _("Manage Sources…"), "app.doc-sources" },
                { _("Bibliography"), "app.doc-bibliography" }
            });
            r3.append_submenu(_("Citation Style"), bibstyles);
            menu.append_submenu(_("References"), menu_of({
                section({
                    { _("Table of Contents"), "app.doc-toc" },
                    { _("Update Table of Contents"), "app.doc-update-toc" }
                }),
                section({
                    { _("Footnote"), "app.doc-footnote" },
                    { _("Endnote"), "app.doc-endnote" }
                }),
                r3,
                section({
                    { _("Insert Caption…"), "app.doc-caption" },
                    { _("Table of Figures"), "app.doc-tof" },
                    { _("Cross-reference…"), "app.doc-cross-reference" }
                }),
                section({
                    { _("Mark Index Entry…"), "app.doc-index-entry" },
                    { _("Insert Index"), "app.doc-index" }
                }),
                section({ { _("Update Fields"), "app.doc-update-fields" } })
            }));

            var markup = section({
                { _("All Markup"), "app.doc-markup::all" },
                { _("Simple Markup"), "app.doc-markup::simple" },
                { _("No Markup"), "app.doc-markup::none" },
                { _("Original"), "app.doc-markup::original" }
            });
            var rv3 = section({ { _("Track Changes"), "app.doc-track-changes" } });
            rv3.append_submenu(_("Show Markup"), markup);
            rv3.append_section(null, section({
                { _("Accept"), "app.doc-accept" },
                { _("Reject"), "app.doc-reject" },
                { _("Accept All Changes"), "app.doc-accept-all" },
                { _("Reject All Changes"), "app.doc-reject-all" },
                { _("Next Change"), "app.doc-next-change" },
                { _("Previous Change"), "app.doc-prev-change" },
                { _("Review Pane"), "app.doc-review-pane" }
            }));
            menu.append_submenu(_("Review"), menu_of({
                section({
                    { _("Spelling and Grammar"), "app.doc-spelling" },
                    { _("Thesaurus"), "app.doc-thesaurus" },
                    { _("Word Count"), "app.doc-word-count" },
                    { _("Language…"), "app.doc-language" },
                    { _("Hyphenation"), "app.doc-hyphenation" },
                    { _("Read Aloud"), "app.doc-read-aloud" },
                    { _("Dictate"), "app.doc-dictate" },
                    { _("Translate\u2026"), "app.doc-translate" },
                    { _("Check Accessibility"), "app.doc-accessibility" }
                }),
                section({
                    { _("New Comment"), "app.doc-new-comment" },
                    { _("Reply to Comment"), "app.doc-comment-reply" },
                    { _("Resolve Comment"), "app.doc-resolve-comment" },
                    { _("Delete Comment"), "app.doc-delete-comment" },
                    { _("Next Comment"), "app.doc-next-comment" },
                    { _("Previous Comment"), "app.doc-prev-comment" },
                    { _("Comments Pane"), "app.doc-comments-pane" }
                }),
                rv3,
                section({
                    { _("Edit Together\u2026"), "app.doc-live-share" },
                    { _("Compare…"), "app.doc-compare" },
                    { _("Combine…"), "app.doc-combine" }
                }),
                section({
                    { _("Restrict Editing…"), "app.doc-protect" },
                    { _("Line Numbers"), "app.doc-line-numbers" }
                })
            }));

            var finish = section({
                { _("Edit Individual Documents"), "app.doc-merge-finish::document" },
                { _("Save as PDF Files…"), "app.doc-merge-finish::pdf" },
                { _("Print Documents…"), "app.doc-merge-finish::print" }
            });
            var m2 = section({
                { _("Preview Results"), "app.doc-merge-preview" },
                { _("Next Record"), "app.doc-merge-next" },
                { _("Previous Record"), "app.doc-merge-prev" }
            });
            m2.append_submenu(_("Finish and Merge"), finish);
            menu.append_submenu(_("Mailings"), menu_of({
                section({
                    { _("Select Recipients…"), "app.doc-merge-recipients" },
                    { _("Insert Merge Field…"), "app.doc-merge-field" }
                }),
                m2,
                section({
                    { _("Envelopes…"), "app.doc-envelopes" },
                    { _("Labels…"), "app.doc-labels" }
                })
            }));

            menu.append_submenu(_("Tools"), menu_of({
                section({
                    { _("Record Macro"), "app.doc-macro-record" },
                    { _("Macros…"), "app.doc-macros" },
                    { _("New Script\u2026"), "app.doc-script-new" }
                }),
                section({
                    { _("AutoCorrect Options…"), "app.doc-autocorrect" },
                    { _("Update Fields"), "app.doc-update-fields" }
                })
            }));

            set_menubar(menu);

            add_simple("new", () => guard_unsaved(() => new_document()));
            add_simple("new-markdown", () => guard_unsaved(() => new_markdown_note()));
            add_simple("new-from-template", () => WriteTemplateDialogs.choose(this, main_window, (t) => start_from_template(t)));
            add_simple("save-as-template", () => on_save_as_template());
            add_simple("open", () => on_open());
            var open_recent = new SimpleAction("open-recent", VariantType.STRING);
            open_recent.activate.connect((v) => do_open(GLib.File.new_for_uri(v.get_string())));
            add_action(open_recent);
            add_simple("save", () => save_current(null));
            add_simple("save-as", () => on_save_as(null));
            add_simple("open-online", () => CloudActions.open.begin(main_window, (f) => do_open(f)));
            add_simple("save-online", () => on_save_online());
            var export_act = new SimpleAction("export", VariantType.STRING);
            export_act.activate.connect((v) => export_as(Write.FileFormat.from_extension("x." + v.get_string())));
            add_action(export_act);
            add_simple("print", () => on_print());
            add_simple("page-setup", () => {
                if (in_rich()) _rich.run("page-setup", null);
                else Singularity.Print.page_setup.begin(main_window);
            });
            Singularity.Share.add_action(this, main_window, () => {
                GLib.File? f = in_rich() ? _rich.file : current_file;
                return f != null ? new Singularity.ShareContent.for_files({ f }) : null;
            });
            add_simple("insert-equation", () => {
                if (in_rich()) _rich.run("equation", null);
                else insert_md_equation.begin();
            });
            add_simple("close-document", () => on_close_document());
            add_simple("undo", () => {
                if (in_rich()) _rich.run("undo", null);
                else if (_md_buffer != null && _md_buffer.can_undo) _md_buffer.undo();
            });
            add_simple("redo", () => {
                if (in_rich()) _rich.run("redo", null);
                else if (_md_buffer != null && _md_buffer.can_redo) _md_buffer.redo();
            });
            add_simple("cut", () => {
                if (in_rich()) _rich.run("cut", null);
                else Signal.emit_by_name(active_view(), "cut-clipboard");
            });
            add_simple("copy", () => {
                if (in_rich()) _rich.run("copy", null);
                else Signal.emit_by_name(active_view(), "copy-clipboard");
            });
            add_simple("paste", () => {
                if (in_rich()) _rich.run("paste", null);
                else Signal.emit_by_name(active_view(), "paste-clipboard");
            });
            add_simple("select-all", () => {
                if (in_rich()) {
                    _rich.run("select-all", null);
                    return;
                }
                active_view().select_all(true);
                active_view().grab_focus();
            });
            add_simple("find", () => {
                if (in_rich()) _rich.run("find", null);
                else find_bar.open_find();
            });
            add_simple("find-replace", () => {
                if (in_rich()) _rich.run("find-replace", null);
                else find_bar.open_replace();
            });
            add_simple("find-next", () => {
                if (in_rich()) _rich.run("find", null);
                else if (_last_search_query != "") do_find(_last_search_query, true);
                else find_bar.open_find();
            });
            add_simple("find-previous", () => {
                if (in_rich()) _rich.run("find", null);
                else if (_last_search_query != "") do_find(_last_search_query, false);
                else find_bar.open_find();
            });
            var md_view = new SimpleAction.stateful("md-view", VariantType.STRING, new Variant.string("S"));
            md_view.activate.connect((v) => {
                if (_md_stack != null) _md_stack.visible_child_name = v.get_string();
            });
            add_action(md_view);
            var outline = new SimpleAction.stateful("outline", null, new Variant.boolean(false));
            outline.activate.connect(() => toggle_sidebar());
            add_action(outline);
            var fullscreen_act = new SimpleAction.stateful("fullscreen", null, new Variant.boolean(false));
            fullscreen_act.activate.connect(() => {
                if (main_window.fullscreened) main_window.unfullscreen();
                else main_window.fullscreen();
            });
            add_action(fullscreen_act);

            var act_settings = new SimpleAction("settings", null);
            act_settings.activate.connect(() => {
                try {
                    Singularity.Shell.ShellService shell = GLib.Bus.get_proxy_sync(
                        GLib.BusType.SESSION, "dev.sinty.desktop", "/dev/sinty/Shell");
                    shell.open_app_settings("dev.sinty.write");
                } catch (Error e) {
                    warning("Failed to open settings: %s", e.message);
                }
            });
            add_action(act_settings);

            set_accels_for_action("app.new", {"<Control>n"});
            set_accels_for_action("app.new-from-template", {"<Control><Shift>t"});
            set_accels_for_action("app.open", {"<Control>o"});
            set_accels_for_action("app.save", {"<Control>s"});
            set_accels_for_action("app.save-as", {"<Control><Shift>s", "F12"});
            set_accels_for_action("app.print", {"<Control>p"});
            set_accels_for_action("app.undo", {"<Control>z"});
            set_accels_for_action("app.redo", {"<Control>y", "<Control><Shift>z"});
            set_accels_for_action("app.cut", {"<Control>x"});
            set_accels_for_action("app.copy", {"<Control>c"});
            set_accels_for_action("app.paste", {"<Control>v"});
            set_accels_for_action("app.select-all", {"<Control>a"});
            set_accels_for_action("app.find", {"<Control>f"});
            set_accels_for_action("app.find-replace", {"<Control>h"});
            set_accels_for_action("app.find-next", {"F3"});
            set_accels_for_action("app.fullscreen", {"F11"});
            set_accels_for_action("app.settings", {"<Control>comma"});
            set_accels_for_action("win.close", {"<Control>w"});

            main_window.notify["fullscreened"].connect(sync_actions);
            settings.changed["recent-files"].connect(refresh_recent_menu);
            refresh_recent_menu();
        }

        private void add_simple(string name, owned GLib.Func<SimpleAction> cb) {
            var act = new SimpleAction(name, null);
            act.activate.connect(() => cb(act));
            add_action(act);
        }

        private void refresh_recent_menu() {
            _recent_menu.remove_all();
            int shown = 0;
            foreach (string uri in settings.get_strv("recent-files")) {
                if (shown >= 10) break;
                if (uri.down().has_suffix(".pdf")) continue;
                var f = GLib.File.new_for_uri(uri);
                if (!f.query_exists()) continue;
                shown++;
                var item = new GLib.MenuItem(f.get_basename(), null);
                item.set_action_and_target_value("app.open-recent", new Variant.string(uri));
                _recent_menu.append_item(item);
            }
            if (shown == 0) _recent_menu.append(_("No Recent Documents"), null);
        }

        private void set_enabled(string name, bool enabled) {
            var act = lookup_action(name) as SimpleAction;
            if (act != null) act.set_enabled(enabled);
        }

        private void sync_actions() {
            if (_layout_stack == null || main_window == null) return;
            bool doc = layout() != "start";
            bool md = in_markdown();
            bool rich = in_rich();
            bool editable = rich ? _rich.editable() : (md && _md_stack != null && _md_stack.visible_child_name != "V");
            foreach (string name in new string[] { "save", "save-as", "save-online", "print", "close-document", "find",
                                                   "find-replace", "find-next", "find-previous", "export", "page-setup",
                                                   "save-as-template", "select-all", "copy" })
                set_enabled(name, doc);
            set_enabled("share", doc && (rich ? _rich.file != null : current_file != null));
            if (rich) {
                set_enabled("undo", _rich.ed.undo.can_undo);
                set_enabled("redo", _rich.ed.undo.can_redo);
                set_enabled("cut", editable);
                set_enabled("paste", editable);
            } else {
                set_enabled("undo", md && _md_buffer != null && _md_buffer.can_undo);
                set_enabled("redo", md && _md_buffer != null && _md_buffer.can_redo);
                set_enabled("cut", editable && _md_buffer != null && _md_buffer.has_selection);
                set_enabled("paste", editable);
            }
            set_enabled("md-view", md);
            set_enabled("outline", md);
            foreach (string n in WriteActions.names()) {
                var a = lookup_action("doc-" + n) as SimpleAction;
                if (a != null) a.set_enabled(rich);
            }
            var md_view = lookup_action("md-view") as SimpleAction;
            if (md_view != null && _md_stack != null)
                md_view.set_state(new Variant.string(_md_stack.visible_child_name ?? "S"));
            var outline = lookup_action("outline") as SimpleAction;
            if (outline != null) outline.set_state(new Variant.boolean(_rich.sidebar_shown()));
            var fullscreen_act = lookup_action("fullscreen") as SimpleAction;
            if (fullscreen_act != null) fullscreen_act.set_state(new Variant.boolean(main_window.fullscreened));
            if (_context_switcher != null) _context_switcher.visible = rich && _rich.fbar.visible;
            if (_md_switcher != null) _md_switcher.visible = md;
        }

        private void watch_buffer(Gtk.TextBuffer buf) {
            buf.notify["can-undo"].connect(sync_actions);
            buf.notify["can-redo"].connect(sync_actions);
            buf.notify["has-selection"].connect(sync_actions);
        }

        private void new_markdown_note() {
            var preset = WriteTemplates.get_default().find(settings.get_string("default-template"));
            if (preset != null && preset.id != WriteTemplates.BLANK) {
                new_markdown_from_template(preset);
                return;
            }
            _is_markdown = true;
            enter_markdown_mode();
            _md_buffer.set_text("", -1);
            current_file = null;
            _suggested_name = null;
            modified = false;
            update_title();
            _layout_stack.visible_child_name = "markdown";
            set_doc_bubbles_visible(true);
        }

        private void start_from_template(WriteTemplate t) {
            guard_unsaved(() => new_document_from_template(t));
        }

        private void new_document_from_template(WriteTemplate t) {
            string body = WriteTemplates.get_default().instantiate(t);
            Write.Document d;
            try {
                d = Write.Formats.load(body.data, Write.FileFormat.MARKDOWN);
            } catch (Error e) {
                toast(e.message);
                return;
            }
            if (t.id != WriteTemplates.BLANK) d.meta.title = t.name;
            show_rich_document(d, null, default_format());
            _rich.modified = false;
            update_title();
        }

        private void new_markdown_from_template(WriteTemplate t) {
            string body = WriteTemplates.get_default().instantiate(t);
            _is_markdown = true;
            enter_markdown_mode();
            _md_buffer.begin_irreversible_action();
            _md_buffer.set_text(body, -1);
            _md_buffer.end_irreversible_action();
            Gtk.TextIter start;
            _md_buffer.get_start_iter(out start);
            _md_buffer.place_cursor(start);
            current_file = null;
            _suggested_name = t.id == WriteTemplates.BLANK ? null : t.name;
            modified = false;
            update_title();
            _layout_stack.visible_child_name = "markdown";
            set_doc_bubbles_visible(true);
            GLib.Idle.add(() => { update_md_preview(); return GLib.Source.REMOVE; });
        }

        private void on_save_as_template() {
            if (in_rich()) {
                on_save_as(null, true);
                return;
            }
            if (!_is_markdown || !_md_ui_built) return;
            string suggested = current_file != null
                ? WriteTemplates.display_name(current_file.get_basename())
                : (_suggested_name ?? "");
            WriteTemplateDialogs.save_as(this, main_window, _md_buffer.text, suggested, (t) => {
                toast(_("Saved as template “%s”").printf(t.name));
            });
        }

        private GLib.List<Widget> _doc_bubbles = new GLib.List<Widget>();
        private Button? _outline_bubble = null;
        private Singularity.Widgets.BubbleSwitcher? _context_switcher = null;
        private Singularity.Widgets.BubbleSwitcher? _md_switcher = null;
        private Singularity.Widgets.SearchBubble? _search_bubble = null;
        private bool _md_switch_sync = false;

        private void track_bubble(Widget w) {
            _doc_bubbles.append(w);
        }

        public void set_doc_bubbles_visible(bool visible) {
            foreach (var w in _doc_bubbles) w.visible = visible;
            if (visible) {
                if (_md_switcher != null) _md_switcher.visible = in_markdown();
                if (_context_switcher != null) _context_switcher.visible = in_rich() && _rich.fbar.visible;
                if (word_count_label != null) word_count_label.visible = in_markdown();
            }
        }

        private void toggle_sidebar() {
            if (layout() == "start") return;
            _rich.show_left(!_rich.sidebar_shown());
        }

        private void build_toolbar() {
            track_bubble(main_window.add_bubble_icon(
                "go-previous-symbolic", _("Back to Start (close document)"),
                () => on_close_document()));

            _outline_bubble = main_window.add_bubble_icon("sidebar-show-symbolic", _("Sidebar"), () => toggle_sidebar());
            track_bubble(_outline_bubble);

            _rich.fbar.attach(main_window);
            _context_switcher = _rich.fbar.tabs;
            main_window.set_bubble_priority(_context_switcher, 10);
            track_bubble(_context_switcher);

            _md_switcher = new Singularity.Widgets.BubbleSwitcher();
            _md_switcher.add_option("R", _("Source"));
            _md_switcher.add_option("S", _("Split"));
            _md_switcher.add_option("V", _("Preview"));
            _md_switcher.set_active("S");
            _md_switcher.selected.connect((n) => {
                if (_md_switch_sync || _md_stack == null) return;
                _md_stack.visible_child_name = n;
            });
            main_window.add_bubble_widget(_md_switcher);
            main_window.set_bubble_priority(_md_switcher, 10);
            track_bubble(_md_switcher);

            _search_bubble = main_window.add_bubble_search(_("Search Document"), (t) => on_search_changed(t));
            _search_bubble.entry.activate.connect(() => {
                if (in_rich()) _rich.nav.search_next();
                else if (_search_bubble.text != "") do_find(_search_bubble.text, true);
            });
            track_bubble(_search_bubble);
            _rich.nav.focus_search_requested.connect((seed) => focus_search_bubble(seed));
            _rich.nav.clear_search_requested.connect(() => _search_bubble.clear());

            var save_btn = main_window.add_bubble_icon("document-save-symbolic", _("Save (Ctrl+S)"), () => {});
            save_btn.clicked.connect(() => WriteRibbon.popup_menu(save_btn, (menu) => {
                menu.add_item(_("Save"), "document-save-symbolic", () => save_current(null));
                menu.add_item(_("Save As\u2026"), "document-save-as-symbolic", () => on_save_as(null));
                menu.add_item(_("Save to Online Account\u2026"), "folder-remote-symbolic", () => on_save_online());
                menu.add_item(_("Save as Template\u2026"), "document-new-symbolic", () => on_save_as_template());
                menu.add_separator();
                var ex = menu.add_submenu(_("Export"), "document-send-symbolic");
                ex.add_css_class("write-menu");
                string[,] formats = {
                    { _("Word Document (.docx)\u2026"), "docx" },
                    { _("OpenDocument Text (.odt)\u2026"), "odt" },
                    { _("Rich Text Format (.rtf)\u2026"), "rtf" },
                    { _("PDF\u2026"), "pdf" },
                    { _("Web Page (.html)\u2026"), "html" },
                    { _("Markdown (.md)\u2026"), "md" },
                    { _("EPUB Book (.epub)\u2026"), "epub" },
                    { _("Plain Text (.txt)\u2026"), "txt" }
                };
                for (int i = 0; i < formats.length[0]; i++) {
                    string ext = formats[i, 1];
                    ex.add_item(formats[i, 0], null, () => activate_action("export", new Variant.string(ext)));
                }
                menu.add_item(_("Print\u2026"), "printer-symbolic", () => on_print());
                menu.add_item(_("Page Setup\u2026"), "document-page-setup-symbolic", () => activate_action("page-setup", null));
                if (in_rich()) {
                    menu.add_separator();
                    menu.add_item(_("Version History\u2026"), "document-open-recent-symbolic", () => _rich.run("versions", null));
                    menu.add_item(_("Properties\u2026"), "document-properties-symbolic", () => _rich.run("properties", null));
                }
            }));
            track_bubble(save_btn);

            var share_btn = main_window.add_bubble_icon("singularity-share-symbolic", _("Share"),
                                       () => activate_action("share", null));
            lookup_action("share").bind_property("enabled", share_btn, "sensitive", BindingFlags.SYNC_CREATE);
            track_bubble(share_btn);

            word_count_label = main_window.add_bubble_label(_("0 words"), main_window.force_ssd);
            track_bubble(word_count_label);

            set_doc_bubbles_visible(false);
        }

        private void focus_search_bubble(string seed) {
            if (_search_bubble == null) return;
            if (seed != "") _search_bubble.text = seed;
            _search_bubble.grab_focus_entry();
        }

        private void on_search_changed(string t) {
            if (in_rich()) {
                _rich.nav.search_for(t.strip());
                return;
            }
            if (in_markdown() && t != "") {
                _last_search_query = t;
                do_find(t, true);
            }
        }

        private void build_layout() {
            var root = main_window.root;
            var content_hbox = main_window.content_hbox;

            outline_box = new Box(Orientation.VERTICAL, 2);
            outline_box.add_css_class("write-outline-list");
            var md_empty = WriteNavigationPane.section_page("write-outline", _("Outline"), _("This note has no headings yet. Lines that start with # appear here."));
            md_empty.add_action("write-outline", _("Add Heading"), _("Turn the current line into a heading"), () => add_md_heading());
            md_empty.visible = true;
            _md_outline_empty = md_empty;
            outline_box.append(_md_outline_empty);
            _rich.nav.add_page("markdown", outline_box, null);
            main_window.set_sidebar(_rich.nav);
            main_window.set_sidebar_visible(false);

            find_bar = new Singularity.Widgets.FindReplaceBar();
            find_bar.find_next.connect((q) => { _last_search_query = q; do_find(q, true); });
            find_bar.find_prev.connect((q) => { _last_search_query = q; do_find(q, false); });
            find_bar.replace_one.connect(do_replace_one);
            find_bar.replace_all.connect(do_replace_all);
            find_bar.closed.connect(() => {
                find_bar.reveal_child = false;
                if (_md_ui_built) active_view().grab_focus();
            });

            _layout_stack = new Gtk.Stack();
            _layout_stack.hexpand = true;
            _layout_stack.vexpand = true;
            _layout_stack.transition_type = Gtk.StackTransitionType.CROSSFADE;
            _layout_stack.transition_duration = 150;
            _layout_stack.add_named(_rich, "rich");
            build_start_page();
            _layout_stack.notify["visible-child-name"].connect(() => {
                _rich.nav.set_markdown(in_markdown());
                if (layout() == "start") main_window.set_sidebar_visible(false);
                sync_actions();
            });

            content_hbox.append(_layout_stack);

            root.append(find_bar);

            main_window.set_content(root);
        }

        private void build_start_page() {
            var wp = new Singularity.Widgets.WelcomePage();
            wp.app_icon_name = "dev.sinty.write";
            wp.title = _("Write");
            wp.subtitle = _("Documents, letters, reports and Markdown notes");

            wp.add_action(
                "x-office-document",
                _("New Document"),
                _("A page-based document with styles,\ntables, pictures and references."),
                () => activate_action("new", null)
            );
            wp.add_action(
                "text-x-generic",
                _("New Markdown Note"),
                _("Plain-text format with Source,\nSplit and Preview modes."),
                () => activate_action("new-markdown", null)
            );
            wp.add_action(
                "folder-open",
                _("Open"),
                _("Word, OpenDocument, RTF, EPUB,\nweb pages and Markdown."),
                () => on_open()
            );

            var recent_wrap = new Box(Orientation.VERTICAL, 12);

            _recovered_box = new Box(Orientation.VERTICAL, 12);
            recent_wrap.append(_recovered_box);

            var recent_section_lbl = new Label(_("Recent"));
            recent_section_lbl.add_css_class("title-2");
            recent_section_lbl.halign = Align.START;

            var recent_list = new Box(Orientation.VERTICAL, 2);
            recent_list.add_css_class("write-recent-list");
            _recent_list_box = recent_list;
            refresh_recent_list(recent_list);

            recent_wrap.append(recent_section_lbl);
            recent_wrap.append(recent_list);
            wp.add_action("x-office-document-template", _("Browse Templates"),
                          _("Meeting notes, reports, letters and more"),
                          () => activate_action("new-from-template", null));
            _start_gallery = new WriteTemplateGallery(132, 4, 8);
            _start_gallery.chosen.connect((t) => start_from_template(t));
            _start_gallery.rename_requested.connect((t) => WriteTemplateDialogs.rename(this, main_window, t));
            _start_gallery.delete_requested.connect((t) => WriteTemplateDialogs.confirm_delete(this, main_window, t));
            var start_extra = new Box(Orientation.VERTICAL, 24);
            start_extra.append(_start_gallery);
            start_extra.append(recent_wrap);
            Singularity.Widgets.apply_titlebar_inset(start_extra);
            wp.set_extra_widget(start_extra);

            _layout_stack.add_named(wp, "start");
        }

        private void refresh_recovered() {
            if (_recovered_box == null) return;
            Widget? w;
            while ((w = _recovered_box.get_first_child()) != null) _recovered_box.remove(w);
            var list = WriteFiles.recovered(in_rich() ? _rich.recovery_id : null);
            if (list.size == 0) return;
            var lbl = new Label(_("Recovered"));
            lbl.add_css_class("title-2");
            lbl.halign = Align.START;
            _recovered_box.append(lbl);
            var box = new Box(Orientation.VERTICAL, 2);
            box.add_css_class("write-recent-list");
            foreach (var rec in list) {
                var row = new Box(Orientation.HORIZONTAL, 12);
                row.add_css_class("write-recent-row");
                row.margin_top = 6;
                row.margin_bottom = 6;
                row.margin_start = 12;
                row.margin_end = 12;
                var icon = new Image.from_icon_name("x-office-document-symbolic");
                icon.pixel_size = 20;
                var text = new Box(Orientation.VERTICAL, 2);
                text.hexpand = true;
                string origin = rec.origin != "" ? GLib.File.new_for_uri(rec.origin).get_basename() : _("Unsaved document");
                var name = new Label(origin);
                name.halign = Align.START;
                name.ellipsize = Pango.EllipsizeMode.END;
                var when = new Label(_("Autosaved %s").printf(rec.when));
                when.halign = Align.START;
                when.add_css_class("dim-label");
                when.add_css_class("caption");
                text.append(name);
                text.append(when);
                var open_btn = new Button.with_label(_("Open"));
                open_btn.valign = Align.CENTER;
                var r = rec;
                open_btn.clicked.connect(() => open_recovered(r));
                var discard = new Button.with_label(_("Discard"));
                discard.valign = Align.CENTER;
                discard.clicked.connect(() => {
                    WriteFiles.discard_recovered(r);
                    refresh_recovered();
                });
                row.append(icon);
                row.append(text);
                row.append(discard);
                row.append(open_btn);
                box.append(row);
            }
            _recovered_box.append(box);
        }

        private void open_recovered(WriteFiles.Recovered rec) {
            try {
                Write.FileFormat fmt;
                var d = WriteFiles.load(GLib.File.new_for_path(rec.path), out fmt);
                GLib.File? origin = rec.origin != "" ? GLib.File.new_for_uri(rec.origin) : null;
                var ofmt = Write.FileFormat.from_extension("x." + rec.ext);
                show_rich_document(d, origin, ofmt.writable() && ofmt.rich() ? ofmt : default_format());
                WriteFiles.discard_recovered(rec);
                _rich.modified = true;
                update_title();
                toast(_("Recovered document opened. Save it to keep the changes."));
            } catch (Error e) {
                toast(e.message);
            }
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
            Gtk.RecentManager.get_default().add_item(uri);
        }

        private void refresh_recent_list(Box list) {
            while (list.get_first_child() != null)
                list.remove(list.get_first_child());

            string[] uris = settings.get_strv("recent-files");
            int shown = 0;
            foreach (string uri in uris) {
                if (shown >= 10) break;
                if (uri.down().has_suffix(".pdf")) continue;
                var f = GLib.File.new_for_uri(uri);
                if (!f.query_exists()) continue;
                shown++;

                string path = f.get_path() ?? uri;
                string fname = f.get_basename() ?? uri;
                string fpath = path.replace(GLib.Environment.get_home_dir(), "~");
                string lu = uri.down();
                bool is_md = lu.has_suffix(".md") || lu.has_suffix(".markdown") || lu.has_suffix(".txt");

                string date_str = "";
                try {
                    var info = f.query_info(GLib.FileAttribute.TIME_MODIFIED, GLib.FileQueryInfoFlags.NONE);
                    var mtime = info.get_modification_date_time();
                    if (mtime != null) date_str = format_recent_date(mtime);
                } catch {}

                var row = new Button();
                row.has_frame = false;
                row.add_css_class("write-recent-row");

                var row_box = new Box(Orientation.HORIZONTAL, 12);
                row_box.margin_top = 8; row_box.margin_bottom = 8;
                row_box.margin_start = 12; row_box.margin_end = 12;

                var row_icon = new Image.from_icon_name(is_md ? "text-x-generic-symbolic" : "x-office-document-symbolic");
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
                var empty = new Label(_("No recent documents"));
                empty.add_css_class("dim-label");
                empty.margin_top = 16;
                list.append(empty);
            }
        }

        private string format_recent_date(GLib.DateTime dt) {
            var now = new GLib.DateTime.now_local();
            var diff = now.difference(dt);
            if (diff < GLib.TimeSpan.DAY) return _("Today");
            if (diff < 2 * GLib.TimeSpan.DAY) return _("Yesterday");
            if (diff < 7 * GLib.TimeSpan.DAY) return dt.format("%A");
            return dt.format("%d %b %Y");
        }

        private void show_start_page() {
            if (_start_gallery != null) _start_gallery.refresh();
            if (_recent_list_box != null) refresh_recent_list(_recent_list_box);
            _layout_stack.visible_child_name = "start";
            refresh_recovered();
            toolbar.set_title_widget(null);
            toolbar.set_title(_("Write"));
            main_window.title = _("Write");
            set_doc_bubbles_visible(false);
            main_window.set_sidebar_visible(false);
            sync_actions();
        }

        private void setup_keyboard() {
            var kc = new EventControllerKey();
            kc.key_pressed.connect((kv, kc2, state) => {
                bool shift = (state & ModifierType.SHIFT_MASK) != 0;
                if (in_markdown() && kv == Key.F3 && shift) {
                    if (_last_search_query != "") do_find(_last_search_query, false);
                    else find_bar.open_find();
                    return true;
                }
                if (kv == Key.Escape && find_bar.reveal_child) {
                    find_bar.reveal_child = false;
                    if (_md_ui_built) active_view().grab_focus();
                    return true;
                }
                return false;
            });
            ((Gtk.Widget) main_window).add_controller(kc);
        }

        private void setup_autosave() {
            int interval = settings.get_int("autosave-interval");
            if (interval <= 0) interval = 0;
            autosave_id = GLib.Timeout.add_seconds(interval > 0 ? interval : 60, () => {
                if (in_rich() && _rich.modified) {
                    WriteFiles.write_recovery(_rich);
                    if (interval > 0 && _rich.file != null && _rich.format.writable() && _rich.format.rich()) rich_write(_rich.file, _rich.format, false);
                } else if (in_markdown() && modified && current_file != null && interval > 0) {
                    md_write(current_file);
                }
                return GLib.Source.CONTINUE;
            });
        }

        private void setup_markdown_mode() {
            if (_md_ui_built) return;
            _md_ui_built = true;

            var lm = GtkSource.LanguageManager.get_default();
            var lang = lm.get_language("markdown");
            _md_buffer = new GtkSource.Buffer.with_language(lang);
            _md_buffer.changed.connect(on_md_source_changed);
            watch_buffer(_md_buffer);
            update_md_color_scheme();

            _md_source_view   = make_md_sourceview();
            _md_source_view_s = make_md_sourceview();
            var s_view        = _md_source_view_s;

            _md_preview_s = make_md_webview();
            _md_preview_v = make_md_webview();

            var r_scroll = new ScrolledWindow();
            r_scroll.hexpand = true; r_scroll.vexpand = true;
            r_scroll.set_child(_md_source_view);

            var md_paned = new Gtk.Paned(Orientation.HORIZONTAL);
            md_paned.hexpand = true; md_paned.vexpand = true;
            md_paned.wide_handle = false;
            var s_source_scroll = new ScrolledWindow();
            s_source_scroll.hexpand = true; s_source_scroll.vexpand = true;
            s_source_scroll.set_child(s_view);
            md_paned.set_start_child(s_source_scroll);
            _md_preview_stack_s = make_md_preview_stack(_md_preview_s);
            md_paned.set_end_child(_md_preview_stack_s);
            md_paned.position = 480;

            var v_box = new Box(Orientation.VERTICAL, 0);
            v_box.hexpand = true; v_box.vexpand = true;
            _md_preview_stack_v = make_md_preview_stack(_md_preview_v);
            v_box.append(_md_preview_stack_v);

            _md_stack = new Gtk.Stack();
            _md_stack.transition_type = Gtk.StackTransitionType.NONE;
            _md_stack.hexpand = true; _md_stack.vexpand = true;
            _md_stack.add_titled(r_scroll,  "R", _("Source"));
            _md_stack.add_titled(md_paned,  "S", _("Split"));
            _md_stack.add_titled(v_box,     "V", _("Preview"));
            _md_stack.visible_child_name = "S";
            _md_stack.add_css_class("write-markdown");

            build_md_switcher();

            _layout_stack.add_named(_md_stack, "markdown");
        }

        private GtkSource.View make_md_sourceview() {
            return new Singularity.Widgets.SourceView(_md_buffer);
        }

        private Gtk.Stack make_md_preview_stack(WebKit.WebView view) {
            var empty = new Singularity.Widgets.StatusPage();
            empty.icon_name = "dev.sinty.write";
            empty.title = _("Nothing to Preview");
            empty.description = _("Start writing to see the formatted document here.");
            var stack = new Gtk.Stack();
            stack.hexpand = true; stack.vexpand = true;
            stack.add_named(view, "preview");
            stack.add_named(empty, "empty");
            stack.visible_child_name = "empty";
            return stack;
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
                            set_md_scheme(scheme);
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
            if (scheme != null) set_md_scheme(scheme);
        }

        private void set_md_scheme(GtkSource.StyleScheme scheme) {
            string accent = Singularity.Style.StyleManager.get_default().accent_hex;
            string id = "write-accent-" + scheme.id;
            string dir = GLib.Path.build_filename(
                GLib.Environment.get_user_cache_dir(), "singularity", "schemes");
            var xml = new StringBuilder();
            xml.append_printf("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<style-scheme id=\"%s\" name=\"%s\" parent-scheme=\"%s\" version=\"1.0\">\n",
                id, Markup.escape_text(scheme.name), scheme.id);
            foreach (string style in new string[] { "def:underlined", "def:link-text", "def:link-destination",
                                                    "markdown:url", "markdown:link-text", "markdown:link-destination",
                                                    "markdown:image-marker", "markdown:email-address" }) {
                xml.append_printf("  <style name=\"%s\" foreground=\"%s\"/>\n", style, accent);
            }
            xml.append("</style-scheme>\n");
            try {
                DirUtils.create_with_parents(dir, 0755);
                FileUtils.set_contents(GLib.Path.build_filename(dir, id + ".xml"), xml.str);
                var sm = GtkSource.StyleSchemeManager.get_default();
                bool known = false;
                foreach (string path in sm.get_search_path()) if (path == dir) known = true;
                if (!known) sm.append_search_path(dir);
                sm.force_rescan();
                var derived = sm.get_scheme(id);
                _md_buffer.style_scheme = derived != null ? derived : scheme;
            } catch (Error e) {
                _md_buffer.style_scheme = scheme;
            }
        }

        private void build_md_switcher() {
            _md_stack.notify["visible-child-name"].connect(() => {
                string cur = _md_stack.visible_child_name;
                if (cur == "R" || cur == "S") {
                    GLib.Idle.add(() => {
                        _md_source_view?.grab_focus();
                        return GLib.Source.REMOVE;
                    });
                }
                if (_md_switcher != null) {
                    _md_switch_sync = true;
                    _md_switcher.set_active(cur);
                    _md_switch_sync = false;
                }
                sync_actions();
            });
        }

        private void enter_markdown_mode() {
            setup_markdown_mode();
            _layout_stack.visible_child_name = "markdown";
            set_doc_bubbles_visible(true);
            GLib.Idle.add(() => {
                if (in_markdown() && settings.get_boolean("show-outline") && main_window.get_width() >= 1500) main_window.set_sidebar_visible(true);
                return GLib.Source.REMOVE;
            });
            GLib.Idle.add(() => { update_outline(); return GLib.Source.REMOVE; });
        }

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
            var ink = (_md_preview_s ?? _md_preview_v).get_color();
            bool dark = 0.2126 * ink.red + 0.7152 * ink.green + 0.0722 * ink.blue > 0.5;
            string html = parser.to_full_html(md_text, Singularity.Style.StyleManager.get_default().accent_hex, dark, main_window.floating_bubbles ? 60 : 24);
            string shown = md_text.strip() == "" ? "empty" : "preview";
            if (_md_preview_stack_s != null) _md_preview_stack_s.visible_child_name = shown;
            if (_md_preview_stack_v != null) _md_preview_stack_v.visible_child_name = shown;
            if (_md_preview_s != null) _md_preview_s.load_html(html, null);
            if (_md_preview_v != null) _md_preview_v.load_html(html, null);
        }


        private void mark_modified() {
            if (!modified) {
                modified = true;
                update_title();
            }
        }

        private void update_word_count() {
            if (_md_buffer == null) return;
            string txt = _md_buffer.text;
            int cnt = 0;
            foreach (var w in txt.split_set(" \t\n\r")) if (w.strip() != "") cnt++;
            word_count_label.label = ngettext("%d word", "%d words", cnt).printf(cnt);
        }

        private void add_md_heading() {
            if (_md_buffer == null) return;
            Gtk.TextIter it;
            _md_buffer.get_iter_at_mark(out it, _md_buffer.get_insert());
            it.set_line_offset(0);
            var end = it;
            if (!end.ends_line()) end.forward_to_line_end();
            string line = _md_buffer.get_text(it, end, false);
            _md_buffer.begin_user_action();
            if (!line.has_prefix("#")) _md_buffer.insert(ref it, line.strip() == "" ? "# " + _("Heading") : "# ", -1);
            _md_buffer.end_user_action();
            active_view().grab_focus();
        }

        private void update_outline() {
            while (outline_box.get_first_child() != null) outline_box.remove(outline_box.get_first_child());
            outline_box.append(_md_outline_empty);
            if (_md_buffer == null) return;
            string[] lines = _md_buffer.text.split("\n");
            int line_no = 0;
            foreach (string raw in lines) {
                int this_line = line_no++;
                string line = raw.strip();
                int level = 0;
                if (line.has_prefix("#### ")) { level = 4; line = line.substring(5); }
                else if (line.has_prefix("### ")) { level = 3; line = line.substring(4); }
                else if (line.has_prefix("## ")) { level = 2; line = line.substring(3); }
                else if (line.has_prefix("# ")) { level = 1; line = line.substring(2); }
                if (level == 0) continue;
                line = line.strip();
                if (line == "") continue;
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
                row.margin_start = (level - 1) * 12;
                row.clicked.connect(() => {
                    Gtk.TextIter it;
                    _md_buffer.get_iter_at_line(out it, this_line);
                    _md_buffer.place_cursor(it);
                    active_view().scroll_to_mark(_md_buffer.get_insert(), 0.1, true, 0, 0.2);
                    active_view().grab_focus();
                });
                outline_box.append(row);
                _md_outline_empty.visible = false;
            }
            _md_outline_empty.visible = outline_box.get_first_child() == _md_outline_empty && _md_outline_empty.get_next_sibling() == null;
        }

        private async void insert_md_equation() {
            if (!FormulaBridge.available()) {
                toast(_("Install Formula to insert equations"));
                return;
            }
            string target = FormulaBridge.new_target();
            if (!(yield FormulaBridge.edit(target, null))) return;
            string? tex = FormulaBridge.latex_for(target);
            FormulaBridge.discard(target);
            if (tex == null || _md_buffer == null) return;
            _md_buffer.insert_at_cursor("$$" + tex + "$$", -1);
        }

        private Gtk.TextView active_view() {
            if (_md_stack != null && _md_stack.visible_child_name == "S" && _md_source_view_s != null)
                return _md_source_view_s;
            return _md_source_view;
        }

        private void do_find(string q, bool fwd) {
            if (q == "" || _md_buffer == null) return;
            var buf = _md_buffer;
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
            if (q == "" || _md_buffer == null) {
                find_bar.set_match_info(0, 0);
                return;
            }
            var buf = _md_buffer;
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
            if (_md_buffer == null) return;
            var buf = _md_buffer;
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
            do_find(q, true);
        }

        private void do_replace_all(string q, string rep) {
            if (q == "" || _md_buffer == null) return;
            var buf = _md_buffer;
            Gtk.TextIter it, ms, me;
            buf.get_start_iter(out it);
            var flags = Gtk.TextSearchFlags.CASE_INSENSITIVE | Gtk.TextSearchFlags.TEXT_ONLY;
            int cnt = 0;
            buf.begin_user_action();
            while (it.forward_search(q, flags, out ms, out me, null)) {
                buf.delete(ref ms, ref me);
                buf.insert(ref ms, rep, -1);
                it = ms;
                it.forward_chars(rep.char_count());
                cnt++;
            }
            buf.end_user_action();
            find_bar.set_match_info(cnt, 0);
        }

        private void update_title() {
            string n;
            bool mod;
            if (in_rich()) {
                n = _rich.title();
                mod = _rich.modified;
            } else {
                if (current_file != null) n = current_file.get_basename();
                else if (_suggested_name != null) n = _suggested_name;
                else n = _("Untitled");
                mod = modified;
                if (n.has_suffix(".md")) n = n[0:n.length - 3];
            }
            toolbar.set_title(mod ? n + " *" : n);
            main_window.title = n;
            sync_actions();
        }

        private Write.FileFormat default_format() {
            string f = settings.get_string("default-save-format");
            var fmt = Write.FileFormat.from_extension("x." + f);
            return fmt.writable() && fmt.rich() ? fmt : Write.FileFormat.DOCX;
        }

        private void show_rich_document(Write.Document d, GLib.File? file, Write.FileFormat fmt) {
            _is_markdown = false;
            _rich.file = file;
            _rich.format = fmt;
            _rich.recovery_id = Uuid.string_random();
            _rich.set_document(d);
            _layout_stack.visible_child_name = "rich";
            toolbar.set_title_widget(null);
            set_doc_bubbles_visible(true);
            if (_search_bubble != null && _search_bubble.text != "") _search_bubble.clear();
            main_window.set_sidebar_visible(false);
            GLib.Idle.add(() => {
                if (in_rich()) main_window.set_sidebar_visible(settings.get_boolean("show-outline") && main_window.get_width() >= 1500);
                return GLib.Source.REMOVE;
            });
            _rich.nav.refresh();
            update_title();
            if (_rich.has_document_scripts()) {
                var dlg = new Singularity.Widgets.ConfirmDialog((Gtk.Application) this,
                    _("Enable Scripts?"), "dialog-warning-symbolic",
                    _("This document contains scripts that can change it when it is opened, saved or printed. Enable them only if you trust where the document comes from."),
                    _("Enable Scripts"), Singularity.Widgets.ConfirmDialog.ActionStyle.SUGGESTED);
                dlg.transient_for = main_window;
                dlg.response.connect((r) => {
                    if (r != Singularity.Widgets.ConfirmDialog.Response.PRIMARY) return;
                    _rich.load_document_scripts(true);
                    _rich.fire_script_event("open");
                });
                dlg.present();
            }
            GLib.Idle.add(() => {
                _rich.view.grab_focus();
                return GLib.Source.REMOVE;
            });
        }

        private void new_document() {
            show_rich_document(Write.Document.create_blank(), null, default_format());
        }

        private void on_close_document() {
            guard_unsaved(() => {
                _rich.modified = false;
                modified = false;
                show_start_page();
            });
        }

        private void on_open() {
            var fd = new FileDialog();
            set_documents_folder(fd);
            fd.title = _("Open Document");
            var flist = new GLib.ListStore(typeof(FileFilter));
            flist.append(WriteFiles.all_documents());
            foreach (var f in new Write.FileFormat[] { Write.FileFormat.DOCX, Write.FileFormat.ODT, Write.FileFormat.RTF, Write.FileFormat.DOC, Write.FileFormat.HTML, Write.FileFormat.EPUB, Write.FileFormat.MARKDOWN, Write.FileFormat.TEXT })
                flist.append(WriteFiles.filter_for(f));
            fd.filters = flist;
            fd.open.begin(main_window, null, (o, r) => {
                try {
                    var file = fd.open.end(r);
                    if (file != null) do_open(file);
                } catch (Error e) {
                }
            });
        }

        private void do_open(GLib.File file) {
            guard_unsaved(() => open_now(file));
        }

        private void open_now(GLib.File file) {
            string? path = file.get_path();
            if (path == null) {
                toast(_("Only local files can be opened."));
                return;
            }
            uint8[] data;
            try {
                FileUtils.get_data(path, out data);
            } catch (Error e) {
                toast(e.message);
                return;
            }
            var fmt = Write.Formats.sniff(data, file.get_basename());
            if (fmt == Write.FileFormat.PDF) {
                GLib.AppInfo.launch_default_for_uri_async.begin(file.get_uri(), null, null);
                return;
            }
            if (fmt == Write.FileFormat.MARKDOWN || fmt == Write.FileFormat.TEXT) {
                open_markdown(file, Write.Formats.decode_text(data));
                return;
            }
            Write.Document d;
            try {
                Write.FileFormat f2;
                d = WriteFiles.load(file, out f2);
            } catch (Error e) {
                toast(_("“%s” could not be opened: %s").printf(file.get_basename(), e.message));
                return;
            }
            if (fmt == Write.FileFormat.DOTX || fmt == Write.FileFormat.OTT) {
                show_rich_document(d, null, fmt == Write.FileFormat.OTT ? Write.FileFormat.ODT : Write.FileFormat.DOCX);
                return;
            }
            show_rich_document(d, file, fmt);
            add_to_recent(file);
            if (!fmt.writable()) {
                toast(_("%s files are opened read and write, and are saved as a new Word document.").printf(fmt.label()));
            }
        }

        private void open_markdown(GLib.File file, string contents) {
            _is_markdown = true;
            enter_markdown_mode();
            _md_buffer.begin_irreversible_action();
            _md_buffer.set_text(contents, -1);
            _md_buffer.end_irreversible_action();
            current_file = file;
            add_to_recent(file);
            modified = false;
            update_title();
            GLib.Idle.add(() => { update_md_preview(); return GLib.Source.REMOVE; });
        }

        private void save_current(owned Done? after) {
            if (in_rich()) {
                if (_rich.file == null || !_rich.format.writable()) {
                    on_save_as((owned) after);
                    return;
                }
                if (rich_write(_rich.file, _rich.format) && after != null) after();
                return;
            }
            if (in_markdown()) {
                if (current_file == null) {
                    on_save_as((owned) after);
                    return;
                }
                if (md_write(current_file) && after != null) after();
            }
        }

        private bool rich_write(GLib.File f, Write.FileFormat fmt, bool keep = true) {
            if (keep) _rich.fire_script_event("save");
            ChartSupport.prepare_all(_rich.doc);
            try {
                WriteFiles.save(_rich, f, fmt, keep && settings.get_boolean("keep-versions"));
            } catch (Error e) {
                toast(_("Could not save “%s”: %s").printf(f.get_basename(), e.message));
                return false;
            }
            _rich.file = f;
            _rich.format = fmt;
            _rich.modified = false;
            _rich.view.filename = f.get_basename();
            WriteFiles.clear_recovery(_rich);
            add_to_recent(f);
            CloudActions.sync_back(main_window, f);
            update_title();
            return true;
        }

        private bool md_write(GLib.File f) {
            try {
                Write.write_atomically(f.get_path(), _md_buffer.text.data);
            } catch (Error e) {
                toast(_("Could not save “%s”: %s").printf(f.get_basename(), e.message));
                return false;
            }
            current_file = f;
            modified = false;
            add_to_recent(f);
            CloudActions.sync_back(main_window, f);
            update_title();
            return true;
        }

        private string base_name() {
            GLib.File? f = in_rich() ? _rich.file : current_file;
            string n;
            if (f != null) n = f.get_basename();
            else if (!in_rich()) n = _suggested_name != null ? _suggested_name : _("Untitled");
            else if (_rich.doc.meta.title != "") n = _rich.doc.meta.title;
            else n = first_line();
            int dot = n.last_index_of_char('.');
            if (f != null && dot > 0) n = n.substring(0, dot);
            return n.replace("/", "-");
        }

        private string first_line() {
            foreach (var b in _rich.doc.body.items) {
                var p = b as Write.Paragraph;
                if (p == null) continue;
                string t = p.plain_text().strip();
                if (t == "") continue;
                if (t.char_count() > 60) t = t.substring(0, t.index_of_nth_char(60)).strip();
                return t;
            }
            return _("Untitled");
        }

        private void set_documents_folder(FileDialog fd) {
            GLib.File? f = in_rich() ? _rich.file : current_file;
            if (f != null && f.get_parent() != null) {
                fd.initial_folder = f.get_parent();
                return;
            }
            string? docs = Environment.get_user_special_dir(UserDirectory.DOCUMENTS);
            if (docs == null || !FileUtils.test(docs, FileTest.IS_DIR)) docs = Environment.get_home_dir();
            fd.initial_folder = GLib.File.new_for_path(docs);
        }

        private void on_save_as(owned Done? after, bool template = false) {
            var fd = new FileDialog();
            set_documents_folder(fd);
            fd.title = template ? _("Save as Template") : _("Save Document");
            var flist = new GLib.ListStore(typeof(FileFilter));
            Write.FileFormat def;
            if (in_markdown()) {
                def = Write.FileFormat.MARKDOWN;
                flist.append(WriteFiles.filter_for(Write.FileFormat.MARKDOWN));
                flist.append(WriteFiles.filter_for(Write.FileFormat.TEXT));
            } else {
                def = template ? Write.FileFormat.DOTX : ((_rich.format.writable() && _rich.format.rich()) ? _rich.format : default_format());
                Write.FileFormat[] kinds = template
                    ? new Write.FileFormat[] { Write.FileFormat.DOTX, Write.FileFormat.OTT }
                    : new Write.FileFormat[] { Write.FileFormat.DOCX, Write.FileFormat.ODT, Write.FileFormat.RTF, Write.FileFormat.DOTX, Write.FileFormat.OTT, Write.FileFormat.HTML, Write.FileFormat.EPUB, Write.FileFormat.MARKDOWN, Write.FileFormat.TEXT };
                foreach (var k in kinds) flist.append(WriteFiles.filter_for(k));
            }
            fd.filters = flist;
            fd.default_filter = (FileFilter) flist.get_item(0);
            for (uint i = 0; i < flist.get_n_items(); i++) {
                var ff = (FileFilter) flist.get_item(i);
                if (ff.name == WriteFiles.format_filter_name(def)) fd.default_filter = ff;
            }
            fd.initial_name = base_name() + "." + def.extension();
            fd.save.begin(main_window, null, (o, r) => {
                GLib.File file;
                try {
                    file = fd.save.end(r);
                } catch (Error e) {
                    return;
                }
                string path = file.get_path();
                var fmt = Write.FileFormat.from_extension(Path.get_basename(path));
                if (in_markdown()) {
                    if (fmt != Write.FileFormat.MARKDOWN && fmt != Write.FileFormat.TEXT) path += ".md";
                    if (md_write(GLib.File.new_for_path(path)) && after != null) after();
                    return;
                }
                if (!fmt.writable() || fmt == Write.FileFormat.PDF) {
                    fmt = def;
                    path += "." + def.extension();
                }
                if (!fmt.rich()) toast(_("Saved as %s. Page layout, comments and tracked changes are not kept in this format.").printf(fmt.label()));
                if (template) {
                    var f = GLib.File.new_for_path(path);
                    try {
                        Write.write_atomically(path, Write.Formats.save(_rich.doc, fmt));
                        toast(_("Saved as template “%s”").printf(f.get_basename()));
                        add_to_recent(f);
                    } catch (Error e) {
                        toast(e.message);
                    }
                    return;
                }
                if (rich_write(GLib.File.new_for_path(path), fmt) && after != null) after();
            });
        }

        private void on_save_online() {
            string name = base_name() + "." + (in_rich() ? ((_rich.format.writable() && _rich.format.rich()) ? _rich.format : default_format()).extension() : "md");
            CloudActions.save.begin(main_window, name, (f) => {
                try {
                    if (in_rich()) Write.write_atomically(f.get_path(), Write.Formats.save(_rich.doc, Write.FileFormat.from_extension(name)));
                    else Write.write_atomically(f.get_path(), _md_buffer.text.data);
                } catch (Error e) {
                    toast(e.message);
                }
            }, (f) => {
                if (in_rich()) {
                    _rich.file = f;
                    _rich.format = Write.FileFormat.from_extension(name);
                    _rich.modified = false;
                } else {
                    current_file = f;
                    modified = false;
                }
                add_to_recent(f);
                update_title();
            });
        }

        private Write.Document? current_document() {
            if (in_rich()) {
                ChartSupport.prepare_all(_rich.doc);
                return _rich.doc;
            }
            if (in_markdown() && _md_buffer != null) {
                try {
                    var d = Write.Formats.load(_md_buffer.text.data, Write.FileFormat.MARKDOWN);
                    d.meta.title = base_name();
                    return d;
                } catch (Error e) {
                    toast(e.message);
                }
            }
            return null;
        }

        private void export_as(Write.FileFormat fmt) {
            if (fmt == Write.FileFormat.UNKNOWN) return;
            var doc = current_document();
            if (doc == null) return;
            var fd = new FileDialog();
            set_documents_folder(fd);
            fd.title = _("Export as %s").printf(fmt.label());
            var flist = new GLib.ListStore(typeof(FileFilter));
            var ff = new FileFilter();
            ff.name = "%s (.%s)".printf(fmt.label(), fmt.extension());
            ff.add_suffix(fmt.extension());
            flist.append(ff);
            fd.filters = flist;
            fd.default_filter = ff;
            fd.initial_name = base_name() + "." + fmt.extension();
            fd.save.begin(main_window, null, (o, r) => {
                GLib.File file;
                try {
                    file = fd.save.end(r);
                } catch (Error e) {
                    return;
                }
                string path = file.get_path();
                if (!path.down().has_suffix("." + fmt.extension())) path += "." + fmt.extension();
                try {
                    if (fmt == Write.FileFormat.PDF) {
                        var ex = new Write.PdfExport(doc);
                        ex.filename = Path.get_basename(path);
                        ex.write_file(path);
                    } else if (fmt == Write.FileFormat.MARKDOWN && in_markdown()) {
                        Write.write_atomically(path, _md_buffer.text.data);
                    } else {
                        Write.write_atomically(path, Write.Formats.save(doc, fmt));
                    }
                    toast(_("Exported “%s”").printf(Path.get_basename(path)));
                } catch (Error e) {
                    toast(_("Export failed: %s").printf(e.message));
                }
            });
        }

        private void on_print() {
            if (in_rich()) {
                _rich.fire_script_event("print");
                _rich.update_fields();
            }
            var doc = current_document();
            if (doc == null) return;
            string title = in_rich() ? _rich.title() : base_name();
            var src = new WritePageSource(doc, title);
            src.filename = title;
            if (in_rich()) {
                src.with_markup = _rich.view.opts.markup != Write.ViewMarkup.FINAL;
                if (_rich.ed.has_selection) {
                    var sel = doc.copy();
                    sel.body.items.clear();
                    foreach (var b in _rich.ed.copy_selection().items) sel.body.add(b);
                    src.selection_doc = sel;
                    src.has_selection = true;
                }
            }
            Singularity.Print.run_source.begin(main_window, src);
        }

        private void setup_styles() {
            add_app_css(WRITE_CSS);
        }

        private const string WRITE_CSS = """
.write-sidebar-actions button:checked {
    background-color: alpha(@accent_color, 0.18);
    color: @accent_color;
}
popover.context-menu.write-menu .menu-row.checked {
    font-weight: 600;
}
popover.context-menu.write-menu button.write-swatch {
    min-width: 0;
    min-height: 0;
    padding: 2px;
    border-radius: 999px;
}
popover.context-menu.write-menu searchentry {
    min-height: 30px;
}
.write-ruler {
    border-bottom: 1px solid alpha(currentColor, 0.08);
    min-height: 24px;
}
.write-docview {
    background-color: @surface_mid;
}
.write-statusbar {
    border-top: 1px solid alpha(currentColor, 0.08);
    padding: 2px 10px;
    min-height: 26px;
}
.write-statusbar button {
    min-height: 22px;
    padding: 0 6px;
}
.write-sidebar-actions {
    border-top: 1px solid alpha(currentColor, 0.08);
    padding: 6px 10px;
}
.write-nav-sidebar .write-outline label {
    padding: 0;
}
.write-pane {
    background-color: @surface_bg;
    border-left: 1px solid alpha(@text_color, 0.07);
    border-right: 1px solid alpha(@text_color, 0.07);
}
.write-comment-card {
    border-radius: 8px;
    padding: 8px 10px;
    margin: 4px 8px;
    background-color: alpha(@text_color, 0.04);
    border-left: 3px solid #e0b020;
}
.write-comment-card.active {
    background-color: alpha(#e0b020, 0.14);
}
.write-comment-card.resolved {
    opacity: 0.6;
}
.write-comment-text {
    font-size: 0.95em;
}
.write-comment-editor {
    border-radius: 6px;
    padding: 6px;
}
.write-page-thumb {
    border-radius: 2px;
    box-shadow: 0 0 0 1px alpha(@shadow_color, 0.25), 0 1px 4px alpha(@shadow_color, 0.3);
    background-color: white;
}
.write-check-context {
    font-style: italic;
    padding: 6px 8px;
    border-radius: 6px;
    background-color: alpha(@text_color, 0.05);
}
button.write-symbol {
    min-width: 34px;
    min-height: 34px;
    font-size: 1.3em;
    padding: 0;
}
.write-chart-data, .write-props-custom {
    border-radius: 6px;
    padding: 6px;
    background-color: alpha(@text_color, 0.05);
}
.write-find-bar {
    background-color: transparent;
}
.write-find-bar-inner {
    background-color: @surface_bg;
    border-top: 1px solid alpha(@text_color, 0.08);
    padding: 2px 0;
}
.write-outline-list button.write-outline-row {
    border-radius: 8px;
    padding: 6px 10px;
}
.write-outline-list button.write-outline-row:hover {
    background-color: alpha(@text_color, 0.08);
    color: @fg_color;
}
.write-outline-h1 { font-weight: 700; }
.write-outline-h2 { font-weight: 600; }
.write-outline-h3 { font-weight: 500; }
.write-outline-h4 { font-weight: 400; }
.write-recent-list {
    border-radius: 10px;
    border: 1px solid alpha(@borders, 0.4);
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
.write-template-card {
    padding: 6px;
    border-radius: 12px;
}
.write-template-thumb {
    border-radius: 6px;
    background-color: @card_bg_color;
    box-shadow: 0 0 0 1px alpha(@borders, 0.7), 0 1px 4px alpha(@shadow_color, 0.25);
}
""";

    }
}
