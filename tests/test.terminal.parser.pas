unit test.terminal.parser;
{$mode objfpc}{$H+}
{ The escape sequence parser and the UTF-8 decoder -- held to xterm.js 6.0.0 itself.

  tools/terminal-oracle/parser-cases.js runs upstream's own EscapeSequenceParser and
  Utf8ToUtf32 (no terminal around them) and records: the VT500 transition table
  (terminal-parser-table.json); what every decode() call returns, across split and
  malformed input (terminal-parser-utf8.json); and the full callback trace of the
  parser -- print ranges, executes, CSI identifiers with their parameters and
  sub-parameters, ESC, OSC / DCS / APC start, put and end with their payloads,
  errors, and the calls into registered handler chains -- for hand-written input,
  every cut in two of fifteen of those, oversized input and seeded random input
  (terminal-parser-trace.json, possibly in parts).

  THE RULE: every event equal to upstream's, in order; payloads over 256 code points
  are compared by count and digest. Each oracle test counts its comparisons and
  asserts the count against the fixture, so an empty fixture or a loop that stops
  early cannot pass. The pure tables in TTyTerminalParserTests do not come from the
  fixtures. }

interface

uses
  Classes, SysUtils, Contnrs, fpcunit, testregistry, fpjson,
  tyControls.Unicode.Width, tyControls.Terminal.Parser, test.terminal.oracle;

type
  TTyTerminalParserOracleTests = class(TTestCase)
  private
    function RunTraces(const ASource: string; AWantCut: Integer; ALong: Boolean;
      AMisses: TTyTermMisses; out AWantCompared: Int64): Integer;
  published
    procedure TestFixturesComeFromThePinnedUpstream;
    procedure TestTransitionTableMatchesUpstream;
    procedure TestUtf8DecodeChunkByChunk;
    procedure TestHandTraces;
    procedure TestEveryCutTraces;
    procedure TestLongInputsStayBounded;
    procedure TestFuzzTraces;
  end;

  TTyTerminalParserTests = class(TTestCase)
  published
    procedure TestParamsBuild;
    procedure TestParamsRejectsBadInput;
    procedure TestIdentifierRules;
    procedure TestIdentToString;
    procedure TestUnregister;
    procedure TestHandlersFreedWithTheParser;
    procedure TestCodepointsToUtf8;
    procedure TestDecoderLeavesNothingBehindAfterClear;
  end;

implementation

{ ---- the trace recorder: the same events, in the same canonical text, as the
  JSON events of parser-cases.js after TyTermCanonJson ------------------------------ }

function S(const AText: string): string;
begin
  Result := TyTermCanonUtf8(AText);
end;

function B(AValue: Boolean): string;
begin
  if AValue then Result := 'true' else Result := 'false';
end;

const
  SubActionOsc: array[TTyTermSubAction] of string = ('START', 'PUT', 'END');
  SubActionDcs: array[TTyTermSubAction] of string = ('HOOK', 'PUT', 'UNHOOK');

type
  TTraceRec = class
  public
    Events: TStringList;
    Parser: TTyTerminalParser;
    constructor Create(AParser: TTyTerminalParser);
    destructor Destroy; override;
    procedure Ev(const AText: string);
    procedure OnPrint(const AData: array of Cardinal; AStart, AEnd: Integer);
    procedure OnExec(ACode: Cardinal);
    procedure OnCsi(AIdent: Cardinal; AParams: TTyTerminalParams);
    procedure OnEsc(AIdent: Cardinal);
    procedure OnOsc(AIdent: Int64; AAction: TTyTermSubAction; const APayload: string; ASuccess: Boolean);
    procedure OnDcs(AIdent: Cardinal; AAction: TTyTermSubAction; AParams: TTyTerminalParams;
      const APayload: string; ASuccess: Boolean);
    procedure OnApc(AIdent: Cardinal; AAction: TTyTermSubAction; const APayload: string; ASuccess: Boolean);
    procedure OnError(var AState: TTyTermParsingState);
  end;

  { one per register item that is not an owned handler object }
  TReg = class
  public
    K: Integer;
    Ret: Boolean;
    Rec: TTraceRec;
    function Csi(AParams: TTyTerminalParams): Boolean;
    function Esc: Boolean;
    function Exec: Boolean;
    function OscData(const AData: string): Boolean;
    function DcsData(const AData: string; AParams: TTyTerminalParams): Boolean;
    function ApcData(const AData: string): Boolean;
  end;

  TRawOsc = class(TTyTerminalOscHandler)
  public
    K: Integer;
    Ret: Boolean;
    Rec: TTraceRec;
    procedure Start; override;
    procedure Put(const AData: array of Cardinal; AStart, AEnd: Integer); override;
    function Finish(ASuccess: Boolean): Boolean; override;
  end;

  TRawDcs = class(TTyTerminalDcsHandler)
  public
    K: Integer;
    Ret: Boolean;
    Rec: TTraceRec;
    procedure Hook(AParams: TTyTerminalParams); override;
    procedure Put(const AData: array of Cardinal; AStart, AEnd: Integer); override;
    function Unhook(ASuccess: Boolean): Boolean; override;
  end;

  TRawApc = class(TTyTerminalApcHandler)
  public
    K: Integer;
    Ret: Boolean;
    Rec: TTraceRec;
    procedure Start; override;
    procedure Put(const AData: array of Cardinal; AStart, AEnd: Integer); override;
    function Finish(ASuccess: Boolean): Boolean; override;
  end;

