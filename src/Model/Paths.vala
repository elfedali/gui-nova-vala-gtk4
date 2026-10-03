/* Paths.vala - Bézier mathematics, node editing, path conversion, and Greiner-Hormann boolean engine */

namespace Nova {

    public class Paths {
        public const double KAPPA = 0.5522847498307935; // 4.0 * (sqrt(2.0) - 1.0) / 3.0

        public static Point cubic_bezier_point(Point p0, Point p1, Point p2, Point p3, double t) {
            double u = 1.0 - t;
            double u2 = u * u;
            double u3 = u2 * u;
            double t2 = t * t;
            double t3 = t2 * t;
            double x = u3 * p0.x + 3.0 * u2 * t * p1.x + 3.0 * u * t2 * p2.x + t3 * p3.x;
            double y = u3 * p0.y + 3.0 * u2 * t * p1.y + 3.0 * u * t2 * p2.y + t3 * p3.y;
            return Point(x, y);
        }

        public static void cubic_bezier_split(Point p0, Point p1, Point p2, Point p3, double t,
                                              out Point left_0, out Point left_1, out Point left_2, out Point left_3,
                                              out Point right_0, out Point right_1, out Point right_2, out Point right_3) {
            Point p01 = Point(p0.x + t * (p1.x - p0.x), p0.y + t * (p1.y - p0.y));
            Point p12 = Point(p1.x + t * (p2.x - p1.x), p1.y + t * (p2.y - p1.y));
            Point p23 = Point(p2.x + t * (p3.x - p2.x), p2.y + t * (p3.y - p2.y));

            Point p012 = Point(p01.x + t * (p12.x - p01.x), p01.y + t * (p12.y - p01.y));
            Point p123 = Point(p12.x + t * (p23.x - p12.x), p12.y + t * (p23.y - p12.y));

            Point p0123 = Point(p012.x + t * (p123.x - p012.x), p012.y + t * (p123.y - p012.y));

            left_0 = p0;
            left_1 = p01;
            left_2 = p012;
            left_3 = p0123;

            right_0 = p0123;
            right_1 = p123;
            right_2 = p23;
            right_3 = p3;
        }

        public static GLib.GenericArray<Point?> sample_cubic_bezier(Point p0, Point p1, Point p2, Point p3, int steps = 16) {
            var pts = new GLib.GenericArray<Point?>();
            for (int i = 0; i <= steps; i++) {
                double t = ((double) i) / steps;
                pts.add(cubic_bezier_point(p0, p1, p2, p3, t));
            }
            return pts;
        }

        public static void closest_point_on_segment(double px, double py, Point p0, Point p1, Point p2, Point p3,
                                                    int samples, out double best_t, out double best_dist) {
            best_t = 0.0;
            double best_dist2 = double.MAX;
            for (int i = 0; i <= samples; i++) {
                double t = ((double) i) / samples;
                Point b = cubic_bezier_point(p0, p1, p2, p3, t);
                double d2 = (px - b.x) * (px - b.x) + (py - b.y) * (py - b.y);
                if (d2 < best_dist2) {
                    best_dist2 = d2;
                    best_t = t;
                }
            }
            best_dist = Math.sqrt(best_dist2);
        }

        public static PathNode create_node(double x, double y, Point? hin = null, Point? hout = null, NodeType ntype = NodeType.CORNER) {
            return new PathNode(x, y, hin, hout, ntype);
        }

