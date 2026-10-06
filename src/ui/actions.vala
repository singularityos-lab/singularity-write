using Gtk;
using Write;

namespace Singularity.Apps {

    public class WriteActions : Object {

        public static string[] names() {
            return {
                "bold", "italic", "underline", "double-underline", "strike", "dstrike", "superscript", "subscript", "smallcaps", "allcaps",
                "grow-font", "shrink-font", "clear-formatting", "font-dialog", "paragraph-dialog", "align", "line-spacing", "space-before", "space-after",
                "indent-more", "indent-less", "bullets", "numbering", "multilevel", "restart-numbering", "style", "styles-pane", "new-style", "modify-style",
                "manage-styles", "style-set", "change-case", "text-color", "highlight", "text-color-menu", "highlight-menu", "font", "size",
                "page-break", "column-break", "section-break", "table-dialog", "picture", "shape", "textbox", "wordart", "equation", "equation-inline",
                "symbol", "footnote", "endnote", "new-comment", "delete-comment", "resolve-comment", "next-comment", "prev-comment", "comments-pane",
                "bookmark", "link", "remove-link", "cross-reference", "caption", "field", "date-time", "page-number", "toc", "tof", "index",
                "index-entry", "citation", "sources", "bibliography", "bib-style", "header", "footer", "watermark", "dropcap", "checkbox-field",
                "text-field", "dropdown-field", "page-setup", "columns", "borders", "page-color", "page-borders", "orientation", "hyphenation",
                "line-numbers", "spelling", "thesaurus", "word-count", "language", "track-changes", "accept", "reject", "accept-all", "reject-all",
                "next-change", "prev-change", "review-pane", "markup", "compare", "combine", "protect", "accessibility", "read-aloud",
                "merge-recipients", "merge-field", "merge-preview", "merge-next", "merge-prev", "merge-finish", "envelopes", "labels",
                "table-op", "table-sort", "table-formula", "table-properties", "table-style", "text-to-table", "table-to-text",
                "macro-record", "macro-run", "macros", "autocorrect", "update-fields", "update-toc", "navigation", "ruler", "marks", "view",
                "zoom", "zoom-in", "zoom-out", "undo", "redo", "cut", "copy", "paste", "paste-text", "paste-special", "select-all", "find",
                "find-replace", "goto", "format-painter", "properties", "versions", "insert-file", "comment-reply", "chart", "reveal-formatting", "equation-gallery", "translate", "dictate", "live-share", "live-stop", "run-script", "script-new", "live-host", "live-join", "live-folder-start", "live-folder-join"
            };
        }

        public static bool with_param(string n) {
            switch (n) {
                case "align":
                case "line-spacing":
                case "style":
                case "style-set":
                case "change-case":
                case "text-color":
                case "highlight":
                case "font":
                case "section-break":
                case "shape":
                case "page-number":
                case "markup":
                case "merge-finish":
                case "table-op":
                case "table-style":
                case "view":
                case "zoom":
                case "orientation":
                case "bib-style":
                case "run-script":
                case "live-join":
                case "live-folder-start":
                case "live-folder-join":
                    return true;
                default:
                    return false;
            }
        }

        public static bool is_double(string n) {
            return n == "size";
        }

        private static void fmt(WriteRichEditor r, string label, owned CharMutator fn) {
            var ed = r.ed;
            if (!r.editable()) return;
            if (ed.has_selection) {
                ed.checkpoint(label);
                ed.format_chars((c) => fn(c));
                return;
            }
            int s, e;
            ed.word_at(ed.focus, out s, out e);
            if (s < ed.focus.offset && ed.focus.offset < e) {
                var saved = ed.focus.copy();
                ed.checkpoint(label);
                ed.select(new Pos(saved.para, s), new Pos(saved.para, e));
                ed.format_chars((c) => fn(c));
                ed.set_caret(saved);
                return;
            }
            var pending = (r.view.pending ?? ed.props_for_insert()).copy();
            fn(pending);
            r.view.pending = pending;
            r.fbar.sync(r.doc, ed, pending);
        }

        private static CharProps current(WriteRichEditor r) {
            var ed = r.ed;
            CharProps raw;
            if (r.view.pending != null) raw = r.view.pending;
            else if (ed.has_selection) {
                Pos a, b;
                ed.ordered(out a, out b);
                raw = a.para.props_at(a.offset + 1);
            } else raw = ed.focus.para.props_at(ed.focus.offset);
            return r.doc.styles.resolve_char(ed.focus.para, raw);
        }

        private static void para(WriteRichEditor r, string label, owned ParaMutator fn) {
            if (!r.editable()) return;
            r.ed.checkpoint(label);
            r.ed.format_paragraphs((p) => fn(p));
        }

        private static void insert_block_field(WriteRichEditor r, FieldBlock fb) {
            var ed = r.ed;
            ed.checkpoint(_("Insert Field"));
            var p = ed.focus.para;
            var list = p.parent;
            if (list == null) return;
            int idx = list.items.index_of(p);
            if (p.is_empty()) {
                list.insert(idx, fb);
            } else {
                if (ed.focus.offset > 0) {
                    ed.split_paragraph();
                    list.insert(list.items.index_of(ed.focus.para), fb);
                } else {
                    list.insert(idx, fb);
                }
            }
            r.update_fields();
            int at = list.items.index_of(fb);
            Paragraph? after = at + 1 < list.size ? list[at + 1] as Paragraph : null;
            if (after == null) {
                after = new Paragraph();
                list.insert(at + 1, after);
                ed.changed();
            }
            ed.set_caret(new Pos(after, 0));
        }

