using Gtk;
using Write;
using Singularity.Widgets;

namespace Singularity.Apps {

    public class WriteRibbon : ContextRibbon {
        public ColorSwatchFace color_face;
        public ColorSwatchFace highlight_face;
        public RibbonMenu color_menu;
        public RibbonMenu highlight_menu;
        public RibbonToggle bold;
        public RibbonToggle italic;
        public RibbonToggle underline;
        public RibbonToggle strike;
        public RibbonToggle sup;
        public RibbonToggle sub;
        public RibbonToggle[] align = new RibbonToggle[4];
        public RibbonToggle bullets;
        public RibbonToggle numbers;
        public RibbonToggle painter;
        public RibbonToggle track;
        public RibbonToggle nav_toggle;
        public RibbonToggle ruler_toggle;
        public RibbonToggle marks_toggle;
        public RibbonToggle comments_toggle;
        public RibbonToggle merge_toggle;
        public RibbonSelector view_modes;
        public string[] style_ids = {};
        private string[] style_names = {};
        private string[] families = {};
        private RibbonSelector style_sel;
        private RibbonSelector font_sel;
        private RibbonSelector size_sel;
        private RibbonSelector markup_sel;
        private RibbonSelector zoom_sel;
        private string cur_style = "";
        private string cur_font = "";
        private double cur_size = 11;
        private string cur_bib = "";
        private bool updating = false;
        public signal void action(string name, Variant? param);

        public const double[] SIZES = { 8, 9, 10, 10.5, 11, 12, 14, 16, 18, 20, 22, 24, 26, 28, 36, 48, 72 };

        public delegate void Build(Singularity.Widgets.ContextMenu menu);

        public WriteRibbon() {
            Object(orientation: Orientation.VERTICAL, spacing: 0);
            add_css_class("write-ribbon");
            load_families();
            build_home(add_context("home", _("Home"), "format-text-bold-symbolic"));
            build_insert(add_context("insert", _("Insert"), "list-add-symbolic"));
            build_layout(add_context("layout", _("Layout"), "document-page-setup-symbolic"));
            build_references(add_context("references", _("References"), "accessories-dictionary-symbolic"));
            build_review(add_context("review", _("Review"), "tools-check-spelling-symbolic"));
            build_mailings(add_context("mailings", _("Mailings"), "mail-send-symbolic"));
            build_view(add_context("view", _("View"), "view-reveal-symbolic"));
        }

        private void load_families() {
            var fm = Pango.CairoFontMap.get_default();
            Pango.FontFamily[] fams;
            fm.list_families(out fams);
            var names = new Gee.ArrayList<string>();
            foreach (var f in fams) names.add(f.get_name());
            names.sort((a, b) => strcmp(a.casefold(), b.casefold()));
            string[] arr = {};
            foreach (string n in names) arr += n;
            families = arr;
        }

        private void fire(string spec) {
            string name = spec;
            Variant? param = null;
            int i = spec.index_of("::");
            if (i >= 0) {
                name = spec.substring(0, i);
                string v = spec.substring(i + 2);
                param = WriteActions.is_double(name) ? new Variant.double(double.parse(v)) : new Variant.string(v);
            }
            if (name == "fullscreen") {
                var app = GLib.Application.get_default();
                if (app != null) app.activate_action("fullscreen", null);
                return;
            }
            action(name, param);
        }

        private RibbonButton button(RibbonContext c, string? icon, string label, string tip, string spec, bool with_label = false) {
            var b = c.add_button(icon, label, tip);
            b.label_in_compact = with_label;
            b.activated.connect(() => fire(spec));
            return b;
        }

        private RibbonToggle toggle(RibbonContext c, string? icon, string label, string tip, string spec, bool with_label = false) {
            var t = c.add_toggle(icon, label, tip);
            t.label_in_compact = with_label;
            t.toggled.connect(() => {
                if (updating) return;
                fire(spec);
            });
            return t;
        }

        private RibbonMenu menu(RibbonContext c, string? icon, string label, string tip, bool with_label, owned Build build) {
            var m = c.add_menu(icon, label, tip);
            m.label_in_compact = with_label;
            m.set_builder((cm) => {
                cm.add_css_class("write-menu");
                build(cm);
            });
            return m;
        }

        private RibbonSelector selector(RibbonContext c, string tip, int chars, owned Build build) {
            var s = c.add_selector(tip, chars);
            s.add_extra((cm) => {
                cm.add_css_class("write-menu");
                build(cm);
            });
            return s;
        }

