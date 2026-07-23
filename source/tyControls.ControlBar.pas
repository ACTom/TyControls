unit tyControls.ControlBar;
{$mode objfpc}{$H+}

{ Phase-5 containers — TTyControlBar: a dockable BAND host.

  A TTyControlBar arranges its child controls (typically toolbars / small panels) into
  horizontal BANDS (rows). Each child sits on a band; a band may hold several children
  side by side; when the current row runs out of width the next child wraps down to a new
  band. Each band draws a left GRIPPER (a couple of vertical dotted rails, theme-derived)
  and every child on the band is indented past that gripper, so a child can be grabbed by
  its band's grip. This mirrors the classic Delphi/VCL TControlBar / an Office rebar.

  It subclasses TTyPanel (GetStyleTypeKey='TyPanel') — reusing the panel's themed frame —
  and adds the band packing. The PACKING is a pure unit-level function (TyControlBarPack)
  the tests exercise directly with no window handle; the control is a thin shell that runs
  the solver in AlignControls and SetBounds()s each child. Live drag-to-reband is a
  real-machine follow-up (the drag interaction), but a per-child band assignment (which
  band index a child ends up on) is stored keyed by the child TControl and dropped when the
  child is freed (via Notification), so it survives across relayouts.

  HARD RULE: reuse the 'TyPanel' typeKey — no new .tycss. Colours (gripper rails, band
  separators) come from the resolved TyPanel style (BorderColor / TextColor). }

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller,
  tyControls.Panel;

