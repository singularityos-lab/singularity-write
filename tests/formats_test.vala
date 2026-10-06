using Write;
using Write.Test;

void test_sniff() {
    check(Formats.sniff(read_fixture("pandoc-sample.docx"), "x.bin") == FileFormat.DOCX, "sniff docx by content");
    check(Formats.sniff(read_fixture("pandoc-sample.odt"), "x.docx") == FileFormat.ODT, "sniff odt despite wrong extension");
    check(Formats.sniff(read_fixture("pandoc-sample.rtf"), "x.txt") == FileFormat.RTF, "sniff rtf");
    check(Formats.sniff(read_fixture("docbook-template.dot"), "t.dot") == FileFormat.DOC, "sniff binary word");
    check(Formats.sniff("# Title\n".data, "a.md") == FileFormat.MARKDOWN, "sniff markdown");
    check(Formats.sniff("<!DOCTYPE html><p>x".data, "a.html") == FileFormat.HTML, "sniff html");
    uint8[] png = read_fixture("dot.png");
    check(Formats.sniff(png, "a.docx") == FileFormat.UNKNOWN, "binary junk named .docx is not treated as a document");
    var z = new ZipWriter();
    try {
        z.add_text("[Content_Types].xml", "<Types><Override ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/></Types>");
        z.add_text("xl/workbook.xml", "<workbook/>");
    } catch (Error e) {
    }
    check(Formats.sniff(z.finish(), "a.xlsx") == FileFormat.OTHER_OFFICE, "sniff spreadsheet as other office");
    bool refused = false;
    try {
        Formats.load(png, FileFormat.UNKNOWN);
    } catch (Error e) {
        refused = true;
    }
    check(refused, "unknown format refused");
}

void test_rtf() {
    try {
        var d = RtfReader.load(read_fixture("pandoc-sample.rtf"));
        check(find_para(d, "Introduction") != null && find_para(d, "Introduction").props.outline == 0, "rtf: heading outline level");
        var b = find_run(d, "bold");
        check(b != null && b.props.bold == Tri.ON, "rtf: bold");
        var l = find_run(d, "link");
        check(l != null && l.props.link == "https://example.org", "rtf: hyperlink field");
        NoteRef? n = first_of<NoteRef>(d);
        check(n != null && n.note.blocks.first_paragraph() != null && n.note.blocks.first_paragraph().plain_text().contains("The footnote text."), "rtf: footnote");
        check(find_run(d, "Helvetica") == null, "rtf: font table not leaked into text");
        Table? t = null;
        foreach (var bl in d.body.items) if (bl is Table) t = (Table) bl;
        check(t != null && t.rows.size == 3 && t.rows[2].cells.size == 2 && t.rows[2].cells[1].plain_text() == "22", "rtf: table");
        check(first_of<ImageRun>(d) != null, "rtf: picture");
        var rich = build_rich();
        var bytes = RtfWriter.save(rich);
        FileUtils.set_data(scratch("roundtrip-rich.rtf"), bytes);
        var d2 = RtfReader.load(bytes);
        var styled = find_run(d2, "Styled");
        check(styled != null && styled.props.font == "Liberation Sans" && styled.props.size == 14 && styled.props.color == "#aa0000" && styled.props.caps == Caps.SMALL, "rtf roundtrip: char props");
        var p = find_para(d2, "commented");
        check(p != null && p.props.align == Align.JUSTIFY && p.props.ind_left == 36 && p.props.space_after == 12, "rtf roundtrip: para props");
        bool hs = false;
        foreach (var hp in d2.paragraphs(false)) if (hp.plain_text() == "Chapter One" && hp.style == "Heading1" && hp.parent == d2.body) hs = true;
        check(hs, "rtf roundtrip: heading style");
        FieldBlock? toc = null;
        foreach (var bl in d2.body.items) if (bl is FieldBlock) toc = (FieldBlock) bl;
        check(toc != null && toc.kind() == "TOC" && toc.result.size == 1, "rtf roundtrip: toc block");
        bool del = false, ins = false;
        foreach (var i in p.inlines) {
            if (i.rev != null && i.rev.kind == RevKind.DELETE) del = true;
            if (i.rev != null && i.rev.kind == RevKind.INSERT && i.rev.author == "Grace") ins = true;
        }
        check(del && ins, "rtf roundtrip: revisions");
        check(d2.final_section.landscape && d2.final_section.header_default != null, "rtf roundtrip: landscape and header");
        Table? t2 = null;
        foreach (var bl in d2.body.items) if (bl is Table) t2 = (Table) bl;
        check(t2 != null && t2.rows.size == 2, "rtf roundtrip: table");
        var li = find_para(d2, "Listed");
        check(li != null && li.props.num_id > 0, "rtf roundtrip: list");
        check(d2.comments.size >= 1 && d2.comments[0].text() == "Check this.", "rtf roundtrip: comment");
        check(first_of<FieldRun>(d2) != null, "rtf roundtrip: field");
    } catch (Error e) {
        check(false, "rtf: " + e.message);
    }
}

