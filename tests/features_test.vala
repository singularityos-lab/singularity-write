using Write;
using Write.Test;

Document simple(string[] lines) {
    var d = Document.create_blank();
    d.body.clear();
    foreach (string l in lines) d.body.add(new Paragraph.with_text(l));
    return d;
}

void test_editing() {
    var d = simple({ "Hello world", "Second line" });
    var ed = new Editor(d);
    var p0 = (Paragraph) d.body[0];
    ed.set_caret(new Pos(p0, 5));
    ed.checkpoint("typing");
    ed.insert_text(", dear");
    check_eq(p0.plain_text(), "Hello, dear world", "insert text");
    ed.split_paragraph();
    check_int(d.body.size, 3, "split paragraph");
    check_eq(((Paragraph) d.body[1]).plain_text(), " world", "split tail");
    ed.delete_backward();
    check_int(d.body.size, 2, "backspace merges paragraphs");
    check_eq(p0.plain_text(), "Hello, dear world", "merge restores text");
    ed.select(new Pos(p0, 0), new Pos(p0, 5));
    ed.format_chars((c) => c.bold = Tri.ON);
    var r = p0.inlines[0];
    check(r is TextRun && ((TextRun) r).text == "Hello" && r.props.bold == Tri.ON, "bold applied to selection only");
    var p1 = (Paragraph) d.body[1];
    ed.select(new Pos(p0, 7), new Pos(p1, 7));
    ed.checkpoint("delete");
    ed.delete_selection();
    check_int(d.body.size, 1, "cross paragraph delete merges");
    check_eq(((Paragraph) d.body[0]).plain_text(), "Hello, line", "cross paragraph delete text");
    ed.do_undo();
    check_int(d.body.size, 2, "undo restores paragraphs");
    check_eq(((Paragraph) d.body[1]).plain_text(), "Second line", "undo restores text");
    ed.do_redo();
    check_int(d.body.size, 1, "redo reapplies");
    ed.do_undo();
    ed.do_undo();
    check_eq(((Paragraph) d.body[0]).plain_text(), "Hello world", "undo back to start");
    var frag = new BlockList();
    frag.add(new Paragraph.with_text("A"));
    frag.add(new Paragraph.with_text("B"));
    frag.add(new Paragraph.with_text("C"));
    ed.set_caret(new Pos((Paragraph) d.body[0], 5));
    ed.insert_blocks(frag);
    check_eq(((Paragraph) d.body[0]).plain_text(), "HelloA", "paste first joins");
    check_eq(((Paragraph) d.body[1]).plain_text(), "B", "paste middle paragraph");
    check_eq(((Paragraph) d.body[2]).plain_text(), "C world", "paste last joins tail");
    ed.select(new Pos((Paragraph) d.body[0], 0), new Pos((Paragraph) d.body[2], 1));
    var copy = ed.copy_selection();
    check_int(copy.size, 3, "copy selection blocks");
    check_eq(((Paragraph) copy[2]).plain_text(), "C", "copy last partial");
}

void test_tracked() {
    var d = simple({ "The quick fox" });
    d.track_changes = true;
    var ed = new Editor(d);
    ed.author = "Tester";
    var p = (Paragraph) d.body[0];
    ed.set_caret(new Pos(p, 4));
    ed.insert_text("very ");
    ed.select(new Pos(p, 9), new Pos(p, 15));
    ed.delete_selection();
    check_eq(p.plain_text(false), "The very fox", "tracked view without deletions");
    check_eq(p.plain_text(true), "The very quick fox", "deleted text kept");
    var revs = Review.collect(d);
    check_int(revs.size, 2, "two revisions");
    var accepted = d.copy();
    Review.resolve_all(accepted, true);
    check_eq(((Paragraph) accepted.body[0]).plain_text(true), "The very fox", "accept all");
    var rejected = d.copy();
    Review.resolve_all(rejected, false);
    check_eq(((Paragraph) rejected.body[0]).plain_text(true), "The quick fox", "reject all");
    var bytes = DocxWriter.save(d);
    try {
        var back = DocxReader.load(bytes);
        check_int(Review.collect(back).size, 2, "revisions survive docx");
    } catch (Error e) {
        check(false, e.message);
    }
    var fmt = simple({ "Plain" });
    fmt.track_changes = true;
    var fe = new Editor(fmt);
    var fp = (Paragraph) fmt.body[0];
    fe.select(new Pos(fp, 0), new Pos(fp, 5));
    fe.format_chars((c) => c.italic = Tri.ON);
    check(fp.inlines[0].fmt_rev != null && fp.inlines[0].props.italic == Tri.ON, "format change tracked");
    Review.resolve_all(fmt, false);
    check(fp.inlines[0].props.italic != Tri.ON, "format change rejected");
}