        public static void set_node_type(PathNode node, NodeType new_type) {
            node.node_type = new_type;
            double x = node.x;
            double y = node.y;
            Point? hin = node.handle_in;
            Point? hout = node.handle_out;

            if (new_type == NodeType.CORNER) {
                // keep independent
            } else if (new_type == NodeType.SMOOTH || new_type == NodeType.ASYMMETRIC) {
                if (hin == null && hout == null) {
                    node.handle_in = Point(x - 20.0, y);
                    node.handle_out = Point(x + 20.0, y);
                } else if (hout != null && hin == null) {
                    double dx = hout.x - x;
                    double dy = hout.y - y;
                    node.handle_in = Point(x - dx, y - dy);
                } else if (hin != null && hout == null) {
                    double dx = hin.x - x;
                    double dy = hin.y - y;
                    node.handle_out = Point(x - dx, y - dy);
                } else if (hin != null && hout != null) {
                    double dx_out = hout.x - x;
                    double dy_out = hout.y - y;
                    double len_out = Math.hypot(dx_out, dy_out);
                    double len_in = Math.hypot(hin.x - x, hin.y - y);
                    if (len_out > 1e-4) {
                        double nx = dx_out / len_out;
                        double ny = dy_out / len_out;
                        if (new_type == NodeType.SMOOTH) {
                            double avg_len = len_in > 1e-4 ? (len_out + len_in) / 2.0 : len_out;
                            node.handle_out = Point(x + nx * avg_len, y + ny * avg_len);
                            node.handle_in = Point(x - nx * avg_len, y - ny * avg_len);
                        } else {
                            node.handle_in = Point(x - nx * len_in, y - ny * len_in);
                        }
                    }
                }
            }
        }

        public static void update_node_handle(PathNode node, string handle_name, double new_hx, double new_hy) {
            double x = node.x;
            double y = node.y;
            if (handle_name == "handle_out") {
                node.handle_out = Point(new_hx, new_hy);
            } else {
                node.handle_in = Point(new_hx, new_hy);
            }

            if (node.node_type == NodeType.SMOOTH || node.node_type == NodeType.ASYMMETRIC) {
                bool is_out = (handle_name == "handle_out");
                double dx = new_hx - x;
                double dy = new_hy - y;
                double dist = Math.hypot(dx, dy);
                if (dist > 1e-4) {
                    double nx = dx / dist;
                    double ny = dy / dist;
                    if (node.node_type == NodeType.SMOOTH) {
                        if (is_out) {
                            node.handle_in = Point(x - nx * dist, y - ny * dist);
                        } else {
                            node.handle_out = Point(x - nx * dist, y - ny * dist);
                        }
                    } else { // ASYMMETRIC
                        if (is_out) {
                            Point? opp_h = node.handle_in;
                            double opp_len = opp_h != null ? Math.hypot(opp_h.x - x, opp_h.y - y) : dist;
                            node.handle_in = Point(x - nx * opp_len, y - ny * opp_len);
                        } else {
                            Point? opp_h = node.handle_out;
                            double opp_len = opp_h != null ? Math.hypot(opp_h.x - x, opp_h.y - y) : dist;
                            node.handle_out = Point(x - nx * opp_len, y - ny * opp_len);
                        }
                    }
                }
            }
        }

