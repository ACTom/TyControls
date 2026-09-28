program fontprobe;
{$mode objfpc}{$H+}
{$APPTYPE CONSOLE}
{ The two experiments the terminal's phase 3 plan runs before the renderer is written
  (plan Task 0, "E1" and "E2"). Builds from source/ without the package; makes no
  window, only bitmaps, through the library's own text path (TyConfigureTextFont).

    fontprobe --e1 | --e2 [--out <dir>]

  --e1  font fallback: for 9 and 12 pt at 96 and 144 PPI, the cell metrics of the
        platform's fixed-pitch face, then for each sample cluster (Latin, CJK, emoji,
        box drawing, Powerline, a combining mark, two missing-glyph references) its
        advance in cells, its ink box relative to the cell, and whether it is missing,
        in colour, or cut off at the bottom; the CJK and emoji again in the platform's
        CJK face. One PNG per setting in <dir> (default ./fontprobe-out).
  --e2  glyph masks: 9 pt at 96 and 144 PPI, three ways of turning a glyph into
        something cacheable -- (a) 3x supersampled and resampled, (b) drawn straight
        in its colours, (c) drawn black on white at 1x and taken as coverage -- each
        compared with TTyPainter.DrawText (how the rest of the library draws text) in
        three colour pairs; then the time to rasterize 95 ASCII glyphs in 4 styles
        cold, and to repaint a 200 x 60 grid from cached masks.

  Not part of the package; the numbers go into the phase 3 plan's experiment record. }

uses
  Interfaces, SysUtils, Classes, Math, Types, Graphics, FPWritePNG,
  BGRABitmap, BGRABitmapTypes, BGRAGrayscaleMask, BGRABlend,
  tyControls.Types, tyControls.Painter, tyControls.Terminal.Core;

const
  {$IFDEF MSWINDOWS}
  MainFont = 'Consolas';
  WideFont = 'Microsoft YaHei';
  UiFont = 'Segoe UI';
  {$ELSE}
  {$IFDEF DARWIN}
  MainFont = 'Menlo';
  WideFont = 'PingFang SC';
  UiFont = 'Helvetica Neue';
  {$ELSE}
  MainFont = 'Monospace';
  WideFont = 'Noto Sans CJK SC';
  UiFont = 'Sans';
  {$ENDIF}
  {$ENDIF}

var
  OutDir: string = 'fontprobe-out';

function Cp(u: Cardinal): string;
begin
  if u < $80 then Result := Chr(u)
  else if u < $800 then Result := Chr($C0 or (u shr 6)) + Chr($80 or (u and $3F))
  else if u < $10000 then Result := Chr($E0 or (u shr 12)) + Chr($80 or ((u shr 6) and $3F)) + Chr($80 or (u and $3F))
  else Result := Chr($F0 or (u shr 18)) + Chr($80 or ((u shr 12) and $3F)) + Chr($80 or ((u shr 6) and $3F)) + Chr($80 or (u and $3F));
end;

function Cps(const A: array of Cardinal): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(A) do Result := Result + Cp(A[i]);
end;

function Median5(var A: array of Double): Double;
var
  i, j: Integer;
  t: Double;
begin
  for i := 0 to High(A) do
    for j := i + 1 to High(A) do
      if A[j] < A[i] then begin t := A[i]; A[i] := A[j]; A[j] := t; end;
  Result := A[Length(A) div 2];
end;

{ ---- E1 ------------------------------------------------------------------------- }

type
  TSample = record
    Name, Text: string;
    Wide: Boolean;           { measured again in the CJK face }
  end;
  TInk = record
    Any: Boolean;
    L, T, R, B: Integer;     { inclusive }
    Coloured: Boolean;
  end;

function InkOf(ABmp: TBGRABitmap): TInk;
var
  x, y, mx, mn: Integer;
  p: PBGRAPixel;
