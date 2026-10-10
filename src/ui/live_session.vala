namespace Singularity.Apps {

    public class WriteLivePeer : Object {
        public string id = "";
        public string name = "";
        public string color = "#1c71d8";
        public Write.LivePosition? focus = null;
        public Write.LivePosition? anchor = null;
        public int64 seen = 0;
    }

    public class WriteLiveSession : Object {
        public signal void packet(Write.LivePacket p);
        public signal void peers_changed();
        public signal void ended(string reason);
        public signal void state_requested();

        public enum Mode {
            HOST,
            GUEST,
            FOLDER,
            COLLAB
        }

        public Mode mode = Mode.HOST;
        public string link = "";
        public string name;
        public string color;
        public string my_id;
        public Gee.HashMap<string, WriteLivePeer> peers = new Gee.HashMap<string, WriteLivePeer>();
        public Write.LivePacket? current_state = null;

        private Soup.Server? server = null;
        private Gee.HashMap<string, Soup.WebsocketConnection> sockets = new Gee.HashMap<string, Soup.WebsocketConnection>();
        private string token = "";
        private int next_id = 1;
        private Soup.WebsocketConnection? ws = null;
        private string folder = "";
        private uint poll_id = 0;
        private int seq = 0;
        private Gee.HashSet<string> processed = new Gee.HashSet<string>();
        private Json.Object? my_presence = null;
        public string collab_session = "";
        public bool collab_hosting = false;
        private ulong collab_raw_id = 0;
        private ulong collab_joined_id = 0;
        private ulong collab_ended_id = 0;
        private int collab_sent = 0;

        public WriteLiveSession(string name) {
            this.name = name;
            my_id = "u" + Uuid.string_random().substring(0, 8);
            string[] colors = { "#e01b24", "#2ec27e", "#9141ac", "#ff7800", "#1c71d8", "#c64600", "#26a269", "#813d9c" };
            color = colors[Random.int_range(0, colors.length)];
        }

        private static string encode(Json.Object o) {
            var node = new Json.Node(Json.NodeType.OBJECT);
            node.set_object(o);
            return Json.to_string(node, false);
        }

        private static Json.Object? decode_text(string text) {
            try {
                var parser = new Json.Parser();
                parser.load_from_data(text);
                var root = parser.get_root();
                return root != null && root.get_node_type() == Json.NodeType.OBJECT ? root.get_object() : null;
            } catch (Error e) {
                return null;
            }
        }

        private static Json.Object? decode(Bytes bytes) {
            return decode_text(((string) bytes.get_data()).make_valid((ssize_t) bytes.get_size()));
        }

        private static string lan_address() {
            try {
                var sock = new Socket(SocketFamily.IPV4, SocketType.DATAGRAM, SocketProtocol.UDP);
                sock.connect(new InetSocketAddress(new InetAddress.from_string("192.0.2.1"), 9));
                var local = (InetSocketAddress) sock.get_local_address();
                string a = local.address.to_string();
                sock.close();
                if (a != "0.0.0.0") return a;
            } catch (Error e) {
            }
            return "127.0.0.1";
        }

        public static bool parse_link(string link, out string url, out string key) {
            url = "";
            key = "";
            string l = link.strip();
            if (l.has_prefix("write-live://")) l = "ws://" + l.substring(13);
            try {
                var uri = Uri.parse(l, UriFlags.NONE);
                string? q = uri.get_query();
                if (q == null) return false;
                var p = Uri.parse_params(q, -1, "&", UriParamsFlags.NONE);
                key = p["key"] ?? "";
                url = "ws://%s:%d/write".printf(uri.get_host(), uri.get_port() > 0 ? uri.get_port() : 7791);
                return key != "";
            } catch (Error e) {
                return false;
            }
        }

        private static Json.Object? pos_json(Write.LivePosition? p) {
            if (p == null) return null;
            var o = new Json.Object();
            o.set_int_member("b", p.block);
            o.set_int_member("p", p.para);
            o.set_int_member("o", p.offset);
            return o;
        }

        private static Write.LivePosition? pos_from(Json.Object o, string key) {
            if (!o.has_member(key)) return null;
            var n = o.get_member(key);
            if (n.get_node_type() != Json.NodeType.OBJECT) return null;
            var po = n.get_object();
            var p = new Write.LivePosition();
            p.block = (uint) po.get_int_member("b");
            p.para = (int) po.get_int_member("p");
            p.offset = (int) po.get_int_member("o");
            return p;
        }

        private Json.Object presence_json(string id, string nm, string col, Write.LivePosition? f, Write.LivePosition? a) {
            var o = new Json.Object();
            o.set_string_member("t", "presence");
            o.set_string_member("id", id);
            o.set_string_member("name", nm);
            o.set_string_member("color", col);
            var fj = pos_json(f);
            if (fj != null) o.set_object_member("focus", fj);
            var aj = pos_json(a);
            if (aj != null) o.set_object_member("anchor", aj);
            return o;
        }

        private void read_presence(Json.Object o) {
            string id = o.get_string_member("id");
            if (id == my_id) return;
            var p = peers.has_key(id) ? peers[id] : new WriteLivePeer();
            p.id = id;
            p.name = o.has_member("name") ? o.get_string_member("name") : _("Guest");
            p.color = o.has_member("color") ? o.get_string_member("color") : "#1c71d8";
            p.focus = pos_from(o, "focus");
            p.anchor = pos_from(o, "anchor");
            p.seen = get_real_time();
            peers[id] = p;
            peers_changed();
        }

        private void handle(Json.Object o, string? from) {
            string t = o.has_member("t") ? o.get_string_member("t") : "";
            if (t == "ops") {
                var pk = Write.LivePacket.from_json(o);
                if (pk.peer == my_id) return;
                packet(pk);
            } else if (t == "presence") {
                read_presence(o);
            } else if (t == "bye") {
                string id = o.get_string_member("id");
                if (peers.unset(id)) peers_changed();
            }
        }

        private void broadcast(Json.Object o, string? except) {
            string text = encode(o);
            foreach (var e in sockets.entries) if (e.key != except && e.value.state == Soup.WebsocketState.OPEN) e.value.send_text(text);
        }

        public void host(Write.LivePacket state, uint port = 0) throws Error {
            mode = Mode.HOST;
            current_state = state;
            token = Uuid.string_random().replace("-", "").substring(0, 20);
            server = new Soup.Server("server-header", "SingularityWriteLive");
            server.add_websocket_handler("/write", null, null, on_socket);
            bool loopback = Environment.get_variable("SINGULARITY_WRITE_LIVE_LOOPBACK") != null;
            if (loopback) server.listen_local(port, Soup.ServerListenOptions.IPV4_ONLY);
            else server.listen_all(port, Soup.ServerListenOptions.IPV4_ONLY);
            uint bound = 0;
            foreach (var uri in server.get_uris()) bound = uri.get_port();
            link = "write-live://%s:%u/?key=%s".printf(loopback ? "127.0.0.1" : lan_address(), bound, token);
        }

        private void on_socket(Soup.Server srv, Soup.ServerMessage msg, string path, Soup.WebsocketConnection conn) {
            string cid = "c%d".printf(next_id++);
            bool accepted = false;
            string peer_id = "";
            conn.max_incoming_payload_size = 256 * 1024 * 1024;
            conn.message.connect((type, bytes) => {
                if (type != Soup.WebsocketDataType.TEXT) return;
                var o = decode(bytes);
                if (o == null) return;
                string t = o.has_member("t") ? o.get_string_member("t") : "";
                if (!accepted) {
                    if (t != "hello" || !o.has_member("key") || o.get_string_member("key") != token) {
                        conn.close(Soup.WebsocketCloseCode.POLICY_VIOLATION, null);
                        return;
                    }
                    accepted = true;
                    peer_id = o.get_string_member("id");
                    sockets[cid] = conn;
                    state_requested();
                    var w = new Json.Object();
                    w.set_string_member("t", "welcome");
                    w.set_object_member("state", current_state.to_json());
                    conn.send_text(encode(w));
                    if (my_presence != null) conn.send_text(encode(my_presence));
                    foreach (var p in peers.values) conn.send_text(encode(presence_json(p.id, p.name, p.color, p.focus, p.anchor)));
                    return;
                }
                if (t == "ops" || t == "presence") broadcast(o, cid);
                handle(o, cid);
            });
            conn.closed.connect(() => {
                sockets.unset(cid);
                if (peer_id != "" && peers.unset(peer_id)) {
                    var bye = new Json.Object();
                    bye.set_string_member("t", "bye");
                    bye.set_string_member("id", peer_id);
                    broadcast(bye, null);
                    peers_changed();
                }
            });
        }

        public async void join(string link) throws Error {
            string url, key;
            if (!parse_link(link, out url, out key)) throw new IOError.INVALID_ARGUMENT(_("This is not a live document link."));
            mode = Mode.GUEST;
            this.link = link;
            var session = new Soup.Session();
            var msg = new Soup.Message("GET", url);
            ws = yield session.websocket_connect_async(msg, null, null, Priority.DEFAULT, null);
            ws.max_incoming_payload_size = 256 * 1024 * 1024;
            ws.message.connect((type, bytes) => {
                if (type != Soup.WebsocketDataType.TEXT) return;
                var o = decode(bytes);
                if (o == null) return;
                string t = o.has_member("t") ? o.get_string_member("t") : "";
                if (t == "welcome") {
                    var st = Write.LivePacket.from_json(o.get_object_member("state"));
                    packet(st);
                    return;
                }
                handle(o, null);
            });
            ws.closed.connect(() => {
                ws = null;
                ended(_("The live session ended."));
            });
            var hello = new Json.Object();
            hello.set_string_member("t", "hello");
            hello.set_string_member("key", key);
            hello.set_string_member("id", my_id);
            ws.send_text(encode(hello));
        }

        public void start_folder(string dir, Write.LivePacket? state) throws Error {
            mode = Mode.FOLDER;
            folder = dir;
            DirUtils.create_with_parents(folder, 0700);
            link = folder;
            if (state != null) write_file("state-%s-%s.json".printf(stamp(), my_id), state.to_json());
            else {
                string? newest = null;
                foreach (string n in list_names()) if (n.has_prefix("state-") && (newest == null || strcmp(n, newest) > 0)) newest = n;
                if (newest == null) throw new IOError.NOT_FOUND(_("This folder has no live document yet."));
                var o = read_file(newest);
                if (o != null) packet(Write.LivePacket.from_json(o));
                string cut = newest.substring(6, 16);
                foreach (string n in list_names()) {
                    if (n.has_prefix("ops-") && strcmp(n.substring(4, 16), cut) < 0) processed.add(n);
                    if (n.has_prefix("state-")) processed.add(n);
                }
            }
            foreach (string n in list_names()) if (n.has_suffix("-" + my_id + ".json") || n.contains("-" + my_id + "-")) processed.add(n);
            poll_id = Timeout.add(600, () => {
                poll();
                return Source.CONTINUE;
            });
        }

        private static string stamp() {
            return "%016lld".printf(get_real_time() / 1000);
        }

        private Gee.ArrayList<string> list_names() {
            var names = new Gee.ArrayList<string>();
            try {
                var d = Dir.open(folder);
                string? n;
                while ((n = d.read_name()) != null) if (n.has_suffix(".json")) names.add(n);
            } catch (Error e) {
            }
            names.sort((a, b) => strcmp(a, b));
            return names;
        }

        private Json.Object? read_file(string n) {
            try {
                string text;
                FileUtils.get_contents(Path.build_filename(folder, n), out text);
                return decode_text(text);
            } catch (Error e) {
                return null;
            }
        }

        private void write_file(string n, Json.Object o) {
            try {
                Write.write_atomically(Path.build_filename(folder, n), encode(o).data);
            } catch (Error e) {
                warning("live folder: %s", e.message);
            }
        }

        private void poll() {
            var names = list_names();
            var gone = new Gee.ArrayList<string>();
            foreach (var p in peers.keys) if (!names.contains("presence-%s.json".printf(p))) gone.add(p);
            foreach (string g in gone) peers.unset(g);
            if (gone.size > 0) peers_changed();
            foreach (string n in names) {
                if (n.has_prefix("presence-")) {
                    if (n == "presence-%s.json".printf(my_id)) continue;
                    try {
                        var info = File.new_for_path(Path.build_filename(folder, n)).query_info(FileAttribute.TIME_MODIFIED, FileQueryInfoFlags.NONE);
                        var dt = info.get_modification_date_time();
                        string key = n + (dt != null ? dt.to_unix().to_string() + dt.get_microsecond().to_string() : "");
                        if (processed.contains(key)) continue;
                        processed.add(key);
                    } catch (Error e) {
                        continue;
                    }
                    var o = read_file(n);
                    if (o != null) read_presence(o);
                    continue;
                }
                if (!n.has_prefix("ops-") || processed.contains(n)) continue;
                var o = read_file(n);
                if (o == null) continue;
                processed.add(n);
                handle(o, null);
            }
        }

        private void collab_wire(string session) {
            collab_session = session;
            var client = Singularity.Collab.Client.get_default();
            collab_raw_id = client.raw.connect((sid, author, data) => {
                if (sid != collab_session) return;
                var o = decode_text(data);
                if (o != null) handle(o, null);
            });
            collab_joined_id = client.joined.connect((sid, who) => {
                if (sid != collab_session || !collab_hosting) return;
                state_requested();
                if (current_state != null) client.update_snapshot.begin(collab_session, encode(current_state.to_json()));
                if (my_presence != null) client.send_raw(collab_session, encode(my_presence));
            });
            collab_ended_id = client.ended.connect((sid) => {
                if (sid != collab_session) return;
                collab_unwire();
                ended(_("The live session ended."));
            });
        }

        private void collab_unwire() {
            var client = Singularity.Collab.Client.get_default();
            if (collab_raw_id != 0) client.disconnect(collab_raw_id);
            if (collab_joined_id != 0) client.disconnect(collab_joined_id);
            if (collab_ended_id != 0) client.disconnect(collab_ended_id);
            collab_raw_id = collab_joined_id = collab_ended_id = 0;
            collab_session = "";
        }

        public async void host_collab(Write.LivePacket state, Singularity.Collab.Person person, string title) throws Error {
            current_state = state;
            var client = Singularity.Collab.Client.get_default();
            if (mode == Mode.COLLAB && collab_session != "") {
                yield client.invite(collab_session, person.id);
                return;
            }
            string sid = yield client.share(person.id, "Document", title, encode(state.to_json()));
            mode = Mode.COLLAB;
            collab_hosting = true;
            link = "";
            collab_wire(sid);
        }

        public void join_collab(string session, string snapshot) {
            mode = Mode.COLLAB;
            collab_hosting = false;
            collab_wire(session);
            var o = decode_text(snapshot);
            if (o != null) packet(Write.LivePacket.from_json(o));
            if (my_presence != null) Singularity.Collab.Client.get_default().send_raw(collab_session, encode(my_presence));
        }

        public void send(Write.LivePacket p) {
            p.peer = my_id;
            p.who = name;
            var o = p.to_json();
            switch (mode) {
                case Mode.COLLAB:
                    if (collab_session == "") break;
                    Singularity.Collab.Client.get_default().send_raw(collab_session, encode(o));
                    if (collab_hosting && ++collab_sent % 200 == 0) state_requested();
                    break;
                case Mode.HOST:
                    broadcast(o, null);
                    break;
                case Mode.GUEST:
                    if (ws != null && ws.state == Soup.WebsocketState.OPEN) ws.send_text(encode(o));
                    break;
                case Mode.FOLDER:
                    string n = "ops-%s-%s-%06d.json".printf(stamp(), my_id, ++seq);
                    processed.add(n);
                    write_file(n, o);
                    if (seq % 40 == 0) state_requested();
                    break;
            }
        }

        public void publish_state(Write.LivePacket state) {
            current_state = state;
            if (mode == Mode.COLLAB && collab_hosting && collab_session != "") {
                Singularity.Collab.Client.get_default().update_snapshot.begin(collab_session, encode(state.to_json()));
            }
            if (mode == Mode.FOLDER) {
                string n = "state-%s-%s.json".printf(stamp(), my_id);
                processed.add(n);
                write_file(n, state.to_json());
            }
        }

        public void presence(Write.LivePosition? focus, Write.LivePosition? anchor) {
            var o = presence_json(my_id, name, color, focus, anchor);
            my_presence = o;
            switch (mode) {
                case Mode.COLLAB:
                    if (collab_session != "") Singularity.Collab.Client.get_default().send_raw(collab_session, encode(o));
                    break;
                case Mode.HOST:
                    broadcast(o, null);
                    break;
                case Mode.GUEST:
                    if (ws != null && ws.state == Soup.WebsocketState.OPEN) ws.send_text(encode(o));
                    break;
                case Mode.FOLDER:
                    write_file("presence-%s.json".printf(my_id), o);
                    break;
            }
        }

        public void leave() {
            if (mode == Mode.COLLAB && collab_session != "") {
                var bye = new Json.Object();
                bye.set_string_member("t", "bye");
                bye.set_string_member("id", my_id);
                var client = Singularity.Collab.Client.get_default();
                client.send_raw(collab_session, encode(bye));
                string sid = collab_session;
                collab_unwire();
                client.leave.begin(sid);
            }
            if (poll_id != 0) {
                Source.remove(poll_id);
                poll_id = 0;
            }
            if (mode == Mode.FOLDER && folder != "") FileUtils.remove(Path.build_filename(folder, "presence-%s.json".printf(my_id)));
            if (server != null) {
                foreach (var s in sockets.values) if (s.state == Soup.WebsocketState.OPEN) s.close(Soup.WebsocketCloseCode.GOING_AWAY, null);
                server.disconnect();
                server = null;
            }
            if (ws != null && ws.state == Soup.WebsocketState.OPEN) ws.close(Soup.WebsocketCloseCode.NORMAL, null);
            ws = null;
            sockets.clear();
            peers.clear();
        }
    }
}
