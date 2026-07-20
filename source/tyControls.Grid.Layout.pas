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

  { 有冻结带时,视口被切成的九个窗格。

      +-------------+-------------+-------------+
      | gpTopLeft   | gpTop       | gpTopRight  |
      +-------------+-------------+-------------+
      | gpLeft      | gpBody      | gpRight     |
      +-------------+-------------+-------------+
      | gpBottomLeft| gpBottom    | gpBottomRight|
      +-------------+-------------+-------------+

    行向:上带含列头带 + 固定行;下带为底部冻结行。
    列向:左带含行头槽 + 固定列;右带为右侧冻结列。
    四条带的厚度由控件从列模型/行模型算出后传入(设备像素)。

    枚举值的**排列顺序是契约的一部分**:按行主序 3x3,
    TyGridPaneRect 直接用 Ord 拆成 (列,行) 下标,不写九分支 case。 }
  TTyGridPane = (
    gpTopLeft,    gpTop,    gpTopRight,
    gpLeft,       gpBody,   gpRight,
    gpBottomLeft, gpBottom, gpBottomRight);

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

    { 四向冻结带的厚度。
      Left  = 行头槽 + 固定列; Top    = 列头带 + 固定行;
      Right = 右侧冻结列;      Bottom = 底部冻结行。
      任一方向的两条带之和会被钳制在视口内(见 TyGridPaneRect)。 }
    FrozenLeft, FrozenRight, FrozenTop, FrozenBottom: Integer;

    { 列头带:**每一级一个高度**,自上而下堆叠(多级/分组表头)。
      空数组 = 无列头。合计恒 <= FrozenTop(其余部分是固定行)。
      拆成数组而不是一个 HeaderH,是因为多级表头的每一级都要能独立取矩形;
      合计值用 TyGridHeaderH 求。 }
    HeaderBands:      TTyIntArray;

    { 网格线宽(设备像素)。**不占用布局像素** —— 线画在单元格边界上、
      压住相邻两格各一半,这与 LCL TCustomGrid / 常见商业网格的约定一致:
      列宽就是列宽,不会因为线变粗而挪位。它影响的是
      TyGridCellContentRect 的内缩量(免得文字压在粗线底下)与画线的笔宽。 }
    GridLineWidth:    Integer;

    RowH:             Integer;   { 统一行高;RowTops 为空时用它 }
    RowCount:         Integer;
    { 冻结在顶部、**不随纵向滚动**的显示行数。这些行画在冻结带里(列头之下),
      其余行才在正文窗格里滚动。FrozenTop 已含它们的高度。 }
    FixedRows:        Integer;
    { 冻结在**底部**、不随纵向滚动的显示行数(钉在正文窗格之下)。
      FrozenBottom 已含它们的高度。与 FixedRows 对称。 }
    FixedRowsBottom:  Integer;
    { 可变行高:长度 = RowCount+1 的**前缀和**(RowTops[i] = 第 i 行顶边的内容坐标,
      RowTops[RowCount] = 内容总高)。为空 = 全部用统一行高 RowH。
      用前缀和而不是逐行高度,是为了让"坐标 → 行"能二分查找而不是线性扫。 }
    RowTops:          TTyIntArray;
    ScrollX, ScrollY: Integer;   { 正文窗格的滚动偏移,>=0 }

    { 只重画某一条横带时,把可见行窗口再夹到这条带里(客户区坐标)。
      ClipBottom <= ClipTop 表示不设限(整个正文窗格)。

      收口在 TyGridVisibleRows 一处:所有逐行循环都走它,于是**全部**自动跟着变窄
      —— 不必去每个循环里再加一个"只画这几行"的判断,那样迟早漏一个。 }
    ClipTop, ClipBottom: Integer;
  end;

{ 列头带的合计高度。固定行从这里起算,而不是从 FrozenTop 起算。 }
function TyGridHeaderH(const M: TTyGridMetrics): Integer;

{ 第 ALevel 级列头带的横带矩形(客户区坐标,跨满整幅宽度)。
  级别越界返回空矩形。 }
function TyGridHeaderBandRect(ALevel: Integer; const M: TTyGridMetrics): TRect;

{ 九个窗格的矩形。它们必须精确铺满视口:互不重叠、无缝隙。
  冻结带若超出视口则被钳制,退化窗格返回空矩形(而非反向矩形)。 }
function TyGridPaneRect(const M: TTyGridMetrics; APane: TTyGridPane): TRect;

{ 第 ARow 行的整行横带,**客户区坐标**、跨满整幅宽度(调用方再与窗格求交)。
  正文行随 ScrollY 滚动并让开冻结带;因此 Top = FrozenTop + ARow*RowH - ScrollY,
  越界的行会算出视口外的坐标 —— 这是正常的,可视性由 TyGridVisibleRows 判定。 }