        public static int add_node_to_path(Shape path, double x, double y, double hit_threshold = 12.0) {
            if (path.nodes.length < 2) {
                path.nodes.add(create_node(x, y));
                path_recalculate_bounds(path);
                return (int) path.nodes.length - 1;
            }

            bool closed = path.closed;
            uint num_segments = closed ? path.nodes.length : path.nodes.length - 1;
            int best_seg = -1;
            double best_t = 0.5;
            double min_dist = double.MAX;

            for (uint i = 0; i < num_segments; i++) {
                unowned PathNode n0 = path.nodes[i];
                unowned PathNode n1 = path.nodes[(i + 1) % path.nodes.length];
                Point p0 = Point(n0.x, n0.y);
                Point p1 = n0.handle_out != null ? n0.handle_out : p0;
                Point p3 = Point(n1.x, n1.y);
                Point p2 = n1.handle_in != null ? n1.handle_in : p3;

                double t, dist;
                closest_point_on_segment(x, y, p0, p1, p2, p3, 32, out t, out dist);
                if (dist < min_dist) {
                    min_dist = dist;
                    best_seg = (int) i;
                    best_t = t;
                }
            }

            if (best_seg >= 0 && min_dist <= hit_threshold * 2.0) {
                unowned PathNode n0 = path.nodes[best_seg];
                unowned PathNode n1 = path.nodes[(best_seg + 1) % path.nodes.length];
                Point p0 = Point(n0.x, n0.y);
                Point p1 = n0.handle_out != null ? n0.handle_out : p0;
                Point p3 = Point(n1.x, n1.y);
                Point p2 = n1.handle_in != null ? n1.handle_in : p3;

                Point l0, l1, l2, l3, r0, r1, r2, r3;
                cubic_bezier_split(p0, p1, p2, p3, best_t, out l0, out l1, out l2, out l3, out r0, out r1, out r2, out r3);

                PathNode new_node;
                if (n0.handle_out != null || n1.handle_in != null) {
                    n0.handle_out = l1;
                    n1.handle_in = r2;
                    new_node = create_node(l3.x, l3.y, l2, r1, NodeType.SMOOTH);
                } else {
                    new_node = create_node(x, y, null, null, NodeType.CORNER);
                }

                int insert_pos = best_seg + 1;
                path.nodes.insert(insert_pos, new_node);
                path_recalculate_bounds(path);
                return insert_pos;
            }

            path.nodes.add(create_node(x, y));
            path_recalculate_bounds(path);
            return (int) path.nodes.length - 1;
        }

        public static bool remove_node_from_path(Shape path, int index) {
            if (index >= 0 && index < (int) path.nodes.length && path.nodes.length > 2) {
                path.nodes.remove_index((uint) index);
                path_recalculate_bounds(path);
                return true;
            }
            return false;
        }

        public static void path_recalculate_bounds(Shape path) {
            if (path.nodes.length == 0) return;
            double min_x = path.nodes[0].x;
            double min_y = path.nodes[0].y;
            double max_x = path.nodes[0].x;
            double max_y = path.nodes[0].y;

            for (uint i = 0; i < path.nodes.length; i++) {
                unowned PathNode n = path.nodes[i];
                min_x = Math.fmin(min_x, n.x);
                min_y = Math.fmin(min_y, n.y);
                max_x = Math.fmax(max_x, n.x);
                max_y = Math.fmax(max_y, n.y);

                if (n.handle_in != null) {
                    min_x = Math.fmin(min_x, n.handle_in.x);
                    min_y = Math.fmin(min_y, n.handle_in.y);
                    max_x = Math.fmax(max_x, n.handle_in.x);
                    max_y = Math.fmax(max_y, n.handle_in.y);
                }
                if (n.handle_out != null) {
                    min_x = Math.fmin(min_x, n.handle_out.x);
                    min_y = Math.fmin(min_y, n.handle_out.y);
                    max_x = Math.fmax(max_x, n.handle_out.x);
                    max_y = Math.fmax(max_y, n.handle_out.y);
                }
            }

            path.x = min_x;
            path.y = min_y;
            path.w = Math.fmax(1.0, max_x - min_x);
            path.h = Math.fmax(1.0, max_y - min_y);
        }

