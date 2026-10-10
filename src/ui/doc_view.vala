using Gtk;
using Write;

namespace Singularity.Apps {

    public enum ViewMode {
        PRINT,
        WEB,
        READ,
        OUTLINE,
        DRAFT
    }

    public class SpellRange : Object {
        public int start;
        public int end;
        public bool grammar;
        public Write.Issue? issue;
    }

    public class RemoteCaret {
        public string name = "";
        public string color = "#1c71d8";
        public Write.LivePosition? focus = null;
        public Write.LivePosition? anchor = null;
    }

    public class WriteDocView : Gtk.Widget, Gtk.Scrollable, Gtk.AccessibleText {
        public Write.Document doc;
        public Write.Editor ed;
        public Write.LayoutEngine engine;
        public Write.DocLayout lay;
        public Write.ViewOptions opts = new Write.ViewOptions();
        public Write.Renderer renderer;
        public double zoom = 1.0;
        public ViewMode mode = ViewMode.PRINT;
        public bool fit_width = false;
        public bool fit_page = false;
        public bool read_only = false;
        public bool spell_enabled = true;
        public bool grammar_enabled = true;
        public string filename = "";
        public CharProps? pending = null;
        public Write.Region edit_region = Write.Region.BODY;
        public int edit_page = 0;
        public ObjBox? selected_obj = null;
        public bool crop_mode = false;
        public Gee.ArrayList<RemoteCaret> remote = new Gee.ArrayList<RemoteCaret>();
        public string remote_edit_by = "";
        public string doc_lang = "";
        public bool show_comments = true;

        private const double PX = 96.0 / 72.0;
        private const double GAP = 18;
        private const double COMMENT_W = 230;
        private Gtk.Adjustment? _hadj = null;
        private Gtk.Adjustment? _vadj = null;
        private Gtk.ScrollablePolicy _hpol = Gtk.ScrollablePolicy.MINIMUM;
        private Gtk.ScrollablePolicy _vpol = Gtk.ScrollablePolicy.MINIMUM;
        private double[] page_x = {};
        private double[] page_y = {};
        private double canvas_w = 0;
        private double canvas_h = 0;
        private uint relayout_id = 0;
        private bool caret_on = true;
        private uint blink_id = 0;
        private double goal_x = -1;
        private Gtk.IMMulticontext im;
        private string preedit = "";
        private Gee.HashMap<Paragraph, SpellCache> spell = new Gee.HashMap<Paragraph, SpellCache>();
        private Write.GrammarChecker grammar = new Write.GrammarChecker();
        private int press_count = 0;
        private double drag_x0;
        private double drag_y0;
        private int drag_mode = 0;
        private int drag_handle = -1;
        private double obj_x0;
        private double obj_y0;
        private double obj_w0;
        private double obj_h0;
        private double crop0_l;
        private double crop0_t;
        private double crop0_r;
        private double crop0_b;
        public Gee.HashMap<string, double?> comment_positions = new Gee.HashMap<string, double?>();
        public string? active_comment = null;

        private class SpellCache {
            public uint version;
            public string lang;
            public Gee.ArrayList<SpellRange> ranges = new Gee.ArrayList<SpellRange>();
        }

        public signal void changed();
        public signal void selection_changed();
        public signal void layout_changed();
        public signal void context_menu(double x, double y);
        public signal void edit_equation(EquationRun e);
        public signal void edit_object(Inline item);
        public signal void open_link(string url);
        public signal void comment_activated(string id);
        public signal void zoom_changed();
        public signal void region_changed();
        public signal void typed(string text);

        public Gtk.Adjustment hadjustment {
            get { return _hadj; }
            set construct {
                if (_hadj != null) _hadj.value_changed.disconnect(on_scroll);
                _hadj = value;
                if (_hadj != null) _hadj.value_changed.connect(on_scroll);
                configure_adjustments();
            }
        }

        public Gtk.Adjustment vadjustment {
            get { return _vadj; }
            set construct {
                if (_vadj != null) _vadj.value_changed.disconnect(on_scroll);
                _vadj = value;
                if (_vadj != null) _vadj.value_changed.connect(on_scroll);
                configure_adjustments();
            }
        }

        public Gtk.ScrollablePolicy hscroll_policy {
            get { return _hpol; }
            set { _hpol = value; }
        }

        public Gtk.ScrollablePolicy vscroll_policy {
            get { return _vpol; }
            set { _vpol = value; }
        }

        public bool get_border(out Gtk.Border border) {
            border = Gtk.Border();
            return false;
        }

        public WriteDocView() {
            Object(accessible_role: Gtk.AccessibleRole.TEXT_BOX);
            focusable = true;
            can_focus = true;
            hexpand = true;
            vexpand = true;
            add_css_class("write-docview");
            set_cursor_from_name("text");
            im = new Gtk.IMMulticontext();
            im.commit.connect(on_commit);
            im.preedit_changed.connect(() => {
                string s;
                Pango.AttrList a;
                int c;
                im.get_preedit_string(out s, out a, out c);
                preedit = s;
                queue_draw();
            });
            var key = new Gtk.EventControllerKey();
            key.set_im_context(im);
            key.key_pressed.connect(on_key);
            add_controller(key);
            var focus = new Gtk.EventControllerFocus();
            focus.enter.connect(() => {
                im.focus_in();
                restart_blink();
            });
            focus.leave.connect(() => {
                im.focus_out();
                queue_draw();
            });
            add_controller(focus);
            var click = new Gtk.GestureClick();
            click.button = 0;
            click.pressed.connect(on_press);
            click.released.connect(on_release);
            add_controller(click);
            var drag = new Gtk.GestureDrag();
            drag.drag_update.connect(on_drag_update);
            drag.drag_end.connect((dx, dy) => {
                if (drag_mode == 2 || drag_mode == 3) end_object_drag();
                drag_mode = 0;
            });
            add_controller(drag);
            var scroll = new Gtk.EventControllerScroll(Gtk.EventControllerScrollFlags.VERTICAL);
            scroll.scroll.connect((dx, dy) => {
                var state = scroll.get_current_event_state();
                if ((state & Gdk.ModifierType.CONTROL_MASK) != 0) {
                    set_zoom(zoom * (dy < 0 ? 1.1 : 1 / 1.1));
                    return true;
                }
                return false;
            });
            add_controller(scroll);
            var motion = new Gtk.EventControllerMotion();
            motion.motion.connect(on_motion);
            add_controller(motion);
            im.set_client_widget(this);
        }

        public void set_document(Write.Document d, Write.Editor e) {
            doc = d;
            doc_lang = "";
            ed = e;
            engine = new Write.LayoutEngine(d, opts);
            engine.filename = filename;
            renderer = new Write.Renderer(d, opts, engine.context());
            ed.selection_changed.connect(() => {
                goal_x = -1;
                ensure_caret_visible();
                restart_blink();
                queue_draw();
                selection_changed();
                update_caret_position();
                update_selection_bound();
            });
            ed.changed.connect(() => {
                scroll_after_layout = true;
                queue_relayout();
                changed();
            });
            spell.clear();
            edit_region = Write.Region.BODY;
            selected_obj = null;
            relayout_now();
        }

        public double scale {
            get { return zoom * PX; }
        }

        public void set_zoom(double z) {
            fit_width = false;
            fit_page = false;
            apply_zoom(z);
        }

        private void apply_zoom(double z) {
            zoom = z.clamp(0.1, 5.0);
            compute_positions();
            configure_adjustments();
            queue_draw();
            zoom_changed();
        }

        public void set_mode(ViewMode m) {
            mode = m;
            opts.draft = m == ViewMode.WEB || m == ViewMode.DRAFT || m == ViewMode.OUTLINE;
            engine.outline_mode = m == ViewMode.OUTLINE;
            if (m == ViewMode.READ) {
                read_only = true;
            }
            engine.invalidate();
            relayout_now();
        }

        public void queue_relayout() {
            if (relayout_id != 0) return;
            relayout_id = Idle.add(() => {
                relayout_id = 0;
                relayout_now();
                return Source.REMOVE;
            }, Priority.HIGH_IDLE + 5);
        }

        public void relayout_now() {
            if (relayout_id != 0) {
                Source.remove(relayout_id);
                relayout_id = 0;
            }
            if (doc == null) return;
            if (opts.draft) {
                double w = get_width() > 0 ? get_width() : 900;
                engine.draft_width = double.max(200, (w - 40) / scale);
            }
            engine.filename = filename;
            lay = engine.run();
            if (edit_page >= lay.pages.size) edit_page = int.max(0, lay.pages.size - 1);
            if (fit_width || fit_page) fit_zoom();
            compute_positions();
            configure_adjustments();
            queue_draw();
            layout_changed();
            if (scroll_after_layout) {
                scroll_after_layout = false;
                ensure_caret_visible();
            }
            update_contents(Gtk.AccessibleTextContentChange.INSERT, 0, 0);
        }

        private bool scroll_after_layout = false;

