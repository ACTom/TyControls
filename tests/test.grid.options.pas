unit test.grid.options;
{ TTyCustomGrid.Options —— 对标 LCL 的 TCustomGrid.Options(grids.pas:1280)。

  这个单元守的不是"属性存在",而是一个集合属性**最容易变成谎话**的四件事:

  一、**发布了却不照办**。集合属性是这个缺陷的重灾区:加一个成员只要改一行,
      而让它真的管用要改绘制/命中/键盘三条路。所以这里有一条
      NoInertOptionMembers —— 它逐个成员去 source 里找强制点,
      找不到就红。加成员却忘了接线,当场就知道。

  二、**一个行为两处存储**。Options 里有一半的位在别处早就有名字了
      (goColSizing 就是 Header.Options 里的 hoColumnResize,goEditing 就是
      ReadOnly 取反……)。这些位必须是**视图**:改名字那边,Options 立刻跟着变;
      改 Options,名字那边立刻跟着变。两个方向各有一条断言,一个都不能少 ——
      只测一个方向的话,"写进去了但读的是副本"这种错法照样全绿。

  三、**三态被压成两态**。SelectionMode 有 gsmCell/gsmRow/gsmColumn 三档,
      而 goRowSelect 只有两档。设计器每次流式化都会做一次
      `Options := Options`,无条件写回的话那一下就把 gsmColumn 压成 gsmCell。
      NoOpWriteKeepsColumnSelection 专钉这一条。

  四、**序号乱掉**。见 OptionOrdinalsAreAppendOnly 的注释 —— 那里同时纠正了
      一个流传的说法(.lfm 里集合按序号存)。

  剩下的是逐个标志的行为断言:每一个自有存储的标志,开与关必须让控件做出
  **看得见的**不同的事。 }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, StrUtils, Types, TypInfo, Controls, Forms, Graphics, LCLType,
  BGRABitmap, BGRABitmapTypes,
  fpcunit, testregistry,
  tyControls.Types, tyControls.Controller, tyControls.Columns, tyControls.Grid;

type
  { 只开必要的口子。刻意不去复用 test.grid.pas 里那个大 accessor:
    那一个是为别的题目长出来的,跟着它走会让这个单元的失败信息指向不相干的地方。 }
  TOptGrid = class(TTyStringGrid)
  public
    function  StoredOptionBits: TTyGridOptions;
    function  CellRectOf(ACol, ARow: Integer): TRect;
    function  HeaderH: Integer;
    function  RowDividerHit(AX, AY: Integer): Integer;
    function  DividerHit(AX: Integer): Integer;
    function  AppearanceOf(ACol, ARow: Integer): TTyGridCellAppearance;
    function  IndicatorLeft: Integer;
    function  TruncHintOf(ACol, ARow: Integer): string;
    { 返回 True = 这一下被网格吃掉了(Key 置 0)。 }
    function  PressKey(AKey: Word; AShift: TShiftState): Boolean;
    procedure ClickAt(X, Y: Integer);
    procedure DragFromTo(X1, Y1, X2, Y2: Integer);
    procedure DoubleClickDivider(X, Y: Integer);
    procedure HoverAt(X, Y: Integer);
    procedure RenderInto(ABmp: TBGRABitmap);
  end;

  TGridOptionsTest = class(TTestCase)
  protected
    FForm: TForm;
    FGrid: TOptGrid;
    procedure SetUp; override;
    procedure TearDown; override;
    { 建一张 ACols 列 x ARows 行、每列 AColWidth 宽的表。 }
    procedure Build(ACols, ARows, AColWidth: Integer);
  published
    { --- 类型纪律 --- }
    procedure TestOptionOrdinalsAreAppendOnly;
    procedure TestSetsStreamByNameNotByOrdinal;
    procedure TestNoInertOptionMembers;
    { --- 出厂值 --- }
    procedure TestDefaultsMatchAFreshStringGrid;
    procedure TestDefaultsMatchAFreshDrawGrid;
    procedure TestDefaultsAgreeWithTheNamedProperties;
    { --- 视图:两个方向 --- }
    procedure TestGridLineStyleIsOneStateWithOptions;
    procedure TestHeaderOptionsAreOneStateWithOptions;
    procedure TestReadOnlyIsOneStateWithGoEditing;
    procedure TestSelectionModeIsOneStateWithGoRowSelect;
    procedure TestShowRowNumbersIsOneStateWithOptions;
    procedure TestShowFocusCellIsOneStateWithOptions;
    procedure TestNoOpWriteKeepsColumnSelection;
    procedure TestDerivedBitsAreNeverCached;
    { --- 行为 --- }
    procedure TestRangeSelectGatesDragSelection;
    procedure TestRangeSelectGatesDiscontiguousBlocks;
    procedure TestRangeSelectGatesShiftArrow;
    procedure TestRowSizingGatesTheRowDivider;
    procedure TestRowMovingGatesTheRowDrag;
    procedure TestDblClickAutoSizeGatesTheAutoFit;
    procedure TestFixedColSizingGatesFrozenColumnDividers;
    procedure TestTabsGatesWhoGetsTheTabKey;
    procedure TestDontScrollPartCellGatesTheClickScroll;
    procedure TestScrollKeepVisibleDragsTheCursorAlong;
    procedure TestCellEllipsisGatesTheTrailingDots;
    procedure TestCellHintsIsTheMasterSwitch;
    procedure TestTruncCellHintsShowsTheFullText;
    procedure TestRowHighlightPaintsTheWholeRow;
    procedure TestHeaderPushedLookGatesThePressedFill;
    { --- 流式化 --- }
    procedure TestOptionsSurviveARoundTrip;
    procedure TestOldLfmWithOnlyTheNamedPropertyStillLoads;
  end;

implementation

const
  { 每一个成员在 source 里的强制点长什么样。**自有存储**的位一律是
    `<名字> in Options`;**派生**的位不出现在那种表达式里(它们的强制点是
    早就存在的 hoColumnResize / FReadOnly / FSelectionMode 检查),所以
    NoInertOptionMembers 对它们只要求"确实登记在 TyGridDerivedOptions 里"。 }
  GridUnitRelPath = 'source' + PathDelim + 'tyControls.Grid.pas';

function RepoRoot: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim;
end;

{ ---- TOptGrid ---- }

function TOptGrid.StoredOptionBits: TTyGridOptions;
begin
  Result := FOptions;
end;

function TOptGrid.CellRectOf(ACol, ARow: Integer): TRect;
begin
  Result := CellRect(ACol, ARow);
end;

function TOptGrid.HeaderH: Integer;
begin
  Result := HeaderHeightPx;
end;

function TOptGrid.RowDividerHit(AX, AY: Integer): Integer;
begin
  Result := RowDividerAtY(AX, AY);
end;

function TOptGrid.DividerHit(AX: Integer): Integer;
begin
  Result := DividerAtX(AX);
end;

function TOptGrid.AppearanceOf(ACol, ARow: Integer): TTyGridCellAppearance;
begin
  Result := CellAppearance(ACol, ARow, DataToDisplay(ARow), CurrentStyle);
end;

function TOptGrid.IndicatorLeft: Integer;
var
  l, r: Integer;
begin
  if IndicatorBandX(l, r) then Result := l else Result := -1;
end;

function TOptGrid.TruncHintOf(ACol, ARow: Integer): string;
begin
  Result := TruncatedCellHint(ACol, ARow);
end;