        public static Shape shape_to_path(Shape shape) {
            if (shape.shape_type == ShapeType.PATH) {
                return shape.clone();
            }

            var path_shape = new Shape(ShapeType.PATH);
            path_shape.name = "Path (" + shape.name + ")";
            path_shape.x = shape.x;
            path_shape.y = shape.y;
            path_shape.w = shape.w;
            path_shape.h = shape.h;
            path_shape.color = shape.color;
            path_shape.fill_visible = shape.fill_visible;
            path_shape.has_stroke = shape.has_stroke;
            path_shape.stroke_color = shape.stroke_color;
            path_shape.stroke_width = shape.stroke_width;
            path_shape.closed = true;

            double x = shape.x;
            double y = shape.y;
            double w = shape.w;
            double h = shape.h;

            if (shape.shape_type == ShapeType.RECT || shape.shape_type == ShapeType.FRAME) {
                CornerRadii radii = Geometry.get_corner_radii(shape);
                if (radii.tl == 0 && radii.tr == 0 && radii.br == 0 && radii.bl == 0) {
                    path_shape.nodes.add(create_node(x, y));
                    path_shape.nodes.add(create_node(x + w, y));
                    path_shape.nodes.add(create_node(x + w, y + h));
                    path_shape.nodes.add(create_node(x, y + h));
                } else {
                    path_shape.nodes.add(create_node(x + radii.tl, y));
                    path_shape.nodes.add(create_node(x + w - radii.tr, y));
                    path_shape.nodes.add(create_node(x + w, y + radii.tr));
                    path_shape.nodes.add(create_node(x + w, y + h - radii.br));
                    path_shape.nodes.add(create_node(x + w - radii.br, y + h));
                    path_shape.nodes.add(create_node(x + radii.bl, y + h));
                    path_shape.nodes.add(create_node(x, y + h - radii.bl));
                    path_shape.nodes.add(create_node(x, y + radii.tl));
                }
            } else if (shape.shape_type == ShapeType.ELLIPSE) {
                double rx = w / 2.0;
                double ry = h / 2.0;
                double cx = x + rx;
                double cy = y + ry;
                double kx = rx * KAPPA;
                double ky = ry * KAPPA;

                path_shape.nodes.add(create_node(cx, cy - ry, Point(cx - kx, cy - ry), Point(cx + kx, cy - ry), NodeType.SMOOTH));
                path_shape.nodes.add(create_node(cx + rx, cy, Point(cx + rx, cy - ky), Point(cx + rx, cy + ky), NodeType.SMOOTH));
                path_shape.nodes.add(create_node(cx, cy + ry, Point(cx + kx, cy + ry), Point(cx - kx, cy + ry), NodeType.SMOOTH));
                path_shape.nodes.add(create_node(cx - rx, cy, Point(cx - rx, cy + ky), Point(cx - rx, cy - ky), NodeType.SMOOTH));
            } else if (shape.shape_type == ShapeType.POLYGON) {
                int sides = int.max(3, shape.sides);
                double cx = x + w / 2.0;
                double cy = y + h / 2.0;
                double rx = w / 2.0;
                double ry = h / 2.0;
                for (int i = 0; i < sides; i++) {
                    double angle = -Math.PI / 2.0 + (2.0 * Math.PI * i) / sides;
                    double px = cx + rx * Math.cos(angle);
                    double py = cy + ry * Math.sin(angle);
                    path_shape.nodes.add(create_node(px, py));
                }
            } else if (shape.shape_type == ShapeType.STAR) {
                int pts_count = int.max(3, shape.points_count);
                double ratio = Math.fmax(0.1, Math.fmin(0.9, shape.inner_ratio));
                double cx = x + w / 2.0;
                double cy = y + h / 2.0;
                double rx = w / 2.0;
                double ry = h / 2.0;
                int total_pts = pts_count * 2;
                for (int i = 0; i < total_pts; i++) {
                    double angle = -Math.PI / 2.0 + (Math.PI * i) / pts_count;
                    double r_scale = (i % 2 == 0) ? 1.0 : ratio;
                    double px = cx + rx * r_scale * Math.cos(angle);
                    double py = cy + ry * r_scale * Math.sin(angle);
                    path_shape.nodes.add(create_node(px, py));
                }
            } else if (shape.shape_type == ShapeType.LINE || shape.shape_type == ShapeType.ARROW) {
                path_shape.nodes.add(create_node(x, y));
                path_shape.nodes.add(create_node(x + w, y + h));
                path_shape.closed = false;
            } else if (shape.shape_type == ShapeType.PENCIL) {
                for (uint i = 0; i < shape.points.length; i++) {
                    Point p = shape.points[i];
                    path_shape.nodes.add(create_node(x + p.x, y + p.y));
                }
                path_shape.closed = false;
            } else {
                path_shape.nodes.add(create_node(x, y));
                path_shape.nodes.add(create_node(x + w, y));
                path_shape.nodes.add(create_node(x + w, y + h));
                path_shape.nodes.add(create_node(x, y + h));
            }

            return path_shape;
        }

