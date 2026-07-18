unit test.grid.layout;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, fpcunit, testregistry,
  tyControls.Grid.Layout;

type
  { 纯几何测试:不建控件、不要句柄、不要主题 —— 全是纯函数。 }
  TTyGridLayoutTest = class(TTestCase)
  private
    function M(AClientW, AClientH, AFrozenW, AFrozenH, ARowH, ARowCount,
      AScrollX, AScrollY: Integer): TTyGridMetrics;
  published
    procedure TestPanesTileTheViewport;
    procedure TestOversizeFrozenBandIsClamped;
    procedure TestNoFrozenBandGivesBodyTheWholeViewport;
    procedure TestRowRectSitsBelowFrozenBandAndFollowsScroll;
    procedure TestVisibleRowsCoverThePartiallyExposedEdges;
    procedure TestVisibleRowsClampToRowCountAndEmptyGrid;
    procedure TestRowAtIsTheExactInverseOfRowRect;
    procedure TestRowAtRejectsFrozenBandAndBeyondLastRow;
  end;

implementation

function TTyGridLayoutTest.M(AClientW, AClientH, AFrozenW, AFrozenH, ARowH,
  ARowCount, AScrollX, AScrollY: Integer): TTyGridMetrics;
begin
  Result := Default(TTyGridMetrics);
  Result.ClientW := AClientW;
  Result.ClientH := AClientH;
  Result.FrozenW := AFrozenW;
  Result.FrozenH := AFrozenH;
  Result.RowH := ARowH;
  Result.RowCount := ARowCount;
  Result.ScrollX := AScrollX;
  Result.ScrollY := AScrollY;
end;

{ 全设计的第一条不变量:四个窗格必须精确铺满视口 —— 互不重叠、无缝隙。
  只要这里漂一个像素,后面所有的绘制与命中都建在斜的地基上。 }
procedure TTyGridLayoutTest.TestPanesTileTheViewport;
var
  Mt: TTyGridMetrics;
  corner, top, left, body: TRect;
begin
  // 400x300 视口,冻结带 120 宽 / 60 高(行头槽+固定列 / 列头带+固定行)。
  Mt := M(400, 300, 120, 60, 20, 50, 0, 0);
  corner := TyGridPaneRect(Mt, gpCorner);
  top    := TyGridPaneRect(Mt, gpTop);
  left   := TyGridPaneRect(Mt, gpLeft);
  body   := TyGridPaneRect(Mt, gpBody);

  // 角落窗格钉在原点,尺寸就是冻结带。
  AssertEquals('corner.Left', 0, corner.Left);
  AssertEquals('corner.Top', 0, corner.Top);
  AssertEquals('corner.Right = FrozenW', 120, corner.Right);
  AssertEquals('corner.Bottom = FrozenH', 60, corner.Bottom);

  // 上下相接、左右相接:同一条边界,不能有缝也不能重叠。
  AssertEquals('top 紧接 corner 右侧', corner.Right, top.Left);
  AssertEquals('top 与 corner 等高', corner.Bottom, top.Bottom);
  AssertEquals('top 右到视口边', 400, top.Right);

  AssertEquals('left 紧接 corner 下方', corner.Bottom, left.Top);
  AssertEquals('left 与 corner 等宽', corner.Right, left.Right);
  AssertEquals('left 下到视口边', 300, left.Bottom);

  AssertEquals('body 左边界 = 冻结宽', 120, body.Left);
  AssertEquals('body 上边界 = 冻结高', 60, body.Top);
  AssertEquals('body 右到视口边', 400, body.Right);
  AssertEquals('body 下到视口边', 300, body.Bottom);

  // 面积守恒 —— 铺满且不重叠的机械证明。
  AssertEquals('四窗格面积之和 = 视口面积',
    400 * 300,
      (corner.Right - corner.Left) * (corner.Bottom - corner.Top)
    + (top.Right - top.Left) * (top.Bottom - top.Top)
    + (left.Right - left.Left) * (left.Bottom - left.Top)
    + (body.Right - body.Left) * (body.Bottom - body.Top));
end;

{ 冻结列比视口还宽是真会发生的(窗口被拖到很窄 / 固定列很多)。此时正文窗格若不钳制
  就会反向(Right < Left),而反向矩形喂给绘制与 PtInRect 都是灾难。钳制后仍须铺满。 }
procedure TTyGridLayoutTest.TestOversizeFrozenBandIsClamped;
var
  Mt: TTyGridMetrics;
  corner, top, left, body: TRect;
