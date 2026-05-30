using GLib;

namespace Odt {

    // ── Pending widget helper (images and tables inserted as child anchors) ──────

    private class PendingWidget : Object {
        public Gtk.TextChildAnchor anchor;
        public Gtk.Widget          widget;
        public PendingWidget(Gtk.TextChildAnchor a, Gtk.Widget w) {
            anchor = a;
            widget = w;
        }
    }

    // ── Public API ──────────────────────────────────────────────────────────────

    public class Document : Object {

        public bool load(string path, Gtk.TextBuffer buffer, Gtk.TextView tv) {
            string tmp = make_tmp_dir();
            if (tmp == "") {
                warning("odt.load: failed to create tmp dir");
                return false;
            }

            if (!run({"unzip", "-q", "-o", path, "-d", tmp})) {
                warning("odt.load: unzip failed for %s", path);
                cleanup(tmp);
                return false;
            }

            string xml = "";
            try {
                FileUtils.get_contents(tmp + "/content.xml", out xml);
            } catch (Error e) {
                warning("odt.load: failed to read content.xml: %s", e.message);
                cleanup(tmp);
                return false;
            }

            // Read styles.xml (named styles with numeric WPS names, etc.)
            string styles_xml = "";
            try { FileUtils.get_contents(tmp + "/styles.xml", out styles_xml); } catch {}

            buffer.set_text("", 0);
            var auto_styles = new AutoStyles();
            if (styles_xml != "") auto_styles.parse_styles_xml(styles_xml);
            auto_styles.parse(xml);
            auto_styles.resolve();
            var parser = new ContentXmlParser(buffer, tmp, auto_styles);
            parser.parse(xml);

            // Apply pending widgets (images, tables) to the TextView BEFORE cleanup
            foreach (var pw in parser.pending_widgets)
                tv.add_child_at_anchor(pw.widget, pw.anchor);

            cleanup(tmp);
            return true;
        }

        public bool save(string path, Gtk.TextBuffer buffer) {
            string tmp = make_tmp_dir();
            if (tmp == "") return false;

            DirUtils.create(tmp + "/META-INF", 0755);
            DirUtils.create(tmp + "/Pictures", 0755);

            // Compute word count for metadata
            Gtk.TextIter si, ei;
            buffer.get_start_iter(out si);
            buffer.get_end_iter(out ei);
            string all_text = buffer.get_text(si, ei, false);
            int word_count = 0;
            foreach (var w in all_text.split_set(" \t\n\r"))
                if (w.strip() != "") word_count++;

            string author = GLib.Environment.get_real_name();
            if (author == "" || author == "Unknown")
                author = GLib.Environment.get_user_name();
            var dt = new GLib.DateTime.now_local();
            string date_str = dt.format("%Y-%m-%dT%H:%M:%S");

            string meta_xml = """<?xml version="1.0" encoding="UTF-8"?>
<office:document-meta
  xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
  xmlns:meta="urn:oasis:names:tc:opendocument:xmlns:meta:1.0"
  xmlns:dc="http://purl.org/dc/elements/1.1/"
  office:version="1.3">
 <office:meta>
  <dc:creator>%s</dc:creator>
  <dc:date>%s</dc:date>
  <meta:document-statistic meta:word-count="%d"/>
 </office:meta>
</office:document-meta>""".printf(Markup.escape_text(author), date_str, word_count);

            try {
                FileUtils.set_contents(tmp + "/mimetype",
                    "application/vnd.oasis.opendocument.text");
                FileUtils.set_contents(tmp + "/META-INF/manifest.xml", MANIFEST_XML);
                FileUtils.set_contents(tmp + "/styles.xml", build_styles_xml());
                FileUtils.set_contents(tmp + "/meta.xml", meta_xml);
                var serial = new ContentXmlSerializer(buffer, tmp);
                FileUtils.set_contents(tmp + "/content.xml", serial.serialize());
            } catch {
                cleanup(tmp);
                return false;
            }

            // Remove old file
            FileUtils.unlink(path);

            // Build ODT ZIP: mimetype MUST be first and uncompressed
            string q_tmp  = GLib.Shell.quote(tmp);
            string q_path = GLib.Shell.quote(path);
            string cmd = "cd %s && zip -0 %s mimetype && zip -r -9 %s META-INF content.xml styles.xml meta.xml Pictures 2>/dev/null"
                .printf(q_tmp, q_path, q_path);
            bool ok = run({"bash", "-c", cmd});

            cleanup(tmp);
            return ok;
        }

        // ── Helpers ─────────────────────────────────────────────────────────────

        private string make_tmp_dir() {
            try {
                return DirUtils.make_tmp("singularity-write-XXXXXX");
            } catch {
                return "";
            }
        }

        private void cleanup(string dir) {
            run({"rm", "-rf", dir});
        }

        private bool run(string[] argv) {
            try {
                var proc = new Subprocess.newv(argv,
                    SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE);
                proc.wait();
                return proc.get_if_exited() && proc.get_exit_status() == 0;
            } catch {
                return false;
            }
        }

        private const string MANIFEST_XML = """<?xml version="1.0" encoding="UTF-8"?>
<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0"
  manifest:version="1.3">
 <manifest:file-entry manifest:full-path="/" manifest:version="1.3"
   manifest:media-type="application/vnd.oasis.opendocument.text"/>
 <manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>
 <manifest:file-entry manifest:full-path="styles.xml"  manifest:media-type="text/xml"/>
 <manifest:file-entry manifest:full-path="meta.xml"    manifest:media-type="text/xml"/>
</manifest:manifest>""";

