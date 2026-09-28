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
  parsing tables, the host OSC hook, mode-change and icon events, the REP cap,
  window reports, theme changes, read-only, the no-LCL rule, lines freed with the
  core and the XTVERSION string. }

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
    procedure TestRepBeyondTheCapEqualsTheCap;
    procedure TestWindowReportsAskTheHost;
    procedure TestThemeChangeDropsOverrides;
    procedure TestReadOnlySendsNothing;
    procedure TestCoreUnitsDoNotUseTheLcl;
    procedure TestNoLineOutlivesTheCore;
    procedure TestXtVersionConstant;
  end;

  { The write queue has no upstream oracle (headless cannot observe slices): these
    are WriteBuffer.ts's rules read one by one, under a scripted clock. }
  TTyTerminalWriteQueueTests = class(TTestCase)
  published
    procedure TestWriteQueuesAndAsksOnce;
    procedure TestProcessDrainsAndReports;
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
              allowed := (Int64(h.Core.Buffers.Normal.Lines.Length) + h.Core.Buffers.Alt.Lines.Length)
                * h.Core.Cols * 64 + 1024 * 1024;
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
    procedure OnOsc(Sender: TObject; AIdent: Integer; const AData: string; var AHandled: Boolean);
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

procedure TOscSink.OnOsc(Sender: TObject; AIdent: Integer; const AData: string; var AHandled: Boolean);
begin
  Log.Add(IntToStr(AIdent) + '=' + AData);
  AHandled := True;
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

procedure TTyTerminalCoreTests.TestRepBeyondTheCapEqualsTheCap;

  function Make(const ACount: string): TTyTerminalCore;
  begin
    Result := TTyTerminalCore.Create(20, 4);
    Result.Scrollback := 10;
    Result.WriteSync('a'#27'[' + ACount + 'b');
  end;

  procedure Same(A, B: TTyTerminalCore; const AWhat: string; var ACompared: Integer);
  var
    r, c: Integer;
    la, lb: TTyTerminalLine;
  begin
    AssertEquals(AWhat + ' x', A.Buffer.X, B.Buffer.X);
    AssertEquals(AWhat + ' y', A.Buffer.Y, B.Buffer.Y);
    AssertEquals(AWhat + ' ybase', A.Buffer.YBase, B.Buffer.YBase);
    AssertEquals(AWhat + ' ydisp', A.Buffer.YDisp, B.Buffer.YDisp);
    AssertEquals(AWhat + ' lines', A.Buffer.Lines.Length, B.Buffer.Lines.Length);
    for r := 0 to A.Buffer.Lines.Length - 1 do
    begin
      la := A.Buffer.Lines.Get(r);
      lb := B.Buffer.Lines.Get(r);
      for c := 0 to 19 do
      begin
        Inc(ACompared);
        AssertEquals(Format('%s row %d col %d content', [AWhat, r, c]), la.GetContent(c), lb.GetContent(c));
        AssertEquals(Format('%s row %d col %d fg', [AWhat, r, c]), la.GetFg(c), lb.GetFg(c));
        AssertEquals(Format('%s row %d col %d bg', [AWhat, r, c]), la.GetBg(c), lb.GetBg(c));
      end;
    end;
  end;

var
  cap, over, huge: TTyTerminalCore;
  n: Integer;
  t0: QWord;
begin
  cap := Make('1048576');
  over := Make('1048577');
  t0 := GetTickCount64;
  huge := Make('2147483647');
  try
    AssertTrue('the huge count returns quickly', GetTickCount64 - t0 < 5000);
    n := 0;
    Same(cap, over, 'cap+1', n);
    AssertEquals('every cell compared', cap.Buffer.Lines.Length * 20, n);
    n := 0;
    Same(cap, huge, '2^31-1', n);
    AssertEquals('every cell compared', cap.Buffer.Lines.Length * 20, n);
    { and the cap is not a no-op: one short of it lands elsewhere }
    over.Free;
    over := Make('1048575');
    AssertTrue('one less moves the cursor differently',
      (over.Buffer.X <> cap.Buffer.X) or (over.Buffer.Y <> cap.Buffer.Y));
  finally
    cap.Free;
    over.Free;
    huge.Free;
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
  base: Integer;
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
  finally
    core.Free;
  end;
  AssertEquals('every line freed with the core', base, TTyTerminalLine.LiveCount);
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

type
  TOtherThread = class(TThread)
  public
    Core: TTyTerminalCore;
    Classes_: array[0..3] of string;
    procedure Execute; override;
  end;

procedure TOtherThread.Execute;

  procedure Try_(AIndex: Integer; AKind: Integer);
  var
    b: Byte;
  begin
    Classes_[AIndex] := '(none)';
    b := Ord('a');
    try
      case AKind of
        0: Core.Write('a');
        1: Core.Write(b, 1);
        2: Core.WriteSync('a');
      else
        Core.ProcessPending;
      end;
    except
      on E: Exception do Classes_[AIndex] := E.ClassName;
    end;
  end;

begin
  Try_(0, 0);
  Try_(1, 1);
  Try_(2, 2);
  Try_(3, 3);
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
    for i := 0 to 3 do
      AssertEquals(Format('entry %d', [i]), 'EInvalidOperation', t.Classes_[i]);
    AssertEquals('nothing queued', 0, core.PendingBytes);
    AssertEquals('nothing parsed', '', core.Buffer.Lines.Get(0).TranslateToString(True, 0, 20));
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
  RegisterTest(TTyTerminalWriteQueueTests);
end.
