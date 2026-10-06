namespace Write.Test {

    public int failures = 0;
    public int passed = 0;

    public void check(bool ok, string what) {
        if (ok) {
            passed++;
        } else {
            failures++;
            stderr.printf("FAIL: %s\n", what);
        }
    }

    public void check_eq(string got, string want, string what) {
        if (got == want) {
            passed++;
        } else {
            failures++;
            stderr.printf("FAIL: %s\n  got:  %s\n  want: %s\n", what, got, want);
        }
    }

    public void check_int(int got, int want, string what) {
        check_eq(got.to_string(), want.to_string(), what);
    }

    public void check_near(double got, double want, double tol, string what) {
        if ((got - want).abs() <= tol) {
            passed++;
        } else {
            failures++;
            stderr.printf("FAIL: %s\n  got:  %g\n  want: %g\n", what, got, want);
        }
    }

    public int finish(string suite) {
        print("%s: %d passed, %d failed\n", suite, passed, failures);
        return failures == 0 ? 0 : 1;
    }

    public string fixture(string name) {
        string dir = Environment.get_variable("WRITE_FIXTURES") ?? "tests/fixtures";
        return Path.build_filename(dir, name);
    }

    public uint8[] read_fixture(string name) {
        uint8[] data = {};
        try {
            FileUtils.get_data(fixture(name), out data);
        } catch (Error e) {
            failures++;
            stderr.printf("FAIL: cannot read fixture %s: %s\n", name, e.message);
        }
        return data;
    }

    public string scratch(string name) {
        string dir = Environment.get_variable("TMPDIR") ?? ".";
        return Path.build_filename(dir, name);
    }

    public string body_text(Document d) {
        var sb = new StringBuilder();
        foreach (var p in d.paragraphs(false)) {
            sb.append(p.plain_text());
            sb.append_c('\n');
        }
        return sb.str;
    }

    public Paragraph? find_para(Document d, string needle) {
        foreach (var p in d.paragraphs(true)) if (p.plain_text().contains(needle)) return p;
        return null;
    }

    public Inline? find_run(Document d, string needle) {
        foreach (var p in d.paragraphs(true)) {
            foreach (var i in p.inlines) {
                var t = i as TextRun;
                if (t != null && t.text.contains(needle)) return t;
            }
        }
        return null;
    }

    public T? first_of<T>(Document d) {
        foreach (var p in d.paragraphs(true)) {
            foreach (var i in p.inlines) if (i is T) return (T) i;
        }
        return null;
    }
}
