/* Svg.vala - Readable SVG 1.1 / SVG 2 markup generation for vector shapes */

namespace Nova {

    public class Svg {

        public static GLib.GenericArray<Shape> collect_export_shapes(GLib.GenericArray<Shape> document_shapes,
                                                                    GLib.GenericArray<Shape> selected) {
            var selected_ids = new GLib.HashTable<string, bool>(GLib.str_hash, GLib.str_equal);
            var child_ids = new GLib.HashTable<string, bool>(GLib.str_hash, GLib.str_equal);

            for (uint i = 0; i < selected.length; i++) {
                selected_ids.insert(selected[i].id, true);
                if (selected[i].shape_type == ShapeType.FRAME) {
                    var children = Geometry.get_frame_children(selected[i], document_shapes);
                    for (uint c = 0; c < children.length; c++) {
                        child_ids.insert(children[c].id, true);
                    }
                }
            }

            var result = new GLib.GenericArray<Shape>();
            for (uint i = 0; i < document_shapes.length; i++) {
                unowned Shape s = document_shapes[i];
                if (s.visible && (selected_ids.contains(s.id) || child_ids.contains(s.id))) {
                    result.add(s);
                }
            }
            return result;
        }

        public static Rect export_bounds(GLib.GenericArray<Shape> shapes) {
            if (shapes.length == 0) {
                return Rect(0.0, 0.0, 1.0, 1.0);
            }
            return Geometry.bounding_box(shapes);
        }

        public static string export_basename(GLib.GenericArray<Shape> shapes) {
            var frames = new GLib.GenericArray<Shape>();
            for (uint i = 0; i < shapes.length; i++) {
                if (shapes[i].shape_type == ShapeType.FRAME) {
                    frames.add(shapes[i]);
                }
            }
            if (frames.length == 1) {
                return safe_name(frames[0].name.length > 0 ? frames[0].name : "Frame");
            }
            if (shapes.length == 1) {
                return safe_name(shapes[0].name.length > 0 ? shapes[0].name : shapes[0].shape_type.to_string());
            }
            return "Selection";
        }

        public static string shapes_to_svg(GLib.GenericArray<Shape> shapes) {
            Rect bounds = export_bounds(shapes);
            double origin_x = bounds.x;
            double origin_y = bounds.y;
            double width = bounds.width;
            double height = bounds.height;

            var used_ids = new GLib.HashTable<string, bool>(GLib.str_hash, GLib.str_equal);
            var nested = nested_child_ids(shapes);

            var sb = new GLib.StringBuilder();
            sb.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
            sb.append("<!-- Nova export: SVG 1.1 markup, also valid as SVG 2 -->\n");
            sb.append("<svg xmlns=\"http://www.w3.org/2000/svg\" ");
            sb.append("xmlns:xlink=\"http://www.w3.org/1999/xlink\" ");
            sb.append("version=\"1.1\" ");
            sb.append("width=\"%s\" height=\"%s\" ".printf(num(width), num(height)));
            sb.append("viewBox=\"0 0 %s %s\">\n".printf(num(width), num(height)));

            for (uint i = 0; i < shapes.length; i++) {
                unowned Shape s = shapes[i];
                if (nested.contains(s.id)) continue;
                emit_shape(sb, s, shapes, origin_x, origin_y, used_ids, 1);
            }

            sb.append("</svg>\n");
            return sb.str;
        }

        private static GLib.HashTable<string, bool> nested_child_ids(GLib.GenericArray<Shape> shapes) {
            var nested = new GLib.HashTable<string, bool>(GLib.str_hash, GLib.str_equal);
            for (uint i = 0; i < shapes.length; i++) {
                if (shapes[i].shape_type != ShapeType.FRAME) continue;
                var children = Geometry.get_frame_children(shapes[i], shapes);
                for (uint c = 0; c < children.length; c++) {
                    nested.insert(children[c].id, true);
                }
            }
            return nested;
        }

