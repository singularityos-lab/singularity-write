using Gtk;
using Write;

namespace Singularity.Apps {

    public class WriteFiles : Object {

        public static string versions_dir(GLib.File f) {
            string key = Checksum.compute_for_string(ChecksumType.SHA1, f.get_uri());
            return Path.build_filename(Environment.get_user_data_dir(), "singularity-write", "versions", key);
        }

        public static string recovery_dir() {
            return Path.build_filename(Environment.get_user_state_dir(), "singularity-write", "recovery");
        }

        public static Write.Document load(GLib.File f, out Write.FileFormat fmt) throws Error {
            uint8[] data;
            string path = f.get_path();
            if (path == null) throw new IOError.NOT_SUPPORTED(_("Only local files can be opened."));
            FileUtils.get_data(path, out data);
            fmt = Formats.sniff(data, f.get_basename());
            if (fmt == FileFormat.OTHER_OFFICE) throw new FormatError.UNSUPPORTED(_("This is a spreadsheet or presentation, not a text document. Open it with Spreadsheet or Slides."));
            if (fmt == FileFormat.PDF) throw new FormatError.UNSUPPORTED(_("PDF files open in the document viewer."));
            if (fmt == FileFormat.UNKNOWN) throw new FormatError.UNSUPPORTED(_("Write does not recognise the format of this file."));
            var d = Formats.load(data, fmt);
            if (d.meta.title == "" && (fmt == FileFormat.TEXT || fmt == FileFormat.HTML)) d.meta.title = "";
            return d;
        }

        public static void save(WriteRichEditor r, GLib.File f, Write.FileFormat fmt, bool keep = true) throws Error {
            var doc = r.doc;
            var now = new DateTime.now_utc().format("%Y-%m-%dT%H:%M:%SZ");
            if (doc.meta.created == "") doc.meta.created = now;
            doc.meta.modified = now;
            doc.meta.last_modified_by = r.ed.author;
            if (doc.meta.author == "") doc.meta.author = r.ed.author;
            doc.meta.revision++;
            uint8[] bytes;
            if (fmt == FileFormat.PDF) {
                var ex = new PdfExport(doc);
                ex.filename = f.get_basename();
                ex.write_file(f.get_path());
                return;
            }
            bytes = Formats.save(doc, fmt);
            if (keep && FileUtils.test(f.get_path(), FileTest.EXISTS) && fmt.rich()) keep_version(f);
            write_atomically(f.get_path(), bytes);
        }

        public static void keep_version(GLib.File f) {
            try {
                string dir = versions_dir(f);
                DirUtils.create_with_parents(dir, 0700);
                string ext = f.get_basename().substring(f.get_basename().last_index_of_char('.') + 1);
                string stamp = new DateTime.now_local().format("%Y%m%d-%H%M%S");
                var dest = GLib.File.new_for_path(Path.build_filename(dir, "%s.%s".printf(stamp, ext)));
                f.copy(dest, FileCopyFlags.OVERWRITE, null, null);
                FileUtils.set_contents(Path.build_filename(dir, "source.txt"), f.get_uri());
                var names = new Gee.ArrayList<string>();
                var d = Dir.open(dir);
                string? n;
                while ((n = d.read_name()) != null) if (n != "source.txt") names.add(n);
                names.sort();
                while (names.size > 60) {
                    FileUtils.remove(Path.build_filename(dir, names[0]));
                    names.remove_at(0);
                }
            } catch (Error e) {
            }
        }

        public static Gee.ArrayList<string> list_versions(GLib.File f) {
            var list = new Gee.ArrayList<string>();
            string dir = versions_dir(f);
            try {
                var d = Dir.open(dir);
                string? n;
                while ((n = d.read_name()) != null) if (n != "source.txt") list.add(Path.build_filename(dir, n));
            } catch (Error e) {
            }
            list.sort((a, b) => strcmp(b, a));
            return list;
        }

        public static void write_recovery(WriteRichEditor r) {
            if (!r.modified) return;
            try {
                string dir = recovery_dir();
                DirUtils.create_with_parents(dir, 0700);
                var bytes = DocxWriter.save(r.doc);
                write_atomically(Path.build_filename(dir, r.recovery_id + ".docx"), bytes);
                string origin = r.file != null ? r.file.get_uri() : "";
                FileUtils.set_contents(Path.build_filename(dir, r.recovery_id + ".txt"), origin + "\n" + r.format.extension() + "\n" + new DateTime.now_local().format("%Y-%m-%d %H:%M"));
            } catch (Error e) {
            }
        }

