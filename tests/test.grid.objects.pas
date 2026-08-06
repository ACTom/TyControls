unit test.grid.objects;
{ TTyStringGrid 的两条移植缺口:每格一个对象槽(LCL 的 Objects[ACol,ARow]),
  以及把整列/整行当成**活的、可赋值的** TStrings 交出去(LCL 的 Cols[]/Rows[])。

  这里守的不是"属性存在",而是三件容易悄悄坏掉的事:

  一、**对象要跟着格子搬家**。对象槽住在 TTyGridCellAttr 里,而那条记录在物理排序
      (SortMode = gsmData)、插删行、换行、拖行时都会被搬。只要 Assign 漏抄一个
      字段,排完序文字换了位置、对象留在原地 —— 宿主拿 Objects[0,0] 去查记录,
      查到的是别人的。这条是最值得守的,所以排在最前面。

  二、**对象不能被稀疏回收顺手丢掉**。属性记录退化成"全默认值"时会被丢弃,
      对象槽必须算进"不是默认值",否则"设个底色再清掉"就把宿主的指针抹了。

  三、**对象不进撤销栈**(设计决定,见 grid.md)。撤销既不恢复它,也不许销毁它。

  Cols[]/Rows[] 这边守的是长度不匹配时的约定:视图的长度就是网格的结构,
  赋值**既不改行数/列数,也不清空多出来的那一段** —— 与 LCL 逐字一致
  (grids.pas:10882),因为移植过来的代码依赖的是那个行为。 }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Forms, Graphics, fpcunit, testregistry,
  tyControls.Types, tyControls.Controller, tyControls.Columns, tyControls.Grid;

type
  { TTyGridCellAttr **去掉 Obj 之后**的字段表,逐字照抄(顺序也一样 ——
    FPC 按声明序布局,顺序变了大小就可能变)。它只为一件事存在:把
    "对象槽究竟多花了多少内存"**量出来**,而不是拍脑袋说"一个指针"。

    加字段忘了同步这里 → 下面那条断言变红,那正是它的用处:
    这条记录是稀疏的,但**每一个有属性的格子**都要按它的大小付钱。 }
  TAttrLayoutWithoutObject = class
  public
    ColSpan, RowSpan: Integer;
    HasBackground:    Boolean;
    Background:       TTyColor;
    HasTextColor:     Boolean;
    TextColor:        TTyColor;
    HasAlignment:     Boolean;
    Alignment:        TAlignment;
    HasFontStyle:     Boolean;
    FontStyle:        TFontStyles;
    ReadOnly:         Boolean;
    HasCellDisplay:   Boolean;
    CellDisplay:      TTyGridCellDisplay;
    Comment:          string;
  end;

  { 挂在格子上的东西随便是什么 —— 网格不认识它、也不拥有它。
    带一个可读的名字,断言失败时能看出拿错了哪一个。 }
  TPayload = class
  public
    Name: string;
    constructor Create(const AName: string);
  end;

  TGridObjectsFixture = class(TTestCase)
  protected
    FForm: TForm;
    FCtl: TTyStyleController;
    FBag: TList;              { 测试自己拥有这些 payload,网格不拥有 }
    { 4 列 x ARowCount 行,列头不可见 —— 与 test.grid.pas 的 MakeStrGrid 同一形状。
      **返回裸类**:这两组成员都必须从宿主够得着。 }
    function NewGrid(ARowCount: Integer = 6): TTyStringGrid;
    function NewPayload(const AName: string): TPayload;
    procedure SetUp; override;
    procedure TearDown; override;
  end;

  { Objects[ACol, ARow]:存在、稀疏、跟着格子搬家。 }
  TGridCellObjectTest = class(TGridObjectsFixture)
  published
    procedure TestObjectSlotStartsNilAndRoundTrips;
    procedure TestObjectSlotCostsExactlyOneSparseEntry;
    procedure TestClearingAnObjectGivesTheSparseEntryBack;
    procedure TestObjectSurvivesAnAttributeThatComesAndGoes;
    procedure TestObjectDoesNotPullTheCellTextIntoStorage;
    { 物理排序:文字换了位置,对象必须跟着换。 }
    procedure TestPhysicalSortMovesTheObjectWithItsText;
    procedure TestInsertRowMovesTheObjectDown;
    procedure TestDeleteRowMovesTheObjectUp;
    procedure TestMoveRowCarriesTheObject;
    procedure TestSwapRowsCarriesTheObject;
  end;

  { 撤销与对象槽的关系 —— 一条明确的"不做"。 }
  TGridObjectUndoTest = class(TGridObjectsFixture)
  published
    procedure TestHangingAnObjectIsNotAnUndoableChange;
    procedure TestUndoingAnAttributeKeepsTheObject;
    procedure TestUndoingAnAttributeThatCreatedTheEntryKeepsTheObject;
    procedure TestUndoingARowDeleteBringsBackTextButNotObjectSlots;
    procedure TestTheTwoContractsAreWrittenDown;
  end;

  { Cols[] / Rows[]:活视图 + 赋值语义。 }
  TGridRowColStringsTest = class(TGridObjectsFixture)
  published
    procedure TestRowViewReadsTheRowAndCountsColumns;
    procedure TestColViewReadsTheColumnAndCountsRows;
    procedure TestViewIsLiveNotACopy;
    procedure TestWritingThroughTheViewWritesTheCell;
    procedure TestSameIndexGivesTheSameViewObject;
    procedure TestViewObjectsAreTheCellObjects;
    procedure TestAssigningARowCopiesStringsAndObjects;
    procedure TestAssigningAShorterListLeavesTheTailAlone;
    procedure TestAssigningALongerListIsTruncatedAndNeverGrowsTheGrid;
    procedure TestAssigningAColumnNeverChangesTheRowCount;
    procedure TestAnyTStringsConsumerCanBeFilledFromAView;
    procedure TestCommaTextFillsFromTheStart;
    procedure TestClearBlanksTheWholeLineAndItsObjects;
    procedure TestInsertAndDeleteAreRefused;
    procedure TestOutOfRangeReadsEmptyAndOutOfRangeWriteRaises;
    procedure TestWholeRowAssignmentIsOneUndoStep;
  end;

  { 往稀疏记录里加一个字段是有代价的 —— 把它量出来,别猜。 }
  TGridCellAttrCostTest = class(TTestCase)
  published
    procedure TestObjectSlotAddsOnePointerToTheAttrRecord;
    procedure TestAnObjectAloneIsNotADefaultAttr;
  end;

