unit tyControls.SizeBox;
{$mode objfpc}{$H+}
{ TTySizeBox — a bottom-right resize grip (the classic Windows "size grip"): a
  diagonal ladder of dots painted in the bottom-right corner. Dragging it with the
  left mouse button resizes its Target (a TControl; default = the owner form / the
  parent) by the mouse delta, clamped to the target's Constraints.

  Reuses the 'TyPanel' typeKey (no new theme token in this batch); the grip dot
  colours are DERIVED from the resolved style (border/text blended toward the
  highlight/shadow), never hard-coded. }
interface
uses
  Classes, SysUtils, Types, Controls, Forms, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base;

type
  TTySizeBox = class(TTyGraphicControl)
  private
    FTarget: TControl;
    FDragging: Boolean;
    FMouseStart: TPoint;   // mouse SCREEN position at drag start (1:1 follow)
    FStartW, FStartH: Integer;
    procedure SetTarget(AValue: TControl);
    function ResolveTarget: TControl;   // FTarget, else owner form, else Parent
  protected
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    { The control resized by dragging the grip. When nil, the grip resizes the owner
      form (if the owner is a TCustomForm) or, failing that, the Parent control. }
    property Target: TControl read FTarget write SetTarget;
    property Anchors;
    property StyleClass;
    property StyleOverride;
    property Controller;
  end;

{ --- Pure geometry (headless-testable; no window handle needed) --------------- }

{ The dot centres of the classic bottom-right size grip, laid out as a diagonal
  triangular ladder inside ARect (device px). The 3 anti-diagonals from the corner
  hold 3, 2, 1 dots (6 total), each dot a fixed logical size scaled by APPI. The
  returned points are the dot CENTRES, anchored to the bottom-right corner. }
function TySizeGripDots(const ARect: TRect; APPI: Integer): TTyRectArray;

{ True when APt falls inside the grip's hit region: the bottom-right triangle whose
  legs equal the grip's device extent (so the whole visible ladder, plus the corner,
  is draggable). Points above/left of the anti-diagonal are outside. }
function TySizeGripHit(const ARect: TRect; APPI: Integer; const APt: TPoint): Boolean;

{ New (width, height) after dragging the grip by (dx, dy) device px from a start size,
  clamped to the given minimums. AMinW/AMinH <= 0 are treated as 1 (a control can never
  collapse to a zero dimension). Pure arithmetic — the actual SetBounds is interaction. }
function TySizeApplyDelta(AStartW, AStartH, ADx, ADy, AMinW, AMinH: Integer): TSize;

implementation

uses
  tyControls.Css.Values;   // TyMix / TyLighten / TyDarken (derive 3D grip colours)

const
  GripDotLogical  = 2;   // dot side, logical px (square dot, like the Windows grip)
  GripStepLogical = 4;   // centre-to-centre spacing along each axis, logical px
  GripPadLogical  = 3;   // inset of the outermost dot from the bottom-right corner

{ --- geometry ---------------------------------------------------------------- }

function TySizeGripDots(const ARect: TRect; APPI: Integer): TTyRectArray;
var
  dot, step, pad, i, j, n, right, bottom, cx, cy, half: Integer;
begin
  // Scale the logical metrics for the target DPI (mirrors TTyPainter.Scale).
  Result := nil;
  dot  := MulDiv(GripDotLogical,  APPI, 96); if dot  < 1 then dot  := 1;
  step := MulDiv(GripStepLogical, APPI, 96); if step < dot + 1 then step := dot + 1;
  pad  := MulDiv(GripPadLogical,  APPI, 96); if pad  < 0 then pad  := 0;
  right  := ARect.Right  - 1 - pad;   // centre of the outermost (corner) dot
  bottom := ARect.Bottom - 1 - pad;
  half := dot div 2;
  // Diagonal ladder: anti-diagonal d (0=corner-most) holds (3-d) dots. Dot j on
  // diagonal d sits at (right - (d+j)*step, bottom - d*step) mirrored so it climbs
  // up-and-left. Classic 3/2/1 triangle => 6 dots.
  SetLength(Result, 6);
  n := 0;
  for i := 0 to 2 do            // i = row from the bottom (0 = bottom row)
    for j := 0 to 2 - i do      // fewer dots as we climb: 3, 2, 1
    begin
      cx := right  - j * step;
      cy := bottom - i * step;
      Result[n] := Rect(cx - half, cy - half, cx - half + dot, cy - half + dot);
      Inc(n);
    end;
  SetLength(Result, n);
end;

function TySizeGripHit(const ARect: TRect; APPI: Integer; const APt: TPoint): Boolean;
var
  step, pad, extent, dxFromRight, dyFromBottom: Integer;
begin
  step := MulDiv(GripStepLogical, APPI, 96); if step < 1 then step := 1;
  pad  := MulDiv(GripPadLogical,  APPI, 96); if pad  < 0 then pad  := 0;
  // The grip spans 3 diagonal steps out from the corner dot (which is inset by pad).
  extent := 3 * step + pad;
  dxFromRight  := ARect.Right  - APt.X;   // 0 at the right edge, grows leftward
  dyFromBottom := ARect.Bottom - APt.Y;   // 0 at the bottom edge, grows upward
  // Inside the bottom-right corner box AND below the anti-diagonal (dx + dy <= extent).
  Result := (dxFromRight >= 0) and (dxFromRight <= extent)
        and (dyFromBottom >= 0) and (dyFromBottom <= extent)
        and (dxFromRight + dyFromBottom <= extent);
