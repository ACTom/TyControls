program genappicon;
{ Renders the shared TyControls application mark and writes a multi-size .ico.

  Every size is DRAWN at its native pixel size from one 64-unit design space
  (the same trick tools/genicons uses) rather than downscaled from 256 -- a
  16px icon resampled from 256 is mush, a 16px icon drawn at 16px is not.

  WHY THE SIZE LIST LOOKS LIKE THAT
  ---------------------------------
  Windows reads PNG-compressed .ico entries at any size (Vista+), and it does so
  correctly here -- LoadImage against the linked .exe returns a real 32bpp bitmap
  for every entry. LCL DOES NOT, and it is not a matter of degree:

    lcl/include/icon.inc, TCustomIcon.ReadStream
      if (IconDir[n].bWidth = 0) or (IconDir[n].bHeight = 0) then
        ... sniff for the PNG signature, use TLazReaderPNG ...
      else
        ... TLazReaderDIB, unconditionally ...

  So LCL only even LOOKS for a PNG at the one slot the format stores as zero --
  256. A PNG entry at any other size goes to the DIB reader, which reads the
  PNG's IHDR width where biCompression should be (64 -> 0x40000000) and raises
  FPImageException in lcl/intfgraphics.pas.

  Where that lands is what makes it invisible. TApplication.Initialize resolves
  MAINICON itself (lcl/include/application.inc, the FindResource/RT_GROUP_ICON
  block) -- and TIcon.LoadFromResourceHandle does not ask Windows for one size,
  it concatenates EVERY RT_ICON back into a synthetic .ico and parses all of
  them. So one bad entry throws inside Initialize, which runs BEFORE
  Application.CreateForm and before Application.Run. No main form is ever built,
  Run is never reached, and the exception arrives after the AppInitialized flag
  is set, so it goes looking for a modal dialog that never appears. The process
  burns ~11s of CPU and then sits there forever with nothing on screen. Every
  one of the 46 examples did exactly that before this list was cut back.

  Hence: 16..64 as classic 32bpp DIB (what LCL can read) plus 256 as PNG (the
  one slot where LCL sniffs, so both readers are happy). 128 is left out because
  as a DIB it is 67KB -- more than the whole rest of the file -- and Windows
  downsamples the native 256 for it. Total ~40KB, linked into all 46 examples.

  SelfCheck at the end is the guard: it loads what it just wrote back through
  LCL's own TIcon, which is the reader that breaks. Adding a size here without
  running this tool is how the trap gets re-armed.

  Usage: genappicon <out.ico> [<preview-dir> [<dib-max> [<size-max>]]]
         The two optional numbers exist to reproduce the bad configurations on
         purpose; the defaults are what ships.
}
{$mode objfpc}{$H+}
uses
  Interfaces, Classes, SysUtils, Math, Graphics,
  BGRABitmap, BGRABitmapTypes, BGRAGradientScanner;