        private string build_styles_xml() {
            return """<?xml version="1.0" encoding="UTF-8"?>
<office:document-styles
  xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
  xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0"
  xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
  xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"
  office:version="1.3">
 <office:styles>
  <style:default-style style:family="paragraph">
   <style:paragraph-properties fo:margin-bottom="3mm"/>
   <style:text-properties fo:font-size="12pt" fo:font-family="Liberation Serif"/>
  </style:default-style>
  <style:style style:name="Text_Body" style:family="paragraph">
   <style:text-properties fo:font-size="12pt"/>
  </style:style>
  <style:style style:name="Heading_1" style:family="paragraph">
   <style:text-properties fo:font-size="24pt" fo:font-weight="bold"/>
   <style:paragraph-properties fo:margin-top="6mm" fo:margin-bottom="3mm"/>
  </style:style>
  <style:style style:name="Heading_2" style:family="paragraph">
   <style:text-properties fo:font-size="20pt" fo:font-weight="bold"/>
   <style:paragraph-properties fo:margin-top="5mm" fo:margin-bottom="2mm"/>
  </style:style>
  <style:style style:name="Heading_3" style:family="paragraph">
   <style:text-properties fo:font-size="16pt" fo:font-weight="bold"/>
   <style:paragraph-properties fo:margin-top="4mm" fo:margin-bottom="2mm"/>
  </style:style>
  <style:style style:name="Heading_4" style:family="paragraph">
   <style:text-properties fo:font-size="14pt" fo:font-weight="600"/>
  </style:style>
  <style:style style:name="Quotations" style:family="paragraph">
   <style:text-properties fo:font-style="italic" fo:color="#888888"/>
   <style:paragraph-properties fo:margin-left="10mm"/>
  </style:style>
  <style:style style:name="Preformatted_Text" style:family="paragraph">
   <style:text-properties fo:font-family="Liberation Mono" fo:font-size="10pt"/>
  </style:style>
  <style:style style:name="List_Bullet" style:family="paragraph">
   <style:paragraph-properties fo:margin-left="10mm" fo:text-indent="-5mm"/>
  </style:style>
  <style:style style:name="List_Number" style:family="paragraph">
   <style:paragraph-properties fo:margin-left="10mm" fo:text-indent="-5mm"/>
  </style:style>
  <text:list-style style:name="L_bullet">
   <text:list-level-style-bullet text:level="1" text:bullet-char="&#x2022;">
    <style:list-level-properties text:space-before="5mm" text:min-label-width="5mm"/>
   </text:list-level-style-bullet>
  </text:list-style>
  <text:list-style style:name="L_numbered">
   <text:list-level-style-number text:level="1" style:num-format="1" style:num-suffix=".">
    <style:list-level-properties text:space-before="5mm" text:min-label-width="5mm"/>
   </text:list-level-style-number>
  </text:list-style>
 </office:styles>
</office:document-styles>""";
        }
    }

    // ── Automatic Style Pre-Parser ──────────────────────────────────────────────
    //
    // Real-world ODT files (LibreOffice / WPS) use *automatic styles*:
    //   - Paragraph styles like P34 with parent-style-name="666" (WPS numeric name)
    //   - Named styles "666" in styles.xml with fo:font-size="20pt"
    //   - Text styles like T40 with fo:font-weight="bold"
    // We pre-parse styles.xml (named) and then content.xml (automatic) so that
    // the body parser can resolve the full parent chain for heading detection.

    // Internal per-style property bag
    private class StyleProps : Object {
        public string parent = "";
        public double font_size_pt = 0;
        public bool bold = false;
        public bool italic = false;
        public string underline_style = "";
        public string strike_style = "";
        public string color = "";
        public string bg_color = "";
        public string font_name = "";
        public string alignment = "";  // "left", "center", "right", "justify", "end"
    }

    private class AutoStyles : Object {
        public const int BOLD      = 1;
        public const int ITALIC    = 2;
        public const int UNDERLINE = 4;
        public const int STRIKE    = 8;

        // Map font-name (e.g. "Arial") to font-family (e.g. "Arial, sans-serif")
        private GLib.HashTable<string, string> _font_map;
        // Named styles from styles.xml (e.g. "666", "Heading_1")
        private GLib.HashTable<string, StyleProps> _named_styles;
        // Automatic paragraph styles from content.xml
        private GLib.HashTable<string, StyleProps> _auto_para_styles;
        // Automatic text styles from content.xml
        private GLib.HashTable<string, StyleProps> _auto_text_styles;

        // Parsing state
        private string _cur_name   = "";
        private string _cur_family = "";
        private bool   _parsing_named = false;

        public GLib.HashTable<string, int> para_heading;
        public GLib.HashTable<string, StyleProps> text_props;
        // Maps paragraph style name, alignment ("center", "right", "justify")
        public GLib.HashTable<string, string> para_align;

        public AutoStyles() {
            _font_map          = new GLib.HashTable<string, string>(str_hash, str_equal);
            _named_styles      = new GLib.HashTable<string, StyleProps>(str_hash, str_equal);
            _auto_para_styles  = new GLib.HashTable<string, StyleProps>(str_hash, str_equal);
            _auto_text_styles  = new GLib.HashTable<string, StyleProps>(str_hash, str_equal);
            para_heading       = new GLib.HashTable<string, int>(str_hash, str_equal);
            text_props         = new GLib.HashTable<string, StyleProps>(str_hash, str_equal);
            para_align         = new GLib.HashTable<string, string>(str_hash, str_equal);
        }

