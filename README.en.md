# TyControls

A skinnable / styleable **Lazarus component library**: every control is fully custom-drawn
(BGRABitmap) and its appearance is driven uniformly by lightweight CSS-lite text themes
(`.tycss`), rendering pixel-identical on Windows / Linux / macOS.

> **中文:** [README.md](README.md) ·  **Changelog:** [CHANGELOG.md](CHANGELOG.md)

```css
:root { --accent: #3B82F6; --radius: 6px; }
TyButton          { background: var(--surface); border-radius: var(--radius); }
TyButton.primary  { background: var(--accent); color: #FFFFFF; }
TyButton:hover    { background: lighten(--surface, 8%); }
TyButton:disabled { opacity: 0.5; }
```

## Features

- **Three-layer architecture** — control layer / style engine / drawing primitives (`TTyPainter`);
  controls never hard-code a colour.
- **CSS-lite theme language** — `:root` variables, type / variant / state selectors,
  `rgb/rgba/lighten/darken/alpha/mix` colour functions, `border` shorthand, linear gradients,
  9-slice images, plus dual `@mode` (light/dark in one file), `@import`, and OS light/dark + accent
  follow.
- **20+ custom-drawn controls** — Button, Label, Edit, Memo, SpinEdit, CheckBox, RadioButton, Panel,
  GroupBox, ComboBox, ListBox, ScrollBar, ProgressBar, ToggleSwitch, TrackBar, PageControl
  (+ TabSheet), Splitter, StatusBar, ToolBar, DateTimePicker, Calendar, TitleBar, CaptionButton.
- **Virtual tree `TTyTreeView`** — a VirtualTreeView-class virtual tree: data-on-demand (scales to
  millions of nodes), multi-column with a draggable header (resize / reorder / sort), checkboxes +
  tri-state + radio nodes, multi-select (Ctrl/Shift) + full-row, variable row height, incremental
  type-to-find, per-cell owner-draw, **inline editing** (F2 / double-click), **node drag-drop**
  (reorder / reparent).
- **Native window `TTyForm`** — borderless + custom-drawn title bar (associable `TTyTitleBar`):
  native window resize on Windows (`Resizable`), maximize that respects the taskbar, OS rounded
  corners + native drop shadow (Windows 11 DWM / macOS, opt-out via CSS).
- **Text editing** — `TTyEdit` single-line (selection / clipboard / horizontal scroll / word-level
  navigation), `TTyMemo` multi-line (2D navigation / cross-line editing / vertical scroll),
  `TTySpinEdit` numeric spin; custom edits support IME (Qt6 / GTK2).
- **Keyboard mnemonics** — `&`-accelerators with Alt-underline display and Alt+letter activation,
  across menus and controls.
- **Native-control harmonization `TTyNativeStyler`** — themes third-party / native LCL controls to
  match the active theme.
- **Internationalization (i18n)** — `resourcestring`s + English / Simplified-Chinese `.po` catalogs
  (theme diagnostics, design-time, demo); the demo switches language at runtime.
- **State transition animations** — `TTyToggleSwitch` knob slides between ON/OFF, `TTyButton` hover
  background fades; per-control `AnimationsEnabled`, with a pure, steppable, testable core.
- **Zero-config default skin + runtime hot-swap** — sensible appearance with no theme loaded or when
  dropped in the designer; `LoadTheme` re-skins every control instantly.
- **HiDPI** — every length scales by PPI; vector drawing stays crisp.
- **Design-time integration** — a "TyControls" component-palette page, a StyleClass property
  drop-down, the PageControl page-manager component editor, and a read-only `About` on every control.
- **1500+ unit tests**, whole suite leak-free (verified with heaptrc).

## Quick start

```pascal
uses tyControls.Controller, tyControls.Button;

// Load a theme (controls with no explicit Controller use the global one)
TyDefaultController.LoadTheme('themes/light.tycss');

// Create a primary button
Btn := TTyButton.Create(Self);
Btn.Parent := Self;
Btn.Caption := 'OK';
Btn.StyleClass := 'primary';   // matches TyButton.primary in the .tycss
```

> Note: a project `.lpr`'s `uses` must start with `Interfaces` (the usual requirement for an LCL
> component library).

Full steps (install the package, first form, theme switching) are in
**[docs/getting-started.md](docs/getting-started.md)**.

## Documentation

