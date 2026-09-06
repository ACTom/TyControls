unit tyControls.Rating;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Math, Controls, Graphics, LCLType,
  BGRABitmapTypes, BGRACanvas2D,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller, tyControls.StyleModel,
  tyControls.Gauge;

{ Map a horizontal position AX (client px) inside a strip of AWidth px holding
  ACount evenly divided star cells to a rating in [1..ACount]. When AAllowHalf
  the result snaps to the nearest half (0.5 steps); otherwise to a whole star.
  Anything left of the first cell rounds up to the first (half-)step, anything
  past the right clamps to ACount. Returns 0 for a degenerate strip (ACount <= 0
  or AWidth <= 0) so callers can't divide by zero or read past the range. }
function TyRatingValueFromX(AX, AWidth, ACount: Integer; AAllowHalf: Boolean): Double;

type
  { An INTERACTIVE star rating: ACount star glyphs left-to-right, filled up to Value
    with the remainder outlined in the face text colour; a half star fills its left
    half. Hovering previews the value under the cursor, clicking commits it, and
    clicking the current single-star value again clears to 0. Arrow keys / Home / End
    also move Value. Themed as itself — 'TyRating' (face + empty/half outlines) and
    'TyRatingStar' (the filled glyph). Star gold is the most theme-specific colour in a
    UI kit and must NOT be the app accent by construction: under the old borrowed key,
    recolouring a rating also recoloured every progress ring, spinner and clock hand.
    The star style is resolved with :hover while the preview is live, so a skin can give
    the preview its own colour — previously impossible, the preview reused the committed
    fill. Direct manipulation SNAPS (no ease) so headless render tests stay pixel-stable. }
  TTyRating = class(TTyCustomControl)
  private
    FCount: Integer;
    FValue: Double;
    FAllowHalf: Boolean;
    FReadOnly: Boolean;
    FHoverValue: Double;   // >= 0 while previewing under the cursor; < 0 when idle
    FOnChange: TNotifyEvent;
    procedure SetCount(const AValue: Integer);
    procedure SetValue(const AValue: Double);
    procedure SetAllowHalf(const AValue: Boolean);
    procedure SetReadOnly(const AValue: Boolean);
    procedure ApplyValue(AValue: Double);   // clamp + Invalidate + fire OnChange on real change
    function DisplayValue: Double;           // hover preview if active, else committed Value
  protected
    function GetStyleTypeKey: string; override;   // 'TyRating' (+ 'Star' sub-part)
    procedure Paint; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property Count: Integer read FCount write SetCount default 5;
    property Value: Double read FValue write SetValue;
    property AllowHalf: Boolean read FAllowHalf write SetAllowHalf default False;
    property ReadOnly: Boolean read FReadOnly write SetReadOnly default False;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property Font;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
    property TabStop default True;
  end;

implementation

function TyRatingValueFromX(AX, AWidth, ACount: Integer; AAllowHalf: Boolean): Double;
var
  raw, cell: Double;
  step: Double;
begin
  if (ACount <= 0) or (AWidth <= 0) then Exit(0);
  cell := AWidth / ACount;
  // Which fractional star does AX fall in (0 at the very left, ACount at the right).
  raw := AX / cell;
  if raw < 0 then raw := 0 else if raw > ACount then raw := ACount;
  if AAllowHalf then step := 0.5 else step := 1.0;
  // Round UP to the next step so the left edge of a cell already selects that star.
  Result := Ceil(raw / step) * step;
  if Result < step then Result := step;      // never below the first (half-)step
  if Result > ACount then Result := ACount;  // clamp to the last star
end;

{ TTyRating }

constructor TTyRating.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TabStop := True;
  FCount := 5;
  FValue := 0;
  FAllowHalf := False;
  FReadOnly := False;
  FHoverValue := -1;
  Width := 120;
  Height := TyDensityHeight(ActiveController, 24);
end;

function TTyRating.GetStyleTypeKey: string;
begin
  { Its own key, not the gauge's: star gold is a per-theme decision that must be settable
    without dragging the app accent (and every gauge fill) along with it. }
  Result := 'TyRating';
end;

procedure TTyRating.ApplyValue(AValue: Double);
var v: Double;
begin
  v := AValue;
  if v < 0 then v := 0 else if v > FCount then v := FCount;
  if FValue = v then Exit;      // no OnChange on a same-value set
  FValue := v;
  Invalidate;
  if Assigned(FOnChange) then FOnChange(Self);
end;

function TTyRating.DisplayValue: Double;
begin
  if FHoverValue >= 0 then Result := FHoverValue else Result := FValue;
end;

procedure TTyRating.SetCount(const AValue: Integer);
begin
  if FCount = AValue then Exit;
  FCount := Math.Max(1, AValue);
  if FValue > FCount then FValue := FCount;
  Invalidate;
end;

procedure TTyRating.SetValue(const AValue: Double);
begin
  // Programmatic set clamps + fires OnChange (only on a real change), like click.
  ApplyValue(AValue);
end;

procedure TTyRating.SetAllowHalf(const AValue: Boolean);
begin
  if FAllowHalf = AValue then Exit;
  FAllowHalf := AValue;
  if not FAllowHalf then FValue := Round(FValue);   // snap off any half on toggle
  Invalidate;
end;

procedure TTyRating.SetReadOnly(const AValue: Boolean);
begin
  if FReadOnly = AValue then Exit;
  FReadOnly := AValue;
  if FReadOnly then FHoverValue := -1;   // drop any live preview
  Invalidate;
end;

procedure TTyRating.KeyDown(var Key: Word; Shift: TShiftState);
var stp: Double;
begin
  if not Enabled then Exit;
  inherited KeyDown(Key, Shift);
  if FReadOnly then Exit;
  if FAllowHalf then stp := 0.5 else stp := 1.0;
  case Key of
    VK_RIGHT, VK_UP:    begin ApplyValue(FValue + stp); Key := 0; end;
    VK_LEFT, VK_DOWN:   begin ApplyValue(FValue - stp); Key := 0; end;
    VK_HOME:            begin ApplyValue(0); Key := 0; end;
    VK_END:             begin ApplyValue(FCount); Key := 0; end;
  end;
end;

procedure TTyRating.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var v: Double;
begin
  if not Enabled then Exit;
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  if TabStop and CanFocus then SetFocus;
  if FReadOnly then Exit;
  v := TyRatingValueFromX(X, ClientWidth, FCount, FAllowHalf);
  // Clicking the current single-star value again clears to 0.
  if (not FAllowHalf) and (v = FValue) then v := 0;
  ApplyValue(v);
end;

procedure TTyRating.MouseMove(Shift: TShiftState; X, Y: Integer);
var v: Double;
begin
  if not Enabled then Exit;
  inherited MouseMove(Shift, X, Y);
  if FReadOnly then Exit;
  v := TyRatingValueFromX(X, ClientWidth, FCount, FAllowHalf);
  if FHoverValue <> v then
  begin
    FHoverValue := v;
    Invalidate;
  end;
end;

procedure TTyRating.MouseLeave;
begin
  inherited MouseLeave;
  if FHoverValue >= 0 then
  begin
    FHoverValue := -1;
    Invalidate;
  end;
end;

procedure TTyRating.Paint;
var
  P: TTyPainter;
  faceS, starS: TTyStyleSet;
  starStates: TTyStateSet;
  R: TRect;
  ctx: TBGRACanvas2D;
  cellW, size, radiusOuter, radiusInner, cx, cy, fillTo: Double;
  i, bw: Integer;

  { 星形路径已抽到 TTyPainter.StarPath —— 网格的星级单元格用的是同一份几何,
    两边各画一套的话同一个值在两处会长得不一样。 }
  procedure StarPath(ACx, ACy, AOuter, AInner: Double);
  begin
    P.StarPath(ACx, ACy, AOuter, AInner);
  end;

begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ClientWidth, ClientHeight);
    P.BeginPaint(Canvas, ClientRect, Font.PixelsPerInch);
    TyApplyStyleOpacity(Self, P, CurrentStyle);   // :disabled { opacity } — this control self-draws (no DrawFrame)
    faceS := CurrentStyle;                                              // TyRating face/border/text
    { Sub-part key derived from the box key so the two can never drift apart. The :hover
      state is asked for only while the preview is live (FHoverValue >= 0), which is what
      makes "preview stars look different" writable in a skin at all. }
    if FHoverValue >= 0 then starStates := [tysHover] else starStates := [];
    starS := ActiveController.Model.ResolveStyle(GetStyleTypeKey + 'Star', StyleClass, starStates);

    // Windowed control (own HWND): fill the full rect with the parent/form background first, so
    // the gaps around/between the stars show the form (or the image-theme photo), not the HWND's
    // white brush. Graphic siblings paint straight onto the form; a windowed control must paint
    // its own backdrop.
    TyFillParentBg(Self, P, R, faceS);

    if (FCount > 0) and (R.Right > R.Left) and (R.Bottom > R.Top) then
    begin
      ctx := P.Bitmap.Canvas2D;
      ctx.lineJoin := 'round';
      cellW := (R.Right - R.Left) / FCount;
      size := Math.Min(cellW, Double(R.Bottom - R.Top));   // Double(): int+Double picks Min's Single overload
      radiusOuter := size / 2 - P.Scale(2);
      if radiusOuter >= 2 then
      begin
        radiusInner := radiusOuter * 0.5;
        cy := (R.Top + R.Bottom) / 2;
        bw := Math.Max(1, P.Scale(Math.Max(1, faceS.BorderWidth)));
        fillTo := DisplayValue;
        for i := 0 to FCount - 1 do
        begin
          cx := R.Left + cellW * (i + 0.5);
          // Fraction of THIS star that is filled: 1 whole, 0.5 half, else 0.
          if fillTo >= i + 1 then
          begin
            // Fully filled star in the star colour.
            StarPath(cx, cy, radiusOuter, radiusInner);
            ctx.fillStyle(TyColorToBGRA(starS.Background.Color));
            ctx.fill;
          end
          else if fillTo >= i + 0.5 then
          begin
            // Half star: outline the whole glyph, then star-fill its left half
            // by clipping to the left rectangle of the cell.
            ctx.save;
            ctx.beginPath;
            ctx.rect(cx - radiusOuter, cy - radiusOuter, radiusOuter, 2 * radiusOuter);
            ctx.clip;
            StarPath(cx, cy, radiusOuter, radiusInner);
            ctx.fillStyle(TyColorToBGRA(starS.Background.Color));
            ctx.fill;
            ctx.restore;
            StarPath(cx, cy, radiusOuter, radiusInner);
            ctx.lineWidth := bw;
            ctx.strokeStyle(TyColorToBGRA(faceS.TextColor));
            ctx.stroke;
          end
          else
          begin
            // Empty star: outline only in the face border/text colour.
            StarPath(cx, cy, radiusOuter, radiusInner);
            ctx.lineWidth := bw;
            ctx.strokeStyle(TyColorToBGRA(faceS.TextColor));
            ctx.stroke;
          end;
        end;
      end;
    end;

    P.EndPaint;
  finally
    P.Free;
  end;
end;

end.
