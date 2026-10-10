using Write;
using Write.Test;
using Singularity.Apps;

int main(string[] args) {
    if (!Gtk.init_check()) return 77;
    string dir;
    try {
        dir = DirUtils.make_tmp("write-proofing-XXXXXX");
        DirUtils.create_with_parents(Path.build_filename(dir, "hunspell"), 0700);
        FileUtils.set_contents(Path.build_filename(dir, "hunspell", "it_IT.aff"), "SET UTF-8\n");
        FileUtils.set_contents(Path.build_filename(dir, "hunspell", "it_IT.dic"), "5\nrichiesta\nconfermata\nverifica\naggiornamento\nperch\u00e9\n");
        FileUtils.set_contents(Path.build_filename(dir, "hunspell", "en_US.aff"), "SET UTF-8\n");
        FileUtils.set_contents(Path.build_filename(dir, "hunspell", "en_US.dic"), "2\nhello\nworld\n");
    } catch (Error e) {
        stderr.printf("%s\n", e.message);
        return 1;
    }
    Environment.set_variable("ENCHANT_CONFIG_DIR", dir, true);
    Environment.set_variable("LANGUAGE", "en_US", true);
    var schema = SettingsSchemaSource.get_default().lookup("dev.sinty.desktop", true);
    if (schema != null) {
        var settings = new GLib.Settings.full(schema, null, null);
        settings.set_strv("spell-check-languages", { "en_US" });
    }
    var first = Singularity.Text.SpellChecker.for_language("it-IT");
    check(first.available && first.check("richiesta"), "explicit language works before desktop checker initializes");
    check(first == Singularity.Text.SpellChecker.for_language("it_IT"), "language tag variants share a checker");
    var global = Singularity.Text.SpellChecker.get_default();
    check(global.available && !global.check("richiesta"), "desktop dictionary remains English");
    var doc = Document.create_blank();
    doc.lang = "it-IT";
    doc.body.clear();
    var p = new Paragraph.with_text("Richiesta confermata. Verifica aggiornamento.");
    doc.body.add(p);
    var view = new WriteDocView();
    view.grammar_enabled = false;
    view.set_document(doc, new Editor(doc));
    check_int(view.all_issues(true).size, 0, "Italian document uses Italian spelling");
    p.inlines.clear();
    p.inlines.add(new TextRun("Richiesta confermtaa"));
    p.touch();
    var issues = view.all_issues(true);
    check_int(issues.size, 1, "Italian typo is underlined");
    if (issues.size > 0) {
        check_eq(usub(p.text(), issues[0].start, issues[0].end), "confermtaa", "correct Italian word is not underlined");
        check("confermata" in issues[0].suggestions, "suggestions use Italian dictionary");
    }
    p.inlines.clear();
    var italian = new CharProps();
    italian.lang = "it-IT";
    p.inlines.add(new TextRun("Richiesta confermata ", italian));
    p.inlines.add(new TextRun("hello world"));
    p.touch();
    doc.lang = "en-US";
    view.refresh_spelling();
    check_int(view.all_issues(true).size, 0, "selected Italian text and English document use separate dictionaries");
    p.inlines[0].props.lang = null;
    p.touch();
    check(view.all_issues(true).size > 0, "removing text language restores document language");
    doc.lang = "it_IT";
    p.inlines.clear();
    p.inlines.add(new TextRun("Richiesta confermata"));
    p.touch();
    check_int(view.all_issues(true).size, 0, "underscore language tag works after switching language");
    doc.lang = "zz-ZZ";
    check_int(view.all_issues(true).size, 0, "missing dictionary does not check against English");
    doc.lang = "it-IT";
    p.inlines.clear();
    p.inlines.add(new TextRun("sintyproofword"));
    p.touch();
    check_int(view.all_issues(true).size, 1, "new personal word starts as a spelling issue");
    view.spell_checker_at(new Pos(p, 0)).add_to_dictionary("sintyproofword");
    view.refresh_spelling();
    check_int(view.all_issues(true).size, 0, "personal word is added to the text dictionary");
    check(!global.check("sintyproofword"), "personal Italian word is not added to English dictionary");
    doc.lang = "it-IT";
    view.doc_lang = "it-IT";
    var next = Document.create_blank();
    next.lang = "en-US";
    next.body.clear();
    next.body.add(new Paragraph.with_text("hello world"));
    view.set_document(next, new Editor(next));
    check_int(view.all_issues(true).size, 0, "opening another document resets proofing language");
    check(!global.check("richiesta") && global.check("hello"), "document language does not change desktop dictionary");
    FileUtils.remove(Path.build_filename(dir, "hunspell", "it_IT.aff"));
    FileUtils.remove(Path.build_filename(dir, "hunspell", "it_IT.dic"));
    FileUtils.remove(Path.build_filename(dir, "hunspell", "en_US.aff"));
    FileUtils.remove(Path.build_filename(dir, "hunspell", "en_US.dic"));
    FileUtils.remove(Path.build_filename(dir, "it_IT.dic"));
    FileUtils.remove(Path.build_filename(dir, "it_IT.exc"));
    FileUtils.remove(Path.build_filename(dir, "en_US.dic"));
    FileUtils.remove(Path.build_filename(dir, "en_US.exc"));
    DirUtils.remove(Path.build_filename(dir, "hunspell"));
    DirUtils.remove(dir);
    return finish("proofing");
}
