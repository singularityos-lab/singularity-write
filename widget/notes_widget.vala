using Gtk;
using GLib;
using Singularity;

namespace SingularityWriteWidget {

    /**
     * Sticky-note widget. Backed by a single plain text file in ~/Documents
     * (created on first save). Autosaves on every change (debounced).
     *
     * Widget code lives in libsingularity-write-widget.so loaded by the
     * overview - no dependency on the write app running.
     */
    public class NotesProvider : Object, OverviewWidgetProvider {
        public string id           { get { return "write.notes"; } }
        public string provider_id  { get { return "dev.sinty.write"; } }
        public string display_name { get { return "Quick Notes"; } }
        public string icon_name    { get { return "accessories-text-editor-symbolic"; } }
        public WidgetSize[] supported_sizes {
            get {
                if (_sizes == null) {
                    _sizes = new WidgetSize[5];
                    _sizes[0] = WidgetSize(1, 1);
                    _sizes[1] = WidgetSize(1, 2);
                    _sizes[2] = WidgetSize(2, 2);
                    _sizes[3] = WidgetSize(4, 2);
                    _sizes[4] = WidgetSize(4, 4);
                }
                return _sizes;
            }
        }
        private WidgetSize[] _sizes;
        public Gtk.Widget create_instance(string instance_id, WidgetSize size, Variant? config) {
            return new NotesInstance(instance_id, size);
        }
    }

    public class NotesInstance : Gtk.Box {
        private Gtk.TextView view;
        private Gtk.Label header;
        private string note_path;
        private uint save_id = 0;

        public NotesInstance(string instance_id, WidgetSize size) {
            Object(orientation: Orientation.VERTICAL, spacing: 0);
            add_css_class("overview-notes");
            overflow = Overflow.HIDDEN;

            note_path = Path.build_filename(Environment.get_home_dir(),
                "Documents", "singularity-note-" + instance_id + ".txt");

            header = new Gtk.Label("Quick Notes");
            header.add_css_class("title-4");
            header.halign = Align.START;
            header.margin_start = 12; header.margin_top = 8;
            append(header);

            var scrolled = new Gtk.ScrolledWindow();
            scrolled.hexpand = true; scrolled.vexpand = true;
            scrolled.hscrollbar_policy = PolicyType.NEVER;
            scrolled.vscrollbar_policy = PolicyType.AUTOMATIC;
            view = new Gtk.TextView();
            view.wrap_mode = WrapMode.WORD_CHAR;
            view.left_margin = 12; view.right_margin = 12;
            view.top_margin = 6;   view.bottom_margin = 12;
            view.add_css_class("overview-notes-view");
            scrolled.set_child(view);
            append(scrolled);

            load();
            view.buffer.changed.connect(schedule_save);
            destroy.connect(() => {
                if (save_id != 0) { GLib.Source.remove(save_id); save_id = 0; }
                save_now();
            });
        }

        private void schedule_save() {
            if (save_id != 0) GLib.Source.remove(save_id);
            save_id = GLib.Timeout.add(800, () => {
                save_id = 0;
                save_now();
                return GLib.Source.REMOVE;
            });
        }

        private void load() {
            try {
                if (FileUtils.test(note_path, FileTest.EXISTS)) {
                    string contents;
                    if (FileUtils.get_contents(note_path, out contents))
                        view.buffer.text = contents;
                }
            } catch (Error e) { warning("notes load: %s", e.message); }
        }

        private void save_now() {
            try {
                var parent = File.new_for_path(note_path).get_parent();
                if (parent != null && !parent.query_exists())
                    parent.make_directory_with_parents();
                FileUtils.set_contents(note_path, view.buffer.text);
            } catch (Error e) { warning("notes save: %s", e.message); }
        }
    }

    [CCode (cname = "singularity_write_notes_widget_new")]
    public static Object singularity_write_notes_widget_new() {
        return new NotesProvider();
    }
}
