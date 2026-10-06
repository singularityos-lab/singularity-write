namespace Write {

    public class ImageCache : Object {
        private static Gee.HashMap<Bytes, Cairo.ImageSurface?>? cache = null;

        public static Cairo.ImageSurface? get_surface(Bytes data) {
            if (cache == null) cache = new Gee.HashMap<Bytes, Cairo.ImageSurface?>();
            if (cache.has_key(data)) return cache[data];
            Cairo.ImageSurface? s = null;
            try {
                var loader = new Gdk.PixbufLoader();
                loader.write(data.get_data());
                loader.close();
                var pb = loader.get_pixbuf();
                if (pb != null) {
                    s = new Cairo.ImageSurface(Cairo.Format.ARGB32, pb.width, pb.height);
                    var cr = new Cairo.Context(s);
                    Gdk.cairo_set_source_pixbuf(cr, pb, 0, 0);
                    cr.paint();
                }
            } catch (Error e) {
            }
            if (cache.size > 200) cache.clear();
            cache[data] = s;
            return s;
        }
    }

    public class Renderer : Object {
        public Document doc;
        public ViewOptions opts;
        public bool dim_body = false;
        public bool dim_headers = false;
        public bool tagged = false;
        public Pango.Context pctx;

        public Renderer(Document doc, ViewOptions opts, Pango.Context pctx) {
            this.doc = doc;
            this.opts = opts;
            this.pctx = pctx;
        }

        private static void set_color(Cairo.Context cr, string? hex, double alpha = 1.0) {
            double r, g, b;
            Palette.rgbd(hex ?? "#000000", out r, out g, out b);
            cr.set_source_rgba(r, g, b, alpha);
        }

        private static bool behind(ObjBox o) {
            var f = o.item as FloatingInline;
            return o.floating && f != null && f.wrap == Wrap.BEHIND;
        }

        public void draw_page(Cairo.Context cr, PageBox p) {
            cr.save();
            set_color(cr, doc.page_color ?? "#ffffff");
            cr.rectangle(0, 0, p.width, p.height);
            cr.fill();
            if (doc.watermark != null && !opts.draft) draw_watermark(cr, p);
            draw_page_border(cr, p);
            foreach (var d in p.decos) if (d.kind == DecoKind.FILL) draw_deco(cr, d);
            foreach (var o in p.objects) if (behind(o)) draw_object(cr, o);
            foreach (var d in p.decos) if (d.kind == DecoKind.STROKE) draw_deco(cr, d);
            Paragraph? open_para = null;
            string open_tag = "";
            foreach (var lb in p.lines) {
                if (tagged && lb.para != open_para) {
                    if (open_para != null) cr.tag_end(open_tag);
                    open_tag = lb.region == Region.HEADER || lb.region == Region.FOOTER ? "Artifact" : struct_tag(lb.para);
                    cr.tag_begin(open_tag, "");
                    open_para = lb.para;
                }
                draw_line(cr, lb);
            }
            if (tagged && open_para != null) cr.tag_end(open_tag);
            foreach (var d in p.decos) if (d.kind != DecoKind.FILL && d.kind != DecoKind.STROKE) draw_deco(cr, d);
            foreach (var o in p.objects) if (!behind(o)) draw_object(cr, o);
            if (p.section.line_numbers && !opts.draft) draw_line_numbers(cr, p);
            if (opts.markup == ViewMarkup.ALL || opts.markup == ViewMarkup.SIMPLE) draw_change_bars(cr, p);
            cr.restore();
        }

        private static bool para_changed(Paragraph para) {
            if (para.props_rev != null || para.mark_rev != null) return true;
            foreach (var i in para.inlines) if (i.rev != null || i.fmt_rev != null) return true;
            return false;
        }

        private void draw_change_bars(Cairo.Context cr, PageBox p) {
            var changed = new Gee.HashMap<Paragraph, bool>();
            foreach (var lb in p.lines) {
                if (!changed.has_key(lb.para)) changed[lb.para] = para_changed(lb.para);
                if (!changed[lb.para]) continue;
                if (opts.markup == ViewMarkup.SIMPLE) cr.set_source_rgb(0.85, 0.15, 0.15);
                else cr.set_source_rgba(0.45, 0.45, 0.45, 0.9);
                double x = double.max(6, p.body_left - 14);
                cr.rectangle(x, lb.top, 1.2, lb.height);
                cr.fill();
            }
        }

        private string struct_tag(Paragraph p) {
            int level = doc.styles.outline_level(p);
            if (level >= 0 && level < 6 && p.style.has_prefix("Heading")) return "H%d".printf(level + 1);
            if (p.style.has_prefix("TOC")) return "TOCI";
            if (p.props.num_id > 0) return "LI";
            return "P";
        }

        private void draw_watermark(Cairo.Context cr, PageBox p) {
            var wm = doc.watermark;
            cr.save();
            cr.translate(p.width / 2, p.height / 2);
            if (wm.image != null) {
                var s = ImageCache.get_surface(wm.image);
                if (s != null) {
                    double sc = double.min(p.width * 0.6 / s.get_width(), p.height * 0.6 / s.get_height());
                    cr.scale(sc, sc);
                    cr.set_source_surface(s, -s.get_width() / 2.0, -s.get_height() / 2.0);
                    cr.paint_with_alpha(wm.washout ? 0.25 : 1.0);
                }
                cr.restore();
                return;
            }
            if (wm.diagonal) cr.rotate(-Math.PI / 4);
            var l = new Pango.Layout(pctx);
            l.set_font_description(Pango.FontDescription.from_string(wm.font + " 72"));
            l.set_text(wm.text, -1);
            Pango.Rectangle ink, logical;
            l.get_extents(out ink, out logical);
            double w = logical.width / (double) Pango.SCALE;
            double h = logical.height / (double) Pango.SCALE;
            double maxw = p.width * 0.9;
            if (w > maxw) {
                double sc = maxw / w;
                cr.scale(sc, sc);
            }
            set_color(cr, wm.color, 0.45);
            cr.move_to(-w / 2, -h / 2);
            Pango.cairo_show_layout(cr, l);
            cr.restore();
        }

        private void draw_page_border(Cairo.Context cr, PageBox p) {
            var s = p.section;
            double pad = 24;
            double x0 = p.body_left - pad;
            double x1 = p.body_right + pad;
            double y0 = p.body_top - pad;
            double y1 = p.body_bottom + pad;
            stroke_border(cr, s.page_border_top, x0, y0, x1, y0);
            stroke_border(cr, s.page_border_bottom, x0, y1, x1, y1);
            stroke_border(cr, s.page_border_left, x0, y0, x0, y1);
            stroke_border(cr, s.page_border_right, x1, y0, x1, y1);
        }

        private void stroke_border(Cairo.Context cr, Border? b, double x0, double y0, double x1, double y1) {
            if (b == null || !b.visible()) return;
            var d = new Deco(DecoKind.LINE, x0, y0, x1 - x0, y1 - y0);
            d.color = b.color;
            d.width = b.width;
            d.style = b.style;
            draw_deco(cr, d);
        }

        public void draw_deco(Cairo.Context cr, Deco d) {
            switch (d.kind) {
                case DecoKind.FILL:
                    set_color(cr, d.color);
                    cr.rectangle(d.x, d.y, d.w, d.h);
                    cr.fill();
                    break;
                case DecoKind.STROKE:
                    if (d.style == "gridline" && opts.print) break;
                    set_color(cr, d.color);
                    cr.set_line_width(d.width);
                    if (d.style == "gridline") {
                        double[] dash = { 1.5, 1.5 };
                        cr.set_dash(dash, 0);
                    }
                    cr.rectangle(d.x, d.y, d.w, d.h);
                    cr.stroke();
                    cr.set_dash(null, 0);
                    break;
                case DecoKind.LINE:
                    set_color(cr, d.color);
                    double w = double.max(0.25, d.width);
                    cr.set_line_width(w);
                    if (d.style == "dotted") {
                        double[] dash = { w, w * 2 };
                        cr.set_dash(dash, 0);
                    } else if (d.style == "dashed") {
                        double[] dash = { w * 4, w * 2 };
                        cr.set_dash(dash, 0);
                    }
                    if (d.style == "double") {
                        bool horiz = d.h.abs() < d.w.abs();
                        double off = w * 1.5;
                        cr.move_to(d.x + (horiz ? 0 : -off), d.y + (horiz ? -off : 0));
                        cr.line_to(d.x + d.w + (horiz ? 0 : -off), d.y + d.h + (horiz ? -off : 0));
                        cr.move_to(d.x + (horiz ? 0 : off), d.y + (horiz ? off : 0));
                        cr.line_to(d.x + d.w + (horiz ? 0 : off), d.y + d.h + (horiz ? off : 0));
                    } else {
                        cr.move_to(d.x, d.y);
                        cr.line_to(d.x + d.w, d.y + d.h);
                    }
                    cr.stroke();
                    cr.set_dash(null, 0);
                    break;
                case DecoKind.LEADER:
                    var l = new Pango.Layout(pctx);
                    l.set_font_description(Pango.FontDescription.from_string("Liberation Serif 10"));
                    l.set_text(d.text, -1);
                    Pango.Rectangle ink, logical;
                    l.get_extents(out ink, out logical);
                    double cw = double.max(1, logical.width / (double) Pango.SCALE);
                    int n = (int) (d.w / cw);
                    var sb = new StringBuilder();
                    for (int i = 0; i < n; i++) sb.append(d.text);
                    l.set_text(sb.str, -1);
                    set_color(cr, "#000000");
                    cr.move_to(d.x + d.w - n * cw, d.y);
                    Pango.cairo_show_layout_line(cr, l.get_line_readonly(0));
                    break;
                case DecoKind.SEPARATOR:
                    if (d.text.has_prefix("notemark:")) {
                        var nl = new Pango.Layout(pctx);
                        nl.set_font_description(Pango.FontDescription.from_string("Liberation Serif 7"));
                        nl.set_text(d.text.substring(9), -1);
                        set_color(cr, "#000000");
                        Pango.Rectangle ink2, lg2;
                        nl.get_extents(out ink2, out lg2);
                        cr.move_to(d.x - lg2.width / (double) Pango.SCALE - 1, d.y - 4);
                        Pango.cairo_show_layout_line(cr, nl.get_line_readonly(0));
                    } else if (d.text.has_prefix("outline-")) {
                        cr.set_source_rgb(0.45, 0.5, 0.6);
                        cr.set_line_width(1);
                        if (d.text == "outline-body") {
                            cr.arc(d.x + d.w / 2, d.y + d.h / 2, 2, 0, 2 * Math.PI);
                            cr.fill();
                        } else {
                            cr.arc(d.x + d.w / 2, d.y + d.h / 2, d.w / 2 - 1, 0, 2 * Math.PI);
                            cr.stroke();
                            cr.move_to(d.x + 2.5, d.y + d.h / 2);
                            cr.line_to(d.x + d.w - 2.5, d.y + d.h / 2);
                            if (d.text == "outline-collapsed") {
                                cr.move_to(d.x + d.w / 2, d.y + 2.5);
                                cr.line_to(d.x + d.w / 2, d.y + d.h - 2.5);
                            }
                            cr.stroke();
                        }
                    } else if (d.text == "dropcap" && d.data is ParaLayout) {
                        var pl = (ParaLayout) d.data;
                        if (pl.dropcap != null) {
                            set_color(cr, pl.text.first_props.color ?? "#000000");
                            Pango.Rectangle ink3, lg3;
                            pl.dropcap.get_extents(out ink3, out lg3);
                            cr.move_to(d.x, d.y - ink3.y / (double) Pango.SCALE);
                            Pango.cairo_show_layout(cr, pl.dropcap);
                        }
                    }
                    break;
                default:
                    break;
            }
        }

        public void draw_line(Cairo.Context cr, LineBox lb) {
            unowned Pango.LayoutLine? line = lb.line();
            if (line == null) return;
            bool dim = (dim_body && lb.region == Region.BODY) || (dim_headers && (lb.region == Region.HEADER || lb.region == Region.FOOTER));
            cr.save();
            if (dim) cr.push_group();
            if (lb.first && lb.pl.label_layout != null) {
                set_color(cr, lb.pl.text.first_props.color ?? "#000000");
                cr.move_to(lb.x + lb.pl.label_x, lb.baseline);
                Pango.cairo_show_layout_line(cr, lb.pl.label_layout.get_line_readonly(0));
            }
            set_color(cr, lb.pl.text.mark_props.color ?? "#000000");
            cr.move_to(lb.x + lb.info.x, lb.baseline);
            Pango.cairo_show_layout_line(cr, line);
            if (opts.formatting_marks && !opts.print) draw_marks(cr, lb);
            if (dim) {
                cr.pop_group_to_source();
                cr.paint_with_alpha(0.45);
            }
            cr.restore();
        }

        private void draw_marks(Cairo.Context cr, LineBox lb) {
            var ml = new Pango.Layout(pctx);
            ml.set_font_description(Pango.FontDescription.from_string("Liberation Sans 8"));
            cr.set_source_rgba(0.35, 0.45, 0.7, 0.9);
            string t = lb.pl.text.text;
            int i = lb.info.start_byte;
            while (i < lb.info.end_byte && i < t.length) {
                int prev = i;
                unichar c;
                t.get_next_char(ref i, out c);
                if (c == ' ' || c == '\t' || c == 0xA0) {
                    double x0 = lb.caret_x(prev);
                    double x1 = lb.caret_x(i);
                    ml.set_text(c == '\t' ? "\u2192" : (c == 0xA0 ? "\u00b0" : "\u00b7"), -1);
                    Pango.Rectangle ink, lg;
                    ml.get_extents(out ink, out lg);
                    cr.move_to((x0 + x1) / 2 - lg.width / (2.0 * Pango.SCALE), lb.baseline);
                    Pango.cairo_show_layout_line(cr, ml.get_line_readonly(0));
                } else if (c == 0x2028) {
                    ml.set_text("\u21b5", -1);
                    cr.move_to(lb.caret_x(prev) + 1, lb.baseline);
                    Pango.cairo_show_layout_line(cr, ml.get_line_readonly(0));
                }
            }
            if (lb.last) {
                ml.set_text("\u00b6", -1);
                cr.move_to(lb.caret_x(lb.info.end_byte) + 1, lb.baseline);
                Pango.cairo_show_layout_line(cr, ml.get_line_readonly(0));
            }
        }

        private void draw_line_numbers(Cairo.Context cr, PageBox p) {
            int n = 0;
            var ml = new Pango.Layout(pctx);
            ml.set_font_description(Pango.FontDescription.from_string("Liberation Serif 8"));
            cr.set_source_rgb(0.4, 0.4, 0.4);
            foreach (var lb in p.lines) {
                if (lb.region != Region.BODY) continue;
                n++;
                ml.set_text(n.to_string(), -1);
                Pango.Rectangle ink, lg;
                ml.get_extents(out ink, out lg);
                cr.move_to(p.body_left - 18 - lg.width / (double) Pango.SCALE, lb.baseline);
                Pango.cairo_show_layout_line(cr, ml.get_line_readonly(0));
            }
        }

        public void draw_object(Cairo.Context cr, ObjBox o) {
            cr.save();
            if (o.item is ImageRun) {
                draw_image(cr, (ImageRun) o.item, o.x, o.y, o.w, o.h);
            } else if (o.item is ShapeRun) {
                draw_shape(cr, (ShapeRun) o.item, o);
            } else if (o.item is EquationRun) {
                draw_equation(cr, (EquationRun) o.item, o);
            } else if (o.item is ChartRun) {
                var ch = (ChartRun) o.item;
                var ph = new OpaqueRun("chart", "", _("Chart"));
                ph.preview = ch.preview;
                draw_opaque(cr, ph, o);
            } else if (o.item is OpaqueRun) {
                draw_opaque(cr, (OpaqueRun) o.item, o);
            }
            cr.restore();
        }

        private void draw_opaque(Cairo.Context cr, OpaqueRun op, ObjBox o) {
            if (op.preview != null) {
                var s = ImageCache.get_surface(op.preview);
                if (s != null) {
                    cr.save();
                    cr.rectangle(o.x, o.y, o.w, o.h);
                    cr.clip();
                    cr.translate(o.x, o.y);
                    cr.scale(o.w / s.get_width(), o.h / s.get_height());
                    cr.set_source_surface(s, 0, 0);
                    cr.paint();
                    cr.restore();
                    return;
                }
            }
            cr.set_source_rgb(0.93, 0.93, 0.95);
            cr.rectangle(o.x, o.y, o.w, o.h);
            cr.fill_preserve();
            cr.set_source_rgb(0.6, 0.6, 0.65);
            cr.set_line_width(0.75);
            cr.stroke();
            var l = new Pango.Layout(pctx);
            l.set_font_description(Pango.FontDescription.from_string("Liberation Sans 9"));
            l.set_width((int) ((o.w - 8) * Pango.SCALE));
            l.set_alignment(Pango.Alignment.CENTER);
            l.set_text(op.description, -1);
            cr.set_source_rgb(0.3, 0.3, 0.35);
            cr.move_to(o.x + 4, o.y + o.h / 2 - 6);
            Pango.cairo_show_layout(cr, l);
        }

        public void draw_image(Cairo.Context cr, ImageRun img, double x, double y, double w, double h) {
            var s = ImageCache.get_surface(img.data);
            if (s == null) {
                cr.set_source_rgb(0.9, 0.9, 0.9);
                cr.rectangle(x, y, w, h);
                cr.fill();
                return;
            }
            double sw = s.get_width();
            double sh = s.get_height();
            double cl = img.crop_l * sw;
            double ct = img.crop_t * sh;
            double cw = sw * (1 - img.crop_l - img.crop_r);
            double ch = sh * (1 - img.crop_t - img.crop_b);
            if (cw <= 0 || ch <= 0) return;
            cr.save();
            cr.rectangle(x, y, w, h);
            cr.clip();
            cr.translate(x, y);
            cr.scale(w / cw, h / ch);
            cr.set_source_surface(s, -cl, -ct);
            ((Cairo.Pattern) cr.get_source()).set_filter(Cairo.Filter.GOOD);
            cr.paint();
            if (img.grayscale) {
                cr.set_operator(Cairo.Operator.HSL_SATURATION);
                cr.set_source_rgb(0.5, 0.5, 0.5);
                cr.paint();
            }
            if (img.brightness != 0) {
                cr.set_operator(Cairo.Operator.OVER);
                if (img.brightness > 0) cr.set_source_rgba(1, 1, 1, img.brightness.clamp(0, 1));
                else cr.set_source_rgba(0, 0, 0, (-img.brightness).clamp(0, 1));
                cr.paint();
            }
            cr.restore();
            if (img.outline_border != null && img.outline_border.visible()) {
                set_color(cr, img.outline_border.color);
                cr.set_line_width(img.outline_border.width);
                cr.rectangle(x, y, w, h);
                cr.stroke();
            }
        }

        public static void shape_path(Cairo.Context cr, ShapeKind kind, double x, double y, double w, double h) {
            switch (kind) {
                case ShapeKind.ELLIPSE:
                    cr.save();
                    cr.translate(x + w / 2, y + h / 2);
                    cr.scale(double.max(0.1, w / 2), double.max(0.1, h / 2));
                    cr.arc(0, 0, 1, 0, 2 * Math.PI);
                    cr.restore();
                    break;
                case ShapeKind.ROUND_RECT:
                    double r = double.min(w, h) * 0.16;
                    cr.new_sub_path();
                    cr.arc(x + w - r, y + r, r, -Math.PI / 2, 0);
                    cr.arc(x + w - r, y + h - r, r, 0, Math.PI / 2);
                    cr.arc(x + r, y + h - r, r, Math.PI / 2, Math.PI);
                    cr.arc(x + r, y + r, r, Math.PI, 1.5 * Math.PI);
                    cr.close_path();
                    break;
                case ShapeKind.TRIANGLE:
                    cr.move_to(x + w / 2, y);
                    cr.line_to(x + w, y + h);
                    cr.line_to(x, y + h);
                    cr.close_path();
                    break;
                case ShapeKind.ARROW:
                    cr.move_to(x, y + h * 0.25);
                    cr.line_to(x + w * 0.75, y + h * 0.25);
                    cr.line_to(x + w * 0.75, y);
                    cr.line_to(x + w, y + h / 2);
                    cr.line_to(x + w * 0.75, y + h);
                    cr.line_to(x + w * 0.75, y + h * 0.75);
                    cr.line_to(x, y + h * 0.75);
                    cr.close_path();
                    break;
                case ShapeKind.LINE:
                    cr.move_to(x, y);
                    cr.line_to(x + w, y + h);
                    break;
                default:
                    cr.rectangle(x, y, w, h);
                    break;
            }
        }

        private void draw_shape(Cairo.Context cr, ShapeRun s, ObjBox o) {
            cr.save();
            if (s.rotation != 0) {
                cr.translate(o.x + o.w / 2, o.y + o.h / 2);
                cr.rotate(s.rotation * Math.PI / 180);
                cr.translate(-(o.x + o.w / 2), -(o.y + o.h / 2));
            }
            shape_path(cr, s.kind, o.x, o.y, o.w, o.h);
            if (s.fill != null && s.kind != ShapeKind.LINE) {
                set_color(cr, s.fill);
                cr.fill_preserve();
            }
            if (s.stroke != null) {
                set_color(cr, s.stroke);
                cr.set_line_width(s.stroke_width);
                cr.stroke();
            } else {
                cr.new_path();
            }
            if (o.inner != null) {
                cr.rectangle(o.x, o.y, o.w, o.h);
                cr.clip();
                foreach (var d in o.inner.decos) draw_deco(cr, d);
                foreach (var lb in o.inner.lines) draw_line(cr, lb);
                foreach (var io in o.inner.objects) draw_object(cr, io);
            }
            cr.restore();
        }

        private void draw_equation(Cairo.Context cr, EquationRun e, ObjBox o) {
            if (e.preview != null) {
                var s = ImageCache.get_surface(e.preview);
                if (s != null) {
                    cr.save();
                    cr.translate(o.x, o.y);
                    cr.scale(o.w / s.get_width(), o.h / s.get_height());
                    cr.set_source_surface(s, 0, 0);
                    ((Cairo.Pattern) cr.get_source()).set_filter(Cairo.Filter.GOOD);
                    cr.paint();
                    cr.restore();
                    return;
                }
            }
            var l = new Pango.Layout(pctx);
            l.set_font_description(Pango.FontDescription.from_string("Liberation Serif Italic 11"));
            l.set_text(e.linear_text(), -1);
            cr.set_source_rgb(0.1, 0.1, 0.2);
            cr.move_to(o.x, o.y + o.h - 4);
            Pango.cairo_show_layout_line(cr, l.get_line_readonly(0));
            if (!opts.print) {
                cr.set_source_rgba(0.2, 0.3, 0.8, 0.25);
                cr.set_line_width(0.5);
                cr.rectangle(o.x - 1, o.y - 1, o.w + 2, o.h + 2);
                cr.stroke();
            }
        }
    }
}