begin
  Result := Default(TInk);
  Result.L := MaxInt; Result.T := MaxInt; Result.R := -1; Result.B := -1;
  for y := 0 to ABmp.Height - 1 do
  begin
    p := ABmp.ScanLine[y];
    for x := 0 to ABmp.Width - 1 do
    begin
      if (p^.red < 255) or (p^.green < 255) or (p^.blue < 255) then
      begin
        Result.Any := True;
        if x < Result.L then Result.L := x;
        if x > Result.R then Result.R := x;
        if y < Result.T then Result.T := y;
        if y > Result.B then Result.B := y;
        mx := Max(p^.red, Max(p^.green, p^.blue));
        mn := Min(p^.red, Min(p^.green, p^.blue));
        if mx - mn > 40 then Result.Coloured := True;
      end;
      Inc(p);
    end;
  end;
end;

function SameImage(A, B: TBGRABitmap): Boolean;
var
  y: Integer;
begin
  Result := (A.Width = B.Width) and (A.Height = B.Height);
  if not Result then Exit;
  for y := 0 to A.Height - 1 do
    if not CompareMem(A.ScanLine[y], B.ScanLine[y], A.Width * SizeOf(TBGRAPixel)) then Exit(False);
end;

function RenderSample(const AText, AFont: string; ASize, APPI, AW, AH, APad: Integer): TBGRABitmap;
begin
  Result := TBGRABitmap.Create(AW, AH, BGRAWhite);
  TyConfigureTextFont(Result, AFont, ASize, 400, APPI);
  Result.TextOut(APad, APad, AText, BGRABlack);
end;

procedure RunE1;
const
  Sizes: array[0..1] of Integer = (9, 12);
  PPIs: array[0..1] of Integer = (96, 144);
var
  samples: array of TSample;
  meas, img, refA, refB, sheet: TBGRABitmap;
  si, pi_, k, fk, cellW, cellH, w, h, pad, sheetY, mainBottom: Integer;
  m: TFontPixelMetric;
  sz, szAg, szZh: TSize;
  ink: TInk;
  font, cfg: string;
  missing, cut: Boolean;
  inkBottoms: array of Integer;

  procedure Add(const AName, AText: string; AWide: Boolean);
  begin
    SetLength(samples, Length(samples) + 1);
    samples[High(samples)].Name := AName;
    samples[High(samples)].Text := AText;
    samples[High(samples)].Wide := AWide;
  end;

