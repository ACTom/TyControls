# TyControls

A custom-drawn component library for Lazarus. All 162 controls are rendered with BGRABitmap and styled by `.tycss` text themes, so your UI looks exactly the same on Windows, Linux, and macOS.

> **中文:** [README.md](README.md) · **Changelog:** [CHANGELOG.en.md](CHANGELOG.en.md)

![Ant Design Pro layout example](docs/images/antd-antdesign.png)

**Same program, different theme name:**

| `classic` | `win11` | `material3` |
|---|---|---|
| ![classic theme](docs/images/antd-classic.png) | ![win11 theme](docs/images/antd-win11.png) | ![material3 theme](docs/images/antd-material3.png) |

All four screenshots share one `.lfm` and one code base; only the theme name differs. Themes go beyond colors: under `classic`, buttons get 3D bevels, square corners, and a gradient header band.

### Light / dark / image themes

| Light | Dark | `green` (image theme) |
|---|---|---|
| ![light](docs/images/demo-light.png) | ![dark](docs/images/demo-dark.png) | ![green image theme](docs/images/demo-green.png) |

Light and dark are two `@mode` value sets in one theme file and can follow the OS. `green` is an image theme: translucent controls over a photo background.

### A few of the controls

| | |
|---|---|
| **`TTyStringGrid`** frozen columns, row gutter, summary band<br>![data grid](docs/images/grid.png) | **`TTyTreeView`** virtual tree, multi-column, tri-state checks<br>![virtual tree](docs/images/treeview.png) |
| **Rich input controls** numeric / currency / mask / slider / calculator<br>![rich input](docs/images/inputs.png) | **Custom-drawn dialogs** color picker<br>![color dialog](docs/images/colordialog.png) |

---

## Features

- **162 controls**: buttons, inputs, lists, data grid, virtual tree, Ribbon, calendar, shell file browsing, and 20 custom-drawn dialogs
- **Identical on all three platforms**: fully custom-drawn, no native control wrapping — one code base renders the same UI everywhere
- **Theming**: 17 built-in themes switched by a single property, with runtime hot-swap and OS light/dark and accent-color following; themes are text files, so restyling needs no recompile
- **Classic and modern looks**: from Win95 / XP bevels to Win11 / Material flat design, with a switchable control-density scale
- **HiDPI**: vector drawing stays crisp at any scale; DPI adapts automatically when dragging across monitors
- **Full designer support**: palette drag-and-drop, container controls you drop into directly, live theme preview at design time, File → New project templates
- **2,022 vector icons built in** (Lucide), referenced by name, zero cost if unused
- **English and Chinese UI**, gettext `.po` translations
- **6,000+ unit tests**, whole suite leak-free

## Supported platforms

| Platform | Widgetset |
|---|---|
| Windows | Win32 / Win64 |
| Linux | GTK2, Qt5, Qt6; GTK3 partially supported ([known issues](docs/known-issues.en.md) under Wayland) |
| macOS | Cocoa |

Requires Lazarus 3.x+, FPC 3.2.2+, and BGRABitmap (OPM package `BGRABitmapPack`).

---

## Quick start

**1. Install the package**

Open `tycontrols_dt.lpk` in Lazarus and click **Use → Install**; the IDE rebuilds and restarts. The runtime package `tycontrols.lpk` installs automatically as a dependency.

**2. New project**

**File → New… → Project → TyControls Application**

The template creates a main form with a custom-drawn title bar, the content container `Surface`, and a style controller already wired up. Put your controls on `Surface` — a `TTyForm`'s visual controls all live there, and graphic controls must (see the [TTyForm docs](docs/controls/ttyform.md)). To add a form to an existing project, use **File → New… → Form → TyControls Form**.

**3. Switch themes**

Select the `TTyStyleController` on the form and set `ThemeName` to any built-in theme name. The designer updates immediately; change the same property at runtime to hot-swap.

Full walkthrough: [docs/getting-started.en.md](docs/getting-started.en.md).

---

## Control list

162 controls across 16 palette pages. Per-control properties, events, and theme keys: **[docs/controls/](docs/controls/)**.

### Core · `TyControls` (2)

