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
  TTyIntArray = array of Integer;

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
    RowH:             Integer;   { 统一行高;RowTops 为空时用它 }
    RowCount:         Integer;
    { 冻结在顶部、**不随纵向滚动**的显示行数。这些行画在冻结带里(列头之下),
      其余行才在正文窗格里滚动。FrozenH 已含它们的高度。 }
    FixedRows:        Integer;
    { 列头带高度(设备像素)。FrozenH = HeaderH + 固定行总高;拆开是因为
      固定行的行矩形要从 HeaderH 起算,而不是从 FrozenH 起算。 }
    HeaderH:          Integer;
    { 可变行高:长度 = RowCount+1 的**前缀和**(RowTops[i] = 第 i 行顶边的内容坐标,
      RowTops[RowCount] = 内容总高)。为空 = 全部用统一行高 RowH。
      用前缀和而不是逐行高度,是为了让"坐标 → 行"能二分查找而不是线性扫。 }
    RowTops:          TTyIntArray;
    ScrollX, ScrollY: Integer;   { 正文窗格的滚动偏移,>=0 }
  end;

{ 四个窗格的矩形。它们必须精确铺满视口:互不重叠、无缝隙。
  冻结带若超出视口则被钳制,退化窗格返回空矩形(而非反向矩形)。 }
function TyGridPaneRect(const M: TTyGridMetrics; APane: TTyGridPane): TRect;

{ 第 ARow 行的整行横带,**客户区坐标**、跨满整幅宽度(调用方再与窗格求交)。
  正文行随 ScrollY 滚动并让开冻结带;因此 Top = FrozenH + ARow*RowH - ScrollY,
  越界的行会算出视口外的坐标 —— 这是正常的,可视性由 TyGridVisibleRows 判定。 }
function TyGridRowRect(ARow: Integer; const M: TTyGridMetrics): TRect;

{ 第 ARow 行在内容坐标里的顶边与高度(不含冻结带与滚动)。 }
procedure TyGridRowExtent(ARow: Integer; const M: TTyGridMetrics;
  out ATop, AHeight: Integer);

{ 内容总高。可变行高时取前缀和末项,否则 RowCount*RowH。 }
function TyGridContentHeight(const M: TTyGridMetrics): Integer;

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

{ 第 ARow 行在**内容坐标**里的顶边与高度(不含冻结带偏移与滚动)。 }
procedure TyGridRowExtent(ARow: Integer; const M: TTyGridMetrics;
  out ATop, AHeight: Integer);
var
  h: Integer;
begin
  if Length(M.RowTops) = M.RowCount + 1 then
  begin
    { 可变行高:直接查前缀和。越界时钳到两端,避免算出荒唐坐标。 }
    if ARow < 0 then
    begin
      ATop := M.RowTops[0];
      AHeight := 0;
      Exit;
    end;
    if ARow >= M.RowCount then
    begin
      ATop := M.RowTops[M.RowCount];
      AHeight := 0;
      Exit;
    end;
    ATop := M.RowTops[ARow];
    AHeight := M.RowTops[ARow + 1] - ATop;
    Exit;
  end;
  h := M.RowH; if h < 0 then h := 0;
  ATop := ARow * h;
  AHeight := h;
end;

function TyGridRowRect(ARow: Integer; const M: TTyGridMetrics): TRect;
var
  top, h, y, fixedTop, fixedH: Integer;
begin
  TyGridRowExtent(ARow, M, top, h);

  if (M.FixedRows > 0) and (ARow < M.FixedRows) then
  begin
    { 固定行:钉在列头带之下、**不随滚动**。它们的位置从 HeaderH 起算。 }
    y := M.HeaderH + top;
    Result := Rect(0, y, M.ClientW, y + h);
    Exit;
  end;

  { 正文行:让开整条冻结带并随滚动平移。注意要减掉固定行占的那段内容高度 ——
    否则第一条正文行会被推到固定行内容之后,与冻结带之间留出一个空洞。 }
  fixedTop := 0;
  fixedH := 0;
  if M.FixedRows > 0 then
    TyGridRowExtent(M.FixedRows, M, fixedTop, fixedH);
  y := M.FrozenH + (top - fixedTop) - M.ScrollY;
  Result := Rect(0, y, M.ClientW, y + h);
end;

function TyGridContentHeight(const M: TTyGridMetrics): Integer;
begin
  if Length(M.RowTops) = M.RowCount + 1 then
    Result := M.RowTops[M.RowCount]
  else
  begin
    Result := M.RowH;
    if Result < 0 then Result := 0;
    Result := Result * M.RowCount;
  end;
