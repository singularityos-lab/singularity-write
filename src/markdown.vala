using GLib;

namespace Markdown {

    // ── Parser: Markdown text, HTML string ──────────────────────────────────

    public class Parser : Object {

        // Wrap the HTML body in a full page with dark CSS for the WebView

        public string to_full_html(string markdown) {
            string body = to_html(markdown);
            return """<!DOCTYPE html><html><head>
<meta charset="UTF-8">
<style>
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;max-width:720px;margin:0 auto;padding:24px;padding-top:60px;color:#e8eaed;background:#1e1e2e;line-height:1.6}
h1,h2,h3,h4,h5,h6{font-weight:700;margin-top:1.5em;margin-bottom:0.5em}
h1{font-size:2em;border-bottom:1px solid rgba(255,255,255,.1);padding-bottom:.3em}
h2{font-size:1.5em;border-bottom:1px solid rgba(255,255,255,.07);padding-bottom:.2em}
h3{font-size:1.25em}h4{font-size:1.1em}h5,h6{font-size:1em}
p{margin:.6em 0}
code{background:rgba(255,255,255,.1);padding:2px 5px;border-radius:4px;font-family:monospace}
pre{background:rgba(0,0,0,.3);padding:16px;border-radius:8px;overflow-x:auto}
pre code{background:none;padding:0}
blockquote{border-left:3px solid rgba(255,255,255,.2);margin:0;padding-left:16px;color:rgba(255,255,255,.6)}
a{color:#7ec8e3}
hr{border:none;border-top:1px solid rgba(255,255,255,.1);margin:1.5em 0}
ul,ol{padding-left:24px}
li{margin:.25em 0}
img{max-width:100%;border-radius:8px}
table{border-collapse:collapse;width:100%}
th,td{border:1px solid rgba(255,255,255,.15);padding:8px 12px;text-align:left}
th{background:rgba(255,255,255,.05)}
del{opacity:.6}
</style></head><body>""" + body + "</body></html>";
        }

        public string to_html(string markdown) {
            string[] lines = markdown.replace("\r\n", "\n").replace("\r", "\n").split("\n");
            var html_out = new StringBuilder();
            process_blocks(lines, 0, lines.length, html_out);
            return html_out.str;
        }

        // ── Block processing ──────────────────────────────────────────────────

