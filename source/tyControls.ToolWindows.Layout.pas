unit tyControls.ToolWindows.Layout;
{$mode objfpc}{$H+}

{ 工具窗口工作台的纯规则 / 几何:无控件、无句柄、无主题,可无头测。
  控件本身在 tyControls.ToolWindows。设计定稿见
  docs/superpowers/specs/2026-09-17-toolwindow-workbench-design.md。 }

interface

uses
  Types;

const
  { 拖动阈值(逻辑像素)。 }
  TyToolWindowDragThresholdPx = 6;

type
  TTyToolWindowHeaderMode = (twhNone, twhSide, twhBottom);

  { 标题行的一个可点部件。返回它的命中测跟底栏一起在 B 期落地。 }
  TTyToolWindowZone = (twzNone, twzTab, twzOverflow, twzSeparator, twzMaximize, twzCollapse);

  { 一个标签 / 一个图标的槽位。ItemIndex 是**窗口序号**,不是排布序号 ——
    当前页被强制留在条上时,已排布的项不再是窗口列表的前缀。 }
  TTyToolWindowSlot = record
    ItemIndex: Integer;
    ItemRect: TRect;
  end;
  TTyToolWindowSlots = array of TTyToolWindowSlot;

  { 可见计划:按排布顺序列出的**窗口序号**。 }
  TTyToolWindowPlan = array of Integer;

  { 一排宽度:设备像素,按**窗口序号**索引。 }
  TTyToolWindowWidths = array of Integer;

  { 排布的全部输入。尺寸一律是**设备像素**,调用方缩放好再传。 }
  TTyToolWindowHeaderInput = record
    Mode: TTyToolWindowHeaderMode;
    RowWidth, RowHeight: Integer;
    Pad, Gap: Integer;
    ActionsWidth: Integer;      { 操作区 raw 首选宽;0 = 没有操作区 }
    TabWidths: TTyToolWindowWidths; { 底栏:每个窗口的标签想要的宽 }
    ActiveIndex: Integer;
    TabAreaMin: Integer;
    ButtonSize: Integer;        { 底栏:最大化 / 收起 }
    SeparatorWidth: Integer;
    OverflowWidth: Integer;
    RightToLeft: Boolean;
  end;

  TTyToolWindowHeaderGeom = record
    Caption: TRect;             { 侧栏 }
    Actions: TRect;
    TabArea: TRect;             { 底栏:标签可用区 }
    Tabs: TTyToolWindowSlots;   { 底栏:真正排上去的标签 }
    Overflow: TRect;
    Separator: TRect;
    Maximize: TRect;
    Collapse: TRect;
    Hidden: TTyToolWindowPlan;  { 底栏:收进溢出菜单的窗口序号 }
  end;

  { 操作区那一排的一项输入(设备像素)。宽、高各按 max(本值, 下限) 算:TTyButton 按标题
    设 MinWidth(Button.pas:702),SetBounds 会把它撑得比 Width 宽 —— 只按 Width 排,
    撑宽的那一个就压到下一个身上。 }
  TTyToolWindowFlowItem = record
    Width, Height, MinWidth, MinHeight: Integer;
  end;
  TTyToolWindowFlowItems = array of TTyToolWindowFlowItem;

  { 操作区那一排的答案:每项的矩形(区域内坐标,与输入同序)和整排的 raw 首选尺寸。 }
  TTyToolWindowFlow = record
    Rects: array of TRect;
    Size: TSize;
  end;

{ 按顺序放,遇到第一个放不下的就停;当前页不在里面就追加到末尾,再从它前面一个
  开始往前挤,直到放得下。返回的是**窗口序号**的可见计划。
  有没有东西被收起来,调用方自己算 `Length(计划) < 窗口总数` ——
  多一个 out 参数买不到任何信息,只会多一处能跟这个恒等式不一致的地方。 }
function TyToolWindowVisiblePlan(AAvail: Integer; const AWidths: array of Integer;
  AActiveIndex, AOverflowWidth: Integer): TTyToolWindowPlan;