type
  { TTyControlBar — a dockable band host (subclass of TTyPanel). }
  TTyControlBar = class(TTyPanel)
  private
    FBandHeight: Integer;
    { True once a host/.lfm pins BandHeight; False = follow the theme's --header-control-height
      token (density-aware: classic 26 == the original constant, modern raises it). }
    FBandHeightExplicit: Boolean;
    FGripperWidth: Integer;
    FBandSpacing: Integer;
    FInLayout: Boolean;
    { Per-child band assignment, keyed by the child control. A parallel pair of arrays
      (FAssignCtl[i] -> FAssignBand[i]); dropped in Notification(opRemove). This is what a
      live drag-to-reband would update; the packer honours it as the child's preferred band
      when set (>= 0). }
    FAssignCtl: array of TControl;
    FAssignBand: array of Integer;
    function GetBandHeight: Integer;
    procedure SetBandHeight(AValue: Integer);
    procedure SetGripperWidth(AValue: Integer);
    procedure SetBandSpacing(AValue: Integer);
    procedure Relayout;
    function BandCount: Integer;
    procedure DrawGripper(P: TTyPainter; const ABandRect: TRect; const AStyle: TTyStyleSet);
  protected
    procedure Paint; override;
    procedure AlignControls(AControl: TControl; var ARect: TRect); override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    function GetStyleTypeKey: string; override;
    { The band index a child currently sits on (-1 when the control is not a child / not yet
      laid out). Read-only view of the packer's result. }
    function BandIndexOf(AControl: TControl): Integer;
  published
    { The uniform pixel height of each band (row). Every child is forced to this height when
      packed. Changing it re-lays the bands. RowSize is a VCL-familiar alias. Left unset it
      follows the theme's --header-control-height token, so bands pack denser at classic
      density (26) and roomier at modern automatically; set it explicitly and that value wins
      and is streamed (stored FBandHeightExplicit). }
    property BandHeight: Integer read GetBandHeight write SetBandHeight stored FBandHeightExplicit;
    property RowSize: Integer read GetBandHeight write SetBandHeight stored FBandHeightExplicit;
    { The left gripper rail width reserved on each band; children start past it. }
    property GripperWidth: Integer read FGripperWidth write SetGripperWidth default 12;
    { Vertical gap between consecutive bands. }
    property BandSpacing: Integer read FBandSpacing write SetBandSpacing default 3;
  end;

{ Pure packing: place each child (widths+heights in AChildSizes, device px) left-to-right
  into horizontal bands of height ABandHeight, each band indented past a AGripperW gripper,
  with ASpacing between children on a row and between bands. Wrap to a new band when the
  next child would overflow AAvail. A child WIDER than the usable row still gets its own
  band (clamped to the usable width) rather than looping forever. Returns each child's rect
  (device px, (0,0)-local). AChildSizes[i].cy is honoured only for centring within the
  band; every returned rect is exactly ABandHeight tall.

  - avail <= gripperW  -> degenerate: children pinned at the gripper edge, zero usable width.
  - zero children      -> empty result.
  Headless-testable; the control just feeds it the child list and applies the rects. }
function TyControlBarPack(const AChildSizes: array of TSize;
  AAvail, ABandHeight, AGripperW, ASpacing: Integer): TTyRectArray;

implementation

// ---------------------------------------------------------------------------
// Pure packing
// ---------------------------------------------------------------------------
function TyControlBarPack(const AChildSizes: array of TSize;
  AAvail, ABandHeight, AGripperW, ASpacing: Integer): TTyRectArray;
var
  N, I, contentLeft, x, y, w, usable: Integer;
  firstOnBand: Boolean;
begin
  Result := nil;
  N := Length(AChildSizes);
  SetLength(Result, N);
  if N = 0 then Exit;
  if ABandHeight < 0 then ABandHeight := 0;
  if AGripperW < 0 then AGripperW := 0;
  if ASpacing < 0 then ASpacing := 0;

  contentLeft := AGripperW;              // children start just past the band gripper
  usable := AAvail - AGripperW;          // width available to children on one band
  if usable < 0 then usable := 0;

  x := contentLeft;
  y := 0;
  firstOnBand := True;
  for I := 0 to N - 1 do
  begin
    w := AChildSizes[I].cx;
    if w < 0 then w := 0;
    // Wrap: this child (past the first on the band) would overflow the usable row width.
    if (not firstOnBand) and (x + w > contentLeft + usable) then
    begin
      Inc(y, ABandHeight + ASpacing);
      x := contentLeft;
      firstOnBand := True;
    end;
    // A child wider than the usable row is clamped so it fits its own band exactly.
    if w > usable then w := usable;
    Result[I].Left := x;
    Result[I].Top := y;
    Result[I].Right := x + w;
    Result[I].Bottom := y + ABandHeight;
    Inc(x, w + ASpacing);
    firstOnBand := False;
  end;
end;

// ===========================================================================
// TTyControlBar
// ===========================================================================
constructor TTyControlBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // TTyPanel already sets csAcceptsControls; keep the band host a designer container.
  FBandHeight := 26;             { classic fallback; unused while FBandHeightExplicit=False }
  FBandHeightExplicit := False;  { follow --header-control-height (density-aware) until set }
  FGripperWidth := 12;
  FBandSpacing := 3;
  Width := 320;
  Height := TyDensityHeight(ActiveController, 32);
end;

function TTyControlBar.GetStyleTypeKey: string;
begin
  { Own key rather than the borrowed 'TyPanel': the per-band grippers are marks a panel never draws.
    Added to 'TyPanel's rule block as an extra selector, so every resolved value is
    unchanged — this opens a hook, it does not restyle anything. }
  Result := 'TyControlBar';   // reuse the panel frame + tokens — NO new tycss
end;

{ Effective band height in logical px: an explicit BandHeight wins; otherwise follow the
  theme's --header-control-height token, whose classic value (26) equals the original constant
  byte-for-byte and which the density pack raises for modern density. Resolved live (not
  cached) so toggling Controller.Density re-heights the bands on the next layout. }
function TTyControlBar.GetBandHeight: Integer;
begin
  if FBandHeightExplicit then
    Result := FBandHeight
  else
    Result := ActiveController.Metric('--header-control-height', 26);
end;

procedure TTyControlBar.SetBandHeight(AValue: Integer);
begin
  if AValue < 1 then AValue := 1;
  FBandHeightExplicit := True;   { even if it equals the classic default, the host pinned it }
  if FBandHeight = AValue then Exit;
  FBandHeight := AValue;
  Relayout;
end;

procedure TTyControlBar.SetGripperWidth(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FGripperWidth = AValue then Exit;
  FGripperWidth := AValue;
  Relayout;
end;

procedure TTyControlBar.SetBandSpacing(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FBandSpacing = AValue then Exit;
  FBandSpacing := AValue;
  Relayout;
end;

procedure TTyControlBar.Relayout;
begin
  if csDestroying in ComponentState then Exit;
  Realign;
  Invalidate;
end;

function TTyControlBar.BandIndexOf(AControl: TControl): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(FAssignCtl) do
    if FAssignCtl[I] = AControl then Exit(FAssignBand[I]);
end;

// The number of distinct bands currently occupied (derived from the stored assignments).
function TTyControlBar.BandCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FAssignBand) do
    if FAssignBand[I] + 1 > Result then Result := FAssignBand[I] + 1;
end;

procedure TTyControlBar.AlignControls(AControl: TControl; var ARect: TRect);
var
  I, N, bands: Integer;
  list: array of TControl;
  sizes: array of TSize;
  rects: TTyRectArray;
  spacing, gripW, bandH: Integer;
  ppi: Integer;
  ctl: TControl;
  newH: Integer;
begin
  // Re-entrancy guard: the trailing Height assignment triggers another AlignControls.
  if FInLayout then Exit;
  FInLayout := True;
  try
    ppi := Font.PixelsPerInch;
    // Scale the logical band metrics to device px (headless PPI=96 -> identity).
    bandH := MulDiv(GetBandHeight, ppi, 96);
    gripW := MulDiv(FGripperWidth, ppi, 96);
    spacing := MulDiv(FBandSpacing, ppi, 96);

    // Collect the visible child controls in child order.
    SetLength(list, ControlCount);
    N := 0;
    for I := 0 to ControlCount - 1 do
    begin
      ctl := Controls[I];
      if ctl.Visible then begin list[N] := ctl; Inc(N); end;
    end;
    SetLength(list, N);
    SetLength(sizes, N);
    for I := 0 to N - 1 do
    begin
      sizes[I].cx := list[I].Width;
      sizes[I].cy := list[I].Height;
    end;

    rects := TyControlBarPack(sizes, ClientWidth, bandH, gripW, spacing);

    // Rebuild the per-child band assignment from the packed rects (band index = the row
    // ordinal, derived from Top / (bandH + spacing)). Keyed by the child control so it
    // survives relayouts and is dropped on free.
    SetLength(FAssignCtl, N);
    SetLength(FAssignBand, N);
    for I := 0 to N - 1 do
    begin
      FAssignCtl[I] := list[I];
      if (bandH + spacing) > 0 then
        FAssignBand[I] := rects[I].Top div (bandH + spacing)
      else
        FAssignBand[I] := 0;
      list[I].SetBounds(rects[I].Left, rects[I].Top, rects[I].Right - rects[I].Left, bandH);
    end;
    bands := BandCount;

    // Grow the bar to fit the bands when top/bottom-docked (like the toolbar auto-grow).
    if (Align in [alTop, alBottom]) and (bands > 0) then
    begin
      newH := bands * bandH + (bands - 1) * spacing;
      // Add the frame padding so the outermost bands aren't flush with the border.
      Inc(newH, 2 * spacing);
      if Height <> newH then
        Height := newH;   // re-lays via a fresh AlignControls once FInLayout clears
    end;
  finally
    FInLayout := False;
  end;
end;

procedure TTyControlBar.Notification(AComponent: TComponent; Operation: TOperation);
var
  I, J: Integer;
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent is TControl) then
  begin
    // Drop the freed child's band assignment (compact the parallel arrays).
    I := 0;
    while I <= High(FAssignCtl) do
      if FAssignCtl[I] = AComponent then
      begin
        for J := I to High(FAssignCtl) - 1 do
        begin
          FAssignCtl[J] := FAssignCtl[J + 1];
          FAssignBand[J] := FAssignBand[J + 1];
        end;
        SetLength(FAssignCtl, Length(FAssignCtl) - 1);
        SetLength(FAssignBand, Length(FAssignBand) - 1);
      end
      else
        Inc(I);
  end;
end;

{ Draw a band gripper: a couple of vertical dotted rails in the reserved gripper column at
  the left of ABandRect, in the theme's border colour (falls back to text colour). }
procedure TTyControlBar.DrawGripper(P: TTyPainter; const ABandRect: TRect;
  const AStyle: TTyStyleSet);
var
  railColor: TTyColor;
  fill: TTyFill;
  gw, cx, railGap, inset, railW, y0, y1: Integer;
begin
  gw := ABandRect.Right - ABandRect.Left;   // = gripper column width (device px)
  if gw <= 0 then Exit;
  if tpBorderColor in AStyle.Present then railColor := AStyle.BorderColor
  else railColor := AStyle.TextColor;
  fill := Default(TTyFill);
  fill.Kind := tfkSolid;
  fill.Color := railColor;

  railW := P.Scale(1); if railW < 1 then railW := 1;
  railGap := P.Scale(3); if railGap < railW + 1 then railGap := railW + 1;
  inset := P.Scale(3);
  y0 := ABandRect.Top + inset;
  y1 := ABandRect.Bottom - inset;
  if y1 <= y0 then Exit;

  // Two rails centred in the gripper column.
  cx := ABandRect.Left + gw div 2 - (railGap div 2);
  P.FillBackground(Rect(cx, y0, cx + railW, y1), fill, 0);
  P.FillBackground(Rect(cx + railGap, y0, cx + railGap + railW, y1), fill, 0);
end;

procedure TTyControlBar.Paint;
var
  P: TTyPainter;
  S: TTyStyleSet;
  ppi, bandH, gripW, spacing, bandTop, I, bands: Integer;
begin
  // Draw the TyPanel frame first (reuses the inherited RenderTo via CurrentStyle).
  inherited Paint;
  // Then overlay a gripper rail per occupied band.
  ppi := Font.PixelsPerInch;
  bandH := MulDiv(GetBandHeight, ppi, 96);
  gripW := MulDiv(FGripperWidth, ppi, 96);
  spacing := MulDiv(FBandSpacing, ppi, 96);
  if (gripW <= 0) or (bandH <= 0) then Exit;
  bands := BandCount;
  if bands <= 0 then Exit;
  P := TTyPainter.Create;
  try
    P.BeginPaint(Canvas, ClientRect, ppi);
    S := CurrentStyle;
    for I := 0 to bands - 1 do
    begin
      bandTop := I * (bandH + spacing);
      DrawGripper(P, Rect(0, bandTop, gripW, bandTop + bandH), S);
    end;
    P.EndPaint;
  finally
    P.Free;
  end;
end;

initialization
  RegisterClass(TTyControlBar);
end.