begin
  // 冻结带 500x400,视口只有 200x100 —— 冻结带整个盖过视口。
  Mt := M(200, 100, 500, 400, 20, 50, 0, 0);
  corner := TyGridPaneRect(Mt, gpCorner);
  top    := TyGridPaneRect(Mt, gpTop);
  left   := TyGridPaneRect(Mt, gpLeft);
  body   := TyGridPaneRect(Mt, gpBody);

  AssertEquals('冻结宽被钳到视口宽', 200, corner.Right);
  AssertEquals('冻结高被钳到视口高', 100, corner.Bottom);

  AssertTrue('top 不反向', top.Right >= top.Left);
  AssertTrue('left 不反向', left.Bottom >= left.Top);
  AssertTrue('body 不反向(宽)', body.Right >= body.Left);
  AssertTrue('body 不反向(高)', body.Bottom >= body.Top);

  AssertEquals('全被角落窗格吃满,面积仍守恒', 200 * 100,
      (corner.Right - corner.Left) * (corner.Bottom - corner.Top)
    + (top.Right - top.Left) * (top.Bottom - top.Top)
    + (left.Right - left.Left) * (left.Bottom - left.Top)
    + (body.Right - body.Left) * (body.Bottom - body.Top));
end;

{ 没有固定行列、没有列头(FrozenW/H 全 0)是最常见的朴素网格:正文应独占整个视口,
  另外三个窗格退化为空矩形 —— 空,但不能反向。 }
procedure TTyGridLayoutTest.TestNoFrozenBandGivesBodyTheWholeViewport;
var
  Mt: TTyGridMetrics;
  corner, body: TRect;
begin
  Mt := M(400, 300, 0, 0, 20, 50, 0, 0);
  corner := TyGridPaneRect(Mt, gpCorner);
  body   := TyGridPaneRect(Mt, gpBody);

  AssertTrue('corner 退化为空', IsRectEmpty(corner));
  AssertEquals('body 独占视口(左)', 0, body.Left);
  AssertEquals('body 独占视口(上)', 0, body.Top);
  AssertEquals('body 独占视口(右)', 400, body.Right);
  AssertEquals('body 独占视口(下)', 300, body.Bottom);
end;

{ 行的纵向几何:必须让开冻结带(否则第 0 行钻到列头底下),并且随滚动整体平移。
  行带跨满整幅宽度 —— 与固定列窗格求交由调用方负责。 }
procedure TTyGridLayoutTest.TestRowRectSitsBelowFrozenBandAndFollowsScroll;
var
  Mt: TTyGridMetrics;
  r0, r3: TRect;
begin
  // 冻结带高 60(列头+固定行),行高 20,未滚动。
  Mt := M(400, 300, 120, 60, 20, 50, 0, 0);
  r0 := TyGridRowRect(0, Mt);
  AssertEquals('第 0 行紧贴冻结带下沿', 60, r0.Top);
  AssertEquals('行高来自 RowH', 80, r0.Bottom);
  AssertEquals('行带从最左起', 0, r0.Left);
  AssertEquals('行带跨满整幅宽', 400, r0.Right);

  r3 := TyGridRowRect(3, Mt);
  AssertEquals('第 3 行 = 冻结带 + 3*行高', 60 + 3 * 20, r3.Top);

  // 纵向滚动 50px:行整体上移 50,冻结带不动。
  Mt := M(400, 300, 120, 60, 20, 50, 0, 50);
  AssertEquals('滚动后第 0 行上移 50', 60 - 50, TyGridRowRect(0, Mt).Top);
  AssertEquals('滚动后第 3 行同步上移', 60 + 3 * 20 - 50, TyGridRowRect(3, Mt).Top);
end;

{ 虚拟化窗口必须**含**只露出一部分的首尾行 —— 漏掉它们就会在滚动时看到边缘空白条。
  这里正文窗格高 240(300-60),行高 20:不滚动时正好 12 整行(0..11)。 }
procedure TTyGridLayoutTest.TestVisibleRowsCoverThePartiallyExposedEdges;
var
  Mt: TTyGridMetrics;
  f, l: Integer;
