/* Render.vala - Cairo rendering engine for vector shapes, typography, guides, and selection overlays */

namespace Nova {

    public struct Guide {
        public string guide_type; // "v" or "h"
        public double val;
        public double start;
        public double end;

        public Guide(string gtype, double val, double start, double end) {
            this.guide_type = gtype;
            this.val = val;
            this.start = start;
            this.end = end;
        }
    }

    public class Render {
        public const double SELECTION_PAD = 0.0;
        public const double HANDLE_SIZE = 10.0;
        public const double EDGE_HIT = 8.0;
        public const double CORNER_HANDLE_RADIUS = 3.5;
        public const double RADIUS_HANDLE_RADIUS = 3.0;
        public const double RADIUS_HANDLE_MIN_INSET = 14.0;
        public const double RADIUS_HANDLE_HIT = 8.0;
        public const double ROTATION_HANDLE_DIST = 24.0;

        public static bool trace_shape(Cairo.Context cr, Shape shape) {
            double x = shape.x;
            double y = shape.y;
            double width = shape.w;
            double height = shape.h;

            if (shape.shape_type != ShapeType.LINE && shape.shape_type != ShapeType.ARROW && (width <= 0.0 || height <= 0.0)) {
                return false;
            }

            switch (shape.shape_type) {
                case ShapeType.FRAME:
                    cr.rectangle(x, y, width, height);
                    return true;

                case ShapeType.RECT:
                case ShapeType.IMAGE:
                    CornerRadii radii = Geometry.get_corner_radii(shape);
                    if (radii.is_zero()) {
                        cr.rectangle(x, y, width, height);
                        return true;
                    }
                    cr.new_sub_path();
                    cr.arc(x + width - radii.tr, y + radii.tr, radii.tr, -Math.PI / 2.0, 0.0);
                    cr.arc(x + width - radii.br, y + height - radii.br, radii.br, 0.0, Math.PI / 2.0);
                    cr.arc(x + radii.bl, y + height - radii.bl, radii.bl, Math.PI / 2.0, Math.PI);
                    cr.arc(x + radii.tl, y + radii.tl, radii.tl, Math.PI, 3.0 * Math.PI / 2.0);
                    cr.close_path();
                    return true;

                case ShapeType.ELLIPSE:
                    cr.save();
                    cr.translate(x + width / 2.0, y + height / 2.0);
                    cr.scale(width / 2.0, height / 2.0);
                    cr.arc(0.0, 0.0, 1.0, 0.0, 2.0 * Math.PI);
                    cr.restore();
                    return true;

                case ShapeType.POLYGON:
                    int sides = int.max(3, shape.sides);
                    double cx = x + width / 2.0;
                    double cy = y + height / 2.0;
                    double rx = width / 2.0;
                    double ry = height / 2.0;
                    cr.new_sub_path();
                    for (int i = 0; i < sides; i++) {
                        double angle = -Math.PI / 2.0 + (2.0 * Math.PI * i) / sides;
                        double px = cx + rx * Math.cos(angle);
                        double py = cy + ry * Math.sin(angle);
                        if (i == 0) cr.move_to(px, py);
                        else cr.line_to(px, py);
                    }
                    cr.close_path();
                    return true;

                case ShapeType.STAR:
                    int pts_count = int.max(3, shape.points_count);
                    double ratio = Math.fmax(0.1, Math.fmin(0.9, shape.inner_ratio));
                    double star_cx = x + width / 2.0;
                    double star_cy = y + height / 2.0;
                    double star_rx = width / 2.0;
                    double star_ry = height / 2.0;
                    int total_pts = pts_count * 2;
                    cr.new_sub_path();
                    for (int i = 0; i < total_pts; i++) {
                        double angle = -Math.PI / 2.0 + (Math.PI * i) / pts_count;
                        double r_scale = (i % 2 == 0) ? 1.0 : ratio;
                        double px = star_cx + star_rx * r_scale * Math.cos(angle);
                        double py = star_cy + star_ry * r_scale * Math.sin(angle);
                        if (i == 0) cr.move_to(px, py);
                        else cr.line_to(px, py);
                    }
                    cr.close_path();
                    return true;

                case ShapeType.LINE:
                case ShapeType.ARROW:
                    cr.new_sub_path();
                    cr.move_to(x, y);
                    cr.line_to(x + width, y + height);
                    return true;

                case ShapeType.PENCIL:
                    if (shape.points.length == 0) {
                        cr.rectangle(x, y, width, height);
                        return true;
                    }
                    cr.new_sub_path();
                    cr.move_to(x + shape.points[0].x, y + shape.points[0].y);
                    for (uint i = 1; i < shape.points.length; i++) {
                        cr.line_to(x + shape.points[i].x, y + shape.points[i].y);
                    }
                    return true;

                case ShapeType.TEXT:
                    cr.rectangle(x, y, width, height);
                    return true;

                case ShapeType.PATH:
                    if (shape.nodes.length == 0) return false;
                    cr.new_sub_path();
                    cr.move_to(shape.nodes[0].x, shape.nodes[0].y);
                    uint num_segs = shape.closed ? shape.nodes.length : shape.nodes.length - 1;
                    for (uint i = 0; i < num_segs; i++) {
                        unowned PathNode n0 = shape.nodes[i];
                        unowned PathNode n1 = shape.nodes[(i + 1) % shape.nodes.length];
                        Point p0 = Point(n0.x, n0.y);
                        Point p1 = n0.handle_out != null ? n0.handle_out : p0;
                        Point p3 = Point(n1.x, n1.y);
                        Point p2 = n1.handle_in != null ? n1.handle_in : p3;

                        if (p1.equals(p0) && p2.equals(p3)) {
                            cr.line_to(p3.x, p3.y);
                        } else {
                            cr.curve_to(p1.x, p1.y, p2.x, p2.y, p3.x, p3.y);
                        }
                    }
                    if (shape.closed && shape.nodes.length >= 3) {
                        cr.close_path();
                    }
                    return true;

                default:
                    return false;
            }
        }