        private static void section_break(WriteRichEditor r, string kind) {
            var ed = r.ed;
            if (!r.editable()) return;
            ed.checkpoint(_("Insert Section Break"));
            if (ed.focus.offset > 0 || !ed.focus.para.is_empty()) ed.split_paragraph();
            var cur = ed.focus.para;
            var list = cur.parent;
            if (list == null || list != r.doc.body) {
                r.toast(_("Section breaks can only be inserted in the main text."));
                return;
            }
            int idx = list.items.index_of(cur);
            Paragraph? prev = idx > 0 ? list[idx - 1] as Paragraph : null;
            if (prev == null) {
                prev = new Paragraph();
                list.insert(idx, prev);
            }
            var old = r.doc.section_for(cur);
            var ended = old.copy();
            prev.section = ended;
            SectionStart st = SectionStart.NEXT_PAGE;
            switch (kind) {
                case "continuous": st = SectionStart.CONTINUOUS; break;
                case "even": st = SectionStart.EVEN_PAGE; break;
                case "odd": st = SectionStart.ODD_PAGE; break;
                default: break;
            }
            old.start = st;
            old.page_start = -1;
            prev.touch();
            ed.changed();
        }

        public static void run(WriteRichEditor r, string name, Variant? p) {
            var ed = r.ed;
            var doc = r.doc;
            var view = r.view;
            string sp = p != null && p.is_of_type(VariantType.STRING) ? p.get_string() : "";
            switch (name) {
                case "bold":
                    bool on = !current(r).bold.on();
                    fmt(r, _("Bold"), (c) => c.bold = Tri.of(on));
                    break;
                case "italic":
                    bool on = !current(r).italic.on();
                    fmt(r, _("Italic"), (c) => c.italic = Tri.of(on));
                    break;
                case "underline":
                    var cu = current(r).underline;
                    bool on = cu == Underline.NONE || cu == Underline.INHERIT;
                    fmt(r, _("Underline"), (c) => c.underline = on ? Underline.SINGLE : Underline.NONE);
                    break;
                case "double-underline":
                    bool on = current(r).underline != Underline.DOUBLE;
                    fmt(r, _("Double Underline"), (c) => c.underline = on ? Underline.DOUBLE : Underline.NONE);
                    break;
                case "strike":
                    bool on = !current(r).strike.on();
                    fmt(r, _("Strikethrough"), (c) => c.strike = Tri.of(on));
                    break;
                case "dstrike":
                    bool on = !current(r).dstrike.on();
                    fmt(r, _("Double Strikethrough"), (c) => c.dstrike = Tri.of(on));
                    break;
                case "superscript":
                    bool on = current(r).valign != VAlign.SUPER;
                    fmt(r, _("Superscript"), (c) => c.valign = on ? VAlign.SUPER : VAlign.BASELINE);
                    break;
                case "subscript":
                    bool on = current(r).valign != VAlign.SUB;
                    fmt(r, _("Subscript"), (c) => c.valign = on ? VAlign.SUB : VAlign.BASELINE);
                    break;
                case "smallcaps":
                    bool on = current(r).caps != Caps.SMALL;
                    fmt(r, _("Small Caps"), (c) => c.caps = on ? Caps.SMALL : Caps.NONE);
                    break;
                case "allcaps":
                    bool on = current(r).caps != Caps.ALL;
                    fmt(r, _("All Caps"), (c) => c.caps = on ? Caps.ALL : Caps.NONE);
                    break;
                case "grow-font":
                case "shrink-font":
                    double cur = current(r).size > 0 ? current(r).size : 11;
                    double[] steps = { 8, 9, 10, 10.5, 11, 12, 14, 16, 18, 20, 22, 24, 26, 28, 36, 48, 72 };
                    double nv = cur;
                    if (name == "grow-font") {
                        nv = cur + 1;
                        foreach (double s in steps) if (s > cur) {
                            nv = s;
                            break;
                        }
                    } else {
                        nv = double.max(1, cur - 1);
                        for (int i = steps.length - 1; i >= 0; i--) if (steps[i] < cur) {
                            nv = steps[i];
                            break;
                        }
                    }
                    fmt(r, _("Font Size"), (c) => c.size = nv);
                    break;
                case "size":
                    double sz = p != null && p.is_of_type(VariantType.DOUBLE) ? p.get_double() : 11;
                    fmt(r, _("Font Size"), (c) => c.size = sz);
                    break;
                case "font":
                    fmt(r, _("Font"), (c) => c.font = sp);
                    break;
                case "text-color":
                    string? col = sp == "" || sp == "auto" ? null : sp;
                    fmt(r, _("Font Color"), (c) => c.color = col);
                    r.fbar.color_face.set_color(col);
                    break;
                case "highlight":
                    string? hl = sp == "" || sp == "none" ? null : sp;
                    fmt(r, _("Highlight"), (c) => c.highlight = hl);
                    r.fbar.highlight_face.set_color(hl);
                    break;
                case "text-color-menu":
                    WriteDialogs.color_menu(r, false);
                    break;
                case "highlight-menu":
                    WriteDialogs.color_menu(r, true);
                    break;
                case "clear-formatting":
                    if (!r.editable()) break;
                    ed.checkpoint(_("Clear Formatting"));
                    if (ed.has_selection) {
                        ed.format_chars((c) => {
                            string? link = c.link;
                            var fresh = new CharProps();
                            fresh.link = link;
                            fresh.style = link != null ? "Hyperlink" : null;
                            c.font = null;
                            c.size = 0;
                            c.bold = Tri.INHERIT;
                            c.italic = Tri.INHERIT;
                            c.strike = Tri.INHERIT;
                            c.dstrike = Tri.INHERIT;
                            c.underline = Underline.INHERIT;
                            c.caps = Caps.INHERIT;
                            c.valign = VAlign.INHERIT;
                            c.color = null;
                            c.highlight = null;
                            c.shading = null;
                            c.spacing = double.NAN;
                            c.position = double.NAN;
                            c.style = fresh.style;
                        });
                    }
                    ed.format_paragraphs((q) => {
                        q.style = "Normal";
                        int nid = q.props.num_id;
                        int lvl = q.props.num_level;
                        q.props = new ParaProps();
                        q.props.num_id = nid;
                        q.props.num_level = lvl;
                    });
                    view.pending = null;
                    break;
                case "font-dialog":
                    WriteDialogs.font(r);
                    break;
                case "paragraph-dialog":
                    WriteDialogs.paragraph(r);
                    break;
                case "align":
                    Write.Align a = sp == "center" ? Write.Align.CENTER : (sp == "right" ? Write.Align.RIGHT : (sp == "justify" ? Write.Align.JUSTIFY : Write.Align.LEFT));
                    var cell_img = view.selected_obj;
                    if (cell_img != null && cell_img.item is FloatingInline && ((FloatingInline) cell_img.item).floating()) {
                        ed.checkpoint(_("Align Object"));
                        var fo = (FloatingInline) cell_img.item;
                        fo.halign = a == Write.Align.CENTER ? HAlignObj.CENTER : (a == Write.Align.RIGHT ? HAlignObj.RIGHT : HAlignObj.LEFT);
                        cell_img.para.touch();
                        ed.changed();
                        break;
                    }
                    para(r, _("Alignment"), (q) => q.props.align = a);
                    break;
                case "line-spacing":
                    double ls = double.parse(sp);
                    para(r, _("Line Spacing"), (q) => {
                        q.props.line = ls;
                        q.props.line_rule = LineRule.AUTO;
                    });
                    break;
                case "space-before":
                    para(r, _("Spacing"), (q) => {
                        var pp = doc.styles.resolve_para(q);
                        q.props.space_before = (pp.space_before.is_nan() || pp.space_before < 1) ? 12 : 0;
                    });
                    break;
                case "space-after":
                    para(r, _("Spacing"), (q) => {
                        var pp = doc.styles.resolve_para(q);
                        q.props.space_after = (pp.space_after.is_nan() || pp.space_after < 1) ? 8 : 0;
                    });
                    break;
                case "indent-more":
                    if (!r.editable()) break;
                    ed.checkpoint(_("Indent"));
                    ed.change_level(1);
                    break;
                case "indent-less":
                    if (!r.editable()) break;
                    ed.checkpoint(_("Indent"));
                    ed.change_level(-1);
                    break;
                case "bullets":
                    if (!r.editable()) break;
                    ed.checkpoint(_("Bullets"));
                    ed.toggle_list(false);
                    break;
                case "numbering":
                    if (!r.editable()) break;
                    ed.checkpoint(_("Numbering"));
                    ed.toggle_list(true);
                    break;
                case "multilevel":
                    WriteDialogs.list_gallery(r);
                    break;
                case "restart-numbering":
                    ed.checkpoint(_("Restart Numbering"));
                    ed.restart_numbering();
                    break;
                case "style":
                    if (!r.editable()) break;
                    ed.checkpoint(_("Style"));
                    ed.set_style(sp);
                    break;
                case "styles-pane":
                    r.show_right("styles");
                    break;
                case "new-style":
                    WriteDialogs.style_editor(r, null);
                    break;
                case "modify-style":
                    WriteDialogs.style_editor(r, doc.styles.get(ed.focus.para.style));
                    break;
                case "manage-styles":
                    r.show_right("styles");
                    break;
                case "style-set":
                    ed.checkpoint(_("Style Set"));
                    StyleSets.apply(doc, sp);
                    r.touch_all();
                    r.fbar.set_styles(doc);
                    break;
                case "change-case":
                    if (!r.editable() || !ed.has_selection) break;
                    ed.checkpoint(_("Change Case"));
                    Pos a, b;
                    ed.ordered(out a, out b);
                    foreach (var q in Story.between(doc, a, b)) {
                        int s0 = q == a.para ? a.offset : 0;
                        int e0 = q == b.para ? b.offset : q.length;
                        bool start = true;
                        q.for_range(s0, e0, (it) => {
                            var tr = it as TextRun;
                            if (tr == null) return;
                            tr.text = change_case(tr.text, sp, ref start);
                        });
                        q.touch();
                    }
                    ed.select(a, b);
                    ed.changed();
                    break;
                case "page-break":
                    if (!r.editable()) break;
                    ed.checkpoint(_("Page Break"));
                    ed.insert_inline(new Break(BreakKind.PAGE));
                    break;
                case "column-break":
                    if (!r.editable()) break;
                    ed.checkpoint(_("Column Break"));
                    ed.insert_inline(new Break(BreakKind.COLUMN));
                    break;
                case "section-break":
                    section_break(r, sp);
                    break;
                case "table-dialog":
                    WriteDialogs.insert_table(r);
                    break;
                case "picture":
                    WriteDialogs.pick_picture(r);
                    break;
                case "shape":
                    ShapeKind k = ShapeKind.RECT;
                    switch (sp) {
                        case "round": k = ShapeKind.ROUND_RECT; break;
                        case "ellipse": k = ShapeKind.ELLIPSE; break;
                        case "line": k = ShapeKind.LINE; break;
                        case "arrow": k = ShapeKind.ARROW; break;
                        case "triangle": k = ShapeKind.TRIANGLE; break;
                        default: break;
                    }
                    r.insert_shape(k);
                    break;
                case "textbox":
                    r.insert_shape(ShapeKind.TEXT_BOX);
                    break;
                case "equation-gallery":
                    WriteDialogs.equation_gallery(r);
                    break;
                case "wordart":
                    WriteDialogs.wordart(r);
                    break;
                case "chart":
                    WriteDialogs.chart(r);
                    break;
                case "equation":
                    r.insert_equation.begin(true);
                    break;
                case "equation-inline":
                    r.insert_equation.begin(false);
                    break;
                case "symbol":
                    WriteDialogs.symbol(r);
                    break;
                case "footnote":
                    r.insert_note(NoteKind.FOOTNOTE);
                    break;
                case "endnote":
                    r.insert_note(NoteKind.ENDNOTE);
                    break;
                case "new-comment":
                    r.insert_comment();
                    break;
                case "delete-comment":
                    if (view.active_comment != null) r.delete_comment(view.active_comment);
                    break;
                case "resolve-comment":
                    if (view.active_comment != null) {
                        var c = doc.find_comment(view.active_comment);
                        if (c != null) {
                            ed.checkpoint(_("Resolve Comment"));
                            c.done = !c.done;
                            ed.changed();
                            r.comments_pane.refresh();
                        }
                    }
                    break;
                case "comment-reply":
                    if (view.active_comment != null) r.comments_pane.reply(view.active_comment);
                    break;
                case "next-comment":
                case "prev-comment":
                    var ids = r.comment_order();
                    if (ids.size == 0) {
                        r.toast(_("There are no comments."));
                        break;
                    }
                    int ci = view.active_comment != null ? ids.index_of(view.active_comment) : -1;
                    ci = name == "next-comment" ? (ci + 1) % ids.size : (ci <= 0 ? ids.size - 1 : ci - 1);
                    r.goto_comment(ids[ci]);
                    r.show_right("comments");
                    r.comments_pane.focus_comment(ids[ci]);
                    break;
                case "comments-pane":
                    view.show_comments = true;
                    r.show_right("comments");
                    view.relayout_now();
                    break;
                case "bookmark":
                    WriteDialogs.bookmark(r);
                    break;
                case "link":
                    WriteDialogs.hyperlink(r);
                    break;
                case "remove-link":
                    if (!r.editable()) break;
                    Pos a, b;
                    if (!ed.has_selection) {
                        var it = ed.focus.para.inline_at(ed.focus.offset);
                        if (it != null && it.props.link != null) {
                            int off = ed.focus.para.offset_of(it);
                            ed.select(new Pos(ed.focus.para, off), new Pos(ed.focus.para, off + it.length));
                        }
                    }
                    ed.checkpoint(_("Remove Link"));
                    ed.format_chars((c) => {
                        c.link = null;
                        if (c.style == "Hyperlink") c.style = null;
                    });
                    ed.ordered(out a, out b);
                    ed.set_caret(b);
                    break;
                case "cross-reference":
                    WriteDialogs.cross_reference(r);
                    break;
                case "caption":
                    WriteDialogs.caption(r);
                    break;
                case "field":
                    WriteDialogs.field(r);
                    break;
                case "date-time":
                    WriteDialogs.date_time(r);
                    break;
                case "page-number":
                    WriteDialogs.page_numbers(r, sp);
                    break;
                case "toc":
                    insert_block_field(r, FieldUpdater.make_toc(3));
                    break;
                case "tof":
                    insert_block_field(r, new FieldBlock("TOC \\h \\z \\c \"Figure\""));
                    break;
                case "index":
                    insert_block_field(r, new FieldBlock("INDEX \\e \"\t\" \\h \"A\" \\c \"2\""));
                    break;
                case "bibliography":
                    insert_block_field(r, new FieldBlock("BIBLIOGRAPHY"));
                    break;
                case "index-entry":
                    WriteDialogs.index_entry(r);
                    break;
                case "citation":
                    WriteDialogs.citation(r);
                    break;
                case "sources":
                    WriteDialogs.sources(r);
                    break;
                case "bib-style":
                    ed.checkpoint(_("Bibliography Style"));
                    doc.bib_style = sp;
                    r.update_fields();
                    break;
                case "header":
                case "footer":
                    int pg = view.line_for(ed.focus) != null ? view.line_for(ed.focus).page : view.visible_page();
                    if (view.mode != ViewMode.PRINT) r.set_view_mode("print");
                    view.enter_header(pg, name == "header");
                    break;
                case "watermark":
                    WriteDialogs.watermark(r);
                    break;
                case "dropcap":
                    WriteDialogs.dropcap(r);
                    break;
                case "checkbox-field":
                case "text-field":
                case "dropdown-field":
                    var ff = new FormField(name == "checkbox-field" ? FormKind.CHECKBOX : (name == "text-field" ? FormKind.TEXT : FormKind.DROPDOWN));
                    if (ff.kind == FormKind.DROPDOWN) ff.options = { _("Choose an item.") };
                    if (ff.kind == FormKind.TEXT) ff.placeholder = _("Click to enter text.");
                    ed.checkpoint(_("Insert Form Field"));
                    ed.insert_inline(ff);
                    break;
                case "page-setup":
                    WriteDialogs.page_setup(r);
                    break;
                case "columns":
                    WriteDialogs.columns(r);
                    break;
                case "borders":
                    WriteDialogs.borders(r);
                    break;
                case "page-color":
                    WriteDialogs.page_color(r);
                    break;
                case "page-borders":
                    WriteDialogs.page_borders(r);
                    break;
                case "orientation":
                    ed.checkpoint(_("Orientation"));
                    doc.section_for(ed.focus.para).set_orientation(sp == "landscape");
                    r.touch_all();
                    break;
                case "hyphenation":
                    ed.checkpoint(_("Hyphenation"));
                    doc.hyphenate = !doc.hyphenate;
                    view.opts.hyphenate = doc.hyphenate;
                    if (doc.hyphenate && !Hyphenator.get_default().available(doc.lang)) r.toast(_("No hyphenation patterns are installed for this language."));
                    view.engine.invalidate();
                    r.touch_all();
                    break;
                case "line-numbers":
                    ed.checkpoint(_("Line Numbers"));
                    var ln = doc.section_for(ed.focus.para);
                    ln.line_numbers = !ln.line_numbers;
                    r.touch_all();
                    break;
                case "spelling":
                    r.check_pane.start_spelling();
                    r.show_right("check");
                    break;
                case "thesaurus":
                    int s0, e0;
                    ed.word_at(ed.focus, out s0, out e0);
                    WriteDialogs.thesaurus(r, ed.has_selection ? ed.selected_text() : usub(ed.focus.para.text(), s0, e0));
                    break;
                case "word-count":
                    WriteDialogs.word_count(r);
                    break;
                case "language":
                    WriteDialogs.language(r);
                    break;
                case "track-changes":
                    if (doc.protection.enforced && doc.protection.kind == ProtectKind.TRACKED) {
                        r.toast(_("The document is protected: changes are always tracked."));
                        break;
                    }
                    doc.track_changes = !doc.track_changes;
                    r.modified = true;
                    r.title_changed();
                    r.update_status();
                    r.state_changed();
                    break;
                case "accept":
                    r.resolve_current(true);
                    break;
                case "reject":
                    r.resolve_current(false);
                    break;
                case "accept-all":
                case "reject-all":
                    ed.checkpoint(name == "accept-all" ? _("Accept All Changes") : _("Reject All Changes"));
                    int n = Review.resolve_all(doc, name == "accept-all");
                    r.touch_all();
                    r.toast(ngettext("%d change resolved", "%d changes resolved", n).printf(n));
                    r.review_pane.refresh();
                    break;
                case "next-change":
                    r.goto_revision(1);
                    break;
                case "prev-change":
                    r.goto_revision(-1);
                    break;
                case "review-pane":
                    r.show_right("review");
                    break;
                case "markup":
                    switch (sp) {
                        case "simple": view.opts.markup = ViewMarkup.SIMPLE; break;
                        case "none": view.opts.markup = ViewMarkup.FINAL; break;
                        case "original": view.opts.markup = ViewMarkup.ORIGINAL; break;
                        default: view.opts.markup = ViewMarkup.ALL; break;
                    }
                    view.engine.invalidate();
                    view.relayout_now();
                    r.state_changed();
                    break;
                case "compare":
                    WriteDialogs.compare(r, false);
                    break;
                case "combine":
                    WriteDialogs.compare(r, true);
                    break;
                case "protect":
                    WriteDialogs.protect(r);
                    break;
                case "accessibility":
                    r.check_pane.start_accessibility();
                    r.show_right("check");
                    break;
                case "live-share":
                    WriteDialogs.live_share(r);
                    break;
                case "run-script":
                    r.run_script(sp);
                    break;
                case "script-new":
                    WriteDialogs.script_editor(r, null);
                    break;
                case "live-host":
                    try {
                        r.start_live_host();
                        r.view.get_clipboard().set_text(r.live.link);
                        r.toast(_("Live session started. The link is on the clipboard."));
                    } catch (Error e) {
                        r.toast(e.message);
                    }
                    break;
                case "live-join":
                    r.join_live.begin(sp, (o, res) => {
                        try {
                            r.join_live.end(res);
                            r.toast(_("Joined the live document."));
                        } catch (Error e) {
                            r.toast(e.message);
                        }
                    });
                    break;
                case "live-folder-start":
                case "live-folder-join":
                    try {
                        r.start_live_folder(Path.build_filename(sp, ".write-live"), name == "live-folder-start");
                    } catch (Error e) {
                        r.toast(e.message);
                    }
                    break;
                case "live-stop":
                    r.stop_live();
                    break;
                case "translate":
                    WriteDialogs.translate(r);
                    break;
                case "dictate":
                    Dictation.toggle(r);
                    break;
                case "read-aloud":
                    ReadAloud.toggle(r);
                    break;
                case "merge-recipients":
                    WriteDialogs.merge_recipients(r);
                    break;
                case "merge-field":
                    WriteDialogs.merge_field(r);
                    break;
                case "merge-preview":
                    if (r.merge_ds == null || r.merge_ds.records.size == 0) {
                        r.toast(_("Select recipients first."));
                        break;
                    }
                    r.merge_preview = !r.merge_preview;
                    view.engine.merge_record = r.merge_preview ? r.merge_ds.records[r.merge_index] : null;
                    r.touch_all();
                    r.update_status();
                    break;
                case "merge-next":
                case "merge-prev":
                    if (r.merge_ds == null || r.merge_ds.records.size == 0) break;
                    r.merge_index = (r.merge_index + (name == "merge-next" ? 1 : -1) + r.merge_ds.records.size) % r.merge_ds.records.size;
                    if (r.merge_preview) view.engine.merge_record = r.merge_ds.records[r.merge_index];
                    r.touch_all();
                    r.update_status();
                    break;
                case "merge-finish":
                    WriteFiles.finish_merge.begin(r, sp);
                    break;
                case "envelopes":
                    WriteDialogs.envelopes(r);
                    break;
                case "labels":
                    WriteDialogs.labels(r);
                    break;
                case "table-op":
                    if (!r.editable()) break;
                    ed.checkpoint(_("Table"));
                    if (!ed.table_op(sp)) r.toast(_("Place the cursor in a table first."));
                    break;
                case "table-sort":
                    WriteDialogs.sort_table(r);
                    break;
                case "table-formula":
                    WriteDialogs.table_formula(r);
                    break;
                case "table-properties":
                    WriteDialogs.table_properties(r);
                    break;
                case "table-style":
                    var t = ed.table_at(ed.focus);
                    if (t == null) break;
                    ed.checkpoint(_("Table Style"));
                    t.style = sp;
                    if (sp != "PlainTable") {
                        t.border_top = null;
                        t.border_bottom = null;
                        t.border_left = null;
                        t.border_right = null;
                        t.border_h = null;
                        t.border_v = null;
                    }
                    r.touch_all();
                    break;
                case "text-to-table":
                    WriteDialogs.text_to_table(r);
                    break;
                case "table-to-text":
                    var tt = ed.table_at(ed.focus);
                    if (tt == null || tt.parent == null) break;
                    ed.checkpoint(_("Convert Table to Text"));
                    var list = tt.parent;
                    int ti = list.items.index_of(tt);
                    list.remove_at(ti);
                    foreach (var row in tt.rows) {
                        var np = new Paragraph();
                        for (int i = 0; i < row.cells.size; i++) {
                            if (i > 0) np.inlines.add(new Tab());
                            var cp = row.cells[i].blocks.first_paragraph();
                            if (cp != null) foreach (var it in cp.inlines) np.inlines.add(it.copy());
                        }
                        np.normalize();
                        list.insert(ti++, np);
                    }
                    ed.set_caret(new Pos((Paragraph) list[ti - 1], 0));
                    ed.changed();
                    break;
                case "macro-record":
                    if (!r.recording) {
                        r.macro_steps.clear();
                        r.recording = true;
                        r.toast(_("Recording a macro. Use Stop Recording when you are done."));
                    } else {
                        r.recording = false;
                        WriteDialogs.save_macro(r);
                    }
                    r.update_status();
                    r.state_changed();
                    break;
                case "macro-run":
                case "macros":
                    WriteDialogs.macros(r);
                    break;
                case "autocorrect":
                    WriteDialogs.autocorrect(r);
                    break;
                case "update-fields":
                case "update-toc":
                    ed.checkpoint(_("Update Fields"));
                    r.update_fields();
                    break;
                case "navigation":
                    r.show_left(!r.sidebar_shown());
                    break;
                case "ruler":
                    r.ruler_rev.reveal_child = !r.ruler_rev.reveal_child;
                    if (r.settings != null) r.settings.set_boolean("show-ruler", r.ruler_rev.reveal_child);
                    r.state_changed();
                    break;
                case "marks":
                    view.opts.formatting_marks = !view.opts.formatting_marks;
                    view.queue_draw();
                    r.state_changed();
                    break;
                case "view":
                    r.set_view_mode(sp);
                    break;
                case "zoom":
                    r.set_zoom_named(sp);
                    break;
                case "zoom-in":
                    view.set_zoom(view.zoom * 1.1);
                    break;
                case "zoom-out":
                    view.set_zoom(view.zoom / 1.1);
                    break;
                case "undo":
                    ed.do_undo();
                    break;
                case "redo":
                    ed.do_redo();
                    break;
                case "cut":
                    r.copy_to_clipboard(true);
                    break;
                case "copy":
                    r.copy_to_clipboard(false);
                    break;
                case "paste":
                    r.paste.begin("keep");
                    break;
                case "paste-text":
                    r.paste.begin("text");
                    break;
                case "paste-special":
                    WriteDialogs.paste_special(r);
                    break;
                case "select-all":
                    var all = Story.paragraphs(Story.root_of(doc, ed.focus.para));
                    if (all.size > 0) ed.select(new Pos(all[0], 0), new Pos(all[all.size - 1], all[all.size - 1].length));
                    break;
                case "find":
                    r.nav.focus_search();
                    break;
                case "find-replace":
                    WriteDialogs.find_replace(r);
                    break;
                case "goto":
                    WriteDialogs.go_to(r);
                    break;
                case "format-painter":
                    if (r.painter_props == null) {
                        r.painter_props = ed.focus.para.props_at(ed.focus.offset);
                        r.painter_props.link = null;
                        r.painter_para = ed.focus.para.props.copy();
                        r.painter_style = ed.focus.para.style;
                        r.fbar.set_painter(true);
                    } else {
                        r.painter_props = null;
                        r.fbar.set_painter(false);
                    }
                    break;
                case "properties":
                    WriteDialogs.doc_properties(r);
                    break;
                case "versions":
                    WriteDialogs.versions(r);
                    break;
                case "insert-file":
                    WriteDialogs.insert_file(r);
                    break;
                case "reveal-formatting":
                    WriteDialogs.reveal_formatting(r);
                    break;
                default:
                    break;
            }
        }

