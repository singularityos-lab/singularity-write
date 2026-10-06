using GLib;
using Singularity;

namespace Singularity.Apps {

    public class WriteSearchProvider : Singularity.SearchProviderService {
        private const int MAX_RESULTS = 20;
        private const int64 MAX_READ = 512 * 1024;

        private weak WriteApp app;
        private string[] last_needles = {};

        public WriteSearchProvider(WriteApp app) {
            this.app = app;
        }

        public override async string[] get_initial_results(string[] terms, Cancellable? cancellable) throws Error {
            string[] needles = normalize(terms);
            if (needles.length == 0) return {};
            last_needles = needles;
            string[] hits = {};
            string[] body_hits = {};
            foreach (string uri in candidates()) {
                if (cancellable != null && cancellable.is_cancelled()) break;
                var file = File.new_for_uri(uri);
                string name = display_name(file).down();
                if (all_in(name, needles)) {
                    hits += uri;
                } else if (all_in(read_text(file).down(), needles)) {
                    body_hits += uri;
                }
                if (hits.length + body_hits.length >= MAX_RESULTS) break;
            }
            foreach (string uri in body_hits) hits += uri;
            return hits;
        }

        public override async SearchResultMeta[] get_result_metas(string[] ids, Cancellable? cancellable) throws Error {
            SearchResultMeta[] metas = {};
            string[] needles = last_needles;
            foreach (string id in ids) {
                var file = File.new_for_uri(id);
                if (!file.query_exists()) continue;
                var meta = new SearchResultMeta(id, display_name(file));
                string? snippet = first_line(read_text(file), needles);
                if (snippet == meta.name) snippet = null;
                if (is_note(file)) {
                    meta.description = snippet != null ? _("Quick Note, %s").printf(snippet) : _("Quick Note");
                } else {
                    meta.description = snippet != null && snippet != "" ? snippet : friendly_folder(file);
                }
                meta.icon = file_icon(file);
                metas += meta;
            }
            return metas;
        }

        public override async SearchActivationReply? activate_result(string id, string[] terms, uint32 timestamp) throws Error {
            app.open_document(File.new_for_uri(id));
            return null;
        }

        public override void launch_search(string[] terms, uint32 timestamp) {
            app.activate();
        }

        private static string[] normalize(string[] terms) {
            string[] result = {};
            foreach (string t in terms) {
                string s = t.strip().down();
                if (s != "") result += s;
            }
            return result;
        }

        private static bool all_in(string haystack, string[] needles) {
            foreach (string n in needles)
                if (!haystack.contains(n)) return false;
            return true;
        }

        private static string[] candidates() {
            string[] uris = {};
            var src = SettingsSchemaSource.get_default();
            if (src != null && src.lookup("dev.sinty.write", true) != null) {
                var settings = new GLib.Settings("dev.sinty.write");
                foreach (string uri in settings.get_strv("recent-files")) {
                    if (uri.down().has_suffix(".pdf") || uri in uris) continue;
                    var file = File.new_for_uri(uri);
                    if (file.get_path() != null && file.query_exists()) uris += uri;
                }
            }
            foreach (string uri in note_files())
                if (!(uri in uris)) uris += uri;
            return uris;
        }

        private static string[] note_files() {
            string[] uris = {};
            string dir = Path.build_filename(Environment.get_home_dir(), "Documents");
            try {
                var enumerator = File.new_for_path(dir).enumerate_children(
                    FileAttribute.STANDARD_NAME, FileQueryInfoFlags.NONE);
                FileInfo? info;
                while ((info = enumerator.next_file()) != null) {
                    string name = info.get_name();
                    if (name.has_prefix("singularity-note-") && name.has_suffix(".txt"))
                        uris += File.new_for_path(Path.build_filename(dir, name)).get_uri();
                }
            } catch (Error e) {
            }
            return uris;
        }

        private static GLib.Icon file_icon(File file) {
            try {
                var info = file.query_info(FileAttribute.STANDARD_CONTENT_TYPE, FileQueryInfoFlags.NONE);
                string? type = info.get_content_type();
                if (type != null) return ContentType.get_icon(type);
            } catch (Error e) {
            }
            return new ThemedIcon("text-x-generic");
        }

        private static bool is_note(File file) {
            string name = file.get_basename() ?? "";
            return name.has_prefix("singularity-note-") && name.has_suffix(".txt");
        }

        private static string display_name(File file) {
            if (is_note(file)) {
                string? line = first_line(read_text(file), {});
                return line != null && line != "" ? line : _("Quick Note");
            }
            return file.get_basename() ?? file.get_uri();
        }

        private static string read_text(File file) {
            string? path = file.get_path();
            if (path == null) return "";
            try {
                var info = file.query_info(FileAttribute.STANDARD_SIZE, FileQueryInfoFlags.NONE);
                if (info.get_size() > MAX_READ) return "";
                string contents;
                FileUtils.get_contents(path, out contents);
                return contents.make_valid();
            } catch (Error e) {
                return "";
            }
        }

        private static string? first_line(string text, string[] needles) {
            string? fallback = null;
            foreach (string raw in text.split("\n")) {
                string line = raw.strip();
                while (line.has_prefix("#")) line = line.substring(1).strip();
                if (line == "") continue;
                if (fallback == null) fallback = line;
                if (needles.length == 0 || all_in(line.down(), needles)) return clip(line);
            }
            return fallback != null ? clip(fallback) : null;
        }

        private static string clip(string line) {
            if (line.char_count() <= 80) return line;
            return line.substring(0, line.index_of_nth_char(79)) + "…";
        }

        private static string friendly_folder(File file) {
            var parent = file.get_parent();
            string path = parent != null ? (parent.get_path() ?? "") : "";
            string home = Environment.get_home_dir();
            if (path == home) return "~";
            if (path.has_prefix(home + "/")) return "~" + path.substring(home.length);
            return path;
        }
    }
}
