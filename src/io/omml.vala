namespace Write {

    public class Omml : Object {
        public const string MATH_NS = "http://www.w3.org/1998/Math/MathML";

        public static string? to_mathml(string omml, bool display) {
            string src = omml;
            if (!src.contains("xmlns:m=")) {
                int gt = src.index_of_char('>');
                int sp = src.index_of_char(' ');
                int cut = sp > 0 && sp < gt ? sp : gt;
                if (cut > 0) src = src.substring(0, cut) + " xmlns:m=\"http://schemas.openxmlformats.org/officeDocument/2006/math\" xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"" + src.substring(cut);
            }
            try {
                Xml.Doc* x = X.parse(src);
                var sb = new StringBuilder();
                sb.append("<math xmlns=\"%s\" display=\"%s\">".printf(MATH_NS, display ? "block" : "inline"));
                Xml.Node* root = x->get_root_element();
                if (root->name == "oMathPara") {
                    var maths = X.kids(root, "oMath");
                    if (maths.size == 1) children(maths[0], sb);
                    else {
                        sb.append("<mtable>");
                        foreach (var m in maths) {
                            sb.append("<mtr><mtd>");
                            children(m, sb);
                            sb.append("</mtd></mtr>");
                        }
                        sb.append("</mtable>");
                    }
                } else {
                    children(root, sb);
                }
                sb.append("</math>");
                delete x;
                return sb.str;
            } catch (Error e) {
                return null;
            }
        }

        private static string esc(string s) {
            return X.esc(s);
        }

        private static void row(Xml.Node* n, StringBuilder sb) {
            if (n == null) {
                sb.append("<mrow/>");
                return;
            }
            sb.append("<mrow>");
            children(n, sb);
            sb.append("</mrow>");
        }

        private static void children(Xml.Node* n, StringBuilder sb) {
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type == Xml.ElementType.ELEMENT_NODE) node(c, sb);
            }
        }

        private static string chr_attr(Xml.Node* pr, string name, string fallback) {
            if (pr == null) return fallback;
            Xml.Node* c = X.child(pr, name);
            if (c == null) return fallback;
            return X.attr(c, "val") ?? fallback;
        }

        private static void text_run(string t, bool plain, StringBuilder sb) {
            if (plain) {
                sb.append("<mtext>%s</mtext>".printf(esc(t)));
                return;
            }
            var num = new StringBuilder();
            unichar c;
            int i = 0;
            while (t.get_next_char(ref i, out c)) {
                if (c.isdigit() || (c == '.' && num.len > 0)) {
                    num.append_unichar(c);
                    continue;
                }
                if (num.len > 0) {
                    sb.append("<mn>%s</mn>".printf(num.str));
                    num.truncate(0);
                }
                if (c == ' ') continue;
                string s = c.to_string();
                if (c.isalpha()) sb.append("<mi>%s</mi>".printf(esc(s)));
                else sb.append("<mo>%s</mo>".printf(esc(s)));
            }
            if (num.len > 0) sb.append("<mn>%s</mn>".printf(num.str));
        }

        private static void node(Xml.Node* n, StringBuilder sb) {
            switch (n->name) {
                case "r":
                    var t = new StringBuilder();
                    foreach (var tn in X.kids(n, "t")) t.append(X.text(tn));
                    Xml.Node* rpr = X.child(n, "rPr");
                    bool plain = rpr != null && X.child(rpr, "nor") != null;
                    text_run(t.str, plain, sb);
                    break;
                case "f":
                    Xml.Node* fpr = X.child(n, "fPr");
                    string type = chr_attr(fpr, "type", "bar");
                    sb.append(type == "lin" || type == "skw" ? "<mfrac bevelled=\"true\">" : (type == "noBar" ? "<mfrac linethickness=\"0\">" : "<mfrac>"));
                    row(X.child(n, "num"), sb);
                    row(X.child(n, "den"), sb);
                    sb.append("</mfrac>");
                    break;
                case "sSup":
                    sb.append("<msup>");
                    row(X.child(n, "e"), sb);
                    row(X.child(n, "sup"), sb);
                    sb.append("</msup>");
                    break;
                case "sSub":
                    sb.append("<msub>");
                    row(X.child(n, "e"), sb);
                    row(X.child(n, "sub"), sb);
                    sb.append("</msub>");
                    break;
                case "sSubSup":
                    sb.append("<msubsup>");
                    row(X.child(n, "e"), sb);
                    row(X.child(n, "sub"), sb);
                    row(X.child(n, "sup"), sb);
                    sb.append("</msubsup>");
                    break;
                case "sPre":
                    sb.append("<mmultiscripts>");
                    row(X.child(n, "e"), sb);
                    sb.append("<mprescripts/>");
                    row(X.child(n, "sub"), sb);
                    row(X.child(n, "sup"), sb);
                    sb.append("</mmultiscripts>");
                    break;
                case "rad":
                    Xml.Node* rpr2 = X.child(n, "radPr");
                    Xml.Node* deg = X.child(n, "deg");
                    bool hide = rpr2 != null && X.child(rpr2, "degHide") != null && chr_attr(rpr2, "degHide", "1") != "0";
                    if (deg == null || hide || deg->children == null) {
                        sb.append("<msqrt>");
                        row(X.child(n, "e"), sb);
                        sb.append("</msqrt>");
                    } else {
                        sb.append("<mroot>");
                        row(X.child(n, "e"), sb);
                        row(deg, sb);
                        sb.append("</mroot>");
                    }
                    break;
                case "d":
                    Xml.Node* dpr = X.child(n, "dPr");
                    string beg = chr_attr(dpr, "begChr", "(");
                    string end = chr_attr(dpr, "endChr", ")");
                    string sep = chr_attr(dpr, "sepChr", "|");
                    sb.append("<mrow>");
                    if (beg != "") sb.append("<mo fence=\"true\">%s</mo>".printf(esc(beg)));
                    bool first = true;
                    foreach (var e in X.kids(n, "e")) {
                        if (!first) sb.append("<mo separator=\"true\">%s</mo>".printf(esc(sep)));
                        row(e, sb);
                        first = false;
                    }
                    if (end != "") sb.append("<mo fence=\"true\">%s</mo>".printf(esc(end)));
                    sb.append("</mrow>");
                    break;
                case "nary":
                    Xml.Node* npr = X.child(n, "naryPr");
                    string op = chr_attr(npr, "chr", "∫");
                    bool under = chr_attr(npr, "limLoc", op == "∫" ? "subSup" : "undOvr") == "undOvr";
                    Xml.Node* sub = X.child(n, "sub");
                    Xml.Node* sup = X.child(n, "sup");
                    bool has_sub = sub != null && sub->children != null && !(npr != null && X.child(npr, "subHide") != null);
                    bool has_sup = sup != null && sup->children != null && !(npr != null && X.child(npr, "supHide") != null);
                    sb.append("<mrow>");
                    string opm = "<mo largeop=\"true\">%s</mo>".printf(esc(op));
                    if (has_sub && has_sup) {
                        sb.append(under ? "<munderover>" : "<msubsup>");
                        sb.append(opm);
                        row(sub, sb);
                        row(sup, sb);
                        sb.append(under ? "</munderover>" : "</msubsup>");
                    } else if (has_sub) {
                        sb.append(under ? "<munder>" : "<msub>");
                        sb.append(opm);
                        row(sub, sb);
                        sb.append(under ? "</munder>" : "</msub>");
                    } else if (has_sup) {
                        sb.append(under ? "<mover>" : "<msup>");
                        sb.append(opm);
                        row(sup, sb);
                        sb.append(under ? "</mover>" : "</msup>");
                    } else {
                        sb.append(opm);
                    }
                    row(X.child(n, "e"), sb);
                    sb.append("</mrow>");
                    break;
                case "acc":
                    string ac = chr_attr(X.child(n, "accPr"), "chr", "̂");
                    sb.append("<mover accent=\"true\">");
                    row(X.child(n, "e"), sb);
                    sb.append("<mo>%s</mo></mover>".printf(esc(ac)));
                    break;
                case "bar":
                    bool top = chr_attr(X.child(n, "barPr"), "pos", "bot") == "top";
                    sb.append(top ? "<mover>" : "<munder>");
                    row(X.child(n, "e"), sb);
                    sb.append(top ? "<mo>¯</mo></mover>" : "<mo>_</mo></munder>");
                    break;
                case "groupChr":
                    Xml.Node* gpr = X.child(n, "groupChrPr");
                    string gc = chr_attr(gpr, "chr", "⏟");
                    bool gtop = chr_attr(gpr, "pos", "bot") == "top";
                    sb.append(gtop ? "<mover>" : "<munder>");
                    row(X.child(n, "e"), sb);
                    sb.append("<mo>%s</mo>".printf(esc(gc)));
                    sb.append(gtop ? "</mover>" : "</munder>");
                    break;
                case "limLow":
                    sb.append("<munder>");
                    row(X.child(n, "e"), sb);
                    row(X.child(n, "lim"), sb);
                    sb.append("</munder>");
                    break;
                case "limUpp":
                    sb.append("<mover>");
                    row(X.child(n, "e"), sb);
                    row(X.child(n, "lim"), sb);
                    sb.append("</mover>");
                    break;
                case "func":
                    sb.append("<mrow>");
                    row(X.child(n, "fName"), sb);
                    sb.append("<mo>⁡</mo>");
                    row(X.child(n, "e"), sb);
                    sb.append("</mrow>");
                    break;
                case "m":
                    sb.append("<mtable>");
                    foreach (var mr in X.kids(n, "mr")) {
                        sb.append("<mtr>");
                        foreach (var e in X.kids(mr, "e")) {
                            sb.append("<mtd>");
                            row(e, sb);
                            sb.append("</mtd>");
                        }
                        sb.append("</mtr>");
                    }
                    sb.append("</mtable>");
                    break;
                case "eqArr":
                    sb.append("<mtable>");
                    foreach (var e in X.kids(n, "e")) {
                        sb.append("<mtr><mtd>");
                        row(e, sb);
                        sb.append("</mtd></mtr>");
                    }
                    sb.append("</mtable>");
                    break;
                case "box":
                case "borderBox":
                case "phant":
                    row(X.child(n, "e"), sb);
                    break;
                case "oMath":
                    row(n, sb);
                    break;
                default:
                    if (n->name.has_suffix("Pr") || n->name == "ctrlPr") break;
                    children(n, sb);
                    break;
            }
        }

        public static string? from_mathml(string mathml, bool display) {
            try {
                Xml.Doc* x = X.parse(mathml);
                var sb = new StringBuilder();
                Xml.Node* root = x->get_root_element();
                sb.append("<m:oMath xmlns:m=\"http://schemas.openxmlformats.org/officeDocument/2006/math\">");
                mchildren(root, sb);
                sb.append("</m:oMath>");
                delete x;
                string r = sb.str;
                if (display) r = "<m:oMathPara xmlns:m=\"http://schemas.openxmlformats.org/officeDocument/2006/math\">" + r + "</m:oMathPara>";
                return r;
            } catch (Error e) {
                return null;
            }
        }

        private static void mchildren(Xml.Node* n, StringBuilder sb) {
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type == Xml.ElementType.ELEMENT_NODE) mnode(c, sb);
            }
        }

        private static Xml.Node* nth(Xml.Node* n, int i) {
            int k = 0;
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                if (k == i) return c;
                k++;
            }
            return null;
        }

        private static void marg(string tag, Xml.Node* n, StringBuilder sb) {
            sb.append("<m:%s>".printf(tag));
            if (n != null) mnode(n, sb);
            sb.append("</m:%s>".printf(tag));
        }

        private static void mrun(string text, bool plain, StringBuilder sb) {
            if (text == "") return;
            sb.append("<m:r>");
            if (plain) sb.append("<m:rPr><m:nor/></m:rPr>");
            sb.append("<m:t xml:space=\"preserve\">%s</m:t></m:r>".printf(X.esc(text)));
        }

        private static void mnode(Xml.Node* n, StringBuilder sb) {
            switch (n->name) {
                case "mi":
                case "mn":
                case "mo":
                    mrun(X.text(n).strip(), false, sb);
                    break;
                case "mtext":
                case "ms":
                    mrun(X.text(n), true, sb);
                    break;
                case "mspace":
                    mrun(" ", false, sb);
                    break;
                case "mrow":
                case "mstyle":
                case "mpadded":
                case "mphantom":
                case "math":
                case "semantics":
                    if (n->name == "semantics") {
                        Xml.Node* first = nth(n, 0);
                        if (first != null) mnode(first, sb);
                        break;
                    }
                    mchildren(n, sb);
                    break;
                case "annotation":
                case "annotation-xml":
                    break;
                case "mfrac":
                    string lt = X.attr(n, "linethickness") ?? "";
                    sb.append("<m:f>");
                    if (X.attr(n, "bevelled") == "true") sb.append("<m:fPr><m:type m:val=\"skw\"/></m:fPr>");
                    else if (lt == "0" || lt == "0px") sb.append("<m:fPr><m:type m:val=\"noBar\"/></m:fPr>");
                    marg("num", nth(n, 0), sb);
                    marg("den", nth(n, 1), sb);
                    sb.append("</m:f>");
                    break;
                case "msup":
                    sb.append("<m:sSup>");
                    marg("e", nth(n, 0), sb);
                    marg("sup", nth(n, 1), sb);
                    sb.append("</m:sSup>");
                    break;
                case "msub":
                    if (is_largeop(nth(n, 0))) {
                        nary(n, nth(n, 1), null, false, sb);
                        break;
                    }
                    sb.append("<m:sSub>");
                    marg("e", nth(n, 0), sb);
                    marg("sub", nth(n, 1), sb);
                    sb.append("</m:sSub>");
                    break;
                case "msubsup":
                    if (is_largeop(nth(n, 0))) {
                        nary(n, nth(n, 1), nth(n, 2), false, sb);
                        break;
                    }
                    sb.append("<m:sSubSup>");
                    marg("e", nth(n, 0), sb);
                    marg("sub", nth(n, 1), sb);
                    marg("sup", nth(n, 2), sb);
                    sb.append("</m:sSubSup>");
                    break;
                case "munderover":
                    if (is_largeop(nth(n, 0))) {
                        nary(n, nth(n, 1), nth(n, 2), true, sb);
                        break;
                    }
                    sb.append("<m:limUpp><m:e><m:limLow>");
                    marg("e", nth(n, 0), sb);
                    marg("lim", nth(n, 1), sb);
                    sb.append("</m:limLow></m:e>");
                    marg("lim", nth(n, 2), sb);
                    sb.append("</m:limUpp>");
                    break;
                case "munder":
                    if (is_largeop(nth(n, 0))) {
                        nary(n, nth(n, 1), null, true, sb);
                        break;
                    }
                    sb.append("<m:limLow>");
                    marg("e", nth(n, 0), sb);
                    marg("lim", nth(n, 1), sb);
                    sb.append("</m:limLow>");
                    break;
                case "mover":
                    Xml.Node* over = nth(n, 1);
                    if (over != null && over->name == "mo" && (X.attr(n, "accent") == "true" || X.text(over).char_count() == 1)) {
                        string ch = X.text(over).strip();
                        if (ch == "¯" || ch == "‾") {
                            sb.append("<m:bar><m:barPr><m:pos m:val=\"top\"/></m:barPr>");
                            marg("e", nth(n, 0), sb);
                            sb.append("</m:bar>");
                        } else {
                            sb.append("<m:acc><m:accPr><m:chr m:val=\"%s\"/></m:accPr>".printf(X.esc(ch)));
                            marg("e", nth(n, 0), sb);
                            sb.append("</m:acc>");
                        }
                        break;
                    }
                    if (is_largeop(nth(n, 0))) {
                        nary(n, null, over, true, sb);
                        break;
                    }
                    sb.append("<m:limUpp>");
                    marg("e", nth(n, 0), sb);
                    marg("lim", over, sb);
                    sb.append("</m:limUpp>");
                    break;
                case "msqrt":
                    sb.append("<m:rad><m:radPr><m:degHide m:val=\"1\"/></m:radPr><m:deg/><m:e>");
                    mchildren(n, sb);
                    sb.append("</m:e></m:rad>");
                    break;
                case "mroot":
                    sb.append("<m:rad>");
                    marg("deg", nth(n, 1), sb);
                    marg("e", nth(n, 0), sb);
                    sb.append("</m:rad>");
                    break;
                case "mfenced":
                    string open = X.attr(n, "open") ?? "(";
                    string close = X.attr(n, "close") ?? ")";
                    sb.append("<m:d><m:dPr><m:begChr m:val=\"%s\"/><m:endChr m:val=\"%s\"/></m:dPr>".printf(X.esc(open), X.esc(close)));
                    for (Xml.Node* c = n->children; c != null; c = c->next) {
                        if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                        marg("e", c, sb);
                    }
                    sb.append("</m:d>");
                    break;
                case "mtable":
                    sb.append("<m:m>");
                    foreach (var tr in X.kids(n, "mtr")) {
                        sb.append("<m:mr>");
                        foreach (var td in X.kids(tr, "mtd")) {
                            sb.append("<m:e>");
                            mchildren(td, sb);
                            sb.append("</m:e>");
                        }
                        sb.append("</m:mr>");
                    }
                    sb.append("</m:m>");
                    break;
                case "mmultiscripts":
                    sb.append("<m:sPre>");
                    Xml.Node* base_n = nth(n, 0);
                    int presc = -1;
                    for (int i = 0; nth(n, i) != null; i++) if (nth(n, i)->name == "mprescripts") presc = i;
                    marg("sub", presc >= 0 ? nth(n, presc + 1) : null, sb);
                    marg("sup", presc >= 0 ? nth(n, presc + 2) : null, sb);
                    marg("e", base_n, sb);
                    sb.append("</m:sPre>");
                    break;
                case "menclose":
                    sb.append("<m:borderBox><m:e>");
                    mchildren(n, sb);
                    sb.append("</m:e></m:borderBox>");
                    break;
                default:
                    mchildren(n, sb);
                    break;
            }
        }

        private static bool is_largeop(Xml.Node* n) {
            if (n == null || n->name != "mo") return false;
            string t = X.text(n).strip();
            return t == "∑" || t == "∏" || t == "∫" || t == "∬" || t == "∭" || t == "∮" || t == "⋃" || t == "⋂" || t == "∐";
        }

        private static void nary(Xml.Node* n, Xml.Node* sub, Xml.Node* sup, bool under, StringBuilder sb) {
            string op = X.text(nth(n, 0)).strip();
            sb.append("<m:nary><m:naryPr><m:chr m:val=\"%s\"/><m:limLoc m:val=\"%s\"/>".printf(X.esc(op), under ? "undOvr" : "subSup"));
            if (sub == null) sb.append("<m:subHide m:val=\"1\"/>");
            if (sup == null) sb.append("<m:supHide m:val=\"1\"/>");
            sb.append("</m:naryPr>");
            marg("sub", sub, sb);
            marg("sup", sup, sb);
            sb.append("<m:e/></m:nary>");
        }

        public static string text_of(string xml) {
            var sb = new StringBuilder();
            bool tag = false;
            unichar c;
            int i = 0;
            while (xml.get_next_char(ref i, out c)) {
                if (c == '<') tag = true;
                else if (c == '>') tag = false;
                else if (!tag) sb.append_unichar(c);
            }
            return sb.str.replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">").strip();
        }
    }
}
