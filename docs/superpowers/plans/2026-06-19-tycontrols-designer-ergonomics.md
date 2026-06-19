# TyControls Designer Ergonomics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the four under-sized controls sensible drop defaults, and give all 20 registered components a real component-palette icon.

**Architecture:** (1) Set `Width`/`Height` in four control constructors. (2) An FPC+BGRABitmap console generator draws 20 line-glyph icons to 24×24 PNGs; `lazres` packs them into `designtime/tycontrols_icons.lrs` (resource name = class name); `{$I}` includes it in `tyControls.Design.pas` before `RegisterComponents` so the IDE shows them by class name. An fpcunit test guards that the `.lrs` carries all 20 PNG resources.

**Tech Stack:** Free Pascal / Lazarus (LCL), BGRABitmap, `lazres.exe`, fpcunit. Build: `lazbuild`. Accent `#3B82F6`, ink `#3C3C3C`, icons 24×24 RGBA.

---

### Task 1: Default control sizes

**Files:**
- Modify: `source/tyControls.Button.pas` (constructor at line 122)
- Modify: `source/tyControls.Edit.pas` (constructor at line 173)
- Modify: `source/tyControls.CheckBox.pas` (both constructors: line 68 and line 178)
- Test: `tests/test.button.pas`, `tests/test.edit.pas`, `tests/test.checkbox.pas`, `tests/test.radiobutton.pas`

- [ ] **Step 1: Add failing default-size tests**

In `tests/test.button.pas`, add to the published section of `TButtonTest` (after `TestTypeKey;`):
```pascal
    procedure TestDefaultSize;
```
and add the body in the implementation section (after the `TestTypeKey` body):
```pascal
procedure TButtonTest.TestDefaultSize;
var B: TTyButton;
begin
  B := TTyButton.Create(nil);
  try
    AssertEquals('default width', 88, B.Width);
    AssertEquals('default height', 30, B.Height);
  finally
    B.Free;
  end;
end;
```

In `tests/test.edit.pas`, add to the published section of `TEditTest`:
```pascal
    procedure TestDefaultSize;
```
and the body:
```pascal
procedure TEditTest.TestDefaultSize;
var E: TTyEdit;
begin
  E := TTyEdit.Create(nil);
  try
    AssertEquals('default width', 140, E.Width);
    AssertEquals('default height', 28, E.Height);
  finally
    E.Free;
  end;
end;
```

In `tests/test.checkbox.pas`, add to the published section of `TCheckBoxTest`:
```pascal
    procedure TestDefaultSize;
```
and the body:
```pascal
procedure TCheckBoxTest.TestDefaultSize;
var C: TTyCheckBox;
begin
  C := TTyCheckBox.Create(nil);
  try
    AssertEquals('default width', 130, C.Width);
    AssertEquals('default height', 22, C.Height);
  finally
    C.Free;
  end;
end;
```

In `tests/test.radiobutton.pas`, add to the published section of `TRadioButtonTest`:
```pascal
    procedure TestDefaultSize;
```
and the body:
```pascal
procedure TRadioButtonTest.TestDefaultSize;
var R: TTyRadioButton;
begin
  R := TTyRadioButton.Create(nil);
  try
    AssertEquals('default width', 130, R.Width);
    AssertEquals('default height', 22, R.Height);
  finally
    R.Free;
  end;
end;
```

- [ ] **Step 2: Build + run, verify the four fail**

Run: `lazbuild tests/tytests.lpi && ./tests/tytests.exe --suite=TButtonTest --suite=TEditTest --suite=TCheckBoxTest --suite=TRadioButtonTest --format=plain`
Expected: 4 failures (the controls currently have no/other default size).

- [ ] **Step 3: Set the defaults**

`source/tyControls.Button.pas` — in the constructor, after `FBgAnim.Easing := teEaseOutCubic;` and before the closing `end;`:
```pascal
  Width := 88;
  Height := 30;
```

`source/tyControls.Edit.pas` — in the constructor, immediately after `TabStop := True;`:
```pascal
  Width := 140;
  Height := 28;
```

`source/tyControls.CheckBox.pas` — in `TTyCheckBox.Create`, after `TabStop := True;`:
```pascal
  Width := 130;
  Height := 22;
```
and in `TTyRadioButton.Create`, after `TabStop := True;`:
```pascal
  Width := 130;
  Height := 22;
```

- [ ] **Step 4: Build + run, verify green**

