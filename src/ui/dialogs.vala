using Gtk;
using Singularity.Widgets;
using Write;

namespace Singularity.Apps {

    public class WriteDialogs : Object {
        public delegate void Apply();
        public delegate FindOptions OptsFn();

        public static AppDialog make(WriteRichEditor r, string title, int w, int h) {
            var dlg = new AppDialog(r.app, true);
            dlg.set_title(title);
            dlg.transient_for = r.window;
            dlg.set_default_size(int.max(w, 500), h);
            dlg.add_css_class("write-dialog");
            dlg.close_request.connect(() => {
                Idle.add(() => {
                    r.view.grab_focus();
                    return false;
                });
                return false;
            });
            return dlg;
        }

        public static Box body(AppDialog dlg) {
            var scroll = new ScrolledWindow();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.vexpand = true;
            var box = new Box(Orientation.VERTICAL, 14);
            box.margin_start = 18;
            box.margin_end = 18;
            box.margin_top = 6;
            box.margin_bottom = 12;
            scroll.child = box;
            dlg.content_box.append(scroll);
            return box;
        }

        public static void footer(AppDialog dlg, string label, owned Apply apply, string? extra = null, owned Apply? extra_apply = null, bool close_after = true) {
            var bar = new Box(Orientation.HORIZONTAL, 8);
            bar.margin_start = 18;
            bar.margin_end = 18;
            bar.margin_bottom = 16;
            bar.margin_top = 4;
            if (extra != null) {
                var e = new Button.with_label(extra);
                e.clicked.connect(() => {
                    extra_apply();
                });
                bar.append(e);
            }
            var spacer = new Box(Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            bar.append(spacer);
            var cancel = new Button.with_label(_("Cancel"));
            cancel.clicked.connect(() => dlg.close());
            dlg.set_cancel_button(cancel);
            var ok = new Button.with_label(label);
            ok.add_css_class("suggested-action");
            ok.clicked.connect(() => {
                apply();
                if (close_after) dlg.close();
            });
            bar.append(cancel);
            bar.append(ok);
            dlg.content_box.append(bar);
            dlg.default_widget = ok;
        }

        public static void close_footer(AppDialog dlg) {
            var bar = new Box(Orientation.HORIZONTAL, 8);
            bar.margin_start = 18;
            bar.margin_end = 18;
            bar.margin_bottom = 16;
            bar.halign = Gtk.Align.END;
            var close = new Button.with_label(_("Close"));
            close.add_css_class("suggested-action");
            close.clicked.connect(() => dlg.close());
            dlg.set_cancel_button(close);
            bar.append(close);
            dlg.content_box.append(bar);
        }

        public static WriteChoice drop_row(PreferencesGroup g, string title, string[] labels, int selected) {
            var d = new WriteChoice(title, labels, selected < 0 ? 0 : selected);
            g.add_row(d.row);
            return d;
        }

        public static SpinRow spin_row(PreferencesGroup g, string title, string? sub, double min, double max, double step, double val, int digits = 1) {
            var s = new SpinRow(title, sub, min, max, step, val);
            s.spin_btn.digits = digits;
            g.add_row(s);
            return s;
        }

        public static SwitchRow switch_row(PreferencesGroup g, string title, string? sub, bool val) {
            var s = new SwitchRow(title, sub, val);
            g.add_row(s);
            return s;
        }

        public static EntryRow entry_row(PreferencesGroup g, string title, string val) {
            var e = new EntryRow(title);
            e.text = val;
            g.add_row(e);
            return e;
        }

        public static Gtk.ColorDialogButton color_row(PreferencesGroup g, string title, string? hex) {
            var row = new ActionRow(title);
            var cd = new Gtk.ColorDialog();
            cd.with_alpha = false;
            var btn = new Gtk.ColorDialogButton(cd);
            var rgba = Gdk.RGBA();
            rgba.parse(hex ?? "#000000");
            btn.rgba = rgba;
            btn.valign = Gtk.Align.CENTER;
            row.add_suffix(btn);
            g.add_row(row);
            return btn;
        }

        public static string hex(Gdk.RGBA c) {
            return "#%02x%02x%02x".printf((int) Math.round(c.red * 255), (int) Math.round(c.green * 255), (int) Math.round(c.blue * 255));
        }

        public static string hex_of(Gtk.ColorDialogButton b) {
            var value = Value(typeof(Gdk.RGBA));
            b.get_property("rgba", ref value);
            Gdk.RGBA* c = (Gdk.RGBA*) value.get_boxed();
            if (c == null) return "#000000";
            return hex(*c);
        }

        public static double to_unit(WriteRichEditor r, double pt) {
            return r.ruler.metric ? pt / 28.3464567 : pt / 72.0;
        }

        public static double from_unit(WriteRichEditor r, double v) {
            return r.ruler.metric ? v * 28.3464567 : v * 72.0;
        }

        public static string unit(WriteRichEditor r) {
            return r.ruler.metric ? _("cm") : _("in");
        }

        private static void message(WriteRichEditor r, string title, string text) {
            var d = new ConfirmDialog.message(r.app, title, "dialog-information", text);
            d.transient_for = r.window;
            d.present();
        }

        public static void font(WriteRichEditor r) {
            var ed = r.ed;
            var cur = ed.focus.para.props_at(ed.has_selection ? ed.focus.offset : ed.focus.offset);
            if (ed.has_selection) {
                Pos a, b;
                ed.ordered(out a, out b);
                cur = a.para.props_at(a.offset + 1);
            }
            var res = r.doc.styles.resolve_char(ed.focus.para, r.view.pending ?? cur);
            var dlg = make(r, _("Font"), 460, 640);
            var box = body(dlg);
            var g = new PreferencesGroup(_("Font"));
            var fam = entry_row(g, _("Font family"), res.font ?? "");
            var size = spin_row(g, _("Size"), _("points"), 1, 400, 0.5, res.size > 0 ? res.size : 11);
            var style = drop_row(g, _("Style"), { _("Regular"), _("Bold"), _("Italic"), _("Bold Italic") }, (res.bold.on() ? 1 : 0) + (res.italic.on() ? 2 : 0));
            var color = color_row(g, _("Color"), res.color ?? "#000000");
            box.append(g);
            var e = new PreferencesGroup(_("Effects"));
            string[] ul = { _("None"), _("Single"), _("Double"), _("Dotted"), _("Dashed"), _("Wave"), _("Thick"), _("Words only") };
            int uli = res.underline == Underline.INHERIT ? 0 : (int) res.underline;
            var under = drop_row(e, _("Underline"), ul, uli);
            var strike = switch_row(e, _("Strikethrough"), null, res.strike.on());
            var dstrike = switch_row(e, _("Double strikethrough"), null, res.dstrike.on());
            var sup = switch_row(e, _("Superscript"), null, res.valign == VAlign.SUPER);
            var sub = switch_row(e, _("Subscript"), null, res.valign == VAlign.SUB);
            var caps = drop_row(e, _("Capitalization"), { _("Normal"), _("All caps"), _("Small caps") }, res.caps == Caps.ALL ? 1 : (res.caps == Caps.SMALL ? 2 : 0));
            var hidden = switch_row(e, _("Hidden"), null, res.hidden.on());
            var outline = switch_row(e, _("Outline"), null, res.outline.on());
            var shadow = switch_row(e, _("Shadow"), null, res.shadow.on());
            box.append(e);
            var a = new PreferencesGroup(_("Character spacing"));
            var spacing = spin_row(a, _("Spacing"), _("points, negative condenses"), -20, 60, 0.1, res.spacing.is_nan() ? 0 : res.spacing);
            var position = spin_row(a, _("Position"), _("points raised or lowered"), -60, 60, 0.5, res.position.is_nan() ? 0 : res.position);
            var lang = entry_row(a, _("Language"), res.lang ?? "");
            box.append(a);
            footer(dlg, _("Apply"), () => {
                string f = fam.text.strip();
                double s = size.value;
                int st = (int) style.selected;
                string col = hex_of(color);
                Underline u = (Underline) under.selected;
                bool sk = strike.active, ds = dstrike.active, su = sup.active, sb = sub.active, hi = hidden.active, ol = outline.active, sh = shadow.active;
                int cp = (int) caps.selected;
                double spc = spacing.value, pos = position.value;
                string lg = lang.text.strip();
                CharMutator fn = (c) => {
                    if (f != "") c.font = f;
                    c.size = s;
                    c.bold = Tri.of(st == 1 || st == 3);
                    c.italic = Tri.of(st >= 2);
                    c.color = col == "#000000" && res.color == null ? null : col;
                    c.underline = u;
                    c.strike = Tri.of(sk);
                    c.dstrike = Tri.of(ds);
                    c.valign = su ? VAlign.SUPER : (sb ? VAlign.SUB : VAlign.BASELINE);
                    c.caps = cp == 1 ? Caps.ALL : (cp == 2 ? Caps.SMALL : Caps.NONE);
                    c.hidden = Tri.of(hi);
                    c.outline = Tri.of(ol);
                    c.shadow = Tri.of(sh);
                    c.spacing = spc == 0 ? double.NAN : spc;
                    c.position = pos == 0 ? double.NAN : pos;
                    c.lang = lg == "" ? null : lg;
                };
                if (ed.has_selection) {
                    ed.checkpoint(_("Font"));
                    ed.format_chars((c) => fn(c));
                } else {
                    var p = (r.view.pending ?? ed.props_for_insert()).copy();
                    fn(p);
                    r.view.pending = p;
                }
                r.fbar.sync(r.doc, ed, r.view.pending);
            });
            dlg.present();
        }

        public static void paragraph(WriteRichEditor r) {
            var ed = r.ed;
            var pp = r.doc.styles.resolve_para(ed.focus.para);
            var dlg = make(r, _("Paragraph"), 480, 660);
            var box = body(dlg);
            string u = unit(r);
            var g = new PreferencesGroup(_("Alignment and outline"));
            var al = drop_row(g, _("Alignment"), { _("Left"), _("Centered"), _("Right"), _("Justified") }, pp.align == Write.Align.INHERIT ? 0 : (int) pp.align);
            string[] levels = { _("Body text"), _("Level 1"), _("Level 2"), _("Level 3"), _("Level 4"), _("Level 5"), _("Level 6"), _("Level 7"), _("Level 8"), _("Level 9") };
            var ol = drop_row(g, _("Outline level"), levels, pp.outline >= 0 && pp.outline < 9 ? pp.outline + 1 : 0);
            box.append(g);
            var i = new PreferencesGroup(_("Indentation"));
            var left = spin_row(i, _("Left"), u, -20, 50, 0.1, to_unit(r, pp.ind_left.is_nan() ? 0 : pp.ind_left), 2);
            var right = spin_row(i, _("Right"), u, -20, 50, 0.1, to_unit(r, pp.ind_right.is_nan() ? 0 : pp.ind_right), 2);
            double first = pp.ind_first.is_nan() ? 0 : pp.ind_first;
            var special = drop_row(i, _("Special"), { _("None"), _("First line"), _("Hanging") }, first > 0 ? 1 : (first < 0 ? 2 : 0));
            var by = spin_row(i, _("By"), u, 0, 20, 0.1, to_unit(r, first.abs()), 2);
            box.append(i);
            var s = new PreferencesGroup(_("Spacing"));
            var before = spin_row(s, _("Before"), _("points"), 0, 400, 1, pp.space_before.is_nan() ? 0 : pp.space_before, 0);
            var after = spin_row(s, _("After"), _("points"), 0, 400, 1, pp.space_after.is_nan() ? 0 : pp.space_after, 0);
            var rule = drop_row(s, _("Line spacing"), { _("Multiple"), _("Exactly"), _("At least") }, (int) pp.line_rule);
            var at = spin_row(s, _("At"), _("lines or points"), 0.5, 200, 0.05, pp.line.is_nan() ? 1 : pp.line, 2);
            var ctx = switch_row(s, _("Don't add space between paragraphs of the same style"), null, pp.contextual.on());
            box.append(s);
            var f = new PreferencesGroup(_("Line and page breaks"));
            var widow = switch_row(f, _("Widow and orphan control"), null, pp.widow != Tri.OFF);
            var keepn = switch_row(f, _("Keep with next"), null, pp.keep_next.on());
            var keepl = switch_row(f, _("Keep lines together"), null, pp.keep_lines.on());
            var pb = switch_row(f, _("Page break before"), null, pp.page_break_before.on());
            box.append(f);
            var t = new PreferencesGroup(_("Tab stops"), _("Positions separated by spaces; add r, c or d for right, center or decimal alignment and . for dot leaders, for example 8r. 12"));
            var sb = new StringBuilder();
            if (pp.tabs != null) foreach (var ts in pp.tabs) {
                if (sb.len > 0) sb.append_c(' ');
                sb.append(Write.X.num(Math.round(to_unit(r, ts.pos) * 100) / 100));
                if (ts.align == TabAlign.RIGHT) sb.append_c('r');
                else if (ts.align == TabAlign.CENTER) sb.append_c('c');
                else if (ts.align == TabAlign.DECIMAL) sb.append_c('d');
                if (ts.leader == TabLeader.DOT) sb.append_c('.');
                else if (ts.leader == TabLeader.HYPHEN) sb.append_c('-');
                else if (ts.leader == TabLeader.UNDERSCORE) sb.append_c('_');
            }
            var tabs = entry_row(t, _("Tab stops"), sb.str);
            box.append(t);
            footer(dlg, _("Apply"), () => {
                ed.checkpoint(_("Paragraph"));
                int ali = (int) al.selected;
                int oli = (int) ol.selected;
                double l = from_unit(r, left.value), rr = from_unit(r, right.value);
                int spi = (int) special.selected;
                double b = from_unit(r, by.value);
                double sbv = before.value, sav = after.value, atv = at.value;
                LineRule lr = (LineRule) rule.selected;
                bool c = ctx.active, w = widow.active, kn = keepn.active, kl = keepl.active, pbb = pb.active;
                var parsed = new Gee.ArrayList<TabStop>();
                foreach (string tok in tabs.text.split(" ")) {
                    string tk = tok.strip();
                    if (tk == "") continue;
                    TabAlign ta = TabAlign.LEFT;
                    TabLeader tl = TabLeader.NONE;
                    while (tk.length > 0 && !tk[tk.length - 1].isdigit()) {
                        char ch = tk[tk.length - 1];
                        if (ch == 'r') ta = TabAlign.RIGHT;
                        else if (ch == 'c') ta = TabAlign.CENTER;
                        else if (ch == 'd') ta = TabAlign.DECIMAL;
                        else if (ch == '.') tl = TabLeader.DOT;
                        else if (ch == '-') tl = TabLeader.HYPHEN;
                        else if (ch == '_') tl = TabLeader.UNDERSCORE;
                        tk = tk.substring(0, tk.length - 1);
                    }
                    double v;
                    if (double.try_parse(tk.replace(",", "."), out v)) parsed.add(new TabStop(from_unit(r, v), ta, tl));
                }
                ed.format_paragraphs((p) => {
                    p.props.align = (Write.Align) ali;
                    p.props.outline = oli == 0 ? 9 : oli - 1;
                    p.props.ind_left = l;
                    p.props.ind_right = rr;
                    p.props.ind_first = spi == 1 ? b : (spi == 2 ? -b : 0);
                    p.props.space_before = sbv;
                    p.props.space_after = sav;
                    p.props.line = atv;
                    p.props.line_rule = lr;
                    p.props.contextual = Tri.of(c);
                    p.props.widow = Tri.of(w);
                    p.props.keep_next = Tri.of(kn);
                    p.props.keep_lines = Tri.of(kl);
                    p.props.page_break_before = Tri.of(pbb);
                    var tl2 = new Gee.ArrayList<TabStop>();
                    foreach (var x in parsed) tl2.add(x.copy());
                    var base_tabs = r.doc.styles.para_chain(p.style).tabs;
                    if (base_tabs != null) foreach (var bt in base_tabs) {
                        bool kept = false;
                        foreach (var x in parsed) if ((x.pos - bt.pos).abs() < 0.5) kept = true;
                        if (!kept) tl2.add(new TabStop(bt.pos, TabAlign.CLEAR));
                    }
                    p.props.tabs = tl2;
                });
            });
            dlg.present();
        }

        public static void list_gallery(WriteRichEditor r) {
            var dlg = make(r, _("Lists"), 420, 520);
            var box = body(dlg);
            var g = new PreferencesGroup(_("Bullets"));
            string[,] bullets = { { "\u2022 \u25e6 \u25aa", "\u2022|\u25e6|\u25aa" }, { "\u2713", "\u2713" }, { "\u25c6", "\u25c6" }, { "\u2043", "\u2043" }, { "\u25a0", "\u25a0" }, { "\u2605", "\u2605" } };
            for (int i = 0; i < bullets.length[0]; i++) {
                var row = new ActionRow(bullets[i, 0]);
                string marks = bullets[i, 1];
                row.activated.connect(() => {
                    r.ed.checkpoint(_("Bullets"));
                    r.ed.apply_list_def(r.doc.numbering.make_bullets(marks.split("|")));
                    dlg.close();
                });
                g.add_row(row);
            }
            box.append(g);
            var n = new PreferencesGroup(_("Numbering"));
            string[] labels = { "1. 2. 3.", "1) 2) 3)", "a. b. c.", "A. B. C.", "i. ii. iii.", "I. II. III.", _("1. 1.1. 1.1.1. (multilevel)") };
            for (int i = 0; i < labels.length; i++) {
                var row = new ActionRow(labels[i]);
                int k = i;
                row.activated.connect(() => {
                    ListDef d;
                    if (k == 6) d = r.doc.numbering.make_outline();
                    else {
                        NumFormat[] f = { NumFormat.DECIMAL, NumFormat.DECIMAL, NumFormat.LOWER_LETTER, NumFormat.UPPER_LETTER, NumFormat.LOWER_ROMAN, NumFormat.UPPER_ROMAN };
                        d = r.doc.numbering.make_numbers({ f[k], NumFormat.LOWER_LETTER, NumFormat.LOWER_ROMAN });
                        if (k == 1) d.levels[0].text = "%1)";
                    }
                    r.ed.checkpoint(_("Numbering"));
                    r.ed.apply_list_def(d);
                    dlg.close();
                });
                n.add_row(row);
            }
            box.append(n);
            var o = new PreferencesGroup(_("Numbering value"));
            var start = spin_row(o, _("Start at"), null, 0, 9999, 1, 1, 0);
            var set = new Button.with_label(_("Set Value"));
            set.valign = Gtk.Align.CENTER;
            set.clicked.connect(() => {
                var pp = r.doc.styles.resolve_para(r.ed.focus.para);
                if (pp.num_id <= 0) return;
                r.ed.checkpoint(_("Set Numbering Value"));
                int fresh = r.doc.numbering.restart(pp.num_id);
                r.doc.numbering.instance(fresh).start_override[int.max(0, pp.num_level)] = (int) start.value;
                int old = pp.num_id;
                bool on = false;
                foreach (var p in Story.paragraphs(Story.root_of(r.doc, r.ed.focus.para))) {
                    if (p == r.ed.focus.para) on = true;
                    if (on && r.doc.styles.resolve_para(p).num_id == old) {
                        p.props.num_id = fresh;
                        p.touch();
                    }
                }
                r.ed.changed();
                dlg.close();
            });
            start.add_suffix(set);
            box.append(o);
            close_footer(dlg);
            dlg.present();
        }

        public static void style_editor(WriteRichEditor r, Write.Style? existing) {
            bool is_new = existing == null;
            var st = existing != null ? existing.copy() : new Write.Style("", "", StyleType.PARAGRAPH);
            var dlg = make(r, is_new ? _("New Style") : _("Modify Style"), 480, 640);
            var box = body(dlg);
            var g = new PreferencesGroup(_("Properties"));
            var name = entry_row(g, _("Name"), is_new ? _("New Style") : st.name);
            var kind = drop_row(g, _("Type"), { _("Paragraph"), _("Character") }, st.kind == StyleType.CHARACTER ? 1 : 0);
            kind.sensitive = is_new;
            var ids = new Gee.ArrayList<string>();
            var labels = new Gee.ArrayList<string>();
            ids.add("");
            labels.add(_("(no style)"));
            foreach (var s in r.doc.styles.of_kind(StyleType.PARAGRAPH)) {
                ids.add(s.id);
                labels.add(s.name);
            }
            string basis = is_new ? r.ed.focus.para.style : (st.based_on ?? "");
            var based = drop_row(g, _("Based on"), labels.to_array(), ids.index_of(basis));
            string nxt = st.next ?? (is_new ? "Normal" : st.id);
            var next = drop_row(g, _("Style for following paragraph"), labels.to_array(), ids.index_of(nxt));
            var quick = switch_row(g, _("Show in the style gallery"), null, is_new || st.quick);
            box.append(g);
            var cur = is_new ? r.doc.styles.resolve_char(r.ed.focus.para, r.ed.focus.para.props_at(r.ed.focus.offset)) : r.doc.styles.char_chain(st.id);
            var curp = is_new ? r.doc.styles.resolve_para(r.ed.focus.para) : r.doc.styles.para_chain(st.id);
            var f = new PreferencesGroup(_("Formatting"));
            var font = entry_row(f, _("Font"), cur.font ?? "");
            var size = spin_row(f, _("Size"), _("points"), 1, 400, 0.5, cur.size > 0 ? cur.size : 11);
            var bold = switch_row(f, _("Bold"), null, cur.bold.on());
            var italic = switch_row(f, _("Italic"), null, cur.italic.on());
            var color = color_row(f, _("Color"), cur.color ?? "#000000");
            var al = drop_row(f, _("Alignment"), { _("Left"), _("Centered"), _("Right"), _("Justified") }, curp.align == Write.Align.INHERIT ? 0 : (int) curp.align);
            var before = spin_row(f, _("Space before"), _("points"), 0, 200, 1, curp.space_before.is_nan() ? 0 : curp.space_before, 0);
            var after = spin_row(f, _("Space after"), _("points"), 0, 200, 1, curp.space_after.is_nan() ? 0 : curp.space_after, 0);
            var line = spin_row(f, _("Line spacing"), _("lines"), 0.5, 5, 0.05, curp.line.is_nan() ? 1 : curp.line, 2);
            var ind = spin_row(f, _("Left indent"), unit(r), 0, 30, 0.1, to_unit(r, curp.ind_left.is_nan() ? 0 : curp.ind_left), 2);
            string[] levels = { _("Body text"), _("Level 1"), _("Level 2"), _("Level 3"), _("Level 4"), _("Level 5"), _("Level 6"), _("Level 7"), _("Level 8"), _("Level 9") };
            var outline = drop_row(f, _("Outline level"), levels, curp.outline >= 0 && curp.outline < 9 ? curp.outline + 1 : 0);
            var keep = switch_row(f, _("Keep with next"), null, curp.keep_next.on());
            box.append(f);
            footer(dlg, is_new ? _("Create") : _("Save"), () => {
                r.ed.checkpoint(is_new ? _("New Style") : _("Modify Style"));
                string nm = name.text.strip();
                if (nm == "") nm = _("Style");
                if (is_new) {
                    st.id = r.doc.styles.unique_id(nm);
                    st.kind = kind.selected == 1 ? StyleType.CHARACTER : StyleType.PARAGRAPH;
                    st.custom = true;
                    st.priority = 50;
                }
                st.name = nm;
                string bo = ids[(int) based.selected];
                st.based_on = bo == "" || bo == st.id ? null : bo;
                string nx = ids[(int) next.selected];
                st.next = nx == "" ? null : nx;
                st.quick = quick.active;
                var baseline = st.based_on != null ? r.doc.styles.char_chain(st.based_on) : r.doc.styles.default_char;
                var basepara = st.based_on != null ? r.doc.styles.para_chain(st.based_on) : r.doc.styles.default_para;
                var c = new CharProps();
                if (font.text.strip() != "" && font.text.strip() != baseline.font) c.font = font.text.strip();
                if (size.value != baseline.size) c.size = size.value;
                if (bold.active != baseline.bold.on()) c.bold = Tri.of(bold.active);
                if (italic.active != baseline.italic.on()) c.italic = Tri.of(italic.active);
                string col = hex_of(color);
                if (col != (baseline.color ?? "#000000")) c.color = col;
                st.chr = c;
                var pp = st.para.copy();
                pp.align = (Write.Align) al.selected;
                pp.space_before = before.value;
                pp.space_after = after.value;
                pp.line = line.value;
                pp.line_rule = LineRule.AUTO;
                pp.ind_left = from_unit(r, ind.value);
                pp.outline = outline.selected == 0 ? (basepara.outline >= 0 && basepara.outline < 9 ? 9 : -1) : (int) outline.selected - 1;
                pp.keep_next = Tri.of(keep.active);
                if (st.kind == StyleType.PARAGRAPH) st.para = pp;
                r.doc.styles.add(st);
                r.doc.styles.touch();
                if (is_new && st.kind == StyleType.PARAGRAPH) r.ed.set_style(st.id);
                r.fbar.set_styles(r.doc);
                r.styles_pane.refresh();
                r.touch_all();
            });
            dlg.present();
        }

        public static void import_styles(WriteRichEditor r) {
            var fd = new Gtk.FileDialog();
            fd.title = _("Import Styles From");
            var fl = new GLib.ListStore(typeof(Gtk.FileFilter));
            fl.append(WriteFiles.all_documents());
            fd.filters = fl;
            fd.open.begin(r.window, null, (o, res) => {
                try {
                    var f = fd.open.end(res);
                    Write.FileFormat fmt;
                    var src = WriteFiles.load(f, out fmt);
                    r.ed.checkpoint(_("Import Styles"));
                    int n = 0;
                    foreach (var s in src.styles.list) {
                        if (s.kind != StyleType.PARAGRAPH && s.kind != StyleType.CHARACTER && s.kind != StyleType.TABLE) continue;
                        r.doc.styles.add(s.copy());
                        n++;
                    }
                    r.doc.styles.touch();
                    r.fbar.set_styles(r.doc);
                    r.styles_pane.refresh();
                    r.touch_all();
                    r.toast(ngettext("%d style imported", "%d styles imported", n).printf(n));
                } catch (Error e) {
                    if (!(e is Gtk.DialogError.DISMISSED)) r.toast(e.message);
                }
            });
        }

        public static void insert_table(WriteRichEditor r) {
            var dlg = make(r, _("Insert Table"), 380, 420);
            var box = body(dlg);
            var g = new PreferencesGroup();
            var rows = spin_row(g, _("Rows"), null, 1, 500, 1, 3, 0);
            var cols = spin_row(g, _("Columns"), null, 1, 63, 1, 3, 0);
            var header = switch_row(g, _("Header row"), _("Repeats at the top of each page"), true);
            var ids = new Gee.ArrayList<string>();
            var labels = new Gee.ArrayList<string>();
            foreach (var s in r.doc.styles.of_kind(StyleType.TABLE)) {
                ids.add(s.id);
                labels.add(s.name);
            }
            var style = drop_row(g, _("Table style"), labels.to_array(), ids.index_of("TableGrid"));
            box.append(g);
            footer(dlg, _("Insert"), () => {
                r.ed.checkpoint(_("Insert Table"));
                r.ed.insert_table((int) rows.value, (int) cols.value);
                var t = r.ed.table_at(r.ed.focus);
                if (t != null) {
                    t.rows[0].header = header.active;
                    string sid = ids.size > 0 ? ids[(int) style.selected] : "TableGrid";
                    t.style = sid;
                    if (sid != "TableGrid" && sid != "PlainTable") {
                        t.border_top = t.border_bottom = t.border_left = t.border_right = t.border_h = t.border_v = null;
                    }
                }
                r.ed.changed();
            });
            dlg.present();
        }

        public static void table_properties(WriteRichEditor r) {
            var t = r.ed.table_at(r.ed.focus);
            var cell = r.ed.cell_at(r.ed.focus);
            if (t == null) {
                r.toast(_("Place the cursor in a table first."));
                return;
            }
            int ri, ci;
            t.locate_cell(cell, out ri, out ci);
            var row = t.rows[ri];
            var dlg = make(r, _("Table Properties"), 460, 640);
            var box = body(dlg);
            var g = new PreferencesGroup(_("Table"));
            var al = drop_row(g, _("Alignment"), { _("Left"), _("Center"), _("Right") }, t.align == Write.Align.CENTER ? 1 : (t.align == Write.Align.RIGHT ? 2 : 0));
            var indent = spin_row(g, _("Indent from left"), unit(r), -10, 30, 0.1, to_unit(r, t.indent), 2);
            var fixed = switch_row(g, _("Fixed column widths"), null, t.fixed_layout);
            var banded = switch_row(g, _("Banded rows"), null, t.look_banded_rows);
            var first = switch_row(g, _("Header row formatting"), null, t.look_first_row);
            box.append(g);
            var rg = new PreferencesGroup(_("Row"));
            var height = spin_row(rg, _("Height"), _("points, 0 for automatic"), 0, 800, 1, row.height, 0);
            var exact = switch_row(rg, _("Exact height"), null, row.height_exact);
            var split = switch_row(rg, _("Allow row to break across pages"), null, !row.cant_split);
            var hdr = switch_row(rg, _("Repeat as header row"), null, row.header);
            box.append(rg);
            var cg = new PreferencesGroup(_("Column and cell"));
            int gc = t.grid_col(row, cell);
            var width = spin_row(cg, _("Column width"), unit(r), 0.2, 60, 0.1, to_unit(r, gc < t.grid.length ? t.grid[gc] : 72), 2);
            var valign = drop_row(cg, _("Vertical alignment"), { _("Top"), _("Center"), _("Bottom") }, (int) cell.valign);
            var shade = color_row(cg, _("Cell shading"), cell.shading ?? "#ffffff");
            var noshade = switch_row(cg, _("No shading"), null, cell.shading == null);
            box.append(cg);
            var bg = new PreferencesGroup(_("Borders"));
            var borders = drop_row(bg, _("Borders"), { _("Keep"), _("All borders"), _("Outside only"), _("No borders") }, 0);
            var bcolor = color_row(bg, _("Border color"), "#000000");
            var bwidth = spin_row(bg, _("Border width"), _("points"), 0.25, 6, 0.25, 0.5, 2);
            box.append(bg);
            var ag = new PreferencesGroup(_("Alt text"));
            var cap = entry_row(ag, _("Title"), t.caption);
            var desc = entry_row(ag, _("Description"), t.description);
            box.append(ag);
            footer(dlg, _("Apply"), () => {
                r.ed.checkpoint(_("Table Properties"));
                t.align = al.selected == 1 ? Write.Align.CENTER : (al.selected == 2 ? Write.Align.RIGHT : Write.Align.LEFT);
                t.indent = from_unit(r, indent.value);
                t.fixed_layout = fixed.active;
                t.look_banded_rows = banded.active;
                t.look_first_row = first.active;
                row.height = height.value;
                row.height_exact = exact.active;
                row.cant_split = !split.active;
                row.header = hdr.active;
                if (gc < t.grid.length) {
                    double[] g2 = t.grid;
                    g2[gc] = from_unit(r, width.value);
                    t.grid = g2;
                }
                cell.valign = (CellVAlign) valign.selected;
                cell.shading = noshade.active ? null : hex_of(shade);
                string col = hex_of(bcolor);
                double w = bwidth.value;
                switch ((int) borders.selected) {
                    case 1:
                        t.border_top = new Write.Border.with("single", w, col);
                        t.border_bottom = new Write.Border.with("single", w, col);
                        t.border_left = new Write.Border.with("single", w, col);
                        t.border_right = new Write.Border.with("single", w, col);
                        t.border_h = new Write.Border.with("single", w, col);
                        t.border_v = new Write.Border.with("single", w, col);
                        break;
                    case 2:
                        t.border_top = new Write.Border.with("single", w, col);
                        t.border_bottom = new Write.Border.with("single", w, col);
                        t.border_left = new Write.Border.with("single", w, col);
                        t.border_right = new Write.Border.with("single", w, col);
                        t.border_h = new Write.Border.with("none", 0, col);
                        t.border_v = new Write.Border.with("none", 0, col);
                        break;
                    case 3:
                        t.border_top = new Write.Border.with("none", 0, col);
                        t.border_bottom = new Write.Border.with("none", 0, col);
                        t.border_left = new Write.Border.with("none", 0, col);
                        t.border_right = new Write.Border.with("none", 0, col);
                        t.border_h = new Write.Border.with("none", 0, col);
                        t.border_v = new Write.Border.with("none", 0, col);
                        break;
                    default:
                        break;
                }
                t.caption = cap.text;
                t.description = desc.text;
                r.touch_all();
            });
            dlg.present();
        }

        public static void table_alt(WriteRichEditor r, Table t, owned Apply? after = null) {
            var dlg = make(r, _("Table Alt Text"), 420, 300);
            var box = body(dlg);
            var g = new PreferencesGroup();
            var cap = entry_row(g, _("Title"), t.caption);
            var desc = entry_row(g, _("Description"), t.description);
            box.append(g);
            footer(dlg, _("Save"), () => {
                r.ed.checkpoint(_("Alt Text"));
                t.caption = cap.text;
                t.description = desc.text;
                r.modified = true;
                r.title_changed();
                if (after != null) after();
            });
            dlg.present();
        }

        public static void sort_table(WriteRichEditor r) {
            var t = r.ed.table_at(r.ed.focus);
            if (t == null) {
                r.toast(_("Place the cursor in a table first."));
                return;
            }
            var dlg = make(r, _("Sort"), 380, 320);
            var box = body(dlg);
            var g = new PreferencesGroup();
            string[] cols = {};
            for (int i = 0; i < t.columns(); i++) {
                var hc = t.rows.size > 0 ? t.cell_at_grid(t.rows[0], i) : null;
                string label = hc != null && t.rows[0].header && hc.plain_text().strip() != "" ? hc.plain_text().strip() : _("Column %d").printf(i + 1);
                cols += label;
            }
            var col = drop_row(g, _("Sort by"), cols, 0);
            var type = drop_row(g, _("Type"), { _("Text"), _("Number") }, 0);
            var order = drop_row(g, _("Order"), { _("Ascending"), _("Descending") }, 0);
            box.append(g);
            footer(dlg, _("Sort"), () => {
                r.ed.checkpoint(_("Sort"));
                r.ed.sort_table((int) col.selected, order.selected == 1, type.selected == 1);
            });
            dlg.present();
        }

        public static void table_formula(WriteRichEditor r) {
            var dlg = make(r, _("Formula"), 400, 300);
            var box = body(dlg);
            var g = new PreferencesGroup(_("Formula"), _("Examples: =SUM(ABOVE), =AVERAGE(LEFT), =2*PI, =ROUND(3.456,2)"));
            var f = entry_row(g, _("Formula"), r.ed.cell_at(r.ed.focus) != null ? "=SUM(ABOVE)" : "=");
            var fmtr = entry_row(g, _("Number format"), "");
            box.append(g);
            footer(dlg, _("Insert"), () => {
                string code = f.text.strip();
                if (!code.has_prefix("=")) code = "=" + code;
                if (fmtr.text.strip() != "") code += " \\# \"" + fmtr.text.strip() + "\"";
                r.ed.checkpoint(_("Insert Formula"));
                r.ed.insert_inline(new FieldRun(code, ""));
                r.update_fields();
            });
            dlg.present();
        }

        public static void text_to_table(WriteRichEditor r) {
            if (!r.ed.has_selection) {
                r.toast(_("Select the paragraphs to convert first."));
                return;
            }
            var dlg = make(r, _("Convert Text to Table"), 380, 280);
            var box = body(dlg);
            var g = new PreferencesGroup();
            var sep = drop_row(g, _("Separate text at"), { _("Tabs"), _("Commas"), _("Semicolons") }, 0);
            box.append(g);
            footer(dlg, _("Convert"), () => {
                var paras = r.ed.selected_paragraphs();
                if (paras.size == 0 || paras[0].parent == null) return;
                var list = paras[0].parent;
                foreach (var p in paras) if (p.parent != list) return;
                r.ed.checkpoint(_("Convert Text to Table"));
                string delim = sep.selected == 0 ? "\t" : (sep.selected == 1 ? "," : ";");
                var rows = new Gee.ArrayList<Gee.ArrayList<Paragraph>>();
                int ncols = 1;
                foreach (var p in paras) {
                    var cells = new Gee.ArrayList<Paragraph>();
                    var curp = p.shell();
                    foreach (var it in p.inlines) {
                        if ((delim == "\t" && it is Tab) ) {
                            cells.add(curp);
                            curp = p.shell();
                            continue;
                        }
                        var tr = it as TextRun;
                        if (tr != null && delim != "\t" && tr.text.contains(delim)) {
                            string[] parts = tr.text.split(delim);
                            for (int i = 0; i < parts.length; i++) {
                                if (i > 0) {
                                    cells.add(curp);
                                    curp = p.shell();
                                }
                                if (parts[i] != "") curp.inlines.add(new TextRun(parts[i].strip(), tr.props));
                            }
                            continue;
                        }
                        curp.inlines.add(it.copy());
                    }
                    cells.add(curp);
                    ncols = int.max(ncols, cells.size);
                    rows.add(cells);
                }
                var s = r.doc.section_for(paras[0]);
                var t = Table.create(rows.size, ncols, s.column_width());
                for (int i = 0; i < rows.size; i++) {
                    for (int k = 0; k < ncols; k++) {
                        var c = t.rows[i].cells[k];
                        c.blocks.clear();
                        c.blocks.add(k < rows[i].size ? rows[i][k] : new Paragraph());
                    }
                }
                int idx = list.items.index_of(paras[0]);
                foreach (var p in paras) list.items.remove(p);
                list.insert(idx, t);
                if (idx + 1 >= list.size) list.add(new Paragraph());
                r.ed.set_caret(new Pos(t.rows[0].cells[0].blocks.first_paragraph(), 0));
                r.ed.changed();
            });
            dlg.present();
        }

        public static void pick_picture(WriteRichEditor r) {
            var fd = new Gtk.FileDialog();
            fd.title = _("Insert Picture");
            var filter = new Gtk.FileFilter();
            filter.name = _("Images");
            foreach (string m in new string[] { "image/png", "image/jpeg", "image/gif", "image/webp", "image/svg+xml", "image/bmp", "image/tiff" }) filter.add_mime_type(m);
            var fl = new GLib.ListStore(typeof(Gtk.FileFilter));
            fl.append(filter);
            fd.filters = fl;
            fd.open.begin(r.window, null, (o, res) => {
                try {
                    var f = fd.open.end(res);
                    if (f != null) r.insert_picture_file(f);
                } catch (Error e) {
                }
            });
        }

        public static void object_properties(WriteRichEditor r, FloatingInline obj) {
            var dlg = make(r, (obj is ImageRun) ? _("Picture") : ((obj is Write.ChartRun) ? _("Chart") : _("Shape")), 480, 680);
            var box = body(dlg);
            var g = new PreferencesGroup(_("Size"));
            var w = spin_row(g, _("Width"), unit(r), 0.1, 60, 0.05, to_unit(r, obj.width), 2);
            var h = spin_row(g, _("Height"), unit(r), 0.05, 60, 0.05, to_unit(r, obj.height), 2);
            var lock = switch_row(g, _("Lock aspect ratio"), null, obj is ImageRun);
            double ratio = obj.width > 0 ? obj.height / obj.width : 1;
            bool guard = false;
            w.spin_btn.value_changed.connect(() => {
                if (guard || !lock.active) return;
                guard = true;
                h.value = w.value * ratio;
                guard = false;
            });
            h.spin_btn.value_changed.connect(() => {
                if (guard || !lock.active) return;
                guard = true;
                w.value = h.value / ratio;
                guard = false;
            });
            SpinRow? rot = (obj is ShapeRun) ? spin_row(g, _("Rotation"), _("degrees"), -360, 360, 1, ((ShapeRun) obj).rotation, 0) : null;
            box.append(g);
            var wg = new PreferencesGroup(_("Text wrapping"));
            string[] wraps = { _("In line with text"), _("Square"), _("Tight"), _("Top and bottom"), _("Behind text"), _("In front of text") };
            var wrap = drop_row(wg, _("Wrap"), wraps, (int) obj.wrap);
            var halign = drop_row(wg, _("Horizontal alignment"), { _("By offset"), _("Left"), _("Center"), _("Right") }, (int) obj.halign);
            var hrel = drop_row(wg, _("Horizontal relative to"), { _("Column"), _("Margin"), _("Page"), _("Character") }, (int) obj.hrel);
            var hoff = spin_row(wg, _("Horizontal offset"), unit(r), -30, 60, 0.1, to_unit(r, obj.hoff), 2);
            var vrel = drop_row(wg, _("Vertical relative to"), { _("Paragraph"), _("Margin"), _("Page"), _("Line") }, (int) obj.vrel);
            var voff = spin_row(wg, _("Vertical offset"), unit(r), -30, 60, 0.1, to_unit(r, obj.voff), 2);
            var dist = spin_row(wg, _("Distance from text"), _("points"), 0, 72, 1, obj.dist, 0);
            box.append(wg);
            SpinRow? cl = null, ct = null, cr = null, cb = null, br = null;
            SwitchRow? gray = null;
            Gtk.ColorDialogButton? fill = null, stroke = null;
            SwitchRow? nofill = null, nostroke = null;
            SpinRow? sw = null;
            if (obj is ImageRun) {
                var img = (ImageRun) obj;
                var cg = new PreferencesGroup(_("Crop and adjust"), _("Crop as a percentage of each side"));
                cl = spin_row(cg, _("Left"), "%", 0, 95, 1, img.crop_l * 100, 0);
                ct = spin_row(cg, _("Top"), "%", 0, 95, 1, img.crop_t * 100, 0);
                cr = spin_row(cg, _("Right"), "%", 0, 95, 1, img.crop_r * 100, 0);
                cb = spin_row(cg, _("Bottom"), "%", 0, 95, 1, img.crop_b * 100, 0);
                br = spin_row(cg, _("Brightness"), "%", -100, 100, 5, img.brightness * 100, 0);
                gray = switch_row(cg, _("Grayscale"), null, img.grayscale);
                box.append(cg);
            } else if (obj is ShapeRun) {
                var s = (ShapeRun) obj;
                var sg = new PreferencesGroup(_("Fill and outline"));
                fill = color_row(sg, _("Fill color"), s.fill ?? "#ffffff");
                nofill = switch_row(sg, _("No fill"), null, s.fill == null);
                stroke = color_row(sg, _("Outline color"), s.stroke ?? "#000000");
                nostroke = switch_row(sg, _("No outline"), null, s.stroke == null);
                sw = spin_row(sg, _("Outline width"), _("points"), 0.25, 20, 0.25, s.stroke_width, 2);
                box.append(sg);
            }
            var ag = new PreferencesGroup(_("Alt text"));
            var title = entry_row(ag, _("Title"), obj.title);
            var alt = entry_row(ag, _("Description"), obj.alt);
            box.append(ag);
            footer(dlg, _("Apply"), () => {
                r.ed.checkpoint(_("Object Properties"));
                obj.width = from_unit(r, w.value);
                obj.height = from_unit(r, h.value);
                obj.wrap = (Wrap) wrap.selected;
                obj.halign = (HAlignObj) halign.selected;
                obj.hrel = (HRel) hrel.selected;
                obj.hoff = from_unit(r, hoff.value);
                obj.vrel = (VRel) vrel.selected;
                obj.voff = from_unit(r, voff.value);
                obj.dist = dist.value;
                obj.title = title.text;
                obj.alt = alt.text;
                if (obj is ImageRun) {
                    var img = (ImageRun) obj;
                    img.crop_l = cl.value / 100;
                    img.crop_t = ct.value / 100;
                    img.crop_r = cr.value / 100;
                    img.crop_b = cb.value / 100;
                    img.brightness = br.value / 100;
                    img.grayscale = gray.active;
                } else if (obj is ShapeRun) {
                    var s = (ShapeRun) obj;
                    s.fill = nofill.active ? null : hex_of(fill);
                    s.stroke = nostroke.active ? null : hex_of(stroke);
                    s.stroke_width = sw.value;
                    if (rot != null) s.rotation = rot.value;
                }
                r.touch_all();
            });
            dlg.present();
        }

        public static void alt_text(WriteRichEditor r, FloatingInline obj, owned Apply? after = null) {
            var dlg = make(r, _("Alt Text"), 420, 320);
            var box = body(dlg);
            var g = new PreferencesGroup(_("Description"), _("Describe the object for people who cannot see it."));
            var title = entry_row(g, _("Title"), obj.title);
            var alt = entry_row(g, _("Description"), obj.alt);
            var deco = switch_row(g, _("Decorative"), _("The object adds no information"), obj.alt == "" && obj.title == "decorative");
            box.append(g);
            footer(dlg, _("Save"), () => {
                r.ed.checkpoint(_("Alt Text"));
                obj.title = deco.active ? "decorative" : title.text;
                obj.alt = deco.active ? " " : alt.text;
                r.modified = true;
                r.title_changed();
                if (after != null) after();
            });
            dlg.present();
        }

        public static void wordart(WriteRichEditor r) {
            var dlg = make(r, _("WordArt"), 400, 260);
            var box = body(dlg);
            var g = new PreferencesGroup();
            var text = entry_row(g, _("Text"), r.ed.has_selection ? r.ed.selected_text() : _("Your text here"));
            box.append(g);
            footer(dlg, _("Insert"), () => r.insert_wordart(text.text));
            dlg.present();
        }

        public static void chart(WriteRichEditor r, Write.ChartRun? existing = null) {
            var old = existing != null ? ChartSupport.spec_of(existing) : null;
            var dlg = make(r, existing != null ? _("Edit Chart") : _("Insert Chart"), 500, 600);
            var box = body(dlg);
            var g = new PreferencesGroup(_("Data"), _("Type the data as a table: the first row names the series, the first column names the categories. Separate cells with commas, semicolons or tabs."));
            Singularity.Charts.ChartType[] kinds = {
                Singularity.Charts.ChartType.COLUMN, Singularity.Charts.ChartType.BAR, Singularity.Charts.ChartType.LINE,
                Singularity.Charts.ChartType.AREA, Singularity.Charts.ChartType.PIE, Singularity.Charts.ChartType.DOUGHNUT,
                Singularity.Charts.ChartType.SCATTER, Singularity.Charts.ChartType.RADAR
            };
            string[] names = { _("Column"), _("Bar"), _("Line"), _("Area"), _("Pie"), _("Doughnut"), _("Scatter"), _("Radar") };
            int sel = 0;
            if (old != null) for (int i = 0; i < kinds.length; i++) if (kinds[i] == old.kind) sel = i;
            var type = drop_row(g, _("Chart type"), names, sel);
            var title = entry_row(g, _("Title"), old != null ? old.title : "");
            var legend = switch_row(g, _("Show legend"), null, old == null || old.legend != Singularity.Charts.LegendPosition.NONE);
            var labels = switch_row(g, _("Data labels"), null, old != null && old.data_labels);
            box.append(g);
            var tv = new Gtk.TextView();
            tv.buffer.text = old != null ? ChartSupport.table_text(old) : _("Quarter, Sales, Costs\nQ1, 12, 8\nQ2, 19, 11\nQ3, 7, 6\nQ4, 15, 9");
            tv.monospace = true;
            tv.height_request = 160;
            tv.add_css_class("write-chart-data");
            box.append(tv);
            footer(dlg, existing != null ? _("Save") : _("Insert"), () => {
                var spec = ChartSupport.parse(tv.buffer.text, old);
                if (spec == null) {
                    r.toast(_("The data needs a header row and at least one row of values."));
                    return;
                }
                spec.kind = kinds[type.selected];
                spec.title = title.text.strip();
                spec.legend = legend.active ? (old != null && old.legend != Singularity.Charts.LegendPosition.NONE ? old.legend : Singularity.Charts.LegendPosition.RIGHT) : Singularity.Charts.LegendPosition.NONE;
                spec.data_labels = labels.active;
                spec.vary_colors = spec.kind == Singularity.Charts.ChartType.PIE || spec.kind == Singularity.Charts.ChartType.DOUGHNUT;
                if (existing != null) {
                    r.ed.checkpoint(_("Edit Chart"));
                    ChartSupport.apply(existing, spec);
                    var p = r.find_para_of(existing);
                    if (p != null) p.touch();
                    r.ed.changed();
                } else {
                    var ch = new Write.ChartRun();
                    ChartSupport.apply(ch, spec);
                    r.ed.checkpoint(_("Insert Chart"));
                    r.ed.insert_inline(ch);
                }
            });
            dlg.present();
        }

        public static void symbol(WriteRichEditor r) {
            var dlg = make(r, _("Symbol"), 520, 520);
            var box = body(dlg);
            var search = new Gtk.SearchEntry();
            search.placeholder_text = _("Search by name or code, for example U+00B6");
            box.append(search);
            var flow = new Gtk.FlowBox();
            flow.max_children_per_line = 12;
            flow.selection_mode = SelectionMode.NONE;
            flow.homogeneous = true;
            box.append(flow);
            int[] codes = {
                0x2013, 0x2014, 0x00a9, 0x00ae, 0x2122, 0x00a7, 0x00b6, 0x2020, 0x2021, 0x2022,
                0x2026, 0x2030, 0x00b0, 0x00b1, 0x00d7, 0x00f7, 0x2260, 0x2264, 0x2265, 0x2248,
                0x221e, 0x221a, 0x2211, 0x220f, 0x222b, 0x2202, 0x2206, 0x2207, 0x2208, 0x2209,
                0x2229, 0x222a, 0x2282, 0x2283, 0x2200, 0x2203, 0x00ac, 0x2227, 0x2228, 0x03b1,
                0x03b2, 0x03b3, 0x03b4, 0x03b5, 0x03b6, 0x03b7, 0x03b8, 0x03b9, 0x03ba, 0x03bb,
                0x03bc, 0x03bd, 0x03be, 0x03c0, 0x03c1, 0x03c3, 0x03c4, 0x03c5, 0x03c6, 0x03c7,
                0x03c8, 0x03c9, 0x0393, 0x0394, 0x0398, 0x039b, 0x039e, 0x03a0, 0x03a3, 0x03a6,
                0x03a8, 0x03a9, 0x20ac, 0x00a3, 0x00a5, 0x00a2, 0x20b9, 0x20bd, 0x20a9, 0x20ba,
                0x00a4, 0x00bd, 0x00bc, 0x00be, 0x2153, 0x2154, 0x215b, 0x00b9, 0x00b2, 0x00b3,
                0x2070, 0x2074, 0x2075, 0x2076, 0x2080, 0x2081, 0x2082, 0x2018, 0x2019, 0x201c,
                0x201d, 0x00ab, 0x00bb, 0x2039, 0x203a, 0x00a1, 0x00bf, 0x00e0, 0x00e8, 0x00e9,
                0x00ec, 0x00f2, 0x00f9, 0x00c0, 0x00c8, 0x00c9, 0x00e7, 0x00f1, 0x00fc, 0x00f6,
                0x00e4, 0x00df, 0x00e6, 0x00f8, 0x00e5, 0x2605, 0x2606, 0x2713, 0x2714, 0x2717,
                0x2610, 0x2611, 0x2612, 0x25cf, 0x25cb, 0x25a0, 0x25a1, 0x25b2, 0x25b3, 0x25c6,
                0x25c7, 0x2660, 0x2663, 0x2665, 0x2666, 0x266a, 0x263a, 0x2600, 0x2601, 0x2602,
                0x260e, 0x2709, 0x270e
            };
            var chars = new Gee.ArrayList<string>();
            foreach (int cp in codes) chars.add(((unichar) cp).to_string());
            Apply fill = () => {};
            fill = () => {
                Widget? w;
                while ((w = flow.get_first_child()) != null) flow.remove(w);
                string q = search.text.strip().up();
                var list = new Gee.ArrayList<string>();
                if (q.has_prefix("U+") && q.length > 2) {
                    int64 v;
                    if (int64.try_parse("0x" + q.substring(2), out v) && v > 0 && v < 0x10FFFF) list.add(((unichar) v).to_string());
                }
                foreach (string c in chars) {
                    if (q == "" || "U+%04X".printf((uint) c.get_char(0)).contains(q)) list.add(c);
                }
                foreach (string c in list) {
                    var b = new Gtk.Button.with_label(c);
                    b.add_css_class("flat");
                    b.add_css_class("write-symbol");
                    b.tooltip_text = "U+%04X".printf((uint) c.get_char(0));
                    string ch = c;
                    b.clicked.connect(() => {
                        r.ed.checkpoint(_("Insert Symbol"), true);
                        r.ed.insert_text(ch, r.view.pending ?? r.ed.props_for_insert());
                    });
                    flow.append(b);
                }
            };
            search.search_changed.connect(() => fill());
            fill();
            close_footer(dlg);
            dlg.present();
        }

        public static Gee.ArrayList<string> bookmarks(Write.Document doc) {
            var list = new Gee.ArrayList<string>();
            foreach (var p in Story.all(doc)) foreach (var i in p.inlines) if (i is Mark && ((Mark) i).kind == MarkKind.BOOKMARK_START && !list.contains(((Mark) i).name)) list.add(((Mark) i).name);
            return list;
        }

        public static void bookmark(WriteRichEditor r) {
            var dlg = make(r, _("Bookmark"), 420, 480);
            var box = body(dlg);
            var g = new PreferencesGroup(_("New bookmark"));
            var name = entry_row(g, _("Name"), "");
            box.append(g);
            var lg = new PreferencesGroup(_("Bookmarks"));
            foreach (string b in bookmarks(r.doc)) {
                if (b.has_prefix("_")) continue;
                var row = new ActionRow(b);
                var go = new Button.with_label(_("Go To"));
                go.valign = Gtk.Align.CENTER;
                string bn = b;
                go.clicked.connect(() => {
                    foreach (var p in Story.all(r.doc)) foreach (var i in p.inlines) if (i is Mark && ((Mark) i).name == bn) {
                        r.view.scroll_to_para(p);
                        dlg.close();
                        return;
                    }
                });
                row.add_suffix(go);
                var del = new Button.from_icon_name("user-trash-symbolic");
                del.valign = Gtk.Align.CENTER;
                del.add_css_class("flat");
                del.clicked.connect(() => {
                    r.ed.checkpoint(_("Delete Bookmark"));
                    foreach (var p in Story.all(r.doc)) {
                        for (int k = p.inlines.size - 1; k >= 0; k--) {
                            var m = p.inlines[k] as Mark;
                            if (m != null && (m.kind == MarkKind.BOOKMARK_START || m.kind == MarkKind.BOOKMARK_END) && m.name == bn) p.inlines.remove_at(k);
                        }
                    }
                    r.ed.changed();
                    lg.remove_row(row);
                });
                row.add_suffix(del);
                lg.add_row(row);
            }
            box.append(lg);
            footer(dlg, _("Add"), () => {
                string n = name.text.strip().replace(" ", "_");
                if (n == "") return;
                r.ed.checkpoint(_("Bookmark"));
                Pos a, b;
                r.ed.ordered(out a, out b);
                int bi = b.para.split_at(b.offset);
                b.para.inlines.insert(bi, new Mark(MarkKind.BOOKMARK_END, n));
                int ai = a.para.split_at(a.offset);
                a.para.inlines.insert(ai, new Mark(MarkKind.BOOKMARK_START, n));
                a.para.touch();
                r.ed.changed();
            });
            dlg.present();
        }

        public static void hyperlink(WriteRichEditor r) {
            var ed = r.ed;
            string url = "";
            var it = ed.focus.para.inline_at(ed.focus.offset);
            if (it != null && it.props.link != null) url = it.props.link;
            var dlg = make(r, _("Link"), 440, 420);
            var box = body(dlg);
            var g = new PreferencesGroup();
            var text = entry_row(g, _("Text to display"), ed.has_selection ? ed.selected_text() : "");
            var addr = entry_row(g, _("Address"), url);
            box.append(g);
            var targets = new PreferencesGroup(_("Place in this document"));
            foreach (var p in Story.paragraphs(r.doc.body)) {
                if (r.doc.styles.outline_level(p) < 0 || !p.style.has_prefix("Heading")) continue;
                string ht = p.plain_text().strip();
                if (ht == "") continue;
                var row = new ActionRow(ht);
                var para = p;
                row.activated.connect(() => {
                    string bm = FieldUpdater.ensure_bookmark(r.doc, para, "_Ref");
                    addr.text = "#" + bm;
                    if (text.text == "") text.text = ht;
                });
                targets.add_row(row);
            }
            foreach (string b in bookmarks(r.doc)) {
                if (b.has_prefix("_")) continue;
                var row = new ActionRow(b, _("Bookmark"));
                string bn = b;
                row.activated.connect(() => addr.text = "#" + bn);
                targets.add_row(row);
            }
            box.append(targets);
            footer(dlg, _("Apply"), () => {
                string a = addr.text.strip();
                if (a != "" && !a.has_prefix("#") && !a.contains(":") && a.contains("@")) a = "mailto:" + a;
                else if (a != "" && !a.has_prefix("#") && !a.contains("://") && !a.has_prefix("mailto:")) a = "https://" + a;
                ed.checkpoint(_("Link"));
                if (!ed.has_selection) {
                    if (it != null && it.props.link != null) {
                        int off = ed.focus.para.offset_of(it);
                        ed.select(new Pos(ed.focus.para, off), new Pos(ed.focus.para, off + it.length));
                    } else {
                        string t = text.text != "" ? text.text : addr.text;
                        var c = ed.props_for_insert();
                        c.link = a;
                        c.style = "Hyperlink";
                        ed.insert_text(t, c);
                        return;
                    }
                } else if (text.text != "" && text.text != ed.selected_text()) {
                    Pos s0, e0;
                    ed.ordered(out s0, out e0);
                    var c = s0.para.props_at(s0.offset + 1);
                    c.link = a;
                    c.style = "Hyperlink";
                    ed.delete_selection();
                    ed.insert_text(text.text, c);
                    return;
                }
                ed.format_chars((c) => {
                    c.link = a == "" ? null : a;
                    c.style = a == "" ? null : "Hyperlink";
                });
            });
            dlg.present();
        }

        public static void cross_reference(WriteRichEditor r) {
            var dlg = make(r, _("Cross-reference"), 480, 560);
            var box = body(dlg);
            var g = new PreferencesGroup();
            var kind = drop_row(g, _("Reference type"), { _("Heading"), _("Figure"), _("Table"), _("Equation"), _("Bookmark"), _("Footnote") }, 0);
            var what = drop_row(g, _("Insert reference to"), { _("Text"), _("Page number"), _("Above or below") }, 0);
            var link = switch_row(g, _("Insert as hyperlink"), null, true);
            box.append(g);
            var items = new PreferencesGroup(_("For which"));
            box.append(items);
            var targets = new Gee.ArrayList<Paragraph?>();
            var names = new Gee.ArrayList<string>();
            Gtk.ListBox? current_list = null;
            Apply fill = () => {};
            string? chosen = null;
            fill = () => {
                items.clear();
                targets.clear();
                names.clear();
                chosen = null;
                int k = (int) kind.selected;
                if (k == 0) {
                    foreach (var p in Story.paragraphs(r.doc.body)) if (r.doc.styles.outline_level(p) >= 0 && p.style.has_prefix("Heading") && p.plain_text().strip() != "") {
                        targets.add(p);
                        names.add(p.plain_text().strip());
                    }
                } else if (k >= 1 && k <= 3) {
                    string label = k == 1 ? "Figure" : (k == 2 ? "Table" : "Equation");
                    foreach (var p in Story.paragraphs(r.doc.body)) foreach (var i in p.inlines) {
                        var f = i as FieldRun;
                        if (f != null && f.kind() == "SEQ" && f.args().length > 1 && f.args()[1] == label) {
                            targets.add(p);
                            names.add(p.plain_text().strip());
                        }
                    }
                } else if (k == 4) {
                    foreach (string b in bookmarks(r.doc)) if (!b.has_prefix("_")) {
                        targets.add(null);
                        names.add(b);
                    }
                } else {
                    int n = 0;
                    foreach (var note in r.doc.notes(NoteKind.FOOTNOTE)) {
                        n++;
                        targets.add(null);
                        var fp = note.blocks.first_paragraph();
                        names.add("%d  %s".printf(n, fp != null ? fp.plain_text() : ""));
                    }
                }
                for (int i = 0; i < names.size; i++) {
                    var row = new ActionRow(names[i]);
                    int idx = i;
                    row.activated.connect(() => {
                        chosen = idx.to_string();
                        foreach (var w in items.get_rows()) w.remove_css_class("selected");
                        row.add_css_class("selected");
                    });
                    items.add_row(row);
                }
            };
            kind.notify["selected"].connect(() => fill());
            fill();
            footer(dlg, _("Insert"), () => {
                if (chosen == null) return;
                int idx = int.parse(chosen);
                int k = (int) kind.selected;
                string bm = "";
                if (k == 4) bm = names[idx];
                else if (k == 5) {
                    int n = 0;
                    foreach (var p in Story.paragraphs(r.doc.body)) {
                        for (int i = 0; i < p.inlines.size; i++) {
                            var nr = p.inlines[i] as NoteRef;
                            if (nr == null || nr.note.kind != NoteKind.FOOTNOTE) continue;
                            if (n++ == idx) {
                                bm = FieldUpdater.new_bookmark_name(r.doc, "_Ref");
                                p.inlines.insert(i, new Mark(MarkKind.BOOKMARK_START, bm));
                                p.inlines.insert(i + 2, new Mark(MarkKind.BOOKMARK_END, bm));
                                break;
                            }
                        }
                        if (bm != "") break;
                    }
                } else {
                    var tp = targets[idx];
                    string? existing = null;
                    foreach (var i in tp.inlines) if (i is Mark && ((Mark) i).kind == MarkKind.BOOKMARK_START && ((Mark) i).name.has_prefix("_Ref")) existing = ((Mark) i).name;
                    bm = existing ?? FieldUpdater.ensure_bookmark(r.doc, tp, "_Ref");
                }
                string code;
                int w = (int) what.selected;
                if (k == 5 && w == 0) code = "NOTEREF %s".printf(bm);
                else if (w == 1) code = "PAGEREF %s".printf(bm);
                else if (w == 2) code = "PAGEREF %s \\p".printf(bm);
                else code = "REF %s".printf(bm);
                if (link.active) code += " \\h";
                r.ed.checkpoint(_("Cross-reference"));
                var f = new FieldRun(code, "");
                r.ed.insert_inline(f);
                r.update_fields();
            });
            dlg.present();
        }

        public static void caption(WriteRichEditor r) {
            var dlg = make(r, _("Caption"), 420, 360);
            var box = body(dlg);
            var g = new PreferencesGroup();
            var label = drop_row(g, _("Label"), { _("Figure"), _("Table"), _("Equation") }, r.ed.table_at(r.ed.focus) != null ? 1 : 0);
            var text = entry_row(g, _("Caption text"), "");
            var pos = drop_row(g, _("Position"), { _("Below selected item"), _("Above selected item") }, r.ed.table_at(r.ed.focus) != null ? 1 : 0);
            box.append(g);
            footer(dlg, _("Insert"), () => {
                string[] names = { "Figure", "Table", "Equation" };
                var cap = FieldUpdater.make_caption(r.doc, names[label.selected], text.text);
                r.ed.checkpoint(_("Insert Caption"));
                Block anchor = r.ed.focus.para;
                var t = r.ed.table_at(r.ed.focus);
                if (t != null) anchor = t;
                var list = anchor.parent;
                if (list == null) return;
                int i = list.items.index_of(anchor);
                list.insert(pos.selected == 1 ? i : i + 1, cap);
                r.update_fields();
                r.ed.set_caret(new Pos(cap, cap.length));
            });
            dlg.present();
        }

        public static void field(WriteRichEditor r) {
            var dlg = make(r, _("Field"), 460, 520);
            var box = body(dlg);
            var g = new PreferencesGroup();
            string[] codes = { "PAGE", "NUMPAGES", "SECTIONPAGES", "DATE \\@ \"d MMMM yyyy\"", "TIME \\@ \"HH:mm\"", "CREATEDATE", "SAVEDATE", "AUTHOR", "TITLE", "SUBJECT", "KEYWORDS", "FILENAME", "NUMWORDS", "NUMCHARS", "USERNAME", "DOCPROPERTY Company", "MERGEFIELD Name", "SEQ Figure", "= 1+1" };
            string[] labels = new string[codes.length];
            for (int i = 0; i < codes.length; i++) labels[i] = Fields.display_name(codes[i]) + "  (" + codes[i] + ")";
            var kind = drop_row(g, _("Field"), labels, 0);
            var code = entry_row(g, _("Field code"), codes[0]);
            kind.notify["selected"].connect(() => code.text = codes[kind.selected]);
            var lock = switch_row(g, _("Lock result"), _("Do not update this field"), false);
            box.append(g);
            footer(dlg, _("Insert"), () => {
                r.ed.checkpoint(_("Insert Field"));
                var f = new FieldRun(code.text.strip(), "");
                f.locked = lock.active;
                r.ed.insert_inline(f);
                r.update_fields();
            });
            dlg.present();
        }

        public static void date_time(WriteRichEditor r) {
            var dlg = make(r, _("Date and Time"), 420, 520);
            var box = body(dlg);
            var g = new PreferencesGroup(_("Available formats"));
            string[] pics = { "d MMMM yyyy", "dd/MM/yyyy", "MM/dd/yyyy", "yyyy-MM-dd", "dddd d MMMM yyyy", "d MMM yy", "MMMM yyyy", "HH:mm", "h:mm am/pm", "dd/MM/yyyy HH:mm" };
            var now = new DateTime.now_local();
            var update = new SwitchRow(_("Update automatically"), _("Insert as a field"), true);
            foreach (string pic in pics) {
                var row = new ActionRow(Fields.date_picture(now, pic), pic);
                string pc = pic;
                row.activated.connect(() => {
                    r.ed.checkpoint(_("Insert Date"));
                    if (update.active) {
                        var f = new FieldRun((pc.contains("H") || pc.contains("h") ? "TIME" : "DATE") + " \\@ \"" + pc + "\"", Fields.date_picture(now, pc));
                        f.dirty = false;
                        r.ed.insert_inline(f);
                    } else {
                        r.ed.insert_text(Fields.date_picture(now, pc), r.view.pending ?? r.ed.props_for_insert());
                    }
                    dlg.close();
                });
                g.add_row(row);
            }
            box.append(g);
            var o = new PreferencesGroup();
            o.add_row(update);
            box.append(o);
            close_footer(dlg);
            dlg.present();
        }

        public static void page_numbers(WriteRichEditor r, string where) {
            var dlg = make(r, _("Page Numbers"), 420, 420);
            var box = body(dlg);
            var g = new PreferencesGroup();
            var pos = drop_row(g, _("Position"), { _("Bottom of page"), _("Top of page") }, where == "header" ? 1 : 0);
            var al = drop_row(g, _("Alignment"), { _("Left"), _("Center"), _("Right") }, 1);
            var style = drop_row(g, _("Format"), { "1, 2, 3", _("Page 1 of 3"), "i, ii, iii", "I, II, III", "a, b, c" }, 0);
            var first = switch_row(g, _("Show number on first page"), null, true);
            var s0 = r.doc.section_for(r.ed.focus.para);
            var start = spin_row(g, _("Start at"), _("0 continues from the previous section"), 0, 9999, 1, s0.page_start >= 0 ? s0.page_start : 0, 0);
            box.append(g);
            footer(dlg, _("Insert"), () => {
                r.ed.checkpoint(_("Page Numbers"));
                var s = r.doc.section_for(r.ed.focus.para);
                var p = new Paragraph(pos.selected == 1 ? "Header" : "Footer");
                p.props.align = al.selected == 0 ? Write.Align.LEFT : (al.selected == 1 ? Write.Align.CENTER : Write.Align.RIGHT);
                p.props.tabs = new Gee.ArrayList<TabStop>();
                if (style.selected == 1) {
                    p.inlines.add(new TextRun(_("Page") + " "));
                    p.inlines.add(new FieldRun("PAGE", "1"));
                    p.inlines.add(new TextRun(" " + _("of") + " "));
                    p.inlines.add(new FieldRun("NUMPAGES", "1"));
                } else {
                    p.inlines.add(new FieldRun("PAGE", "1"));
                }
                s.page_format = style.selected == 2 ? NumFormat.LOWER_ROMAN : (style.selected == 3 ? NumFormat.UPPER_ROMAN : (style.selected == 4 ? NumFormat.LOWER_LETTER : NumFormat.DECIMAL));
                s.page_start = start.value > 0 ? (int) start.value : -1;
                var hf = new HeaderFooter();
                hf.blocks.add(p);
                if (pos.selected == 1) {
                    if (s.header_default != null && !s.header_default.is_blank()) s.header_default.blocks.add(p);
                    else s.header_default = hf;
                } else {
                    if (s.footer_default != null && !s.footer_default.is_blank()) s.footer_default.blocks.add(p);
                    else s.footer_default = hf;
                }
                if (!first.active) {
                    s.title_page = true;
                    if (pos.selected == 1) s.header_first = new HeaderFooter();
                    else s.footer_first = new HeaderFooter();
                    if (pos.selected == 1) s.header_first.blocks.add(new Paragraph("Header"));
                    else s.footer_first.blocks.add(new Paragraph("Footer"));
                }
                r.touch_all();
            });
            dlg.present();
        }

        public static void index_entry(WriteRichEditor r) {
            var dlg = make(r, _("Mark Index Entry"), 420, 320);
            var box = body(dlg);
            var g = new PreferencesGroup(_("Entry"), _("Use Main:Sub for a subentry."));
            var main = entry_row(g, _("Main entry"), r.ed.has_selection ? r.ed.selected_text().strip() : "");
            var sub = entry_row(g, _("Subentry"), "");
            var all = switch_row(g, _("Mark all occurrences"), null, false);
            box.append(g);
            footer(dlg, _("Mark"), () => {
                string term = main.text.strip() + (sub.text.strip() != "" ? ":" + sub.text.strip() : "");
                if (term == "") return;
                r.ed.checkpoint(_("Mark Index Entry"));
                if (all.active && main.text.strip() != "") {
                    var o = new FindOptions();
                    o.query = main.text.strip();
                    o.whole_word = true;
                    o.match_case = true;
                    try {
                        foreach (var m in Finder.find_all(r.doc, o)) {
                            int idx = m.para.split_at(m.end);
                            m.para.inlines.insert(idx, new Mark(MarkKind.INDEX_ENTRY, term));
                            m.para.touch();
                        }
                    } catch (Error e) {
                    }
                    r.ed.changed();
                } else {
                    Pos a, b;
                    r.ed.ordered(out a, out b);
                    int idx = b.para.split_at(b.offset);
                    b.para.inlines.insert(idx, new Mark(MarkKind.INDEX_ENTRY, term));
                    b.para.touch();
                    r.ed.changed();
                }
                r.toast(_("Index entry marked. Update the index to include it."));
            });
            dlg.present();
        }

        public static void citation(WriteRichEditor r) {
            if (r.doc.sources.size == 0) {
                source_editor(r, null, () => citation(r));
                return;
            }
            var dlg = make(r, _("Insert Citation"), 460, 520);
            var box = body(dlg);
            var g = new PreferencesGroup(_("Sources"));
            var pages = new EntryRow(_("Pages (optional)"));
            foreach (var s in r.doc.sources) {
                string who = s.authors.length > 0 ? Citations.last_name(s.authors[0]) : "";
                var row = new ActionRow(s.title, "%s %s".printf(who, s.year));
                var src = s;
                row.activated.connect(() => {
                    r.ed.checkpoint(_("Insert Citation"));
                    string code = "CITATION " + src.tag;
                    if (pages.text.strip() != "") code += " \\p " + pages.text.strip();
                    var f = new FieldRun(code, "");
                    r.ed.insert_inline(f);
                    r.update_fields();
                    dlg.close();
                });
                g.add_row(row);
            }
            box.append(g);
            var o = new PreferencesGroup();
            o.add_row(pages);
            var style = drop_row(o, _("Citation style"), Citations.styles(), index_of(Citations.styles(), r.doc.bib_style));
            style.notify["selected"].connect(() => r.run("bib-style", new Variant.string(Citations.styles()[style.selected])));
            box.append(o);
            footer(dlg, _("New Source\u2026"), () => source_editor(r, null, null));
            dlg.present();
        }

        private static int index_of(string[] arr, string v) {
            for (int i = 0; i < arr.length; i++) if (arr[i] == v) return i;
            return 0;
        }

        public static void sources(WriteRichEditor r) {
            var dlg = make(r, _("Manage Sources"), 460, 520);
            var box = body(dlg);
            var g = new PreferencesGroup(_("Sources in this document"));
            foreach (var s in r.doc.sources) {
                var row = new ActionRow(s.title, "%s  %s".printf(string.joinv("; ", s.authors), s.year));
                var src = s;
                var edit = new Button.from_icon_name("document-edit-symbolic");
                edit.add_css_class("flat");
                edit.valign = Gtk.Align.CENTER;
                edit.clicked.connect(() => {
                    dlg.close();
                    source_editor(r, src, () => sources(r));
                });
                row.add_suffix(edit);
                var del = new Button.from_icon_name("user-trash-symbolic");
                del.add_css_class("flat");
                del.valign = Gtk.Align.CENTER;
                del.clicked.connect(() => {
                    r.ed.checkpoint(_("Delete Source"));
                    r.doc.sources.remove(src);
                    g.remove_row(row);
                    r.update_fields();
                });
                row.add_suffix(del);
                g.add_row(row);
            }
            box.append(g);
            footer(dlg, _("New Source\u2026"), () => source_editor(r, null, () => sources(r)));
            dlg.present();
        }

        public static void source_editor(WriteRichEditor r, BibSource? existing, owned Apply? after) {
            var s = existing ?? new BibSource();
            var dlg = make(r, existing == null ? _("New Source") : _("Edit Source"), 460, 620);
            var box = body(dlg);
            var g = new PreferencesGroup();
            string[] kinds = { "Book", "JournalArticle", "InternetSite", "Report", "ConferenceProceedings", "BookSection" };
            string[] kind_labels = { _("Book"), _("Journal article"), _("Website"), _("Report"), _("Conference paper"), _("Book section") };
            var kind = drop_row(g, _("Type"), kind_labels, index_of(kinds, s.kind));
            var authors = entry_row(g, _("Authors (Last, First; Last, First)"), string.joinv("; ", s.authors));
            var title = entry_row(g, _("Title"), s.title);
            var year = entry_row(g, _("Year"), s.year);
            var journal = entry_row(g, _("Journal or container"), s.journal);
            var publisher = entry_row(g, _("Publisher"), s.publisher);
            var city = entry_row(g, _("City"), s.city);
            var volume = entry_row(g, _("Volume"), s.volume);
            var issue = entry_row(g, _("Issue"), s.issue);
            var pages = entry_row(g, _("Pages"), s.pages);
            var url = entry_row(g, _("URL"), s.url);
            var doi = entry_row(g, _("DOI"), s.doi);
            var tag = entry_row(g, _("Tag name"), s.tag);
            box.append(g);
            footer(dlg, _("Save"), () => {
                r.ed.checkpoint(_("Source"));
                s.kind = kinds[kind.selected];
                string[] au = {};
                foreach (string a in authors.text.split(";")) if (a.strip() != "") au += a.strip();
                s.authors = au;
                s.title = title.text;
                s.year = year.text;
                s.journal = journal.text;
                s.publisher = publisher.text;
                s.city = city.text;
                s.volume = volume.text;
                s.issue = issue.text;
                s.pages = pages.text;
                s.url = url.text;
                s.doi = doi.text;
                string tg = tag.text.strip();
                if (tg == "") tg = (au.length > 0 ? Citations.last_name(au[0]).substring(0, int.min(3, Citations.last_name(au[0]).length)) : "Src") + (s.year.length >= 2 ? s.year.substring(s.year.length - 2) : "");
                string base_tag = tg;
                int n = 1;
                while (r.doc.find_source(tg) != null && r.doc.find_source(tg) != s) tg = base_tag + (n++).to_string();
                s.tag = tg;
                if (existing == null) r.doc.sources.add(s);
                r.update_fields();
                if (after != null) after();
            });
            dlg.present();
        }

        public static void watermark(WriteRichEditor r) {
            var wm = r.doc.watermark ?? new Watermark();
            var dlg = make(r, _("Watermark"), 440, 480);
            var box = body(dlg);
            var g = new PreferencesGroup();
            var kind = drop_row(g, _("Watermark"), { _("None"), _("Text"), _("Picture") }, r.doc.watermark == null ? 0 : (wm.image != null ? 2 : 1));
            var text = entry_row(g, _("Text"), wm.text != "" ? wm.text : _("CONFIDENTIAL"));
            var font = entry_row(g, _("Font"), wm.font);
            var color = color_row(g, _("Color"), wm.color);
            var diag = switch_row(g, _("Diagonal"), null, wm.diagonal);
            var wash = switch_row(g, _("Washout"), null, wm.washout);
            box.append(g);
            Bytes? picked = wm.image;
            var pick = new Button.with_label(_("Choose Picture\u2026"));
            pick.clicked.connect(() => {
                var fd = new Gtk.FileDialog();
                fd.open.begin(dlg, null, (o, res) => {
                    try {
                        var f = fd.open.end(res);
                        uint8[] d;
                        FileUtils.get_data(f.get_path(), out d);
                        picked = new Bytes(d);
                        kind.selected = 2;
                    } catch (Error e) {
                    }
                });
            });
            box.append(pick);
            footer(dlg, _("Apply"), () => {
                r.ed.checkpoint(_("Watermark"));
                if (kind.selected == 0) r.doc.watermark = null;
                else {
                    var w = new Watermark();
                    w.text = text.text;
                    w.font = font.text;
                    w.color = hex_of(color);
                    w.diagonal = diag.active;
                    w.washout = wash.active;
                    if (kind.selected == 2 && picked != null) {
                        w.image = picked;
                        w.image_mime = ImageRun.sniff(picked.get_data());
                    }
                    r.doc.watermark = w;
                }
                r.touch_all();
            });
            dlg.present();
        }

        public static void dropcap(WriteRichEditor r) {
            var dlg = make(r, _("Drop Cap"), 380, 300);
            var box = body(dlg);
            var g = new PreferencesGroup();
            var pp = r.doc.styles.resolve_para(r.ed.focus.para);
            var kind = drop_row(g, _("Position"), { _("None"), _("Dropped"), _("In margin") }, pp.dropcap_lines == 0 ? 0 : (pp.dropcap_margin ? 2 : 1));
            var lines = spin_row(g, _("Lines to drop"), null, 2, 10, 1, pp.dropcap_lines > 0 ? pp.dropcap_lines : 3, 0);
            box.append(g);
            footer(dlg, _("Apply"), () => {
                int k = (int) kind.selected;
                int n = (int) lines.value;
                r.ed.checkpoint(_("Drop Cap"));
                r.ed.format_paragraphs((p) => {
                    p.props.dropcap_lines = k == 0 ? 0 : n;
                    p.props.dropcap_margin = k == 2;
                });
            });
            dlg.present();
        }

        public static void page_setup(WriteRichEditor r) {
            var s = r.doc.section_for(r.ed.focus.para);
            var dlg = make(r, _("Page Setup"), 480, 700);
            var box = body(dlg);
            string u = unit(r);
            var pg = new PreferencesGroup(_("Paper"));
            string[] sizes = { "A4", "A5", "A3", "Letter", "Legal", "Executive", "B5", _("Custom") };
            double[,] dims = { { 595.3, 841.9 }, { 419.5, 595.3 }, { 841.9, 1190.6 }, { 612, 792 }, { 612, 1008 }, { 522, 756 }, { 498.9, 708.7 }, { 0, 0 } };
            int sel = sizes.length - 1;
            double pw = s.landscape ? s.page_h : s.page_w, ph = s.landscape ? s.page_w : s.page_h;
            for (int i = 0; i < 7; i++) if ((dims[i, 0] - pw).abs() < 2 && (dims[i, 1] - ph).abs() < 2) sel = i;
            var size = drop_row(pg, _("Paper size"), sizes, sel);
            var width = spin_row(pg, _("Width"), u, 1, 200, 0.1, to_unit(r, pw), 2);
            var height = spin_row(pg, _("Height"), u, 1, 200, 0.1, to_unit(r, ph), 2);
            size.notify["selected"].connect(() => {
                int k = (int) size.selected;
                if (k < 7) {
                    width.value = to_unit(r, dims[k, 0]);
                    height.value = to_unit(r, dims[k, 1]);
                }
            });
            var orient = drop_row(pg, _("Orientation"), { _("Portrait"), _("Landscape") }, s.landscape ? 1 : 0);
            box.append(pg);
            var mg = new PreferencesGroup(_("Margins"));
            var top = spin_row(mg, _("Top"), u, 0, 50, 0.1, to_unit(r, s.margin_top), 2);
            var bottom = spin_row(mg, _("Bottom"), u, 0, 50, 0.1, to_unit(r, s.margin_bottom), 2);
            var left = spin_row(mg, _("Left"), u, 0, 50, 0.1, to_unit(r, s.margin_left), 2);
            var right = spin_row(mg, _("Right"), u, 0, 50, 0.1, to_unit(r, s.margin_right), 2);
            var gutter = spin_row(mg, _("Gutter"), u, 0, 20, 0.1, to_unit(r, s.gutter), 2);
            box.append(mg);
            var lg = new PreferencesGroup(_("Headers and footers"));
            var hdist = spin_row(lg, _("Header from edge"), u, 0, 20, 0.1, to_unit(r, s.header_dist), 2);
            var fdist = spin_row(lg, _("Footer from edge"), u, 0, 20, 0.1, to_unit(r, s.footer_dist), 2);
            var firstp = switch_row(lg, _("Different first page"), null, s.title_page);
            var oddeven = switch_row(lg, _("Different odd and even pages"), null, r.doc.even_odd_headers);
            var start = drop_row(lg, _("Section start"), { _("New page"), _("Continuous"), _("Even page"), _("Odd page"), _("New column") }, (int) s.start);
            var apply_all = switch_row(lg, _("Apply to whole document"), null, true);
            box.append(lg);
            footer(dlg, _("Apply"), () => {
                r.ed.checkpoint(_("Page Setup"));
                var targets = apply_all.active ? r.doc.sections() : new Gee.ArrayList<Section>();
                if (!apply_all.active) targets.add(s);
                foreach (var t in targets) {
                    double w = from_unit(r, width.value);
                    double h = from_unit(r, height.value);
                    bool land = orient.selected == 1;
                    t.landscape = land;
                    t.page_w = land ? double.max(w, h) : double.min(w, h);
                    t.page_h = land ? double.min(w, h) : double.max(w, h);
                    if (sizes[size.selected] == _("Custom")) {
                        t.page_w = land ? h : w;
                        t.page_h = land ? w : h;
                    }
                    t.margin_top = from_unit(r, top.value);
                    t.margin_bottom = from_unit(r, bottom.value);
                    t.margin_left = from_unit(r, left.value);
                    t.margin_right = from_unit(r, right.value);
                    t.gutter = from_unit(r, gutter.value);
                    t.header_dist = from_unit(r, hdist.value);
                    t.footer_dist = from_unit(r, fdist.value);
                    t.title_page = firstp.active;
                }
                s.start = (SectionStart) start.selected;
                r.doc.even_odd_headers = oddeven.active;
                r.touch_all();
            });
            dlg.present();
        }

        public static void columns(WriteRichEditor r) {
            var s = r.doc.section_for(r.ed.focus.para);
            var dlg = make(r, _("Columns"), 400, 360);
            var box = body(dlg);
            var g = new PreferencesGroup();
            var n = spin_row(g, _("Number of columns"), null, 1, 12, 1, s.columns, 0);
            var space = spin_row(g, _("Spacing"), unit(r), 0, 10, 0.05, to_unit(r, s.column_space), 2);
            var line = switch_row(g, _("Line between"), null, s.column_sep);
            var scope = drop_row(g, _("Apply to"), { _("This section"), _("Selected text (new section)") }, r.ed.has_selection ? 1 : 0);
            box.append(g);
            footer(dlg, _("Apply"), () => {
                r.ed.checkpoint(_("Columns"));
                if (scope.selected == 1 && r.ed.has_selection) {
                    Pos a, b;
                    r.ed.ordered(out a, out b);
                    var list = r.doc.body;
                    Block top_a = a.para, top_b = b.para;
                    if (a.para.parent != list || b.para.parent != list) {
                        r.toast(_("Select paragraphs in the main text."));
                        return;
                    }
                    var old = r.doc.section_for(b.para);
                    int ia = list.items.index_of(top_a);
                    if (ia > 0 && list[ia - 1] is Paragraph && ((Paragraph) list[ia - 1]).section == null) {
                        var before = old.copy();
                        ((Paragraph) list[ia - 1]).section = before;
                    } else if (ia == 0) {
                        var carrier = new Paragraph();
                        carrier.section = old.copy();
                        list.insert(0, carrier);
                    }
                    var mid = old.copy();
                    mid.columns = (int) n.value;
                    mid.column_space = from_unit(r, space.value);
                    mid.column_sep = line.active;
                    mid.start = SectionStart.CONTINUOUS;
                    ((Paragraph) top_b).section = mid;
                    old.start = SectionStart.CONTINUOUS;
                } else {
                    s.columns = (int) n.value;
                    s.column_space = from_unit(r, space.value);
                    s.column_sep = line.active;
                }
                r.touch_all();
            });
            dlg.present();
        }

        public static void borders(WriteRichEditor r) {
            var pp = r.doc.styles.resolve_para(r.ed.focus.para);
            var dlg = make(r, _("Borders and Shading"), 440, 520);
            var box = body(dlg);
            var g = new PreferencesGroup(_("Paragraph borders"));
            var which = drop_row(g, _("Borders"), { _("None"), _("Box"), _("Top"), _("Bottom"), _("Top and bottom"), _("Left") }, pp.border_top != null && pp.border_bottom != null && pp.border_left != null ? 1 : (pp.border_bottom != null ? 3 : 0));
            var style = drop_row(g, _("Style"), { _("Single"), _("Double"), _("Dotted"), _("Dashed"), _("Thick") }, 0);
            var color = color_row(g, _("Color"), "#000000");
            var width = spin_row(g, _("Width"), _("points"), 0.25, 6, 0.25, 0.75, 2);
            box.append(g);
            var sg = new PreferencesGroup(_("Shading"));
            var shade = color_row(sg, _("Fill"), pp.shading ?? "#f2f2f2");
            var noshade = switch_row(sg, _("No fill"), null, pp.shading == null);
            box.append(sg);
            footer(dlg, _("Apply"), () => {
                r.ed.checkpoint(_("Borders"));
                string[] styles = { "single", "double", "dotted", "dashed", "thick" };
                string st = styles[style.selected];
                string col = hex_of(color);
                double w = st == "thick" ? double.max(2, width.value) : width.value;
                int k = (int) which.selected;
                string? fill = noshade.active ? null : hex_of(shade);
                r.ed.format_paragraphs((p) => {
                    var none = new Write.Border.with("none", 0, col);
                    string bs = st == "thick" ? "single" : st;
                    p.props.border_top = k == 1 || k == 2 || k == 4 ? new Write.Border.with(bs, w, col) : none;
                    p.props.border_bottom = k == 1 || k == 3 || k == 4 ? new Write.Border.with(bs, w, col) : none.copy();
                    p.props.border_left = k == 1 || k == 5 ? new Write.Border.with(bs, w, col) : none.copy();
                    p.props.border_right = k == 1 ? new Write.Border.with(bs, w, col) : none.copy();
                    p.props.shading = fill;
                });
            });
            dlg.present();
        }

        public static void page_color(WriteRichEditor r) {
            var dlg = make(r, _("Page Color"), 380, 280);
            var box = body(dlg);
            var g = new PreferencesGroup();
            var color = color_row(g, _("Color"), r.doc.page_color ?? "#ffffff");
            var none = switch_row(g, _("No color"), null, r.doc.page_color == null);
            box.append(g);
            footer(dlg, _("Apply"), () => {
                r.ed.checkpoint(_("Page Color"));
                string c = hex_of(color);
                r.doc.page_color = none.active || c == "#ffffff" ? null : c;
                r.touch_all();
            });
            dlg.present();
        }

        public static void page_borders(WriteRichEditor r) {
            var s = r.doc.section_for(r.ed.focus.para);
            var dlg = make(r, _("Page Borders"), 400, 360);
            var box = body(dlg);
            var g = new PreferencesGroup();
            var on = switch_row(g, _("Box around the page"), null, s.page_border_top != null && s.page_border_top.visible());
            var style = drop_row(g, _("Style"), { _("Single"), _("Double"), _("Dotted"), _("Dashed") }, 0);
            var color = color_row(g, _("Color"), s.page_border_top != null ? s.page_border_top.color : "#000000");
            var width = spin_row(g, _("Width"), _("points"), 0.25, 12, 0.25, s.page_border_top != null ? s.page_border_top.width : 1, 2);
            box.append(g);
            footer(dlg, _("Apply"), () => {
                r.ed.checkpoint(_("Page Borders"));
                string[] styles = { "single", "double", "dotted", "dashed" };
                foreach (var sec in r.doc.sections()) {
                    if (!on.active) {
                        sec.page_border_top = sec.page_border_bottom = sec.page_border_left = sec.page_border_right = null;
                        continue;
                    }
                    var b = new Write.Border.with(styles[style.selected], width.value, hex_of(color));
                    sec.page_border_top = b;
                    sec.page_border_bottom = b.copy();
                    sec.page_border_left = b.copy();
                    sec.page_border_right = b.copy();
                }
                r.touch_all();
            });
            dlg.present();
        }

        public static void thesaurus(WriteRichEditor r, string word) {
            var dlg = make(r, _("Thesaurus"), 420, 520);
            var box = body(dlg);
            var entry = new Gtk.SearchEntry();
            entry.text = word.strip();
            box.append(entry);
            var results = new Box(Orientation.VERTICAL, 10);
            box.append(results);
            string lang = r.doc.lang != "" ? r.doc.lang : Hyphenator.default_lang();
            Apply look = () => {};
            look = () => {
                Widget? w;
                while ((w = results.get_first_child()) != null) results.remove(w);
                var th = Thesaurus.get_default();
                if (th.file_for(lang) == null) {
                    var l = new Label(_("No thesaurus is installed for %s. Install a MyThes thesaurus (for example the mythes package) to look up synonyms.").printf(lang));
                    l.wrap = true;
                    results.append(l);
                    return;
                }
                var meanings = th.lookup(entry.text, lang);
                if (meanings.size == 0) {
                    results.append(new Label(_("No synonyms found.")));
                    return;
                }
                foreach (var m in meanings) {
                    var g = new PreferencesGroup(m.pos != "" ? m.pos : _("Synonyms"));
                    foreach (string syn in m.synonyms) {
                        var row = new ActionRow(syn);
                        var ins = new Button.with_label(_("Replace"));
                        ins.valign = Gtk.Align.CENTER;
                        string s = syn;
                        ins.clicked.connect(() => {
                            r.ed.checkpoint(_("Replace Word"));
                            if (!r.ed.has_selection) {
                                int a, b;
                                r.ed.word_at(r.ed.focus, out a, out b);
                                r.ed.select(new Pos(r.ed.focus.para, a), new Pos(r.ed.focus.para, b));
                            }
                            Pos a0, b0;
                            r.ed.ordered(out a0, out b0);
                            var props = a0.para.props_at(a0.offset + 1);
                            r.ed.delete_selection();
                            r.ed.insert_text(s, props);
                            dlg.close();
                        });
                        row.add_suffix(ins);
                        row.activated.connect(() => {
                            entry.text = s;
                            look();
                        });
                        g.add_row(row);
                    }
                    results.append(g);
                }
            };
            entry.activate.connect(() => look());
            look();
            close_footer(dlg);
            dlg.present();
        }

        public static void word_count(WriteRichEditor r) {
            var dlg = make(r, _("Word Count"), 380, 460);
            var box = body(dlg);
            var g = new PreferencesGroup();
            var notes = new SwitchRow(_("Include text boxes, footnotes and endnotes"), null, false);
            Apply fill = () => {};
            var rows = new Gee.ArrayList<ActionRow>();
            string[] titles = { _("Pages"), _("Words"), _("Characters (no spaces)"), _("Characters (with spaces)"), _("Paragraphs"), _("Lines"), _("Sentences") };
            foreach (string t in titles) {
                var row = new ActionRow(t);
                var l = new Label("");
                row.add_suffix(l);
                rows.add(row);
                g.add_row(row);
            }
            fill = () => {
                var st = Stats.compute(r.doc, notes.active);
                if (r.ed.has_selection) {
                    DocStats sel = { 0, 0, 0, 0, 0 };
                    Stats.count_text(r.ed.selected_text(), ref sel);
                    sel.paragraphs = r.ed.selected_paragraphs().size;
                    st = sel;
                }
                int lines = 0;
                if (r.view.lay != null) foreach (var p in r.view.lay.pages) foreach (var lb in p.lines) if (lb.region == Region.BODY || (notes.active && lb.region == Region.NOTES)) lines++;
                string[] vals = { r.view.lay != null ? r.view.lay.pages.size.to_string() : "1", st.words.to_string(), st.chars_no_spaces.to_string(), st.chars.to_string(), st.paragraphs.to_string(), lines.to_string(), st.sentences.to_string() };
                for (int i = 0; i < rows.size; i++) {
                    set_suffix_text(rows[i], vals[i]);
                }
            };
            notes.switch_btn.notify["active"].connect(() => fill());
            fill();
            box.append(g);
            var o = new PreferencesGroup();
            o.add_row(notes);
            box.append(o);
            if (r.ed.has_selection) {
                var hint = new Label(_("Counts refer to the selection."));
                hint.add_css_class("dim-label");
                box.append(hint);
            }
            close_footer(dlg);
            dlg.present();
        }

        private static void set_suffix_text(ActionRow row, string text) {
            var labels = new Gee.ArrayList<Label>();
            find_labels(row, labels);
            if (labels.size > 0) labels[labels.size - 1].label = text;
        }

        private static void find_labels(Widget w, Gee.ArrayList<Label> into) {
            for (var c = w.get_first_child(); c != null; c = c.get_next_sibling()) {
                if (c is Label) into.add((Label) c);
                find_labels(c, into);
            }
        }

        public static void language(WriteRichEditor r) {
            var dlg = make(r, _("Language"), 400, 520);
            var box = body(dlg);
            var g = new PreferencesGroup(_("Proofing"), _("Spelling, grammar, hyphenation and quotes follow the language."));
            string[] codes = { "en-US", "en-GB", "it-IT", "fr-FR", "de-DE", "es-ES", "pt-PT", "pt-BR", "nl-NL", "sv-SE", "pl-PL", "ru-RU" };
            string[] names = { _("English (United States)"), _("English (United Kingdom)"), _("Italian"), _("French"), _("German"), _("Spanish"), _("Portuguese (Portugal)"), _("Portuguese (Brazil)"), _("Dutch"), _("Swedish"), _("Polish"), _("Russian") };
            var lang = drop_row(g, _("Language"), names, 0);
            string cur = r.doc.lang.replace("_", "-");
            for (int i = 0; i < codes.length; i++) if (codes[i].down() == cur.down()) lang.selected = i;
            var scope = drop_row(g, _("Apply to"), { _("Selected text"), _("Whole document") }, r.ed.has_selection ? 0 : 1);
            var nocheck = switch_row(g, _("Do not check spelling or grammar"), null, false);
            box.append(g);
            footer(dlg, _("Apply"), () => {
                r.ed.checkpoint(_("Language"));
                string code = codes[lang.selected];
                if (scope.selected == 1) {
                    r.doc.lang = code;
                    foreach (var p in Story.all(r.doc)) {
                        foreach (var it in p.inlines) it.props.lang = null;
                        p.touch();
                    }
                } else {
                    r.ed.format_chars((c) => c.lang = code);
                }
                r.view.spell_enabled = !nocheck.active;
                r.view.doc_lang = r.doc.lang;
                r.view.refresh_spelling();
                r.ed.changed();
            });
            dlg.present();
        }

        public static void compare(WriteRichEditor r, bool combine) {
            var fd = new Gtk.FileDialog();
            fd.title = combine ? _("Combine With") : _("Compare With");
            var fl = new GLib.ListStore(typeof(Gtk.FileFilter));
            fl.append(WriteFiles.all_documents());
            fd.filters = fl;
            fd.open.begin(r.window, null, (o, res) => {
                try {
                    var f = fd.open.end(res);
                    Write.FileFormat fmt;
                    var other = WriteFiles.load(f, out fmt);
                    string author = other.meta.last_modified_by != "" ? other.meta.last_modified_by : (other.meta.author != "" ? other.meta.author : f.get_basename());
                    if (combine) {
                        r.ed.checkpoint(_("Combine"));
                        var merged = Review.compare(r.doc, other, author);
                        foreach (var c in other.comments) if (r.doc.find_comment(c.id) == null) merged.comments.add(c.copy());
                        r.doc.assign(merged);
                        r.touch_all();
                        r.show_right("review");
                    } else {
                        var result = Review.compare(r.doc, other, author);
                        r.file = null;
                        r.set_document(result);
                        r.modified = true;
                        r.title_changed();
                        r.show_right("review");
                    }
                } catch (Error e) {
                    if (!(e is Gtk.DialogError.DISMISSED)) r.toast(e.message);
                }
            });
        }


        public static void protect(WriteRichEditor r) {
            var pr = r.doc.protection;
            if (pr.enforced) {
                var dlg = make(r, _("Stop Protection"), 400, 280);
                var box = body(dlg);
                var g = new PreferencesGroup(_("Password"), pr.hash != "" ? _("Enter the password to stop protection.") : null);
                var pw = new PasswordRow(_("Password"));
                if (pr.hash != "") g.add_row(pw);
                box.append(g);
                footer(dlg, _("Stop Protection"), () => {
                    if (pr.hash != "" && Write.Protection.hash_password(pw.text, pr.salt, pr.spin) != pr.hash) {
                        r.toast(_("The password is not correct."));
                        return;
                    }
                    pr.enforced = false;
                    r.apply_protection();
                    r.modified = true;
                    r.title_changed();
                    r.update_status();
                });
                dlg.present();
                return;
            }
            var dlg = make(r, _("Restrict Editing"), 440, 420);
            var box = body(dlg);
            var g = new PreferencesGroup(_("Restriction"), _("Protection prevents accidental changes. It is not encryption."));
            var kind = drop_row(g, _("Allow only"), { _("No changes (read only)"), _("Comments"), _("Tracked changes"), _("Filling in forms") }, 0);
            var pw = new PasswordRow(_("Password (optional)"));
            g.add_row(pw);
            var pw2 = new PasswordRow(_("Confirm password"));
            g.add_row(pw2);
            box.append(g);
            footer(dlg, _("Start Enforcing"), () => {
                if (pw.text != pw2.text) {
                    r.toast(_("The passwords do not match."));
                    return;
                }
                ProtectKind[] kinds = { ProtectKind.READ_ONLY, ProtectKind.COMMENTS, ProtectKind.TRACKED, ProtectKind.FORMS };
                pr.kind = kinds[kind.selected];
                pr.enforced = true;
                pr.algorithm = "SHA-512";
                pr.spin = 100000;
                if (pw.text != "") {
                    uint8[] salt = new uint8[16];
                    for (int i = 0; i < 16; i++) salt[i] = (uint8) Random.int_range(0, 256);
                    pr.salt = Base64.encode(salt);
                    pr.hash = Write.Protection.hash_password(pw.text, pr.salt, pr.spin);
                } else {
                    pr.salt = "";
                    pr.hash = "";
                }
                r.apply_protection();
                r.modified = true;
                r.title_changed();
                r.update_status();
            });
            dlg.present();
        }

        public static void merge_recipients(WriteRichEditor r) {
            var fd = new Gtk.FileDialog();
            fd.title = _("Select Recipients");
            var ff = new Gtk.FileFilter();
            ff.name = _("Recipient lists (CSV, TSV, vCard, JSON)");
            foreach (string s in new string[] { "csv", "tsv", "tab", "txt", "vcf", "vcard", "json" }) ff.add_suffix(s);
            var fl = new GLib.ListStore(typeof(Gtk.FileFilter));
            fl.append(ff);
            fd.filters = fl;
            fd.open.begin(r.window, null, (o, res) => {
                try {
                    var f = fd.open.end(res);
                    r.merge_ds = DataSource.load(f.get_path());
                    r.merge_index = 0;
                    r.doc.merge_source = f.get_path();
                    r.modified = true;
                    r.title_changed();
                    r.toast(ngettext("%d recipient loaded", "%d recipients loaded", r.merge_ds.records.size).printf(r.merge_ds.records.size));
                    r.update_status();
                } catch (Error e) {
                    if (!(e is Gtk.DialogError.DISMISSED)) r.toast(e.message);
                }
            });
        }

        public static void merge_field(WriteRichEditor r) {
            var dlg = make(r, _("Insert Merge Field"), 380, 480);
            var box = body(dlg);
            var g = new PreferencesGroup(_("Fields"));
            string[] cols = r.merge_ds != null ? r.merge_ds.columns : new string[] { "Name", "FirstName", "LastName", "Street", "City", "PostalCode", "Country", "Email" };
            foreach (string c in cols) {
                var row = new ActionRow(c);
                string cn = c;
                row.activated.connect(() => {
                    r.ed.checkpoint(_("Insert Merge Field"));
                    r.ed.insert_inline(new FieldRun("MERGEFIELD " + (cn.contains(" ") ? "\"" + cn + "\"" : cn), ""));
                });
                g.add_row(row);
            }
            box.append(g);
            var o = new PreferencesGroup();
            var greeting = new ActionRow(_("Greeting line"), _("Dear first name,"));
            greeting.activated.connect(() => {
                r.ed.checkpoint(_("Greeting Line"));
                r.ed.insert_text(_("Dear") + " ");
                r.ed.insert_inline(new FieldRun("MERGEFIELD FirstName", ""));
                r.ed.insert_text(",");
            });
            o.add_row(greeting);
            var address = new ActionRow(_("Address block"));
            address.activated.connect(() => {
                r.ed.checkpoint(_("Address Block"));
                foreach (string f in new string[] { "Name", "Street" }) {
                    r.ed.insert_inline(new FieldRun("MERGEFIELD " + f, ""));
                    r.ed.insert_inline(new Break(BreakKind.LINE));
                }
                r.ed.insert_inline(new FieldRun("MERGEFIELD PostalCode", ""));
                r.ed.insert_text(" ");
                r.ed.insert_inline(new FieldRun("MERGEFIELD City", ""));
            });
            o.add_row(address);
            box.append(o);
            close_footer(dlg);
            dlg.present();
        }

        public static void envelopes(WriteRichEditor r) {
            var dlg = make(r, _("Envelope"), 420, 480);
            var box = body(dlg);
            var g = new PreferencesGroup();
            var tv_from = new Gtk.TextView();
            tv_from.buffer.text = r.doc.meta.author != "" ? r.doc.meta.author : r.ed.author;
            tv_from.height_request = 70;
            var tv_to = new Gtk.TextView();
            tv_to.buffer.text = r.ed.has_selection ? r.ed.selected_text() : "";
            tv_to.height_request = 90;
            var l1 = new Label(_("Return address"));
            l1.xalign = 0;
            box.append(l1);
            box.append(tv_from);
            var l2 = new Label(_("Delivery address"));
            l2.xalign = 0;
            box.append(l2);
            box.append(tv_to);
            var size = drop_row(g, _("Envelope size"), { "DL (110 \u00d7 220 mm)", "Commercial 10" }, 0);
            var merge = switch_row(g, _("One envelope per recipient"), _("Uses the recipient list"), r.merge_ds != null);
            box.append(g);
            footer(dlg, _("Create"), () => {
                var env = MailMerge.envelope(tv_from.buffer.text, tv_to.buffer.text, size.selected == 0);
                if (merge.active && r.merge_ds != null) {
                    var tmpl = MailMerge.envelope(tv_from.buffer.text, "", size.selected == 0);
                    foreach (string f in new string[] { "Name", "Street", "PostalCode City" }) {
                        var p = new Paragraph("NoSpacing");
                        p.props.ind_left = tmpl.final_section.page_w * 0.42;
                        foreach (string part in f.split(" ")) {
                            if (p.inlines.size > 0) p.inlines.add(new TextRun(" "));
                            p.inlines.add(new FieldRun("MERGEFIELD " + part, ""));
                        }
                        tmpl.body.add(p);
                    }
                    env = MailMerge.merge_all(tmpl, r.merge_ds);
                }
                r.file = null;
                r.set_document(env);
                r.modified = true;
                r.title_changed();
            });
            dlg.present();
        }

        public static void labels(WriteRichEditor r) {
            var dlg = make(r, _("Labels"), 440, 460);
            var box = body(dlg);
            var g = new PreferencesGroup();
            var specs = MailMerge.label_specs();
            string[] names = {};
            foreach (var s in specs) names += s.name;
            var spec = drop_row(g, _("Label sheet"), names, 0);
            var source = drop_row(g, _("Content"), { _("Same text on every label"), _("One label per recipient") }, r.merge_ds != null ? 1 : 0);
            box.append(g);
            var tv = new Gtk.TextView();
            tv.buffer.text = r.ed.has_selection ? r.ed.selected_text() : _("Name\nStreet\nCity");
            tv.height_request = 100;
            box.append(tv);
            footer(dlg, _("Create"), () => {
                var sp = specs[(int) spec.selected];
                Write.Document d;
                if (source.selected == 1 && r.merge_ds != null) {
                    var tmpl = new BlockList();
                    foreach (string f in new string[] { "Name", "Street", "PostalCode City" }) {
                        var p = new Paragraph("NoSpacing");
                        foreach (string part in f.split(" ")) {
                            if (p.inlines.size > 0) p.inlines.add(new TextRun(" "));
                            p.inlines.add(new FieldRun("MERGEFIELD " + part, ""));
                        }
                        tmpl.add(p);
                    }
                    d = MailMerge.labels(tmpl, r.merge_ds, sp);
                } else {
                    d = MailMerge.labels(new BlockList(), null, sp, tv.buffer.text);
                }
                r.file = null;
                r.set_document(d);
                r.modified = true;
                r.title_changed();
            });
            dlg.present();
        }

        public static void save_macro(WriteRichEditor r) {
            if (r.macro_steps.size == 0) {
                r.toast(_("Nothing was recorded."));
                return;
            }
            var dlg = make(r, _("Save Macro"), 400, 300);
            var box = body(dlg);
            var g = new PreferencesGroup();
            var name = entry_row(g, _("Macro name"), _("Macro %d").printf(r.doc.macros.size + 1));
            var where = drop_row(g, _("Store in"), { _("This document"), _("All documents") }, 1);
            box.append(g);
            footer(dlg, _("Save"), () => {
                string body_text = "name:" + name.text.strip() + "\n" + string.joinv("\n", r.macro_steps.to_array());
                if (where.selected == 0) {
                    r.doc.macros.add(body_text);
                    r.modified = true;
                    r.title_changed();
                } else {
                    MacroLibrary.add(body_text);
                }
                r.toast(_("Macro saved."));
            });
            dlg.present();
        }

        public static void macros(WriteRichEditor r) {
            var dlg = make(r, _("Macros"), 460, 560);
            var box = body(dlg);
            var all = new Gee.ArrayList<string>();
            all.add_all(r.doc.macros);
            all.add_all(MacroLibrary.load());
            var g = new PreferencesGroup(_("Library"), _("Recorded macros replay commands and typing. Scripts can use variables, loops, conditions and document events, and read or change paragraphs, styles and tables."));
            foreach (string m in all) {
                string[] lines = m.split("\n");
                bool script = lines.length > 0 && lines[0].has_prefix("script:");
                string nm = lines.length > 0 && (lines[0].has_prefix("name:") || script) ? lines[0].substring(script ? 7 : 5) : _("Macro");
                string sub = script ? _("Script") : ngettext("%d step", "%d steps", lines.length - 1).printf(lines.length - 1);
                if (!r.doc.macros.contains(m)) sub += "  " + _("All documents");
                var row = new ActionRow(nm, sub);
                var run = new Button.with_label(_("Run"));
                run.valign = Gtk.Align.CENTER;
                string body_text = m;
                run.clicked.connect(() => {
                    dlg.close();
                    if (script) r.run_script(body_text.substring(body_text.index_of_char('\n') + 1));
                    else r.play_macro(body_text);
                });
                row.add_suffix(run);
                if (script) {
                    var edit = new Button.from_icon_name("document-edit-symbolic");
                    edit.add_css_class("flat");
                    edit.valign = Gtk.Align.CENTER;
                    edit.tooltip_text = _("Edit");
                    edit.clicked.connect(() => {
                        dlg.close();
                        script_editor(r, body_text);
                    });
                    row.add_suffix(edit);
                }
                var del = new Button.from_icon_name("user-trash-symbolic");
                del.add_css_class("flat");
                del.valign = Gtk.Align.CENTER;
                del.clicked.connect(() => {
                    if (r.doc.macros.contains(body_text)) {
                        r.doc.macros.remove(body_text);
                        r.modified = true;
                        r.title_changed();
                    } else {
                        MacroLibrary.remove(body_text);
                    }
                    g.remove_row(row);
                });
                row.add_suffix(del);
                g.add_row(row);
            }
            box.append(g);
            var ng = new PreferencesGroup();
            var nscript = new ActionRow(_("New Script"), _("Write a script for this document or for all documents"));
            nscript.activated.connect(() => {
                dlg.close();
                script_editor(r, null);
            });
            ng.add_row(nscript);
            box.append(ng);
            footer(dlg, r.recording ? _("Stop Recording") : _("Record Macro"), () => r.run("macro-record", null));
            dlg.present();
        }

        public static void script_editor(WriteRichEditor r, string? existing) {
            string nm = _("Script");
            string src = "# " + _("Example: make every short paragraph a heading") + "\nfor p in paragraphs() {\n    if len(p.text) > 0 and len(p.text) < 30 and not p.in_table {\n        set_style(p, \"Heading1\")\n    }\n}\n";
            bool in_doc = true;
            if (existing != null) {
                int nl = existing.index_of_char('\n');
                nm = existing.substring(7, nl - 7);
                src = existing.substring(nl + 1);
                in_doc = r.doc.macros.contains(existing);
            }
            var dlg = make(r, existing != null ? _("Edit Script") : _("New Script"), 640, 640);
            var box = body(dlg);
            var g = new PreferencesGroup(_("Script"), _("Statements: let, if/else, while, for x in list, func, return, break, continue, on open/save/print/change. Functions: paragraphs(), headings(), tables(), styles(), current(), goto, select, set_style, set_text, format, append, insert_after, delete, cell, set_cell, add_row, insert_table, find, replace_all, word_count, set_title, variable, set_variable, run(command), type, print, and text and list helpers."));
            var name = entry_row(g, _("Name"), nm);
            var where = drop_row(g, _("Store in"), { _("This document"), _("All documents") }, in_doc ? 0 : 1);
            box.append(g);
            var tv = new Gtk.TextView();
            tv.monospace = true;
            tv.buffer.text = src;
            tv.height_request = 260;
            tv.vexpand = true;
            tv.add_css_class("write-chart-data");
            box.append(tv);
            var result = new Gtk.Label("");
            result.wrap = true;
            result.xalign = 0;
            result.selectable = true;
            result.add_css_class("dim-label");
            box.append(result);
            var bar = new Box(Orientation.HORIZONTAL, 8);
            var runb = new Button.with_label(_("Run"));
            runb.clicked.connect(() => {
                result.label = r.run_script(tv.buffer.text);
            });
            bar.append(runb);
            box.append(bar);
            footer(dlg, _("Save"), () => {
                string body_text = "script:" + (name.text.strip() != "" ? name.text.strip() : _("Script")) + "\n" + tv.buffer.text;
                if (existing != null) {
                    if (r.doc.macros.contains(existing)) r.doc.macros.remove(existing);
                    else MacroLibrary.remove(existing);
                }
                if (where.selected == 0) {
                    r.doc.macros.add(body_text);
                    r.modified = true;
                    r.title_changed();
                    r.load_document_scripts(true);
                } else {
                    MacroLibrary.add(body_text);
                }
                r.toast(_("Script saved."));
            });
            dlg.present();
        }

        public static void autocorrect(WriteRichEditor r) {
            var ac = AutoCorrect.get_default();
            var dlg = make(r, _("AutoCorrect"), 460, 640);
            var box = body(dlg);
            var g = new PreferencesGroup(_("As you type"));
            var caps = switch_row(g, _("Capitalize first letter of sentences"), null, ac.capitalize_sentences);
            var two = switch_row(g, _("Correct TWo INitial CApitals"), null, ac.two_initial_caps);
            var days = switch_row(g, _("Capitalize names of days"), null, ac.capitalize_days);
            var rep = switch_row(g, _("Replace text as you type"), null, ac.replace_text);
            var lists = switch_row(g, _("Automatic bulleted and numbered lists"), null, ac.auto_lists);
            var quotes = switch_row(g, _("Typographic quotes"), null, ac.smart_quotes);
            var links = switch_row(g, _("Internet paths as links"), null, ac.auto_hyperlinks);
            box.append(g);
            var eg = new PreferencesGroup(_("Replacements"));
            var from = entry_row(eg, _("Replace"), "");
            var to = entry_row(eg, _("With"), r.ed.has_selection ? r.ed.selected_text() : "");
            var add = new Button.with_label(_("Add"));
            add.valign = Gtk.Align.CENTER;
            box.append(eg);
            var list = new PreferencesGroup();
            Apply fill = () => {};
            fill = () => {
                list.clear();
                foreach (var e in ac.entries.entries) {
                    var row = new ActionRow(e.key, e.value);
                    string k = e.key;
                    var del = new Button.from_icon_name("user-trash-symbolic");
                    del.add_css_class("flat");
                    del.valign = Gtk.Align.CENTER;
                    del.clicked.connect(() => {
                        ac.entries.unset(k);
                        fill();
                    });
                    row.add_suffix(del);
                    list.add_row(row);
                }
            };
            add.clicked.connect(() => {
                if (from.text.strip() == "") return;
                ac.entries[from.text.strip()] = to.text;
                from.text = "";
                to.text = "";
                fill();
            });
            to.add_suffix(add);
            fill();
            box.append(list);
            footer(dlg, _("Save"), () => {
                ac.capitalize_sentences = caps.active;
                ac.two_initial_caps = two.active;
                ac.capitalize_days = days.active;
                ac.replace_text = rep.active;
                ac.auto_lists = lists.active;
                ac.smart_quotes = quotes.active;
                ac.auto_hyperlinks = links.active;
                try {
                    ac.save();
                } catch (Error e) {
                    r.toast(e.message);
                }
            });
            dlg.present();
        }

        public static void paste_special(WriteRichEditor r) {
            var dlg = make(r, _("Paste Special"), 380, 360);
            var box = body(dlg);
            var g = new PreferencesGroup();
            string[] modes = { "keep", "merge", "text", "picture" };
            string[] labels = { _("Keep source formatting"), _("Merge formatting"), _("Keep text only"), _("Picture") };
            for (int i = 0; i < 4; i++) {
                var row = new ActionRow(labels[i]);
                string m = modes[i];
                row.activated.connect(() => {
                    dlg.close();
                    r.paste.begin(m);
                });
                g.add_row(row);
            }
            box.append(g);
            close_footer(dlg);
            dlg.present();
        }

        public static void find_replace(WriteRichEditor r) {
            var dlg = make(r, _("Find and Replace"), 480, 620);
            var box = body(dlg);
            var g = new PreferencesGroup();
            var find = entry_row(g, _("Find what"), r.ed.has_selection ? r.ed.selected_text() : "");
            var rep = entry_row(g, _("Replace with"), "");
            box.append(g);
            var o = new PreferencesGroup(_("Options"), _("Special: ^t tab, ^l line break, ^m page break, ^p paragraph mark in replacements, ^& found text. Wildcards: ? any character, * any text, [abc], < > word boundaries, (group) and \\1 in the replacement."));
            var mc = switch_row(o, _("Match case"), null, false);
            var ww = switch_row(o, _("Whole words only"), null, false);
            var wc = switch_row(o, _("Use wildcards"), null, false);
            var rx = switch_row(o, _("Regular expression"), null, false);
            var notes = switch_row(o, _("Include headers, footers and notes"), null, true);
            box.append(o);
            var fg = new PreferencesGroup(_("Format"));
            var fbold = drop_row(fg, _("Bold"), { _("Any"), _("Bold"), _("Not bold") }, 0);
            var fital = drop_row(fg, _("Italic"), { _("Any"), _("Italic"), _("Not italic") }, 0);
            var ids = new Gee.ArrayList<string>();
            var names = new Gee.ArrayList<string>();
            ids.add("");
            names.add(_("Any style"));
            foreach (var s in r.doc.styles.of_kind(StyleType.PARAGRAPH)) {
                ids.add(s.id);
                names.add(s.name);
            }
            var fstyle = drop_row(fg, _("Style"), names.to_array(), 0);
            var rbold = drop_row(fg, _("Replace with bold"), { _("Unchanged"), _("Bold"), _("Not bold") }, 0);
            var rhigh = switch_row(fg, _("Highlight replacements"), null, false);
            box.append(fg);
            var status = new Label("");
            status.add_css_class("dim-label");
            box.append(status);
            OptsFn opts = () => {
                var fo = new FindOptions();
                fo.query = find.text;
                fo.match_case = mc.active;
                fo.whole_word = ww.active;
                fo.wildcards = wc.active;
                fo.regex = rx.active;
                fo.include_notes = notes.active;
                fo.include_headers = notes.active;
                fo.bold = fbold.selected == 0 ? Tri.INHERIT : Tri.of(fbold.selected == 1);
                fo.italic = fital.selected == 0 ? Tri.INHERIT : Tri.of(fital.selected == 1);
                fo.style = ids[(int) fstyle.selected] == "" ? null : ids[(int) fstyle.selected];
                return fo;
            };
            var bar = new Box(Orientation.HORIZONTAL, 6);
            var next = new Button.with_label(_("Find Next"));
            next.clicked.connect(() => {
                try {
                    var ms = Finder.find_all(r.doc, opts());
                    status.label = ngettext("%d match", "%d matches", ms.size).printf(ms.size);
                    if (ms.size == 0) return;
                    var order = Story.all(r.doc);
                    Pos a, b;
                    r.ed.ordered(out a, out b);
                    int cur = order.index_of(b.para);
                    foreach (var m in ms) {
                        int mi = order.index_of(m.para);
                        if (mi > cur || (mi == cur && m.start >= b.offset)) {
                            r.ed.select(new Pos(m.para, m.start), new Pos(m.para, m.end));
                            return;
                        }
                    }
                    r.ed.select(new Pos(ms[0].para, ms[0].start), new Pos(ms[0].para, ms[0].end));
                } catch (RegexError e) {
                    status.label = e.message;
                }
            });
            bar.append(next);
            var one = new Button.with_label(_("Replace"));
            one.clicked.connect(() => {
                try {
                    var fo = opts();
                    var ms = Finder.find_all(r.doc, fo);
                    Pos a, b;
                    r.ed.ordered(out a, out b);
                    foreach (var m in ms) {
                        if (m.para == a.para && m.start == a.offset && m.end == b.offset) {
                            r.ed.checkpoint(_("Replace"));
                            Finder.replace_one_raw(r.ed, m, Finder.expand_replacement(rep.text, m, fo.wildcards || fo.regex), replacement_fmt(rbold, rhigh));
                            break;
                        }
                    }
                    next.clicked();
                } catch (RegexError e) {
                    status.label = e.message;
                }
            });
            bar.append(one);
            var all = new Button.with_label(_("Replace All"));
            all.add_css_class("suggested-action");
            all.clicked.connect(() => {
                try {
                    int n = Finder.replace_all(r.ed, opts(), rep.text, replacement_fmt(rbold, rhigh));
                    status.label = ngettext("%d replacement made", "%d replacements made", n).printf(n);
                } catch (RegexError e) {
                    status.label = e.message;
                }
            });
            bar.append(all);
            box.append(bar);
            close_footer(dlg);
            dlg.present();
        }

        private static CharMutator? replacement_fmt(WriteChoice bold, SwitchRow high) {
            uint b = bold.selected;
            bool h = high.active;
            if (b == 0 && !h) return null;
            return (c) => {
                if (b == 1) c.bold = Tri.ON;
                else if (b == 2) c.bold = Tri.OFF;
                if (h) c.highlight = "#ffff00";
            };
        }

        public static void go_to(WriteRichEditor r) {
            var dlg = make(r, _("Go To"), 380, 320);
            var box = body(dlg);
            var g = new PreferencesGroup();
            var kind = drop_row(g, _("Go to what"), { _("Page"), _("Section"), _("Heading"), _("Comment"), _("Footnote"), _("Table") }, 0);
            var num = spin_row(g, _("Number"), null, 1, 99999, 1, 1, 0);
            box.append(g);
            footer(dlg, _("Go To"), () => {
                int n = (int) num.value;
                switch ((int) kind.selected) {
                    case 0:
                        r.view.scroll_to_page(n - 1);
                        if (r.view.lay != null && n - 1 < r.view.lay.pages.size) {
                            foreach (var lb in r.view.lay.pages[n - 1].lines) if (lb.region == Region.BODY) {
                                r.ed.set_caret(new Pos(lb.para, lb.pl.text.byte_to_model(lb.info.start_byte)));
                                break;
                            }
                        }
                        break;
                    case 1:
                        int s = 1;
                        foreach (var b in r.doc.body.items) {
                            var p = b as Paragraph;
                            if (s == n && p != null) {
                                r.view.scroll_to_para(p);
                                break;
                            }
                            if (p != null && p.section != null) s++;
                        }
                        break;
                    case 2:
                        int h = 0;
                        foreach (var p in Story.paragraphs(r.doc.body)) if (r.doc.styles.outline_level(p) >= 0 && ++h == n) {
                            r.view.scroll_to_para(p);
                            break;
                        }
                        break;
                    case 3:
                        var ids = r.comment_order();
                        if (n - 1 < ids.size) r.goto_comment(ids[n - 1]);
                        break;
                    case 4:
                        int f = 0;
                        foreach (var p in Story.paragraphs(r.doc.body)) {
                            int off = 0;
                            foreach (var i in p.inlines) {
                                if (i is NoteRef && ++f == n) {
                                    r.ed.set_caret(new Pos(p, off));
                                    return;
                                }
                                off += i.length;
                            }
                        }
                        break;
                    default:
                        int t = 0;
                        foreach (var b in r.doc.body.items) if (b is Table && ++t == n) {
                            var fp = ((Table) b).rows[0].cells[0].blocks.first_paragraph();
                            if (fp != null) r.view.scroll_to_para(fp);
                            break;
                        }
                        break;
                }
            });
            dlg.present();
        }

        public static void doc_properties(WriteRichEditor r) {
            var m = r.doc.meta;
            var dlg = make(r, _("Document Properties"), 460, 640);
            var box = body(dlg);
            var g = new PreferencesGroup(_("Summary"));
            var title = entry_row(g, _("Title"), m.title);
            var subject = entry_row(g, _("Subject"), m.subject);
            var author = entry_row(g, _("Author"), m.author);
            var manager = entry_row(g, _("Manager"), m.manager);
            var company = entry_row(g, _("Company"), m.company);
            var category = entry_row(g, _("Category"), m.category);
            var keywords = entry_row(g, _("Keywords"), m.keywords);
            var comments = entry_row(g, _("Comments"), m.description);
            box.append(g);
            var s = new PreferencesGroup(_("Statistics"));
            var st = Stats.compute(r.doc, false);
            s.add_row(new ActionRow(_("Created"), m.created != "" ? m.created : _("Not saved yet")));
            s.add_row(new ActionRow(_("Modified"), m.modified != "" ? m.modified : "-"));
            s.add_row(new ActionRow(_("Last saved by"), m.last_modified_by != "" ? m.last_modified_by : "-"));
            s.add_row(new ActionRow(_("Revision"), m.revision.to_string()));
            s.add_row(new ActionRow(_("Words"), st.words.to_string()));
            box.append(s);
            var cg = new PreferencesGroup(_("Custom properties"), _("One per line as Name = Value"));
            var sb = new StringBuilder();
            foreach (var e in m.custom.entries) sb.append("%s = %s\n".printf(e.key, e.value));
            var tv = new Gtk.TextView();
            tv.buffer.text = sb.str;
            tv.height_request = 90;
            tv.add_css_class("write-props-custom");
            box.append(cg);
            box.append(tv);
            footer(dlg, _("Save"), () => {
                r.ed.checkpoint(_("Properties"));
                m.title = title.text;
                m.subject = subject.text;
                m.author = author.text;
                m.manager = manager.text;
                m.company = company.text;
                m.category = category.text;
                m.keywords = keywords.text;
                m.description = comments.text;
                m.custom.clear();
                foreach (string line in tv.buffer.text.split("\n")) {
                    int eq = line.index_of_char('=');
                    if (eq <= 0) continue;
                    m.custom[line.substring(0, eq).strip()] = line.substring(eq + 1).strip();
                }
                r.modified = true;
                r.title_changed();
                r.update_fields();
            });
            dlg.present();
        }

        public static void versions(WriteRichEditor r) {
            if (r.file == null) {
                r.toast(_("Save the document to keep a version history."));
                return;
            }
            var list = WriteFiles.list_versions(r.file);
            var dlg = make(r, _("Version History"), 520, 600);
            var box = body(dlg);
            var g = new PreferencesGroup(_("Versions"), _("A version is kept every time the document is saved."));
            if (list.size == 0) g.add_row(new ActionRow(_("No earlier versions yet")));
            foreach (string path in list) {
                string name = Path.get_basename(path);
                string when = name.length >= 15 ? "%s-%s-%s %s:%s:%s".printf(name.substring(0, 4), name.substring(4, 2), name.substring(6, 2), name.substring(9, 2), name.substring(11, 2), name.substring(13, 2)) : name;
                var row = new ActionRow(when);
                string pth = path;
                var open = new Button.with_label(_("Open"));
                open.valign = Gtk.Align.CENTER;
                open.clicked.connect(() => {
                    try {
                        Write.FileFormat fmt;
                        var d = WriteFiles.load(GLib.File.new_for_path(pth), out fmt);
                        dlg.close();
                        r.file = null;
                        r.set_document(d);
                        r.modified = true;
                        r.title_changed();
                    } catch (Error e) {
                        r.toast(e.message);
                    }
                });
                row.add_suffix(open);
                var cmp = new Button.with_label(_("Compare"));
                cmp.valign = Gtk.Align.CENTER;
                cmp.clicked.connect(() => {
                    try {
                        Write.FileFormat fmt;
                        var old = WriteFiles.load(GLib.File.new_for_path(pth), out fmt);
                        var result = Review.compare(old, r.doc, r.ed.author);
                        dlg.close();
                        r.file = null;
                        r.set_document(result);
                        r.modified = true;
                        r.title_changed();
                        r.show_right("review");
                    } catch (Error e) {
                        r.toast(e.message);
                    }
                });
                row.add_suffix(cmp);
                var restore = new Button.with_label(_("Restore"));
                restore.valign = Gtk.Align.CENTER;
                restore.add_css_class("suggested-action");
                restore.clicked.connect(() => {
                    try {
                        Write.FileFormat fmt;
                        var d = WriteFiles.load(GLib.File.new_for_path(pth), out fmt);
                        r.ed.checkpoint(_("Restore Version"));
                        r.doc.assign(d);
                        r.touch_all();
                        dlg.close();
                    } catch (Error e) {
                        r.toast(e.message);
                    }
                });
                row.add_suffix(restore);
                g.add_row(row);
            }
            box.append(g);
            close_footer(dlg);
            dlg.present();
        }

        public static void insert_file(WriteRichEditor r) {
            var fd = new Gtk.FileDialog();
            fd.title = _("Insert Text From File");
            var fl = new GLib.ListStore(typeof(Gtk.FileFilter));
            fl.append(WriteFiles.all_documents());
            fd.filters = fl;
            fd.open.begin(r.window, null, (o, res) => {
                try {
                    var f = fd.open.end(res);
                    Write.FileFormat fmt;
                    var d = WriteFiles.load(f, out fmt);
                    foreach (var s in d.styles.list) if (r.doc.styles.get(s.id) == null) r.doc.styles.add(s.copy());
                    foreach (var def in d.numbering.defs) if (r.doc.numbering.def(def.id) == null) r.doc.numbering.defs.add(def.copy());
                    foreach (var n in d.numbering.instances) if (r.doc.numbering.instance(n.id) == null) r.doc.numbering.instances.add(n.copy());
                    r.ed.checkpoint(_("Insert File"));
                    r.ed.insert_blocks(d.body);
                } catch (Error e) {
                    if (!(e is Gtk.DialogError.DISMISSED)) r.toast(e.message);
                }
            });
        }

        public static void reveal_formatting(WriteRichEditor r) {
            var p = r.ed.focus.para;
            var c = r.doc.styles.resolve_char(p, p.props_at(r.ed.focus.offset));
            var pp = r.doc.styles.resolve_para(p);
            var dlg = make(r, _("Reveal Formatting"), 420, 560);
            var box = body(dlg);
            var g = new PreferencesGroup(_("Font"));
            g.add_row(new ActionRow(_("Font"), "%s %s pt".printf(c.font ?? "", X.num(c.size))));
            g.add_row(new ActionRow(_("Style"), (c.bold.on() ? _("Bold") + " " : "") + (c.italic.on() ? _("Italic") : "") + (c.style != null ? " (" + c.style + ")" : "")));
            g.add_row(new ActionRow(_("Color"), c.color ?? _("Automatic")));
            if (c.highlight != null) g.add_row(new ActionRow(_("Highlight"), c.highlight));
            if (c.lang != null) g.add_row(new ActionRow(_("Language"), c.lang));
            box.append(g);
            var pg = new PreferencesGroup(_("Paragraph"));
            pg.add_row(new ActionRow(_("Style"), r.doc.styles.get(p.style) != null ? r.doc.styles.get(p.style).name : p.style));
            string[] al = { _("Left"), _("Centered"), _("Right"), _("Justified") };
            pg.add_row(new ActionRow(_("Alignment"), al[((int) pp.align).clamp(0, 3)]));
            pg.add_row(new ActionRow(_("Indentation"), _("Left %s, right %s, first line %s pt").printf(X.num(pp.ind_left), X.num(pp.ind_right), X.num(pp.ind_first))));
            pg.add_row(new ActionRow(_("Spacing"), _("Before %s pt, after %s pt, line %s").printf(X.num(pp.space_before), X.num(pp.space_after), X.num(pp.line))));
            if (pp.num_id > 0) pg.add_row(new ActionRow(_("List"), _("Level %d").printf(int.max(0, pp.num_level) + 1)));
            box.append(pg);
            var sg = new PreferencesGroup(_("Section"));
            var s = r.doc.section_for(p);
            sg.add_row(new ActionRow(_("Page"), "%s \u00d7 %s pt %s".printf(X.num(s.page_w), X.num(s.page_h), s.landscape ? _("landscape") : _("portrait"))));
            sg.add_row(new ActionRow(_("Margins"), "%s / %s / %s / %s pt".printf(X.num(s.margin_top), X.num(s.margin_bottom), X.num(s.margin_left), X.num(s.margin_right))));
            sg.add_row(new ActionRow(_("Columns"), s.columns.to_string()));
            box.append(sg);
            close_footer(dlg);
            dlg.present();
        }

        public static void equation_text(WriteRichEditor r, EquationRun e, bool insert = false) {
            var dlg = make(r, _("Equation"), 460, 320);
            var box = body(dlg);
            var g = new PreferencesGroup(_("Equation"), _("Type the equation in LaTeX, for example \\frac{a}{b} + x^2. Install Formula for visual editing."));
            var tex = entry_row(g, _("LaTeX"), e.latex != "" ? e.latex : e.linear_text());
            var disp = switch_row(g, _("Display on its own line"), null, e.display);
            box.append(g);
            footer(dlg, insert ? _("Insert") : _("Save"), () => {
                r.ed.checkpoint(_("Equation"));
                e.latex = tex.text.strip();
                e.mathml = LatexMath.to_mathml(e.latex, disp.active);
                e.omml = null;
                e.display = disp.active;
                e.preview = null;
                e.width = 0;
                if (insert) r.ed.insert_inline(e);
                var p = r.find_para_of(e);
                if (p != null) p.touch();
                r.ed.changed();
            });
            dlg.present();
        }

        public static void equation_gallery(WriteRichEditor r) {
            var dlg = make(r, _("Equation Gallery"), 460, 520);
            var box = body(dlg);
            var items = Singularity.Equations.UserGallery.get_default().items();
            var g = new PreferencesGroup(_("Saved Equations"), items.size == 0 ? _("Equations saved in Formula with Save as New Equation appear here.") : null);
            string[,] builtin = {
                { _("Quadratic formula"), "x=\\frac{-b\\pm\\sqrt{b^2-4ac}}{2a}" },
                { _("Pythagorean theorem"), "a^2+b^2=c^2" },
                { _("Sum of integers"), "\\sum_{k=1}^{n}k=\\frac{n(n+1)}{2}" },
                { _("Area of a circle"), "A=\\pi r^2" },
                { _("Euler identity"), "e^{i\\pi}+1=0" }
            };
            for (int i = 0; i < builtin.length[0]; i++) {
                var row = new ActionRow(builtin[i, 0], builtin[i, 1]);
                string tex = builtin[i, 1];
                row.activated.connect(() => {
                    dlg.close();
                    var e = new EquationRun(EquationSupport.available() ? "" : LatexMath.to_mathml(tex, true));
                    e.latex = tex;
                    e.display = true;
                    r.insert_equation_run.begin(e);
                });
                g.add_row(row);
            }
            foreach (var it in items) {
                var row = new ActionRow(it.name, it.category != "" ? it.category : it.latex);
                var entry = it;
                row.activated.connect(() => {
                    dlg.close();
                    var e = new EquationRun(entry.mathml);
                    e.latex = entry.latex;
                    e.display = true;
                    r.insert_equation_run.begin(e);
                });
                g.add_row(row);
            }
            box.append(g);
            close_footer(dlg);
            dlg.present();
        }

        private const string TRANSLATE_BUS = "dev.sinty.TranslateService";
        private const string TRANSLATE_PATH = "/dev/sinty/TranslateService";

        public static void translate(WriteRichEditor r) {
            if (!DesktopServices.present(TRANSLATE_BUS)) {
                r.toast(_("The translation service of the desktop is not available."));
                return;
            }
            string src = r.ed.has_selection ? r.ed.selected_text() : r.ed.focus.para.plain_text();
            if (src.strip() == "") {
                r.toast(_("Select the text to translate."));
                return;
            }
            var dlg = make(r, _("Translate"), 520, 560);
            var box = body(dlg);
            var g = new PreferencesGroup();
            var target = drop_row(g, _("Translate to"), { _("Loading\u2026") }, 0);
            var info = new ActionRow(_("Detected language"), "");
            g.add_row(info);
            box.append(g);
            var out_view = new Gtk.TextView();
            out_view.wrap_mode = WrapMode.WORD_CHAR;
            out_view.editable = false;
            out_view.height_request = 200;
            out_view.add_css_class("write-chart-data");
            box.append(out_view);
            var codes = new Gee.ArrayList<string>();
            Apply run = () => {};
            run = () => {
                if (codes.size == 0) return;
                string code = codes[(int) target.selected];
                out_view.buffer.text = _("Translating\u2026");
                Bus.get.begin(BusType.SESSION, null, (o, res) => {
                    try {
                        var bus = Bus.get.end(res);
                        bus.call.begin(TRANSLATE_BUS, TRANSLATE_PATH, TRANSLATE_BUS, "Translate", new Variant("(sss)", src, "auto", code), new VariantType("(sss)"), DBusCallFlags.NONE, 30000, null, (o2, res2) => {
                            try {
                                var reply = bus.call.end(res2);
                                string translation, detected, provider;
                                reply.get("(sss)", out translation, out detected, out provider);
                                out_view.buffer.text = translation;
                                info.subtitle = provider != "" ? "%s  (%s)".printf(detected, provider) : detected;
                            } catch (Error e) {
                                DBusError.strip_remote_error(e);
                                out_view.buffer.text = e.message;
                            }
                        });
                    } catch (Error e) {
                        out_view.buffer.text = e.message;
                    }
                });
            };
            Bus.get.begin(BusType.SESSION, null, (o, res) => {
                try {
                    var bus = Bus.get.end(res);
                    var reply = bus.call_sync(TRANSLATE_BUS, TRANSLATE_PATH, TRANSLATE_BUS, "LanguageNames", null, new VariantType("(a{ss})"), DBusCallFlags.NONE, 5000, null);
                    var pairs = new Gee.TreeMap<string, string>();
                    var iter = reply.get_child_value(0).iterator();
                    string code, name;
                    while (iter.next("{ss}", out code, out name)) pairs[name] = code;
                    string def = "en";
                    try {
                        var dt = bus.call_sync(TRANSLATE_BUS, TRANSLATE_PATH, TRANSLATE_BUS, "DefaultTarget", null, new VariantType("(s)"), DBusCallFlags.NONE, 5000, null);
                        dt.get("(s)", out def);
                    } catch (Error e) {
                    }
                    string[] names = {};
                    int sel = 0;
                    foreach (var e in pairs.entries) {
                        if (e.value == def) sel = names.length;
                        names += e.key;
                        codes.add(e.value);
                    }
                    target.set_labels(names);
                    target.selected = sel;
                    target.notify["selected"].connect(() => run());
                    run();
                } catch (Error e) {
                    DBusError.strip_remote_error(e);
                    out_view.buffer.text = e.message;
                }
            });
            footer(dlg, r.ed.has_selection ? _("Replace") : _("Insert Below"), () => {
                string t = out_view.buffer.text;
                if (t == "") return;
                r.ed.checkpoint(_("Translate"));
                if (r.ed.has_selection) {
                    Pos a, b;
                    r.ed.ordered(out a, out b);
                    var props = a.para.props_at(a.offset + 1);
                    r.ed.delete_selection();
                    r.ed.insert_text(t, props);
                } else {
                    r.ed.set_caret(new Pos(r.ed.focus.para, r.ed.focus.para.length));
                    r.ed.split_paragraph();
                    r.ed.insert_text(t, r.ed.props_for_insert());
                }
            });
            dlg.present();
        }

        public static void live_share(WriteRichEditor r) {
            var dlg = make(r, _("Edit Together"), 480, 560);
            var box = body(dlg);
            if (r.live != null) {
                var g = new PreferencesGroup(r.live.mode == WriteLiveSession.Mode.FOLDER ? _("Shared through a folder") : _("Live session"));
                if (r.live.mode == WriteLiveSession.Mode.HOST) {
                    var link = entry_row(g, _("Link"), r.live.link);
                    var copy = new Button.from_icon_name("edit-copy-symbolic");
                    copy.valign = Gtk.Align.CENTER;
                    copy.add_css_class("flat");
                    copy.tooltip_text = _("Copy link");
                    copy.clicked.connect(() => {
                        link.get_clipboard().set_text(r.live.link);
                        r.toast(_("Link copied."));
                    });
                    link.add_suffix(copy);
                } else {
                    g.add_row(new ActionRow(r.live.mode == WriteLiveSession.Mode.FOLDER ? _("Folder") : _("Link"), r.live.link));
                }
                box.append(g);
                var pg = new PreferencesGroup(_("People"));
                pg.add_row(new ActionRow(r.live.name, _("You")));
                foreach (var p in r.live.peers.values) pg.add_row(new ActionRow(p.name, p.color));
                box.append(pg);
                footer(dlg, _("Stop Sharing"), () => r.stop_live());
                dlg.present();
                return;
            }
            var hg = new PreferencesGroup(_("On this network"), _("Others join with the link and its key. Changes merge paragraph by paragraph, and everyone sees each other's cursor."));
            var start = new ActionRow(_("Start a live session"), _("Creates a link to share"));
            start.activated.connect(() => {
                try {
                    r.start_live_host();
                    dlg.close();
                    live_share(r);
                } catch (Error e) {
                    r.toast(e.message);
                }
            });
            hg.add_row(start);
            var join = entry_row(hg, _("Join with a link"), "");
            var jb = new Button.with_label(_("Join"));
            jb.valign = Gtk.Align.CENTER;
            jb.clicked.connect(() => {
                string l = join.text.strip();
                if (l == "") return;
                dlg.close();
                r.join_live.begin(l, (o, res) => {
                    try {
                        r.join_live.end(res);
                        r.toast(_("Joined the live document."));
                    } catch (Error e) {
                        r.toast(e.message);
                    }
                });
            });
            join.add_suffix(jb);
            box.append(hg);
            var cg = new PreferencesGroup(_("Through a cloud folder"), _("Choose a folder of an online account that everyone can open. Write keeps the session in it, so it also works across networks."));
            var fstart = new ActionRow(_("Share in a folder"), _("Start editing together in a folder"));
            var fjoin = new ActionRow(_("Join from a folder"), _("Open a document someone shared in a folder"));
            cg.add_row(fstart);
            cg.add_row(fjoin);
            box.append(cg);
            foreach (var row in new ActionRow[] { fstart, fjoin }) {
                bool create = row == fstart;
                row.activated.connect(() => {
                    var fd = new Gtk.FileDialog();
                    fd.title = create ? _("Choose a Shared Folder") : _("Choose the Shared Folder");
                    string cloud = Path.build_filename(Environment.get_home_dir(), "Cloud");
                    if (FileUtils.test(cloud, FileTest.IS_DIR)) fd.initial_folder = GLib.File.new_for_path(cloud);
                    fd.select_folder.begin(r.window, null, (o, res) => {
                        try {
                            var folder = fd.select_folder.end(res);
                            string dir = Path.build_filename(folder.get_path(), ".write-live");
                            r.start_live_folder(dir, create);
                            dlg.close();
                            r.toast(create ? _("The document is shared in the folder.") : _("Joined the shared document."));
                        } catch (Error e) {
                            if (!(e is Gtk.DialogError.DISMISSED)) r.toast(e.message);
                        }
                    });
                });
            }
            close_footer(dlg);
            dlg.present();
        }

        public static void color_menu(WriteRichEditor r, bool highlight) {
            var item = highlight ? r.fbar.highlight_menu : r.fbar.color_menu;
            if (item.button.get_mapped()) {
                item.popup();
                return;
            }
            WriteRibbon.popup_menu(r.fbar, (m) => fill_color_menu(r, highlight, m));
        }

        public static void fill_color_menu(WriteRichEditor r, bool highlight, Singularity.Widgets.ContextMenu m) {
            m.add_css_class("write-menu");
            var grid = new Gtk.Grid();
            grid.row_spacing = 6;
            grid.column_spacing = 6;
            grid.margin_start = 6;
            grid.margin_end = 6;
            grid.margin_top = 4;
            grid.margin_bottom = 6;
            grid.halign = Gtk.Align.CENTER;
            string[] colors = highlight
                ? new string[] { "#ffff00", "#00ff00", "#00ffff", "#ff00ff", "#0000ff", "#ff0000", "#000080", "#008080", "#008000", "#800080", "#800000", "#808000", "#808080", "#c0c0c0", "#000000", "#ffffff" }
                : new string[] { "#000000", "#404040", "#7f7f7f", "#c00000", "#ff0000", "#ffc000", "#ffff00", "#92d050", "#00b050", "#00b0f0", "#0070c0", "#002060", "#7030a0", "#2f5496", "#833c0b", "#ffffff" };
            for (int i = 0; i < colors.length; i++) {
                string c = colors[i];
                var b = new Gtk.Button();
                b.add_css_class("flat");
                b.add_css_class("write-swatch");
                b.tooltip_text = c;
                var dot = new Gtk.DrawingArea();
                dot.set_size_request(20, 20);
                dot.set_draw_func((area, cr, w, h) => {
                    double rr, gg, bb;
                    Write.Palette.rgbd(c, out rr, out gg, out bb);
                    cr.arc(w / 2.0, h / 2.0, 9, 0, 2 * Math.PI);
                    cr.set_source_rgb(rr, gg, bb);
                    cr.fill_preserve();
                    var fg = area.get_color();
                    cr.set_source_rgba(fg.red, fg.green, fg.blue, 0.25);
                    cr.set_line_width(1);
                    cr.stroke();
                });
                b.child = dot;
                b.clicked.connect(() => {
                    m.popdown();
                    r.run(highlight ? "highlight" : "text-color", new Variant.string(c));
                });
                grid.attach(b, i % 8, i / 8);
            }
            m.add_widget(grid);
            m.add_separator();
            m.add_item(highlight ? _("No Highlight") : _("Automatic"), null, () => {
                r.run(highlight ? "highlight" : "text-color", new Variant.string(highlight ? "none" : "auto"));
            });
            m.add_item(_("More Colors\u2026"), "color-select-symbolic", () => {
                var cd = new Gtk.ColorDialog();
                cd.with_alpha = false;
                cd.choose_rgba.begin(r.window, null, null, (o, res) => {
                    try {
                        var rgba = cd.choose_rgba.end(res);
                        r.run(highlight ? "highlight" : "text-color", new Variant.string(hex(rgba)));
                    } catch (Error e) {
                    }
                });
            });
        }
    }

