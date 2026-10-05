unit test.terminal.hooks;
{$mode objfpc}{$H+}
{ The core's parser hooks (spec 19.6): Register*Handler / UnregisterHandler.

  TTyTerminalHookOracleTests hold them to xterm.js 6.0.0's terminal.parser
  (ParserApi.ts) through tests/fixtures/terminal-core-hooks.json
  (tools/terminal-oracle/hook-cases.js, cases/hooks.js): the same scripted handlers
  are registered, the same bytes written, and both the whole terminal state and the
  handlers' call log (tag, kind, params as JSON.stringify(toArray()), payload as
  base64 of UTF-8, the answer) must be equal -- then Reset and the same steps again on
  the same core (the handlers stay), against afterReset. The call log, the
  inside-actions and the tag map are the run's, as hook-cases.js keeps them.

  TTyTerminalHookTests are the parts upstream has no oracle for (P1-P6 of the phase 7
  plan). }

interface

uses
  Classes, SysUtils, fpcunit, testregistry, fpjson,
  tyControls.Terminal.Parser, tyControls.Terminal.Core, test.terminal.oracle;

type
  TTyTerminalHookOracleTests = class(TTestCase)
  published
    procedure TestTheFixtures;
  end;

  TTyTerminalHookTests = class(TTestCase)
  published
    procedure TestOnlyItsOwnHandlesAreUnregistered;          { P1 }
    procedure TestARegisteredOscNoLongerReachesOnOsc;        { P2 }
    procedure TestArgumentsAreChecked;                       { P3 }
    procedure TestOtherThreadsAreRefused;                    { P4 }
    procedure TestAHandlerRaising;                           { P5 }
    procedure TestBorrowedParamsCanBeCloned;                 { P6 }
  end;

implementation

uses
  Math, base64, tyControls.Terminal.Buffer;

{ ---- the scripted handlers ------------------------------------------------------------ }

type
  TScriptRun = class;

  TScripted = class
  public
    Run: TScriptRun;
    Tag, Kind: string;
    Returns: TJSONArray;                 { borrowed from the fixture }
    N: Integer;
    Returned: Boolean;
    procedure Before;
    function Log(const AParams: string; AHasParams: Boolean; const AData: string; AHasData: Boolean): Boolean;
    function Csi(AParams: TTyTerminalParams): Boolean;
    function Esc: Boolean;
    function Osc(const AData: string): Boolean;
    function Dcs(const AData: string; AParams: TTyTerminalParams): Boolean;
    function Apc(const AData: string): Boolean;
  end;

  { hook-cases.js's ctx: the calls, the actions and the tag map of the running run;
    Handlers owns every scripted handler of the case (both runs) }
  TScriptRun = class
  public
    Core: TTyTerminalCore;
    Calls: TJSONArray;
    Actions: TFPList;                    { TJSONObject, borrowed }
    Tags: TStringList;                   { tag -> handle (Objects) }
    Handlers: TFPList;
    constructor Create(ACore: TTyTerminalCore);
    destructor Destroy; override;
    procedure NewRun;
    function Register(ASpec: TJSONObject): Integer;
    procedure Dispose(const ATag: string);
    procedure DoAction(AAction: TJSONObject);
  end;

function IdOf(AObj: TJSONObject): TTyTerminalFunctionId;
var
  f: string;
begin
  f := AObj.Get('final', '');
  Result := TyTerminalFunctionId(AObj.Get('prefix', ''), AObj.Get('intermediates', ''), f[1]);
end;

procedure TScripted.Before;
var
  i: Integer;
  a: TJSONObject;
  todo: TFPList;
begin
  Returned := Returns.Booleans[Min(N, Returns.Count - 1)];
  Inc(N);
  { a copy of the list: an action may add to it (hook-cases.js: actions.slice()) }
  todo := TFPList.Create;
  try
    for i := 0 to Run.Actions.Count - 1 do
    begin
      a := TJSONObject(Run.Actions[i]);
      if (a.Strings['tag'] = Tag) and (a.Integers['onCall'] = N) then
        todo.Add(a);
    end;
    for i := 0 to todo.Count - 1 do
      Run.DoAction(TJSONObject(todo[i]));
  finally
    todo.Free;
  end;
