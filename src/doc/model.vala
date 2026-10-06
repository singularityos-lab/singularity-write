namespace Write {

    public enum Tri {
        INHERIT = -1,
        OFF = 0,
        ON = 1;

        public static Tri of(bool v) {
            return v ? ON : OFF;
        }

        public bool on() {
            return this == ON;
        }
    }

    public enum Align {
        INHERIT = -1,
        LEFT,
        CENTER,
        RIGHT,
        JUSTIFY
    }

    public enum VAlign {
        INHERIT = -1,
        BASELINE,
        SUPER,
        SUB
    }

    public enum Underline {
        INHERIT = -1,
        NONE,
        SINGLE,
        DOUBLE,
        DOTTED,
        DASHED,
        WAVY,
        THICK,
        WORDS
    }

    public enum Caps {
        INHERIT = -1,
        NONE,
        ALL,
        SMALL
    }

    public enum LineRule {
        AUTO,
        EXACT,
        AT_LEAST
    }

    public enum TabAlign {
        LEFT,
        CENTER,
        RIGHT,
        DECIMAL,
        BAR,
        CLEAR
    }

    public enum TabLeader {
        NONE,
        DOT,
        HYPHEN,
        UNDERSCORE
    }

    public enum RevKind {
        INSERT,
        DELETE,
        FORMAT
    }

    public class Revision : Object {
        public RevKind kind;
        public string author;
        public string date;
        public int id;

        public Revision(RevKind kind, string author, string date = "") {
            this.kind = kind;
            this.author = author;
            this.date = date != "" ? date : new DateTime.now_utc().format("%Y-%m-%dT%H:%M:%SZ");
        }

        public Revision copy() {
            var r = new Revision(kind, author, date);
            r.id = id;
            return r;
        }
    }

    public class Border : Object {
        public string style = "single";
        public double width = 0.5;
        public string color = "#000000";
        public double space = 0;

        public Border.with(string style, double width, string color) {
            this.style = style;
            this.width = width;
            this.color = color;
        }

        public Border copy() {
            var b = new Border.with(style, width, color);
            b.space = space;
            return b;
        }

        public bool visible() {
            return style != "none" && style != "nil" && width > 0;
        }

        public bool equal(Border? o) {
            return o != null && o.style == style && o.width == width && o.color == color && o.space == space;
        }
    }

    public class TabStop : Object {
        public double pos;
        public TabAlign align;
        public TabLeader leader;

        public TabStop(double pos, TabAlign align = TabAlign.LEFT, TabLeader leader = TabLeader.NONE) {
            this.pos = pos;
            this.align = align;
            this.leader = leader;
        }

        public TabStop copy() {
            return new TabStop(pos, align, leader);
        }
    }

    public class CharProps : Object {
        public string? font = null;
        public double size = 0;
        public Tri bold = Tri.INHERIT;
        public Tri italic = Tri.INHERIT;
        public Tri strike = Tri.INHERIT;
        public Tri dstrike = Tri.INHERIT;
        public Tri hidden = Tri.INHERIT;
        public Tri outline = Tri.INHERIT;
        public Tri shadow = Tri.INHERIT;
        public Underline underline = Underline.INHERIT;
        public Caps caps = Caps.INHERIT;
        public VAlign valign = VAlign.INHERIT;
        public string? color = null;
        public string? highlight = null;
        public string? shading = null;
        public double spacing = double.NAN;
        public double position = double.NAN;
        public string? lang = null;
        public string? style = null;
        public string? link = null;

        public CharProps copy() {
            var c = new CharProps();
            c.font = font;
            c.size = size;
            c.bold = bold;
            c.italic = italic;
            c.strike = strike;
            c.dstrike = dstrike;
            c.hidden = hidden;
            c.outline = outline;
            c.shadow = shadow;
            c.underline = underline;
            c.caps = caps;
            c.valign = valign;
            c.color = color;
            c.highlight = highlight;
            c.shading = shading;
            c.spacing = spacing;
            c.position = position;
            c.lang = lang;
            c.style = style;
            c.link = link;
            return c;
        }

        public void overlay(CharProps o) {
            if (o.font != null) font = o.font;
            if (o.size > 0) size = o.size;
            if (o.bold != Tri.INHERIT) bold = o.bold;
            if (o.italic != Tri.INHERIT) italic = o.italic;
            if (o.strike != Tri.INHERIT) strike = o.strike;
            if (o.dstrike != Tri.INHERIT) dstrike = o.dstrike;
            if (o.hidden != Tri.INHERIT) hidden = o.hidden;
            if (o.outline != Tri.INHERIT) outline = o.outline;
            if (o.shadow != Tri.INHERIT) shadow = o.shadow;
            if (o.underline != Underline.INHERIT) underline = o.underline;
            if (o.caps != Caps.INHERIT) caps = o.caps;
            if (o.valign != VAlign.INHERIT) valign = o.valign;
            if (o.color != null) color = o.color;
            if (o.highlight != null) highlight = o.highlight;
            if (o.shading != null) shading = o.shading;
            if (!o.spacing.is_nan()) spacing = o.spacing;
            if (!o.position.is_nan()) position = o.position;
            if (o.lang != null) lang = o.lang;
            if (o.style != null) style = o.style;
            if (o.link != null) link = o.link;
        }

        public bool is_empty() {
            return equal(new CharProps());
        }

        public bool equal(CharProps o) {
            return font == o.font && size == o.size && bold == o.bold && italic == o.italic
                && strike == o.strike && dstrike == o.dstrike && hidden == o.hidden && outline == o.outline
                && shadow == o.shadow && underline == o.underline && caps == o.caps && valign == o.valign
                && color == o.color && highlight == o.highlight && shading == o.shading
                && same_num(spacing, o.spacing) && same_num(position, o.position)
                && lang == o.lang && style == o.style && link == o.link;
        }

        public string key() {
            return "%s|%g|%d%d%d%d%d%d%d|%d|%d|%d|%s|%s|%s|%g|%g|%s|%s|%s".printf(
                font ?? "", size, bold, italic, strike, dstrike, hidden, outline, shadow,
                underline, caps, valign, color ?? "", highlight ?? "", shading ?? "",
                spacing.is_nan() ? -9999.0 : spacing, position.is_nan() ? -9999.0 : position,
                lang ?? "", style ?? "", link ?? "");
        }
    }

    public static bool same_num(double a, double b) {
        if (a.is_nan() && b.is_nan()) return true;
        return a == b;
    }

    public class ParaProps : Object {
        public Align align = Align.INHERIT;
        public double ind_left = double.NAN;
        public double ind_right = double.NAN;
        public double ind_first = double.NAN;
        public double space_before = double.NAN;
        public double space_after = double.NAN;
        public double line = double.NAN;
        public LineRule line_rule = LineRule.AUTO;
        public Tri keep_next = Tri.INHERIT;
        public Tri keep_lines = Tri.INHERIT;
        public Tri page_break_before = Tri.INHERIT;
        public Tri widow = Tri.INHERIT;
        public Tri contextual = Tri.INHERIT;
        public int outline = -1;
        public string? shading = null;
        public Border? border_top = null;
        public Border? border_bottom = null;
        public Border? border_left = null;
        public Border? border_right = null;
        public Gee.ArrayList<TabStop>? tabs = null;
        public int num_id = -1;
        public int num_level = -1;
        public int dropcap_lines = 0;
        public bool dropcap_margin = false;

        public ParaProps copy() {
            var p = new ParaProps();
            p.align = align;
            p.ind_left = ind_left;
            p.ind_right = ind_right;
            p.ind_first = ind_first;
            p.space_before = space_before;
            p.space_after = space_after;
            p.line = line;
            p.line_rule = line_rule;
            p.keep_next = keep_next;
            p.keep_lines = keep_lines;
            p.page_break_before = page_break_before;
            p.widow = widow;
            p.contextual = contextual;
            p.outline = outline;
            p.shading = shading;
            p.border_top = border_top != null ? border_top.copy() : null;
            p.border_bottom = border_bottom != null ? border_bottom.copy() : null;
            p.border_left = border_left != null ? border_left.copy() : null;
            p.border_right = border_right != null ? border_right.copy() : null;
            if (tabs != null) {
                p.tabs = new Gee.ArrayList<TabStop>();
                foreach (var t in tabs) p.tabs.add(t.copy());
            }
            p.num_id = num_id;
            p.num_level = num_level;
            p.dropcap_lines = dropcap_lines;
            p.dropcap_margin = dropcap_margin;
            return p;
        }

        public void overlay(ParaProps o) {
            if (o.align != Align.INHERIT) align = o.align;
            if (!o.ind_left.is_nan()) ind_left = o.ind_left;
            if (!o.ind_right.is_nan()) ind_right = o.ind_right;
            if (!o.ind_first.is_nan()) ind_first = o.ind_first;
            if (!o.space_before.is_nan()) space_before = o.space_before;
            if (!o.space_after.is_nan()) space_after = o.space_after;
            if (!o.line.is_nan()) {
                line = o.line;
                line_rule = o.line_rule;
            }
            if (o.keep_next != Tri.INHERIT) keep_next = o.keep_next;
            if (o.keep_lines != Tri.INHERIT) keep_lines = o.keep_lines;
            if (o.page_break_before != Tri.INHERIT) page_break_before = o.page_break_before;
            if (o.widow != Tri.INHERIT) widow = o.widow;
            if (o.contextual != Tri.INHERIT) contextual = o.contextual;
            if (o.outline >= 0) outline = o.outline;
            if (o.shading != null) shading = o.shading;
            if (o.border_top != null) border_top = o.border_top.copy();
            if (o.border_bottom != null) border_bottom = o.border_bottom.copy();
            if (o.border_left != null) border_left = o.border_left.copy();
            if (o.border_right != null) border_right = o.border_right.copy();
            if (o.tabs != null) {
                var merged = new Gee.ArrayList<TabStop>();
                if (tabs != null) foreach (var t in tabs) merged.add(t.copy());
                foreach (var t in o.tabs) {
                    for (int i = merged.size - 1; i >= 0; i--) {
                        if ((merged[i].pos - t.pos).abs() < 0.5) merged.remove_at(i);
                    }
                    if (t.align != TabAlign.CLEAR) merged.add(t.copy());
                }
                merged.sort((a, b) => a.pos < b.pos ? -1 : (a.pos > b.pos ? 1 : 0));
                tabs = merged;
            }
            if (o.num_id >= 0) num_id = o.num_id;
            if (o.num_level >= 0) num_level = o.num_level;
            if (o.dropcap_lines > 0) {
                dropcap_lines = o.dropcap_lines;
                dropcap_margin = o.dropcap_margin;
            }
        }

        public bool is_empty() {
            return equal(new ParaProps());
        }

        public bool equal(ParaProps o) {
            if (align != o.align || !same_num(ind_left, o.ind_left) || !same_num(ind_right, o.ind_right)
                || !same_num(ind_first, o.ind_first) || !same_num(space_before, o.space_before)
                || !same_num(space_after, o.space_after) || !same_num(line, o.line) || line_rule != o.line_rule
                || keep_next != o.keep_next || keep_lines != o.keep_lines || page_break_before != o.page_break_before
                || widow != o.widow || contextual != o.contextual || outline != o.outline || shading != o.shading
                || num_id != o.num_id || num_level != o.num_level || dropcap_lines != o.dropcap_lines
                || dropcap_margin != o.dropcap_margin) return false;
            if (!border_eq(border_top, o.border_top) || !border_eq(border_bottom, o.border_bottom)
                || !border_eq(border_left, o.border_left) || !border_eq(border_right, o.border_right)) return false;
            if ((tabs == null) != (o.tabs == null)) return false;
            if (tabs != null) {
                if (tabs.size != o.tabs.size) return false;
                for (int i = 0; i < tabs.size; i++) {
                    if (tabs[i].pos != o.tabs[i].pos || tabs[i].align != o.tabs[i].align || tabs[i].leader != o.tabs[i].leader) return false;
                }
            }
            return true;
        }

        private static bool border_eq(Border? a, Border? b) {
            if (a == null) return b == null;
            return a.equal(b);
        }
    }

    public abstract class Block : Object {
        public weak BlockList? parent = null;
        public uint version = 0;
        public uint uid = 0;

        public void touch() {
            version++;
        }

        public abstract Block copy();

        public int index() {
            return parent != null ? parent.items.index_of(this) : -1;
        }
    }

    public class BlockList : Object {
        public Gee.ArrayList<Block> items = new Gee.ArrayList<Block>();
        public weak Object? owner = null;

        public BlockList(Object? owner = null) {
            this.owner = owner;
        }

        public int size {
            get { return items.size; }
        }

        public new Block get(int i) {
            return items[i];
        }

        public void add(Block b) {
            b.parent = this;
            items.add(b);
        }

        public void insert(int i, Block b) {
            b.parent = this;
            items.insert(i, b);
        }

        public void remove_at(int i) {
            items[i].parent = null;
            items.remove_at(i);
        }

        public void replace(int i, Block b) {
            items[i].parent = null;
            b.parent = this;
            items[i] = b;
        }

        public void clear() {
            foreach (var b in items) b.parent = null;
            items.clear();
        }

        public BlockList copy(Object? new_owner = null) {
            var l = new BlockList(new_owner);
            foreach (var b in items) {
                var c = b.copy();
                c.uid = b.uid;
                l.add(c);
            }
            return l;
        }

        public Paragraph? first_paragraph() {
            foreach (var b in items) {
                if (b is Paragraph) return (Paragraph) b;
                var t = b as Table;
                if (t != null && t.rows.size > 0 && t.rows[0].cells.size > 0) {
                    var p = t.rows[0].cells[0].blocks.first_paragraph();
                    if (p != null) return p;
                }
                var fb = b as FieldBlock;
                if (fb != null) {
                    var p = fb.result.first_paragraph();
                    if (p != null) return p;
                }
            }
            return null;
        }

        public Paragraph? last_paragraph() {
            for (int i = items.size - 1; i >= 0; i--) {
                var b = items[i];
                if (b is Paragraph) return (Paragraph) b;
                var t = b as Table;
                if (t != null && t.rows.size > 0) {
                    var row = t.rows[t.rows.size - 1];
                    if (row.cells.size > 0) {
                        var p = row.cells[row.cells.size - 1].blocks.last_paragraph();
                        if (p != null) return p;
                    }
                }
                var fb = b as FieldBlock;
                if (fb != null) {
                    var p = fb.result.last_paragraph();
                    if (p != null) return p;
                }
            }
            return null;
        }

        public void ensure_paragraph() {
            if (items.size == 0 || !(items[items.size - 1] is Paragraph)) add(new Paragraph());
        }
    }

    public abstract class Inline : Object {
        public CharProps props = new CharProps();
        public Revision? rev = null;
        public Revision? fmt_rev = null;
        public CharProps? fmt_old = null;

        public abstract int length { get; }
        public abstract Inline copy();

        public virtual unichar flat_char() {
            return 0xFFFC;
        }

        public virtual string flat() {
            if (length == 0) return "";
            var sb = new StringBuilder();
            sb.append_unichar(flat_char());
            return sb.str;
        }

        protected void copy_base(Inline to) {
            to.props = props.copy();
            to.rev = rev != null ? rev.copy() : null;
            to.fmt_rev = fmt_rev != null ? fmt_rev.copy() : null;
            to.fmt_old = fmt_old != null ? fmt_old.copy() : null;
        }

        public bool deleted() {
            return rev != null && rev.kind == RevKind.DELETE;
        }

        public bool same_attrs(Inline o) {
            if (!props.equal(o.props)) return false;
            if ((rev == null) != (o.rev == null)) return false;
            if (rev != null && (rev.kind != o.rev.kind || rev.author != o.rev.author || rev.date != o.rev.date)) return false;
            if ((fmt_rev == null) != (o.fmt_rev == null)) return false;
            if (fmt_rev != null && (fmt_rev.author != o.fmt_rev.author || !fmt_old.equal(o.fmt_old))) return false;
            return true;
        }
    }

    public class TextRun : Inline {
        private string _text = "";
        private int _len = 0;

        public string text {
            get { return _text; }
            set {
                _text = value;
                _len = value.char_count();
            }
        }

        public TextRun(string text = "", CharProps? props = null) {
            this.text = text;
            if (props != null) this.props = props.copy();
        }

        public override int length {
            get { return _len; }
        }

        public override Inline copy() {
            var r = new TextRun(_text);
            copy_base(r);
            return r;
        }

        public override string flat() {
            return _text;
        }
    }

    public class Tab : Inline {
        public override int length {
            get { return 1; }
        }

        public override Inline copy() {
            var t = new Tab();
            copy_base(t);
            return t;
        }

        public override unichar flat_char() {
            return '\t';
        }
    }

    public enum BreakKind {
        LINE,
        PAGE,
        COLUMN
    }

    public class Break : Inline {
        public BreakKind kind;

        public Break(BreakKind kind) {
            this.kind = kind;
        }

        public override int length {
            get { return 1; }
        }

        public override Inline copy() {
            var b = new Break(kind);
            copy_base(b);
            return b;
        }

        public override unichar flat_char() {
            switch (kind) {
                case BreakKind.PAGE: return '\f';
                case BreakKind.COLUMN: return 0x0B;
                default: return 0x2028;
            }
        }
    }

    public class FieldRun : Inline {
        public string code;
        public string result;
        public bool locked = false;
        public bool dirty = true;

        public FieldRun(string code, string result = "") {
            this.code = code;
            this.result = result;
        }

        public override int length {
            get { return 1; }
        }

        public override Inline copy() {
            var f = new FieldRun(code, result);
            f.locked = locked;
            f.dirty = dirty;
            copy_base(f);
            return f;
        }

        public string kind() {
            string c = code.strip();
            if (c.has_prefix("=")) return "=";
            int sp = c.index_of_char(' ');
            return (sp > 0 ? c.substring(0, sp) : c).up();
        }

        public string[] args() {
            return Fields.tokenize(code);
        }
    }

    public enum NoteKind {
        FOOTNOTE,
        ENDNOTE
    }

    public class Note : Object {
        public NoteKind kind;
        public BlockList blocks;
        public string? custom_mark = null;

        public Note(NoteKind kind) {
            this.kind = kind;
            blocks = new BlockList(this);
        }

        public Note copy() {
            var n = new Note(kind);
            n.blocks = blocks.copy(n);
            n.custom_mark = custom_mark;
            return n;
        }
    }

    public class NoteRef : Inline {
        public Note note;

        public NoteRef(Note note) {
            this.note = note;
        }

        public override int length {
            get { return 1; }
        }

        public override Inline copy() {
            var r = new NoteRef(note.copy());
            copy_base(r);
            return r;
        }
    }

    public enum MarkKind {
        BOOKMARK_START,
        BOOKMARK_END,
        COMMENT_START,
        COMMENT_END,
        INDEX_ENTRY
    }

    public class Mark : Inline {
        public MarkKind kind;
        public string name;

        public Mark(MarkKind kind, string name) {
            this.kind = kind;
            this.name = name;
        }

        public override int length {
            get { return 0; }
        }

        public override Inline copy() {
            var m = new Mark(kind, name);
            copy_base(m);
            return m;
        }
    }

    public enum Wrap {
        INLINE,
        SQUARE,
        TIGHT,
        TOP_BOTTOM,
        BEHIND,
        FRONT
    }

    public enum HRel {
        COLUMN,
        MARGIN,
        PAGE,
        CHARACTER
    }

    public enum VRel {
        PARAGRAPH,
        MARGIN,
        PAGE,
        LINE
    }

    public enum HAlignObj {
        NONE,
        LEFT,
        CENTER,
        RIGHT
    }

    public abstract class FloatingInline : Inline {
        public double width = 72;
        public double height = 72;
        public Wrap wrap = Wrap.INLINE;
        public HRel hrel = HRel.COLUMN;
        public VRel vrel = VRel.PARAGRAPH;
        public double hoff = 0;
        public double voff = 0;
        public HAlignObj halign = HAlignObj.NONE;
        public double dist = 9;
        public string alt = "";
        public string title = "";
        public string name = "";

        protected void copy_float(FloatingInline to) {
            copy_base(to);
            to.width = width;
            to.height = height;
            to.wrap = wrap;
            to.hrel = hrel;
            to.vrel = vrel;
            to.hoff = hoff;
            to.voff = voff;
            to.halign = halign;
            to.dist = dist;
            to.alt = alt;
            to.title = title;
            to.name = name;
        }

        public override int length {
            get { return 1; }
        }

        public bool floating() {
            return wrap != Wrap.INLINE;
        }
    }

    public class ChartRun : FloatingInline {
        public string chart_xml = "";
        public bool extended = false;
        public string odf_content = "";
        public string odf_styles = "";
        public Bytes? preview = null;
        public OpaqueRun? original = null;
        public bool edited = false;

        public ChartRun() {
            width = 360;
            height = 216;
        }

        public override Inline copy() {
            var c = new ChartRun();
            copy_float(c);
            c.chart_xml = chart_xml;
            c.extended = extended;
            c.odf_content = odf_content;
            c.odf_styles = odf_styles;
            c.preview = preview;
            c.original = original != null ? (OpaqueRun) original.copy() : null;
            c.edited = edited;
            return c;
        }
    }

    public class ImageRun : FloatingInline {
        public Bytes data;
        public string mime;
        public double crop_l = 0;
        public double crop_t = 0;
        public double crop_r = 0;
        public double crop_b = 0;
        public double brightness = 0;
        public double contrast = 0;
        public bool grayscale = false;
        public Border? outline_border = null;

        public ImageRun(Bytes data, string mime) {
            this.data = data;
            this.mime = mime;
        }

        public override Inline copy() {
            var i = new ImageRun(data, mime);
            copy_float(i);
            i.crop_l = crop_l;
            i.crop_t = crop_t;
            i.crop_r = crop_r;
            i.crop_b = crop_b;
            i.brightness = brightness;
            i.contrast = contrast;
            i.grayscale = grayscale;
            i.outline_border = outline_border != null ? outline_border.copy() : null;
            return i;
        }

        public string extension() {
            switch (mime) {
                case "image/jpeg": return "jpeg";
                case "image/gif": return "gif";
                case "image/svg+xml": return "svg";
                case "image/webp": return "webp";
                case "image/bmp": return "bmp";
                case "image/tiff": return "tiff";
                default: return "png";
            }
        }

        public static string sniff(uint8[] d) {
            if (d.length > 8 && d[0] == 0x89 && d[1] == 'P' && d[2] == 'N' && d[3] == 'G') return "image/png";
            if (d.length > 3 && d[0] == 0xFF && d[1] == 0xD8) return "image/jpeg";
            if (d.length > 6 && d[0] == 'G' && d[1] == 'I' && d[2] == 'F') return "image/gif";
            if (d.length > 12 && d[0] == 'R' && d[1] == 'I' && d[2] == 'F' && d[3] == 'F' && d[8] == 'W' && d[9] == 'E') return "image/webp";
            if (d.length > 2 && d[0] == 'B' && d[1] == 'M') return "image/bmp";
            if (d.length > 4 && ((d[0] == 'I' && d[1] == 'I' && d[2] == 42) || (d[0] == 'M' && d[1] == 'M' && d[3] == 42))) return "image/tiff";
            var head = new StringBuilder();
            for (int i = 0; i < d.length && i < 512; i++) head.append_c((char) d[i]);
            if ("<svg" in head.str) return "image/svg+xml";
            return "application/octet-stream";
        }
    }

    public enum ShapeKind {
        RECT,
        ROUND_RECT,
        ELLIPSE,
        LINE,
        ARROW,
        TRIANGLE,
        TEXT_BOX
    }

    public class ShapeRun : FloatingInline {
        public ShapeKind kind;
        public string? fill = "#ffffff";
        public string? stroke = "#000000";
        public double stroke_width = 1;
        public BlockList text;
        public bool wordart = false;
        public bool watermark = false;
        public double rotation = 0;

        public ShapeRun(ShapeKind kind) {
            this.kind = kind;
            text = new BlockList(this);
        }

        public override Inline copy() {
            var s = new ShapeRun(kind);
            copy_float(s);
            s.fill = fill;
            s.stroke = stroke;
            s.stroke_width = stroke_width;
            s.text = text.copy(s);
            s.wordart = wordart;
            s.watermark = watermark;
            s.rotation = rotation;
            return s;
        }
    }

    public class EquationRun : Inline {
        public string mathml;
        public string? omml = null;
        public string latex = "";
        public bool display = false;
        public double width = 0;
        public double ascent = 0;
        public double descent = 0;
        public Bytes? preview = null;
        public string? label = null;
        public bool numbered = false;

        public EquationRun(string mathml) {
            this.mathml = mathml;
        }

        public override int length {
            get { return 1; }
        }

        public override Inline copy() {
            var e = new EquationRun(mathml);
            copy_base(e);
            e.omml = omml;
            e.latex = latex;
            e.display = display;
            e.width = width;
            e.ascent = ascent;
            e.descent = descent;
            e.preview = preview;
            e.label = label;
            e.numbered = numbered;
            return e;
        }

        public string linear_text() {
            if (latex != "") return latex;
            string src = mathml != "" ? mathml : (omml ?? "");
            var sb = new StringBuilder();
            bool in_tag = false;
            unichar c;
            int i = 0;
            while (src.get_next_char(ref i, out c)) {
                if (c == '<') in_tag = true;
                else if (c == '>') in_tag = false;
                else if (!in_tag && !c.isspace()) sb.append_unichar(c);
            }
            return sb.str;
        }
    }

    public enum FormKind {
        TEXT,
        CHECKBOX,
        DROPDOWN,
        DATE
    }

    public class FormField : Inline {
        public FormKind kind;
        public string name = "";
        public string value = "";
        public bool checked = false;
        public string[] options = {};
        public string placeholder = "";

        public FormField(FormKind kind) {
            this.kind = kind;
        }

        public override int length {
            get { return 1; }
        }

        public override Inline copy() {
            var f = new FormField(kind);
            copy_base(f);
            f.name = name;
            f.value = value;
            f.checked = checked;
            f.options = options;
            f.placeholder = placeholder;
            return f;
        }

        public string display_text() {
            switch (kind) {
                case FormKind.CHECKBOX: return checked ? "\u2612" : "\u2610";
                default: return value != "" ? value : (placeholder != "" ? placeholder : "\u2002\u2002\u2002\u2002\u2002");
            }
        }
    }

    public class OpaqueRun : Inline {
        public string format;
        public string xml;
        public string description;
        public Gee.HashMap<string, Bytes> parts = new Gee.HashMap<string, Bytes>();
        public Gee.HashMap<string, string> rels = new Gee.HashMap<string, string>();
        public Bytes? preview = null;
        public double width = 144;
        public double height = 72;

        public OpaqueRun(string format, string xml, string description) {
            this.format = format;
            this.xml = xml;
            this.description = description;
        }

        public override int length {
            get { return 1; }
        }

        public override Inline copy() {
            var o = new OpaqueRun(format, xml, description);
            copy_base(o);
            foreach (var e in parts.entries) o.parts[e.key] = e.value;
            foreach (var e in rels.entries) o.rels[e.key] = e.value;
            o.preview = preview;
            o.width = width;
            o.height = height;
            return o;
        }
    }

    public class Paragraph : Block {
        public string style = "Normal";
        public ParaProps props = new ParaProps();
        public CharProps mark_props = new CharProps();
        public Gee.ArrayList<Inline> inlines = new Gee.ArrayList<Inline>();
        public Section? section = null;
        public Revision? mark_rev = null;
        public Revision? props_rev = null;
        public ParaProps? props_old = null;
        public string? style_old = null;

        public Paragraph(string style = "Normal") {
            this.style = style;
        }

        public Paragraph.with_text(string text, string style = "Normal", CharProps? props = null) {
            this.style = style;
            if (text != "") inlines.add(new TextRun(text, props));
        }

        public override Block copy() {
            var p = new Paragraph(style);
            p.props = props.copy();
            p.mark_props = mark_props.copy();
            foreach (var i in inlines) p.inlines.add(i.copy());
            p.section = section != null ? section.copy() : null;
            p.mark_rev = mark_rev != null ? mark_rev.copy() : null;
            p.props_rev = props_rev != null ? props_rev.copy() : null;
            p.props_old = props_old != null ? props_old.copy() : null;
            p.style_old = style_old;
            return p;
        }

        public Paragraph shell() {
            var p = new Paragraph(style);
            p.props = props.copy();
            p.mark_props = mark_props.copy();
            return p;
        }

        public int length {
            get {
                int n = 0;
                foreach (var i in inlines) n += i.length;
                return n;
            }
        }

        public string text() {
            var sb = new StringBuilder();
            foreach (var i in inlines) sb.append(i.flat());
            return sb.str;
        }

        public string plain_text(bool include_deleted = false) {
            var sb = new StringBuilder();
            foreach (var i in inlines) {
                if (!include_deleted && i.deleted()) continue;
                if (i is TextRun) sb.append(((TextRun) i).text);
                else if (i is Tab) sb.append_c('\t');
                else if (i is Break) sb.append_c(((Break) i).kind == BreakKind.LINE ? '\n' : ' ');
                else if (i is FieldRun) sb.append(((FieldRun) i).result);
                else if (i is FormField) sb.append(((FormField) i).display_text());
            }
            return sb.str;
        }

        public bool is_empty() {
            foreach (var i in inlines) if (i.length > 0) return false;
            return true;
        }

        public int locate(int offset, out int inner) {
            int pos = 0;
            for (int i = 0; i < inlines.size; i++) {
                int len = inlines[i].length;
                if (offset < pos + len) {
                    inner = offset - pos;
                    return i;
                }
                pos += len;
            }
            inner = 0;
            return inlines.size;
        }

        public int offset_of(Inline target) {
            int pos = 0;
            foreach (var i in inlines) {
                if (i == target) return pos;
                pos += i.length;
            }
            return -1;
        }

        public Inline? inline_at(int offset) {
            int inner;
            int idx = locate(offset, out inner);
            return idx < inlines.size ? inlines[idx] : null;
        }

        public int split_at(int offset) {
            if (offset <= 0) return 0;
            int pos = 0;
            for (int i = 0; i < inlines.size; i++) {
                int len = inlines[i].length;
                if (offset == pos) return i;
                if (offset < pos + len) {
                    var run = inlines[i] as TextRun;
                    if (run == null) return i;
                    int cut = offset - pos;
                    string a = usub(run.text, 0, cut);
                    string b = usub(run.text, cut, len);
                    var second = (TextRun) run.copy();
                    run.text = a;
                    second.text = b;
                    inlines.insert(i + 1, second);
                    return i + 1;
                }
                pos += len;
            }
            return inlines.size;
        }

        public int boundary_after(int offset) {
            int idx = split_at(offset);
            while (idx < inlines.size && inlines[idx].length == 0 && offset > 0) idx++;
            return idx;
        }

        public CharProps props_at(int offset) {
            if (inlines.size == 0) return mark_props.copy();
            int pos = 0;
            Inline? prev = null;
            foreach (var i in inlines) {
                int len = i.length;
                if (len > 0 && offset > pos && offset <= pos + len) return i.props.copy();
                if (len > 0 && offset == pos && offset == 0) return i.props.copy();
                if (len > 0) prev = i;
                pos += len;
                if (pos > offset) break;
            }
            if (prev != null) return prev.props.copy();
            return mark_props.copy();
        }

        public void insert_inline(int offset, Inline item) {
            int idx = split_at(offset);
            inlines.insert(idx, item);
        }

        public void insert_text(int offset, string text, CharProps props, Revision? rev = null) {
            if (text == "") return;
            int idx = split_at(offset);
            var run = new TextRun(text, props);
            run.rev = rev != null ? rev.copy() : null;
            inlines.insert(idx, run);
            normalize();
        }

        public Gee.ArrayList<Inline> cut(int start, int end) {
            var removed = new Gee.ArrayList<Inline>();
            if (end <= start) return removed;
            int a = split_at(start);
            int b = split_at(end);
            for (int i = a; i < b; i++) removed.add(inlines[i]);
            for (int i = b - 1; i >= a; i--) {
                var it = inlines[i];
                if (it.length == 0 && it is Mark) {
                    continue;
                }
                inlines.remove_at(i);
            }
            normalize();
            return removed;
        }

        public Gee.ArrayList<Inline> slice(int start, int end) {
            var outl = new Gee.ArrayList<Inline>();
            if (end <= start) return outl;
            var tmp = (Paragraph) copy();
            int a = tmp.split_at(start);
            int b = tmp.split_at(end);
            for (int i = a; i < b; i++) outl.add(tmp.inlines[i]);
            return outl;
        }

        public void for_range(int start, int end, owned InlineFunc fn) {
            if (end <= start) return;
            int a = split_at(start);
            int b = split_at(end);
            for (int i = a; i < b; i++) fn(inlines[i]);
            normalize();
        }

        public Paragraph split(int offset) {
            int idx = split_at(offset);
            var tail = shell();
            tail.style = style;
            for (int i = idx; i < inlines.size; i++) tail.inlines.add(inlines[i]);
            while (inlines.size > idx) inlines.remove_at(inlines.size - 1);
            tail.section = section;
            section = null;
            normalize();
            tail.normalize();
            return tail;
        }

        public void append_from(Paragraph other) {
            foreach (var i in other.inlines) inlines.add(i);
            if (other.section != null) section = other.section;
            normalize();
        }

        public void normalize() {
            for (int i = inlines.size - 1; i >= 0; i--) {
                var r = inlines[i] as TextRun;
                if (r != null && r.length == 0) {
                    inlines.remove_at(i);
                    continue;
                }
                if (r != null && i + 1 < inlines.size) {
                    var n = inlines[i + 1] as TextRun;
                    if (n != null && r.same_attrs(n)) {
                        r.text = r.text + n.text;
                        inlines.remove_at(i + 1);
                    }
                }
            }
        }
    }

    public delegate void InlineFunc(Inline i);

    public static string usub(string s, int a, int b) {
        int n = s.char_count();
        if (a < 0) a = 0;
        if (b > n) b = n;
        if (b <= a) return "";
        int ia = s.index_of_nth_char(a);
        int ib = s.index_of_nth_char(b);
        return s.substring(ia, ib - ia);
    }

    public enum VMerge {
        NONE,
        RESTART,
        CONTINUE
    }

    public enum CellVAlign {
        TOP,
        CENTER,
        BOTTOM
    }

    public class TableCell : Object {
        public int span = 1;
        public VMerge vmerge = VMerge.NONE;
        public double width = 0;
        public string? shading = null;
        public Border? top = null;
        public Border? bottom = null;
        public Border? left = null;
        public Border? right = null;
        public CellVAlign valign = CellVAlign.TOP;
        public BlockList blocks;

        public TableCell() {
            blocks = new BlockList(this);
        }

        public TableCell copy() {
            var c = new TableCell();
            c.span = span;
            c.vmerge = vmerge;
            c.width = width;
            c.shading = shading;
            c.top = top != null ? top.copy() : null;
            c.bottom = bottom != null ? bottom.copy() : null;
            c.left = left != null ? left.copy() : null;
            c.right = right != null ? right.copy() : null;
            c.valign = valign;
            c.blocks = blocks.copy(c);
            return c;
        }

        public string plain_text() {
            var sb = new StringBuilder();
            foreach (var b in blocks.items) {
                var p = b as Paragraph;
                if (p == null) continue;
                if (sb.len > 0) sb.append_c('\n');
                sb.append(p.plain_text());
            }
            return sb.str;
        }
    }

    public class TableRow : Object {
        public bool header = false;
        public double height = 0;
        public bool height_exact = false;
        public bool cant_split = false;
        public Revision? rev = null;
        public Gee.ArrayList<TableCell> cells = new Gee.ArrayList<TableCell>();

        public TableRow copy() {
            var r = new TableRow();
            r.header = header;
            r.height = height;
            r.height_exact = height_exact;
            r.cant_split = cant_split;
            r.rev = rev != null ? rev.copy() : null;
            foreach (var c in cells) r.cells.add(c.copy());
            return r;
        }
    }

    public class Table : Block {
        public string? style = "TableGrid";
        public double width = 0;
        public bool width_pct = false;
        public Align align = Align.LEFT;
        public double indent = 0;
        public double[] grid = {};
        public Border? border_top = null;
        public Border? border_bottom = null;
        public Border? border_left = null;
        public Border? border_right = null;
        public Border? border_h = null;
        public Border? border_v = null;
        public double margin_l = 5.4;
        public double margin_r = 5.4;
        public double margin_t = 0;
        public double margin_b = 0;
        public bool fixed_layout = false;
        public bool look_first_row = true;
        public bool look_last_row = false;
        public bool look_first_col = true;
        public bool look_banded_rows = true;
        public string caption = "";
        public string description = "";
        public Gee.ArrayList<TableRow> rows = new Gee.ArrayList<TableRow>();

        public override Block copy() {
            var t = new Table();
            t.style = style;
            t.width = width;
            t.width_pct = width_pct;
            t.align = align;
            t.indent = indent;
            t.grid = grid;
            t.border_top = border_top != null ? border_top.copy() : null;
            t.border_bottom = border_bottom != null ? border_bottom.copy() : null;
            t.border_left = border_left != null ? border_left.copy() : null;
            t.border_right = border_right != null ? border_right.copy() : null;
            t.border_h = border_h != null ? border_h.copy() : null;
            t.border_v = border_v != null ? border_v.copy() : null;
            t.margin_l = margin_l;
            t.margin_r = margin_r;
            t.margin_t = margin_t;
            t.margin_b = margin_b;
            t.fixed_layout = fixed_layout;
            t.look_first_row = look_first_row;
            t.look_last_row = look_last_row;
            t.look_first_col = look_first_col;
            t.look_banded_rows = look_banded_rows;
            t.caption = caption;
            t.description = description;
            foreach (var r in rows) t.rows.add(r.copy());
            return t;
        }

        public int columns() {
            if (grid.length > 0) return grid.length;
            int n = 0;
            foreach (var r in rows) {
                int c = 0;
                foreach (var cell in r.cells) c += cell.span;
                if (c > n) n = c;
            }
            return n;
        }

        public static Table create(int nrows, int ncols, double total_width) {
            var t = new Table();
            double w = total_width / ncols;
            double[] g = new double[ncols];
            for (int i = 0; i < ncols; i++) g[i] = w;
            t.grid = g;
            t.border_top = new Border.with("single", 0.5, "#000000");
            t.border_bottom = new Border.with("single", 0.5, "#000000");
            t.border_left = new Border.with("single", 0.5, "#000000");
            t.border_right = new Border.with("single", 0.5, "#000000");
            t.border_h = new Border.with("single", 0.5, "#000000");
            t.border_v = new Border.with("single", 0.5, "#000000");
            for (int r = 0; r < nrows; r++) {
                var row = new TableRow();
                for (int c = 0; c < ncols; c++) {
                    var cell = new TableCell();
                    cell.width = w;
                    cell.blocks.add(new Paragraph());
                    row.cells.add(cell);
                }
                t.rows.add(row);
            }
            return t;
        }

        public int grid_col(TableRow row, TableCell cell) {
            int c = 0;
            foreach (var x in row.cells) {
                if (x == cell) return c;
                c += x.span;
            }
            return -1;
        }

        public TableCell? cell_at_grid(TableRow row, int col) {
            int c = 0;
            foreach (var x in row.cells) {
                if (col >= c && col < c + x.span) return x;
                c += x.span;
            }
            return null;
        }

        public void locate_cell(TableCell cell, out int row, out int col) {
            for (int r = 0; r < rows.size; r++) {
                int i = rows[r].cells.index_of(cell);
                if (i >= 0) {
                    row = r;
                    col = i;
                    return;
                }
            }
            row = -1;
            col = -1;
        }
    }

    public class FieldBlock : Block {
        public string code;
        public BlockList result;

        public FieldBlock(string code) {
            this.code = code;
            result = new BlockList(this);
        }

        public override Block copy() {
            var f = new FieldBlock(code);
            f.result = result.copy(f);
            return f;
        }

        public string kind() {
            string c = code.strip();
            int sp = c.index_of_char(' ');
            return (sp > 0 ? c.substring(0, sp) : c).up();
        }
    }

    public enum SectionStart {
        NEXT_PAGE,
        CONTINUOUS,
        EVEN_PAGE,
        ODD_PAGE,
        NEXT_COLUMN
    }

    public enum NumFormat {
        DECIMAL,
        LOWER_LETTER,
        UPPER_LETTER,
        LOWER_ROMAN,
        UPPER_ROMAN,
        BULLET,
        NONE,
        DECIMAL_ZERO,
        ORDINAL,
        CARDINAL_TEXT
    }

    public class HeaderFooter : Object {
        public BlockList blocks;

        public HeaderFooter() {
            blocks = new BlockList(this);
        }

        public HeaderFooter copy() {
            var h = new HeaderFooter();
            h.blocks = blocks.copy(h);
            return h;
        }

        public bool is_blank() {
            foreach (var b in blocks.items) {
                var p = b as Paragraph;
                if (p == null || !p.is_empty()) return false;
            }
            return true;
        }
    }

    public class Section : Object {
        public double page_w = 595.3;
        public double page_h = 841.9;
        public bool landscape = false;
        public double margin_top = 72;
        public double margin_bottom = 72;
        public double margin_left = 72;
        public double margin_right = 72;
        public double header_dist = 36;
        public double footer_dist = 36;
        public double gutter = 0;
        public int columns = 1;
        public double column_space = 36;
        public bool column_sep = false;
        public SectionStart start = SectionStart.NEXT_PAGE;
        public HeaderFooter? header_default = null;
        public HeaderFooter? header_first = null;
        public HeaderFooter? header_even = null;
        public HeaderFooter? footer_default = null;
        public HeaderFooter? footer_first = null;
        public HeaderFooter? footer_even = null;
        public bool title_page = false;
        public int page_start = -1;
        public NumFormat page_format = NumFormat.DECIMAL;
        public Border? page_border_top = null;
        public Border? page_border_bottom = null;
        public Border? page_border_left = null;
        public Border? page_border_right = null;
        public bool line_numbers = false;

        public Section copy() {
            var s = new Section();
            s.page_w = page_w;
            s.page_h = page_h;
            s.landscape = landscape;
            s.margin_top = margin_top;
            s.margin_bottom = margin_bottom;
            s.margin_left = margin_left;
            s.margin_right = margin_right;
            s.header_dist = header_dist;
            s.footer_dist = footer_dist;
            s.gutter = gutter;
            s.columns = columns;
            s.column_space = column_space;
            s.column_sep = column_sep;
            s.start = start;
            s.header_default = header_default != null ? header_default.copy() : null;
            s.header_first = header_first != null ? header_first.copy() : null;
            s.header_even = header_even != null ? header_even.copy() : null;
            s.footer_default = footer_default != null ? footer_default.copy() : null;
            s.footer_first = footer_first != null ? footer_first.copy() : null;
            s.footer_even = footer_even != null ? footer_even.copy() : null;
            s.title_page = title_page;
            s.page_start = page_start;
            s.page_format = page_format;
            s.page_border_top = page_border_top != null ? page_border_top.copy() : null;
            s.page_border_bottom = page_border_bottom != null ? page_border_bottom.copy() : null;
            s.page_border_left = page_border_left != null ? page_border_left.copy() : null;
            s.page_border_right = page_border_right != null ? page_border_right.copy() : null;
            s.line_numbers = line_numbers;
            return s;
        }

        public double content_width() {
            return page_w - margin_left - margin_right - gutter;
        }

        public double column_width() {
            if (columns <= 1) return content_width();
            return (content_width() - column_space * (columns - 1)) / columns;
        }

        public void set_orientation(bool land) {
            if (land == landscape) return;
            landscape = land;
            double w = page_w;
            page_w = page_h;
            page_h = w;
        }
    }

    public class Comment : Object {
        public string id;
        public string author;
        public string initials;
        public string date;
        public BlockList blocks;
        public bool done = false;
        public string? parent_id = null;

        public Comment(string id, string author) {
            this.id = id;
            this.author = author;
            initials = make_initials(author);
            date = new DateTime.now_utc().format("%Y-%m-%dT%H:%M:%SZ");
            blocks = new BlockList(this);
        }

        public static string make_initials(string name) {
            var sb = new StringBuilder();
            foreach (string part in name.split(" ")) {
                if (part.length > 0) sb.append_unichar(part.get_char(0).toupper());
            }
            return sb.str;
        }

        public string text() {
            var sb = new StringBuilder();
            foreach (var b in blocks.items) {
                var p = b as Paragraph;
                if (p == null) continue;
                if (sb.len > 0) sb.append_c('\n');
                sb.append(p.plain_text());
            }
            return sb.str;
        }

        public Comment copy() {
            var c = new Comment(id, author);
            c.initials = initials;
            c.date = date;
            c.blocks = blocks.copy(c);
            c.done = done;
            c.parent_id = parent_id;
            return c;
        }
    }

    public class BibSource : Object {
        public string tag = "";
        public string kind = "Book";
        public string[] authors = {};
        public string title = "";
        public string year = "";
        public string publisher = "";
        public string city = "";
        public string journal = "";
        public string volume = "";
        public string issue = "";
        public string pages = "";
        public string url = "";
        public string accessed = "";
        public string edition = "";
        public string doi = "";

        public BibSource copy() {
            var s = new BibSource();
            s.tag = tag;
            s.kind = kind;
            s.authors = authors;
            s.title = title;
            s.year = year;
            s.publisher = publisher;
            s.city = city;
            s.journal = journal;
            s.volume = volume;
            s.issue = issue;
            s.pages = pages;
            s.url = url;
            s.accessed = accessed;
            s.edition = edition;
            s.doi = doi;
            return s;
        }
    }

    public enum ProtectKind {
        NONE,
        READ_ONLY,
        COMMENTS,
        TRACKED,
        FORMS
    }

    public class Protection : Object {
        public static string hash_password(string pw, string salt_b64, int spin) {
            uchar[] salt = Base64.decode(salt_b64);
            var sb = new ByteArray();
            sb.append(salt);
            unichar c;
            int i = 0;
            while (pw.get_next_char(ref i, out c)) {
                uint16 u = (uint16) c;
                uint8[] two = { (uint8) (u & 0xff), (uint8) (u >> 8) };
                sb.append(two);
            }
            var cs = new Checksum(ChecksumType.SHA512);
            cs.update(sb.data, sb.len);
            uint8[] digest = new uint8[64];
            size_t len = 64;
            cs.get_digest(digest, ref len);
            for (int k = 0; k < spin; k++) {
                var c2 = new Checksum(ChecksumType.SHA512);
                c2.update(digest, 64);
                uint8[] it = { (uint8) (k & 0xff), (uint8) ((k >> 8) & 0xff), (uint8) ((k >> 16) & 0xff), (uint8) ((k >> 24) & 0xff) };
                c2.update(it, 4);
                len = 64;
                c2.get_digest(digest, ref len);
            }
            return Base64.encode(digest);
        }

        public void set_password(string pw) {
            if (pw == "") {
                hash = "";
                salt = "";
                return;
            }
            uint8[] s = new uint8[16];
            for (int i = 0; i < 16; i++) s[i] = (uint8) Random.int_range(0, 256);
            algorithm = "SHA-512";
            salt = Base64.encode(s);
            hash = hash_password(pw, salt, spin);
        }

        public bool check_password(string pw) {
            if (hash == "") return true;
            return hash_password(pw, salt, spin) == hash;
        }

        public ProtectKind kind = ProtectKind.NONE;
        public bool enforced = false;
        public string algorithm = "SHA-512";
        public string hash = "";
        public string salt = "";
        public int spin = 100000;

        public Protection copy() {
            var p = new Protection();
            p.kind = kind;
            p.enforced = enforced;
            p.algorithm = algorithm;
            p.hash = hash;
            p.salt = salt;
            p.spin = spin;
            return p;
        }
    }

    public class Properties : Object {
        public string title = "";
        public string subject = "";
        public string author = "";
        public string keywords = "";
        public string description = "";
        public string category = "";
        public string company = "";
        public string manager = "";
        public string created = "";
        public string modified = "";
        public string last_modified_by = "";
        public int revision = 0;
        public Gee.TreeMap<string, string> custom = new Gee.TreeMap<string, string>();

        public Properties copy() {
            var p = new Properties();
            p.title = title;
            p.subject = subject;
            p.author = author;
            p.keywords = keywords;
            p.description = description;
            p.category = category;
            p.company = company;
            p.manager = manager;
            p.created = created;
            p.modified = modified;
            p.last_modified_by = last_modified_by;
            p.revision = revision;
            foreach (var e in custom.entries) p.custom[e.key] = e.value;
            return p;
        }
    }

    public class Watermark : Object {
        public string text = "";
        public Bytes? image = null;
        public string image_mime = "image/png";
        public string color = "#c0c0c0";
        public string font = "Calibri";
        public bool diagonal = true;
        public bool washout = true;

        public Watermark copy() {
            var w = new Watermark();
            w.text = text;
            w.image = image;
            w.image_mime = image_mime;
            w.color = color;
            w.font = font;
            w.diagonal = diagonal;
            w.washout = washout;
            return w;
        }
    }

    public class Document : Object {
        public Properties meta = new Properties();
        public StyleSheet styles = new StyleSheet();
        public Numbering numbering = new Numbering();
        public BlockList body;
        public Section final_section = new Section();
        public Gee.ArrayList<Comment> comments = new Gee.ArrayList<Comment>();
        public Gee.ArrayList<BibSource> sources = new Gee.ArrayList<BibSource>();
        public string bib_style = "APA";
        public bool track_changes = false;
        public bool even_odd_headers = false;
        public double default_tab = 36;
        public Protection protection = new Protection();
        public string? page_color = null;
        public Watermark? watermark = null;
        public string? merge_source = null;
        public Gee.TreeMap<string, string> variables = new Gee.TreeMap<string, string>();
        public Gee.HashMap<string, Bytes> passthrough = new Gee.HashMap<string, Bytes>();
        public string passthrough_format = "";
        public string lang = "";
        public bool hyphenate = false;
        public string footnote_position = "page";
        public NumFormat footnote_format = NumFormat.DECIMAL;
        public NumFormat endnote_format = NumFormat.LOWER_ROMAN;
        public Gee.ArrayList<string> macros = new Gee.ArrayList<string>();
        private int _next_id = 1;

        public Document() {
            body = new BlockList(this);
        }

        public static Document create_blank() {
            var d = new Document();
            d.styles.ensure_builtins();
            d.body.add(new Paragraph());
            return d;
        }

        public int next_id() {
            return _next_id++;
        }

        public void bump_id(int seen) {
            if (seen >= _next_id) _next_id = seen + 1;
        }

        public Document copy() {
            var d = new Document();
            d.meta = meta.copy();
            d.styles = styles.copy();
            d.numbering = numbering.copy();
            d.body = body.copy(d);
            d.final_section = final_section.copy();
            foreach (var c in comments) d.comments.add(c.copy());
            foreach (var s in sources) d.sources.add(s.copy());
            d.bib_style = bib_style;
            d.track_changes = track_changes;
            d.even_odd_headers = even_odd_headers;
            d.default_tab = default_tab;
            d.protection = protection.copy();
            d.page_color = page_color;
            d.watermark = watermark != null ? watermark.copy() : null;
            d.merge_source = merge_source;
            foreach (var e in variables.entries) d.variables[e.key] = e.value;
            foreach (var e in passthrough.entries) d.passthrough[e.key] = e.value;
            d.passthrough_format = passthrough_format;
            d.lang = lang;
            d.hyphenate = hyphenate;
            d.footnote_position = footnote_position;
            d.footnote_format = footnote_format;
            d.endnote_format = endnote_format;
            foreach (var m in macros) d.macros.add(m);
            d._next_id = _next_id;
            return d;
        }

        public void assign(Document o) {
            meta = o.meta;
            styles = o.styles;
            styles.touch();
            numbering = o.numbering;
            body = o.body;
            body.owner = this;
            final_section = o.final_section;
            comments = o.comments;
            sources = o.sources;
            bib_style = o.bib_style;
            track_changes = o.track_changes;
            even_odd_headers = o.even_odd_headers;
            default_tab = o.default_tab;
            protection = o.protection;
            page_color = o.page_color;
            watermark = o.watermark;
            merge_source = o.merge_source;
            variables = o.variables;
            passthrough = o.passthrough;
            passthrough_format = o.passthrough_format;
            lang = o.lang;
            hyphenate = o.hyphenate;
            footnote_position = o.footnote_position;
            footnote_format = o.footnote_format;
            endnote_format = o.endnote_format;
            macros = o.macros;
            _next_id = int.max(_next_id, o._next_id);
        }

        public Comment? find_comment(string id) {
            foreach (var c in comments) if (c.id == id) return c;
            return null;
        }

        public BibSource? find_source(string tag) {
            foreach (var s in sources) if (s.tag == tag) return s;
            return null;
        }

        public Gee.ArrayList<Section> sections() {
            var list = new Gee.ArrayList<Section>();
            foreach (var b in body.items) {
                var p = b as Paragraph;
                if (p != null && p.section != null) list.add(p.section);
            }
            list.add(final_section);
            return list;
        }

        public Section section_for(Block b) {
            Block top = b;
            while (top.parent != null && top.parent.owner != this) {
                var owner = top.parent.owner;
                Block? next = null;
                if (owner is TableCell) {
                    next = find_table_of((TableCell) owner);
                } else if (owner is FieldBlock) {
                    next = (Block) owner;
                }
                if (next == null) break;
                top = next;
            }
            int idx = body.items.index_of(top);
            if (idx < 0) return final_section;
            for (int i = idx; i < body.size; i++) {
                var p = body[i] as Paragraph;
                if (p != null && p.section != null) return p.section;
            }
            return final_section;
        }

        public Table? find_table_of(TableCell cell) {
            Table? found = null;
            walk_blocks(body, (b) => {
                var t = b as Table;
                if (t == null || found != null) return;
                foreach (var r in t.rows) if (r.cells.contains(cell)) found = t;
            });
            return found;
        }

        public void walk_blocks(BlockList list, BlockFunc fn) {
            foreach (var b in list.items) {
                fn(b);
                var t = b as Table;
                if (t != null) {
                    foreach (var r in t.rows) foreach (var c in r.cells) walk_blocks(c.blocks, fn);
                }
                var fb = b as FieldBlock;
                if (fb != null) walk_blocks(fb.result, fn);
                var p = b as Paragraph;
                if (p != null) {
                    foreach (var i in p.inlines) {
                        var s = i as ShapeRun;
                        if (s != null) walk_blocks(s.text, fn);
                    }
                }
            }
        }

        public Gee.ArrayList<Paragraph> paragraphs(bool with_notes = false) {
            var list = new Gee.ArrayList<Paragraph>();
            walk_blocks(body, (b) => {
                var p = b as Paragraph;
                if (p != null) list.add(p);
            });
            if (with_notes) {
                foreach (var n in notes()) walk_blocks(n.blocks, (b) => {
                    var p = b as Paragraph;
                    if (p != null) list.add(p);
                });
            }
            return list;
        }

        public Gee.ArrayList<Note> notes(NoteKind? kind = null) {
            var list = new Gee.ArrayList<Note>();
            walk_blocks(body, (b) => {
                var p = b as Paragraph;
                if (p == null) return;
                foreach (var i in p.inlines) {
                    var r = i as NoteRef;
                    if (r != null && (kind == null || r.note.kind == kind)) list.add(r.note);
                }
            });
            return list;
        }

        public Gee.ArrayList<HeaderFooter> header_footers() {
            var list = new Gee.ArrayList<HeaderFooter>();
            foreach (var s in sections()) {
                foreach (var h in new HeaderFooter?[] { s.header_default, s.header_first, s.header_even, s.footer_default, s.footer_first, s.footer_even }) {
                    if (h != null && !list.contains(h)) list.add(h);
                }
            }
            return list;
        }
    }

    public delegate void BlockFunc(Block b);
}
