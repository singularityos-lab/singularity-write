using Write;

namespace Singularity.Apps {

    public class WritePageSource : Singularity.Print.PageSource {
        private Write.Document doc;
        private Write.DocLayout? lay = null;
        private Write.LayoutEngine? engine = null;
        private Write.ViewOptions opts;
        private Singularity.Print.PageFormat format = new Singularity.Print.PageFormat();
        public bool with_markup = false;
        public string filename = "";

        public WritePageSource(Write.Document doc, string title) {
            this.doc = doc;
            this.title = title;
            opts = new Write.ViewOptions();
            opts.print = true;
            opts.field_shading = false;
            opts.markup = Write.ViewMarkup.FINAL;
            opts.hyphenate = doc.hyphenate;
        }

        public override bool can_reflow {
            get { return true; }
        }

        public override async int paginate(Singularity.Print.PageFormat f) throws Error {
            format = f;
            page_width = f.width;
            page_height = f.height;
            opts.markup = with_markup ? Write.ViewMarkup.ALL : Write.ViewMarkup.FINAL;
            Write.Document source = doc;
            if (print_selection && has_selection && selection_doc != null) source = selection_doc;
            engine = new Write.LayoutEngine(source, opts);
            engine.filename = filename;
            lay = engine.run();
            document_pages = lay.pages.size;
            return lay.pages.size;
        }

        public Write.Document? selection_doc = null;

        public override void render_page(Cairo.Context cr, int index) {
            if (lay == null || index < 0 || index >= lay.pages.size) return;
            var p = lay.pages[index];
            double sx = page_width / p.width;
            double sy = page_height / p.height;
            double s = double.min(sx, sy);
            if ((s - 1).abs() < 0.02) s = 1;
            cr.save();
            cr.translate((page_width - p.width * s) / 2, (page_height - p.height * s) / 2);
            cr.scale(s, s);
            var r = new Write.Renderer(lay == null ? doc : doc, opts, engine.context());
            r.draw_page(cr, p);
            cr.restore();
        }
    }

    public class EquationSupport : Object {

        public static void setup() {
            if (Singularity.Equations.Equation.editor_available()) return;
            try {
                string exe = FileUtils.read_link("/proc/self/exe");
                string dev = Path.build_filename(Path.get_dirname(Path.get_dirname(exe)), "singularity-formula", "singularity-formula");
                if (FileUtils.test(dev, FileTest.IS_EXECUTABLE)) Environment.set_variable("SINGULARITY_EQUATION_HELPER", dev, false);
            } catch (Error e) {
            }
        }

        public static bool available() {
            setup();
            return Singularity.Equations.Equation.editor_available();
        }

        public static Singularity.Equations.Equation to_equation(Write.EquationRun e) {
            Singularity.Equations.Equation? eq = null;
            if (e.mathml != "") eq = new Singularity.Equations.Equation.from_mathml(e.mathml);
            else if (e.omml != null) eq = Singularity.Equations.Equation.from_omml(e.omml);
            if (eq == null) eq = new Singularity.Equations.Equation.from_latex(e.latex);
            eq.display = e.display;
            eq.numbered = e.numbered;
            if (e.label != null) eq.label = e.label;
            return eq;
        }

        public static async bool render(Write.EquationRun e, double size_pt, double column_pt = 0) {
            if (!available()) return false;
            var eq = to_equation(e);
            if (column_pt > 0) eq.max_width_pt = column_pt;
            double scale = 3;
            if (!(yield eq.render(size_pt, scale))) return false;
            var tex = eq.texture;
            if (tex == null) return false;
            e.preview = tex.save_to_png_bytes();
            e.width = eq.width_pt;
            e.ascent = eq.ascent_pt;
            e.descent = eq.descent_pt;
            if (e.mathml == "") e.mathml = eq.mathml;
            return true;
        }

        public static async bool edit(Write.EquationRun e, Gtk.Window? parent) {
            if (!available()) return false;
            var eq = to_equation(e);
            if (!(yield eq.edit(parent))) return false;
            e.mathml = eq.mathml;
            e.latex = eq.latex;
            e.omml = null;
            e.preview = null;
            return true;
        }

        public static async void render_all(Write.Document doc, owned GLib.SourceFunc? done) {
            if (!available()) return;
            foreach (var p in Write.Story.all(doc)) {
                foreach (var i in p.inlines) {
                    var e = i as Write.EquationRun;
                    if (e == null || e.preview != null) continue;
                    var c = doc.styles.resolve_char(p, e.props);
                    var sec = doc.section_for(p);
                    if (yield render(e, c.size > 0 ? c.size : 11, sec != null ? sec.column_width() : 0)) p.touch();
                }
            }
            if (done != null) done();
        }
    }
}
