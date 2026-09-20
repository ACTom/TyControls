unit tyControls.ToolWindows;
{$mode objfpc}{$H+}

{ IDE 工作台的侧栏 / 底栏。设计定稿见
  docs/superpowers/specs/2026-09-17-toolwindow-workbench-design.md。
  四个类同在一个单元:窗口与栏互相引用,拆单元只会多一圈前向声明。 }

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Base, tyControls.Component;

const
  { 长度 token。经典值必须等于这里的 Def —— light.tycss 的 :root 里写同一个数,
    不然加 token 这一步会悄悄给控件换一套尺寸。 }
  TyToolWindowHeaderHeightVar = '--toolwindow-header-height';
  TyToolWindowHeaderHeightDef = 26;
  TyToolWindowHeaderPadVar    = '--toolwindow-header-pad';
  TyToolWindowHeaderPadDef    = 6;
  TyToolWindowHeaderGapVar    = '--toolwindow-header-gap';
  TyToolWindowHeaderGapDef    = 4;
  TyToolWindowTabPadVar       = '--toolwindow-tab-pad';
  TyToolWindowTabPadDef       = 10;
  TyToolWindowTabAreaMinVar   = '--toolwindow-tab-area-min';
  TyToolWindowTabAreaMinDef   = 50;
  TyToolWindowIndicatorSizeVar = '--toolwindow-indicator-size';
  TyToolWindowIndicatorSizeDef = 2;
  TyToolWindowStripIndicatorSizeVar = '--toolwindow-strip-indicator-size';
  TyToolWindowStripIndicatorSizeDef = 2;
  TyToolWindowButtonSizeVar   = '--toolwindow-button-size';
  TyToolWindowButtonSizeDef   = 22;
  TyToolWindowGlyphSizeVar    = '--toolwindow-glyph-size';
  TyToolWindowGlyphSizeDef    = 16;
  TyToolWindowContentMinVar   = '--toolwindow-content-min';
  TyToolWindowContentMinDef   = 120;
  TyToolWindowStripSizeVar    = '--toolwindow-strip-size';
  TyToolWindowStripSizeDef    = 36;
  TyToolWindowStripItemSizeVar = '--toolwindow-strip-item-size';
  TyToolWindowStripItemSizeDef = 36;
  TyToolWindowEdgeSizeVar     = '--toolwindow-edge-size';
  TyToolWindowEdgeSizeDef     = 4;
  TyToolWindowDropSizeVar     = '--toolwindow-drop-size';
  TyToolWindowDropSizeDef     = 2;

  { 展开尺寸的出厂值。侧栏与底栏共用一个数:Pascal 的 published default 只能是常量,
    按 Placement 分两个数会让 .lfm 省略掉其中一侧的值、加载后变成另一侧的默认。
    名字不叫 ...Def —— 本库的 ...Var / ...Def 成对只用于「主题 token 与它的回落值」。 }
  TyToolWindowDefaultExpandedSize = 240;

  { 拖动阈值(逻辑像素)与点击防抖(毫秒)。 }
  TyToolWindowDragThresholdPx = 6;
  TyToolWindowClickGuardMs    = 300;

type
  TTyToolWindowPlacement = (twpLeft, twpRight, twpBottom);
  TTyToolWindowHeaderMode = (twhNone, twhSide, twhBottom);

  TTyToolWindowBar = class;
  TTyToolWindowActions = class;
  TTyToolWindowManager = class;

  { GetStyleTypeKey 在 TTyCustomControl 上是 abstract,不覆写就等于注册了一个
    「一解析样式就抛 EAbstractError」的类 —— 而 RegisterClass 已经把它交给流式化了。
    类型键是契约不是实现,A 期就钉死。 }
  TTyToolWindow = class(TTyCustomControl)
  protected
    function GetStyleTypeKey: string; override;
  end;

  TTyToolWindowActions = class(TTyCustomControl)
  protected
    function GetStyleTypeKey: string; override;
  end;

  TTyToolWindowBar = class(TTyCustomControl)
  protected
    function GetStyleTypeKey: string; override;
  end;

  { A 期只建壳:栏的 Manager 属性要到 C 期才接线,但类名先占住,
    免得 B 期的测试和 .lfm 里写出两个名字。
    继承 TTyComponent(不是 TComponent):全库非可视组件都从它来,它带着
    对象查看器里那个只读 Version。 }
  TTyToolWindowManager = class(TTyComponent)
  end;

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

  { 排布的全部输入。尺寸一律是**设备像素**,调用方缩放好再传。 }
  TTyToolWindowHeaderInput = record
    Mode: TTyToolWindowHeaderMode;
    RowWidth, RowHeight: Integer;
    Pad, Gap: Integer;
    ActionsWidth: Integer;      { 操作区 raw 首选宽;0 = 没有操作区 }
    TabWidths: array of Integer;{ 底栏:每个窗口的标签想要的宽 }
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
    Hidden: array of Integer;   { 底栏:收进溢出菜单的窗口序号 }
  end;

