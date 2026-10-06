namespace Write {

    public class LivePacket : Object {
        public string peer = "";
        public string who = "";
        public Gee.ArrayList<uint> order = new Gee.ArrayList<uint>();
        public Gee.ArrayList<uint> dirty = new Gee.ArrayList<uint>();
        public Gee.HashMap<uint, string> blocks = new Gee.HashMap<uint, string>();
        public Gee.HashMap<uint, string> from = new Gee.HashMap<uint, string>();
        public string design = "";

        public bool empty {
            get { return dirty.size == 0 && design == ""; }
        }

        public Json.Object to_json() {
            var o = new Json.Object();
            o.set_string_member("t", "ops");
            o.set_string_member("peer", peer);
            o.set_string_member("who", who);
            var ord = new Json.Array();
            foreach (uint u in order) ord.add_int_element(u);
            o.set_array_member("order", ord);
            var dr = new Json.Array();
            foreach (uint u in dirty) dr.add_int_element(u);
            o.set_array_member("dirty", dr);
            var bl = new Json.Object();
            foreach (var e in blocks.entries) bl.set_string_member(e.key.to_string(), e.value);
            o.set_object_member("blocks", bl);
            var fr = new Json.Object();
            foreach (var e in from.entries) fr.set_string_member(e.key.to_string(), e.value);
            o.set_object_member("from", fr);
            if (design != "") o.set_string_member("design", design);
            return o;
        }

        public static LivePacket from_json(Json.Object o) {
            var p = new LivePacket();
            p.peer = o.has_member("peer") ? o.get_string_member("peer") : "";
            p.who = o.has_member("who") ? o.get_string_member("who") : "";
            if (o.has_member("order")) foreach (var n in o.get_array_member("order").get_elements()) p.order.add((uint) n.get_int());
            if (o.has_member("dirty")) foreach (var n in o.get_array_member("dirty").get_elements()) p.dirty.add((uint) n.get_int());
            if (o.has_member("blocks")) {
                var bl = o.get_object_member("blocks");
                foreach (string k in bl.get_members()) p.blocks[(uint) uint64.parse(k)] = bl.get_string_member(k);
            }
            if (o.has_member("from")) {
                var fr = o.get_object_member("from");
                foreach (string k in fr.get_members()) p.from[(uint) uint64.parse(k)] = fr.get_string_member(k);
            }
            if (o.has_member("design")) p.design = o.get_string_member("design");
            return p;
        }
    }

    public class LivePosition {
        public uint block = 0;
        public int para = 0;
        public int offset = 0;
    }

    public class LiveDoc : Object {
        public string peer_id;
        private uint seed;
        private uint counter = 0;
        private Gee.HashMap<uint, uint64?> sent = new Gee.HashMap<uint, uint64?>();
        private Gee.HashMap<uint, Block> bases = new Gee.HashMap<uint, Block>();
        private Gee.HashMap<uint, Gee.HashMap<string, Block>> history = new Gee.HashMap<uint, Gee.HashMap<string, Block>>();

        public static string content_hash(Block b) {
            var p = b as Paragraph;
            string key = p != null ? "p:" + para_text(p) + ":" + p.style : "b:" + block_sig(b).to_string();
            return Checksum.compute_for_string(ChecksumType.MD5, key);
        }

        private void remember(uint u, Block b) {
            if (!history.has_key(u)) history[u] = new Gee.HashMap<string, Block>();
            var h = history[u];
            if (h.size > 16) h.clear();
            h[content_hash(b)] = b.copy();
        }
        private uint64 design_sig = 0;
        private string last_order = "";
        public int merged_conflicts = 0;

        private static string order_key(Gee.List<uint> order) {
            var sb = new StringBuilder();
            foreach (uint u in order) sb.append(u.to_string()).append_c(',');
            return sb.str;
        }

        public LiveDoc(string peer_id) {
            this.peer_id = peer_id;
            seed = (uint) Random.int_range(1, 4000);
        }

        private uint new_uid() {
            counter++;
            return (seed << 18) | (counter & 0x3FFFF);
        }

        public void assign_uids(Document doc) {
            var seen = new Gee.HashSet<uint>();
            foreach (var b in doc.body.items) {
                if (b.uid == 0 || seen.contains(b.uid)) b.uid = new_uid();
                seen.add(b.uid);
            }
        }

        private static uint64 para_sig(Paragraph p) {
            uint64 s = p.version * 31 + (uint64) p.inlines.size;
            foreach (var i in p.inlines) {
                var n = i as NoteRef;
                if (n != null) foreach (var q in Story.paragraphs(n.note.blocks)) s = s * 131 + para_sig(q);
                var sh = i as ShapeRun;
                if (sh != null) foreach (var q in Story.paragraphs(sh.text)) s = s * 131 + para_sig(q);
            }
            return s;
        }

        public static uint64 block_sig(Block b) {
            uint64 s = b.version;
            var p = b as Paragraph;
            if (p != null) return s * 7 + para_sig(p);
            var t = b as Table;
            if (t != null) {
                s = s * 1000003 + (uint64) t.rows.size * 1009;
                foreach (var r in t.rows) {
                    s = s * 17 + (uint64) r.cells.size;
                    foreach (var c in r.cells) foreach (var q in Story.paragraphs(c.blocks)) s = s * 131 + para_sig(q);
                }
                return s;
            }
            var f = b as FieldBlock;
            if (f != null) {
                s = s * 13 + (uint64) f.code.hash();
                foreach (var q in Story.paragraphs(f.result)) s = s * 131 + para_sig(q);
            }
            return s;
        }

        public static uint64 design_signature(Document doc) {
            uint64 s = doc.styles.generation * 7919 + (uint64) doc.styles.list.size;
            s = s * 31 + (uint64) doc.numbering.defs.size * 101 + (uint64) doc.numbering.instances.size;
            s = s * 31 + (uint64) doc.comments.size;
            foreach (var c in doc.comments) {
                s = s * 131 + (c.done ? 1 : 2);
                foreach (var q in Story.paragraphs(c.blocks)) s = s * 131 + para_sig(q);
            }
            s = s * 31 + (uint64) doc.sources.size;
            foreach (var hf in doc.header_footers()) foreach (var q in Story.paragraphs(hf.blocks)) s = s * 131 + para_sig(q);
            s = s * 31 + (doc.track_changes ? 1 : 0);
            s = s * 31 + (uint64) (doc.page_color ?? "").hash();
            s = s * 31 + (uint64) doc.meta.title.hash();
            return s;
        }

        private static Document shell(Document doc) {
            var d = new Document();
            d.body.items.clear();
            d.meta = doc.meta;
            d.styles = doc.styles;
            d.numbering = doc.numbering;
            d.comments = doc.comments;
            d.sources = doc.sources;
            d.final_section = doc.final_section;
            d.track_changes = doc.track_changes;
            d.even_odd_headers = doc.even_odd_headers;
            d.page_color = doc.page_color;
            d.watermark = doc.watermark;
            d.lang = doc.lang;
            d.bib_style = doc.bib_style;
            return d;
        }

        public static string encode_block(Document doc, Block b) {
            var d = shell(doc);
            d.comments = new Gee.ArrayList<Comment>();
            var c = b.copy();
            c.uid = b.uid;
            d.body.add(c);
            return Base64.encode(DocxWriter.save(d));
        }

        public static string encode_design(Document doc) {
            var d = shell(doc);
            d.body.add(new Paragraph());
            return Base64.encode(DocxWriter.save(d));
        }

        public static Block? decode_block(string b64) {
            try {
                var d = DocxReader.load(Base64.decode(b64));
                if (d.body.size == 0) return null;
                return d.body[0];
            } catch (Error e) {
                return null;
            }
        }

        public LivePacket full_state(Document doc) {
            assign_uids(doc);
            var p = new LivePacket();
            p.peer = peer_id;
            foreach (var b in doc.body.items) {
                p.order.add(b.uid);
                p.dirty.add(b.uid);
                p.blocks[b.uid] = encode_block(doc, b);
                sent[b.uid] = block_sig(b);
                bases[b.uid] = b.copy();
                remember(b.uid, b);
            }
            p.design = encode_design(doc);
            design_sig = design_signature(doc);
            last_order = order_key(p.order);
            return p;
        }

        public void mark_synced(Document doc) {
            assign_uids(doc);
            sent.clear();
            bases.clear();
            foreach (var b in doc.body.items) {
                sent[b.uid] = block_sig(b);
                bases[b.uid] = b.copy();
                remember(b.uid, b);
            }
            design_sig = design_signature(doc);
        }

        public LivePacket? collect(Document doc) {
            assign_uids(doc);
            var p = new LivePacket();
            p.peer = peer_id;
            var present = new Gee.HashSet<uint>();
            foreach (var b in doc.body.items) {
                p.order.add(b.uid);
                present.add(b.uid);
                uint64 sg = block_sig(b);
                if (!sent.has_key(b.uid) || sent[b.uid] != sg) {
                    p.dirty.add(b.uid);
                    p.blocks[b.uid] = encode_block(doc, b);
                    sent[b.uid] = sg;
                    if (bases.has_key(b.uid)) p.from[b.uid] = content_hash(bases[b.uid]);
                    bases[b.uid] = b.copy();
                    remember(b.uid, b);
                }
            }
            var gone = new Gee.ArrayList<uint>();
            foreach (uint u in sent.keys) if (!present.contains(u)) gone.add(u);
            foreach (uint u in gone) {
                p.dirty.add(u);
                sent.unset(u);
                bases.unset(u);
            }
            uint64 ds = design_signature(doc);
            if (ds != design_sig) {
                p.design = encode_design(doc);
                design_sig = ds;
            }
            string ok = order_key(p.order);
            bool reordered = ok != last_order;
            last_order = ok;
            if (p.dirty.size == 0 && p.design == "" && !reordered) return null;
            return p;
        }

        private static void common(string a, string b, out int pre, out int suf) {
            int la = a.char_count(), lb = b.char_count();
            pre = 0;
            int ia = 0, ib = 0;
            unichar ca, cb;
            while (pre < la && pre < lb) {
                int sa = ia, sb = ib;
                a.get_next_char(ref ia, out ca);
                b.get_next_char(ref ib, out cb);
                if (ca != cb) {
                    ia = sa;
                    ib = sb;
                    break;
                }
                pre++;
            }
            suf = 0;
            string ra = a.reverse(), rb = b.reverse();
            int ja = 0, jb = 0;
            while (suf < la - pre && suf < lb - pre) {
                ra.get_next_char(ref ja, out ca);
                rb.get_next_char(ref jb, out cb);
                if (ca != cb) break;
                suf++;
            }
        }

        private static string para_text(Paragraph p) {
            var sb = new StringBuilder();
            foreach (var i in p.inlines) {
                var t = i as TextRun;
                if (t != null) sb.append(t.text);
                else for (int k = 0; k < i.length; k++) sb.append_unichar(0xFFFC);
            }
            return sb.str;
        }

        public static Paragraph? merge_paragraph(Paragraph base_p, Paragraph local, Paragraph remote, bool local_first = false) {
            string b = para_text(base_p), l = para_text(local), r = para_text(remote);
            if (l == b || l == r) return (Paragraph) remote.copy();
            if (r == b) return (Paragraph) local.copy();
            int lp, ls, rp, rs;
            common(b, l, out lp, out ls);
            common(b, r, out rp, out rs);
            int bl = b.char_count();
            int l_start = lp, l_end = bl - ls;
            int r_start = rp, r_end = bl - rs;
            if (!(l_end <= r_start || r_end <= l_start)) return null;
            var merged = (Paragraph) remote.copy();
            int ins_len = l.char_count() - ls - lp;
            var ins = local.slice(lp, lp + ins_len);
            int shift = 0;
            bool same_point = l_start == l_end && r_start == r_end && l_start == r_start;
            if (r_end <= l_start && !(same_point && local_first)) shift = (r.char_count() - rs - rp) - (r_end - r_start);
            int at = l_start + shift;
            merged.cut(at, at + (l_end - l_start));
            int pos = at;
            foreach (var it in ins) {
                merged.insert_inline(pos, it.copy());
                pos += it.length;
            }
            merged.normalize();
            return merged;
        }

        public bool apply(Document doc, LivePacket p) {
            assign_uids(doc);
            bool changed = false;
            if (p.design != "") {
                try {
                    var d = DocxReader.load(Base64.decode(p.design));
                    doc.styles = d.styles;
                    doc.styles.touch();
                    doc.numbering = d.numbering;
                    doc.comments = d.comments;
                    doc.sources = d.sources;
                    doc.final_section = d.final_section;
                    doc.track_changes = d.track_changes;
                    doc.even_odd_headers = d.even_odd_headers;
                    doc.page_color = d.page_color;
                    doc.watermark = d.watermark;
                    doc.meta.title = d.meta.title;
                    design_sig = design_signature(doc);
                    changed = true;
                } catch (Error e) {
                }
            }
            var local_index = new Gee.HashMap<uint, int>();
            for (int i = 0; i < doc.body.size; i++) local_index[doc.body[i].uid] = i;
            foreach (uint u in p.dirty) {
                if (!p.blocks.has_key(u)) {
                    if (!p.order.contains(u) && local_index.has_key(u)) {
                        var victim = doc.body[local_index[u]];
                        doc.body.items.remove(victim);
                        sent.unset(u);
                        bases.unset(u);
                        changed = true;
                        local_index.clear();
                        for (int i = 0; i < doc.body.size; i++) local_index[doc.body[i].uid] = i;
                    }
                    continue;
                }
                var nb = decode_block(p.blocks[u]);
                if (nb == null) continue;
                nb.uid = u;
                if (local_index.has_key(u)) {
                    int idx = local_index[u];
                    var cur = doc.body[idx];
                    Block result = nb;
                    Block? basis = null;
                    if (p.from.has_key(u) && history.has_key(u) && history[u].has_key(p.from[u])) basis = history[u][p.from[u]];
                    else if (bases.has_key(u)) basis = bases[u];
                    if (basis != null && cur is Paragraph && nb is Paragraph && basis is Paragraph) {
                        var m = merge_paragraph((Paragraph) basis, (Paragraph) cur, (Paragraph) nb, strcmp(peer_id, p.peer) < 0);
                        if (m != null) {
                            m.uid = u;
                            result = m;
                            merged_conflicts++;
                        }
                    }
                    doc.body.items[idx] = result;
                    result.parent = doc.body;
                    result.touch();
                    bases[u] = nb.copy();
                    remember(u, nb);
                    sent[u] = result == nb ? block_sig(result) : 0;
                } else {
                    int at = doc.body.size;
                    int ri = p.order.index_of(u);
                    for (int k = ri - 1; k >= 0; k--) {
                        if (local_index.has_key(p.order[k])) {
                            at = local_index[p.order[k]] + 1;
                            break;
                        }
                        if (k == 0) at = 0;
                    }
                    if (ri == 0) at = 0;
                    doc.body.insert(at, nb);
                    bases[u] = nb.copy();
                    remember(u, nb);
                    sent[u] = block_sig(nb);
                    local_index.clear();
                    for (int i = 0; i < doc.body.size; i++) local_index[doc.body[i].uid] = i;
                }
                changed = true;
            }
            if (p.order.size > 0) {
                var rank = new Gee.HashMap<uint, int>();
                for (int i = 0; i < p.order.size; i++) rank[p.order[i]] = i;
                var known = new Gee.ArrayList<Block>();
                var local_only = new Gee.ArrayList<Block>();
                var after = new Gee.HashMap<Block, uint>();
                uint last = 0;
                foreach (var b in doc.body.items) {
                    if (rank.has_key(b.uid)) {
                        known.add(b);
                        last = b.uid;
                    } else {
                        local_only.add(b);
                        after[b] = last;
                    }
                }
                var sorted = new Gee.ArrayList<Block>();
                sorted.add_all(known);
                sorted.sort((a, b) => rank[a.uid] - rank[b.uid]);
                bool same = true;
                for (int i = 0; i < known.size; i++) if (known[i] != sorted[i]) same = false;
                if (!same) {
                    var result = new Gee.ArrayList<Block>();
                    foreach (var b in local_only) if (after[b] == 0) result.add(b);
                    foreach (var b in sorted) {
                        result.add(b);
                        foreach (var o in local_only) if (after[o] == b.uid) result.add(o);
                    }
                    doc.body.items.clear();
                    foreach (var b in result) doc.body.add(b);
                    changed = true;
                }
            }
            if (doc.body.size == 0) doc.body.add(new Paragraph());
            return changed;
        }

        public static LivePosition? position_of(Document doc, Pos pos) {
            var root = Story.root_of(doc, pos.para);
            if (root != doc.body) return null;
            Block? top = pos.para;
            while (top != null && top.parent != doc.body) {
                var owner = top.parent != null ? top.parent.owner : null;
                if (owner is TableCell) top = doc.find_table_of((TableCell) owner);
                else if (owner is FieldBlock) top = (FieldBlock) owner;
                else return null;
            }
            if (top == null) return null;
            var lp = new LivePosition();
            lp.block = top.uid;
            var single = new BlockList();
            single.items.add(top);
            lp.para = Story.paragraphs(single).index_of(pos.para);
            lp.offset = pos.offset;
            return lp.para >= 0 ? lp : null;
        }

        public static Pos? resolve(Document doc, LivePosition lp) {
            foreach (var b in doc.body.items) {
                if (b.uid != lp.block) continue;
                var single = new BlockList();
                single.items.add(b);
                var ps = Story.paragraphs(single);
                if (lp.para < 0 || lp.para >= ps.size) return null;
                return new Pos(ps[lp.para], lp.offset.clamp(0, ps[lp.para].length));
            }
            return null;
        }
    }
}