        public static void popup_menu(Widget anchor, owned Build build) {
            var menu = new Singularity.Widgets.ContextMenu(anchor);
            menu.add_css_class("write-menu");
            build(menu);
            var rect = Gdk.Rectangle();
            rect.x = anchor.get_width() / 2;
            rect.y = anchor.get_height();
            rect.width = 1;
            rect.height = 1;
            menu.set_pointing_to(rect);
            menu.closed.connect(() => {
                Idle.add(() => {
                    if (menu.get_parent() != null) menu.unparent();
                    return Source.REMOVE;
                });
            });
            menu.popup();
        }

        public static Gtk.Button check_row(Singularity.Widgets.ContextMenu menu, string label, bool active, owned Singularity.Widgets.ContextMenu.ClickedCallback cb) {
            var row = new Singularity.Widgets.MenuRow(label, null);
            row.halign = Gtk.Align.FILL;
            if (active) {
                row.add_css_class("checked");
                var box = row.get_child() as Box;
                if (box != null) {
                    var mark = new Image.from_icon_name("object-select-symbolic");
                    mark.pixel_size = 16;
                    box.append(mark);
                }
            }
            row.clicked.connect(() => {
                menu.popdown();
                cb();
            });
            menu.add_widget(row);
            return row;
        }

        private void add_specs(Singularity.Widgets.ContextMenu m, string[,] items) {
            for (int i = 0; i < items.length[0]; i++) {
                string label = items[i, 0];
                string spec = items[i, 1];
                if (label == "") {
                    m.add_separator();
                    continue;
                }
                m.add_item(label, null, () => fire(spec));
            }
        }

        private void add_spec_submenu(Singularity.Widgets.ContextMenu m, string title, string[,] items) {
            var sub = m.add_submenu(title, null);
            sub.add_css_class("write-menu");
            add_specs(sub, items);
        }

        private Widget scroll_list(Box list, int max_height, int min_width) {
            var scroll = new ScrolledWindow();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.vscrollbar_policy = PolicyType.AUTOMATIC;
            scroll.propagate_natural_height = true;
            scroll.max_content_height = max_height;
            scroll.min_content_width = min_width;
            scroll.child = list;
            return scroll;
        }

        private Singularity.Widgets.MenuRow list_row(string label, bool current) {
            var row = new Singularity.Widgets.MenuRow(label, null);
            row.halign = Gtk.Align.FILL;
            if (current) {
                row.add_css_class("checked");
                var box = row.get_child() as Box;
                if (box != null) box.append(new Image.from_icon_name("object-select-symbolic"));
            }
            return row;
        }

