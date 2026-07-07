unit tyControls.CalcCurrencyEdit;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls,
  tyControls.Types, tyControls.Painter, tyControls.StyleModel,
  tyControls.CurrencyEdit, tyControls.CalcEdit;

type
  { A currency edit with a trailing button that drops down a TTyCalculator; the calculator's
    result is written back into the edit. Everything else is TTyCurrencyEdit (currency symbol
    on the blurred display + grouped formatting). Reuses TTyCalcDropdown + the shared trailing
    button from tyControls.CalcEdit. }
  TTyCalcCurrencyEdit = class(TTyCurrencyEdit)
  private
    FDrop: TTyCalcDropdown;
  protected
    function RightReserve(APPI: Integer): Integer; override;
    procedure PaintTrailing(APainter: TTyPainter; const AZone: TRect; const AStyle: TTyStyleSet); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

implementation

constructor TTyCalcCurrencyEdit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FDrop := TTyCalcDropdown.Create(Self);   // TTyCurrencyEdit is a TTyNumericEdit
end;

function TTyCalcCurrencyEdit.RightReserve(APPI: Integer): Integer;
begin
  Result := TyCalcButtonReserve(APPI);
end;

procedure TTyCalcCurrencyEdit.PaintTrailing(APainter: TTyPainter; const AZone: TRect;
  const AStyle: TTyStyleSet);
begin
  TyDrawCalcButton(APainter, AZone, AStyle);
end;

procedure TTyCalcCurrencyEdit.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if (Button = mbLeft) and PtInRect(TrailingZone(Font.PixelsPerInch), Point(X, Y)) then
  begin
    FDrop.Toggle;
    Exit;
  end;
  inherited MouseDown(Button, Shift, X, Y);
end;

end.
