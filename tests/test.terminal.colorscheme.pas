unit test.terminal.colorscheme;
{$mode objfpc}{$H+}
{ tyControls.Terminal.ColorScheme(6 期):颜色串、\u 预解码、方案对象、读写 Windows Terminal
  的 JSON。纯逻辑,期望值是按 WT 的文档与源码(spec §11.1.2)手写的表。

  测试数据里的 JSON 反斜杠一律写成反引号、经 J() 换回:编辑工具会把源码里的反斜杠加 u 加
  四位十六进制当成转义吞掉,写成反引号就不经过它。 }

interface

uses
  Classes, SysUtils, TypInfo, Graphics, fpcunit, testregistry,
  fpjson, jsonparser, jsonscanner,
  tyControls.StrConsts, tyControls.Terminal.ColorScheme, test.terminal.oracle;

type
  TTyTerminalColorSchemeTests = class(TTestCase)
  private
    FChanges: Integer;
    procedure Counted(Sender: TObject);
    function NewCounted: TTyTerminalColorScheme;
    function LoadOk(ARow: Integer; const AText, AName: string): TTyTerminalColorScheme;
    procedure LoadFails(ARow: Integer; const AText, AName, AFmt, AKey: string; const AAlsoIn: string);
  published
    { Task 1:颜色串、字节序、键名、预解码 }
    procedure TestParseSchemeColor;
    procedure TestSchemeColorText;
    procedure TestTColorAndRgbConvert;
    procedure TestWtKeys;
    procedure TestDecodeEscapes;
    procedure TestDecodedTextParses;
    { Task 2:方案对象 }
    procedure TestANewSchemeIsEmpty;
    procedure TestSchemeDefaultsMatchTheConstructor;
    procedure TestAChangeIsCountedOnce;
    procedure TestUpdatesAreBatched;
    procedure TestAssignClearAndEquals;
    procedure TestSlotRgb;
    procedure TestNamedAndIndexedAreOneSlot;
    { Task 3:读 WT }
    procedure TestReadTheDocsCampbell;
    procedure TestTheFixtureIsByteForByte;
    procedure TestListTheFixture;
    procedure TestReadByNameFromTheFixture;
    procedure TestReadRules;
    procedure TestReadFromFile;
    { Task 4:写 WT }
    procedure TestSaveCampbellExactly;
    procedure TestReadWriteReadTheFixture;
    procedure TestUnsetOptionalsAreNotWritten;
    procedure TestIncompleteSchemesAreNotWritten;
    procedure TestNamesRoundTrip;
    procedure TestWhatWtLacksIsNotWritten;
    procedure TestSystemColoursAreWrittenAsRgb;
    { Task 7:设计器导入的纯逻辑 }
    procedure TestTheImportPlan;
    { 6 期审查 }
    procedure TestDeepNestingIsRefused;
    procedure TestVeryDeepNestingDoesNotCrash;
    procedure TestAHugeFileIsNotRead;
    procedure TestNameListsNameEachOnce;
    procedure TestTheImportPlanSkipsBadColours;
    procedure TestChangedIsAChange;
  end;

{ 反引号换成反斜杠(见单元头) }
function J(const S: string): string;
{ WT 文档里 Campbell 的示例(单个对象) }
function TyTermDocCampbell: string;
{ 夹具 terminal-wt-defaults.json 的原样字节 }
function TyTermWtFixtureText: string;

implementation

const
  ZH = #$E4#$B8#$AD#$E6#$96#$87;          { 中文 }
  FFFD = #$EF#$BF#$BD;

function J(const S: string): string;
begin
  Result := StringReplace(S, '`', '\', [rfReplaceAll]);
end;

function Hex6(V: Cardinal): string;
begin
  Result := '$' + IntToHex(V, 6);
end;

procedure TTyTerminalColorSchemeTests.TestParseSchemeColor;

  procedure Ok(const AText: string; AWant: Cardinal);
  var
    rgb: Cardinal;
  begin
    AssertTrue('parses: "' + AText + '"', TyTermParseSchemeColor(AText, rgb));
    AssertEquals('"' + AText + '"', Hex6(AWant), Hex6(rgb));
  end;

  procedure Bad(const AText: string);
  var
    rgb: Cardinal;
  begin
    rgb := $123456;
    AssertFalse('refused: "' + AText + '"', TyTermParseSchemeColor(AText, rgb));
    AssertEquals('0 when refused: "' + AText + '"', Hex6(0), Hex6(rgb));
  end;

begin
  Ok('#C50F1F', $C50F1F);
  Ok('#c50f1f', $C50F1F);
  Ok('#0C0C0C', $0C0C0C);
  Ok('#fff', $FFFFFF);
  Ok('#1a2', $11AA22);
  Ok('#000', $000000);
  Bad('#C50F1FFF');
  Bad('#C50F1');
  Bad('C50F1F');
  Bad('#12345g');
  Bad(' #123456');
  Bad('#123456 ');
  Bad('');
  Bad('#');
  Bad('rgb(1,2,3)');
  Bad('red');
  Bad('#'#$EF#$BC#$A6#$EF#$BC#$A6#$EF#$BC#$A6);   { #ＦＦＦ(全角) }
end;

procedure TTyTerminalColorSchemeTests.TestSchemeColorText;
begin
  AssertEquals('#C50F1F', TyTermSchemeColorText($C50F1F));
  AssertEquals('#000000', TyTermSchemeColorText(0));
  AssertEquals('upper case', '#ABCDEF', TyTermSchemeColorText($ABCDEF));
end;

procedure TTyTerminalColorSchemeTests.TestTColorAndRgbConvert;
var
  rgb, sys: Cardinal;
begin
  AssertTrue('a plain colour', TyTermSchemeColorRgb(TColor($1F0FC5), rgb));
  AssertEquals('TColor $1F0FC5 is #C50F1F', Hex6($C50F1F), Hex6(rgb));
  AssertEquals('#C50F1F is TColor $1F0FC5', IntToHex($1F0FC5, 8),
    IntToHex(Cardinal(TyTermRgbToSchemeColor($C50F1F)), 8));
  AssertFalse('clNone is not set', TyTermSchemeColorRgb(clNone, rgb));
  AssertFalse('clDefault is not set', TyTermSchemeColorRgb(clDefault, rgb));
  AssertTrue('clBlack is set', TyTermSchemeColorRgb(clBlack, rgb));
  AssertEquals('clBlack', Hex6(0), Hex6(rgb));
  AssertTrue('clWindow is set', TyTermSchemeColorRgb(clWindow, rgb));
  sys := Cardinal(ColorToRGB(clWindow));
  AssertEquals('clWindow resolves through ColorToRGB',
    Hex6(((sys and $FF) shl 16) or (sys and $FF00) or ((sys shr 16) and $FF)), Hex6(rgb));
  AssertTrue('round trip', TyTermSchemeColorRgb(TyTermRgbToSchemeColor($C50F1F), rgb));
  AssertEquals('round trip', Hex6($C50F1F), Hex6(rgb));
end;

procedure TTyTerminalColorSchemeTests.TestWtKeys;
const
  Want: array[TTyTerminalSchemeSlot] of string = (
    'black', 'red', 'green', 'yellow', 'blue', 'purple', 'cyan', 'white',
    'brightBlack', 'brightRed', 'brightGreen', 'brightYellow',
    'brightBlue', 'brightPurple', 'brightCyan', 'brightWhite',
    'foreground', 'background', 'cursorColor', '', 'selectionBackground', '');
var
  s: TTyTerminalSchemeSlot;
begin
  for s := Low(s) to High(s) do
    AssertEquals(GetEnumName(TypeInfo(TTyTerminalSchemeSlot), Ord(s)), Want[s], TyTermWtSchemeKey(s));
  AssertEquals('the first sixteen are the ANSI numbers', 5, Ord(tssPurple));
  AssertEquals('the first sixteen are the ANSI numbers', 15, Ord(tssBrightWhite));
end;

type
  TDecodeCase = record
    Src, Want, WantN: string;
    Parses: Boolean;
  end;
  TDecodeCases = array of TDecodeCase;

function DecodeCases: TDecodeCases;

  procedure Add(const ASrc, AWant: string; AParses: Boolean; const AWantN: string);
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)].Src := J(ASrc);
    Result[High(Result)].Want := AWant;
    Result[High(Result)].Parses := AParses;
    Result[High(Result)].WantN := AWantN;
  end;