        private void build_home(RibbonContext c) {
            menu(c, "edit-paste-symbolic", _("Clipboard"), _("Clipboard"), false, (m) => add_specs(m, {
                { _("Cut"), "cut" },
                { _("Copy"), "copy" },
                { _("Paste"), "paste" },
                { "", "" },
                { _("Paste as Plain Text"), "paste-text" },
                { _("Paste Special…"), "paste-special" },
                { "", "" },
                { _("Format Painter"), "format-painter" }
            }));
            painter = toggle(c, "write-format-painter-symbolic", _("Format Painter"), _("Format Painter (Ctrl+Shift+C)"), "format-painter");
            c.add_separator();
            style_sel = selector(c, _("Paragraph Style"), 10, (m) => style_menu(m));
            style_sel.text = _("Normal");
            font_sel = selector(c, _("Font"), 11, (m) => font_menu(m));
            font_sel.text = _("Font");
            size_sel = selector(c, _("Font Size"), 3, (m) => size_menu(m));
            size_sel.text = "11";
            c.add_separator();
            bold = toggle(c, "format-text-bold-symbolic", _("Bold"), _("Bold (Ctrl+B)"), "bold");
            italic = toggle(c, "format-text-italic-symbolic", _("Italic"), _("Italic (Ctrl+I)"), "italic");
            underline = toggle(c, "format-text-underline-symbolic", _("Underline"), _("Underline (Ctrl+U)"), "underline");
            strike = toggle(c, "format-text-strikethrough-symbolic", _("Strikethrough"), _("Strikethrough"), "strike");
            sup = toggle(c, "write-superscript-symbolic", _("Superscript"), _("Superscript (Ctrl+Shift+Plus)"), "superscript");
            sub = toggle(c, "write-subscript-symbolic", _("Subscript"), _("Subscript (Ctrl+Equal)"), "subscript");
            menu(c, "write-text-effects-symbolic", _("Text Effects"), _("Text Effects and Case"), false, (m) => {
                add_specs(m, {
                    { _("Strikethrough"), "strike" },
                    { _("Superscript"), "superscript" },
                    { _("Subscript"), "subscript" },
                    { _("Double Underline"), "double-underline" },
                    { _("Double Strikethrough"), "dstrike" },
                    { _("Small Caps"), "smallcaps" },
                    { _("All Caps"), "allcaps" },
                    { "", "" },
                    { _("Grow Font"), "grow-font" },
                    { _("Shrink Font"), "shrink-font" },
                    { "", "" }
                });
                add_spec_submenu(m, _("Change Case"), {
                    { _("Sentence case."), "change-case::sentence" },
                    { _("lowercase"), "change-case::lower" },
                    { _("UPPERCASE"), "change-case::upper" },
                    { _("Capitalize Each Word"), "change-case::title" },
                    { _("tOGGLE cASE"), "change-case::toggle" }
                });
                add_specs(m, { { _("Font…"), "font-dialog" }, { _("Reveal Formatting"), "reveal-formatting" } });
            });
            color_face = new ColorSwatchFace("write-text-color-symbolic", "#c00000");
            color_menu = c.add_menu(null, _("Font Color"));
            color_menu.set_face(color_face);
            highlight_face = new ColorSwatchFace("write-marker-symbolic", "#ffff00");
            highlight_menu = c.add_menu(null, _("Highlight Color"));
            highlight_menu.set_face(highlight_face);
            button(c, "edit-clear-all-symbolic", _("Clear Formatting"), _("Clear Formatting (Ctrl+Space)"), "clear-formatting");
            c.add_separator();
            string[] icons = { "format-justify-left-symbolic", "format-justify-center-symbolic", "format-justify-right-symbolic", "format-justify-fill-symbolic" };
            string[] labels = { _("Align Left"), _("Center"), _("Align Right"), _("Justify") };
            string[] tips = { _("Align Left (Ctrl+L)"), _("Center (Ctrl+E)"), _("Align Right (Ctrl+R)"), _("Justify (Ctrl+J)") };
            string[] vals = { "left", "center", "right", "justify" };
            for (int i = 0; i < 4; i++) align[i] = toggle(c, icons[i], labels[i], tips[i], "align::" + vals[i]);
            menu(c, "write-line-spacing-symbolic", _("Spacing"), _("Line and Paragraph Spacing"), false, (m) => add_specs(m, {
                { "1.0", "line-spacing::1.0" },
                { "1.08", "line-spacing::1.08" },
                { "1.15", "line-spacing::1.15" },
                { "1.5", "line-spacing::1.5" },
                { "2.0", "line-spacing::2.0" },
                { "2.5", "line-spacing::2.5" },
                { "3.0", "line-spacing::3.0" },
                { "", "" },
                { _("Add Space Before Paragraph"), "space-before" },
                { _("Add Space After Paragraph"), "space-after" },
                { _("Paragraph…"), "paragraph-dialog" }
            }));
            c.add_separator();
            bullets = toggle(c, "view-list-bullet-symbolic", _("Bullets"), _("Bullets (Ctrl+Shift+L)"), "bullets");
            numbers = toggle(c, "view-list-ordered-symbolic", _("Numbering"), _("Numbering"), "numbering");
            menu(c, "view-list-symbolic", _("Lists"), _("Lists"), false, (m) => add_specs(m, {
                { _("Lists…"), "multilevel" },
                { _("Restart Numbering"), "restart-numbering" },
                { "", "" },
                { _("Decrease Indent"), "indent-less" },
                { _("Increase Indent"), "indent-more" }
            }));
            button(c, "format-indent-less-symbolic", _("Decrease Indent"), _("Decrease Indent (Ctrl+Shift+M)"), "indent-less");
            button(c, "format-indent-more-symbolic", _("Increase Indent"), _("Increase Indent (Ctrl+M)"), "indent-more");
            c.add_separator();
            button(c, null, _("Styles"), _("Styles Pane (Ctrl+Alt+Shift+S)"), "styles-pane");
        }

        private void style_menu(Singularity.Widgets.ContextMenu m) {
            var list = new Box(Orientation.VERTICAL, 0);
            for (int i = 0; i < style_ids.length; i++) {
                if (style_ids[i] == "__more") continue;
                string id = style_ids[i];
                var row = list_row(style_names[i], id == cur_style);
                row.clicked.connect(() => {
                    m.popdown();
                    fire("style::" + id);
                });
                list.append(row);
            }
            m.add_widget(scroll_list(list, 360, 220));
            m.add_separator();
            add_specs(m, {
                { _("Styles Pane"), "styles-pane" },
                { _("New Style…"), "new-style" },
                { _("Modify Style…"), "modify-style" },
                { _("Import Styles…"), "manage-styles" }
            });
        }