implementation


{ TPayload }

constructor TPayload.Create(const AName: string);
begin
  inherited Create;
  Name := AName;
end;

{ TGridObjectsFixture }

procedure TGridObjectsFixture.SetUp;
begin
  inherited SetUp;
  FCtl := TTyStyleController.Create(nil);
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 600, 400);
  FBag := TList.Create;
end;

procedure TGridObjectsFixture.TearDown;
var
  i: Integer;
begin
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  { 网格先没了,payload 后没 —— 顺序是故意的:网格**不拥有**它们,
    先释放网格不该让这些指针出事。 }
  for i := 0 to FBag.Count - 1 do TPayload(FBag[i]).Free;
  FreeAndNil(FBag);
  inherited TearDown;
end;

function TGridObjectsFixture.NewGrid(ARowCount: Integer): TTyStringGrid;
var
  i: Integer;
  c: TTyColumn;
begin
  Result := TTyStringGrid.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, 400, 300);
  for i := 0 to 3 do
  begin
    c := Result.Header.Columns.Add as TTyColumn;
    c.Width := 80;
  end;
  Result.Header.Options := Result.Header.Options - [hoVisible];
  Result.DefaultRowHeight := 20;
  Result.RowCount := ARowCount;
end;

function TGridObjectsFixture.NewPayload(const AName: string): TPayload;
begin
  Result := TPayload.Create(AName);
  FBag.Add(Result);
end;

{ ---- Objects[ACol, ARow] --------------------------------------------------- }

procedure TGridCellObjectTest.TestObjectSlotStartsNilAndRoundTrips;
var
  G: TTyStringGrid;
  p: TPayload;
begin
  G := NewGrid;
  AssertTrue('没挂过东西的格子是 nil', G.Objects[1, 2] = nil);
  p := NewPayload('rec-1');
  G.Objects[1, 2] := p;
  AssertTrue('取回来还是同一个指针', G.Objects[1, 2] = p);
  AssertTrue('别的格子没被连累', G.Objects[1, 3] = nil);
  AssertTrue('别的列也没有', G.Objects[0, 2] = nil);
end;

{ 稀疏是这套存储的立身之本:挂一个对象只该多出**一条**属性记录,
  不该顺手把整行整列都实体化。 }
procedure TGridCellObjectTest.TestObjectSlotCostsExactlyOneSparseEntry;
var
  G: TTyStringGrid;
