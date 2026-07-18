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
- **20+ core custom-drawn controls** — Button, Label, Edit, Memo, SpinEdit, CheckBox (tri-state), RadioButton,
  Panel, GroupBox, ComboBox (editable + prefix autocomplete), ListBox, ScrollBar, ProgressBar,
  ToggleSwitch, TrackBar, PageControl (+ TabSheet), TabSet, Splitter, StatusBar, ToolBar,
  DateTimePicker, Calendar, TitleBar, CaptionButton.
- **Extended control families (140+ types, all custom-drawn · cross-platform)** — **instruments/charts**:
  Gauge / Meter / Dial / AnalogClock / Sparkline / Rating / CircularProgress / activity indicators +
  `TTyChart` (line/bar/pie); **Ribbon & navigation**: Ribbon (page/group/app-menu/QAT/Gallery/Backstage);
  **rich inputs & pickers**: numeric/currency/mask/URL/combo/track/calculator edits, colour/font/file
  combos, colour & HS pickers, `TTyValueListEditor` (property inspector); **containers & layout**:
  Bevel/Divider/PaintPanel, RadioGroup/CheckGroup, ScrollBox/ExPanel, GridPanel/RelativePanel,
  ToolBarEx/ControlBar/CoolBar, HeaderControl, ListGroupPanel; **lists/trees/shell**: `TTyListView`
  (report/icon/tile + virtual), `TTyShellTreeView`/`TTyShellListView`/`TTyShellComboBox`/`TTyFilterComboBox`
  (file-system-backed); **menus/effects**: MenuEx/ImagesMenu, vector primitives (Shape/Star/Arrow),
  `TTyImageView` (pan/zoom + BGRA filters), `TTyHtmlLabel` (inline HTML subset), `tyControls.Transitions`
  (slide/fade appearance animations).
- **Ant Design gap controls (14, all custom-drawn · usable under all 20 themes · each documented)** —
  **cards & markers**: `TTyCard` (title/content/actions card, `hoverable` via one `TyCard:hover` rule),
  `TTyTag` (closable tag pill, variants via `StyleClass`), `TTyBadge` (**standalone** count/dot badge
  that pins to any control via `Target`); **feedback**: `TTyAlert` (**inline** alert bar —
  info/success/warning/error), `TTyNotification` (corner auto-dismiss toast), `TTyPopover` (a bubble
  overlay that **hosts controls**); **navigation & flow**: `TTySegmented` (segmented control),
  `TTyPagination` (pager), `TTySteps` (wizard step bar, horizontal/vertical), `TTyBreadcrumb`
  (breadcrumb); **inputs**: `TTyTransfer` (dual-list transfer), `TTyTreeSelect` (tree dropdown),
  `TTyCascader` (cascading select); **empty state**: `TTyEmpty` (illustration + text + optional action).
- **Data grid `TTyStringGrid`** (three layers: `TTyCustomGrid` / `TTyDrawGrid` / `TTyStringGrid`) —
  frozen rows/columns (four panes), virtualised rendering (a million rows paints only the visible
  window), sparse cell storage, 2-D cursor + rectangular multi-select, embedded scrollbars,
  variable row heights, **editing** (text / numeric / checkbox / pick-list / date / colour, per
  cell), **display** (text / progress bar / rating / image, orthogonal to editing), click-to-sort
  (stable merge sort), column filtering (text + header distinct-value checklist), group rows with
  collapse, cell merging, a summary footer (sum/avg/min/max/count over the *filtered* rows),
  clipboard (Excel format) + CSV import/export, column resize and drag-reorder.
- **Virtual tree `TTyTreeView`** — a VirtualTreeView-class virtual tree: data-on-demand (scales to
  millions of nodes), multi-column with a draggable header (resize / reorder / sort), checkboxes +
  tri-state + radio nodes, multi-select (Ctrl/Shift) + full-row, variable row height, incremental
  type-to-find, per-cell owner-draw, **inline editing** (F2 / double-click), **node drag-drop**
  (reorder / reparent).
- **Native window `TTyForm`** — borderless + custom-drawn title bar (associable `TTyTitleBar`):
  native window resize on Windows (`Resizable`), maximize that respects the taskbar, OS rounded
  corners + native drop shadow (Windows 11 DWM / macOS, opt-out via CSS). A form's controls live on
  its content container, **`TTyFormSurface`** (named `Surface`, filling the form) — **put every
  control inside it**; the New Form templates ship with it. See [Form structure](#form-structure).
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
  LCL `TFindDialog` parity) and a Progress dialog (`TTyProgressDialog`); **file dialogs**:
  `TTyOpenDialog` / `TTySaveDialog` + Picture and Preview variants (right-hand image/text preview +
  an `OnPreview` custom hook), a 3-tier API mirroring LCL.