function TyGridRowRect(ARow: Integer; const M: TTyGridMetrics): TRect;

{ 第 ARow 行(**显示序**)所属的那条**横向带**:上冻结带 / 正文 / 下冻结带,
  跨满整幅宽度、客户区坐标。

  "跨列的 chrome 必须裁到它所属的那条带"是本控件反复漏掉的一条规则 ——
  行号、横格线、选区外框各漏过一次,症状每次都一样:滚到冻结带底下的那一行,
  把自己的装饰画到了固定行的槽位上。规则只写在这里一处,
  调用方一律走 TTyCustomGrid.DrawInRowBand,不自己算带。

  与 TyGridPaneRect 的差别:顶部带**不含列头带**(列头是另画的,不属于任何行)。 }
function TyGridRowBandRect(ARow: Integer; const M: TTyGridMetrics): TRect;

{ 把单元格矩形内缩成**内容矩形**:让开边界上的网格线,免得文字压在粗线底下。
  线画在边界上、两侧各占一半,所以每边内缩 GridLineWidth 的一半(向上取整)。
  线宽 <= 1 时(最常见)内缩为 0,几何与从前逐像素一致。 }
function TyGridCellContentRect(const ACell: TRect; const M: TTyGridMetrics): TRect;

{ 第 ARow 行在内容坐标里的顶边与高度(不含冻结带与滚动)。 }
procedure TyGridRowExtent(ARow: Integer; const M: TTyGridMetrics;
  out ATop, AHeight: Integer);

{ 内容总高。可变行高时取前缀和末项,否则 RowCount*RowH。 }
function TyGridContentHeight(const M: TTyGridMetrics): Integer;

{ 与正文窗格相交的行区间(闭区间,含只露出一部分的首尾行)—— 虚拟化的核心:
  百万行的表每帧也只绘制这几十行。无行可见时返回 False(AFirst/ALast 置 -1)。 }
{ --- 逐行绘制的槽位 ---
  槽位 0..FixedRows-1 是**顶部固定行**,其后接正文窗口里的行。
  所有逐行**绘制**循环都遍历槽位,再用 TyGridRowAtSlot 换成显示行号。

  为什么不直接扩 TyGridVisibleRows:它返回的是"正文窗口的行区间",被寻址/
  滚动/命中多处依赖,也被多条测试直接断言;把固定行塞进那个区间会连带改掉
  不该改的语义。绘制这一路单独走槽位,两边互不干扰。

  收口在一处的意义:"固定行也要画"只写一遍。从前它是在每个循环里各自
  (没)处理的 —— 十个循环全漏了,固定行占了高度、一个字都不画。 }
function TyGridDrawSlots(const M: TTyGridMetrics;
  out AFirst, ALast: Integer): Boolean;
function TyGridRowAtSlot(ASlot: Integer; const M: TTyGridMetrics): Integer;

function TyGridVisibleRows(const M: TTyGridMetrics;
  out AFirst, ALast: Integer): Boolean;

{ 纵坐标落在哪一行 —— **TyGridRowRect 的逆**。落在正文窗格之外、或超出 RowCount 时答 -1。

  刻意只做行轴:列轴用现成的 TTyColumns.ColumnFromPosition,几何层不重复实现列模型。

  不变量:**本函数必须恒为 TyGridRowRect 的逆**。一旦绘制与命中各算各的,就会在边界像素上
  分叉(本库在 Segmented/Alert/Tag/Pagination 上反复栽过这个跟头)。守住它的是逐像素反查的
  测试,而非某种特定写法 —— 见实现里的说明。 }
function TyGridFixedBottom(const M: TTyGridMetrics): Integer;
function TyGridRowAt(AY: Integer; const M: TTyGridMetrics): Integer;

implementation

{ 实际生效的底部固定行数。顶部固定行优先 —— 两者相加超过总行数时,
  底部让步,免得同一行既被钉在上面又被钉在下面。 }
function TyGridFixedBottom(const M: TTyGridMetrics): Integer;
var
  top: Integer;
begin
  Result := M.FixedRowsBottom;
  if Result < 0 then Result := 0;
  top := M.FixedRows;
  if top < 0 then top := 0;
  if top > M.RowCount then top := M.RowCount;
  if Result > M.RowCount - top then Result := M.RowCount - top;
  if Result < 0 then Result := 0;
end;

function TyGridHeaderH(const M: TTyGridMetrics): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(M.HeaderBands) do
    if M.HeaderBands[i] > 0 then Inc(Result, M.HeaderBands[i]);