        private void fit_zoom() {
            if (lay == null || lay.pages.size == 0 || get_width() <= 0) return;
            var p = lay.pages[0];
            double avail_w = get_width() - 2 * GAP - (show_comments && has_comments() ? COMMENT_W : 0);
            double z = avail_w / (p.width * PX);
            if (fit_page) z = double.min(z, (get_height() - 2 * GAP) / (p.height * PX));
            zoom = z.clamp(0.1, 5.0);
            zoom_changed();
        }

        public bool has_comments() {
            return doc != null && doc.comments.size > 0;
        }

        private void compute_positions() {
            if (lay == null) return;
            int n = lay.pages.size;
            page_x = new double[n];
            page_y = new double[n];
            double w = get_width();
            double s = scale;
            double extra = show_comments && has_comments() && mode == ViewMode.PRINT ? COMMENT_W : 0;
            if (mode == ViewMode.READ) {
                double y = GAP;
                double maxw = 0;
                for (int i = 0; i < n; i += 2) {
                    double pw = lay.pages[i].width * s;
                    double pw2 = i + 1 < n ? lay.pages[i + 1].width * s : 0;
                    double rw = pw + (pw2 > 0 ? GAP + pw2 : 0);
                    double x0 = double.max(GAP, (w - rw) / 2);
                    page_x[i] = x0;
                    page_y[i] = y;
                    if (i + 1 < n) {
                        page_x[i + 1] = x0 + pw + GAP;
                        page_y[i + 1] = y;
                    }
                    double h = double.max(lay.pages[i].height, i + 1 < n ? lay.pages[i + 1].height : 0) * s;
                    y += h + GAP;
                    maxw = double.max(maxw, rw);
                }
                canvas_w = double.max(w, maxw + 2 * GAP);
                canvas_h = y;
                return;
            }
            double maxpw = 0;
            foreach (var p in lay.pages) maxpw = double.max(maxpw, p.width * s);
            canvas_w = double.max(w, maxpw + 2 * GAP + extra);
            double y = opts.draft ? 0 : GAP;
            for (int i = 0; i < n; i++) {
                double pw = lay.pages[i].width * s;
                page_x[i] = opts.draft ? 0 : double.max(GAP, (canvas_w - extra - pw) / 2);
                page_y[i] = y;
                double ph = lay.pages[i].height * s;
                if (opts.draft) {
                    double maxy = 0;
                    foreach (var lb in lay.pages[i].lines) maxy = double.max(maxy, lb.top + lb.height);
                    foreach (var o in lay.pages[i].objects) maxy = double.max(maxy, o.y + o.h);
                    ph = (maxy + 40) * s;
                    lay.pages[i].height = maxy + 40;
                }
                y += ph + (opts.draft ? 0 : GAP);
            }
            canvas_h = y;
        }

        private void configure_adjustments() {
            double w = get_width();
            double h = get_height();
            if (_hadj != null) {
                double v = _hadj.value;
                _hadj.configure(v.clamp(0, double.max(0, canvas_w - w)), 0, double.max(canvas_w, w), w * 0.1, w * 0.9, w);
            }
            if (_vadj != null) {
                double v = _vadj.value;
                _vadj.configure(v.clamp(0, double.max(0, canvas_h - h)), 0, double.max(canvas_h, h), 40, h * 0.9, h);
            }
        }

        private void on_scroll() {
            queue_draw();
        }

        public override void size_allocate(int width, int height, int baseline) {
            if (opts.draft) queue_relayout();
            if (fit_width || fit_page) {
                fit_zoom();
            }
            compute_positions();
            configure_adjustments();
        }

        public override void measure(Gtk.Orientation o, int for_size, out int min, out int nat, out int min_base, out int nat_base) {
            min = 100;
            nat = o == Gtk.Orientation.HORIZONTAL ? 900 : 700;
            min_base = -1;
            nat_base = -1;
        }

        private double sx() {
            return _hadj != null ? _hadj.value : 0;
        }

        private double sy() {
            return _vadj != null ? _vadj.value : 0;
        }

        public int visible_page() {
            if (lay == null || lay.pages.size == 0) return 0;
            double mid = sy() + get_height() * 0.3;
            for (int i = 0; i < lay.pages.size; i++) {
                if (page_y[i] + lay.pages[i].height * scale >= mid) return i;
            }
            return lay.pages.size - 1;
        }

        public void to_page(double wx, double wy, out int page, out double px, out double py) {
            double cx = wx + sx();
            double cy = wy + sy();
            page = -1;
            px = 0;
            py = 0;
            if (lay == null || lay.pages.size == 0) return;
            double best = double.MAX;
            for (int i = 0; i < lay.pages.size; i++) {
                double x0 = page_x[i];
                double y0 = page_y[i];
                double x1 = x0 + lay.pages[i].width * scale;
                double y1 = y0 + lay.pages[i].height * scale;
                double dx = cx < x0 ? x0 - cx : (cx > x1 ? cx - x1 : 0);
                double dy = cy < y0 ? y0 - cy : (cy > y1 ? cy - y1 : 0);
                double d = dy * 10 + dx;
                if (d < best) {
                    best = d;
                    page = i;
                }
            }
            px = (cx - page_x[page]) / scale;
            py = (cy - page_y[page]) / scale;
        }

        public void page_to_widget(int page, double px, double py, out double wx, out double wy) {
            wx = page_x[page] + px * scale - sx();
            wy = page_y[page] + py * scale - sy();
        }

        private bool region_ok(LineBox lb) {
            switch (edit_region) {
                case Write.Region.HEADER:
                case Write.Region.FOOTER:
                    return lb.region == Write.Region.HEADER || lb.region == Write.Region.FOOTER;
                default:
                    return lb.region == Write.Region.BODY || lb.region == Write.Region.NOTES || lb.region == Write.Region.FRAME;
            }
        }

        private Gee.ArrayList<LineBox> page_lines(int page) {
            var list = new Gee.ArrayList<LineBox>();
            if (lay == null || page < 0 || page >= lay.pages.size) return list;
            foreach (var lb in lay.pages[page].lines) if (region_ok(lb)) list.add(lb);
            foreach (var o in lay.pages[page].objects) {
                if (o.inner == null) continue;
                foreach (var lb in o.inner.lines) if (region_ok(lb)) list.add(lb);
            }
            return list;
        }

        public Pos? hit(int page, double px, double py) {
            var lines = page_lines(page);
            if (lines.size == 0) return null;
            LineBox? best = null;
            double best_d = double.MAX;
            foreach (var lb in lines) {
                bool in_y = py >= lb.top && py < lb.top + lb.height;
                bool in_x = px >= lb.clip_x0 - 12 && px <= lb.clip_x1 + 12;
                double dy = in_y ? 0 : (py < lb.top ? lb.top - py : py - lb.top - lb.height);
                double dx = in_x ? 0 : (px < lb.clip_x0 ? lb.clip_x0 - px : px - lb.clip_x1);
                double d = dy * 3 + dx;
                if (lb.region == Write.Region.FRAME && !(in_x && in_y)) d += 1000;
                if (d < best_d) {
                    best_d = d;
                    best = lb;
                }
            }
            if (best == null) return null;
            int b = best.hit(px);
            return new Pos(best.para, best.pl.text.byte_to_model(b));
        }

        public LineBox? line_for(Pos p) {
            if (lay == null) return null;
            var list = lay.para_lines[p.para];
            if (list == null || list.size == 0) return null;
            int b = list[0].pl.text.to_byte(p.offset);
            LineBox? found = null;
            foreach (var lb in list) {
                bool here = b >= lb.info.start_byte && b < lb.info.end_byte;
                bool at_end = b == lb.info.end_byte && (lb.last || lb.info.end_byte == lb.info.start_byte);
                if (!here && !at_end) continue;
                if ((edit_region == Write.Region.HEADER || edit_region == Write.Region.FOOTER) && lb.page != edit_page) {
                    if (found == null) found = lb;
                    continue;
                }
                return lb;
            }
            if (found != null) return found;
            foreach (var lb in list) if (b <= lb.info.end_byte) return lb;
            return list[list.size - 1];
        }

        public bool caret_rect(Pos p, out int page, out double x, out double y, out double h) {
            page = 0;
            x = 0;
            y = 0;
            h = 12;
            var lb = line_for(p);
            if (lb == null) return false;
            page = lb.page;
            x = lb.caret_x(lb.pl.text.to_byte(p.offset));
            y = lb.top;
            h = lb.height;
            return true;
        }

        public void ensure_caret_visible() {
            if (ed == null || _vadj == null || lay == null) return;
            int pg;
            double x, y, h;
            if (!caret_rect(ed.focus, out pg, out x, out y, out h)) return;
            if (pg >= page_y.length) return;
            double cy = page_y[pg] + y * scale;
            double ch = h * scale;
            double top = _vadj.value;
            double bot = top + _vadj.page_size;
            if (cy < top + 10) _vadj.value = double.max(0, cy - 40);
            else if (cy + ch > bot - 10) _vadj.value = cy + ch - _vadj.page_size + 40;
            if (_hadj != null) {
                double cx = page_x[pg] + x * scale;
                if (cx < _hadj.value) _hadj.value = double.max(0, cx - 40);
                else if (cx > _hadj.value + _hadj.page_size) _hadj.value = cx - _hadj.page_size + 40;
            }
        }