function TyToolWindowHeaderLayout(const AInput: TTyToolWindowHeaderInput): TTyToolWindowHeaderGeom;

{ 把排好的整套几何按行宽镜像(spec §7.3)。每个矩形字段和每个槽位都过一遍,
  所以 B 期给 Geom 加部件不用记得回来添一行。

  就地改,而且**不幂等**:TyToolWindowHeaderLayout 在 RightToLeft 为真时已经替你调过了,
  拿到它的结果别再调第二次 —— 镜像两次等于没镜像,而 LTR 那边照样全绿。
  ARowWidth 必须就是排布时用的那个 RowWidth;传成别的(比如此刻的 ClientWidth)不会报错,
  整套几何会整体平移,同样不会红。 }
procedure TyToolWindowFlipAll(var AGeom: TTyToolWindowHeaderGeom; ARowWidth: Integer);

{ 两套几何是否一模一样:每个矩形字段、每个标签槽(窗口序号 + 矩形)、收进溢出菜单的
  序号都比。同 TyToolWindowFlipAll,一处过完所有字段 —— 只比手挑的几个,B 期标签宽变了
  而控件尺寸没变,窗口就会 blit 出旧的那一帧。 }
function TyToolWindowSameGeom(const A, B: TTyToolWindowHeaderGeom): Boolean;

{ 操作区自己那一排(spec §4):按顺序从左往右,两端各 APad、之间 AGap;每项宽按
  max(Width, MinWidth)、高按 max(Height, MinHeight),在 AAvailH 里垂直居中。整排比
  AAvailW 宽时贴尾端(裁掉的是开头的);ARightToLeft 时按 AAvailW 整排镜像。
  Size 与 AAvailW / AAvailH 无关;一项都没有时 Size = (0, 0)、Rects 为空。 }
function TyToolWindowActionsFlow(const AItems: array of TTyToolWindowFlowItem;
  AAvailW, AAvailH, APad, AGap: Integer; ARightToLeft: Boolean): TTyToolWindowFlow;

{ 图标条 / 标签行的插入槽:按已排布项的中点分。返回 0..N 的**窗口序号**位置。 }
function TyToolWindowSlotAt(const ASlots: TTyToolWindowSlots; X, Y: Integer;
  AVertical: Boolean; ACount: Integer): Integer;

{ 图标条排布(竖直)。 }
function TyToolWindowStripLayout(AStripWidth, AStripHeight, AItemSize, AOverflowSize: Integer;
  ACount, AActiveIndex: Integer): TTyToolWindowSlots;

function TyToolWindowDragThreshold(APPI: Integer): Integer;

implementation

uses
  LCLType,   { MulDiv }
  Controls;  { BidiFlipRect:LCL 自己的镜像算术 }

procedure TyToolWindowFlipAll(var AGeom: TTyToolWindowHeaderGeom; ARowWidth: Integer);
var
  span: TRect;
  i: Integer;

  function Flip(const ARect: TRect): TRect;
  begin
    { 只豁免全零那个「没有这个部件」的哨兵。被挤成零宽但**有位置**的部件照样要镜像 ——
      放过它的话它会原地留在 LTR 坐标,而 LTR 那边全绿。 }
    if (ARect.Left = 0) and (ARect.Right = 0) and (ARect.Top = 0) and (ARect.Bottom = 0) then
      Exit(ARect);
    Result := BidiFlipRect(ARect, span, True);
  end;

begin
  { 末尾一次过完每个矩形字段 —— 逐字段列在调用处的话,B 期加一个部件漏一行不会红。
    算术交给 LCL 自己那五行(controls.pp:2966),跟 CoolBar / ControlBar 同一个调用。
    span 的高写 0:纵向不动,这本身就是声明。 }
  span := Rect(0, 0, ARowWidth, 0);
  AGeom.Caption := Flip(AGeom.Caption);
  AGeom.Actions := Flip(AGeom.Actions);
  AGeom.TabArea := Flip(AGeom.TabArea);
  AGeom.Overflow := Flip(AGeom.Overflow);
  AGeom.Separator := Flip(AGeom.Separator);
  AGeom.Maximize := Flip(AGeom.Maximize);
  AGeom.Collapse := Flip(AGeom.Collapse);
  for i := 0 to High(AGeom.Tabs) do
    AGeom.Tabs[i].ItemRect := Flip(AGeom.Tabs[i].ItemRect);
