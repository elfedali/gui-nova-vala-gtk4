/* Canvas.vala - Interactive GTK4 canvas with gestures, viewport navigation, tool authoring, and node editing */

namespace Nova {

    public class Canvas : Gtk.DrawingArea {
        public Document document { get; private set; }

        public double pan_x { get; set; default = 40.0; }
        public double pan_y { get; set; default = 40.0; }
        public double zoom { get; set; default = 1.0; }

        private string _tool = "select";
        public string tool {
            get { return _tool; }
        }
        public Color pen_color { get; set; default = Color.rgb(0.2, 0.6, 0.85); }
        public string canvas_bg { get; set; default = "theme"; }

        public GLib.GenericArray<Shape> selected_shapes { get; private set; }
        public Shape? primary_selected {
            get {
                return selected_shapes.length > 0 ? selected_shapes[selected_shapes.length - 1] : null;
            }
        }

        private Shape? draft_shape = null;
        private string drag_mode = "none";
        private string? active_handle = null;
        private double drag_start_x = 0.0;
        private double drag_start_y = 0.0;
        private double doc_drag_start_x = 0.0;
        private double doc_drag_start_y = 0.0;
        private double doc_pointer_x = 0.0;
        private double doc_pointer_y = 0.0;
        private double last_mouse_x = 0.0;
        private double last_mouse_y = 0.0;
        private double pinch_start_zoom = 1.0;
        private double pan_origin_x = 0.0;
        private double pan_origin_y = 0.0;
        private GLib.GenericArray<Shape> drag_shapes;
        private double[] drag_origin_x = {};
        private double[] drag_origin_y = {};
        private double resize_x = 0.0;
        private double resize_y = 0.0;
        private double resize_w = 0.0;
        private double resize_h = 0.0;
        private bool alt_copy_done = false;
        private double last_drag_offset_x = 0.0;
        private double last_drag_offset_y = 0.0;
        private CornerRadii radius_origin = CornerRadii(0, 0, 0, 0);

        private GLib.GenericArray<Guide?> smart_guides;
        private Shape? measurement_target = null;
        public bool alt_held { get; set; default = false; }
        public bool shift_held { get; set; default = false; }
        public bool space_held { get; set; default = false; }
        public Color accent_color = Color.rgb(0.208, 0.518, 0.894);

        // Vector node editing
        public Shape? node_edit_shape { get; private set; default = null; }
        public int selected_node_idx { get; private set; default = -1; }
        private string? selected_handle_name = null;

        // Pen tool draft
        public Shape? pen_draft_path { get; private set; default = null; }
        private Point? pen_hover_pt = null;

        // Gestures & Controllers
        private Gtk.GestureClick click_gesture;
        private Gtk.GestureDrag drag_gesture;
        private Gtk.EventControllerMotion motion_ctrl;
        private Gtk.EventControllerScroll scroll_ctrl;
        private Gtk.GestureZoom zoom_gesture;
        private Gtk.GestureClick right_click_gesture;

        // Signals
        public signal void selection_changed();
        public signal void zoom_changed(double zoom);
        public signal void tool_changed(string tool);
        public signal void geometry_changed();
        public signal void frame_renamed(Shape frame);

        public Canvas(Document doc) {
            this.document = doc;
            this.selected_shapes = new GLib.GenericArray<Shape>();
            this.smart_guides = new GLib.GenericArray<Guide?>();
            this.drag_shapes = new GLib.GenericArray<Shape>();

            this.hexpand = true;
            this.vexpand = true;
            this.can_focus = true;

            this.set_draw_func(on_draw);
            this.document.changed.connect(() => {
                this.queue_draw();
            });

            add_controllers();
        }

        public void set_canvas_background(string bg_type) {
            this.canvas_bg = bg_type;
            this.queue_draw();
        }

        public int get_zoom_percentage() {
            return (int) Math.round(zoom * 100.0);
        }

        public void zoom_at(double new_zoom, double center_x, double center_y) {
            double clamped = Math.fmax(0.02, Math.fmin(32.0, new_zoom));
            double doc_x = (center_x - pan_x) / zoom;
            double doc_y = (center_y - pan_y) / zoom;
            pan_x = center_x - doc_x * clamped;
            pan_y = center_y - doc_y * clamped;
            zoom = clamped;
            zoom_changed(zoom);
            queue_draw();
        }

        public void zoom_to_fit() {
            if (document.shapes.length == 0) return;
            Rect bbox = Geometry.bounding_box(document.shapes);
            int w = get_width();
            int h = get_height();
            if (w <= 0 || h <= 0) return;
            double margin = 60.0;
            double fit_zoom = Math.fmin((w - margin * 2.0) / bbox.width, (h - margin * 2.0) / bbox.height);
            double clamped = Math.fmax(0.05, Math.fmin(4.0, fit_zoom));
            pan_x = (w - bbox.width * clamped) / 2.0 - bbox.x * clamped;
            pan_y = (h - bbox.height * clamped) / 2.0 - bbox.y * clamped;
            zoom = clamped;
            zoom_changed(zoom);
            queue_draw();
        }

        public void zoom_to_100() {
            int w = get_width();
            int h = get_height();
            zoom_at(1.0, w / 2.0, h / 2.0);
        }

        public void zoom_to_selection() {
            if (selected_shapes.length == 0) {
                zoom_to_fit();
                return;
            }
            Rect bbox = Geometry.bounding_box(selected_shapes);
            int w = get_width();
            int h = get_height();
            double margin = 80.0;
            double fit_zoom = Math.fmin((w - margin * 2.0) / bbox.width, (h - margin * 2.0) / bbox.height);
            double clamped = Math.fmax(0.1, Math.fmin(8.0, fit_zoom));
            pan_x = (w - bbox.width * clamped) / 2.0 - bbox.x * clamped;
            pan_y = (h - bbox.height * clamped) / 2.0 - bbox.y * clamped;
            zoom = clamped;
            zoom_changed(zoom);
            queue_draw();
        }

        public void select_shape(Shape? shape) {
            selected_shapes.remove_range(0, selected_shapes.length);
            if (shape != null) {
                selected_shapes.add(shape);
            }
            selection_changed();
            queue_draw();
        }

        public void toggle_selection(Shape shape) {
            int idx = -1;
            for (uint i = 0; i < selected_shapes.length; i++) {
                if (selected_shapes[i] == shape) {
                    idx = (int) i;
                    break;
                }
            }
            if (idx >= 0) {
                selected_shapes.remove_index((uint) idx);
            } else {
                selected_shapes.add(shape);
            }
            selection_changed();
            queue_draw();
        }

        public void select_all() {
            selected_shapes.remove_range(0, selected_shapes.length);
            for (uint i = 0; i < document.shapes.length; i++) {
                if (document.shapes[i].visible) {
                    selected_shapes.add(document.shapes[i]);
                }
            }
            selection_changed();
            queue_draw();
        }

        public void invert_selection() {
            var inverted = new GLib.GenericArray<Shape>();
            var sel_ids = new GLib.HashTable<string, bool>(GLib.str_hash, GLib.str_equal);
            for (uint i = 0; i < selected_shapes.length; i++) {
                sel_ids.insert(selected_shapes[i].id, true);
            }
            for (uint i = 0; i < document.shapes.length; i++) {
                unowned Shape s = document.shapes[i];
                if (s.visible && !sel_ids.contains(s.id)) {
                    inverted.add(s);
                }
            }
            selected_shapes.remove_range(0, selected_shapes.length);
            for (uint i = 0; i < inverted.length; i++) {
                selected_shapes.add(inverted[i]);
            }
            selection_changed();
            queue_draw();
        }