        public static void paint_shapes(Cairo.Context cr, GLib.GenericArray<Shape> shapes, Color outline,
                                        bool preview = false, double zoom = 1.0, bool chrome = true) {
            for (uint i = 0; i < shapes.length; i++) {
                paint_shape_in_frame(cr, shapes[i], shapes, outline, preview, zoom, chrome);
            }
        }

        private static void paint_shape_in_frame(Cairo.Context cr, Shape shape, GLib.GenericArray<Shape> shapes,
                                                 Color outline, bool preview, double zoom, bool chrome) {
            Shape? frame = clip_frame_for(shape, shapes);
            if (frame == null) {
                paint_shape(cr, shape, outline, preview, zoom, chrome);
                return;
            }
            cr.save();
            clip_to_frame(cr, frame);
            paint_shape(cr, shape, outline, preview, zoom, chrome);
            cr.restore();
        }

        private static Shape? clip_frame_for(Shape shape, GLib.GenericArray<Shape> shapes) {
            if (shape.frame_id == null || shape.shape_type == ShapeType.FRAME) return null;
            for (uint i = 0; i < shapes.length; i++) {
                unowned Shape candidate = shapes[i];
                if (candidate.id == shape.frame_id && candidate.shape_type == ShapeType.FRAME &&
                    candidate.w > 0.0 && candidate.h > 0.0) {
                    return candidate;
                }
            }
            return null;
        }

        private static void clip_to_frame(Cairo.Context cr, Shape frame) {
            double rotation = frame.rotation % 360.0;
            if (rotation != 0.0) {
                double cx = frame.x + frame.w / 2.0;
                double cy = frame.y + frame.h / 2.0;
                cr.translate(cx, cy);
                cr.rotate(rotation * Math.PI / 180.0);
                cr.translate(-cx, -cy);
            }
            cr.new_path();
            cr.rectangle(frame.x, frame.y, frame.w, frame.h);
            cr.clip();
        }

        public static void paint_shape(Cairo.Context cr, Shape shape, Color outline,
                                       bool preview = false, double zoom = 1.0, bool chrome = true) {
            if (!Geometry.is_drawable(shape)) return;

            double opacity = shape.opacity;
            if (preview) opacity *= 0.45;

            double rotation = shape.rotation % 360.0;
            cr.save();

            if (rotation != 0.0) {
                double cx = shape.x + shape.w / 2.0;
                double cy = shape.y + shape.h / 2.0;
                cr.translate(cx, cy);
                cr.rotate(rotation * Math.PI / 180.0);
                cr.translate(-cx, -cy);
            }

            bool layer = opacity < 0.999;
            if (shape.shape_type == ShapeType.GROUP) {
                if (layer) cr.push_group();
                for (uint i = 0; i < shape.children.length; i++) {
                    paint_shape(cr, shape.children[i], outline, preview, zoom, chrome);
                }
                if (layer) {
                    cr.pop_group_to_source();
                    cr.paint_with_alpha(Math.fmax(0.0, Math.fmin(1.0, opacity)));
                }
                cr.restore();
                return;
            }

            if (layer) cr.push_group();

            if (shape.shape_type == ShapeType.TEXT) {
                paint_text(cr, shape);
            } else if (shape.shape_type == ShapeType.LINE || shape.shape_type == ShapeType.ARROW) {
                paint_line_or_arrow(cr, shape, outline);
            } else if (shape.shape_type == ShapeType.IMAGE) {
                paint_image(cr, shape, outline);
            } else {
                paint_standard_shape(cr, shape, outline);
            }

            if (layer) {
                cr.pop_group_to_source();
                cr.paint_with_alpha(Math.fmax(0.0, Math.fmin(1.0, opacity)));
            }

            if (chrome && shape.shape_type == ShapeType.FRAME && !preview) {
                paint_frame_header(cr, shape, zoom);
            }

            cr.restore();
        }