end;

function TyToolWindowSameGeom(const A, B: TTyToolWindowHeaderGeom): Boolean;
var
  i: Integer;
begin
  { 跟 TyToolWindowFlipAll 同一份字段清单,一处过完 —— B 期给 Geom 加部件时,这里和
    那里挨着,漏一行看得见。 }
  Result := False;
  if not EqualRect(A.Caption, B.Caption) then Exit;
  if not EqualRect(A.Actions, B.Actions) then Exit;
  if not EqualRect(A.TabArea, B.TabArea) then Exit;
  if not EqualRect(A.Overflow, B.Overflow) then Exit;
  if not EqualRect(A.Separator, B.Separator) then Exit;
  if not EqualRect(A.Maximize, B.Maximize) then Exit;
  if not EqualRect(A.Collapse, B.Collapse) then Exit;
  if Length(A.Tabs) <> Length(B.Tabs) then Exit;
  for i := 0 to High(A.Tabs) do
  begin
    if A.Tabs[i].ItemIndex <> B.Tabs[i].ItemIndex then Exit;
    if not EqualRect(A.Tabs[i].ItemRect, B.Tabs[i].ItemRect) then Exit;
  end;
  if Length(A.Hidden) <> Length(B.Hidden) then Exit;
  for i := 0 to High(A.Hidden) do
    if A.Hidden[i] <> B.Hidden[i] then Exit;
  Result := True;
end;

function TyToolWindowActionsFlow(const AItems: array of TTyToolWindowFlowItem;
  AAvailW, AAvailH, APad, AGap: Integer; ARightToLeft: Boolean): TTyToolWindowFlow;
var
  ws, hs: array of Integer;
  n, i, sum, tallest, x, left: Integer;
begin
  Result := Default(TTyToolWindowFlow);
  n := Length(AItems);
  if n = 0 then Exit;
  { 同 TyToolWindowHeaderLayout:度量值不钳,负的内距 / 间距按 0 算。 }
  if APad < 0 then APad := 0;
  if AGap < 0 then AGap := 0;
  ws := nil;
  hs := nil;
  SetLength(ws, n);
  SetLength(hs, n);
  sum := 0;
  tallest := 0;
  for i := 0 to n - 1 do
  begin
    ws[i] := AItems[i].Width;
    if AItems[i].MinWidth > ws[i] then ws[i] := AItems[i].MinWidth;
    if ws[i] < 0 then ws[i] := 0;
    hs[i] := AItems[i].Height;
    if AItems[i].MinHeight > hs[i] then hs[i] := AItems[i].MinHeight;
    if hs[i] < 0 then hs[i] := 0;
    Inc(sum, ws[i]);
    if hs[i] > tallest then tallest := hs[i];
  end;
  Result.Size.cx := 2 * APad + sum + (n - 1) * AGap;
  Result.Size.cy := tallest + 2 * APad;
  { 放得下从前导内距开始;放不下整排贴尾端,被裁掉的是开头的。 }
  if Result.Size.cx <= AAvailW then x := APad
  else x := AAvailW - Result.Size.cx + APad;
  SetLength(Result.Rects, n);
  for i := 0 to n - 1 do
  begin
    { 从右往左读时整排按宽镜像:第一个到右端,贴尾端就成了贴左端,被裁的仍是开头那个。 }
    if ARightToLeft then left := AAvailW - x - ws[i]
    else left := x;
    Result.Rects[i] := Bounds(left, (AAvailH - hs[i]) div 2, ws[i], hs[i]);
    Inc(x, ws[i] + AGap);
  end;
end;

function TyToolWindowHeaderLayout(const AInput: TTyToolWindowHeaderInput): TTyToolWindowHeaderGeom;
var
  pad, gap, aw, x: Integer;