void test_compare() {
    var a = simple({ "Alpha beta gamma.", "Removed paragraph.", "Stays." });
    var b = simple({ "Alpha delta gamma.", "Stays.", "New paragraph." });
    var c = Review.compare(a, b, "Compare");
    string finals = "";
    string originals = "";
    var acc = c.copy();
    Review.resolve_all(acc, true);
    foreach (var p in acc.paragraphs(false)) finals += p.plain_text(true) + "|";
    var rej = c.copy();
    Review.resolve_all(rej, false);
    foreach (var p in rej.paragraphs(false)) originals += p.plain_text(true) + "|";
    check_eq(finals, "Alpha delta gamma.|Stays.|New paragraph.|", "compare accept gives revised");
    check_eq(originals, "Alpha beta gamma.|Removed paragraph.|Stays.|", "compare reject gives original");
}

void test_fields_toc() {
    var d = simple({ "Intro" });
    d.body.clear();
    d.body.add(FieldUpdater.make_toc());
    var h1 = new Paragraph.with_text("First", "Heading1");
    d.body.add(h1);
    var cap = FieldUpdater.make_caption(d, "Figure", "A chart");
    d.body.add(cap);
    var cap2 = FieldUpdater.make_caption(d, "Figure", "Another");
    d.body.add(cap2);
    var h2 = new Paragraph.with_text("Second", "Heading2");
    d.body.add(h2);
    var xp = new Paragraph.with_text("Term here");
    xp.inlines.add(new Mark(MarkKind.INDEX_ENTRY, "Zebra"));
    xp.inlines.add(new Mark(MarkKind.INDEX_ENTRY, "Apple"));
    d.body.add(xp);
    string bm = FieldUpdater.bookmark_of(cap2);
    var refp = new Paragraph.with_text("See ");
    refp.inlines.add(new FieldRun("REF %s \\h".printf(bm), "?"));
    refp.inlines.add(new TextRun(" and total "));
    refp.inlines.add(new FieldRun("= 2*(3+4)", ""));
    d.body.add(refp);
    var t = Table.create(3, 1, 200);
    ((Paragraph) t.rows[0].cells[0].blocks[0]).inlines.add(new TextRun("10"));
    ((Paragraph) t.rows[1].cells[0].blocks[0]).inlines.add(new TextRun("32"));
    ((Paragraph) t.rows[2].cells[0].blocks[0]).inlines.add(new FieldRun("=SUM(ABOVE)", ""));
    d.body.add(t);
    var idx = new FieldBlock("INDEX");
    d.body.add(idx);
    var src = new BibSource();
    src.tag = "Doe20";
    src.authors = { "Doe, Jane" };
    src.title = "A Study";
    src.year = "2020";
    src.publisher = "Pub";
    d.sources.add(src);
    var cp = new Paragraph.with_text("As shown ");
    cp.inlines.add(new FieldRun("CITATION Doe20", ""));
    d.body.add(cp);
    var bib = new FieldBlock("BIBLIOGRAPHY");
    d.body.add(bib);
    var engine = new LayoutEngine(d, new ViewOptions());
    var lay = engine.run();
    var up = new FieldUpdater(d, (p) => {
        int pi = lay.page_of(p);
        return pi >= 0 ? lay.pages[pi].number : 1;
    });
    up.update_all();
    var toc = (FieldBlock) d.body[0];
    check(toc.result.size == 2 && ((Paragraph) toc.result[0]).plain_text().has_prefix("First\t") && ((Paragraph) toc.result[1]).style == "TOC2", "toc generated with levels");
    check(((Paragraph) toc.result[0]).inlines[0].props.link != null, "toc entries are hyperlinks");
    check(cap2.plain_text().contains("Figure 2"), "caption numbering");
    check(refp.plain_text().contains("See Figure 2"), "cross reference to caption (%s)".printf(refp.plain_text()));
    check(refp.plain_text().contains("total 14"), "formula field");
    check(t.rows[2].cells[0].plain_text() == "42", "table SUM(ABOVE) (%s)".printf(t.rows[2].cells[0].plain_text()));
    check(idx.result.size >= 4 && ((Paragraph) idx.result[1]).plain_text().has_prefix("Apple") && ((Paragraph) idx.result[3]).plain_text().has_prefix("Zebra"), "index sorted with letters");
    check(cp.plain_text().contains("(Doe, 2020)"), "APA citation (%s)".printf(cp.plain_text()));
    check(bib.result.size == 1 && ((Paragraph) bib.result[0]).plain_text().has_prefix("Doe, J. (2020). A Study"), "bibliography entry (%s)".printf(((Paragraph) bib.result[0]).plain_text()));
    d.bib_style = "IEEE";
    up.update_all();
    check(cp.plain_text().contains("[1]"), "IEEE citation");
}