begin
  Add('W', 'W', False);
  Add('g', 'g', False);
  Add('|', '|', False);
  Add('U+4E2D', Cp($4E2D), True);
  Add('U+6587', Cp($6587), True);
  Add('U+3042', Cp($3042), True);
  Add('U+D55C', Cp($D55C), True);
  Add('U+20000', Cp($20000), True);
  Add('U+1F600', Cp($1F600), True);
  Add('U+1F44D+1F3FD', Cps([$1F44D, $1F3FD]), True);
  Add('U+1F1E8+1F1F3', Cps([$1F1E8, $1F1F3]), True);
  Add('U+2500', Cp($2500), False);
  Add('U+2502', Cp($2502), False);
  Add('U+253C', Cp($253C), False);
  Add('U+2588', Cp($2588), False);
  Add('U+E0B0', Cp($E0B0), False);
  Add('U+E0A0', Cp($E0A0), False);
  Add('e+U+0301', 'e' + Cp($0301), False);
  Add('ref U+10FFFD', Cp($10FFFD), False);
  Add('ref U+0378', Cp($0378), False);
  SetLength(inkBottoms, Length(samples));

  ForceDirectories(OutDir);
  WriteLn('E1  font fallback; main ', MainFont, ', wide candidate ', WideFont);
  for k := 0 to 3 do
  begin
    meas := TBGRABitmap.Create(1, 1);
    try
      TyConfigureTextFont(meas, MainFont, Sizes[k div 2], 400, PPIs[k mod 2]);
      m := meas.FontPixelMetric;
      szAg := meas.TextSize('Ag');
      szZh := meas.TextSize(Cp($4E2D));
      cellW := Ceil(meas.TextSize(StringOfChar('W', 32)).cx / 32);
    finally
      meas.Free;
    end;
    cellH := m.Lineheight;
    if (not m.Defined) or (cellH <= 0) then cellH := szAg.cy;
    cfg := Format('%dpt@%d', [Sizes[k div 2], PPIs[k mod 2]]);
    WriteLn;
    WriteLn(Format('== %s  metric defined=%s baseline=%d xLine=%d capLine=%d descent=%d lineheight=%d  TextSize(Ag).cy=%d TextSize(zh).cy=%d cellW=%d cellH=%d',
      [cfg, BoolToStr(m.Defined, True), m.Baseline, m.xLine, m.CapLine, m.DescentLine, m.Lineheight,
       szAg.cy, szZh.cy, cellW, cellH]));
    WriteLn(Format('%-16s %-18s %6s  %-22s %-7s %-6s %-4s', ['cluster', 'font', 'adv', 'ink (x0,y0)-(x1,y1)', 'missing', 'colour', 'cut']));
    pad := cellH;
    w := cellW * 6 + 2 * pad;
    h := cellH + 2 * pad;
    sheet := TBGRABitmap.Create(w * 2, h * Length(samples), BGRA(240, 240, 240));
    try
      for fk := 0 to 1 do
      begin
        if fk = 0 then font := MainFont else font := WideFont;
        refA := RenderSample(Cp($10FFFD), font, Sizes[k div 2], PPIs[k mod 2], w, h, pad);
        refB := RenderSample(Cp($0378), font, Sizes[k div 2], PPIs[k mod 2], w, h, pad);
        try
          for si := 0 to High(samples) do
          begin
            if (fk = 1) and not samples[si].Wide then Continue;
            meas := TBGRABitmap.Create(1, 1);
            try
              TyConfigureTextFont(meas, font, Sizes[k div 2], 400, PPIs[k mod 2]);
              sz := meas.TextSize(samples[si].Text);
            finally
              meas.Free;
            end;
            img := RenderSample(samples[si].Text, font, Sizes[k div 2], PPIs[k mod 2], w, h, pad);
            try
              ink := InkOf(img);
              missing := (not ink.Any) or ((Pos('ref', samples[si].Name) = 0) and (SameImage(img, refA) or SameImage(img, refB)));
              { cut: the ink reaches the last row of the text box BGRA sized the mask by
                (TextExtent + 1). The second test of the plan -- the same glyph inks 15% of
                a cell lower in the CJK face -- is printed on the CJK face's row: it says
                the main face's glyph MAY be cut (the PNG settles it), and it also says
                how far the CJK face would overflow the cell. }
              cut := ink.Any and (ink.B >= pad + sz.cy - 1);
              if fk = 0 then
                inkBottoms[si] := ink.B
              else if ink.Any then
              begin
                mainBottom := inkBottoms[si];
                WriteLn(Format('   (%s in %s: ink bottom %d px lower than %s%s; ink bottom row %d of a %d px cell%s)',
                  [samples[si].Name, font, ink.B - mainBottom, MainFont,
                   BoolToStr(ink.B - mainBottom >= Ceil(0.15 * cellH), ', 15% of a cell or more', ''),
                   ink.B - pad, cellH, BoolToStr(ink.B - pad >= cellH, ' -- OVERFLOWS the cell', '')]));
              end;
              if ink.Any then
                WriteLn(Format('%-16s %-18s %6.2f  (%d,%d)-(%d,%d)%s %-7s %-6s %-4s',
                  [samples[si].Name, font, sz.cx / cellW, ink.L - pad, ink.T - pad, ink.R - pad, ink.B - pad,
                   StringOfChar(' ', Max(0, 22 - Length(Format('(%d,%d)-(%d,%d)', [ink.L - pad, ink.T - pad, ink.R - pad, ink.B - pad])))),
                   BoolToStr(missing, 'MISSING', '-'), BoolToStr(ink.Coloured, 'colour', '-'), BoolToStr(cut, 'CUT', '-')]))
              else
                WriteLn(Format('%-16s %-18s %6.2f  %-22s %-7s %-6s %-4s',
                  [samples[si].Name, font, sz.cx / cellW, 'no ink', 'MISSING', '-', '-']));
              sheetY := si * h;
              sheet.PutImage(fk * w, sheetY, img, dmSet);
              { the cell grid of the main face, for the eye }
              sheet.Rectangle(fk * w + pad, sheetY + pad, fk * w + pad + cellW * 2, sheetY + pad + cellH, BGRA(0, 160, 255), dmSet);
            finally
              img.Free;
            end;
          end;
        finally
          refA.Free;
          refB.Free;
        end;
      end;
      sheet.SaveToFile(IncludeTrailingPathDelimiter(OutDir) + 'e1-' + cfg + '.png');
    finally
      sheet.Free;
    end;
  end;
