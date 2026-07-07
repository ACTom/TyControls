unit tyControls.CheckListBox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.StyleModel, tyControls.Base,
  tyControls.ListBox;

type
  { A list box with a checkbox per row (via the TTyListBox.PaintItemContent hook). The
    checked state is stored in Items.Objects[i] (0/1) so it stays aligned with the item
    through Sorted / Delete (no parallel array). Click the checkbox column — or press Space
    on the selected row — to toggle; selection otherwise works as in TTyListBox. Checkbox
    chrome comes from the 'TyCheckBox' token. OnClickCheck fires when a check toggles. }
  TTyCheckListBox = class(TTyListBox)
  private
    FOnClickCheck: TNotifyEvent;
    function GetChecked(AIndex: Integer): Boolean;
    procedure SetChecked(AIndex: Integer; AValue: Boolean);
    function CheckZoneWidth: Integer;   // device px of the left checkbox column
    procedure ToggleCheck(AIndex: Integer);
  protected
    procedure PaintItemContent(P: TTyPainter; const ARowRect: TRect; AIndex: Integer;
      const AStyle: TTyStyleSet); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    // Number of checked items.
    function CheckedCount: Integer;
    property Checked[AIndex: Integer]: Boolean read GetChecked write SetChecked;
  published
    property OnClickCheck: TNotifyEvent read FOnClickCheck write FOnClickCheck;
  end;

implementation

function TTyCheckListBox.GetChecked(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex < Items.Count)
    and (PtrInt(Items.Objects[AIndex]) <> 0);
end;

procedure TTyCheckListBox.SetChecked(AIndex: Integer; AValue: Boolean);
begin
  if (AIndex < 0) or (AIndex >= Items.Count) then Exit;
  if GetChecked(AIndex) = AValue then Exit;
  Items.Objects[AIndex] := TObject(PtrInt(Ord(AValue)));
  Invalidate;
end;

procedure TTyCheckListBox.ToggleCheck(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex >= Items.Count) then Exit;
  SetChecked(AIndex, not GetChecked(AIndex));
  if Assigned(FOnClickCheck) then FOnClickCheck(Self);
end;

function TTyCheckListBox.CheckedCount: Integer;
var i: Integer;
begin
  Result := 0;
  for i := 0 to Items.Count - 1 do
    if GetChecked(i) then Inc(Result);
end;

function TTyCheckListBox.CheckZoneWidth: Integer;
var
  s: TTyStyleSet;
  sh, pad, sz: Integer;
begin
  // Everything left of the item TEXT is the toggle column: the row's left padding + the
  // checkbox square (row-height minus insets) + a gap. Tracks the actual box geometry
  // (same as PaintItemContent) rather than assuming a fixed width.
  s := CurrentStyle;
  sh := MulDiv(ItemHeight, Font.PixelsPerInch, 96);
  pad := MulDiv(4, Font.PixelsPerInch, 96);
  sz := sh - 2 * pad;
  if sz < 6 then sz := 6;
  Result := MulDiv(s.Padding.Left, Font.PixelsPerInch, 96) + pad + sz + pad;
end;

procedure TTyCheckListBox.PaintItemContent(P: TTyPainter; const ARowRect: TRect;
  AIndex: Integer; const AStyle: TTyStyleSet);
var
  cs: TTyStyleSet;
  isChecked: Boolean;
  pad, sz, boxTop: Integer;
  boxR, textR: TRect;
  states: TTyStateSet;
begin
  isChecked := GetChecked(AIndex);
  pad := P.Scale(4);
  sz := (ARowRect.Bottom - ARowRect.Top) - 2 * pad;
  if sz < 6 then sz := 6;
  boxTop := ARowRect.Top + ((ARowRect.Bottom - ARowRect.Top) - sz) div 2;
  boxR := Rect(ARowRect.Left + pad, boxTop, ARowRect.Left + pad + sz, boxTop + sz);
  // Checkbox chrome from the 'TyCheckBox' token (checked -> active/accent).
  if isChecked then states := [tysActive] else states := [tysNormal];
  cs := ActiveController.Model.ResolveStyle('TyCheckBox', '', states);
  if tpBackground in cs.Present then
    P.FillBackground(boxR, cs.Background, cs.BorderRadius);
  if (tpBorderColor in cs.Present) and (cs.BorderWidth > 0) then
    P.StrokeBorder(boxR, cs.BorderRadius, cs.BorderWidth, cs.BorderColor);
  if isChecked then
    P.DrawGlyph(boxR, tgCheck, cs.TextColor, 2);
  // Item text, to the right of the checkbox.
  textR := Rect(boxR.Right + pad, ARowRect.Top,
    ARowRect.Right - P.Scale(AStyle.Padding.Right), ARowRect.Bottom);
  P.DrawText(textR, Items[AIndex], AStyle.FontName, ResolveFontSize(AStyle),
    AStyle.FontWeight, AStyle.TextColor, taLeftJustify, tlCenter, True);
end;

procedure TTyCheckListBox.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var row: Integer;
begin
  // Let the base handle focus + row selection first, THEN toggle if the click landed in the
  // checkbox column (so clicking a checkbox both selects the row and flips its check).
  inherited MouseDown(Button, Shift, X, Y);
  // NOTE: in LCL, MouseDown's Shift set INCLUDES the pressed button (ssLeft), so do NOT
  // gate on `Shift = []` — that is never true during a left click.
  if (Button = mbLeft) and (X < CheckZoneWidth) then
  begin
    row := RowAtY(Y);
    if row >= 0 then ToggleCheck(row);
  end;
end;

procedure TTyCheckListBox.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_SPACE) and (Shift = []) and (ItemIndex >= 0) then
  begin
    ToggleCheck(ItemIndex);
    Key := 0;
    Exit;
  end;
  inherited KeyDown(Key, Shift);
end;

end.