void test_find_replace() {
    var d = simple({ "Colour and colour and COLOUR", "cats catalog cat" });
    var o = new FindOptions();
    o.query = "colour";
    try {
        check_int(Finder.find_all(d, o).size, 3, "case insensitive find");
        o.match_case = true;
        check_int(Finder.find_all(d, o).size, 1, "match case");
        o.match_case = false;
        o.query = "cat";
        o.whole_word = true;
        check_int(Finder.find_all(d, o).size, 1, "whole word");
        o.whole_word = false;
        o.wildcards = true;
        o.query = "<cat*>";
        check_int(Finder.find_all(d, o).size, 3, "wildcard word start");
        o.query = "(c)(a)(t)";
        var ed = new Editor(d);
        int n = Finder.replace_all(ed, o, "\\3\\2\\1");
        check(n == 3 && ((Paragraph) d.body[1]).plain_text() == "tacs tacalog tac", "wildcard groups replace (%s)".printf(((Paragraph) d.body[1]).plain_text()));
        var fo = new FindOptions();
        fo.query = "and";
        int k = Finder.replace_all(ed, fo, "^t");
        check(k == 2 && ((Paragraph) d.body[0]).plain_text().contains("\t"), "special replacement tab");
        var bo = new FindOptions();
        var bd = simple({ "one two" });
        var bp = (Paragraph) bd.body[0];
        var be = new Editor(bd);
        be.select(new Pos(bp, 4), new Pos(bp, 7));
        be.format_chars((c) => c.bold = Tri.ON);
        bo.bold = Tri.ON;
        bo.query = "two";
        check_int(Finder.find_all(bd, bo).size, 1, "find with formatting");
        bo.query = "one";
        check_int(Finder.find_all(bd, bo).size, 0, "format filter excludes");
    } catch (RegexError e) {
        check(false, e.message);
    }
}

void test_merge() {
    var d = simple({ "Dear " });
    var p = (Paragraph) d.body[0];
    p.inlines.add(new FieldRun("MERGEFIELD First", ""));
    p.inlines.add(new TextRun(", you owe "));
    p.inlines.add(new FieldRun("MERGEFIELD Amount \\b \"EUR \"", ""));
    string csv = "First,Amount\n\"Ada, Countess\",10\nGrace,\n";
    try {
        FileUtils.set_contents(scratch("merge.csv"), csv);
        var ds = DataSource.load(scratch("merge.csv"));
        check(ds.records.size == 2 && ds.records[0]["First"] == "Ada, Countess", "csv parse with quotes");
        var merged = MailMerge.merge_all(d, ds);
        var paras = merged.paragraphs(false);
        check(paras.size == 2 && paras[0].plain_text() == "Dear Ada, Countess, you owe EUR 10" && paras[1].plain_text() == "Dear Grace, you owe ", "merge result (%s)".printf(paras[0].plain_text()));
        check(paras[0].section != null, "records separated by section breaks");
        FileUtils.set_contents(scratch("merge.vcf"), "BEGIN:VCARD\nVERSION:3.0\nFN:Linus T\nN:T;Linus;;;\nEMAIL:l@example.org\nADR:;;Main St 1;Town;;12345;FI\nEND:VCARD\n");
        var vc = DataSource.load(scratch("merge.vcf"));
        check(vc.records.size == 1 && vc.records[0]["City"] == "Town" && vc.records[0]["FirstName"] == "Linus", "vcard source");
        FileUtils.unlink(scratch("merge.sqlite"));
        Sqlite.Database sdb;
        Sqlite.Database.open(scratch("merge.sqlite"), out sdb);
        sdb.exec("CREATE TABLE Notes(x TEXT); CREATE TABLE Customers(First TEXT, Amount TEXT); INSERT INTO Customers VALUES('Bianchi Design','40'),('Casa Verde','15');");
        var sq = DataSource.load(scratch("merge.sqlite"));
        check(sq.records.size == 2 && sq.columns.length == 2 && sq.records[1]["First"] == "Casa Verde", "sqlite source picks the table with rows");
        var sq_merged = MailMerge.merge_all(d, sq).paragraphs(false);
        check(sq_merged.size == 2 && sq_merged[0].plain_text() == "Dear Bianchi Design, you owe EUR 40", "merge from sqlite (%s)".printf(sq_merged[0].plain_text()));
        var tmpl = new BlockList();
        var lp = new Paragraph("NoSpacing");
        lp.inlines.add(new FieldRun("MERGEFIELD Name", ""));
        tmpl.add(lp);
        var labels = MailMerge.labels(tmpl, vc, MailMerge.label_specs()[0]);
        check(labels.body[0] is Table && ((Table) labels.body[0]).rows[0].cells[0].plain_text() == "Linus T", "labels from data");
        var lay = new LayoutEngine(labels, new ViewOptions()).run();
        check(lay.pages.size == 1, "label sheet on one page");
        var env = MailMerge.envelope("Me\nHere", "You\nThere", true);
        check(env.final_section.page_w > env.final_section.page_h, "envelope landscape");
    } catch (Error e) {
        check(false, "merge: " + e.message);
    }
}