end;

{ 内容坐标 AY 落在哪一行 —— 前缀和上二分。越界返回钳制后的端点行。 }
function TyGridRowAtContentY(AContentY: Integer; const M: TTyGridMetrics): Integer;
var
  lo, hi, mid: Integer;
begin
  if Length(M.RowTops) <> M.RowCount + 1 then
  begin
    if M.RowH <= 0 then Exit(-1);
    Exit(AContentY div M.RowH);
  end;
  if M.RowCount <= 0 then Exit(-1);
  if AContentY < M.RowTops[0] then Exit(-1);
  if AContentY >= M.RowTops[M.RowCount] then Exit(-1);
  lo := 0;
  hi := M.RowCount - 1;
  while lo < hi do
  begin
    mid := (lo + hi + 1) div 2;
    if M.RowTops[mid] <= AContentY then lo := mid else hi := mid - 1;
  end;
  Result := lo;
end;

function TyGridVisibleRows(const M: TTyGridMetrics;
  out AFirst, ALast: Integer): Boolean;
var
  body: TRect;
  h, avail, fixedTop, fixedH: Integer;
begin
  AFirst := -1;
  ALast := -1;
  Result := False;

  h := M.RowH;
  if M.RowCount <= 0 then Exit;
  if (h <= 0) and (Length(M.RowTops) <> M.RowCount + 1) then Exit;

  { 用窗格函数取正文区,而不是自己再算一遍 —— 可见性判定与窗格切分必须同源,
    否则两处的钳制规则一旦分叉,滚动到边缘就会出现少画/多画一行。 }
  body := TyGridPaneRect(M, gpBody);
  avail := body.Bottom - body.Top;
  if avail <= 0 then Exit;   { 冻结带吃满视口:正文零高 }

  { 固定行恒可见且不滚动,不参与这个窗口 —— 从它们之后开始算。 }
  fixedTop := 0;
  if M.FixedRows > 0 then
    TyGridRowExtent(M.FixedRows, M, fixedTop, fixedH);

  if Length(M.RowTops) = M.RowCount + 1 then
  begin
    AFirst := TyGridRowAtContentY(M.ScrollY + fixedTop, M);
    if AFirst < 0 then AFirst := M.FixedRows;
    ALast := TyGridRowAtContentY(M.ScrollY + fixedTop + avail - 1, M);
    if ALast < 0 then ALast := M.RowCount - 1;   { 滚过尾部:钳到末行 }
  end
  else
  begin
    if M.ScrollY > 0 then AFirst := (M.ScrollY + fixedTop) div h
    else AFirst := M.FixedRows;
    ALast := (M.ScrollY + fixedTop + avail - 1) div h;
  end;
  if AFirst < M.FixedRows then AFirst := M.FixedRows;

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
  cand, fixedTop, fixedH: Integer;
begin
  Result := -1;

  if M.RowCount <= 0 then Exit;
  if (M.RowH <= 0) and (Length(M.RowTops) <> M.RowCount + 1) then Exit;

  { 固定行带(列头之下、冻结带之内)—— 它们也是真实的行,能点。 }
  if (M.FixedRows > 0) and (AY >= M.HeaderH) and (AY < M.FrozenH) then
  begin
    cand := TyGridRowAtContentY(AY - M.HeaderH, M);
    if (cand >= 0) and (cand < M.FixedRows) then Result := cand;
    Exit;
  end;

  { 正文窗格。列头带与其余冻结区不是行。 }
  body := TyGridPaneRect(M, gpBody);
  if (AY < body.Top) or (AY >= body.Bottom) then Exit;

  { 换算到**内容坐标**再定位:可变行高走前缀和二分,统一行高退化成整除。
    两条路径都与 TyGridRowRect 用同一份数据推出,因此恒为它的逆 ——
    曾经在这里加过一步"用矩形回验候选",变异测试证明它是无法被区分的冗余代码,已删。
    守住不变量的是那两条逐像素反查测试(统一行高一条、可变行高一条),与实现写法无关。 }
  fixedTop := 0;
  if M.FixedRows > 0 then
    TyGridRowExtent(M.FixedRows, M, fixedTop, fixedH);
  cand := TyGridRowAtContentY(AY - M.FrozenH + M.ScrollY + fixedTop, M);
  if (cand < M.FixedRows) or (cand > M.RowCount - 1) then Exit;
  Result := cand;
end;

end.
