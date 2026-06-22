# Control Mnemonics (Accelerators) — Design

**Date:** 2026-06-22
**Status:** Draft — awaiting spec review → plan

## Goal

Caption-bearing TyControls support mnemonics, matching what the menu now does:
1. **Display** — a `&` in the caption is stripped from what's drawn (`&&` → literal `&`); fixes the
   current bug where `&OK` shows the `&` literally.
2. **Underline on Alt** — the mnemonic char is underlined **only while Alt is held**.
3. **Alt+`<letter>` activation** — `Alt+O` on an `&OK` button clicks it; on a checkbox toggles it;
   on a label focuses its `FocusControl`; on a group box focuses its first child.

In scope: `TTyButton`, `TTyCheckBox`, `TTyRadioButton`, `TTyGroupBox`, `TTyLabel`, and `TTyPageControl`
tab captions. (Edit/Memo/ScrollBar/ListBox/ProgressBar/TrackBar/ToggleSwitch have no activatable caption
— a ToggleSwitch caption, if any, can be added later.)

## Current state (verified)

- `TTyButton.Paint` ([Button.pas:460](source/tyControls.Button.pas:460)), `TTyCheckBox`
  ([CheckBox.pas:165](source/tyControls.CheckBox.pas:165)), `TTyGroupBox`
  ([GroupBox.pas:146](source/tyControls.GroupBox.pas:146)) all draw the **raw** caption → literal `&`.
- No control overrides `DialogChar` → no `Alt+key` activation.
- The menu already has the pieces this generalizes: `TyParseMnemonic`, `TTyPainter.DrawText`'s
  `AMnemonicPos`, and a per-control Alt-state hook (`TTyMenuBar.FShowAccel`/`AccelInput`).
- `DialogChar(var Message: TLMKey): Boolean` is a `TControl` virtual broadcast by the parent form to ALL
  children (windowed and graphic), so both `TTyCustomControl` and `TTyGraphicControl` controls can override it.
- `TTyLabel` has `FocusControl: TWinControl` and its `Click` already focuses it ([TyLabel.pas:142](source/tyControls.TyLabel.pas:142)).

## Architecture — a shared accelerator facility (DRY)

### New unit `source/tyControls.Accel.pas`

Lowest-level shared helpers, used by both the menu and every caption control (so `TyParseMnemonic` moves
out of `tyControls.Menu` — Button must not depend on Menu).

```pascal
unit tyControls.Accel;
{$mode objfpc}{$H+}
interface
uses Classes, Controls, LMessages;

{ Parse a caption mnemonic (moved verbatim from tyControls.Menu). Single '&' marks the next char and
  is removed; '&&' -> literal '&'; first single '&' wins; mnemonic returned upper-cased (#0 = none). }
function TyParseMnemonic(const ACaption: string; out ADisplay: string; out AMnemonicPos: Integer): Char;

{ True while Alt is currently held (the "show access keys" cue). Maintained by one app-wide input hook. }
function TyAccelShowing: Boolean;

{ Returns AMnemonicPos when TyAccelShowing, else 0 — pass to TTyPainter.DrawText to gate the underline. }
function TyAccelGatePos(AMnemonicPos: Integer): Integer;

{ Register/unregister a control to be Invalidate()d whenever the Alt-held state flips (so its underline
  appears/disappears live). Controls call these in Create/Destroy. The single Application user-input hook
  is installed on the first registration and removed when the registry empties. }
procedure TyAccelRegister(AControl: TControl);
procedure TyAccelUnregister(AControl: TControl);

{ DialogChar helper: True iff Message is Alt+<the caption's mnemonic> (Alt-only modifier gate + char match).
  Wraps the same correctness the menu's DialogChar fix established (CharCode is the TRANSLATED char). }
function TyIsAccelKey(const Message: TLMKey; const ACaption: string): Boolean;
implementation
  // - GTyShowing: Boolean; GRegistry: TFPList; GHooked: Boolean.
  // - AccelInput(Sender; Msg): alt := GetKeyState(VK_MENU) < 0; if changed -> GTyShowing := alt;
  //   invalidate every registered control. (LCLIntf.GetKeyState; VK_MENU.)
  // - Register installs Application.AddOnUserInputHandler(@AccelInput) once; Unregister removes the
  //   control and, when empty, RemoveOnUserInputHandler. finalization clears the registry.
end.
```