begin
  G := NewGrid(1000);
  AssertEquals('前置条件:一条属性都没有', 0, G.StoredCellAttrCount);
  G.Objects[2, 700] := NewPayload('one');
  AssertEquals('挂一个对象 = 一条属性记录', 1, G.StoredCellAttrCount);
  G.Objects[2, 701] := NewPayload('two');
  AssertEquals('再挂一个 = 两条', 2, G.StoredCellAttrCount);
end;

procedure TGridCellObjectTest.TestClearingAnObjectGivesTheSparseEntryBack;
var
  G: TTyStringGrid;
begin
  G := NewGrid;
  G.Objects[1, 1] := NewPayload('x');
  AssertEquals('前置条件', 1, G.StoredCellAttrCount);
  G.Objects[1, 1] := nil;
  AssertTrue('清掉了', G.Objects[1, 1] = nil);
  AssertEquals('只剩对象槽的空壳记录要被回收', 0, G.StoredCellAttrCount);
end;

{ 属性记录退化成"全默认值"时会被丢弃。对象槽必须算进"不是默认值" ——
  否则"涂个底色再清掉"会把宿主的指针一起抹了。 }
procedure TGridCellObjectTest.TestObjectSurvivesAnAttributeThatComesAndGoes;
var
  G: TTyStringGrid;
  p: TPayload;
begin
  G := NewGrid;
  p := NewPayload('keep-me');
  G.Objects[1, 1] := p;
  G.CellColors[1, 1] := $FFFF0000;
  G.CellColors[1, 1] := 0;                  { 0 = 无色;记录退化 → DropIfDefault 要跑 }
  AssertTrue('底色来了又走,对象还在', G.Objects[1, 1] = p);
  G.CellReadOnly[1, 1] := True;
  G.CellReadOnly[1, 1] := False;
  AssertTrue('只读来了又走,对象还在', G.Objects[1, 1] = p);
end;

{ 对象槽与文字是两套存储。挂对象不该凭空造出一个"写过的格"。 }
procedure TGridCellObjectTest.TestObjectDoesNotPullTheCellTextIntoStorage;
var
  G: TTyStringGrid;
begin
  G := NewGrid;
  G.Objects[1, 1] := NewPayload('x');
  AssertEquals('文字存储一格没多', 0, G.StoredCellCount);
  AssertEquals('文字仍是空的', '', G.Cells[1, 1]);
end;

{ **这条是核心。** 物理排序把数据真的换位置;对象必须与它那一格的文字
  一起走。漏抄一个字段的症状是:文字排好了,Objects[] 全留在旧行 ——
  宿主照着行号去查记录,查到的是别人的记录,而且一声不响。 }
procedure TGridCellObjectTest.TestPhysicalSortMovesTheObjectWithItsText;
var
  G: TTyStringGrid;
  r: Integer;
  pay: array[0..5] of TPayload;
begin
  G := NewGrid(6);
  for r := 0 to 5 do
  begin
    G.Cells[0, r] := Format('%.2d', [5 - r]);       { 05 04 03 02 01 00 }
    pay[r] := NewPayload('row-' + IntToStr(r));
    G.Objects[0, r] := pay[r];
  end;
  G.SortMode := gsmData;
  G.SortByColumn(0, sdAscending);

  { 排完之后数据行 r 上的文字是 '0r';它原来在第 (5-r) 行,
    所以那一行的对象也该是 pay[5-r]。 }
  for r := 0 to 5 do
  begin
    AssertEquals(Format('前置条件:第 %d 行的文字已排好', [r]),
      Format('%.2d', [r]), G.Cells[0, r]);
    AssertTrue(Format('第 %d 行的对象跟着它的文字走了(应为 row-%d)', [r, 5 - r]),
      G.Objects[0, r] = pay[5 - r]);
  end;
end;

procedure TGridCellObjectTest.TestInsertRowMovesTheObjectDown;
var
  G: TTyStringGrid;
  p: TPayload;
begin
  G := NewGrid(4);
  p := NewPayload('third');
  G.Cells[0, 2] := 'c';
  G.Objects[0, 2] := p;
  G.InsertRow(1);
  AssertEquals('前置条件:文字下移了一行', 'c', G.Cells[0, 3]);
  AssertTrue('对象跟着下移', G.Objects[0, 3] = p);
  AssertTrue('旧位置空了', G.Objects[0, 2] = nil);
end;

procedure TGridCellObjectTest.TestDeleteRowMovesTheObjectUp;
var
  G: TTyStringGrid;
  p: TPayload;