        public void clear_selection() {
            if (selected_shapes.length > 0) {
                selected_shapes.remove_range(0, selected_shapes.length);
                selection_changed();
                queue_draw();
            }
        }

        public void set_tool(string new_tool) {
            if (_tool == "pen" && new_tool != "pen" && pen_draft_path != null) {
                commit_pen_path(false, false);
            }
            if (node_edit_shape != null && new_tool != "select") {
                exit_node_edit_mode();
            }
            _tool = new_tool;
            tool_changed(new_tool);
            update_cursor();
            queue_draw();
        }

        public void hold_space(bool held) {
            space_held = held;
            update_cursor();
        }

        private void update_cursor() {
            if (space_held || _tool == "hand") {
                set_cursor(new Gdk.Cursor.from_name("grab", null));
            } else if (_tool == "select") {
                set_cursor(null);
            } else {
                set_cursor(new Gdk.Cursor.from_name("crosshair", null));
            }
        }

        public void enter_node_edit_mode(Shape? target = null) {
            Shape? s = target != null ? target : primary_selected;
            if (s == null) return;
            if (s.shape_type != ShapeType.PATH) {
                s = document.convert_to_path(s, true);
            }
            node_edit_shape = s;
            selected_node_idx = -1;
            selected_handle_name = null;
            _tool = "select";
            tool_changed(_tool);
            geometry_changed();
            queue_draw();
        }

        public void exit_node_edit_mode() {
            node_edit_shape = null;
            selected_node_idx = -1;
            selected_handle_name = null;
            geometry_changed();
            queue_draw();
        }

        public bool is_in_node_edit_mode() {
            return node_edit_shape != null;
        }

        public PathNode? get_selected_node() {
            if (node_edit_shape != null && selected_node_idx >= 0 && selected_node_idx < (int) node_edit_shape.nodes.length) {
                return node_edit_shape.nodes[selected_node_idx];
            }
            return null;
        }

        public void set_selected_node_type(NodeType node_type) {
            PathNode? n = get_selected_node();
            if (n != null && node_edit_shape != null) {
                document.checkpoint();
                Paths.set_node_type(n, node_type);
                Paths.path_recalculate_bounds(node_edit_shape);
                geometry_changed();
                queue_draw();
            }
        }

        public void delete_selected_node() {
            if (node_edit_shape != null && selected_node_idx >= 0) {
                document.checkpoint();
                Paths.remove_node_from_path(node_edit_shape, selected_node_idx);
                selected_node_idx = -1;
                geometry_changed();
                queue_draw();
            }
        }

        public void commit_pen_path(bool closed = false, bool return_to_select = true) {
            if (pen_draft_path == null || pen_draft_path.nodes.length < 2) {
                pen_draft_path = null;
                pen_hover_pt = null;
                if (return_to_select) set_tool("select");
                queue_draw();
                return;
            }

            pen_draft_path.closed = closed;
            Paths.path_recalculate_bounds(pen_draft_path);
            Shape added = document.add_shape(pen_draft_path, true);
            pen_draft_path = null;
            pen_hover_pt = null;
            select_shape(added);
            if (return_to_select) {
                set_tool("select");
            }
            queue_draw();
        }

        public void set_selected_opacity(double opacity) {
            for (uint i = 0; i < selected_shapes.length; i++) {
                document.set_opacity(selected_shapes[i], opacity, (i == 0));
            }
        }

        public void set_selected_rotation(double rotation) {
            for (uint i = 0; i < selected_shapes.length; i++) {
                document.set_rotation(selected_shapes[i], rotation, (i == 0));
            }
        }

        public void set_selected_stroke(bool? has_stroke = null, Color? color = null, double? width = null,
                                        StrokeDash? dash = null, StrokeAlign? align = null,
                                        StrokeCap? cap = null, StrokeJoin? join = null) {
            for (uint i = 0; i < selected_shapes.length; i++) {
                document.set_stroke(selected_shapes[i], has_stroke, color, width, dash, align, cap, join, (i == 0));
            }
        }

        public void set_selected_corner_radius(CornerRadii radius) {
            bool first = true;
            for (uint i = 0; i < selected_shapes.length; i++) {
                if (selected_shapes[i].shape_type == ShapeType.FRAME) continue;
                document.set_corner_radius(selected_shapes[i], radius, first);
                first = false;
            }
        }

        public void delete_selected() {
            if (is_in_node_edit_mode() && selected_node_idx >= 0) {
                delete_selected_node();
                return;
            }
            if (selected_shapes.length > 0) {
                document.remove_shapes(selected_shapes, true);
                selected_shapes.remove_range(0, selected_shapes.length);
                selection_changed();
                queue_draw();
            }
        }

        public void duplicate_selected() {
            if (selected_shapes.length == 0) return;
            document.checkpoint();
            var new_sel = new GLib.GenericArray<Shape>();
            for (uint i = 0; i < selected_shapes.length; i++) {
                new_sel.add(document.duplicate_shape(selected_shapes[i], null, null, false));
            }
            selected_shapes.remove_range(0, selected_shapes.length);
            for (uint i = 0; i < new_sel.length; i++) {
                selected_shapes.add(new_sel[i]);
            }
            selection_changed();
            queue_draw();
        }

        public void nudge_selection(double dx, double dy) {
            if (selected_shapes.length == 0) return;
            document.checkpoint();
            for (uint i = 0; i < selected_shapes.length; i++) {
                unowned Shape s = selected_shapes[i];
                document.move_shape(s, s.x + dx, s.y + dy, false);
            }
            geometry_changed();
            queue_draw();
        }

        public void group_selected() {
            Shape? g = document.group_shapes(selected_shapes, true);
            if (g != null) {
                select_shape(g);
            }
        }

        public void ungroup_selected() {
            if (primary_selected != null && primary_selected.shape_type == ShapeType.GROUP) {
                var children = document.ungroup_shapes(primary_selected, true);
                selected_shapes.remove_range(0, selected_shapes.length);
                for (uint i = 0; i < children.length; i++) {
                    selected_shapes.add(children[i]);
                }
                selection_changed();
                queue_draw();
            }
        }

        public void undo() {
            if (document.undo()) {
                selected_shapes.remove_range(0, selected_shapes.length);
                selection_changed();
                queue_draw();
            }
        }

        public void redo() {
            if (document.redo()) {
                selected_shapes.remove_range(0, selected_shapes.length);
                selection_changed();
                queue_draw();
            }
        }

        public void copy() {
            if (selected_shapes.length > 0) {
                document.clipboard.copy(selected_shapes);
            }
        }

        public void cut() {
            if (selected_shapes.length > 0) {
                document.checkpoint();
                document.clipboard.copy(selected_shapes);
                document.remove_shapes(selected_shapes, false);
                selected_shapes.remove_range(0, selected_shapes.length);
                selection_changed();
                queue_draw();
            }
        }

        public void paste() {
            if (!document.clipboard.has_content()) return;
            document.checkpoint();
            var pasted = document.clipboard.paste(16.0, 16.0);
            selected_shapes.remove_range(0, selected_shapes.length);
            for (uint i = 0; i < pasted.length; i++) {
                Shape added = document.add_shape(pasted[i], false);
                selected_shapes.add(added);
            }
            selection_changed();
            queue_draw();
        }

