namespace Write {

    public class FindOptions : Object {
        public string query = "";
        public bool match_case = false;
        public bool whole_word = false;
        public bool wildcards = false;
        public bool regex = false;
        public bool sounds_like = false;
        public bool all_forms = false;
        public Tri bold = Tri.INHERIT;
        public Tri italic = Tri.INHERIT;
        public Tri underline = Tri.INHERIT;
        public string? style = null;
        public string? highlight = null;
        public string? font = null;
        public bool include_notes = true;
        public bool include_headers = true;
    }

    public class Match : Object {
        public Paragraph para;
        public int start;
        public int end;
        public string text;
        public string[] groups = {};

        public Match(Paragraph para, int start, int end, string text) {
            this.para = para;
            this.start = start;
            this.end = end;
            this.text = text;
        }
    }

    public class Finder : Object {

        public static string special(string q) {
            var sb = new StringBuilder();
            int i = 0;
            while (i < q.length) {
                if (q[i] == '^' && i + 1 < q.length) {
                    char c = q[i + 1];
                    switch (c) {
                        case 't': sb.append_c('\t'); i += 2; continue;
                        case 'l': sb.append_unichar(0x2028); i += 2; continue;
                        case 'm': sb.append_c('\f'); i += 2; continue;
                        case 'n': sb.append_c(0x0B); i += 2; continue;
                        case '~': sb.append_unichar(0xA0); i += 2; continue;
                        case '-': sb.append_unichar(0xAD); i += 2; continue;
                        case '_': sb.append_unichar(0x2011); i += 2; continue;
                        case '+': sb.append_unichar(0x2014); i += 2; continue;
                        case '=': sb.append_unichar(0x2013); i += 2; continue;
                        case '^': sb.append_c('^'); i += 2; continue;
                        case 's': sb.append_unichar(0xA0); i += 2; continue;
                        default: break;
                    }
                }
                sb.append_c(q[i]);
                i++;
            }
            return sb.str;
        }

        public static string wildcard_to_regex(string q) {
            var sb = new StringBuilder();
            int i = 0;
            while (i < q.length) {
                char c = q[i];
                switch (c) {
                    case '?': sb.append("."); break;
                    case '*': sb.append(".*?"); break;
                    case '@': sb.append("+"); break;
                    case '<': sb.append("\\b(?=\\w)"); break;
                    case '>': sb.append("\\b(?<=\\w)"); break;
                    case '[':
                        int e = q.index_of_char(']', i);
                        if (e < 0) {
                            sb.append("\\[");
                            break;
                        }
                        string inner = q.substring(i + 1, e - i - 1);
                        if (inner.has_prefix("!")) inner = "^" + inner.substring(1);
                        sb.append("[" + inner + "]");
                        i = e;
                        break;
                    case '{':
                        int ce = q.index_of_char('}', i);
                        if (ce < 0) {
                            sb.append("\\{");
                            break;
                        }
                        sb.append(q.substring(i, ce - i + 1).replace(";", ","));
                        i = ce;
                        break;
                    case '(':
                    case ')':
                        sb.append_c(c);
                        break;
                    case '\\':
                        if (i + 1 < q.length) {
                            sb.append(Regex.escape_string(q.substring(i + 1, 1)));
                            i++;
                        }
                        break;
                    default:
                        sb.append(Regex.escape_string(q.substring(i, 1)));
                        break;
                }
                i++;
            }
            return sb.str;
        }

        public static Regex? build(FindOptions o) throws RegexError {
            if (o.query == "") return null;
            string pattern;
            if (o.regex) pattern = o.query;
            else if (o.wildcards) pattern = wildcard_to_regex(o.query);
            else pattern = Regex.escape_string(special(o.query));
            if (o.whole_word && !o.regex) pattern = "\\b" + pattern + "\\b";
            RegexCompileFlags flags = RegexCompileFlags.OPTIMIZE;
            if (!o.match_case && !(o.wildcards && !o.regex)) flags |= RegexCompileFlags.CASELESS;
            if (o.wildcards && !o.match_case) flags |= RegexCompileFlags.CASELESS;
            return new Regex(pattern, flags);
        }

        public static Gee.ArrayList<Paragraph> scope(Document doc, FindOptions o) {
            var list = Story.paragraphs(doc.body);
            if (o.include_headers) foreach (var hf in doc.header_footers()) list.add_all(Story.paragraphs(hf.blocks));
            if (o.include_notes) foreach (var n in doc.notes()) list.add_all(Story.paragraphs(n.blocks));
            return list;
        }