Run: `lazbuild tests/tytests.lpi && ./tests/tytests.exe --suite=TButtonTest --suite=TEditTest --suite=TCheckBoxTest --suite=TRadioButtonTest --format=plain`
Expected: 0 failures.

- [ ] **Step 5: Commit**
```bash
git add source/tyControls.Button.pas source/tyControls.Edit.pas source/tyControls.CheckBox.pas tests/test.button.pas tests/test.edit.pas tests/test.checkbox.pas tests/test.radiobutton.pas
git commit -m "feat(tycontrols): sensible drop default sizes for Button/Edit/CheckBox/RadioButton"
```

---

### Task 2: Icon glyph generator

**Files:**
- Create: `tools/genicons/genicons.lpr`
- Create: `tools/genicons/genicons.lpi`

The generator draws each of the 20 glyphs (geometry from the spec appendix) at 24×24 transparent RGBA and writes `<OutDir>/<ClassName>.png`. Ink `#3C3C3C`, accent `#3B82F6`. It self-checks each bitmap is 24×24 and prints the count.

- [ ] **Step 1: Create `tools/genicons/genicons.lpr`**

```pascal
program genicons;
{$mode objfpc}{$H+}
uses
  Interfaces, SysUtils, BGRABitmap, BGRABitmapTypes;

const
  ST = 1.7;

var
  Ink, Acc, Faint: TBGRAPixel;

procedure Line(b: TBGRABitmap; x1, y1, x2, y2: single; c: TBGRAPixel; w: single = ST);
begin
  b.DrawLineAntialias(x1, y1, x2, y2, c, w);
end;

procedure RRect(b: TBGRABitmap; l, t, r, bot, rad: single; c: TBGRAPixel; w: single = ST);
begin
  b.RoundRectAntialias(l, t, r, bot, rad, rad, c, w);
end;

procedure FillRRect(b: TBGRABitmap; l, t, r, bot, rad: single; c: TBGRAPixel);
begin
  b.FillRoundRectAntialias(l, t, r, bot, rad, rad, c);
end;

procedure Circ(b: TBGRABitmap; cx, cy, rad: single; c: TBGRAPixel; w: single = ST);
begin
  b.EllipseAntialias(cx, cy, rad, rad, c, w);
end;

procedure FillCirc(b: TBGRABitmap; cx, cy, rad: single; c: TBGRAPixel);
begin
  b.FillEllipseAntialias(cx, cy, rad, rad, c);
end;

procedure PolyL(b: TBGRABitmap; const pts: array of TPointF; c: TBGRAPixel; w: single = ST);
begin
  b.DrawPolyLineAntialias(pts, c, w);
end;

procedure FillPolyG(b: TBGRABitmap; const pts: array of TPointF; c: TBGRAPixel);
begin
  b.FillPolyAntialias(pts, c);
end;

procedure GButton(b: TBGRABitmap); begin RRect(b,3,7,21,17,3,Ink); Line(b,8,12,16,12,Acc,2.4); end;
procedure GLabel(b: TBGRABitmap); begin PolyL(b,[PointF(6,18),PointF(12,6),PointF(18,18)],Ink); Line(b,8.6,13.2,15.4,13.2,Ink); end;
procedure GEdit(b: TBGRABitmap); begin RRect(b,3,7,21,17,2,Ink); Line(b,7,9.5,7,14.5,Acc,2); Line(b,10,12,16,12,Faint,1.3); end;
procedure GCheckBox(b: TBGRABitmap); begin RRect(b,4,4,20,20,3,Ink); PolyL(b,[PointF(8,12.4),PointF(11,15.4),PointF(16,8.6)],Acc,2.2); end;
procedure GRadio(b: TBGRABitmap); begin Circ(b,12,12,8,Ink); FillCirc(b,12,12,3.1,Acc); end;
procedure GCombo(b: TBGRABitmap); begin RRect(b,3,7,21,17,2,Ink); PolyL(b,[PointF(13.5,10.8),PointF(16,13.4),PointF(18.5,10.8)],Ink); end;
procedure GToggle(b: TBGRABitmap); begin RRect(b,3,8,21,16,4,Ink); FillCirc(b,16.5,12,2.7,Acc); end;
procedure GTrack(b: TBGRABitmap); begin Line(b,3,12,21,12,Ink); Line(b,6,10.4,6,13.6,Ink); Line(b,18,10.4,18,13.6,Ink); FillCirc(b,12,12,3,Acc); end;
procedure GProgress(b: TBGRABitmap); begin RRect(b,3,9,21,15,3,Ink); FillRRect(b,3,9,13,15,3,Acc); end;
procedure GListBox(b: TBGRABitmap); begin RRect(b,3,4,21,20,2,Ink); Line(b,6,9,18,9,Acc,2); Line(b,6,13,18,13,Ink); Line(b,6,17,15,17,Ink); end;
procedure GTabControl(b: TBGRABitmap); begin FillRRect(b,3.5,5,11.5,10.5,1.5,Acc); RRect(b,12.5,6.2,20,10.5,1.5,Ink); RRect(b,3,10,21,20,2,Ink); end;
procedure GGroupBox(b: TBGRABitmap); begin RRect(b,4,7,20,20,2,Ink); Line(b,6.5,7,11.5,7,Acc,2.6); end;
procedure GPanel(b: TBGRABitmap); begin RRect(b,3,5,21,19,2,Ink); end;
procedure GScrollBar(b: TBGRABitmap); begin RRect(b,9,3,15,21,3,Ink); PolyL(b,[PointF(10.5,7),PointF(12,5.5),PointF(13.5,7)],Ink); PolyL(b,[PointF(10.5,17),PointF(12,18.5),PointF(13.5,17)],Ink); FillRRect(b,9.5,10,14.5,15,1.5,Acc); end;
procedure GSpinEdit(b: TBGRABitmap); begin RRect(b,3,7,15,17,2,Ink); Line(b,6,9.5,6,14.5,Acc,2); Line(b,15,7,15,17,Ink); PolyL(b,[PointF(16.5,11),PointF(18,9.5),PointF(19.5,11)],Ink); PolyL(b,[PointF(16.5,13),PointF(18,14.5),PointF(19.5,13)],Ink); end;
procedure GMemo(b: TBGRABitmap); begin RRect(b,3,3,21,21,2,Ink); Line(b,6,8,17,8,Ink); Line(b,6,12,17,12,Ink); Line(b,6,16,13,16,Ink); end;
procedure GTitleBar(b: TBGRABitmap); begin RRect(b,3,4,21,20,2,Ink); Line(b,3,9,21,9,Ink); FillCirc(b,15,6.5,0.9,Ink); FillCirc(b,17,6.5,0.9,Ink); FillCirc(b,19,6.5,0.9,Acc); end;
procedure GMenuBar(b: TBGRABitmap); begin RRect(b,3,6,21,12,2,Ink); Line(b,6,9,8,9,Acc); Line(b,10,9,12,9,Ink); Line(b,14,9,16,9,Ink); end;
procedure GStyleController(b: TBGRABitmap); begin RRect(b,4,4,20,20,3,Ink); FillPolyG(b,[PointF(5,19),PointF(19,19),PointF(5,5)],Acc); end;
procedure GPopupMenu(b: TBGRABitmap); begin RRect(b,4,3,19,21,2,Ink); Line(b,7,7,16,7,Ink); Line(b,7,11,16,11,Acc); Line(b,7,15,16,15,Ink); end;

type
  TGlyphProc = procedure(b: TBGRABitmap);
  TGlyph = record Name: string; Draw: TGlyphProc; end;

const
  Glyphs: array[0..19] of TGlyph = (
    (Name:'TTyButton';          Draw:@GButton),
    (Name:'TTyLabel';           Draw:@GLabel),
    (Name:'TTyEdit';            Draw:@GEdit),
    (Name:'TTyCheckBox';        Draw:@GCheckBox),
    (Name:'TTyRadioButton';     Draw:@GRadio),
    (Name:'TTyComboBox';        Draw:@GCombo),
    (Name:'TTyToggleSwitch';    Draw:@GToggle),
    (Name:'TTyTrackBar';        Draw:@GTrack),
    (Name:'TTyProgressBar';     Draw:@GProgress),
    (Name:'TTyListBox';         Draw:@GListBox),
    (Name:'TTyTabControl';      Draw:@GTabControl),
    (Name:'TTyGroupBox';        Draw:@GGroupBox),
    (Name:'TTyPanel';           Draw:@GPanel),
    (Name:'TTyScrollBar';       Draw:@GScrollBar),
    (Name:'TTySpinEdit';        Draw:@GSpinEdit),
    (Name:'TTyMemo';            Draw:@GMemo),
    (Name:'TTyTitleBar';        Draw:@GTitleBar),
    (Name:'TTyMenuBar';         Draw:@GMenuBar),
    (Name:'TTyStyleController';  Draw:@GStyleController),
    (Name:'TTyPopupMenu';       Draw:@GPopupMenu)
  );

var
  OutDir: string;
  i: Integer;
  bmp: TBGRABitmap;
begin
  Ink   := BGRA($3C, $3C, $3C, 255);
  Acc   := BGRA($3B, $82, $F6, 255);
  Faint := BGRA($3C, $3C, $3C, 140);

  if ParamCount >= 1 then OutDir := ParamStr(1) else OutDir := GetCurrentDir;
  OutDir := IncludeTrailingPathDelimiter(OutDir);
  ForceDirectories(OutDir);

  for i := 0 to High(Glyphs) do
  begin
    bmp := TBGRABitmap.Create(24, 24);   // fully transparent
    try
      Glyphs[i].Draw(bmp);
      if (bmp.Width <> 24) or (bmp.Height <> 24) then
      begin
        writeln('ERROR: ', Glyphs[i].Name, ' is not 24x24');
        Halt(2);
      end;
      bmp.SaveToFile(OutDir + Glyphs[i].Name + '.png');
    finally
      bmp.Free;
    end;
  end;
  writeln('Wrote ', Length(Glyphs), ' icons to ', OutDir);
end.
```