end;

function TScripted.Log(const AParams: string; AHasParams: Boolean; const AData: string; AHasData: Boolean): Boolean;
var
  o: TJSONObject;
begin
  o := TJSONObject.Create;
  o.Add('tag', Tag);
  o.Add('kind', Kind);
  if AHasParams then o.Add('params', AParams) else o.Add('params', TJSONNull.Create);
  if AHasData then o.Add('data', EncodeStringBase64(AData)) else o.Add('data', TJSONNull.Create);
  o.Add('returned', Returned);
  Run.Calls.Add(o);
  Result := Returned;
end;

function TScripted.Csi(AParams: TTyTerminalParams): Boolean;
var
  p: string;
begin
  p := AParams.ToJson;
  Before;
  Result := Log(p, True, '', False);
end;

function TScripted.Esc: Boolean;
begin
  Before;
  Result := Log('', False, '', False);
end;

function TScripted.Osc(const AData: string): Boolean;
begin
  Before;
  Result := Log('', False, AData, True);
end;

function TScripted.Dcs(const AData: string; AParams: TTyTerminalParams): Boolean;
var
  p: string;
begin
  p := AParams.ToJson;
  Before;
  Result := Log(p, True, AData, True);
end;

function TScripted.Apc(const AData: string): Boolean;
begin
  Before;
  Result := Log('', False, AData, True);
end;

constructor TScriptRun.Create(ACore: TTyTerminalCore);
begin
  inherited Create;
  Core := ACore;
  Calls := TJSONArray.Create;
  Actions := TFPList.Create;
  Tags := TStringList.Create;
  Handlers := TFPList.Create;
end;

destructor TScriptRun.Destroy;
var
  i: Integer;
begin
  for i := 0 to Handlers.Count - 1 do
    TObject(Handlers[i]).Free;
  Handlers.Free;
  Tags.Free;
  Actions.Free;
  Calls.Free;
  inherited Destroy;
end;

procedure TScriptRun.NewRun;
begin
  Calls.Clear;
  Actions.Clear;
  Tags.Clear;
end;

function TScriptRun.Register(ASpec: TJSONObject): Integer;
var
  h: TScripted;
  k: Integer;
begin
  h := TScripted.Create;
  Handlers.Add(h);
  h.Run := Self;
  h.Tag := ASpec.Strings['tag'];
  h.Kind := ASpec.Strings['kind'];
  h.Returns := ASpec.Arrays['returns'];
  if h.Kind = 'csi' then
    Result := Core.RegisterCsiHandler(IdOf(ASpec.Objects['id']), @h.Csi)
  else if h.Kind = 'esc' then
    Result := Core.RegisterEscHandler(IdOf(ASpec.Objects['id']), @h.Esc)
  else if h.Kind = 'osc' then
    Result := Core.RegisterOscHandler(ASpec.Integers['ident'], @h.Osc)
  else if h.Kind = 'dcs' then
    Result := Core.RegisterDcsHandler(IdOf(ASpec.Objects['id']), @h.Dcs)
  else
    Result := Core.RegisterApcHandler(IdOf(ASpec.Objects['id']), @h.Apc);
  k := Tags.IndexOf(h.Tag);
  if k < 0 then
    Tags.AddObject(h.Tag, TObject(PtrInt(Result)))
  else
    Tags.Objects[k] := TObject(PtrInt(Result));
end;

procedure TScriptRun.Dispose(const ATag: string);
begin
  Core.UnregisterHandler(Integer(PtrInt(Tags.Objects[Tags.IndexOf(ATag)])));
end;

procedure TScriptRun.DoAction(AAction: TJSONObject);
begin
  if AAction.Find('register') <> nil then
    Register(AAction.Objects['register'])
  else
    Dispose(AAction.Strings['dispose']);
end;