begin
  G := NewGrid(4);
  p := NewPayload('third');
  G.Cells[0, 2] := 'c';
  G.Objects[0, 2] := p;
  G.DeleteRow(1);
  AssertEquals('前置条件:文字上移了一行', 'c', G.Cells[0, 1]);
  AssertTrue('对象跟着上移', G.Objects[0, 1] = p);
end;

procedure TGridCellObjectTest.TestMoveRowCarriesTheObject;
var
  G: TTyStringGrid;
  p: TPayload;
begin
  G := NewGrid(5);
  p := NewPayload('mover');
  G.Cells[0, 0] := 'a';
  G.Objects[0, 0] := p;
  G.MoveRow(0, 3);
  AssertEquals('前置条件:文字搬到了第 3 行', 'a', G.Cells[0, 3]);
  AssertTrue('对象跟着搬', G.Objects[0, 3] = p);
end;

procedure TGridCellObjectTest.TestSwapRowsCarriesTheObject;
var
  G: TTyStringGrid;
  p1, p2: TPayload;
begin
  G := NewGrid(4);
  p1 := NewPayload('one');
  p2 := NewPayload('two');
  G.Cells[0, 1] := '1';  G.Objects[0, 1] := p1;
  G.Cells[0, 3] := '3';  G.Objects[0, 3] := p2;
  G.SwapRows(1, 3);
  AssertEquals('前置条件:文字换了', '3', G.Cells[0, 1]);
  AssertTrue('对象也换了(1 号位)', G.Objects[0, 1] = p2);
  AssertTrue('对象也换了(3 号位)', G.Objects[0, 3] = p1);
end;

{ ---- 撤销与对象槽 ---------------------------------------------------------- }

{ 挂一个对象**不是**一次可撤销的改动:撤销栈是值语义的,而对象是宿主的指针。
  记进去就等于允许 Ctrl+Z 交还一个宿主可能已经释放掉的地址。 }
procedure TGridObjectUndoTest.TestHangingAnObjectIsNotAnUndoableChange;
var
  G: TTyStringGrid;
begin
  G := NewGrid;
  G.ClearUndo;
  G.Objects[1, 1] := NewPayload('x');
  AssertFalse('挂对象没往撤销栈里压记录', G.CanUndo);
  G.Objects[1, 1] := nil;
  AssertFalse('取下对象也没有', G.CanUndo);
end;

procedure TGridObjectUndoTest.TestUndoingAnAttributeKeepsTheObject;
var
  G: TTyStringGrid;
  p: TPayload;
begin
  G := NewGrid;
  p := NewPayload('x');
  G.Objects[1, 1] := p;
  G.CellColors[1, 1] := $FF00FF00;
  G.ClearUndo;
  G.CellColors[1, 1] := $FF0000FF;
  G.Undo;
  AssertEquals('前置条件:底色退回去了', TTyColor($FF00FF00), G.CellColors[1, 1]);
  AssertTrue('撤销没有碰对象槽', G.Objects[1, 1] = p);
end;

{ 最阴的一条:撤销要还原的是"当时这一格**根本没有**属性记录"。
  从前那条路是整条删掉 —— 而那会把后来挂上去的对象一起删。 }
procedure TGridObjectUndoTest.TestUndoingAnAttributeThatCreatedTheEntryKeepsTheObject;
var
  G: TTyStringGrid;
  p: TPayload;
begin
  G := NewGrid;
  G.ClearUndo;
  G.CellColors[1, 1] := $FF00FF00;      { 这一步**创建**了属性记录 }
  p := NewPayload('later');
  G.Objects[1, 1] := p;                 { 对象挂在同一条记录上 }
  G.Undo;                               { 撤销 = "回到没有这条记录的时候" }
  AssertEquals('前置条件:底色没了', TTyColor(0), G.CellColors[1, 1]);
  AssertTrue('撤销不许销毁宿主挂的对象', G.Objects[1, 1] = p);
end;

{ **一条明确的取舍,不是 bug。** 对象槽不进撤销栈,所以撤销一次**结构性**编辑时
  文字与属性都回到原位,而对象槽停在正向操作把它放下的地方 —— 删行时它们跟着
  上移过,撤销不会把它们移回来。

  这条断言故意钉住"没有移回来":哪天有人把对象记进撤销栈,它会变红,
  逼那个人重新读一遍那个决定(以及它防的 use-after-free)。 }
procedure TGridObjectUndoTest.TestUndoingARowDeleteBringsBackTextButNotObjectSlots;
var
  G: TTyStringGrid;
  pa, pb, pc: TPayload;
