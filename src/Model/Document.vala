/* Document.vala - Scene graph, undo/redo history, frame containment, and alignment operations */

namespace Nova {

    public enum LayerPlace {
        BEFORE,
        AFTER,
        INTO
    }

    public class Document : GLib.Object {
        public GLib.GenericArray<Shape> shapes { get; private set; }
        public UndoStack undo_stack { get; private set; }
        public Clipboard clipboard { get; private set; }

        public signal void changed();

        private GLib.HashTable<string, GLib.GenericArray<Shape>>? frame_index = null;

        public Document() {
            this.shapes = new GLib.GenericArray<Shape>();
            this.undo_stack = new UndoStack();
            this.clipboard = new Clipboard();
            this.changed.connect(() => { frame_index = null; });
        }

        public void checkpoint() {
            undo_stack.record(shapes);
        }

        public void note_changed() {
            changed();
        }

        public void discard_checkpoint() {
            undo_stack.discard();
        }

        public bool can_undo() {
            return undo_stack.can_undo();
        }

        public bool can_redo() {
            return undo_stack.can_redo();
        }

        public bool undo() {
            var restored = undo_stack.undo(shapes);
            if (restored != null) {
                shapes.remove_range(0, shapes.length);
                for (uint i = 0; i < restored.length; i++) {
                    shapes.add(restored[i]);
                }
                changed();
                return true;
            }
            return false;
        }

        public bool redo() {
            var restored = undo_stack.redo(shapes);
            if (restored != null) {
                shapes.remove_range(0, shapes.length);
                for (uint i = 0; i < restored.length; i++) {
                    shapes.add(restored[i]);
                }
                changed();
                return true;
            }
            return false;
        }

        public GLib.GenericArray<Shape> get_frame_children(Shape frame) {
            if (frame_index == null) build_frame_index();
            var copy = new GLib.GenericArray<Shape>();
            var list = frame_index.lookup(frame.id);
            if (list == null) return copy;
            for (uint i = 0; i < list.length; i++) copy.add(list[i]);
            return copy;
        }

        private void build_frame_index() {
            frame_index = new GLib.HashTable<string, GLib.GenericArray<Shape>>(GLib.str_hash, GLib.str_equal);
            for (uint i = 0; i < shapes.length; i++) {
                if (shapes[i].shape_type != ShapeType.FRAME) continue;
                frame_index.insert(shapes[i].id, new GLib.GenericArray<Shape>());
            }
            for (uint i = 0; i < shapes.length; i++) {
                unowned Shape shape = shapes[i];
                if (shape.shape_type == ShapeType.FRAME) continue;
                if (shape.frame_id != null) {
                    var list = frame_index.lookup(shape.frame_id);
                    if (list != null) list.add(shape);
                    continue;
                }
                double cx = shape.x + shape.w / 2.0;
                double cy = shape.y + shape.h / 2.0;
                for (int f = (int) shapes.length - 1; f >= 0; f--) {
                    if (shapes[f].shape_type == ShapeType.FRAME && Geometry.is_point_in_frame(cx, cy, shapes[f])) {
                        frame_index.lookup(shapes[f].id).add(shape);
                        break;
                    }
                }
            }
        }

        public string next_shape_name(ShapeType type) {
            string base_name = Shape.default_name(type);
            int max_n = 0;
            highest_name_index(shapes, base_name, ref max_n);
            return "%s %d".printf(base_name, max_n + 1);
        }

        private static void highest_name_index(GLib.GenericArray<Shape> list, string base_name, ref int max_n) {
            for (uint i = 0; i < list.length; i++) {
                int n = name_index(list[i].name, base_name);
                if (n > max_n) max_n = n;
                if (list[i].children.length > 0) {
                    highest_name_index(list[i].children, base_name, ref max_n);
                }
            }
        }

        private static int name_index(string name, string base_name) {
            if (!name.has_prefix(base_name)) return 0;
            string rest = name.substring(base_name.length).strip();
            if (rest.length == 0) return 0;
            for (int i = 0; i < rest.length; i++) {
                if (!rest[i].isdigit()) return 0;
            }
            return int.parse(rest);
        }

        public Shape add_shape(Shape shape, bool record_undo = true) {
            string base_name = Shape.default_name(shape.shape_type);
            if (shape.name.length == 0 || shape.name == base_name) {
                shape.name = next_shape_name(shape.shape_type);
            }

            double nx, ny, nw, nh;
            Geometry.normalize_bounds(shape.x, shape.y, shape.w, shape.h, out nx, out ny, out nw, out nh);
            shape.x = nx;
            shape.y = ny;
            shape.w = nw;
            shape.h = nh;

            if (record_undo) {
                checkpoint();
            }

            // Auto-detect frame containment if not explicitly set
            if (shape.frame_id == null && shape.shape_type != ShapeType.FRAME) {
                for (int i = (int) shapes.length - 1; i >= 0; i--) {
                    if (shapes[i].shape_type == ShapeType.FRAME && Geometry.is_shape_in_frame(shape, shapes[i])) {
                        shape.frame_id = shapes[i].id;
                        break;
                    }
                }
            }

            if (shape.frame_id != null) {
                Shape? parent = find_shape_by_id(shape.frame_id);
                if (parent != null) {
                    var p_children = new GLib.GenericArray<Shape>();
                    for (uint c = 0; c < shapes.length; c++) {
                        if (shapes[c].frame_id == parent.id) {
                            p_children.add(shapes[c]);
                        }
                    }
                    if (p_children.length > 0) {
                        int last_idx = -1;
                        for (uint c = 0; c < p_children.length; c++) {
                            int idx = index_of(p_children[c]);
                            if (idx > last_idx) last_idx = idx;
                        }
                        shapes.insert(last_idx + 1, shape);
                    } else {
                        int p_idx = index_of(parent);
                        shapes.insert(p_idx + 1, shape);
                    }
                    changed();
                    return shape;
                }
            }

            shapes.add(shape);
            changed();
            return shape;
        }