    public class WriteChoice : Object {
        public SelectionRow row;
        private string[] labels;
        private uint _selected = 0;
        private bool syncing = false;

        public uint selected {
            get { return _selected; }
            set {
                _selected = value;
                syncing = true;
                row.current_value = value < labels.length ? labels[value] : "";
                syncing = false;
            }
        }

        public bool sensitive {
            get { return row.sensitive; }
            set { row.sensitive = value; }
        }

        public WriteChoice(string title, string[] labels, uint selected) {
            this.labels = labels;
            row = new SelectionRow(title, labels, selected < labels.length ? labels[selected] : "");
            _selected = selected;
            row.selected.connect((item) => {
                if (syncing) return;
                for (uint i = 0; i < this.labels.length; i++) {
                    if (this.labels[i] == item) {
                        if (_selected != i) this.selected = i;
                        return;
                    }
                }
            });
        }

        public void set_labels(string[] labels) {
            this.labels = labels;
            row.set_items(labels);
            selected = 0;
        }
    }

    public class MacroLibrary : Object {
        private static string path() {
            return Path.build_filename(Environment.get_user_config_dir(), "singularity-write", "macros.txt");
        }

        public static Gee.ArrayList<string> load() {
            var list = new Gee.ArrayList<string>();
            try {
                string t;
                if (!FileUtils.get_contents(path(), out t)) return list;
                foreach (string block in t.split("\n\u001e\n")) if (block.strip() != "") list.add(block.strip());
            } catch (Error e) {
            }
            return list;
        }