end;

function TySizeApplyDelta(AStartW, AStartH, ADx, ADy, AMinW, AMinH: Integer): TSize;
begin
  if AMinW < 1 then AMinW := 1;
  if AMinH < 1 then AMinH := 1;
  Result.cx := AStartW + ADx;
  Result.cy := AStartH + ADy;
  if Result.cx < AMinW then Result.cx := AMinW;
  if Result.cy < AMinH then Result.cy := AMinH;
end;

{ --- control ----------------------------------------------------------------- }

constructor TTySizeBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Width := 16;
  Height := 16;
  Cursor := crSizeNWSE;
end;

function TTySizeBox.GetStyleTypeKey: string;
begin
  { Own key rather than the borrowed 'TyPanel': the engraved size grip is a mark a panel never draws.
    Added to 'TyPanel's rule block as an extra selector, so every resolved value is
    unchanged — this opens a hook, it does not restyle anything. }
  Result := 'TySizeBox';
end;

procedure TTySizeBox.SetTarget(AValue: TControl);
begin
  if FTarget = AValue then Exit;
  if FTarget <> nil then FTarget.RemoveFreeNotification(Self);
  FTarget := AValue;
  if FTarget <> nil then FTarget.FreeNotification(Self);
end;

procedure TTySizeBox.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FTarget) then
    FTarget := nil;
end;

function TTySizeBox.ResolveTarget: TControl;
begin
  // Explicit target wins; else the owning form; else the immediate parent.
  if FTarget <> nil then
    Exit(FTarget);
  if (Owner <> nil) and (Owner is TCustomForm) then
    Exit(TCustomForm(Owner));
  Result := Parent;
end;

procedure TTySizeBox.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  tgt: TControl;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  if not TySizeGripHit(ClientRect, Font.PixelsPerInch, Point(X, Y)) then Exit;
  tgt := ResolveTarget;
  if tgt = nil then Exit;
  FDragging := True;
  FStartW := tgt.Width;
  FStartH := tgt.Height;
  // Screen coords: a stable reference so the resize follows the mouse 1:1 even as the
  // grip (and its container) grows underneath the pointer.
  FMouseStart := ClientToScreen(Point(X, Y));
end;

procedure TTySizeBox.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  tgt: TControl;
  scr: TPoint;
  sz: TSize;
  minW, minH: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  if not FDragging then Exit;
  // If the left button is no longer held (a stolen/missed MouseUp — capture theft, modal, Alt+Tab),
  // stop dragging instead of resizing under a released cursor on later button-less hover moves.
  if not (ssLeft in Shift) then begin FDragging := False; Exit; end;
  tgt := ResolveTarget;
  if tgt = nil then Exit;
  scr := ClientToScreen(Point(X, Y));
  minW := tgt.Constraints.MinWidth;
  minH := tgt.Constraints.MinHeight;
  sz := TySizeApplyDelta(FStartW, FStartH, scr.X - FMouseStart.X, scr.Y - FMouseStart.Y,
    minW, minH);
  // Honour a MaxWidth/MaxHeight constraint too (0 = unbounded).
  if (tgt.Constraints.MaxWidth  > 0) and (sz.cx > tgt.Constraints.MaxWidth)  then sz.cx := tgt.Constraints.MaxWidth;
  if (tgt.Constraints.MaxHeight > 0) and (sz.cy > tgt.Constraints.MaxHeight) then sz.cy := tgt.Constraints.MaxHeight;
  tgt.SetBounds(tgt.Left, tgt.Top, sz.cx, sz.cy);
end;

procedure TTySizeBox.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if (Button = mbLeft) and FDragging then
    FDragging := False;
  inherited MouseUp(Button, Shift, X, Y);
end;

procedure TTySizeBox.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  W, H: Integer;
  dots: TTyRectArray;
  hi, lo: TTyFill;
  seed, hiColor, loColor: TTyColor;
  i: Integer;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    W := ARect.Right - ARect.Left;
    H := ARect.Bottom - ARect.Top;
    // Honour a themed background/border if the (TyPanel) style sets one; default is a
    // surface swatch — the grip reads as part of its container's corner.
    DrawFrame(P, Rect(0, 0, W, H), S);

    // Derive the 3D dot colours from the resolved style — never hard-coded. Seed from
    // the border colour when present (the grip's natural "chrome" line), else the text
    // colour. A raised dot = a light highlight body + a darker shadow offset, exactly
    // like the classic engraved size grip, both blended off the same theme token so a
    // theme switch recolours the grip.
    if tpBorderColor in S.Present then
      seed := S.BorderColor
    else
      seed := S.TextColor;
    hiColor := TyLighten(seed, 55);   // highlight: seed toward white
    loColor := TyDarken(seed, 30);    // shadow: seed toward black

    hi := Default(TTyFill); hi.Kind := tfkSolid; hi.Color := hiColor;
    lo := Default(TTyFill); lo.Kind := tfkSolid; lo.Color := loColor;

    dots := TySizeGripDots(Rect(0, 0, W, H), APPI);
    // Paint the shadow dot first (offset by 1 device px down-right), then the highlight
    // body on top — the offset is what gives each dot its engraved 3D read.
    for i := 0 to High(dots) do
      P.FillBackground(Rect(dots[i].Left + 1, dots[i].Top + 1,
        dots[i].Right + 1, dots[i].Bottom + 1), lo, 0);
    for i := 0 to High(dots) do
      P.FillBackground(dots[i], hi, 0);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTySizeBox.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
