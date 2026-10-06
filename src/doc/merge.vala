namespace Write {

    public class DataSource : Object {
        public string[] columns = {};
        public Gee.ArrayList<Gee.HashMap<string, string>> records = new Gee.ArrayList<Gee.HashMap<string, string>>();
        public string path = "";

        public static DataSource load(string path) throws Error {
            string text;
            FileUtils.get_contents(path, out text);
            text = Formats.decode_text(text.data);
            string lp = path.down();
            DataSource ds;
            if (lp.has_suffix(".vcf") || lp.has_suffix(".vcard")) ds = from_vcard(text);
            else if (lp.has_suffix(".json")) ds = from_json(text);
            else ds = from_delimited(text, lp.has_suffix(".tsv") || lp.has_suffix(".tab") ? '\t' : guess_delim(text));
            ds.path = path;
            return ds;
        }

        private static char guess_delim(string text) {
            int nl = text.index_of_char('\n');
            string first = nl > 0 ? text.substring(0, nl) : text;
            int commas = 0, semis = 0, tabs = 0;
            for (int i = 0; i < first.length; i++) {
                if (first[i] == ',') commas++;
                else if (first[i] == ';') semis++;
                else if (first[i] == '\t') tabs++;
            }
            if (tabs > commas && tabs > semis) return '\t';
            return semis > commas ? ';' : ',';
        }

        public static Gee.ArrayList<Gee.ArrayList<string>> parse_rows(string text, char delim) {
            var rows = new Gee.ArrayList<Gee.ArrayList<string>>();
            var row = new Gee.ArrayList<string>();
            var cell = new StringBuilder();
            bool quoted = false;
            int i = 0;
            int n = text.length;
            while (i < n) {
                char c = text[i];
                if (quoted) {
                    if (c == '"') {
                        if (i + 1 < n && text[i + 1] == '"') {
                            cell.append_c('"');
                            i += 2;
                            continue;
                        }
                        quoted = false;
                    } else {
                        cell.append_c(c);
                    }
                    i++;
                    continue;
                }
                if (c == '"' && cell.len == 0) {
                    quoted = true;
                } else if (c == delim) {
                    row.add(cell.str);
                    cell.truncate(0);
                } else if (c == '\n' || c == '\r') {
                    if (c == '\r' && i + 1 < n && text[i + 1] == '\n') i++;
                    row.add(cell.str);
                    cell.truncate(0);
                    if (!(row.size == 1 && row[0] == "")) rows.add(row);
                    row = new Gee.ArrayList<string>();
                } else {
                    cell.append_c(c);
                }
                i++;
            }
            if (cell.len > 0 || row.size > 0) {
                row.add(cell.str);
                rows.add(row);
            }
            return rows;
        }

        public static DataSource from_delimited(string text, char delim) {
            var ds = new DataSource();
            var rows = parse_rows(text, delim);
            if (rows.size == 0) return ds;
            string[] cols = {};
            foreach (var h in rows[0]) cols += h.strip();
            ds.columns = cols;
            for (int r = 1; r < rows.size; r++) {
                var rec = new Gee.HashMap<string, string>();
                for (int c = 0; c < cols.length; c++) rec[cols[c]] = c < rows[r].size ? rows[r][c] : "";
                ds.records.add(rec);
            }
            return ds;
        }

        public static DataSource from_vcard(string text) {
            var ds = new DataSource();
            ds.columns = { "Name", "FirstName", "LastName", "Organization", "Title", "Email", "Phone", "Street", "City", "Region", "PostalCode", "Country" };
            Gee.HashMap<string, string>? rec = null;
            string unfolded = text.replace("\r\n ", "").replace("\n ", "").replace("\r\n", "\n");
            foreach (string line in unfolded.split("\n")) {
                string l = line.strip();
                if (l.up() == "BEGIN:VCARD") {
                    rec = new Gee.HashMap<string, string>();
                    foreach (string c in ds.columns) rec[c] = "";
                    continue;
                }
                if (l.up() == "END:VCARD") {
                    if (rec != null) ds.records.add(rec);
                    rec = null;
                    continue;
                }
                if (rec == null) continue;
                int colon = l.index_of_char(':');
                if (colon < 0) continue;
                string key = l.substring(0, colon).up();
                string val = l.substring(colon + 1).replace("\\,", ",").replace("\\;", ";").replace("\\n", "\n");
                int semi = key.index_of_char(';');
                string base_key = semi > 0 ? key.substring(0, semi) : key;
                switch (base_key) {
                    case "FN": rec["Name"] = val; break;
                    case "N":
                        string[] parts = val.split(";");
                        rec["LastName"] = parts.length > 0 ? parts[0] : "";
                        rec["FirstName"] = parts.length > 1 ? parts[1] : "";
                        break;
                    case "ORG": rec["Organization"] = val.replace(";", " "); break;
                    case "TITLE": rec["Title"] = val; break;
                    case "EMAIL": if (rec["Email"] == "") rec["Email"] = val; break;
                    case "TEL": if (rec["Phone"] == "") rec["Phone"] = val; break;
                    case "ADR":
                        string[] a = val.split(";");
                        if (a.length >= 7) {
                            rec["Street"] = a[2];
                            rec["City"] = a[3];
                            rec["Region"] = a[4];
                            rec["PostalCode"] = a[5];
                            rec["Country"] = a[6];
                        }
                        break;
                    default: break;
                }
            }
            return ds;
        }

        public static DataSource from_json(string text) throws Error {
            var ds = new DataSource();
            var parser = new Json.Parser();
            parser.load_from_data(text);
            var root = parser.get_root();
            if (root == null || root.get_node_type() != Json.NodeType.ARRAY) return ds;
            var cols = new Gee.ArrayList<string>();
            foreach (var el in root.get_array().get_elements()) {
                if (el.get_node_type() != Json.NodeType.OBJECT) continue;
                var obj = el.get_object();
                var rec = new Gee.HashMap<string, string>();
                foreach (string m in obj.get_members()) {
                    if (!cols.contains(m)) cols.add(m);
                    var n = obj.get_member(m);
                    rec[m] = n.get_node_type() == Json.NodeType.VALUE ? n.get_value().strdup_contents().replace("\"", "") : "";
                    if (n.get_value_type() == typeof(string)) rec[m] = n.get_string();
                }
                ds.records.add(rec);
            }
            ds.columns = cols.to_array();
            return ds;
        }
    }

    public class MailMerge : Object {

        public static Document instantiate(Document template, Gee.HashMap<string, string> record) {
            var d = template.copy();
            foreach (var p in Story.all(d)) {
                for (int i = 0; i < p.inlines.size; i++) {
                    var f = p.inlines[i] as FieldRun;
                    if (f == null) continue;
                    string k = f.kind();
                    if (k == "MERGEFIELD") {
                        string[] t = f.args();
                        string name = t.length > 1 ? t[1] : "";
                        string v = record[name] ?? "";
                        if (v == "") foreach (var e in record.entries) if (e.key.down() == name.down()) v = e.value;
                        v = Fields.apply_format(v, t);
                        string? before = Fields.switch_arg(t, "\\b");
                        string? after = Fields.switch_arg(t, "\\f");
                        if (v != "" && before != null) v = before + v;
                        if (v != "" && after != null) v = v + after;
                        var run = new TextRun(v, f.props);
                        p.inlines[i] = run;
                    } else if (k == "IF") {
                        p.inlines[i] = new TextRun(eval_if(f, record), f.props);
                    } else if (k == "NEXT" || k == "NEXTIF" || k == "MERGEREC") {
                        p.inlines[i] = new TextRun(k == "MERGEREC" ? "" : "", f.props);
                    }
                }
                p.normalize();
                p.touch();
            }
            return d;
        }

        private static string eval_if(FieldRun f, Gee.HashMap<string, string> rec) {
            string[] t = f.args();
            if (t.length < 5) return f.result;
            string left = t[1];
            if (rec.has_key(left)) left = rec[left];
            string op = t[2];
            string right = t[3];
            if (rec.has_key(right)) right = rec[right];
            bool r;
            double a = 0, b = 0;
            bool num = double.try_parse(left, out a) && double.try_parse(right, out b);
            switch (op) {
                case "<>": r = left != right; break;
                case "<": r = num ? a < b : strcmp(left, right) < 0; break;
                case ">": r = num ? a > b : strcmp(left, right) > 0; break;
                case "<=": r = num ? a <= b : strcmp(left, right) <= 0; break;
                case ">=": r = num ? a >= b : strcmp(left, right) >= 0; break;
                default: r = left == right; break;
            }
            return r ? t[4] : (t.length > 5 ? t[5] : "");
        }

        public static Document merge_all(Document template, DataSource ds, int from = 0, int to = -1) {
            var result = template.copy();
            result.body.clear();
            int last = to < 0 ? ds.records.size - 1 : int.min(to, ds.records.size - 1);
            for (int r = from; r <= last; r++) {
                var one = instantiate(template, ds.records[r]);
                var items = new Gee.ArrayList<Block>();
                items.add_all(one.body.items);
                for (int i = 0; i < items.size; i++) {
                    var b = items[i];
                    var p = b as Paragraph;
                    if (p != null && p.section != null) p.section = null;
                    if (i == items.size - 1 && r < last && p != null) {
                        var sec = template.final_section.copy();
                        sec.start = SectionStart.NEXT_PAGE;
                        p.section = sec;
                    }
                    one.body.items.remove(b);
                    result.body.add(b);
                }
            }
            if (result.body.size == 0) result.body.add(new Paragraph());
            result.merge_source = null;
            return result;
        }

        public class LabelSpec : Object {
            public string name;
            public double page_w;
            public double page_h;
            public double top;
            public double left;
            public double w;
            public double h;
            public double hgap;
            public double vgap;
            public int cols;
            public int rows;

            public LabelSpec(string name, double page_w, double page_h, double top, double left, double w, double h, double hgap, double vgap, int cols, int rows) {
                this.name = name;
                this.page_w = page_w;
                this.page_h = page_h;
                this.top = top;
                this.left = left;
                this.w = w;
                this.h = h;
                this.hgap = hgap;
                this.vgap = vgap;
                this.cols = cols;
                this.rows = rows;
            }
        }

        public static Gee.ArrayList<LabelSpec> label_specs() {
            var l = new Gee.ArrayList<LabelSpec>();
            l.add(new LabelSpec("Avery 5160 / L7160 (address, 30 per page)", 612, 792, 36, 13.5, 189, 72, 9, 0, 3, 10));
            l.add(new LabelSpec("Avery 5162 (address, 14 per page)", 612, 792, 60.5, 11.25, 288, 96, 13.5, 0, 2, 7));
            l.add(new LabelSpec("Avery 5163 (shipping, 10 per page)", 612, 792, 36, 11.25, 288, 144, 13.5, 0, 2, 5));
            l.add(new LabelSpec("Avery L7163 (A4, 14 per page)", 595.3, 841.9, 42.5, 13.3, 283.5, 107.7, 7.1, 0, 2, 7));
            l.add(new LabelSpec("Avery L7160 (A4, 21 per page)", 595.3, 841.9, 42.5, 20.4, 181.4, 107.7, 7.1, 0, 3, 7));
            l.add(new LabelSpec("Herma 4453 (A4, 24 per page)", 595.3, 841.9, 25.5, 0, 198.4, 99.2, 0, 0, 3, 8));
            return l;
        }

        public static Document labels(BlockList label_template, DataSource? ds, LabelSpec spec, string fixed_text = "") {
            var d = Document.create_blank();
            d.body.clear();
            var s = d.final_section;
            s.page_w = spec.page_w;
            s.page_h = spec.page_h;
            s.margin_top = spec.top;
            s.margin_left = spec.left;
            s.margin_right = 0;
            s.margin_bottom = 0;
            s.header_dist = 0;
            s.footer_dist = 0;
            int count = ds != null ? ds.records.size : spec.cols * spec.rows;
            int per_page = spec.cols * spec.rows;
            int pages = int.max(1, (count + per_page - 1) / per_page);
            int idx = 0;
            for (int pg = 0; pg < pages; pg++) {
                int ncols = spec.cols * 2 - 1;
                double[] grid = new double[ncols];
                for (int c = 0; c < ncols; c++) grid[c] = c % 2 == 0 ? spec.w : spec.hgap;
                var t = new Table();
                t.style = "PlainTable";
                t.grid = grid;
                t.fixed_layout = true;
                t.margin_l = 6;
                t.margin_r = 6;
                for (int r = 0; r < spec.rows; r++) {
                    var row = new TableRow();
                    row.height = spec.h;
                    row.height_exact = true;
                    row.cant_split = true;
                    for (int c = 0; c < ncols; c++) {
                        var cell = new TableCell();
                        if (c % 2 == 0 && idx < count) {
                            BlockList content;
                            if (ds != null) {
                                var tmp = new Document();
                                tmp.body = label_template.copy(tmp);
                                content = MailMerge.instantiate(tmp, ds.records[idx]).body;
                            } else {
                                content = new BlockList();
                                foreach (string line in fixed_text.split("\n")) content.add(new Paragraph.with_text(line, "NoSpacing"));
                            }
                            foreach (var b in content.items) cell.blocks.add(b.copy());
                            idx++;
                        }
                        if (cell.blocks.size == 0) cell.blocks.add(new Paragraph("NoSpacing"));
                        row.cells.add(cell);
                    }
                    t.rows.add(row);
                }
                d.body.add(t);
                var after = new Paragraph("NoSpacing");
                after.props.space_after = 0;
                after.mark_props.size = 1;
                if (pg < pages - 1) after.inlines.add(new Break(BreakKind.PAGE));
                d.body.add(after);
                if (idx >= count) break;
            }
            return d;
        }

        public static Document envelope(string sender, string recipient, bool dl) {
            var d = Document.create_blank();
            d.body.clear();
            var s = d.final_section;
            if (dl) {
                s.page_w = 623.6;
                s.page_h = 311.8;
            } else {
                s.page_w = 684;
                s.page_h = 297;
            }
            s.landscape = true;
            s.margin_top = 25;
            s.margin_left = 25;
            s.margin_right = 25;
            s.margin_bottom = 25;
            foreach (string line in sender.split("\n")) d.body.add(new Paragraph.with_text(line, "NoSpacing"));
            var gap = new Paragraph("NoSpacing");
            gap.props.space_after = s.page_h * 0.28;
            d.body.add(gap);
            foreach (string line in recipient.split("\n")) {
                var p = new Paragraph.with_text(line, "NoSpacing");
                p.props.ind_left = s.page_w * 0.42;
                p.mark_props.size = 12;
                d.body.add(p);
            }
            return d;
        }
    }
}