begin
  G := NewGrid(3);
  pa := NewPayload('a');  pb := NewPayload('b');  pc := NewPayload('c');
  G.Cells[0, 0] := 'a';   G.Objects[0, 0] := pa;
  G.Cells[0, 1] := 'b';   G.Objects[0, 1] := pb;
  G.Cells[0, 2] := 'c';   G.Objects[0, 2] := pc;
  G.ClearUndo;

  G.DeleteRow(1);
  AssertEquals('前置条件:中间那行删掉了', 'c', G.Cells[0, 1]);
  AssertTrue('前置条件:对象跟着上移了', G.Objects[0, 1] = pc);

  G.Undo;
  AssertEquals('文字全回来了(第 1 行)', 'b', G.Cells[0, 1]);
  AssertEquals('文字全回来了(第 2 行)', 'c', G.Cells[0, 2]);
  AssertTrue('没被搬过的那一行,对象原样', G.Objects[0, 0] = pa);
  AssertTrue('对象槽**没有**跟着撤销回原位 —— 这是取舍,写在 grid.md 里',
    G.Objects[0, 1] <> pb);
end;

{ 这两条都是**取舍**,不是能从代码里读出来的事实:代码只说"当前这样",
  说不出"为什么不那样"。宿主会撞上它们(撤销之后对象槽没归位、赋一个短列表
  尾巴没被清),所以文档里必须写着 —— 与 GridLineStyle 那条分歧同一个道理
  (见 test.parity.grid.pas)。 }
procedure TGridObjectUndoTest.TestTheTwoContractsAreWrittenDown;
var
  doc: TStringList;
  fn, all: string;
begin
  fn := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'docs' + PathDelim
        + 'controls' + PathDelim + 'grid.md';
  AssertTrue('grid.md must exist at ' + fn, FileExists(fn));
  doc := TStringList.Create;
  try
    doc.LoadFromFile(fn);
    all := doc.Text;
    AssertTrue('grid.md 必须写着 Objects[] 不进撤销栈',
      (Pos('Objects', all) > 0) and (Pos('不进撤销栈', all) > 0));
    AssertTrue('grid.md 必须写着 Cols/Rows 赋值不改网格结构',
      (Pos('Cols[', all) > 0) and (Pos('Rows[', all) > 0)
      and (Pos('赋值绝不改网格的结构', all) > 0));
  finally
    doc.Free;
  end;
end;

{ ---- Cols[] / Rows[] ------------------------------------------------------- }

procedure TGridRowColStringsTest.TestRowViewReadsTheRowAndCountsColumns;
var
  G: TTyStringGrid;
  v: TStrings;
begin
  G := NewGrid(6);
  G.Cells[0, 2] := 'a';  G.Cells[1, 2] := 'b';  G.Cells[3, 2] := 'd';
  v := G.Rows[2];
  AssertEquals('行视图的长度 = 列数', 4, v.Count);
  AssertEquals('第 0 列', 'a', v[0]);
  AssertEquals('第 1 列', 'b', v[1]);
  AssertEquals('没写过的格子是空串', '', v[2]);
  AssertEquals('第 3 列', 'd', v[3]);
end;

procedure TGridRowColStringsTest.TestColViewReadsTheColumnAndCountsRows;
var
  G: TTyStringGrid;
  v: TStrings;
begin
  G := NewGrid(6);
  G.Cells[1, 0] := 'r0';  G.Cells[1, 5] := 'r5';
  v := G.Cols[1];
  AssertEquals('列视图的长度 = 行数', 6, v.Count);
  AssertEquals('第 0 行', 'r0', v[0]);
  AssertEquals('第 5 行', 'r5', v[5]);
end;

{ 活视图,不是快照:取过之后网格改了,同一个视图对象要看得见。 }
procedure TGridRowColStringsTest.TestViewIsLiveNotACopy;
var
  G: TTyStringGrid;
  v: TStrings;
begin
  G := NewGrid(6);
  v := G.Cols[0];
  G.Cells[0, 3] := 'later';
  AssertEquals('视图看得见后写进去的值', 'later', v[3]);
  G.RowCount := 9;
  AssertEquals('行数变了,视图长度跟着变', 9, v.Count);
end;

procedure TGridRowColStringsTest.TestWritingThroughTheViewWritesTheCell;
var
  G: TTyStringGrid;