begin
  Result := Default(TTyToolWindowHeaderGeom);
  if (AInput.RowWidth <= 0) or (AInput.RowHeight <= 0) then Exit;
  pad := AInput.Pad; if pad < 0 then pad := 0;
  gap := AInput.Gap; if gap < 0 then gap := 0;
  aw := AInput.ActionsWidth; if aw < 0 then aw := 0;

  if AInput.Mode = twhSide then
  begin
    { 贴右端的操作区只是侧栏的答案。底栏从尾端往前是
      [收起][最大化][分隔线][操作区][溢出][标签…](spec §7.3),操作区不在最右端;
      twhNone 的操作区按 raw 首选尺寸放在正文左上角(spec §3.2)。
      在分支外面算就等于给那两支发一个看起来合法的错答案 —— 下面的钳位也一样。 }
    { 只给前导那个内距让位:尾端的 pad 由操作区自己带着(它的首选宽里就有两侧的 2×pad),
      spec §3.4「操作区自带内边距,宽为 0 时尾端补一个 header-pad」。 }
    if aw > AInput.RowWidth - pad then aw := AInput.RowWidth - pad;
    if aw > 0 then
    begin
      { 贴到行的右端:再补一个 pad 的话,最后一个按钮离右边就是 2×pad。 }
      Result.Actions := Rect(AInput.RowWidth - aw, 0, AInput.RowWidth, AInput.RowHeight);
      x := Result.Actions.Left - gap;
    end
    else
      x := AInput.RowWidth - pad;         { 没有操作区,尾端补一个内距 }
    if x > pad then
      Result.Caption := Rect(pad, 0, x, AInput.RowHeight);
    { 标题拿下整个剩余跨度 —— spec §3.4:"操作区优先保宽;标题先省略号"。
      放不下由 DrawText 自己出省略号,所以这里没有「标题想要多宽」这个输入。 }
  end;
  { twhBottom 那一支在 B 期实现;twhNone 什么都不排。 }

  if AInput.RightToLeft then
    TyToolWindowFlipAll(Result, AInput.RowWidth);
end;

function TyToolWindowVisiblePlan(AAvail: Integer; const AWidths: array of Integer;
  AActiveIndex, AOverflowWidth: Integer): TTyToolWindowPlan;
var
  w: TTyToolWindowWidths;
  plan: TTyToolWindowPlan;
  n, budget, i: Integer;

  function Fill(ABudget: Integer): TTyToolWindowPlan;
  var
    k, used: Integer;
  begin
    Result := nil;
    used := 0;
    for k := 0 to n - 1 do
    begin
      if used + w[k] > ABudget then Break;   { 遇到第一个放不下的就停 }
      Inc(used, w[k]);
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := k;
    end;
  end;

  function Has(const APlan: TTyToolWindowPlan; AIdx: Integer): Boolean;
  var k: Integer;
  begin
    Result := False;
    for k := 0 to High(APlan) do
      if APlan[k] = AIdx then Exit(True);
  end;

  function Width(const APlan: TTyToolWindowPlan): Integer;
  var k: Integer;
  begin
    Result := 0;
    for k := 0 to High(APlan) do Inc(Result, w[APlan[k]]);
  end;