        public void move_shape(Shape shape, double x, double y, bool record_undo = false, bool notify = true) {
            if (record_undo) {
                checkpoint();
            }
            if (!record_undo && x == shape.x && y == shape.y) return;
            if (shape.shape_type == ShapeType.FRAME) {
                x = Math.round(x);
                y = Math.round(y);
            }
            double dx = x - shape.x;
            double dy = y - shape.y;

            if (shape.shape_type == ShapeType.FRAME) {
                var children = get_frame_children(shape);
                shape.x = x;
                shape.y = y;
                for (uint i = 0; i < children.length; i++) {
                    unowned Shape child = children[i];
                    child.x += dx;
                    child.y += dy;
                    if (child.shape_type == ShapeType.GROUP) {
                        for (uint g = 0; g < child.children.length; g++) {
                            child.children[g].x += dx;
                            child.children[g].y += dy;
                        }
                    } else if (child.shape_type == ShapeType.PATH) {
                        for (uint n = 0; n < child.nodes.length; n++) {
                            child.nodes[n].x += dx;
                            child.nodes[n].y += dy;
                            if (child.nodes[n].handle_in != null) {
                                child.nodes[n].handle_in = Point(child.nodes[n].handle_in.x + dx, child.nodes[n].handle_in.y + dy);
                            }
                            if (child.nodes[n].handle_out != null) {
                                child.nodes[n].handle_out = Point(child.nodes[n].handle_out.x + dx, child.nodes[n].handle_out.y + dy);
                            }
                        }
                    }
                }
            } else if (shape.shape_type == ShapeType.GROUP) {
                shape.x = x;
                shape.y = y;
                for (uint i = 0; i < shape.children.length; i++) {
                    shape.children[i].x += dx;
                    shape.children[i].y += dy;
                }
            } else if (shape.shape_type == ShapeType.PATH) {
                shape.x = x;
                shape.y = y;
                for (uint n = 0; n < shape.nodes.length; n++) {
                    shape.nodes[n].x += dx;
                    shape.nodes[n].y += dy;
                    if (shape.nodes[n].handle_in != null) {
                        shape.nodes[n].handle_in = Point(shape.nodes[n].handle_in.x + dx, shape.nodes[n].handle_in.y + dy);
                    }
                    if (shape.nodes[n].handle_out != null) {
                        shape.nodes[n].handle_out = Point(shape.nodes[n].handle_out.x + dx, shape.nodes[n].handle_out.y + dy);
                    }
                }
                update_frame_containment(shape);
            } else {
                shape.x = x;
                shape.y = y;
                update_frame_containment(shape);
            }
            if (notify) changed();
        }

        public void resize_shape(Shape shape, double width, double height, bool record_undo = false) {
            place_shape(shape, shape.x, shape.y, width, height, record_undo);
        }

        public void place_shape(Shape shape, double x, double y, double width, double height, bool record_undo = false) {
            if (record_undo) {
                checkpoint();
            }
            if (shape.shape_type == ShapeType.FRAME) {
                x = Math.round(x);
                y = Math.round(y);
                width = Math.round(width);
                height = Math.round(height);
            }
            shape.x = x;
            shape.y = y;
            shape.w = Math.fmax(1.0, width);
            shape.h = Math.fmax(1.0, height);
            changed();
        }

        public void set_color(Shape shape, Color color, bool record_undo = true) {
            if (record_undo) checkpoint();
            shape.color = color;
            changed();
        }

        public void set_fill_visible(Shape shape, bool visible, bool record_undo = true) {
            if (record_undo) checkpoint();
            shape.fill_visible = visible;
            changed();
        }

        public void set_opacity(Shape shape, double opacity, bool record_undo = true) {
            if (record_undo) checkpoint();
            shape.opacity = Math.fmax(0.0, Math.fmin(1.0, opacity));
            changed();
        }

        public void set_rotation(Shape shape, double rotation, bool record_undo = true) {
            if (record_undo) checkpoint();
            double rot = rotation % 360.0;
            if (rot < 0) rot += 360.0;
            shape.rotation = rot;
            changed();
        }

