namespace Write {

    public class Pos : Object {
        public Paragraph para;
        public int offset;

        public Pos(Paragraph para, int offset) {
            this.para = para;
            this.offset = offset.clamp(0, para.length);
        }

        public Pos copy() {
            return new Pos(para, offset);
        }

        public bool same(Pos o) {
            return para == o.para && offset == o.offset;
        }
    }

    public class Story : Object {

        public static BlockList root_of(Document doc, Paragraph p) {
            BlockList? list = p.parent;
            int guard = 0;
            while (list != null && guard++ < 64) {
                var owner = list.owner;
                if (owner is TableCell) {
                    var t = doc.find_table_of((TableCell) owner);
                    if (t == null || t.parent == null) return list;
                    list = t.parent;
                    continue;
                }
                if (owner is FieldBlock) {
                    var fb = (FieldBlock) owner;
                    if (fb.parent == null) return list;
                    list = fb.parent;
                    continue;
                }
                return list;
            }
            return doc.body;
        }

        public static Gee.ArrayList<Paragraph> paragraphs(BlockList root) {
            var list = new Gee.ArrayList<Paragraph>();
            collect(root, list);
            return list;
        }

        private static void collect(BlockList l, Gee.ArrayList<Paragraph> into) {
            foreach (var b in l.items) {
                if (b is Paragraph) into.add((Paragraph) b);
                else if (b is Table) {
                    foreach (var r in ((Table) b).rows) foreach (var c in r.cells) collect(c.blocks, into);
                } else if (b is FieldBlock) collect(((FieldBlock) b).result, into);
            }
        }

        public static int compare(Document doc, Pos a, Pos b) {
            if (a.para == b.para) return a.offset - b.offset;
            var list = paragraphs(root_of(doc, a.para));
            int ia = list.index_of(a.para);
            int ib = list.index_of(b.para);
            return ia - ib;
        }

        public static Gee.ArrayList<Paragraph> between(Document doc, Pos a, Pos b) {
            var result = new Gee.ArrayList<Paragraph>();
            if (a.para == b.para) {
                result.add(a.para);
                return result;
            }
            var list = paragraphs(root_of(doc, a.para));
            int ia = list.index_of(a.para);
            int ib = list.index_of(b.para);
            if (ia < 0 || ib < 0) {
                result.add(a.para);
                return result;
            }
            if (ia > ib) {
                int t = ia;
                ia = ib;
                ib = t;
            }
            for (int i = ia; i <= ib; i++) result.add(list[i]);
            return result;
        }

        public static Gee.ArrayList<Paragraph> all(Document doc) {
            var list = paragraphs(doc.body);
            foreach (var hf in doc.header_footers()) list.add_all(paragraphs(hf.blocks));
            foreach (var n in doc.notes()) list.add_all(paragraphs(n.blocks));
            foreach (var c in doc.comments) list.add_all(paragraphs(c.blocks));
            var shapes = new Gee.ArrayList<ShapeRun>();
            foreach (var p in paragraphs(doc.body)) foreach (var i in p.inlines) if (i is ShapeRun) shapes.add((ShapeRun) i);
            foreach (var s in shapes) list.add_all(paragraphs(s.text));
            return list;
        }
    }

    public class Snapshot : Object {
        public Document doc;
        public int anchor_para;
        public int anchor_off;
        public int focus_para;
        public int focus_off;
        public string label;
    }

    public class UndoStack : Object {
        public Gee.ArrayList<Snapshot> undo_list = new Gee.ArrayList<Snapshot>();
        public Gee.ArrayList<Snapshot> redo_list = new Gee.ArrayList<Snapshot>();
        public int limit = 200;
        public signal void changed();

        public bool can_undo {
            get { return undo_list.size > 0; }
        }

        public bool can_redo {
            get { return redo_list.size > 0; }
        }

        public static Snapshot take(Document doc, Pos anchor, Pos focus, string label) {
            var s = new Snapshot();
            var all = Story.all(doc);
            s.doc = doc.copy();
            s.anchor_para = all.index_of(anchor.para);
            s.anchor_off = anchor.offset;
            s.focus_para = all.index_of(focus.para);
            s.focus_off = focus.offset;
            s.label = label;
            return s;
        }

        public void push(Snapshot s) {
            undo_list.add(s);
            if (undo_list.size > limit) undo_list.remove_at(0);
            redo_list.clear();
            changed();
        }

        public void clear() {
            undo_list.clear();
            redo_list.clear();
            changed();
        }
    }

    public delegate void CharMutator(CharProps c);
    public delegate void ParaMutator(Paragraph p);

    public class Editor : Object {
        public Document doc;
        public string author = "";
        public UndoStack undo = new UndoStack();
        public Pos anchor;
        public Pos focus;
        public signal void changed();
        public signal void selection_changed();
        private string group_label = "";
        private int64 group_time = 0;
        private Paragraph? group_para = null;

