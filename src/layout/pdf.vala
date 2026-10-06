namespace Write {

    public class PdfExport : Object {
        public Document doc;
        public ViewOptions opts;
        public string filename = "";

        public PdfExport(Document doc) {
            this.doc = doc;
            opts = new ViewOptions();
            opts.print = true;
            opts.markup = ViewMarkup.FINAL;
            opts.field_shading = false;
            opts.hyphenate = doc.hyphenate;
        }

        public DocLayout layout(out LayoutEngine engine) {
            engine = new LayoutEngine(doc, opts);
            engine.filename = filename;
            return engine.run();
        }

        public void write_file(string path) throws Error {
            LayoutEngine engine;
            var lay = layout(out engine);
            if (lay.pages.size == 0) throw new FormatError.INVALID(_("The document has no pages."));
            var first = lay.pages[0];
            var surface = new Cairo.PdfSurface(path, first.width, first.height);
            render(surface, lay, engine);
            surface.finish();
            if (surface.status() != Cairo.Status.SUCCESS) throw new IOError.FAILED(_("Could not write the PDF file."));
        }

        private void render(Cairo.PdfSurface surface, DocLayout lay, LayoutEngine engine) {
            var m = doc.meta;
            if (m.title != "") surface.set_metadata(Cairo.PdfMetadata.TITLE, m.title);
            if (m.author != "") surface.set_metadata(Cairo.PdfMetadata.AUTHOR, m.author);
            if (m.subject != "") surface.set_metadata(Cairo.PdfMetadata.SUBJECT, m.subject);
            if (m.keywords != "") surface.set_metadata(Cairo.PdfMetadata.KEYWORDS, m.keywords);
            surface.set_metadata(Cairo.PdfMetadata.CREATOR, "Singularity Write");
            surface.set_metadata(Cairo.PdfMetadata.CREATE_DATE, new DateTime.now_local().format("%Y-%m-%dT%H:%M:%S%:z"));
            var cr = new Cairo.Context(surface);
            var renderer = new Renderer(doc, opts, engine.context());
            renderer.tagged = true;
            int[] parents = new int[10];
            for (int i = 0; i < 10; i++) parents[i] = 0;
            for (int i = 0; i < lay.pages.size; i++) {
                var p = lay.pages[i];
                surface.set_size(p.width, p.height);
                cr.tag_begin("Document", "");
                draw_tagged(cr, renderer, p);
                cr.tag_end("Document");
                foreach (var lb in p.lines) {
                    if (lb.region != Region.BODY || !lb.first) continue;
                    int level = doc.styles.outline_level(lb.para);
                    if (level < 0 || level > 8 || !lb.para.style.has_prefix("Heading")) continue;
                    string title = lb.para.plain_text().strip();
                    if (title == "") continue;
                    int parent = level > 0 ? parents[level - 1] : 0;
                    int id = surface.add_outline(parent, title, "page=%d pos=[%s %s]".printf(i + 1, X.num(lb.x), X.num(lb.top)), 0);
                    parents[level] = id;
                    for (int k = level + 1; k < 10; k++) parents[k] = id;
                }
                add_links(cr, p);
                cr.show_page();
            }
        }

        private void draw_tagged(Cairo.Context cr, Renderer r, PageBox p) {
            cr.save();
            cr.set_source_rgb(1, 1, 1);
            r.draw_page(cr, p);
            cr.restore();
        }

        private void add_links(Cairo.Context cr, PageBox p) {
            foreach (var lb in p.lines) {
                int off = 0;
                foreach (var item in lb.para.inlines) {
                    int len = item.length;
                    string? link = item.props.link;
                    if (link != null && link != "" && len > 0) {
                        int b0 = lb.pl.text.to_byte(off);
                        int b1 = lb.pl.text.to_byte(off + len);
                        if (b1 > lb.info.start_byte && b0 < lb.info.end_byte) {
                            double x0 = lb.caret_x(int.max(b0, lb.info.start_byte));
                            double x1 = lb.caret_x(int.min(b1, lb.info.end_byte));
                            string attrs;
                            if (link.has_prefix("#")) attrs = "dest='%s' rect=[%s %s %s %s]".printf(link.substring(1).replace("'", ""), X.num(x0), X.num(lb.top), X.num(x1 - x0), X.num(lb.height));
                            else attrs = "uri='%s' rect=[%s %s %s %s]".printf(link.replace("'", "%27"), X.num(x0), X.num(lb.top), X.num(x1 - x0), X.num(lb.height));
                            cr.tag_begin("Link", attrs);
                            cr.tag_end("Link");
                        }
                    }
                    if (item is Mark && ((Mark) item).kind == MarkKind.BOOKMARK_START && lb.first) {
                        cr.tag_begin("cairo.dest", "name='%s' x=%s y=%s".printf(((Mark) item).name.replace("'", ""), X.num(lb.x), X.num(lb.top)));
                        cr.tag_end("cairo.dest");
                    }
                    off += len;
                }
            }
        }

        public static void render_png(Document doc, int page_index, string path, double scale) throws Error {
            var opts = new ViewOptions();
            opts.print = true;
            var engine = new LayoutEngine(doc, opts);
            var lay = engine.run();
            if (page_index >= lay.pages.size) throw new IOError.FAILED("no such page");
            var p = lay.pages[page_index];
            var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, (int) (p.width * scale), (int) (p.height * scale));
            var cr = new Cairo.Context(surface);
            cr.scale(scale, scale);
            new Renderer(doc, opts, engine.context()).draw_page(cr, p);
            surface.write_to_png(path);
        }
    }
}
