namespace Write {

    public class CfbReader : Object {
        private uint8[] data;
        private int sector_size;
        private int mini_size;
        private uint32 mini_cutoff;
        private uint32[] fat = {};
        private uint32[] minifat = {};
        private uint8[] ministream = {};
        public Gee.HashMap<string, int> entries = new Gee.HashMap<string, int>();
        private Gee.ArrayList<uint32> starts = new Gee.ArrayList<uint32>();
        private Gee.ArrayList<uint32> sizes = new Gee.ArrayList<uint32>();

        public CfbReader(uint8[] data) throws FormatError {
            this.data = data;
            if (data.length < 512 || data[0] != 0xD0 || data[1] != 0xCF) throw new FormatError.INVALID("not a compound file");
            sector_size = 1 << u16(0x1E);
            mini_size = 1 << u16(0x20);
            mini_cutoff = u32(0x38);
            uint32 nfat = u32(0x2C);
            uint32 dir_start = u32(0x30);
            uint32 minifat_start = u32(0x3C);
            uint32 difat_start = u32(0x44);
            uint32[] difat = {};
            for (int i = 0; i < 109; i++) {
                uint32 v = u32(0x4C + i * 4);
                if (v != 0xFFFFFFFF) difat += v;
            }
            uint32 ds = difat_start;
            int guard = 0;
            while (ds != 0xFFFFFFFE && ds != 0xFFFFFFFF && guard++ < 10000) {
                int off = sector_offset(ds);
                int per = sector_size / 4 - 1;
                for (int i = 0; i < per; i++) {
                    uint32 v = u32(off + i * 4);
                    if (v != 0xFFFFFFFF) difat += v;
                }
                ds = u32(off + per * 4);
            }
            for (int i = 0; i < difat.length && i < (int) nfat; i++) {
                int off = sector_offset(difat[i]);
                for (int k = 0; k < sector_size / 4; k++) fat += u32(off + k * 4);
            }
            var dir = chain(dir_start, fat, sector_size, null);
            for (int i = 0; i + 128 <= dir.length; i += 128) {
                int name_len = dir[i + 0x40] | (dir[i + 0x41] << 8);
                var sb = new StringBuilder();
                for (int k = 0; k + 1 < name_len - 2 && k < 64; k += 2) sb.append_unichar((unichar) (dir[i + k] | (dir[i + k + 1] << 8)));
                uint32 start = (uint32) dir[i + 0x74] | ((uint32) dir[i + 0x75] << 8) | ((uint32) dir[i + 0x76] << 16) | ((uint32) dir[i + 0x77] << 24);
                uint32 size = (uint32) dir[i + 0x78] | ((uint32) dir[i + 0x79] << 8) | ((uint32) dir[i + 0x7A] << 16) | ((uint32) dir[i + 0x7B] << 24);
                int type = dir[i + 0x42];
                starts.add(start);
                sizes.add(size);
                if (type == 5) {
                    ministream = chain(start, fat, sector_size, size);
                } else if (type == 2 && !entries.has_key(sb.str)) {
                    entries[sb.str] = starts.size - 1;
                }
            }
            if (minifat_start != 0xFFFFFFFE) {
                var mf = chain(minifat_start, fat, sector_size, null);
                for (int i = 0; i + 4 <= mf.length; i += 4) minifat += (uint32) mf[i] | ((uint32) mf[i + 1] << 8) | ((uint32) mf[i + 2] << 16) | ((uint32) mf[i + 3] << 24);
            }
        }

        private int sector_offset(uint32 s) {
            return (int) ((s + 1) * sector_size);
        }

        private uint16 u16(int i) {
            return (uint16) (data[i] | (data[i + 1] << 8));
        }

        private uint32 u32(int i) {
            if (i + 4 > data.length) return uint32.MAX;
            return (uint32) data[i] | ((uint32) data[i + 1] << 8) | ((uint32) data[i + 2] << 16) | ((uint32) data[i + 3] << 24);
        }

