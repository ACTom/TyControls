unit test.toolwindow.layouttext;
{$mode objfpc}{$H+}

{ 布局串的纯函数(spec §10.2 / §10.3):解析、格式化(表 A / R / F)、截断,以及版本漂移计划
  (表 P)。输入都是字符串和记录,没有控件。 }

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  tyControls.ToolWindows.LayoutText;

type
  TTyToolWindowLayoutTextTests = class(TTestCase)
  private
    function Parse(const AText: string): TTyToolLayoutDoc;
    procedure CheckGroup(const AMsg: string; const AGroup: TTyToolLayoutGroup;
      ASize: Integer; ACollapsed: Boolean; const ANames: array of string; const AActive: string);
    procedure CheckRejected(const AMsg, AText: string);
    procedure CheckSameDoc(const AMsg: string; const A, B: TTyToolLayoutDoc);
  published
    procedure TestTheGoodStringParses;
    procedure TestGroupsAreOptionalAndOrderFree;
    procedure TestUnknownKeysAreIgnored;
    procedure TestEmptyListsAndEmptyActive;
    procedure TestDottedNamesAreAccepted;
    procedure TestSizesAreOneToFiveDigits;
    procedure TestActiveTakesTheListsSpelling;
    procedure TestEveryDefectRejectsTheWholeString;
    procedure TestFormatWritesTheGroupsInOrder;
    procedure TestFormatRoundTrips;
    procedure TestEveryPrefixIsRejected;
  end;

implementation

const
  G = 'TYTOOLLAYOUT/1|left=240,0|leftWins=Explorer,Search|leftActive=Explorer' +
    '|right=300,1|rightWins=Outline|rightActive=Outline' +
    '|bottom=200,0|bottomWins=Problems,Output|bottomActive=Output|end';

{ G 里把第一处 AOld 换成 ANew(测试前提:必须真的换到了)。 }
function Mutate(const AOld, ANew: string): string;
var
  p: Integer;
begin
  p := Pos(AOld, G);
  if p = 0 then raise Exception.Create('前提:G 里没有 ' + AOld);
  Result := Copy(G, 1, p - 1) + ANew + Copy(G, p + Length(AOld), MaxInt);
end;

function TTyToolWindowLayoutTextTests.Parse(const AText: string): TTyToolLayoutDoc;
begin
  AssertTrue('应当接受:' + AText, TyToolLayoutParse(AText, Result));
end;

procedure TTyToolWindowLayoutTextTests.CheckGroup(const AMsg: string;
  const AGroup: TTyToolLayoutGroup; ASize: Integer; ACollapsed: Boolean;
  const ANames: array of string; const AActive: string);
var
  i: Integer;
begin
  AssertTrue(AMsg + ':Present', AGroup.Present);
  AssertEquals(AMsg + ':尺寸', ASize, AGroup.Size);
  AssertEquals(AMsg + ':收起', ACollapsed, AGroup.Collapsed);
  AssertEquals(AMsg + ':名字个数', Length(ANames), Length(AGroup.Names));
  for i := 0 to High(ANames) do
    AssertEquals(AMsg + ':名字 ' + IntToStr(i), ANames[i], AGroup.Names[i]);
  AssertEquals(AMsg + ':当前页', AActive, AGroup.Active);
end;

procedure TTyToolWindowLayoutTextTests.CheckRejected(const AMsg, AText: string);
var
  d: TTyToolLayoutDoc;
  side: TTyToolLayoutSide;
begin
  AssertFalse(AMsg + ' 应当拒绝:' + AText, TyToolLayoutParse(AText, d));
  for side := Low(TTyToolLayoutSide) to High(TTyToolLayoutSide) do
    AssertFalse(AMsg + ':拒绝时 doc 全是零值', d[side].Present);
end;

procedure TTyToolWindowLayoutTextTests.CheckSameDoc(const AMsg: string;
  const A, B: TTyToolLayoutDoc);
var
  side: TTyToolLayoutSide;
  i: Integer;
begin
  for side := Low(TTyToolLayoutSide) to High(TTyToolLayoutSide) do
  begin
    AssertEquals(AMsg + ':Present', A[side].Present, B[side].Present);
    if not A[side].Present then Continue;
    AssertEquals(AMsg + ':Size', A[side].Size, B[side].Size);
    AssertEquals(AMsg + ':Collapsed', A[side].Collapsed, B[side].Collapsed);
    AssertEquals(AMsg + ':Names 个数', Length(A[side].Names), Length(B[side].Names));
    for i := 0 to High(A[side].Names) do
      AssertEquals(AMsg + ':Names', A[side].Names[i], B[side].Names[i]);
    AssertEquals(AMsg + ':Active', A[side].Active, B[side].Active);
  end;
end;

{ --- 接受(A1–A10) ----------------------------------------------------------------- }

