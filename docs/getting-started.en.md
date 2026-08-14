# Getting started with TyControls

For Lazarus developers using TyControls for the first time.

> 中文版见 [getting-started.md](getting-started.md)。

---

## 1. Introduction

TyControls is a skinnable component library for Lazarus. Your application gets a consistent, custom look on Windows, Linux, and macOS without depending on any native control styling.

**The three-layer architecture in one line:**

```
Controls (TTyButton / TTyEdit / …)
  → Style engine (TTyStyleController: parses .tycss, returns property sets)
    → Drawing primitives (TTyPainter: wraps BGRABitmap, vector drawing)
```

The layers are strictly decoupled: controls know nothing about colors, the engine knows nothing about drawing, and the painter knows nothing about controls.

**Platforms and dependencies:**

| Item | Requirement |
|---|---|
| Lazarus | 3.x+ |
| FPC | 3.2.2+ |
| Third-party dependency | BGRABitmap (runtime only) |
| Target platforms | Windows / Linux / macOS |

---

## 2. Installation

### Option A — IDE install (recommended)

1. **Install BGRABitmapPack**
   - In the Lazarus IDE, open **Package → Online Package Manager (OPM)**, search for `BGRABitmap`, install, and rebuild the IDE;
   - or install from source: **Package → Open Package File (.lpk)**, pick BGRABitmapPack's `.lpk`, compile, install.

2. **Compile the runtime package**
   Open `tycontrols.lpk` and click **Compile**.

3. **Install the design-time package**
   Open `tycontrols_dt.lpk` and click **Install**; the IDE rebuilds automatically.
   After the rebuild, the component palette gains the **TyControls** pages and all controls can be dropped onto forms.

> `tycontrols.lpk` depends on `BGRABitmapPack` and `LCL`.
> `tycontrols_dt.lpk` depends on `tycontrols` and `IDEIntf`.

### Option B — source-only (no package install)

Add TyControls' `source/` directory to your project's `OtherUnitFiles` in the `.lpi`. The examples use this approach:

```xml
<SearchPaths>
  <OtherUnitFiles Value=".;../../source"/>
  <UnitOutputDirectory Value="lib/$(TargetCPU)-$(TargetOS)"/>
</SearchPaths>
```

List only `LCL` and `BGRABitmapPack` under `RequiredPackages` (no `tycontrols` package entry needed).

---

## 3. Your first form

A minimal compilable example that creates a themed `TTyButton` in pure code. The full source is in `examples/button/`.

### Program file (`.lpr`)

The `.lpr` must include `Interfaces` in its `uses` clause, or the LCL widgetset fails to initialize on non-Windows platforms:

```pascal
program button_example;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces,   // required: initializes the LCL widgetset
  Forms, umain;

begin
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
```

### Form unit

```pascal
unit umain;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Button, tyControls.TyLabel;

type
  TMainForm = class(TForm)
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  MainForm: TMainForm;

implementation

{ Walk up from the exe directory looking for themes/, so lazbuild's
  lib/<cpu>-<os>/ output path also works }
function ThemesDir: string;
var
  Dir: string;
  i: Integer;
begin
  Dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  for i := 1 to 8 do
  begin
    if DirectoryExists(Dir + 'themes') then
      Exit(Dir + 'themes' + PathDelim);
    Dir := ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
    if Dir = '' then Break;
  end;
  Result := 'themes' + PathDelim;
end;

constructor TMainForm.Create(AOwner: TComponent);
var
  Btn: TTyButton;
begin
  inherited CreateNew(AOwner, 0);
  Caption := 'My first TyControls form';
  SetBounds(0, 0, 320, 200);
  Position := poScreenCenter;

  // Load a theme into the global controller.
  // Controls without an explicit Controller register with TyDefaultController.
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  // A default button
  Btn := TTyButton.Create(Self);
  Btn.Parent := Self;
  Btn.SetBounds(24, 24, 160, 32);
  Btn.Caption := 'Default button';

  // A primary-variant button (matches TyButton.primary in the .tycss)
  Btn := TTyButton.Create(Self);
  Btn.Parent := Self;
  Btn.SetBounds(24, 64, 160, 32);
  Btn.Caption := 'Primary button';
  Btn.StyleClass := 'primary';
end;

end.
```

**Key points:**

