/* Export.vala - Bitmap rasterization (PNG, JPEG, WebP) and live export preview */

namespace Nova {

    public class Export {
        private const double CHECKER_LIGHT = 1.0;
        private const double CHECKER_DARK = 0.90;

        public static Cairo.ImageSurface rasterize(GLib.GenericArray<Shape> shapes, int scale = 1) {
            int factor = (scale >= 1 && scale <= 3) ? scale : 1;
            Rect bounds = Svg.export_bounds(shapes);
            double origin_x = bounds.x;
            double origin_y = bounds.y;
            int pixel_w = int.max(1, (int) Math.round(bounds.width * factor));
            int pixel_h = int.max(1, (int) Math.round(bounds.height * factor));

            var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, pixel_w, pixel_h);
            var cr = new Cairo.Context(surface);
            cr.scale(factor, factor);
            cr.translate(-origin_x, -origin_y);

            Render.paint_shapes(cr, shapes, Color.rgb(0.2, 0.2, 0.2), false, factor, false, false);
            surface.flush();
            return surface;
        }

        public static void save_bitmap(GLib.GenericArray<Shape> shapes, string path, string fmt, int scale = 1) throws GLib.Error {
            string kind = fmt.down();
            if (kind == "jpg") kind = "jpeg";

            Cairo.ImageSurface surface = rasterize(shapes, scale);
            if (kind == "png") {
                surface.write_to_png(path);
                return;
            }

            Cairo.ImageSurface to_save = surface;
            if (kind == "jpeg") {
                to_save = flatten_on_white(surface);
            }

            // Save via Gdk.Pixbuf
            save_with_pixbuf(to_save, path, kind);
        }

        public static void paint_export_preview(Cairo.Context cr, GLib.GenericArray<Shape> shapes, int width, int height) {
            paint_checkerboard(cr, width, height);
            if (shapes.length == 0 || width <= 0 || height <= 0) return;

            Rect bounds = Svg.export_bounds(shapes);
            double pad = 12.0;
            double avail_w = Math.fmax(1.0, width - pad * 2.0);
            double avail_h = Math.fmax(1.0, height - pad * 2.0);
            double fit = Math.fmin(avail_w / bounds.width, avail_h / bounds.height);
            double offset_x = (width - bounds.width * fit) / 2.0;
            double offset_y = (height - bounds.height * fit) / 2.0;

            cr.save();
            cr.translate(offset_x, offset_y);
            cr.scale(fit, fit);
            cr.translate(-bounds.x, -bounds.y);

            Render.paint_shapes(cr, shapes, Color.rgb(0.2, 0.2, 0.2), false, fit, false, false);
            cr.restore();
        }

        private static Cairo.ImageSurface flatten_on_white(Cairo.ImageSurface surface) {
            var flat = new Cairo.ImageSurface(Cairo.Format.RGB24, surface.get_width(), surface.get_height());
            var cr = new Cairo.Context(flat);
            cr.set_source_rgb(1.0, 1.0, 1.0);
            cr.paint();
            cr.set_source_surface(surface, 0.0, 0.0);
            cr.paint();
            flat.flush();
            return flat;
        }

        private static void save_with_pixbuf(Cairo.ImageSurface surface, string path, string kind) throws GLib.Error {
            var pixbuf = pixbuf_from_surface(surface);
            string type_name = (kind == "jpeg") ? "jpeg" : "webp";
            if (kind == "jpeg") {
                pixbuf = without_alpha(pixbuf);
            }
            pixbuf.save(path, type_name, "quality", "90", null);
        }

        private static Gdk.Pixbuf without_alpha(Gdk.Pixbuf src) {
            if (!src.has_alpha) return src;
            int width = src.get_width();
            int height = src.get_height();
            var rgb = new Gdk.Pixbuf(Gdk.Colorspace.RGB, false, 8, width, height);
            int src_stride = src.get_rowstride();
            int dst_stride = rgb.get_rowstride();
            unowned uint8[] sp = src.get_pixels();
            unowned uint8[] dp = rgb.get_pixels();
            for (int y = 0; y < height; y++) {
                int src_row = y * src_stride;
                int dst_row = y * dst_stride;
                for (int x = 0; x < width; x++) {
                    int si = src_row + x * 4;
                    int di = dst_row + x * 3;
                    dp[di] = sp[si];
                    dp[di + 1] = sp[si + 1];
                    dp[di + 2] = sp[si + 2];
                }
            }
            return rgb;
        }

        // Cairo image surfaces are native-endian and, for ARGB32, premultiplied.
        // Gdk.Pixbuf is straight (non-premultiplied) RGBA. gdk_pixbuf_get_from_surface
        // did this conversion, but GTK deprecated it in 4.12.
        private static Gdk.Pixbuf pixbuf_from_surface(Cairo.ImageSurface surface) {
            surface.flush();
            int width = surface.get_width();
            int height = surface.get_height();
            int src_stride = surface.get_stride();
            unowned uint8[] src = surface.get_data();
            bool premultiplied = surface.get_format() == Cairo.Format.ARGB32;
            bool little = host_is_little_endian();

            var pixbuf = new Gdk.Pixbuf(Gdk.Colorspace.RGB, true, 8, width, height);
            int dst_stride = pixbuf.get_rowstride();
            unowned uint8[] dst = pixbuf.get_pixels();

            for (int y = 0; y < height; y++) {
                int src_row = y * src_stride;
                int dst_row = y * dst_stride;
                for (int x = 0; x < width; x++) {
                    int si = src_row + x * 4;
                    int di = dst_row + x * 4;
                    uint8 r, g, b, a;
                    if (little) {
                        b = src[si];
                        g = src[si + 1];
                        r = src[si + 2];
                        a = premultiplied ? src[si + 3] : (uint8) 255;
                    } else {
                        a = premultiplied ? src[si] : (uint8) 255;
                        r = src[si + 1];
                        g = src[si + 2];
                        b = src[si + 3];
                    }
                    if (premultiplied && a > 0 && a < 255) {
                        r = (uint8) ((r * 255 + a / 2) / a);
                        g = (uint8) ((g * 255 + a / 2) / a);
                        b = (uint8) ((b * 255 + a / 2) / a);
                    }
                    dst[di] = r;
                    dst[di + 1] = g;
                    dst[di + 2] = b;
                    dst[di + 3] = a;
                }
            }
            return pixbuf;
        }

        [CCode (cname = "G_BYTE_ORDER")]
        private extern const int HOST_BYTE_ORDER;
        [CCode (cname = "G_LITTLE_ENDIAN")]
        private extern const int HOST_LITTLE_ENDIAN;

        private static bool host_is_little_endian() {
            return HOST_BYTE_ORDER == HOST_LITTLE_ENDIAN;
        }

        private static void paint_checkerboard(Cairo.Context cr, int width, int height) {
            int cell = 8;
            cr.save();
            cr.set_source_rgb(CHECKER_LIGHT, CHECKER_LIGHT, CHECKER_LIGHT);
            cr.rectangle(0, 0, width, height);
            cr.fill();

            cr.set_source_rgb(CHECKER_DARK, CHECKER_DARK, CHECKER_DARK);
            for (int y = 0; y < height; y += cell) {
                for (int x = 0; x < width; x += cell) {
                    if (((x / cell) + (y / cell)) % 2 == 0) {
                        cr.rectangle(x, y, cell, cell);
                    }
                }
            }
            cr.fill();
            cr.restore();
        }
    }
}
