using GLib;
using Gtk;

namespace Pdf {

    // Loads a PDF and renders each page on demand. Read-only.
    public class Reader : Object {
        public Poppler.Document? document = null;
        public string path = "";

        public bool load(string file_path) {
            try {
                document = new Poppler.Document.from_file(GLib.Filename.to_uri(file_path), null);
                path     = file_path;
                return true;
            } catch (Error e) {
                warning("Pdf.Reader: failed to open %s: %s", file_path, e.message);
                return false;
            }
        }

        public int page_count {
            get { return document != null ? document.get_n_pages() : 0; }
        }

        public Gdk.Texture? render_page(int index, double dpi = 120.0) {
            if (document == null) return null;
            if (index < 0 || index >= document.get_n_pages()) return null;

            var page = document.get_page(index);
            double w_pt, h_pt;
            page.get_size(out w_pt, out h_pt);
            double scale = dpi / 72.0;
            int w = (int)(w_pt * scale);
            int h = (int)(h_pt * scale);
            if (w <= 0 || h <= 0) return null;

            var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, w, h);
            var cr      = new Cairo.Context(surface);
            cr.scale(scale, scale);
            cr.set_source_rgb(1.0, 1.0, 1.0);
            cr.paint();
            page.render(cr);
            surface.flush();

            unowned uint8[] raw = surface.get_data();
            int stride = surface.get_stride();
            // Copy because the ImageSurface owns the buffer.
            uint8[] copy = new uint8[h * stride];
            Memory.copy(copy, raw, copy.length);
            var bytes = new GLib.Bytes.take((owned) copy);
            return new Gdk.MemoryTexture(w, h, Gdk.MemoryFormat.B8G8R8A8_PREMULTIPLIED, bytes, stride);
        }
    }

    // Read-only paginated viewer. One Gtk.Picture per page inside a scroll.
    // We extend Box (not ScrolledWindow) because GtkScrolledWindow is final in GTK4.
    public class Viewer : Box {
        private Reader         reader;
        private ScrolledWindow scroll;
        private Box            pages_box;
        private string         loaded_path = "";

        public Viewer() {
            Object(orientation: Orientation.VERTICAL, spacing: 0);
            hexpand = true;
            vexpand = true;
            add_css_class("write-pdf-viewer");

            scroll = new ScrolledWindow();
            scroll.hexpand = true;
            scroll.vexpand = true;
            scroll.hscrollbar_policy = PolicyType.AUTOMATIC;
            scroll.vscrollbar_policy = PolicyType.AUTOMATIC;

            pages_box = new Box(Orientation.VERTICAL, 16);
            pages_box.margin_top    = 16;
            pages_box.margin_bottom = 16;
            pages_box.margin_start  = 16;
            pages_box.margin_end    = 16;
            pages_box.halign        = Align.CENTER;
            scroll.set_child(pages_box);
            append(scroll);

            reader = new Reader();
        }

        public bool load(string path) {
            Widget? c = pages_box.get_first_child();
            while (c != null) { var n = c.get_next_sibling(); pages_box.remove(c); c = n; }

            if (!reader.load(path)) return false;
            loaded_path = path;

            for (int i = 0; i < reader.page_count; i++) {
                var tex = reader.render_page(i, 120.0);
                if (tex == null) continue;
                int px_w = tex.width;
                int px_h = tex.height;
                // Display at 50% of the render so HiDPI looks crisp.
                var pic = new Picture.for_paintable(tex);
                pic.content_fit       = ContentFit.CONTAIN;
                pic.can_shrink        = false;
                pic.set_size_request(px_w / 2, px_h / 2);
                pic.add_css_class("write-pdf-page");
                pages_box.append(pic);
            }
            return true;
        }
    }

    // Paginated PDF export of a Gtk.TextBuffer via cairo. Plain text for now;
    // future iterations can preserve TextTag attributes.
    public class Writer : Object {

        public double page_width_pt   = 595.276;  // A4 width
        public double page_height_pt  = 841.89;   // A4 height
        public double margin_left_pt  = 72.0;     // ~25.4 mm
        public double margin_right_pt = 72.0;
        public double margin_top_pt   = 72.0;
        public double margin_bot_pt   = 72.0;
        public string font_family     = "Serif";
        public int    font_size_pt    = 11;

        public bool save(string path, Gtk.TextBuffer buffer) {
            var surface = new Cairo.PdfSurface(path, page_width_pt, page_height_pt);
            var cr      = new Cairo.Context(surface);
            var layout  = Pango.cairo_create_layout(cr);

            double text_w = page_width_pt - margin_left_pt - margin_right_pt;
            layout.set_width((int)(text_w * Pango.SCALE));
            layout.set_wrap(Pango.WrapMode.WORD_CHAR);

            var font = new Pango.FontDescription();
            font.set_family(font_family);
            font.set_size(font_size_pt * Pango.SCALE);
            layout.set_font_description(font);

            Gtk.TextIter s, e;
            buffer.get_bounds(out s, out e);
            string content = buffer.get_text(s, e, false);
            if (content.length == 0) content = " ";
            layout.set_text(content, -1);

            double cursor_y = margin_top_pt;
            double bottom   = page_height_pt - margin_bot_pt;
            bool   first    = true;

            Pango.LayoutIter it = layout.get_iter();
            do {
                Pango.Rectangle ink, log;
                it.get_line_extents(out ink, out log);
                double line_h = log.height / (double)Pango.SCALE;

                if (cursor_y + line_h > bottom && !first) {
                    cr.show_page();
                    cursor_y = margin_top_pt;
                }
                cr.set_source_rgb(0, 0, 0);
                cr.move_to(margin_left_pt, cursor_y);
                Pango.cairo_show_layout_line(cr, it.get_line_readonly());
                cursor_y += line_h;
                first = false;
            } while (it.next_line());

            surface.finish();
            return true;
        }
    }
}