        public void paste_in_place() {
            if (!document.clipboard.has_content()) return;
            document.checkpoint();
            var pasted = document.clipboard.paste(0.0, 0.0);
            selected_shapes.remove_range(0, selected_shapes.length);
            for (uint i = 0; i < pasted.length; i++) {
                Shape added = document.add_shape(pasted[i], false);
                selected_shapes.add(added);
            }
            selection_changed();
            queue_draw();
        }

        public void bring_to_front() {
            if (primary_selected != null) {
                document.bring_to_front(primary_selected);
                queue_draw();
            }
        }

        public void send_to_back() {
            if (primary_selected != null) {
                document.send_to_back(primary_selected);
                queue_draw();
            }
        }

        public void bring_forward() {
            if (primary_selected != null) {
                document.bring_forward(primary_selected);
                queue_draw();
            }
        }

        public void send_backward() {
            if (primary_selected != null) {
                document.send_backward(primary_selected);
                queue_draw();
            }
        }

        public void boolean_union() {
            Shape? res = document.boolean_union(selected_shapes, true);
            if (res != null) select_shape(res);
        }

        public void boolean_difference() {
            Shape? res = document.boolean_difference(selected_shapes, true);
            if (res != null) select_shape(res);
        }

        public void boolean_intersection() {
            Shape? res = document.boolean_intersection(selected_shapes, true);
            if (res != null) select_shape(res);
        }

        public void boolean_exclusion() {
            Shape? res = document.boolean_exclusion(selected_shapes, true);
            if (res != null) select_shape(res);
        }

        public void add_image_shape(string path, double x = 80, double y = 80, double width = 200, double height = 150) {
            var img_shape = new Shape(ShapeType.IMAGE);
            img_shape.x = x;
            img_shape.y = y;
            img_shape.w = width;
            img_shape.h = height;
            img_shape.image_path = path;
            img_shape.name = "Image";
            Shape added = document.add_shape(img_shape, true);
            select_shape(added);
        }

        public void toggle_shape_lock(Shape shape) {
            document.set_shape_locked(shape, !shape.locked, true);
        }

        public void toggle_shape_visibility(Shape shape) {
            document.set_shape_visibility(shape, !shape.visible, true);
        }

        public bool toggle_all_visibility() {
            return document.toggle_all_visibility(true);
        }

        public void to_document(double wx, double wy, out double dx, out double dy) {
            dx = (wx - pan_x) / zoom;
            dy = (wy - pan_y) / zoom;
        }

        public void to_widget(double dx, double dy, out double wx, out double wy) {
            wx = dx * zoom + pan_x;
            wy = dy * zoom + pan_y;
        }

        private void on_draw(Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
            paint_background(cr, width, height);

            cr.save();
            cr.translate(pan_x, pan_y);
            cr.scale(zoom, zoom);

            // Paint all document shapes. Frame children are clipped; selection is drawn after.
            Render.paint_shapes(cr, document.shapes, Color.rgb(0.2, 0.2, 0.2), false, zoom, true);

            // Paint live drafting shape if creating
            if (draft_shape != null) {
                Render.paint_shape(cr, draft_shape, accent_color, true, zoom, true);
            }

            // Paint pen tool live preview
            if (pen_draft_path != null) {
                Render.paint_pen_preview(cr, pen_draft_path, pen_hover_pt, accent_color, zoom);
            }

            // Paint node edit overlay if editing vector nodes
            if (node_edit_shape != null) {
                Render.paint_node_edit_overlay(cr, node_edit_shape, selected_node_idx, accent_color, zoom);
            }

            // Paint selection borders and resize handles. Hidden while moving so the outline does not follow the drag.
            if (node_edit_shape == null && pen_draft_path == null && drag_mode != "move") {
                if (selected_shapes.length == 1) {
                    unowned Shape s = selected_shapes[0];
                    Rect bbox = Render.selection_bounds(s, 0.0, zoom);
                    CornerRadii? radii = null;
                    if (shows_radius_handles(s)) {
                        radii = Geometry.get_corner_radii(s);
                    }
                    Render.paint_selection_bounds(cr, bbox, accent_color, zoom, radii);
                } else if (selected_shapes.length > 1) {
                    Rect multi_bbox = Render.multi_selection_bounds(selected_shapes, 0.0, zoom);
                    Render.paint_selection_bounds(cr, multi_bbox, accent_color, zoom, null);
                }
            }

            if (drag_mode == "marquee") {
                double rx, ry, rw, rh;
                Geometry.normalize_bounds(doc_drag_start_x, doc_drag_start_y,
                                         doc_pointer_x - doc_drag_start_x,
                                         doc_pointer_y - doc_drag_start_y,
                                         out rx, out ry, out rw, out rh);
                Render.paint_marquee(cr, rx, ry, rw, rh, accent_color, zoom);
            }

            // Paint smart guides
            if (smart_guides.length > 0) {
                Render.paint_smart_guides(cr, smart_guides, zoom);
            }

            // Paint distance measurement overlay
            if (alt_held && measurement_target != null && primary_selected != null && measurement_target != primary_selected) {
                Render.paint_measurement_overlay(cr, primary_selected.get_bounds(), measurement_target.get_bounds(), zoom);
            }

            cr.restore();

            // Pixel grid from 400% upward.
            bool dark_canvas = canvas_bg == "dark" || canvas_bg == "slate";
            Render.paint_pixel_grid(cr, pan_x, pan_y, zoom, width, height, dark_canvas);
        }

        private void paint_background(Cairo.Context cr, int width, int height) {
            Color bg;
            if (canvas_bg == "white") bg = Color.rgb(1.0, 1.0, 1.0);
            else if (canvas_bg == "gray") bg = Color.rgb(0.95, 0.96, 0.96);
            else if (canvas_bg == "dark") bg = Color.rgb(0.12, 0.12, 0.13);
            else if (canvas_bg == "slate") bg = Color.rgb(0.12, 0.16, 0.23);
            else bg = Color.rgb(0.93, 0.93, 0.94); // Auto/Theme default

            cr.set_source_rgb(bg.red, bg.green, bg.blue);
            cr.rectangle(0, 0, width, height);
            cr.fill();
        }

        private void add_controllers() {
            // Click gesture (pressed / released)
            click_gesture = new Gtk.GestureClick();
            click_gesture.set_button(1);
            click_gesture.pressed.connect(on_pressed);
            this.add_controller(click_gesture);

            // Drag gesture (drag begin, update, end). Grouped with the click
            // so a press on a handle is seen before the drag starts.
            drag_gesture = new Gtk.GestureDrag();
            drag_gesture.set_button(1);
            click_gesture.group(drag_gesture);
            drag_gesture.drag_begin.connect(on_drag_begin);
            drag_gesture.drag_update.connect(on_drag_update);
            drag_gesture.drag_end.connect(on_drag_end);
            this.add_controller(drag_gesture);

            // Motion controller
            motion_ctrl = new Gtk.EventControllerMotion();
            motion_ctrl.motion.connect(on_motion);
            motion_ctrl.leave.connect(on_leave);
            this.add_controller(motion_ctrl);

            // Scroll controller
            scroll_ctrl = new Gtk.EventControllerScroll(Gtk.EventControllerScrollFlags.BOTH_AXES);
            scroll_ctrl.scroll.connect(on_scroll);
            this.add_controller(scroll_ctrl);

            zoom_gesture = new Gtk.GestureZoom();
            zoom_gesture.begin.connect(() => {
                pinch_start_zoom = zoom;
            });
            zoom_gesture.scale_changed.connect((scale) => {
                double cx, cy;
                if (!zoom_gesture.get_bounding_box_center(out cx, out cy)) {
                    cx = get_width() / 2.0;
                    cy = get_height() / 2.0;
                }
                zoom_at(pinch_start_zoom * scale, cx, cy);
            });
            this.add_controller(zoom_gesture);

            var middle_pan = new Gtk.GestureDrag();
            middle_pan.set_button(2);
            middle_pan.drag_begin.connect(() => {
                pan_origin_x = pan_x;
                pan_origin_y = pan_y;
            });
            middle_pan.drag_update.connect((offset_x, offset_y) => {
                pan_x = pan_origin_x + offset_x;
                pan_y = pan_origin_y + offset_y;
                queue_draw();
            });
            this.add_controller(middle_pan);

            // Right click context menu gesture
            right_click_gesture = new Gtk.GestureClick();
            right_click_gesture.set_button(3);
            right_click_gesture.pressed.connect((n_press, x, y) => {
                popup_context_menu(x, y);
            });
            this.add_controller(right_click_gesture);
        }