- `TyDefaultController` is a global singleton created by the library. Controls whose `Controller` property is unset register with it automatically.
- `LoadTheme(AFileName)` loads a `.tycss` theme from a file and notifies every registered control to repaint.
- `StyleClass` names a variant in the `.tycss` (`'primary'` matches `TyButton.primary { … }`).

---

## 4. Themes

### Built-in default skin (zero configuration)

TyControls compiles a default skin into the library (light, identical to `themes/light.tycss`). Controls look right even if you never load a theme:

- controls with no explicit `Controller` and no `LoadTheme` call show the built-in default;
- controls dropped in the Lazarus form designer render with the built-in default too, without running the program.

A loaded theme overrides the built-in skin **per typeKey**:

- a complete theme (`light` / `dark` / `showcase` define every control) replaces the built-in look entirely;
- a partial theme (say, only `TyButton` rules, or just `:root` variable changes plus a few controls) styles the controls it mentions, and everything else keeps the built-in default — nothing goes blank.

> Suppression is per typeKey: once a theme writes any rule for a typeKey, the built-in default for that whole typeKey yields to the theme, so built-in properties never leak through unexpectedly.

### Bundled theme files

| File | Description |
|---|---|
| `themes/light.tycss` | Light theme (white surfaces, blue accent) |
| `themes/dark.tycss` | Dark theme |
| `themes/builtin/showcase.tycss` | Showcase theme |

### Loading a theme

```pascal
// Global switch: affects every control on TyDefaultController
TyDefaultController.LoadTheme('themes/dark.tycss');

// Load from an in-memory CSS string (handy for embedded resources)
TyDefaultController.LoadThemeCss('TyButton { background: #222; color: #FFF; }');
```

### Runtime hot-swap

After `LoadTheme` or `LoadThemeCss`, the controller calls `Changed` and every registered control invalidates and repaints with the new theme. No manual refresh needed.

### A per-form local controller

If one form needs a theme independent of the global one, drop a `TTyStyleController` on that form and point its controls' `Controller` property at it:

```pascal
// in code
LocalCtrl := TTyStyleController.Create(Self);
LocalCtrl.LoadTheme('themes/builtin/showcase.tycss');

MyButton.Controller := LocalCtrl;
MyEdit.Controller   := LocalCtrl;
```

The same works in the IDE: drop a `TTyStyleController` and wire it up in the Object Inspector.

### Theme file format

`.tycss` is a CSS-lite DSL. Variables live in a `:root` block; rules are written as `Type[.variant][:state]`:

```css
:root {
  --accent:     #3B82F6;
  --surface:    #FFFFFF;
  --on-surface: #1F2937;
  --border:     #D1D5DB;
  --radius:     6px;
}

TyButton {
  background:    var(--surface);
  color:         var(--on-surface);
  border-color:  var(--border);
  border-radius: var(--radius);
}
TyButton.primary          { background: var(--accent); color: #FFFFFF; }
TyButton.primary:hover    { background: lighten(--accent, 8%); }
TyButton:disabled         { opacity: 0.5; }
```

Full syntax: [tycss-reference.en.md](tycss-reference.en.md).

---

## 5. Examples

All examples live under `examples/` and build UI in pure code (no `.lfm`).

