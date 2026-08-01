

# TyControls

A **Lazarus component library** supporting skins/styles: fully self-drawn controls (using BGRABitmap), with appearance uniformly driven by CSS-lite text themes (`.tycss`), delivering pixel-perfect consistent interfaces across Windows / Linux / macOS.

> **English:** [README.en.md](README.en.md) · **Changelog:** [CHANGELOG.md](CHANGELOG.md)

![Ant Design Pro Layout Example](docs/images/antd-antdesign.png)

**The same application, changing only the theme name:**

| `classic` | `win11` | `material3` |
|---|---|---|
| ![classic theme](docs/images/antd-classic.png) | ![win11 theme](docs/images/antd-win11.png) | ![material3 theme](docs/images/antd-material3.png) |

All four images above are from the **exact same `.lfm` file and the same business code**, differing only by a single theme name. There are no hardcoded colors, border radii, or line widths in the controls — everything comes from theme tokens. Notice the `classic` image: it's not just the color scheme that changes, but also the 3D button borders, the gradient on the title bar, and the sharp corners.

### Light / Dark / Image Themes

In the comprehensive gallery example (`examples/demo`), the same form:

| Light | Dark | `green` (Image Theme) |
|---|---|---|
| ![Light](docs/images/demo-light.png) | ![Dark](docs/images/demo-dark.png) | ![Green Image Theme](docs/images/demo-green.png) |

Light/Dark are two `@mode` values within the same `.tycss` file, capable of following the OS. `green` demonstrates how far themes can go — translucent controls floating over a photo background, using 9-slice tiling and the `alpha()` color function, without a single line of control code being modified for it.

### Appearance of a Few Controls

| | |
|---|---|
| **`TTyStringGrid`** —— Frozen columns, row number gutter, summary band, cell marker colors<br>![Data Grid](docs/images/grid.png) | **`TTyTreeView`** —— Virtual tree, multi-column, tri-state checkboxes<br>![Virtual Tree](docs/images/treeview.png) |
| **Rich Input Controls** —— Numeric / Currency / Mask / Slider / Calculator edits<br>![Rich Inputs](docs/images/inputs.png) | **Self-drawn Dialog** —— Color picker: HSV + RGB / CMYK / Alpha, fully bidirectional<br>![Color Dialog](docs/images/colordialog.png) |

---

## Features