        // Call with styles.xml content BEFORE parse()

        public void parse_styles_xml(string xml) {
            _parsing_named = true;
            do_parse(xml);
            _parsing_named = false;
        }

        // Call with content.xml content

        public void parse(string xml) {
            _parsing_named = false;
            do_parse(xml);
        }

        // After parse_styles_xml() + parse(), call this to populate
        // para_heading, text_props and para_align via chain resolution.

        public void resolve() {
            _auto_para_styles.foreach((name, props) => {
                int lv = resolve_heading_for(name);
                if (lv > 0) para_heading.set(name, lv);
            });
            _named_styles.foreach((name, props) => {
                int lv = resolve_heading_for(name);
                if (lv > 0) para_heading.set(name, lv);
            });
            _auto_text_styles.foreach((name, props) => {
                StyleProps? p = resolve_text_chain(name, 0);
                if (p != null) text_props.set(name, p);
            });
            // Populate para_align: skip default left/start alignments
            _auto_para_styles.foreach((name, props) => {
                string al = resolve_alignment(name, 0);
                if (al != "" && al != "left" && al != "start")
                    para_align.set(name, al);
            });
            _named_styles.foreach((name, props) => {
                string al = resolve_alignment(name, 0);
                if (al != "" && al != "left" && al != "start")
                    para_align.set(name, al);
            });
        }

        // ── Internal parsing ────────────────────────────────────────────────────

        private void do_parse(string xml) {
            var ctx = new MarkupParseContext(
                MarkupParser() {
                    start_element = on_start,
                    end_element   = on_end
                },
                MarkupParseFlags.TREAT_CDATA_AS_TEXT,
                this, null
            );
            try { ctx.parse(xml, -1); ctx.end_parse(); } catch {}
        }

        private void on_start(MarkupParseContext ctx, string elem,
                               string[] names, string[] vals) throws MarkupError {
            if (elem == "style:font-face") {
                string fname = attr(names, vals, "style:name");
                string ffamily = attr(names, vals, "svg:font-family");
                if (fname != "" && ffamily != "") {
                    // Remove single quotes if present (common in ODT)
                    if (ffamily.has_prefix("'") && ffamily.has_suffix("'")) {
                        ffamily = ffamily[1:ffamily.length-1];
                    }
                    _font_map.set(fname, ffamily);
                }
            } else if (elem == "style:style") {
                _cur_name   = attr(names, vals, "style:name");
                _cur_family = attr(names, vals, "style:family");
                if (_cur_name == "") return;

                var props = new StyleProps();
                props.parent = attr(names, vals, "style:parent-style-name");

                if (_parsing_named) {
                    _named_styles.set(_cur_name, props);
                } else if (_cur_family == "paragraph") {
                    _auto_para_styles.set(_cur_name, props);
                } else if (_cur_family == "text") {
                    _auto_text_styles.set(_cur_name, props);
                }
            } else if (elem == "style:paragraph-properties" && _cur_name != "") {
                StyleProps? props = null;
                if (_parsing_named) {
                    props = _named_styles.lookup(_cur_name);
                } else if (_cur_family == "paragraph") {
                    props = _auto_para_styles.lookup(_cur_name);
                }
                if (props != null) {
                    string al = attr(names, vals, "fo:text-align");
                    if (al != "") props.alignment = al;
                }
            } else if (elem == "style:text-properties" && _cur_name != "") {
                StyleProps? props = null;
                if (_parsing_named) {
                    props = _named_styles.lookup(_cur_name);
                } else if (_cur_family == "paragraph") {
                    props = _auto_para_styles.lookup(_cur_name);
                } else if (_cur_family == "text") {
                    props = _auto_text_styles.lookup(_cur_name);
                }
                if (props == null) return;

                double pt = parse_pt(attr(names, vals, "fo:font-size"));
                if (pt > 0) props.font_size_pt = pt;

                string fw = attr(names, vals, "fo:font-weight");
                if (fw == "bold" || fw == "700" || fw == "600") props.bold = true;

                string fi = attr(names, vals, "fo:font-style");
                if (fi == "italic") props.italic = true;

                string ul = attr(names, vals, "style:text-underline-style");
                if (ul != "") props.underline_style = ul;

                string st = attr(names, vals, "style:text-line-through-style");
                if (st != "") props.strike_style = st;

                string col = attr(names, vals, "fo:color");
                if (col != "") props.color = col;

                string bg = attr(names, vals, "fo:background-color");
                if (bg != "") props.bg_color = bg;

                string fn = attr(names, vals, "style:font-name");
                if (fn != "") {
                    props.font_name = _font_map.contains(fn) ? _font_map.get(fn) : fn;
                }
            }
        }

        private void on_end(MarkupParseContext ctx, string elem) throws MarkupError {
            if (elem == "style:style") _cur_name = _cur_family = "";
        }

        // ── Chain resolution ────────────────────────────────────────────────────

        private int resolve_heading_for(string name) {
            int lv = heading_level(name);
            if (lv > 0) return lv;
            double fs = resolve_font_size(name, 0);
            if (fs >= 20.0) return 1;
            if (fs >= 16.0) return 2;
            if (fs >= 14.0) return 3;
            if (fs >= 12.0 && resolve_bold(name, 0)) return 4;
            return 0;
        }

