project(
  'nova',
  ['vala', 'c'],
  version: '0.1.0',
  license: 'GPL-3.0-or-later',
  meson_version: '>= 0.59.0',
  default_options: [
    'warning_level=1',
    'buildtype=debugoptimized',
  ],
)

app_id = 'com.iminwa.nova'

add_project_arguments(
  ['--target-glib=2.66'],
  language: 'vala',
)

gnome = import('gnome')
i18n = import('i18n')

cc = meson.get_compiler('c')
m_dep = cc.find_library('m', required: false)

glib_dep = dependency('glib-2.0', version: '>= 2.66')
gobject_dep = dependency('gobject-2.0')
gio_dep = dependency('gio-2.0')
gtk_dep = dependency('gtk4', version: '>= 4.0')
adw_dep = dependency('libadwaita-1', version: '>= 1.0')
cairo_dep = dependency('cairo')
pango_dep = dependency('pango')
pixbuf_dep = dependency('gdk-pixbuf-2.0')

nova_deps = [
  glib_dep,
  gobject_dep,
  gio_dep,
  gtk_dep,
  adw_dep,
  cairo_dep,
  pango_dep,
  pixbuf_dep,
  m_dep,
]

subdir('data')
subdir('src')
