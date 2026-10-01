/* Geometry.vala - Pure geometric math, bounds normalization, resizing, alignments, and spatial hits */

namespace Nova {

    public class Geometry {
        public const double MIN_SHAPE_SIZE = 8.0;

        public static void normalize_bounds(double in_x, double in_y, double in_w, double in_h,
                                            out double out_x, out double out_y, out double out_w, out double out_h) {
            out_x = in_x;
            out_y = in_y;
            out_w = in_w;
            out_h = in_h;

            if (out_w < 0.0) {
                out_x += out_w;
                out_w = -out_w;
            }
            if (out_h < 0.0) {
                out_y += out_h;
                out_h = -out_h;
            }
        }

        private static void bounds_around_center(double x, double y, double width, double height,
                                                 double new_width, double new_height,
                                                 out double rx, out double ry, out double rw, out double rh) {
            double center_x = x + width / 2.0;
            double center_y = y + height / 2.0;
            rx = center_x - new_width / 2.0;
            ry = center_y - new_height / 2.0;
            rw = new_width;
            rh = new_height;
        }

        public static void resize_from_corner(double x, double y, double width, double height,
                                              string handle, double dx, double dy,
                                              bool lock_ratio, bool from_center, double min_size,
                                              out double rx, out double ry, out double rw, out double rh) {
            double anchor_x = x;
            double anchor_y = y;
            double sign_x = 1.0;
            double sign_y = 1.0;

            if (handle == "se") {
                anchor_x = x;
                anchor_y = y;
                sign_x = 1.0;
                sign_y = 1.0;
            } else if (handle == "nw") {
                anchor_x = x + width;
                anchor_y = y + height;
                sign_x = -1.0;
                sign_y = -1.0;
            } else if (handle == "ne") {
                anchor_x = x;
                anchor_y = y + height;
                sign_x = 1.0;
                sign_y = -1.0;
            } else if (handle == "sw") {
                anchor_x = x + width;
                anchor_y = y;
                sign_x = -1.0;
                sign_y = 1.0;
            } else {
                rx = x; ry = y; rw = width; rh = height;
                return;
            }

            double growth = from_center ? 2.0 : 1.0;
            double new_width = width;
            double new_height = height;

            if (lock_ratio) {
                double grown_width = width + growth * sign_x * dx;
                double grown_height = height + growth * sign_y * dy;
                double scale_x = width > 0.0 ? grown_width / width : 1.0;
                double scale_y = height > 0.0 ? grown_height / height : 1.0;
                double scale = (Math.fabs(dx) * height >= Math.fabs(dy) * width) ? scale_x : scale_y;
                double smallest = Math.fmin(width, height);
                if (smallest > 0.0) {
                    scale = Math.fmax(scale, min_size / smallest);
                }
                new_width = width * scale;
                new_height = height * scale;
            } else {
                new_width = Math.fmax(width + growth * sign_x * dx, min_size);
                new_height = Math.fmax(height + growth * sign_y * dy, min_size);
            }

            if (from_center) {
                bounds_around_center(x, y, width, height, new_width, new_height, out rx, out ry, out rw, out rh);
                return;
            }

            if (handle == "se") {
                rx = anchor_x;
                ry = anchor_y;
                rw = new_width;
                rh = new_height;
            } else if (handle == "nw") {
                rx = anchor_x - new_width;
                ry = anchor_y - new_height;
                rw = new_width;
                rh = new_height;
            } else if (handle == "ne") {
                rx = anchor_x;
                ry = anchor_y - new_height;
                rw = new_width;
                rh = new_height;
            } else { // "sw"
                rx = anchor_x - new_width;
                ry = anchor_y;
                rw = new_width;
                rh = new_height;
            }
        }

