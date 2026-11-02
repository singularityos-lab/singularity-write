namespace Singularity.Apps {

    internal class WriteIntents : Object {
        private const string NONE = "{\"type\":\"object\",\"properties\":{}}";

        private static string text (Json.Object args, string key) {
            return args.has_member (key) ? args.get_string_member (key) : "";
        }

        private static Json.Node brief (WriteRichEditor r) {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("path").add_string_value (r.file != null ? r.file.get_path () ?? "" : "");
            b.set_member_name ("modified").add_boolean_value (r.modified);
            b.end_object ();
            return b.get_root ();
        }

        internal static void install (WriteApp app) {
            var agent = app.agent;
            agent.add_intent ("write_new", "Open a new blank document.", NONE,
                Singularity.AppIntentRisk.UNDOABLE, (args) => brief (app.agent_new ()));
            agent.add_intent ("write_open", "Open a document file.",
                "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"}},\"required\":[\"path\"]}",
                Singularity.AppIntentRisk.READ, (args) => {
                    app.open_document (File.new_for_path (text (args, "path")));
                    return null;
                });
            agent.add_intent ("write_type", "Write text at the cursor, on screen and undoable. A line break starts a new paragraph.",
                "{\"type\":\"object\",\"properties\":{\"text\":{\"type\":\"string\"}},\"required\":[\"text\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var r = app.agent_editor ();
                    string[] lines = text (args, "text").split ("\n");
                    for (int i = 0; i < lines.length; i++) {
                        if (i > 0) r.ed.split_paragraph ();
                        r.ed.insert_text (lines[i]);
                    }
                    r.modified = true;
                    r.view.queue_draw ();
                    return brief (r);
                });
            agent.add_intent ("write_read", "Read the text of the open document.", NONE,
                Singularity.AppIntentRisk.READ, (args) => {
                    var r = app.agent_editor ();
                    var node = brief (r);
                    var out_text = new StringBuilder ();
                    foreach (var p in Write.Story.all (r.doc)) out_text.append (p.plain_text ()).append_c ('\n');
                    node.get_object ().set_string_member ("text", out_text.str);
                    return node;
                });
            agent.add_intent ("write_save", "Save the open document, to its file or to a new path given with the format of its extension.",
                "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"}}}",
                Singularity.AppIntentRisk.IRREVERSIBLE, (args) => {
                    var r = app.agent_editor ();
                    if (text (args, "path") != "") {
                        r.file = File.new_for_path (text (args, "path"));
                        r.format = Write.FileFormat.from_extension (r.file.get_basename ());
                    }
                    if (r.file == null) throw new IOError.INVALID_ARGUMENT ("the document has no file yet");
                    WriteFiles.save (r, r.file, r.format);
                    r.modified = false;
                    return brief (r);
                });
        }
    }
}
