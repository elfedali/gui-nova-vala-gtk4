/* Color.vala - Color structures, hex parsing, and palette extraction */

namespace Nova {

    public struct Color {
        public double red;
        public double green;
        public double blue;
        public double alpha;

        public Color(double r = 0.0, double g = 0.0, double b = 0.0, double a = 1.0) {
            this.red = Math.fmax(0.0, Math.fmin(1.0, r));
            this.green = Math.fmax(0.0, Math.fmin(1.0, g));
            this.blue = Math.fmax(0.0, Math.fmin(1.0, b));
            this.alpha = Math.fmax(0.0, Math.fmin(1.0, a));
        }

        public static Color rgb(double r, double g, double b) {
            return Color(r, g, b, 1.0);
        }

        public static Color rgba(double r, double g, double b, double a) {
            return Color(r, g, b, a);
        }

        public bool equals(Color other, double epsilon = 1e-3) {
            return Math.fabs(red - other.red) <= epsilon &&
                   Math.fabs(green - other.green) <= epsilon &&
                   Math.fabs(blue - other.blue) <= epsilon &&
                   Math.fabs(alpha - other.alpha) <= epsilon;
        }

        public string to_hex(bool include_alpha = false) {
            int r = (int) Math.round(red * 255.0);
            int g = (int) Math.round(green * 255.0);
            int b = (int) Math.round(blue * 255.0);
            int a = (int) Math.round(alpha * 255.0);

            if (include_alpha || a < 255) {
                return "#%02X%02X%02X%02X".printf(r, g, b, a);
            }
            return "#%02X%02X%02X".printf(r, g, b);
        }

        private static inline int hex_val(char c) {
            if (c >= '0' && c <= '9') return c - '0';
            if (c >= 'a' && c <= 'f') return c - 'a' + 10;
            if (c >= 'A' && c <= 'F') return c - 'A' + 10;
            return 0;
        }

        public static Color? from_hex(string hex_str) {
            string cleaned = hex_str.strip();
            if (cleaned.has_prefix("#")) {
                cleaned = cleaned.substring(1);
            }
            int len = (int) cleaned.length;
            if (len != 3 && len != 4 && len != 6 && len != 8) {
                return null;
            }

            // Verify all characters are hex digits
            for (int i = 0; i < len; i++) {
                char c = cleaned[i];
                if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))) {
                    return null;
                }
            }

            if (len == 3) { // #RGB
                int r = hex_val(cleaned[0]) * 17;
                int g = hex_val(cleaned[1]) * 17;
                int b = hex_val(cleaned[2]) * 17;
                return Color(r / 255.0, g / 255.0, b / 255.0, 1.0);
            } else if (len == 4) { // #RGBA
                int r = hex_val(cleaned[0]) * 17;
                int g = hex_val(cleaned[1]) * 17;
                int b = hex_val(cleaned[2]) * 17;
                int a = hex_val(cleaned[3]) * 17;
                return Color(r / 255.0, g / 255.0, b / 255.0, a / 255.0);
            } else if (len == 6) { // #RRGGBB
                int r = hex_val(cleaned[0]) * 16 + hex_val(cleaned[1]);
                int g = hex_val(cleaned[2]) * 16 + hex_val(cleaned[3]);
                int b = hex_val(cleaned[4]) * 16 + hex_val(cleaned[5]);
                return Color(r / 255.0, g / 255.0, b / 255.0, 1.0);
            } else if (len == 8) { // #RRGGBBAA
                int r = hex_val(cleaned[0]) * 16 + hex_val(cleaned[1]);
                int g = hex_val(cleaned[2]) * 16 + hex_val(cleaned[3]);
                int b = hex_val(cleaned[4]) * 16 + hex_val(cleaned[5]);
                int a = hex_val(cleaned[6]) * 16 + hex_val(cleaned[7]);
                return Color(r / 255.0, g / 255.0, b / 255.0, a / 255.0);
            }
            return null;
        }

        public static GLib.GenericArray<Color?> extract_document_colors(GLib.GenericArray<Shape> shapes) {
            var result = new GLib.GenericArray<Color?>();

            for (uint i = 0; i < shapes.length; i++) {
                unowned Shape s = shapes[i];
                if (s.shape_type != ShapeType.GROUP) {
                    Color fill = s.color;
                    bool exists = false;
                    for (uint j = 0; j < result.length; j++) {
                        if (result[j].equals(fill)) {
                            exists = true;
                            break;
                        }
                    }
                    if (!exists) {
                        result.add(fill);
                    }
                }
                if (s.has_stroke && s.stroke_width > 0) {
                    Color stroke = s.stroke_color;
                    bool exists = false;
                    for (uint j = 0; j < result.length; j++) {
                        if (result[j].equals(stroke)) {
                            exists = true;
                            break;
                        }
                    }
                    if (!exists) {
                        result.add(stroke);
                    }
                }
                if (s.shape_type == ShapeType.GROUP) {
                    var child_colors = extract_document_colors(s.children);
                    for (uint k = 0; k < child_colors.length; k++) {
                        Color cc = child_colors[k];
                        bool exists = false;
                        for (uint j = 0; j < result.length; j++) {
                            if (result[j].equals(cc)) {
                                exists = true;
                                break;
                            }
                        }
                        if (!exists) {
                            result.add(cc);
                        }
                    }
                }
            }

            return result;
        }
    }
}
