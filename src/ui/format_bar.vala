using Gtk;
using Write;

namespace Singularity.Apps {

    public class ColorSwatchFace : Gtk.Box {
        public string? color = null;
        private Gtk.DrawingArea bar;
        private string fallback;

        public ColorSwatchFace(string icon, string fallback) {
            Object(orientation: Orientation.VERTICAL, spacing: 1);
            this.fallback = fallback;
            valign = Gtk.Align.CENTER;
            append(new Image.from_icon_name(icon));
            bar = new Gtk.DrawingArea();
            bar.set_size_request(16, 3);
            bar.set_draw_func((area, cr, w, h) => {
                double r, g, b;
                Write.Palette.rgbd(color ?? this.fallback, out r, out g, out b);
                if (color == null && this.fallback == "none") {
                    cr.set_source_rgba(0.5, 0.5, 0.5, 0.35);
                } else {
                    cr.set_source_rgb(r, g, b);
                }
                cr.rectangle(0, 0, w, h);
                cr.fill();
            });
            append(bar);
        }

        public void set_color(string? c) {
            color = c;
            bar.queue_draw();
        }
    }

    public class WriteRuler : Gtk.DrawingArea {
        public WriteDocView? view = null;
        public bool metric = true;
        private int dragging = -1;
        private double press_x = 0;
        public signal void indents_changed(double left, double first, double right);
        public signal void margins_changed(double left, double right);
        public signal void tab_added(double pos);
        public signal void tab_removed(int index);
        public signal void tab_moved(int index, double pos);

        public WriteRuler() {
            add_css_class("sx-rulers");
            add_css_class("write-ruler");
            set_content_height(24);
            hexpand = true;
            set_draw_func(draw);
            var click = new Gtk.GestureDrag();
            click.drag_begin.connect(on_begin);
            click.drag_update.connect(on_update);
            click.drag_end.connect(on_end);
            add_controller(click);
        }

        private bool geometry(out double x0, out double scale, out PageBox? page, out LineBox? line) {
            x0 = 0;
            scale = 1;
            page = null;
            line = null;
            if (view == null || view.lay == null || view.ed == null) return false;
            line = view.line_for(view.ed.focus);
            int pg = line != null ? line.page : view.visible_page();
            if (pg < 0 || pg >= view.lay.pages.size) return false;
            page = view.lay.pages[pg];
            double wx, wy;
            view.page_to_widget(pg, 0, 0, out wx, out wy);
            Graphene.Point src = { (float) wx, 0 };
            Graphene.Point dst;
            if (!view.compute_point(this, src, out dst)) return false;
            x0 = dst.x;
            scale = view.scale;
            return true;
        }

        private void markers(out double left, out double first, out double right, out double col_x, out double col_w) {
            left = 0;
            first = 0;
            right = 0;
            col_x = 72;
            col_w = 468;
            double x0, s;
            PageBox? page;
            LineBox? line;
            if (!geometry(out x0, out s, out page, out line)) return;
            col_x = line != null ? line.clip_x0 : page.body_left;
            col_w = line != null ? line.clip_x1 - line.clip_x0 : page.body_right - page.body_left;
            var pp = view.doc.styles.resolve_para(view.ed.focus.para);
            left = pp.ind_left.is_nan() ? 0 : pp.ind_left;
            first = pp.ind_first.is_nan() ? 0 : pp.ind_first;
            right = pp.ind_right.is_nan() ? 0 : pp.ind_right;
            if (line != null && line.pl.label != null) {
                left = line.pl.ind_left;
                first = line.pl.label_x - line.pl.ind_left;
            }
        }

