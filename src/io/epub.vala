namespace Write {

    public class EpubWriter : Object {
        private Document doc;
        private ZipWriter zip = new ZipWriter();
        private Gee.ArrayList<string> manifest = new Gee.ArrayList<string>();
        private Gee.HashMap<Bytes, string> images = new Gee.HashMap<Bytes, string>();
        private int image_n = 0;

        public static uint8[] save(Document doc) throws Error {
            return new EpubWriter(doc).write();
        }

        public EpubWriter(Document doc) {
            this.doc = doc;
        }

        private string image_src(ImageRun img) {
            if (images.has_key(img.data)) return images[img.data];
            image_n++;
            string name = "images/image%d.%s".printf(image_n, img.extension());
            try {
                zip.add("OEBPS/" + name, img.data.get_data(), false);
            } catch (Error e) {
            }
            manifest.add("<item id=\"img%d\" href=\"%s\" media-type=\"%s\"/>".printf(image_n, name, img.mime));
            images[img.data] = name;
            return name;
        }

        public uint8[] write() throws Error {
            zip.add_text("mimetype", "application/epub+zip", false);
            zip.add_text("META-INF/container.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<container version=\"1.0\" xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\"><rootfiles><rootfile full-path=\"OEBPS/content.opf\" media-type=\"application/oebps-package+xml\"/></rootfiles></container>\n");
            var chapters = new Gee.ArrayList<Gee.ArrayList<Block>>();
            var titles = new Gee.ArrayList<string>();
            var current = new Gee.ArrayList<Block>();
            string current_title = doc.meta.title != "" ? doc.meta.title : _("Start");
            foreach (var b in doc.body.items) {
                var p = b as Paragraph;
                if (p != null && p.style == "Heading1" && current.size > 0) {
                    chapters.add(current);
                    titles.add(current_title);
                    current = new Gee.ArrayList<Block>();
                }
                if (p != null && p.style == "Heading1") current_title = p.plain_text().strip();
                current.add(b);
            }
            if (current.size > 0 || chapters.size == 0) {
                chapters.add(current);
                titles.add(current_title);
            }
            var spine = new StringBuilder();
            var nav = new StringBuilder();
            for (int i = 0; i < chapters.size; i++) {
                var part = new Document();
                part.meta = doc.meta;
                part.styles = doc.styles;
                part.numbering = doc.numbering;
                part.lang = doc.lang;
                part.final_section = doc.final_section;
                foreach (var b in chapters[i]) part.body.items.add(b);
                var w = new HtmlWriter(part);
                w.xhtml = true;
                w.image_src = image_src;
                string html = w.write();
                string name = "chapter%03d.xhtml".printf(i + 1);
                zip.add_text("OEBPS/" + name, html);
                manifest.add("<item id=\"ch%d\" href=\"%s\" media-type=\"application/xhtml+xml\"/>".printf(i + 1, name));
                spine.append("<itemref idref=\"ch%d\"/>".printf(i + 1));
                nav.append("<li><a href=\"%s\">%s</a>".printf(name, X.esc(titles[i])));
                var sub = new StringBuilder();
                foreach (var b in chapters[i]) {
                    var p = b as Paragraph;
                    if (p == null || p.style != "Heading2") continue;
                    string anchor = FieldUpdater.bookmark_of(p) ?? "";
                    if (anchor == "") continue;
                    sub.append("<li><a href=\"%s#%s\">%s</a></li>".printf(name, X.esc(anchor), X.esc(p.plain_text().strip())));
                }
                if (sub.len > 0) nav.append("<ol>" + sub.str + "</ol>");
                nav.append("</li>\n");
            }
            string lang = doc.lang != "" ? doc.lang : "en";
            string title = doc.meta.title != "" ? doc.meta.title : _("Untitled");
            zip.add_text("OEBPS/nav.xhtml", "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE html>\n<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:epub=\"http://www.idpf.org/2007/ops\" lang=\"%s\"><head><meta charset=\"utf-8\"/><title>%s</title></head><body><nav epub:type=\"toc\" id=\"toc\"><h1>%s</h1><ol>\n%s</ol></nav></body></html>\n".printf(X.esc(lang), X.esc(title), X.esc(_("Contents")), nav.str));
            string uid = "urn:uuid:" + Uuid.string_random();
            string modified = new DateTime.now_utc().format("%Y-%m-%dT%H:%M:%SZ");
            var opf = new StringBuilder();
            opf.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<package xmlns=\"http://www.idpf.org/2007/opf\" version=\"3.0\" unique-identifier=\"uid\" xml:lang=\"%s\">".printf(X.esc(lang)));
            opf.append("<metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\"><dc:identifier id=\"uid\">%s</dc:identifier><dc:title>%s</dc:title><dc:language>%s</dc:language>".printf(uid, X.esc(title), X.esc(lang)));
            if (doc.meta.author != "") opf.append("<dc:creator>%s</dc:creator>".printf(X.esc(doc.meta.author)));
            if (doc.meta.subject != "") opf.append("<dc:subject>%s</dc:subject>".printf(X.esc(doc.meta.subject)));
            if (doc.meta.description != "") opf.append("<dc:description>%s</dc:description>".printf(X.esc(doc.meta.description)));
            opf.append("<meta property=\"dcterms:modified\">%s</meta></metadata><manifest>".printf(modified));
            opf.append("<item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/>");
            foreach (string m in manifest) opf.append(m);
            opf.append("</manifest><spine>%s</spine></package>\n".printf(spine.str));
            zip.add_text("OEBPS/content.opf", opf.str);
            return zip.finish();
        }
    }

    public class EpubReader : Object {

        public static Document load(uint8[] data) throws Error {
            var zip = new ZipReader(data);
            string? container = zip.read_text("META-INF/container.xml");
            if (container == null) throw new FormatError.INVALID(_("The file is not an EPUB book."));
            Xml.Doc* cx = X.parse(container);
            Xml.Node* rf = X.find_desc(cx->get_root_element(), "rootfile");
            string opf_path = rf != null ? X.val(rf, "full-path") : "";
            delete cx;
            string? opf = zip.read_text(opf_path);
            if (opf == null) throw new FormatError.INVALID(_("The book has no package document."));
            Xml.Doc* ox = X.parse(opf);
            Xml.Node* root = ox->get_root_element();
            var doc = Document.create_blank();
            doc.body.clear();
            Xml.Node* meta = X.child(root, "metadata");
            if (meta != null) {
                foreach (var n in X.kids(meta)) {
                    if (n->name == "title") doc.meta.title = X.text(n);
                    else if (n->name == "creator") doc.meta.author = X.text(n);
                    else if (n->name == "language") doc.lang = X.text(n);
                    else if (n->name == "subject") doc.meta.subject = X.text(n);
                    else if (n->name == "description") doc.meta.description = X.text(n);
                }
            }
            var items = new Gee.HashMap<string, string>();
            Xml.Node* man = X.child(root, "manifest");
            if (man != null) foreach (var it in X.kids(man, "item")) items[X.val(it, "id")] = DocxReader.resolve(opf_path, X.val(it, "href"));
            Xml.Node* spine = X.child(root, "spine");
            var chapters = new Gee.ArrayList<string>();
            if (spine != null) foreach (var ir in X.kids(spine, "itemref")) {
                string? path = items[X.val(ir, "idref")];
                if (path != null) chapters.add(path);
            }
            delete ox;
            string saved_title = doc.meta.title;
            foreach (string ch in chapters) {
                string? html = zip.read_text(ch);
                if (html == null) continue;
                var r = new HtmlReader();
                string chapter = ch;
                r.resolver = (src) => {
                    try {
                        return zip.read_bytes(DocxReader.resolve(chapter, Uri.unescape_string(src) ?? src));
                    } catch (Error e) {
                        return null;
                    }
                };
                r.read_into(html, doc);
            }
            doc.meta.title = saved_title;
            if (doc.body.size == 0) doc.body.add(new Paragraph());
            return doc;
        }
    }
}