        private void font_menu(Singularity.Widgets.ContextMenu m) {
            var search = new Gtk.SearchEntry();
            search.placeholder_text = _("Search Fonts");
            search.margin_start = 4;
            search.margin_end = 4;
            search.margin_top = 2;
            search.margin_bottom = 6;
            m.add_widget(search);
            var list = new Box(Orientation.VERTICAL, 0);
            var rows = new Gee.ArrayList<Widget>();
            var scroll = (ScrolledWindow) scroll_list(list, 380, 240);
            Widget? current = null;
            foreach (string f in families) {
                string fam = f;
                var r = list_row(fam, fam == cur_font);
                if (fam == cur_font) current = r;
                r.clicked.connect(() => {
                    m.popdown();
                    fire("font::" + fam);
                });
                r.set_data<string>("family", fam.casefold());
                list.append(r);
                rows.add(r);
            }
            m.add_widget(scroll);
            search.search_changed.connect(() => {
                string q = search.text.strip().casefold();
                foreach (var r in rows) r.visible = q == "" || r.get_data<string>("family").contains(q);
            });
            search.stop_search.connect(() => m.popdown());
            search.activate.connect(() => {
                foreach (var r in rows) {
                    if (r.visible) {
                        ((Gtk.Button) r).clicked();
                        return;
                    }
                }
            });
            m.add_separator();
            add_specs(m, { { _("Font…"), "font-dialog" } });
            m.map.connect(() => {
                search.grab_focus();
                if (current != null) {
                    var target = current;
                    Idle.add(() => {
                        Graphene.Point p;
                        if (target.compute_point(list, Graphene.Point().init(0, 0), out p)) {
                            scroll.vadjustment.value = double.max(0, p.y - 120);
                        }
                        return Source.REMOVE;
                    });
                }
            });
        }

        private static string size_text(double sz) {
            return sz == Math.floor(sz) ? "%d".printf((int) sz) : "%.1f".printf(sz);
        }

        private void size_menu(Singularity.Widgets.ContextMenu m) {
            var list = new Box(Orientation.VERTICAL, 0);
            foreach (double s in SIZES) {
                double sz = s;
                var row = list_row(size_text(sz), (cur_size - sz).abs() < 0.01);
                row.clicked.connect(() => {
                    m.popdown();
                    action("size", new Variant.double(sz));
                });
                list.append(row);
            }
            m.add_widget(scroll_list(list, 320, 140));
            m.add_separator();
            add_specs(m, {
                { _("Grow Font"), "grow-font" },
                { _("Shrink Font"), "shrink-font" },
                { _("Font…"), "font-dialog" }
            });
        }

        private void breaks_menu(RibbonContext c) {
            menu(c, "document-new-symbolic", _("Breaks"), _("Page, Column and Section Breaks"), true, (m) => add_specs(m, {
                { _("Page Break"), "page-break" },
                { _("Column Break"), "column-break" },
                { "", "" },
                { _("Section Break (Next Page)"), "section-break::next" },
                { _("Section Break (Continuous)"), "section-break::continuous" },
                { _("Section Break (Even Page)"), "section-break::even" },
                { _("Section Break (Odd Page)"), "section-break::odd" }
            }));
        }