        public void set_stroke(Shape shape, bool? has_stroke = null, Color? color = null, double? width = null,
                               StrokeDash? dash = null, StrokeAlign? align = null,
                               StrokeCap? cap = null, StrokeJoin? join = null, bool record_undo = true) {
            if (record_undo) checkpoint();
            if (has_stroke != null) shape.has_stroke = has_stroke;
            if (color != null) shape.stroke_color = color;
            if (width != null) shape.stroke_width = Math.fmax(0.0, width);
            if (dash != null) shape.stroke_dash = dash;
            if (align != null) shape.stroke_align = align;
            if (cap != null) shape.stroke_cap = cap;
            if (join != null) shape.stroke_join = join;
            changed();
        }

        public string set_shape_name(Shape shape, string name, bool record_undo = true) {
            string cleaned = name.strip();
            if (cleaned.length == 0 || cleaned == shape.name) {
                return shape.name;
            }
            if (record_undo) checkpoint();
            shape.name = cleaned;
            changed();
            return cleaned;
        }

        public void set_corner_radius(Shape shape, CornerRadii radius, bool record_undo = true) {
            if (record_undo) checkpoint();
            shape.corner_radius = radius;
            changed();
        }

        public Shape duplicate_shape(Shape shape, double? in_dx = null, double? in_dy = null, bool record_undo = true) {
            if (record_undo) checkpoint();

            if (shape.shape_type == ShapeType.FRAME) {
                double dx = 0.0;
                double dy = 0.0;
                if (in_dx != null) dx = in_dx;
                if (in_dy != null) dy = in_dy;

                if (in_dx == null && in_dy == null) {
                    double FRAME_GAP = 40.0;
                    double max_right = shape.x + shape.w;
                    for (uint i = 0; i < shapes.length; i++) {
                        if (shapes[i].shape_type == ShapeType.FRAME &&
                            Math.fabs(shapes[i].y - shape.y) < Math.fmax(shapes[i].h, shape.h)) {
                            max_right = Math.fmax(max_right, shapes[i].x + shapes[i].w);
                        }
                    }
                    dx = max_right + FRAME_GAP - shape.x;
                    dy = 0.0;
                }

                Shape clone_frame = shape.clone();
                clone_frame.x += dx;
                clone_frame.y += dy;

                clone_frame.name = "Frame";

                Shape new_frame = add_shape(clone_frame, false);
                var children = get_frame_children(shape);
                for (uint c = 0; c < children.length; c++) {
                    Shape c_clone = children[c].clone();
                    c_clone.x += dx;
                    c_clone.y += dy;
                    c_clone.frame_id = new_frame.id;
                    add_shape(c_clone, false);
                }
                changed();
                return new_frame;
            }

            double dx = 16.0;
            double dy = 16.0;
            if (in_dx != null) dx = in_dx;
            if (in_dy != null) dy = in_dy;

            Shape clone = shape.clone();
            string base_name = Shape.default_name(clone.shape_type);
            if (clone.name == base_name || name_index(clone.name, base_name) > 0) {
                clone.name = base_name;
            }
            clone.x += dx;
            clone.y += dy;
            if (clone.shape_type == ShapeType.GROUP) {
                for (uint c = 0; c < clone.children.length; c++) {
                    clone.children[c].x += dx;
                    clone.children[c].y += dy;
                }
            } else if (clone.shape_type == ShapeType.PATH) {
                for (uint n = 0; n < clone.nodes.length; n++) {
                    clone.nodes[n].x += dx;
                    clone.nodes[n].y += dy;
                    if (clone.nodes[n].handle_in != null) {
                        clone.nodes[n].handle_in = Point(clone.nodes[n].handle_in.x + dx, clone.nodes[n].handle_in.y + dy);
                    }
                    if (clone.nodes[n].handle_out != null) {
                        clone.nodes[n].handle_out = Point(clone.nodes[n].handle_out.x + dx, clone.nodes[n].handle_out.y + dy);
                    }
                }
            }
            Shape added = add_shape(clone, false);
            changed();
            return added;
        }

        public Shape? boolean_operation(GLib.GenericArray<Shape> shapes_to_combine, string operation = "union", bool record_undo = true) {
            if (shapes_to_combine.length < 2) return null;
            var valid = new GLib.GenericArray<Shape>();
            for (uint i = 0; i < shapes_to_combine.length; i++) {
                if (index_of(shapes_to_combine[i]) >= 0) {
                    valid.add(shapes_to_combine[i]);
                }
            }
            if (valid.length < 2) return null;

            if (record_undo) checkpoint();

            Shape? result_path = Paths.boolean_operation_shapes(valid, operation);
            if (result_path == null) return null;

            int insert_idx = int.MAX;
            for (uint i = 0; i < valid.length; i++) {
                int idx = index_of(valid[i]);
                if (idx < insert_idx) insert_idx = idx;
            }

            remove_shapes(valid, false);
            if (insert_idx >= (int) shapes.length) {
                shapes.add(result_path);
            } else {
                shapes.insert(insert_idx, result_path);
            }
            changed();
            return result_path;
        }

        public Shape? boolean_union(GLib.GenericArray<Shape> shapes_to_combine, bool record_undo = true) {
            return boolean_operation(shapes_to_combine, "union", record_undo);
        }

