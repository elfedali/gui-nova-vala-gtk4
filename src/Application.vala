/* Application.vala - Nova Adw.Application lifecycle and document initialization */

namespace Nova {

    public class Application : Adw.Application {
        public Document document { get; private set; }

        public Application() {
            Object(
                application_id: "com.iminwa.nova",
                flags: ApplicationFlags.DEFAULT_FLAGS
            );
            this.document = create_default_document();
        }

        private Document create_default_document() {
            var doc = new Document();
            var frame = new Shape(ShapeType.FRAME);
            frame.name = "Frame 1";
            frame.frame_preset = "393×852";
            frame.x = 100.0;
            frame.y = 60.0;
            frame.w = 393.0;
            frame.h = 852.0;
            frame.color = Color.rgb(1.0, 1.0, 1.0);
            doc.add_shape(frame, false);
            return doc;
        }

        protected override void activate() {
            Icons.init();
            var win = this.active_window as Window;
            if (win == null) {
                win = new Window(this, this.document);
            }
            win.present();
        }
    }
}