        public static GLib.GenericArray<Point?> sample_path_to_polygon(Shape shape, bool closed = true, int steps_per_segment = 16) {
            Shape path_shape = (shape.shape_type == ShapeType.PATH) ? shape : shape_to_path(shape);
            var poly = new GLib.GenericArray<Point?>();

            if (path_shape.nodes.length == 0) {
                return poly;
            }

            uint num_segs = closed ? path_shape.nodes.length : path_shape.nodes.length - 1;
            for (uint i = 0; i < num_segs; i++) {
                unowned PathNode n0 = path_shape.nodes[i];
                unowned PathNode n1 = path_shape.nodes[(i + 1) % path_shape.nodes.length];
                Point p0 = Point(n0.x, n0.y);
                Point p1 = n0.handle_out != null ? n0.handle_out : p0;
                Point p3 = Point(n1.x, n1.y);
                Point p2 = n1.handle_in != null ? n1.handle_in : p3;

                if (p1.equals(p0) && p2.equals(p3)) {
                    poly.add(p0);
                } else {
                    var sampled = sample_cubic_bezier(p0, p1, p2, p3, steps_per_segment);
                    for (uint s = 0; s < sampled.length - 1; s++) {
                        poly.add(sampled[s]);
                    }
                }
            }

            if (!closed && path_shape.nodes.length > 0) {
                unowned PathNode last = path_shape.nodes[path_shape.nodes.length - 1];
                poly.add(Point(last.x, last.y));
            }

            return poly;
        }

        public static bool point_in_polygon(double px, double py, GLib.GenericArray<Point?> poly) {
            bool inside = false;
            uint n = poly.length;
            if (n < 3) return false;

            Point p1 = poly[0];
            for (uint i = 1; i <= n; i++) {
                Point p2 = poly[i % n];
                if (py > Math.fmin(p1.y, p2.y)) {
                    if (py <= Math.fmax(p1.y, p2.y)) {
                        if (px <= Math.fmax(p1.x, p2.x)) {
                            double xinters = (p1.y != p2.y) ? (py - p1.y) * (p2.x - p1.x) / (p2.y - p1.y) + p1.x : p1.x;
                            if (p1.x == p2.x || px <= xinters) {
                                inside = !inside;
                            }
                        }
                    }
                }
                p1 = p2;
            }
            return inside;
        }

        public static double polygon_area(GLib.GenericArray<Point?> poly) {
            uint n = poly.length;
            if (n < 3) return 0.0;
            double area = 0.0;
            for (uint i = 0; i < n; i++) {
                uint j = (i + 1) % n;
                area += poly[i].x * poly[j].y;
                area -= poly[j].x * poly[i].y;
            }
            return area / 2.0;
        }

        public static bool line_segment_intersection(Point p1, Point p2, Point p3, Point p4,
                                                     out double ua, out double ub, out Point inter) {
            ua = 0.0; ub = 0.0; inter = Point(0, 0);
            double denom = (p4.y - p3.y) * (p2.x - p1.x) - (p4.x - p3.x) * (p2.y - p1.y);
            if (Math.fabs(denom) < 1e-9) {
                return false;
            }
            ua = ((p4.x - p3.x) * (p1.y - p3.y) - (p4.y - p3.y) * (p1.x - p3.x)) / denom;
            ub = ((p2.x - p1.x) * (p1.y - p3.y) - (p2.y - p1.y) * (p1.x - p3.x)) / denom;

            if (ua >= 0.0 && ua <= 1.0 && ub >= 0.0 && ub <= 1.0) {
                inter = Point(p1.x + ua * (p2.x - p1.x), p1.y + ua * (p2.y - p1.y));
                return true;
            }
            return false;
        }

