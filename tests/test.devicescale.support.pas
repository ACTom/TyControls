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

  HOW THE TWO PICTURES ARE COMPARED, and why. Everything below was chosen offline on the same
  set of pictures: every check and palette control drawn correctly (the noise) against each of
  21 porting mistakes put back one at a time (the signal).
  - INK, not colour: a 2:1 average and a direct rasterisation differ in antialiasing wherever a
    line or a glyph runs, while both are right. A pixel counts when it is clearly ink and the
    other picture has no ink near it at least a quarter as strong: faint antialiasing covers
    faint antialiasing, but a light box outline does not cover the dark mark missing inside it
    (a tree's "mixed" check scored 4 with any ink covering, 40 with this).
  - NEAR is wider across than down (CRadiusX, CRadiusY): text laid out at 96 and drawn at 192
    drifts along its run under GDI hinting, a few pixels by the end of a short line; a glyph
    drawn at the wrong SIZE differs in height too, and that stays caught.
  - Ink against two backgrounds, the larger count wins: the whole picture's most frequent
    colour (a thin rule on a plain field) and each 16 x 16 tile's own (white text on a coloured
    banner, which is "background" to the whole picture).
  - Plus 4 x 4 blocks whose mean colour differs: a picture covering the whole control is ink
    everywhere in both pictures wherever it was drawn.
  Measured when set (2026-10-17): every correct picture scored at most 20 (a bold title in
  TTyAdvancedListBox; the next was 2); the weakest mistake still caught scored 28. Two kinds are
  not seen: a rule drawn at the right place with half its weight, and a faint 1-px rule drawn
  at the wrong place. Rules get their own assertion: found as rules (TyRules) on the S = 2
  raster itself, each must be the S = 1 rule doubled (TyDoubledRules). }

interface

uses
  Classes, SysUtils, Types, Math, Controls, Forms, Graphics, LMessages, LCLType, fpcunit,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Painter;

type
  { Builds the control on AParent at APPI, in the state the check is about. The caller sizes it. }
  TTyBuildForScale = function(AParent: TWinControl; APPI: Integer): TControl of object;
  TTyIntArray = array of Integer;