- **Fully self-drawn** — Every control is rendered using BGRABitmap, without wrapping native controls. The same code produces identical pixels on Windows, Linux, and macOS.
- **Separation of appearance and code** — Colors, border radii, borders, padding, font sizes, shadows, gradients, and 9-slice tiles are all defined in `.tycss` text files. Change the appearance without recompiling; hot-swap at runtime with a single `LoadTheme` call.
- **Structural-level theming** — Themes do more than change colors: `render-style` can switch a button from flat to a 3D border, and geometric tokens can alter a control's intrinsic dimensions.
- **Dual density scales** — Classic (Win32 scale) and Modern (Web scale) form an axis **orthogonal** to color schemes, switchable via a single `Controller.Density` property.
- **Follows the system** — Light/dark modes and accent colors can follow the OS; a single-file `@mode` carries both sets of values simultaneously.
- **160 drag-and-drop controls**, organized across 16 component panel tabs — see [Control List](#control-list).
- **Designer-first** — Pages in `TTyPageControl` and cells in `TTyGridPanel` are **true designer containers**: drag controls directly into them, see the final result in the designer, and save with `.lfm` files without writing a single line of layout code. Theme changes are visible in the designer.
- **HiDPI** — All dimensions scale by PPI, with vector rendering ensuring native clarity.
- **Internationalization** — The library's own UI strings use `resourcestring` + `.po`, provided in English and Simplified Chinese.
- **3,949 unit tests**, with zero memory leaks across the full suite (verified by heaptrc). Appearance is further guarded by pixel-level golden tests — any change in theme parsing results must be intentional.

---

## Quick Start

**1. Install the package**

Open `tycontrols_dt.lpk` (design-time package) in Lazarus → **Use → Install**. The IDE will recompile and restart. The runtime package `tycontrols.lpk` will be installed automatically as a dependency.

> Dependencies: Lazarus 3.x+ / FPC 3.2.2+ / **BGRABitmap** (OPM package name `BGRABitmapPack`).

**2. Create a new project**

**File → New… → Project → TyControls Application**

The template provides a pre-assembled `TTyForm` main window: self-drawn title bar, content container `Surface`, and `TTyStyleController` are all in place and linked. Simply drag controls onto `Surface`.

> To add a form to an existing project, use **File → New… → Form → TyControls Form**.

**3. Switch themes**

Select the `TTyStyleController` on the main form and set `ThemeName` to any built-in theme name (`default` / `system` / `win11` / `classic` / `material3` / …). Changes are visible immediately in the designer; modifying the same property at runtime performs a hot swap.

For the full steps (first form, theme switching, HiDPI, deployment), see **[docs/getting-started.md](docs/getting-started.md)**.

---

## Form Structure

Controls in `TTyForm` are hosted on a content container **`TTyFormSurface`** — each form has exactly one, named `Surface`, covering the entire form. **Place all controls inside it.**

- **No need to worry for new forms**: Both templates come with `Surface` pre-configured, and dragging controls in the designer automatically places them inside it.
- **Graphic controls must be placed inside it**: Windowless graphic controls like `TTyLabel` and `TTyShape` paint onto their parent control — placing them directly on the form will hide them behind `Surface`, making them **invisible**. The designer will warn you if you do this.
- **Non-visual components remain on the form**: Style controllers, timers, dialog components, image lists, menus, etc., are unaffected.
- **Dialogs (`TTyDialog`) do not have a `Surface`**: They are not resizable and don't need one; place controls directly on them as usual.

**Why it exists — the root cause is Windows.** Resizable top-level windows have `WS_THICKFRAME`, but Windows' DWM backing surface for them is **smaller** than the window's visible area (height is only `window height - 2×border`). Consequently, the form's own GDI client area DC is cropped, leaving an unpaintable dead zone on the right and bottom edges. Child windows lack this border layer; their backing surfaces cover their full rectangles, allowing drawing all the way to the edges — so `TTyForm` delegates the themed background to `Surface` instead of painting it on itself.

This container is harmless across all widgetsets, so no Windows-specific fork is needed. It also conveniently solves a second issue: since controls are **children of `Surface`**, windowless controls like `TTyLabel` paint onto `Surface`'s canvas and remain visible — if you merely placed a background image at the bottom of the form, they would be obscured.

In the designer, select `Surface` to see the same explanation in the `Purpose` property.

---

## Control List

160 drag-and-drop controls available from the component panel, organized into 16 tabs. Per-control documentation for properties / events / states / theme keys can be found in **[docs/controls/](docs/controls/)**.

### Core · `TyControls` (2)

| Control | Purpose |
|---|---|
| `TTyStyleController` | Style controller: loads themes, switches density, follows system light/dark; controls retrieve styles via it |
| `TTyNativeStyler` | Allows native / third-party LCL controls to follow the current theme's coloring |

### Buttons · `TyControls Buttons` (8)

| Control | Purpose |
|---|---|
| `TTyButton` | Basic button, supports primary / danger / ghost variants and numeric badges |
| `TTyGlyphButton` | Icon button, icons from icon fonts or image collections |
| `TTyGlyphContainerButton` | Square button holding a single icon, commonly used in toolbars |
| `TTySpeedButton` | Shortcut button that can maintain a pressed state |
| `TTyDropDownButton` | Split button: left half executes action, right half drops down menu |
| `TTyMenuButton` | Entire button acts as a dropdown trigger |
| `TTyColorButton` | Button to display and select a color |
| `TTyButtonGroup` | Segmented button bar, adjacent segments share edges, single selection |

### Labels & Tags · `TyControls Labels` (7)

| Control | Purpose |
|---|---|
| `TTyLabel` | Text label, supports auto-wrap (including CJK character-by-character breaking) and mnemonics |
| `TTyHtmlLabel` | Label supporting an inline HTML subset (bold / italic / links / colors) |
| `TTyLinkLabel` | Hyperlink text with underline and hover highlighting |
| `TTyShadowLabel` | Label with drop shadow |
| `TTyGlowLabel` | Label with glowing stroke |
| `TTyTag` | Closable tag capsule, used for filters and status markers |
| `TTyBadge` | Numeric / dot badge, can attach to the top-right corner of any control |

### Text & Numeric Inputs · `TyControls Edits` (13)

| Control | Purpose |
|---|---|
| `TTyEdit` | Single-line text box: selection, clipboard, word-level navigation, horizontal scroll |
| `TTyMemo` | Multi-line text box: 2D navigation, cross-line editing, vertical scroll |
| `TTySpinEdit` | Numeric spin box with up/down arrows |
| `TTyNumericEdit` | Input box accepting only numbers, formats with thousands separator on focus loss |
| `TTyCurrencyEdit` | Currency input box, automatically adds currency symbol |
| `TTyMaskEdit` | Input constrained by a mask (phone, ID, date, etc.) |
| `TTyURLEdit` | URL input box with an open button at the end |
| `TTyComboEdit` | Text box + dropdown arrow, dropdown content is customizable |
| `TTyTrackEdit` | Text box with an embedded slider, value can be dragged or typed |
| `TTyCalcEdit` | Text box with an embedded calculator button, click to calculate |
| `TTyCalcCurrencyEdit` | Currency version of the calculator input box |
| `TTyCalculator` | Standalone calculator panel |
| `TTyUpDown` | Standalone spin buttons, can be bound to other controls |

### Checkboxes & Toggles · `TyControls Choices` (6)

| Control | Purpose |
|---|---|
| `TTyCheckBox` | Checkbox, supports tri-state |
| `TTyRadioButton` | Radio button |
| `TTyToggleSwitch` | Toggle switch, knob slides between two states |
| `TTyRadioGroup` | Radio group with titled border, auto-layout |
| `TTyCheckGroup` | Checkbox group with titled border |
| `TTySegmented` | Segmented control: a row of mutually exclusive options, selects a value rather than switching pages |

### Lists & Dropdowns · `TyControls Lists` (14)

| Control | Purpose |
|---|---|
| `TTyComboBox` | Dropdown box, editable with prefix auto-completion |
| `TTyListBox` | Item list with keyboard navigation and embedded scrollbar |
| `TTyCheckListBox` | List with checkboxes on each row |
| `TTyMRUComboBox` | Dropdown that remembers recent inputs and pins them to the top |
| `TTyComboBoxEx` | Dropdown with icons per item |
| `TTyOfficeComboBox` | Dropdown with grouped header bands |
| `TTyOfficeListBox` | List with grouped header bands |
| `TTyAdvancedComboBox` | Dropdown with two lines per item (title + subtitle + icon) |
| `TTyAdvancedListBox` | Rich list with two lines per item |
| `TTyCheckComboBox` | Multi-select dropdown, field displays a summary of selected items |
| `TTyValueListEditor` | Property grid: left key, right value, editable row types |
| `TTyTransfer` | Dual-list shuttle box, moves items between two sides |
| `TTyTreeSelect` | Selector with a tree inside the dropdown |
| `TTyCascader` | Cascading selector: multi-column picker that expands level by level |

### Color / Font / File Pickers · `TyControls Pickers` (11)

| Control | Purpose |
|---|---|
| `TTyColorBox` | Color dropdown, each item is a color swatch |
| `TTyColorComboBox` | Color dropdown with a "More…" option at the end to open the color dialog |
| `TTyColorListBox` | Color list |
| `TTyColorGrid` | Grid-style color palette |
| `TTyLColorPicker` | Lightness bar color picker |
| `TTyHSColorPicker` | Hue / Saturation plane color picker |
| `TTyFontComboBox` | Font dropdown, each item previews using that font |
| `TTyFontListBox` | Font list |
| `TTyFontSizeComboBox` | Font size dropdown |
| `TTyFilterComboBox` | File type filter dropdown |
| `TTyShellComboBox` | Directory dropdown, used with file views |

### Gauges & Indicators · `TyControls Gauges` (12)

| Control | Purpose |
|---|---|
| `TTyGauge` | Gauge: linear / arc / circular forms |
| `TTyMeter` | Needle-style dial with tick marks |
| `TTyLevelMeter` | Level meter, segmented illumination + peak hold |
| `TTyDial` | Rotary knob |
| `TTyGearDial` | Decorative knob with a gear-shaped outer ring |
| `TTyAnalogClock` | Analog clock |
| `TTyCircularProgress` | Circular progress, displays percentage in the center |
| `TTyActivityIndicator` | Spinning busy indicator ring |
| `TTyActivityBar` | Indeterminate progress bar |
| `TTyGearActivityIndicator` | Gear-shaped busy indicator |
| `TTySparkline` | Mini trend chart, embedded in cards or grids |
| `TTyRating` | Star rating, supports hover preview |

### Bar Controls · `TyControls Bars` (14)

| Control | Purpose |
|---|---|
| `TTyTrackBar` | Slider |
| `TTyProgressBar` | Progress bar |
| `TTyScrollBar` | Scroll bar |
| `TTyStatusBar` | Multi-zone bottom status bar |
| `TTyToolBar` | Toolbar |
| `TTyToolSeparator` | Toolbar separator |
| `TTyToolBarEx` | Toolbar that automatically collapses overflowing buttons into an overflow menu |
| `TTyControlBar` | Multi-band container with draggable/reorderable bands |
| `TTyCoolBar` | Windows-style draggable band |
| `TTyAlert` | Inline alert bar: info / success / warning / error |
| `TTyPagination` | Paginator |
| `TTySteps` | Step indicator, horizontal or vertical |
| `TTyBreadcrumb` | Breadcrumb navigation |
| `TTyHeaderControl` | Standalone column header bar, resizable and sortable |

### Containers & Layouts · `TyControls Containers` (20)

| Control | Purpose |
|---|---|
| `TTyPanel` | Basic panel |
| `TTyGroupBox` | Group box with title |
| `TTyCard` | Card: three-section layout (title / content / actions) |
| `TTyExPanel` | Collapsible panel with an expand arrow in the title bar |
| `TTyScrollBox` | Scrollable container |
| `TTyScrollPanel` | Container that auto-scrolls when dragging to the edge |
| `TTyGridPanel` | **Designer grid**: set rows and columns to generate cells, drag controls directly into cells |
| `TTyRelativePanel` | Container that layouts based on relative relationships (right of X, aligned with Y) |
| `TTyPageControl` | **Designer multi-page container**, pages are true containers that accept dragged controls |
| `TTyTabSheet` | A single page of `TTyPageControl` |
| `TTyTabSet` | Pure tab strip, does not host pages; content switching is handled manually |
| `TTySplitter` | Draggable panel splitter |
| `TTyBevel` | Raised/sunken decorative line |
| `TTyDivider` | Divider line, optionally with a centered title |
| `TTyPaintPanel` | Panel that hands its canvas over to you for custom drawing |
| `TTySizeBox` | Resize handle at the bottom-right corner |
| `TTyToolGroupPanel` | Tool group container |
| `TTyListGroupPanel` | List container with grouped headers |
| `TTyTitleBar` | Self-drawn title bar, used with `TTyForm` |
| `TTyEmpty` | Empty state: illustration + text + optional action button |

### Data Views · `TyControls Data Views` (10)

| Control | Purpose |
|---|---|
| `TTyStringGrid` | **Data grid**: frozen rows/cols, virtualization, editing, filtering, grouping, undo/redo |
| `TTyDrawGrid` | Grid where data is provided via events, content self-drawn |
| `TTyTreeView` | **Virtual tree**: on-demand loading, supports millions of nodes; multi-column, checkboxes, inline editing, drag-and-drop |
| `TTyListView` | List view: report / icon / tile / list / small icon views + grouping + virtual mode |
| `TTyShellTreeView` | File system directory tree |
| `TTyShellListView` | File system file list |
| `TTyCalendar` | Calendar: day / month / year drill-down |
| `TTyDateTimePicker` | Date-time picker, dropdown calendar + minute interval spin |
| `TTyImageView` | Image viewer: pan, zoom, BGRA filters |
| `TTyPreviewBox` | File preview box, used with file dialogs |

### Menus · `TyControls Menus` (4)

| Control | Purpose |
|---|---|
| `TTyMenuBar` | Main menu bar |
| `TTyPopupMenu` | Right-click context menu |
| `TTyImagesMenu` | Menu with icons per item |
| `TTyMenuEx` | Extended menu, supports richer item styling |

### Ribbon · `TyControls Ribbon` (7)

| Control | Purpose |
|---|---|
| `TTyRibbon` | Ribbon main body, hosts multiple pages |
| `TTyRibbonPage` | A single ribbon page |
| `TTyRibbonGroup` | A functional group within a page |
| `TTyRibbonAppMenu` | Top-left application menu (File) button |
| `TTyRibbonQuickAccess` | Quick Access Toolbar |
| `TTyRibbonGallery` | Gallery: a row of visual options, expandable into a popup grid |
| `TTyRibbonBackstage` | Full-window backstage view (the screen shown when File expands) |

### Images & Hints · `TyControls Images` (9)

| Control | Purpose |
|---|---|
| `TTyIconFont` | Icon font: retrieves vector icons by codepoint, colors follow theme |
| `TTyCharImage` | Uses an icon font glyph as an image |
| `TTyImage` | Image control, supports transparency and scaling modes |
| `TTyGlyphImageList` | Image list driven by an icon font |
| `TTyImageCollection` | Multi-resolution image set, selects the best match based on DPI |
| `TTyVirtualImageList` | Generates image lists of specified sizes on demand from a collection |
| `TTyHint` | Themed hint bubble |
| `TTyBalloonHint` | Balloon hint with arrow |
| `TTyPopover` | **Control-hosting** bubble overlay, not just text |

### Shapes & Charts · `TyControls Shapes & Charts` (4)

| Control | Purpose |
|---|---|
| `TTyShape` | Vector shapes: rectangle / circle / ellipse / triangle / diamond / rounded rectangle / line |
| `TTyStarShape` | Star shape, adjustable points |
| `TTyArrow` | Directional arrow |
| `TTyChart` | Chart: line / bar / pie |

### Dialogs · `TyControls Dialogs` (19)

| Control | Purpose |
|---|---|
| `TTyMessage` | Message box (info / warning / error / confirm) |
| `TTyInputDialog` | Single-line text input dialog |
| `TTyPasswordDialog` | Masked password input dialog |
| `TTyTextDialog` | Resizable multi-line text dialog |
| `TTySelectValueDialog` | List single-select dialog |
| `TTySelectPathDialog` | Folder selection dialog |
| `TTyColorDialog` | Color dialog: HSV / RGB / CMYK / Alpha, fully bidirectional |
| `TTyFontDialog` | Font dialog with live preview |
| `TTyFindDialog` | Find dialog (modeless) |
| `TTyReplaceDialog` | Find & Replace dialog (modeless) |
| `TTyProgressDialog` | Progress dialog |
| `TTyAboutDialog` | About dialog |
| `TTyOpenDialog` | Open file dialog |
| `TTySaveDialog` | Save file dialog |
| `TTyOpenPictureDialog` | Open picture dialog with thumbnails |
| `TTySavePictureDialog` | Save picture dialog |
| `TTyOpenPreviewDialog` | Open dialog + custom preview on the right |
| `TTySavePreviewDialog` | Save dialog + custom preview on the right |
| `TTyNotification` | Corner popup notification, auto-dismisses |

> Three controls exceed what a single-line list can capture:
> **[`TTyStringGrid`](docs/controls/grid.md)** —— Frozen rows/cols, million-row virtualization, 16 built-in editors, Excel-style column filtering, group subtotals, undo/redo, clipboard & CSV import/export;
> **[`TTyTreeView`](docs/controls/treeview.md)** —— Virtual tree with on-demand data loading, draggable multi-column headers, tri-state checkboxes, inline editing, node drag-and-drop;
> **[`TTyForm`](docs/controls/ttyform.md)** —— Borderless self-drawn window, featuring native resizing, system-style rounded corners, and drop shadows.

---

## Themes

All built-in themes are **compiled into the binary**, so the app can switch by name without needing a `themes/` folder (`TyBuiltinThemeNames` lists them all).

| Theme | Description |
|---|---|
| `default` | Neutral base with light/dark `@mode` in a single file |
| `system` | Follows OS light/dark mode + accent color |
| `win11` `win10` `xp` `classic` `aero` | Windows generations |
| `macos` `adwaita` `breeze` `ubuntu` | macOS and Linux desktop environments |
| `material3` `fluent` `antdesign` `bootstrap` | Design systems |
| `office` | Office-style |
| `showcase` | Showcase/theme demo |

Additionally, `green` (an image theme, provided as files) and curated palettes in `themes/palettes/` are available. All themes share the same `:root` semantic variables, and `--accent` can be overridden at runtime — one theme, any brand color.

**Write your own theme** → [docs/themes.md](docs/themes.md) · **`.tycss` language full reference** → [docs/tycss-reference.md](docs/tycss-reference.md)

---

## Examples

Each example is a minimal, independently buildable project: `lazbuild examples/<name>/<project>.lpi`.

| Example | Demonstrates |
|---|---|
| [antdesign](examples/antdesign/) | **TyControls Pro** —— Ant Design Pro-style backend (side nav + 6 pages), runtime theme switching |
| [demo](examples/demo/) | Comprehensive gallery: all controls + multiple themes + runtime language switching |
| [grid](examples/grid/) | `TTyStringGrid` six pages: frozen / million-row virtual / sort/filter/group / 16 editors / undo/redo |
| [treeview](examples/treeview/) | `TTyTreeView`: million-node virtual tree / multi-column sort / tri-state checkboxes / inline editing / node drag-and-drop |
| [dialogs](examples/dialogs/) | All 11 self-drawn dialogs (modal & modeless) |
| [theming](examples/theming/) | Custom `.tycss` themes + runtime hot-swapping |
| [ribbon](examples/ribbon/) | Ribbon: pages / groups / app menu / QAT / Gallery / Backstage |
| [containers](examples/containers/) | Layout containers: `TTyGridPanel` / `TTyExPanel` / `TTyScrollBox`, etc. |
| [listview](examples/listview/) | `TTyListView`: five views / group collapsing / 100k-row virtualization |
| [inputs](examples/inputs/) | Rich inputs: numeric / currency / mask / URL / slider / calculator edits |
| [shapes](examples/shapes/) | `TTyShape` / `TTyStarShape` / `TTyArrow` + `StyleOverride` |
| [icons](examples/icons/) | `TTyIconFont` icon fonts |
| [transitions](examples/transitions/) | Slide / fade transitions |

Additional single-control examples (button / label / labels / edit / memo / combobox / listbox / spinedit / checkbox / radiobutton / panel / groupbox / scrollbar / progressbar / toggleswitch / trackbar / splitter / statusbar / toolbar / menu / calendar / datetimepicker / tabcontrol / tabset / chart / gauge / hint / htmllabel / imageview / filedialog / shell) can be found in [examples/](examples/).

---

## Documentation

| Document | Content |
|---|---|
| [getting-started.md](docs/getting-started.md) | Installation, first form, theme loading & switching, HiDPI |
| [controls/](docs/controls/) | Per-control API documentation (properties / events / states / theme keys / examples) |
| [themes.md](docs/themes.md) | Writing your own themes |
| [tycss-reference.md](docs/tycss-reference.md) | `.tycss` language authoritative reference: properties, functions, selectors, merge order, typeKey directory |
| [events.md](docs/events.md) | Common event delegation conventions |
| [CHANGELOG.md](CHANGELOG.md) | Version update log |

---

## Interface Language

TyControls' own UI strings (dialog buttons, ThemeLint diagnostics, etc.) use a **separate** `resourcestring` directory from the host application, provided in English and Simplified Chinese.

LCL's `SetDefaultLang` only loads **your application's** `.po` files, not the component library's — so you need an extra line:

```pascal
uses ..., LCLTranslator;

SetDefaultLang('', LangDir);                                                       // Your application
TranslateUnitResourceStringsEx('', LangDir, 'tycontrols', 'tyControls.StrConsts');  // Component library
Application.CreateForm(TMainForm, MainForm);
```

Place `languages/tycontrols.<lang>.po` alongside your own `.po` files in the `languages/` directory next to the executable.

> **The file base name must not contain a dot.** The third parameter must be `'tycontrols'` — LCL's `FindLocaleFileName` calls `ChangeFileExt` on it, and passing `'tycontrols.strconsts'` would strip `.strconsts` as an extension. The fourth parameter should receive the actual dotted unit name `tyControls.StrConsts`.
>
> To force a specific language (ignoring system locale detection), pass the language name to both calls: `SetDefaultLang('zh_CN', LangDir)` + `TranslateUnitResourceStringsEx('zh_CN', …)`.

A complete example can be found in [examples/demo](examples/demo/).

---

## License

TyControls is licensed under a **Modified LGPL** (same as FPC RTL / LCL / BGRABitmap): allows static linking into closed-source commercial applications for distribution; if you modify the library's source code, the modifications must be released under the same license.

See full terms in [COPYING.modifiedLGPL.txt](COPYING.modifiedLGPL.txt) (exception clause) and [COPYING.LGPL.txt](COPYING.LGPL.txt) (LGPL text).