        public static void resize_from_edge(double x, double y, double width, double height,
                                            string handle, double dx, double dy,
                                            bool from_center, double min_size,
                                            out double rx, out double ry, out double rw, out double rh) {
            double growth = from_center ? 2.0 : 1.0;
            double new_width = width;
            double new_height = height;

            if (handle == "e") {
                new_width = Math.fmax(width + growth * dx, min_size);
            } else if (handle == "w") {
                new_width = Math.fmax(width - growth * dx, min_size);
            } else if (handle == "s") {
                new_height = Math.fmax(height + growth * dy, min_size);
            } else if (handle == "n") {
                new_height = Math.fmax(height - growth * dy, min_size);
            }

            if (from_center) {
                bounds_around_center(x, y, width, height, new_width, new_height, out rx, out ry, out rw, out rh);
                return;
            }

            if (handle == "e" || handle == "s") {
                rx = x;
                ry = y;
                rw = new_width;
                rh = new_height;
            } else if (handle == "w") {
                rx = x + width - new_width;
                ry = y;
                rw = new_width;
                rh = new_height;
            } else { // "n"
                rx = x;
                ry = y + height - new_height;
                rw = new_width;
                rh = new_height;
            }
        }

        public static double corner_radius_from_pointer(string handle, double px, double py,
                                                        double x, double y, double width, double height) {
            double raw = 0.0;
            if (handle == "rtl") {
                raw = Math.fmax(px - x, py - y);
            } else if (handle == "rtr") {
                raw = Math.fmax(x + width - px, py - y);
            } else if (handle == "rbr") {
                raw = Math.fmax(x + width - px, y + height - py);
            } else if (handle == "rbl") {
                raw = Math.fmax(px - x, y + height - py);
            }
            double limit = Math.fmax(0.0, Math.fmin(width, height) / 2.0);
            return Math.fmax(0.0, Math.fmin(raw, limit));
        }

        public static CornerRadii get_corner_radii(Shape shape) {
            double tl = Math.fmax(0.0, shape.corner_radius.tl);
            double tr = Math.fmax(0.0, shape.corner_radius.tr);
            double br = Math.fmax(0.0, shape.corner_radius.br);
            double bl = Math.fmax(0.0, shape.corner_radius.bl);

            double w = Math.fmax(0.0, shape.w);
            double h = Math.fmax(0.0, shape.h);
            if (w <= 0.0 || h <= 0.0) {
                return CornerRadii(0, 0, 0, 0);
            }

            double factor = 1.0;
            double top_sum = tl + tr;
            double bottom_sum = bl + br;
            double left_sum = tl + bl;
            double right_sum = tr + br;

            if (top_sum > w) {
                factor = Math.fmin(factor, w / top_sum);
            }
            if (bottom_sum > w) {
                factor = Math.fmin(factor, w / bottom_sum);
            }
            if (left_sum > h) {
                factor = Math.fmin(factor, h / left_sum);
            }
            if (right_sum > h) {
                factor = Math.fmin(factor, h / right_sum);
            }

            return CornerRadii(tl * factor, tr * factor, br * factor, bl * factor);
        }

        public static bool is_drawable(Shape shape) {
            if (!shape.visible) {
                return false;
            }
            if (shape.shape_type == ShapeType.LINE || shape.shape_type == ShapeType.ARROW) {
                return shape.w >= 0.0 && shape.h >= 0.0 && (shape.w > 0.0 || shape.h > 0.0);
            }
            return shape.w > 0.0 && shape.h > 0.0;
        }