        private static void emit_shape(GLib.StringBuilder sb, Shape shape, GLib.GenericArray<Shape> all_shapes,
                                       double origin_x, double origin_y, GLib.HashTable<string, bool> used_ids, int depth) {
            if (!shape.visible) return;
            string pad = string.nfill(depth * 2, ' ');
            double rotation = shape.rotation % 360.0;
            bool has_rotation = rotation != 0.0;

            if (has_rotation) {
                double center_x = shape.x + shape.w / 2.0 - origin_x;
                double center_y = shape.y + shape.h / 2.0 - origin_y;
                sb.append("%s<g transform=\"rotate(%s %s %s)\">\n".printf(pad, num(rotation), num(center_x), num(center_y)));
                depth++;
                pad = string.nfill(depth * 2, ' ');
            }

            if (shape.shape_type == ShapeType.GROUP) {
                emit_group(sb, shape, origin_x, origin_y, used_ids, depth);
            } else if (shape.shape_type == ShapeType.FRAME) {
                emit_frame(sb, shape, all_shapes, origin_x, origin_y, used_ids, depth);
            } else {
                emit_leaf(sb, shape, origin_x, origin_y, used_ids, depth, true);
            }

            if (has_rotation) {
                sb.append("%s</g>\n".printf(string.nfill((depth - 1) * 2, ' ')));
            }
        }

        private static void emit_group(GLib.StringBuilder sb, Shape shape, double origin_x, double origin_y,
                                       GLib.HashTable<string, bool> used_ids, int depth) {
            string pad = string.nfill(depth * 2, ' ');
            string element_id = xml_id(shape.name.length > 0 ? shape.name : "Group", used_ids);
            string opacity = opacity_attr(shape);
            sb.append("%s<g id=\"%s\"%s>\n".printf(pad, element_id, opacity));

            for (uint i = 0; i < shape.children.length; i++) {
                emit_shape(sb, shape.children[i], new GLib.GenericArray<Shape>(), origin_x, origin_y, used_ids, depth + 1);
            }
            sb.append("%s</g>\n".printf(pad));
        }

        private static void emit_frame(GLib.StringBuilder sb, Shape shape, GLib.GenericArray<Shape> all_shapes,
                                       double origin_x, double origin_y, GLib.HashTable<string, bool> used_ids, int depth) {
            string pad = string.nfill(depth * 2, ' ');
            string element_id = xml_id(shape.name.length > 0 ? shape.name : "Frame", used_ids);
            sb.append("%s<g id=\"%s\">\n".printf(pad, element_id));

            emit_leaf(sb, shape, origin_x, origin_y, used_ids, depth + 1, false);

            var children = Geometry.get_frame_children(shape, all_shapes);
            for (uint i = 0; i < children.length; i++) {
                emit_shape(sb, children[i], all_shapes, origin_x, origin_y, used_ids, depth + 1);
            }

            sb.append("%s</g>\n".printf(pad));
        }

        private static void emit_leaf(GLib.StringBuilder sb, Shape shape, double origin_x, double origin_y,
                                      GLib.HashTable<string, bool> used_ids, int depth, bool force_id) {
            string pad = string.nfill(depth * 2, ' ');
            string element_id = force_id ? xml_id(shape.name.length > 0 ? shape.name : shape.shape_type.to_string(), used_ids) : "";
            string id_attr = element_id.length > 0 ? " id=\"%s\"".printf(element_id) : "";

            string geometry, tag, extra;
            get_geometry(shape, origin_x, origin_y, out geometry, out tag, out extra);
            if (tag.length == 0) {
                sb.append("%s<!-- skipped %s -->\n".printf(pad, GLib.Markup.escape_text(shape.shape_type.to_string())));
                return;
            }

            string attrs = style_attrs(shape);
            string opacity = opacity_attr(shape);

            if (tag == "text") {
                emit_text(sb, shape, origin_x, origin_y, pad, id_attr, opacity);
                return;
            }
            if (tag == "image") {
                emit_image(sb, shape, origin_x, origin_y, pad, id_attr, opacity);
                return;
            }
            if (shape.shape_type == ShapeType.ARROW) {
                emit_arrow(sb, shape, origin_x, origin_y, pad, id_attr, opacity);
                return;
            }

            string open_tag = "%s<%s%s%s%s%s%s/>\n".printf(pad, tag, id_attr, geometry, attrs, opacity, extra);
            StrokeAlign align = shape.stroke_align;
            double stroke_width = shape.stroke_width;

            if (align == StrokeAlign.CENTER || stroke_width <= 0 || !shape.has_stroke) {
                sb.append(open_tag);
                return;
            }

            emit_aligned_stroke(sb, shape, tag, geometry, pad, id_attr, opacity, align, used_ids);
        }

