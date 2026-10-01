/* Window.vala - Main application window with collapsible sidebars, floating dock, and inspector */

namespace Nova {

    public class Window : Adw.ApplicationWindow {
        public Document document { get; private set; }
        public Canvas canvas { get; private set; }

        private Gtk.Box main_box;
        private Gtk.Box left_sidebar;
        private Gtk.Box right_sidebar;
        private Gtk.ListBox layer_list;
        private Gtk.SearchEntry layer_search;
        private Gtk.Label layer_count_label;
        private Gtk.Button toggle_all_vis_btn;

        // Floating dock tool buttons
        private Gtk.ToggleButton select_tool_btn;
        private Gtk.ToggleButton hand_tool_btn;
        private Gtk.ToggleButton frame_tool_btn;
        private Gtk.ToggleButton shape_tool_btn;
        private Gtk.ToggleButton draw_tool_btn;
        private Gtk.ToggleButton text_tool_btn;
        private Gtk.Image shape_icon;
        private Gtk.Image draw_icon;
        private Gtk.Popover frame_popover;
        private Gtk.Popover shape_popover;
        private Gtk.Popover draw_popover;

        private string current_shape_tool = "rect";
        private string current_draw_tool = "pen";
        private bool updating_tools = false;
        private bool frame_press_active = false;
        private bool shape_press_active = false;
        private bool draw_press_active = false;

        // Inspector widgets
        private Gtk.Box alignment_box;
        private Gtk.Box boolean_box;
        private Gtk.SpinButton x_spin;
        private Gtk.SpinButton y_spin;
        private Gtk.SpinButton w_spin;
        private Gtk.SpinButton h_spin;
        private Gtk.SpinButton rot_spin;

        private Gtk.Scale radius_scale;
        private Gtk.SpinButton radius_spin;
        private Gtk.ToggleButton indep_radius_toggle;
        private Gtk.Box indep_radius_box;
        private Gtk.SpinButton tl_spin;
        private Gtk.SpinButton tr_spin;
        private Gtk.SpinButton br_spin;
        private Gtk.SpinButton bl_spin;

        private Gtk.Scale opacity_scale;
        private Gtk.SpinButton opacity_spin;

        private Gtk.Button fill_swatch;
        private Gtk.Entry fill_hex_entry;
        private Gtk.Button eyedropper_btn;
        private Gtk.Box doc_palette_box;

        private Gtk.SpinButton stroke_width_spin;
        private Gtk.Button stroke_swatch;
        private Gtk.Entry stroke_hex_entry;
        private Gtk.DropDown stroke_dash_dd;
        private Gtk.DropDown stroke_align_dd;
        private Gtk.DropDown stroke_cap_dd;
        private Gtk.DropDown stroke_join_dd;

        private Gtk.Box text_section;
        private Gtk.Entry text_entry;
        private Gtk.Entry font_family_entry;
        private Gtk.SpinButton font_size_spin;
        private Gtk.DropDown font_weight_dd;
        private Gtk.DropDown font_slant_dd;
        private Gtk.DropDown text_align_dd;
        private Gtk.Box polygon_section;
        private Gtk.SpinButton polygon_sides_spin;
        private Gtk.Box star_section;
        private Gtk.SpinButton star_points_spin;
        private Gtk.Scale star_ratio_scale;

        private Gtk.Box node_edit_box;
        private Gtk.Button node_corner_btn;
        private Gtk.Button node_smooth_btn;
        private Gtk.Button node_asymm_btn;
        private Gtk.Button node_del_btn;

        private Gtk.DropDown export_fmt_dd;
        private Gtk.DropDown export_scale_dd;
        private Gtk.Button export_button;
        private Gtk.DrawingArea export_preview_area;
        private Gtk.DrawingArea fill_chip;
        private Gtk.DrawingArea stroke_chip;
        private Color fill_chip_color = Color.rgb(0.2, 0.6, 0.85);
        private Color stroke_chip_color = Color.rgb(0.2, 0.2, 0.2);
        private Gtk.Entry rename_entry;
        private Shape? rename_target = null;
        private bool rename_open = false;
        private bool updating_layers = false;
        private Gtk.Entry? layer_rename_entry = null;
        private Shape? layer_rename_shape = null;
        private bool layer_rename_done = false;

        private Gtk.Label zoom_label;
        private bool updating_inspector = false;
        private GLib.HashTable<string, bool> collapsed_frames;

        public Window(Adw.Application app, Document doc) {
            Object(application: app);
            this.title = "Nova";
            this.set_default_size(1220, 780);

            this.document = doc;
            this.canvas = new Canvas(doc);
            this.collapsed_frames = new GLib.HashTable<string, bool>(GLib.str_hash, GLib.str_equal);

            install_css();
            var header = build_header_bar();
            build_layout(header);
            wire_canvas_events();
            add_keyboard_controller();

            refresh_layers();
            update_inspector();
        }

        private void install_css() {
            var provider = new Gtk.CssProvider();
            provider.load_from_resource("/com/iminwa/nova/style.css");
            // The C function is still the supported way to install app CSS.
            // Vala only exposes it on the deprecated Gtk.StyleContext type.
            add_provider_for_display(
                this.get_display(),
                provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            );
        }

        [CCode (cname = "gtk_style_context_add_provider_for_display")]
        private static extern void add_provider_for_display (Gdk.Display display, Gtk.StyleProvider provider, uint priority);

        private static Gtk.DropDown dropdown_from_strings(string[] labels) {
            var list = new Gtk.StringList(null);
            for (int i = 0; i < labels.length; i++) {
                list.append(labels[i]);
            }
            return new Gtk.DropDown(list, null);
        }

        private Adw.HeaderBar build_header_bar() {
            var header = new Adw.HeaderBar();

            // Left Box
            var left_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
            var left_sidebar_toggle = Icons.create_lucide_button("panel-left", "Toggle Layers Sidebar (Ctrl+\\)", 16);
            left_sidebar_toggle.clicked.connect(() => {
                left_sidebar.visible = !left_sidebar.visible;
            });
            left_box.append(left_sidebar_toggle);

            var undo_btn = Icons.create_lucide_button("undo-2", "Undo (Ctrl+Z)", 16);
            undo_btn.clicked.connect(() => canvas.undo());
            left_box.append(undo_btn);

            var redo_btn = Icons.create_lucide_button("redo-2", "Redo (Ctrl+Shift+Z)", 16);
            redo_btn.clicked.connect(() => canvas.redo());
            left_box.append(redo_btn);

            header.pack_start(left_box);

            // Right Box
            var right_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);

            var zoom_out_btn = Icons.create_lucide_button("zoom-out", "Zoom Out", 16);
            zoom_out_btn.clicked.connect(() => {
                canvas.zoom_at(canvas.zoom * 0.85, canvas.get_width() / 2.0, canvas.get_height() / 2.0);
            });
            right_box.append(zoom_out_btn);

            zoom_label = new Gtk.Label("100%");
            zoom_label.add_css_class("nova-stat-pill");
            right_box.append(zoom_label);

            var zoom_in_btn = Icons.create_lucide_button("zoom-in", "Zoom In", 16);
            zoom_in_btn.clicked.connect(() => {
                canvas.zoom_at(canvas.zoom * 1.15, canvas.get_width() / 2.0, canvas.get_height() / 2.0);
            });
            right_box.append(zoom_in_btn);

            var shortcuts_btn = Icons.create_lucide_button("help-circle", "Keyboard Shortcuts", 16);
            shortcuts_btn.clicked.connect(() => Shortcuts.show_shortcuts_window(this));
            right_box.append(shortcuts_btn);

            var right_sidebar_toggle = Icons.create_lucide_button("panel-right", "Toggle Properties Inspector (Ctrl+Alt+\\)", 16);
            right_sidebar_toggle.clicked.connect(() => {
                right_sidebar.visible = !right_sidebar.visible;
            });
            right_box.append(right_sidebar_toggle);

            header.pack_end(right_box);
            return header;
        }

        private void build_layout(Adw.HeaderBar header) {
            main_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);

            // 1. Left Sidebar (Layers)
            build_left_sidebar();
            main_box.append(left_sidebar);

            // 2. Center Viewport (Canvas + Floating Dock)
            var center_overlay = new Gtk.Overlay();
            center_overlay.hexpand = true;
            center_overlay.vexpand = true;
            center_overlay.set_child(canvas);

            var dock = build_floating_dock();
            dock.halign = Gtk.Align.CENTER;
            dock.valign = Gtk.Align.END;
            dock.margin_bottom = 10;
            center_overlay.add_overlay(dock);

            rename_entry = new Gtk.Entry();
            rename_entry.visible = false;
            rename_entry.halign = Gtk.Align.START;
            rename_entry.valign = Gtk.Align.START;
            rename_entry.width_chars = 16;
            rename_entry.activate.connect(() => commit_canvas_rename());
            var rename_focus = new Gtk.EventControllerFocus();
            rename_focus.leave.connect(() => commit_canvas_rename());
            rename_entry.add_controller(rename_focus);
            var rename_keys = new Gtk.EventControllerKey();
            rename_keys.key_pressed.connect((keyval, keycode, state) => {
                if (keyval == Gdk.Key.Escape) {
                    cancel_canvas_rename();
                    return true;
                }
                return false;
            });
            rename_entry.add_controller(rename_keys);
            center_overlay.add_overlay(rename_entry);