function CpsSlice(const AData: array of Cardinal; AStart, AEnd: Integer): string;
var
  c: TTyTermCps;
  i: Integer;
begin
  c := nil;
  SetLength(c, AEnd - AStart);
  for i := AStart to AEnd - 1 do
    c[i - AStart] := AData[i];
  Result := TyTermCanonCps(c);
end;

constructor TTraceRec.Create(AParser: TTyTerminalParser);
begin
  inherited Create;
  Events := TStringList.Create;
  Parser := AParser;
end;

destructor TTraceRec.Destroy;
begin
  Events.Free;
  inherited Destroy;
end;

procedure TTraceRec.Ev(const AText: string);
begin
  Events.Add(AText);
end;

procedure TTraceRec.OnPrint(const AData: array of Cardinal; AStart, AEnd: Integer);
begin
  Ev(S('print') + ' ' + CpsSlice(AData, AStart, AEnd));
  if AEnd > AStart then
    Parser.PrecedingJoinState := TTyUnicodeCharProps(AData[AEnd - 1]);
end;

procedure TTraceRec.OnExec(ACode: Cardinal);
begin
  Ev(S('exec') + ' ' + IntToStr(ACode));
end;

procedure TTraceRec.OnCsi(AIdent: Cardinal; AParams: TTyTerminalParams);
begin
  Ev(S('csi') + ' ' + IntToStr(AIdent) + ' ' + S(AParams.ToJson));
end;

procedure TTraceRec.OnEsc(AIdent: Cardinal);
begin
  Ev(S('esc') + ' ' + IntToStr(AIdent));
end;

procedure TTraceRec.OnOsc(AIdent: Int64; AAction: TTyTermSubAction; const APayload: string; ASuccess: Boolean);
var
  id, p, ok: string;
begin
  if AIdent > High(Integer) then id := S('big') else id := IntToStr(AIdent);
  if AAction = tsaPut then p := S(APayload) else p := 'null';
  if AAction = tsaEnd then ok := B(ASuccess) else ok := 'null';
  Ev(S('osc') + ' ' + id + ' ' + S(SubActionOsc[AAction]) + ' ' + p + ' ' + ok);
end;

procedure TTraceRec.OnDcs(AIdent: Cardinal; AAction: TTyTermSubAction; AParams: TTyTerminalParams;
  const APayload: string; ASuccess: Boolean);
var
  p, ok: string;
begin
  case AAction of
    tsaStart: p := S(AParams.ToJson);
    tsaPut: p := S(APayload);
  else
    p := 'null';
  end;
  if AAction = tsaEnd then ok := B(ASuccess) else ok := 'null';
  Ev(S('dcs') + ' ' + IntToStr(AIdent) + ' ' + S(SubActionDcs[AAction]) + ' ' + p + ' ' + ok);
end;

procedure TTraceRec.OnApc(AIdent: Cardinal; AAction: TTyTermSubAction; const APayload: string; ASuccess: Boolean);
var
  p, ok: string;
begin
  if AAction = tsaPut then p := S(APayload) else p := 'null';
  if AAction = tsaEnd then ok := B(ASuccess) else ok := 'null';
  Ev(S('apc') + ' ' + IntToStr(AIdent) + ' ' + S(SubActionOsc[AAction]) + ' ' + p + ' ' + ok);
end;

procedure TTraceRec.OnError(var AState: TTyTermParsingState);
begin
  Ev(S('error') + ' ' + IntToStr(AState.Code) + ' ' + IntToStr(Ord(AState.CurrentState)));
end;

function HPrefix(AK: Integer; const AKind: string): string;
begin
  Result := S('h') + ' ' + IntToStr(AK) + ' ' + S(AKind);
end;

function TReg.Csi(AParams: TTyTerminalParams): Boolean;
begin
  Rec.Ev(HPrefix(K, 'csi') + ' ' + S(AParams.ToJson));
  Result := Ret;
end;

function TReg.Esc: Boolean;
begin
  Rec.Ev(HPrefix(K, 'esc'));
  Result := Ret;
end;

function TReg.Exec: Boolean;
begin
  Rec.Ev(HPrefix(K, 'exec'));
  Result := True;
end;

function TReg.OscData(const AData: string): Boolean;
begin
  Rec.Ev(HPrefix(K, 'osc') + ' ' + S(AData));
  Result := Ret;
end;

