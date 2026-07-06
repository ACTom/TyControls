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
    Subclasses TTyNumericEdit (Value / input filter / formatting) and paints + drives the
    slider through the TTyEdit RightReserve/PaintTrailing hooks. }
  TTyTrackEdit = class(TTyNumericEdit)
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

constructor TTyTrackEdit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSliderWidth := 74;
  MinValue := 0;
  MaxValue := 100;
  Decimals := 0;    // track values read as whole numbers by default
end;

function TTyTrackEdit.RightReserve(APPI: Integer): Integer;
begin
  Result := MulDiv(FSliderWidth, APPI, 96);
end;

procedure TTyTrackEdit.TrackSpan(out ALeft, ARight, AMidY: Integer);
var zone: TRect; margin: Integer;
begin
  zone := TrailingZone(Font.PixelsPerInch);
  margin := MulDiv(8, Font.PixelsPerInch, 96);
  ALeft := zone.Left + margin;
  ARight := zone.Right - margin;
  AMidY := (zone.Top + zone.Bottom) div 2;
end;

procedure TTyTrackEdit.PaintTrailing(APainter: TTyPainter; const AZone: TRect; const AStyle: TTyStyleSet);
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
  accentS := ActiveController.Model.ResolveStyle('TyGaugeFill', '', []);   // theme accent
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

procedure TTyTrackEdit.SetFromX(AX: Integer);
var tl, tr, midY: Integer;
begin
  TrackSpan(tl, tr, midY);
  if tr > tl then
    Value := TyTrackEditValueAt(AX, tl, tr, MinValue, MaxValue);
end;

procedure TTyTrackEdit.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if (Button = mbLeft) and PtInRect(TrailingZone(Font.PixelsPerInch), Point(X, Y)) then
  begin
    FDragging := True;
    SetFromX(X);
    Exit;   // slider consumes the click (no caret / selection)
  end;
  inherited MouseDown(Button, Shift, X, Y);
end;

procedure TTyTrackEdit.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  if FDragging then
  begin
    SetFromX(X);
    Exit;
  end;
  inherited MouseMove(Shift, X, Y);
end;

procedure TTyTrackEdit.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if FDragging then
  begin
    FDragging := False;
    Exit;
  end;
  inherited MouseUp(Button, Shift, X, Y);
end;

end.