        private static void emit_aligned_stroke(GLib.StringBuilder sb, Shape shape, string tag, string geometry,
                                                string pad, string id_attr, string opacity, StrokeAlign align,
                                                GLib.HashTable<string, bool> used_ids) {
            string fill = fill_attr(shape);
            string stroke = stroke_only_attrs(shape, true, false);

            if (align == StrokeAlign.INSIDE) {
                string clip_id = xml_id("clip", used_ids);
                sb.append("%s<g%s%s>\n".printf(pad, id_attr, opacity));
                sb.append("%s  <clipPath id=\"%s\"><%s%s/></clipPath>\n".printf(pad, clip_id, tag, geometry));
                sb.append("%s  <%s%s%s%s clip-path=\"url(#%s)\"/>\n".printf(pad, tag, geometry, fill, stroke, clip_id));
                sb.append("%s</g>\n".printf(pad));
            } else { // OUTSIDE
                sb.append("%s<g%s%s>\n".printf(pad, id_attr, opacity));
                sb.append("%s  <%s%s fill=\"none\"%s/>\n".printf(pad, tag, geometry, stroke));
                sb.append("%s  <%s%s%s/>\n".printf(pad, tag, geometry, fill));
                sb.append("%s</g>\n".printf(pad));
            }
        }

        private static void get_geometry(Shape shape, double origin_x, double origin_y,
                                         out string geometry, out string tag, out string extra) {
            geometry = "";
            tag = "";
            extra = "";

            double x = shape.x - origin_x;
            double y = shape.y - origin_y;
            double width = shape.w;
            double height = shape.h;

            switch (shape.shape_type) {
                case ShapeType.RECT:
                case ShapeType.FRAME:
                case ShapeType.IMAGE:
                    if (shape.shape_type == ShapeType.IMAGE) {
                        geometry = " x=\"%s\" y=\"%s\" width=\"%s\" height=\"%s\"".printf(num(x), num(y), num(width), num(height));
                        tag = "image";
                        return;
                    }
                    CornerRadii radii = Geometry.get_corner_radii(shape);
                    if (radii.is_zero()) {
                        geometry = " x=\"%s\" y=\"%s\" width=\"%s\" height=\"%s\"".printf(num(x), num(y), num(width), num(height));
                        tag = "rect";
                        return;
                    }
                    if (radii.is_uniform()) {
                        geometry = " x=\"%s\" y=\"%s\" width=\"%s\" height=\"%s\" rx=\"%s\"".printf(
                            num(x), num(y), num(width), num(height), num(radii.tl));
                        tag = "rect";
                        return;
                    }
                    string path_d = rounded_rect_path(x, y, width, height, radii);
                    geometry = " d=\"%s\"".printf(path_d);
                    tag = "path";
                    return;

                case ShapeType.ELLIPSE:
                    geometry = " cx=\"%s\" cy=\"%s\" rx=\"%s\" ry=\"%s\"".printf(
                        num(x + width / 2.0), num(y + height / 2.0), num(width / 2.0), num(height / 2.0));
                    tag = "ellipse";
                    return;

                case ShapeType.POLYGON:
                    geometry = " points=\"%s\"".printf(polygon_points(shape, origin_x, origin_y));
                    tag = "polygon";
                    return;

                case ShapeType.STAR:
                    geometry = " points=\"%s\"".printf(star_points(shape, origin_x, origin_y));
                    tag = "polygon";
                    return;

                case ShapeType.LINE:
                    geometry = " x1=\"%s\" y1=\"%s\" x2=\"%s\" y2=\"%s\"".printf(num(x), num(y), num(x + width), num(y + height));
                    tag = "line";
                    return;

                case ShapeType.ARROW:
                    tag = "line";
                    return;

                case ShapeType.PENCIL:
                    geometry = " d=\"%s\"".printf(pencil_path(shape, origin_x, origin_y));
                    tag = "path";
                    return;

                case ShapeType.PATH:
                    string data = vector_path(shape, origin_x, origin_y);
                    if (data.length == 0) return;
                    geometry = " d=\"%s\"".printf(data);
                    tag = "path";
                    return;

                case ShapeType.TEXT:
                    tag = "text";
                    return;

                default:
                    return;
            }
        }

