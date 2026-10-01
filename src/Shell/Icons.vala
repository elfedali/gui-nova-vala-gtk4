/* Icons.vala - Lucide iconography loader and button helpers for Nova */

namespace Nova {

    public class Icons {
        private static GLib.HashTable<string, string> alias_map;

        public static void init() {
            alias_map = new GLib.HashTable<string, string>(GLib.str_hash, GLib.str_equal);
            alias_map.insert("edit-undo", "undo-2");
            alias_map.insert("edit-redo", "redo-2");
            alias_map.insert("format-justify-left", "align-left");
            alias_map.insert("format-justify-center", "align-center");
            alias_map.insert("format-justify-right", "align-right");
            alias_map.insert("go-top", "chevrons-up");
            alias_map.insert("go-up", "chevron-up");
            alias_map.insert("go-down", "chevron-down");
            alias_map.insert("go-bottom", "chevrons-down");
            alias_map.insert("help-about", "help-circle");
            alias_map.insert("view-grid", "frame");
            alias_map.insert("view-paged", "align-center-horizontal");
            alias_map.insert("color-select", "pipette");
            alias_map.insert("sidebar-show-left", "panel-left");
            alias_map.insert("sidebar-show-right", "panel-right");
        }

        public static string get_icon_name(string name) {
            string base_name = name.has_suffix(".svg") ? name.substring(0, name.length - 4) : name;
            if (base_name.has_suffix("-symbolic")) {
                base_name = base_name.substring(0, base_name.length - 9);
            }
            if (alias_map != null && alias_map.contains(base_name)) {
                return alias_map.lookup(base_name);
            }
            return base_name;
        }

        public static string get_resource_path(string name) {
            string icon_name = get_icon_name(name);
            return "/com/iminwa/nova/icons/" + icon_name + ".svg";
        }

        private static bool resource_exists(string res_path) {
            try {
                return GLib.resources_get_info(res_path, 0, null, null);
            } catch (GLib.Error e) {
                return false;
            }
        }

        public static Gtk.Image create_lucide_image(string name, int pixel_size = 16) {
            string res_path = get_resource_path(name);
            Gtk.Image img;
            if (resource_exists(res_path)) {
                img = new Gtk.Image.from_resource(res_path);
            } else {
                img = new Gtk.Image.from_icon_name(name);
            }
            img.pixel_size = pixel_size;
            return img;
        }

        public static Gtk.Button create_lucide_button(string icon_name, string? tooltip = null, int pixel_size = 16, string css_class = "flat") {
            var btn = new Gtk.Button();
            btn.child = create_lucide_image(icon_name, pixel_size);
            if (css_class.length > 0) {
                string[] classes = css_class.split(" ");
                for (int i = 0; i < classes.length; i++) {
                    if (classes[i].length > 0) btn.add_css_class(classes[i]);
                }
            }
            if (tooltip != null) {
                btn.tooltip_text = tooltip;
            }
            return btn;
        }

        public static Gtk.ToggleButton create_lucide_toggle_button(string icon_name, string? tooltip = null, int pixel_size = 16, string css_class = "flat") {
            var btn = new Gtk.ToggleButton();
            btn.child = create_lucide_image(icon_name, pixel_size);
            if (css_class.length > 0) {
                string[] classes = css_class.split(" ");
                for (int i = 0; i < classes.length; i++) {
                    if (classes[i].length > 0) btn.add_css_class(classes[i]);
                }
            }
            if (tooltip != null) {
                btn.tooltip_text = tooltip;
            }
            return btn;
        }

        public static void update_button_icon(Gtk.Button btn, string icon_name, int pixel_size = 16) {
            btn.child = create_lucide_image(icon_name, pixel_size);
        }

        public static void update_image_icon(Gtk.Image img, string icon_name, int pixel_size = 16) {
            string res_path = get_resource_path(icon_name);
            if (resource_exists(res_path)) {
                img.set_from_resource(res_path);
            } else {
                img.set_from_icon_name(icon_name);
            }
            img.pixel_size = pixel_size;
        }
    }
}
