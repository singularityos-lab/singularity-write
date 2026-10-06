namespace Write {

    public struct DocStats {
        public int words;
        public int chars;
        public int chars_no_spaces;
        public int paragraphs;
        public int sentences;
    }

    public class Stats : Object {

        public static DocStats compute(Document doc, bool with_notes) {
            var list = doc.paragraphs(with_notes);
            if (with_notes) {
                foreach (var hf in doc.header_footers()) {
                    foreach (var b in hf.blocks.items) {
                        var p = b as Paragraph;
                        if (p != null) list.add(p);
                    }
                }
            }
            return of_texts(texts(list));
        }

        public static string[] texts(Gee.List<Paragraph> list) {
            string[] res = {};
            foreach (var p in list) res += p.plain_text();
            return res;
        }

        public static DocStats of_texts(string[] texts) {
            DocStats s = { 0, 0, 0, 0, 0 };
            foreach (string t in texts) {
                if (t.strip() != "") s.paragraphs++;
                count_text(t, ref s);
            }
            return s;
        }

        public static void count_text(string t, ref DocStats s) {
            bool in_word = false;
            unichar c;
            unichar prev = 0;
            int i = 0;
            while (t.get_next_char(ref i, out c)) {
                if (c == 0xFFFC) continue;
                s.chars++;
                bool space = c.isspace() || c == 0x00A0 || c == 0x2002 || c == 0x2003;
                if (!space) s.chars_no_spaces++;
                bool word_char = !space && c != 0x2014 && c != 0x2013;
                if (word_char && !in_word) s.words++;
                in_word = word_char;
                if ((c == '.' || c == '!' || c == '?') && prev != '.' && prev != '!' && prev != '?') s.sentences++;
                prev = c;
            }
        }

        public static int count_words(string t) {
            DocStats s = { 0, 0, 0, 0, 0 };
            count_text(t, ref s);
            return s.words;
        }
    }

    public class Citations : Object {

        public static string[] styles() {
            return { "APA", "MLA", "Chicago", "IEEE", "Harvard" };
        }

        public static string last_name(string author) {
            string a = author.strip();
            int comma = a.index_of_char(',');
            if (comma > 0) return a.substring(0, comma).strip();
            int sp = a.last_index_of_char(' ');
            return sp > 0 ? a.substring(sp + 1) : a;
        }

        public static string first_names(string author) {
            string a = author.strip();
            int comma = a.index_of_char(',');
            if (comma > 0) return a.substring(comma + 1).strip();
            int sp = a.last_index_of_char(' ');
            return sp > 0 ? a.substring(0, sp) : "";
        }

        public static string initials(string names) {
            var sb = new StringBuilder();
            foreach (string part in names.split(" ")) {
                if (part == "") continue;
                if (sb.len > 0) sb.append_c(' ');
                sb.append_unichar(part.get_char(0).toupper());
                sb.append_c('.');
            }
            return sb.str;
        }

        public static int number_of(Document doc, string tag) {
            var order = new Gee.ArrayList<string>();
            foreach (var p in doc.paragraphs(true)) {
                foreach (var i in p.inlines) {
                    var f = i as FieldRun;
                    if (f == null || f.kind() != "CITATION") continue;
                    string[] t = f.args();
                    if (t.length > 1 && !order.contains(t[1])) order.add(t[1]);
                }
            }
            int idx = order.index_of(tag);
            if (idx < 0) {
                int s = 0;
                foreach (var src in doc.sources) {
                    s++;
                    if (src.tag == tag) return s;
                }
                return 0;
            }
            return idx + 1;
        }

        public static string cite(Document doc, string tag, string[] toks) {
            var s = doc.find_source(tag);
            if (s == null) return _("[Unknown source %s]").printf(tag);
            string? pages = Fields.switch_arg(toks, "\\p");
            bool no_author = Fields.has_switch(toks, "\\n");
            bool no_year = Fields.has_switch(toks, "\\y");
            string auth;
            if (s.authors.length == 0) {
                auth = s.title;
            } else if (s.authors.length == 1) {
                auth = last_name(s.authors[0]);
            } else if (s.authors.length == 2) {
                string a0 = last_name(s.authors[0]);
                string a1 = last_name(s.authors[1]);
                auth = "%s & %s".printf(a0, a1);
            } else {
                string a0 = last_name(s.authors[0]);
                auth = "%s et al.".printf(a0);
            }
            switch (doc.bib_style) {
                case "IEEE":
                    return "[%d]".printf(number_of(doc, tag)) + (pages != null ? ", p. " + pages : "");
                case "MLA":
                    string m = no_author ? "" : auth;
                    if (pages != null) m += (m != "" ? " " : "") + pages;
                    return "(" + m + ")";
                case "Chicago":
                case "Harvard":
                    string c = (no_author ? "" : auth) + (no_year || s.year == "" ? "" : " " + s.year);
                    if (pages != null) c += ", " + pages;
                    return "(" + c.strip() + ")";
                default:
                    string a = (no_author ? "" : auth) + (no_year || s.year == "" ? "" : ", " + s.year);
                    if (s.year == "" && !no_year) a += ", n.d.";
                    if (pages != null) a += ", p. " + pages;
                    return "(" + a.strip() + ")";
            }
        }

        private static string join_authors(string[] authors, string style) {
            var parts = new Gee.ArrayList<string>();
            for (int i = 0; i < authors.length; i++) {
                string last = last_name(authors[i]);
                string first = first_names(authors[i]);
                switch (style) {
                    case "APA":
                    case "Harvard":
                        parts.add(first != "" ? "%s, %s".printf(last, initials(first)) : last);
                        break;
                    case "IEEE":
                        parts.add(first != "" ? "%s %s".printf(initials(first), last) : last);
                        break;
                    default:
                        if (i == 0) parts.add(first != "" ? "%s, %s".printf(last, first) : last);
                        else parts.add(first != "" ? "%s %s".printf(first, last) : last);
                        break;
                }
            }
            if (parts.size == 0) return "";
            if (parts.size == 1) return parts[0];
            var sb = new StringBuilder();
            string last_join = style == "APA" ? ", & " : (style == "IEEE" ? ", and " : ", and ");
            if (style == "MLA" && parts.size > 2) return parts[0] + ", et al.";
            for (int i = 0; i < parts.size; i++) {
                if (i > 0) sb.append(i == parts.size - 1 ? (parts.size == 2 && style != "APA" ? " and " : last_join) : ", ");
                sb.append(parts[i]);
            }
            return sb.str;
        }

        public struct Piece {
            public string text;
            public bool italic;
        }

        public static Piece[] entry(Document doc, BibSource s) {
            Piece[] p = {};
            string style = doc.bib_style;
            string authors = join_authors(s.authors, style);
            bool container = s.journal != "";
            string year = s.year != "" ? s.year : "n.d.";
            switch (style) {
                case "IEEE":
                    p += Piece() { text = "[%d] ".printf(number_of(doc, s.tag)), italic = false };
                    if (authors != "") p += Piece() { text = authors + ", ", italic = false };
                    if (container) {
                        p += Piece() { text = "\u201c" + s.title + ",\u201d ", italic = false };
                        p += Piece() { text = s.journal, italic = true };
                        string tail = "";
                        if (s.volume != "") tail += ", vol. " + s.volume;
                        if (s.issue != "") tail += ", no. " + s.issue;
                        if (s.pages != "") tail += ", pp. " + s.pages;
                        tail += ", " + year + ".";
                        p += Piece() { text = tail, italic = false };
                    } else {
                        p += Piece() { text = s.title, italic = true };
                        string tail = ". ";
                        if (s.city != "") tail += s.city + ": ";
                        if (s.publisher != "") tail += s.publisher + ", ";
                        tail += year + ".";
                        p += Piece() { text = tail, italic = false };
                    }
                    break;
                case "MLA":
                    if (authors != "") p += Piece() { text = authors + ". ", italic = false };
                    if (container) {
                        p += Piece() { text = "\u201c" + s.title + ".\u201d ", italic = false };
                        p += Piece() { text = s.journal, italic = true };
                        string tail = "";
                        if (s.volume != "") tail += ", vol. " + s.volume;
                        if (s.issue != "") tail += ", no. " + s.issue;
                        tail += ", " + year;
                        if (s.pages != "") tail += ", pp. " + s.pages;
                        p += Piece() { text = tail + ".", italic = false };
                    } else {
                        p += Piece() { text = s.title, italic = true };
                        string tail = ". ";
                        if (s.publisher != "") tail += s.publisher + ", ";
                        tail += year + ".";
                        p += Piece() { text = tail, italic = false };
                    }
                    break;
                case "Chicago":
                    if (authors != "") p += Piece() { text = authors + ". ", italic = false };
                    if (container) {
                        p += Piece() { text = "\u201c" + s.title + ".\u201d ", italic = false };
                        p += Piece() { text = s.journal, italic = true };
                        string tail = s.volume != "" ? " " + s.volume : "";
                        if (s.issue != "") tail += ", no. " + s.issue;
                        tail += " (" + year + ")";
                        if (s.pages != "") tail += ": " + s.pages;
                        p += Piece() { text = tail + ".", italic = false };
                    } else {
                        p += Piece() { text = s.title, italic = true };
                        string tail = ". ";
                        if (s.city != "") tail += s.city + ": ";
                        if (s.publisher != "") tail += s.publisher + ", ";
                        tail += year + ".";
                        p += Piece() { text = tail, italic = false };
                    }
                    break;
                default:
                    if (authors != "") p += Piece() { text = authors + " ", italic = false };
                    p += Piece() { text = "(" + year + "). ", italic = false };
                    if (container) {
                        p += Piece() { text = s.title + ". ", italic = false };
                        p += Piece() { text = s.journal + (s.volume != "" ? ", " + s.volume : ""), italic = true };
                        string tail = s.issue != "" ? "(" + s.issue + ")" : "";
                        if (s.pages != "") tail += ", " + s.pages;
                        p += Piece() { text = tail + ".", italic = false };
                    } else {
                        p += Piece() { text = s.title, italic = true };
                        string tail = ". ";
                        if (s.edition != "") tail = " (" + s.edition + " ed.). ";
                        if (s.publisher != "") tail += s.publisher + ".";
                        p += Piece() { text = tail.strip() == "." ? "." : tail, italic = false };
                    }
                    break;
            }
            string link = s.doi != "" ? "https://doi.org/" + s.doi : s.url;
            if (link != "") p += Piece() { text = " " + link, italic = false };
            return p;
        }

        public static Gee.ArrayList<BibSource> cited_sources(Document doc) {
            var tags = new Gee.ArrayList<string>();
            foreach (var p in doc.paragraphs(true)) {
                foreach (var i in p.inlines) {
                    var f = i as FieldRun;
                    if (f == null || f.kind() != "CITATION") continue;
                    string[] t = f.args();
                    if (t.length > 1 && !tags.contains(t[1])) tags.add(t[1]);
                }
            }
            var list = new Gee.ArrayList<BibSource>();
            foreach (string t in tags) {
                var s = doc.find_source(t);
                if (s != null) list.add(s);
            }
            if (list.size == 0) foreach (var s in doc.sources) list.add(s);
            if (doc.bib_style != "IEEE") {
                list.sort((a, b) => {
                    string ka = a.authors.length > 0 ? last_name(a.authors[0]) : a.title;
                    string kb = b.authors.length > 0 ? last_name(b.authors[0]) : b.title;
                    return strcmp(ka.casefold(), kb.casefold());
                });
            }
            return list;
        }
    }
}