| Control | Description |
|---|---|
| `TTyStyleController` | Style controller: loads themes, switches density, follows OS light/dark |
| `TTyNativeStyler` | Themes native / third-party LCL controls to match |

### Buttons · `TyControls Buttons` (8)

| Control | Description |
|---|---|
| `TTyButton` | Button with primary / danger / ghost variants and a numeric badge |
| `TTyGlyphButton` | Button with an icon |
| `TTyGlyphContainerButton` | Square icon-only button, typical on toolbars |
| `TTySpeedButton` | Shortcut button that can stay pressed |
| `TTyDropDownButton` | Split button: left half acts, right half opens a menu |
| `TTyMenuButton` | The whole button is the dropdown trigger |
| `TTyColorButton` | Button that shows and picks a color |
| `TTyButtonGroup` | Segmented bar; adjacent segments share edges, one selected |

### Labels & marks · `TyControls Labels` (7)

| Control | Description |
|---|---|
| `TTyLabel` | Text label with word wrap (including per-glyph CJK breaking) and mnemonics |
| `TTyHtmlLabel` | Label supporting an inline HTML subset (bold / italic / link / color) |
| `TTyLinkLabel` | Hyperlink text |
| `TTyShadowLabel` | Label with a drop shadow |
| `TTyGlowLabel` | Label with a glow outline |
| `TTyTag` | Closable tag pill |
| `TTyBadge` | Numeric / dot badge that can attach to any control |

### Text & numeric input · `TyControls Edits` (14)

| Control | Description |
|---|---|
| `TTyEdit` | Single-line edit: selection, clipboard, word navigation |
| `TTyMemo` | Multi-line edit |
| `TTySpinEdit` | Integer spinner |
| `TTyFloatSpinEdit` | Decimal spinner; the step can be less than 1 |
| `TTyNumericEdit` | Digits-only field, group-formatted on blur |
| `TTyCurrencyEdit` | Currency field |
| `TTyMaskEdit` | Masked input (phone, ID, date) |
| `TTyURLEdit` | URL field with a trailing open button |
| `TTyComboEdit` | Edit plus a dropdown arrow; you decide what drops down |
| `TTyTrackEdit` | Numeric field with an inline slider |
| `TTyCalcEdit` | Field with an inline calculator |
| `TTyCalcCurrencyEdit` | Currency calculator field |
| `TTyCalculator` | Standalone calculator panel |
| `TTyUpDown` | Standalone up/down spinner, bindable to another control |

### Choices & switches · `TyControls Choices` (6)

| Control | Description |
|---|---|
| `TTyCheckBox` | Check box, tri-state capable |
| `TTyRadioButton` | Radio button |
| `TTyToggleSwitch` | Toggle switch |
| `TTyRadioGroup` | Titled radio group |
| `TTyCheckGroup` | Titled check-box group |
| `TTySegmented` | Segmented control |

### Lists & dropdowns · `TyControls Lists` (14)

| Control | Description |
|---|---|
| `TTyComboBox` | Combo box, editable, with prefix autocomplete |
| `TTyListBox` | List box |
| `TTyCheckListBox` | List with a check box per row |
| `TTyMRUComboBox` | Combo box that remembers recent entries |
| `TTyComboBoxEx` | Combo box with a per-item image |
| `TTyOfficeComboBox` | Combo box with group headers |
| `TTyOfficeListBox` | List with group headers |
| `TTyAdvancedComboBox` | Two-line items (title + subtitle + image) |
| `TTyAdvancedListBox` | Rich two-line list |
| `TTyCheckComboBox` | Multi-select combo box |
| `TTyValueListEditor` | Property grid: key on the left, value on the right, editor kind per row |
| `TTyTransfer` | Dual-list transfer |
| `TTyTreeSelect` | Selector whose dropdown is a tree |
| `TTyCascader` | Cascading multi-column selector |

### Color / font / file pickers · `TyControls Pickers` (11)

