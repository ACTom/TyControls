{ 网格的纯几何层 —— 无控件、无画布、无句柄,全部是可无头测试的纯函数。

  与 tyControls.ListView.Layout.pas 同构,并遵循同一条铁律:
  **命中测试必须由矩形函数取逆得到**(TyGridCellAt = TyGridCellRect + PtInRect),
  这样绘制几何与命中几何在机械上就不可能漂移。

  本单元不依赖 tyControls.Columns —— 列的 Left/Width 由调用方(控件)算好后传入,
  保持几何层与列模型解耦、可独立测试。 }
unit tyControls.Grid.Layout;

{$mode objfpc}{$H+}

interface

uses
  Types;

type
  { 有固定行/列时,视口被切成的四个窗格。

      +----------+---------------------+
      | gpCorner | gpTop   (固定行)    |
      +----------+---------------------+
      | gpLeft   | gpBody  (可滚动正文)|
      | (固定列) |                     |
      +----------+---------------------+

    冻结带的宽/高(FrozenW/FrozenH)含行头槽与列头带,由控件从列模型算出后传入。 }
  TTyGridPane = (gpCorner, gpTop, gpLeft, gpBody);

  { 命中到的部位。 }
  TTyGridHitPart = (
    ghpNowhere,      { 空白 }
    ghpCell,         { 正文单元格 }
    ghpHeader,       { 列头带 }
    ghpIndicator,    { 行头/行号槽 }
    ghpColDivider,   { 列分隔条(拖宽) }
    ghpRowDivider    { 行分隔条(拖高) }
  );

  TTyGridHit = record
    Part: TTyGridHitPart;
    Col:  Integer;   { 不适用时为 -1 }
    Row:  Integer;   { 不适用时为 -1 }
  end;

  { 网格的几何输入。全部为设备像素(已按 PPI 缩放)。 }
  TTyGridMetrics = record
    ClientW, ClientH: Integer;   { 视口尺寸 }
    FrozenW, FrozenH: Integer;   { 冻结带范围:行头槽+固定列 / 列头带+固定行 }
    RowH:             Integer;   { 统一行高(P0 阶段不支持可变行高) }
    RowCount:         Integer;
    ScrollX, ScrollY: Integer;   { 正文窗格的滚动偏移,>=0 }
  end;

{ 四个窗格的矩形。它们必须精确铺满视口:互不重叠、无缝隙。
  冻结带若超出视口则被钳制,退化窗格返回空矩形(而非反向矩形)。 }
function TyGridPaneRect(const M: TTyGridMetrics; APane: TTyGridPane): TRect;

{ 第 ARow 行的整行横带,**客户区坐标**、跨满整幅宽度(调用方再与窗格求交)。
  正文行随 ScrollY 滚动并让开冻结带;因此 Top = FrozenH + ARow*RowH - ScrollY,
  越界的行会算出视口外的坐标 —— 这是正常的,可视性由 TyGridVisibleRows 判定。 }
function TyGridRowRect(ARow: Integer; const M: TTyGridMetrics): TRect;

{ 与正文窗格相交的行区间(闭区间,含只露出一部分的首尾行)—— 虚拟化的核心:
  百万行的表每帧也只绘制这几十行。无行可见时返回 False(AFirst/ALast 置 -1)。 }
function TyGridVisibleRows(const M: TTyGridMetrics;
  out AFirst, ALast: Integer): Boolean;

{ 纵坐标落在哪一行 —— **TyGridRowRect 的逆**。落在正文窗格之外、或超出 RowCount 时答 -1。

  刻意只做行轴:列轴用现成的 TTyColumns.ColumnFromPosition,几何层不重复实现列模型。

  不变量:**本函数必须恒为 TyGridRowRect 的逆**。一旦绘制与命中各算各的,就会在边界像素上
  分叉(本库在 Segmented/Alert/Tag/Pagination 上反复栽过这个跟头)。守住它的是逐像素反查的
  测试,而非某种特定写法 —— 见实现里的说明。 }
function TyGridRowAt(AY: Integer; const M: TTyGridMetrics): Integer;

implementation

