using Gtk;
using GLib;
using Singularity;

namespace SingularityWriteWidget {

    /**
     * Sticky-note widget. Each placed widget is one note of the shared
     * notes store (Singularity.Notes), so it also shows up in Notes. The
     * older plain text files in ~/Documents are imported once.
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
        private string note_id;
        private Singularity.Notes.NoteStore store;
        private Singularity.Notes.Note? current = null;
        private ulong changed_id = 0;
        private bool loading = false;
        private uint save_id = 0;

        public NotesInstance(string instance_id, WidgetSize size) {
            Object(orientation: Orientation.VERTICAL, spacing: 0);
            add_css_class("overview-notes");
            overflow = Overflow.HIDDEN;

            store = Singularity.Notes.NoteStore.get_default();
            note_id = Singularity.Notes.NoteStore.WIDGET_PREFIX + instance_id;
            if (!Singularity.Notes.NoteStore.valid_id(note_id)) {
                note_id = Singularity.Notes.NoteStore.WIDGET_PREFIX + GLib.Checksum.compute_for_string(ChecksumType.SHA1, instance_id).substring(0, 16);
            }

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
            changed_id = store.changed.connect(() => {
                if (save_id == 0) load();
            });
            destroy.connect(() => {
                if (changed_id != 0) store.disconnect(changed_id);
                changed_id = 0;
                if (save_id != 0) { GLib.Source.remove(save_id); save_id = 0; }
                save_now();
            });
        }

        private void schedule_save() {
            if (loading) return;
            if (save_id != 0) GLib.Source.remove(save_id);
            save_id = GLib.Timeout.add(800, () => {
                save_id = 0;
                save_now();
                return GLib.Source.REMOVE;
            });
        }

        private void load() {
            var note = store.lookup(note_id);
            current = note != null ? note.copy() : null;
            show_text(note != null ? note.body : "");
        }

        private void show_text(string body) {
            if (view.buffer.text == body) return;
            Gtk.TextIter it;
            view.buffer.get_iter_at_mark(out it, view.buffer.get_insert());
            int offset = it.get_offset();
            loading = true;
            view.buffer.text = body;
            loading = false;
            view.buffer.get_iter_at_offset(out it, int.min(offset, view.buffer.get_char_count()));
            view.buffer.place_cursor(it);
        }

        private void save_now() {
            string content = view.buffer.text;
            try {
                if (content.strip() == "") {
                    if (current != null && !store.remove_unchanged(current)) load();
                    current = null;
                    return;
                }
                var note = current ?? store.ensure(note_id).copy();
                if (note.body == content) return;
                note.body = content;
                store.save(note);
                current = note.copy();
                show_text(note.body);
            } catch (Error e) { warning("notes save: %s", e.message); }
        }
    }

    [CCode (cname = "singularity_write_notes_widget_new")]
    public static Object singularity_write_notes_widget_new() {
        return new NotesProvider();
    }
}