function TReg.DcsData(const AData: string; AParams: TTyTerminalParams): Boolean;
begin
  Rec.Ev(HPrefix(K, 'dcs') + ' ' + S(AData) + ' ' + S(AParams.ToJson));
  Result := Ret;
end;

function TReg.ApcData(const AData: string): Boolean;
begin
  Rec.Ev(HPrefix(K, 'apc') + ' ' + S(AData));
  Result := Ret;
end;

procedure TRawOsc.Start;
begin
  Rec.Ev(HPrefix(K, 'osc-start'));
end;

procedure TRawOsc.Put(const AData: array of Cardinal; AStart, AEnd: Integer);
begin
  Rec.Ev(HPrefix(K, 'osc-put') + ' ' + CpsSlice(AData, AStart, AEnd));
end;

function TRawOsc.Finish(ASuccess: Boolean): Boolean;
begin
  Rec.Ev(HPrefix(K, 'osc-end') + ' ' + B(ASuccess));
  Result := Ret;
end;

procedure TRawDcs.Hook(AParams: TTyTerminalParams);
begin
  Rec.Ev(HPrefix(K, 'dcs-hook') + ' ' + S(AParams.ToJson));
end;

procedure TRawDcs.Put(const AData: array of Cardinal; AStart, AEnd: Integer);
begin
  Rec.Ev(HPrefix(K, 'dcs-put') + ' ' + CpsSlice(AData, AStart, AEnd));
end;

function TRawDcs.Unhook(ASuccess: Boolean): Boolean;
begin
  Rec.Ev(HPrefix(K, 'dcs-unhook') + ' ' + B(ASuccess));
  Result := Ret;
end;

procedure TRawApc.Start;
begin
  Rec.Ev(HPrefix(K, 'apc-start'));
end;

procedure TRawApc.Put(const AData: array of Cardinal; AStart, AEnd: Integer);
begin
  Rec.Ev(HPrefix(K, 'apc-put') + ' ' + CpsSlice(AData, AStart, AEnd));
end;

function TRawApc.Finish(ASuccess: Boolean): Boolean;
begin
  Rec.Ev(HPrefix(K, 'apc-end') + ' ' + B(ASuccess));
  Result := Ret;
end;

function FunctionIdOf(AObj: TJSONObject): TTyTerminalFunctionId;
begin
  Result.Prefix := AObj.Get('prefix', '');
  Result.Intermediates := AObj.Get('intermediates', '');
  Result.Final := AObj.Strings['final'][1];
end;

function JsonEventCanon(AArr: TJSONArray): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to AArr.Count - 1 do
  begin
    if i > 0 then
      Result := Result + ' ';
    Result := Result + TyTermCanonJson(AArr.Items[i]);
  end;
end;

type
  TCpsArray = array of Cardinal;

function FilledCps(ACp: Cardinal; ACount: Integer): TCpsArray;
var
  i: Integer;
begin
  Result := nil;
  SetLength(Result, ACount);
  for i := 0 to ACount - 1 do
    Result[i] := ACp;
end;

{ Runs one trace case: registers, feeds, compares every event and the final state.
  AParseCalls / ABoundChecks count the OscPayloadLength checks made after each parse
  when ACheckBounds. Returns the number of comparisons the fixture calls for. }
function RunTraceCase(ACase: TJSONObject; AMisses: TTyTermMisses; ACheckBounds: Boolean;
  var ABoundChecks, AWantBoundChecks: Int64; out AHeapGrowth: Int64): Int64;
var
  parser: TTyTerminalParser;
  rec: TTraceRec;
  regs: TObjectList;
  reg: TReg;
  handles: array of Integer;
  regArr, feed, trace: TJSONArray;
  item, spec: TJSONObject;
  k, n, times, t, h: Integer;
  data: TCpsArray;
  id, want, got, around: string;
  rawOsc: TRawOsc;
  rawDcs: TRawDcs;
  rawApc: TRawApc;
  heapBefore: PtrUInt;

  procedure DoParse(const AData: TCpsArray);
  begin
    parser.Parse(AData, Length(AData));
    if ACheckBounds then
    begin
      Inc(AWantBoundChecks);
      Inc(ABoundChecks);
      if parser.OscPayloadLength > TyTermParserPayloadLimit then
        AMisses.Add(id, 'bounds', '<= limit', IntToStr(parser.OscPayloadLength));
    end;
  end;

