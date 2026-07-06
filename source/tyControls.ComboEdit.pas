unit tyControls.ComboEdit;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.StyleModel, tyControls.Edit;

type
  { An edit with a trailing drop-down button. Clicking the button (or calling DropDown)
    fires OnDropDown, where the caller shows an arbitrary popup (colour grid, calculator,
    date picker, …) and writes the chosen value back into Text. The base for the richer
    combo-style edits. Reuses the TTyEdit text engine + 'TyEdit' theme via the
    RightReserve/PaintTrailing hooks. }
  TTyComboEdit = class(TTyEdit)
  private
    FButtonWidth: Integer;
    FOnDropDown: TNotifyEvent;
  protected
    function RightReserve(APPI: Integer): Integer; override;
    procedure PaintTrailing(APainter: TTyPainter; const AZone: TRect; const AStyle: TTyStyleSet); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    // Fire OnDropDown (also triggered by clicking the trailing button).
    procedure DropDown;
  published
    property OnDropDown: TNotifyEvent read FOnDropDown write FOnDropDown;
  end;

implementation

constructor TTyComboEdit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FButtonWidth := 20;
end;

function TTyComboEdit.RightReserve(APPI: Integer): Integer;
begin
  Result := MulDiv(FButtonWidth, APPI, 96);
end;

procedure TTyComboEdit.PaintTrailing(APainter: TTyPainter; const AZone: TRect; const AStyle: TTyStyleSet);
begin
  APainter.DrawDropChevron(AZone, AStyle.TextColor);   // fixed small chevron, like TTyComboBox
end;

procedure TTyComboEdit.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if (Button = mbLeft) and PtInRect(TrailingZone(Font.PixelsPerInch), Point(X, Y)) then
  begin
    DropDown;
    Exit;   // consumed by the button
  end;
  inherited MouseDown(Button, Shift, X, Y);
end;

procedure TTyComboEdit.DropDown;
begin
  if Assigned(FOnDropDown) then FOnDropDown(Self);
end;

end.