end;

{ ---- E2 ------------------------------------------------------------------------- }

type
  TColorPair = record Fg, Bg: TBGRAPixel; Name: string; end;
  TMethod = (mRef, mA, mB, mC, mCLinear, mCOwn);

const
  MethodNames: array[TMethod] of string = ('ref', '(a) 3x', '(b) direct', '(c) mask', '(c) mask linear', '(c) own loop');

function PixelOf(ARgb: Cardinal): TBGRAPixel;
begin
  Result := BGRA((ARgb shr 16) and $FF, (ARgb shr 8) and $FF, ARgb and $FF, 255);
end;

function CoverageMask(ASrc: TBGRABitmap): TGrayscaleMask;
var
  x, y: Integer;
  p: PBGRAPixel;
  q: PByte;
begin
  Result := TGrayscaleMask.Create(ASrc.Width, ASrc.Height, 0);
  for y := 0 to ASrc.Height - 1 do
  begin
    p := ASrc.ScanLine[y];
    q := Result.ScanLine[y];
    for x := 0 to ASrc.Width - 1 do
    begin
      q^ := 255 - (p^.red + p^.green + p^.blue) div 3;
      Inc(p);
      Inc(q);
    end;
  end;
end;

procedure BlendMask(ADest: TBGRABitmap; AX, AY: Integer; AMask: TGrayscaleMask; AInk: TBGRAPixel);
var
  x, y, x0, x1, dy: Integer;
  src: PByte;
  dst: PBGRAPixel;
  c: TBGRAPixel;
begin
  c := AInk;
  x0 := Max(0, -AX);
  x1 := Min(AMask.Width, ADest.Width - AX);
  if x1 <= x0 then Exit;
  for y := 0 to AMask.Height - 1 do
  begin
    dy := AY + y;
    if (dy < 0) or (dy >= ADest.Height) then Continue;
    src := AMask.ScanLine[y] + x0;
    dst := ADest.ScanLine[dy] + AX + x0;
    for x := x0 to x1 - 1 do
    begin
      if src^ <> 0 then
      begin
        c.alpha := src^;
        FastBlendPixelInline(dst, c);
      end;
      Inc(src);
      Inc(dst);
    end;
  end;
  ADest.InvalidateBitmap;
end;

{ The glyph drawn by one method into a W x H bitmap at (APad, APad). }
function Draw(AMethod: TMethod; const AGlyph: string; ABold: Boolean; const C: TColorPair;
  APPI, AW, AH, APad: Integer): TBGRABitmap;
var
  P: TTyPainter;
  tmp, hi: TBGRABitmap;
  lo: TBGRACustomBitmap;
  mask: TGrayscaleMask;
  wt: Integer;