| Control | Description |
|---|---|
| `TTyColorBox` | Color dropdown |
| `TTyColorComboBox` | Color dropdown with a trailing More… entry opening the color dialog |
| `TTyColorListBox` | Color list |
| `TTyColorGrid` | Swatch grid palette |
| `TTyLColorPicker` | Lightness bar picker |
| `TTyHSColorPicker` | Hue / saturation picker |
| `TTyFontComboBox` | Font dropdown; each item previews in its own typeface |
| `TTyFontListBox` | Font list |
| `TTyFontSizeComboBox` | Font-size dropdown |
| `TTyFilterComboBox` | File-type filter dropdown |
| `TTyShellComboBox` | Directory dropdown |

### Gauges & indicators · `TyControls Gauges` (12)

| Control | Description |
|---|---|
| `TTyGauge` | Gauge: linear / arc / ring |
| `TTyMeter` | Needle gauge |
| `TTyLevelMeter` | VU meter with lit segments and peak hold |
| `TTyDial` | Rotary knob |
| `TTyGearDial` | Knob with a toothed rim |
| `TTyAnalogClock` | Analog clock |
| `TTyCircularProgress` | Ring progress |
| `TTyActivityIndicator` | Spinning busy ring |
| `TTyActivityBar` | Indeterminate progress bar |
| `TTyGearActivityIndicator` | Gear-shaped busy indicator |
| `TTySparkline` | Mini trend chart |
| `TTyRating` | Star rating |

### Bars · `TyControls Bars` (15)

| Control | Description |
|---|---|
| `TTyTrackBar` | Slider |
| `TTyProgressBar` | Progress bar |
| `TTyScrollBar` | Scroll bar |
| `TTyStatusBar` | Status bar |
| `TTyToolBar` | Toolbar |
| `TTyToolButton` | Toolbar button: six styles (command / toggle / dropdown / grouped / separator, …) |
| `TTyToolSeparator` | Toolbar separator |
| `TTyToolBarEx` | Toolbar that folds overflow into a menu |
| `TTyControlBar` | Container that wraps children into bands |
| `TTyCoolBar` | Draggable band container |
| `TTyAlert` | Inline alert: info / success / warning / error |
| `TTyPagination` | Pager |
| `TTySteps` | Step bar |
| `TTyBreadcrumb` | Breadcrumb trail |
| `TTyHeaderControl` | Standalone column header strip |

### Containers & layout · `TyControls Containers` (20)

| Control | Description |
|---|---|
| `TTyPanel` | Panel |
| `TTyGroupBox` | Group box |
| `TTyCard` | Card: title / content / actions |
| `TTyExPanel` | Collapsible panel |
| `TTyScrollBox` | Scrollable container |
| `TTyScrollPanel` | Container that auto-scrolls near its edges |
| `TTyGridPanel` | Designer grid container; drop controls straight into its cells |
| `TTyRelativePanel` | Layout by relative rules |
| `TTyPageControl` | Page container; drop controls straight onto its pages |
| `TTyTabSheet` | One page of a `TTyPageControl` |
| `TTyTabSet` | Pure tab strip, hosts no pages |
| `TTySplitter` | Splitter |
| `TTyBevel` | Decorative bevel |
| `TTyDivider` | Divider line, optionally captioned |
| `TTyPaintPanel` | Panel that hands you its canvas |
| `TTySizeBox` | Bottom-right size grip |
| `TTyToolGroupPanel` | Tool group container |
| `TTyListGroupPanel` | List container with group headers |
| `TTyTitleBar` | Custom-drawn title bar, pairs with `TTyForm` |
| `TTyEmpty` | Empty state: illustration + text + action button |

### Data views · `TyControls Data Views` (10)

| Control | Description |
|---|---|
| `TTyStringGrid` | Data grid: freezing, virtualization, editing, filtering, grouping, undo/redo |
| `TTyDrawGrid` | Owner-drawn grid |
| `TTyTreeView` | Virtual tree, million-node capable; multi-column, tri-state checks, inline edit, drag-drop |
| `TTyListView` | List view: report / icon / tile and more, grouping, virtual mode |
| `TTyShellTreeView` | File-system directory tree |
| `TTyShellListView` | File-system file list |
| `TTyCalendar` | Calendar with day / month / year drill-down |
| `TTyDateTimePicker` | Date-time picker with null-date support |
| `TTyImageView` | Image viewer: pan, zoom, filters |
| `TTyPreviewBox` | File preview pane |

