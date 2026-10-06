using Singularity.Apps;

private DateTime fixed_now() {
    return new DateTime.local(2026, 9, 28, 9, 5, 0);
}

private string root_dir;

private string make_dir(string name) {
    string path = Path.build_filename(root_dir, name);
    DirUtils.create_with_parents(path, 0755);
    return path;
}

private void write_file(string dir, string name, string body) {
    try {
        FileUtils.set_contents(Path.build_filename(dir, name), body);
    } catch (Error e) {
        assert_not_reached();
    }
}

private void test_expand_known() {
    string out_text = WriteTemplates.expand("# {{title}}\n{{date}} {{time}} by {{user}} ({{weekday}}, {{isodate}}, {{year}})",
                                            "Notes", "Ada Lovelace", fixed_now());
    assert(out_text == "# Notes\n28 September 2026 09:05 by Ada Lovelace (Monday, 2026-09-28, 2026)");
}

private void test_expand_spacing_and_case() {
    assert(WriteTemplates.expand("{{ Date }}|{{TITLE}}", "T", "U", fixed_now()) == "28 September 2026|T");
}

private void test_expand_unknown_and_unclosed() {
    assert(WriteTemplates.expand("{{nope}} and {{user}}", "T", "U", fixed_now()) == "{{nope}} and U");
    assert(WriteTemplates.expand("open {{user", "T", "U", fixed_now()) == "open {{user");
    assert(WriteTemplates.expand("no placeholders", "T", "U", fixed_now()) == "no placeholders");
    assert(WriteTemplates.expand("", "T", "U", fixed_now()) == "");
}

private void test_expand_repeated() {
    assert(WriteTemplates.expand("{{user}}{{user}}", "T", "Bo", fixed_now()) == "BoBo");
}

private void test_builtin_templates() {
    var list = WriteTemplates.builtin();
    assert(list.size == 12);
    assert(list[0].id == WriteTemplates.BLANK);
    assert(list[0].load_body() == "");
    var ids = new GenericSet<string>(str_hash, str_equal);
    foreach (var t in list) {
        assert(!ids.contains(t.id));
        ids.add(t.id);
        assert(t.name != "" && t.description != "");
        assert(!t.removable);
        string body = t.load_body();
        if (t.id != WriteTemplates.BLANK) assert(body.length > 100);
        string expanded = WriteTemplates.expand(body, t.name, "Ada", fixed_now());
        assert(!("{{" in expanded));
    }
}

private void test_discovery() {
    string user = make_dir("user");
    string folder = make_dir("folder");
    write_file(user, "Standup.md", "# Standup\n");
    write_file(user, "alpha notes.markdown", "a");
    write_file(user, "ignored.txt", "x");
    write_file(user, ".hidden.md", "x");
    DirUtils.create_with_parents(Path.build_filename(user, "sub.md"), 0755);
    write_file(folder, "Invoice.md", "# Invoice\n");
    write_file(folder, "Sheet.ods", "x");
    var found = WriteTemplates.discover(user, folder);
    assert(found.size == 3);
    assert(found[0].name == "alpha notes");
    assert(found[0].kind == WriteTemplateKind.USER);
    assert(found[1].name == "Standup");
    assert(found[1].load_body() == "# Standup\n");
    assert(found[1].removable);
    assert(found[2].name == "Invoice");
    assert(found[2].kind == WriteTemplateKind.FOLDER);
    assert(found[2].id.has_prefix("folder:"));
    assert(WriteTemplates.discover(Path.build_filename(user, "missing"), null).size == 0);
    assert(WriteTemplates.discover(user, user).size == 2);
}