        private void process_blocks(string[] lines, int start, int end_idx, StringBuilder sb) {
            int i = start;
            while (i < end_idx) {
                string line = lines[i];

                // Blank line
                if (line.strip() == "") {
                    i++;
                    continue;
                }

                // Setext heading (check next non-blank line)
                if (i + 1 < end_idx) {
                    string next = lines[i + 1];
                    if (is_setext_h1(next)) {
                        sb.append("<h1>").append(inline_parse(line.strip())).append("</h1>\n");
                        i += 2;
                        continue;
                    }
                    if (is_setext_h2(next)) {
                        sb.append("<h2>").append(inline_parse(line.strip())).append("</h2>\n");
                        i += 2;
                        continue;
                    }
                }

                // ATX heading
                if (line[0] == '#') {
                    int level = 0;
                    while (level < line.length && line[level] == '#') level++;
                    if (level <= 6 && (level == line.length || line[level] == ' ')) {
                        string text = level < line.length ? line.substring(level + 1).strip() : "";
                        // Strip trailing '#' markers
                        while (text.has_suffix("#")) text = text[0:text.length - 1].strip();
                        sb.append("<h%d>".printf(level))
                           .append(inline_parse(text))
                           .append("</h%d>\n".printf(level));
                        i++;
                        continue;
                    }
                }

                // Fenced code block
                if (line.has_prefix("```") || line.has_prefix("~~~")) {
                    string fence = line.has_prefix("```") ? "```" : "~~~";
                    string lang = line.substring(3).strip();
                    i++;
                    var code = new StringBuilder();
                    while (i < end_idx && !lines[i].has_prefix(fence)) {
                        code.append(Markup.escape_text(lines[i])).append_c('\n');
                        i++;
                    }
                    if (i < end_idx) i++; // skip closing fence
                    sb.append("<pre><code");
                    if (lang != "") sb.append(" class=\"language-%s\"".printf(Markup.escape_text(lang)));
                    sb.append(">").append(code.str).append("</code></pre>\n");
                    continue;
                }

                // Blockquote
                if (line.has_prefix("> ") || line == ">") {
                    string[] bq = {};
                    while (i < end_idx && (lines[i].has_prefix("> ") || lines[i] == ">")) {
                        bq += lines[i].has_prefix("> ") ? lines[i].substring(2) : "";
                        i++;
                    }
                    sb.append("<blockquote>\n");
                    process_blocks(bq, 0, bq.length, sb);
                    sb.append("</blockquote>\n");
                    continue;
                }

                // Horizontal rule
                if (is_hr(line.strip())) {
                    sb.append("<hr>\n");
                    i++;
                    continue;
                }

                // Unordered list
                if (is_ul_item(line)) {
                    sb.append("<ul>\n");
                    while (i < end_idx && (is_ul_item(lines[i]) || is_continuation(lines[i]))) {
                        if (is_ul_item(lines[i])) {
                            string item = lines[i].substring(2).strip();
                            sb.append("<li>").append(inline_parse(item)).append("</li>\n");
                        }
                        i++;
                    }
                    sb.append("</ul>\n");
                    continue;
                }

                // Ordered list
                if (is_ol_item(line)) {
                    sb.append("<ol>\n");
                    while (i < end_idx && (is_ol_item(lines[i]) || is_continuation(lines[i]))) {
                        if (is_ol_item(lines[i])) {
                            string item = ol_item_text(lines[i]);
                            sb.append("<li>").append(inline_parse(item)).append("</li>\n");
                        }
                        i++;
                    }
                    sb.append("</ol>\n");
                    continue;
                }

                // GFM Table: header row | separator row | data rows
                if (is_table_row(line) && i + 1 < end_idx && is_table_separator(lines[i + 1])) {
                    string[] headers = split_table_row(line);
                    // Parse optional alignment from separator
                    string[] seps = split_table_row(lines[i + 1]);
                    string[] aligns = new string[seps.length];
                    for (int k = 0; k < seps.length; k++) {
                        string sc = seps[k].strip();
                        bool left_colon  = sc.has_prefix(":");
                        bool right_colon = sc.has_suffix(":");
                        if (left_colon && right_colon) aligns[k] = "center";
                        else if (right_colon)           aligns[k] = "right";
                        else                            aligns[k] = "left";
                    }
                    i += 2;
                    sb.append("<table>\n<thead>\n<tr>\n");
                    for (int k = 0; k < headers.length; k++) {
                        string align = k < aligns.length ? aligns[k] : "left";
                        sb.append("<th style=\"text-align:").append(align).append("\">")
                          .append(inline_parse(headers[k].strip()))
                          .append("</th>\n");
                    }
                    sb.append("</tr>\n</thead>\n<tbody>\n");
                    while (i < end_idx && is_table_row(lines[i])) {
                        string[] cells = split_table_row(lines[i]);
                        sb.append("<tr>\n");
                        for (int k = 0; k < headers.length; k++) {
                            string align = k < aligns.length ? aligns[k] : "left";
                            string cell  = k < cells.length ? cells[k].strip() : "";
                            sb.append("<td style=\"text-align:").append(align).append("\">")
                              .append(inline_parse(cell))
                              .append("</td>\n");
                        }
                        sb.append("</tr>\n");
                        i++;
                    }
                    sb.append("</tbody>\n</table>\n");
                    continue;
                }

                // Indented code block (4 spaces)
                if (line.has_prefix("    ")) {
                    var code = new StringBuilder();
                    while (i < end_idx && (lines[i].has_prefix("    ") || lines[i].strip() == "")) {
                        if (lines[i].has_prefix("    "))
                            code.append(Markup.escape_text(lines[i].substring(4))).append_c('\n');
                        else
                            code.append_c('\n');
                        i++;
                    }
                    // Trim trailing blank lines
                    string cs = code.str;
                    while (cs.has_suffix("\n\n")) cs = cs[0:cs.length - 1];
                    sb.append("<pre><code>").append(cs).append("</code></pre>\n");
                    continue;
                }

                // Paragraph: collect lines until blank line or block-level start
                var para = new StringBuilder();
                while (i < end_idx && lines[i].strip() != "" && !is_block_start(lines[i])) {
                    string pline = lines[i];
                    if (para.len > 0) {
                        if (pline.has_suffix("  ") || pline.has_suffix("\t")) {
                            sb.append("<p>").append(inline_parse(para.str)).append("</p>\n");
                            sb.append("<br>\n");
                            para.truncate(0);
                        } else {
                            para.append_c(' ');
                        }
                    }
                    // Strip trailing whitespace used for hard break marker
                    para.append(pline.strip());
                    i++;
                }
                if (para.len > 0)
                    sb.append("<p>").append(inline_parse(para.str)).append("</p>\n");
            }
        }