        public Editor(Document doc) {
            this.doc = doc;
            author = Environment.get_real_name();
            if (author == "" || author == "Unknown") author = Environment.get_user_name();
            var first = doc.body.first_paragraph();
            if (first == null) {
                first = new Paragraph();
                doc.body.add(first);
            }
            anchor = new Pos(first, 0);
            focus = new Pos(first, 0);
        }

        public void reset() {
            undo.clear();
            var first = doc.body.first_paragraph();
            if (first == null) {
                first = new Paragraph();
                doc.body.add(first);
            }
            anchor = new Pos(first, 0);
            focus = new Pos(first, 0);
            group_para = null;
        }

        public bool has_selection {
            get { return !anchor.same(focus); }
        }

        public void ordered(out Pos a, out Pos b) {
            if (Story.compare(doc, anchor, focus) <= 0) {
                a = anchor.copy();
                b = focus.copy();
            } else {
                a = focus.copy();
                b = anchor.copy();
            }
        }

        public void set_caret(Pos p, bool extend = false) {
            focus = p.copy();
            if (!extend) anchor = p.copy();
            selection_changed();
        }

        public void select(Pos a, Pos b) {
            anchor = a.copy();
            focus = b.copy();
            selection_changed();
        }

        public bool tracking {
            get { return doc.track_changes; }
        }

        public Revision new_rev(RevKind k) {
            var r = new Revision(k, author);
            r.id = doc.next_id();
            return r;
        }

        public void checkpoint(string label, bool coalesce = false) {
            int64 now = get_monotonic_time();
            if (coalesce && group_label == label && group_para == focus.para && now - group_time < 1500000) {
                group_time = now;
                return;
            }
            undo.push(UndoStack.take(doc, anchor, focus, label));
            group_label = label;
            group_time = now;
            group_para = coalesce ? focus.para : null;
        }

        public void break_group() {
            group_para = null;
            group_label = "";
        }

        private void restore(Snapshot s) {
            doc.assign(s.doc.copy());
            var all = Story.all(doc);
            var fallback = doc.body.first_paragraph();
            var ap = s.anchor_para >= 0 && s.anchor_para < all.size ? all[s.anchor_para] : fallback;
            var fp = s.focus_para >= 0 && s.focus_para < all.size ? all[s.focus_para] : fallback;
            anchor = new Pos(ap, s.anchor_off);
            focus = new Pos(fp, s.focus_off);
            foreach (var p in all) p.touch();
        }

        public bool do_undo() {
            if (!undo.can_undo) return false;
            var s = undo.undo_list.remove_at(undo.undo_list.size - 1);
            undo.redo_list.add(UndoStack.take(doc, anchor, focus, s.label));
            restore(s);
            break_group();
            undo.changed();
            changed();
            return true;
        }

        public bool do_redo() {
            if (!undo.can_redo) return false;
            var s = undo.redo_list.remove_at(undo.redo_list.size - 1);
            undo.undo_list.add(UndoStack.take(doc, anchor, focus, s.label));
            restore(s);
            break_group();
            undo.changed();
            changed();
            return true;
        }

        public CharProps props_for_insert() {
            var c = focus.para.props_at(focus.offset);
            c.link = null;
            var fr = focus.para.inline_at(focus.offset > 0 ? focus.offset - 1 : 0);
            if (fr != null && fr.props.link != null && focus.offset > 0) {
                var nx = focus.para.inline_at(focus.offset);
                if (nx != null && nx.props.link == fr.props.link) c.link = fr.props.link;
            }
            return c;
        }

        public void insert_text(string text, CharProps? props = null) {
            if (text == "") return;
            if (has_selection) delete_selection_raw();
            var p = focus.para;
            var cp = props ?? props_for_insert();
            string[] parts = text.replace("\r\n", "\n").replace("\r", "\n").split("\n");
            for (int i = 0; i < parts.length; i++) {
                if (i > 0) split_raw();
                string part = parts[i];
                if (part == "") continue;
                p = focus.para;
                if (part.contains("\t")) {
                    string[] segs = part.split("\t");
                    for (int k = 0; k < segs.length; k++) {
                        if (k > 0) {
                            var tab = new Tab();
                            tab.props = cp.copy();
                            if (tracking) tab.rev = new_rev(RevKind.INSERT);
                            p.insert_inline(focus.offset, tab);
                            focus = new Pos(p, focus.offset + 1);
                        }
                        if (segs[k] != "") {
                            p.insert_text(focus.offset, segs[k], cp, tracking ? new_rev(RevKind.INSERT) : null);
                            focus = new Pos(p, focus.offset + segs[k].char_count());
                        }
                    }
                } else {
                    p.insert_text(focus.offset, part, cp, tracking ? new_rev(RevKind.INSERT) : null);
                    focus = new Pos(p, focus.offset + part.char_count());
                }
                p.touch();
            }
            anchor = focus.copy();
            changed();
        }