        private static void store(Gee.ArrayList<string> list) {
            try {
                DirUtils.create_with_parents(Path.get_dirname(path()), 0700);
                FileUtils.set_contents(path(), string.joinv("\n\u001e\n", list.to_array()));
            } catch (Error e) {
            }
        }

        public static void add(string m) {
            var l = load();
            l.add(m);
            store(l);
        }

        public static void remove(string m) {
            var l = load();
            l.remove(m);
            store(l);
        }
    }

    public class LatexMath : Object {
        public static string to_mathml(string tex, bool display) {
            var sb = new StringBuilder("<math xmlns=\"http://www.w3.org/1998/Math/MathML\" display=\"%s\"><semantics><mrow>".printf(display ? "block" : "inline"));
            int i = 0;
            parse(tex, ref i, sb, false);
            sb.append("</mrow><annotation encoding=\"application/x-tex\">%s</annotation></semantics></math>".printf(X.esc(tex)));
            return sb.str;
        }

        private static string group(string t, ref int i) {
            while (i < t.length && t[i] == ' ') i++;
            if (i >= t.length) return "";
            if (t[i] == '{') {
                int depth = 0;
                int s = i;
                for (; i < t.length; i++) {
                    if (t[i] == '{') depth++;
                    else if (t[i] == '}') {
                        depth--;
                        if (depth == 0) {
                            i++;
                            return t.substring(s + 1, i - s - 2);
                        }
                    }
                }
                return t.substring(s + 1);
            }
            if (t[i] == '\\') {
                int s = i;
                i++;
                while (i < t.length && t[i].isalpha()) i++;
                return t.substring(s, i - s);
            }
            string r = t.substring(i, 1);
            i++;
            return r;
        }