begin
  wt := IfThen(ABold, 700, 400);
  Result := TBGRABitmap.Create(AW, AH, C.Bg);
  case AMethod of
    mRef:
      begin
        P := TTyPainter.Create;
        try
          P.BeginPaintOn(nil, Rect(0, 0, AW, AH), APPI, Result);
          P.DrawText(Rect(APad, APad, AW, AH), AGlyph, MainFont, 9, wt,
            TyRGB(C.Fg.red, C.Fg.green, C.Fg.blue), taLeftJustify, tlTop, False);
          P.EndPaint;
        finally
          P.Free;
        end;
      end;
    mB:
      begin
        TyConfigureTextFont(Result, MainFont, 9, wt, APPI);
        Result.TextOut(APad, APad, AGlyph, C.Fg);
      end;
    mC, mCLinear, mCOwn:
      begin
        tmp := TBGRABitmap.Create(AW, AH, BGRAWhite);
        try
          TyConfigureTextFont(tmp, MainFont, 9, wt, APPI);
          tmp.TextOut(APad, APad, AGlyph, BGRABlack);
          mask := CoverageMask(tmp);
          try
            if AMethod = mC then
              Result.FillMask(0, 0, mask, C.Fg, dmDrawWithTransparency)
            else if AMethod = mCOwn then
              BlendMask(Result, 0, 0, mask, C.Fg)
            else
              Result.FillMask(0, 0, mask, C.Fg, dmLinearBlend);
          finally
            mask.Free;
          end;
        finally
          tmp.Free;
        end;
      end;
    mA:
      begin
        hi := TBGRABitmap.Create(AW * 3, AH * 3, BGRAWhite);
        try
          TyConfigureTextFont(hi, MainFont, 9, wt, APPI * 3);
          hi.TextOut(APad * 3, APad * 3, AGlyph, BGRABlack);
          hi.ResampleFilter := rfBestQuality;
          lo := hi.Resample(AW, AH, rmFineResample);
          try
            mask := CoverageMask(TBGRABitmap(lo));
            try
              Result.FillMask(0, 0, mask, C.Fg, dmDrawWithTransparency);
            finally
              mask.Free;
            end;
          finally
            lo.Free;
          end;
        finally
          hi.Free;
        end;
      end;
  end;
end;

procedure RunE2;
const
  PPIs: array[0..1] of Integer = (96, 144);
var
  pairs: array[0..2] of TColorPair;
  meas, ref, got, tmp, grid: TBGRABitmap;
  mth: TMethod;
  k, pc, ch, x, y, cellW, cellH, pad, w, h, rep, n, col, row, bold: Integer;
  sumAll, sumInk, cntAll, cntInk, solid, inked: Int64;
  pr, pg: PBGRAPixel;
  isInk: Boolean;
  cov, st: Integer;
  times: array[0..4] of Double;
  t0: Double;
  masks: array[0..94] of TGrayscaleMask;
  maskOfs: array[0..94] of TPoint;
  m: TGrayscaleMask;
  bb: TRect;
  glyph: string;