procedure TTyToolWindowLayoutTextTests.TestTheGoodStringParses;
var
  d: TTyToolLayoutDoc;
begin
  d := Parse(G);
  CheckGroup('A1 left', d[tlsLeft], 240, False, ['Explorer', 'Search'], 'Explorer');
  CheckGroup('A1 right', d[tlsRight], 300, True, ['Outline'], 'Outline');
  CheckGroup('A1 bottom', d[tlsBottom], 200, False, ['Problems', 'Output'], 'Output');
end;

procedure TTyToolWindowLayoutTextTests.TestGroupsAreOptionalAndOrderFree;
var
  d: TTyToolLayoutDoc;
begin
  d := Parse(Mutate('|right=300,1|rightWins=Outline|rightActive=Outline', ''));
  AssertFalse('A2 缺 right:不 Present', d[tlsRight].Present);
  CheckGroup('A2 left', d[tlsLeft], 240, False, ['Explorer', 'Search'], 'Explorer');
  CheckGroup('A2 bottom', d[tlsBottom], 200, False, ['Problems', 'Output'], 'Output');
  d := Parse('TYTOOLLAYOUT/1|end');
  AssertFalse('A3 left', d[tlsLeft].Present);
  AssertFalse('A3 right', d[tlsRight].Present);
  AssertFalse('A3 bottom', d[tlsBottom].Present);
  d := Parse('TYTOOLLAYOUT/1|bottom=200,0|bottomWins=Problems,Output|bottomActive=Output' +
    '|right=300,1|rightWins=Outline|rightActive=Outline' +
    '|left=240,0|leftWins=Explorer,Search|leftActive=Explorer|end');
  CheckGroup('A10 倒过来 left', d[tlsLeft], 240, False, ['Explorer', 'Search'], 'Explorer');
  CheckGroup('A10 倒过来 right', d[tlsRight], 300, True, ['Outline'], 'Outline');
  CheckGroup('A10 倒过来 bottom', d[tlsBottom], 200, False, ['Problems', 'Output'], 'Output');
end;

procedure TTyToolWindowLayoutTextTests.TestUnknownKeysAreIgnored;
var
  d: TTyToolLayoutDoc;
begin
  d := Parse(Mutate('|end', '|future=a,b|end'));
  CheckGroup('A4 left', d[tlsLeft], 240, False, ['Explorer', 'Search'], 'Explorer');
  CheckGroup('A4 bottom', d[tlsBottom], 200, False, ['Problems', 'Output'], 'Output');
end;

procedure TTyToolWindowLayoutTextTests.TestEmptyListsAndEmptyActive;
var
  d: TTyToolLayoutDoc;
begin
  d := Parse('TYTOOLLAYOUT/1|left=240,0|leftWins=|leftActive=|end');
  CheckGroup('A5 空列表', d[tlsLeft], 240, False, [], '');
  d := Parse(Mutate('leftActive=Explorer', 'leftActive='));
  CheckGroup('A6 空当前页', d[tlsLeft], 240, False, ['Explorer', 'Search'], '');
end;

procedure TTyToolWindowLayoutTextTests.TestDottedNamesAreAccepted;
var
  d: TTyToolLayoutDoc;
begin
  d := Parse(Mutate('leftWins=Explorer,Search|leftActive=Explorer',
    'leftWins=Frame1.Explorer,Search|leftActive=Search'));
  CheckGroup('A7 带点的名字', d[tlsLeft], 240, False, ['Frame1.Explorer', 'Search'], 'Search');
end;

procedure TTyToolWindowLayoutTextTests.TestSizesAreOneToFiveDigits;
begin
  AssertEquals('A8 0', 0, Parse(Mutate('left=240,0', 'left=0,0'))[tlsLeft].Size);
  AssertEquals('A8 99999', 99999, Parse(Mutate('left=240,0', 'left=99999,1'))[tlsLeft].Size);
  AssertTrue('A8 99999 收起', Parse(Mutate('left=240,0', 'left=99999,1'))[tlsLeft].Collapsed);
  AssertEquals('A8 前导零', 240, Parse(Mutate('left=240,0', 'left=00240,0'))[tlsLeft].Size);
end;

procedure TTyToolWindowLayoutTextTests.TestActiveTakesTheListsSpelling;
begin
  AssertEquals('A9 拼写取列表里的', 'Explorer',
    Parse(Mutate('leftActive=Explorer', 'leftActive=explorer'))[tlsLeft].Active);
end;

{ --- 拒绝(R1–R24) ----------------------------------------------------------------- }

procedure TTyToolWindowLayoutTextTests.TestEveryDefectRejectsTheWholeString;
var
  s: string;
