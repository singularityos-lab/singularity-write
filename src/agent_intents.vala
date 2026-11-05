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

        private static Json.Node para_node (Write.Document doc, Write.Paragraph p, int index) {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("index").add_int_value (index);
            b.set_member_name ("style").add_string_value (p.style);
            var st = doc.styles.get (p.style);
            b.set_member_name ("style_name").add_string_value (st != null ? st.name : p.style);
            b.set_member_name ("level").add_int_value (doc.styles.outline_level (p) + 1);
            b.set_member_name ("text").add_string_value (p.plain_text ());
            b.end_object ();
            return b.get_root ();
        }

        private static Write.Paragraph find_para (WriteRichEditor r, Json.Object args, out int index) throws Error {
            var list = Write.Story.paragraphs (r.doc.body);
            if (args.has_member ("index")) {
                index = (int) args.get_int_member ("index");
                if (index < 0 || index >= list.size) throw new IOError.INVALID_ARGUMENT ("no paragraph %d, the document has %d".printf (index, list.size));
                return list[index];
            }
            string match = text (args, "match");
            if (match != "") {
                for (int i = 0; i < list.size; i++) {
                    if (list[i].plain_text ().down ().contains (match.down ())) {
                        index = i;
                        return list[i];
                    }
                }
                throw new IOError.NOT_FOUND ("no paragraph contains \"%s\"".printf (match));
            }
            index = list.index_of (r.ed.focus.para);
            return r.ed.focus.para;
        }

        private static string resolve_style (Write.Document doc, string name) throws Error {
            foreach (var st in doc.styles.list) if (st.id == name || st.name == name || st.name.down () == name.down ()) return st.id;
            string[] known = {};
            foreach (var st in doc.styles.list) known += st.name;
            throw new IOError.INVALID_ARGUMENT ("no style \"%s\"; styles: %s".printf (name, string.joinv (", ", known)));
        }

        private static void commit (WriteRichEditor r) {
            r.touch_all ();
            r.ed.changed ();
            r.modified = true;
            r.view.queue_draw ();
        }

        private static Json.Node verified (Json.Node n, bool ok) {
            n.get_object ().set_boolean_member ("verified", ok);
            return n;
        }

        private const string TARGET = "\"index\":{\"type\":\"integer\",\"description\":\"paragraph index from write_outline\"},\"match\":{\"type\":\"string\",\"description\":\"first paragraph containing this text\"}";

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
            agent.add_intent ("write_outline", "List every paragraph of the open document with its index, style, heading level and text. Use the index with the other write_ intents.", NONE,
                Singularity.AppIntentRisk.READ, (args) => {
                    var r = app.agent_editor ();
                    var node = brief (r);
                    var arr = new Json.Array ();
                    var list = Write.Story.paragraphs (r.doc.body);
                    for (int i = 0; i < list.size; i++) arr.add_element (para_node (r.doc, list[i], i));
                    node.get_object ().set_array_member ("paragraphs", arr);
                    var styles = new Json.Array ();
                    foreach (var st in r.doc.styles.list) styles.add_string_element (st.name);
                    node.get_object ().set_array_member ("styles", styles);
                    return node;
                });
            agent.add_intent ("write_set_style", "Give a paragraph a style such as Title, Subtitle, Heading 1 to Heading 6, Quote or Normal. Answers with the style read back from the document; verified is false if it did not take.",
                "{\"type\":\"object\",\"properties\":{" + TARGET + ",\"style\":{\"type\":\"string\"}},\"required\":[\"style\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var r = app.agent_editor ();
                    if (!r.editable ()) throw new IOError.PERMISSION_DENIED ("the document is read-only");
                    int index;
                    var p = find_para (r, args, out index);
                    string id = resolve_style (r.doc, text (args, "style"));
                    r.ed.checkpoint ("Style");
                    p.style = id;
                    p.touch ();
                    commit (r);
                    var back = Write.Story.paragraphs (r.doc.body);
                    bool ok = index >= 0 && index < back.size && back[index].style == id;
                    return verified (para_node (r.doc, p, index), ok);
                });
            agent.add_intent ("write_format", "Format the whole text of a paragraph: bold, italic, underline, strike (on true or false), color or highlight (value #rrggbb), size (value in points), font (value family name).",
                "{\"type\":\"object\",\"properties\":{" + TARGET + ",\"what\":{\"type\":\"string\",\"enum\":[\"bold\",\"italic\",\"underline\",\"strike\",\"color\",\"highlight\",\"size\",\"font\"]},\"on\":{\"type\":\"boolean\"},\"value\":{\"type\":\"string\"}},\"required\":[\"what\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var r = app.agent_editor ();
                    if (!r.editable ()) throw new IOError.PERMISSION_DENIED ("the document is read-only");
                    int index;
                    var p = find_para (r, args, out index);
                    string what = text (args, "what");
                    bool on = !args.has_member ("on") || args.get_boolean_member ("on");
                    string value = text (args, "value");
                    r.ed.checkpoint ("Format");
                    foreach (var it in p.inlines) {
                        switch (what) {
                            case "bold": it.props.bold = Write.Tri.of (on); break;
                            case "italic": it.props.italic = Write.Tri.of (on); break;
                            case "underline": it.props.underline = on ? Write.Underline.SINGLE : Write.Underline.NONE; break;
                            case "strike": it.props.strike = Write.Tri.of (on); break;
                            case "color": it.props.color = value; break;
                            case "highlight": it.props.highlight = value; break;
                            case "size": it.props.size = double.parse (value); break;
                            case "font": it.props.font = value; break;
                            default: throw new IOError.INVALID_ARGUMENT ("unknown format \"%s\"".printf (what));
                        }
                    }
                    p.touch ();
                    commit (r);
                    return verified (para_node (r.doc, p, index), p.inlines.size > 0);
                });
            agent.add_intent ("write_set_text", "Replace the text of a paragraph, keeping its style.",
                "{\"type\":\"object\",\"properties\":{" + TARGET + ",\"text\":{\"type\":\"string\"}},\"required\":[\"text\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var r = app.agent_editor ();
                    if (!r.editable ()) throw new IOError.PERMISSION_DENIED ("the document is read-only");
                    int index;
                    var p = find_para (r, args, out index);
                    string t = text (args, "text");
                    r.ed.checkpoint ("Replace Text");
                    var props = p.inlines.size > 0 ? p.props_at (1) : new Write.CharProps ();
                    var keep = new Gee.ArrayList<Write.Inline> ();
                    foreach (var i in p.inlines) if (i is Write.Mark) keep.add (i);
                    p.inlines.clear ();
                    p.inlines.add_all (keep);
                    p.insert_text (p.length, t, props);
                    p.touch ();
                    commit (r);
                    return verified (para_node (r.doc, p, index), p.plain_text () == t);
                });
            agent.add_intent ("write_insert_paragraph", "Insert a new paragraph after the given one (or at the end when no target is given), with an optional style.",
                "{\"type\":\"object\",\"properties\":{" + TARGET + ",\"text\":{\"type\":\"string\"},\"style\":{\"type\":\"string\"}},\"required\":[\"text\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var r = app.agent_editor ();
                    if (!r.editable ()) throw new IOError.PERMISSION_DENIED ("the document is read-only");
                    string id = text (args, "style") != "" ? resolve_style (r.doc, text (args, "style")) : "Normal";
                    r.ed.checkpoint ("Insert Paragraph");
                    var np = new Write.Paragraph (id);
                    np.insert_text (0, text (args, "text"), new Write.CharProps ());
                    if (args.has_member ("index") || text (args, "match") != "") {
                        int index;
                        var ref_p = find_para (r, args, out index);
                        if (ref_p.parent == null) throw new IOError.FAILED ("the paragraph is not in the document");
                        ref_p.parent.insert (ref_p.parent.items.index_of (ref_p) + 1, np);
                    } else {
                        var last = r.doc.body.size > 0 ? r.doc.body[r.doc.body.size - 1] as Write.Paragraph : null;
                        if (last != null && last.is_empty () && r.doc.body.size > 1) r.doc.body.insert (r.doc.body.size - 1, np);
                        else r.doc.body.add (np);
                    }
                    commit (r);
                    int at = Write.Story.paragraphs (r.doc.body).index_of (np);
                    return verified (para_node (r.doc, np, at), at >= 0);
                });
            agent.add_intent ("write_delete_paragraph", "Delete a paragraph. Undoable with Ctrl+Z.",
                "{\"type\":\"object\",\"properties\":{" + TARGET + "}}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var r = app.agent_editor ();
                    if (!r.editable ()) throw new IOError.PERMISSION_DENIED ("the document is read-only");
                    int index;
                    var p = find_para (r, args, out index);
                    if (p.parent == null) throw new IOError.FAILED ("the paragraph is not in the document");
                    var removed = para_node (r.doc, p, index);
                    r.ed.checkpoint ("Delete Paragraph");
                    var list = p.parent;
                    list.items.remove (p);
                    if (list.size == 0) list.add (new Write.Paragraph ());
                    commit (r);
                    return verified (removed, !Write.Story.paragraphs (r.doc.body).contains (p));
                });
            agent.add_intent ("write_insert_image", "Insert a picture file after a paragraph (or at the cursor). Takes a path on disk, never the clipboard.",
                "{\"type\":\"object\",\"properties\":{" + TARGET + ",\"path\":{\"type\":\"string\"}},\"required\":[\"path\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var r = app.agent_editor ();
                    if (!r.editable ()) throw new IOError.PERMISSION_DENIED ("the document is read-only");
                    var f = File.new_for_path (text (args, "path"));
                    if (!f.query_exists ()) throw new IOError.NOT_FOUND ("no file %s".printf (f.get_path ()));
                    if (args.has_member ("index") || text (args, "match") != "") {
                        int index;
                        var p = find_para (r, args, out index);
                        r.ed.select (new Write.Pos (p, p.length), new Write.Pos (p, p.length));
                        r.ed.split_paragraph ();
                    }
                    int before = 0;
                    foreach (var p in Write.Story.paragraphs (r.doc.body)) foreach (var i in p.inlines) if (i is Write.ImageRun) before++;
                    r.insert_picture_file (f);
                    commit (r);
                    int after = 0;
                    foreach (var p in Write.Story.paragraphs (r.doc.body)) foreach (var i in p.inlines) if (i is Write.ImageRun) after++;
                    var n = brief (r);
                    n.get_object ().set_int_member ("pictures", after);
                    return verified (n, after > before);
                });
            var action_names = new Json.Array ();
            foreach (string n in WriteActions.names ()) action_names.add_string_element (n);
            var enum_node = new Json.Node (Json.NodeType.ARRAY);
            enum_node.set_array (action_names);
            agent.add_intent ("write_action", "Run any command of the Write ribbon on the selection or cursor, exactly as the button does. value is the parameter some commands take (style name, font, size, color, alignment).",
                "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\",\"enum\":" + Json.to_string (enum_node, false) + "},\"value\":{\"type\":\"string\"}},\"required\":[\"name\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var r = app.agent_editor ();
                    string n = text (args, "name");
                    if (!(n in WriteActions.names ())) throw new IOError.INVALID_ARGUMENT ("unknown command %s".printf (n));
                    Variant? v = null;
                    if (args.has_member ("value")) v = WriteActions.is_double (n) ? new Variant.double (double.parse (text (args, "value"))) : new Variant.string (text (args, "value"));
                    r.run (n, v);
                    var node = brief (r);
                    int index = Write.Story.paragraphs (r.doc.body).index_of (r.ed.focus.para);
                    node.get_object ().set_member ("current", para_node (r.doc, r.ed.focus.para, index));
                    return node;
                });
            agent.add_intent ("write_script", "Run a Write document script for edits the other intents do not cover: loops over paragraphs, headings and tables, set_style, set_text, format, append, insert_after, delete, set_cell, add_row. Answers with what the script printed and the outline after it ran.",
                "{\"type\":\"object\",\"properties\":{\"source\":{\"type\":\"string\"}},\"required\":[\"source\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var r = app.agent_editor ();
                    if (!r.editable ()) throw new IOError.PERMISSION_DENIED ("the document is read-only");
                    string result = r.run_script (text (args, "source"));
                    r.modified = true;
                    var node = brief (r);
                    node.get_object ().set_string_member ("result", result);
                    var arr = new Json.Array ();
                    var list = Write.Story.paragraphs (r.doc.body);
                    for (int i = 0; i < list.size && i < 400; i++) arr.add_element (para_node (r.doc, list[i], i));
                    node.get_object ().set_array_member ("paragraphs", arr);
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