- [ ] **Step 2: Create `tools/genicons/genicons.lpi`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CONFIG>
  <ProjectOptions>
    <Version Value="12"/>
    <General>
      <Flags>
        <MainUnitHasCreateFormStatements Value="False"/>
        <MainUnitHasTitleStatement Value="False"/>
      </Flags>
      <SessionStorage Value="InProjectDir"/>
      <Title Value="genicons"/>
    </General>
    <BuildModes>
      <Item Name="Default" Default="True"/>
    </BuildModes>
    <RequiredPackages>
      <Item>
        <PackageName Value="BGRABitmapPack"/>
      </Item>
      <Item>
        <PackageName Value="LCL"/>
      </Item>
    </RequiredPackages>
    <Units>
      <Unit>
        <Filename Value="genicons.lpr"/>
        <IsPartOfProject Value="True"/>
      </Unit>
    </Units>
  </ProjectOptions>
  <CompilerOptions>
    <Version Value="11"/>
    <Target>
      <Filename Value="genicons"/>
    </Target>
    <SearchPaths>
      <UnitOutputDirectory Value="lib/$(TargetCPU)-$(TargetOS)"/>
    </SearchPaths>
  </CompilerOptions>
</CONFIG>
```

- [ ] **Step 3: Build the generator**

Run: `lazbuild tools/genicons/genicons.lpi`
Expected: builds, produces `tools/genicons/genicons.exe`. If BGRABitmap API names differ (e.g. `DrawPolyLineAntialias`), fix the helper bodies to the available BGRABitmap signatures and rebuild — the geometry stays the same.

- [ ] **Step 4: Smoke-run to a temp dir**

Run: `./tools/genicons/genicons.exe tools/genicons/_smoke && ls tools/genicons/_smoke | wc -l`
Expected: `Wrote 20 icons...` and 20 files. Then clean: `rm -rf tools/genicons/_smoke`.

- [ ] **Step 5: Commit the generator**
```bash
git add tools/genicons/genicons.lpr tools/genicons/genicons.lpi
git commit -m "feat(tools): genicons — BGRA generator for the 20 palette icons"
```

---

### Task 3: Generation script + the .lrs artifact

**Files:**
- Create: `scripts/gen-icons.ps1`
- Create: `designtime/icons/*.png` (20 generated, committed for review)
- Create: `designtime/tycontrols_icons.lrs` (generated, used by the build)
- Modify: `.gitignore` (ignore the generator's build output)

- [ ] **Step 1: Create `scripts/gen-icons.ps1`**

```powershell
$ErrorActionPreference = 'Stop'
$root   = Split-Path $PSScriptRoot -Parent
$genLpi = Join-Path $root 'tools/genicons/genicons.lpi'
$genExe = Join-Path $root 'tools/genicons/genicons.exe'
$icons  = Join-Path $root 'designtime/icons'
$lrs    = Join-Path $root 'designtime/tycontrols_icons.lrs'
$lazres = 'C:\lazarus\tools\lazres.exe'

$classes = @(
  'TTyButton','TTyLabel','TTyEdit','TTyCheckBox','TTyRadioButton',
  'TTyComboBox','TTyToggleSwitch','TTyTrackBar','TTyProgressBar','TTyListBox',
  'TTyTabControl','TTyGroupBox','TTyPanel','TTyScrollBar','TTySpinEdit',
  'TTyMemo','TTyTitleBar','TTyMenuBar','TTyStyleController','TTyPopupMenu'
)

Write-Host '== building genicons =='
& lazbuild $genLpi
if ($LASTEXITCODE -ne 0) { throw 'genicons build failed' }

Write-Host '== rendering PNGs =='
New-Item -ItemType Directory -Force $icons | Out-Null
& $genExe $icons
if ($LASTEXITCODE -ne 0) { throw 'genicons run failed' }

Write-Host '== packing .lrs =='
$lazArgs = @($lrs)
foreach ($c in $classes) {
  $png = Join-Path $icons "$c.png"
  if (-not (Test-Path $png)) { throw "missing PNG: $png" }
  $lazArgs += ('{0}={1}' -f $png, $c)
}
& $lazres @lazArgs
if ($LASTEXITCODE -ne 0) { throw 'lazres failed' }
Write-Host "Packed $($classes.Count) icons into $lrs"
```

- [ ] **Step 2: Run it**

Run: `pwsh -File scripts/gen-icons.ps1` (or `powershell -File scripts/gen-icons.ps1`)
Expected: 20 PNGs in `designtime/icons/`, and `designtime/tycontrols_icons.lrs` created.

- [ ] **Step 3: Verify the .lrs content**

Run: `grep -c "LazarusResources.Add" designtime/tycontrols_icons.lrs` → expect `20`.
Run: `grep -oE "LazarusResources.Add\('[^']+','[^']+'" designtime/tycontrols_icons.lrs | head -3` → expect entries like `LazarusResources.Add('TTyButton','PNG'`.

- [ ] **Step 4: Ignore the generator build output**

Append to `.gitignore`:
```
tools/genicons/genicons.exe
tools/genicons/lib/
tools/genicons/_smoke/
```

- [ ] **Step 5: Commit**
```bash
git add scripts/gen-icons.ps1 designtime/icons/ designtime/tycontrols_icons.lrs .gitignore
git commit -m "feat(designtime): generate + pack the 20 palette icons (tycontrols_icons.lrs)"
```

---

### Task 4: fpcunit guard for the icon resources

**Files:**
- Create: `tests/test.paletteicons.pas`
- Modify: `tests/tytests.lpr` (add the unit to the uses list)

- [ ] **Step 1: Create `tests/test.paletteicons.pas`**

```pascal
unit test.paletteicons;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, LResources;

type
  TPaletteIconTest = class(TTestCase)
  published
    procedure TestAllTwentyResourcesPresentAndPng;
  end;

implementation

const
  CClasses: array[0..19] of string = (
    'TTyButton','TTyLabel','TTyEdit','TTyCheckBox','TTyRadioButton',
    'TTyComboBox','TTyToggleSwitch','TTyTrackBar','TTyProgressBar','TTyListBox',
    'TTyTabControl','TTyGroupBox','TTyPanel','TTyScrollBar','TTySpinEdit',
    'TTyMemo','TTyTitleBar','TTyMenuBar','TTyStyleController','TTyPopupMenu');

procedure TPaletteIconTest.TestAllTwentyResourcesPresentAndPng;
var
  i: Integer;
  res: TLResource;
begin
  for i := 0 to High(CClasses) do
  begin
    res := LazarusResources.Find(CClasses[i]);
    AssertNotNull('palette icon resource missing: ' + CClasses[i], res);
    AssertEquals('palette icon resource not PNG: ' + CClasses[i], 'PNG', res.ValueType);
  end;
end;

initialization
  {$I ../designtime/tycontrols_icons.lrs}
  RegisterTest(TPaletteIconTest);
end.
```

- [ ] **Step 2: Register the unit**

In `tests/tytests.lpr`, add `test.paletteicons,` to the `uses` clause (e.g. next to `test.menu,`).

- [ ] **Step 3: Build + run the new suite, verify green**

Run: `lazbuild tests/tytests.lpi && ./tests/tytests.exe --suite=TPaletteIconTest --format=plain`
Expected: 0 failures (the `.lrs` from Task 3 is included and carries all 20 PNG resources).

> If the build errors on the `{$I}` path, confirm the relative path from `tests/` to the `.lrs` is `../designtime/tycontrols_icons.lrs`.

- [ ] **Step 4: Commit**
```bash
git add tests/test.paletteicons.pas tests/tytests.lpr
git commit -m "test(tycontrols): guard that the palette .lrs carries all 20 PNG icon resources"
```

---

### Task 5: Wire the icons into the design-time package

**Files:**
- Modify: `designtime/tyControls.Design.pas` (uses clause line 4-12; `Register` at line 128)

- [ ] **Step 1: Add `LResources` to the uses clause**

In `designtime/tyControls.Design.pas`, change the first uses line:
```pascal
uses
  Classes, SysUtils, PropEdits, ComponentEditors, ProjectIntf, FormEditingIntf,
  LResources,
```

- [ ] **Step 2: Include the .lrs at the top of `Register`**

In `procedure Register;`, insert as the very first statement (before the `if FormEditingHook ...` block):
```pascal
  {$I tycontrols_icons.lrs}
```
(The `.lrs` is in the same directory as `tyControls.Design.pas`, so the bare filename resolves.)

- [ ] **Step 3: Build the design-time package**

Run: `lazbuild tycontrols_dt.lpk`
Expected: builds with no errors (hints/notes ok).

- [ ] **Step 4: Build runtime package + full test suite (no regressions)**

Run: `lazbuild tyControls.lpk && lazbuild tests/tytests.lpi && ./tests/tytests.exe -a --format=plain`
Expected: same pass count as before plus the new tests; 0 new failures (pre-existing ~11 sandbox errors unchanged).

- [ ] **Step 5: Commit**
```bash
git add designtime/tyControls.Design.pas
git commit -m "feat(designtime): show palette icons by including tycontrols_icons.lrs before RegisterComponents"
```

---

### Task 6: Docs — regeneration note

**Files:**
- Create: `tools/genicons/README.md`

- [ ] **Step 1: Document the regeneration workflow**

Create `tools/genicons/README.md`:
```markdown
# Palette icon generator

Draws the 20 TyControls component-palette icons (24x24 RGBA, line-glyph + #3B82F6 accent)
and packs them into `designtime/tycontrols_icons.lrs`, which `tyControls.Design.pas`
includes via `{$I}` before `RegisterComponents`. The IDE shows each by class name.

## Regenerate

    pwsh -File scripts/gen-icons.ps1

This rebuilds `genicons`, renders `designtime/icons/<ClassName>.png`, and repacks the
`.lrs` (via `C:\lazarus\tools\lazres.exe`). Commit the changed `designtime/icons/*.png`
and `designtime/tycontrols_icons.lrs`.

## Edit a glyph

Edit its `G<Name>` routine in `genicons.lpr` (geometry is plain BGRA primitives in a
24-unit space), then regenerate. After changing icons, rebuild `tycontrols_dt.lpk` and
restart Lazarus to see them in the palette.
```

- [ ] **Step 2: Commit**
```bash
git add tools/genicons/README.md
git commit -m "docs(tools): document palette-icon regeneration"
```

---

## Verification (manual, post-merge — cannot be headless-tested)

1. `lazbuild tycontrols_dt.lpk`, reinstall the design-time package, restart Lazarus.
2. Component palette → "TyControls" tab shows a distinct icon for each of the 20 components.
3. Drop `TyButton`/`TyEdit`/`TyCheckBox`/`TyRadioButton` — each appears at its new default size.

## Notes for the implementer

- BGRABitmap drawing method names are the load-bearing risk in Task 2. If `lazbuild` reports an unknown method, look up the closest BGRABitmap equivalent (the units `BGRABitmap`/`BGRABitmapTypes` expose `DrawLineAntialias`, `RoundRectAntialias`, `FillRoundRectAntialias`, `EllipseAntialias`, `FillEllipseAntialias`, `DrawPolyLineAntialias`, `FillPolyAntialias`) and adjust only the six helper bodies — the 20 `G*` glyph routines call only those helpers.
- `lazres` resource name = the PNG filename without path/extension, case preserved; we also pass an explicit `=ClassName` to be unambiguous.
- The test binary links the runtime package + test units only (not `tycontrols_dt`), so its `{$I ...lrs}` cannot clash with `Design.pas`'s include.
```
