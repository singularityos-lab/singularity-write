using Write;
using Write.Test;

string lorem(int n) {
    string[] words = { "lorem", "ipsum", "dolor", "sit", "amet", "consectetur", "adipiscing", "elit", "sed", "do", "eiusmod", "tempor", "incididunt", "ut", "labore", "et", "dolore", "magna", "aliqua" };
    var sb = new StringBuilder();
    for (int i = 0; i < n; i++) {
        if (i > 0) sb.append_c(' ');
        sb.append(words[i % words.length]);
    }
    return sb.str;
}

Document long_doc() {
    var d = Document.create_blank();
    d.body.clear();
    var hdr = new HeaderFooter();
    var hp = new Paragraph.with_text("Page ", "Header");
    hp.inlines.add(new FieldRun("PAGE", "1"));
    hp.inlines.add(new TextRun(" of "));
    hp.inlines.add(new FieldRun("NUMPAGES", "1"));
    hdr.blocks.add(hp);
    d.final_section.header_default = hdr;
    for (int i = 0; i < 12; i++) {
        var h = new Paragraph.with_text("Chapter %d".printf(i + 1), "Heading1");
        d.body.add(h);
        for (int k = 0; k < 4; k++) d.body.add(new Paragraph.with_text(lorem(60 + i * 3 + k)));
    }
    return d;
}

LineBox? line_with(DocLayout lay, string text) {
    foreach (var p in lay.pages) foreach (var lb in p.lines) if (lb.para.plain_text().contains(text)) return lb;
    return null;
}

void test_pagination() {
    var d = long_doc();
    var engine = new LayoutEngine(d, new ViewOptions());
    var lay = engine.run();
    check(lay.pages.size >= 5, "pagination: long document spans pages (%d)".printf(lay.pages.size));
    foreach (var p in lay.pages) {
        foreach (var lb in p.lines) {
            if (lb.region != Region.BODY) continue;
            check(lb.top >= p.body_top - 0.5 && lb.top + lb.height <= p.body_bottom + 0.5, "pagination: line inside body area on page %d".printf(p.index + 1));
        }
    }
    int headers = 0;
    for (int i = 0; i < lay.pages.size; i++) {
        var p = lay.pages[i];
        foreach (var lb in p.lines) {
            if (lb.region != Region.HEADER) continue;
            string shown = lb.pl.text.text;
            if (shown.contains("Page %d of %d".printf(i + 1, lay.pages.size))) headers++;
        }
    }
    check(headers == lay.pages.size, "header with live PAGE and NUMPAGES on every page (%d of %d)".printf(headers, lay.pages.size));
    foreach (var p in lay.pages) {
        LineBox? lastb = null;
        foreach (var lb in p.lines) if (lb.region == Region.BODY) lastb = lb;
        if (lastb != null) check(!lastb.para.style.has_prefix("Heading") || lastb.para == d.body[d.body.size - 5], "keep with next: no heading stranded at page bottom (page %d)".printf(p.index + 1));
    }
}

void test_page_break_and_sections() {
    var d = Document.create_blank();
    d.body.clear();
    var a = new Paragraph.with_text("Before break");
    a.inlines.add(new Break(BreakKind.PAGE));
    a.inlines.add(new TextRun("After break"));
    d.body.add(a);
    var b = new Paragraph.with_text("Next page by property");
    b.props.page_break_before = Tri.ON;
    d.body.add(b);
    var c = new Paragraph.with_text("End of portrait section");
    c.section = new Section();
    d.body.add(c);
    d.body.add(new Paragraph.with_text("Landscape text " + lorem(400)));
    d.final_section.set_orientation(true);
    d.final_section.columns = 2;
    var lay = new LayoutEngine(d, new ViewOptions()).run();
    var l1 = line_with(lay, "Before break");
    int p_before = -1, p_after = -1;
    foreach (var p in lay.pages) foreach (var lb in p.lines) {
        string t = lb.pl.text.text.substring(lb.info.start_byte, lb.info.end_byte - lb.info.start_byte);
        if (t.contains("Before break")) p_before = p.index;
        if (t.contains("After break")) p_after = p.index;
    }
    check(l1 != null && p_before == 0 && p_after == 1, "inline page break honoured (%d, %d)".printf(p_before, p_after));
    var lb2 = line_with(lay, "Next page by property");
    check(lb2 != null && lb2.page == 2, "page break before honoured");
    var land = line_with(lay, "Landscape text");
    check(land != null && lay.pages[land.page].width > lay.pages[land.page].height, "new section starts landscape page");
    var xs = new Gee.HashSet<int>();
    foreach (var lb in lay.pages[land.page].lines) if (lb.region == Region.BODY && lb.para.plain_text().has_prefix("Landscape")) xs.add((int) lb.x);
    check(xs.size == 2, "two columns used (%d distinct x)".printf(xs.size));
}

