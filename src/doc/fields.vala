namespace Write {

    public delegate string? LookupFunc(string name);
    public delegate double[] CellValuesFunc(string direction);

    public class FieldContext : Object {
        public Document doc;
        public int page = 1;
        public int pages = 1;
        public int section_pages = 1;
        public int section = 1;
        public NumFormat page_format = NumFormat.DECIMAL;
        public string filename = "";
        public string filepath = "";
        public DateTime now;
        public Gee.HashMap<string, int> seq = new Gee.HashMap<string, int>();
        public Gee.HashMap<string, string> bookmark_text = new Gee.HashMap<string, string>();
        public Gee.HashMap<string, int> bookmark_page = new Gee.HashMap<string, int>();
        public Gee.HashMap<string, string> note_numbers = new Gee.HashMap<string, string>();
        public Gee.HashMap<string, string>? record = null;
        public Gee.HashMap<string, string> seq_labels = new Gee.HashMap<string, string>();
        public unowned CellValuesFunc? cells = null;

        public FieldContext(Document doc) {
            this.doc = doc;
            now = new DateTime.now_local();
        }
    }

    public class Fields : Object {

        public static string[] tokenize(string code) {
            string[] out_tokens = {};
            var sb = new StringBuilder();
            bool quoted = false;
            bool had = false;
            unichar c;
            int i = 0;
            while (code.get_next_char(ref i, out c)) {
                if (c == '"' || c == 0x201C || c == 0x201D) {
                    quoted = !quoted;
                    had = true;
                    continue;
                }
                if (!quoted && c.isspace()) {
                    if (sb.len > 0 || had) {
                        out_tokens += sb.str;
                        sb.truncate(0);
                        had = false;
                    }
                    continue;
                }
                if (c == '\\' && !quoted && sb.len > 0) {
                    out_tokens += sb.str;
                    sb.truncate(0);
                }
                sb.append_unichar(c);
            }
            if (sb.len > 0 || had) out_tokens += sb.str;
            return out_tokens;
        }

        public static string? switch_arg(string[] toks, string sw) {
            for (int i = 0; i < toks.length; i++) {
                if (toks[i].down() == sw.down() && i + 1 < toks.length) return toks[i + 1];
            }
            return null;
        }

        public static bool has_switch(string[] toks, string sw) {
            foreach (var t in toks) if (t.down() == sw.down()) return true;
            return false;
        }

        public static string[] format_switches(string[] toks) {
            string[] res = {};
            for (int i = 0; i < toks.length; i++) {
                if (toks[i] == "\\*" && i + 1 < toks.length) res += toks[i + 1];
            }
            return res;
        }

        public static string apply_format(string value, string[] toks) {
            string v = value;
            foreach (string f in format_switches(toks)) {
                int n = 0;
                bool numeric = int.try_parse(v.strip(), out n);
                switch (f) {
                    case "ROMAN": if (numeric) v = Numbering.roman(n); break;
                    case "roman": if (numeric) v = Numbering.roman(n).down(); break;
                    case "ALPHABETIC": if (numeric) v = Numbering.letters(n); break;
                    case "alphabetic": if (numeric) v = Numbering.letters(n).down(); break;
                    case "Ordinal": if (numeric) v = Numbering.ordinal(n); break;
                    case "Arabic":
                    case "ARABIC": break;
                    case "Upper": v = v.up(); break;
                    case "Lower": v = v.down(); break;
                    case "FirstCap": if (v.length > 0) v = v.substring(0, v.index_of_nth_char(1)).up() + v.substring(v.index_of_nth_char(1)); break;
                    case "Caps": v = title_case(v); break;
                    default: break;
                }
            }
            string? pic = switch_arg(toks, "\\#");
            if (pic != null) {
                double d;
                if (double.try_parse(v.strip().replace(",", ""), out d)) v = number_picture(d, pic);
            }
            return v;
        }

        public static string title_case(string s) {
            var sb = new StringBuilder();
            bool start = true;
            unichar c;
            int i = 0;
            while (s.get_next_char(ref i, out c)) {
                sb.append_unichar(start ? c.toupper() : c);
                start = c.isspace();
            }
            return sb.str;
        }

        public static string number_picture(double d, string pic) {
            int decimals = 0;
            int dot = pic.index_of_char('.');
            if (dot >= 0) {
                for (int i = dot + 1; i < pic.length && (pic[i] == '0' || pic[i] == '#'); i++) decimals++;
            }
            bool grouping = pic.contains(",");
            string num = fixed(d.abs(), decimals);
            string ip = num;
            string fp = "";
            int nd = num.index_of_char('.');
            if (nd >= 0) {
                ip = num.substring(0, nd);
                fp = num.substring(nd + 1);
            }
            if (grouping) {
                var g = new StringBuilder();
                int cnt = 0;
                for (int i = ip.length - 1; i >= 0; i--) {
                    g.prepend_c(ip[i]);
                    if (++cnt % 3 == 0 && i > 0) g.prepend_c(',');
                }
                ip = g.str;
            }
            string prefix = "";
            foreach (string cur in new string[] { "$", "\u20ac", "\u00a3" }) if (pic.has_prefix(cur)) prefix = cur;
            string res = prefix + ip + (fp != "" ? "." + fp : "");
            return d < 0 ? "-" + res : res;
        }

        public static string fixed(double v, int decimals) {
            double p = Math.pow(10, decimals);
            int64 scaled = (int64) Math.round(v * p);
            if (decimals == 0) return scaled.to_string();
            string digits = scaled.to_string();
            while (digits.length <= decimals) digits = "0" + digits;
            return digits.substring(0, digits.length - decimals) + "." + digits.substring(digits.length - decimals);
        }

        public static string date_picture(DateTime dt, string pic) {
            var sb = new StringBuilder();
            int i = 0;
            int n = pic.length;
            while (i < n) {
                char c = pic[i];
                if (c == '\'') {
                    int j = pic.index_of_char('\'', i + 1);
                    if (j < 0) j = n;
                    sb.append(pic.substring(i + 1, j - i - 1));
                    i = j + 1;
                    continue;
                }
                int run = 1;
                while (i + run < n && pic[i + run] == c) run++;
                switch (c) {
                    case 'd':
                        if (run == 1) sb.append(dt.get_day_of_month().to_string());
                        else if (run == 2) sb.append("%02d".printf(dt.get_day_of_month()));
                        else if (run == 3) sb.append(dt.format("%a"));
                        else sb.append(dt.format("%A"));
                        break;
                    case 'M':
                        if (run == 1) sb.append(dt.get_month().to_string());
                        else if (run == 2) sb.append("%02d".printf(dt.get_month()));
                        else if (run == 3) sb.append(dt.format("%b"));
                        else sb.append(dt.format("%B"));
                        break;
                    case 'y':
                        if (run <= 2) sb.append("%02d".printf(dt.get_year() % 100));
                        else sb.append(dt.get_year().to_string());
                        break;
                    case 'H':
                        sb.append(run >= 2 ? "%02d".printf(dt.get_hour()) : dt.get_hour().to_string());
                        break;
                    case 'h':
                        int h12 = dt.get_hour() % 12;
                        if (h12 == 0) h12 = 12;
                        sb.append(run >= 2 ? "%02d".printf(h12) : h12.to_string());
                        break;
                    case 'm':
                        sb.append(run >= 2 ? "%02d".printf(dt.get_minute()) : dt.get_minute().to_string());
                        break;
                    case 's':
                        sb.append(run >= 2 ? "%02d".printf(dt.get_second()) : dt.get_second().to_string());
                        break;
                    case 'a':
                    case 'A':
                        if (pic.substring(i).down().has_prefix("am/pm")) {
                            string ap = dt.get_hour() < 12 ? "AM" : "PM";
                            sb.append(c == 'a' ? ap.down() : ap);
                            i += 5;
                            continue;
                        }
                        sb.append_c(c);
                        run = 1;
                        break;
                    default:
                        for (int k = 0; k < run; k++) sb.append_c(c);
                        break;
                }
                i += run;
            }
            return sb.str;
        }

        public static string evaluate(FieldRun f, FieldContext ctx) {
            string[] toks = tokenize(f.code);
            if (toks.length == 0) return f.result;
            string kind = f.code.strip().has_prefix("=") ? "=" : toks[0].up();
            string v;
            switch (kind) {
                case "PAGE":
                    v = Numbering.format_number(ctx.page, ctx.page_format);
                    break;
                case "NUMPAGES":
                    v = ctx.pages.to_string();
                    break;
                case "SECTIONPAGES":
                    v = ctx.section_pages.to_string();
                    break;
                case "SECTION":
                    v = ctx.section.to_string();
                    break;
                case "DATE":
                case "CREATEDATE":
                case "SAVEDATE":
                case "PRINTDATE":
                case "TIME":
                    string pic = switch_arg(toks, "\\@") ?? (kind == "TIME" ? "HH:mm" : "d MMMM yyyy");
                    DateTime dt = ctx.now;
                    if (kind == "CREATEDATE" && ctx.doc.meta.created != "") {
                        var p = new DateTime.from_iso8601(ctx.doc.meta.created, new TimeZone.utc());
                        if (p != null) dt = p.to_local();
                    } else if (kind == "SAVEDATE" && ctx.doc.meta.modified != "") {
                        var p = new DateTime.from_iso8601(ctx.doc.meta.modified, new TimeZone.utc());
                        if (p != null) dt = p.to_local();
                    }
                    v = date_picture(dt, pic);
                    break;
                case "AUTHOR":
                    v = ctx.doc.meta.author;
                    break;
                case "LASTSAVEDBY":
                    v = ctx.doc.meta.last_modified_by;
                    break;
                case "TITLE":
                    v = ctx.doc.meta.title;
                    break;
                case "SUBJECT":
                    v = ctx.doc.meta.subject;
                    break;
                case "KEYWORDS":
                    v = ctx.doc.meta.keywords;
                    break;
                case "COMMENTS":
                    v = ctx.doc.meta.description;
                    break;
                case "FILENAME":
                    v = has_switch(toks, "\\p") ? ctx.filepath : ctx.filename;
                    break;
                case "NUMWORDS":
                    v = Stats.compute(ctx.doc, false).words.to_string();
                    break;
                case "NUMCHARS":
                    v = Stats.compute(ctx.doc, false).chars_no_spaces.to_string();
                    break;
                case "DOCPROPERTY":
                    string name = toks.length > 1 ? toks[1] : "";
                    v = ctx.doc.meta.custom[name] ?? "";
                    break;
                case "DOCVARIABLE":
                    v = toks.length > 1 ? (ctx.doc.variables[toks[1]] ?? "") : "";
                    break;
                case "SEQ":
                    string id = toks.length > 1 ? toks[1] : "Figure";
                    int cur = ctx.seq.has_key(id) ? ctx.seq[id] : 0;
                    string? reset = switch_arg(toks, "\\r");
                    if (reset != null) cur = int.parse(reset) - 1;
                    if (!has_switch(toks, "\\c")) cur++;
                    ctx.seq[id] = cur;
                    v = has_switch(toks, "\\h") ? "" : cur.to_string();
                    break;
                case "REF":
                    string bm = toks.length > 1 ? toks[1] : "";
                    if (has_switch(toks, "\\n") || has_switch(toks, "\\r")) v = ctx.seq_labels[bm] ?? (ctx.bookmark_text[bm] ?? f.result);
                    else v = ctx.bookmark_text[bm] ?? f.result;
                    break;
                case "PAGEREF":
                    string pb = toks.length > 1 ? toks[1] : "";
                    v = ctx.bookmark_page.has_key(pb) ? ctx.bookmark_page[pb].to_string() : f.result;
                    break;
                case "NOTEREF":
                    string nb = toks.length > 1 ? toks[1] : "";
                    v = ctx.note_numbers[nb] ?? f.result;
                    break;
                case "MERGEFIELD":
                    string fname = toks.length > 1 ? toks[1] : "";
                    if (ctx.record != null) v = lookup_record(ctx.record, fname);
                    else v = "\u00ab" + fname + "\u00bb";
                    break;
                case "CITATION":
                    string tag = toks.length > 1 ? toks[1] : "";
                    v = Citations.cite(ctx.doc, tag, toks);
                    break;
                case "=":
                    string expr = f.code.strip().substring(1);
                    int sw = expr.index_of("\\#");
                    if (sw >= 0) expr = expr.substring(0, sw);
                    double r = Formula.eval(expr, ctx);
                    v = r.is_nan() ? _("!Syntax Error") : number_picture(r, r == Math.floor(r) ? "0" : "0.00");
                    break;
                case "USERNAME":
                    v = Environment.get_real_name();
                    break;
                case "QUOTE":
                    v = toks.length > 1 ? toks[1] : "";
                    break;
                case "SYMBOL":
                    int code = toks.length > 1 ? int.parse(toks[1]) : 0;
                    var sb = new StringBuilder();
                    if (code > 0) sb.append_unichar((unichar) code);
                    v = sb.str;
                    break;
                case "FILLIN":
                case "ASK":
                    v = f.result;
                    break;
                default:
                    return f.result;
            }
            if (kind != "=") v = apply_format(v, toks);
            return v;
        }

        private static string lookup_record(Gee.HashMap<string, string> record, string name) {
            if (record.has_key(name)) return record[name];
            string n = name.down();
            foreach (var e in record.entries) if (e.key.down() == n) return e.value;
            return "";
        }

        public static string display_name(string code) {
            string[] toks = tokenize(code);
            if (toks.length == 0) return code;
            switch (toks[0].up()) {
                case "PAGE": return _("Page Number");
                case "NUMPAGES": return _("Number of Pages");
                case "DATE": return _("Date");
                case "TIME": return _("Time");
                case "AUTHOR": return _("Author");
                case "TITLE": return _("Title");
                case "FILENAME": return _("File Name");
                case "MERGEFIELD": return toks.length > 1 ? toks[1] : _("Merge Field");
                case "REF": return _("Cross-reference");
                case "PAGEREF": return _("Page Reference");
                case "SEQ": return _("Sequence");
                case "CITATION": return _("Citation");
                default: return toks[0];
            }
        }
    }

    public class Formula : Object {
        private string s;
        private int pos;
        private FieldContext ctx;
        private bool error = false;

        private Formula(string s, FieldContext ctx) {
            this.s = s;
            this.ctx = ctx;
        }

        public static double eval(string expr, FieldContext ctx) {
            var f = new Formula(expr.strip(), ctx);
            double v = f.parse_cmp();
            f.skip();
            if (f.error || f.pos < f.s.length) return double.NAN;
            return v;
        }

        private void skip() {
            while (pos < s.length && s[pos].isspace()) pos++;
        }

        private bool accept(string t) {
            skip();
            if (s.substring(pos).has_prefix(t)) {
                pos += t.length;
                return true;
            }
            return false;
        }

        private double parse_cmp() {
            double a = parse_add();
            skip();
            if (accept("<=")) return a <= parse_add() ? 1 : 0;
            if (accept(">=")) return a >= parse_add() ? 1 : 0;
            if (accept("<>")) return a != parse_add() ? 1 : 0;
            if (accept("<")) return a < parse_add() ? 1 : 0;
            if (accept(">")) return a > parse_add() ? 1 : 0;
            if (accept("=")) return a == parse_add() ? 1 : 0;
            return a;
        }

        private double parse_add() {
            double a = parse_mul();
            while (true) {
                if (accept("+")) a += parse_mul();
                else if (accept("-")) a -= parse_mul();
                else break;
            }
            return a;
        }

        private double parse_mul() {
            double a = parse_pow();
            while (true) {
                if (accept("*")) a *= parse_pow();
                else if (accept("/")) {
                    double b = parse_pow();
                    a = b == 0 ? double.NAN : a / b;
                } else break;
            }
            return a;
        }

        private double parse_pow() {
            double a = parse_unary();
            if (accept("^")) a = Math.pow(a, parse_pow());
            return a;
        }

        private double parse_unary() {
            if (accept("-")) return -parse_unary();
            if (accept("+")) return parse_unary();
            return parse_atom();
        }

        private double[] parse_args() {
            double[] vals = {};
            if (!accept("(")) {
                error = true;
                return vals;
            }
            if (accept(")")) return vals;
            while (true) {
                skip();
                string rest = s.substring(pos).up();
                bool dir = false;
                foreach (string d in new string[] { "ABOVE", "BELOW", "LEFT", "RIGHT" }) {
                    if (rest.has_prefix(d)) {
                        pos += d.length;
                        if (ctx.cells != null) foreach (double x in ctx.cells(d)) vals += x;
                        dir = true;
                        break;
                    }
                }
                if (!dir) vals += parse_cmp();
                if (accept(",") || accept(";")) continue;
                if (accept(")")) break;
                error = true;
                break;
            }
            return vals;
        }

        private double parse_atom() {
            skip();
            if (accept("(")) {
                double v = parse_cmp();
                if (!accept(")")) error = true;
                return v;
            }
            int start = pos;
            if (pos < s.length && (s[pos].isdigit() || s[pos] == '.')) {
                while (pos < s.length && (s[pos].isdigit() || s[pos] == '.' || s[pos] == ',')) pos++;
                double d;
                if (!double.try_parse(s.substring(start, pos - start).replace(",", ""), out d)) error = true;
                if (pos < s.length && s[pos] == '%') {
                    pos++;
                    d /= 100;
                }
                return d;
            }
            while (pos < s.length && (s[pos].isalnum() || s[pos] == '_')) pos++;
            string name = s.substring(start, pos - start);
            if (name == "") {
                error = true;
                return 0;
            }
            string up = name.up();
            switch (up) {
                case "SUM":
                case "AVERAGE":
                case "MIN":
                case "MAX":
                case "COUNT":
                case "PRODUCT":
                case "ABS":
                case "ROUND":
                case "INT":
                case "MOD":
                case "SIGN":
                case "AND":
                case "OR":
                case "NOT":
                case "IF":
                case "TRUE":
                case "FALSE":
                case "DEFINED":
                    break;
                default:
                    string? t = ctx.bookmark_text[name];
                    double d = 0;
                    if (t != null && double.try_parse(t.strip().replace(",", ""), out d)) return d;
                    error = true;
                    return 0;
            }
            if (up == "TRUE") return 1;
            if (up == "FALSE") return 0;
            double[] a = parse_args();
            switch (up) {
                case "SUM": { double r = 0; foreach (var x in a) r += x; return r; }
                case "PRODUCT": { double r = 1; foreach (var x in a) r *= x; return r; }
                case "AVERAGE": { if (a.length == 0) return 0; double r = 0; foreach (var x in a) r += x; return r / a.length; }
                case "MIN": { if (a.length == 0) return 0; double r = a[0]; foreach (var x in a) r = double.min(r, x); return r; }
                case "MAX": { if (a.length == 0) return 0; double r = a[0]; foreach (var x in a) r = double.max(r, x); return r; }
                case "COUNT": return a.length;
                case "ABS": return a.length > 0 ? a[0].abs() : 0;
                case "INT": return a.length > 0 ? Math.floor(a[0]) : 0;
                case "SIGN": return a.length > 0 ? (a[0] > 0 ? 1 : (a[0] < 0 ? -1 : 0)) : 0;
                case "ROUND": {
                    if (a.length < 1) return 0;
                    double p = Math.pow(10, a.length > 1 ? a[1] : 0);
                    return Math.round(a[0] * p) / p;
                }
                case "MOD": return a.length > 1 && a[1] != 0 ? Math.fmod(a[0], a[1]) : double.NAN;
                case "AND": { foreach (var x in a) if (x == 0) return 0; return 1; }
                case "OR": { foreach (var x in a) if (x != 0) return 1; return 0; }
                case "NOT": return a.length > 0 && a[0] == 0 ? 1 : 0;
                case "IF": return a.length >= 3 ? (a[0] != 0 ? a[1] : a[2]) : double.NAN;
                case "DEFINED": return error ? 0 : 1;
                default: return double.NAN;
            }
        }
    }
}
