namespace Write {

    public class HyphenPatterns : Object {
        public Gee.HashMap<string, string> map = new Gee.HashMap<string, string>();
        public Gee.HashMap<string, string> exceptions = new Gee.HashMap<string, string>();
        public int maxlen = 0;
        public int leftmin = 2;
        public int rightmin = 3;

        public void add_pattern(string raw) {
            string pat = raw.strip();
            if (pat == "" || pat.has_prefix("%")) return;
            var letters = new StringBuilder();
            var digits = new StringBuilder();
            bool last_digit = false;
            unichar c;
            int i = 0;
            while (pat.get_next_char(ref i, out c)) {
                if (c >= '0' && c <= '9') {
                    digits.append_c((char) c);
                    last_digit = true;
                } else {
                    if (!last_digit) digits.append_c('0');
                    letters.append_unichar(c.tolower());
                    last_digit = false;
                }
            }
            if (!last_digit) digits.append_c('0');
            map[letters.str] = digits.str;
            int n = letters.str.char_count();
            if (n > maxlen) maxlen = n;
        }

        public void add_exception(string raw) {
            string w = raw.strip();
            if (w == "") return;
            map_exception(w);
        }

        private void map_exception(string w) {
            var plain = new StringBuilder();
            var pts = new StringBuilder("0");
            unichar c;
            int i = 0;
            while (w.get_next_char(ref i, out c)) {
                if (c == '-') {
                    pts.truncate(pts.len - 1);
                    pts.append_c('1');
                } else {
                    plain.append_unichar(c.tolower());
                    pts.append_c('0');
                }
            }
            exceptions[plain.str] = pts.str;
        }

        public static HyphenPatterns parse(string text, bool tex) {
            var p = new HyphenPatterns();
            string body = text;
            if (tex) {
                int s = body.index_of("\\patterns{");
                if (s >= 0) {
                    int e = body.index_of("}", s);
                    string pats = body.substring(s + 10, (e > s ? e : body.length) - s - 10);
                    foreach (string tok in pats.split_set(" \n\t\r")) p.add_pattern(tok);
                    int h = body.index_of("\\hyphenation{");
                    if (h >= 0) {
                        int he = body.index_of("}", h);
                        foreach (string tok in body.substring(h + 13, (he > h ? he : body.length) - h - 13).split_set(" \n\t\r")) p.add_exception(tok);
                    }
                    return p;
                }
                foreach (string tok in body.split_set(" \n\t\r")) p.add_pattern(tok);
                return p;
            }
            bool first = true;
            foreach (string line in body.split("\n")) {
                string l = line.strip();
                if (first) {
                    first = false;
                    if (l.up().has_prefix("UTF") || l.up().has_prefix("ISO") || l.up().has_prefix("KOI")) continue;
                }
                if (l.has_prefix("LEFTHYPHENMIN")) {
                    p.leftmin = int.parse(l.substring(13).strip());
                    continue;
                }
                if (l.has_prefix("RIGHTHYPHENMIN")) {
                    p.rightmin = int.parse(l.substring(14).strip());
                    continue;
                }
                if (l.has_prefix("%") || l.has_prefix("NEXTLEVEL") || l.has_prefix("COMPOUND") || l.has_prefix("NOHYPHEN")) continue;
                if (l.contains("/")) continue;
                p.add_pattern(l);
            }
            return p;
        }

        public int[] word_points(string word) {
            string lw = word.down();
            int n = lw.char_count();
            int[] result = new int[n + 1];
            if (exceptions.has_key(lw)) {
                string e = exceptions[lw];
                for (int i = 0; i < e.length && i <= n; i++) result[i] = e[i] - '0';
                return result;
            }
            string w = "." + lw + ".";
            unichar[] chars = {};
            unichar c;
            int idx = 0;
            while (w.get_next_char(ref idx, out c)) chars += c;
            int len = chars.length;
            int[] pts = new int[len + 1];
            for (int i = 0; i < len; i++) {
                var sb = new StringBuilder();
                for (int j = i; j < len && j - i < maxlen; j++) {
                    sb.append_unichar(chars[j]);
                    string? v = map[sb.str];
                    if (v == null) continue;
                    for (int k = 0; k < v.length; k++) {
                        int d = v[k] - '0';
                        if (i + k < pts.length && d > pts[i + k]) pts[i + k] = d;
                    }
                }
            }
            for (int i = 0; i <= n; i++) result[i] = pts[i + 1];
            return result;
        }
    }