begin
  G := NewGrid(6);
  G.Rows[2][1] := 'through';
  AssertEquals('写视图 = 写格子', 'through', G.Cells[1, 2]);
  G.Cols[3][4] := 'down';
  AssertEquals('列视图同理', 'down', G.Cells[3, 4]);
end;

{ 视图对象归网格所有。同一个下标必须交出**同一个**对象 ——
  每次新建一个就是每次调用泄漏一个。 }
procedure TGridRowColStringsTest.TestSameIndexGivesTheSameViewObject;
var
  G: TTyStringGrid;
begin
  G := NewGrid(6);
  AssertTrue('Rows[2] 两次是同一个对象', G.Rows[2] = G.Rows[2]);
  AssertTrue('Cols[1] 两次是同一个对象', G.Cols[1] = G.Cols[1]);
  AssertTrue('行视图与列视图不是同一个', G.Rows[1] <> G.Cols[1]);
  AssertTrue('不同下标不是同一个', G.Rows[1] <> G.Rows[2]);
end;

procedure TGridRowColStringsTest.TestViewObjectsAreTheCellObjects;
var
  G: TTyStringGrid;
  p: TPayload;
begin
  G := NewGrid(6);
  p := NewPayload('x');
  G.Objects[1, 2] := p;
  AssertTrue('行视图的 Objects[] 就是格对象', G.Rows[2].Objects[1] = p);
  AssertTrue('列视图的 Objects[] 就是格对象', G.Cols[1].Objects[2] = p);
  G.Rows[2].Objects[3] := NewPayload('y');
  AssertTrue('从视图写进去也落到格子上',
    G.Objects[3, 2] = TObject(G.Rows[2].Objects[3]));
  AssertTrue('确实写到了', G.Objects[3, 2] <> nil);
end;

procedure TGridRowColStringsTest.TestAssigningARowCopiesStringsAndObjects;
var
  G: TTyStringGrid;
  src: TStringList;
  p: TPayload;
begin
  G := NewGrid(6);
  p := NewPayload('from-list');
  src := TStringList.Create;
  try
    src.AddObject('w', nil);
    src.AddObject('x', p);
    src.AddObject('y', nil);
    src.AddObject('z', nil);
    G.Rows[3] := src;
  finally
    src.Free;
  end;
  AssertEquals('第 0 列', 'w', G.Cells[0, 3]);
  AssertEquals('第 3 列', 'z', G.Cells[3, 3]);
  AssertTrue('对象也跟着抄过来了', G.Objects[1, 3] = p);
  AssertEquals('别的行没被碰', '', G.Cells[0, 2]);
end;

{ **明确的约定**:源比视图短时,多出来的那一段**原样留着**,不清空。
  逐字照 LCL(grids.pas:10882)—— 移植过来的代码依赖的正是这个行为,
  "赋一个短列表"在那边从来就不是"整行换掉"。 }
procedure TGridRowColStringsTest.TestAssigningAShorterListLeavesTheTailAlone;
var
  G: TTyStringGrid;
  src: TStringList;
begin
  G := NewGrid(6);
  G.Cells[0, 3] := 'old0';
  G.Cells[1, 3] := 'old1';
  G.Cells[2, 3] := 'old2';
  G.Cells[3, 3] := 'old3';
  src := TStringList.Create;
  try
    src.Add('new0');
    src.Add('new1');
    G.Rows[3] := src;
  finally
    src.Free;
  end;
  AssertEquals('覆盖了第 0 列', 'new0', G.Cells[0, 3]);
  AssertEquals('覆盖了第 1 列', 'new1', G.Cells[1, 3]);
  AssertEquals('第 2 列原样留着', 'old2', G.Cells[2, 3]);
  AssertEquals('第 3 列原样留着', 'old3', G.Cells[3, 3]);
end;

{ 源比视图长时多出来的项丢掉 —— 一次数据赋值绝不许偷偷加列/加行。 }
procedure TGridRowColStringsTest.TestAssigningALongerListIsTruncatedAndNeverGrowsTheGrid;
var
  G: TTyStringGrid;
  src: TStringList;
  i: Integer;
begin
  G := NewGrid(6);
  src := TStringList.Create;
  try
    for i := 0 to 9 do src.Add('v' + IntToStr(i));
    G.Rows[3] := src;
  finally
    src.Free;
  end;
  AssertEquals('列数没变', 4, G.Header.Columns.Count);
  AssertEquals('行数没变', 6, G.RowCount);
  AssertEquals('最后一个装得下的项', 'v3', G.Cells[3, 3]);
end;

