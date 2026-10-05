unit tyControls.TrackEdit;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, LCLType, Math,
  tyControls.Types, tyControls.Painter, tyControls.StyleModel, tyControls.Base,
  tyControls.NumericEdit;

{ Value at device x within the slider span [ALeft,ARight), mapped to [AMin,AMax]
  (clamped to the ends). AMax<=AMin -> AMin. }
function TyTrackEditValueAt(AX, ALeft, ARight: Integer; AMin, AMax: Double): Double;
{ Device x of the thumb centre for AValue within [ALeft,ARight). AMax<=AMin -> ALeft. }
function TyTrackEditThumbX(AValue, AMin, AMax: Double; ALeft, ARight: Integer): Integer;

type
  { A numeric edit with an inline mini-slider in its reserved right zone: drag the thumb
    to set Value across [MinValue,MaxValue] (default 0..100), and the number echoes it.
    Descends from TTyCustomNumericEdit (Value / input filter / formatting) and paints + drives the
    slider through the TTyEdit RightReserve/PaintTrailing hooks. }
  TTyCustomTrackEdit = class(TTyCustomNumericEdit)
  private
    FSliderWidth: Integer;   // logical px of the slider zone
    FDragging: Boolean;
    procedure TrackSpan(out ALeft, ARight, AMidY: Integer);
    procedure SetFromX(AX: Integer);
  protected
    function RightReserve(APPI: Integer): Integer; override;
    procedure PaintTrailing(APainter: TTyPainter; const AZone: TRect; const AStyle: TTyStyleSet); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

  { TTyTrackEdit publishes TTyCustomTrackEdit's properties; everything lives in TTyCustomTrackEdit. }
  TTyTrackEdit = class(TTyCustomTrackEdit)
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
  end;

implementation

function TyTrackEditValueAt(AX, ALeft, ARight: Integer; AMin, AMax: Double): Double;
var frac: Double;
begin
  if (AMax <= AMin) or (ARight <= ALeft) then Exit(AMin);
  frac := (AX - ALeft) / (ARight - ALeft);
  if frac < 0 then frac := 0 else if frac > 1 then frac := 1;
  Result := AMin + frac * (AMax - AMin);
end;

function TyTrackEditThumbX(AValue, AMin, AMax: Double; ALeft, ARight: Integer): Integer;
var frac: Double;
begin
  if AMax <= AMin then Exit(ALeft);
  frac := (AValue - AMin) / (AMax - AMin);
  if frac < 0 then frac := 0 else if frac > 1 then frac := 1;
  Result := ALeft + Round(frac * (ARight - ALeft));
end;

constructor TTyCustomTrackEdit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSliderWidth := 74;
  MinValue := 0;
  MaxValue := 100;
  Decimals := 0;    // track values read as whole numbers by default
end;

function TTyCustomTrackEdit.RightReserve(APPI: Integer): Integer;
begin
  Result := MulDiv(FSliderWidth, APPI, 96);
end;

procedure TTyCustomTrackEdit.TrackSpan(out ALeft, ARight, AMidY: Integer);
var zone: TRect; margin: Integer;
begin
  zone := TrailingZone(Font.PixelsPerInch);
  margin := MulDiv(8, Font.PixelsPerInch, 96);
  ALeft := zone.Left + margin;
  ARight := zone.Right - margin;
  AMidY := (zone.Top + zone.Bottom) div 2;
end;

procedure TTyCustomTrackEdit.PaintTrailing(APainter: TTyPainter; const AZone: TRect; const AStyle: TTyStyleSet);
var
  accentS: TTyStyleSet;
  margin, tl, tr, midY, thumbX, r, halfTrack: Integer;
  trackFill, thumbFill: TTyFill;
begin
  margin := APainter.Scale(8);
  tl := AZone.Left + margin;
  tr := AZone.Right - margin;
  midY := (AZone.Top + AZone.Bottom) div 2;
  if tr <= tl then Exit;
  { The thumb of an inline slider is a TRACK BAR thumb, not a gauge's lit fill. It read
    'TyGaugeFill' only because that key happened to carry the accent — which chained this
    control's thumb to every gauge in the app and made it unstyleable on its own. TyTrackThumb
    already exists for exactly this part (TTyTrackBar resolves it), and carries the same
    var(--accent), so this is the same pixel with the right owner. }
  accentS := ActiveController.Model.ResolveStyle('TyTrackThumb', '', []);
  // Track (muted border colour), ~2 device px tall, 1-logical rounded.
  halfTrack := APainter.Scale(1);
  trackFill := Default(TTyFill);
  trackFill.Kind := tfkSolid;
  trackFill.Color := AStyle.BorderColor;
  APainter.FillBackground(Rect(tl, midY - halfTrack, tr, midY + halfTrack), trackFill, 1);
  // Thumb (accent circle, logical radius 5) at Value's position.
  thumbX := TyTrackEditThumbX(Value, MinValue, MaxValue, tl, tr);
  r := APainter.Scale(5);
  thumbFill := Default(TTyFill);
  thumbFill.Kind := tfkSolid;
  thumbFill.Color := accentS.Background.Color;
  APainter.FillBackground(Rect(thumbX - r, midY - r, thumbX + r, midY + r), thumbFill, 5);
end;

procedure TTyCustomTrackEdit.SetFromX(AX: Integer);
var tl, tr, midY: Integer;
begin
  TrackSpan(tl, tr, midY);
  if tr > tl then
    Value := TyTrackEditValueAt(AX, tl, tr, MinValue, MaxValue);
end;

procedure TTyCustomTrackEdit.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if (Button = mbLeft) and PtInRect(TrailingZone(Font.PixelsPerInch), Point(X, Y)) then
  begin
    FDragging := True;
    SetFromX(X);
    Exit;   // slider consumes the click (no caret / selection)
  end;
  inherited MouseDown(Button, Shift, X, Y);
end;

procedure TTyCustomTrackEdit.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  if FDragging then
  begin
    SetFromX(X);
    Exit;
  end;
  inherited MouseMove(Shift, X, Y);
end;

procedure TTyCustomTrackEdit.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if FDragging then
  begin
    FDragging := False;
    Exit;
  end;
  inherited MouseUp(Button, Shift, X, Y);
end;

end.