        private void draw(Gtk.DrawingArea area, Cairo.Context cr, int w, int h) {
            var fg = get_color();
            double x0, s;
            PageBox? page;
            LineBox? line;
            if (!geometry(out x0, out s, out page, out line)) return;
            double left, first, right, cx, cw;
            markers(out left, out first, out right, out cx, out cw);
            double top = 3;
            double bh = h - 6;
            cr.set_source_rgba(fg.red, fg.green, fg.blue, 0.10);
            cr.rectangle(x0, top, page.width * s, bh);
            cr.fill();
            cr.set_source_rgba(fg.red, fg.green, fg.blue, 0.04);
            cr.rectangle(x0 + cx * s, top, cw * s, bh);
            cr.fill();
            cr.set_source_rgba(fg.red, fg.green, fg.blue, 0.12);
            cr.set_line_width(1);
            cr.rectangle(Math.round(x0) + 0.5, top + 0.5, Math.round(page.width * s) - 1, bh - 1);
            cr.stroke();
            double unit = metric ? 28.3464567 : 72;
            double minor = metric ? unit / 4 : unit / 8;
            var l = Pango.cairo_create_layout(cr);
            var fd = new Pango.FontDescription();
            fd.set_family("Inter");
            fd.set_absolute_size(9 * Pango.SCALE);
            l.set_font_description(fd);
            double mid = top + bh / 2.0;
            for (double v = 0; v <= page.width; v += minor) {
                double x = Math.round(x0 + v * s) + 0.5;
                int idx = (int) Math.round(v / minor);
                bool major = (idx % (metric ? 4 : 8)) == 0;
                bool half = (idx % (metric ? 2 : 4)) == 0;
                if (major) {
                    int n = (int) Math.round((v - cx) / unit);
                    if (n != 0) {
                        l.set_text(n.abs().to_string(), -1);
                        int lw, lh;
                        l.get_pixel_size(out lw, out lh);
                        cr.set_source_rgba(fg.red, fg.green, fg.blue, 0.65);
                        cr.move_to(x - lw / 2.0, mid - lh / 2.0);
                        Pango.cairo_show_layout(cr, l);
                    }
                } else {
                    double len = half ? 6 : 3;
                    cr.set_source_rgba(fg.red, fg.green, fg.blue, half ? 0.45 : 0.3);
                    cr.move_to(x, mid - len / 2);
                    cr.line_to(x, mid + len / 2);
                    cr.stroke();
                }
            }
            double lx = x0 + (cx + left) * s;
            double fx = x0 + (cx + left + first) * s;
            double rx = x0 + (cx + cw - right) * s;
            var ac = accent();
            cr.set_source_rgba(ac.red, ac.green, ac.blue, 1);
            cr.move_to(fx - 5, 1);
            cr.line_to(fx + 5, 1);
            cr.line_to(fx, 8);
            cr.close_path();
            cr.fill();
            cr.move_to(lx - 5, h - 1);
            cr.line_to(lx + 5, h - 1);
            cr.line_to(lx, h - 8);
            cr.close_path();
            cr.fill();
            cr.move_to(rx - 5, h - 1);
            cr.line_to(rx + 5, h - 1);
            cr.line_to(rx, h - 8);
            cr.close_path();
            cr.fill();
            var pp = view.doc.styles.resolve_para(view.ed.focus.para);
            if (pp.tabs != null) {
                cr.set_source_rgba(fg.red, fg.green, fg.blue, 0.85);
                cr.set_line_width(1.5);
                foreach (var t in pp.tabs) {
                    double tx = x0 + (cx + t.pos) * s;
                    cr.move_to(tx, h - 9);
                    cr.line_to(tx, h - 3);
                    if (t.align == TabAlign.RIGHT) cr.line_to(tx - 5, h - 3);
                    else if (t.align == TabAlign.CENTER) {
                        cr.move_to(tx - 4, h - 3);
                        cr.line_to(tx + 4, h - 3);
                    } else cr.line_to(tx + 5, h - 3);
                    cr.stroke();
                }
            }
        }

        private Gdk.RGBA accent() {
            var c = Gdk.RGBA();
            if (!c.parse(Singularity.Style.StyleManager.get_default().accent_hex)) c.parse("#3584e4");
            return c;
        }

        private void on_begin(double x, double y) {
            press_x = x;
            dragging = -1;
            double x0, s;
            PageBox? page;
            LineBox? line;
            if (!geometry(out x0, out s, out page, out line)) return;
            double left, first, right, cx, cw;
            markers(out left, out first, out right, out cx, out cw);
            double lx = x0 + (cx + left) * s;
            double fx = x0 + (cx + left + first) * s;
            double rx = x0 + (cx + cw - right) * s;
            if ((x - fx).abs() < 7 && y < 11) dragging = 0;
            else if ((x - lx).abs() < 7) dragging = 1;
            else if ((x - rx).abs() < 7) dragging = 2;
            else if ((x - (x0 + cx * s)).abs() < 5) dragging = 3;
            else if ((x - (x0 + (cx + cw) * s)).abs() < 5) dragging = 4;
            else {
                var pp = view.doc.styles.resolve_para(view.ed.focus.para);
                if (pp.tabs != null) {
                    for (int i = 0; i < pp.tabs.size; i++) {
                        if ((x - (x0 + (cx + pp.tabs[i].pos) * s)).abs() < 5) dragging = 10 + i;
                    }
                }
                if (dragging < 0 && x > x0 + cx * s && x < x0 + (cx + cw) * s && y > get_height() / 2) dragging = 100;
            }
        }

        private void on_update(double dx, double dy) {
            queue_draw();
        }

        private void on_end(double dx, double dy) {
            if (dragging < 0) return;
            double x0, s;
            PageBox? page;
            LineBox? line;
            if (!geometry(out x0, out s, out page, out line)) return;
            double left, first, right, cx, cw;
            markers(out left, out first, out right, out cx, out cw);
            double pt = (press_x + dx - x0) / s - cx;
            double snap = metric ? 28.3464567 / 8 : 72.0 / 16;
            pt = Math.round(pt / snap) * snap;
            switch (dragging) {
                case 0:
                    indents_changed(left, pt - left, right);
                    break;
                case 1:
                    indents_changed(double.max(0, pt), left + first - double.max(0, pt), right);
                    break;
                case 2:
                    indents_changed(left, first, double.max(0, cw - pt));
                    break;
                case 3:
                    margins_changed(double.max(0, (press_x + dx - x0) / s), -1);
                    break;
                case 4:
                    margins_changed(-1, double.max(0, page.width - (press_x + dx - x0) / s));
                    break;
                case 100:
                    if (dx.abs() < 3) tab_added(pt);
                    break;
                default:
                    if (dragging >= 10) {
                        if (dy.abs() > 18) tab_removed(dragging - 10);
                        else tab_moved(dragging - 10, pt);
                    }
                    break;
            }
            dragging = -1;
            queue_draw();
        }
    }
}