        public static void clear_recovery(WriteRichEditor r) {
            string dir = recovery_dir();
            FileUtils.remove(Path.build_filename(dir, r.recovery_id + ".docx"));
            FileUtils.remove(Path.build_filename(dir, r.recovery_id + ".txt"));
        }

        public class Recovered : Object {
            public string path;
            public string origin;
            public string ext;
            public string when;
        }

        public static Gee.ArrayList<Recovered> recovered(string? skip_id) {
            var list = new Gee.ArrayList<Recovered>();
            try {
                var d = Dir.open(recovery_dir());
                string? n;
                while ((n = d.read_name()) != null) {
                    if (!n.has_suffix(".docx")) continue;
                    string id = n.substring(0, n.length - 5);
                    if (skip_id != null && id == skip_id) continue;
                    var r = new Recovered();
                    r.path = Path.build_filename(recovery_dir(), n);
                    string meta = "";
                    FileUtils.get_contents(Path.build_filename(recovery_dir(), id + ".txt"), out meta);
                    string[] parts = meta.split("\n");
                    r.origin = parts.length > 0 ? parts[0] : "";
                    r.ext = parts.length > 1 ? parts[1] : "docx";
                    r.when = parts.length > 2 ? parts[2] : "";
                    list.add(r);
                }
            } catch (Error e) {
            }
            return list;
        }

        public static void discard_recovered(Recovered r) {
            FileUtils.remove(r.path);
            FileUtils.remove(r.path.substring(0, r.path.length - 5) + ".txt");
        }

        public static async void finish_merge(WriteRichEditor r, string mode) {
            if (r.merge_ds == null || r.merge_ds.records.size == 0) {
                r.toast(_("Select recipients first."));
                return;
            }
            if (mode == "pdf") {
                var fd = new Gtk.FileDialog();
                fd.title = _("Choose a Folder for the PDF Files");
                try {
                    var folder = yield fd.select_folder(r.window, null);
                    if (folder == null) return;
                    int n = 0;
                    for (int i = 0; i < r.merge_ds.records.size; i++) {
                        var one = MailMerge.instantiate(r.doc, r.merge_ds.records[i]);
                        string name = r.merge_ds.columns.length > 0 ? r.merge_ds.records[i][r.merge_ds.columns[0]] : "";
                        name = name.replace("/", "-").strip();
                        if (name == "") name = "record";
                        var ex = new PdfExport(one);
                        ex.write_file(Path.build_filename(folder.get_path(), "%03d %s.pdf".printf(i + 1, name)));
                        n++;
                    }
                    r.toast(ngettext("%d PDF file written", "%d PDF files written", n).printf(n));
                } catch (Error e) {
                    if (!(e is Gtk.DialogError.DISMISSED)) r.toast(e.message);
                }
                return;
            }
            var merged = MailMerge.merge_all(r.doc, r.merge_ds);
            if (mode == "print") {
                var src = new WritePageSource(merged, _("Merged Letters"));
                Singularity.Print.run_source.begin(r.window, src);
                return;
            }
            r.file = null;
            r.format = FileFormat.DOCX;
            r.set_document(merged);
            r.modified = true;
            r.title_changed();
        }

        public static string format_filter_name(FileFormat f) {
            return "%s (.%s)".printf(f.label(), f.extension());
        }

        public static Gtk.FileFilter filter_for(FileFormat f) {
            var ff = new Gtk.FileFilter();
            ff.name = format_filter_name(f);
            ff.add_suffix(f.extension());
            if (f == FileFormat.HTML) ff.add_suffix("htm");
            if (f == FileFormat.MARKDOWN) ff.add_suffix("markdown");
            if (f == FileFormat.DOC) ff.add_suffix("dot");
            if (f == FileFormat.DOCM) ff.add_suffix("dotm");
            return ff;
        }

        public static Gtk.FileFilter all_documents() {
            var ff = new Gtk.FileFilter();
            ff.name = _("All Documents");
            foreach (string s in new string[] { "docx", "dotx", "docm", "dotm", "odt", "ott", "rtf", "doc", "dot", "html", "htm", "md", "markdown", "txt", "epub" }) ff.add_suffix(s);
            return ff;
        }
    }
}
