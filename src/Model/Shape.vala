/* Shape.vala - Core vector shape model representation */

namespace Nova {

    public class Shape : GLib.Object {
        public string id { get; set; }
        public ShapeType shape_type { get; set; default = ShapeType.RECT; }
        public string name { get; set; default = "Rectangle"; }

        public double x { get; set; default = 0.0; }
        public double y { get; set; default = 0.0; }
        public double w { get; set; default = 100.0; }
        public double h { get; set; default = 100.0; }

        public Color color { get; set; default = Color.rgb(0.2, 0.6, 0.85); }
        public double opacity { get; set; default = 1.0; }
        public double rotation { get; set; default = 0.0; }

        public bool has_stroke { get; set; default = false; }
        public Color stroke_color { get; set; default = Color.rgb(0.2, 0.2, 0.2); }
        public double stroke_width { get; set; default = 0.0; }
        public StrokeDash stroke_dash { get; set; default = StrokeDash.SOLID; }
        public StrokeAlign stroke_align { get; set; default = StrokeAlign.CENTER; }
        public StrokeCap stroke_cap { get; set; default = StrokeCap.BUTT; }
        public StrokeJoin stroke_join { get; set; default = StrokeJoin.MITER; }

        public CornerRadii corner_radius { get; set; default = CornerRadii(0, 0, 0, 0); }
        public bool locked { get; set; default = false; }
        public bool visible { get; set; default = true; }
        public string? frame_id { get; set; default = null; }

        // Group specific
        public GLib.GenericArray<Shape> children { get; set; }

        // Typography
        public string text { get; set; default = "Text"; }
        public string font_family { get; set; default = "Sans"; }
        public double font_size { get; set; default = 20.0; }
        public string font_weight { get; set; default = "normal"; }
        public string font_slant { get; set; default = "normal"; }
        public string text_align { get; set; default = "left"; }
        public double line_height { get; set; default = 1.2; }
        public double letter_spacing { get; set; default = 0.0; }

        // Polygon & Star
        public int sides { get; set; default = 5; }
        public int points_count { get; set; default = 5; }
        public double inner_ratio { get; set; default = 0.5; }

        // Line & Arrow
        public string arrow_start { get; set; default = "none"; }
        public string arrow_end { get; set; default = "none"; }

        // Pencil
        public GLib.GenericArray<Point?> points { get; set; }

        // Image
        public string? image_path { get; set; default = null; }

        // Frame
        public string? frame_preset { get; set; default = null; }

        // Path
        public bool closed { get; set; default = true; }
        public GLib.GenericArray<PathNode> nodes { get; set; }

        public Shape(ShapeType stype = ShapeType.RECT) {
            this.id = "node_" + GLib.Uuid.string_random().substring(0, 8);
            this.shape_type = stype;
            this.children = new GLib.GenericArray<Shape>();
            this.points = new GLib.GenericArray<Point?>();
            this.nodes = new GLib.GenericArray<PathNode>();

            this.name = default_name(stype);
            switch (stype) {
                case ShapeType.FRAME:
                    this.color = Color.rgb(1.0, 1.0, 1.0);
                    break;
                case ShapeType.TEXT:
                    this.color = Color.rgb(0.1, 0.1, 0.1);
                    break;
                case ShapeType.POLYGON:
                    this.sides = 5;
                    break;
                case ShapeType.STAR:
                    this.points_count = 5;
                    this.inner_ratio = 0.5;
                    break;
                case ShapeType.LINE:
                case ShapeType.ARROW:
                case ShapeType.PENCIL:
                    this.color = Color.rgb(0.2, 0.2, 0.2);
                    this.stroke_width = 2.0;
                    this.stroke_color = Color.rgb(0.2, 0.2, 0.2);
                    this.has_stroke = true;
                    if (stype == ShapeType.ARROW) this.arrow_end = "filled";
                    if (stype == ShapeType.PENCIL) this.closed = false;
                    break;
                case ShapeType.PATH:
                    this.closed = true;
                    break;
                default:
                    break;
            }
        }

        public static string default_name(ShapeType stype) {
            switch (stype) {
                case ShapeType.RECT: return "Rectangle";
                case ShapeType.ELLIPSE: return "Ellipse";
                case ShapeType.FRAME: return "Frame";
                case ShapeType.TEXT: return "Text";
                case ShapeType.POLYGON: return "Polygon";
                case ShapeType.STAR: return "Star";
                case ShapeType.LINE: return "Line";
                case ShapeType.ARROW: return "Arrow";
                case ShapeType.PENCIL: return "Pencil";
                case ShapeType.PATH: return "Vector Path";
                case ShapeType.IMAGE: return "Image";
                case ShapeType.GROUP: return "Group";
                default: return "Shape";
            }
        }

        public Shape clone() {
            var copy = new Shape(this.shape_type);
            copy.id = "node_" + GLib.Uuid.string_random().substring(0, 8);
            copy.name = this.name;
            copy.x = this.x;
            copy.y = this.y;
            copy.w = this.w;
            copy.h = this.h;
            copy.color = this.color;
            copy.opacity = this.opacity;
            copy.rotation = this.rotation;
            copy.has_stroke = this.has_stroke;
            copy.stroke_color = this.stroke_color;
            copy.stroke_width = this.stroke_width;
            copy.stroke_dash = this.stroke_dash;
            copy.stroke_align = this.stroke_align;
            copy.stroke_cap = this.stroke_cap;
            copy.stroke_join = this.stroke_join;
            copy.corner_radius = this.corner_radius;
            copy.locked = this.locked;
            copy.visible = this.visible;
            copy.frame_id = this.frame_id;

            copy.text = this.text;
            copy.font_family = this.font_family;
            copy.font_size = this.font_size;
            copy.font_weight = this.font_weight;
            copy.font_slant = this.font_slant;
            copy.text_align = this.text_align;
            copy.line_height = this.line_height;
            copy.letter_spacing = this.letter_spacing;

            copy.sides = this.sides;
            copy.points_count = this.points_count;
            copy.inner_ratio = this.inner_ratio;

            copy.arrow_start = this.arrow_start;
            copy.arrow_end = this.arrow_end;

            copy.image_path = this.image_path;
            copy.frame_preset = this.frame_preset;
            copy.closed = this.closed;

            for (uint i = 0; i < this.children.length; i++) {
                copy.children.add(this.children[i].clone());
            }

            for (uint i = 0; i < this.points.length; i++) {
                copy.points.add(this.points[i]);
            }

            for (uint i = 0; i < this.nodes.length; i++) {
                copy.nodes.add(this.nodes[i].clone());
            }

            return copy;
        }

        public Rect get_bounds() {
            return Rect(x, y, w, h);
        }
    }
}
