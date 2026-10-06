namespace Write {

    public class OdtReader : Object {
        private ZipReader zip;
        private Document doc;
        private Xml.Doc* xdoc;
        private Gee.HashMap<string, Xml.Node*> auto_styles = new Gee.HashMap<string, Xml.Node*>();
        private Gee.HashMap<string, Xml.Node*> named_styles = new Gee.HashMap<string, Xml.Node*>();
        private Gee.HashMap<string, Xml.Node*> list_styles = new Gee.HashMap<string, Xml.Node*>();
        private Gee.HashMap<string, Xml.Node*> page_layouts = new Gee.HashMap<string, Xml.Node*>();
        private Gee.HashMap<string, Xml.Node*> master_pages = new Gee.HashMap<string, Xml.Node*>();
        private Gee.HashMap<string, string> style_ids = new Gee.HashMap<string, string>();
        private Gee.HashMap<string, int> list_nums = new Gee.HashMap<string, int>();
        private Gee.HashMap<string, string> font_faces = new Gee.HashMap<string, string>();
        private Gee.HashMap<string, Revision> changes = new Gee.HashMap<string, Revision>();
        private Gee.HashMap<string, Gee.ArrayList<Inline>> deletions = new Gee.HashMap<string, Gee.ArrayList<Inline>>();
        private Gee.ArrayList<Xml.Doc*> docs = new Gee.ArrayList<Xml.Doc*>();
        private string first_master = "Standard";
        private Revision? active_ins = null;
        private Revision? active_fmt = null;
        private Gee.HashMap<string, string> comment_names = new Gee.HashMap<string, string>();

        public static Document load(uint8[] data) throws Error {
            return new OdtReader().read(data);
        }

        ~OdtReader() {
            foreach (var d in docs) delete d;
        }

        private Xml.Doc* parse_part(string name) throws Error {
            string? t = zip.read_text(name);
            if (t == null) return null;
            Xml.Doc* d = X.parse(t);
            docs.add(d);
            return d;
        }

        public Document read(uint8[] data) throws Error {
            zip = new ZipReader(data);
            if (zip.is_encrypted("content.xml")) throw new FormatError.ENCRYPTED(_("The document is password protected."));
            string? mt = zip.read_text("mimetype");
            if (mt != null && !mt.has_prefix("application/vnd.oasis.opendocument.text")) throw new FormatError.UNSUPPORTED(_("This OpenDocument file is not a text document."));
            doc = new Document();
            doc.styles.ensure_builtins();
            Xml.Doc* sd = parse_part("styles.xml");
            if (sd != null) read_styles_root(sd->get_root_element(), true);
            xdoc = parse_part("content.xml");
            if (xdoc == null) throw new FormatError.INVALID(_("The file has no document content."));
            Xml.Node* root = xdoc->get_root_element();
            read_styles_root(root, false);
            read_meta();
            Xml.Node* text = X.path(root, "body/text");
            if (text == null) throw new FormatError.INVALID(_("This OpenDocument file is not a text document."));
            Xml.Node* tc = X.child(text, "tracked-changes");
            if (tc != null) {
                doc.track_changes = X.val(tc, "track-changes") != "false";
                read_tracked(tc);
            }
            Xml.Node* decls = X.child(text, "variable-decls");
            doc.final_section = section_for_master(first_master);
            read_blocks(text, doc.body);
            if (doc.body.size == 0) doc.body.add(new Paragraph());
            return doc;
        }

        private void read_settings() {
            try {
                Xml.Doc* m = parse_part("settings.xml");
                if (m == null) return;
                read_config(m->get_root_element());
            } catch (Error e) {
            }
        }

        private void read_config(Xml.Node* n) {
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                if (c->name == "config-item") {
                    string? nm = X.attr(c, "name");
                    if (nm != null && nm.has_prefix("SingularityMacro")) doc.macros.add(X.text(c));
                } else read_config(c);
            }
        }

        private void read_meta() {
            read_settings();
            try {
                Xml.Doc* m = parse_part("meta.xml");
                if (m == null) return;
                Xml.Node* meta = X.child(m->get_root_element(), "meta");
                foreach (var n in X.kids(meta)) {
                    string t = X.text(n);
                    switch (n->name) {
                        case "title": doc.meta.title = t; break;
                        case "subject": doc.meta.subject = t; break;
                        case "initial-creator": doc.meta.author = t; break;
                        case "creator": doc.meta.last_modified_by = t; break;
                        case "description": doc.meta.description = t; break;
                        case "keyword": doc.meta.keywords = doc.meta.keywords == "" ? t : doc.meta.keywords + ", " + t; break;
                        case "creation-date": doc.meta.created = t; break;
                        case "date": doc.meta.modified = t; break;
                        case "editing-cycles": doc.meta.revision = int.parse(t); break;
                        case "user-defined": doc.meta.custom[X.val(n, "name")] = t; break;
                        default: break;
                    }
                }
            } catch (Error e) {
            }
        }

        private void read_styles_root(Xml.Node* root, bool named) {
            Xml.Node* ff = X.child(root, "font-face-decls");
            if (ff != null) {
                foreach (var f in X.kids(ff, "font-face")) {
                    string fam = X.attr(f, "font-family") ?? X.val(f, "name");
                    font_faces[X.val(f, "name")] = fam.replace("'", "").replace("\"", "");
                }
            }
            Xml.Node* st = X.child(root, "styles");
            if (st != null) {
                foreach (var s in X.kids(st)) {
                    if (s->name == "style") named_styles[X.val(s, "name")] = s;
                    else if (s->name == "list-style") list_styles[X.val(s, "name")] = s;
                    else if (s->name == "default-style" && X.val(s, "family") == "paragraph") {
                        Xml.Node* tp = X.child(s, "text-properties");
                        if (tp != null) doc.styles.default_char.overlay(text_props(tp));
                        Xml.Node* pp = X.child(s, "paragraph-properties");
                        if (pp != null) doc.styles.default_para.overlay(para_props(pp));
                    }
                }
            }
            Xml.Node* au = X.child(root, "automatic-styles");
            if (au != null) {
                foreach (var s in X.kids(au)) {
                    if (s->name == "style") auto_styles[X.val(s, "name")] = s;
                    else if (s->name == "list-style") list_styles[X.val(s, "name")] = s;
                    else if (s->name == "page-layout") page_layouts[X.val(s, "name")] = s;
                }
            }
            Xml.Node* ms = X.child(root, "master-styles");
            if (ms != null) {
                bool first = true;
                foreach (var m in X.kids(ms, "master-page")) {
                    master_pages[X.val(m, "name")] = m;
                    if (first) first_master = X.val(m, "name");
                    first = false;
                }
                if (master_pages.has_key("Standard")) first_master = "Standard";
            }
            if (named) {
                foreach (var e in named_styles.entries) {
                    string fam = X.val(e.value, "family");
                    if (fam != "paragraph" && fam != "text") continue;
                    import_named(e.key);
                }
            }
        }

        public static string map_name(string odf) {
            string n = odf.replace("_20_", " ");
            if (n.has_prefix("Heading ") && n.length > 8 && n[8].isdigit()) return "Heading" + n.substring(8);
            if (n.has_prefix("Contents ") && n.length > 9 && n[9].isdigit()) return "TOC" + n.substring(9);
            if (n.has_prefix("Index ") && n.length > 6 && n[6].isdigit()) return "Index" + n.substring(6);
            switch (n) {
                case "Standard":
                case "Text body":
                case "Body Text":
                case "Default Paragraph Style":
                case "Normal": return "Normal";
                case "Title": return "Title";
                case "Subtitle": return "Subtitle";
                case "Quotations":
                case "Quote": return "Quote";
                case "Preformatted Text":
                case "Source Code": return "SourceCode";
                case "Footnote": return "FootnoteText";
                case "Endnote": return "EndnoteText";
                case "Header": return "Header";
                case "Footer": return "Footer";
                case "Caption":
                case "Figure":
                case "Illustration":
                case "Table":
                case "Drawing": return "Caption";
                case "Contents Heading": return "TOCHeading";
                case "Bibliography 1": return "Bibliography";
                case "List Paragraph":
                case "List": return "ListParagraph";
                case "Strong Emphasis":
                case "Strong": return "Strong";
                case "Emphasis": return "Emphasis";
                case "Internet link":
                case "Internet Link":
                case "Hyperlink": return "Hyperlink";
                case "Footnote Symbol":
                case "Footnote anchor": return "FootnoteReference";
                case "Endnote Symbol":
                case "Endnote anchor": return "EndnoteReference";
                case "Comment": return "CommentText";
                case "Index Heading": return "IndexHeading";
                case "Illustration Index 1":
                case "Figure Index 1":
                case "Table of Figures": return "TableofFigures";
                default: return "";
            }
        }

        private string import_named(string odf_name) {
            if (style_ids.has_key(odf_name)) return style_ids[odf_name];
            Xml.Node* s = named_styles[odf_name];
            string mapped = map_name(odf_name);
            string display = X.attr(s, "display-name") ?? odf_name.replace("_20_", " ");
            string id = mapped != "" ? mapped : doc.styles.unique_id(display);
            style_ids[odf_name] = id;
            if (s == null) return id;
            string fam = X.val(s, "family");
            var st = doc.styles.get(id);
            if (st == null) {
                st = new Style(id, display, fam == "text" ? StyleType.CHARACTER : StyleType.PARAGRAPH);
                st.custom = true;
                st.quick = true;
                doc.styles.add(st);
            }
            string? parent = X.attr(s, "parent-style-name");
            if (parent != null && named_styles.has_key(parent)) {
                string pid = import_named(parent);
                if (pid != id) st.based_on = pid;
            } else if (st.kind == StyleType.PARAGRAPH && id != "Normal") {
                st.based_on = "Normal";
            }
            string? next = X.attr(s, "next-style-name");
            if (next != null && named_styles.has_key(next)) st.next = import_named(next);
            Xml.Node* tp = X.child(s, "text-properties");
            if (tp != null) st.chr = text_props(tp);
            Xml.Node* pp = X.child(s, "paragraph-properties");
            if (pp != null) st.para = para_props(pp);
            string? lvl = X.attr(s, "default-outline-level");
            if (lvl != null && lvl != "") st.para.outline = int.parse(lvl) - 1;
            return id;
        }

        public Border? border_of(string? v) {
            if (v == null) return null;
            string s = v.strip();
            if (s == "none" || s == "") return new Border.with("none", 0, "#000000");
            string[] parts = s.split(" ");
            double w = 0.5;
            string style = "single";
            string color = "#000000";
            foreach (string p in parts) {
                if (p.has_prefix("#")) color = p.down();
                else if (p == "solid") style = "single";
                else if (p == "double" || p == "dotted" || p == "dashed") style = p == "dashed" ? "dashed" : p;
                else if (p.length > 0 && (p[0].isdigit() || p[0] == '.')) w = X.length_pt(p, 0.5);
            }
            return new Border.with(style, w, color);
        }

        public ParaProps para_props(Xml.Node* n) {
            var p = new ParaProps();
            string? al = X.attr(n, "text-align");
            if (al != null) {
                switch (al) {
                    case "center": p.align = Align.CENTER; break;
                    case "end":
                    case "right": p.align = Align.RIGHT; break;
                    case "justify": p.align = Align.JUSTIFY; break;
                    default: p.align = Align.LEFT; break;
                }
            }
            if (X.attr(n, "margin-left") != null) p.ind_left = X.length_pt(X.attr(n, "margin-left"));
            if (X.attr(n, "margin-right") != null) p.ind_right = X.length_pt(X.attr(n, "margin-right"));
            if (X.attr(n, "text-indent") != null) p.ind_first = X.length_pt(X.attr(n, "text-indent"));
            if (X.attr(n, "margin-top") != null) p.space_before = X.length_pt(X.attr(n, "margin-top"));
            if (X.attr(n, "margin-bottom") != null) p.space_after = X.length_pt(X.attr(n, "margin-bottom"));
            string? lh = X.attr(n, "line-height");
            if (lh != null && lh != "normal") {
                if (lh.has_suffix("%")) {
                    p.line = double.parse(lh.substring(0, lh.length - 1)) / 100.0;
                    p.line_rule = LineRule.AUTO;
                } else {
                    p.line = X.length_pt(lh);
                    p.line_rule = LineRule.EXACT;
                }
            }
            string? la = X.attr(n, "line-height-at-least");
            if (la != null) {
                p.line = X.length_pt(la);
                p.line_rule = LineRule.AT_LEAST;
            }
            if (X.attr(n, "keep-with-next") != null) p.keep_next = Tri.of(X.val(n, "keep-with-next") == "always");
            if (X.attr(n, "keep-together") != null) p.keep_lines = Tri.of(X.val(n, "keep-together") == "always");
            if (X.attr(n, "break-before") == "page") p.page_break_before = Tri.ON;
            string? bg = X.attr(n, "background-color");
            if (bg != null && bg.has_prefix("#")) p.shading = bg.down();
            string? all = X.attr(n, "border");
            if (all != null) {
                var b = border_of(all);
                p.border_top = b;
                p.border_bottom = b != null ? b.copy() : null;
                p.border_left = b != null ? b.copy() : null;
                p.border_right = b != null ? b.copy() : null;
            }
            if (X.attr(n, "border-top") != null) p.border_top = border_of(X.attr(n, "border-top"));
            if (X.attr(n, "border-bottom") != null) p.border_bottom = border_of(X.attr(n, "border-bottom"));
            if (X.attr(n, "border-left") != null) p.border_left = border_of(X.attr(n, "border-left"));
            if (X.attr(n, "border-right") != null) p.border_right = border_of(X.attr(n, "border-right"));
            Xml.Node* ts = X.child(n, "tab-stops");
            if (ts != null) {
                p.tabs = new Gee.ArrayList<TabStop>();
                foreach (var t in X.kids(ts, "tab-stop")) {
                    TabAlign ta = TabAlign.LEFT;
                    switch (X.val(t, "type")) {
                        case "center": ta = TabAlign.CENTER; break;
                        case "right": ta = TabAlign.RIGHT; break;
                        case "char": ta = TabAlign.DECIMAL; break;
                        default: break;
                    }
                    TabLeader tl = TabLeader.NONE;
                    string lt = X.val(t, "leader-text");
                    if (lt == ".") tl = TabLeader.DOT;
                    else if (lt == "-") tl = TabLeader.HYPHEN;
                    else if (lt == "_") tl = TabLeader.UNDERSCORE;
                    p.tabs.add(new TabStop(X.length_pt(X.attr(t, "position")), ta, tl));
                }
            }
            Xml.Node* dc = X.child(n, "drop-cap");
            if (dc != null && X.ival(dc, "lines", 1) > 1) p.dropcap_lines = X.ival(dc, "lines", 3);
            return p;
        }

        public CharProps text_props(Xml.Node* n) {
            var c = new CharProps();
            string? fn = X.attr(n, "font-name") ?? X.attr(n, "font-family");
            if (fn != null) c.font = font_faces[fn] ?? fn.replace("'", "");
            string? fs = X.attr(n, "font-size");
            if (fs != null && !fs.has_suffix("%")) c.size = X.length_pt(fs);
            string? fw = X.attr(n, "font-weight");
            if (fw != null) c.bold = Tri.of(fw == "bold" || fw == "600" || fw == "700" || fw == "800" || fw == "900");
            string? fst = X.attr(n, "font-style");
            if (fst != null) c.italic = Tri.of(fst == "italic" || fst == "oblique");
            string? ul = X.attr(n, "text-underline-style");
            if (ul != null) {
                if (ul == "none") c.underline = Underline.NONE;
                else if (X.attr(n, "text-underline-type") == "double") c.underline = Underline.DOUBLE;
                else if (ul == "dotted") c.underline = Underline.DOTTED;
                else if (ul == "dash" || ul == "long-dash") c.underline = Underline.DASHED;
                else if (ul == "wave") c.underline = Underline.WAVY;
                else c.underline = Underline.SINGLE;
            }
            string? lt = X.attr(n, "text-line-through-style");
            if (lt != null) {
                if (lt == "none") c.strike = Tri.OFF;
                else if (X.attr(n, "text-line-through-type") == "double") c.dstrike = Tri.ON;
                else c.strike = Tri.ON;
            }
            string? col = X.attr(n, "color");
            if (col != null && col.has_prefix("#")) c.color = col.down();
            string? bg = X.attr(n, "background-color");
            if (bg != null && bg.has_prefix("#")) c.highlight = bg.down();
            if (X.attr(n, "font-variant") == "small-caps") c.caps = Caps.SMALL;
            if (X.attr(n, "text-transform") == "uppercase") c.caps = Caps.ALL;
            string? pos = X.attr(n, "text-position");
            if (pos != null) {
                if (pos.has_prefix("super") || (pos.length > 0 && pos[0].isdigit() && !pos.has_prefix("0"))) c.valign = VAlign.SUPER;
                else if (pos.has_prefix("sub") || pos.has_prefix("-")) c.valign = VAlign.SUB;
                else c.valign = VAlign.BASELINE;
            }
            string? ls = X.attr(n, "letter-spacing");
            if (ls != null && ls != "normal") c.spacing = X.length_pt(ls);
            string? lang = X.attr(n, "language");
            if (lang != null && lang != "zxx" && lang != "none") {
                string? country = X.attr(n, "country");
                c.lang = country != null && country != "none" ? lang + "-" + country : lang;
            }
            if (X.attr(n, "display") == "none") c.hidden = Tri.ON;
            if (X.attr(n, "text-outline") == "true") c.outline = Tri.ON;
            string? sh = X.attr(n, "text-shadow");
            if (sh != null && sh != "none") c.shadow = Tri.ON;
            return c;
        }

        private void para_style(string name, Paragraph p, out string? master) {
            master = null;
            Xml.Node* s = auto_styles[name];
            if (s != null) {
                string? parent = X.attr(s, "parent-style-name");
                if (parent != null) p.style = import_named(parent);
                Xml.Node* pp = X.child(s, "paragraph-properties");
                if (pp != null) p.props = para_props(pp);
                Xml.Node* tp = X.child(s, "text-properties");
                if (tp != null) p.mark_props = text_props(tp);
                master = X.attr(s, "master-page-name");
                string? ls = X.attr(s, "list-style-name");
                if (ls != null && ls != "") p.props.num_id = list_num(ls);
            } else if (named_styles.has_key(name)) {
                p.style = import_named(name);
                master = X.attr(named_styles[name], "master-page-name");
            }
        }

        private CharProps span_props(string name) {
            Xml.Node* s = auto_styles[name];
            if (s != null) {
                var c = new CharProps();
                string? parent = X.attr(s, "parent-style-name");
                if (parent != null) c.style = import_named(parent);
                Xml.Node* tp = X.child(s, "text-properties");
                if (tp != null) c.overlay(text_props(tp));
                return c;
            }
            if (named_styles.has_key(name)) {
                var c = new CharProps();
                c.style = import_named(name);
                return c;
            }
            return new CharProps();
        }

        private int list_num(string name) {
            if (list_nums.has_key(name)) return list_nums[name];
            Xml.Node* ls = list_styles[name];
            ListDef d = doc.numbering.make_numbers();
            if (ls != null) {
                foreach (var lvl in X.kids(ls)) {
                    int i = X.ival(lvl, "level", 1) - 1;
                    if (i < 0 || i > 8) continue;
                    var l = d.levels[i];
                    if (lvl->name == "list-level-style-bullet") {
                        l.format = NumFormat.BULLET;
                        string bc = X.val(lvl, "bullet-char");
                        l.text = bc != "" ? bc : "\u2022";
                    } else if (lvl->name == "list-level-style-number") {
                        string fmt = X.val(lvl, "num-format");
                        switch (fmt) {
                            case "a": l.format = NumFormat.LOWER_LETTER; break;
                            case "A": l.format = NumFormat.UPPER_LETTER; break;
                            case "i": l.format = NumFormat.LOWER_ROMAN; break;
                            case "I": l.format = NumFormat.UPPER_ROMAN; break;
                            case "": l.format = NumFormat.NONE; break;
                            default: l.format = NumFormat.DECIMAL; break;
                        }
                        int display = X.ival(lvl, "display-levels", 1);
                        var sb = new StringBuilder(X.val(lvl, "num-prefix"));
                        for (int k = i - display + 1; k <= i; k++) {
                            if (k < 0) continue;
                            if (k > i - display + 1) sb.append_c('.');
                            sb.append("%" + (k + 1).to_string());
                        }
                        sb.append(X.val(lvl, "num-suffix"));
                        l.text = sb.str;
                        l.start = X.ival(lvl, "start-value", 1);
                    } else {
                        continue;
                    }
                    Xml.Node* lp = X.child(lvl, "list-level-properties");
                    Xml.Node* la = lp != null ? X.child(lp, "list-level-label-alignment") : null;
                    if (la != null) {
                        l.ind_left = X.length_pt(X.attr(la, "margin-left"), l.ind_left);
                        l.hanging = -X.length_pt(X.attr(la, "text-indent"), -l.hanging);
                    } else if (lp != null) {
                        double sb2 = X.length_pt(X.attr(lp, "space-before"), 0);
                        double mw = X.length_pt(X.attr(lp, "min-label-width"), 18);
                        l.ind_left = sb2 + mw;
                        l.hanging = mw;
                    }
                }
            }
            int id = doc.numbering.add_instance(d);
            list_nums[name] = id;
            return id;
        }

        private Section section_for_master(string name) {
            var s = new Section();
            Xml.Node* mp = master_pages[name];
            if (mp == null) return s;
            string? pl = X.attr(mp, "page-layout-name");
            Xml.Node* layout = pl != null ? page_layouts[pl] : null;
            if (layout != null) {
                Xml.Node* lp = X.child(layout, "page-layout-properties");
                if (lp != null) {
                    s.page_w = X.length_pt(X.attr(lp, "page-width"), s.page_w);
                    s.page_h = X.length_pt(X.attr(lp, "page-height"), s.page_h);
                    s.landscape = X.val(lp, "print-orientation") == "landscape";
                    s.margin_top = X.length_pt(X.attr(lp, "margin-top"), 72);
                    s.margin_bottom = X.length_pt(X.attr(lp, "margin-bottom"), 72);
                    s.margin_left = X.length_pt(X.attr(lp, "margin-left"), 72);
                    s.margin_right = X.length_pt(X.attr(lp, "margin-right"), 72);
                    Xml.Node* cols = X.child(lp, "columns");
                    if (cols != null) {
                        s.columns = int.max(1, X.ival(cols, "column-count", 1));
                        s.column_space = X.length_pt(X.attr(cols, "column-gap"), 36);
                        s.column_sep = X.child(cols, "column-sep") != null;
                    }
                    string? fmt = X.attr(lp, "num-format");
                    if (fmt == "i") s.page_format = NumFormat.LOWER_ROMAN;
                    else if (fmt == "I") s.page_format = NumFormat.UPPER_ROMAN;
                    else if (fmt == "a") s.page_format = NumFormat.LOWER_LETTER;
                    else if (fmt == "A") s.page_format = NumFormat.UPPER_LETTER;
                    string? pbg = X.attr(lp, "background-color");
                    if (pbg != null && pbg.has_prefix("#") && pbg.down() != "#ffffff") doc.page_color = pbg.down();
                    string? pb = X.attr(lp, "border");
                    if (pb != null && pb != "none") {
                        var b = border_of(pb);
                        s.page_border_top = b;
                        s.page_border_bottom = b.copy();
                        s.page_border_left = b.copy();
                        s.page_border_right = b.copy();
                    }
                }
                Xml.Node* hs = X.path(layout, "header-style/header-footer-properties");
                if (hs != null) {
                    double hh = X.length_pt(X.attr(hs, "min-height"), 0) + X.length_pt(X.attr(hs, "margin-bottom"), 0);
                    s.header_dist = s.margin_top;
                    s.margin_top += hh;
                }
                Xml.Node* fs = X.path(layout, "footer-style/header-footer-properties");
                if (fs != null) {
                    double fh = X.length_pt(X.attr(fs, "min-height"), 0) + X.length_pt(X.attr(fs, "margin-top"), 0);
                    s.footer_dist = s.margin_bottom;
                    s.margin_bottom += fh;
                }
            }
            foreach (var hf in X.kids(mp)) {
                if (X.attr(hf, "display") == "false") continue;
                var h = new HeaderFooter();
                read_blocks(hf, h.blocks);
                if (h.blocks.size == 0) h.blocks.add(new Paragraph());
                switch (hf->name) {
                    case "header": s.header_default = h; break;
                    case "footer": s.footer_default = h; break;
                    case "header-first": s.header_first = h; s.title_page = true; break;
                    case "footer-first": s.footer_first = h; s.title_page = true; break;
                    case "header-left": s.header_even = h; doc.even_odd_headers = true; break;
                    case "footer-left": s.footer_even = h; doc.even_odd_headers = true; break;
                    default: break;
                }
            }
            return s;
        }

        private void read_tracked(Xml.Node* tc) {
            foreach (var cr in X.kids(tc, "changed-region")) {
                string id = X.attr(cr, "id") ?? X.val(cr, "id");
                foreach (var ch in X.kids(cr)) {
                    RevKind kind = ch->name == "insertion" ? RevKind.INSERT : (ch->name == "deletion" ? RevKind.DELETE : RevKind.FORMAT);
                    Xml.Node* info = X.child(ch, "change-info");
                    string author = info != null ? X.text(X.child(info, "creator")) : "";
                    string date = info != null ? X.text(X.child(info, "date")) : "";
                    var r = new Revision(kind, author, date);
                    changes[id] = r;
                    if (kind == RevKind.DELETE) {
                        var saved_para = cur_para;
                        var tmp = new BlockList();
                        foreach (var p in X.kids(ch, "p")) read_paragraph(p, tmp, 0);
                        foreach (var p in X.kids(ch, "h")) read_paragraph(p, tmp, 1);
                        var items = new Gee.ArrayList<Inline>();
                        for (int i = 0; i < tmp.size; i++) {
                            var p = tmp[i] as Paragraph;
                            if (p == null) continue;
                            if (i > 0) items.add(new Break(BreakKind.LINE));
                            foreach (var it in p.inlines) items.add(it);
                        }
                        foreach (var it in items) it.rev = r.copy();
                        deletions[id] = items;
                        cur_para = saved_para;
                    }
                }
            }
        }

        private Paragraph cur_para;
        private Gee.ArrayList<CharProps> span_stack = new Gee.ArrayList<CharProps>();
        private string? cur_link = null;
        private Gee.ArrayList<int> list_stack = new Gee.ArrayList<int>();
        private int list_level = -1;
        private int cur_list_num = 0;

        private void read_blocks(Xml.Node* parent, BlockList into) {
            for (Xml.Node* c = parent->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                read_block(c, into);
            }
        }

        private void read_block(Xml.Node* c, BlockList into) {
            switch (c->name) {
                case "p":
                    read_paragraph(c, into, 0);
                    break;
                case "h":
                    read_paragraph(c, into, X.ival(c, "outline-level", 1));
                    break;
                case "list":
                    read_list(c, into);
                    break;
                case "table":
                    if (into == doc.body) {
                        string? ts = X.attr(c, "style-name");
                        Xml.Node* tst = ts != null ? auto_styles[ts] : null;
                        string? tm = tst != null ? X.attr(tst, "master-page-name") : null;
                        if (tm != null && tm != "") switch_master(tm);
                    }
                    into.add(read_table(c));
                    break;
                case "section":
                    read_section(c, into);
                    break;
                case "table-of-content":
                case "alphabetical-index":
                case "bibliography":
                case "illustration-index":
                case "table-index":
                case "user-index":
                    read_index(c, into);
                    break;
                case "soft-page-break":
                case "tracked-changes":
                case "variable-decls":
                case "sequence-decls":
                case "user-field-decls":
                    break;
                case "change-start":
                    Revision? bs = changes[X.val(c, "change-id")];
                    if (bs != null && bs.kind == RevKind.INSERT) active_ins = bs;
                    break;
                case "change-end":
                    active_ins = null;
                    break;
                case "change":
                    string cid = X.val(c, "change-id");
                    var dl = deletions[cid];
                    if (dl != null) {
                        var p = new Paragraph();
                        foreach (var it in dl) p.inlines.add(it.copy());
                        into.add(p);
                    }
                    break;
                default:
                    break;
            }
        }

        private void switch_master(string master) {
            if (doc.body.size == 0) {
                doc.final_section = section_for_master(master);
                return;
            }
            var last = doc.body[doc.body.size - 1] as Paragraph;
            if (last == null) {
                last = new Paragraph();
                doc.body.add(last);
            }
            if (last.section != null) {
                var carrier = new Paragraph();
                doc.body.add(carrier);
                last = carrier;
            }
            last.section = doc.final_section;
            doc.final_section = section_for_master(master);
        }

        private void read_section(Xml.Node* sn, BlockList into) {
            string? sname = X.attr(sn, "style-name");
            Xml.Node* st = sname != null ? auto_styles[sname] : null;
            int cols = 1;
            double gap = 36;
            bool sep = false;
            if (st != null) {
                Xml.Node* cn = X.path(st, "section-properties/columns");
                if (cn != null) {
                    cols = int.max(1, X.ival(cn, "column-count", 1));
                    gap = X.length_pt(X.attr(cn, "column-gap"), 36);
                    sep = X.child(cn, "column-sep") != null;
                }
            }
            if (cols > 1 && into == doc.body) {
                var before = into.last_paragraph();
                if (before == null || before.parent != into) {
                    before = new Paragraph();
                    into.add(before);
                }
                if (before.section == null) {
                    var prev = doc.final_section.copy();
                    before.section = prev;
                }
                int start_count = into.size;
                read_blocks(sn, into);
                var last = into.size > start_count ? into[into.size - 1] as Paragraph : null;
                if (last == null) {
                    last = new Paragraph();
                    into.add(last);
                }
                var sec = doc.final_section.copy();
                sec.columns = cols;
                sec.column_space = gap;
                sec.column_sep = sep;
                sec.start = SectionStart.CONTINUOUS;
                last.section = sec;
                var after = new Paragraph();
                into.add(after);
                doc.final_section.start = SectionStart.CONTINUOUS;
            } else {
                read_blocks(sn, into);
            }
        }

        private void read_index(Xml.Node* n, BlockList into) {
            string code = "TOC \\o \"1-3\" \\h";
            switch (n->name) {
                case "alphabetical-index": code = "INDEX \\c \"2\""; break;
                case "bibliography": code = "BIBLIOGRAPHY"; break;
                case "illustration-index": code = "TOC \\h \\c \"Figure\""; break;
                case "table-index": code = "TOC \\h \\c \"Table\""; break;
                default:
                    Xml.Node* src = X.child(n, "table-of-content-source");
                    if (src != null && X.attr(src, "outline-level") != null) code = "TOC \\o \"1-%s\" \\h".printf(X.val(src, "outline-level"));
                    break;
            }
            var fb = new FieldBlock(code);
            Xml.Node* body = X.child(n, "index-body");
            if (body != null) {
                for (Xml.Node* c = body->children; c != null; c = c->next) {
                    if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                    if (c->name == "index-title") read_blocks(c, fb.result);
                    else read_block(c, fb.result);
                }
            }
            into.add(fb);
        }

        private void read_list(Xml.Node* ln, BlockList into) {
            string? sn = X.attr(ln, "style-name");
            bool top = list_level < 0;
            int saved_num = cur_list_num;
            if (sn != null && sn != "") {
                if (top && X.attr(ln, "continue-numbering") != "true" && list_nums.has_key(sn) && X.attr(ln, "continue-list") == null) {
                    int fresh = doc.numbering.restart(list_nums[sn]);
                    cur_list_num = fresh;
                } else {
                    cur_list_num = list_num(sn);
                }
            } else if (top) {
                cur_list_num = list_num("__default");
            }
            list_level++;
            foreach (var item in X.kids(ln)) {
                if (item->name != "list-item" && item->name != "list-header") continue;
                foreach (var ch in X.kids(item)) {
                    if (ch->name == "list") {
                        read_list(ch, into);
                    } else if (ch->name == "p" || ch->name == "h") {
                        read_paragraph(ch, into, ch->name == "h" ? X.ival(ch, "outline-level", 1) : 0);
                        var p = into[into.size - 1] as Paragraph;
                        if (p != null && item->name == "list-item") {
                            p.props.num_id = cur_list_num;
                            p.props.num_level = list_level;
                            if (p.style == "Normal") p.style = "ListParagraph";
                        }
                    } else {
                        read_block(ch, into);
                    }
                }
            }
            list_level--;
            cur_list_num = saved_num;
        }

        private void read_paragraph(Xml.Node* pn, BlockList into, int heading) {
            var p = new Paragraph();
            string? master = null;
            string? sn = X.attr(pn, "style-name");
            if (sn != null) para_style(sn, p, out master);
            if (heading > 0) {
                if (!p.style.has_prefix("Heading")) p.style = "Heading%d".printf(heading.clamp(1, 9));
            }
            if (master != null && master != "" && into == doc.body) switch_master(master);
            var saved = cur_para;
            cur_para = p;
            into.add(p);
            span_stack.clear();
            read_inlines(pn);
            p.normalize();
            if (p.inlines.size == 1 && p.inlines[0] is EquationRun) ((EquationRun) p.inlines[0]).display = true;
            cur_para = saved ?? p;
        }

        private CharProps cur_props() {
            var c = new CharProps();
            foreach (var s in span_stack) c.overlay(s);
            if (cur_link != null) c.link = cur_link;
            return c;
        }

        private void add(Inline i) {
            if (active_ins != null && i.rev == null) i.rev = active_ins.copy();
            if (active_fmt != null && i.rev == null && i.fmt_rev == null) {
                i.fmt_rev = active_fmt.copy();
                i.fmt_old = new CharProps();
            }
            cur_para.inlines.add(i);
        }

        private void add_text(string t) {
            if (t == "") return;
            add(new TextRun(t, cur_props()));
        }

        private static string collapse(string s) {
            var sb = new StringBuilder();
            bool sp = false;
            unichar c;
            int i = 0;
            while (s.get_next_char(ref i, out c)) {
                if (c == ' ' || c == '\n' || c == '\r' || c == '\t') {
                    if (!sp) sb.append_c(' ');
                    sp = true;
                } else {
                    sb.append_unichar(c);
                    sp = false;
                }
            }
            return sb.str;
        }

        private void read_inlines(Xml.Node* parent) {
            for (Xml.Node* c = parent->children; c != null; c = c->next) {
                if (c->type == Xml.ElementType.TEXT_NODE || c->type == Xml.ElementType.CDATA_SECTION_NODE) {
                    add_text(collapse(c->content));
                    continue;
                }
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                switch (c->name) {
                    case "span":
                        string? sn = X.attr(c, "style-name");
                        span_stack.add(sn != null ? span_props(sn) : new CharProps());
                        read_inlines(c);
                        span_stack.remove_at(span_stack.size - 1);
                        break;
                    case "a":
                        string? href = X.attr_p(c, "xlink", "href");
                        string? saved = cur_link;
                        cur_link = href;
                        string? vs = X.attr(c, "style-name");
                        if (vs != null) span_stack.add(span_props(vs));
                        read_inlines(c);
                        if (vs != null) span_stack.remove_at(span_stack.size - 1);
                        cur_link = saved;
                        break;
                    case "s":
                        int n = X.ival(c, "c", 1);
                        add_text(string.nfill(n, ' '));
                        break;
                    case "tab":
                        var t = new Tab();
                        t.props = cur_props();
                        add(t);
                        break;
                    case "line-break":
                        var b = new Break(BreakKind.LINE);
                        b.props = cur_props();
                        add(b);
                        break;
                    case "soft-page-break":
                        break;
                    case "note":
                        read_note(c);
                        break;
                    case "bookmark":
                        add(new Mark(MarkKind.BOOKMARK_START, X.val(c, "name")));
                        add(new Mark(MarkKind.BOOKMARK_END, X.val(c, "name")));
                        break;
                    case "bookmark-start":
                        add(new Mark(MarkKind.BOOKMARK_START, X.val(c, "name")));
                        break;
                    case "bookmark-end":
                        add(new Mark(MarkKind.BOOKMARK_END, X.val(c, "name")));
                        break;
                    case "annotation":
                        read_annotation(c);
                        break;
                    case "annotation-end":
                        string? an = comment_names[X.val(c, "name")];
                        if (an != null) add(new Mark(MarkKind.COMMENT_END, an));
                        break;
                    case "change-start":
                        Revision? r = changes[X.val(c, "change-id")];
                        if (r != null && r.kind == RevKind.INSERT) active_ins = r;
                        else if (r != null && r.kind == RevKind.FORMAT) active_fmt = r;
                        break;
                    case "change-end":
                        Revision? er = changes[X.val(c, "change-id")];
                        if (er != null && er.kind == RevKind.FORMAT) active_fmt = null;
                        else active_ins = null;
                        break;
                    case "change":
                        var dl = deletions[X.val(c, "change-id")];
                        if (dl != null) foreach (var it in dl) cur_para.inlines.add(it.copy());
                        break;
                    case "frame":
                        read_frame(c);
                        break;
                    case "custom-shape":
                    case "rect":
                    case "ellipse":
                    case "line":
                        read_shape(c);
                        break;
                    case "alphabetical-index-mark":
                        add(new Mark(MarkKind.INDEX_ENTRY, X.val(c, "string-value")));
                        break;
                    case "alphabetical-index-mark-start":
                        string key = X.attr(c, "string-value") ?? "";
                        if (key == "") {
                            Xml.Node* nxt = c->next;
                            if (nxt != null && nxt->type == Xml.ElementType.TEXT_NODE) key = nxt->content.strip();
                        }
                        add(new Mark(MarkKind.INDEX_ENTRY, key));
                        break;
                    default:
                        var f = field_of(c);
                        if (f != null) {
                            f.props = cur_props();
                            f.dirty = false;
                            add(f);
                        } else {
                            read_inlines(c);
                        }
                        break;
                }
            }
        }

        private FieldRun? field_of(Xml.Node* c) {
            string res = X.text(c);
            switch (c->name) {
                case "page-number":
                    return new FieldRun("PAGE", res);
                case "page-count":
                    return new FieldRun("NUMPAGES", res);
                case "date":
                    return new FieldRun("DATE \\@ \"d MMMM yyyy\"", res);
                case "time":
                    return new FieldRun("TIME \\@ \"HH:mm\"", res);
                case "title":
                    return new FieldRun("TITLE", res);
                case "subject":
                    return new FieldRun("SUBJECT", res);
                case "initial-creator":
                case "author-name":
                case "creator":
                    return new FieldRun("AUTHOR", res);
                case "file-name":
                    return new FieldRun(X.val(c, "display") == "full" ? "FILENAME \\p" : "FILENAME", res);
                case "word-count":
                    return new FieldRun("NUMWORDS", res);
                case "character-count":
                    return new FieldRun("NUMCHARS", res);
                case "sequence":
                    string code = "SEQ %s \\* ARABIC".printf(X.val(c, "name"));
                    var f = new FieldRun(code, res);
                    string? rn = X.attr(c, "ref-name");
                    if (rn != null) {
                        add(new Mark(MarkKind.BOOKMARK_START, rn));
                        add(f);
                        f.props = cur_props();
                        f.dirty = false;
                        add(new Mark(MarkKind.BOOKMARK_END, rn));
                        return null;
                    }
                    return f;
                case "bookmark-ref":
                case "reference-ref":
                case "sequence-ref":
                    string fmt = X.val(c, "reference-format");
                    string name = X.val(c, "ref-name");
                    if (fmt == "page") return new FieldRun("PAGEREF %s \\h".printf(name), res);
                    return new FieldRun("REF %s \\h".printf(name), res);
                case "note-ref":
                    return new FieldRun("NOTEREF %s \\h".printf(X.val(c, "ref-name")), res);
                case "bibliography-mark":
                    string id = X.val(c, "identifier");
                    ensure_source(c);
                    return new FieldRun("CITATION %s".printf(id), res);
                case "database-display":
                    return new FieldRun("MERGEFIELD %s".printf(X.val(c, "column-name")), res);
                case "user-field-get":
                case "variable-get":
                    return new FieldRun("DOCVARIABLE %s".printf(X.val(c, "name")), res);
                case "user-defined":
                    return new FieldRun("DOCPROPERTY %s".printf(X.val(c, "name")), res);
                case "expression":
                    string formula = X.val(c, "formula");
                    if (formula.has_prefix("ooow:")) formula = formula.substring(5);
                    return new FieldRun("= " + formula, res);
                default:
                    return null;
            }
        }

        private void ensure_source(Xml.Node* c) {
            string id = X.val(c, "identifier");
            if (doc.find_source(id) != null) return;
            var s = new BibSource();
            s.tag = id;
            string type = X.val(c, "bibliography-type");
            s.kind = type == "article" ? "JournalArticle" : (type == "www" ? "InternetSite" : "Book");
            string au = X.val(c, "author");
            if (au != "") {
                string[] names = {};
                foreach (string a in au.split(";")) if (a.strip() != "") names += a.strip();
                s.authors = names;
            }
            s.title = X.val(c, "title");
            s.year = X.val(c, "year");
            s.publisher = X.val(c, "publisher");
            s.city = X.val(c, "address");
            s.journal = X.val(c, "journal");
            s.volume = X.val(c, "volume");
            s.issue = X.val(c, "number");
            s.pages = X.val(c, "pages");
            s.url = X.val(c, "url");
            s.edition = X.val(c, "edition");
            doc.sources.add(s);
        }

        private void read_note(Xml.Node* c) {
            var note = new Note(X.val(c, "note-class") == "endnote" ? NoteKind.ENDNOTE : NoteKind.FOOTNOTE);
            Xml.Node* body = X.child(c, "note-body");
            var saved = cur_para;
            var saved_stack = span_stack;
            span_stack = new Gee.ArrayList<CharProps>();
            int saved_level = list_level;
            list_level = -1;
            if (body != null) read_blocks(body, note.blocks);
            list_level = saved_level;
            span_stack = saved_stack;
            cur_para = saved;
            foreach (var b in note.blocks.items) {
                var p = b as Paragraph;
                if (p != null && p.style == "Normal") p.style = note.kind == NoteKind.FOOTNOTE ? "FootnoteText" : "EndnoteText";
            }
            Xml.Node* cit = X.child(c, "note-citation");
            if (cit != null && X.attr(cit, "label") != null) note.custom_mark = X.val(cit, "label");
            var r = new NoteRef(note);
            r.props = cur_props();
            add(r);
            string? id = X.attr(c, "id");
            if (id != null) {
                cur_para.inlines.insert(cur_para.inlines.size - 1, new Mark(MarkKind.BOOKMARK_START, id));
                cur_para.inlines.add(new Mark(MarkKind.BOOKMARK_END, id));
            }
        }

        private void read_annotation(Xml.Node* c) {
            string id = doc.next_id().to_string();
            var com = new Comment(id, X.text(X.child(c, "creator")));
            com.date = X.text(X.child(c, "date"));
            string? ini = X.text(X.child(c, "creator-initials"));
            if (ini != null && ini != "") com.initials = ini;
            var saved = cur_para;
            var saved_stack = span_stack;
            span_stack = new Gee.ArrayList<CharProps>();
            foreach (var p in X.kids(c, "p")) read_paragraph(p, com.blocks, 0);
            span_stack = saved_stack;
            cur_para = saved;
            string? rn = X.attr(c, "name");
            string? parent_name = X.attr(c, "parent-name");
            if (parent_name != null && comment_names.has_key(parent_name)) com.parent_id = comment_names[parent_name];
            if (X.val(c, "resolved") == "true") com.done = true;
            doc.comments.add(com);
            add(new Mark(MarkKind.COMMENT_START, id));
            if (rn != null) comment_names[rn] = id;
            else add(new Mark(MarkKind.COMMENT_END, id));
        }

        private void frame_geometry(Xml.Node* f, FloatingInline obj) {
            obj.width = X.length_pt(X.attr(f, "width"), obj.width);
            obj.height = X.length_pt(X.attr(f, "height"), obj.height);
            string anchor = X.val(f, "anchor-type");
            string? sn = X.attr(f, "style-name");
            Xml.Node* st = sn != null ? auto_styles[sn] : null;
            Xml.Node* gp = st != null ? X.child(st, "graphic-properties") : null;
            if (anchor != "as-char") {
                string wrap = gp != null ? X.val(gp, "wrap") : "parallel";
                bool bg = gp != null && X.val(gp, "run-through") == "background";
                switch (wrap) {
                    case "none": obj.wrap = Wrap.TOP_BOTTOM; break;
                    case "run-through": obj.wrap = bg ? Wrap.BEHIND : Wrap.FRONT; break;
                    case "dynamic":
                    case "parallel":
                    case "left":
                    case "right": obj.wrap = Wrap.SQUARE; break;
                    default: obj.wrap = Wrap.SQUARE; break;
                }
                if (gp != null && X.val(gp, "wrap-contour") == "true") obj.wrap = Wrap.TIGHT;
                obj.hoff = X.length_pt(X.attr(f, "x"), 0);
                obj.voff = X.length_pt(X.attr(f, "y"), 0);
                if (gp != null) {
                    string hp = X.val(gp, "horizontal-pos");
                    obj.halign = hp == "center" ? HAlignObj.CENTER : (hp == "right" ? HAlignObj.RIGHT : (hp == "left" ? HAlignObj.LEFT : HAlignObj.NONE));
                    string hr = X.val(gp, "horizontal-rel");
                    obj.hrel = hr.has_prefix("page") ? HRel.PAGE : (hr == "char" ? HRel.CHARACTER : HRel.COLUMN);
                    string vr = X.val(gp, "vertical-rel");
                    obj.vrel = vr.has_prefix("page") ? VRel.PAGE : (vr == "line" ? VRel.LINE : VRel.PARAGRAPH);
                }
                if (anchor == "page") {
                    obj.hrel = HRel.PAGE;
                    obj.vrel = VRel.PAGE;
                }
            }
            obj.name = X.val(f, "name");
            Xml.Node* title = X.child(f, "title");
            if (title != null) obj.title = X.text(title);
            Xml.Node* desc = X.child(f, "desc");
            if (desc != null) obj.alt = X.text(desc);
        }

        private static string bytes_str(Bytes b) {
            var ba = new ByteArray();
            ba.append(b.get_data());
            uint8[] z = { 0 };
            ba.append(z);
            return ((string) ba.data).dup();
        }

        private void read_frame(Xml.Node* f) {
            Xml.Node* obj_node = X.child(f, "object");
            Xml.Node* img = X.child(f, "image");
            Xml.Node* tb = X.child(f, "text-box");
            if (obj_node != null) {
                string href = (X.attr_p(obj_node, "xlink", "href") ?? "").replace("./", "");
                while (href.has_suffix("/")) href = href.substring(0, href.length - 1);
                try {
                    string? content = zip.read_text(href + "/content.xml");
                    if (content != null && content.contains("math")) {
                        string mathml = content;
                        int s = mathml.index_of("<math");
                        if (s < 0) s = mathml.index_of(":math");
                        if (s > 0 && mathml[s] == ':') s = mathml.last_index_of_char('<', s);
                        if (s >= 0) mathml = mathml.substring(s);
                        if (EquationCodec.odf_to_mathml != null) mathml = EquationCodec.odf_to_mathml(content, false) ?? mathml;
                        var eq = new EquationRun(mathml);
                        eq.width = X.length_pt(X.attr(f, "width"), 0);
                        double h = X.length_pt(X.attr(f, "height"), 0);
                        double y = X.length_pt(X.attr(f, "y"), 0);
                        eq.ascent = y < 0 ? -y : h * 0.7;
                        eq.descent = h - eq.ascent;
                        Xml.Node* rimg = img;
                        if (rimg != null) {
                            string rh = (X.attr_p(rimg, "xlink", "href") ?? "").replace("./", "");
                            eq.preview = zip.read_bytes(rh);
                        }
                        eq.props = cur_props();
                        add(eq);
                        return;
                    }
                } catch (Error e) {
                }
                var op = new OpaqueRun("odt-object", href, _("Embedded object"));
                foreach (string entry in zip.names()) {
                    if (!entry.has_prefix(href + "/") || entry.has_suffix("/")) continue;
                    try {
                        var eb = zip.read_bytes(entry);
                        if (eb != null) op.parts[entry.substring(href.length + 1)] = eb;
                    } catch (Error e) {
                    }
                }
                try {
                    string? man = zip.read_text("META-INF/manifest.xml");
                    if (man != null) {
                        Xml.Doc* mx = X.parse(man);
                        foreach (var fe in X.kids(mx->get_root_element(), "file-entry")) {
                            string fp = X.val(fe, "full-path");
                            if (fp == href + "/" || fp == href) op.rels["mediatype"] = X.val(fe, "media-type");
                        }
                        delete mx;
                    }
                } catch (Error e) {
                }
                op.width = X.length_pt(X.attr(f, "width"), 144);
                op.height = X.length_pt(X.attr(f, "height"), 72);
                if (img != null) {
                    try {
                        op.preview = zip.read_bytes((X.attr_p(img, "xlink", "href") ?? "").replace("./", ""));
                    } catch (Error e) {
                    }
                }
                if ((op.rels["mediatype"] ?? "").has_suffix("opendocument.chart") && op.parts.has_key("content.xml")) {
                    var ch = new ChartRun();
                    ch.odf_content = bytes_str(op.parts["content.xml"]);
                    if (op.parts.has_key("styles.xml")) ch.odf_styles = bytes_str(op.parts["styles.xml"]);
                    ch.original = op;
                    ch.width = op.width;
                    ch.height = op.height;
                    ch.preview = op.preview;
                    ch.props = cur_props();
                    add(ch);
                    return;
                }
                add(op);
                return;
            }
            if (img != null) {
                string href = X.attr_p(img, "xlink", "href") ?? "";
                Bytes? data = null;
                try {
                    if (href != "" && !href.has_prefix("http")) data = zip.read_bytes(href.replace("./", ""));
                    else {
                        Xml.Node* bin = X.child(img, "binary-data");
                        if (bin != null) data = new Bytes(Base64.decode(X.text(bin)));
                    }
                } catch (Error e) {
                }
                if (data == null) return;
                var ir = new ImageRun(data, ImageRun.sniff(data.get_data()));
                frame_geometry(f, ir);
                ir.props = cur_props();
                add(ir);
                return;
            }
            if (tb != null) {
                var s = new ShapeRun(ShapeKind.TEXT_BOX);
                frame_geometry(f, s);
                if (s.wrap == Wrap.INLINE && X.val(f, "anchor-type") != "as-char") s.wrap = Wrap.SQUARE;
                var saved = cur_para;
                var saved_stack = span_stack;
                span_stack = new Gee.ArrayList<CharProps>();
                read_blocks(tb, s.text);
                span_stack = saved_stack;
                cur_para = saved;
                s.props = cur_props();
                if (s.text.size == 1 && s.text.first_paragraph() != null) {
                    var only = s.text.first_paragraph();
                    if (only.inlines.size == 1 && only.inlines[0] is ImageRun) {
                        var inner = (ImageRun) only.inlines[0];
                        inner.wrap = s.wrap;
                        inner.hoff = s.hoff;
                        inner.voff = s.voff;
                        inner.hrel = s.hrel;
                        inner.vrel = s.vrel;
                        add(inner);
                        foreach (var b in s.text.items) {
                            var cp = b as Paragraph;
                            if (cp != null && cp != only) foreach (var it in cp.inlines) add(it);
                        }
                        return;
                    }
                }
                add(s);
            }
        }

        private void read_shape(Xml.Node* n) {
            ShapeKind kind = ShapeKind.RECT;
            if (n->name == "ellipse") kind = ShapeKind.ELLIPSE;
            else if (n->name == "line") kind = ShapeKind.LINE;
            else if (n->name == "custom-shape") {
                Xml.Node* g = X.child(n, "enhanced-geometry");
                string t = g != null ? X.val(g, "type") : "rectangle";
                if (t == "ellipse") kind = ShapeKind.ELLIPSE;
                else if (t == "round-rectangle") kind = ShapeKind.ROUND_RECT;
                else if (t == "right-arrow") kind = ShapeKind.ARROW;
                else if (t == "isosceles-triangle") kind = ShapeKind.TRIANGLE;
            }
            var s = new ShapeRun(kind);
            frame_geometry(n, s);
            if (kind == ShapeKind.LINE) {
                double x1 = X.length_pt(X.attr(n, "x1"), 0), x2 = X.length_pt(X.attr(n, "x2"), 72);
                double y1 = X.length_pt(X.attr(n, "y1"), 0), y2 = X.length_pt(X.attr(n, "y2"), 0);
                s.width = (x2 - x1).abs();
                s.height = (y2 - y1).abs();
                s.hoff = double.min(x1, x2);
                s.voff = double.min(y1, y2);
            }
            string? sn = X.attr(n, "style-name");
            Xml.Node* st = sn != null ? auto_styles[sn] : null;
            Xml.Node* gp = st != null ? X.child(st, "graphic-properties") : null;
            if (gp != null) {
                if (X.val(gp, "fill") == "none") s.fill = null;
                else if (X.attr(gp, "fill-color") != null) s.fill = X.val(gp, "fill-color").down();
                if (X.val(gp, "stroke") == "none") s.stroke = null;
                else if (X.attr(gp, "stroke-color") != null) s.stroke = X.val(gp, "stroke-color").down();
                if (X.attr(gp, "stroke-width") != null) s.stroke_width = double.max(0.5, X.length_pt(X.attr(gp, "stroke-width")));
            }
            if (s.wrap == Wrap.INLINE && X.val(n, "anchor-type") != "as-char") s.wrap = Wrap.FRONT;
            var saved = cur_para;
            var saved_stack = span_stack;
            span_stack = new Gee.ArrayList<CharProps>();
            foreach (var p in X.kids(n, "p")) read_paragraph(p, s.text, 0);
            span_stack = saved_stack;
            cur_para = saved;
            s.props = cur_props();
            add(s);
        }

        private Table read_table(Xml.Node* tn) {
            var t = new Table();
            t.style = "TableGrid";
            string? ts = X.attr(tn, "style-name");
            Xml.Node* tst = ts != null ? auto_styles[ts] : null;
            Xml.Node* tp = tst != null ? X.child(tst, "table-properties") : null;
            if (tp != null) {
                t.width = X.length_pt(X.attr(tp, "width"), 0);
                string al = X.val(tp, "align");
                t.align = al == "center" ? Align.CENTER : (al == "right" ? Align.RIGHT : Align.LEFT);
                t.indent = X.length_pt(X.attr(tp, "margin-left"), 0);
            }
            var gl = new Gee.ArrayList<double?>();
            var rows = new Gee.ArrayList<Xml.Node*>();
            var header_rows = new Gee.HashSet<Xml.Node*>();
            collect_rows(tn, gl, rows, header_rows, false);
            double[] grid = new double[gl.size];
            for (int i = 0; i < gl.size; i++) grid[i] = gl[i];
            t.grid = grid;
            var pending_spans = new Gee.HashMap<int, int>();
            bool any_border = false;
            foreach (var rn in rows) {
                var row = new TableRow();
                row.header = header_rows.contains(rn);
                string? rs = X.attr(rn, "style-name");
                Xml.Node* rst = rs != null ? auto_styles[rs] : null;
                Xml.Node* rp = rst != null ? X.child(rst, "table-row-properties") : null;
                if (rp != null) {
                    if (X.attr(rp, "row-height") != null) {
                        row.height = X.length_pt(X.attr(rp, "row-height"));
                        row.height_exact = true;
                    } else if (X.attr(rp, "min-row-height") != null) {
                        row.height = X.length_pt(X.attr(rp, "min-row-height"));
                    }
                    row.cant_split = X.val(rp, "keep-together") == "always";
                }
                int col = 0;
                foreach (var cn in X.kids(rn)) {
                    if (cn->name != "table-cell" && cn->name != "covered-table-cell") continue;
                    int rep = int.max(1, X.ival(cn, "number-columns-repeated", 1));
                    for (int r = 0; r < rep; r++) {
                        if (cn->name == "covered-table-cell") {
                            if (pending_spans.has_key(col) && pending_spans[col] > 0) {
                                var cc = new TableCell();
                                cc.vmerge = VMerge.CONTINUE;
                                cc.span = pending_span_width.has_key(col) ? pending_span_width[col] : 1;
                                cc.blocks.add(new Paragraph());
                                row.cells.add(cc);
                                pending_spans[col] = pending_spans[col] - 1;
                                col += cc.span;
                            } else {
                                col++;
                            }
                            continue;
                        }
                        var cell = new TableCell();
                        cell.span = int.max(1, X.ival(cn, "number-columns-spanned", 1));
                        int rspan = X.ival(cn, "number-rows-spanned", 1);
                        if (rspan > 1) {
                            cell.vmerge = VMerge.RESTART;
                            pending_spans[col] = rspan - 1;
                            pending_span_width[col] = cell.span;
                        }
                        string? cs = X.attr(cn, "style-name");
                        Xml.Node* cst = cs != null ? auto_styles[cs] : null;
                        Xml.Node* cp = cst != null ? X.child(cst, "table-cell-properties") : null;
                        if (cp != null) {
                            string? bg = X.attr(cp, "background-color");
                            if (bg != null && bg.has_prefix("#")) cell.shading = bg.down();
                            string? all = X.attr(cp, "border");
                            if (all != null) {
                                cell.top = border_of(all);
                                cell.bottom = border_of(all);
                                cell.left = border_of(all);
                                cell.right = border_of(all);
                            }
                            if (X.attr(cp, "border-top") != null) cell.top = border_of(X.attr(cp, "border-top"));
                            if (X.attr(cp, "border-bottom") != null) cell.bottom = border_of(X.attr(cp, "border-bottom"));
                            if (X.attr(cp, "border-left") != null) cell.left = border_of(X.attr(cp, "border-left"));
                            if (X.attr(cp, "border-right") != null) cell.right = border_of(X.attr(cp, "border-right"));
                            if (cell.top != null && cell.top.visible()) any_border = true;
                            string va = X.val(cp, "vertical-align");
                            cell.valign = va == "middle" ? CellVAlign.CENTER : (va == "bottom" ? CellVAlign.BOTTOM : CellVAlign.TOP);
                        }
                        int saved_level = list_level;
                        list_level = -1;
                        read_blocks(cn, cell.blocks);
                        list_level = saved_level;
                        if (cell.blocks.size == 0) cell.blocks.add(new Paragraph());
                        row.cells.add(cell);
                        col += cell.span;
                    }
                }
                t.rows.add(row);
            }
            if (t.grid.length == 0) {
                int n = t.columns();
                double[] g = new double[n];
                for (int i = 0; i < n; i++) g[i] = 468.0 / int.max(1, n);
                t.grid = g;
            }
            if (any_border) {
                t.style = "PlainTable";
            } else {
                t.style = "PlainTable";
            }
            return t;
        }

        private Gee.HashMap<int, int> pending_span_width = new Gee.HashMap<int, int>();

        private void collect_rows(Xml.Node* parent, Gee.ArrayList<double?> grid, Gee.ArrayList<Xml.Node*> rows, Gee.HashSet<Xml.Node*> headers, bool header) {
            foreach (var c in X.kids(parent)) {
                switch (c->name) {
                    case "table-column":
                        int rep = int.max(1, X.ival(c, "number-columns-repeated", 1));
                        string? cs = X.attr(c, "style-name");
                        Xml.Node* st = cs != null ? auto_styles[cs] : null;
                        Xml.Node* cp = st != null ? X.child(st, "table-column-properties") : null;
                        double w = cp != null ? X.length_pt(X.attr(cp, "column-width"), 72) : 72;
                        for (int i = 0; i < rep; i++) grid.add(w);
                        break;
                    case "table-columns":
                    case "table-header-columns":
                        collect_rows(c, grid, rows, headers, header);
                        break;
                    case "table-header-rows":
                        collect_rows(c, grid, rows, headers, true);
                        break;
                    case "table-rows":
                        collect_rows(c, grid, rows, headers, header);
                        break;
                    case "table-row":
                        int rep = int.max(1, X.ival(c, "number-rows-repeated", 1));
                        for (int i = 0; i < int.min(rep, 200); i++) {
                            rows.add(c);
                            if (header) headers.add(c);
                        }
                        break;
                    default:
                        break;
                }
            }
        }
    }
}