        private static string style_attrs(Shape shape) {
            if (shape.shape_type == ShapeType.LINE || shape.shape_type == ShapeType.ARROW || shape.shape_type == ShapeType.PENCIL) {
                return " fill=\"none\"" + stroke_only_attrs(shape, false, true);
            }
            string fill = fill_attr(shape);
            if (shape.has_stroke && shape.stroke_width > 0 && shape.stroke_align == StrokeAlign.CENTER) {
                return fill + stroke_only_attrs(shape, false, false);
            }
            if (shape.shape_type == ShapeType.FRAME && (!shape.has_stroke || shape.stroke_width <= 0)) {
                return fill + " stroke=\"#BFBFCC\" stroke-width=\"1\"";
            }
            return fill;
        }

        private static string fill_attr(Shape shape) {
            return " fill=\"%s\"".printf(shape.color.to_hex());
        }

        private static string stroke_only_attrs(Shape shape, bool double_width, bool fallback_color) {
            Color color = shape.has_stroke ? shape.stroke_color : (fallback_color ? Color.rgb(0.2, 0.2, 0.2) : Color());
            if (!shape.has_stroke && !fallback_color) {
                return "";
            }
            double width = shape.stroke_width > 0 ? shape.stroke_width : (fallback_color ? 2.0 : 0.0);
            if (width <= 0.0 && !fallback_color) {
                return "";
            }
            if (width <= 0.0) width = 2.0;
            if (double_width) width *= 2.0;

            var sb = new GLib.StringBuilder();
            sb.append(" stroke=\"%s\"".printf(color.to_hex()));
            sb.append(" stroke-width=\"%s\"".printf(num(width)));

            if (shape.stroke_cap == StrokeCap.ROUND) {
                sb.append(" stroke-linecap=\"round\"");
            } else if (shape.stroke_cap == StrokeCap.SQUARE) {
                sb.append(" stroke-linecap=\"square\"");
            }

            if (shape.stroke_join == StrokeJoin.ROUND) {
                sb.append(" stroke-linejoin=\"round\"");
            } else if (shape.stroke_join == StrokeJoin.BEVEL) {
                sb.append(" stroke-linejoin=\"bevel\"");
            }

            if (shape.stroke_dash == StrokeDash.DASHED) {
                sb.append(" stroke-dasharray=\"%s %s\"".printf(num(width * 3.0), num(width * 2.0)));
            } else if (shape.stroke_dash == StrokeDash.DOTTED) {
                sb.append(" stroke-dasharray=\"%s %s\"".printf(num(width), num(width * 1.5)));
            }

            return sb.str;
        }