        private uint8[] chain(uint32 start, uint32[] table, int ssize, uint32? limit) {
            var out_buf = new ByteArray();
            uint32 s = start;
            int guard = 0;
            bool mini = ssize == mini_size && table == minifat;
            while (s != 0xFFFFFFFE && s != 0xFFFFFFFF && s < table.length && guard++ < 1000000) {
                if (mini) {
                    int off = (int) (s * ssize);
                    if (off + ssize > ministream.length) break;
                    out_buf.append(ministream[off:off + ssize]);
                } else {
                    int off = sector_offset(s);
                    if (off + ssize > data.length) {
                        if (off < data.length) out_buf.append(data[off:data.length]);
                        break;
                    }
                    out_buf.append(data[off:off + ssize]);
                }
                if (limit != null && out_buf.len >= limit) break;
                s = table[s];
            }
            if (limit != null && out_buf.len > limit) out_buf.set_size(limit);
            return out_buf.steal();
        }

        public uint8[]? stream(string name) {
            if (!entries.has_key(name)) return null;
            int idx = entries[name];
            uint32 size = sizes[idx];
            if (size < mini_cutoff) return chain(starts[idx], minifat, mini_size, size);
            return chain(starts[idx], fat, sector_size, size);
        }
    }

    public class DocReader : Object {
        private uint8[] wd;
        private uint8[] table;
        private Gee.ArrayList<Run> chp_runs = new Gee.ArrayList<Run>();
        private Gee.ArrayList<PRun> pap_runs = new Gee.ArrayList<PRun>();

        private class Run {
            public uint32 fc_start;
            public uint32 fc_end;
            public CharProps props;
        }

        private class PRun {
            public uint32 fc_start;
            public uint32 fc_end;
            public int istd;
            public bool in_table;
            public bool ttp;
            public Align align = Align.INHERIT;
        }

        public static Document load(uint8[] data) throws Error {
            return new DocReader().read(data);
        }

        private static uint16 r16(uint8[] b, int i) {
            if (i + 2 > b.length) return 0;
            return (uint16) (b[i] | (b[i + 1] << 8));
        }

        private static uint32 r32(uint8[] b, int i) {
            if (i + 4 > b.length) return 0;
            return (uint32) b[i] | ((uint32) b[i + 1] << 8) | ((uint32) b[i + 2] << 16) | ((uint32) b[i + 3] << 24);
        }

        public Document read(uint8[] data) throws Error {
            var cfb = new CfbReader(data);
            wd = cfb.stream("WordDocument");
            if (wd == null || wd.length < 0x200 || r16(wd, 0) != 0xA5EC) throw new FormatError.INVALID(_("The file is not a Word 97-2003 document."));
            uint16 flags = r16(wd, 0x0A);
            if ((flags & 0x0100) != 0) throw new FormatError.ENCRYPTED(_("The document is password protected."));
            table = cfb.stream((flags & 0x0200) != 0 ? "1Table" : "0Table");
            if (table == null) throw new FormatError.INVALID(_("The document has no table stream."));
            int csw = r16(wd, 32);
            int lw_off = 32 + 2 + csw * 2;
            int cslw = r16(wd, lw_off);
            int ccp_text = (int) r32(wd, lw_off + 2 + 3 * 4);
            int fclcb = lw_off + 2 + cslw * 4 + 2;
            uint32 fc_clx = r32(wd, fclcb + 33 * 8);
            uint32 lcb_clx = r32(wd, fclcb + 33 * 8 + 4);
            uint32 fc_bte_chpx = r32(wd, fclcb + 12 * 8);
            uint32 lcb_bte_chpx = r32(wd, fclcb + 12 * 8 + 4);
            uint32 fc_bte_papx = r32(wd, fclcb + 13 * 8);
            uint32 lcb_bte_papx = r32(wd, fclcb + 13 * 8 + 4);
            read_chpx(fc_bte_chpx, lcb_bte_chpx);
            read_papx(fc_bte_papx, lcb_bte_papx);
            var doc = Document.create_blank();
            doc.body.clear();
            build(doc, fc_clx, lcb_clx, ccp_text);
            read_props(cfb, doc);
            if (doc.body.size == 0) doc.body.add(new Paragraph());
            return doc;
        }

        private void read_props(CfbReader cfb, Document doc) {
            var si = cfb.stream("\x05SummaryInformation");
            if (si == null || si.length < 48) return;
            uint32 off = r32(si, 44);
            if (off + 8 > si.length) return;
            uint32 count = r32(si, (int) off + 4);
            for (uint32 i = 0; i < count && i < 64; i++) {
                uint32 pid = r32(si, (int) (off + 8 + i * 8));
                uint32 poff = r32(si, (int) (off + 12 + i * 8));
                int p = (int) (off + poff);
                if (p + 8 > si.length || r32(si, p) != 30) continue;
                uint32 len = r32(si, p + 4);
                if (p + 8 + len > si.length || len == 0) continue;
                var sb = new StringBuilder();
                for (int k = 0; k < (int) len && si[p + 8 + k] != 0; k++) sb.append_c((char) si[p + 8 + k]);
                string v = Formats.decode_text(sb.str.data);
                if (pid == 2) doc.meta.title = v;
                else if (pid == 3) doc.meta.subject = v;
                else if (pid == 4) doc.meta.author = v;
                else if (pid == 5) doc.meta.keywords = v;
                else if (pid == 6) doc.meta.description = v;
            }
        }

