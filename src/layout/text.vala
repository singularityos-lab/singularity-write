namespace Write {

    public enum ViewMarkup {
        ALL,
        SIMPLE,
        FINAL,
        ORIGINAL
    }

    public class ViewOptions : Object {
        public ViewMarkup markup = ViewMarkup.ALL;
        public bool formatting_marks = false;
        public bool field_shading = true;
        public bool show_hidden = false;
        public bool draft = false;
        public bool print = false;
        public bool hyphenate = false;
        public string? highlight_author = null;

        public ViewOptions copy() {
            var v = new ViewOptions();
            v.markup = markup;
            v.formatting_marks = formatting_marks;
            v.field_shading = field_shading;
            v.show_hidden = show_hidden;
            v.draft = draft;
            v.print = print;
            v.hyphenate = hyphenate;
            v.highlight_author = highlight_author;
            return v;
        }

        public string key() {
            return "%d%d%d%d%d".printf(markup, formatting_marks ? 1 : 0, show_hidden ? 1 : 0, print ? 1 : 0, hyphenate ? 1 : 0);
        }
    }

    public class ObjRef : Object {
        public Inline item;
        public int model;
        public int byte_index;

        public ObjRef(Inline item, int model, int byte_index) {
            this.item = item;
            this.model = model;
            this.byte_index = byte_index;
        }
    }

    public class ParaText : Object {
        public string text = "";
        public int[] model_to_byte = {};
        public Pango.AttrList attrs = new Pango.AttrList();
        public Gee.ArrayList<ObjRef> objects = new Gee.ArrayList<ObjRef>();
        public Gee.ArrayList<ObjRef> floats = new Gee.ArrayList<ObjRef>();
        public Gee.ArrayList<ObjRef> tabs = new Gee.ArrayList<ObjRef>();
        public Gee.ArrayList<ObjRef> fields = new Gee.ArrayList<ObjRef>();
        public Gee.ArrayList<int> page_breaks = new Gee.ArrayList<int>();
        public Gee.ArrayList<int> column_breaks = new Gee.ArrayList<int>();
        public double max_size = 0;
        public CharProps first_props;
        public CharProps mark_props;

        public int byte_to_model(int b) {
            int lo = 0;
            int hi = model_to_byte.length - 1;
            if (hi < 0) return 0;
            while (lo < hi) {
                int mid = (lo + hi + 1) / 2;
                if (model_to_byte[mid] <= b) lo = mid;
                else hi = mid - 1;
            }
            return lo;
        }

        public int to_byte(int model) {
            if (model_to_byte.length == 0) return 0;
            return model_to_byte[model.clamp(0, model_to_byte.length - 1)];
        }
    }

    public class Palette : Object {
        public static string author_color(string author) {
            string[] colors = { "#b5082e", "#2e5aac", "#1f7a3a", "#8a3fb0", "#b35c00", "#00808a", "#a0306e", "#5a6a00" };
            uint h = author.hash();
            return colors[h % colors.length];
        }

        public static void rgb(string? hex, out uint16 r, out uint16 g, out uint16 b) {
            r = 0;
            g = 0;
            b = 0;
            if (hex == null || hex.length < 7) return;
            r = (uint16) (long.parse("0x" + hex.substring(1, 2), 16) * 257);
            g = (uint16) (long.parse("0x" + hex.substring(3, 2), 16) * 257);
            b = (uint16) (long.parse("0x" + hex.substring(5, 2), 16) * 257);
        }

        public static void rgbd(string? hex, out double r, out double g, out double b) {
            uint16 ri, gi, bi;
            rgb(hex, out ri, out gi, out bi);
            r = ri / 65535.0;
            g = gi / 65535.0;
            b = bi / 65535.0;
        }
    }

    public delegate string FieldText(FieldRun f);
    public delegate string NoteMark(NoteRef r);

    public class TextBuilder : Object {
        private Document doc;
        private ViewOptions opts;
        private unowned FieldText field_text;
        private unowned NoteMark note_mark;
        public Hyphenator? hyphenator = null;
        public CharProps? overlay = null;

        public TextBuilder(Document doc, ViewOptions opts, FieldText field_text, NoteMark note_mark) {
            this.doc = doc;
            this.opts = opts;
            this.field_text = field_text;
            this.note_mark = note_mark;
        }

        public static Pango.FontDescription font_for(CharProps c) {
            var fd = new Pango.FontDescription();
            fd.set_family(c.font ?? "Liberation Serif");
            fd.set_size((int) Math.round((c.size > 0 ? c.size : 11) * Pango.SCALE));
            if (c.bold.on()) fd.set_weight(Pango.Weight.BOLD);
            if (c.italic.on()) fd.set_style(Pango.Style.ITALIC);
            return fd;
        }

        private static void add(Pango.AttrList list, owned Pango.Attribute a, int s, int e) {
            a.start_index = s;
            a.end_index = e;
            list.insert((owned) a);
        }

        private void style_range(Pango.AttrList l, CharProps c, Inline? item, int s, int e) {
            if (e <= s) return;
            add(l, Pango.attr_font_desc_new(font_for(c)), s, e);
            Underline u = c.underline;
            bool strike = c.strike.on() || c.dstrike.on();
            string? color = c.color;
            if (c.link != null && c.style == null && color == null) {
                color = "#0563c1";
                if (u == Underline.INHERIT || u == Underline.NONE) u = Underline.SINGLE;
            }
            if (item != null && item.rev != null && opts.markup != ViewMarkup.FINAL && opts.markup != ViewMarkup.ORIGINAL) {
                string rc = Palette.author_color(item.rev.author);
                if (opts.markup == ViewMarkup.ALL) {
                    color = rc;
                    if (item.rev.kind == RevKind.INSERT) u = Underline.SINGLE;
                    else strike = true;
                }
            }
            switch (u) {
                case Underline.SINGLE:
                case Underline.WORDS:
                case Underline.DOTTED:
                case Underline.DASHED:
                    add(l, Pango.attr_underline_new(Pango.Underline.SINGLE), s, e);
                    break;
                case Underline.DOUBLE:
                    add(l, Pango.attr_underline_new(Pango.Underline.DOUBLE), s, e);
                    break;
                case Underline.WAVY:
                    add(l, Pango.attr_underline_new(Pango.Underline.ERROR), s, e);
                    break;
                case Underline.THICK:
                    add(l, Pango.attr_underline_new(Pango.Underline.SINGLE), s, e);
                    add(l, Pango.attr_underline_new(Pango.Underline.DOUBLE), s, e);
                    break;
                default:
                    break;
            }
            if (strike) add(l, Pango.attr_strikethrough_new(true), s, e);
            if (color != null) {
                uint16 r, g, b;
                Palette.rgb(color, out r, out g, out b);
                add(l, Pango.attr_foreground_new(r, g, b), s, e);
            }
            string? bg = c.highlight != null && c.highlight != "none" ? c.highlight : c.shading;
            if (bg != null) {
                uint16 r, g, b;
                Palette.rgb(bg, out r, out g, out b);
                add(l, Pango.attr_background_new(r, g, b), s, e);
            }
            if (c.valign == VAlign.SUPER) {
                add(l, Pango.attr_baseline_shift_new(Pango.BaselineShift.SUPERSCRIPT), s, e);
                add(l, Pango.attr_font_scale_new(Pango.FontScale.SUPERSCRIPT), s, e);
            } else if (c.valign == VAlign.SUB) {
                add(l, Pango.attr_baseline_shift_new(Pango.BaselineShift.SUBSCRIPT), s, e);
                add(l, Pango.attr_font_scale_new(Pango.FontScale.SUBSCRIPT), s, e);
            }
            if (!c.position.is_nan() && c.position != 0) add(l, Pango.attr_rise_new((int) (c.position * Pango.SCALE)), s, e);
            if (!c.spacing.is_nan() && c.spacing != 0) add(l, Pango.attr_letter_spacing_new((int) (c.spacing * Pango.SCALE)), s, e);
            if (c.caps == Caps.SMALL) add(l, Pango.attr_variant_new(Pango.Variant.SMALL_CAPS), s, e);
            else if (c.caps == Caps.ALL) add(l, Pango.attr_text_transform_new(Pango.TextTransform.UPPERCASE), s, e);
            if (c.lang != null) add(l, Pango.AttrLanguage.@new(Pango.Language.from_string(c.lang)), s, e);
            if (c.hidden.on() && opts.show_hidden) add(l, Pango.attr_underline_new(Pango.Underline.ERROR), s, e);
        }

        private bool visible(Inline i, CharProps resolved) {
            if (resolved.hidden.on() && !opts.show_hidden) return false;
            if (i.rev != null) {
                if (opts.markup == ViewMarkup.FINAL || opts.markup == ViewMarkup.SIMPLE) return i.rev.kind != RevKind.DELETE;
                if (opts.markup == ViewMarkup.ORIGINAL) return i.rev.kind != RevKind.INSERT;
            }
            return true;
        }

        public ParaText build(Paragraph p) {
            var pt = new ParaText();
            var sb = new StringBuilder();
            int[] map = new int[p.length + 1];
            int model = 0;
            pt.mark_props = doc.styles.resolve_char(p, p.mark_props);
            pt.first_props = pt.mark_props;
            bool first_set = false;
            foreach (var item in p.inlines) {
                var c = doc.styles.resolve_char(p, item.props);
                if (overlay != null) {
                    if (overlay.color != null && item.props.color == null) c.color = overlay.color;
                    if (overlay.bold != Tri.INHERIT && item.props.bold == Tri.INHERIT) c.bold = overlay.bold;
                    if (overlay.italic != Tri.INHERIT && item.props.italic == Tri.INHERIT) c.italic = overlay.italic;
                }
                if (item.length > 0 && !first_set) {
                    pt.first_props = c;
                    first_set = true;
                }
                double sz = c.size > 0 ? c.size : 11;
                bool vis = visible(item, c);
                int start = (int) sb.len;
                if (item is TextRun) {
                    var tr = (TextRun) item;
                    Gee.HashSet<int>? hy = null;
                    if (vis && hyphenator != null && opts.hyphenate) hy = hyphenator.points(tr.text, c.lang ?? doc.lang);
                    unichar ch;
                    int i = 0;
                    int ci = 0;
                    while (tr.text.get_next_char(ref i, out ch)) {
                        if (vis && hy != null && hy.contains(ci)) sb.append_unichar(0xAD);
                        map[model++] = (int) sb.len;
                        ci++;
                        if (!vis) continue;
                        if (ch == '\t') {
                            pt.tabs.add(new ObjRef(item, model - 1, (int) sb.len));
                            sb.append_c('\t');
                        } else if (ch == '\n' || ch == '\r') {
                            sb.append_unichar(0x2028);
                        } else {
                            sb.append_unichar(ch);
                        }
                    }
                    if (vis) style_range(pt.attrs, c, item, start, (int) sb.len);
                    if (vis && sz > pt.max_size) pt.max_size = sz;
                    continue;
                }
                map[model] = (int) sb.len;
                if (item.length > 0) model++;
                if (!vis) continue;
                if (item is Tab) {
                    pt.tabs.add(new ObjRef(item, model - 1, (int) sb.len));
                    sb.append_c('\t');
                    style_range(pt.attrs, c, item, start, (int) sb.len);
                } else if (item is Break) {
                    var b = (Break) item;
                    sb.append_unichar(0x2028);
                    if (b.kind == BreakKind.PAGE) pt.page_breaks.add((int) sb.len);
                    else if (b.kind == BreakKind.COLUMN) pt.column_breaks.add((int) sb.len);
                } else if (item is FieldRun) {
                    var f = (FieldRun) item;
                    string t = field_text(f);
                    if (t == "") t = "\u200b";
                    pt.fields.add(new ObjRef(item, model - 1, start));
                    sb.append(t.replace("\n", " ").replace("\r", " "));
                    style_range(pt.attrs, c, item, start, (int) sb.len);
                    if (opts.field_shading && !opts.print) {
                        add(pt.attrs, Pango.attr_background_new(0xd9d9, 0xd9d9, 0xd9d9), start, (int) sb.len);
                    }
                } else if (item is NoteRef) {
                    var r = (NoteRef) item;
                    sb.append(note_mark(r));
                    var nc = c.copy();
                    if (nc.valign == VAlign.INHERIT || nc.valign == VAlign.BASELINE) nc.valign = VAlign.SUPER;
                    style_range(pt.attrs, nc, item, start, (int) sb.len);
                } else if (item is FormField) {
                    var ff = (FormField) item;
                    sb.append(ff.display_text());
                    style_range(pt.attrs, c, item, start, (int) sb.len);
                    if (!opts.print) add(pt.attrs, Pango.attr_background_new(0xe6e6, 0xe6e6, 0xe6e6), start, (int) sb.len);
                    pt.fields.add(new ObjRef(item, model - 1, start));
                } else if (item is Mark) {
                    continue;
                } else {
                    double w = 0, asc = 0, desc = 0;
                    bool floating = false;
                    object_metrics(item, out w, out asc, out desc, out floating);
                    sb.append_unichar(0xFFFC);
                    var ink = Pango.Rectangle();
                    ink.x = 0;
                    ink.y = (int) (-asc * Pango.SCALE);
                    ink.width = (int) (w * Pango.SCALE);
                    ink.height = (int) ((asc + desc) * Pango.SCALE);
                    var logical = ink;
                    add(pt.attrs, Pango.AttrShape.@new(ink, logical), start, (int) sb.len);
                    var o = new ObjRef(item, model - 1, start);
                    if (floating) pt.floats.add(o);
                    else pt.objects.add(o);
                }
            }
            map[model] = (int) sb.len;
            while (model < map.length - 1) map[++model] = (int) sb.len;
            pt.text = sb.str;
            pt.model_to_byte = map;
            if (pt.max_size <= 0) pt.max_size = pt.mark_props.size > 0 ? pt.mark_props.size : 11;
            if (sb.len == 0) {
                pt.attrs = new Pango.AttrList();
            }
            return pt;
        }

        public static void object_metrics(Inline item, out double w, out double asc, out double desc, out bool floating) {
            w = 0;
            asc = 0;
            desc = 0;
            floating = false;
            var f = item as FloatingInline;
            if (f != null) {
                if (f.floating()) {
                    floating = true;
                    return;
                }
                w = f.width;
                asc = f.height;
                desc = 0;
                return;
            }
            var e = item as EquationRun;
            if (e != null) {
                if (e.width > 0) {
                    w = e.width;
                    asc = e.ascent;
                    desc = e.descent;
                } else {
                    w = double.max(12, e.linear_text().char_count() * 6.5);
                    asc = 10;
                    desc = 4;
                }
                return;
            }
            var o = item as OpaqueRun;
            if (o != null) {
                w = o.width;
                asc = o.height;
                return;
            }
        }
    }
}