| Directory | Shows | Build command |
|---|---|---|
| `button/` | `TTyButton` default / primary / danger variants, disabled state | `lazbuild examples/button/button_example.lpi` |
| `label/` | `TTyLabel` text colors and variants | `lazbuild examples/label/label_example.lpi` |
| `edit/` | `TTyEdit` input, selection, clipboard, word navigation, focus | `lazbuild examples/edit/edit_example.lpi` |
| `checkbox/` | `TTyCheckBox` checking and disabling | `lazbuild examples/checkbox/checkbox_example.lpi` |
| `radiobutton/` | `TTyRadioButton` groups | `lazbuild examples/radiobutton/radiobutton_example.lpi` |
| `panel/` | `TTyPanel` containers and captions, nesting | `lazbuild examples/panel/panel_example.lpi` |
| `combobox/` | `TTyComboBox` items / selection / OnChange, real popup | `lazbuild examples/combobox/combobox_example.lpi` |
| `scrollbar/` | `TTyScrollBar` vertical / horizontal, Position / OnChange | `lazbuild examples/scrollbar/scrollbar_example.lpi` |
| `listbox/` | `TTyListBox` items, keyboard navigation, embedded scrollbar | `lazbuild examples/listbox/listbox_example.lpi` |
| `progressbar/` | `TTyProgressBar` progress updates | `lazbuild examples/progressbar/progressbar_example.lpi` |
| `toggleswitch/` | `TTyToggleSwitch` toggling, ON/OFF theming | `lazbuild examples/toggleswitch/toggleswitch_example.lpi` |
| `trackbar/` | `TTyTrackBar` dragging, arrow-key stepping | `lazbuild examples/trackbar/trackbar_example.lpi` |
| `groupbox/` | `TTyGroupBox` grouping, radio-button groups | `lazbuild examples/groupbox/groupbox_example.lpi` |
| `tabcontrol/` | `TTyPageControl` + `TTyTabSheet`: ActivePage, arrow keys, overflow scrolling, drag reorder | `lazbuild examples/tabcontrol/tabcontrol_example.lpi` |
| `spinedit/` | `TTySpinEdit` spinning, arrows / wheel, Min / Max / Increment | `lazbuild examples/spinedit/spinedit_example.lpi` |
| `memo/` | `TTyMemo` multi-line editing, navigation, scrolling | `lazbuild examples/memo/memo_example.lpi` |
| `formchrome/` | `TTyForm` borderless custom window chrome | `lazbuild examples/formchrome/formchrome_example.lpi` |
| `theming/` | a custom `.tycss` theme + runtime hot-swap | `lazbuild examples/theming/theming_example.lpi` |
| `demo/` | everything: all controls, three themes, custom chrome | `lazbuild examples/demo/demo.lpi` |

Building the examples requires `tycontrols.lpk` installed (option A), or `--add-package tycontrols` on the `lazbuild` command line.

---

## 6. HiDPI

Every length token (radius, border width, padding, …) scales with the form's PPI at paint time. BGRABitmap renders vector paths, so high-DPI screens are crisp with no extra work in the application.

---

## 7. Known limitations

The ones most worth knowing up front (for bidirectional text and right-to-left layout, see [rtl.md](rtl.md)):

1. **`TTyMemo` right-to-left is half done.** Editing is complete — selection, clipboard, `WordWrap`, horizontal scrolling, undo/redo, word navigation and word deletion, `ReadOnly` / `MaxLength`. Bidirectional text *layout* is correct (UAX #9; Arabic and Hebrew word order and shaping work), and the caret and hit-testing are visual-order. What is missing is the mirroring half: the control's own scrollbar, padding, and alignment do not flip, so `BidiMode` is deliberately not published — this library does not publish a property it only half honors. Two consequences to know: a selection across writing directions draws as multiple bands, and `Home` / `End` are logical endpoints. Details: [controls/memo.md](controls/memo.md) and [rtl.md](rtl.md).

2. **Window-chrome gaps.** Custom chrome comes from inheriting `TTyForm = class(TForm)`. Windows Aero Snap, DWM native shadows, and macOS native shadows work; macOS native traffic-light buttons are not implemented yet. Details: [controls/ttyform.md](controls/ttyform.md).

3. **Cross-monitor DPI: round trips restore, but not pixel-for-pixel.** A 96 → 240 → 96 DPI round trip returns controls to their original sizes. Two tolerances remain by design: a control sitting exactly at its minimum size can grow a few pixels (4–10 px) on the first trip and then converges; right after a trip a control can sit about 1 px under its minimum until the next `SetBounds` corrects it. One trap *below* this library: LCL's `DoScaleFontPPI` irreversibly replaces an unset `Font.Height` using `Screen.PixelsPerInch` — on machines whose primary display is not 96 DPI, the first cross-monitor move rescales all fonts before any TyControls code runs. Avoid it by setting an explicit font size on the form. Cross-monitor awareness also requires a PerMonitorV2 manifest (`<DpiAware Value="True/PM_V2"/>` in the `.lpi`, plus `{$R *.res}`); the `demo` and `containers` examples declare it.

4. **Design-time rendering.** Controls render with the built-in default skin in the Lazarus designer. `TTyForm` layout is WYSIWYG (title bar on top, content below); the one gap is that the title bar shows the built-in skin rather than your loaded `.tycss` theme — the designer has no runtime theme context. This matches every other control and is not a defect.