        public void scroll_to_para(Paragraph p) {
            ed.set_caret(new Pos(p, 0));
            if (_vadj == null) return;
            int pg;
            double x, y, h;
            if (!caret_rect(ed.focus, out pg, out x, out y, out h)) return;
            _vadj.value = double.max(0, page_y[pg] + y * scale - 60);
        }

        public void scroll_to_page(int i) {
            if (_vadj == null || i < 0 || i >= page_y.length) return;
            _vadj.value = page_y[i] - GAP / 2;
        }

        private void restart_blink() {
            caret_on = true;
            if (blink_id != 0) Source.remove(blink_id);
            blink_id = Timeout.add(530, () => {
                caret_on = !caret_on;
                queue_draw();
                return Source.CONTINUE;
            });
            queue_draw();
        }

        public override void dispose() {
            if (blink_id != 0) {
                Source.remove(blink_id);
                blink_id = 0;
            }
            if (relayout_id != 0) {
                Source.remove(relayout_id);
                relayout_id = 0;
            }
            base.dispose();
        }

        private void set_accent(Cairo.Context cr, double alpha) {
            var c = Gdk.RGBA();
            if (!c.parse(Singularity.Style.StyleManager.get_default().accent_hex)) c.parse("#3584e4");
            cr.set_source_rgba(c.red, c.green, c.blue, alpha);
        }

        public override void snapshot(Gtk.Snapshot snap) {
            int w = get_width();
            int h = get_height();
            var bounds = Graphene.Rect();
            bounds.init(0, 0, w, h);
            var cr = snap.append_cairo(bounds);
            if (opts.draft) {
                cr.set_source_rgb(1, 1, 1);
                cr.paint();
            }
            if (lay == null) return;
            double s = scale;
            renderer.dim_body = edit_region == Write.Region.HEADER || edit_region == Write.Region.FOOTER;
            renderer.dim_headers = !renderer.dim_body && mode == ViewMode.PRINT;
            for (int i = 0; i < lay.pages.size; i++) {
                var p = lay.pages[i];
                double x0 = page_x[i] - sx();
                double y0 = page_y[i] - sy();
                double pw = p.width * s;
                double ph = p.height * s;
                if (y0 > h || y0 + ph < 0 || x0 > w || x0 + pw < 0) continue;
                cr.save();
                if (!opts.draft) {
                    cr.set_source_rgba(0, 0, 0, 0.18);
                    cr.rectangle(x0 + 1, y0 + 2, pw, ph);
                    cr.fill();
                }
                cr.translate(x0, y0);
                cr.scale(s, s);
                cr.rectangle(0, 0, p.width, p.height);
                cr.clip();
                renderer.draw_page(cr, p);
                if (!opts.print) draw_overlays(cr, p, i);
                cr.restore();
            }
            if (show_comments && has_comments() && mode == ViewMode.PRINT) draw_comment_balloons(cr);
        }

        private void draw_overlays(Cairo.Context cr, PageBox p, int index) {
            if (edit_region == Write.Region.HEADER || edit_region == Write.Region.FOOTER) {
                if (index == edit_page || true) {
                    set_accent(cr, 0.8);
                    cr.set_line_width(0.6);
                    double[] dash = { 3, 2 };
                    cr.set_dash(dash, 0);
                    double hb = double.max(p.header_bottom, p.section.margin_top - 6);
                    cr.move_to(0, hb + 2);
                    cr.line_to(p.width, hb + 2);
                    double ft = p.footer_top > 0 ? p.footer_top : p.height - p.section.margin_bottom + 6;
                    cr.move_to(0, ft - 2);
                    cr.line_to(p.width, ft - 2);
                    cr.stroke();
                    cr.set_dash(null, 0);
                    var l = new Pango.Layout(engine.context());
                    l.set_font_description(Pango.FontDescription.from_string("Liberation Sans 7"));
                    string head = p.section.title_page && p.first_of_section ? _("First Page Header") : (doc.even_odd_headers ? (p.number % 2 == 0 ? _("Even Page Header") : _("Odd Page Header")) : _("Header"));
                    l.set_text(head, -1);
                    cr.move_to(p.body_left, hb + 3);
                    Pango.cairo_show_layout(cr, l);
                    l.set_text(head.replace(_("Header"), _("Footer")), -1);
                    cr.move_to(p.body_left, ft - 12);
                    Pango.cairo_show_layout(cr, l);
                }
            }
            if (mode == ViewMode.PRINT && !opts.draft) {
                cr.set_source_rgba(0.6, 0.6, 0.6, 0.35);
                cr.set_line_width(0.4);
                double l0 = p.body_left, r0 = p.body_right, t0 = p.body_top, b0 = p.body_bottom;
                double m = 8;
                cr.move_to(l0 - m, t0);
                cr.line_to(l0, t0);
                cr.line_to(l0, t0 - m);
                cr.move_to(r0 + m, t0);
                cr.line_to(r0, t0);
                cr.line_to(r0, t0 - m);
                cr.move_to(l0 - m, b0);
                cr.line_to(l0, b0);
                cr.line_to(l0, b0 + m);
                cr.move_to(r0 + m, b0);
                cr.line_to(r0, b0);
                cr.line_to(r0, b0 + m);
                cr.stroke();
            }
            draw_comment_ranges(cr, p);
            draw_spelling(cr, p);
            draw_selection(cr, index);
            draw_remote(cr, index);
            draw_object_selection(cr, index);
            if (has_focus && caret_on && ed != null && !ed.has_selection && selected_obj == null) draw_caret(cr, index);
        }

        private void draw_comment_ranges(Cairo.Context cr, PageBox p) {
            if (!show_comments) return;
            foreach (var a in p.comments) {
                cr.set_source_rgba(0.98, 0.8, 0.2, a.id == active_comment ? 0.45 : 0.25);
                double y0 = a.y;
                double y1 = a.y_end;
                if (y1 <= y0 + 1 || a.x_end <= a.x) {
                    cr.rectangle(a.x - 1, y0, double.max(3, a.x_end - a.x + 2), double.max(10, y1 - y0));
                } else {
                    cr.rectangle(a.x, y0, a.x_end - a.x, y1 - y0);
                }
                cr.fill();
            }
        }

        private void draw_comment_balloons(Cairo.Context cr) {
            comment_positions.clear();
            double last_bottom = -1e9;
            var l = new Pango.Layout(engine.context());
            for (int i = 0; i < lay.pages.size; i++) {
                var p = lay.pages[i];
                double px = page_x[i] + p.width * scale + 12 - sx();
                foreach (var a in p.comments) {
                    var c = doc.find_comment(a.id);
                    if (c == null) continue;
                    double ay = page_y[i] + a.y * scale - sy();
                    double by = double.max(ay, last_bottom + 6);
                    l.set_width((int) ((COMMENT_W - 36) * Pango.SCALE));
                    l.set_wrap(Pango.WrapMode.WORD_CHAR);
                    l.set_font_description(Pango.FontDescription.from_string("Liberation Sans 8.5"));
                    var sb = new StringBuilder();
                    sb.append("<b>%s</b>\n%s".printf(Markup.escape_text(c.author), Markup.escape_text(c.text())));
                    foreach (var r in doc.comments) if (r.parent_id == c.id) sb.append("\n<b>%s</b>: %s".printf(Markup.escape_text(r.author), Markup.escape_text(r.text())));
                    if (c.done) sb.append("\n<i>%s</i>".printf(_("Resolved")));
                    l.set_markup(sb.str, -1);
                    Pango.Rectangle ink, lg;
                    l.get_extents(out ink, out lg);
                    double bh = lg.height / (double) Pango.SCALE + 12;
                    double bw = COMMENT_W - 24;
                    comment_positions[a.id] = by;
                    cr.set_source_rgba(0.98, 0.8, 0.2, 0.7);
                    cr.set_line_width(0.8);
                    cr.move_to(page_x[i] + a.x * scale - sx(), ay + 2);
                    cr.line_to(px, by + 8);
                    cr.stroke();
                    cr.set_source_rgb(c.done ? 0.93 : 1.0, c.done ? 0.93 : 0.98, c.done ? 0.93 : 0.88);
                    rounded(cr, px, by, bw, bh, 6);
                    cr.fill_preserve();
                    cr.set_source_rgba(0.85, 0.65, 0.1, a.id == active_comment ? 1 : 0.6);
                    cr.stroke();
                    cr.set_source_rgb(0.15, 0.15, 0.15);
                    cr.move_to(px + 6, by + 6);
                    Pango.cairo_show_layout(cr, l);
                    last_bottom = by + bh;
                }
            }
        }

        private static void rounded(Cairo.Context cr, double x, double y, double w, double h, double r) {
            cr.new_sub_path();
            cr.arc(x + w - r, y + r, r, -Math.PI / 2, 0);
            cr.arc(x + w - r, y + h - r, r, 0, Math.PI / 2);
            cr.arc(x + r, y + h - r, r, Math.PI / 2, Math.PI);
            cr.arc(x + r, y + r, r, Math.PI, 1.5 * Math.PI);
            cr.close_path();
        }