        public static bool contains_point(Shape shape, double px, double py) {
            if (!is_drawable(shape)) {
                return false;
            }

            double left = shape.x;
            double top = shape.y;
            double width = shape.w;
            double height = shape.h;

            if (shape.shape_type == ShapeType.GROUP) {
                for (uint i = 0; i < shape.children.length; i++) {
                    if (contains_point(shape.children[i], px, py)) {
                        return true;
                    }
                }
                return px >= left && px <= left + width && py >= top && py <= top + height;
            }

            if (shape.shape_type == ShapeType.ELLIPSE) {
                double rx = width / 2.0;
                double ry = height / 2.0;
                if (rx <= 0.0 || ry <= 0.0) return false;
                double dx = (px - (left + rx)) / rx;
                double dy = (py - (top + ry)) / ry;
                return (dx * dx + dy * dy) <= 1.0;
            }

            if (shape.shape_type == ShapeType.LINE || shape.shape_type == ShapeType.ARROW) {
                double x1 = left;
                double y1 = top;
                double x2 = left + width;
                double y2 = top + height;
                double seg_len2 = (x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1);
                if (seg_len2 == 0.0) {
                    return (px - x1) * (px - x1) + (py - y1) * (py - y1) <= 64.0;
                }
                double t = Math.fmax(0.0, Math.fmin(1.0, ((px - x1) * (x2 - x1) + (py - y1) * (y2 - y1)) / seg_len2));
                double proj_x = x1 + t * (x2 - x1);
                double proj_y = y1 + t * (y2 - y1);
                return (px - proj_x) * (px - proj_x) + (py - proj_y) * (py - proj_y) <= 64.0;
            }

            if (shape.shape_type == ShapeType.PATH) {
                if (shape.nodes.length < 2) {
                    return px >= left && px <= left + width && py >= top && py <= top + height;
                }
                var poly = Paths.sample_path_to_polygon(shape, shape.closed, 16);
                if (shape.closed && poly.length >= 3) {
                    if (Paths.point_in_polygon(px, py, poly)) {
                        return true;
                    }
                }
                for (uint i = 0; i < poly.length - 1; i++) {
                    double x1 = poly[i].x;
                    double y1 = poly[i].y;
                    double x2 = poly[i + 1].x;
                    double y2 = poly[i + 1].y;
                    double seg_len2 = (x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1);
                    if (seg_len2 > 0.0) {
                        double t = Math.fmax(0.0, Math.fmin(1.0, ((px - x1) * (x2 - x1) + (py - y1) * (y2 - y1)) / seg_len2));
                        double proj_x = x1 + t * (x2 - x1);
                        double proj_y = y1 + t * (y2 - y1);
                        if ((px - proj_x) * (px - proj_x) + (py - proj_y) * (py - proj_y) <= 64.0) {
                            return true;
                        }
                    }
                }
                return false;
            }

            // Default bounding box check
            if (!(px >= left && px <= left + width && py >= top && py <= top + height)) {
                return false;
            }

            if (shape.shape_type == ShapeType.RECT || shape.shape_type == ShapeType.FRAME) {
                CornerRadii radii = get_corner_radii(shape);
                if (radii.tl > 0.0 && px < left + radii.tl && py < top + radii.tl) {
                    double dx = px - (left + radii.tl);
                    double dy = py - (top + radii.tl);
                    return dx * dx + dy * dy <= radii.tl * radii.tl;
                }
                if (radii.tr > 0.0 && px > left + width - radii.tr && py < top + radii.tr) {
                    double dx = px - (left + width - radii.tr);
                    double dy = py - (top + radii.tr);
                    return dx * dx + dy * dy <= radii.tr * radii.tr;
                }
                if (radii.br > 0.0 && px > left + width - radii.br && py > top + height - radii.br) {
                    double dx = px - (left + width - radii.br);
                    double dy = py - (top + height - radii.br);
                    return dx * dx + dy * dy <= radii.br * radii.br;
                }
                if (radii.bl > 0.0 && px < left + radii.bl && py > top + height - radii.bl) {
                    double dx = px - (left + radii.bl);
                    double dy = py - (top + height - radii.bl);
                    return dx * dx + dy * dy <= radii.bl * radii.bl;
                }
            }

            return true;
        }

        public static Rect bounding_box(GLib.GenericArray<Shape> shapes) {
            if (shapes.length == 0) {
                return Rect(0.0, 0.0, 0.0, 0.0);
            }
            double min_x = shapes[0].x;
            double min_y = shapes[0].y;
            double max_x = shapes[0].x + shapes[0].w;
            double max_y = shapes[0].y + shapes[0].h;

            for (uint i = 1; i < shapes.length; i++) {
                unowned Shape s = shapes[i];
                min_x = Math.fmin(min_x, s.x);
                min_y = Math.fmin(min_y, s.y);
                max_x = Math.fmax(max_x, s.x + s.w);
                max_y = Math.fmax(max_y, s.y + s.h);
            }

            return Rect(min_x, min_y, Math.fmax(1.0, max_x - min_x), Math.fmax(1.0, max_y - min_y));
        }