        private class PolyVertex {
            public double x;
            public double y;
            public PolyVertex? next = null;
            public PolyVertex? prev = null;
            public PolyVertex? neighbor = null;
            public bool is_intersection = false;
            public bool entry = false;
            public bool visited = false;
            public double alpha = 0.0;

            public PolyVertex(double x, double y, bool is_inter = false) {
                this.x = x;
                this.y = y;
                this.is_intersection = is_inter;
            }
        }

        private static PolyVertex build_vertex_list(GLib.GenericArray<Point?> poly) {
            PolyVertex? head = null;
            PolyVertex? prev = null;
            for (uint i = 0; i < poly.length; i++) {
                var v = new PolyVertex(poly[i].x, poly[i].y);
                if (head == null) head = v;
                if (prev != null) {
                    prev.next = v;
                    v.prev = prev;
                }
                prev = v;
            }
            if (head != null && prev != null) {
                prev.next = head;
                head.prev = prev;
            }
            return head;
        }

        private static void insert_intersection(PolyVertex head, PolyVertex inter_v, PolyVertex start_v, double alpha) {
            inter_v.alpha = alpha;
            PolyVertex curr = start_v;
            while (curr.next != head && curr.next.is_intersection && curr.next.alpha < alpha) {
                curr = curr.next;
            }
            inter_v.next = curr.next;
            inter_v.prev = curr;
            curr.next.prev = inter_v;
            curr.next = inter_v;
        }

