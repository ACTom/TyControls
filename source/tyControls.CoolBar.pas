unit tyControls.CoolBar;
{$mode objfpc}{$H+}

{ Phase-5 (containers) — TTyCoolBar: a REBAR band container.

  TTyCoolBar SUBCLASSES TTyControlBar (the band-packing base, built the same batch;
  GetStyleTypeKey='TyPanel' — NO new .tycss). TTyControlBar already packs each child
  control onto a horizontal band with a left gripper; TTyCoolBar upgrades every band so
  it can be:

    * MOVED   — grab a band's gripper and drag it DOWN to give the band a row of its own,
                or UP to return it to the row above. Every band has its own gripper, drawn
                immediately to its left, so every band can be grabbed.
    * RESIZED — grab that gripper and drag HORIZONTALLY to widen/narrow the band, honouring
                a per-band minimum / maximum width.

    The pointer's direction picks between the two (TyCoolDragMode), as it does in Delphi's and
    Lazarus's TCoolBar.

    NOT implemented: reordering bands WITHIN a row. That needs a child-index primitive and the
    LCL exposes only SetZOrder(TopMost), so a control cannot be placed at an arbitrary position
    in its parent's list. Row membership is the whole of the model for now.

  Per-band metadata (a fixed/min Width the band is given) is stored keyed by the child
  TControl in FBands and dropped when the child is freed (Notification/opRemove) — never
  a parallel array indexed by position, which would desync the moment a band is removed.

  The DRAG ITSELF (mouse capture, live reorder animation) is real-machine; the two bits
  of math it needs are PURE unit-level functions exercised headlessly with no window:

    TyCoolBandResize(AStartW, ADx, AMinW, AMaxW) : Integer    // clamped new band width
    TyCoolGripperHit(ABandRect, AGripperW, APt) : Boolean     // is APt on the gripper?

  IMPORTANT (controller integration): this unit codes against TTyControlBar's PUBLIC
  contract as described — a csAcceptsControls band-packing container with per-band
  grippers and a keyed per-child band assignment. The one protected hook it would like
  the base to expose is the DEVICE-PX RECT of a band (so a gripper hit-test and the
  resize origin can reuse the base's own packing geometry instead of recomputing it).
  Until the base exposes that, TTyCoolBar computes a band rect itself from the child's
  BoundsRect (see BandRectFor) — see the summary note. }

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.ControlBar;

type
  { One band's per-child metadata, keyed by the child control (position-independent). }
  { What a gripper drag means once the pointer commits to an axis. }
  TTyCoolDrag = (cdNone, cdMove, cdResize);

  TTyCoolBand = record
    Ctl: TControl;      // the hosted child this band wraps
    Width: Integer;     // the band's assigned/min logical width (0 = auto = child.Width)
    MinWidth: Integer;  // clamp floor for a gripper resize (logical px)
    MaxWidth: Integer;  // clamp ceiling for a gripper resize (0 = unbounded)
    Break_: Boolean;    // start a new row at this band, even when it would fit on the current
    Text_: string;      // the band's own caption, drawn between its gripper and its child
    FixedSize: Boolean; // the band refuses a gripper resize (it may still be MOVED)
  end;

  TTyCoolBar = class(TTyControlBar)
  private
    FBands: array of TTyCoolBand;      // per-child band metadata, keyed by Ctl
    FDefaultBandMinWidth: Integer;     // fallback min when a band has none of its own
    FDragStartY: Integer;
    FDragMode: TTyCoolDrag;
    FShowText: Boolean;
    FOnChange: TNotifyEvent;
    // --- live drag state (real-machine) ---
    FDragging: Boolean;
    FDragCtl: TControl;                // the band being resized
    FDragStartX: Integer;             // mouse X (device px) at grab
    FDragStartW: Integer;             // the band's logical width at grab
    function BandTextWidth(const AText: string; const AStyle: TTyStyleSet): Integer;
    procedure SetShowText(AValue: Boolean);
    procedure Changed;
    function IndexOfBand(ACtl: TControl): Integer;
    function EnsureBand(ACtl: TControl): Integer;   // find, or create, this child's band record
    function BandAtPoint(AX, AY: Integer): TControl;   // the band whose gripper is under (X,Y)
  protected
    function GetStyleTypeKey: string; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    { The device-px rect of ACtl's band. Derived from the child's current BoundsRect
      grown left by the gripper strip (so the gripper column is part of the band). If a
      future TTyControlBar exposes a real per-band rect, override/redirect here. }
    function BandRectFor(ACtl: TControl): TRect; virtual;
    function PackBands(const ABands: array of TControl; const ASizes: array of TSize;
      AAvail, ABandHeight, AGripperW, ASpacing: Integer): TTyRectArray; override;
    procedure PaintGrippers(APainter: TTyPainter; const AStyle: TTyStyleSet;
      ABandCount, ABandHeight, AGripperW, ASpacing: Integer); override;
    { The device-px width of the gripper strip at this control's PPI. }
    function GripperWidthPx: Integer;
  public
    constructor Create(AOwner: TComponent); override;
    { Assign / query a band's fixed-or-min width (logical px). Setting it re-lays the
      bands (via the inherited container relayout). AWidth <= 0 clears it (auto). The
      value is keyed by the child, so it survives reorders and other bands' removal. }
    procedure SetBandWidth(ACtl: TControl; AWidth: Integer);
    function GetBandWidth(ACtl: TControl): Integer;
    { Per-band resize clamps (logical px). AMax = 0 means unbounded. }
    procedure SetBandMinWidth(ACtl: TControl; AMinWidth: Integer);
    procedure SetBandMaxWidth(ACtl: TControl; AMaxWidth: Integer);
    function BandMinWidth(ACtl: TControl): Integer;
    function BandMaxWidth(ACtl: TControl): Integer;
    { A band with Break starts a new row even when it would fit on the current one -- what
      dragging a band downward sets, and what Delphi's TCoolBand.Break means. Inert on the
      first band: there is no row above it to leave. }
    procedure SetBandBreak(ACtl: TControl; AValue: Boolean);
    function BandBreak(ACtl: TControl): Boolean;
    { The band's own caption. Drawn between the gripper and the child when ShowText is on, and
      the packer reserves room for it there -- a rebar band labels itself rather than relying on
      whatever control happens to be inside it. }
    procedure SetBandText(ACtl: TControl; const AValue: string);
    function BandText(ACtl: TControl): string;
    { A fixed band refuses a gripper RESIZE. It can still be moved between rows: fixing a size
      is not the same as nailing a band down. }
    procedure SetBandFixedSize(ACtl: TControl; AValue: Boolean);
    function BandFixedSize(ACtl: TControl): Boolean;
    { Show or hide one band. The hosted child's own Visible is the single source of truth, so
      the packer, the hit-test and the painter cannot disagree about it. }
    procedure SetBandVisible(ACtl: TControl; AValue: Boolean);
    function BandVisible(ACtl: TControl): Boolean;
  published
    // GripperWidth is INHERITED from TTyControlBar (same field the band packing uses) — do NOT
    // redeclare it here, or the base would pack with one width while our hit-test used another.
    { Fallback resize floor for a band that has no MinWidth of its own (logical px). }
    property DefaultBandMinWidth: Integer read FDefaultBandMinWidth write FDefaultBandMinWidth default 24;
    { Draw each band's own caption between its gripper and its child, reserving room for it. }
    property ShowText: Boolean read FShowText write SetShowText default False;
    { Fired after the band layout changes -- a band moved to another row, resized, or hidden. }
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

{ ------------------------------------------------------------------------------
  PURE, headless-tested band math (no window handle needed)
  ------------------------------------------------------------------------------ }

{ The new band width after dragging its gripper by ADx (device or logical px — the
  caller keeps units consistent) from a starting width AStartW, clamped to
  [AMinW .. AMaxW]. A non-positive AMaxW means "unbounded" (only the floor applies).
  AMinW is floored at 1 so a band never collapses to nothing. }
{ Pack COOLBAR bands: unlike a ControlBar's one-gripper-per-row, every band carries its own
  gripper immediately to its left -- that is what makes a band individually grabbable, and it is
  what Delphi's and Lazarus's TCoolBar draw. A band starts a new row when its Break flag says so,
  or when it would not fit on the current one.

  ABreaks is parallel to AChildSizes; a missing entry reads as False. ALeadExtra is likewise
  parallel and is the width reserved between a band's gripper and its child -- the band's own
  caption when ShowText is on; a missing entry reads as 0. Returns the CHILD rects
  (the band minus its gripper), so the gripper for band i is the AGripperW-wide strip immediately
  left of Result[i]. Pure: no control, no canvas, no PPI -- device px in, device px out. }
function TyCoolBarPack(const AChildSizes: array of TSize; const ABreaks: array of Boolean;
  const ALeadExtra: array of Integer;
  AAvail, ABandHeight, AGripperW, ASpacing: Integer): TTyRectArray;

{ What a gripper drag MEANS, from the travel so far. A CoolBar grip does two jobs and the
  pointer's direction picks between them -- the same disambiguation Delphi's and Lazarus's
  TCoolBar use. Below the threshold the drag is still undecided, so a twitch does neither.
  Pure so the rule is testable without a mouse. }
function TyCoolDragMode(ADx, ADy, AThreshold: Integer): TTyCoolDrag;

function TyCoolBandResize(AStartW, ADx, AMinW, AMaxW: Integer): Integer;

{ True when APt lies on the gripper strip of ABandRect: the leftmost AGripperW px
  column of the band (device px). AGripperW <= 0 -> no gripper -> always False. The
  test is half-open on the right edge (Left .. Left+AGripperW), inclusive on top,
  exclusive on bottom — matching LCL hit-testing. }
function TyCoolGripperHit(const ABandRect: TRect; AGripperW: Integer; const APt: TPoint): Boolean;

implementation

// -----------------------------------------------------------------------------
// Pure functions
// -----------------------------------------------------------------------------
function TyCoolBarPack(const AChildSizes: array of TSize; const ABreaks: array of Boolean;
  const ALeadExtra: array of Integer;
  AAvail, ABandHeight, AGripperW, ASpacing: Integer): TTyRectArray;
var
  n, i, x, y, w, rowStart, lead: Integer;
  brk, firstOnRow: Boolean;
begin
  Result := nil;
  n := Length(AChildSizes);
  SetLength(Result, n);
  if n = 0 then Exit;
  if ABandHeight < 0 then ABandHeight := 0;
  if AGripperW < 0 then AGripperW := 0;
  if ASpacing < 0 then ASpacing := 0;

  x := 0;
  y := 0;
  firstOnRow := True;
  for i := 0 to n - 1 do
  begin
    w := AChildSizes[i].cx;
    if w < 0 then w := 0;
    brk := (i < Length(ABreaks)) and ABreaks[i];
    lead := AGripperW;
    if (i < Length(ALeadExtra)) and (ALeadExtra[i] > 0) then Inc(lead, ALeadExtra[i]);
    { A break is honoured even for a band that would have fitted -- that is the whole point of
      dragging a band onto a row of its own. The first band can never break: there is no row
      above it to leave. }
    if (not firstOnRow) and (brk or (x + lead + w > AAvail)) then
    begin
      Inc(y, ABandHeight + ASpacing);
      x := 0;
      firstOnRow := True;
    end;
    rowStart := x + lead;                 // the child begins after its gripper (and caption)
    if rowStart + w > AAvail then         // a band wider than the row is clamped to it
      w := AAvail - rowStart;
    if w < 0 then w := 0;
    Result[i].Left := rowStart;
    Result[i].Top := y;
    Result[i].Right := rowStart + w;
    Result[i].Bottom := y + ABandHeight;
    x := rowStart + w + ASpacing;
    firstOnRow := False;
  end;
end;

function TyCoolDragMode(ADx, ADy, AThreshold: Integer): TTyCoolDrag;
begin
  if AThreshold < 1 then AThreshold := 1;
  { Vertical wins ties-with-intent: a band is MOVED between rows far more often than it is
    resized, and a horizontal wobble during a downward drag must not flip the meaning. }
  if (Abs(ADy) >= AThreshold) and (Abs(ADy) > Abs(ADx)) then
    Result := cdMove
  else if Abs(ADx) >= AThreshold then
    Result := cdResize
  else
    Result := cdNone;
end;

function TyCoolBandResize(AStartW, ADx, AMinW, AMaxW: Integer): Integer;
begin
  if AMinW < 1 then AMinW := 1;
  Result := AStartW + ADx;
  if Result < AMinW then Result := AMinW;
  // A non-positive ceiling means unbounded; otherwise clamp (and never below the floor).
  if AMaxW > 0 then
  begin
    if AMaxW < AMinW then AMaxW := AMinW;   // an inverted range collapses to the floor
    if Result > AMaxW then Result := AMaxW;
  end;
end;

function TyCoolGripperHit(const ABandRect: TRect; AGripperW: Integer; const APt: TPoint): Boolean;
begin
  if AGripperW <= 0 then Exit(False);
  Result :=
    (APt.X >= ABandRect.Left) and (APt.X < ABandRect.Left + AGripperW) and
    (APt.Y >= ABandRect.Top)  and (APt.Y < ABandRect.Bottom);
end;

// =============================================================================
// TTyCoolBar
// =============================================================================
constructor TTyCoolBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // The base already sets csAcceptsControls; a rebar hosts arbitrary band content.
  GripperWidth := 10;   // inherited property (the base packs with the same value we hit-test)
  FDefaultBandMinWidth := 24;
  FDragging := False;
  FDragCtl := nil;
end;

function TTyCoolBar.GetStyleTypeKey: string;
begin
  { Own key rather than the borrowed 'TyPanel': same as its TTyControlBar ancestor — band grippers are not panel chrome.
    Added to 'TyPanel's rule block as an extra selector, so every resolved value is
    unchanged — this opens a hook, it does not restyle anything. }
  Result := 'TyCoolBar';
end;

function TTyCoolBar.GripperWidthPx: Integer;
begin
  Result := MulDiv(GripperWidth, Font.PixelsPerInch, 96);   // inherited from TTyControlBar
  if Result < 0 then Result := 0;
end;

function TTyCoolBar.IndexOfBand(ACtl: TControl): Integer;
var
  i: Integer;
begin
  Result := -1;
  if ACtl = nil then Exit;
  for i := 0 to High(FBands) do
    if FBands[i].Ctl = ACtl then Exit(i);
end;

function TTyCoolBar.EnsureBand(ACtl: TControl): Integer;
begin
  { Band metadata used to spring into existence only when a WIDTH was assigned, so setting any
    other band property on a band nobody had sized yet silently did nothing. Every setter goes
    through here instead. }
  Result := -1;
  if ACtl = nil then Exit;
  Result := IndexOfBand(ACtl);
  if Result >= 0 then Exit;
  SetLength(FBands, Length(FBands) + 1);
  Result := High(FBands);
  FBands[Result].Ctl := ACtl;
  FBands[Result].MinWidth := 0;
  FBands[Result].MaxWidth := 0;
end;

procedure TTyCoolBar.SetBandWidth(ACtl: TControl; AWidth: Integer);
var
  idx: Integer;
begin
  if ACtl = nil then Exit;
  if AWidth < 0 then AWidth := 0;
  idx := EnsureBand(ACtl);
  if idx < 0 then Exit;
  FBands[idx].Width := AWidth;
  // A given width should be honoured as the child's actual width; the base packs from
  // the child bounds, so set the child width too (auto = leave it as-is).
  if (AWidth > 0) and (ACtl.Width <> AWidth) then
    ACtl.Width := AWidth;
  Realign;
  Changed;
end;

function TTyCoolBar.GetBandWidth(ACtl: TControl): Integer;
var
  idx: Integer;
begin
  idx := IndexOfBand(ACtl);
  if idx >= 0 then Result := FBands[idx].Width else Result := 0;
end;

procedure TTyCoolBar.SetBandMinWidth(ACtl: TControl; AMinWidth: Integer);
var
  idx: Integer;
begin
  if ACtl = nil then Exit;
  if AMinWidth < 0 then AMinWidth := 0;
  idx := IndexOfBand(ACtl);
  if idx < 0 then
  begin
    SetLength(FBands, Length(FBands) + 1);
    idx := High(FBands);
    FBands[idx].Ctl := ACtl;
    FBands[idx].Width := 0;
    FBands[idx].MaxWidth := 0;
  end;
  FBands[idx].MinWidth := AMinWidth;
end;

procedure TTyCoolBar.SetBandMaxWidth(ACtl: TControl; AMaxWidth: Integer);
var
  idx: Integer;
begin
  if ACtl = nil then Exit;
  if AMaxWidth < 0 then AMaxWidth := 0;
  idx := IndexOfBand(ACtl);
  if idx < 0 then
  begin
    SetLength(FBands, Length(FBands) + 1);
    idx := High(FBands);
    FBands[idx].Ctl := ACtl;
    FBands[idx].Width := 0;
    FBands[idx].MinWidth := 0;
  end;
  FBands[idx].MaxWidth := AMaxWidth;
end;

function TTyCoolBar.BandMinWidth(ACtl: TControl): Integer;
var
  idx: Integer;
begin
  idx := IndexOfBand(ACtl);
  if (idx >= 0) and (FBands[idx].MinWidth > 0) then
    Result := FBands[idx].MinWidth
  else
    Result := FDefaultBandMinWidth;
  if Result < 1 then Result := 1;
end;

function TTyCoolBar.BandMaxWidth(ACtl: TControl): Integer;
var
  idx: Integer;
begin
  idx := IndexOfBand(ACtl);
  if idx >= 0 then Result := FBands[idx].MaxWidth else Result := 0;   // 0 = unbounded
end;

function TTyCoolBar.BandRectFor(ACtl: TControl): TRect;
var
  gw: Integer;
begin
  // The base (TTyControlBar) reserves + draws ONE gripper per band-ROW, at the row's left edge
  // (x = 0..gw). So only the row's FIRST child — the one placed at Left = gw (the content-left
  // after that single gripper) — is a resize target; a child packed further right on the same row
  // shares no gripper and must NOT be grippable (else its hit-zone is a phantom strip with nothing
  // drawn, resizing the wrong band). Return the real row-left gripper rect for a first child, else
  // an empty rect. Device px, control-local.
  if ACtl = nil then Exit(Rect(0, 0, 0, 0));
  gw := GripperWidthPx;
  if gw <= 0 then Exit(Rect(0, 0, 0, 0));
  { EVERY band has its own gripper, immediately to its left -- the packer reserves it there.
    The old rule returned an empty rect for anything that was not the row's first child, which
    is a ControlBar's one-grip-per-row model: band 2 had no handle to grab and none drawn. }
  Result := ACtl.BoundsRect;
  Result.Right := Result.Left;
  Dec(Result.Left, gw);
  if Result.Left < 0 then Result.Left := 0;
end;

procedure TTyCoolBar.SetBandBreak(ACtl: TControl; AValue: Boolean);
var i: Integer;
begin
  i := EnsureBand(ACtl);
  if i < 0 then Exit;
  if FBands[i].Break_ = AValue then Exit;
  FBands[i].Break_ := AValue;
  Relayout;
  Changed;
end;

function TTyCoolBar.BandBreak(ACtl: TControl): Boolean;
var i: Integer;
begin
  i := IndexOfBand(ACtl);
  Result := (i >= 0) and FBands[i].Break_;
end;

procedure TTyCoolBar.SetBandText(ACtl: TControl; const AValue: string);
var i: Integer;
begin
  i := EnsureBand(ACtl);
  if i < 0 then Exit;
  if FBands[i].Text_ = AValue then Exit;
  FBands[i].Text_ := AValue;
  Relayout;
  Changed;
end;

function TTyCoolBar.BandText(ACtl: TControl): string;
var i: Integer;
begin
  i := IndexOfBand(ACtl);
  if i >= 0 then Result := FBands[i].Text_ else Result := '';
end;

procedure TTyCoolBar.SetBandFixedSize(ACtl: TControl; AValue: Boolean);
var i: Integer;
begin
  i := EnsureBand(ACtl);
  if i < 0 then Exit;
  FBands[i].FixedSize := AValue;
end;

function TTyCoolBar.BandFixedSize(ACtl: TControl): Boolean;
var i: Integer;
begin
  i := IndexOfBand(ACtl);
  Result := (i >= 0) and FBands[i].FixedSize;
end;

procedure TTyCoolBar.SetBandVisible(ACtl: TControl; AValue: Boolean);
begin
  { The child's Visible IS the band's visibility -- the packer already skips invisible children,
    so there is no second flag to fall out of step with it. }
  if (ACtl = nil) or (ACtl.Visible = AValue) then Exit;
  ACtl.Visible := AValue;
  Relayout;
  Changed;
end;

function TTyCoolBar.BandVisible(ACtl: TControl): Boolean;
begin
  Result := (ACtl <> nil) and ACtl.Visible;
end;

{ Measure a band caption on a scratch canvas -- the pattern TTyCustomTabStrip and TTyGroupBox
  use, so CJK and variable-width fonts measure correctly with no window. }
function TTyCoolBar.BandTextWidth(const AText: string; const AStyle: TTyStyleSet): Integer;
var
  bmp: TBitmap;
begin
  Result := 0;
  if (AText = '') or (not FShowText) then Exit;
  bmp := TBitmap.Create;
  try
    bmp.SetSize(1, 1);
    bmp.Canvas.Font.Name := TyEffectiveFontName(AStyle.FontName);
    bmp.Canvas.Font.Size := MulDiv(ResolveFontSize(AStyle), Font.PixelsPerInch, 96);
    Result := bmp.Canvas.TextWidth(AText);
  finally
    bmp.Free;
  end;
  if Result > 0 then Inc(Result, MulDiv(8, Font.PixelsPerInch, 96));   // a gap before the child
end;

procedure TTyCoolBar.SetShowText(AValue: Boolean);
begin
  if FShowText = AValue then Exit;
  FShowText := AValue;
  Relayout;   // the caption strip is packed, so turning it on/off moves every band
end;

procedure TTyCoolBar.Changed;
begin
  if Assigned(FOnChange) then FOnChange(Self);
end;

function TTyCoolBar.PackBands(const ABands: array of TControl; const ASizes: array of TSize;
  AAvail, ABandHeight, AGripperW, ASpacing: Integer): TTyRectArray;
var
  brks: array of Boolean;
  leads: array of Integer;
  S: TTyStyleSet;
  i, bi: Integer;
begin
  { Every band carries its own gripper, and a band may force a row break -- the two things
    that make a CoolBar a CoolBar rather than a ControlBar. }
  SetLength(brks, Length(ABands));
  SetLength(leads, Length(ABands));
  S := CurrentStyle;
  for i := 0 to High(ABands) do
  begin
    bi := IndexOfBand(ABands[i]);
    brks[i] := (bi >= 0) and FBands[bi].Break_;
    if bi >= 0 then leads[i] := BandTextWidth(FBands[bi].Text_, S) else leads[i] := 0;
  end;
  Result := TyCoolBarPack(ASizes, brks, leads, AAvail, ABandHeight, AGripperW, ASpacing);
end;

procedure TTyCoolBar.PaintGrippers(APainter: TTyPainter; const AStyle: TTyStyleSet;
  ABandCount, ABandHeight, AGripperW, ASpacing: Integer);
var
  i, bi: Integer;
  ctl: TControl;
  r: TRect;
begin
  { One gripper per BAND, drawn immediately left of the child it belongs to -- not one per row.
    Band 2 having no handle at all was this loop inherited unchanged from the base. }
  for i := 0 to ControlCount - 1 do
  begin
    ctl := Controls[i];
    if (ctl = nil) or (not ctl.Visible) then Continue;
    r := BandRectFor(ctl);
    if r.Right > r.Left then DrawGripper(APainter, r, AStyle);
    if FShowText then
    begin
      bi := IndexOfBand(ctl);
      if (bi >= 0) and (FBands[bi].Text_ <> '') then
        { Between the gripper and the child -- the strip PackBands reserved for exactly this. }
        APainter.DrawText(Rect(r.Right, r.Top, ctl.Left, r.Bottom), FBands[bi].Text_,
          AStyle.FontName, ResolveFontSize(AStyle), AStyle.FontWeight, AStyle.TextColor,
          taLeftJustify, tlCenter, True);
    end;
  end;
end;

function TTyCoolBar.BandAtPoint(AX, AY: Integer): TControl;
var
  i: Integer;
  ctl: TControl;
  gw: Integer;
  r: TRect;
begin
  Result := nil;
  gw := GripperWidthPx;
  if gw <= 0 then Exit;
  for i := 0 to ControlCount - 1 do
  begin
    ctl := Controls[i];
    if (ctl = nil) or not ctl.Visible then Continue;
    r := BandRectFor(ctl);
    if TyCoolGripperHit(r, gw, Point(AX, AY)) then Exit(ctl);
  end;
end;

procedure TTyCoolBar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  hit: TControl;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  hit := BandAtPoint(X, Y);
  if hit = nil then Exit;
  // Begin a gripper drag: remember the band + the starting width so MouseMove can apply
  // the clamped resize. (Reorder-vs-resize disambiguation by drag direction is a
  // real-machine refinement; the resize math is what we test.)
  FDragging := True;
  FDragCtl := hit;
  FDragStartX := X;
  FDragStartY := Y;
  FDragMode := cdNone;   // undecided until the pointer commits to an axis
  if GetBandWidth(hit) > 0 then
    FDragStartW := GetBandWidth(hit)
  else
    FDragStartW := hit.Width;
end;

procedure TTyCoolBar.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  dxLogical, newW, minW, maxW, ppi, step, curRow, wantRow: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  if not (FDragging and (FDragCtl <> nil)) then Exit;
  ppi := Font.PixelsPerInch;
  if FDragMode = cdNone then
    FDragMode := TyCoolDragMode(X - FDragStartX, Y - FDragStartY, MulDiv(4, ppi, 96));

  case FDragMode of
    cdResize:
      begin
        if BandFixedSize(FDragCtl) then Exit;   // fixed: the drag simply does nothing
        // Device-px delta -> logical (band widths are logical), clamped, then applied; the
        // base re-packs from the child width.
        dxLogical := MulDiv(X - FDragStartX, 96, ppi);
        minW := BandMinWidth(FDragCtl);
        maxW := BandMaxWidth(FDragCtl);
        newW := TyCoolBandResize(FDragStartW, dxLogical, minW, maxW);
        if newW <> GetBandWidth(FDragCtl) then
          SetBandWidth(FDragCtl, newW);
      end;
    cdMove:
      begin
        { Which row the pointer is over, versus which row the band is on. Moving DOWN gives the
          band a row of its own (Break); moving back UP returns it to the row above. That is the
          whole of the row model -- a band either starts a row or continues one.

          Reordering WITHIN a row is deliberately not attempted: it needs a child-index
          primitive, and the LCL exposes only SetZOrder(TopMost), so there is no way to place a
          control at an arbitrary position in its parent's list. }
        step := MulDiv(BandHeight, ppi, 96) + MulDiv(BandSpacing, ppi, 96);
        if step <= 0 then Exit;
        curRow := FDragCtl.Top div step;
        wantRow := Y div step;
        if wantRow < 0 then wantRow := 0;
        if wantRow > curRow then SetBandBreak(FDragCtl, True)
        else if wantRow < curRow then SetBandBreak(FDragCtl, False);
      end;
  end;
end;

procedure TTyCoolBar.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FDragging := False;
    FDragCtl := nil;
    FDragMode := cdNone;
  end;
end;

procedure TTyCoolBar.Notification(AComponent: TComponent; Operation: TOperation);
var
  idx, j: Integer;
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent is TControl) then
  begin
    // Drop the freed child's band metadata (keyed by control, never by position).
    idx := IndexOfBand(TControl(AComponent));
    if idx >= 0 then
    begin
      for j := idx to High(FBands) - 1 do
        FBands[j] := FBands[j + 1];
      SetLength(FBands, Length(FBands) - 1);
    end;
    if FDragCtl = AComponent then
    begin
      FDragging := False;
      FDragCtl := nil;
    end;
  end;
end;

initialization
  RegisterClass(TTyCoolBar);
end.
