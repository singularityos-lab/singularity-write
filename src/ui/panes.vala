using Gtk;
using Write;

namespace Singularity.Apps {

    public delegate void WritePaneClose();

    public class WritePaneHeader : Gtk.Box {
        public WritePaneHeader(string title, owned WritePaneClose? close) {
            Object(orientation: Orientation.HORIZONTAL, spacing: 6);
            margin_start = 12;
            margin_end = 6;
            margin_top = 8;
            margin_bottom = 4;
            var l = new Label(title);
            l.add_css_class("heading");
            l.halign = Gtk.Align.START;
            l.hexpand = true;
            append(l);
            if (close != null) {
                var b = new Button.from_icon_name("window-close-symbolic");
                b.add_css_class("flat");
                b.tooltip_text = _("Close");
                b.clicked.connect(() => close());
                append(b);
            }
        }
    }

    public class WriteNavigationPane : Singularity.Widgets.AppSidebar {
        private weak WriteRichEditor r;
        private string query = "";
        public signal void focus_search_requested(string seed);
        public Gtk.Stack stack;
        private Gtk.Stack actions;
        private Gtk.ListBox headings;
        private Singularity.Widgets.WelcomePage headings_empty;
        private Singularity.Widgets.StatusPage no_results;
        public signal void clear_search_requested();
        private Gtk.FlowBox pages;
        private Gtk.ListBox results;
        private Gtk.Label results_info;
        public Singularity.Widgets.SidebarTabs tabs;
        private string last_page = "headings";
        private uint refresh_id = 0;
        private Gee.ArrayList<Paragraph> heading_paras = new Gee.ArrayList<Paragraph>();
        private Gee.ArrayList<Write.Match> matches = new Gee.ArrayList<Write.Match>();

        public WriteNavigationPane(WriteRichEditor r) {
            base(300);
            this.r = r;
            add_css_class("write-nav-sidebar");
            tabs = new Singularity.Widgets.SidebarTabs();
            tabs.add_option("headings", _("Outline"));
            tabs.add_option("pages", _("Pages"));
            tabs.add_option("comments", _("Comments"));
            tabs.add_option("review", _("Changes"));
            tabs.selected.connect((n) => show_page(n));
            prepend(tabs);
            stack = new Gtk.Stack();
            stack.vhomogeneous = false;
            stack.hhomogeneous = true;
            stack.transition_type = StackTransitionType.CROSSFADE;
            stack.transition_duration = Singularity.Motion.Duration.SMALL;
            var hbox = new Box(Orientation.VERTICAL, 0);
            headings = new Gtk.ListBox();
            headings.add_css_class("navigation-sidebar");
            headings.add_css_class("write-outline");
            headings.selection_mode = SelectionMode.SINGLE;
            headings.row_activated.connect((row) => {
                int i = row.get_index();
                if (i >= 0 && i < heading_paras.size) {
                    r.view.scroll_to_para(heading_paras[i]);
                    r.view.grab_focus();
                }
            });
            hbox.append(headings);
            headings_empty = section_page("write-outline", _("Outline"), _("This document has no headings yet. Headings build the outline and the table of contents."));
            headings_empty.add_action("write-outline", _("Add Heading"), _("Make the current paragraph a Heading 1"), () => {
                r.run("style", new Variant.string("Heading1"));
                r.view.grab_focus();
            });
            headings_empty.add_action("x-office-document-template", _("Browse Styles"), _("See every paragraph style in the Styles panel"), () => r.run("styles-pane", null));
            hbox.append(headings_empty);
            stack.add_named(hbox, "headings");
            pages = new Gtk.FlowBox();
            pages.max_children_per_line = 2;
            pages.min_children_per_line = 2;
            pages.homogeneous = true;
            pages.selection_mode = SelectionMode.NONE;
            pages.row_spacing = 8;
            pages.column_spacing = 8;
            pages.margin_top = 4;
            pages.valign = Gtk.Align.START;
            stack.add_named(pages, "pages");
            var rbox = new Box(Orientation.VERTICAL, 4);
            results_info = new Label("");
            results_info.add_css_class("dim-label");
            results_info.add_css_class("caption");
            results_info.margin_start = 8;
            results_info.margin_top = 2;
            results_info.halign = Gtk.Align.START;
            rbox.append(results_info);
            results = new Gtk.ListBox();
            results.add_css_class("navigation-sidebar");
            results.row_activated.connect((row) => {
                int i = row.get_index();
                if (i >= 0 && i < matches.size) select_match(matches[i]);
            });
            rbox.append(results);
            no_results = new Singularity.Widgets.StatusPage();
            no_results.icon_name = "system-search";
            no_results.title = _("No Results");
            no_results.description = _("Nothing in this document matches the search.");
            no_results.compact = true;
            no_results.margin_top = 24;
            var clear = new Button.with_label(_("Clear Search"));
            clear.add_css_class("pill");
            clear.halign = Gtk.Align.CENTER;
            clear.clicked.connect(() => clear_search_requested());
            no_results.child = clear;
            no_results.visible = false;
            rbox.append(no_results);
            stack.add_named(rbox, "results");
            box.append(stack);
            actions = new Gtk.Stack();
            actions.vhomogeneous = false;
            actions.add_css_class("write-sidebar-actions");
            actions.add_named(new Box(Orientation.HORIZONTAL, 0), "none");
            append(actions);
            tabs.set_active("headings");
            sync_actions();
        }

