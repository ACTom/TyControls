unit tyControls.CheckListBox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, StdCtrls, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.StyleModel, tyControls.Base,
  tyControls.ListBox;

type
  { A list box with a checkbox per row (via the TTyListBox.PaintItemContent hook).
    Per-row state is packed into Items.Objects[i] so it stays aligned with the item through
    Sorted / Delete (no parallel array that could desync):

        bits 0-1  Ord(State)  -- cbUnchecked / cbChecked / cbGrayed
        bit  2    disabled    -- 0 means enabled, so an untouched nil Objects[] entry is a
                                 plain enabled unchecked row, and every list written before
                                 tri-state existed (which stored 0/1) still reads correctly

    Click the checkbox column — or press Space on the selected row — to toggle; selection
    otherwise works as in TTyListBox. A row turned off through ItemEnabled[] refuses both
    and renders in the theme's disabled row style. Checkbox chrome comes from the
    'TyCheckBox' token. OnClickCheck fires when a check toggles. }
  TTyCheckListBox = class(TTyListBox)
  private
    FAllowGrayed: Boolean;
    FOnClickCheck: TNotifyEvent;
    function GetChecked(AIndex: Integer): Boolean;
    procedure SetChecked(AIndex: Integer; AValue: Boolean);
    function GetState(AIndex: Integer): TCheckBoxState;
    procedure SetState(AIndex: Integer; AValue: TCheckBoxState);
    function GetItemEnabled(AIndex: Integer): Boolean;
    procedure SetItemEnabled(AIndex: Integer; AValue: Boolean);
    { The packed word for AIndex, and the write-back. Out of range reads 0. }
    function ItemFlags(AIndex: Integer): PtrInt;
    procedure SetItemFlags(AIndex: Integer; AFlags: PtrInt);
  protected
    { The toggle column, in device px, client coordinates -- everything from the row's leading
      edge to just past the box. It used to be a WIDTH measured from x=0, which was only ever
      right because the column started at x=0; the leading edge moves twice now (a mirrored
      box docks its scrollbar on the left, and the column with it), so the zone is a rect.
      Protected so a guard can assert it against the box PaintItemContent actually drew --
      the two agreeing is the whole point of TyCheckBoxSlotRect. }
    function CheckZoneRect: TRect;
    procedure PaintItemContent(P: TTyPainter; const ARowRect: TRect; AIndex: Integer;
      const AStyle: TTyStyleSet); override;
    function ItemStatesFor(AIndex: Integer; ABaseStates: TTyStateSet): TTyStateSet; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    { Raised after a row's check state changed by user action. }
    procedure ClickCheck; virtual;
  public
    // Number of checked items (cbGrayed counts, as LCL's Checked[] reports it checked).
    function CheckedCount: Integer;
    { Advance AIndex through the state cycle: Unchecked -> Checked -> Unchecked, or, with
      AllowGrayed, Unchecked -> Grayed -> Checked -> Unchecked. LCL's NextStateMap
      (checklst.pas:233-243) value for value. A disabled row does not move. }
    procedure Toggle(AIndex: Integer);
    { Put every row into AState. aAllowGrayed=False leaves rows that are already cbGrayed
      alone; aAllowDisabled=False leaves rows ItemEnabled[] turned off. LCL checklst.pas:246. }
    procedure CheckAll(AState: TCheckBoxState; aAllowGrayed: Boolean = True;
      aAllowDisabled: Boolean = True);
    { Checked[] is the two-value view of State[]: reading it reports cbGrayed as CHECKED
      (LCL checklst.pas:279-282), writing it sets cbChecked / cbUnchecked outright. }
    property Checked[AIndex: Integer]: Boolean read GetChecked write SetChecked;
    { The full three-value state. LCL checklst.pas:85. Without it a "partially selected"
      row -- a parent whose children disagree -- had no way to say so. }
    property State[AIndex: Integer]: TCheckBoxState read GetState write SetState;
    { Turn one row off: it renders in the disabled row style and neither a click nor Space
      can toggle it. LCL checklst.pas:84 plus its keyboard gate at :336. An options list
      where some choices are unavailable no longer has to delete the rows. }
    property ItemEnabled[AIndex: Integer]: Boolean read GetItemEnabled write SetItemEnabled;
  published
    { Whether the user's toggle passes through cbGrayed. LCL checklst.pas:79, default
      False -- and the same name and default TTyCheckBox already carries. }
    property AllowGrayed: Boolean read FAllowGrayed write FAllowGrayed default False;
    property OnClickCheck: TNotifyEvent read FOnClickCheck write FOnClickCheck;
  end;

{ THE CHECK BOX INSIDE ONE ROW -- the only arithmetic in this control that says where the
  square is, and therefore the only one that can be wrong.

  PaintItemContent draws it here and MouseDown toggles when the click lands in the column
  around it; both go through this function with the same ARightToLeft, so there is no
  arrangement in which a mirrored box is drawn on one side and answers clicks on the other.
  That split -- painted right, clicked left -- is the exact defect this pass has been closing
  across the library, and it was live here in the shape of two independent formulas: a
  Left+pad+size rect in the painter and a Padding.Left+pad+size+pad WIDTH in the hit test,
  agreeing only because both happened to start from zero.

  APad is the scaled gap between the row edge and the box, and between the box and the text.
  The square is the row height less a pad top and bottom, floored so a very short row still
  gets something clickable. }
function TyCheckBoxSlotRect(const ARowRect: TRect; APad: Integer;
  ARightToLeft: Boolean): TRect;

implementation

function TyCheckBoxSlotRect(const ARowRect: TRect; APad: Integer;
  ARightToLeft: Boolean): TRect;
var
  sz, rowH, boxTop: Integer;
begin
  rowH := ARowRect.Bottom - ARowRect.Top;
  sz := rowH - 2 * APad;
  if sz < 6 then sz := 6;
  boxTop := ARowRect.Top + (rowH - sz) div 2;
  if ARightToLeft then
    Result := Rect(ARowRect.Right - APad - sz, boxTop, ARowRect.Right - APad, boxTop + sz)
  else
    Result := Rect(ARowRect.Left + APad, boxTop, ARowRect.Left + APad + sz, boxTop + sz);
end;

const
  { Bit layout of the packed per-row word in Items.Objects[i]. See the class comment for
    why 'disabled' rather than 'enabled' occupies bit 2. }
  ckStateMask = PtrInt(3);
  ckDisabled  = PtrInt(4);
  ckAllBits   = ckStateMask or ckDisabled;

function TTyCheckListBox.ItemFlags(AIndex: Integer): PtrInt;
begin
  Result := 0;
  if (AIndex < 0) or (AIndex >= Items.Count) then Exit;
  Result := PtrInt(Items.Objects[AIndex]);
  { Anything with bits outside our range is not ours -- an application (or
    TTyCheckComboBox, which parks a state object there) put a real pointer in Objects[].
    Report 0: such a row is unchecked and enabled, and the next write overwrites the slot
    wholesale rather than rewriting someone else's low bits in place. Reading a pointer as
    "checked" merely because it is non-zero is what made a row carrying app data drop down
    pre-ticked. }
  if (Result and not ckAllBits) <> 0 then Result := 0;
end;

procedure TTyCheckListBox.SetItemFlags(AIndex: Integer; AFlags: PtrInt);
begin
  if (AIndex < 0) or (AIndex >= Items.Count) then Exit;
  if PtrInt(Items.Objects[AIndex]) = AFlags then Exit;
  Items.Objects[AIndex] := TObject(AFlags);
  Invalidate;
end;

function TTyCheckListBox.GetState(AIndex: Integer): TCheckBoxState;
var v: PtrInt;
begin
  v := ItemFlags(AIndex) and ckStateMask;
  // 3 is not a state; a caller that stuffed its own object into Objects[] should not make
  // this raise. Clamp rather than range-check.
  if v > Ord(High(TCheckBoxState)) then v := Ord(cbUnchecked);
  Result := TCheckBoxState(v);
end;

procedure TTyCheckListBox.SetState(AIndex: Integer; AValue: TCheckBoxState);
begin
  SetItemFlags(AIndex, (ItemFlags(AIndex) and not ckStateMask) or PtrInt(Ord(AValue)));
end;

function TTyCheckListBox.GetChecked(AIndex: Integer): Boolean;
begin
  // cbGrayed reads as checked, exactly as LCL's GetChecked does (checklst.pas:279-282):
  // "not fully off" is what a two-value caller means by checked.
  Result := (AIndex >= 0) and (AIndex < Items.Count)
    and (GetState(AIndex) <> cbUnchecked);
end;

procedure TTyCheckListBox.SetChecked(AIndex: Integer; AValue: Boolean);
begin
  if AValue then SetState(AIndex, cbChecked) else SetState(AIndex, cbUnchecked);
end;

function TTyCheckListBox.GetItemEnabled(AIndex: Integer): Boolean;
begin
  Result := (ItemFlags(AIndex) and ckDisabled) = 0;
end;

procedure TTyCheckListBox.SetItemEnabled(AIndex: Integer; AValue: Boolean);
var f: PtrInt;
begin
  f := ItemFlags(AIndex) and not ckDisabled;
  if not AValue then f := f or ckDisabled;
  SetItemFlags(AIndex, f);
end;

procedure TTyCheckListBox.Toggle(AIndex: Integer);
const
  { LCL's NextStateMap, checklst.pas:233-243, value for value. }
  NextState: array[TCheckBoxState] of array[Boolean] of TCheckBoxState = (
    {cbUnchecked} (cbChecked,   cbGrayed),
    {cbChecked  } (cbUnchecked, cbUnchecked),
    {cbGrayed   } (cbChecked,   cbChecked));
begin
  if (AIndex < 0) or (AIndex >= Items.Count) then Exit;
  if not GetItemEnabled(AIndex) then Exit;   { a disabled row does not move }
  SetState(AIndex, NextState[GetState(AIndex)][FAllowGrayed]);
  ClickCheck;
end;

procedure TTyCheckListBox.CheckAll(AState: TCheckBoxState; aAllowGrayed: Boolean;
  aAllowDisabled: Boolean);
var i: Integer;
begin
  for i := 0 to Items.Count - 1 do
  begin
    if (not aAllowGrayed) and (GetState(i) = cbGrayed) then Continue;
    if (not aAllowDisabled) and (not GetItemEnabled(i)) then Continue;
    SetState(i, AState);
  end;
end;

procedure TTyCheckListBox.ClickCheck;
begin
  if Assigned(FOnClickCheck) then FOnClickCheck(Self);
end;

function TTyCheckListBox.CheckedCount: Integer;
var i: Integer;
begin
  Result := 0;
  for i := 0 to Items.Count - 1 do
    if GetChecked(i) then Inc(Result);
end;

function TTyCheckListBox.ItemStatesFor(AIndex: Integer; ABaseStates: TTyStateSet): TTyStateSet;
begin
  Result := inherited ItemStatesFor(AIndex, ABaseStates);
  // A row the host turned off must LOOK off. Without this ItemEnabled[] would only refuse
  // input, which reads to a user as a control that has stopped responding.
  if not GetItemEnabled(AIndex) then
  begin
    Exclude(Result, tysNormal);
    Exclude(Result, tysHover);
    Include(Result, tysDisabled);
  end;
end;

function TTyCheckListBox.CheckZoneRect: TRect;
var
  ppi, pad, sh, l, r: Integer;
  slot: TRect;
begin
  { Everything BEFORE the item text is the toggle column: the row's leading padding + the
    checkbox square + the gap after it. Built from the same row bounds RenderTo paints between
    and the same slot function PaintItemContent draws into, so the column cannot drift from
    the square inside it -- which is what the old width-from-zero did the moment either edge
    moved. The far end runs to the row's own edge so the leading padding stays clickable, the
    way it always was. }
  ppi := Font.PixelsPerInch;
  pad := MulDiv(4, ppi, 96);
  sh  := MulDiv(ItemHeight, ppi, 96);
  RowContentBounds(ClientWidth, ppi, l, r);
  slot := TyCheckBoxSlotRect(Rect(l, 0, r, sh), pad, RtlRowLayout);
  if RtlRowLayout then
    Result := Rect(slot.Left - pad, 0, ClientWidth, ClientHeight)
  else
    Result := Rect(0, 0, slot.Right + pad, ClientHeight);
end;

procedure TTyCheckListBox.PaintItemContent(P: TTyPainter; const ARowRect: TRect;
  AIndex: Integer; const AStyle: TTyStyleSet);
var
  cs: TTyStyleSet;
  st: TCheckBoxState;
  pad: Integer;
  boxR, textR: TRect;
  states: TTyStateSet;
begin
  st := GetState(AIndex);
  pad := P.Scale(4);
  boxR := TyCheckBoxSlotRect(ARowRect, pad, RtlRowLayout);
  // Checkbox chrome from the 'TyCheckBox' token. Both non-empty states resolve :active, so
  // a grayed box carries the same accent chrome as a checked one and differs by its glyph
  // -- which is how TTyCheckBox itself renders indeterminate.
  if st <> cbUnchecked then states := [tysActive] else states := [tysNormal];
  if not GetItemEnabled(AIndex) then
  begin
    Exclude(states, tysNormal);
    Include(states, tysDisabled);
  end;
  cs := ActiveController.Model.ResolveStyle('TyCheckBox', '', states);
  if tpBackground in cs.Present then
    P.FillBackground(boxR, cs.Background, cs.BorderRadius);
  if (tpBorderColor in cs.Present) and (cs.BorderWidth > 0) then
    P.StrokeBorder(boxR, cs.BorderRadius, cs.BorderWidth, cs.BorderColor);
  // Through TyDrawGlyph so a theme can substitute an icon-font codepoint, exactly as
  // TTyCheckBox does (tyControls.CheckBox.pas:264-266).
  case st of
    cbChecked: TyDrawGlyph(P, ActiveController, boxR, '--glyph-check', tgCheck, cs.TextColor, 2);
    cbGrayed:  TyDrawGlyph(P, ActiveController, boxR, '--glyph-check-indeterminate',
                           tgCheckIndeterminate, cs.TextColor, 2);
  end;
  // Item text, on the far side of the checkbox from the row's leading edge.
  if RtlRowLayout then
    textR := Rect(ARowRect.Left + P.Scale(AStyle.Padding.Right), ARowRect.Top,
      boxR.Left - pad, ARowRect.Bottom)
  else
    textR := Rect(boxR.Right + pad, ARowRect.Top,
      ARowRect.Right - P.Scale(AStyle.Padding.Right), ARowRect.Bottom);
  P.DrawText(textR, Items[AIndex], AStyle.FontName, ResolveFontSize(AStyle),
    AStyle.FontWeight, AStyle.TextColor,
    BidiFlipAlignment(taLeftJustify, RtlRowLayout), tlCenter, True);
end;

procedure TTyCheckListBox.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var row: Integer;
begin
  // Let the base handle focus + row selection first, THEN toggle if the click landed in the
  // checkbox column (so clicking a checkbox both selects the row and flips its check).
  inherited MouseDown(Button, Shift, X, Y);
  // NOTE: in LCL, MouseDown's Shift set INCLUDES the pressed button (ssLeft), so do NOT
  // gate on `Shift = []` — that is never true during a left click.
  if (Button = mbLeft) and PtInRect(CheckZoneRect, Point(X, Y)) then
  begin
    row := RowAtY(Y);
    // Toggle already refuses a disabled row; the guard here is only so a click on one
    // cannot be mistaken for a no-op caused by geometry.
    if (row >= 0) and GetItemEnabled(row) then Toggle(row);
  end;
end;

procedure TTyCheckListBox.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_SPACE) and (Shift = []) and (ItemIndex >= 0) then
  begin
    // LCL gates the keyboard toggle on ItemEnabled too (checklst.pas:336). Space is still
    // consumed on a disabled row: the row IS the focused one, so letting the key fall
    // through to the form would fire whatever default button is there.
    if GetItemEnabled(ItemIndex) then Toggle(ItemIndex);
    Key := 0;
    Exit;
  end;
  inherited KeyDown(Key, Shift);
end;

end.