begin
  pairs[0].Fg := BGRABlack; pairs[0].Bg := BGRAWhite; pairs[0].Name := 'black/white';
  pairs[1].Fg := BGRAWhite; pairs[1].Bg := PixelOf($1E1E1E); pairs[1].Name := 'white/#1e1e1e';
  pairs[2].Fg := PixelOf($CC0000); pairs[2].Bg := BGRAWhite; pairs[2].Name := '#cc0000/white';
  WriteLn('E2  glyph masks, ', MainFont, ' 9pt; 95 printable ASCII, regular and bold');
  for k := 0 to 1 do
  begin
    meas := TBGRABitmap.Create(1, 1);
    try
      TyConfigureTextFont(meas, MainFont, 9, 400, PPIs[k]);
      cellW := Ceil(meas.TextSize(StringOfChar('W', 32)).cx / 32);
      cellH := meas.FontPixelMetric.Lineheight;
    finally
      meas.Free;
    end;
    pad := cellH;
    w := cellW * 2 + 2 * pad;
    h := cellH + 2 * pad;
    WriteLn;
    WriteLn(Format('== %d PPI  cell %d x %d', [PPIs[k], cellW, cellH]));
    WriteLn(Format('%-16s %-15s %10s %10s %8s', ['method', 'colours', 'MAD(all)', 'MAD(ink)', 'solid']));
    for mth := mA to mCOwn do
      for pc := 0 to 2 do
      begin
        sumAll := 0; sumInk := 0; cntAll := 0; cntInk := 0; solid := 0; inked := 0;
        for bold := 0 to 1 do
          for ch := 33 to 126 do
          begin
            glyph := Chr(ch);
            ref := Draw(mRef, glyph, bold = 1, pairs[pc], PPIs[k], w, h, pad);
            got := Draw(mth, glyph, bold = 1, pairs[pc], PPIs[k], w, h, pad);
            try
              for y := 0 to h - 1 do
              begin
                pr := ref.ScanLine[y];
                pg := got.ScanLine[y];
                for x := 0 to w - 1 do
                begin
                  st := Abs(pr^.red - pg^.red) + Abs(pr^.green - pg^.green) + Abs(pr^.blue - pg^.blue);
                  Inc(sumAll, st);
                  Inc(cntAll, 3);
                  isInk := (pr^.red <> pairs[pc].Bg.red) or (pr^.green <> pairs[pc].Bg.green) or (pr^.blue <> pairs[pc].Bg.blue)
                    or (pg^.red <> pairs[pc].Bg.red) or (pg^.green <> pairs[pc].Bg.green) or (pg^.blue <> pairs[pc].Bg.blue);
                  if isInk then
                  begin
                    Inc(sumInk, st);
                    Inc(cntInk, 3);
                  end;
                  if pc = 0 then
                  begin
                    cov := 255 - (pg^.red + pg^.green + pg^.blue) div 3;
                    if cov > 0 then
                    begin
                      Inc(inked);
                      if cov >= 230 then Inc(solid);
                    end;
                  end;
                  Inc(pr);
                  Inc(pg);
                end;
              end;
            finally
              ref.Free;
              got.Free;
            end;
          end;
        if pc = 0 then
          WriteLn(Format('%-16s %-15s %10.3f %10.3f %7.1f%%', [MethodNames[mth], pairs[pc].Name,
            sumAll / Max(1, cntAll), sumInk / Max(1, cntInk), 100 * solid / Max(1, inked)]))
        else
          WriteLn(Format('%-16s %-15s %10.3f %10.3f %8s', [MethodNames[mth], pairs[pc].Name,
            sumAll / Max(1, cntAll), sumInk / Max(1, cntInk), '']));
      end;
    { the reference's own solid share, black on white }
    solid := 0; inked := 0;
    for ch := 33 to 126 do
    begin
      ref := Draw(mRef, Chr(ch), False, pairs[0], PPIs[k], w, h, pad);
      try
        for y := 0 to h - 1 do
        begin
          pr := ref.ScanLine[y];
          for x := 0 to w - 1 do
          begin
            cov := 255 - (pr^.red + pr^.green + pr^.blue) div 3;
            if cov > 0 then begin Inc(inked); if cov >= 230 then Inc(solid); end;
            Inc(pr);
          end;
        end;
      finally
        ref.Free;
      end;
    end;
    WriteLn(Format('%-16s %-15s %10s %10s %7.1f%% (regular only)', ['ref', 'black/white', '', '', 100 * solid / Max(1, inked)]));

    { cold: 95 glyphs x 4 styles through (c), each cropped to its ink box }
    for rep := 0 to 4 do
    begin
      t0 := TyTermDefaultClock;
      for st := 0 to 3 do
        for ch := 32 to 126 do
        begin
          tmp := TBGRABitmap.Create(w, h, BGRAWhite);
          try
            TyConfigureTextFont(tmp, MainFont, 9, IfThen(st and 1 <> 0, 700, 400), PPIs[k]);
            if st and 2 <> 0 then tmp.FontStyle := tmp.FontStyle + [fsItalic];
            tmp.TextOut(pad, pad, Chr(ch), BGRABlack);
            m := CoverageMask(tmp);
            try
              bb := m.GetImageBoundsWithin(Rect(0, 0, w, h), cGreen, 0);
            finally
              m.Free;
            end;
          finally
            tmp.Free;
          end;
        end;
      times[rep] := TyTermDefaultClock - t0;
    end;
    WriteLn(Format('cold fill, 380 rasterizations through (c): median %.1f ms (%.3f ms each)', [Median5(times), Median5(times) / 380]));

    { warm: a 200 x 60 grid from cached, cropped masks }
    for ch := 32 to 126 do
    begin
      tmp := TBGRABitmap.Create(w, h, BGRAWhite);
      try
        TyConfigureTextFont(tmp, MainFont, 9, 400, PPIs[k]);
        tmp.TextOut(pad, pad, Chr(ch), BGRABlack);
        m := CoverageMask(tmp);
        try
          bb := Rect(0, 0, 0, 0);
          for y := 0 to h - 1 do
            for x := 0 to w - 1 do
              if m.GetPixel(x, y) > 0 then
              begin
                if bb.IsEmpty then bb := Rect(x, y, x + 1, y + 1)
                else begin
                  bb.Left := Min(bb.Left, x); bb.Top := Min(bb.Top, y);
                  bb.Right := Max(bb.Right, x + 1); bb.Bottom := Max(bb.Bottom, y + 1);
                end;
              end;
          if bb.IsEmpty then
          begin
            masks[ch - 32] := nil;
            maskOfs[ch - 32] := Point(0, 0);
          end
          else
          begin
            masks[ch - 32] := m.GetPart(bb);
            maskOfs[ch - 32] := Point(bb.Left - pad, bb.Top - pad);
          end;
        finally
          m.Free;
        end;
      finally
        tmp.Free;
      end;
    end;
    grid := TBGRABitmap.Create(200 * cellW, 60 * cellH, BGRAWhite);
    try
      for rep := 0 to 4 do
      begin
        t0 := TyTermDefaultClock;
        n := 0;
        for row := 0 to 59 do
          for col := 0 to 199 do
          begin
            grid.FillRect(col * cellW, row * cellH, (col + 1) * cellW, (row + 1) * cellH, PixelOf($1E1E1E), dmSet);
            ch := 33 + (row * 200 + col) mod 94;
            if masks[ch - 32] <> nil then
            begin
              grid.FillMask(col * cellW + maskOfs[ch - 32].X, row * cellH + maskOfs[ch - 32].Y,
                masks[ch - 32], BGRA(204, 204, 204), dmLinearBlend);
              Inc(n);
            end;
          end;
        times[rep] := TyTermDefaultClock - t0;
      end;
      WriteLn(Format('warm repaint, 200 x 60 cells (%d masks tinted, FillMask linear): median %.1f ms', [n, Median5(times)]));
      { the same with the plan's fallback: a row fill per row and our own blend loop
        (FastBlendPixelInline, the blend TTyGdiTextRenderer lays text down with) }
      for rep := 0 to 4 do
      begin
        t0 := TyTermDefaultClock;
        for row := 0 to 59 do
        begin
          grid.FillRect(0, row * cellH, 200 * cellW, (row + 1) * cellH, PixelOf($1E1E1E), dmSet);
          for col := 0 to 199 do
          begin
            ch := 33 + (row * 200 + col) mod 94;
            if masks[ch - 32] <> nil then
              BlendMask(grid, col * cellW + maskOfs[ch - 32].X, row * cellH + maskOfs[ch - 32].Y,
                masks[ch - 32], BGRA(204, 204, 204));
          end;
        end;
        times[rep] := TyTermDefaultClock - t0;
      end;
      WriteLn(Format('warm repaint, 200 x 60 cells, row fill + own blend loop: median %.1f ms', [Median5(times)]));
      grid.SaveToFile(IncludeTrailingPathDelimiter(OutDir) + Format('e2-grid-%d.png', [PPIs[k]]));
    finally
      grid.Free;
    end;
    for ch := 0 to 94 do FreeAndNil(masks[ch]);
  end;
end;

var
  i: Integer;
  doE1, doE2: Boolean;
begin
  TyFallbackFontName := UiFont;
  doE1 := False;
  doE2 := False;
  i := 1;
  while i <= ParamCount do
  begin
    if ParamStr(i) = '--e1' then doE1 := True
    else if ParamStr(i) = '--e2' then doE2 := True
    else if (ParamStr(i) = '--out') and (i < ParamCount) then
    begin
      Inc(i);
      OutDir := ParamStr(i);
    end;
    Inc(i);
  end;
  if not (doE1 or doE2) then
  begin
    WriteLn('fontprobe --e1 | --e2 [--out <dir>]');
    Halt(2);
  end;
  ForceDirectories(OutDir);
  if doE1 then RunE1;
  if doE2 then RunE2;
end.