begin
  Result := nil;
  { 1 } Add('{"n":"`u4e2d`u6587"}', '{"n":"' + ZH + '"}', True, ZH);
  { 2 } Add('{"n":"a`u0022b"}', J('{"n":"a`"b"}'), True, 'a"b');
  { 3 } Add('{"n":"a`u005cb"}', J('{"n":"a``b"}'), True, J('a`b'));
  { 4 } Add('{"n":"a`u0001b"}', J('{"n":"a`u0001b"}'), True, 'a'#1'b');
  { 5 } Add('{"n":"``u4e2d"}', J('{"n":"``u4e2d"}'), True, J('`u4e2d'));
  { 6 } Add('{"n":"`ud83d`ude00"}', '{"n":"'#$F0#$9F#$98#$80'"}', True, #$F0#$9F#$98#$80);
  { 7 } Add('{"n":"`ud83d"}', '{"n":"' + FFFD + '"}', True, FFFD);
  { 7b} Add('{"n":"`ude00"}', '{"n":"' + FFFD + '"}', True, FFFD);
  { 8 } Add('{"n":"`u12"}', J('{"n":"`u12"}'), False, '');
  { 9 } Add('// it''s "x" `u4e2d'#10'{"n":"`u4e2d`u6587"}',
    J('// it''s "x" `u4e2d'#10) + '{"n":"' + ZH + '"}', True, ZH);
  { 10} Add('/* "x */ {"n":"`u00e9`u00e8"}', '/* "x */ {"n":"'#$C3#$A9#$C3#$A8'"}', True, #$C3#$A9#$C3#$A8);
  { 11} Add('{"u":"ms-appx:///P","n":"`u4e2d`u6587"}', '{"u":"ms-appx:///P","n":"' + ZH + '"}', True, ZH);
  { 12: WT defaults.json 第 16 行的形状 }
  Add('{"w":" /``()`"''-.,:;<>~?`u2502","n":"`u4e2d`u6587"}',
    J('{"w":" /``()`"''-.,:;<>~?') + #$E2#$94#$82 + '","n":"' + ZH + '"}', True, ZH);
end;

procedure TTyTerminalColorSchemeTests.TestDecodeEscapes;
var
  cases: TDecodeCases;
  i: Integer;
begin
  cases := DecodeCases;
  for i := 0 to High(cases) do
    AssertEquals('row ' + IntToStr(i + 1) + ': ' + cases[i].Src, cases[i].Want,
      TyTermJsonDecodeEscapes(cases[i].Src));
  AssertEquals('no escape: the text as it is', '{"a":1} // "x', TyTermJsonDecodeEscapes('{"a":1} // "x'));
end;

procedure TTyTerminalColorSchemeTests.TestDecodedTextParses;
var
  cases: TDecodeCases;
  i, parsed: Integer;
  p: TJSONParser;
  d: TJSONData;
begin
  cases := DecodeCases;
  parsed := 0;
  for i := 0 to High(cases) do
  begin
    if not cases[i].Parses then Continue;
    p := TJSONParser.Create(TyTermJsonDecodeEscapes(cases[i].Src), [joUTF8, joComments, joIgnoreTrailingComma]);
    try
      d := nil;
      try
        d := p.Parse;
      except
        on E: Exception do
          Fail('row ' + IntToStr(i + 1) + ' does not parse after decoding: ' + E.Message);
      end;
      try
        AssertEquals('row ' + IntToStr(i + 1) + ': n', cases[i].WantN, string(TJSONObject(d).Strings['n']));
        Inc(parsed);
      finally
        d.Free;
      end;
    finally
      p.Free;
    end;
  end;
  AssertEquals('rows parsed', 12, parsed);
end;

{ ---- Task 2:方案对象 ------------------------------------------------------------- }

const
  { published 属性名,按槽的顺序 }
  SlotProps: array[TTyTerminalSchemeSlot] of string = (
    'Black', 'Red', 'Green', 'Yellow', 'Blue', 'Purple', 'Cyan', 'White',
    'BrightBlack', 'BrightRed', 'BrightGreen', 'BrightYellow',
    'BrightBlue', 'BrightPurple', 'BrightCyan', 'BrightWhite',
    'Foreground', 'Background', 'CursorColor', 'CursorText',
    'SelectionBackground', 'SelectionInactiveBackground');

procedure TTyTerminalColorSchemeTests.Counted(Sender: TObject);
begin
  Inc(FChanges);
end;

function TTyTerminalColorSchemeTests.NewCounted: TTyTerminalColorScheme;
begin
  Result := TTyTerminalColorScheme.Create;
  Result.OnChange := @Counted;
  FChanges := 0;
end;

procedure TTyTerminalColorSchemeTests.TestANewSchemeIsEmpty;
var
  c: TTyTerminalColorScheme;
  s: TTyTerminalSchemeSlot;
begin
  c := TTyTerminalColorScheme.Create;
  try
    for s := Low(s) to High(s) do
      AssertEquals(SlotProps[s] + ' is clNone', IntToHex(clNone, 8), IntToHex(c.Colors[s], 8));
    AssertEquals('no name', '', c.Name);
    AssertTrue('empty', c.IsEmpty);
    AssertEquals('revision', 0, c.Revision);
    c.CursorText := clBlack;
    AssertFalse('black is a colour, not "unset"', c.IsEmpty);
    c.CursorText := clDefault;
    AssertTrue('clDefault counts as unset', c.IsEmpty);
  finally
    c.Free;
  end;
end;

procedure TTyTerminalColorSchemeTests.TestSchemeDefaultsMatchTheConstructor;
var
  c: TTyTerminalColorScheme;
  list: PPropList;
  n, i, checked: Integer;
  p: PPropInfo;
begin
  c := TTyTerminalColorScheme.Create;
  try
    n := GetPropList(c.ClassInfo, [tkInteger], nil);
    GetMem(list, n * SizeOf(Pointer));
    try
      GetPropList(c.ClassInfo, [tkInteger], list);
      checked := 0;
      for i := 0 to n - 1 do
      begin
        p := list^[i];
        AssertTrue(p^.Name + ' has a default', p^.Default <> Longint($80000000));
        AssertEquals('published default of ' + p^.Name + ' = what the constructor makes',
          Int64(p^.Default), GetOrdProp(c, p));
        Inc(checked);
      end;
      AssertEquals('colour properties checked', 22, checked);
    finally
      FreeMem(list);
    end;
  finally
    c.Free;
  end;
end;

procedure TTyTerminalColorSchemeTests.TestAChangeIsCountedOnce;
var
  c: TTyTerminalColorScheme;
begin
  c := NewCounted;
  try
    c.Red := TColor($1F0FC5);
    AssertEquals('one OnChange', 1, FChanges);
    AssertEquals('revision + 1', 1, c.Revision);
    c.Red := TColor($1F0FC5);
    AssertEquals('the same value again: no OnChange', 1, FChanges);
    AssertEquals('the same value again: revision kept', 1, c.Revision);
    c.Name := 'Mine';
    AssertEquals('the name is a change', 2, FChanges);
    c.Name := 'Mine';
    AssertEquals('the same name: no change', 2, FChanges);
  finally
    c.Free;
  end;
end;

procedure TTyTerminalColorSchemeTests.TestUpdatesAreBatched;
var
  c: TTyTerminalColorScheme;
begin
  c := NewCounted;
  try
    c.BeginUpdate;
    c.Red := TColor($1F0FC5);
    c.Green := TColor($0CA113);
    c.Blue := TColor($DA3700);
    AssertEquals('nothing inside the update', 0, FChanges);
    c.EndUpdate;
    AssertEquals('one OnChange for three colours', 1, FChanges);
    AssertEquals('one revision', 1, c.Revision);
    c.BeginUpdate;
    c.BeginUpdate;
    c.Red := TColor($000001);
    c.EndUpdate;
    AssertEquals('the inner end sends nothing', 1, FChanges);
    c.Green := TColor($000002);
    c.EndUpdate;
    AssertEquals('the outer end sends one', 2, FChanges);
    c.BeginUpdate;
    c.Red := TColor($000001);
    c.EndUpdate;
    AssertEquals('an update that changed nothing sends nothing', 2, FChanges);
  finally
    c.Free;
  end;
end;

procedure TTyTerminalColorSchemeTests.TestAssignClearAndEquals;
var
  a, b: TTyTerminalColorScheme;
begin
  a := TTyTerminalColorScheme.Create;
  b := NewCounted;
  try
    a.Name := 'Campbell';
    a.Red := TColor($1F0FC5);
    a.Background := TColor($0C0C0C);
    AssertFalse('different before', b.Equals(a));
    b.Assign(a);
    AssertTrue('equal after Assign', b.Equals(a));
    AssertEquals('Assign sends one OnChange', 1, FChanges);
    b.Assign(a);
    AssertEquals('assigning the same scheme sends nothing', 1, FChanges);
    a.CursorText := TColor($010203);
    AssertFalse('one colour apart', b.Equals(a));
    a.CursorText := clNone;
    a.Name := 'Other';
    AssertFalse('the name counts', b.Equals(a));
    b.Clear;
    AssertEquals('Clear sends one', 2, FChanges);
    AssertTrue('cleared', b.IsEmpty);
    AssertEquals('cleared name', '', b.Name);
    b.Clear;
    AssertEquals('clearing an empty scheme sends nothing', 2, FChanges);
  finally
    a.Free;
    b.Free;
  end;
end;

procedure TTyTerminalColorSchemeTests.TestSlotRgb;
var
  c: TTyTerminalColorScheme;
  rgb: Cardinal;
begin
  c := TTyTerminalColorScheme.Create;
  try
    c.Red := TColor($1F0FC5);
    AssertTrue('set', c.SlotRgb(tssRed, rgb));
    AssertEquals('RGB order', Hex6($C50F1F), Hex6(rgb));
    AssertFalse('unset', c.SlotRgb(tssGreen, rgb));
  finally
    c.Free;
  end;
end;

procedure TTyTerminalColorSchemeTests.TestNamedAndIndexedAreOneSlot;
var
  c: TTyTerminalColorScheme;
  s: TTyTerminalSchemeSlot;
begin
  c := TTyTerminalColorScheme.Create;
  try
    for s := Low(s) to High(s) do
    begin
      c.Colors[s] := TColor($100000 + Ord(s));
      AssertEquals(SlotProps[s] + ' reads the slot it names', $100000 + Ord(s), GetOrdProp(c, SlotProps[s]));
      SetOrdProp(c, SlotProps[s], $200000 + Ord(s));
      AssertEquals(SlotProps[s] + ' writes the slot it names', $200000 + Ord(s), Integer(c.Colors[s]));
    end;
    AssertEquals('Purple is slot 5', $200005, Integer(c.Colors[tssPurple]));
  finally
    c.Free;
  end;
end;

{ ---- Task 3:读 WT ----------------------------------------------------------------- }

const
  { WT 文档(customize-settings/color-schemes)里 Campbell 的示例:单个对象、键序与空格照文档
    (键之间有空行,冒号前有空格);值和 defaults.json 的 Campbell 逐个相同 }
  DocCampbell =
    '{'#10 +
    '    "name" : "Campbell",'#10 +
    #10 +
    '    "cursorColor": "#FFFFFF",'#10 +
    '    "selectionBackground": "#FFFFFF",'#10 +
    #10 +
    '    "background" : "#0C0C0C",'#10 +
    '    "foreground" : "#CCCCCC",'#10 +
    #10 +
    '    "black" : "#0C0C0C",'#10 +
    '    "blue" : "#0037DA",'#10 +
    '    "cyan" : "#3A96DD",'#10 +
    '    "green" : "#13A10E",'#10 +
    '    "purple" : "#881798",'#10 +
    '    "red" : "#C50F1F",'#10 +
    '    "white" : "#CCCCCC",'#10 +
    '    "yellow" : "#C19C00",'#10 +
    '    "brightBlack" : "#767676",'#10 +
    '    "brightBlue" : "#3B78FF",'#10 +
    '    "brightCyan" : "#61D6D6",'#10 +
    '    "brightGreen" : "#16C60C",'#10 +
    '    "brightPurple" : "#B4009E",'#10 +
    '    "brightRed" : "#E74856",'#10 +
    '    "brightWhite" : "#F2F2F2",'#10 +
    '    "brightYellow" : "#F9F1A5"'#10 +
    '}'#10;

  CampbellKeys: array[0..15] of string = (
    'black', 'red', 'green', 'yellow', 'blue', 'purple', 'cyan', 'white',
    'brightBlack', 'brightRed', 'brightGreen', 'brightYellow',
    'brightBlue', 'brightPurple', 'brightCyan', 'brightWhite');
  CampbellValues: array[0..15] of string = (
    '#0C0C0C', '#C50F1F', '#13A10E', '#C19C00', '#0037DA', '#881798', '#3A96DD', '#CCCCCC',
    '#767676', '#E74856', '#16C60C', '#F9F1A5', '#3B78FF', '#B4009E', '#61D6D6', '#F2F2F2');

  FixtureNames: array[0..15] of string = (
    'Dimidium', 'Ottosson', 'Campbell', 'Campbell Powershell', 'Vintage', 'One Half Dark',
    'One Half Light', 'Solarized Dark', 'Solarized Light', 'Tango Dark', 'Tango Light', 'Dark+',
    'VSCode Dark Modern', 'VSCode Light Modern', 'CGA', 'IBM 5153');

type
  TSchemeRow = record
    Name: string;
    { 16 色,然后 foreground、background、cursorColor、selectionBackground(缺的按 WT 补) }
    Rgb: array[0..19] of Cardinal;
  end;

const
  { 示例带的七套:照 WT defaults.json(commit 4e2b8bd9)逐色手抄,不经 fpjson }
  SevenSchemes: array[0..6] of TSchemeRow = (
    (Name: 'Campbell'; Rgb: ($0C0C0C, $C50F1F, $13A10E, $C19C00, $0037DA, $881798, $3A96DD, $CCCCCC, $767676, $E74856, $16C60C, $F9F1A5, $3B78FF, $B4009E, $61D6D6, $F2F2F2, $CCCCCC, $0C0C0C, $FFFFFF, $FFFFFF)),
    (Name: 'One Half Dark'; Rgb: ($282C34, $E06C75, $98C379, $E5C07B, $61AFEF, $C678DD, $56B6C2, $DCDFE4, $5A6374, $E06C75, $98C379, $E5C07B, $61AFEF, $C678DD, $56B6C2, $DCDFE4, $DCDFE4, $282C34, $FFFFFF, $FFFFFF)),
    (Name: 'One Half Light'; Rgb: ($383A42, $E45649, $50A14F, $C18301, $0184BC, $A626A4, $0997B3, $FAFAFA, $4F525D, $DF6C75, $98C379, $E4C07A, $61AFEF, $C577DD, $56B5C1, $FFFFFF, $383A42, $FAFAFA, $4F525D, $383A42)),
    (Name: 'Solarized Dark'; Rgb: ($002B36, $DC322F, $859900, $B58900, $268BD2, $D33682, $2AA198, $EEE8D5, $073642, $CB4B16, $586E75, $657B83, $839496, $6C71C4, $93A1A1, $FDF6E3, $839496, $002B36, $FFFFFF, $FFFFFF)),
    (Name: 'Solarized Light'; Rgb: ($002B36, $DC322F, $859900, $B58900, $268BD2, $D33682, $2AA198, $EEE8D5, $073642, $CB4B16, $586E75, $657B83, $839496, $6C71C4, $93A1A1, $FDF6E3, $657B83, $FDF6E3, $002B36, $2C4D57)),
    (Name: 'Tango Dark'; Rgb: ($000000, $CC0000, $4E9A06, $C4A000, $3465A4, $75507B, $06989A, $D3D7CF, $555753, $EF2929, $8AE234, $FCE94F, $729FCF, $AD7FA8, $34E2E2, $EEEEEC, $D3D7CF, $000000, $FFFFFF, $FFFFFF)),
    (Name: 'Tango Light'; Rgb: ($000000, $CC0000, $4E9A06, $C4A000, $3465A4, $75507B, $06989A, $D3D7CF, $555753, $EF2929, $8AE234, $FCE94F, $729FCF, $AD7FA8, $34E2E2, $EEEEEC, $555753, $FFFFFF, $000000, $141414)));

  RowSlots: array[0..19] of TTyTerminalSchemeSlot = (
    tssBlack, tssRed, tssGreen, tssYellow, tssBlue, tssPurple, tssCyan, tssWhite,
    tssBrightBlack, tssBrightRed, tssBrightGreen, tssBrightYellow,
    tssBrightBlue, tssBrightPurple, tssBrightCyan, tssBrightWhite,
    tssForeground, tssBackground, tssCursor, tssSelection);

{ Campbell 的 16 色,"键": "值" 用 ", " 连;ASkip 不写;5 / 13 号用给的键名 }
function Colours16(const ASkip: string = ''; const APurple: string = 'purple';
  const ABrightPurple: string = 'brightPurple'): string;
var
  i: Integer;
  k: string;
begin
  Result := '';
  for i := 0 to 15 do
  begin
    k := CampbellKeys[i];
    if k = ASkip then Continue;
    if k = 'purple' then k := APurple;
    if k = 'brightPurple' then k := ABrightPurple;
    if Result <> '' then Result := Result + ', ';
    Result := Result + '"' + k + '": "' + CampbellValues[i] + '"';
  end;
end;

{ 模板里第一个 % 之前的那一段:按它认是哪一条消息(翻译过也对) }
function Head(const AFmt: string): string;
var
  p: Integer;
begin
  p := Pos('%', AFmt);
  if p = 0 then Result := AFmt else Result := Copy(AFmt, 1, p - 1);
end;

function FixtureText: string;
var
  fs: TFileStream;
begin
  Result := '';
  fs := TFileStream.Create(TyTermFixturePath('terminal-wt-defaults.json'), fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, fs.Size);
    if Length(Result) > 0 then fs.ReadBuffer(Result[1], Length(Result));
  finally
    fs.Free;
  end;
end;

function SlotHex(C: TTyTerminalColorScheme; S: TTyTerminalSchemeSlot): string;
var
  rgb: Cardinal;
begin
  if C.SlotRgb(S, rgb) then Result := Hex6(rgb) else Result := 'unset';
end;

function TyTermDocCampbell: string;
begin
  Result := DocCampbell;
end;

function TyTermWtFixtureText: string;
begin
  Result := FixtureText;
end;

{ 读成功:OnChange 恰好一次;调用者释放 }
function TTyTerminalColorSchemeTests.LoadOk(ARow: Integer; const AText, AName: string): TTyTerminalColorScheme;
var
  err: string;
begin
  Result := NewCounted;
  if not Result.TryLoadFromText(AText, AName, err) then
  begin
    Result.Free;
    Fail(Format('row %d should load: %s', [ARow, err]));
  end;
  AssertEquals(Format('row %d: one OnChange', [ARow]), 1, FChanges);
end;

{ 读失败:消息是 AFmt 那一条、Key 是 AKey;事先装好的一套不变、不发 OnChange、修订号不动 }
procedure TTyTerminalColorSchemeTests.LoadFails(ARow: Integer; const AText, AName, AFmt, AKey: string;
  const AAlsoIn: string);
var
  c, snap: TTyTerminalColorScheme;
  err, msg, key: string;
  rev: Cardinal;
begin
  c := NewCounted;
  snap := TTyTerminalColorScheme.Create;
  try
    c.LoadFromText(DocCampbell);
    c.CursorText := TColor($030201);
    snap.Assign(c);
    rev := c.Revision;
    FChanges := 0;
    AssertFalse(Format('row %d: TryLoadFromText fails', [ARow]), c.TryLoadFromText(AText, AName, err));
    AssertTrue(Format('row %d: a message', [ARow]), err <> '');
    msg := '';
    key := '';
    try
      c.LoadFromText(AText, AName);
    except
      on E: ETyTerminalColorSchemeError do
      begin
        msg := E.Message;
        key := E.Key;
      end;
    end;
    AssertEquals(Format('row %d: the same message both ways', [ARow]), err, msg);
    AssertTrue(Format('row %d: "%s" is the message "%s"', [ARow, msg, AFmt]), Pos(Head(AFmt), msg) = 1);
    if AKey <> '*' then
      AssertEquals(Format('row %d: Key', [ARow]), AKey, key);
    if AAlsoIn <> '' then
      AssertTrue(Format('row %d: "%s" in "%s"', [ARow, AAlsoIn, msg]), Pos(AAlsoIn, msg) > 0);
    AssertTrue(Format('row %d: the scheme is as it was', [ARow]), c.Equals(snap));
    AssertEquals(Format('row %d: no OnChange', [ARow]), 0, FChanges);
    AssertEquals(Format('row %d: the revision is kept', [ARow]), rev, c.Revision);
  finally
    snap.Free;
    c.Free;
  end;
end;

procedure TTyTerminalColorSchemeTests.TestReadTheDocsCampbell;
var
  c: TTyTerminalColorScheme;
begin
  c := LoadOk(1, DocCampbell, '');
  try
    AssertEquals('name', 'Campbell', c.Name);
    AssertEquals('red', Hex6($C50F1F), SlotHex(c, tssRed));
    AssertEquals('purple', Hex6($881798), SlotHex(c, tssPurple));
    AssertEquals('brightYellow', Hex6($F9F1A5), SlotHex(c, tssBrightYellow));
    AssertEquals('background', Hex6($0C0C0C), SlotHex(c, tssBackground));
    AssertEquals('foreground', Hex6($CCCCCC), SlotHex(c, tssForeground));
    AssertEquals('cursorColor', Hex6($FFFFFF), SlotHex(c, tssCursor));
    AssertEquals('selectionBackground', Hex6($FFFFFF), SlotHex(c, tssSelection));
    AssertEquals('CursorText is not in WT', 'unset', SlotHex(c, tssCursorText));
    AssertEquals('SelectionInactiveBackground is not in WT', 'unset', SlotHex(c, tssSelectionInactive));
    AssertEquals('the TColor itself is BGR', IntToHex($1F0FC5, 8), IntToHex(c.Red, 8));
  finally
    c.Free;
  end;
  LoadOk(2, DocCampbell, 'Campbell').Free;
  LoadFails(3, DocCampbell, 'campbell', rsTermSchemeNotFound, '', 'campbell');
end;

procedure TTyTerminalColorSchemeTests.TestTheFixtureIsByteForByte;
var
  s: string;
  i, crlf: Integer;
begin
  s := FixtureText;
  AssertEquals('defaults.json at 4e2b8bd9 is 36805 bytes (autocrlf must not touch it)', 36805, Length(s));
  crlf := 0;
  for i := 1 to Length(s) - 1 do
    if (s[i] = #13) and (s[i + 1] = #10) then Inc(crlf);
  AssertEquals('CRLF throughout', 805, crlf);
end;

procedure TTyTerminalColorSchemeTests.TestListTheFixture;
var
  names: TStringArray;
  i: Integer;
begin
  names := TTyTerminalColorScheme.ListSchemeNames(FixtureText);
  AssertEquals('16 schemes', 16, Length(names));
  for i := 0 to 15 do
    AssertEquals('scheme ' + IntToStr(i), FixtureNames[i], names[i]);
  names := TTyTerminalColorScheme.ListSchemeNames(DocCampbell);
  AssertEquals('a single object: its own name', 1, Length(names));
  AssertEquals('a single object: its own name', 'Campbell', names[0]);
  names := TTyTerminalColorScheme.ListSchemeNames('{' + Colours16 + '}');
  AssertEquals('a single object without a name: one, empty', 1, Length(names));
  AssertEquals('a single object without a name: one, empty', '', names[0]);
  names := TTyTerminalColorScheme.ListSchemeNames('{"schemes": [{"name": "A"}, 1, {"name": 2}, {"name": "B", "red": "x"}]}');
  AssertEquals('named objects, complete or not', 2, Length(names));
  AssertEquals('A', names[0]);
  AssertEquals('B', names[1]);
  AssertEquals('text that does not parse: none', 0, Length(TTyTerminalColorScheme.ListSchemeNames('{')));
  AssertEquals('an array at the top: none', 0, Length(TTyTerminalColorScheme.ListSchemeNames('[1]')));
end;

procedure TTyTerminalColorSchemeTests.TestReadByNameFromTheFixture;
var
  c: TTyTerminalColorScheme;
  txt: string;
  i, k, loaded, compared: Integer;
begin
  txt := FixtureText;
  c := LoadOk(5, txt, 'Solarized Light');
  try
    AssertEquals('background', Hex6($FDF6E3), SlotHex(c, tssBackground));
    AssertEquals('cursorColor', Hex6($002B36), SlotHex(c, tssCursor));
    AssertEquals('selectionBackground', Hex6($2C4D57), SlotHex(c, tssSelection));
    AssertEquals('purple', Hex6($D33682), SlotHex(c, tssPurple));
    AssertEquals('brightWhite', Hex6($FDF6E3), SlotHex(c, tssBrightWhite));
  finally
    c.Free;
  end;
  c := LoadOk(6, txt, 'Campbell');
  try
    AssertEquals('Campbell has no selectionBackground: WT''s #FFFFFF', Hex6($FFFFFF), SlotHex(c, tssSelection));
  finally
    c.Free;
  end;
  LoadFails(7, txt, '', rsTermSchemeNeedName, '', 'Campbell');
  LoadFails(8, txt, 'Nope', rsTermSchemeNotFound, '', 'Tango Light');
  { 16 套都读得进 }
  loaded := 0;
  for i := 0 to 15 do
  begin
    c := LoadOk(100 + i, txt, FixtureNames[i]);
    try
      AssertEquals('the name', FixtureNames[i], c.Name);
      Inc(loaded);
    finally
      c.Free;
    end;
  end;
  AssertEquals('every scheme in defaults.json loads', 16, loaded);
  { 示例带的七套逐色 }
  compared := 0;
  for i := 0 to High(SevenSchemes) do
  begin
    c := LoadOk(200 + i, txt, SevenSchemes[i].Name);
    try
      for k := 0 to 19 do
      begin
        AssertEquals(SevenSchemes[i].Name + ' ' + SlotProps[RowSlots[k]], Hex6(SevenSchemes[i].Rgb[k]),
          SlotHex(c, RowSlots[k]));
        Inc(compared);
      end;
    finally
      c.Free;
    end;
  end;
  AssertEquals('7 schemes x 20 colours', 140, compared);
end;

procedure TTyTerminalColorSchemeTests.TestReadRules;
var
  c: TTyTerminalColorScheme;
begin
  { 9:没有 name 的单个对象;四个可选项按 WT 补 }
  c := LoadOk(9, '{' + Colours16 + '}', '');
  try
    AssertEquals('row 9: no name', '', c.Name);
    AssertEquals('row 9: foreground, WT''s default', Hex6($FFFFFF), SlotHex(c, tssForeground));
    AssertEquals('row 9: background, WT''s default', Hex6($000000), SlotHex(c, tssBackground));
    AssertEquals('row 9: cursor, WT''s default', Hex6($FFFFFF), SlotHex(c, tssCursor));
    AssertEquals('row 9: selection, WT''s default', Hex6($FFFFFF), SlotHex(c, tssSelection));
  finally
    c.Free;
  end;
  { 10:magenta / brightMagenta 代替 purple / brightPurple }
  c := LoadOk(10, '{' + Colours16('', 'magenta', 'brightMagenta') + '}', '');
  try
    AssertEquals('row 10: purple from magenta', Hex6($881798), SlotHex(c, tssPurple));
    AssertEquals('row 10: brightPurple from brightMagenta', Hex6($B4009E), SlotHex(c, tssBrightPurple));
  finally
    c.Free;
  end;
  { 11:purple 和 magenta 都写:主名为准 }
  c := LoadOk(11, '{' + Colours16 + ', "magenta": "#010203", "brightMagenta": "#040506"}', '');
  try
    AssertEquals('row 11: purple wins', Hex6($881798), SlotHex(c, tssPurple));
    AssertEquals('row 11: brightPurple wins', Hex6($B4009E), SlotHex(c, tssBrightPurple));
  finally
    c.Free;
  end;
  LoadFails(12, '{' + Colours16('brightCyan') + '}', '', rsTermSchemeMissingKeys, 'brightCyan', 'brightCyan');
  LoadFails(13, '{' + Colours16('red') + ', "magenta": "#010203"}', '', rsTermSchemeMissingKeys, 'red', 'red');
  LoadFails(14, '{' + Colours16('red') + ', "red": "#C50F1FFF"}', '', rsTermSchemeBadColor, 'red', '#C50F1FFF');
  LoadFails(15, '{' + Colours16('red') + ', "red": 12910623}', '', rsTermSchemeBadColor, 'red', '12910623');
  LoadFails(16, '{' + Colours16('red') + ', "red": null}', '', rsTermSchemeBadColor, 'red', 'null');
  LoadFails(17, '{' + Colours16 + ', "cursorColor": "#12345g"}', '', rsTermSchemeBadColor, 'cursorColor', '#12345g');
  LoadOk(18, '{' + Colours16 + ', "foo": 1, "cursorShape": "bar"}', '').Free;
  LoadFails(19, '{' + Colours16 + ', "red": "#C50F1F"}', '', rsTermSchemeBadJson, '', '');
  LoadOk(20, #$EF#$BB#$BF + DocCampbell, '').Free;
  LoadFails(21, #$FF#$FE'{'#0'}'#0, '', rsTermSchemeUtf16, '', '');
  LoadFails(211, #$FE#$FF#0'{'#0'}', '', rsTermSchemeUtf16, '', '');
  LoadFails(22, '[1, 2]', '', rsTermSchemeNotObject, '', '');
  LoadFails(23, '{"schemes": {}}', '', rsTermSchemeSchemesNotArray, 'schemes', '');
  { 24:第一个没有 name,不算候选 }
  c := LoadOk(24, '{"schemes": [{' + Colours16('red') + ', "red": "#111111"}, ' + DocCampbell + ']}', '');
  try
    AssertEquals('row 24: the named one', 'Campbell', c.Name);
    AssertEquals('row 24: its red', Hex6($C50F1F), SlotHex(c, tssRed));
  finally
    c.Free;
  end;
  { 25:不全的同名跳过 }
  c := LoadOk(25, '{"schemes": [{"name": "A", ' + Colours16('red') + '}, {"name": "A", ' + Colours16 + '}]}', 'A');
  try
    AssertEquals('row 25: the complete one', Hex6($C50F1F), SlotHex(c, tssRed));
  finally
    c.Free;
  end;
  { 26:同名的第一个(WT 的 emplace 不覆盖) }
  c := LoadOk(26, '{"schemes": [{"name": "A", ' + Colours16('red') + ', "red": "#111111"}, {"name": "A", '
    + Colours16('red') + ', "red": "#222222"}]}', 'A');
  try
    AssertEquals('row 26: the first', Hex6($111111), SlotHex(c, tssRed));
  finally
    c.Free;
  end;
  { 27:别的方案里的坏颜色不连累 }
  LoadOk(27, '{"schemes": [{"name": "A", ' + Colours16 + '}, {"name": "B", ' + Colours16('red')
    + ', "red": "bad"}]}', 'A').Free;
  { 28:名字写成两个挨着的 \u 转义 }
  c := LoadOk(28, J('{"schemes": [{"name": "`u4e2d`u6587", ') + Colours16 + '}]}', ZH);
  try
    AssertEquals('row 28: the name decoded', ZH, c.Name);
  finally
    c.Free;
  end;
  LoadFails(29, '{"schemes": []}', '', rsTermSchemeNoneValid, '', '');
  LoadFails(30, '{', '', rsTermSchemeBadJson, '', 'line 1');
  { settings.json 里只有一套完整的:不给名字也行 }
  LoadOk(31, '{"schemes": [{"name": "A"}, {"name": "B", ' + Colours16 + '}]}', '').Free;
  { 找不到时列出完整的名字 }
  LoadFails(32, '{"schemes": [{"name": "A", ' + Colours16 + '}, {"name": "B"}]}', 'C', rsTermSchemeNotFound, '', ': A');
end;

procedure TTyTerminalColorSchemeTests.TestReadFromFile;
var
  c: TTyTerminalColorScheme;
  err: string;
  raised: Boolean;
begin
  c := NewCounted;
  try
    AssertTrue('the fixture by name', c.TryLoadFromFile(TyTermFixturePath('terminal-wt-defaults.json'), 'Tango Light', err));
    AssertEquals('no message', '', err);
    AssertEquals('Tango Light', Hex6($FFFFFF), SlotHex(c, tssBackground));
    FChanges := 0;
    AssertFalse('a missing file', c.TryLoadFromFile(TyTermFixturePath('no-such-scheme.json'), '', err));
    AssertTrue('its message', err <> '');
    AssertEquals('nothing changed', 0, FChanges);
    raised := False;
    try
      c.LoadFromFile(TyTermFixturePath('no-such-scheme.json'));
    except
      on E: EFOpenError do raised := True;
    end;
    AssertTrue('LoadFromFile lets the RTL''s exception through', raised);
  finally
    c.Free;
  end;
end;

{ ---- Task 4:写 WT ----------------------------------------------------------------- }

procedure TTyTerminalColorSchemeTests.TestSaveCampbellExactly;
const
  Want =
    '{'#10 +
    '    "name": "Campbell",'#10 +
    '    "foreground": "#CCCCCC",'#10 +
    '    "background": "#0C0C0C",'#10 +
    '    "selectionBackground": "#FFFFFF",'#10 +
    '    "cursorColor": "#FFFFFF",'#10 +
    '    "black": "#0C0C0C",'#10 +
    '    "red": "#C50F1F",'#10 +
    '    "green": "#13A10E",'#10 +
    '    "yellow": "#C19C00",'#10 +
    '    "blue": "#0037DA",'#10 +
    '    "purple": "#881798",'#10 +
    '    "cyan": "#3A96DD",'#10 +
    '    "white": "#CCCCCC",'#10 +
    '    "brightBlack": "#767676",'#10 +
    '    "brightRed": "#E74856",'#10 +
    '    "brightGreen": "#16C60C",'#10 +
    '    "brightYellow": "#F9F1A5",'#10 +
    '    "brightBlue": "#3B78FF",'#10 +
    '    "brightPurple": "#B4009E",'#10 +
    '    "brightCyan": "#61D6D6",'#10 +
    '    "brightWhite": "#F2F2F2"'#10 +
    '}'#10;
var
  c: TTyTerminalColorScheme;
begin
  c := TTyTerminalColorScheme.Create;
  try
    { 小写的 #rgb 读进来,写成大写的 #RRGGBB }
    c.LoadFromText(DocCampbell.Replace('"#FFFFFF"', '"#fff"').Replace('"#C50F1F"', '"#c50f1f"'));
    AssertEquals('WT''s key order, upper case, four spaces, LF, one newline at the end', Want, c.SaveToText);
  finally
    c.Free;
  end;
end;

procedure TTyTerminalColorSchemeTests.TestReadWriteReadTheFixture;
var
  a, b: TTyTerminalColorScheme;
  txt: string;
  i, same: Integer;
begin
  txt := FixtureText;
  same := 0;
  a := TTyTerminalColorScheme.Create;
  b := TTyTerminalColorScheme.Create;
  try
    for i := 0 to 15 do
    begin
      a.LoadFromText(txt, FixtureNames[i]);
      b.LoadFromText(a.SaveToText);
      AssertTrue(FixtureNames[i] + ' reads back the same', b.Equals(a));
      Inc(same);
    end;
  finally
    a.Free;
    b.Free;
  end;
  AssertEquals('all 16 round-tripped', 16, same);
end;

procedure TTyTerminalColorSchemeTests.TestUnsetOptionalsAreNotWritten;
var
  a, b: TTyTerminalColorScheme;
  s: TTyTerminalSchemeSlot;
  txt: string;
begin
  a := TTyTerminalColorScheme.Create;
  b := TTyTerminalColorScheme.Create;
  try
    a.Name := 'Bare';
    for s := tssBlack to tssBrightWhite do
      a.Colors[s] := TColor($100000 + Ord(s));
    txt := a.SaveToText;
    AssertEquals('no foreground', 0, Pos('"foreground"', txt));
    AssertEquals('no background', 0, Pos('"background"', txt));
    AssertEquals('no cursorColor', 0, Pos('"cursorColor"', txt));
    AssertEquals('no selectionBackground', 0, Pos('"selectionBackground"', txt));
    b.LoadFromText(txt);
    AssertEquals('read back: WT''s foreground', Hex6($FFFFFF), SlotHex(b, tssForeground));
    AssertEquals('read back: WT''s background', Hex6($000000), SlotHex(b, tssBackground));
    AssertEquals('read back: WT''s cursor', Hex6($FFFFFF), SlotHex(b, tssCursor));
    AssertEquals('read back: WT''s selection', Hex6($FFFFFF), SlotHex(b, tssSelection));
    AssertEquals('the sixteen', IntToHex(a.Colors[tssBrightCyan], 8), IntToHex(b.Colors[tssBrightCyan], 8));
  finally
    a.Free;
    b.Free;
  end;
end;

procedure TTyTerminalColorSchemeTests.TestIncompleteSchemesAreNotWritten;
var
  c, snap: TTyTerminalColorScheme;
  key, fn: string;
begin
  c := NewCounted;
  snap := TTyTerminalColorScheme.Create;
  try
    c.LoadFromText(DocCampbell);
    c.Yellow := clNone;
    snap.Assign(c);
    FChanges := 0;
    key := '';
    try
      c.SaveToText;
    except
      on E: ETyTerminalColorSchemeError do key := E.Key;
    end;
    AssertEquals('a missing colour is refused, naming it', 'yellow', key);
    AssertTrue('the scheme is as it was', c.Equals(snap));
    AssertEquals('no OnChange', 0, FChanges);
    fn := GetTempDir(False) + 'tyterm-scheme-missing.json';
    DeleteFile(fn);
    try
      c.SaveToFile(fn);
    except
      on ETyTerminalColorSchemeError do ;
    end;
    AssertFalse('no file left behind', FileExists(fn));
    c.LoadFromText(DocCampbell);
    c.Name := '';
    key := '?';
    try
      c.SaveToText;
    except
      on E: ETyTerminalColorSchemeError do key := E.Key;
    end;
    AssertEquals('no name is refused', 'name', key);
  finally
    snap.Free;
    c.Free;
  end;
end;

procedure TTyTerminalColorSchemeTests.TestNamesRoundTrip;

  procedure Trip(const AName: string);
  var
    a, b: TTyTerminalColorScheme;
  begin
    a := TTyTerminalColorScheme.Create;
    b := TTyTerminalColorScheme.Create;
    try
      a.LoadFromText(DocCampbell);
      a.Name := AName;
      b.LoadFromText(a.SaveToText);
      AssertEquals('the name read back', AName, b.Name);
    finally
      a.Free;
      b.Free;
    end;
  end;

begin
  Trip(J('a"b`c'));
  Trip(ZH);
  Trip('a'#1'b');
  Trip(J('`u4e2d'));
end;

procedure TTyTerminalColorSchemeTests.TestWhatWtLacksIsNotWritten;
var
  c: TTyTerminalColorScheme;
  txt: string;
begin
  c := TTyTerminalColorScheme.Create;
  try
    c.LoadFromText(DocCampbell);
    c.CursorText := TColor($0C0B0A);
    c.SelectionInactiveBackground := TColor($0F0E0D);
    txt := c.SaveToText;
    AssertEquals('no cursor text', 0, Pos('#0A0B0C', txt));
    AssertEquals('no inactive selection', 0, Pos('#0D0E0F', txt));
    AssertEquals('no such key', 0, Pos('Inactive', txt));
    AssertEquals('no such key', 0, Pos('ursorText', txt));
  finally
    c.Free;
  end;
end;

procedure TTyTerminalColorSchemeTests.TestSystemColoursAreWrittenAsRgb;
var
  c: TTyTerminalColorScheme;
  sys: Cardinal;
begin
  c := TTyTerminalColorScheme.Create;
  try
    c.LoadFromText(DocCampbell);
    c.Red := clWindow;
    sys := Cardinal(ColorToRGB(clWindow));
    AssertTrue('clWindow as its RGB', Pos('"red": "' + TyTermSchemeColorText(((sys and $FF) shl 16)
      or (sys and $FF00) or ((sys shr 16) and $FF)) + '"', c.SaveToText) > 0);
  finally
    c.Free;
  end;
end;

{ ---- Task 7:设计器导入 ------------------------------------------------------------ }

procedure TTyTerminalColorSchemeTests.TestTheImportPlan;
var
  names: TStringArray;
  err: string;
  i: Integer;
begin
  AssertTrue('the fixture', TyTermSchemeImportPlan(FixtureText, names, err));
  AssertEquals('all 16', 16, Length(names));
  for i := 0 to 15 do
    AssertEquals('in order', FixtureNames[i], names[i]);
  AssertTrue('one object', TyTermSchemeImportPlan(DocCampbell, names, err));
  AssertEquals('one object: one name', 1, Length(names));
  AssertEquals('one object: its name', 'Campbell', names[0]);
  AssertTrue('only the complete ones', TyTermSchemeImportPlan('{"schemes": [{"name": "A"}, {"name": "B", '
    + Colours16 + '}, {"name": "B", ' + Colours16 + '}]}', names, err));
  AssertEquals('only the complete ones, a name once', 1, Length(names));
  AssertEquals('only the complete ones', 'B', names[0]);
  AssertFalse('bad JSON', TyTermSchemeImportPlan('{', names, err));
  AssertTrue('bad JSON: a message', Pos(Head(rsTermSchemeBadJson), err) = 1);
  AssertEquals('bad JSON: no names', 0, Length(names));
  AssertFalse('nothing complete', TyTermSchemeImportPlan('{"schemes": [{"name": "A"}]}', names, err));
  AssertEquals('nothing complete: the message', rsTermSchemeNoneValid, err);
  AssertFalse('an incomplete object', TyTermSchemeImportPlan('{' + Colours16('red') + '}', names, err));
  AssertTrue('an incomplete object: what is missing', Pos(Head(rsTermSchemeMissingKeys), err) = 1);
end;

{ ---- 6 期审查 ------------------------------------------------------------------- }

{ ADepth levels of [ ... ] (as the value of "x" inside a scheme object: the object is one
  more level) }
function Nested(ADepth: Integer; const AOpen, AClose: string): string;
begin
  Result := StringOfChar(AOpen[1], ADepth) + StringOfChar(AClose[1], ADepth);
end;

procedure TTyTerminalColorSchemeTests.TestDeepNestingIsRefused;
var
  deep: string;
  c: TTyTerminalColorScheme;
begin
  deep := Format(rsTermSchemeTooDeep, [TyTermJsonMaxDepth]);
  AssertEquals('the limit', 64, TyTermJsonMaxDepth);
  { 64 levels in all (the object, then 63 arrays): reads }
  c := LoadOk(40, '{' + Colours16 + ', "x": ' + Nested(63, '[', ']') + '}', '');
  c.Free;
  { 65: refused, as bad JSON, before fpjson sees it -- with no \u in the text (the path that
    skips the decoding) and with one }
  LoadFails(41, '{' + Colours16 + ', "x": ' + Nested(64, '[', ']') + '}', '', rsTermSchemeBadJson, '', deep);
  LoadFails(42, J('{"name": "`u4e2d", ') + Colours16 + ', "x": ' + Nested(64, '[', ']') + '}', '',
    rsTermSchemeBadJson, '', deep);
  { braces count too, and the two mixed }
  LoadFails(44, StringOfChar('{', 65) + StringOfChar('}', 65), '', rsTermSchemeBadJson, '', deep);
  LoadFails(45, '{"a": ' + StringOfChar('[', 32) + '{"b": ' + StringOfChar('[', 32)
    + StringOfChar(']', 32) + '}' + StringOfChar(']', 32) + '}', '', rsTermSchemeBadJson, '', deep);
  { brackets in a string, a comment, or after the closing ones do not count }
  c := LoadOk(46, '{' + Colours16 + ', "name": "' + StringOfChar('[', 100) + '", "n2": ''' + StringOfChar('{', 100)
    + '''' + #10'// ' + StringOfChar('[', 100) + #10'/* ' + StringOfChar('{', 100) + ' */}', '');
  try
    AssertEquals('row 46: the name', StringOfChar('[', 100), c.Name);
  finally
    c.Free;
  end;
  { the pure function says so itself }
  try
    TyTermJsonDecodeEscapes(StringOfChar('[', 65));
    Fail('65 levels, no escape: TyTermJsonDecodeEscapes raises');
  except
    on E: ETyTerminalColorSchemeError do
      AssertTrue('its message: ' + E.Message, Pos(deep, E.Message) > 0);
  end;
  AssertEquals('64 levels, no escape: as it was', StringOfChar('[', 64), TyTermJsonDecodeEscapes(StringOfChar('[', 64)));
end;

{ 100 000 levels used to overflow fpjson's recursion and take the process down (the IDE,
  in the designer). Every entry point answers instead. }
procedure TTyTerminalColorSchemeTests.TestVeryDeepNestingDoesNotCrash;
var
  txt, err: string;
  c: TTyTerminalColorScheme;
  names: TStringArray;
begin
  txt := StringOfChar('[', 100000);
  c := TTyTerminalColorScheme.Create;
  try
    AssertFalse('TryLoadFromText', c.TryLoadFromText(txt, '', err));
    AssertTrue('the message: ' + err, Pos(Head(rsTermSchemeBadJson), err) = 1);
    AssertFalse('with a name', c.TryLoadFromText('{"schemes": ' + txt, 'A', err));
    AssertFalse('and an escape', c.TryLoadFromText(J('{"name": "`u4e2d", "x": ') + txt, '', err));
    AssertTrue('nothing loaded', c.IsEmpty);
  finally
    c.Free;
  end;
  AssertEquals('ListSchemeNames', 0, Length(TTyTerminalColorScheme.ListSchemeNames(txt)));
  AssertFalse('the import plan', TyTermSchemeImportPlan(txt, names, err));
  AssertTrue('the import plan: the message', Pos(Head(rsTermSchemeBadJson), err) = 1);
end;

procedure TTyTerminalColorSchemeTests.TestAHugeFileIsNotRead;
var
  fn, err: string;
  fs: TFileStream;
  c: TTyTerminalColorScheme;
  raised: Boolean;
  buf: string;
begin
  AssertEquals('the limit', 16 * 1024 * 1024, TyTermSchemeMaxFileBytes);
  fn := GetTempDir(False) + 'tyterm-huge-scheme.json';
  buf := DocCampbell + StringOfChar(' ', TyTermSchemeMaxFileBytes + 1 - Length(DocCampbell));
  fs := TFileStream.Create(fn, fmCreate);
  try
    fs.WriteBuffer(buf[1], Length(buf));
  finally
    fs.Free;
  end;
  c := NewCounted;
  try
    AssertEquals('one byte over', TyTermSchemeMaxFileBytes + 1, Length(buf));
    AssertFalse('TryLoadFromFile', c.TryLoadFromFile(fn, '', err));
    AssertTrue('the message: ' + err, Pos(Head(rsTermSchemeTooBig), err) = 1);
    AssertEquals('nothing changed', 0, FChanges);
    raised := False;
    try
      c.LoadFromFile(fn);
    except
      on E: ETyTerminalColorSchemeError do raised := True;
    end;
    AssertTrue('LoadFromFile raises the scheme error', raised);
    AssertTrue('still empty', c.IsEmpty);
  finally
    c.Free;
    DeleteFile(fn);
  end;
end;

{ the part of a message after its last %s (tells apart two messages that start alike) }
function Tail(const AFmt: string): string;
var
  p: Integer;
begin
  Result := AFmt;
  p := Pos('%s', Result);
  while p > 0 do
  begin
    Delete(Result, 1, p + 1);
    p := Pos('%s', Result);
  end;
end;

procedure TTyTerminalColorSchemeTests.TestNameListsNameEachOnce;
var
  c: TTyTerminalColorScheme;
begin
  { a name twice: listed once }
  LoadFails(50, '{"schemes": [{"name": "A", ' + Colours16 + '}, {"name": "A", ' + Colours16 + '}, {"name": "B", '
    + Colours16 + '}]}', 'C', rsTermSchemeNotFound, '', 'text: A, B');
  LoadFails(51, '{"schemes": [{"name": "A", ' + Colours16 + '}, {"name": "A", ' + Colours16 + '}, {"name": "B", '
    + Colours16 + '}]}', '', rsTermSchemeNeedName, '', 'one: A, B');
  { two of one name and nothing else: one scheme can be named, so no name is needed (the first) }
  c := LoadOk(52, '{"schemes": [{"name": "A", ' + Colours16('red') + ', "red": "#111111"}, {"name": "A", '
    + Colours16 + '}]}', '');
  try
    AssertEquals('row 52: the first A', Hex6($111111), SlotHex(c, tssRed));
  finally
    c.Free;
  end;
  { no complete scheme to list: another sentence, not "Schemes in the text: " and nothing }
  LoadFails(53, '{"schemes": [{"name": "A"}]}', 'C', rsTermSchemeNotFoundNone, '', Tail(rsTermSchemeNotFoundNone));
  LoadFails(54, '{"schemes": []}', 'C', rsTermSchemeNotFoundNone, '', Tail(rsTermSchemeNotFoundNone));
  { a single object without a name, asked for by name }
  LoadFails(55, '{' + Colours16 + '}', 'C', rsTermSchemeNotFoundUnnamed, '', Tail(rsTermSchemeNotFoundUnnamed));
  { with a name it is listed }
  LoadFails(56, DocCampbell, 'C', rsTermSchemeNotFound, '', 'text: Campbell');
end;

procedure TTyTerminalColorSchemeTests.TestTheImportPlanSkipsBadColours;
var
  names: TStringArray;
  err: string;
begin
  AssertTrue('a bad colour in one', TyTermSchemeImportPlan('{"schemes": [{"name": "A", ' + Colours16('red')
    + ', "red": "bad"}, {"name": "B", ' + Colours16 + '}]}', names, err));
  AssertEquals('only B', 1, Length(names));
  AssertEquals('only B', 'B', names[0]);
  { the first A is the one read by name: if it is broken, A is not offered, even though a
    second A is fine }
  AssertTrue('the first of a name is broken', TyTermSchemeImportPlan('{"schemes": [{"name": "A", ' + Colours16('red')
    + ', "red": "bad"}, {"name": "A", ' + Colours16 + '}, {"name": "B", ' + Colours16 + '}]}', names, err));
  AssertEquals('A is not offered', 1, Length(names));
  AssertEquals('A is not offered', 'B', names[0]);
  AssertFalse('all broken', TyTermSchemeImportPlan('{"schemes": [{"name": "A", ' + Colours16('red')
    + ', "red": "bad"}]}', names, err));
  AssertTrue('all broken: which colour: ' + err, (Pos(Head(rsTermSchemeBadColor), err) = 1) and (Pos('bad', err) > 0));
  AssertEquals('all broken: no names', 0, Length(names));
  AssertFalse('a single object with a bad colour', TyTermSchemeImportPlan('{' + Colours16('red')
    + ', "red": "#12345g"}', names, err));
  AssertTrue('a single object with a bad colour: which: ' + err, Pos('#12345g', err) > 0);
end;

procedure TTyTerminalColorSchemeTests.TestChangedIsAChange;
var
  c: TTyTerminalColorScheme;
begin
  c := NewCounted;
  try
    c.Background := clWindow;
    AssertEquals('set once', 1, FChanges);
    c.Background := clWindow;
    AssertEquals('the same system colour again: nothing', 1, FChanges);
    c.Changed;
    AssertEquals('Changed: an OnChange with nothing changed', 2, FChanges);
    AssertEquals('Changed: a revision', 2, c.Revision);
    c.BeginUpdate;
    c.Changed;
    c.Changed;
    AssertEquals('inside an update: held', 2, FChanges);
    c.EndUpdate;
    AssertEquals('one at the end', 3, FChanges);
    AssertEquals('one revision', 3, c.Revision);
  finally
    c.Free;
  end;
end;

initialization
  RegisterTest(TTyTerminalColorSchemeTests);
end.
