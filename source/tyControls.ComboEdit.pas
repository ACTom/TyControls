unit tyControls.ComboEdit;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.StyleModel, tyControls.Edit,
  tyControls.Base, tyControls.Controller;

type
  { An edit with a trailing drop-down button. Clicking the button (or calling DropDown)
    fires OnDropDown, where the caller shows an arbitrary popup (colour grid, calculator,
    date picker, …) and writes the chosen value back into Text. The base for the richer
    combo-style edits. Reuses the TTyEdit text engine + 'TyEdit' theme via the
    RightReserve/PaintTrailing hooks. }
  TTyCustomComboEdit = class(TTyCustomEdit)
  private
    FOnDropDown: TNotifyEvent;
  protected
    function RightReserve(APPI: Integer): Integer; override;
    procedure PaintTrailing(APainter: TTyPainter; const AZone: TRect; const AStyle: TTyStyleSet); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    // Fire OnDropDown (also triggered by clicking the trailing button).
    procedure DropDown;
  protected
    property OnDropDown: TNotifyEvent read FOnDropDown write FOnDropDown;
  end;

  { TTyComboEdit publishes TTyCustomComboEdit's properties; everything lives in TTyCustomComboEdit. }
  TTyComboEdit = class(TTyCustomComboEdit)
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
    property OnDropDown;
  end;

implementation

constructor TTyCustomComboEdit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
end;

function TTyCustomComboEdit.RightReserve(APPI: Integer): Integer;
begin
  { Read the drop-button width live (like TTyComboBox.ButtonWidthLogical), so the
    trailing chevron zone tracks the theme's density and lines up with a combo box's.
    No constructor cache. }
  Result := MulDiv(ActiveController.Metric('--field-button-width', TyFieldButtonWidth), APPI, 96);
end;

procedure TTyCustomComboEdit.PaintTrailing(APainter: TTyPainter; const AZone: TRect; const AStyle: TTyStyleSet);
begin
  TyDrawDropChevron(APainter, ActiveController, AZone, AStyle.TextColor);   // like TTyComboBox
end;

procedure TTyCustomComboEdit.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if (Button = mbLeft) and PtInRect(TrailingZone(Font.PixelsPerInch), Point(X, Y)) then
  begin
    DropDown;
    Exit;   // consumed by the button
  end;
  inherited MouseDown(Button, Shift, X, Y);
end;

procedure TTyCustomComboEdit.DropDown;
begin
  if Assigned(FOnDropDown) then FOnDropDown(Self);
end;

end.