        private void draw_caret(Cairo.Context cr, int index) {
            int pg;
            double x, y, h;
            if (!caret_rect(ed.focus, out pg, out x, out y, out h)) return;
            if (pg != index) return;
            var fg = get_color();
            cr.set_source_rgb(0.1, 0.1, 0.12);
            if (doc.page_color != null) {
                double r, g, b;
                Palette.rgbd(doc.page_color, out r, out g, out b);
                if (0.2126 * r + 0.7152 * g + 0.0722 * b < 0.4) cr.set_source_rgb(fg.red, fg.green, fg.blue);
            }
            if (preedit != "") {
                var l = new Pango.Layout(engine.context());
                var props = pending ?? ed.props_for_insert();
                l.set_font_description(TextBuilder.font_for(doc.styles.resolve_char(ed.focus.para, props)));
                l.set_text(preedit, -1);
                var attrs = new Pango.AttrList();
                attrs.insert(Pango.attr_underline_new(Pango.Underline.SINGLE));
                l.set_attributes(attrs);
                cr.move_to(x, y);
                Pango.cairo_show_layout(cr, l);
                return;
            }
            cr.set_line_width(1.2 / scale);
            cr.move_to(x, y);
            cr.line_to(x, y + h);
            cr.stroke();
        }

        private void draw_remote(Cairo.Context cr, int index) {
            if (remote.size == 0 || doc == null) return;
            foreach (var rc in remote) {
                var f = Write.LiveDoc.resolve(doc, rc.focus);
                if (f == null) continue;
                double r, g, b;
                Write.Palette.rgbd(rc.color, out r, out g, out b);
                var a = rc.anchor != null ? Write.LiveDoc.resolve(doc, rc.anchor) : null;
                if (a != null && (a.para != f.para || a.offset != f.offset)) {
                    Pos s0 = a, e0 = f;
                    if (Story.compare(doc, a, f) > 0) {
                        s0 = f;
                        e0 = a;
                    }
                    cr.set_source_rgba(r, g, b, 0.22);
                    foreach (var p in Story.between(doc, s0, e0)) {
                        var list = lay.para_lines[p];
                        if (list == null) continue;
                        int bs = list[0].pl.text.to_byte(p == s0.para ? s0.offset : 0);
                        int be = list[0].pl.text.to_byte(p == e0.para ? e0.offset : p.length);
                        foreach (var lb in list) {
                            if (lb.page != index || lb.region != Write.Region.BODY) continue;
                            int ls = int.max(bs, lb.info.start_byte);
                            int le = int.min(be, lb.info.end_byte);
                            if (le < ls) continue;
                            double x0 = lb.caret_x(ls);
                            double x1 = lb.caret_x(le);
                            cr.rectangle(x0, lb.top, double.max(1, x1 - x0), lb.height);
                            cr.fill();
                        }
                    }
                }
                int pg;
                double x, y, h;
                if (!caret_rect(f, out pg, out x, out y, out h) || pg != index) continue;
                cr.set_source_rgb(r, g, b);
                cr.set_line_width(1.6 / scale);
                cr.move_to(x, y);
                cr.line_to(x, y + h);
                cr.stroke();
                var l = new Pango.Layout(engine.context());
                l.set_font_description(Pango.FontDescription.from_string("Liberation Sans Bold 6.5"));
                l.set_text(rc.name, -1);
                Pango.Rectangle ink, lg;
                l.get_extents(out ink, out lg);
                double tw = lg.width / (double) Pango.SCALE + 4;
                double th = lg.height / (double) Pango.SCALE + 1;
                cr.rectangle(x, y - th, tw, th);
                cr.fill();
                cr.set_source_rgb(1, 1, 1);
                cr.move_to(x + 2, y - th + 0.5);
                Pango.cairo_show_layout(cr, l);
            }
        }

        private void draw_selection(Cairo.Context cr, int index) {
            if (ed == null || !ed.has_selection) return;
            Pos a, b;
            ed.ordered(out a, out b);
            set_accent(cr, 0.3);
            foreach (var p in Story.between(doc, a, b)) {
                var list = lay.para_lines[p];
                if (list == null) continue;
                int s = p == a.para ? a.offset : 0;
                int e = p == b.para ? b.offset : p.length;
                int bs = list[0].pl.text.to_byte(s);
                int be = list[0].pl.text.to_byte(e);
                foreach (var lb in list) {
                    if (lb.page != index) continue;
                    if ((edit_region == Write.Region.HEADER || edit_region == Write.Region.FOOTER) != (lb.region == Write.Region.HEADER || lb.region == Write.Region.FOOTER)) continue;
                    int ls = int.max(bs, lb.info.start_byte);
                    int le = int.min(be, lb.info.end_byte);
                    if (le < ls || (le == ls && !(p != b.para && lb.last))) continue;
                    double x0 = lb.caret_x(ls);
                    double x1 = lb.caret_x(le);
                    if (p != b.para && lb.last && le >= lb.info.end_byte) x1 += 5;
                    cr.rectangle(x0, lb.top, double.max(1, x1 - x0), lb.height);
                    cr.fill();
                }
            }
        }

        private void draw_object_selection(Cairo.Context cr, int index) {
            if (selected_obj == null) return;
            var o = find_box(selected_obj.item);
            if (o == null || page_of_box(o) != index) return;
            set_accent(cr, 0.9);
            cr.set_line_width(1 / scale);
            cr.rectangle(o.x, o.y, o.w, o.h);
            cr.stroke();
            double hs = 4 / scale;
            double[] hx, hy;
            handles(o, out hx, out hy);
            for (int i = 0; i < 8; i++) {
                cr.rectangle(hx[i] - hs, hy[i] - hs, hs * 2, hs * 2);
                cr.set_source_rgb(1, 1, 1);
                cr.fill_preserve();
                set_accent(cr, 1);
                cr.stroke();
            }
            if (crop_mode) {
                cr.set_source_rgba(0, 0, 0, 0.8);
                cr.set_line_width(3 / scale);
                for (int i = 0; i < 8; i++) {
                    cr.move_to(hx[i] - 6 / scale, hy[i]);
                    cr.line_to(hx[i] + 6 / scale, hy[i]);
                }
                cr.stroke();
            }
        }

        private static void handles(ObjBox o, out double[] hx, out double[] hy) {
            hx = { o.x, o.x + o.w / 2, o.x + o.w, o.x + o.w, o.x + o.w, o.x + o.w / 2, o.x, o.x };
            hy = { o.y, o.y, o.y, o.y + o.h / 2, o.y + o.h, o.y + o.h, o.y + o.h, o.y + o.h / 2 };
        }

        private ObjBox? find_box(Inline item) {
            if (lay == null) return null;
            foreach (var p in lay.pages) foreach (var o in p.objects) if (o.item == item) return o;
            return null;
        }

        private int page_of_box(ObjBox o) {
            for (int i = 0; i < lay.pages.size; i++) if (lay.pages[i].objects.contains(o)) return i;
            return -1;
        }

        private void draw_spelling(Cairo.Context cr, PageBox p) {
            if (!spell_enabled && !grammar_enabled) return;
            if (read_only && mode == ViewMode.READ) return;
            var seen = new Gee.HashSet<Paragraph>();
            foreach (var lb in p.lines) {
                if (seen.contains(lb.para)) {
                    draw_spell_line(cr, lb);
                    continue;
                }
                seen.add(lb.para);
                ensure_spell(lb.para);
                draw_spell_line(cr, lb);
            }
        }

        private void draw_spell_line(Cairo.Context cr, LineBox lb) {
            var sc = spell[lb.para];
            if (sc == null) return;
            foreach (var r in sc.ranges) {
                if (r.grammar && !grammar_enabled) continue;
                if (!r.grammar && !spell_enabled) continue;
                int bs = lb.pl.text.to_byte(r.start);
                int be = lb.pl.text.to_byte(r.end);
                int ls = int.max(bs, lb.info.start_byte);
                int le = int.min(be, lb.info.end_byte);
                if (le <= ls) continue;
                double x0 = lb.caret_x(ls);
                double x1 = lb.caret_x(le);
                double y = lb.baseline + 2;
                if (r.grammar) {
                    set_accent(cr, 0.85);
                    cr.set_line_width(0.6);
                    cr.move_to(x0, y);
                    cr.line_to(x1, y);
                    cr.move_to(x0, y + 1.3);
                    cr.line_to(x1, y + 1.3);
                    cr.stroke();
                } else {
                    cr.set_source_rgba(0.85, 0.1, 0.1, 0.9);
                    cr.set_line_width(0.6);
                    double x = x0;
                    bool up = true;
                    cr.move_to(x, y);
                    while (x < x1) {
                        x += 1.5;
                        cr.line_to(double.min(x, x1), up ? y + 1.2 : y);
                        up = !up;
                    }
                    cr.stroke();
                }
            }
        }