private void test_save_rename_remove() {
    string data = Environment.get_variable("XDG_DATA_HOME");
    var store = WriteTemplates.get_default();
    int changes = 0;
    store.changed.connect(() => changes++);
    try {
        var f = store.save("  Team/Sync ", "Hello {{user}}");
        assert(f.get_basename() == "Team-Sync.md");
        assert(f.get_path().has_prefix(Path.build_filename(data, "singularity-write", "templates")));
        var t = store.find("user:" + f.get_path());
        assert(t != null);
        assert(t.name == "Team-Sync");
        store.rename(t, "Weekly Sync");
        var renamed = store.find("user:" + Path.build_filename(WriteTemplates.user_dir(), "Weekly Sync.md"));
        assert(renamed != null);
        assert(renamed.load_body() == "Hello {{user}}");
        store.save("Other", "x");
        bool refused = false;
        try {
            store.rename(renamed, "Other");
        } catch (Error e) {
            refused = true;
        }
        assert(refused);
        bool empty_refused = false;
        try {
            store.save("  ", "x");
        } catch (Error e) {
            empty_refused = true;
        }
        assert(empty_refused);
        store.remove(renamed);
        assert(!renamed.file.query_exists());
    } catch (Error e) {
        stderr.printf("%s\n", e.message);
        assert_not_reached();
    }
    assert(changes == 4);
}

private void test_display_name() {
    assert(WriteTemplates.display_name("Report.md") == "Report");
    assert(WriteTemplates.display_name("a.b.MARKDOWN") == "a.b");
    assert(WriteTemplates.safe_name("..hidden") == "hidden");
}

private void test_parser_features() {
    var p = new Markdown.Parser();
    string html = p.to_html("---\ntitle: \"Hi\"\ntags: [a, b]\n---\n\n# Hello World\n\n- [ ] todo\n- [x] done\n- plain\n\nText[^n] here.\n\nLine one  \nLine two\n\n[^n]: The note.\n");
    assert("<dl class=\"front-matter\">" in html);
    assert("<dt>title</dt><dd>Hi</dd>" in html);
    assert("<dd>a, b</dd>" in html);
    assert("<h1 id=\"hello-world\">" in html);
    assert("<input type=\"checkbox\" disabled>todo" in html);
    assert("<input type=\"checkbox\" disabled checked>done" in html);
    assert("<li>plain</li>" in html);
    assert("<sup class=\"fn\"><a href=\"#fn-1\">1</a></sup>" in html);
    assert("<li id=\"fn-1\">The note.</li>" in html);
    assert(!("[^n]:" in html));
    assert("<p>Line one<br>\nLine two</p>" in html);
    string slash = p.to_html("First\\\nSecond\n");
    assert("<p>First<br>\nSecond</p>" in slash);
    string dup = p.to_html("## Notes\n\n## Notes\n");
    assert("id=\"notes\"" in dup && "id=\"notes-1\"" in dup);
    string hr = p.to_html("text\n\n---\n\nmore");
    assert("<hr>" in hr);
}

private void remove_tree(File dir) {
    try {
        var en = dir.enumerate_children("standard::name,standard::type", FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
        FileInfo? info;
        while ((info = en.next_file()) != null) {
            var child = dir.get_child(info.get_name());
            if (info.get_file_type() == FileType.DIRECTORY) remove_tree(child);
            else child.delete();
        }
        dir.delete();
    } catch (Error e) {
    }
}

public int main(string[] args) {
    Intl.setlocale(LocaleCategory.ALL, "C.UTF-8");
    try {
        root_dir = DirUtils.make_tmp("write-templates-XXXXXX");
    } catch (Error e) {
        return 1;
    }
    foreach (string v in new string[] { "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME" }) {
        string d = Path.build_filename(root_dir, v.down());
        DirUtils.create_with_parents(d, 0755);
        Environment.set_variable(v, d, true);
    }
    Test.init(ref args);
    Test.add_func("/write/templates/expand-known", test_expand_known);
    Test.add_func("/write/templates/expand-spacing", test_expand_spacing_and_case);
    Test.add_func("/write/templates/expand-unknown", test_expand_unknown_and_unclosed);
    Test.add_func("/write/templates/expand-repeated", test_expand_repeated);
    Test.add_func("/write/templates/builtin", test_builtin_templates);
    Test.add_func("/write/templates/discovery", test_discovery);
    Test.add_func("/write/templates/save-rename-remove", test_save_rename_remove);
    Test.add_func("/write/templates/display-name", test_display_name);
    Test.add_func("/write/templates/parser", test_parser_features);
    int status = Test.run();
    remove_tree(File.new_for_path(root_dir));
    return status;
}
