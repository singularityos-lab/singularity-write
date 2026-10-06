namespace Write {

    public enum Region {
        BODY,
        HEADER,
        FOOTER,
        NOTES,
        FRAME
    }

    public class LineInfo : Object {
        public Pango.Layout layout;
        public int line_no;
        public int byte_base;
        public double x;
        public double top;
        public double height;
        public double baseline;
        public int start_byte;
        public int end_byte;
        public bool page_break;
        public bool column_break;
    }

    public class ParaLayout : Object {
        public Paragraph para;
        public ParaText text;
        public ParaProps pp;
        public Gee.ArrayList<LineInfo> lines = new Gee.ArrayList<LineInfo>();
        public double width;
        public double space_before;
        public double space_after;
        public double origin;
        public double ind_left;
        public double ind_right;
        public string? label = null;
        public Pango.Layout? label_layout = null;
        public double label_x = 0;
        public bool live = false;
        public double dropcap_w = 0;
        public double dropcap_h = 0;
        public Pango.Layout? dropcap = null;

        public double content_height() {
            double h = 0;
            foreach (var l in lines) h = double.max(h, l.top + l.height);
            return h;
        }
    }

    public class LineBox : Object {
        public ParaLayout pl;
        public LineInfo info;
        public double x;
        public double top;
        public double baseline;
        public double height;
        public Region region;
        public int page;
        public double clip_x0;
        public double clip_x1;
        public bool first;
        public bool last;

        public Paragraph para {
            get { return pl.para; }
        }

        public unowned Pango.LayoutLine? line() {
            return info.layout.get_line_readonly(info.line_no);
        }

        public double caret_x(int para_byte) {
            unowned Pango.LayoutLine? l = line();
            if (l == null) return x + info.x;
            int idx = (para_byte - info.byte_base).clamp(l.start_index, l.start_index + l.length);
            int xp;
            l.index_to_x(idx, false, out xp);
            return x + info.x + xp / (double) Pango.SCALE;
        }

        public int hit(double px) {
            unowned Pango.LayoutLine? l = line();
            if (l == null) return info.start_byte;
            int idx, trailing;
            l.x_to_index((int) ((px - x - info.x) * Pango.SCALE), out idx, out trailing);
            int b = idx + info.byte_base;
            if (trailing > 0) {
                string t = pl.text.text;
                if (b < t.length) {
                    unichar c;
                    int i = b;
                    t.get_next_char(ref i, out c);
                    b = i;
                }
            }
            return b.clamp(info.start_byte, info.end_byte);
        }

        public bool contains_byte(int b) {
            return b >= info.start_byte && (b < info.end_byte || (last && b == info.end_byte) || (b == info.end_byte && info.end_byte == info.start_byte));
        }
    }

    public enum DecoKind {
        FILL,
        STROKE,
        LINE,
        LEADER,
        SEPARATOR
    }

    public class Deco : Object {
        public DecoKind kind;
        public double x;
        public double y;
        public double w;
        public double h;
        public string color = "#000000";
        public double width = 0.5;
        public string style = "single";
        public bool behind = true;
        public string text = "";
        public Object? data = null;

        public Deco(DecoKind kind, double x, double y, double w, double h) {
            this.kind = kind;
            this.x = x;
            this.y = y;
            this.w = w;
            this.h = h;
        }
    }

    public class ObjBox : Object {
        public Inline item;
        public Paragraph para;
        public double x;
        public double y;
        public double w;
        public double h;
        public Region region;
        public bool floating;
        public Frame? inner = null;

        public ObjBox(Inline item, Paragraph para, double x, double y, double w, double h) {
            this.item = item;
            this.para = para;
            this.x = x;
            this.y = y;
            this.w = w;
            this.h = h;
        }
    }

    public class Frame : Object {
        public Gee.ArrayList<LineBox> lines = new Gee.ArrayList<LineBox>();
        public Gee.ArrayList<Deco> decos = new Gee.ArrayList<Deco>();
        public Gee.ArrayList<ObjBox> objects = new Gee.ArrayList<ObjBox>();
        public double height = 0;

        public void translate(double dx, double dy) {
            foreach (var l in lines) {
                l.x += dx;
                l.top += dy;
                l.baseline += dy;
                l.clip_x0 += dx;
                l.clip_x1 += dx;
            }
            foreach (var d in decos) {
                d.x += dx;
                d.y += dy;
            }
            foreach (var o in objects) {
                o.x += dx;
                o.y += dy;
                if (o.inner != null) o.inner.translate(dx, dy);
            }
        }
    }

    public class CommentAnchor : Object {
        public string id;
        public double x;
        public double y;
        public double y_end;
        public double x_end;
    }

    public class PageBox : Object {
        public int index;
        public double width;
        public double height;
        public Section section;
        public int section_index;
        public int number;
        public string number_text = "";
        public bool first_of_section;
        public double body_top;
        public double body_bottom;
        public double body_left;
        public double body_right;
        public Gee.ArrayList<LineBox> lines = new Gee.ArrayList<LineBox>();
        public Gee.ArrayList<Deco> decos = new Gee.ArrayList<Deco>();
        public Gee.ArrayList<ObjBox> objects = new Gee.ArrayList<ObjBox>();
        public Gee.ArrayList<CommentAnchor> comments = new Gee.ArrayList<CommentAnchor>();
        public Gee.ArrayList<NoteRef> notes = new Gee.ArrayList<NoteRef>();
        public HeaderFooter? header = null;
        public HeaderFooter? footer = null;
        public double header_bottom = 0;
        public double footer_top = 0;
    }

    public class DocLayout : Object {
        public Gee.ArrayList<PageBox> pages = new Gee.ArrayList<PageBox>();
        public Gee.HashMap<Paragraph, Gee.ArrayList<LineBox>> para_lines = new Gee.HashMap<Paragraph, Gee.ArrayList<LineBox>>();
        public Gee.HashMap<string, int> bookmark_page = new Gee.HashMap<string, int>();
        public Gee.HashMap<Paragraph, int> para_page = new Gee.HashMap<Paragraph, int>();
        public Gee.HashMap<Note, string> note_marks = new Gee.HashMap<Note, string>();
        public Gee.HashMap<Paragraph, string> labels = new Gee.HashMap<Paragraph, string>();
        public int total_pages {
            get { return pages.size; }
        }

        public void index_line(LineBox lb) {
            var list = para_lines[lb.para];
            if (list == null) {
                list = new Gee.ArrayList<LineBox>();
                para_lines[lb.para] = list;
            }
            list.add(lb);
            if (!para_page.has_key(lb.para)) para_page[lb.para] = lb.page;
        }

        public int page_of(Paragraph p) {
            return para_page.has_key(p) ? para_page[p] : -1;
        }
    }

    private class Rect {
        public double x;
        public double y;
        public double w;
        public double h;

        public Rect(double x, double y, double w, double h) {
            this.x = x;
            this.y = y;
            this.w = w;
            this.h = h;
        }
    }

    public class LayoutEngine : Object {
        public Document doc;
        public ViewOptions opts;
        public double draft_width = 612;
        private Pango.Context pctx;
        private TextBuilder builder;
        private DocLayout result;
        private int assumed_pages = 1;
        private FieldContext fctx;
        private Gee.HashMap<Paragraph, CacheEntry> cache = new Gee.HashMap<Paragraph, CacheEntry>();
        private int cache_gen = 0;
        private Gee.HashMap<Note, string> note_marks = new Gee.HashMap<Note, string>();
        private Gee.HashMap<Paragraph, string> labels = new Gee.HashMap<Paragraph, string>();
        public string filename = "";
        public string filepath = "";
        public Gee.HashMap<string, string>? merge_record = null;
        public bool outline_mode = false;
        public int outline_show = 9;
        public bool outline_body = true;
        public Gee.HashSet<Paragraph> collapsed = new Gee.HashSet<Paragraph>();
        private int outline_hide_below = -1;

        private class CacheEntry {
            public uint version;
            public string key;
            public ParaLayout pl;
            public int seen;
        }

        private PageBox page;
        private Section sec;
        private int sec_index;
        private double[] col_x = {};
        private double col_w;
        private int col;
        private double y;
        private double region_top;
        private double bottom;
        private double notes_h;
        private Gee.ArrayList<Rect> exclusions = new Gee.ArrayList<Rect>();
        private int page_number = 0;

        public LayoutEngine(Document doc, ViewOptions opts) {
            this.doc = doc;
            this.opts = opts;
            var fm = Pango.CairoFontMap.new_for_font_type(Cairo.FontType.FT);
            if (fm == null) fm = Pango.CairoFontMap.get_default();
            pctx = ((Pango.FontMap) fm).create_context();
            Pango.cairo_context_set_resolution(pctx, 72);
            var fo = new Cairo.FontOptions();
            fo.set_hint_metrics(Cairo.HintMetrics.OFF);
            fo.set_hint_style(Cairo.HintStyle.NONE);
            Pango.cairo_context_set_font_options(pctx, fo);
            pctx.set_round_glyph_positions(false);
            fctx = new FieldContext(doc);
            builder = new TextBuilder(doc, opts, field_text, note_mark);
            builder.hyphenator = Hyphenator.get_default();
        }

        public Pango.Context context() {
            return pctx;
        }

        public void invalidate() {
            cache.clear();
        }

        private string field_text(FieldRun f) {
            string k = f.kind();
            if (k == "PAGE" || k == "NUMPAGES" || k == "SECTIONPAGES" || k == "SECTION") {
                return Fields.evaluate(f, fctx);
            }
            if (k == "PAGEREF" && result != null) {
                string[] t = f.args();
                if (t.length > 1 && result.bookmark_page.has_key(t[1])) return result.bookmark_page[t[1]].to_string();
            }
            if (k == "MERGEFIELD") {
                if (merge_record != null) {
                    fctx.record = merge_record;
                    string v = Fields.evaluate(f, fctx);
                    fctx.record = null;
                    return v;
                }
                if (f.result == "" || f.result.has_prefix("\u00ab")) {
                    string[] t = f.args();
                    return "\u00ab" + (t.length > 1 ? t[1] : "") + "\u00bb";
                }
            }
            if (k == "NOTEMARK") return "";
            return f.result;
        }

        private string note_mark(NoteRef r) {
            if (r.note.custom_mark != null && r.note.custom_mark != "") return r.note.custom_mark;
            return note_marks[r.note] ?? "*";
        }

        private static bool is_live(Paragraph p) {
            foreach (var i in p.inlines) {
                var f = i as FieldRun;
                if (f == null) continue;
                string k = f.kind();
                if (k == "PAGE" || k == "NUMPAGES" || k == "SECTIONPAGES" || k == "SECTION" || k == "PAGEREF" || k == "MERGEFIELD") return true;
            }
            return false;
        }

        private void prepass() {
            note_marks.clear();
            labels.clear();
            int fn = 0;
            int en = 0;
            foreach (var n in doc.notes()) {
                if (n.kind == NoteKind.FOOTNOTE) note_marks[n] = Numbering.format_number(++fn, doc.footnote_format);
                else note_marks[n] = Numbering.format_number(++en, doc.endnote_format);
            }
            label_lists(doc.body, new ListCounter(doc.numbering));
        }

        private void label_lists(BlockList list, ListCounter counter) {
            foreach (var b in list.items) {
                var p = b as Paragraph;
                if (p != null) {
                    var pp = doc.styles.resolve_para(p);
                    if (pp.num_id > 0) {
                        string? lab = counter.label(pp.num_id, int.max(0, pp.num_level));
                        if (lab != null && lab != "") labels[p] = lab;
                    }
                    continue;
                }
                var t = b as Table;
                if (t != null) {
                    foreach (var r in t.rows) foreach (var c in r.cells) label_lists(c.blocks, counter);
                    continue;
                }
                var fb = b as FieldBlock;
                if (fb != null) label_lists(fb.result, counter);
            }
        }

        private string opts_key() {
            return opts.key() + "|" + doc.styles.generation.to_string();
        }

        public ParaLayout para_layout(Paragraph p, double width, CharProps? overlay = null) {
            string key = "%s|%.2f|%s".printf(opts_key(), width, overlay != null ? overlay.key() : "");
            bool live = is_live(p);
            if (!live) {
                var e = cache[p];
                if (e != null && e.version == p.version && e.key == key) {
                    e.seen = cache_gen;
                    var lab = labels[p];
                    if (lab == e.pl.label) return e.pl;
                }
            }
            builder.overlay = overlay;
            var pl = build_para(p, width);
            builder.overlay = null;
            pl.live = live;
            if (!live) {
                var e = new CacheEntry();
                e.version = p.version;
                e.key = key;
                e.pl = pl;
                e.seen = cache_gen;
                cache[p] = e;
            }
            return pl;
        }

        private Pango.TabArray tabs_for(ParaProps pp, double origin, double width) {
            var positions = new Gee.ArrayList<double?>();
            var aligns = new Gee.ArrayList<int>();
            double last = 0;
            if (pp.tabs != null) {
                foreach (var t in pp.tabs) {
                    if (t.align == TabAlign.CLEAR || t.align == TabAlign.BAR) continue;
                    double pos = t.pos - origin;
                    if (pos <= 0) continue;
                    positions.add(pos);
                    int a = 0;
                    if (t.align == TabAlign.CENTER) a = 2;
                    else if (t.align == TabAlign.RIGHT) a = 1;
                    else if (t.align == TabAlign.DECIMAL) a = 3;
                    aligns.add(a);
                    last = double.max(last, pos);
                }
            }
            double step = doc.default_tab > 1 ? doc.default_tab : 36;
            double next = Math.ceil((last + origin + 0.01) / step) * step - origin;
            while (next < width + step && positions.size < 64) {
                if (next > last) {
                    positions.add(next);
                    aligns.add(0);
                }
                next += step;
            }
            var arr = new Pango.TabArray(positions.size, false);
            for (int i = 0; i < positions.size; i++) {
                Pango.TabAlign ta = Pango.TabAlign.LEFT;
                if (aligns[i] == 1) ta = Pango.TabAlign.RIGHT;
                else if (aligns[i] == 2) ta = Pango.TabAlign.CENTER;
                else if (aligns[i] == 3) ta = Pango.TabAlign.DECIMAL;
                arr.set_tab(i, ta, (int) (positions[i] * Pango.SCALE));
            }
            return arr;
        }

        private ParaLayout build_para(Paragraph p, double width) {
            var pl = new ParaLayout();
            pl.para = p;
            pl.pp = doc.styles.resolve_para(p);
            var pp = pl.pp;
            pl.text = builder.build(p);
            double ind_left = pp.ind_left.is_nan() ? 0 : pp.ind_left;
            double ind_right = pp.ind_right.is_nan() ? 0 : pp.ind_right;
            double first = pp.ind_first.is_nan() ? 0 : pp.ind_first;
            string? lab = labels[p];
            if (pp.num_id > 0 && lab != null) {
                var lvl = doc.numbering.level(pp.num_id, int.max(0, pp.num_level));
                if (lvl != null) {
                    if (p.props.ind_left.is_nan() && doc.styles.para_chain(p.style).ind_left == doc.styles.default_para.ind_left) ind_left = lvl.ind_left;
                    if (p.props.ind_first.is_nan()) first = -lvl.hanging;
                }
                pl.label = lab;
                var ll = new Pango.Layout(pctx);
                var lc = pl.text.first_props.copy();
                if (lvl != null && lvl.label_props != null) {
                    var lp = lvl.label_props.copy();
                    if (lvl.format == NumFormat.BULLET) lp.font = null;
                    lc.overlay(lp);
                }
                lc.valign = VAlign.BASELINE;
                ll.set_font_description(TextBuilder.font_for(lc));
                ll.set_text(lab, -1);
                pl.label_layout = ll;
            }
            pl.ind_left = ind_left;
            pl.ind_right = ind_right;
            double origin = pl.label != null ? ind_left : ind_left + double.min(first, 0);
            pl.origin = origin;
            pl.label_x = ind_left + first;
            pl.width = width;
            double avail = double.max(12, width - origin - ind_right);
            pl.space_before = pp.space_before.is_nan() ? 0 : pp.space_before;
            pl.space_after = pp.space_after.is_nan() ? 0 : pp.space_after;
            var layout = make_layout(pl, avail, pl.label != null ? 0 : first - double.min(first, 0) + (first < 0 ? first : 0), 0, -1);
            if (pl.label != null) {
                layout.set_indent(0);
            } else if (first < 0) {
                layout.set_indent((int) (first * Pango.SCALE));
            } else {
                layout.set_indent((int) (first * Pango.SCALE));
            }
            if (pp.dropcap_lines > 0 && pl.text.text.length > 0) apply_dropcap(pl, layout, avail);
            collect_lines(pl, layout, 0, 0);
            return pl;
        }

        private void apply_dropcap(ParaLayout pl, Pango.Layout layout, double avail) {
            string t = pl.text.text;
            int end = t.index_of_nth_char(1);
            if (end <= 0) return;
            string letter = t.substring(0, end);
            double line_h = pl.text.max_size * 1.2;
            double h = line_h * pl.pp.dropcap_lines;
            var dc = new Pango.Layout(pctx);
            var c = pl.text.first_props.copy();
            c.size = h * 0.85;
            dc.set_font_description(TextBuilder.font_for(c));
            dc.set_text(letter, -1);
            Pango.Rectangle ink, logical;
            dc.get_extents(out ink, out logical);
            pl.dropcap = dc;
            pl.dropcap_w = logical.width / (double) Pango.SCALE + 4;
            pl.dropcap_h = h;
            var attrs = pl.text.attrs.copy();
            var ink0 = Pango.Rectangle();
            var a = Pango.AttrShape.@new(ink0, ink0);
            a.start_index = 0;
            a.end_index = end;
            attrs.insert((owned) a);
            layout.set_attributes(attrs);
        }

        private Pango.Layout make_layout(ParaLayout pl, double width, double indent, int from_byte, int to_byte) {
            var layout = new Pango.Layout(pctx);
            layout.set_font_description(TextBuilder.font_for(pl.text.mark_props));
            if (from_byte > 0 || to_byte >= 0) {
                int e = to_byte >= 0 ? to_byte : pl.text.text.length;
                layout.set_text(pl.text.text.substring(from_byte, e - from_byte), -1);
                var attrs = pl.text.attrs.copy();
                if (from_byte > 0) attrs.update(0, from_byte, 0);
                layout.set_attributes(attrs);
            } else {
                layout.set_text(pl.text.text, -1);
                layout.set_attributes(pl.text.attrs);
            }
            layout.set_width((int) (width * Pango.SCALE));
            layout.set_wrap(Pango.WrapMode.WORD_CHAR);
            switch (pl.pp.align) {
                case Align.CENTER: layout.set_alignment(Pango.Alignment.CENTER); break;
                case Align.RIGHT: layout.set_alignment(Pango.Alignment.RIGHT); break;
                case Align.JUSTIFY: layout.set_justify(true); break;
                default: layout.set_alignment(Pango.Alignment.LEFT); break;
            }
            layout.set_tabs(tabs_for(pl.pp, pl.origin, width));
            return layout;
        }

        private void line_metrics(Pango.LayoutIter iter, ParaProps pp, out double height, out double base_off, out double lx) {
            Pango.Rectangle ink, logical;
            iter.get_line_extents(out ink, out logical);
            double nat = logical.height / (double) Pango.SCALE;
            double asc = (iter.get_baseline() - logical.y) / (double) Pango.SCALE;
            lx = logical.x / (double) Pango.SCALE;
            double mult = pp.line.is_nan() ? 1.0 : pp.line;
            switch (pp.line_rule) {
                case LineRule.EXACT:
                    height = mult;
                    base_off = mult * 0.8;
                    break;
                case LineRule.AT_LEAST:
                    height = double.max(nat, mult);
                    base_off = height - (nat - asc);
                    break;
                default:
                    height = nat * mult;
                    base_off = height - (nat - asc);
                    break;
            }
        }

        private void collect_lines(ParaLayout pl, Pango.Layout layout, int byte_base, double y0) {
            var iter = layout.get_iter();
            int n = 0;
            double y = y0;
            do {
                unowned Pango.LayoutLine line = iter.get_line_readonly();
                var li = new LineInfo();
                li.layout = layout;
                li.line_no = n;
                li.byte_base = byte_base;
                double h, b, lx;
                line_metrics(iter, pl.pp, out h, out b, out lx);
                li.x = pl.origin + lx;
                li.top = y;
                li.height = h;
                li.baseline = y + b;
                li.start_byte = line.start_index + byte_base;
                li.end_byte = line.start_index + line.length + byte_base;
                foreach (int pb in pl.text.page_breaks) if (pb == li.end_byte) li.page_break = true;
                foreach (int cb in pl.text.column_breaks) if (cb == li.end_byte) li.column_break = true;
                pl.lines.add(li);
                y += h;
                n++;
            } while (iter.next_line());
        }

        public DocLayout run() {
            cache_gen++;
            prepass();
            DocLayout? last = null;
            for (int pass = 0; pass < 3; pass++) {
                result = new DocLayout();
                result.note_marks = note_marks;
                result.labels = labels;
                if (last != null) {
                    foreach (var e in last.bookmark_page.entries) result.bookmark_page[e.key] = e.value;
                }
                fctx = new FieldContext(doc);
                fctx.filename = filename;
                fctx.filepath = filepath;
                fctx.pages = assumed_pages;
                flow_document();
                finish_pages();
                int total = result.pages.size;
                bool changed = total != assumed_pages;
                assumed_pages = total;
                last = result;
                if (!changed || !uses_numpages()) break;
            }
            var stale = new Gee.ArrayList<Paragraph>();
            foreach (var e in cache.entries) if (e.value.seen < cache_gen - 2) stale.add(e.key);
            foreach (var p in stale) cache.unset(p);
            return result;
        }

        private bool uses_numpages() {
            foreach (var hf in doc.header_footers()) {
                foreach (var b in hf.blocks.items) {
                    var p = b as Paragraph;
                    if (p == null) continue;
                    foreach (var i in p.inlines) if (i is FieldRun && (((FieldRun) i).kind() == "NUMPAGES" || ((FieldRun) i).kind() == "SECTIONPAGES")) return true;
                }
            }
            foreach (var p in doc.paragraphs(false)) foreach (var i in p.inlines) if (i is FieldRun && (((FieldRun) i).kind() == "NUMPAGES" || ((FieldRun) i).kind() == "PAGEREF")) return true;
            return false;
        }

        private Section draft_section() {
            var s = new Section();
            s.page_w = draft_width;
            s.page_h = 1e7;
            s.margin_left = 18;
            s.margin_right = 18;
            s.margin_top = 12;
            s.margin_bottom = 12;
            s.columns = 1;
            return s;
        }

        private void flow_document() {
            outline_hide_below = -1;
            last_outline_level = -1;
            var sections = doc.sections();
            sec_index = 0;
            sec = opts.draft ? draft_section() : sections[0];
            page_number = 0;
            new_page(true);
            var items = doc.body.items;
            for (int i = 0; i < items.size; i++) {
                var b = items[i];
                place_block(b, items, i);
                var p = b as Paragraph;
                if (p != null && p.section != null && !opts.draft) {
                    sec_index++;
                    if (sec_index < sections.size) start_section(sections[sec_index], sections[sec_index - 1]);
                }
            }
            place_endnotes();
        }

        private void start_section(Section next, Section prev) {
            bool same_geometry = (next.page_w - prev.page_w).abs() < 0.5 && (next.page_h - prev.page_h).abs() < 0.5
                && (next.margin_left - prev.margin_left).abs() < 0.5 && (next.margin_right - prev.margin_right).abs() < 0.5;
            if (next.start == SectionStart.CONTINUOUS && same_geometry) {
                if (col_x.length > 1) balance_region();
                double used = y;
                sec = next;
                page.section = next;
                setup_columns(used);
                return;
            }
            if (next.start == SectionStart.NEXT_COLUMN && same_geometry && col + 1 < col_x.length) {
                sec = next;
                next_column();
                return;
            }
            sec = next;
            new_page(true);
            if (next.start == SectionStart.ODD_PAGE && page.number % 2 == 0) new_page(false);
            else if (next.start == SectionStart.EVEN_PAGE && page.number % 2 == 1) new_page(false);
        }

        private int region_line_start = 0;
        private int region_deco_start = 0;
        private int region_obj_start = 0;
        private int region_block_start = -1;
        private Gee.ArrayList<Block> region_blocks = new Gee.ArrayList<Block>();

        private void setup_columns(double top) {
            region_top = top;
            y = top;
            int n = opts.draft ? 1 : int.max(1, sec.columns);
            double left = sec.margin_left + sec.gutter;
            double cw = sec.page_w - left - sec.margin_right;
            col_w = n > 1 ? (cw - sec.column_space * (n - 1)) / n : cw;
            double[] xs = new double[n];
            for (int i = 0; i < n; i++) xs[i] = left + i * (col_w + sec.column_space);
            col_x = xs;
            col = 0;
            region_line_start = page.lines.size;
            region_deco_start = page.decos.size;
            region_obj_start = page.objects.size;
            region_blocks.clear();
        }

        private HeaderFooter? pick_header(Section s, bool first, bool even) {
            HeaderFooter? h = null;
            if (first && s.title_page) h = s.header_first ?? new HeaderFooter();
            else if (even && doc.even_odd_headers) h = s.header_even ?? inherited_header(s, 1);
            else h = s.header_default ?? inherited_header(s, 0);
            return h;
        }

        private HeaderFooter? pick_footer(Section s, bool first, bool even) {
            HeaderFooter? h = null;
            if (first && s.title_page) h = s.footer_first ?? new HeaderFooter();
            else if (even && doc.even_odd_headers) h = s.footer_even ?? inherited_footer(s, 1);
            else h = s.footer_default ?? inherited_footer(s, 0);
            return h;
        }

        private HeaderFooter? inherited_header(Section s, int kind) {
            var list = doc.sections();
            int idx = list.index_of(s);
            for (int i = idx - 1; i >= 0; i--) {
                var h = kind == 1 ? list[i].header_even : list[i].header_default;
                if (h != null) return h;
            }
            return null;
        }

        private HeaderFooter? inherited_footer(Section s, int kind) {
            var list = doc.sections();
            int idx = list.index_of(s);
            for (int i = idx - 1; i >= 0; i--) {
                var h = kind == 1 ? list[i].footer_even : list[i].footer_default;
                if (h != null) return h;
            }
            return null;
        }

        private void new_page(bool section_start) {
            if (page != null) finish_page_notes();
            page = new PageBox();
            page.index = result.pages.size;
            page.width = sec.page_w;
            page.height = sec.page_h;
            page.section = sec;
            page.section_index = sec_index;
            page.first_of_section = section_start;
            if (section_start && sec.page_start >= 0) page_number = sec.page_start;
            else page_number++;
            page.number = page_number;
            page.number_text = Numbering.format_number(page_number, sec.page_format);
            result.pages.add(page);
            exclusions.clear();
            notes_h = 0;
            double top = sec.margin_top;
            double bot = sec.page_h - sec.margin_bottom;
            if (!opts.draft) {
                bool even = page_number % 2 == 0;
                page.header = pick_header(sec, section_start, even);
                page.footer = pick_footer(sec, section_start, even);
                fctx.page = page_number;
                fctx.page_format = sec.page_format;
                if (page.header != null && !page.header.is_blank()) {
                    var f = layout_frame(page.header.blocks, sec.page_w - sec.margin_left - sec.margin_right - sec.gutter, Region.HEADER);
                    double hb = sec.header_dist + f.height;
                    if (hb + 4 > top) top = hb + 4;
                }
                if (page.footer != null && !page.footer.is_blank()) {
                    var f = layout_frame(page.footer.blocks, sec.page_w - sec.margin_left - sec.margin_right - sec.gutter, Region.FOOTER);
                    double ft = sec.page_h - sec.footer_dist - f.height;
                    if (ft - 4 < bot) bot = ft - 4;
                }
            }
            page.body_top = top;
            page.body_bottom = bot;
            page.body_left = sec.margin_left + sec.gutter;
            page.body_right = sec.page_w - sec.margin_right;
            bottom = bot;
            setup_columns(top);
            if (opts.draft) bottom = 1e9;
        }

        private void next_column() {
            if (col + 1 < col_x.length) {
                col++;
                y = region_top;
                return;
            }
            new_page(false);
        }

        private double avail() {
            return bottom - notes_h - y;
        }

        private bool at_top() {
            return (y - region_top).abs() < 0.01;
        }

        private void place_block(Block b, Gee.List<Block> siblings, int idx) {
            region_blocks.add(b);
            if (b is Paragraph) place_paragraph((Paragraph) b, siblings, idx);
            else if (b is Table) place_table((Table) b);
            else if (b is FieldBlock) {
                var fb = (FieldBlock) b;
                for (int i = 0; i < fb.result.size; i++) {
                    var inner = fb.result[i];
                    if (inner is Paragraph) place_paragraph((Paragraph) inner, fb.result.items, i);
                    else if (inner is Table) place_table((Table) inner);
                }
            }
        }

        private bool contextual_skip(Paragraph p, Gee.List<Block> siblings, int idx, bool before) {
            var pp = doc.styles.resolve_para(p);
            if (!pp.contextual.on()) return false;
            int j = before ? idx - 1 : idx + 1;
            if (j < 0 || j >= siblings.size) return false;
            var q = siblings[j] as Paragraph;
            return q != null && q.style == p.style;
        }

        private double keep_chain_height(Gee.List<Block> siblings, int idx) {
            double h = 0;
            int i = idx;
            while (i < siblings.size) {
                var p = siblings[i] as Paragraph;
                if (p == null) break;
                var pl = para_layout(p, col_w);
                if (i > idx) h += pl.space_before;
                bool keep = pl.pp.keep_next.on();
                if (!keep || i > idx + 8) {
                    if (i > idx && pl.lines.size > 0) h += pl.lines[0].height + (pl.lines.size > 1 ? pl.lines[1].height : 0);
                    break;
                }
                h += pl.content_height() + pl.space_after;
                i++;
            }
            return h;
        }

        private void place_paragraph(Paragraph p, Gee.List<Block> siblings, int idx) {
            if (outline_mode && p.parent == doc.body) {
                int lvl = doc.styles.outline_level(p);
                int level = lvl >= 0 ? lvl : 9;
                if (outline_hide_below >= 0) {
                    if (level > outline_hide_below) return;
                    outline_hide_below = -1;
                }
                if (level < 9 && level + 1 > outline_show) return;
                if (level == 9 && !outline_body) return;
                if (collapsed.contains(p)) outline_hide_below = level;
                double shift = (level == 9 ? (last_outline_level + 1) : level) * 22 + 20;
                double saved = col_x[col];
                col_x[col] = saved + shift;
                double saved_w = col_w;
                col_w = double.max(60, col_w - shift);
                double top = y;
                place_paragraph_inner(p, siblings, idx);
                var mark = new Deco(DecoKind.SEPARATOR, saved + shift - 14, top + 2, 10, 10);
                mark.text = level == 9 ? "outline-body" : (collapsed.contains(p) ? "outline-collapsed" : "outline-heading");
                page.decos.add(mark);
                col_x[col] = saved;
                col_w = saved_w;
                if (level < 9) last_outline_level = level;
                return;
            }
            place_paragraph_inner(p, siblings, idx);
        }

        private int last_outline_level = -1;

        private void place_paragraph_inner(Paragraph p, Gee.List<Block> siblings, int idx) {
            fctx.page = page.number;
            var pl = para_layout(p, col_w);
            if (pl.pp.page_break_before.on() && !(at_top() && col == 0 && page.lines.size == 0) && !opts.draft) new_page(false);
            double sb = contextual_skip(p, siblings, idx, true) ? 0 : pl.space_before;
            double sa = contextual_skip(p, siblings, idx, false) ? 0 : pl.space_after;
            if (at_top() && page.lines.size > 0 && col == 0) sb = 0;
            if (at_top() && col > 0) sb = 0;
            if (!opts.draft && !at_top()) {
                double need = pl.content_height() + sb;
                if (pl.pp.keep_next.on()) {
                    double chain = keep_chain_height(siblings, idx) + sb;
                    if (chain <= bottom - region_top && chain > avail()) next_column();
                } else if (pl.pp.keep_lines.on() && need <= bottom - region_top && need > avail()) {
                    next_column();
                } else if (pl.lines.size > 0 && sb + pl.lines[0].height > avail()) {
                    next_column();
                }
            }
            if (!at_top()) y += sb;
            double para_top = y;
            int para_page = page.index;
            var anchored = anchored_floats(pl);
            if (anchored.size > 0) place_floats(pl, anchored, para_top);
            bool constrained = needs_constrained(pl, para_top);
            var placed = new Gee.ArrayList<LineBox>();
            if (!constrained) place_lines(pl, placed);
            else place_lines_constrained(pl, placed);
            decorate_paragraph(pl, placed);
            y += sa;
            index_marks(pl, placed);
        }

        private Gee.ArrayList<ObjRef> anchored_floats(ParaLayout pl) {
            return pl.text.floats;
        }

        private void place_floats(ParaLayout pl, Gee.ArrayList<ObjRef> floats, double para_top) {
            foreach (var o in floats) {
                var f = o.item as FloatingInline;
                if (f == null) continue;
                double fx, fy;
                double col_left = col_x[col];
                switch (f.hrel) {
                    case HRel.PAGE: fx = 0; break;
                    case HRel.MARGIN: fx = page.body_left; break;
                    default: fx = col_left; break;
                }
                double span_w = f.hrel == HRel.PAGE ? page.width : (f.hrel == HRel.MARGIN ? page.body_right - page.body_left : col_w);
                switch (f.halign) {
                    case HAlignObj.CENTER: fx += (span_w - f.width) / 2; break;
                    case HAlignObj.RIGHT: fx += span_w - f.width; break;
                    case HAlignObj.LEFT: break;
                    default: fx += f.hoff; break;
                }
                switch (f.vrel) {
                    case VRel.PAGE: fy = f.voff; break;
                    case VRel.MARGIN: fy = page.body_top + f.voff; break;
                    default: fy = para_top + f.voff; break;
                }
                fx = fx.clamp(0, double.max(0, page.width - f.width));
                fy = fy.clamp(0, double.max(0, page.height - f.height));
                var box = new ObjBox(f, pl.para, fx, fy, f.width, f.height);
                box.floating = true;
                box.region = Region.BODY;
                var shape = f as ShapeRun;
                if (shape != null && shape.text.size > 0) {
                    var inner = layout_frame(shape.text, double.max(12, f.width - 14), Region.FRAME);
                    inner.translate(fx + 7, fy + 4);
                    box.inner = inner;
                    foreach (var il in inner.lines) {
                        il.page = page.index;
                        result.index_line(il);
                    }
                }
                page.objects.add(box);
                if (f.wrap == Wrap.SQUARE || f.wrap == Wrap.TIGHT) exclusions.add(new Rect(fx - f.dist, fy - f.dist * 0.5, f.width + 2 * f.dist, f.height + f.dist));
                else if (f.wrap == Wrap.TOP_BOTTOM) exclusions.add(new Rect(0, fy - f.dist * 0.5, page.width, f.height + f.dist));
            }
        }

        private bool needs_constrained(ParaLayout pl, double top) {
            if (exclusions.size == 0 && pl.dropcap == null) return false;
            double h = pl.content_height() + 40;
            if (pl.dropcap != null) return true;
            foreach (var r in exclusions) {
                if (r.y < top + h && r.y + r.h > top && r.x < col_x[col] + col_w && r.x + r.w > col_x[col]) return true;
            }
            return false;
        }

        private void register(LineBox lb, Gee.ArrayList<LineBox> placed) {
            lb.page = page.index;
            lb.region = Region.BODY;
            page.lines.add(lb);
            result.index_line(lb);
            placed.add(lb);
        }

        private double notes_for_line(ParaLayout pl, LineInfo li) {
            double extra = 0;
            foreach (var item in pl.para.inlines) {
                var r = item as NoteRef;
                if (r == null || r.note.kind != NoteKind.FOOTNOTE) continue;
                int off = pl.para.offset_of(r);
                int b = pl.text.to_byte(off);
                if (b < li.start_byte || b >= li.end_byte) continue;
                if (page.notes.contains(r)) continue;
                var f = layout_note(r);
                extra += f.height + 2;
                if (page.notes.size == 0 && extra > 0) extra += 12;
            }
            return extra;
        }

        private void add_line_notes(ParaLayout pl, LineInfo li, double extra) {
            if (extra <= 0) return;
            foreach (var item in pl.para.inlines) {
                var r = item as NoteRef;
                if (r == null || r.note.kind != NoteKind.FOOTNOTE) continue;
                int off = pl.para.offset_of(r);
                int b = pl.text.to_byte(off);
                if (b < li.start_byte || b >= li.end_byte) continue;
                if (!page.notes.contains(r)) page.notes.add(r);
            }
            notes_h += extra;
        }

        private void place_lines(ParaLayout pl, Gee.ArrayList<LineBox> placed) {
            int n = pl.lines.size;
            int i = 0;
            while (i < n) {
                var li = pl.lines[i];
                double note_extra = opts.draft ? 0 : notes_for_line(pl, li);
                if (!opts.draft && li.height + note_extra > avail() && !(at_top() && placed.size == 0 && page.lines.size == 0)) {
                    if (!at_top() || placed.size > 0) {
                        bool widow = pl.pp.widow != Tri.OFF;
                        if (widow && i == 1 && n > 2 && placed.size == 1 && !at_top_of_para(placed)) {
                            unplace(placed);
                            i = 0;
                            next_column();
                            continue;
                        }
                        if (widow && n - i == 1 && i >= 2 && placed.size >= 2) {
                            var lastp = placed[placed.size - 1];
                            unplace_one(placed, lastp);
                            i--;
                            next_column();
                            continue;
                        }
                        next_column();
                        continue;
                    }
                }
                add_line_notes(pl, li, note_extra);
                var lb = new LineBox();
                lb.pl = pl;
                lb.info = li;
                lb.x = col_x[col];
                lb.top = y;
                lb.baseline = y + (li.baseline - li.top);
                lb.height = li.height;
                lb.clip_x0 = col_x[col];
                lb.clip_x1 = col_x[col] + col_w;
                lb.first = i == 0;
                lb.last = i == n - 1;
                register(lb, placed);
                place_inline_objects(pl, lb);
                y += li.height;
                i++;
                if (li.page_break && !opts.draft && i <= n) new_page(false);
                else if (li.column_break && !opts.draft) next_column();
            }
        }

        private bool at_top_of_para(Gee.ArrayList<LineBox> placed) {
            return placed.size > 0 && (placed[0].top - region_top).abs() < 0.01;
        }

        private void unplace(Gee.ArrayList<LineBox> placed) {
            foreach (var lb in placed) unplace_line(lb);
            placed.clear();
        }

        private void unplace_one(Gee.ArrayList<LineBox> placed, LineBox lb) {
            unplace_line(lb);
            placed.remove(lb);
        }

        private void unplace_line(LineBox lb) {
            var pg = result.pages[lb.page];
            pg.lines.remove(lb);
            var list = result.para_lines[lb.para];
            if (list != null) list.remove(lb);
            if (list != null && list.size == 0) {
                result.para_lines.unset(lb.para);
                result.para_page.unset(lb.para);
            }
            for (int i = pg.objects.size - 1; i >= 0; i--) {
                var o = pg.objects[i];
                if (o.para == lb.para && !o.floating && o.y >= lb.top - 0.01 && o.y <= lb.top + lb.height + 0.01) pg.objects.remove_at(i);
            }
        }

        private void place_lines_constrained(ParaLayout pl, Gee.ArrayList<LineBox> placed) {
            int pos = 0;
            int total = pl.text.text.length;
            bool first = true;
            double first_indent = pl.pp.ind_first.is_nan() ? 0 : pl.pp.ind_first;
            double dc_bottom = y + pl.dropcap_h;
            if (pl.dropcap != null) {
                var r = new Rect(col_x[col] + pl.origin - 1, y, pl.dropcap_w + 1, pl.dropcap_h);
                exclusions.add(r);
                var d = new Deco(DecoKind.FILL, col_x[col] + pl.origin, y, pl.dropcap_w, pl.dropcap_h);
                d.kind = DecoKind.SEPARATOR;
                d.text = "dropcap";
                d.data = pl;
                page.decos.add(d);
            }
            int guard = 0;
            while ((pos < total || first) && guard++ < 10000) {
                double est = pl.text.max_size * 1.25;
                double x0 = col_x[col] + pl.origin;
                double x1 = col_x[col] + col_w - pl.ind_right;
                double seg0, seg1;
                free_interval(x0, x1, y, est, out seg0, out seg1);
                if (seg1 - seg0 < 18) {
                    double jump = next_clear_y(x0, x1, y, est);
                    if (jump > y && jump < bottom) {
                        y = jump;
                        continue;
                    }
                    if (!at_top()) {
                        next_column();
                        continue;
                    }
                    seg0 = x0;
                    seg1 = x1;
                }
                double ind = first && pl.label == null ? first_indent : 0;
                if (ind < 0) ind = 0;
                var layout = make_layout(pl, seg1 - seg0 - ind, 0, pos, -1);
                if (pl.dropcap != null && pos == 0) {
                    var attrs = layout.get_attributes().copy();
                    var z = Pango.Rectangle();
                    var a = Pango.AttrShape.@new(z, z);
                    a.start_index = 0;
                    a.end_index = pl.text.text.index_of_nth_char(1);
                    attrs.insert((owned) a);
                    layout.set_attributes(attrs);
                }
                layout.set_indent(0);
                var iter = layout.get_iter();
                unowned Pango.LayoutLine line = iter.get_line_readonly();
                double h, b, lx;
                line_metrics(iter, pl.pp, out h, out b, out lx);
                if (h > avail() && !(at_top() && placed.size == 0)) {
                    next_column();
                    continue;
                }
                var li = new LineInfo();
                li.layout = layout;
                li.line_no = 0;
                li.byte_base = pos;
                li.x = 0;
                li.top = 0;
                li.height = h;
                li.baseline = b;
                li.start_byte = pos;
                int len = line.length;
                if (len == 0 && pos < total) len = total - pos;
                li.end_byte = pos + len;
                bool is_last = li.end_byte >= total || layout.get_line_count() == 1;
                if (pl.pp.align == Align.JUSTIFY && !is_last) {
                    layout.set_width((int) ((seg1 - seg0 - ind) * Pango.SCALE));
                }
                foreach (int pb in pl.text.page_breaks) if (pb == li.end_byte) li.page_break = true;
                var lb = new LineBox();
                lb.pl = pl;
                lb.info = li;
                lb.x = seg0 + ind + lx;
                lb.top = y;
                lb.baseline = y + b;
                lb.height = h;
                lb.clip_x0 = col_x[col];
                lb.clip_x1 = col_x[col] + col_w;
                lb.first = first;
                lb.last = is_last;
                register(lb, placed);
                place_inline_objects(pl, lb);
                y += h;
                first = false;
                pos = li.end_byte;
                if (is_last) break;
                if (li.page_break) new_page(false);
            }
            if (pl.dropcap != null && y < dc_bottom && dc_bottom < bottom) y = dc_bottom;
        }


        private void free_interval(double x0, double x1, double top, double h, out double s0, out double s1) {
            double a = x0;
            double b = x1;
            double best0 = x0, best1 = x1;
            var blocks = new Gee.ArrayList<Rect>();
            foreach (var r in exclusions) {
                if (r.y < top + h && r.y + r.h > top && r.x < x1 && r.x + r.w > x0) blocks.add(r);
            }
            if (blocks.size == 0) {
                s0 = x0;
                s1 = x1;
                return;
            }
            blocks.sort((p, q) => p.x < q.x ? -1 : (p.x > q.x ? 1 : 0));
            double best = -1;
            double cur = a;
            foreach (var r in blocks) {
                if (r.x > cur && r.x - cur > best) {
                    best = r.x - cur;
                    best0 = cur;
                    best1 = r.x;
                }
                cur = double.max(cur, r.x + r.w);
            }
            if (b - cur > best) {
                best = b - cur;
                best0 = cur;
                best1 = b;
            }
            if (best <= 0) {
                s0 = x0;
                s1 = x0;
                return;
            }
            s0 = best0;
            s1 = best1;
        }

        private double next_clear_y(double x0, double x1, double top, double h) {
            double ny = top;
            foreach (var r in exclusions) {
                if (r.y < top + h && r.y + r.h > top && r.x < x1 && r.x + r.w > x0) ny = double.max(ny, r.y + r.h);
            }
            return ny;
        }

        private void place_inline_objects(ParaLayout pl, LineBox lb) {
            foreach (var o in pl.text.objects) {
                if (o.byte_index < lb.info.start_byte || o.byte_index >= lb.info.end_byte) continue;
                double w, asc, desc;
                bool fl;
                TextBuilder.object_metrics(o.item, out w, out asc, out desc, out fl);
                double ox = lb.caret_x(o.byte_index);
                var box = new ObjBox(o.item, pl.para, ox, lb.baseline - asc, w, asc + desc);
                box.region = lb.region;
                var shape = o.item as ShapeRun;
                if (shape != null && shape.text.size > 0) {
                    var inner = layout_frame(shape.text, double.max(12, w - 14), Region.FRAME);
                    inner.translate(ox + 7, lb.baseline - asc + 4);
                    box.inner = inner;
                    foreach (var il in inner.lines) {
                        il.page = lb.page;
                        result.index_line(il);
                    }
                }
                var pg = result.pages[lb.page];
                pg.objects.add(box);
            }
        }

        private void decorate_paragraph(ParaLayout pl, Gee.ArrayList<LineBox> placed) {
            if (placed.size == 0) return;
            var pp = pl.pp;
            bool border = (pp.border_top != null && pp.border_top.visible()) || (pp.border_bottom != null && pp.border_bottom.visible())
                || (pp.border_left != null && pp.border_left.visible()) || (pp.border_right != null && pp.border_right.visible());
            if (pp.shading == null && !border && pl.label == null) return;
            int i = 0;
            while (i < placed.size) {
                int pg = placed[i].page;
                double top = placed[i].top;
                double bot = top;
                int j = i;
                double cx0 = placed[i].clip_x0;
                while (j < placed.size && placed[j].page == pg && (placed[j].clip_x0 - cx0).abs() < 0.5) {
                    bot = placed[j].top + placed[j].height;
                    j++;
                }
                var page_box = result.pages[pg];
                double x0 = cx0 + pl.ind_left - 4;
                double x1 = placed[i].clip_x1 - pl.ind_right + 4;
                if (pp.shading != null) {
                    var d = new Deco(DecoKind.FILL, x0, top - 1, x1 - x0, bot - top + 2);
                    d.color = pp.shading;
                    page_box.decos.add(d);
                }
                bool first_frag = i == 0;
                bool last_frag = j == placed.size;
                if (pp.border_top != null && pp.border_top.visible() && first_frag) page_box.decos.add(border_line(x0, top - 2, x1, top - 2, pp.border_top));
                if (pp.border_bottom != null && pp.border_bottom.visible() && last_frag) page_box.decos.add(border_line(x0, bot + 2, x1, bot + 2, pp.border_bottom));
                if (pp.border_left != null && pp.border_left.visible()) page_box.decos.add(border_line(x0, top - 2, x0, bot + 2, pp.border_left));
                if (pp.border_right != null && pp.border_right.visible()) page_box.decos.add(border_line(x1, top - 2, x1, bot + 2, pp.border_right));
                i = j;
            }
        }

        private Deco border_line(double x0, double y0, double x1, double y1, Border b) {
            var d = new Deco(DecoKind.LINE, x0, y0, x1 - x0, y1 - y0);
            d.color = b.color;
            d.width = b.width;
            d.style = b.style;
            return d;
        }

        private void index_marks(ParaLayout pl, Gee.ArrayList<LineBox> placed) {
            if (placed.size == 0) return;
            int off = 0;
            foreach (var item in pl.para.inlines) {
                var m = item as Mark;
                if (m != null) {
                    int b = pl.text.to_byte(off);
                    LineBox? where = placed[0];
                    foreach (var lb in placed) if (b >= lb.info.start_byte && b <= lb.info.end_byte) {
                        where = lb;
                        break;
                    }
                    if (m.kind == MarkKind.BOOKMARK_START && !result.bookmark_page.has_key(m.name)) {
                        result.bookmark_page[m.name] = result.pages[where.page].number;
                    } else if (m.kind == MarkKind.COMMENT_START || m.kind == MarkKind.COMMENT_END) {
                        var pg = result.pages[where.page];
                        if (m.kind == MarkKind.COMMENT_START) {
                            var a = new CommentAnchor();
                            a.id = m.name;
                            a.x = where.caret_x(b);
                            a.y = where.top;
                            a.y_end = where.top + where.height;
                            a.x_end = a.x;
                            pg.comments.add(a);
                        } else {
                            foreach (var p2 in result.pages) {
                                foreach (var a in p2.comments) if (a.id == m.name) {
                                    a.x_end = where.caret_x(b);
                                    a.y_end = where.top + where.height;
                                }
                            }
                        }
                    }
                }
                off += item.length;
            }
            foreach (var lb in placed) {
                foreach (var o in pl.text.tabs) {
                    if (o.byte_index < lb.info.start_byte || o.byte_index >= lb.info.end_byte) continue;
                    add_leader(pl, lb, o.byte_index);
                }
            }
        }

        private void add_leader(ParaLayout pl, LineBox lb, int byte_index) {
            if (pl.pp.tabs == null) return;
            double x0 = lb.caret_x(byte_index);
            double x1 = lb.caret_x(byte_index + 1);
            if (x1 - x0 < 6) return;
            double rel = x1 - lb.clip_x0;
            TabStop? stop = null;
            foreach (var t in pl.pp.tabs) {
                double tabx = t.pos;
                if (stop == null && (tabx - rel).abs() < 40 && tabx >= rel - 40) stop = t;
            }
            if (stop == null || stop.leader == TabLeader.NONE) return;
            var d = new Deco(DecoKind.LEADER, x0 + 2, lb.baseline, x1 - x0 - 4, 0);
            d.text = stop.leader == TabLeader.DOT ? "." : (stop.leader == TabLeader.HYPHEN ? "-" : "_");
            d.behind = false;
            result.pages[lb.page].decos.add(d);
        }

        public Frame layout_frame(BlockList blocks, double width, Region region, CharProps? overlay = null) {
            var f = new Frame();
            double fy = 0;
            for (int i = 0; i < blocks.size; i++) {
                var b = blocks[i];
                var p = b as Paragraph;
                if (p != null) {
                    var pl = para_layout(p, width, overlay);
                    bool ctx_before = contextual_skip(p, blocks.items, i, true);
                    bool ctx_after = contextual_skip(p, blocks.items, i, false);
                    if (i > 0 && !ctx_before) fy += pl.space_before;
                    var placed = new Gee.ArrayList<LineBox>();
                    for (int k = 0; k < pl.lines.size; k++) {
                        var li = pl.lines[k];
                        var lb = new LineBox();
                        lb.pl = pl;
                        lb.info = li;
                        lb.x = 0;
                        lb.top = fy + li.top;
                        lb.baseline = fy + li.baseline;
                        lb.height = li.height;
                        lb.region = region;
                        lb.clip_x0 = 0;
                        lb.clip_x1 = width;
                        lb.first = k == 0;
                        lb.last = k == pl.lines.size - 1;
                        f.lines.add(lb);
                        placed.add(lb);
                        foreach (var o in pl.text.objects) {
                            if (o.byte_index < li.start_byte || o.byte_index >= li.end_byte) continue;
                            double w, asc, desc;
                            bool fl;
                            TextBuilder.object_metrics(o.item, out w, out asc, out desc, out fl);
                            double ox = lb.caret_x(o.byte_index);
                            var box = new ObjBox(o.item, p, ox, lb.baseline - asc, w, asc + desc);
                            box.region = region;
                            f.objects.add(box);
                        }
                    }
                    foreach (var o in pl.text.floats) {
                        var fl2 = o.item as FloatingInline;
                        if (fl2 == null) continue;
                        double fx = fl2.halign == HAlignObj.CENTER ? (width - fl2.width) / 2 : (fl2.halign == HAlignObj.RIGHT ? width - fl2.width : fl2.hoff);
                        var box = new ObjBox(fl2, p, fx, fy + fl2.voff, fl2.width, fl2.height);
                        box.floating = true;
                        box.region = region;
                        f.objects.add(box);
                    }
                    double ph = pl.content_height();
                    if (pl.pp.shading != null) {
                        var d = new Deco(DecoKind.FILL, pl.ind_left - 2, fy, width - pl.ind_left - pl.ind_right + 4, ph);
                        d.color = pl.pp.shading;
                        f.decos.add(d);
                    }
                    if (pl.pp.border_bottom != null && pl.pp.border_bottom.visible()) f.decos.add(border_line(pl.ind_left, fy + ph + 1, width - pl.ind_right, fy + ph + 1, pl.pp.border_bottom));
                    if (pl.pp.border_top != null && pl.pp.border_top.visible()) f.decos.add(border_line(pl.ind_left, fy - 1, width - pl.ind_right, fy - 1, pl.pp.border_top));
                    fy += ph;
                    if (!ctx_after && i < blocks.size - 1) fy += pl.space_after;
                    continue;
                }
                var t = b as Table;
                if (t != null) {
                    var tf = table_frame(t, width, region);
                    tf.translate(0, fy);
                    merge_frame(f, tf);
                    fy += tf.height;
                    continue;
                }
                var fb = b as FieldBlock;
                if (fb != null) {
                    var inner = layout_frame(fb.result, width, region, overlay);
                    inner.translate(0, fy);
                    merge_frame(f, inner);
                    fy += inner.height;
                }
            }
            f.height = fy;
            return f;
        }

        private static void merge_frame(Frame into, Frame from) {
            into.lines.add_all(from.lines);
            into.decos.add_all(from.decos);
            into.objects.add_all(from.objects);
        }

        private Frame layout_note(NoteRef r) {
            var blocks = r.note.blocks;
            var f = layout_frame(blocks, page.body_right - page.body_left, Region.NOTES);
            return f;
        }

        private void finish_page_notes() {
            if (page == null || page.notes.size == 0) return;
            double width = page.body_right - page.body_left;
            var frames = new Gee.ArrayList<Frame>();
            double total = 12;
            foreach (var r in page.notes) {
                var f = layout_note(r);
                frames.add(f);
                total += f.height + 2;
            }
            double ny = page.body_bottom - total;
            var sep = new Deco(DecoKind.LINE, page.body_left, ny + 6, double.min(144, width), 0);
            sep.width = 0.5;
            page.decos.add(sep);
            ny += 12;
            for (int i = 0; i < frames.size; i++) {
                var f = frames[i];
                string mark = note_mark(page.notes[i]);
                var markbox = new Deco(DecoKind.SEPARATOR, page.body_left, ny, 0, 0);
                markbox.text = "notemark:" + mark;
                if (f.lines.size > 0) markbox.y = f.lines[0].baseline + ny;
                page.decos.add(markbox);
                f.translate(page.body_left, ny);
                foreach (var lb in f.lines) {
                    lb.page = page.index;
                    page.lines.add(lb);
                    result.index_line(lb);
                }
                page.decos.add_all(f.decos);
                foreach (var o in f.objects) page.objects.add(o);
                ny += f.height + 2;
            }
        }

        private void place_endnotes() {
            var ends = new Gee.ArrayList<Note>();
            foreach (var n in doc.notes(NoteKind.ENDNOTE)) ends.add(n);
            if (ends.size == 0) return;
            y += 12;
            if (avail() < 30) next_column();
            var sep = new Deco(DecoKind.LINE, col_x[col], y, double.min(144, col_w), 0);
            page.decos.add(sep);
            y += 8;
            foreach (var n in ends) {
                var f = layout_frame(n.blocks, col_w, Region.NOTES);
                if (f.height > avail() && !at_top()) next_column();
                string mark = note_marks[n] ?? "";
                var markbox = new Deco(DecoKind.SEPARATOR, col_x[col], y + (f.lines.size > 0 ? f.lines[0].baseline : 10), 0, 0);
                markbox.text = "notemark:" + mark;
                page.decos.add(markbox);
                f.translate(col_x[col], y);
                foreach (var lb in f.lines) {
                    lb.page = page.index;
                    page.lines.add(lb);
                    result.index_line(lb);
                }
                page.decos.add_all(f.decos);
                page.objects.add_all(f.objects);
                y += f.height + 4;
            }
        }

        private Frame table_frame(Table t, double avail_w, Region region) {
            var rows = measure_table(t, avail_w, region);
            var f = new Frame();
            double ty = 0;
            for (int r = 0; r < rows.size; r++) {
                var rm = rows[r];
                emit_row(f, t, rm, rows, 0, ty, 0, rm.height, region);
                ty += rm.height;
            }
            f.height = ty;
            return f;
        }

        private class CellMeasure {
            public TableCell cell;
            public Frame frame;
            public double x;
            public double w;
            public int col;
            public int rspan = 1;
        }

        private class RowMeasure {
            public TableRow row;
            public int index;
            public Gee.ArrayList<CellMeasure> cells = new Gee.ArrayList<CellMeasure>();
            public double height;
        }

        private Gee.ArrayList<RowMeasure> measure_table(Table t, double avail_w, Region region) {
            double[] grid = t.grid;
            if (grid.length == 0) {
                int n = int.max(1, t.columns());
                grid = new double[n];
                for (int i = 0; i < n; i++) grid[i] = avail_w / n;
            }
            double total = 0;
            foreach (double g in grid) total += g;
            double target = total;
            if (t.width > 0) target = t.width_pct ? avail_w * t.width / 100.0 : t.width;
            if (target > avail_w - t.indent) target = avail_w - double.max(0, t.indent);
            double scale = total > 0 ? target / total : 1;
            double[] xs = new double[grid.length + 1];
            for (int i = 0; i < grid.length; i++) xs[i + 1] = xs[i] + grid[i] * scale;
            var rows = new Gee.ArrayList<RowMeasure>();
            var style = doc.styles.get(t.style);
            for (int r = 0; r < t.rows.size; r++) {
                var row = t.rows[r];
                var rm = new RowMeasure();
                rm.row = row;
                rm.index = r;
                double h = 0;
                int col = 0;
                foreach (var cell in row.cells) {
                    int c1 = int.min(col + cell.span, grid.length);
                    var cm = new CellMeasure();
                    cm.cell = cell;
                    cm.col = col;
                    cm.x = xs[int.min(col, grid.length)];
                    cm.w = xs[c1] - cm.x;
                    if (cell.vmerge != VMerge.CONTINUE) {
                        double inner = double.max(6, cm.w - t.margin_l - t.margin_r);
                        CharProps? ov = null;
                        if (style != null && style.table_header_chr != null && (row.header || (r == 0 && t.look_first_row))) ov = style.table_header_chr;
                        cm.frame = layout_frame(cell.blocks, inner, region, ov);
                        if (cell.vmerge == VMerge.NONE) h = double.max(h, cm.frame.height + t.margin_t + t.margin_b + 2);
                        else h = double.max(h, (cm.frame.lines.size > 0 ? cm.frame.lines[0].height : 12) + t.margin_t + t.margin_b + 2);
                    }
                    rm.cells.add(cm);
                    col = c1;
                }
                if (row.height > 0) h = row.height_exact ? row.height : double.max(h, row.height);
                if (h < 8) h = 14;
                rm.height = h;
                rows.add(rm);
            }
            for (int r = 0; r < rows.size; r++) {
                foreach (var cm in rows[r].cells) {
                    if (cm.cell.vmerge != VMerge.RESTART) continue;
                    int span = 1;
                    double sum = rows[r].height;
                    for (int k = r + 1; k < rows.size; k++) {
                        var below = t.cell_at_grid(t.rows[k], cm.col);
                        if (below == null || below.vmerge != VMerge.CONTINUE) break;
                        span++;
                        sum += rows[k].height;
                    }
                    cm.rspan = span;
                    double need = cm.frame.height + t.margin_t + t.margin_b + 2;
                    if (need > sum) rows[r + span - 1].height += need - sum;
                }
            }
            return rows;
        }

        private double table_x(Table t, double x0, double width, double tw) {
            if (t.align == Align.CENTER) return x0 + (width - tw) / 2;
            if (t.align == Align.RIGHT) return x0 + width - tw;
            return x0 + t.indent;
        }

        private void emit_row(Frame f, Table t, RowMeasure rm, Gee.ArrayList<RowMeasure> rows, double x0, double y0, double clip_from, double clip_to, Region region) {
            var style = doc.styles.get(t.style);
            int r = rm.index;
            bool header = rm.row.header || (r == 0 && t.look_first_row && style != null && style.table_header_shading != null);
            foreach (var cm in rm.cells) {
                if (cm.cell.vmerge == VMerge.CONTINUE) continue;
                double cx = x0 + cm.x;
                double ch = rm.height;
                if (cm.rspan > 1) {
                    ch = 0;
                    for (int k = 0; k < cm.rspan && r + k < rows.size; k++) ch += rows[r + k].height;
                }
                string? shade = cm.cell.shading;
                if (shade == null && style != null) {
                    if (header && style.table_header_shading != null) shade = style.table_header_shading;
                    else if (t.look_banded_rows && style.table_band_shading != null && (r % 2 == (t.look_first_row ? 1 : 0))) shade = style.table_band_shading;
                }
                if (shade != null) {
                    var d = new Deco(DecoKind.FILL, cx, y0, cm.w, ch);
                    d.color = shade;
                    f.decos.add(d);
                }
                double inner_top = y0 + t.margin_t + 1;
                double content_h = cm.frame.height;
                if (cm.cell.valign == CellVAlign.CENTER) inner_top += (ch - content_h - t.margin_t - t.margin_b - 2) / 2;
                else if (cm.cell.valign == CellVAlign.BOTTOM) inner_top += ch - content_h - t.margin_t - t.margin_b - 2;
                var frame = cm.frame;
                double ox = cx + t.margin_l;
                foreach (var lb in frame.lines) {
                    if (lb.top < clip_from - 0.01 || lb.top + lb.height > clip_to + 0.01) continue;
                    var c = clone_line(lb);
                    c.x += ox;
                    c.top += inner_top - clip_from;
                    c.baseline += inner_top - clip_from;
                    c.clip_x0 = cx;
                    c.clip_x1 = cx + cm.w;
                    f.lines.add(c);
                }
                foreach (var d in frame.decos) {
                    if (d.y < clip_from - 0.01 || d.y > clip_to + 0.01) continue;
                    var dd = new Deco(d.kind, d.x + ox, d.y + inner_top - clip_from, d.w, d.h);
                    dd.color = d.color;
                    dd.width = d.width;
                    dd.style = d.style;
                    dd.text = d.text;
                    f.decos.add(dd);
                }
                foreach (var o in frame.objects) {
                    if (o.y < clip_from - 0.01 || o.y > clip_to + 0.01) continue;
                    var oo = new ObjBox(o.item, o.para, o.x + ox, o.y + inner_top - clip_from, o.w, o.h);
                    oo.region = o.region;
                    oo.floating = o.floating;
                    f.objects.add(oo);
                }
                Border? def = style != null ? style.table_border : null;
                Border? bt = cm.cell.top ?? (r == 0 ? t.border_top : t.border_h) ?? def;
                Border? bb = cm.cell.bottom ?? (r + cm.rspan >= t.rows.size ? t.border_bottom : t.border_h) ?? def;
                Border? bl = cm.cell.left ?? (cm.col == 0 ? t.border_left : t.border_v) ?? def;
                Border? br = cm.cell.right ?? (cm.col + cm.cell.span >= t.grid.length ? t.border_right : t.border_v) ?? def;
                if (bt != null && bt.visible()) f.decos.add(border_line(cx, y0, cx + cm.w, y0, bt));
                if (bb != null && bb.visible()) f.decos.add(border_line(cx, y0 + ch, cx + cm.w, y0 + ch, bb));
                if (bl != null && bl.visible()) f.decos.add(border_line(cx, y0, cx, y0 + ch, bl));
                if (br != null && br.visible()) f.decos.add(border_line(cx + cm.w, y0, cx + cm.w, y0 + ch, br));
                if (!opts.print && (bt == null || !bt.visible()) && (bl == null || !bl.visible())) {
                    var g = new Deco(DecoKind.STROKE, cx, y0, cm.w, ch);
                    g.color = "#c8d2e0";
                    g.width = 0.3;
                    g.style = "gridline";
                    f.decos.add(g);
                }
            }
        }


        private LineBox clone_line(LineBox lb) {
            var c = new LineBox();
            c.pl = lb.pl;
            c.info = lb.info;
            c.x = lb.x;
            c.top = lb.top;
            c.baseline = lb.baseline;
            c.height = lb.height;
            c.region = lb.region;
            c.clip_x0 = lb.clip_x0;
            c.clip_x1 = lb.clip_x1;
            c.first = lb.first;
            c.last = lb.last;
            return c;
        }

        private void place_table(Table t) {
            double tw_total = 0;
            var rows = measure_table(t, col_w, Region.BODY);
            foreach (double g in t.grid) tw_total += g;
            double tw = 0;
            if (rows.size > 0 && rows[0].cells.size > 0) {
                var lastc = rows[0].cells[rows[0].cells.size - 1];
                tw = lastc.x + lastc.w;
            }
            var header_rows = new Gee.ArrayList<RowMeasure>();
            foreach (var rm in rows) {
                if (rm.row.header) header_rows.add(rm);
                else break;
            }
            for (int r = 0; r < rows.size; r++) {
                var rm = rows[r];
                double h = rm.height;
                if (!opts.draft && h > avail() && !at_top()) {
                    bool split = !rm.row.cant_split && h > bottom - region_top;
                    if (!split || avail() < 30) {
                        next_column();
                        if (header_rows.size > 0 && r >= header_rows.size) emit_headers(t, header_rows, rows, tw);
                    }
                }
                double from = 0;
                while (true) {
                    double take = opts.draft ? h - from : double.min(h - from, avail());
                    if (take <= 0.5 && !at_top()) {
                        next_column();
                        if (header_rows.size > 0 && r >= header_rows.size) emit_headers(t, header_rows, rows, tw);
                        continue;
                    }
                    var f = new Frame();
                    double cut = from + take;
                    if (cut < h - 0.5) cut = split_point(rm, from, cut);
                    if (cut <= from + 0.5) cut = from + take;
                    var part = new RowMeasure();
                    part.row = rm.row;
                    part.index = rm.index;
                    part.cells = rm.cells;
                    part.height = cut - from;
                    emit_row(f, t, part, rows, 0, 0, from, cut, Region.BODY);
                    f.translate(table_x(t, col_x[col], col_w, tw), y);
                    add_frame_to_page(f);
                    y += cut - from;
                    from = cut;
                    if (from >= h - 0.5) break;
                    next_column();
                    if (header_rows.size > 0 && r >= header_rows.size) emit_headers(t, header_rows, rows, tw);
                }
            }
        }

        private double split_point(RowMeasure rm, double from, double cut) {
            double best = cut;
            foreach (var cm in rm.cells) {
                if (cm.frame == null) continue;
                foreach (var lb in cm.frame.lines) {
                    double lt = lb.top + 1;
                    double lbot = lb.top + lb.height + 1;
                    if (lt < cut && lbot > cut && lt > from) best = double.min(best, lt);
                }
            }
            return best;
        }

        private void emit_headers(Table t, Gee.ArrayList<RowMeasure> headers, Gee.ArrayList<RowMeasure> rows, double tw) {
            foreach (var hm in headers) {
                var f = new Frame();
                emit_row(f, t, hm, rows, 0, 0, 0, hm.height, Region.BODY);
                f.translate(table_x(t, col_x[col], col_w, tw), y);
                add_frame_to_page(f);
                y += hm.height;
            }
        }

        private void add_frame_to_page(Frame f) {
            foreach (var lb in f.lines) {
                lb.page = page.index;
                lb.region = Region.BODY;
                page.lines.add(lb);
                result.index_line(lb);
                var tmp = new Gee.ArrayList<LineBox>();
                tmp.add(lb);
                index_marks(lb.pl, tmp);
            }
            page.decos.add_all(f.decos);
            page.objects.add_all(f.objects);
        }

        private void balance_region() {
            if (region_blocks.size == 0 || col_x.length < 2 || page.notes.size > 0) return;
            var first_page = page;
            bool single_page = true;
            foreach (var b in region_blocks) {
                var p = b as Paragraph;
                if (p != null && result.para_page.has_key(p) && result.para_page[p] != first_page.index) single_page = false;
            }
            if (!single_page) return;
            double lo = 12;
            double hi = bottom - region_top;
            var blocks = new Gee.ArrayList<Block>();
            blocks.add_all(region_blocks);
            double top = region_top;
            int lstart = region_line_start;
            int dstart = region_deco_start;
            int ostart = region_obj_start;
            double best = hi;
            for (int iter = 0; iter < 12; iter++) {
                double mid = (lo + hi) / 2;
                if (trial(blocks, top, mid, lstart, dstart, ostart)) {
                    best = mid;
                    hi = mid;
                } else {
                    lo = mid;
                }
            }
            trial(blocks, top, best, lstart, dstart, ostart);
            y = top + best;
            double maxy = top;
            for (int i = lstart; i < page.lines.size; i++) maxy = double.max(maxy, page.lines[i].top + page.lines[i].height);
            y = maxy;
            bottom = page.body_bottom;
        }

        private bool trial(Gee.ArrayList<Block> blocks, double top, double height, int lstart, int dstart, int ostart) {
            var pg = page;
            while (pg.lines.size > lstart) {
                var lb = pg.lines[pg.lines.size - 1];
                pg.lines.remove_at(pg.lines.size - 1);
                var list = result.para_lines[lb.para];
                if (list != null) {
                    list.remove(lb);
                    if (list.size == 0) {
                        result.para_lines.unset(lb.para);
                        result.para_page.unset(lb.para);
                    }
                }
            }
            while (pg.decos.size > dstart) pg.decos.remove_at(pg.decos.size - 1);
            while (pg.objects.size > ostart) pg.objects.remove_at(pg.objects.size - 1);
            int pages_before = result.pages.size;
            col = 0;
            y = top;
            region_top = top;
            bottom = top + height;
            var saved = new Gee.ArrayList<Block>();
            saved.add_all(blocks);
            region_blocks.clear();
            bool ok = true;
            for (int i = 0; i < saved.size; i++) {
                place_block(saved[i], saved, i);
                if (result.pages.size != pages_before) {
                    ok = false;
                    break;
                }
            }
            if (result.pages.size != pages_before) {
                while (result.pages.size > pages_before) {
                    var gone = result.pages.remove_at(result.pages.size - 1);
                    foreach (var lb in gone.lines) {
                        var list = result.para_lines[lb.para];
                        if (list != null) {
                            list.remove(lb);
                            if (list.size == 0) {
                                result.para_lines.unset(lb.para);
                                result.para_page.unset(lb.para);
                            }
                        }
                    }
                }
                page = pg;
                page_number = pg.number;
                ok = false;
            }
            region_blocks.clear();
            region_blocks.add_all(saved);
            return ok;
        }

        private void finish_pages() {
            finish_page_notes();
            page = null;
            int total = result.pages.size;
            var sec_pages = new Gee.HashMap<int, int>();
            foreach (var p in result.pages) sec_pages[p.section_index] = (sec_pages.has_key(p.section_index) ? sec_pages[p.section_index] : 0) + 1;
            foreach (var p in result.pages) {
                if (opts.draft) continue;
                var s = p.section;
                fctx.page = p.number;
                fctx.pages = total;
                fctx.section = p.section_index + 1;
                fctx.section_pages = sec_pages[p.section_index];
                fctx.page_format = s.page_format;
                double cw = s.page_w - s.margin_left - s.margin_right - s.gutter;
                if (p.header != null && !p.header.is_blank()) {
                    var f = layout_frame(p.header.blocks, cw, Region.HEADER);
                    f.translate(s.margin_left + s.gutter, s.header_dist);
                    p.header_bottom = s.header_dist + f.height;
                    attach_frame(p, f);
                }
                if (p.footer != null && !p.footer.is_blank()) {
                    var f = layout_frame(p.footer.blocks, cw, Region.FOOTER);
                    double top = s.page_h - s.footer_dist - f.height;
                    f.translate(s.margin_left + s.gutter, top);
                    p.footer_top = top;
                    attach_frame(p, f);
                }
                if (s.columns > 1 && s.column_sep) {
                    double left = s.margin_left + s.gutter;
                    double colw = (s.page_w - left - s.margin_right - s.column_space * (s.columns - 1)) / s.columns;
                    for (int c = 1; c < s.columns; c++) {
                        double x = left + c * colw + (c - 0.5) * s.column_space;
                        var d = new Deco(DecoKind.LINE, x, p.body_top, 0, p.body_bottom - p.body_top);
                        p.decos.add(d);
                    }
                }
            }
        }

        private void attach_frame(PageBox p, Frame f) {
            foreach (var lb in f.lines) {
                lb.page = p.index;
                p.lines.add(lb);
                result.index_line(lb);
            }
            p.decos.add_all(f.decos);
            p.objects.add_all(f.objects);
        }

        public Frame measure_blocks(BlockList blocks, double width) {
            cache_gen++;
            prepass();
            return layout_frame(blocks, width, Region.FRAME);
        }
    }
}
