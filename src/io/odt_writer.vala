namespace Write {

    public class OdtWriter : Object {
        public const string NS = "xmlns:office=\"urn:oasis:names:tc:opendocument:xmlns:office:1.0\" xmlns:style=\"urn:oasis:names:tc:opendocument:xmlns:style:1.0\" xmlns:text=\"urn:oasis:names:tc:opendocument:xmlns:text:1.0\" xmlns:table=\"urn:oasis:names:tc:opendocument:xmlns:table:1.0\" xmlns:draw=\"urn:oasis:names:tc:opendocument:xmlns:drawing:1.0\" xmlns:fo=\"urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:meta=\"urn:oasis:names:tc:opendocument:xmlns:meta:1.0\" xmlns:number=\"urn:oasis:names:tc:opendocument:xmlns:datastyle:1.0\" xmlns:svg=\"urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0\" xmlns:math=\"http://www.w3.org/1998/Math/MathML\" xmlns:loext=\"urn:org:documentfoundation:names:experimental:office:xmlns:loext:1.0\" xmlns:officeooo=\"http://openoffice.org/2009/office\" xmlns:ooow=\"http://openoffice.org/2004/writer\" office:version=\"1.3\"";

        private Document doc;
        private ZipWriter zip = new ZipWriter();
        private Gee.ArrayList<string> manifest = new Gee.ArrayList<string>();
        private StringBuilder auto_styles = new StringBuilder();
        private Gee.HashMap<string, string> auto_keys = new Gee.HashMap<string, string>();
        private int auto_n = 0;
        private Gee.HashSet<int> used_lists = new Gee.HashSet<int>();
        private Gee.HashSet<int> started_lists = new Gee.HashSet<int>();
        private Gee.HashSet<string> fonts = new Gee.HashSet<string>();
        private int pic_n = 0;
        private int obj_n = 0;
        private int note_n = 0;
        private int frame_n = 0;
        private int change_n = 0;
        private StringBuilder changes = new StringBuilder();
        private Gee.ArrayList<Section> section_list;
        private Gee.HashMap<Section, string> masters = new Gee.HashMap<Section, string>();
        private bool pending_master = true;
        private Section? pending_section = null;
        private bool in_header = false;
        public bool template = false;

        public static uint8[] save(Document doc, bool template = false) throws Error {
            var w = new OdtWriter(doc);
            w.template = template;
            return w.write();
        }

        public OdtWriter(Document doc) {
            this.doc = doc;
        }

        public static string odf_name(Document doc, string id) {
            if (id.has_prefix("Heading") && id.length > 7 && id[7].isdigit()) return "Heading_20_" + id.substring(7);
            if (id.has_prefix("TOC") && id.length > 3 && id[3].isdigit()) return "Contents_20_" + id.substring(3);
            if (id.has_prefix("Index") && id.length > 5 && id[5].isdigit()) return "Index_20_" + id.substring(5);
            switch (id) {
                case "Normal": return "Standard";
                case "Title": return "Title";
                case "Subtitle": return "Subtitle";
                case "Quote": return "Quotations";
                case "SourceCode": return "Preformatted_20_Text";
                case "FootnoteText": return "Footnote";
                case "EndnoteText": return "Endnote";
                case "Header": return "Header";
                case "Footer": return "Footer";
                case "Caption": return "Caption";
                case "TOCHeading": return "Contents_20_Heading";
                case "ListParagraph": return "List_20_Paragraph";
                case "Hyperlink": return "Internet_20_link";
                case "Strong": return "Strong_20_Emphasis";
                case "Emphasis": return "Emphasis";
                case "FootnoteReference": return "Footnote_20_Symbol";
                case "EndnoteReference": return "Endnote_20_Symbol";
                case "Bibliography": return "Bibliography_20_1";
                case "IndexHeading": return "Index_20_Heading";
                case "TableofFigures": return "Figure_20_Index_20_1";
                case "CommentText": return "Comment";
                default: break;
            }
            var s = doc.styles.get(id);
            string n = s != null ? s.name : id;
            return encode(n);
        }

        public static string encode(string n) {
            var sb = new StringBuilder();
            unichar c;
            int i = 0;
            while (n.get_next_char(ref i, out c)) {
                if (c == ' ') sb.append("_20_");
                else if (c.isalnum() || c == '_' || c == '-') sb.append_unichar(c);
                else sb.append("_%X_".printf((uint) c));
            }
            return sb.str;
        }

        private static string pt(double v) {
            return X.num(Math.round(v * 100) / 100) + "pt";
        }

        private static string border_str(Border? b) {
            if (b == null || !b.visible()) return "none";
            string st = b.style == "double" ? "double" : (b.style == "dotted" ? "dotted" : (b.style == "dashed" ? "dashed" : "solid"));
            return "%s %s %s".printf(pt(b.width), st, b.color);
        }

        private void font(string? f) {
            if (f != null) fonts.add(f);
        }

        public string text_props(CharProps c) {
            var sb = new StringBuilder();
            if (c.font != null) {
                font(c.font);
                sb.append(" style:font-name=\"%s\"".printf(X.esc(c.font)));
            }
            if (c.size > 0) sb.append(" fo:font-size=\"%s\" style:font-size-asian=\"%s\" style:font-size-complex=\"%s\"".printf(pt(c.size), pt(c.size), pt(c.size)));
            if (c.bold != Tri.INHERIT) sb.append(" fo:font-weight=\"%s\" style:font-weight-asian=\"%s\"".printf(c.bold.on() ? "bold" : "normal", c.bold.on() ? "bold" : "normal"));
            if (c.italic != Tri.INHERIT) sb.append(" fo:font-style=\"%s\" style:font-style-asian=\"%s\"".printf(c.italic.on() ? "italic" : "normal", c.italic.on() ? "italic" : "normal"));
            if (c.underline != Underline.INHERIT) {
                switch (c.underline) {
                    case Underline.NONE: sb.append(" style:text-underline-style=\"none\""); break;
                    case Underline.DOUBLE: sb.append(" style:text-underline-style=\"solid\" style:text-underline-type=\"double\" style:text-underline-width=\"auto\" style:text-underline-color=\"font-color\""); break;
                    case Underline.DOTTED: sb.append(" style:text-underline-style=\"dotted\" style:text-underline-width=\"auto\" style:text-underline-color=\"font-color\""); break;
                    case Underline.DASHED: sb.append(" style:text-underline-style=\"dash\" style:text-underline-width=\"auto\" style:text-underline-color=\"font-color\""); break;
                    case Underline.WAVY: sb.append(" style:text-underline-style=\"wave\" style:text-underline-width=\"auto\" style:text-underline-color=\"font-color\""); break;
                    case Underline.THICK: sb.append(" style:text-underline-style=\"solid\" style:text-underline-width=\"bold\" style:text-underline-color=\"font-color\""); break;
                    default: sb.append(" style:text-underline-style=\"solid\" style:text-underline-width=\"auto\" style:text-underline-color=\"font-color\""); break;
                }
            }
            if (c.strike != Tri.INHERIT) sb.append(c.strike.on() ? " style:text-line-through-style=\"solid\" style:text-line-through-type=\"single\"" : " style:text-line-through-style=\"none\"");
            if (c.dstrike.on()) sb.append(" style:text-line-through-style=\"solid\" style:text-line-through-type=\"double\"");
            if (c.color != null) sb.append(" fo:color=\"%s\"".printf(c.color));
            string? bg = c.highlight != null && c.highlight != "none" ? c.highlight : c.shading;
            if (bg != null) sb.append(" fo:background-color=\"%s\"".printf(bg));
            if (c.caps == Caps.SMALL) sb.append(" fo:font-variant=\"small-caps\"");
            else if (c.caps == Caps.ALL) sb.append(" fo:text-transform=\"uppercase\"");
            else if (c.caps == Caps.NONE) sb.append(" fo:font-variant=\"normal\" fo:text-transform=\"none\"");
            if (c.valign == VAlign.SUPER) sb.append(" style:text-position=\"super 58%\"");
            else if (c.valign == VAlign.SUB) sb.append(" style:text-position=\"sub 58%\"");
            else if (c.valign == VAlign.BASELINE) sb.append(" style:text-position=\"0% 100%\"");
            if (!c.spacing.is_nan()) sb.append(" fo:letter-spacing=\"%s\"".printf(pt(c.spacing)));
            if (c.lang != null) {
                string[] lc = c.lang.split("-");
                sb.append(" fo:language=\"%s\"".printf(X.esc(lc[0])));
                if (lc.length > 1) sb.append(" fo:country=\"%s\"".printf(X.esc(lc[1])));
            }
            if (c.hidden.on()) sb.append(" text:display=\"none\"");
            if (c.outline.on()) sb.append(" style:text-outline=\"true\"");
            if (c.shadow.on()) sb.append(" fo:text-shadow=\"1pt 1pt\"");
            if (sb.len == 0) return "";
            return "<style:text-properties" + sb.str + "/>";
        }

        public string para_props(ParaProps p) {
            var sb = new StringBuilder();
            switch (p.align) {
                case Align.LEFT: sb.append(" fo:text-align=\"start\""); break;
                case Align.CENTER: sb.append(" fo:text-align=\"center\""); break;
                case Align.RIGHT: sb.append(" fo:text-align=\"end\""); break;
                case Align.JUSTIFY: sb.append(" fo:text-align=\"justify\""); break;
                default: break;
            }
            if (!p.ind_left.is_nan()) sb.append(" fo:margin-left=\"%s\"".printf(pt(p.ind_left)));
            if (!p.ind_right.is_nan()) sb.append(" fo:margin-right=\"%s\"".printf(pt(p.ind_right)));
            if (!p.ind_first.is_nan()) sb.append(" fo:text-indent=\"%s\"".printf(pt(p.ind_first)));
            if (!p.space_before.is_nan()) sb.append(" fo:margin-top=\"%s\"".printf(pt(p.space_before)));
            if (!p.space_after.is_nan()) sb.append(" fo:margin-bottom=\"%s\"".printf(pt(p.space_after)));
            if (!p.line.is_nan()) {
                if (p.line_rule == LineRule.AUTO) sb.append(" fo:line-height=\"%d%%\"".printf((int) Math.round(p.line * 100)));
                else if (p.line_rule == LineRule.EXACT) sb.append(" fo:line-height=\"%s\"".printf(pt(p.line)));
                else sb.append(" style:line-height-at-least=\"%s\"".printf(pt(p.line)));
            }
            if (p.keep_next != Tri.INHERIT) sb.append(" fo:keep-with-next=\"%s\"".printf(p.keep_next.on() ? "always" : "auto"));
            if (p.keep_lines != Tri.INHERIT) sb.append(" fo:keep-together=\"%s\"".printf(p.keep_lines.on() ? "always" : "auto"));
            if (p.page_break_before.on()) sb.append(" fo:break-before=\"page\"");
            if (p.widow != Tri.INHERIT) sb.append(" fo:widows=\"%d\" fo:orphans=\"%d\"".printf(p.widow.on() ? 2 : 0, p.widow.on() ? 2 : 0));
            if (p.shading != null) sb.append(" fo:background-color=\"%s\"".printf(p.shading));
            if (p.border_top != null) sb.append(" fo:border-top=\"%s\"".printf(border_str(p.border_top)));
            if (p.border_bottom != null) sb.append(" fo:border-bottom=\"%s\"".printf(border_str(p.border_bottom)));
            if (p.border_left != null) sb.append(" fo:border-left=\"%s\"".printf(border_str(p.border_left)));
            if (p.border_right != null) sb.append(" fo:border-right=\"%s\"".printf(border_str(p.border_right)));
            if (p.border_top != null || p.border_bottom != null) sb.append(" fo:padding=\"1pt\"");
            if (p.contextual.on()) sb.append(" style:contextual-spacing=\"true\"");
            var inner = new StringBuilder();
            if (p.tabs != null && p.tabs.size > 0) {
                inner.append("<style:tab-stops>");
                foreach (var t in p.tabs) {
                    string type = t.align == TabAlign.CENTER ? "center" : (t.align == TabAlign.RIGHT ? "right" : (t.align == TabAlign.DECIMAL ? "char" : "left"));
                    inner.append("<style:tab-stop style:position=\"%s\" style:type=\"%s\"".printf(pt(t.pos), type));
                    if (t.align == TabAlign.DECIMAL) inner.append(" style:char=\".\"");
                    if (t.leader == TabLeader.DOT) inner.append(" style:leader-style=\"dotted\" style:leader-text=\".\"");
                    else if (t.leader == TabLeader.HYPHEN) inner.append(" style:leader-style=\"dash\" style:leader-text=\"-\"");
                    else if (t.leader == TabLeader.UNDERSCORE) inner.append(" style:leader-style=\"solid\" style:leader-text=\"_\"");
                    inner.append("/>");
                }
                inner.append("</style:tab-stops>");
            }
            if (p.dropcap_lines > 0) inner.append("<style:drop-cap style:lines=\"%d\" style:length=\"1\" style:distance=\"2pt\"/>".printf(p.dropcap_lines));
            if (sb.len == 0 && inner.len == 0) return "";
            if (inner.len == 0) return "<style:paragraph-properties" + sb.str + "/>";
            return "<style:paragraph-properties" + sb.str + ">" + inner.str + "</style:paragraph-properties>";
        }

        private string auto_style(string family, string prefix, string parent, string body, string extra_attrs = "") {
            string key = family + "|" + parent + "|" + body + "|" + extra_attrs;
            if (auto_keys.has_key(key)) return auto_keys[key];
            auto_n++;
            string name = "%s%d".printf(prefix, auto_n);
            auto_keys[key] = name;
            auto_styles.append("<style:style style:name=\"%s\" style:family=\"%s\"".printf(name, family));
            if (parent != "") auto_styles.append(" style:parent-style-name=\"%s\"".printf(parent));
            auto_styles.append(extra_attrs);
            auto_styles.append(">");
            auto_styles.append(body);
            auto_styles.append("</style:style>");
            return name;
        }

        private string para_style_name(Paragraph p, string? master) {
            string parent = odf_name(doc, p.style);
            string body = para_props(p.props) + text_props(p.mark_props);
            string extra = master != null ? " style:master-page-name=\"%s\"".printf(master) : "";
            if (body == "" && extra == "") return parent;
            return auto_style("paragraph", "P", parent, body, extra);
        }

        private string span_style(CharProps c) {
            var cc = c.copy();
            cc.link = null;
            string? parent = cc.style != null ? odf_name(doc, cc.style) : null;
            cc.style = null;
            string body = text_props(cc);
            if (body == "" && parent == null) return "";
            if (body == "") return parent;
            return auto_style("text", "T", parent ?? "", body);
        }

        public uint8[] write() throws Error {
            section_list = doc.sections();
            for (int i = 0; i < section_list.size; i++) masters[section_list[i]] = i == 0 ? "Standard" : "MP%d".printf(i);
            string mime = template ? "application/vnd.oasis.opendocument.text-template" : "application/vnd.oasis.opendocument.text";
            zip.add_text("mimetype", mime, false);
            pending_section = section_list[0];
            var body = new StringBuilder();
            write_body(body);
            var content = new StringBuilder();
            content.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<office:document-content " + NS + ">");
            content.append(font_decls());
            content.append("<office:automatic-styles>");
            content.append(auto_styles.str);
            foreach (int id in used_lists) content.append(list_style(id));
            content.append("</office:automatic-styles><office:body><office:text>");
            if (changes.len > 0) content.append("<text:tracked-changes text:track-changes=\"%s\">%s</text:tracked-changes>".printf(doc.track_changes ? "true" : "false", changes.str));
            content.append("<text:sequence-decls><text:sequence-decl text:display-outline-level=\"0\" text:name=\"Illustration\"/><text:sequence-decl text:display-outline-level=\"0\" text:name=\"Table\"/><text:sequence-decl text:display-outline-level=\"0\" text:name=\"Text\"/><text:sequence-decl text:display-outline-level=\"0\" text:name=\"Drawing\"/><text:sequence-decl text:display-outline-level=\"0\" text:name=\"Figure\"/><text:sequence-decl text:display-outline-level=\"0\" text:name=\"Equation\"/></text:sequence-decls>");
            content.append(body.str);
            content.append("</office:text></office:body></office:document-content>");
            string styles = styles_xml();
            zip.add_text("content.xml", content.str);
            zip.add_text("styles.xml", styles);
            zip.add_text("meta.xml", meta_xml());
            zip.add_text("settings.xml", settings_xml());
            var m = new StringBuilder();
            m.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<manifest:manifest xmlns:manifest=\"urn:oasis:names:tc:opendocument:xmlns:manifest:1.0\" manifest:version=\"1.3\">");
            m.append("<manifest:file-entry manifest:full-path=\"/\" manifest:version=\"1.3\" manifest:media-type=\"%s\"/>".printf(mime));
            foreach (string e in new string[] { "content.xml", "styles.xml", "meta.xml", "settings.xml" }) m.append("<manifest:file-entry manifest:full-path=\"%s\" manifest:media-type=\"text/xml\"/>".printf(e));
            foreach (string e in manifest) m.append(e);
            m.append("</manifest:manifest>");
            zip.add_text("META-INF/manifest.xml", m.str);
            return zip.finish();
        }

        private string font_decls() {
            var sb = new StringBuilder("<office:font-face-decls>");
            foreach (string f in fonts) sb.append("<style:font-face style:name=\"%s\" svg:font-family=\"'%s'\"/>".printf(X.esc(f), X.esc(f)));
            sb.append("</office:font-face-decls>");
            return sb.str;
        }

        private void write_blocks(StringBuilder o, BlockList list, bool top) {
            int i = 0;
            while (i < list.size) {
                var b = list[i];
                var p = b as Paragraph;
                if (p != null && p.props.num_id > 0 && doc.numbering.instance(p.props.num_id) != null) {
                    int j = i;
                    while (j < list.size && list[j] is Paragraph && ((Paragraph) list[j]).props.num_id > 0 && doc.numbering.instance(((Paragraph) list[j]).props.num_id) != null) {
                        if (((Paragraph) list[j]).section != null && j > i) break;
                        j++;
                        if (((Paragraph) list[j - 1]).section != null) break;
                    }
                    write_list_run(o, list, i, j, top);
                    i = j;
                    continue;
                }
                write_block(o, b, top);
                i++;
            }
        }

        private void write_block(StringBuilder o, Block b, bool top) {
            if (b is Paragraph) write_paragraph(o, (Paragraph) b, top);
            else if (b is Table) write_table(o, (Table) b, top);
            else if (b is FieldBlock) write_field_block(o, (FieldBlock) b, top);
        }

        private void write_list_run(StringBuilder o, BlockList list, int from, int to, bool top) {
            int k = from;
            while (k < to) {
                var p = (Paragraph) list[k];
                int num = p.props.num_id;
                int m = k;
                while (m < to && ((Paragraph) list[m]).props.num_id == num) m++;
                used_lists.add(num);
                bool cont = started_lists.contains(num);
                started_lists.add(num);
                write_list_level(o, list, k, m, 0, num, cont, top);
                k = m;
            }
        }

        private void write_list_level(StringBuilder o, BlockList list, int from, int to, int level, int num, bool cont, bool top) {
            o.append("<text:list");
            if (level == 0) {
                o.append(" text:style-name=\"L%d\"".printf(num));
                if (cont) o.append(" text:continue-numbering=\"true\"");
            }
            o.append(">");
            int k = from;
            while (k < to) {
                var p = (Paragraph) list[k];
                int lvl = int.max(0, p.props.num_level);
                o.append("<text:list-item>");
                if (lvl <= level) {
                    write_paragraph(o, p, top);
                    k++;
                }
                int m = k;
                while (m < to && int.max(0, ((Paragraph) list[m]).props.num_level) > level) m++;
                if (m > k) {
                    write_list_level(o, list, k, m, level + 1, num, false, top);
                    k = m;
                }
                o.append("</text:list-item>");
            }
            o.append("</text:list>");
        }

        private string list_style(int num_id) {
            var inst = doc.numbering.instance(num_id);
            var d = inst != null ? doc.numbering.def(inst.def_id) : null;
            var sb = new StringBuilder("<text:list-style style:name=\"L%d\">".printf(num_id));
            if (d == null) {
                sb.append("</text:list-style>");
                return sb.str;
            }
            for (int i = 0; i < 9; i++) {
                var l = d.levels[i];
                string props = "<style:list-level-properties text:list-level-position-and-space-mode=\"label-alignment\"><style:list-level-label-alignment text:label-followed-by=\"listtab\" text:list-tab-stop-position=\"%s\" fo:text-indent=\"%s\" fo:margin-left=\"%s\"/></style:list-level-properties>".printf(pt(l.ind_left), pt(-l.hanging), pt(l.ind_left));
                if (l.format == NumFormat.BULLET) {
                    string ch = l.text != "" ? l.text : "\u2022";
                    sb.append("<text:list-level-style-bullet text:level=\"%d\" text:bullet-char=\"%s\">%s</text:list-level-style-bullet>".printf(i + 1, X.esc(usub(ch, 0, 1)), props));
                } else {
                    string fmt = "1";
                    switch (l.format) {
                        case NumFormat.LOWER_LETTER: fmt = "a"; break;
                        case NumFormat.UPPER_LETTER: fmt = "A"; break;
                        case NumFormat.LOWER_ROMAN: fmt = "i"; break;
                        case NumFormat.UPPER_ROMAN: fmt = "I"; break;
                        case NumFormat.NONE: fmt = ""; break;
                        default: break;
                    }
                    string t = l.text;
                    int first = t.index_of_char('%');
                    int last = t.last_index_of_char('%');
                    string prefix = first > 0 ? t.substring(0, first) : "";
                    string suffix = last >= 0 && last + 2 <= t.length ? t.substring(last + 2) : "";
                    int display = 0;
                    for (int k = 0; k < t.length; k++) if (t[k] == '%') display++;
                    int start = l.start;
                    if (inst.start_override.has_key(i)) start = inst.start_override[i];
                    sb.append("<text:list-level-style-number text:level=\"%d\" style:num-prefix=\"%s\" style:num-suffix=\"%s\" style:num-format=\"%s\" text:start-value=\"%d\"%s>%s</text:list-level-style-number>".printf(
                        i + 1, X.esc(prefix), X.esc(suffix), fmt, start, display > 1 ? " text:display-levels=\"%d\"".printf(display) : "", props));
                }
            }
            sb.append("</text:list-style>");
            return sb.str;
        }

        private void write_paragraph(StringBuilder o, Paragraph p, bool top) {
            string? master = null;
            if (top && pending_master && !in_header) {
                master = masters[pending_section];
                pending_master = false;
            }
            string tag = "text:p";
            int lvl = doc.styles.outline_level(p);
            if (lvl >= 0 && p.style.has_prefix("Heading")) tag = "text:h";
            var chunks = new Gee.ArrayList<Gee.ArrayList<Inline>>();
            chunks.add(new Gee.ArrayList<Inline>());
            foreach (var it in p.inlines) {
                var br = it as Break;
                if (br != null && br.kind == BreakKind.PAGE && it.rev == null) {
                    chunks.add(new Gee.ArrayList<Inline>());
                    continue;
                }
                chunks[chunks.size - 1].add(it);
            }
            for (int c = 0; c < chunks.size; c++) {
                string sname;
                if (c == 0) {
                    sname = para_style_name(p, master);
                } else {
                    var q = p.shell();
                    q.props.page_break_before = Tri.ON;
                    sname = para_style_name(q, null);
                }
                o.append("<" + tag + " text:style-name=\"" + sname + "\"");
                if (tag == "text:h") o.append(" text:outline-level=\"%d\"".printf(lvl + 1));
                o.append(">");
                write_inlines(o, chunks[c]);
                o.append("</" + tag + ">");
            }
        }

        private void write_body(StringBuilder o) {
            var group = new BlockList();
            int k = 0;
            var items = new Gee.ArrayList<Block>();
            foreach (var b in doc.body.items) items.add(b);
            var current = new Gee.ArrayList<Block>();
            for (int i = 0; i <= items.size; i++) {
                bool end = i == items.size;
                if (!end) current.add(items[i]);
                var p = end ? null : items[i] as Paragraph;
                if (!end && (p == null || p.section == null)) continue;
                if (current.size == 0) break;
                var sec = section_list[int.min(k, section_list.size - 1)];
                bool continuous = k > 0 && sec.start == SectionStart.CONTINUOUS && same_page(section_list[k - 1], sec);
                pending_section = sec;
                pending_master = !continuous;
                bool wrap = continuous && sec.columns > 1;
                if (wrap) {
                    frame_n++;
                    var cs = new StringBuilder("<style:section-properties text:dont-balance-text-columns=\"false\"><style:columns fo:column-count=\"%d\" fo:column-gap=\"%s\">".printf(sec.columns, pt(sec.column_space)));
                    if (sec.column_sep) cs.append("<style:column-sep style:width=\"0.5pt\" style:color=\"#000000\" style:height=\"100%\"/>");
                    cs.append("</style:columns></style:section-properties>");
                    string sname = auto_style("section", "Sect", "", cs.str);
                    o.append("<text:section text:style-name=\"%s\" text:name=\"Section%d\">".printf(sname, frame_n));
                }
                group.items.clear();
                foreach (var b in current) group.items.add(b);
                write_blocks(o, group, true);
                if (wrap) o.append("</text:section>");
                current.clear();
                k++;
            }
            group.items.clear();
        }

        private static bool same_page(Section a, Section b) {
            return (a.page_w - b.page_w).abs() < 1 && (a.page_h - b.page_h).abs() < 1 && (a.margin_left - b.margin_left).abs() < 1 && (a.margin_right - b.margin_right).abs() < 1;
        }

        private void write_inlines(StringBuilder o, Gee.List<Inline> inlines) {
            int i = 0;
            while (i < inlines.size) {
                string? link = inlines[i].props.link;
                int j = i;
                while (j < inlines.size && inlines[j].props.link == link) j++;
                if (link != null && link != "") o.append("<text:a xlink:type=\"simple\" xlink:href=\"%s\">".printf(X.esc(link)));
                for (int k = i; k < j; k++) {
                    var it = inlines[k];
                    if (it.rev != null && it.rev.kind == RevKind.DELETE) {
                        int m = k;
                        while (m < j && inlines[m].rev != null && inlines[m].rev.kind == RevKind.DELETE) m++;
                        write_deletion(o, inlines, k, m);
                        k = m - 1;
                        continue;
                    }
                    if (it.rev != null && it.rev.kind == RevKind.INSERT) {
                        int m = k;
                        while (m < j && inlines[m].rev != null && inlines[m].rev.kind == RevKind.INSERT) m++;
                        string id = add_change("insertion", it.rev, "");
                        o.append("<text:change-start text:change-id=\"%s\"/>".printf(id));
                        for (int q = k; q < m; q++) write_inline(o, inlines[q]);
                        o.append("<text:change-end text:change-id=\"%s\"/>".printf(id));
                        k = m - 1;
                        continue;
                    }
                    if (it.fmt_rev != null && it.rev == null) {
                        string fid = add_change("format-change", it.fmt_rev, "");
                        o.append("<text:change-start text:change-id=\"%s\"/>".printf(fid));
                        write_inline(o, it);
                        o.append("<text:change-end text:change-id=\"%s\"/>".printf(fid));
                        continue;
                    }
                    write_inline(o, it);
                }
                if (link != null && link != "") o.append("</text:a>");
                i = j;
            }
        }

        private string add_change(string kind, Revision r, string content) {
            change_n++;
            string id = "ct%d".printf(change_n);
            changes.append("<text:changed-region xml:id=\"%s\" text:id=\"%s\"><text:%s><office:change-info><dc:creator>%s</dc:creator><dc:date>%s</dc:date></office:change-info>%s</text:%s></text:changed-region>".printf(
                id, id, kind, X.esc(r.author), X.esc(r.date.replace("Z", "")), content, kind));
            return id;
        }

        private void write_deletion(StringBuilder o, Gee.List<Inline> inlines, int from, int to) {
            var sb = new StringBuilder("<text:p>");
            for (int q = from; q < to; q++) {
                var copy = inlines[q].copy();
                copy.rev = null;
                write_inline(sb, copy);
            }
            sb.append("</text:p>");
            string id = add_change("deletion", inlines[from].rev, sb.str);
            o.append("<text:change text:change-id=\"%s\"/>".printf(id));
        }

        private void write_text(StringBuilder o, string text) {
            int spaces = 0;
            unichar c;
            int i = 0;
            bool at_start = true;
            while (text.get_next_char(ref i, out c)) {
                if (c == ' ') {
                    spaces++;
                    continue;
                }
                flush_spaces(o, ref spaces, at_start);
                at_start = false;
                switch (c) {
                    case '\t': o.append("<text:tab/>"); break;
                    case '\n': o.append("<text:line-break/>"); break;
                    case '&': o.append("&amp;"); break;
                    case '<': o.append("&lt;"); break;
                    case '>': o.append("&gt;"); break;
                    default:
                        if (c < 0x20) break;
                        o.append_unichar(c);
                        break;
                }
            }
            if (spaces > 0) {
                if (spaces == 1 && !at_start) o.append(" ");
                else o.append("<text:s text:c=\"%d\"/>".printf(spaces));
            }
        }

        private void flush_spaces(StringBuilder o, ref int spaces, bool at_start) {
            if (spaces == 0) return;
            if (at_start) {
                o.append("<text:s text:c=\"%d\"/>".printf(spaces));
            } else {
                o.append(" ");
                if (spaces > 1) o.append("<text:s text:c=\"%d\"/>".printf(spaces - 1));
            }
            spaces = 0;
        }

        private void span_open(StringBuilder o, CharProps c, out bool opened) {
            string st = span_style(c);
            opened = st != "";
            if (opened) o.append("<text:span text:style-name=\"%s\">".printf(st));
        }

        private void write_inline(StringBuilder o, Inline it) {
            bool opened;
            if (it is TextRun) {
                span_open(o, it.props, out opened);
                write_text(o, ((TextRun) it).text);
                if (opened) o.append("</text:span>");
            } else if (it is Tab) {
                o.append("<text:tab/>");
            } else if (it is Break) {
                var b = (Break) it;
                if (b.kind == BreakKind.LINE) o.append("<text:line-break/>");
                else o.append("<text:soft-page-break/>");
            } else if (it is FieldRun) {
                span_open(o, it.props, out opened);
                write_field(o, (FieldRun) it);
                if (opened) o.append("</text:span>");
            } else if (it is NoteRef) {
                write_note(o, (NoteRef) it);
            } else if (it is Mark) {
                var m = (Mark) it;
                switch (m.kind) {
                    case MarkKind.BOOKMARK_START: o.append("<text:bookmark-start text:name=\"%s\"/>".printf(X.esc(m.name))); break;
                    case MarkKind.BOOKMARK_END: o.append("<text:bookmark-end text:name=\"%s\"/>".printf(X.esc(m.name))); break;
                    case MarkKind.COMMENT_START: write_annotation(o, m.name); break;
                    case MarkKind.COMMENT_END: o.append("<office:annotation-end office:name=\"c%s\"/>".printf(X.esc(m.name))); break;
                    case MarkKind.INDEX_ENTRY: o.append("<text:alphabetical-index-mark text:string-value=\"%s\"/>".printf(X.esc(m.name))); break;
                    default: break;
                }
            } else if (it is ImageRun) {
                write_image(o, (ImageRun) it);
            } else if (it is ShapeRun) {
                write_shape(o, (ShapeRun) it);
            } else if (it is EquationRun) {
                write_equation(o, (EquationRun) it);
            } else if (it is FormField) {
                var f = (FormField) it;
                span_open(o, it.props, out opened);
                write_text(o, f.display_text());
                if (opened) o.append("</text:span>");
            } else if (it is ChartRun) {
                write_chart(o, (ChartRun) it);
            } else if (it is OpaqueRun && ((OpaqueRun) it).format == "odt-object") {
                write_object(o, (OpaqueRun) it);
            } else if (it is OpaqueRun) {
                var op = (OpaqueRun) it;
                if (op.preview != null) {
                    var img = new ImageRun(op.preview, ImageRun.sniff(op.preview.get_data()));
                    img.width = op.width;
                    img.height = op.height;
                    img.alt = op.description;
                    write_image(o, img);
                } else {
                    var box = new ShapeRun(ShapeKind.TEXT_BOX);
                    box.width = op.width;
                    box.height = op.height;
                    box.text.add(new Paragraph.with_text(op.description));
                    write_shape(o, box);
                }
            }
        }

        private void write_object(StringBuilder o, OpaqueRun op) {
            obj_n++;
            string dir = "Object %d".printf(obj_n);
            foreach (var e in op.parts.entries) {
                try {
                    zip.add(dir + "/" + e.key, e.value.get_data());
                } catch (Error err) {
                }
                if (e.key.has_suffix(".xml")) manifest.add("<manifest:file-entry manifest:full-path=\"%s/%s\" manifest:media-type=\"text/xml\"/>".printf(dir, X.esc(e.key)));
            }
            manifest.add("<manifest:file-entry manifest:full-path=\"%s/\" manifest:media-type=\"%s\"/>".printf(dir, X.esc(op.rels["mediatype"] ?? "application/vnd.oasis.opendocument.chart")));
            string style = auto_style("graphic", "fr", "", "<style:graphic-properties style:vertical-pos=\"top\" style:vertical-rel=\"baseline\"/>");
            o.append("<draw:frame draw:style-name=\"%s\" text:anchor-type=\"as-char\" svg:width=\"%s\" svg:height=\"%s\"><draw:object xlink:href=\"./%s\" xlink:type=\"simple\" xlink:show=\"embed\" xlink:actuate=\"onLoad\"/>".printf(style, pt(op.width), pt(op.height), dir));
            if (op.preview != null) {
                string rp = "ObjectReplacements/%s".printf(dir);
                try {
                    zip.add(rp, op.preview.get_data(), false);
                } catch (Error err) {
                }
                manifest.add("<manifest:file-entry manifest:full-path=\"%s\" manifest:media-type=\"image/png\"/>".printf(rp));
                o.append("<draw:image xlink:href=\"./%s\"/>".printf(rp));
            }
            o.append("</draw:frame>");
        }

        private void write_chart(StringBuilder o, ChartRun ch) {
            if (!ch.edited && ch.original != null && ch.original.format == "odt-object") {
                write_object(o, ch.original);
                return;
            }
            if (ch.odf_content != "") {
                var op = new OpaqueRun("odt-object", "", _("Chart"));
                op.parts["content.xml"] = new Bytes(ch.odf_content.data);
                if (ch.odf_styles != "") op.parts["styles.xml"] = new Bytes(ch.odf_styles.data);
                op.rels["mediatype"] = "application/vnd.oasis.opendocument.chart";
                op.width = ch.width;
                op.height = ch.height;
                op.preview = ch.preview;
                write_object(o, op);
                return;
            }
            if (ch.preview != null) {
                var img = new ImageRun(ch.preview, "image/png");
                img.width = ch.width;
                img.height = ch.height;
                img.alt = ch.alt;
                img.title = ch.title;
                write_image(o, img);
            }
        }

        private void write_field(StringBuilder o, FieldRun f) {
            string[] t = f.args();
            string kind = f.kind();
            string res = X.esc(f.result);
            switch (kind) {
                case "PAGE": o.append("<text:page-number text:select-page=\"current\">%s</text:page-number>".printf(res)); break;
                case "NUMPAGES": o.append("<text:page-count>%s</text:page-count>".printf(res)); break;
                case "DATE": o.append("<text:date>%s</text:date>".printf(res)); break;
                case "TIME": o.append("<text:time>%s</text:time>".printf(res)); break;
                case "TITLE": o.append("<text:title>%s</text:title>".printf(res)); break;
                case "SUBJECT": o.append("<text:subject>%s</text:subject>".printf(res)); break;
                case "AUTHOR": o.append("<text:initial-creator>%s</text:initial-creator>".printf(res)); break;
                case "FILENAME": o.append("<text:file-name text:display=\"%s\">%s</text:file-name>".printf(Fields.has_switch(t, "\\p") ? "full" : "name-and-extension", res)); break;
                case "NUMWORDS": o.append("<text:word-count>%s</text:word-count>".printf(res)); break;
                case "NUMCHARS": o.append("<text:character-count>%s</text:character-count>".printf(res)); break;
                case "SEQ":
                    string name = t.length > 1 ? t[1] : "Figure";
                    o.append("<text:sequence text:name=\"%s\" text:formula=\"ooow:%s+1\" style:num-format=\"1\">%s</text:sequence>".printf(X.esc(name), X.esc(name), res));
                    break;
                case "REF":
                    o.append("<text:bookmark-ref text:reference-format=\"text\" text:ref-name=\"%s\">%s</text:bookmark-ref>".printf(X.esc(t.length > 1 ? t[1] : ""), res));
                    break;
                case "PAGEREF":
                    o.append("<text:bookmark-ref text:reference-format=\"page\" text:ref-name=\"%s\">%s</text:bookmark-ref>".printf(X.esc(t.length > 1 ? t[1] : ""), res));
                    break;
                case "NOTEREF":
                    o.append("<text:note-ref text:note-class=\"footnote\" text:reference-format=\"text\" text:ref-name=\"%s\">%s</text:note-ref>".printf(X.esc(t.length > 1 ? t[1] : ""), res));
                    break;
                case "CITATION":
                    string tag = t.length > 1 ? t[1] : "";
                    var s = doc.find_source(tag);
                    o.append("<text:bibliography-mark text:identifier=\"%s\" text:bibliography-type=\"%s\"".printf(X.esc(tag), s != null && s.journal != "" ? "article" : (s != null && s.url != "" && s.publisher == "" ? "www" : "book")));
                    if (s != null) {
                        if (s.authors.length > 0) o.append(" text:author=\"%s\"".printf(X.esc(string.joinv("; ", s.authors))));
                        string[,] kv = { { "title", s.title }, { "year", s.year }, { "publisher", s.publisher }, { "address", s.city }, { "journal", s.journal }, { "volume", s.volume }, { "number", s.issue }, { "pages", s.pages }, { "url", s.url }, { "edition", s.edition } };
                        for (int i = 0; i < kv.length[0]; i++) if (kv[i, 1] != "") o.append(" text:%s=\"%s\"".printf(kv[i, 0], X.esc(kv[i, 1])));
                    }
                    o.append(">%s</text:bibliography-mark>".printf(res));
                    break;
                case "MERGEFIELD":
                    o.append("<text:database-display text:table-name=\"\" text:table-type=\"table\" text:column-name=\"%s\">%s</text:database-display>".printf(X.esc(t.length > 1 ? t[1] : ""), res));
                    break;
                case "DOCVARIABLE":
                    o.append("<text:user-field-get text:name=\"%s\">%s</text:user-field-get>".printf(X.esc(t.length > 1 ? t[1] : ""), res));
                    break;
                case "DOCPROPERTY":
                    o.append("<text:user-defined text:name=\"%s\">%s</text:user-defined>".printf(X.esc(t.length > 1 ? t[1] : ""), res));
                    break;
                case "=":
                    o.append("<text:expression text:formula=\"ooow:%s\">%s</text:expression>".printf(X.esc(f.code.strip().substring(1).strip()), res));
                    break;
                default:
                    write_text(o, f.result);
                    break;
            }
        }

        private void write_note(StringBuilder o, NoteRef r) {
            note_n++;
            bool foot = r.note.kind == NoteKind.FOOTNOTE;
            o.append("<text:note text:id=\"ftn%d\" text:note-class=\"%s\"><text:note-citation%s>%s</text:note-citation><text:note-body>".printf(
                note_n, foot ? "footnote" : "endnote", r.note.custom_mark != null && r.note.custom_mark != "" ? " text:label=\"%s\"".printf(X.esc(r.note.custom_mark)) : "", note_n.to_string()));
            bool saved = in_header;
            in_header = true;
            write_blocks(o, r.note.blocks, false);
            in_header = saved;
            if (r.note.blocks.size == 0) o.append("<text:p text:style-name=\"Footnote\"/>");
            o.append("</text:note-body></text:note>");
        }

        private void write_annotation(StringBuilder o, string id) {
            var c = doc.find_comment(id);
            if (c == null) return;
            o.append("<office:annotation office:name=\"c%s\"".printf(X.esc(id)));
            if (c.done) o.append(" loext:resolved=\"true\"");
            if (c.parent_id != null) o.append(" loext:parent-name=\"c%s\"".printf(X.esc(c.parent_id)));
            o.append("><dc:creator>%s</dc:creator><dc:date>%s</dc:date><meta:creator-initials>%s</meta:creator-initials>".printf(X.esc(c.author), X.esc(c.date.replace("Z", "")), X.esc(c.initials)));
            bool saved = in_header;
            in_header = true;
            foreach (var b in c.blocks.items) {
                var p = b as Paragraph;
                if (p == null) continue;
                o.append("<text:p>");
                write_inlines(o, p.inlines);
                o.append("</text:p>");
            }
            in_header = saved;
            o.append("</office:annotation>");
            foreach (var reply in doc.comments) {
                if (reply.parent_id != id) continue;
                bool ranged = false;
                foreach (var p in doc.paragraphs(true)) foreach (var i in p.inlines) if (i is Mark && ((Mark) i).kind == MarkKind.COMMENT_START && ((Mark) i).name == reply.id) ranged = true;
                if (!ranged) {
                    write_annotation(o, reply.id);
                    o.append("<office:annotation-end office:name=\"c%s\"/>".printf(X.esc(reply.id)));
                }
            }
        }

        private string frame_style(FloatingInline f) {
            var sb = new StringBuilder("<style:graphic-properties");
            if (f.floating()) {
                string wrap = "parallel";
                switch (f.wrap) {
                    case Wrap.TOP_BOTTOM: wrap = "none"; break;
                    case Wrap.BEHIND:
                    case Wrap.FRONT: wrap = "run-through"; break;
                    default: break;
                }
                sb.append(" style:wrap=\"%s\" style:number-wrapped-paragraphs=\"no-limit\"".printf(wrap));
                if (f.wrap == Wrap.BEHIND) sb.append(" style:run-through=\"background\"");
                else if (f.wrap == Wrap.FRONT) sb.append(" style:run-through=\"foreground\"");
                if (f.wrap == Wrap.TIGHT) sb.append(" style:wrap-contour=\"true\" style:wrap-contour-mode=\"outside\"");
                string hp = f.halign == HAlignObj.CENTER ? "center" : (f.halign == HAlignObj.RIGHT ? "right" : (f.halign == HAlignObj.LEFT ? "left" : "from-left"));
                sb.append(" style:horizontal-pos=\"%s\" style:horizontal-rel=\"%s\"".printf(hp, f.hrel == HRel.PAGE ? "page" : (f.hrel == HRel.CHARACTER ? "char" : "paragraph")));
                sb.append(" style:vertical-pos=\"from-top\" style:vertical-rel=\"%s\"".printf(f.vrel == VRel.PAGE ? "page" : (f.vrel == VRel.LINE ? "line" : "paragraph")));
                sb.append(" fo:margin-left=\"%s\" fo:margin-right=\"%s\" fo:margin-top=\"%s\" fo:margin-bottom=\"%s\"".printf(pt(f.dist), pt(f.dist), pt(f.dist), pt(f.dist)));
            } else {
                sb.append(" style:vertical-pos=\"top\" style:vertical-rel=\"baseline\"");
            }
            var sh = f as ShapeRun;
            if (sh != null) {
                if (sh.fill != null) sb.append(" draw:fill=\"solid\" draw:fill-color=\"%s\"".printf(sh.fill));
                else sb.append(" draw:fill=\"none\"");
                if (sh.stroke != null) sb.append(" draw:stroke=\"solid\" svg:stroke-color=\"%s\" svg:stroke-width=\"%s\"".printf(sh.stroke, pt(sh.stroke_width)));
                else sb.append(" draw:stroke=\"none\"");
                if (sh.kind == ShapeKind.TEXT_BOX) sb.append(" fo:border=\"%s\" fo:padding=\"4pt\"".printf(sh.stroke != null ? "%s solid %s".printf(pt(sh.stroke_width), sh.stroke) : "none"));
            }
            sb.append("/>");
            return auto_style("graphic", "fr", "", sb.str);
        }

        private string frame_attrs(FloatingInline f) {
            frame_n++;
            string name = f.name != "" ? f.name : "Object%d".printf(frame_n);
            var sb = new StringBuilder(" draw:style-name=\"%s\" draw:name=\"%s\"".printf(frame_style(f), X.esc(name)));
            if (f.floating()) {
                sb.append(" text:anchor-type=\"%s\"".printf(f.hrel == HRel.PAGE && f.vrel == VRel.PAGE ? "paragraph" : (f.hrel == HRel.CHARACTER ? "char" : "paragraph")));
                if (f.halign == HAlignObj.NONE) sb.append(" svg:x=\"%s\"".printf(pt(f.hoff)));
                sb.append(" svg:y=\"%s\"".printf(pt(f.voff)));
            } else {
                sb.append(" text:anchor-type=\"as-char\"");
            }
            sb.append(" svg:width=\"%s\" svg:height=\"%s\" draw:z-index=\"%d\"".printf(pt(f.width), pt(f.height), frame_n));
            return sb.str;
        }

        private string meta_children(FloatingInline f) {
            var sb = new StringBuilder();
            if (f.title != "") sb.append("<svg:title>%s</svg:title>".printf(X.esc(f.title)));
            if (f.alt != "") sb.append("<svg:desc>%s</svg:desc>".printf(X.esc(f.alt)));
            return sb.str;
        }

        private string add_picture(Bytes data, string ext, string mime) {
            pic_n++;
            string path = "Pictures/image%d.%s".printf(pic_n, ext);
            try {
                zip.add(path, data.get_data(), false);
            } catch (Error e) {
            }
            manifest.add("<manifest:file-entry manifest:full-path=\"%s\" manifest:media-type=\"%s\"/>".printf(path, mime));
            return path;
        }

        private void write_image(StringBuilder o, ImageRun img) {
            string path = add_picture(img.data, img.extension(), img.mime);
            o.append("<draw:frame" + frame_attrs(img) + "><draw:image xlink:href=\"%s\" xlink:type=\"simple\" xlink:show=\"embed\" xlink:actuate=\"onLoad\"/>".printf(path));
            o.append(meta_children(img));
            o.append("</draw:frame>");
        }

        private void write_shape(StringBuilder o, ShapeRun s) {
            if (s.kind == ShapeKind.TEXT_BOX) {
                o.append("<draw:frame" + frame_attrs(s) + "><draw:text-box>");
                bool saved = in_header;
                in_header = true;
                write_blocks(o, s.text, false);
                in_header = saved;
                if (s.text.size == 0) o.append("<text:p/>");
                o.append("</draw:text-box>" + meta_children(s) + "</draw:frame>");
                return;
            }
            if (s.kind == ShapeKind.LINE) {
                frame_n++;
                o.append("<draw:line draw:style-name=\"%s\" text:anchor-type=\"paragraph\" svg:x1=\"%s\" svg:y1=\"%s\" svg:x2=\"%s\" svg:y2=\"%s\"/>".printf(
                    frame_style(s), pt(s.hoff), pt(s.voff), pt(s.hoff + s.width), pt(s.voff + s.height)));
                return;
            }
            string type = "rectangle";
            string path = "M 0 0 L 21600 0 21600 21600 0 21600 Z N";
            switch (s.kind) {
                case ShapeKind.ELLIPSE: type = "ellipse"; path = "U 10800 10800 10800 10800 0 360 Z N"; break;
                case ShapeKind.ROUND_RECT: type = "round-rectangle"; path = "M 3600 0 L 18000 0 21600 3600 21600 18000 18000 21600 3600 21600 0 18000 0 3600 Z N"; break;
                case ShapeKind.ARROW: type = "right-arrow"; path = "M 0 5400 L 16200 5400 16200 0 21600 10800 16200 21600 16200 16200 0 16200 Z N"; break;
                case ShapeKind.TRIANGLE: type = "isosceles-triangle"; path = "M 10800 0 L 21600 21600 0 21600 Z N"; break;
                default: break;
            }
            o.append("<draw:custom-shape" + frame_attrs(s) + ">");
            bool saved = in_header;
            in_header = true;
            foreach (var b in s.text.items) {
                var p = b as Paragraph;
                if (p == null || p.is_empty()) continue;
                o.append("<text:p>");
                write_inlines(o, p.inlines);
                o.append("</text:p>");
            }
            in_header = saved;
            o.append("<draw:enhanced-geometry svg:viewBox=\"0 0 21600 21600\" draw:type=\"%s\" draw:enhanced-path=\"%s\"/>".printf(type, path));
            o.append(meta_children(s) + "</draw:custom-shape>");
        }

        private void write_equation(StringBuilder o, EquationRun e) {
            string? mathml = e.mathml != "" ? e.mathml : null;
            if (mathml == null && e.omml != null) mathml = EquationCodec.omml_to_mathml != null ? EquationCodec.omml_to_mathml(e.omml, e.display) : Omml.to_mathml(e.omml, e.display);
            if (mathml == null) {
                write_text(o, e.linear_text());
                return;
            }
            obj_n++;
            string dir = "Object %d".printf(obj_n);
            string content;
            if (EquationCodec.mathml_to_odf != null) content = EquationCodec.mathml_to_odf(mathml, e.display) ?? "";
            else content = "";
            if (content == "") {
                string m = mathml;
                if (!m.contains("xmlns")) m = m.replace("<math", "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"");
                content = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" + m;
            }
            try {
                zip.add_text(dir + "/content.xml", content);
            } catch (Error err) {
            }
            manifest.add("<manifest:file-entry manifest:full-path=\"%s/\" manifest:version=\"1.3\" manifest:media-type=\"application/vnd.oasis.opendocument.formula\"/>".printf(dir));
            manifest.add("<manifest:file-entry manifest:full-path=\"%s/content.xml\" manifest:media-type=\"text/xml\"/>".printf(dir));
            double w = e.width > 0 ? e.width : 40;
            double asc = e.ascent > 0 ? e.ascent : 10;
            double h = asc + (e.descent > 0 ? e.descent : 4);
            string style = auto_style("graphic", "fr", "", "<style:graphic-properties style:vertical-pos=\"from-top\" style:vertical-rel=\"baseline\" fo:margin-left=\"0pt\" fo:margin-right=\"0pt\" draw:ole-draw-aspect=\"1\"/>");
            o.append("<draw:frame draw:style-name=\"%s\" draw:name=\"Formula%d\" text:anchor-type=\"as-char\" svg:y=\"%s\" svg:width=\"%s\" svg:height=\"%s\" draw:z-index=\"%d\">".printf(style, obj_n, pt(-asc), pt(w), pt(h), obj_n));
            o.append("<draw:object xlink:href=\"./%s\" xlink:type=\"simple\" xlink:show=\"embed\" xlink:actuate=\"onLoad\"/>".printf(dir));
            if (e.preview != null) {
                string rp = "ObjectReplacements/Object %d".printf(obj_n);
                try {
                    zip.add(rp, e.preview.get_data(), false);
                } catch (Error err) {
                }
                manifest.add("<manifest:file-entry manifest:full-path=\"%s\" manifest:media-type=\"image/png\"/>".printf(rp));
                o.append("<draw:image xlink:href=\"./%s\" xlink:type=\"simple\" xlink:show=\"embed\" xlink:actuate=\"onLoad\"/>".printf(rp));
            }
            o.append("<svg:desc>%s</svg:desc></draw:frame>".printf(X.esc(e.linear_text())));
        }

        private void write_field_block(StringBuilder o, FieldBlock fb, bool top) {
            string k = fb.kind();
            string tag = "text:table-of-content";
            string src = "<text:table-of-content-source text:outline-level=\"%d\"/>".printf(toc_levels(fb.code));
            if (k == "INDEX") {
                tag = "text:alphabetical-index";
                src = "<text:alphabetical-index-source text:main-entry-style-name=\"Index_20_1\"/>";
            } else if (k == "BIBLIOGRAPHY") {
                tag = "text:bibliography";
                src = "<text:bibliography-source/>";
            } else if (fb.code.contains("\\c")) {
                tag = "text:illustration-index";
                string[] t = Fields.tokenize(fb.code);
                src = "<text:illustration-index-source text:caption-sequence-name=\"%s\"/>".printf(X.esc(Fields.switch_arg(t, "\\c") ?? "Figure"));
            }
            frame_n++;
            o.append("<%s text:name=\"Index%d\">%s<text:index-body>".printf(tag, frame_n, src));
            foreach (var b in fb.result.items) write_block(o, b, false);
            o.append("</text:index-body></%s>".printf(tag));
        }

        private static int toc_levels(string code) {
            string[] t = Fields.tokenize(code);
            string? o = Fields.switch_arg(t, "\\o");
            if (o != null) {
                string[] r = o.split("-");
                if (r.length == 2) return int.parse(r[1]).clamp(1, 9);
            }
            return 3;
        }

        private void write_table(StringBuilder o, Table t, bool top) {
            frame_n++;
            string tname = "Table%d".printf(frame_n);
            double total = 0;
            foreach (double g in t.grid) total += g;
            string al = t.align == Align.CENTER ? "center" : (t.align == Align.RIGHT ? "right" : (t.indent != 0 ? "margins" : "left"));
            string tmaster = "";
            if (top && pending_master && !in_header) {
                tmaster = " style:master-page-name=\"%s\"".printf(masters[pending_section]);
                pending_master = false;
            }
            string tstyle = auto_style("table", "Tbl", "", "<style:table-properties style:width=\"%s\" table:align=\"%s\"%s/>".printf(pt(total), al, t.indent != 0 ? " fo:margin-left=\"%s\"".printf(pt(t.indent)) : ""), tmaster);
            o.append("<table:table table:name=\"%s\" table:style-name=\"%s\">".printf(tname, tstyle));
            foreach (double g in t.grid) {
                string cs = auto_style("table-column", "TC", "", "<style:table-column-properties style:column-width=\"%s\"/>".printf(pt(g)));
                o.append("<table:table-column table:style-name=\"%s\"/>".printf(cs));
            }
            var style = doc.styles.get(t.style);
            int header_rows = 0;
            while (header_rows < t.rows.size && t.rows[header_rows].header) header_rows++;
            for (int r = 0; r < t.rows.size; r++) {
                if (r == 0 && header_rows > 0) o.append("<table:table-header-rows>");
                var row = t.rows[r];
                string rs = "";
                if (row.height > 0) rs = auto_style("table-row", "TR", "", "<style:table-row-properties %s=\"%s\"%s/>".printf(row.height_exact ? "style:row-height" : "style:min-row-height", pt(row.height), row.cant_split ? " fo:keep-together=\"always\"" : ""));
                o.append(rs != "" ? "<table:table-row table:style-name=\"%s\">".printf(rs) : "<table:table-row>");
                int col = 0;
                for (int c = 0; c < row.cells.size; c++) {
                    var cell = row.cells[c];
                    if (cell.vmerge == VMerge.CONTINUE) {
                        for (int k = 0; k < cell.span; k++) o.append("<table:covered-table-cell/>");
                        col += cell.span;
                        continue;
                    }
                    int rspan = 1;
                    if (cell.vmerge == VMerge.RESTART) {
                        for (int rr = r + 1; rr < t.rows.size; rr++) {
                            var below = t.cell_at_grid(t.rows[rr], col);
                            if (below == null || below.vmerge != VMerge.CONTINUE) break;
                            rspan++;
                        }
                    }
                    var cp = new StringBuilder("<style:table-cell-properties fo:padding-left=\"%s\" fo:padding-right=\"%s\" fo:padding-top=\"%s\" fo:padding-bottom=\"%s\"".printf(pt(t.margin_l), pt(t.margin_r), pt(double.max(1, t.margin_t)), pt(double.max(1, t.margin_b))));
                    Border? bt = cell.top ?? (r == 0 ? t.border_top : t.border_h) ?? (style != null ? style.table_border : null);
                    Border? bb = cell.bottom ?? (r + rspan >= t.rows.size ? t.border_bottom : t.border_h) ?? (style != null ? style.table_border : null);
                    Border? bl = cell.left ?? (col == 0 ? t.border_left : t.border_v) ?? (style != null ? style.table_border : null);
                    Border? br = cell.right ?? (col + cell.span >= t.grid.length ? t.border_right : t.border_v) ?? (style != null ? style.table_border : null);
                    cp.append(" fo:border-top=\"%s\" fo:border-bottom=\"%s\" fo:border-left=\"%s\" fo:border-right=\"%s\"".printf(border_str(bt), border_str(bb), border_str(bl), border_str(br)));
                    string? shade = cell.shading;
                    if (shade == null && style != null && row.header && style.table_header_shading != null && t.look_first_row) shade = style.table_header_shading;
                    if (shade != null) cp.append(" fo:background-color=\"%s\"".printf(shade));
                    if (cell.valign != CellVAlign.TOP) cp.append(" style:vertical-align=\"%s\"".printf(cell.valign == CellVAlign.CENTER ? "middle" : "bottom"));
                    cp.append("/>");
                    string cs = auto_style("table-cell", "TD", "", cp.str);
                    o.append("<table:table-cell table:style-name=\"%s\" office:value-type=\"string\"".printf(cs));
                    if (cell.span > 1) o.append(" table:number-columns-spanned=\"%d\"".printf(cell.span));
                    if (rspan > 1) o.append(" table:number-rows-spanned=\"%d\"".printf(rspan));
                    o.append(">");
                    write_blocks(o, cell.blocks, false);
                    if (cell.blocks.size == 0) o.append("<text:p/>");
                    o.append("</table:table-cell>");
                    for (int k = 1; k < cell.span; k++) o.append("<table:covered-table-cell/>");
                    col += cell.span;
                }
                o.append("</table:table-row>");
                if (header_rows > 0 && r == header_rows - 1) o.append("</table:table-header-rows>");
            }
            o.append("</table:table>");
        }

        private string page_layout(Section s, int idx) {
            var sb = new StringBuilder();
            bool has_header = s.header_default != null || s.header_first != null || s.header_even != null;
            bool has_footer = s.footer_default != null || s.footer_first != null || s.footer_even != null;
            double header_h = has_header ? double.max(0, s.margin_top - s.header_dist) : 0;
            double footer_h = has_footer ? double.max(0, s.margin_bottom - s.footer_dist) : 0;
            sb.append("<style:page-layout style:name=\"pm%d\"><style:page-layout-properties fo:page-width=\"%s\" fo:page-height=\"%s\" style:print-orientation=\"%s\"".printf(
                idx, pt(s.page_w), pt(s.page_h), s.landscape ? "landscape" : "portrait"));
            sb.append(" fo:margin-top=\"%s\" fo:margin-bottom=\"%s\" fo:margin-left=\"%s\" fo:margin-right=\"%s\"".printf(
                pt(has_header ? s.header_dist : s.margin_top), pt(has_footer ? s.footer_dist : s.margin_bottom), pt(s.margin_left + s.gutter), pt(s.margin_right)));
            string fmt = s.page_format == NumFormat.LOWER_ROMAN ? "i" : (s.page_format == NumFormat.UPPER_ROMAN ? "I" : (s.page_format == NumFormat.LOWER_LETTER ? "a" : (s.page_format == NumFormat.UPPER_LETTER ? "A" : "1")));
            sb.append(" style:num-format=\"%s\"".printf(fmt));
            if (doc.page_color != null) sb.append(" fo:background-color=\"%s\"".printf(doc.page_color));
            if (s.page_border_top != null) sb.append(" fo:border=\"%s\" fo:padding=\"12pt\"".printf(border_str(s.page_border_top)));
            sb.append(">");
            if (s.columns > 1) {
                sb.append("<style:columns fo:column-count=\"%d\" fo:column-gap=\"%s\">".printf(s.columns, pt(s.column_space)));
                if (s.column_sep) sb.append("<style:column-sep style:width=\"0.5pt\" style:color=\"#000000\" style:height=\"100%\"/>");
                sb.append("</style:columns>");
            }
            sb.append("</style:page-layout-properties>");
            if (has_header) sb.append("<style:header-style><style:header-footer-properties fo:min-height=\"%s\" fo:margin-bottom=\"0pt\" style:dynamic-spacing=\"true\"/></style:header-style>".printf(pt(header_h)));
            else sb.append("<style:header-style/>");
            if (has_footer) sb.append("<style:footer-style><style:header-footer-properties fo:min-height=\"%s\" fo:margin-top=\"0pt\" style:dynamic-spacing=\"true\"/></style:footer-style>".printf(pt(footer_h)));
            else sb.append("<style:footer-style/>");
            sb.append("</style:page-layout>");
            return sb.str;
        }

        private string hf_content(HeaderFooter hf) {
            var sb = new StringBuilder();
            bool saved = in_header;
            in_header = true;
            write_blocks(sb, hf.blocks, false);
            in_header = saved;
            return sb.str;
        }

        private string styles_xml() {
            var named = new StringBuilder();
            named.append("<style:default-style style:family=\"paragraph\">");
            named.append(para_props(doc.styles.default_para));
            named.append(text_props(doc.styles.default_char));
            named.append("</style:default-style>");
            foreach (var s in doc.styles.list) {
                if (s.kind != StyleType.PARAGRAPH && s.kind != StyleType.CHARACTER) continue;
                string name = odf_name(doc, s.id);
                named.append("<style:style style:name=\"%s\" style:display-name=\"%s\" style:family=\"%s\"".printf(X.esc(name), X.esc(s.name), s.kind == StyleType.CHARACTER ? "text" : "paragraph"));
                if (s.based_on != null && doc.styles.get(s.based_on) != null) named.append(" style:parent-style-name=\"%s\"".printf(X.esc(odf_name(doc, s.based_on))));
                if (s.next != null && s.kind == StyleType.PARAGRAPH && doc.styles.get(s.next) != null) named.append(" style:next-style-name=\"%s\"".printf(X.esc(odf_name(doc, s.next))));
                if (s.para.outline >= 0 && s.para.outline < 9) named.append(" style:default-outline-level=\"%d\"".printf(s.para.outline + 1));
                named.append(s.id.has_prefix("Heading") || s.id == "Title" ? " style:class=\"text\">" : ">");
                if (s.kind == StyleType.PARAGRAPH) named.append(para_props(s.para));
                named.append(text_props(s.chr));
                named.append("</style:style>");
            }
            var layouts = new StringBuilder();
            var mp = new StringBuilder();
            for (int i = 0; i < section_list.size; i++) {
                var s = section_list[i];
                layouts.append(page_layout(s, i));
                mp.append("<style:master-page style:name=\"%s\" style:page-layout-name=\"pm%d\">".printf(masters[s], i));
                if (s.header_default != null || s.header_first != null || s.header_even != null) {
                    var h = s.header_default ?? new HeaderFooter();
                    mp.append("<style:header>%s</style:header>".printf(hf_content(h)));
                    if (s.header_even != null && doc.even_odd_headers) mp.append("<style:header-left>%s</style:header-left>".printf(hf_content(s.header_even)));
                    if (s.title_page) mp.append("<style:header-first>%s</style:header-first>".printf(s.header_first != null ? hf_content(s.header_first) : "<text:p/>"));
                }
                if (s.footer_default != null || s.footer_first != null || s.footer_even != null) {
                    var f = s.footer_default ?? new HeaderFooter();
                    mp.append("<style:footer>%s</style:footer>".printf(hf_content(f)));
                    if (s.footer_even != null && doc.even_odd_headers) mp.append("<style:footer-left>%s</style:footer-left>".printf(hf_content(s.footer_even)));
                    if (s.title_page) mp.append("<style:footer-first>%s</style:footer-first>".printf(s.footer_first != null ? hf_content(s.footer_first) : "<text:p/>"));
                }
                mp.append("</style:master-page>");
            }
            var sb = new StringBuilder();
            sb.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<office:document-styles " + NS + ">");
            sb.append(font_decls());
            sb.append("<office:styles>");
            sb.append(named.str);
            sb.append("<text:notes-configuration text:note-class=\"footnote\" style:num-format=\"%s\" text:start-value=\"0\" text:footnotes-position=\"page\" text:start-numbering-at=\"document\"/>".printf(odf_fmt(doc.footnote_format)));
            sb.append("<text:notes-configuration text:note-class=\"endnote\" style:num-format=\"%s\" text:start-value=\"0\"/>".printf(odf_fmt(doc.endnote_format)));
            sb.append("</office:styles><office:automatic-styles>");
            sb.append(layouts.str);
            sb.append(auto_styles_hf());
            sb.append("</office:automatic-styles><office:master-styles>");
            sb.append(mp.str);
            sb.append("</office:master-styles></office:document-styles>");
            return sb.str;
        }

        private string auto_styles_hf() {
            return auto_styles.str;
        }

        private static string odf_fmt(NumFormat f) {
            switch (f) {
                case NumFormat.LOWER_ROMAN: return "i";
                case NumFormat.UPPER_ROMAN: return "I";
                case NumFormat.LOWER_LETTER: return "a";
                case NumFormat.UPPER_LETTER: return "A";
                default: return "1";
            }
        }

        private string meta_xml() {
            var m = doc.meta;
            var now = new DateTime.now_utc().format("%Y-%m-%dT%H:%M:%S");
            var sb = new StringBuilder("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<office:document-meta " + NS + "><office:meta>");
            sb.append("<meta:generator>Singularity Write</meta:generator>");
            if (m.title != "") sb.append("<dc:title>%s</dc:title>".printf(X.esc(m.title)));
            if (m.subject != "") sb.append("<dc:subject>%s</dc:subject>".printf(X.esc(m.subject)));
            if (m.description != "") sb.append("<dc:description>%s</dc:description>".printf(X.esc(m.description)));
            if (m.author != "") sb.append("<meta:initial-creator>%s</meta:initial-creator>".printf(X.esc(m.author)));
            if (m.last_modified_by != "") sb.append("<dc:creator>%s</dc:creator>".printf(X.esc(m.last_modified_by)));
            if (m.keywords != "") foreach (string k in m.keywords.split(",")) if (k.strip() != "") sb.append("<meta:keyword>%s</meta:keyword>".printf(X.esc(k.strip())));
            sb.append("<meta:creation-date>%s</meta:creation-date>".printf(X.esc(m.created != "" ? m.created.replace("Z", "") : now)));
            sb.append("<dc:date>%s</dc:date>".printf(X.esc(m.modified != "" ? m.modified.replace("Z", "") : now)));
            sb.append("<meta:editing-cycles>%d</meta:editing-cycles>".printf(int.max(1, m.revision)));
            var st = Stats.compute(doc, false);
            sb.append("<meta:document-statistic meta:paragraph-count=\"%d\" meta:word-count=\"%d\" meta:character-count=\"%d\" meta:non-whitespace-character-count=\"%d\"/>".printf(st.paragraphs, st.words, st.chars, st.chars_no_spaces));
            foreach (var e in m.custom.entries) sb.append("<meta:user-defined meta:name=\"%s\">%s</meta:user-defined>".printf(X.esc(e.key), X.esc(e.value)));
            sb.append("</office:meta></office:document-meta>");
            return sb.str;
        }

        private string settings_xml() {
            var sb = new StringBuilder("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<office:document-settings " + NS + " xmlns:config=\"urn:oasis:names:tc:opendocument:xmlns:config:1.0\"><office:settings><config:config-item-set config:name=\"ooo:configuration-settings\">");
            sb.append("<config:config-item config:name=\"LoadReadonly\" config:type=\"boolean\">%s</config:config-item>".printf(doc.protection.kind == ProtectKind.READ_ONLY && doc.protection.enforced ? "true" : "false"));
            sb.append("<config:config-item config:name=\"ProtectForm\" config:type=\"boolean\">%s</config:config-item>".printf(doc.protection.kind == ProtectKind.FORMS && doc.protection.enforced ? "true" : "false"));
            sb.append("<config:config-item config:name=\"RecordChanges\" config:type=\"boolean\">%s</config:config-item>".printf(doc.track_changes ? "true" : "false"));
            for (int i = 0; i < doc.macros.size; i++) sb.append("<config:config-item config:name=\"SingularityMacro%02d\" config:type=\"string\">%s</config:config-item>".printf(i, X.esc(doc.macros[i])));
            sb.append("</config:config-item-set></office:settings></office:document-settings>");
            return sb.str;
        }
    }
}
