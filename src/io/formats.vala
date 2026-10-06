namespace Write {

    public enum FileFormat {
        DOCX,
        DOTX,
        DOCM,
        ODT,
        OTT,
        RTF,
        HTML,
        MARKDOWN,
        TEXT,
        DOC,
        PDF,
        EPUB,
        OTHER_OFFICE,
        UNKNOWN;

        public bool rich() {
            return this == DOCX || this == DOTX || this == DOCM || this == ODT || this == OTT || this == RTF || this == DOC || this == HTML || this == EPUB;
        }

        public bool writable() {
            return this == DOCX || this == DOTX || this == ODT || this == OTT || this == RTF || this == HTML || this == MARKDOWN || this == TEXT || this == EPUB;
        }

        public string extension() {
            switch (this) {
                case DOCX: return "docx";
                case DOTX: return "dotx";
                case DOCM: return "docm";
                case ODT: return "odt";
                case OTT: return "ott";
                case RTF: return "rtf";
                case HTML: return "html";
                case MARKDOWN: return "md";
                case TEXT: return "txt";
                case DOC: return "doc";
                case PDF: return "pdf";
                case EPUB: return "epub";
                default: return "";
            }
        }

        public string label() {
            switch (this) {
                case DOCX: return _("Word Document");
                case DOTX: return _("Word Template");
                case DOCM: return _("Word Macro-Enabled Document");
                case ODT: return _("OpenDocument Text");
                case OTT: return _("OpenDocument Text Template");
                case RTF: return _("Rich Text Format");
                case HTML: return _("Web Page");
                case MARKDOWN: return _("Markdown");
                case TEXT: return _("Plain Text");
                case DOC: return _("Word 97-2003 Document");
                case PDF: return _("PDF");
                case EPUB: return _("EPUB Book");
                default: return _("Unknown");
            }
        }

        public static FileFormat from_extension(string name) {
            string n = name.down();
            if (n.has_suffix(".docx")) return DOCX;
            if (n.has_suffix(".dotx")) return DOTX;
            if (n.has_suffix(".docm") || n.has_suffix(".dotm")) return DOCM;
            if (n.has_suffix(".odt")) return ODT;
            if (n.has_suffix(".ott")) return OTT;
            if (n.has_suffix(".rtf")) return RTF;
            if (n.has_suffix(".html") || n.has_suffix(".htm") || n.has_suffix(".xhtml")) return HTML;
            if (n.has_suffix(".md") || n.has_suffix(".markdown")) return MARKDOWN;
            if (n.has_suffix(".txt") || n.has_suffix(".text")) return TEXT;
            if (n.has_suffix(".doc") || n.has_suffix(".dot")) return DOC;
            if (n.has_suffix(".pdf")) return PDF;
            if (n.has_suffix(".epub")) return EPUB;
            return UNKNOWN;
        }
    }

    public class Formats : Object {

        public static FileFormat sniff(uint8[] data, string name) {
            var by_ext = FileFormat.from_extension(name);
            if (ZipReader.is_zip(data)) {
                try {
                    var z = new ZipReader(data);
                    if (z.has("word/document.xml")) {
                        if (by_ext == FileFormat.DOTX || by_ext == FileFormat.DOCM) return by_ext;
                        return FileFormat.DOCX;
                    }
                    string? mt = z.read_text("mimetype");
                    if (mt != null) {
                        if (mt.strip() == "application/vnd.oasis.opendocument.text") return FileFormat.ODT;
                        if (mt.strip() == "application/vnd.oasis.opendocument.text-template") return FileFormat.OTT;
                        if (mt.strip() == "application/epub+zip") return FileFormat.EPUB;
                        return FileFormat.OTHER_OFFICE;
                    }
                    if (z.has("[Content_Types].xml")) {
                        string? ct = z.read_text("[Content_Types].xml");
                        if (ct != null && ct.contains("wordprocessingml")) return FileFormat.DOCX;
                        return FileFormat.OTHER_OFFICE;
                    }
                } catch (Error e) {
                }
                return FileFormat.UNKNOWN;
            }
            if (data.length >= 8 && data[0] == 0xD0 && data[1] == 0xCF && data[2] == 0x11 && data[3] == 0xE0) {
                if (by_ext == FileFormat.DOC) return FileFormat.DOC;
                return FileFormat.DOC;
            }
            if (data.length >= 5 && data[0] == '{' && data[1] == '\\' && data[2] == 'r' && data[3] == 't' && data[4] == 'f') return FileFormat.RTF;
            if (data.length >= 5 && data[0] == '%' && data[1] == 'P' && data[2] == 'D' && data[3] == 'F') return FileFormat.PDF;
            for (int i = 0; i < data.length && i < 8192; i++) if (data[i] == 0) return FileFormat.UNKNOWN;
            var sb = new StringBuilder();
            sb.append_len((string) data, int.min(data.length, 8192));
            string head = sb.str;
            if (!head.validate()) {
                string lh = head.down();
                if (lh.contains("<html") || lh.contains("<!doctype html")) return FileFormat.HTML;
                return by_ext == FileFormat.MARKDOWN ? FileFormat.MARKDOWN : FileFormat.TEXT;
            }
            string lh = head.strip().down();
            if (lh.has_prefix("<!doctype html") || lh.has_prefix("<html") || (by_ext == FileFormat.HTML && lh.has_prefix("<"))) return FileFormat.HTML;
            if (by_ext == FileFormat.MARKDOWN) return FileFormat.MARKDOWN;
            if (by_ext == FileFormat.TEXT) return FileFormat.TEXT;
            if (by_ext == FileFormat.UNKNOWN) return FileFormat.TEXT;
            return by_ext;
        }

        public static Document load(uint8[] data, FileFormat fmt) throws Error {
            switch (fmt) {
                case FileFormat.DOCX:
                case FileFormat.DOTX:
                case FileFormat.DOCM:
                    return DocxReader.load(data);
                case FileFormat.ODT:
                case FileFormat.OTT:
                    return OdtReader.load(data);
                case FileFormat.RTF:
                    return RtfReader.load(data);
                case FileFormat.HTML:
                    return HtmlReader.load(decode_text(data), null);
                case FileFormat.TEXT:
                    return from_text(decode_text(data));
                case FileFormat.DOC:
                    return DocReader.load(data);
                case FileFormat.EPUB:
                    return EpubReader.load(data);
                case FileFormat.MARKDOWN:
                    var md = new Markdown.Parser();
                    return HtmlReader.load_fragment(md.to_html(decode_text(data)));
                default:
                    throw new FormatError.UNSUPPORTED(_("Write cannot open this kind of file."));
            }
        }

        public static Document charts_as_pictures(Document doc) {
            bool any = false;
            foreach (var p in Story.all(doc)) foreach (var i in p.inlines) if (i is ChartRun) any = true;
            if (!any) return doc;
            var d = doc.copy();
            foreach (var p in Story.all(d)) {
                for (int k = 0; k < p.inlines.size; k++) {
                    var ch = p.inlines[k] as ChartRun;
                    if (ch == null) continue;
                    if (ch.preview == null) {
                        p.inlines.remove_at(k--);
                        continue;
                    }
                    var img = new ImageRun(ch.preview, "image/png");
                    img.width = ch.width;
                    img.height = ch.height;
                    img.wrap = ch.wrap;
                    img.halign = ch.halign;
                    img.alt = ch.alt != "" ? ch.alt : _("Chart");
                    img.title = ch.title;
                    img.props = ch.props;
                    p.inlines[k] = img;
                }
                p.touch();
            }
            return d;
        }

        public static uint8[] save(Document src, FileFormat fmt) throws Error {
            var doc = fmt == FileFormat.DOCX || fmt == FileFormat.DOCM || fmt == FileFormat.DOTX || fmt == FileFormat.ODT || fmt == FileFormat.OTT ? src : charts_as_pictures(src);
            switch (fmt) {
                case FileFormat.DOCX:
                case FileFormat.DOCM:
                    return DocxWriter.save(doc, false);
                case FileFormat.DOTX:
                    return DocxWriter.save(doc, true);
                case FileFormat.ODT:
                    return OdtWriter.save(doc, false);
                case FileFormat.OTT:
                    return OdtWriter.save(doc, true);
                case FileFormat.RTF:
                    return RtfWriter.save(doc);
                case FileFormat.HTML:
                    return HtmlWriter.save(doc).data;
                case FileFormat.MARKDOWN:
                    return MarkdownWriter.save(doc).data;
                case FileFormat.TEXT:
                    return to_text(doc).data;
                case FileFormat.EPUB:
                    return EpubWriter.save(doc);
                default:
                    throw new FormatError.UNSUPPORTED(_("Write cannot save in this format."));
            }
        }

        public static string decode_text(uint8[] data) {
            var sb = new StringBuilder();
            sb.append_len((string) data, data.length);
            string s = sb.str;
            if (s.has_prefix("\xef\xbb\xbf")) s = s.substring(3);
            if (data.length >= 2 && ((data[0] == 0xFF && data[1] == 0xFE) || (data[0] == 0xFE && data[1] == 0xFF))) {
                try {
                    return convert((string) data, data.length, "UTF-8", data[0] == 0xFF ? "UTF-16LE" : "UTF-16BE").substring(3);
                } catch (Error e) {
                }
            }
            if (s.validate()) return s;
            try {
                return convert(s, s.length, "UTF-8", "CP1252");
            } catch (Error e) {
                return s.make_valid();
            }
        }

        public static Document from_text(string text) {
            var d = Document.create_blank();
            d.body.clear();
            foreach (string line in text.replace("\r\n", "\n").replace("\r", "\n").split("\n")) {
                var p = new Paragraph();
                if (line.contains("\t")) {
                    string[] parts = line.split("\t");
                    for (int i = 0; i < parts.length; i++) {
                        if (i > 0) p.inlines.add(new Tab());
                        if (parts[i] != "") p.inlines.add(new TextRun(parts[i]));
                    }
                } else if (line != "") {
                    p.inlines.add(new TextRun(line));
                }
                p.props.space_after = 0;
                d.body.add(p);
            }
            if (d.body.size > 1 && ((Paragraph) d.body[d.body.size - 1]).is_empty()) d.body.remove_at(d.body.size - 1);
            if (d.body.size == 0) d.body.add(new Paragraph());
            return d;
        }

        public static string to_text(Document doc) {
            var sb = new StringBuilder();
            text_blocks(doc, doc.body, sb);
            return sb.str;
        }

        private static void text_blocks(Document doc, BlockList list, StringBuilder sb) {
            var counter = new ListCounter(doc.numbering);
            foreach (var b in list.items) {
                var p = b as Paragraph;
                if (p != null) {
                    if (p.props.num_id > 0) {
                        string? lab = counter.label(p.props.num_id, int.max(0, p.props.num_level));
                        if (lab != null) {
                            sb.append(string.nfill(int.max(0, p.props.num_level) * 2, ' '));
                            sb.append(lab + " ");
                        }
                    }
                    sb.append(p.plain_text());
                    sb.append_c('\n');
                    continue;
                }
                var t = b as Table;
                if (t != null) {
                    foreach (var r in t.rows) {
                        string[] cells = {};
                        foreach (var c in r.cells) cells += c.plain_text().replace("\n", " ");
                        sb.append(string.joinv("\t", cells));
                        sb.append_c('\n');
                    }
                    continue;
                }
                var fb = b as FieldBlock;
                if (fb != null) text_blocks(doc, fb.result, sb);
            }
        }
    }

    public class HtmlReader : Object {
        public unowned BytesResolver? resolver = null;
        private Document doc;
        private string? base_dir;
        private Paragraph? para = null;
        private BlockList target;
        private Gee.ArrayList<CharProps> stack = new Gee.ArrayList<CharProps>();
        private Gee.ArrayList<int> lists = new Gee.ArrayList<int>();
        private bool pre = false;
        private Gee.HashMap<string, Note> notes = new Gee.HashMap<string, Note>();
        private Gee.HashMap<string, NoteRef> note_refs = new Gee.HashMap<string, NoteRef>();

        public static Document load(string html, string? base_dir) {
            var r = new HtmlReader();
            return r.read(html, base_dir);
        }

        public static Document load_fragment(string html) {
            return load("<html><body>" + html + "</body></html>", null);
        }

        public Document read(string html, string? base_dir) {
            this.base_dir = base_dir;
            doc = Document.create_blank();
            doc.body.clear();
            return read_into(html, doc);
        }

        public Document read_into(string html, Document target_doc) {
            doc = target_doc;
            target = doc.body;
            stack.add(new CharProps());
            char[] buf = (char[]) html.data;
            Html.Doc* h = Html.Doc.read_memory(buf, html.length, "", "UTF-8", Html.ParserOption.RECOVER | Html.ParserOption.NOERROR | Html.ParserOption.NOWARNING | Html.ParserOption.NONET);
            if (h != null) {
                Xml.Node* root = h->get_root_element();
                if (root != null) {
                    Xml.Node* head = X.child(root, "head");
                    if (head != null) {
                        Xml.Node* title = X.child(head, "title");
                        if (title != null) doc.meta.title = X.text(title).strip();
                        foreach (var m in X.kids(head, "meta")) {
                            string name = (X.attr(m, "name") ?? "").down();
                            string content = X.attr(m, "content") ?? "";
                            if (name == "author") doc.meta.author = content;
                            else if (name == "description") doc.meta.description = content;
                            else if (name == "keywords") doc.meta.keywords = content;
                        }
                    }
                    Xml.Node* body = X.child(root, "body");
                    walk(body != null ? body : root);
                }
                delete h;
            }
            end_para();
            attach_notes();
            if (doc.body.size == 0) doc.body.add(new Paragraph());
            return doc;
        }

        private void attach_notes() {
            foreach (var e in note_refs.entries) {
                var n = notes[e.key];
                if (n != null) e.value.note = n;
            }
        }

        private CharProps top() {
            return stack[stack.size - 1];
        }

        private Paragraph ensure_para() {
            if (para == null) {
                para = new Paragraph();
                target.add(para);
            }
            return para;
        }

        private void end_para() {
            if (para != null) {
                para.normalize();
                para = null;
            }
        }

        private void block(string style) {
            end_para();
            para = new Paragraph(style);
            target.add(para);
        }

        private void text(string raw) {
            string t = raw;
            if (!pre) {
                var sb = new StringBuilder();
                bool sp = false;
                unichar c;
                int i = 0;
                while (t.get_next_char(ref i, out c)) {
                    if (c == ' ' || c == '\n' || c == '\r' || c == '\t') {
                        if (!sp) sb.append_c(' ');
                        sp = true;
                    } else {
                        sb.append_unichar(c);
                        sp = false;
                    }
                }
                t = sb.str;
                if (para == null && t.strip() == "") return;
                if (para != null && para.is_empty() && t.has_prefix(" ")) t = t.chug();
                if (para != null && para.inlines.size > 0 && para.inlines[para.inlines.size - 1] is FormField) {
                    string ct = t.chug();
                    if (ct.has_prefix("\u2610") || ct.has_prefix("\u2611") || ct.has_prefix("\u2612")) t = ct.substring(ct.index_of_nth_char(1)).chug();
                }
            }
            if (t == "") return;
            var p = ensure_para();
            if (pre && t.contains("\n")) {
                string[] lines = t.split("\n");
                for (int i = 0; i < lines.length; i++) {
                    if (i > 0) p.inlines.add(new Break(BreakKind.LINE));
                    if (lines[i] != "") p.inlines.add(new TextRun(lines[i], top()));
                }
                return;
            }
            p.inlines.add(new TextRun(t, top()));
        }

        private void push(CharProps c) {
            var n = top().copy();
            n.overlay(c);
            stack.add(n);
        }

        private void pop() {
            if (stack.size > 1) stack.remove_at(stack.size - 1);
        }

        private CharProps css(string? style) {
            var c = new CharProps();
            if (style == null) return c;
            foreach (string decl in style.split(";")) {
                int colon = decl.index_of_char(':');
                if (colon < 0) continue;
                string k = decl.substring(0, colon).strip().down();
                string v = decl.substring(colon + 1).strip();
                string vl = v.down();
                switch (k) {
                    case "font-weight": c.bold = Tri.of(vl == "bold" || vl == "bolder" || int.parse(vl) >= 600); break;
                    case "font-style": c.italic = Tri.of(vl == "italic" || vl == "oblique"); break;
                    case "text-decoration":
                    case "text-decoration-line":
                        if (vl.contains("underline")) c.underline = Underline.SINGLE;
                        if (vl.contains("line-through")) c.strike = Tri.ON;
                        break;
                    case "color": c.color = css_color(v); break;
                    case "background-color":
                    case "background": c.highlight = css_color(v); break;
                    case "font-size":
                        if (vl.has_suffix("pt") || vl.has_suffix("px") || vl.has_suffix("em")) {
                            double sz = vl.has_suffix("em") ? double.parse(vl.substring(0, vl.length - 2)) * 11 : X.length_pt(vl, 0);
                            if (sz > 0) c.size = sz;
                        }
                        break;
                    case "font-family":
                        string f = v.split(",")[0].replace("\"", "").replace("'", "").strip();
                        if (f != "" && f != "inherit" && f != "serif" && f != "sans-serif") c.font = f;
                        break;
                    case "vertical-align":
                        if (vl == "super") c.valign = VAlign.SUPER;
                        else if (vl == "sub") c.valign = VAlign.SUB;
                        break;
                    case "font-variant": if (vl == "small-caps") c.caps = Caps.SMALL; break;
                    case "text-transform": if (vl == "uppercase") c.caps = Caps.ALL; break;
                    default: break;
                }
            }
            return c;
        }

        private static string? css_color(string v) {
            string s = v.strip().down();
            if (s.has_prefix("#") && s.length == 7) return s;
            if (s.has_prefix("#") && s.length == 4) return "#%c%c%c%c%c%c".printf(s[1], s[1], s[2], s[2], s[3], s[3]);
            if (s.has_prefix("rgb")) {
                int a = s.index_of_char('('), b = s.index_of_char(')');
                if (a > 0 && b > a) {
                    string[] p = s.substring(a + 1, b - a - 1).split(",");
                    if (p.length >= 3) {
                        if (p.length == 4 && double.parse(p[3]) == 0) return null;
                        return "#%02x%02x%02x".printf(int.parse(p[0].strip()), int.parse(p[1].strip()), int.parse(p[2].strip()));
                    }
                }
            }
            var rgba = Gdk.RGBA();
            if (rgba.parse(s) && rgba.alpha > 0) return "#%02x%02x%02x".printf((int) (rgba.red * 255), (int) (rgba.green * 255), (int) (rgba.blue * 255));
            return null;
        }

        private static string? css_value(string? style, string key) {
            if (style == null) return null;
            foreach (string decl in style.split(";")) {
                int colon = decl.index_of_char(':');
                if (colon < 0) continue;
                if (decl.substring(0, colon).strip().down() == key) return decl.substring(colon + 1).strip();
            }
            return null;
        }

        private void para_css(Paragraph p, string? style) {
            if (style == null) return;
            foreach (string decl in style.split(";")) {
                int colon = decl.index_of_char(':');
                if (colon < 0) continue;
                string k = decl.substring(0, colon).strip().down();
                string v = decl.substring(colon + 1).strip().down();
                switch (k) {
                    case "text-align":
                        p.props.align = v == "center" ? Align.CENTER : (v == "right" ? Align.RIGHT : (v == "justify" ? Align.JUSTIFY : Align.LEFT));
                        break;
                    case "margin-left": p.props.ind_left = X.length_pt(v, 0); break;
                    case "text-indent": p.props.ind_first = X.length_pt(v, 0); break;
                    default: break;
                }
            }
        }

        private void walk(Xml.Node* n) {
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type == Xml.ElementType.TEXT_NODE || c->type == Xml.ElementType.CDATA_SECTION_NODE) {
                    text(c->content);
                    continue;
                }
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                element(c);
            }
        }

        private void element(Xml.Node* c) {
            string tag = c->name.down();
            string? style = X.attr(c, "style");
            string cls = X.attr(c, "class") ?? "";
            switch (tag) {
                case "script":
                case "style":
                case "head":
                case "title":
                case "meta":
                    return;
                case "p":
                case "div":
                    if (cls.contains("footnotes") || cls.contains("front-matter")) {
                        if (cls.contains("footnotes")) read_footnotes(c);
                        return;
                    }
                    if (tag == "div" && has_block_children(c)) {
                        walk(c);
                        return;
                    }
                    block(para_style_of(c, "Normal"));
                    para_css(para, style);
                    push(css(style));
                    walk(c);
                    pop();
                    end_para();
                    return;
                case "section":
                    if (cls.contains("footnotes")) {
                        read_footnotes(c);
                        return;
                    }
                    walk(c);
                    return;
                case "h1": case "h2": case "h3": case "h4": case "h5": case "h6":
                    block("Heading" + tag.substring(1));
                    para_css(para, style);
                    string? hid = X.attr(c, "id");
                    if (hid != null) para.inlines.add(new Mark(MarkKind.BOOKMARK_START, hid));
                    push(css(style));
                    walk(c);
                    pop();
                    if (hid != null) para.inlines.add(new Mark(MarkKind.BOOKMARK_END, hid));
                    end_para();
                    return;
                case "blockquote":
                    end_para();
                    int before = target.size;
                    walk(c);
                    end_para();
                    for (int i = before; i < target.size; i++) {
                        var p = target[i] as Paragraph;
                        if (p != null && p.style == "Normal") p.style = "Quote";
                    }
                    return;
                case "pre":
                    block("SourceCode");
                    pre = true;
                    walk(c);
                    pre = false;
                    end_para();
                    return;
                case "br":
                    ensure_para().inlines.add(new Break(BreakKind.LINE));
                    return;
                case "hr":
                    end_para();
                    var hr = new Paragraph();
                    hr.props.border_bottom = new Border.with("single", 0.75, "#808080");
                    target.add(hr);
                    return;
                case "b": case "strong":
                    var b = new CharProps();
                    b.bold = Tri.ON;
                    b.overlay(css(style));
                    inline_with(c, b);
                    return;
                case "i": case "em": case "cite": case "dfn":
                    var i = new CharProps();
                    i.italic = Tri.ON;
                    i.overlay(css(style));
                    inline_with(c, i);
                    return;
                case "u": case "ins":
                    var u = new CharProps();
                    u.underline = Underline.SINGLE;
                    inline_with(c, u);
                    return;
                case "s": case "strike": case "del":
                    var s = new CharProps();
                    s.strike = Tri.ON;
                    inline_with(c, s);
                    return;
                case "sup":
                    if (cls.contains("fn") || cls.contains("footnote")) {
                        Xml.Node* a = X.child(c, "a");
                        string href = a != null ? (X.attr(a, "href") ?? "") : "";
                        if (href.has_prefix("#")) {
                            var r = new NoteRef(new Note(NoteKind.FOOTNOTE));
                            note_refs[href.substring(1)] = r;
                            ensure_para().inlines.add(r);
                            return;
                        }
                    }
                    var sp = new CharProps();
                    sp.valign = VAlign.SUPER;
                    inline_with(c, sp);
                    return;
                case "sub":
                    var sb = new CharProps();
                    sb.valign = VAlign.SUB;
                    inline_with(c, sb);
                    return;
                case "code": case "kbd": case "samp": case "tt":
                    var cd = new CharProps();
                    cd.font = "Liberation Mono";
                    inline_with(c, cd);
                    return;
                case "mark":
                    var mk = new CharProps();
                    mk.highlight = "#ffff00";
                    inline_with(c, mk);
                    return;
                case "small":
                    var sm = new CharProps();
                    sm.size = 9;
                    inline_with(c, sm);
                    return;
                case "font":
                    var f = new CharProps();
                    string? col = X.attr(c, "color");
                    if (col != null) f.color = css_color(col);
                    string? face = X.attr(c, "face");
                    if (face != null) f.font = face.split(",")[0].strip();
                    inline_with(c, f);
                    return;
                case "span":
                    if (cls.contains("check-fallback")) return;
                    inline_with(c, css(style));
                    return;
                case "a":
                    var l = new CharProps();
                    string? href2 = X.attr(c, "href");
                    if (href2 != null && href2 != "") l.link = href2;
                    string? name = X.attr(c, "name") ?? X.attr(c, "id");
                    if (name != null && href2 == null) ensure_para().inlines.add(new Mark(MarkKind.BOOKMARK_START, name));
                    inline_with(c, l);
                    if (name != null && href2 == null) ensure_para().inlines.add(new Mark(MarkKind.BOOKMARK_END, name));
                    return;
                case "img":
                    image(c);
                    return;
                case "ul":
                case "ol":
                    list(c, tag == "ol");
                    return;
                case "li":
                    walk(c);
                    return;
                case "table":
                    table(c);
                    return;
                case "input":
                    if ((X.attr(c, "type") ?? "") == "checkbox") {
                        var ff = new FormField(FormKind.CHECKBOX);
                        ff.checked = X.attr(c, "checked") != null;
                        ensure_para().inlines.add(ff);
                    }
                    return;
                case "dl":
                    walk(c);
                    return;
                case "dt":
                    block("Normal");
                    var dt = new CharProps();
                    dt.bold = Tri.ON;
                    push(dt);
                    walk(c);
                    pop();
                    end_para();
                    return;
                case "dd":
                    block("Normal");
                    para.props.ind_left = 36;
                    walk(c);
                    end_para();
                    return;
                default:
                    walk(c);
                    return;
            }
        }

        private string para_style_of(Xml.Node* c, string fallback) {
            string cls = X.attr(c, "class") ?? "";
            foreach (string s in cls.split(" ")) {
                if (s.has_prefix("style-")) return s.substring(6);
            }
            return fallback;
        }

        private static bool has_block_children(Xml.Node* n) {
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                switch (c->name.down()) {
                    case "p": case "div": case "h1": case "h2": case "h3": case "h4": case "h5": case "h6":
                    case "ul": case "ol": case "table": case "blockquote": case "pre": case "section":
                        return true;
                    default: break;
                }
            }
            return false;
        }

        private void inline_with(Xml.Node* c, CharProps props) {
            push(props);
            walk(c);
            pop();
        }

        private void image(Xml.Node* c) {
            string src = X.attr(c, "src") ?? "";
            Bytes? data = null;
            if (src.has_prefix("data:")) {
                int comma = src.index_of_char(',');
                if (comma > 0 && src.substring(0, comma).contains("base64")) data = new Bytes(Base64.decode(src.substring(comma + 1)));
            } else if (src != "" && resolver != null && (data = resolver(src)) != null) {
            } else if (src != "" && !src.has_prefix("http")) {
                string path = src.has_prefix("file://") ? File.new_for_uri(src).get_path() : (base_dir != null && !Path.is_absolute(src) ? Path.build_filename(base_dir, Uri.unescape_string(src) ?? src) : src);
                try {
                    uint8[] d;
                    FileUtils.get_data(path, out d);
                    data = new Bytes(d);
                } catch (Error e) {
                }
            }
            if (data == null) {
                string alt = X.attr(c, "alt") ?? "";
                if (alt != "") text("[" + alt + "]");
                return;
            }
            var img = new ImageRun(data, ImageRun.sniff(data.get_data()));
            img.alt = X.attr(c, "alt") ?? "";
            img.title = X.attr(c, "title") ?? "";
            double w = X.length_pt((X.attr(c, "width") ?? "") + (X.attr(c, "width") != null && !(X.attr(c, "width") ?? "").contains("%") ? "px" : ""), 0);
            double h = X.length_pt((X.attr(c, "height") ?? "") + (X.attr(c, "height") != null ? "px" : ""), 0);
            int pw, ph;
            natural_size(data, out pw, out ph);
            if (w <= 0 && pw > 0) w = pw * 0.75;
            if (h <= 0 && ph > 0) h = w > 0 && pw > 0 ? w * ph / pw : ph * 0.75;
            img.width = w > 0 ? double.min(w, 450) : 144;
            img.height = h > 0 ? (w > 450 ? h * 450 / w : h) : 144;
            ensure_para().inlines.add(img);
        }

        public static void natural_size(Bytes data, out int w, out int h) {
            w = 0;
            h = 0;
            try {
                var loader = new Gdk.PixbufLoader();
                loader.write(data.get_data());
                loader.close();
                var pb = loader.get_pixbuf();
                if (pb != null) {
                    w = pb.width;
                    h = pb.height;
                }
            } catch (Error e) {
            }
        }

        private void list(Xml.Node* c, bool ordered) {
            end_para();
            int level = lists.size;
            string lst = (X.attr(c, "style") ?? "").down().replace(" ", "");
            bool plain = lst.contains("list-style-type:none") || lst.contains("list-style:none");
            int num = 0;
            if (!plain) {
                int parent = -1;
                for (int k = lists.size - 1; k >= 0; k--) if (lists[k] > 0) {
                    parent = lists[k];
                    break;
                }
                var pd = parent > 0 ? doc.numbering.def_for(parent) : null;
                bool same = pd != null && pd.is_bullet() == !ordered;
                if (same) {
                    num = parent;
                } else {
                    var d = ordered ? doc.numbering.make_numbers() : doc.numbering.make_bullets();
                    num = doc.numbering.add_instance(d);
                }
                string type = X.attr(c, "type") ?? "";
                if (ordered && type != "") {
                    var lv = doc.numbering.level(num, level);
                    if (lv != null) {
                        switch (type) {
                            case "i": lv.format = NumFormat.LOWER_ROMAN; break;
                            case "I": lv.format = NumFormat.UPPER_ROMAN; break;
                            case "a": lv.format = NumFormat.LOWER_LETTER; break;
                            case "A": lv.format = NumFormat.UPPER_LETTER; break;
                            default: lv.format = NumFormat.DECIMAL; break;
                        }
                    }
                }
            }
            lists.add(num);
            foreach (var li in X.kids(c)) {
                if (li->name.down() != "li") continue;
                para = new Paragraph("ListParagraph");
                if (num > 0) {
                    para.props.num_id = num;
                    para.props.num_level = level;
                    var lvp = doc.numbering.level(num, level);
                    if (lvp != null) para.props.ind_left = lvp.ind_left;
                } else {
                    para.props.num_id = 0;
                    para.props.ind_left = 36 * level;
                }
                target.add(para);
                for (Xml.Node* k = li->children; k != null; k = k->next) {
                    if (k->type == Xml.ElementType.TEXT_NODE) {
                        text(k->content);
                        continue;
                    }
                    if (k->type != Xml.ElementType.ELEMENT_NODE) continue;
                    string kt = k->name.down();
                    if (kt == "ul" || kt == "ol") {
                        list(k, kt == "ol");
                    } else if (kt == "p") {
                        if (para == null) {
                            para = new Paragraph("ListParagraph");
                            target.add(para);
                        }
                        walk(k);
                    } else {
                        element(k);
                    }
                }
                end_para();
            }
            lists.remove_at(lists.size - 1);
            end_para();
        }

        private void table(Xml.Node* c) {
            end_para();
            var rows = new Gee.ArrayList<Xml.Node*>();
            collect_tr(c, rows);
            int ncols = 0;
            foreach (var tr in rows) {
                int n = 0;
                foreach (var td in X.kids(tr)) {
                    string t = td->name.down();
                    if (t == "td" || t == "th") n += int.max(1, X.ival(td, "colspan", 1));
                }
                ncols = int.max(ncols, n);
            }
            if (ncols == 0) return;
            var t = Table.create(0, ncols, 450);
            var saved = target;
            foreach (var tr in rows) {
                var row = new TableRow();
                bool all_th = true;
                foreach (var td in X.kids(tr)) {
                    string tn = td->name.down();
                    if (tn != "td" && tn != "th") continue;
                    if (tn == "td") all_th = false;
                    var cell = new TableCell();
                    cell.span = int.max(1, X.ival(td, "colspan", 1));
                    target = cell.blocks;
                    para = null;
                    if (tn == "th") {
                        var b = new CharProps();
                        b.bold = Tri.ON;
                        push(b);
                    }
                    string? al = X.attr(td, "align");
                    string? st = X.attr(td, "style");
                    walk(td);
                    if (tn == "th") pop();
                    end_para();
                    if (cell.blocks.size == 0) cell.blocks.add(new Paragraph());
                    foreach (var bl in cell.blocks.items) {
                        var p = bl as Paragraph;
                        if (p == null) continue;
                        if (al != null) p.props.align = al == "center" ? Align.CENTER : (al == "right" ? Align.RIGHT : Align.LEFT);
                        para_css(p, st);
                        p.props.space_after = 0;
                    }
                    string? bg = X.attr(td, "bgcolor");
                    if (bg != null) cell.shading = css_color(bg);
                    string? cbg = css_value(st, "background-color") ?? css_value(st, "background");
                    if (cbg != null && css_color(cbg) != null) cell.shading = css_color(cbg);
                    row.cells.add(cell);
                }
                row.header = all_th && row.cells.size > 0;
                t.rows.add(row);
            }
            target = saved;
            para = null;
            target.add(t);
        }

        private void collect_tr(Xml.Node* n, Gee.ArrayList<Xml.Node*> rows) {
            foreach (var c in X.kids(n)) {
                string t = c->name.down();
                if (t == "tr") rows.add(c);
                else if (t == "thead" || t == "tbody" || t == "tfoot") collect_tr(c, rows);
            }
        }

        private void read_footnotes(Xml.Node* c) {
            var items = new Gee.ArrayList<Xml.Node*>();
            X.descendants(c, "li", items);
            foreach (var li in items) {
                string? id = X.attr(li, "id");
                if (id == null) continue;
                var note = new Note(NoteKind.FOOTNOTE);
                var saved = target;
                target = note.blocks;
                para = null;
                walk(li);
                end_para();
                target = saved;
                foreach (var b in note.blocks.items) {
                    var p = b as Paragraph;
                    if (p == null) continue;
                    p.style = "FootnoteText";
                    for (int i = p.inlines.size - 1; i >= 0; i--) {
                        var tr = p.inlines[i] as TextRun;
                        if (tr != null && tr.props.link != null && tr.props.link.has_prefix("#")) p.inlines.remove_at(i);
                    }
                    p.normalize();
                }
                notes[id] = note;
            }
        }
    }

    public delegate string ImageSrc(ImageRun img);
    public delegate Bytes? BytesResolver(string src);

    public class HtmlWriter : Object {
        public bool xhtml = false;
        public unowned ImageSrc? image_src = null;
        private Document doc;
        private StringBuilder o = new StringBuilder();
        private Gee.ArrayList<Note> notes = new Gee.ArrayList<Note>();
        private ListCounter counter;

        public static string save(Document doc) {
            var w = new HtmlWriter(doc);
            return w.write();
        }

        public HtmlWriter(Document doc) {
            this.doc = doc;
            counter = new ListCounter(doc.numbering);
        }

        public static string esc(string s) {
            return X.esc(s);
        }

        private string css_char(CharProps c) {
            var sb = new StringBuilder();
            if (c.font != null) sb.append("font-family:'%s';".printf(c.font));
            if (c.size > 0) sb.append("font-size:%spt;".printf(X.num(c.size)));
            if (c.bold != Tri.INHERIT) sb.append(c.bold.on() ? "font-weight:bold;" : "font-weight:normal;");
            if (c.italic != Tri.INHERIT) sb.append(c.italic.on() ? "font-style:italic;" : "font-style:normal;");
            var deco = new StringBuilder();
            if (c.underline != Underline.INHERIT && c.underline != Underline.NONE) deco.append(" underline");
            if (c.strike.on() || c.dstrike.on()) deco.append(" line-through");
            if (deco.len > 0) sb.append("text-decoration:%s;".printf(deco.str.strip()));
            if (c.underline == Underline.DOUBLE) sb.append("text-decoration-style:double;");
            else if (c.underline == Underline.WAVY) sb.append("text-decoration-style:wavy;");
            else if (c.underline == Underline.DOTTED) sb.append("text-decoration-style:dotted;");
            if (c.color != null) sb.append("color:%s;".printf(c.color));
            if (c.highlight != null && c.highlight != "none") sb.append("background-color:%s;".printf(c.highlight));
            else if (c.shading != null) sb.append("background-color:%s;".printf(c.shading));
            if (c.caps == Caps.SMALL) sb.append("font-variant:small-caps;");
            else if (c.caps == Caps.ALL) sb.append("text-transform:uppercase;");
            if (c.valign == VAlign.SUPER) sb.append("vertical-align:super;font-size:smaller;");
            else if (c.valign == VAlign.SUB) sb.append("vertical-align:sub;font-size:smaller;");
            if (!c.spacing.is_nan()) sb.append("letter-spacing:%spt;".printf(X.num(c.spacing)));
            if (c.hidden.on()) sb.append("display:none;");
            return sb.str;
        }

        private string css_para(ParaProps p) {
            var sb = new StringBuilder();
            switch (p.align) {
                case Align.CENTER: sb.append("text-align:center;"); break;
                case Align.RIGHT: sb.append("text-align:right;"); break;
                case Align.JUSTIFY: sb.append("text-align:justify;"); break;
                case Align.LEFT: sb.append("text-align:left;"); break;
                default: break;
            }
            if (!p.ind_left.is_nan()) sb.append("margin-left:%spt;".printf(X.num(p.ind_left)));
            if (!p.ind_right.is_nan()) sb.append("margin-right:%spt;".printf(X.num(p.ind_right)));
            if (!p.ind_first.is_nan()) sb.append("text-indent:%spt;".printf(X.num(p.ind_first)));
            if (!p.space_before.is_nan()) sb.append("margin-top:%spt;".printf(X.num(p.space_before)));
            if (!p.space_after.is_nan()) sb.append("margin-bottom:%spt;".printf(X.num(p.space_after)));
            if (!p.line.is_nan()) {
                if (p.line_rule == LineRule.AUTO) sb.append("line-height:%s;".printf(X.num(p.line * 1.15)));
                else sb.append("line-height:%spt;".printf(X.num(p.line)));
            }
            if (p.shading != null) sb.append("background-color:%s;".printf(p.shading));
            if (p.border_top != null && p.border_top.visible()) sb.append("border-top:%spt solid %s;".printf(X.num(p.border_top.width), p.border_top.color));
            if (p.border_bottom != null && p.border_bottom.visible()) sb.append("border-bottom:%spt solid %s;".printf(X.num(p.border_bottom.width), p.border_bottom.color));
            if (p.border_left != null && p.border_left.visible()) sb.append("border-left:%spt solid %s;".printf(X.num(p.border_left.width), p.border_left.color));
            if (p.border_right != null && p.border_right.visible()) sb.append("border-right:%spt solid %s;".printf(X.num(p.border_right.width), p.border_right.color));
            if (p.page_break_before.on()) sb.append("page-break-before:always;");
            return sb.str;
        }

        private static string css_class(string id) {
            var sb = new StringBuilder();
            unichar c;
            int i = 0;
            while (id.get_next_char(ref i, out c)) if (c.isalnum()) sb.append_unichar(c);
            return "style-" + sb.str;
        }

        public string write() {
            var body = new StringBuilder();
            write_blocks(body, doc.body);
            string lang = doc.lang != "" ? esc(doc.lang) : "en";
            if (xhtml) {
                o.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE html>\n<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:epub=\"http://www.idpf.org/2007/ops\" lang=\"%s\" xml:lang=\"%s\"><head><meta charset=\"utf-8\"/>\n".printf(lang, lang));
            } else {
                o.append("<!DOCTYPE html>\n<html lang=\"%s\"><head><meta charset=\"utf-8\">\n".printf(lang));
                o.append("<meta name=\"generator\" content=\"Singularity Write\">\n");
            }
            string close = xhtml ? "/>" : ">";
            if (doc.meta.author != "") o.append("<meta name=\"author\" content=\"%s\"%s\n".printf(esc(doc.meta.author), close));
            if (doc.meta.description != "") o.append("<meta name=\"description\" content=\"%s\"%s\n".printf(esc(doc.meta.description), close));
            if (doc.meta.keywords != "") o.append("<meta name=\"keywords\" content=\"%s\"%s\n".printf(esc(doc.meta.keywords), close));
            o.append("<title>%s</title>\n<style>\n".printf(esc(doc.meta.title != "" ? doc.meta.title : _("Document"))));
            var s = doc.final_section;
            o.append("body{max-width:%spt;margin:2em auto;padding:0 1em;%s%s}\n".printf(X.num(s.content_width()), css_char(doc.styles.default_char), doc.page_color != null ? "background:%s;".printf(doc.page_color) : ""));
            o.append("p{margin:0;%s}\n".printf(css_para(doc.styles.default_para)));
            o.append("table{border-collapse:collapse}td,th{vertical-align:top;padding:2pt 5pt}\n");
            o.append("img{max-width:100%}\n.footnotes{font-size:smaller;border-top:1px solid #999;margin-top:2em}\n");
            foreach (var st in doc.styles.list) {
                if (st.kind != StyleType.PARAGRAPH && st.kind != StyleType.CHARACTER) continue;
                string pcss = st.kind == StyleType.PARAGRAPH ? css_para(doc.styles.para_chain(st.id)) : "";
                o.append(".%s{%s%s}\n".printf(css_class(st.id), pcss, css_char(doc.styles.char_chain(st.id))));
            }
            o.append("</style></head><body>\n");
            o.append(body.str);
            if (notes.size > 0) {
                o.append("<section class=\"footnotes\"><ol>\n");
                for (int i = 0; i < notes.size; i++) {
                    o.append("<li id=\"fn%d\">".printf(i + 1));
                    var nb = new StringBuilder();
                    foreach (var b in notes[i].blocks.items) {
                        var p = b as Paragraph;
                        if (p != null) inlines(nb, p.inlines);
                        nb.append(" ");
                    }
                    o.append(nb.str.strip());
                    o.append(" <a href=\"#fnref%d\">^</a></li>\n".printf(i + 1));
                }
                o.append("</ol></section>\n");
            }
            o.append("</body></html>\n");
            return o.str;
        }

        private void write_blocks(StringBuilder sb, BlockList list) {
            int i = 0;
            while (i < list.size) {
                var p = list[i] as Paragraph;
                if (p != null && p.props.num_id > 0 && doc.numbering.instance(p.props.num_id) != null) {
                    int j = i;
                    while (j < list.size && list[j] is Paragraph && ((Paragraph) list[j]).props.num_id > 0) j++;
                    write_list(sb, list, i, j, 0);
                    i = j;
                    continue;
                }
                var b = list[i];
                if (p != null) write_para(sb, p, "p");
                else if (b is Table) write_table(sb, (Table) b);
                else if (b is FieldBlock) {
                    sb.append("<nav class=\"field-%s\">\n".printf(((FieldBlock) b).kind().down()));
                    write_blocks(sb, ((FieldBlock) b).result);
                    sb.append("</nav>\n");
                }
                i++;
            }
        }

        private void write_list(StringBuilder sb, BlockList list, int from, int to, int level) {
            var first = (Paragraph) list[from];
            var def = doc.numbering.def_for(first.props.num_id);
            bool ordered = def != null && def.levels[level.clamp(0, 8)].format != NumFormat.BULLET;
            sb.append(ordered ? "<ol>\n" : "<ul>\n");
            int k = from;
            while (k < to) {
                var p = (Paragraph) list[k];
                sb.append("<li>");
                counter.label(p.props.num_id, int.max(0, p.props.num_level));
                write_para(sb, p, "span");
                k++;
                int m = k;
                while (m < to && int.max(0, ((Paragraph) list[m]).props.num_level) > level) m++;
                if (m > k) {
                    write_list(sb, list, k, m, level + 1);
                    k = m;
                }
                sb.append("</li>\n");
            }
            sb.append(ordered ? "</ol>\n" : "</ul>\n");
        }

        private void write_para(StringBuilder sb, Paragraph p, string container) {
            int lvl = doc.styles.outline_level(p);
            string tag = container;
            if (container == "p" && lvl >= 0 && lvl < 6 && p.style.has_prefix("Heading")) tag = "h%d".printf(lvl + 1);
            else if (container == "p" && p.style == "Title") tag = "h1";
            else if (container == "p" && (p.style == "Quote" || p.style == "IntenseQuote")) tag = "blockquote";
            else if (container == "p" && p.style == "SourceCode") tag = "pre";
            sb.append("<%s class=\"%s\"".printf(tag, css_class(p.style)));
            string pc = css_para(p.props);
            if (pc != "") sb.append(" style=\"%s\"".printf(esc(pc)));
            sb.append(">");
            if (p.is_empty() && tag == "p") sb.append(xhtml ? "<br/>" : "<br>");
            inlines(sb, p.inlines);
            sb.append("</%s>\n".printf(tag));
        }

        private void inlines(StringBuilder sb, Gee.List<Inline> list) {
            foreach (var it in list) {
                if (it.deleted()) continue;
                string link = it.props.link ?? "";
                if (link != "") sb.append("<a href=\"%s\">".printf(esc(link)));
                var cp = it.props.copy();
                cp.link = null;
                string cstyle = cp.style != null ? css_class(cp.style) : "";
                cp.style = null;
                string css = css_char(cp);
                bool span = css != "" || cstyle != "";
                if (span && (it is TextRun || it is FieldRun)) {
                    sb.append("<span");
                    if (cstyle != "") sb.append(" class=\"%s\"".printf(cstyle));
                    if (css != "") sb.append(" style=\"%s\"".printf(esc(css)));
                    sb.append(">");
                }
                if (it is TextRun) {
                    sb.append(esc(((TextRun) it).text).replace("\n", xhtml ? "<br/>" : "<br>"));
                } else if (it is Tab) {
                    sb.append("&#8195;");
                } else if (it is Break) {
                    var b = (Break) it;
                    sb.append(b.kind == BreakKind.LINE ? (xhtml ? "<br/>" : "<br>") : (xhtml ? "<br style=\"page-break-after:always\"/>" : "<br style=\"page-break-after:always\">"));
                } else if (it is FieldRun) {
                    sb.append(esc(((FieldRun) it).result));
                } else if (it is NoteRef) {
                    notes.add(((NoteRef) it).note);
                    int n = notes.size;
                    sb.append("<sup class=\"fn\" id=\"fnref%d\"><a href=\"#fn%d\">%d</a></sup>".printf(n, n, n));
                } else if (it is Mark) {
                    var m = (Mark) it;
                    if (m.kind == MarkKind.BOOKMARK_START) sb.append("<a id=\"%s\"></a>".printf(esc(m.name)));
                } else if (it is ImageRun) {
                    var img = (ImageRun) it;
                    string fl = "";
                    if (img.wrap == Wrap.SQUARE || img.wrap == Wrap.TIGHT) fl = img.halign == HAlignObj.RIGHT || img.hoff > 200 ? "float:right;margin:0 0 6pt 9pt;" : "float:left;margin:0 9pt 6pt 0;";
                    else if (img.wrap == Wrap.TOP_BOTTOM) fl = "display:block;";
                    string src = image_src != null ? image_src(img) : "data:%s;base64,%s".printf(img.mime, Base64.encode(img.data.get_data()));
                    sb.append("<img src=\"%s\" alt=\"%s\" style=\"width:%spt;height:%spt;%s\"%s%s".printf(
                        esc(src), esc(img.alt), X.num(img.width), X.num(img.height), fl, img.title != "" ? " title=\"%s\"".printf(esc(img.title)) : "", xhtml ? "/>" : ">"));
                } else if (it is ShapeRun) {
                    var s = (ShapeRun) it;
                    sb.append("<div style=\"display:inline-block;width:%spt;min-height:%spt;%s%s\">".printf(X.num(s.width), X.num(s.height), s.fill != null ? "background:%s;".printf(s.fill) : "", s.stroke != null ? "border:%spt solid %s;".printf(X.num(s.stroke_width), s.stroke) : ""));
                    write_blocks(sb, s.text);
                    sb.append("</div>");
                } else if (it is EquationRun) {
                    var e = (EquationRun) it;
                    sb.append(e.mathml != "" ? e.mathml : esc(e.linear_text()));
                } else if (it is FormField) {
                    var f = (FormField) it;
                    if (f.kind == FormKind.CHECKBOX) sb.append(xhtml ? "<input type=\"checkbox\" disabled=\"disabled\"%s/>".printf(f.checked ? " checked=\"checked\"" : "") : "<input type=\"checkbox\" disabled%s>".printf(f.checked ? " checked" : ""));
                    else sb.append(esc(f.display_text()));
                } else if (it is OpaqueRun) {
                    var op = (OpaqueRun) it;
                    if (op.preview != null) sb.append("<img src=\"data:%s;base64,%s\" alt=\"%s\"%s".printf(ImageRun.sniff(op.preview.get_data()), Base64.encode(op.preview.get_data()), esc(op.description), xhtml ? "/>" : ">"));
                }
                if (span && (it is TextRun || it is FieldRun)) sb.append("</span>");
                if (link != "") sb.append("</a>");
            }
        }

        private void write_table(StringBuilder sb, Table t) {
            sb.append("<table%s>\n".printf(t.description != "" ? " summary=\"%s\"".printf(esc(t.description)) : ""));
            if (t.caption != "") sb.append("<caption>%s</caption>\n".printf(esc(t.caption)));
            var style = doc.styles.get(t.style);
            for (int r = 0; r < t.rows.size; r++) {
                var row = t.rows[r];
                sb.append("<tr>");
                int col = 0;
                foreach (var c in row.cells) {
                    if (c.vmerge == VMerge.CONTINUE) {
                        col += c.span;
                        continue;
                    }
                    int rspan = 1;
                    if (c.vmerge == VMerge.RESTART) {
                        for (int rr = r + 1; rr < t.rows.size; rr++) {
                            var below = t.cell_at_grid(t.rows[rr], col);
                            if (below == null || below.vmerge != VMerge.CONTINUE) break;
                            rspan++;
                        }
                    }
                    string tag = row.header ? "th" : "td";
                    var css = new StringBuilder();
                    Border? b = t.border_h ?? t.border_top ?? (style != null ? style.table_border : null);
                    if (b != null && b.visible()) css.append("border:%spt solid %s;".printf(X.num(b.width), b.color));
                    string? shade = c.shading ?? (row.header && style != null ? style.table_header_shading : null);
                    if (shade != null) css.append("background:%s;".printf(shade));
                    double w = 0;
                    for (int k = col; k < col + c.span && k < t.grid.length; k++) w += t.grid[k];
                    if (w > 0) css.append("width:%spt;".printf(X.num(w)));
                    sb.append("<%s style=\"%s\"%s%s>".printf(tag, css.str, c.span > 1 ? " colspan=\"%d\"".printf(c.span) : "", rspan > 1 ? " rowspan=\"%d\"".printf(rspan) : ""));
                    write_blocks(sb, c.blocks);
                    sb.append("</%s>".printf(tag));
                    col += c.span;
                }
                sb.append("</tr>\n");
            }
            sb.append("</table>\n");
        }
    }

    public class MarkdownWriter : Object {
        private Document doc;
        private Gee.ArrayList<Note> notes = new Gee.ArrayList<Note>();
        private ListCounter counter;

        public static string save(Document doc) {
            return new MarkdownWriter(doc).write();
        }

        public MarkdownWriter(Document doc) {
            this.doc = doc;
            counter = new ListCounter(doc.numbering);
        }

        public string write() {
            var sb = new StringBuilder();
            if (doc.meta.title != "" || doc.meta.author != "") {
                sb.append("---\n");
                if (doc.meta.title != "") sb.append("title: %s\n".printf(doc.meta.title));
                if (doc.meta.author != "") sb.append("author: %s\n".printf(doc.meta.author));
                sb.append("---\n\n");
            }
            blocks(sb, doc.body);
            for (int i = 0; i < notes.size; i++) {
                var nb = new StringBuilder();
                foreach (var b in notes[i].blocks.items) {
                    var p = b as Paragraph;
                    if (p != null) nb.append(inl(p.inlines));
                }
                sb.append("[^%d]: %s\n".printf(i + 1, nb.str.strip()));
            }
            return sb.str;
        }

        private void blocks(StringBuilder sb, BlockList list) {
            foreach (var b in list.items) {
                var p = b as Paragraph;
                if (p != null) {
                    int lvl = doc.styles.outline_level(p);
                    string text = inl(p.inlines);
                    if (p.props.num_id > 0) {
                        var def = doc.numbering.def_for(p.props.num_id);
                        int level = int.max(0, p.props.num_level);
                        string? lab = counter.label(p.props.num_id, level);
                        bool bullet = def == null || def.levels[level.clamp(0, 8)].format == NumFormat.BULLET;
                        sb.append(string.nfill(level * 4, ' '));
                        sb.append(bullet ? "- " : (lab ?? "1.") + " ");
                        sb.append(text);
                        sb.append("\n");
                        continue;
                    }
                    if (p.style == "Title") sb.append("# " + text + "\n\n");
                    else if (lvl >= 0 && lvl < 6 && p.style.has_prefix("Heading")) sb.append(string.nfill(lvl + 1, '#') + " " + text + "\n\n");
                    else if (p.style == "Quote" || p.style == "IntenseQuote") sb.append("> " + text + "\n\n");
                    else if (p.style == "SourceCode") sb.append("```\n" + p.plain_text() + "\n```\n\n");
                    else if (text.strip() != "") sb.append(text + "\n\n");
                    continue;
                }
                var t = b as Table;
                if (t != null) {
                    for (int r = 0; r < t.rows.size; r++) {
                        sb.append("|");
                        foreach (var c in t.rows[r].cells) {
                            var cb = new StringBuilder();
                            foreach (var cbk in c.blocks.items) {
                                var cp = cbk as Paragraph;
                                if (cp != null) cb.append(inl(cp.inlines) + " ");
                            }
                            sb.append(" " + cb.str.strip().replace("|", "\\|") + " |");
                            for (int k = 1; k < c.span; k++) sb.append(" |");
                        }
                        sb.append("\n");
                        if (r == 0) {
                            sb.append("|");
                            for (int k = 0; k < t.columns(); k++) sb.append(" --- |");
                            sb.append("\n");
                        }
                    }
                    sb.append("\n");
                    continue;
                }
                var fb = b as FieldBlock;
                if (fb != null) blocks(sb, fb.result);
            }
        }

        private string inl(Gee.List<Inline> list) {
            var sb = new StringBuilder();
            foreach (var it in list) {
                if (it.deleted()) continue;
                string s = "";
                if (it is TextRun) s = md_escape(((TextRun) it).text);
                else if (it is Tab) s = "    ";
                else if (it is Break) s = "  \n";
                else if (it is FieldRun) s = md_escape(((FieldRun) it).result);
                else if (it is NoteRef) {
                    notes.add(((NoteRef) it).note);
                    sb.append("[^%d]".printf(notes.size));
                    continue;
                } else if (it is ImageRun) {
                    var img = (ImageRun) it;
                    sb.append("![%s](data:%s;base64,%s)".printf(img.alt, img.mime, Base64.encode(img.data.get_data())));
                    continue;
                } else if (it is EquationRun) {
                    var e = (EquationRun) it;
                    sb.append(e.display ? "$$" + e.linear_text() + "$$" : "$" + e.linear_text() + "$");
                    continue;
                } else if (it is FormField) {
                    var f = (FormField) it;
                    s = f.kind == FormKind.CHECKBOX ? (f.checked ? "[x]" : "[ ]") : f.display_text();
                } else {
                    continue;
                }
                if (s == "") continue;
                var c = it.props;
                string lead = "";
                string trail = "";
                string core = s;
                while (core.has_prefix(" ")) {
                    lead += " ";
                    core = core.substring(1);
                }
                while (core.has_suffix(" ")) {
                    trail += " ";
                    core = core.substring(0, core.length - 1);
                }
                if (core == "") {
                    sb.append(s);
                    continue;
                }
                if (c.font != null && c.font.contains("Mono")) core = "`" + core + "`";
                if (c.bold.on() || c.style == "Strong") core = "**" + core + "**";
                if (c.italic.on() || c.style == "Emphasis") core = "*" + core + "*";
                if (c.strike.on()) core = "~~" + core + "~~";
                if (c.valign == VAlign.SUPER) core = "^" + core + "^";
                if (c.valign == VAlign.SUB) core = "~" + core + "~";
                if (c.link != null) core = "[" + core + "](" + c.link + ")";
                sb.append(lead + core + trail);
            }
            return sb.str;
        }

        private static string md_escape(string s) {
            var sb = new StringBuilder();
            unichar c;
            int i = 0;
            while (s.get_next_char(ref i, out c)) {
                if (c == '*' || c == '_' || c == '`' || c == '[' || c == ']' || c == '\\') sb.append_c('\\');
                sb.append_unichar(c);
            }
            return sb.str;
        }
    }
}