        private static string change_case(string t, string mode, ref bool start) {
            var sb = new StringBuilder();
            unichar c;
            int i = 0;
            while (t.get_next_char(ref i, out c)) {
                switch (mode) {
                    case "upper": sb.append_unichar(c.toupper()); break;
                    case "lower": sb.append_unichar(c.tolower()); break;
                    case "toggle": sb.append_unichar(c.isupper() ? c.tolower() : c.toupper()); break;
                    case "title":
                        sb.append_unichar(start ? c.toupper() : c.tolower());
                        break;
                    default:
                        sb.append_unichar(start && c.isalpha() ? c.toupper() : (c.isalpha() ? c.tolower() : c));
                        break;
                }
                if (mode == "title") start = c.isspace();
                else if (mode != "upper" && mode != "lower" && mode != "toggle") {
                    if (c == '.' || c == '!' || c == '?') start = true;
                    else if (c.isalpha()) start = false;
                }
            }
            return sb.str;
        }
    }

    public class StyleSets : Object {
        public static string[] names() {
            return { "default", "classic", "modern", "elegant", "minimal", "technical" };
        }

        public static string label(string id) {
            switch (id) {
                case "classic": return _("Classic");
                case "modern": return _("Modern");
                case "elegant": return _("Elegant");
                case "minimal": return _("Minimal");
                case "technical": return _("Technical");
                default: return _("Default");
            }
        }