void test_html_md() {
    var rich = build_rich();
    string html = HtmlWriter.save(rich);
    try {
        FileUtils.set_contents(scratch("export.html"), html);
    } catch (Error e) {
    }
    check(html.contains("<h1") && html.contains("Chapter One") && html.contains("<table") && html.contains("footnotes") == false || html.contains("An endnote."), "html export content");
    var d = HtmlReader.load(html, null);
    bool hh = false;
    foreach (var hp in d.paragraphs(false)) if (hp.plain_text() == "Chapter One" && hp.style == "Heading1") hh = true;
    check(hh, "html roundtrip heading");
    var st = find_run(d, "Styled");
    check(st != null && st.props.color == "#aa0000" && st.props.size == 14, "html roundtrip char props");
    Table? t = null;
    foreach (var b in d.body.items) if (b is Table) t = (Table) b;
    check(t != null && t.rows.size == 2, "html roundtrip table");
    string md = MarkdownWriter.save(rich);
    try {
        FileUtils.set_contents(scratch("export.md"), md);
    } catch (Error e) {
    }
    check(md.contains("# Chapter One") && md.contains("- Listed") && md.contains("[^1]"), "markdown export");
    var parser = new Markdown.Parser();
    var back = HtmlReader.load_fragment(parser.to_html(md));
    check(find_para(back, "Chapter One") != null && find_para(back, "Listed") != null && find_para(back, "Listed").props.num_id > 0, "markdown import via html");
    var pd = HtmlReader.load_fragment(parser.to_html("Some **bold** and *it* text [^n]\n\n[^n]: A note.\n"));
    var bb = find_run(pd, "bold");
    check(bb != null && bb.props.bold == Tri.ON, "markdown bold imported");
    NoteRef? nr = first_of<NoteRef>(pd);
    check(nr != null && nr.note.blocks.size > 0 && nr.note.blocks.first_paragraph().plain_text().contains("A note."), "markdown footnote imported");
    string txt = Formats.to_text(rich);
    check(txt.contains("Chapter One\n") && txt.contains("\u2022 Listed"), "text export with list labels");
    var td = Formats.from_text("a\tb\nc\n");
    check(td.body.size == 2 && ((Paragraph) td.body[0]).inlines.size == 3, "text import with tabs");
}

void test_doc() {
    try {
        var d = DocReader.load(read_fixture("docbook-template.dot"));
        string txt = body_text(d);
        FileUtils.set_contents(scratch("doc.txt"), txt);
        check(txt.strip() == "Generic DocBook roundtrip template - 2008-10-09-01.", "doc: body text of a real Word 97 file");
        check(d.meta.title == "This document left intentionally blank" && d.meta.author == "Steve Ball", "doc: summary properties");
        var saved = DocxWriter.save(d);
        var back = DocxReader.load(saved);
        check_eq(body_text(back), body_text(d), "doc converted to docx keeps text");
    } catch (Error e) {
        check(false, "doc: " + e.message);
    }
}

void test_notes_clip() {
    var html = (string) read_fixture("notes-clip.html");
    var d = HtmlReader.load(html, null);
    var h = find_para(d, "Launch notes");
    check(h != null && h.style == "Heading2", "notes clip: first heading keeps its style");
    var draft = find_para(d, "Draft the announcement");
    int boxes = 0;
    bool glyph = false;
    if (draft != null) foreach (var i in draft.inlines) {
        if (i is FormField) boxes++;
        if (i is TextRun && (((TextRun) i).text.contains("\u2610") || ((TextRun) i).text.contains("\u2611"))) glyph = true;
    }
    check(boxes == 1 && !glyph, "notes clip: one real checkbox and no fallback glyph");
    check(draft != null && draft.props.num_id == 0, "notes clip: to do items carry no bullet");
    var checked_box = draft != null ? draft.inlines[0] as FormField : null;
    check(checked_box != null && checked_box.checked, "notes clip: checked state kept");
    var login = find_para(d, "Check the login flow");
    check(login != null && login.props.ind_left > 0, "notes clip: nested to do item indented");
    var prepare = find_para(d, "Prepare");
    var freeze = find_para(d, "Freeze the features");
    var rome = find_para(d, "Rome");
    check(prepare != null && prepare.props.num_id > 0 && prepare.props.num_level == 0, "notes clip: outer bullet at level 0");
    check(freeze != null && freeze.props.num_level == 1 && freeze.props.num_id == prepare.props.num_id, "notes clip: nested bullet at level 1");
    check(rome != null && rome.props.num_level == 2 && rome.props.num_id > 0 && !d.numbering.def_for(rome.props.num_id).is_bullet(), "notes clip: nested ordered list at level 2");
    var lv = rome != null ? d.numbering.level(rome.props.num_id, 2) : null;
    check(lv != null && lv.format == NumFormat.LOWER_ROMAN && lv.ind_left > d.numbering.level(prepare.props.num_id, 0).ind_left, "notes clip: roman numbering and deeper indent");
    check(prepare != null && freeze != null && rome != null && prepare.props.ind_left < freeze.props.ind_left && freeze.props.ind_left < rome.props.ind_left, "notes clip: nested items are laid out deeper");
    Table? t = null;
    foreach (var b in d.body.items) if (b is Table) t = (Table) b;
    check(t != null && t.rows.size == 3, "notes clip: table read");
    check(t != null && t.rows[0].cells[0].shading == "#d0ebff" && t.rows[1].cells[1].shading == "#fff3bf" && t.rows[1].cells[0].shading == null, "notes clip: cell shading from style");
    var doc = Document.create_blank();
    var ed = new Editor(doc);
    var existing = doc.numbering.add_instance(doc.numbering.make_numbers());
    var nums = doc.numbering.merge(d.numbering);
    check(nums.has_key(prepare.props.num_id) && nums[prepare.props.num_id] != existing && doc.numbering.def_for(nums[prepare.props.num_id]).is_bullet(), "notes clip: pasted lists get their own numbering");
    foreach (var p in Story.paragraphs(d.body)) if (p.props.num_id > 0 && nums.has_key(p.props.num_id)) p.props.num_id = nums[p.props.num_id];
    ed.insert_blocks(d.body, true);
    var ph = find_para(doc, "Launch notes");
    check(ph != null && ph.style == "Heading2", "notes clip: heading style survives paste into an empty paragraph");
}

int main(string[] args) {
    test_sniff();
    test_rtf();
    test_html_md();
    test_doc();
    test_notes_clip();
    return finish("formats");
}