        private void ensure_spell(Paragraph p) {
            var sc = spell[p];
            string lang = proofing_language();
            if (sc != null && sc.version == p.version && sc.lang == lang) return;
            sc = new SpellCache();
            sc.version = p.version;
            sc.lang = lang;
            spell[p] = sc;
            if (p.style.has_prefix("TOC") || p.style == "SourceCode") return;
            string t = p.text();
            if (spell_enabled) {
                var checker = Singularity.Text.SpellChecker.get_default();
                if (checker.enabled) {
                    int ci = 0;
                    int ws = -1;
                    var word = new StringBuilder();
                    unichar c;
                    int i = 0;
                    while (true) {
                        bool more = t.get_next_char(ref i, out c);
                        if (more && (c.isalpha() || (c == '\'' && word.len > 0) || c == 0x2019)) {
                            if (ws < 0) ws = ci;
                            word.append_unichar(c == 0x2019 ? '\'' : c);
                        } else if (ws >= 0) {
                            string w = word.str;
                            while (w.has_suffix("'")) w = w.substring(0, w.length - 1);
                            if (w.char_count() > 1 && !ignored.contains(w) && !is_link_at(p, ws) && !spell_checker_at(new Pos(p, ws)).check(w)) {
                                var r = new SpellRange();
                                r.start = ws;
                                r.end = ws + w.char_count();
                                sc.ranges.add(r);
                            }
                            ws = -1;
                            word.truncate(0);
                        }
                        if (!more) break;
                        ci++;
                    }
                }
            }
            if (grammar_enabled) {
                foreach (var issue in grammar.check(p, lang)) {
                    var r = new SpellRange();
                    r.start = issue.start;
                    r.end = issue.end;
                    r.grammar = true;
                    r.issue = issue;
                    sc.ranges.add(r);
                }
            }
        }

        private bool is_link_at(Paragraph p, int off) {
            var it = p.inline_at(off);
            return it != null && it.props.link != null;
        }

        private string proofing_language() {
            if (doc_lang != "") return doc_lang;
            if (doc.lang != "") return doc.lang;
            return Write.Hyphenator.default_lang();
        }

        public Singularity.Text.SpellChecker spell_checker_at(Pos p) {
            string? lang = p.para.inline_at(p.offset)?.props.lang;
            return Singularity.Text.SpellChecker.for_language(lang != null && lang != "" ? lang : proofing_language());
        }

        public Gee.HashSet<string> ignored = new Gee.HashSet<string>();

        public void refresh_spelling() {
            spell.clear();
            queue_draw();
        }

        public SpellRange? spell_at(Pos p) {
            ensure_spell(p.para);
            var sc = spell[p.para];
            if (sc == null) return null;
            foreach (var r in sc.ranges) if (p.offset >= r.start && p.offset <= r.end) return r;
            return null;
        }

        public Gee.ArrayList<Write.Issue> all_issues(bool with_spelling) {
            var list = new Gee.ArrayList<Write.Issue>();
            foreach (var p in Story.paragraphs(doc.body)) {
                ensure_spell(p);
                var sc = spell[p];
                if (sc == null) continue;
                foreach (var r in sc.ranges) {
                    if (r.grammar) list.add(r.issue);
                    else if (with_spelling) {
                        string word = usub(p.text(), r.start, r.end);
                        var issue = new Write.Issue(p, r.start, r.end, "spelling", _("Not in dictionary: \u201c%s\u201d").printf(word));
                        issue.suggestions = spell_checker_at(new Pos(p, r.start)).suggest(word, 6);
                        list.add(issue);
                    }
                }
            }
            return list;
        }

        private void on_motion(double x, double y) {
            if (lay == null) return;
            int pg;
            double px, py;
            to_page(x, y, out pg, out px, out py);
            if (pg < 0) return;
            string cursor = "text";
            string? tip = null;
            foreach (var o in lay.pages[pg].objects) {
                if (px >= o.x && px <= o.x + o.w && py >= o.y && py <= o.y + o.h && o.inner == null) {
                    cursor = selected_obj != null && selected_obj.item == o.item ? "move" : "default";
                    if (o.item is EquationRun) tip = _("Double-click to edit the equation");
                    break;
                }
            }
            if (selected_obj != null) {
                var o = find_box(selected_obj.item);
                if (o != null && page_of_box(o) == pg) {
                    double[] hx, hy;
                    handles(o, out hx, out hy);
                    string[] names = { "nwse-resize", "ns-resize", "nesw-resize", "ew-resize", "nwse-resize", "ns-resize", "nesw-resize", "ew-resize" };
                    for (int i = 0; i < 8; i++) if ((px - hx[i]).abs() * scale < 6 && (py - hy[i]).abs() * scale < 6) cursor = names[i];
                }
            }
            var pos = hit(pg, px, py);
            if (pos != null) {
                var it = pos.para.inline_at(pos.offset);
                if (it != null && it.props.link != null) {
                    tip = _("Ctrl+click to follow %s").printf(it.props.link);
                    cursor = "pointer";
                }
                var sr = spell_at(pos);
                if (sr != null && sr.grammar && sr.issue != null) tip = sr.issue.message;
            }
            set_cursor_from_name(cursor);
            tooltip_text = tip;
        }

        private void on_press(Gtk.GestureClick g, int n, double x, double y) {
            grab_focus();
            if (lay == null || ed == null) return;
            uint button = g.get_current_button();
            var state = g.get_current_event_state();
            bool shift = (state & Gdk.ModifierType.SHIFT_MASK) != 0;
            bool ctrl = (state & Gdk.ModifierType.CONTROL_MASK) != 0;
            int pg;
            double px, py;
            to_page(x, y, out pg, out px, out py);
            if (pg < 0) return;
            drag_x0 = px;
            drag_y0 = py;
            drag_mode = 0;
            press_count = n;
            if (show_comments && button == 1 && mode == ViewMode.PRINT && px > lay.pages[pg].width) {
                foreach (var e in comment_positions.entries) {
                    double by = e.value;
                    if (y >= by && y <= by + 60) {
                        active_comment = e.key;
                        comment_activated(e.key);
                        queue_draw();
                        return;
                    }
                }
            }
            if (selected_obj != null && button == 1) {
                var o = find_box(selected_obj.item);
                if (o != null && page_of_box(o) == pg) {
                    double[] hx, hy;
                    handles(o, out hx, out hy);
                    for (int i = 0; i < 8; i++) {
                        if ((px - hx[i]).abs() * scale < 7 && (py - hy[i]).abs() * scale < 7) {
                            begin_object_drag(o, 3, i);
                            return;
                        }
                    }
                }
            }
            foreach (var o in lay.pages[pg].objects) {
                if (!(px >= o.x && px <= o.x + o.w && py >= o.y && py <= o.y + o.h)) continue;
                if (o.inner != null && selected_obj != null && selected_obj.item == o.item) break;
                if (o.item is FloatingInline || o.item is EquationRun || o.item is OpaqueRun) {
                    if (n == 2 && o.item is EquationRun) {
                        edit_equation((EquationRun) o.item);
                        return;
                    }
                    if (n == 2 && o.inner != null) {
                        selected_obj = null;
                        break;
                    }
                    if (n == 2) {
                        edit_object(o.item);
                        return;
                    }
                    selected_obj = o;
                    crop_mode = false;
                    int off = o.para.offset_of(o.item);
                    if (off >= 0) ed.select(new Pos(o.para, off), new Pos(o.para, off + o.item.length));
                    begin_object_drag(o, 2, -1);
                    queue_draw();
                    selection_changed();
                    if (button == 3) context_menu(x, y);
                    return;
                }
            }
            selected_obj = null;
            crop_mode = false;
            var p = lay.pages[pg];
            if (n == 2 && mode == ViewMode.PRINT && !opts.draft) {
                bool in_header = py < p.body_top - 2;
                bool in_footer = py > p.body_bottom + 2 && !(p.notes.size > 0);
                if ((in_header || in_footer) && edit_region == Write.Region.BODY && !read_only) {
                    enter_header(pg, in_header);
                    return;
                }
                if (!in_header && !in_footer && edit_region != Write.Region.BODY) {
                    edit_region = Write.Region.BODY;
                    region_changed();
                    var bp = hit(pg, px, py);
                    if (bp != null) ed.set_caret(bp);
                    queue_draw();
                    return;
                }
            }
            if (outline_toggle(pg, px, py)) return;
            var pos = hit(pg, px, py);
            if (pos == null) return;
            if (button == 3) {
                if (!ed.has_selection || !in_selection(pos)) ed.set_caret(pos);
                context_menu(x, y);
                return;
            }
            if (ctrl && button == 1) {
                var it = pos.para.inline_at(pos.offset);
                if (it != null && it.props.link != null) {
                    open_link(it.props.link);
                    return;
                }
            }
            var ff = pos.para.inline_at(pos.offset) as FormField;
            if (ff != null && ff.kind == FormKind.CHECKBOX && button == 1 && (!read_only || doc.protection.kind == ProtectKind.FORMS)) {
                ed.checkpoint(_("Check Box"));
                ff.checked = !ff.checked;
                pos.para.touch();
                ed.changed();
                return;
            }
            pending = null;
            if (n == 1) {
                ed.set_caret(pos, shift);
                drag_mode = 1;
            } else if (n == 2) {
                int s, e;
                ed.word_at(pos, out s, out e);
                ed.select(new Pos(pos.para, s), new Pos(pos.para, e));
            } else {
                ed.select(new Pos(pos.para, 0), new Pos(pos.para, pos.para.length));
            }
        }