        public static Singularity.Widgets.WelcomePage section_page(string icon, string title, string subtitle) {
            var w = new Singularity.Widgets.WelcomePage();
            w.is_section = true;
            w.compact = true;
            w.embedded = true;
            w.app_icon_name = icon;
            w.title = title;
            w.subtitle = subtitle;
            w.margin_start = 4;
            w.margin_end = 4;
            w.valign = Gtk.Align.START;
            w.visible = false;
            return w;
        }

        public void add_page(string name, Gtk.Widget content, Gtk.Widget? bar) {
            stack.add_named(content, name);
            if (bar != null) {
                bar.add_css_class("sx-control-strip");
                actions.add_named(bar, name);
            }
        }

        public string page {
            owned get { return stack.visible_child_name == "results" ? last_page : (stack.visible_child_name ?? "headings"); }
        }

        public void show_page(string name) {
            last_page = name;
            if (tabs.active_option != name) tabs.set_active(name);
            stack.visible_child_name = name;
            switch (name) {
                case "pages": refresh_pages(); break;
                case "comments": r.comments_pane.refresh(); break;
                case "review": r.review_pane.refresh(); break;
                case "markdown": break;
                default: refresh(); break;
            }
            sync_actions();
            r.state_changed();
        }

        private void sync_actions() {
            string n = stack.visible_child_name ?? "";
            actions.visible_child_name = actions.get_child_by_name(n) != null ? n : "none";
            actions.visible = actions.visible_child_name != "none";
        }

        public void set_markdown(bool md) {
            tabs.visible = !md;
            if (md) {
                stack.visible_child_name = "markdown";
                sync_actions();
            } else if (stack.visible_child_name == "markdown") {
                show_page(last_page == "markdown" ? "headings" : last_page);
            }
        }

        public void focus_search() {
            focus_search_requested(r.ed.has_selection ? r.ed.selected_text() : "");
        }

        public void search_for(string q) {
            query = q;
            run_search();
            if (q != "") {
                if (!r.sidebar_shown()) r.show_left(true);
                stack.visible_child_name = "results";
            } else if (stack.visible_child_name == "results") {
                stack.visible_child_name = last_page;
            }
            sync_actions();
        }

        public void search_next() {
            next_result();
        }

        public void schedule_refresh() {
            if (refresh_id != 0) return;
            refresh_id = Timeout.add(400, () => {
                refresh_id = 0;
                refresh();
                return Source.REMOVE;
            });
        }

        public void refresh() {
            if (!r.sidebar_shown()) return;
            Widget? c;
            while ((c = headings.get_first_child()) != null) headings.remove(c);
            heading_paras.clear();
            foreach (var b in r.doc.body.items) {
                var p = b as Paragraph;
                if (p == null) continue;
                int lvl = r.doc.styles.outline_level(p);
                if (lvl < 0) continue;
                string text = p.plain_text().strip();
                if (text == "") continue;
                heading_paras.add(p);
                var row = new Gtk.ListBoxRow();
                var l = new Label(text);
                l.xalign = 0;
                l.ellipsize = Pango.EllipsizeMode.END;
                l.margin_start = 8 + lvl * 14;
                l.margin_top = 3;
                l.margin_bottom = 3;
                if (lvl == 0) l.add_css_class("heading");
                row.child = l;
                var para = p;
                var drag = new Gtk.DragSource();
                drag.actions = Gdk.DragAction.MOVE;
                drag.prepare.connect((x, y) => {
                    var v = Value(typeof(string));
                    v.set_string("heading:%d".printf(heading_paras.index_of(para)));
                    return new Gdk.ContentProvider.for_value(v);
                });
                row.add_controller(drag);
                var drop = new Gtk.DropTarget(typeof(string), Gdk.DragAction.MOVE);
                drop.drop.connect((val, x, y) => {
                    string s = val.get_string();
                    if (!s.has_prefix("heading:")) return false;
                    int from = int.parse(s.substring(8));
                    if (from < 0 || from >= heading_paras.size) return false;
                    r.ed.checkpoint(_("Move Heading"));
                    r.ed.move_heading_section(heading_paras[from], para);
                    return true;
                });
                row.add_controller(drop);
                var click = new Gtk.GestureClick();
                click.button = 3;
                click.pressed.connect((n, x, y) => heading_menu(row, para, x, y));
                row.add_controller(click);
                headings.append(row);
            }
            headings.visible = heading_paras.size > 0;
            headings_empty.visible = heading_paras.size == 0;
            highlight_current();
            if (stack.visible_child_name == "pages") refresh_pages();
        }