        public void insert_inline(Inline item) {
            if (has_selection) delete_selection_raw();
            if (tracking && item.rev == null) item.rev = new_rev(RevKind.INSERT);
            if (item.props.is_empty()) item.props = props_for_insert();
            focus.para.insert_inline(focus.offset, item);
            focus.para.touch();
            focus = new Pos(focus.para, focus.offset + item.length);
            anchor = focus.copy();
            changed();
        }

        public void split_paragraph() {
            if (has_selection) delete_selection_raw();
            split_raw();
            anchor = focus.copy();
            changed();
        }

        private void split_raw() {
            var p = focus.para;
            var list = p.parent;
            if (list == null) return;
            bool at_end = focus.offset >= p.length;
            var tail = p.split(focus.offset);
            if (at_end) {
                var st = doc.styles.get(p.style);
                if (st != null && st.next != null && doc.styles.get(st.next) != null) {
                    tail.style = st.next;
                    if (st.next != p.style) {
                        tail.props.num_id = -1;
                        tail.props.num_level = -1;
                    }
                }
                tail.props.page_break_before = Tri.INHERIT;
            }
            if (tracking) p.mark_rev = new_rev(RevKind.INSERT);
            list.insert(list.items.index_of(p) + 1, tail);
            p.touch();
            tail.touch();
            focus = new Pos(tail, 0);
        }

        public void delete_selection() {
            if (!has_selection) return;
            delete_selection_raw();
            changed();
        }

        private void delete_selection_raw() {
            Pos a, b;
            ordered(out a, out b);
            var r = delete_range(a, b);
            focus = r;
            anchor = r.copy();
        }

        public Pos delete_range(Pos a, Pos b) {
            if (a.para == b.para) {
                delete_in_para(a.para, a.offset, b.offset);
                a.para.touch();
                return new Pos(a.para, a.offset);
            }
            var paras = Story.between(doc, a, b);
            if (tracking) {
                for (int i = 0; i < paras.size; i++) {
                    var p = paras[i];
                    int s = p == a.para ? a.offset : 0;
                    int e = p == b.para ? b.offset : p.length;
                    delete_in_para(p, s, e);
                    if (p != b.para) {
                        if (p.mark_rev != null && p.mark_rev.kind == RevKind.INSERT && p.mark_rev.author == author) merge_next(p);
                        else p.mark_rev = new_rev(RevKind.DELETE);
                    }
                    p.touch();
                }
                return new Pos(a.para, a.offset);
            }
            if (a.para.parent == b.para.parent && a.para.parent != null) {
                var list = a.para.parent;
                int ia = list.items.index_of(a.para);
                int ib = list.items.index_of(b.para);
                a.para.cut(a.offset, a.para.length);
                b.para.cut(0, b.offset);
                for (int i = ib - 1; i > ia; i--) list.remove_at(i);
                if (b.para.section != null && a.para.section == null) a.para.section = null;
                a.para.append_from(b.para);
                list.remove_at(list.items.index_of(b.para));
                a.para.touch();
                return new Pos(a.para, a.offset);
            }
            foreach (var p in paras) {
                int s = p == a.para ? a.offset : 0;
                int e = p == b.para ? b.offset : p.length;
                p.cut(s, e);
                p.touch();
            }
            var root = a.para.parent;
            if (root != null) {
                for (int i = root.size - 1; i >= 0; i--) {
                    var t = root[i] as Table;
                    if (t == null) continue;
                    bool inside = true;
                    foreach (var r in t.rows) foreach (var c in r.cells) foreach (var cp in Story.paragraphs(c.blocks)) if (!paras.contains(cp) || cp == b.para) inside = false;
                    if (inside) root.remove_at(i);
                }
            }
            return new Pos(a.para, a.offset);
        }

        private void merge_next(Paragraph p) {
            var list = p.parent;
            if (list == null) return;
            int i = list.items.index_of(p);
            if (i + 1 >= list.size) return;
            var n = list[i + 1] as Paragraph;
            if (n == null) return;
            p.append_from(n);
            list.remove_at(i + 1);
            p.mark_rev = null;
        }

        private void delete_in_para(Paragraph p, int s, int e) {
            if (e <= s) return;
            if (!tracking) {
                p.cut(s, e);
                return;
            }
            int a = p.split_at(s);
            int b = p.split_at(e);
            var rev = new_rev(RevKind.DELETE);
            for (int i = b - 1; i >= a; i--) {
                var it = p.inlines[i];
                if (it.length == 0) continue;
                if (it.rev != null && it.rev.kind == RevKind.INSERT && it.rev.author == author) {
                    p.inlines.remove_at(i);
                    continue;
                }
                if (it.rev != null && it.rev.kind == RevKind.DELETE) continue;
                it.rev = rev.copy();
            }
            p.normalize();
        }