void test_proofing() {
    var g = new GrammarChecker();
    var p = new Paragraph.with_text("this is is a example.  We could of done it .");
    var issues = g.check(p, "en_US");
    var kinds = new StringBuilder();
    bool rep = false, art = false, could = false, cap = false, sp = false, pun = false;
    foreach (var i in issues) {
        kinds.append(i.message + ";");
        if (i.message.contains("Repeated")) rep = true;
        if (i.message.contains("“an”")) art = true;
        if (i.message.contains("have")) could = true;
        if (i.message.contains("capital")) cap = true;
        if (i.message.contains("Multiple spaces")) sp = true;
        if (i.message.contains("before punctuation")) pun = true;
    }
    check(rep && art && could && cap && sp && pun, "grammar rules fire: " + kinds.str);
    var it = g.check(new Paragraph.with_text("Non so perchè sia qual'è."), "it_IT");
    check(it.size >= 2, "italian rules fire");
    var ac = new AutoCorrect(scratch("ac.json"));
    int remove;
    string ins;
    check(ac.correct("I think teh", out remove, out ins) && ins == "the" && remove == 3, "autocorrect replacement");
    check(ac.correct("Done. next", out remove, out ins) && ins == "Next", "capitalize sentence start");
    check(ac.correct("I met HEllo", out remove, out ins) && ins == "Hello", "two initial caps");
    check(ac.correct("see (c)", out remove, out ins) && ins == "©", "symbol replacement");
    try {
        ac.entries["zz"] = "sleep";
        ac.save();
        var ac2 = new AutoCorrect(scratch("ac.json"));
        ac2.load();
        check(ac2.entries["zz"] == "sleep", "autocorrect list persisted");
    } catch (Error e) {
        check(false, e.message);
    }
    var hp = HyphenPatterns.parse("UTF-8\nLEFTHYPHENMIN 2\nRIGHTHYPHENMIN 2\n.hy3ph\nhe2n\nhena4\nhen5at\n1na\nn2at\n1tio\n2io\no2n\n", false);
    Hyphenator.get_default().register("xx", hp);
    check_eq(Hyphenator.get_default().hyphenate_word("hyphenation", "xx"), "hy-phen-ation", "hyphenation with patterns");
    try {
        FileUtils.set_contents(scratch("th_xx_v2.dat"), "UTF-8\nbig|2\n(adj)|large|huge\n(adj)|important\nsmall|1\n(adj)|little\n");
        var th = Thesaurus.get_default();
        th.dirs.insert(0, scratch(""));
        var m = th.lookup("big", "xx");
        check(m.size == 2 && m[0].synonyms[0] == "large" && m[1].synonyms[0] == "important", "mythes thesaurus lookup");
    } catch (Error e) {
        check(false, e.message);
    }
    var ad = simple({ "Title missing" });
    var img = new ImageRun(new Bytes(read_fixture("dot.png")), "image/png");
    ((Paragraph) ad.body[0]).inlines.add(img);
    ad.meta.title = "";
    var lowc = new CharProps();
    lowc.color = "#dddddd";
    ((Paragraph) ad.body[0]).inlines.add(new TextRun("pale", lowc));
    ad.body.add(new Paragraph.with_text("H1", "Heading1"));
    ad.body.add(new Paragraph.with_text("H3", "Heading3"));
    ad.body.add(Table.create(2, 2, 200));
    var found = AccessibilityChecker.check(ad);
    bool alt = false, title = false, contrast = false, skip = false, header = false;
    foreach (var f in found) {
        if (f.fix == "alt") alt = true;
        if (f.fix == "properties") title = true;
        if (f.title.contains("contrast")) contrast = true;
        if (f.title.contains("Skipped")) skip = true;
        if (f.fix == "header-row") header = true;
    }
    check(alt && title && contrast && skip && header, "accessibility checker findings");
}

void test_epub() {
    var d = build_rich();
    d.body.add(new Paragraph.with_text("Second chapter", "Heading1"));
    d.body.add(new Paragraph.with_text("More text"));
    var img = new Paragraph();
    var ir = new ImageRun(new Bytes(read_fixture("dot.png")), "image/png");
    ir.alt = "dot";
    img.inlines.add(ir);
    d.body.add(img);
    try {
        var bytes = EpubWriter.save(d);
        FileUtils.set_data(scratch("book.epub"), bytes);
        var z = new ZipReader(bytes);
        check(z.read_text("mimetype") == "application/epub+zip" && z.has("OEBPS/content.opf") && z.has("OEBPS/nav.xhtml"), "epub package parts");
        foreach (string n in z.names()) {
            if (!n.has_suffix(".xhtml") && !n.has_suffix(".opf") && !n.has_suffix(".xml")) continue;
            Xml.Doc* x = X.parse(z.read_text(n));
            delete x;
        }
        passed++;
        var back = EpubReader.load(bytes);
        check(find_para(back, "Second chapter") != null && find_para(back, "More text") != null, "epub text round trip");
        bool hh = false;
        foreach (var p in back.paragraphs(false)) if (p.plain_text() == "Chapter One" && p.style == "Heading1") hh = true;
        check(hh, "epub heading style round trip");
        check(first_of<ImageRun>(back) != null && first_of<ImageRun>(back).data.get_size() == 93, "epub image round trip");
        check(back.meta.title == "Rich", "epub title");
    } catch (Error e) {
        check(false, "epub: " + e.message);
    }
}