        private void build_insert(RibbonContext c) {
            breaks_menu(c);
            c.add_separator();
            button(c, "write-table-symbolic", _("Table"), _("Insert Table"), "table-dialog", true);
            button(c, "insert-image-symbolic", _("Picture"), _("Insert Picture"), "picture", true);
            menu(c, "write-shape-symbolic", _("Shape"), _("Insert Shape"), true, (m) => add_specs(m, {
                { _("Rectangle"), "shape::rect" },
                { _("Rounded Rectangle"), "shape::round" },
                { _("Ellipse"), "shape::ellipse" },
                { _("Triangle"), "shape::triangle" },
                { _("Line"), "shape::line" },
                { _("Arrow"), "shape::arrow" }
            }));
            button(c, "x-office-spreadsheet-symbolic", _("Chart"), _("Insert Chart"), "chart", true);
            menu(c, "insert-text-symbolic", _("Text"), _("Text Box, WordArt, Fields and More"), true, (m) => {
                add_specs(m, {
                    { _("Text Box"), "textbox" },
                    { _("WordArt…"), "wordart" },
                    { _("Drop Cap…"), "dropcap" },
                    { "", "" },
                    { _("Date and Time…"), "date-time" },
                    { _("Field…"), "field" },
                    { _("Text from File…"), "insert-file" },
                    { "", "" }
                });
                add_spec_submenu(m, _("Form Field"), {
                    { _("Check Box"), "checkbox-field" },
                    { _("Text Field"), "text-field" },
                    { _("Drop-Down List"), "dropdown-field" }
                });
            });
            c.add_separator();
            menu(c, "write-equation-symbolic", _("Equation"), _("Insert Equation (Alt+=)"), true, (m) => add_specs(m, {
                { _("Equation"), "equation" },
                { _("Inline Equation"), "equation-inline" },
                { _("Equation Gallery…"), "equation-gallery" }
            }));
            button(c, "accessories-character-map-symbolic", _("Symbol"), _("Insert Symbol"), "symbol", true);
            c.add_separator();
            menu(c, "insert-link-symbolic", _("Link"), _("Links, Bookmarks and Cross-references"), true, (m) => add_specs(m, {
                { _("Link…"), "link" },
                { _("Remove Link"), "remove-link" },
                { "", "" },
                { _("Bookmark…"), "bookmark" },
                { _("Cross-reference…"), "cross-reference" }
            }));
            button(c, "chat-message-new-symbolic", _("Comment"), _("New Comment (Ctrl+Alt+M)"), "new-comment", true);
            c.add_separator();
            menu(c, "document-page-setup-symbolic", _("Header and Footer"), _("Header, Footer and Page Numbers"), true, (m) => {
                add_specs(m, { { _("Edit Header"), "header" }, { _("Edit Footer"), "footer" }, { "", "" } });
                add_spec_submenu(m, _("Page Number"), {
                    { _("Top of Page…"), "page-number::header" },
                    { _("Bottom of Page…"), "page-number::footer" }
                });
            });
        }

        private void build_layout(RibbonContext c) {
            button(c, "document-page-setup-symbolic", _("Page Setup"), _("Margins, Paper Size and Layout"), "page-setup", true);
            menu(c, "orientation-portrait-right-symbolic", _("Orientation"), _("Page Orientation"), true, (m) => add_specs(m, {
                { _("Portrait"), "orientation::portrait" },
                { _("Landscape"), "orientation::landscape" }
            }));
            button(c, "view-dual-symbolic", _("Columns"), _("Text Columns"), "columns", true);
            breaks_menu(c);
            menu(c, "view-list-ordered-symbolic", _("Line Numbers"), _("Line Numbers and Hyphenation"), true, (m) => add_specs(m, {
                { _("Line Numbers"), "line-numbers" },
                { _("Hyphenation"), "hyphenation" }
            }));
            c.add_separator();
            button(c, "image-x-generic-symbolic", _("Watermark"), _("Watermark"), "watermark", true);
            button(c, "color-select-symbolic", _("Page Color"), _("Page Color"), "page-color", true);
            menu(c, "view-paged-symbolic", _("Borders"), _("Page Borders and Paragraph Borders"), true, (m) => add_specs(m, {
                { _("Page Borders…"), "page-borders" },
                { _("Borders and Shading…"), "borders" }
            }));
            c.add_separator();
            button(c, "write-line-spacing-symbolic", _("Paragraph"), _("Indents and Spacing"), "paragraph-dialog", true);
            menu(c, "preferences-desktop-appearance-symbolic", _("Style Set"), _("Document Style Set"), true, (m) => add_specs(m, {
                { _("Classic"), "style-set::classic" },
                { _("Modern"), "style-set::modern" },
                { _("Elegant"), "style-set::elegant" },
                { _("Minimal"), "style-set::minimal" },
                { _("Technical"), "style-set::technical" }
            }));
            c.add_separator();
            menu(c, "write-table-symbolic", _("Table"), _("Table Layout"), true, (m) => {
                add_specs(m, {
                    { _("Insert Row Above"), "table-op::row-above" },
                    { _("Insert Row Below"), "table-op::row-below" },
                    { _("Insert Column Left"), "table-op::col-left" },
                    { _("Insert Column Right"), "table-op::col-right" },
                    { "", "" },
                    { _("Delete Row"), "table-op::delete-row" },
                    { _("Delete Column"), "table-op::delete-col" },
                    { _("Delete Table"), "table-op::delete-table" },
                    { "", "" },
                    { _("Merge With Right Cell"), "table-op::merge-right" },
                    { _("Merge With Cell Below"), "table-op::merge-down" },
                    { _("Split Cell"), "table-op::split" },
                    { _("Distribute Columns Evenly"), "table-op::distribute" },
                    { _("Repeat Header Row"), "table-op::header-row" },
                    { "", "" }
                });
                add_spec_submenu(m, _("Table Style"), {
                    { _("Table Grid"), "table-style::TableGrid" },
                    { _("Plain Table"), "table-style::PlainTable" },
                    { _("Grid Table Light"), "table-style::GridTableLight" },
                    { _("Grid Table Accent"), "table-style::GridTableAccent" }
                });
                add_specs(m, {
                    { _("Sort…"), "table-sort" },
                    { _("Formula…"), "table-formula" },
                    { _("Table Properties…"), "table-properties" },
                    { "", "" },
                    { _("Convert Text to Table…"), "text-to-table" },
                    { _("Convert Table to Text"), "table-to-text" }
                });
            });
        }