        private static bool format_ok(Document doc, Paragraph p, int start, int end, FindOptions o) {
            if (o.style != null && p.style != o.style) {
                bool char_style = false;
                var it0 = p.inline_at(start);
                if (it0 != null && it0.props.style == o.style) char_style = true;
                if (!char_style) return false;
            }
            if (o.bold == Tri.INHERIT && o.italic == Tri.INHERIT && o.underline == Tri.INHERIT && o.highlight == null && o.font == null) return true;
            int off = 0;
            foreach (var it in p.inlines) {
                int len = it.length;
                if (len > 0 && off + len > start && off < end) {
                    var c = doc.styles.resolve_char(p, it.props);
                    if (o.bold != Tri.INHERIT && c.bold.on() != o.bold.on()) return false;
                    if (o.italic != Tri.INHERIT && c.italic.on() != o.italic.on()) return false;
                    if (o.underline != Tri.INHERIT && (c.underline != Underline.NONE && c.underline != Underline.INHERIT) != o.underline.on()) return false;
                    if (o.highlight != null && c.highlight != o.highlight) return false;
                    if (o.font != null && c.font != o.font) return false;
                }
                off += len;
            }
            return true;
        }

        public static Gee.ArrayList<Match> find_all(Document doc, FindOptions o) throws RegexError {
            var result = new Gee.ArrayList<Match>();
            if (o.query == "" && o.style == null && o.bold == Tri.INHERIT && o.italic == Tri.INHERIT) return result;
            Regex? re = o.query != "" ? build(o) : null;
            foreach (var p in scope(doc, o)) {
                string t = p.text();
                if (re == null) {
                    if (t.length > 0 && format_ok(doc, p, 0, p.length, o)) result.add(new Match(p, 0, p.length, t));
                    continue;
                }
                MatchInfo mi;
                if (!re.match(t, 0, out mi)) continue;
                while (mi.matches()) {
                    int bs, be;
                    mi.fetch_pos(0, out bs, out be);
                    if (be > bs) {
                        int s = t.substring(0, bs).char_count();
                        int e = s + t.substring(bs, be - bs).char_count();
                        if (format_ok(doc, p, s, e, o)) {
                            var m = new Match(p, s, e, mi.fetch(0));
                            m.groups = mi.fetch_all();
                            result.add(m);
                        }
                    }
                    try {
                        if (!mi.next()) break;
                    } catch (RegexError e) {
                        break;
                    }
                }
            }
            return result;
        }

        public static string expand_replacement(string rep, Match m, bool wildcards) {
            string r = special(rep);
            if (r.contains("^&")) r = r.replace("^&", m.text);
            if (wildcards || r.contains("\\")) {
                var sb = new StringBuilder();
                int i = 0;
                while (i < r.length) {
                    if (r[i] == '\\' && i + 1 < r.length && r[i + 1].isdigit()) {
                        int g = r[i + 1] - '0';
                        if (g < m.groups.length) sb.append(m.groups[g]);
                        i += 2;
                        continue;
                    }
                    if (r[i] == '$' && i + 1 < r.length && r[i + 1].isdigit()) {
                        int g = r[i + 1] - '0';
                        if (g < m.groups.length) sb.append(m.groups[g]);
                        i += 2;
                        continue;
                    }
                    sb.append_c(r[i]);
                    i++;
                }
                r = sb.str;
            }
            return r;
        }

        public static int replace_all(Editor ed, FindOptions o, string replacement, CharMutator? fmt = null) throws RegexError {
            var matches = find_all(ed.doc, o);
            if (matches.size == 0) return 0;
            ed.checkpoint(_("Replace All"));
            for (int i = matches.size - 1; i >= 0; i--) {
                var m = matches[i];
                string rep = expand_replacement(replacement, m, o.wildcards || o.regex);
                replace_one_raw(ed, m, rep, fmt);
            }
            ed.changed();
            return matches.size;
        }

        public static void replace_one_raw(Editor ed, Match m, string rep, CharMutator? fmt = null) {
            var props = m.para.props_at(m.start + 1);
            ed.select(new Pos(m.para, m.start), new Pos(m.para, m.end));
            string text = rep;
            bool para_break = text.contains("^p");
            if (para_break) text = text.replace("^p", "\n");
            ed.delete_selection();
            if (text != "") {
                var cp = props.copy();
                if (fmt != null) fmt(cp);
                ed.insert_text(text, cp);
            }
        }
    }
}
