using Gtk;
using Gdk;
using GLib;
using WebKit;
using Singularity;
using Singularity.Widgets;

namespace Singularity.Apps {

    [GtkTemplate(ui = "/dev/sinty/write/ui/main.ui")]
    public class WriteWindow : Singularity.Widgets.Window {
        [GtkChild] public new unowned Box root;
        [GtkChild] public unowned Box content_hbox;

        public WriteWindow(Gtk.Application app) {
            Object(application: app);
            set_title(_("Write"));
            set_default_size(1140, 860);
        }
    }
}
