/* Eyedropper.vala - Desktop eyedropper portal client using XDG Desktop Portal DBus API */

namespace Nova {

    public delegate void ColorPickedCallback(Color color);
    public delegate void ErrorCallback(GLib.Error err);

    public class Eyedropper {

        public static void pick_screen_color(ColorPickedCallback on_picked, ErrorCallback? on_error = null) {
            try {
                var proxy = new GLib.DBusProxy.for_bus_sync(
                    GLib.BusType.SESSION,
                    GLib.DBusProxyFlags.NONE,
                    null,
                    "org.freedesktop.portal.Desktop",
                    "/org/freedesktop/portal/desktop",
                    "org.freedesktop.portal.Screenshot",
                    null
                );

                var builder = new GLib.VariantBuilder(new GLib.VariantType("a{sv}"));
                var params = new GLib.Variant.tuple(new GLib.Variant[] { new GLib.Variant.string(""), builder.end() });

                proxy.call.begin("PickColor", params, GLib.DBusCallFlags.NONE, -1, null, (source, call_res) => {
                    try {
                        var ret = proxy.call.end(call_res);
                        // Returns dict with 'color' (ddd)
                        GLib.Variant data = ret.get_child_value(0);
                        GLib.Variant? color_var = data.lookup_value("color", null);
                        if (color_var != null && color_var.n_children() >= 3) {
                            double r = color_var.get_child_value(0).get_double();
                            double g = color_var.get_child_value(1).get_double();
                            double b = color_var.get_child_value(2).get_double();
                            GLib.Idle.add(() => {
                                on_picked(Color.rgb(r, g, b));
                                return GLib.Source.REMOVE;
                            });
                        }
                    } catch (GLib.Error err) {
                        if (on_error != null) on_error(err);
                    }
                });
            } catch (GLib.Error err) {
                if (on_error != null) on_error(err);
            }
        }
    }
}
