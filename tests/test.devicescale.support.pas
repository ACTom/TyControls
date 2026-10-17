unit test.devicescale.support;
{$mode objfpc}{$H+}

{ #83: is a control drawn at the device scale drawn where it should be?

  At S = 2 a control laid out at W x H (PPI 96) paints a 2W x 2H raster. Averaged down 2:1 it
  must look like the same control painted at S = 1 -- same layout, same PPI, so no layout
  rounding can tell the two apart, only the drawing. Drawing done in layout coordinates on the
  raster lands at half its position and half its size, and stays there after the averaging.

  (The first reference tried was the control laid out at 2W x 2H at PPI 192. It drifts on its
  own: a calendar's six rows, laid out at 96 and doubled, end a few device pixels away from the
  same rows laid out at 192, and that noise was larger than the misplaced 1-px lines this has
  to catch.)

  The pictures are compared as INK, not colour (TyInkMismatch): antialiasing differs between a
  2:1 average and a direct rasterisation everywhere a line or a glyph runs, while both are
  right. }

interface

uses
  Classes, SysUtils, Types, Math, Controls, Forms, Graphics, LMessages, LCLType,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Painter;

type
  { Builds the control on AParent at APPI, in the state the check is about. The caller sizes it. }
  TTyBuildForScale = function(AParent: TWinControl; APPI: Integer): TControl of object;

const
  CFuzzyRadius = 2;
  { Ink thresholds, as a channel distance from the background: a pixel counts against the other
    picture when it is STRONG ink there is no WEAK ink near in the other. The gap between the
    two is what keeps a border drawn a shade lighter by one rasterisation from flipping
    between ink and background and counting as drawn in only one picture. }
  CStrongInk = 15;
  CWeakInk = 5;
  CBlock = 4;
  CBlockTolerance = 48;

{ The control's OWN surface (no children), painted the way test.dpi.support's PaintOne paints it:
  at S = AScale through the seam with DeviceUnits, into a W*S x H*S bitmap that starts white.
  AScale = 1 paints with the seam off. The caller frees the result. }
function TyPaintOwnSurface(AControl: TControl; AScale: Integer): TBGRABitmap;
{ INK, not colour. The background is the most frequent colour of ARef; a pixel's ink is how far
  its farthest channel is from it. The count is the strong-ink pixels of A with no weak-ink
  pixel of ARef within ARadius, plus the same the other way round. Pictures of different sizes
  count every pixel. }