        private void on_pressed(int n_press, double x, double y) {
            this.grab_focus();
            double doc_x, doc_y;
            to_document(x, y, out doc_x, out doc_y);

            // Space key or Hand tool panning handled in drag
            if (space_held || tool == "hand") {
                return;
            }

            // Node edit mode clicks
            if (is_in_node_edit_mode() && node_edit_shape != null) {
                // Check anchor hit
                int hit_idx = Render.hit_node_anchor(node_edit_shape, doc_x, doc_y, zoom, 8.0);
                if (hit_idx >= 0) {
                    selected_node_idx = hit_idx;
                    selected_handle_name = null;
                    if (n_press == 2) { // Double click: toggle Corner / Smooth
                        unowned PathNode n = node_edit_shape.nodes[hit_idx];
                        NodeType next_type = (n.node_type == NodeType.CORNER) ? NodeType.SMOOTH : NodeType.CORNER;
                        set_selected_node_type(next_type);
                    }
                    geometry_changed();
                    queue_draw();
                    return;
                }
                // Check handle hit on selected node
                PathNode? sel_n = get_selected_node();
                if (sel_n != null) {
                    string? hhit = Render.hit_node_handle(sel_n, doc_x, doc_y, zoom, 8.0);
                    if (hhit != null) {
                        selected_handle_name = hhit;
                        queue_draw();
                        return;
                    }
                }
                // Click on path curve: add node!
                if (n_press == 1) {
                    int inserted = Paths.add_node_to_path(node_edit_shape, doc_x, doc_y, 10.0);
                    if (inserted >= 0) {
                        selected_node_idx = inserted;
                        selected_handle_name = null;
                        geometry_changed();
                        queue_draw();
                        return;
                    }
                }
                selected_node_idx = -1;
                selected_handle_name = null;
                geometry_changed();
                queue_draw();
                return;
            }

            // Pen tool clicks
            if (tool == "pen") {
                if (pen_draft_path == null) {
                    pen_draft_path = new Shape(ShapeType.PATH);
                    pen_draft_path.closed = false;
                    pen_draft_path.color = pen_color;
                    pen_draft_path.stroke_color = pen_color;
                    pen_draft_path.stroke_width = 2.0;
                    pen_draft_path.has_stroke = true;
                }
                // Check if loop closure
                if (pen_draft_path.nodes.length >= 2) {
                    unowned PathNode first = pen_draft_path.nodes[0];
                    double d_first = Math.hypot(doc_x - first.x, doc_y - first.y);
                    if (d_first <= 14.0 / zoom) {
                        commit_pen_path(true, true);
                        return;
                    }
                }
                pen_draft_path.nodes.add(Paths.create_node(doc_x, doc_y, null, null, NodeType.CORNER));
                Paths.path_recalculate_bounds(pen_draft_path);
                queue_draw();
                return;
            }

            if (n_press == 2) {
                Shape? header = frame_header_at(doc_x, doc_y);
                if (header != null) {
                    select_shape(header);
                    frame_renamed(header);
                    return;
                }
                Shape? hit = document.hit_test(doc_x, doc_y);
                if (hit != null && (hit.shape_type == ShapeType.PATH || hit.shape_type == ShapeType.RECT ||
                                    hit.shape_type == ShapeType.ELLIPSE || hit.shape_type == ShapeType.POLYGON ||
                                    hit.shape_type == ShapeType.STAR)) {
                    enter_node_edit_mode(hit);
                    return;
                }
            }

            // Select tool or Shape creation tool
            if (tool == "select") {
                active_handle = selection_handle_at(doc_x, doc_y);
                if (active_handle != null) {
                    return;
                }

                Shape? header = frame_header_at(doc_x, doc_y);
                if (header != null) {
                    pick_shape(header);
                    return;
                }

                Shape? hit = document.hit_test(doc_x, doc_y);
                if (hit != null && hit.shape_type == ShapeType.FRAME && !frame_body_selects(hit, doc_x, doc_y)) {
                    if (!shift_held) {
                        clear_selection();
                    }
                    return;
                }
                if (hit != null) {
                    pick_shape(hit);
                    return;
                }
                if (!shift_held) {
                    clear_selection();
                }
            }
        }

        private void on_drag_begin(double start_x, double start_y) {
            drag_start_x = start_x;
            drag_start_y = start_y;
            to_document(start_x, start_y, out doc_drag_start_x, out doc_drag_start_y);
            doc_pointer_x = doc_drag_start_x;
            doc_pointer_y = doc_drag_start_y;

            if (space_held || tool == "hand") {
                drag_mode = "pan";
                pan_origin_x = pan_x;
                pan_origin_y = pan_y;
                return;
            }

            if (is_in_node_edit_mode() && node_edit_shape != null) {
                if (selected_handle_name != null) {
                    drag_mode = "handle_drag";
                    document.checkpoint();
                    return;
                }
                if (selected_node_idx >= 0) {
                    drag_mode = "node_drag";
                    document.checkpoint();
                    return;
                }
            }

            if (tool == "pen") {
                drag_mode = "pen_drag";
                return;
            }

            if (tool == "pencil") {
                drag_mode = "pencil";
                doc_drag_start_x = snap_px(doc_drag_start_x);
                doc_drag_start_y = snap_px(doc_drag_start_y);
                draft_shape = new Shape(ShapeType.PENCIL);
                draft_shape.x = doc_drag_start_x;
                draft_shape.y = doc_drag_start_y;
                draft_shape.w = 1.0;
                draft_shape.h = 1.0;
                draft_shape.color = pen_color;
                draft_shape.stroke_color = pen_color;
                draft_shape.points.add(Point(0.0, 0.0));
                return;
            }

            if (tool == "select") {
                active_handle = selection_handle_at(doc_drag_start_x, doc_drag_start_y);
                if (active_handle != null) {
                    if (active_handle == "rtl" || active_handle == "rtr" || active_handle == "rbr" || active_handle == "rbl") {
                        drag_mode = "radius";
                        if (primary_selected != null) {
                            radius_origin = primary_selected.corner_radius;
                        }
                    } else if (active_handle == "rot") {
                        drag_mode = "rotate";
                    } else {
                        drag_mode = "resize";
                    }
                    if (drag_mode == "resize" && primary_selected != null) {
                        resize_x = primary_selected.x;
                        resize_y = primary_selected.y;
                        resize_w = primary_selected.w;
                        resize_h = primary_selected.h;
                    }
                    document.checkpoint();
                    return;
                }

                Shape? header = frame_header_at(doc_drag_start_x, doc_drag_start_y);
                Shape? under = header ?? document.hit_test(doc_drag_start_x, doc_drag_start_y);
                if (under != null && header == null && under.shape_type == ShapeType.FRAME && !frame_body_selects(under, doc_drag_start_x, doc_drag_start_y)) {
                    under = null;
                }
                if (selected_shapes.length > 0 && under != null && !under.locked) {
                    drag_mode = "move";
                    document.checkpoint();
                    begin_move_drag();
                    return;
                }

                drag_mode = "marquee";
                return;
            }

            // Otherwise, shape creation tool. Start on a corner or a whole pixel.
            drag_mode = "draw";
            snap_draw_point(doc_drag_start_x, doc_drag_start_y, out doc_drag_start_x, out doc_drag_start_y);
            ShapeType stype = ShapeType.from_string(tool);
            draft_shape = new Shape(stype);
            draft_shape.x = doc_drag_start_x;
            draft_shape.y = doc_drag_start_y;
            draft_shape.w = 1.0;
            draft_shape.h = 1.0;
            draft_shape.color = pen_color;
            if (stype == ShapeType.FRAME) {
                draft_shape.color = Color.rgb(1.0, 1.0, 1.0);
            }
        }