        private static void paint_standard_shape(Cairo.Context cr, Shape shape, Color outline) {
            cr.new_path();
            if (!trace_shape(cr, shape)) return;

            cr.set_source_rgb(shape.color.red, shape.color.green, shape.color.blue);

            bool has_custom_stroke = shape.has_stroke && shape.stroke_width > 0;

            if (!has_custom_stroke) {
                if (shape.shape_type == ShapeType.FRAME) {
                    cr.fill_preserve();
                    cr.set_source_rgba(0.75, 0.75, 0.8, 0.8);
                    cr.set_line_width(1.0);
                    cr.set_line_cap(Cairo.LineCap.BUTT);
                    cr.set_line_join(Cairo.LineJoin.MITER);
                    cr.set_dash(new double[0], 0.0);
                    cr.stroke();
                } else {
                    cr.fill();
                }
            } else {
                cr.fill();
                Color sc = shape.stroke_color;
                double sw = shape.stroke_width;

                if (shape.stroke_align == StrokeAlign.INSIDE) {
                    cr.save();
                    cr.new_path();
                    trace_shape(cr, shape);
                    cr.clip();

                    cr.new_path();
                    trace_shape(cr, shape);
                    cr.set_source_rgb(sc.red, sc.green, sc.blue);
                    cr.set_line_width(sw * 2.0);
                    apply_stroke_caps_joins(cr, shape.stroke_cap, shape.stroke_join);
                    apply_dash(cr, shape.stroke_dash, sw);
                    cr.stroke();
                    cr.restore();
                } else if (shape.stroke_align == StrokeAlign.OUTSIDE) {
                    cr.save();
                    cr.new_path();
                    trace_shape(cr, shape);
                    cr.set_source_rgb(sc.red, sc.green, sc.blue);
                    cr.set_line_width(sw * 2.0);
                    apply_stroke_caps_joins(cr, shape.stroke_cap, shape.stroke_join);
                    apply_dash(cr, shape.stroke_dash, sw);
                    cr.stroke();

                    cr.new_path();
                    trace_shape(cr, shape);
                    cr.set_source_rgb(shape.color.red, shape.color.green, shape.color.blue);
                    cr.fill();
                    cr.restore();
                } else { // CENTER
                    cr.new_path();
                    trace_shape(cr, shape);
                    cr.set_source_rgb(sc.red, sc.green, sc.blue);
                    cr.set_line_width(sw);
                    apply_stroke_caps_joins(cr, shape.stroke_cap, shape.stroke_join);
                    apply_dash(cr, shape.stroke_dash, sw);
                    cr.stroke();
                }
            }
        }

        private static void apply_stroke_caps_joins(Cairo.Context cr, StrokeCap cap, StrokeJoin join) {
            if (cap == StrokeCap.ROUND) cr.set_line_cap(Cairo.LineCap.ROUND);
            else if (cap == StrokeCap.SQUARE) cr.set_line_cap(Cairo.LineCap.SQUARE);
            else cr.set_line_cap(Cairo.LineCap.BUTT);

            if (join == StrokeJoin.ROUND) cr.set_line_join(Cairo.LineJoin.ROUND);
            else if (join == StrokeJoin.BEVEL) cr.set_line_join(Cairo.LineJoin.BEVEL);
            else cr.set_line_join(Cairo.LineJoin.MITER);
        }

        public static void apply_dash(Cairo.Context cr, StrokeDash dash, double stroke_width) {
            double w = Math.fmax(1.0, stroke_width);
            if (dash == StrokeDash.DASHED) {
                double[] dashes = { w * 3.0, w * 2.0 };
                cr.set_dash(dashes, 0.0);
            } else if (dash == StrokeDash.DOTTED) {
                double[] dashes = { w * 1.0, w * 1.5 };
                cr.set_dash(dashes, 0.0);
            } else {
                cr.set_dash(new double[0], 0.0);
            }
        }

        private static void paint_image(Cairo.Context cr, Shape shape, Color outline) {
            double x = shape.x;
            double y = shape.y;
            double w = shape.w;
            double h = shape.h;
            bool painted = false;

            if (shape.image_path != null && GLib.FileUtils.test(shape.image_path, GLib.FileTest.EXISTS)) {
                var surface = new Cairo.ImageSurface.from_png(shape.image_path);
                if (surface.status() == Cairo.Status.SUCCESS) {
                    int sw = surface.get_width();
                    int sh = surface.get_height();
                    if (sw > 0 && sh > 0) {
                        cr.save();
                        cr.translate(x, y);
                        cr.scale(w / sw, h / sh);
                        cr.set_source_surface(surface, 0, 0);
                        cr.paint();
                        cr.restore();
                        painted = true;
                    }
                }
            }

            if (!painted) {
                cr.new_path();
                cr.rectangle(x, y, w, h);
                cr.set_source_rgb(0.9, 0.9, 0.92);
                cr.fill_preserve();
                cr.set_source_rgb(outline.red, outline.green, outline.blue);
                cr.set_line_width(1.5);
                cr.set_dash(new double[0], 0.0);
                cr.stroke();

                cr.save();
                cr.select_font_face("Sans", Cairo.FontSlant.NORMAL, Cairo.FontWeight.NORMAL);
                cr.set_font_size(12.0);
                cr.set_source_rgb(0.4, 0.4, 0.45);
                cr.move_to(x + 10.0, y + h / 2.0);
                cr.show_text("Image");
                cr.restore();
            }
        }