        public static GLib.GenericArray<Point?> polygon_boolean_operation(GLib.GenericArray<Point?> in_poly_a,
                                                                         GLib.GenericArray<Point?> in_poly_b,
                                                                         string operation = "union") {
            if (in_poly_a.length < 3 || in_poly_b.length < 3) {
                if (operation == "union" || operation == "difference") {
                    var ret = new GLib.GenericArray<Point?>();
                    for (uint i = 0; i < in_poly_a.length; i++) ret.add(in_poly_a[i]);
                    return ret;
                }
                return new GLib.GenericArray<Point?>();
            }

            var poly_a = new GLib.GenericArray<Point?>();
            for (uint i = 0; i < in_poly_a.length; i++) poly_a.add(in_poly_a[i]);
            var poly_b = new GLib.GenericArray<Point?>();
            for (uint i = 0; i < in_poly_b.length; i++) poly_b.add(in_poly_b[i]);

            // Ensure CCW orientation in screen space
            if (polygon_area(poly_a) > 0) {
                var rev = new GLib.GenericArray<Point?>();
                for (int i = (int) poly_a.length - 1; i >= 0; i--) rev.add(poly_a[i]);
                poly_a = rev;
            }
            if (polygon_area(poly_b) > 0) {
                var rev = new GLib.GenericArray<Point?>();
                for (int i = (int) poly_b.length - 1; i >= 0; i--) rev.add(poly_b[i]);
                poly_b = rev;
            }

            PolyVertex head_a = build_vertex_list(poly_a);
            PolyVertex head_b = build_vertex_list(poly_b);

            // 1. Find all intersections
            PolyVertex curr_a = head_a;
            int intersections_found = 0;
            while (true) {
                PolyVertex next_a = curr_a.next;
                Point p1 = Point(curr_a.x, curr_a.y);
                Point p2 = Point(next_a.x, next_a.y);

                PolyVertex curr_b = head_b;
                while (true) {
                    PolyVertex next_b = curr_b.next;
                    Point p3 = Point(curr_b.x, curr_b.y);
                    Point p4 = Point(next_b.x, next_b.y);

                    double ua, ub;
                    Point inter;
                    if (line_segment_intersection(p1, p2, p3, p4, out ua, out ub, out inter)) {
                        if (1e-6 < ua && ua < 1.0 - 1e-6 && 1e-6 < ub && ub < 1.0 - 1e-6) {
                            var va = new PolyVertex(inter.x, inter.y, true);
                            var vb = new PolyVertex(inter.x, inter.y, true);
                            va.neighbor = vb;
                            vb.neighbor = va;
                            insert_intersection(head_a, va, curr_a, ua);
                            insert_intersection(head_b, vb, curr_b, ub);
                            intersections_found++;
                        }
                    }

                    curr_b = next_b;
                    if (curr_b == head_b) break;
                }

                curr_a = next_a;
                if (curr_a == head_a) break;
            }

            // Non-intersecting cases
            if (intersections_found == 0) {
                bool a_in_b = point_in_polygon(poly_a[0].x, poly_a[0].y, poly_b);
                bool b_in_a = point_in_polygon(poly_b[0].x, poly_b[0].y, poly_a);

                if (operation == "union") {
                    if (a_in_b) return poly_b;
                    if (b_in_a) return poly_a;
                    var combined = new GLib.GenericArray<Point?>();
                    for (uint i = 0; i < poly_a.length; i++) combined.add(poly_a[i]);
                    for (uint i = 0; i < poly_b.length; i++) combined.add(poly_b[i]);
                    return combined;
                } else if (operation == "intersection") {
                    if (a_in_b) return poly_a;
                    if (b_in_a) return poly_b;
                    return new GLib.GenericArray<Point?>();
                } else if (operation == "difference") {
                    if (a_in_b) return new GLib.GenericArray<Point?>();
                    return poly_a;
                } else if (operation == "exclusion") {
                    var combined = new GLib.GenericArray<Point?>();
                    for (uint i = 0; i < poly_a.length; i++) combined.add(poly_a[i]);
                    for (uint i = 0; i < poly_b.length; i++) combined.add(poly_b[i]);
                    return combined;
                }
            }

            // 2. Mark entry/exit flags
            curr_a = head_a;
            bool inside = point_in_polygon(curr_a.x, curr_a.y, poly_b);
            while (true) {
                if (curr_a.is_intersection) {
                    curr_a.entry = !inside;
                    inside = !inside;
                }
                curr_a = curr_a.next;
                if (curr_a == head_a) break;
            }

            PolyVertex curr_b = head_b;
            inside = point_in_polygon(curr_b.x, curr_b.y, poly_a);
            while (true) {
                if (curr_b.is_intersection) {
                    curr_b.entry = !inside;
                    inside = !inside;
                }
                curr_b = curr_b.next;
                if (curr_b == head_b) break;
            }

            // 3. Construct resulting polygon rings
            var result_polys = new GLib.GenericArray<GLib.GenericArray<Point?>>();

            if (operation == "union" || operation == "intersection" || operation == "difference") {
                curr_a = head_a;
                while (true) {
                    bool can_start = curr_a.is_intersection && !curr_a.visited;
                    if (operation == "union") {
                        can_start = can_start && (!curr_a.entry);
                    } else if (operation == "intersection") {
                        can_start = can_start && curr_a.entry;
                    } else if (operation == "difference") {
                        can_start = can_start && (!curr_a.entry);
                    }

                    if (can_start) {
                        var ring = new GLib.GenericArray<Point?>();
                        PolyVertex v = curr_a;
                        int loop_limit = 0;
                        while (loop_limit++ < 2000) {
                            v.visited = true;
                            ring.add(Point(v.x, v.y));
                            if (operation == "union" || operation == "intersection") {
                                v = v.next;
                                while (!v.is_intersection) {
                                    ring.add(Point(v.x, v.y));
                                    v = v.next;
                                }
                                ring.add(Point(v.x, v.y));
                                v.visited = true;
                                v = v.neighbor;
                                v.visited = true;
                                v = v.next;
                                while (!v.is_intersection) {
                                    ring.add(Point(v.x, v.y));
                                    v = v.next;
                                }
                                v.visited = true;
                                v = v.neighbor;
                            } else if (operation == "difference") {
                                v = v.next;
                                while (!v.is_intersection) {
                                    ring.add(Point(v.x, v.y));
                                    v = v.next;
                                }
                                ring.add(Point(v.x, v.y));
                                v.visited = true;
                                v = v.neighbor;
                                v.visited = true;
                                v = v.prev;
                                while (!v.is_intersection) {
                                    ring.add(Point(v.x, v.y));
                                    v = v.prev;
                                }
                                v.visited = true;
                                v = v.neighbor;
                            }

                            if (v == curr_a || (v.neighbor != null && v.neighbor == curr_a)) {
                                break;
                            }
                        }

                        var cleaned = new GLib.GenericArray<Point?>();
                        for (uint r = 0; r < ring.length; r++) {
                            Point pt = ring[r];
                            if (cleaned.length == 0 ||
                                (Math.fabs(pt.x - cleaned[cleaned.length - 1].x) > 1e-4 ||
                                 Math.fabs(pt.y - cleaned[cleaned.length - 1].y) > 1e-4)) {
                                cleaned.add(pt);
                            }
                        }
                        if (cleaned.length >= 3) {
                            result_polys.add(cleaned);
                        }
                    }

                    curr_a = curr_a.next;
                    if (curr_a == head_a) break;
                }
            } else if (operation == "exclusion") {
                var diff_ab = polygon_boolean_operation(poly_a, poly_b, "difference");
                var diff_ba = polygon_boolean_operation(poly_b, poly_a, "difference");
                var ret = new GLib.GenericArray<Point?>();
                for (uint i = 0; i < diff_ab.length; i++) ret.add(diff_ab[i]);
                for (uint i = 0; i < diff_ba.length; i++) ret.add(diff_ba[i]);
                return ret;
            }

            if (result_polys.length == 0) {
                return (operation == "union" || operation == "difference") ? poly_a : new GLib.GenericArray<Point?>();
            }

            if (result_polys.length == 1) {
                return result_polys[0];
            }

            var merged = new GLib.GenericArray<Point?>();
            for (uint i = 0; i < result_polys.length; i++) {
                for (uint j = 0; j < result_polys[i].length; j++) {
                    merged.add(result_polys[i][j]);
                }
            }
            return merged;
        }