        public void refresh_modifier_drag() {
            if (drag_mode == "none") return;
            on_drag_update(last_drag_offset_x, last_drag_offset_y);
        }

        private void on_drag_update(double offset_x, double offset_y) {
            last_drag_offset_x = offset_x;
            last_drag_offset_y = offset_y;
            double cur_x = drag_start_x + offset_x;
            double cur_y = drag_start_y + offset_y;
            double doc_x, doc_y;
            to_document(cur_x, cur_y, out doc_x, out doc_y);
            doc_pointer_x = doc_x;
            doc_pointer_y = doc_y;
            clear_smart_guides();

            double doc_offset_x = offset_x / zoom;
            double doc_offset_y = offset_y / zoom;

            if (drag_mode == "marquee") {
                queue_draw();
                return;
            }

            if (drag_mode == "pan") {
                pan_x = pan_origin_x + offset_x;
                pan_y = pan_origin_y + offset_y;
                queue_draw();
                return;
            }

            if (drag_mode == "move") {
                double total_dx = doc_x - doc_drag_start_x;
                double total_dy = doc_y - doc_drag_start_y;
                if (alt_held && !alt_copy_done && (Math.fabs(total_dx) > 1.0 || Math.fabs(total_dy) > 1.0)) {
                    alt_copy_done = true;
                    for (uint i = 0; i < drag_shapes.length; i++) {
                        document.move_shape(drag_shapes[i], drag_origin_x[i], drag_origin_y[i], false);
                    }
                    var copies = new GLib.GenericArray<Shape>();
                    for (uint i = 0; i < drag_shapes.length; i++) {
                        copies.add(document.duplicate_shape(drag_shapes[i], 0.0, 0.0, false));
                    }
                    drag_shapes = copies;
                    drag_origin_x = new double[copies.length];
                    drag_origin_y = new double[copies.length];
                    selected_shapes.remove_range(0, selected_shapes.length);
                    for (uint i = 0; i < copies.length; i++) {
                        drag_origin_x[i] = copies[i].x;
                        drag_origin_y[i] = copies[i].y;
                        selected_shapes.add(copies[i]);
                    }
                    selection_changed();
                }
                var moving_frames = new GLib.HashTable<string, bool>(GLib.str_hash, GLib.str_equal);
                for (uint i = 0; i < drag_shapes.length; i++) {
                    if (drag_shapes[i].shape_type == ShapeType.FRAME) {
                        moving_frames.insert(drag_shapes[i].id, true);
                    }
                }
                double adj_x, adj_y;
                move_corner_adjust(total_dx, total_dy, moving_frames, out adj_x, out adj_y);
                for (uint i = 0; i < drag_shapes.length; i++) {
                    unowned Shape s = drag_shapes[i];
                    if (s.frame_id != null && moving_frames.contains(s.frame_id)) {
                        continue;
                    }
                    document.move_shape(s, snap_px(drag_origin_x[i] + total_dx) + adj_x, snap_px(drag_origin_y[i] + total_dy) + adj_y, false);
                }
                geometry_changed();
                queue_draw();
                return;
            }

            if (drag_mode == "resize" && primary_selected != null && active_handle != null) {
                unowned Shape s = primary_selected;
                double total_dx = doc_x - doc_drag_start_x;
                double total_dy = doc_y - doc_drag_start_y;
                double rx, ry, rw, rh;
                if (active_handle == "nw" || active_handle == "ne" || active_handle == "se" || active_handle == "sw") {
                    Geometry.resize_from_corner(resize_x, resize_y, resize_w, resize_h, active_handle, total_dx, total_dy,
                                               shift_held, alt_held, Geometry.MIN_SHAPE_SIZE, out rx, out ry, out rw, out rh);
                } else {
                    Geometry.resize_from_edge(resize_x, resize_y, resize_w, resize_h, active_handle, total_dx, total_dy,
                                             alt_held, Geometry.MIN_SHAPE_SIZE, out rx, out ry, out rw, out rh);
                }
                s.x = snap_px(rx);
                s.y = snap_px(ry);
                s.w = Math.fmax(1.0, snap_px(rw));
                s.h = Math.fmax(1.0, snap_px(rh));
                if (!shift_held && !alt_held) {
                    snap_resize_to_corner(s, active_handle);
                } else {
                    clear_smart_guides();
                }
                geometry_changed();
                queue_draw();
                return;
            }

            if (drag_mode == "radius" && primary_selected != null && active_handle != null) {
                unowned Shape s = primary_selected;
                double r = Geometry.corner_radius_from_pointer(active_handle, doc_x, doc_y, s.x, s.y, s.w, s.h);
                if (alt_held) {
                    CornerRadii radii = radius_origin;
                    if (active_handle == "rtl") radii.tl = r;
                    else if (active_handle == "rtr") radii.tr = r;
                    else if (active_handle == "rbr") radii.br = r;
                    else radii.bl = r;
                    s.corner_radius = radii;
                } else {
                    s.corner_radius = CornerRadii.uniform(r);
                }
                geometry_changed();
                queue_draw();
                return;
            }

            if (drag_mode == "rotate" && primary_selected != null) {
                unowned Shape s = primary_selected;
                double cx = s.x + s.w / 2.0;
                double cy = s.y + s.h / 2.0;
                double angle_rad = Math.atan2(doc_y - cy, doc_x - cx) + Math.PI / 2.0;
                double deg = (angle_rad * 180.0 / Math.PI) % 360.0;
                if (deg < 0) deg += 360.0;
                if (shift_held) {
                    deg = Math.round(deg / 15.0) * 15.0;
                }
                s.rotation = deg;
                geometry_changed();
                queue_draw();
                return;
            }

            if (drag_mode == "pencil" && draft_shape != null) {
                draft_shape.points.add(Point(snap_px(doc_x) - draft_shape.x, snap_px(doc_y) - draft_shape.y));
                queue_draw();
                return;
            }

            if (drag_mode == "draw" && draft_shape != null) {
                double px, py;
                snap_draw_point(doc_x, doc_y, out px, out py);
                if (tool == "line" || tool == "arrow") {
                    double lw = px - doc_drag_start_x;
                    double lh = py - doc_drag_start_y;
                    if (shift_held) {
                        double ang = Math.atan2(lh, lw);
                        double snap = Math.round(ang / (Math.PI / 4.0)) * (Math.PI / 4.0);
                        double dist = Math.hypot(lw, lh);
                        lw = dist * Math.cos(snap);
                        lh = dist * Math.sin(snap);
                    }
                    draft_shape.x = doc_drag_start_x;
                    draft_shape.y = doc_drag_start_y;
                    draft_shape.w = snap_px(lw);
                    draft_shape.h = snap_px(lh);
                } else {
                    double nx, ny, nw, nh;
                    Geometry.normalize_bounds(doc_drag_start_x, doc_drag_start_y,
                                             px - doc_drag_start_x, py - doc_drag_start_y,
                                             out nx, out ny, out nw, out nh);
                    if (shift_held) {
                        double sz = Math.fmax(nw, nh);
                        nw = sz; nh = sz;
                    }
                    draft_shape.x = snap_px(nx);
                    draft_shape.y = snap_px(ny);
                    draft_shape.w = Math.fmax(1.0, snap_px(nw));
                    draft_shape.h = Math.fmax(1.0, snap_px(nh));
                }
                queue_draw();
                return;
            }

            if (drag_mode == "pen_drag" && pen_draft_path != null && pen_draft_path.nodes.length > 0) {
                unowned PathNode last = pen_draft_path.nodes[pen_draft_path.nodes.length - 1];
                double hdx = doc_x - last.x;
                double hdy = doc_y - last.y;
                last.handle_out = Point(last.x + hdx, last.y + hdy);
                last.handle_in = Point(last.x - hdx, last.y - hdy);
                last.node_type = NodeType.SMOOTH;
                queue_draw();
                return;
            }

            if (drag_mode == "handle_drag" && node_edit_shape != null) {
                PathNode? sel_n = get_selected_node();
                if (sel_n != null && selected_handle_name != null) {
                    Paths.update_node_handle(sel_n, selected_handle_name, doc_x, doc_y);
                    Paths.path_recalculate_bounds(node_edit_shape);
                    queue_draw();
                    return;
                }
            }

            if (drag_mode == "node_drag" && node_edit_shape != null) {
                PathNode? sel_n = get_selected_node();
                if (sel_n != null) {
                    double ndx = doc_x - sel_n.x;
                    double ndy = doc_y - sel_n.y;
                    sel_n.x = doc_x;
                    sel_n.y = doc_y;
                    if (sel_n.handle_in != null) sel_n.handle_in = Point(sel_n.handle_in.x + ndx, sel_n.handle_in.y + ndy);
                    if (sel_n.handle_out != null) sel_n.handle_out = Point(sel_n.handle_out.x + ndx, sel_n.handle_out.y + ndy);
                    Paths.path_recalculate_bounds(node_edit_shape);
                    queue_draw();
                    return;
                }
            }
        }

