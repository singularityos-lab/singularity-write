# Singularity Write

> [!IMPORTANT]
> Report bugs and request features in the
> [Singularity Desktop tracker](https://github.com/singularityos-lab/singularity-desktop/issues/new/choose).

Word processor and Markdown editor for the Singularity Desktop. Documents are laid out in real pages and read and written as DOCX, ODT, RTF, HTML, EPUB, Markdown and plain text (DOC 97-2003 is read); PDF export and printing use the same page layout.

## Requirements

- [Meson](https://mesonbuild.com/) >= 0.59
- [Vala](https://vala.dev/) compiler
- [Vetro](https://github.com/singularityos-lab/vetro/) compiler
- GTK4, libgee-0.8, webkitgtk-6.0, gtksourceview-5, libxml-2.0, zlib, pangocairo, json-glib-1.0
- poppler-glib (tests only)
- [libsingularity](https://github.com/singularityos-lab/libsingularity)

## Build & Install

```sh
meson setup build
meson compile -C build
meson install -C build
```

## For distributors

Write works without any of the programs below and explains in the interface what is missing. Each one is looked up at run time and can be replaced:

| Feature | Default | Override |
| --- | --- | --- |
| Equation editing and rendering | `singularity-formula` | `SINGULARITY_EQUATION_HELPER` |
| Read aloud | `spd-say`, `espeak-ng`, `espeak` or `festival` | `SINGULARITY_TTS` |
| Dictation | the desktop dictation service `dev.sinty.Dictation` (session bus, `TranscribeFile`); audio from `autoaudiosrc`, `pipewiresrc` or `pulsesrc` | `SINGULARITY_WRITE_AUDIO_SOURCE`, a GStreamer source description |
| Translation | the desktop translation service `dev.sinty.TranslateService` (session bus) | any service implementing the same interface |
| Hyphenation | `hyph_<lang>.dic` (libhyphen) under `$XDG_DATA_DIRS/hyphen` or the TeX hyph-utf8 patterns | `SINGULARITY_HYPHEN_DIRS` |
| Thesaurus | MyThes `th_<lang>*.idx/.dat` under `$XDG_DATA_DIRS/mythes`, `myspell/dicts` or `hunspell` | `SINGULARITY_THESAURUS_DIRS` |
| Spelling | the system spell checker used by libsingularity | |

Edit Together listens on the local network (IPv4, a random port, protected by the key in the link); set `SINGULARITY_WRITE_LIVE_LOOPBACK=1` to keep it on this machine. The cloud folder mode only writes small JSON files into a `.write-live` folder of the chosen directory.

Autosave copies live in `$XDG_STATE_HOME/singularity-write/recovery`, earlier versions of saved documents in `$XDG_DATA_HOME/singularity-write/versions`.

## License

GPL-3.0-only, see [LICENSE](LICENSE).

## Use of Generative AI

Maintainers may use generative AI tools as assistants while working on singularity-write. Non-trivial assisted commits disclose the tool, model, and scope of the work.

AI tools may assist with code comments, documentation, repetitive code, and issue triage. Maintainers make project decisions and review every assisted change before it is merged.

Use these trailers for non-trivial assisted commits:

```plain
Assisted-by: <tool>:<model-version>
AI-Scope: <what the tool generated and the prompt or a short prompt summary>
```

Single-line completions, renames, and formatting changes do not need trailers.

Coding agents must also follow [AGENTS.md](AGENTS.md) before changing files,
creating commits, or opening pull requests.