        private void build_references(RibbonContext c) {
            menu(c, "view-list-symbolic", _("Contents"), _("Table of Contents"), true, (m) => add_specs(m, {
                { _("Insert Table of Contents"), "toc" },
                { _("Update Table of Contents"), "update-toc" }
            }));
            c.add_separator();
            button(c, null, _("Footnote"), _("Insert Footnote (Ctrl+Alt+F)"), "footnote");
            button(c, null, _("Endnote"), _("Insert Endnote (Ctrl+Alt+D)"), "endnote");
            c.add_separator();
            menu(c, "accessories-dictionary-symbolic", _("Citations"), _("Citations and Bibliography"), true, (m) => {
                add_specs(m, {
                    { _("Insert Citation…"), "citation" },
                    { _("Manage Sources…"), "sources" },
                    { _("Bibliography"), "bibliography" },
                    { "", "" }
                });
                foreach (string st in new string[] { "APA", "MLA", "Chicago", "IEEE", "Harvard" }) {
                    string s = st;
                    check_row(m, s, s == cur_bib, () => {
                        cur_bib = s;
                        fire("bib-style::" + s);
                    });
                }
            });
            c.add_separator();
            button(c, null, _("Caption"), _("Insert Caption"), "caption");
            button(c, null, _("Table of Figures"), _("Insert Table of Figures"), "tof");
            button(c, null, _("Cross-reference"), _("Insert Cross-reference"), "cross-reference");
            c.add_separator();
            menu(c, null, _("Index"), _("Index"), true, (m) => add_specs(m, {
                { _("Mark Index Entry…"), "index-entry" },
                { _("Insert Index"), "index" }
            }));
            c.add_separator();
            button(c, "view-refresh-symbolic", _("Update Fields"), _("Update Fields (F9)"), "update-fields", true);
        }

        private void build_review(RibbonContext c) {
            button(c, "tools-check-spelling-symbolic", _("Spelling"), _("Spelling and Grammar (F7)"), "spelling", true);
            button(c, "accessories-dictionary-symbolic", _("Thesaurus"), _("Thesaurus (Shift+F7)"), "thesaurus");
            button(c, "x-office-document-symbolic", _("Word Count"), _("Word Count (Ctrl+Shift+G)"), "word-count");
            button(c, "preferences-desktop-locale-symbolic", _("Proofing Language"), _("Proofing Language"), "language");
            button(c, "preferences-desktop-accessibility-symbolic", _("Check Accessibility"), _("Check Accessibility"), "accessibility");
            c.add_separator();
            button(c, "audio-speakers-symbolic", _("Read Aloud"), _("Read Aloud (Ctrl+Alt+Space)"), "read-aloud");
            button(c, "audio-input-microphone-symbolic", _("Dictate"), _("Dictate"), "dictate");
            button(c, "write-translate-symbolic", _("Translate"), _("Translate"), "translate");
            c.add_separator();
            button(c, "chat-message-new-symbolic", _("Comment"), _("New Comment (Ctrl+Alt+M)"), "new-comment", true);
            button(c, "go-up-symbolic", _("Previous Comment"), _("Previous Comment"), "prev-comment");
            button(c, "go-down-symbolic", _("Next Comment"), _("Next Comment"), "next-comment");
            menu(c, "mail-reply-sender-symbolic", _("Comment Actions"), _("Comment Actions"), false, (m) => add_specs(m, {
                { _("Reply to Comment"), "comment-reply" },
                { _("Resolve Comment"), "resolve-comment" },
                { _("Delete Comment"), "delete-comment" }
            }));
            c.add_separator();
            track = toggle(c, null, _("Track Changes"), _("Track Changes (Ctrl+Shift+E)"), "track-changes");
            markup_sel = c.add_selector(_("Show Markup"), 12);
            markup_sel.add_option("all", _("All Markup"));
            markup_sel.add_option("simple", _("Simple Markup"));
            markup_sel.add_option("none", _("No Markup"));
            markup_sel.add_option("original", _("Original"));
            markup_sel.selected = "all";
            markup_sel.changed.connect((id) => fire("markup::" + id));
            menu(c, "object-select-symbolic", _("Accept"), _("Accept Changes"), true, (m) => add_specs(m, {
                { _("Accept"), "accept" },
                { _("Accept All Changes"), "accept-all" }
            }));
            menu(c, "window-close-symbolic", _("Reject"), _("Reject Changes"), true, (m) => add_specs(m, {
                { _("Reject"), "reject" },
                { _("Reject All Changes"), "reject-all" }
            }));
            button(c, "go-up-symbolic", _("Previous Change"), _("Previous Change"), "prev-change");
            button(c, "go-down-symbolic", _("Next Change"), _("Next Change"), "next-change");
            c.add_separator();
            menu(c, null, _("Compare"), _("Compare and Combine Documents"), true, (m) => add_specs(m, {
                { _("Compare…"), "compare" },
                { _("Combine…"), "combine" }
            }));
            button(c, "system-users-symbolic", _("Edit Together"), _("Edit Together"), "live-share", true);
            button(c, "system-lock-screen-symbolic", _("Restrict"), _("Restrict Editing"), "protect", true);
        }