void test_omml() {
    try {
        var d = DocxReader.load(read_fixture("pandoc-sample.docx"));
        EquationRun? eq = first_of<EquationRun>(d);
        check(eq != null && eq.mathml.contains("<msup>") && eq.mathml.contains("<mi>a</mi>"), "omml converted to mathml (%s)".printf(eq != null ? eq.mathml : ""));
        string mml = "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mfrac><mrow><mi>a</mi></mrow><mrow><msqrt><mi>x</mi></msqrt></mrow></mfrac><msubsup><mo>\u2211</mo><mi>i</mi><mn>9</mn></msubsup></math>";
        string? om = Omml.from_mathml(mml, true);
        check(om != null && om.contains("<m:f>") && om.contains("<m:rad>") && om.contains("<m:nary>") && om.contains("oMathPara"), "mathml to omml");
        string? back = Omml.to_mathml(om, true);
        check(back != null && back.contains("<mfrac>") && back.contains("<msqrt>") && back.contains("\u2211"), "omml back to mathml");
        var nd = Document.create_blank();
        var p = (Paragraph) nd.body[0];
        var e2 = new EquationRun(mml);
        e2.display = true;
        p.inlines.add(e2);
        var bytes = DocxWriter.save(nd);
        var z = new ZipReader(bytes);
        check(z.read_text("word/document.xml").contains("<m:oMathPara"), "edited equation written as OMML");
        var odt = OdtWriter.save(nd);
        var oz = new ZipReader(odt);
        check(oz.has("Object 1/content.xml") && oz.read_text("Object 1/content.xml").contains("mfrac"), "equation written as ODF formula object");
        var od = OdtReader.load(odt);
        EquationRun? oe = first_of<EquationRun>(od);
        check(oe != null && oe.mathml.contains("mfrac"), "ODF formula object read back");
    } catch (Error e) {
        check(false, "omml: " + e.message);
    }
}

void test_charts() {
    try {
        var d = Document.create_blank();
        var ch = new ChartRun();
        ch.chart_xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><c:chartSpace xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\"><c:chart><c:plotArea><c:barChart><c:barDir val=\"col\"/></c:barChart></c:plotArea></c:chart></c:chartSpace>";
        ch.odf_content = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><office:document-content xmlns:office=\"urn:oasis:names:tc:opendocument:xmlns:office:1.0\" xmlns:chart=\"urn:oasis:names:tc:opendocument:xmlns:chart:1.0\"><office:body><office:chart><chart:chart chart:class=\"chart:bar\"/></office:chart></office:body></office:document-content>";
        ch.edited = true;
        ch.alt = "Sales chart";
        ((Paragraph) d.body[0]).inlines.add(ch);
        var bytes = DocxWriter.save(d);
        var z = new ZipReader(bytes);
        check(z.has("word/charts/chart1.xml") && z.read_text("word/charts/chart1.xml").contains("barChart"), "chart part written to DOCX");
        check(z.read_text("[Content_Types].xml").contains("drawingml.chart+xml"), "chart content type declared");
        check(z.read_text("word/_rels/document.xml.rels").contains("relationships/chart"), "chart relationship written");
        var back = DocxReader.load(bytes);
        ChartRun? rc = first_of<ChartRun>(back);
        check(rc != null && rc.chart_xml.contains("barChart"), "DOCX chart read back as a chart object");
        check(rc != null && (rc.alt == "Sales chart"), "chart alt text read back");
        var again = new ZipReader(DocxWriter.save(back));
        check(again.has("word/charts/chart1.xml"), "unedited chart passes through a second save");
        var odt = OdtWriter.save(d);
        var oz = new ZipReader(odt);
        check(oz.has("Object 1/content.xml") && oz.read_text("META-INF/manifest.xml").contains("opendocument.chart"), "chart written as ODF chart object");
        var od = OdtReader.load(odt);
        ChartRun? oc = first_of<ChartRun>(od);
        check(oc != null && oc.odf_content.contains("chart:bar"), "ODF chart read back as a chart object");
        var html = (string) Formats.save(d, FileFormat.HTML);
        check(!html.contains("chartSpace"), "chart without preview does not leak XML into HTML");
    } catch (Error e) {
        check(false, "charts: " + e.message);
    }
}

string body_text(Document d) {
    var sb = new StringBuilder();
    foreach (var b in d.body.items) {
        var p = b as Paragraph;
        if (p != null) sb.append(p.plain_text()).append("|");
        else sb.append("#|");
    }
    return sb.str;
}