        public static void apply(Write.Document doc, string id) {
            string body = "Liberation Serif", head = "Liberation Sans", color = "#2f5496";
            double size = 11;
            switch (id) {
                case "classic": body = "Liberation Serif"; head = "Liberation Serif"; color = "#000000"; size = 12; break;
                case "modern": body = "Liberation Sans"; head = "Liberation Sans"; color = "#0b7a75"; size = 10.5; break;
                case "elegant": body = "DejaVu Serif"; head = "DejaVu Serif"; color = "#7a3e65"; size = 11; break;
                case "minimal": body = "Liberation Sans"; head = "Liberation Sans"; color = "#404040"; size = 10.5; break;
                case "technical": body = "DejaVu Sans"; head = "DejaVu Sans Mono"; color = "#1f5f99"; size = 10; break;
                default: break;
            }
            doc.styles.default_char.font = body;
            doc.styles.default_char.size = size;
            for (int i = 1; i <= 9; i++) {
                var h = doc.styles.get("Heading%d".printf(i));
                if (h == null) continue;
                h.chr.font = head;
                h.chr.color = color;
            }
            var t = doc.styles.get("Title");
            if (t != null) {
                t.chr.font = head;
                t.chr.color = id == "default" ? null : color;
            }
            doc.styles.touch();
        }
    }