        public void delete_backward(bool word = false) {
            if (has_selection) {
                delete_selection();
                return;
            }
            var p = focus.para;
            if (focus.offset > 0) {
                int start = word ? word_start(p, focus.offset) : prev_char(p, focus.offset);
                delete_in_para(p, start, focus.offset);
                p.touch();
                focus = new Pos(p, tracking ? start : start);
                anchor = focus.copy();
                changed();
                return;
            }
            var pp = doc.styles.resolve_para(p);
            if (pp.num_id > 0) {
                p.props.num_id = 0;
                p.touch();
                changed();
                return;
            }
            var list = p.parent;
            if (list == null) return;
            int idx = list.items.index_of(p);
            if (idx <= 0) return;
            var prev = list[idx - 1] as Paragraph;
            if (prev == null) {
                if (p.is_empty() && list.size > 1) {
                    list.remove_at(idx);
                    changed();
                }
                return;
            }
            int off = prev.length;
            if (tracking) {
                prev.mark_rev = new_rev(RevKind.DELETE);
                prev.touch();
                focus = new Pos(prev, off);
            } else {
                prev.append_from(p);
                list.remove_at(idx);
                prev.touch();
                focus = new Pos(prev, off);
            }
            anchor = focus.copy();
            changed();
        }

        public void delete_forward(bool word = false) {
            if (has_selection) {
                delete_selection();
                return;
            }
            var p = focus.para;
            if (focus.offset < p.length) {
                int end = word ? word_end(p, focus.offset) : next_char(p, focus.offset);
                delete_in_para(p, focus.offset, end);
                p.touch();
                if (tracking) focus = new Pos(p, end);
                anchor = focus.copy();
                changed();
                return;
            }
            var list = p.parent;
            if (list == null) return;
            int idx = list.items.index_of(p);
            if (idx + 1 >= list.size) return;
            var next = list[idx + 1] as Paragraph;
            if (next == null) return;
            if (tracking) {
                p.mark_rev = new_rev(RevKind.DELETE);
            } else {
                p.append_from(next);
                list.remove_at(idx + 1);
            }
            p.touch();
            changed();
        }

        public static int prev_char(Paragraph p, int off) {
            return int.max(0, off - 1);
        }

        public static int next_char(Paragraph p, int off) {
            return int.min(p.length, off + 1);
        }

        public static bool is_word(unichar c) {
            return c.isalnum() || c == '_' || c == '\'' || c == 0x2019;
        }

        public static int word_start(Paragraph p, int off) {
            string t = p.text();
            int i = off;
            while (i > 0 && !is_word(t.get_char(t.index_of_nth_char(i - 1)))) i--;
            while (i > 0 && is_word(t.get_char(t.index_of_nth_char(i - 1)))) i--;
            return i;
        }

        public static int word_end(Paragraph p, int off) {
            string t = p.text();
            int n = p.length;
            int i = off;
            while (i < n && is_word(t.get_char(t.index_of_nth_char(i)))) i++;
            while (i < n && !is_word(t.get_char(t.index_of_nth_char(i))) && t.get_char(t.index_of_nth_char(i)) == ' ') i++;
            return i;
        }

        public void word_at(Pos p, out int s, out int e) {
            string t = p.para.text();
            int n = p.para.length;
            s = p.offset;
            e = p.offset;
            while (s > 0 && is_word(t.get_char(t.index_of_nth_char(s - 1)))) s--;
            while (e < n && is_word(t.get_char(t.index_of_nth_char(e)))) e++;
        }

        public string selected_text() {
            if (!has_selection) return "";
            Pos a, b;
            ordered(out a, out b);
            var sb = new StringBuilder();
            var paras = Story.between(doc, a, b);
            for (int i = 0; i < paras.size; i++) {
                var p = paras[i];
                int s = p == a.para ? a.offset : 0;
                int e = p == b.para ? b.offset : p.length;
                var tmp = new Paragraph();
                foreach (var it in p.slice(s, e)) tmp.inlines.add(it);
                if (i > 0) sb.append_c('\n');
                sb.append(tmp.plain_text());
            }
            return sb.str;
        }

        public Gee.ArrayList<Paragraph> selected_paragraphs() {
            Pos a, b;
            ordered(out a, out b);
            return Story.between(doc, a, b);
        }