        private static void paint_text(Cairo.Context cr, Shape shape) {
            double x = shape.x;
            double y = shape.y;
            double width = shape.w;
            double height = shape.h;
            string text = shape.text;
            double font_size = Math.fmax(6.0, shape.font_size);

            var slant = (shape.font_slant.down() == "italic") ? Cairo.FontSlant.ITALIC : Cairo.FontSlant.NORMAL;
            string fw = shape.font_weight.down();
            var weight = (fw == "bold" || fw == "semibold" || fw == "700" || fw == "600") ? Cairo.FontWeight.BOLD : Cairo.FontWeight.NORMAL;

            cr.select_font_face(shape.font_family, slant, weight);
            cr.set_font_size(font_size);
            cr.set_source_rgb(shape.color.red, shape.color.green, shape.color.blue);

            string[] raw_lines = text.split("\n");
            var lines = new GLib.GenericArray<string>();

            for (int r = 0; r < raw_lines.length; r++) {
                string[] words = raw_lines[r].split(" ");
                if (words.length == 0 || (words.length == 1 && words[0].length == 0)) {
                    lines.add("");
                    continue;
                }
                string cur_line = words[0];
                for (int w = 1; w < words.length; w++) {
                    Cairo.TextExtents ext;
                    cr.text_extents(cur_line + " " + words[w], out ext);
                    if (ext.width > width - 8.0 && cur_line.length > 0) {
                        lines.add(cur_line);
                        cur_line = words[w];
                    } else {
                        cur_line += " " + words[w];
                    }
                }
                lines.add(cur_line);
            }

            double line_spacing = font_size * Math.fmax(0.8, shape.line_height);
            for (uint i = 0; i < lines.length; i++) {
                double line_y = y + font_size + i * line_spacing;
                if (line_y > y + height + font_size * 2.0) break;
                Cairo.TextExtents ext;
                cr.text_extents(lines[i], out ext);
                double line_x = x + 4.0;
                if (shape.text_align.down() == "center") {
                    line_x = x + (width - ext.width) / 2.0;
                } else if (shape.text_align.down() == "right") {
                    line_x = x + width - ext.width - 4.0;
                }
                cr.move_to(line_x, line_y);
                cr.show_text(lines[i]);
            }
        }

        private static void paint_line_or_arrow(Cairo.Context cr, Shape shape, Color outline) {
            double x1 = shape.x;
            double y1 = shape.y;
            double x2 = shape.x + shape.w;
            double y2 = shape.y + shape.h;
            double stroke_width = Math.fmax(1.0, shape.stroke_width > 0 ? shape.stroke_width : 2.0);
            Color stroke_color = shape.has_stroke ? shape.stroke_color : shape.color;

            cr.new_path();
            cr.move_to(x1, y1);
            cr.line_to(x2, y2);
            cr.set_source_rgb(stroke_color.red, stroke_color.green, stroke_color.blue);
            cr.set_line_width(stroke_width);
            apply_stroke_caps_joins(cr, shape.stroke_cap, shape.stroke_join);
            apply_dash(cr, shape.stroke_dash, stroke_width);
            cr.stroke();

            if (shape.shape_type == ShapeType.ARROW || shape.arrow_end == "filled") {
                double angle = Math.atan2(y2 - y1, x2 - x1);
                double head_len = Math.fmax(12.0, stroke_width * 3.5);
                cr.new_path();
                cr.move_to(x2, y2);
                cr.line_to(x2 - head_len * Math.cos(angle - Math.PI / 6.0), y2 - head_len * Math.sin(angle - Math.PI / 6.0));
                cr.line_to(x2 - head_len * Math.cos(angle + Math.PI / 6.0), y2 - head_len * Math.sin(angle + Math.PI / 6.0));
                cr.close_path();
                cr.set_source_rgb(stroke_color.red, stroke_color.green, stroke_color.blue);
                cr.fill();
            }
        }

        private static void paint_frame_header(Cairo.Context cr, Shape shape, double zoom = 1.0) {
            double x = shape.x;
            double y = shape.y;
            double w = shape.w;
            double h = shape.h;
            string name = shape.name.length > 0 ? shape.name : "Frame";
            string label = (shape.frame_preset == null || shape.frame_preset == "Custom") ?
                           "%s (%d×%d)".printf(name, (int) w, (int) h) : "%s · %s".printf(name, shape.frame_preset);
            double z = Math.fmax(1e-6, zoom);
            cr.save();
            cr.select_font_face("Sans", Cairo.FontSlant.NORMAL, Cairo.FontWeight.BOLD);
            cr.set_font_size(11.0 / z);
            cr.set_source_rgba(0.45, 0.45, 0.5, 0.9);
            cr.move_to(x, y - 6.0 / z);
            cr.show_text(label);
            cr.restore();
        }

        public static Rect selection_bounds(Shape shape, double pad = SELECTION_PAD, double zoom = 1.0) {
            double effective_pad = pad / Math.fmax(1e-6, zoom);
            return Rect(shape.x - effective_pad, shape.y - effective_pad,
                        shape.w + effective_pad * 2.0, shape.h + effective_pad * 2.0);
        }