        private static string opacity_attr(Shape shape) {
            if (shape.opacity >= 0.999) return "";
            return " opacity=\"%s\"".printf(num(Math.fmax(0.0, Math.fmin(1.0, shape.opacity))));
        }

        private static void emit_text(GLib.StringBuilder sb, Shape shape, double origin_x, double origin_y,
                                      string pad, string id_attr, string opacity) {
            double x = shape.x - origin_x;
            double y = shape.y - origin_y;
            double width = shape.w;
            double size = Math.fmax(6.0, shape.font_size);
            string family = GLib.Markup.escape_text(shape.font_family);
            string fw = shape.font_weight.down();
            string weight = (fw == "bold" || fw == "semibold" || fw == "700" || fw == "600") ? "700" : "400";
            string style = (shape.font_slant.down() == "italic") ? "italic" : "normal";

            string anchor = "start";
            double text_x = x;
            if (shape.text_align.down() == "center") {
                anchor = "middle";
                text_x = x + width / 2.0;
            } else if (shape.text_align.down() == "right") {
                anchor = "end";
                text_x = x + width;
            }

            string fill = shape.color.to_hex();
            string[] lines = shape.text.split("\n");

            string opening = "%s<text%s x=\"%s\" y=\"%s\" fill=\"%s\" font-family=\"%s\" font-size=\"%s\" font-weight=\"%s\" font-style=\"%s\" text-anchor=\"%s\"%s>".printf(
                pad, id_attr, num(text_x), num(y + size), fill, family, num(size), weight, style, anchor, opacity);

            if (lines.length == 1) {
                sb.append("%s%s</text>\n".printf(opening, GLib.Markup.escape_text(lines[0])));
                return;
            }

            sb.append("%s\n".printf(opening));
            double line_height = Math.fmax(0.8, shape.line_height);
            for (int i = 0; i < lines.length; i++) {
                double dy = (i == 0) ? 0.0 : size * line_height;
                sb.append("%s  <tspan x=\"%s\" dy=\"%s\">%s</tspan>\n".printf(pad, num(text_x), num(dy), GLib.Markup.escape_text(lines[i])));
            }
            sb.append("%s</text>\n".printf(pad));
        }

        private static void emit_image(GLib.StringBuilder sb, Shape shape, double origin_x, double origin_y,
                                       string pad, string id_attr, string opacity) {
            double x = shape.x - origin_x;
            double y = shape.y - origin_y;
            double width = shape.w;
            double height = shape.h;
            string href = shape.image_path != null ? shape.image_path : "";

            if (href.length > 0 && GLib.FileUtils.test(href, GLib.FileTest.EXISTS)) {
                string esc_href = GLib.Markup.escape_text(href);
                sb.append("%s<image%s x=\"%s\" y=\"%s\" width=\"%s\" height=\"%s\" href=\"%s\" xlink:href=\"%s\"%s/>\n".printf(
                    pad, id_attr, num(x), num(y), num(width), num(height), esc_href, esc_href, opacity));
            } else {
                sb.append("%s<rect%s x=\"%s\" y=\"%s\" width=\"%s\" height=\"%s\" fill=\"#E6E6EB\"%s/>\n".printf(
                    pad, id_attr, num(x), num(y), num(width), num(height), opacity));
            }
        }