        // ── Block classification helpers ──────────────────────────────────────

        private bool is_setext_h1(string line) {
            if (line.length < 1) return false;
            for (int i = 0; i < line.length; i++)
                if (line[i] != '=') return false;
            return true;
        }

        private bool is_setext_h2(string line) {
            if (line.length < 2) return false;
            for (int i = 0; i < line.length; i++)
                if (line[i] != '-') return false;
            return true;
        }

        private bool is_hr(string s) {
            if (s.length < 3) return false;
            char c = s[0];
            if (c != '-' && c != '*' && c != '_') return false;
            int cnt = 0;
            for (int i = 0; i < s.length; i++) {
                if (s[i] == c) cnt++;
                else if (s[i] != ' ') return false;
            }
            return cnt >= 3;
        }

        private bool is_ul_item(string line) {
            if (line.length < 2) return false;
            char c = line[0];
            return (c == '-' || c == '*' || c == '+') && line[1] == ' ';
        }

        private bool is_ol_item(string line) {
            int j = 0;
            while (j < line.length && line[j] >= '0' && line[j] <= '9') j++;
            if (j == 0 || j >= line.length) return false;
            return (line[j] == '.' || line[j] == ')') && j + 1 < line.length && line[j + 1] == ' ';
        }

        private string ol_item_text(string line) {
            int j = 0;
            while (j < line.length && line[j] >= '0' && line[j] <= '9') j++;
            if (j + 2 <= line.length) return line.substring(j + 2).strip();
            return "";
        }

        // A list continuation line (indented, not blank)

        private bool is_continuation(string line) {
            return line.has_prefix("  ") && line.strip() != "";
        }

        private bool is_block_start(string line) {
            if (line[0] == '#') return true;
            if (line.has_prefix("```") || line.has_prefix("~~~")) return true;
            if (line.has_prefix("> ") || line == ">") return true;
            if (is_ul_item(line)) return true;
            if (is_ol_item(line)) return true;
            if (is_hr(line.strip())) return true;
            if (line.has_prefix("    ")) return true;
            if (is_table_row(line)) return true;
            return false;
        }

        // ── GFM table helpers ─────────────────────────────────────────────────

        private bool is_table_row(string line) {
            return "|" in line;
        }

        private bool is_table_separator(string line) {
            string[] cells = split_table_row(line);
            if (cells.length == 0) return false;
            foreach (string cell in cells) {
                string c = cell.strip();
                if (c == "") continue;
                if (c.has_prefix(":")) c = c.substring(1);
                if (c.has_suffix(":")) c = c[0:c.length - 1];
                if (c.length == 0) return false;
                for (int k = 0; k < c.length; k++)
                    if (c[k] != '-') return false;
            }
            return true;
        }

