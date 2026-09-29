unit test.terminal.core;
{$mode objfpc}{$H+}
{ TTyTerminalCore -- held to xterm.js 6.0.0 headless on every fixture class, plus
  the behaviour that is ours alone.

  The fixtures come from tools/terminal-oracle: core-cases.js (hand-written
  vttest-style cases, oversized input, colour / colour-scheme / focus replies, mouse
  restriction and encoding), escape-files.js (xterm.js's own escape sequence files),
  fuzz.js (seeded random bytes) and recordings.js (real programs recorded in WSL).
  Each case runs on a new core and is compared field by field -- both buffers cell
  by cell with combined text and extended attributes, cursor, margins, tab stops,
  saved cursor, markers, modes, charsets, titles, replies, events, links, parser
  state -- then again on the same core after Reset, then once per cut-up variant.
  Every test asserts how many comparisons it made.

  TTyTerminalCoreTests are direct checks of what upstream has no oracle for: colour
  parsing tables, the host OSC hook, mode-change and icon events, REP's fast-forward
  and its stop, the loop clamps at 2^31, window reports, theme changes, colour
  replies without a theme, read-only, the no-LCL rule, lines / markers / links freed
  with the core, the XTVERSION string, the resize, scrollback-cleared and
  synchronized-output entries, TriggerMouseEvent, and the bounds on scrollback,
  links, link numbers and scroll counts.

  TTyTerminalReentryTests call the core from its own events and make handlers and
  callbacks raise. }

interface

uses
  Classes, SysUtils, Types, fpcunit, testregistry, fpjson,
  tyControls.Unicode.Width, tyControls.Terminal.Parser, tyControls.Terminal.Buffer,
  tyControls.Terminal.Core, test.terminal.oracle;

type
  TTyTerminalCoreOracleTests = class(TTestCase)
  private
    procedure RunKind(const AKind: string; AMinCases: Integer; ABounded: Boolean = False);
  published
    procedure TestFixturesComeFromThePinnedUpstream;
    procedure TestHandCases;
    procedure TestLongInputsStayBounded;
    procedure TestSynthesizedReplies;
    procedure TestMouseEncoding;
    procedure TestEscapeFiles;
    procedure TestFuzz;
    procedure TestRecordings;
  end;

  TTyTerminalCoreTests = class(TTestCase)
  published
    procedure TestParseXColor;
    procedure TestToRgbString;
    procedure TestUnhandledOscGoesToTheHost;
    procedure TestModesChangeFiresOncePerSequence;
    procedure TestIconNameEvent;
    procedure TestRepHugeCountEqualsPlainText;
    procedure TestRepPilingOntoOneCellStops;
    procedure TestHugeLoopCountsReturnAtOnce;
    procedure TestWindowReportsAskTheHost;
    procedure TestThemeChangeDropsOverrides;
    procedure TestColorQueriesNeedABaseColor;
    procedure TestReadOnlySendsNothing;
    procedure TestCoreUnitsDoNotUseTheLcl;
    procedure TestNoLineOutlivesTheCore;
    procedure TestXtVersionConstant;
    procedure TestGridResizeEvent;
    procedure TestScrollbackClearedEvent;
    procedure TestEndSynchronizedOutput;
    procedure TestTriggerMouseEvent;
    procedure TestScrollbackIsCapped;
    procedure TestLinkTableIsBounded;
    procedure TestLinkNumbersPastHighInteger;
    procedure TestScrollOverflowSaturates;
    procedure TestUserInputIsAnnouncedBeforeData;
  end;

  { Calls from events while the core is busy (unit header of the core): each is
    carried out after the chunk, and the result equals making the call afterwards. }
  TTyTerminalReentryTests = class(TTestCase)
  published
    procedure TestResizeFromOnScroll;
    procedure TestWriteSyncFromOnTitleChange;
    procedure TestResetFromOnBell;
    procedure TestProcessPendingFromOnData;
    procedure TestResizeFromOnResize;
    procedure TestHandlerExceptionInWriteSync;
    procedure TestCallbackExceptionInASlice;
    procedure TestExceptionInAFlushKeepsTheRest;
  end;

  { The write queue has no upstream oracle (headless cannot observe slices): these
    are WriteBuffer.ts's rules read one by one, under a scripted clock. }
  TTyTerminalWriteQueueTests = class(TTestCase)
  published
    procedure TestWriteQueuesAndAsksOnce;
    procedure TestProcessDrainsAndReports;
    procedure TestAnOutstandingRequestIsNotRepeated;
    procedure TestSliceStopsBetweenChunksAtTheBudget;
    procedure TestOneBigChunkIsNotSplit;
    procedure TestCallbacksRunInOrder;
    procedure TestCallbackMayWriteAgain;
    procedure TestFirstWriteAfterInputParsesAtOnce;
    procedure TestFiftyMegabytesRaises;
    procedure TestWriteSyncParsesQueuedFirst;
    procedure TestResizeFlushesFirst;
    procedure TestResizeFlushDoesNotReparse;
    procedure TestSlicedEqualsWhole;
    procedure TestOtherThreadsAreRefused;
    procedure TestDestroyDropsPending;
    procedure TestDefaultClockMoves;
    procedure TestEmptyWritesAndTheChunkBound;
    procedure TestAParsedChunkIsReleased;
  end;

implementation

uses
  StrUtils, tyControls.Types;

const
  CoreKinds: array[0..6] of string = ('core-hand', 'core-long', 'core-synth', 'core-mouse',
    'core-escape', 'core-fuzz', 'core-recording');

{ ---- TTyTerminalCoreOracleTests ------------------------------------------------------ }

procedure TTyTerminalCoreOracleTests.TestFixturesComeFromThePinnedUpstream;
var
  m: TTyTermMisses;
  fx: TTyTermFixtures;
  i, k: Integer;
  commit: string;
begin
  m := TTyTermMisses.Create;
  commit := '';
  try
    for i := 0 to High(CoreKinds) do
    begin
      fx := TyTermLoadFixtures(CoreKinds[i], m);
      try
        for k := 0 to High(fx) do
        begin
          TyTermCheckUpstream(fx[k], CoreKinds[i], m);
          if commit = '' then
            commit := fx[k].Objects['upstream'].Strings['commit']
          else if fx[k].Objects['upstream'].Strings['commit'] <> commit then
            m.Add(CoreKinds[i], 'upstream.commit', commit, fx[k].Objects['upstream'].Strings['commit']);
          m.AddCompared;
          if fx[k].Find('palette') = nil then
            m.Add(CoreKinds[i], 'palette', '259 entries', 'none')
          else if fx[k].Arrays['palette'].Count <> 259 then
            m.Add(CoreKinds[i], 'palette', '259 entries', IntToStr(fx[k].Arrays['palette'].Count));
        end;
      finally
        TyTermFreeFixtures(fx);
      end;
    end;
    AssertEquals(m.Text, 0, m.Count);
    AssertTrue('checked', m.Compared >= 14);
  finally
    m.Free;
  end;
end;

procedure TTyTerminalCoreOracleTests.RunKind(const AKind: string; AMinCases: Integer; ABounded: Boolean);
var
  m: TTyTermMisses;
  fx: TTyTermFixtures;
  k, n: Integer;
  cases: TJSONArray;
  c: TJSONObject;
  total, heap, allowed: Int64;
  h: TTyTermHarness;
  t0: QWord;
begin
  m := TTyTermMisses.Create;
  n := 0;
  total := 0;
  t0 := GetTickCount64;
  try
    fx := TyTermLoadFixtures(AKind, m);
    try
      for k := 0 to High(fx) do
      begin
        cases := fx[k].Arrays['cases'];
        for n := 0 to cases.Count - 1 do
        begin
          c := cases.Objects[n];
          Inc(total, TyTermRunCase(c, fx[k].Arrays['palette'], m));
          if ABounded then
          begin
            { after the case the OSC builder is empty and the heap holds about the
              screen, not the megabytes that went through it }
            h := TTyTermHarness.Create(c, fx[k].Arrays['palette']);
            try
              heap := GetFPCHeapStatus.CurrHeapUsed;
              h.Run(c.Arrays['steps']);
              m.AddCompared(2);
              if h.Core.Parser.OscPayloadLength <> 0 then
                m.Add(c.Strings['id'], 'OscPayloadLength after the case', '0', IntToStr(h.Core.Parser.OscPayloadLength));
              { what the terminal keeps on purpose: the screens, and a title that fit
                under the limit (held by the core and by the harness's title list) }
              allowed := (Int64(h.Core.Buffers.Normal.Lines.Length) + h.Core.Buffers.Alt.Lines.Length)
                * h.Core.Cols * 64 + 1024 * 1024 + Length(h.Core.Title) + Length(h.Core.IconName)
                + Length(h.Titles.Text);
              if Int64(GetFPCHeapStatus.CurrHeapUsed) - heap > allowed then
                m.Add(c.Strings['id'], 'heap growth', '<= ' + IntToStr(allowed),
                  IntToStr(Int64(GetFPCHeapStatus.CurrHeapUsed) - heap));
            finally
              h.Free;
            end;
          end;
        end;
      end;
      n := 0;
      for k := 0 to High(fx) do
        Inc(n, fx[k].Arrays['cases'].Count);
    finally
      TyTermFreeFixtures(fx);
    end;
    WriteLn(Format('%s: %d cases, %d comparisons, %d ms', [AKind, n, m.Compared, GetTickCount64 - t0]));
    AssertEquals(m.Text, 0, m.Count);
    AssertTrue(AKind + ' cases read', n >= AMinCases);
    AssertTrue(AKind + ' comparisons', total >= Int64(n) * 40);
  finally
    m.Free;
  end;
end;

procedure TTyTerminalCoreOracleTests.TestHandCases;
begin
  RunKind('core-hand', 200);
end;

procedure TTyTerminalCoreOracleTests.TestLongInputsStayBounded;
begin
  RunKind('core-long', 10, True);
end;

procedure TTyTerminalCoreOracleTests.TestSynthesizedReplies;
begin
  RunKind('core-synth', 15);
end;

procedure TTyTerminalCoreOracleTests.TestEscapeFiles;
begin
  RunKind('core-escape', 79);
end;

procedure TTyTerminalCoreOracleTests.TestFuzz;
begin
  RunKind('core-fuzz', 300);
end;

procedure TTyTerminalCoreOracleTests.TestRecordings;
begin
  RunKind('core-recording', 8);
end;

type
  TMouseCore = record
    Key: string;
    Core: TTyTerminalCore;
  end;

function ButtonOf(const S: string): TTyTerminalMouseButton;
begin
  if S = 'LEFT' then Result := tmbLeft
  else if S = 'MIDDLE' then Result := tmbMiddle
  else if S = 'RIGHT' then Result := tmbRight
  else if S = 'NONE' then Result := tmbNone
  else Result := tmbWheel;
end;

function ActionOf(const S: string): TTyTerminalMouseAction;
begin
  if S = 'UP' then Result := tmaUp
  else if S = 'DOWN' then Result := tmaDown
  else if S = 'LEFT' then Result := tmaLeft
  else if S = 'RIGHT' then Result := tmaRight
  else Result := tmaMove;
end;

{ the protocol and the encoding set the way a program sets them: DECSET }
function MouseSetup(const AProtocol, AEncoding: string): RawByteString;
begin
  Result := '';
  if AProtocol = 'X10' then Result := #27'[?9h'
  else if AProtocol = 'VT200' then Result := #27'[?1000h'
  else if AProtocol = 'DRAG' then Result := #27'[?1002h'
  else if AProtocol = 'ANY' then Result := #27'[?1003h';
  if AEncoding = 'SGR' then Result := Result + #27'[?1006h'
  else if AEncoding = 'SGR_PIXELS' then Result := Result + #27'[?1016h';
end;

procedure TTyTerminalCoreOracleTests.TestMouseEncoding;
var
  m: TTyTermMisses;
  fx: TTyTermFixtures;
  cases: TFPList;
  c, ev, after: TJSONObject;
  cores: array of TMouseCore;
  core: TTyTerminalCore;
  key, id: string;
  i, k, n: Integer;
  e: TTyTerminalMouseEvent;
  ok: Boolean;
  enc, want: RawByteString;
begin
  m := TTyTermMisses.Create;
  cores := nil;
  n := 0;
  try
    fx := TyTermLoadFixtures('core-mouse', m);
    cases := TyTermAllCases(fx);
    try
      for i := 0 to cases.Count - 1 do
      begin
        c := TJSONObject(cases[i]);
        id := c.Strings['id'];
        key := c.Strings['protocol'] + '/' + c.Strings['encoding'];
        core := nil;
        for k := 0 to High(cores) do
          if cores[k].Key = key then
            core := cores[k].Core;
        if core = nil then
        begin
          core := TTyTerminalCore.Create(80, 24);
          core.WriteSync(MouseSetup(c.Strings['protocol'], c.Strings['encoding']));
          SetLength(cores, Length(cores) + 1);
          cores[High(cores)].Key := key;
          cores[High(cores)].Core := core;
        end;
        ev := c.Objects['event'];
        e.Col := ev.Integers['col'];
        e.Row := ev.Integers['row'];
        e.X := ev.Integers['x'];
        e.Y := ev.Integers['y'];
        e.Button := ButtonOf(ev.Strings['button']);
        e.Action := ActionOf(ev.Strings['action']);
        e.Ctrl := ev.Booleans['ctrl'];
        e.Alt := ev.Booleans['alt'];
        e.Shift := ev.Booleans['shift'];
        ok := core.RestrictMouseEvent(e);
        after := c.Objects['eventAfter'];
        m.AddCompared(5);
        Inc(n);
        if ok <> c.Booleans['restrict'] then
          m.Add(id, 'restrict', BoolToStr(c.Booleans['restrict'], True), BoolToStr(ok, True));
        if e.Ctrl <> after.Booleans['ctrl'] then
          m.Add(id, 'ctrl after restrict', BoolToStr(after.Booleans['ctrl'], True), BoolToStr(e.Ctrl, True));
        if e.Alt <> after.Booleans['alt'] then
          m.Add(id, 'alt after restrict', BoolToStr(after.Booleans['alt'], True), BoolToStr(e.Alt, True));
        if e.Shift <> after.Booleans['shift'] then
          m.Add(id, 'shift after restrict', BoolToStr(after.Booleans['shift'], True), BoolToStr(e.Shift, True));
        if ok then
          enc := core.EncodeMouseEvent(e)
        else
          enc := '';
        if c.Items[c.IndexOfName('encoded')].JSONType = jtNull then
        begin
          if ok then
            m.Add(id, 'encoded', 'null', enc);
        end
        else
        begin
          want := TyTermBase64Bytes(c.Strings['encoded']);
          if (not ok) or (want <> enc) then
            m.Add(id, 'encoded', want, enc);
        end;
      end;
    finally
      cases.Free;
      TyTermFreeFixtures(fx);
      for k := 0 to High(cores) do
        cores[k].Core.Free;
    end;
    AssertEquals(m.Text, 0, m.Count);
    AssertTrue('cases', n >= 6000);
    AssertEquals('five comparisons a case', Int64(n) * 5, m.Compared);
  finally
    m.Free;
  end;
end;

{ ---- TTyTerminalCoreTests ------------------------------------------------------------- }

procedure TTyTerminalCoreTests.TestParseXColor;

  procedure Ok(const ASpec: string; AR, AG, AB: Integer);
  var
    r, g, b: Integer;
  begin
    AssertTrue(ASpec + ' parses', TyTermParseXColor(ASpec, r, g, b));
    AssertEquals(ASpec + ' r', AR, r);
    AssertEquals(ASpec + ' g', AG, g);
    AssertEquals(ASpec + ' b', AB, b);
  end;

  procedure Bad(const ASpec: string);
  var
    r, g, b: Integer;
  begin
    AssertFalse(ASpec + ' must not parse', TyTermParseXColor(ASpec, r, g, b));
  end;

begin
  Ok('rgb:f/0/8', 255, 0, 136);
  Ok('rgb:ff/00/80', 255, 0, 128);
  Ok('rgb:fff/000/888', 255, 0, 136);
  Ok('rgb:ffff/0000/8888', 255, 0, 136);
  Ok('RGB:FF/00/80', 255, 0, 128);
  Ok('#f08', 240, 0, 128);
  Ok('#ff0088', 255, 0, 136);
  Ok('#fff000888', 255, 0, 136);
  Ok('#ffff00008888', 255, 0, 136);
  Bad('rgb:1/22/333');
  Bad('#12345');
  Bad('red');
  Bad('');
end;

procedure TTyTerminalCoreTests.TestToRgbString;
begin
  AssertEquals('rgb:ffff/0000/8888', TyTermToRgbString($FF0088));
  AssertEquals('rgb:0000/0000/0000', TyTermToRgbString($000000));
  AssertEquals('rgb:0a0a/0b0b/0c0c', TyTermToRgbString($0A0B0C));
end;

type
  TOscSink = class
  public
    Log: TStringList;
    HostLog: TStringList;
    ModesChanges: Integer;
    Titles, Icons: TStringList;
    Reports: array of TTyTermWindowReport;
    Data: RawByteString;
    constructor Create;
    destructor Destroy; override;
    procedure OnOsc(Sender: TObject; AIdent: Integer; const AData: string);
    function HostHandler(const AData: string): Boolean;
    procedure OnModes(Sender: TObject);
    procedure OnTitle(Sender: TObject; const AText: string);
    procedure OnIcon(Sender: TObject; const AText: string);
    procedure OnReport(Sender: TObject; AKind: TTyTermWindowReport);
    procedure OnData(Sender: TObject; const AData: RawByteString);
    procedure OnColor(Sender: TObject; AIndex: Integer; out ARgb: Cardinal);
  end;

constructor TOscSink.Create;
begin
  inherited Create;
  Log := TStringList.Create;
  HostLog := TStringList.Create;
  Titles := TStringList.Create;
  Icons := TStringList.Create;
end;

destructor TOscSink.Destroy;
begin
  Log.Free;
  HostLog.Free;
  Titles.Free;
  Icons.Free;
  inherited Destroy;
end;

procedure TOscSink.OnOsc(Sender: TObject; AIdent: Integer; const AData: string);
begin
  Log.Add(IntToStr(AIdent) + '=' + AData);
end;

function TOscSink.HostHandler(const AData: string): Boolean;
begin
  HostLog.Add(AData);
  Result := True;
end;

procedure TOscSink.OnModes(Sender: TObject);
begin
  Inc(ModesChanges);
end;

procedure TOscSink.OnTitle(Sender: TObject; const AText: string);
begin
  Titles.Add(AText);
end;

procedure TOscSink.OnIcon(Sender: TObject; const AText: string);
begin
  Icons.Add(AText);
end;

procedure TOscSink.OnReport(Sender: TObject; AKind: TTyTermWindowReport);
begin
  SetLength(Reports, Length(Reports) + 1);
  Reports[High(Reports)] := AKind;
end;

procedure TOscSink.OnData(Sender: TObject; const AData: RawByteString);
begin
  Data := Data + AData;
end;

procedure TOscSink.OnColor(Sender: TObject; AIndex: Integer; out ARgb: Cardinal);
begin
  ARgb := $010203 * Cardinal(AIndex mod 80);
end;

procedure TTyTerminalCoreTests.TestUnhandledOscGoesToTheHost;
var
  core: TTyTerminalCore;
  sink: TOscSink;
begin
  core := TTyTerminalCore.Create(20, 5);
  sink := TOscSink.Create;
  try
    core.OnOsc := @sink.OnOsc;
    core.WriteSync(#27']7;file:///tmp'#7);
    AssertEquals('OSC 7', '7=file:///tmp', Trim(sink.Log.Text));
    sink.Log.Clear;
    core.WriteSync(#27']133;A'#27'\');
    AssertEquals('OSC 133', '133=A', Trim(sink.Log.Text));
    sink.Log.Clear;
    core.WriteSync(#27']2;t'#7);
    AssertEquals('OSC 2 is the core''s', 0, sink.Log.Count);
    core.WriteSync(#27']4294967300;x'#7);
    AssertEquals('a number past Integer never reaches the host', 0, sink.Log.Count);
    core.WriteSync(#27']7;x'#$18);
    AssertEquals('a cancelled OSC never reaches the host', 0, sink.Log.Count);
    core.Parser.RegisterOscHandler(1337, TTyTerminalOscStringHandler.Create(@sink.HostHandler));
    core.WriteSync(#27']1337;x'#7);
    AssertEquals('the host''s own handler', 'x', Trim(sink.HostLog.Text));
    AssertEquals('and not OnOsc', 0, sink.Log.Count);
    { nobody listening as the OSC starts: its payload is not collected, so a listener
      that turns up halfway gets nothing }
    core.OnOsc := nil;
    core.WriteSync(#27']7;abc');
    core.OnOsc := @sink.OnOsc;
    core.WriteSync('def'#7);
    AssertEquals('an OSC begun unheard stays unheard', 0, sink.Log.Count);
    core.WriteSync(#27']7;next'#7);
    AssertEquals('the next one is heard', '7=next', Trim(sink.Log.Text));
  finally
    core.Free;
    sink.Free;
  end;
end;

procedure TTyTerminalCoreTests.TestModesChangeFiresOncePerSequence;
var
  core: TTyTerminalCore;
  sink: TOscSink;
begin
  core := TTyTerminalCore.Create(20, 5);
  sink := TOscSink.Create;
  try
    core.OnModesChange := @sink.OnModes;
    core.WriteSync(#27'[?1;25;2004h');
    AssertEquals('three modes, one sequence', 1, sink.ModesChanges);
    core.WriteSync(#27'[?1h');
    AssertEquals('already on', 1, sink.ModesChanges);
    core.WriteSync(#27'[1m');
    AssertEquals('SGR is no mode', 1, sink.ModesChanges);
    core.WriteSync(#27'[?1000h');
    AssertEquals('the mouse protocol', 2, sink.ModesChanges);
  finally
    core.Free;
    sink.Free;
  end;
end;

procedure TTyTerminalCoreTests.TestIconNameEvent;
var
  core: TTyTerminalCore;
  sink: TOscSink;
begin
  core := TTyTerminalCore.Create(20, 5);
  sink := TOscSink.Create;
  try
    core.OnTitleChange := @sink.OnTitle;
    core.OnIconNameChange := @sink.OnIcon;
    core.WriteSync(#27']1;icon'#7);
    AssertEquals('icon', Trim(sink.Icons.Text));
    AssertEquals('no title', 0, sink.Titles.Count);
    core.WriteSync(#27']0;both'#7);
    AssertEquals('icon, both', 'icon,both', sink.Icons.CommaText);
    AssertEquals('title both', 'both', Trim(sink.Titles.Text));
    AssertEquals('both', core.IconName);
  finally
    core.Free;
    sink.Free;
  end;
end;

function CountOf(const ANeedle, AHay: RawByteString): Integer;
var
  p: Integer;
begin
  Result := 0;
  p := Pos(ANeedle, AHay);
  while p > 0 do
  begin
    Inc(Result);
    p := PosEx(ANeedle, AHay, p + Length(ANeedle));
  end;
end;

{ '' when both cores hold the same screens (the active buffer: every line's cells,
  combined text and wrap flag, the cursor, ybase, ydisp, the line count); otherwise
  the first difference. ACompared counts the cells looked at. }
function ScreenDiff(A, B: TTyTerminalCore; var ACompared: Int64): string;
var
  r, c: Integer;
  la, lb: TTyTerminalLine;
  sa, sb: string;
begin
  Result := '';
  if (A.Cols <> B.Cols) or (A.Rows <> B.Rows) then
    Exit(Format('size %dx%d vs %dx%d', [A.Cols, A.Rows, B.Cols, B.Rows]));
  if A.Buffers.IsAlt <> B.Buffers.IsAlt then
    Exit('active buffer');
  if (A.Buffer.X <> B.Buffer.X) or (A.Buffer.Y <> B.Buffer.Y) then
    Exit(Format('cursor (%d,%d) vs (%d,%d)', [A.Buffer.X, A.Buffer.Y, B.Buffer.X, B.Buffer.Y]));
  if (A.Buffer.YBase <> B.Buffer.YBase) or (A.Buffer.YDisp <> B.Buffer.YDisp) then
    Exit(Format('ybase/ydisp %d/%d vs %d/%d', [A.Buffer.YBase, A.Buffer.YDisp, B.Buffer.YBase, B.Buffer.YDisp]));
  if A.Buffer.Lines.Length <> B.Buffer.Lines.Length then
    Exit(Format('lines %d vs %d', [A.Buffer.Lines.Length, B.Buffer.Lines.Length]));
  for r := 0 to A.Buffer.Lines.Length - 1 do
  begin
    la := A.Buffer.Lines.Get(r);
    lb := B.Buffer.Lines.Get(r);
    if (la = nil) or (lb = nil) then
    begin
      if la <> lb then
        Exit(Format('row %d: a missing line', [r]));
      Continue;
    end;
    if la.IsWrapped <> lb.IsWrapped then
      Exit(Format('row %d wrap', [r]));
    for c := 0 to A.Cols - 1 do
    begin
      Inc(ACompared);
      if (la.GetContent(c) <> lb.GetContent(c)) or (la.GetFg(c) <> lb.GetFg(c)) or (la.GetBg(c) <> lb.GetBg(c)) then
        Exit(Format('row %d col %d: "%s" vs "%s"', [r, c, la.TranslateToString(True), lb.TranslateToString(True)]));
      la.CombinedEntry(c, sa);
      lb.CombinedEntry(c, sb);
      if sa <> sb then
        Exit(Format('row %d col %d combined text', [r, c]));
    end;
  end;
end;

{ REP's fast-forward (unit header of the core): a count of 2^31 - 1 finishes at once
  and equals the same characters written out -- as many as it takes to turn the
  ring over many times, and congruent to the REP's count modulo the period of the
  line (20 'a's; 9 wide characters in 19 columns). The written-out text never goes
  near REP's code. }
procedure TTyTerminalCoreTests.TestRepHugeCountEqualsPlainText;

  procedure Check(const AText: RawByteString; ACols, APerLine: Integer; const AWhat: string);
  var
    rep, plain: TTyTerminalCore;
    total, n, compared: Int64;
    t0: QWord;
    s: RawByteString;
    diff: string;
  begin
    rep := TTyTerminalCore.Create(ACols, 4);
    plain := TTyTerminalCore.Create(ACols, 4);
    try
      rep.Scrollback := 10;
      plain.Scrollback := 10;
      t0 := GetTickCount64;
      rep.WriteSync(AText + #27'[2147483647b');
      AssertTrue(AWhat + ': 2^31 - 1 repetitions return at once (30 s is generous)', GetTickCount64 - t0 < 30000);
      total := Int64(1) + 2147483647;      { the character itself, then the repetitions }
      n := Int64(APerLine) * 100 + total mod APerLine;
      s := '';
      while n > 0 do
      begin
        s := s + AText;
        Dec(n);
      end;
      plain.WriteSync(s);
      compared := 0;
      diff := ScreenDiff(plain, rep, compared);
      AssertEquals(AWhat + ': ' + diff, '', diff);
      AssertEquals(AWhat + ': every cell compared', Int64(plain.Buffer.Lines.Length) * ACols, compared);
    finally
      rep.Free;
      plain.Free;
    end;
  end;

begin
  Check('a', 20, 20, 'one cell');
  Check(#$E4#$B8#$AD, 19, 9, 'wide in an odd width');
end;

{ The one case the fast-forward cannot shorten: every repetition piles its code
  points onto the same cell (a lone combining mark repeated under '15-graphemes').
  It stops after TyTermRepeatLimit code points on the line -- here 1 + (limit + 1)
  marks in cell 0 -- in bounded time, with the cursor where it was. }
procedure TTyTerminalCoreTests.TestRepPilingOntoOneCellStops;
var
  core: TTyTerminalCore;
  t0: QWord;
  text: string;
begin
  core := TTyTerminalCore.Create(20, 4);
  try
    core.UnicodeVersion := tuv15Graphemes;
    core.WriteSync(#$CC#$81);              { U+0301 at column 0: a cell of its own }
    AssertEquals('the mark took one cell', 1, core.Buffer.X);
    t0 := GetTickCount64;
    core.WriteSync(#27'[2147483647b');
    AssertTrue('bounded (30 s is generous)', GetTickCount64 - t0 < 30000);
    text := core.Buffer.Lines.Get(0).GetChars(0);
    AssertEquals('marks in cell 0', TyTermRepeatLimit + 2, Length(TyTermUtf8Codepoints(text)));
    AssertEquals('the cursor did not move', 1, core.Buffer.X);
    AssertEquals('nor the line', 0, core.Buffer.Y);
  finally
    core.Free;
  end;
end;

{ IL, DL, SU, SD, CHT and CBT with a count of 2^31 - 1 return at once and leave what
  a count of 1000 leaves: every pass past the clamp was a no-op. Without a clamp the
  loop runs 2^31 times -- the test then does not finish, which is the failure. }
procedure TTyTerminalCoreTests.TestHugeLoopCountsReturnAtOnce;
const
  Fill = 'line 0 aaaa'#13#10'line 1 bbbb'#13#10'line 2 cccc'#13#10'line 3 dddd'#13#10'line 4 eeee'#13#10'line 5 ffff';
  Finals: array[0..6] of Char = ('L', 'M', 'S', 'T', '^', 'I', 'Z');
  Setups: array[0..6] of string = (#27'[2;5r'#27'[3;1H', #27'[2;5r'#27'[3;1H', #27'[2;5r', #27'[2;5r',
    #27'[2;5r', #27'[1;1H', #27'[1;20H');
var
  i: Integer;
  huge, ref: TTyTerminalCore;
  t0: QWord;
  compared: Int64;
  diff: string;
begin
  for i := 0 to High(Finals) do
  begin
    huge := TTyTerminalCore.Create(20, 6);
    ref := TTyTerminalCore.Create(20, 6);
    try
      t0 := GetTickCount64;
      huge.WriteSync(Fill + Setups[i] + #27'[2147483647' + Finals[i] + 'x');
      AssertTrue(Finals[i] + ': returns at once (30 s is generous)', GetTickCount64 - t0 < 30000);
      ref.WriteSync(Fill + Setups[i] + #27'[1000' + Finals[i] + 'x');
      compared := 0;
      diff := ScreenDiff(ref, huge, compared);
      AssertEquals(Finals[i] + ': ' + diff, '', diff);
      AssertTrue(Finals[i] + ': compared', compared >= 6 * 20);
    finally
      huge.Free;
      ref.Free;
    end;
  end;
end;

procedure TTyTerminalCoreTests.TestWindowReportsAskTheHost;
var
  core: TTyTerminalCore;
  sink: TOscSink;
begin
  core := TTyTerminalCore.Create(20, 5);
  sink := TOscSink.Create;
  try
    core.OnWindowOptionsReport := @sink.OnReport;
    core.WindowOptions := [twoGetWinSizePixels, twoGetCellSizePixels];
    core.WriteSync(#27'[14t');
    AssertEquals(1, Length(sink.Reports));
    AssertTrue('window pixels', sink.Reports[0] = twrWinSizePixels);
    core.WriteSync(#27'[14;2t');
    AssertEquals('14;2 is not asked', 1, Length(sink.Reports));
    core.WriteSync(#27'[16t');
    AssertEquals(2, Length(sink.Reports));
    AssertTrue('cell pixels', sink.Reports[1] = twrCellSizePixels);
    core.WindowOptions := [];
    core.WriteSync(#27'[14t'#27'[16t');
    AssertEquals('off: nothing', 2, Length(sink.Reports));
  finally
    core.Free;
    sink.Free;
  end;
end;

procedure TTyTerminalCoreTests.TestThemeChangeDropsOverrides;
var
  core: TTyTerminalCore;
  sink: TOscSink;
  base: Cardinal;
begin
  core := TTyTerminalCore.Create(20, 5);
  sink := TOscSink.Create;
  try
    core.OnQueryBaseColor := @sink.OnColor;
    sink.OnColor(nil, 1, base);
    AssertFalse(core.HasColorOverride(1));
    core.WriteSync(#27']4;1;#123456'#7);
    AssertTrue('set', core.HasColorOverride(1));
    AssertEquals('override answers', $123456, core.ResolveColor(1));
    core.NotifyColorSchemeChanged;
    AssertFalse('a new theme drops it', core.HasColorOverride(1));
    AssertEquals('the base colour again', base, core.ResolveColor(1));
  finally
    core.Free;
    sink.Free;
  end;
end;

{ No OnQueryBaseColor, no theme: the core answers no colour query, no colour-scheme
  query and sends no 2031 report, as headless xterm.js. With one, it answers. }
procedure TTyTerminalCoreTests.TestColorQueriesNeedABaseColor;
const
  Queries = #27']4;1;?'#7#27']10;?'#7#27']11;?'#7#27']12;?'#7#27'[?996n'
    + #27'[?2031h'#27']4;2;#102030'#7#27']104;2'#7;
var
  core: TTyTerminalCore;
  sink: TOscSink;
begin
  core := TTyTerminalCore.Create(20, 5);
  sink := TOscSink.Create;
  try
    core.OnData := @sink.OnData;
    core.WriteSync(Queries);
    AssertEquals('nothing without a base colour', '', sink.Data);
    core.WriteSync(#27']4;3;#102030'#7);
    AssertTrue('a set still takes, it just reports nothing', core.HasColorOverride(3));
    AssertEquals('still nothing', '', sink.Data);
    core.WriteSync(#27'[?1004h');
    AssertEquals('focus is not a colour: still reported', #27'[I', sink.Data);
    sink.Data := '';
    core.WriteSync(#27'[?1004l'#27'[?2031l');
    core.OnQueryBaseColor := @sink.OnColor;
    core.WriteSync(Queries);
    AssertEquals('with one: four colour answers', 4, CountOf(#27']', sink.Data));
    AssertEquals('the 996 answer and a 2031 report per change', 3, CountOf(#27'[?997;', sink.Data));
    AssertTrue('an OSC 11 answer', Pos(#27']11;rgb:', sink.Data) > 0);
  finally
    core.Free;
    sink.Free;
  end;
end;

procedure TTyTerminalCoreTests.TestReadOnlySendsNothing;
var
  core: TTyTerminalCore;
  sink: TOscSink;
begin
  core := TTyTerminalCore.Create(20, 5);
  sink := TOscSink.Create;
  try
    core.OnData := @sink.OnData;
    core.ReadOnly := True;
    core.WriteSync(#27'[c'#27'[5n'#27'[?1$p'#27'[?1004h'#27']4;1;?'#7);
    core.ReportFocus(False);
    core.Input('typed', True);
    AssertEquals('nothing at all', '', sink.Data);
    core.ReadOnly := False;
    core.WriteSync(#27'[5n');
    AssertEquals('and something once it is off', #27'[0n', sink.Data);
  finally
    core.Free;
    sink.Free;
  end;
end;

{ spec 3.1: the three units run without the LCL }
procedure TTyTerminalCoreTests.TestCoreUnitsDoNotUseTheLcl;
const
  Units: array[0..2] of string = ('tyControls.Terminal.Parser.pas', 'tyControls.Terminal.Buffer.pas',
    'tyControls.Terminal.Core.pas');
  Banned: array[0..12] of string = ('forms', 'controls', 'graphics', 'lcltype', 'lclintf', 'lresources',
    'dialogs', 'extctrls', 'stdctrls', 'menus', 'interfacebase', 'lmessages', 'lclproc');
var
  sl: TStringList;
  i, k, p, e: Integer;
  text, clause, name: string;
  names: TStringList;
begin
  names := TStringList.Create;
  sl := TStringList.Create;
  try
    for i := 0 to High(Units) do
    begin
      sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'source' + PathDelim + Units[i]);
      text := LowerCase(sl.Text);
      p := 1;
      names.Clear;
      repeat
        p := Pos('uses', Copy(text, p, MaxInt)) + p - 1;
        if p < 1 then Break;
        { a whole word "uses" starting a clause }
        if ((p = 1) or not (text[p - 1] in ['a'..'z', '0'..'9', '_', '.'])) and (p + 4 <= Length(text))
          and (text[p + 4] in [' ', #9, #10, #13]) then
        begin
          e := p + 4;
          while (e <= Length(text)) and (text[e] <> ';') do
            Inc(e);
          clause := Copy(text, p + 4, e - p - 4);
          clause := StringReplace(clause, #13, ' ', [rfReplaceAll]);
          clause := StringReplace(clause, #10, ' ', [rfReplaceAll]);
          names.CommaText := StringReplace(clause, ' ', '', [rfReplaceAll]);
          for k := 0 to names.Count - 1 do
          begin
            name := Trim(names[k]);
            AssertFalse(Units[i] + ' uses ' + name, (name <> '') and
              (AnsiIndexText(name, Banned) >= 0));
          end;
          p := e;
        end
        else
          Inc(p, 4);
      until p >= Length(text);
    end;
  finally
    sl.Free;
    names.Free;
  end;
end;

procedure TTyTerminalCoreTests.TestNoLineOutlivesTheCore;
var
  base, markers, links: Integer;
  core: TTyTerminalCore;
  fx: TTyTermFixtures;
  m: TTyTermMisses;
  cases: TFPList;
  i: Integer;
  input: RawByteString;
begin
  m := TTyTermMisses.Create;
  input := '';
  try
    fx := TyTermLoadFixtures('core-escape', m);
    cases := TyTermAllCases(fx);
    try
      for i := 0 to cases.Count - 1 do
        if TJSONObject(cases[i]).Strings['id'] = 't0504-vim.in' then
          input := TyTermBase64Bytes(TJSONObject(cases[i]).Arrays['steps'].Objects[0].Strings['write']);
    finally
      cases.Free;
      TyTermFreeFixtures(fx);
    end;
  finally
    m.Free;
  end;
  AssertTrue('the vim recording was found', Length(input) > 1000);
  base := TTyTerminalLine.LiveCount;
  markers := TTyTerminalMarker.LiveCount;
  links := TTyTermLinkEntry.LiveCount;
  core := TTyTerminalCore.Create(80, 25);
  try
    core.Scrollback := 50;
    core.ConvertEol := True;
    core.WriteSync(input);
    core.WriteSync(#27']8;;u'#7'link'#27']8;;'#7);
    core.Resize(60, 30);
    core.Resize(90, 10);
    core.ClearScrollback;
    core.WriteSync(#27'[?1049hin alt'#27'[?1049l');
    core.WriteSync(input);
    AssertTrue('lines exist meanwhile', TTyTerminalLine.LiveCount > base);
    core.WriteSync(#27']8;id=k;v'#7'link'#27']8;;'#7);
    AssertTrue('markers exist meanwhile', TTyTerminalMarker.LiveCount > markers);
    AssertTrue('link entries exist meanwhile', TTyTermLinkEntry.LiveCount > links);
  finally
    core.Free;
  end;
  AssertEquals('every line freed with the core', base, TTyTerminalLine.LiveCount);
  AssertEquals('every marker freed with the core', markers, TTyTerminalMarker.LiveCount);
  AssertEquals('every link entry freed with the core', links, TTyTermLinkEntry.LiveCount);
end;

procedure TTyTerminalCoreTests.TestXtVersionConstant;
var
  core: TTyTerminalCore;
  sink: TOscSink;
begin
  AssertEquals('TyTermLibraryVersion follows TyVersion', TyVersion, TyTermLibraryVersion);
  core := TTyTerminalCore.Create(20, 5);
  sink := TOscSink.Create;
  try
    core.OnData := @sink.OnData;
    core.WriteSync(#27'[>q');
    AssertEquals(#27'P>|TyControls(' + TyVersion + ')'#27'\', sink.Data);
  finally
    core.Free;
    sink.Free;
  end;
end;

type
  TEventSink = class
  public
    Resizes: TStringList;
    Cleared, ModeChanges, ScrollRequests: Integer;
    Refreshes: TStringList;
    Data: RawByteString;
    constructor Create;
    destructor Destroy; override;
    procedure OnResize(Sender: TObject; ACols, ARows: Integer);
    procedure OnCleared(Sender: TObject);
    procedure OnModes(Sender: TObject);
    procedure OnRows(Sender: TObject; AFirst, ALast: Integer);
    procedure OnData(Sender: TObject; const AData: RawByteString);
    procedure OnScrollRequest(Sender: TObject);
  end;

constructor TEventSink.Create;
begin
  inherited Create;
  Resizes := TStringList.Create;
  Refreshes := TStringList.Create;
end;

destructor TEventSink.Destroy;
begin
  Resizes.Free;
  Refreshes.Free;
  inherited Destroy;
end;

procedure TEventSink.OnResize(Sender: TObject; ACols, ARows: Integer);
begin
  Resizes.Add(Format('%dx%d', [ACols, ARows]));
end;

procedure TEventSink.OnCleared(Sender: TObject);
begin
  Inc(Cleared);
end;

procedure TEventSink.OnModes(Sender: TObject);
begin
  Inc(ModeChanges);
end;

procedure TEventSink.OnRows(Sender: TObject; AFirst, ALast: Integer);
begin
  Refreshes.Add(Format('%d-%d', [AFirst, ALast]));
end;

procedure TEventSink.OnData(Sender: TObject; const AData: RawByteString);
begin
  Data := Data + AData;
end;

procedure TEventSink.OnScrollRequest(Sender: TObject);
begin
  Inc(ScrollRequests);
end;

{ BufferService.onResize reaches the host as OnResize: Resize, and DECCOLM under
  twoSetWinLines (132 then 80 columns); DECCOLM without the option does nothing }
procedure TTyTerminalCoreTests.TestGridResizeEvent;
var
  core: TTyTerminalCore;
  sink: TEventSink;
begin
  core := TTyTerminalCore.Create(20, 5);
  sink := TEventSink.Create;
  try
    core.OnResize := @sink.OnResize;
    core.Resize(30, 7);
    AssertEquals('Resize', '30x7', sink.Resizes.CommaText);
    core.Resize(30, 7);
    AssertEquals('the same size: nothing', 1, sink.Resizes.Count);
    core.WriteSync(#27'[?3h');
    AssertEquals('DECCOLM is off by default', 1, sink.Resizes.Count);
    core.WindowOptions := [twoSetWinLines];
    core.WriteSync(#27'[?3h');
    AssertEquals('132 columns', '30x7,132x7', sink.Resizes.CommaText);
    AssertEquals(132, core.Cols);
    core.WriteSync(#27'[?3l');
    AssertEquals('80 columns', '30x7,132x7,80x7', sink.Resizes.CommaText);
    AssertEquals(80, core.Cols);
  finally
    core.Free;
    sink.Free;
  end;
end;

{ ED 3 with scrollback and ClearScrollback both tell the host; ED 3 with nothing to
  clear does not }
procedure TTyTerminalCoreTests.TestScrollbackClearedEvent;
var
  core: TTyTerminalCore;
  sink: TEventSink;
  i: Integer;
begin
  core := TTyTerminalCore.Create(20, 3);
  sink := TEventSink.Create;
  try
    core.OnScrollbackCleared := @sink.OnCleared;
    core.WriteSync(#27'[3J');
    AssertEquals('no scrollback yet: no event', 0, sink.Cleared);
    for i := 1 to 10 do
      core.WriteSync('line'#13#10);
    AssertTrue('scrollback now', core.Buffer.YBase > 0);
    core.WriteSync(#27'[3J');
    AssertEquals('ED 3', 1, sink.Cleared);
    AssertEquals('gone', 0, core.Buffer.YBase);
    for i := 1 to 10 do
      core.WriteSync('line'#13#10);
    core.ClearScrollback;
    AssertEquals('ClearScrollback', 2, sink.Cleared);
  finally
    core.Free;
    sink.Free;
  end;
end;

{ the 1-second timeout of DECSET 2026 (RenderService.ts:359-363): mode off, the whole
  screen refreshed, a mode change; nothing when the mode is not on }
procedure TTyTerminalCoreTests.TestEndSynchronizedOutput;
var
  core: TTyTerminalCore;
  sink: TEventSink;
begin
  core := TTyTerminalCore.Create(20, 5);
  sink := TEventSink.Create;
  try
    core.OnModesChange := @sink.OnModes;
    core.OnRefreshRows := @sink.OnRows;
    core.WriteSync(#27'[?2026h');
    AssertTrue('on', core.Modes.SynchronizedOutput);
    sink.ModeChanges := 0;
    sink.Refreshes.Clear;
    core.EndSynchronizedOutput;
    AssertFalse('off', core.Modes.SynchronizedOutput);
    AssertEquals('the whole screen', '0-4', sink.Refreshes.CommaText);
    AssertEquals('a mode change', 1, sink.ModeChanges);
    core.EndSynchronizedOutput;
    AssertEquals('not on: nothing', 1, sink.Refreshes.Count);
    AssertEquals('not on: no mode change', 1, sink.ModeChanges);
  finally
    core.Free;
    sink.Free;
  end;
end;

function MouseAt(ACol, ARow: Integer; AButton: TTyTerminalMouseButton; AAction: TTyTerminalMouseAction;
  AX: Integer = 0; AY: Integer = 0): TTyTerminalMouseEvent;
begin
  Result.Col := ACol;
  Result.Row := ARow;
  Result.X := AX;
  Result.Y := AY;
  Result.Button := AButton;
  Result.Action := AAction;
  Result.Shift := False;
  Result.Alt := False;
  Result.Ctrl := False;
end;

{ MouseService._triggerMouseEvent (MouseService.ts:497-545), read one rule at a time }
procedure TTyTerminalCoreTests.TestTriggerMouseEvent;
var
  core: TTyTerminalCore;
  sink: TEventSink;
  i: Integer;
begin
  core := TTyTerminalCore.Create(20, 5);
  sink := TEventSink.Create;
  try
    core.OnData := @sink.OnData;
    core.OnRequestScrollToBottom := @sink.OnScrollRequest;
    AssertFalse('no protocol: nothing', core.TriggerMouseEvent(MouseAt(0, 0, tmbLeft, tmaDown)));
    core.WriteSync(#27'[?1000h');
    AssertTrue('VT200 press', core.TriggerMouseEvent(MouseAt(0, 0, tmbLeft, tmaDown)));
    AssertEquals('0-based in, 1-based out', #27'[M'#32#33#33, sink.Data);
    sink.Data := '';
    AssertFalse('past the last column', core.TriggerMouseEvent(MouseAt(20, 0, tmbLeft, tmaDown)));
    AssertFalse('past the last row', core.TriggerMouseEvent(MouseAt(0, 5, tmbLeft, tmaDown)));
    AssertFalse('before the first', core.TriggerMouseEvent(MouseAt(-1, 0, tmbLeft, tmaDown)));
    AssertFalse('wheel + move', core.TriggerMouseEvent(MouseAt(1, 1, tmbWheel, tmaMove)));
    AssertFalse('no button + press', core.TriggerMouseEvent(MouseAt(1, 1, tmbNone, tmaDown)));
    AssertFalse('button + left', core.TriggerMouseEvent(MouseAt(1, 1, tmbLeft, tmaLeft)));
    AssertEquals('none of them sent', '', sink.Data);
    { routing: the default encoding is binary -- no jump to the bottom -- the others
      are user input (triggerDataEvent(report, true)) }
    for i := 1 to 10 do
      core.WriteSync('line'#13#10);
    core.ScrollLines(-2);
    AssertTrue('scrolled up', core.Buffer.YDisp < core.Buffer.YBase);
    core.TriggerMouseEvent(MouseAt(2, 3, tmbLeft, tmaDown));
    AssertEquals('binary report', #27'[M'#32#35#36, sink.Data);
    AssertTrue('binary: still scrolled up', core.Buffer.YDisp < core.Buffer.YBase);
    AssertEquals('binary: no scroll request', 0, sink.ScrollRequests);
    sink.Data := '';
    core.WriteSync(#27'[?1006h');
    core.TriggerMouseEvent(MouseAt(2, 3, tmbLeft, tmaDown));
    AssertEquals('SGR report', #27'[<0;3;4M', sink.Data);
    AssertEquals('SGR: user input scrolls to the bottom', core.Buffer.YBase, core.Buffer.YDisp);
    AssertEquals('SGR: a scroll request', 1, sink.ScrollRequests);
    { moves: once per cell, or per pixel under SGR-pixels }
    core.WriteSync(#27'[?1003h');
    sink.Data := '';
    AssertTrue('first move', core.TriggerMouseEvent(MouseAt(4, 1, tmbNone, tmaMove, 40, 17)));
    AssertFalse('the same cell again', core.TriggerMouseEvent(MouseAt(4, 1, tmbNone, tmaMove, 41, 18)));
    AssertTrue('another cell', core.TriggerMouseEvent(MouseAt(5, 1, tmbNone, tmaMove, 50, 18)));
    AssertEquals('two moves', #27'[<35;5;2M'#27'[<35;6;2M', sink.Data);
    core.WriteSync(#27'[?1016h');
    sink.Data := '';
    AssertTrue('pixels: first', core.TriggerMouseEvent(MouseAt(5, 1, tmbNone, tmaMove, 51, 18)));
    AssertTrue('pixels: same cell, another pixel', core.TriggerMouseEvent(MouseAt(5, 1, tmbNone, tmaMove, 52, 18)));
    AssertFalse('pixels: the same pixel', core.TriggerMouseEvent(MouseAt(5, 1, tmbNone, tmaMove, 52, 18)));
    AssertEquals('pixel reports', #27'[<35;51;18M'#27'[<35;52;18M', sink.Data);
    { read-only: passes the filters, sends nothing }
    core.ReadOnly := True;
    sink.Data := '';
    AssertTrue('read-only still passes', core.TriggerMouseEvent(MouseAt(1, 1, tmbLeft, tmaDown)));
    AssertEquals('read-only sends nothing', '', sink.Data);
  finally
    core.Free;
    sink.Free;
  end;
end;

type
  { the order OnUserInput and OnData come in }
  TOrderSink = class
  public
    Log: string;
    procedure OnUser(Sender: TObject);
    procedure OnData(Sender: TObject; const AData: RawByteString);
  end;

procedure TOrderSink.OnUser(Sender: TObject);
begin
  Log := Log + 'user,';
end;

procedure TOrderSink.OnData(Sender: TObject; const AData: RawByteString);
begin
  Log := Log + 'data,';
end;

{ CoreService.triggerDataEvent (:74-95): onUserInput before onData, only for user
  input, never while stdin is disabled }
procedure TTyTerminalCoreTests.TestUserInputIsAnnouncedBeforeData;
var
  core: TTyTerminalCore;
  sink: TOrderSink;
begin
  core := TTyTerminalCore.Create(20, 5);
  sink := TOrderSink.Create;
  try
    core.OnUserInput := @sink.OnUser;
    core.OnData := @sink.OnData;
    core.Input('a', True);
    AssertEquals('typing', 'user,data,', sink.Log);
    sink.Log := '';
    core.Input('a', False);
    AssertEquals('a reply', 'data,', sink.Log);
    sink.Log := '';
    core.ReadOnly := True;
    core.Input('a', True);
    AssertEquals('read-only: nothing', '', sink.Log);
    core.ReadOnly := False;
    core.WriteSync(#27'[?1000h'#27'[?1006h');
    sink.Log := '';
    core.TriggerMouseEvent(MouseAt(1, 1, tmbLeft, tmaDown));
    AssertEquals('an SGR report is user input', 'user,data,', sink.Log);
    core.WriteSync(#27'[?1006l');
    sink.Log := '';
    core.TriggerMouseEvent(MouseAt(2, 1, tmbLeft, tmaDown));
    AssertEquals('the default encoding is binary', 'data,', sink.Log);
  finally
    core.Free;
    sink.Free;
  end;
end;

{ the ring allocates its slots up front: Scrollback stops at TyTermMaxScrollback }
procedure TTyTerminalCoreTests.TestScrollbackIsCapped;
var
  core: TTyTerminalCore;
  raised: Boolean;
begin
  core := TTyTerminalCore.Create(20, 5);
  try
    core.Scrollback := 500000000;
    AssertEquals('the maximum', TyTermMaxScrollback, core.Scrollback);
    AssertEquals('the ring', 5 + TyTermMaxScrollback, core.Buffer.Lines.MaxLength);
    core.Scrollback := TyTermMaxScrollback - 1;
    AssertEquals('below it: as given', TyTermMaxScrollback - 1, core.Scrollback);
    raised := False;
    try
      core.Scrollback := -1;
    except
      on EArgumentException do raised := True;
    end;
    AssertTrue('negative raises (upstream''s check)', raised);
  finally
    core.Free;
  end;
end;

{ past TyTermMaxLinks links, or TyTermMaxLinkBytes of ids and URIs, the oldest go }
procedure TTyTerminalCoreTests.TestLinkTableIsBounded;
var
  core: TTyTerminalCore;
  s: RawByteString;
  i: Integer;
  d: TTyTerminalLinkData;
  ids: TInt64DynArray;
  big: string;
begin
  core := TTyTerminalCore.Create(20, 5);
  try
    s := '';
    for i := 1 to TyTermMaxLinks + 5 do
      s := s + #27']8;;u' + IntToStr(i) + #7'x'#27']8;;'#7;
    core.WriteSync(s);
    AssertEquals('at most', TyTermMaxLinks, core.Links.Count);
    AssertFalse('the oldest went', core.Links.GetLinkData(1, d));
    AssertFalse('the fifth oldest went', core.Links.GetLinkData(5, d));
    AssertTrue('the sixth stays', core.Links.GetLinkData(6, d));
    AssertEquals('u6', d.Uri);
    AssertTrue('the newest stays', core.Links.GetLinkData(TyTermMaxLinks + 5, d));
    ids := core.Links.LinkIds;
    AssertEquals('ascending from 6', 6, ids[0]);
    AssertEquals('to the newest', TyTermMaxLinks + 5, ids[High(ids)]);
    { bytes: 1 MB URIs, twenty of them }
    core.Reset;
    big := StringOfChar('q', 1024 * 1024);
    s := '';
    for i := 1 to 20 do
      s := s + #27']8;;' + big + IntToStr(i) + #7'y'#27']8;;'#7;
    core.WriteSync(s);
    AssertTrue('within the byte bound', core.Links.Bytes <= TyTermMaxLinkBytes);
    AssertTrue('the newest kept', core.Links.Count > 0);
    ids := core.Links.LinkIds;
    core.Links.GetLinkData(ids[High(ids)], d);
    AssertEquals('the newest is the last written', big + '20', d.Uri);
  finally
    core.Free;
  end;
end;

{ link numbers are Int64: past High(Integer) they keep counting up, the table stays
  in order and a cell carries the big number }
procedure TTyTerminalCoreTests.TestLinkNumbersPastHighInteger;
var
  core: TTyTerminalCore;
  ids: TInt64DynArray;
  d: TTyTerminalLinkData;
  e: TTyTerminalExtAttrs;
  i: Integer;
begin
  core := TTyTerminalCore.Create(20, 5);
  try
    core.Links.SeedNextIdForTest(Int64(High(Integer)) - 1);
    core.WriteSync(#27']8;;a'#7'1'#27']8;;'#7#27']8;;b'#7'2'#27']8;;'#7#27']8;;c'#7'3'#27']8;;'#7);
    ids := core.Links.LinkIds;
    AssertEquals('three', 3, Length(ids));
    for i := 0 to 2 do
      AssertEquals('number ' + IntToStr(i), Int64(High(Integer)) - 1 + i, ids[i]);
    AssertTrue('found past High(Integer)', core.Links.GetLinkData(Int64(High(Integer)) + 1, d));
    AssertEquals('c', d.Uri);
    AssertTrue('the cell holds it', core.Buffer.Lines.Get(0).ExtendedEntry(2, e));
    AssertEquals('the cell''s number', Int64(High(Integer)) + 1, e.UrlId);
  finally
    core.Free;
  end;
end;

{ ScrollLines / ScrollPages with extreme counts clamp to the scrollback's ends: the
  sums are Int64, nothing wraps round }
procedure TTyTerminalCoreTests.TestScrollOverflowSaturates;
var
  core: TTyTerminalCore;
  i: Integer;
begin
  core := TTyTerminalCore.Create(20, 5);
  try
    for i := 1 to 30 do
      core.WriteSync('line'#13#10);
    AssertTrue('scrollback', core.Buffer.YBase > 0);
    core.ScrollLines(-3);
    core.ScrollLines(High(Integer));
    AssertEquals('to the bottom', core.Buffer.YBase, core.Buffer.YDisp);
    core.ScrollLines(Low(Integer));
    AssertEquals('to the top', 0, core.Buffer.YDisp);
    core.ScrollPages(High(Integer));
    AssertEquals('pages to the bottom', core.Buffer.YBase, core.Buffer.YDisp);
    core.ScrollPages(Low(Integer));
    AssertEquals('pages to the top', 0, core.Buffer.YDisp);
  finally
    core.Free;
  end;
end;

{ ---- TTyTerminalReentryTests ----------------------------------------------------- }

type
  { calls the core from its events, once each (Action picks which) }
  TReentrySink = class
  public
    Core: TTyTerminalCore;
    Action: Integer;          { 1 Resize on scroll, 2 WriteSync on title, 3 Reset on bell,
                                4 ProcessPending on data, 5 Resize on resize,
                                6 raise on bell, 7 raise in a write callback }
    Fired: Integer;
    NestedResult: Boolean;
    Requests: Integer;
    Rows: Integer;
    Data: RawByteString;
    Tick, Step: Double;       { the clock: Tick, then Step further each call }
    procedure OnScroll(Sender: TObject; AYDisp: Integer);
    procedure OnTitle(Sender: TObject; const AText: string);
    procedure OnBell(Sender: TObject);
    procedure OnData(Sender: TObject; const AData: RawByteString);
    procedure OnResize(Sender: TObject; ACols, ARows: Integer);
    procedure OnRows(Sender: TObject; AFirst, ALast: Integer);
    procedure OnRequest(Sender: TObject);
    procedure OnDone(Sender: TObject; ATag: PtrInt);
    function Clock: Double;
  end;

procedure TReentrySink.OnScroll(Sender: TObject; AYDisp: Integer);
begin
  if (Action = 1) and (Fired = 0) then
  begin
    Inc(Fired);
    Core.Resize(15, 4);
  end;
end;

procedure TReentrySink.OnTitle(Sender: TObject; const AText: string);
begin
  if (Action = 2) and (Fired = 0) then
  begin
    Inc(Fired);
    Core.WriteSync('X');
  end;
end;

procedure TReentrySink.OnBell(Sender: TObject);
begin
  if (Action = 3) and (Fired = 0) then
  begin
    Inc(Fired);
    Core.Reset;
  end
  else if (Action = 6) and (Fired = 0) then
  begin
    Inc(Fired);
    raise Exception.Create('bell handler');
  end;
end;

procedure TReentrySink.OnData(Sender: TObject; const AData: RawByteString);
begin
  Data := Data + AData;
  if (Action = 4) and (Fired = 0) then
  begin
    Inc(Fired);
    NestedResult := Core.ProcessPending;
  end;
end;

procedure TReentrySink.OnResize(Sender: TObject; ACols, ARows: Integer);
begin
  if (Action = 5) and (Fired = 0) then
  begin
    Inc(Fired);
    Core.Resize(ACols + 1, ARows);         { a host that adjusts: after this one }
  end;
end;

procedure TReentrySink.OnRows(Sender: TObject; AFirst, ALast: Integer);
begin
  Inc(Rows);
end;

procedure TReentrySink.OnRequest(Sender: TObject);
begin
  Inc(Requests);
end;

procedure TReentrySink.OnDone(Sender: TObject; ATag: PtrInt);
begin
  if (Action = 7) and (Fired = 0) then
  begin
    Inc(Fired);
    raise Exception.Create('write callback');
  end;
end;

function TReentrySink.Clock: Double;
begin
  Result := Tick;                          { Step 0: a slice never runs out of time }
  Tick := Tick + Step;
end;

function NewReentry(AAction: Integer; ACols: Integer = 20; ARows: Integer = 4): TReentrySink;
begin
  Result := TReentrySink.Create;
  Result.Action := AAction;
  Result.Core := TTyTerminalCore.Create(ACols, ARows);
  Result.Core.OnScroll := @Result.OnScroll;
  Result.Core.OnTitleChange := @Result.OnTitle;
  Result.Core.OnBell := @Result.OnBell;
  Result.Core.OnData := @Result.OnData;
  Result.Core.OnResize := @Result.OnResize;
  Result.Core.OnRefreshRows := @Result.OnRows;
  Result.Core.OnProcessRequest := @Result.OnRequest;
  Result.Core.Clock := @Result.Clock;
end;

procedure FreeReentry(ASink: TReentrySink);
begin
  ASink.Core.Free;
  ASink.Free;
end;

procedure AssertSameScreen(const AWhat: string; A, B: TTyTerminalCore);
var
  compared: Int64;
  diff: string;
begin
  compared := 0;
  diff := ScreenDiff(A, B, compared);
  TAssert.AssertEquals(AWhat + ': ' + diff, '', diff);
  TAssert.AssertTrue(AWhat + ': compared', compared > 0);
end;

const
  SixLines = 'one'#13#10'two'#13#10'three'#13#10'four'#13#10'five'#13#10'six';
  LongLines = 'one 345678901234567'#13#10'two 345678901234567'#13#10'three 5678901234567'#13#10
    + 'four 45678901234567'#13#10'five 45678901234567'#13#10'six 345678901234567';

{ OnScroll fires in the middle of printing; a Resize there waits for the chunk and
  then equals a Resize made after WriteSync returned }
procedure TTyTerminalReentryTests.TestResizeFromOnScroll;
var
  s: TReentrySink;
  ref: TTyTerminalCore;
begin
  s := NewReentry(1);
  ref := TTyTerminalCore.Create(20, 4);
  try
    { lines longer than the new width: printed at 15 columns they would wrap }
    s.Core.WriteSync(LongLines);
    AssertEquals('fired', 1, s.Fired);
    ref.WriteSync(LongLines);
    ref.Resize(15, 4);
    AssertEquals('resized', 15, s.Core.Cols);
    AssertSameScreen('as if called afterwards', ref, s.Core);
    AssertEquals('nothing parsed twice', 1, CountOf('six', s.Core.Buffer.TranslateBufferLineToString(
      s.Core.Buffer.YBase + s.Core.Buffer.Y, True)));
  finally
    FreeReentry(s);
    ref.Free;
  end;
end;

procedure TTyTerminalReentryTests.TestWriteSyncFromOnTitleChange;
var
  s: TReentrySink;
  ref: TTyTerminalCore;
begin
  s := NewReentry(2);
  ref := TTyTerminalCore.Create(20, 4);
  try
    s.Core.WriteSync('ab'#27']2;t'#7'cd');
    AssertEquals('fired', 1, s.Fired);
    AssertEquals('the title chunk, then X', 'abcdX', s.Core.Buffer.TranslateBufferLineToString(0, True));
    ref.WriteSync('ab'#27']2;t'#7'cd');
    ref.WriteSync('X');
    AssertSameScreen('as if called afterwards', ref, s.Core);
  finally
    FreeReentry(s);
    ref.Free;
  end;
  { in a slice whose budget runs out after that chunk: WriteSync still keeps its
    word once the chunk is done -- everything queued, then X, parsed at once }
  s := NewReentry(2);
  try
    s.Step := 20;
    s.Core.Write('ab'#27']2;t'#7'cd');
    s.Core.Write('ef');
    AssertFalse('nothing left after the chunk', s.Core.ProcessPending);
    AssertEquals('the rest, then X', 'abcdefX', s.Core.Buffer.TranslateBufferLineToString(0, True));
  finally
    FreeReentry(s);
  end;
end;

procedure TTyTerminalReentryTests.TestResetFromOnBell;
var
  s: TReentrySink;
  ref: TTyTerminalCore;
begin
  s := NewReentry(3);
  ref := TTyTerminalCore.Create(20, 4);
  try
    s.Core.WriteSync(SixLines + #7'after');
    AssertEquals('fired', 1, s.Fired);
    ref.WriteSync(SixLines + #7'after');
    ref.Reset;
    AssertSameScreen('as if called afterwards', ref, s.Core);
    s.Core.WriteSync('more');
    ref.WriteSync('more');
    AssertSameScreen('and it goes on the same', ref, s.Core);
  finally
    FreeReentry(s);
    ref.Free;
  end;
end;

{ a modal loop in a handler can run the host's scheduled ProcessPending: it returns
  False at once, the running slice finishes, nothing is parsed twice }
procedure TTyTerminalReentryTests.TestProcessPendingFromOnData;
var
  s: TReentrySink;
begin
  s := NewReentry(4);
  try
    s.Core.Write('ab'#27'[5ncd');
    s.Core.Write('ef');
    AssertFalse('the slice drains the queue', s.Core.ProcessPending);
    AssertEquals('fired', 1, s.Fired);
    AssertFalse('the nested call did nothing', s.NestedResult);
    AssertEquals('each byte once', 'abcdef', s.Core.Buffer.TranslateBufferLineToString(0, True));
    AssertEquals('one reply', #27'[0n', s.Data);
    AssertEquals('empty queue', 0, s.Core.PendingBytes);
  finally
    FreeReentry(s);
  end;
end;

{ OnResize fires while the core is resizing: a Resize from there comes after }
procedure TTyTerminalReentryTests.TestResizeFromOnResize;
var
  s: TReentrySink;
begin
  s := NewReentry(5);
  try
    s.Core.Resize(30, 6);
    AssertEquals('fired', 1, s.Fired);
    AssertEquals('the host''s adjustment last', 31, s.Core.Cols);
    AssertEquals(6, s.Core.Rows);
  finally
    FreeReentry(s);
  end;
end;

{ a handler raises: the exception reaches WriteSync's caller, the rows the chunk
  changed are still reported, and the next write goes on from there -- the failed
  chunk is not parsed again }
procedure TTyTerminalReentryTests.TestHandlerExceptionInWriteSync;
var
  s: TReentrySink;
  raised: Boolean;
begin
  s := NewReentry(6);
  try
    raised := False;
    try
      s.Core.WriteSync('a'#7'b');
    except
      on E: Exception do raised := E.Message = 'bell handler';
    end;
    AssertTrue('raised through', raised);
    AssertEquals('dirty rows reported', 1, s.Rows);
    s.Core.WriteSync('c');
    AssertEquals('on from there, nothing twice', 'ac', s.Core.Buffer.TranslateBufferLineToString(0, True));
    AssertEquals('empty queue', 0, s.Core.PendingBytes);
  finally
    FreeReentry(s);
  end;
end;

{ a write callback raises in a slice: the rest stays queued and is asked for again }
procedure TTyTerminalReentryTests.TestCallbackExceptionInASlice;
var
  s: TReentrySink;
  raised: Boolean;
begin
  s := NewReentry(7);
  try
    s.Core.Write('A', @s.OnDone);
    s.Core.Write('B');
    AssertEquals('asked once', 1, s.Requests);
    raised := False;
    try
      s.Core.ProcessPending;
    except
      on E: Exception do raised := E.Message = 'write callback';
    end;
    AssertTrue('raised through', raised);
    AssertEquals('asked again', 2, s.Requests);
    AssertEquals('B waits', 1, s.Core.PendingBytes);
    AssertFalse('the rest', s.Core.ProcessPending);
    AssertEquals('each once', 'AB', s.Core.Buffer.TranslateBufferLineToString(0, True));
  finally
    FreeReentry(s);
  end;
end;

{ WriteSync's flush meets a raising handler: what is behind the chunk stays queued
  for a slice, instead of being dropped or leaving the flush stuck }
procedure TTyTerminalReentryTests.TestExceptionInAFlushKeepsTheRest;
var
  s: TReentrySink;
  raised: Boolean;
begin
  s := NewReentry(6);
  try
    s.Core.Write('P');
    s.Core.Write('Q'#7);
    s.Core.Write('R');
    raised := False;
    try
      s.Core.WriteSync('S');
    except
      on E: Exception do raised := E.Message = 'bell handler';
    end;
    AssertTrue('raised through', raised);
    AssertEquals('R and S wait', 2, s.Core.PendingBytes);
    AssertTrue('a slice asked for', s.Requests >= 1);
    AssertFalse('the rest', s.Core.ProcessPending);
    AssertEquals('each once, in order', 'PQRS', s.Core.Buffer.TranslateBufferLineToString(0, True));
  finally
    FreeReentry(s);
  end;
end;

{ ---- TTyTerminalWriteQueueTests ---------------------------------------------------- }

type
  { a clock that answers a script, repeating its last value; or steps by Step }
  TQueueRig = class
  public
    Core: TTyTerminalCore;
    Script: array of Double;
    Pos: Integer;
    Step: Double;
    Current: Double;
    Requests: Integer;
    Done: array of PtrInt;
    SeenOnDone: TStringList;           { line 0 as each callback saw it }
    WriteAgainTag: PtrInt;
    constructor Create(ACols: Integer = 20; ARows: Integer = 6);
    destructor Destroy; override;
    function Clock: Double;
    procedure OnRequest(Sender: TObject);
    procedure OnDone(Sender: TObject; ATag: PtrInt);
    function Line0: string;
    procedure SetScript(const AValues: array of Double);
  end;

constructor TQueueRig.Create(ACols, ARows: Integer);
begin
  inherited Create;
  SeenOnDone := TStringList.Create;
  WriteAgainTag := -1;
  Core := TTyTerminalCore.Create(ACols, ARows);
  Core.Clock := @Clock;
  Core.OnProcessRequest := @OnRequest;
end;

destructor TQueueRig.Destroy;
begin
  Core.Free;
  SeenOnDone.Free;
  inherited Destroy;
end;

function TQueueRig.Clock: Double;
begin
  if Length(Script) > 0 then
  begin
    if Pos <= High(Script) then
      Result := Script[Pos]
    else
      Result := Script[High(Script)];
    Inc(Pos);
  end
  else
  begin
    Current := Current + Step;
    Result := Current;
  end;
end;

procedure TQueueRig.SetScript(const AValues: array of Double);
var
  i: Integer;
begin
  Script := nil;
  SetLength(Script, Length(AValues));
  for i := 0 to High(AValues) do
    Script[i] := AValues[i];
  Pos := 0;
end;

procedure TQueueRig.OnRequest(Sender: TObject);
begin
  Inc(Requests);
end;

procedure TQueueRig.OnDone(Sender: TObject; ATag: PtrInt);
begin
  SetLength(Done, Length(Done) + 1);
  Done[High(Done)] := ATag;
  SeenOnDone.Add(Line0);
  if ATag = WriteAgainTag then
    Core.Write('z');
end;

function TQueueRig.Line0: string;
begin
  Result := Core.Buffer.Lines.Get(Core.Buffer.YBase).TranslateToString(True, 0, Core.Cols);
end;

procedure TTyTerminalWriteQueueTests.TestWriteQueuesAndAsksOnce;
var
  r: TQueueRig;
begin
  r := TQueueRig.Create;
  try
    r.Core.Write('a');
    r.Core.Write('b');
    AssertEquals('asked once', 1, r.Requests);
    AssertEquals('only queued', '', r.Line0);
    AssertEquals('pending', 2, r.Core.PendingBytes);
  finally
    r.Free;
  end;
end;

procedure TTyTerminalWriteQueueTests.TestProcessDrainsAndReports;
var
  r: TQueueRig;
begin
  r := TQueueRig.Create;
  try
    r.Core.Write('a');
    r.Core.Write('b');
    r.SetScript([0, 1, 2]);
    AssertFalse('nothing left', r.Core.ProcessPending);
    AssertEquals('ab', r.Line0);
    AssertEquals('pending', 0, r.Core.PendingBytes);
    r.Core.Write('c');
    AssertEquals('an empty queue asks again', 2, r.Requests);
  finally
    r.Free;
  end;
end;

{ upstream's cancelAndSet keeps one timer: a queue emptied by WriteSync while a
  request is still out does not ask a second time when it fills again }
procedure TTyTerminalWriteQueueTests.TestAnOutstandingRequestIsNotRepeated;
var
  r: TQueueRig;
begin
  r := TQueueRig.Create;
  try
    r.Core.Write('a');
    r.Core.WriteSync('b');
    AssertEquals('drained', 0, r.Core.PendingBytes);
    r.Core.Write('c');
    AssertEquals('still the one request', 1, r.Requests);
    r.SetScript([0, 1, 2]);
    AssertFalse('nothing left', r.Core.ProcessPending);
    AssertEquals('abc', r.Line0);
    r.Core.Write('d');
    AssertEquals('asks again once the slice ran', 2, r.Requests);
  finally
    r.Free;
  end;
end;

procedure TTyTerminalWriteQueueTests.TestSliceStopsBetweenChunksAtTheBudget;
var
  r: TQueueRig;
  i: Integer;
begin
  r := TQueueRig.Create;
  try
    for i := 1 to 5 do
      r.Core.Write('x');
    AssertEquals(1, r.Requests);
    { the start, then after each chunk }
    r.SetScript([0, 5, 11, 12, 13]);
    AssertTrue('something left', r.Core.ProcessPending);
    AssertEquals('three chunks: 12 - 0 >= 12 after the third', 'xxx', r.Line0);
    AssertEquals('the slice does not ask by itself', 1, r.Requests);
    AssertEquals('pending', 2, r.Core.PendingBytes);
    AssertFalse('the rest', r.Core.ProcessPending);
    AssertEquals('xxxxx', r.Line0);
    AssertEquals('pending', 0, r.Core.PendingBytes);
  finally
    r.Free;
  end;
end;

procedure TTyTerminalWriteQueueTests.TestOneBigChunkIsNotSplit;
var
  r: TQueueRig;
  s: RawByteString;
begin
  r := TQueueRig.Create;
  try
    s := StringOfChar('x', 1024 * 1024);
    r.Core.Write(s);
    r.Step := 100;
    AssertFalse('one chunk, whole', r.Core.ProcessPending);
    AssertEquals('pending', 0, r.Core.PendingBytes);
    AssertEquals(StringOfChar('x', 20), r.Line0);
  finally
    r.Free;
  end;
end;

procedure TTyTerminalWriteQueueTests.TestCallbacksRunInOrder;
var
  r: TQueueRig;
begin
  r := TQueueRig.Create;
  try
    r.Core.Write('A', @r.OnDone, 1);
    r.Core.Write('B', @r.OnDone, 2);
    r.Core.Write('C', @r.OnDone, 3);
    r.SetScript([0, 5, 12, 12]);
    AssertTrue(r.Core.ProcessPending);
    AssertEquals('two callbacks in the first slice', 2, Length(r.Done));
    AssertEquals(1, r.Done[0]);
    AssertEquals(2, r.Done[1]);
    r.SetScript([0, 1]);
    AssertFalse(r.Core.ProcessPending);
    AssertEquals(3, Length(r.Done));
    AssertEquals(3, r.Done[2]);
    AssertEquals('each callback sees its chunk and not the next', 'A,AB,ABC', r.SeenOnDone.CommaText);
  finally
    r.Free;
  end;
end;

procedure TTyTerminalWriteQueueTests.TestCallbackMayWriteAgain;
var
  r: TQueueRig;
begin
  r := TQueueRig.Create;
  try
    r.WriteAgainTag := 1;
    r.Core.Write('a', @r.OnDone, 1);
    r.Core.Write('b');
    r.SetScript([0]);
    AssertFalse('the new chunk goes in the same slice', r.Core.ProcessPending);
    AssertEquals('no second request: the queue was not empty', 1, r.Requests);
    AssertEquals('abz', r.Line0);
  finally
    r.Free;
  end;
end;

procedure TTyTerminalWriteQueueTests.TestFirstWriteAfterInputParsesAtOnce;
var
  r: TQueueRig;
begin
  r := TQueueRig.Create;
  try
    r.SetScript([0]);
    r.Core.Input('k', True);
    r.Core.Write('ab', @r.OnDone, 7);
    AssertEquals('parsed at once', 'ab', r.Line0);
    AssertEquals('callback called', 1, Length(r.Done));
    AssertEquals('nothing asked', 0, r.Requests);
    r.Core.Write('c');
    AssertEquals('the next one only queues', 'ab', r.Line0);
    AssertEquals(1, r.Requests);
    r.Core.ProcessPending;
    r.Core.Input('k', False);
    r.Core.Write('d');
    AssertEquals('not user input: queued', 'abc', r.Line0);
  finally
    r.Free;
  end;
end;

procedure TTyTerminalWriteQueueTests.TestFiftyMegabytesRaises;
var
  r: TQueueRig;
  s: RawByteString;
  i: Integer;
  raised: Boolean;
begin
  r := TQueueRig.Create;
  try
    s := StringOfChar('y', 1000000);
    for i := 1 to 50 do
      r.Core.Write(s);
    AssertEquals(Int64(50000000), r.Core.PendingBytes);
    r.Core.Write(s);                     { 50,000,000 is not more than the limit }
    AssertEquals(Int64(51000000), r.Core.PendingBytes);
    raised := False;
    try
      r.Core.Write(s);
    except
      on ETyTerminalWriteOverflow do raised := True;
    end;
    AssertTrue('past 50 MB', raised);
    AssertEquals('nothing added', Int64(51000000), r.Core.PendingBytes);
  finally
    r.Free;
  end;
end;

procedure TTyTerminalWriteQueueTests.TestWriteSyncParsesQueuedFirst;
var
  r: TQueueRig;
begin
  r := TQueueRig.Create;
  try
    r.Core.Write('a', @r.OnDone, 1);
    r.Core.WriteSync('b');
    AssertEquals('ab', r.Line0);
    AssertEquals('the queued callback ran', 1, Length(r.Done));
    AssertEquals('pending', 0, r.Core.PendingBytes);
  finally
    r.Free;
  end;
end;

procedure TTyTerminalWriteQueueTests.TestResizeFlushesFirst;
var
  r: TQueueRig;
  wp: TTyTerminalWindowsPty;
begin
  r := TQueueRig.Create(20, 6);
  try
    wp.Backend := twpConPty;
    wp.BuildNumber := 19044;
    r.Core.WindowsPty := wp;
    r.Core.Write(StringOfChar('x', 25));
    r.Core.Resize(10, 6);
    AssertEquals('wrapped at the old 20 columns', StringOfChar('x', 20),
      r.Core.Buffer.Lines.Get(0).TranslateToString(True, 0, 20));
    AssertEquals(StringOfChar('x', 5), r.Core.Buffer.Lines.Get(1).TranslateToString(True, 0, 20));
    AssertTrue(r.Core.Buffer.Lines.Get(1).IsWrapped);
    AssertEquals(10, r.Core.Cols);
  finally
    r.Free;
  end;
end;

procedure TTyTerminalWriteQueueTests.TestResizeFlushDoesNotReparse;
var
  r: TQueueRig;
  wp: TTyTerminalWindowsPty;
begin
  r := TQueueRig.Create(20, 6);
  try
    wp.Backend := twpConPty;
    wp.BuildNumber := 19044;
    r.Core.WindowsPty := wp;
    r.Core.Write('A', @r.OnDone, 1);
    r.Core.Write('B');
    r.Core.Write('C');
    r.SetScript([0, 12]);
    AssertTrue('A only', r.Core.ProcessPending);
    AssertEquals('A', r.Line0);
    r.Core.Resize(30, 6);
    AssertEquals('upstream parses A again here (AABC)', 'ABC', r.Line0);
    AssertEquals('A''s callback once', 1, Length(r.Done));
  finally
    r.Free;
  end;
end;

procedure TTyTerminalWriteQueueTests.TestSlicedEqualsWhole;
var
  m: TTyTermMisses;
  fx: TTyTermFixtures;
  cases: TFPList;
  c: TJSONObject;
  palette: TJSONArray;
  i, k: Integer;
  input: RawByteString;
  h: TTyTermHarness;
  rig: TQueueRig;
begin
  m := TTyTermMisses.Create;
  try
    fx := TyTermLoadFixtures('core-escape', m);
    cases := TyTermAllCases(fx);
    try
      c := nil;
      for i := 0 to cases.Count - 1 do
        if TJSONObject(cases[i]).Strings['id'] = 't0504-vim.in' then
          c := TJSONObject(cases[i]);
      AssertNotNull('t0504-vim.in in the fixture', c);
      palette := fx[0].Arrays['palette'];
      input := TyTermBase64Bytes(c.Arrays['steps'].Objects[0].Strings['write']);
      { sliced: 97-byte writes, one chunk per slice }
      h := TTyTermHarness.Create(c, palette);
      rig := TQueueRig.Create;
      try
        rig.Step := 100;
        h.Core.Clock := @rig.Clock;
        k := 1;
        while k <= Length(input) do
        begin
          h.Core.Write(Copy(input, k, 97));
          Inc(k, 97);
        end;
        i := 0;
        while h.Core.ProcessPending do
          Inc(i);
        AssertTrue('many slices', i > 10);
        TyTermCompareState(h, c.Objects['expect'], 'sliced', True, m);
      finally
        h.Free;
        rig.Free;
      end;
      { whole, through WriteSync }
      h := TTyTermHarness.Create(c, palette);
      try
        h.Core.WriteSync(input);
        TyTermCompareState(h, c.Objects['expect'], 'whole', False, m);
      finally
        h.Free;
      end;
    finally
      cases.Free;
      TyTermFreeFixtures(fx);
    end;
    AssertEquals(m.Text, 0, m.Count);
    AssertTrue('compared', m.Compared > 2 * 80 * 25);
  finally
    m.Free;
  end;
end;

const
  ThreadEntries = 15;

type
  TOtherThread = class(TThread)
  public
    Core: TTyTerminalCore;
    Classes_: array[0..ThreadEntries - 1] of string;
    procedure Execute; override;
  end;

procedure TOtherThread.Execute;

  procedure Try_(AKind: Integer);
  var
    b: Byte;
    ev: TTyTerminalMouseEvent;
  begin
    Classes_[AKind] := '(none)';
    b := Ord('a');
    ev := MouseAt(0, 0, tmbLeft, tmaDown);
    try
      case AKind of
        0: Core.Write('a');
        1: Core.Write(b, 1);
        2: Core.WriteSync('a');
        3: Core.ProcessPending;
        4: Core.Resize(30, 8);
        5: Core.Reset;
        6: Core.Input('a');
        7: Core.ScrollLines(-1);
        8: Core.ScrollPages(-1);
        9: Core.ScrollToBottom;
        10: Core.ScrollToTop;
        11: Core.ClearScrollback;
        12: Core.TriggerMouseEvent(ev);
        13: Core.ReportFocus(False);
      else
        Core.EndSynchronizedOutput;
      end;
    except
      on E: Exception do Classes_[AKind] := E.ClassName;
    end;
  end;

var
  k: Integer;
begin
  for k := 0 to ThreadEntries - 1 do
    Try_(k);
end;

procedure TTyTerminalWriteQueueTests.TestOtherThreadsAreRefused;
var
  core: TTyTerminalCore;
  t: TOtherThread;
  i: Integer;
begin
  core := TTyTerminalCore.Create(20, 5);
  t := TOtherThread.Create(True);
  try
    t.Core := core;
    t.FreeOnTerminate := False;
    t.Start;
    t.WaitFor;
    for i := 0 to ThreadEntries - 1 do
      AssertEquals(Format('entry %d', [i]), 'EInvalidOperation', t.Classes_[i]);
    AssertEquals('nothing queued', 0, core.PendingBytes);
    AssertEquals('nothing parsed', '', core.Buffer.Lines.Get(0).TranslateToString(True, 0, 20));
    AssertEquals('not resized', 20, core.Cols);
  finally
    t.Free;
    core.Free;
  end;
end;

procedure TTyTerminalWriteQueueTests.TestDestroyDropsPending;
var
  r: TQueueRig;
  base, calls: Integer;
begin
  base := TTyTerminalLine.LiveCount;
  r := TQueueRig.Create;
  r.Core.Write('a', @r.OnDone, 1);
  r.Core.Write('b', @r.OnDone, 2);
  r.Core.Write('c', @r.OnDone, 3);
  r.Core.Free;
  r.Core := nil;
  calls := Length(r.Done);
  r.Free;
  AssertEquals('no callback for dropped chunks', 0, calls);
  AssertEquals('lines freed', base, TTyTerminalLine.LiveCount);
end;

{ Write('') alone is nothing; with a callback it is queued, for its callback. The
  chunks waiting are bounded like their bytes. }
procedure TTyTerminalWriteQueueTests.TestEmptyWritesAndTheChunkBound;
var
  r: TQueueRig;
  i: Integer;
  raised: Boolean;
begin
  r := TQueueRig.Create;
  try
    r.Core.Write('');
    AssertEquals('nothing asked', 0, r.Requests);
    r.Core.Write('', @r.OnDone, 5);
    AssertEquals('a callback: queued', 1, r.Requests);
    r.SetScript([0]);
    AssertFalse(r.Core.ProcessPending);
    AssertEquals('its callback ran', 1, Length(r.Done));
    AssertEquals(5, r.Done[0]);
    for i := 1 to TyTermMaxPendingChunks do
      r.Core.Write('x');
    raised := False;
    try
      r.Core.Write('x');
    except
      on ETyTerminalWriteOverflow do raised := True;
    end;
    AssertTrue('one chunk too many', raised);
    AssertEquals('the bound held', Int64(TyTermMaxPendingChunks), r.Core.PendingBytes);
    AssertFalse('they all parse', r.Core.ProcessPending);
    r.Core.Write('x');
    AssertEquals('and room again', 1, r.Core.PendingBytes);
  finally
    r.Free;
  end;
end;

{ a chunk's bytes are let go of as soon as it is parsed, not when the queue empties }
procedure TTyTerminalWriteQueueTests.TestAParsedChunkIsReleased;
var
  r: TQueueRig;
  s: RawByteString;
  before, after: PtrUInt;
begin
  r := TQueueRig.Create;
  try
    s := StringOfChar(#0, 8 * 1024 * 1024);   { NUL: parsed and ignored, quick }
    r.Core.Write(s);
    s := '';                               { the queue holds the only reference }
    r.Core.Write('z');
    before := GetFPCHeapStatus.CurrHeapUsed;
    r.SetScript([0, 20]);                  { one chunk, then the budget is spent }
    AssertTrue('z still waits', r.Core.ProcessPending);
    after := GetFPCHeapStatus.CurrHeapUsed;
    AssertTrue(Format('8 MB given back (%d -> %d)', [before, after]), Int64(before) - Int64(after) > 7 * 1024 * 1024);
  finally
    r.Free;
  end;
end;

procedure TTyTerminalWriteQueueTests.TestDefaultClockMoves;
var
  t1, t2: Double;
  core: TTyTerminalCore;
begin
  t1 := TyTermDefaultClock;
  Sleep(20);
  t2 := TyTermDefaultClock;
  AssertTrue(Format('milliseconds that move (%.3f)', [t2 - t1]), (t2 - t1 >= 10) and (t2 - t1 <= 1000));
  core := TTyTerminalCore.Create(20, 5);
  try
    core.Write('a');
    AssertFalse('the built-in clock slices too', core.ProcessPending);
    AssertEquals('a', core.Buffer.Lines.Get(0).TranslateToString(True, 0, 20));
  finally
    core.Free;
  end;
end;

initialization
  RegisterTest(TTyTerminalCoreOracleTests);
  RegisterTest(TTyTerminalCoreTests);
  RegisterTest(TTyTerminalReentryTests);
  RegisterTest(TTyTerminalWriteQueueTests);
end.