begin
  Result := nil;
  n := Length(AWidths);
  if n = 0 then Exit;
  { 负数入参在这里一次钳干净,下面的算术就能直着读(照 Breadcrumb 的规矩)。
    不钳的话:负的项宽让累加倒退、负的溢出按钮宽把预算放大,两个都能骗过「放不下就停」。
    B 期的 TabWidths 是量文字来的,一次测量失败就能喂进 0 或负数。 }
  w := nil;
  SetLength(w, n);
  for i := 0 to n - 1 do
  begin
    w[i] := AWidths[i];
    if w[i] < 0 then w[i] := 0;
  end;
  if AOverflowWidth < 0 then AOverflowWidth := 0;

  if AAvail <= 0 then
  begin
    { spec §7.3:当前页始终留在行上。「留出溢出按钮后一个都放不下」
      那条路径就是这么答的 —— 这里不一致的话,栏宽收到 0 会把当前页也弄丢。 }
    if (AActiveIndex >= 0) and (AActiveIndex < n) then
    begin
      SetLength(Result, 1);
      Result[0] := AActiveIndex;
    end;
    Exit;
  end;

  plan := Fill(AAvail);
  if Length(plan) < n then
  begin
    { 确实有东西被收起来了,才给溢出按钮留位置,然后重排一次。 }
    budget := AAvail - AOverflowWidth;
    if budget < 0 then budget := 0;
    plan := Fill(budget);
    { 当前页强制留在行上:追加到末尾,再从它前面一个开始往前挤。 }
    if (AActiveIndex >= 0) and (AActiveIndex < n) and not Has(plan, AActiveIndex) then
    begin
      SetLength(plan, Length(plan) + 1);
      plan[High(plan)] := AActiveIndex;
      i := Length(plan) - 2;
      while (i >= 0) and (Width(plan) > budget) do
      begin
        Delete(plan, i, 1);
        Dec(i);
      end;
    end;
  end;
  Result := plan;
end;

function TyToolWindowSlotAt(const ASlots: TTyToolWindowSlots; X, Y: Integer;
  AVertical: Boolean; ACount: Integer): Integer;
var
  i, mid, pos, last: Integer;
  R: TRect;
begin
  { 已排布项不一定是窗口列表的前缀(当前页被强制留下),所以空隙映射到**它对应窗口的序号**,
    不是排布序号。 }
  if Length(ASlots) = 0 then Exit(ACount);
  last := -1;
  for i := 0 to High(ASlots) do
  begin
    R := ASlots[i].ItemRect;
    { 空槽没有中点可言,跳过 —— B 期 Geom.Tabs 会带被挤成零的槽位。 }
    if (R.Right <= R.Left) or (R.Bottom <= R.Top) then Continue;
    last := i;
    if AVertical then
    begin
      mid := (R.Top + R.Bottom) div 2;
      pos := Y;
    end
    else
    begin
      mid := (R.Left + R.Right) div 2;
      pos := X;
    end;
    if pos < mid then Exit(ASlots[i].ItemIndex);
  end;
  if last < 0 then Exit(ACount);          { 全是空槽 }
  Result := ASlots[last].ItemIndex + 1;
end;

function TyToolWindowStripLayout(AStripWidth, AStripHeight, AItemSize, AOverflowSize: Integer;
  ACount, AActiveIndex: Integer): TTyToolWindowSlots;
var
  widths: TTyToolWindowWidths;
  plan: TTyToolWindowPlan;
  i, y, t, b: Integer;
begin
  Result := nil;
  if (ACount <= 0) or (AItemSize <= 0) or (AStripWidth <= 0) or (AStripHeight <= 0) then Exit;
  widths := nil;
  SetLength(widths, ACount);
  for i := 0 to ACount - 1 do widths[i] := AItemSize;   { 图标是方的,等宽 }
  plan := TyToolWindowVisiblePlan(AStripHeight, widths, AActiveIndex, AOverflowSize);
  SetLength(Result, Length(plan));
  y := 0;
  for i := 0 to High(plan) do
  begin
    { 条裁掉它。条矮到放不下一个图标时当前页仍然被强制留下,那个槽位不裁就会戳在条外面;
      同时保证不反转。 }
    t := y;
    if t > AStripHeight then t := AStripHeight;
    b := y + AItemSize;
    if b > AStripHeight then b := AStripHeight;
    if b < t then b := t;
    Result[i].ItemIndex := plan[i];
    Result[i].ItemRect := Rect(0, t, AStripWidth, b);
    Inc(y, AItemSize);
  end;
end;

function TyToolWindowDragThreshold(APPI: Integer): Integer;
begin
  if APPI <= 0 then APPI := 96;
  Result := MulDiv(TyToolWindowDragThresholdPx, APPI, 96);
  if Result < 1 then Result := 1;
end;

end.