        private string[] split_table_row(string line) {
            string t = line.strip();
            if (t.has_prefix("|")) t = t.substring(1);
            if (t.has_suffix("|")) t = t[0:t.length - 1];
            return t.split("|");
        }


        //
        // Processes markdown inline syntax left-to-right with a simple scanner.
        // HTML special chars (&, <, >) are escaped for literal text segments.

        public string inline_parse(string text) {
            var html_out = new StringBuilder();
            int i = 0;
            int n = text.length;

            while (i < n) {
                char c = text[i];

                // Code span: `...`
                if (c == '`') {
                    int j = i + 1;
                    while (j < n && text[j] != '`') j++;
                    if (j < n) {
                        html_out.append("<code>")
                           .append(Markup.escape_text(text.substring(i + 1, j - i - 1)))
                           .append("</code>");
                        i = j + 1;
                        continue;
                    }
                }

                // Strikethrough: ~~...~~
                if (c == '~' && i + 1 < n && text[i + 1] == '~') {
                    int j = text.index_of("~~", i + 2);
                    if (j >= i + 2) {
                        html_out.append("<del>")
                           .append(inline_parse(text.substring(i + 2, j - i - 2)))
                           .append("</del>");
                        i = j + 2;
                        continue;
                    }
                }

                // Image: ![alt](url)
                if (c == '!' && i + 1 < n && text[i + 1] == '[') {
                    int cb = text.index_of("]", i + 2);
                    if (cb > 0 && cb + 1 < n && text[cb + 1] == '(') {
                        int cp = text.index_of(")", cb + 2);
                        if (cp > 0) {
                            string alt = text.substring(i + 2, cb - i - 2);
                            string url = text.substring(cb + 2, cp - cb - 2);
                            html_out.append("<img src=\"").append(Markup.escape_text(url))
                               .append("\" alt=\"").append(Markup.escape_text(alt))
                               .append("\">");
                            i = cp + 1;
                            continue;
                        }
                    }
                }

                // Link: [text](url)
                if (c == '[') {
                    int cb = text.index_of("]", i + 1);
                    if (cb > 0 && cb + 1 < n && text[cb + 1] == '(') {
                        int cp = text.index_of(")", cb + 2);
                        if (cp > 0) {
                            string link_text = text.substring(i + 1, cb - i - 1);
                            string url = text.substring(cb + 2, cp - cb - 2);
                            html_out.append("<a href=\"").append(Markup.escape_text(url)).append("\">")
                               .append(inline_parse(link_text))
                               .append("</a>");
                            i = cp + 1;
                            continue;
                        }
                    }
                }

                // Bold + Italic: ***...*** or ___...___
                if (i + 2 < n && ((c == '*' && text[i+1] == '*' && text[i+2] == '*') ||
                                   (c == '_' && text[i+1] == '_' && text[i+2] == '_'))) {
                    string delim = text.substring(i, 3);
                    int j = text.index_of(delim, i + 3);
                    if (j >= i + 3) {
                        html_out.append("<strong><em>")
                           .append(inline_parse(text.substring(i + 3, j - i - 3)))
                           .append("</em></strong>");
                        i = j + 3;
                        continue;
                    }
                }

                // Bold: **...** or __...__
                if (i + 1 < n && ((c == '*' && text[i+1] == '*') ||
                                   (c == '_' && text[i+1] == '_'))) {
                    string delim = text.substring(i, 2);
                    int j = text.index_of(delim, i + 2);
                    if (j >= i + 2) {
                        html_out.append("<strong>")
                           .append(inline_parse(text.substring(i + 2, j - i - 2)))
                           .append("</strong>");
                        i = j + 2;
                        continue;
                    }
                }

                // Italic: *...* or _..._  (avoid matching inside words for _)
                if (c == '*' || (c == '_' && (i == 0 || text[i-1] == ' '))) {
                    int j = i + 1;
                    while (j < n && text[j] != c) j++;
                    if (j < n && j > i + 1) {
                        html_out.append("<em>")
                           .append(inline_parse(text.substring(i + 1, j - i - 1)))
                           .append("</em>");
                        i = j + 1;
                        continue;
                    }
                }

                // Autolinks: http:// and https://
                if ((n - i >= 7 && text.substring(i, 7) == "http://") ||
                    (n - i >= 8 && text.substring(i, 8) == "https://")) {
                    int j = i;
                    while (j < n && text[j] != ' ' && text[j] != '\n' &&
                           text[j] != '<' && text[j] != '>' && text[j] != '"') j++;
                    string url = text.substring(i, j - i);
                    html_out.append("<a href=\"").append(Markup.escape_text(url)).append("\">")
                       .append(Markup.escape_text(url)).append("</a>");
                    i = j;
                    continue;
                }

                // Literal character - HTML-escape &, <, >
                if      (c == '&') html_out.append("&amp;");
                else if (c == '<') html_out.append("&lt;");
                else if (c == '>') html_out.append("&gt;");
                else               html_out.append_c(c);
                i++;
            }

            return html_out.str;
        }
    }