- **Internationalization (i18n)** — `resourcestring`s + English / Simplified-Chinese `.po` catalogs
  (theme diagnostics, design-time, demo); the demo switches language at runtime.
- **State transition animations** — `TTyToggleSwitch` knob slides between ON/OFF, `TTyButton` hover
  background fades; per-control `AnimationsEnabled`, with a pure, steppable, testable core.
- **Zero-config default skin + runtime hot-swap** — sensible appearance with no theme loaded or when
  dropped in the designer; `LoadTheme` re-skins every control instantly.
- **HiDPI** — every length scales by PPI; vector drawing stays crisp.
- **Design-time integration** — a "TyControls" component-palette page, a StyleClass property
  drop-down, the PageControl page-manager component editor, and a read-only `About` on every control.
- **2800+ unit tests**, whole suite leak-free (verified with heaptrc).

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

## Form structure

A `TTyForm`'s controls live on a content container, **`TTyFormSurface`** — exactly one per form, named `Surface`, filling the form. **Put every control inside it.**

- **New forms need no effort**: the File > New *TyControls Form / Application* templates ship with the `Surface` (title bar included), and dropping controls in the designer lands them in it.
- **Graphic controls must go inside**: windowless graphic controls such as `TTyLabel` and `TTyShape` paint onto their parent — one placed directly on the form is hidden behind the `Surface` and **will not be visible**. The designer warns you when you do this.
- **Non-visual components stay on the form**: style controllers, timers, dialog components, image lists, menus are unaffected.
- **Dialogs (`TTyDialog`) have no `Surface`**: they are not resizable and do not need one — controls sit directly on the dialog, as before.

Why it exists: a borderless resizable window cannot paint its own outermost pixels, which left an unpainted strip along the right and bottom edges; a child window paints to the true edge, so the form's themed background is rendered by the `Surface`. Select it in the designer — its `Purpose` property explains the rest.

**Migrating an existing form**: move the controls that sat directly on the form into the `Surface` (leave non-visual components where they are). See [examples/button/umain.lfm](examples/button/umain.lfm).


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

One independently-buildable minimal project per control (each form is a designed `.lfm`, not built
in code), plus a combined gallery and a dedicated TreeView showcase:

| Example | What it shows |
|---|---|
| [examples/treeview](examples/treeview/) | **TTyTreeView showcase**: million-node virtual tree / multi-column + sort / checkboxes + tri-state + radio / multi-select + full-row / inline editing / node drag-drop |
| [examples/antdesign](examples/antdesign/) | **TyControls Pro**: an Ant Design Pro-style admin shell (sider + 6 pages), defaulting to the antdesign skin, with runtime skin switching |
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
| [examples/listview](examples/listview/) | `TTyListView`: five view styles, sorting, multi-select + marquee, checkboxes + F2 rename, **collapsible groups**, a 100k-row virtual mode |
| [examples/theming](examples/theming/) | A custom `.tycss` theme + runtime hot-swap |

The remaining per-control examples (button / label / checkbox / radiobutton / panel / groupbox /
scrollbar / progressbar / toggleswitch / trackbar) are under [examples/](examples/). **Every example
form is a designed `.lfm` using the `TTyForm` + `TTyTitleBar` custom-drawn window frame, with an
in-title-bar theme switcher for live skin changes.** Build any example with
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
themes/      theme sources: root auto/dark/light/green/system; builtin/ = compiled-in structural skins; palettes/ = curated palettes
examples/    example projects (one per control + the combined demo + the treeview showcase)
tests/       FPCUnit test suite
docs/        documentation
scripts/     build & release scripts
```

## Themes

Every built-in theme is **compiled into the binary** — `default` (a neutral `@mode` light/dark base),
`system` (follows the OS light/dark + accent colour), and a whole set of **structural skins**
(`office` / `win11` / `xp` / `classic` / `macos` / `material3` …). An app switches to any of them by
name with no `themes/` folder (`TyBuiltinThemeNames` lists them all). Each skin's `.tycss` source is
also kept in `themes/builtin/` as a **reference for users to base their own themes on** — it is not
read dynamically at runtime. The repo also ships `green` (an image theme, still a file) and the
curated palettes in `themes/palettes/`. All themes share one set of `:root` semantic variables
(`--accent` / `--surface` / `--on-surface` / `--border` / `--danger` / `--radius` …) — re-skinning
just swaps the variables; `--accent` can be overridden at runtime (one theme in any brand colour);
`LoadTheme` / `ThemeName` hot-swaps and every control repaints instantly.

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