end;

function TyGridHeaderBandRect(ALevel: Integer; const M: TTyGridMetrics): TRect;
var
  i, y, h: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  if (ALevel < 0) or (ALevel > High(M.HeaderBands)) then Exit;
  y := 0;
  for i := 0 to ALevel - 1 do
    if M.HeaderBands[i] > 0 then Inc(y, M.HeaderBands[i]);
  h := M.HeaderBands[ALevel];
  if h < 0 then h := 0;
  Result := Rect(0, y, M.ClientW, y + h);
end;

function TyGridPaneRect(const M: TTyGridMetrics; APane: TTyGridPane): TRect;
var
  cw, ch, fl, fr, ft, fb, k: Integer;
  xs, ys: array[0..3] of Integer;
begin
  { 先把视口与四条冻结带都钳到合法区间:同一方向的两条带之和不可能超过视口
    (那样正文窗格会反向),负厚度一律按 0 处理。钳制之后九个窗格必然铺满
    [0,cw]x[0,ch] 且互不重叠 —— 这条由面积守恒的测试守着。 }
  cw := M.ClientW; if cw < 0 then cw := 0;
  ch := M.ClientH; if ch < 0 then ch := 0;

  fl := M.FrozenLeft;   if fl < 0 then fl := 0; if fl > cw then fl := cw;
  fr := M.FrozenRight;  if fr < 0 then fr := 0; if fr > cw - fl then fr := cw - fl;
  ft := M.FrozenTop;    if ft < 0 then ft := 0; if ft > ch then ft := ch;
  fb := M.FrozenBottom; if fb < 0 then fb := 0; if fb > ch - ft then fb := ch - ft;

  xs[0] := 0;  xs[1] := fl;  xs[2] := cw - fr;  xs[3] := cw;
  ys[0] := 0;  ys[1] := ft;  ys[2] := ch - fb;  ys[3] := ch;

  k := Ord(APane);
  Result := Rect(xs[k mod 3], ys[k div 3], xs[k mod 3 + 1], ys[k div 3 + 1]);
end;

function TyGridCellContentRect(const ACell: TRect; const M: TTyGridMetrics): TRect;
var
  half: Integer;
begin
  Result := ACell;
  if M.GridLineWidth <= 1 then Exit;    { 发丝线:不内缩,与从前逐像素一致 }
  half := (M.GridLineWidth + 1) div 2;
  InflateRect(Result, -half, -half);
  { 单元格比线还窄时别返回反向矩形。 }
  if Result.Right < Result.Left then Result.Right := Result.Left;
  if Result.Bottom < Result.Top then Result.Bottom := Result.Top;
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
  nBot, i, botTop, botH: Integer;
begin
  TyGridRowExtent(ARow, M, top, h);

  if (M.FixedRows > 0) and (ARow < M.FixedRows) then
  begin
    { 固定行:钉在列头带之下、**不随滚动**。它们的位置从列头合计高度起算。 }
    y := TyGridHeaderH(M) + top;
    Result := Rect(0, y, M.ClientW, y + h);
    Exit;
  end;

  { 底部固定行:钉在视口下沿那条带里,自下而上排。 }
  nBot := TyGridFixedBottom(M);
  if (nBot > 0) and (ARow >= M.RowCount - nBot) then
  begin
    y := M.ClientH;
    for i := M.RowCount - 1 downto ARow do
    begin
      TyGridRowExtent(i, M, botTop, botH);
      Dec(y, botH);
    end;
    Result := Rect(0, y, M.ClientW, y + h);
    Exit;
  end;

  { 正文行:让开整条上冻结带并随滚动平移。注意要减掉固定行占的那段内容高度 ——
    否则第一条正文行会被推到固定行内容之后,与冻结带之间留出一个空洞。 }
  fixedTop := 0;
  fixedH := 0;
  if M.FixedRows > 0 then
    TyGridRowExtent(M.FixedRows, M, fixedTop, fixedH);
  y := M.FrozenTop + (top - fixedTop) - M.ScrollY;
  Result := Rect(0, y, M.ClientW, y + h);
end;

function TyGridRowBandRect(ARow: Integer; const M: TTyGridMetrics): TRect;
var
  nBot: Integer;
begin
  { 顶部固定行:列头之下、上冻结带之内。 }
  if (M.FixedRows > 0) and (ARow >= 0) and (ARow < M.FixedRows) then
    Exit(Rect(0, TyGridHeaderH(M), M.ClientW, M.FrozenTop));

  { 底部固定行:视口下沿那条带。 }
  nBot := TyGridFixedBottom(M);
  if (nBot > 0) and (ARow >= M.RowCount - nBot) then
    Exit(Rect(0, M.ClientH - M.FrozenBottom, M.ClientW, M.ClientH));

  { 正文:两条冻结带之间。 }
  Result := Rect(0, M.FrozenTop, M.ClientW, M.ClientH - M.FrozenBottom);
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

