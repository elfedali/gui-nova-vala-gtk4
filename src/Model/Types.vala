/* Types.vala - Shared enums, structs, and node models */

namespace Nova {

    public enum ShapeType {
        RECT,
        ELLIPSE,
        GROUP,
        TEXT,
        POLYGON,
        STAR,
        LINE,
        ARROW,
        PENCIL,
        IMAGE,
        FRAME,
        PATH;

        public string to_string() {
            switch (this) {
                case RECT: return "rect";
                case ELLIPSE: return "ellipse";
                case GROUP: return "group";
                case TEXT: return "text";
                case POLYGON: return "polygon";
                case STAR: return "star";
                case LINE: return "line";
                case ARROW: return "arrow";
                case PENCIL: return "pencil";
                case IMAGE: return "image";
                case FRAME: return "frame";
                case PATH: return "path";
                default: return "rect";
            }
        }

        public static ShapeType from_string(string s) {
            switch (s.down()) {
                case "rect": return RECT;
                case "ellipse": return ELLIPSE;
                case "group": return GROUP;
                case "text": return TEXT;
                case "polygon": return POLYGON;
                case "star": return STAR;
                case "line": return LINE;
                case "arrow": return ARROW;
                case "pencil": return PENCIL;
                case "image": return IMAGE;
                case "frame": return FRAME;
                case "path": return PATH;
                default: return RECT;
            }
        }
    }

    public enum StrokeDash {
        SOLID,
        DASHED,
        DOTTED;

        public string to_string() {
            switch (this) {
                case DASHED: return "dashed";
                case DOTTED: return "dotted";
                default: return "solid";
            }
        }

        public static StrokeDash from_string(string s) {
            switch (s.down()) {
                case "dashed": return DASHED;
                case "dotted": return DOTTED;
                default: return SOLID;
            }
        }
    }

    public enum StrokeAlign {
        CENTER,
        INSIDE,
        OUTSIDE;

        public string to_string() {
            switch (this) {
                case INSIDE: return "inside";
                case OUTSIDE: return "outside";
                default: return "center";
            }
        }

        public static StrokeAlign from_string(string s) {
            switch (s.down()) {
                case "inside": return INSIDE;
                case "outside": return OUTSIDE;
                default: return CENTER;
            }
        }
    }

    public enum StrokeCap {
        BUTT,
        ROUND,
        SQUARE;

        public string to_string() {
            switch (this) {
                case ROUND: return "round";
                case SQUARE: return "square";
                default: return "butt";
            }
        }

        public static StrokeCap from_string(string s) {
            switch (s.down()) {
                case "round": return ROUND;
                case "square": return SQUARE;
                default: return BUTT;
            }
        }
    }

    public enum StrokeJoin {
        MITER,
        ROUND,
        BEVEL;

        public string to_string() {
            switch (this) {
                case ROUND: return "round";
                case BEVEL: return "bevel";
                default: return "miter";
            }
        }

        public static StrokeJoin from_string(string s) {
            switch (s.down()) {
                case "round": return ROUND;
                case "bevel": return BEVEL;
                default: return MITER;
            }
        }
    }

    public enum NodeType {
        CORNER,
        SMOOTH,
        ASYMMETRIC;

        public string to_string() {
            switch (this) {
                case SMOOTH: return "smooth";
                case ASYMMETRIC: return "asymmetric";
                default: return "corner";
            }
        }

        public static NodeType from_string(string s) {
            switch (s.down()) {
                case "smooth": return SMOOTH;
                case "asymmetric": return ASYMMETRIC;
                default: return CORNER;
            }
        }
    }

    public struct Point {
        public double x;
        public double y;

        public Point(double x, double y) {
            this.x = x;
            this.y = y;
        }

        public bool equals(Point other, double epsilon = 1e-4) {
            return (Math.fabs(x - other.x) <= epsilon) && (Math.fabs(y - other.y) <= epsilon);
        }
    }

    public struct CornerRadii {
        public double tl;
        public double tr;
        public double br;
        public double bl;

        public CornerRadii(double tl = 0.0, double tr = 0.0, double br = 0.0, double bl = 0.0) {
            this.tl = tl;
            this.tr = tr;
            this.br = br;
            this.bl = bl;
        }

        public static CornerRadii uniform(double r) {
            double val = Math.fmax(0.0, r);
            return CornerRadii(val, val, val, val);
        }

        public bool is_zero() {
            return tl <= 0.0 && tr <= 0.0 && br <= 0.0 && bl <= 0.0;
        }

        public bool is_uniform() {
            return tl == tr && tr == br && br == bl;
        }
    }

    public struct Rect {
        public double x;
        public double y;
        public double width;
        public double height;

        public Rect(double x, double y, double width, double height) {
            this.x = x;
            this.y = y;
            this.width = width;
            this.height = height;
        }

        public bool contains(double px, double py) {
            return px >= x && px <= x + width && py >= y && py <= y + height;
        }

        public bool intersects(Rect other) {
            return !(x + width < other.x || x > other.x + other.width ||
                     y + height < other.y || y > other.y + other.height);
        }
    }

    public class PathNode : GLib.Object {
        public double x { get; set; }
        public double y { get; set; }
        public Point? handle_in { get; set; default = null; }
        public Point? handle_out { get; set; default = null; }
        public NodeType node_type { get; set; default = NodeType.CORNER; }

        public PathNode(double x, double y, Point? hin = null, Point? hout = null, NodeType ntype = NodeType.CORNER) {
            this.x = x;
            this.y = y;
            this.handle_in = hin;
            this.handle_out = hout;
            this.node_type = ntype;
        }

        public PathNode clone() {
            return new PathNode(x, y, handle_in, handle_out, node_type);
        }
    }
}