        private static void emit_arrow(GLib.StringBuilder sb, Shape shape, double origin_x, double origin_y,
                                       string pad, string id_attr, string opacity) {
            double x1 = shape.x - origin_x;
            double y1 = shape.y - origin_y;
            double x2 = x1 + shape.w;
            double y2 = y1 + shape.h;

            string stroke = stroke_only_attrs(shape, false, true);
            double stroke_width = Math.fmax(1.0, shape.stroke_width > 0 ? shape.stroke_width : 2.0);
            double angle = Math.atan2(y2 - y1, x2 - x1);
            double head = Math.fmax(12.0, stroke_width * 3.5);

            double left_x = x2 - head * Math.cos(angle - Math.PI / 6.0);
            double left_y = y2 - head * Math.sin(angle - Math.PI / 6.0);
            double right_x = x2 - head * Math.cos(angle + Math.PI / 6.0);
            double right_y = y2 - head * Math.sin(angle + Math.PI / 6.0);

            Color color = shape.has_stroke ? shape.stroke_color : shape.color;

            sb.append("%s<line%s x1=\"%s\" y1=\"%s\" x2=\"%s\" y2=\"%s\"%s%s/>\n".printf(
                pad, id_attr, num(x1), num(y1), num(x2), num(y2), stroke, opacity));
            sb.append("%s<polygon points=\"%s,%s %s,%s %s,%s\" fill=\"%s\"%s/>\n".printf(
                pad, num(x2), num(y2), num(left_x), num(left_y), num(right_x), num(right_y), color.to_hex(), opacity));
        }

        private static string rounded_rect_path(double x, double y, double width, double height, CornerRadii radii) {
            double tl = radii.tl;
            double tr = radii.tr;
            double br = radii.br;
            double bl = radii.bl;

            var sb = new GLib.StringBuilder();
            sb.append("M %s %s ".printf(num(x + tl), num(y)));
            sb.append("H %s ".printf(num(x + width - tr)));
            if (tr > 0) sb.append("A %s %s 0 0 1 %s %s ".printf(num(tr), num(tr), num(x + width), num(y + tr)));
            sb.append("V %s ".printf(num(y + height - br)));
            if (br > 0) sb.append("A %s %s 0 0 1 %s %s ".printf(num(br), num(br), num(x + width - br), num(y + height)));
            sb.append("H %s ".printf(num(x + bl)));
            if (bl > 0) sb.append("A %s %s 0 0 1 %s %s ".printf(num(bl), num(bl), num(x), num(y + height - bl)));
            sb.append("V %s ".printf(num(y + tl)));
            if (tl > 0) sb.append("A %s %s 0 0 1 %s %s ".printf(num(tl), num(tl), num(x + tl), num(y)));
            sb.append("Z");
            return sb.str;
        }

        private static string polygon_points(Shape shape, double origin_x, double origin_y) {
            int sides = int.max(3, shape.sides);
            double cx = shape.x + shape.w / 2.0 - origin_x;
            double cy = shape.y + shape.h / 2.0 - origin_y;
            double rx = shape.w / 2.0;
            double ry = shape.h / 2.0;

            var sb = new GLib.StringBuilder();
            for (int i = 0; i < sides; i++) {
                double angle = -Math.PI / 2.0 + (2.0 * Math.PI * i) / sides;
                if (i > 0) sb.append(" ");
                sb.append("%s,%s".printf(num(cx + rx * Math.cos(angle)), num(cy + ry * Math.sin(angle))));
            }
            return sb.str;
        }

        private static string star_points(Shape shape, double origin_x, double origin_y) {
            int pts_count = int.max(3, shape.points_count);
            double ratio = Math.fmax(0.1, Math.fmin(0.9, shape.inner_ratio));
            double cx = shape.x + shape.w / 2.0 - origin_x;
            double cy = shape.y + shape.h / 2.0 - origin_y;
            double rx = shape.w / 2.0;
            double ry = shape.h / 2.0;
            int total = pts_count * 2;

            var sb = new GLib.StringBuilder();
            for (int i = 0; i < total; i++) {
                double angle = -Math.PI / 2.0 + (Math.PI * i) / pts_count;
                double scale = (i % 2 == 0) ? 1.0 : ratio;
                if (i > 0) sb.append(" ");
                sb.append("%s,%s".printf(num(cx + rx * scale * Math.cos(angle)), num(cy + ry * scale * Math.sin(angle))));
            }
            return sb.str;
        }