        public static bool shape_intersects_rect(Shape shape, double rx, double ry, double rw, double rh) {
            double sx = shape.x;
            double sy = shape.y;
            double sw = shape.w;
            double sh = shape.h;
            return !(sx + sw < rx || sx > rx + rw || sy + sh < ry || sy > ry + rh);
        }

        public static void align_shapes_left(GLib.GenericArray<Shape> shapes) {
            if (shapes.length < 2) return;
            double target_x = shapes[0].x;
            for (uint i = 1; i < shapes.length; i++) {
                target_x = Math.fmin(target_x, shapes[i].x);
            }
            for (uint i = 0; i < shapes.length; i++) {
                shapes[i].x = target_x;
            }
        }

        public static void align_shapes_center(GLib.GenericArray<Shape> shapes) {
            if (shapes.length < 2) return;
            double min_x = shapes[0].x;
            double max_x = shapes[0].x + shapes[0].w;
            for (uint i = 1; i < shapes.length; i++) {
                min_x = Math.fmin(min_x, shapes[i].x);
                max_x = Math.fmax(max_x, shapes[i].x + shapes[i].w);
            }
            double center_x = (min_x + max_x) / 2.0;
            for (uint i = 0; i < shapes.length; i++) {
                shapes[i].x = center_x - shapes[i].w / 2.0;
            }
        }

        public static void align_shapes_right(GLib.GenericArray<Shape> shapes) {
            if (shapes.length < 2) return;
            double target_right = shapes[0].x + shapes[0].w;
            for (uint i = 1; i < shapes.length; i++) {
                target_right = Math.fmax(target_right, shapes[i].x + shapes[i].w);
            }
            for (uint i = 0; i < shapes.length; i++) {
                shapes[i].x = target_right - shapes[i].w;
            }
        }

        public static void align_shapes_top(GLib.GenericArray<Shape> shapes) {
            if (shapes.length < 2) return;
            double target_y = shapes[0].y;
            for (uint i = 1; i < shapes.length; i++) {
                target_y = Math.fmin(target_y, shapes[i].y);
            }
            for (uint i = 0; i < shapes.length; i++) {
                shapes[i].y = target_y;
            }
        }

        public static void align_shapes_middle(GLib.GenericArray<Shape> shapes) {
            if (shapes.length < 2) return;
            double min_y = shapes[0].y;
            double max_y = shapes[0].y + shapes[0].h;
            for (uint i = 1; i < shapes.length; i++) {
                min_y = Math.fmin(min_y, shapes[i].y);
                max_y = Math.fmax(max_y, shapes[i].y + shapes[i].h);
            }
            double middle_y = (min_y + max_y) / 2.0;
            for (uint i = 0; i < shapes.length; i++) {
                shapes[i].y = middle_y - shapes[i].h / 2.0;
            }
        }

        public static void align_shapes_bottom(GLib.GenericArray<Shape> shapes) {
            if (shapes.length < 2) return;
            double target_bottom = shapes[0].y + shapes[0].h;
            for (uint i = 1; i < shapes.length; i++) {
                target_bottom = Math.fmax(target_bottom, shapes[i].y + shapes[i].h);
            }
            for (uint i = 0; i < shapes.length; i++) {
                shapes[i].y = target_bottom - shapes[i].h;
            }
        }

        public static void distribute_shapes_horizontally(GLib.GenericArray<Shape> shapes) {
            if (shapes.length < 3) return;
            var list = new GLib.GenericArray<Shape>();
            for (uint i = 0; i < shapes.length; i++) {
                list.add(shapes[i]);
            }
            list.sort((a, b) => {
                double diff = a.x - b.x;
                if (diff < 0) return -1;
                if (diff > 0) return 1;
                return 0;
            });
            double first_x = list[0].x;
            double last_x = list[list.length - 1].x;
            double step = (last_x - first_x) / (list.length - 1);
            for (uint i = 0; i < list.length; i++) {
                list[i].x = first_x + i * step;
            }
        }