        public static Rect multi_selection_bounds(GLib.GenericArray<Shape> shapes, double pad = SELECTION_PAD, double zoom = 1.0) {
            if (shapes.length == 0) return Rect(0, 0, 0, 0);
            Rect b = Geometry.bounding_box(shapes);
            double effective_pad = pad / Math.fmax(1e-6, zoom);
            return Rect(b.x - effective_pad, b.y - effective_pad,
                        b.width + effective_pad * 2.0, b.height + effective_pad * 2.0);
        }

        public static GLib.HashTable<string, Point?> handle_centers(Rect bbox, double zoom = 1.0) {
            var map = new GLib.HashTable<string, Point?>(GLib.str_hash, GLib.str_equal);
            double x = bbox.x;
            double y = bbox.y;
            double width = bbox.width;
            double height = bbox.height;
            double mid_x = x + width / 2.0;
            double mid_y = y + height / 2.0;

            map.insert("nw", Point(x, y));
            map.insert("n", Point(mid_x, y));
            map.insert("ne", Point(x + width, y));
            map.insert("e", Point(x + width, mid_y));
            map.insert("se", Point(x + width, y + height));
            map.insert("s", Point(mid_x, y + height));
            map.insert("sw", Point(x, y + height));
            map.insert("w", Point(x, mid_y));
            map.insert("rot", Point(mid_x, y - ROTATION_HANDLE_DIST / Math.fmax(1e-6, zoom)));

            return map;
        }

        public static GLib.HashTable<string, Point?> radius_handle_centers(Rect bbox, CornerRadii radii, double zoom = 1.0) {
            var map = new GLib.HashTable<string, Point?>(GLib.str_hash, GLib.str_equal);
            double x = bbox.x;
            double y = bbox.y;
            double width = bbox.width;
            double height = bbox.height;
            if (width <= 0.0 || height <= 0.0) return map;

            double z = Math.fmax(1e-6, zoom);
            double inset = RADIUS_HANDLE_MIN_INSET / z;
            if (width < inset * 2.5 || height < inset * 2.5) return map;

            map.insert("rtl", Point(x + Math.fmin(Math.fmax(radii.tl, inset), width * 0.45),
                                   y + Math.fmin(Math.fmax(radii.tl, inset), height * 0.45)));
            map.insert("rtr", Point(x + width - Math.fmin(Math.fmax(radii.tr, inset), width * 0.45),
                                   y + Math.fmin(Math.fmax(radii.tr, inset), height * 0.45)));
            map.insert("rbr", Point(x + width - Math.fmin(Math.fmax(radii.br, inset), width * 0.45),
                                   y + height - Math.fmin(Math.fmax(radii.br, inset), height * 0.45)));
            map.insert("rbl", Point(x + Math.fmin(Math.fmax(radii.bl, inset), width * 0.45),
                                   y + height - Math.fmin(Math.fmax(radii.bl, inset), height * 0.45)));

            return map;
        }

        public static string? hit_handle(Rect bbox, double px, double py, double size = HANDLE_SIZE,
                                         double zoom = 1.0, CornerRadii? radii = null) {
            double z = Math.fmax(1e-6, zoom);
            double half = (size / 2.0) / z;
            double edge_half = EDGE_HIT / z;

            var centers = handle_centers(bbox, zoom);
            string[] corners = { "nw", "ne", "se", "sw" };
            for (int i = 0; i < corners.length; i++) {
                Point? p = centers.lookup(corners[i]);
                if (p != null && Math.fabs(px - p.x) <= half && Math.fabs(py - p.y) <= half) {
                    return corners[i];
                }
            }

            if (radii != null) {
                double rad_half = (RADIUS_HANDLE_HIT / 2.0) / z;
                var rcenters = radius_handle_centers(bbox, radii, zoom);
                string[] rhandles = { "rtl", "rtr", "rbr", "rbl" };
                for (int i = 0; i < rhandles.length; i++) {
                    Point? rp = rcenters.lookup(rhandles[i]);
                    if (rp != null && Math.fabs(px - rp.x) <= rad_half && Math.fabs(py - rp.y) <= rad_half) {
                        return rhandles[i];
                    }
                }
            }

            // Check edges
            double x0 = bbox.x;
            double y0 = bbox.y;
            double w0 = bbox.width;
            double h0 = bbox.height;

            if (px >= x0 && px <= x0 + w0 && Math.fabs(py - y0) <= edge_half) return "n";
            if (px >= x0 && px <= x0 + w0 && Math.fabs(py - (y0 + h0)) <= edge_half) return "s";
            if (py >= y0 && py <= y0 + h0 && Math.fabs(px - x0) <= edge_half) return "w";
            if (py >= y0 && py <= y0 + h0 && Math.fabs(px - (x0 + w0)) <= edge_half) return "e";

            Point? rot_p = centers.lookup("rot");
            if (rot_p != null && Math.fabs(px - rot_p.x) <= half && Math.fabs(py - rot_p.y) <= half) {
                return "rot";
            }

            return null;
        }