        private static double snap_px(double value) {
            return Math.round(value);
        }

        private double corner_snap_threshold() {
            return 8.0 / Math.fmax(zoom, 1e-6);
        }

        private void clear_smart_guides() {
            if (smart_guides.length > 0) {
                smart_guides.remove_range(0, smart_guides.length);
            }
        }

        private void show_corner_cross(double x, double y) {
            double arm = 14.0 / Math.fmax(zoom, 1e-6);
            smart_guides.add(Guide("v", x, y - arm, y + arm));
            smart_guides.add(Guide("h", y, x - arm, x + arm));
        }

        private void snap_draw_point(double x, double y, out double out_x, out double out_y) {
            clear_smart_guides();
            double sx, sy;
            if (closest_corner(x, y, corner_snap_threshold(), null, null, out sx, out sy)) {
                out_x = sx;
                out_y = sy;
                show_corner_cross(sx, sy);
                return;
            }
            out_x = snap_px(x);
            out_y = snap_px(y);
        }

        private void move_corner_adjust(double total_dx, double total_dy, GLib.HashTable<string, bool> moving_frames, out double adj_x, out double adj_y) {
            adj_x = 0.0;
            adj_y = 0.0;
            clear_smart_guides();
            var ignore = new GLib.HashTable<string, bool>(GLib.str_hash, GLib.str_equal);
            for (uint i = 0; i < drag_shapes.length; i++) {
                ignore.insert(drag_shapes[i].id, true);
            }
            double thresh = corner_snap_threshold();
            double best = thresh * thresh;
            bool found = false;
            double hit_x = 0.0;
            double hit_y = 0.0;
            for (uint i = 0; i < drag_shapes.length; i++) {
                unowned Shape s = drag_shapes[i];
                if (s.frame_id != null && moving_frames.contains(s.frame_id)) continue;
                double nx = snap_px(drag_origin_x[i] + total_dx);
                double ny = snap_px(drag_origin_y[i] + total_dy);
                double[] xs = { nx, nx + s.w, nx + s.w, nx };
                double[] ys = { ny, ny, ny + s.h, ny + s.h };
                for (int c = 0; c < 4; c++) {
                    double tx, ty;
                    if (!closest_corner(xs[c], ys[c], thresh, ignore, moving_frames, out tx, out ty)) continue;
                    double ddx = tx - xs[c];
                    double ddy = ty - ys[c];
                    double dist2 = ddx * ddx + ddy * ddy;
                    if (dist2 <= best) {
                        best = dist2;
                        found = true;
                        adj_x = ddx;
                        adj_y = ddy;
                        hit_x = tx;
                        hit_y = ty;
                    }
                }
            }
            if (found) show_corner_cross(hit_x, hit_y);
        }

        private void snap_resize_to_corner(Shape shape, string handle) {
            clear_smart_guides();
            var ignore = new GLib.HashTable<string, bool>(GLib.str_hash, GLib.str_equal);
            ignore.insert(shape.id, true);
            double thresh = corner_snap_threshold();

            if (handle == "nw" || handle == "ne" || handle == "se" || handle == "sw") {
                double cx = shape.x;
                double cy = shape.y;
                double ax = shape.x + shape.w;
                double ay = shape.y + shape.h;
                if (handle == "ne") {
                    cx = shape.x + shape.w;
                    cy = shape.y;
                    ax = shape.x;
                    ay = shape.y + shape.h;
                } else if (handle == "se") {
                    cx = shape.x + shape.w;
                    cy = shape.y + shape.h;
                    ax = shape.x;
                    ay = shape.y;
                } else if (handle == "sw") {
                    cx = shape.x;
                    cy = shape.y + shape.h;
                    ax = shape.x + shape.w;
                    ay = shape.y;
                }
                double tx, ty;
                if (!closest_corner(cx, cy, thresh, ignore, null, out tx, out ty)) return;
                double nx, ny, nw, nh;
                Geometry.normalize_bounds(ax, ay, tx - ax, ty - ay, out nx, out ny, out nw, out nh);
                if (nw < Geometry.MIN_SHAPE_SIZE || nh < Geometry.MIN_SHAPE_SIZE) return;
                shape.x = nx;
                shape.y = ny;
                shape.w = nw;
                shape.h = nh;
                show_corner_cross(tx, ty);
                return;
            }

            bool vertical = handle == "e" || handle == "w";
            double edge = vertical ? shape.x : shape.y;
            if (handle == "e") edge = shape.x + shape.w;
            else if (handle == "s") edge = shape.y + shape.h;
            double best = thresh;
            bool found = false;
            double hit = edge;
            double guide_x = 0.0;
            double guide_y = 0.0;
            for (uint i = 0; i < document.shapes.length; i++) {
                unowned Shape other = document.shapes[i];
                if (!other.visible || ignore.contains(other.id)) continue;
                double[] xs = { other.x, other.x + other.w, other.x + other.w, other.x };
                double[] ys = { other.y, other.y, other.y + other.h, other.y + other.h };
                for (int c = 0; c < 4; c++) {
                    if (vertical) {
                        double delta = Math.fabs(xs[c] - edge);
                        if (delta >= best) continue;
                        if (ys[c] < shape.y - thresh || ys[c] > shape.y + shape.h + thresh) continue;
                        best = delta;
                        found = true;
                        hit = xs[c];
                        guide_x = xs[c];
                        guide_y = ys[c];
                    } else {
                        double delta = Math.fabs(ys[c] - edge);
                        if (delta >= best) continue;
                        if (xs[c] < shape.x - thresh || xs[c] > shape.x + shape.w + thresh) continue;
                        best = delta;
                        found = true;
                        hit = ys[c];
                        guide_x = xs[c];
                        guide_y = ys[c];
                    }
                }
            }
            if (!found) return;
            if (handle == "e") {
                shape.w = Math.fmax(Geometry.MIN_SHAPE_SIZE, hit - shape.x);
            } else if (handle == "w") {
                double right = shape.x + shape.w;
                shape.x = hit;
                shape.w = Math.fmax(Geometry.MIN_SHAPE_SIZE, right - hit);
            } else if (handle == "s") {
                shape.h = Math.fmax(Geometry.MIN_SHAPE_SIZE, hit - shape.y);
            } else if (handle == "n") {
                double bottom = shape.y + shape.h;
                shape.y = hit;
                shape.h = Math.fmax(Geometry.MIN_SHAPE_SIZE, bottom - hit);
            }
            show_corner_cross(guide_x, guide_y);
        }