begin
  Mt := M(400, 300, 120, 60, 20, 1000, 0, 0);
  AssertTrue('有行可见', TyGridVisibleRows(Mt, f, l));
  AssertEquals('未滚动时自第 0 行起', 0, f);
  AssertEquals('正文 240px / 行高 20 = 12 整行,末行 11', 11, l);

  // 滚动 25px:第 0 行已完全滚出(其底边 55 < 窗格顶 60),第 1 行只露一半 —— 必须算可见。
  Mt := M(400, 300, 120, 60, 20, 1000, 0, 25);
  AssertTrue('有行可见', TyGridVisibleRows(Mt, f, l));
  AssertEquals('首行 = 被滚掉的整行数', 1, f);
  AssertEquals('末行含底部露出一部分的那行', 13, l);

  // 与矩形函数互为印证:首尾行的矩形必须真的与正文窗格相交,末行的下一行必须不相交。
  AssertTrue('首行确实与正文窗格相交',
    TyGridRowRect(f, Mt).Bottom > TyGridPaneRect(Mt, gpBody).Top);
  AssertTrue('末行确实与正文窗格相交',
    TyGridRowRect(l, Mt).Top < TyGridPaneRect(Mt, gpBody).Bottom);
  AssertFalse('末行之后那行不再相交',
    TyGridRowRect(l + 1, Mt).Top < TyGridPaneRect(Mt, gpBody).Bottom);
end;

{ 行数不够填满视口时不能越界报到 RowCount 之外;空表必须干脆答"没有"。 }
procedure TTyGridLayoutTest.TestVisibleRowsClampToRowCountAndEmptyGrid;
var
  Mt: TTyGridMetrics;
  f, l: Integer;
begin
  // 只有 3 行,却有 12 行的空间 —— 末行必须钳到 2,不能是 11。
  Mt := M(400, 300, 120, 60, 20, 3, 0, 0);
  AssertTrue('有行可见', TyGridVisibleRows(Mt, f, l));
  AssertEquals('首行 0', 0, f);
  AssertEquals('末行钳到 RowCount-1', 2, l);

  // 空表。
  Mt := M(400, 300, 120, 60, 20, 0, 0, 0);
  AssertFalse('空表没有可见行', TyGridVisibleRows(Mt, f, l));
  AssertEquals('空表首行置 -1', -1, f);
  AssertEquals('空表末行置 -1', -1, l);

  // 冻结带吃满整个视口 —— 正文窗格零高,同样没有可见行。
  Mt := M(400, 300, 120, 300, 20, 1000, 0, 0);
  AssertFalse('正文窗格零高时没有可见行', TyGridVisibleRows(Mt, f, l));
end;

{ 全库最贵的一类 bug 是"绘制用一套几何、命中用另一套",两边差一个像素就点不准。
  这条测试把不变量钉死:对每一可见行,取其矩形内的每一个 Y,反查必须回到同一行。 }
procedure TTyGridLayoutTest.TestRowAtIsTheExactInverseOfRowRect;
var
  Mt: TTyGridMetrics;
  f, l, row, y: Integer;
  r: TRect;
begin
  // 带滚动的一般情形,首尾都有半露的行。
  Mt := M(400, 300, 120, 60, 20, 1000, 0, 25);
  AssertTrue('有可见行', TyGridVisibleRows(Mt, f, l));

  for row := f to l do
  begin
    r := TyGridRowRect(row, Mt);
    // 逐像素扫该行落在正文窗格内的部分 —— 每一个 Y 都必须反查回本行。
    for y := r.Top to r.Bottom - 1 do
      if (y >= TyGridPaneRect(Mt, gpBody).Top) and (y < TyGridPaneRect(Mt, gpBody).Bottom) then
        AssertEquals(Format('y=%d 必须反查回第 %d 行', [y, row]), row, TyGridRowAt(y, Mt));
  end;
end;

{ 冻结带(列头/固定行)不属于任何正文行;滚过最后一行之后的空白也不是行。
  这两处若误答成某一行,点空白会选中行、拖冻结带会开始编辑单元格。 }
procedure TTyGridLayoutTest.TestRowAtRejectsFrozenBandAndBeyondLastRow;
var
  Mt: TTyGridMetrics;
begin
  Mt := M(400, 300, 120, 60, 20, 3, 0, 0);   // 只有 3 行,正文却有 240px

  AssertEquals('冻结带内(列头)不是行', -1, TyGridRowAt(0, Mt));
  AssertEquals('冻结带下沿前一像素仍不是行', -1, TyGridRowAt(59, Mt));
  AssertEquals('冻结带下沿即第 0 行', 0, TyGridRowAt(60, Mt));

  AssertEquals('第 2 行(末行)最后一像素', 2, TyGridRowAt(60 + 3 * 20 - 1, Mt));
  AssertEquals('末行之后是空白,不是行', -1, TyGridRowAt(60 + 3 * 20, Mt));
  AssertEquals('视口底部空白也不是行', -1, TyGridRowAt(299, Mt));
  AssertEquals('视口之外不是行', -1, TyGridRowAt(5000, Mt));
end;

initialization
  RegisterTest(TTyGridLayoutTest);
end.