        private double resolve_font_size(string name, int depth) {
            if (depth > 8) return 0;
            StyleProps? p = _auto_para_styles.lookup(name);
            if (p == null) p = _named_styles.lookup(name);
            if (p == null) return 0;
            if (p.font_size_pt > 0) return p.font_size_pt;
            if (p.parent != "") return resolve_font_size(p.parent, depth + 1);
            return 0;
        }

        private bool resolve_bold(string name, int depth) {
            if (depth > 8) return false;
            StyleProps? p = _auto_para_styles.lookup(name);
            if (p == null) p = _named_styles.lookup(name);
            if (p == null) return false;
            if (p.bold) return true;
            if (p.parent != "") return resolve_bold(p.parent, depth + 1);
            return false;
        }

        private string resolve_alignment(string name, int depth) {
            if (depth > 8) return "";
            StyleProps? p = _auto_para_styles.lookup(name);
            if (p == null) p = _named_styles.lookup(name);
            if (p == null) return "";
            if (p.alignment != "") return p.alignment;
            if (p.parent != "") return resolve_alignment(p.parent, depth + 1);
            return "";
        }

        private StyleProps? resolve_text_chain(string name, int depth) {
            if (depth > 8) return null;
            StyleProps? p = _auto_text_styles.lookup(name);
            if (p == null) p = _auto_para_styles.lookup(name);
            if (p == null) p = _named_styles.lookup(name);
            if (p == null) return null;

            if (p.parent == "") return p;
            StyleProps? parent = resolve_text_chain(p.parent, depth + 1);
            if (parent == null) return p;

            var merged = new StyleProps();
            merged.bold = p.bold || parent.bold;
            merged.italic = p.italic || parent.italic;
            merged.underline_style = p.underline_style != "" ? p.underline_style : parent.underline_style;
            merged.strike_style = p.strike_style != "" ? p.strike_style : parent.strike_style;
            merged.color = p.color != "" ? p.color : parent.color;
            merged.bg_color = p.bg_color != "" ? p.bg_color : parent.bg_color;
            merged.font_name = p.font_name != "" ? p.font_name : parent.font_name;
            merged.font_size_pt = p.font_size_pt > 0 ? p.font_size_pt : parent.font_size_pt;
            return merged;
        }

        // ── Public helpers ──────────────────────────────────────────────────────

        public int heading_level(string name) {
            // LibreOffice encodes spaces as _20_ in style names
            if (name.has_prefix("Heading_20_")) return int.parse(name[11:]).clamp(1, 4);
            if (name.has_prefix("Heading_"))   return int.parse(name[8:]).clamp(1, 4);
            if (name.has_prefix("Heading "))   return int.parse(name[8:]).clamp(1, 4);
            return 0;
        }

        // ── Utilities ───────────────────────────────────────────────────────────

        private double parse_pt(string s) {
            if (s == "") return 0;
            if (s.has_suffix("pt")) return double.parse(s[0:s.length - 2]);
            if (s.has_suffix("in")) return double.parse(s[0:s.length - 2]) * 72.0;
            if (s.has_suffix("mm")) return double.parse(s[0:s.length - 2]) * 2.83465;
            if (s.has_suffix("cm")) return double.parse(s[0:s.length - 2]) * 28.3465;
            if (s.has_suffix("%")) return 0; // Relative font size not supported yet
            return double.parse(s);
        }

        private string attr(string[] names, string[] vals, string target) {
            for (int i = 0; i < names.length; i++)
                if (names[i] == target) return vals[i];
            return "";
        }
    }

    // ── XML Parser ──────────────────────────────────────────────────────────────

    private class ContentXmlParser : Object {
        private Gtk.TextBuffer _buf;
        private string _tmp_dir;
        private AutoStyles _auto;

        // Parser state
        private bool _in_body        = false;
        private bool _in_para        = false;
        private int  _heading_level  = 0;
        private string _para_align   = "";
        private string[] _style_stack = {};
        private int _style_depth     = 0;

        // List tracking
        private bool _in_list        = false;
        private bool _list_is_bullet = true;

        // Hyperlink tracking
        private bool _in_link        = false;
        private string _link_href    = "";

        // Table parsing state
        private bool     _in_table      = false;
        private bool     _in_table_cell = false;
        private string   _cur_cell_text = "";
        private string[] _cur_row_data  = {};
        private string[] _table_flat    = {};  // flat row-major cell data
        private int[]    _table_row_len = {};  // length of each row

        // Pending child anchor widgets for the caller to add to the TextView
        public GLib.List<PendingWidget> pending_widgets = new GLib.List<PendingWidget>();

        public ContentXmlParser(Gtk.TextBuffer buf, string tmp_dir, AutoStyles auto_styles) {
            _buf     = buf;
            _tmp_dir = tmp_dir;
            _auto    = auto_styles;
        }

        public void parse(string xml) {
            var ctx = new MarkupParseContext(
                MarkupParser() {
                    start_element = on_start,
                    end_element   = on_end,
                    text          = on_text
                },
                MarkupParseFlags.TREAT_CDATA_AS_TEXT,
                this, null
            );
            try { ctx.parse(xml, -1); ctx.end_parse(); } catch {}
        }