            main_box.append(center_overlay);

            // 3. Right Sidebar (Inspector)
            build_right_sidebar();
            main_box.append(right_sidebar);

            var toolbar = new Adw.ToolbarView();
            toolbar.add_top_bar(header);
            toolbar.content = main_box;
            this.content = toolbar;
        }

        private void build_left_sidebar() {
            left_sidebar = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            left_sidebar.add_css_class("nova-sidebar");
            left_sidebar.add_css_class("nova-sidebar-left");
            left_sidebar.hexpand = false;
            left_sidebar.vexpand = true;
            left_sidebar.width_request = 260;

            // Header
            var hdr = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            hdr.margin_start = 12;
            hdr.margin_end = 8;
            hdr.margin_top = 8;
            hdr.margin_bottom = 4;

            var title_lbl = new Gtk.Label("LAYERS");
            title_lbl.add_css_class("figma-section-header");
            title_lbl.hexpand = true;
            title_lbl.xalign = 0.0f;
            hdr.append(title_lbl);

            layer_count_label = new Gtk.Label("0");
            layer_count_label.add_css_class("nova-stat-pill");
            hdr.append(layer_count_label);

            toggle_all_vis_btn = Icons.create_lucide_button("eye", "Toggle Visibility of All Layers", 14);
            toggle_all_vis_btn.clicked.connect(() => {
                bool any_visible = canvas.toggle_all_visibility();
                Icons.update_button_icon(toggle_all_vis_btn, any_visible ? "eye" : "eye-off", 14);
            });
            hdr.append(toggle_all_vis_btn);

            left_sidebar.append(hdr);

            // Search entry
            layer_search = new Gtk.SearchEntry();
            layer_search.placeholder_text = "Filter layers…";
            layer_search.margin_start = 8;
            layer_search.margin_end = 8;
            layer_search.margin_bottom = 6;
            layer_search.search_changed.connect(() => refresh_layers());
            left_sidebar.append(layer_search);

            // Layer list in scrolled window
            var scroll = new Gtk.ScrolledWindow();
            scroll.hexpand = true;
            scroll.vexpand = true;
            scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scroll.propagate_natural_width = false;

            layer_list = new Gtk.ListBox();
            layer_list.selection_mode = Gtk.SelectionMode.SINGLE;
            layer_list.row_selected.connect((row) => {
                if (updating_layers || row == null) return;
                unowned Shape? s = row.get_data<Shape>("shape");
                if (s != null) {
                    canvas.select_shape(s);
                }
            });
            layer_list.row_activated.connect((row) => {
                unowned Shape? s = row.get_data<Shape>("shape");
                if (s != null && s.shape_type == ShapeType.FRAME) {
                    begin_layer_rename(row, s);
                }
            });
            scroll.set_child(layer_list);
            left_sidebar.append(scroll);
        }

        private Gtk.Widget build_floating_dock() {
            var dock = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 3);
            dock.add_css_class("nova-dock");

            select_tool_btn = dock_toggle("mouse-pointer-2", "Select & Move (V)");
            hand_tool_btn = dock_toggle("hand", "Hand (H)");
            frame_tool_btn = dock_toggle("frame", "Artboard Frame (F) - Long-press for presets");
            shape_tool_btn = new Gtk.ToggleButton();
            shape_tool_btn.add_css_class("flat");
            shape_tool_btn.add_css_class("nova-tool-btn");
            shape_tool_btn.tooltip_text = "Rectangle (R) - Long-press for shapes";
            shape_icon = Icons.create_lucide_image("square", 18);
            shape_tool_btn.child = shape_icon;
            draw_tool_btn = new Gtk.ToggleButton();
            draw_tool_btn.add_css_class("flat");
            draw_tool_btn.add_css_class("nova-tool-btn");
            draw_tool_btn.tooltip_text = "Pen Tool (P) - Long-press for pencil";
            draw_icon = Icons.create_lucide_image("pen-tool", 18);
            draw_tool_btn.child = draw_icon;
            text_tool_btn = dock_toggle("type", "Typography Text (T)");

            hand_tool_btn.set_group(select_tool_btn);
            frame_tool_btn.set_group(select_tool_btn);
            shape_tool_btn.set_group(select_tool_btn);
            draw_tool_btn.set_group(select_tool_btn);
            text_tool_btn.set_group(select_tool_btn);

            select_tool_btn.toggled.connect(() => {
                if (select_tool_btn.active) activate_tool("select");
            });
            hand_tool_btn.toggled.connect(() => {
                if (hand_tool_btn.active) activate_tool("hand");
            });
            frame_tool_btn.toggled.connect(() => {
                if (frame_tool_btn.active) activate_tool("frame");
            });
            shape_tool_btn.toggled.connect(() => {
                if (shape_tool_btn.active) activate_tool(current_shape_tool);
            });
            draw_tool_btn.toggled.connect(() => {
                if (draw_tool_btn.active) activate_tool(current_draw_tool);
            });
            text_tool_btn.toggled.connect(() => {
                if (text_tool_btn.active) activate_tool("text");
            });
            select_tool_btn.active = true;

            Gtk.MenuButton frame_arrow;
            Gtk.MenuButton shape_arrow;
            Gtk.MenuButton draw_arrow;
            var frame_slot = dock_slot(frame_tool_btn, out frame_arrow, "Artboard Presets");
            var shape_slot = dock_slot(shape_tool_btn, out shape_arrow, "Shape & Line Tools");
            var draw_slot = dock_slot(draw_tool_btn, out draw_arrow, "Drawing Tools");
            frame_popover = build_frame_popover();
            shape_popover = build_tool_popover(true);
            draw_popover = build_tool_popover(false);
            frame_arrow.popover = frame_popover;
            shape_arrow.popover = shape_popover;
            draw_arrow.popover = draw_popover;
            setup_slot_gestures(frame_tool_btn, frame_popover, "frame");
            setup_slot_gestures(shape_tool_btn, shape_popover, "shape");
            setup_slot_gestures(draw_tool_btn, draw_popover, "draw");

            dock.append(select_tool_btn);
            dock.append(hand_tool_btn);
            dock.append(frame_slot);
            dock.append(shape_slot);
            dock.append(draw_slot);
            dock.append(new Gtk.Separator(Gtk.Orientation.VERTICAL));
            dock.append(text_tool_btn);
            return dock;
        }

        private Gtk.ToggleButton dock_toggle(string icon, string tooltip) {
            var btn = Icons.create_lucide_toggle_button(icon, tooltip, 18, "flat nova-tool-btn");
            return btn;
        }

        private Gtk.Box dock_slot(Gtk.ToggleButton tool_btn, out Gtk.MenuButton arrow, string arrow_tip) {
            var slot = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 1);
            slot.add_css_class("nova-dock-slot");
            slot.append(tool_btn);
            arrow = new Gtk.MenuButton();
            arrow.add_css_class("flat");
            arrow.add_css_class("nova-dock-arrow-btn");
            arrow.has_frame = false;
            arrow.direction = Gtk.ArrowType.UP;
            arrow.child = Icons.create_lucide_image("chevron-down", 12);
            arrow.tooltip_text = arrow_tip;
            slot.append(arrow);
            return slot;
        }

        private static bool is_shape_tool(string t) {
            return t == "rect" || t == "ellipse" || t == "polygon" || t == "star" || t == "line" || t == "arrow";
        }

        private static bool is_draw_tool(string t) {
            return t == "pen" || t == "pencil";
        }

        private void activate_tool(string tname) {
            if (updating_tools) return;
            updating_tools = true;

            if (is_shape_tool(tname)) {
                current_shape_tool = tname;
                Icons.update_image_icon(shape_icon, shape_icon_name(tname), 18);
                shape_tool_btn.tooltip_text = shape_tooltip(tname) + " - Long-press for shapes";
                if (!shape_tool_btn.active) shape_tool_btn.active = true;
            } else if (is_draw_tool(tname)) {
                current_draw_tool = tname;
                Icons.update_image_icon(draw_icon, tname == "pen" ? "pen-tool" : "pencil", 18);
                string tip = tname == "pen" ? "Pen Tool (P)" : "Pencil (Shift+P)";
                draw_tool_btn.tooltip_text = tip + " - Long-press for drawing tools";
                if (!draw_tool_btn.active) draw_tool_btn.active = true;
            } else if (tname == "select" && !select_tool_btn.active) {
                select_tool_btn.active = true;
            } else if (tname == "hand" && !hand_tool_btn.active) {
                hand_tool_btn.active = true;
            } else if (tname == "frame" && !frame_tool_btn.active) {
                frame_tool_btn.active = true;
            } else if (tname == "text" && !text_tool_btn.active) {
                text_tool_btn.active = true;
            }

            if (canvas.tool != tname) canvas.set_tool(tname);
            updating_tools = false;
        }

        private static string shape_icon_name(string tname) {
            if (tname == "ellipse") return "circle";
            if (tname == "polygon") return "pentagon";
            if (tname == "star") return "star";
            if (tname == "line") return "minus";
            if (tname == "arrow") return "arrow-up-right";
            return "square";
        }

        private static string shape_tooltip(string tname) {
            if (tname == "ellipse") return "Ellipse (O)";
            if (tname == "polygon") return "Polygon";
            if (tname == "star") return "Star";
            if (tname == "line") return "Line (L)";
            if (tname == "arrow") return "Arrow (A)";
            return "Rectangle (R)";
        }

        private Gtk.Button dock_menu_button(string icon, string label, string badge) {
            var btn = new Gtk.Button();
            btn.add_css_class("flat");
            btn.add_css_class("nova-dock-menu-item");
            var row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
            row.append(Icons.create_lucide_image(icon, 16));
            var lbl = new Gtk.Label(label);
            lbl.xalign = 0;
            lbl.hexpand = true;
            row.append(lbl);
            if (badge.length > 0) {
                var sc = new Gtk.Label(badge);
                sc.add_css_class("nova-shortcut-badge");
                row.append(sc);
            }
            btn.child = row;
            return btn;
        }

        private Gtk.Popover build_frame_popover() {
            var popover = new Gtk.Popover();
            popover.position = Gtk.PositionType.TOP;
            popover.add_css_class("nova-dock-popover");

            var menu = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);
            menu.margin_top = 4;
            menu.margin_bottom = 4;
            menu.margin_start = 4;
            menu.margin_end = 4;

            var custom = dock_menu_button("frame", "Custom Frame", "F");
            custom.clicked.connect(() => {
                popover.popdown();
                activate_tool("frame");
            });
            menu.append(custom);

            var sep = new Gtk.Separator(Gtk.Orientation.HORIZONTAL);
            sep.margin_top = 3;
            sep.margin_bottom = 3;
            menu.append(sep);

            var header = new Gtk.Label("Artboard Presets");
            header.add_css_class("figma-section-header");
            header.xalign = 0;
            header.margin_start = 8;
            header.margin_top = 2;
            menu.append(header);

            string[] names = { "iPhone 15", "Desktop HD", "iPad Pro", "Paper A4", "Social Post" };
            int[] widths = { 393, 1440, 834, 595, 1080 };
            int[] heights = { 852, 900, 1194, 842, 1080 };
            string[] dims = { "393 × 852", "1440 × 900", "834 × 1194", "595 × 842", "1080 × 1080" };
            for (int i = 0; i < names.length; i++) {
                string name = names[i];
                int w = widths[i];
                int h = heights[i];
                var item = dock_menu_button("frame", name, dims[i]);
                item.clicked.connect(() => {
                    popover.popdown();
                    add_preset_frame(w, h);
                });
                menu.append(item);
            }
            popover.child = menu;
            return popover;
        }

        private void add_preset_frame(int width, int height) {
            var frame = new Shape(ShapeType.FRAME);
            frame.frame_preset = "%d×%d".printf(width, height);
            frame.x = 80;
            frame.y = 80;
            frame.w = width;
            frame.h = height;
            Shape added = document.add_shape(frame, true);
            canvas.select_shape(added);
            activate_tool("select");
            canvas.zoom_to_fit();
        }

        private Gtk.Popover build_tool_popover(bool shapes) {
            var popover = new Gtk.Popover();
            popover.position = Gtk.PositionType.TOP;
            popover.add_css_class("nova-dock-popover");

            string[] ids;
            string[] names;
            string[] icons;
            string[] shortcuts;
            if (shapes) {
                ids = { "rect", "ellipse", "polygon", "star", "line", "arrow" };
                names = { "Rectangle", "Ellipse", "Polygon", "Star", "Line", "Arrow" };
                icons = { "square", "circle", "pentagon", "star", "minus", "arrow-up-right" };
                shortcuts = { "R", "O", "", "", "L", "A" };
            } else {
                ids = { "pen", "pencil" };
                names = { "Pen Tool", "Pencil" };
                icons = { "pen-tool", "pencil" };
                shortcuts = { "P", "Shift+P" };
            }

            var menu = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);
            menu.margin_top = 4;
            menu.margin_bottom = 4;
            menu.margin_start = 4;
            menu.margin_end = 4;
            var buttons = new Gtk.Button[ids.length];
            for (int i = 0; i < ids.length; i++) {
                string id = ids[i];
                var item = dock_menu_button(icons[i], names[i], shortcuts[i]);
                item.clicked.connect(() => {
                    popover.popdown();
                    activate_tool(id);
                });
                menu.append(item);
                buttons[i] = item;
            }
            popover.show.connect(() => {
                string cur = shapes ? current_shape_tool : current_draw_tool;
                for (int i = 0; i < ids.length; i++) {
                    if (ids[i] == cur) buttons[i].add_css_class("active");
                    else buttons[i].remove_css_class("active");
                }
            });
            popover.child = menu;
            return popover;
        }

        private string current_slot_tool(string slot) {
            if (slot == "shape") return current_shape_tool;
            if (slot == "draw") return current_draw_tool;
            return "frame";
        }

        private void set_slot_press_active(string slot, bool active) {
            if (slot == "shape") shape_press_active = active;
            else if (slot == "draw") draw_press_active = active;
            else frame_press_active = active;
        }

        private bool slot_press_active(string slot) {
            if (slot == "shape") return shape_press_active;
            if (slot == "draw") return draw_press_active;
            return frame_press_active;
        }

        private void setup_slot_gestures(Gtk.ToggleButton icon_button, Gtk.Popover popover, string slot_name) {
            var long_press = new Gtk.GestureLongPress();
            long_press.touch_only = false;
            long_press.pressed.connect((x, y) => {
                long_press.set_state(Gtk.EventSequenceState.CLAIMED);
                popover.popup();
            });
            icon_button.add_controller(long_press);

            var right_click = new Gtk.GestureClick();
            right_click.button = 3;
            right_click.pressed.connect((n_press, x, y) => {
                right_click.set_state(Gtk.EventSequenceState.CLAIMED);
                popover.popup();
            });
            icon_button.add_controller(right_click);

            var click = new Gtk.GestureClick();
            click.button = 1;
            click.pressed.connect((n_press, x, y) => {
                set_slot_press_active(slot_name, icon_button.active && canvas.tool == current_slot_tool(slot_name));
            });
            click.released.connect((n_press, x, y) => {
                if (slot_press_active(slot_name)) popover.popup();
                set_slot_press_active(slot_name, false);
            });
            icon_button.add_controller(click);
        }

        private void build_right_sidebar() {
            right_sidebar = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            right_sidebar.add_css_class("nova-sidebar");
            right_sidebar.add_css_class("nova-sidebar-right");
            right_sidebar.hexpand = false;
            right_sidebar.vexpand = true;
            right_sidebar.width_request = 320;

            var scroll = new Gtk.ScrolledWindow();
            scroll.hexpand = true;
            scroll.vexpand = true;
            scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scroll.propagate_natural_width = false;

            var content = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
            content.margin_start = 12;
            content.margin_end = 12;
            content.margin_top = 8;
            content.margin_bottom = 16;

            // 1. Alignment Buttons
            build_alignment_section(content);

            // 2. Boolean Operations
            build_boolean_section(content);

            // 3. Vector Node Toolbar (active in node edit mode)
            build_node_edit_section(content);

            // 4. Transform & Dimensions
            build_transform_section(content);

            // 5. Corner Radius
            build_radius_section(content);

            // 6. Layer Opacity
            build_opacity_section(content);

            // 7. Fill Color
            build_fill_section(content);

            // 8. Stroke
            build_stroke_section(content);

            // 9. Typography, polygon, and star
            build_text_section(content);
            build_polygon_section(content);
            build_star_section(content);

            // 10. Canvas Background
            build_canvas_bg_section(content);

            build_actions_section(content);

            // 11. Export Section
            build_export_section(content);

            scroll.set_child(content);
            right_sidebar.append(scroll);
        }

        private void build_alignment_section(Gtk.Box parent) {
            alignment_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 2);
            alignment_box.homogeneous = true;
            alignment_box.hexpand = true;

            string[] icons = {
                "align-start-vertical", "align-center-vertical", "align-end-vertical",
                "align-start-horizontal", "align-center-horizontal", "align-end-horizontal",
                "align-horizontal-distribute-center", "align-vertical-distribute-center"
            };
            string[] tips = {
                "Align Left in Frame", "Align Horizontal Center in Frame", "Align Right in Frame",
                "Align Top in Frame", "Align Vertical Center in Frame", "Align Bottom in Frame",
                "Distribute Horizontal Spacing", "Distribute Vertical Spacing"
            };

            for (int i = 0; i < icons.length; i++) {
                int idx = i;
                var btn = Icons.create_lucide_button(icons[i], tips[i], 16);
                btn.clicked.connect(() => {
                    var sel = canvas.selected_shapes;
                    if (idx == 0) document.align_left(sel);
                    else if (idx == 1) document.align_center(sel);
                    else if (idx == 2) document.align_right(sel);
                    else if (idx == 3) document.align_top(sel);
                    else if (idx == 4) document.align_middle(sel);
                    else if (idx == 5) document.align_bottom(sel);
                    else if (idx == 6) document.distribute_horizontal(sel);
                    else if (idx == 7) document.distribute_vertical(sel);
                });
                alignment_box.append(btn);
            }
            parent.append(alignment_box);
        }

        private void build_boolean_section(Gtk.Box parent) {
            boolean_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
            var u_btn = Icons.create_lucide_button("boolean-union", "Boolean Union (Ctrl+Alt+U)", 16);
            u_btn.clicked.connect(() => canvas.boolean_union());
            boolean_box.append(u_btn);

            var s_btn = Icons.create_lucide_button("boolean-subtract", "Boolean Subtract (Ctrl+Alt+S)", 16);
            s_btn.clicked.connect(() => canvas.boolean_difference());
            boolean_box.append(s_btn);

            var i_btn = Icons.create_lucide_button("boolean-intersect", "Boolean Intersect (Ctrl+Alt+I)", 16);
            i_btn.clicked.connect(() => canvas.boolean_intersection());
            boolean_box.append(i_btn);

            var x_btn = Icons.create_lucide_button("boolean-exclude", "Boolean Exclude (Ctrl+Alt+X)", 16);
            x_btn.clicked.connect(() => canvas.boolean_exclusion());
            boolean_box.append(x_btn);

            parent.append(boolean_box);
        }

        private void build_node_edit_section(Gtk.Box parent) {
            node_edit_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
            node_corner_btn = Icons.create_lucide_button("corner-up-right", "Corner Node", 16);
            node_corner_btn.clicked.connect(() => canvas.set_selected_node_type(NodeType.CORNER));
            node_edit_box.append(node_corner_btn);

            node_smooth_btn = Icons.create_lucide_button("spline", "Smooth Node", 16);
            node_smooth_btn.clicked.connect(() => canvas.set_selected_node_type(NodeType.SMOOTH));
            node_edit_box.append(node_smooth_btn);

            node_asymm_btn = Icons.create_lucide_button("git-branch", "Asymmetric Node", 16);
            node_asymm_btn.clicked.connect(() => canvas.set_selected_node_type(NodeType.ASYMMETRIC));
            node_edit_box.append(node_asymm_btn);

            node_del_btn = Icons.create_lucide_button("trash-2", "Delete Anchor Node", 16);
            node_del_btn.clicked.connect(() => canvas.delete_selected_node());
            node_edit_box.append(node_del_btn);

            var done_btn = Icons.create_lucide_button("check", "Finish Vector Editing", 16);
            done_btn.clicked.connect(() => canvas.exit_node_edit_mode());
            node_edit_box.append(done_btn);

            node_edit_box.visible = false;
            parent.append(node_edit_box);
        }

        private void build_transform_section(Gtk.Box parent) {
            var lbl = new Gtk.Label("TRANSFORM");
            lbl.add_css_class("figma-section-header");
            lbl.xalign = 0.0f;
            parent.append(lbl);

            var grid = new Gtk.Grid();
            grid.column_spacing = 8;
            grid.row_spacing = 6;

            grid.attach(new Gtk.Label("X"), 0, 0);
            x_spin = new Gtk.SpinButton.with_range(-10000, 10000, 1);
            x_spin.value_changed.connect(() => {
                if (updating_inspector || canvas.primary_selected == null) return;
                document.move_shape(canvas.primary_selected, x_spin.value, canvas.primary_selected.y, true);
            });
            grid.attach(x_spin, 1, 0);

            grid.attach(new Gtk.Label("Y"), 2, 0);
            y_spin = new Gtk.SpinButton.with_range(-10000, 10000, 1);
            y_spin.value_changed.connect(() => {
                if (updating_inspector || canvas.primary_selected == null) return;
                document.move_shape(canvas.primary_selected, canvas.primary_selected.x, y_spin.value, true);
            });
            grid.attach(y_spin, 3, 0);

            grid.attach(new Gtk.Label("W"), 0, 1);
            w_spin = new Gtk.SpinButton.with_range(1, 10000, 1);
            w_spin.value_changed.connect(() => {
                if (updating_inspector || canvas.primary_selected == null) return;
                document.resize_shape(canvas.primary_selected, w_spin.value, canvas.primary_selected.h, true);
            });
            grid.attach(w_spin, 1, 1);

            grid.attach(new Gtk.Label("H"), 2, 1);
            h_spin = new Gtk.SpinButton.with_range(1, 10000, 1);
            h_spin.value_changed.connect(() => {
                if (updating_inspector || canvas.primary_selected == null) return;
                document.resize_shape(canvas.primary_selected, canvas.primary_selected.w, h_spin.value, true);
            });
            grid.attach(h_spin, 3, 1);

            grid.attach(new Gtk.Label("°"), 0, 2);
            rot_spin = new Gtk.SpinButton.with_range(0, 360, 1);
            rot_spin.value_changed.connect(() => {
                if (updating_inspector) return;
                canvas.set_selected_rotation(rot_spin.value);
            });
            grid.attach(rot_spin, 1, 2);

            parent.append(grid);
        }

        private void build_radius_section(Gtk.Box parent) {
            var row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            var lbl = new Gtk.Label("CORNER RADIUS");
            lbl.add_css_class("figma-section-header");
            lbl.hexpand = true;
            lbl.xalign = 0.0f;
            row.append(lbl);

            indep_radius_toggle = Icons.create_lucide_toggle_button("maximize-2", "Independent Corners", 14);
            indep_radius_toggle.toggled.connect(() => {
                indep_radius_box.visible = indep_radius_toggle.active;
            });
            row.append(indep_radius_toggle);
            parent.append(row);

            var u_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            radius_scale = new Gtk.Scale.with_range(Gtk.Orientation.HORIZONTAL, 0, 100, 1);
            radius_scale.hexpand = true;
            radius_scale.value_changed.connect(() => {
                if (updating_inspector) return;
                double r = radius_scale.get_value();
                radius_spin.set_value(r);
                canvas.set_selected_corner_radius(CornerRadii.uniform(r));
            });
            u_box.append(radius_scale);

            radius_spin = new Gtk.SpinButton.with_range(0, 500, 1);
            radius_spin.value_changed.connect(() => {
                if (updating_inspector) return;
                double r = radius_spin.get_value();
                radius_scale.set_value(r);
                canvas.set_selected_corner_radius(CornerRadii.uniform(r));
            });
            u_box.append(radius_spin);
            parent.append(u_box);

            indep_radius_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
            tl_spin = new Gtk.SpinButton.with_range(0, 500, 1);
            tr_spin = new Gtk.SpinButton.with_range(0, 500, 1);
            br_spin = new Gtk.SpinButton.with_range(0, 500, 1);
            bl_spin = new Gtk.SpinButton.with_range(0, 500, 1);

            indep_radius_box.append(tl_spin);
            indep_radius_box.append(tr_spin);
            indep_radius_box.append(br_spin);
            indep_radius_box.append(bl_spin);

            var apply_indep = new Gtk.Button.with_label("Apply");
            apply_indep.clicked.connect(() => {
                var cr = CornerRadii(tl_spin.value, tr_spin.value, br_spin.value, bl_spin.value);
                canvas.set_selected_corner_radius(cr);
            });
            indep_radius_box.append(apply_indep);

            indep_radius_box.visible = false;
            parent.append(indep_radius_box);
        }

        private void build_opacity_section(Gtk.Box parent) {
            var lbl = new Gtk.Label("OPACITY");
            lbl.add_css_class("figma-section-header");
            lbl.xalign = 0.0f;
            parent.append(lbl);

            var row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            opacity_scale = new Gtk.Scale.with_range(Gtk.Orientation.HORIZONTAL, 0, 100, 1);
            opacity_scale.hexpand = true;
            opacity_scale.value_changed.connect(() => {
                if (updating_inspector) return;
                double val = opacity_scale.get_value();
                opacity_spin.set_value(val);
                canvas.set_selected_opacity(val / 100.0);
            });
            row.append(opacity_scale);

            opacity_spin = new Gtk.SpinButton.with_range(0, 100, 1);
            opacity_spin.value_changed.connect(() => {
                if (updating_inspector) return;
                double val = opacity_spin.get_value();
                opacity_scale.set_value(val);
                canvas.set_selected_opacity(val / 100.0);
            });
            row.append(opacity_spin);
            parent.append(row);
        }

        private void build_fill_section(Gtk.Box parent) {
            var lbl = new Gtk.Label("FILL");
            lbl.add_css_class("figma-section-header");
            lbl.xalign = 0.0f;
            parent.append(lbl);

            var row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            fill_swatch = new Gtk.Button();
            fill_swatch.add_css_class("nova-color-chip");
            fill_swatch.tooltip_text = "Open Fill Color Picker";
            fill_chip = new Gtk.DrawingArea();
            fill_chip.set_size_request(22, 22);
            fill_chip.set_draw_func((area, cr, w, h) => paint_chip(cr, w, h, fill_chip_color));
            fill_swatch.child = fill_chip;
            fill_swatch.clicked.connect(() => open_color_picker(false));
            row.append(fill_swatch);

            fill_hex_entry = new Gtk.Entry();
            fill_hex_entry.add_css_class("nova-hex-entry");
            fill_hex_entry.activate.connect(() => {
                Color? c = Color.from_hex(fill_hex_entry.text);
                if (c != null) {
                    for (uint i = 0; i < canvas.selected_shapes.length; i++) {
                        document.set_color(canvas.selected_shapes[i], c, (i == 0));
                    }
                    update_inspector();
                }
            });
            row.append(fill_hex_entry);

            eyedropper_btn = Icons.create_lucide_button("pipette", "Desktop Eyedropper (Pick Fill Color)", 16);
            eyedropper_btn.clicked.connect(() => {
                Eyedropper.pick_screen_color((c) => {
                    for (uint i = 0; i < canvas.selected_shapes.length; i++) {
                        document.set_color(canvas.selected_shapes[i], c, (i == 0));
                    }
                    update_inspector();
                });
            });
            row.append(eyedropper_btn);
            parent.append(row);

            // Palette Swatches
            var pal_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
            Color[] pal = {
                Color.rgb(0.20, 0.60, 0.85), Color.rgb(0.90, 0.35, 0.30),
                Color.rgb(0.95, 0.75, 0.25), Color.rgb(0.30, 0.70, 0.40),
                Color.rgb(0.55, 0.40, 0.80), Color.rgb(0.20, 0.20, 0.22)
            };
            for (int i = 0; i < pal.length; i++) {
                Color pc = pal[i];
                var s = new Gtk.Button();
                s.add_css_class("nova-swatch");
                s.add_css_class("nova-swatch-%d".printf(i));
                s.clicked.connect(() => {
                    for (uint j = 0; j < canvas.selected_shapes.length; j++) {
                        document.set_color(canvas.selected_shapes[j], pc, (j == 0));
                    }
                    update_inspector();
                });
                pal_box.append(s);
            }
            parent.append(pal_box);

            // Document Colors
            var doc_hdr = new Gtk.Label("DOCUMENT COLORS");
            doc_hdr.add_css_class("figma-section-header");
            doc_hdr.xalign = 0.0f;
            parent.append(doc_hdr);

            doc_palette_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
            parent.append(doc_palette_box);
        }

        private void build_stroke_section(Gtk.Box parent) {
            var lbl = new Gtk.Label("STROKE");
            lbl.add_css_class("figma-section-header");
            lbl.xalign = 0.0f;
            parent.append(lbl);

            var row1 = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            stroke_swatch = new Gtk.Button();
            stroke_swatch.add_css_class("nova-color-chip");
            stroke_swatch.tooltip_text = "Open Stroke Color Picker";
            stroke_chip = new Gtk.DrawingArea();
            stroke_chip.set_size_request(22, 22);
            stroke_chip.set_draw_func((area, cr, w, h) => paint_chip(cr, w, h, stroke_chip_color));
            stroke_swatch.child = stroke_chip;
            stroke_swatch.clicked.connect(() => open_color_picker(true));
            row1.append(stroke_swatch);

            stroke_hex_entry = new Gtk.Entry();
            stroke_hex_entry.add_css_class("nova-hex-entry");
            stroke_hex_entry.activate.connect(() => {
                Color? c = Color.from_hex(stroke_hex_entry.text);
                if (c != null) {
                    canvas.set_selected_stroke(true, c, null, null, null, null, null);
                    update_inspector();
                }
            });
            row1.append(stroke_hex_entry);

            var stroke_dropper = Icons.create_lucide_button("pipette", "Desktop Eyedropper (Pick Stroke Color)", 16);
            stroke_dropper.clicked.connect(() => {
                Eyedropper.pick_screen_color((c) => {
                    canvas.set_selected_stroke(true, c, null, null, null, null, null);
                    update_inspector();
                });
            });
            row1.append(stroke_dropper);

            stroke_width_spin = new Gtk.SpinButton.with_range(0, 100, 1);
            stroke_width_spin.value_changed.connect(() => {
                if (updating_inspector) return;
                double w = stroke_width_spin.value;
                canvas.set_selected_stroke(w > 0, null, w, null, null, null, null);
            });
            row1.append(stroke_width_spin);
            parent.append(row1);

            // Stroke Options Grid
            var grid = new Gtk.Grid();
            grid.column_spacing = 6;
            grid.row_spacing = 6;

            grid.attach(new Gtk.Label("Dash"), 0, 0);
            stroke_dash_dd = dropdown_from_strings({ "Solid", "Dashed", "Dotted" });
            stroke_dash_dd.notify["selected"].connect(() => {
                if (updating_inspector) return;
                var dash = (stroke_dash_dd.selected == 1) ? StrokeDash.DASHED :
                           ((stroke_dash_dd.selected == 2) ? StrokeDash.DOTTED : StrokeDash.SOLID);
                canvas.set_selected_stroke(null, null, null, dash, null, null, null);
            });
            grid.attach(stroke_dash_dd, 1, 0);

            grid.attach(new Gtk.Label("Align"), 2, 0);
            stroke_align_dd = dropdown_from_strings({ "Center", "Inside", "Outside" });
            stroke_align_dd.notify["selected"].connect(() => {
                if (updating_inspector) return;
                var align = (stroke_align_dd.selected == 1) ? StrokeAlign.INSIDE :
                            ((stroke_align_dd.selected == 2) ? StrokeAlign.OUTSIDE : StrokeAlign.CENTER);
                canvas.set_selected_stroke(null, null, null, null, align, null, null);
            });
            grid.attach(stroke_align_dd, 3, 0);

            grid.attach(new Gtk.Label("Cap"), 0, 1);
            stroke_cap_dd = dropdown_from_strings({ "Butt", "Round", "Square" });
            stroke_cap_dd.notify["selected"].connect(() => {
                if (updating_inspector) return;
                var cap = (stroke_cap_dd.selected == 1) ? StrokeCap.ROUND :
                          ((stroke_cap_dd.selected == 2) ? StrokeCap.SQUARE : StrokeCap.BUTT);
                canvas.set_selected_stroke(null, null, null, null, null, cap, null);
            });
            grid.attach(stroke_cap_dd, 1, 1);

            grid.attach(new Gtk.Label("Join"), 2, 1);
            stroke_join_dd = dropdown_from_strings({ "Miter", "Round", "Bevel" });
            stroke_join_dd.notify["selected"].connect(() => {
                if (updating_inspector) return;
                var join = (stroke_join_dd.selected == 1) ? StrokeJoin.ROUND :
                           ((stroke_join_dd.selected == 2) ? StrokeJoin.BEVEL : StrokeJoin.MITER);
                canvas.set_selected_stroke(null, null, null, null, null, null, join);
            });
            grid.attach(stroke_join_dd, 3, 1);

            parent.append(grid);
        }

        private void build_text_section(Gtk.Box parent) {
            text_section = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
            var lbl = new Gtk.Label("TYPOGRAPHY");
            lbl.add_css_class("figma-section-header");
            lbl.xalign = 0.0f;
            text_section.append(lbl);

            text_entry = new Gtk.Entry();
            text_entry.placeholder_text = "Text content...";
            text_entry.changed.connect(() => {
                if (updating_inspector) return;
                if (canvas.primary_selected != null && canvas.primary_selected.shape_type == ShapeType.TEXT) {
                    canvas.primary_selected.text = text_entry.text;
                    canvas.queue_draw();
                }
            });
            text_section.append(text_entry);

            var row1 = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            font_family_entry = new Gtk.Entry();
            font_family_entry.placeholder_text = "Font Family (e.g. Sans)";
            font_family_entry.hexpand = true;
            font_family_entry.activate.connect(() => {
                if (canvas.primary_selected != null && canvas.primary_selected.shape_type == ShapeType.TEXT) {
                    canvas.primary_selected.font_family = font_family_entry.text;
                    canvas.queue_draw();
                }
            });
            row1.append(font_family_entry);

            font_size_spin = new Gtk.SpinButton.with_range(6, 200, 1);
            font_size_spin.value_changed.connect(() => {
                if (updating_inspector) return;
                if (canvas.primary_selected != null && canvas.primary_selected.shape_type == ShapeType.TEXT) {
                    canvas.primary_selected.font_size = font_size_spin.value;
                    canvas.queue_draw();
                }
            });
            row1.append(font_size_spin);
            text_section.append(row1);

            var row2 = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            font_weight_dd = dropdown_from_strings({ "Normal", "Semibold", "Bold" });
            font_weight_dd.notify["selected"].connect(() => {
                if (updating_inspector) return;
                if (canvas.primary_selected != null && canvas.primary_selected.shape_type == ShapeType.TEXT) {
                    string[] w = { "normal", "semibold", "bold" };
                    canvas.primary_selected.font_weight = w[font_weight_dd.selected];
                    canvas.queue_draw();
                }
            });
            row2.append(font_weight_dd);

            font_slant_dd = dropdown_from_strings({ "Normal", "Italic" });
            font_slant_dd.notify["selected"].connect(() => {
                if (updating_inspector) return;
                if (canvas.primary_selected != null && canvas.primary_selected.shape_type == ShapeType.TEXT) {
                    canvas.primary_selected.font_slant = font_slant_dd.selected == 1 ? "italic" : "normal";
                    canvas.queue_draw();
                }
            });
            row2.append(font_slant_dd);

            text_align_dd = dropdown_from_strings({ "Left", "Center", "Right" });
            text_align_dd.notify["selected"].connect(() => {
                if (updating_inspector) return;
                if (canvas.primary_selected != null && canvas.primary_selected.shape_type == ShapeType.TEXT) {
                    string[] a = { "left", "center", "right" };
                    canvas.primary_selected.text_align = a[text_align_dd.selected];
                    canvas.queue_draw();
                }
            });
            row2.append(text_align_dd);
            text_section.append(row2);

            text_section.visible = false;
            parent.append(text_section);
        }

        private void build_polygon_section(Gtk.Box parent) {
            polygon_section = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            var lbl = new Gtk.Label("Sides");
            lbl.add_css_class("dim-label");
            polygon_section.append(lbl);
            polygon_sides_spin = new Gtk.SpinButton.with_range(3, 32, 1);
            polygon_sides_spin.value_changed.connect(() => {
                if (updating_inspector) return;
                Shape? s = canvas.primary_selected;
                if (s != null && s.shape_type == ShapeType.POLYGON) {
                    document.checkpoint();
                    s.sides = (int) polygon_sides_spin.value;
                    document.note_changed();
                }
            });
            polygon_section.append(polygon_sides_spin);
            polygon_section.visible = false;
            parent.append(polygon_section);
        }

        private void build_star_section(Gtk.Box parent) {
            star_section = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
            var points_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            var pts = new Gtk.Label("Points");
            pts.add_css_class("dim-label");
            points_row.append(pts);
            star_points_spin = new Gtk.SpinButton.with_range(3, 32, 1);
            star_points_spin.value_changed.connect(() => apply_star());
            points_row.append(star_points_spin);
            star_section.append(points_row);

            var ratio_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            var ratio = new Gtk.Label("Ratio");
            ratio.add_css_class("dim-label");
            ratio_row.append(ratio);
            star_ratio_scale = new Gtk.Scale.with_range(Gtk.Orientation.HORIZONTAL, 10, 90, 1);
            star_ratio_scale.hexpand = true;
            star_ratio_scale.value_changed.connect(() => apply_star());
            ratio_row.append(star_ratio_scale);
            star_section.append(ratio_row);
            star_section.visible = false;
            parent.append(star_section);
        }

        private void apply_star() {
            if (updating_inspector) return;
            Shape? s = canvas.primary_selected;
            if (s == null || s.shape_type != ShapeType.STAR) return;
            document.checkpoint();
            s.points_count = (int) star_points_spin.value;
            s.inner_ratio = star_ratio_scale.get_value() / 100.0;
            document.note_changed();
        }

        private void build_actions_section(Gtk.Box parent) {
            var row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            var dup = new Gtk.Button.with_label("Duplicate");
            dup.hexpand = true;
            dup.clicked.connect(() => canvas.duplicate_selected());
            row.append(dup);
            var del = new Gtk.Button.with_label("Delete");
            del.hexpand = true;
            del.add_css_class("destructive-action");
            del.clicked.connect(() => canvas.delete_selected());
            row.append(del);
            parent.append(row);
        }

        private void build_canvas_bg_section(Gtk.Box parent) {
            var lbl = new Gtk.Label("CANVAS BACKGROUND");
            lbl.add_css_class("figma-section-header");
            lbl.xalign = 0.0f;
            parent.append(lbl);

            var row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
            string[] bgs = { "theme", "white", "gray", "dark", "slate" };
            string[] tips = { "Auto (Theme)", "Pure White", "Soft Gray", "Figma Dark", "Slate" };

            for (int i = 0; i < bgs.length; i++) {
                string bg = bgs[i];
                var btn = new Gtk.Button();
                btn.add_css_class("nova-bg-chip");
                btn.add_css_class("nova-bg-chip-" + bg);
                btn.tooltip_text = tips[i];
                btn.clicked.connect(() => canvas.set_canvas_background(bg));
                row.append(btn);
            }
            parent.append(row);
        }

        private void build_export_section(Gtk.Box parent) {
            var lbl = new Gtk.Label("EXPORT");
            lbl.add_css_class("figma-section-header");
            lbl.xalign = 0.0f;
            parent.append(lbl);

            var row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            export_scale_dd = dropdown_from_strings({ "1x", "2x", "3x" });
            export_scale_dd.hexpand = true;
            row.append(export_scale_dd);

            export_fmt_dd = dropdown_from_strings({ "PNG", "JPG", "WEBP", "SVG" });
            export_fmt_dd.hexpand = true;
            export_fmt_dd.notify["selected"].connect(() => {
                export_scale_dd.sensitive = export_fmt_dd.selected != 3;
            });
            row.append(export_fmt_dd);
            parent.append(row);

            export_preview_area = new Gtk.DrawingArea();
            export_preview_area.set_size_request(-1, 90);
            export_preview_area.add_css_class("nova-export-preview");
            export_preview_area.set_draw_func((area, cr, w, h) => {
                var shapes_to_draw = export_targets();
                Export.paint_export_preview(cr, shapes_to_draw, w, h);
            });
            parent.append(export_preview_area);

            export_button = new Gtk.Button.with_label("Export");
            export_button.add_css_class("suggested-action");
            export_button.clicked.connect(() => do_export());
            parent.append(export_button);
        }

        private GLib.GenericArray<Shape> export_targets() {
            if (canvas.selected_shapes.length == 0) {
                return new GLib.GenericArray<Shape>();
            }
            return Svg.collect_export_shapes(document.shapes, canvas.selected_shapes);
        }

        private void do_export() {
            var shapes = export_targets();
            if (shapes.length == 0) {
                show_export_error("Select a shape or artboard to export.");
                return;
            }

            int fmt_index = (int) export_fmt_dd.selected;
            string[] labels = { "PNG", "JPG", "WEBP", "SVG" };
            string[] extensions = { "png", "jpg", "webp", "svg" };
            string[] kinds = { "png", "jpeg", "webp", "svg" };
            string kind = kinds[fmt_index];
            int scale = kind == "svg" ? 1 : (int) export_scale_dd.selected + 1;
            string suffix = scale == 1 ? "" : "@%dx".printf(scale);
            string stem = Svg.export_basename(shapes);

            var dialog = new Gtk.FileDialog();
            dialog.title = "Export %s".printf(labels[fmt_index]);
            dialog.initial_name = "%s%s.%s".printf(stem, suffix, extensions[fmt_index]);
            dialog.save.begin(this, null, (obj, res) => {
                try {
                    GLib.File? file = dialog.save.end(res);
                    if (file == null) return;
                    string path = file.get_path();
                    if (kind == "svg") {
                        GLib.FileUtils.set_contents(path, Svg.shapes_to_svg(shapes));
                    } else {
                        Export.save_bitmap(shapes, path, kind, scale);
                    }
                } catch (GLib.Error e) {
                    if (e.message != null && !e.message.contains("dismissed")) {
                        show_export_error(e.message);
                    }
                }
            });
        }

        private void show_export_error(string message) {
            var dialog = new Adw.AlertDialog("Export failed", message);
            dialog.add_response("ok", "OK");
            dialog.default_response = "ok";
            dialog.present(this);
        }

        private void wire_canvas_events() {
            canvas.selection_changed.connect(() => {
                update_inspector();
                refresh_layers();
            });
            canvas.zoom_changed.connect((z) => {
                zoom_label.label = "%d%%".printf(canvas.get_zoom_percentage());
            });
            canvas.geometry_changed.connect(() => {
                update_inspector();
                refresh_layers();
            });
            canvas.frame_renamed.connect((frame) => start_canvas_rename(frame));
            canvas.tool_changed.connect((t) => {
                activate_tool(t);
                update_inspector();
            });
            document.changed.connect(() => {
                export_preview_area.queue_draw();
                update_doc_colors();
            });
        }

        private void update_inspector() {
            updating_inspector = true;
            Shape? s = canvas.primary_selected;

            node_edit_box.visible = canvas.is_in_node_edit_mode();
            text_section.visible = (s != null && s.shape_type == ShapeType.TEXT);
            polygon_section.visible = (s != null && s.shape_type == ShapeType.POLYGON);
            star_section.visible = (s != null && s.shape_type == ShapeType.STAR);

            if (s != null) {
                x_spin.value = s.x;
                y_spin.value = s.y;
                w_spin.value = s.w;
                h_spin.value = s.h;
                rot_spin.value = s.rotation;

                CornerRadii radii = Geometry.get_corner_radii(s);
                radius_scale.set_value(radii.tl);
                radius_spin.value = radii.tl;
                tl_spin.value = radii.tl;
                tr_spin.value = radii.tr;
                br_spin.value = radii.br;
                bl_spin.value = radii.bl;

                opacity_scale.set_value(s.opacity * 100.0);
                opacity_spin.value = s.opacity * 100.0;

                fill_hex_entry.text = s.color.to_hex();
                fill_chip_color = s.color;
                fill_chip.queue_draw();
                stroke_hex_entry.text = s.stroke_color.to_hex();
                stroke_chip_color = s.stroke_color;
                stroke_chip.queue_draw();
                stroke_width_spin.value = s.stroke_width;

                stroke_dash_dd.selected = (s.stroke_dash == StrokeDash.DASHED) ? 1 : ((s.stroke_dash == StrokeDash.DOTTED) ? 2 : 0);
                stroke_align_dd.selected = (s.stroke_align == StrokeAlign.INSIDE) ? 1 : ((s.stroke_align == StrokeAlign.OUTSIDE) ? 2 : 0);
                stroke_cap_dd.selected = (s.stroke_cap == StrokeCap.ROUND) ? 1 : ((s.stroke_cap == StrokeCap.SQUARE) ? 2 : 0);
                stroke_join_dd.selected = (s.stroke_join == StrokeJoin.ROUND) ? 1 : ((s.stroke_join == StrokeJoin.BEVEL) ? 2 : 0);

                if (s.shape_type == ShapeType.TEXT) {
                    text_entry.text = s.text;
                    font_family_entry.text = s.font_family;
                    font_size_spin.value = s.font_size;
                    font_weight_dd.selected = (s.font_weight.down() == "bold") ? 2 : ((s.font_weight.down() == "semibold") ? 1 : 0);
                    font_slant_dd.selected = s.font_slant.down() == "italic" ? 1 : 0;
                    text_align_dd.selected = (s.text_align.down() == "center") ? 1 : ((s.text_align.down() == "right") ? 2 : 0);
                } else if (s.shape_type == ShapeType.POLYGON) {
                    polygon_sides_spin.value = s.sides;
                } else if (s.shape_type == ShapeType.STAR) {
                    star_points_spin.value = s.points_count;
                    star_ratio_scale.set_value(s.inner_ratio * 100.0);
                }
            }
            var targets = export_targets();
            export_button.label = targets.length == 0 ? "Export" : "Export %s".printf(Svg.export_basename(targets));
            export_preview_area.queue_draw();
            updating_inspector = false;
        }

        private void update_doc_colors() {
            while (doc_palette_box.get_first_child() != null) {
                doc_palette_box.remove(doc_palette_box.get_first_child());
            }
            var colors = Color.extract_document_colors(document.shapes);
            if (colors.length == 0) {
                var empty = new Gtk.Label("No document colors");
                empty.add_css_class("dim-label");
                doc_palette_box.append(empty);
                return;
            }
            for (uint i = 0; i < colors.length && i < 12; i++) {
                Color c = colors[i];
                var b = new Gtk.Button();
                b.add_css_class("nova-swatch");
                var chip = new Gtk.DrawingArea();
                chip.set_size_request(18, 18);
                chip.set_draw_func((area, cr, w, h) => paint_chip(cr, w, h, c));
                b.child = chip;
                b.clicked.connect(() => {
                    for (uint j = 0; j < canvas.selected_shapes.length; j++) {
                        document.set_color(canvas.selected_shapes[j], c, (j == 0));
                    }
                    update_inspector();
                });
                doc_palette_box.append(b);
            }
        }

        private static void paint_chip(Cairo.Context cr, int w, int h, Color color) {
            cr.set_source_rgba(color.red, color.green, color.blue, color.alpha);
            cr.rectangle(0, 0, w, h);
            cr.fill();
        }

        private void open_color_picker(bool stroke) {
            Shape? s = canvas.primary_selected;
            if (s == null) return;
            Color current = stroke ? s.stroke_color : s.color;
            var rgba = Gdk.RGBA();
            rgba.red = (float) current.red;
            rgba.green = (float) current.green;
            rgba.blue = (float) current.blue;
            rgba.alpha = (float) current.alpha;
            var dialog = new Gtk.ColorDialog();
            dialog.choose_rgba.begin(this, rgba, null, (obj, res) => {
                try {
                    Gdk.RGBA? chosen = dialog.choose_rgba.end(res);
                    if (chosen == null) return;
                    var picked = Color.rgba(chosen.red, chosen.green, chosen.blue, chosen.alpha);
                    if (stroke) {
                        canvas.set_selected_stroke(true, picked, null, null, null, null, null);
                    } else {
                        for (uint i = 0; i < canvas.selected_shapes.length; i++) {
                            document.set_color(canvas.selected_shapes[i], picked, i == 0);
                        }
                        canvas.pen_color = picked;
                    }
                    update_inspector();
                } catch (GLib.Error e) {
                }
            });
        }

        private void refresh_layers() {
            updating_layers = true;
            while (layer_list.get_first_child() != null) {
                layer_list.remove(layer_list.get_first_child());
            }

            layer_count_label.label = "%u".printf(document.shapes.length);
            string filter_text = layer_search.text.down().strip();
            Gtk.ListBoxRow? selected_row = null;

            if (filter_text.length > 0) {
                for (int i = (int) document.shapes.length - 1; i >= 0; i--) {
                    unowned Shape s = document.shapes[i];
                    if (!s.name.down().contains(filter_text)) continue;
                    var row = make_layer_row(s, false, false);
                    if (canvas.primary_selected == s) selected_row = row;
                    layer_list.append(row);
                }
            } else {
                var child_ids = new GLib.HashTable<string, bool>(GLib.str_hash, GLib.str_equal);
                for (uint i = 0; i < document.shapes.length; i++) {
                    if (document.shapes[i].shape_type != ShapeType.FRAME) continue;
                    var children = document.get_frame_children(document.shapes[i]);
                    for (uint c = 0; c < children.length; c++) {
                        child_ids.insert(children[c].id, true);
                    }
                }
                for (int i = (int) document.shapes.length - 1; i >= 0; i--) {
                    unowned Shape s = document.shapes[i];
                    if (s.shape_type != ShapeType.FRAME && child_ids.contains(s.id)) continue;
                    bool is_frame = s.shape_type == ShapeType.FRAME;
                    var row = make_layer_row(s, is_frame, false);
                    if (canvas.primary_selected == s) selected_row = row;
                    layer_list.append(row);
                    if (!is_frame || collapsed_frames.contains(s.id)) continue;
                    var children = document.get_frame_children(s);
                    for (int c = (int) children.length - 1; c >= 0; c--) {
                        var child_row = make_layer_row(children[c], false, true);
                        if (canvas.primary_selected == children[c]) selected_row = child_row;
                        layer_list.append(child_row);
                    }
                }
            }

            if (layer_list.get_first_child() == null) {
                var empty = new Gtk.ListBoxRow();
                empty.selectable = false;
                empty.activatable = false;
                var label = new Gtk.Label("No layers");
                label.add_css_class("dim-label");
                label.margin_top = 12;
                label.margin_bottom = 12;
                empty.child = label;
                layer_list.append(empty);
            } else if (selected_row != null) {
                layer_list.select_row(selected_row);
            }
            updating_layers = false;
        }

        private Gtk.ListBoxRow make_layer_row(Shape shape, bool is_frame, bool nested) {
            var row = new Gtk.ListBoxRow();
            row.set_data("shape", shape);
            if (is_frame) row.add_css_class("nova-frame-row");
            if (nested) row.add_css_class("nova-tree-child-row");

            var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            box.margin_start = nested ? 22 : 6;
            box.margin_end = 6;
            box.margin_top = 4;
            box.margin_bottom = 4;

            if (is_frame) {
                var children = document.get_frame_children(shape);
                if (children.length > 0) {
                    bool collapsed = collapsed_frames.contains(shape.id);
                    string fid = shape.id;
                    var exp = Icons.create_lucide_button(collapsed ? "chevron-right" : "chevron-down", "Collapse/Expand Artboard", 14, "flat");
                    exp.clicked.connect(() => {
                        if (collapsed_frames.contains(fid)) collapsed_frames.remove(fid);
                        else collapsed_frames.insert(fid, true);
                        refresh_layers();
                    });
                    box.append(exp);
                }
            } else {
                var chip = new Gtk.DrawingArea();
                chip.set_size_request(10, 10);
                chip.add_css_class("nova-swatch");
                Color paint = shape.color;
                chip.set_draw_func((area, cr, w, h) => paint_chip(cr, w, h, paint));
                box.append(chip);
            }

            box.append(Icons.create_lucide_image(layer_glyph(shape), 14));

            var name = new Gtk.Label(shape.name);
            name.add_css_class("heading");
            name.xalign = 0.0f;
            name.hexpand = true;
            name.ellipsize = Pango.EllipsizeMode.END;
            name.tooltip_text = shape.name;
            if (!shape.visible) name.add_css_class("dim-label");
            box.append(name);

            var dim = new Gtk.Label("%d×%d".printf((int) shape.w, (int) shape.h));
            dim.add_css_class("dim-label");
            box.append(dim);

            var lock_btn = Icons.create_lucide_button(shape.locked ? "lock" : "unlock", shape.locked ? "Unlock" : "Lock", 14, "nova-layer-vis-btn");
            lock_btn.clicked.connect(() => {
                document.set_shape_locked(shape, !shape.locked, true);
                refresh_layers();
            });
            box.append(lock_btn);

            string vis_tip = shape.visible ? (is_frame ? "Hide Artboard" : "Hide Layer") : (is_frame ? "Show Artboard" : "Show Layer");
            var vis_btn = Icons.create_lucide_button(shape.visible ? "eye" : "eye-off", vis_tip, 14, "nova-layer-vis-btn");
            vis_btn.clicked.connect(() => {
                document.set_shape_visibility(shape, !shape.visible, true);
                refresh_layers();
            });
            box.append(vis_btn);

            row.child = box;
            return row;
        }

        private static string layer_glyph(Shape shape) {
            switch (shape.shape_type) {
                case ShapeType.FRAME: return "frame";
                case ShapeType.ELLIPSE: return "circle";
                case ShapeType.TEXT: return "type";
                case ShapeType.PATH: return "spline";
                case ShapeType.GROUP: return "folder";
                case ShapeType.POLYGON: return "pentagon";
                case ShapeType.STAR: return "star";
                case ShapeType.LINE: return "minus";
                case ShapeType.ARROW: return "arrow-up-right";
                case ShapeType.PENCIL: return "pencil";
                case ShapeType.IMAGE: return "image";
                default: return "square";
            }
        }

        private void begin_layer_rename(Gtk.ListBoxRow row, Shape shape) {
            var box = row.child as Gtk.Box;
            if (box == null) return;
            Gtk.Label? label = null;
            for (Gtk.Widget? child = box.get_first_child(); child != null; child = child.get_next_sibling()) {
                var candidate = child as Gtk.Label;
                if (candidate != null && candidate.has_css_class("heading")) {
                    label = candidate;
                    break;
                }
            }
            if (label == null) return;
            var entry = new Gtk.Entry();
            entry.text = shape.name;
            entry.hexpand = true;
            Gtk.Widget? previous = label.get_prev_sibling();
            box.remove(label);
            if (previous == null) box.prepend(entry);
            else box.insert_child_after(entry, previous);
            layer_rename_entry = entry;
            layer_rename_shape = shape;
            layer_rename_done = false;
            entry.activate.connect(() => finish_layer_rename(false));
            var focus = new Gtk.EventControllerFocus();
            focus.leave.connect(() => finish_layer_rename(false));
            entry.add_controller(focus);
            var keys = new Gtk.EventControllerKey();
            keys.key_pressed.connect((keyval, keycode, state) => {
                if (keyval == Gdk.Key.Escape) {
                    finish_layer_rename(true);
                    return true;
                }
                return false;
            });
            entry.add_controller(keys);
            entry.grab_focus();
            entry.select_region(0, -1);
        }

        private void finish_layer_rename(bool cancel) {
            if (layer_rename_done || layer_rename_shape == null || layer_rename_entry == null) return;
            layer_rename_done = true;
            if (!cancel) {
                document.set_shape_name(layer_rename_shape, layer_rename_entry.text);
            }
            layer_rename_shape = null;
            layer_rename_entry = null;
            refresh_layers();
            canvas.queue_draw();
        }

        private void start_canvas_rename(Shape frame) {
            rename_target = frame;
            rename_open = true;
            double wx, wy;
            canvas.to_widget(frame.x, frame.y, out wx, out wy);
            rename_entry.text = frame.name;
            rename_entry.margin_start = (int) Math.fmax(0.0, wx);
            rename_entry.margin_top = (int) Math.fmax(0.0, wy - 28.0);
            rename_entry.visible = true;
            rename_entry.grab_focus();
            rename_entry.select_region(0, -1);
        }

        private void cancel_canvas_rename() {
            rename_open = false;
            rename_target = null;
            rename_entry.visible = false;
        }

        private void commit_canvas_rename() {
            if (!rename_open || rename_target == null) return;
            Shape frame = rename_target;
            string text = rename_entry.text;
            rename_open = false;
            rename_target = null;
            rename_entry.visible = false;
            document.set_shape_name(frame, text);
            refresh_layers();
            canvas.queue_draw();
        }

        private void add_keyboard_controller() {
            var key_ctrl = new Gtk.EventControllerKey();
            key_ctrl.key_pressed.connect((keyval, keycode, state) => {
                bool ctrl = (state & Gdk.ModifierType.CONTROL_MASK) != 0;
                bool shift = (state & Gdk.ModifierType.SHIFT_MASK) != 0;
                bool alt = (state & Gdk.ModifierType.ALT_MASK) != 0;

                canvas.alt_held = alt;
                canvas.shift_held = shift;

                if (keyval == Gdk.Key.F1 || (ctrl && (keyval == Gdk.Key.question || keyval == Gdk.Key.slash))) {
                    Shortcuts.show_shortcuts_window(this);
                    return true;
                }

                if (ctrl && !shift && !alt) {
                    if (keyval == Gdk.Key.z || keyval == Gdk.Key.Z) {
                        canvas.undo(); return true;
                    }
                    if (keyval == Gdk.Key.c || keyval == Gdk.Key.C) {
                        canvas.copy(); return true;
                    }
                    if (keyval == Gdk.Key.x || keyval == Gdk.Key.X) {
                        canvas.cut(); return true;
                    }
                    if (keyval == Gdk.Key.v || keyval == Gdk.Key.V) {
                        canvas.paste(); return true;
                    }
                    if (keyval == Gdk.Key.d || keyval == Gdk.Key.D) {
                        canvas.duplicate_selected(); return true;
                    }
                    if (keyval == Gdk.Key.g || keyval == Gdk.Key.G) {
                        canvas.group_selected(); return true;
                    }
                    if (keyval == Gdk.Key.a || keyval == Gdk.Key.A) {
                        canvas.select_all(); return true;
                    }
                    if (keyval == '0') {
                        canvas.zoom_to_fit(); return true;
                    }
                    if (keyval == '1') {
                        canvas.zoom_to_100(); return true;
                    }
                    if (keyval == Gdk.Key.bracketright) {
                        canvas.bring_forward(); return true;
                    }
                    if (keyval == Gdk.Key.bracketleft) {
                        canvas.send_backward(); return true;
                    }
                }

                if (ctrl && shift) {
                    if (keyval == Gdk.Key.z || keyval == Gdk.Key.Z) {
                        canvas.redo(); return true;
                    }
                    if (keyval == Gdk.Key.v || keyval == Gdk.Key.V) {
                        canvas.paste_in_place(); return true;
                    }
                    if (keyval == Gdk.Key.g || keyval == Gdk.Key.G) {
                        canvas.ungroup_selected(); return true;
                    }
                    if (keyval == Gdk.Key.i || keyval == Gdk.Key.I) {
                        canvas.invert_selection(); return true;
                    }
                    if (keyval == Gdk.Key.bracketright) {
                        canvas.bring_to_front(); return true;
                    }
                    if (keyval == Gdk.Key.bracketleft) {
                        canvas.send_to_back(); return true;
                    }
                }

                if (ctrl && alt) {
                    if (keyval == Gdk.Key.u || keyval == Gdk.Key.U) {
                        canvas.boolean_union(); return true;
                    }
                    if (keyval == Gdk.Key.s || keyval == Gdk.Key.S) {
                        canvas.boolean_difference(); return true;
                    }
                    if (keyval == Gdk.Key.i || keyval == Gdk.Key.I) {
                        canvas.boolean_intersection(); return true;
                    }
                    if (keyval == Gdk.Key.x || keyval == Gdk.Key.X) {
                        canvas.boolean_exclusion(); return true;
                    }
                }

                // Single letter tool shortcuts without Ctrl/Alt
                if (!ctrl && !alt) {
                    if (keyval == Gdk.Key.v || keyval == Gdk.Key.V) {
                        activate_tool("select"); return true;
                    }
                    if (keyval == Gdk.Key.h || keyval == Gdk.Key.H) {
                        activate_tool("hand"); return true;
                    }
                    if (keyval == Gdk.Key.r || keyval == Gdk.Key.R) {
                        activate_tool("rect"); return true;
                    }
                    if (keyval == Gdk.Key.o || keyval == Gdk.Key.O) {
                        activate_tool("ellipse"); return true;
                    }
                    if (keyval == Gdk.Key.t || keyval == Gdk.Key.T) {
                        activate_tool("text"); return true;
                    }
                    if (keyval == Gdk.Key.l || keyval == Gdk.Key.L) {
                        activate_tool("line"); return true;
                    }
                    if (keyval == Gdk.Key.a || keyval == Gdk.Key.A) {
                        activate_tool("arrow"); return true;
                    }
                    if (keyval == Gdk.Key.f || keyval == Gdk.Key.F) {
                        activate_tool("frame"); return true;
                    }
                    if (keyval == Gdk.Key.p || keyval == Gdk.Key.P) {
                        if (shift) activate_tool("pencil");
                        else activate_tool("pen");
                        return true;
                    }
                    if (shift && (keyval == Gdk.Key.@2 || keyval == Gdk.Key.KP_2)) {
                        canvas.zoom_to_selection(); return true;
                    }
                    if (keyval == Gdk.Key.Delete || keyval == Gdk.Key.BackSpace) {
                        canvas.delete_selected(); return true;
                    }
                    if (keyval == Gdk.Key.Escape) {
                        if (canvas.is_in_node_edit_mode()) canvas.exit_node_edit_mode();
                        else canvas.clear_selection();
                        return true;
                    }
                    if (keyval == Gdk.Key.Return) {
                        if (canvas.is_in_node_edit_mode()) canvas.exit_node_edit_mode();
                        else if (canvas.primary_selected != null) canvas.enter_node_edit_mode();
                        return true;
                    }

                    // Nudge
                    double nudge_step = shift ? 10.0 : 1.0;
                    if (keyval == Gdk.Key.Left) {
                        canvas.nudge_selection(-nudge_step, 0); return true;
                    }
                    if (keyval == Gdk.Key.Right) {
                        canvas.nudge_selection(nudge_step, 0); return true;
                    }
                    if (keyval == Gdk.Key.Up) {
                        canvas.nudge_selection(0, -nudge_step); return true;
                    }
                    if (keyval == Gdk.Key.Down) {
                        canvas.nudge_selection(0, nudge_step); return true;
                    }
                }

                return false;
            });

            key_ctrl.key_released.connect((keyval, keycode, state) => {
                canvas.alt_held = (state & Gdk.ModifierType.ALT_MASK) != 0;
                canvas.shift_held = (state & Gdk.ModifierType.SHIFT_MASK) != 0;
            });

            ((Gtk.Widget) this).add_controller(key_ctrl);
        }
    }
}