        private void heading_menu(Gtk.Widget row, Paragraph p, double x, double y) {
            var m = new Singularity.Widgets.ContextMenu(row);
            m.add_item(_("Promote"), "go-up-symbolic", () => {
                r.ed.checkpoint(_("Promote"));
                r.ed.promote(p, -1);
            });
            m.add_item(_("Demote"), "go-down-symbolic", () => {
                r.ed.checkpoint(_("Demote"));
                r.ed.promote(p, 1);
            });
            m.add_separator();
            m.add_item(_("Select Heading and Content"), "edit-select-all-symbolic", () => {
                var blocks = r.ed.heading_section(p);
                Paragraph? last = null;
                foreach (var b in blocks) if (b is Paragraph) last = (Paragraph) b;
                if (last != null) r.ed.select(new Pos(p, 0), new Pos(last, last.length));
            });
            m.add_item(_("Delete Heading and Content"), "edit-delete-symbolic", () => {
                r.ed.checkpoint(_("Delete Section"));
                var list = p.parent;
                foreach (var b in r.ed.heading_section(p)) list.items.remove(b);
                if (list.size == 0) list.add(new Paragraph());
                r.ed.set_caret(new Pos(list.first_paragraph(), 0));
                r.ed.changed();
            });
            m.add_item(_("New Heading After"), "list-add-symbolic", () => {
                r.ed.checkpoint(_("New Heading"));
                var list = p.parent;
                var blocks = r.ed.heading_section(p);
                int at = list.items.index_of(blocks[blocks.size - 1]) + 1;
                var np = new Paragraph(p.style);
                list.insert(at, np);
                r.ed.set_caret(new Pos(np, 0));
                r.ed.changed();
            });
            var rect = Gdk.Rectangle() { x = (int) x, y = (int) y, width = 1, height = 1 };
            m.set_pointing_to(rect);
            m.closed.connect(() => m.unparent());
            m.popup();
        }

        public void highlight_current() {
            if (heading_paras.size == 0) return;
            var all = r.doc.body.items;
            int cur_top = -1;
            var focus = r.ed.focus.para;
            Block top = focus;
            var root = Story.root_of(r.doc, focus);
            if (root != r.doc.body) return;
            foreach (var b in all) {
                if (b is Paragraph && heading_paras.contains((Paragraph) b)) cur_top = heading_paras.index_of((Paragraph) b);
                if (b == top) break;
                if (b is Table) {
                    bool inside = false;
                    foreach (var q in Story.paragraphs(((Table) b).rows[0].cells[0].blocks)) if (q == focus) inside = true;
                    if (inside) break;
                }
            }
            if (cur_top >= 0) {
                var row = headings.get_row_at_index(cur_top);
                if (row != null) headings.select_row(row);
            }
        }

        public void refresh_pages() {
            Widget? c;
            while ((c = pages.get_first_child()) != null) pages.remove(c);
            if (r.view.lay == null) return;
            int n = int.min(r.view.lay.pages.size, 120);
            for (int i = 0; i < n; i++) {
                var p = r.view.lay.pages[i];
                double sc = 100.0 / p.width;
                var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, (int) (p.width * sc), (int) (p.height * sc));
                var cr = new Cairo.Context(surface);
                cr.scale(sc, sc);
                var opts = r.view.opts.copy();
                opts.print = true;
                new Write.Renderer(r.doc, opts, r.view.engine.context()).draw_page(cr, p);
                surface.flush();
                var tex = texture_from(surface);
                var pic = new Gtk.Picture.for_paintable(tex);
                pic.can_shrink = false;
                pic.add_css_class("write-page-thumb");
                var box = new Box(Orientation.VERTICAL, 2);
                box.append(pic);
                var l = new Label(p.number_text);
                l.add_css_class("caption");
                box.append(l);
                var btn = new Gtk.Button();
                btn.child = box;
                btn.add_css_class("flat");
                int idx = i;
                btn.clicked.connect(() => r.view.scroll_to_page(idx));
                pages.append(btn);
            }
        }

        public static Gdk.Texture texture_from(Cairo.ImageSurface s) {
            int w = s.get_width();
            int h = s.get_height();
            int stride = s.get_stride();
            unowned uint8[] data = s.get_data();
            uint8[] copy = new uint8[stride * h];
            Memory.copy(copy, data, stride * h);
            var bytes = new Bytes.take((owned) copy);
            return new Gdk.MemoryTexture(w, h, Gdk.MemoryFormat.B8G8R8A8_PREMULTIPLIED, bytes, stride);
        }

        private void run_search() {
            Widget? c;
            while ((c = results.get_first_child()) != null) results.remove(c);
            matches.clear();
            string q = query;
            if (q == "") {
                results_info.label = "";
                return;
            }
            var o = new FindOptions();
            o.query = q;
            try {
                matches = Finder.find_all(r.doc, o);
            } catch (RegexError e) {
            }
            results_info.label = ngettext("%d result", "%d results", matches.size).printf(matches.size);
            results_info.visible = matches.size > 0;
            results.visible = matches.size > 0;
            no_results.visible = matches.size == 0;
            int shown = 0;
            foreach (var m in matches) {
                if (shown++ > 300) break;
                string t = m.para.plain_text();
                int s = int.max(0, m.start - 30);
                int e = int.min(t.char_count(), m.end + 40);
                string before = Markup.escape_text(usub(t, s, m.start));
                string hit = Markup.escape_text(usub(t, m.start, m.end));
                string after = Markup.escape_text(usub(t, m.end, e));
                var l = new Label(null);
                l.set_markup((s > 0 ? "\u2026" : "") + before + "<b>" + hit + "</b>" + after);
                l.wrap = true;
                l.xalign = 0;
                l.lines = 3;
                l.ellipsize = Pango.EllipsizeMode.END;
                l.margin_start = 8;
                l.margin_end = 8;
                l.margin_top = 4;
                l.margin_bottom = 4;
                results.append(l);
            }
            highlight_all();
        }