        private void on_start(MarkupParseContext ctx, string elem,
                               string[] names, string[] vals) throws MarkupError {
            switch (elem) {
                case "office:body":
                case "office:text":
                    _in_body = true;
                    break;

                case "text:p":
                    if (!_in_body || _in_table_cell) break;
                    _in_para = true;
                    _style_depth = 0;
                    string pstyle = attr(names, vals, "text:style-name");
                    int phlv = _auto.para_heading.contains(pstyle)
                        ? _auto.para_heading.get(pstyle)
                        : _auto.heading_level(pstyle);
                    _heading_level = phlv;
                    _para_align = _auto.para_align.contains(pstyle)
                        ? _auto.para_align.get(pstyle) : "";
                    if (pstyle != "" && phlv == 0) push_style(pstyle);
                    break;

                case "text:h":
                    if (!_in_body) break;
                    _in_para = true;
                    _style_depth = 0;
                    string lv_str = attr(names, vals, "text:outline-level");
                    _heading_level = lv_str != "" ? int.parse(lv_str) : 1;
                    _para_align = "";
                    break;

                case "text:list":
                    if (!_in_body) break;
                    _in_list = true;
                    string lst = attr(names, vals, "text:style-name");
                    // Treat as numbered if style name indicates it; default to bullet
                    _list_is_bullet = !(lst.has_prefix("L_numbered") ||
                                        lst == "List_Number" ||
                                        lst.down().contains("number"));
                    break;

                case "text:list-item":
                    break;

                case "text:span":
                    push_style(attr(names, vals, "text:style-name"));
                    break;

                case "text:line-break":
                    if (_in_para) insert_text("\n");
                    break;

                case "text:tab":
                    if (_in_para) insert_text("\t");
                    break;

                case "text:a":
                    _in_link = true;
                    _link_href = attr(names, vals, "xlink:href");
                    break;

                case "draw:image":
                    if (_in_body) handle_image(attr(names, vals, "xlink:href"));
                    break;

                case "table:table":
                    if (_in_body) {
                        _in_table   = true;
                        _table_flat    = {};
                        _table_row_len = {};
                        _cur_row_data  = {};
                    }
                    break;

                case "table:table-row":
                    if (_in_table) _cur_row_data = {};
                    break;

                case "table:table-cell":
                    if (_in_table) {
                        _in_table_cell = true;
                        _cur_cell_text = "";
                    }
                    break;
            }
        }

        private void on_end(MarkupParseContext ctx, string elem) throws MarkupError {
            switch (elem) {
                case "text:p":
                    if (_in_table_cell) break;
                    if (_in_para) {
                        insert_text("\n");
                        _in_para       = false;
                        _heading_level = 0;
                        _para_align    = "";
                        _style_depth   = 0;
                    }
                    break;

                case "text:h":
                    if (_in_para) {
                        insert_text("\n");
                        _in_para       = false;
                        _heading_level = 0;
                        _para_align    = "";
                        _style_depth   = 0;
                    }
                    break;

                case "text:span":
                    if (_style_depth > 0) _style_depth--;
                    break;

                case "text:list":
                    _in_list = false;
                    break;

                case "text:a":
                    _in_link  = false;
                    _link_href = "";
                    break;

                case "table:table-cell":
                    if (_in_table) {
                        _cur_row_data += _cur_cell_text;
                        _in_table_cell = false;
                        _cur_cell_text = "";
                    }
                    break;

                case "table:table-row":
                    if (_in_table) {
                        _table_row_len += _cur_row_data.length;
                        foreach (string c in _cur_row_data) _table_flat += c;
                        _cur_row_data = {};
                    }
                    break;

                case "table:table":
                    if (_in_table) {
                        build_table_widget();
                        _in_table = false;
                    }
                    break;
            }
        }

        private void on_text(MarkupParseContext ctx, string text, size_t text_len) throws MarkupError {
            if (text == "") return;
            if (_in_table_cell) {
                _cur_cell_text += text;
                return;
            }
            if (!_in_para) return;
            insert_text(text);
        }

        private void insert_text(string text) {
            Gtk.TextIter end;
            _buf.get_end_iter(out end);
            var mark = _buf.create_mark(null, end, true);

            _buf.insert(ref end, text, -1);

            Gtk.TextIter ts, te;
            _buf.get_iter_at_mark(out ts, mark);
            _buf.get_end_iter(out te);

            // Heading tag
            if (_heading_level > 0 && _heading_level <= 4) {
                var t = _buf.tag_table.lookup("h%d".printf(_heading_level));
                if (t != null) _buf.apply_tag(t, ts, te);
            }

            // Span / named style tags
            for (int i = 0; i < _style_depth; i++)
                apply_style(_style_stack[i], ts, te);

            // Paragraph alignment tag
            if (_para_align != "" && _para_align != "left" && _para_align != "start") {
                string aname = "align-" + _para_align;  // e.g. "align-center"
                var at = _buf.tag_table.lookup(aname);
                if (at == null) {
                    at = _buf.create_tag(aname);
                    switch (_para_align) {
                        case "center":  at.justification = Gtk.Justification.CENTER; break;
                        case "right":
                        case "end":     at.justification = Gtk.Justification.RIGHT;  break;
                        case "justify": at.justification = Gtk.Justification.FILL;   break;
                    }
                }
                _buf.apply_tag(at, ts, te);
            }

            // List bullet / numbered tag
            if (_in_list && _in_para) {
                string ltag = _list_is_bullet ? "bullet" : "numbered";
                var lt = _buf.tag_table.lookup(ltag);
                if (lt == null) lt = _buf.create_tag(ltag);
                if (lt != null) _buf.apply_tag(lt, ts, te);
            }

            // Hyperlink tag: named "href:<url>" so the serializer can find it
            if (_in_link && _link_href != "") {
                string htag_name = "href:" + _link_href;
                var ht = _buf.tag_table.lookup(htag_name);
                if (ht == null) {
                    ht = _buf.create_tag(htag_name);
                    ht.underline = Pango.Underline.SINGLE;
                    Gdk.RGBA blue = Gdk.RGBA();
                    blue.parse("#0066cc");
                    ht.foreground_rgba = blue;
                }
                _buf.apply_tag(ht, ts, te);
            }

            _buf.delete_mark(mark);
        }

