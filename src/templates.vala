using GLib;

namespace Singularity.Apps {

    public enum WriteTemplateKind {
        BUILTIN,
        USER,
        FOLDER
    }

    public class WriteTemplate : Object {
        public string id { get; construct; }
        public string name { get; set; }
        public string description { get; set; }
        public string icon_name { get; set; }
        public WriteTemplateKind kind { get; construct; }
        public GLib.File? file { get; set; default = null; }

        public WriteTemplate(string id, string name, string description, string icon_name,
                             WriteTemplateKind kind, GLib.File? file = null) {
            Object(id: id, kind: kind);
            this.name = name;
            this.description = description;
            this.icon_name = icon_name;
            this.file = file;
        }

        public bool removable {
            get { return kind != WriteTemplateKind.BUILTIN; }
        }

        public string load_body() {
            if (kind == WriteTemplateKind.BUILTIN) {
                try {
                    var bytes = GLib.resources_lookup_data(WriteTemplates.RESOURCE_PREFIX + id + ".md",
                                                           ResourceLookupFlags.NONE);
                    if (bytes.get_size() == 0) return "";
                    return (string) bytes.get_data();
                } catch (Error e) {
                    return "";
                }
            }
            if (file == null) return "";
            try {
                uint8[] data;
                file.load_contents(null, out data, null);
                string text = (string) data;
                return text.validate() ? text : "";
            } catch (Error e) {
                return "";
            }
        }
    }

    public class WriteTemplates : Object {
        public const string RESOURCE_PREFIX = "/dev/sinty/write/templates/";
        public const string BLANK = "blank";

        private static WriteTemplates? _instance = null;

        public signal void changed();

        public static WriteTemplates get_default() {
            if (_instance == null) _instance = new WriteTemplates();
            return _instance;
        }

        public static Gee.ArrayList<WriteTemplate> builtin() {
            var l = new Gee.ArrayList<WriteTemplate>();
            l.add(new WriteTemplate(BLANK, _("Blank"), _("An empty document"), "text-x-generic", WriteTemplateKind.BUILTIN));
            l.add(new WriteTemplate("meeting-notes", _("Meeting Notes"), _("Agenda, attendees and action items"), "x-office-document", WriteTemplateKind.BUILTIN));
            l.add(new WriteTemplate("project-brief", _("Project Brief"), _("Goals, scope, milestones and risks"), "x-office-document", WriteTemplateKind.BUILTIN));
            l.add(new WriteTemplate("readme", _("README"), _("Introduce a project, install and use it"), "text-x-generic", WriteTemplateKind.BUILTIN));
            l.add(new WriteTemplate("blog-post", _("Blog Post"), _("A post with front matter for your blog"), "text-x-generic", WriteTemplateKind.BUILTIN));
            l.add(new WriteTemplate("letter", _("Letter"), _("A formal letter with a subject"), "x-office-document", WriteTemplateKind.BUILTIN));
            l.add(new WriteTemplate("report", _("Report"), _("Contents, findings in a table and footnotes"), "x-office-document", WriteTemplateKind.BUILTIN));
            l.add(new WriteTemplate("resume", _("Resume"), _("Profile, experience, education and skills"), "x-office-document", WriteTemplateKind.BUILTIN));
            l.add(new WriteTemplate("journal-entry", _("Journal Entry"), _("Today's date, good things and reflections"), "text-x-generic", WriteTemplateKind.BUILTIN));
            l.add(new WriteTemplate("weekly-planner", _("Weekly Planner"), _("Priorities and a task list for every day"), "x-office-document", WriteTemplateKind.BUILTIN));
            l.add(new WriteTemplate("recipe", _("Recipe"), _("Servings, ingredients and method"), "text-x-generic", WriteTemplateKind.BUILTIN));
            l.add(new WriteTemplate("lecture-notes", _("Lecture Notes"), _("Key questions, notes and a summary"), "x-office-document", WriteTemplateKind.BUILTIN));
            return l;
        }

        public static string user_dir() {
            return GLib.Path.build_filename(GLib.Environment.get_user_data_dir(), "singularity-write", "templates");
        }

        public static string? folder_dir() {
            string? dir = GLib.Environment.get_user_special_dir(GLib.UserDirectory.TEMPLATES);
            if (dir == null) return null;
            string home = GLib.Environment.get_home_dir();
            if (dir == home || dir.has_suffix("/") && dir.substring(0, dir.length - 1) == home) return null;
            return dir;
        }

        public static bool is_markdown_name(string name) {
            string n = name.down();
            return n.has_suffix(".md") || n.has_suffix(".markdown");
        }

        public static string display_name(string basename) {
            string n = basename;
            if (n.down().has_suffix(".markdown")) n = n.substring(0, n.length - 9);
            else if (n.down().has_suffix(".md")) n = n.substring(0, n.length - 3);
            return n;
        }

