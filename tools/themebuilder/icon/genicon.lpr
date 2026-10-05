program genicon;
{ Renders the theme builder's application icon -- Lucide's "palette" in white on a rounded
  square of the default theme's accent -- and writes:

    <out.ico>   16, 24, 32, 48, 64 (32bpp DIB) and 256 (PNG) -- Windows: the exe's MAINICON
                (themebuilder.lpi, <Icon Value="0"/>, so the file sits beside the .lpi and is
                named after the project), the task bar, and the title bar (TTbMainForm.ShowAppIcon
                takes it from Application.Icon);
    <out.png>   the 256 px picture alone -- Linux / macOS, where a program's icon comes from a
                desktop entry or an app bundle, not from the executable.

  Every size is DRAWN at its own pixel size (the square, then the glyph from the bundled Lucide
  font at that size), never downscaled from 256 -- the same rule as tools/genappicon, and the
  same .ico layout for the same reason: LCL's icon reader takes a PNG entry only in the 256
  slot, and an entry it cannot read stops the program before its first window (see the long
  note at the top of tools/genappicon/genappicon.lpr). SelfCheck reads the file back through
  LCL's TIcon, the reader that would break.

  The glyph is centred on its INK, not on the font's box: it is drawn on a larger ground, its
  bounding box found, and that box centred on the square.

  Rebuild and rerun after changing anything here:
    lazbuild -B tools/themebuilder/icon/genicon.lpi
    tools/themebuilder/icon/genicon.exe tools/themebuilder/themebuilder.ico tools/themebuilder/icon/themebuilder-256.png [<preview-dir>]
  (from the repository root; scripts/gen-themebuilder-icon.ps1 does both). Then rebuild the
  theme builder: lazbuild links the .ico into its resource. }
{$mode objfpc}{$H+}
uses
  Interfaces, Classes, SysUtils, Math, Graphics, Forms,
  BGRABitmap, BGRABitmapTypes, BGRAGradientScanner,
  tyControls.Types, tyControls.IconFont, tyControls.Icons.Lucide;

const
  Sizes: array[0..5] of Integer = (16, 24, 32, 48, 64, 256);
  IcoDibMax = 64;            { at or below: 32bpp DIB; above: PNG (LCL reads PNG only at 256) }
  cGlyph = 'palette';
  cAccent: TBGRAPixel = (blue: $F6; green: $82; red: $3B; alpha: 255);     { --accent, light.tycss }
  cAccentTop: TBGRAPixel = (blue: $FA; green: $9E; red: $60; alpha: 255);  { a restrained lift }

{ ------------------------------------------------------------------ drawing -- }

{ the glyph AName in white, ASizePx em, cut to its ink: a bitmap just as big as the strokes }
function InkOf(const AName: string; ASizePx: Integer): TBGRABitmap;
var
  ground: TBGRABitmap;
  s: string;
  x, y, l, t, r, b: Integer;
  p: PBGRAPixel;
begin
  s := TyLucideFont.GlyphText(AName);
  if s = '' then
    raise Exception.CreateFmt('the Lucide font has no glyph "%s"', [AName]);
  ground := TBGRABitmap.Create(ASizePx * 3, ASizePx * 3, BGRAPixelTransparent);
  try
    ground.FontName := TyLucideFont.FontFamily;
    ground.FontHeight := ASizePx;
    ground.FontQuality := fqFineAntialiasing;
    ground.FontStyle := [];
    ground.TextOut(ASizePx, ASizePx, s, BGRAWhite);
    l := MaxInt; t := MaxInt; r := -1; b := -1;
    for y := 0 to ground.Height - 1 do
    begin
      p := ground.ScanLine[y];
      for x := 0 to ground.Width - 1 do
      begin
        if p^.alpha > 0 then
        begin
          if x < l then l := x;
          if x > r then r := x;
          if y < t then t := y;
          if y > b then b := y;
        end;
        Inc(p);
      end;
    end;
    if r < 0 then
      raise Exception.CreateFmt('the glyph "%s" drew nothing (is the font registered?)', [AName]);
    Result := ground.GetPart(Rect(l, t, r + 1, b + 1)) as TBGRABitmap;
  finally
    ground.Free;
  end;
end;

procedure DrawIcon(b: TBGRABitmap; Px: Integer);
var
  grad: TBGRAGradientScanner;
  inset, rad, sc: single;
  ink: TBGRABitmap;
  em: Integer;