        private static string sub_ml(string t) {
            var sb = new StringBuilder("<mrow>");
            int i = 0;
            parse(t, ref i, sb, false);
            sb.append("</mrow>");
            return sb.str;
        }

        private static string? symbol(string cmd) {
            switch (cmd) {
                case "alpha": return "\u03b1";
                case "beta": return "\u03b2";
                case "gamma": return "\u03b3";
                case "delta": return "\u03b4";
                case "epsilon": return "\u03b5";
                case "theta": return "\u03b8";
                case "lambda": return "\u03bb";
                case "mu": return "\u03bc";
                case "pi": return "\u03c0";
                case "sigma": return "\u03c3";
                case "phi": return "\u03c6";
                case "omega": return "\u03c9";
                case "Delta": return "\u0394";
                case "Sigma": return "\u03a3";
                case "Omega": return "\u03a9";
                case "infty": return "\u221e";
                case "times": return "\u00d7";
                case "cdot": return "\u22c5";
                case "pm": return "\u00b1";
                case "leq": return "\u2264";
                case "geq": return "\u2265";
                case "neq": return "\u2260";
                case "approx": return "\u2248";
                case "sum": return "\u2211";
                case "prod": return "\u220f";
                case "int": return "\u222b";
                case "partial": return "\u2202";
                case "nabla": return "\u2207";
                case "in": return "\u2208";
                case "cdots": return "\u22ef";
                case "ldots": return "\u2026";
                default: return null;
            }
        }