        private int sprm_size(uint16 sprm, uint8[] b, int pos) {
            int spra = sprm >> 13;
            switch (spra) {
                case 0:
                case 1: return 1;
                case 2:
                case 4:
                case 5: return 2;
                case 3: return 4;
                case 7: return 3;
                default:
                    if (sprm == 0xD608 || sprm == 0xC615) return (int) r16(b, pos) + 1;
                    return pos < b.length ? b[pos] + 1 : 1;
            }
        }

        private void apply_chp(CharProps c, uint8[] g, int start, int end) {
            int p = start;
            while (p + 2 <= end) {
                uint16 sprm = r16(g, p);
                p += 2;
                int sz = sprm_size(sprm, g, p);
                if (p + sz > end) break;
                uint8 v = g[p];
                switch (sprm) {
                    case 0x0835: c.bold = v == 0 ? Tri.OFF : Tri.ON; break;
                    case 0x0836: c.italic = v == 0 ? Tri.OFF : Tri.ON; break;
                    case 0x0837: c.strike = v == 0 ? Tri.OFF : Tri.ON; break;
                    case 0x2A53: c.dstrike = v == 0 ? Tri.OFF : Tri.ON; break;
                    case 0x083A: c.caps = v == 0 ? Caps.NONE : Caps.SMALL; break;
                    case 0x083B: c.caps = v == 0 ? Caps.NONE : Caps.ALL; break;
                    case 0x083C: c.hidden = v == 0 ? Tri.OFF : Tri.ON; break;
                    case 0x2A3E: c.underline = v == 0 ? Underline.NONE : (v == 3 ? Underline.DOUBLE : (v == 4 ? Underline.DOTTED : Underline.SINGLE)); break;
                    case 0x4A43: c.size = r16(g, p) / 2.0; break;
                    case 0x2A48: c.valign = v == 1 ? VAlign.SUPER : (v == 2 ? VAlign.SUB : VAlign.BASELINE); break;
                    case 0x2A42: c.color = ico_color(v); break;
                    case 0x2A0C: c.highlight = ico_color(v); break;
                    case 0x6870:
                        c.color = "#%02x%02x%02x".printf(g[p], g[p + 1], g[p + 2]);
                        break;
                    default: break;
                }
                p += sz;
            }
        }

        private static string? ico_color(uint8 ico) {
            string[] map = { "", "#000000", "#0000ff", "#00ffff", "#00ff00", "#ff00ff", "#ff0000", "#ffff00", "#ffffff", "#000080", "#008080", "#008000", "#800080", "#800000", "#808000", "#808080", "#c0c0c0" };
            if (ico == 0 || ico >= map.length) return null;
            return map[ico];
        }

        private void read_chpx(uint32 fc, uint32 lcb) {
            if (lcb < 8 || fc + lcb > table.length) return;
            int n = (int) ((lcb - 4) / 8);
            for (int i = 0; i < n; i++) {
                uint32 pn = r32(table, (int) (fc + (n + 1) * 4 + i * 4)) & 0x3FFFFF;
                int page = (int) (pn * 512);
                if (page + 512 > wd.length) continue;
                int crun = wd[page + 511];
                for (int k = 0; k < crun; k++) {
                    var run = new Run();
                    run.fc_start = r32(wd, page + k * 4);
                    run.fc_end = r32(wd, page + (k + 1) * 4);
                    run.props = new CharProps();
                    int b = wd[page + (crun + 1) * 4 + k];
                    if (b != 0) {
                        int off = page + b * 2;
                        int cb = wd[off];
                        apply_chp(run.props, wd, off + 1, int.min(off + 1 + cb, page + 511));
                    }
                    chp_runs.add(run);
                }
            }
        }