        public static void paint_selection_bounds(Cairo.Context cr, Rect bbox, Color color,
                                                 double zoom = 1.0, CornerRadii? radii = null) {
            double z = Math.fmax(1e-6, zoom);
            cr.new_path();
            cr.rectangle(bbox.x, bbox.y, bbox.width, bbox.height);
            cr.set_source_rgb(color.red, color.green, color.blue);
            cr.set_line_width(1.0 / z);
            cr.set_dash(new double[0], 0.0);
            cr.stroke();

            if (radii != null) {
                double inner = RADIUS_HANDLE_RADIUS / z;
                var rcenters = radius_handle_centers(bbox, radii, z);
                string[] rnames = { "rtl", "rtr", "rbr", "rbl" };
                for (int i = 0; i < rnames.length; i++) {
                    Point? rp = rcenters.lookup(rnames[i]);
                    if (rp != null) {
                        cr.new_path();
                        cr.arc(rp.x, rp.y, inner, 0.0, 2.0 * Math.PI);
                        cr.set_source_rgb(1.0, 1.0, 1.0);
                        cr.fill_preserve();
                        cr.set_source_rgb(color.red, color.green, color.blue);
                        cr.set_line_width(1.0 / z);
                        cr.stroke();
                    }
                }
            }

            double corner_size = (CORNER_HANDLE_RADIUS * 2.0) / z;
            var centers = handle_centers(bbox, z);
            string[] corners = { "nw", "ne", "se", "sw" };
            for (int i = 0; i < corners.length; i++) {
                Point? p = centers.lookup(corners[i]);
                if (p != null) {
                    cr.new_path();
                    cr.rectangle(p.x - corner_size / 2.0, p.y - corner_size / 2.0, corner_size, corner_size);
                    cr.set_source_rgb(1.0, 1.0, 1.0);
                    cr.fill_preserve();
                    cr.set_source_rgb(color.red, color.green, color.blue);
                    cr.set_line_width(1.0 / z);
                    cr.stroke();
                }
            }
        }

        public static void paint_marquee(Cairo.Context cr, double rx, double ry, double rw, double rh,
                                         Color accent, double zoom = 1.0) {
            double z = Math.fmax(1e-6, zoom);
            cr.new_path();
            cr.rectangle(rx, ry, rw, rh);
            cr.set_source_rgba(accent.red, accent.green, accent.blue, 0.12);
            cr.fill_preserve();
            cr.set_source_rgba(accent.red, accent.green, accent.blue, 0.85);
            cr.set_line_width(1.5 / z);
            double[] dashes = { 4.0 / z, 3.0 / z };
            cr.set_dash(dashes, 0.0);
            cr.stroke();
        }

        public static void paint_smart_guides(Cairo.Context cr, GLib.GenericArray<Guide?> guides, double zoom = 1.0) {
            double z = Math.fmax(1e-6, zoom);
            cr.save();
            cr.set_source_rgba(0.95, 0.15, 0.65, 0.9);
            cr.set_line_width(1.0 / z);
            double[] dashes = { 4.0 / z, 2.0 / z };
            cr.set_dash(dashes, 0.0);
            for (uint i = 0; i < guides.length; i++) {
                Guide g = guides[i];
                cr.new_path();
                if (g.guide_type == "v") {
                    cr.move_to(g.val, g.start);
                    cr.line_to(g.val, g.end);
                } else {
                    cr.move_to(g.start, g.val);
                    cr.line_to(g.end, g.val);
                }
                cr.stroke();
            }
            cr.restore();
        }

        public static void paint_pixel_grid(Cairo.Context cr, double pan_x, double pan_y, double zoom, int width, int height, bool dark_canvas) {
            // One document pixel is large enough to see from 400% upward.
            if (zoom < 4.0 || width <= 0 || height <= 0) return;
            double fade = Math.fmin(1.0, (zoom - 4.0) / 4.0);
            double alpha = 0.16 + 0.22 * fade;
            cr.save();
            if (dark_canvas) cr.set_source_rgba(1.0, 1.0, 1.0, alpha);
            else cr.set_source_rgba(0.0, 0.0, 0.0, alpha);
            cr.set_line_width(1.0);
            cr.set_dash(new double[0], 0.0);

            double x = Math.ceil(-pan_x / zoom) * zoom + pan_x;
            while (x < width) {
                double hair = Math.floor(x) + 0.5;
                cr.move_to(hair, 0.0);
                cr.line_to(hair, height);
                x += zoom;
            }

            double y = Math.ceil(-pan_y / zoom) * zoom + pan_y;
            while (y < height) {
                double hair = Math.floor(y) + 0.5;
                cr.move_to(0.0, hair);
                cr.line_to(width, hair);
                y += zoom;
            }

            cr.stroke();
            cr.restore();
        }