begin
  id := ACase.Strings['id'];
  heapBefore := GetFPCHeapStatus.CurrHeapUsed;
  parser := TTyTerminalParser.Create;
  rec := TTraceRec.Create(parser);
  regs := TObjectList.Create(True);
  handles := nil;
  try
    parser.SetPrintHandler(@rec.OnPrint);
    parser.SetExecuteHandlerFallback(@rec.OnExec);
    parser.SetCsiHandlerFallback(@rec.OnCsi);
    parser.SetEscHandlerFallback(@rec.OnEsc);
    parser.SetOscHandlerFallback(@rec.OnOsc);
    parser.SetDcsHandlerFallback(@rec.OnDcs);
    parser.SetApcHandlerFallback(@rec.OnApc);
    parser.SetErrorHandler(@rec.OnError);

    regArr := ACase.Arrays['register'];
    SetLength(handles, regArr.Count);
    for k := 0 to regArr.Count - 1 do
    begin
      item := regArr.Objects[k];
      reg := TReg.Create;
      reg.K := k;
      reg.Ret := item.Get('ret', False);
      reg.Rec := rec;
      regs.Add(reg);
      h := -1;
      if item.Find('csi') <> nil then
        h := parser.RegisterCsiHandler(FunctionIdOf(item.Objects['csi']), @reg.Csi)
      else if item.Find('esc') <> nil then
        h := parser.RegisterEscHandler(FunctionIdOf(item.Objects['esc']), @reg.Esc)
      else if item.Find('exec') <> nil then
        parser.SetExecuteHandler(item.Integers['exec'], @reg.Exec)
      else if item.Find('osc') <> nil then
      begin
        if item.Strings['kind'] = 'string' then
          h := parser.RegisterOscHandler(item.Integers['osc'], TTyTerminalOscStringHandler.Create(@reg.OscData))
        else
        begin
          rawOsc := TRawOsc.Create;
          rawOsc.K := k;
          rawOsc.Ret := reg.Ret;
          rawOsc.Rec := rec;
          h := parser.RegisterOscHandler(item.Integers['osc'], rawOsc);
        end;
      end
      else if item.Find('dcs') <> nil then
      begin
        if item.Strings['kind'] = 'string' then
          h := parser.RegisterDcsHandler(FunctionIdOf(item.Objects['dcs']), TTyTerminalDcsStringHandler.Create(@reg.DcsData))
        else
        begin
          rawDcs := TRawDcs.Create;
          rawDcs.K := k;
          rawDcs.Ret := reg.Ret;
          rawDcs.Rec := rec;
          h := parser.RegisterDcsHandler(FunctionIdOf(item.Objects['dcs']), rawDcs);
        end;
      end
      else if item.Find('apc') <> nil then
      begin
        if item.Strings['kind'] = 'string' then
          h := parser.RegisterApcHandler(FunctionIdOf(item.Objects['apc']), TTyTerminalApcStringHandler.Create(@reg.ApcData))
        else
        begin
          rawApc := TRawApc.Create;
          rawApc.K := k;
          rawApc.Ret := reg.Ret;
          rawApc.Rec := rec;
          h := parser.RegisterApcHandler(FunctionIdOf(item.Objects['apc']), rawApc);
        end;
      end;
      handles[k] := h;
    end;

    feed := ACase.Arrays['feed'];
    for k := 0 to feed.Count - 1 do
    begin
      item := feed.Objects[k];
      if item.Find('cp') <> nil then
        DoParse(TyTermJsonCps(item.Arrays['cp']))
      else if item.Find('fill') <> nil then
      begin
        data := FilledCps(Cardinal(item.Arrays['fill'].Int64s[0]), item.Arrays['fill'].Integers[1]);
        times := item.Get('times', 1);
        for t := 1 to times do
          DoParse(data);
        data := nil;
      end
      else if item.Find('repeat') <> nil then
      begin
        spec := item.Objects['repeat'];
        data := TyTermJsonCps(spec.Arrays['cp']);
        for t := 1 to spec.Integers['times'] do
          DoParse(data);
        data := nil;
      end
      else if item.Find('reset') <> nil then
        parser.Reset
      else if item.Find('unregister') <> nil then
        parser.Unregister(handles[item.Integers['unregister']]);
    end;
    AHeapGrowth := Int64(GetFPCHeapStatus.CurrHeapUsed) - Int64(heapBefore);

    trace := ACase.Arrays['trace'];
    Result := trace.Count + 2;
    n := trace.Count;
    if rec.Events.Count > n then
      n := rec.Events.Count;
    for k := 0 to n - 1 do
    begin
      if k < trace.Count then
      begin
        AMisses.AddCompared;
        want := JsonEventCanon(trace.Arrays[k]);
      end
      else
        want := '(none)';
      if k < rec.Events.Count then
        got := rec.Events[k]
      else
        got := '(none)';
      if want <> got then
      begin
        around := '';
        for t := k - 2 to k + 2 do
          if (t >= 0) and (t < rec.Events.Count) and (t <> k) then
            around := around + Format(' [#%d %s]', [t, rec.Events[t]]);
        AMisses.Add(id, Format('event #%d', [k]), want, got + '; got around:' + around);
        Break;       { one miss per case: the rest is shifted anyway }
      end;
    end;
    AMisses.AddCompared(2);
    if ACase.Integers['finalState'] <> Ord(parser.CurrentState) then
      AMisses.Add(id, 'finalState', IntToStr(ACase.Integers['finalState']), IntToStr(Ord(parser.CurrentState)));
    if ACase.Int64s['finalJoinState'] <> Int64(parser.PrecedingJoinState) then
      AMisses.Add(id, 'finalJoinState', IntToStr(ACase.Int64s['finalJoinState']), IntToStr(parser.PrecedingJoinState));
  finally
    parser.Free;
    rec.Free;
    regs.Free;
  end;
