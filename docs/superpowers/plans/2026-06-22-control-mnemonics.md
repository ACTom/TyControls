# Control Mnemonics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Caption-bearing TyControls (Button, CheckBox, RadioButton, GroupBox, Label, tab strip) strip the mnemonic `&` from their drawn caption, underline the mnemonic char only while Alt is held, and activate on `Alt+<letter>` — via one shared `tyControls.Accel` facility, with the menu bar refactored onto it.

**Architecture:** A new `tyControls.Accel` unit owns `TyParseMnemonic` (moved out of `tyControls.Menu`), a single app-wide Alt-state hook (`TyAccelShowing` + register/unregister for live underline repaint), a gate helper (`TyAccelGatePos`), and an `Alt+key` matcher (`TyIsAccelKey`). Each caption control makes the same 3 edits: draw the stripped display + gated underline, register/unregister, and override `DialogChar` to perform its action. Tab mnemonics live in the `TTyCustomTabStrip` base so `TTyPageControl` (and the future `TTyTabSet`) inherit them.

**Tech Stack:** Free Pascal / Lazarus (LCL), BGRABitmap text, fpcunit. LCL `DialogChar`/`IsAccel`/`KeyDataToShiftState`/`Application.AddOnUserInputHandler`/`GetKeyState`.

---

## File structure

| File | Action | Responsibility |
|---|---|---|
| `source/tyControls.Accel.pas` | **create** | `TyParseMnemonic`, `TyAccelShowing`, `TyAccelGatePos`, `TyAccelRegister/Unregister`, `TyIsAccelKey` |
| `source/tyControls.Menu.pas` | modify | use `tyControls.Accel`; drop the duplicate `TyParseMnemonic` + the bar's private Alt hook |
| `source/tyControls.Button.pas` | modify | strip+underline caption; register; `DialogChar` → `Click` |
| `source/tyControls.CheckBox.pas` | modify | strip+underline (CheckBox + RadioButton); register; `DialogChar` → `SetFocus; Click` |
| `source/tyControls.GroupBox.pas` | modify | strip+underline `FCaption`; register; `DialogChar` → focus first child |
| `source/tyControls.TyLabel.pas` | modify | strip caption (single-line underline); register; `DialogChar` → `Click` (focuses `FocusControl`) |
| `source/tyControls.TabStrip.pas` | modify | strip+underline tab captions; register; `DialogChar` → `SetTabIndex(match)` |
| `tycontrols.lpk` | modify | add `tyControls.Accel` |
| `tests/test.accel.pas` | **create** | `TyParseMnemonic`, `TyAccelGatePos`, `TyIsAccelKey`-where-constructible |
| `tests/tytests.lpr` | modify | register `test.accel` |
| `tests/test.menu.pas` | modify | add `tyControls.Accel` to uses (TyParseMnemonic moved) |

---

### Task 1: `tyControls.Accel` unit

**Files:** Create `source/tyControls.Accel.pas`, `tests/test.accel.pas`; modify `tests/tytests.lpr`, `tycontrols.lpk`.

- [ ] **Step 1: Write the failing test** — create `tests/test.accel.pas`:
```pascal
unit test.accel;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry, tyControls.Accel;
type
  TAccelTest = class(TTestCase)
  published
    procedure TestParseMnemonic;
    procedure TestGatePosOffByDefault;
  end;
implementation
procedure TAccelTest.TestParseMnemonic;
var d: string; p: Integer; m: Char;
begin
  m := TyParseMnemonic('&File', d, p);
  AssertEquals('display', 'File', d);
  AssertEquals('mnemonic', 'F', m);
  AssertEquals('pos', 1, p);
  m := TyParseMnemonic('a && b', d, p);
  AssertEquals('literal amp', 'a & b', d);
  AssertEquals('no mnemonic', #0, m);
end;
procedure TAccelTest.TestGatePosOffByDefault;
begin
  // No Alt held in a headless run -> gate returns 0 (underline suppressed).
  AssertEquals('gate off', 0, TyAccelGatePos(3));
end;
initialization
  RegisterTest(TAccelTest);
end.
```
Add `test.accel,` to `tests/tytests.lpr` uses (after `test.about,` or alongside the others).

- [ ] **Step 2: Run, verify it fails** (unit missing).
Run: `lazbuild tests/tytests.lpi` → Expected: FAIL (`tyControls.Accel` not found).