### Per-control changes (the repeating pattern)

Each caption control gets the same three edits:

1. **Display:** in `Paint`, replace the raw-caption draw with:
   ```pascal
   TyParseMnemonic(Caption, disp, mpos);
   P.DrawText(..., disp, ..., TyAccelGatePos(mpos));   // was: Caption, (no mnemonic arg)
   ```
   and measure `disp` wherever the caption width is measured.
2. **Live underline:** `TyAccelRegister(Self)` in the constructor, `TyAccelUnregister(Self)` in the destructor.
3. **Activation:** override `DialogChar`:
   ```pascal
   function TTyXxx.DialogChar(var Message: TLMKey): Boolean;
   begin
     if Enabled and TyIsAccelKey(Message, Caption) then
       begin <action>; Exit(True); end;
     Result := inherited DialogChar(Message);
   end;
   ```
   with `<action>` per control:

   | Control | `<action>` |
   |---|---|
   | `TTyButton` | `Click` |
   | `TTyCheckBox` / `TTyRadioButton` | `SetFocus; Click` (focus then toggle, like LCL) |
   | `TTyLabel` | `if FFocusControl <> nil then Click` (Click already focuses FocusControl) |
   | `TTyGroupBox` | focus the first focusable child (`SelectFirst`-style) |
   | `TTyPageControl` | per tab caption: match the mnemonic against each tab → switch `TabIndex` |

   `TTyGroupBox`/`TTyLabel` are `TTyGraphicControl` (non-windowed) but still receive `DialogChar` via the
   parent's broadcast, so the override works.

### Menu-bar refactor (consolidation)

`TTyMenuBar` currently has its own `FShowAccel` + `AccelInput` + private app-input hook. Refactor it onto
the shared facility: `TyAccelRegister(Self)` / `TyAccelUnregister(Self)`, and `AccelPos` → `TyAccelGatePos`.
The bar's `DialogChar` keeps its top-menu loop (it matches against multiple captions, not one). This proves
the facility is reusable and removes the duplicate hook. (The menu *dropdown* keeps showing underlines while
open — unchanged.)

## CSS / tokens

None. Mnemonics are caption semantics, not theme values; the underline uses the existing text color.

## Testing

- **Headless (fpcunit):** `TyParseMnemonic` (move the existing menu test, or re-cover here);
  `TyAccelGatePos` returns 0 vs the pos by the global flag; per control, that the drawn/measured text is the
  stripped `Display` (e.g. a `TTyButton` with `Caption := '&OK'` measures/exposes `'OK'` — add a small
  display-text seam if needed). `TyIsAccelKey` char/Alt logic where constructible.
- **Manual (real machine — none of the live behavior is headless-testable):** Alt reveals/hides underlines on
  every control; `Alt+O` clicks `&OK`; `Alt+E` toggles `E&nable`; a label mnemonic focuses its edit; a group
  box mnemonic focuses its first field; a tab mnemonic switches tabs.

## Risks

- **R1 — graphic-control DialogChar reach.** `DialogChar` on `TGraphicControl` is delivered via the parent's
  broadcast; confirmed it's a `TControl` virtual and `TCustomLabel` uses exactly this. Verify on a real form
  that `Alt+key` reaches `TTyLabel`/`TTyGroupBox`.
- **R2 — double activation / focus fights.** A control's `Click` from `DialogChar` plus any default handling
  must not double-fire. Gate on `Enabled`; `Exit(True)` to consume.
- **R3 — registry lifecycle.** The single app-input hook must be installed once and removed when the registry
  empties (and at finalization), with register/unregister balanced in every control's Create/Destroy.
- **R4 — verification is manual** (Alt state, focus, activation) — same constraint as the menu work; the
  adversarial review (which caught two real menu bugs) substitutes for live testing on the logic.

## Out of scope

- Sticky "keyboard cues" mode (underlines staying after Alt release once keyboard-engaged) — we use the
  literal "while Alt held" rule, consistent with the menu bar.
- Non-caption controls; a ToggleSwitch text label (can be added later with the same pattern).
- Changing control inheritance (no new `TTyCaptionControl` base — the shared facility is opt-in per control
  to avoid touching non-caption controls).