        private bool outline_toggle(int pg, double px, double py) {
            if (mode != ViewMode.OUTLINE) return false;
            foreach (var d in lay.pages[pg].decos) {
                if (!d.text.has_prefix("outline-") || d.text == "outline-body") continue;
                if (px >= d.x - 2 && px <= d.x + d.w + 2 && py >= d.y - 2 && py <= d.y + d.h + 2) {
                    var pos = hit(pg, d.x + d.w + 16, d.y + d.h / 2);
                    if (pos == null) return false;
                    if (engine.collapsed.contains(pos.para)) engine.collapsed.remove(pos.para);
                    else engine.collapsed.add(pos.para);
                    relayout_now();
                    return true;
                }
            }
            return false;
        }

        private bool in_selection(Pos p) {
            Pos a, b;
            ed.ordered(out a, out b);
            return Story.compare(doc, a, p) <= 0 && Story.compare(doc, p, b) <= 0;
        }

        public void enter_header(int pg, bool header) {
            var p = lay.pages[pg];
            var s = p.section;
            bool first = s.title_page && p.first_of_section;
            bool even = doc.even_odd_headers && p.number % 2 == 0;
            ed.checkpoint(_("Edit Header"));
            HeaderFooter hf;
            if (header) {
                if (first) hf = s.header_first ?? (s.header_first = new_hf("Header"));
                else if (even) hf = s.header_even ?? (s.header_even = new_hf("Header"));
                else hf = s.header_default ?? (s.header_default = new_hf("Header"));
            } else {
                if (first) hf = s.footer_first ?? (s.footer_first = new_hf("Footer"));
                else if (even) hf = s.footer_even ?? (s.footer_even = new_hf("Footer"));
                else hf = s.footer_default ?? (s.footer_default = new_hf("Footer"));
            }
            edit_region = header ? Write.Region.HEADER : Write.Region.FOOTER;
            edit_page = pg;
            relayout_now();
            var para = hf.blocks.first_paragraph();
            if (para != null) ed.set_caret(new Pos(para, para.length));
            region_changed();
            queue_draw();
        }

        private static HeaderFooter new_hf(string style) {
            var h = new HeaderFooter();
            h.blocks.add(new Paragraph(style));
            return h;
        }

        public void leave_header() {
            if (edit_region == Write.Region.BODY) return;
            edit_region = Write.Region.BODY;
            var first = doc.body.first_paragraph();
            if (lay != null && edit_page < lay.pages.size) {
                foreach (var lb in lay.pages[edit_page].lines) if (lb.region == Write.Region.BODY) {
                    first = lb.para;
                    break;
                }
            }
            if (first != null) ed.set_caret(new Pos(first, 0));
            region_changed();
            queue_draw();
        }

        private void on_release(Gtk.GestureClick g, int n, double x, double y) {
        }

        private void begin_object_drag(ObjBox o, int kind, int handle) {
            drag_mode = kind;
            drag_handle = handle;
            obj_x0 = o.x;
            obj_y0 = o.y;
            obj_w0 = o.w;
            obj_h0 = o.h;
            var img = o.item as ImageRun;
            if (img != null) {
                crop0_l = img.crop_l;
                crop0_t = img.crop_t;
                crop0_r = img.crop_r;
                crop0_b = img.crop_b;
            }
            drag_started = false;
        }

        private bool drag_started = false;

        private void on_drag_update(Gtk.GestureDrag g, double dx, double dy) {
            if (lay == null) return;
            double sx0, sy0;
            g.get_start_point(out sx0, out sy0);
            int pg;
            double px, py;
            to_page(sx0 + dx, sy0 + dy, out pg, out px, out py);
            if (drag_mode == 1) {
                var pos = hit(pg, px, py);
                if (pos != null) ed.set_caret(pos, true);
                return;
            }
            if ((drag_mode == 2 || drag_mode == 3) && selected_obj != null && !read_only) {
                if (!drag_started) {
                    ed.checkpoint(drag_mode == 2 ? _("Move Object") : _("Resize Object"));
                    drag_started = true;
                }
                double ddx = dx / scale;
                double ddy = dy / scale;
                var o = selected_obj;
                if (drag_mode == 2) {
                    o.x = obj_x0 + ddx;
                    o.y = obj_y0 + ddy;
                } else {
                    double nx = obj_x0, ny = obj_y0, nw = obj_w0, nh = obj_h0;
                    int hdl = drag_handle;
                    if (hdl == 0 || hdl == 6 || hdl == 7) {
                        nx = obj_x0 + ddx;
                        nw = obj_w0 - ddx;
                    }
                    if (hdl == 2 || hdl == 3 || hdl == 4) nw = obj_w0 + ddx;
                    if (hdl == 0 || hdl == 1 || hdl == 2) {
                        ny = obj_y0 + ddy;
                        nh = obj_h0 - ddy;
                    }
                    if (hdl == 4 || hdl == 5 || hdl == 6) nh = obj_h0 + ddy;
                    bool corner = hdl == 0 || hdl == 2 || hdl == 4 || hdl == 6;
                    var state = g.get_current_event_state();
                    bool free = (state & Gdk.ModifierType.SHIFT_MASK) != 0;
                    if (corner && !free && !crop_mode && obj_w0 > 0 && obj_h0 > 0 && (o.item is ImageRun || o.item is EquationRun)) {
                        double ratio = obj_h0 / obj_w0;
                        nh = nw * ratio;
                        if (hdl == 0 || hdl == 2) ny = obj_y0 + obj_h0 - nh;
                    }
                    o.x = nx;
                    o.y = ny;
                    o.w = double.max(6, nw);
                    o.h = double.max(6, nh);
                }
                queue_draw();
            }
        }

        private void end_object_drag() {
            if (!drag_started || selected_obj == null) return;
            drag_started = false;
            var o = selected_obj;
            var f = o.item as FloatingInline;
            if (drag_mode == 3) {
                if (crop_mode && o.item is ImageRun) {
                    var img = (ImageRun) o.item;
                    double fw = obj_w0 / double.max(0.001, 1 - crop0_l - crop0_r);
                    double fh = obj_h0 / double.max(0.001, 1 - crop0_t - crop0_b);
                    img.crop_l = (crop0_l + (o.x - obj_x0) / fw).clamp(0, 0.95);
                    img.crop_t = (crop0_t + (o.y - obj_y0) / fh).clamp(0, 0.95);
                    img.crop_r = (crop0_r - (o.x + o.w - obj_x0 - obj_w0) / fw).clamp(0, 0.95);
                    img.crop_b = (crop0_b - (o.y + o.h - obj_y0 - obj_h0) / fh).clamp(0, 0.95);
                    img.width = o.w;
                    img.height = o.h;
                } else if (f != null) {
                    f.width = o.w;
                    f.height = o.h;
                    if (f.floating()) {
                        f.hoff += o.x - obj_x0;
                        f.voff += o.y - obj_y0;
                        f.halign = HAlignObj.NONE;
                    }
                } else if (o.item is EquationRun) {
                    var e = (EquationRun) o.item;
                    double sc = o.h / double.max(1, obj_h0);
                    e.width *= sc;
                    e.ascent *= sc;
                    e.descent *= sc;
                } else if (o.item is OpaqueRun) {
                    ((OpaqueRun) o.item).width = o.w;
                    ((OpaqueRun) o.item).height = o.h;
                }
            } else if (drag_mode == 2) {
                if (f != null && f.floating()) {
                    f.hoff += o.x - obj_x0;
                    f.voff += o.y - obj_y0;
                    f.halign = HAlignObj.NONE;
                } else {
                    int pg;
                    double px, py;
                    double cx = (o.x - obj_x0) * scale;
                    double cy = (o.y - obj_y0) * scale;
                    int op = page_of_box(o);
                    double wx, wy;
                    page_to_widget(op, obj_x0 + o.w / 2, obj_y0 + o.h / 2, out wx, out wy);
                    to_page(wx + cx, wy + cy, out pg, out px, out py);
                    var target = hit(pg, px, py);
                    if (target != null && !(target.para == o.para && (target.offset - o.para.offset_of(o.item)).abs() <= 1)) {
                        o.para.inlines.remove(o.item);
                        o.para.normalize();
                        o.para.touch();
                        int off = target.offset;
                        if (target.para == o.para && off > o.para.length) off = o.para.length;
                        target.para.insert_inline(off, o.item);
                        target.para.touch();
                    }
                }
            }
            o.para.touch();
            ed.changed();
            relayout_now();
            var nb = find_box(o.item);
            selected_obj = nb;
        }