void test_live() {
    var a = Document.create_blank();
    ((Paragraph) a.body[0]).insert_text(0, "Alpha one", new CharProps());
    var p2 = new Paragraph();
    p2.insert_text(0, "Beta two", new CharProps());
    a.body.add(p2);
    var p3 = new Paragraph();
    p3.insert_text(0, "Gamma three", new CharProps());
    a.body.add(p3);
    var la = new LiveDoc("a");
    var lb = new LiveDoc("b");
    var b = Document.create_blank();
    var state = la.full_state(a);
    var wire = LivePacket.from_json(state.to_json());
    lb.apply(b, wire);
    for (int i = b.body.size - 1; i >= 0; i--) if (!wire.order.contains(b.body[i].uid)) b.body.items.remove_at(i);
    lb.mark_synced(b);
    check(body_text(b) == body_text(a), "joining peer receives the whole document");
    ((Paragraph) a.body[0]).insert_text(5, " big", new CharProps());
    a.body[0].touch();
    ((Paragraph) b.body[2]).insert_text(11, " done", new CharProps());
    b.body[2].touch();
    var pa = la.collect(a);
    var pb = lb.collect(b);
    check(pa != null && pa.dirty.size == 1 && pb != null && pb.dirty.size == 1, "only the edited paragraph travels");
    lb.apply(b, LivePacket.from_json(pa.to_json()));
    la.apply(a, LivePacket.from_json(pb.to_json()));
    check(body_text(a) == body_text(b) && body_text(a).contains("Alpha big one") && body_text(a).contains("Gamma three done"), "edits in different paragraphs merge on both sides");
    ((Paragraph) a.body[1]).insert_text(0, "Very ", new CharProps());
    a.body[1].touch();
    ((Paragraph) b.body[1]).insert_text(8, " indeed", new CharProps());
    b.body[1].touch();
    pa = la.collect(a);
    pb = lb.collect(b);
    lb.apply(b, LivePacket.from_json(pa.to_json()));
    la.apply(a, LivePacket.from_json(pb.to_json()));
    check(((Paragraph) a.body[1]).plain_text() == "Very Beta two indeed" && ((Paragraph) b.body[1]).plain_text() == "Very Beta two indeed", "concurrent edits in the same paragraph merge at operation level");
    ((Paragraph) a.body[2]).insert_text(0, "[A]", new CharProps());
    a.body[2].touch();
    ((Paragraph) b.body[2]).insert_text(0, "[B]", new CharProps());
    b.body[2].touch();
    pa = la.collect(a);
    pb = lb.collect(b);
    lb.apply(b, LivePacket.from_json(pa.to_json()));
    la.apply(a, LivePacket.from_json(pb.to_json()));
    for (int round = 0; round < 3; round++) {
        var ra = la.collect(a);
        var rb = lb.collect(b);
        if (ra != null) lb.apply(b, LivePacket.from_json(ra.to_json()));
        if (rb != null) la.apply(a, LivePacket.from_json(rb.to_json()));
    }
    check(((Paragraph) a.body[2]).plain_text() == ((Paragraph) b.body[2]).plain_text() && ((Paragraph) a.body[2]).plain_text().has_prefix("[A][B]"), "inserts at the same point converge in the same order: " + ((Paragraph) a.body[2]).plain_text() + " / " + ((Paragraph) b.body[2]).plain_text());
    ((Paragraph) a.body[1]).insert_text(4, "X", new CharProps());
    a.body[1].touch();
    pa = la.collect(a);
    lb.apply(b, LivePacket.from_json(pa.to_json()));
    ((Paragraph) b.body[1]).insert_text(0, "Y", new CharProps());
    b.body[1].touch();
    ((Paragraph) a.body[1]).insert_text(0, "Z", new CharProps());
    a.body[1].touch();
    pa = la.collect(a);
    pb = lb.collect(b);
    lb.apply(b, LivePacket.from_json(pa.to_json()));
    la.apply(a, LivePacket.from_json(pb.to_json()));
    for (int round = 0; round < 3; round++) {
        var ra = la.collect(a);
        var rb = lb.collect(b);
        if (ra != null) lb.apply(b, LivePacket.from_json(ra.to_json()));
        if (rb != null) la.apply(a, LivePacket.from_json(rb.to_json()));
    }
    check(((Paragraph) a.body[1]).plain_text() == ((Paragraph) b.body[1]).plain_text() && ((Paragraph) a.body[1]).plain_text().index_of("X") > 0 && ((Paragraph) a.body[1]).plain_text().char_count() == 23, "an edit already seen is not duplicated: " + ((Paragraph) a.body[1]).plain_text() + " / " + ((Paragraph) b.body[1]).plain_text());
    var np = new Paragraph();
    np.insert_text(0, "Inserted by A", new CharProps());
    a.body.insert(1, np);
    b.body.items.remove_at(2);
    pa = la.collect(a);
    pb = lb.collect(b);
    lb.apply(b, LivePacket.from_json(pa.to_json()));
    la.apply(a, LivePacket.from_json(pb.to_json()));
    check(body_text(a) == body_text(b), "insert and delete converge: " + body_text(a) + " / " + body_text(b));
    check(body_text(a).contains("Inserted by A") && !body_text(a).contains("Gamma"), "inserted paragraph present and deleted one gone");
    var pos = new Pos((Paragraph) a.body[0], 3);
    var lp = LiveDoc.position_of(a, pos);
    var back = lp != null ? LiveDoc.resolve(b, lp) : null;
    check(back != null && back.offset == 3 && back.para.plain_text() == ((Paragraph) a.body[0]).plain_text(), "remote cursor position resolves on the other peer");
}