- [ ] **Step 3: Create `source/tyControls.Accel.pas`:**
```pascal
unit tyControls.Accel;
{$mode objfpc}{$H+}
interface
uses Classes, Controls, LMessages;

{ Parse a caption mnemonic. Single '&' marks the next char and is removed from the display;
  '&&' -> literal '&'; the first single '&' wins; the mnemonic char is returned upper-cased
  (#0 = none); AMnemonicPos is its 1-based index in ADisplay (0 = none). }
function TyParseMnemonic(const ACaption: string; out ADisplay: string; out AMnemonicPos: Integer): Char;

{ True while Alt is currently held (the "show access keys" cue). }
function TyAccelShowing: Boolean;

{ AMnemonicPos when TyAccelShowing, else 0 — pass to TTyPainter.DrawText to gate the underline. }
function TyAccelGatePos(AMnemonicPos: Integer): Integer;

{ Register/unregister a control to be Invalidate()d when the Alt-held state flips. The single
  Application input hook is installed on the first registration, removed when the registry empties. }
procedure TyAccelRegister(AControl: TControl);
procedure TyAccelUnregister(AControl: TControl);

{ True iff Message is Alt+<the caption's mnemonic> (Alt-only modifier gate + LCL IsAccel, which
  treats CharCode as the translated character — the correctness the menu's DialogChar fix established). }
function TyIsAccelKey(const Message: TLMKey; const ACaption: string): Boolean;

implementation
uses Forms, LCLType, LCLIntf, LCLProc;

type
  { A method-of-object host for Application.AddOnUserInputHandler (which needs an of-object event). }
  TTyAccelWatcher = class
    procedure Input(Sender: TObject; Msg: Cardinal);
  end;

var
  GShowing: Boolean = False;
  GRegistry: TFPList = nil;
  GWatcher: TTyAccelWatcher = nil;
  GHooked: Boolean = False;

function TyParseMnemonic(const ACaption: string; out ADisplay: string; out AMnemonicPos: Integer): Char;
var i, n: Integer;
begin
  Result := #0; AMnemonicPos := 0; ADisplay := '';
  n := Length(ACaption); i := 1;
  while i <= n do
  begin
    if ACaption[i] = '&' then
    begin
      if (i < n) and (ACaption[i + 1] = '&') then
        begin ADisplay := ADisplay + '&'; Inc(i, 2); Continue; end
      else if i < n then
      begin
        if Result = #0 then
          begin Result := UpCase(ACaption[i + 1]); AMnemonicPos := Length(ADisplay) + 1; end;
        Inc(i); Continue;
      end
      else Break;
    end;
    ADisplay := ADisplay + ACaption[i]; Inc(i);
  end;
end;

function TyAccelShowing: Boolean;
begin Result := GShowing; end;

function TyAccelGatePos(AMnemonicPos: Integer): Integer;
begin if GShowing then Result := AMnemonicPos else Result := 0; end;

procedure TTyAccelWatcher.Input(Sender: TObject; Msg: Cardinal);
var alt: Boolean; i: Integer;
begin
  // GetKeyState high bit (negative) = key down. Fires on Alt press/release + mouse input.
  alt := GetKeyState(VK_MENU) < 0;
  if alt = GShowing then Exit;
  GShowing := alt;
  if GRegistry <> nil then
    for i := 0 to GRegistry.Count - 1 do
      TControl(GRegistry[i]).Invalidate;
end;

procedure TyAccelRegister(AControl: TControl);
begin
  if AControl = nil then Exit;
  if GRegistry = nil then GRegistry := TFPList.Create;
  if GRegistry.IndexOf(AControl) < 0 then GRegistry.Add(AControl);
  if not GHooked then
  begin
    if GWatcher = nil then GWatcher := TTyAccelWatcher.Create;
    Application.AddOnUserInputHandler(@GWatcher.Input);
    GHooked := True;
  end;
end;

procedure TyAccelUnregister(AControl: TControl);
begin
  if GRegistry <> nil then GRegistry.Remove(AControl);
  if GHooked and ((GRegistry = nil) or (GRegistry.Count = 0)) then
  begin
    Application.RemoveOnUserInputHandler(@GWatcher.Input);
    GHooked := False;
  end;
end;

function TyIsAccelKey(const Message: TLMKey; const ACaption: string): Boolean;
begin
  Result := (KeyDataToShiftState(Message.KeyData) * [ssShift, ssCtrl, ssAlt] = [ssAlt])
            and IsAccel(Message.CharCode, ACaption);
end;

finalization
  if GHooked and (GWatcher <> nil) then Application.RemoveOnUserInputHandler(@GWatcher.Input);
  GWatcher.Free;
  GRegistry.Free;
end.
```
Add the unit to `tycontrols.lpk` (after the Painter `<Item>`, mirroring it):
```xml
      <Item>
        <Filename Value="source/tyControls.Accel.pas"/>
        <UnitName Value="tyControls.Accel"/>
      </Item>
```