        private bool closest_corner(double x, double y, double thresh, GLib.HashTable<string, bool>? ignore, GLib.HashTable<string, bool>? moving_frames, out double out_x, out double out_y) {
            out_x = x;
            out_y = y;
            double best = thresh * thresh;
            bool found = false;
            for (uint i = 0; i < document.shapes.length; i++) {
                unowned Shape shape = document.shapes[i];
                if (!shape.visible) continue;
                if (ignore != null && ignore.contains(shape.id)) continue;
                if (moving_frames != null && shape.frame_id != null && moving_frames.contains(shape.frame_id)) continue;
                double[] xs = { shape.x, shape.x + shape.w, shape.x + shape.w, shape.x };
                double[] ys = { shape.y, shape.y, shape.y + shape.h, shape.y + shape.h };
                for (int c = 0; c < 4; c++) {
                    double ddx = xs[c] - x;
                    double ddy = ys[c] - y;
                    if (Math.fabs(ddx) > thresh || Math.fabs(ddy) > thresh) continue;
                    double dist2 = ddx * ddx + ddy * ddy;
                    if (dist2 <= best) {
                        best = dist2;
                        found = true;
                        out_x = xs[c];
                        out_y = ys[c];
                    }
                }
            }
            return found;
        }

        private static void fit_pencil_bounds(Shape shape) {
            if (shape.points.length == 0) return;
            double min_x = 0.0;
            double min_y = 0.0;
            double max_x = 0.0;
            double max_y = 0.0;
            bool any = false;
            for (uint i = 0; i < shape.points.length; i++) {
                Point? raw = shape.points[i];
                if (raw == null) continue;
                Point p = raw;
                if (!any) {
                    min_x = max_x = p.x;
                    min_y = max_y = p.y;
                    any = true;
                } else {
                    min_x = Math.fmin(min_x, p.x);
                    min_y = Math.fmin(min_y, p.y);
                    max_x = Math.fmax(max_x, p.x);
                    max_y = Math.fmax(max_y, p.y);
                }
            }
            if (!any) return;
            shape.x = snap_px(shape.x + min_x);
            shape.y = snap_px(shape.y + min_y);
            shape.w = Math.fmax(1.0, snap_px(max_x - min_x));
            shape.h = Math.fmax(1.0, snap_px(max_y - min_y));
            for (uint i = 0; i < shape.points.length; i++) {
                Point? raw = shape.points[i];
                if (raw == null) continue;
                Point p = raw;
                shape.points[i] = Point(p.x - min_x, p.y - min_y);
            }
        }

        private void on_drag_end(double offset_x, double offset_y) {
            smart_guides.remove_range(0, smart_guides.length);

            if (drag_mode == "pencil" && draft_shape != null) {
                draft_shape.points = Geometry.smooth_points(draft_shape.points, 2);
                fit_pencil_bounds(draft_shape);
                if (draft_shape.points.length >= 2) {
                    Shape added = document.add_shape(draft_shape, true);
                    draft_shape = null;
                    select_shape(added);
                } else {
                    draft_shape = null;
                }
                set_tool("select");
            }

            if (drag_mode == "draw" && draft_shape != null) {
                if (tool == "line" || tool == "arrow") {
                    if (Math.hypot(draft_shape.w, draft_shape.h) < 2.0) {
                        draft_shape.w = 100.0;
                        draft_shape.h = 0.0;
                    }
                    draft_shape.x = snap_px(draft_shape.x);
                    draft_shape.y = snap_px(draft_shape.y);
                    draft_shape.w = snap_px(draft_shape.w);
                    draft_shape.h = snap_px(draft_shape.h);
                } else if (draft_shape.w < 4.0 && draft_shape.h < 4.0) {
                    if (tool == "frame") {
                        draft_shape.w = 393.0;
                        draft_shape.h = 852.0;
                        int count = 1;
                        for (uint i = 0; i < document.shapes.length; i++) {
                            if (document.shapes[i].shape_type == ShapeType.FRAME) count++;
                        }
                        draft_shape.name = "iPhone 15 - %d".printf(count);
                        draft_shape.frame_preset = "iPhone 15 (393 × 852)";
                    } else {
                        draft_shape.w = 100.0;
                        draft_shape.h = 100.0;
                    }
                } else if (tool == "frame") {
                    draft_shape.frame_preset = "Custom";
                }
                draft_shape.x = snap_px(draft_shape.x);
                draft_shape.y = snap_px(draft_shape.y);
                if (tool != "line" && tool != "arrow") {
                    draft_shape.w = Math.fmax(1.0, snap_px(draft_shape.w));
                    draft_shape.h = Math.fmax(1.0, snap_px(draft_shape.h));
                }
                Shape added = document.add_shape(draft_shape, true);
                draft_shape = null;
                select_shape(added);
                set_tool("select");
            }

            if (drag_mode == "move") {
                for (uint i = 0; i < selected_shapes.length; i++) {
                    document.update_frame_containment(selected_shapes[i]);
                }
            }
            if (drag_mode == "resize" && primary_selected != null && primary_selected.shape_type != ShapeType.FRAME) {
                document.update_frame_containment(primary_selected);
            }

            if (drag_mode == "marquee") {
                double rx, ry, rw, rh;
                Geometry.normalize_bounds(doc_drag_start_x, doc_drag_start_y,
                                         doc_pointer_x - doc_drag_start_x,
                                         doc_pointer_y - doc_drag_start_y,
                                         out rx, out ry, out rw, out rh);
                if (rw >= 2.0 || rh >= 2.0) {
                    if (!shift_held) {
                        selected_shapes.remove_range(0, selected_shapes.length);
                    }
                    for (uint i = 0; i < document.shapes.length; i++) {
                        unowned Shape s = document.shapes[i];
                        if (s.shape_type == ShapeType.FRAME) continue;
                        if (!s.visible || !Geometry.shape_intersects_rect(s, rx, ry, rw, rh)) {
                            continue;
                        }
                        bool already = false;
                        for (uint j = 0; j < selected_shapes.length; j++) {
                            if (selected_shapes[j] == s) {
                                already = true;
                                break;
                            }
                        }
                        if (!already) {
                            selected_shapes.add(s);
                        }
                    }
                    selection_changed();
                }
            }

            drag_mode = "none";
            active_handle = null;
            queue_draw();
        }