procedure TGridRowColStringsTest.TestAssigningAColumnNeverChangesTheRowCount;
var
  G: TTyStringGrid;
  src: TStringList;
  i: Integer;
begin
  G := NewGrid(6);
  G.Cells[2, 5] := 'tail';
  src := TStringList.Create;
  try
    for i := 0 to 19 do src.Add('c' + IntToStr(i));
    G.Cols[2] := src;
  finally
    src.Free;
  end;
  AssertEquals('行数没变', 6, G.RowCount);
  AssertEquals('装得下的最后一行被覆盖了', 'c5', G.Cells[2, 5]);
  AssertEquals('第 0 行', 'c0', G.Cells[2, 0]);
end;

{ `Memo.Lines := Grid.Cols[0]` 这条写法 —— 任何 TStrings 消费者都该收得下视图。 }
procedure TGridRowColStringsTest.TestAnyTStringsConsumerCanBeFilledFromAView;
var
  G: TTyStringGrid;
  dst: TStringList;
  p: TPayload;
begin
  G := NewGrid(4);
  p := NewPayload('carried');
  G.Cells[0, 0] := 'a';
  G.Cells[0, 2] := 'c';
  G.Objects[0, 2] := p;
  dst := TStringList.Create;
  try
    dst.Assign(G.Cols[0]);
    AssertEquals('每一行一条', 4, dst.Count);
    AssertEquals('第 0 行', 'a', dst[0]);
    AssertEquals('空行也占一条', '', dst[1]);
    AssertEquals('第 2 行', 'c', dst[2]);
    AssertTrue('对象也被读了出来', dst.Objects[2] = p);
  finally
    dst.Free;
  end;
end;

{ CommaText 的赋值走的是 Clear + Add,所以 Add 必须"往下一个空槽写"
  而不是抛异常。

  **第二遍是关键的一半**:视图对象是按下标缓存的,同一个下标每次拿到的是
  同一个实例,于是 Add 的游标是**跨调用留着的** —— Clear 不把它归零的话,
  第二次赋值一个字都写不进去(视图看着"已经写满了")。
  只赋一次的测试逮不到这条:新视图的游标本来就是 0。 }
procedure TGridRowColStringsTest.TestCommaTextFillsFromTheStart;
var
  G: TTyStringGrid;
begin
  G := NewGrid(6);
  G.Cells[3, 1] := 'stale';
  G.Rows[1].CommaText := 'p,q,r';
  AssertEquals('第 0 列', 'p', G.Cells[0, 1]);
  AssertEquals('第 1 列', 'q', G.Cells[1, 1]);
  AssertEquals('第 2 列', 'r', G.Cells[2, 1]);
  AssertEquals('Clear 把整行都擦了,第 3 列是空的', '', G.Cells[3, 1]);
  AssertEquals('读回来是同一串', 'p,q,r,', G.Rows[1].CommaText);

  { 再来一遍 —— 同一个缓存视图,必须照样从第 0 列开始填。 }
  G.Rows[1].CommaText := 'x,y';
  AssertEquals('第二遍也从头填(第 0 列)', 'x', G.Cells[0, 1]);
  AssertEquals('第二遍也从头填(第 1 列)', 'y', G.Cells[1, 1]);
  AssertEquals('第二遍的 Clear 把上一遍的第 2 列擦了', '', G.Cells[2, 1]);
end;

procedure TGridRowColStringsTest.TestClearBlanksTheWholeLineAndItsObjects;
var
  G: TTyStringGrid;
  i: Integer;
begin
  G := NewGrid(6);
  for i := 0 to 3 do
  begin
    G.Cells[i, 2] := 'x' + IntToStr(i);
    G.Objects[i, 2] := NewPayload('o' + IntToStr(i));
  end;
  G.Cells[0, 3] := 'neighbour';
  G.Rows[2].Clear;
  for i := 0 to 3 do
  begin
    AssertEquals(Format('第 %d 列的文字清了', [i]), '', G.Cells[i, 2]);
    AssertTrue(Format('第 %d 列的对象也清了', [i]), G.Objects[i, 2] = nil);
  end;
  AssertEquals('邻行没被碰', 'neighbour', G.Cells[0, 3]);
end;

{ 视图的长度就是网格的结构 —— 改长度得走 InsertRow / Columns.Add,
  不能从一个 TStrings 视图上偷偷改掉。与 LCL 一致(grids.pas:10902/10907)。 }
procedure TGridRowColStringsTest.TestInsertAndDeleteAreRefused;
var
  G: TTyStringGrid;
  raised1, raised2: Boolean;
