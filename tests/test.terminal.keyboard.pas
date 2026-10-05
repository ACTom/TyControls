unit test.terminal.keyboard;
{$mode objfpc}{$H+}
{ tyControls.Terminal.Keyboard -- held to xterm.js 6.0.0.

  TTyTerminalKeyboardOracleTests read the fixtures tools/terminal-oracle/
  keyboard-cases.js writes: the US layout table (the one source of it -- the Pascal
  table is compared with it row by row), evaluateKeyboardEvent over every layout key
  x 16 modifier sets x application cursor x three platform settings, the events LCL
  cannot make, _isThirdLevelShift (called on upstream's own prototype), and the two
  paste helpers. Each test asserts how many comparisons it made, against a number
  worked out from the Pascal side where one exists.

  TTyTerminalKeyboardTests are the same functions as a readable input / expected
  table, independent of the fixtures. }

interface

uses
  Classes, SysUtils, fpcunit, testregistry, fpjson, LCLType,
  tyControls.Terminal.Keyboard, test.terminal.oracle;

type
  TTyTerminalKeyboardOracleTests = class(TTestCase)
  published
    procedure TestFixturesComeFromThePinnedUpstream;
    procedure TestLayoutMatchesTheFixture;
    procedure TestEvaluateMatchesUpstream;
    procedure TestHandEventsMatchUpstream;
    procedure TestThirdLevelShiftMatchesUpstream;
    procedure TestPasteMatchesUpstream;
  end;

  TTyTerminalKeyboardTests = class(TTestCase)
  private
    function Enc(AKey: Word; AShift: TShiftState; AApp: Boolean; const APlatform: string): string;
    function KindOf(AKey: Word; AShift: TShiftState; const APlatform: string): TTyTerminalKeyResultKind;
    procedure Check(const AWhat: string; AKey: Word; AShift: TShiftState; AApp: Boolean;
      const APlatform, AWantHex: string);
  published
    procedure TestCursorKeys;
    procedure TestFunctionKeys;
    procedure TestEditingKeys;
    procedure TestPaging;
    procedure TestCtrlKeys;
    procedure TestAltKeys;
    procedure TestMacKeys;
    procedure TestPrintableKeysAndTheKeypad;
    procedure TestThirdLevelShiftTable;
    procedure TestPaste;
    procedure TestJsLength;
  end;

{ Bytes as upper-case hex, space separated (shared with the view's input tests). }
function TyTermHex(const S: RawByteString): string;

implementation

function TyTermHex(const S: RawByteString): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(S) do
  begin
    if i > 1 then Result := Result + ' ';
    Result := Result + IntToHex(Ord(S[i]), 2);
  end;
end;

function ShiftOfMods(AMods: Integer): TShiftState;
begin
  Result := [];
  if AMods and 1 <> 0 then Include(Result, ssShift);
  if AMods and 2 <> 0 then Include(Result, ssAlt);
  if AMods and 4 <> 0 then Include(Result, ssCtrl);
  if AMods and 8 <> 0 then Include(Result, ssMeta);
end;

function ModsText(AMods: Integer): string;
begin
  Result := '';
  if AMods and 1 <> 0 then Result := Result + 'shift ';
  if AMods and 2 <> 0 then Result := Result + 'alt ';
  if AMods and 4 <> 0 then Result := Result + 'ctrl ';
  if AMods and 8 <> 0 then Result := Result + 'meta ';
  Result := Trim(Result);
  if Result = '' then Result := 'none';
end;

function ResultText(AKind, ACancel: Integer; const AKey: RawByteString): string;
begin
  Result := Format('kind %d cancel %d [%s]', [AKind, ACancel, TyTermHex(AKey)]);
end;

function NullableB64(AData: TJSONData): RawByteString;
begin
  if (AData = nil) or (AData.JSONType = jtNull) then
    Result := ''
  else
    Result := TyTermBase64Bytes(AData.AsString);
end;

{ ---- TTyTerminalKeyboardOracleTests ---------------------------------------------- }

procedure TTyTerminalKeyboardOracleTests.TestFixturesComeFromThePinnedUpstream;
const
  Kinds: array[0..1] of string = ('keyboard', 'paste');
var
  miss: TTyTermMisses;
  fx: TTyTermFixtures;
  kind: string;
  i, k: Integer;
begin
  miss := TTyTermMisses.Create;
  try
    for k := 0 to High(Kinds) do
    begin
      kind := Kinds[k];
      fx := TyTermLoadFixtures(kind, miss);
      try
        for i := 0 to High(fx) do
          TyTermCheckUpstream(fx[i], kind, miss);
        AssertEquals(kind + ' parts', 1, Length(fx));
      finally
        TyTermFreeFixtures(fx);
      end;
    end;
    AssertEquals(miss.Text, 0, miss.Count);
    AssertEquals('comparisons', 4, miss.Compared);
  finally
    miss.Free;
  end;
end;

procedure TTyTerminalKeyboardOracleTests.TestLayoutMatchesTheFixture;
const
  Outside: array[0..4] of Word = (0, 1, 150, 200, 255);
var
  miss: TTyTermMisses;
  fx: TTyTermFixtures;
  layout, row: TJSONArray;
  i: Integer;
  vk: Word;
  ev: TTyTerminalKeyEvent;
  id: string;
begin
  miss := TTyTermMisses.Create;
  try
    fx := TyTermLoadFixtures('keyboard', miss);
    try
      AssertEquals(miss.Text, 0, miss.Count);
      layout := fx[0].Arrays['layout'];
      for i := 0 to layout.Count - 1 do
      begin
        row := layout.Arrays[i];
        vk := row.Integers[0];
        id := 'vk ' + IntToStr(vk);
        ev := TyTerminalKeyEventFromLCL(vk, []);
        miss.AddCompared;
        if ev.Key <> row.Strings[1] then miss.Add(id, 'key', row.Strings[1], ev.Key);
        miss.AddCompared;
        if ev.Code <> row.Strings[3] then miss.Add(id, 'code', row.Strings[3], ev.Code);
        ev := TyTerminalKeyEventFromLCL(vk, [ssShift]);
        miss.AddCompared;
        if ev.Key <> row.Strings[2] then miss.Add(id, 'shifted key', row.Strings[2], ev.Key);
      end;
      { the two tables have the same rows: nothing the Pascal one has is missing there }
      miss.AddCompared;
      if TyTerminalLayoutCount <> layout.Count then
        miss.Add('layout', 'rows', IntToStr(layout.Count), IntToStr(TyTerminalLayoutCount));
      for i := 0 to High(Outside) do
      begin
        ev := TyTerminalKeyEventFromLCL(Outside[i], []);
        miss.AddCompared;
        if (ev.Key <> 'Unidentified') or (ev.Code <> '') then
          miss.Add('vk ' + IntToStr(Outside[i]), 'outside the table', 'Unidentified / ''''', ev.Key + ' / ' + ev.Code);
      end;
      AssertEquals(miss.Text, 0, miss.Count);
      AssertTrue('rows read', layout.Count > 90);
      AssertEquals('comparisons', Int64(layout.Count) * 3 + 1 + Length(Outside), miss.Compared);
    finally
      TyTermFreeFixtures(fx);
    end;
  finally
    miss.Free;
  end;
end;

procedure TTyTerminalKeyboardOracleTests.TestEvaluateMatchesUpstream;
const
  PlatformNames: array[0..2] of string = ('win', 'mac', 'macMeta');
var
  miss: TTyTermMisses;
  fx: TTyTermFixtures;
  combos, c: TJSONArray;
  i, vk, mods, app, plat: Integer;
  ev: TTyTerminalKeyEvent;
  r: TTyTerminalKeyResult;
  want, got: string;
begin
  miss := TTyTermMisses.Create;
  try
    fx := TyTermLoadFixtures('keyboard', miss);
    try
      AssertEquals(miss.Text, 0, miss.Count);
      combos := fx[0].Arrays['combos'];
      for i := 0 to combos.Count - 1 do
      begin
        c := combos.Arrays[i];
        vk := c.Integers[0];
        mods := c.Integers[1];
        app := c.Integers[2];
        plat := c.Integers[3];
        ev := TyTerminalKeyEventFromLCL(vk, ShiftOfMods(mods));
        r := TyTerminalEvaluateKey(ev, app = 1, plat > 0, plat = 2);
        want := ResultText(c.Integers[4], c.Integers[5], NullableB64(c.Items[6]));
        got := ResultText(Ord(r.Kind), Ord(r.Cancel), r.Key);
        miss.AddCompared;
        if want <> got then
          miss.Add(Format('vk=%d(%s) mods=%s app=%d %s', [vk, ev.Key, ModsText(mods), app, PlatformNames[plat]]),
            'result', want, got);
      end;
      AssertEquals(miss.Text, 0, miss.Count);
      AssertTrue('combos read', combos.Count > 0);
      AssertEquals('comparisons = layout x 16 x 2 x 3', Int64(TyTerminalLayoutCount) * 16 * 2 * 3, miss.Compared);
    finally
      TyTermFreeFixtures(fx);
    end;
  finally
    miss.Free;
  end;
end;

procedure TTyTerminalKeyboardOracleTests.TestHandEventsMatchUpstream;
var
  miss: TTyTermMisses;
  fx: TTyTermFixtures;
  hand: TJSONArray;
  h, e: TJSONObject;
  i: Integer;
  ev: TTyTerminalKeyEvent;
  r: TTyTerminalKeyResult;
  want, got: string;
begin
  miss := TTyTermMisses.Create;
  try
    fx := TyTermLoadFixtures('keyboard', miss);
    try
      AssertEquals(miss.Text, 0, miss.Count);
      hand := fx[0].Arrays['hand'];
      for i := 0 to hand.Count - 1 do
      begin
        h := hand.Objects[i];
        e := h.Objects['ev'];
        ev := Default(TTyTerminalKeyEvent);
        ev.KeyCode := e.Integers['keyCode'];
        ev.Key := e.Strings['key'];
        ev.Code := e.Strings['code'];
        ev.Shift := e.Booleans['shift'];
        ev.Alt := e.Booleans['alt'];
        ev.Ctrl := e.Booleans['ctrl'];
        ev.Meta := e.Booleans['meta'];
        r := TyTerminalEvaluateKey(ev, h.Booleans['app'], h.Booleans['isMac'], h.Booleans['optMeta']);
        want := ResultText(h.Integers['type'], Ord(h.Booleans['cancel']), NullableB64(h.Find('key')));
        got := ResultText(Ord(r.Kind), Ord(r.Cancel), r.Key);
        miss.AddCompared;
        if want <> got then miss.Add(h.Strings['id'], 'result', want, got);
      end;
      AssertEquals(miss.Text, 0, miss.Count);
      AssertTrue('hand events read', hand.Count >= 100);
      AssertEquals('comparisons', hand.Count, miss.Compared);
    finally
      TyTermFreeFixtures(fx);
    end;
  finally
    miss.Free;
  end;
end;

procedure TTyTerminalKeyboardOracleTests.TestThirdLevelShiftMatchesUpstream;
var
  miss: TTyTermMisses;
  fx: TTyTermFixtures;
  third, t: TJSONArray;
  i, withoutAltGraph: Integer;
  sh: TShiftState;
  ev: TTyTerminalKeyEvent;
  got: Boolean;
begin
  { upstream's _isThirdLevelShift itself, called on CoreBrowserTerminal's prototype in
    node (keyboard-cases.js) }
  miss := TTyTermMisses.Create;
  try
    fx := TyTermLoadFixtures('keyboard', miss);
    try
      AssertEquals(miss.Text, 0, miss.Count);
      AssertFalse('the third-level cases are in the fixture', fx[0].Find('third') = nil);
      third := fx[0].Arrays['third'];
      withoutAltGraph := 0;
      for i := 0 to third.Count - 1 do
      begin
        t := third.Arrays[i];
        sh := ShiftOfMods(t.Integers[1]);
        if t.Integers[2] = 1 then Include(sh, ssAltGr) else Inc(withoutAltGraph);
        ev := TyTerminalKeyEventFromLCL(t.Integers[0], sh);
        got := TyTerminalIsThirdLevelShift(ev, t.Integers[3] = 1, t.Integers[4] = 1, t.Integers[5] = 1, t.Integers[6] = 1);
        miss.AddCompared;
        if Ord(got) <> t.Integers[7] then
          miss.Add(Format('vk=%d mods=%s altGraph=%d mac=%d windows=%d optMeta=%d keypress=%d',
            [t.Integers[0], ModsText(t.Integers[1]), t.Integers[2], t.Integers[3], t.Integers[4], t.Integers[5], t.Integers[6]]),
            'third level', IntToStr(t.Integers[7]), IntToStr(Ord(got)));
      end;
      AssertEquals(miss.Text, 0, miss.Count);
      AssertEquals('comparisons', third.Count, miss.Compared);
      { every layout key x 8 meta-less modifier sets x 3 platforms x optMeta x keypress,
        plus the AltGraph extras }
      AssertEquals('rows without AltGraph', TyTerminalLayoutCount * 8 * 12, withoutAltGraph);
      AssertTrue('AltGraph rows', third.Count > withoutAltGraph);
    finally
      TyTermFreeFixtures(fx);
    end;
  finally
    miss.Free;
  end;
end;

procedure TTyTerminalKeyboardOracleTests.TestPasteMatchesUpstream;
var
  miss: TTyTermMisses;
  fx: TTyTermFixtures;
  cases, c: TJSONArray;
  i: Integer;
  txt: RawByteString;
  want, got: RawByteString;
begin
  miss := TTyTermMisses.Create;
  try
    fx := TyTermLoadFixtures('paste', miss);
    try
      AssertEquals(miss.Text, 0, miss.Count);
      cases := fx[0].Arrays['cases'];
      for i := 0 to cases.Count - 1 do
      begin
        c := cases.Arrays[i];
        txt := TyTermBase64Bytes(c.Strings[0]);
        want := TyTermBase64Bytes(c.Strings[2]);
        got := TyTerminalPrepareTextForPaste(txt, c.Integers[1] = 1);
        miss.AddCompared;
        if want <> got then
          miss.Add('[' + TyTermHex(txt) + '] bracketed ' + IntToStr(c.Integers[1]), 'paste', TyTermHex(want), TyTermHex(got));
      end;
      AssertEquals(miss.Text, 0, miss.Count);
      AssertTrue('cases read', cases.Count >= 20);
      AssertEquals('comparisons', cases.Count, miss.Compared);
    finally
      TyTermFreeFixtures(fx);
    end;
  finally
    miss.Free;
  end;
end;

{ ---- TTyTerminalKeyboardTests ----------------------------------------------------- }

function TTyTerminalKeyboardTests.Enc(AKey: Word; AShift: TShiftState; AApp: Boolean;
  const APlatform: string): string;
var
  r: TTyTerminalKeyResult;
begin
  r := TyTerminalEvaluateKey(TyTerminalKeyEventFromLCL(AKey, AShift), AApp,
    APlatform <> 'win', APlatform = 'macMeta');
  Result := TyTermHex(r.Key);
end;

function TTyTerminalKeyboardTests.KindOf(AKey: Word; AShift: TShiftState; const APlatform: string): TTyTerminalKeyResultKind;
begin
  Result := TyTerminalEvaluateKey(TyTerminalKeyEventFromLCL(AKey, AShift), False,
    APlatform <> 'win', APlatform = 'macMeta').Kind;
end;

procedure TTyTerminalKeyboardTests.Check(const AWhat: string; AKey: Word; AShift: TShiftState;
  AApp: Boolean; const APlatform, AWantHex: string);
begin
  AssertEquals(AWhat, AWantHex, Enc(AKey, AShift, AApp, APlatform));
end;

procedure TTyTerminalKeyboardTests.TestCursorKeys;
begin
  Check('Up', VK_UP, [], False, 'win', '1B 5B 41');
  Check('Up, application cursor', VK_UP, [], True, 'win', '1B 4F 41');
  Check('Shift+Up ignores application cursor', VK_UP, [ssShift], True, 'win', '1B 5B 31 3B 32 41');
  Check('Ctrl+Left', VK_LEFT, [ssCtrl], False, 'win', '1B 5B 31 3B 35 44');
  Check('Meta+Left sends nothing', VK_LEFT, [ssMeta], False, 'mac', '');
  Check('Home, application cursor', VK_HOME, [], True, 'win', '1B 4F 48');
  Check('End, application cursor', VK_END, [], True, 'win', '1B 4F 46');
end;

procedure TTyTerminalKeyboardTests.TestFunctionKeys;
begin
  Check('F1', VK_F1, [], False, 'win', '1B 4F 50');
  Check('Shift+F1', VK_F1, [ssShift], False, 'win', '1B 5B 31 3B 32 50');
  Check('F5', VK_F5, [], False, 'win', '1B 5B 31 35 7E');
  Check('Ctrl+F5', VK_F5, [ssCtrl], False, 'win', '1B 5B 31 35 3B 35 7E');
  Check('F11', VK_F11, [], False, 'win', '1B 5B 32 33 7E');
end;

procedure TTyTerminalKeyboardTests.TestEditingKeys;
var
  r: TTyTerminalKeyResult;
begin
  Check('Backspace', VK_BACK, [], False, 'win', '7F');
  Check('Ctrl+Backspace', VK_BACK, [ssCtrl], False, 'win', '08');
  Check('Alt+Backspace', VK_BACK, [ssAlt], False, 'win', '1B 7F');
  Check('Tab', VK_TAB, [], False, 'win', '09');
  r := TyTerminalEvaluateKey(TyTerminalKeyEventFromLCL(VK_TAB, []), False, False, False);
  AssertTrue('Tab cancels', r.Cancel);
  Check('Shift+Tab', VK_TAB, [ssShift], False, 'win', '1B 5B 5A');
  Check('Enter', VK_RETURN, [], False, 'win', '0D');
  Check('Alt+Enter', VK_RETURN, [ssAlt], False, 'win', '1B 0D');
  Check('Escape', VK_ESCAPE, [], False, 'win', '1B');
  Check('Alt+Escape', VK_ESCAPE, [ssAlt], False, 'win', '1B 1B');
  Check('Insert', VK_INSERT, [], False, 'win', '1B 5B 32 7E');
  Check('Shift+Insert is left for paste', VK_INSERT, [ssShift], False, 'win', '');
  Check('Ctrl+Insert is left for copy', VK_INSERT, [ssCtrl], False, 'win', '');
  Check('Delete', VK_DELETE, [], False, 'win', '1B 5B 33 7E');
  Check('Shift+Delete', VK_DELETE, [ssShift], False, 'win', '1B 5B 33 3B 32 7E');
end;

procedure TTyTerminalKeyboardTests.TestPaging;
begin
  AssertTrue('Shift+PgUp pages locally', KindOf(VK_PRIOR, [ssShift], 'win') = tkrPageUp);
  AssertEquals('Shift+PgUp sends nothing', '', Enc(VK_PRIOR, [ssShift], False, 'win'));
  AssertTrue('Shift+PgDn pages locally', KindOf(VK_NEXT, [ssShift], 'win') = tkrPageDown);
  Check('Ctrl+PgUp', VK_PRIOR, [ssCtrl], False, 'win', '1B 5B 35 3B 35 7E');
  Check('Alt+PgUp: only Ctrl adds the code', VK_PRIOR, [ssAlt], False, 'win', '1B 5B 35 7E');
  Check('PgDn', VK_NEXT, [], False, 'win', '1B 5B 36 7E');
end;

procedure TTyTerminalKeyboardTests.TestCtrlKeys;
begin
  Check('Ctrl+A', Ord('A'), [ssCtrl], False, 'win', '01');
  Check('Ctrl+Z', Ord('Z'), [ssCtrl], False, 'win', '1A');
  Check('Ctrl+Space', VK_SPACE, [ssCtrl], False, 'win', '00');
  Check('Ctrl+3', Ord('3'), [ssCtrl], False, 'win', '1B');
  Check('Ctrl+7', Ord('7'), [ssCtrl], False, 'win', '1F');
  Check('Ctrl+8', Ord('8'), [ssCtrl], False, 'win', '7F');
  Check('Ctrl+[', VK_OEM_4, [ssCtrl], False, 'win', '1B');
  Check('Ctrl+\', VK_OEM_5, [ssCtrl], False, 'win', '1C');
  Check('Ctrl+]', VK_OEM_6, [ssCtrl], False, 'win', '1D');
  Check('Ctrl+/', VK_OEM_2, [ssCtrl], False, 'win', '1F');
  Check('Ctrl+Shift+2', Ord('2'), [ssCtrl, ssShift], False, 'win', '00');
  Check('Ctrl+Shift+6', Ord('6'), [ssCtrl, ssShift], False, 'win', '1E');
  Check('Ctrl+Shift+-', VK_OEM_MINUS, [ssCtrl, ssShift], False, 'win', '1F');
  Check('Ctrl+Shift+C is left for copy', Ord('C'), [ssCtrl, ssShift], False, 'win', '');
  Check('Ctrl+Shift+V is left for paste', Ord('V'), [ssCtrl, ssShift], False, 'win', '');
end;

procedure TTyTerminalKeyboardTests.TestAltKeys;
begin
  Check('Alt+A', Ord('A'), [ssAlt], False, 'win', '1B 61');
  Check('Alt+Shift+A', Ord('A'), [ssAlt, ssShift], False, 'win', '1B 41');
  Check('Ctrl+Alt+A', Ord('A'), [ssCtrl, ssAlt], False, 'win', '1B 01');
  Check('Alt+2', Ord('2'), [ssAlt], False, 'win', '1B 32');
  Check('Alt+Shift+2', Ord('2'), [ssAlt, ssShift], False, 'win', '1B 40');
  Check('Alt+Space', VK_SPACE, [ssAlt], False, 'win', '1B 20');
  Check('Ctrl+Alt+Space', VK_SPACE, [ssCtrl, ssAlt], False, 'win', '1B 00');
end;

procedure TTyTerminalKeyboardTests.TestMacKeys;
begin
  Check('Option+A is a third-level key on macOS', Ord('A'), [ssAlt], False, 'mac', '');
  Check('Option+A with MacOptionIsMeta', Ord('A'), [ssAlt], False, 'macMeta', '1B 61');
  AssertTrue('Cmd+A is select all', KindOf(Ord('A'), [ssMeta], 'mac') = tkrSelectAll);
  AssertTrue('Meta+A is nothing off macOS', KindOf(Ord('A'), [ssMeta], 'win') = tkrSendKey);
end;

procedure TTyTerminalKeyboardTests.TestPrintableKeysAndTheKeypad;
begin
  Check('A', Ord('A'), [], False, 'win', '61');
  Check('Shift+A', Ord('A'), [ssShift], False, 'win', '41');
  Check('keypad 5, whatever the keypad mode', VK_NUMPAD5, [], False, 'win', '35');
  Check('keypad *', VK_MULTIPLY, [], False, 'win', '2A');
  Check('the input method key', TyVkImeProcess, [], False, 'win', '');
end;

procedure TTyTerminalKeyboardTests.TestThirdLevelShiftTable;

  procedure T3(const AWhat: string; AKey: Word; AShift: TShiftState; AMac, AWindows, AOptMeta,
    AKeyPress, AWant: Boolean);
  begin
    AssertEquals(AWhat, AWant, TyTerminalIsThirdLevelShift(TyTerminalKeyEventFromLCL(AKey, AShift),
      AMac, AWindows, AOptMeta, AKeyPress));
  end;

begin
  T3('Ctrl+Alt+Q on Windows', Ord('Q'), [ssCtrl, ssAlt], False, True, False, False, True);
  T3('Ctrl+Alt+Left on a keydown (key code <= 47)', VK_LEFT, [ssCtrl, ssAlt], False, True, False, False, False);
  T3('Ctrl+Alt+Left on a keypress', VK_LEFT, [ssCtrl, ssAlt], False, True, False, True, True);
  T3('Ctrl+Alt+Q on Linux: upstream only knows Windows'' Ctrl+Alt', Ord('Q'), [ssCtrl, ssAlt], False, False, False, False, False);
  T3('AltGraph+Q on Windows', Ord('Q'), [ssAltGr], False, True, False, False, True);
  T3('AltGraph+Q on Linux', Ord('Q'), [ssAltGr], False, False, False, False, False);
  T3('Option+Q on macOS', Ord('Q'), [ssAlt], True, False, False, False, True);
  T3('Option+Q on macOS with MacOptionIsMeta', Ord('Q'), [ssAlt], True, False, True, False, False);
  T3('Option+Ctrl+Q on macOS', Ord('Q'), [ssAlt, ssCtrl], True, False, False, False, False);
  T3('Meta+Ctrl+Alt+Q on Windows', Ord('Q'), [ssMeta, ssCtrl, ssAlt], False, True, False, False, False);
end;

procedure TTyTerminalKeyboardTests.TestPaste;
begin
  AssertEquals('line endings', '61 0D 62 0D 63', TyTermHex(TyTerminalPrepareTextForPaste('a'#13#10'b'#10'c', False)));
  AssertEquals('a lone CR stays', '61 0D 62', TyTermHex(TyTerminalPrepareTextForPaste('a'#13'b', False)));
  AssertEquals('bracketed, ESC made harmless',
    '1B 5B 32 30 30 7E 78 E2 90 9B 5B 32 30 31 7E 79 1B 5B 32 30 31 7E',
    TyTermHex(TyTerminalPrepareTextForPaste('x'#27'[201~y', True)));
  AssertEquals('empty, bracketed', '1B 5B 32 30 30 7E 1B 5B 32 30 31 7E', TyTermHex(TyTerminalPrepareTextForPaste('', True)));
end;

procedure TTyTerminalKeyboardTests.TestJsLength;
begin
  AssertEquals('ASCII', 3, TyTermJsLength('abc'));
  AssertEquals('e acute, two bytes', 1, TyTermJsLength(#$C3#$A9));
  AssertEquals('CJK, three bytes', 1, TyTermJsLength(#$E4#$B8#$AD));
  AssertEquals('an astral character is a surrogate pair', 2, TyTermJsLength(#$F0#$9F#$98#$80));
  AssertEquals('empty', 0, TyTermJsLength(''));
end;

initialization
  RegisterTest(TTyTerminalKeyboardOracleTests);
  RegisterTest(TTyTerminalKeyboardTests);
end.