        public static void distribute_shapes_vertically(GLib.GenericArray<Shape> shapes) {
            if (shapes.length < 3) return;
            var list = new GLib.GenericArray<Shape>();
            for (uint i = 0; i < shapes.length; i++) {
                list.add(shapes[i]);
            }
            list.sort((a, b) => {
                double diff = a.y - b.y;
                if (diff < 0) return -1;
                if (diff > 0) return 1;
                return 0;
            });
            double first_y = list[0].y;
            double last_y = list[list.length - 1].y;
            double step = (last_y - first_y) / (list.length - 1);
            for (uint i = 0; i < list.length; i++) {
                list[i].y = first_y + i * step;
            }
        }

        public static GLib.GenericArray<Point?> smooth_points(GLib.GenericArray<Point?> points, int iterations = 2) {
            if (points.length < 3 || iterations <= 0) {
                var copy = new GLib.GenericArray<Point?>();
                for (uint i = 0; i < points.length; i++) copy.add(points[i]);
                return copy;
            }
            var current = new GLib.GenericArray<Point?>();
            for (uint i = 0; i < points.length; i++) current.add(points[i]);

            for (int iter = 0; iter < iterations; iter++) {
                if (current.length < 3) break;
                var smoothed = new GLib.GenericArray<Point?>();
                smoothed.add(current[0]);
                for (uint i = 0; i < current.length - 1; i++) {
                    Point p0 = current[i];
                    Point p1 = current[i + 1];
                    Point q = Point(0.75 * p0.x + 0.25 * p1.x, 0.75 * p0.y + 0.25 * p1.y);
                    Point r = Point(0.25 * p0.x + 0.75 * p1.x, 0.25 * p0.y + 0.75 * p1.y);
                    smoothed.add(q);
                    smoothed.add(r);
                }
                smoothed.add(current[current.length - 1]);
                current = smoothed;
            }
            return current;
        }

        public static bool is_point_in_frame(double px, double py, Shape frame) {
            return px >= frame.x && px <= frame.x + frame.w &&
                   py >= frame.y && py <= frame.y + frame.h;
        }

        public static bool is_shape_in_frame(Shape shape, Shape frame) {
            if (shape == frame || shape.shape_type == ShapeType.FRAME) {
                return false;
            }
            if (shape.frame_id != null) {
                return shape.frame_id == frame.id;
            }
            double cx = shape.x + shape.w / 2.0;
            double cy = shape.y + shape.h / 2.0;
            return is_point_in_frame(cx, cy, frame);
        }

        public static GLib.GenericArray<Shape> get_frame_children(Shape frame, GLib.GenericArray<Shape> shapes) {
            var result = new GLib.GenericArray<Shape>();
            for (uint i = 0; i < shapes.length; i++) {
                if (is_shape_in_frame(shapes[i], frame)) {
                    result.add(shapes[i]);
                }
            }
            return result;
        }

        public static bool hit_test_frame_header(Shape frame, double x, double y, double zoom = 1.0) {
            double fx = frame.x;
            double fy = frame.y;
            double fw = frame.w;
            double z = Math.fmax(1e-6, zoom);
            double header_height = Math.fmax(18.0, 24.0 / z);
            return x >= fx && x <= fx + fw && y >= fy - header_height && y <= fy;
        }

        public static bool hit_test_frame_border(Shape frame, double x, double y, double margin = 6.0) {
            double fx = frame.x;
            double fy = frame.y;
            double fw = frame.w;
            double fh = frame.h;
            if (!(x >= fx - margin && x <= fx + fw + margin && y >= fy - margin && y <= fy + fh + margin)) {
                return false;
            }
            bool near_left = Math.fabs(x - fx) <= margin;
            bool near_right = Math.fabs(x - (fx + fw)) <= margin;
            bool near_top = Math.fabs(y - fy) <= margin;
            bool near_bottom = Math.fabs(y - (fy + fh)) <= margin;
            return near_left || near_right || near_top || near_bottom;
        }
    }
}