        private static void parse(string t, ref int i, StringBuilder sb, bool one) {
            while (i < t.length) {
                char c = t[i];
                if (c == ' ') {
                    i++;
                    continue;
                }
                string atom;
                if (c == '\\') {
                    int s = i;
                    i++;
                    while (i < t.length && t[i].isalpha()) i++;
                    string cmd = t.substring(s + 1, i - s - 1);
                    if (cmd == "frac") {
                        string a = group(t, ref i);
                        string b = group(t, ref i);
                        atom = "<mfrac>" + sub_ml(a) + sub_ml(b) + "</mfrac>";
                    } else if (cmd == "sqrt") {
                        atom = "<msqrt>" + sub_ml(group(t, ref i)) + "</msqrt>";
                    } else if (cmd == "left" || cmd == "right") {
                        string d = group(t, ref i);
                        atom = d == "." ? "" : "<mo>%s</mo>".printf(X.esc(d));
                    } else {
                        string? sym = symbol(cmd);
                        if (sym != null) atom = (cmd == "sum" || cmd == "prod" || cmd == "int" || cmd == "times" || cmd == "cdot" || cmd == "pm" || cmd == "leq" || cmd == "geq" || cmd == "neq" || cmd == "approx" || cmd == "in") ? "<mo>%s</mo>".printf(sym) : "<mi>%s</mi>".printf(sym);
                        else atom = "<mi mathvariant=\"normal\">%s</mi>".printf(X.esc(cmd));
                    }
                } else if (c == '{') {
                    atom = sub_ml(group(t, ref i));
                } else if (c.isdigit()) {
                    int s = i;
                    while (i < t.length && (t[i].isdigit() || t[i] == '.')) i++;
                    atom = "<mn>%s</mn>".printf(t.substring(s, i - s));
                } else if (c.isalpha()) {
                    atom = "<mi>%c</mi>".printf(c);
                    i++;
                } else {
                    atom = "<mo>%s</mo>".printf(X.esc(t.substring(i, 1)));
                    i++;
                }
                while (i < t.length && (t[i] == '^' || t[i] == '_')) {
                    char op = t[i];
                    i++;
                    string arg = sub_ml(group(t, ref i));
                    if (i < t.length && (t[i] == '^' || t[i] == '_') && t[i] != op) {
                        i++;
                        string arg2 = sub_ml(group(t, ref i));
                        atom = op == '_' ? "<msubsup>%s%s%s</msubsup>".printf(atom, arg, arg2) : "<msubsup>%s%s%s</msubsup>".printf(atom, arg2, arg);
                    } else {
                        atom = op == '^' ? "<msup>%s%s</msup>".printf(atom, arg) : "<msub>%s%s</msub>".printf(atom, arg);
                    }
                }
                sb.append(atom);
                if (one) return;
            }
        }
    }