begin
  G := NewGrid(6);
  raised1 := False;
  try
    G.Rows[1].Insert(0, 'nope');
  except
    on E: EListError do raised1 := True;
  end;
  AssertTrue('Insert 被拒', raised1);

  raised2 := False;
  try
    G.Cols[1].Delete(0);
  except
    on E: EListError do raised2 := True;
  end;
  AssertTrue('Delete 被拒', raised2);
  AssertEquals('行数一根没动', 6, G.RowCount);
  AssertEquals('列数一根没动', 4, G.Header.Columns.Count);
end;

procedure TGridRowColStringsTest.TestOutOfRangeReadsEmptyAndOutOfRangeWriteRaises;
var
  G: TTyStringGrid;
  raised: Boolean;
begin
  G := NewGrid(6);
  AssertEquals('越界读给空串', '', G.Rows[1][9]);
  AssertTrue('越界读对象给 nil', G.Rows[1].Objects[9] = nil);
  raised := False;
  try
    G.Rows[1][9] := 'x';
  except
    on E: EListError do raised := True;
  end;
  AssertTrue('越界写要吭声', raised);
end;

{ 整行赋值是一批改动,一次 Ctrl+Z 就该全退回去(与粘贴、填充同一条规矩)。 }
procedure TGridRowColStringsTest.TestWholeRowAssignmentIsOneUndoStep;
var
  G: TTyStringGrid;
  src: TStringList;
begin
  G := NewGrid(6);
  G.Cells[0, 2] := 'a';
  G.Cells[1, 2] := 'b';
  G.ClearUndo;
  src := TStringList.Create;
  try
    src.Add('A');
    src.Add('B');
    src.Add('C');
    src.Add('D');
    G.Rows[2] := src;
  finally
    src.Free;
  end;
  AssertEquals('前置条件:写进去了', 'A', G.Cells[0, 2]);
  G.Undo;
  AssertEquals('一次撤销退回第 0 列', 'a', G.Cells[0, 2]);
  AssertEquals('一次撤销退回第 1 列', 'b', G.Cells[1, 2]);
  AssertEquals('一次撤销退回第 2 列', '', G.Cells[2, 2]);
  AssertEquals('一次撤销退回第 3 列', '', G.Cells[3, 2]);
end;

{ ---- 代价 ------------------------------------------------------------------ }

{ 往稀疏记录里加一个字段,**每一条有属性的记录**都要付。量出来:
  一个指针,不多不少 —— 没有隐藏的 Boolean 伴随位(nil 本身就是"没有")。

  这条会随着 TTyGridCellAttr 加字段而变红,那正是它的用处:
  下一个往这条记录里塞东西的人得先看见代价。 }
procedure TGridCellAttrCostTest.TestObjectSlotAddsOnePointerToTheAttrRecord;
begin
  { 同一个编译器、同一套对齐规则下量的两个 InstanceSize —— TObject 的那份
    开销在两边都有,相减正好剩下对象槽自己的净代价:**一个指针,不多不少**。
    (没有伴随的 Has 标志:nil 本身就是"没有"。)

    失败时消息里带着两个实测值,直接就是"现在到底多大"的答案。 }
  AssertEquals(Format(
      '对象槽的净代价必须正好是一个指针(不带 Has 标志)。'
    + '实测:带 Obj 的 %d 字节,不带的 %d 字节',
      [TTyGridCellAttr.InstanceSize, TAttrLayoutWithoutObject.InstanceSize]),
    TAttrLayoutWithoutObject.InstanceSize + SizeOf(Pointer),
    TTyGridCellAttr.InstanceSize);
end;

procedure TGridCellAttrCostTest.TestAnObjectAloneIsNotADefaultAttr;
var
  a: TTyGridCellAttr;
  probe: TObject;
begin
  probe := TObject.Create;
  a := TTyGridCellAttr.Create;
  try
    AssertTrue('刚建出来是全默认值', a.IsDefault);
    a.Obj := probe;
    AssertFalse('挂了对象就不再是"可以丢掉的默认记录"', a.IsDefault);
    a.Obj := nil;
    AssertTrue('取下来又变回默认值', a.IsDefault);
  finally
    a.Free;
    probe.Free;
  end;
end;

initialization
  RegisterTest(TGridCellObjectTest);
  RegisterTest(TGridObjectUndoTest);
  RegisterTest(TGridRowColStringsTest);
  RegisterTest(TGridCellAttrCostTest);
end.
