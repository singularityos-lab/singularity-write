using Write;
using Write.Test;

void check_pandoc_sample(Document d, string label) {
    var h1 = find_para(d, "Introduction");
    check(h1 != null && h1.style == "Heading1", label + ": heading 1 style");
    check(d.styles.outline_level(h1) == 0, label + ": heading outline level");
    var bold = find_run(d, "bold");
    check(bold != null && d.styles.resolve_char(find_para(d, "bold"), bold.props).bold == Tri.ON, label + ": bold run");
    var ital = find_run(d, "italic");
    check(ital != null && ital.props.italic == Tri.ON, label + ": italic run");
    var strike = find_run(d, "struck");
    check(strike != null && strike.props.strike == Tri.ON, label + ": strikethrough run");
    var link = find_run(d, "link");
    check(link != null && link.props.link == "https://example.org", label + ": hyperlink target");
    NoteRef? note = first_of<NoteRef>(d);
    check(note != null && note.note.kind == NoteKind.FOOTNOTE, label + ": footnote reference");
    if (note != null) {
        var np = note.note.blocks.first_paragraph();
        check(np != null && np.plain_text().contains("The footnote text."), label + ": footnote text");
    }
    var sub = find_run(d, "2");
    bool found_sub = false, found_sup = false;
    foreach (var p in d.paragraphs(false)) {
        foreach (var i in p.inlines) {
            if (i.props.valign == VAlign.SUB) found_sub = true;
            if (i.props.valign == VAlign.SUPER && !(i is NoteRef) && i.props.style == null) found_sup = true;
        }
    }
    check(sub != null && found_sub, label + ": subscript");
    check(found_sup, label + ": superscript");
    var bullet = find_para(d, "First bullet");
    check(bullet != null && bullet.props.num_id > 0, label + ": bullet list numbering");
    if (bullet != null) {
        var def = d.numbering.def_for(bullet.props.num_id);
        check(def != null && def.levels[0].format == NumFormat.BULLET, label + ": bullet format");
    }
    var nested = find_para(d, "Nested bullet");
    check(nested != null && nested.props.num_level == 1, label + ": nested level");
    var one = find_para(d, "One");
    if (one != null) {
        var def = d.numbering.def_for(one.props.num_id);
        check(def != null && def.levels[0].format == NumFormat.DECIMAL, label + ": decimal list");
    } else {
        check(false, label + ": numbered paragraph");
    }
    Table? table = null;
    foreach (var b in d.body.items) if (b is Table) table = (Table) b;
    check(table != null && table.rows.size == 3, label + ": table rows");
    if (table != null) {
        check(table.rows[2].cells.size == 2 && table.rows[2].cells[1].plain_text() == "22", label + ": table cell text");
        var cp = table.rows[2].cells[1].blocks.first_paragraph();
        check(cp != null && d.styles.resolve_para(cp).align == Align.RIGHT, label + ": right aligned column");
    }
    ImageRun? img = first_of<ImageRun>(d);
    check(img != null && img.mime == "image/png" && img.data.get_size() == 93, label + ": image bytes");
    if (img != null) {
        check_near(img.width, 144, 1, label + ": image width");
        check(img.alt.contains("red box") || img.title.contains("red box") || find_para(d, "A red box") != null, label + ": image description");
    }
    EquationRun? eq = first_of<EquationRun>(d);
    check(eq != null && eq.omml != null && eq.omml.contains("oMath"), label + ": inline equation kept as OMML");
    check_eq(d.meta.title, "Quarterly Report", label + ": title property");
    check_eq(d.meta.author, "Ada Lovelace", label + ": author property");
    var q = find_para(d, "A quoted paragraph.");
    check(q != null, label + ": quote paragraph");
}

void check_xml_parts(uint8[] data, string label) {
    try {
        var z = new ZipReader(data);
        foreach (string n in z.names()) {
            if (!n.has_suffix(".xml") && !n.has_suffix(".rels")) continue;
            string? t = z.read_text(n);
            Xml.Doc* x = X.parse(t);
            delete x;
        }
        check(z.has("[Content_Types].xml") && z.has("word/document.xml") && z.has("word/styles.xml"), label + ": package parts");
        passed++;
    } catch (Error e) {
        check(false, label + ": xml well formed: " + e.message);
    }
}

void test_pandoc_docx() {
    try {
        var d = DocxReader.load(read_fixture("pandoc-sample.docx"));
        check_pandoc_sample(d, "pandoc docx");
        var bytes = DocxWriter.save(d);
        check_xml_parts(bytes, "pandoc docx resave");
        var z = new ZipReader(bytes);
        check(z.has("word/theme/theme1.xml") && z.has("word/fontTable.xml"), "pandoc docx: unknown parts preserved");
        FileUtils.set_data(scratch("roundtrip-pandoc.docx"), bytes);
        var d2 = DocxReader.load(bytes);
        check_pandoc_sample(d2, "pandoc docx roundtrip");
        check_eq(body_text(d2), body_text(d), "pandoc docx roundtrip text identical");
    } catch (Error e) {
        check(false, "pandoc docx: " + e.message);
    }
}

void test_python_docx_default() {
    try {
        var d = DocxReader.load(read_fixture("python-docx-default.docx"));
        check(d.styles.list.size > 30, "python-docx default: styles read (%d)".printf(d.styles.list.size));
        check(d.styles.get("Heading1") != null && d.styles.get("Heading1").chr.size > 0, "python-docx default: heading style props");
        var bytes = DocxWriter.save(d);
        check_xml_parts(bytes, "python-docx default resave");
        var d2 = DocxReader.load(bytes);
        check(d2.styles.list.size >= d.styles.list.size, "python-docx default: styles survive");
    } catch (Error e) {
        check(false, "python-docx default: " + e.message);
    }
}

void test_rich_roundtrip() {
    try {
        var d = build_rich();
        check_rich(d, "rich model");
        var bytes = DocxWriter.save(d);
        check_xml_parts(bytes, "rich docx");
        FileUtils.set_data(scratch("roundtrip-rich.docx"), bytes);
        var d2 = DocxReader.load(bytes);
        check_rich(d2, "rich docx roundtrip");
        var bytes2 = DocxWriter.save(d2);
        var d3 = DocxReader.load(bytes2);
        check_rich(d3, "rich docx second roundtrip");
        check_eq(body_text(d3), body_text(d2), "rich docx stable text");
    } catch (Error e) {
        check(false, "rich docx: " + e.message);
    }
}

void test_refuse_garbage() {
    bool refused = false;
    try {
        DocxReader.load("not a zip at all".data);
    } catch (Error e) {
        refused = true;
    }
    check(refused, "garbage is refused, not parsed");
}

int main(string[] args) {
    test_pandoc_docx();
    test_python_docx_default();
    test_rich_roundtrip();
    test_refuse_garbage();
    return finish("docx");
}