        private void handle_image(string href) {
            if (href == "" || !_in_body) return;
            string img_path = _tmp_dir + "/" + href;
            if (!FileUtils.test(img_path, FileTest.EXISTS)) return;

            // Copy image to stable cache dir so it survives tmp cleanup
            string cache_dir = GLib.Path.build_filename(
                GLib.Environment.get_user_data_dir(), "singularity", "write", "images");
            try { GLib.DirUtils.create_with_parents(cache_dir, 0755); } catch {}
            string basename = GLib.Path.get_basename(img_path);
            string stable_path = GLib.Path.build_filename(cache_dir, basename);
            try {
                var src  = GLib.File.new_for_path(img_path);
                var dest = GLib.File.new_for_path(stable_path);
                src.copy(dest, GLib.FileCopyFlags.OVERWRITE, null, null);
            } catch (GLib.Error e) {
                warning("odt: failed to cache image %s: %s", basename, e.message);
                stable_path = img_path; // fallback to tmp (may not survive)
            }

            Gtk.TextIter end;
            _buf.get_end_iter(out end);
            var anchor = _buf.create_child_anchor(end);

            var pic = new Gtk.Picture.for_filename(stable_path);
            pic.set_size_request(400, -1);
            pic.halign = Gtk.Align.START;

            pending_widgets.append(new PendingWidget(anchor, pic));
        }

        private void build_table_widget() {
            int n_rows = _table_row_len.length;
            if (n_rows == 0) return;

            int n_cols = 0;
            foreach (int l in _table_row_len)
                if (l > n_cols) n_cols = l;
            if (n_cols == 0) return;

            var grid = new Gtk.Grid();
            grid.name = "%d x %d".printf(n_rows, n_cols);
            grid.row_spacing    = 2;
            grid.column_spacing = 4;
            grid.add_css_class("write-table");

            int flat_idx = 0;
            for (int r = 0; r < n_rows; r++) {
                int row_len = _table_row_len[r];
                for (int c = 0; c < n_cols; c++) {
                    string cell_text = (c < row_len) ? _table_flat[flat_idx + c] : "";
                    var lbl = new Gtk.Label(cell_text);
                    lbl.halign = Gtk.Align.START;
                    lbl.xalign = 0;
                    lbl.add_css_class("write-table-cell");
                    grid.attach(lbl, c, r, 1, 1);
                }
                flat_idx += row_len;
            }

            var frame = new Gtk.Frame(null);
            frame.child = grid;

            Gtk.TextIter end;
            _buf.get_end_iter(out end);
            var anchor = _buf.create_child_anchor(end);
            pending_widgets.append(new PendingWidget(anchor, frame));
        }

        private void apply_style(string s, Gtk.TextIter ts, Gtk.TextIter te) {
            // Named style mapping
            string tag_name = style_to_tag(s);
            if (tag_name != "") {
                var t = _buf.tag_table.lookup(tag_name);
                if (t != null) _buf.apply_tag(t, ts, te);
            }

            // Automatic style properties
            if (_auto.text_props.contains(s)) {
                StyleProps p = _auto.text_props.get(s);
                string dynamic_tag_id = "odt-style-" + s;
                var t = _buf.tag_table.lookup(dynamic_tag_id);
                if (t == null) {
                    t = _buf.create_tag(dynamic_tag_id);
                    if (p.bold) t.weight = 700;
                    if (p.italic) t.style = Pango.Style.ITALIC;
                    if (p.underline_style != "" && p.underline_style != "none") t.underline = Pango.Underline.SINGLE;
                    if (p.strike_style != "" && p.strike_style != "none") t.strikethrough = true;
                    if (p.font_size_pt > 0) t.size_points = p.font_size_pt;
                    if (p.color != "") {
                        Gdk.RGBA rgba = Gdk.RGBA();
                        if (rgba.parse(p.color)) t.foreground_rgba = rgba;
                    }
                    if (p.bg_color != "") {
                        Gdk.RGBA rgba = Gdk.RGBA();
                        if (rgba.parse(p.bg_color)) t.background_rgba = rgba;
                    }
                    if (p.font_name != "") t.family = p.font_name;
                }
                _buf.apply_tag(t, ts, te);
            }
        }

