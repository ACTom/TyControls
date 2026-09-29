unit test.terminal.perf;
{$mode objfpc}{$H+}
{ The terminal's resource and time guards (phase 5, Task 9).

  What can be counted is counted (live lines, heap growth, glyph cache entries, misses and
  evictions); the two timed tests use the wall clock and a generous bound -- relative to a
  piece timed in the same run, or a multiple of the phase-3 number -- and the exact numbers
  live in the spec, not in the asserts.

  The mixed text is tools/terminal-bench's generator (same seed, same line shape): words,
  CJK from a pool of code points, emoji, a combining mark, numbers and punctuation, a colour
  change every few words, lines of 60-200 columns. }

interface

uses
  Classes, SysUtils, Types, Math, fpcunit, testregistry, fpjson, Forms, Graphics,
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

procedure TTyTerminalPerfTests.TestTheLongestSliceStaysNearTheBudget;
const
  Total = 20 * MB;
  Piece = 128 * 1024;
var
  data: RawByteString;
  core: TTyTerminalCore;
  t, longest, one: Double;
  pieces: array[0..2] of Double;
  k: Integer;
  more: Boolean;
begin
  data := TyTermMixedText(Total);
  { one piece, alone, in this run: three places, the slowest }
  for k := 0 to 2 do
  begin
    core := TTyTerminalCore.Create(200, 60);
    try
      core.Scrollback := 1000;
      core.WriteSync(Copy(data, 1 + k * 7 * MB, 4 * Piece));   { a full screen and scrollback first }
      t := TyTermDefaultClock;
      core.WriteSync(Copy(data, 1 + k * 7 * MB + 4 * Piece, Piece));
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
    data := '';
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
  WriteLn(Format('  (longest slice %.1f ms; one 128 KB piece %.1f ms)', [longest, one]));
  AssertTrue(Format('the longest slice %.1f ms <= 12 + 3 x %.1f ms', [longest, one]),
    longest <= 12 + 3 * one);
end;

procedure TTyTerminalPerfTests.TestAFullRepaintIsNotSlower;
var
  fx: TTyTermViewFixture;
  bmp: TBitmap;
  times: array[0..19] of Double;
  k, w, h: Integer;
  t0: Double;
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
    for k := 0 to High(times) do
    begin
      fx.View.Forget;
      t0 := TyTermDefaultClock;
      fx.View.Render(bmp.Canvas, Rect(0, 0, w, h), fx.View.Font.PixelsPerInch);
      times[k] := TyTermDefaultClock - t0;
      AssertEquals('every row painted', fx.View.Rows, fx.View.PaintedLast);
    end;
    SortDoubles(times);
    WriteLn(Format('  (200 x 60 full repaint, warm: median %.1f ms)', [(times[9] + times[10]) / 2]));
    AssertTrue(Format('median %.1f ms <= 30 ms', [(times[9] + times[10]) / 2]), (times[9] + times[10]) / 2 <= 30);
  finally
    bmp.Free;
    fx.Free;
  end;
end;

procedure TTyTerminalPerfTests.TestContrastCostsLittle;
var
  fx: TTyTermViewFixture;
  bmp: TBitmap;
  times: array[0..19] of Double;
  med: array[0..1] of Double;
  k, w, h, pass: Integer;
  t0: Double;
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
    AssertTrue('pairs were cached', fx.View.Contrast.Count > 0);
    WriteLn(Format('  (200 x 60 full repaint, warm: %.1f ms at 1, %.1f ms at 4.5)', [med[0], med[1]]));
    AssertTrue(Format('at 4.5 %.1f ms <= 1.3 x %.1f ms', [med[1], med[0]]), med[1] <= 1.3 * med[0]);
  finally
    bmp.Free;
    fx.Free;
  end;
end;

initialization
  RegisterTest(TTyTerminalPerfTests);
end.