const
  { Sizes at or below this go in as DIB; above, as PNG. See the note up top --
    this is a hard limit of LCL's icon reader, not a preference. }
  IcoDibMaxDefault = 64;
  IcoMaxSizeDefault = 256;
  Sizes: array[0..5] of Integer = (16, 24, 32, 48, 64, 256);

var
  IcoDibMax: Integer = IcoDibMaxDefault;
  IcoMaxSize: Integer = IcoMaxSizeDefault;

var
  { Design space is 64 units square; GScale maps it onto the output size. }
  GScale: single = 1.0;

function S(v: single): single; inline;
begin
  Result := v * GScale;
end;

{ ---------------------------------------------------------------- the mark -- }

{ "Ty" -- a cap T over a lowercase y, built from rects and quads so the weight
  is identical at every size and no cap-style guesswork enters the shape. The
  arms of the y are cut horizontally (as a typeface cuts them), which is why
  they are quads rather than strokes. Authored on the 64 grid: x 10.4..53.65,
  y 14..50, so the glyph is centred in the square. }
procedure DrawMark(b: TBGRABitmap; Px: Integer);
var
  Accent, AccentTop: TBGRAPixel;
  grad: TBGRAGradientScanner;
  inset, rad: single;
  Snap: Boolean;

  procedure Quad(x1, y1, x2, y2, x3, y3, x4, y4: single);
  begin
    b.FillPolyAntialias([PointF(S(x1), S(y1)), PointF(S(x2), S(y2)),
                         PointF(S(x3), S(y3)), PointF(S(x4), S(y4))], BGRAWhite);
  end;

  { The T is all horizontal and vertical edges, so at the sizes where a half-lit
    pixel is a large fraction of the stroke it is worth snapping the rect to the
    pixel grid: 16px goes from a grey smear to a crisp 5x1 bar over a 1x6 stem.
    The y is diagonal and gains nothing from snapping. }
  procedure Bar(x1, y1, x2, y2: single);
  var
    l, t, r, bt: single;
  begin
    l := S(x1); t := S(y1); r := S(x2); bt := S(y2);
    if Snap then
    begin
      { Round the ORIGIN and the EXTENT, not the two edges: rounding edges turns
        a 1.5px crossbar into 1px (4.0 and 5.0 both land on their own integer),
        where rounding the extent keeps the 2px the design asks for. }
      l := Floor(l + 0.5); t := Floor(t + 0.5);
      r := l + Max(1, Floor(r - S(x1) + 0.5));
      bt := t + Max(1, Floor(bt - S(y1) + 0.5));
    end;
    b.FillRectAntialias(l, t, r, bt, BGRAWhite);
  end;

begin
  GScale := Px / 64.0;

  Accent    := BGRA($3B, $82, $F6, 255);   { --accent in themes/light.tycss }
  AccentTop := BGRA($60, $9E, $FA, 255);   { a restrained lift, not a gloss }

  { A hair of inset keeps the antialiased corner off the very edge pixel; at
    16 and 24px there is no room for it, so the square goes full bleed. }
  if Px >= 32 then inset := 1.5 else inset := 0.0;
  rad := 13.0;
  Snap := Px <= 32;

  grad := TBGRAGradientScanner.Create(AccentTop, Accent, gtLinear,
    PointF(0, S(inset)), PointF(0, S(64 - inset)));
  try
    b.FillRoundRectAntialias(S(inset), S(inset), S(64 - inset), S(64 - inset),
      S(rad), S(rad), grad);
  finally
    grad.Free;
  end;

  { T -- crossbar and stem. }
  Bar(10.4, 14, 32.4, 20);
  Bar(18.4, 14, 24.4, 41);

  { y -- the short arm runs into the long one, which carries the descender.
    The short arm stops at y=38.3, the height at which its edges meet the long
    arm's: run it any further and its flat cut protrudes past the long arm's
    right edge as a spur, because the two strokes lean opposite ways. }
  Quad(47.15, 21, 53.65, 21, 41.65, 50, 35.15, 50);
  Quad(31.58, 21, 38.22, 21, 46.46, 38.3, 39.82, 38.3);
end;

{ ------------------------------------------------------------- .ico writing -- }

procedure WriteWordLE(st: TStream; v: Word);
begin
  st.WriteBuffer(v, 2);
end;

procedure WriteDWordLE(st: TStream; v: LongWord);
begin
  st.WriteBuffer(v, 4);
end;

{ 32bpp bottom-up DIB with a real 1bpp AND mask -- a few legacy paths still
  consult it, and an all-zero mask would square off the rounded corners there. }
function DibEntry(b: TBGRABitmap): TMemoryStream;
var
  x, y, i, maskStride: Integer;
  p: PBGRAPixel;
  row: array of Byte;
begin
  Result := TMemoryStream.Create;
  WriteDWordLE(Result, 40);                        { biSize }
  WriteDWordLE(Result, LongWord(b.Width));         { biWidth }
  WriteDWordLE(Result, LongWord(b.Height * 2));    { biHeight: XOR + AND }
  WriteWordLE(Result, 1);                          { biPlanes }
  WriteWordLE(Result, 32);                         { biBitCount }
  WriteDWordLE(Result, 0);                         { biCompression = BI_RGB }
  WriteDWordLE(Result, LongWord(b.Width * b.Height * 4));
  for i := 1 to 4 do WriteDWordLE(Result, 0);      { ppm x2, clrUsed, clrImportant }

  for y := b.Height - 1 downto 0 do
  begin
    p := b.ScanLine[y];
    for x := 0 to b.Width - 1 do
    begin
      Result.WriteByte(p^.blue);
      Result.WriteByte(p^.green);
      Result.WriteByte(p^.red);
      Result.WriteByte(p^.alpha);
      Inc(p);
    end;
  end;

  maskStride := ((b.Width + 31) div 32) * 4;
  SetLength(row, maskStride);
  for y := b.Height - 1 downto 0 do
  begin
    FillChar(row[0], maskStride, 0);
    p := b.ScanLine[y];
    for x := 0 to b.Width - 1 do
    begin
      if p^.alpha < 128 then
        row[x div 8] := row[x div 8] or (128 shr (x mod 8));
      Inc(p);
    end;
    Result.WriteBuffer(row[0], maskStride);
  end;
end;

function PngEntry(b: TBGRABitmap): TMemoryStream;
begin
  Result := TMemoryStream.Create;
  b.SaveToStreamAs(Result, ifPng);
end;

function WriteIco(const FileName: string; const Bmps: array of TBGRABitmap): Int64;
var
  ico: TFileStream;
  data: array of TMemoryStream;
  i, offset: Integer;
  wh: Byte;
begin
  SetLength(data, Length(Bmps));
  for i := 0 to High(Bmps) do
    if Bmps[i].Width <= IcoDibMax then
      data[i] := DibEntry(Bmps[i])
    else
      data[i] := PngEntry(Bmps[i]);

  ico := TFileStream.Create(FileName, fmCreate);
  try
    WriteWordLE(ico, 0);                        { reserved }
    WriteWordLE(ico, 1);                        { type: icon }
    WriteWordLE(ico, Word(Length(Bmps)));

    offset := 6 + 16 * Length(Bmps);
    for i := 0 to High(Bmps) do
    begin
      if Bmps[i].Width >= 256 then wh := 0 else wh := Byte(Bmps[i].Width);
      ico.WriteByte(wh);                        { bWidth  (0 means 256) }
      ico.WriteByte(wh);                        { bHeight }
      ico.WriteByte(0);                         { bColorCount }
      ico.WriteByte(0);                         { bReserved }
      WriteWordLE(ico, 1);                      { wPlanes }
      WriteWordLE(ico, 32);                     { wBitCount }
      WriteDWordLE(ico, LongWord(data[i].Size));
      WriteDWordLE(ico, LongWord(offset));
      Inc(offset, Integer(data[i].Size));
    end;

    for i := 0 to High(Bmps) do
    begin
      data[i].Position := 0;
      ico.CopyFrom(data[i], data[i].Size);
    end;
    Result := ico.Size;
  finally
    ico.Free;
    for i := 0 to High(data) do data[i].Free;
  end;
end;

{ --------------------------------------------------------------- self-check -- }

{ Read the file back through LCL's TIcon -- the same reader every LCL program
  runs over MAINICON at startup, and the one that cannot parse a PNG-compressed
  entry. An entry LCL rejects is not a cosmetic loss: it is a program that never
  shows its window. Anything LCL silently drops (the 256 entry) is reported so
  the count is never mistaken for a promise. }
procedure SelfCheck(const FileName: string; Expected: Integer);
var
  ic: TIcon;
  i: Integer;
  fmt: TPixelFormat;
  w, h: Word;
  got: string;
begin
  ic := TIcon.Create;
  try
    try
      ic.LoadFromFile(FileName);
    except
      on E: Exception do
      begin
        writeln('SELF-CHECK FAILED: LCL TIcon cannot read the file just written: ',
                E.ClassName, ': ', E.Message);
        Halt(3);
      end;
    end;
    got := '';
    for i := 0 to ic.Count - 1 do
    begin
      ic.GetDescription(i, fmt, h, w);
      got := got + Format(' %dx%d', [w, h]);
    end;
    writeln('  LCL TIcon reads', got, '  (', ic.Count, ' of ', Expected, ' written)');
    if ic.Count = 0 then
    begin
      writeln('SELF-CHECK FAILED: LCL read no entries at all.');
      Halt(3);
    end;
  finally
    ic.Free;
  end;
end;

{ ------------------------------------------------------------ contact sheet -- }

{ A single reviewable image: every size at 1:1 over a light and a dark strip,
  then the three smallest magnified 8x so pixel-level legibility can be judged
  without squinting. Nothing here ships -- it exists to be looked at. }
procedure WriteSheet(const FileName: string; const Bmps: array of TBGRABitmap);
const
  Pad = 16;
  Zoom = 8;
var
  sheet: TBGRABitmap;
  i, x, y, w, h, zx: Integer;
  big: TBGRABitmap;
begin
  w := Pad;
  for i := 0 to High(Bmps) do Inc(w, Bmps[i].Width + Pad);
  h := Pad + 256 + Pad + 256 + Pad;
  zx := Pad;
  for i := 0 to 2 do Inc(zx, Bmps[i].Width * Zoom + Pad);
  if zx > w then w := zx;
  Inc(h, 32 * Zoom + Pad);

  sheet := TBGRABitmap.Create(w, h, BGRA($F5, $F5, $F5, 255));
  try
    sheet.FillRect(0, Pad + 256 + Pad div 2, w, Pad + 256 + Pad div 2 + 256 + Pad,
      BGRA($20, $24, $2C, 255), dmSet);
    x := Pad;
    for i := 0 to High(Bmps) do
    begin
      sheet.PutImage(x, Pad + 256 - Bmps[i].Height, Bmps[i], dmDrawWithTransparency);
      sheet.PutImage(x, Pad + 256 + Pad + 256 - Bmps[i].Height, Bmps[i],
        dmDrawWithTransparency);
      Inc(x, Bmps[i].Width + Pad);
    end;

    y := Pad + 256 + Pad + 256 + Pad;
    x := Pad;
    for i := 0 to 2 do
    begin
      big := Bmps[i].Resample(Bmps[i].Width * Zoom, Bmps[i].Height * Zoom,
        rmSimpleStretch) as TBGRABitmap;
      try
        sheet.PutImage(x, y, big, dmDrawWithTransparency);
      finally
        big.Free;
      end;
      Inc(x, Bmps[i].Width * Zoom + Pad);
    end;

    sheet.SaveToFile(FileName);
  finally
    sheet.Free;
  end;
end;

{ ------------------------------------------------------------------- main -- }

var
  OutIco, PreviewDir: string;
  Bmps: array of TBGRABitmap;
  i, n: Integer;
  Total: Int64;
begin
  if ParamCount < 1 then
  begin
    writeln('usage: genappicon <out.ico> [<preview-dir> [<dib-max> [<size-max>]]]');
    Halt(1);
  end;
  OutIco := ExpandFileName(ParamStr(1));
  { An EMPTY second argument means "no preview" -- ExpandFileName('') is the
    current directory, which would scatter the preview PNGs wherever this ran. }
  if (ParamCount >= 2) and (ParamStr(2) <> '') then
    PreviewDir := IncludeTrailingPathDelimiter(ExpandFileName(ParamStr(2)))
  else
    PreviewDir := '';
  if ParamCount >= 3 then IcoDibMax := StrToInt(ParamStr(3));
  if ParamCount >= 4 then IcoMaxSize := StrToInt(ParamStr(4));

  ForceDirectories(ExtractFileDir(OutIco));
  if PreviewDir <> '' then ForceDirectories(PreviewDir);

  n := 0;
  for i := 0 to High(Sizes) do
    if Sizes[i] <= IcoMaxSize then Inc(n);
  SetLength(Bmps, n);
  for i := 0 to n - 1 do
  begin
    Bmps[i] := TBGRABitmap.Create(Sizes[i], Sizes[i], BGRAPixelTransparent);
    DrawMark(Bmps[i], Sizes[i]);
    if PreviewDir <> '' then
      Bmps[i].SaveToFile(PreviewDir + 'ty-' + IntToStr(Sizes[i]) + '.png');
  end;
  if PreviewDir <> '' then WriteSheet(PreviewDir + 'sheet.png', Bmps);

  Total := WriteIco(OutIco, Bmps);
  for i := 0 to High(Bmps) do Bmps[i].Free;

  writeln('Wrote ', OutIco, ' (', n, ' sizes, ', Total, ' bytes)');
  SelfCheck(OutIco, n);
end.