        public void format_chars(owned CharMutator fn) {
            Pos a, b;
            ordered(out a, out b);
            if (!has_selection) return;
            foreach (var p in Story.between(doc, a, b)) {
                int s = p == a.para ? a.offset : 0;
                int e = p == b.para ? b.offset : p.length;
                if (e <= s) continue;
                p.for_range(s, e, (it) => {
                    if (tracking && it.fmt_rev == null) {
                        it.fmt_old = it.props.copy();
                        it.fmt_rev = new_rev(RevKind.FORMAT);
                    }
                    fn(it.props);
                });
                p.touch();
            }
            changed();
        }

        public void format_paragraphs(owned ParaMutator fn) {
            foreach (var p in selected_paragraphs()) {
                fn(p);
                p.touch();
            }
            changed();
        }

        public BlockList copy_selection() {
            var outl = new BlockList();
            if (!has_selection) return outl;
            Pos a, b;
            ordered(out a, out b);
            var paras = Story.between(doc, a, b);
            if (a.para.parent == b.para.parent && a.para.parent != null && paras.size > 1) {
                var list = a.para.parent;
                int ia = list.items.index_of(a.para);
                int ib = list.items.index_of(b.para);
                for (int i = ia; i <= ib; i++) {
                    var blk = list[i];
                    var p = blk as Paragraph;
                    if (p != null) {
                        int s = p == a.para ? a.offset : 0;
                        int e = p == b.para ? b.offset : p.length;
                        var np = p.shell();
                        foreach (var it in p.slice(s, e)) np.inlines.add(it);
                        outl.add(np);
                    } else {
                        outl.add(blk.copy());
                    }
                }
                return outl;
            }
            foreach (var p in paras) {
                int s = p == a.para ? a.offset : 0;
                int e = p == b.para ? b.offset : p.length;
                var np = p.shell();
                foreach (var it in p.slice(s, e)) np.inlines.add(it);
                outl.add(np);
            }
            return outl;
        }

        public void insert_blocks(BlockList frag, bool keep_formatting = true) {
            if (frag.size == 0) return;
            if (has_selection) delete_selection_raw();
            var p = focus.para;
            var list = p.parent;
            if (frag.size == 1 && frag[0] is Paragraph) {
                var src = (Paragraph) frag[0];
                int off = focus.offset;
                foreach (var it in src.inlines) {
                    var c = it.copy();
                    if (!keep_formatting) c.props = props_for_insert();
                    if (tracking) c.rev = new_rev(RevKind.INSERT);
                    p.insert_inline(off, c);
                    off += c.length;
                }
                p.normalize();
                p.touch();
                focus = new Pos(p, off);
                anchor = focus.copy();
                changed();
                return;
            }
            if (list == null) return;
            var tail = p.split(focus.offset);
            int idx = list.items.index_of(p);
            list.insert(idx + 1, tail);
            var first = frag[0] as Paragraph;
            int start = 0;
            if (first != null) {
                if (keep_formatting && p.length == 0) {
                    p.style = first.style;
                    p.props = first.props.copy();
                }
                foreach (var it in first.inlines) {
                    var c = it.copy();
                    if (tracking) c.rev = new_rev(RevKind.INSERT);
                    p.inlines.add(c);
                }
                p.normalize();
                start = 1;
            }
            int insert_at = idx + 1;
            Paragraph? last_para = null;
            for (int i = start; i < frag.size; i++) {
                var blk = frag[i].copy();
                if (i == frag.size - 1 && blk is Paragraph) {
                    var lp = (Paragraph) blk;
                    int len = lp.length;
                    for (int k = lp.inlines.size - 1; k >= 0; k--) {
                        var c = lp.inlines[k];
                        if (tracking) c.rev = new_rev(RevKind.INSERT);
                        tail.inlines.insert(0, c);
                    }
                    tail.style = lp.style;
                    tail.props = lp.props.copy();
                    tail.normalize();
                    last_para = tail;
                    focus = new Pos(tail, len);
                    break;
                }
                list.insert(insert_at++, blk);
            }
            if (last_para == null) focus = new Pos(tail, 0);
            p.touch();
            tail.touch();
            anchor = focus.copy();
            changed();
        }

        public void set_style(string id) {
            var st = doc.styles.get(id);
            if (st == null) return;
            if (st.kind == StyleType.CHARACTER) {
                format_chars((c) => c.style = id);
                return;
            }
            format_paragraphs((p) => p.style = id);
        }