function TyInkMismatch(A, ARef: TBGRABitmap; ARadius: Integer): Integer;
{ COLOUR, coarsely: ABlock x ABlock blocks whose mean colour differs between A and ARef by more
  than ATolerance in some channel. Catches what ink cannot -- a picture that covers the whole
  control is ink everywhere in both pictures wherever it was drawn -- while a one-pixel shift
  or a different antialiasing hardly moves a block's mean. }
function TyBlockMismatch(A, ARef: TBGRABitmap; ABlock, ATolerance: Integer): Integer;
{ Builds at 96 sized AW x AH twice: paints one at S = 2 and averages it down 2:1, paints the
  other at S = 1. The score is the unmatched ink (TyInkMismatch, both directions) plus the
  mismatched CBlock-pixel blocks (TyBlockMismatch). Measured noise: 0 ink and at most 6 blocks
  (TTyCalendar) for every control drawing correctly. }
{ For looking at a failure: ARef in grey, ink of A that ARef does not have in red, ink of ARef
  that A does not have in blue. The caller frees it. }
function TyInkMismatchImage(A, ARef: TBGRABitmap; ARadius: Integer): TBGRABitmap;
function TyDeviceScaleMismatch(ABuild: TTyBuildForScale; AW, AH: Integer): Integer;
{ The same, keeping both pictures (the caller frees them; AScaled is the averaged-down one) --
  for saving them when a check fails. }
function TyDeviceScaleMismatchPictures(ABuild: TTyBuildForScale; AW, AH: Integer;
  out AScaled, ARef: TBGRABitmap; out AInk, ABlocks: Integer): Integer;

implementation

type
  TWinControlAccess = class(TWinControl);
  TInkMask = array of array of Boolean;

function TyPaintOwnSurface(AControl: TControl; AScale: Integer): TBGRABitmap;
var
  bmp: TBitmap;
  w, h: Integer;
begin
  if AScale < 1 then AScale := 1;
  w := AControl.Width * AScale;
  h := AControl.Height * AScale;
  if w < 1 then w := 1;
  if h < 1 then h := 1;
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(w, h);
    bmp.Canvas.Brush.Color := clWhite;
    bmp.Canvas.FillRect(0, 0, w, h);
    if AScale > 1 then TyForceDeviceScaleForTest(AScale, True);
    try
      if AControl is TWinControl then
        TWinControlAccess(AControl).PaintWindow(bmp.Canvas.Handle)
      else
        AControl.Perform(LM_PAINT, WPARAM(bmp.Canvas.Handle), 0);
    finally
      TyForceDeviceScaleForTest(0, False);
    end;
    Result := TBGRABitmap.Create(bmp);
  finally
    bmp.Free;
  end;
end;

{ The most frequent colour, as the MEAN of the pixels in the most frequent 4-bit bucket -- not
  the bucket's corner: a #F0F0F0 surface falls in the same bucket as white, and decoding the
  bucket gave 255 for it, which made every background pixel "ink". }
function BackgroundOf(B: TBGRABitmap): TBGRAPixel;
var
  counts: array of Integer;
  sr, sg, sb: array of Int64;
  y, k, best, r, g, bl: Integer;
  p: PBGRAPixel;
begin
  SetLength(counts, 4096);   // zero-filled
  SetLength(sr, 4096);
  SetLength(sg, 4096);
  SetLength(sb, 4096);
  p := B.Data;
  for y := 0 to B.NbPixels - 1 do
  begin
    { Channels go through Integer LOCALS: Integer(p^.red) on a Byte field is a variable
      typecast in FPC -- it reads four bytes at the field, past the buffer's end on the last
      pixel. }
    r := p^.red;
    g := p^.green;
    bl := p^.blue;
    k := (r shr 4) * 256 + (g shr 4) * 16 + (bl shr 4);
    Inc(counts[k]);
    Inc(sr[k], r);
    Inc(sg[k], g);
    Inc(sb[k], bl);
    Inc(p);
  end;
  best := 0;
  for k := 1 to High(counts) do
    if counts[k] > counts[best] then best := k;
  if counts[best] = 0 then Exit(BGRAWhite);
  Result := BGRA(sr[best] div counts[best], sg[best] div counts[best], sb[best] div counts[best], 255);
end;

function InkMask(B: TBGRABitmap; const ABg: TBGRAPixel; ATolerance: Integer): TInkMask;
var
  x, y, r, g, bl: Integer;
  p: PBGRAPixel;
begin
  SetLength(Result, B.Height, B.Width);
  for y := 0 to B.Height - 1 do
  begin
    p := B.ScanLine[y];
    for x := 0 to B.Width - 1 do
    begin
      r := p[x].red;
      g := p[x].green;
      bl := p[x].blue;
      Result[y][x] := (Abs(r - ABg.red) > ATolerance) or (Abs(g - ABg.green) > ATolerance) or
        (Abs(bl - ABg.blue) > ATolerance);
    end;
  end;
end;

function Unmatched(const AInk, AOther: TInkMask; AW, AH, ARadius: Integer): Integer;
var
  x, y, dx, dy: Integer;
  found: Boolean;
begin
  Result := 0;
  for y := 0 to AH - 1 do
    for x := 0 to AW - 1 do
      if AInk[y][x] then
      begin
        found := False;
        for dy := -ARadius to ARadius do
        begin
          if (y + dy < 0) or (y + dy >= AH) then Continue;
          for dx := -ARadius to ARadius do
            if (x + dx >= 0) and (x + dx < AW) and AOther[y + dy][x + dx] then
            begin
              found := True;
              Break;
            end;
          if found then Break;
        end;
        if not found then Inc(Result);
      end;
end;

function Covered(const AOther: TInkMask; AX, AY, AW, AH, ARadius: Integer): Boolean;
var
  dx, dy: Integer;
begin
  for dy := -ARadius to ARadius do
    if (AY + dy >= 0) and (AY + dy < AH) then
      for dx := -ARadius to ARadius do
        if (AX + dx >= 0) and (AX + dx < AW) and AOther[AY + dy][AX + dx] then Exit(True);
  Result := False;
end;

function TyInkMismatchImage(A, ARef: TBGRABitmap; ARadius: Integer): TBGRABitmap;
var
  bg, c: TBGRAPixel;
  sa, wa, sb, wb: TInkMask;
  x, y, v: Integer;
begin
  Result := TBGRABitmap.Create(ARef.Width, ARef.Height, BGRAWhite);
  if (A.Width <> ARef.Width) or (A.Height <> ARef.Height) then Exit;
  bg := BackgroundOf(ARef);
  sa := InkMask(A, bg, CStrongInk);
  wa := InkMask(A, bg, CWeakInk);
  sb := InkMask(ARef, bg, CStrongInk);
  wb := InkMask(ARef, bg, CWeakInk);
  for y := 0 to ARef.Height - 1 do
    for x := 0 to ARef.Width - 1 do
    begin
      c := ARef.GetPixel(x, y);
      v := c.green;
      v := 128 + v div 2;
      Result.SetPixel(x, y, BGRA(v, v, v, 255));
      if sa[y][x] and not Covered(wb, x, y, A.Width, A.Height, ARadius) then
        Result.SetPixel(x, y, BGRA(255, 0, 0, 255))
      else if sb[y][x] and not Covered(wa, x, y, A.Width, A.Height, ARadius) then
        Result.SetPixel(x, y, BGRA(0, 0, 255, 255));
    end;
end;

{ Blocks of ABlock x ABlock pixels whose mean colour differs between A and ARef by more than
  ATolerance in some channel. }
function TyBlockMismatch(A, ARef: TBGRABitmap; ABlock, ATolerance: Integer): Integer;
var
  bx, by, x, y, n: Integer;
  ra, ga, ba, rb, gb, bb: Integer;
  pa, pb: PBGRAPixel;
begin
  if (A.Width <> ARef.Width) or (A.Height <> ARef.Height) then Exit(A.Width * A.Height);
  Result := 0;
  by := 0;
  while by < A.Height do
  begin
    bx := 0;
    while bx < A.Width do
    begin
      ra := 0; ga := 0; ba := 0; rb := 0; gb := 0; bb := 0; n := 0;
      for y := by to Min(by + ABlock, A.Height) - 1 do
      begin
        pa := A.ScanLine[y];
        pb := ARef.ScanLine[y];
        for x := bx to Min(bx + ABlock, A.Width) - 1 do
        begin
          ra := ra + pa[x].red; ga := ga + pa[x].green; ba := ba + pa[x].blue;
          rb := rb + pb[x].red; gb := gb + pb[x].green; bb := bb + pb[x].blue;
          Inc(n);
        end;
      end;
      if (Abs(ra - rb) > ATolerance * n) or (Abs(ga - gb) > ATolerance * n) or
        (Abs(ba - bb) > ATolerance * n) then Inc(Result);
      Inc(bx, ABlock);
    end;
    Inc(by, ABlock);
  end;
end;

function TyInkMismatch(A, ARef: TBGRABitmap; ARadius: Integer): Integer;
var
  bg: TBGRAPixel;
  sa, wa, sb, wb: TInkMask;
begin
  if (A.Width <> ARef.Width) or (A.Height <> ARef.Height) then Exit(A.Width * A.Height);
  bg := BackgroundOf(ARef);
  sa := InkMask(A, bg, CStrongInk);
  wa := InkMask(A, bg, CWeakInk);
  sb := InkMask(ARef, bg, CStrongInk);
  wb := InkMask(ARef, bg, CWeakInk);
  Result := Unmatched(sa, wb, A.Width, A.Height, ARadius) +
    Unmatched(sb, wa, A.Width, A.Height, ARadius);
end;

{ A 2:1 box average: every output pixel the mean of the 2 x 2 block it covers. }
function HalveBox(B: TBGRABitmap): TBGRABitmap;
var
  x, y, r, g, bl, a: Integer;
  p0, p1, q: PBGRAPixel;
begin
  Result := TBGRABitmap.Create(B.Width div 2, B.Height div 2);
  for y := 0 to Result.Height - 1 do
  begin
    p0 := B.ScanLine[2 * y];
    p1 := B.ScanLine[2 * y + 1];
    q := Result.ScanLine[y];
    for x := 0 to Result.Width - 1 do
    begin
      r := p0[2 * x].red;   r := r + p0[2 * x + 1].red;   r := r + p1[2 * x].red;   r := r + p1[2 * x + 1].red;
      g := p0[2 * x].green; g := g + p0[2 * x + 1].green; g := g + p1[2 * x].green; g := g + p1[2 * x + 1].green;
      bl := p0[2 * x].blue; bl := bl + p0[2 * x + 1].blue; bl := bl + p1[2 * x].blue; bl := bl + p1[2 * x + 1].blue;
      a := p0[2 * x].alpha; a := a + p0[2 * x + 1].alpha; a := a + p1[2 * x].alpha; a := a + p1[2 * x + 1].alpha;
      q[x] := BGRA((r + 2) div 4, (g + 2) div 4, (bl + 2) div 4, (a + 2) div 4);
    end;
  end;
  Result.InvalidateBitmap;
end;

function TyDeviceScaleMismatchPictures(ABuild: TTyBuildForScale; AW, AH: Integer;
  out AScaled, ARef: TBGRABitmap; out AInk, ABlocks: Integer): Integer;
var
  f1, f2: TForm;
  c1, c2: TControl;
  raster: TBGRABitmap;
begin
  AScaled := nil;
  ARef := nil;
  f1 := TForm.CreateNew(nil);
  f2 := TForm.CreateNew(nil);
  try
    f1.SetBounds(0, 0, AW + 40, AH + 40);
    f2.SetBounds(0, 0, AW + 40, AH + 40);
    c1 := ABuild(f1, 96);
    c1.SetBounds(0, 0, AW, AH);
    raster := TyPaintOwnSurface(c1, 2);
    try
      AScaled := HalveBox(raster);
    finally
      raster.Free;
    end;
    c2 := ABuild(f2, 96);
    c2.SetBounds(0, 0, AW, AH);
    ARef := TyPaintOwnSurface(c2, 1);
    AInk := TyInkMismatch(AScaled, ARef, CFuzzyRadius);
    ABlocks := TyBlockMismatch(AScaled, ARef, CBlock, CBlockTolerance);
    Result := AInk + ABlocks;
  finally
    f2.Free;
    f1.Free;
  end;
end;

function TyDeviceScaleMismatch(ABuild: TTyBuildForScale; AW, AH: Integer): Integer;
var
  a, b: TBGRABitmap;
  ink, blocks: Integer;
begin
  Result := TyDeviceScaleMismatchPictures(ABuild, AW, AH, a, b, ink, blocks);
  a.Free;
  b.Free;
end;

end.