        public static Gee.ArrayList<WriteTemplate> discover(string? user_path, string? folder_path) {
            var l = new Gee.ArrayList<WriteTemplate>();
            if (user_path != null) scan(l, user_path, WriteTemplateKind.USER);
            if (folder_path != null && folder_path != user_path) scan(l, folder_path, WriteTemplateKind.FOLDER);
            l.sort((a, b) => {
                if (a.kind != b.kind) return (int) a.kind - (int) b.kind;
                return a.name.casefold().collate(b.name.casefold());
            });
            return l;
        }

        private static void scan(Gee.ArrayList<WriteTemplate> l, string path, WriteTemplateKind kind) {
            var dir = GLib.File.new_for_path(path);
            try {
                var en = dir.enumerate_children("standard::name,standard::type,standard::is-hidden",
                                                FileQueryInfoFlags.NONE, null);
                FileInfo? info;
                while ((info = en.next_file(null)) != null) {
                    if (info.get_file_type() != FileType.REGULAR || info.get_is_hidden()) continue;
                    string name = info.get_name();
                    if (!is_markdown_name(name)) continue;
                    var f = dir.get_child(name);
                    string desc = kind == WriteTemplateKind.USER ? _("Your saved template") : _("From your Templates folder");
                    l.add(new WriteTemplate((kind == WriteTemplateKind.USER ? "user:" : "folder:") + f.get_path(),
                                            display_name(name), desc, "text-x-generic-template", kind, f));
                }
            } catch (Error e) {
            }
        }

        public Gee.ArrayList<WriteTemplate> user_templates() {
            return discover(user_dir(), folder_dir());
        }

        public Gee.ArrayList<WriteTemplate> all() {
            var l = builtin();
            l.add_all(user_templates());
            return l;
        }

        public WriteTemplate? find(string id) {
            foreach (var t in all()) if (t.id == id) return t;
            return null;
        }

        public static string expand(string text, string title, string user, GLib.DateTime now) {
            if (!("{{" in text)) return text;
            var sb = new StringBuilder();
            int i = 0;
            while (i < text.length) {
                int open = text.index_of("{{", i);
                if (open < 0) { sb.append(text.substring(i)); break; }
                int close = text.index_of("}}", open + 2);
                if (close < 0) { sb.append(text.substring(i)); break; }
                sb.append(text.substring(i, open - i));
                string key = text.substring(open + 2, close - open - 2).strip().down();
                string? value = placeholder(key, title, user, now);
                sb.append(value ?? text.substring(open, close + 2 - open));
                i = close + 2;
            }
            return sb.str;
        }

        private static string? placeholder(string key, string title, string user, GLib.DateTime now) {
            switch (key) {
                case "date": return now.format("%-d %B %Y");
                case "time": return now.format("%H:%M");
                case "weekday": return now.format("%A");
                case "isodate": return now.format("%Y-%m-%d");
                case "year": return now.format("%Y");
                case "user": return user;
                case "title": return title;
                default: return null;
            }
        }

        public static string current_user() {
            string real = GLib.Environment.get_real_name();
            if (real != null && real != "" && real != "Unknown") return real;
            return GLib.Environment.get_user_name();
        }

        public string instantiate(WriteTemplate t, GLib.DateTime? at = null) {
            string title = t.id == BLANK ? _("Untitled") : t.name;
            return expand(t.load_body(), title, current_user(), at ?? new GLib.DateTime.now_local());
        }

        public string preview_text(WriteTemplate t) {
            var now = new GLib.DateTime.now_local();
            return instantiate(t, new GLib.DateTime.local(now.get_year(), now.get_month(), now.get_day_of_month(), 9, 0, 0));
        }

        public static string safe_name(string name) {
            string n = name.strip().replace("/", "-").replace("\\", "-");
            while (n.has_prefix(".")) n = n.substring(1);
            return n.strip();
        }

        public GLib.File file_for_name(string name) {
            return GLib.File.new_for_path(GLib.Path.build_filename(user_dir(), safe_name(name) + ".md"));
        }

        public GLib.File save(string name, string body) throws Error {
            string n = safe_name(name);
            if (n == "") throw new IOError.INVALID_ARGUMENT(_("The template needs a name"));
            GLib.DirUtils.create_with_parents(user_dir(), 0755);
            var f = file_for_name(n);
            GLib.FileUtils.set_contents(f.get_path(), body);
            changed();
            return f;
        }

        public void rename(WriteTemplate t, string new_name) throws Error {
            if (t.file == null || t.kind == WriteTemplateKind.BUILTIN) return;
            string n = safe_name(new_name);
            if (n == "") throw new IOError.INVALID_ARGUMENT(_("The template needs a name"));
            string ext = t.file.get_basename().down().has_suffix(".markdown") ? ".markdown" : ".md";
            var target = t.file.get_parent().get_child(n + ext);
            if (target.equal(t.file)) return;
            if (target.query_exists()) throw new IOError.EXISTS(_("A template with this name already exists"));
            t.file.move(target, FileCopyFlags.NONE);
            changed();
        }

        public void remove(WriteTemplate t) throws Error {
            if (t.file == null || t.kind == WriteTemplateKind.BUILTIN) return;
            try {
                t.file.trash();
            } catch (IOError.NOT_SUPPORTED e) {
                t.file.delete();
            }
            changed();
        }
    }
}