void test_footnotes_tables() {
    var d = Document.create_blank();
    d.body.clear();
    for (int i = 0; i < 6; i++) d.body.add(new Paragraph.with_text(lorem(80)));
    var p = new Paragraph.with_text("Reference here");
    var n = new Note(NoteKind.FOOTNOTE);
    n.blocks.add(new Paragraph.with_text("The note body text", "FootnoteText"));
    p.inlines.add(new NoteRef(n));
    d.body.add(p);
    var t = Table.create(60, 3, 450);
    t.rows[0].header = true;
    ((Paragraph) t.rows[0].cells[0].blocks[0]).inlines.add(new TextRun("HeaderCell"));
    for (int r = 1; r < 60; r++) ((Paragraph) t.rows[r].cells[0].blocks[0]).inlines.add(new TextRun("Row %d".printf(r)));
    d.body.add(t);
    var lay = new LayoutEngine(d, new ViewOptions()).run();
    var ref_line = line_with(lay, "Reference here");
    var note_line = line_with(lay, "The note body text");
    check(ref_line != null && note_line != null && note_line.page == ref_line.page && note_line.region == Region.NOTES, "footnote on the page of its reference");
    if (note_line != null) check(note_line.top > ref_line.top && note_line.top + note_line.height <= lay.pages[note_line.page].body_bottom + 0.5, "footnote at page bottom inside body area");
    int header_repeats = 0;
    var pages_with_rows = new Gee.HashSet<int>();
    foreach (var pg in lay.pages) foreach (var lb in pg.lines) {
        string txt = lb.para.plain_text();
        if (txt == "HeaderCell") header_repeats++;
        if (txt.has_prefix("Row ")) pages_with_rows.add(pg.index);
    }
    check(pages_with_rows.size >= 2, "table flows over pages");
    check(header_repeats == pages_with_rows.size, "table header row repeated on each page (%d/%d)".printf(header_repeats, pages_with_rows.size));
}

void test_pdf() {
    var d = long_doc();
    d.meta.title = "Layout Test";
    string path = scratch("layout-test.pdf");
    try {
        var ex = new PdfExport(d);
        ex.write_file(path);
        var pdf = new Poppler.Document.from_file(File.new_for_path(path).get_uri(), null);
        var lay = new LayoutEngine(d, new ViewOptions()).run();
        check(pdf.get_n_pages() == lay.pages.size, "pdf page count matches layout (%d)".printf(pdf.get_n_pages()));
        string t2 = pdf.get_page(1).get_text();
        check(t2.contains("Page 2 of %d".printf(lay.pages.size)), "pdf page 2 header text");
        check(pdf.get_page(0).get_text().contains("Chapter 1"), "pdf body text");
        check(pdf.get_title() == "Layout Test", "pdf metadata title");
        var idx = new Poppler.IndexIter(pdf);
        check(idx != null, "pdf outline present");
        PdfExport.render_png(d, 0, scratch("layout-page1.png"), 1.5);
        check(FileUtils.test(scratch("layout-page1.png"), FileTest.EXISTS), "png render");
    } catch (Error e) {
        check(false, "pdf: " + e.message);
    }
}

void test_real_docx_layout() {
    try {
        var d = DocxReader.load(read_fixture("pandoc-sample.docx"));
        var lay = new LayoutEngine(d, new ViewOptions()).run();
        check(lay.pages.size == 1, "pandoc sample fits one page");
        bool img = false;
        foreach (var o in lay.pages[0].objects) if (o.item is ImageRun) img = true;
        check(img, "image placed in layout");
        PdfExport.render_png(d, 0, scratch("pandoc-sample-page1.png"), 1.5);
    } catch (Error e) {
        check(false, "real docx layout: " + e.message);
    }
}

int main(string[] args) {
    test_pagination();
    test_page_break_and_sections();
    test_footnotes_tables();
    test_pdf();
    test_real_docx_layout();
    return finish("layout");
}
