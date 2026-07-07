unit tyControls.CalcEdit;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, LCLType, LCLIntf, BGRACanvas2D,
  tyControls.Types, tyControls.Painter, tyControls.StyleModel,
  tyControls.NumericEdit, tyControls.Popup, tyControls.Calculator;

type
  { Manages a drop-down TTyCalculator for a numeric edit. Owned by the edit; the popup + its
    calculator are created lazily on first open. Seeds the calculator from the edit's Value on
    open, and writes the calculator's Value back to the edit on '=' or when the popup closes.
    Shared by TTyCalcEdit and TTyCalcCurrencyEdit (both are TTyNumericEdit descendants). }
  TTyCalcDropdown = class(TComponent)
  private
    FEdit: TTyNumericEdit;
    FPopup: TTyDropdownPopup;
    FCalc: TTyCalculator;
    procedure DoResult(Sender: TObject);   // '=' pressed: apply + close
    procedure DoClosed(Sender: TObject);    // any close: apply the current value
  public
    constructor Create(AEdit: TTyNumericEdit); reintroduce;
    destructor Destroy; override;
    // Open the calculator (or close it if already open), anchored to the edit.
    procedure Toggle;
    function IsOpen: Boolean;
  end;

  { A numeric edit with a trailing button that drops down a TTyCalculator; the calculator's
    result is written back into the edit. Everything else is TTyNumericEdit (input filter +
    grouped-on-blur formatting + range). }
  TTyCalcEdit = class(TTyNumericEdit)
  private
    FDrop: TTyCalcDropdown;
  protected
    function RightReserve(APPI: Integer): Integer; override;
    procedure PaintTrailing(APainter: TTyPainter; const AZone: TRect; const AStyle: TTyStyleSet); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

{ Shared trailing-button glyph (a small 2x2 keypad grid) — reused by TTyCalcCurrencyEdit. }
procedure TyDrawCalcButton(APainter: TTyPainter; const AZone: TRect; const AStyle: TTyStyleSet);
{ Shared trailing-button reserve width (logical px), reused by TTyCalcCurrencyEdit. }
function TyCalcButtonReserve(APPI: Integer): Integer;

implementation

const
  cCalcButtonLogical = 22;   // trailing button width (logical px)

function TyCalcButtonReserve(APPI: Integer): Integer;
begin
  Result := MulDiv(cCalcButtonLogical, APPI, 96);
end;

procedure TyDrawCalcButton(APainter: TTyPainter; const AZone: TRect; const AStyle: TTyStyleSet);
var
  d, gap, cx, cy: Integer;
  ctx: TBGRACanvas2D;
begin
  ctx := APainter.Bitmap.Canvas2D;
  ctx.fillStyle(TyColorToBGRA(AStyle.TextColor));
  d := APainter.Scale(3);
  gap := APainter.Scale(2);
  cx := (AZone.Left + AZone.Right) div 2;
  cy := (AZone.Top + AZone.Bottom) div 2;
  // a 2x2 grid of small squares (a keypad hint)
  ctx.fillRect(cx - d - gap, cy - d - gap, d, d);
  ctx.fillRect(cx + gap,     cy - d - gap, d, d);
  ctx.fillRect(cx - d - gap, cy + gap,     d, d);
  ctx.fillRect(cx + gap,     cy + gap,     d, d);
end;

{ ---- TTyCalcDropdown ---- }

constructor TTyCalcDropdown.Create(AEdit: TTyNumericEdit);
begin
  inherited Create(AEdit);   // owned by the edit
  FEdit := AEdit;
end;

destructor TTyCalcDropdown.Destroy;
begin
  { Free the popup (its form) FIRST — it only parented FCalc — then FCalc. }
  FreeAndNil(FPopup);
  FreeAndNil(FCalc);
  inherited Destroy;
end;

function TTyCalcDropdown.IsOpen: Boolean;
begin
  Result := (FPopup <> nil) and FPopup.IsOpen;
end;

procedure TTyCalcDropdown.Toggle;
var w, h: Integer;
begin
  if IsOpen then
  begin
    FPopup.Close;
    Exit;
  end;
  { Reopen-race guard: clicking the button to CLOSE first deactivates + closes the popup, so this
    Toggle runs with IsOpen already False — suppress an immediate reopen (mirrors TTyComboBox). }
  if (FPopup <> nil) and (GetTickCount64 - FPopup.CloseUpTick <= 200) then Exit;
  if FPopup = nil then
  begin
    FPopup := TTyDropdownPopup.Create;
    FPopup.OnClose := @DoClosed;
    FCalc := TTyCalculator.Create(nil);   // owned by this helper (freed in Destroy)
    FCalc.OnResult := @DoResult;
    FPopup.SetContent(FCalc);
  end;
  FCalc.Controller := FEdit.Controller;   // theme with the edit's controller
  FCalc.Value := FEdit.Value;             // seed from the edit
  w := MulDiv(210, FEdit.Font.PixelsPerInch, 96);
  h := MulDiv(290, FEdit.Font.PixelsPerInch, 96);
  FPopup.Popup(FEdit, w, h);
  if FCalc.CanFocus then FCalc.SetFocus;  // keyboard input goes to the calculator
end;

procedure TTyCalcDropdown.DoResult(Sender: TObject);
begin
  if (FCalc = nil) or FCalc.IsError then Exit;   // don't commit/close on an error result
  FEdit.Value := FCalc.Value;   // '=' : apply
  if FPopup <> nil then FPopup.Close;
end;

procedure TTyCalcDropdown.DoClosed(Sender: TObject);
begin
  { Apply the current value on close — but NOT while in the error state (Value is 0 there, which
    would silently wipe the field). }
  if (FCalc <> nil) and not FCalc.IsError then FEdit.Value := FCalc.Value;
end;

{ ---- TTyCalcEdit ---- }

constructor TTyCalcEdit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FDrop := TTyCalcDropdown.Create(Self);
end;

function TTyCalcEdit.RightReserve(APPI: Integer): Integer;
begin
  Result := TyCalcButtonReserve(APPI);
end;

procedure TTyCalcEdit.PaintTrailing(APainter: TTyPainter; const AZone: TRect;
  const AStyle: TTyStyleSet);
begin
  TyDrawCalcButton(APainter, AZone, AStyle);
end;

procedure TTyCalcEdit.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if (Button = mbLeft) and PtInRect(TrailingZone(Font.PixelsPerInch), Point(X, Y)) then
  begin
    FDrop.Toggle;
    Exit;   // consumed by the calc button
  end;
  inherited MouseDown(Button, Shift, X, Y);
end;

end.
