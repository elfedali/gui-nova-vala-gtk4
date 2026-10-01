/* Shortcuts.vala - Native Libadwaita Shortcuts cheat-sheet window */

namespace Nova {

    public class Shortcuts {

        public static void show_shortcuts_window(Gtk.Window parent_window) {
            var dialog = new Adw.PreferencesDialog();
            dialog.title = "Keyboard Shortcuts";
            dialog.content_width = 620;
            dialog.content_height = 540;
            dialog.search_enabled = false;

            var page = new Adw.PreferencesPage();

            // 1. Tools
            var group_tools = new Adw.PreferencesGroup();
            group_tools.title = "Tools";
            add_shortcut(group_tools, "Select Tool", "V");
            add_shortcut(group_tools, "Hand Tool", "H");
            add_shortcut(group_tools, "Pen Tool (Bézier)", "P");
            add_shortcut(group_tools, "Freehand Pencil", "<Shift>P");
            add_shortcut(group_tools, "Rectangle", "R");
            add_shortcut(group_tools, "Ellipse", "O");
            add_shortcut(group_tools, "Text Tool", "T");
            add_shortcut(group_tools, "Line Tool", "L");
            add_shortcut(group_tools, "Arrow Tool", "A");
            add_shortcut(group_tools, "Frame / Artboard", "F");
            page.add(group_tools);

            // 2. Selection & Grouping
            var group_sel = new Adw.PreferencesGroup();
            group_sel.title = "Selection & Grouping";
            add_shortcut(group_sel, "Select All", "<Primary>a");
            add_shortcut(group_sel, "Invert Selection", "<Primary><Shift>i");
            add_shortcut(group_sel, "Group Selection", "<Primary>g");
            add_shortcut(group_sel, "Ungroup Selection", "<Primary><Shift>g");
            add_shortcut(group_sel, "Deselect / Exit", "Escape");
            page.add(group_sel);

            // 3. Edit & History
            var group_edit = new Adw.PreferencesGroup();
            group_edit.title = "Edit & History";
            add_shortcut(group_edit, "Undo", "<Primary>z");
            add_shortcut(group_edit, "Redo", "<Primary><Shift>z");
            add_shortcut(group_edit, "Copy", "<Primary>c");
            add_shortcut(group_edit, "Cut", "<Primary>x");
            add_shortcut(group_edit, "Paste", "<Primary>v");
            add_shortcut(group_edit, "Paste in Place", "<Primary><Shift>v");
            add_shortcut(group_edit, "Duplicate", "<Primary>d");
            add_shortcut(group_edit, "Delete", "Delete");
            page.add(group_edit);

            // 4. Transform & Arrange
            var group_arrange = new Adw.PreferencesGroup();
            group_arrange.title = "Transform & Arrange";
            add_shortcut(group_arrange, "Bring to Front", "<Primary><Shift>bracketright");
            add_shortcut(group_arrange, "Bring Forward", "<Primary>bracketright");
            add_shortcut(group_arrange, "Send Backward", "<Primary>bracketleft");
            add_shortcut(group_arrange, "Send to Back", "<Primary><Shift>bracketleft");
            add_shortcut(group_arrange, "Smart Nudge (1px)", "Up / Down / Left / Right");
            add_shortcut(group_arrange, "Large Nudge (10px)", "<Shift>Up / Down / Left / Right");
            add_shortcut(group_arrange, "Aspect Ratio Lock", "<Shift>Drag Handle");
            add_shortcut(group_arrange, "Scale from Center", "<Alt>Drag Handle");
            add_shortcut(group_arrange, "Distance Measurement", "<Alt>Hover Shape");
            page.add(group_arrange);

            // 5. Navigation & View
            var group_view = new Adw.PreferencesGroup();
            group_view.title = "Navigation & View";
            add_shortcut(group_view, "Pan Canvas", "Space + Drag");
            add_shortcut(group_view, "Middle-Click Pan", "Middle Click + Drag");
            add_shortcut(group_view, "Smooth Scroll Zoom", "<Primary>Scroll");
            add_shortcut(group_view, "Pinch to Zoom", "Touchpad Pinch");
            add_shortcut(group_view, "Zoom to Fit", "<Primary>0");
            add_shortcut(group_view, "Zoom to 100%", "<Primary>1");
            add_shortcut(group_view, "Zoom to Selection", "<Shift>2");
            page.add(group_view);

            // 6. Vector Networks & Boolean
            var group_vector = new Adw.PreferencesGroup();
            group_vector.title = "Vector Networks & Boolean";
            add_shortcut(group_vector, "Enter/Exit Vector Edit Mode", "Return");
            add_shortcut(group_vector, "Toggle Anchor Sharp/Smooth", "Double Click Anchor");
            add_shortcut(group_vector, "Boolean Union", "<Primary><Alt>u");
            add_shortcut(group_vector, "Boolean Subtract", "<Primary><Alt>s");
            add_shortcut(group_vector, "Boolean Intersection", "<Primary><Alt>i");
            add_shortcut(group_vector, "Boolean Exclusion", "<Primary><Alt>x");
            page.add(group_vector);

            dialog.add(page);
            dialog.present(parent_window);
        }

        private static void add_shortcut(Adw.PreferencesGroup group, string title, string accelerator) {
            var row = new Adw.ActionRow();
            row.title = title;
            var label = new Gtk.ShortcutLabel(accelerator);
            label.valign = Gtk.Align.CENTER;
            row.add_suffix(label);
            group.add(row);
        }
    }
}
