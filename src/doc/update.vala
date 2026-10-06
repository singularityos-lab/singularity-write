namespace Write {

    public delegate int PageLookup(Paragraph p);

    public class FieldUpdater : Object {
        private Document doc;
        private unowned PageLookup? page_of;
        public string filename = "";
        public string filepath = "";

        public FieldUpdater(Document doc, PageLookup? page_of) {
            this.doc = doc;
            this.page_of = page_of;
        }

        private int page(Paragraph p) {
            if (page_of == null) return 1;
            int n = page_of(p);
            return n > 0 ? n : 1;
        }

        public static string new_bookmark_name(Document doc, string prefix) {
            var names = new Gee.HashSet<string>();
            foreach (var p in Story.all(doc)) foreach (var i in p.inlines) if (i is Mark && ((Mark) i).kind == MarkKind.BOOKMARK_START) names.add(((Mark) i).name);
            int n = doc.next_id();
            string name = "%s%08d".printf(prefix, n);
            while (names.contains(name)) name = "%s%08d".printf(prefix, ++n);
            return name;
        }

        public static string? bookmark_of(Paragraph p) {
            foreach (var i in p.inlines) {
                var m = i as Mark;
                if (m != null && m.kind == MarkKind.BOOKMARK_START) return m.name;
            }
            return null;
        }

        public static string ensure_bookmark(Document doc, Paragraph p, string prefix) {
            foreach (var i in p.inlines) {
                var m = i as Mark;
                if (m != null && m.kind == MarkKind.BOOKMARK_START && m.name.has_prefix(prefix)) return m.name;
            }
            string name = new_bookmark_name(doc, prefix);
            p.inlines.insert(0, new Mark(MarkKind.BOOKMARK_START, name));
            p.inlines.add(new Mark(MarkKind.BOOKMARK_END, name));
            p.touch();
            return name;
        }

        public int update_all() {
            int count = 0;
            var fctx = new FieldContext(doc);
            fctx.filename = filename;
            fctx.filepath = filepath;
            collect_bookmarks(fctx);
            foreach (var p in Story.all(doc)) {
                foreach (var i in p.inlines) {
                    var f = i as FieldRun;
                    if (f == null || f.locked) continue;
                    string k = f.kind();
                    if (k == "SEQ") {
                        string old = f.result;
                        f.result = Fields.evaluate(f, fctx);
                        if (old != f.result) p.touch();
                        count++;
                    }
                }
            }
            collect_bookmarks(fctx);
            foreach (var p in Story.all(doc)) {
                bool touched = false;
                foreach (var i in p.inlines) {
                    var f = i as FieldRun;
                    if (f == null || f.locked) continue;
                    string k = f.kind();
                    if (k == "PAGE" || k == "NUMPAGES" || k == "SECTIONPAGES" || k == "SEQ" || k == "MERGEFIELD" || k == "FILLIN" || k == "ASK" || f.code.has_prefix("\x01")) continue;
                    string old = f.result;
                    if (k == "PAGEREF") {
                        string[] t = f.args();
                        var target = t.length > 1 ? bookmark_para(t[1]) : null;
                        f.result = target != null ? page(target).to_string() : _("Error! Bookmark not defined.");
                    } else if (k == "=") {
                        fctx.cells = null;
                        Table? table = null;
                        TableCell? cell = null;
                        if (p.parent != null && p.parent.owner is TableCell) {
                            cell = (TableCell) p.parent.owner;
                            table = doc.find_table_of(cell);
                        }
                        if (table != null) {
                            var tt = table;
                            var cc = cell;
                            fctx.cells = (dir) => {
                                return cell_values(tt, cc, dir);
                            };
                            f.result = Fields.evaluate(f, fctx);
                            fctx.cells = null;
                        } else {
                            f.result = Fields.evaluate(f, fctx);
                        }
                    } else {
                        f.result = Fields.evaluate(f, fctx);
                    }
                    f.dirty = false;
                    if (old != f.result) touched = true;
                    count++;
                }
                if (touched) p.touch();
            }
            foreach (var b in all_field_blocks(doc.body)) {
                update_block(b);
                count++;
            }
            return count;
        }

        private static double[] cell_values(Table t, TableCell cell, string dir) {
            double[] vals = {};
            int r, c;
            t.locate_cell(cell, out r, out c);
            if (r < 0) return vals;
            int gc = t.grid_col(t.rows[r], cell);
            if (dir == "ABOVE" || dir == "BELOW") {
                int from = dir == "ABOVE" ? 0 : r + 1;
                int to = dir == "ABOVE" ? r : t.rows.size;
                for (int k = from; k < to; k++) {
                    var x = t.cell_at_grid(t.rows[k], gc);
                    double d = 0;
                    if (x != null && double.try_parse(x.plain_text().strip().replace(",", ""), out d)) vals += d;
                }
            } else {
                var row = t.rows[r];
                int from = dir == "LEFT" ? 0 : c + 1;
                int to = dir == "LEFT" ? c : row.cells.size;
                for (int k = from; k < to; k++) {
                    double d = 0;
                    if (double.try_parse(row.cells[k].plain_text().strip().replace(",", ""), out d)) vals += d;
                }
            }
            return vals;
        }

        private Paragraph? bookmark_para(string name) {
            foreach (var p in Story.all(doc)) foreach (var i in p.inlines) if (i is Mark && ((Mark) i).kind == MarkKind.BOOKMARK_START && ((Mark) i).name == name) return p;
            return null;
        }

        private void collect_bookmarks(FieldContext ctx) {
            ctx.bookmark_text.clear();
            ctx.seq_labels.clear();
            foreach (var p in Story.all(doc)) {
                var open = new Gee.HashMap<string, string>();
                string? seq_label = null;
                foreach (var i in p.inlines) {
                    var m = i as Mark;
                    if (m != null && m.kind == MarkKind.BOOKMARK_START) open[m.name] = "";
                    else if (m != null && m.kind == MarkKind.BOOKMARK_END && open.has_key(m.name)) {
                        ctx.bookmark_text[m.name] = open[m.name];
                        if (seq_label != null) ctx.seq_labels[m.name] = seq_label;
                        open.unset(m.name);
                    } else {
                        string t = "";
                        if (i is TextRun) t = ((TextRun) i).text;
                        else if (i is FieldRun) {
                            t = ((FieldRun) i).result;
                            if (((FieldRun) i).kind() == "SEQ") seq_label = t;
                        } else if (i is Tab) t = "\t";
                        foreach (var key in open.keys.to_array()) open[key] = open[key] + t;
                    }
                }
                foreach (var e in open.entries) ctx.bookmark_text[e.key] = e.value;
                ctx.bookmark_page[""] = 0;
            }
            int fn = 0;
            foreach (var n in doc.notes(NoteKind.FOOTNOTE)) {
                fn++;
                foreach (var p in Story.all(doc)) {
                    foreach (var i in p.inlines) {
                        var r = i as NoteRef;
                        if (r == null || r.note != n) continue;
                        int idx = p.inlines.index_of(r);
                        if (idx > 0 && p.inlines[idx - 1] is Mark && ((Mark) p.inlines[idx - 1]).kind == MarkKind.BOOKMARK_START) ctx.note_numbers[((Mark) p.inlines[idx - 1]).name] = fn.to_string();
                    }
                }
            }
        }

        private Gee.ArrayList<FieldBlock> all_field_blocks(BlockList list) {
            var res = new Gee.ArrayList<FieldBlock>();
            foreach (var b in list.items) {
                if (b is FieldBlock) res.add((FieldBlock) b);
                var t = b as Table;
                if (t != null) foreach (var r in t.rows) foreach (var c in r.cells) res.add_all(all_field_blocks(c.blocks));
            }
            return res;
        }

        public void update_block(FieldBlock fb) {
            string k = fb.kind();
            string[] toks = Fields.tokenize(fb.code);
            var old_first = fb.result.first_paragraph();
            fb.result.clear();
            var s = doc.section_for(fb);
            double right = s.column_width();
            switch (k) {
                case "TOC":
                    string? cap = Fields.switch_arg(toks, "\\c");
                    if (cap != null) build_tof(fb, cap, right);
                    else build_toc(fb, toks, right);
                    break;
                case "INDEX":
                    build_index(fb, toks);
                    break;
                case "BIBLIOGRAPHY":
                    build_bibliography(fb);
                    break;
                default:
                    break;
            }
            if (fb.result.size == 0) {
                var p = new Paragraph();
                p.inlines.add(new TextRun(k == "TOC" ? _("No table of contents entries found.") : (k == "INDEX" ? _("No index entries found.") : _("There are no sources in the current document."))));
                fb.result.add(p);
            }
            foreach (var b in fb.result.items) b.touch();
            fb.touch();
        }

        private Paragraph entry(string style, string text, int pg, double right, string? target) {
            var p = new Paragraph(style);
            p.props.tabs = new Gee.ArrayList<TabStop>();
            p.props.tabs.add(new TabStop(right, TabAlign.RIGHT, TabLeader.DOT));
            var cp = new CharProps();
            if (target != null) cp.link = "#" + target;
            p.inlines.add(new TextRun(text, cp));
            var tab = new Tab();
            tab.props = cp.copy();
            p.inlines.add(tab);
            var f = new FieldRun("PAGEREF %s \\h".printf(target ?? ""), pg.to_string());
            f.props = cp.copy();
            f.dirty = false;
            p.inlines.add(f);
            return p;
        }

        private void build_toc(FieldBlock fb, string[] toks, double right) {
            int from = 1, to = 3;
            string? o = Fields.switch_arg(toks, "\\o");
            if (o != null) {
                string[] r = o.split("-");
                if (r.length == 2) {
                    from = int.parse(r[0]).clamp(1, 9);
                    to = int.parse(r[1]).clamp(from, 9);
                }
            }
            bool links = Fields.has_switch(toks, "\\h");
            foreach (var b in doc.body.items) {
                var p = b as Paragraph;
                if (p == null) continue;
                int lvl = doc.styles.outline_level(p);
                if (lvl < 0 || lvl + 1 < from || lvl + 1 > to) continue;
                if (p.style.has_prefix("TOC")) continue;
                string text = p.plain_text().strip();
                if (text == "") continue;
                string bm = ensure_bookmark(doc, p, "_Toc");
                var e = entry("TOC%d".printf(lvl + 1), text, page(p), right, links ? bm : null);
                if (!links) {
                    var f = e.inlines[e.inlines.size - 1] as FieldRun;
                    if (f != null) f.code = "PAGEREF %s \\h".printf(bm);
                }
                fb.result.add(e);
            }
        }

        private void build_tof(FieldBlock fb, string label, double right) {
            foreach (var p in Story.paragraphs(doc.body)) {
                bool has = false;
                foreach (var i in p.inlines) {
                    var f = i as FieldRun;
                    if (f != null && f.kind() == "SEQ") {
                        string[] t = f.args();
                        if (t.length > 1 && t[1] == label) has = true;
                    }
                }
                if (!has) continue;
                string bm = ensure_bookmark(doc, p, "_Toc");
                fb.result.add(entry("TableofFigures", p.plain_text().strip(), page(p), right, bm));
            }
        }

        private void build_index(FieldBlock fb, string[] toks) {
            var terms = new Gee.TreeMap<string, Gee.TreeSet<int>>((a, b) => strcmp(a.casefold(), b.casefold()));
            foreach (var p in Story.paragraphs(doc.body)) {
                foreach (var i in p.inlines) {
                    var m = i as Mark;
                    if (m == null || m.kind != MarkKind.INDEX_ENTRY || m.name.strip() == "") continue;
                    string term = m.name.strip();
                    var set = terms[term];
                    if (set == null) {
                        set = new Gee.TreeSet<int>();
                        terms[term] = set;
                    }
                    set.add(page(p));
                }
            }
            string? current_letter = null;
            bool headings = Fields.has_switch(toks, "\\h") || true;
            foreach (var e in terms.entries) {
                string term = e.key;
                string main = term;
                string sub = "";
                int colon = term.index_of_char(':');
                if (colon > 0) {
                    main = term.substring(0, colon);
                    sub = term.substring(colon + 1);
                }
                string letter = main.get_char(0).toupper().to_string();
                if (headings && letter != current_letter) {
                    current_letter = letter;
                    fb.result.add(new Paragraph.with_text(letter, "IndexHeading"));
                }
                var sb = new StringBuilder(sub != "" ? sub : main);
                bool first = true;
                foreach (int pg in e.value) {
                    sb.append(first ? ", " : ", ");
                    sb.append(pg.to_string());
                    first = false;
                }
                fb.result.add(new Paragraph.with_text(sb.str, sub != "" ? "Index2" : "Index1"));
            }
        }

        private void build_bibliography(FieldBlock fb) {
            foreach (var src in Citations.cited_sources(doc)) {
                var p = new Paragraph("Bibliography");
                foreach (var piece in Citations.entry(doc, src)) {
                    var c = new CharProps();
                    if (piece.italic) c.italic = Tri.ON;
                    p.inlines.add(new TextRun(piece.text, c));
                }
                p.normalize();
                fb.result.add(p);
            }
        }

        public static FieldBlock make_toc(int levels = 3) {
            return new FieldBlock("TOC \\o \"1-%d\" \\h \\z \\u".printf(levels));
        }

        public static Paragraph make_caption(Document doc, string label, string text) {
            var p = new Paragraph("Caption");
            string bm = new_bookmark_name(doc, "_Ref");
            p.inlines.add(new Mark(MarkKind.BOOKMARK_START, bm));
            p.inlines.add(new TextRun(label + " "));
            var f = new FieldRun("SEQ %s \\* ARABIC".printf(label), "1");
            p.inlines.add(f);
            p.inlines.add(new Mark(MarkKind.BOOKMARK_END, bm));
            if (text != "") p.inlines.add(new TextRun(": " + text));
            return p;
        }
    }
}