        private string style_to_tag(string s) {
            switch (s) {
                case "Bold":              return "bold";
                case "Italic":            return "italic";
                case "Underline":         return "underline";
                case "Strikethrough":     return "strikethrough";
                case "Quotations":        return "quote";
                case "Preformatted_Text": return "code";
                case "Heading_1":
                case "Heading 1":
                case "Heading_20_1":      return "h1";
                case "Heading_2":
                case "Heading 2":
                case "Heading_20_2":      return "h2";
                case "Heading_3":
                case "Heading 3":
                case "Heading_20_3":      return "h3";
                case "Heading_4":
                case "Heading 4":
                case "Heading_20_4":      return "h4";
                default:                  return "";
            }
        }

        private void push_style(string s) {
            if (_style_depth < 16) {
                if (_style_stack.length <= _style_depth)
                    _style_stack.resize(_style_depth + 1);
                _style_stack[_style_depth++] = s;
            }
        }

        private string attr(string[] names, string[] vals, string target) {
            for (int i = 0; i < names.length; i++)
                if (names[i] == target) return vals[i];
            return "";
        }
    }

    // ── XML Serializer ──────────────────────────────────────────────────────────

    private class ContentXmlSerializer : Object {
        private Gtk.TextBuffer _buf;
        private string _tmp_dir;

        public ContentXmlSerializer(Gtk.TextBuffer buf, string tmp_dir = "") {
            _buf     = buf;
            _tmp_dir = tmp_dir;
        }

        public string serialize() {
            var sb = new StringBuilder();
            sb.append(CONTENT_HEADER);

            Gtk.TextIter line_start;
            _buf.get_start_iter(out line_start);

            while (!line_start.is_end()) {
                Gtk.TextIter line_end = line_start;
                if (!line_end.ends_line()) line_end.forward_to_line_end();

                // Skip empty trailing line at doc end
                bool is_last_empty = line_end.equal(line_start) && line_end.is_end();
                if (!is_last_empty) {
                    bool is_bullet   = has("bullet",   line_start);
                    bool is_numbered = has("numbered", line_start);

                    if (is_bullet) {
                        sb.append("<text:list text:style-name=\"L_bullet\"><text:list-item><text:p text:style-name=\"List_Bullet\">");
                        serialize_run(sb, line_start, line_end);
                        sb.append("</text:p></text:list-item></text:list>\n");
                    } else if (is_numbered) {
                        sb.append("<text:list text:style-name=\"L_numbered\"><text:list-item><text:p text:style-name=\"List_Number\">");
                        serialize_run(sb, line_start, line_end);
                        sb.append("</text:p></text:list-item></text:list>\n");
                    } else {
                        string para_style = get_para_style(line_start);
                        open_para(sb, para_style);
                        serialize_run(sb, line_start, line_end);
                        close_para(sb, para_style);
                    }
                }

                line_start = line_end;
                if (!line_start.forward_char()) break;
            }

            sb.append(CONTENT_FOOTER);
            return sb.str;
        }

        private string get_para_style(Gtk.TextIter it) {
            for (int h = 1; h <= 4; h++) {
                var t = _buf.tag_table.lookup("h%d".printf(h));
                if (t != null && it.has_tag(t)) return "h%d".printf(h);
            }
            var quote = _buf.tag_table.lookup("quote");
            if (quote != null && it.has_tag(quote)) return "quote";
            var code = _buf.tag_table.lookup("code");
            if (code != null && it.has_tag(code)) return "code";
            if (has("align-center",  it)) return "body_center";
            if (has("align-right",   it)) return "body_right";
            if (has("align-end",     it)) return "body_right";
            if (has("align-justify", it)) return "body_justify";
            return "body";
        }

        private void open_para(StringBuilder sb, string style) {
            switch (style) {
                case "h1":          sb.append("<text:h text:outline-level=\"1\" text:style-name=\"Heading_1\">"); break;
                case "h2":          sb.append("<text:h text:outline-level=\"2\" text:style-name=\"Heading_2\">"); break;
                case "h3":          sb.append("<text:h text:outline-level=\"3\" text:style-name=\"Heading_3\">"); break;
                case "h4":          sb.append("<text:h text:outline-level=\"4\" text:style-name=\"Heading_4\">"); break;
                case "quote":       sb.append("<text:p text:style-name=\"Quotations\">"); break;
                case "code":        sb.append("<text:p text:style-name=\"Preformatted_Text\">"); break;
                case "body_center": sb.append("<text:p text:style-name=\"p_center\">"); break;
                case "body_right":  sb.append("<text:p text:style-name=\"p_right\">"); break;
                case "body_justify":sb.append("<text:p text:style-name=\"p_justify\">"); break;
                default:            sb.append("<text:p text:style-name=\"Text_Body\">"); break;
            }
        }

        private void close_para(StringBuilder sb, string style) {
            if (style.has_prefix("h"))
                sb.append("</text:h>\n");
            else
                sb.append("</text:p>\n");
        }

        private void serialize_run(StringBuilder sb, Gtk.TextIter start, Gtk.TextIter end) {
            Gtk.TextIter it = start;
            while (it.compare(end) < 0) {
                if (it.get_child_anchor() != null) {
                    serialize_anchor(sb, it.get_child_anchor());
                    it.forward_char();
                    continue;
                }

                Gtk.TextIter next = it;
                next.forward_to_tag_toggle(null);
                if (next.compare(end) > 0) next = end;

                bool bold  = has("bold",          it);
                bool ital  = has("italic",        it);
                bool under = has("underline",     it);
                bool strk  = has("strikethrough", it);
                string href = get_href_tag(it);

                string text = _buf.get_text(it, next, false);
                if (text == "") { it = next; continue; }

                string escaped = Markup.escape_text(text);

                if (href != "")
                    sb.append("<text:a xlink:type=\"simple\" xlink:href=\"%s\">".printf(
                        Markup.escape_text(href)));
                if (bold)  sb.append("<text:span text:style-name=\"s_bold\">");
                if (ital)  sb.append("<text:span text:style-name=\"s_italic\">");
                if (under) sb.append("<text:span text:style-name=\"s_underline\">");
                if (strk)  sb.append("<text:span text:style-name=\"s_strike\">");
                sb.append(escaped);
                if (strk)  sb.append("</text:span>");
                if (under) sb.append("</text:span>");
                if (ital)  sb.append("</text:span>");
                if (bold)  sb.append("</text:span>");
                if (href != "") sb.append("</text:a>");

                it = next;
            }
        }