        private static string pencil_path(Shape shape, double origin_x, double origin_y) {
            double x = shape.x - origin_x;
            double y = shape.y - origin_y;
            if (shape.points.length == 0) {
                return "M %s %s h %s v %s h -%s Z".printf(num(x), num(y), num(shape.w), num(shape.h), num(shape.w));
            }

            var sb = new GLib.StringBuilder();
            sb.append("M %s %s ".printf(num(x + shape.points[0].x), num(y + shape.points[0].y)));
            for (uint i = 1; i < shape.points.length; i++) {
                sb.append("L %s %s ".printf(num(x + shape.points[i].x), num(y + shape.points[i].y)));
            }
            return sb.str.strip();
        }

        private static string vector_path(Shape shape, double origin_x, double origin_y) {
            if (shape.nodes.length == 0) return "";
            var sb = new GLib.StringBuilder();

            unowned PathNode start = shape.nodes[0];
            sb.append("M %s %s ".printf(num(start.x - origin_x), num(start.y - origin_y)));

            uint count = shape.closed ? shape.nodes.length : shape.nodes.length - 1;
            for (uint i = 0; i < count; i++) {
                unowned PathNode first = shape.nodes[i];
                unowned PathNode second = shape.nodes[(i + 1) % shape.nodes.length];
                Point p0 = Point(first.x, first.y);
                Point p1 = first.handle_out != null ? first.handle_out : p0;
                Point p3 = Point(second.x, second.y);
                Point p2 = second.handle_in != null ? second.handle_in : p3;

                if (p1.equals(p0) && p2.equals(p3)) {
                    sb.append("L %s %s ".printf(num(p3.x - origin_x), num(p3.y - origin_y)));
                } else {
                    sb.append("C %s %s %s %s %s %s ".printf(
                        num(p1.x - origin_x), num(p1.y - origin_y),
                        num(p2.x - origin_x), num(p2.y - origin_y),
                        num(p3.x - origin_x), num(p3.y - origin_y)));
                }
            }

            if (shape.closed && shape.nodes.length >= 3) {
                sb.append("Z");
            }
            return sb.str.strip();
        }

        public static string num(double val) {
            double rounded = Math.round(val * 100.0) / 100.0;
            if (rounded == (int) rounded) {
                return "%d".printf((int) rounded);
            }
            string s = "%.2f".printf(rounded);
            while (s.has_suffix("0")) s = s.substring(0, s.length - 1);
            if (s.has_suffix(".")) s = s.substring(0, s.length - 1);
            return s;
        }

        private static string safe_name(string name) {
            string cleaned = name.strip();
            var sb = new GLib.StringBuilder();
            for (int i = 0; i < cleaned.length; i++) {
                unichar c = cleaned.get_char(i);
                if (c == '\\' || c == '/' || c == ':' || c == '*' || c == '?' || c == '"' || c == '<' || c == '>' || c == '|') {
                    continue;
                }
                sb.append_unichar(c);
            }
            return sb.len > 0 ? sb.str : "Export";
        }

        private static string xml_id(string name, GLib.HashTable<string, bool> used) {
            var sb = new GLib.StringBuilder();
            for (int i = 0; i < name.length; i++) {
                unichar c = name.get_char(i);
                if (c.isalnum() || c == '_' || c == '-') {
                    sb.append_unichar(c);
                } else {
                    sb.append_c('-');
                }
            }
            string slug = sb.str.strip();
            while (slug.has_prefix("-")) slug = slug.substring(1);
            while (slug.has_suffix("-")) slug = slug.substring(0, slug.length - 1);
            if (slug.length == 0) slug = "shape";
            if (!slug.get_char(0).isalpha() && slug.get_char(0) != '_') {
                slug = "s-" + slug;
            }

            string base_slug = slug;
            int idx = 2;
            while (used.contains(slug)) {
                slug = "%s-%d".printf(base_slug, idx++);
            }
            used.insert(slug, true);
            return slug;
        }
    }
}