        private void read_papx(uint32 fc, uint32 lcb) {
            if (lcb < 8 || fc + lcb > table.length) return;
            int n = (int) ((lcb - 4) / 8);
            for (int i = 0; i < n; i++) {
                uint32 pn = r32(table, (int) (fc + (n + 1) * 4 + i * 4)) & 0x3FFFFF;
                int page = (int) (pn * 512);
                if (page + 512 > wd.length) continue;
                int crun = wd[page + 511];
                for (int k = 0; k < crun; k++) {
                    var run = new PRun();
                    run.fc_start = r32(wd, page + k * 4);
                    run.fc_end = r32(wd, page + (k + 1) * 4);
                    int bx = page + (crun + 1) * 4 + k * 13;
                    int b = wd[bx];
                    if (b != 0) {
                        int off = page + b * 2;
                        int cb = wd[off];
                        int size;
                        int start;
                        if (cb == 0) {
                            size = wd[off + 1] * 2;
                            start = off + 2;
                        } else {
                            size = cb * 2 - 1;
                            start = off + 1;
                        }
                        run.istd = r16(wd, start);
                        int p = start + 2;
                        int end = int.min(start + size, page + 511);
                        while (p + 2 <= end) {
                            uint16 sprm = r16(wd, p);
                            p += 2;
                            int sz = sprm_size(sprm, wd, p);
                            if (p + sz > end) break;
                            switch (sprm) {
                                case 0x2416: run.in_table = wd[p] != 0; break;
                                case 0x2417: run.ttp = wd[p] != 0; break;
                                case 0x2403:
                                case 0x2461:
                                    uint8 jc = wd[p];
                                    run.align = jc == 1 ? Align.CENTER : (jc == 2 ? Align.RIGHT : (jc == 3 ? Align.JUSTIFY : Align.LEFT));
                                    break;
                                default: break;
                            }
                            p += sz;
                        }
                    }
                    pap_runs.add(run);
                }
            }
        }

        private CharProps props_at(uint32 fc) {
            foreach (var r in chp_runs) if (fc >= r.fc_start && fc < r.fc_end) return r.props;
            return new CharProps();
        }

        private PRun? pap_at(uint32 fc) {
            foreach (var r in pap_runs) if (fc >= r.fc_start && fc < r.fc_end) return r;
            return null;
        }

