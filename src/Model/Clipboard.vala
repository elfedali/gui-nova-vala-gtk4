/* Clipboard.vala - In-memory clipboard for copying and pasting shapes */

namespace Nova {

    public class Clipboard : GLib.Object {
        private GLib.GenericArray<Shape> buffer;

        public Clipboard() {
            this.buffer = new GLib.GenericArray<Shape>();
        }

        public void copy(GLib.GenericArray<Shape> shapes) {
            buffer.remove_range(0, buffer.length);
            for (uint i = 0; i < shapes.length; i++) {
                buffer.add(shapes[i].clone());
            }
        }

        public bool has_content() {
            return buffer.length > 0;
        }

        public GLib.GenericArray<Shape> paste(double offset_x = 16.0, double offset_y = 16.0) {
            var clones = new GLib.GenericArray<Shape>();
            if (buffer.length == 0) return clones;

            for (uint i = 0; i < buffer.length; i++) {
                var clone = buffer[i].clone();
                clone.x += offset_x;
                clone.y += offset_y;
                if (clone.children.length > 0) {
                    shift_children(clone.children, offset_x, offset_y);
                }
                clones.add(clone);
            }
            return clones;
        }

        public GLib.GenericArray<Shape> paste_in_place() {
            return paste(0.0, 0.0);
        }

        private void shift_children(GLib.GenericArray<Shape> children, double dx, double dy) {
            for (uint i = 0; i < children.length; i++) {
                children[i].x += dx;
                children[i].y += dy;
                if (children[i].children.length > 0) {
                    shift_children(children[i].children, dx, dy);
                }
            }
        }
    }
}