void test_script() {
    var d = Document.create_blank();
    ((Paragraph) d.body[0]).insert_text(0, "Intro TODO", new CharProps());
    foreach (string s in new string[] { "Plan", "Budget TODO", "Risks" }) {
        var p = new Paragraph();
        p.insert_text(0, s, new CharProps());
        d.body.add(p);
    }
    var t = Table.create(2, 2, 400);
    d.body.add(t);
    var ed = new Editor(d);
    var r = new ScriptRunner(d, ed);
    string[] actions = {};
    r.set_action((n, p) => {
        actions += n;
        return true;
    });
    string src = """
# headings for short paragraphs, counting with a loop
let n = 0
let todo = []
func shout(s) {
    return upper(s) + "!"
}
for p in paragraphs() {
    if p.in_table { continue }
    if contains(p.text, "TODO") {
        push(todo, p.text)
        p.text = replace(p.text, " TODO", "")
    } else if len(p.text) < 6 {
        set_style(p, "Heading1")
        n += 1
    }
}
let i = 0
while i < 3 {
    i = i + 1
    if i == 2 { break }
}
let tb = tables()[0]
set_cell(tb, 0, 0, "Item")
set_cell(tb, 0, 1, shout("cost"))
let row = add_row(tb)
set_cell(tb, row, 0, str(n))
let last = append("Open items: " + join(todo, "; "), "Normal")
format(last, "bold")
run("update-fields")
on save {
    set_variable("saved", "yes")
}
print("done", n, i)
""";
    try {
        r.run(src);
        check(r.output.size == 1 && r.output[0] == "done 2 2", "script variables, loops, conditions, break and functions: " + (r.output.size > 0 ? r.output[0] : ""));
        check(((Paragraph) d.body[1]).style == "Heading1" && ((Paragraph) d.body[3]).style == "Heading1", "script sets paragraph styles");
        check(((Paragraph) d.body[0]).plain_text() == "Intro" && ((Paragraph) d.body[2]).plain_text() == "Budget", "script edits paragraph text");
        check(t.rows.size == 3, "script adds a table row");
        var c00 = t.cell_at_grid(t.rows[0], 1).blocks.first_paragraph();
        check(c00 != null && c00.plain_text() == "COST!", "script writes table cells");
        bool found = false;
        foreach (var b in d.body.items) if (b is Paragraph && ((Paragraph) b).plain_text() == "Open items: Intro TODO; Budget TODO") found = ((Paragraph) b).inlines[0].props.bold.on();
        check(found, "script appends a formatted paragraph");
        check(actions.length == 1 && actions[0] == "update-fields", "script runs editor commands");
        r.fire("save");
        check(d.variables["saved"] == "yes", "document event handler runs");
    } catch (ScriptError e) {
        check(false, "script: " + e.message);
    }
    try {
        var sd = Document.create_blank();
        string script = "script:Tidy\non save {\n    set_title(\"Saved \" + str(word_count()))\n}\n";
        sd.macros.add(script);
        var back = DocxReader.load(DocxWriter.save(sd));
        check(back.macros.size == 1 && back.macros[0] == script, "document scripts survive a DOCX round trip");
        var odt_back = OdtReader.load(OdtWriter.save(sd));
        check(odt_back.macros.size == 1 && odt_back.macros[0] == script, "document scripts survive an ODT round trip");
    } catch (Error e) {
        check(false, "script storage: " + e.message);
    }
    try {
        new ScriptRunner(d, ed).run("let x = 1\nwhile true { x = x + 1 }");
        check(false, "endless loop is stopped");
    } catch (ScriptError e) {
        check(e.message.contains("too long"), "endless loop is stopped");
    }
    try {
        new ScriptRunner(d, ed).run("if 1 {");
        check(false, "syntax error reported");
    } catch (ScriptError e) {
        check(e is ScriptError.SYNTAX, "syntax error reported");
    }
}

