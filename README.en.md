# TyControls

A skinnable / styleable **Lazarus component library**: every control is fully custom-drawn
(BGRABitmap) and its appearance is driven uniformly by lightweight CSS-lite text themes
(`.tycss`), rendering pixel-identical on Windows / Linux / macOS.

> **中文:** [README.md](README.md) ·  **Changelog:** [CHANGELOG.en.md](CHANGELOG.en.md)

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
- **20+ custom-drawn controls** — Button, Label, Edit, Memo, SpinEdit, CheckBox (tri-state), RadioButton,
  Panel, GroupBox, ComboBox (editable + prefix autocomplete), ListBox, ScrollBar, ProgressBar,
  ToggleSwitch, TrackBar, PageControl (+ TabSheet), TabSet, Splitter, StatusBar, ToolBar,
  DateTimePicker, Calendar, TitleBar, CaptionButton.
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
- **Dialog subsystem** — custom-drawn themed modal dialogs: `TyShowMessage` / `TyMessageDlg`
  (mtWarning / mtError / mtConfirmation / mtInformation + full LCL button set) global functions,
  `TTyDialog` derivable base class (Enter/Esc + right-aligned button bar), and a `TTyMessage`
  design-time component; **input-family dialogs**: `TyInputQuery` (single-line text) /
  `TyPasswordBox` (masked password) / `TyTextQuery` (resizable multi-line) / `TySelectValue`
  (list single-select) / `TySelectDirectory` (folder picker); **picker dialogs**: `TySelectColor`
  (HSV/RGB/CMYK/Alpha color picker with full bidirectional sync) / `TyFontDialog` (family, size,
  style, color + live preview); button captions and type titles are internationalized
  (resourcestring + zh_CN); plus **modeless** Find/Replace (`TTyFindDialog` / `TTyReplaceDialog`,
  LCL `TFindDialog` parity) and a Progress dialog (`TTyProgressDialog`).
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
| [CHANGELOG.en.md](CHANGELOG.en.md) | Release changelog |
| [KNOWN_GAPS.md](docs/KNOWN_GAPS.md) | Known limitations and planned work |

> The newer controls (`TTyTreeView`, `TTySplitter`, `TTyStatusBar`, `TTyToolBar`,
> `TTyDateTimePicker`, `TTyCalendar`, `TTyTabSet`) ship both example projects (below) and
> per-control [API docs](docs/controls/).

## Examples

One independently-buildable minimal project per control (UI built in pure code), plus a combined
gallery and a dedicated TreeView showcase:

| Example | What it shows |
|---|---|
| [examples/treeview](examples/treeview/) | **TTyTreeView showcase**: million-node virtual tree / multi-column + sort / checkboxes + tri-state + radio / multi-select + full-row / inline editing / node drag-drop |
| [examples/demo](examples/demo/) | Combined gallery: all controls + multi-theme switch + custom window frame + runtime language switch |
| [examples/dialogs](examples/dialogs/) | **All 11 custom-drawn dialogs**: message / input / password / text / select-value / select-path / colour / font / find / replace / progress (modal and modeless) |
| [examples/edit](examples/edit/) | Text input, selection, clipboard, word-level navigation, mouse positioning |
| [examples/memo](examples/memo/) | Multi-line editing, cross-line editing, 2D navigation, embedded vertical scrollbar |
| [examples/combobox](examples/combobox/) | Items / selection / OnChange, real drop-down popup |
| [examples/listbox](examples/listbox/) | Item list, keyboard navigation, embedded auto scrollbar |
| [examples/spinedit](examples/spinedit/) | Numeric spin, arrow buttons / arrow keys / wheel, Min/Max/Increment |
| [examples/tabcontrol](examples/tabcontrol/) | `TTyPageControl` + `TTyTabSheet`: multi-page container, switch ActivePage, independent per-page content |
| [examples/tabset](examples/tabset/) | `TTyTabSet`: pure tab strip, `TabIndex` switching, OnChange |
| [examples/calendar](examples/calendar/) | `TTyCalendar`: date picking, day/month/year drill-down, Min/MaxDate |
| [examples/datetimepicker](examples/datetimepicker/) | `TTyDateTimePicker`: date drop-down calendar + time segment spin |
| [examples/splitter](examples/splitter/) | `TTySplitter`: drag-resizable divider between panels |
| [examples/statusbar](examples/statusbar/) | `TTyStatusBar`: bottom multi-panel status bar |
| [examples/toolbar](examples/toolbar/) | `TTyToolBar` + `TTyToolSeparator`: toolbar with buttons and separators |
| [examples/menu](examples/menu/) | `TTyMenuBar` + `TTyPopupMenu`: menu bar + right-click popup menu |
| [examples/shapes](examples/shapes/) | `TTyShape` / `TTyStarShape` / `TTyArrow`: vector shapes, recolouring via `StyleOverride`, live sliders, theme switch |
| [examples/theming](examples/theming/) | A custom `.tycss` theme + runtime hot-swap |

