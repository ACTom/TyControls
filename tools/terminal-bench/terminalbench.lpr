program terminalbench;
{$mode objfpc}{$H+}
{$modeswitch advancedrecords}
{$APPTYPE CONSOLE}
{ The terminal's benchmark (phase 5 plan, Task 1 and Task 9). Builds from source/
  without the package, like tools/terminal-fontprobe; the control is drawn off screen
  the way tools/terminal-shots draws it (a form that never appears, the control's own
  RenderTo), except for --flood and --window, which need a real window to be painted.

    terminalbench --all | --core | --slice | --paint | --scroll | --raster | --flood | --reflow
    terminalbench --window --flood <MB>

  Every switch prints one Markdown table; --all runs them in the order above. The
  input is made in memory by one seeded generator (xorshift32, seed 20260929, no
  clock): lines of 60-200 columns, 70% ASCII words, 10% CJK, 1% emoji, 1% an e with a
  combining acute, the rest digits and punctuation, a colour change every 5-12 words
  (ESC[3Nm, ESC[38;5;Nm, ESC[38;2;r;g;bm, ESC[0m), CRLF line ends. Times come from
  TyTermDefaultClock; a figure over several runs is the median (and the maximum where
  it says so).

  --core     a 200 x 60 core, Scrollback 1000: 32 MB in 64 KB chunks through WriteSync.
             MB/s; the parse time of one chunk, median and maximum; live lines after.
  --slice    the same core: ONE Write of 20 MB, then ProcessPending(12) until it answers
             False. How many slices, and the longest.
  --paint    the control, 200 x 60, a screen of mixed text; after one warm-up frame, 50
             frames with every row dirty. 96 and 144 PPI; with MinimumContrastRatio 4.5
             once the property exists (phase 5 Task 11).
  --scroll   the same control: a full screen, then 2000 times one line written and one
             frame drawn. Rows painted per frame and the frame time.
  --raster   a new control, an empty glyph cache: one frame of the 95 printable ASCII
             characters in four styles (regular, bold, italic, bold italic), then one of 200
             CJK characters, the rasterizing budget off. The cold frame against the same
             screen warm, per glyph. Then TextSize and TextOut apart, on a scratch surface
             set up as the rasterizer sets up its own, 376 of each.
  --flood    the control on a shown form: 50 MB in 64 KB chunks through View.Write with a
             callback, four chunks in flight (the example's replay does the same), the
             message loop pumped until every callback is back. Wall time, MB/s, the
             longest gap between two paints, the heap growth, live lines, glyph cache hits /
             misses (and evictions from phase 5 Task 9).
  --reflow   a 200 x 60 core, Scrollback 10000, filled with 400-column lines (two rows
             each); Resize to 120, 200 and 80 columns, each timed.
  --window --flood <MB>
             a real window; once it is up, ONE View.Write of that many megabytes. Not
             timed: for the real-machine check that the window stays responsive (drag it,
             resize it) while the write is parsed. Close the window to end.

  The numbers go into docs/superpowers/plans/2026-09-29-terminal-phase-5.md ("基线数字")
  and the design spec's section 16. Run from the repository root:

    lazbuild -B tools/terminal-bench/terminalbench.lpi
    tools/terminal-bench/terminalbench.exe --all > bench.md }

uses
  Interfaces, SysUtils, Classes, Math, Types, Forms, Controls, Graphics, LCLType, LCLIntf,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Controller, tyControls.BuiltinThemes,
  tyControls.Terminal.Buffer, tyControls.Terminal.Core, tyControls.Terminal.Render,
  tyControls.Terminal;

const
  MB = 1024 * 1024;
  Seed = 20260929;

{ ---- the input ------------------------------------------------------------------ }

type
  TMixGen = object
    X: Cardinal;
    CjkPool: Integer;
    procedure Init(ACjkPool: Integer);
    function Next: Cardinal;
    function Below(N: Integer): Integer;
  end;

procedure TMixGen.Init(ACjkPool: Integer);
begin
  X := Seed;
  CjkPool := ACjkPool;
end;

function TMixGen.Next: Cardinal;
begin
  X := X xor (X shl 13);
  X := X xor (X shr 17);
  X := X xor (X shl 5);
  Result := X;
end;

function TMixGen.Below(N: Integer): Integer;
begin
  Result := Integer(Next mod Cardinal(N));
end;

function Utf8(u: Cardinal): string;
begin
  if u < $80 then Result := Chr(u)
  else if u < $800 then Result := Chr($C0 or (u shr 6)) + Chr($80 or (u and $3F))
  else if u < $10000 then Result := Chr($E0 or (u shr 12)) + Chr($80 or ((u shr 6) and $3F)) + Chr($80 or (u and $3F))
  else Result := Chr($F0 or (u shr 18)) + Chr($80 or ((u shr 12) and $3F)) + Chr($80 or ((u shr 6) and $3F))
    + Chr($80 or (u and $3F));
end;

type
  { a growing byte buffer: 50 MB built line by line without a copy per line }
  TAppender = record
    S: RawByteString;
    N: Int64;
    procedure Add(const T: RawByteString);
    function Done: RawByteString;
  end;

procedure TAppender.Add(const T: RawByteString);
begin
  if T = '' then Exit;
  if N + Length(T) > Length(S) then
    SetLength(S, Max(Int64(Length(S)) * 2, N + Length(T) + 65536));
  Move(T[1], S[N + 1], Length(T));
  Inc(N, Length(T));
end;

function TAppender.Done: RawByteString;
begin
  SetLength(S, N);
  Result := S;
end;

{ One line of mixed output, 60-200 columns, CRLF. }
function MixedLine(var G: TMixGen): RawByteString;
const
  Letters = 'abcdefghijklmnopqrstuvwxyz';
  Punct = '.,;:-_/()[]{}=+*#@!?%&';
var
  target, col, words, nextColor, r, k, n: Integer;
  s: RawByteString;
begin
  target := 60 + G.Below(141);
  col := 0;
  words := 0;
  nextColor := 5 + G.Below(8);
  s := '';
  while col < target do
  begin
    r := G.Below(100);
    if r < 70 then
    begin
      n := 1 + G.Below(9);
      for k := 1 to n do
        s := s + Letters[1 + G.Below(26)];
      s := s + ' ';
      Inc(col, n + 1);
    end
    else if r < 80 then
    begin
      s := s + Utf8($4E00 + Cardinal(G.Below(G.CjkPool)));
      Inc(col, 2);
    end
    else if r < 81 then
    begin
      s := s + Utf8($1F600 + Cardinal(G.Below($50)));
      Inc(col, 2);
    end
    else if r < 82 then
    begin
      s := s + 'e' + Utf8($301);
      Inc(col);
    end
    else
    begin
      n := 1 + G.Below(4);
      for k := 1 to n do
        if G.Below(2) = 0 then s := s + Chr(Ord('0') + G.Below(10)) else s := s + Punct[1 + G.Below(Length(Punct))];
      s := s + ' ';
      Inc(col, n + 1);
    end;
    Inc(words);
    if words >= nextColor then
    begin
      case G.Below(4) of
        0: s := s + #27'[3' + IntToStr(G.Below(8)) + 'm';
        1: s := s + #27'[38;5;' + IntToStr(G.Below(256)) + 'm';
        2: s := s + #27'[38;2;' + IntToStr(G.Below(256)) + ';' + IntToStr(G.Below(256)) + ';'
          + IntToStr(G.Below(256)) + 'm';
      else
        s := s + #27'[0m';
      end;
      words := 0;
      nextColor := 5 + G.Below(8);
    end;
  end;
  Result := s + #13#10;
end;

{ At least ABytes of whole lines. }
function MixedText(ABytes: Int64; ACjkPool: Integer = 3000): RawByteString;
var
  g: TMixGen;
  a: TAppender;
begin
  g.Init(ACjkPool);
  a.S := '';
  a.N := 0;
  while a.N < ABytes do
    a.Add(MixedLine(g));
  Result := a.Done;
end;

function MixedLines(ACount: Integer): RawByteString;
var
  g: TMixGen;
  i: Integer;
begin
  g.Init(3000);
  Result := '';
  for i := 1 to ACount do
    Result := Result + MixedLine(g);
end;

{ ---- numbers ---------------------------------------------------------------------- }

type
  TDoubles = array of Double;

procedure Push(var A: TDoubles; V: Double);
begin
  SetLength(A, Length(A) + 1);
  A[High(A)] := V;
end;

function Median(A: TDoubles): Double;
var
  i, j: Integer;
  t: Double;
begin
  if Length(A) = 0 then Exit(0);
  A := Copy(A);
  for i := 1 to High(A) do
  begin
    t := A[i];
    j := i - 1;
    while (j >= 0) and (A[j] > t) do
    begin
      A[j + 1] := A[j];
      Dec(j);
    end;
    A[j + 1] := t;
  end;
  if Odd(Length(A)) then
    Result := A[Length(A) div 2]
  else
    Result := (A[Length(A) div 2 - 1] + A[Length(A) div 2]) / 2;
end;

function MaxOf(const A: TDoubles): Double;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(A) do
    if A[i] > Result then Result := A[i];
end;

function Ms(V: Double): string;
begin
  Result := FormatFloat('0.00', V) + ' ms';
end;

function Now: Double;
begin
  Result := TyTermDefaultClock;
end;

{ ---- the control, off screen -------------------------------------------------------- }

type
  TBenchView = class(TTyTerminalView)
  public
    PaintTimes: TDoubles;
    RecordPaints: Boolean;
    procedure Shot(ABmp: TBitmap; APPI: Integer);
    { every row painted again next frame (phase 5: the view keys its rows and moves
      the ones it finds, so a scroll no longer repaints them -- ForgetPaintedRows) }
    procedure AllDirty;
    function Painted: Integer;
    function Cache: TTyTermGlyphCache;
    function Spec: TTyTermFontSpec;
    function Cell: TTyTermCellMetrics;
  protected
    procedure Paint; override;
  end;

procedure TBenchView.Shot(ABmp: TBitmap; APPI: Integer);
begin
  RasterBudgetMs := 0;
  RenderTo(ABmp.Canvas, Rect(0, 0, ABmp.Width, ABmp.Height), APPI);
end;

procedure TBenchView.AllDirty;
begin
  ForgetPaintedRows;
end;

function TBenchView.Painted: Integer;
begin
  Result := RowsPainted;
end;

function TBenchView.Cache: TTyTermGlyphCache;
begin
  Result := GlyphCache;
end;

function TBenchView.Spec: TTyTermFontSpec;
begin
  Result := FontSpec;
end;

function TBenchView.Cell: TTyTermCellMetrics;
begin
  Result := Metrics;
end;

procedure TBenchView.Paint;
begin
  if RecordPaints then Push(PaintTimes, Now);
  inherited Paint;
end;

var
  Form: TForm;
  Ctl: TTyStyleController;

type
  TOffscreen = record
    View: TBenchView;
    Bmp: TBitmap;
    PPI: Integer;
  end;

function NewOffscreen(ACols, ARows, APPI: Integer): TOffscreen;
var
  sz: TSize;
begin
  Result.View := TBenchView.Create(Form);
  Result.View.Controller := Ctl;
  Result.View.Parent := Form;
  sz := Result.View.SizeForGrid(ACols, ARows);
  Result.View.SetBounds(0, 0, sz.cx, sz.cy);
  Result.PPI := APPI;
  Result.Bmp := TBitmap.Create;
  Result.Bmp.PixelFormat := pf24bit;
  Result.Bmp.SetSize(MulDiv(sz.cx, APPI, Result.View.Font.PixelsPerInch),
    MulDiv(sz.cy, APPI, Result.View.Font.PixelsPerInch));
end;

procedure FreeOffscreen(var O: TOffscreen);
begin
  O.View.Free;
  O.Bmp.Free;
end;

{ ---- the switches ------------------------------------------------------------------ }

procedure BenchCore;
const
  Total = 32 * MB;
  Chunk = 64 * 1024;
  Runs = 3;
var
  data: RawByteString;
  core: TTyTerminalCore;
  run, pos: Integer;
  t0, tc, wall: Double;
  chunkTimes, rates: TDoubles;
  live: Integer;
begin
  data := MixedText(Total);
  chunkTimes := nil;
  rates := nil;
  live := 0;
  for run := 1 to Runs do
  begin
    core := TTyTerminalCore.Create(200, 60);
    try
      core.Scrollback := 1000;
      t0 := Now;
      pos := 1;
      while pos <= Length(data) do
      begin
        tc := Now;
        core.WriteSync(Copy(data, pos, Chunk));
        if run = Runs then Push(chunkTimes, Now - tc);
        Inc(pos, Chunk);
      end;
      wall := Now - t0;
      Push(rates, Length(data) / MB / (wall / 1000));
      live := TTyTerminalLine.LiveCount;
    finally
      core.Free;
    end;
  end;
  WriteLn('## --core');
  WriteLn;
  WriteLn(Format('%d MB in 64 KB chunks through WriteSync, 200 x 60, Scrollback 1000; %d runs.',
    [Length(data) div MB, Runs]));
  WriteLn;
  WriteLn('| MB/s (median) | chunk parse, median | chunk parse, max | live lines at the end |');
  WriteLn('|---|---|---|---|');
  WriteLn(Format('| %s | %s | %s | %d |', [FormatFloat('0.0', Median(rates)), Ms(Median(chunkTimes)),
    Ms(MaxOf(chunkTimes)), live]));
  WriteLn;
end;

procedure BenchSlice;
const
  Total = 20 * MB;
  Runs = 3;
var
  data: RawByteString;
  core: TTyTerminalCore;
  run, slices: Integer;
  t, longest: Double;
  more: Boolean;
  counts, longests: TDoubles;
begin
  data := MixedText(Total);
  counts := nil;
  longests := nil;
  for run := 1 to Runs do
  begin
    core := TTyTerminalCore.Create(200, 60);
    try
      core.Scrollback := 1000;
      core.Write(data);
      slices := 0;
      longest := 0;
      repeat
        t := Now;
        more := core.ProcessPending(12);
        t := Now - t;
        Inc(slices);
        if t > longest then longest := t;
      until not more;
      Push(counts, slices);
      Push(longests, longest);
    finally
      core.Free;
    end;
  end;
  WriteLn('## --slice');
  WriteLn;
  WriteLn(Format('One Write of %d MB, then ProcessPending(12) until False; %d runs.', [Length(data) div MB, Runs]));
  WriteLn;
  WriteLn('| slices (median) | longest slice (median) | longest slice (max) |');
  WriteLn('|---|---|---|');
  WriteLn(Format('| %s | %s | %s |', [FormatFloat('0', Median(counts)), Ms(Median(longests)), Ms(MaxOf(longests))]));
  WriteLn;
end;

function ScreenText: RawByteString;
begin
  { more than a screen, so the scrollback has lines to scroll into; cursor hidden }
  Result := MixedLines(200) + #27'[?25l';
end;

procedure BenchPaint;
const
  Frames = 50;
  PPIs: array[0..2] of Integer = (96, 144, 96);
  Contrast: array[0..2] of Double = (1, 1, 4.5);
var
  o: TOffscreen;
  k, f: Integer;
  t: Double;
  times: TDoubles;
  res: array[0..2] of Double;
  mx: array[0..2] of Double;
begin
  for k := 0 to 2 do
  begin
    o := NewOffscreen(200, 60, PPIs[k]);
    try
      o.View.MinimumContrastRatio := Contrast[k];
      o.View.WriteSync(ScreenText);
      o.View.Shot(o.Bmp, o.PPI);                   { warm-up: every glyph (and colour pair) into the cache }
      times := nil;
      for f := 1 to Frames do
      begin
        o.View.AllDirty;
        t := Now;
        o.View.Shot(o.Bmp, o.PPI);
        Push(times, Now - t);
      end;
      res[k] := Median(times);
      mx[k] := MaxOf(times);
    finally
      FreeOffscreen(o);
    end;
  end;
  WriteLn('## --paint');
  WriteLn;
  WriteLn(Format('200 x 60, a screen of mixed text, warm cache, every row dirty; median of %d frames (max).', [Frames]));
  WriteLn;
  WriteLn('| 96 PPI | 144 PPI | 96 PPI, contrast 4.5 |');
  WriteLn('|---|---|---|');
  WriteLn(Format('| %s (%s) | %s (%s) | %s (%s) |', [Ms(res[0]), Ms(mx[0]), Ms(res[1]), Ms(mx[1]), Ms(res[2]),
    Ms(mx[2])]));
  WriteLn;
end;

procedure BenchScroll;
const
  Lines = 2000;
var
  o: TOffscreen;
  n, rows0: Integer;
  t: Double;
  times: TDoubles;
begin
  o := NewOffscreen(200, 60, 96);
  try
    o.View.WriteSync(ScreenText);
    o.View.Shot(o.Bmp, o.PPI);
    { one throw-away line: the numbers start with the glyphs of "line n" cached }
    o.View.WriteSync('line 0'#13#10);
    o.View.Shot(o.Bmp, o.PPI);
    rows0 := o.View.Painted;
    times := nil;
    for n := 1 to Lines do
    begin
      o.View.WriteSync('line ' + IntToStr(n) + #13#10);
      t := Now;
      o.View.Shot(o.Bmp, o.PPI);
      Push(times, Now - t);
    end;
    WriteLn('## --scroll');
    WriteLn;
    WriteLn(Format('200 x 60 at 96 PPI, a full screen, then %d times one line written and one frame drawn.', [Lines]));
    WriteLn;
    WriteLn('| rows painted per frame | frame, median | frame, max |');
    WriteLn('|---|---|---|');
    WriteLn(Format('| %s | %s | %s |', [FormatFloat('0.00', (o.View.Painted - rows0) / Lines), Ms(Median(times)),
      Ms(MaxOf(times))]));
    WriteLn;
  finally
    FreeOffscreen(o);
  end;
end;

procedure BenchRaster;
const
  Runs = 3;
  Styles: array[0..3] of string = (#27'[0m', #27'[0;1m', #27'[0;3m', #27'[0;1;3m');
var
  o: TOffscreen;
  run, s, c, n0, asciiN, cjkN: Integer;
  txt, cjk: RawByteString;
  t, cold, warm: Double;
  asciiPer, cjkPer, asciiCold, cjkCold, sizeT, outT: TDoubles;
  bmp: TBGRABitmap;
  spec: TTyTermFontSpec;
  m: TTyTermCellMetrics;
  pad: Integer;
  tSize, tOut: Double;
begin
  txt := #27'[?25l'#27'[H';
  for s := 0 to 3 do
  begin
    txt := txt + Styles[s];
    for c := 32 to 126 do
      txt := txt + Chr(c);
    txt := txt + #13#10;
  end;
  txt := txt + #27'[0m';
  cjk := #27'[2J'#27'[H';
  for c := 0 to 199 do
    cjk := cjk + Utf8($4E00 + Cardinal(c) * 7);
  asciiPer := nil; cjkPer := nil; asciiCold := nil; cjkCold := nil;
  asciiN := 0; cjkN := 0;
  for run := 1 to Runs do
  begin
    o := NewOffscreen(200, 60, 96);
    try
      o.View.Shot(o.Bmp, o.PPI);                   { the metrics, the frame, an empty grid }
      o.View.Cache.Clear;
      n0 := o.View.Cache.Count;
      o.View.WriteSync(txt);
      t := Now;
      o.View.Shot(o.Bmp, o.PPI);
      cold := Now - t;
      asciiN := o.View.Cache.Count - n0;
      o.View.AllDirty;
      t := Now;
      o.View.Shot(o.Bmp, o.PPI);
      warm := Now - t;
      Push(asciiCold, cold);
      Push(asciiPer, (cold - warm) / Max(1, asciiN));
      n0 := o.View.Cache.Count;
      o.View.WriteSync(cjk);
      t := Now;
      o.View.Shot(o.Bmp, o.PPI);
      cold := Now - t;
      cjkN := o.View.Cache.Count - n0;
      o.View.AllDirty;
      t := Now;
      o.View.Shot(o.Bmp, o.PPI);
      warm := Now - t;
      Push(cjkCold, cold);
      Push(cjkPer, (cold - warm) / Max(1, cjkN));
      if run = Runs then
      begin
        spec := o.View.Spec;
        m := o.View.Cell;
      end;
    finally
      FreeOffscreen(o);
    end;
  end;
  { TextSize and TextOut apart, on a scratch surface set up as TTyTermGlyphRasterizer sets
    up its own (Reserve + Configure; the font changes only with the style) }
  sizeT := nil; outT := nil;
  pad := m.CellH;
  for run := 1 to Runs do
  begin
    bmp := TBGRABitmap.Create(Max(4 * m.CellW + 2 * pad, 64), Max(m.CellH + 2 * pad, 32));
    try
      tSize := 0;
      tOut := 0;
      for s := 0 to 3 do
      begin
        TyConfigureTextFont(bmp, spec.MainName, spec.SizeLogical, IfThen(s in [1, 3], 700, 400), spec.PPI);
        if s >= 2 then bmp.FontStyle := bmp.FontStyle + [fsItalic];
        for c := 33 to 126 do
        begin
          t := Now;
          bmp.TextSize(Chr(c));
          tSize := tSize + (Now - t);
          t := Now;
          bmp.FillRect(0, 0, bmp.Width, bmp.Height, BGRAWhite, dmSet);
          bmp.TextOut(pad, pad + m.TextTop, Chr(c), BGRABlack);
          tOut := tOut + (Now - t);
        end;
      end;
      Push(sizeT, tSize / 376);
      Push(outT, tOut / 376);
    finally
      bmp.Free;
    end;
  end;
  WriteLn('## --raster');
  WriteLn;
  WriteLn(Format('A new control at 96 PPI, empty glyph cache, budget off; per glyph = (cold frame - the same frame warm) / new glyphs; median of %d runs.', [Runs]));
  WriteLn;
  WriteLn('| set | new glyphs | cold frame | per glyph |');
  WriteLn('|---|---|---|---|');
  WriteLn(Format('| ASCII x 4 styles | %d | %s | %s |', [asciiN, Ms(Median(asciiCold)), Ms(Median(asciiPer))]));
  WriteLn(Format('| CJK | %d | %s | %s |', [cjkN, Ms(Median(cjkCold)), Ms(Median(cjkPer))]));
  WriteLn;
  WriteLn('| TextSize per call | TextOut (with the white fill) per call | TextSize share |');
  WriteLn('|---|---|---|');
  WriteLn(Format('| %s | %s | %s%% |', [Ms(Median(sizeT)), Ms(Median(outT)),
    FormatFloat('0', 100 * Median(sizeT) / Max(1e-9, Median(sizeT) + Median(outT)))]));
  WriteLn;
end;

var
  FloodDone, FloodNext: Integer;
  FloodChunks: array of RawByteString;
  FloodView: TBenchView;

type
  TFloodSink = class
    procedure Done(Sender: TObject; ATag: PtrInt);
  end;

procedure TFloodSink.Done(Sender: TObject; ATag: PtrInt);
begin
  Inc(FloodDone);
  if FloodNext <= High(FloodChunks) then
  begin
    FloodView.Write(FloodChunks[FloodNext], @Done, FloodNext);
    Inc(FloodNext);
  end;
end;

procedure BenchFlood;
const
  Total = 50 * MB;
  Chunk = 64 * 1024;
  InFlight = 4;
var
  data: RawByteString;
  f: TForm;
  sink: TFloodSink;
  sz: TSize;
  i, n: Integer;
  t0, wall, gap: Double;
  heap0, heap1: Int64;
begin
  data := MixedText(Total);
  n := (Length(data) + Chunk - 1) div Chunk;
  SetLength(FloodChunks, n);
  for i := 0 to n - 1 do
    FloodChunks[i] := Copy(data, i * Chunk + 1, Chunk);
  data := '';
  f := TForm.CreateNew(nil);
  sink := TFloodSink.Create;
  try
    f.Caption := 'terminalbench --flood';
    FloodView := TBenchView.Create(f);
    FloodView.Controller := Ctl;
    FloodView.Parent := f;
    sz := FloodView.SizeForGrid(200, 60);
    f.SetBounds(40, 40, sz.cx, sz.cy);
    FloodView.SetBounds(0, 0, sz.cx, sz.cy);
    f.Show;
    for i := 1 to 20 do Application.ProcessMessages;
    heap0 := GetFPCHeapStatus.CurrHeapUsed;
    FloodView.PaintTimes := nil;
    FloodView.RecordPaints := True;
    FloodDone := 0;
    FloodNext := 0;
    t0 := Now;
    while (FloodNext < InFlight) and (FloodNext < n) do
    begin
      FloodView.Write(FloodChunks[FloodNext], @sink.Done, FloodNext);
      Inc(FloodNext);
    end;
    while FloodDone < n do
      Application.ProcessMessages;
    wall := Now - t0;
    for i := 1 to 20 do Application.ProcessMessages;
    FloodView.RecordPaints := False;
    heap1 := GetFPCHeapStatus.CurrHeapUsed;
    gap := 0;
    for i := 1 to High(FloodView.PaintTimes) do
      gap := Max(gap, FloodView.PaintTimes[i] - FloodView.PaintTimes[i - 1]);
    WriteLn('## --flood');
    WriteLn;
    WriteLn('50 MB in 64 KB chunks through View.Write, four in flight, on a shown 200 x 60 control.');
    WriteLn;
    WriteLn('| wall | MB/s | paints | longest gap between paints | heap growth | live lines | cache hits / misses / evictions |');
    WriteLn('|---|---|---|---|---|---|---|');
    WriteLn(Format('| %s | %s | %d | %s | %s MB | %d | %d / %d / %d |', [Ms(wall),
      FormatFloat('0.0', Total / MB / (wall / 1000)), Length(FloodView.PaintTimes), Ms(gap),
      FormatFloat('0.0', (heap1 - heap0) / MB), TTyTerminalLine.LiveCount,
      FloodView.Cache.Hits, FloodView.Cache.Misses, FloodView.Cache.Evictions]));
    WriteLn;
  finally
    sink.Free;
    f.Free;
    FloodChunks := nil;
    FloodView := nil;
  end;
end;

procedure BenchReflow;
const
  Runs = 3;
  Widths: array[0..2] of Integer = (120, 200, 80);
var
  core: TTyTerminalCore;
  line, data: RawByteString;
  run, k, i: Integer;
  t: Double;
  times: array[0..2] of TDoubles;
  lines: array[0..2] of Integer;
begin
  line := '';
  for i := 0 to 399 do
    line := line + Chr(Ord('a') + i mod 26);
  line := line + #13#10;
  data := '';
  for i := 1 to 5100 do
    data := data + line;
  for k := 0 to 2 do times[k] := nil;
  for run := 1 to Runs do
  begin
    core := TTyTerminalCore.Create(200, 60);
    try
      core.Scrollback := 10000;
      core.WriteSync(data);
      for k := 0 to 2 do
      begin
        t := Now;
        core.Resize(Widths[k], 60);
        Push(times[k], Now - t);
        lines[k] := core.Buffer.Lines.Length;
      end;
    finally
      core.Free;
    end;
  end;
  WriteLn('## --reflow');
  WriteLn;
  WriteLn(Format('200 x 60, Scrollback 10000, filled with 400-column lines (two rows each); median of %d runs.', [Runs]));
  WriteLn;
  WriteLn('| 200 -> 120 | 120 -> 200 | 200 -> 80 |');
  WriteLn('|---|---|---|');
  WriteLn(Format('| %s (%d lines) | %s (%d lines) | %s (%d lines) |', [Ms(Median(times[0])), lines[0],
    Ms(Median(times[1])), lines[1], Ms(Median(times[2])), lines[2]]));
  WriteLn;
end;

procedure WindowFlood(AMegabytes: Integer);
var
  f: TForm;
  v: TTyTerminalView;
  data: RawByteString;
begin
  data := MixedText(Int64(AMegabytes) * MB);
  f := TForm.CreateNew(nil);
  try
    f.Caption := Format('terminalbench --window --flood %d', [AMegabytes]);
    f.SetBounds(80, 80, 1000, 640);
    v := TTyTerminalView.Create(f);
    v.Controller := Ctl;
    v.Parent := f;
    v.Align := alClient;
    f.Show;
    Application.ProcessMessages;
    v.Write(data);
    data := '';
    while f.Visible do
      Application.HandleMessage;
  finally
    f.Free;
  end;
end;

function Has(const S: string): Boolean;
var
  i: Integer;
begin
  for i := 1 to ParamCount do
    if ParamStr(i) = S then Exit(True);
  Result := False;
end;

var
  all: Boolean;
  i, floodMb: Integer;
begin
  TyFallbackFontName := {$IFDEF MSWINDOWS}'Segoe UI'{$ELSE}''{$ENDIF};
  Application.Initialize;
  TyRegisterBuiltinThemes;
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  try
    Form.SetBounds(0, 0, 1600, 1200);
    if Has('--window') then
    begin
      floodMb := 20;
      for i := 1 to ParamCount - 1 do
        if ParamStr(i) = '--flood' then floodMb := StrToIntDef(ParamStr(i + 1), 20);
      WindowFlood(floodMb);
      Exit;
    end;
    all := Has('--all');
    WriteLn('# terminalbench');
    WriteLn;
    if all or Has('--core') then BenchCore;
    if all or Has('--slice') then BenchSlice;
    if all or Has('--paint') then BenchPaint;
    if all or Has('--scroll') then BenchScroll;
    if all or Has('--raster') then BenchRaster;
    if all or Has('--flood') then BenchFlood;
    if all or Has('--reflow') then BenchReflow;
  finally
    Form.Free;
    Ctl.Free;
  end;
end.
