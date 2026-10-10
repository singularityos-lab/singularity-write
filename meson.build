project('singularity-write', ['vala', 'c'],
  version: '0.1.0',
  meson_version: '>= 0.59.0'
)

i18n = import('i18n')
add_project_arguments('-DGETTEXT_PACKAGE="singularity-write"', language: 'c')
subdir('po')

gnome = import('gnome')

cc            = meson.get_compiler('c')
gtk_dep       = dependency('gtk4')
gee_dep       = dependency('gee-0.8')
webkit_dep    = dependency('webkitgtk-6.0')
gtksource_dep = dependency('gtksourceview-5')
xml_dep       = dependency('libxml-2.0')
zlib_dep      = dependency('zlib')
gio_dep       = dependency('gio-2.0')
gio_unix_dep  = dependency('gio-unix-2.0')
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

engine = files(
  'src/doc/model.vala',
  'src/doc/styles.vala',
  'src/doc/fields.vala',
  'src/doc/stats.vala',
  'src/io/zip.vala',
  'src/io/xml.vala',
  'src/io/docx_reader.vala',
  'src/io/docx_writer.vala',
  'src/io/odt_reader.vala',
  'src/io/odt_writer.vala',
  'src/io/rtf.vala',
  'src/io/doc_reader.vala',
  'src/io/formats.vala',
  'src/markdown.vala',
  'src/doc/hyphen.vala',
  'src/layout/text.vala',
  'src/layout/engine.vala',
  'src/layout/render.vala',
  'src/layout/pdf.vala',
  'src/doc/edit.vala',
  'src/doc/review.vala',
  'src/doc/update.vala',
  'src/doc/find.vala',
  'src/doc/merge.vala',
  'src/doc/proof.vala',
  'src/io/epub.vala',
  'src/io/omml.vala',
  'src/doc/live.vala',
  'src/doc/script.vala',
)
pangocairo_dep = dependency('pangocairo')
poppler_dep = dependency('poppler-glib')
json_dep = dependency('json-glib-1.0')
soup_dep = dependency('libsoup-3.0')
gst_dep = dependency('gstreamer-1.0')
engine_deps = [gtk_dep, gee_dep, gio_dep, xml_dep, zlib_dep, math_dep, pangocairo_dep, json_dep, dependency('sqlite3')]
engine_args = ['--pkg', 'zlib']

sources = files(
  'src/main.vala',
  'src/window.vala',
  'src/app.vala',
  'src/collab_bus.vala',
  'src/cloud_actions.vala',
  'src/formula_bridge.vala',
  'src/search_provider.vala',
  'src/templates.vala',
  'src/template_gallery.vala',
  'src/ui/doc_view.vala',
  'src/ui/print_source.vala',
  'src/ui/format_bar.vala',
  'src/ui/ribbon.vala',
  'src/ui/rich_editor.vala',
  'src/ui/actions.vala',
  'src/ui/files.vala',
  'src/ui/panes.vala',
  'src/ui/dialogs.vala',
  'src/ui/live_session.vala',
)

executable('singularity-write',
  sources + engine + [resources],
  dependencies: [gtk_dep, gee_dep, webkit_dep, gtksource_dep, math_dep, libsingularity_dep, soup_dep, gst_dep, gio_unix_dep] + engine_deps,
  vala_args: engine_args,
  install: true
)

shared_module('singularity-write-widget',
  files('widget/notes_widget.vala'),
  dependencies: [gtk_dep, gee_dep, libsingularity_dep],
  install: true,
  install_dir: get_option('libdir') / 'singularity' / 'widgets'
)
install_data('widget/dev.sinty.write.notes.widget',
  install_dir: get_option('datadir') / 'singularity' / 'widgets'
)

install_data('data/dev.sinty.write.search-provider.ini',
  rename: 'dev.sinty.write.ini',
  install_dir: get_option('datadir') / 'singularity' / 'search-providers'
)
configure_file(
  input: 'data/dev.sinty.write.service.in',
  output: 'dev.sinty.write.service',
  configuration: {'bindir': get_option('prefix') / get_option('bindir')},
  install_dir: get_option('datadir') / 'dbus-1' / 'services'
)

templates_test = executable('write-templates-test',
  files('tests/templates_test.vala', 'src/templates.vala', 'src/markdown.vala') + [resources],
  dependencies: [gtk_dep, gee_dep],
)
test('templates', templates_test, env: ['TMPDIR=' + meson.current_build_dir()])

foreach t : ['docx', 'odt', 'formats', 'layout', 'features']
  exe = executable('write-' + t + '-test',
    engine + files('tests/harness.vala', 'tests/rich_doc.vala', 'tests/' + t + '_test.vala'),
    dependencies: engine_deps + [poppler_dep],
    vala_args: engine_args,
  )
  test(t, exe, env: ['WRITE_FIXTURES=' + meson.current_source_dir() / 'tests' / 'fixtures', 'TMPDIR=' + meson.current_build_dir()])
endforeach

proofing_test = executable('write-proofing-test',
  engine + files('src/ui/doc_view.vala', 'tests/harness.vala', 'tests/proofing_test.vala'),
  dependencies: engine_deps + [poppler_dep, libsingularity_dep],
  vala_args: engine_args,
)
test('proofing', proofing_test, env: ['GSETTINGS_BACKEND=memory'])

install_data('data/dev.sinty.write.desktop',
  install_dir: get_option('datadir') / 'applications'
)
install_data('data/dev.sinty.write.gschema.xml',
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas'
)
install_data('data/dev.sinty.write.json',
  install_dir: get_option('datadir') / 'singularity' / 'app-settings'
)
install_data('data/icons/dev.sinty.write.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps'
)

install_data('data/capabilities/dev.sinty.Collab.Document1.ini',
  install_dir: get_option('datadir') / 'singularity' / 'capabilities')