const
  CRadiusX = 5;
  CRadiusY = 2;
  { Ink thresholds, as a channel distance from the background: STRONG ink of one picture with
    no WEAK ink near it in the other counts. The gap keeps a border drawn a shade lighter by one
    rasterisation from flipping between ink and background. }
  CStrongInk = 15;
  CWeakInk = 5;
  { Ink near a pixel covers it only when stronger than 1/CCoverFraction of the pixel's own. }
  CCoverFraction = 5;
  CLocalTile = 16;
  CBlock = 4;
  CBlockTolerance = 64;

  { The score (unmatched ink + mismatched blocks) above which a
    control counts as not drawing at the device scale. Measured when this was set (2026-10-17,
    the comparison as this unit has it): every correct picture, palette and
    stateful checks together, scored at most 20 (a bold title in TTyAdvancedListBox; the next
    was 2); of 21 porting mistakes put back one at a time, the lowest still caught scored 28
    (the menu banner drawn at its layout position). 24 sits between them. }
  CMaxMismatch = 24;

type
  { The checks a device-scale test makes on a control built in a given state. }
  TDeviceScaleCase = class(TTestCase)
  protected
    { The control ABuild makes, sized AW x AH, draws at S = 2 as at S = 1: score <= CMaxMismatch.
      With TY_SWEEP_DIR set, a failing check (every check, with TY_SWEEP_ALL too) leaves its two
      pictures, the ink difference and its score there. }
    procedure CheckScale(const AName: string; ABuild: TTyBuildForScale; AW, AH: Integer);
    { The rules across ABand (layout pixels) at S = 1 -- between AMin and AMax of them, so the
      band is not all "rule" -- must be on the S = 2 raster, as painted, exactly those rules one
      layout pixel wide: at twice their place, two device pixels each. Catches what the picture
      comparison cannot see: a rule at the wrong place, or at half its weight. }
    procedure CheckRules(const AName: string; ABuild: TTyBuildForScale; AW, AH: Integer;
      const ABand: TRect; AVertical: Boolean; AMin, AMax: Integer);
  end;

function TyRulesText(const A: TTyIntArray): string;

{ The control's OWN surface (no children), painted the way test.dpi.support's PaintOne paints it:
  at S = AScale through the seam with DeviceUnits, into a W*S x H*S bitmap that starts white.
  AScale = 1 paints with the seam off. The caller frees the result. }
function TyPaintOwnSurface(AControl: TControl; AScale: Integer): TBGRABitmap;
{ A 2:1 box average: every output pixel the mean of the 2 x 2 block it covers. }
function TyHalve(B: TBGRABitmap): TBGRABitmap;
{ Unmatched ink, both directions, against the global and against the tile-local background;
  the larger. Pictures of different sizes count every pixel. }
function TyInkMismatch(A, ARef: TBGRABitmap): Integer;
{ CBlock x CBlock blocks whose mean colour differs by more than CBlockTolerance in a channel. }
function TyBlockMismatch(A, ARef: TBGRABitmap): Integer;
{ For looking at a failure: ARef in grey, A's unmatched ink in red, ARef's in blue (global
  background). The caller frees it. }
function TyInkMismatchImage(A, ARef: TBGRABitmap): TBGRABitmap;
{ The rules of a band: the x of every column (AVertical) or the y of every row of ABand where at
  least 80% of the band's pixels differ from its most frequent colour by more than ATolerance --
  lines across the whole band, which text never makes. Keep the band inside a frame: its
  antialiased sides come out a shade apart at the two scales. }
function TyRules(B: TBGRABitmap; const ABand: TRect; AVertical: Boolean;
  ATolerance: Integer): TTyIntArray;
{ What a rule one layout pixel wide is on a 2x raster: every coordinate x of A as 2x and 2x + 1. }
function TyDoubledRules(const A: TTyIntArray): TTyIntArray;
{ Builds at 96 sized AW x AH twice and paints one at S = 2 (ARaster, 2AW x 2AH, as painted) and
  the other at S = 1 (ARef). The caller frees both. }
procedure TyPaintAtBothScales(ABuild: TTyBuildForScale; AW, AH: Integer;
  out ARaster, ARef: TBGRABitmap);
{ Builds at 96 sized AW x AH twice: paints one at S = 2 and averages it down 2:1, paints the
  other at S = 1. Score = TyInkMismatch + TyBlockMismatch. }
function TyDeviceScaleMismatch(ABuild: TTyBuildForScale; AW, AH: Integer): Integer;
{ The same, keeping both pictures (the caller frees them; AScaled is the averaged-down one). }
function TyDeviceScaleMismatchPictures(ABuild: TTyBuildForScale; AW, AH: Integer;
  out AScaled, ARef: TBGRABitmap; out AInk, ABlocks: Integer): Integer;

implementation

type
  TWinControlAccess = class(TWinControl);
  TInkLevel = array of array of Integer;
  TBgMap = array of array of TBGRAPixel;

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

function TyHalve(B: TBGRABitmap): TBGRABitmap;
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
      { Channels through Integer locals: Integer(p^.red) on a Byte field is a variable typecast
        in FPC and reads four bytes (memory fpc-variable-typecast-reads-wider). }
      r := p0[2 * x].red;   r := r + p0[2 * x + 1].red;   r := r + p1[2 * x].red;   r := r + p1[2 * x + 1].red;
      g := p0[2 * x].green; g := g + p0[2 * x + 1].green; g := g + p1[2 * x].green; g := g + p1[2 * x + 1].green;
      bl := p0[2 * x].blue; bl := bl + p0[2 * x + 1].blue; bl := bl + p1[2 * x].blue; bl := bl + p1[2 * x + 1].blue;
      a := p0[2 * x].alpha; a := a + p0[2 * x + 1].alpha; a := a + p1[2 * x].alpha; a := a + p1[2 * x + 1].alpha;
      q[x] := BGRA((r + 2) div 4, (g + 2) div 4, (bl + 2) div 4, (a + 2) div 4);
    end;
  end;
  Result.InvalidateBitmap;
end;

{ The most frequent colour of the rectangle, as the MEAN of the pixels in its most frequent
  4-bit bucket -- not the bucket's corner: #F0F0F0 shares a bucket with white. }
function BackgroundIn(B: TBGRABitmap; AX0, AY0, AX1, AY1: Integer): TBGRAPixel;
var
  counts: array of Integer;
  sr, sg, sb: array of Int64;
  x, y, k, best, r, g, bl: Integer;
  p: PBGRAPixel;
begin
  SetLength(counts, 4096);
  SetLength(sr, 4096);
  SetLength(sg, 4096);
  SetLength(sb, 4096);
  for y := AY0 to AY1 - 1 do
  begin
    p := B.ScanLine[y];
    for x := AX0 to AX1 - 1 do
    begin
      r := p[x].red;
      g := p[x].green;
      bl := p[x].blue;
      k := (r shr 4) * 256 + (g shr 4) * 16 + (bl shr 4);
      Inc(counts[k]);
      Inc(sr[k], r);
      Inc(sg[k], g);
      Inc(sb[k], bl);
    end;
  end;
  best := 0;
  for k := 1 to High(counts) do
    if counts[k] > counts[best] then best := k;
  if counts[best] = 0 then Exit(BGRAWhite);
  Result := BGRA(sr[best] div counts[best], sg[best] div counts[best], sb[best] div counts[best], 255);
end;

function GlobalBackground(B: TBGRABitmap): TBgMap;
var
  bg: TBGRAPixel;
  x, y: Integer;
begin
  bg := BackgroundIn(B, 0, 0, B.Width, B.Height);
  SetLength(Result, B.Height, B.Width);
  for y := 0 to B.Height - 1 do
    for x := 0 to B.Width - 1 do
      Result[y][x] := bg;
end;

function LocalBackground(B: TBGRABitmap): TBgMap;
var
  bg: TBGRAPixel;
  x, y, x0, y0: Integer;
begin
  SetLength(Result, B.Height, B.Width);
  y0 := 0;
  while y0 < B.Height do
  begin
    x0 := 0;
    while x0 < B.Width do
    begin
      bg := BackgroundIn(B, x0, y0, Min(x0 + CLocalTile, B.Width), Min(y0 + CLocalTile, B.Height));
      for y := y0 to Min(y0 + CLocalTile, B.Height) - 1 do
        for x := x0 to Min(x0 + CLocalTile, B.Width) - 1 do
          Result[y][x] := bg;
      Inc(x0, CLocalTile);
    end;
    Inc(y0, CLocalTile);
  end;
end;

{ Every pixel's ink: its farthest channel's distance from the background under it. }
function InkLevel(B: TBGRABitmap; const ABg: TBgMap): TInkLevel;
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
      r := Abs(r - ABg[y][x].red);
      g := p[x].green;
      g := Abs(g - ABg[y][x].green);
      bl := p[x].blue;
      bl := Abs(bl - ABg[y][x].blue);
      Result[y][x] := Max(r, Max(g, bl));
    end;
  end;
end;

{ The strongest ink within CRadiusX across and CRadiusY down of every pixel. }
function NearMax(const L: TInkLevel; AW, AH: Integer): TInkLevel;
var
  across: TInkLevel;
  x, y, d, m: Integer;
begin
  SetLength(across, AH, AW);
  for y := 0 to AH - 1 do
    for x := 0 to AW - 1 do
    begin
      m := 0;
      for d := Max(0, x - CRadiusX) to Min(AW - 1, x + CRadiusX) do
        if L[y][d] > m then m := L[y][d];
      across[y][x] := m;
    end;
  SetLength(Result, AH, AW);
  for y := 0 to AH - 1 do
    for x := 0 to AW - 1 do
    begin
      m := 0;
      for d := Max(0, y - CRadiusY) to Min(AH - 1, y + CRadiusY) do
        if across[d][x] > m then m := across[d][x];
      Result[y][x] := m;
    end;
end;

function Uncovered(AOwn, ANear: Integer): Boolean; inline;
begin
  Result := (AOwn > CStrongInk) and not ((ANear > CWeakInk) and (ANear * CCoverFraction > AOwn));
end;

function Unmatched(const AOwn, AOtherNear: TInkLevel; AW, AH: Integer): Integer;
var
  x, y: Integer;
begin
  Result := 0;
  for y := 0 to AH - 1 do
    for x := 0 to AW - 1 do
      if Uncovered(AOwn[y][x], AOtherNear[y][x]) then Inc(Result);
end;

function InkAgainst(A, ARef: TBGRABitmap; const ABg: TBgMap): Integer;
var
  la, lb: TInkLevel;
begin
  la := InkLevel(A, ABg);
  lb := InkLevel(ARef, ABg);
  Result := Unmatched(la, NearMax(lb, A.Width, A.Height), A.Width, A.Height) +
    Unmatched(lb, NearMax(la, A.Width, A.Height), A.Width, A.Height);
end;

function TyInkMismatch(A, ARef: TBGRABitmap): Integer;
begin
  if (A.Width <> ARef.Width) or (A.Height <> ARef.Height) then Exit(A.Width * A.Height);
  Result := Max(InkAgainst(A, ARef, GlobalBackground(ARef)),
    InkAgainst(A, ARef, LocalBackground(ARef)));
end;

function TyBlockMismatch(A, ARef: TBGRABitmap): Integer;
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
      for y := by to Min(by + CBlock, A.Height) - 1 do
      begin
        pa := A.ScanLine[y];
        pb := ARef.ScanLine[y];
        for x := bx to Min(bx + CBlock, A.Width) - 1 do
        begin
          ra := ra + pa[x].red; ga := ga + pa[x].green; ba := ba + pa[x].blue;
          rb := rb + pb[x].red; gb := gb + pb[x].green; bb := bb + pb[x].blue;
          Inc(n);
        end;
      end;
      if (Abs(ra - rb) > CBlockTolerance * n) or (Abs(ga - gb) > CBlockTolerance * n) or
        (Abs(ba - bb) > CBlockTolerance * n) then Inc(Result);
      Inc(bx, CBlock);
    end;
    Inc(by, CBlock);
  end;
end;

function TyInkMismatchImage(A, ARef: TBGRABitmap): TBGRABitmap;
var
  bg: TBgMap;
  la, lb, na, nb: TInkLevel;
  x, y, v: Integer;
begin
  Result := TBGRABitmap.Create(ARef.Width, ARef.Height, BGRAWhite);
  if (A.Width <> ARef.Width) or (A.Height <> ARef.Height) then Exit;
  bg := GlobalBackground(ARef);
  la := InkLevel(A, bg);
  lb := InkLevel(ARef, bg);
  na := NearMax(la, A.Width, A.Height);
  nb := NearMax(lb, A.Width, A.Height);
  for y := 0 to ARef.Height - 1 do
    for x := 0 to ARef.Width - 1 do
    begin
      v := ARef.GetPixel(x, y).green;
      v := 128 + v div 2;
      Result.SetPixel(x, y, BGRA(v, v, v, 255));
      if Uncovered(la[y][x], nb[y][x]) then
        Result.SetPixel(x, y, BGRA(255, 0, 0, 255))
      else if Uncovered(lb[y][x], na[y][x]) then
        Result.SetPixel(x, y, BGRA(0, 0, 255, 255));
    end;
end;

function TyRules(B: TBGRABitmap; const ABand: TRect; AVertical: Boolean;
  ATolerance: Integer): TTyIntArray;
var
  bg, p: TBGRAPixel;
  a, c, n, r, g, bl, x0, y0, x1, y1, a0, a1, c0, c1: Integer;
begin
  Result := nil;
  x0 := Max(ABand.Left, 0);
  y0 := Max(ABand.Top, 0);
  x1 := Min(ABand.Right, B.Width);
  y1 := Min(ABand.Bottom, B.Height);
  if (x1 <= x0) or (y1 <= y0) then Exit;
  bg := BackgroundIn(B, x0, y0, x1, y1);
  { a runs along the axis the rules are found on, c across the band. }
  if AVertical then
  begin
    a0 := x0; a1 := x1; c0 := y0; c1 := y1;
  end
  else
  begin
    a0 := y0; a1 := y1; c0 := x0; c1 := x1;
  end;
  for a := a0 to a1 - 1 do
  begin
    n := 0;
    for c := c0 to c1 - 1 do
    begin
      if AVertical then p := B.GetPixel(a, c) else p := B.GetPixel(c, a);
      r := p.red;
      g := p.green;
      bl := p.blue;
      if (Abs(r - bg.red) > ATolerance) or (Abs(g - bg.green) > ATolerance) or
        (Abs(bl - bg.blue) > ATolerance) then Inc(n);
    end;
    if n * 5 >= (c1 - c0) * 4 then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := a;
    end;
  end;
end;

function TyDoubledRules(const A: TTyIntArray): TTyIntArray;
var
  i: Integer;
begin
  SetLength(Result, 2 * Length(A));
  for i := 0 to High(A) do
  begin
    Result[2 * i] := 2 * A[i];
    Result[2 * i + 1] := 2 * A[i] + 1;
  end;
end;

procedure TyPaintAtBothScales(ABuild: TTyBuildForScale; AW, AH: Integer;
  out ARaster, ARef: TBGRABitmap);
var
  f1, f2: TForm;
  c1, c2: TControl;
begin
  ARaster := nil;
  ARef := nil;
  f1 := TForm.CreateNew(nil);
  f2 := TForm.CreateNew(nil);
  try
    f1.SetBounds(0, 0, AW + 40, AH + 40);
    f2.SetBounds(0, 0, AW + 40, AH + 40);
    c1 := ABuild(f1, 96);
    c1.SetBounds(0, 0, AW, AH);
    ARaster := TyPaintOwnSurface(c1, 2);
    c2 := ABuild(f2, 96);
    c2.SetBounds(0, 0, AW, AH);
    ARef := TyPaintOwnSurface(c2, 1);
  finally
    f2.Free;
    f1.Free;
  end;
end;

function TyDeviceScaleMismatchPictures(ABuild: TTyBuildForScale; AW, AH: Integer;
  out AScaled, ARef: TBGRABitmap; out AInk, ABlocks: Integer): Integer;
var
  raster: TBGRABitmap;
begin
  TyPaintAtBothScales(ABuild, AW, AH, raster, ARef);
  try
    AScaled := TyHalve(raster);
  finally
    raster.Free;
  end;
  AInk := TyInkMismatch(AScaled, ARef);
  ABlocks := TyBlockMismatch(AScaled, ARef);
  Result := AInk + ABlocks;
end;

function TyRulesText(const A: TTyIntArray): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(A) do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + IntToStr(A[i]);
  end;
end;

procedure TDeviceScaleCase.CheckScale(const AName: string; ABuild: TTyBuildForScale;
  AW, AH: Integer);
var
  a, b, d: TBGRABitmap;
  score, ink, blocks: Integer;
  dir: string;
  log: TextFile;
begin
  score := TyDeviceScaleMismatchPictures(ABuild, AW, AH, a, b, ink, blocks);
  try
    dir := GetEnvironmentVariable('TY_SWEEP_DIR');
    if ((score > CMaxMismatch) or (GetEnvironmentVariable('TY_SWEEP_ALL') <> '')) and (dir <> '') then
    begin
      { Every score, passing or not, for measuring the threshold against. }
      AssignFile(log, IncludeTrailingPathDelimiter(dir) + 'scores.txt');
      if FileExists(IncludeTrailingPathDelimiter(dir) + 'scores.txt') then Append(log) else Rewrite(log);
      WriteLn(log, Format('%-28s %5d  (ink %d, blocks %d)', [AName, score, ink, blocks]));
      CloseFile(log);
      a.SaveToFile(IncludeTrailingPathDelimiter(dir) + AName + '-s2.png');
      b.SaveToFile(IncludeTrailingPathDelimiter(dir) + AName + '-ref.png');
      d := TyInkMismatchImage(a, b);
      d.SaveToFile(IncludeTrailingPathDelimiter(dir) + AName + '-diff.png');
      d.Free;
    end;
  finally
    a.Free;
    b.Free;
  end;
  AssertTrue(Format('%s draws at the device scale (score %d > %d: ink %d, blocks %d)',
    [AName, score, CMaxMismatch, ink, blocks]), score <= CMaxMismatch);
end;

procedure TDeviceScaleCase.CheckRules(const AName: string; ABuild: TTyBuildForScale;
  AW, AH: Integer; const ABand: TRect; AVertical: Boolean; AMin, AMax: Integer);
var
  raster, ref: TBGRABitmap;
  rr, rs: TTyIntArray;
begin
  TyPaintAtBothScales(ABuild, AW, AH, raster, ref);
  try
    rs := TyRules(ref, ABand, AVertical, 4);
    rr := TyRules(raster, Rect(2 * ABand.Left, 2 * ABand.Top, 2 * ABand.Right, 2 * ABand.Bottom),
      AVertical, 4);
  finally
    raster.Free;
    ref.Free;
  end;
  AssertTrue(Format('%s at S = 1: %d to %d rules, found %s', [AName, AMin, AMax, TyRulesText(rs)]),
    (Length(rs) >= AMin) and (Length(rs) <= AMax));
  AssertEquals(AName + ' at S = 2: the S = 1 rules, one layout pixel wide',
    TyRulesText(TyDoubledRules(rs)), TyRulesText(rr));
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