### Menus · `TyControls Menus` (4)

| Control | Description |
|---|---|
| `TTyMenuBar` | Main menu bar |
| `TTyPopupMenu` | Context menu |
| `TTyImagesMenu` | Menu with per-item icons |
| `TTyMenuEx` | Extended menu |

### Ribbon · `TyControls Ribbon` (7)

| Control | Description |
|---|---|
| `TTyRibbon` | The ribbon itself |
| `TTyRibbonPage` | Ribbon page |
| `TTyRibbonGroup` | Group within a page |
| `TTyRibbonAppMenu` | Application (File) button |
| `TTyRibbonQuickAccess` | Quick access toolbar |
| `TTyRibbonGallery` | Gallery that expands into a popup grid |
| `TTyRibbonBackstage` | Full-window backstage view |

### Images & hints · `TyControls Images` (9)

| Control | Description |
|---|---|
| `TTyIconFont` | Icon font: vector icons by codepoint or name, themed |
| `TTyCharImage` | Uses one icon-font glyph as an image |
| `TTyImage` | Image control |
| `TTyGlyphImageList` | Image list driven by an icon font |
| `TTyImageCollection` | Multi-resolution image set, picked per DPI |
| `TTyVirtualImageList` | Renders any size on demand; it is a standard `TCustomImageList`, assignable to any control, addressable by image name |
| `TTyHint` | Themed tooltip |
| `TTyBalloonHint` | Balloon tooltip with a pointer |
| `TTyPopover` | Popover that hosts controls |

**Built-in icons (Lucide)**: one `uses tyControls.Icons.Lucide` gives you 2,022 vector icons, referenced by name:

```pascal
CharImage1.IconFont  := TyLucideFont;
CharImage1.GlyphName := 'house';
```

The font is embedded in the unit — nothing to ship or install, and it costs nothing if you don't use it. `TTyLucideImageList` on the palette works as a drop-in image list. Licensed ISC / MIT with no attribution required at runtime; just ship [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) with your release.

### Shapes & charts · `TyControls Shapes & Charts` (4)

| Control | Description |
|---|---|
| `TTyShape` | Vector shape: 15 kinds (rectangle / circle / triangle / diamond / star, …) plus custom polygons |
| `TTyStarShape` | Star with a configurable point count |
| `TTyArrow` | Directional arrow |
| `TTyChart` | Chart: line / bar / pie |

### Dialogs · `TyControls Dialogs` (20)

| Control | Description |
|---|---|
| `TTyMessage` | Message box |
| `TTyInputDialog` | Text input dialog |
| `TTyPasswordDialog` | Password dialog |
| `TTyTextDialog` | Multi-line text dialog |
| `TTySelectValueDialog` | Pick-from-a-list dialog |
| `TTySelectPathDialog` | Folder picker |
| `TTyColorDialog` | Color picker: HSV / RGB / CMYK / alpha |
| `TTyFontDialog` | Font dialog with live preview |
| `TTyFindDialog` | Find dialog |
| `TTyReplaceDialog` | Find-and-replace dialog |
| `TTyProgressDialog` | Progress dialog |
| `TTyAboutDialog` | About box |
| `TTyOpenDialog` | Open-file dialog |
| `TTySaveDialog` | Save-file dialog |
| `TTyOpenPictureDialog` | Open-picture dialog with thumbnails |
| `TTySavePictureDialog` | Save-picture dialog |
| `TTyOpenPreviewDialog` | Open dialog with a custom preview pane |
| `TTySavePreviewDialog` | Save dialog with a custom preview pane |
| `TTyNotification` | Corner toast |
| `TTyIconBrowserDialog` | Icon browser |

For the full capabilities of `TTyStringGrid`, `TTyTreeView`, and `TTyForm`, see their docs: [grid.md](docs/controls/grid.md) · [treeview.md](docs/controls/treeview.md) · [ttyform.md](docs/controls/ttyform.md).

---

## Themes

Built-in themes are compiled into the binary, so apps switch by name without shipping a `themes/` folder:

| Theme | Description |
|---|---|
| `default` | Neutral base, light and dark in one file |
| `system` | Follows the OS light/dark and accent color |
| `win11` `win10` `xp` `classic` `aero` | Windows generations |
| `macos` `adwaita` `breeze` `ubuntu` | macOS and Linux desktops |
| `material3` `fluent` `antdesign` `bootstrap` | Common design systems |
| `office` | Office style |
| `showcase` | Showcase theme |

Also the image theme `green` (shipped as a file) and curated palettes under `themes/palettes/`. All themes share one set of semantic variables, and `--accent` can be overridden at runtime with any brand color.

Writing your own theme: [docs/themes.en.md](docs/themes.en.md). The `.tycss` language reference: [docs/tycss-reference.en.md](docs/tycss-reference.en.md).

---

## Examples

Each example builds standalone: `lazbuild examples/<name>/<project>.lpi`.

| Example | Contents |
|---|---|
| [antdesign](examples/antdesign/) | Ant Design Pro-style admin (sider + 6 pages), runtime theming |
| [demo](examples/demo/) | Gallery: all controls + themes + language switching |
| [grid](examples/grid/) | Data grid: freezing / million rows / sort-filter-group / 16 editors / undo-redo |
| [treeview](examples/treeview/) | Virtual tree: million nodes / multi-column / checks / inline edit / drag-drop |
| [dialogs](examples/dialogs/) | All custom-drawn dialogs |
| [theming](examples/theming/) | A custom theme + runtime hot-swap |
| [ribbon](examples/ribbon/) | The full Ribbon |
| [containers](examples/containers/) | Layout containers |
| [listview](examples/listview/) | List view: five views / grouping / 100k rows virtual |
| [inputs](examples/inputs/) | Rich input controls |
| [shapes](examples/shapes/) | Shape controls + `StyleOverride` |
| [rtl](examples/rtl/) | Right-to-left mirroring and bidirectional text |
| [icons](examples/icons/) | Icon fonts |
| [transitions](examples/transitions/) | Slide / fade transitions |

Thirty-plus single-control examples live under [examples/](examples/).

---

## Documentation

| Doc | Contents |
|---|---|
| [getting-started.en.md](docs/getting-started.en.md) | Install, first form, themes, HiDPI |
| [controls/](docs/controls/) | Per-control API reference (Chinese) |
| [themes.en.md](docs/themes.en.md) | Built-in themes and writing your own |
| [tycss-reference.en.md](docs/tycss-reference.en.md) | The `.tycss` language reference |
| [events.en.md](docs/events.en.md) | Common event conventions |
| [rtl.md](docs/rtl.md) | Bidirectional text and right-to-left layout (Chinese) |
| [known-issues.en.md](docs/known-issues.en.md) | Known issues |
| [CHANGELOG.en.md](CHANGELOG.en.md) | Changelog |

---

## UI language

The library ships with English and Chinese UI strings. LCL's `SetDefaultLang` only loads your app's `.po`, so add one line for the library:

```pascal
uses ..., LCLTranslator;

SetDefaultLang('', LangDir);                                                        // your app
TranslateUnitResourceStringsEx('', LangDir, 'tycontrols', 'tyControls.StrConsts');  // the library
```

Deploy `languages/tycontrols.<lang>.po` next to your own `.po` files. Two notes:

- The deployed file name is `tycontrols.<lang>.po`, renamed from the source's `tycontrols.strconsts.<lang>.po`. The third argument must be `'tycontrols'` (no dot — LCL strips everything after a dot as an extension); the real unit name `tyControls.StrConsts` goes in the fourth.
- English deployments should ship `tycontrols.en.po` too; it is the switch that makes the calendar's and date picker's month and weekday names follow the app language.

Full example: [examples/demo](examples/demo/).

---

## License

Modified LGPL, the same license as the FPC RTL, LCL, and BGRABitmap: you may statically link the library into closed-source commercial applications; modifications to the library's own source must be released under the same license.

Full terms: [COPYING.modifiedLGPL.txt](COPYING.modifiedLGPL.txt) and [COPYING.LGPL.txt](COPYING.LGPL.txt).