{ --- 纯规则 / 几何(无控件、无句柄、无主题,可无头测) ------------------------ }

{ 按顺序放,遇到第一个放不下的就停;当前页不在里面就追加到末尾,再从它前面一个
  开始往前挤,直到放得下。返回的是**窗口序号**的可见计划。 }
function TyToolWindowVisiblePlan(AAvail: Integer; const AWidths: array of Integer;
  AActiveIndex, AOverflowWidth: Integer; out AAnyHidden: Boolean): TTyToolWindowPlan;

function TyToolWindowHeaderLayout(const AInput: TTyToolWindowHeaderInput): TTyToolWindowHeaderGeom;

{ 图标条 / 标签行的插入槽:按已排布项的中点分。返回 0..N 的**窗口序号**位置。 }
function TyToolWindowSlotAt(const ASlots: TTyToolWindowSlots; X, Y: Integer;
  AVertical: Boolean; ACount: Integer): Integer;

{ 图标条排布(竖直)。 }
function TyToolWindowStripLayout(AStripWidth, AStripHeight, AItemSize, AOverflowSize: Integer;
  ACount, AActiveIndex: Integer; out AAnyHidden: Boolean): TTyToolWindowSlots;

function TyToolWindowDragThreshold(APPI: Integer): Integer;

implementation

function TTyToolWindow.GetStyleTypeKey: string;
begin
  Result := 'TyToolWindow';
end;

function TTyToolWindowActions.GetStyleTypeKey: string;
begin
  Result := 'TyToolWindowActions';
end;

function TTyToolWindowBar.GetStyleTypeKey: string;
begin
  Result := 'TyToolWindowBar';
end;

function TyToolWindowHeaderLayout(const AInput: TTyToolWindowHeaderInput): TTyToolWindowHeaderGeom;

  function Flip(const ARect: TRect): TRect;
  begin
    { 空矩形保持全零:把「没有操作区」镜像成 (RowWidth,0,RowWidth,0)
      会让零值看起来像个真位置。算术交给 LCL 自己那五行
      (controls.pp:2966),跟 CheckGroup / Columns 同一个调用。 }
    if ARect.Right <= ARect.Left then Exit(ARect);
    Result := BidiFlipRect(ARect, Rect(0, 0, AInput.RowWidth, AInput.RowHeight), True);
  end;

var
  pad, gap, aw, x: Integer;
begin
  Result := Default(TTyToolWindowHeaderGeom);
  Result.Tabs := nil;                { FPC 3.2 不认 SetLength 初始化 managed result }
  Result.Hidden := nil;
  if (AInput.RowWidth <= 0) or (AInput.RowHeight <= 0) then Exit;
  pad := AInput.Pad; if pad < 0 then pad := 0;
  gap := AInput.Gap; if gap < 0 then gap := 0;
  aw := AInput.ActionsWidth; if aw < 0 then aw := 0;
  if aw > AInput.RowWidth - pad then aw := AInput.RowWidth - pad;

  if AInput.Mode = twhSide then
  begin
    { 贴右端的操作区只是侧栏的答案。底栏从尾端往前是
      [收起][最大化][分隔线][操作区][溢出][标签…](spec §7.3),操作区不在最右端;
      twhNone 的操作区按 raw 首选尺寸放在正文左上角(spec §3.2)。
      在分支外面算就等于给那两支发一个看起来合法的错答案。 }
    if aw > 0 then
    begin
      Result.Actions := Rect(AInput.RowWidth - pad - aw, 0, AInput.RowWidth - pad, AInput.RowHeight);
      x := Result.Actions.Left - gap;
    end
    else
      x := AInput.RowWidth - pad;         { 没有操作区,尾端补一个内距 }
    if x > pad then
      Result.Caption := Rect(pad, 0, x, AInput.RowHeight);
    { 标题拿下整个剩余跨度 —— spec §3.4:“操作区优先保宽;标题先省略号”。
      放不下由 DrawText 自己出省略号,所以这里没有「标题想要多宽」这个输入。 }
  end;
  { twhBottom 那一支在 B 期实现;twhNone 什么都不排。 }

  if AInput.RightToLeft then
  begin
    { spec §7.3:整套几何按 LTR 算一次,再按行宽镜像。
      镜像只动横向:标题行高就是行高。 }
    Result.Caption := Flip(Result.Caption);
    Result.Actions := Flip(Result.Actions);
  end;
end;