function TyGridRowAtSlot(ASlot: Integer; const M: TTyGridMetrics): Integer;
var
  bf, bl, nFixed, nBot, nBody: Integer;
begin
  nFixed := M.FixedRows;
  if nFixed < 0 then nFixed := 0;
  if nFixed > M.RowCount then nFixed := M.RowCount;
  if ASlot < 0 then Exit(-1);
  if ASlot < nFixed then Exit(ASlot);

  nBot := TyGridFixedBottom(M);
  if TyGridVisibleRows(M, bf, bl) then nBody := bl - bf + 1 else nBody := 0;

  { 尾段:底部固定行。 }
  if ASlot >= nFixed + nBody then
  begin
    Result := M.RowCount - nBot + (ASlot - nFixed - nBody);
    if (Result < 0) or (Result > M.RowCount - 1) then Result := -1;
    Exit;
  end;

  Result := bf + (ASlot - nFixed);
  if Result > bl then Result := -1;
end;

function TyGridDrawSlots(const M: TTyGridMetrics;
  out AFirst, ALast: Integer): Boolean;
var
  bf, bl, nFixed: Integer;
begin
  nFixed := M.FixedRows;
  if nFixed < 0 then nFixed := 0;
  if nFixed > M.RowCount then nFixed := M.RowCount;
  AFirst := 0;
  if TyGridVisibleRows(M, bf, bl) then
    ALast := nFixed + (bl - bf)
  else
    ALast := nFixed - 1;
  Inc(ALast, TyGridFixedBottom(M));
  Result := ALast >= AFirst;
  if not Result then
  begin
    AFirst := -1;
    ALast := -1;
  end;
end;

function TyGridVisibleRows(const M: TTyGridMetrics;
  out AFirst, ALast: Integer): Boolean;
var
  body: TRect;
  h, avail, fixedTop, fixedH, clipFirst, clipLast: Integer;
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
  { 底部固定行不在滚动窗口里 —— 它们由槽位的尾段负责。 }
  if TyGridFixedBottom(M) > 0 then
  begin
    if ALast > M.RowCount - 1 - TyGridFixedBottom(M) then
      ALast := M.RowCount - 1 - TyGridFixedBottom(M);
    if ALast < AFirst then
    begin
      AFirst := -1;
      ALast := -1;
      Exit(False);
    end;
  end;

  { 脏区重绘:再把窗口夹到指定的横带里。 }
  if M.ClipBottom > M.ClipTop then
  begin
    clipFirst := TyGridRowAt(M.ClipTop, M);
    if clipFirst < 0 then clipFirst := AFirst;
    clipLast := TyGridRowAt(M.ClipBottom - 1, M);
    if clipLast < 0 then clipLast := ALast;
    if clipFirst > AFirst then AFirst := clipFirst;
    if clipLast < ALast then ALast := clipLast;
  end;

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
  cand, fixedTop, fixedH, headerH: Integer;
  nBot, i, y, botTop, botH: Integer;
begin
  Result := -1;

  if M.RowCount <= 0 then Exit;
  if (M.RowH <= 0) and (Length(M.RowTops) <> M.RowCount + 1) then Exit;

  { 固定行带(列头之下、上冻结带之内)—— 它们也是真实的行,能点。 }
  headerH := TyGridHeaderH(M);
  if (M.FixedRows > 0) and (AY >= headerH) and (AY < M.FrozenTop) then
  begin
    cand := TyGridRowAtContentY(AY - headerH, M);
    if (cand >= 0) and (cand < M.FixedRows) then Result := cand;
    Exit;
  end;

  { 底部固定行带 —— 与顶部对称,也是真实的行,能点。
    自下而上一行行地量,与 TyGridRowRect 那边同一套算法(它是这里的逆)。 }
  nBot := TyGridFixedBottom(M);
  if (nBot > 0) and (AY >= M.ClientH - M.FrozenBottom) and (AY < M.ClientH) then
  begin
    y := M.ClientH;
    for i := M.RowCount - 1 downto M.RowCount - nBot do
    begin
      TyGridRowExtent(i, M, botTop, botH);
      Dec(y, botH);
      if AY >= y then Exit(i);
    end;
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
  cand := TyGridRowAtContentY(AY - M.FrozenTop + M.ScrollY + fixedTop, M);
  if (cand < M.FixedRows) or (cand > M.RowCount - 1 - nBot) then Exit;
  Result := cand;
end;

end.
