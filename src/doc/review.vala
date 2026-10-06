namespace Write {

    public class RevisionRef : Object {
        public Paragraph para;
        public Inline? item;
        public TableRow? row;
        public Revision rev;
        public int offset;
        public bool mark;
        public bool para_props;

        public string description() {
            switch (rev.kind) {
                case RevKind.INSERT:
                    if (mark) return _("Inserted paragraph");
                    if (row != null) return _("Inserted row");
                    return _("Inserted: %s").printf(snippet());
                case RevKind.DELETE:
                    if (mark) return _("Deleted paragraph mark");
                    if (row != null) return _("Deleted row");
                    return _("Deleted: %s").printf(snippet());
                default:
                    if (para_props) return _("Paragraph formatting changed");
                    return _("Formatted: %s").printf(snippet());
            }
        }

        private string snippet() {
            if (item is TextRun) {
                string t = ((TextRun) item).text;
                return t.char_count() > 40 ? usub(t, 0, 40) + "…" : t;
            }
            if (item is ImageRun) return _("picture");
            if (item is Tab) return _("tab");
            return _("object");
        }
    }

    public class Review : Object {

        public static Gee.ArrayList<RevisionRef> collect(Document doc) {
            var list = new Gee.ArrayList<RevisionRef>();
            collect_list(doc, doc.body, list);
            foreach (var hf in doc.header_footers()) collect_list(doc, hf.blocks, list);
            foreach (var n in doc.notes()) collect_list(doc, n.blocks, list);
            return list;
        }

        private static void collect_list(Document doc, BlockList bl, Gee.ArrayList<RevisionRef> list) {
            foreach (var b in bl.items) {
                var t = b as Table;
                if (t != null) {
                    foreach (var r in t.rows) {
                        if (r.rev != null && r.cells.size > 0) {
                            var rr = new RevisionRef();
                            rr.para = r.cells[0].blocks.first_paragraph() ?? new Paragraph();
                            rr.row = r;
                            rr.rev = r.rev;
                            list.add(rr);
                        }
                        foreach (var c in r.cells) collect_list(doc, c.blocks, list);
                    }
                    continue;
                }
                var fb = b as FieldBlock;
                if (fb != null) {
                    collect_list(doc, fb.result, list);
                    continue;
                }
                var p = b as Paragraph;
                if (p == null) continue;
                int off = 0;
                foreach (var it in p.inlines) {
                    if (it.rev != null) {
                        var rr = new RevisionRef();
                        rr.para = p;
                        rr.item = it;
                        rr.rev = it.rev;
                        rr.offset = off;
                        list.add(rr);
                    } else if (it.fmt_rev != null) {
                        var rr = new RevisionRef();
                        rr.para = p;
                        rr.item = it;
                        rr.rev = it.fmt_rev;
                        rr.offset = off;
                        list.add(rr);
                    }
                    off += it.length;
                }
                if (p.props_rev != null) {
                    var pr = new RevisionRef();
                    pr.para = p;
                    pr.rev = p.props_rev;
                    pr.offset = 0;
                    pr.para_props = true;
                    list.add(pr);
                }
                if (p.mark_rev != null) {
                    var rr = new RevisionRef();
                    rr.para = p;
                    rr.rev = p.mark_rev;
                    rr.offset = p.length;
                    rr.mark = true;
                    list.add(rr);
                }
            }
        }

        public static void resolve(Document doc, RevisionRef r, bool accept) {
            if (r.row != null) {
                var t = doc.find_table_of(r.row.cells[0]);
                bool remove = (r.rev.kind == RevKind.DELETE) == accept;
                if (remove && t != null) {
                    t.rows.remove(r.row);
                    if (t.rows.size == 0 && t.parent != null) {
                        var list = t.parent;
                        int i = list.items.index_of(t);
                        list.remove_at(i);
                        if (list.size == 0) list.add(new Paragraph());
                    }
                } else {
                    r.row.rev = null;
                }
                return;
            }
            var p = r.para;
            if (r.para_props) {
                if (!accept) {
                    if (p.props_old != null) p.props = p.props_old.copy();
                    if (p.style_old != null) p.style = p.style_old;
                }
                p.props_rev = null;
                p.props_old = null;
                p.style_old = null;
                p.touch();
                return;
            }
            if (r.mark) {
                bool join = (r.rev.kind == RevKind.DELETE) == accept;
                p.mark_rev = null;
                if (join) join_next(p);
                p.touch();
                return;
            }
            var it = r.item;
            if (it == null) return;
            if (r.rev.kind == RevKind.FORMAT) {
                if (!accept && it.fmt_old != null) {
                    var link = it.props.link;
                    it.props = it.fmt_old.copy();
                    it.props.link = link;
                }
                it.fmt_rev = null;
                it.fmt_old = null;
            } else {
                bool remove = (r.rev.kind == RevKind.DELETE) == accept;
                if (remove) p.inlines.remove(it);
                else it.rev = null;
            }
            p.normalize();
            p.touch();
        }

        private static void join_next(Paragraph p) {
            var list = p.parent;
            if (list == null) return;
            int i = list.items.index_of(p);
            if (i + 1 >= list.size) {
                if (p.is_empty() && list.size > 1) list.remove_at(i);
                return;
            }
            var n = list[i + 1] as Paragraph;
            if (n == null) return;
            p.append_from(n);
            list.remove_at(i + 1);
        }

        public static int resolve_all(Document doc, bool accept, string? author = null) {
            int count = 0;
            for (int guard = 0; guard < 100000; guard++) {
                var list = collect(doc);
                RevisionRef? target = null;
                foreach (var r in list) {
                    if (author != null && r.rev.author != author) continue;
                    target = r;
                    break;
                }
                if (target == null) break;
                resolve(doc, target, accept);
                count++;
            }
            return count;
        }

        public static Gee.ArrayList<string> authors(Document doc) {
            var set = new Gee.ArrayList<string>();
            foreach (var r in collect(doc)) if (!set.contains(r.rev.author)) set.add(r.rev.author);
            foreach (var c in doc.comments) if (!set.contains(c.author)) set.add(c.author);
            return set;
        }

        private static string[] words(string s) {
            string[] out_words = {};
            var sb = new StringBuilder();
            int kind = -1;
            unichar c;
            int i = 0;
            while (s.get_next_char(ref i, out c)) {
                int k = c.isspace() ? 0 : (c.isalnum() ? 1 : 2);
                if (sb.len > 0 && (k != kind || k == 2)) {
                    out_words += sb.str;
                    sb.truncate(0);
                }
                sb.append_unichar(c);
                kind = k;
            }
            if (sb.len > 0) out_words += sb.str;
            return out_words;
        }

        private static int[,] lcs_table(string[] a, string[] b) {
            int n = a.length;
            int m = b.length;
            var t = new int[n + 1, m + 1];
            for (int i = n - 1; i >= 0; i--) {
                for (int j = m - 1; j >= 0; j--) {
                    if (a[i] == b[j]) t[i, j] = t[i + 1, j + 1] + 1;
                    else t[i, j] = int.max(t[i + 1, j], t[i, j + 1]);
                }
            }
            return t;
        }

        public static Document compare(Document original, Document revised, string author) {
            var result = revised.copy();
            var date = new DateTime.now_utc().format("%Y-%m-%dT%H:%M:%SZ");
            var orig_paras = new Gee.ArrayList<Paragraph>();
            foreach (var b in original.body.items) if (b is Paragraph) orig_paras.add((Paragraph) b);
            var rev_paras = new Gee.ArrayList<Paragraph>();
            foreach (var b in result.body.items) if (b is Paragraph) rev_paras.add((Paragraph) b);
            string[] ta = new string[orig_paras.size];
            string[] tb = new string[rev_paras.size];
            for (int i = 0; i < ta.length; i++) ta[i] = orig_paras[i].plain_text();
            for (int i = 0; i < tb.length; i++) tb[i] = rev_paras[i].plain_text();
            var t = lcs_table(ta, tb);
            int x = 0, y = 0;
            var ops = new Gee.ArrayList<int>();
            while (x < ta.length || y < tb.length) {
                if (x < ta.length && y < tb.length && ta[x] == tb[y]) {
                    ops.add(0);
                    x++;
                    y++;
                } else if (x < ta.length && y < tb.length && similar(ta[x], tb[y]) && (t[x + 1, y + 1] >= t[x + 1, y] && t[x + 1, y + 1] >= t[x, y + 1])) {
                    ops.add(3);
                    x++;
                    y++;
                } else if (y < tb.length && (x >= ta.length || t[x, y + 1] >= t[x + 1, y])) {
                    ops.add(1);
                    y++;
                } else {
                    ops.add(2);
                    x++;
                }
            }
            x = 0;
            y = 0;
            int insert_pos = 0;
            foreach (int op in ops) {
                switch (op) {
                    case 0:
                        insert_pos = result.body.items.index_of(rev_paras[y]) + 1;
                        x++;
                        y++;
                        break;
                    case 1:
                        var rp = rev_paras[y];
                        foreach (var it in rp.inlines) if (it.length > 0) it.rev = new Revision(RevKind.INSERT, author, date);
                        rp.mark_rev = new Revision(RevKind.INSERT, author, date);
                        insert_pos = result.body.items.index_of(rp) + 1;
                        y++;
                        break;
                    case 2:
                        var dp = (Paragraph) orig_paras[x].copy();
                        foreach (var it in dp.inlines) if (it.length > 0) it.rev = new Revision(RevKind.DELETE, author, date);
                        dp.mark_rev = new Revision(RevKind.DELETE, author, date);
                        dp.section = null;
                        result.body.insert(insert_pos, dp);
                        insert_pos++;
                        x++;
                        break;
                    default:
                        diff_paragraph(orig_paras[x], rev_paras[y], author, date);
                        insert_pos = result.body.items.index_of(rev_paras[y]) + 1;
                        x++;
                        y++;
                        break;
                }
            }
            result.track_changes = true;
            return result;
        }

        private static bool similar(string a, string b) {
            string[] wa = words(a);
            string[] wb = words(b);
            if (wa.length == 0 || wb.length == 0) return false;
            var t = lcs_table(wa, wb);
            int common = t[0, 0];
            return common * 2 >= int.max(wa.length, wb.length);
        }

        private static void diff_paragraph(Paragraph orig, Paragraph rev, string author, string date) {
            string[] wa = words(orig.plain_text());
            string[] wb = words(rev.plain_text());
            var t = lcs_table(wa, wb);
            var rebuilt = new Gee.ArrayList<Inline>();
            int i = 0, j = 0;
            int rev_off = 0;
            var props_src = rev;
            while (i < wa.length || j < wb.length) {
                if (i < wa.length && j < wb.length && wa[i] == wb[j]) {
                    append_slice(rebuilt, props_src, rev_off, rev_off + wb[j].char_count(), null);
                    rev_off += wb[j].char_count();
                    i++;
                    j++;
                } else if (j < wb.length && (i >= wa.length || t[i, j + 1] >= t[i + 1, j])) {
                    append_slice(rebuilt, props_src, rev_off, rev_off + wb[j].char_count(), new Revision(RevKind.INSERT, author, date));
                    rev_off += wb[j].char_count();
                    j++;
                } else {
                    var d = new TextRun(wa[i], orig.props_at(0));
                    d.rev = new Revision(RevKind.DELETE, author, date);
                    rebuilt.add(d);
                    i++;
                }
            }
            if (rebuilt.size == 0) return;
            bool plain = true;
            foreach (var it in rev.inlines) if (!(it is TextRun) && !(it is Tab) && it.length > 0) plain = false;
            if (!plain) return;
            rev.inlines.clear();
            rev.inlines.add_all(rebuilt);
            rev.normalize();
        }

        private static void append_slice(Gee.ArrayList<Inline> into, Paragraph src, int s, int e, Revision? r) {
            var text = src.plain_text();
            string piece = usub(text, s, e);
            var cp = src.props_at(s + 1);
            var run = new TextRun(piece, cp);
            run.rev = r;
            into.add(run);
        }
    }
}