        private void on_motion(double x, double y) {
            last_mouse_x = x;
            last_mouse_y = y;
            double doc_x, doc_y;
            to_document(x, y, out doc_x, out doc_y);

            if (tool == "pen" && pen_draft_path != null) {
                pen_hover_pt = Point(doc_x, doc_y);
                queue_draw();
                return;
            }

            if (alt_held) {
                Shape? hit = document.hit_test(doc_x, doc_y);
                if (hit != measurement_target) {
                    measurement_target = hit;
                    queue_draw();
                }
            } else if (measurement_target != null) {
                measurement_target = null;
                queue_draw();
            }
        }

        private void on_leave() {
            if (pen_hover_pt != null) {
                pen_hover_pt = null;
                queue_draw();
            }
            if (measurement_target != null) {
                measurement_target = null;
                queue_draw();
            }
        }

        private bool on_scroll(double dx, double dy) {
            Gdk.ModifierType state = scroll_ctrl.get_current_event_state();
            bool ctrl = (state & Gdk.ModifierType.CONTROL_MASK) != 0;
            double cx = last_mouse_x > 0.0 ? last_mouse_x : get_width() / 2.0;
            double cy = last_mouse_y > 0.0 ? last_mouse_y : get_height() / 2.0;

            // Touchpads report pixels. A mouse wheel reports clicks.
            bool pixels = scroll_ctrl.get_unit() == Gdk.ScrollUnit.SURFACE;
            if (ctrl) {
                double steps = pixels ? dy / 40.0 : dy;
                zoom_at(zoom * Math.pow(1.15, -steps), cx, cy);
                return true;
            }
            if (dx == 0.0 && dy == 0.0) return false;
            double mx = pixels ? dx : dx * 12.0;
            double my = pixels ? dy : dy * 12.0;
            pan_x -= mx;
            pan_y -= my;
            queue_draw();
            return true;
        }

        private bool shows_radius_handles(Shape shape) {
            return shape.shape_type == ShapeType.RECT || shape.shape_type == ShapeType.IMAGE;
        }

        private string? selection_handle_at(double doc_x, double doc_y) {
            if (selected_shapes.length != 1) return null;
            unowned Shape s = selected_shapes[0];
            if (s.locked) return null;
            Rect bbox = Render.selection_bounds(s, 0.0, zoom);
            CornerRadii? radii = null;
            if (shows_radius_handles(s)) {
                radii = Geometry.get_corner_radii(s);
            }
            return Render.hit_handle(bbox, doc_x, doc_y, Render.HANDLE_SIZE, zoom, radii);
        }

        private bool frame_body_selects(Shape frame, double x, double y) {
            if (document.get_frame_children(frame).length == 0) {
                return true;
            }
            double margin = 6.0 / double.max(1e-6, zoom);
            return Geometry.hit_test_frame_border(frame, x, y, margin);
        }

        private void pick_shape(Shape hit) {
            if (shift_held) {
                toggle_selection(hit);
                return;
            }
            for (uint i = 0; i < selected_shapes.length; i++) {
                if (selected_shapes[i] == hit) {
                    return;
                }
            }
            select_shape(hit);
        }

        private Shape? frame_header_at(double doc_x, double doc_y) {
            for (int i = (int) document.shapes.length - 1; i >= 0; i--) {
                unowned Shape shape = document.shapes[i];
                if (shape.shape_type == ShapeType.FRAME && shape.visible &&
                    Geometry.hit_test_frame_header(shape, doc_x, doc_y, zoom)) {
                    return shape;
                }
            }
            return null;
        }

        private void begin_move_drag() {
            alt_copy_done = false;
            drag_shapes.remove_range(0, drag_shapes.length);
            var moving_frames = new GLib.HashTable<string, bool>(GLib.str_hash, GLib.str_equal);
            for (uint i = 0; i < selected_shapes.length; i++) {
                if (selected_shapes[i].shape_type == ShapeType.FRAME) {
                    moving_frames.insert(selected_shapes[i].id, true);
                }
            }
            for (uint i = 0; i < selected_shapes.length; i++) {
                unowned Shape shape = selected_shapes[i];
                if (shape.locked) continue;
                if (shape.frame_id != null && moving_frames.contains(shape.frame_id)) continue;
                drag_shapes.add(shape);
            }
            drag_origin_x = new double[drag_shapes.length];
            drag_origin_y = new double[drag_shapes.length];
            for (uint i = 0; i < drag_shapes.length; i++) {
                drag_origin_x[i] = drag_shapes[i].x;
                drag_origin_y[i] = drag_shapes[i].y;
            }
        }

        private void popup_context_menu(double x, double y) {
            var menu = new GLib.Menu();

            if (selected_shapes.length > 0) {
                var edit_section = new GLib.Menu();
                edit_section.append("Cut", "app.cut");
                edit_section.append("Copy", "app.copy");
                edit_section.append("Paste", "app.paste");
                edit_section.append("Duplicate", "app.duplicate");
                edit_section.append("Delete", "app.delete");
                menu.append_section(null, edit_section);

                var arrange_section = new GLib.Menu();
                arrange_section.append("Bring to Front", "app.bring-front");
                arrange_section.append("Bring Forward", "app.bring-forward");
                arrange_section.append("Send Backward", "app.send-backward");
                arrange_section.append("Send to Back", "app.send-back");
                menu.append_section(null, arrange_section);

                var group_section = new GLib.Menu();
                if (primary_selected != null && primary_selected.shape_type == ShapeType.GROUP) {
                    group_section.append("Ungroup", "app.ungroup");
                } else if (selected_shapes.length > 1) {
                    group_section.append("Group", "app.group");
                }
                menu.append_section(null, group_section);

                var path_section = new GLib.Menu();
                path_section.append("Convert to Vector Path", "app.convert-path");
                if (selected_shapes.length >= 2) {
                    path_section.append("Boolean Union", "app.bool-union");
                    path_section.append("Boolean Subtract", "app.bool-diff");
                    path_section.append("Boolean Intersect", "app.bool-inter");
                    path_section.append("Boolean Exclude", "app.bool-excl");
                }
                menu.append_section(null, path_section);
            } else {
                var vp_section = new GLib.Menu();
                vp_section.append("Select All", "app.select-all");
                vp_section.append("Paste", "app.paste");
                vp_section.append("Zoom to Fit", "app.zoom-fit");
                vp_section.append("Zoom to 100%", "app.zoom-100");
                menu.append_section(null, vp_section);
            }

            var popover = new Gtk.PopoverMenu.from_model(menu);
            popover.set_parent(this);
            var rect = Gdk.Rectangle();
            rect.x = (int) x;
            rect.y = (int) y;
            rect.width = 1;
            rect.height = 1;
            popover.set_pointing_to(rect);
            popover.set_has_arrow(false);
            popover.popup();
        }
    }
}
