# Compile GResource bundle containing style.css and all 60 Lucide SVG icons
nova_resources = gnome.compile_resources(
  'nova-resources',
  'nova.gresource.xml',
  source_dir: meson.current_source_dir(),
  c_name: 'nova',
)

desktop_file = configure_file(
  input: 'com.iminwa.nova.desktop.in',
  output: 'com.iminwa.nova.desktop',
  copy: true,
  install: true,
  install_dir: get_option('datadir') / 'applications',
)

appstream_file = configure_file(
  input: 'com.iminwa.nova.metainfo.xml.in',
  output: 'com.iminwa.nova.metainfo.xml',
  copy: true,
  install: true,
  install_dir: get_option('datadir') / 'metainfo',
)