        public Shape? boolean_difference(GLib.GenericArray<Shape> shapes_to_combine, bool record_undo = true) {
            return boolean_operation(shapes_to_combine, "difference", record_undo);
        }

        public Shape? boolean_intersection(GLib.GenericArray<Shape> shapes_to_combine, bool record_undo = true) {
            return boolean_operation(shapes_to_combine, "intersection", record_undo);
        }

        public Shape? boolean_exclusion(GLib.GenericArray<Shape> shapes_to_combine, bool record_undo = true) {
            return boolean_operation(shapes_to_combine, "exclusion", record_undo);
        }

        public Shape? convert_to_path(Shape shape, bool record_undo = true) {
            int idx = index_of(shape);
            if (idx < 0) return null;
            if (shape.shape_type == ShapeType.PATH) return shape;

            if (record_undo) checkpoint();

            Shape path_shape = Paths.shape_to_path(shape);
            shapes.remove_index((uint) idx);
            shapes.insert(idx, path_shape);
            changed();
            return path_shape;
        }

        public void remove_shape(Shape shape, bool record_undo = true) {
            int idx = index_of(shape);
            if (idx < 0) return;

            if (record_undo) checkpoint();

            if (shape.shape_type == ShapeType.FRAME) {
                var children = get_frame_children(shape);
                var to_remove = new GLib.HashTable<string, bool>(GLib.str_hash, GLib.str_equal);
                to_remove.insert(shape.id, true);
                for (uint c = 0; c < children.length; c++) {
                    to_remove.insert(children[c].id, true);
                }
                for (int i = (int) shapes.length - 1; i >= 0; i--) {
                    if (to_remove.contains(shapes[i].id)) {
                        shapes.remove_index((uint) i);
                    }
                }
            } else {
                shapes.remove_index((uint) idx);
            }
            changed();
        }

        public void remove_shapes(GLib.GenericArray<Shape> shapes_to_remove, bool record_undo = true) {
            if (shapes_to_remove.length == 0) return;
            if (record_undo) checkpoint();

            var to_remove = new GLib.HashTable<string, bool>(GLib.str_hash, GLib.str_equal);
            for (uint i = 0; i < shapes_to_remove.length; i++) {
                to_remove.insert(shapes_to_remove[i].id, true);
                if (shapes_to_remove[i].shape_type == ShapeType.FRAME) {
                    var children = get_frame_children(shapes_to_remove[i]);
                    for (uint c = 0; c < children.length; c++) {
                        to_remove.insert(children[c].id, true);
                    }
                }
            }

            for (int i = (int) shapes.length - 1; i >= 0; i--) {
                if (to_remove.contains(shapes[i].id)) {
                    shapes.remove_index((uint) i);
                }
            }
            changed();
        }

        public Shape? group_shapes(GLib.GenericArray<Shape> shapes_to_group, bool record_undo = true) {
            if (shapes_to_group.length < 2) return null;
            var valid = new GLib.GenericArray<Shape>();
            for (uint i = 0; i < shapes_to_group.length; i++) {
                if (index_of(shapes_to_group[i]) >= 0) {
                    valid.add(shapes_to_group[i]);
                }
            }
            if (valid.length < 2) return null;

            if (record_undo) checkpoint();

            Rect bbox = Geometry.bounding_box(valid);
            int insert_idx = -1;
            for (uint i = 0; i < valid.length; i++) {
                int idx = index_of(valid[i]);
                if (idx > insert_idx) insert_idx = idx;
            }

            for (uint i = 0; i < valid.length; i++) {
                int idx = index_of(valid[i]);
                if (idx >= 0) shapes.remove_index((uint) idx);
            }

            var group = new Shape(ShapeType.GROUP);
            group.name = next_shape_name(ShapeType.GROUP);
            group.x = bbox.x;
            group.y = bbox.y;
            group.w = bbox.width;
            group.h = bbox.height;
            group.frame_id = valid[0].frame_id;
            for (uint i = 0; i < valid.length; i++) {
                group.children.add(valid[i]);
            }

            if (insert_idx >= (int) shapes.length) {
                shapes.add(group);
            } else {
                shapes.insert(insert_idx, group);
            }
            changed();
            return group;
        }

        public GLib.GenericArray<Shape> ungroup_shapes(Shape group_shape, bool record_undo = true) {
            var children = new GLib.GenericArray<Shape>();
            int idx = index_of(group_shape);
            if (idx < 0 || group_shape.shape_type != ShapeType.GROUP) return children;

            if (record_undo) checkpoint();

            shapes.remove_index((uint) idx);
            for (uint i = 0; i < group_shape.children.length; i++) {
                Shape child = group_shape.children[i];
                shapes.insert(idx + (int) i, child);
                children.add(child);
            }
            changed();
            return children;
        }

        public void align_left(GLib.GenericArray<Shape> sel_shapes) {
            align(sel_shapes, "left");
        }

        public void align_center(GLib.GenericArray<Shape> sel_shapes) {
            align(sel_shapes, "center");
        }

        public void align_right(GLib.GenericArray<Shape> sel_shapes) {
            align(sel_shapes, "right");
        }

        public void align_top(GLib.GenericArray<Shape> sel_shapes) {
            align(sel_shapes, "top");
        }