void test_protection() {
    try {
        var d = Document.create_blank();
        d.protection.kind = ProtectKind.READ_ONLY;
        d.protection.enforced = true;
        d.protection.spin = 1000;
        d.protection.set_password("s3cret");
        var bytes = DocxWriter.save(d);
        var z = new ZipReader(bytes);
        string st = z.read_text("word/settings.xml");
        check(st.contains("w:algorithmName=\"SHA-512\"") && st.contains("w:spinCount=\"1000\""), "protection written with modern hash attributes");
        var back = DocxReader.load(bytes);
        check(back.protection.enforced && back.protection.kind == ProtectKind.READ_ONLY, "protection kind read back");
        check(back.protection.check_password("s3cret"), "right password unlocks after round trip");
        check(!back.protection.check_password("wrong"), "wrong password rejected after round trip");
    } catch (Error e) {
        check(false, "protection: " + e.message);
    }
}

string rev_summary(Document d) {
    var sb = new StringBuilder();
    foreach (var r in Review.collect(d)) sb.append("%s|%s|%s|%s;".printf(r.rev.kind.to_string(), r.rev.author, r.rev.date.substring(0, int.min(16, r.rev.date.length)), r.description()));
    return sb.str;
}

void check_revisions(Document d, string label, bool odt) {
    var list = Review.collect(d);
    int ins = 0, del = 0, fmt = 0;
    var authors = new Gee.HashSet<string>();
    foreach (var r in list) {
        if (r.rev.kind == RevKind.INSERT) ins++;
        else if (r.rev.kind == RevKind.DELETE) del++;
        else fmt++;
        authors.add(r.rev.author);
    }
    check(ins >= (odt ? 3 : 1), label + ": insertions read (" + rev_summary(d) + ")");
    check(del >= 1, label + ": deletion read");
    check(fmt >= (odt ? 1 : 2), label + ": formatting changes read");
    check(authors.contains("Ada Reviewer") && authors.contains("Bob Editor"), label + ": authors kept");
    var ir = find_run(d, "reviewed every year");
    check(ir != null && ir.rev != null && ir.rev.kind == RevKind.INSERT && ir.rev.date.has_prefix("2026-10-05T14:00"), label + ": inserted run carries author date");
    var dr = find_run(d, "old wording");
    check(dr != null && dr.rev != null && dr.rev.kind == RevKind.DELETE, label + ": deleted text kept as deletion");
    if (odt) {
        var a = find_run(d, "First added paragraph");
        var b = find_run(d, "Second added paragraph");
        check(a != null && a.rev != null && b != null && b.rev != null, label + ": insertion spanning paragraphs");
        var u = find_run(d, "Unchanged closing line");
        check(u != null && u.rev == null, label + ": text after the change is not marked");
    } else {
        var cp = find_para(d, "Centered by a reviewer");
        check(cp != null && cp.props_rev != null && cp.props_old != null && cp.props_old.align == Write.Align.LEFT, label + ": paragraph property change read");
    }
}

void test_revisions() {
    try {
        var od = OdtReader.load(read_fixture("revisions.odt"));
        check_revisions(od, "odt revisions", true);
        var od2 = OdtReader.load(OdtWriter.save(od));
        check_revisions(od2, "odt revisions roundtrip", true);
        var dd = DocxReader.load(read_fixture("revisions.docx"));
        check_revisions(dd, "docx revisions", false);
        var bytes = DocxWriter.save(dd);
        FileUtils.set_data(scratch("revisions-roundtrip.docx"), bytes);
        var dd2 = DocxReader.load(bytes);
        check_revisions(dd2, "docx revisions roundtrip", false);
        var odx = DocxReader.load(DocxWriter.save(od));
        check_revisions(odx, "odt to docx revisions", true);
        FileUtils.set_data(scratch("revisions-roundtrip.odt"), OdtWriter.save(od));
        var cp = find_para(dd2, "Centered by a reviewer");
        foreach (var r in Review.collect(dd2)) if (r.para == cp && r.para_props) Review.resolve(dd2, r, false);
        check(cp.props.align == Write.Align.LEFT && cp.props_rev == null, "reject paragraph change restores old properties");
        int n = Review.resolve_all(od, true);
        check(n > 0 && Review.collect(od).size == 0 && find_run(od, "old wording") == null && find_run(od, "reviewed every year").rev == null, "accept all resolves every revision");
        var dr = DocxReader.load(read_fixture("revisions.docx"));
        Review.resolve_all(dr, false);
        check(find_run(dr, "reviewed every year") == null && find_run(dr, "old wording") != null, "reject all removes insertions and keeps deleted text");
    } catch (Error e) {
        check(false, "revisions: " + e.message);
    }
}

int main(string[] args) {
    test_protection();
    test_script();
    test_live();
    test_charts();
    test_omml();
    test_editing();
    test_tracked();
    test_compare();
    test_fields_toc();
    test_find_replace();
    test_merge();
    test_proofing();
    test_epub();
    test_revisions();
    return finish("features");
}