    // ── Serializer: Gtk.TextBuffer rich-text, Markdown string ───────────────

    public class Serializer : Object {

        public string serialize(Gtk.TextBuffer buf) {
            var sb = new StringBuilder();
            Gtk.TextIter line_start;
            buf.get_start_iter(out line_start);

            while (!line_start.is_end()) {
                Gtk.TextIter line_end = line_start;
                if (!line_end.ends_line()) line_end.forward_to_line_end();

                bool is_last_empty = line_end.equal(line_start) && line_end.is_end();
                if (!is_last_empty) {
                    string para = get_para_prefix(buf, line_start);
                    sb.append(para);
                    serialize_inline(sb, buf, line_start, line_end, para.has_prefix("#"));
                    sb.append_c('\n');
                }

                line_start = line_end;
                if (!line_start.forward_char()) break;
            }

            return sb.str;
        }

        private string get_para_prefix(Gtk.TextBuffer buf, Gtk.TextIter it) {
            for (int h = 1; h <= 4; h++) {
                var t = buf.tag_table.lookup("h%d".printf(h));
                if (t != null && it.has_tag(t)) return string.nfill(h, '#') + " ";
            }
            var quote = buf.tag_table.lookup("quote");
            if (quote != null && it.has_tag(quote)) return "> ";
            return "";
        }

        private void serialize_inline(StringBuilder sb, Gtk.TextBuffer buf,
                                      Gtk.TextIter start, Gtk.TextIter end,
                                      bool is_heading) {
            Gtk.TextIter it = start;
            while (it.compare(end) < 0) {
                if (it.get_child_anchor() != null) { it.forward_char(); continue; }

                Gtk.TextIter next = it;
                next.forward_to_tag_toggle(null);
                if (next.compare(end) > 0) next = end;

                bool bold  = has_tag(buf, "bold", it) && !is_heading;
                bool ital  = has_tag(buf, "italic", it);
                bool code  = has_tag(buf, "code", it);
                bool strk  = has_tag(buf, "strikethrough", it);

                string text = buf.get_text(it, next, false);
                if (text == "") { it = next; continue; }

                if (code)  sb.append("`");
                if (strk)  sb.append("~~");
                if (bold && ital) sb.append("***");
                else if (bold)   sb.append("**");
                else if (ital)   sb.append("*");

                sb.append(text);

                if (bold && ital) sb.append("***");
                else if (bold)   sb.append("**");
                else if (ital)   sb.append("*");
                if (strk)  sb.append("~~");
                if (code)  sb.append("`");

                it = next;
            }
        }

        private bool has_tag(Gtk.TextBuffer buf, string name, Gtk.TextIter it) {
            var t = buf.tag_table.lookup(name);
            return t != null && it.has_tag(t);
        }
    }
}