        public void align_middle(GLib.GenericArray<Shape> sel_shapes) {
            align(sel_shapes, "middle");
        }

        public void align_bottom(GLib.GenericArray<Shape> sel_shapes) {
            align(sel_shapes, "bottom");
        }

        public void distribute_horizontal(GLib.GenericArray<Shape> sel_shapes) {
            checkpoint();
            var groups = alignment_groups(sel_shapes);
            for (uint i = 0; i < groups.length; i++) {
                Geometry.distribute_shapes_horizontally(groups[i].items);
            }
            changed();
        }

        public void distribute_vertical(GLib.GenericArray<Shape> sel_shapes) {
            checkpoint();
            var groups = alignment_groups(sel_shapes);
            for (uint i = 0; i < groups.length; i++) {
                Geometry.distribute_shapes_vertically(groups[i].items);
            }
            changed();
        }

        private class AlignBucket {
            public Shape? frame;
            public GLib.GenericArray<Shape> items;
            public AlignBucket(Shape? frame) {
                this.frame = frame;
                this.items = new GLib.GenericArray<Shape>();
            }
        }

        // A selected frame aligns the layers inside it. A selected layer aligns
        // to its parent frame. Locked layers stay put. Layers with no frame
        // align to one another.
        private GLib.GenericArray<AlignBucket> alignment_groups(GLib.GenericArray<Shape> sel_shapes) {
            var groups = new GLib.GenericArray<AlignBucket>();
            var covered = new GLib.HashTable<string, bool>(GLib.str_hash, GLib.str_equal);

            for (uint i = 0; i < sel_shapes.length; i++) {
                if (sel_shapes[i].shape_type != ShapeType.FRAME) continue;
                var bucket = new AlignBucket(sel_shapes[i]);
                var children = get_frame_children(sel_shapes[i]);
                for (uint c = 0; c < children.length; c++) {
                    covered.insert(children[c].id, true);
                    if (children[c].shape_type != ShapeType.FRAME && !children[c].locked) {
                        bucket.items.add(children[c]);
                    }
                }
                groups.add(bucket);
            }

            var free = new AlignBucket(null);
            var parent_buckets = new GLib.GenericArray<AlignBucket>();
            for (uint i = 0; i < sel_shapes.length; i++) {
                unowned Shape shape = sel_shapes[i];
                if (shape.shape_type == ShapeType.FRAME || shape.locked || covered.contains(shape.id)) {
                    continue;
                }
                Shape? parent = find_parent_frame(shape);
                if (parent == null) {
                    free.items.add(shape);
                    continue;
                }
                AlignBucket? bucket = null;
                for (uint p = 0; p < parent_buckets.length; p++) {
                    if (parent_buckets[p].frame == parent) {
                        bucket = parent_buckets[p];
                        break;
                    }
                }
                if (bucket == null) {
                    bucket = new AlignBucket(parent);
                    parent_buckets.add(bucket);
                }
                bucket.items.add(shape);
            }
            for (uint p = 0; p < parent_buckets.length; p++) {
                groups.add(parent_buckets[p]);
            }
            if (free.items.length > 0) {
                groups.add(free);
            }
            return groups;
        }

        private void align_items(GLib.GenericArray<Shape> items, string edge) {
            if (edge == "left") Geometry.align_shapes_left(items);
            else if (edge == "center") Geometry.align_shapes_center(items);
            else if (edge == "right") Geometry.align_shapes_right(items);
            else if (edge == "top") Geometry.align_shapes_top(items);
            else if (edge == "middle") Geometry.align_shapes_middle(items);
            else if (edge == "bottom") Geometry.align_shapes_bottom(items);
        }

        private void align_to_frame(Shape frame, GLib.GenericArray<Shape> items, string edge) {
            for (uint i = 0; i < items.length; i++) {
                unowned Shape shape = items[i];
                if (edge == "left") shape.x = frame.x;
                else if (edge == "center") shape.x = frame.x + (frame.w - shape.w) / 2.0;
                else if (edge == "right") shape.x = frame.x + frame.w - shape.w;
                else if (edge == "top") shape.y = frame.y;
                else if (edge == "middle") shape.y = frame.y + (frame.h - shape.h) / 2.0;
                else if (edge == "bottom") shape.y = frame.y + frame.h - shape.h;
            }
        }

        private void align(GLib.GenericArray<Shape> sel_shapes, string edge) {
            checkpoint();
            var groups = alignment_groups(sel_shapes);
            for (uint i = 0; i < groups.length; i++) {
                if (groups[i].frame == null) {
                    align_items(groups[i].items, edge);
                } else {
                    align_to_frame(groups[i].frame, groups[i].items, edge);
                }
            }
            changed();
        }

        public void set_shape_locked(Shape shape, bool locked, bool record_undo = true) {
            if (record_undo) checkpoint();
            shape.locked = locked;
            changed();
        }

        public void set_shape_visibility(Shape shape, bool visible, bool record_undo = true) {
            if (record_undo) checkpoint();
            shape.visible = visible;
            changed();
        }