end;

{ ---- TTyTerminalParserOracleTests ---------------------------------------------- }

procedure TTyTerminalParserOracleTests.TestFixturesComeFromThePinnedUpstream;
const
  Kinds: array[0..2] of string = ('parser-table', 'parser-utf8', 'parser-trace');
var
  m: TTyTermMisses;
  fx: TTyTermFixtures;
  i, k: Integer;
  commit: string;
begin
  m := TTyTermMisses.Create;
  commit := '';
  try
    for i := 0 to High(Kinds) do
    begin
      fx := TyTermLoadFixtures(Kinds[i], m);
      try
        for k := 0 to High(fx) do
        begin
          TyTermCheckUpstream(fx[k], Kinds[i], m);
          if commit = '' then
            commit := fx[k].Objects['upstream'].Strings['commit']
          else if fx[k].Objects['upstream'].Strings['commit'] <> commit then
            m.Add(Kinds[i], 'upstream.commit', commit, fx[k].Objects['upstream'].Strings['commit']);
        end;
      finally
        TyTermFreeFixtures(fx);
      end;
    end;
    AssertEquals(m.Text, 0, m.Count);
    AssertTrue('upstream checked', m.Compared >= 6);
  finally
    m.Free;
  end;
end;

procedure TTyTerminalParserOracleTests.TestTransitionTableMatchesUpstream;
var
  m: TTyTermMisses;
  fx: TTyTermFixtures;
  runs: TJSONArray;
  r, i, stop: Integer;
  v: Word;
begin
  m := TTyTermMisses.Create;
  try
    fx := TyTermLoadFixtures('parser-table', m);
    try
      runs := fx[0].Arrays['table'];
      r := 0;
      while r < runs.Count do
      begin
        if r + 2 < runs.Count then stop := runs.Integers[r + 2] else stop := TyTermTransitionCount;
        v := runs.Integers[r + 1];
        for i := runs.Integers[r] to stop - 1 do
        begin
          m.AddCompared;
          if TyTermTransition(i) <> v then
            m.Add('table', Format('[%d] state %d code $%.2x', [i, i shr 8, i and $FF]),
              '$' + IntToHex(v, 4), '$' + IntToHex(TyTermTransition(i), 4));
        end;
        Inc(r, 2);
      end;
    finally
      TyTermFreeFixtures(fx);
    end;
    AssertEquals(m.Text, 0, m.Count);
    AssertEquals('every entry compared', TyTermTransitionCount, m.Compared);
  finally
    m.Free;
  end;
end;

procedure TTyTerminalParserOracleTests.TestUtf8DecodeChunkByChunk;
var
  m: TTyTermMisses;
  fx: TTyTermFixtures;
  cases: TFPList;
  c: TJSONObject;
  chunks, outs, want: TJSONArray;
  dec: TTyUtf8Decoder;
  i, k, j, n: Integer;
  bytes: RawByteString;
  outArr: array of Cardinal;
  dummy: Byte;
  wantCompared: Int64;
begin
  m := TTyTermMisses.Create;
  wantCompared := 0;
  dummy := 0;
  try
    fx := TyTermLoadFixtures('parser-utf8', m);
    cases := TyTermAllCases(fx);
    try
      for i := 0 to cases.Count - 1 do
      begin
        c := TJSONObject(cases[i]);
        chunks := c.Arrays['chunks'];
        outs := c.Arrays['out'];
        dec := TTyUtf8Decoder.Create;
        try
          for k := 0 to chunks.Count - 1 do
          begin
            bytes := TyTermBase64Bytes(chunks.Strings[k]);
            outArr := nil;
            SetLength(outArr, Length(bytes) + 4);
            if Length(bytes) > 0 then
              n := dec.Decode(bytes[1], Length(bytes), outArr)
            else
              n := dec.Decode(dummy, 0, outArr);
            want := outs.Arrays[k];
            Inc(wantCompared, 1 + want.Count);
            m.AddCompared;
            if n <> want.Count then
            begin
              m.Add(c.Strings['id'], Format('chunk %d count', [k]), IntToStr(want.Count), IntToStr(n));
              m.AddCompared(want.Count);
              Continue;
            end;
            for j := 0 to n - 1 do
            begin
              m.AddCompared;
              if outArr[j] <> Cardinal(want.Int64s[j]) then
                m.Add(c.Strings['id'], Format('chunk %d cp %d', [k, j]), IntToHex(want.Int64s[j], 1), IntToHex(outArr[j], 1));
            end;
          end;
        finally
          dec.Free;
        end;
      end;
    finally
      cases.Free;
      TyTermFreeFixtures(fx);
    end;
    AssertEquals(m.Text, 0, m.Count);
    AssertTrue('something compared', wantCompared > 0);
    AssertEquals('every code point compared', wantCompared, m.Compared);
  finally
    m.Free;
  end;
