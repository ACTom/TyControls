# TyControls

A skinnable / styleable **Lazarus component library**: every control is fully custom-drawn
(BGRABitmap) and its appearance is driven uniformly by lightweight CSS-lite text themes
(`.tycss`), rendering pixel-identical on Windows / Linux / macOS.

> **中文:** [README.md](README.md) · **Changelog:** [CHANGELOG.en.md](CHANGELOG.en.md)

![Ant Design Pro layout example](docs/images/antd-antdesign.png)

**Same program, one theme name changed:**

| `classic` | `win11` | `material3` |
|---|---|---|
| ![classic theme](docs/images/antd-classic.png) | ![win11 theme](docs/images/antd-win11.png) | ![material3 theme](docs/images/antd-material3.png) |

All four are the **same `.lfm` and the same application code** — only the theme name differs.
Not one control hardcodes a colour, corner radius or line width; every visual value comes from
a theme token. Look at `classic`: it isn't just recoloured — the 3D button bevels, the gradient
header band and the square corners changed too.

> Screenshots are from the Ant Design Pro example. Its UI is currently Chinese; an English
> render will land once the examples are internationalised.

---

## Features

- **Fully custom-drawn** — every control is painted with BGRABitmap; nothing wraps a native
  control. The same code is the same pixels on Windows, Linux and macOS.
- **Appearance separated from code** — colours, radii, borders, padding, font sizes, shadows,
  gradients and 9-slice images all live in `.tycss` text. Restyling needs no recompile;
  `LoadTheme` hot-swaps at runtime.
- **Structural skinning** — a theme is more than a palette: `render-style` turns a flat button
  into a 3D bevelled one, and geometry tokens change a control's intrinsic size.
- **Two density scales** — classic (Win32 scale) and modern (web scale) are an axis
  **orthogonal** to colour, switched by one `Controller.Density` property.
- **Follows the OS** — light/dark mode and accent colour can track the operating system; a
  single-file `@mode` carries both sets of values.