| Doc | Contents |
|---|---|
| [getting-started.md](docs/getting-started.md) | Install, first form, theme load/switch, HiDPI |
| [tycss-reference.md](docs/tycss-reference.md) | The authoritative `.tycss` reference: every property, function, selector, merge order |
| [controls/](docs/controls/) | Per-control API (properties / events / states / theme variants / examples) |
| [CHANGELOG.md](CHANGELOG.md) | Release changelog |
| [KNOWN_GAPS.md](docs/KNOWN_GAPS.md) | Known limitations and planned work |

> The newer controls (`TTyTreeView`, `TTySplitter`, `TTyStatusBar`, `TTyToolBar`,
> `TTyDateTimePicker`, `TTyCalendar`) are demonstrated in example projects for now; standalone API
> docs are pending — see the examples below and [CHANGELOG.md](CHANGELOG.md).

## Examples

One independently-buildable minimal project per control (UI built in pure code), plus a combined
gallery and a dedicated TreeView showcase:

| Example | What it shows |
|---|---|
| [examples/treeview](examples/treeview/) | **TTyTreeView showcase**: million-node virtual tree / multi-column + sort / checkboxes + tri-state + radio / multi-select + full-row / inline editing / node drag-drop |
| [examples/demo](examples/demo/) | Combined gallery: all controls + multi-theme switch + custom window frame + runtime language switch |
| [examples/edit](examples/edit/) | Text input, selection, clipboard, word-level navigation, mouse positioning |
| [examples/memo](examples/memo/) | Multi-line editing, cross-line editing, 2D navigation, embedded vertical scrollbar |
| [examples/combobox](examples/combobox/) | Items / selection / OnChange, real drop-down popup |
| [examples/listbox](examples/listbox/) | Item list, keyboard navigation, embedded auto scrollbar |
| [examples/spinedit](examples/spinedit/) | Numeric spin, arrow buttons / arrow keys / wheel, Min/Max/Increment |
| [examples/tabcontrol](examples/tabcontrol/) | Tab switching, closable tabs, keyboard navigation, overflow scroll, drag reorder |
| [examples/formchrome](examples/formchrome/) | Borderless custom-drawn window frame |
| [examples/theming](examples/theming/) | A custom `.tycss` theme + runtime hot-swap |

The remaining per-control examples (button / label / checkbox / radiobutton / panel / groupbox /
scrollbar / progressbar / toggleswitch / trackbar) are under [examples/](examples/). Build any
example with `lazbuild examples/<name>/<name>_example.lpi` (demo is `demo.lpi`, treeview is
`treeviewshowcase.lpi`).

## Build & test

```bash
# Requires: Lazarus 3.x+ / FPC 3.2.2+ / BGRABitmap (package BGRABitmapPack)

lazbuild tycontrols.lpk          # runtime package
lazbuild tycontrols_dt.lpk       # design-time package (install into the IDE)

# Full build matrix (both packages + all examples + the test runner)
bash scripts/build-matrix.sh

# Run the unit tests
lazbuild tests/tytests.lpi && ./tests/tytests -a --format=plain
```

## Layout

```
source/      runtime units (style engine / TTyPainter / controls)
designtime/  design-time registration units
themes/      theme files (light / dark / green / showcase / system …)
examples/    example projects (one per control + the combined demo + the treeview showcase)
tests/       FPCUnit test suite
docs/        documentation
scripts/     build & release scripts
```

## Themes

`themes/` ships `light` / `dark` / `green` / `showcase` and more `.tycss` files, plus a set of
**compiled-in** curated dual-mode themes (`@mode` light/dark in one file) and `system` (follows the
OS light/dark + accent colour). All themes share one set of `:root` semantic variables
(`--accent` / `--surface` / `--on-surface` / `--border` / `--danger` / `--radius` …) — re-skinning
just swaps the variables; `LoadTheme` hot-swaps at runtime and every control repaints instantly.

## License

TyControls is licensed under the **modified LGPL** (the same as FPC RTL / LCL / BGRABitmap): you may
statically link it into closed-source commercial applications; if you modify the library's own
source, those modifications must be released under the same license.

See [COPYING.modifiedLGPL.txt](COPYING.modifiedLGPL.txt) (the exception clause) and
[COPYING.LGPL.txt](COPYING.LGPL.txt) (the LGPL body) for the full terms.