        public bool toggle_all_visibility(bool record_undo = true) {
            if (shapes.length == 0) return true;
            if (record_undo) checkpoint();

            bool any_visible = false;
            for (uint i = 0; i < shapes.length; i++) {
                if (shapes[i].visible) {
                    any_visible = true;
                    break;
                }
            }
            bool target = !any_visible;
            for (uint i = 0; i < shapes.length; i++) {
                shapes[i].visible = target;
            }
            changed();
            return target;
        }

        public bool bring_to_front(Shape shape) {
            int idx = index_of(shape);
            if (idx < 0) return false;

            if (shape.shape_type == ShapeType.FRAME) {
                var unit = get_frame_unit(shape);
                checkpoint();
                for (uint i = 0; i < unit.length; i++) {
                    int ui = index_of(unit[i]);
                    if (ui >= 0) shapes.remove_index((uint) ui);
                }
                for (uint i = 0; i < unit.length; i++) {
                    shapes.add(unit[i]);
                }
                changed();
                return true;
            }

            Shape? parent = find_parent_frame(shape);
            if (parent != null) {
                var p_children = get_frame_children(parent);
                if (p_children.length == 0 || p_children[p_children.length - 1] == shape) {
                    return false;
                }
                checkpoint();
                shapes.remove_index((uint) idx);
                var remaining_children = get_frame_children(parent);
                if (remaining_children.length > 0) {
                    int last_pos = index_of(remaining_children[remaining_children.length - 1]);
                    shapes.insert(last_pos + 1, shape);
                } else {
                    int p_idx = index_of(parent);
                    shapes.insert(p_idx + 1, shape);
                }
                changed();
                return true;
            }

            if (idx < (int) shapes.length - 1) {
                checkpoint();
                shapes.remove_index((uint) idx);
                shapes.add(shape);
                changed();
                return true;
            }
            return false;
        }

        public bool send_to_back(Shape shape) {
            int idx = index_of(shape);
            if (idx < 0) return false;

            if (shape.shape_type == ShapeType.FRAME) {
                var unit = get_frame_unit(shape);
                checkpoint();
                for (int i = (int) unit.length - 1; i >= 0; i--) {
                    int ui = index_of(unit[i]);
                    if (ui >= 0) shapes.remove_index((uint) ui);
                }
                for (uint i = 0; i < unit.length; i++) {
                    shapes.insert((int) i, unit[i]);
                }
                changed();
                return true;
            }

            Shape? parent = find_parent_frame(shape);
            if (parent != null) {
                int p_idx = index_of(parent);
                if (idx == p_idx + 1) return false;
                checkpoint();
                shapes.remove_index((uint) idx);
                int new_p_idx = index_of(parent);
                shapes.insert(new_p_idx + 1, shape);
                changed();
                return true;
            }

            if (idx > 0) {
                checkpoint();
                shapes.remove_index((uint) idx);
                shapes.insert(0, shape);
                changed();
                return true;
            }
            return false;
        }

        public bool bring_forward(Shape shape) {
            int idx = index_of(shape);
            if (idx < 0) return false;

            Shape? parent = find_parent_frame(shape);
            if (parent != null) {
                var p_children = get_frame_children(parent);
                int c_idx = -1;
                for (uint i = 0; i < p_children.length; i++) {
                    if (p_children[i] == shape) {
                        c_idx = (int) i;
                        break;
                    }
                }
                if (c_idx < 0 || c_idx >= (int) p_children.length - 1) return false;
                Shape next_child = p_children[c_idx + 1];
                int i1 = index_of(shape);
                int i2 = index_of(next_child);
                checkpoint();
                shapes[i1] = next_child;
                shapes[i2] = shape;
                changed();
                return true;
            }

            if (idx < (int) shapes.length - 1) {
                checkpoint();
                Shape next = shapes[idx + 1];
                shapes[idx] = next;
                shapes[idx + 1] = shape;
                changed();
                return true;
            }
            return false;
        }

        public bool send_backward(Shape shape) {
            int idx = index_of(shape);
            if (idx < 0) return false;

            Shape? parent = find_parent_frame(shape);
            if (parent != null) {
                int p_idx = index_of(parent);
                if (idx <= p_idx + 1) return false;
                var p_children = get_frame_children(parent);
                int c_idx = -1;
                for (uint i = 0; i < p_children.length; i++) {
                    if (p_children[i] == shape) {
                        c_idx = (int) i;
                        break;
                    }
                }
                if (c_idx <= 0) return false;
                Shape prev_child = p_children[c_idx - 1];
                int i1 = index_of(shape);
                int i2 = index_of(prev_child);
                checkpoint();
                shapes[i1] = prev_child;
                shapes[i2] = shape;
                changed();
                return true;
            }

            if (idx > 0) {
                checkpoint();
                Shape prev = shapes[idx - 1];
                shapes[idx] = prev;
                shapes[idx - 1] = shape;
                changed();
                return true;
            }
            return false;
        }

