nova_sources = files(
  'Main.vala',
  'Application.vala',
  'Model/Types.vala',
  'Model/Color.vala',
  'Model/Shape.vala',
  'Model/Geometry.vala',
  'Model/Paths.vala',
  'Model/History.vala',
  'Model/Clipboard.vala',
  'Model/Svg.vala',
  'Model/Document.vala',
  'Canvas/Render.vala',
  'Canvas/Export.vala',
  'Canvas/Canvas.vala',
  'Shell/Icons.vala',
  'Shell/Shortcuts.vala',
  'Shell/Eyedropper.vala',
  'Shell/Window.vala',
)

executable(
  'nova',
  nova_sources,
  nova_resources,
  dependencies: nova_deps,
  install: true,
)