        private void build_mailings(RibbonContext c) {
            button(c, "x-office-address-book-symbolic", _("Recipients"), _("Select Recipients"), "merge-recipients", true);
            button(c, "insert-object-symbolic", _("Merge Field"), _("Insert Merge Field"), "merge-field", true);
            c.add_separator();
            merge_toggle = toggle(c, null, _("Preview Results"), _("Preview Results"), "merge-preview");
            button(c, "go-previous-symbolic", _("Previous Record"), _("Previous Record"), "merge-prev");
            button(c, "go-next-symbolic", _("Next Record"), _("Next Record"), "merge-next");
            c.add_separator();
            menu(c, "mail-send-symbolic", _("Finish and Merge"), _("Finish and Merge"), true, (m) => add_specs(m, {
                { _("Edit Individual Documents"), "merge-finish::document" },
                { _("Save as PDF Files…"), "merge-finish::pdf" },
                { _("Print Documents…"), "merge-finish::print" }
            }));
            c.add_separator();
            button(c, "mail-unread-symbolic", _("Envelopes"), _("Envelopes"), "envelopes", true);
            button(c, "view-grid-symbolic", _("Labels"), _("Labels"), "labels", true);
        }

        private void build_view(RibbonContext c) {
            view_modes = c.add_selector(_("Document View"), 10, "view-paged-symbolic");
            view_modes.add_option("read", _("Read"));
            view_modes.add_option("print", _("Print Layout"));
            view_modes.add_option("web", _("Web Layout"));
            view_modes.add_option("outline", _("Outline"));
            view_modes.add_option("draft", _("Draft"));
            view_modes.selected = "print";
            view_modes.changed.connect((n) => {
                if (updating) return;
                fire("view::" + n);
            });
            c.add_separator();
            nav_toggle = toggle(c, "sidebar-show-symbolic", _("Navigation"), _("Navigation Sidebar (Ctrl+Alt+N)"), "navigation", true);
            ruler_toggle = toggle(c, null, _("Ruler"), _("Show Ruler"), "ruler");
            marks_toggle = toggle(c, null, _("Formatting Marks"), _("Show Formatting Marks (Ctrl+Shift+*)"), "marks");
            comments_toggle = toggle(c, null, _("Comments"), _("Comments Panel"), "comments-pane");
            c.add_separator();
            button(c, "zoom-out-symbolic", _("Zoom Out"), _("Zoom Out (Ctrl+Minus)"), "zoom-out");
            zoom_sel = c.add_selector(_("Zoom"), 5);
            foreach (string z in new string[] { "50", "75", "100", "125", "150", "200" }) zoom_sel.add_option(z, z + "%");
            zoom_sel.add_separator();
            zoom_sel.add_option("width", _("Page Width"));
            zoom_sel.add_option("page", _("Whole Page"));
            zoom_sel.text = "100%";
            zoom_sel.changed.connect((z) => fire("zoom::" + z));
            button(c, "zoom-in-symbolic", _("Zoom In"), _("Zoom In (Ctrl+Plus)"), "zoom-in");
            c.add_separator();
            button(c, "view-fullscreen-symbolic", _("Full Screen"), _("Full Screen"), "fullscreen", true);
            menu(c, "media-record-symbolic", _("Macros"), _("Macros, Scripts and AutoCorrect"), true, (m) => add_specs(m, {
                { _("Record Macro"), "macro-record" },
                { _("Macros…"), "macros" },
                { _("New Script…"), "script-new" },
                { "", "" },
                { _("AutoCorrect Options…"), "autocorrect" }
            }));
        }