begin
  CheckRejected('R1 版本', Mutate('TYTOOLLAYOUT/1', 'TYTOOLLAYOUT/2'));
  CheckRejected('R2 标签小写', Mutate('TYTOOLLAYOUT/1', 'tytoollayout/1'));
  CheckRejected('R3 缺 end', Mutate('|end', ''));
  s := Mutate('leftActive=Explorer|right', 'leftActive=Explorer|end|right');
  CheckRejected('R4 end 不在最后', Copy(s, 1, Length(s) - Length('|end')));
  CheckRejected('R5 两个 end', G + '|end');
  CheckRejected('R6 组不完整', Mutate('|rightActive=Outline', ''));
  CheckRejected('R7 前导空格', Mutate('left=240,0', 'left= 240,0'));
  CheckRejected('R8 十六进制', Mutate('left=240,0', 'left=$F0,0'));
  CheckRejected('R9 标志 2', Mutate('left=240,0', 'left=240,2'));
  CheckRejected('R10 三个字段', Mutate('left=240,0', 'left=240,0,1'));
  CheckRejected('R11 六位数', Mutate('left=240,0', 'left=100000,0'));
  CheckRejected('R12 空尺寸', Mutate('left=240,0', 'left=,0'));
  CheckRejected('R13 负号', Mutate('left=240,0', 'left=-1,0'));
  CheckRejected('R13 正号', Mutate('left=240,0', 'left=+240,0'));
  CheckRejected('R14 当前页不在自己的列表里', Mutate('leftActive=Explorer', 'leftActive=Outline'));
  CheckRejected('R15 只差大小写的重名',
    Mutate('rightWins=Outline|rightActive=Outline', 'rightWins=explorer|rightActive=explorer'));
  CheckRejected('R16 重复 key', Mutate('|end', '|left=240,0|end'));
  CheckRejected('R17 空列表项', Mutate('leftWins=Explorer,Search', 'leftWins=Explorer,,Search'));
  CheckRejected('R18 末尾空项', Mutate('leftWins=Explorer,Search', 'leftWins=Explorer,'));
  CheckRejected('R19 空段', Mutate('left=240,0|', 'left=240,0||'));
  CheckRejected('R20 空 key', Mutate('|end', '|=5|end'));
  CheckRejected('R21 没有 =', Mutate('|end', '|foo|end'));
  CheckRejected('R22 数字开头', Mutate('leftWins=Explorer,Search', 'leftWins=Explorer,1abc'));
  CheckRejected('R22 带空格', Mutate('leftWins=Explorer,Search', 'leftWins=Exp lorer'));
  CheckRejected('R23 key 区分大小写', Mutate('left=240,0', 'Left=240,0'));
  CheckRejected('R24 空串', '');
end;

{ --- 格式化(F1–F5)与截断 ------------------------------------------------------------ }

procedure TTyToolWindowLayoutTextTests.TestFormatWritesTheGroupsInOrder;
var
  d: TTyToolLayoutDoc;
begin
  AssertEquals('F1 逐字等于 G', G, TyToolLayoutFormat(Parse(G)));
  d := Parse(G);
  d[tlsRight].Present := False;
  d[tlsBottom].Present := False;
  AssertEquals('F2 只有 left',
    'TYTOOLLAYOUT/1|left=240,0|leftWins=Explorer,Search|leftActive=Explorer|end',
    TyToolLayoutFormat(d));
  AssertEquals('F3 空列表', 'TYTOOLLAYOUT/1|left=240,0|leftWins=|leftActive=|end',
    TyToolLayoutFormat(Parse('TYTOOLLAYOUT/1|left=240,0|leftWins=|leftActive=|end')));
  d := Default(TTyToolLayoutDoc);
  AssertEquals('F4 全不 Present', 'TYTOOLLAYOUT/1|end', TyToolLayoutFormat(d));
end;

procedure TTyToolWindowLayoutTextTests.TestFormatRoundTrips;

  procedure Check(const AMsg: string; const ADoc: TTyToolLayoutDoc);
  var
    back: TTyToolLayoutDoc;
  begin
    AssertTrue(AMsg + ':读得回来', TyToolLayoutParse(TyToolLayoutFormat(ADoc), back));
    CheckSameDoc(AMsg, ADoc, back);
  end;

var
  d: TTyToolLayoutDoc;
begin
  Check('F5 F1', Parse(G));
  d := Parse(G);
  d[tlsRight].Present := False;
  d[tlsBottom].Present := False;
  Check('F5 F2', d);
  Check('F5 F3', Parse('TYTOOLLAYOUT/1|left=240,0|leftWins=|leftActive=|end'));
  Check('F5 F4', Default(TTyToolLayoutDoc));
end;

procedure TTyToolWindowLayoutTextTests.TestEveryPrefixIsRejected;
var
  i: Integer;
  d: TTyToolLayoutDoc;
begin
  for i := 1 to Length(G) - 1 do
    AssertFalse('前缀 ' + IntToStr(i) + ' 应当拒绝', TyToolLayoutParse(Copy(G, 1, i), d));
end;

initialization
  RegisterTest(TTyToolWindowLayoutTextTests);
end.