- [ ] **Step 4: Run, verify green.**
Run: `lazbuild tyControls.lpk && lazbuild tests/tytests.lpi && ./tests/tytests.exe --suite=TAccelTest --format=plain` → Expected: 0 failures.

- [ ] **Step 5: Commit**
```bash
git add source/tyControls.Accel.pas tests/test.accel.pas tests/tytests.lpr tycontrols.lpk
git commit -m "feat(tycontrols): tyControls.Accel — shared mnemonic parse + Alt-state + DialogChar helper"
```

### Task 2: Move `TyParseMnemonic` out of `tyControls.Menu`

**Files:** Modify `source/tyControls.Menu.pas`, `tests/test.menu.pas`.

- [ ] **Step 1: Delete the duplicate from Menu.** In `source/tyControls.Menu.pas` remove the `TyParseMnemonic` interface declaration AND its implementation body (the `function TyParseMnemonic(...)` block added for the menu). Add `tyControls.Accel` to the Menu interface `uses` clause (it already uses `LCLIntf, LMessages`):
```pascal
uses Classes, SysUtils, Types, Controls, Graphics, Forms, ExtCtrls, LCLType, LCLProc, LCLIntf, LMessages, Menus,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller, tyControls.Accel;
```

- [ ] **Step 2: Point the menu test at Accel.** In `tests/test.menu.pas`, add `tyControls.Accel` to the `uses` clause (the `TestParseMnemonic` there now resolves `TyParseMnemonic` from Accel):
```pascal
uses Classes, SysUtils, Types, Controls, Forms, Menus, fpcunit, testregistry, tyControls.Menu, tyControls.Accel;
```

- [ ] **Step 3: Build + run menu + accel suites — no regressions.**
Run: `lazbuild tyControls.lpk && lazbuild tests/tytests.lpi && ./tests/tytests.exe --suite=TMenuModelTest --format=plain && ./tests/tytests.exe --suite=TAccelTest --format=plain`
Expected: 0 failures (TyParseMnemonic now resolves from Accel everywhere).

- [ ] **Step 4: Commit**
```bash
git add source/tyControls.Menu.pas tests/test.menu.pas
git commit -m "refactor(menu): source TyParseMnemonic from tyControls.Accel (single owner)"
```

### Task 3: Refactor the menu bar onto the shared Alt-state

**Files:** Modify `source/tyControls.Menu.pas`.

- [ ] **Step 1: Replace the bar's private hook with the shared facility.**
  - In `TTyMenuBar.Create`, replace `Application.AddOnUserInputHandler(@AccelInput);` + `FShowAccel := False;` with `TyAccelRegister(Self);`.
  - In `TTyMenuBar.Destroy`, replace `Application.RemoveOnUserInputHandler(@AccelInput);` with `TyAccelUnregister(Self);`.
  - Delete the `FShowAccel` field, the `AccelInput` method (declaration + body).
  - Change `AccelPos` body to use the shared gate:
```pascal
function TTyMenuBar.AccelPos(AIndex: Integer): Integer;
begin
  Result := TyAccelGatePos(TopMnemonicPos(AIndex));
end;
```
  - (`LCLIntf` may now be unused by Menu — leave it; harmless. The bar's `RenderTo` already calls `AccelPos(i)`.)

- [ ] **Step 2: Build + run the full suite — no regressions.**
Run: `lazbuild tyControls.lpk && lazbuild tests/tytests.lpi && ./tests/tytests.exe -a --format=plain`
Expected: all compile; 0 failures; 11 known headless errors unchanged.

- [ ] **Step 3: Commit**
```bash
git add source/tyControls.Menu.pas
git commit -m "refactor(menu): bar Alt-underline uses the shared tyControls.Accel facility"
```

### Task 4: `TTyButton` mnemonic

**Files:** Modify `source/tyControls.Button.pas`. (Class `TTyButton = class(TTyCustomControl)`; Paint draws `Caption` at line ~460; ctor ~122, dtor ~137.)

- [ ] **Step 1: Add uses + DialogChar declaration.** Add `LMessages, tyControls.Accel` to the implementation/interface `uses` (wherever the other `tyControls.*` are). In the `TTyButton` protected section (near `procedure Paint; override;`) add:
```pascal
    function DialogChar(var Message: TLMKey): Boolean; override;
```

- [ ] **Step 2: Register/unregister.** In `TTyButton.Create` (after `inherited Create`) add `TyAccelRegister(Self);`. In `TTyButton.Destroy` (before `inherited Destroy`) add `TyAccelUnregister(Self);`.

- [ ] **Step 3: Strip + underline the caption.** At the caption draw (`Button.pas:460`, `P.DrawText(ContentRect, Caption, ...)`), introduce locals and rewrite the call to draw the stripped display with the gated underline. Add `disp: string; mp: Integer;` to the Paint `var` block, then:
```pascal
    TyParseMnemonic(Caption, disp, mp);
    P.DrawText(ContentRect, disp, S.FontName, S.FontSize, S.FontWeight,
      S.TextColor, taCenter, tlCenter, True, TyAccelGatePos(mp));
```
(Keep the original alignment/ellipsis args from the existing call; only `Caption`→`disp` and the new trailing `TyAccelGatePos(mp)` change.)

- [ ] **Step 4: Implement DialogChar.**
```pascal
function TTyButton.DialogChar(var Message: TLMKey): Boolean;
begin
  if Enabled and TyIsAccelKey(Message, Caption) then
  begin
    Click;
    Exit(True);
  end;
  Result := inherited DialogChar(Message);
end;
```

- [ ] **Step 5: Build + full suite.**
Run: `lazbuild tyControls.lpk && lazbuild tests/tytests.lpi && ./tests/tytests.exe -a --format=plain`
Expected: 0 failures; 11 known errors unchanged. (The golden test renders no `&`-captioned button, so pixels are unchanged.)

- [ ] **Step 6: Commit**
```bash
git add source/tyControls.Button.pas
git commit -m "feat(button): mnemonic — strip & display + Alt underline + Alt+key Click"
```

### Task 5: `TTyCheckBox` + `TTyRadioButton` mnemonic

**Files:** Modify `source/tyControls.CheckBox.pas`. (Both `= class(TTyCustomControl)`; caption draws at lines ~165 and ~298; CheckBox ctor ~68, RadioButton ctor ~180.)

- [ ] **Step 1: uses + DialogChar decls.** Add `LMessages, tyControls.Accel` to `uses`. In BOTH `TTyCheckBox` and `TTyRadioButton` protected sections add:
```pascal
    function DialogChar(var Message: TLMKey): Boolean; override;
```

- [ ] **Step 2: Register/unregister.** In `TTyCheckBox.Create` and `TTyRadioButton.Create` add `TyAccelRegister(Self);`. Add a `destructor Destroy; override;` to each that does `TyAccelUnregister(Self); inherited Destroy;` (if none exists yet — add the declaration in the class too).

- [ ] **Step 3: Strip + underline.** At each caption draw (`CheckBox.pas:165` and `:298`, `P.DrawText(TextRect, Caption, ...)`), add `disp: string; mp: Integer;` to that Paint's `var`, and rewrite:
```pascal
    TyParseMnemonic(Caption, disp, mp);
    P.DrawText(TextRect, disp, S.FontName, ResolveFontSize(S), S.FontWeight,
      <existing colour/align/ellipsis args>, TyAccelGatePos(mp));
```
(Preserve the existing trailing args; only `Caption`→`disp` and the new `TyAccelGatePos(mp)`.)

- [ ] **Step 4: DialogChar (both).** Focus then toggle (LCL checkbox behavior):
```pascal
function TTyCheckBox.DialogChar(var Message: TLMKey): Boolean;
begin
  if Enabled and TyIsAccelKey(Message, Caption) then
  begin
    if CanFocus then SetFocus;
    Click;
    Exit(True);
  end;
  Result := inherited DialogChar(Message);
end;
```
Repeat identically for `TTyRadioButton.DialogChar` (same body, `TTyRadioButton.` prefix).

- [ ] **Step 5: Build + full suite.**
Run: `lazbuild tyControls.lpk && lazbuild tests/tytests.lpi && ./tests/tytests.exe -a --format=plain` → 0 failures.

- [ ] **Step 6: Commit**
```bash
git add source/tyControls.CheckBox.pas
git commit -m "feat(checkbox,radio): mnemonic — strip & display + Alt underline + Alt+key focus/toggle"
```

### Task 6: `TTyGroupBox` mnemonic

**Files:** Modify `source/tyControls.GroupBox.pas`. (`= class(TTyCustomControl)`; `FCaption`; draw at ~146; measure `TextWidth(FCaption)` at ~122; ctor ~49.)

- [ ] **Step 1: uses + DialogChar decl + destructor.** Add `LMessages, tyControls.Accel` to `uses`. Add to the protected section `function DialogChar(var Message: TLMKey): Boolean; override;`. Ensure a `destructor Destroy; override;` exists (add if absent).

- [ ] **Step 2: Register/unregister.** `TyAccelRegister(Self)` in `Create`; `TyAccelUnregister(Self)` in `Destroy` before `inherited`.

- [ ] **Step 3: Strip + underline + measure.** The caption width measure at line ~122 (`TextW := MeasBmp.Canvas.TextWidth(FCaption)`) must measure the STRIPPED text; the draw at ~146 draws it. Add `disp: string; mp: Integer;` to Paint's `var`, compute `TyParseMnemonic(FCaption, disp, mp);` once near the top of the caption block (the `if FCaption <> '' then` guard at ~111), use `disp` for `TextWidth(disp)` and in the draw:
```pascal
      P.DrawText(TextRect, disp, S.FontName, ResolveFontSize(S), S.FontWeight,
        <existing args>, TyAccelGatePos(mp));
```

- [ ] **Step 4: DialogChar → focus first child.** A group box isn't focusable itself; its mnemonic moves focus to the first focusable child:
```pascal
function TTyGroupBox.DialogChar(var Message: TLMKey): Boolean;
var pf: TCustomForm;
begin
  if Enabled and TyIsAccelKey(Message, FCaption) then
  begin
    pf := GetParentForm(Self);
    if pf <> nil then pf.SelectNext(Self, True, True);   // first tab-order control after the group box
    Exit(True);
  end;
  Result := inherited DialogChar(Message);
end;
```
Add `Forms` to `uses` if not present (for `TCustomForm`/`GetParentForm`).

- [ ] **Step 5: Build + full suite.**
Run: `lazbuild tyControls.lpk && lazbuild tests/tytests.lpi && ./tests/tytests.exe -a --format=plain` → 0 failures.

- [ ] **Step 6: Commit**
```bash
git add source/tyControls.GroupBox.pas
git commit -m "feat(groupbox): mnemonic — strip & caption + Alt underline + Alt+key focuses first child"
```

### Task 7: `TTyLabel` mnemonic

**Files:** Modify `source/tyControls.TyLabel.pas`. (`= class(TTyGraphicControl)`; `FocusControl: TWinControl`; `Click` focuses it; single-line draw at ~360, wrapped at ~351; ctor ~67.)

- [ ] **Step 1: uses + DialogChar decl + destructor.** Add `LMessages, tyControls.Accel` to `uses`. Add `function DialogChar(var Message: TLMKey): Boolean; override;` to the protected section. Ensure a `destructor Destroy; override;` exists (add if absent).

- [ ] **Step 2: Register/unregister.** `TyAccelRegister(Self)` in `Create`; `TyAccelUnregister(Self)` in `Destroy` before `inherited`.

- [ ] **Step 3: Strip the caption; underline single-line only.** Wherever `Caption` feeds wrapping/drawing (lines ~241/243/246/334/351/360), use a stripped copy. Simplest: at the top of `Paint`, compute `TyParseMnemonic(Caption, dispCap, mp);` (add `dispCap: string; mp: Integer;` to `var`) and use `dispCap` in place of `Caption` for measuring/wrapping/drawing. For the SINGLE-line draw (`:360`) pass the gated underline; for the WRAPPED path (`:351`) pass `0` (no underline across wrapped lines):
```pascal
   // single line (~360):
   P.DrawText(ContentRect, dispCap, S.FontName, fontSize, S.FontWeight,
     <existing args>, TyAccelGatePos(mp));
   // wrapped lines (~351): keep Lines[i], pass 0 (default) — no underline
```

- [ ] **Step 4: DialogChar → Click (focuses FocusControl).**
```pascal
function TTyLabel.DialogChar(var Message: TLMKey): Boolean;
begin
  if (FocusControl <> nil) and TyIsAccelKey(Message, Caption) then
  begin
    Click;            // TTyLabel.Click already focuses FocusControl (TyLabel.pas:142)
    Exit(True);
  end;
  Result := inherited DialogChar(Message);
end;
```

- [ ] **Step 5: Build + full suite.**
Run: `lazbuild tyControls.lpk && lazbuild tests/tytests.lpi && ./tests/tytests.exe -a --format=plain` → 0 failures.

- [ ] **Step 6: Commit**
```bash
git add source/tyControls.TyLabel.pas
git commit -m "feat(label): mnemonic — strip & caption + single-line Alt underline + Alt+key focuses FocusControl"
```

### Task 8: Tab mnemonics in `TTyCustomTabStrip` (covers PageControl + future TabSet)

**Files:** Modify `source/tyControls.TabStrip.pas`. (`= class(TTyCustomControl)`; `GetTabCaption(i)` abstract; `SetTabIndex`; tab captions drawn in `Paint`; ctor ~194, dtor ~219.)

- [ ] **Step 1: uses + DialogChar decl.** Add `LMessages, tyControls.Accel` to `uses`. Add to the protected section `function DialogChar(var Message: TLMKey): Boolean; override;`.

- [ ] **Step 2: Register/unregister.** `TyAccelRegister(Self)` in `TTyCustomTabStrip.Create`; `TyAccelUnregister(Self)` in `Destroy` before `inherited`.

- [ ] **Step 3: Strip + underline each tab caption.** Find the tab-caption draw in `Paint` (it calls `GetTabCaption(i)` and `P.DrawText(...)`). For each tab `i`, replace the raw caption with the stripped display + gated underline:
```pascal
    TyParseMnemonic(GetTabCaption(i), disp, mp);
    P.DrawText(<tab text rect>, disp, <font args>, <colour/align/ellipsis>, TyAccelGatePos(mp));
```
(Add `disp: string; mp: Integer;` to that method's `var`. Also strip in any tab-width measurement that uses `GetTabCaption(i)`.)

- [ ] **Step 4: DialogChar → select the matching tab.**
```pascal
function TTyCustomTabStrip.DialogChar(var Message: TLMKey): Boolean;
var i: Integer;
begin
  for i := 0 to GetTabCount - 1 do
    if TyIsAccelKey(Message, GetTabCaption(i)) then
    begin
      SetTabIndex(i);
      Exit(True);
    end;
  Result := inherited DialogChar(Message);
end;
```

- [ ] **Step 5: Build + full suite (incl. PageControl tests).**
Run: `lazbuild tyControls.lpk && lazbuild tests/tytests.lpi && ./tests/tytests.exe -a --format=plain` → 0 failures.

- [ ] **Step 6: Commit**
```bash
git add source/tyControls.TabStrip.pas
git commit -m "feat(tabstrip): tab mnemonics at the base — strip & + Alt underline + Alt+key selects tab (PageControl + future TabSet)"
```

---

## Manual verification (real machine — none of the live behavior is headless-testable)

1. Captions with `&` (e.g. `&OK`, `E&nable`, a `&General` tab) show clean text, no literal `&`.
2. Hold **Alt** → the access-key char underlines on buttons, checkboxes, radios, group boxes, labels, tabs, and the menu bar; release → underlines vanish.
3. `Alt+O` clicks the `&OK` button; `Alt+E` toggles `E&nable`; a label's mnemonic focuses its `FocusControl` edit; a group box mnemonic focuses its first field; a tab mnemonic switches tabs.
4. Plain typing into an edit/memo does NOT trigger any mnemonic (Alt-only gate).
5. Existing menu behavior still works (the bar refactor didn't regress it).

## Self-review notes
- Spec coverage: shared facility (T1) incl. `TyParseMnemonic` move (T2) + menu-bar consolidation (T3); display+underline+activation per control — Button (T4), CheckBox/Radio (T5), GroupBox (T6), Label (T7), tab strip → PageControl + future TabSet (T8). R1 (graphic-control DialogChar) is exercised by T6/T7; R3 (registry lifecycle) is the Accel unit's register/unregister + finalization.
- Type consistency: `TyParseMnemonic`, `TyAccelShowing`, `TyAccelGatePos`, `TyAccelRegister`/`TyAccelUnregister`, `TyIsAccelKey` are used identically across all tasks; every `DialogChar` override has the same signature `function DialogChar(var Message: TLMKey): Boolean; override;`.
- The only non-verbatim edits are the per-control caption `DrawText` calls (their full arg lists vary): each task names the exact file:line and the exact transformation (`Caption`/`GetTabCaption(i)`/`FCaption` → `TyParseMnemonic` display + trailing `TyAccelGatePos(mp)`), preserving the existing colour/alignment/ellipsis args.
