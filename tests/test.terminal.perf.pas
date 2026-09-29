unit test.terminal.perf;
{$mode objfpc}{$H+}
{ The terminal's resource and time guards (phase 5, Task 9).

  What can be counted is counted (live lines, heap growth, glyph cache entries, misses and
  evictions, contrast pairs found); the timed tests use the wall clock and a bound relative
  to something timed in the same run (a piece parsed alone, the least a repaint of the
  screen costs, the same frame at a ratio of 1), are tried twice before they count as red,
  and the exact numbers live in the spec, not in the asserts.

  The mixed text is tools/terminal-bench's generator (same seed, same line shape): words,
  CJK from a pool of code points, emoji, a combining mark, numbers and punctuation, a colour
  change every few words, lines of 60-200 columns. }

interface

uses
  Classes, SysUtils, Types, Math, fpcunit, testregistry, fpjson, Forms, Graphics,
  BGRABitmap, BGRABitmapTypes, BGRAGrayscaleMask,
  tyControls.Terminal.Buffer, tyControls.Terminal.Core, tyControls.Terminal.Render,
  test.terminal.oracle, test.terminal.view;

type
  TTyTerminalPerfTests = class(TTestCase)
  private
    FDone: Integer;
    FNext: Integer;
    FChunks: array of RawByteString;
    FView: TTyTerminalViewProbe;
    FShot: TBitmap;
    procedure ChunkDone(Sender: TObject; ATag: PtrInt);
  published
    procedure TestAFloodKeepsMemoryFlat;
    procedure TestTheCacheHitsOnceWarm;
    procedure TestTheLongestSliceStaysNearTheBudget;
    procedure TestAFullRepaintIsNotSlower;
    procedure TestContrastCostsLittle;
    procedure TestAFloodStillPaints;
  end;

  { the view that records when it paints (TestAFloodStillPaints) }
  TPaintRecorder = class(TTyTerminalViewProbe)
  public
    Paints: array of Double;
    Recording: Boolean;
  protected
    procedure Paint; override;
  end;