function TyGridPaneRect(const M: TTyGridMetrics; APane: TTyGridPane): TRect;
var
  cw, ch, fw, fh: Integer;
begin
  { 先把视口与冻结带都钳制到合法区间:冻结带不可能大于视口(那样正文窗格会反向),
    负尺寸一律按 0 处理。钳制之后四个窗格必然铺满 [0,cw]x[0,ch] 且互不重叠。 }
  cw := M.ClientW; if cw < 0 then cw := 0;
  ch := M.ClientH; if ch < 0 then ch := 0;
  fw := M.FrozenW; if fw < 0 then fw := 0; if fw > cw then fw := cw;
  fh := M.FrozenH; if fh < 0 then fh := 0; if fh > ch then fh := ch;

  case APane of
    gpCorner: Result := Rect(0,  0,  fw, fh);
    gpTop:    Result := Rect(fw, 0,  cw, fh);
    gpLeft:   Result := Rect(0,  fh, fw, ch);
  else        Result := Rect(fw, fh, cw, ch);   { gpBody }
  end;
end;

function TyGridRowRect(ARow: Integer; const M: TTyGridMetrics): TRect;
var
  y, h: Integer;
begin
  h := M.RowH; if h < 0 then h := 0;
  y := M.FrozenH + ARow * h - M.ScrollY;
  Result := Rect(0, y, M.ClientW, y + h);
end;

function TyGridVisibleRows(const M: TTyGridMetrics;
  out AFirst, ALast: Integer): Boolean;
var
  body: TRect;
  h, avail: Integer;
begin
  AFirst := -1;
  ALast := -1;
  Result := False;

  h := M.RowH;
  if (h <= 0) or (M.RowCount <= 0) then Exit;

  { 用窗格函数取正文区,而不是自己再算一遍 —— 可见性判定与窗格切分必须同源,
    否则两处的钳制规则一旦分叉,滚动到边缘就会出现少画/多画一行。 }
  body := TyGridPaneRect(M, gpBody);
  avail := body.Bottom - body.Top;
  if avail <= 0 then Exit;   { 冻结带吃满视口:正文零高 }

  { 首行 = 被滚掉的整行数;负偏移按 0 处理。 }
  if M.ScrollY > 0 then AFirst := M.ScrollY div h else AFirst := 0;

  { 末行 = 最后一个顶边仍落在正文区内的行(故 -1 再整除,含只露一点的那行)。 }
  ALast := (M.ScrollY + avail - 1) div h;

  if AFirst > M.RowCount - 1 then   { 整个滚过了尾部 }
  begin
    AFirst := -1;
    ALast := -1;
    Exit;
  end;
  if ALast > M.RowCount - 1 then ALast := M.RowCount - 1;

  Result := ALast >= AFirst;
  if not Result then
  begin
    AFirst := -1;
    ALast := -1;
  end;
end;

function TyGridRowAt(AY: Integer; const M: TTyGridMetrics): Integer;
var
  body: TRect;
  cand: Integer;
begin
  Result := -1;

  { 只有正文窗格里才有行:冻结带(列头/固定行)与窗格外一律不是行。 }
  body := TyGridPaneRect(M, gpBody);
  if (AY < body.Top) or (AY >= body.Bottom) then Exit;
  if (M.RowH <= 0) or (M.RowCount <= 0) then Exit;

  { 统一行高下,本式与 TyGridRowRect 用的是同一个公式(FrozenH + row*RowH - ScrollY),
    因此两者恒等 —— 不需要再回头验证一遍(验证过也确认是冗余代码,没有测试能区分)。

    守住"命中 = 矩形取逆"的是 TestRowAtIsTheExactInverseOfRowRect:它逐像素扫过每一
    可见行、要求反查回同一行,与实现无关。**等 P1 引入可变行高**,本式将不再与矩形恒等,
    那条测试会立刻转红 —— 届时必须改成按行高表搜索并用 TyGridRowRect 校验命中。 }
  cand := (AY - M.FrozenH + M.ScrollY) div M.RowH;
  if (cand < 0) or (cand > M.RowCount - 1) then Exit;
  Result := cand;
end;

end.
