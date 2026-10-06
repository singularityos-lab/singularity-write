using GLib;

namespace Singularity.Apps {

    public class FormulaBridge : Object {
        public static bool available() {
            return Environment.find_program_in_path("singularity-formula") != null;
        }

        public static string new_target() {
            string dir = Path.build_filename(Environment.get_user_data_dir(), "singularity-write", "equations");
            DirUtils.create_with_parents(dir, 0700);
            string stamp = new DateTime.now_local().format("%Y%m%d-%H%M%S");
            string path = Path.build_filename(dir, "equation-%s.png".printf(stamp));
            int n = 2;
            while (FileUtils.test(path, FileTest.EXISTS))
                path = Path.build_filename(dir, "equation-%s-%d.png".printf(stamp, n++));
            return path;
        }

        public static string? latex_for(string image_path) {
            int dot = image_path.last_index_of(".");
            string tex = (dot > 0 ? image_path.substring(0, dot) : image_path) + ".tex";
            try {
                string text;
                FileUtils.get_contents(tex, out text);
                return text.strip();
            } catch (Error e) {
                return null;
            }
        }

        public static void discard(string image_path) {
            int dot = image_path.last_index_of(".");
            string stem = dot > 0 ? image_path.substring(0, dot) : image_path;
            FileUtils.remove(image_path);
            FileUtils.remove(stem + ".tex");
            FileUtils.remove(stem + ".mml");
        }

        private static int64 mtime(string path) {
            try {
                var info = File.new_for_path(path).query_info(FileAttribute.TIME_MODIFIED + "," + FileAttribute.TIME_MODIFIED_USEC, FileQueryInfoFlags.NONE);
                var dt = info.get_modification_date_time();
                return dt != null ? dt.to_unix() * 1000000 + dt.get_microsecond() : 0;
            } catch (Error e) {
                return 0;
            }
        }

        public static async bool edit(string target, string? latex) {
            int64 before = FileUtils.test(target, FileTest.EXISTS) ? mtime(target) : -1;
            string[] argv = { "singularity-formula", "--insert", target };
            if (latex != null && latex != "") {
                argv += "--latex";
                argv += latex;
            }
            try {
                var proc = new Subprocess.newv(argv, SubprocessFlags.NONE);
                yield proc.wait_async();
            } catch (Error e) {
                warning("formula: %s", e.message);
                return false;
            }
            if (!FileUtils.test(target, FileTest.EXISTS)) return false;
            return before < 0 || mtime(target) != before;
        }
    }
}
