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

        private static Write.FindOptions find_options (Json.Object args) throws Error {
            var o = new Write.FindOptions ();
            o.query = text (args, "find");
            if (o.query == "") throw new IOError.INVALID_ARGUMENT ("find is empty");
            o.match_case = args.has_member ("match_case") && args.get_boolean_member ("match_case");
            o.whole_word = args.has_member ("whole_word") && args.get_boolean_member ("whole_word");
            o.regex = args.has_member ("regex") && args.get_boolean_member ("regex");
            return o;
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
            agent.add_intent ("write_find", "Find text in the open document. Answers with every match: paragraph index and the text around it.",
                "{\"type\":\"object\",\"properties\":{\"find\":{\"type\":\"string\"},\"match_case\":{\"type\":\"boolean\"},\"whole_word\":{\"type\":\"boolean\"},\"regex\":{\"type\":\"boolean\"}},\"required\":[\"find\"]}",
                Singularity.AppIntentRisk.READ, (args) => {
                    var r = app.agent_editor ();
                    var list = Write.Story.paragraphs (r.doc.body);
                    var arr = new Json.Array ();
                    var found = Write.Finder.find_all (r.doc, find_options (args));
                    foreach (var m in found) {
                        if (arr.get_length () == 200) break;
                        var o = new Json.Object ();
                        o.set_int_member ("index", list.index_of (m.para));
                        o.set_string_member ("match", m.text);
                        o.set_string_member ("paragraph", m.para.plain_text ());
                        arr.add_object_element (o);
                    }
                    var node = brief (r);
                    node.get_object ().set_int_member ("count", found.size);
                    node.get_object ().set_array_member ("matches", arr);
                    return node;
                });
            agent.add_intent ("write_replace", "Replace every occurrence of a text in the open document, as Replace All does. With regex, \\1 or $1 in replace inserts a group. Undoable, and recorded as revisions when Track Changes is on.",
                "{\"type\":\"object\",\"properties\":{\"find\":{\"type\":\"string\"},\"replace\":{\"type\":\"string\"},\"match_case\":{\"type\":\"boolean\"},\"whole_word\":{\"type\":\"boolean\"},\"regex\":{\"type\":\"boolean\"}},\"required\":[\"find\",\"replace\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var r = app.agent_editor ();
                    if (!r.editable ()) throw new IOError.PERMISSION_DENIED ("the document is read-only");
                    var o = find_options (args);
                    int n = Write.Finder.replace_all (r.ed, o, text (args, "replace"));
                    commit (r);
                    var node = brief (r);
                    node.get_object ().set_int_member ("replaced", n);
                    node.get_object ().set_boolean_member ("tracked", r.doc.track_changes);
                    bool left = r.doc.track_changes || text (args, "replace").contains (text (args, "find")) ? false : Write.Finder.find_all (r.doc, o).size > 0;
                    return verified (node, n > 0 && !left);
                });
            agent.add_intent ("write_insert_table", "Insert a table after a paragraph (or at the cursor), optionally filled: cells is a list of rows, each a list of cell texts. rows and cols default to the size of cells.",
                "{\"type\":\"object\",\"properties\":{" + TARGET + ",\"rows\":{\"type\":\"integer\"},\"cols\":{\"type\":\"integer\"},\"cells\":{\"type\":\"array\",\"items\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}}}}}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var r = app.agent_editor ();
                    if (!r.editable ()) throw new IOError.PERMISSION_DENIED ("the document is read-only");
                    var cells = args.has_member ("cells") ? args.get_array_member ("cells") : new Json.Array ();
                    int rows = (int) cells.get_length ();
                    int cols = 0;
                    foreach (var row in cells.get_elements ()) cols = int.max (cols, (int) row.get_array ().get_length ());
                    if (args.has_member ("rows")) rows = int.max (rows, (int) args.get_int_member ("rows"));
                    if (args.has_member ("cols")) cols = int.max (cols, (int) args.get_int_member ("cols"));
                    if (rows < 1 || cols < 1) throw new IOError.INVALID_ARGUMENT ("give cells, or rows and cols");
                    if (rows > 500 || cols > 60) throw new IOError.INVALID_ARGUMENT ("a table holds at most 500 rows and 60 columns");
                    if (args.has_member ("index") || text (args, "match") != "") {
                        int index;
                        var p = find_para (r, args, out index);
                        r.ed.select (new Write.Pos (p, p.length), new Write.Pos (p, p.length));
                    }
                    r.ed.checkpoint ("Insert Table");
                    r.ed.insert_table (rows, cols);
                    var t = r.ed.table_at (r.ed.focus);
                    if (t == null) throw new IOError.FAILED ("the table could not be placed here");
                    for (int i = 0; i < rows && i < cells.get_length (); i++) {
                        var row = cells.get_array_element (i);
                        for (int j = 0; j < cols && j < row.get_length (); j++) {
                            var cp = t.rows[i].cells[j].blocks[0] as Write.Paragraph;
                            if (cp != null) {
                                cp.insert_text (0, row.get_string_element (j), new Write.CharProps ());
                                cp.touch ();
                            }
                        }
                    }
                    commit (r);
                    var node = brief (r);
                    node.get_object ().set_int_member ("rows", t.rows.size);
                    node.get_object ().set_int_member ("cols", t.rows[0].cells.size);
                    return verified (node, t.parent != null && t.rows.size == rows);
                });
            agent.add_intent ("write_comment", "Add a review comment on a paragraph, anchored to the words given in quote (or to the whole paragraph).",
                "{\"type\":\"object\",\"properties\":{" + TARGET + ",\"quote\":{\"type\":\"string\"},\"text\":{\"type\":\"string\"}},\"required\":[\"text\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var r = app.agent_editor ();
                    if (!r.editable ()) throw new IOError.PERMISSION_DENIED ("the document is read-only");
                    int index;
                    var p = find_para (r, args, out index);
                    if (p.length == 0) throw new IOError.INVALID_ARGUMENT ("the paragraph is empty, give one with text");
                    int start = 0;
                    int end = p.length;
                    string quote = text (args, "quote");
                    if (quote != "") {
                        var o = new Write.FindOptions ();
                        o.query = quote;
                        Write.Match? hit = null;
                        foreach (var m in Write.Finder.find_all (r.doc, o)) {
                            if (m.para == p) {
                                hit = m;
                                break;
                            }
                        }
                        if (hit == null) throw new IOError.NOT_FOUND ("paragraph %d does not contain \"%s\"".printf (index, quote));
                        start = hit.start;
                        end = hit.end;
                    }
                    int before = r.doc.comments.size;
                    r.ed.select (new Write.Pos (p, start), new Write.Pos (p, end));
                    r.insert_comment (false);
                    if (r.doc.comments.size == before) throw new IOError.FAILED ("the comment was not added");
                    var c = r.doc.comments[r.doc.comments.size - 1];
                    var body = c.blocks[0] as Write.Paragraph;
                    if (body != null) {
                        body.insert_text (0, text (args, "text"), new Write.CharProps ());
                        body.touch ();
                    }
                    r.comments_pane.refresh ();
                    commit (r);
                    var node = brief (r);
                    node.get_object ().set_string_member ("id", c.id);
                    node.get_object ().set_string_member ("author", c.author);
                    node.get_object ().set_string_member ("text", c.text ());
                    node.get_object ().set_int_member ("comments", r.doc.comments.size);
                    return verified (node, c.text () == text (args, "text"));
                });
            agent.add_intent ("write_track_changes", "Turn Track Changes on or off, or accept or reject every recorded change. Answers with the state and how many changes are recorded.",
                "{\"type\":\"object\",\"properties\":{\"on\":{\"type\":\"boolean\"},\"resolve\":{\"type\":\"string\",\"enum\":[\"accept_all\",\"reject_all\"]}}}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var r = app.agent_editor ();
                    if (args.has_member ("on") && args.get_boolean_member ("on") != r.doc.track_changes) {
                        r.run ("track-changes", null);
                        if (args.get_boolean_member ("on") != r.doc.track_changes) throw new IOError.PERMISSION_DENIED ("the document is protected: changes are always tracked");
                    }
                    string resolve = text (args, "resolve");
                    if (resolve != "") {
                        if (resolve != "accept_all" && resolve != "reject_all") throw new IOError.INVALID_ARGUMENT ("resolve is accept_all or reject_all");
                        if (!r.editable ()) throw new IOError.PERMISSION_DENIED ("the document is read-only");
                        r.run (resolve.replace ("_", "-"), null);
                    }
                    var node = brief (r);
                    node.get_object ().set_boolean_member ("track_changes", r.doc.track_changes);
                    node.get_object ().set_int_member ("changes", Write.Review.collect (r.doc).size);
                    return node;
                });
            agent.add_intent ("write_export", "Export a copy of the open document to another file, the extension picks the format (pdf, docx, odt, rtf, html, md, txt, epub). The open document keeps its own file. A bare file name goes to Documents.",
                "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"}},\"required\":[\"path\"]}",
                Singularity.AppIntentRisk.IRREVERSIBLE, (args) => {
                    var r = app.agent_editor ();
                    string path = text (args, "path");
                    if (!Path.is_absolute (path)) path = Path.build_filename (Environment.get_user_special_dir (UserDirectory.DOCUMENTS) ?? Environment.get_home_dir (), path);
                    var f = File.new_for_path (path);
                    var fmt = Write.FileFormat.from_extension (f.get_basename ());
                    if (fmt != Write.FileFormat.PDF && !fmt.writable ()) throw new IOError.INVALID_ARGUMENT ("Write cannot export to %s, use pdf, docx, odt, rtf, html, md, txt or epub".printf (f.get_basename ()));
                    bool was = r.modified;
                    WriteFiles.save (r, f, fmt, false);
                    r.modified = was;
                    var node = brief (r);
                    node.get_object ().set_string_member ("exported", path);
                    node.get_object ().set_string_member ("format", fmt.label ());
                    return verified (node, f.query_exists ());
                });
            agent.set_context_provider (() => {
                WriteRichEditor r;
                try {
                    r = app.agent_editor ();
                } catch (Error e) {
                    return null;
                }
                var node = brief (r);
                var o = node.get_object ();
                o.set_string_member ("title", r.file != null ? r.file.get_basename () : "Untitled");
                var list = Write.Story.paragraphs (r.doc.body);
                int index = list.index_of (r.ed.focus.para);
                o.set_int_member ("paragraphs", list.size);
                o.set_member ("cursor", para_node (r.doc, r.ed.focus.para, index));
                if (r.ed.has_selection) {
                    string sel = r.ed.selected_text ();
                    o.set_string_member ("selection", sel.length > 2000 ? sel.substring (0, sel.index_of_nth_char (2000)) : sel);
                }
                o.set_boolean_member ("track_changes", r.doc.track_changes);
                o.set_int_member ("comments", r.doc.comments.size);
                o.set_boolean_member ("read_only", !r.editable ());
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
                    r.title_changed ();
                    r.update_status ();
                    return brief (r);
                });
        }
    }
}