{ At least ABytes of whole mixed lines (tools/terminal-bench's MixedText). }
function TyTermMixedText(ABytes: Int64; ACjkPool: Integer = 3000): RawByteString;

implementation

const
  MB = 1024 * 1024;
  BenchSeed = 20260929;

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
  X := BenchSeed;
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

function Utf8(u: Cardinal): RawByteString;
begin
  if u < $80 then Result := Chr(u)
  else if u < $800 then Result := Chr($C0 or (u shr 6)) + Chr($80 or (u and $3F))
  else if u < $10000 then Result := Chr($E0 or (u shr 12)) + Chr($80 or ((u shr 6) and $3F)) + Chr($80 or (u and $3F))
  else Result := Chr($F0 or (u shr 18)) + Chr($80 or ((u shr 12) and $3F)) + Chr($80 or ((u shr 6) and $3F))
    + Chr($80 or (u and $3F));
end;

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

function TyTermMixedText(ABytes: Int64; ACjkPool: Integer): RawByteString;
var
  g: TMixGen;
  n: Int64;
  line: RawByteString;
begin
  g.Init(ACjkPool);
  Result := '';
  SetLength(Result, ABytes + 4096);
  n := 0;
  while n < ABytes do
  begin
    line := MixedLine(g);
    if n + Length(line) > Length(Result) then
      SetLength(Result, Max(Int64(Length(Result)) * 2, n + Length(line) + 65536));
    Move(line[1], Result[n + 1], Length(line));
    Inc(n, Length(line));
  end;
  SetLength(Result, n);
end;

{ The bytes of one recording in terminal-core-recording.json, every write step joined. }
function RecordingBytes(const AId: string; out ACols, ARows: Integer): TStringList;
var
  fx: TTyTermFixtures;
  m: TTyTermMisses;
  cases: TFPList;
  i, k: Integer;
  c: TJSONObject;
  steps: TJSONArray;
begin
  Result := TStringList.Create;
  ACols := 0;
  ARows := 0;
  m := TTyTermMisses.Create;
  try
    fx := TyTermLoadFixtures('core-recording', m);
    cases := TyTermAllCases(fx);
    try
      for i := 0 to cases.Count - 1 do
      begin
        c := TJSONObject(cases[i]);
        if c.Strings['id'] <> AId then Continue;
        ACols := c.Integers['cols'];
        ARows := c.Integers['rows'];
        steps := c.Arrays['steps'];
        for k := 0 to steps.Count - 1 do
          if steps.Objects[k].IndexOfName('write') >= 0 then
            Result.Add(TyTermBase64Bytes(steps.Objects[k].Strings['write']));
      end;
    finally
      cases.Free;
      TyTermFreeFixtures(fx);
    end;
  finally
    m.Free;
  end;
end;

procedure SortDoubles(var A: array of Double);
var
  i, j: Integer;
  t: Double;
begin
  for i := 0 to High(A) do
    for j := i + 1 to High(A) do
      if A[j] < A[i] then
      begin
        t := A[i];
        A[i] := A[j];
        A[j] := t;
      end;
end;

{ ---- the tests --------------------------------------------------------------------- }

procedure TTyTerminalPerfTests.ChunkDone(Sender: TObject; ATag: PtrInt);
begin
  Inc(FDone);
  { a frame every other chunk, the glyphs on screen then: past the cache's 4096 with room
    to spare (one ProcessMessages runs slice after slice, so a frame per pump would be one
    frame in all) }
  if (FShot <> nil) and (FDone mod 2 = 0) then
    FView.Render(FShot.Canvas, Rect(0, 0, FShot.Width, FShot.Height), FView.Font.PixelsPerInch);
  if FNext <= High(FChunks) then
  begin
    FView.Write(FChunks[FNext], @ChunkDone, FNext);
    Inc(FNext);
  end;
end;

{ What this holds is the memory and the glyph cache under a flood: the frames are drawn
  by ChunkDone (headless, one ProcessMessages runs slice after slice), so it proves the
  cache evicts, not that a real window repaints in time -- TestAFloodStillPaints does that
  on a shown window. }
procedure TTyTerminalPerfTests.TestAFloodKeepsMemoryFlat;
const
  Total = 20 * MB;
  Chunk = 64 * 1024;
  InFlight = 4;
var
  fx: TTyTermViewFixture;
  data: RawByteString;
  i, n, base, rows, t: Integer;
  heap0, heap1: Int64;
  bmp: TBitmap;
  w, h: Integer;
begin
  TyTermNeedWidgetSet;
  data := TyTermMixedText(Total, 6000);
  SetLength(data, Total);                        { 320 whole chunks; a cut character is fine }
  n := Total div Chunk;
  SetLength(FChunks, n);
  for i := 0 to n - 1 do
    FChunks[i] := Copy(data, i * Chunk + 1, Chunk);
  data := '';
  base := TTyTerminalLine.LiveCount;
  fx := TTyTermViewFixture.Create;
  bmp := TBitmap.Create;
  try
    FView := fx.View;
    fx.View.PassSlices := True;
    fx.View.RasterBudgetMs := 0;
    fx.SizeTo(120, 40);
    rows := fx.View.Rows;
    w := fx.View.ClientWidth;
    h := fx.View.ClientHeight;
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(w, h);
    fx.View.Render(bmp.Canvas, Rect(0, 0, w, h), fx.View.Font.PixelsPerInch);
    fx.View.Cache.ResetStats;
    FShot := bmp;
    heap0 := GetFPCHeapStatus.CurrHeapUsed;
    FDone := 0;
    FNext := 0;
    while (FNext < InFlight) and (FNext < n) do
    begin
      fx.View.Write(FChunks[FNext], @ChunkDone, FNext);
      Inc(FNext);
    end;
    t := 0;
    while (FDone < n) and (t < 2000000) do
    begin
      Forms.Application.ProcessMessages;
      Inc(t);
    end;
    heap1 := GetFPCHeapStatus.CurrHeapUsed;
    WriteLn(Format('  (flood: %d misses, %d evictions, %d in the cache, heap +%.1f MB, %d live lines)',
      [fx.View.Cache.Misses, fx.View.Cache.Evictions, fx.View.Cache.Count, (heap1 - heap0) / MB,
       TTyTerminalLine.LiveCount - base]));
    AssertEquals('every callback, once', n, FDone);
    AssertEquals('320 of them', 320, FDone);
    AssertTrue(Format('live lines %d <= rows %d + scrollback %d + 4',
      [TTyTerminalLine.LiveCount - base, rows, fx.View.Scrollback]),
      TTyTerminalLine.LiveCount - base <= rows + fx.View.Scrollback + 4);
    AssertTrue(Format('heap growth %.1f MB <= 32 MB', [(heap1 - heap0) / MB]), heap1 - heap0 <= 32 * MB);
    AssertTrue(Format('the glyph cache holds %d <= 4096', [fx.View.Cache.Count]), fx.View.Cache.Count <= 4096);
    AssertTrue(Format('it evicted (%d misses, %d evictions)', [fx.View.Cache.Misses, fx.View.Cache.Evictions]),
      fx.View.Cache.Evictions > 0);
  finally
    FView := nil;
    FShot := nil;
    FChunks := nil;
    bmp.Free;
    fx.Free;
  end;
end;

procedure TTyTerminalPerfTests.TestTheCacheHitsOnceWarm;
const
  Ids: array[0..1] of string = ('vim-edit', 'htop-few-frames');
var
  fx: TTyTermViewFixture;
  writes: TStringList;
  cols, rows, k, pass, i, w, h, misses1: Integer;
  bmp: TBitmap;
begin
  for k := 0 to High(Ids) do
  begin
    writes := RecordingBytes(Ids[k], cols, rows);
    fx := nil;
    bmp := TBitmap.Create;
    try
      AssertTrue(Ids[k] + ' found', writes.Count > 10);
      fx := TTyTermViewFixture.Create;
      fx.View.RasterBudgetMs := 0;
      fx.View.Scrollback := 200;
      fx.SizeTo(cols, rows);
      AssertEquals(Ids[k] + ' cols', cols, fx.View.Cols);
      w := fx.View.ClientWidth;
      h := fx.View.ClientHeight;
      bmp.PixelFormat := pf32bit;
      bmp.SetSize(w, h);
      misses1 := 0;
      { the second pass starts where the first ended: the same glyphs, other cells,
        other cursor places }
      for pass := 1 to 2 do
      begin
        if pass = 2 then misses1 := fx.View.Cache.Misses;
        for i := 0 to writes.Count - 1 do
        begin
          fx.View.WriteSync(writes[i]);
          fx.View.Render(bmp.Canvas, Rect(0, 0, w, h), fx.View.Font.PixelsPerInch);
        end;
      end;
      AssertTrue(Ids[k] + ': the first pass filled the cache', misses1 > 20);
      AssertEquals(Ids[k] + ': no miss on the second pass', 0, fx.View.Cache.Misses - misses1);
    finally
      bmp.Free;
      fx.Free;
      writes.Free;
    end;
  end;
end;

{ A slice's budget is looked at between pieces of TyTermSlicePieceBytes: the longest
  slice of one 20 MB Write stays within 12 ms and a few pieces (each timed alone in this
  run). Timed on the wall clock: tried twice before it counts as red (other test runs on
  the machine make it jitter). }
procedure TTyTerminalPerfTests.TestTheLongestSliceStaysNearTheBudget;
const
  Total = 20 * MB;
var
  data: RawByteString;
  core: TTyTerminalCore;
  t, longest, one: Double;
  pieces: array[0..2] of Double;
  k, attempt: Integer;
  more: Boolean;
begin
  data := TyTermMixedText(Total);
  longest := 0;
  one := 0;
  for attempt := 1 to 2 do
  begin
    { one piece, alone, in this run: three places, the slowest }
    for k := 0 to 2 do
    begin
      core := TTyTerminalCore.Create(200, 60);
      try
        core.Scrollback := 1000;
        core.WriteSync(Copy(data, 1 + k * 7 * MB, 16 * TyTermSlicePieceBytes));   { a full screen and scrollback first }
        t := TyTermDefaultClock;
        core.WriteSync(Copy(data, 1 + k * 7 * MB + 16 * TyTermSlicePieceBytes, TyTermSlicePieceBytes));
        pieces[k] := TyTermDefaultClock - t;
      finally
        core.Free;
      end;
    end;
    SortDoubles(pieces);
    one := pieces[2];
    core := TTyTerminalCore.Create(200, 60);
    try
      core.Scrollback := 1000;
      core.Write(data);
      longest := 0;
      repeat
        t := TyTermDefaultClock;
        more := core.ProcessPending(12);
        t := TyTermDefaultClock - t;
        if t > longest then longest := t;
      until not more;
      AssertEquals('all of it parsed', 0, core.PendingBytes);
    finally
      core.Free;
    end;
    if longest <= 12 + 3 * one + 2 then Break;
  end;
  WriteLn(Format('  (longest slice %.1f ms; one %d-byte piece %.1f ms)', [longest, TyTermSlicePieceBytes, one]));
  AssertTrue(Format('the longest slice %.1f ms <= 12 + 3 x %.1f ms + 2', [longest, one]),
    longest <= 12 + 3 * one + 2);
end;

{ The least a full repaint of this screen costs on this machine, timed in this run: a
  background and a glyph mask for every cell of it, as the row painter lays them down
  (TyTermBlendMask). A full repaint is held to a share of that, not to a number of
  milliseconds -- a slow machine is not red, a fast one is still held. (The view's frame
  fills a background run at a time, so it comes in at about half of it: 8.4 against
  16.5 ms on the build machine; 0.8 of it plus 3 ms is the bound.) }
function CellFloorMs(ACols, ARows, ACellW, ACellH: Integer): Double;
var
  bmp: TBGRABitmap;
  mask: TGrayscaleMask;
  times: array[0..4] of Double;
  k, r, c, x, y: Integer;
  t: Double;
begin
  bmp := TBGRABitmap.Create(ACols * ACellW, ARows * ACellH);
  mask := TGrayscaleMask.Create(ACellW, ACellH);
  try
    for y := 0 to ACellH - 1 do
      for x := 0 to ACellW - 1 do
        mask.SetPixel(x, y, Byte((x * 37 + y * 11) and 255));
    for k := 0 to High(times) do
    begin
      t := TyTermDefaultClock;
      for r := 0 to ARows - 1 do
        for c := 0 to ACols - 1 do
        begin
          bmp.FillRect(c * ACellW, r * ACellH, (c + 1) * ACellW, (r + 1) * ACellH, BGRA(20, 30, 40), dmSet);
          TyTermBlendMask(bmp, c * ACellW, r * ACellH, mask, $C0C0C0,
            Rect(c * ACellW, r * ACellH, (c + 1) * ACellW, (r + 1) * ACellH));
        end;
      times[k] := TyTermDefaultClock - t;
    end;
    SortDoubles(times);
    Result := times[2];
  finally
    mask.Free;
    bmp.Free;
  end;
end;

procedure TTyTerminalPerfTests.TestAFullRepaintIsNotSlower;
var
  fx: TTyTermViewFixture;
  bmp: TBitmap;
  times: array[0..19] of Double;
  k, w, h, attempt: Integer;
  t0, med, floor: Double;
begin
  fx := TTyTermViewFixture.Create;
  bmp := TBitmap.Create;
  try
    fx.View.RasterBudgetMs := 0;
    fx.SizeTo(200, 60);
    fx.View.WriteSync(TyTermMixedText(40000) + #27'[?25l');
    w := fx.View.ClientWidth;
    h := fx.View.ClientHeight;
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(w, h);
    fx.View.Render(bmp.Canvas, Rect(0, 0, w, h), fx.View.Font.PixelsPerInch);   { warm }
    med := 0;
    floor := 0;
    for attempt := 1 to 2 do
    begin
      floor := CellFloorMs(200, 60, fx.View.CellMetrics.CellW, fx.View.CellMetrics.CellH);
      for k := 0 to High(times) do
      begin
        fx.View.Forget;
        t0 := TyTermDefaultClock;
        fx.View.Render(bmp.Canvas, Rect(0, 0, w, h), fx.View.Font.PixelsPerInch);
        times[k] := TyTermDefaultClock - t0;
        AssertEquals('every row painted', fx.View.Rows, fx.View.PaintedLast);
      end;
      SortDoubles(times);
      med := (times[9] + times[10]) / 2;
      if med <= 0.8 * floor + 3 then Break;
    end;
    WriteLn(Format('  (200 x 60 full repaint, warm: median %.1f ms; a fill and a mask per cell %.1f ms)', [med, floor]));
    AssertTrue(Format('median %.1f ms <= 0.8 x %.1f ms + 3', [med, floor]), med <= 0.8 * floor + 3);
  finally
    bmp.Free;
    fx.Free;
  end;
end;

{ The contrast caches answer a warm frame whole: every cell that asks (it has a glyph or
  a line, it is not left out, it is not invisible) finds its pair, none is added. Counted
  -- then the time at 4.5 against 1, tried twice. }
procedure TTyTerminalPerfTests.TestContrastCostsLittle;
var
  fx: TTyTermViewFixture;
  bmp: TBitmap;
  times: array[0..19] of Double;
  med: array[0..1] of Double;
  k, w, h, pass, attempt, asks, r, c, hits, misses, count: Integer;
  t0: Double;
  buf: TTyTerminalBuffer;
  line: TTyTerminalLine;
  attr: TTyTerminalAttrData;
  cp: Cardinal;
begin
  fx := TTyTermViewFixture.Create;
  bmp := TBitmap.Create;
  try
    fx.View.RasterBudgetMs := 0;
    fx.SizeTo(200, 60);
    { a screen of mixed text: 16, 256 and true colours every few words }
    fx.View.WriteSync(TyTermMixedText(40000) + #27'[?25l');
    w := fx.View.ClientWidth;
    h := fx.View.ClientHeight;
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(w, h);
    for attempt := 1 to 2 do
    begin
      for pass := 0 to 1 do
      begin
        if pass = 0 then fx.View.MinimumContrastRatio := 1 else fx.View.MinimumContrastRatio := 4.5;
        { warm: the glyphs and, at 4.5, the colour pairs }
        fx.View.Render(bmp.Canvas, Rect(0, 0, w, h), fx.View.Font.PixelsPerInch);
        fx.View.Forget;
        fx.View.Render(bmp.Canvas, Rect(0, 0, w, h), fx.View.Font.PixelsPerInch);
        for k := 0 to High(times) do
        begin
          fx.View.Forget;
          t0 := TyTermDefaultClock;
          fx.View.Render(bmp.Canvas, Rect(0, 0, w, h), fx.View.Font.PixelsPerInch);
          times[k] := TyTermDefaultClock - t0;
        end;
        SortDoubles(times);
        med[pass] := (times[9] + times[10]) / 2;
      end;
      if med[1] <= 1.3 * med[0] then Break;
    end;
    AssertTrue('pairs were cached', fx.View.Contrast.Count > 0);
    { the cells that ask, counted from the buffer }
    buf := fx.View.Core.Buffer;
    asks := 0;
    for r := 0 to fx.View.Rows - 1 do
    begin
      line := buf.GetLine(buf.YDisp + r);
      if line = nil then Continue;
      for c := 0 to Min(fx.View.Cols, line.Length) - 1 do
      begin
        if (c > 0) and (line.GetWidth(c) = 0) then Continue;
        attr.Fg := line.GetFg(c);
        attr.Bg := line.GetBg(c);
        if attr.IsInvisible then Continue;
        cp := line.GetCodePoint(c);
        if (line.GetContent(c) and TyTermContentIsCombinedMask) = 0 then
        begin
          if ((cp = 0) or (cp = 32)) and not attr.IsUnderline and not attr.IsStrikethrough
            and not attr.IsOverline then Continue;
          if TyTermExcludedFromContrast(cp) then Continue;
        end;
        Inc(asks);
      end;
    end;
    hits := fx.View.Contrast.Hits + fx.View.HalfContrast.Hits;
    misses := fx.View.Contrast.Misses + fx.View.HalfContrast.Misses;
    count := fx.View.Contrast.Count + fx.View.HalfContrast.Count;
    fx.View.Forget;
    fx.View.Render(bmp.Canvas, Rect(0, 0, w, h), fx.View.Font.PixelsPerInch);
    AssertTrue(Format('cells that ask: %d', [asks]), asks > 2000);
    AssertEquals('a warm frame misses nothing', 0, fx.View.Contrast.Misses + fx.View.HalfContrast.Misses - misses);
    AssertEquals('and adds no pair', count, fx.View.Contrast.Count + fx.View.HalfContrast.Count);
    AssertEquals('every cell that asks found its pair', asks, fx.View.Contrast.Hits + fx.View.HalfContrast.Hits - hits);
    WriteLn(Format('  (200 x 60 full repaint, warm: %.1f ms at 1, %.1f ms at 4.5)', [med[0], med[1]]));
    AssertTrue(Format('at 4.5 %.1f ms <= 1.3 x %.1f ms', [med[1], med[0]]), med[1] <= 1.3 * med[0]);
  finally
    bmp.Free;
    fx.Free;
  end;
end;

procedure TPaintRecorder.Paint;
begin
  if Recording then
  begin
    SetLength(Paints, Length(Paints) + 1);
    Paints[High(Paints)] := TyTermDefaultClock;
  end;
  inherited Paint;
end;

{ The view on a shown form, a flood of Writes with callbacks, the message loop pumped
  until they are all back: the window paints all along. The next slice goes through the
  async queue, which posts a message a slice; Windows hands out WM_PAINT only when no
  posted message waits, so the view paints a due frame itself (UpdateWindow) -- without
  that the window did not paint at all until the flood was nearly over. Paint times are
  recorded from the first write to the last callback; the longest stretch without one
  (the start and the end included) stays far below a second. }
procedure TTyTerminalPerfTests.TestAFloodStillPaints;
const
  Total = 6 * MB;
  Chunk = 64 * 1024;
  InFlight = 4;
var
  fx: TTyTermViewFixture;
  rec: TPaintRecorder;
  data: RawByteString;
  i, n, t: Integer;
  t0, t1, gap: Double;
begin
  TyTermNeedWidgetSet;
  data := TyTermMixedText(Total);
  SetLength(data, Total);
  n := Total div Chunk;
  SetLength(FChunks, n);
  for i := 0 to n - 1 do
    FChunks[i] := Copy(data, i * Chunk + 1, Chunk);
  data := '';
  fx := TTyTermViewFixture.Create;
  try
    rec := TPaintRecorder.Create(fx.Form);
    rec.Controller := fx.Ctl;
    rec.Parent := fx.Form;
    rec.PassSlices := True;
    rec.SetBounds(0, 0, 900, 500);
    fx.Form.SetBounds(60, 60, 900, 500);
    fx.Form.Show;
    for i := 1 to 20 do Forms.Application.ProcessMessages;
    FView := rec;
    FShot := nil;
    FDone := 0;
    FNext := 0;
    rec.Recording := True;
    t0 := TyTermDefaultClock;
    while (FNext < InFlight) and (FNext < n) do
    begin
      rec.Write(FChunks[FNext], @ChunkDone, FNext);
      Inc(FNext);
    end;
    t := 0;
    while (FDone < n) and (t < 2000000) do
    begin
      Forms.Application.ProcessMessages;
      Inc(t);
    end;
    t1 := TyTermDefaultClock;
    rec.Recording := False;
    fx.Form.Hide;
    AssertEquals('every callback', n, FDone);
    AssertTrue(Format('painted during the flood (%d paints)', [Length(rec.Paints)]), Length(rec.Paints) >= 3);
    gap := rec.Paints[0] - t0;
    for i := 1 to High(rec.Paints) do
      gap := Max(gap, rec.Paints[i] - rec.Paints[i - 1]);
    gap := Max(gap, t1 - rec.Paints[High(rec.Paints)]);
    WriteLn(Format('  (flood on a shown window: %.0f ms, %d paints, longest without one %.1f ms)',
      [t1 - t0, Length(rec.Paints), gap]));
    AssertTrue(Format('the longest stretch without a paint %.1f ms < 300 ms', [gap]), gap < 300);
  finally
    FView := nil;
    FChunks := nil;
    fx.Free;
  end;
end;

initialization
  RegisterTest(TTyTerminalPerfTests);
end.
