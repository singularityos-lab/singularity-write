namespace Write {

    public enum StyleType {
        PARAGRAPH,
        CHARACTER,
        TABLE,
        NUMBERING
    }

    public class Style : Object {
        public string id;
        public string name;
        public StyleType kind;
        public string? based_on = null;
        public string? next = null;
        public string? link = null;
        public ParaProps para = new ParaProps();
        public CharProps chr = new CharProps();
        public bool custom = false;
        public bool quick = false;
        public bool hidden = false;
        public int priority = 99;
        public string? table_header_shading = null;
        public string? table_band_shading = null;
        public CharProps? table_header_chr = null;
        public Border? table_border = null;

        public Style(string id, string name, StyleType kind = StyleType.PARAGRAPH) {
            this.id = id;
            this.name = name;
            this.kind = kind;
        }

        public Style copy() {
            var s = new Style(id, name, kind);
            s.based_on = based_on;
            s.next = next;
            s.link = link;
            s.para = para.copy();
            s.chr = chr.copy();
            s.custom = custom;
            s.quick = quick;
            s.hidden = hidden;
            s.priority = priority;
            s.table_header_shading = table_header_shading;
            s.table_band_shading = table_band_shading;
            s.table_header_chr = table_header_chr != null ? table_header_chr.copy() : null;
            s.table_border = table_border != null ? table_border.copy() : null;
            return s;
        }
    }

    public class StyleSheet : Object {
        public CharProps default_char = new CharProps();
        public ParaProps default_para = new ParaProps();
        public Gee.ArrayList<Style> list = new Gee.ArrayList<Style>();
        private Gee.HashMap<string, Style> by_id = new Gee.HashMap<string, Style>();
        public int generation { get; private set; default = 0; }

        public signal void changed();

        public StyleSheet() {
            default_char.font = "Liberation Serif";
            default_char.size = 11;
            default_para.space_after = 8;
            default_para.line = 1.08;
            default_para.line_rule = LineRule.AUTO;
            default_para.ind_left = 0;
            default_para.ind_right = 0;
            default_para.ind_first = 0;
            default_para.space_before = 0;
            default_para.align = Align.LEFT;
        }

        public void touch() {
            generation++;
            changed();
        }

        public StyleSheet copy() {
            var s = new StyleSheet();
            s.default_char = default_char.copy();
            s.default_para = default_para.copy();
            foreach (var st in list) s.add(st.copy());
            return s;
        }

        public new Style? get(string? id) {
            if (id == null) return null;
            return by_id[id];
        }

        public Style? by_name(string name) {
            string n = name.down();
            foreach (var s in list) if (s.name.down() == n) return s;
            return null;
        }

        public void add(Style s) {
            var old = by_id[s.id];
            if (old != null) list.remove(old);
            list.add(s);
            by_id[s.id] = s;
        }

        public void remove(string id) {
            var s = by_id[id];
            if (s == null) return;
            list.remove(s);
            by_id.unset(id);
            foreach (var o in list) {
                if (o.based_on == id) o.based_on = s.based_on;
                if (o.next == id) o.next = null;
            }
        }

        public string unique_id(string name) {
            var sb = new StringBuilder();
            unichar c;
            int i = 0;
            while (name.get_next_char(ref i, out c)) if (c.isalnum()) sb.append_unichar(c);
            string base_id = sb.len > 0 ? sb.str : "Style";
            string id = base_id;
            int n = 1;
            while (by_id.has_key(id)) id = "%s%d".printf(base_id, n++);
            return id;
        }

        public ParaProps para_chain(string? id) {
            var p = default_para.copy();
            foreach (var s in chain(id)) p.overlay(s.para);
            return p;
        }

        public CharProps char_chain(string? id) {
            var c = new CharProps();
            foreach (var s in chain(id)) c.overlay(s.chr);
            return c;
        }

        public Gee.ArrayList<Style> chain(string? id) {
            var stack = new Gee.ArrayList<Style>();
            var seen = new Gee.HashSet<string>();
            string? cur = id;
            while (cur != null && !seen.contains(cur)) {
                seen.add(cur);
                var s = by_id[cur];
                if (s == null) break;
                stack.insert(0, s);
                cur = s.based_on;
            }
            return stack;
        }

        public ParaProps resolve_para(Paragraph p) {
            var r = para_chain(p.style);
            r.overlay(p.props);
            return r;
        }

        public CharProps resolve_char(Paragraph p, CharProps run) {
            var c = default_char.copy();
            c.overlay(char_chain(p.style));
            if (run.style != null) c.overlay(char_chain(run.style));
            c.overlay(run);
            return c;
        }

        public int outline_level(Paragraph p) {
            var r = resolve_para(p);
            return r.outline >= 0 && r.outline < 9 ? r.outline : -1;
        }

        public Gee.ArrayList<Style> quick_styles() {
            var out_list = new Gee.ArrayList<Style>();
            foreach (var s in list) if (s.quick && !s.hidden) out_list.add(s);
            out_list.sort((a, b) => a.priority - b.priority);
            return out_list;
        }

        public Gee.ArrayList<Style> of_kind(StyleType kind) {
            var out_list = new Gee.ArrayList<Style>();
            foreach (var s in list) if (s.kind == kind && !s.hidden) out_list.add(s);
            out_list.sort((a, b) => strcmp(a.name.down(), b.name.down()));
            return out_list;
        }

        private Style para_style(string id, string name, int priority, bool quick, string? based = "Normal") {
            var s = get(id);
            if (s == null) {
                s = new Style(id, name, StyleType.PARAGRAPH);
                s.based_on = based;
                s.next = "Normal";
                s.priority = priority;
                s.quick = quick;
                add(s);
            }
            return s;
        }

        private Style char_style(string id, string name, int priority, bool quick) {
            var s = get(id);
            if (s == null) {
                s = new Style(id, name, StyleType.CHARACTER);
                s.priority = priority;
                s.quick = quick;
                add(s);
            }
            return s;
        }

        public void ensure_builtins() {
            bool fresh = get("Normal") == null;
            var normal = para_style("Normal", "Normal", 0, true, null);
            normal.next = "Normal";
            if (fresh) {
                double[] sizes = { 16, 13, 12, 11, 11, 11, 11, 11, 11 };
                string[] colors = { "#2f5496", "#2f5496", "#1f3763", "#2f5496", "#2f5496", "#1f3763", "#1f3763", "#272727", "#272727" };
                for (int i = 1; i <= 9; i++) {
                    var h = para_style("Heading%d".printf(i), "Heading %d".printf(i), 9, i <= 3);
                    h.chr.font = "Liberation Sans";
                    h.chr.size = sizes[i - 1];
                    h.chr.color = colors[i - 1];
                    if (i <= 2) h.chr.bold = Tri.OFF;
                    if (i >= 3) h.chr.bold = Tri.ON;
                    if (i == 4 || i == 7) h.chr.italic = Tri.ON;
                    h.para.space_before = i == 1 ? 12 : 2;
                    h.para.space_after = 0;
                    h.para.keep_next = Tri.ON;
                    h.para.keep_lines = Tri.ON;
                    h.para.outline = i - 1;
                }
                var title = para_style("Title", "Title", 10, true);
                title.chr.font = "Liberation Sans";
                title.chr.size = 28;
                title.para.space_after = 0;
                title.para.contextual = Tri.ON;
                var sub = para_style("Subtitle", "Subtitle", 11, true);
                sub.chr.color = "#5a5a5a";
                sub.chr.size = 13;
                sub.para.space_after = 8;
                var quote = para_style("Quote", "Quote", 29, true);
                quote.chr.italic = Tri.ON;
                quote.chr.color = "#404040";
                quote.para.ind_left = 43.2;
                quote.para.ind_right = 43.2;
                quote.para.space_before = 10;
                quote.para.align = Align.CENTER;
                var iq = para_style("IntenseQuote", "Intense Quote", 30, true);
                iq.chr.italic = Tri.ON;
                iq.chr.color = "#2f5496";
                iq.para.ind_left = 43.2;
                iq.para.ind_right = 43.2;
                iq.para.space_before = 18;
                iq.para.space_after = 18;
                iq.para.align = Align.CENTER;
                iq.para.border_top = new Border.with("single", 0.5, "#2f5496");
                iq.para.border_bottom = new Border.with("single", 0.5, "#2f5496");
                var nospace = para_style("NoSpacing", "No Spacing", 1, true);
                nospace.para.space_after = 0;
                nospace.para.line = 1.0;
                var lp = para_style("ListParagraph", "List Paragraph", 34, true);
                lp.para.ind_left = 36;
                lp.para.contextual = Tri.ON;
                var cap = para_style("Caption", "Caption", 35, false);
                cap.chr.italic = Tri.ON;
                cap.chr.size = 9;
                cap.chr.color = "#44546a";
                cap.para.space_after = 10;
                cap.para.line = 1.0;
                var code = para_style("SourceCode", "Source Code", 36, true);
                code.chr.font = "Liberation Mono";
                code.chr.size = 10;
                code.para.space_after = 0;
                code.para.line = 1.0;
                code.para.shading = "#f2f2f2";
                var tochead = para_style("TOCHeading", "TOC Heading", 39, false, "Heading1");
                tochead.para.outline = 9;
                for (int i = 1; i <= 9; i++) {
                    var t = para_style("TOC%d".printf(i), "TOC %d".printf(i), 39, false);
                    t.para.ind_left = (i - 1) * 11;
                    t.para.space_after = 5;
                    t.hidden = false;
                }
                for (int i = 1; i <= 3; i++) {
                    var ix = para_style("Index%d".printf(i), "Index %d".printf(i), 99, false);
                    ix.para.ind_left = i * 11;
                    ix.para.ind_first = -11;
                    ix.para.space_after = 0;
                }
                var ih = para_style("IndexHeading", "Index Heading", 99, false);
                ih.chr.bold = Tri.ON;
                ih.chr.font = "Liberation Sans";
                var tof = para_style("TableofFigures", "Table of Figures", 99, false);
                tof.para.space_after = 0;
                var bib = para_style("Bibliography", "Bibliography", 37, false);
                bib.para.ind_left = 36;
                bib.para.ind_first = -36;
                var fnt = para_style("FootnoteText", "Footnote Text", 99, false);
                fnt.chr.size = 10;
                fnt.para.space_after = 0;
                fnt.para.line = 1.0;
                var ent = para_style("EndnoteText", "Endnote Text", 99, false);
                ent.chr.size = 10;
                ent.para.space_after = 0;
                ent.para.line = 1.0;
                var hdr = para_style("Header", "Header", 99, false);
                hdr.para.space_after = 0;
                hdr.para.line = 1.0;
                hdr.para.tabs = new Gee.ArrayList<TabStop>();
                hdr.para.tabs.add(new TabStop(234, TabAlign.CENTER));
                hdr.para.tabs.add(new TabStop(468, TabAlign.RIGHT));
                var ftr = para_style("Footer", "Footer", 99, false);
                ftr.para.space_after = 0;
                ftr.para.line = 1.0;
                ftr.para.tabs = new Gee.ArrayList<TabStop>();
                ftr.para.tabs.add(new TabStop(234, TabAlign.CENTER));
                ftr.para.tabs.add(new TabStop(468, TabAlign.RIGHT));
                var ct = para_style("CommentText", "Comment Text", 99, false);
                ct.chr.size = 10;
                var strong = char_style("Strong", "Strong", 22, true);
                strong.chr.bold = Tri.ON;
                var em = char_style("Emphasis", "Emphasis", 20, true);
                em.chr.italic = Tri.ON;
                var ie = char_style("IntenseEmphasis", "Intense Emphasis", 21, true);
                ie.chr.italic = Tri.ON;
                ie.chr.color = "#2f5496";
                var link = char_style("Hyperlink", "Hyperlink", 99, false);
                link.chr.color = "#0563c1";
                link.chr.underline = Underline.SINGLE;
                var fref = char_style("FootnoteReference", "Footnote Reference", 99, false);
                fref.chr.valign = VAlign.SUPER;
                var eref = char_style("EndnoteReference", "Endnote Reference", 99, false);
                eref.chr.valign = VAlign.SUPER;
                var icode = char_style("VerbatimChar", "Verbatim Char", 99, false);
                icode.chr.font = "Liberation Mono";
                var grid = new Style("TableGrid", "Table Grid", StyleType.TABLE);
                grid.table_border = new Border.with("single", 0.5, "#000000");
                add(grid);
                var plain = new Style("PlainTable", "Plain Table", StyleType.TABLE);
                add(plain);
                var accent = new Style("GridTableAccent", "Grid Table Accent", StyleType.TABLE);
                accent.table_border = new Border.with("single", 0.5, "#8eaadb");
                accent.table_header_shading = "#4472c4";
                accent.table_header_chr = new CharProps();
                accent.table_header_chr.color = "#ffffff";
                accent.table_header_chr.bold = Tri.ON;
                accent.table_band_shading = "#d9e2f3";
                add(accent);
                var light = new Style("GridTableLight", "Grid Table Light", StyleType.TABLE);
                light.table_border = new Border.with("single", 0.5, "#bfbfbf");
                light.table_header_chr = new CharProps();
                light.table_header_chr.bold = Tri.ON;
                light.table_band_shading = "#f2f2f2";
                add(light);
            }
            touch();
        }

        public static string[] builtin_ids() {
            return { "Normal", "Heading1", "Heading2", "Heading3", "Heading4", "Heading5", "Heading6", "Heading7", "Heading8", "Heading9",
                     "Title", "Subtitle", "Quote", "IntenseQuote", "NoSpacing", "ListParagraph", "Caption", "SourceCode",
                     "TOCHeading", "Bibliography", "FootnoteText", "EndnoteText", "Header", "Footer", "CommentText" };
        }
    }

    public class ListLevel : Object {
        public int start = 1;
        public NumFormat format = NumFormat.DECIMAL;
        public string text = "%1.";
        public string? bullet_font = null;
        public double ind_left = 36;
        public double hanging = 18;
        public Align align = Align.LEFT;
        public string suffix = "tab";
        public CharProps? label_props = null;

        public ListLevel copy() {
            var l = new ListLevel();
            l.start = start;
            l.format = format;
            l.text = text;
            l.bullet_font = bullet_font;
            l.ind_left = ind_left;
            l.hanging = hanging;
            l.align = align;
            l.suffix = suffix;
            l.label_props = label_props != null ? label_props.copy() : null;
            return l;
        }
    }

    public class ListDef : Object {
        public int id;
        public ListLevel[] levels = new ListLevel[9];
        public string name = "";

        public ListDef(int id) {
            this.id = id;
            for (int i = 0; i < 9; i++) levels[i] = new ListLevel();
        }

        public ListDef copy() {
            var d = new ListDef(id);
            for (int i = 0; i < 9; i++) d.levels[i] = levels[i].copy();
            d.name = name;
            return d;
        }

        public bool is_bullet() {
            return levels[0].format == NumFormat.BULLET;
        }
    }

    public class ListInstance : Object {
        public int id;
        public int def_id;
        public Gee.HashMap<int, int> start_override = new Gee.HashMap<int, int>();

        public ListInstance(int id, int def_id) {
            this.id = id;
            this.def_id = def_id;
        }

        public ListInstance copy() {
            var n = new ListInstance(id, def_id);
            foreach (var e in start_override.entries) n.start_override[e.key] = e.value;
            return n;
        }
    }

    public class Numbering : Object {
        public Gee.ArrayList<ListDef> defs = new Gee.ArrayList<ListDef>();
        public Gee.ArrayList<ListInstance> instances = new Gee.ArrayList<ListInstance>();

        public Numbering copy() {
            var n = new Numbering();
            foreach (var d in defs) n.defs.add(d.copy());
            foreach (var i in instances) n.instances.add(i.copy());
            return n;
        }

        public ListInstance? instance(int id) {
            foreach (var i in instances) if (i.id == id) return i;
            return null;
        }

        public ListDef? def(int id) {
            foreach (var d in defs) if (d.id == id) return d;
            return null;
        }

        public ListDef? def_for(int num_id) {
            var inst = instance(num_id);
            return inst != null ? def(inst.def_id) : null;
        }

        public ListLevel? level(int num_id, int lvl) {
            var d = def_for(num_id);
            if (d == null) return null;
            return d.levels[lvl.clamp(0, 8)];
        }

        private int next_def_id() {
            int m = 0;
            foreach (var d in defs) if (d.id >= m) m = d.id + 1;
            return m;
        }

        private int next_instance_id() {
            int m = 1;
            foreach (var i in instances) if (i.id >= m) m = i.id + 1;
            return m;
        }

        public int add_instance(ListDef d) {
            if (!defs.contains(d)) defs.add(d);
            var inst = new ListInstance(next_instance_id(), d.id);
            instances.add(inst);
            return inst.id;
        }

        public Gee.HashMap<int, int> merge(Numbering src) {
            var defmap = new Gee.HashMap<int, int>();
            var map = new Gee.HashMap<int, int>();
            foreach (var d in src.defs) {
                var nd = d.copy();
                nd.id = next_def_id();
                defs.add(nd);
                defmap[d.id] = nd.id;
            }
            foreach (var i in src.instances) {
                var ni = i.copy();
                ni.id = next_instance_id();
                if (defmap.has_key(i.def_id)) ni.def_id = defmap[i.def_id];
                instances.add(ni);
                map[i.id] = ni.id;
            }
            return map;
        }

        public int restart(int num_id) {
            var inst = instance(num_id);
            if (inst == null) return num_id;
            var n = new ListInstance(next_instance_id(), inst.def_id);
            for (int i = 0; i < 9; i++) {
                var lv = def(inst.def_id).levels[i];
                n.start_override[i] = lv.start;
            }
            instances.add(n);
            return n.id;
        }

        public ListDef make_bullets(string[]? chars = null) {
            var d = new ListDef(next_def_id());
            string[] marks = chars ?? new string[] { "\u2022", "\u25e6", "\u25aa" };
            for (int i = 0; i < 9; i++) {
                var l = d.levels[i];
                l.format = NumFormat.BULLET;
                l.text = marks[i % marks.length];
                l.ind_left = 36 * (i + 1);
                l.hanging = 18;
            }
            d.name = "bullets";
            return d;
        }

        public ListDef make_numbers(NumFormat[]? formats = null) {
            var d = new ListDef(next_def_id());
            NumFormat[] fm = formats ?? new NumFormat[] { NumFormat.DECIMAL, NumFormat.LOWER_LETTER, NumFormat.LOWER_ROMAN };
            for (int i = 0; i < 9; i++) {
                var l = d.levels[i];
                l.format = fm[i % fm.length];
                l.text = "%" + (i + 1).to_string() + ".";
                l.ind_left = 36 * (i + 1);
                l.hanging = 18;
            }
            d.name = "numbers";
            return d;
        }

        public ListDef make_outline() {
            var d = new ListDef(next_def_id());
            for (int i = 0; i < 9; i++) {
                var l = d.levels[i];
                l.format = NumFormat.DECIMAL;
                var sb = new StringBuilder();
                for (int k = 0; k <= i; k++) {
                    if (k > 0) sb.append_c('.');
                    sb.append("%" + (k + 1).to_string());
                }
                if (i == 0) sb.append_c('.');
                l.text = sb.str;
                l.ind_left = 18 + 21.6 * i + 18;
                l.hanging = 18 + 7.2 * i;
            }
            d.name = "outline";
            return d;
        }

        public static string format_number(int n, NumFormat f) {
            switch (f) {
                case NumFormat.LOWER_LETTER: return letters(n).down();
                case NumFormat.UPPER_LETTER: return letters(n);
                case NumFormat.LOWER_ROMAN: return roman(n).down();
                case NumFormat.UPPER_ROMAN: return roman(n);
                case NumFormat.DECIMAL_ZERO: return n < 10 ? "0%d".printf(n) : n.to_string();
                case NumFormat.ORDINAL: return ordinal(n);
                case NumFormat.NONE: return "";
                case NumFormat.BULLET: return "\u2022";
                default: return n.to_string();
            }
        }

        public static string letters(int n) {
            if (n <= 0) return "";
            int k = (n - 1) % 26;
            int rep = (n - 1) / 26 + 1;
            var sb = new StringBuilder();
            for (int i = 0; i < rep; i++) sb.append_c((char) ('A' + k));
            return sb.str;
        }

        public static string roman(int n) {
            if (n <= 0 || n >= 4000) return n.to_string();
            int[] vals = { 1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1 };
            string[] syms = { "M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I" };
            var sb = new StringBuilder();
            for (int i = 0; i < vals.length; i++) {
                while (n >= vals[i]) {
                    sb.append(syms[i]);
                    n -= vals[i];
                }
            }
            return sb.str;
        }

        public static string ordinal(int n) {
            int m = n % 100;
            if (m >= 11 && m <= 13) return "%dth".printf(n);
            switch (n % 10) {
                case 1: return "%dst".printf(n);
                case 2: return "%dnd".printf(n);
                case 3: return "%drd".printf(n);
                default: return "%dth".printf(n);
            }
        }
    }

    public class ListCounter : Object {
        private class Counts : Object {
            public int[] c = new int[9];
        }

        private Gee.HashMap<int, Counts> counters = new Gee.HashMap<int, Counts>();
        private Numbering numbering;

        public ListCounter(Numbering numbering) {
            this.numbering = numbering;
        }

        public string? label(int num_id, int lvl) {
            var inst = numbering.instance(num_id);
            if (inst == null) return null;
            var d = numbering.def(inst.def_id);
            if (d == null) return null;
            lvl = lvl.clamp(0, 8);
            int key = shared_key(inst);
            var counts = counters[key];
            if (counts == null) {
                counts = new Counts();
                for (int i = 0; i < 9; i++) counts.c[i] = start_of(inst, d, i) - 1;
                counters[key] = counts;
            }
            unowned int[] c = counts.c;
            c[lvl] = c[lvl] + 1;
            for (int i = lvl + 1; i < 9; i++) c[i] = start_of(inst, d, i) - 1;
            var lv = d.levels[lvl];
            if (lv.format == NumFormat.BULLET) return lv.text;
            var sb = new StringBuilder();
            string t = lv.text;
            int i = 0;
            while (i < t.length) {
                if (t[i] == '%' && i + 1 < t.length && t[i + 1] >= '1' && t[i + 1] <= '9') {
                    int ref_lvl = t[i + 1] - '1';
                    int val = c[ref_lvl];
                    if (val < start_of(inst, d, ref_lvl)) val = start_of(inst, d, ref_lvl);
                    sb.append(Numbering.format_number(val, d.levels[ref_lvl].format));
                    i += 2;
                } else {
                    sb.append_c(t[i]);
                    i++;
                }
            }
            return sb.str;
        }

        private int shared_key(ListInstance inst) {
            if (inst.start_override.size > 0) return 1000000 + inst.id;
            return inst.def_id;
        }

        private int start_of(ListInstance inst, ListDef d, int lvl) {
            if (inst.start_override.has_key(lvl)) return inst.start_override[lvl];
            return d.levels[lvl].start;
        }
    }
}