end;

{ AWantCut: -1 = cases without "cut", 1 = only cases with it, 0 = either. }
function TTyTerminalParserOracleTests.RunTraces(const ASource: string; AWantCut: Integer;
  ALong: Boolean; AMisses: TTyTermMisses; out AWantCompared: Int64): Integer;
var
  fx: TTyTermFixtures;
  cases: TFPList;
  c: TJSONObject;
  i: Integer;
  checks, wantChecks, growth: Int64;
  isCut, bounds: Boolean;
begin
  Result := 0;
  AWantCompared := 0;
  checks := 0;
  wantChecks := 0;
  fx := TyTermLoadFixtures('parser-trace', AMisses);
  cases := TyTermAllCases(fx);
  try
    for i := 0 to cases.Count - 1 do
    begin
      c := TJSONObject(cases[i]);
      if c.Strings['source'] <> ASource then
        Continue;
      isCut := c.Find('cut') <> nil;
      if (AWantCut = -1) and isCut then Continue;
      if (AWantCut = 1) and not isCut then Continue;
      bounds := ALong and (Pos('long-osc', c.Strings['id']) = 1);
      Inc(AWantCompared, RunTraceCase(c, AMisses, bounds, checks, wantChecks, growth));
      Inc(Result);
      if ALong and (growth > 2 * 1024 * 1024) then
        AMisses.Add(c.Strings['id'], 'heap growth after the feed', '<= 2 MB', IntToStr(growth));
    end;
  finally
    cases.Free;
    TyTermFreeFixtures(fx);
  end;
  if ALong then
  begin
    AMisses.AddCompared(checks);
    Inc(AWantCompared, wantChecks);
    if wantChecks = 0 then
      AMisses.Add('long-osc-*', 'bound checks', '> 0', '0');
  end;
end;

procedure TTyTerminalParserOracleTests.TestHandTraces;
var
  m: TTyTermMisses;
  want: Int64;
  n: Integer;
begin
  m := TTyTermMisses.Create;
  try
    n := RunTraces('hand', -1, False, m, want);
    AssertEquals(m.Text, 0, m.Count);
    AssertTrue('cases read', n > 50);
    AssertEquals('comparisons', want, m.Compared);
  finally
    m.Free;
  end;
end;

procedure TTyTerminalParserOracleTests.TestEveryCutTraces;
var
  m: TTyTermMisses;
  want: Int64;
  n: Integer;
begin
  m := TTyTermMisses.Create;
  try
    n := RunTraces('hand', 1, False, m, want);
    AssertEquals(m.Text, 0, m.Count);
    AssertTrue('cases read', n > 50);
    AssertEquals('comparisons', want, m.Compared);
  finally
    m.Free;
  end;
end;

procedure TTyTerminalParserOracleTests.TestLongInputsStayBounded;
var
  m: TTyTermMisses;
  want: Int64;
  n: Integer;
begin
  m := TTyTermMisses.Create;
  try
    n := RunTraces('long', 0, True, m, want);
    AssertEquals(m.Text, 0, m.Count);
    AssertTrue('cases read', n >= 10);
    AssertEquals('comparisons', want, m.Compared);
  finally
    m.Free;
  end;
end;

procedure TTyTerminalParserOracleTests.TestFuzzTraces;
var
  m: TTyTermMisses;
  want: Int64;
  n: Integer;
begin
  m := TTyTermMisses.Create;
  try
    n := RunTraces('fuzz', 0, False, m, want);
    AssertEquals(m.Text, 0, m.Count);
    AssertEquals('cases read', 100, n);
    AssertEquals('comparisons', want, m.Compared);
  finally
    m.Free;
  end;
end;

{ ---- TTyTerminalParserTests ------------------------------------------------------ }

procedure TTyTerminalParserTests.TestParamsBuild;
var
  p: TTyTerminalParams;
  i: Integer;
  s: string;

  procedure Check(const AWhat, AWant: string; AWantLength: Integer);
  begin
    AssertEquals(AWhat, AWant, p.ToJson);
    AssertEquals(AWhat + ' length', AWantLength, p.Length);
  end;