- **160 droppable controls** across 16 component-palette pages — see the [control list](#control-list).
- **Designer-first** — every control has a palette icon, a read-only `Version` property and a
  `StyleClass` dropdown. `TTyPageControl`'s pages and `TTyGridPanel`'s cells are **real designer
  containers**: drop controls straight into them and they persist to the `.lfm`.
- **HiDPI** — every length scales by PPI; vector drawing stays crisp.
- **Internationalised** — the library's own UI strings go through `resourcestring` + `.po`,
  shipped in English and Simplified Chinese.
- **3949 unit tests**, whole suite leak-free (heaptrc-verified). Appearance additionally has a
  pixel-level golden guard — every change to a theme's resolved styles must be deliberate.

---

## Quick start

**1. Install the package**

In Lazarus open `tycontrols_dt.lpk` (the design-time package) → **Use → Install**; the IDE
recompiles and restarts. The runtime package `tycontrols.lpk` comes in automatically as a
dependency.

> Requires: Lazarus 3.x+ / FPC 3.2.2+ / **BGRABitmap** (OPM package `BGRABitmapPack`).

**2. New project**

**File → New… → Project → TyControls Application**

The template gives you a wired-up `TTyForm` main form: custom-drawn title bar, the content-host
container `Surface`, and a `TTyStyleController`, all in place and associated. Drop controls onto
`Surface`.

> To add a form to an existing project use **File → New… → Form → TyControls Form**.

**3. Switch theme**

Select the `TTyStyleController` on the main form and set `ThemeName` to any built-in name
(`default` / `system` / `win11` / `classic` / `material3` / …). The designer updates instantly;
change the same property at runtime to hot-swap.

Full steps (first form, theme switching, HiDPI, deployment) → **[docs/getting-started.md](docs/getting-started.md)**.

---

## Form structure

A `TTyForm`'s controls live on a content-host container, **`TTyFormSurface`** — exactly one per
form, named `Surface`, filling the whole window. **Put your controls inside it.**

- **New forms need no thought**: both templates ship with `Surface` already there, and dropping
  a control in the designer lands it inside.
- **Graphic controls MUST go inside**: windowless graphic controls like `TTyLabel` and
  `TTyShape` paint onto their parent — placed on the form directly they are hidden behind
  `Surface`. The designer warns you when you do this.
- **Non-visual components stay on the form**: style controllers, timers, dialog components,
  image lists, menus are unaffected.
- **Dialogs (`TTyDialog`) have no `Surface`**: they are not resizable and do not need one;
  place controls directly on them.

Why it exists: a borderless resizable window cannot paint its own outermost pixels, leaving an
unpainted band along the right/bottom edge — but a child window can paint edge to edge, so the
form's themed background is rendered by `Surface`. Select it in the designer; its `Purpose`
property explains the rest.

**Migrating an existing form**: move the controls that sat directly on the form into `Surface`
(leave non-visual components alone). See [examples/button/umain.lfm](examples/button/umain.lfm).

---

## Control list

160 controls you can drop from the component palette, across 16 pages. Per-control
properties / events / states / theme keys are in **[docs/controls/](docs/controls/)**.

### Core · `TyControls` (2)
`TTyStyleController` the style controller · `TTyNativeStyler` themes native / third-party LCL controls

### Buttons · `TyControls Buttons` (8)
`TTyButton` · `TTyGlyphButton` icon button · `TTyGlyphContainerButton` · `TTySpeedButton` · `TTyDropDownButton` split · `TTyMenuButton` · `TTyColorButton` · `TTyButtonGroup` segmented bar

### Labels & marks · `TyControls Labels` (7)
`TTyLabel` · `TTyHtmlLabel` inline HTML subset · `TTyLinkLabel` · `TTyShadowLabel` · `TTyGlowLabel` · `TTyTag` closable tag · `TTyBadge` numeric / dot badge

### Text & numeric input · `TyControls Edits` (13)
`TTyEdit` · `TTyMemo` multiline · `TTySpinEdit` · `TTyNumericEdit` · `TTyCurrencyEdit` · `TTyMaskEdit` · `TTyURLEdit` · `TTyComboEdit` · `TTyTrackEdit` inline slider · `TTyCalcEdit` / `TTyCalcCurrencyEdit` inline calculator · `TTyCalculator` · `TTyUpDown`

### Choices & switches · `TyControls Choices` (6)
`TTyCheckBox` tri-state · `TTyRadioButton` · `TTyToggleSwitch` · `TTyRadioGroup` · `TTyCheckGroup` · `TTySegmented`

### Lists & dropdowns · `TyControls Lists` (14)
`TTyComboBox` editable + prefix autocomplete · `TTyListBox` · `TTyCheckListBox` · `TTyMRUComboBox` · `TTyComboBoxEx` with images · `TTyOfficeComboBox` / `TTyOfficeListBox` grouped · `TTyAdvancedComboBox` / `TTyAdvancedListBox` two-line · `TTyCheckComboBox` · `TTyValueListEditor` property grid · `TTyTransfer` · `TTyTreeSelect` · `TTyCascader`

### Colour / font / file pickers · `TyControls Pickers` (11)
`TTyColorBox` · `TTyColorComboBox` · `TTyColorListBox` · `TTyColorGrid` palette · `TTyLColorPicker` / `TTyHSColorPicker` · `TTyFontComboBox` / `TTyFontListBox` / `TTyFontSizeComboBox` · `TTyFilterComboBox` · `TTyShellComboBox`

### Gauges & indicators · `TyControls Gauges` (12)
`TTyGauge` linear / arc / ring · `TTyMeter` needle · `TTyLevelMeter` · `TTyDial` / `TTyGearDial` knobs · `TTyAnalogClock` · `TTyCircularProgress` · `TTyActivityIndicator` / `TTyActivityBar` / `TTyGearActivityIndicator` busy · `TTySparkline` · `TTyRating`

### Bars · `TyControls Bars` (14)
`TTyTrackBar` · `TTyProgressBar` · `TTyScrollBar` · `TTyStatusBar` · `TTyToolBar` + `TTyToolSeparator` · `TTyToolBarEx` overflow · `TTyControlBar` / `TTyCoolBar` draggable bands · `TTyAlert` inline banner · `TTyPagination` · `TTySteps` · `TTyBreadcrumb` · `TTyHeaderControl`

### Containers & layout · `TyControls Containers` (20)
`TTyPanel` · `TTyGroupBox` · `TTyCard` · `TTyExPanel` collapsible · `TTyScrollBox` / `TTyScrollPanel` · `TTyGridPanel` **designer grid** · `TTyRelativePanel` · `TTyPageControl` + `TTyTabSheet` **designer pager** · `TTyTabSet` pure tab strip · `TTySplitter` · `TTyBevel` · `TTyDivider` · `TTyPaintPanel` · `TTySizeBox` · `TTyToolGroupPanel` · `TTyListGroupPanel` · `TTyTitleBar` · `TTyEmpty`

### Data views · `TyControls Data Views` (10)
`TTyStringGrid` / `TTyDrawGrid` **data grid** · `TTyTreeView` **virtual tree** · `TTyListView` five views · `TTyShellTreeView` / `TTyShellListView` file system · `TTyCalendar` · `TTyDateTimePicker` · `TTyImageView` pan/zoom + filters · `TTyPreviewBox`

### Menus · `TyControls Menus` (4)
`TTyMenuBar` · `TTyPopupMenu` · `TTyImagesMenu` · `TTyMenuEx`

### Ribbon · `TyControls Ribbon` (7)
`TTyRibbon` + `TTyRibbonPage` + `TTyRibbonGroup` · `TTyRibbonAppMenu` · `TTyRibbonQuickAccess` · `TTyRibbonGallery` · `TTyRibbonBackstage`

### Images & hints · `TyControls Images` (9)
`TTyIconFont` icon font · `TTyCharImage` · `TTyImage` · `TTyGlyphImageList` · `TTyImageCollection` · `TTyVirtualImageList` · `TTyHint` · `TTyBalloonHint` · `TTyPopover` control-hosting popover

### Shapes & charts · `TyControls Shapes & Charts` (4)
`TTyShape` · `TTyStarShape` · `TTyArrow` · `TTyChart` line / bar / pie

### Dialogs · `TyControls Dialogs` (19)
`TTyMessage` · `TTyInputDialog` · `TTyPasswordDialog` · `TTyTextDialog` · `TTySelectValueDialog` · `TTySelectPathDialog` · `TTyColorDialog` · `TTyFontDialog` · `TTyFindDialog` / `TTyReplaceDialog` modeless · `TTyProgressDialog` · `TTyAboutDialog` · `TTyOpenDialog` / `TTySaveDialog` + picture + preview variants · `TTyNotification` corner toast

> Three controls do far more than one list line can say:
> **[`TTyStringGrid`](docs/controls/grid.md)** — frozen rows/cols, million-row virtualization,
> 16 built-in editors, Excel-style column filters, group subtotals, undo/redo, clipboard & CSV;
> **[`TTyTreeView`](docs/controls/treeview.md)** — lazy-loaded virtual tree, multi-column
> draggable header, tri-state checks, inline edit, node drag-drop;
> **[`TTyForm`](docs/controls/ttyform.md)** — borderless custom window with native resize,
> system rounded corners and drop shadow.

---

## Themes

Every built-in theme is **compiled into the binary**, so an app can switch by name with no
`themes/` folder shipped (`TyBuiltinThemeNames` lists them all).

| Theme | About |
|---|---|
| `default` | neutral base with `@mode` light/dark in one file |
| `system` | follows the OS light/dark + accent |
| `win11` `win10` `xp` `classic` `aero` | Windows generations |
| `macos` `adwaita` `breeze` `ubuntu` | macOS and Linux desktops |
| `material3` `fluent` `antdesign` `bootstrap` | design systems |
| `office` | Office style |
| `showcase` | a showpiece theme |

Also `green` (an image theme, shipped as a file) and the curated palettes under
`themes/palettes/`. All themes share one set of `:root` semantic variables, and `--accent` can
be overridden at runtime — one theme, any brand colour.

**Write your own theme** → [docs/themes.md](docs/themes.md) · **full `.tycss` reference** →
[docs/tycss-reference.md](docs/tycss-reference.md)

---

## Examples

Each example is a standalone buildable project: `lazbuild examples/<name>/<project>.lpi`.

| Example | Shows |
|---|---|
| [antdesign](examples/antdesign/) | **TyControls Pro** — an Ant Design Pro-style admin (sider + 6 pages), runtime theming |
| [demo](examples/demo/) | gallery: all controls + multiple themes + runtime language switch |
| [grid](examples/grid/) | `TTyStringGrid` in six pages: freeze / million-row virtual / sort-filter-group / 16 editors / undo-redo |
| [treeview](examples/treeview/) | `TTyTreeView`: million-node virtual tree / multi-column sort / tri-state checks / inline edit / node drag-drop |
| [dialogs](examples/dialogs/) | all 11 custom-drawn dialogs (modal and modeless) |
| [theming](examples/theming/) | a custom `.tycss` theme + runtime hot-swap |
| [ribbon](examples/ribbon/) | Ribbon: page / group / app menu / QAT / Gallery / Backstage |
| [containers](examples/containers/) | `TTyGridPanel` / `TTyExPanel` / `TTyScrollBox` layout containers |
| [listview](examples/listview/) | `TTyListView`: five views / grouped collapse / 100k virtual |
| [inputs](examples/inputs/) | rich input: numeric / currency / mask / URL / slider / calculator edits |
| [shapes](examples/shapes/) | `TTyShape` / `TTyStarShape` / `TTyArrow` + `StyleOverride` |
| [icons](examples/icons/) | `TTyIconFont` icon font |
| [transitions](examples/transitions/) | slide / fade transitions |

Other single-control examples (button / label / labels / edit / memo / combobox / listbox /
spinedit / checkbox / radiobutton / panel / groupbox / scrollbar / progressbar / toggleswitch /
trackbar / splitter / statusbar / toolbar / menu / calendar / datetimepicker / tabcontrol /
tabset / chart / gauge / hint / htmllabel / imageview / filedialog / shell) are under
[examples/](examples/).

---

## Documentation

| Doc | Contents |
|---|---|
| [getting-started.md](docs/getting-started.md) | install, first form, loading/switching themes, HiDPI |
| [controls/](docs/controls/) | per-control API (properties / events / states / theme keys / example) |
| [themes.md](docs/themes.md) | writing your own theme |
| [tycss-reference.md](docs/tycss-reference.md) | the `.tycss` language reference: properties, functions, selectors, merge order, typeKey catalogue |
| [events.md](docs/events.md) | the tiered common-event convention |
| [CHANGELOG.en.md](CHANGELOG.en.md) | changelog |

---

## UI language

TyControls' own UI strings (dialog buttons, ThemeLint diagnostics, …) use a resourcestring
catalogue **independent of the host application**, shipped in English and Simplified Chinese.

LCL's `SetDefaultLang` only loads **your app's** `.po`, not the library's — so add one more line:

```pascal
uses ..., LCLTranslator;

SetDefaultLang('', LangDir);                                                       // your app
TranslateUnitResourceStringsEx('', LangDir, 'tycontrols', 'tyControls.StrConsts');  // the library
Application.CreateForm(TMainForm, MainForm);
```

Deploy `languages/tycontrols.<lang>.po` next to your own `.po` in the `languages/` folder beside
the executable.

> **The file's base name must not contain a dot.** The third argument must be `'tycontrols'` —
> LCL's `FindLocaleFileName` calls `ChangeFileExt` on it, so `'tycontrols.strconsts'` would have
> `.strconsts` stripped as an extension. The real dotted unit name `tyControls.StrConsts` goes in
> the fourth argument.
>
> To force a language (bypassing OS-locale detection), pass the language name in both places:
> `SetDefaultLang('zh_CN', LangDir)` + `TranslateUnitResourceStringsEx('zh_CN', …)`.

Full example: [examples/demo](examples/demo/).

---

## License

TyControls is licensed under the **modified LGPL** (the same as FPC RTL / LCL / BGRABitmap):
you may statically link it into a closed-source commercial application and distribute that; if
you modify the library's own source, the modified parts must be released under the same license.

Full terms: [COPYING.modifiedLGPL.txt](COPYING.modifiedLGPL.txt) (the exception) and
[COPYING.LGPL.txt](COPYING.LGPL.txt) (the LGPL body).
