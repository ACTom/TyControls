unit test.themebuilder.diff;
{ The line diff behind the AI comparison window, and the one edit that puts the AI's version
  into the editor touching only the lines that differ (phase 3). }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry;

type
  TTbDiffTests = class(TTestCase)
  published
    procedure TestTheSame;                   { D1 }
    procedure TestAChangedLine;              { D2 }
    procedure TestARemovedLine;              { D3 }
    procedure TestAnAddedLine;               { D4 }
    procedure TestPairsAndTheRest;           { D5 }
    procedure TestFirstGoneLastNew;          { D6 }
    procedure TestLineBreaksDoNotCount;      { D7 }
    procedure TestALongTheme;                { D8 }
    procedure TestTooBigIsCoarse;            { D9 }
    procedure TestTheEditTouchesTheMiddle;   { D10 }
    procedure TestTheEditStaysInTheText;     { D11 }
    procedure TestSplittingLines;            { D12 }
    procedure TestLinesAtTheEnd;             { D13 }
  end;

implementation

uses
  tbcssscan, tbdiff, test.themebuilder.golden;

function Lines(const S: string): TStringList;
begin
  Result := TStringList.Create;
  if S <> '' then
    TbSplitLines(StringReplace(S, '|', #10, [rfReplaceAll]), Result);
end;

function Describe(const ARows: TTbDiffRows): string;
const
  cNames: array[TTbDiffKind] of string = ('same', 'removed', 'added', 'changed');
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(ARows) do
  begin
    if Result <> '' then Result := Result + ', ';
    Result := Result + Format('%s(%d,%d)', [cNames[ARows[i].Kind], ARows[i].Left, ARows[i].Right]);
  end;
end;

function DiffOf(const A, B: string; AMax: Integer = TbDiffMaxCells): string;
var
  la, lb: TStringList;
begin
  la := Lines(A);
  lb := Lines(B);
  try
    Result := Describe(TbDiffLines(la, lb, AMax));
  finally
    la.Free;
    lb.Free;
  end;
end;

function CountOf(const A, B: string): Integer;
var
  la, lb: TStringList;
begin
  la := Lines(A);
  lb := Lines(B);
  try
    Result := TbDiffChangeCount(TbDiffLines(la, lb));
  finally
    la.Free;
    lb.Free;
  end;
end;

procedure TTbDiffTests.TestTheSame;
begin
  AssertEquals('D1', 'same(0,0), same(1,1), same(2,2)', DiffOf('a|b|c', 'a|b|c'));
  AssertEquals('D1: no change', 0, CountOf('a|b|c', 'a|b|c'));
end;

procedure TTbDiffTests.TestAChangedLine;
begin
  AssertEquals('D2', 'same(0,0), changed(1,1), same(2,2)', DiffOf('a|b|c', 'a|x|c'));
end;

procedure TTbDiffTests.TestARemovedLine;
begin
  AssertEquals('D3', 'same(0,0), removed(1,-1), same(2,1)', DiffOf('a|b|c', 'a|c'));
end;

procedure TTbDiffTests.TestAnAddedLine;
begin
  AssertEquals('D4', 'same(0,0), added(-1,1), same(1,2)', DiffOf('a|c', 'a|b|c'));
end;

procedure TTbDiffTests.TestPairsAndTheRest;
begin
  AssertEquals('D5', 'same(0,0), changed(1,1), changed(2,2), added(-1,3), same(3,4)',
    DiffOf('a|b|c|d', 'a|x|y|z|d'));
  AssertEquals('D5: more removed than added', 'same(0,0), changed(1,1), removed(2,-1), same(3,2)',
    DiffOf('a|b|c|d', 'a|x|d'));
end;

procedure TTbDiffTests.TestFirstGoneLastNew;
begin
  AssertEquals('D6', 'removed(0,-1), same(1,0), same(2,1), added(-1,2)', DiffOf('x|a|b', 'a|b|y'));
  AssertEquals('D6: two places', 2, CountOf('x|a|b', 'a|b|y'));
  { the common start and end must not overlap: all of 'a|a' is a common start already }
  AssertEquals('D6: no overlap', 'same(0,0), same(1,1), added(-1,2)', DiffOf('a|a', 'a|a|a'));
end;

procedure TTbDiffTests.TestLineBreaksDoNotCount;
var
  la, lb: TStringList;
begin
  la := TStringList.Create;
  lb := TStringList.Create;
  try
    TbSplitLines('a'#13#10'b'#13#10'c'#13#10, la);
    TbSplitLines('a'#10'b'#10'c', lb);
    AssertEquals('D7', 'same(0,0), same(1,1), same(2,2)', Describe(TbDiffLines(la, lb)));
  finally
    la.Free;
    lb.Free;
  end;
end;

procedure TTbDiffTests.TestALongTheme;
var
  la, lb: TStringList;
  sl: TStringList;
  rows: TTbDiffRows;
  t0: QWord;
  ms: Int64;
begin
  sl := TStringList.Create;
  la := TStringList.Create;
  lb := TStringList.Create;
  try
    sl.LoadFromFile(TbRepoDir + 'themes' + PathDelim + 'light.tycss');
    TbSplitLines(sl.Text, la);
    AssertTrue('D8: a long theme', la.Count > 1000);
    lb.Assign(la);
    lb[699] := lb[699] + ' /* changed */';
    lb.Delete(899);
    t0 := GetTickCount64;
    rows := TbDiffLines(la, lb);
    ms := GetTickCount64 - t0;
    WriteLn(Format('D8: %d lines compared in %d ms', [la.Count, ms]));
    AssertEquals('D8: two places', 2, TbDiffChangeCount(rows));
    AssertTrue(Format('D8: %d ms', [ms]), ms < 200);
  finally
    sl.Free;
    la.Free;
    lb.Free;
  end;
end;

procedure TTbDiffTests.TestTooBigIsCoarse;
begin
  AssertEquals('D9', 'changed(0,0), same(1,1), changed(2,2)', DiffOf('a|b|c', 'x|b|y'));
  AssertEquals('D9: over the limit', 'changed(0,0), changed(1,1), changed(2,2)',
    DiffOf('a|b|c', 'x|b|y', 4));
end;

procedure TTbDiffTests.TestTheEditTouchesTheMiddle;
const
  cOld = 'a'#13#10'b'#13#10'c'#13#10;
  cNew = 'a'#10'X'#10'c'#10;
var
  e: TTbTextEdit;
  old: string;
begin
  old := TbNormalizeEol(cOld);
  e := TbWholeTextEdit(old, cNew);
  AssertEquals('D10: starts at b', Pos('b', old), e.Start);
  AssertEquals('D10: stops where c starts', Pos('c', old), e.Stop);
  AssertEquals('D10: the new line', 'X' + LineEnding, e.Text);
  AssertEquals('D10: applied, it is the new text', TbNormalizeEol(cNew),
    TbApplyEdits(old, [e]));
end;

procedure TTbDiffTests.TestTheEditStaysInTheText;
var
  e: TTbTextEdit;
  old: string;
begin
  old := TbNormalizeEol('a'#10'b'#10);
  e := TbWholeTextEdit(old, old);
  AssertEquals('D11: nothing to do: start', e.Start, e.Stop);
  AssertEquals('D11: nothing to do: text', '', e.Text);
  e := TbWholeTextEdit(old, 'x'#10'y'#10);
  AssertEquals('D11: all different: from the start', 1, e.Start);
  AssertTrue(Format('D11: stops inside the text (%d of %d)', [e.Stop, Length(old)]),
    e.Stop <= Length(old));
  AssertEquals('D11: before the last break', Length(old) - Length(LineEnding) + 1, e.Stop);
  AssertEquals('D11: applied', TbNormalizeEol('x'#10'y'#10), TbApplyEdits(old, [e]));
end;

procedure TTbDiffTests.TestSplittingLines;
var
  sl: TStringList;
begin
  sl := TStringList.Create;
  try
    TbSplitLines('a'#13'b'#10'c', sl);
    AssertEquals('D12: three lines', 3, sl.Count);
    AssertEquals('D12: the third', 'c', sl[2]);
    TbSplitLines('a'#10, sl);
    AssertEquals('D12: a final break adds no line', 1, sl.Count);
    TbSplitLines('', sl);
    AssertEquals('D12: nothing', 0, sl.Count);
    TbSplitLines('a'#10#10, sl);
    AssertEquals('D12: an empty line before the final break', 2, sl.Count);
  finally
    sl.Free;
  end;
end;

{ lines added or removed at the very end: still one edit inside the text }
procedure TTbDiffTests.TestLinesAtTheEnd;
var
  e: TTbTextEdit;
  old: string;
begin
  old := TbNormalizeEol('a'#10'b'#10);
  e := TbWholeTextEdit(old, 'a'#10'b'#10'c'#10);
  AssertTrue('D13: added at the end, inside the text', e.Stop <= Length(old));
  AssertTrue('D13: a proper edit', e.Start <= e.Stop);
  AssertEquals('D13: added at the end, applied', TbNormalizeEol('a'#10'b'#10'c'#10), TbApplyEdits(old, [e]));
  e := TbWholeTextEdit(old, 'a'#10);
  AssertTrue('D13: removed at the end, inside the text', e.Stop <= Length(old));
  AssertEquals('D13: removed at the end, applied', TbNormalizeEol('a'#10), TbApplyEdits(old, [e]));
end;

initialization
  RegisterTest(TTbDiffTests);
end.