begin
  p := TTyTerminalParams.Create;
  try
    p.AddParam(0);
    Check('AddParam(0)', '[0]', 1);
  finally
    p.Free;
  end;
  p := TTyTerminalParams.Create;
  try
    p.AddParam(1); p.AddSubParam(2); p.AddSubParam(3); p.AddParam(4);
    Check('sub params', '[1,[2,3],4]', 2);
  finally
    p.Free;
  end;
  p := TTyTerminalParams.Create;
  try
    p.AddSubParam(5);
    Check('sub param without a param', '[]', 0);
  finally
    p.Free;
  end;
  p := TTyTerminalParams.Create;
  try
    p.ResetZdm; p.AddDigit(1); p.AddDigit(2);
    Check('digits', '[12]', 1);
  finally
    p.Free;
  end;
  p := TTyTerminalParams.Create;
  try
    p.ResetZdm; p.AddSubParam(-1); p.AddDigit(7);
    Check('empty sub param then digit', '[0,[7]]', 1);
  finally
    p.Free;
  end;
  p := TTyTerminalParams.Create;
  try
    p.ResetZdm;
    for i := 1 to 22 do
      p.AddDigit(9);
    Check('22 nines clamp', '[2147483647]', 1);
  finally
    p.Free;
  end;
  p := TTyTerminalParams.Create;
  try
    for i := 1 to 33 do
      p.AddParam(1);
    s := '[1';
    for i := 2 to 32 do
      s := s + ',1';
    Check('33 params keep 32', s + ']', 32);
  finally
    p.Free;
  end;
  p := TTyTerminalParams.Create;
  try
    for i := 1 to 32 do
      p.AddParam(1);
    p.AddDigit(5);
    s := '[1';
    for i := 2 to 31 do
      s := s + ',1';
    Check('32nd param still takes digits', s + ',15]', 32);
  finally
    p.Free;
  end;
  p := TTyTerminalParams.Create;
  try
    for i := 1 to 33 do
      p.AddParam(1);
    p.AddDigit(5);
    s := '[1';
    for i := 2 to 32 do
      s := s + ',1';
    Check('digits after the rejected 33rd dropped', s + ']', 32);
  finally
    p.Free;
  end;
  p := TTyTerminalParams.Create;
  try
    p.AddParam(1);
    for i := 1 to 33 do
      p.AddSubParam(1);
    s := '[1,[1';
    for i := 2 to 32 do
      s := s + ',1';
    Check('33 sub params keep 32', s + ']]', 1);
  finally
    p.Free;
  end;
  p := TTyTerminalParams.Create;
  try
    p.AddParam(2147483647); p.AddParam(-1);
    Check('max and -1', '[2147483647,-1]', 2);
  finally
    p.Free;
  end;
end;

procedure TTyTerminalParserTests.TestParamsRejectsBadInput;
var
  p: TTyTerminalParams;
  raised: Boolean;
begin
  raised := False;
  try
    TTyTerminalParams.Create(32, 257).Free;
  except
    on EArgumentException do raised := True;
  end;
  AssertTrue('257 sub params', raised);
  p := TTyTerminalParams.Create;
  try
    raised := False;
    try
      p.AddParam(-2);
    except
      on EArgumentException do raised := True;
    end;
    AssertTrue('AddParam(-2)', raised);
    p.AddParam(1);
    raised := False;
    try
      p.AddSubParam(-2);
    except
      on EArgumentException do raised := True;
    end;
    AssertTrue('AddSubParam(-2)', raised);
  finally
    p.Free;
  end;
end;

type
  TDummy = class
    function Csi(AParams: TTyTerminalParams): Boolean;
    function Esc: Boolean;
  end;

function TDummy.Csi(AParams: TTyTerminalParams): Boolean;
begin
  Result := True;
end;

function TDummy.Esc: Boolean;
begin
  Result := True;
end;

var
  GFreed: Integer;

type
  TCountedOsc = class(TTyTerminalOscStringHandler)
    destructor Destroy; override;
  end;
  TCountedDcs = class(TTyTerminalDcsStringHandler)
    destructor Destroy; override;
  end;
  TCountedApc = class(TTyTerminalApcStringHandler)
    destructor Destroy; override;
  end;

destructor TCountedOsc.Destroy;
begin
  Inc(GFreed);
  inherited Destroy;
end;

destructor TCountedDcs.Destroy;
begin
  Inc(GFreed);
  inherited Destroy;
end;

destructor TCountedApc.Destroy;
begin
  Inc(GFreed);
  inherited Destroy;
end;

procedure TTyTerminalParserTests.TestIdentifierRules;
var
  p: TTyTerminalParser;
  d: TDummy;

  procedure Expect(const AWhat: string; AKind: Char; const APrefix, AInter: string; AFinal: Char; AOk: Boolean);
  var
    raised: Boolean;
    h: Integer;
  begin
    raised := False;
    h := 0;
    try
      case AKind of
        'c': h := p.RegisterCsiHandler(TyTerminalFunctionId(APrefix, AInter, AFinal), @d.Csi);
        'e': h := p.RegisterEscHandler(TyTerminalFunctionId(APrefix, AInter, AFinal), @d.Esc);
        'a': h := p.RegisterApcHandler(TyTerminalFunctionId(APrefix, AInter, AFinal), TTyTerminalApcStringHandler.Create(nil));
      end;
    except
      on EArgumentException do raised := True;
    end;
    if AOk then
    begin
      AssertFalse(AWhat + ' raised', raised);
      AssertTrue(AWhat + ' handle', h > 0);
    end
    else
      AssertTrue(AWhat + ' must raise', raised);
  end;

