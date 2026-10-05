unit tyControls.URLEdit;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, LCLType, LCLIntf,
  tyControls.Types, tyControls.Painter, tyControls.StyleModel, tyControls.Controller, tyControls.Edit;

type
  { An edit for URLs: a plain edit (TTyCustomEdit) plus a trailing "open" button (a → glyph in the
    reserved right zone) that launches the current text in the default browser. Reuses
    the TTyEdit text engine + 'TyEdit' theme via the RightReserve/PaintTrailing hooks. }
  TTyCustomURLEdit = class(TTyCustomEdit)
  protected
    function RightReserve(APPI: Integer): Integer; override;
    procedure PaintTrailing(APainter: TTyPainter; const AZone: TRect; const AStyle: TTyStyleSet); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    // Launch the current text as a URL in the default browser (also fired by the button).
    procedure OpenURL;
  end;

  { TTyURLEdit publishes TTyCustomURLEdit's properties; everything lives in TTyCustomURLEdit. }
  TTyURLEdit = class(TTyCustomURLEdit)
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
  end;

implementation

constructor TTyCustomURLEdit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TextHint := 'https://…';
end;

function TTyCustomURLEdit.RightReserve(APPI: Integer): Integer;
begin
  // Trailing open-button slot: read the icon-size token live (density-aware) so the
  // modern density pack widens it; classic falls back to the original 20px constant
  // when the token is absent.
  Result := MulDiv(TyDensityMetric(ActiveController, 20, '--icon-size'), APPI, 96);
end;

procedure TTyCustomURLEdit.PaintTrailing(APainter: TTyPainter; const AZone: TRect; const AStyle: TTyStyleSet);
begin
  APainter.DrawGlyph(AZone, tgArrowRight, AStyle.TextColor, 2);
end;

procedure TTyCustomURLEdit.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if (Button = mbLeft) and PtInRect(TrailingZone(Font.PixelsPerInch), Point(X, Y)) then
  begin
    OpenURL;
    Exit;   // consumed by the button — don't move the caret / start a selection
  end;
  inherited MouseDown(Button, Shift, X, Y);
end;

procedure TTyCustomURLEdit.OpenURL;
begin
  if Trim(Text) <> '' then
    LCLIntf.OpenURL(Text);   // qualified: the method shares the name with the LCL routine
end;

end.