        public Shape? update_frame_containment(Shape shape) {
            frame_index = null;
            if (shape.shape_type == ShapeType.FRAME) return null;

            double cx = shape.x + shape.w / 2.0;
            double cy = shape.y + shape.h / 2.0;

            Shape? target_frame = null;
            for (int i = (int) shapes.length - 1; i >= 0; i--) {
                if (shapes[i].shape_type == ShapeType.FRAME &&
                    Geometry.is_point_in_frame(cx, cy, shapes[i])) {
                    target_frame = shapes[i];
                    break;
                }
            }

            string? old_fid = shape.frame_id;
            string? target_id = target_frame != null ? target_frame.id : null;

            if (target_frame != null) {
                shape.frame_id = target_id;
                int f_idx = index_of(target_frame);
                int s_idx = index_of(shape);
                if (old_fid != target_id || s_idx <= f_idx) {
                    shapes.remove_index((uint) s_idx);
                    var children = get_frame_children(target_frame);
                    if (children.length > 0) {
                        int last_pos = -1;
                        for (uint c = 0; c < children.length; c++) {
                            int ci = index_of(children[c]);
                            if (ci > last_pos) last_pos = ci;
                        }
                        shapes.insert(last_pos + 1, shape);
                    } else {
                        int new_f_idx = index_of(target_frame);
                        shapes.insert(new_f_idx + 1, shape);
                    }
                }
            } else {
                shape.frame_id = null;
            }

            return target_frame;
        }

        public Shape? hit_test(double x, double y) {
            Shape? frame_hit = null;
            for (int i = (int) shapes.length - 1; i >= 0; i--) {
                unowned Shape s = shapes[i];
                if (!s.visible || !Geometry.contains_point(s, x, y)) continue;
                if (s.shape_type == ShapeType.FRAME) {
                    if (frame_hit == null) frame_hit = s;
                } else {
                    return s;
                }
            }
            return frame_hit;
        }

        public int index_of(Shape shape) {
            for (uint i = 0; i < shapes.length; i++) {
                if (shapes[i] == shape) return (int) i;
            }
            return -1;
        }

        public Shape? find_shape_by_id(string id) {
            return find_in_list(shapes, id);
        }

        // Back-to-front children of a frame or group. The layers panel shows the reverse.
        public GLib.GenericArray<Shape> stacked_children(Shape shape) {
            var list = new GLib.GenericArray<Shape>();
            if (shape.shape_type == ShapeType.GROUP) {
                for (uint i = 0; i < shape.children.length; i++) list.add(shape.children[i]);
                return list;
            }
            if (shape.shape_type != ShapeType.FRAME) return list;
            for (uint i = 0; i < shapes.length; i++) {
                if (shapes[i].frame_id == shape.id) list.add(shapes[i]);
            }
            return list;
        }

        // Back-to-front top-level rows: frames and shapes that are not inside a frame or group.
        public GLib.GenericArray<Shape> root_layers() {
            var list = new GLib.GenericArray<Shape>();
            for (uint i = 0; i < shapes.length; i++) {
                if (layer_parent(shapes[i]) == null) list.add(shapes[i]);
            }
            return list;
        }

        public Shape? layer_parent(Shape shape) {
            Shape? group = find_group_parent(shape);
            if (group != null) return group;
            if (shape.frame_id != null) {
                Shape? frame = find_in_list(shapes, shape.frame_id);
                if (frame != null && frame.shape_type == ShapeType.FRAME) return frame;
            }
            return null;
        }

        public bool layer_contains(Shape parent, Shape needle) {
            if (parent == needle) return true;
            var kids = stacked_children(parent);
            for (uint i = 0; i < kids.length; i++) {
                if (kids[i] == needle || layer_contains(kids[i], needle)) return true;
            }
            return false;
        }

        public bool move_layer(Shape dragged, Shape target, LayerPlace place) {
            if (!move_layer_allowed(dragged, target, place)) return false;
            Shape? dest = place == LayerPlace.INTO ? target : layer_parent(target);
            var current = siblings_of(dest);
            int old_index = index_in(current, dragged);
            var sibs = copy_without(current, dragged);
            int insert_at = layer_insert_at(sibs, target, place);
            if (layer_parent(dragged) == dest && old_index == insert_at) return false;

            checkpoint();
            Shape? old_group = find_group_parent(dragged);
            if (old_group != null && old_group != dest) {
                remove_child(old_group, dragged);
                refit_group(old_group);
            }
            if (insert_at >= (int) sibs.length) sibs.add(dragged);
            else sibs.insert(insert_at, dragged);
            write_siblings(dest, sibs);
            if (dest != null && dest.shape_type == ShapeType.GROUP) refit_group(dest);
            changed();
            return true;
        }

        public Shape? find_parent_frame(Shape shape) {
            if (shape.shape_type == ShapeType.FRAME) return null;
            if (shape.frame_id != null) {
                return find_shape_by_id(shape.frame_id);
            }
            for (uint i = 0; i < shapes.length; i++) {
                if (shapes[i].shape_type == ShapeType.FRAME && Geometry.is_shape_in_frame(shape, shapes[i])) {
                    return shapes[i];
                }
            }
            return null;
        }

        private GLib.GenericArray<Shape> get_frame_unit(Shape frame) {
            var unit = new GLib.GenericArray<Shape>();
            unit.add(frame);
            var children = get_frame_children(frame);
            for (uint i = 0; i < children.length; i++) {
                unit.add(children[i]);
            }
            return unit;
        }

