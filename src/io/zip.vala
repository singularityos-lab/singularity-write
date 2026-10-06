namespace Write {

    public errordomain FormatError {
        INVALID,
        UNSUPPORTED,
        ENCRYPTED
    }

    public class ZipReader : Object {
        private uint8[] data;
        private Gee.HashMap<string, Entry> entries = new Gee.HashMap<string, Entry>();
        private Gee.ArrayList<string> order = new Gee.ArrayList<string>();

        private class Entry {
            public uint16 method;
            public uint16 flags;
            public uint32 compressed;
            public uint32 size;
            public uint32 offset;
        }

        public ZipReader(uint8[] data) throws FormatError {
            this.data = data;
            int eocd = -1;
            for (int i = data.length - 22; i >= 0 && i >= data.length - 65557; i--) {
                if (u32(i) == 0x06054b50) {
                    eocd = i;
                    break;
                }
            }
            if (eocd < 0) throw new FormatError.INVALID("not a zip archive");
            int count = u16(eocd + 10);
            int pos = (int) u32(eocd + 16);
            for (int n = 0; n < count; n++) {
                if (pos < 0 || pos + 46 > data.length || u32(pos) != 0x02014b50) throw new FormatError.INVALID("bad zip central directory");
                var e = new Entry();
                e.flags = u16(pos + 8);
                e.method = u16(pos + 10);
                e.compressed = u32(pos + 20);
                e.size = u32(pos + 24);
                int name_len = u16(pos + 28);
                int extra_len = u16(pos + 30);
                int comment_len = u16(pos + 32);
                e.offset = u32(pos + 42);
                if (pos + 46 + name_len > data.length) throw new FormatError.INVALID("bad zip entry name");
                var nb = new StringBuilder();
                nb.append_len((string) ((uint8*) data + pos + 46), name_len);
                string name = nb.str.replace("\\", "/");
                entries[name] = e;
                order.add(name);
                pos += 46 + name_len + extra_len + comment_len;
            }
        }

        public static bool is_zip(uint8[] d) {
            return d.length > 4 && d[0] == 'P' && d[1] == 'K' && d[2] == 3 && d[3] == 4;
        }

        private uint16 u16(int i) {
            return (uint16) (data[i] | (data[i + 1] << 8));
        }

        private uint32 u32(int i) {
            return (uint32) data[i] | ((uint32) data[i + 1] << 8) | ((uint32) data[i + 2] << 16) | ((uint32) data[i + 3] << 24);
        }

        public bool has(string name) {
            return find(name) != null;
        }

        public Gee.List<string> names() {
            return order;
        }

        private string? find(string name) {
            string n = name.has_prefix("/") ? name.substring(1) : name;
            if (entries.has_key(n)) return n;
            string f = n.casefold();
            foreach (var k in order) if (k.casefold() == f) return k;
            return null;
        }

        public bool is_encrypted(string name) {
            var k = find(name);
            return k != null && (entries[k].flags & 1) != 0;
        }

        public uint8[]? read(string name) throws Error {
            var k = find(name);
            if (k == null) return null;
            var e = entries[k];
            if ((e.flags & 1) != 0) throw new FormatError.ENCRYPTED("entry %s is encrypted", k);
            int p = (int) e.offset;
            if (p + 30 > data.length || u32(p) != 0x04034b50) throw new FormatError.INVALID("bad zip local header");
            int start = p + 30 + u16(p + 26) + u16(p + 28);
            int end = start + (int) e.compressed;
            if (end > data.length || start > end) throw new FormatError.INVALID("truncated zip entry");
            uint8[] raw = data[start:end];
            if (e.method == 0) return raw;
            if (e.method != 8) throw new FormatError.UNSUPPORTED("zip compression method %d", e.method);
            var conv = new ZlibDecompressor(ZlibCompressorFormat.RAW);
            var input = new MemoryInputStream.from_data(raw);
            var stream = new ConverterInputStream(input, conv);
            var out_buf = new ByteArray.sized(e.size > 0 ? e.size : 4096);
            uint8[] chunk = new uint8[65536];
            ssize_t n;
            while ((n = stream.read(chunk)) > 0) out_buf.append(chunk[0:n]);
            return out_buf.steal();
        }

        public Bytes? read_bytes(string name) throws Error {
            var d = read(name);
            return d != null ? new Bytes(d) : null;
        }

        public string? read_text(string name) throws Error {
            var b = read(name);
            if (b == null) return null;
            var sb = new StringBuilder.sized(b.length + 1);
            sb.append_len((string) b, b.length);
            string s = sb.str;
            if (s.has_prefix("\xef\xbb\xbf")) s = s.substring(3);
            return s;
        }
    }

    public class ZipWriter : Object {
        private ByteArray out_data = new ByteArray();
        private ByteArray central = new ByteArray();
        private int count = 0;
        private uint dos_time;
        private uint dos_date;
        private Gee.HashSet<string> written = new Gee.HashSet<string>();

        public ZipWriter() {
            var now = new DateTime.now_local();
            dos_time = (now.get_hour() << 11) | (now.get_minute() << 5) | (now.get_second() / 2);
            dos_date = ((now.get_year() - 1980) << 9) | (now.get_month() << 5) | now.get_day_of_month();
        }

        private static void put16(ByteArray b, uint v) {
            uint8[] x = { (uint8) (v & 0xff), (uint8) ((v >> 8) & 0xff) };
            b.append(x);
        }

        private static void put32(ByteArray b, uint32 v) {
            uint8[] x = { (uint8) (v & 0xff), (uint8) ((v >> 8) & 0xff), (uint8) ((v >> 16) & 0xff), (uint8) ((v >> 24) & 0xff) };
            b.append(x);
        }

        public bool contains(string name) {
            return written.contains(name);
        }

        public void add_text(string name, string text, bool compress = true) throws Error {
            add(name, text.data, compress);
        }

        public void add(string name, uint8[] content, bool compress = true) throws Error {
            if (written.contains(name)) return;
            written.add(name);
            uint32 crc = (uint32) ZLib.Utility.crc32(0, content);
            uint8[] payload = content;
            uint16 method = 0;
            if (compress && content.length > 0) {
                var conv = new ZlibCompressor(ZlibCompressorFormat.RAW, 6);
                var mem = new MemoryOutputStream.resizable();
                var stream = new ConverterOutputStream(mem, conv);
                size_t w;
                stream.write_all(content, out w);
                stream.close();
                payload = mem.steal_data();
                payload.length = (int) mem.get_data_size();
                method = 8;
            }
            uint32 offset = out_data.len;
            put32(out_data, 0x04034b50);
            put16(out_data, 20);
            put16(out_data, 0x0800);
            put16(out_data, method);
            put16(out_data, dos_time);
            put16(out_data, dos_date);
            put32(out_data, crc);
            put32(out_data, payload.length);
            put32(out_data, content.length);
            put16(out_data, name.length);
            put16(out_data, 0);
            out_data.append(name.data);
            out_data.append(payload);

            put32(central, 0x02014b50);
            put16(central, 20);
            put16(central, 20);
            put16(central, 0x0800);
            put16(central, method);
            put16(central, dos_time);
            put16(central, dos_date);
            put32(central, crc);
            put32(central, payload.length);
            put32(central, content.length);
            put16(central, name.length);
            put16(central, 0);
            put16(central, 0);
            put16(central, 0);
            put16(central, 0);
            put32(central, 0);
            put32(central, offset);
            central.append(name.data);
            count++;
        }

        public uint8[] finish() {
            uint32 cd_offset = out_data.len;
            uint32 cd_size = central.len;
            out_data.append(central.data);
            put32(out_data, 0x06054b50);
            put16(out_data, 0);
            put16(out_data, 0);
            put16(out_data, count);
            put16(out_data, count);
            put32(out_data, cd_size);
            put32(out_data, cd_offset);
            put16(out_data, 0);
            return out_data.steal();
        }
    }

    public static void write_atomically(string path, uint8[] data) throws Error {
        var file = File.new_for_path(path);
        file.replace_contents(data, null, false, FileCreateFlags.NONE, null, null);
    }
}