{ one run of the steps on the harness's core; refused registrations are checked here }
procedure RunSteps(AHarness: TTyTermHarness; ARun: TScriptRun; ASteps: TJSONArray; const AId: string;
  AMisses: TTyTermMisses);
var
  k: Integer;
  s, r: TJSONObject;
  want, got: string;
begin
  ARun.NewRun;
  for k := 0 to ASteps.Count - 1 do
  begin
    s := ASteps.Objects[k];
    if s.Find('write') <> nil then
      AHarness.Core.WriteSync(TyTermBase64Bytes(s.Strings['write']))
    else if s.Find('register') <> nil then
    begin
      r := s.Objects['register'];
      if r.Find('error') = nil then
        raise Exception.Create(AId + ': a register step without "error"');
      if r.Items[r.IndexOfName('error')].JSONType = jtNull then want := '' else want := r.Strings['error'];
      got := '';
      try
        ARun.Register(r);
      except
        on E: EArgumentException do got := E.Message;
      end;
      AMisses.AddCompared;
      if got <> want then
        AMisses.Add(AId, 'register ' + r.Strings['tag'], '"' + want + '"', '"' + got + '"');
    end
    else if s.Find('dispose') <> nil then
      ARun.Dispose(s.Strings['dispose'])
    else if s.Find('inside') <> nil then
      ARun.Actions.Add(s.Objects['inside'])
    else if s.Find('reset') <> nil then
      AHarness.Core.Reset
    else
      raise Exception.Create('unknown step ' + s.AsJSON);
  end;
end;

procedure CompareCalls(AWant: TJSONData; ARun: TScriptRun; const AId: string; AMisses: TTyTermMisses);
begin
  TyTermCompareJson(AWant, ARun.Calls, AId, 'calls', AMisses);
end;

{ ---- TTyTerminalHookOracleTests ---------------------------------------------------------- }

procedure TTyTerminalHookOracleTests.TestTheFixtures;
var
  m: TTyTermMisses;
  fx: TTyTermFixtures;
  cases: TFPList;
  c: TJSONObject;
  h: TTyTermHarness;
  scr: TScriptRun;
  after: TJSONData;
  i, calls: Integer;
  id: string;
begin
  m := TTyTermMisses.Create;
  cases := nil;
  calls := 0;
  try
    fx := TyTermLoadFixtures('core-hooks', m);
    try
      TyTermCheckUpstream(fx[0], 'core-hooks', m);
      cases := TyTermAllCases(fx);
      for i := 0 to cases.Count - 1 do
      begin
        c := TJSONObject(cases[i]);
        id := c.Strings['id'];
        h := TTyTermHarness.Create(c, fx[0].Arrays['palette']);
        scr := TScriptRun.Create(h.Core);
        try
          RunSteps(h, scr, c.Arrays['steps'], id, m);
          TyTermCompareState(h, c.Objects['expect'], id, False, m);
          CompareCalls(c.Objects['expect'].Arrays['calls'], scr, id, m);
          Inc(calls, scr.Calls.Count);
          { the same core again after Reset: the handlers of the first scr stay }
          h.Core.Reset;
          h.ClearRecord;
          RunSteps(h, scr, c.Arrays['steps'], id + ' after Reset', m);
          after := c.Find('afterReset');
          if (after = nil) or (after.JSONType = jtString) then
          begin
            TyTermCompareState(h, c.Objects['expect'], id + ' after Reset', False, m);
            CompareCalls(c.Objects['expect'].Arrays['calls'], scr, id + ' after Reset', m);
          end
          else
          begin
            TyTermCompareState(h, TJSONObject(after), id + ' after Reset', False, m);
            CompareCalls(TJSONObject(after).Arrays['calls'], scr, id + ' after Reset', m);
          end;
        finally
          { the core first: its parser still points at the handlers' methods }
          h.Free;
          scr.Free;
        end;
      end;
      WriteLn(Format('core-hooks: %d cases, %d calls, %d comparisons', [cases.Count, calls, m.Compared]));
      AssertEquals(m.Text, 0, m.Count);
      AssertTrue('cases read', cases.Count >= 20);
      AssertTrue('handlers were called', calls >= 30);
    finally
      cases.Free;
      TyTermFreeFixtures(fx);
    end;
  finally
    m.Free;
  end;
end;

{ ---- TTyTerminalHookTests ------------------------------------------------------------------- }

type
  THookRig = class
  public
    Core: TTyTerminalCore;
    Calls: Integer;
    Answer: Boolean;
    Raise_: Boolean;
    Kept: TTyTerminalParams;
    OscSeen: TStringList;
    constructor Create;
    destructor Destroy; override;
    function Csi(AParams: TTyTerminalParams): Boolean;
    function Osc(const AData: string): Boolean;
    procedure OnOsc(Sender: TObject; AIdent: Integer; const AData: string);
    function Line: string;
  end;

constructor THookRig.Create;
begin
  inherited Create;
  Core := TTyTerminalCore.Create(20, 4);
  Core.OnOsc := @OnOsc;
  OscSeen := TStringList.Create;
end;

destructor THookRig.Destroy;
begin
  Core.Free;
  Kept.Free;
  OscSeen.Free;
  inherited Destroy;
end;

function THookRig.Csi(AParams: TTyTerminalParams): Boolean;
begin
  Inc(Calls);
  if Raise_ then
    raise Exception.Create('the handler raised');
  FreeAndNil(Kept);
  Kept := AParams.Clone;
  Result := Answer;
end;

function THookRig.Osc(const AData: string): Boolean;
begin
  Inc(Calls);
  Result := Answer;
end;

procedure THookRig.OnOsc(Sender: TObject; AIdent: Integer; const AData: string);
begin
  OscSeen.Add(IntToStr(AIdent) + ':' + AData);
end;

function THookRig.Line: string;
begin
  Result := Core.Buffer.Lines.Get(Core.Buffer.YBase).TranslateToString(True, 0, Core.Cols);
end;

function MId: TTyTerminalFunctionId;
begin
  Result := TyTerminalFunctionId('', '', 'm');
end;

{ P1. Mutation: UnregisterHandler going straight to the parser. }
procedure TTyTerminalHookTests.TestOnlyItsOwnHandlesAreUnregistered;
var
  r: THookRig;
  i, mine: Integer;
begin
  r := THookRig.Create;
  try
    mine := r.Core.RegisterCsiHandler(MId, @r.Csi);
    r.Answer := False;
    for i := 1 to 500 do
      if i <> mine then
        r.Core.UnregisterHandler(i);
    r.Core.WriteSync(#27'[31mX');
    AssertEquals('the core''s own SGR is still there', 1, r.Core.Buffer.Lines.Get(0).GetFg(0) and $FF);
    AssertTrue('red: an SGR colour', r.Core.Buffer.Lines.Get(0).GetFg(0) <> 0);
    AssertEquals('ours was called', 1, r.Calls);
    r.Core.UnregisterHandler(mine);
    r.Core.WriteSync(#27'[32mY');
    AssertEquals('ours is gone', 1, r.Calls);
  finally
    r.Free;
  end;
end;

{ P2. The documented behaviour (spec 7.4, 19.6): a registered OSC number no longer
  reaches OnOsc, even when the chain answers False; unregistered, it does again.
  Mutation: the wrapper calling OnOsc itself when the handler answers False. }
procedure TTyTerminalHookTests.TestARegisteredOscNoLongerReachesOnOsc;
var
  r: THookRig;
  h: Integer;
begin
  r := THookRig.Create;
  try
    r.Core.WriteSync(#27']7;file://a'#7);
    AssertEquals('OnOsc first', '7:file://a', r.OscSeen.CommaText);
    h := r.Core.RegisterOscHandler(7, @r.Osc);
    r.Answer := False;
    r.Core.WriteSync(#27']7;file://b'#7);
    AssertEquals('the handler was asked', 1, r.Calls);
    AssertEquals('not OnOsc any more', 1, r.OscSeen.Count);
    r.Core.UnregisterHandler(h);
    r.Core.WriteSync(#27']7;file://c'#7);
    AssertEquals('OnOsc again', 2, r.OscSeen.Count);
    AssertEquals('7:file://c', r.OscSeen[1]);
  finally
    r.Free;
  end;
end;

{ P3. Mutation: the nil check dropped. }
procedure TTyTerminalHookTests.TestArgumentsAreChecked;
var
  r: THookRig;
  cls: string;

  procedure Try_(AKind: Integer);
  begin
    cls := '(none)';
    try
      case AKind of
        0: r.Core.RegisterCsiHandler(MId, nil);
        1: r.Core.RegisterEscHandler(TyTerminalFunctionId('', '', '7'), nil);
        2: r.Core.RegisterOscHandler(1337, nil);
        3: r.Core.RegisterDcsHandler(TyTerminalFunctionId('', '$', 'q'), nil);
        4: r.Core.RegisterApcHandler(TyTerminalFunctionId('', '', 'G'), nil);
        5: r.Core.RegisterOscHandler(-1, @r.Osc);
      else
        r.Core.RegisterCsiHandler(TyTerminalFunctionId('!', '', 'm'), @r.Csi);
      end;
    except
      on E: Exception do cls := E.ClassName;
    end;
  end;

var
  k: Integer;
begin
  r := THookRig.Create;
  try
    for k := 0 to 4 do
    begin
      Try_(k);
      AssertEquals(Format('nil handler %d', [k]), 'EArgumentNilException', cls);
    end;
    Try_(5);
    AssertEquals('OSC -1', 'EArgumentOutOfRangeException', cls);
    Try_(6);
    AssertEquals('prefix !', 'EArgumentException', cls);
    r.Core.WriteSync(#27'[31mX'#27'[1mY');
    AssertEquals('nothing registered by the refused calls', 0, r.Calls);
  finally
    r.Free;
  end;
end;

type
  TRegisterThread = class(TThread)
  public
    Rig: THookRig;
    Outcome: string;
    procedure Execute; override;
  end;

procedure TRegisterThread.Execute;
begin
  Outcome := '(none)';
  try
    Rig.Core.RegisterCsiHandler(MId, @Rig.Csi);
  except
    on E: Exception do Outcome := E.ClassName;
  end;
end;

{ P4. Mutation: CheckThread dropped. }
procedure TTyTerminalHookTests.TestOtherThreadsAreRefused;
var
  r: THookRig;
  t: TRegisterThread;
begin
  r := THookRig.Create;
  t := TRegisterThread.Create(True);
  try
    t.Rig := r;
    t.FreeOnTerminate := False;
    t.Start;
    t.WaitFor;
    AssertEquals('refused', 'EInvalidOperation', t.Outcome);
    r.Core.WriteSync(#27'[31mX');
    AssertEquals('not registered', 0, r.Calls);
  finally
    t.Free;
    r.Free;
  end;
end;

{ P5. The wrapper does not swallow a handler's exception; the queue's rule (spec 3.1)
  holds, and the handler stays registered. }
procedure TTyTerminalHookTests.TestAHandlerRaising;
var
  r: THookRig;
  raised: Boolean;
begin
  r := THookRig.Create;
  try
    r.Core.RegisterCsiHandler(MId, @r.Csi);
    r.Raise_ := True;
    raised := False;
    try
      r.Core.WriteSync(#27'[31mX');
    except
      raised := True;
    end;
    AssertTrue('WriteSync raised', raised);
    r.Raise_ := False;
    r.Answer := True;
    r.Core.WriteSync('ab'#27'[32m');
    AssertEquals('still registered: called again', 2, r.Calls);
    AssertTrue('the next chunk parsed', Pos('ab', r.Line) > 0);
  finally
    r.Free;
  end;
end;

{ P6. The params are the parser's, borrowed: a Clone taken in the call keeps them. }
procedure TTyTerminalHookTests.TestBorrowedParamsCanBeCloned;
var
  r: THookRig;
begin
  r := THookRig.Create;
  try
    r.Core.RegisterCsiHandler(MId, @r.Csi);
    r.Answer := True;
    r.Core.WriteSync(#27'[38:2::10:20:30;4m'#27'[1;2;3H');
    AssertEquals('the clone after the call', '[38,[2,-1,10,20,30],4]', r.Kept.ToJson);
  finally
    r.Free;
  end;
end;

initialization
  RegisterTest(TTyTerminalHookOracleTests);
  RegisterTest(TTyTerminalHookTests);
end.
