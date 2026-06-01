using Gtk;
using Gdk;
using GLib;
using WebKit;
using Singularity;
using Singularity.Widgets;

namespace Singularity.Apps {

    public static int main(string[] args) {
        Intl.setlocale(GLib.LocaleCategory.ALL, "");
        string locale_dir = "/usr/share/locale";
        try {
            string exe = GLib.FileUtils.read_link("/proc/self/exe");
            locale_dir = GLib.Path.build_filename(GLib.Path.get_dirname(GLib.Path.get_dirname(exe)), "share", "locale");
        } catch (GLib.Error e) { }
        Intl.bindtextdomain("singularity-write", locale_dir);
        Intl.bind_textdomain_codeset("singularity-write", "UTF-8");
        Intl.textdomain("singularity-write");

        return new WriteApp().run(args);
    }
}
