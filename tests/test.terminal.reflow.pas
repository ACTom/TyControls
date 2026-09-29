unit test.terminal.reflow;
{$mode objfpc}{$H+}
{ The reflow on a new column count (phase 5, Task 4).

  TTyTerminalReflowOracleTests hold the five BufferReflow.ts functions to upstream's
  own answers (terminal-reflow-units.json, tools/terminal-oracle/reflow-cases.js): the
  new line lengths of a narrower reflow, the trimmed length of a wrapped row, the rows
  a wider reflow removes (and the lines as that call leaves them), and the new layout
  with the delete events it sends. The whole-terminal reflow cases are in the core
  oracle (TTyTerminalCoreOracleTests.TestReflowCases), the buffer-level ones in the
  buffer oracle.

  TTyTerminalReflowTests: what upstream has no oracle for -- one column refused where
  upstream loops for ever, no line or marker outliving a reflow, the trim count a
  selection follows, the core's ReflowCursorLine, and the cost with a deep scrollback. }

interface

uses
  Classes, SysUtils, Types, fpcunit, testregistry, fpjson,
  tyControls.Terminal.Buffer, tyControls.Terminal.Core, test.terminal.oracle;

type
  TTyTerminalReflowOracleTests = class(TTestCase)
  published
    procedure TestFixtureComesFromThePinnedUpstream;
    procedure TestNewLineLengths;
    procedure TestWrappedLineTrimmedLength;
    procedure TestLinesToRemove;
    procedure TestNewLayoutAndItsEvents;
  end;

  TTyTerminalReflowTests = class(TTestCase)
  published
    procedure TestOneColumnIsRefused;
    procedure TestNoLineOrMarkerLeaks;
    procedure TestTrimmedLinesFollowsReflow;
    procedure TestReflowCursorLineProperty;
    procedure TestDeepScrollbackReflowIsQuick;
    procedure TestNarrowingAFullScrollbackKeepsThePrompt;
    procedure TestAHundredThousandLinesReflowInLinearTime;
    procedure TestNarrowerAgainGivesTheMemoryBack;
    procedure TestTheBlockCopyMatchesTheCellCopy;
  end;

implementation

{ ---- the units fixture -------------------------------------------------------------- }

function LoadUnits: TJSONObject;
var
  fs: TFileStream;
begin
  fs := TFileStream.Create(TyTermFixturePath('terminal-reflow-units.json'), fmOpenRead or fmShareDenyWrite);
  try
    Result := TJSONObject(GetJSON(fs));
  finally
    fs.Free;
  end;
end;

{ A line as the fixture writes it -- cols, wrapped, cells as [cp, width] pairs from
  column 0: [0, 1] an empty cell (left as the new line's NULL cell), [0, 0] the
  second half of a wide character. }
function LineFromJson(AObj: TJSONObject): TTyTerminalLine;
var
  cells: TJSONArray;
  x: Integer;
  cp: Cardinal;
  w: Integer;
begin
  Result := TTyTerminalLine.CreateDefault(AObj.Integers['cols'], AObj.Booleans['wrapped']);
  cells := AObj.Arrays['cells'];
  for x := 0 to cells.Count - 1 do
  begin
    cp := Cardinal(cells.Arrays[x].Int64s[0]);
    w := cells.Arrays[x].Integers[1];
    if (cp = 0) and (w = 1) then
      Continue;
    Result.SetCellFromCodepoint(x, cp, w, TyTermDefaultAttr);
  end;
end;

function LinesFromJson(AArr: TJSONArray): TTyTermLineArray;
var
  i: Integer;
begin
  Result := nil;
  SetLength(Result, AArr.Count);
  for i := 0 to AArr.Count - 1 do
    Result[i] := LineFromJson(AArr.Objects[i]);
end;

procedure ReleaseLines(var A: TTyTermLineArray);
var
  i: Integer;
begin
  for i := 0 to High(A) do
    A[i].Release;
  A := nil;
end;

{ every column as [codepoint, width], wrapped, cols -- the fixture's "after" shape }
function LineText(ALine: TTyTerminalLine): string;
var
  x: Integer;
begin
  Result := IntToStr(ALine.Length) + BoolToStr(ALine.IsWrapped, ' w', '') + ':';
  for x := 0 to ALine.Length - 1 do
    Result := Result + ' ' + IntToStr(ALine.GetCodePoint(x)) + '/' + IntToStr(ALine.GetWidth(x));
end;

function JsonLineText(AObj: TJSONObject): string;
var
  cells: TJSONArray;
  x: Integer;
begin
  Result := IntToStr(AObj.Integers['cols']) + BoolToStr(AObj.Booleans['wrapped'], ' w', '') + ':';
  cells := AObj.Arrays['cells'];
  for x := 0 to cells.Count - 1 do
    Result := Result + ' ' + IntToStr(cells.Arrays[x].Int64s[0]) + '/' + IntToStr(cells.Arrays[x].Integers[1]);
end;

function IntsText(const A: TIntegerDynArray): string;
var
  i: Integer;
begin
  Result := '[';
  for i := 0 to High(A) do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + IntToStr(A[i]);
  end;
  Result := Result + ']';
end;

function JsonIntsText(AArr: TJSONArray): string;
var
  i: Integer;
begin
  Result := '[';
  for i := 0 to AArr.Count - 1 do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + IntToStr(AArr.Integers[i]);
  end;
  Result := Result + ']';
end;

{ the lines of a case as a ring of exactly their number (reflow-cases.js listOf) }
function ListFromJson(AArr: TJSONArray): TTyTerminalLineList;
var
  i, n: Integer;
begin
  n := AArr.Count;
  if n < 1 then n := 1;
  Result := TTyTerminalLineList.Create(n);
  for i := 0 to AArr.Count - 1 do
    Result.PushOwned(LineFromJson(AArr.Objects[i]));
end;

type
  TDeleteRec = class
  public
    Text: string;
    procedure OnDelete(AIndex, AAmount: Integer);
  end;

procedure TDeleteRec.OnDelete(AIndex, AAmount: Integer);
begin
  Text := Text + Format('[%d,%d]', [AIndex, AAmount]);
end;

function JsonEventsText(AArr: TJSONArray): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to AArr.Count - 1 do
    Result := Result + Format('[%d,%d]', [AArr.Arrays[i].Integers[0], AArr.Arrays[i].Integers[1]]);
end;

{ ---- TTyTerminalReflowOracleTests ------------------------------------------------------ }

procedure TTyTerminalReflowOracleTests.TestFixtureComesFromThePinnedUpstream;
var
  u: TJSONObject;
  m: TTyTermMisses;
begin
  u := LoadUnits;
  m := TTyTermMisses.Create;
  try
    TyTermCheckUpstream(u, 'reflow-units', m);
    AssertEquals(m.Text, 0, m.Count);
    AssertEquals('kind', 'reflow-units', u.Strings['kind']);
  finally
    m.Free;
    u.Free;
  end;
end;

procedure TTyTerminalReflowOracleTests.TestNewLineLengths;
var
  u, t: TJSONObject;
  arr: TJSONArray;
  lines: TTyTermLineArray;
  i, compared: Integer;
  got: string;
begin
  u := LoadUnits;
  try
    arr := u.Arrays['newLineLengths'];
    compared := 0;
    for i := 0 to arr.Count - 1 do
    begin
      t := arr.Objects[i];
      lines := LinesFromJson(t.Arrays['lines']);
      try
        got := IntsText(TyTermReflowSmallerGetNewLineLengths(lines, t.Integers['oldCols'], t.Integers['newCols']));
      finally
        ReleaseLines(lines);
      end;
      AssertEquals(Format('case %d (%d -> %d)', [i, t.Integers['oldCols'], t.Integers['newCols']]),
        JsonIntsText(t.Arrays['result']), got);
      Inc(compared);
    end;
    { the cases reflow-cases.js writes, counted there: a fixture that lost some is red }
    AssertEquals('cases read', 27, arr.Count);
    AssertEquals('compared', arr.Count, compared);
  finally
    u.Free;
  end;
end;

procedure TTyTerminalReflowOracleTests.TestWrappedLineTrimmedLength;
var
  u, t: TJSONObject;
  arr: TJSONArray;
  lines: TTyTermLineArray;
  i, compared, got: Integer;
begin
  u := LoadUnits;
  try
    arr := u.Arrays['trimmedLength'];
    compared := 0;
    for i := 0 to arr.Count - 1 do
    begin
      t := arr.Objects[i];
      lines := LinesFromJson(t.Arrays['lines']);
      try
        got := TyTermGetWrappedLineTrimmedLength(lines, t.Integers['i'], t.Integers['cols']);
      finally
        ReleaseLines(lines);
      end;
      AssertEquals(Format('case %d', [i]), t.Integers['result'], got);
      Inc(compared);
    end;
    AssertEquals('cases read', 7, arr.Count);
    AssertEquals('compared', arr.Count, compared);
  finally
    u.Free;
  end;
end;

procedure TTyTerminalReflowOracleTests.TestLinesToRemove;
var
  u, t: TJSONObject;
  arr, after: TJSONArray;
  list: TTyTerminalLineList;
  i, k, compared: Integer;
  got: TIntegerDynArray;
begin
  u := LoadUnits;
  try
    arr := u.Arrays['linesToRemove'];
    compared := 0;
    for i := 0 to arr.Count - 1 do
    begin
      t := arr.Objects[i];
      list := ListFromJson(t.Arrays['lines']);
      try
        got := TyTermReflowLargerGetLinesToRemove(list, t.Integers['oldCols'], t.Integers['newCols'],
          t.Integers['absY'], TyTermNullCell(TyTermDefaultAttr), t.Booleans['reflowCursorLine']);
        AssertEquals(Format('case %d: rows to remove', [i]), JsonIntsText(t.Arrays['result']), IntsText(got));
        Inc(compared);
        { the lines as the call leaves them (it moves the cells) }
        after := t.Arrays['after'];
        AssertEquals(Format('case %d: lines', [i]), after.Count, list.Length);
        for k := 0 to after.Count - 1 do
        begin
          AssertEquals(Format('case %d: line %d after', [i, k]), JsonLineText(after.Objects[k]), LineText(list.Get(k)));
          Inc(compared);
        end;
      finally
        list.Free;
      end;
    end;
    AssertEquals('cases read', 8, arr.Count);
    k := 0;
    for i := 0 to arr.Count - 1 do
      Inc(k, 1 + arr.Objects[i].Arrays['after'].Count);
    AssertEquals('compared', k, compared);
  finally
    u.Free;
  end;
end;

procedure TTyTerminalReflowOracleTests.TestNewLayoutAndItsEvents;
var
  u, t: TJSONObject;
  arr: TJSONArray;
  list: TTyTerminalLineList;
  i, compared: Integer;
  toRemove: TIntegerDynArray;
  layout: TTyTermReflowLayout;
  rec: TDeleteRec;
begin
  u := LoadUnits;
  rec := TDeleteRec.Create;
  try
    arr := u.Arrays['linesToRemove'];
    compared := 0;
    for i := 0 to arr.Count - 1 do
    begin
      t := arr.Objects[i];
      list := ListFromJson(t.Arrays['lines']);
      try
        toRemove := TyTermReflowLargerGetLinesToRemove(list, t.Integers['oldCols'], t.Integers['newCols'],
          t.Integers['absY'], TyTermNullCell(TyTermDefaultAttr), t.Booleans['reflowCursorLine']);
        { as reflow-cases.js: listening from here on }
        rec.Text := '';
        list.OnDelete := @rec.OnDelete;
        layout := TyTermReflowLargerCreateNewLayout(list, toRemove);
        AssertEquals(Format('case %d: layout', [i]), JsonIntsText(t.Arrays['layout']), IntsText(layout.Layout));
        AssertEquals(Format('case %d: countRemoved', [i]), t.Integers['countRemoved'], layout.CountRemoved);
        AssertEquals(Format('case %d: delete events', [i]), JsonEventsText(t.Arrays['events']), rec.Text);
        Inc(compared, 3);
      finally
        list.OnDelete := nil;
        list.Free;
      end;
    end;
    AssertEquals('cases read', 8, arr.Count);
    AssertEquals('compared', 3 * arr.Count, compared);
  finally
    rec.Free;
    u.Free;
  end;
end;

{ ---- TTyTerminalReflowTests ---------------------------------------------------------- }

type
  { upstream loops for ever on this input: run it where a hang cannot stop the suite }
  TOneColumnThread = class(TThread)
  public
    Raised: Boolean;
    RaisedClass: string;
    Answered: Boolean;
  protected
    procedure Execute; override;
  end;

procedure TOneColumnThread.Execute;
var
  line: TTyTerminalLine;
  lines: TTyTermLineArray;
begin
  line := TTyTerminalLine.CreateDefault(4);
  try
    line.SetCellFromCodepoint(0, Ord('a'), 1, TyTermDefaultAttr);
    line.SetCellFromCodepoint(1, $6C49, 2, TyTermDefaultAttr);
    line.SetCellFromCodepoint(2, 0, 0, TyTermDefaultAttr);
    line.SetCellFromCodepoint(3, Ord('b'), 1, TyTermDefaultAttr);
    lines := nil;
    SetLength(lines, 1);
    lines[0] := line;
    try
      TyTermReflowSmallerGetNewLineLengths(lines, 4, 1);
      Answered := True;
    except
      on E: Exception do
      begin
        Raised := True;
        RaisedClass := E.ClassName;
      end;
    end;
  finally
    line.Release;
  end;
end;

procedure TTyTerminalReflowTests.TestOneColumnIsRefused;
var
  th: TOneColumnThread;
  t0: QWord;
  core: TTyTerminalCore;
begin
  { the buffer layer: raises where upstream would loop (a wide character at a cut of
    one column); bounded in time so a hang is a red test, not a stuck suite }
  th := TOneColumnThread.Create(True);
  th.FreeOnTerminate := False;
  th.Start;
  t0 := GetTickCount64;
  while not th.Finished and (GetTickCount64 - t0 < 2000) do
    Sleep(5);
  if not th.Finished then
    Fail('TyTermReflowSmallerGetNewLineLengths(..., 1) did not come back in 2 s (it loops, as upstream)');
  try
    AssertTrue('raised', th.Raised);
    AssertEquals('the exception', 'EArgumentOutOfRangeException', th.RaisedClass);
    AssertFalse('answered', th.Answered);
  finally
    th.Free;
  end;
  { through the core: one column is two (BufferService MINIMUM_COLS), and the wide
    characters rewrap }
  core := TTyTerminalCore.Create(10, 5);
  try
    core.WriteSync(#$E4#$B8#$AD#$E6#$96#$87'ab'#$E5#$AD#$97#13#10'$ ');
    core.Resize(1, 5);
    AssertEquals('cols', 2, core.Cols);
    AssertEquals('row 0', #$E4#$B8#$AD, core.Buffer.GetLine(0).TranslateToString(True));
    AssertEquals('row 1', #$E6#$96#$87, core.Buffer.GetLine(1).TranslateToString(True));
    AssertTrue('row 1 wrapped', core.Buffer.GetLine(1).IsWrapped);
    AssertEquals('row 2', 'ab', core.Buffer.GetLine(2).TranslateToString(True));
    AssertEquals('row 3', #$E5#$AD#$97, core.Buffer.GetLine(3).TranslateToString(True));
  finally
    core.Free;
  end;
end;

procedure TTyTerminalReflowTests.TestNoLineOrMarkerLeaks;
var
  m: TTyTermMisses;
  fx: TTyTermFixtures;
  cases: TFPList;
  c: TJSONObject;
  i, k, lines0, markers0, n: Integer;
  h: TTyTermHarness;
  palette: TJSONArray;
begin
  m := TTyTermMisses.Create;
  try
    fx := TyTermLoadFixtures('core-reflow', m);
    try
      AssertEquals(m.Text, 0, m.Count);
      n := 0;
      for k := 0 to High(fx) do
      begin
        palette := fx[k].Arrays['palette'];
        cases := TFPList.Create;
        try
          for i := 0 to fx[k].Arrays['cases'].Count - 1 do
            cases.Add(fx[k].Arrays['cases'].Objects[i]);
          for i := 0 to cases.Count - 1 do
          begin
            c := TJSONObject(cases[i]);
            lines0 := TTyTerminalLine.LiveCount;
            markers0 := TTyTerminalMarker.LiveCount;
            h := TTyTermHarness.Create(c, palette);
            try
              h.Run(c.Arrays['steps']);
              h.Core.Reset;
              h.Run(c.Arrays['steps']);
            finally
              h.Free;
            end;
            m.AddCompared(2);
            if TTyTerminalLine.LiveCount <> lines0 then
              m.Add(c.Strings['id'], 'lines alive', IntToStr(lines0), IntToStr(TTyTerminalLine.LiveCount));
            if TTyTerminalMarker.LiveCount <> markers0 then
              m.Add(c.Strings['id'], 'markers alive', IntToStr(markers0), IntToStr(TTyTerminalMarker.LiveCount));
            Inc(n);
          end;
        finally
          cases.Free;
        end;
      end;
    finally
      TyTermFreeFixtures(fx);
    end;
    AssertEquals(m.Text, 0, m.Count);
    AssertTrue('cases', n >= 244);
    AssertEquals('compared', 2 * n, m.Compared);
  finally
    m.Free;
  end;
end;

{ The selection fixture's reflow-trim-shifts: the same bytes and resize on a core; the
  buffer's TrimmedLines grows by what upstream's list trimmed that step (the count the
  control moves a selection by). }
procedure TTyTerminalReflowTests.TestTrimmedLinesFollowsReflow;
var
  m: TTyTermMisses;
  fx: TTyTermFixtures;
  cases: TFPList;
  c, st: TJSONObject;
  steps: TJSONArray;
  i: Integer;
  core: TTyTerminalCore;
  before: Int64;
  found: Boolean;
begin
  m := TTyTermMisses.Create;
  try
    fx := TyTermLoadFixtures('selection', m);
    cases := TyTermAllCases(fx);
    try
      found := False;
      for i := 0 to cases.Count - 1 do
      begin
        c := TJSONObject(cases[i]);
        if c.Strings['id'] <> 'reflow-trim-shifts' then
          Continue;
        found := True;
        steps := c.Arrays['steps'];
        core := TTyTerminalCore.Create(c.Integers['cols'], c.Integers['rows']);
        try
          core.Scrollback := c.Integers['scrollback'];
          core.WriteSync(TyTermBase64Bytes(steps.Objects[0].Strings['write']));
          st := steps.Objects[2];
          AssertTrue('step 2 is the resize', st.Find('resize') <> nil);
          before := core.Buffer.TrimmedLines;
          core.Resize(st.Arrays['resize'].Integers[0], st.Arrays['resize'].Integers[1]);
          AssertTrue('upstream trimmed some', st.Objects['after'].Integers['trimmed'] > 0);
          AssertEquals('trimmed by the reflow', st.Objects['after'].Integers['trimmed'],
            core.Buffer.TrimmedLines - before);
        finally
          core.Free;
        end;
      end;
      AssertTrue('case found', found);
    finally
      cases.Free;
      TyTermFreeFixtures(fx);
    end;
  finally
    m.Free;
  end;
end;

procedure TTyTerminalReflowTests.TestReflowCursorLineProperty;
var
  core: TTyTerminalCore;
begin
  { the prompt's run, the cursor in it: kept by default (OptionsService.ts:50) }
  core := TTyTerminalCore.Create(10, 6);
  try
    AssertFalse('default', core.ReflowCursorLine);
    core.WriteSync('$ abcdefghijKLM');
    core.Resize(20, 6);
    AssertEquals('default: two rows', '$ abcdefgh', core.Buffer.GetLine(0).TranslateToString(True));
    AssertTrue('default: the second row still wrapped', core.Buffer.GetLine(1).IsWrapped);
  finally
    core.Free;
  end;
  core := TTyTerminalCore.Create(10, 6);
  try
    core.ReflowCursorLine := True;
    AssertTrue('set', core.ReflowCursorLine);
    core.WriteSync('$ abcdefghijKLM');
    core.Resize(20, 6);
    AssertEquals('on: one row', '$ abcdefghijKLM', core.Buffer.GetLine(0).TranslateToString(True));
    AssertFalse('on: nothing wrapped below', core.Buffer.GetLine(1).IsWrapped);
  finally
    core.Free;
  end;
end;

procedure TTyTerminalReflowTests.TestDeepScrollbackReflowIsQuick;
var
  core: TTyTerminalCore;
  line, data: RawByteString;
  i: Integer;
  t, narrow, wide: Double;
begin
  line := '';
  for i := 0 to 399 do
    line := line + Chr(Ord('a') + i mod 26);
  line := line + #13#10;
  data := '';
  for i := 1 to 5100 do
    data := data + line;
  core := TTyTerminalCore.Create(200, 60);
  try
    core.Scrollback := 10000;
    core.WriteSync(data);
    AssertEquals('filled', 10060, core.Buffer.Lines.Length);
    t := TyTermDefaultClock;
    core.Resize(120, 60);
    narrow := TyTermDefaultClock - t;
    t := TyTermDefaultClock;
    core.Resize(200, 60);
    wide := TyTermDefaultClock - t;
    WriteLn(Format('reflow, Scrollback 10000, 400-column lines: 200 -> 120 %.1f ms, 120 -> 200 %.1f ms', [narrow, wide]));
    { a generous bound (the plan's question two #14): a quadratic reflow takes seconds }
    AssertTrue(Format('200 -> 120 took %.1f ms', [narrow]), narrow < 1000);
    AssertTrue(Format('120 -> 200 took %.1f ms', [wide]), wide < 1000);
    { and relative to the same run: widening moves fewer lines than narrowing makes (about
      half its time); removing the emptied rows one splice at a time instead of one new
      layout (quadratic) made it five times the narrowing }
    AssertTrue(Format('120 -> 200 (%.1f ms) within twice 200 -> 120 (%.1f ms)', [wide, narrow]), wide < 2 * narrow + 20);
  finally
    core.Free;
  end;
end;

{ Upstream's _reflowSmaller writes a run's new lines below index 0 once the ring's
  start has moved (Buffer.ts:504-510), and the ring wraps them onto the LAST lines: a
  full scrollback narrowed turned the prompt row into the line pushed out at the top.
  Not copied (unit header, spec 15): the prompt stays the last row, the cursor on it. }
procedure TTyTerminalReflowTests.TestNarrowingAFullScrollbackKeepsThePrompt;
var
  core: TTyTerminalCore;
  data: RawByteString;
  i: Integer;
  buf: TTyTerminalBuffer;
begin
  data := '';
  for i := 0 to 19 do
    data := data + StringOfChar(Chr(Ord('A') + i), 12) + #13#10;
  data := data + '$ ';
  core := TTyTerminalCore.Create(20, 3);
  try
    core.Scrollback := 5;
    core.WriteSync(data);
    core.Resize(5, 3);
    buf := core.Buffer;
    AssertEquals('the cursor row is the prompt', '$ ',
      buf.GetLine(buf.YBase + buf.Y).TranslateToString(True));
    AssertEquals('the last line is the prompt', '$ ',
      buf.GetLine(buf.Lines.Length - 1).TranslateToString(True));
    AssertEquals('above it the end of the last output', 'TT',
      buf.GetLine(buf.Lines.Length - 2).TranslateToString(True));
  finally
    core.Free;
  end;
end;

{ Filled with (Rows + Scrollback) lines of 100 columns, 120 -> 70 -> 120 columns, at
  10 000 and at 100 000 lines of scrollback: a reflow that grew faster than the number
  of lines (a splice per run, a search per line) is ten times slower per line at the
  larger size; this one stays within three times (the ring's lines are touched once
  each), and the larger one within a generous bound. }
procedure TTyTerminalReflowTests.TestAHundredThousandLinesReflowInLinearTime;

  function Measure(AScrollback: Integer; out ALines: Integer): Double;
  var
    core: TTyTerminalCore;
    line, data: RawByteString;
    i: Integer;
    t: Double;
  begin
    line := '';
    for i := 0 to 99 do
      line := line + Chr(Ord('a') + i mod 26);
    line := line + #13#10;
    data := '';
    SetLength(data, 0);
    for i := 1 to AScrollback + 40 do
      data := data + line;
    core := TTyTerminalCore.Create(120, 40);
    try
      core.Scrollback := AScrollback;
      core.WriteSync(data);
      data := '';
      ALines := core.Buffer.Lines.Length;          { full before the first reflow }
      t := TyTermDefaultClock;
      core.Resize(70, 40);
      core.Resize(120, 40);
      Result := TyTermDefaultClock - t;
    finally
      core.Free;
    end;
  end;

var
  small, big: Double;
  n1, n2, attempt: Integer;
begin
  for attempt := 1 to 2 do
  begin
    small := Measure(10000, n1);
    big := Measure(100000, n2);
    if big <= 3 * 10 * small + 50 then Break;
  end;
  WriteLn(Format('  (reflow 120 -> 70 -> 120: %d lines %.1f ms, %d lines %.1f ms)', [n1, small, n2, big]));
  AssertTrue(Format('the ring is full (%d, %d lines)', [n1, n2]), (n1 = 10040) and (n2 = 100040));
  AssertTrue(Format('100 000 lines %.1f ms within 3 x 10 x %.1f ms + 50', [big, small]), big <= 3 * 10 * small + 50);
  AssertTrue(Format('100 000 lines %.1f ms < 10 s', [big]), big < 10000);
end;

{ Wider, then narrower again: upstream cuts every line's allocation back to its cells
  (cleanupMemory, from Buffer.resize's _memoryCleanupQueue). 10 000 lines at 80 columns
  widened to 400 hold five times the cells; back at 80 the heap is where it was. }
procedure TTyTerminalReflowTests.TestNarrowerAgainGivesTheMemoryBack;
var
  core: TTyTerminalCore;
  data: RawByteString;
  i: Integer;
  h0, h1, h2: Int64;
begin
  data := '';
  for i := 1 to 10040 do
    data := data + 'line ' + IntToStr(i) + #13#10;
  core := TTyTerminalCore.Create(80, 40);
  try
    core.Scrollback := 10000;
    core.WriteSync(data);
    data := '';
    h0 := GetFPCHeapStatus.CurrHeapUsed;
    core.Resize(400, 40);
    h1 := GetFPCHeapStatus.CurrHeapUsed;
    core.Resize(80, 40);
    h2 := GetFPCHeapStatus.CurrHeapUsed;
    WriteLn(Format('  (10 040 lines: %.1f MB at 80, %.1f MB at 400, %.1f MB back at 80)',
      [h0 / 1048576, h1 / 1048576, h2 / 1048576]));
    AssertTrue(Format('wider took more (%d -> %d)', [h0, h1]), h1 - h0 > 20 * 1048576);
    AssertTrue(Format('narrower gave it back (%d -> %d, started at %d)', [h1, h2, h0]), h2 - h0 < 2 * 1048576);
  finally
    core.Free;
  end;
end;

{ CopyCellsFrom moves a run of plain cells in one block; the answer must be the
  cell-by-cell one: forward and backward, within one line both ways, and with combined
  text or extended attributes in the run (those go cell by cell). }
procedure TTyTerminalReflowTests.TestTheBlockCopyMatchesTheCellCopy;
var
  src, a, short: TTyTerminalLine;
  attr: TTyTerminalAttrData;
  k: Integer;
begin
  src := TTyTerminalLine.CreateDefault(20);
  a := TTyTerminalLine.CreateDefault(20);
  short := TTyTerminalLine.CreateDefault(5);
  try
    attr := TyTermDefaultAttr;
    for k := 0 to 19 do
    begin
      attr.Fg := Cardinal(k);
      src.SetCellFromCodepoint(k, Cardinal(Ord('a') + k), 1, attr);
    end;
    { plain: one block, the attributes along }
    a.CopyCellsFrom(src, 3, 5, 10, False);
    AssertEquals('the cells', StringOfChar(' ', 5) + 'defghijklm' + StringOfChar(' ', 5), a.TranslateToString(False));
    AssertEquals('their attributes', src.GetFg(3), a.GetFg(5));
    AssertEquals('to the last', src.GetFg(12), a.GetFg(14));
    AssertEquals('none past it', 0, a.GetFg(15));
    { within one line: to the right (the backward order) and to the left (forward) }
    a.CopyFrom(src);
    a.CopyCellsFrom(a, 0, 4, 12, True);
    AssertEquals('within a line, to the right', 'abcdabcdefghijklqrst', a.TranslateToString(False));
    a.CopyFrom(src);
    a.CopyCellsFrom(a, 6, 2, 10, False);
    AssertEquals('within a line, to the left', 'abghijklmnopmnopqrst', a.TranslateToString(False));
    { a source shorter than the run: the cells past its end come out empty (0) }
    for k := 0 to 4 do
      short.SetCellFromCodepoint(k, Cardinal(Ord('v') + k), 1, attr);
    a.CopyFrom(src);
    a.CopyCellsFrom(short, 0, 0, 8, False);
    AssertEquals('the short line''s cells', 'vwxyz', Copy(a.TranslateToString(False), 1, 5));
    for k := 5 to 7 do
      AssertEquals(Format('cell %d past its end', [k]), 0, a.GetContent(k));
    { combined text in the run: cell by cell, the combined text moved along }
    src.AddCodepointToCell(4, $301, 0);
    a.Fill(TyTermNullCell(TyTermDefaultAttr));
    a.CopyCellsFrom(src, 2, 0, 5, False);
    AssertEquals('combined text moved', 'cde' + #$CC#$81 + 'fg', a.TranslateToString(True));
  finally
    src.Release;
    a.Release;
    short.Release;
  end;
end;

initialization
  RegisterTest(TTyTerminalReflowOracleTests);
  RegisterTest(TTyTerminalReflowTests);
end.