        public void toggle_list(bool numbered) {
            var paras = selected_paragraphs();
            if (paras.size == 0) return;
            var first = doc.styles.resolve_para(paras[0]);
            bool has = first.num_id > 0;
            ListDef? existing = has ? doc.numbering.def_for(first.num_id) : null;
            bool same_kind = existing != null && existing.is_bullet() != numbered;
            int id = 0;
            if (!has || !same_kind) {
                int prev_id = find_adjacent_list(paras[0], numbered);
                if (prev_id > 0) id = prev_id;
                else {
                    var d = numbered ? doc.numbering.make_numbers() : doc.numbering.make_bullets();
                    id = doc.numbering.add_instance(d);
                }
            }
            foreach (var p in paras) {
                if (has && same_kind) {
                    p.props.num_id = 0;
                    p.props.num_level = -1;
                    if (p.style == "ListParagraph") p.style = "Normal";
                } else {
                    p.props.num_id = id;
                    if (p.props.num_level < 0) p.props.num_level = 0;
                    if (p.style == "Normal") p.style = "ListParagraph";
                }
                p.touch();
            }
            changed();
        }

        private int find_adjacent_list(Paragraph p, bool numbered) {
            var list = p.parent;
            if (list == null) return 0;
            int i = list.items.index_of(p) - 1;
            if (i < 0) return 0;
            var prev = list[i] as Paragraph;
            if (prev == null) return 0;
            var pp = doc.styles.resolve_para(prev);
            if (pp.num_id <= 0) return 0;
            var d = doc.numbering.def_for(pp.num_id);
            if (d == null || d.is_bullet() == numbered) return 0;
            return pp.num_id;
        }

        public void apply_list_def(ListDef d) {
            int id = doc.numbering.add_instance(d);
            format_paragraphs((p) => {
                p.props.num_id = id;
                if (p.props.num_level < 0) p.props.num_level = 0;
                if (p.style == "Normal") p.style = "ListParagraph";
            });
        }

        public void change_level(int delta) {
            format_paragraphs((p) => {
                var pp = doc.styles.resolve_para(p);
                if (pp.num_id > 0) {
                    p.props.num_level = (int.max(0, pp.num_level) + delta).clamp(0, 8);
                } else {
                    double l = pp.ind_left.is_nan() ? 0 : pp.ind_left;
                    p.props.ind_left = double.max(0, l + delta * 36);
                }
            });
        }

        public void restart_numbering() {
            var paras = selected_paragraphs();
            if (paras.size == 0) return;
            var pp = doc.styles.resolve_para(paras[0]);
            if (pp.num_id <= 0) return;
            int old = pp.num_id;
            int fresh = doc.numbering.restart(old);
            var all = Story.paragraphs(Story.root_of(doc, paras[0]));
            bool on = false;
            foreach (var p in all) {
                if (p == paras[0]) on = true;
                if (!on) continue;
                var q = doc.styles.resolve_para(p);
                if (q.num_id == old) {
                    p.props.num_id = fresh;
                    p.touch();
                } else if (q.num_id <= 0 && !p.is_empty()) {
                    break;
                }
            }
            changed();
        }

        public Table? table_at(Pos p) {
            var list = p.para.parent;
            if (list == null || !(list.owner is TableCell)) return null;
            return doc.find_table_of((TableCell) list.owner);
        }

        public TableCell? cell_at(Pos p) {
            var list = p.para.parent;
            return list != null ? list.owner as TableCell : null;
        }

        public void insert_table(int rows, int cols) {
            var s = doc.section_for(focus.para);
            double width = s.column_width() - 1;
            var t = Table.create(rows, cols, width);
            if (has_selection) delete_selection_raw();
            var p = focus.para;
            var list = p.parent;
            if (list == null) return;
            int idx = list.items.index_of(p);
            if (focus.offset > 0 && focus.offset < p.length) {
                var tail = p.split(focus.offset);
                list.insert(idx + 1, tail);
                list.insert(idx + 1, t);
            } else if (focus.offset == 0 && !p.is_empty()) {
                list.insert(idx, t);
            } else {
                list.insert(idx + 1, t);
                if (idx + 2 >= list.size || !(list[idx + 2] is Paragraph)) list.insert(idx + 2, new Paragraph());
            }
            p.touch();
            focus = new Pos((Paragraph) t.rows[0].cells[0].blocks[0], 0);
            anchor = focus.copy();
            changed();
        }