function TyToolWindowVisiblePlan(AAvail: Integer; const AWidths: array of Integer;
  AActiveIndex, AOverflowWidth: Integer; out AAnyHidden: Boolean): TTyToolWindowPlan;

  function Fill(ABudget: Integer): TTyToolWindowPlan;
  var
    i, used: Integer;
  begin
    Result := nil;
    used := 0;
    for i := 0 to High(AWidths) do
    begin
      if used + AWidths[i] > ABudget then Break;   { 遇到第一个放不下的就停 }
      Inc(used, AWidths[i]);
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := i;
    end;
  end;

  function Has(const APlan: TTyToolWindowPlan; AIdx: Integer): Boolean;
  var i: Integer;
  begin
    Result := False;
    for i := 0 to High(APlan) do
      if APlan[i] = AIdx then Exit(True);
  end;

  function Width(const APlan: TTyToolWindowPlan): Integer;
  var i: Integer;
  begin
    Result := 0;
    for i := 0 to High(APlan) do Inc(Result, AWidths[APlan[i]]);
  end;

var
  plan: TTyToolWindowPlan;
  budget, i: Integer;
begin
  Result := nil;
  AAnyHidden := False;
  if Length(AWidths) = 0 then Exit;
  if AAvail <= 0 then
  begin
    { spec §7.3:当前页始终留在行上。「留出溢出按钮后一个都放不下」
      那条路径就是这么答的 —— 这里不一致的话,栏宽收到 0 会把当前页也弄丢。 }
    if (AActiveIndex >= 0) and (AActiveIndex <= High(AWidths)) then
    begin
      SetLength(Result, 1);
      Result[0] := AActiveIndex;
    end;
    AAnyHidden := Length(Result) < Length(AWidths);
    Exit;
  end;
  plan := Fill(AAvail);
  AAnyHidden := Length(plan) < Length(AWidths);
  if AAnyHidden then
  begin
    { 确实有东西被收起来了,才给溢出按钮留位置,然后重排一次。 }
    budget := AAvail - AOverflowWidth;
    if budget < 0 then budget := 0;
    plan := Fill(budget);
    { 当前页强制留在行上:追加到末尾,再从它前面一个开始往前挤。 }
    if (AActiveIndex >= 0) and (AActiveIndex <= High(AWidths)) and not Has(plan, AActiveIndex) then
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
    AAnyHidden := Length(plan) < Length(AWidths);
  end;
  Result := plan;
end;

function TyToolWindowSlotAt(const ASlots: TTyToolWindowSlots; X, Y: Integer;
  AVertical: Boolean; ACount: Integer): Integer;
var
  i, mid, pos: Integer;
begin
  { 已排布项不一定是窗口列表的前缀(当前页被强制留下),所以空隙映射到**它对应窗口的序号**,
    不是排布序号。 }
  Result := ACount;
  if Length(ASlots) = 0 then Exit;
  for i := 0 to High(ASlots) do
  begin
    if AVertical then
    begin
      mid := (ASlots[i].ItemRect.Top + ASlots[i].ItemRect.Bottom) div 2;
      pos := Y;
    end
    else
    begin
      mid := (ASlots[i].ItemRect.Left + ASlots[i].ItemRect.Right) div 2;
      pos := X;
    end;
    if pos < mid then Exit(ASlots[i].ItemIndex);
  end;
  Result := ASlots[High(ASlots)].ItemIndex + 1;
end;

function TyToolWindowStripLayout(AStripWidth, AStripHeight, AItemSize, AOverflowSize: Integer;
  ACount, AActiveIndex: Integer; out AAnyHidden: Boolean): TTyToolWindowSlots;
var
  widths: array of Integer;
  plan: TTyToolWindowPlan;
  i, y: Integer;
begin
  Result := nil;
  AAnyHidden := False;
  if (ACount <= 0) or (AItemSize <= 0) or (AStripWidth <= 0) or (AStripHeight <= 0) then Exit;
  widths := nil;
  SetLength(widths, ACount);
  for i := 0 to ACount - 1 do widths[i] := AItemSize;   { 图标是方的,等宽 }
  plan := TyToolWindowVisiblePlan(AStripHeight, widths, AActiveIndex, AOverflowSize, AAnyHidden);
  SetLength(Result, Length(plan));
  y := 0;
  for i := 0 to High(plan) do
  begin
    Result[i].ItemIndex := plan[i];
    Result[i].ItemRect := Rect(0, y, AStripWidth, y + AItemSize);
    Inc(y, AItemSize);
  end;
end;

function TyToolWindowDragThreshold(APPI: Integer): Integer;
begin
  if APPI <= 0 then APPI := 96;
  Result := MulDiv(TyToolWindowDragThresholdPx, APPI, 96);
  if Result < 1 then Result := 1;
end;

initialization
  { 运行时 .lfm 按类名实例化流里的子对象,四个都要注册。 }
  RegisterClass(TTyToolWindow);
  RegisterClass(TTyToolWindowActions);
  RegisterClass(TTyToolWindowBar);
  RegisterClass(TTyToolWindowManager);
end.