        private void build(Document doc, uint32 fc_clx, uint32 lcb_clx, int ccp_text) {
            int p = (int) fc_clx;
            int end = (int) (fc_clx + lcb_clx);
            while (p < end && p < table.length && table[p] == 0x01) {
                int cb = r16(table, p + 1);
                p += 3 + cb;
            }
            if (p >= end || p >= table.length || table[p] != 0x02) return;
            uint32 lcb = r32(table, p + 1);
            int plc = p + 5;
            int n = (int) ((lcb - 4) / 12);
            var para = new Paragraph();
            var text = new StringBuilder();
            CharProps? cur = null;
            Table? tbl = null;
            TableRow? row = null;
            TableCell? cell = null;
            int field_depth = 0;
            bool field_result = false;
            var field_code = new StringBuilder();
            var field_res = new StringBuilder();
            uint32 last_fc = 0;
            int cp_total = 0;
            for (int i = 0; i < n && cp_total < ccp_text; i++) {
                uint32 cp_start = r32(table, plc + i * 4);
                uint32 cp_end = r32(table, plc + (i + 1) * 4);
                int pcd = plc + (n + 1) * 4 + i * 8;
                uint32 fc = r32(table, pcd + 2);
                bool compressed = (fc & 0x40000000) != 0;
                uint32 base_fc = compressed ? (fc & ~0x40000000) / 2 : fc;
                for (uint32 cp = cp_start; cp < cp_end && cp_total < ccp_text; cp++) {
                    cp_total++;
                    uint32 cfc;
                    unichar ch;
                    if (compressed) {
                        cfc = base_fc + (cp - cp_start);
                        if (cfc >= wd.length) break;
                        uint8 b = wd[cfc];
                        ch = b;
                        if (b >= 0x80) {
                            try {
                                uint8[] one = { b, 0 };
                                ch = convert((string) one, 1, "UTF-8", "CP1252").get_char(0);
                            } catch (Error e) {
                            }
                        }
                    } else {
                        cfc = base_fc + (cp - cp_start) * 2;
                        if (cfc + 1 >= wd.length) break;
                        ch = (unichar) r16(wd, (int) cfc);
                    }
                    last_fc = cfc;
                    if (ch == 0x13) {
                        field_depth++;
                        if (field_depth == 1) {
                            flush(para, text, cur);
                            field_code.truncate(0);
                            field_res.truncate(0);
                            field_result = false;
                        }
                        continue;
                    }
                    if (ch == 0x14 && field_depth > 0) {
                        if (field_depth == 1) field_result = true;
                        continue;
                    }
                    if (ch == 0x15 && field_depth > 0) {
                        field_depth--;
                        if (field_depth == 0) {
                            string code = field_code.str.strip();
                            if (code.up().has_prefix("HYPERLINK")) {
                                string[] toks = Fields.tokenize(code);
                                var lp = props_at(cfc).copy();
                                lp.link = toks.length > 1 ? toks[1] : "";
                                if (field_res.len > 0) para.inlines.add(new TextRun(field_res.str, lp));
                            } else if (code != "") {
                                var f = new FieldRun(code, field_res.str);
                                f.dirty = false;
                                f.props = props_at(cfc).copy();
                                para.inlines.add(f);
                            }
                        }
                        continue;
                    }
                    if (field_depth > 0) {
                        if (ch >= 0x20 || ch == '\t') {
                            if (field_result) field_res.append_unichar(ch);
                            else field_code.append_unichar(ch);
                        }
                        continue;
                    }
                    var props = props_at(cfc);
                    if (cur != null && props != cur) flush(para, text, cur);
                    cur = props;
                    switch (ch) {
                        case 0x0D:
                        case 0x07:
                            flush(para, text, cur);
                            var pr = pap_at(cfc);
                            if (pr != null && pr.istd >= 1 && pr.istd <= 9) para.style = "Heading%d".printf(pr.istd);
                            if (pr != null && pr.align != Align.INHERIT) para.props.align = pr.align;
                            para.normalize();
                            bool in_table = pr != null && (pr.in_table || pr.ttp) || ch == 0x07;
                            if (in_table) {
                                if (tbl == null) {
                                    tbl = Table.create(0, 1, 450);
                                    tbl.rows.clear();
                                }
                                if (row == null) row = new TableRow();
                                if (pr != null && pr.ttp) {
                                    if (row.cells.size > 0) tbl.rows.add(row);
                                    row = null;
                                    cell = null;
                                } else {
                                    if (cell == null) cell = new TableCell();
                                    cell.blocks.add(para);
                                    if (ch == 0x07) {
                                        row.cells.add(cell);
                                        cell = null;
                                    }
                                }
                            } else {
                                if (tbl != null) {
                                    finish_table(doc, tbl, row);
                                    tbl = null;
                                    row = null;
                                    cell = null;
                                }
                                doc.body.add(para);
                            }
                            para = new Paragraph();
                            break;
                        case 0x09:
                            flush(para, text, cur);
                            para.inlines.add(new Tab());
                            break;
                        case 0x0B:
                            flush(para, text, cur);
                            para.inlines.add(new Break(BreakKind.LINE));
                            break;
                        case 0x0C:
                            flush(para, text, cur);
                            para.inlines.add(new Break(BreakKind.PAGE));
                            break;
                        case 0x0E:
                            flush(para, text, cur);
                            para.inlines.add(new Break(BreakKind.COLUMN));
                            break;
                        case 0x1E:
                            text.append_unichar(0x2011);
                            break;
                        case 0x1F:
                            text.append_unichar(0xAD);
                            break;
                        case 0xA0:
                            text.append_unichar(0xA0);
                            break;
                        default:
                            if (ch >= 0x20) text.append_unichar(ch);
                            break;
                    }
                }
            }
            flush(para, text, cur);
            if (tbl != null) finish_table(doc, tbl, row);
            if (!para.is_empty()) doc.body.add(para);
        }

        private void finish_table(Document doc, Table t, TableRow? row) {
            if (row != null && row.cells.size > 0) t.rows.add(row);
            int cols = t.columns();
            if (cols == 0) return;
            double[] g = new double[cols];
            for (int i = 0; i < cols; i++) g[i] = 450.0 / cols;
            t.grid = g;
            foreach (var r in t.rows) foreach (var c in r.cells) if (c.blocks.size == 0) c.blocks.add(new Paragraph());
            doc.body.add(t);
        }

        private void flush(Paragraph p, StringBuilder text, CharProps? props) {
            if (text.len == 0) return;
            p.inlines.add(new TextRun(text.str, props));
            text.truncate(0);
        }
    }
}