    public class Hyphenator : Object {
        private static Hyphenator? instance = null;
        private Gee.HashMap<string, HyphenPatterns?> cache = new Gee.HashMap<string, HyphenPatterns?>();
        public Gee.ArrayList<string> dirs = new Gee.ArrayList<string>();

        public static Hyphenator get_default() {
            if (instance == null) instance = new Hyphenator();
            return instance;
        }

        public Hyphenator() {
            string? extra = Environment.get_variable("SINGULARITY_HYPHEN_DIRS");
            if (extra != null) foreach (string d in extra.split(":")) if (d != "") dirs.add(d);
            dirs.add(Path.build_filename(Environment.get_user_data_dir(), "hyphen"));
            foreach (string base_dir in Environment.get_system_data_dirs()) {
                dirs.add(Path.build_filename(base_dir, "hyphen"));
                dirs.add(Path.build_filename(base_dir, "myspell", "dicts"));
                dirs.add(Path.build_filename(base_dir, "hunspell"));
                dirs.add(Path.build_filename(base_dir, "texmf", "tex", "generic", "hyph-utf8", "patterns", "txt"));
                dirs.add(Path.build_filename(base_dir, "texlive", "texmf-dist", "tex", "generic", "hyph-utf8", "patterns", "txt"));
                dirs.add(Path.build_filename(base_dir, "texlive", "texmf-dist", "tex", "generic", "hyph-utf8", "patterns", "tex"));
            }
        }

        public void register(string lang, HyphenPatterns p) {
            cache[norm(lang)] = p;
        }

        private static string norm(string lang) {
            return lang.replace("-", "_").down();
        }

        public bool available(string lang) {
            return patterns(lang) != null;
        }

        public HyphenPatterns? patterns(string lang) {
            string key = norm(lang == "" ? default_lang() : lang);
            if (cache.has_key(key)) return cache[key];
            HyphenPatterns? found = null;
            string[] parts = key.split("_");
            string ll = parts[0];
            string full = parts.length > 1 ? "%s_%s".printf(ll, parts[1].up()) : ll;
            string[] names = {
                "hyph_%s.dic".printf(full), "hyph_%s.dic".printf(ll), "hyph-%s.pat.txt".printf(key.replace("_", "-")),
                "hyph-%s.pat.txt".printf(ll), "hyph-%s.tex".printf(key.replace("_", "-")), "hyph-%s.tex".printf(ll)
            };
            if (ll == "en") names += "hyph-en-us.pat.txt";
            foreach (string d in dirs) {
                foreach (string n in names) {
                    string path = Path.build_filename(d, n);
                    if (!FileUtils.test(path, FileTest.IS_REGULAR)) continue;
                    try {
                        string text;
                        FileUtils.get_contents(path, out text);
                        if (!text.validate()) text = Formats.decode_text(text.data);
                        found = HyphenPatterns.parse(text, !n.has_suffix(".dic"));
                    } catch (Error e) {
                    }
                    if (found != null) break;
                }
                if (found != null) break;
            }
            cache[key] = found;
            return found;
        }

        public static string default_lang() {
            foreach (unowned string n in Intl.get_language_names()) {
                if (n == "C" || n.contains(".") || n.contains("@")) continue;
                return n;
            }
            return "en_US";
        }

        public Gee.HashSet<int>? points(string text, string lang) {
            var pat = patterns(lang);
            if (pat == null) return null;
            var result = new Gee.HashSet<int>();
            var word = new StringBuilder();
            int word_start = 0;
            int ci = 0;
            unichar c;
            int i = 0;
            while (true) {
                bool more = text.get_next_char(ref i, out c);
                if (more && c.isalpha()) {
                    if (word.len == 0) word_start = ci;
                    word.append_unichar(c);
                    ci++;
                    continue;
                }
                if (word.len > 0) {
                    int n = word.str.char_count();
                    if (n >= pat.leftmin + pat.rightmin) {
                        int[] pts = pat.word_points(word.str);
                        for (int k = pat.leftmin; k <= n - pat.rightmin; k++) {
                            if ((pts[k] & 1) == 1) result.add(word_start + k);
                        }
                    }
                    word.truncate(0);
                }
                if (!more) break;
                ci++;
            }
            return result;
        }

        public string hyphenate_word(string word, string lang) {
            var pts = points(word, lang);
            if (pts == null) return word;
            var sb = new StringBuilder();
            int ci = 0;
            unichar c;
            int i = 0;
            while (word.get_next_char(ref i, out c)) {
                if (pts.contains(ci)) sb.append_c('-');
                sb.append_unichar(c);
                ci++;
            }
            return sb.str;
        }
    }
}