        public static void paint_measurement_overlay(Cairo.Context cr, Rect bbox1, Rect bbox2, double zoom = 1.0) {
            double z = Math.fmax(1e-6, zoom);
            double r1_right = bbox1.x + bbox1.width;
            double r1_bottom = bbox1.y + bbox1.height;
            double r2_right = bbox2.x + bbox2.width;
            double r2_bottom = bbox2.y + bbox2.height;

            double cx1 = bbox1.x + bbox1.width / 2.0;
            double cy1 = bbox1.y + bbox1.height / 2.0;
            double cx2 = bbox2.x + bbox2.width / 2.0;
            double cy2 = bbox2.y + bbox2.height / 2.0;

            cr.save();
            cr.set_source_rgba(0.95, 0.1, 0.45, 0.95);
            cr.set_line_width(1.2 / z);

            // Horizontal
            if (bbox2.x >= r1_right) {
                double gap = bbox2.x - r1_right;
                cr.new_path();
                cr.move_to(r1_right, cy1);
                cr.line_to(bbox2.x, cy1);
                cr.stroke();
                draw_badge(cr, (r1_right + bbox2.x) / 2.0, cy1, "%dpx".printf((int) Math.round(gap)), z);
            } else if (bbox1.x >= r2_right) {
                double gap = bbox1.x - r2_right;
                cr.new_path();
                cr.move_to(r2_right, cy2);
                cr.line_to(bbox1.x, cy2);
                cr.stroke();
                draw_badge(cr, (r2_right + bbox1.x) / 2.0, cy2, "%dpx".printf((int) Math.round(gap)), z);
            }

            // Vertical
            if (bbox2.y >= r1_bottom) {
                double gap = bbox2.y - r1_bottom;
                cr.new_path();
                cr.move_to(cx1, r1_bottom);
                cr.line_to(cx1, bbox2.y);
                cr.stroke();
                draw_badge(cr, cx1, (r1_bottom + bbox2.y) / 2.0, "%dpx".printf((int) Math.round(gap)), z);
            } else if (bbox1.y >= r2_bottom) {
                double gap = bbox1.y - r2_bottom;
                cr.new_path();
                cr.move_to(cx2, r2_bottom);
                cr.line_to(cx2, bbox1.y);
                cr.stroke();
                draw_badge(cr, cx2, (r2_bottom + bbox1.y) / 2.0, "%dpx".printf((int) Math.round(gap)), z);
            }

            cr.restore();
        }

        private static void draw_badge(Cairo.Context cr, double x, double y, string text, double zoom = 1.0) {
            double z = Math.fmax(1e-6, zoom);
            cr.save();
            cr.select_font_face("Sans", Cairo.FontSlant.NORMAL, Cairo.FontWeight.BOLD);
            cr.set_font_size(10.0 / z);
            Cairo.TextExtents ext;
            cr.text_extents(text, out ext);
            double pad = 3.0 / z;
            double bw = ext.width + pad * 2.0;
            double bh = ext.height + pad * 2.0;
            double bx = x - bw / 2.0;
            double by = y - bh / 2.0;

            cr.new_path();
            cr.rectangle(bx, by, bw, bh);
            cr.set_source_rgba(0.95, 0.1, 0.45, 0.95);
            cr.fill();

            cr.set_source_rgba(1.0, 1.0, 1.0, 1.0);
            cr.move_to(bx + pad, by + bh - pad - 1.0 / z);
            cr.show_text(text);
            cr.restore();
        }

        public static void paint_node_edit_overlay(Cairo.Context cr, Shape path, int selected_node_idx = -1,
                                                   Color accent = Color.rgb(0.2, 0.5, 0.9), double zoom = 1.0) {
            if (path.nodes.length == 0) return;
            double z = Math.fmax(1e-6, zoom);
            double handle_radius = 4.0 / z;
            double anchor_size = 8.0 / z;

            cr.save();
            cr.new_path();
            trace_shape(cr, path);
            cr.set_source_rgba(accent.red, accent.green, accent.blue, 0.75);
            cr.set_line_width(1.5 / z);
            cr.set_dash(new double[0], 0.0);
            cr.stroke();
            cr.restore();

            for (uint i = 0; i < path.nodes.length; i++) {
                unowned PathNode node = path.nodes[i];
                double x = node.x;
                double y = node.y;
                bool is_selected = ((int) i == selected_node_idx);

                if (is_selected) {
                    cr.save();
                    cr.set_line_width(1.2 / z);

                    if (node.handle_in != null) {
                        Point hin = node.handle_in;
                        cr.new_path();
                        cr.move_to(x, y);
                        cr.line_to(hin.x, hin.y);
                        cr.set_source_rgba(accent.red, accent.green, accent.blue, 0.85);
                        cr.stroke();

                        cr.new_path();
                        cr.arc(hin.x, hin.y, handle_radius, 0.0, 2.0 * Math.PI);
                        cr.set_source_rgb(1.0, 1.0, 1.0);
                        cr.fill_preserve();
                        cr.set_source_rgb(accent.red, accent.green, accent.blue);
                        cr.set_line_width(1.5 / z);
                        cr.stroke();
                    }

                    if (node.handle_out != null) {
                        Point hout = node.handle_out;
                        cr.new_path();
                        cr.move_to(x, y);
                        cr.line_to(hout.x, hout.y);
                        cr.set_source_rgba(accent.red, accent.green, accent.blue, 0.85);
                        cr.stroke();

                        cr.new_path();
                        cr.arc(hout.x, hout.y, handle_radius, 0.0, 2.0 * Math.PI);
                        cr.set_source_rgb(1.0, 1.0, 1.0);
                        cr.fill_preserve();
                        cr.set_source_rgb(accent.red, accent.green, accent.blue);
                        cr.set_line_width(1.5 / z);
                        cr.stroke();
                    }
                    cr.restore();
                }

                cr.save();
                cr.new_path();
                double half_a = anchor_size / 2.0;
                if (node.node_type == NodeType.SMOOTH || node.node_type == NodeType.ASYMMETRIC) {
                    cr.arc(x, y, half_a, 0.0, 2.0 * Math.PI);
                } else {
                    cr.rectangle(x - half_a, y - half_a, anchor_size, anchor_size);
                }

                if (is_selected) {
                    cr.set_source_rgb(accent.red, accent.green, accent.blue);
                    cr.fill_preserve();
                    cr.set_source_rgb(1.0, 1.0, 1.0);
                    cr.set_line_width(2.0 / z);
                    cr.stroke();
                } else {
                    cr.set_source_rgb(1.0, 1.0, 1.0);
                    cr.fill_preserve();
                    cr.set_source_rgba(0.15, 0.15, 0.2, 0.85);
                    cr.set_line_width(1.5 / z);
                    cr.stroke();
                }
                cr.restore();
            }
        }