        public void set_painter(bool on) {
            updating = true;
            painter.active = on;
            updating = false;
        }

        public void set_editable(bool on) {
            foreach (string n in new string[] { "home", "insert", "layout", "references", "mailings" }) {
                var c = stack.get_child_by_name(n);
                if (c != null) c.sensitive = on;
            }
        }

        public void set_styles(Write.Document doc) {
            string[] ids = {};
            string[] names = {};
            foreach (var s in doc.styles.quick_styles()) {
                if (s.kind != StyleType.PARAGRAPH) continue;
                ids += s.id;
                names += s.name;
            }
            style_ids = ids;
            style_names = names;
        }

        public void sync(Write.Document doc, Write.Editor ed, CharProps? pending) {
            updating = true;
            var p = ed.focus.para;
            var raw = pending ?? p.props_at(ed.focus.offset > 0 && !ed.has_selection ? ed.focus.offset : ed.focus.offset + 1);
            if (ed.has_selection) {
                Pos a, b;
                ed.ordered(out a, out b);
                raw = a.para.props_at(a.offset + 1);
            }
            var c = doc.styles.resolve_char(p, raw);
            var pp = doc.styles.resolve_para(p);
            bold.active = c.bold.on();
            italic.active = c.italic.on();
            underline.active = c.underline != Underline.NONE && c.underline != Underline.INHERIT;
            strike.active = c.strike.on();
            sup.active = c.valign == VAlign.SUPER;
            sub.active = c.valign == VAlign.SUB;
            cur_size = c.size > 0 ? c.size : 11;
            size_sel.text = size_text(cur_size);
            cur_font = c.font ?? "Liberation Serif";
            font_sel.text = cur_font;
            int ai = pp.align == Write.Align.CENTER ? 1 : (pp.align == Write.Align.RIGHT ? 2 : (pp.align == Write.Align.JUSTIFY ? 3 : 0));
            for (int i = 0; i < 4; i++) align[i].active = i == ai;
            bool is_list = pp.num_id > 0;
            var def = is_list ? doc.numbering.def_for(pp.num_id) : null;
            bullets.active = def != null && def.is_bullet();
            numbers.active = def != null && !def.is_bullet();
            track.active = doc.track_changes;
            cur_style = p.style;
            string sname = p.style;
            for (int i = 0; i < style_ids.length; i++) if (style_ids[i] == p.style) sname = style_names[i];
            var st = doc.styles.get(p.style);
            if (st != null && sname == p.style) sname = st.name;
            style_sel.text = sname;
            updating = false;
        }

        public void sync_view(WriteRichEditor r) {
            updating = true;
            nav_toggle.active = r.sidebar_shown();
            ruler_toggle.active = r.ruler_rev.reveal_child;
            ruler_toggle.button.sensitive = r.view.mode == ViewMode.PRINT;
            marks_toggle.active = r.view.opts.formatting_marks;
            comments_toggle.active = r.sidebar_page() == "comments" && r.sidebar_shown();
            merge_toggle.active = r.merge_preview;
            switch (r.view.opts.markup) {
                case ViewMarkup.SIMPLE: markup_sel.selected = "simple"; break;
                case ViewMarkup.FINAL: markup_sel.selected = "none"; break;
                case ViewMarkup.ORIGINAL: markup_sel.selected = "original"; break;
                default: markup_sel.selected = "all"; break;
            }
            int zoom = (int) Math.round(r.view.zoom * 100);
            zoom_sel.selected = zoom.to_string();
            zoom_sel.text = "%d%%".printf(zoom);
            string vm = "print";
            switch (r.view.mode) {
                case ViewMode.READ: vm = "read"; break;
                case ViewMode.WEB: vm = "web"; break;
                case ViewMode.OUTLINE: vm = "outline"; break;
                case ViewMode.DRAFT: vm = "draft"; break;
                default: vm = "print"; break;
            }
            view_modes.selected = vm;
            updating = false;
        }
    }
}
