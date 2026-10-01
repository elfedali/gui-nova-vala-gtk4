# Nova Design (Vala + GTK 4) 🎨

A native, high-performance vector design and layout tool built for the GNOME desktop with **Vala**, **GTK 4**, **Libadwaita**, and **Cairo**.

This is a complete, native rewrite of Nova from Python into Vala, designed for fast startup, low memory footprint, and tight desktop integration.

---

## Architecture

The application ID is `com.iminwa.nova`. The source code is organized following strict MVC principles:

- **`src/Model/`** — Data Model & Mathematical Engine:
  - `Types.vala`: Core enumerations (`ShapeType`, `StrokeDash`, `StrokeAlign`, `StrokeCap`, `StrokeJoin`, `NodeType`), point and rect structs, and `PathNode`.
  - `Shape.vala`: Rich vector shape object model with properties and deep cloning.
  - `Color.vala`: Color conversions, RGBA normalization, hex parsing (`#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA`), and document palette extraction.
  - `Geometry.vala`: Pure geometric math, bounds normalization, resize calculations (corner, edge, aspect ratio lock, center growth), corner radius clamping, hit testing, alignment, distribution, and frame containment.
  - `Paths.vala`: Bézier mathematics (evaluation, subdivision with de Casteljau, sampling, projection), node handle collinearity constraints, shape-to-path conversion, and high-precision **Greiner-Hormann 2D polygon boolean operations** (Union, Difference, Intersection, Exclusion).
  - `History.vala`: Non-destructive Undo/Redo command history stack using document state snapshots.
  - `Clipboard.vala`: In-memory clipboard for copy, cut, paste, and paste-in-place operations.
  - `Svg.vala`: SVG generator outputting standard SVG 1.1 / SVG 2 markup with styling, clip paths for inside strokes, and transforms.
  - `Document.vala`: Scene graph management, z-index ordering (respecting artboard frame hierarchy), grouping/ungrouping, alignment, and hit testing.

- **`src/Canvas/`** — Cairo Rendering & Interactive Viewport:
  - `Canvas.vala`: `Gtk.DrawingArea` canvas widget with GTK 4 gesture controllers (`Gtk.GestureClick`, `Gtk.GestureDrag`, `Gtk.EventControllerMotion`, `Gtk.EventControllerScroll`, `Gtk.GestureZoom`), interactive shape authoring, selection transforms, marquee drag, smart alignment guides, measurement overlays, and right-click context menu.
  - `Render.vala`: Cairo drawing engine for shapes, strokes (center, inside, outside), dash patterns, line caps/joins, typography, selection bounding boxes, corner radius handles, and vector node overlays.
  - `Export.vala`: Rasterization engine for PNG, JPEG, and WebP at 1x, 2x, and 3x scale with checkerboard preview painting.

- **`src/Shell/`** — User Interface & Application Shell:
  - `Window.vala`: Main `Adw.ApplicationWindow` containing:
    - HeaderBar with undo/redo, zoom controls, and sidebar toggles.
    - Left sidebar with searchable Layers tree, frame hierarchy, expanders, per-layer visibility, and lock controls.
    - Floating bottom tool dock (`.nova-dock`) with 5 slots: Select, Frame (with Artboard presets), Shapes (Rectangle, Ellipse, Polygon, Star, Line, Arrow), Drawing (Pen, Pencil), and Text.
    - Right sidebar with the Properties Inspector (Alignment, Booleans, Transform, Corner Radius, Opacity, Fill, Stroke, Typography, Vector Nodes, Canvas Background, and Export).
  - `Icons.vala`: Bundled Lucide SVG iconography helper and `Gtk.Button` / `Gtk.Image` factories.
  - `Shortcuts.vala`: Native GNOME `Gtk.ShortcutsWindow` cheat sheet.
  - `Eyedropper.vala`: System desktop eyedropper via the XDG Desktop Portal D-Bus API (`PickColor`).

- **`src/Application.vala` & `src/Main.vala`**:
  - `Adw.Application` lifecycle management and default document setup (starter iPhone 15 frame).

- **`data/`**:
  - `nova.gresource.xml`: GResource compiling `style.css` and all 60 bundled Lucide SVG icons directly into the binary.
  - `style.css`: Clean Libadwaita stylesheet styling the floating tool dock, layers tree, and inspector chips.
  - `com.iminwa.nova.desktop.in`: Desktop launcher file.
  - `com.iminwa.nova.metainfo.xml.in`: AppStream metainfo.