    public class DesktopServices : Object {
        public static bool present(string bus_name) {
            try {
                var connection = Bus.get_sync(BusType.SESSION);
                var reply = connection.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "NameHasOwner",
                    new Variant("(s)", bus_name), new VariantType("(b)"), DBusCallFlags.NONE, 2000, null);
                bool owned;
                reply.get("(b)", out owned);
                if (owned) return true;
                var act = connection.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "ListActivatableNames",
                    null, new VariantType("(as)"), DBusCallFlags.NONE, 2000, null);
                var names = act.get_child_value(0);
                for (size_t i = 0; i < names.n_children(); i++) if (names.get_child_value(i).get_string() == bus_name) return true;
            } catch (Error e) {
            }
            return false;
        }

        public static string language(WriteRichEditor r) {
            string l = r.doc.lang != "" ? r.doc.lang : Write.Hyphenator.default_lang();
            int u = l.index_of_char('_');
            if (u < 0) u = l.index_of_char('-');
            return u > 0 ? l.substring(0, u) : l;
        }
    }

    public class Dictation : Object {
        public const string BUS_NAME = "dev.sinty.Dictation";
        private static Gst.Pipeline? pipeline = null;
        private static string chunk = "";
        private static uint rotate_id = 0;
        private static weak WriteRichEditor? editor = null;
        private static int pending = 0;

        public static bool active() {
            return pipeline != null;
        }

        private static string? source() {
            string? v = Environment.get_variable("SINGULARITY_WRITE_AUDIO_SOURCE");
            if (v != null && v.strip() != "") return v.strip();
            foreach (string s in new string[] { "autoaudiosrc", "pipewiresrc", "pulsesrc" }) if (Gst.ElementFactory.find(s) != null) return s;
            return null;
        }

        private static bool start_chunk() {
            string? src = source();
            if (src == null || Gst.ElementFactory.find("wavenc") == null) return false;
            chunk = Path.build_filename(Environment.get_tmp_dir(), "write-dictation-%s.wav".printf(Uuid.string_random()));
            try {
                pipeline = (Gst.Pipeline) Gst.parse_launch("%s ! queue ! audioconvert ! audioresample ! audio/x-raw,format=S16LE,rate=16000,channels=1 ! wavenc ! filesink name=sink".printf(src));
            } catch (Error e) {
                pipeline = null;
                return false;
            }
            pipeline.get_by_name("sink").set("location", chunk);
            if (pipeline.set_state(Gst.State.PLAYING) == Gst.StateChangeReturn.FAILURE) {
                pipeline.set_state(Gst.State.NULL);
                pipeline = null;
                return false;
            }
            return true;
        }

        private static string finish_chunk() {
            if (pipeline == null) return "";
            pipeline.send_event(new Gst.Event.eos());
            var bus = pipeline.get_bus();
            bus.timed_pop_filtered(2 * Gst.SECOND, Gst.MessageType.EOS | Gst.MessageType.ERROR);
            pipeline.set_state(Gst.State.NULL);
            pipeline = null;
            return chunk;
        }

        private static async void transcribe(string path, string lang) {
            pending++;
            try {
                var connection = yield Bus.get(BusType.SESSION);
                var reply = yield connection.call(BUS_NAME, "/dev/sinty/Dictation", "dev.sinty.Dictation", "TranscribeFile",
                    new Variant("(ss)", path, lang), new VariantType("(s)"), DBusCallFlags.NONE, 10 * 60 * 1000, null);
                string text;
                reply.get("(s)", out text);
                text = text.strip();
                var r = editor;
                if (text != "" && r != null) {
                    r.ed.checkpoint(_("Dictation"), true);
                    var props = r.view.pending ?? r.ed.props_for_insert();
                    int off = r.ed.focus.offset;
                    string before = r.ed.focus.para.plain_text();
                    bool space = off > 0 && !before.substring(0, before.index_of_nth_char(off)).has_suffix(" ");
                    r.ed.insert_text((space ? " " : "") + text, props);
                }
            } catch (Error e) {
                DBusError.strip_remote_error(e);
                if (editor != null) editor.toast(_("Dictation failed: %s").printf(e.message));
            } finally {
                FileUtils.unlink(path);
                pending--;
            }
        }

        public static void toggle(WriteRichEditor r) {
            if (pipeline != null) {
                if (rotate_id != 0) {
                    Source.remove(rotate_id);
                    rotate_id = 0;
                }
                string path = finish_chunk();
                if (path != "") transcribe.begin(path, DesktopServices.language(r));
                r.toast(_("Dictation stopped."));
                r.update_status();
                return;
            }
            if (!DesktopServices.present(BUS_NAME)) {
                r.toast(_("The dictation service of the desktop is not available."));
                return;
            }
            unowned string[]? args = null;
            Gst.init(ref args);
            editor = r;
            if (!start_chunk()) {
                r.toast(_("The microphone could not be opened."));
                return;
            }
            string lang = DesktopServices.language(r);
            rotate_id = Timeout.add_seconds(6, () => {
                string path = finish_chunk();
                if (path != "") transcribe.begin(path, lang);
                if (!start_chunk()) {
                    rotate_id = 0;
                    return false;
                }
                return true;
            });
            r.toast(_("Dictation started. Speak now; choose Dictate again to stop."));
            r.update_status();
        }
    }

    public class ReadAloud : Object {
        private static Subprocess? proc = null;

        public static string? program() {
            string? env = Environment.get_variable("SINGULARITY_TTS");
            if (env != null && env != "") return env;
            foreach (string p in new string[] { "spd-say", "espeak-ng", "espeak", "festival" }) {
                string? path = Environment.find_program_in_path(p);
                if (path != null) return path;
            }
            return null;
        }

        public static void toggle(WriteRichEditor r) {
            if (proc != null) {
                proc.force_exit();
                proc = null;
                return;
            }
            string? prog = program();
            if (prog == null) {
                r.toast(_("No speech synthesizer is installed (for example speech-dispatcher or espeak-ng)."));
                return;
            }
            string text;
            if (r.ed.has_selection) text = r.ed.selected_text();
            else {
                var sb = new StringBuilder();
                bool on = false;
                foreach (var p in Story.paragraphs(r.doc.body)) {
                    if (p == r.ed.focus.para) on = true;
                    if (on) sb.append(p.plain_text()).append("\n");
                }
                text = sb.str;
            }
            if (text.strip() == "") return;
            string name = Path.get_basename(prog);
            string[] argv;
            if (name == "spd-say") argv = { prog, "-w", "-e" };
            else if (name == "festival") argv = { prog, "--tts" };
            else argv = { prog, "--stdin" };
            try {
                proc = new Subprocess.newv(argv, SubprocessFlags.STDIN_PIPE | SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE);
                var input = proc.get_stdin_pipe();
                input.write_all(text.data, null);
                input.close();
                proc.wait_async.begin(null, (o, res) => {
                    proc = null;
                });
            } catch (Error e) {
                r.toast(e.message);
                proc = null;
            }
        }
    }
}
