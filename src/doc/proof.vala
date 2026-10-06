namespace Write {

    public class Issue : Object {
        public Paragraph para;
        public int start;
        public int end;
        public string message;
        public string[] suggestions = {};
        public string kind;

        public Issue(Paragraph para, int start, int end, string kind, string message) {
            this.para = para;
            this.start = start;
            this.end = end;
            this.kind = kind;
            this.message = message;
        }
    }

    public class GrammarChecker : Object {
        private struct Rule {
            public string pattern;
            public string replacement;
            public string message;
        }

        private Gee.HashMap<string, Regex> compiled = new Gee.HashMap<string, Regex>();

        private Regex re(string p) {
            if (!compiled.has_key(p)) {
                try {
                    compiled[p] = new Regex(p, RegexCompileFlags.OPTIMIZE);
                } catch (RegexError e) {
                    try {
                        compiled[p] = new Regex("(?!)");
                    } catch (RegexError e2) {
                    }
                }
            }
            return compiled[p];
        }

        private static Rule[] english_rules() {
            return {
                Rule() { pattern = "(?i)\\b(could|should|would|must|might) of\\b", replacement = "\\1 have", message = _("Use \u201chave\u201d after this verb.") },
                Rule() { pattern = "(?i)\\balot\\b", replacement = "a lot", message = _("\u201cA lot\u201d is written as two words.") },
                Rule() { pattern = "(?i)\\b(more|less|better|worse|rather|other) then\\b", replacement = "\\1 than", message = _("Use \u201cthan\u201d for comparisons.") },
                Rule() { pattern = "(?i)\\byour welcome\\b", replacement = "you're welcome", message = _("Did you mean \u201cyou're\u201d?") },
                Rule() { pattern = "(?i)\\btheir (is|are|was|were)\\b", replacement = "there \\1", message = _("Did you mean \u201cthere\u201d?") },
                Rule() { pattern = "(?i)\\bits (a|the|been|not|going)\\b", replacement = "it's \\1", message = _("Did you mean \u201cit's\u201d (it is)?") },
                Rule() { pattern = "(?i)\\bin order to\\b", replacement = "to", message = _("Wordy: consider \u201cto\u201d.") },
                Rule() { pattern = "(?i)\\bat this point in time\\b", replacement = "now", message = _("Wordy: consider \u201cnow\u201d.") },
                Rule() { pattern = "(?i)\\bdue to the fact that\\b", replacement = "because", message = _("Wordy: consider \u201cbecause\u201d.") },
                Rule() { pattern = "(?i)\\bthe reason why is because\\b", replacement = "because", message = _("Redundant phrase.") },
                Rule() { pattern = "(?i)\\bshould of\\b", replacement = "should have", message = _("Use \u201chave\u201d after this verb.") },
                Rule() { pattern = "(?i)\\beach and every\\b", replacement = "every", message = _("Redundant phrase.") },
                Rule() { pattern = "(?i)\\bfree gift\\b", replacement = "gift", message = _("Redundant phrase.") },
                Rule() { pattern = "(?i)\\bi\\b(?=[ ,.;:!?'])", replacement = "I", message = _("The pronoun \u201cI\u201d is always capitalized.") }
            };
        }

        private static Rule[] italian_rules() {
            return {
                Rule() { pattern = "(?i)\\bqual'\u00e8\\b", replacement = "qual \u00e8", message = _("\u201cQual \u00e8\u201d is written without an apostrophe.") },
                Rule() { pattern = "\\bp\u00f2\\b", replacement = "po'", message = _("\u201cPo'\u201d is written with an apostrophe.") },
                Rule() { pattern = "(?i)\\bperch\u00e8\\b", replacement = "perch\u00e9", message = _("Use the acute accent: \u201cperch\u00e9\u201d.") },
                Rule() { pattern = "(?i)\\bpoich\u00e8\\b", replacement = "poich\u00e9", message = _("Use the acute accent: \u201cpoich\u00e9\u201d.") },
                Rule() { pattern = "(?i)\\bn\u00e8\\b", replacement = "n\u00e9", message = _("Use the acute accent: \u201cn\u00e9\u201d.") },
                Rule() { pattern = "\\bE' ", replacement = "\u00c8 ", message = _("Use the accented capital \u201c\u00c8\u201d.") },
                Rule() { pattern = "(?i)\\bun'altro\\b", replacement = "un altro", message = _("Masculine \u201cun altro\u201d takes no apostrophe.") },
                Rule() { pattern = "(?i)\\bsopratutto\\b", replacement = "soprattutto", message = _("The correct spelling is \u201csoprattutto\u201d.") }
            };
        }

        public Gee.ArrayList<Issue> check(Paragraph p, string lang) {
            var list = new Gee.ArrayList<Issue>();
            string t = p.plain_text(false);
            if (t.strip() == "") return list;
            string text = p.text();
            bool it = lang.has_prefix("it");
            repeated_words(p, text, list);
            spacing(p, text, list);
            capitalization(p, text, list);
            if (!it) articles(p, text, list);
            foreach (var r in it ? italian_rules() : english_rules()) {
                if (r.message == "") continue;
                pattern_rule(p, text, r.pattern, r.replacement, r.message, list);
            }
            long_sentences(p, text, list);
            brackets(p, text, list);
            return list;
        }

        private void add(Gee.ArrayList<Issue> list, Paragraph p, string text, int bs, int be, string kind, string msg, string[] sugg) {
            int s = text.substring(0, bs).char_count();
            int e = s + text.substring(bs, be - bs).char_count();
            var i = new Issue(p, s, e, kind, msg);
            i.suggestions = sugg;
            list.add(i);
        }

        private void each(Regex r, string text, owned MatchFunc fn) {
            MatchInfo mi;
            if (!r.match(text, 0, out mi)) return;
            while (mi.matches()) {
                int bs, be;
                mi.fetch_pos(0, out bs, out be);
                fn(mi, bs, be);
                try {
                    if (!mi.next()) break;
                } catch (RegexError e) {
                    break;
                }
            }
        }

        private delegate void MatchFunc(MatchInfo mi, int bs, int be);

        private void repeated_words(Paragraph p, string text, Gee.ArrayList<Issue> list) {
            each(re("(?i)\\b(\\w+)(\\s+)\\1\\b"), text, (mi, bs, be) => {
                string w = mi.fetch(1);
                if (w.down() == "had" || w.down() == "that") return;
                add(list, p, text, bs, be, "grammar", _("Repeated word: \u201c%s\u201d.").printf(w), { w });
            });
        }

        private void spacing(Paragraph p, string text, Gee.ArrayList<Issue> list) {
            each(re("(?<=\\S)  +(?=\\S)"), text, (mi, bs, be) => {
                add(list, p, text, bs, be, "style", _("Multiple spaces between words."), { " " });
            });
            each(re("(?<=\\w) +(?=[,.;:!?](\\s|$))"), text, (mi, bs, be) => {
                add(list, p, text, bs, be, "grammar", _("Remove the space before punctuation."), { "" });
            });
            each(re("(?<=[a-z])[,;](?=[A-Za-z])"), text, (mi, bs, be) => {
                string punct = mi.fetch(0);
                add(list, p, text, bs, be, "grammar", _("Add a space after punctuation."), { punct + " " });
            });
        }

        private void capitalization(Paragraph p, string text, Gee.ArrayList<Issue> list) {
            each(re("(?:^|[.!?]\\s+)([a-z])"), text, (mi, bs, be) => {
                int s, e;
                mi.fetch_pos(1, out s, out e);
                if (s == 0 && p.style.has_prefix("TOC")) return;
                string before = text.substring(0, int.max(0, s)).strip();
                if (before.has_suffix("e.g.") || before.has_suffix("i.e.") || before.has_suffix("etc.") || before.has_suffix("vs.") || before.has_suffix("ecc.")) return;
                string letter = mi.fetch(1);
                add(list, p, text, s, e, "grammar", _("Sentences should start with a capital letter."), { letter.up() });
            });
        }

        private void articles(Paragraph p, string text, Gee.ArrayList<Issue> list) {
            each(re("\\b([Aa]) ([aeiouAEIOU]\\w*)"), text, (mi, bs, be) => {
                string w = mi.fetch(2).down();
                if (w.has_prefix("uni") || w.has_prefix("use") || w.has_prefix("usu") || w.has_prefix("eu") || w.has_prefix("one") || w.has_prefix("once") || w.has_prefix("ufo")) return;
                int s, e;
                mi.fetch_pos(1, out s, out e);
                string a = mi.fetch(1);
                add(list, p, text, s, e, "grammar", _("Use \u201can\u201d before a vowel sound."), { a == "A" ? "An" : "an" });
            });
            each(re("\\b([Aa]n) ([b-df-hj-np-tv-zB-DF-HJ-NP-TV-Z]\\w*)"), text, (mi, bs, be) => {
                string w = mi.fetch(2).down();
                if (w.has_prefix("hour") || w.has_prefix("honest") || w.has_prefix("honor") || w.has_prefix("honour") || w.has_prefix("heir") || w.length <= 1) return;
                int s, e;
                mi.fetch_pos(1, out s, out e);
                string a = mi.fetch(1);
                add(list, p, text, s, e, "grammar", _("Use \u201ca\u201d before a consonant sound."), { a == "An" ? "A" : "a" });
            });
        }

        private void pattern_rule(Paragraph p, string text, string pattern, string replacement, string message, Gee.ArrayList<Issue> list) {
            var r = re(pattern);
            each(r, text, (mi, bs, be) => {
                string rep = replacement;
                for (int g = 1; g < 4; g++) {
                    string? v = mi.fetch(g);
                    if (v != null) rep = rep.replace("\\%d".printf(g), v);
                }
                string orig = mi.fetch(0);
                if (orig.length > 0 && rep.length > 0 && orig.get_char(0).isupper() && !rep.get_char(0).isupper()) rep = rep.get_char(0).toupper().to_string() + rep.substring(rep.index_of_nth_char(1));
                if (rep == orig) return;
                add(list, p, text, bs, be, "grammar", message, { rep });
            });
        }

        private void long_sentences(Paragraph p, string text, Gee.ArrayList<Issue> list) {
            each(re("[^.!?]+[.!?]?"), text, (mi, bs, be) => {
                string s = mi.fetch(0);
                if (Stats.count_words(s) > 45) add(list, p, text, bs, be, "style", _("Long sentence: consider splitting it."), {});
            });
        }

        private void brackets(Paragraph p, string text, Gee.ArrayList<Issue> list) {
            int depth = 0;
            int quotes = 0;
            unichar c;
            int i = 0;
            while (text.get_next_char(ref i, out c)) {
                if (c == '(') depth++;
                else if (c == ')') depth--;
                else if (c == '"') quotes++;
            }
            if (depth != 0) add(list, p, text, 0, text.length, "grammar", _("Unbalanced parentheses in this paragraph."), {});
            if (quotes % 2 != 0) add(list, p, text, 0, text.length, "grammar", _("Unbalanced quotation marks in this paragraph."), {});
        }
    }

    public class Thesaurus : Object {
        private static Thesaurus? instance = null;
        public Gee.ArrayList<string> dirs = new Gee.ArrayList<string>();
        private Gee.HashMap<string, string?> files = new Gee.HashMap<string, string?>();

        public static Thesaurus get_default() {
            if (instance == null) instance = new Thesaurus();
            return instance;
        }

        public Thesaurus() {
            string? extra = Environment.get_variable("SINGULARITY_THESAURUS_DIRS");
            if (extra != null) foreach (string d in extra.split(":")) if (d != "") dirs.add(d);
            dirs.add(Path.build_filename(Environment.get_user_data_dir(), "mythes"));
            foreach (string base_dir in Environment.get_system_data_dirs()) {
                dirs.add(Path.build_filename(base_dir, "mythes"));
                dirs.add(Path.build_filename(base_dir, "myspell", "dicts"));
                dirs.add(Path.build_filename(base_dir, "hunspell"));
                dirs.add(Path.build_filename(base_dir, "libreoffice", "share", "extensions"));
            }
        }

        public string? file_for(string lang) {
            string key = lang.replace("-", "_");
            if (files.has_key(key)) return files[key];
            string[] parts = key.split("_");
            string[] names = { "th_%s_v2.dat".printf(key), "th_%s.dat".printf(key) };
            if (parts.length > 1) {
                names += "th_%s_%s_v2.dat".printf(parts[0], parts[1].up());
                names += "th_%s_%s.dat".printf(parts[0], parts[1].up());
            }
            names += "th_%s_v2.dat".printf(parts[0]);
            names += "th_%s.dat".printf(parts[0]);
            string? found = null;
            foreach (string d in dirs) {
                foreach (string n in names) {
                    string pth = Path.build_filename(d, n);
                    if (FileUtils.test(pth, FileTest.IS_REGULAR)) {
                        found = pth;
                        break;
                    }
                }
                if (found != null) break;
            }
            files[key] = found;
            return found;
        }

        public class Meaning : Object {
            public string pos;
            public string[] synonyms;
        }

        public Gee.ArrayList<Meaning> lookup(string word, string lang) {
            var result = new Gee.ArrayList<Meaning>();
            string? path = file_for(lang);
            if (path == null) return result;
            try {
                string data;
                FileUtils.get_contents(path, out data);
                if (!data.validate()) data = Formats.decode_text(data.data);
                string needle = word.down().strip();
                string[] lines = data.split("\n");
                for (int i = 1; i < lines.length; i++) {
                    string l = lines[i];
                    int bar = l.index_of_char('|');
                    if (bar < 0 || l.has_prefix("(")) continue;
                    if (l.substring(0, bar).down() != needle) continue;
                    int n = int.parse(l.substring(bar + 1));
                    for (int k = 1; k <= n && i + k < lines.length; k++) {
                        string[] parts = lines[i + k].strip().split("|");
                        if (parts.length < 2) continue;
                        var m = new Meaning();
                        m.pos = parts[0].replace("(", "").replace(")", "");
                        string[] syn = {};
                        for (int j = 1; j < parts.length; j++) if (parts[j].strip() != "") syn += parts[j].strip();
                        m.synonyms = syn;
                        result.add(m);
                    }
                    break;
                }
            } catch (Error e) {
            }
            return result;
        }
    }

    public class AutoCorrect : Object {
        private static AutoCorrect? instance = null;
        public Gee.TreeMap<string, string> entries = new Gee.TreeMap<string, string>();
        public bool capitalize_sentences = true;
        public bool two_initial_caps = true;
        public bool capitalize_days = true;
        public bool replace_text = true;
        public bool auto_lists = true;
        public bool smart_quotes = true;
        public bool auto_hyperlinks = true;
        public string path;

        public static AutoCorrect get_default() {
            if (instance == null) {
                instance = new AutoCorrect(Path.build_filename(Environment.get_user_config_dir(), "singularity-write", "autocorrect.json"));
                instance.load();
            }
            return instance;
        }

        public AutoCorrect(string path) {
            this.path = path;
            defaults();
        }

        public void defaults() {
            entries.clear();
            string[,] d = {
                { "(c)", "\u00a9" }, { "(r)", "\u00ae" }, { "(tm)", "\u2122" }, { "...", "\u2026" }, { "--", "\u2013" },
                { "1/2", "\u00bd" }, { "1/4", "\u00bc" }, { "3/4", "\u00be" }, { "+-", "\u00b1" }, { "!=", "\u2260" },
                { "teh", "the" }, { "adn", "and" }, { "recieve", "receive" }, { "seperate", "separate" }, { "definately", "definitely" },
                { "occured", "occurred" }, { "untill", "until" }, { "wich", "which" }, { "becuase", "because" }, { "thier", "their" },
                { "dont", "don't" }, { "doesnt", "doesn't" }, { "cant", "can't" }, { "wont", "won't" }, { "isnt", "isn't" },
                { "perch\u00e8", "perch\u00e9" }, { "poich\u00e8", "poich\u00e9" }, { "qual'\u00e8", "qual \u00e8" }, { "p\u00f2", "po'" }, { "sopratutto", "soprattutto" }
            };
            for (int i = 0; i < d.length[0]; i++) entries[d[i, 0]] = d[i, 1];
        }

        public void load() {
            try {
                if (!FileUtils.test(path, FileTest.EXISTS)) return;
                var parser = new Json.Parser();
                parser.load_from_file(path);
                var o = parser.get_root().get_object();
                if (o.has_member("entries")) {
                    entries.clear();
                    var e = o.get_object_member("entries");
                    foreach (string k in e.get_members()) entries[k] = e.get_string_member(k);
                }
                if (o.has_member("capitalize_sentences")) capitalize_sentences = o.get_boolean_member("capitalize_sentences");
                if (o.has_member("two_initial_caps")) two_initial_caps = o.get_boolean_member("two_initial_caps");
                if (o.has_member("capitalize_days")) capitalize_days = o.get_boolean_member("capitalize_days");
                if (o.has_member("replace_text")) replace_text = o.get_boolean_member("replace_text");
                if (o.has_member("auto_lists")) auto_lists = o.get_boolean_member("auto_lists");
                if (o.has_member("smart_quotes")) smart_quotes = o.get_boolean_member("smart_quotes");
                if (o.has_member("auto_hyperlinks")) auto_hyperlinks = o.get_boolean_member("auto_hyperlinks");
            } catch (Error e) {
            }
        }

        public void save() throws Error {
            var b = new Json.Builder();
            b.begin_object();
            b.set_member_name("entries");
            b.begin_object();
            foreach (var e in entries.entries) {
                b.set_member_name(e.key);
                b.add_string_value(e.value);
            }
            b.end_object();
            b.set_member_name("capitalize_sentences");
            b.add_boolean_value(capitalize_sentences);
            b.set_member_name("two_initial_caps");
            b.add_boolean_value(two_initial_caps);
            b.set_member_name("capitalize_days");
            b.add_boolean_value(capitalize_days);
            b.set_member_name("replace_text");
            b.add_boolean_value(replace_text);
            b.set_member_name("auto_lists");
            b.add_boolean_value(auto_lists);
            b.set_member_name("smart_quotes");
            b.add_boolean_value(smart_quotes);
            b.set_member_name("auto_hyperlinks");
            b.add_boolean_value(auto_hyperlinks);
            b.end_object();
            var g = new Json.Generator();
            g.pretty = true;
            g.set_root(b.get_root());
            DirUtils.create_with_parents(Path.get_dirname(path), 0755);
            g.to_file(path);
        }

        public bool correct(string text_before, out int remove, out string insert) {
            remove = 0;
            insert = "";
            int end = text_before.length;
            int start = end;
            while (start > 0 && text_before[start - 1] != ' ' && text_before[start - 1] != '\t' && text_before[start - 1] != '\n') start--;
            string word = text_before.substring(start, end - start);
            if (word == "") return false;
            if (replace_text) {
                string? rep = entries[word] ?? entries[word.down()];
                if (rep != null) {
                    if (entries[word] == null && word.get_char(0).isupper()) rep = rep.get_char(0).toupper().to_string() + rep.substring(rep.index_of_nth_char(1));
                    remove = word.char_count();
                    insert = rep;
                    return true;
                }
                foreach (var e in entries.entries) {
                    if (e.key.length > 1 && !e.key.get_char(0).isalnum() && word.has_suffix(e.key)) {
                        remove = e.key.char_count();
                        insert = e.value;
                        return true;
                    }
                }
            }
            if (two_initial_caps && word.char_count() > 2) {
                unichar a = word.get_char(0);
                unichar b = word.get_char(word.index_of_nth_char(1));
                unichar c = word.get_char(word.index_of_nth_char(2));
                if (a.isupper() && b.isupper() && c.islower()) {
                    remove = word.char_count();
                    insert = a.to_string() + b.tolower().to_string() + word.substring(word.index_of_nth_char(2));
                    return true;
                }
            }
            if (capitalize_days) {
                string[] days = { "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday" };
                foreach (string dname in days) {
                    if (word == dname) {
                        remove = word.char_count();
                        insert = dname.get_char(0).toupper().to_string() + dname.substring(1);
                        return true;
                    }
                }
            }
            if (capitalize_sentences && word.get_char(0).islower()) {
                string before = text_before.substring(0, start).strip();
                bool sentence_start = before == "" || before.has_suffix(".") || before.has_suffix("!") || before.has_suffix("?");
                if (before.has_suffix("e.g.") || before.has_suffix("i.e.") || before.has_suffix("etc.") || before.has_suffix("...")) sentence_start = false;
                if (sentence_start && word.get_char(0).isalpha() && !word.contains("@") && !word.contains("://") && !word.contains(".")) {
                    remove = word.char_count();
                    insert = word.get_char(0).toupper().to_string() + word.substring(word.index_of_nth_char(1));
                    return true;
                }
            }
            return false;
        }
    }

    public class AccessibilityChecker : Object {
        public class Finding : Object {
            public string severity;
            public string title;
            public string detail;
            public Paragraph? para;
            public Inline? item;
            public Table? table;
            public string fix;
        }

        private static double lum(string hex) {
            double r, g, b;
            Palette.rgbd(hex, out r, out g, out b);
            double[] c = { r, g, b };
            for (int i = 0; i < 3; i++) c[i] = c[i] <= 0.03928 ? c[i] / 12.92 : Math.pow((c[i] + 0.055) / 1.055, 2.4);
            return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
        }

        public static double contrast(string fg, string bg) {
            double a = lum(fg) + 0.05;
            double b = lum(bg) + 0.05;
            return a > b ? a / b : b / a;
        }

        public static Gee.ArrayList<Finding> check(Document doc) {
            var list = new Gee.ArrayList<Finding>();
            if (doc.meta.title.strip() == "") list.add(finding("warning", _("Missing document title"), _("Set a title in the document properties so assistive technology can announce it."), null, null, "properties"));
            int last_level = -1;
            bool any_heading = false;
            foreach (var b in doc.body.items) {
                var p = b as Paragraph;
                if (p != null) {
                    int lvl = doc.styles.outline_level(p);
                    if (lvl >= 0 && p.style.has_prefix("Heading")) {
                        any_heading = true;
                        if (p.plain_text().strip() == "") list.add(finding("warning", _("Empty heading"), _("Headings should contain text."), p, null, "goto"));
                        if (last_level >= 0 && lvl > last_level + 1) list.add(finding("warning", _("Skipped heading level"), _("A heading level %d follows a level %d heading.").printf(lvl + 1, last_level + 1), p, null, "goto"));
                        last_level = lvl;
                    }
                    check_para(doc, p, list);
                    continue;
                }
                var t = b as Table;
                if (t != null) {
                    bool header = t.rows.size > 0 && t.rows[0].header;
                    if (!header) {
                        var f = finding("error", _("Table without header row"), _("Mark the first row as a header row so it is read correctly and repeats on each page."), t.rows.size > 0 && t.rows[0].cells.size > 0 ? t.rows[0].cells[0].blocks.first_paragraph() : null, null, "header-row");
                        f.table = t;
                        list.add(f);
                    }
                    bool merged = false;
                    foreach (var r in t.rows) foreach (var c in r.cells) if (c.vmerge != VMerge.NONE) merged = true;
                    if (merged) {
                        var f = finding("tip", _("Merged cells"), _("Merged cells can make navigation harder for screen readers."), t.rows[0].cells[0].blocks.first_paragraph(), null, "goto");
                        f.table = t;
                        list.add(f);
                    }
                    if (t.description == "" && t.caption == "") {
                        var f = finding("tip", _("Table without alternative text"), _("Describe the table content."), t.rows[0].cells[0].blocks.first_paragraph(), null, "table-alt");
                        f.table = t;
                        list.add(f);
                    }
                    foreach (var r in t.rows) foreach (var c in r.cells) foreach (var cp in Story.paragraphs(c.blocks)) check_para(doc, cp, list);
                }
            }
            if (!any_heading && Stats.compute(doc, false).words > 400) list.add(finding("tip", _("No headings"), _("Long documents are easier to navigate with headings."), null, null, "none"));
            return list;
        }

        private static void check_para(Document doc, Paragraph p, Gee.ArrayList<Finding> list) {
            string bg = doc.page_color ?? "#ffffff";
            foreach (var it in p.inlines) {
                var fl = it as FloatingInline;
                if (fl != null && fl.alt.strip() == "" && !(it is ShapeRun && ((ShapeRun) it).text.size > 0 && !((ShapeRun) it).text.first_paragraph().is_empty())) {
                    list.add(finding("error", (it is ImageRun) ? _("Missing alternative text for a picture") : _("Missing alternative text for a shape"), _("Describe the object so people who cannot see it understand it."), p, it, "alt"));
                    if (fl.wrap != Wrap.INLINE && fl.wrap != Wrap.TOP_BOTTOM && fl.wrap != Wrap.SQUARE) list.add(finding("tip", _("Floating object"), _("Objects placed in front of or behind text can be skipped by screen readers."), p, it, "inline"));
                }
                var eq = it as EquationRun;
                if (eq != null && eq.linear_text() == "") list.add(finding("tip", _("Equation without text"), _("The equation has no readable text."), p, it, "goto"));
                var tr = it as TextRun;
                if (tr != null) {
                    var c = doc.styles.resolve_char(p, tr.props);
                    if (c.color != null) {
                        string back = c.highlight != null && c.highlight != "none" ? c.highlight : (c.shading ?? bg);
                        double ratio = contrast(c.color, back);
                        double size = c.size > 0 ? c.size : 11;
                        double need = size >= 18 || (size >= 14 && c.bold.on()) ? 3.0 : 4.5;
                        if (ratio < need) list.add(finding("warning", _("Hard to read text contrast"), _("Contrast ratio %.1f:1 is below %.1f:1.").printf(ratio, need), p, it, "goto"));
                    }
                    if (c.link != null) {
                        string lt = tr.text.strip().down();
                        if (lt == "click here" || lt == "here" || lt == "link" || lt == "qui" || lt == "clicca qui" || lt.has_prefix("http")) list.add(finding("tip", _("Unclear link text"), _("Link text should describe the destination."), p, it, "goto"));
                    }
                }
            }
            string text = p.plain_text();
            if (text.has_prefix("    ") || text.contains("     ")) list.add(finding("tip", _("Repeated blank characters"), _("Use indentation and tab stops instead of spaces for layout."), p, null, "goto"));
        }

        private static Finding finding(string sev, string title, string detail, Paragraph? p, Inline? item, string fix) {
            var f = new Finding();
            f.severity = sev;
            f.title = title;
            f.detail = detail;
            f.para = p;
            f.item = item;
            f.fix = fix;
            return f;
        }
    }
}
