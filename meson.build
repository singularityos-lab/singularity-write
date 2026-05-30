project('singularity-write', ['vala', 'c'],
  version: '0.1.0',
  meson_version: '>= 0.59.0'
)

gnome = import('gnome')

cc            = meson.get_compiler('c')
gtk_dep       = dependency('gtk4')
gee_dep       = dependency('gee-0.8')
webkit_dep    = dependency('webkitgtk-6.0')
gtksource_dep = dependency('gtksourceview-5')
poppler_dep   = dependency('poppler-glib')
math_dep      = cc.find_library('m')

libsingularity_dep = dependency('singularity-1.0',
  fallback: ['libsingularity', 'libsingularity_dep']
)

if not meson.is_subproject() and libsingularity_dep.type_name() == 'internal'
  libsingularity_vapi_dir = join_paths(meson.project_build_root(), 'subprojects', 'libsingularity')
  add_project_arguments(['--vapidir=' + libsingularity_vapi_dir], language: 'vala')
endif

subdir('ui')

resources = gnome.compile_resources(
  'singularity-write-resources',
  'resources/dev.sinty.write.gresource.xml',
  source_dir: [meson.current_source_dir(), meson.current_build_dir()],
  dependencies: main_ui
)

sources = files(
  'src/main.vala',
  'src/window.vala',
  'src/app.vala',
  'src/odt.vala',
  'src/pdf.vala',
  'src/markdown.vala',
)

executable('singularity-write',
  sources + [resources],
  dependencies: [gtk_dep, gee_dep, webkit_dep, gtksource_dep, poppler_dep, math_dep, libsingularity_dep],
  install: true
)

shared_module('singularity-write-widget',
  files('widget/notes_widget.vala'),
  dependencies: [gtk_dep, libsingularity_dep],
  install: true,
  install_dir: get_option('libdir') / 'singularity' / 'widgets'
)
install_data('widget/dev.sinty.write.notes.widget',
  install_dir: get_option('datadir') / 'singularity' / 'widgets'
)

install_data('data/dev.sinty.write.desktop',
  install_dir: get_option('datadir') / 'applications'
)
install_data('data/dev.sinty.write.gschema.xml',
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas'
)
install_data('data/dev.sinty.write.json',
  install_dir: get_option('datadir') / 'singularity' / 'apps'
)
install_data('data/icons/dev.sinty.write.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps'
)
