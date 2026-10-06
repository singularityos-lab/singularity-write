namespace Write {

    public delegate string? MathConvert(string input, bool display);

    public class EquationCodec : Object {
        public static MathConvert? mathml_to_omml = null;
        public static MathConvert? omml_to_mathml = null;
        public static MathConvert? mathml_to_odf = null;
        public static MathConvert? odf_to_mathml = null;
    }

    public class DocxWriter : Object {
        public const string NS = "xmlns:wpc=\"http://schemas.microsoft.com/office/word/2010/wordprocessingCanvas\" xmlns:mc=\"http://schemas.openxmlformats.org/markup-compatibility/2006\" xmlns:o=\"urn:schemas-microsoft-com:office:office\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:m=\"http://schemas.openxmlformats.org/officeDocument/2006/math\" xmlns:v=\"urn:schemas-microsoft-com:vml\" xmlns:wp14=\"http://schemas.microsoft.com/office/word/2010/wordprocessingDrawing\" xmlns:wp=\"http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing\" xmlns:w10=\"urn:schemas-microsoft-com:office:word\" xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:w14=\"http://schemas.microsoft.com/office/word/2010/wordml\" xmlns:w15=\"http://schemas.microsoft.com/office/word/2012/wordml\" xmlns:wpg=\"http://schemas.microsoft.com/office/word/2010/wordprocessingGroup\" xmlns:wpi=\"http://schemas.microsoft.com/office/word/2010/wordprocessingInk\" xmlns:wne=\"http://schemas.microsoft.com/office/word/2006/wordml\" xmlns:wps=\"http://schemas.microsoft.com/office/word/2010/wordprocessingShape\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:pic=\"http://schemas.openxmlformats.org/drawingml/2006/picture\" xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\" xmlns:dgm=\"http://schemas.openxmlformats.org/drawingml/2006/diagram\" xmlns:a14=\"http://schemas.microsoft.com/office/drawing/2010/main\" mc:Ignorable=\"w14 w15 wp14\"";
        public const string REL = "http://schemas.openxmlformats.org/officeDocument/2006/relationships";
        public const string CT_MAIN = "application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml";
        public const string CT_TEMPLATE = "application/vnd.openxmlformats-officedocument.wordprocessingml.template.main+xml";

        private Document doc;
        private ZipWriter zip = new ZipWriter();
        private Gee.HashMap<string, string> overrides = new Gee.HashMap<string, string>();
        private Gee.HashMap<string, string> defaults = new Gee.HashMap<string, string>();
        private Rels rels;
        private Rels doc_rels;
        private int media_n = 0;
        private int drawing_id = 1;
        private Gee.HashMap<string, int> bookmark_ids = new Gee.HashMap<string, int>();
        private int next_bookmark = 1;
        private Gee.ArrayList<Note> foot_list = new Gee.ArrayList<Note>();
        private Gee.ArrayList<Note> end_list = new Gee.ArrayList<Note>();
        private Gee.HashMap<HeaderFooter, string> hf_rid = new Gee.HashMap<HeaderFooter, string>();
        private int hf_n = 0;
        private Gee.HashMap<string, string> original_ct = new Gee.HashMap<string, string>();
        private Gee.HashMap<string, string> original_defaults = new Gee.HashMap<string, string>();
        private Gee.HashMap<string, string> comment_para = new Gee.HashMap<string, string>();
        public bool template = false;

        public class Rels : Object {
            public string part;
            public Gee.ArrayList<string> ids = new Gee.ArrayList<string>();
            public Gee.ArrayList<string> types = new Gee.ArrayList<string>();
            public Gee.ArrayList<string> targets = new Gee.ArrayList<string>();
            public Gee.ArrayList<bool> external = new Gee.ArrayList<bool>();

            public Rels(string part) {
                this.part = part;
            }

            public string add(string type, string target, bool ext = false) {
                for (int i = 0; i < ids.size; i++) {
                    if (types[i] == type && targets[i] == target && external[i] == ext) return ids[i];
                }
                string id = "rId%d".printf(ids.size + 1);
                ids.add(id);
                types.add(type);
                targets.add(target);
                external.add(ext);
                return id;
            }

            public string xml() {
                var o = new XmlOut();
                o.start("Relationships").a("xmlns", "http://schemas.openxmlformats.org/package/2006/relationships");
                for (int i = 0; i < ids.size; i++) {
                    o.start("Relationship").a("Id", ids[i]).a("Type", types[i]).a("Target", targets[i]);
                    if (external[i]) o.a("TargetMode", "External");
                    o.end();
                }
                return o.str();
            }
        }

        public static uint8[] save(Document doc, bool template = false) throws Error {
            var w = new DocxWriter(doc);
            w.template = template;
            return w.write();
        }

        public DocxWriter(Document doc) {
            this.doc = doc;
        }

        private static string rel_target(string from_part, string to_part) {
            int slash = from_part.last_index_of_char('/');
            string dir = slash >= 0 ? from_part.substring(0, slash + 1) : "";
            if (to_part.has_prefix(dir)) return to_part.substring(dir.length);
            string[] fp = dir.split("/");
            string[] tp = to_part.split("/");
            int common = 0;
            while (common < fp.length - 1 && common < tp.length - 1 && fp[common] == tp[common]) common++;
            var sb = new StringBuilder();
            for (int i = common; i < fp.length - 1; i++) sb.append("../");
            for (int i = common; i < tp.length; i++) {
                if (i > common) sb.append_c('/');
                sb.append(tp[i]);
            }
            return sb.str;
        }

        private void load_original_ct() {
            var ct = doc.passthrough["[Content_Types].xml"];
            if (ct == null) return;
            try {
                var sb = new StringBuilder();
                sb.append_len((string) ct.get_data(), (ssize_t) ct.get_size());
                Xml.Doc* x = X.parse(sb.str);
                foreach (var n in X.kids(x->get_root_element())) {
                    if (n->name == "Override") original_ct[X.val(n, "PartName").substring(1)] = X.val(n, "ContentType");
                    else if (n->name == "Default") original_defaults[X.val(n, "Extension").down()] = X.val(n, "ContentType");
                }
                delete x;
            } catch (Error e) {
            }
        }

        public uint8[] write() throws Error {
            load_original_ct();
            defaults["rels"] = "application/vnd.openxmlformats-package.relationships+xml";
            defaults["xml"] = "application/xml";
            doc_rels = new Rels("word/document.xml");
            rels = doc_rels;
            string body = document_xml();
            doc_rels.add(REL + "/styles", "styles.xml");
            zip.add_text("word/styles.xml", styles_xml());
            overrides["word/styles.xml"] = "application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml";
            if (doc.numbering.instances.size > 0) {
                doc_rels.add(REL + "/numbering", "numbering.xml");
                zip.add_text("word/numbering.xml", numbering_xml());
                overrides["word/numbering.xml"] = "application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml";
            }
            doc_rels.add(REL + "/settings", "settings.xml");
            zip.add_text("word/settings.xml", settings_xml());
            overrides["word/settings.xml"] = "application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml";
            write_notes();
            write_comments();
            write_sources();
            write_passthrough();
            zip.add_text("word/document.xml", body);
            overrides["word/document.xml"] = template ? CT_TEMPLATE : CT_MAIN;
            zip.add_text("word/_rels/document.xml.rels", doc_rels.xml());
            write_props();
            var pkg = new Rels("");
            pkg.add(REL + "/officeDocument", "word/document.xml");
            pkg.add("http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties", "docProps/core.xml");
            pkg.add(REL + "/extended-properties", "docProps/app.xml");
            if (doc.meta.custom.size > 0) pkg.add(REL + "/custom-properties", "docProps/custom.xml");
            if (doc.passthrough.has_key("docProps/thumbnail.jpeg")) pkg.add("http://schemas.openxmlformats.org/package/2006/relationships/metadata/thumbnail", "docProps/thumbnail.jpeg");
            zip.add_text("_rels/.rels", pkg.xml());
            var ct = new XmlOut();
            ct.start("Types").a("xmlns", "http://schemas.openxmlformats.org/package/2006/content-types");
            foreach (var e in original_defaults.entries) if (!defaults.has_key(e.key)) defaults[e.key] = e.value;
            foreach (var e in defaults.entries) ct.start("Default").a("Extension", e.key).a("ContentType", e.value).end();
            foreach (var e in overrides.entries) ct.start("Override").a("PartName", "/" + e.key).a("ContentType", e.value).end();
            zip.add_text("[Content_Types].xml", ct.str());
            return zip.finish();
        }

        private void write_passthrough() throws Error {
            foreach (var e in doc.passthrough.entries) {
                string name = e.key;
                if (name == "[Content_Types].xml") continue;
                if (zip.contains(name)) continue;
                zip.add(name, e.value.get_data());
                string ext = name.substring(name.last_index_of_char('.') + 1).down();
                if (original_ct.has_key(name)) overrides[name] = original_ct[name];
                else if (!defaults.has_key(ext) && original_defaults.has_key(ext)) defaults[ext] = original_defaults[ext];
                if (name == "word/theme/theme1.xml") doc_rels.add(REL + "/theme", "theme/theme1.xml");
                else if (name == "word/fontTable.xml") doc_rels.add(REL + "/fontTable", "fontTable.xml");
                else if (name == "word/webSettings.xml") doc_rels.add(REL + "/webSettings", "webSettings.xml");
                else if (name == "word/glossary/document.xml") doc_rels.add("http://schemas.openxmlformats.org/officeDocument/2006/relationships/glossaryDocument", "glossary/document.xml");
                else if (name.has_prefix("customXml/item") && !name.contains("Props") && name.has_suffix(".xml")) doc_rels.add(REL + "/customXml", "../" + name);
            }
        }

        private string document_xml() {
            var o = new XmlOut();
            o.raw("<w:document " + NS + ">");
            if (doc.page_color != null) o.start("w:background").a("w:color", doc.page_color.substring(1).up()).end();
            o.raw("<w:body>");
            write_blocks(o, doc.body);
            write_sect(o, doc.final_section);
            o.raw("</w:body></w:document>");
            return o.str();
        }

        private void write_blocks(XmlOut o, BlockList list) {
            foreach (var b in list.items) {
                if (b is Paragraph) write_paragraph(o, (Paragraph) b, null, false);
                else if (b is Table) write_table(o, (Table) b);
                else if (b is FieldBlock) write_field_block(o, (FieldBlock) b);
            }
        }

        private void write_field_block(XmlOut o, FieldBlock fb) {
            if (fb.result.size == 0) {
                var p = new Paragraph();
                write_paragraph(o, p, fb, true, true);
                return;
            }
            for (int i = 0; i < fb.result.size; i++) {
                var b = fb.result[i];
                bool first = i == 0;
                bool last = i == fb.result.size - 1;
                var p = b as Paragraph;
                if (p != null) {
                    write_paragraph(o, p, first ? fb : null, last, first);
                } else {
                    if (first) {
                        var begin = new Paragraph();
                        write_paragraph(o, begin, fb, false, true);
                    }
                    if (b is Table) write_table(o, (Table) b);
                    if (last) {
                        var endp = new Paragraph();
                        write_paragraph(o, endp, null, true, false);
                    }
                }
            }
        }

        private void write_border(XmlOut o, string tag, Border? b) {
            if (b == null) return;
            o.start(tag);
            if (!b.visible()) {
                o.a("w:val", "nil");
            } else {
                o.a("w:val", b.style);
                o.ai("w:sz", (int) Math.round(b.width * 8));
                o.ad("w:space", b.space);
                o.a("w:color", b.color.has_prefix("#") ? b.color.substring(1).up() : "auto");
            }
            o.end();
        }

        private static int tw(double pt) {
            return (int) Math.round(pt * 20);
        }

        private static string jc(Align a) {
            switch (a) {
                case Align.CENTER: return "center";
                case Align.RIGHT: return "right";
                case Align.JUSTIFY: return "both";
                default: return "left";
            }
        }

        public void write_ppr(XmlOut o, ParaProps pp, string? style, CharProps? mark, Revision? mark_rev, Section? sect, Paragraph? owner = null) {
            var tmp = new XmlOut(false);
            if (style != null && style != "Normal") tmp.start("w:pStyle").a("w:val", style).end();
            if (pp.keep_next != Tri.INHERIT) tmp.start("w:keepNext").a("w:val", pp.keep_next.on() ? "1" : "0").end();
            if (pp.keep_lines != Tri.INHERIT) tmp.start("w:keepLines").a("w:val", pp.keep_lines.on() ? "1" : "0").end();
            if (pp.page_break_before != Tri.INHERIT) tmp.start("w:pageBreakBefore").a("w:val", pp.page_break_before.on() ? "1" : "0").end();
            if (pp.dropcap_lines > 0) tmp.start("w:framePr").a("w:dropCap", pp.dropcap_margin ? "margin" : "drop").ai("w:lines", pp.dropcap_lines).a("w:wrap", "around").a("w:vAnchor", "text").a("w:hAnchor", "text").end();
            if (pp.widow != Tri.INHERIT) tmp.start("w:widowControl").a("w:val", pp.widow.on() ? "1" : "0").end();
            if (pp.num_id >= 0) {
                tmp.start("w:numPr");
                tmp.start("w:ilvl").ai("w:val", int.max(0, pp.num_level)).end();
                tmp.start("w:numId").ai("w:val", pp.num_id).end();
                tmp.end();
            }
            if (pp.border_top != null || pp.border_bottom != null || pp.border_left != null || pp.border_right != null) {
                tmp.start("w:pBdr");
                write_border(tmp, "w:top", pp.border_top);
                write_border(tmp, "w:left", pp.border_left);
                write_border(tmp, "w:bottom", pp.border_bottom);
                write_border(tmp, "w:right", pp.border_right);
                tmp.end();
            }
            if (pp.shading != null) tmp.start("w:shd").a("w:val", "clear").a("w:color", "auto").a("w:fill", pp.shading.substring(1).up()).end();
            if (pp.tabs != null && pp.tabs.size > 0) {
                tmp.start("w:tabs");
                foreach (var t in pp.tabs) {
                    string al = "left";
                    switch (t.align) {
                        case TabAlign.CENTER: al = "center"; break;
                        case TabAlign.RIGHT: al = "right"; break;
                        case TabAlign.DECIMAL: al = "decimal"; break;
                        case TabAlign.BAR: al = "bar"; break;
                        case TabAlign.CLEAR: al = "clear"; break;
                        default: break;
                    }
                    tmp.start("w:tab").a("w:val", al);
                    if (t.leader == TabLeader.DOT) tmp.a("w:leader", "dot");
                    else if (t.leader == TabLeader.HYPHEN) tmp.a("w:leader", "hyphen");
                    else if (t.leader == TabLeader.UNDERSCORE) tmp.a("w:leader", "underscore");
                    tmp.ai("w:pos", tw(t.pos)).end();
                }
                tmp.end();
            }
            if (!pp.space_before.is_nan() || !pp.space_after.is_nan() || !pp.line.is_nan()) {
                tmp.start("w:spacing");
                if (!pp.space_before.is_nan()) tmp.ai("w:before", tw(pp.space_before));
                if (!pp.space_after.is_nan()) tmp.ai("w:after", tw(pp.space_after));
                if (!pp.line.is_nan()) {
                    if (pp.line_rule == LineRule.AUTO) tmp.ai("w:line", (int) Math.round(pp.line * 240)).a("w:lineRule", "auto");
                    else tmp.ai("w:line", tw(pp.line)).a("w:lineRule", pp.line_rule == LineRule.EXACT ? "exact" : "atLeast");
                }
                tmp.end();
            }
            if (!pp.ind_left.is_nan() || !pp.ind_right.is_nan() || !pp.ind_first.is_nan()) {
                tmp.start("w:ind");
                if (!pp.ind_left.is_nan()) tmp.ai("w:left", tw(pp.ind_left));
                if (!pp.ind_right.is_nan()) tmp.ai("w:right", tw(pp.ind_right));
                if (!pp.ind_first.is_nan()) {
                    if (pp.ind_first < 0) tmp.ai("w:hanging", tw(-pp.ind_first));
                    else tmp.ai("w:firstLine", tw(pp.ind_first));
                }
                tmp.end();
            }
            if (pp.contextual != Tri.INHERIT) tmp.start("w:contextualSpacing").a("w:val", pp.contextual.on() ? "1" : "0").end();
            if (pp.align != Align.INHERIT) tmp.start("w:jc").a("w:val", jc(pp.align)).end();
            if (pp.outline >= 0) tmp.start("w:outlineLvl").ai("w:val", pp.outline).end();
            if ((mark != null && !mark.is_empty()) || mark_rev != null) {
                tmp.start("w:rPr");
                if (mark_rev != null) write_rev_attr(tmp, mark_rev.kind == RevKind.DELETE ? "w:del" : "w:ins", mark_rev, true);
                if (mark != null) write_rpr_inner(tmp, mark);
                tmp.end();
            }
            if (sect != null) write_sect(tmp, sect);
            if (owner != null && owner.props_rev != null) {
                write_rev_attr(tmp, "w:pPrChange", owner.props_rev, false);
                var old = new XmlOut(false);
                write_ppr(old, owner.props_old ?? new ParaProps(), owner.style_old, null, null, null);
                string os = old.str();
                tmp.raw(os != "" ? os : "<w:pPr/>");
                tmp.end();
            }
            string inner = tmp.str();
            if (inner != "") {
                o.raw("<w:pPr>");
                o.raw(inner);
                o.raw("</w:pPr>");
            }
        }

        private void write_rev_attr(XmlOut o, string tag, Revision r, bool empty) {
            o.start(tag).ai("w:id", r.id > 0 ? r.id : next_rev_id()).a("w:author", r.author);
            if (r.date != "") o.a("w:date", r.date);
            if (empty) o.end();
        }

        private int rev_counter = 1000;

        private int next_rev_id() {
            return rev_counter++;
        }

        public void write_rpr_inner(XmlOut o, CharProps c) {
            if (c.style != null) o.start("w:rStyle").a("w:val", c.style).end();
            if (c.font != null) o.start("w:rFonts").a("w:ascii", c.font).a("w:hAnsi", c.font).a("w:cs", c.font).a("w:eastAsia", c.font).end();
            if (c.bold != Tri.INHERIT) o.start("w:b").a("w:val", c.bold.on() ? "1" : "0").end();
            if (c.italic != Tri.INHERIT) o.start("w:i").a("w:val", c.italic.on() ? "1" : "0").end();
            if (c.caps == Caps.ALL) o.empty("w:caps");
            else if (c.caps == Caps.SMALL) o.empty("w:smallCaps");
            else if (c.caps == Caps.NONE) {
                o.start("w:caps").a("w:val", "0").end();
                o.start("w:smallCaps").a("w:val", "0").end();
            }
            if (c.strike != Tri.INHERIT) o.start("w:strike").a("w:val", c.strike.on() ? "1" : "0").end();
            if (c.dstrike != Tri.INHERIT) o.start("w:dstrike").a("w:val", c.dstrike.on() ? "1" : "0").end();
            if (c.outline != Tri.INHERIT) o.start("w:outline").a("w:val", c.outline.on() ? "1" : "0").end();
            if (c.shadow != Tri.INHERIT) o.start("w:shadow").a("w:val", c.shadow.on() ? "1" : "0").end();
            if (c.hidden != Tri.INHERIT) o.start("w:vanish").a("w:val", c.hidden.on() ? "1" : "0").end();
            if (c.color != null) o.start("w:color").a("w:val", c.color.substring(1).up()).end();
            if (!c.spacing.is_nan()) o.start("w:spacing").ai("w:val", tw(c.spacing)).end();
            if (!c.position.is_nan()) o.start("w:position").ai("w:val", (int) Math.round(c.position * 2)).end();
            if (c.size > 0) {
                o.start("w:sz").ai("w:val", (int) Math.round(c.size * 2)).end();
                o.start("w:szCs").ai("w:val", (int) Math.round(c.size * 2)).end();
            }
            if (c.highlight != null) {
                string hn = highlight_name(c.highlight);
                if (hn != "") o.start("w:highlight").a("w:val", hn).end();
            }
            if (c.underline != Underline.INHERIT) {
                string u = "single";
                switch (c.underline) {
                    case Underline.NONE: u = "none"; break;
                    case Underline.DOUBLE: u = "double"; break;
                    case Underline.DOTTED: u = "dotted"; break;
                    case Underline.DASHED: u = "dash"; break;
                    case Underline.WAVY: u = "wave"; break;
                    case Underline.THICK: u = "thick"; break;
                    case Underline.WORDS: u = "words"; break;
                    default: break;
                }
                o.start("w:u").a("w:val", u).end();
            }
            if (c.shading != null) o.start("w:shd").a("w:val", "clear").a("w:color", "auto").a("w:fill", c.shading.substring(1).up()).end();
            if (c.highlight != null && highlight_name(c.highlight) == "" && c.shading == null) o.start("w:shd").a("w:val", "clear").a("w:color", "auto").a("w:fill", c.highlight.substring(1).up()).end();
            if (c.valign == VAlign.SUPER) o.start("w:vertAlign").a("w:val", "superscript").end();
            else if (c.valign == VAlign.SUB) o.start("w:vertAlign").a("w:val", "subscript").end();
            else if (c.valign == VAlign.BASELINE) o.start("w:vertAlign").a("w:val", "baseline").end();
            if (c.lang != null) o.start("w:lang").a("w:val", c.lang).end();
        }

        public static string highlight_name(string hex) {
            switch (hex.down()) {
                case "#ffff00": return "yellow";
                case "#00ff00": return "green";
                case "#00ffff": return "cyan";
                case "#ff00ff": return "magenta";
                case "#0000ff": return "blue";
                case "#ff0000": return "red";
                case "#000080": return "darkBlue";
                case "#008080": return "darkCyan";
                case "#008000": return "darkGreen";
                case "#800080": return "darkMagenta";
                case "#800000": return "darkRed";
                case "#808000": return "darkYellow";
                case "#808080": return "darkGray";
                case "#c0c0c0": return "lightGray";
                case "#000000": return "black";
                case "#ffffff": return "white";
                case "none": return "none";
                default: return "";
            }
        }

        private void write_rpr(XmlOut o, CharProps c, Inline? item = null) {
            var tmp = new XmlOut(false);
            write_rpr_inner(tmp, c);
            if (item != null && item.fmt_rev != null && item.fmt_old != null) {
                write_rev_attr(tmp, "w:rPrChange", item.fmt_rev, false);
                tmp.start("w:rPr");
                write_rpr_inner(tmp, item.fmt_old);
                tmp.end();
                tmp.end();
            }
            string inner = tmp.str();
            if (inner != "") {
                o.raw("<w:rPr>");
                o.raw(inner);
                o.raw("</w:rPr>");
            }
        }

        private void write_paragraph(XmlOut o, Paragraph p, FieldBlock? begin_field, bool end_field, bool field_first = false) {
            o.raw("<w:p");
            if (current_comment_para != null) {
                o.raw(" w14:paraId=\"" + current_comment_para + "\" w14:textId=\"77777777\"");
            }
            o.raw(">");
            write_ppr(o, p.props, p.style, p.mark_props, p.mark_rev, p.section, p);
            if (begin_field != null) {
                field_begin(o, begin_field.code, new CharProps(), false, false);
                o.raw("<w:r><w:fldChar w:fldCharType=\"separate\"/></w:r>");
            }
            write_inlines(o, p.inlines);
            if (end_field) o.raw("<w:r><w:fldChar w:fldCharType=\"end\"/></w:r>");
            o.raw("</w:p>");
        }

        private string? current_comment_para = null;

        private void field_begin(XmlOut o, string code, CharProps props, bool deleted, bool dirty) {
            o.raw("<w:r>");
            write_rpr(o, props);
            o.raw(dirty ? "<w:fldChar w:fldCharType=\"begin\" w:dirty=\"true\"/></w:r>" : "<w:fldChar w:fldCharType=\"begin\"/></w:r>");
            o.raw("<w:r>");
            write_rpr(o, props);
            string tag = deleted ? "w:delInstrText" : "w:instrText";
            o.raw("<" + tag + " xml:space=\"preserve\"> ");
            o.raw(X.esc(code));
            o.raw(" </" + tag + "></w:r>");
        }

        private void write_inlines(XmlOut o, Gee.List<Inline> inlines) {
            int i = 0;
            while (i < inlines.size) {
                string? link = inlines[i].props.link;
                int j = i;
                while (j < inlines.size && inlines[j].props.link == link) j++;
                if (link != null && link != "") {
                    o.raw("<w:hyperlink");
                    int hash = link.index_of_char('#');
                    string url = hash >= 0 ? link.substring(0, hash) : link;
                    string anchor = hash >= 0 ? link.substring(hash + 1) : "";
                    if (url != "") o.raw(" r:id=\"" + rels.add(REL + "/hyperlink", url, true) + "\"");
                    if (anchor != "") o.raw(" w:anchor=\"" + X.esc(anchor) + "\"");
                    o.raw(" w:history=\"1\">");
                }
                write_rev_groups(o, inlines, i, j);
                if (link != null && link != "") o.raw("</w:hyperlink>");
                i = j;
            }
        }

        private void write_rev_groups(XmlOut o, Gee.List<Inline> inlines, int from, int to) {
            int i = from;
            while (i < to) {
                Revision? r = inlines[i].rev;
                int j = i;
                while (j < to && same_rev(inlines[j].rev, r)) j++;
                if (r != null) write_rev_attr(o, r.kind == RevKind.DELETE ? "w:del" : "w:ins", r, false);
                for (int k = i; k < j; k++) write_inline(o, inlines[k], r != null && r.kind == RevKind.DELETE);
                if (r != null) o.end();
                i = j;
            }
        }

        private static bool same_rev(Revision? a, Revision? b) {
            if (a == null || b == null) return a == b;
            return a.kind == b.kind && a.author == b.author && a.date == b.date;
        }

        private CharProps run_props(Inline item) {
            var c = item.props.copy();
            c.link = null;
            return c;
        }

        private void write_inline(XmlOut o, Inline item, bool deleted) {
            var props = run_props(item);
            if (item is TextRun) {
                string t = ((TextRun) item).text;
                write_text_run(o, t, props, item, deleted);
            } else if (item is Tab) {
                o.raw("<w:r>");
                write_rpr(o, props, item);
                o.raw("<w:tab/></w:r>");
            } else if (item is Break) {
                var b = (Break) item;
                o.raw("<w:r>");
                write_rpr(o, props, item);
                if (b.kind == BreakKind.PAGE) o.raw("<w:br w:type=\"page\"/>");
                else if (b.kind == BreakKind.COLUMN) o.raw("<w:br w:type=\"column\"/>");
                else o.raw("<w:br/>");
                o.raw("</w:r>");
            } else if (item is FieldRun) {
                var f = (FieldRun) item;
                if (f.code.has_prefix("\x01")) return;
                field_begin(o, f.code, props, deleted, f.dirty);
                o.raw("<w:r><w:fldChar w:fldCharType=\"separate\"/></w:r>");
                write_text_run(o, f.result, props, null, deleted);
                o.raw("<w:r><w:fldChar w:fldCharType=\"end\"/></w:r>");
            } else if (item is NoteRef) {
                var n = (NoteRef) item;
                bool foot = n.note.kind == NoteKind.FOOTNOTE;
                var list = foot ? foot_list : end_list;
                int id = list.size + 1;
                list.add(n.note);
                var rp = props.copy();
                if (rp.style == null) rp.style = foot ? "FootnoteReference" : "EndnoteReference";
                o.raw("<w:r>");
                write_rpr(o, rp);
                o.raw(foot ? "<w:footnoteReference w:id=\"%d\"/>".printf(id) : "<w:endnoteReference w:id=\"%d\"/>".printf(id));
                o.raw("</w:r>");
            } else if (item is Mark) {
                var m = (Mark) item;
                switch (m.kind) {
                    case MarkKind.BOOKMARK_START:
                        int id = next_bookmark++;
                        bookmark_ids[m.name] = id;
                        o.raw("<w:bookmarkStart w:id=\"%d\" w:name=\"%s\"/>".printf(id, X.esc(m.name)));
                        break;
                    case MarkKind.BOOKMARK_END:
                        if (bookmark_ids.has_key(m.name)) o.raw("<w:bookmarkEnd w:id=\"%d\"/>".printf(bookmark_ids[m.name]));
                        break;
                    case MarkKind.COMMENT_START:
                        o.raw("<w:commentRangeStart w:id=\"%s\"/>".printf(X.esc(m.name)));
                        break;
                    case MarkKind.COMMENT_END:
                        o.raw("<w:commentRangeEnd w:id=\"%s\"/>".printf(X.esc(m.name)));
                        o.raw("<w:r><w:rPr><w:rStyle w:val=\"CommentReference\"/></w:rPr><w:commentReference w:id=\"%s\"/></w:r>".printf(X.esc(m.name)));
                        break;
                    case MarkKind.INDEX_ENTRY:
                        field_begin(o, "XE \"" + m.name.replace("\"", "") + "\"", props, deleted, false);
                        o.raw("<w:r><w:fldChar w:fldCharType=\"end\"/></w:r>");
                        break;
                    default:
                        break;
                }
            } else if (item is ImageRun) {
                o.raw("<w:r>");
                write_rpr(o, props);
                write_image(o, (ImageRun) item);
                o.raw("</w:r>");
            } else if (item is ShapeRun) {
                o.raw("<w:r>");
                write_rpr(o, props);
                write_shape(o, (ShapeRun) item);
                o.raw("</w:r>");
            } else if (item is EquationRun) {
                var e = (EquationRun) item;
                string? omml = e.omml;
                if (omml == null && e.mathml != "") omml = EquationCodec.mathml_to_omml != null ? EquationCodec.mathml_to_omml(e.mathml, e.display) : Omml.from_mathml(e.mathml, e.display);
                if (omml != null) {
                    if (!e.display && omml.contains("oMathPara")) {
                        int s = omml.index_of("<m:oMath>");
                        if (s < 0) s = omml.index_of("<m:oMath ");
                        int en = omml.last_index_of("</m:oMath>");
                        if (s >= 0 && en > s) omml = omml.substring(s, en + 10 - s);
                    }
                    o.raw(omml);
                } else {
                    write_text_run(o, e.linear_text(), props, null, deleted);
                }
            } else if (item is FormField) {
                write_form(o, (FormField) item, props);
            } else if (item is ChartRun) {
                write_chart(o, (ChartRun) item, props, deleted);
            } else if (item is OpaqueRun) {
                var op = (OpaqueRun) item;
                string xml = op.xml;
                foreach (var e in op.rels.entries) {
                    string[] tt = e.value.split("\n", 2);
                    if (tt.length != 2) continue;
                    string part = tt[1];
                    string nid = rels.add(tt[0], rel_target(rels.part, part));
                    xml = xml.replace("\"" + e.key + "\"", "\"" + nid + "\"");
                }
                foreach (var e in op.parts.entries) {
                    if (zip.contains(e.key)) continue;
                    try {
                        zip.add(e.key, e.value.get_data());
                    } catch (Error err) {
                    }
                    if (original_ct.has_key(e.key)) overrides[e.key] = original_ct[e.key];
                    string ext = e.key.substring(e.key.last_index_of_char('.') + 1).down();
                    if (!defaults.has_key(ext) && original_defaults.has_key(ext)) defaults[ext] = original_defaults[ext];
                }
                o.raw("<w:r>");
                write_rpr(o, props);
                o.raw(xml);
                o.raw("</w:r>");
            }
        }

        private void write_text_run(XmlOut o, string text, CharProps props, Inline? item, bool deleted) {
            if (text == "") return;
            o.raw("<w:r>");
            write_rpr(o, props, item);
            string tag = deleted ? "w:delText" : "w:t";
            var sb = new StringBuilder();
            unichar c;
            int i = 0;
            while (text.get_next_char(ref i, out c)) {
                if (c == 0x00AD || c == 0x2011 || c == '\t' || c == '\n') {
                    if (sb.len > 0) {
                        o.raw("<" + tag + " xml:space=\"preserve\">" + X.esc(sb.str) + "</" + tag + ">");
                        sb.truncate(0);
                    }
                    if (c == 0x00AD) o.raw("<w:softHyphen/>");
                    else if (c == 0x2011) o.raw("<w:noBreakHyphen/>");
                    else if (c == '\t') o.raw("<w:tab/>");
                    else o.raw("<w:br/>");
                    continue;
                }
                sb.append_unichar(c);
            }
            if (sb.len > 0) o.raw("<" + tag + " xml:space=\"preserve\">" + X.esc(sb.str) + "</" + tag + ">");
            o.raw("</w:r>");
        }

        private void write_form(XmlOut o, FormField f, CharProps props) {
            o.raw("<w:sdt><w:sdtPr>");
            if (f.name != "") o.raw("<w:alias w:val=\"%s\"/><w:tag w:val=\"%s\"/>".printf(X.esc(f.name), X.esc(f.name)));
            bool placeholder = f.kind != FormKind.CHECKBOX && f.value == "";
            if (placeholder) o.raw("<w:showingPlcHdr/>");
            switch (f.kind) {
                case FormKind.CHECKBOX:
                    o.raw("<w14:checkbox><w14:checked w14:val=\"%s\"/><w14:checkedState w14:val=\"2612\" w14:font=\"MS Gothic\"/><w14:uncheckedState w14:val=\"2610\" w14:font=\"MS Gothic\"/></w14:checkbox>".printf(f.checked ? "1" : "0"));
                    break;
                case FormKind.DROPDOWN:
                    o.raw("<w:dropDownList>");
                    foreach (string opt in f.options) o.raw("<w:listItem w:displayText=\"%s\" w:value=\"%s\"/>".printf(X.esc(opt), X.esc(opt)));
                    o.raw("</w:dropDownList>");
                    break;
                case FormKind.DATE:
                    o.raw("<w:date><w:dateFormat w:val=\"d MMMM yyyy\"/></w:date>");
                    break;
                default:
                    o.raw("<w:text/>");
                    break;
            }
            o.raw("</w:sdtPr><w:sdtContent>");
            write_text_run(o, f.kind == FormKind.CHECKBOX ? f.display_text() : (f.value != "" ? f.value : (f.placeholder != "" ? f.placeholder : _("Click to enter text."))), props, null, false);
            o.raw("</w:sdtContent></w:sdt>");
        }

        private string emu(double pt) {
            return ((int64) Math.round(pt * 12700)).to_string();
        }

        private void anchor_open(XmlOut o, FloatingInline f) {
            if (!f.floating()) {
                o.raw("<wp:inline distT=\"0\" distB=\"0\" distL=\"0\" distR=\"0\">");
                o.raw("<wp:extent cx=\"%s\" cy=\"%s\"/>".printf(emu(f.width), emu(f.height)));
                o.raw("<wp:effectExtent l=\"0\" t=\"0\" r=\"0\" b=\"0\"/>");
                return;
            }
            string d = emu(f.dist);
            o.raw("<wp:anchor distT=\"%s\" distB=\"%s\" distL=\"%s\" distR=\"%s\" simplePos=\"0\" relativeHeight=\"%d\" behindDoc=\"%s\" locked=\"0\" layoutInCell=\"1\" allowOverlap=\"1\">".printf(
                d, d, d, d, 251658240 + drawing_id, f.wrap == Wrap.BEHIND ? "1" : "0"));
            o.raw("<wp:simplePos x=\"0\" y=\"0\"/>");
            string hr = f.hrel == HRel.PAGE ? "page" : (f.hrel == HRel.MARGIN ? "margin" : (f.hrel == HRel.CHARACTER ? "character" : "column"));
            o.raw("<wp:positionH relativeFrom=\"%s\">".printf(hr));
            if (f.halign != HAlignObj.NONE) o.raw("<wp:align>%s</wp:align>".printf(f.halign == HAlignObj.CENTER ? "center" : (f.halign == HAlignObj.RIGHT ? "right" : "left")));
            else o.raw("<wp:posOffset>%s</wp:posOffset>".printf(emu(f.hoff)));
            o.raw("</wp:positionH>");
            string vr = f.vrel == VRel.PAGE ? "page" : (f.vrel == VRel.MARGIN ? "margin" : (f.vrel == VRel.LINE ? "line" : "paragraph"));
            o.raw("<wp:positionV relativeFrom=\"%s\"><wp:posOffset>%s</wp:posOffset></wp:positionV>".printf(vr, emu(f.voff)));
            o.raw("<wp:extent cx=\"%s\" cy=\"%s\"/>".printf(emu(f.width), emu(f.height)));
            o.raw("<wp:effectExtent l=\"0\" t=\"0\" r=\"0\" b=\"0\"/>");
            switch (f.wrap) {
                case Wrap.SQUARE: o.raw("<wp:wrapSquare wrapText=\"bothSides\"/>"); break;
                case Wrap.TIGHT: o.raw("<wp:wrapTight wrapText=\"bothSides\"><wp:wrapPolygon edited=\"0\"><wp:start x=\"0\" y=\"0\"/><wp:lineTo x=\"0\" y=\"21600\"/><wp:lineTo x=\"21600\" y=\"21600\"/><wp:lineTo x=\"21600\" y=\"0\"/><wp:lineTo x=\"0\" y=\"0\"/></wp:wrapPolygon></wp:wrapTight>"); break;
                case Wrap.TOP_BOTTOM: o.raw("<wp:wrapTopAndBottom/>"); break;
                default: o.raw("<wp:wrapNone/>"); break;
            }
        }

        private void doc_pr(XmlOut o, FloatingInline f, string fallback) {
            int id = drawing_id++;
            string name = f.name != "" ? f.name : "%s %d".printf(fallback, id);
            o.raw("<wp:docPr id=\"%d\" name=\"%s\"".printf(id, X.esc(name)));
            if (f.alt != "") o.raw(" descr=\"" + X.esc(f.alt) + "\"");
            if (f.title != "") o.raw(" title=\"" + X.esc(f.title) + "\"");
            o.raw("/>");
        }

        private int chart_n = 0;

        private void write_chart(XmlOut o, ChartRun ch, CharProps props, bool deleted) {
            if (!ch.edited && ch.original != null && ch.original.format == "docx-drawing") {
                write_inline(o, ch.original, deleted);
                return;
            }
            if (ch.chart_xml == "") {
                if (ch.preview == null) return;
                var img = new ImageRun(ch.preview, "image/png");
                img.width = ch.width;
                img.height = ch.height;
                img.alt = ch.alt;
                img.title = ch.title;
                o.raw("<w:r>");
                write_rpr(o, props);
                write_image(o, img);
                o.raw("</w:r>");
                return;
            }
            chart_n++;
            string part = "word/charts/chart%d.xml".printf(chart_n);
            while (zip.contains(part)) part = "word/charts/chart%d.xml".printf(++chart_n);
            try {
                zip.add(part, ch.chart_xml.data);
            } catch (Error e) {
            }
            overrides[part] = ch.extended ? "application/vnd.ms-office.chartex+xml" : "application/vnd.openxmlformats-officedocument.drawingml.chart+xml";
            string rid = rels.add(ch.extended ? "http://schemas.microsoft.com/office/2014/relationships/chartEx" : REL + "/chart", rel_target(rels.part, part));
            o.raw("<w:r>");
            write_rpr(o, props);
            o.raw("<w:drawing>");
            anchor_open(o, ch);
            doc_pr(o, ch, "Chart");
            o.raw("<wp:cNvGraphicFramePr/>");
            if (ch.extended) {
                o.raw("<a:graphic><a:graphicData uri=\"http://schemas.microsoft.com/office/drawing/2014/chartex\"><cx:chart xmlns:cx=\"http://schemas.microsoft.com/office/drawing/2014/chartex\" r:id=\"%s\"/></a:graphicData></a:graphic>".printf(rid));
            } else {
                o.raw("<a:graphic><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/chart\"><c:chart r:id=\"%s\"/></a:graphicData></a:graphic>".printf(rid));
            }
            o.raw(ch.floating() ? "</wp:anchor>" : "</wp:inline>");
            o.raw("</w:drawing></w:r>");
        }

        private void write_image(XmlOut o, ImageRun img) {
            media_n++;
            string ext = img.extension();
            string part = "word/media/image%d.%s".printf(media_n, ext);
            try {
                zip.add(part, img.data.get_data(), false);
            } catch (Error e) {
            }
            if (!defaults.has_key(ext)) defaults[ext] = img.mime;
            string rid = rels.add(REL + "/image", rel_target(rels.part, part));
            o.raw("<w:drawing>");
            anchor_open(o, img);
            doc_pr(o, img, "Picture");
            o.raw("<wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect=\"1\"/></wp:cNvGraphicFramePr>");
            o.raw("<a:graphic><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/picture\"><pic:pic>");
            o.raw("<pic:nvPicPr><pic:cNvPr id=\"0\" name=\"image%d.%s\"/><pic:cNvPicPr/></pic:nvPicPr>".printf(media_n, ext));
            o.raw("<pic:blipFill><a:blip r:embed=\"%s\">".printf(rid));
            if (img.grayscale) o.raw("<a:grayscl/>");
            if (img.brightness != 0 || img.contrast != 0) o.raw("<a:lum bright=\"%d\" contrast=\"%d\"/>".printf((int) (img.brightness * 100000), (int) (img.contrast * 100000)));
            o.raw("</a:blip>");
            if (img.crop_l > 0 || img.crop_t > 0 || img.crop_r > 0 || img.crop_b > 0) {
                o.raw("<a:srcRect l=\"%d\" t=\"%d\" r=\"%d\" b=\"%d\"/>".printf((int) (img.crop_l * 100000), (int) (img.crop_t * 100000), (int) (img.crop_r * 100000), (int) (img.crop_b * 100000)));
            }
            o.raw("<a:stretch><a:fillRect/></a:stretch></pic:blipFill>");
            o.raw("<pic:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"%s\" cy=\"%s\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom>".printf(emu(img.width), emu(img.height)));
            if (img.outline_border != null && img.outline_border.visible()) {
                o.raw("<a:ln w=\"%s\"><a:solidFill><a:srgbClr val=\"%s\"/></a:solidFill></a:ln>".printf(emu(img.outline_border.width), img.outline_border.color.substring(1).up()));
            }
            o.raw("</pic:spPr></pic:pic></a:graphicData></a:graphic>");
            o.raw(img.floating() ? "</wp:anchor>" : "</wp:inline>");
            o.raw("</w:drawing>");
        }

        private void write_shape(XmlOut o, ShapeRun s) {
            string prst = "rect";
            switch (s.kind) {
                case ShapeKind.ROUND_RECT: prst = "roundRect"; break;
                case ShapeKind.ELLIPSE: prst = "ellipse"; break;
                case ShapeKind.LINE: prst = "line"; break;
                case ShapeKind.ARROW: prst = "rightArrow"; break;
                case ShapeKind.TRIANGLE: prst = "triangle"; break;
                default: break;
            }
            o.raw("<mc:AlternateContent><mc:Choice Requires=\"wps\"><w:drawing>");
            anchor_open(o, s);
            doc_pr(o, s, s.kind == ShapeKind.TEXT_BOX ? "Text Box" : "Shape");
            o.raw("<wp:cNvGraphicFramePr/><a:graphic><a:graphicData uri=\"http://schemas.microsoft.com/office/word/2010/wordprocessingShape\"><wps:wsp>");
            o.raw(s.kind == ShapeKind.TEXT_BOX ? "<wps:cNvSpPr txBox=\"1\"/>" : "<wps:cNvSpPr/>");
            o.raw("<wps:spPr><a:xfrm");
            if (s.rotation != 0) o.raw(" rot=\"%d\"".printf((int) (s.rotation * 60000)));
            o.raw("><a:off x=\"0\" y=\"0\"/><a:ext cx=\"%s\" cy=\"%s\"/></a:xfrm>".printf(emu(s.width), emu(s.height)));
            o.raw("<a:prstGeom prst=\"%s\"><a:avLst/></a:prstGeom>".printf(prst));
            if (s.fill != null) o.raw("<a:solidFill><a:srgbClr val=\"%s\"/></a:solidFill>".printf(s.fill.substring(1).up()));
            else o.raw("<a:noFill/>");
            if (s.stroke != null) o.raw("<a:ln w=\"%s\"><a:solidFill><a:srgbClr val=\"%s\"/></a:solidFill></a:ln>".printf(emu(s.stroke_width), s.stroke.substring(1).up()));
            else o.raw("<a:ln><a:noFill/></a:ln>");
            o.raw("</wps:spPr>");
            if (s.text.size > 0 && (s.kind == ShapeKind.TEXT_BOX || !s.text.first_paragraph().is_empty() || s.text.size > 1)) {
                o.raw("<wps:txbx><w:txbxContent>");
                write_blocks(o, s.text);
                o.raw("</w:txbxContent></wps:txbx>");
            }
            o.raw("<wps:bodyPr rot=\"0\" vert=\"horz\" wrap=\"square\" lIns=\"91440\" tIns=\"45720\" rIns=\"91440\" bIns=\"45720\" anchor=\"t\" anchorCtr=\"0\"><a:noAutofit/></wps:bodyPr>");
            o.raw("</wps:wsp></a:graphicData></a:graphic>");
            o.raw(s.floating() ? "</wp:anchor>" : "</wp:inline>");
            o.raw("</w:drawing></mc:Choice></mc:AlternateContent>");
        }

        private void write_table(XmlOut o, Table t) {
            o.raw("<w:tbl><w:tblPr>");
            if (t.style != null && t.style != "PlainTable") o.raw("<w:tblStyle w:val=\"%s\"/>".printf(X.esc(t.style)));
            if (t.width > 0) {
                if (t.width_pct) o.raw("<w:tblW w:w=\"%d\" w:type=\"pct\"/>".printf((int) (t.width * 50)));
                else o.raw("<w:tblW w:w=\"%d\" w:type=\"dxa\"/>".printf(tw(t.width)));
            } else {
                o.raw("<w:tblW w:w=\"0\" w:type=\"auto\"/>");
            }
            if (t.align != Align.LEFT) o.raw("<w:jc w:val=\"%s\"/>".printf(jc(t.align)));
            if (t.indent != 0) o.raw("<w:tblInd w:w=\"%d\" w:type=\"dxa\"/>".printf(tw(t.indent)));
            if (t.border_top != null || t.border_bottom != null || t.border_left != null || t.border_right != null || t.border_h != null || t.border_v != null) {
                var tmp = new XmlOut(false);
                tmp.start("w:tblBorders");
                write_border(tmp, "w:top", t.border_top);
                write_border(tmp, "w:left", t.border_left);
                write_border(tmp, "w:bottom", t.border_bottom);
                write_border(tmp, "w:right", t.border_right);
                write_border(tmp, "w:insideH", t.border_h);
                write_border(tmp, "w:insideV", t.border_v);
                tmp.end();
                o.raw(tmp.str());
            }
            if (t.fixed_layout) o.raw("<w:tblLayout w:type=\"fixed\"/>");
            o.raw("<w:tblCellMar><w:top w:w=\"%d\" w:type=\"dxa\"/><w:left w:w=\"%d\" w:type=\"dxa\"/><w:bottom w:w=\"%d\" w:type=\"dxa\"/><w:right w:w=\"%d\" w:type=\"dxa\"/></w:tblCellMar>".printf(
                tw(t.margin_t), tw(t.margin_l), tw(t.margin_b), tw(t.margin_r)));
            o.raw("<w:tblLook w:val=\"%04X\" w:firstRow=\"%s\" w:lastRow=\"%s\" w:firstColumn=\"%s\" w:lastColumn=\"0\" w:noHBand=\"%s\" w:noVBand=\"1\"/>".printf(
                (t.look_first_row ? 0x20 : 0) | (t.look_last_row ? 0x40 : 0) | (t.look_first_col ? 0x80 : 0) | (t.look_banded_rows ? 0 : 0x200) | 0x400,
                t.look_first_row ? "1" : "0", t.look_last_row ? "1" : "0", t.look_first_col ? "1" : "0", t.look_banded_rows ? "0" : "1"));
            if (t.caption != "") o.raw("<w:tblCaption w:val=\"%s\"/>".printf(X.esc(t.caption)));
            if (t.description != "") o.raw("<w:tblDescription w:val=\"%s\"/>".printf(X.esc(t.description)));
            o.raw("</w:tblPr><w:tblGrid>");
            foreach (double g in t.grid) o.raw("<w:gridCol w:w=\"%d\"/>".printf(tw(g)));
            o.raw("</w:tblGrid>");
            foreach (var row in t.rows) {
                o.raw("<w:tr>");
                if (row.header || row.cant_split || row.height > 0 || row.rev != null) {
                    o.raw("<w:trPr>");
                    if (row.cant_split) o.raw("<w:cantSplit/>");
                    if (row.height > 0) o.raw("<w:trHeight w:val=\"%d\" w:hRule=\"%s\"/>".printf(tw(row.height), row.height_exact ? "exact" : "atLeast"));
                    if (row.header) o.raw("<w:tblHeader/>");
                    if (row.rev != null) {
                        var tmp = new XmlOut(false);
                        write_rev_attr(tmp, row.rev.kind == RevKind.DELETE ? "w:del" : "w:ins", row.rev, true);
                        o.raw(tmp.str());
                    }
                    o.raw("</w:trPr>");
                }
                int col = 0;
                foreach (var cell in row.cells) {
                    o.raw("<w:tc><w:tcPr>");
                    double w = cell.width;
                    if (w <= 0) {
                        w = 0;
                        for (int k = col; k < col + cell.span && k < t.grid.length; k++) w += t.grid[k];
                    }
                    o.raw("<w:tcW w:w=\"%d\" w:type=\"dxa\"/>".printf(tw(w)));
                    if (cell.span > 1) o.raw("<w:gridSpan w:val=\"%d\"/>".printf(cell.span));
                    if (cell.vmerge == VMerge.RESTART) o.raw("<w:vMerge w:val=\"restart\"/>");
                    else if (cell.vmerge == VMerge.CONTINUE) o.raw("<w:vMerge/>");
                    if (cell.top != null || cell.bottom != null || cell.left != null || cell.right != null) {
                        var tmp = new XmlOut(false);
                        tmp.start("w:tcBorders");
                        write_border(tmp, "w:top", cell.top);
                        write_border(tmp, "w:left", cell.left);
                        write_border(tmp, "w:bottom", cell.bottom);
                        write_border(tmp, "w:right", cell.right);
                        tmp.end();
                        o.raw(tmp.str());
                    }
                    if (cell.shading != null) o.raw("<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"%s\"/>".printf(cell.shading.substring(1).up()));
                    if (cell.valign != CellVAlign.TOP) o.raw("<w:vAlign w:val=\"%s\"/>".printf(cell.valign == CellVAlign.CENTER ? "center" : "bottom"));
                    o.raw("</w:tcPr>");
                    write_blocks(o, cell.blocks);
                    if (cell.blocks.size == 0 || !(cell.blocks[cell.blocks.size - 1] is Paragraph)) o.raw("<w:p/>");
                    o.raw("</w:tc>");
                    col += cell.span;
                }
                o.raw("</w:tr>");
            }
            o.raw("</w:tbl>");
        }

        private string hf_part(HeaderFooter hf, bool header) {
            if (hf_rid.has_key(hf)) return hf_rid[hf];
            hf_n++;
            string name = "%s%d.xml".printf(header ? "header" : "footer", hf_n);
            string part = "word/" + name;
            var saved = rels;
            rels = new Rels(part);
            var o = new XmlOut();
            o.raw("<w:%s %s>".printf(header ? "hdr" : "ftr", NS));
            write_blocks(o, hf.blocks);
            if (hf.blocks.size == 0) o.raw("<w:p/>");
            o.raw("</w:%s>".printf(header ? "hdr" : "ftr"));
            try {
                zip.add_text(part, o.str());
                if (rels.ids.size > 0) zip.add_text("word/_rels/" + name + ".rels", rels.xml());
            } catch (Error e) {
            }
            rels = saved;
            overrides[part] = "application/vnd.openxmlformats-officedocument.wordprocessingml.%s+xml".printf(header ? "header" : "footer");
            string rid = doc_rels.add(REL + "/" + (header ? "header" : "footer"), name);
            hf_rid[hf] = rid;
            return rid;
        }

        private void write_sect(XmlOut o, Section s) {
            var tmp = new XmlOut(false);
            tmp.raw("<w:sectPr>");
            string[] kinds = { "default", "first", "even" };
            HeaderFooter?[] heads = { s.header_default, s.header_first, s.header_even };
            HeaderFooter?[] foots = { s.footer_default, s.footer_first, s.footer_even };
            for (int i = 0; i < 3; i++) if (heads[i] != null) tmp.raw("<w:headerReference w:type=\"%s\" r:id=\"%s\"/>".printf(kinds[i], hf_part(heads[i], true)));
            for (int i = 0; i < 3; i++) if (foots[i] != null) tmp.raw("<w:footerReference w:type=\"%s\" r:id=\"%s\"/>".printf(kinds[i], hf_part(foots[i], false)));
            string type = "nextPage";
            switch (s.start) {
                case SectionStart.CONTINUOUS: type = "continuous"; break;
                case SectionStart.EVEN_PAGE: type = "evenPage"; break;
                case SectionStart.ODD_PAGE: type = "oddPage"; break;
                case SectionStart.NEXT_COLUMN: type = "nextColumn"; break;
                default: break;
            }
            if (s.start != SectionStart.NEXT_PAGE) tmp.raw("<w:type w:val=\"%s\"/>".printf(type));
            tmp.raw("<w:pgSz w:w=\"%d\" w:h=\"%d\"%s/>".printf(tw(s.page_w), tw(s.page_h), s.landscape ? " w:orient=\"landscape\"" : ""));
            tmp.raw("<w:pgMar w:top=\"%d\" w:right=\"%d\" w:bottom=\"%d\" w:left=\"%d\" w:header=\"%d\" w:footer=\"%d\" w:gutter=\"%d\"/>".printf(
                tw(s.margin_top), tw(s.margin_right), tw(s.margin_bottom), tw(s.margin_left), tw(s.header_dist), tw(s.footer_dist), tw(s.gutter)));
            if (s.page_border_top != null || s.page_border_bottom != null || s.page_border_left != null || s.page_border_right != null) {
                var b = new XmlOut(false);
                b.start("w:pgBorders").a("w:offsetFrom", "text");
                write_border(b, "w:top", s.page_border_top);
                write_border(b, "w:left", s.page_border_left);
                write_border(b, "w:bottom", s.page_border_bottom);
                write_border(b, "w:right", s.page_border_right);
                b.end();
                tmp.raw(b.str());
            }
            if (s.line_numbers) tmp.raw("<w:lnNumType w:countBy=\"1\" w:restart=\"continuous\"/>");
            if (s.page_start >= 0 || s.page_format != NumFormat.DECIMAL) {
                tmp.raw("<w:pgNumType");
                if (s.page_format != NumFormat.DECIMAL) tmp.raw(" w:fmt=\"%s\"".printf(num_fmt_name(s.page_format)));
                if (s.page_start >= 0) tmp.raw(" w:start=\"%d\"".printf(s.page_start));
                tmp.raw("/>");
            }
            tmp.raw("<w:cols w:space=\"%d\"%s%s/>".printf(tw(s.column_space), s.columns > 1 ? " w:num=\"%d\"".printf(s.columns) : "", s.column_sep ? " w:sep=\"1\"" : ""));
            if (s.title_page) tmp.raw("<w:titlePg/>");
            tmp.raw("</w:sectPr>");
            o.raw(tmp.str());
        }

        public static string num_fmt_name(NumFormat f) {
            switch (f) {
                case NumFormat.LOWER_LETTER: return "lowerLetter";
                case NumFormat.UPPER_LETTER: return "upperLetter";
                case NumFormat.LOWER_ROMAN: return "lowerRoman";
                case NumFormat.UPPER_ROMAN: return "upperRoman";
                case NumFormat.BULLET: return "bullet";
                case NumFormat.NONE: return "none";
                case NumFormat.DECIMAL_ZERO: return "decimalZero";
                case NumFormat.ORDINAL: return "ordinal";
                case NumFormat.CARDINAL_TEXT: return "cardinalText";
                default: return "decimal";
            }
        }

        private static string word_style_name(Style s) {
            string n = s.name;
            if (n.has_prefix("Heading ") && s.kind == StyleType.PARAGRAPH) return "heading " + n.substring(8);
            if (n.has_prefix("TOC ") && n != "TOC Heading") return "toc " + n.substring(4);
            if (n.has_prefix("Index ") && n != "Index Heading") return "index " + n.substring(6);
            switch (n) {
                case "Caption": return "caption";
                case "Footnote Text": return "footnote text";
                case "Endnote Text": return "endnote text";
                case "Footnote Reference": return "footnote reference";
                case "Endnote Reference": return "endnote reference";
                case "Header": return "header";
                case "Footer": return "footer";
                case "Comment Text": return "annotation text";
                case "Table of Figures": return "table of figures";
                case "Index Heading": return "index heading";
                default: return n;
            }
        }

        private string styles_xml() {
            var o = new XmlOut();
            o.raw("<w:styles " + NS + ">");
            o.raw("<w:docDefaults><w:rPrDefault><w:rPr>");
            var dc = doc.styles.default_char;
            write_rpr_inner(o, dc);
            o.raw("</w:rPr></w:rPrDefault><w:pPrDefault>");
            write_ppr(o, doc.styles.default_para, null, null, null, null);
            if (doc.styles.default_para.is_empty()) o.raw("<w:pPr/>");
            o.raw("</w:pPrDefault></w:docDefaults>");
            o.raw("<w:style w:type=\"character\" w:default=\"1\" w:styleId=\"DefaultParagraphFont\"><w:name w:val=\"Default Paragraph Font\"/><w:uiPriority w:val=\"1\"/><w:semiHidden/><w:unhideWhenUsed/></w:style>");
            o.raw("<w:style w:type=\"table\" w:default=\"1\" w:styleId=\"TableNormal\"><w:name w:val=\"Normal Table\"/><w:uiPriority w:val=\"99\"/><w:semiHidden/><w:unhideWhenUsed/><w:tblPr><w:tblInd w:w=\"0\" w:type=\"dxa\"/><w:tblCellMar><w:top w:w=\"0\" w:type=\"dxa\"/><w:left w:w=\"108\" w:type=\"dxa\"/><w:bottom w:w=\"0\" w:type=\"dxa\"/><w:right w:w=\"108\" w:type=\"dxa\"/></w:tblCellMar></w:tblPr></w:style>");
            o.raw("<w:style w:type=\"character\" w:styleId=\"CommentReference\"><w:name w:val=\"annotation reference\"/><w:basedOn w:val=\"DefaultParagraphFont\"/><w:uiPriority w:val=\"99\"/><w:semiHidden/><w:unhideWhenUsed/><w:rPr><w:sz w:val=\"16\"/></w:rPr></w:style>");
            foreach (var s in doc.styles.list) {
                if (s.id == "DefaultParagraphFont" || s.id == "TableNormal" || s.id == "CommentReference") continue;
                string type = s.kind == StyleType.CHARACTER ? "character" : (s.kind == StyleType.TABLE ? "table" : (s.kind == StyleType.NUMBERING ? "numbering" : "paragraph"));
                o.raw("<w:style w:type=\"%s\"%s%s w:styleId=\"%s\">".printf(type, s.id == "Normal" ? " w:default=\"1\"" : "", s.custom ? " w:customStyle=\"1\"" : "", X.esc(s.id)));
                o.raw("<w:name w:val=\"%s\"/>".printf(X.esc(word_style_name(s))));
                if (s.based_on != null) o.raw("<w:basedOn w:val=\"%s\"/>".printf(X.esc(s.based_on)));
                if (s.next != null && s.kind == StyleType.PARAGRAPH) o.raw("<w:next w:val=\"%s\"/>".printf(X.esc(s.next)));
                if (s.link != null) o.raw("<w:link w:val=\"%s\"/>".printf(X.esc(s.link)));
                o.raw("<w:uiPriority w:val=\"%d\"/>".printf(s.priority));
                if (s.hidden) o.raw("<w:semiHidden/><w:unhideWhenUsed/>");
                if (s.quick) o.raw("<w:qFormat/>");
                if (s.kind == StyleType.PARAGRAPH) write_ppr(o, s.para, null, null, null, null);
                if (!s.chr.is_empty()) {
                    o.raw("<w:rPr>");
                    write_rpr_inner(o, s.chr);
                    o.raw("</w:rPr>");
                }
                if (s.kind == StyleType.TABLE && s.table_border != null) {
                    var tmp = new XmlOut(false);
                    tmp.raw("<w:tblPr><w:tblBorders>");
                    foreach (string side in new string[] { "w:top", "w:left", "w:bottom", "w:right", "w:insideH", "w:insideV" }) write_border(tmp, side, s.table_border);
                    tmp.raw("</w:tblBorders></w:tblPr>");
                    o.raw(tmp.str());
                }
                if (s.kind == StyleType.TABLE && (s.table_header_shading != null || s.table_header_chr != null)) {
                    o.raw("<w:tblStylePr w:type=\"firstRow\">");
                    if (s.table_header_chr != null) {
                        o.raw("<w:rPr>");
                        write_rpr_inner(o, s.table_header_chr);
                        o.raw("</w:rPr>");
                    }
                    if (s.table_header_shading != null) o.raw("<w:tcPr><w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"%s\"/></w:tcPr>".printf(s.table_header_shading.substring(1).up()));
                    o.raw("</w:tblStylePr>");
                }
                if (s.kind == StyleType.TABLE && s.table_band_shading != null) {
                    o.raw("<w:tblStylePr w:type=\"band1Horz\"><w:tcPr><w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"%s\"/></w:tcPr></w:tblStylePr>".printf(s.table_band_shading.substring(1).up()));
                }
                o.raw("</w:style>");
            }
            o.raw("</w:styles>");
            return o.str();
        }

        private string numbering_xml() {
            var o = new XmlOut();
            o.raw("<w:numbering " + NS + ">");
            foreach (var d in doc.numbering.defs) {
                o.raw("<w:abstractNum w:abstractNumId=\"%d\"><w:multiLevelType w:val=\"hybridMultilevel\"/>".printf(d.id));
                for (int i = 0; i < 9; i++) {
                    var l = d.levels[i];
                    o.raw("<w:lvl w:ilvl=\"%d\"><w:start w:val=\"%d\"/><w:numFmt w:val=\"%s\"/>".printf(i, l.start, num_fmt_name(l.format)));
                    if (l.suffix != "tab") o.raw("<w:suff w:val=\"%s\"/>".printf(l.suffix));
                    o.raw("<w:lvlText w:val=\"%s\"/>".printf(X.esc(l.text)));
                    o.raw("<w:lvlJc w:val=\"%s\"/>".printf(l.align == Align.CENTER ? "center" : (l.align == Align.RIGHT ? "right" : "left")));
                    o.raw("<w:pPr><w:ind w:left=\"%d\" w:hanging=\"%d\"/></w:pPr>".printf(tw(l.ind_left), tw(l.hanging)));
                    if (l.label_props != null && !l.label_props.is_empty()) {
                        var lp = l.label_props.copy();
                        if (l.format == NumFormat.BULLET && (lp.font == "Symbol" || lp.font == "Wingdings")) lp.font = null;
                        o.raw("<w:rPr>");
                        write_rpr_inner(o, lp);
                        o.raw("</w:rPr>");
                    }
                    o.raw("</w:lvl>");
                }
                o.raw("</w:abstractNum>");
            }
            foreach (var n in doc.numbering.instances) {
                o.raw("<w:num w:numId=\"%d\"><w:abstractNumId w:val=\"%d\"/>".printf(n.id, n.def_id));
                foreach (var e in n.start_override.entries) o.raw("<w:lvlOverride w:ilvl=\"%d\"><w:startOverride w:val=\"%d\"/></w:lvlOverride>".printf(e.key, e.value));
                o.raw("</w:num>");
            }
            o.raw("</w:numbering>");
            return o.str();
        }

        private string settings_xml() {
            var o = new XmlOut();
            o.raw("<w:settings " + NS + ">");
            o.raw("<w:zoom w:percent=\"100\"/>");
            if (doc.page_color != null) o.raw("<w:displayBackgroundShape/>");
            if (doc.track_changes) o.raw("<w:trackRevisions/>");
            if (doc.protection.kind != ProtectKind.NONE) {
                string edit = "readOnly";
                switch (doc.protection.kind) {
                    case ProtectKind.COMMENTS: edit = "comments"; break;
                    case ProtectKind.TRACKED: edit = "trackedChanges"; break;
                    case ProtectKind.FORMS: edit = "forms"; break;
                    default: break;
                }
                o.raw("<w:documentProtection w:edit=\"%s\" w:enforcement=\"%s\"".printf(edit, doc.protection.enforced ? "1" : "0"));
                if (doc.protection.hash != "") {
                    o.raw(" w:algorithmName=\"%s\" w:hashValue=\"%s\" w:saltValue=\"%s\" w:spinCount=\"%d\"".printf(X.esc(doc.protection.algorithm), X.esc(doc.protection.hash), X.esc(doc.protection.salt), doc.protection.spin));
                }
                o.raw("/>");
            }
            o.raw("<w:defaultTabStop w:val=\"%d\"/>".printf(tw(doc.default_tab)));
            if (doc.hyphenate) o.raw("<w:autoHyphenation/>");
            if (doc.even_odd_headers) o.raw("<w:evenAndOddHeaders/>");
            o.raw("<w:characterSpacingControl w:val=\"doNotCompress\"/>");
            o.raw("<w:footnotePr>");
            if (doc.footnote_format != NumFormat.DECIMAL) o.raw("<w:numFmt w:val=\"%s\"/>".printf(num_fmt_name(doc.footnote_format)));
            o.raw("<w:footnote w:id=\"-1\"/><w:footnote w:id=\"0\"/></w:footnotePr>");
            o.raw("<w:endnotePr><w:numFmt w:val=\"%s\"/><w:endnote w:id=\"-1\"/><w:endnote w:id=\"0\"/></w:endnotePr>".printf(num_fmt_name(doc.endnote_format)));
            o.raw("<w:compat><w:compatSetting w:name=\"compatibilityMode\" w:uri=\"http://schemas.microsoft.com/office/word\" w:val=\"15\"/></w:compat>");
            var vars = new Gee.TreeMap<string, string>();
            foreach (var e in doc.variables.entries) vars[e.key] = e.value;
            if (doc.merge_source != null) vars["SingularityMergeSource"] = doc.merge_source;
            if (doc.bib_style != "APA") vars["SingularityBibStyle"] = doc.bib_style;
            for (int i = 0; i < doc.macros.size; i++) vars["SingularityMacro%02d".printf(i)] = doc.macros[i];
            if (vars.size > 0) {
                o.raw("<w:docVars>");
                foreach (var e in vars.entries) o.raw("<w:docVar w:name=\"%s\" w:val=\"%s\"/>".printf(X.esc(e.key), X.esc(e.value).replace("\r", "&#13;").replace("\n", "&#10;").replace("\t", "&#9;")));
                o.raw("</w:docVars>");
            }
            if (doc.lang != "") o.raw("<w:themeFontLang w:val=\"%s\"/>".printf(X.esc(doc.lang)));
            o.raw("</w:settings>");
            return o.str();
        }

        private void write_notes() throws Error {
            if (foot_list.size > 0) {
                write_note_part("footnotes", "footnote", foot_list, NoteKind.FOOTNOTE);
            }
            if (end_list.size > 0) {
                write_note_part("endnotes", "endnote", end_list, NoteKind.ENDNOTE);
            }
        }

        private void write_note_part(string part_name, string tag, Gee.ArrayList<Note> list, NoteKind kind) throws Error {
            string part = "word/" + part_name + ".xml";
            var saved = rels;
            rels = new Rels(part);
            var o = new XmlOut();
            o.raw("<w:%s %s>".printf(part_name, NS));
            o.raw("<w:%s w:type=\"separator\" w:id=\"-1\"><w:p><w:pPr><w:spacing w:after=\"0\" w:line=\"240\" w:lineRule=\"auto\"/></w:pPr><w:r><w:separator/></w:r></w:p></w:%s>".printf(tag, tag));
            o.raw("<w:%s w:type=\"continuationSeparator\" w:id=\"0\"><w:p><w:pPr><w:spacing w:after=\"0\" w:line=\"240\" w:lineRule=\"auto\"/></w:pPr><w:r><w:continuationSeparator/></w:r></w:p></w:%s>".printf(tag, tag));
            string ref_style = kind == NoteKind.FOOTNOTE ? "FootnoteReference" : "EndnoteReference";
            string text_style = kind == NoteKind.FOOTNOTE ? "FootnoteText" : "EndnoteText";
            int idx = 0;
            while (idx < list.size) {
                var n = list[idx];
                idx++;
                o.raw("<w:%s w:id=\"%d\">".printf(tag, idx));
                var blocks = n.blocks.copy();
                if (blocks.size == 0) blocks.add(new Paragraph(text_style));
                var first = blocks[0] as Paragraph;
                if (first != null && first.style == "Normal") first.style = text_style;
                for (int b = 0; b < blocks.size; b++) {
                    var p = blocks[b] as Paragraph;
                    if (p != null && p == first) {
                        o.raw("<w:p>");
                        write_ppr(o, p.props, p.style, p.mark_props, p.mark_rev, null);
                        o.raw("<w:r><w:rPr><w:rStyle w:val=\"%s\"/></w:rPr><w:%sRef/></w:r>".printf(ref_style, tag));
                        o.raw("<w:r><w:t xml:space=\"preserve\"> </w:t></w:r>");
                        write_inlines(o, p.inlines);
                        o.raw("</w:p>");
                    } else if (p != null) {
                        write_paragraph(o, p, null, false);
                    } else if (blocks[b] is Table) {
                        write_table(o, (Table) blocks[b]);
                    }
                }
                o.raw("</w:%s>".printf(tag));
            }
            o.raw("</w:%s>".printf(part_name));
            zip.add_text(part, o.str());
            if (rels.ids.size > 0) zip.add_text("word/_rels/" + part_name + ".xml.rels", rels.xml());
            rels = saved;
            overrides[part] = "application/vnd.openxmlformats-officedocument.wordprocessingml.%s+xml".printf(part_name);
            doc_rels.add(REL + "/" + part_name, part_name + ".xml");
        }

        private void write_comments() throws Error {
            if (doc.comments.size == 0) return;
            var saved = rels;
            rels = new Rels("word/comments.xml");
            var o = new XmlOut();
            o.raw("<w:comments " + NS + ">");
            int n = 0;
            foreach (var c in doc.comments) {
                n++;
                string pid = "%08X".printf(0x10000000 + n);
                comment_para[c.id] = pid;
                o.raw("<w:comment w:id=\"%s\" w:author=\"%s\" w:date=\"%s\" w:initials=\"%s\">".printf(X.esc(c.id), X.esc(c.author), X.esc(c.date), X.esc(c.initials)));
                var blocks = c.blocks;
                if (blocks.size == 0) {
                    blocks = new BlockList();
                    blocks.add(new Paragraph("CommentText"));
                }
                for (int i = 0; i < blocks.size; i++) {
                    var p = blocks[i] as Paragraph;
                    if (p == null) continue;
                    bool last = i == blocks.size - 1;
                    current_comment_para = last ? pid : null;
                    if (i == 0) {
                        o.raw("<w:p");
                        if (current_comment_para != null) o.raw(" w14:paraId=\"" + pid + "\" w14:textId=\"77777777\"");
                        o.raw(">");
                        write_ppr(o, p.props, p.style == "Normal" ? "CommentText" : p.style, p.mark_props, null, null);
                        o.raw("<w:r><w:rPr><w:rStyle w:val=\"CommentReference\"/></w:rPr><w:annotationRef/></w:r>");
                        write_inlines(o, p.inlines);
                        o.raw("</w:p>");
                    } else {
                        write_paragraph(o, p, null, false);
                    }
                    current_comment_para = null;
                }
                o.raw("</w:comment>");
            }
            o.raw("</w:comments>");
            zip.add_text("word/comments.xml", o.str());
            if (rels.ids.size > 0) zip.add_text("word/_rels/comments.xml.rels", rels.xml());
            rels = saved;
            overrides["word/comments.xml"] = "application/vnd.openxmlformats-officedocument.wordprocessingml.comments+xml";
            doc_rels.add(REL + "/comments", "comments.xml");
            var ex = new XmlOut();
            ex.raw("<w15:commentsEx " + NS + ">");
            foreach (var c in doc.comments) {
                ex.raw("<w15:commentEx w15:paraId=\"%s\"".printf(comment_para[c.id]));
                if (c.parent_id != null && comment_para.has_key(c.parent_id)) ex.raw(" w15:paraIdParent=\"%s\"".printf(comment_para[c.parent_id]));
                ex.raw(" w15:done=\"%s\"/>".printf(c.done ? "1" : "0"));
            }
            ex.raw("</w15:commentsEx>");
            zip.add_text("word/commentsExtended.xml", ex.str());
            overrides["word/commentsExtended.xml"] = "application/vnd.openxmlformats-officedocument.wordprocessingml.commentsExtended+xml";
            doc_rels.add("http://schemas.microsoft.com/office/2011/relationships/commentsExtended", "commentsExtended.xml");
        }

        private void write_sources() throws Error {
            if (doc.sources.size == 0) return;
            int n = 1;
            while (doc.passthrough.has_key("customXml/item%d.xml".printf(n))) n++;
            string part = "customXml/item%d.xml".printf(n);
            var o = new XmlOut();
            string style = doc.bib_style == "APA" ? "\\APASixthEditionOfficeOnline.xsl" : (doc.bib_style == "MLA" ? "\\MLASeventhEditionOfficeOnline.xsl" : (doc.bib_style == "Chicago" ? "\\ChicagoFifteenthEditionOfficeOnline.xsl" : (doc.bib_style == "IEEE" ? "\\IEEE2006OfficeOnline.xsl" : "\\HarvardAnglia2008OfficeOnline.xsl")));
            o.raw("<b:Sources SelectedStyle=\"%s\" StyleName=\"%s\" xmlns:b=\"http://schemas.openxmlformats.org/officeDocument/2006/bibliography\" xmlns=\"http://schemas.openxmlformats.org/officeDocument/2006/bibliography\">".printf(X.esc(style), doc.bib_style));
            foreach (var s in doc.sources) {
                o.raw("<b:Source>");
                o.raw("<b:Tag>%s</b:Tag><b:SourceType>%s</b:SourceType>".printf(X.esc(s.tag), X.esc(s.kind)));
                if (s.authors.length > 0) {
                    o.raw("<b:Author><b:Author><b:NameList>");
                    foreach (string a in s.authors) {
                        o.raw("<b:Person><b:Last>%s</b:Last>".printf(X.esc(Citations.last_name(a))));
                        string first = Citations.first_names(a);
                        if (first != "") o.raw("<b:First>%s</b:First>".printf(X.esc(first)));
                        o.raw("</b:Person>");
                    }
                    o.raw("</b:NameList></b:Author></b:Author>");
                }
                string[,] fields = {
                    { "Title", s.title }, { "Year", s.year }, { "Publisher", s.publisher }, { "City", s.city },
                    { "JournalName", s.journal }, { "Volume", s.volume }, { "Issue", s.issue }, { "Pages", s.pages },
                    { "URL", s.url }, { "Edition", s.edition }, { "DOI", s.doi }
                };
                for (int i = 0; i < fields.length[0]; i++) {
                    if (fields[i, 1] != "") o.raw("<b:%s>%s</b:%s>".printf(fields[i, 0], X.esc(fields[i, 1]), fields[i, 0]));
                }
                o.raw("</b:Source>");
            }
            o.raw("</b:Sources>");
            zip.add_text(part, o.str());
            string props = "customXml/itemProps%d.xml".printf(n);
            zip.add_text(props, "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"no\"?>\n<ds:datastoreItem ds:itemID=\"{%s}\" xmlns:ds=\"http://schemas.openxmlformats.org/officeDocument/2006/customXml\"><ds:schemaRefs><ds:schemaRef ds:uri=\"http://schemas.openxmlformats.org/officeDocument/2006/bibliography\"/></ds:schemaRefs></ds:datastoreItem>".printf(Uuid.string_random().up()));
            var r = new Rels(part);
            r.add("http://schemas.openxmlformats.org/officeDocument/2006/relationships/customXmlProps", "itemProps%d.xml".printf(n));
            zip.add_text("customXml/_rels/item%d.xml.rels".printf(n), r.xml());
            overrides[props] = "application/vnd.openxmlformats-officedocument.customXmlProperties+xml";
            doc_rels.add(REL + "/customXml", "../" + part);
        }

        private void write_props() throws Error {
            var now = new DateTime.now_utc().format("%Y-%m-%dT%H:%M:%SZ");
            var m = doc.meta;
            var o = new XmlOut();
            o.raw("<cp:coreProperties xmlns:cp=\"http://schemas.openxmlformats.org/package/2006/metadata/core-properties\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:dcterms=\"http://purl.org/dc/terms/\" xmlns:dcmitype=\"http://purl.org/dc/dcmitype/\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\">");
            if (m.title != "") o.raw("<dc:title>%s</dc:title>".printf(X.esc(m.title)));
            if (m.subject != "") o.raw("<dc:subject>%s</dc:subject>".printf(X.esc(m.subject)));
            if (m.author != "") o.raw("<dc:creator>%s</dc:creator>".printf(X.esc(m.author)));
            if (m.keywords != "") o.raw("<cp:keywords>%s</cp:keywords>".printf(X.esc(m.keywords)));
            if (m.description != "") o.raw("<dc:description>%s</dc:description>".printf(X.esc(m.description)));
            if (m.last_modified_by != "") o.raw("<cp:lastModifiedBy>%s</cp:lastModifiedBy>".printf(X.esc(m.last_modified_by)));
            o.raw("<cp:revision>%d</cp:revision>".printf(int.max(1, m.revision)));
            if (m.category != "") o.raw("<cp:category>%s</cp:category>".printf(X.esc(m.category)));
            o.raw("<dcterms:created xsi:type=\"dcterms:W3CDTF\">%s</dcterms:created>".printf(X.esc(m.created != "" ? m.created : now)));
            o.raw("<dcterms:modified xsi:type=\"dcterms:W3CDTF\">%s</dcterms:modified>".printf(X.esc(m.modified != "" ? m.modified : now)));
            o.raw("</cp:coreProperties>");
            zip.add_text("docProps/core.xml", o.str());
            overrides["docProps/core.xml"] = "application/vnd.openxmlformats-package.core-properties+xml";
            var stats = Stats.compute(doc, false);
            var app = new XmlOut();
            app.raw("<Properties xmlns=\"http://schemas.openxmlformats.org/officeDocument/2006/extended-properties\" xmlns:vt=\"http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes\">");
            app.raw("<Application>Singularity Write</Application><Words>%d</Words><Characters>%d</Characters><Paragraphs>%d</Paragraphs>".printf(stats.words, stats.chars_no_spaces, stats.paragraphs));
            if (m.company != "") app.raw("<Company>%s</Company>".printf(X.esc(m.company)));
            if (m.manager != "") app.raw("<Manager>%s</Manager>".printf(X.esc(m.manager)));
            app.raw("</Properties>");
            zip.add_text("docProps/app.xml", app.str());
            overrides["docProps/app.xml"] = "application/vnd.openxmlformats-officedocument.extended-properties+xml";
            if (m.custom.size > 0) {
                var c = new XmlOut();
                c.raw("<Properties xmlns=\"http://schemas.openxmlformats.org/officeDocument/2006/custom-properties\" xmlns:vt=\"http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes\">");
                int pid = 2;
                foreach (var e in m.custom.entries) {
                    c.raw("<property fmtid=\"{D5CDD505-2E9C-101B-9397-08002B2CF9AE}\" pid=\"%d\" name=\"%s\"><vt:lpwstr>%s</vt:lpwstr></property>".printf(pid++, X.esc(e.key), X.esc(e.value)));
                }
                c.raw("</Properties>");
                zip.add_text("docProps/custom.xml", c.str());
                overrides["docProps/custom.xml"] = "application/vnd.openxmlformats-officedocument.custom-properties+xml";
            }
        }
    }
}