        private void highlight_all() {
            r.view.queue_draw();
        }

        private void select_match(Write.Match m) {
            r.ed.select(new Pos(m.para, m.start), new Pos(m.para, m.end));
            r.view.ensure_caret_visible();
        }

        private void next_result() {
            if (matches.size == 0) return;
            var order = Story.all(r.doc);
            int cur = order.index_of(r.ed.focus.para);
            foreach (var m in matches) {
                int mi = order.index_of(m.para);
                if (mi > cur || (mi == cur && m.start >= r.ed.focus.offset)) {
                    select_match(m);
                    return;
                }
            }
            select_match(matches[0]);
        }
    }

    public class WriteCommentsPane : Gtk.Box {
        private weak WriteRichEditor r;
        private Gtk.Box list;
        public Gtk.Box bar;
        private Gee.HashMap<string, Gtk.Widget> cards = new Gee.HashMap<string, Gtk.Widget>();

        public WriteCommentsPane(WriteRichEditor r) {
            Object(orientation: Orientation.VERTICAL, spacing: 6);
            this.r = r;
            add_css_class("write-sidebar-page");
            margin_top = 4;
            list = new Box(Orientation.VERTICAL, 8);
            list.margin_bottom = 10;
            append(list);
            bar = new Box(Orientation.HORIZONTAL, 6);
            var add = new Button.with_label(_("New Comment"));
            add.add_css_class("flat");
            add.tooltip_text = _("New Comment (Ctrl+Alt+M)");
            add.clicked.connect(() => r.insert_comment());
            bar.append(add);
            var sp = new Box(Orientation.HORIZONTAL, 0);
            sp.hexpand = true;
            bar.append(sp);
            var prev = new Button.from_icon_name("go-up-symbolic");
            prev.add_css_class("flat");
            prev.tooltip_text = _("Previous Comment");
            prev.clicked.connect(() => r.run("prev-comment", null));
            bar.append(prev);
            var next = new Button.from_icon_name("go-down-symbolic");
            next.add_css_class("flat");
            next.tooltip_text = _("Next Comment");
            next.clicked.connect(() => r.run("next-comment", null));
            bar.append(next);
        }

        public void refresh() {
            Widget? c;
            while ((c = list.get_first_child()) != null) list.remove(c);
            cards.clear();
            var order = r.comment_order();
            var roots = new Gee.ArrayList<Comment>();
            foreach (string id in order) {
                var cm = r.doc.find_comment(id);
                if (cm != null && cm.parent_id == null && !roots.contains(cm)) roots.add(cm);
            }
            foreach (var cm in r.doc.comments) if (cm.parent_id == null && !roots.contains(cm)) roots.add(cm);
            if (roots.size == 0) {
                var e = WriteNavigationPane.section_page("write-comments", _("Comments"), _("No comments yet. Comments stay next to the text they talk about."));
                e.add_action("write-comments", _("New Comment"), _("Comment on the selected text (Ctrl+Alt+M)"), () => r.insert_comment());
                e.visible = true;
                list.append(e);
                return;
            }
            foreach (var cm in roots) list.append(card(cm));
        }

        private Gtk.Widget card(Comment cm) {
            var box = new Box(Orientation.VERTICAL, 4);
            box.valign = Gtk.Align.START;
            box.vexpand = false;
            box.add_css_class("write-comment-card");
            if (cm.done) box.add_css_class("resolved");
            box.append(entry_for(cm));
            foreach (var reply in r.doc.comments) {
                if (reply.parent_id != cm.id) continue;
                var rb = entry_for(reply);
                rb.margin_start = 14;
                box.append(rb);
            }
            var bar = new Box(Orientation.HORIZONTAL, 4);
            var reply_b = new Button.with_label(_("Reply"));
            reply_b.add_css_class("flat");
            string id = cm.id;
            reply_b.clicked.connect(() => reply(id));
            bar.append(reply_b);
            var res = new Button.with_label(cm.done ? _("Reopen") : _("Resolve"));
            res.add_css_class("flat");
            res.clicked.connect(() => {
                r.ed.checkpoint(_("Resolve Comment"));
                cm.done = !cm.done;
                r.ed.changed();
                refresh();
            });
            bar.append(res);
            var del = new Button.from_icon_name("user-trash-symbolic");
            del.add_css_class("flat");
            del.tooltip_text = _("Delete comment");
            del.clicked.connect(() => r.delete_comment(id));
            bar.append(del);
            box.append(bar);
            var click = new Gtk.GestureClick();
            click.pressed.connect(() => {
                r.view.active_comment = id;
                r.goto_comment(id);
            });
            box.add_controller(click);
            cards[cm.id] = box;
            return box;
        }

        private Gtk.Widget entry_for(Comment cm) {
            var box = new Box(Orientation.VERTICAL, 2);
            var head = new Label(null);
            string date = cm.date.length >= 10 ? cm.date.substring(0, 10) : cm.date;
            head.set_markup("<b>%s</b>  <span size=\"small\" alpha=\"60%%\">%s</span>".printf(Markup.escape_text(cm.author), Markup.escape_text(date)));
            head.xalign = 0;
            box.append(head);
            var body = new Label(cm.text() != "" ? cm.text() : _("Empty comment"));
            body.wrap = true;
            body.wrap_mode = Pango.WrapMode.WORD_CHAR;
            body.xalign = 0;
            body.add_css_class("write-comment-text");
            if (cm.text() == "") body.add_css_class("dim-label");
            box.append(body);
            bool can_edit = !r.doc.protection.enforced || r.doc.protection.kind != ProtectKind.READ_ONLY;
            if (can_edit) {
                var dbl = new Gtk.GestureClick();
                dbl.pressed.connect((n, x, y) => {
                    if (n == 2) edit_comment(cm);
                });
                body.add_controller(dbl);
            }
            return box;
        }

        public void edit_comment(Comment cm) {
            var dlg = WriteDialogs.make(r, _("Edit Comment"), 420, 300);
            var tv = new Gtk.TextView();
            tv.wrap_mode = WrapMode.WORD_CHAR;
            tv.buffer.text = cm.text();
            tv.vexpand = true;
            tv.margin_start = 18;
            tv.margin_end = 18;
            tv.margin_top = 6;
            tv.margin_bottom = 12;
            tv.add_css_class("write-comment-editor");
            Singularity.Text.SpellIntegration.attach(tv);
            dlg.content_box.append(tv);
            bool saved = false;
            WriteDialogs.footer(dlg, _("Save"), () => {
                saved = true;
                save_one(cm, tv.buffer.text);
                refresh();
            });
            dlg.close_request.connect(() => {
                if (!saved && cm.text().strip() == "") r.delete_comment(cm.id);
                return false;
            });
            dlg.present();
            tv.grab_focus();
        }

        private void save_one(Comment cm, string t) {
            if (t == cm.text()) return;
            r.ed.checkpoint(_("Edit Comment"));
            cm.blocks.clear();
            foreach (string line in t.split("\n")) cm.blocks.add(new Paragraph.with_text(line, "CommentText"));
            r.modified = true;
            r.title_changed();
            r.view.queue_draw();
        }


        public void reply(string id) {
            r.ed.checkpoint(_("Reply"));
            string nid = r.doc.next_id().to_string();
            while (r.doc.find_comment(nid) != null) nid = r.doc.next_id().to_string();
            var c = new Comment(nid, r.ed.author);
            c.parent_id = id;
            c.blocks.add(new Paragraph("CommentText"));
            r.doc.comments.add(c);
            r.ed.changed();
            refresh();
            focus_comment(nid, true);
        }

        public void focus_comment(string id, bool edit = false) {
            if (edit) {
                var cm = r.doc.find_comment(id);
                if (cm != null) edit_comment(cm);
            }
            var card = cards[id];
            if (card != null) {
                foreach (var c in cards.values) c.remove_css_class("active");
                card.add_css_class("active");
            }
        }
    }

    public class WriteReviewPane : Gtk.Box {
        private weak WriteRichEditor r;
        private Gtk.ListBox list;
        private Singularity.Widgets.WelcomePage empty;
        public Gtk.Box bar;
        private Gtk.Label summary;
        private Gee.ArrayList<RevisionRef> revs = new Gee.ArrayList<RevisionRef>();

        public WriteReviewPane(WriteRichEditor r) {
            Object(orientation: Orientation.VERTICAL, spacing: 6);
            this.r = r;
            add_css_class("write-sidebar-page");
            margin_top = 4;
            summary = new Label("");
            summary.add_css_class("dim-label");
            summary.add_css_class("caption");
            summary.halign = Gtk.Align.START;
            summary.margin_start = 8;
            append(summary);
            list = new Gtk.ListBox();
            list.add_css_class("navigation-sidebar");
            list.row_activated.connect((row) => {
                int i = row.get_index();
                if (i < 0 || i >= revs.size) return;
                var rv = revs[i];
                int len = rv.item != null ? rv.item.length : 0;
                r.ed.select(new Pos(rv.para, rv.offset), new Pos(rv.para, rv.offset + len));
            });
            append(list);
            empty = WriteNavigationPane.section_page("write-track-changes", _("Changes"), "");
            empty.add_action("write-track-changes", _("Track Changes"), _("Record insertions, deletions and formatting (Ctrl+Shift+E)"), () => r.run("track-changes", null));
            append(empty);
            bar = new Box(Orientation.HORIZONTAL, 6);
            var acc = new Button.with_label(_("Accept All"));
            acc.add_css_class("flat");
            acc.clicked.connect(() => r.run("accept-all", null));
            bar.append(acc);
            var rej = new Button.with_label(_("Reject All"));
            rej.add_css_class("flat");
            rej.clicked.connect(() => r.run("reject-all", null));
            bar.append(rej);
            var sp = new Box(Orientation.HORIZONTAL, 0);
            sp.hexpand = true;
            bar.append(sp);
            var prev = new Button.from_icon_name("go-up-symbolic");
            prev.add_css_class("flat");
            prev.tooltip_text = _("Previous Change");
            prev.clicked.connect(() => r.run("prev-change", null));
            bar.append(prev);
            var next = new Button.from_icon_name("go-down-symbolic");
            next.add_css_class("flat");
            next.tooltip_text = _("Next Change");
            next.clicked.connect(() => r.run("next-change", null));
            bar.append(next);
        }

        public void refresh() {
            Widget? c;
            while ((c = list.get_first_child()) != null) list.remove(c);
            revs = Review.collect(r.doc);
            int ins = 0, del = 0, fmt = 0;
            foreach (var rv in revs) {
                if (rv.rev.kind == RevKind.INSERT) ins++;
                else if (rv.rev.kind == RevKind.DELETE) del++;
                else fmt++;
                var row = new Box(Orientation.VERTICAL, 2);
                row.margin_start = 8;
                row.margin_end = 8;
                row.margin_top = 4;
                row.margin_bottom = 4;
                var who = new Label(null);
                string when = rv.rev.date.length >= 16 ? rv.rev.date.substring(0, 10) + " " + rv.rev.date.substring(11, 5) : rv.rev.date;
                who.set_markup("<b>%s</b>  <span size=\"small\" alpha=\"60%%\">%s</span>".printf(Markup.escape_text(rv.rev.author), Markup.escape_text(when)));
                who.xalign = 0;
                who.hexpand = true;
                who.ellipsize = Pango.EllipsizeMode.END;
                var head = new Box(Orientation.HORIZONTAL, 2);
                head.append(who);
                row.append(head);
                var what = new Label(rv.description());
                what.xalign = 0;
                what.wrap = true;
                what.lines = 3;
                what.ellipsize = Pango.EllipsizeMode.END;
                row.append(what);
                var a = new Button.from_icon_name("object-select-symbolic");
                a.tooltip_text = _("Accept");
                a.add_css_class("flat");
                var ref_a = rv;
                a.clicked.connect(() => {
                    r.ed.checkpoint(_("Accept Change"));
                    Review.resolve(r.doc, ref_a, true);
                    r.ed.changed();
                    refresh();
                });
                var j = new Button.from_icon_name("edit-undo-symbolic");
                j.tooltip_text = _("Reject");
                j.add_css_class("flat");
                j.clicked.connect(() => {
                    r.ed.checkpoint(_("Reject Change"));
                    Review.resolve(r.doc, ref_a, false);
                    r.ed.changed();
                    refresh();
                });
                head.append(a);
                head.append(j);
                list.append(row);
            }
            summary.label = _("%d insertions, %d deletions, %d formatting changes").printf(ins, del, fmt);
            summary.visible = revs.size > 0;
            list.visible = revs.size > 0;
            empty.visible = revs.size == 0;
            empty.subtitle = r.doc.track_changes ? _("Track Changes is on. Your edits will be listed here.") : _("No tracked changes. Turn on Track Changes to record every edit.");
            empty.set_action_description(0, r.doc.track_changes ? _("Turn off recording of edits (Ctrl+Shift+E)") : _("Record insertions, deletions and formatting (Ctrl+Shift+E)"));
        }
    }

    public class WriteStylesPane : Gtk.Box {
        private weak WriteRichEditor r;
        private Gtk.ListBox list;
        private Gtk.CheckButton show_all;

        public WriteStylesPane(WriteRichEditor r) {
            Object(orientation: Orientation.VERTICAL, spacing: 6);
            this.r = r;
            add_css_class("write-pane");
            append(new WritePaneHeader(_("Styles"), () => r.show_right("styles")));
            show_all = new Gtk.CheckButton.with_label(_("Show All Styles"));
            show_all.margin_start = 12;
            show_all.toggled.connect(() => refresh());
            append(show_all);
            list = new Gtk.ListBox();
            list.add_css_class("navigation-sidebar");
            var sc = new Gtk.ScrolledWindow();
            sc.child = list;
            sc.vexpand = true;
            sc.hscrollbar_policy = PolicyType.NEVER;
            append(sc);
            var bar = new Box(Orientation.HORIZONTAL, 6);
            bar.add_css_class("sx-control-strip");
            bar.add_css_class("write-sidebar-actions");
            var nb = new Button.with_label(_("New Style"));
            nb.add_css_class("flat");
            nb.clicked.connect(() => WriteDialogs.style_editor(r, null));
            bar.append(nb);
            var sets = new Button();
            var sbox = new Box(Orientation.HORIZONTAL, 4);
            sbox.append(new Label(_("Style Set")));
            var arrow = new Image.from_icon_name("pan-down-symbolic");
            arrow.pixel_size = 12;
            sbox.append(arrow);
            sets.child = sbox;
            sets.add_css_class("flat");
            sets.clicked.connect(() => WriteRibbon.popup_menu(sets, (m) => {
                foreach (string st in StyleSets.names()) {
                    string id = st;
                    m.add_item(StyleSets.label(id), null, () => r.run("style-set", new Variant.string(id)));
                }
            }));
            bar.append(sets);
            var sp = new Box(Orientation.HORIZONTAL, 0);
            sp.hexpand = true;
            bar.append(sp);
            var imp = new Button.from_icon_name("document-open-symbolic");
            imp.add_css_class("flat");
            imp.tooltip_text = _("Import Styles from Another Document");
            imp.clicked.connect(() => WriteDialogs.import_styles(r));
            bar.append(imp);
            append(bar);
        }

        public void refresh() {
            Widget? c;
            while ((c = list.get_first_child()) != null) list.remove(c);
            var styles = new Gee.ArrayList<Write.Style>();
            foreach (var s in r.doc.styles.list) {
                if (s.kind != StyleType.PARAGRAPH && s.kind != StyleType.CHARACTER) continue;
                if (!show_all.active && !s.quick && !s.custom && !used(s.id)) continue;
                styles.add(s);
            }
            styles.sort((a, b) => a.priority != b.priority ? a.priority - b.priority : strcmp(a.name, b.name));
            foreach (var s in styles) {
                var row = new Box(Orientation.HORIZONTAL, 6);
                row.margin_start = 8;
                row.margin_end = 4;
                var l = new Label(null);
                var cp = r.doc.styles.char_chain(s.id);
                var attrs = new StringBuilder();
                if (cp.bold.on()) attrs.append(" weight=\"bold\"");
                if (cp.italic.on()) attrs.append(" style=\"italic\"");
                if (cp.color != null) attrs.append(" foreground=\"%s\"".printf(cp.color));
                double sz = cp.size > 0 ? double.min(cp.size, 16) : 11;
                l.set_markup("<span size=\"%dpt\"%s>%s</span>".printf((int) sz, attrs.str, Markup.escape_text(s.name)));
                l.xalign = 0;
                l.hexpand = true;
                l.ellipsize = Pango.EllipsizeMode.END;
                row.append(l);
                var kind = new Label(s.kind == StyleType.CHARACTER ? "a" : "\u00b6");
                kind.add_css_class("dim-label");
                row.append(kind);
                var mod = new Button.from_icon_name("document-edit-symbolic");
                mod.add_css_class("flat");
                mod.tooltip_text = _("Modify");
                var st = s;
                mod.clicked.connect(() => WriteDialogs.style_editor(r, st));
                row.append(mod);
                if (s.custom) {
                    var del = new Button.from_icon_name("user-trash-symbolic");
                    del.add_css_class("flat");
                    del.tooltip_text = _("Delete");
                    del.clicked.connect(() => {
                        r.ed.checkpoint(_("Delete Style"));
                        foreach (var p in Story.all(r.doc)) {
                            if (p.style == st.id) {
                                p.style = st.based_on ?? "Normal";
                                p.touch();
                            }
                            foreach (var it in p.inlines) if (it.props.style == st.id) it.props.style = null;
                        }
                        r.doc.styles.remove(st.id);
                        r.doc.styles.touch();
                        r.fbar.set_styles(r.doc);
                        r.touch_all();
                        refresh();
                    });
                    row.append(del);
                }
                var lr = new Gtk.ListBoxRow();
                lr.child = row;
                var click = new Gtk.GestureClick();
                click.pressed.connect((n, x, y) => {
                    if (n == 1) r.run("style", new Variant.string(st.id));
                });
                lr.add_controller(click);
                list.append(lr);
            }
        }

        private bool used(string id) {
            foreach (var p in Story.paragraphs(r.doc.body)) {
                if (p.style == id) return true;
                foreach (var i in p.inlines) if (i.props.style == id) return true;
            }
            return false;
        }
    }

    public class WriteCheckPane : Gtk.Box {
        private weak WriteRichEditor r;
        private Gtk.Label title;
        private Gtk.Box body;
        private Gee.ArrayList<Write.Issue> issues = new Gee.ArrayList<Write.Issue>();
        private int index = 0;

        public WriteCheckPane(WriteRichEditor r) {
            Object(orientation: Orientation.VERTICAL, spacing: 6);
            this.r = r;
            add_css_class("write-pane");
            var head = new Box(Orientation.HORIZONTAL, 6);
            title = new Label("");
            title.add_css_class("heading");
            title.hexpand = true;
            title.xalign = 0;
            title.margin_start = 12;
            title.margin_top = 8;
            head.append(title);
            var close = new Button.from_icon_name("window-close-symbolic");
            close.add_css_class("flat");
            close.clicked.connect(() => r.show_right("check"));
            head.append(close);
            append(head);
            body = new Box(Orientation.VERTICAL, 8);
            body.margin_start = 12;
            body.margin_end = 12;
            var sc = new Gtk.ScrolledWindow();
            sc.child = body;
            sc.vexpand = true;
            sc.hscrollbar_policy = PolicyType.NEVER;
            append(sc);
        }

        private void clear() {
            Widget? c;
            while ((c = body.get_first_child()) != null) body.remove(c);
        }

        public void start_spelling() {
            title.label = _("Spelling and Grammar");
            issues = r.view.all_issues(true);
            index = 0;
            show_issue();
        }

        private void show_issue() {
            clear();
            if (index >= issues.size) {
                var l = new Label(issues.size == 0 ? _("No spelling or grammar issues found.") : _("The check is complete."));
                l.wrap = true;
                l.margin_top = 12;
                body.append(l);
                return;
            }
            var is = issues[index];
            r.ed.select(new Pos(is.para, is.start), new Pos(is.para, is.end));
            var kind = new Label(is.kind == "spelling" ? _("Spelling") : (is.kind == "style" ? _("Style") : _("Grammar")));
            kind.add_css_class("dim-label");
            kind.xalign = 0;
            body.append(kind);
            var msg = new Label(is.message);
            msg.wrap = true;
            msg.xalign = 0;
            body.append(msg);
            var ctx = new Label(null);
            string t = is.para.plain_text();
            int s = int.max(0, is.start - 40);
            int e = int.min(t.char_count(), is.end + 40);
            ctx.set_markup(Markup.escape_text(usub(t, s, is.start)) + "<span underline=\"error\"><b>" + Markup.escape_text(usub(t, is.start, is.end)) + "</b></span>" + Markup.escape_text(usub(t, is.end, e)));
            ctx.wrap = true;
            ctx.xalign = 0;
            ctx.add_css_class("write-check-context");
            body.append(ctx);
            var group = new Singularity.Widgets.PreferencesGroup(_("Suggestions"));
            foreach (string sug in is.suggestions) {
                var row = new Singularity.Widgets.ActionRow(sug == "" ? _("(delete)") : sug);
                string rep = sug;
                row.activated.connect(() => {
                    apply(is, rep);
                    index++;
                    show_issue();
                });
                group.add_row(row);
            }
            if (is.suggestions.length == 0) group.add_row(new Singularity.Widgets.ActionRow(_("No suggestions")));
            body.append(group);
            var bar = new Box(Orientation.HORIZONTAL, 6);
            var ignore = new Button.with_label(_("Ignore"));
            ignore.clicked.connect(() => {
                index++;
                show_issue();
            });
            bar.append(ignore);
            if (is.kind == "spelling") {
                var ign_all = new Button.with_label(_("Ignore All"));
                string word = usub(is.para.text(), is.start, is.end);
                ign_all.clicked.connect(() => {
                    r.view.ignored.add(word);
                    for (int i = issues.size - 1; i > index; i--) if (usub(issues[i].para.text(), issues[i].start, issues[i].end) == word) issues.remove_at(i);
                    r.view.refresh_spelling();
                    index++;
                    show_issue();
                });
                bar.append(ign_all);
                var add = new Button.with_label(_("Add to Dictionary"));
                add.clicked.connect(() => {
                    Singularity.Text.SpellChecker.get_default().add_to_dictionary(word);
                    r.view.refresh_spelling();
                    index++;
                    show_issue();
                });
                bar.append(add);
            }
            body.append(bar);
            var progress = new Label(_("Issue %d of %d").printf(index + 1, issues.size));
            progress.add_css_class("dim-label");
            progress.add_css_class("caption");
            progress.xalign = 0;
            body.append(progress);
        }

        private void apply(Write.Issue is, string rep) {
            r.ed.checkpoint(_("Correct"));
            var props = is.para.props_at(is.start + 1);
            r.ed.select(new Pos(is.para, is.start), new Pos(is.para, is.end));
            r.ed.delete_selection();
            if (rep != "") r.ed.insert_text(rep, props);
            int delta = rep.char_count() - (is.end - is.start);
            for (int i = index + 1; i < issues.size; i++) {
                if (issues[i].para != is.para || issues[i].start < is.end) continue;
                issues[i].start += delta;
                issues[i].end += delta;
            }
        }

        public void start_accessibility() {
            title.label = _("Accessibility");
            clear();
            var found = AccessibilityChecker.check(r.doc);
            if (found.size == 0) {
                var l = new Label(_("No accessibility issues found."));
                l.wrap = true;
                l.margin_top = 12;
                body.append(l);
                return;
            }
            string[] sev = { "error", "warning", "tip" };
            string[] titles = { _("Errors"), _("Warnings"), _("Tips") };
            for (int k = 0; k < 3; k++) {
                var group = new Singularity.Widgets.PreferencesGroup(titles[k]);
                int n = 0;
                foreach (var f in found) {
                    if (f.severity != sev[k]) continue;
                    n++;
                    var row = new Singularity.Widgets.ActionRow(f.title, f.detail);
                    var ff = f;
                    string fix_label = fix_name(f.fix);
                    if (fix_label != "") {
                        var b = new Button.with_label(fix_label);
                        b.valign = Gtk.Align.CENTER;
                        b.clicked.connect(() => fix(ff));
                        row.add_suffix(b);
                    }
                    row.activated.connect(() => {
                        if (ff.para != null) r.view.scroll_to_para(ff.para);
                    });
                    group.add_row(row);
                }
                if (n > 0) body.append(group);
            }
        }

        private string fix_name(string fix) {
            switch (fix) {
                case "alt": return _("Add Alt Text");
                case "properties": return _("Properties");
                case "header-row": return _("Mark Header Row");
                case "table-alt": return _("Describe");
                case "inline": return _("Place In Line");
                default: return "";
            }
        }

        private void fix(AccessibilityChecker.Finding f) {
            switch (f.fix) {
                case "alt":
                    if (f.item is FloatingInline) WriteDialogs.alt_text(r, (FloatingInline) f.item, () => start_accessibility());
                    break;
                case "properties":
                    WriteDialogs.doc_properties(r);
                    break;
                case "header-row":
                    if (f.table != null && f.table.rows.size > 0) {
                        r.ed.checkpoint(_("Header Row"));
                        f.table.rows[0].header = true;
                        r.touch_all();
                        start_accessibility();
                    }
                    break;
                case "table-alt":
                    if (f.table != null) WriteDialogs.table_alt(r, f.table, () => start_accessibility());
                    break;
                case "inline":
                    if (f.item is FloatingInline) {
                        r.ed.checkpoint(_("In Line With Text"));
                        ((FloatingInline) f.item).wrap = Wrap.INLINE;
                        r.touch_all();
                        start_accessibility();
                    }
                    break;
                default:
                    break;
            }
        }
    }
}
