unit tyControls.AdvanceChart.DirtyRect;
{$mode objfpc}{$H+}
{ TTyAdvanceChart -- the coarse pointer and the dirty-rectangle repaint, as
  zrender does them. [Batch 142, D9]

  THE COARSE POINTER (Handler.findHover). When the pointer finds no target
  and the handler has a pointer size, every element of the display list --
  top first, not ignored, not marked ignoreCoarsePointer -- whose box meets
  the pointer's square (size wide, centred on the pointer) is a candidate.
  Then the samples: r = 0, 4, 8, ... while r < size / 2; for each r,
  theta = 0, PI / 12, ... while theta < 2 PI, ACCUMULATED with += (it stays
  below 2 PI after 24 steps, so a ring has 25 samples and ring 0 asks the
  same point 25 times); at each sample the candidates are walked from the
  END of the array -- the bottom one first -- and the first that contains
  the sample is the target. The init options: useCoarsePointer 'auto'
  (the default: the browser's touch events), true or false; pointerSize
  defaults to 44 and is tested for truthiness, so 0 is off. Large batches
  set ignoreCoarsePointer.

  THE DIRTY RECTANGLES (canvas/Layer.createRepaintRects). For each element
  of this frame's list: the previous paint rect joins the pool when it was
  rendered and is dirty or no longer to be painted; the current one when it
  is to be painted and is dirty or was not rendered. Then every element of
  the previous list that is no longer to be painted, or no longer in the
  storage, but was rendered: its previous rect. A rect joins only when
  finite and not zero. The pool: a rect merges into the FIRST rect it meets
  (touching counts); once the pool holds maxRepaintRectCount (5) rects it
  is full, and from then on a rect also merges into the rect whose union
  grows least -- upstream does that even after merging it into the one it
  met, and so does this; otherwise it starts a rect of its own. Last, rects
  that meet are merged until none do. getPaintRect: the box grown by the
  shadow, then floor(x - tolerance), floor(y - tolerance),
  ceil(width + 1 + 2 tolerance), ceil(height + 1 + 2 tolerance) unless the
  box is zero; tolerance is 10 for text, else 0.

  WHAT THE CONTROL ADDS around these two transcriptions, and why it is not
  upstream's: the element's box is the port's own (TyElementPaintRect) --
  it must hold every pixel the port's renderer can put down, and the port
  draws strokes with miter joins and text with halos where zrender's box
  is the path's -- and an element's previous rect is recorded on EVERY
  paint, where upstream records it only while repainting in rects (a full
  paint leaves it unset, so an element moved after one leaves its old
  pixels behind; the fixture's move-after-full case shows upstream doing
  it). A changed element is one whose record differs in any field
  (TyElementsSame, by RTTI): zrender's REDRAW_BIT is set by whoever changes
  the element, and the port's elements are records rebuilt every frame.

  PURE apart from BGRABitmap for the ink scan: no LCL, no painter. }
interface
uses
  Types, Math, TypInfo, BGRABitmap, BGRABitmapTypes,
  tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Shape, tyControls.AdvanceChart.Paint;

type
  { echarts.init's useCoarsePointer: 'auto' (the default), false, true }
  TTyChartCoarsePointer = (ccpAuto, ccpOff, ccpOn);

  TTyZrRectArray = array of TTyXYWH;

  { one element as createRepaintRects reads it }
  TTyRepaintItem = record
    { shouldBePainted(w, h, true, true) now }
    ShouldPaint: Boolean;
    { __isRendered: on the canvas from an earlier frame }
    Rendered: Boolean;
    { __dirty & REDRAW_BIT }
    Dirty: Boolean;
    { el.__zr: still in the storage (read for the previous list only) }
    InStorage: Boolean;
    { getPaintRect; HasPaint False is null }
    HasPaint: Boolean;
    Paint: TTyXYWH;
    { getPrevPaintRect; HasPrev False is undefined }
    HasPrev: Boolean;
    Prev: TTyXYWH;
  end;
  TTyRepaintItemArray = array of TTyRepaintItem;

  { ONE ELEMENT OF A LAYER AS IT WAS PAINTED: the record, whether it was
    painted (zrender's shouldBePainted: not ignored, not a chunk still to
    come, not under the axes, opacity not 0), and its paint rect -- Bounded
    False when the port cannot bound it }
  TTyDirtySnapItem = record
    El: TTyChartElement;
    Painted: Boolean;
    Bounded: Boolean;
    Rect: TTyXYWH;
  end;
  TTyDirtySnap = array of TTyDirtySnapItem;

  { createRepaintRects' merge pool on its own, for rects that are not an
    element's (the dynamic layer's ink) }
  TTyRepaintPool = record
    Rects: TTyZrRectArray;
    Count: Integer;
    Full: Boolean;
    MaxCount: Integer;
  end;

const
  cTyMaxRepaintRectCount = 5;
  cTyDefaultPointerSize = 44;
  { a TSpan's dirtyRectTolerance }
  cTyTextDirtyTolerance = 10;

{ ---- BoundingRect ---- }
{ intersect with no options: touching edges count; a NaN never separates }
function TyZrRectIntersect(const A, B: TTyXYWH): Boolean;
{ union, as BoundingRect.union writes it into A }
procedure TyZrRectUnion(var A: TTyXYWH; const B: TTyXYWH);
function TyZrRectIsZero(const A: TTyXYWH): Boolean;
function TyZrRectIsFinite(const A: TTyXYWH): Boolean;
{ Displayable.getPaintRect from a box already through its transform }
function TyZrPaintRect(const ABox: TTyXYWH; AShadowBlur, AShadowOffsetX,
  AShadowOffsetY, ATolerance: Double): TTyXYWH;

{ ---- the merge pool and createRepaintRects ---- }
procedure TyRepaintPoolInit(out APool: TTyRepaintPool;
  AMaxCount: Integer = cTyMaxRepaintRectCount);
procedure TyRepaintPoolAdd(var APool: TTyRepaintPool; const ARect: TTyXYWH);
{ the final pass: zero rects dropped, rects that meet merged until none do }
function TyRepaintPoolFinish(var APool: TTyRepaintPool): TTyZrRectArray;
{ Layer.createRepaintRects after its first-paint answer (null): AList is
  this frame's list (the layer's range), APrev the previous frame's }
function TyCreateRepaintRects(const AList, APrev: TTyRepaintItemArray;
  AMaxCount: Integer = cTyMaxRepaintRectCount): TTyZrRectArray;

{ ---- the coarse pointer ---- }
{ how the port answers 'auto': a touch platform. Decided when the library
  is compiled, not by asking the machine: Android and iOS builds are touch
  platforms; every desktop widgetset (win32, gtk2/3, qt5/6, cocoa) is a
  mouse platform, a touch-screen laptop included -- LCL hands a desktop
  control a touch as a synthesised mouse message and gives it no way to
  tell the two apart, so 'auto' cannot mean "the pointer is a finger"
  there the way the browser's touch events let it. }
function TyTouchPlatform: Boolean;
{ the handler's pointer size, logical px: 0 when the fallback is off }
function TyCoarsePointerSize(AMode: TTyChartCoarsePointer;
  APointerSize: Integer; ATouch: Boolean): Integer;
{ findHover's samples about (AX, AY) for a pointer APointerSize wide, in
  order, as x, y pairs; AScale multiplies the radius (device px per logical
  px -- 1 reproduces upstream's numbers to the bit) }
function TyCoarseSamples(AX, AY, APointerSize: Double;
  AScale: Double = 1): TTyDoubleArray;
{ the fallback over a paint list: the insertion index of the element found,
  or -1. Containment is the list's own without the port's pad
  (HitPadLogical): what upstream's Path.contain would answer. }
function TyCoarseHitTest(AList: TTyPaintList; AX, AY: Double; APPI: Integer;
  APointerSizeLogical: Double): Integer;
{ an element's box as the candidate test reads it (getBoundingRect through
  the transform), device px; False when it has none }
function TyElementCoarseBox(const AEl: TTyChartElement; APPI: Integer;
  out ABox: TTyXYWH): Boolean;

{ ---- the dirty rectangles ---- }
{ two values of one type, field by field through the RTTI: strings and
  dynamic arrays by content, numbers by their bytes (so NaN is NaN and -0
  is not 0 -- a difference is only ever an extra repaint). A type the walk
  does not know answers False, which is the safe side. }
function TyDeepSame(A, B: Pointer; ATypeInfo: PTypeInfo): Boolean;
function TyElementsSame(const A, B: TTyChartElement): Boolean;
{ the paint rect of a port element: every pixel the renderer can put down
  for it lies inside, device px. False when the port cannot bound it (a
  large batch, a rich-text caption): a change to one repaints everything. }
function TyElementPaintRect(const AEl: TTyChartElement; APPI: Integer;
  out ARect: TTyXYWH): Boolean;
{ a paint list as painted now, in insertion order }
function TyDirtySnapshot(AList: TTyPaintList; APPI: Integer): TTyDirtySnap;
{ THE REPAINT between two snapshots of one layer, the same elements in the
  same insertion order: each element changed in any field is dirty, its
  old and new rects go to createRepaintRects, and the rects come back in
  APool's terms (added to it, not finished). False -- repaint everything --
  when the two lists are not the same elements (their lengths differ), or a
  changed element cannot be bounded, or one under the axes changed (it is
  part of the ground the rects start from). }
function TyDirtyDiff(const AOld, ANew: TTyDirtySnap; out ARects: TTyZrRectArray): Boolean;

{ the tiles of ABmp (ATile px square, clipped to the bitmap) holding any
  pixel that is not fully transparent, appended to ARects }
procedure TyInkTiles(ABmp: TBGRABitmap; ATile: Integer; var ARects: TTyZrRectArray);
{ a pool rect as pixels, clipped to AW x AH; False when nothing is left }
function TyZrRectToPixels(const AR: TTyXYWH; AW, AH: Integer; out APx: TRect): Boolean;

implementation

uses
  tyControls.AdvanceChart.JsMath;

const
  { Math.PI as a double, so the step and the bound are upstream's numbers
    whatever precision Pi folds in }
  cJsPi: Double = 3.141592653589793;
  { the canvas' default miterLimit: a mitred corner reaches up to this many
    half pen widths from the outline }
  cMiterLimit = 10;

function NumGt(A, B: Double): Boolean; inline;
begin
  { a NaN on either side is false, as JavaScript's > is -- and an ordered
    compare against a NaN would raise here }
  if IsNan(A) or IsNan(B) then Exit(False);
  Result := A > B;
end;

function NumLt(A, B: Double): Boolean; inline;
begin
  if IsNan(A) or IsNan(B) then Exit(False);
  Result := A < B;
end;

function JsMin(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if A < B then Result := A else Result := B;
end;

function JsMax(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if A > B then Result := A else Result := B;
end;

function JsFinite(A: Double): Boolean; inline;
begin
  Result := not (IsNan(A) or IsInfinite(A));
end;

{ ==================== BoundingRect ==================== }

function TyZrRectIntersect(const A, B: TTyXYWH): Boolean;
var ax0, ax1, ay0, ay1, bx0, bx1, by0, by1, t: Double;
begin
  { BoundingRect.set normalises a negative size, as the constructor does
    for the pointer's square }
  ax0 := A.X; ax1 := A.X + A.W;
  if NumLt(A.W, 0) then begin t := ax0; ax0 := ax1; ax1 := t; end;
  ay0 := A.Y; ay1 := A.Y + A.H;
  if NumLt(A.H, 0) then begin t := ay0; ay0 := ay1; ay1 := t; end;
  bx0 := B.X; bx1 := B.X + B.W;
  if NumLt(B.W, 0) then begin t := bx0; bx0 := bx1; bx1 := t; end;
  by0 := B.Y; by1 := B.Y + B.H;
  if NumLt(B.H, 0) then begin t := by0; by0 := by1; by1 := t; end;
  if NumGt(ax0, ax1) or NumGt(ay0, ay1) or NumGt(bx0, bx1) or NumGt(by0, by1) then
    Exit(False);
  Result := not (NumLt(ax1, bx0) or NumLt(bx1, ax0) or NumLt(ay1, by0)
    or NumLt(by1, ay0));
end;

procedure TyZrRectUnion(var A: TTyXYWH; const B: TTyXYWH);
var x, y: Double;
begin
  x := JsMin(B.X, A.X);
  y := JsMin(B.Y, A.Y);
  { x -Infinity with width Infinity would make x + width NaN: the other's
    width is taken whole }
  if JsFinite(A.X) and JsFinite(A.W) then
    A.W := JsMax(B.X + B.W, A.X + A.W) - x
  else
    A.W := B.W;
  if JsFinite(A.Y) and JsFinite(A.H) then
    A.H := JsMax(B.Y + B.H, A.Y + A.H) - y
  else
    A.H := B.H;
  A.X := x;
  A.Y := y;
end;

function TyZrRectIsZero(const A: TTyXYWH): Boolean;
begin
  Result := (A.W = 0) or (A.H = 0);
end;

function TyZrRectIsFinite(const A: TTyXYWH): Boolean;
begin
  Result := JsFinite(A.X) and JsFinite(A.Y) and JsFinite(A.W) and JsFinite(A.H);
end;

function TyZrPaintRect(const ABox: TTyXYWH; AShadowBlur, AShadowOffsetX,
  AShadowOffsetY, ATolerance: Double): TTyXYWH;
var x0, y0: Double;
begin
  Result := ABox;
  { `style.shadowBlur || 0`: NaN and 0 alike }
  if IsNan(AShadowBlur) then AShadowBlur := 0;
  if IsNan(AShadowOffsetX) then AShadowOffsetX := 0;
  if IsNan(AShadowOffsetY) then AShadowOffsetY := 0;
  if (AShadowBlur <> 0) or (AShadowOffsetX <> 0) or (AShadowOffsetY <> 0) then
  begin
    { the width before x, as upstream: x then reads the old x }
    Result.W := Result.W + AShadowBlur * 2 + Abs(AShadowOffsetX);
    Result.H := Result.H + AShadowBlur * 2 + Abs(AShadowOffsetY);
    x0 := Result.X;
    y0 := Result.Y;
    Result.X := JsMin(x0, x0 + AShadowOffsetX - AShadowBlur);
    Result.Y := JsMin(y0, y0 + AShadowOffsetY - AShadowBlur);
  end;
  if not TyZrRectIsZero(Result) then
  begin
    Result.X := Floor(Result.X - ATolerance);
    Result.Y := Floor(Result.Y - ATolerance);
    Result.W := Ceil(Result.W + 1 + ATolerance * 2);
    Result.H := Ceil(Result.H + 1 + ATolerance * 2);
  end;
end;

{ ==================== the pool ==================== }

procedure TyRepaintPoolInit(out APool: TTyRepaintPool; AMaxCount: Integer);
begin
  APool.Rects := nil;
  APool.Count := 0;
  APool.Full := False;
  APool.MaxCount := AMaxCount;
end;

procedure PoolPush(var APool: TTyRepaintPool; const ARect: TTyXYWH);
begin
  if APool.Count >= Length(APool.Rects) then
    SetLength(APool.Rects, APool.Count * 2 + 4);
  APool.Rects[APool.Count] := ARect;
  Inc(APool.Count);
end;

procedure TyRepaintPoolAdd(var APool: TTyRepaintPool; const ARect: TTyXYWH);
var
  i, best: Integer;
  merged: Boolean;
  minDelta, aArea, bArea, pArea, delta: Double;
  pending: TTyXYWH;
begin
  if not TyZrRectIsFinite(ARect) or TyZrRectIsZero(ARect) then Exit;
  if APool.Count = 0 then
  begin
    PoolPush(APool, ARect);
    Exit;
  end;
  merged := False;
  minDelta := Infinity;
  best := 0;
  for i := 0 to APool.Count - 1 do
  begin
    if TyZrRectIntersect(APool.Rects[i], ARect) then
    begin
      pending := APool.Rects[i];
      TyZrRectUnion(pending, ARect);
      APool.Rects[i] := pending;
      merged := True;
      Break;
    end
    else if APool.Full then
    begin
      pending := ARect;
      TyZrRectUnion(pending, APool.Rects[i]);
      aArea := ARect.W * ARect.H;
      bArea := APool.Rects[i].W * APool.Rects[i].H;
      pArea := pending.W * pending.H;
      delta := pArea - aArea - bArea;
      if NumLt(delta, minDelta) then
      begin
        minDelta := delta;
        best := i;
      end;
    end;
  end;
  { FULL: into the rect it grows least -- and upstream does this even when
    the loop above already merged it into a rect it met, with `best` as far
    as the loop got (0 when it met the first) }
  if APool.Full then
  begin
    TyZrRectUnion(APool.Rects[best], ARect);
    merged := True;
  end;
  if not merged then PoolPush(APool, ARect);
  if not APool.Full then APool.Full := APool.Count >= APool.MaxCount;
end;

function TyRepaintPoolFinish(var APool: TTyRepaintPool): TTyZrRectArray;
var
  i, j, k: Integer;
  again: Boolean;
begin
  repeat
    again := False;
    i := 0;
    while i < APool.Count do
    begin
      if TyZrRectIsZero(APool.Rects[i]) then
      begin
        for k := i to APool.Count - 2 do APool.Rects[k] := APool.Rects[k + 1];
        Dec(APool.Count);
        Continue;
      end;
      j := i + 1;
      while j < APool.Count do
      begin
        if TyZrRectIntersect(APool.Rects[i], APool.Rects[j]) then
        begin
          again := True;
          TyZrRectUnion(APool.Rects[i], APool.Rects[j]);
          for k := j to APool.Count - 2 do APool.Rects[k] := APool.Rects[k + 1];
          Dec(APool.Count);
        end
        else
          Inc(j);
      end;
      Inc(i);
    end;
  until not again;
  Result := nil;
  SetLength(Result, APool.Count);
  for i := 0 to APool.Count - 1 do Result[i] := APool.Rects[i];
end;

function TyCreateRepaintRects(const AList, APrev: TTyRepaintItemArray;
  AMaxCount: Integer): TTyZrRectArray;
var
  pool: TTyRepaintPool;
  i: Integer;
begin
  TyRepaintPoolInit(pool, AMaxCount);
  for i := 0 to High(AList) do
  begin
    { the previous rect: on the canvas, and dirty or not to be painted }
    if AList[i].Rendered and (AList[i].Dirty or not AList[i].ShouldPaint)
      and AList[i].HasPrev then
      TyRepaintPoolAdd(pool, AList[i].Prev);
    { the current rect: to be painted, and dirty or not on the canvas }
    if AList[i].ShouldPaint and (AList[i].Dirty or not AList[i].Rendered)
      and AList[i].HasPaint then
      TyRepaintPoolAdd(pool, AList[i].Paint);
  end;
  { the elements this frame's list lost }
  for i := 0 to High(APrev) do
    if ((not APrev[i].ShouldPaint) or not APrev[i].InStorage)
      and APrev[i].Rendered and APrev[i].HasPrev then
      TyRepaintPoolAdd(pool, APrev[i].Prev);
  Result := TyRepaintPoolFinish(pool);
end;

{ ==================== the coarse pointer ==================== }

function TyTouchPlatform: Boolean;
begin
  {$IF defined(ANDROID) or defined(IOS)}
  Result := True;
  {$ELSE}
  Result := False;
  {$ENDIF}
end;

function TyCoarsePointerSize(AMode: TTyChartCoarsePointer;
  APointerSize: Integer; ATouch: Boolean): Integer;
var on_: Boolean;
begin
  case AMode of
    ccpOn: on_ := True;
    ccpOff: on_ := False;
  else
    on_ := ATouch;
  end;
  { `this._pointerSize && ...`: 0 is off, and a negative size has no ring
    below its half -- no sample, no target }
  if on_ and (APointerSize > 0) then Result := APointerSize else Result := 0;
end;

function TyCoarseSamples(AX, AY, APointerSize, AScale: Double): TTyDoubleArray;
var
  r, half, theta, step, pi2, rr: Double;
  n: Integer;
begin
  Result := nil;
  n := 0;
  half := APointerSize / 2;
  step := cJsPi / 12;
  pi2 := cJsPi * 2;
  r := 0;
  while NumLt(r, half) do
  begin
    rr := r * AScale;
    theta := 0;
    while theta < pi2 do
    begin
      if n + 2 > Length(Result) then SetLength(Result, n * 2 + 64);
      Result[n] := AX + rr * TyJsCos(theta);
      Result[n + 1] := AY + rr * TyJsSin(theta);
      Inc(n, 2);
      theta := theta + step;
    end;
    r := r + 4;
  end;
  SetLength(Result, n);
end;

function RotatedBox(const ABox: TTyXYWH; ARad, ACX, ACY: Double): TTyXYWH;
var
  c, s, x, y, minX, minY, maxX, maxY, px, py: Double;
  k: Integer;
begin
  c := Cos(ARad);
  s := Sin(ARad);
  minX := Infinity; minY := Infinity; maxX := -Infinity; maxY := -Infinity;
  for k := 0 to 3 do
  begin
    if (k = 1) or (k = 2) then x := ABox.X + ABox.W else x := ABox.X;
    if k >= 2 then y := ABox.Y + ABox.H else y := ABox.Y;
    { positive is clockwise on screen, as the painter turns }
    px := ACX + (x - ACX) * c - (y - ACY) * s;
    py := ACY + (x - ACX) * s + (y - ACY) * c;
    if px < minX then minX := px;
    if px > maxX then maxX := px;
    if py < minY then minY := py;
    if py > maxY then maxY := py;
  end;
  Result.X := minX;
  Result.Y := minY;
  Result.W := maxX - minX;
  Result.H := maxY - minY;
end;

function TyElementCoarseBox(const AEl: TTyChartElement; APPI: Integer;
  out ABox: TTyXYWH): Boolean;
var
  b: TTyRectF;
  s: Double;
begin
  b := TyShapeBounds(AEl.Shape);
  if not TyRectFIsValid(b) then Exit(False);
  ABox := TyRectToXYWH(b);
  if (AEl.Shape.Kind = cskPath) and (AEl.Shape.RotationRad <> 0) then
    ABox := RotatedBox(ABox, AEl.Shape.RotationRad, AEl.Shape.RotCX, AEl.Shape.RotCY);
  if APPI > 0 then s := APPI / 96 else s := 1;
  { Path.getBoundingRect: the stroke's width, max(width, 5) without a fill }
  if AEl.Style.StrokeWidthLogical > 0 then
    ABox := TyGrowByStroke(ABox, AEl.Style.HasFill, AEl.Style.StrokeWidthLogical * s);
  Result := True;
end;

function TyCoarseHitTest(AList: TTyPaintList; AX, AY: Double; APPI: Integer;
  APointerSizeLogical: Double): Integer;
var
  s, half: Double;
  pr, box: TTyXYWH;
  cand: array of Integer;
  nc, i, idx, k: Integer;
  el: TTyChartElement;
  pts: TTyDoubleArray;
  slops: TTyDoubleArray;
begin
  Result := -1;
  if (AList = nil) or not (APointerSizeLogical > 0) then Exit;
  if APPI > 0 then s := APPI / 96 else s := 1;
  half := APointerSizeLogical / 2;
  pr.X := AX - half * s;
  pr.Y := AY - half * s;
  pr.W := APointerSizeLogical * s;
  pr.H := APointerSizeLogical * s;
  { THE CANDIDATES, top first: not ignored, not a large batch
    (ignoreCoarsePointer), not silent -- a silent element is a candidate
    upstream too, and never the target, so it is left out here -- whose box
    meets the pointer's square }
  SetLength(cand, AList.Count);
  SetLength(slops, AList.Count);
  nc := 0;
  for i := AList.Count - 1 downto 0 do
  begin
    idx := AList.PaintOrder(i);
    el := AList.Element(idx);
    if el.Silent or el.Ignore or el.ProgHidden then Continue;
    if el.Shape.Kind = cskLarge then Continue;
    if not TyElementCoarseBox(el, APPI, box) then Continue;
    if not TyZrRectIntersect(box, pr) then Continue;
    cand[nc] := idx;
    slops[nc] := el.HitSlopLogical * s;
    Inc(nc);
  end;
  if nc = 0 then Exit;
  pts := TyCoarseSamples(AX, AY, APointerSizeLogical, s);
  i := 0;
  while i + 1 < Length(pts) do
  begin
    { BOTTOM FIRST: setHoverTarget walks the candidates from the end }
    { an element's own contain: a geo region's path [Batch 148] }
    for k := nc - 1 downto 0 do
      if TyElementContains(AList.Element(cand[k]), pts[i], pts[i + 1], slops[k]) then
        Exit(cand[k]);
    Inc(i, 2);
  end;
end;

{ ==================== change detection ==================== }

function OrdSize(AOrd: TOrdType): Integer;
begin
  case AOrd of
    otSByte, otUByte: Result := 1;
    otSWord, otUWord: Result := 2;
    otSLong, otULong: Result := 4;
  else
    Result := 8;
  end;
end;

function TyDeepSame(A, B: Pointer; ATypeInfo: PTypeInfo): Boolean;
var
  td: PTypeData;
  mf: PManagedField;
  i, n, sz: SizeInt;
  ti: PTypeInfo;
  pa, pb: Pointer;
begin
  if (ATypeInfo = nil) or (A = nil) or (B = nil) then Exit(False);
  td := GetTypeData(ATypeInfo);
  case ATypeInfo^.Kind of
    tkRecord, tkObject:
      begin
        { every field, managed or not: FPC lists them all with their
          offsets, so padding never takes part }
        mf := PManagedField(PByte(@td^.TotalFieldCount) + SizeOf(td^.TotalFieldCount));
        for i := 0 to td^.TotalFieldCount - 1 do
        begin
          if not TyDeepSame(PByte(A) + mf^.FldOffset, PByte(B) + mf^.FldOffset,
            mf^.TypeRef) then Exit(False);
          Inc(mf);
        end;
        Result := True;
      end;
    tkArray:
      begin
        n := td^.ArrayData.ElCount;
        if n <= 0 then Exit(True);
        sz := td^.ArrayData.Size div n;
        ti := td^.ArrayData.ElType;
        for i := 0 to n - 1 do
          if not TyDeepSame(PByte(A) + i * sz, PByte(B) + i * sz, ti) then Exit(False);
        Result := True;
      end;
    tkDynArray:
      begin
        pa := PPointer(A)^;
        pb := PPointer(B)^;
        if pa = pb then Exit(True);
        n := DynArraySize(pa);
        if n <> DynArraySize(pb) then Exit(False);
        sz := td^.elSize;
        ti := td^.elType2;
        for i := 0 to n - 1 do
          if not TyDeepSame(PByte(pa) + i * sz, PByte(pb) + i * sz, ti) then Exit(False);
        Result := True;
      end;
    tkAString:
      Result := PAnsiString(A)^ = PAnsiString(B)^;
    tkUString:
      Result := PUnicodeString(A)^ = PUnicodeString(B)^;
    tkWString:
      Result := PWideString(A)^ = PWideString(B)^;
    tkSString:
      Result := PShortString(A)^ = PShortString(B)^;
    tkInteger, tkChar, tkEnumeration, tkBool, tkWChar:
      Result := CompareByte(A^, B^, OrdSize(td^.OrdType)) = 0;
    tkSet:
      Result := CompareByte(A^, B^, td^.SetSize) = 0;
    tkFloat:
      case td^.FloatType of
        ftSingle: Result := CompareByte(A^, B^, 4) = 0;
        ftDouble, ftComp, ftCurr: Result := CompareByte(A^, B^, 8) = 0;
      else
        Result := CompareByte(A^, B^, SizeOf(Extended)) = 0;
      end;
    tkInt64, tkQWord:
      Result := CompareByte(A^, B^, 8) = 0;
    tkPointer, tkClass, tkClassRef, tkInterface, tkInterfaceRaw, tkProcVar:
      Result := PPointer(A)^ = PPointer(B)^;
    tkMethod:
      Result := CompareByte(A^, B^, 2 * SizeOf(Pointer)) = 0;
  else
    Result := False;
  end;
end;

function TyElementsSame(const A, B: TTyChartElement): Boolean;
begin
  Result := TyDeepSame(@A, @B, TypeInfo(TTyChartElement));
end;

function TyElementPaintRect(const AEl: TTyChartElement; APPI: Integer;
  out ARect: TTyXYWH): Boolean;
var
  s, sw, halo, half, tol: Double;
  b: TTyRectF;
  box, cap: TTyXYWH;
begin
  ARect := Default(TTyXYWH);
  { a large batch draws in tiles of its own: no bound is promised }
  if AEl.Shape.Kind = cskLarge then Exit(False);
  if APPI > 0 then s := APPI / 96 else s := 1;
  b := TyShapeBounds(AEl.Shape);
  if not TyRectFIsValid(b) then Exit(False);
  box := TyRectToXYWH(b);
  { a turned path is turned at draw time about its own point }
  if (AEl.Shape.Kind = cskPath) and (AEl.Shape.RotationRad <> 0) then
    box := RotatedBox(box, AEl.Shape.RotationRad, AEl.Shape.RotCX, AEl.Shape.RotCY);
  sw := Max(Double(0), AEl.Style.StrokeWidthLogical) * s;
  if sw > 0 then
  begin
    box := TyGrowByStroke(box, AEl.Style.HasFill, sw);
    { A MITRED CORNER reaches past half the pen: up to miterLimit half
      widths at a sharp turn -- a polyline's spike, a thin sector's tip.
      A rect's and an ellipse's never do. }
    if not (AEl.Shape.Kind in [cskRect, cskRoundRect, cskCircle, cskEllipse]) then
    begin
      box.X := box.X - (cMiterLimit - 1) * sw / 2;
      box.Y := box.Y - (cMiterLimit - 1) * sw / 2;
      box.W := box.W + (cMiterLimit - 1) * sw;
      box.H := box.H + (cMiterLimit - 1) * sw;
    end;
  end;
  tol := 0;
  if AEl.Caption.Text <> '' then
  begin
    { the rich pieces carry boxes, shadows and words of their own }
    if Length(AEl.Caption.RtPieces) > 0 then Exit(False);
    halo := Ceil(Max(Double(0), AEl.Caption.StrokeWidthLogical) / 2 * s) + 1;
    if AEl.Caption.RotationRad <> 0 then
    begin
      { turned about its anchor, which lies on its box: the box's two sides
        bound the reach in every direction }
      half := (b.Right - b.Left) + (b.Bottom - b.Top) + halo;
      if not (half > 0) or IsNan(AEl.Caption.X) or IsNan(AEl.Caption.Y) then Exit(False);
      cap.X := AEl.Caption.X - half;
      cap.Y := AEl.Caption.Y - half;
      cap.W := 2 * half;
      cap.H := 2 * half;
    end
    else
    begin
      { the glyphs are clipped to the shape's rect, the halo stamped round
        them }
      cap := TyRectToXYWH(b);
      cap.X := cap.X - halo;
      cap.Y := cap.Y - halo;
      cap.W := cap.W + 2 * halo;
      cap.H := cap.H + 2 * halo;
    end;
    TyZrRectUnion(box, cap);
    tol := cTyTextDirtyTolerance;
  end;
  { THE PORT'S PIXEL OF ANTIALIASING on every side: an edge on a whole
    pixel can still tint the pixel beside it }
  box.X := box.X - 1;
  box.Y := box.Y - 1;
  box.W := box.W + 2;
  box.H := box.H + 2;
  if not TyZrRectIsFinite(box) then Exit(False);
  ARect := TyZrPaintRect(box, 0, 0, 0, tol);
  Result := True;
end;

function SnapPainted(const AEl: TTyChartElement): Boolean;
begin
  Result := not AEl.Ignore and not AEl.ProgHidden and not AEl.GfxUnder
    and not (AEl.Style.Alpha = 0);
end;

function TyDirtySnapshot(AList: TTyPaintList; APPI: Integer): TTyDirtySnap;
var i: Integer;
begin
  Result := nil;
  if AList = nil then Exit;
  SetLength(Result, AList.Count);
  for i := 0 to AList.Count - 1 do
  begin
    Result[i].El := AList.Element(i);
    Result[i].Painted := SnapPainted(Result[i].El);
    Result[i].Bounded := TyElementPaintRect(Result[i].El, APPI, Result[i].Rect);
  end;
end;

function TyDirtyDiff(const AOld, ANew: TTyDirtySnap; out ARects: TTyZrRectArray): Boolean;
var
  items, prev: TTyRepaintItemArray;
  i: Integer;
  changed: Boolean;
begin
  ARects := nil;
  if Length(AOld) <> Length(ANew) then Exit(False);
  SetLength(items, Length(ANew));
  SetLength(prev, Length(AOld));
  for i := 0 to High(ANew) do
  begin
    changed := not TyElementsSame(AOld[i].El, ANew[i].El);
    if changed and (AOld[i].El.GfxUnder or ANew[i].El.GfxUnder) then Exit(False);
    if changed and not (AOld[i].Bounded and ANew[i].Bounded) then Exit(False);
    { as createRepaintRects reads it: on the canvas when it was painted last
      frame -- every element's rect is recorded on every paint, so an
      element first painted by a full frame has its previous rect too }
    items[i].ShouldPaint := ANew[i].Painted;
    items[i].Rendered := AOld[i].Painted;
    items[i].Dirty := changed;
    items[i].InStorage := True;
    items[i].HasPaint := ANew[i].Bounded;
    items[i].Paint := ANew[i].Rect;
    items[i].HasPrev := AOld[i].Bounded;
    items[i].Prev := AOld[i].Rect;
    { the previous list holds the same elements, read now }
    prev[i] := items[i];
  end;
  ARects := TyCreateRepaintRects(items, prev);
  Result := True;
end;

procedure TyInkTiles(ABmp: TBGRABitmap; ATile: Integer; var ARects: TTyZrRectArray);
var
  tx, ty, x, y, x1, y1, n: Integer;
  p: PBGRAPixel;
  found: Boolean;
  r: TTyXYWH;
begin
  if (ABmp = nil) or (ATile <= 0) then Exit;
  n := Length(ARects);
  ty := 0;
  while ty < ABmp.Height do
  begin
    y1 := Min(ty + ATile, ABmp.Height);
    tx := 0;
    while tx < ABmp.Width do
    begin
      x1 := Min(tx + ATile, ABmp.Width);
      found := False;
      for y := ty to y1 - 1 do
      begin
        p := ABmp.ScanLine[y];
        Inc(p, tx);
        for x := tx to x1 - 1 do
        begin
          if p^.alpha <> 0 then
          begin
            found := True;
            Break;
          end;
          Inc(p);
        end;
        if found then Break;
      end;
      if found then
      begin
        r.X := tx;
        r.Y := ty;
        r.W := x1 - tx;
        r.H := y1 - ty;
        SetLength(ARects, n + 1);
        ARects[n] := r;
        Inc(n);
      end;
      tx := x1;
    end;
    ty := y1;
  end;
end;

function TyZrRectToPixels(const AR: TTyXYWH; AW, AH: Integer; out APx: TRect): Boolean;
begin
  APx := Rect(0, 0, 0, 0);
  if not TyZrRectIsFinite(AR) then Exit(False);
  APx.Left := Max(0, Floor(AR.X));
  APx.Top := Max(0, Floor(AR.Y));
  APx.Right := Min(AW, Ceil(AR.X + AR.W));
  APx.Bottom := Min(AH, Ceil(AR.Y + AR.H));
  Result := (APx.Right > APx.Left) and (APx.Bottom > APx.Top);
end;

end.