        public static Shape? boolean_operation_shapes(GLib.GenericArray<Shape> shapes, string operation = "union") {
            if (shapes.length < 2) return null;

            unowned Shape b = shapes[0];
            Color base_color = b.color;
            Color base_stroke = b.stroke_color;
            double base_stroke_width = b.stroke_width;
            bool base_has_stroke = b.has_stroke;

            var polys = new GLib.GenericArray<GLib.GenericArray<Point?>>();
            for (uint i = 0; i < shapes.length; i++) {
                polys.add(sample_path_to_polygon(shapes[i], true, 24));
            }

            var current_poly = polys[0];
            for (uint i = 1; i < polys.length; i++) {
                current_poly = polygon_boolean_operation(current_poly, polys[i], operation);
            }

            if (current_poly.length < 3) {
                current_poly = new GLib.GenericArray<Point?>();
                current_poly.add(Point(b.x, b.y));
                current_poly.add(Point(b.x + b.w, b.y));
                current_poly.add(Point(b.x + b.w, b.y + b.h));
                current_poly.add(Point(b.x, b.y + b.h));
            }

            var path_shape = new Shape(ShapeType.PATH);
            string op_title = operation.substring(0, 1).up() + operation.substring(1);
            if (operation == "difference") op_title = "Subtract";
            else if (operation == "intersection") op_title = "Intersect";
            else if (operation == "exclusion") op_title = "Exclude";
            path_shape.name = op_title + " Path";
            path_shape.color = base_color;
            path_shape.fill_visible = b.fill_visible;
            path_shape.stroke_color = base_stroke;
            path_shape.stroke_width = base_stroke_width;
            path_shape.has_stroke = base_has_stroke;
            path_shape.closed = true;

            for (uint i = 0; i < current_poly.length; i++) {
                path_shape.nodes.add(create_node(current_poly[i].x, current_poly[i].y, null, null, NodeType.CORNER));
            }

            path_recalculate_bounds(path_shape);
            return path_shape;
        }
    }
}
