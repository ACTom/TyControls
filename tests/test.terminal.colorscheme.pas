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
  tyControls.Terminal.ColorScheme;

type
  TTyTerminalColorSchemeTests = class(TTestCase)
  private
    FChanges: Integer;
    procedure Counted(Sender: TObject);
    function NewCounted: TTyTerminalColorScheme;
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
  end;

{ 反引号换成反斜杠(见单元头) }
function J(const S: string): string;

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

initialization
  RegisterTest(TTyTerminalColorSchemeTests);
end.