The remaining per-control examples (button / label / checkbox / radiobutton / panel / groupbox /
scrollbar / progressbar / toggleswitch / trackbar) are under [examples/](examples/). **Every example
form uses the `TTyForm` + `TTyTitleBar` custom-drawn window frame.** Build any example with
`lazbuild examples/<name>/<name>_example.lpi` (demo is `demo.lpi`, treeview is `treeviewshowcase.lpi`).

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

## Enabling translations

TyControls' own user-facing strings (dialog buttons, labels, ThemeLint diagnostics, …) live in a
separate resourcestring catalog from your application's. LCL's `SetDefaultLang('', LangDir)` only
auto-loads `languages/<exe-name>.<lang>.po` — it never touches the library's catalog, so those
strings stay at their English msgids no matter what UI language your app picks. Load the package
catalog explicitly, right after `SetDefaultLang` and before any form is created:

```pascal
uses ..., LCLTranslator;
...
SetDefaultLang('', LangDir);
TranslateUnitResourceStringsEx('', LangDir, 'tycontrols', 'tyControls.StrConsts');
Application.CreateForm(TMainForm, MainForm);
```

Deploy the catalog as `languages/tycontrols.<lang>.po` (built from this repo) — a **dot-free** file
stem — next to your exe's own `languages/` folder, alongside your app's own `.po` files. Do **not**
name it `tycontrols.strconsts.<lang>.po`: LCL's `FindLocaleFileName` runs the file stem you pass
through `ChangeFileExt`, which treats the dot before `strconsts` as an extension separator and
strips it, so it would search for `tycontrols.<lang>.po` regardless of what you deployed. Passing
`'tycontrols'` as the third argument (`LocaleFileName`) keeps the file lookup dot-free, while the
fourth argument (`LocaleUnitName`) supplies the real dotted unit name `tyControls.StrConsts` so the
resourcestring identifiers still match. See [examples/demo](examples/demo/) for a working setup
(`demo.lpr` + `examples/demo/languages/tycontrols.zh_CN.po`).

To force Chinese output regardless of the machine's OS locale (e.g. for testing), drive the language
explicitly instead of relying on auto-detection — `SetDefaultLang('')` and `TranslateUnitResourceStringsEx`
with an empty `Lang` argument auto-detect the OS locale (or honor a `--lang=` command-line
parameter, already supported by the demo/example apps). Pass `'zh_CN'` directly instead:

```pascal
SetDefaultLang('zh_CN', LangDir);
TranslateUnitResourceStringsEx('zh_CN', LangDir, 'tycontrols', 'tyControls.StrConsts');
```

## License

TyControls is licensed under the **modified LGPL** (the same as FPC RTL / LCL / BGRABitmap): you may
statically link it into closed-source commercial applications; if you modify the library's own
source, those modifications must be released under the same license.

See [COPYING.modifiedLGPL.txt](COPYING.modifiedLGPL.txt) (the exception clause) and
[COPYING.LGPL.txt](COPYING.LGPL.txt) (the LGPL body) for the full terms.
