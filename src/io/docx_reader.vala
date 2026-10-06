namespace Write {

    public class DocxReader : Object {
        private ZipReader zip;
        private Document doc;
        private string main_part = "word/document.xml";
        private Gee.HashMap<string, string> rel_target = new Gee.HashMap<string, string>();
        private Gee.HashMap<string, string> rel_type = new Gee.HashMap<string, string>();
        private Gee.HashMap<string, string> rel_mode = new Gee.HashMap<string, string>();
        private Gee.HashMap<string, Note> footnotes = new Gee.HashMap<string, Note>();
        private Gee.HashMap<string, Note> endnotes = new Gee.HashMap<string, Note>();
        private Gee.HashMap<string, HeaderFooter> hf_cache = new Gee.HashMap<string, HeaderFooter>();
        private string minor_font = "Calibri";
        private string major_font = "Calibri Light";
        private Gee.HashMap<string, string> theme_colors = new Gee.HashMap<string, string>();
        private Gee.HashSet<string> consumed = new Gee.HashSet<string>();
        private Gee.HashMap<string, string> comment_para_ids = new Gee.HashMap<string, string>();

        private class PartCtx {
            public string part;
            public Gee.HashMap<string, string> targets = new Gee.HashMap<string, string>();
            public Gee.HashMap<string, string> types = new Gee.HashMap<string, string>();
            public Gee.HashMap<string, string> modes = new Gee.HashMap<string, string>();
            public Xml.Doc* xdoc;
        }

        private PartCtx cur;

        private class FieldState {
            public string code = "";
            public bool in_result = false;
            public Gee.ArrayList<Inline> result = new Gee.ArrayList<Inline>();
            public FieldBlock? block = null;
            public CharProps? props = null;
        }

        private Gee.ArrayList<FieldState> fields = new Gee.ArrayList<FieldState>();
        private Gee.ArrayList<BlockList> redirect = new Gee.ArrayList<BlockList>();

        public static Document load(uint8[] data) throws Error {
            var r = new DocxReader();
            return r.read(data);
        }

        public Document read(uint8[] data) throws Error {
            zip = new ZipReader(data);
            if (zip.has("EncryptionInfo")) throw new FormatError.ENCRYPTED(_("The document is password protected."));
            doc = new Document();
            find_main_part();
            if (!zip.has(main_part)) throw new FormatError.INVALID(_("The file is not a Word document."));
            consumed.add("[Content_Types].xml");
            consumed.add("_rels/.rels");
            try {
                var ct = zip.read_bytes("[Content_Types].xml");
                if (ct != null) doc.passthrough["[Content_Types].xml"] = ct;
            } catch (Error e) {
            }
            consumed.add(main_part);
            consumed.add(rels_path(main_part));
            load_theme();
            load_styles();
            load_numbering();
            load_settings();
            load_notes("footnotes", NoteKind.FOOTNOTE, footnotes);
            load_notes("endnotes", NoteKind.ENDNOTE, endnotes);
            load_comments();
            load_props();
            load_sources();
            load_body();
            keep_passthrough();
            doc.styles.ensure_builtins();
            return doc;
        }

        private static string rels_path(string part) {
            int slash = part.last_index_of_char('/');
            string dir = slash >= 0 ? part.substring(0, slash + 1) : "";
            string name = slash >= 0 ? part.substring(slash + 1) : part;
            return dir + "_rels/" + name + ".rels";
        }

        public static string resolve(string base_part, string target) {
            if (target.has_prefix("/")) return target.substring(1);
            int slash = base_part.last_index_of_char('/');
            string dir = slash >= 0 ? base_part.substring(0, slash) : "";
            var parts = new Gee.ArrayList<string>();
            if (dir != "") foreach (string p in dir.split("/")) parts.add(p);
            foreach (string p in target.split("/")) {
                if (p == "..") {
                    if (parts.size > 0) parts.remove_at(parts.size - 1);
                } else if (p != "." && p != "") {
                    parts.add(p);
                }
            }
            return string.joinv("/", parts.to_array());
        }

        private void find_main_part() throws Error {
            string? rels = zip.read_text("_rels/.rels");
            if (rels == null) return;
            Xml.Doc* x = X.parse(rels);
            foreach (var r in X.kids(x->get_root_element(), "Relationship")) {
                string type = X.val(r, "Type");
                if (type.has_suffix("/officeDocument")) main_part = resolve("", X.val(r, "Target"));
            }
            delete x;
        }

        private PartCtx open_part(string part) throws Error {
            var ctx = new PartCtx();
            ctx.part = part;
            string? rels = zip.read_text(rels_path(part));
            if (rels != null) {
                consumed.add(rels_path(part));
                Xml.Doc* x = X.parse(rels);
                foreach (var r in X.kids(x->get_root_element(), "Relationship")) {
                    string id = X.val(r, "Id");
                    string mode = X.val(r, "TargetMode");
                    ctx.types[id] = X.val(r, "Type");
                    ctx.modes[id] = mode;
                    ctx.targets[id] = mode == "External" ? X.val(r, "Target") : resolve(part, X.val(r, "Target"));
                }
                delete x;
            }
            string? text = zip.read_text(part);
            if (text == null) throw new FormatError.INVALID("missing part %s", part);
            consumed.add(part);
            ctx.xdoc = X.parse(text);
            return ctx;
        }

        private string? part_by_type(string suffix) {
            try {
                string? rels = zip.read_text(rels_path(main_part));
                if (rels == null) return null;
                Xml.Doc* x = X.parse(rels);
                string? found = null;
                foreach (var r in X.kids(x->get_root_element(), "Relationship")) {
                    if (X.val(r, "Type").has_suffix(suffix)) found = resolve(main_part, X.val(r, "Target"));
                }
                delete x;
                return found;
            } catch (Error e) {
                return null;
            }
        }

        private void load_theme() {
            string? part = part_by_type("/theme");
            if (part == null) return;
            try {
                string? t = zip.read_text(part);
                if (t == null) return;
                Xml.Doc* x = X.parse(t);
                Xml.Node* root = x->get_root_element();
                Xml.Node* fs = X.find_desc(root, "fontScheme");
                if (fs != null) {
                    Xml.Node* maj = X.path(fs, "majorFont/latin");
                    Xml.Node* min = X.path(fs, "minorFont/latin");
                    if (maj != null && X.val(maj, "typeface") != "") major_font = X.val(maj, "typeface");
                    if (min != null && X.val(min, "typeface") != "") minor_font = X.val(min, "typeface");
                }
                Xml.Node* cs = X.find_desc(root, "clrScheme");
                if (cs != null) {
                    foreach (var c in X.kids(cs)) {
                        Xml.Node* srgb = X.child(c, "srgbClr");
                        Xml.Node* sys = X.child(c, "sysClr");
                        string col = srgb != null ? X.val(srgb, "val") : (sys != null ? X.val(sys, "lastClr") : "");
                        if (col != "") theme_colors[c->name] = "#" + col.down();
                    }
                }
                delete x;
            } catch (Error e) {
            }
        }

        private void load_styles() throws Error {
            string? part = part_by_type("/styles");
            if (part == null || !zip.has(part)) return;
            var ctx = open_part(part);
            Xml.Node* root = ctx.xdoc->get_root_element();
            Xml.Node* defs = X.child(root, "docDefaults");
            var sheet = doc.styles;
            sheet.default_char = new CharProps();
            sheet.default_char.font = minor_font;
            sheet.default_char.size = 10;
            var dp = new ParaProps();
            dp.space_before = 0;
            dp.space_after = 0;
            dp.line = 1;
            dp.ind_left = 0;
            dp.ind_right = 0;
            dp.ind_first = 0;
            dp.align = Align.LEFT;
            sheet.default_para = dp;
            if (defs != null) {
                Xml.Node* rpr = X.path(defs, "rPrDefault/rPr");
                if (rpr != null) sheet.default_char.overlay(read_rpr(rpr));
                Xml.Node* ppr = X.path(defs, "pPrDefault/pPr");
                if (ppr != null) sheet.default_para.overlay(read_ppr(ppr, null));
            }
            foreach (var s in X.kids(root, "style")) {
                string type = X.val(s, "type");
                StyleType kind = StyleType.PARAGRAPH;
                if (type == "character") kind = StyleType.CHARACTER;
                else if (type == "table") kind = StyleType.TABLE;
                else if (type == "numbering") kind = StyleType.NUMBERING;
                string id = X.val(s, "styleId");
                Xml.Node* nm = X.child(s, "name");
                string name = nm != null ? X.val(nm) : id;
                var st = new Style(id, pretty_style_name(name), kind);
                Xml.Node* bo = X.child(s, "basedOn");
                if (bo != null) st.based_on = X.val(bo);
                Xml.Node* nx = X.child(s, "next");
                if (nx != null) st.next = X.val(nx);
                Xml.Node* lk = X.child(s, "link");
                if (lk != null) st.link = X.val(lk);
                st.quick = X.child(s, "qFormat") != null;
                st.hidden = X.child(s, "semiHidden") != null || X.child(s, "hidden") != null;
                Xml.Node* up = X.child(s, "uiPriority");
                if (up != null) st.priority = X.ival(up, "val", 99);
                st.custom = X.val(s, "customStyle") == "1";
                Xml.Node* ppr = X.child(s, "pPr");
                if (ppr != null) st.para = read_ppr(ppr, null);
                Xml.Node* rpr = X.child(s, "rPr");
                if (rpr != null) st.chr = read_rpr(rpr);
                if (kind == StyleType.TABLE) {
                    Xml.Node* tb = X.path(s, "tblPr/tblBorders");
                    if (tb != null) {
                        Border? b = read_border(X.child(tb, "insideH")) ?? read_border(X.child(tb, "top"));
                        st.table_border = b;
                    }
                    foreach (var tsp in X.kids(s, "tblStylePr")) {
                        string tt = X.val(tsp, "type");
                        Xml.Node* shd = X.path(tsp, "tcPr/shd");
                        string? fill = shd != null ? color_of(X.val(shd, "fill")) : null;
                        if (tt == "firstRow") {
                            st.table_header_shading = fill;
                            Xml.Node* hr = X.child(tsp, "rPr");
                            if (hr != null) st.table_header_chr = read_rpr(hr);
                        } else if (tt == "band1Horz") {
                            st.table_band_shading = fill;
                        }
                    }
                }
                sheet.add(st);
            }
            delete ctx.xdoc;
        }

        private static string pretty_style_name(string n) {
            string l = n.down();
            if (l.has_prefix("heading ")) return "Heading " + n.substring(8);
            if (l.has_prefix("toc ")) return "TOC " + n.substring(4);
            if (l.has_prefix("index ")) return "Index " + n.substring(6);
            switch (l) {
                case "normal": return "Normal";
                case "title": return "Title";
                case "subtitle": return "Subtitle";
                case "caption": return "Caption";
                case "footnote text": return "Footnote Text";
                case "endnote text": return "Endnote Text";
                case "footnote reference": return "Footnote Reference";
                case "endnote reference": return "Endnote Reference";
                case "header": return "Header";
                case "footer": return "Footer";
                case "hyperlink": return "Hyperlink";
                case "list paragraph": return "List Paragraph";
                case "table grid": return "Table Grid";
                case "annotation text": return "Comment Text";
                case "annotation reference": return "Comment Reference";
                case "table of figures": return "Table of Figures";
                case "index heading": return "Index Heading";
                case "toc heading": return "TOC Heading";
                default: return n;
            }
        }

        private void load_numbering() throws Error {
            string? part = part_by_type("/numbering");
            if (part == null || !zip.has(part)) return;
            var ctx = open_part(part);
            Xml.Node* root = ctx.xdoc->get_root_element();
            foreach (var an in X.kids(root, "abstractNum")) {
                var d = new ListDef(X.ival(an, "abstractNumId", 0));
                foreach (var lvl in X.kids(an, "lvl")) {
                    int i = X.ival(lvl, "ilvl", 0);
                    if (i < 0 || i > 8) continue;
                    var l = d.levels[i];
                    Xml.Node* st = X.child(lvl, "start");
                    if (st != null) l.start = X.ival(st, "val", 1);
                    Xml.Node* fmt = X.child(lvl, "numFmt");
                    if (fmt != null) l.format = num_format(X.val(fmt));
                    Xml.Node* txt = X.child(lvl, "lvlText");
                    if (txt != null) l.text = X.val(txt);
                    Xml.Node* jc = X.child(lvl, "lvlJc");
                    if (jc != null) l.align = align_of(X.val(jc));
                    Xml.Node* suff = X.child(lvl, "suff");
                    if (suff != null) l.suffix = X.val(suff);
                    Xml.Node* ind = X.path(lvl, "pPr/ind");
                    if (ind != null) {
                        l.ind_left = twip(X.attr(ind, "left") ?? X.attr(ind, "start"), l.ind_left);
                        if (X.attr(ind, "hanging") != null) l.hanging = twip(X.attr(ind, "hanging"), 0);
                        else if (X.attr(ind, "firstLine") != null) l.hanging = -twip(X.attr(ind, "firstLine"), 0);
                    }
                    Xml.Node* rpr = X.child(lvl, "rPr");
                    if (rpr != null) {
                        l.label_props = read_rpr(rpr);
                        if (l.label_props.font != null) l.bullet_font = l.label_props.font;
                    }
                    if (l.format == NumFormat.BULLET) l.text = map_symbol_bullet(l.text, l.bullet_font);
                }
                doc.numbering.defs.add(d);
            }
            foreach (var n in X.kids(root, "num")) {
                Xml.Node* aid = X.child(n, "abstractNumId");
                var inst = new ListInstance(X.ival(n, "numId", 0), aid != null ? X.ival(aid, "val", 0) : 0);
                foreach (var ov in X.kids(n, "lvlOverride")) {
                    Xml.Node* so = X.child(ov, "startOverride");
                    if (so != null) inst.start_override[X.ival(ov, "ilvl", 0)] = X.ival(so, "val", 1);
                }
                doc.numbering.instances.add(inst);
            }
            delete ctx.xdoc;
        }

        private static string map_symbol_bullet(string t, string? font) {
            if (t.length == 0) return "\u2022";
            unichar c = t.get_char(0);
            if (c >= 0xF000 && c <= 0xF0FF) {
                unichar low = c - 0xF000;
                if (low == 0xB7) return "\u2022";
                if (low == 0xA7) return "\u25aa";
                if (low == 0xD8) return "\u25b8";
                if (low == 0xFC) return "\u2713";
                if (low == 0x6F) return "\u25e6";
                return "\u2022";
            }
            if (font != null && (font == "Symbol" || font == "Wingdings")) {
                if (c == 0xB7) return "\u2022";
                if (c == 0xA7) return "\u25aa";
            }
            if (c == 'o' && font == "Courier New") return "\u25e6";
            return t;
        }

        public static NumFormat num_format(string v) {
            switch (v) {
                case "lowerLetter": return NumFormat.LOWER_LETTER;
                case "upperLetter": return NumFormat.UPPER_LETTER;
                case "lowerRoman": return NumFormat.LOWER_ROMAN;
                case "upperRoman": return NumFormat.UPPER_ROMAN;
                case "bullet": return NumFormat.BULLET;
                case "none": return NumFormat.NONE;
                case "decimalZero": return NumFormat.DECIMAL_ZERO;
                case "ordinal": return NumFormat.ORDINAL;
                case "cardinalText": return NumFormat.CARDINAL_TEXT;
                default: return NumFormat.DECIMAL;
            }
        }

        private void load_settings() throws Error {
            string? part = part_by_type("/settings");
            if (part == null || !zip.has(part)) return;
            var ctx = open_part(part);
            Xml.Node* root = ctx.xdoc->get_root_element();
            doc.even_odd_headers = X.child(root, "evenAndOddHeaders") != null && X.on(X.child(root, "evenAndOddHeaders"));
            doc.track_changes = X.child(root, "trackRevisions") != null && X.on(X.child(root, "trackRevisions"));
            Xml.Node* dt = X.child(root, "defaultTabStop");
            if (dt != null) doc.default_tab = twip(X.attr(dt, "val"), 36);
            Xml.Node* prot = X.child(root, "documentProtection");
            if (prot != null) {
                string edit = X.val(prot, "edit");
                switch (edit) {
                    case "readOnly": doc.protection.kind = ProtectKind.READ_ONLY; break;
                    case "comments": doc.protection.kind = ProtectKind.COMMENTS; break;
                    case "trackedChanges": doc.protection.kind = ProtectKind.TRACKED; break;
                    case "forms": doc.protection.kind = ProtectKind.FORMS; break;
                    default: break;
                }
                doc.protection.enforced = X.val(prot, "enforcement") == "1" || X.val(prot, "enforcement") == "true" || X.val(prot, "enforcement") == "on";
                doc.protection.algorithm = X.attr(prot, "algorithmName") ?? "SHA-512";
                doc.protection.hash = X.attr(prot, "hashValue") ?? (X.attr(prot, "hash") ?? "");
                doc.protection.salt = X.attr(prot, "saltValue") ?? (X.attr(prot, "salt") ?? "");
                doc.protection.spin = X.attr(prot, "spinCount") != null ? X.ival(prot, "spinCount", 100000) : X.ival(prot, "cryptSpinCount", 100000);
            }
            Xml.Node* fpr = X.child(root, "footnotePr");
            if (fpr != null) {
                Xml.Node* nf = X.child(fpr, "numFmt");
                if (nf != null) doc.footnote_format = num_format(X.val(nf));
            }
            Xml.Node* epr = X.child(root, "endnotePr");
            if (epr != null) {
                Xml.Node* nf = X.child(epr, "numFmt");
                if (nf != null) doc.endnote_format = num_format(X.val(nf));
            }
            Xml.Node* hy = X.child(root, "autoHyphenation");
            doc.hyphenate = hy != null && X.on(hy);
            Xml.Node* vars = X.child(root, "docVars");
            if (vars != null) {
                foreach (var v in X.kids(vars, "docVar")) {
                    string vn = X.val(v, "name");
                    if (vn == "SingularityMergeSource") doc.merge_source = X.val(v, "val");
                    else if (vn.has_prefix("SingularityMacro")) doc.macros.add(X.val(v, "val"));
                    else if (vn == "SingularityBibStyle") doc.bib_style = X.val(v, "val");
                    else doc.variables[vn] = X.val(v, "val");
                }
            }
            Xml.Node* mm = X.child(root, "mailMerge");
            if (mm != null) {
                Xml.Node* ds = X.child(mm, "dataSource");
                if (ds != null) {
                    string rid = X.attr_p(ds, "r", "id") ?? "";
                    if (ctx.targets.has_key(rid)) doc.merge_source = ctx.targets[rid];
                }
            }
            Xml.Node* lang = X.path(root, "themeFontLang");
            if (lang != null) doc.lang = X.val(lang);
            delete ctx.xdoc;
        }

        private void load_notes(string kind, NoteKind nk, Gee.HashMap<string, Note> into) throws Error {
            string? part = part_by_type("/" + kind);
            if (part == null || !zip.has(part)) return;
            var ctx = open_part(part);
            var saved = cur;
            cur = ctx;
            Xml.Node* root = ctx.xdoc->get_root_element();
            foreach (var n in X.kids(root)) {
                string t = X.val(n, "type");
                if (t == "separator" || t == "continuationSeparator" || t == "continuationNotice") continue;
                var note = new Note(nk);
                read_blocks(n, note.blocks);
                strip_note_ref_marks(note);
                into[X.val(n, "id")] = note;
            }
            cur = saved;
            delete ctx.xdoc;
        }

        private void strip_note_ref_marks(Note note) {
            var p = note.blocks.first_paragraph();
            if (p == null) return;
            for (int i = 0; i < p.inlines.size; i++) {
                var f = p.inlines[i] as FieldRun;
                if (f != null && f.code == "\x01NOTEMARK") {
                    p.inlines.remove_at(i);
                    if (i < p.inlines.size) {
                        var t = p.inlines[i] as TextRun;
                        if (t != null && t.text.has_prefix(" ")) t.text = t.text.substring(1);
                    }
                    break;
                }
            }
            p.normalize();
        }

        private void load_comments() throws Error {
            string? ext = part_by_type("/commentsExtended");
            var done = new Gee.HashMap<string, bool>();
            var parents = new Gee.HashMap<string, string>();
            if (ext != null && zip.has(ext)) {
                var ectx = open_part(ext);
                foreach (var c in X.kids(ectx.xdoc->get_root_element(), "commentEx")) {
                    string pid = X.val(c, "paraId");
                    done[pid] = X.val(c, "done") == "1";
                    string? par = X.attr(c, "paraIdParent");
                    if (par != null) parents[pid] = par;
                }
                delete ectx.xdoc;
            }
            string? part = part_by_type("/comments");
            if (part == null || !zip.has(part)) return;
            var ctx = open_part(part);
            var saved = cur;
            cur = ctx;
            var para_to_comment = new Gee.HashMap<string, string>();
            foreach (var c in X.kids(ctx.xdoc->get_root_element(), "comment")) {
                string id = X.val(c, "id");
                var com = new Comment(id, X.val(c, "author"));
                com.initials = X.attr(c, "initials") ?? Comment.make_initials(com.author);
                com.date = X.val(c, "date");
                read_blocks(c, com.blocks);
                string? last_pid = null;
                foreach (var p in X.kids(c, "p")) {
                    string? pid = X.attr_p(p, "w14", "paraId");
                    if (pid != null) last_pid = pid;
                }
                if (last_pid != null) {
                    para_to_comment[last_pid] = id;
                    if (done.has_key(last_pid)) com.done = done[last_pid];
                    comment_para_ids[id] = last_pid;
                }
                doc.comments.add(com);
                doc.bump_id(int.parse(id));
            }
            foreach (var com in doc.comments) {
                string? pid = comment_para_ids[com.id];
                if (pid != null && parents.has_key(pid)) com.parent_id = para_to_comment[parents[pid]];
            }
            cur = saved;
            delete ctx.xdoc;
        }

        private void load_props() {
            try {
                string? core = zip.read_text("docProps/core.xml");
                if (core != null) {
                    consumed.add("docProps/core.xml");
                    Xml.Doc* x = X.parse(core);
                    foreach (var n in X.kids(x->get_root_element())) {
                        string t = X.text(n);
                        switch (n->name) {
                            case "title": doc.meta.title = t; break;
                            case "subject": doc.meta.subject = t; break;
                            case "creator": doc.meta.author = t; break;
                            case "keywords": doc.meta.keywords = t; break;
                            case "description": doc.meta.description = t; break;
                            case "category": doc.meta.category = t; break;
                            case "lastModifiedBy": doc.meta.last_modified_by = t; break;
                            case "created": doc.meta.created = t; break;
                            case "modified": doc.meta.modified = t; break;
                            case "revision": doc.meta.revision = int.parse(t); break;
                            default: break;
                        }
                    }
                    delete x;
                }
                string? app = zip.read_text("docProps/app.xml");
                if (app != null) {
                    consumed.add("docProps/app.xml");
                    Xml.Doc* x = X.parse(app);
                    foreach (var n in X.kids(x->get_root_element())) {
                        if (n->name == "Company") doc.meta.company = X.text(n);
                        else if (n->name == "Manager") doc.meta.manager = X.text(n);
                    }
                    delete x;
                }
                string? custom = zip.read_text("docProps/custom.xml");
                if (custom != null) {
                    consumed.add("docProps/custom.xml");
                    Xml.Doc* x = X.parse(custom);
                    foreach (var n in X.kids(x->get_root_element(), "property")) {
                        string name = X.val(n, "name");
                        foreach (var v in X.kids(n)) {
                            doc.meta.custom[name] = X.text(v);
                            break;
                        }
                    }
                    delete x;
                }
            } catch (Error e) {
            }
        }

        private void load_sources() {
            foreach (string name in zip.names()) {
                if (!name.has_prefix("customXml/item") || !name.has_suffix(".xml") || name.contains("Props")) continue;
                try {
                    string? t = zip.read_text(name);
                    if (t == null || !t.contains("Sources")) continue;
                    Xml.Doc* x = X.parse(t);
                    Xml.Node* root = x->get_root_element();
                    if (root->name != "Sources") {
                        delete x;
                        continue;
                    }
                    string style = X.attr(root, "StyleName") ?? "";
                    if (style.contains("APA")) doc.bib_style = "APA";
                    else if (style.contains("MLA")) doc.bib_style = "MLA";
                    else if (style.contains("Chicago")) doc.bib_style = "Chicago";
                    else if (style.contains("IEEE")) doc.bib_style = "IEEE";
                    else if (style.contains("Harvard")) doc.bib_style = "Harvard";
                    foreach (var s in X.kids(root, "Source")) {
                        var src = new BibSource();
                        foreach (var f in X.kids(s)) {
                            string v = X.text(f);
                            switch (f->name) {
                                case "Tag": src.tag = v; break;
                                case "SourceType": src.kind = v; break;
                                case "Title": src.title = v; break;
                                case "Year": src.year = v; break;
                                case "Publisher": src.publisher = v; break;
                                case "City": src.city = v; break;
                                case "JournalName": src.journal = v; break;
                                case "Volume": src.volume = v; break;
                                case "Issue": src.issue = v; break;
                                case "Pages": src.pages = v; break;
                                case "URL": src.url = v; break;
                                case "Edition": src.edition = v; break;
                                case "DOI": src.doi = v; break;
                                case "Author":
                                    var people = new Gee.ArrayList<Xml.Node*>();
                                    X.descendants(f, "Person", people);
                                    string[] names = {};
                                    foreach (var p in people) {
                                        string last = X.text(X.child(p, "Last"));
                                        string first = X.text(X.child(p, "First"));
                                        names += first != "" ? last + ", " + first : last;
                                    }
                                    if (names.length == 0) {
                                        Xml.Node* corp = X.find_desc(f, "Corporate");
                                        if (corp != null) names += X.text(corp);
                                    }
                                    src.authors = names;
                                    break;
                                default: break;
                            }
                        }
                        doc.sources.add(src);
                    }
                    delete x;
                    consumed.add(name);
                    string num = name.substring(14, name.length - 18);
                    consumed.add("customXml/itemProps" + num + ".xml");
                    consumed.add("customXml/_rels/item" + num + ".xml.rels");
                } catch (Error e) {
                }
            }
        }

        private void load_body() throws Error {
            var ctx = open_part(main_part);
            cur = ctx;
            Xml.Node* root = ctx.xdoc->get_root_element();
            Xml.Node* bg = X.child(root, "background");
            if (bg != null) {
                string c = X.val(bg, "color");
                if (c != "" && c != "auto") doc.page_color = "#" + c.down();
            }
            Xml.Node* body = X.child(root, "body");
            if (body == null) throw new FormatError.INVALID(_("The document has no body."));
            read_blocks(body, doc.body);
            Xml.Node* sect = X.child(body, "sectPr");
            if (sect != null) doc.final_section = read_section(sect);
            if (doc.body.size == 0) doc.body.add(new Paragraph());
            delete ctx.xdoc;
        }

        private void keep_passthrough() {
            doc.passthrough_format = "docx";
            foreach (string name in zip.names()) {
                if (consumed.contains(name) || name.has_suffix("/")) continue;
                if (name.has_prefix("word/media/") || name == "word/styles.xml" || name == "word/numbering.xml"
                    || name == "word/settings.xml" || name == "word/footnotes.xml" || name == "word/endnotes.xml"
                    || name == "word/comments.xml" || name.has_prefix("word/header") || name.has_prefix("word/footer")
                    || name == "word/commentsExtended.xml" || name == "word/commentsIds.xml" || name == "word/commentsExtensible.xml"
                    || name == "word/stylesWithEffects.xml") continue;
                try {
                    var b = zip.read_bytes(name);
                    if (b != null) doc.passthrough[name] = b;
                } catch (Error e) {
                }
            }
        }

        private BlockList target(BlockList fallback) {
            return redirect.size > 0 ? redirect[redirect.size - 1] : fallback;
        }

        private void read_blocks(Xml.Node* parent, BlockList into) {
            for (Xml.Node* c = parent->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                switch (c->name) {
                    case "p":
                        read_paragraph(c, into);
                        break;
                    case "tbl":
                        target(into).add(read_table(c));
                        break;
                    case "sdt":
                        Xml.Node* content = X.child(c, "sdtContent");
                        if (content != null) read_blocks(content, into);
                        break;
                    case "customXml":
                    case "smartTag":
                        read_blocks(c, into);
                        break;
                    case "AlternateContent":
                        Xml.Node* fb = X.child(c, "Fallback");
                        if (fb != null) read_blocks(fb, into);
                        break;
                    case "ins":
                    case "del":
                    case "moveFrom":
                    case "moveTo":
                        read_blocks(c, into);
                        break;
                    default:
                        break;
                }
            }
        }

        private Paragraph cur_para;
        private BlockList cur_list;
        private CharProps? pending_link = null;
        private Revision? pending_rev = null;

        private void read_paragraph(Xml.Node* pn, BlockList into) {
            var p = new Paragraph();
            Xml.Node* ppr = X.child(pn, "pPr");
            if (ppr != null) {
                Xml.Node* ps = X.child(ppr, "pStyle");
                if (ps != null) p.style = X.val(ps);
                p.props = read_ppr(ppr, p);
                Xml.Node* rpr = X.child(ppr, "rPr");
                if (rpr != null) {
                    p.mark_props = read_rpr(rpr);
                    Xml.Node* ins = X.child(rpr, "ins");
                    Xml.Node* del = X.child(rpr, "del");
                    if (ins != null) p.mark_rev = rev_of(ins, RevKind.INSERT);
                    if (del != null) p.mark_rev = rev_of(del, RevKind.DELETE);
                }
                Xml.Node* sect = X.child(ppr, "sectPr");
                if (sect != null) p.section = read_section(sect);
                Xml.Node* pch = X.child(ppr, "pPrChange");
                if (pch != null) {
                    p.props_rev = rev_of(pch, RevKind.FORMAT);
                    Xml.Node* oldp = X.child(pch, "pPr");
                    p.props_old = oldp != null ? read_ppr(oldp, null) : new ParaProps();
                    Xml.Node* ops = oldp != null ? X.child(oldp, "pStyle") : null;
                    p.style_old = ops != null ? X.val(ops) : "Normal";
                }
            }
            cur_para = p;
            cur_list = into;
            target(into).add(p);
            read_inlines(pn, null, null);
            finish_paragraph();
            if (field_tail != null) {
                if (field_tail.is_empty() && field_tail.section == null && field_tail.parent != null) {
                    var host = field_tail.parent;
                    host.remove_at(host.items.index_of(field_tail));
                }
                field_tail = null;
            }
        }

        private Paragraph? field_tail = null;

        private void finish_paragraph() {
            var p = cur_para;
            p.normalize();
            if (p.inlines.size == 1) {
                var eq = p.inlines[0] as EquationRun;
                if (eq != null && eq.omml != null && eq.omml.contains("oMathPara")) eq.display = true;
            }
        }

        private void emit(Inline item) {
            if (fields.size > 0) {
                var f = fields[fields.size - 1];
                if (!f.in_result) return;
                if (f.block == null) {
                    f.result.add(item);
                    return;
                }
            }
            if (pending_link != null && pending_link.link != null) item.props.link = pending_link.link;
            if (pending_rev != null && item.rev == null) item.rev = pending_rev.copy();
            cur_para.inlines.add(item);
        }

        private void read_inlines(Xml.Node* parent, string? link, Revision? rev) {
            for (Xml.Node* c = parent->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                switch (c->name) {
                    case "r":
                        read_run(c, link, rev);
                        break;
                    case "hyperlink":
                        string? url = null;
                        string? rid = X.attr_p(c, "r", "id");
                        if (rid != null && cur.targets.has_key(rid)) url = cur.targets[rid];
                        string? anchor = X.attr(c, "anchor");
                        if (anchor != null) url = (url ?? "") + "#" + anchor;
                        read_inlines(c, url, rev);
                        break;
                    case "ins":
                    case "moveTo":
                        read_inlines(c, link, rev_of(c, RevKind.INSERT));
                        break;
                    case "del":
                    case "moveFrom":
                        read_inlines(c, link, rev_of(c, RevKind.DELETE));
                        break;
                    case "bookmarkStart":
                        string bname = X.val(c, "name");
                        if (bname != "_GoBack") {
                            var m = new Mark(MarkKind.BOOKMARK_START, bname);
                            bookmark_ids[X.val(c, "id")] = bname;
                            add_mark(m);
                        }
                        break;
                    case "bookmarkEnd":
                        string? bn = bookmark_ids[X.val(c, "id")];
                        if (bn != null) add_mark(new Mark(MarkKind.BOOKMARK_END, bn));
                        break;
                    case "commentRangeStart":
                        add_mark(new Mark(MarkKind.COMMENT_START, X.val(c, "id")));
                        break;
                    case "commentRangeEnd":
                        add_mark(new Mark(MarkKind.COMMENT_END, X.val(c, "id")));
                        break;
                    case "fldSimple":
                        string code = X.val(c, "instr").strip();
                        var inner = new StringBuilder();
                        var ts = new Gee.ArrayList<Xml.Node*>();
                        X.descendants(c, "t", ts);
                        foreach (var t in ts) inner.append(X.text(t));
                        Xml.Node* first_r = X.child(c, "r");
                        Xml.Node* frpr = first_r != null ? X.child(first_r, "rPr") : null;
                        if (code.up().has_prefix("HYPERLINK")) {
                            string[] toks = Fields.tokenize(code);
                            string target_url = toks.length > 1 ? toks[1] : "";
                            string? loc = Fields.switch_arg(toks, "\\l");
                            if (loc != null) target_url = target_url + "#" + loc;
                            read_inlines(c, target_url, rev);
                        } else {
                            var f = new FieldRun(code, inner.str);
                            f.dirty = false;
                            if (frpr != null) f.props = read_rpr(frpr);
                            if (rev != null) f.rev = rev.copy();
                            emit(f);
                        }
                        break;
                    case "oMath":
                    case "oMathPara":
                        var eq = new EquationRun("");
                        eq.omml = X.dump(cur.xdoc, c);
                        eq.display = c->name == "oMathPara";
                        eq.mathml = (EquationCodec.omml_to_mathml != null ? EquationCodec.omml_to_mathml(eq.omml, eq.display) : Omml.to_mathml(eq.omml, eq.display)) ?? "";
                        emit(eq);
                        break;
                    case "smartTag":
                    case "customXml":
                        read_inlines(c, link, rev);
                        break;
                    case "sdt":
                        Xml.Node* sc = X.child(c, "sdtContent");
                        if (sc != null) {
                            Xml.Node* spr = X.child(c, "sdtPr");
                            if (spr != null && (X.child(spr, "checkbox") != null || X.child(spr, "dropDownList") != null || X.child(spr, "date") != null || X.child(spr, "text") != null)) {
                                read_form_sdt(spr, sc);
                            } else {
                                read_inlines(sc, link, rev);
                            }
                        }
                        break;
                    case "AlternateContent":
                        Xml.Node* ch = X.child(c, "Choice");
                        Xml.Node* fb = X.child(c, "Fallback");
                        if (ch != null && (X.find_desc(ch, "wsp") != null || X.find_desc(ch, "oMath") != null)) read_inlines(ch, link, rev);
                        else if (fb != null) read_inlines(fb, link, rev);
                        break;
                    default:
                        break;
                }
            }
        }

        private Gee.HashMap<string, string> bookmark_ids = new Gee.HashMap<string, string>();

        private void add_mark(Mark m) {
            if (fields.size > 0) {
                var f = fields[fields.size - 1];
                if (f.block == null) {
                    if (f.in_result) f.result.add(m);
                    return;
                }
            }
            cur_para.inlines.add(m);
        }

        private void read_form_sdt(Xml.Node* spr, Xml.Node* content) {
            FormField ff;
            if (X.child(spr, "checkbox") != null) {
                ff = new FormField(FormKind.CHECKBOX);
                Xml.Node* chk = X.find_desc(X.child(spr, "checkbox"), "checked");
                ff.checked = chk != null && X.val(chk) == "1";
            } else if (X.child(spr, "dropDownList") != null) {
                ff = new FormField(FormKind.DROPDOWN);
                string[] opts = {};
                foreach (var li in X.kids(X.child(spr, "dropDownList"), "listItem")) opts += X.attr(li, "displayText") ?? X.val(li, "value");
                ff.options = opts;
            } else if (X.child(spr, "date") != null) {
                ff = new FormField(FormKind.DATE);
            } else {
                ff = new FormField(FormKind.TEXT);
            }
            Xml.Node* alias = X.child(spr, "alias");
            if (alias != null) ff.name = X.val(alias);
            Xml.Node* tag = X.child(spr, "tag");
            if (tag != null && ff.name == "") ff.name = X.val(tag);
            bool placeholder = X.child(spr, "showingPlcHdr") != null;
            var ts = new Gee.ArrayList<Xml.Node*>();
            X.descendants(content, "t", ts);
            var sb = new StringBuilder();
            foreach (var t in ts) sb.append(X.text(t));
            if (ff.kind != FormKind.CHECKBOX) {
                if (placeholder) ff.placeholder = sb.str;
                else ff.value = sb.str;
            }
            emit(ff);
        }

        private Revision rev_of(Xml.Node* n, RevKind kind) {
            var r = new Revision(kind, X.val(n, "author"), X.val(n, "date"));
            r.id = X.ival(n, "id", 0);
            return r;
        }

        private void read_run(Xml.Node* rn, string? link, Revision? rev) {
            CharProps props = new CharProps();
            Xml.Node* rpr = X.child(rn, "rPr");
            Revision? fmt_rev = null;
            CharProps? fmt_old = null;
            if (rpr != null) {
                props = read_rpr(rpr);
                Xml.Node* ch = X.child(rpr, "rPrChange");
                if (ch != null) {
                    fmt_rev = rev_of(ch, RevKind.FORMAT);
                    Xml.Node* old = X.child(ch, "rPr");
                    fmt_old = old != null ? read_rpr(old) : new CharProps();
                }
            }
            if (link != null) props.link = link;
            var text = new StringBuilder();
            for (Xml.Node* c = rn->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                switch (c->name) {
                    case "t":
                    case "delText":
                        text.append(X.text(c));
                        break;
                    case "instrText":
                    case "delInstrText":
                        if (fields.size > 0 && !fields[fields.size - 1].in_result) fields[fields.size - 1].code += X.text(c);
                        break;
                    case "noBreakHyphen":
                        text.append("\u2011");
                        break;
                    case "softHyphen":
                        text.append("\u00ad");
                        break;
                    case "sym":
                        flush_text(text, props, rev, fmt_rev, fmt_old);
                        string code = X.val(c, "char");
                        int64 cp = 0;
                        int64.try_parse("0x" + code, out cp);
                        uint32 v = (uint32) cp;
                        if (v >= 0xF000) v -= 0xF000;
                        var sp = props.copy();
                        string sym_font = X.val(c, "font");
                        var sb2 = new StringBuilder();
                        sb2.append_unichar(map_symbol(v, sym_font));
                        if (sym_font != "Symbol" && sym_font != "Wingdings") sp.font = sym_font;
                        var tr = new TextRun(sb2.str, sp);
                        tr.rev = rev != null ? rev.copy() : null;
                        emit(tr);
                        break;
                    case "tab":
                        flush_text(text, props, rev, fmt_rev, fmt_old);
                        var tab = new Tab();
                        tab.props = props.copy();
                        tab.rev = rev != null ? rev.copy() : null;
                        emit(tab);
                        break;
                    case "br":
                    case "cr":
                        flush_text(text, props, rev, fmt_rev, fmt_old);
                        string bt = X.val(c, "type");
                        var br = new Break(bt == "page" ? BreakKind.PAGE : (bt == "column" ? BreakKind.COLUMN : BreakKind.LINE));
                        br.props = props.copy();
                        br.rev = rev != null ? rev.copy() : null;
                        emit(br);
                        break;
                    case "fldChar":
                        flush_text(text, props, rev, fmt_rev, fmt_old);
                        field_char(X.val(c, "fldCharType"), props);
                        break;
                    case "footnoteReference":
                    case "endnoteReference":
                        flush_text(text, props, rev, fmt_rev, fmt_old);
                        var map = c->name == "footnoteReference" ? footnotes : endnotes;
                        Note? note = map[X.val(c, "id")];
                        if (note == null) note = new Note(c->name == "footnoteReference" ? NoteKind.FOOTNOTE : NoteKind.ENDNOTE);
                        if (X.attr(c, "customMarkFollows") == "1" || X.attr(c, "customMarkFollows") == "true") note.custom_mark = "";
                        var nr = new NoteRef(note);
                        nr.props = props.copy();
                        nr.rev = rev != null ? rev.copy() : null;
                        emit(nr);
                        break;
                    case "footnoteRef":
                    case "endnoteRef":
                        flush_text(text, props, rev, fmt_rev, fmt_old);
                        emit(new FieldRun("\x01NOTEMARK", ""));
                        break;
                    case "drawing":
                        flush_text(text, props, rev, fmt_rev, fmt_old);
                        read_drawing(c, props, rev);
                        break;
                    case "pict":
                    case "object":
                        flush_text(text, props, rev, fmt_rev, fmt_old);
                        read_vml(c, props, rev);
                        break;
                    case "AlternateContent":
                        flush_text(text, props, rev, fmt_rev, fmt_old);
                        Xml.Node* ch2 = X.child(c, "Choice");
                        Xml.Node* fb2 = X.child(c, "Fallback");
                        Xml.Node* drawing = ch2 != null ? X.find_desc(ch2, "drawing") : null;
                        if (drawing != null) read_drawing(drawing, props, rev);
                        else if (fb2 != null) {
                            Xml.Node* pict = X.find_desc(fb2, "pict");
                            if (pict != null) read_vml(pict, props, rev);
                        }
                        break;
                    default:
                        break;
                }
            }
            flush_text(text, props, rev, fmt_rev, fmt_old);
        }

        private static unichar map_symbol(uint32 v, string font) {
            if (font == "Symbol") {
                if (v >= 0x41 && v <= 0x5A) {
                    unichar[] up = { 0x391, 0x392, 0x3A7, 0x394, 0x395, 0x3A6, 0x393, 0x397, 0x399, 0x3D1, 0x39A, 0x39B, 0x39C, 0x39D, 0x39F, 0x3A0, 0x398, 0x3A1, 0x3A3, 0x3A4, 0x3A5, 0x3C2, 0x3A9, 0x39E, 0x3A8, 0x396 };
                    return up[v - 0x41];
                }
                if (v >= 0x61 && v <= 0x7A) {
                    unichar[] lo = { 0x3B1, 0x3B2, 0x3C7, 0x3B4, 0x3B5, 0x3C6, 0x3B3, 0x3B7, 0x3B9, 0x3D5, 0x3BA, 0x3BB, 0x3BC, 0x3BD, 0x3BF, 0x3C0, 0x3B8, 0x3C1, 0x3C3, 0x3C4, 0x3C5, 0x3D6, 0x3C9, 0x3BE, 0x3C8, 0x3B6 };
                    return lo[v - 0x61];
                }
                if (v == 0xB7) return 0x2022;
                if (v == 0xB4) return 0xD7;
                if (v == 0xB1) return 0xB1;
                if (v == 0xA3) return 0x2264;
                if (v == 0xB3) return 0x2265;
                if (v == 0xB9) return 0x2260;
                if (v == 0xA5) return 0x221E;
                if (v == 0xE5) return 0x2211;
                if (v == 0xD6) return 0x221A;
            }
            if (font == "Wingdings") {
                if (v == 0xFC) return 0x2713;
                if (v == 0xFB) return 0x2717;
                if (v == 0xA7) return 0x25AA;
                if (v == 0x6C) return 0x25CF;
                if (v == 0x4A) return 0x263A;
                if (v == 0xE0) return 0x2192;
            }
            return (unichar) v;
        }

        private void flush_text(StringBuilder text, CharProps props, Revision? rev, Revision? fmt_rev, CharProps? fmt_old) {
            if (text.len == 0) return;
            var tr = new TextRun(text.str, props);
            tr.rev = rev != null ? rev.copy() : null;
            tr.fmt_rev = fmt_rev != null ? fmt_rev.copy() : null;
            tr.fmt_old = fmt_old != null ? fmt_old.copy() : null;
            text.truncate(0);
            emit(tr);
        }

        private static bool is_block_field(string code) {
            string k = code.strip().up();
            return k.has_prefix("TOC") || k.has_prefix("INDEX") || k.has_prefix("BIBLIOGRAPHY");
        }

        private void field_char(string type, CharProps props) {
            if (type == "begin") {
                var f = new FieldState();
                f.props = props.copy();
                fields.add(f);
            } else if (type == "separate") {
                if (fields.size == 0) return;
                var f = fields[fields.size - 1];
                f.in_result = true;
                if (fields.size == 1 && is_block_field(f.code)) {
                    var fb = new FieldBlock(f.code.strip());
                    f.block = fb;
                    var host = cur_list;
                    int idx = host.items.index_of(cur_para);
                    var trailing = cur_para;
                    if (trailing.is_empty()) {
                        if (idx >= 0) host.remove_at(idx);
                        host.insert(idx >= 0 ? idx : host.size, fb);
                    } else {
                        host.insert(idx + 1, fb);
                    }
                    var start = trailing.shell();
                    fb.result.add(start);
                    cur_para = start;
                    redirect.add(fb.result);
                } else if (f.code.strip().up().has_prefix("HYPERLINK")) {
                    string[] toks = Fields.tokenize(f.code);
                    string url = toks.length > 1 && !toks[1].has_prefix("\\") ? toks[1] : "";
                    string? loc = Fields.switch_arg(toks, "\\l");
                    if (loc != null) url = url + "#" + loc;
                    fields.remove_at(fields.size - 1);
                    pending_link = new CharProps();
                    pending_link.link = url;
                    link_depth = fields.size;
                    var marker = new FieldState();
                    marker.code = "\x02LINK";
                    marker.in_result = true;
                    hyperlink_markers.add(marker);
                }
            } else if (type == "end") {
                if (hyperlink_markers.size > 0 && fields.size == link_depth) {
                    hyperlink_markers.remove_at(hyperlink_markers.size - 1);
                    pending_link = null;
                    return;
                }
                if (fields.size == 0) return;
                var f = fields.remove_at(fields.size - 1);
                if (f.block != null) {
                    redirect.remove_at(redirect.size - 1);
                    var fb = f.block;
                    var host = fb.parent;
                    int idx = host != null ? host.items.index_of(fb) : -1;
                    var last = fb.result.size > 0 ? fb.result[fb.result.size - 1] as Paragraph : null;
                    if (last != null && last == cur_para && last.is_empty() && fb.result.size > 1) fb.result.remove_at(fb.result.size - 1);
                    var after = cur_para.shell();
                    if (host != null) host.insert(idx + 1, after);
                    cur_para = after;
                    field_tail = after;
                    cur_list = host ?? cur_list;
                    return;
                }
                string code = f.code.strip();
                if (code.up().has_prefix("HYPERLINK")) {
                    foreach (var i in f.result) emit(i);
                    return;
                }
                var sb = new StringBuilder();
                CharProps? rp = null;
                foreach (var i in f.result) {
                    if (rp == null && i.length > 0) rp = i.props;
                    if (i is TextRun) sb.append(((TextRun) i).text);
                    else if (i is Tab) sb.append_c('\t');
                    else if (i is FieldRun) sb.append(((FieldRun) i).result);
                }
                if (code == "" && sb.len == 0) return;
                if (code.up().has_prefix("FORMCHECKBOX") || code.up().has_prefix("FORMTEXT") || code.up().has_prefix("FORMDROPDOWN")) {
                    var ff = new FormField(code.up().has_prefix("FORMCHECKBOX") ? FormKind.CHECKBOX : (code.up().has_prefix("FORMDROPDOWN") ? FormKind.DROPDOWN : FormKind.TEXT));
                    ff.value = sb.str;
                    ff.props = rp != null ? rp.copy() : f.props;
                    emit(ff);
                    return;
                }
                if (code.up().has_prefix("XE")) {
                    string[] toks = Fields.tokenize(code);
                    var m = new Mark(MarkKind.INDEX_ENTRY, toks.length > 1 ? toks[1] : "");
                    add_mark(m);
                    return;
                }
                var fr = new FieldRun(code, sb.str);
                fr.dirty = false;
                fr.props = rp != null ? rp.copy() : f.props;
                if (fields.size > 0 && fields[fields.size - 1].block == null && !fields[fields.size - 1].in_result) return;
                emit(fr);
            }
        }

        private int link_depth = -1;
        private Gee.ArrayList<FieldState> hyperlink_markers = new Gee.ArrayList<FieldState>();

        private void read_drawing(Xml.Node* dn, CharProps props, Revision? rev) {
            Xml.Node* holder = X.child(dn, "inline");
            bool anchored = false;
            if (holder == null) {
                holder = X.child(dn, "anchor");
                anchored = true;
            }
            if (holder == null) return;
            Xml.Node* ext = X.child(holder, "extent");
            double w = ext != null ? X.dval(ext, "cx", 914400) / 12700.0 : 72;
            double h = ext != null ? X.dval(ext, "cy", 914400) / 12700.0 : 72;
            Xml.Node* pr = X.child(holder, "docPr");
            Xml.Node* gd = X.path(holder, "graphic/graphicData");
            if (gd == null) return;
            string uri = X.val(gd, "uri");
            FloatingInline? obj = null;
            Xml.Node* pic = X.child(gd, "pic");
            Xml.Node* wsp = X.child(gd, "wsp");
            if (pic != null) {
                Xml.Node* blip = X.find_desc(pic, "blip");
                string? rid = blip != null ? X.attr_p(blip, "r", "embed") : null;
                if (rid != null && cur.targets.has_key(rid)) {
                    try {
                        var bytes = zip.read_bytes(cur.targets[rid]);
                        if (bytes != null) {
                            var img = new ImageRun(bytes, ImageRun.sniff(bytes.get_data()));
                            Xml.Node* src = X.find_desc(pic, "srcRect");
                            if (src != null) {
                                img.crop_l = X.dval(src, "l", 0) / 100000.0;
                                img.crop_t = X.dval(src, "t", 0) / 100000.0;
                                img.crop_r = X.dval(src, "r", 0) / 100000.0;
                                img.crop_b = X.dval(src, "b", 0) / 100000.0;
                            }
                            Xml.Node* gs = X.find_desc(blip, "grayscl");
                            img.grayscale = gs != null;
                            Xml.Node* lum = X.find_desc(blip, "lum");
                            if (lum != null) {
                                img.brightness = X.dval(lum, "bright", 0) / 100000.0;
                                img.contrast = X.dval(lum, "contrast", 0) / 100000.0;
                            }
                            obj = img;
                        }
                    } catch (Error e) {
                    }
                }
            } else if (wsp != null) {
                obj = read_wsp(wsp);
            }
            if (obj == null) {
                var op = new OpaqueRun("docx-drawing", X.dump(cur.xdoc, dn), uri.contains("chart") ? _("Chart") : (uri.contains("diagram") ? _("SmartArt graphic") : _("Embedded object")));
                op.width = w;
                op.height = h;
                collect_opaque_parts(dn, op);
                op.props = props.copy();
                op.rev = rev != null ? rev.copy() : null;
                if (uri.contains("chart")) {
                    Xml.Node* cn = null;
                    for (Xml.Node* c = gd->children; c != null; c = c->next) if (c->type == Xml.ElementType.ELEMENT_NODE) cn = c;
                    string? crid = cn != null ? X.attr_p(cn, "r", "id") : null;
                    string? cxml = null;
                    try {
                        if (crid != null && cur.targets.has_key(crid)) cxml = zip.read_text(cur.targets[crid]);
                    } catch (Error e) {
                    }
                    if (cxml != null) {
                        var ch = new ChartRun();
                        ch.chart_xml = cxml;
                        ch.extended = uri.contains("chartex") || uri.contains("2014/chartex");
                        ch.original = op;
                        ch.width = w;
                        ch.height = h;
                        if (pr != null) {
                            ch.alt = X.attr(pr, "descr") ?? "";
                            ch.title = X.attr(pr, "title") ?? "";
                            ch.name = X.attr(pr, "name") ?? "";
                        }
                        if (anchored) read_anchor(holder, ch);
                        ch.props = props.copy();
                        ch.rev = rev != null ? rev.copy() : null;
                        emit(ch);
                        return;
                    }
                }
                emit(op);
                return;
            }
            obj.width = w;
            obj.height = h;
            if (pr != null) {
                obj.alt = X.attr(pr, "descr") ?? "";
                obj.title = X.attr(pr, "title") ?? "";
                obj.name = X.attr(pr, "name") ?? "";
            }
            if (anchored) read_anchor(holder, obj);
            obj.props = props.copy();
            obj.rev = rev != null ? rev.copy() : null;
            emit(obj);
        }

        private void collect_opaque_parts(Xml.Node* n, OpaqueRun op) {
            for (Xml.Attr* a = n->properties; a != null; a = a->next) {
                if (a->ns == null || a->ns->prefix != "r") continue;
                string rid = a->children != null ? a->children->content : "";
                if (!cur.targets.has_key(rid)) continue;
                string target_part = cur.targets[rid];
                op.rels[rid] = cur.types[rid] + "\n" + target_part;
                add_part_tree(target_part, op);
            }
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type == Xml.ElementType.ELEMENT_NODE) collect_opaque_parts(c, op);
            }
        }

        private void add_part_tree(string part, OpaqueRun op) {
            if (op.parts.has_key(part)) return;
            try {
                var b = zip.read_bytes(part);
                if (b == null) return;
                op.parts[part] = b;
                string rp = rels_path(part);
                var rb = zip.read_bytes(rp);
                if (rb != null) {
                    op.parts[rp] = rb;
                    string? rt = zip.read_text(rp);
                    Xml.Doc* x = X.parse(rt);
                    foreach (var r in X.kids(x->get_root_element(), "Relationship")) {
                        if (X.val(r, "TargetMode") == "External") continue;
                        add_part_tree(resolve(part, X.val(r, "Target")), op);
                    }
                    delete x;
                }
            } catch (Error e) {
            }
        }

        private ShapeRun read_wsp(Xml.Node* wsp) {
            var geom = X.find_desc(wsp, "prstGeom");
            string prst = geom != null ? X.val(geom, "prst") : "rect";
            ShapeKind kind = ShapeKind.RECT;
            switch (prst) {
                case "roundRect": kind = ShapeKind.ROUND_RECT; break;
                case "ellipse": kind = ShapeKind.ELLIPSE; break;
                case "line":
                case "straightConnector1": kind = ShapeKind.LINE; break;
                case "rightArrow": kind = ShapeKind.ARROW; break;
                case "triangle": kind = ShapeKind.TRIANGLE; break;
                default: kind = ShapeKind.RECT; break;
            }
            var s = new ShapeRun(kind);
            Xml.Node* sppr = X.child(wsp, "spPr");
            if (sppr != null) {
                Xml.Node* fill = X.child(sppr, "solidFill");
                if (fill != null) s.fill = drawing_color(fill);
                else if (X.child(sppr, "noFill") != null) s.fill = null;
                Xml.Node* ln = X.child(sppr, "ln");
                if (ln != null) {
                    s.stroke_width = X.dval(ln, "w", 12700) / 12700.0;
                    Xml.Node* lf = X.child(ln, "solidFill");
                    if (lf != null) s.stroke = drawing_color(lf);
                    else if (X.child(ln, "noFill") != null) s.stroke = null;
                }
                Xml.Node* xfrm = X.child(sppr, "xfrm");
                if (xfrm != null) s.rotation = X.dval(xfrm, "rot", 0) / 60000.0;
            }
            Xml.Node* txbx = X.child(wsp, "txbx");
            if (txbx != null) {
                Xml.Node* content = X.child(txbx, "txbxContent");
                if (content != null) {
                    var saved_para = cur_para;
                    var saved_list = cur_list;
                    var saved_fields = fields;
                    fields = new Gee.ArrayList<FieldState>();
                    read_blocks(content, s.text);
                    fields = saved_fields;
                    cur_para = saved_para;
                    cur_list = saved_list;
                }
                if (kind == ShapeKind.RECT) s.kind = ShapeKind.TEXT_BOX;
            }
            return s;
        }

        private string? drawing_color(Xml.Node* fill) {
            Xml.Node* srgb = X.child(fill, "srgbClr");
            if (srgb != null) return "#" + X.val(srgb).down();
            Xml.Node* sch = X.child(fill, "schemeClr");
            if (sch != null) {
                string v = X.val(sch);
                string key = v == "tx1" ? "dk1" : (v == "bg1" ? "lt1" : (v == "tx2" ? "dk2" : (v == "bg2" ? "lt2" : v)));
                return theme_colors[key] ?? "#4472c4";
            }
            return "#4472c4";
        }

        private void read_anchor(Xml.Node* a, FloatingInline obj) {
            obj.wrap = Wrap.FRONT;
            if (X.child(a, "wrapSquare") != null) obj.wrap = Wrap.SQUARE;
            else if (X.child(a, "wrapTight") != null || X.child(a, "wrapThrough") != null) obj.wrap = Wrap.TIGHT;
            else if (X.child(a, "wrapTopAndBottom") != null) obj.wrap = Wrap.TOP_BOTTOM;
            else if (X.child(a, "wrapNone") != null) obj.wrap = X.val(a, "behindDoc") == "1" ? Wrap.BEHIND : Wrap.FRONT;
            obj.dist = X.dval(a, "distL", 114300) / 12700.0;
            Xml.Node* ph = X.child(a, "positionH");
            if (ph != null) {
                switch (X.val(ph, "relativeFrom")) {
                    case "page": obj.hrel = HRel.PAGE; break;
                    case "margin": obj.hrel = HRel.MARGIN; break;
                    case "character": obj.hrel = HRel.CHARACTER; break;
                    default: obj.hrel = HRel.COLUMN; break;
                }
                Xml.Node* off = X.child(ph, "posOffset");
                if (off != null) obj.hoff = double.parse(X.text(off)) / 12700.0;
                Xml.Node* al = X.child(ph, "align");
                if (al != null) {
                    string v = X.text(al);
                    obj.halign = v == "center" ? HAlignObj.CENTER : (v == "right" || v == "outside" ? HAlignObj.RIGHT : HAlignObj.LEFT);
                }
            }
            Xml.Node* pv = X.child(a, "positionV");
            if (pv != null) {
                switch (X.val(pv, "relativeFrom")) {
                    case "page": obj.vrel = VRel.PAGE; break;
                    case "margin": obj.vrel = VRel.MARGIN; break;
                    case "line": obj.vrel = VRel.LINE; break;
                    default: obj.vrel = VRel.PARAGRAPH; break;
                }
                Xml.Node* off = X.child(pv, "posOffset");
                if (off != null) obj.voff = double.parse(X.text(off)) / 12700.0;
            }
        }

        private void read_vml(Xml.Node* pict, CharProps props, Revision? rev) {
            var shapes = new Gee.ArrayList<Xml.Node*>();
            X.descendants(pict, "shape", shapes);
            foreach (var shp in shapes) {
                string id = X.attr(shp, "id") ?? "";
                Xml.Node* tp = X.child(shp, "textpath");
                if (id.contains("PowerPlusWaterMarkObject") && tp != null) {
                    var wm = new Watermark();
                    wm.text = X.val(tp, "string");
                    string? col = X.attr(shp, "fillcolor");
                    if (col != null && col.has_prefix("#")) wm.color = col;
                    string style = X.val(tp, "style");
                    int ff = style.index_of("font-family:");
                    if (ff >= 0) {
                        string rest = style.substring(ff + 12);
                        int semi = rest.index_of_char(';');
                        wm.font = (semi >= 0 ? rest.substring(0, semi) : rest).replace("\"", "").replace("&quot;", "").strip();
                    }
                    wm.diagonal = (X.attr(shp, "style") ?? "").contains("rotation:315");
                    doc.watermark = wm;
                    return;
                }
                if (id.contains("WordPictureWatermark")) {
                    Xml.Node* im = X.child(shp, "imagedata");
                    string? rid = im != null ? X.attr_p(im, "r", "id") : null;
                    if (rid != null && cur.targets.has_key(rid)) {
                        try {
                            var wm = new Watermark();
                            wm.image = zip.read_bytes(cur.targets[rid]);
                            if (wm.image != null) {
                                wm.image_mime = ImageRun.sniff(wm.image.get_data());
                                doc.watermark = wm;
                            }
                        } catch (Error e) {
                        }
                    }
                    return;
                }
            }
            Xml.Node* im = X.find_desc(pict, "imagedata");
            if (pict->name == "object") {
                var op = new OpaqueRun("docx-object", X.dump(cur.xdoc, pict), _("Embedded object"));
                collect_opaque_parts(pict, op);
                string? rid = im != null ? X.attr_p(im, "r", "id") : null;
                if (rid != null && cur.targets.has_key(rid)) {
                    try {
                        op.preview = zip.read_bytes(cur.targets[rid]);
                    } catch (Error e) {
                    }
                }
                Xml.Node* shp = X.find_desc(pict, "shape");
                if (shp != null) vml_size(X.val(shp, "style"), out op.width, out op.height);
                op.props = props.copy();
                emit(op);
                return;
            }
            if (im != null) {
                string? rid = X.attr_p(im, "r", "id");
                if (rid != null && cur.targets.has_key(rid)) {
                    try {
                        var b = zip.read_bytes(cur.targets[rid]);
                        if (b != null) {
                            var img = new ImageRun(b, ImageRun.sniff(b.get_data()));
                            Xml.Node* shp = X.find_desc(pict, "shape");
                            double w = 144, h = 144;
                            if (shp != null) vml_size(X.val(shp, "style"), out w, out h);
                            img.width = w;
                            img.height = h;
                            img.props = props.copy();
                            img.rev = rev != null ? rev.copy() : null;
                            emit(img);
                        }
                    } catch (Error e) {
                    }
                }
                return;
            }
            Xml.Node* tb = X.find_desc(pict, "txbxContent");
            if (tb != null) {
                var s = new ShapeRun(ShapeKind.TEXT_BOX);
                Xml.Node* shp = X.find_desc(pict, "shape") ?? X.find_desc(pict, "rect");
                if (shp != null) vml_size(X.val(shp, "style"), out s.width, out s.height);
                var saved_para = cur_para;
                var saved_list = cur_list;
                var saved_fields = fields;
                fields = new Gee.ArrayList<FieldState>();
                read_blocks(tb, s.text);
                fields = saved_fields;
                cur_para = saved_para;
                cur_list = saved_list;
                s.wrap = Wrap.SQUARE;
                s.props = props.copy();
                emit(s);
                return;
            }
            var op = new OpaqueRun("docx-vml", X.dump(cur.xdoc, pict), _("Drawing"));
            collect_opaque_parts(pict, op);
            op.props = props.copy();
            emit(op);
        }

        private static void vml_size(string style, out double w, out double h) {
            w = 144;
            h = 72;
            foreach (string part in style.split(";")) {
                string[] kv = part.split(":");
                if (kv.length != 2) continue;
                string k = kv[0].strip();
                if (k == "width") w = X.length_pt(kv[1].strip(), w);
                else if (k == "height") h = X.length_pt(kv[1].strip(), h);
            }
        }

        private Table read_table(Xml.Node* tn) {
            var t = new Table();
            t.style = null;
            t.margin_l = 5.4;
            t.margin_r = 5.4;
            Xml.Node* tpr = X.child(tn, "tblPr");
            if (tpr != null) {
                Xml.Node* ts = X.child(tpr, "tblStyle");
                if (ts != null) t.style = X.val(ts);
                Xml.Node* tw = X.child(tpr, "tblW");
                if (tw != null) {
                    string type = X.val(tw, "type");
                    if (type == "dxa") t.width = twip(X.attr(tw, "w"), 0);
                    else if (type == "pct") {
                        string wv = X.val(tw, "w");
                        t.width = wv.has_suffix("%") ? double.parse(wv.substring(0, wv.length - 1)) : double.parse(wv) / 50.0;
                        t.width_pct = true;
                    }
                }
                Xml.Node* jc = X.child(tpr, "jc");
                if (jc != null) t.align = align_of(X.val(jc));
                Xml.Node* ind = X.child(tpr, "tblInd");
                if (ind != null) t.indent = twip(X.attr(ind, "w"), 0);
                Xml.Node* bd = X.child(tpr, "tblBorders");
                if (bd != null) {
                    t.border_top = read_border(X.child(bd, "top"));
                    t.border_bottom = read_border(X.child(bd, "bottom"));
                    t.border_left = read_border(X.child(bd, "left") ?? X.child(bd, "start"));
                    t.border_right = read_border(X.child(bd, "right") ?? X.child(bd, "end"));
                    t.border_h = read_border(X.child(bd, "insideH"));
                    t.border_v = read_border(X.child(bd, "insideV"));
                }
                Xml.Node* mar = X.child(tpr, "tblCellMar");
                if (mar != null) {
                    Xml.Node* l = X.child(mar, "left") ?? X.child(mar, "start");
                    Xml.Node* r = X.child(mar, "right") ?? X.child(mar, "end");
                    Xml.Node* tt = X.child(mar, "top");
                    Xml.Node* bb = X.child(mar, "bottom");
                    if (l != null) t.margin_l = twip(X.attr(l, "w"), 5.4);
                    if (r != null) t.margin_r = twip(X.attr(r, "w"), 5.4);
                    if (tt != null) t.margin_t = twip(X.attr(tt, "w"), 0);
                    if (bb != null) t.margin_b = twip(X.attr(bb, "w"), 0);
                }
                Xml.Node* lay = X.child(tpr, "tblLayout");
                t.fixed_layout = lay != null && X.val(lay, "type") == "fixed";
                Xml.Node* look = X.child(tpr, "tblLook");
                if (look != null) {
                    string v = X.val(look);
                    if (X.attr(look, "firstRow") != null) {
                        t.look_first_row = X.val(look, "firstRow") == "1";
                        t.look_last_row = X.val(look, "lastRow") == "1";
                        t.look_first_col = X.val(look, "firstColumn") == "1";
                        t.look_banded_rows = X.val(look, "noHBand") != "1";
                    } else if (v != "") {
                        int64 bits = 0;
                        int64.try_parse("0x" + v, out bits);
                        t.look_first_row = (bits & 0x20) != 0;
                        t.look_last_row = (bits & 0x40) != 0;
                        t.look_first_col = (bits & 0x80) != 0;
                        t.look_banded_rows = (bits & 0x200) == 0;
                    }
                }
                Xml.Node* cap = X.child(tpr, "tblCaption");
                if (cap != null) t.caption = X.val(cap);
                Xml.Node* desc = X.child(tpr, "tblDescription");
                if (desc != null) t.description = X.val(desc);
            }
            if (t.style == null && t.border_top == null) {
                t.style = "PlainTable";
            }
            Xml.Node* grid = X.child(tn, "tblGrid");
            if (grid != null) {
                double[] g = {};
                foreach (var gc in X.kids(grid, "gridCol")) g += twip(X.attr(gc, "w"), 72);
                t.grid = g;
            }
            foreach (var tr in X.kids(tn, "tr")) {
                var row = new TableRow();
                Xml.Node* trpr = X.child(tr, "trPr");
                if (trpr != null) {
                    row.header = X.child(trpr, "tblHeader") != null && X.on(X.child(trpr, "tblHeader"));
                    row.cant_split = X.child(trpr, "cantSplit") != null && X.on(X.child(trpr, "cantSplit"));
                    Xml.Node* th = X.child(trpr, "trHeight");
                    if (th != null) {
                        row.height = twip(X.attr(th, "val"), 0);
                        row.height_exact = X.val(th, "hRule") == "exact";
                    }
                    Xml.Node* ins = X.child(trpr, "ins");
                    Xml.Node* del = X.child(trpr, "del");
                    if (ins != null) row.rev = rev_of(ins, RevKind.INSERT);
                    if (del != null) row.rev = rev_of(del, RevKind.DELETE);
                }
                var cells = new Gee.ArrayList<Xml.Node*>();
                foreach (var ch in X.kids(tr)) {
                    if (ch->name == "tc") cells.add(ch);
                    else if (ch->name == "sdt") {
                        Xml.Node* sc = X.child(ch, "sdtContent");
                        if (sc != null) foreach (var c2 in X.kids(sc, "tc")) cells.add(c2);
                    }
                }
                foreach (var tc in cells) {
                    var cell = new TableCell();
                    Xml.Node* tcpr = X.child(tc, "tcPr");
                    if (tcpr != null) {
                        Xml.Node* w = X.child(tcpr, "tcW");
                        if (w != null && X.val(w, "type") == "dxa") cell.width = twip(X.attr(w, "w"), 0);
                        Xml.Node* gs = X.child(tcpr, "gridSpan");
                        if (gs != null) cell.span = int.max(1, X.ival(gs, "val", 1));
                        Xml.Node* vm = X.child(tcpr, "vMerge");
                        if (vm != null) cell.vmerge = X.val(vm) == "restart" ? VMerge.RESTART : VMerge.CONTINUE;
                        Xml.Node* shd = X.child(tcpr, "shd");
                        if (shd != null) cell.shading = color_of(X.val(shd, "fill"));
                        Xml.Node* va = X.child(tcpr, "vAlign");
                        if (va != null) {
                            string v = X.val(va);
                            cell.valign = v == "center" ? CellVAlign.CENTER : (v == "bottom" ? CellVAlign.BOTTOM : CellVAlign.TOP);
                        }
                        Xml.Node* cb = X.child(tcpr, "tcBorders");
                        if (cb != null) {
                            cell.top = read_border(X.child(cb, "top"));
                            cell.bottom = read_border(X.child(cb, "bottom"));
                            cell.left = read_border(X.child(cb, "left") ?? X.child(cb, "start"));
                            cell.right = read_border(X.child(cb, "right") ?? X.child(cb, "end"));
                        }
                    }
                    var saved_para = cur_para;
                    var saved_list = cur_list;
                    read_blocks(tc, cell.blocks);
                    cur_para = saved_para;
                    cur_list = saved_list;
                    if (cell.blocks.size == 0) cell.blocks.add(new Paragraph());
                    row.cells.add(cell);
                }
                t.rows.add(row);
            }
            if (t.grid.length == 0) {
                int n = t.columns();
                double[] g = new double[n];
                for (int i = 0; i < n; i++) g[i] = 468.0 / int.max(1, n);
                t.grid = g;
            }
            return t;
        }

        private HeaderFooter? read_hf(string rid) {
            if (!cur.targets.has_key(rid)) return null;
            string part = cur.targets[rid];
            if (hf_cache.has_key(part)) return hf_cache[part];
            try {
                var ctx = open_part(part);
                var saved = cur;
                var saved_para = cur_para;
                var saved_list = cur_list;
                var saved_fields = fields;
                fields = new Gee.ArrayList<FieldState>();
                cur = ctx;
                var hf = new HeaderFooter();
                read_blocks(ctx.xdoc->get_root_element(), hf.blocks);
                if (hf.blocks.size == 0) hf.blocks.add(new Paragraph());
                cur = saved;
                cur_para = saved_para;
                cur_list = saved_list;
                fields = saved_fields;
                delete ctx.xdoc;
                hf_cache[part] = hf;
                return hf;
            } catch (Error e) {
                return null;
            }
        }

        private Section read_section(Xml.Node* sp) {
            var s = new Section();
            Xml.Node* sz = X.child(sp, "pgSz");
            if (sz != null) {
                s.page_w = twip(X.attr(sz, "w"), 612);
                s.page_h = twip(X.attr(sz, "h"), 792);
                s.landscape = X.val(sz, "orient") == "landscape";
            }
            Xml.Node* mar = X.child(sp, "pgMar");
            if (mar != null) {
                s.margin_top = twip(X.attr(mar, "top"), 72).abs();
                s.margin_bottom = twip(X.attr(mar, "bottom"), 72).abs();
                s.margin_left = twip(X.attr(mar, "left"), 72);
                s.margin_right = twip(X.attr(mar, "right"), 72);
                s.header_dist = twip(X.attr(mar, "header"), 36);
                s.footer_dist = twip(X.attr(mar, "footer"), 36);
                s.gutter = twip(X.attr(mar, "gutter"), 0);
            }
            Xml.Node* cols = X.child(sp, "cols");
            if (cols != null) {
                s.columns = int.max(1, X.ival(cols, "num", 1));
                s.column_space = twip(X.attr(cols, "space"), 36);
                s.column_sep = X.val(cols, "sep") == "1" || X.val(cols, "sep") == "true";
            }
            Xml.Node* type = X.child(sp, "type");
            if (type != null) {
                switch (X.val(type)) {
                    case "continuous": s.start = SectionStart.CONTINUOUS; break;
                    case "evenPage": s.start = SectionStart.EVEN_PAGE; break;
                    case "oddPage": s.start = SectionStart.ODD_PAGE; break;
                    case "nextColumn": s.start = SectionStart.NEXT_COLUMN; break;
                    default: s.start = SectionStart.NEXT_PAGE; break;
                }
            }
            s.title_page = X.child(sp, "titlePg") != null && X.on(X.child(sp, "titlePg"));
            Xml.Node* pn = X.child(sp, "pgNumType");
            if (pn != null) {
                if (X.attr(pn, "start") != null) s.page_start = X.ival(pn, "start", 1);
                if (X.attr(pn, "fmt") != null) s.page_format = num_format(X.val(pn, "fmt"));
            }
            Xml.Node* ln = X.child(sp, "lnNumType");
            s.line_numbers = ln != null;
            Xml.Node* pb = X.child(sp, "pgBorders");
            if (pb != null) {
                s.page_border_top = read_border(X.child(pb, "top"));
                s.page_border_bottom = read_border(X.child(pb, "bottom"));
                s.page_border_left = read_border(X.child(pb, "left"));
                s.page_border_right = read_border(X.child(pb, "right"));
            }
            foreach (var r in X.kids(sp)) {
                bool header = r->name == "headerReference";
                bool footer = r->name == "footerReference";
                if (!header && !footer) continue;
                string rid = X.attr_p(r, "r", "id") ?? "";
                var hf = read_hf(rid);
                if (hf == null) continue;
                string kind = X.val(r, "type");
                if (header) {
                    if (kind == "first") s.header_first = hf;
                    else if (kind == "even") s.header_even = hf;
                    else s.header_default = hf;
                } else {
                    if (kind == "first") s.footer_first = hf;
                    else if (kind == "even") s.footer_even = hf;
                    else s.footer_default = hf;
                }
            }
            return s;
        }

        public static double twip(string? v, double fallback) {
            if (v == null) return fallback;
            string s = v.strip();
            if (s.has_suffix("pt") || s.has_suffix("in") || s.has_suffix("cm") || s.has_suffix("mm")) return X.length_pt(s, fallback);
            double d;
            if (!double.try_parse(s, out d)) return fallback;
            return d / 20.0;
        }

        public static Align align_of(string v) {
            switch (v) {
                case "center": return Align.CENTER;
                case "right":
                case "end": return Align.RIGHT;
                case "both":
                case "distribute":
                case "justify": return Align.JUSTIFY;
                default: return Align.LEFT;
            }
        }

        private string? color_of(string v) {
            if (v == "" || v == "auto") return null;
            if (v.length == 6) return "#" + v.down();
            return null;
        }

        private Border? read_border(Xml.Node* b) {
            if (b == null) return null;
            string style = X.val(b);
            if (style == "nil" || style == "none") return new Border.with("none", 0, "#000000");
            string col = X.val(b, "color");
            var br = new Border.with(style == "" ? "single" : style, X.dval(b, "sz", 4) / 8.0, col == "" || col == "auto" ? "#000000" : "#" + col.down());
            br.space = X.dval(b, "space", 0);
            return br;
        }

        public ParaProps read_ppr(Xml.Node* ppr, Paragraph? p) {
            var pp = new ParaProps();
            Xml.Node* jc = X.child(ppr, "jc");
            if (jc != null) pp.align = align_of(X.val(jc));
            Xml.Node* ind = X.child(ppr, "ind");
            if (ind != null) {
                string? l = X.attr(ind, "left") ?? X.attr(ind, "start");
                string? r = X.attr(ind, "right") ?? X.attr(ind, "end");
                if (l != null) pp.ind_left = twip(l, 0);
                if (r != null) pp.ind_right = twip(r, 0);
                if (X.attr(ind, "hanging") != null) pp.ind_first = -twip(X.attr(ind, "hanging"), 0);
                else if (X.attr(ind, "firstLine") != null) pp.ind_first = twip(X.attr(ind, "firstLine"), 0);
            }
            Xml.Node* sp = X.child(ppr, "spacing");
            if (sp != null) {
                if (X.attr(sp, "before") != null && X.val(sp, "beforeAutospacing") != "1") pp.space_before = twip(X.attr(sp, "before"), 0);
                if (X.attr(sp, "after") != null && X.val(sp, "afterAutospacing") != "1") pp.space_after = twip(X.attr(sp, "after"), 0);
                if (X.val(sp, "beforeAutospacing") == "1") pp.space_before = 14;
                if (X.val(sp, "afterAutospacing") == "1") pp.space_after = 14;
                string? line = X.attr(sp, "line");
                if (line != null) {
                    string rule = X.val(sp, "lineRule");
                    double lv = double.parse(line);
                    if (rule == "exact") {
                        pp.line_rule = LineRule.EXACT;
                        pp.line = lv / 20.0;
                    } else if (rule == "atLeast") {
                        pp.line_rule = LineRule.AT_LEAST;
                        pp.line = lv / 20.0;
                    } else {
                        pp.line_rule = LineRule.AUTO;
                        pp.line = lv / 240.0;
                    }
                }
            }
            Xml.Node* kn = X.child(ppr, "keepNext");
            if (kn != null) pp.keep_next = Tri.of(X.on(kn));
            Xml.Node* kl = X.child(ppr, "keepLines");
            if (kl != null) pp.keep_lines = Tri.of(X.on(kl));
            Xml.Node* pb = X.child(ppr, "pageBreakBefore");
            if (pb != null) pp.page_break_before = Tri.of(X.on(pb));
            Xml.Node* wc = X.child(ppr, "widowControl");
            if (wc != null) pp.widow = Tri.of(X.on(wc));
            Xml.Node* cs = X.child(ppr, "contextualSpacing");
            if (cs != null) pp.contextual = Tri.of(X.on(cs));
            Xml.Node* ol = X.child(ppr, "outlineLvl");
            if (ol != null) pp.outline = X.ival(ol, "val", 9);
            Xml.Node* shd = X.child(ppr, "shd");
            if (shd != null) pp.shading = color_of(X.val(shd, "fill"));
            Xml.Node* bd = X.child(ppr, "pBdr");
            if (bd != null) {
                pp.border_top = read_border(X.child(bd, "top"));
                pp.border_bottom = read_border(X.child(bd, "bottom"));
                pp.border_left = read_border(X.child(bd, "left"));
                pp.border_right = read_border(X.child(bd, "right"));
            }
            Xml.Node* tabs = X.child(ppr, "tabs");
            if (tabs != null) {
                pp.tabs = new Gee.ArrayList<TabStop>();
                foreach (var t in X.kids(tabs, "tab")) {
                    TabAlign al = TabAlign.LEFT;
                    switch (X.val(t)) {
                        case "center": al = TabAlign.CENTER; break;
                        case "right":
                        case "end": al = TabAlign.RIGHT; break;
                        case "decimal": al = TabAlign.DECIMAL; break;
                        case "bar": al = TabAlign.BAR; break;
                        case "clear": al = TabAlign.CLEAR; break;
                        default: break;
                    }
                    TabLeader ld = TabLeader.NONE;
                    switch (X.val(t, "leader")) {
                        case "dot": ld = TabLeader.DOT; break;
                        case "hyphen": ld = TabLeader.HYPHEN; break;
                        case "underscore": ld = TabLeader.UNDERSCORE; break;
                        default: break;
                    }
                    pp.tabs.add(new TabStop(twip(X.attr(t, "pos"), 0), al, ld));
                }
            }
            Xml.Node* np = X.child(ppr, "numPr");
            if (np != null) {
                Xml.Node* ni = X.child(np, "numId");
                Xml.Node* il = X.child(np, "ilvl");
                if (ni != null) pp.num_id = X.ival(ni, "val", 0);
                if (il != null) pp.num_level = X.ival(il, "val", 0);
                else if (ni != null) pp.num_level = 0;
            }
            Xml.Node* fp = X.child(ppr, "framePr");
            if (fp != null && X.attr(fp, "dropCap") != null) {
                string dc = X.val(fp, "dropCap");
                if (dc == "drop" || dc == "margin") {
                    pp.dropcap_lines = X.ival(fp, "lines", 3);
                    pp.dropcap_margin = dc == "margin";
                }
            }
            return pp;
        }

        public CharProps read_rpr(Xml.Node* rpr) {
            var c = new CharProps();
            for (Xml.Node* n = rpr->children; n != null; n = n->next) {
                if (n->type != Xml.ElementType.ELEMENT_NODE) continue;
                switch (n->name) {
                    case "rStyle": c.style = X.val(n); break;
                    case "rFonts":
                        string? f = X.attr(n, "ascii") ?? X.attr(n, "hAnsi");
                        if (f == null) {
                            string? th = X.attr(n, "asciiTheme") ?? X.attr(n, "hAnsiTheme");
                            if (th != null) f = th.has_prefix("major") ? major_font : minor_font;
                        }
                        if (f != null) c.font = f;
                        break;
                    case "b": c.bold = Tri.of(X.on(n)); break;
                    case "i": c.italic = Tri.of(X.on(n)); break;
                    case "strike": c.strike = Tri.of(X.on(n)); break;
                    case "dstrike": c.dstrike = Tri.of(X.on(n)); break;
                    case "vanish": c.hidden = Tri.of(X.on(n)); break;
                    case "outline": c.outline = Tri.of(X.on(n)); break;
                    case "shadow": c.shadow = Tri.of(X.on(n)); break;
                    case "caps": c.caps = X.on(n) ? Caps.ALL : Caps.NONE; break;
                    case "smallCaps": c.caps = X.on(n) ? Caps.SMALL : Caps.NONE; break;
                    case "u":
                        switch (X.val(n)) {
                            case "none": c.underline = Underline.NONE; break;
                            case "double": c.underline = Underline.DOUBLE; break;
                            case "dotted":
                            case "dottedHeavy": c.underline = Underline.DOTTED; break;
                            case "dash":
                            case "dashedHeavy":
                            case "dashLong": c.underline = Underline.DASHED; break;
                            case "wave":
                            case "wavyHeavy":
                            case "wavyDouble": c.underline = Underline.WAVY; break;
                            case "thick": c.underline = Underline.THICK; break;
                            case "words": c.underline = Underline.WORDS; break;
                            default: c.underline = Underline.SINGLE; break;
                        }
                        break;
                    case "color":
                        string v = X.val(n);
                        if (v != "" && v != "auto" && v.length == 6) c.color = "#" + v.down();
                        else if (X.attr(n, "themeColor") != null) {
                            string tc = X.val(n, "themeColor");
                            string key = tc == "text1" ? "dk1" : (tc == "background1" ? "lt1" : (tc == "text2" ? "dk2" : (tc == "background2" ? "lt2" : tc)));
                            if (theme_colors.has_key(key)) c.color = theme_colors[key];
                        }
                        break;
                    case "highlight": c.highlight = highlight_hex(X.val(n)); break;
                    case "shd":
                        string fill = X.val(n, "fill");
                        if (fill != "" && fill != "auto" && fill.length == 6) c.shading = "#" + fill.down();
                        break;
                    case "sz": c.size = X.dval(n, "val", 22) / 2.0; break;
                    case "vertAlign":
                        string va = X.val(n);
                        c.valign = va == "superscript" ? VAlign.SUPER : (va == "subscript" ? VAlign.SUB : VAlign.BASELINE);
                        break;
                    case "spacing": c.spacing = twip(X.attr(n, "val"), 0); break;
                    case "position": c.position = X.dval(n, "val", 0) / 2.0; break;
                    case "lang":
                        string? l = X.attr(n, "val");
                        if (l != null) c.lang = l;
                        break;
                    default: break;
                }
            }
            return c;
        }

        public static string? highlight_hex(string name) {
            switch (name) {
                case "yellow": return "#ffff00";
                case "green": return "#00ff00";
                case "cyan": return "#00ffff";
                case "magenta": return "#ff00ff";
                case "blue": return "#0000ff";
                case "red": return "#ff0000";
                case "darkBlue": return "#000080";
                case "darkCyan": return "#008080";
                case "darkGreen": return "#008000";
                case "darkMagenta": return "#800080";
                case "darkRed": return "#800000";
                case "darkYellow": return "#808000";
                case "darkGray": return "#808080";
                case "lightGray": return "#c0c0c0";
                case "black": return "#000000";
                case "white": return "#ffffff";
                case "none": return "none";
                default: return null;
            }
        }
    }
}
