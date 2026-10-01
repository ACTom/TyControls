unit tyControls.CalcCurrencyEdit;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls,
  tyControls.Types, tyControls.Painter, tyControls.StyleModel,
  tyControls.CurrencyEdit, tyControls.CalcEdit;

type
  { A currency edit with a trailing button that drops down a TTyCalculator; the calculator's
    result is written back into the edit. Everything else is the currency edit's
    (TTyCustomCurrencyEdit: currency symbol on the blurred display + grouped formatting). Reuses TTyCalcDropdown + the shared trailing
    button from tyControls.CalcEdit. }
  TTyCustomCalcCurrencyEdit = class(TTyCustomCurrencyEdit)
  private
    FDrop: TTyCalcDropdown;
  protected
    function RightReserve(APPI: Integer): Integer; override;
    procedure PaintTrailing(APainter: TTyPainter; const AZone: TRect; const AStyle: TTyStyleSet); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

  { TTyCalcCurrencyEdit publishes TTyCustomCalcCurrencyEdit's properties; everything lives in TTyCustomCalcCurrencyEdit. }
  TTyCalcCurrencyEdit = class(TTyCustomCalcCurrencyEdit)
  published
    property Version;
    property Enabled;
    property Visible;
    property Font;
    property ShowHint;
    property TabOrder;
    property TabStop;
    property OnClick;
    property OnDblClick;
    property OnMouseDown;
    property OnMouseUp;
    property OnMouseMove;
    property OnMouseEnter;
    property OnMouseLeave;
    property OnMouseWheel;
    property OnMouseWheelUp;
    property OnMouseWheelDown;
    property OnContextPopup;
    property OnResize;
    property OnChangeBounds;
    property AutoSize;
    property BorderWidth;
    property ChildSizing;
    property DragMode;
    property DragKind;
    property DragCursor;
    property OnDragOver;
    property OnDragDrop;
    property OnStartDrag;
    property OnEndDrag;
    property OnMouseWheelHorz;
    property OnMouseWheelLeft;
    property OnMouseWheelRight;
    property OnShowHint;
    property PopupMenu;
    property Constraints;
    property BorderSpacing;
    property ParentShowHint;
    property Action;
    property OnPaint;
    property OnKeyDown;
    property OnKeyUp;
    property OnKeyPress;
    property OnUTF8KeyPress;
    property OnEnter;
    property OnExit;
    property OnEditingDone;
    property StyleClass;
    property StyleOverride;
    property Controller;
    property Text;
    property ReadOnly;
    property MaxLength;
    property PasswordChar;
    property EchoMode;
    property HideSelection;
    property AutoSelect;
    property TextHint;
    property Alignment;
    property CharCase;
    property NumbersOnly;
    property Align;
    property Anchors;
    property OnChange;
    property Decimals;
    property UseThousands;
    property MinValue;
    property MaxValue;
    property CurrencySymbol;
    property SymbolBefore;
  end;

implementation

constructor TTyCustomCalcCurrencyEdit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FDrop := TTyCalcDropdown.Create(Self);   // TTyCustomCurrencyEdit is a TTyCustomNumericEdit
end;

function TTyCustomCalcCurrencyEdit.RightReserve(APPI: Integer): Integer;
begin
  Result := TyCalcButtonReserve(APPI);
end;

procedure TTyCustomCalcCurrencyEdit.PaintTrailing(APainter: TTyPainter; const AZone: TRect;
  const AStyle: TTyStyleSet);
begin
  TyDrawCalcButton(APainter, AZone, AStyle);
end;

procedure TTyCustomCalcCurrencyEdit.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if (Button = mbLeft) and PtInRect(TrailingZone(Font.PixelsPerInch), Point(X, Y)) then
  begin
    FDrop.Toggle;
    Exit;
  end;
  inherited MouseDown(Button, Shift, X, Y);
end;

end.