---

## Features

- **Vector Authoring**:
  - **Rectangle** (`R`), **Ellipse** (`O`), **Polygon**, **Star**, **Line** (`L`), **Arrow** (`A`).
  - **Artboard Frames** (`F`) with preset sizes (iPhone 15, Desktop HD, iPad Pro, Paper A4, Social Post) with automatic child layer containment.
  - **Bézier Pen Tool** (`P`) with dynamic rubberband preview, loop closure indicators, and tangent handle drags.
  - **Freehand Pencil** (`Shift+P`) with Chaikin smoothing.
  - **Typography** (`T`) with font family, size, weight, slant, alignment, and line height.
- **Node Editing**:
  - Double-click any path or shape to enter vector edit mode.
  - Manipulate individual anchor points and control handles.
  - Switch anchor types between **Corner**, **Smooth** (collinear symmetric), and **Asymmetric**.
  - Add nodes by clicking on the path curve, or delete selected nodes (`Delete`).
- **Boolean Operations**:
  - Combine multiple shapes with **Union** (`Ctrl+Alt+U`), **Subtract** (`Ctrl+Alt+S`), **Intersect** (`Ctrl+Alt+I`), and **Exclude** (`Ctrl+Alt+X`).
- **Properties Inspector**:
  - **Transform**: Coordinates X, Y, dimensions W, H, and rotation angle (with 15° snap holding Shift).
  - **Corner Radius**: Uniform slider/entry and independent 4-corner inputs (Top-Left, Top-Right, Bottom-Right, Bottom-Left).
  - **Fill**: Hex `#RRGGBB` / `#RRGGBBAA` entry, palette chips, document colors auto-palette, and desktop eyedropper.
  - **Stroke**: Width, color, dash styles (Solid, Dashed, Dotted), stroke alignment (Center, Inside, Outside), caps (Butt, Round, Square), joins (Miter, Round, Bevel).
  - **Opacity**: Global layer alpha slider (0–100%).
- **Layers & Hierarchy**:
  - Searchable layer list.
  - Visual distinction for frames, groups, rects, ellipses, text, and vector paths.
  - Per-layer visibility (`eye` / `eye-off`) and lock (`lock` / `unlock`) toggles.
  - Z-Index ordering (Bring to Front `Ctrl+Shift+]`, Bring Forward `Ctrl+]`, Send Backward `Ctrl+[`, Send to Back `Ctrl+Shift+[`).
- **Navigation & Viewport**:
  - Pan via Middle-Click drag or Space + Left-Click drag.
  - Zoom via Ctrl + Mouse Wheel, Trackpad pinch, Zoom to Fit (`Ctrl+0`), Zoom to 100% (`Ctrl+1`), or Zoom to Selection (`Shift+2`).
  - Sub-pixel grid visible at >= 800% zoom.
  - Smart distance measurement overlay holding `Alt` while hovering shapes.
- **Export**:
  - Vector export to clean SVG.
  - Raster export to PNG, JPEG, or WebP at 1x, 2x, or 3x scale.
  - Live export preview with transparency checkerboard.

---

## System Requirements

To build and run Nova on Ubuntu / Debian:

```bash
sudo apt update
sudo apt install \
  valac \
  meson \
  ninja-build \
  libgtk-4-dev \
  libadwaita-1-dev \
  libcairo2-dev \
  libpango1.0-dev \
  libgdk-pixbuf-2.0-dev \
  pkg-config
```

On Fedora:

```bash
sudo dnf install \
  vala \
  meson \
  ninja-build \
  gtk4-devel \
  libadwaita-devel \
  cairo-devel \
  pango-devel \
  gdk-pixbuf2-devel
```

On Arch Linux:

```bash
sudo pacman -S \
  vala \
  meson \
  ninja \
  gtk4 \
  libadwaita \
  cairo \
  pango \
  gdk-pixbuf2
```

---

## Build and Run

To compile and launch Nova:

```bash
cd gui-nova-vala-gtk4
make
make run
```

Or manually with Meson:

```bash
meson setup build
ninja -C build
./build/src/nova
```