function TOptGrid.PressKey(AKey: Word; AShift: TShiftState): Boolean;
var
  k: Word;
begin
  k := AKey;
  KeyDown(k, AShift);
  Result := k = 0;
end;

procedure TOptGrid.ClickAt(X, Y: Integer);
begin
  MouseDown(mbLeft, [], X, Y);
  MouseUp(mbLeft, [], X, Y);
end;

procedure TOptGrid.DragFromTo(X1, Y1, X2, Y2: Integer);
begin
  MouseDown(mbLeft, [], X1, Y1);
  MouseMove([ssLeft], X2, Y2);
  MouseUp(mbLeft, [], X2, Y2);
end;

procedure TOptGrid.DoubleClickDivider(X, Y: Integer);
begin
  MouseDown(mbLeft, [], X, Y);
  MouseUp(mbLeft, [], X, Y);
  { LCL 在第二次按下时把 ssDouble 塞进 Shift。 }
  MouseDown(mbLeft, [ssDouble], X, Y);
  MouseUp(mbLeft, [], X, Y);
end;

{ 提示那条路上有一道**换格才重问**的闸(FHintCol/FHintRow)。同一格里挪几个
  像素是问不出新提示的 —— 所以这里先去别处晃一下再回来,把闸复位。
  第一版测试就栽在这上面:改了批注却还是拿到上一次的答案。 }
procedure TOptGrid.HoverAt(X, Y: Integer);
begin
  MouseMove([], 0, 0);           { 先离开当前格(左上角是列头/槽,不是格) }
  MouseMove([], X, Y);
end;

procedure TOptGrid.RenderInto(ABmp: TBGRABitmap);
var
  bmp: TBitmap;
begin
  bmp := TBitmap.Create;
  try
    bmp.SetSize(Width, Height);
    RenderTo(bmp.Canvas, Rect(0, 0, Width, Height), 96);
    ABmp.SetSize(Width, Height);
    ABmp.Canvas.Draw(0, 0, bmp);
  finally
    bmp.Free;
  end;
end;

{ ---- fixture ---- }

procedure TGridOptionsTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 700, 500);
end;

procedure TGridOptionsTest.TearDown;
begin
  FreeAndNil(FForm);
  FGrid := nil;
end;

procedure TGridOptionsTest.Build(ACols, ARows, AColWidth: Integer);
var
  i: Integer;
  c: TTyColumn;
begin
  FGrid := TOptGrid.Create(FForm);
  FGrid.Parent := FForm;
  FGrid.Font.PixelsPerInch := 96;
  FGrid.SetBounds(0, 0, 400, 240);
  for i := 0 to ACols - 1 do
  begin
    c := FGrid.Header.Columns.Add as TTyColumn;
    c.Width := AColWidth;
    c.Text := 'C' + IntToStr(i);
  end;
  FGrid.RowCount := ARows;
end;

{ ================= 类型纪律 ================= }

{ 序号是**只增不改**的。每一个成员的 Ord 写死在这里,连总数一起。

  为什么值得写死:插一个成员进中间会让它后面每一位的序号整体挪一格,
  而序号被两处吃进去 —— 编译期的 `default TyDefaultGridOptions` 子句,
  以及任何 `Integer(Options)` 式的强转/持久化。

  **顺带纠正一个说法**:.lfm 里集合**不是**按序号存的。TWriter.WriteSet 走
  GetEnumName,写出去的是 `Options = [goVertLine, goHorzLine]` 这样的名字
  (下面那条 SetsStreamByNameNotByOrdinal 是实证)。所以真正会让老窗体读不进来的
  是**改名和删名**,不是重排。两种危险合起来仍然只有一条纪律:只在末尾追加。 }