begin
  p := TTyTerminalParser.Create;
  d := TDummy.Create;
  try
    Expect('CSI m', 'c', '', '', 'm', True);
    Expect('CSI ?? prefix', 'c', '??', '', 'm', False);
    Expect('CSI ! prefix', 'c', '!', '', 'm', False);
    Expect('CSI three intermediates', 'c', '', '!!!', 'p', False);
    Expect('CSI intermediate 0', 'c', '', '0', 'p', False);
    Expect('CSI final 0', 'c', '', '', '0', False);
    Expect('ESC final 0', 'e', '', '', '0', True);
    Expect('CSI final DEL', 'c', '', '', #$7F, False);
    Expect('APC ignores the prefix', 'a', '?', '', 'G', True);
  finally
    p.Free;
    d.Free;
  end;
end;

procedure TTyTerminalParserTests.TestIdentToString;
var
  p: TTyTerminalParser;
begin
  p := TTyTerminalParser.Create;
  try
    AssertEquals('?$p', p.IdentToString($3F2470));
    AssertEquals('m', p.IdentToString(Ord('m')));
    AssertEquals('', p.IdentToString(0));
  finally
    p.Free;
  end;
end;

procedure TTyTerminalParserTests.TestUnregister;
var
  p: TTyTerminalParser;
  d: TDummy;
  h: Integer;
begin
  p := TTyTerminalParser.Create;
  d := TDummy.Create;
  try
    p.Unregister(9999);
    h := p.RegisterCsiHandler(TyTerminalFunctionId('', '', 'm'), @d.Csi);
    p.Unregister(h);
    p.Unregister(h);
    GFreed := 0;
    h := p.RegisterOscHandler(7, TCountedOsc.Create(nil));
    AssertEquals('not freed while registered', 0, GFreed);
    p.Unregister(h);
    AssertEquals('freed on unregister', 1, GFreed);
    p.Unregister(h);
    AssertEquals('second unregister is a no-op', 1, GFreed);
  finally
    p.Free;
    d.Free;
  end;
end;

procedure TTyTerminalParserTests.TestHandlersFreedWithTheParser;
var
  p: TTyTerminalParser;
begin
  GFreed := 0;
  p := TTyTerminalParser.Create;
  p.RegisterOscHandler(7, TCountedOsc.Create(nil));
  p.RegisterOscHandler(8, TCountedOsc.Create(nil));
  p.RegisterDcsHandler(TyTerminalFunctionId('', '$', 'q'), TCountedDcs.Create(nil));
  p.RegisterDcsHandler(TyTerminalFunctionId('', '', 'q'), TCountedDcs.Create(nil));
  p.RegisterApcHandler(TyTerminalFunctionId('', '', 'G'), TCountedApc.Create(nil));
  p.RegisterApcHandler(TyTerminalFunctionId('', '', 'G'), TCountedApc.Create(nil));
  AssertEquals(0, GFreed);
  p.Free;
  AssertEquals('all six freed', 6, GFreed);
end;

procedure TTyTerminalParserTests.TestCodepointsToUtf8;

  function HexOf(const S: string): string;
  var
    i: Integer;
  begin
    Result := '';
    for i := 1 to Length(S) do
      Result := Result + IntToHex(Ord(S[i]), 2) + ' ';
    Result := Trim(Result);
  end;

  procedure Check(const AWhat: string; const ACps: array of Cardinal; const AWantHex: string; AUnits: Integer);
  begin
    AssertEquals(AWhat + ' bytes', AWantHex, HexOf(TyTerminalCodepointsToUtf8(ACps, 0, Length(ACps))));
    AssertEquals(AWhat + ' UTF-16 length', AUnits, TyTerminalUtf16Length(ACps, 0, Length(ACps)));
  end;

begin
  Check('A', [$41], '41', 1);
  Check('e acute, zhong', [$E9, $4E2D], 'C3 A9 E4 B8 AD', 2);
  Check('grinning face', [$1F600], 'F0 9F 98 80', 2);
  Check('lone surrogate', [$D800], 'EF BF BD', 1);
  { counted 2 because it is above U+FFFF; upstream never sees such a code point }
  Check('beyond U+10FFFF', [$110000], 'EF BF BD', 2);
end;

procedure TTyTerminalParserTests.TestDecoderLeavesNothingBehindAfterClear;
var
  dec: TTyUtf8Decoder;
  outArr: array of Cardinal;
  b1: Byte;
  b3: array[0..2] of Byte;
  n: Integer;
begin
  dec := TTyUtf8Decoder.Create;
  try
    outArr := nil;
    SetLength(outArr, 8);
    b1 := $E4;
    AssertEquals('half a sequence', 0, dec.Decode(b1, 1, outArr));
    dec.Clear;
    b3[0] := $B8; b3[1] := $AD; b3[2] := $61;
    n := dec.Decode(b3, 3, outArr);
    AssertEquals('only the a', 1, n);
    AssertEquals('a', $61, outArr[0]);
  finally
    dec.Free;
  end;
end;

initialization
  RegisterTest(TTyTerminalParserOracleTests);
  RegisterTest(TTyTerminalParserTests);
end.