        public static int hit_node_anchor(Shape path, double doc_x, double doc_y, double zoom = 1.0, double hit_radius = 8.0) {
            double z = Math.fmax(1e-6, zoom);
            double threshold = (hit_radius / z) * (hit_radius / z);
            for (uint i = 0; i < path.nodes.length; i++) {
                unowned PathNode n = path.nodes[i];
                double d2 = (doc_x - n.x) * (doc_x - n.x) + (doc_y - n.y) * (doc_y - n.y);
                if (d2 <= threshold) return (int) i;
            }
            return -1;
        }

        public static string? hit_node_handle(PathNode node, double doc_x, double doc_y, double zoom = 1.0, double hit_radius = 8.0) {
            double z = Math.fmax(1e-6, zoom);
            double threshold = (hit_radius / z) * (hit_radius / z);
            if (node.handle_in != null) {
                Point hin = node.handle_in;
                if ((doc_x - hin.x) * (doc_x - hin.x) + (doc_y - hin.y) * (doc_y - hin.y) <= threshold) {
                    return "handle_in";
                }
            }
            if (node.handle_out != null) {
                Point hout = node.handle_out;
                if ((doc_x - hout.x) * (doc_x - hout.x) + (doc_y - hout.y) * (doc_y - hout.y) <= threshold) {
                    return "handle_out";
                }
            }
            return null;
        }

        public static void paint_pen_preview(Cairo.Context cr, Shape draft_path, Point? hover_pt = null,
                                             Color accent = Color.rgb(0.2, 0.5, 0.9), double zoom = 1.0) {
            if (draft_path.nodes.length == 0) return;
            double z = Math.fmax(1e-6, zoom);
            cr.save();

            cr.new_path();
            trace_shape(cr, draft_path);
            cr.set_source_rgba(accent.red, accent.green, accent.blue, 0.9);
            cr.set_line_width(2.0 / z);
            cr.stroke();

            bool is_closing = false;
            if (hover_pt != null && draft_path.nodes.length > 0) {
                unowned PathNode last = draft_path.nodes[draft_path.nodes.length - 1];
                unowned PathNode first = draft_path.nodes[0];
                Point hpt = hover_pt;
                double dist_to_first = Math.hypot(hpt.x - first.x, hpt.y - first.y);

                Point target = hpt;
                if (draft_path.nodes.length >= 2 && dist_to_first <= (14.0 / z)) {
                    is_closing = true;
                    target = Point(first.x, first.y);
                }

                cr.new_path();
                cr.move_to(last.x, last.y);
                if (last.handle_out != null) {
                    Point hout = last.handle_out;
                    cr.curve_to(hout.x, hout.y, target.x, target.y, target.x, target.y);
                } else {
                    cr.line_to(target.x, target.y);
                }
                double[] dashes = { 5.0 / z, 4.0 / z };
                cr.set_dash(dashes, 0.0);
                cr.set_source_rgba(accent.red, accent.green, accent.blue, 0.75);
                cr.set_line_width(1.5 / z);
                cr.stroke();

                if (is_closing) {
                    cr.set_dash(new double[0], 0.0);
                    cr.new_path();
                    cr.arc(first.x + 11.0 / z, first.y - 11.0 / z, 3.5 / z, 0.0, 2.0 * Math.PI);
                    cr.set_source_rgb(accent.red, accent.green, accent.blue);
                    cr.set_line_width(1.5 / z);
                    cr.stroke();
                }
            }

            cr.restore();
            paint_node_edit_overlay(cr, draft_path, (int) draft_path.nodes.length - 1, accent, zoom);
        }
    }
}