procedure TGridOptionsTest.TestOptionOrdinalsAreAppendOnly;
begin
  AssertEquals('goVertLine',            0,  Ord(goVertLine));
  AssertEquals('goHorzLine',            1,  Ord(goHorzLine));
  AssertEquals('goRangeSelect',         2,  Ord(goRangeSelect));
  AssertEquals('goDrawFocusSelected',   3,  Ord(goDrawFocusSelected));
  AssertEquals('goRowSizing',           4,  Ord(goRowSizing));
  AssertEquals('goColSizing',           5,  Ord(goColSizing));
  AssertEquals('goRowMoving',           6,  Ord(goRowMoving));
  AssertEquals('goColMoving',           7,  Ord(goColMoving));
  AssertEquals('goEditing',             8,  Ord(goEditing));
  AssertEquals('goTabs',                9,  Ord(goTabs));
  AssertEquals('goRowSelect',           10, Ord(goRowSelect));
  AssertEquals('goDblClickAutoSize',    11, Ord(goDblClickAutoSize));
  AssertEquals('goFixedRowNumbering',   12, Ord(goFixedRowNumbering));
  AssertEquals('goScrollKeepVisible',   13, Ord(goScrollKeepVisible));
  AssertEquals('goHeaderHotTracking',   14, Ord(goHeaderHotTracking));
  AssertEquals('goFixedColSizing',      15, Ord(goFixedColSizing));
  AssertEquals('goDontScrollPartCell',  16, Ord(goDontScrollPartCell));
  AssertEquals('goCellHints',           17, Ord(goCellHints));
  AssertEquals('goTruncCellHints',      18, Ord(goTruncCellHints));
  AssertEquals('goCellEllipsis',        19, Ord(goCellEllipsis));
  AssertEquals('goRowHighlight',        20, Ord(goRowHighlight));
  AssertEquals('goHeaderPushedLook',    21, Ord(goHeaderPushedLook));
  { 总数。新成员追加在末尾时这一行也要动 —— 那正是提醒"你在改一个流式化过的
    类型"的时刻。 }
  AssertEquals('成员总数', 22, Ord(High(TTyGridOption)) + 1);
end;

{ 实证上一条注释里的说法:写出去的 .lfm 里是**名字**。

  这条不是学术兴趣。它决定了两件相反的事该怕哪一件:
  重排成员 —— 不怕(名字没变);改名/删名 —— 很怕(老窗体加载时直接抛)。 }
procedure TGridOptionsTest.TestSetsStreamByNameNotByOrdinal;
var
  ms: TMemoryStream;
  txt: TStringStream;
  s: string;
begin
  Build(3, 5, 80);
  { 挑一个与出厂值不同的集合,否则 TWriter 会把整行略掉。 }
  FGrid.Options := FGrid.Options - [goTabs] + [goRowHighlight];
  FGrid.Name := 'G';

  ms := TMemoryStream.Create;
  txt := TStringStream.Create('');
  try
    ms.WriteComponent(FGrid);
    ms.Position := 0;
    ObjectBinaryToText(ms, txt);
    s := txt.DataString;
  finally
    txt.Free;
    ms.Free;
  end;

  AssertTrue('Options 应当被写进流(它已不等于出厂值)', Pos('Options', s) > 0);
  AssertTrue('集合成员按**名字**写出:应能看到 goRowHighlight',
    Pos('goRowHighlight', s) > 0);
  AssertTrue('被去掉的成员不该出现:goTabs', Pos('goTabs', s) = 0);
end;

{ **没有摆设成员。**

  逐个成员去 source/tyControls.Grid.pas 里找强制点:
    - 自有存储的位:必须出现 `<名字> in Options`(或 `in FOptions`);
    - 派生位:必须登记在 TyGridDerivedOptions 那个常量里 —— 它们的强制点是
      hoColumnResize / FReadOnly / FSelectionMode 那些早就存在的检查。

  这一条是 LyingPropertiesStayUnpublished 在集合上的对应物。加一个成员却忘了
  接线时,它是唯一会响的东西 —— 而"加一个成员"只要一行,太容易了。 }
procedure TGridOptionsTest.TestNoInertOptionMembers;
var
  src: TStringList;
  body, derivedBlock, nm: string;
  o: TTyGridOption;
  p1, p2: Integer;
  missing: TStringList;
begin
  src := TStringList.Create;
  missing := TStringList.Create;
  try
    src.LoadFromFile(RepoRoot + GridUnitRelPath);
    body := src.Text;

    { 只取 TyGridDerivedOptions 那个常量的字面量,免得把别处偶然提到的名字算进来。 }
    p1 := Pos('TyGridDerivedOptions =', body);
    AssertTrue('source 里应当有 TyGridDerivedOptions 常量', p1 > 0);
    p2 := PosEx(';', body, p1);
    AssertTrue('TyGridDerivedOptions 常量应当以分号收尾', p2 > p1);
    derivedBlock := Copy(body, p1, p2 - p1);

    for o := Low(TTyGridOption) to High(TTyGridOption) do
    begin
      nm := GetEnumName(TypeInfo(TTyGridOption), Ord(o));
      if Pos(nm, derivedBlock) > 0 then Continue;   { 派生位:强制点在别的名字上 }
      if (Pos(nm + ' in Options', body) > 0)
         or (Pos(nm + ' in FOptions', body) > 0) then Continue;
      missing.Add(nm);
    end;

    AssertEquals('这些成员在 source 里既不是派生位、也找不到 `X in Options` 强制点'
      + ' —— 加了成员忘了接线:' + missing.CommaText, 0, missing.Count);
  finally
    missing.Free;
    src.Free;
  end;
end;

{ ================= 出厂值 ================= }

procedure TGridOptionsTest.TestDefaultsMatchAFreshStringGrid;
begin
  Build(3, 5, 80);
  AssertTrue('新建的 TTyStringGrid 读出来必须**逐位**等于 default 子句里那个常量'
    + ' —— 不等的话 TWriter 要么漏写(窗体丢设置)要么每张窗体都多写一行',
    FGrid.Options = TyDefaultGridOptions);
end;

{ 基类那条路也要走一遍:goEditing / goRowSelect 在 TTyDrawGrid 上落在基类的
  常量实现(永远可编辑、永远按格选)。两个类的读数必须都等于同一个 default ——
  不然其中一个类的 .lfm 会莫名其妙多出一行 Options。 }
procedure TGridOptionsTest.TestDefaultsMatchAFreshDrawGrid;
var
  g: TTyDrawGrid;
begin
  g := TTyDrawGrid.Create(FForm);
  g.Parent := FForm;
  AssertTrue('新建的 TTyDrawGrid 也必须等于同一个出厂集合',
    g.Options = TyDefaultGridOptions);
end;

{ 出厂值必须**描述现状**,不是偷偷改现状。逐条对照具名属性。 }
procedure TGridOptionsTest.TestDefaultsAgreeWithTheNamedProperties;
begin
  Build(3, 5, 80);
  AssertTrue('GridLineStyle 出厂 glsBoth → 两条线都在',
    (goVertLine in FGrid.Options) and (goHorzLine in FGrid.Options));
  AssertTrue('ShowFocusCell 出厂 True → goDrawFocusSelected 在',
    goDrawFocusSelected in FGrid.Options);
  AssertTrue('Header 出厂含 hoColumnResize → goColSizing 在',
    goColSizing in FGrid.Options);
  AssertTrue('Header 出厂含 hoDrag → goColMoving 在',
    goColMoving in FGrid.Options);
  AssertFalse('Header 出厂**不含** hoHotTrack → goHeaderHotTracking 不在',
    goHeaderHotTracking in FGrid.Options);
  AssertTrue('ReadOnly 出厂 False → goEditing 在', goEditing in FGrid.Options);
  AssertFalse('SelectionMode 出厂 gsmCell → goRowSelect 不在',
    goRowSelect in FGrid.Options);
  AssertFalse('ShowRowNumbers 出厂 False → goFixedRowNumbering 不在',
    goFixedRowNumbering in FGrid.Options);
  { 这个观感以前根本不存在,所以出厂必须是关的 —— 出厂值描述现状,不改现状。 }
  AssertFalse('goHeaderPushedLook 出厂不在(以前没有"按下去"的观感)',
    goHeaderPushedLook in FGrid.Options);
  { 而且它是**自有位**,不是视图:没有第二个属性表达同一件事,所以它必须
    躺在 FOptions 里,且不许被登记成派生位。 }
  AssertFalse('goHeaderPushedLook 不是派生位',
    goHeaderPushedLook in TyGridDerivedOptions);
  { 派生位一个都不许躺在自有存储里 —— 躺进去就是那份会发霉的副本。 }
  AssertTrue('FOptions 里不该含任何派生位',
    (FGrid.StoredOptionBits * TyGridDerivedOptions) = []);
end;

{ ================= 视图:两个方向 ================= }

procedure TGridOptionsTest.TestGridLineStyleIsOneStateWithOptions;
begin
  Build(3, 5, 80);

  { 方向一:改具名属性 → Options 立刻跟着变。 }
  FGrid.GridLineStyle := glsHorizontal;
  AssertFalse('GridLineStyle := glsHorizontal 之后 goVertLine 必须没了',
    goVertLine in FGrid.Options);
  AssertTrue('…而 goHorzLine 还在', goHorzLine in FGrid.Options);

  FGrid.GridLineStyle := glsNone;
  AssertTrue('glsNone → 两位都没', (FGrid.Options * [goVertLine, goHorzLine]) = []);

  { 方向二:改 Options → 具名属性立刻跟着变。 }
  FGrid.Options := FGrid.Options + [goVertLine];
  AssertTrue('只加回 goVertLine → glsVertical',
    FGrid.GridLineStyle = glsVertical);
  FGrid.Options := FGrid.Options + [goHorzLine];
  AssertTrue('两位都在 → glsBoth', FGrid.GridLineStyle = glsBoth);
  FGrid.Options := FGrid.Options - [goVertLine];
  AssertTrue('只剩 goHorzLine → glsHorizontal',
    FGrid.GridLineStyle = glsHorizontal);
end;

procedure TGridOptionsTest.TestHeaderOptionsAreOneStateWithOptions;
begin
  Build(3, 5, 80);

  FGrid.Header.Options := FGrid.Header.Options - [hoColumnResize];
  AssertFalse('去掉 hoColumnResize → goColSizing 没了',
    goColSizing in FGrid.Options);
  FGrid.Header.Options := FGrid.Header.Options - [hoDrag];
  AssertFalse('去掉 hoDrag → goColMoving 没了', goColMoving in FGrid.Options);
  FGrid.Header.Options := FGrid.Header.Options + [hoHotTrack];
  AssertTrue('加上 hoHotTrack → goHeaderHotTracking 有了',
    goHeaderHotTracking in FGrid.Options);

  FGrid.Options := FGrid.Options + [goColSizing];
  AssertTrue('加回 goColSizing → Header 里 hoColumnResize 回来了',
    hoColumnResize in FGrid.Header.Options);
  FGrid.Options := FGrid.Options + [goColMoving];
  AssertTrue('加回 goColMoving → hoDrag 回来了', hoDrag in FGrid.Header.Options);
  FGrid.Options := FGrid.Options - [goHeaderHotTracking];
  AssertFalse('去掉 goHeaderHotTracking → hoHotTrack 没了',
    hoHotTrack in FGrid.Header.Options);
end;

procedure TGridOptionsTest.TestReadOnlyIsOneStateWithGoEditing;
begin
  Build(3, 5, 80);
  FGrid.ReadOnly := True;
  AssertFalse('ReadOnly := True → goEditing 没了', goEditing in FGrid.Options);
  FGrid.ReadOnly := False;
  AssertTrue('ReadOnly := False → goEditing 回来', goEditing in FGrid.Options);

  FGrid.Options := FGrid.Options - [goEditing];
  AssertTrue('去掉 goEditing → ReadOnly 变 True', FGrid.ReadOnly);
  { 而且是**真的**只读 —— 不只是一个布尔翻了个个儿。 }
  AssertFalse('只读之后 BeginEdit 必须进不去', FGrid.BeginEdit);

  FGrid.Options := FGrid.Options + [goEditing];
  AssertFalse('加回 goEditing → ReadOnly 变 False', FGrid.ReadOnly);
end;

procedure TGridOptionsTest.TestSelectionModeIsOneStateWithGoRowSelect;
begin
  Build(3, 5, 80);
  FGrid.SelectionMode := gsmRow;
  AssertTrue('SelectionMode := gsmRow → goRowSelect 有了',
    goRowSelect in FGrid.Options);
  FGrid.SelectionMode := gsmCell;
  AssertFalse('回到 gsmCell → goRowSelect 没了', goRowSelect in FGrid.Options);

  FGrid.Options := FGrid.Options + [goRowSelect];
  AssertTrue('加 goRowSelect → SelectionMode 变 gsmRow',
    FGrid.SelectionMode = gsmRow);
  FGrid.Options := FGrid.Options - [goRowSelect];
  AssertTrue('去掉 goRowSelect → SelectionMode 变 gsmCell',
    FGrid.SelectionMode = gsmCell);
end;

{ **三态压两态的那个坑。**

  设计器每次流式化都会写一次 Options,读回来时就是一次
  `Options := <与当前相同的值>`。若 SetOptions 无条件把 goRowSelect 那一位
  写回 SelectionMode,这一下就会把 gsmColumn 压成 gsmCell —— 用户设的"按列选"
  在保存/重开之后莫名其妙变回按格选,而且没有任何报错。 }
procedure TGridOptionsTest.TestNoOpWriteKeepsColumnSelection;
begin
  Build(3, 5, 80);
  FGrid.SelectionMode := gsmColumn;
  AssertFalse('gsmColumn 下 goRowSelect 读出来是 False',
    goRowSelect in FGrid.Options);

  { 无变化的一次写 —— 正是流式化会做的那一下。 }
  FGrid.Options := FGrid.Options;
  AssertTrue('无变化的写不许动 SelectionMode', FGrid.SelectionMode = gsmColumn);

  { 动别的位也不许殃及它。 }
  FGrid.Options := FGrid.Options + [goRowHighlight];
  AssertTrue('改别的位时 gsmColumn 仍要原封不动',
    FGrid.SelectionMode = gsmColumn);

  { 真的翻这一位时才动 —— 而且答案是明确的。 }
  FGrid.Options := FGrid.Options + [goRowSelect];
  AssertTrue('显式加 goRowSelect → gsmRow', FGrid.SelectionMode = gsmRow);
end;

{ 派生位在 FOptions 里**不留副本**。直接把整个出厂集合硬写进去也一样 ——
  存储侧会把派生位滤掉,读回来的仍是现算的。 }
procedure TGridOptionsTest.TestDerivedBitsAreNeverCached;
begin
  Build(3, 5, 80);
  FGrid.Options := [goVertLine, goHorzLine, goColSizing, goEditing,
                    goRangeSelect, goCellEllipsis];
  AssertTrue('写进去的派生位不许落到自有存储里',
    (FGrid.StoredOptionBits * TyGridDerivedOptions) = []);

  { 绕过 Options 改具名属性,读数必须立刻跟上 —— 有副本的话这里就会答旧值。 }
  FGrid.GridLineStyle := glsNone;
  AssertTrue('绕过 Options 改 GridLineStyle 之后,两条线位必须都没了',
    (FGrid.Options * [goVertLine, goHorzLine]) = []);
  FGrid.Header.Options := FGrid.Header.Options - [hoColumnResize];
  AssertFalse('绕过 Options 改 Header.Options 之后 goColSizing 必须没了',
    goColSizing in FGrid.Options);
end;

procedure TGridOptionsTest.TestShowRowNumbersIsOneStateWithOptions;
begin
  Build(3, 5, 80);
  FGrid.ShowRowNumbers := True;
  AssertTrue('ShowRowNumbers → goFixedRowNumbering',
    goFixedRowNumbering in FGrid.Options);
  FGrid.Options := FGrid.Options - [goFixedRowNumbering];
  AssertFalse('去掉 goFixedRowNumbering → ShowRowNumbers 变 False',
    FGrid.ShowRowNumbers);
end;

procedure TGridOptionsTest.TestShowFocusCellIsOneStateWithOptions;
begin
  Build(3, 5, 80);
  FGrid.ShowFocusCell := False;
  AssertFalse('ShowFocusCell := False → goDrawFocusSelected 没了',
    goDrawFocusSelected in FGrid.Options);
  FGrid.Options := FGrid.Options + [goDrawFocusSelected];
  AssertTrue('加回 goDrawFocusSelected → ShowFocusCell 变 True',
    FGrid.ShowFocusCell);
end;

{ ================= 行为 ================= }

{ 拖选:开着能拉出一块,关掉只剩当前格(光标仍然跟着走 —— 那是"点着走"的手感)。 }
procedure TGridOptionsTest.TestRangeSelectGatesDragSelection;
var
  r1, r2: TRect;
  x1, y1, x2, y2: Integer;
begin
  Build(3, 6, 80);
  r1 := FGrid.CellRectOf(0, 0);
  r2 := FGrid.CellRectOf(2, 3);
  x1 := (r1.Left + r1.Right) div 2;  y1 := (r1.Top + r1.Bottom) div 2;
  x2 := (r2.Left + r2.Right) div 2;  y2 := (r2.Top + r2.Bottom) div 2;

  FGrid.DragFromTo(x1, y1, x2, y2);
  AssertEquals('开着时拖出 3 列', 2, FGrid.Selection.Right - FGrid.Selection.Left);
  AssertEquals('开着时拖出 4 行', 3, FGrid.Selection.Bottom - FGrid.Selection.Top);

  FGrid.Options := FGrid.Options - [goRangeSelect];
  FGrid.ClickAt(x1, y1);
  FGrid.DragFromTo(x1, y1, x2, y2);
  AssertEquals('关掉后选区宽必须收成 1 格', 0,
    FGrid.Selection.Right - FGrid.Selection.Left);
  AssertEquals('关掉后选区高必须收成 1 格', 0,
    FGrid.Selection.Bottom - FGrid.Selection.Top);
  AssertEquals('但光标仍然跟着走到了拖动终点(列)', 2, FGrid.Col);
  AssertEquals('但光标仍然跟着走到了拖动终点(行)', 3, FGrid.Row);
end;

{ 只挡拖选是不够的:Ctrl+点 会把当前块**固化**成一块离散选区,于是用户仍能
  攒出一把单格 —— "选区永远只有当前格"那句话就不成立了。 }
procedure TGridOptionsTest.TestRangeSelectGatesDiscontiguousBlocks;
var
  r1, r2: TRect;
begin
  Build(3, 6, 80);
  r1 := FGrid.CellRectOf(0, 0);
  r2 := FGrid.CellRectOf(2, 3);

  FGrid.ClickAt((r1.Left + r1.Right) div 2, (r1.Top + r1.Bottom) div 2);
  FGrid.MouseDown(mbLeft, [ssCtrl], (r2.Left + r2.Right) div 2,
    (r2.Top + r2.Bottom) div 2);
  FGrid.MouseUp(mbLeft, [ssCtrl], (r2.Left + r2.Right) div 2,
    (r2.Top + r2.Bottom) div 2);
  AssertEquals('开着时 Ctrl+点 攒出两块', 2, FGrid.SelectedRangeCount);

  FGrid.Options := FGrid.Options - [goRangeSelect];
  FGrid.ClickAt((r1.Left + r1.Right) div 2, (r1.Top + r1.Bottom) div 2);
  FGrid.MouseDown(mbLeft, [ssCtrl], (r2.Left + r2.Right) div 2,
    (r2.Top + r2.Bottom) div 2);
  FGrid.MouseUp(mbLeft, [ssCtrl], (r2.Left + r2.Right) div 2,
    (r2.Top + r2.Bottom) div 2);
  AssertEquals('关掉后 Ctrl+点 也只剩一块', 1, FGrid.SelectedRangeCount);
end;

procedure TGridOptionsTest.TestRangeSelectGatesShiftArrow;
begin
  Build(3, 6, 80);
  FGrid.Col := 0;
  FGrid.Row := 0;
  FGrid.PressKey(VK_DOWN, [ssShift]);
  AssertEquals('Shift+↓ 应当扩出两行', 1,
    FGrid.Selection.Bottom - FGrid.Selection.Top);

  FGrid.Options := FGrid.Options - [goRangeSelect];
  FGrid.Col := 0;
  FGrid.Row := 0;
  FGrid.PressKey(VK_DOWN, [ssShift]);
  AssertEquals('关掉后 Shift+↓ 只移动光标,不扩选', 0,
    FGrid.Selection.Bottom - FGrid.Selection.Top);
  AssertEquals('光标仍然下移了一行', 1, FGrid.Row);
end;

{ 行高分隔线的命中。收口在 RowDividerAtY 上,所以**光标形状与实际动作同源**
  —— 分开写就会出现"指针变了、按下去不动"的假动作。 }
procedure TGridOptionsTest.TestRowSizingGatesTheRowDivider;
var
  y, x: Integer;
  r: TRect;
begin
  Build(3, 6, 80);
  FGrid.ShowIndicator := True;          { 分隔线只在行头槽里认 }
  x := FGrid.IndicatorLeft + 4;
  AssertTrue('行头槽应当存在', FGrid.IndicatorLeft >= 0);
  r := FGrid.CellRectOf(0, 0);
  y := r.Bottom;

  AssertEquals('开着时第 0 行的下边界应当被认成分隔线', 0,
    FGrid.RowDividerHit(x, y));

  FGrid.Options := FGrid.Options - [goRowSizing];
  AssertEquals('关掉后同一个点必须谁也不认(-1)', -1,
    FGrid.RowDividerHit(x, y));
end;

{ 拖行重排。用 OnRowMove 计数而不是比行内容 —— 事件是这个手势唯一的对外证据,
  而且否决路径也走它。 }
type
  TRowMoveCounter = class
  public
    Count: Integer;
    procedure OnMove(Sender: TObject; AFrom, ATo: Integer; var AAllow: Boolean);
  end;

procedure TRowMoveCounter.OnMove(Sender: TObject; AFrom, ATo: Integer;
  var AAllow: Boolean);
begin
  Inc(Count);
  AAllow := True;
end;

procedure TGridOptionsTest.TestRowMovingGatesTheRowDrag;
var
  counter: TRowMoveCounter;
  x, y1, y2: Integer;
  r1, r2: TRect;
begin
  Build(3, 6, 80);
  FGrid.ShowIndicator := True;
  counter := TRowMoveCounter.Create;
  try
    FGrid.OnRowMove := @counter.OnMove;
    x := FGrid.IndicatorLeft + 4;
    r1 := FGrid.CellRectOf(0, 1);
    r2 := FGrid.CellRectOf(0, 3);
    { 从行中间起手 —— 贴边会被行高分隔线抢走。 }
    y1 := (r1.Top + r1.Bottom) div 2;
    y2 := (r2.Top + r2.Bottom) div 2;

    FGrid.DragFromTo(x, y1, x, y2);
    AssertTrue('开着时拖行应当触发 OnRowMove', counter.Count > 0);

    counter.Count := 0;
    FGrid.Options := FGrid.Options - [goRowMoving];
    FGrid.DragFromTo(x, y1, x, y2);
    AssertEquals('关掉后同一次拖动一次都不许触发', 0, counter.Count);
  finally
    FGrid.OnRowMove := nil;
    counter.Free;
  end;
end;

procedure TGridOptionsTest.TestDblClickAutoSizeGatesTheAutoFit;
var
  edgeX, y, before: Integer;
begin
  Build(3, 6, 200);
  FGrid.Cells[0, 0] := 'x';       { 内容很窄 → 自适应会把列**缩小** }
  edgeX := FGrid.CellRectOf(0, 0).Right;
  y := FGrid.HeaderH div 2;
  AssertTrue('列头带应当有高度', FGrid.HeaderH > 0);
  AssertEquals('分隔线命中应当是第 0 列', 0, FGrid.DividerHit(edgeX));

  before := FGrid.Header.Columns.Items[0].Width;
  FGrid.DoubleClickDivider(edgeX, y);
  AssertTrue('开着时双击分隔线应当把列宽改掉',
    FGrid.Header.Columns.Items[0].Width <> before);

  FGrid.Header.Columns.Items[0].Width := 200;
  FGrid.Options := FGrid.Options - [goDblClickAutoSize];
  edgeX := FGrid.CellRectOf(0, 0).Right;
  before := FGrid.Header.Columns.Items[0].Width;
  FGrid.DoubleClickDivider(edgeX, y);
  AssertEquals('关掉后双击不许改列宽', before,
    FGrid.Header.Columns.Items[0].Width);
end;

procedure TGridOptionsTest.TestFixedColSizingGatesFrozenColumnDividers;
var
  frozenEdge, freeEdge: Integer;
begin
  Build(3, 6, 80);
  FGrid.FixedCols := 1;
  frozenEdge := FGrid.CellRectOf(0, 0).Right;

  AssertEquals('开着时冻结列的分隔线要认', 0, FGrid.DividerHit(frozenEdge));

  FGrid.Options := FGrid.Options - [goFixedColSizing];
  AssertEquals('关掉后冻结列的分隔线必须不认', -1, FGrid.DividerHit(frozenEdge));

  { 可滚动列**不受影响** —— 关的是"冻结列也能拖",不是"谁都不能拖"。 }
  freeEdge := FGrid.CellRectOf(1, 0).Right;
  AssertEquals('可滚动列的分隔线仍然要认', 1, FGrid.DividerHit(freeEdge));
end;

{ Tab 归谁。关键在于**Key 有没有被置 0** —— LCL 靠它决定要不要换焦点,
  吞掉了就等于"关了也还是不放行"。 }
procedure TGridOptionsTest.TestTabsGatesWhoGetsTheTabKey;
begin
  Build(3, 6, 80);
  FGrid.Col := 0;
  FGrid.Row := 0;
  AssertTrue('开着时 Tab 必须被网格吃掉', FGrid.PressKey(VK_TAB, []));
  AssertEquals('…并且光标右移一格', 1, FGrid.Col);

  FGrid.Options := FGrid.Options - [goTabs];
  FGrid.Col := 0;
  FGrid.Row := 0;
  AssertFalse('关掉后 Tab 必须放行(Key 不被置 0)', FGrid.PressKey(VK_TAB, []));
  AssertEquals('…而且不许再动光标', 0, FGrid.Col);
end;

{ 点一个半露的格:默认把它滚进来,加上 goDontScrollPartCell 之后不滚。

  **两次点击之间必须把状态复位。** 第一版没复位,于是第二次点的是**光标已经
  在的那一格** —— `ScrollIntoView` 本来就无事可做,"没滚"这个结果与标志毫无
  关系。变异测试当场抓到:把 `MoveCursor` 里那句
  `if not FSuppressScrollIntoView then` 去掉(等于标志永远不生效),
  这条测试照样全绿。复位之后它就红了。 }
procedure TGridOptionsTest.TestDontScrollPartCellGatesTheClickScroll;

  { 从同一个已知状态出发:光标 (0,0)、视口贴顶。然后点视口**下沿**那一条 ——
    边缘探针,不是中心:整格可见的格子怎么点都不会滚。 }
  function ClickBottomEdgeThenScrollY: Integer;
  var
    r: TRect;
  begin
    FGrid.Col := 0;
    FGrid.Row := 0;
    FGrid.ScrollY := 0;
    r := FGrid.CellRectOf(0, 0);
    FGrid.ClickAt(r.Left + 4, FGrid.Height - 2);
    Result := FGrid.ScrollY;
  end;

var
  scrolled, held: Integer;
begin
  Build(3, 60, 80);

  scrolled := ClickBottomEdgeThenScrollY;
  AssertTrue('默认(不含 goDontScrollPartCell)点半露的格应当把它滚进来'
    + ' —— 实测 ScrollY=' + IntToStr(scrolled), scrolled > 0);

  FGrid.Options := FGrid.Options + [goDontScrollPartCell];
  held := ClickBottomEdgeThenScrollY;
  AssertEquals('加上 goDontScrollPartCell 之后同一下不许滚', 0, held);
end;

procedure TGridOptionsTest.TestScrollKeepVisibleDragsTheCursorAlong;
var
  rowBefore: Integer;
begin
  Build(3, 200, 80);
  FGrid.Col := 0;
  FGrid.Row := 0;
  rowBefore := FGrid.Row;

  { 默认:滚走了光标留在原地(视口与光标解耦,见 ScrollVerticallyBy 的说明)。 }
  FGrid.ScrollY := 1200;
  AssertEquals('默认不含 goScrollKeepVisible → 光标留在原地', rowBefore, FGrid.Row);

  FGrid.ScrollY := 0;
  FGrid.Row := 0;
  FGrid.Options := FGrid.Options + [goScrollKeepVisible];
  FGrid.ScrollY := 1200;
  AssertTrue('加上 goScrollKeepVisible 之后光标必须被拖进新视口',
    FGrid.Row > rowBefore);
end;

{ 省略号。数的是**单元格里的墨**。

  第一版探针量的是"单元格右缘往里 10px 那条竖带",两种画法都答 7 —— 因为那条
  带整个落在主题的右内边距里,文字根本没画到那儿(墨量 7 是抗锯齿的零头)。
  这正是"探针要瞄在真正会变的地方"那条教训的又一次:边缘要瞄**文字框**的边缘,
  不是单元格的边缘。

  改成数整格的墨,因为两种画法的差别本来就不在某一条边上,而在"画了几个字":
  开着时是 `M…` 之类(一两个字母 + 三个坐在基线上的点),关掉是尽可能多的 'M'
  被硬裁在同一个宽度里。'M' 比 '.' 密得多,所以关掉之后墨必然显著更多。 }
procedure TGridOptionsTest.TestCellEllipsisGatesTheTrailingDots;

  procedure Snap(ADest: TBGRABitmap);
  begin
    FGrid.RenderInto(ADest);
  end;

  function InkOf(ABmp: TBGRABitmap; const R: TRect): Integer;
  var
    x, y: Integer;
    p, bg: TBGRAPixel;
  begin
    Result := 0;
    bg := ABmp.GetPixel(R.Left + 1, R.Top + 1);
    for x := R.Left + 1 to R.Right - 2 do
      for y := R.Top + 1 to R.Bottom - 2 do
      begin
        if (x < 0) or (y < 0) or (x >= ABmp.Width) or (y >= ABmp.Height) then Continue;
        p := ABmp.GetPixel(x, y);
        if (Abs(p.red - bg.red) > 40) or (Abs(p.green - bg.green) > 40)
           or (Abs(p.blue - bg.blue) > 40) then Inc(Result);
      end;
  end;

var
  a, b: TBGRABitmap;
  r: TRect;
  x, y, diff, inkA, inkB, noise, twoChars: Integer;
  pa, pb: TBGRAPixel;
begin
  { **列宽是这条测试的关键参数,不是随手挑的。**

    第一版用 60px 宽的列,两种画法测出来的墨一模一样(183 对 183),逐像素差
    也是 0 —— 不是标志没生效,而是这个宽度下两者**都把 48px 的文字带填满了**:
    省略号版是 `MMMMM...`(5 个 M + 三个点 ≈ 48px),硬裁版是 8 个 M 被切在
    48px 上。宽度一样、密度接近,ink 这个统计量分辨不出来。
    (确认过不是标志的问题:把 TyGridEllipsisFit 的宽度写死成 20 之后,
     同一条测试立刻通过 —— 说明闸是通的,是探针分辨不出来。)

    列窄到只放得下两三个字母时,差别就无法混淆了:
    省略号版基本只剩 `M...`,硬裁版是密密两个 M。 }
  Build(2, 4, 26);
  FGrid.Cells[0, 0] := 'MMMMMMMMMMMMMMMMMMMMMMMM';
  FGrid.Col := 1;                        { 光标挪开,免得焦点底色掺进来 }
  FGrid.Row := 2;

  a := TBGRABitmap.Create(1, 1);
  b := TBGRABitmap.Create(1, 1);
  try
    { 先证明探针**看得见文字** —— 否则下面比出来的 0 差异毫无意义
      (第一版就是在这儿栽的:两边都答 183,而 183 究竟是不是字都没验过)。 }
    Snap(a);
    r := FGrid.CellRectOf(0, 0);
    inkA := InkOf(a, r);
    FGrid.Cells[0, 0] := '';
    Snap(b);
    inkB := InkOf(b, r);
    AssertTrue('探针必须看得见文字:清空这一格之后墨要显著变少'
      + ' —— 实测 有字=' + IntToStr(inkA) + ' 空格=' + IntToStr(inkB),
      inkA > inkB + 20);
    noise := inkB;                       { 空格底噪,留着进诊断信息 }
    FGrid.Cells[0, 0] := 'MM';
    Snap(b);
    twoChars := InkOf(b, r);             { 两个字母时的墨 }
    FGrid.Cells[0, 0] := 'MMMMMMMMMMMMMMMMMMMMMMMM';

    Snap(a);
    FGrid.Options := FGrid.Options - [goCellEllipsis];
    Snap(b);

    inkA := InkOf(a, r);
    inkB := InkOf(b, r);

    { **断言的是"画出来的东西变了"**,不是某个统计量变了。
      第一版数墨量,两边都答 183 —— 而墨量相等既可能是"没生效",也可能是
      "生效了但两种画法碰巧一样密"。逐像素比就没有这种歧义。 }
    diff := 0;
    for x := r.Left + 1 to r.Right - 2 do
      for y := r.Top + 1 to r.Bottom - 2 do
      begin
        if (x < 0) or (y < 0) or (x >= a.Width) or (y >= a.Height) then Continue;
        pa := a.GetPixel(x, y);
        pb := b.GetPixel(x, y);
        if (pa.red <> pb.red) or (pa.green <> pb.green) or (pa.blue <> pb.blue) then
          Inc(diff);
      end;

    AssertTrue('关掉 goCellEllipsis 之后这一格画出来的像素必须变'
      + ' —— 实测 diff=' + IntToStr(diff)
      + ' inkA=' + IntToStr(inkA) + ' inkB=' + IntToStr(inkB)
      + ' 空格底噪=' + IntToStr(noise) + ' 两字母=' + IntToStr(twoChars),
      diff > 0);
    { 方向也要对:硬裁能塞进更多字母,'M' 比 '.' 密得多。 }
    AssertTrue('硬裁版的墨应当多于省略号版'
      + ' —— 实测 inkA=' + IntToStr(inkA) + ' inkB=' + IntToStr(inkB),
      inkB > inkA);
  finally
    b.Free;
    a.Free;
  end;
end;

procedure TGridOptionsTest.TestCellHintsIsTheMasterSwitch;
var
  r: TRect;
begin
  Build(3, 6, 80);
  FGrid.CellComment[0, 0] := '这是批注';
  r := FGrid.CellRectOf(0, 0);

  FGrid.HoverAt((r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2);
  AssertEquals('默认含 goCellHints → 批注变成提示', '这是批注', FGrid.Hint);
  AssertTrue('…且 ShowHint 被打开', FGrid.ShowHint);

  { 关掉时不只是"以后不再给",**已经挂上的那条也要摘掉** ——
    不摘的话鼠标停在格上时关开关,提示会一直悬在那儿。 }
  FGrid.Options := FGrid.Options - [goCellHints];
  FGrid.HoverAt((r.Left + r.Right) div 2 + 1, (r.Top + r.Bottom) div 2);
  AssertEquals('关掉后提示必须被摘掉', '', FGrid.Hint);
  AssertFalse('…ShowHint 也要关', FGrid.ShowHint);
end;

procedure TGridOptionsTest.TestTruncCellHintsShowsTheFullText;
var
  r: TRect;
  longTxt: string;
begin
  Build(2, 6, 60);
  longTxt := 'MMMMMMMMMMMMMMMMMMMMMMMMMMMM';
  FGrid.Cells[0, 0] := longTxt;
  FGrid.Cells[1, 0] := 'x';                { 短的,放得下 }

  AssertEquals('放不下的格:TruncatedCellHint 答全文', longTxt,
    FGrid.TruncHintOf(0, 0));
  AssertEquals('放得下的格:答空串', '', FGrid.TruncHintOf(1, 0));

  r := FGrid.CellRectOf(0, 0);
  FGrid.HoverAt((r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2);
  AssertEquals('默认不含 goTruncCellHints → 不给提示', '', FGrid.Hint);

  FGrid.Options := FGrid.Options + [goTruncCellHints];
  FGrid.HoverAt((r.Left + r.Right) div 2 + 1, (r.Top + r.Bottom) div 2);
  AssertEquals('加上之后放不下的格用全文当提示', longTxt, FGrid.Hint);

  { 批注比它强:两者都在时批注赢。 }
  FGrid.CellComment[0, 0] := '批注赢';
  FGrid.HoverAt((r.Left + r.Right) div 2 + 2, (r.Top + r.Bottom) div 2);
  AssertEquals('批注优先于截断全文', '批注赢', FGrid.Hint);
end;

{ 整行高亮。断言在 CellAppearance 上而不是像素上:这一层就是绘制读的那一层,
  而且它能把"光标那一格"和"同一行的别的格"分开问 —— 后者正是这个标志的全部内容。 }
procedure TGridOptionsTest.TestRowHighlightPaintsTheWholeRow;
var
  sameRowOther, otherRow, focused: TTyGridCellAppearance;
begin
  Build(3, 6, 80);
  FGrid.Col := 0;
  FGrid.Row := 2;

  { 第 2 行与第 4 行**同奇偶**,所以斑马纹给的底色本来就一样 ——
    默认状态下这两格必须长得一模一样。写成 `not (A and not B)` 那种形式的话,
    两格都有底色时会无条件通过,等于什么都没测。 }
  sameRowOther := FGrid.AppearanceOf(2, 2);   { 光标那一行,别的列 }
  otherRow     := FGrid.AppearanceOf(2, 4);   { 别的行,同奇偶 }
  AssertEquals('默认不含 goRowHighlight → 同行别的格与别的行一样有没有底',
    Ord(otherRow.HasBackground), Ord(sameRowOther.HasBackground));
  AssertEquals('…底色也一样',
    Integer(otherRow.Background.Color), Integer(sameRowOther.Background.Color));

  FGrid.Options := FGrid.Options + [goRowHighlight];
  focused      := FGrid.AppearanceOf(0, 2);
  sameRowOther := FGrid.AppearanceOf(2, 2);
  otherRow     := FGrid.AppearanceOf(2, 4);

  AssertTrue('开着时同一行的别的格必须拿到高亮底', sameRowOther.HasBackground);
  AssertTrue('…而且与焦点格用的是同一层底色',
    sameRowOther.Background.Color = focused.Background.Color);
  AssertFalse('…别的行不许被波及', otherRow.HasBackground);
end;

{ **按下去的列头**。这个标志从前被**刻意扣着不发布**(不是"发布了却不照办"):
  主题里没有 TyGridHeaderSection:active,按下态解析回 base 的 `background: none`,
  与静止态一模一样。规则补上之后才接的线,所以这一条钉的是那根线本身。

  按整段数**变了多少像素**,而不是挑一个点:挑点会踩到标题文字或排序箭头,
  而"底色换了"的表现就是整段大面积改变。三次渲染互相对照:
    静止               —— 基准
    按住 + 标志关       —— 必须与基准**逐像素相同**(现有窗体一帧都不许动)
    按住 + 标志开       —— 必须大面积不同(那就是按下去的底)
  把 RenderHeaderSections 里 [tysActive] 那一趟解析删掉(或改成 []),
  第三条断言立刻变红。 }
procedure TGridOptionsTest.TestHeaderPushedLookGatesThePressedFill;
var
  rest, pressedOff, pressedOn: TBGRABitmap;
  secL, secR, hdrH, x, y, diffOff, diffOn, area: Integer;
  boxOff, boxOn: string;

  { 第 1 列的列头段里,和基准比有多少个像素不一样;顺带把它们的**包围盒**记下来
    —— 数字单说"变了 22 个点"没法查,包围盒直接指出是哪一块(排序箭头?焦点框?)。 }
  function DiffInSection(A, B: TBGRABitmap; out ABox: string): Integer;
  var
    px, py, x0, y0, x1, y1: Integer;
  begin
    Result := 0;
    x0 := MaxInt; y0 := MaxInt; x1 := -1; y1 := -1;
    for py := 1 to hdrH - 2 do
      for px := secL + 1 to secR - 2 do
        if (A.GetPixel(px, py).red   <> B.GetPixel(px, py).red)
           or (A.GetPixel(px, py).green <> B.GetPixel(px, py).green)
           or (A.GetPixel(px, py).blue  <> B.GetPixel(px, py).blue) then
        begin
          Inc(Result);
          if px < x0 then x0 := px;
          if py < y0 then y0 := py;
          if px > x1 then x1 := px;
          if py > y1 then y1 := py;
        end;
    if Result = 0 then ABox := '(none)'
    else ABox := Format('x %d..%d, y %d..%d (段 x %d..%d, 带高 %d)',
      [x0, x1, y0, y1, secL, secR, hdrH]);
  end;

begin
  Build(3, 6, 80);
  { 点列头默认还会**排序**,排序会在段的右端画/换一个排序三角(第一版就栽在这:
    标志关着也有 22 个像素在动,包围盒正好落在三角那 6x6 上)。这条测试要量的是
    "按下去换不换底",所以先把点击排序摘掉,免得两件事混在一个数字里。 }
  FGrid.Header.Options := FGrid.Header.Options - [hoHeaderClickAutoSort];
  hdrH := FGrid.HeaderH;
  AssertTrue('列头带要有高度,否则这条测试什么也没看', hdrH > 4);
  { 列头段与正文列同一套列几何,所以拿正文格的左右边当段的左右边。 }
  secL := FGrid.CellRectOf(1, 0).Left;
  secR := FGrid.CellRectOf(1, 0).Right;
  AssertTrue('第 1 列要在可视区里', secR > secL + 8);
  area := (hdrH - 2) * (secR - secL - 2);
  AssertTrue('取样面积要有意义', area > 100);

  x := secL + (secR - secL) div 2;    { 按在第 1 列的列头上 }
  y := hdrH div 2;

  rest := TBGRABitmap.Create;
  pressedOff := TBGRABitmap.Create;
  pressedOn := TBGRABitmap.Create;
  try
    FGrid.RenderInto(rest);

    { 标志关(出厂态):按住列头,画面必须与静止时一模一样。 }
    AssertFalse('前置:出厂不含 goHeaderPushedLook',
      goHeaderPushedLook in FGrid.Options);
    FGrid.MouseDown(mbLeft, [], x, y);
    FGrid.RenderInto(pressedOff);
    FGrid.MouseUp(mbLeft, [], x, y);

    { 标志开:同一个按下动作现在要解析出 :active 的底。 }
    FGrid.Options := FGrid.Options + [goHeaderPushedLook];
    FGrid.MouseDown(mbLeft, [], x, y);
    FGrid.RenderInto(pressedOn);
    FGrid.MouseUp(mbLeft, [], x, y);

    diffOff := DiffInSection(rest, pressedOff, boxOff);
    diffOn  := DiffInSection(rest, pressedOn, boxOn);

    AssertEquals('标志关着时按下列头不许改变任何一个像素'
      + '(否则就是偷偷改了现有窗体)。变化区域:' + boxOff, 0, diffOff);
    AssertTrue(Format('标志开着时按下的那一段必须换底 —— 与静止相比只有 %d/%d '
      + '个像素变了。RenderHeaderSections 里那趟 [tysActive] 解析没接上?',
      [diffOn, area]), diffOn > area div 3);
  finally
    rest.Free;
    pressedOff.Free;
    pressedOn.Free;
  end;
end;

{ ================= 流式化 ================= }

procedure TGridOptionsTest.TestOptionsSurviveARoundTrip;
var
  ms: TMemoryStream;
  host, back: TForm;
  g: TOptGrid;
  want: TTyGridOptions;
begin
  host := TForm.CreateNew(nil);
  back := nil;
  ms := TMemoryStream.Create;
  try
    g := TOptGrid.Create(host);
    g.Parent := host;
    g.Name := 'G';
    { 自有位与派生位都动:两类都必须原样回来。 }
    want := [goVertLine, goRangeSelect, goRowSizing, goColMoving, goTabs,
             goRowSelect, goCellHints, goRowHighlight];
    g.Options := want;
    AssertTrue('写进去先要读得回来', g.Options = want);

    ms.WriteComponent(g);
    ms.Position := 0;

    back := TForm.CreateNew(nil);
    g := TOptGrid.Create(back);
    g.Parent := back;
    ms.ReadComponent(g);

    AssertTrue('往返之后 Options 必须逐位相同', g.Options = want);
    { 派生位不是靠 Options 那一行活下来的 —— 具名属性也必须对上。
      两边都写进了流,谁后读到都要收敛到同一个值。 }
    AssertTrue('goRowSelect 落到了 SelectionMode', g.SelectionMode = gsmRow);
    AssertTrue('goVertLine 无 goHorzLine → glsVertical',
      g.GridLineStyle = glsVertical);
    AssertFalse('goColSizing 没写 → hoColumnResize 也没了',
      hoColumnResize in g.Header.Options);
    AssertTrue('goColMoving 写了 → hoDrag 在', hoDrag in g.Header.Options);
    AssertTrue('goEditing 没写 → ReadOnly 是 True', g.ReadOnly);
  finally
    ms.Free;
    back.Free;
    host.Free;
  end;
end;

{ 老窗体里只有 GridLineStyle、没有 Options 那一行(这个属性是后加的)。
  派生位是**现算**的,所以读回来必须是老窗体的意思,而不是出厂值。
  这条正是"两处存储"最会栽的地方:留了副本的话,构造函数里那份出厂副本
  会盖掉老窗体刚读进来的 GridLineStyle。 }
procedure TGridOptionsTest.TestOldLfmWithOnlyTheNamedPropertyStillLoads;
var
  lfm: TStringList;
  txt: TStringStream;
  bin: TMemoryStream;
  host: TForm;
  g: TOptGrid;
begin
  lfm := TStringList.Create;
  txt := nil;
  bin := TMemoryStream.Create;
  host := TForm.CreateNew(nil);
  try
    lfm.Add('object G: TOptGrid');
    lfm.Add('  GridLineStyle = glsHorizontal');
    lfm.Add('  ReadOnly = True');
    lfm.Add('end');
    txt := TStringStream.Create(lfm.Text);
    ObjectTextToBinary(txt, bin);
    bin.Position := 0;

    g := TOptGrid.Create(host);
    g.Parent := host;
    bin.ReadComponent(g);

    AssertFalse('老窗体的 glsHorizontal 必须还在:goVertLine 不该有',
      goVertLine in g.Options);
    AssertTrue('…goHorzLine 该有', goHorzLine in g.Options);
    AssertFalse('老窗体的 ReadOnly=True 必须还在:goEditing 不该有',
      goEditing in g.Options);
    { 没被老窗体提到的位仍是出厂值。 }
    AssertTrue('没提到的 goRangeSelect 仍是出厂的开',
      goRangeSelect in g.Options);
  finally
    bin.Free;
    txt.Free;
    lfm.Free;
    host.Free;
  end;
end;

initialization
  RegisterTest(TGridOptionsTest);
  { .lfm 文本要能被 ObjectTextToBinary 认出类名。 }
  RegisterClass(TOptGrid);
end.
