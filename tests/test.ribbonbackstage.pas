unit test.ribbonbackstage;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, fpcunit, testregistry,
  tyControls.Base, tyControls.RibbonBackstage;

type
  TBackstageTest = class(TTestCase)
  private
    FSelected: Integer;
    FSelectCount: Integer;
    procedure HandleSelect(Sender: TObject; AIndex: Integer);
  published
    procedure RowRectStacksBelowBackBand;
    procedure RowAtBackBandRowsAndNone;
    procedure BottomRowRectFlushToBottom;
    procedure IndexAtSpansTopAndBottom;
    procedure TypeKey;
    procedure CommandsRoundTrip;
    procedure ItemIndexFiresSelectOnChange;
    procedure ItemIndexClampsToCommands;
  end;

implementation

procedure TBackstageTest.HandleSelect(Sender: TObject; AIndex: Integer);
begin
  FSelected := AIndex;
  Inc(FSelectCount);
end;

procedure TBackstageTest.RowRectStacksBelowBackBand;
var R: TRect;
begin
  // sidebar 180, back band 44, row 34 -> row 0 = (0,44,180,78); row 2 = (0,112,180,146).
  R := TyBackstageRowRect(0, 180, 44, 34);
  AssertEquals('row0 top', 44, R.Top);
  AssertEquals('row0 bottom', 78, R.Bottom);
  AssertEquals('row width', 180, R.Right);
  R := TyBackstageRowRect(2, 180, 44, 34);
  AssertEquals('row2 top', 44 + 2 * 34, R.Top);
end;

procedure TBackstageTest.RowAtBackBandRowsAndNone;
begin
  AssertEquals('in back band', TyBackstageBackRow, TyBackstageRowAt(20, 44, 34, 3));
  AssertEquals('first row', 0, TyBackstageRowAt(50, 44, 34, 3));
  AssertEquals('third row', 2, TyBackstageRowAt(44 + 2 * 34 + 5, 44, 34, 3));
  AssertEquals('past last row', TyBackstageNoRow, TyBackstageRowAt(44 + 3 * 34 + 5, 44, 34, 3));
  AssertEquals('zero row height', TyBackstageNoRow, TyBackstageRowAt(50, 44, 0, 3));
end;

procedure TBackstageTest.BottomRowRectFlushToBottom;
var R: TRect;
begin
  // client 600, sidebar 180, row 34, 3 bottom rows -> the block occupies 498..600.
  // Bottom row j=0 is the TOP of the block; j=2 is flush to the bottom edge.
  R := TyBackstageBottomRowRect(0, 3, 600, 180, 34);
  AssertEquals('j0 top', 600 - 3 * 34, R.Top);
  AssertEquals('j0 bottom', 600 - 2 * 34, R.Bottom);
  AssertEquals('width', 180, R.Right);
  R := TyBackstageBottomRowRect(2, 3, 600, 180, 34);
  AssertEquals('last row bottom == client bottom', 600, R.Bottom);
end;

procedure TBackstageTest.IndexAtSpansTopAndBottom;
begin
  // back band 44, row 34, 2 top + 3 bottom, client 600 (bottom block = 498..600).
  AssertEquals('back band', TyBackstageBackRow,
    TyBackstageIndexAt(20, 600, 44, 34, 2, 3));
  AssertEquals('top row 0', 0, TyBackstageIndexAt(50, 600, 44, 34, 2, 3));
  AssertEquals('top row 1', 1, TyBackstageIndexAt(44 + 34 + 2, 600, 44, 34, 2, 3));
  AssertEquals('gap between blocks -> none', TyBackstageNoRow,
    TyBackstageIndexAt(300, 600, 44, 34, 2, 3));
  // Bottom block: first bottom row = unified index 2 (top count), last = 4.
  AssertEquals('bottom row 0 -> idx 2', 2, TyBackstageIndexAt(600 - 3 * 34 + 2, 600, 44, 34, 2, 3));
  AssertEquals('bottom row 2 -> idx 4', 4, TyBackstageIndexAt(600 - 1, 600, 44, 34, 2, 3));
end;

procedure TBackstageTest.TypeKey;
var B: TTyRibbonBackstage;
begin
  B := TTyRibbonBackstage.Create(nil);
  try
    AssertEquals('typeKey', 'TyRibbonBackstage', (B as ITyStyleable).GetStyleTypeKey);
  finally
    B.Free;
  end;
end;

procedure TBackstageTest.CommandsRoundTrip;
var B: TTyRibbonBackstage;
begin
  B := TTyRibbonBackstage.Create(nil);
  try
    B.Commands.Add('开始'); B.Commands.Add('新建'); B.Commands.Add('打开');
    AssertEquals('count', 3, B.Commands.Count);
    B.Commands := nil;   // nil assign clears, no raise
    AssertEquals('cleared', 0, B.Commands.Count);
  finally
    B.Free;
  end;
end;

procedure TBackstageTest.ItemIndexFiresSelectOnChange;
var B: TTyRibbonBackstage;
begin
  FSelected := -99; FSelectCount := 0;
  B := TTyRibbonBackstage.Create(nil);
  try
    B.Commands.Add('a'); B.Commands.Add('b');
    B.OnCommandSelect := @HandleSelect;
    B.ItemIndex := 1;
    AssertEquals('fired once', 1, FSelectCount);
    AssertEquals('index reported', 1, FSelected);
    B.ItemIndex := 1;   // no-op -> no fire
    AssertEquals('no fire on no-op', 1, FSelectCount);
  finally
    B.Free;
  end;
end;

procedure TBackstageTest.ItemIndexClampsToCommands;
var B: TTyRibbonBackstage;
begin
  B := TTyRibbonBackstage.Create(nil);
  try
    B.Commands.Add('only');
    B.ItemIndex := 5;               // clamps to Count-1 = 0
    AssertEquals('clamped', 0, B.ItemIndex);
    B.Commands.Clear;               // shrink -> stale index reset
    AssertEquals('reset after clear', -1, B.ItemIndex);
  finally
    B.Free;
  end;
end;

initialization
  RegisterTest(TBackstageTest);
end.