        public bool move_layer_allowed(Shape dragged, Shape target, LayerPlace place) {
            if (dragged == target) return false;
            if (layer_contains(dragged, target)) return false;
            if (place == LayerPlace.INTO) {
                if (dragged.shape_type == ShapeType.FRAME) return false;
                if (target.shape_type != ShapeType.GROUP && target.shape_type != ShapeType.FRAME) return false;
                return true;
            }
            Shape? dest = layer_parent(target);
            if (dragged.shape_type == ShapeType.FRAME && dest != null) return false;
            return index_in(siblings_of(dest), target) >= 0;
        }

        private GLib.GenericArray<Shape> siblings_of(Shape? parent) {
            if (parent == null) return root_layers();
            return stacked_children(parent);
        }

        private static int layer_insert_at(GLib.GenericArray<Shape> sibs, Shape target, LayerPlace place) {
            if (place == LayerPlace.INTO) return (int) sibs.length;
            int index = index_in(sibs, target);
            if (place == LayerPlace.BEFORE) return index + 1;
            return index;
        }

        private static int index_in(GLib.GenericArray<Shape> list, Shape shape) {
            for (uint i = 0; i < list.length; i++) {
                if (list[i] == shape) return (int) i;
            }
            return -1;
        }

        private static GLib.GenericArray<Shape> copy_without(GLib.GenericArray<Shape> list, Shape skip) {
            var copy = new GLib.GenericArray<Shape>();
            for (uint i = 0; i < list.length; i++) {
                if (list[i] != skip) copy.add(list[i]);
            }
            return copy;
        }

        private Shape? find_group_parent(Shape shape) {
            return find_group_parent_in(shapes, shape);
        }

        private Shape? find_group_parent_in(GLib.GenericArray<Shape> list, Shape shape) {
            for (uint i = 0; i < list.length; i++) {
                if (list[i].shape_type != ShapeType.GROUP) continue;
                for (uint c = 0; c < list[i].children.length; c++) {
                    if (list[i].children[c] == shape) return list[i];
                }
                Shape? nested = find_group_parent_in(list[i].children, shape);
                if (nested != null) return nested;
            }
            return null;
        }

        private static Shape? find_in_list(GLib.GenericArray<Shape> list, string id) {
            for (uint i = 0; i < list.length; i++) {
                if (list[i].id == id) return list[i];
                if (list[i].children.length > 0) {
                    Shape? nested = find_in_list(list[i].children, id);
                    if (nested != null) return nested;
                }
            }
            return null;
        }

        private void remove_child(Shape group, Shape shape) {
            for (uint i = 0; i < group.children.length; i++) {
                if (group.children[i] == shape) {
                    group.children.remove_index(i);
                    return;
                }
            }
        }

        private void refit_group(Shape group) {
            if (group.shape_type != ShapeType.GROUP || group.children.length == 0) return;
            Rect bounds = Geometry.bounding_box(group.children);
            group.x = bounds.x;
            group.y = bounds.y;
            group.w = bounds.width;
            group.h = bounds.height;
            Shape? parent = find_group_parent(group);
            if (parent != null) refit_group(parent);
        }

        private void write_siblings(Shape? parent, GLib.GenericArray<Shape> ordered) {
            if (parent != null && parent.shape_type == ShapeType.GROUP) {
                for (uint i = 0; i < ordered.length; i++) {
                    int idx = index_of(ordered[i]);
                    if (idx >= 0) shapes.remove_index((uint) idx);
                    ordered[i].frame_id = parent.frame_id;
                }
                parent.children.remove_range(0, parent.children.length);
                for (uint i = 0; i < ordered.length; i++) parent.children.add(ordered[i]);
                return;
            }
            if (parent != null && parent.shape_type == ShapeType.FRAME) {
                remove_shapes_from_document(ordered);
                int frame_index_now = index_of(parent);
                for (uint i = 0; i < ordered.length; i++) {
                    ordered[i].frame_id = parent.id;
                    shapes.insert(frame_index_now + 1 + (int) i, ordered[i]);
                }
                return;
            }
            for (uint i = 0; i < ordered.length; i++) {
                if (ordered[i].shape_type != ShapeType.FRAME) ordered[i].frame_id = null;
            }
            var next = new GLib.GenericArray<Shape>();
            for (uint i = 0; i < ordered.length; i++) {
                next.add(ordered[i]);
                if (ordered[i].shape_type != ShapeType.FRAME) continue;
                var kids = stacked_children(ordered[i]);
                for (uint k = 0; k < kids.length; k++) {
                    if (index_in(ordered, kids[k]) >= 0) continue;
                    next.add(kids[k]);
                }
            }
            shapes.remove_range(0, shapes.length);
            for (uint i = 0; i < next.length; i++) shapes.add(next[i]);
        }

        private void remove_shapes_from_document(GLib.GenericArray<Shape> list) {
            for (int i = (int) shapes.length - 1; i >= 0; i--) {
                if (index_in(list, shapes[i]) >= 0) shapes.remove_index((uint) i);
            }
        }
    }
}
