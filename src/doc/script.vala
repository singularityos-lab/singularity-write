namespace Write {

    public errordomain ScriptError {
        SYNTAX,
        RUNTIME
    }

    public enum ValueKind {
        NULL,
        NUMBER,
        STRING,
        BOOL,
        LIST,
        PARAGRAPH,
        TABLE,
        FUNCTION
    }

    public class SValue : Object {
        public ValueKind kind = ValueKind.NULL;
        public double num = 0;
        public string str = "";
        public bool flag = false;
        public Gee.ArrayList<SValue> items = null;
        public Paragraph? para = null;
        public Table? table = null;
        public SNode? fn = null;

        public static SValue nil() {
            return new SValue();
        }

        public static SValue number(double v) {
            var s = new SValue();
            s.kind = ValueKind.NUMBER;
            s.num = v;
            return s;
        }

        public static SValue text(string v) {
            var s = new SValue();
            s.kind = ValueKind.STRING;
            s.str = v;
            return s;
        }

        public static SValue boolean(bool v) {
            var s = new SValue();
            s.kind = ValueKind.BOOL;
            s.flag = v;
            return s;
        }

        public static SValue list() {
            var s = new SValue();
            s.kind = ValueKind.LIST;
            s.items = new Gee.ArrayList<SValue>();
            return s;
        }

        public bool truthy() {
            switch (kind) {
                case ValueKind.NULL: return false;
                case ValueKind.NUMBER: return num != 0;
                case ValueKind.STRING: return str != "";
                case ValueKind.BOOL: return flag;
                case ValueKind.LIST: return items.size > 0;
                default: return true;
            }
        }

        public string to_text() {
            switch (kind) {
                case ValueKind.NULL: return "null";
                case ValueKind.NUMBER: return num == Math.floor(num) && num.abs() < 1e15 ? "%.0f".printf(num) : X.num(num);
                case ValueKind.STRING: return str;
                case ValueKind.BOOL: return flag ? "true" : "false";
                case ValueKind.LIST:
                    string[] parts = {};
                    foreach (var i in items) parts += i.to_text();
                    return "[" + string.joinv(", ", parts) + "]";
                case ValueKind.PARAGRAPH: return para.plain_text();
                case ValueKind.TABLE: return "table %dx%d".printf(table.rows.size, table.columns());
                default: return "function";
            }
        }

        public double to_number() {
            switch (kind) {
                case ValueKind.NUMBER: return num;
                case ValueKind.BOOL: return flag ? 1 : 0;
                case ValueKind.STRING:
                    double v;
                    return double.try_parse(str.strip(), out v) ? v : 0;
                default: return 0;
            }
        }
    }

    public class SNode : Object {
        public string kind;
        public string name = "";
        public double num = 0;
        public int line = 0;
        public Gee.ArrayList<SNode> kids = new Gee.ArrayList<SNode>();
        public Gee.ArrayList<string> args = new Gee.ArrayList<string>();

        public SNode(string kind, int line) {
            this.kind = kind;
            this.line = line;
        }

        public SNode add(SNode? n) {
            if (n != null) kids.add(n);
            return this;
        }
    }

    public class SToken {
        public string kind;
        public string text;
        public double num;
        public int line;
    }

    public class ScriptParser : Object {
        private Gee.ArrayList<SToken> toks = new Gee.ArrayList<SToken>();
        private int pos = 0;

        private static bool is_ident(unichar c, bool first) {
            return c.isalpha() || c == '_' || (!first && c.isdigit());
        }

        private void lex(string src) throws ScriptError {
            int i = 0;
            int line = 1;
            unichar c;
            string[] ops = { "==", "!=", "<=", ">=", "+=", "-=", "&&", "||" };
            while (i < src.length) {
                int start = i;
                src.get_next_char(ref i, out c);
                if (c == '\n') {
                    var t = new SToken();
                    t.kind = "nl";
                    t.text = "\n";
                    t.line = line++;
                    toks.add(t);
                    continue;
                }
                if (c == ' ' || c == '\t' || c == '\r') continue;
                if (c == '#') {
                    while (i < src.length && src[i] != '\n') i++;
                    continue;
                }
                var tk = new SToken();
                tk.line = line;
                if (c.isdigit()) {
                    int s = start;
                    while (i < src.length && (src[i].isdigit() || src[i] == '.')) i++;
                    tk.kind = "num";
                    tk.text = src.substring(s, i - s);
                    tk.num = double.parse(tk.text);
                } else if (c == '"' || c == '\'') {
                    var sb = new StringBuilder();
                    unichar q = c;
                    bool closed = false;
                    while (i < src.length) {
                        unichar d;
                        src.get_next_char(ref i, out d);
                        if (d == q) {
                            closed = true;
                            break;
                        }
                        if (d == '\\' && i < src.length) {
                            unichar e;
                            src.get_next_char(ref i, out e);
                            if (e == 'n') sb.append_c('\n');
                            else if (e == 't') sb.append_c('\t');
                            else sb.append_unichar(e);
                            continue;
                        }
                        if (d == '\n') line++;
                        sb.append_unichar(d);
                    }
                    if (!closed) throw new ScriptError.SYNTAX(_("Line %d: unterminated text").printf(tk.line));
                    tk.kind = "str";
                    tk.text = sb.str;
                } else if (is_ident(c, true)) {
                    int s = start;
                    while (i < src.length) {
                        int save = i;
                        unichar d;
                        src.get_next_char(ref i, out d);
                        if (!is_ident(d, false)) {
                            i = save;
                            break;
                        }
                    }
                    tk.kind = "id";
                    tk.text = src.substring(s, i - s);
                } else {
                    string two = i < src.length ? src.substring(start, 2) : "";
                    bool found = false;
                    foreach (string op in ops) if (two == op) {
                        tk.kind = "op";
                        tk.text = op;
                        i = start + 2;
                        found = true;
                    }
                    if (!found) {
                        tk.kind = "op";
                        tk.text = c.to_string();
                        if (!("(){}[],.+-*/%<>=!;:".contains(tk.text))) throw new ScriptError.SYNTAX(_("Line %d: unexpected character “%s”").printf(line, tk.text));
                    }
                }
                toks.add(tk);
            }
            var end = new SToken();
            end.kind = "eof";
            end.text = "";
            end.line = line;
            toks.add(end);
        }

        private SToken peek() {
            return toks[pos];
        }

        private SToken next() {
            return toks[pos++];
        }

        private bool at(string text) {
            var t = peek();
            return (t.kind == "op" || t.kind == "id") && t.text == text;
        }

        private void expect(string text) throws ScriptError {
            if (!at(text)) throw new ScriptError.SYNTAX(_("Line %d: expected “%s”").printf(peek().line, text));
            pos++;
        }

        private void skip_nl() {
            while (peek().kind == "nl" || (peek().kind == "op" && peek().text == ";")) pos++;
        }

        public SNode parse(string src) throws ScriptError {
            lex(src);
            var prog = new SNode("block", 1);
            skip_nl();
            while (peek().kind != "eof") {
                prog.add(statement());
                skip_nl();
            }
            return prog;
        }

        private SNode block() throws ScriptError {
            skip_nl();
            expect("{");
            var b = new SNode("block", peek().line);
            skip_nl();
            while (!at("}")) {
                if (peek().kind == "eof") throw new ScriptError.SYNTAX(_("Missing “}”"));
                b.add(statement());
                skip_nl();
            }
            expect("}");
            return b;
        }

        private SNode statement() throws ScriptError {
            var t = peek();
            int line = t.line;
            if (t.kind == "id") {
                switch (t.text) {
                    case "let":
                        pos++;
                        var n = new SNode("let", line);
                        n.name = next().text;
                        expect("=");
                        n.add(expr());
                        return n;
                    case "if":
                        pos++;
                        var n = new SNode("if", line);
                        n.add(expr());
                        n.add(block());
                        int save = pos;
                        skip_nl();
                        if (at("else")) {
                            pos++;
                            if (at("if")) {
                                var inner = new SNode("block", line);
                                inner.add(statement());
                                n.add(inner);
                            } else n.add(block());
                        } else pos = save;
                        return n;
                    case "while":
                        pos++;
                        var n = new SNode("while", line);
                        n.add(expr());
                        n.add(block());
                        return n;
                    case "for":
                        pos++;
                        var n = new SNode("for", line);
                        n.name = next().text;
                        expect("in");
                        n.add(expr());
                        n.add(block());
                        return n;
                    case "func":
                        pos++;
                        var n = new SNode("func", line);
                        n.name = next().text;
                        expect("(");
                        while (!at(")")) {
                            n.args.add(next().text);
                            if (at(",")) pos++;
                        }
                        expect(")");
                        n.add(block());
                        return n;
                    case "on":
                        pos++;
                        var n = new SNode("on", line);
                        n.name = next().text;
                        n.add(block());
                        return n;
                    case "return":
                        pos++;
                        var n = new SNode("return", line);
                        if (peek().kind != "nl" && !at("}") && peek().kind != "eof") n.add(expr());
                        return n;
                    case "break":
                        pos++;
                        return new SNode("break", line);
                    case "continue":
                        pos++;
                        return new SNode("continue", line);
                    default:
                        break;
                }
            }
            var e = expr();
            if (at("=") || at("+=") || at("-=")) {
                string op = next().text;
                var n = new SNode("assign", line);
                n.name = op;
                n.add(e);
                n.add(expr());
                return n;
            }
            var s = new SNode("expr", line);
            s.add(e);
            return s;
        }

        private SNode expr() throws ScriptError {
            return or_expr();
        }

        private SNode or_expr() throws ScriptError {
            var l = and_expr();
            while (at("or") || at("||")) {
                int line = next().line;
                var n = new SNode("or", line);
                n.add(l);
                n.add(and_expr());
                l = n;
            }
            return l;
        }

        private SNode and_expr() throws ScriptError {
            var l = cmp_expr();
            while (at("and") || at("&&")) {
                int line = next().line;
                var n = new SNode("and", line);
                n.add(l);
                n.add(cmp_expr());
                l = n;
            }
            return l;
        }

        private SNode cmp_expr() throws ScriptError {
            var l = add_expr();
            while (at("==") || at("!=") || at("<") || at(">") || at("<=") || at(">=")) {
                var t = next();
                var n = new SNode("bin", t.line);
                n.name = t.text;
                n.add(l);
                n.add(add_expr());
                l = n;
            }
            return l;
        }

        private SNode add_expr() throws ScriptError {
            var l = mul_expr();
            while (at("+") || at("-")) {
                var t = next();
                var n = new SNode("bin", t.line);
                n.name = t.text;
                n.add(l);
                n.add(mul_expr());
                l = n;
            }
            return l;
        }

        private SNode mul_expr() throws ScriptError {
            var l = unary();
            while (at("*") || at("/") || at("%")) {
                var t = next();
                var n = new SNode("bin", t.line);
                n.name = t.text;
                n.add(l);
                n.add(unary());
                l = n;
            }
            return l;
        }

        private SNode unary() throws ScriptError {
            if (at("not") || at("!")) {
                int line = next().line;
                return new SNode("not", line).add(unary());
            }
            if (at("-")) {
                int line = next().line;
                return new SNode("neg", line).add(unary());
            }
            return postfix();
        }

        private SNode postfix() throws ScriptError {
            var n = primary();
            while (true) {
                if (at("(")) {
                    int line = next().line;
                    var c = new SNode("call", line);
                    c.add(n);
                    while (!at(")")) {
                        c.add(expr());
                        if (at(",")) pos++;
                        else if (!at(")")) throw new ScriptError.SYNTAX(_("Line %d: expected “,” or “)”").printf(peek().line));
                    }
                    expect(")");
                    n = c;
                } else if (at(".")) {
                    int line = next().line;
                    var m = new SNode("member", line);
                    m.name = next().text;
                    m.add(n);
                    n = m;
                } else if (at("[")) {
                    int line = next().line;
                    var ix = new SNode("index", line);
                    ix.add(n);
                    ix.add(expr());
                    expect("]");
                    n = ix;
                } else break;
            }
            return n;
        }

        private SNode primary() throws ScriptError {
            var t = next();
            switch (t.kind) {
                case "num":
                    var n = new SNode("num", t.line);
                    n.num = t.num;
                    return n;
                case "str":
                    var n = new SNode("str", t.line);
                    n.name = t.text;
                    return n;
                case "id":
                    if (t.text == "true" || t.text == "false") {
                        var b = new SNode("bool", t.line);
                        b.num = t.text == "true" ? 1 : 0;
                        return b;
                    }
                    if (t.text == "null") return new SNode("null", t.line);
                    var v = new SNode("var", t.line);
                    v.name = t.text;
                    return v;
                case "op":
                    if (t.text == "(") {
                        var e = expr();
                        expect(")");
                        return e;
                    }
                    if (t.text == "[") {
                        var l = new SNode("list", t.line);
                        while (!at("]")) {
                            l.add(expr());
                            if (at(",")) pos++;
                        }
                        expect("]");
                        return l;
                    }
                    break;
                default:
                    break;
            }
            throw new ScriptError.SYNTAX(_("Line %d: unexpected “%s”").printf(t.line, t.text == "\n" ? _("end of line") : t.text));
        }
    }

    public delegate void ScriptMessage(string text);
    public delegate bool ScriptAction(string name, string? param);

    public class ScriptRunner : Object {
        public Document doc;
        public Editor? ed;
        public Gee.ArrayList<string> output = new Gee.ArrayList<string>();
        public Gee.HashMap<string, SNode> handlers = new Gee.HashMap<string, SNode>();
        public int steps_limit = 2000000;
        private int steps = 0;
        private Gee.ArrayList<Gee.HashMap<string, SValue>> scopes = new Gee.ArrayList<Gee.HashMap<string, SValue>>();
        private Gee.HashMap<string, SNode> funcs = new Gee.HashMap<string, SNode>();
        private SValue? ret = null;
        private bool breaking = false;
        private bool continuing = false;
        private ScriptMessage? on_message = null;
        private ScriptAction? on_action = null;
        public bool changed = false;

        public ScriptRunner(Document doc, Editor? ed) {
            this.doc = doc;
            this.ed = ed;
            scopes.add(new Gee.HashMap<string, SValue>());
        }

        public void set_message(owned ScriptMessage m) {
            on_message = (owned) m;
        }

        public void set_action(owned ScriptAction a) {
            on_action = (owned) a;
        }

        public void run(string source) throws ScriptError {
            var prog = new ScriptParser().parse(source);
            exec_block(prog, false);
        }

        public void fire(string event) throws ScriptError {
            if (!handlers.has_key(event)) return;
            scopes.add(new Gee.HashMap<string, SValue>());
            scopes[0]["event"] = SValue.text(event);
            exec_block(handlers[event], false);
            scopes.remove_at(scopes.size - 1);
        }

        private SValue? lookup(string name) {
            for (int i = scopes.size - 1; i >= 0; i--) if (scopes[i].has_key(name)) return scopes[i][name];
            return null;
        }

        private void store(string name, SValue v, int line) throws ScriptError {
            for (int i = scopes.size - 1; i >= 0; i--) {
                if (scopes[i].has_key(name)) {
                    scopes[i][name] = v;
                    return;
                }
            }
            throw new ScriptError.RUNTIME(_("Line %d: “%s” is not defined; use let").printf(line, name));
        }

        private void tick(int line) throws ScriptError {
            if (++steps > steps_limit) throw new ScriptError.RUNTIME(_("Line %d: the script ran too long and was stopped").printf(line));
        }

        private void exec_block(SNode b, bool scoped = true) throws ScriptError {
            if (scoped) scopes.add(new Gee.HashMap<string, SValue>());
            foreach (var s in b.kids) {
                exec(s);
                if (ret != null || breaking || continuing) break;
            }
            if (scoped) scopes.remove_at(scopes.size - 1);
        }

        private void exec(SNode s) throws ScriptError {
            tick(s.line);
            switch (s.kind) {
                case "let":
                    scopes[scopes.size - 1][s.name] = eval(s.kids[0]);
                    break;
                case "assign":
                    var target = s.kids[0];
                    var v = eval(s.kids[1]);
                    if (s.name != "=") {
                        var cur = eval(target);
                        v = binop(s.name == "+=" ? "+" : "-", cur, v, s.line);
                    }
                    assign(target, v, s.line);
                    break;
                case "if":
                    if (eval(s.kids[0]).truthy()) exec_block(s.kids[1]);
                    else if (s.kids.size > 2) exec_block(s.kids[2]);
                    break;
                case "while":
                    while (eval(s.kids[0]).truthy()) {
                        tick(s.line);
                        exec_block(s.kids[1]);
                        if (continuing) continuing = false;
                        if (breaking) {
                            breaking = false;
                            break;
                        }
                        if (ret != null) break;
                    }
                    break;
                case "for":
                    var coll = eval(s.kids[0]);
                    var items = new Gee.ArrayList<SValue>();
                    if (coll.kind == ValueKind.LIST) items.add_all(coll.items);
                    else if (coll.kind == ValueKind.NUMBER) for (int i = 0; i < (int) coll.num; i++) items.add(SValue.number(i));
                    else if (coll.kind == ValueKind.STRING) {
                        unichar c;
                        int i = 0;
                        while (coll.str.get_next_char(ref i, out c)) items.add(SValue.text(c.to_string()));
                    } else throw new ScriptError.RUNTIME(_("Line %d: cannot loop over %s").printf(s.line, coll.to_text()));
                    foreach (var it in items) {
                        tick(s.line);
                        scopes.add(new Gee.HashMap<string, SValue>());
                        scopes[scopes.size - 1][s.name] = it;
                        exec_block(s.kids[1], false);
                        scopes.remove_at(scopes.size - 1);
                        if (continuing) continuing = false;
                        if (breaking) {
                            breaking = false;
                            break;
                        }
                        if (ret != null) break;
                    }
                    break;
                case "func":
                    funcs[s.name] = s;
                    break;
                case "on":
                    handlers[s.name] = s.kids[0];
                    break;
                case "return":
                    ret = s.kids.size > 0 ? eval(s.kids[0]) : SValue.nil();
                    break;
                case "break":
                    breaking = true;
                    break;
                case "continue":
                    continuing = true;
                    break;
                default:
                    eval(s.kids[0]);
                    break;
            }
        }

        private void assign(SNode target, SValue v, int line) throws ScriptError {
            if (target.kind == "var") {
                store(target.name, v, line);
                return;
            }
            if (target.kind == "index") {
                var l = eval(target.kids[0]);
                int i = (int) eval(target.kids[1]).to_number();
                if (l.kind != ValueKind.LIST || i < 0 || i >= l.items.size) throw new ScriptError.RUNTIME(_("Line %d: index out of range").printf(line));
                l.items[i] = v;
                return;
            }
            if (target.kind == "member") {
                var o = eval(target.kids[0]);
                if (o.kind == ValueKind.PARAGRAPH) {
                    switch (target.name) {
                        case "text":
                            set_para_text(o.para, v.to_text());
                            return;
                        case "style":
                            o.para.style = doc.styles.get(v.to_text()) != null ? v.to_text() : style_id(v.to_text(), line);
                            touch(o.para);
                            return;
                        case "align":
                            string a = v.to_text();
                            o.para.props.align = a == "center" ? Align.CENTER : (a == "right" ? Align.RIGHT : (a == "justify" ? Align.JUSTIFY : Align.LEFT));
                            touch(o.para);
                            return;
                        default:
                            break;
                    }
                }
                throw new ScriptError.RUNTIME(_("Line %d: “%s” cannot be changed").printf(line, target.name));
            }
            throw new ScriptError.RUNTIME(_("Line %d: cannot assign here").printf(line));
        }

        private string style_id(string name, int line) throws ScriptError {
            foreach (var s in doc.styles.list) if (s.name == name || s.id == name) return s.id;
            throw new ScriptError.RUNTIME(_("Line %d: there is no style “%s”").printf(line, name));
        }

        private void touch(Paragraph p) {
            p.touch();
            changed = true;
        }

        private void set_para_text(Paragraph p, string text) {
            var props = p.inlines.size > 0 ? p.props_at(1) : new CharProps();
            var keep = new Gee.ArrayList<Inline>();
            foreach (var i in p.inlines) if (i is Mark) keep.add(i);
            p.inlines.clear();
            p.inlines.add_all(keep);
            p.insert_text(p.length, text, props);
            touch(p);
        }

        private SValue binop(string op, SValue a, SValue b, int line) throws ScriptError {
            switch (op) {
                case "+":
                    if (a.kind == ValueKind.NUMBER && b.kind == ValueKind.NUMBER) return SValue.number(a.num + b.num);
                    if (a.kind == ValueKind.LIST) {
                        var l = SValue.list();
                        l.items.add_all(a.items);
                        if (b.kind == ValueKind.LIST) l.items.add_all(b.items);
                        else l.items.add(b);
                        return l;
                    }
                    return SValue.text(a.to_text() + b.to_text());
                case "-": return SValue.number(a.to_number() - b.to_number());
                case "*": return SValue.number(a.to_number() * b.to_number());
                case "/":
                    if (b.to_number() == 0) throw new ScriptError.RUNTIME(_("Line %d: division by zero").printf(line));
                    return SValue.number(a.to_number() / b.to_number());
                case "%": return SValue.number(a.to_number() % b.to_number());
                case "==": return SValue.boolean(equal(a, b));
                case "!=": return SValue.boolean(!equal(a, b));
                default:
                    int c = (a.kind == ValueKind.STRING && b.kind == ValueKind.STRING) ? strcmp(a.str, b.str) : (a.to_number() < b.to_number() ? -1 : (a.to_number() > b.to_number() ? 1 : 0));
                    if (op == "<") return SValue.boolean(c < 0);
                    if (op == ">") return SValue.boolean(c > 0);
                    if (op == "<=") return SValue.boolean(c <= 0);
                    return SValue.boolean(c >= 0);
            }
        }

        private static bool equal(SValue a, SValue b) {
            if (a.kind == ValueKind.NULL || b.kind == ValueKind.NULL) return a.kind == b.kind;
            if (a.kind == ValueKind.NUMBER || b.kind == ValueKind.NUMBER) return a.to_number() == b.to_number();
            if (a.kind == ValueKind.BOOL && b.kind == ValueKind.BOOL) return a.flag == b.flag;
            if (a.kind == ValueKind.PARAGRAPH && b.kind == ValueKind.PARAGRAPH) return a.para == b.para;
            return a.to_text() == b.to_text();
        }

        private SValue eval(SNode n) throws ScriptError {
            tick(n.line);
            switch (n.kind) {
                case "num": return SValue.number(n.num);
                case "str": return SValue.text(n.name);
                case "bool": return SValue.boolean(n.num != 0);
                case "null": return SValue.nil();
                case "list":
                    var l = SValue.list();
                    foreach (var k in n.kids) l.items.add(eval(k));
                    return l;
                case "var":
                    var v = lookup(n.name);
                    if (v == null) {
                        if (funcs.has_key(n.name)) {
                            var f = new SValue();
                            f.kind = ValueKind.FUNCTION;
                            f.fn = funcs[n.name];
                            return f;
                        }
                        throw new ScriptError.RUNTIME(_("Line %d: “%s” is not defined").printf(n.line, n.name));
                    }
                    return v;
                case "not": return SValue.boolean(!eval(n.kids[0]).truthy());
                case "neg": return SValue.number(-eval(n.kids[0]).to_number());
                case "and":
                    var a = eval(n.kids[0]);
                    return a.truthy() ? SValue.boolean(eval(n.kids[1]).truthy()) : SValue.boolean(false);
                case "or":
                    var a = eval(n.kids[0]);
                    return a.truthy() ? SValue.boolean(true) : SValue.boolean(eval(n.kids[1]).truthy());
                case "bin": return binop(n.name, eval(n.kids[0]), eval(n.kids[1]), n.line);
                case "index":
                    var c = eval(n.kids[0]);
                    int i = (int) eval(n.kids[1]).to_number();
                    if (c.kind == ValueKind.LIST) {
                        if (i < 0) i += c.items.size;
                        if (i < 0 || i >= c.items.size) throw new ScriptError.RUNTIME(_("Line %d: index out of range").printf(n.line));
                        return c.items[i];
                    }
                    if (c.kind == ValueKind.STRING) {
                        if (i < 0 || i >= c.str.char_count()) return SValue.text("");
                        return SValue.text(c.str.get_char(c.str.index_of_nth_char(i)).to_string());
                    }
                    throw new ScriptError.RUNTIME(_("Line %d: cannot index %s").printf(n.line, c.to_text()));
                case "member": return member(eval(n.kids[0]), n.name, n.line);
                case "call": return call(n);
                default:
                    throw new ScriptError.RUNTIME(_("Line %d: cannot evaluate this").printf(n.line));
            }
        }

        private SValue para_value(Paragraph p) {
            var v = new SValue();
            v.kind = ValueKind.PARAGRAPH;
            v.para = p;
            return v;
        }

        private SValue table_value(Table t) {
            var v = new SValue();
            v.kind = ValueKind.TABLE;
            v.table = t;
            return v;
        }

        private SValue member(SValue o, string name, int line) throws ScriptError {
            if (o.kind == ValueKind.PARAGRAPH) {
                var p = o.para;
                switch (name) {
                    case "text": return SValue.text(p.plain_text());
                    case "style": return SValue.text(p.style);
                    case "style_name":
                        var st = doc.styles.get(p.style);
                        return SValue.text(st != null ? st.name : p.style);
                    case "level": return SValue.number(doc.styles.outline_level(p) + 1);
                    case "length": return SValue.number(p.length);
                    case "words": return SValue.number(Stats.count_words(p.plain_text()));
                    case "index": return SValue.number(Story.paragraphs(doc.body).index_of(p));
                    case "is_heading": return SValue.boolean(doc.styles.outline_level(p) >= 0 && p.style.has_prefix("Heading"));
                    case "in_table": return SValue.boolean(p.parent != null && p.parent.owner is TableCell);
                    default: break;
                }
            } else if (o.kind == ValueKind.TABLE) {
                switch (name) {
                    case "rows": return SValue.number(o.table.rows.size);
                    case "columns": return SValue.number(o.table.columns());
                    case "style": return SValue.text(o.table.style);
                    default: break;
                }
            } else if (o.kind == ValueKind.LIST && name == "length") {
                return SValue.number(o.items.size);
            } else if (o.kind == ValueKind.STRING && name == "length") {
                return SValue.number(o.str.char_count());
            }
            throw new ScriptError.RUNTIME(_("Line %d: “%s” has no “%s”").printf(line, o.to_text(), name));
        }

        private TableCell? cell_of(Table t, int r, int c, int line) throws ScriptError {
            if (r < 0 || r >= t.rows.size) throw new ScriptError.RUNTIME(_("Line %d: row %d does not exist").printf(line, r));
            var cell = t.cell_at_grid(t.rows[r], c);
            if (cell == null) throw new ScriptError.RUNTIME(_("Line %d: column %d does not exist").printf(line, c));
            return cell;
        }

        private SValue call(SNode n) throws ScriptError {
            var callee = n.kids[0];
            var args = new Gee.ArrayList<SValue>();
            for (int i = 1; i < n.kids.size; i++) args.add(eval(n.kids[i]));
            string fname = callee.kind == "var" ? callee.name : "";
            if (callee.kind == "member") {
                var obj = eval(callee.kids[0]);
                var all = new Gee.ArrayList<SValue>();
                all.add(obj);
                all.add_all(args);
                return builtin(callee.name, all, n.line);
            }
            if (funcs.has_key(fname)) {
                var f = funcs[fname];
                var scope = new Gee.HashMap<string, SValue>();
                for (int i = 0; i < f.args.size; i++) scope[f.args[i]] = i < args.size ? args[i] : SValue.nil();
                scopes.add(scope);
                exec_block(f.kids[0], false);
                scopes.remove_at(scopes.size - 1);
                var r = ret ?? SValue.nil();
                ret = null;
                return r;
            }
            return builtin(fname, args, n.line);
        }

        private string arg_text(Gee.ArrayList<SValue> a, int i) {
            return i < a.size ? a[i].to_text() : "";
        }

        private double arg_num(Gee.ArrayList<SValue> a, int i) {
            return i < a.size ? a[i].to_number() : 0;
        }

        private Paragraph need_para(Gee.ArrayList<SValue> a, int i, int line) throws ScriptError {
            if (i >= a.size || a[i].kind != ValueKind.PARAGRAPH) throw new ScriptError.RUNTIME(_("Line %d: a paragraph is expected").printf(line));
            return a[i].para;
        }

        private Table need_table(Gee.ArrayList<SValue> a, int i, int line) throws ScriptError {
            if (i >= a.size || a[i].kind != ValueKind.TABLE) throw new ScriptError.RUNTIME(_("Line %d: a table is expected").printf(line));
            return a[i].table;
        }

        private SValue builtin(string name, Gee.ArrayList<SValue> a, int line) throws ScriptError {
            switch (name) {
                case "print":
                case "message":
                    string[] parts = {};
                    foreach (var v in a) parts += v.to_text();
                    string msg = string.joinv(" ", parts);
                    output.add(msg);
                    if (on_message != null) on_message(msg);
                    return SValue.nil();
                case "len":
                    if (a.size == 0) return SValue.number(0);
                    if (a[0].kind == ValueKind.LIST) return SValue.number(a[0].items.size);
                    return SValue.number(a[0].to_text().char_count());
                case "str": return SValue.text(arg_text(a, 0));
                case "num": return SValue.number(arg_num(a, 0));
                case "upper": return SValue.text(arg_text(a, 0).up());
                case "lower": return SValue.text(arg_text(a, 0).down());
                case "trim": return SValue.text(arg_text(a, 0).strip());
                case "contains": return SValue.boolean(a.size > 0 && a[0].kind == ValueKind.LIST ? list_contains(a[0], a.size > 1 ? a[1] : SValue.nil()) : arg_text(a, 0).contains(arg_text(a, 1)));
                case "starts_with": return SValue.boolean(arg_text(a, 0).has_prefix(arg_text(a, 1)));
                case "ends_with": return SValue.boolean(arg_text(a, 0).has_suffix(arg_text(a, 1)));
                case "replace": return SValue.text(string.joinv(arg_text(a, 2), arg_text(a, 0).split(arg_text(a, 1))));
                case "split":
                    var l = SValue.list();
                    foreach (string s in arg_text(a, 0).split(a.size > 1 ? arg_text(a, 1) : " ")) l.items.add(SValue.text(s));
                    return l;
                case "join":
                    if (a.size == 0 || a[0].kind != ValueKind.LIST) return SValue.text("");
                    string[] js = {};
                    foreach (var v in a[0].items) js += v.to_text();
                    return SValue.text(string.joinv(arg_text(a, 1), js));
                case "range":
                    var rl = SValue.list();
                    int from = a.size > 1 ? (int) arg_num(a, 0) : 0;
                    int to = a.size > 1 ? (int) arg_num(a, 1) : (int) arg_num(a, 0);
                    for (int i = from; i < to; i++) {
                        tick(line);
                        rl.items.add(SValue.number(i));
                    }
                    return rl;
                case "push":
                    if (a.size < 2 || a[0].kind != ValueKind.LIST) throw new ScriptError.RUNTIME(_("Line %d: push needs a list and a value").printf(line));
                    a[0].items.add(a[1]);
                    return a[0];
                case "round": return SValue.number(Math.round(arg_num(a, 0) * Math.pow(10, arg_num(a, 1))) / Math.pow(10, arg_num(a, 1)));
                case "floor": return SValue.number(Math.floor(arg_num(a, 0)));
                case "paragraphs":
                    var pl = SValue.list();
                    foreach (var p in Story.paragraphs(doc.body)) pl.items.add(para_value(p));
                    return pl;
                case "headings":
                    var hl = SValue.list();
                    foreach (var p in Story.paragraphs(doc.body)) if (doc.styles.outline_level(p) >= 0 && p.style.has_prefix("Heading")) hl.items.add(para_value(p));
                    return hl;
                case "tables":
                    var tl = SValue.list();
                    doc.walk_blocks(doc.body, (b) => {
                        if (b is Table) tl.items.add(table_value((Table) b));
                    });
                    return tl;
                case "styles":
                    var sl = SValue.list();
                    foreach (var s in doc.styles.list) sl.items.add(SValue.text(s.id));
                    return sl;
                case "style_exists": return SValue.boolean(doc.styles.get(arg_text(a, 0)) != null);
                case "current":
                    if (ed == null) return SValue.nil();
                    return para_value(ed.focus.para);
                case "selection": return SValue.text(ed != null ? ed.selected_text() : "");
                case "set_style":
                    var sp = need_para(a, 0, line);
                    sp.style = style_id(arg_text(a, 1), line);
                    touch(sp);
                    return SValue.nil();
                case "set_text":
                    set_para_text(need_para(a, 0, line), arg_text(a, 1));
                    return SValue.nil();
                case "format":
                    var fp = need_para(a, 0, line);
                    string what = arg_text(a, 1);
                    bool on = a.size < 3 || a[2].truthy();
                    foreach (var it in fp.inlines) {
                        switch (what) {
                            case "bold": it.props.bold = Tri.of(on); break;
                            case "italic": it.props.italic = Tri.of(on); break;
                            case "underline": it.props.underline = on ? Underline.SINGLE : Underline.NONE; break;
                            case "strike": it.props.strike = Tri.of(on); break;
                            case "color": it.props.color = arg_text(a, 2); break;
                            case "highlight": it.props.highlight = arg_text(a, 2); break;
                            case "size": it.props.size = arg_num(a, 2); break;
                            case "font": it.props.font = arg_text(a, 2); break;
                            default: throw new ScriptError.RUNTIME(_("Line %d: unknown format “%s”").printf(line, what));
                        }
                    }
                    touch(fp);
                    return SValue.nil();
                case "append":
                case "insert_after":
                    Paragraph np = new Paragraph(a.size > (name == "append" ? 1 : 2) ? style_id(arg_text(a, name == "append" ? 1 : 2), line) : "Normal");
                    np.insert_text(0, arg_text(a, name == "append" ? 0 : 1), new CharProps());
                    if (name == "append") {
                        var last = doc.body.size > 0 ? doc.body[doc.body.size - 1] as Paragraph : null;
                        if (last != null && last.is_empty() && doc.body.size > 1) doc.body.insert(doc.body.size - 1, np);
                        else doc.body.add(np);
                    } else {
                        var ref_p = need_para(a, 0, line);
                        if (ref_p.parent == null) throw new ScriptError.RUNTIME(_("Line %d: the paragraph is not in the document").printf(line));
                        ref_p.parent.insert(ref_p.parent.items.index_of(ref_p) + 1, np);
                    }
                    changed = true;
                    return para_value(np);
                case "delete":
                    var dp = need_para(a, 0, line);
                    if (dp.parent != null) {
                        var list = dp.parent;
                        list.items.remove(dp);
                        if (list.size == 0) list.add(new Paragraph());
                        changed = true;
                    }
                    return SValue.nil();
                case "cell":
                    var ct = need_table(a, 0, line);
                    var cell = cell_of(ct, (int) arg_num(a, 1), (int) arg_num(a, 2), line);
                    var sb = new StringBuilder();
                    foreach (var p in Story.paragraphs(cell.blocks)) {
                        if (sb.len > 0) sb.append_c('\n');
                        sb.append(p.plain_text());
                    }
                    return SValue.text(sb.str);
                case "set_cell":
                    var st = need_table(a, 0, line);
                    var sc = cell_of(st, (int) arg_num(a, 1), (int) arg_num(a, 2), line);
                    var first = sc.blocks.first_paragraph();
                    if (first == null) {
                        first = new Paragraph();
                        sc.blocks.add(first);
                    }
                    while (sc.blocks.size > 1) sc.blocks.items.remove_at(sc.blocks.size - 1);
                    set_para_text(first, arg_text(a, 3));
                    st.touch();
                    return SValue.nil();
                case "add_row":
                    var at = need_table(a, 0, line);
                    var last_row = at.rows[at.rows.size - 1];
                    var nr = last_row.copy();
                    foreach (var c in nr.cells) {
                        c.blocks.items.clear();
                        c.blocks.add(new Paragraph());
                    }
                    at.rows.add(nr);
                    at.touch();
                    changed = true;
                    return SValue.number(at.rows.size - 1);
                case "insert_table":
                    int rows = int.max(1, (int) arg_num(a, 0));
                    int cols = int.max(1, (int) arg_num(a, 1));
                    var t = Table.create(rows, cols, doc.final_section.column_width());
                    var last = doc.body.size > 0 ? doc.body[doc.body.size - 1] as Paragraph : null;
                    if (last != null && last.is_empty()) doc.body.insert(doc.body.size - 1, t);
                    else {
                        doc.body.add(t);
                        doc.body.add(new Paragraph());
                    }
                    changed = true;
                    return table_value(t);
                case "find":
                    var fl = SValue.list();
                    string needle = arg_text(a, 0);
                    foreach (var p in Story.paragraphs(doc.body)) if (needle != "" && p.plain_text().contains(needle)) fl.items.add(para_value(p));
                    return fl;
                case "replace_all":
                    var fo = new FindOptions();
                    fo.query = arg_text(a, 0);
                    int count = 0;
                    try {
                        foreach (var m in Finder.find_all(doc, fo)) count++;
                        if (ed != null && count > 0) Finder.replace_all(ed, fo, arg_text(a, 1), null);
                    } catch (RegexError e) {
                        throw new ScriptError.RUNTIME(e.message);
                    }
                    if (count > 0) changed = true;
                    return SValue.number(count);
                case "word_count": return SValue.number(Stats.compute(doc, false).words);
                case "title": return SValue.text(doc.meta.title);
                case "set_title":
                    doc.meta.title = arg_text(a, 0);
                    changed = true;
                    return SValue.nil();
                case "variable": return SValue.text(doc.variables[arg_text(a, 0)] ?? "");
                case "set_variable":
                    doc.variables[arg_text(a, 0)] = arg_text(a, 1);
                    changed = true;
                    return SValue.nil();
                case "run":
                    if (on_action == null) return SValue.boolean(false);
                    bool ok = on_action(arg_text(a, 0), a.size > 1 ? arg_text(a, 1) : null);
                    changed = true;
                    return SValue.boolean(ok);
                case "goto":
                    if (ed == null) return SValue.nil();
                    var gp = need_para(a, 0, line);
                    int go = a.size > 1 ? (int) arg_num(a, 1) : gp.length;
                    ed.set_caret(new Pos(gp, go.clamp(0, gp.length)));
                    return SValue.nil();
                case "select":
                    if (ed == null) return SValue.nil();
                    var selp = need_para(a, 0, line);
                    int s0 = ((int) arg_num(a, 1)).clamp(0, selp.length);
                    int s1 = (a.size > 2 ? (int) arg_num(a, 2) : selp.length).clamp(0, selp.length);
                    ed.select(new Pos(selp, s0), new Pos(selp, s1));
                    return SValue.nil();
                case "type":
                    if (ed == null) return SValue.nil();
                    ed.insert_text(arg_text(a, 0), ed.props_for_insert());
                    changed = true;
                    return SValue.nil();
                default:
                    throw new ScriptError.RUNTIME(_("Line %d: unknown function “%s”").printf(line, name));
            }
        }

        private static bool list_contains(SValue l, SValue v) {
            foreach (var i in l.items) if (equal(i, v)) return true;
            return false;
        }
    }
}