        private void serialize_anchor(StringBuilder sb, Gtk.TextChildAnchor anchor) {
            var widgets = anchor.get_widgets();
            if (widgets.length == 0) return;

            var pic = widgets[0] as Gtk.Picture;
            if (pic != null) { serialize_image(sb, pic); return; }

            var frame = widgets[0] as Gtk.Frame;
            if (frame != null) {
                var grid = frame.child as Gtk.Grid;
                if (grid != null) serialize_table(sb, grid);
                return;
            }

            var grid = widgets[0] as Gtk.Grid;
            if (grid != null) serialize_table(sb, grid);
        }

        private void serialize_image(StringBuilder sb, Gtk.Picture pic) {
            if (_tmp_dir == "") return;
            var file = pic.get_file();
            if (file == null) return;
            string basename = file.get_basename();
            string dest = _tmp_dir + "/Pictures/" + basename;
            try {
                file.copy(GLib.File.new_for_path(dest), GLib.FileCopyFlags.OVERWRITE, null, null);
            } catch {}
            sb.append("<draw:frame draw:name=\"");
            sb.append(Markup.escape_text(basename));
            sb.append("\" text:anchor-type=\"as-char\" svg:width=\"200mm\" svg:height=\"auto\">");
            sb.append("<draw:image xlink:href=\"Pictures/");
            sb.append(Markup.escape_text(basename));
            sb.append("\" xlink:type=\"simple\" xlink:show=\"embed\" xlink:actuate=\"onLoad\"/>");
            sb.append("</draw:frame>");
        }

        private void serialize_table(StringBuilder sb, Gtk.Grid grid) {
            string[] dim = grid.name.split(" x ");
            if (dim.length < 2) return;
            int n_rows = int.parse(dim[0]);
            int n_cols = int.parse(dim[1]);
            if (n_rows <= 0 || n_cols <= 0) return;

            sb.append("<table:table table:name=\"T1\">");
            for (int c = 0; c < n_cols; c++)
                sb.append("<table:table-column/>");
            for (int r = 0; r < n_rows; r++) {
                sb.append("<table:table-row>");
                for (int c = 0; c < n_cols; c++) {
                    var cell = grid.get_child_at(c, r);
                    string txt = "";
                    if (cell is Gtk.Label)
                        txt = ((Gtk.Label) cell).label;
                    sb.append("<table:table-cell office:value-type=\"string\"><text:p>");
                    sb.append(Markup.escape_text(txt));
                    sb.append("</text:p></table:table-cell>");
                }
                sb.append("</table:table-row>");
            }
            sb.append("</table:table>");
        }

        private bool has(string tag_name, Gtk.TextIter it) {
            var t = _buf.tag_table.lookup(tag_name);
            return t != null && it.has_tag(t);
        }

        private string get_href_tag(Gtk.TextIter it) {
            foreach (Gtk.TextTag t in it.get_tags()) {
                string? tname = t.name;
                if (tname != null && tname.has_prefix("href:"))
                    return tname.substring(5);
            }
            return "";
        }

        private const string CONTENT_HEADER = """<?xml version="1.0" encoding="UTF-8"?>
<office:document-content
  xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
  xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
  xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0"
  xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0"
  xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"
  xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0"
  xmlns:xlink="http://www.w3.org/1999/xlink"
  xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0"
  office:version="1.3">
<office:automatic-styles>
 <style:style style:name="s_bold"    style:family="text">
  <style:text-properties fo:font-weight="bold"/>
 </style:style>
 <style:style style:name="s_italic"  style:family="text">
  <style:text-properties fo:font-style="italic"/>
 </style:style>
 <style:style style:name="s_underline" style:family="text">
  <style:text-properties style:text-underline-style="solid"
   style:text-underline-width="auto" style:text-underline-color="font-color"/>
 </style:style>
 <style:style style:name="s_strike"  style:family="text">
  <style:text-properties style:text-line-through-style="solid"/>
 </style:style>
 <style:style style:name="p_center" style:family="paragraph" style:parent-style-name="Text_Body">
  <style:paragraph-properties fo:text-align="center"/>
 </style:style>
 <style:style style:name="p_right" style:family="paragraph" style:parent-style-name="Text_Body">
  <style:paragraph-properties fo:text-align="end"/>
 </style:style>
 <style:style style:name="p_justify" style:family="paragraph" style:parent-style-name="Text_Body">
  <style:paragraph-properties fo:text-align="justify"/>
 </style:style>
</office:automatic-styles>
<office:body>
<office:text>
""";
        private const string CONTENT_FOOTER = "</office:text>\n</office:body>\n</office:document-content>\n";
    }
}