        public bool table_op(string op) {
            var cell = cell_at(focus);
            var t = cell != null ? table_at(focus) : null;
            if (t == null) return false;
            int r, c;
            t.locate_cell(cell, out r, out c);
            if (r < 0) return false;
            int gc = t.grid_col(t.rows[r], cell);
            switch (op) {
                case "row-above":
                case "row-below":
                    var src = t.rows[r];
                    var nr = new TableRow();
                    foreach (var cc in src.cells) {
                        var n = new TableCell();
                        n.span = cc.span;
                        n.width = cc.width;
                        n.shading = cc.shading;
                        var np = new Paragraph();
                        var fp = cc.blocks.first_paragraph();
                        if (fp != null) {
                            np.style = fp.style;
                            np.props = fp.props.copy();
                        }
                        n.blocks.add(np);
                        nr.cells.add(n);
                    }
                    if (tracking) nr.rev = new_rev(RevKind.INSERT);
                    t.rows.insert(op == "row-above" ? r : r + 1, nr);
                    break;
                case "col-left":
                case "col-right":
                    int at = op == "col-left" ? gc : gc + cell.span;
                    double[] g = {};
                    double w = gc < t.grid.length ? t.grid[gc] : 72;
                    for (int i = 0; i < t.grid.length; i++) {
                        if (i == at) g += w;
                        g += t.grid[i];
                    }
                    if (at >= t.grid.length) g += w;
                    double total = 0;
                    foreach (double x in t.grid) total += x;
                    double nt = 0;
                    foreach (double x in g) nt += x;
                    for (int i = 0; i < g.length; i++) g[i] = g[i] * total / nt;
                    t.grid = g;
                    foreach (var row in t.rows) {
                        int col = 0;
                        int insert_idx = row.cells.size;
                        for (int i = 0; i < row.cells.size; i++) {
                            if (col >= at) {
                                insert_idx = i;
                                break;
                            }
                            col += row.cells[i].span;
                        }
                        var n = new TableCell();
                        n.blocks.add(new Paragraph());
                        row.cells.insert(insert_idx, n);
                    }
                    break;
                case "delete-row":
                    if (t.rows.size <= 1) return table_op("delete-table");
                    if (tracking) {
                        t.rows[r].rev = new_rev(RevKind.DELETE);
                    } else {
                        t.rows.remove_at(r);
                        int nr2 = int.min(r, t.rows.size - 1);
                        focus = new Pos(t.rows[nr2].cells[0].blocks.first_paragraph(), 0);
                    }
                    break;
                case "delete-col":
                    if (t.grid.length <= 1) return table_op("delete-table");
                    foreach (var row in t.rows) {
                        var target = t.cell_at_grid(row, gc);
                        if (target == null) continue;
                        if (target.span > 1) target.span--;
                        else row.cells.remove(target);
                    }
                    double[] g2 = {};
                    double removed = t.grid[gc];
                    for (int i = 0; i < t.grid.length; i++) if (i != gc) g2 += t.grid[i];
                    for (int i = 0; i < g2.length; i++) g2[i] += removed / g2.length;
                    t.grid = g2;
                    var row0 = t.rows[r];
                    focus = new Pos(row0.cells[int.min(c, row0.cells.size - 1)].blocks.first_paragraph(), 0);
                    break;
                case "delete-table":
                    var list = t.parent;
                    if (list == null) return false;
                    int ti = list.items.index_of(t);
                    list.remove_at(ti);
                    if (list.size == 0) list.add(new Paragraph());
                    var after = ti < list.size ? list[ti] as Paragraph : null;
                    if (after == null) {
                        after = new Paragraph();
                        list.insert(ti, after);
                    }
                    focus = new Pos(after, 0);
                    break;
                case "merge-right":
                    if (c + 1 >= t.rows[r].cells.size) return false;
                    var right = t.rows[r].cells[c + 1];
                    cell.span += right.span;
                    foreach (var b in right.blocks.items) {
                        var bp = b as Paragraph;
                        if (bp != null && bp.is_empty()) continue;
                        cell.blocks.add(b.copy());
                    }
                    t.rows[r].cells.remove_at(c + 1);
                    break;
                case "merge-down":
                    if (r + 1 >= t.rows.size) return false;
                    var below = t.cell_at_grid(t.rows[r + 1], gc);
                    if (below == null) return false;
                    if (cell.vmerge == VMerge.NONE) cell.vmerge = VMerge.RESTART;
                    foreach (var b in below.blocks.items) {
                        var bp = b as Paragraph;
                        if (bp != null && bp.is_empty()) continue;
                        cell.blocks.add(b.copy());
                    }
                    below.blocks.clear();
                    below.blocks.add(new Paragraph());
                    below.vmerge = VMerge.CONTINUE;
                    below.span = cell.span;
                    break;
                case "split":
                    if (cell.span > 1) {
                        int extra = cell.span - 1;
                        cell.span = 1;
                        for (int i = 0; i < extra; i++) {
                            var n = new TableCell();
                            n.blocks.add(new Paragraph());
                            t.rows[r].cells.insert(c + 1, n);
                        }
                    } else if (cell.vmerge == VMerge.RESTART) {
                        cell.vmerge = VMerge.NONE;
                        for (int k = r + 1; k < t.rows.size; k++) {
                            var bc = t.cell_at_grid(t.rows[k], gc);
                            if (bc == null || bc.vmerge != VMerge.CONTINUE) break;
                            bc.vmerge = VMerge.NONE;
                        }
                    } else {
                        double w0 = gc < t.grid.length ? t.grid[gc] : 72;
                        double[] g = {};
                        for (int i = 0; i < t.grid.length; i++) {
                            if (i == gc) {
                                g += w0 / 2;
                                g += w0 / 2;
                            } else {
                                g += t.grid[i];
                            }
                        }
                        t.grid = g;
                        foreach (var row in t.rows) {
                            var tc = t.cell_at_grid(row, gc);
                            if (tc == null) continue;
                            if (row == t.rows[r]) {
                                var n = new TableCell();
                                n.blocks.add(new Paragraph());
                                row.cells.insert(row.cells.index_of(tc) + 1, n);
                            } else {
                                tc.span++;
                            }
                        }
                    }
                    break;
                case "distribute":
                    double total = 0;
                    foreach (double x in t.grid) total += x;
                    double[] g3 = new double[t.grid.length];
                    for (int i = 0; i < g3.length; i++) g3[i] = total / g3.length;
                    t.grid = g3;
                    break;
                case "header-row":
                    t.rows[r].header = !t.rows[r].header;
                    break;
                default:
                    return false;
            }
            foreach (var row in t.rows) foreach (var cc in row.cells) foreach (var p in Story.paragraphs(cc.blocks)) p.touch();
            focus.para.touch();
            anchor = focus.copy();
            changed();
            return true;
        }

