namespace Write {

    public class X : Object {

        public static Xml.Doc* parse(string text) throws FormatError {
            Xml.Doc* doc = Xml.Parser.read_memory(text, text.length, null, null, Xml.ParserOption.NONET | Xml.ParserOption.HUGE);
            if (doc == null || doc->get_root_element() == null) {
                if (doc != null) delete doc;
                throw new FormatError.INVALID(_("The document contains malformed XML."));
            }
            return doc;
        }

        public static bool is(Xml.Node* n, string name) {
            return n != null && n->type == Xml.ElementType.ELEMENT_NODE && n->name == name;
        }

        public static string prefix(Xml.Node* n) {
            return n != null && n->ns != null && n->ns->prefix != null ? n->ns->prefix : "";
        }

        public static string ns(Xml.Node* n) {
            return n != null && n->ns != null && n->ns->href != null ? n->ns->href : "";
        }

        public static Xml.Node* child(Xml.Node* n, string name) {
            if (n == null) return null;
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type == Xml.ElementType.ELEMENT_NODE && c->name == name) return c;
            }
            return null;
        }

        public static Xml.Node* path(Xml.Node* n, string p) {
            Xml.Node* cur = n;
            foreach (string part in p.split("/")) {
                cur = child(cur, part);
                if (cur == null) return null;
            }
            return cur;
        }

        public static Gee.ArrayList<Xml.Node*> kids(Xml.Node* n, string? name = null) {
            var list = new Gee.ArrayList<Xml.Node*>();
            if (n == null) return list;
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                if (name == null || c->name == name) list.add(c);
            }
            return list;
        }

        public static void descendants(Xml.Node* n, string name, Gee.ArrayList<Xml.Node*> into) {
            if (n == null) return;
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                if (c->name == name) into.add(c);
                descendants(c, name, into);
            }
        }

        public static Xml.Node* find_desc(Xml.Node* n, string name) {
            if (n == null) return null;
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                if (c->name == name) return c;
                Xml.Node* r = find_desc(c, name);
                if (r != null) return r;
            }
            return null;
        }

        public static string? attr(Xml.Node* n, string name) {
            if (n == null) return null;
            for (Xml.Attr* a = n->properties; a != null; a = a->next) {
                if (a->name == name) return a->children != null ? a->children->content : "";
            }
            return null;
        }

        public static string? attr_p(Xml.Node* n, string pfx, string name) {
            if (n == null) return null;
            for (Xml.Attr* a = n->properties; a != null; a = a->next) {
                if (a->name != name) continue;
                string ap = a->ns != null && a->ns->prefix != null ? a->ns->prefix : "";
                if (ap == pfx) return a->children != null ? a->children->content : "";
            }
            return null;
        }

        public static string val(Xml.Node* n, string name = "val") {
            return attr(n, name) ?? "";
        }

        public static int ival(Xml.Node* n, string name, int fallback) {
            string? v = attr(n, name);
            if (v == null) return fallback;
            int64 r;
            if (int64.try_parse(v.strip(), out r)) return (int) r;
            double d;
            if (double.try_parse(v.strip(), out d)) return (int) d;
            return fallback;
        }

        public static double dval(Xml.Node* n, string name, double fallback) {
            string? v = attr(n, name);
            if (v == null) return fallback;
            double r;
            if (double.try_parse(v.strip(), out r)) return r;
            return fallback;
        }

        public static bool on(Xml.Node* n) {
            if (n == null) return false;
            string? v = attr(n, "val");
            return v == null || v == "1" || v == "true" || v == "on";
        }

        public static string text(Xml.Node* n) {
            if (n == null) return "";
            string? c = n->get_content();
            return c ?? "";
        }

        public static string dump(Xml.Doc* doc, Xml.Node* n) {
            var buf = new Xml.Buffer();
            buf.node_dump(doc, n, 0, 0);
            return buf.content();
        }

        public static double length_pt(string? s, double fallback = 0) {
            if (s == null) return fallback;
            string v = s.strip();
            if (v == "") return fallback;
            double factor = 1;
            string num = v;
            if (v.has_suffix("pt")) num = v.substring(0, v.length - 2);
            else if (v.has_suffix("in")) { num = v.substring(0, v.length - 2); factor = 72; }
            else if (v.has_suffix("cm")) { num = v.substring(0, v.length - 2); factor = 28.3464567; }
            else if (v.has_suffix("mm")) { num = v.substring(0, v.length - 2); factor = 2.83464567; }
            else if (v.has_suffix("pc")) { num = v.substring(0, v.length - 2); factor = 12; }
            else if (v.has_suffix("px")) { num = v.substring(0, v.length - 2); factor = 0.75; }
            double d;
            if (!double.try_parse(num, out d)) return fallback;
            return d * factor;
        }

        public static string esc(string s) {
            var b = new StringBuilder.sized(s.length + 8);
            unichar c;
            int i = 0;
            while (s.get_next_char(ref i, out c)) {
                switch (c) {
                    case '&': b.append("&amp;"); break;
                    case '<': b.append("&lt;"); break;
                    case '>': b.append("&gt;"); break;
                    case '"': b.append("&quot;"); break;
                    default:
                        if (c < 0x20 && c != '\t' && c != '\n' && c != '\r') break;
                        if (c == 0xFFFE || c == 0xFFFF) break;
                        b.append_unichar(c);
                        break;
                }
            }
            return b.str;
        }

        public static string num(double v) {
            if (v == Math.floor(v) && v.abs() < 1e15) return "%.0f".printf(v);
            string s = Fields.fixed(v, 4);
            while (s.has_suffix("0")) s = s.substring(0, s.length - 1);
            if (s.has_suffix(".")) s = s.substring(0, s.length - 1);
            return s;
        }
    }

    public class XmlOut : Object {
        public StringBuilder sb = new StringBuilder();
        private Gee.ArrayList<string> stack = new Gee.ArrayList<string>();
        private bool open_tag = false;

        public XmlOut(bool declaration = true) {
            if (declaration) sb.append("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n");
        }

        private void close_open() {
            if (open_tag) {
                sb.append(">");
                open_tag = false;
            }
        }

        public XmlOut start(string tag) {
            close_open();
            sb.append("<");
            sb.append(tag);
            stack.add(tag);
            open_tag = true;
            return this;
        }

        public XmlOut a(string name, string val) {
            sb.append(" ");
            sb.append(name);
            sb.append("=\"");
            sb.append(X.esc(val));
            sb.append("\"");
            return this;
        }

        public XmlOut ai(string name, int64 val) {
            return a(name, val.to_string());
        }

        public XmlOut ad(string name, double val) {
            return a(name, X.num(val));
        }

        public XmlOut text(string t) {
            close_open();
            sb.append(X.esc(t));
            return this;
        }

        public XmlOut raw(string t) {
            close_open();
            sb.append(t);
            return this;
        }

        public XmlOut end() {
            string tag = stack.remove_at(stack.size - 1);
            if (open_tag) {
                sb.append("/>");
                open_tag = false;
            } else {
                sb.append("</");
                sb.append(tag);
                sb.append(">");
            }
            return this;
        }

        public XmlOut empty(string tag) {
            start(tag);
            return end();
        }

        public XmlOut val(string tag, string v) {
            start(tag);
            a("w:val", v);
            return end();
        }

        public XmlOut elem(string tag, string content) {
            start(tag);
            text(content);
            return end();
        }

        public string str() {
            while (stack.size > 0) end();
            return sb.str;
        }
    }
}