    public class ChartSupport : Object {
        public static Singularity.Charts.ChartSpec? spec_of(Write.ChartRun ch) {
            Singularity.Charts.ChartSpec? spec = null;
            if (ch.chart_xml != "") spec = Singularity.Charts.DrawingML.read_chart(ch.chart_xml);
            if (spec == null && ch.odf_content != "") spec = Singularity.Charts.OdfChart.read_content(ch.odf_content);
            return spec;
        }

        public static Bytes? preview(Singularity.Charts.ChartSpec spec, double w, double h) {
            var painter = new Singularity.Charts.ChartPainter();
            var surf = painter.render_image(spec, (int) Math.round(w), (int) Math.round(h), 2);
            var mem = new MemoryOutputStream.resizable();
            var st = surf.write_to_png_stream((data) => {
                try {
                    size_t n;
                    mem.write_all(data, out n);
                } catch (Error e) {
                    return Cairo.Status.WRITE_ERROR;
                }
                return Cairo.Status.SUCCESS;
            });
            if (st != Cairo.Status.SUCCESS) return null;
            try {
                mem.close();
            } catch (Error e) {
                return null;
            }
            return mem.steal_as_bytes();
        }

        public static void apply(Write.ChartRun ch, Singularity.Charts.ChartSpec spec) {
            bool ext;
            ch.chart_xml = Singularity.Charts.DrawingML.write_any(spec, out ext);
            ch.extended = ext;
            ch.odf_content = Singularity.Charts.OdfChart.write_content(spec, ch.width / 28.3464567, ch.height / 28.3464567);
            ch.odf_styles = Singularity.Charts.OdfChart.write_styles();
            ch.preview = preview(spec, ch.width, ch.height);
            ch.edited = true;
            if (ch.alt == "") ch.alt = spec.title != "" ? spec.title : _("Chart");
        }

