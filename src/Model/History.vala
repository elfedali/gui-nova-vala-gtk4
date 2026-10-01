/* History.vala - Undo/Redo command history stack for Document state */

namespace Nova {

    public class UndoStack : GLib.Object {
        public int max_history { get; set; default = 100; }
        private GLib.GenericArray<GLib.GenericArray<Shape>> undo_stack;
        private GLib.GenericArray<GLib.GenericArray<Shape>> redo_stack;

        public UndoStack(int max_hist = 100) {
            this.max_history = max_hist;
            this.undo_stack = new GLib.GenericArray<GLib.GenericArray<Shape>>();
            this.redo_stack = new GLib.GenericArray<GLib.GenericArray<Shape>>();
        }

        private static GLib.GenericArray<Shape> clone_shapes(GLib.GenericArray<Shape> shapes) {
            var copy = new GLib.GenericArray<Shape>();
            for (uint i = 0; i < shapes.length; i++) {
                copy.add(shapes[i].clone());
            }
            return copy;
        }

        public void record(GLib.GenericArray<Shape> shapes) {
            undo_stack.add(clone_shapes(shapes));
            if (undo_stack.length > (uint) max_history) {
                undo_stack.remove_index(0);
            }
            redo_stack.remove_range(0, redo_stack.length);
        }

        public bool can_undo() {
            return undo_stack.length > 0;
        }

        public bool can_redo() {
            return redo_stack.length > 0;
        }

        public GLib.GenericArray<Shape>? undo(GLib.GenericArray<Shape> current) {
            if (!can_undo()) {
                return null;
            }
            redo_stack.add(clone_shapes(current));
            uint last_idx = undo_stack.length - 1;
            var prev = undo_stack[last_idx];
            undo_stack.remove_index(last_idx);
            return prev;
        }

        public GLib.GenericArray<Shape>? redo(GLib.GenericArray<Shape> current) {
            if (!can_redo()) {
                return null;
            }
            undo_stack.add(clone_shapes(current));
            uint last_idx = redo_stack.length - 1;
            var next_state = redo_stack[last_idx];
            redo_stack.remove_index(last_idx);
            return next_state;
        }

        public void discard() {
            if (undo_stack.length > 0) {
                undo_stack.remove_index(undo_stack.length - 1);
            }
        }

        public void clear() {
            undo_stack.remove_range(0, undo_stack.length);
            redo_stack.remove_range(0, redo_stack.length);
        }
    }
}