        private void on_commit(string text) {
            if (ed == null || !can_edit()) return;
            string t = text;
            if (t == "") return;
            var ac = Write.AutoCorrect.get_default();
            ed.checkpoint(_("Typing"), true);
            selected_obj = null;
            if (ac.smart_quotes && (t == "\"" || t == "'")) t = smart_quote(t);
            unichar c0 = t.get_char(0);
            bool boundary = c0 == ' ' || c0 == '.' || c0 == ',' || c0 == ';' || c0 == ':' || c0 == '!' || c0 == '?' || c0 == ')';
            if (boundary && !ed.has_selection) {
                if (c0 == ' ' && ac.auto_lists && try_auto_list()) return;
                apply_autocorrect();
                if (ac.auto_hyperlinks) auto_link();
            }
            var props = pending ?? ed.props_for_insert();
            ed.insert_text(t, props);
            typed(t);
            update_contents(Gtk.AccessibleTextContentChange.INSERT, 0, 0);
        }

        public bool can_edit() {
            if (read_only) return false;
            var k = doc.protection.enforced ? doc.protection.kind : ProtectKind.NONE;
            if (k == ProtectKind.READ_ONLY || k == ProtectKind.COMMENTS || k == ProtectKind.FORMS) return false;
            return true;
        }

        private string smart_quote(string q) {
            int off = ed.focus.offset;
            bool opening = true;
            if (off > 0) {
                string t = ed.focus.para.text();
                unichar pc = t.get_char(t.index_of_nth_char(off - 1));
                if (!(pc.isspace() || pc == '(' || pc == '[' || pc == '{' || pc == 0x2014 || pc == 0x2013)) opening = false;
            }
            string lang = doc_lang != "" ? doc_lang : doc.lang;
            if (q == "\"") {
                if (lang.has_prefix("it") || lang.has_prefix("fr")) return opening ? "\u00ab" : "\u00bb";
                if (lang.has_prefix("de")) return opening ? "\u201e" : "\u201c";
                return opening ? "\u201c" : "\u201d";
            }
            return opening ? "\u2018" : "\u2019";
        }

        private bool try_auto_list() {
            var p = ed.focus.para;
            if (ed.focus.offset != p.length) return false;
            string t = p.plain_text();
            bool bullet = t == "*" || t == "-" || t == "\u2022";
            bool number = t == "1." || t == "1)" || t == "a)" || t == "a.";
            if (!bullet && !number) return false;
            ed.select(new Pos(p, 0), new Pos(p, p.length));
            ed.delete_selection();
            ed.toggle_list(number);
            if (t.has_prefix("a")) {
                var pp = doc.styles.resolve_para(p);
                var d = doc.numbering.def_for(pp.num_id);
                if (d != null) d.levels[0].format = NumFormat.LOWER_LETTER;
            }
            return true;
        }

        private void apply_autocorrect() {
            var p = ed.focus.para;
            int off = ed.focus.offset;
            string before = usub(p.text(), 0, off);
            int remove;
            string insert;
            if (!Write.AutoCorrect.get_default().correct(before, out remove, out insert)) return;
            var props = p.props_at(off);
            ed.select(new Pos(p, off - remove), new Pos(p, off));
            ed.delete_selection();
            ed.insert_text(insert, props);
        }

        private void auto_link() {
            var p = ed.focus.para;
            int off = ed.focus.offset;
            string before = usub(p.text(), 0, off);
            int sp = before.last_index_of_char(' ');
            string word = before.substring(sp + 1);
            if (!(word.has_prefix("http://") || word.has_prefix("https://") || word.has_prefix("www.") || (word.contains("@") && word.contains(".") && !word.has_prefix("@")))) return;
            int n = word.char_count();
            string url = word.has_prefix("www.") ? "https://" + word : (word.contains("@") && !word.contains("://") ? "mailto:" + word : word);
            var saved = ed.focus.copy();
            ed.select(new Pos(p, off - n), new Pos(p, off));
            ed.format_chars((c) => {
                c.link = url;
                c.style = "Hyperlink";
            });
            ed.set_caret(saved);
        }

        private bool on_key(uint kv, uint code, Gdk.ModifierType state) {
            if (ed == null) return false;
            bool ctrl = (state & Gdk.ModifierType.CONTROL_MASK) != 0;
            bool shift = (state & Gdk.ModifierType.SHIFT_MASK) != 0;
            bool alt = (state & Gdk.ModifierType.ALT_MASK) != 0;
            restart_blink();
            if (kv == Gdk.Key.Escape) {
                if (selected_obj != null) {
                    selected_obj = null;
                    crop_mode = false;
                    queue_draw();
                    return true;
                }
                if (edit_region != Write.Region.BODY) {
                    leave_header();
                    return true;
                }
                return false;
            }
            switch (kv) {
                case Gdk.Key.Left:
                case Gdk.Key.KP_Left:
                    move_horizontal(-1, ctrl, shift);
                    return true;
                case Gdk.Key.Right:
                case Gdk.Key.KP_Right:
                    move_horizontal(1, ctrl, shift);
                    return true;
                case Gdk.Key.Up:
                case Gdk.Key.KP_Up:
                    if (ctrl && alt) return false;
                    if (ctrl) {
                        move_paragraph_edge(-1, shift);
                        return true;
                    }
                    move_vertical(-1, shift);
                    return true;
                case Gdk.Key.Down:
                case Gdk.Key.KP_Down:
                    if (ctrl && alt) return false;
                    if (ctrl) {
                        move_paragraph_edge(1, shift);
                        return true;
                    }
                    move_vertical(1, shift);
                    return true;
                case Gdk.Key.Home:
                case Gdk.Key.KP_Home:
                    if (ctrl) move_story_edge(-1, shift);
                    else move_line_edge(-1, shift);
                    return true;
                case Gdk.Key.End:
                case Gdk.Key.KP_End:
                    if (ctrl) move_story_edge(1, shift);
                    else move_line_edge(1, shift);
                    return true;
                case Gdk.Key.Page_Up:
                    move_page(-1, shift);
                    return true;
                case Gdk.Key.Page_Down:
                    move_page(1, shift);
                    return true;
                default:
                    break;
            }
            if (!can_edit()) return false;
            switch (kv) {
                case Gdk.Key.BackSpace:
                    if (selected_obj != null) {
                        delete_selected_object();
                        return true;
                    }
                    ed.checkpoint(_("Delete"), !ed.has_selection && !ctrl);
                    ed.delete_backward(ctrl);
                    return true;
                case Gdk.Key.Delete:
                case Gdk.Key.KP_Delete:
                    if (selected_obj != null) {
                        delete_selected_object();
                        return true;
                    }
                    ed.checkpoint(_("Delete"), !ed.has_selection && !ctrl);
                    ed.delete_forward(ctrl);
                    return true;
                case Gdk.Key.Return:
                case Gdk.Key.KP_Enter:
                    if (ctrl) return false;
                    ed.checkpoint(_("New Paragraph"));
                    ed.break_group();
                    if (shift) {
                        ed.insert_inline(new Break(BreakKind.LINE));
                        return true;
                    }
                    enter_key();
                    return true;
                case Gdk.Key.Tab:
                case Gdk.Key.ISO_Left_Tab:
                    if (ctrl) return false;
                    return tab_key(shift || kv == Gdk.Key.ISO_Left_Tab);
                default:
                    break;
            }
            return false;
        }

        private void enter_key() {
            var p = ed.focus.para;
            var pp = doc.styles.resolve_para(p);
            if (pp.num_id > 0 && p.is_empty() && !ed.has_selection) {
                if (pp.num_level > 0) ed.change_level(-1);
                else {
                    p.props.num_id = 0;
                    if (p.style == "ListParagraph") p.style = "Normal";
                    p.touch();
                    ed.changed();
                }
                return;
            }
            apply_autocorrect();
            ed.split_paragraph();
        }

        private bool tab_key(bool back) {
            var cell = ed.cell_at(ed.focus);
            if (cell != null) {
                var t = ed.table_at(ed.focus);
                if (t == null) return false;
                int r, c;
                t.locate_cell(cell, out r, out c);
                if (back) {
                    if (c > 0) c--;
                    else if (r > 0) {
                        r--;
                        c = t.rows[r].cells.size - 1;
                    }
                } else {
                    if (c + 1 < t.rows[r].cells.size) c++;
                    else if (r + 1 < t.rows.size) {
                        r++;
                        c = 0;
                    } else {
                        ed.checkpoint(_("Insert Row"));
                        ed.table_op("row-below");
                        r++;
                        c = 0;
                    }
                }
                var target = t.rows[r].cells[c].blocks.first_paragraph();
                var last = t.rows[r].cells[c].blocks.last_paragraph();
                if (target != null) ed.select(new Pos(target, 0), new Pos(last, last.length));
                return true;
            }
            var pp = doc.styles.resolve_para(ed.focus.para);
            if (pp.num_id > 0 && (ed.focus.offset == 0 || ed.has_selection)) {
                ed.checkpoint(_("Change List Level"));
                ed.change_level(back ? -1 : 1);
                return true;
            }
            if (back) return false;
            ed.checkpoint(_("Typing"), true);
            var tab = new Tab();
            tab.props = pending ?? ed.props_for_insert();
            ed.insert_inline(tab);
            return true;
        }

