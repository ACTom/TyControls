unit test.retiredprops;

{$mode objfpc}{$H+}

{ #130 (4.0): the properties 3.x published and 4.0 does not -- CharCase on the numeric edits;
  MaxLength, CharCase and ReadOnly on the pick-only combo boxes; HideSelectionWhenInactive,
  FadeUnfocusedSelection and MinEditorWidth on TTyDrawGrid; MainColumn on a grid's header.
  A form saved by 3.x holds them; it opens, the values are dropped, and what follows each of
  them in the form file is still read. Saved again, the form no longer holds them. }

interface

uses
  Classes, SysUtils, Forms, StdCtrls, fpcunit, testregistry,
  tyControls.NumericEdit, tyControls.CalcEdit, tyControls.ComboBox, tyControls.ColorBox,
  tyControls.ShellComboBox, tyControls.Grid;

type
  TRetiredPropertiesTest = class(TTestCase)
  private
    FForm: TForm;
    function FromText(const AText: string): TForm;
    function FormText(AHost: TForm): string;
  protected
    procedure TearDown; override;
  published
    procedure TestANumericEditDropsCharCase;
    procedure TestAPickOnlyComboBoxDropsItsEditProperties;
    procedure TestADrawGridDropsItsSelectionAndEditorProperties;
    procedure TestAGridHeaderDropsMainColumn;
    procedure TestTheControlsThatStillPublishThemReadThem;
  end;

implementation

const
  Head = 'object Form1: TForm' + LineEnding + '  Left = 0' + LineEnding;
  Tail = 'end' + LineEnding;

function TRetiredPropertiesTest.FromText(const AText: string): TForm;
var
  ts: TStringStream;
  bs: TMemoryStream;
begin
  Result := TForm.CreateNew(nil);
  ts := TStringStream.Create(AText);
  bs := TMemoryStream.Create;
  try
    ObjectTextToBinary(ts, bs);
    bs.Position := 0;
    bs.ReadComponent(Result);   // a property it does not know raises EReadError here
  finally
    bs.Free;
    ts.Free;
  end;
end;

function TRetiredPropertiesTest.FormText(AHost: TForm): string;
var
  ms: TMemoryStream;
  ts: TStringStream;
begin
  ms := TMemoryStream.Create;
  ts := TStringStream.Create('');
  try
    ms.WriteComponent(AHost);
    ms.Position := 0;
    ObjectBinaryToText(ms, ts);
    Result := ts.DataString;
  finally
    ts.Free;
    ms.Free;
  end;
end;

procedure TRetiredPropertiesTest.TearDown;
begin
  FreeAndNil(FForm);
end;

procedure TRetiredPropertiesTest.TestANumericEditDropsCharCase;
var
  n: TTyNumericEdit;
  c: TTyCalcEdit;
begin
  FForm := FromText(Head +
    '  object N1: TTyNumericEdit' + LineEnding +
    '    CharCase = ecUppercase' + LineEnding +
    '    Width = 120' + LineEnding +
    '  end' + LineEnding +
    '  object C1: TTyCalcEdit' + LineEnding +
    '    CharCase = ecLowerCase' + LineEnding +
    '    Width = 130' + LineEnding +
    '  end' + LineEnding + Tail);
  n := FForm.FindComponent('N1') as TTyNumericEdit;
  c := FForm.FindComponent('C1') as TTyCalcEdit;
  AssertEquals('what follows CharCase is read', 120, n.Width);
  AssertTrue('the value is dropped', n.CharCase = ecNormal);
  AssertEquals('a descendant too', 130, c.Width);
  AssertEquals('and saved again, the form holds no CharCase', 0, Pos('CharCase', FormText(FForm)));
end;

procedure TRetiredPropertiesTest.TestAPickOnlyComboBoxDropsItsEditProperties;
var
  b: TTyColorBox;
  s: TTyShellComboBox;
  txt: string;