begin
  sc := Px / 64.0;
  { a hair of inset keeps the antialiased corner off the edge pixel; at 16 and 24 px there is
    no room for it, so the square goes full bleed -- as tools/genappicon draws the Ty mark }
  if Px >= 32 then inset := 1.5 * sc else inset := 0.0;
  rad := 13.0 * sc;
  grad := TBGRAGradientScanner.Create(cAccentTop, cAccent, gtLinear,
    PointF(0, inset), PointF(0, Px - inset));
  try
    b.FillRoundRectAntialias(inset, inset, Px - inset, Px - inset, rad, rad, grad);
  finally
    grad.Free;
  end;
  { Lucide draws in a 24 grid with 2 units of air: an em of ~0.8 of the square leaves the ink
    at ~two thirds of it, the proportion of a system icon's symbol on its plate }
  em := Max(10, Round(Px * 0.8));
  ink := InkOf(cGlyph, em);
  try
    b.PutImage((Px - ink.Width) div 2, (Px - ink.Height) div 2, ink, dmDrawWithTransparency);
  finally
    ink.Free;
  end;
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

{ 32bpp bottom-up DIB with a real 1bpp AND mask (tools/genappicon has the reasons) }
function DibEntry(b: TBGRABitmap): TMemoryStream;
var
  x, y, i, maskStride: Integer;
  p: PBGRAPixel;
  row: array of Byte;
begin
  Result := TMemoryStream.Create;
  WriteDWordLE(Result, 40);
  WriteDWordLE(Result, LongWord(b.Width));
  WriteDWordLE(Result, LongWord(b.Height * 2));
  WriteWordLE(Result, 1);
  WriteWordLE(Result, 32);
  WriteDWordLE(Result, 0);
  WriteDWordLE(Result, LongWord(b.Width * b.Height * 4));
  for i := 1 to 4 do WriteDWordLE(Result, 0);
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
    WriteWordLE(ico, 0);
    WriteWordLE(ico, 1);
    WriteWordLE(ico, Word(Length(Bmps)));
    offset := 6 + 16 * Length(Bmps);
    for i := 0 to High(Bmps) do
    begin
      if Bmps[i].Width >= 256 then wh := 0 else wh := Byte(Bmps[i].Width);
      ico.WriteByte(wh);
      ico.WriteByte(wh);
      ico.WriteByte(0);
      ico.WriteByte(0);
      WriteWordLE(ico, 1);
      WriteWordLE(ico, 32);
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

{ read back through LCL's TIcon: an entry it cannot read is a program that never shows its
  window (tools/genappicon) }
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

{ every size at 1:1 over a light and a dark strip, the three smallest at 8x: to be looked at }
procedure WriteSheet(const FileName: string; const Bmps: array of TBGRABitmap);
const
  Pad = 16;
  Zoom = 8;
var
  sheet, big: TBGRABitmap;
  i, x, y, w, h, zx: Integer;
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
      sheet.PutImage(x, Pad + 256 + Pad + 256 - Bmps[i].Height, Bmps[i], dmDrawWithTransparency);
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

var
  OutIco, OutPng, PreviewDir: string;
  Bmps: array of TBGRABitmap;
  i: Integer;
  Total: Int64;
begin
  if ParamCount < 2 then
  begin
    writeln('usage: genicon <out.ico> <out-256.png> [<preview-dir>]');
    Halt(1);
  end;
  Application.Initialize;     { the font is registered through the widgetset }
  OutIco := ExpandFileName(ParamStr(1));
  OutPng := ExpandFileName(ParamStr(2));
  if (ParamCount >= 3) and (ParamStr(3) <> '') then
    PreviewDir := IncludeTrailingPathDelimiter(ExpandFileName(ParamStr(3)))
  else
    PreviewDir := '';
  if not TyLucideFont.Available then
  begin
    writeln('the bundled Lucide font did not load: ', TyLucideFont.LoadError);
    Halt(2);
  end;
  ForceDirectories(ExtractFileDir(OutIco));
  ForceDirectories(ExtractFileDir(OutPng));
  if PreviewDir <> '' then ForceDirectories(PreviewDir);

  SetLength(Bmps, Length(Sizes));
  for i := 0 to High(Sizes) do
  begin
    Bmps[i] := TBGRABitmap.Create(Sizes[i], Sizes[i], BGRAPixelTransparent);
    DrawIcon(Bmps[i], Sizes[i]);
    if PreviewDir <> '' then
      Bmps[i].SaveToFile(PreviewDir + 'themebuilder-' + IntToStr(Sizes[i]) + '.png');
  end;
  if PreviewDir <> '' then WriteSheet(PreviewDir + 'sheet.png', Bmps);
  Bmps[High(Bmps)].SaveToFile(OutPng);
  Total := WriteIco(OutIco, Bmps);
  for i := 0 to High(Bmps) do Bmps[i].Free;
  writeln('Wrote ', OutIco, ' (', Length(Sizes), ' sizes, ', Total, ' bytes) and ', OutPng);
  SelfCheck(OutIco, Length(Sizes));
end.
