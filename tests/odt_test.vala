using Write;
using Write.Test;

void check_pandoc_odt(Document d, string label) {
    var h1 = find_para(d, "Introduction");
    check(h1 != null && h1.style == "Heading1", label + ": heading 1");
    var bold = find_run(d, "bold");
    check(bold != null && d.styles.resolve_char(find_para(d, "bold"), bold.props).bold == Tri.ON, label + ": bold");
    var ital = find_run(d, "italic");
    check(ital != null && d.styles.resolve_char(find_para(d, "italic"), ital.props).italic == Tri.ON, label + ": italic");
    var link = find_run(d, "link");
    check(link != null && link.props.link == "https://example.org", label + ": link");
    NoteRef? note = first_of<NoteRef>(d);
    check(note != null && note.note.blocks.first_paragraph().plain_text().contains("The footnote text."), label + ": footnote");
    var bullet = find_para(d, "First bullet");
    check(bullet != null && bullet.props.num_id > 0 && d.numbering.def_for(bullet.props.num_id).is_bullet(), label + ": bullet list");
    var nested = find_para(d, "Nested bullet");
    check(nested != null && nested.props.num_level == 1, label + ": nested level");
    Table? table = null;
    foreach (var b in d.body.items) if (b is Table) table = (Table) b;
    check(table != null && table.rows.size == 3 && table.rows[2].cells[1].plain_text() == "22", label + ": table");
    ImageRun? img = first_of<ImageRun>(d);
    check(img != null && img.mime == "image/png" && img.data.get_size() == 93, label + ": image");
    check_eq(d.meta.title, "Quarterly Report", label + ": title");
}

void test_pandoc_odt() {
    try {
        var d = OdtReader.load(read_fixture("pandoc-sample.odt"));
        check_pandoc_odt(d, "pandoc odt");
        var bytes = OdtWriter.save(d);
        FileUtils.set_data(scratch("roundtrip-pandoc.odt"), bytes);
        var z = new ZipReader(bytes);
        check(z.read_text("mimetype") == "application/vnd.oasis.opendocument.text", "odt: mimetype");
        foreach (string n in z.names()) {
            if (!n.has_suffix(".xml")) continue;
            Xml.Doc* x = X.parse(z.read_text(n));
            delete x;
        }
        passed++;
        var d2 = OdtReader.load(bytes);
        check_pandoc_odt(d2, "pandoc odt roundtrip");
        check_eq(body_text(d2), body_text(d), "pandoc odt roundtrip text");
    } catch (Error e) {
        check(false, "pandoc odt: " + e.message);
    }
}

void test_rich_odt() {
    try {
        var d = build_rich();
        var bytes = OdtWriter.save(d);
        FileUtils.set_data(scratch("roundtrip-rich.odt"), bytes);
        var d2 = OdtReader.load(bytes);
        check_rich(d2, "rich odt roundtrip", true);
        var d3 = OdtReader.load(OdtWriter.save(d2));
        check_rich(d3, "rich odt second roundtrip", true);
        check_eq(body_text(d3), body_text(d2), "rich odt stable text");
    } catch (Error e) {
        check(false, "rich odt: " + e.message);
    }
}

void test_cross_format() {
    try {
        var d = DocxReader.load(read_fixture("pandoc-sample.docx"));
        var odt = OdtWriter.save(d);
        var back = OdtReader.load(odt);
        check(find_para(back, "Introduction") != null && first_of<NoteRef>(back) != null && first_of<ImageRun>(back) != null, "docx to odt keeps structure");
        var docx = DocxWriter.save(back);
        var again = DocxReader.load(docx);
        check(find_run(again, "bold") != null && again.meta.title == "Quarterly Report", "odt to docx keeps content");
    } catch (Error e) {
        check(false, "cross format: " + e.message);
    }
}

void test_legacy_write_odt() {
    string legacy = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><office:document-content xmlns:office=\"urn:oasis:names:tc:opendocument:xmlns:office:1.0\" xmlns:text=\"urn:oasis:names:tc:opendocument:xmlns:text:1.0\" xmlns:style=\"urn:oasis:names:tc:opendocument:xmlns:style:1.0\" xmlns:fo=\"urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0\"><office:automatic-styles><style:style style:name=\"s_bold\" style:family=\"text\"><style:text-properties fo:font-weight=\"bold\"/></style:style></office:automatic-styles><office:body><office:text><text:h text:outline-level=\"1\" text:style-name=\"Heading_1\">Old</text:h><text:p text:style-name=\"Text_Body\">plain <text:span text:style-name=\"s_bold\">strong</text:span></text:p></office:text></office:body></office:document-content>";
    try {
        var z = new ZipWriter();
        z.add_text("mimetype", "application/vnd.oasis.opendocument.text", false);
        z.add_text("content.xml", legacy);
        var d = OdtReader.load(z.finish());
        var h = find_para(d, "Old");
        check(h != null && h.style == "Heading1", "legacy odt heading");
        var s = find_run(d, "strong");
        check(s != null && s.props.bold == Tri.ON, "legacy odt bold span");
    } catch (Error e) {
        check(false, "legacy odt: " + e.message);
    }
}

int main(string[] args) {
    test_pandoc_odt();
    test_rich_odt();
    test_cross_format();
    test_legacy_write_odt();
    return finish("odt");
}