begin
  FForm := FromText(Head +
    '  object B1: TTyColorBox' + LineEnding +
    '    MaxLength = 5' + LineEnding +
    '    CharCase = ecLowerCase' + LineEnding +
    '    ReadOnly = True' + LineEnding +
    '    Width = 140' + LineEnding +
    '  end' + LineEnding +
    '  object S1: TTyShellComboBox' + LineEnding +
    '    ReadOnly = True' + LineEnding +
    '    Width = 150' + LineEnding +
    '  end' + LineEnding + Tail);
  b := FForm.FindComponent('B1') as TTyColorBox;
  s := FForm.FindComponent('S1') as TTyShellComboBox;
  AssertEquals('what follows them is read', 140, b.Width);
  AssertEquals('on another pick-only box too', 150, s.Width);
  txt := FormText(FForm);
  AssertEquals('saved again: no MaxLength', 0, Pos('MaxLength', txt));
  AssertEquals('no CharCase', 0, Pos('CharCase', txt));
  AssertEquals('no ReadOnly', 0, Pos('ReadOnly', txt));
end;

procedure TRetiredPropertiesTest.TestADrawGridDropsItsSelectionAndEditorProperties;
var
  g: TTyDrawGrid;
  txt: string;
begin
  FForm := FromText(Head +
    '  object G1: TTyDrawGrid' + LineEnding +
    '    HideSelectionWhenInactive = True' + LineEnding +
    '    FadeUnfocusedSelection = False' + LineEnding +
    '    MinEditorWidth = 40' + LineEnding +
    '    Width = 160' + LineEnding +
    '  end' + LineEnding + Tail);
  g := FForm.FindComponent('G1') as TTyDrawGrid;
  AssertEquals('what follows them is read', 160, g.Width);
  txt := FormText(FForm);
  AssertEquals('saved again: no HideSelectionWhenInactive', 0, Pos('HideSelectionWhenInactive', txt));
  AssertEquals('no FadeUnfocusedSelection', 0, Pos('FadeUnfocusedSelection', txt));
  AssertEquals('no MinEditorWidth', 0, Pos('MinEditorWidth', txt));
end;

procedure TRetiredPropertiesTest.TestAGridHeaderDropsMainColumn;
var
  g: TTyDrawGrid;
begin
  FForm := FromText(Head +
    '  object G1: TTyDrawGrid' + LineEnding +
    '    Header.MainColumn = 1' + LineEnding +
    '    Header.Height = 31' + LineEnding +
    '    Width = 170' + LineEnding +
    '  end' + LineEnding + Tail);
  g := FForm.FindComponent('G1') as TTyDrawGrid;
  AssertEquals('what follows it in the header is read', 31, g.Header.Height);
  AssertEquals('and after the header', 170, g.Width);
  AssertEquals('saved again: no MainColumn', 0, Pos('MainColumn', FormText(FForm)));
end;

{ A published property is read before DefineProperties is asked: the controls that still
  publish one take its value. }
procedure TRetiredPropertiesTest.TestTheControlsThatStillPublishThemReadThem;
var
  cb: TTyComboBox;
  sg: TTyStringGrid;
begin
  FForm := FromText(Head +
    '  object B1: TTyComboBox' + LineEnding +
    '    MaxLength = 5' + LineEnding +
    '    ReadOnly = True' + LineEnding +
    '  end' + LineEnding +
    '  object G1: TTyStringGrid' + LineEnding +
    '    MinEditorWidth = 40' + LineEnding +
    '  end' + LineEnding + Tail);
  cb := FForm.FindComponent('B1') as TTyComboBox;
  sg := FForm.FindComponent('G1') as TTyStringGrid;
  AssertEquals('the editable combo box reads MaxLength', 5, cb.MaxLength);
  AssertTrue('and ReadOnly', cb.ReadOnly);
  AssertEquals('the string grid reads MinEditorWidth', 40, sg.MinEditorWidth);
end;

initialization
  RegisterClasses([TTyNumericEdit, TTyCalcEdit, TTyColorBox, TTyShellComboBox, TTyComboBox,
    TTyDrawGrid, TTyStringGrid]);
  RegisterTest(TRetiredPropertiesTest);
end.