        private void delete_selected_object() {
            if (selected_obj == null) return;
            ed.checkpoint(_("Delete Object"));
            var o = selected_obj;
            if (doc.track_changes) {
                o.item.rev = ed.new_rev(RevKind.DELETE);
            } else {
                o.para.inlines.remove(o.item);
                o.para.normalize();
            }
            o.para.touch();
            selected_obj = null;
            ed.changed();
        }

        private Gee.ArrayList<Paragraph> story_paragraphs() {
            return Story.paragraphs(Story.root_of(doc, ed.focus.para));
        }

        private void move_horizontal(int dir, bool word, bool extend) {
            if (!extend && ed.has_selection) {
                Pos a, b;
                ed.ordered(out a, out b);
                ed.set_caret(dir < 0 ? a : b);
                return;
            }
            var p = ed.focus.para;
            int off = ed.focus.offset;
            if (dir < 0) {
                if (off > 0) {
                    off = word ? Editor.word_start(p, off) : off - 1;
                    ed.set_caret(new Pos(p, off), extend);
                    return;
                }
                var list = story_paragraphs();
                int i = list.index_of(p);
                if (i > 0) ed.set_caret(new Pos(list[i - 1], list[i - 1].length), extend);
            } else {
                if (off < p.length) {
                    off = word ? Editor.word_end(p, off) : off + 1;
                    ed.set_caret(new Pos(p, off), extend);
                    return;
                }
                var list = story_paragraphs();
                int i = list.index_of(p);
                if (i >= 0 && i + 1 < list.size) ed.set_caret(new Pos(list[i + 1], 0), extend);
            }
        }

        private void move_paragraph_edge(int dir, bool extend) {
            var p = ed.focus.para;
            if (dir < 0) {
                if (ed.focus.offset > 0) {
                    ed.set_caret(new Pos(p, 0), extend);
                    return;
                }
                var list = story_paragraphs();
                int i = list.index_of(p);
                if (i > 0) ed.set_caret(new Pos(list[i - 1], 0), extend);
            } else {
                var list = story_paragraphs();
                int i = list.index_of(p);
                if (i >= 0 && i + 1 < list.size) ed.set_caret(new Pos(list[i + 1], 0), extend);
                else ed.set_caret(new Pos(p, p.length), extend);
            }
        }

        private void move_story_edge(int dir, bool extend) {
            var list = story_paragraphs();
            if (list.size == 0) return;
            if (dir < 0) ed.set_caret(new Pos(list[0], 0), extend);
            else ed.set_caret(new Pos(list[list.size - 1], list[list.size - 1].length), extend);
        }

        private void move_line_edge(int dir, bool extend) {
            var lb = line_for(ed.focus);
            if (lb == null) return;
            int b = dir < 0 ? lb.info.start_byte : lb.info.end_byte;
            if (dir > 0 && !lb.last && b > lb.info.start_byte) {
                string t = lb.pl.text.text;
                int prev = b;
                while (prev > lb.info.start_byte) {
                    prev--;
                    if ((t[prev] & 0xC0) != 0x80) break;
                }
                unichar c = t.get_char(prev);
                if (c == ' ' || c == 0x2028 || c == 0xAD) b = prev;
            }
            ed.set_caret(new Pos(lb.para, lb.pl.text.byte_to_model(b)), extend);
        }

        private void move_vertical(int dir, bool extend) {
            var lb = line_for(ed.focus);
            if (lb == null) return;
            double x = lb.caret_x(lb.pl.text.to_byte(ed.focus.offset));
            if (goal_x < 0) goal_x = x;
            double keep_goal = goal_x;
            var lines = page_lines(lb.page);
            LineBox? best = null;
            double best_y = dir > 0 ? double.MAX : -double.MAX;
            foreach (var c in lines) {
                if (c == lb) continue;
                bool cand = dir > 0 ? c.top >= lb.top + lb.height - 0.5 : c.top + c.height <= lb.top + 0.5;
                if (!cand) continue;
                if (!(keep_goal >= c.clip_x0 - 2 && keep_goal <= c.clip_x1 + 2)) continue;
                if ((c.region == Write.Region.FRAME) != (lb.region == Write.Region.FRAME)) continue;
                if (dir > 0 ? c.top < best_y : c.top > best_y) {
                    best_y = c.top;
                    best = c;
                }
            }
            if (best == null) {
                var list = lay.para_lines[lb.para];
                var story = story_paragraphs();
                int pi = story.index_of(lb.para);
                Paragraph? np = null;
                if (list != null) {
                    int li = list.index_of(lb);
                    if (dir > 0 && li + 1 < list.size) best = list[li + 1];
                    else if (dir < 0 && li > 0) best = list[li - 1];
                }
                if (best == null) {
                    if (dir > 0 && pi + 1 < story.size) np = story[pi + 1];
                    else if (dir < 0 && pi > 0) np = story[pi - 1];
                    if (np != null) {
                        var nl = lay.para_lines[np];
                        if (nl != null && nl.size > 0) best = dir > 0 ? nl[0] : nl[nl.size - 1];
                    }
                }
            }
            if (best == null) {
                if (dir > 0) move_line_edge(1, extend);
                else move_line_edge(-1, extend);
                return;
            }
            int b = best.hit(keep_goal);
            ed.set_caret(new Pos(best.para, best.pl.text.byte_to_model(b)), extend);
            goal_x = keep_goal;
        }

        private void move_page(int dir, bool extend) {
            int pg;
            double x, y, h;
            if (!caret_rect(ed.focus, out pg, out x, out y, out h)) return;
            double wx, wy;
            page_to_widget(pg, x, y, out wx, out wy);
            double delta = get_height() * 0.9 * dir;
            if (_vadj != null) _vadj.value = (_vadj.value + delta).clamp(0, double.max(0, _vadj.upper - _vadj.page_size));
            int npg;
            double px, py;
            to_page(wx, wy + (_vadj != null ? 0 : delta), out npg, out px, out py);
            var pos = hit(npg, px, py);
            if (pos != null) ed.set_caret(pos, extend);
        }

        public Gdk.Rectangle caret_widget_rect() {
            var r = Gdk.Rectangle();
            int pg = 0;
            double x = 0, y = 0, h = 0;
            if (ed == null || !caret_rect(ed.focus, out pg, out x, out y, out h)) return r;
            double wx, wy;
            page_to_widget(pg, x, y, out wx, out wy);
            r.x = (int) wx;
            r.y = (int) wy;
            r.width = 1;
            r.height = (int) (h * scale);
            return r;
        }

        private string flat_text() {
            var sb = new StringBuilder();
            foreach (var p in Story.paragraphs(doc.body)) {
                sb.append(p.plain_text());
                sb.append_c('\n');
            }
            return sb.str;
        }

        private uint global_offset(Pos p) {
            uint off = 0;
            foreach (var q in Story.paragraphs(doc.body)) {
                if (q == p.para) return off + (uint) p.offset;
                off += (uint) q.plain_text().char_count() + 1;
            }
            return 0;
        }

        public Bytes get_contents(uint start, uint end) {
            string t = flat_text();
            int n = t.char_count();
            int s = (int) uint.min(start, n);
            int e = end == uint.MAX ? n : (int) uint.min(end, n);
            return new Bytes(usub(t, s, e).data);
        }

        public Bytes get_contents_at(uint offset, Gtk.AccessibleTextGranularity granularity, out uint start, out uint end) {
            string t = flat_text();
            int n = t.char_count();
            int o = (int) uint.min(offset, n);
            int s = o, e = o;
            switch (granularity) {
                case Gtk.AccessibleTextGranularity.CHARACTER:
                    e = int.min(n, o + 1);
                    break;
                case Gtk.AccessibleTextGranularity.WORD:
                    while (s > 0 && !t.get_char(t.index_of_nth_char(s - 1)).isspace()) s--;
                    while (e < n && !t.get_char(t.index_of_nth_char(e)).isspace()) e++;
                    break;
                default:
                    while (s > 0 && t.get_char(t.index_of_nth_char(s - 1)) != '\n') s--;
                    while (e < n && t.get_char(t.index_of_nth_char(e)) != '\n') e++;
                    break;
            }
            start = s;
            end = e;
            return new Bytes(usub(t, s, e).data);
        }

        public uint get_caret_position() {
            if (ed == null) return 0;
            return global_offset(ed.focus);
        }

        public bool get_selection(out Gtk.AccessibleTextRange[] ranges) {
            ranges = {};
            if (ed == null || !ed.has_selection) return false;
            Pos a, b;
            ed.ordered(out a, out b);
            var r = Gtk.AccessibleTextRange();
            uint ga = global_offset(a);
            r.start = ga;
            r.length = global_offset(b) - ga;
            ranges = { r };
            return true;
        }

        public bool get_accessible_text_attributes(uint offset, out Gtk.AccessibleTextRange[] ranges, out string[] attribute_names, out string[] attribute_values) {
            ranges = {};
            attribute_names = {};
            attribute_values = {};
            return false;
        }
    }
}