        public void sort_table(int col, bool descending, bool numeric) {
            var t = table_at(focus);
            if (t == null) return;
            int first = 0;
            while (first < t.rows.size && t.rows[first].header) first++;
            var body = new Gee.ArrayList<TableRow>();
            for (int i = first; i < t.rows.size; i++) body.add(t.rows[i]);
            body.sort((a, b) => {
                var ca = t.cell_at_grid(a, col);
                var cb = t.cell_at_grid(b, col);
                string sa = ca != null ? ca.plain_text() : "";
                string sb = cb != null ? cb.plain_text() : "";
                int r;
                if (numeric) {
                    double da = double.parse(sa.replace(",", ""));
                    double db = double.parse(sb.replace(",", ""));
                    r = da < db ? -1 : (da > db ? 1 : 0);
                } else {
                    r = strcmp(sa.casefold(), sb.casefold());
                }
                return descending ? -r : r;
            });
            for (int i = 0; i < body.size; i++) t.rows[first + i] = body[i];
            foreach (var row in t.rows) foreach (var cc in row.cells) foreach (var p in Story.paragraphs(cc.blocks)) p.touch();
            changed();
        }

        public void move_paragraphs(int dir) {
            var paras = selected_paragraphs();
            if (paras.size == 0) return;
            var list = paras[0].parent;
            if (list == null) return;
            foreach (var p in paras) if (p.parent != list) return;
            int first = list.items.index_of(paras[0]);
            int last = list.items.index_of(paras[paras.size - 1]);
            if (dir < 0 && first > 0) {
                var b = list[first - 1];
                list.items.remove_at(first - 1);
                list.items.insert(last, b);
            } else if (dir > 0 && last + 1 < list.size) {
                var b = list[last + 1];
                list.items.remove_at(last + 1);
                list.items.insert(first, b);
            }
            foreach (var p in paras) p.touch();
            changed();
        }

        public Gee.ArrayList<Block> heading_section(Paragraph h) {
            var result = new Gee.ArrayList<Block>();
            var list = h.parent;
            if (list == null) return result;
            int lvl = doc.styles.outline_level(h);
            int i = list.items.index_of(h);
            result.add(h);
            for (int k = i + 1; k < list.size; k++) {
                var p = list[k] as Paragraph;
                if (p != null) {
                    int l2 = doc.styles.outline_level(p);
                    if (l2 >= 0 && l2 <= lvl) break;
                }
                result.add(list[k]);
            }
            return result;
        }

        public void move_heading_section(Paragraph h, Paragraph? before) {
            var list = h.parent;
            if (list == null || (before != null && before.parent != list)) return;
            var blocks = heading_section(h);
            if (before != null && blocks.contains(before)) return;
            foreach (var b in blocks) list.items.remove(b);
            int at = before != null ? list.items.index_of(before) : list.size;
            foreach (var b in blocks) list.items.insert(at++, b);
            foreach (var b in blocks) b.touch();
            changed();
        }

        public void promote(Paragraph h, int delta) {
            int lvl = doc.styles.outline_level(h);
            if (lvl < 0) {
                if (delta < 0) h.style = "Heading9";
            } else {
                int nl = lvl + delta;
                if (nl < 0) nl = 0;
                if (nl > 8) {
                    h.style = "Normal";
                } else {
                    h.style = "Heading%d".printf(nl + 1);
                }
            }
            h.touch();
            changed();
        }
    }
}