        public static void prepare(Write.ChartRun ch) {
            if (ch.preview != null && ch.chart_xml != "" && ch.odf_content != "") return;
            var spec = spec_of(ch);
            if (spec == null) return;
            if (ch.preview == null) ch.preview = preview(spec, ch.width, ch.height);
            if (ch.chart_xml == "") {
                bool ext;
                ch.chart_xml = Singularity.Charts.DrawingML.write_any(spec, out ext);
                ch.extended = ext;
            }
            if (ch.odf_content == "") {
                ch.odf_content = Singularity.Charts.OdfChart.write_content(spec, ch.width / 28.3464567, ch.height / 28.3464567);
                ch.odf_styles = Singularity.Charts.OdfChart.write_styles();
            }
        }

        public static void prepare_all(Write.Document doc) {
            foreach (var p in Write.Story.all(doc)) {
                bool touched = false;
                foreach (var i in p.inlines) {
                    var ch = i as Write.ChartRun;
                    if (ch == null) continue;
                    bool had = ch.preview != null;
                    prepare(ch);
                    if (!had && ch.preview != null) touched = true;
                }
                if (touched) p.touch();
            }
        }

        public static string table_text(Singularity.Charts.ChartSpec spec) {
            var t = Singularity.Charts.DataTable.from_spec(spec);
            var sb = new StringBuilder();
            for (int r = 0; r < t.rows; r++) {
                string[] cells = {};
                for (int c = 0; c < t.columns; c++) cells += t.get_text(r, c);
                sb.append(string.joinv(", ", cells));
                sb.append_c('\n');
            }
            return sb.str;
        }

        public static Singularity.Charts.ChartSpec? parse(string text, Singularity.Charts.ChartSpec? style) {
            var lines = new Gee.ArrayList<Gee.ArrayList<string>>();
            int cols = 0;
            foreach (string l in text.split("\n")) {
                if (l.strip() == "") continue;
                string[] cells = l.contains("\t") ? l.split("\t") : l.split(l.contains(";") ? ";" : ",");
                var row = new Gee.ArrayList<string>();
                foreach (string c in cells) row.add(c.strip());
                cols = int.max(cols, row.size);
                lines.add(row);
            }
            if (lines.size < 2 || cols < 2) return null;
            var t = new Singularity.Charts.DataTable(lines.size, cols);
            for (int r = 0; r < lines.size; r++) {
                for (int c = 0; c < lines[r].size; c++) {
                    double v = 0;
                    string cell = lines[r][c];
                    if (r > 0 && c > 0 && double.try_parse(cell.replace(",", "."), out v)) t.set_number(r, c, v);
                    else t.set_text(r, c, cell);
                }
            }
            return t.to_spec(style, false, true, true);
        }
    }
}
