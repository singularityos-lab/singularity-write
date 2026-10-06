namespace Write {

    public class RtfReader : Object {
        private string src;
        private int pos = 0;
        private Document doc;
        private Gee.HashMap<int, string> fonts = new Gee.HashMap<int, string>();
        private Gee.HashMap<int, string> font_charsets = new Gee.HashMap<int, string>();
        private Gee.ArrayList<string?> colors = new Gee.ArrayList<string?>();
        private Gee.HashMap<int, string> style_map = new Gee.HashMap<int, string>();
        private Gee.HashMap<int, int> list_map = new Gee.HashMap<int, int>();
        private Gee.HashMap<int, ListDef> list_defs = new Gee.HashMap<int, ListDef>();
        private Gee.ArrayList<string> authors = new Gee.ArrayList<string>();
        private string codepage = "CP1252";
        private int uc = 1;

        private class State {
            public CharProps chr = new CharProps();
            public ParaProps para = new ParaProps();
            public string style = "Normal";
            public string dest = "";
            public bool skip = false;
            public int uc = 1;
            public int font = -1;
            public Revision? rev = null;
            public bool in_table = false;

            public State copy() {
                var s = new State();
                s.chr = chr.copy();
                s.para = para.copy();
                s.style = style;
                s.dest = dest;
                s.skip = skip;
                s.uc = uc;
                s.font = font;
                s.rev = rev;
                s.in_table = in_table;
                return s;
            }
        }

        private Gee.ArrayList<State> stack = new Gee.ArrayList<State>();
        private State st;
        private BlockList target;
        private Paragraph para;
        private StringBuilder text = new StringBuilder();
        private Section section;

        private Table? table = null;
        private TableRow? row = null;
        private TableCell? cell = null;
        private double[] cellx = {};
        private Gee.ArrayList<TableCell> row_defs = new Gee.ArrayList<TableCell>();
        private BlockList? saved_target = null;
        private bool row_header = false;

        private StringBuilder dest_text = new StringBuilder();
        private int dest_depth = -1;
        private string field_inst = "";
        private int field_depth = -1;
        private int fldrslt_depth = -1;
        private int field_para_start = -1;
        private Paragraph? field_para = null;
        private StringBuilder pict_hex = new StringBuilder();
        private string pict_type = "";
        private double pict_w = 0;
        private double pict_h = 0;
        private int pict_depth = -1;
        private int note_depth = -1;
        private Note? note = null;
        private BlockList? note_saved_target = null;
        private Paragraph? note_saved_para = null;
        private int hf_depth = -1;
        private string hf_kind = "";
        private BlockList? hf_saved_target = null;
        private Paragraph? hf_saved_para = null;
        private HeaderFooter? hf = null;
        private int atn_depth = -1;
        private string atn_author = "";
        private Comment? atn = null;
        private int style_depth = -1;
        private int listtable_depth = -1;
        private ListDef? cur_list = null;
        private int cur_level = -1;
        private int cur_list_id = 0;
        private int override_list = 0;
        private int override_ls = 0;

        public static Document load(uint8[] data) throws Error {
            var b = new StringBuilder();
            b.append_len((string) data, data.length);
            if (!b.str.has_prefix("{\\rtf")) throw new FormatError.INVALID(_("The file is not an RTF document."));
            var r = new RtfReader();
            return r.read(b.str);
        }

        public Document read(string s) throws Error {
            src = s;
            doc = new Document();
            doc.styles.ensure_builtins();
            section = new Section();
            section.page_w = 612;
            section.page_h = 792;
            section.margin_left = 90;
            section.margin_right = 90;
            target = doc.body;
            st = new State();
            para = new Paragraph();
            run();
            flush_text();
            if (!para.is_empty() || doc.body.size == 0) commit_para();
            doc.final_section = section;
            return doc;
        }

        private void run() {
            int n = src.length;
            while (pos < n) {
                char c = src[pos];
                if (c == '{') {
                    flush_text();
                    stack.add(st);
                    st = st.copy();
                    pos++;
                } else if (c == '}') {
                    flush_text();
                    end_group();
                    if (stack.size > 0) st = stack.remove_at(stack.size - 1);
                    pos++;
                } else if (c == '\\') {
                    control();
                } else if (c == '\r' || c == '\n') {
                    pos++;
                } else {
                    int start = pos;
                    while (pos < n && src[pos] != '{' && src[pos] != '}' && src[pos] != '\\' && src[pos] != '\r' && src[pos] != '\n') pos++;
                    add_raw(src.substring(start, pos - start));
                }
            }
        }

        private void add_raw(string t) {
            if (st.skip) return;
            if (st.dest == "pict") {
                pict_hex.append(t);
                return;
            }
            if (st.dest == "fonttbl" || st.dest == "colortbl" || st.dest == "stylesheet") {
                string u = to_utf8(t);
                unichar c;
                int i = 0;
                while (u.get_next_char(ref i, out c)) {
                    if (c != ';') {
                        dest_text.append_unichar(c);
                        continue;
                    }
                    table_entry(dest_text.str.strip());
                    dest_text.truncate(0);
                }
                return;
            }
            if (st.dest != "") {
                dest_text.append(to_utf8(t));
                return;
            }
            text.append(to_utf8(t));
        }

        private void table_entry(string name) {
            switch (st.dest) {
                case "fonttbl":
                    if (name != "") fonts[cur_font] = name;
                    break;
                case "colortbl":
                    colors.add(color_set ? "#%02x%02x%02x".printf(color_r, color_g, color_b) : null);
                    color_r = 0;
                    color_g = 0;
                    color_b = 0;
                    color_set = false;
                    break;
                case "stylesheet":
                    if (name == "") break;
                    string id = map_style(name);
                    var s = doc.styles.get(id);
                    if (s == null) {
                        s = new Style(id, name, cur_style_char ? StyleType.CHARACTER : StyleType.PARAGRAPH);
                        s.custom = true;
                        s.based_on = cur_style_char ? null : "Normal";
                        s.para = st.para.copy();
                        s.chr = st.chr.copy();
                        doc.styles.add(s);
                    }
                    style_map[cur_style_num] = id;
                    cur_style_num = 0;
                    cur_style_char = false;
                    break;
                default:
                    break;
            }
        }

        private string to_utf8(string t) {
            if (t.validate()) return t;
            try {
                return convert(t, t.length, "UTF-8", codepage);
            } catch (Error e) {
                return t.make_valid();
            }
        }

        private void add_char(unichar u) {
            if (st.skip) return;
            if (st.dest == "pict") return;
            if (st.dest != "") {
                dest_text.append_unichar(u);
                return;
            }
            text.append_unichar(u);
        }

        private void control() {
            pos++;
            if (pos >= src.length) return;
            char c = src[pos];
            if (!c.isalpha()) {
                pos++;
                switch (c) {
                    case '\'':
                        if (pos + 2 <= src.length) {
                            string hex = src.substring(pos, 2);
                            pos += 2;
                            uint8 b = (uint8) long.parse("0x" + hex, 16);
                            if (st.skip) return;
                            uint8[] one = { b, 0 };
                            string s1 = (string) one;
                            try {
                                string u = convert(s1, 1, "UTF-8", codepage);
                                if (st.dest != "") dest_text.append(u);
                                else text.append(u);
                            } catch (Error e) {
                            }
                        }
                        break;
                    case '~': add_char(0xA0); break;
                    case '_': add_char(0x2011); break;
                    case '-': add_char(0xAD); break;
                    case '*':
                        st.skip = st.skip || false;
                        star = true;
                        break;
                    case '\\':
                    case '{':
                    case '}':
                        add_char(c);
                        break;
                    case '\n':
                    case '\r':
                        do_word("par", false, 0);
                        break;
                    default: break;
                }
                return;
            }
            int start = pos;
            while (pos < src.length && src[pos].isalpha()) pos++;
            string word = src.substring(start, pos - start);
            bool has_param = false;
            int param = 0;
            if (pos < src.length && (src[pos] == '-' || src[pos].isdigit())) {
                int ps = pos;
                pos++;
                while (pos < src.length && src[pos].isdigit()) pos++;
                param = int.parse(src.substring(ps, pos - ps));
                has_param = true;
            }
            if (pos < src.length && src[pos] == ' ') pos++;
            do_word(word, has_param, param);
            star = false;
        }

        private bool star = false;

        private void set_dest(string d) {
            flush_text();
            st.dest = d;
            dest_text.truncate(0);
            dest_depth = stack.size;
        }

        private void do_word(string w, bool hp, int p) {
            if (st.skip && w != "bin") return;
            switch (w) {
                case "ansicpg": codepage = "CP%d".printf(p); return;
                case "mac": codepage = "MACINTOSH"; return;
                case "uc": st.uc = p; return;
                case "u":
                    int cp = p < 0 ? p + 65536 : p;
                    add_char((unichar) cp);
                    skip_fallback(st.uc);
                    return;
                case "fonttbl": set_dest("fonttbl"); return;
                case "colortbl": set_dest("colortbl"); color_r = 0; color_g = 0; color_b = 0; color_set = false; return;
                case "stylesheet": style_depth = stack.size; set_dest("stylesheet"); return;
                case "info": set_dest("info"); return;
                case "title":
                case "author":
                case "subject":
                case "keywords":
                case "doccomm":
                case "operator":
                case "company":
                case "category":
                    set_dest(w);
                    return;
                case "listtable": listtable_depth = stack.size; set_dest("listtable"); return;
                case "listoverridetable": set_dest("listoverridetable"); return;
                case "revtbl": set_dest("revtbl"); return;
                case "pict":
                    set_dest("pict");
                    pict_hex.truncate(0);
                    pict_type = "";
                    pict_w = 0;
                    pict_h = 0;
                    pict_depth = stack.size;
                    return;
                case "pngblip": pict_type = "image/png"; return;
                case "jpegblip": pict_type = "image/jpeg"; return;
                case "emfblip":
                case "wmetafile":
                case "macpict": pict_type = "unsupported"; return;
                case "picwgoal": pict_w = p / 20.0; return;
                case "pichgoal": pict_h = p / 20.0; return;
                case "picscalex": if (pict_w > 0) pict_w = pict_w * p / 100.0; return;
                case "picscaley": if (pict_h > 0) pict_h = pict_h * p / 100.0; return;
                case "fldinst": set_dest("fldinst"); return;
                case "fldrslt":
                    if (st.dest == "fldinst") field_inst = dest_text.str.strip();
                    st.dest = "";
                    fldrslt_depth = stack.size;
                    flush_text();
                    string fk = field_inst.strip().up();
                    if (field_block == null && (fk.has_prefix("TOC") || fk.has_prefix("INDEX") || fk.has_prefix("BIBLIOGRAPHY"))) {
                        if (!para.is_empty()) commit_para();
                        field_block = new FieldBlock(field_inst.strip());
                        target.add(field_block);
                        block_saved_target = target;
                        target = field_block.result;
                        field_para = null;
                        return;
                    }
                    field_para = para;
                    field_para_start = para.inlines.size;
                    return;
                case "field":
                    field_depth = stack.size;
                    field_inst = "";
                    return;
                case "footnote":
                    flush_text();
                    note_depth = stack.size;
                    note = new Note(endnote_flag ? NoteKind.ENDNOTE : NoteKind.FOOTNOTE);
                    endnote_flag = false;
                    note_saved_target = target;
                    note_saved_para = para;
                    target = note.blocks;
                    para = new Paragraph(note.kind == NoteKind.FOOTNOTE ? "FootnoteText" : "EndnoteText");
                    st.para = new ParaProps();
                    st.chr = new CharProps();
                    return;
                case "ftnalt": endnote_flag = true; if (note != null) note.kind = NoteKind.ENDNOTE; return;
                case "chftn":
                    return;
                case "header":
                case "footer":
                case "headerl":
                case "headerr":
                case "headerf":
                case "footerl":
                case "footerr":
                case "footerf":
                    flush_text();
                    hf_depth = stack.size;
                    hf_kind = w;
                    hf = new HeaderFooter();
                    hf_saved_target = target;
                    hf_saved_para = para;
                    target = hf.blocks;
                    para = new Paragraph(w.has_prefix("header") ? "Header" : "Footer");
                    return;
                case "atnid":
                case "atnauthor":
                case "atndate":
                case "atnicn":
                case "atnref":
                case "atntime":
                    set_dest(w);
                    return;
                case "annotation":
                    flush_text();
                    atn_depth = stack.size;
                    atn = new Comment(doc.next_id().to_string(), atn_author != "" ? atn_author : _("Unknown"));
                    note_saved_target = target;
                    note_saved_para = para;
                    target = atn.blocks;
                    para = new Paragraph("CommentText");
                    return;
                case "bkmkstart": set_dest("bkmkstart"); return;
                case "bkmkend": set_dest("bkmkend"); return;
                case "list":
                    if (st.dest == "listtable") {
                        cur_list = new ListDef(doc.numbering.defs.size);
                        cur_level = -1;
                    }
                    return;
                case "listlevel":
                    cur_level++;
                    return;
                case "levelnfc":
                    if (cur_list != null && cur_level >= 0 && cur_level < 9) cur_list.levels[cur_level].format = nfc(p);
                    return;
                case "levelstartat":
                    if (cur_list != null && cur_level >= 0 && cur_level < 9) cur_list.levels[cur_level].start = p;
                    return;
                case "listid":
                    if (st.dest == "listtable" && cur_list != null) {
                        cur_list_id = p;
                        list_defs[p] = cur_list;
                        if (!doc.numbering.defs.contains(cur_list)) doc.numbering.defs.add(cur_list);
                    } else if (st.dest == "listoverridetable") {
                        override_list = p;
                    }
                    return;
                case "ls":
                    if (st.dest == "listoverridetable") {
                        override_ls = p;
                        if (list_defs.has_key(override_list)) {
                            var d = list_defs[override_list];
                            list_map[p] = doc.numbering.add_instance(d);
                        }
                    } else {
                        st.para.num_id = list_map.has_key(p) ? list_map[p] : ensure_default_list(p);
                        if (st.para.num_level < 0) st.para.num_level = 0;
                    }
                    return;
                case "ilvl": st.para.num_level = p; return;
                case "pntext":
                case "listtext":
                    st.skip = true;
                    return;
                case "par":
                    end_paragraph();
                    return;
                case "line": flush_text(); para.inlines.add(inl(new Break(BreakKind.LINE))); return;
                case "page": flush_text(); para.inlines.add(inl(new Break(BreakKind.PAGE))); return;
                case "column": flush_text(); para.inlines.add(inl(new Break(BreakKind.COLUMN))); return;
                case "tab": flush_text(); para.inlines.add(inl(new Tab())); return;
                case "emdash": add_char(0x2014); return;
                case "endash": add_char(0x2013); return;
                case "bullet": add_char(0x2022); return;
                case "lquote": add_char(0x2018); return;
                case "rquote": add_char(0x2019); return;
                case "ldblquote": add_char(0x201C); return;
                case "rdblquote": add_char(0x201D); return;
                case "emspace": add_char(0x2003); return;
                case "enspace": add_char(0x2002); return;
                case "sect":
                    end_paragraph();
                    var last = doc.body.last_paragraph();
                    if (last != null && last.parent == doc.body) {
                        last.section = section;
                        section = section.copy();
                        section.header_default = null;
                        section.footer_default = null;
                        section.start = SectionStart.NEXT_PAGE;
                        section.columns = 1;
                    }
                    return;
                case "sectd": return;
                case "sbknone": section.start = SectionStart.CONTINUOUS; return;
                case "sbkodd": section.start = SectionStart.ODD_PAGE; return;
                case "sbkeven": section.start = SectionStart.EVEN_PAGE; return;
                case "cols": section.columns = int.max(1, p); return;
                case "colsx": section.column_space = p / 20.0; return;
                case "linebetcol": section.column_sep = true; return;
                case "paperw": section.page_w = p / 20.0; doc_page_w = section.page_w; return;
                case "paperh": section.page_h = p / 20.0; return;
                case "pgwsxn": section.page_w = p / 20.0; return;
                case "pghsxn": section.page_h = p / 20.0; return;
                case "margl":
                case "marglsxn": section.margin_left = p / 20.0; return;
                case "margr":
                case "margrsxn": section.margin_right = p / 20.0; return;
                case "margt":
                case "margtsxn": section.margin_top = p / 20.0; return;
                case "margb":
                case "margbsxn": section.margin_bottom = p / 20.0; return;
                case "headery": section.header_dist = p / 20.0; return;
                case "footery": section.footer_dist = p / 20.0; return;
                case "landscape":
                case "lndscpsxn": section.landscape = true; return;
                case "titlepg": section.title_page = true; return;
                case "facingp": doc.even_odd_headers = true; return;
                case "pgnstarts": section.page_start = p; return;
                case "pgnlcrm": section.page_format = NumFormat.LOWER_ROMAN; return;
                case "pgnucrm": section.page_format = NumFormat.UPPER_ROMAN; return;
                case "revisions": doc.track_changes = true; return;
                case "pard":
                    st.para = new ParaProps();
                    st.style = "Normal";
                    st.in_table = false;
                    return;
                case "plain": st.chr = new CharProps(); return;
                case "s":
                    if (st.dest == "stylesheet") {
                        cur_style_num = p;
                        cur_style_char = false;
                    } else {
                        st.style = style_map.has_key(p) ? style_map[p] : "Normal";
                    }
                    return;
                case "cs":
                    if (st.dest == "stylesheet") {
                        cur_style_num = p;
                        cur_style_char = true;
                    }
                    return;
                case "outlinelevel": st.para.outline = p; return;
                case "ql": st.para.align = Align.LEFT; return;
                case "qc": st.para.align = Align.CENTER; return;
                case "qr": st.para.align = Align.RIGHT; return;
                case "qj": st.para.align = Align.JUSTIFY; return;
                case "li": st.para.ind_left = p / 20.0; return;
                case "ri": st.para.ind_right = p / 20.0; return;
                case "fi": st.para.ind_first = p / 20.0; return;
                case "sb": st.para.space_before = p / 20.0; return;
                case "sa": st.para.space_after = p / 20.0; return;
                case "sl":
                    if (p == 0) return;
                    st.para.line = p.abs() / 20.0;
                    st.para.line_rule = p < 0 ? LineRule.EXACT : LineRule.AT_LEAST;
                    return;
                case "slmult":
                    if (p == 1 && !st.para.line.is_nan()) {
                        st.para.line = st.para.line / 12.0;
                        st.para.line_rule = LineRule.AUTO;
                    }
                    return;
                case "keepn": st.para.keep_next = Tri.ON; return;
                case "keep": st.para.keep_lines = Tri.ON; return;
                case "pagebb": st.para.page_break_before = Tri.ON; return;
                case "widctlpar": st.para.widow = Tri.ON; return;
                case "nowidctlpar": st.para.widow = Tri.OFF; return;
                case "tx":
                    if (st.para.tabs == null) st.para.tabs = new Gee.ArrayList<TabStop>();
                    st.para.tabs.add(new TabStop(p / 20.0, pending_tab_align, pending_tab_leader));
                    pending_tab_align = TabAlign.LEFT;
                    pending_tab_leader = TabLeader.NONE;
                    return;
                case "tqc": pending_tab_align = TabAlign.CENTER; return;
                case "tqr": pending_tab_align = TabAlign.RIGHT; return;
                case "tqdec": pending_tab_align = TabAlign.DECIMAL; return;
                case "tldot": pending_tab_leader = TabLeader.DOT; return;
                case "tlhyph": pending_tab_leader = TabLeader.HYPHEN; return;
                case "tlul": pending_tab_leader = TabLeader.UNDERSCORE; return;
                case "cbpat": case "shading":
                    return;
                case "b": st.chr.bold = Tri.of(!hp || p != 0); return;
                case "i": st.chr.italic = Tri.of(!hp || p != 0); return;
                case "ul": st.chr.underline = !hp || p != 0 ? Underline.SINGLE : Underline.NONE; return;
                case "uldb": st.chr.underline = Underline.DOUBLE; return;
                case "uld": st.chr.underline = Underline.DOTTED; return;
                case "uldash": st.chr.underline = Underline.DASHED; return;
                case "ulwave": st.chr.underline = Underline.WAVY; return;
                case "ulth": st.chr.underline = Underline.THICK; return;
                case "ulw": st.chr.underline = Underline.WORDS; return;
                case "ulnone": st.chr.underline = Underline.NONE; return;
                case "strike": st.chr.strike = Tri.of(!hp || p != 0); return;
                case "striked": st.chr.dstrike = Tri.of(!hp || p != 0); return;
                case "caps": st.chr.caps = !hp || p != 0 ? Caps.ALL : Caps.NONE; return;
                case "scaps": st.chr.caps = !hp || p != 0 ? Caps.SMALL : Caps.NONE; return;
                case "v": st.chr.hidden = Tri.of(!hp || p != 0); return;
                case "outl": st.chr.outline = Tri.of(!hp || p != 0); return;
                case "shad": st.chr.shadow = Tri.of(!hp || p != 0); return;
                case "super": st.chr.valign = VAlign.SUPER; return;
                case "sub": st.chr.valign = VAlign.SUB; return;
                case "nosupersub": st.chr.valign = VAlign.BASELINE; return;
                case "fs": st.chr.size = p / 2.0; return;
                case "expndtw": st.chr.spacing = p / 20.0; return;
                case "f":
                    if (st.dest == "fonttbl") {
                        cur_font = p;
                    } else {
                        st.font = p;
                        st.chr.font = fonts[p];
                    }
                    return;
                case "fcharset":
                    if (st.dest == "fonttbl") font_charsets[cur_font] = p.to_string();
                    return;
                case "cf": st.chr.color = p > 0 && p < colors.size ? colors[p] : null; return;
                case "highlight": st.chr.highlight = p > 0 && p < colors.size ? colors[p] : null; return;
                case "chcbpat":
                case "cb": st.chr.shading = p > 0 && p < colors.size ? colors[p] : null; return;
                case "lang": return;
                case "red": if (st.dest == "colortbl") { color_r = p; color_set = true; } return;
                case "green": if (st.dest == "colortbl") { color_g = p; color_set = true; } return;
                case "blue": if (st.dest == "colortbl") { color_b = p; color_set = true; } return;
                case "revauth": st.rev = rev_for(p, st.rev != null ? st.rev.kind : RevKind.INSERT); return;
                case "revised": st.rev = rev_for(rev_author, RevKind.INSERT); return;
                case "deleted": st.rev = rev_for(rev_author, RevKind.DELETE); return;
                case "revauthdel": rev_author = p; if (st.rev != null && st.rev.kind == RevKind.DELETE) st.rev = rev_for(p, RevKind.DELETE); return;
                case "trowd":
                    start_row_defs();
                    return;
                case "trhdr": row_header = true; return;
                case "clmgf": next_cell().span = -1; return;
                case "clmrg": next_cell().span = -2; return;
                case "clvmgf": next_cell().vmerge = VMerge.RESTART; return;
                case "clvmrg": next_cell().vmerge = VMerge.CONTINUE; return;
                case "clcbpat": next_cell().shading = p > 0 && p < colors.size ? colors[p] : null; return;
                case "clvertalc": next_cell().valign = CellVAlign.CENTER; return;
                case "clvertalb": next_cell().valign = CellVAlign.BOTTOM; return;
                case "cellx":
                    var cd = next_cell();
                    cd.width = p / 20.0;
                    cellx += p / 20.0;
                    pending_cell = null;
                    return;
                case "intbl": st.in_table = true; return;
                case "cell":
                    end_cell();
                    return;
                case "row":
                    end_row();
                    return;
                case "bin":
                    if (hp && p > 0) pos += p;
                    return;
                default:
                    if (star && !known_dest(w)) {
                        flush_text();
                        st.skip = true;
                    }
                    return;
            }
        }

        private bool endnote_flag = false;
        private double doc_page_w = 612;
        private int cur_font = 0;
        private int cur_style_num = 0;
        private bool cur_style_char = false;
        private TabAlign pending_tab_align = TabAlign.LEFT;
        private TabLeader pending_tab_leader = TabLeader.NONE;
        private int color_r = 0;
        private int color_g = 0;
        private int color_b = 0;
        private bool color_set = false;
        private int rev_author = 0;
        private TableCell? pending_cell = null;

        private static bool known_dest(string w) {
            switch (w) {
                case "fldinst":
                case "bkmkstart":
                case "bkmkend":
                case "atnid":
                case "atnauthor":
                case "atndate":
                case "annotation":
                case "revtbl":
                case "listtable":
                case "listoverridetable":
                case "footnote":
                    return true;
                default:
                    return false;
            }
        }

        private int ensure_default_list(int ls) {
            var d = doc.numbering.make_bullets();
            int id = doc.numbering.add_instance(d);
            list_map[ls] = id;
            return id;
        }

        private static NumFormat nfc(int v) {
            switch (v) {
                case 1: return NumFormat.UPPER_ROMAN;
                case 2: return NumFormat.LOWER_ROMAN;
                case 3: return NumFormat.UPPER_LETTER;
                case 4: return NumFormat.LOWER_LETTER;
                case 5: return NumFormat.ORDINAL;
                case 23: return NumFormat.BULLET;
                case 255: return NumFormat.NONE;
                default: return NumFormat.DECIMAL;
            }
        }

        private Revision rev_for(int author, RevKind kind) {
            string name = author >= 0 && author < authors.size ? authors[author] : _("Unknown");
            return new Revision(kind, name, "");
        }

        private void skip_fallback(int count) {
            int n = count;
            while (n > 0 && pos < src.length) {
                if (src[pos] == '\\') {
                    if (pos + 1 < src.length && src[pos + 1] == '\'') {
                        pos += 4;
                    } else {
                        pos++;
                        while (pos < src.length && src[pos].isalpha()) pos++;
                        while (pos < src.length && (src[pos] == '-' || src[pos].isdigit())) pos++;
                        if (pos < src.length && src[pos] == ' ') pos++;
                    }
                } else if (src[pos] == '{' || src[pos] == '}') {
                    break;
                } else {
                    pos++;
                }
                n--;
            }
        }

        private Inline inl(Inline i) {
            i.props = st.chr.copy();
            if (st.rev != null) i.rev = st.rev.copy();
            return i;
        }

        private void flush_text() {
            if (text.len == 0) return;
            var r = new TextRun(text.str, st.chr);
            if (st.rev != null) r.rev = st.rev.copy();
            para.inlines.add(r);
            text.truncate(0);
        }

        private void end_paragraph() {
            flush_text();
            if (st.in_table && table != null && cell == null) begin_cell();
            commit_para();
        }

        private void commit_para() {
            para.props = st.para.copy();
            para.style = para.style != "Normal" && para.style != "" && st.style == "Normal" ? para.style : st.style;
            if (para.style == "Normal" && target != doc.body && note != null && target == note.blocks) para.style = note.kind == NoteKind.FOOTNOTE ? "FootnoteText" : "EndnoteText";
            para.normalize();
            if (st.in_table) {
                if (cell == null) begin_cell();
                cell.blocks.add(para);
            } else {
                if (table != null && target == doc.body) finish_table();
                target.add(para);
            }
            string next_style = target == doc.body || cell != null ? "Normal" : para.style;
            para = new Paragraph(next_style);
        }

        private TableCell next_cell() {
            if (pending_cell == null) {
                pending_cell = new TableCell();
                row_defs.add(pending_cell);
            }
            return pending_cell;
        }

        private void start_row_defs() {
            row_defs.clear();
            cellx = {};
            pending_cell = null;
            row_header = false;
        }

        private void begin_cell() {
            if (table == null) {
                table = new Table();
                table.style = "TableGrid";
                var b = new Border.with("single", 0.5, "#000000");
                table.border_top = b;
                table.border_bottom = b.copy();
                table.border_left = b.copy();
                table.border_right = b.copy();
                table.border_h = b.copy();
                table.border_v = b.copy();
            }
            if (row == null) {
                row = new TableRow();
                row.header = row_header;
            }
            int idx = row.cells.size;
            cell = new TableCell();
            if (idx < row_defs.size) {
                var d = row_defs[idx];
                cell.vmerge = d.vmerge;
                cell.shading = d.shading;
                cell.valign = d.valign;
                cell.span = d.span;
            }
        }

        private void end_cell() {
            flush_text();
            if (cell == null) begin_cell();
            if (!para.is_empty() || cell.blocks.size == 0) {
                para.props = st.para.copy();
                para.style = st.style;
                para.normalize();
                cell.blocks.add(para);
            }
            para = new Paragraph();
            row.cells.add(cell);
            cell = null;
        }

        private void end_row() {
            flush_text();
            if (row == null) return;
            var merged = new TableRow();
            merged.header = row.header;
            foreach (var c in row.cells) {
                if (c.span == -2 && merged.cells.size > 0) {
                    merged.cells[merged.cells.size - 1].span++;
                    continue;
                }
                if (c.span < 1) c.span = 1;
                merged.cells.add(c);
            }
            table.rows.add(merged);
            double[] widths = {};
            double prev = 0;
            foreach (double x in cellx) {
                widths += double.max(6, x - prev);
                prev = x;
            }
            if (widths.length > table.grid.length) table.grid = widths;
            row = null;
            st.in_table = false;
        }

        private void finish_table() {
            if (table == null) return;
            if (row != null && row.cells.size > 0) end_row();
            if (table.grid.length == 0) {
                int n = table.columns();
                double[] g = new double[n];
                for (int i = 0; i < n; i++) g[i] = 432.0 / int.max(1, n);
                table.grid = g;
            }
            if (table.rows.size > 0) doc.body.add(table);
            table = null;
            row = null;
        }

        private void end_group() {
            int depth = stack.size;
            if (st.dest != "" && depth == dest_depth) finish_dest();
            if (depth == pict_depth) {
                pict_depth = -1;
                finish_pict();
            }
            if (depth == fldrslt_depth) {
                fldrslt_depth = -1;
                finish_field_result();
            }
            if (depth == field_depth) {
                field_depth = -1;
                if (field_para == null && field_inst != "" && field_block == null) {
                    var f = new FieldRun(field_inst, "");
                    para.inlines.add(inl(f));
                }
                field_para = null;
                field_inst = "";
            }
            if (depth == note_depth) {
                note_depth = -1;
                if (!para.is_empty()) commit_para();
                target = note_saved_target;
                para = note_saved_para;
                var r = new NoteRef(note);
                r.props = new CharProps();
                para.inlines.add(r);
                note = null;
            }
            if (depth == hf_depth) {
                hf_depth = -1;
                if (!para.is_empty() || hf.blocks.size == 0) commit_para();
                target = hf_saved_target;
                para = hf_saved_para;
                switch (hf_kind) {
                    case "header":
                    case "headerr": section.header_default = hf; break;
                    case "headerl": section.header_even = hf; break;
                    case "headerf": section.header_first = hf; break;
                    case "footer":
                    case "footerr": section.footer_default = hf; break;
                    case "footerl": section.footer_even = hf; break;
                    case "footerf": section.footer_first = hf; break;
                    default: break;
                }
                hf = null;
            }
            if (depth == atn_depth) {
                atn_depth = -1;
                if (!para.is_empty()) commit_para();
                target = note_saved_target;
                para = note_saved_para;
                doc.comments.add(atn);
                para.inlines.add(new Mark(MarkKind.COMMENT_START, atn.id));
                para.inlines.add(new Mark(MarkKind.COMMENT_END, atn.id));
                atn = null;
                atn_author = "";
            }
            if (depth == style_depth) style_depth = -1;
            if (depth == listtable_depth) listtable_depth = -1;
        }

        private void finish_dest() {
            string t = dest_text.str;
            string d = st.dest;
            switch (d) {
                case "fonttbl":
                case "colortbl":
                case "stylesheet":
                    break;
                case "title": doc.meta.title = t; break;
                case "author": doc.meta.author = t; break;
                case "subject": doc.meta.subject = t; break;
                case "keywords": doc.meta.keywords = t; break;
                case "doccomm": doc.meta.description = t; break;
                case "operator": doc.meta.last_modified_by = t; break;
                case "company": doc.meta.company = t; break;
                case "category": doc.meta.category = t; break;
                case "revtbl":
                    foreach (string a in t.split(";")) authors.add(a.strip());
                    break;
                case "fldinst":
                    field_inst = t.strip();
                    break;
                case "atnauthor": atn_author = t.strip(); break;
                case "bkmkstart":
                    flush_text();
                    para.inlines.add(new Mark(MarkKind.BOOKMARK_START, t.strip()));
                    break;
                case "bkmkend":
                    flush_text();
                    para.inlines.add(new Mark(MarkKind.BOOKMARK_END, t.strip()));
                    break;
                default: break;
            }
            st.dest = "";
            dest_depth = -1;
            dest_text.truncate(0);
        }

        private static string map_style(string n) {
            string l = n.down();
            if (l.has_prefix("heading ") && l.length > 8) return "Heading" + l.substring(8).strip();
            switch (l) {
                case "normal": return "Normal";
                case "title": return "Title";
                case "subtitle": return "Subtitle";
                case "quote":
                case "block text": return "Quote";
                case "caption": return "Caption";
                case "footnote text": return "FootnoteText";
                case "header": return "Header";
                case "footer": return "Footer";
                case "list paragraph": return "ListParagraph";
                default:
                    var sb = new StringBuilder();
                    unichar c;
                    int i = 0;
                    while (n.get_next_char(ref i, out c)) if (c.isalnum()) sb.append_unichar(c);
                    return sb.len > 0 ? sb.str : "Custom";
            }
        }

        private void finish_pict() {
            string hex = pict_hex.str;
            var bytes = new ByteArray();
            int hi = -1;
            for (int i = 0; i < hex.length; i++) {
                char c = hex[i];
                int v = c.xdigit_value();
                if (v < 0) continue;
                if (hi < 0) {
                    hi = v;
                } else {
                    uint8[] b = { (uint8) (hi * 16 + v) };
                    bytes.append(b);
                    hi = -1;
                }
            }
            st.dest = "";
            if (bytes.len == 0) return;
            var data = new Bytes(bytes.data);
            string mime = ImageRun.sniff(bytes.data);
            if (mime == "application/octet-stream") {
                var op = new OpaqueRun("rtf-pict", "", _("Picture in an unsupported format"));
                op.width = pict_w > 0 ? pict_w : 144;
                op.height = pict_h > 0 ? pict_h : 72;
                op.parts["data"] = data;
                para.inlines.add(op);
                return;
            }
            var img = new ImageRun(data, mime);
            img.width = pict_w > 0 ? pict_w : 144;
            img.height = pict_h > 0 ? pict_h : 144;
            para.inlines.add(inl(img));
        }

        private FieldBlock? field_block = null;
        private BlockList? block_saved_target = null;

        private void finish_field_result() {
            flush_text();
            if (field_block != null && field_para == null) {
                if (!para.is_empty()) commit_para();
                target = block_saved_target;
                field_block = null;
                field_inst = "";
                return;
            }
            if (field_para == null) return;
            string code = field_inst.strip();
            var items = new Gee.ArrayList<Inline>();
            while (field_para.inlines.size > field_para_start) items.add(field_para.inlines.remove_at(field_para_start));
            if (code.up().has_prefix("HYPERLINK")) {
                string[] toks = Fields.tokenize(code);
                string url = toks.length > 1 ? toks[1] : "";
                string? loc = Fields.switch_arg(toks, "\\l");
                if (loc != null) url = url + "#" + loc;
                foreach (var i in items) {
                    i.props.link = url;
                    field_para.inlines.add(i);
                }
            } else {
                var sb = new StringBuilder();
                CharProps? cp = null;
                foreach (var i in items) {
                    if (cp == null) cp = i.props;
                    if (i is TextRun) sb.append(((TextRun) i).text);
                }
                var f = new FieldRun(code, sb.str);
                f.dirty = false;
                if (cp != null) f.props = cp.copy();
                field_para.inlines.add(f);
            }
            field_para = null;
        }
    }

    public class RtfWriter : Object {
        private Document doc;
        private StringBuilder o = new StringBuilder();
        private Gee.ArrayList<string> fonts = new Gee.ArrayList<string>();
        private Gee.ArrayList<string> colors = new Gee.ArrayList<string>();
        private Gee.ArrayList<string> authors = new Gee.ArrayList<string>();
        private Gee.HashMap<string, int> style_nums = new Gee.HashMap<string, int>();
        private Gee.HashMap<int, int> list_ls = new Gee.HashMap<int, int>();

        public static uint8[] save(Document doc) {
            var w = new RtfWriter(doc);
            return w.write().data;
        }

        public RtfWriter(Document doc) {
            this.doc = doc;
        }

        private int font_index(string? f) {
            string name = f ?? doc.styles.default_char.font ?? "Liberation Serif";
            int i = fonts.index_of(name);
            if (i < 0) {
                fonts.add(name);
                i = fonts.size - 1;
            }
            return i;
        }

        private int color_index(string? c) {
            if (c == null || c == "none") return 0;
            int i = colors.index_of(c.down());
            if (i < 0) {
                colors.add(c.down());
                i = colors.size - 1;
            }
            return i + 1;
        }

        private int author_index(string a) {
            int i = authors.index_of(a);
            if (i < 0) {
                authors.add(a);
                i = authors.size - 1;
            }
            return i + 1;
        }

        public static string esc(string s) {
            var sb = new StringBuilder();
            unichar c;
            int i = 0;
            while (s.get_next_char(ref i, out c)) {
                if (c == '\\' || c == '{' || c == '}') {
                    sb.append_c('\\');
                    sb.append_unichar(c);
                } else if (c == '\t') {
                    sb.append("\\tab ");
                } else if (c == '\n' || c == 0x2028) {
                    sb.append("\\line ");
                } else if (c == 0xA0) {
                    sb.append("\\~");
                } else if (c == 0xAD) {
                    sb.append("\\-");
                } else if (c == 0x2011) {
                    sb.append("\\_");
                } else if (c < 0x80) {
                    if (c >= 0x20) sb.append_unichar(c);
                } else if (c < 0x10000) {
                    int v = (int) c;
                    if (v > 32767) v -= 65536;
                    sb.append("\\u%d?".printf(v));
                } else {
                    uint32 u = (uint32) c - 0x10000;
                    int hi = (int) (0xD800 + (u >> 10)) - 65536;
                    int lo = (int) (0xDC00 + (u & 0x3FF)) - 65536;
                    sb.append("\\u%d?\\u%d?".printf(hi, lo));
                }
            }
            return sb.str;
        }

        private string char_codes(CharProps c) {
            var sb = new StringBuilder();
            if (c.style != null && style_nums.has_key(c.style)) sb.append("\\cs%d".printf(style_nums[c.style]));
            if (c.font != null) sb.append("\\f%d".printf(font_index(c.font)));
            if (c.size > 0) sb.append("\\fs%d".printf((int) Math.round(c.size * 2)));
            if (c.bold != Tri.INHERIT) sb.append(c.bold.on() ? "\\b" : "\\b0");
            if (c.italic != Tri.INHERIT) sb.append(c.italic.on() ? "\\i" : "\\i0");
            switch (c.underline) {
                case Underline.SINGLE: sb.append("\\ul"); break;
                case Underline.DOUBLE: sb.append("\\uldb"); break;
                case Underline.DOTTED: sb.append("\\uld"); break;
                case Underline.DASHED: sb.append("\\uldash"); break;
                case Underline.WAVY: sb.append("\\ulwave"); break;
                case Underline.THICK: sb.append("\\ulth"); break;
                case Underline.WORDS: sb.append("\\ulw"); break;
                case Underline.NONE: sb.append("\\ulnone"); break;
                default: break;
            }
            if (c.strike != Tri.INHERIT) sb.append(c.strike.on() ? "\\strike" : "\\strike0");
            if (c.dstrike.on()) sb.append("\\striked1");
            if (c.caps == Caps.ALL) sb.append("\\caps");
            else if (c.caps == Caps.SMALL) sb.append("\\scaps");
            if (c.hidden.on()) sb.append("\\v");
            if (c.outline.on()) sb.append("\\outl");
            if (c.shadow.on()) sb.append("\\shad");
            if (c.valign == VAlign.SUPER) sb.append("\\super");
            else if (c.valign == VAlign.SUB) sb.append("\\sub");
            if (c.color != null) sb.append("\\cf%d".printf(color_index(c.color)));
            if (c.highlight != null && c.highlight != "none") sb.append("\\highlight%d".printf(color_index(c.highlight)));
            if (c.shading != null) sb.append("\\chcbpat%d".printf(color_index(c.shading)));
            if (!c.spacing.is_nan()) sb.append("\\expndtw%d".printf((int) Math.round(c.spacing * 20)));
            return sb.str;
        }

        private string para_codes(Paragraph p) {
            var sb = new StringBuilder("\\pard");
            if (style_nums.has_key(p.style)) sb.append("\\s%d".printf(style_nums[p.style]));
            sb.append(para_prop_codes(p.props));
            int lvl = doc.styles.outline_level(p);
            if (lvl >= 0) sb.append("\\outlinelevel%d".printf(lvl));
            if (p.props.num_id > 0 && list_ls.has_key(p.props.num_id)) sb.append("\\ls%d\\ilvl%d".printf(list_ls[p.props.num_id], int.max(0, p.props.num_level)));
            return sb.str;
        }

        private string para_prop_codes(ParaProps pp) {
            var sb = new StringBuilder();
            switch (pp.align) {
                case Align.CENTER: sb.append("\\qc"); break;
                case Align.RIGHT: sb.append("\\qr"); break;
                case Align.JUSTIFY: sb.append("\\qj"); break;
                case Align.LEFT: sb.append("\\ql"); break;
                default: break;
            }
            if (!pp.ind_left.is_nan()) sb.append("\\li%d".printf((int) Math.round(pp.ind_left * 20)));
            if (!pp.ind_right.is_nan()) sb.append("\\ri%d".printf((int) Math.round(pp.ind_right * 20)));
            if (!pp.ind_first.is_nan()) sb.append("\\fi%d".printf((int) Math.round(pp.ind_first * 20)));
            if (!pp.space_before.is_nan()) sb.append("\\sb%d".printf((int) Math.round(pp.space_before * 20)));
            if (!pp.space_after.is_nan()) sb.append("\\sa%d".printf((int) Math.round(pp.space_after * 20)));
            if (!pp.line.is_nan()) {
                if (pp.line_rule == LineRule.AUTO) sb.append("\\sl%d\\slmult1".printf((int) Math.round(pp.line * 240)));
                else if (pp.line_rule == LineRule.EXACT) sb.append("\\sl-%d\\slmult0".printf((int) Math.round(pp.line * 20)));
                else sb.append("\\sl%d\\slmult0".printf((int) Math.round(pp.line * 20)));
            }
            if (pp.keep_next.on()) sb.append("\\keepn");
            if (pp.keep_lines.on()) sb.append("\\keep");
            if (pp.page_break_before.on()) sb.append("\\pagebb");
            if (pp.tabs != null) {
                foreach (var t in pp.tabs) {
                    if (t.leader == TabLeader.DOT) sb.append("\\tldot");
                    else if (t.leader == TabLeader.HYPHEN) sb.append("\\tlhyph");
                    else if (t.leader == TabLeader.UNDERSCORE) sb.append("\\tlul");
                    if (t.align == TabAlign.CENTER) sb.append("\\tqc");
                    else if (t.align == TabAlign.RIGHT) sb.append("\\tqr");
                    else if (t.align == TabAlign.DECIMAL) sb.append("\\tqdec");
                    sb.append("\\tx%d".printf((int) Math.round(t.pos * 20)));
                }
            }
            return sb.str;
        }

        private string write() {
            var body = new StringBuilder();
            int n = 1;
            foreach (var s in doc.styles.list) {
                if (s.kind == StyleType.PARAGRAPH || s.kind == StyleType.CHARACTER) style_nums[s.id] = s.id == "Normal" ? 0 : n++;
            }
            int ls = 1;
            foreach (var inst in doc.numbering.instances) list_ls[inst.id] = ls++;
            write_blocks(body, doc.body, false);
            var s = doc.final_section;
            var sb = new StringBuilder();
            sb.append("{\\rtf1\\ansi\\ansicpg1252\\deff0\\uc1");
            font_index(doc.styles.default_char.font);
            var styles = new StringBuilder("{\\stylesheet");
            foreach (var st in doc.styles.list) {
                if (!style_nums.has_key(st.id)) continue;
                if (st.kind == StyleType.CHARACTER) styles.append("{\\*\\cs%d ".printf(style_nums[st.id]));
                else styles.append("{\\s%d".printf(style_nums[st.id]));
                if (st.kind == StyleType.PARAGRAPH) styles.append(para_prop_codes(st.para));
                styles.append(char_codes(st.chr));
                if (st.based_on != null && style_nums.has_key(st.based_on)) styles.append("\\sbasedon%d".printf(style_nums[st.based_on]));
                if (st.next != null && style_nums.has_key(st.next)) styles.append("\\snext%d".printf(style_nums[st.next]));
                styles.append(" %s;}".printf(esc(st.name)));
            }
            styles.append("}");
            string style_str = styles.str;
            var lists = new StringBuilder();
            if (doc.numbering.instances.size > 0) {
                lists.append("{\\*\\listtable");
                foreach (var d in doc.numbering.defs) {
                    lists.append("{\\list\\listtemplateid%d".printf(d.id + 1));
                    for (int i = 0; i < 9; i++) {
                        var l = d.levels[i];
                        int nfc = 0;
                        switch (l.format) {
                            case NumFormat.UPPER_ROMAN: nfc = 1; break;
                            case NumFormat.LOWER_ROMAN: nfc = 2; break;
                            case NumFormat.UPPER_LETTER: nfc = 3; break;
                            case NumFormat.LOWER_LETTER: nfc = 4; break;
                            case NumFormat.BULLET: nfc = 23; break;
                            case NumFormat.NONE: nfc = 255; break;
                            default: nfc = 0; break;
                        }
                        lists.append("{\\listlevel\\levelnfc%d\\levelstartat%d".printf(nfc, l.start));
                        if (l.format == NumFormat.BULLET) lists.append("{\\leveltext\\'01%s;}{\\levelnumbers;}".printf(esc(l.text)));
                        else lists.append("{\\leveltext\\'02\\'0%d.;}{\\levelnumbers\\'01;}".printf(i));
                        lists.append("\\li%d\\fi-%d}".printf((int) (l.ind_left * 20), (int) (l.hanging * 20)));
                    }
                    lists.append("\\listid%d}".printf(d.id + 1));
                }
                lists.append("}{\\*\\listoverridetable");
                foreach (var inst in doc.numbering.instances) lists.append("{\\listoverride\\listid%d\\listoverridecount0\\ls%d}".printf(inst.def_id + 1, list_ls[inst.id]));
                lists.append("}");
            }
            s = doc.sections()[0];
            sb.append("{\\fonttbl");
            for (int i = 0; i < fonts.size; i++) sb.append("{\\f%d\\fnil\\fcharset0 %s;}".printf(i, esc(fonts[i])));
            sb.append("}{\\colortbl;");
            foreach (string c in colors) {
                string h = c.has_prefix("#") ? c.substring(1) : c;
                if (h.length != 6) h = "000000";
                sb.append("\\red%d\\green%d\\blue%d;".printf((int) long.parse("0x" + h.substring(0, 2), 16), (int) long.parse("0x" + h.substring(2, 2), 16), (int) long.parse("0x" + h.substring(4, 2), 16)));
            }
            sb.append("}");
            sb.append(style_str);
            sb.append(lists.str);
            if (authors.size > 0) {
                sb.append("{\\*\\revtbl{Unknown;}");
                foreach (string a in authors) sb.append("{%s;}".printf(esc(a)));
                sb.append("}");
            }
            sb.append("{\\info");
            if (doc.meta.title != "") sb.append("{\\title %s}".printf(esc(doc.meta.title)));
            if (doc.meta.subject != "") sb.append("{\\subject %s}".printf(esc(doc.meta.subject)));
            if (doc.meta.author != "") sb.append("{\\author %s}".printf(esc(doc.meta.author)));
            if (doc.meta.keywords != "") sb.append("{\\keywords %s}".printf(esc(doc.meta.keywords)));
            if (doc.meta.description != "") sb.append("{\\doccomm %s}".printf(esc(doc.meta.description)));
            sb.append("}");
            sb.append("\\paperw%d\\paperh%d\\margl%d\\margr%d\\margt%d\\margb%d".printf((int) (s.page_w * 20), (int) (s.page_h * 20), (int) (s.margin_left * 20), (int) (s.margin_right * 20), (int) (s.margin_top * 20), (int) (s.margin_bottom * 20)));
            if (s.landscape) sb.append("\\landscape");
            if (doc.track_changes) sb.append("\\revisions");
            if (doc.even_odd_headers) sb.append("\\facingp");
            sb.append(section_codes(s));
            sb.append(body.str);
            sb.append("}");
            return sb.str;
        }

        private string section_codes(Section ns) {
            var sb = new StringBuilder("\\sectd");
            if (ns.start == SectionStart.CONTINUOUS) sb.append("\\sbknone");
            else if (ns.start == SectionStart.ODD_PAGE) sb.append("\\sbkodd");
            else if (ns.start == SectionStart.EVEN_PAGE) sb.append("\\sbkeven");
            if (ns.columns > 1) sb.append("\\cols%d\\colsx%d".printf(ns.columns, (int) (ns.column_space * 20)));
            if (ns.column_sep) sb.append("\\linebetcol");
            if (ns.landscape) sb.append("\\lndscpsxn");
            sb.append("\\pgwsxn%d\\pghsxn%d\\marglsxn%d\\margrsxn%d\\margtsxn%d\\margbsxn%d\\headery%d\\footery%d".printf(
                (int) (ns.page_w * 20), (int) (ns.page_h * 20), (int) (ns.margin_left * 20), (int) (ns.margin_right * 20),
                (int) (ns.margin_top * 20), (int) (ns.margin_bottom * 20), (int) (ns.header_dist * 20), (int) (ns.footer_dist * 20)));
            if (ns.title_page) sb.append("\\titlepg");
            if (ns.page_start >= 0) sb.append("\\pgnrestart\\pgnstarts%d".printf(ns.page_start));
            if (ns.page_format == NumFormat.LOWER_ROMAN) sb.append("\\pgnlcrm");
            else if (ns.page_format == NumFormat.UPPER_ROMAN) sb.append("\\pgnucrm");
            sb.append("\n");
            write_hf(sb, "header", ns.header_default);
            write_hf(sb, "headerf", ns.header_first);
            write_hf(sb, "headerl", ns.header_even);
            write_hf(sb, "footer", ns.footer_default);
            write_hf(sb, "footerf", ns.footer_first);
            write_hf(sb, "footerl", ns.footer_even);
            return sb.str;
        }

        private void write_hf(StringBuilder sb, string kind, HeaderFooter? h) {
            if (h == null) return;
            sb.append("{\\%s ".printf(kind));
            write_blocks(sb, h.blocks, true);
            sb.append("}");
        }

        private void write_blocks(StringBuilder sb, BlockList list, bool nested) {
            for (int i = 0; i < list.size; i++) {
                var b = list[i];
                if (b is Paragraph) {
                    var p = (Paragraph) b;
                    sb.append(para_codes(p));
                    sb.append(" ");
                    write_inlines(sb, p.inlines);
                    bool last = nested && i == list.size - 1;
                    if (p.section != null && !nested) {
                        sb.append("\\par\\sect");
                        var sections = doc.sections();
                        var next_idx = sections.index_of(p.section) + 1;
                        if (next_idx < sections.size) sb.append(section_codes(sections[next_idx]));
                        sb.append("\n");
                    } else if (!last) {
                        sb.append("\\par\n");
                    }
                } else if (b is Table) {
                    write_table(sb, (Table) b);
                } else if (b is FieldBlock) {
                    var fb = (FieldBlock) b;
                    sb.append("{\\field{\\*\\fldinst %s}{\\fldrslt ".printf(esc(fb.code)));
                    write_blocks(sb, fb.result, false);
                    sb.append("}}\n");
                }
            }
        }

        private void write_table(StringBuilder sb, Table t) {
            for (int r = 0; r < t.rows.size; r++) {
                var row = t.rows[r];
                sb.append("\\trowd\\trgaph%d".printf((int) (t.margin_l * 20)));
                if (row.header) sb.append("\\trhdr");
                double x = t.indent;
                int col = 0;
                foreach (var c in row.cells) {
                    if (c.vmerge == VMerge.RESTART) sb.append("\\clvmgf");
                    else if (c.vmerge == VMerge.CONTINUE) sb.append("\\clvmrg");
                    if (c.shading != null) sb.append("\\clcbpat%d".printf(color_index(c.shading)));
                    if (c.valign == CellVAlign.CENTER) sb.append("\\clvertalc");
                    else if (c.valign == CellVAlign.BOTTOM) sb.append("\\clvertalb");
                    sb.append("\\clbrdrt\\brdrs\\brdrw10\\clbrdrl\\brdrs\\brdrw10\\clbrdrb\\brdrs\\brdrw10\\clbrdrr\\brdrs\\brdrw10");
                    for (int k = col; k < col + c.span && k < t.grid.length; k++) x += t.grid[k];
                    col += c.span;
                    sb.append("\\cellx%d".printf((int) Math.round(x * 20)));
                }
                sb.append("\n");
                foreach (var c in row.cells) {
                    for (int i = 0; i < c.blocks.size; i++) {
                        var p = c.blocks[i] as Paragraph;
                        if (p == null) continue;
                        sb.append(para_codes(p));
                        sb.append("\\intbl ");
                        write_inlines(sb, p.inlines);
                        if (i < c.blocks.size - 1) sb.append("\\par ");
                    }
                    sb.append("\\cell ");
                }
                sb.append("\\row\n");
            }
            sb.append("\\pard\n");
        }

        private void write_inlines(StringBuilder sb, Gee.List<Inline> inlines) {
            foreach (var it in inlines) {
                string codes = char_codes(it.props);
                string rev = "";
                if (it.rev != null) rev = it.rev.kind == RevKind.DELETE ? "\\deleted\\revauthdel%d".printf(author_index(it.rev.author)) : "\\revised\\revauth%d".printf(author_index(it.rev.author));
                string link = it.props.link ?? "";
                if (link != "") {
                    int h = link.index_of_char('#');
                    string url = h >= 0 ? link.substring(0, h) : link;
                    string anchor = h >= 0 ? link.substring(h + 1) : "";
                    string inst = url != "" ? "HYPERLINK \"%s\"".printf(url) : "HYPERLINK";
                    if (anchor != "") inst += " \\l \"%s\"".printf(anchor);
                    sb.append("{\\field{\\*\\fldinst %s}{\\fldrslt ".printf(esc(inst)));
                }
                string sep = codes + rev != "" ? " " : "";
                if (it is TextRun) {
                    sb.append("{%s%s%s%s}".printf(codes, rev, sep, esc(((TextRun) it).text)));
                } else if (it is Tab) {
                    sb.append("\\tab ");
                } else if (it is Break) {
                    var b = (Break) it;
                    sb.append(b.kind == BreakKind.PAGE ? "\\page " : (b.kind == BreakKind.COLUMN ? "\\column " : "\\line "));
                } else if (it is FieldRun) {
                    var f = (FieldRun) it;
                    if (!f.code.has_prefix("\x01")) sb.append("{\\field{\\*\\fldinst %s}{\\fldrslt {%s%s%s}}}".printf(esc(f.code), codes, sep, esc(f.result)));
                } else if (it is NoteRef) {
                    var n = (NoteRef) it;
                    sb.append("{\\super\\chftn}{\\footnote%s\\pard\\plain{\\super\\chftn} ".printf(n.note.kind == NoteKind.ENDNOTE ? "\\ftnalt" : ""));
                    write_blocks(sb, n.note.blocks, true);
                    sb.append("}");
                } else if (it is Mark) {
                    var m = (Mark) it;
                    if (m.kind == MarkKind.BOOKMARK_START) sb.append("{\\*\\bkmkstart %s}".printf(esc(m.name)));
                    else if (m.kind == MarkKind.BOOKMARK_END) sb.append("{\\*\\bkmkend %s}".printf(esc(m.name)));
                    else if (m.kind == MarkKind.COMMENT_END) {
                        var c = doc.find_comment(m.name);
                        if (c != null) {
                            sb.append("{\\*\\atnid %s}{\\*\\atnauthor %s}\\chatn{\\*\\annotation\\pard\\plain ".printf(esc(c.initials), esc(c.author)));
                            write_blocks(sb, c.blocks, true);
                            sb.append("}");
                        }
                    } else if (m.kind == MarkKind.INDEX_ENTRY) {
                        sb.append("{\\xe {\\v %s}}".printf(esc(m.name)));
                    }
                } else if (it is ImageRun) {
                    var img = (ImageRun) it;
                    string blip = img.mime == "image/jpeg" ? "\\jpegblip" : (img.mime == "image/png" ? "\\pngblip" : "");
                    if (blip != "") {
                        sb.append("{\\pict%s\\picwgoal%d\\pichgoal%d\n".printf(blip, (int) (img.width * 20), (int) (img.height * 20)));
                        uint8[] d = img.data.get_data();
                        for (int i = 0; i < d.length; i++) {
                            sb.append("%02x".printf(d[i]));
                            if (i % 64 == 63) sb.append_c('\n');
                        }
                        sb.append("}");
                    }
                } else if (it is ShapeRun) {
                    var s = (ShapeRun) it;
                    foreach (var b in s.text.items) {
                        var p = b as Paragraph;
                        if (p != null) write_inlines(sb, p.inlines);
                    }
                } else if (it is EquationRun) {
                    sb.append("{%s%s%s}".printf(codes, sep, esc(((EquationRun) it).linear_text())));
                } else if (it is FormField) {
                    sb.append("{%s%s%s}".printf(codes, sep, esc(((FormField) it).display_text())));
                }
                if (link != "") sb.append("}}");
            }
        }
    }
}
