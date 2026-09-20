unit tyControls.ToolWindows;
{$mode objfpc}{$H+}

{ IDE 工作台的侧栏 / 底栏。设计定稿见
  docs/superpowers/specs/2026-09-17-toolwindow-workbench-design.md。
  四个类同在一个单元:窗口与栏互相引用,拆单元只会多一圈前向声明。 }

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, LMessages,
  tyControls.Types, tyControls.Base, tyControls.Component, tyControls.Painter,
  tyControls.StyleModel;

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
  private
    FImageName: string;
    FImageIndex: Integer;
    FStripHint: string;
    FOnShow: TNotifyEvent;
    FOnHide: TNotifyEvent;
    { 标题行高的 token 那一项的缓存,键 = (PPI, model 身份, 主题版本, RTL, 标题行模式);
      -1 = 没缓存。操作区那一项不进这里,见 HeaderHeightPx。 }
    FHeaderPxCache: Integer;
    FHeaderPxPPI: Integer;
    FHeaderPxVer: Cardinal;
    FHeaderPxAnchor: TObject;
    FHeaderPxRTL: Boolean;
    FHeaderPxMode: TTyToolWindowHeaderMode;
    FRelayouting: Boolean;
    function ImageIndexIsStored: Boolean;
    function GetBar: TTyToolWindowBar;
    function GetActions: TTyToolWindowActions;
  protected
    FPaintCache: TTyPaintCache;      { protected:测试要能问「重渲染了没有」 }
    function GetStyleTypeKey: string; override;
    procedure TextChanged; override;
    procedure AdjustClientRect(var ARect: TRect); override;
    procedure AutoAdjustLayout(AMode: TLayoutAdjustmentPolicy;
      const AFromPPI, AToPPI, AOldFormWidth, ANewFormWidth: Integer); override;
    procedure CMBiDiModeChanged(var Msg: TLMessage); message CM_BIDIMODECHANGED;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Invalidate; override;
    procedure Paint; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure RelayoutHeader;
    function HeaderMode: TTyToolWindowHeaderMode;
    function HeaderHeightPx: Integer;
    function HeaderRowRect: TRect;
    function BodyRect: TRect;
    property Bar: TTyToolWindowBar read GetBar;
    property Actions: TTyToolWindowActions read GetActions;
  published
    property Caption;
    property ImageName: string read FImageName write FImageName;
    property ImageIndex: Integer read FImageIndex write FImageIndex
      stored ImageIndexIsStored default -1;
    property StripHint: string read FStripHint write FStripHint;
    property StyleClass;
    { 栏推给窗口、窗口再推给操作区;不进 .lfm(读进来的时机在注册之后,两边会漂开)。 }
    property Controller stored False;
    property Left stored False;
    property Top stored False;
    property Width stored False;
    property Height stored False;
    property TabOrder stored False;
    property Visible stored False;
    { 切页的触发边是 Visible —— 栏把当前页显示出来、把上一页藏起来。那一段(连同
      从 CM_VISIBLECHANGED 发这两个事件)是 Task 10「可见性与焦点」的活,在那之前
      这两个事件挂得上但不会响。 }
    property OnShow: TNotifyEvent read FOnShow write FOnShow;
    property OnHide: TNotifyEvent read FOnHide write FOnHide;
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

{ --- 纯规则 / 几何(无控件、无句柄、无主题,可无头测) ------------------------ }

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

{ 图标条 / 标签行的插入槽:按已排布项的中点分。返回 0..N 的**窗口序号**位置。 }
function TyToolWindowSlotAt(const ASlots: TTyToolWindowSlots; X, Y: Integer;
  AVertical: Boolean; ACount: Integer): Integer;

{ 图标条排布(竖直)。 }
function TyToolWindowStripLayout(AStripWidth, AStripHeight, AItemSize, AOverflowSize: Integer;
  ACount, AActiveIndex: Integer): TTyToolWindowSlots;

function TyToolWindowDragThreshold(APPI: Integer): Integer;

implementation

{ --- TTyToolWindow ------------------------------------------------------------ }

constructor TTyToolWindow.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  { 多击两个标志:底栏标题行的按下落在窗口的句柄上,LCL 数点击次数看的是收到消息的
    那个窗口化控件;不加的话第三次按下会被还原成普通按下,又生效一次。 }
  ControlStyle := ControlStyle + [csAcceptsControls, csDesignFixedBounds,
    csNoDesignVisible, csNoFocus, csTripleClicks, csQuadClicks];
  FImageIndex := -1;
  FHeaderPxCache := -1;
  Align := alClient;
  Visible := False;
  { 构造里一个子对象都不建 —— 建了会在流式加载时翻倍。 }
end;

destructor TTyToolWindow.Destroy;
begin
  FPaintCache.Free;
  inherited Destroy;
end;

function TTyToolWindow.GetStyleTypeKey: string;
begin
  Result := 'TyToolWindow';
end;

function TTyToolWindow.ImageIndexIsStored: Boolean;
begin
  { 名字是持久键,序号只在名字给不出答案时才进流。 }
  Result := (FImageName = '') and (FImageIndex >= 0);
end;

function TTyToolWindow.GetBar: TTyToolWindowBar;
begin
  if Parent is TTyToolWindowBar then Result := TTyToolWindowBar(Parent)
  else Result := nil;
end;

function TTyToolWindow.GetActions: TTyToolWindowActions;
begin
  { 操作区本身(连同扫 Controls[] 取第一个的这一句)是 Task 4 的活;在那之前一个
    操作区都不存在,标题行高就退化成 token 值。 }
  Result := nil;
end;

procedure TTyToolWindow.TextChanged;
begin
  inherited TextChanged;
  { 标题就画在自己的标题行里(见 RenderTo),不重画就停在上一句。 }
  Invalidate;
end;

function TTyToolWindow.HeaderMode: TTyToolWindowHeaderMode;
begin
  { 只看所在栏的**位置** —— 不看哪页是当前页,否则切页时正文会跳。
    而位置(Placement)是 Task 5 的活,今天栏还答不出来;A 期也只有侧栏,
    twhBottom 连同它那一支标题行排布都在 B 期。Task 5 补上 Placement 时,
    这里要跟着变成 `if Bar.Placement = twpBottom then twhBottom else twhSide`。 }
  if Parent is TTyToolWindowBar then Result := twhSide
  else Result := twhNone;
end;

function TTyToolWindow.HeaderHeightPx: Integer;
var
  mdl: TTyStyleModel;
  ver: Cardinal;
  mode: TTyToolWindowHeaderMode;
  tokenPx, actionsPx: Integer;
begin
  mode := HeaderMode;
  if mode = twhNone then Exit(0);
  mdl := ActiveController.Model;
  ver := mdl.ThemeVersion;
  { 键里既要版本号也要 model 身份:版本号是每个 model 各自算的,只按版本号键控
    会把 A 的值端给 B —— Controller 是 published,中途换得掉。 }
  if (FHeaderPxAnchor <> TObject(mdl)) or (FHeaderPxVer <> ver)
     or (FHeaderPxPPI <> Font.PixelsPerInch) or (FHeaderPxRTL <> UseRightToLeftAlignment)
     or (FHeaderPxMode <> mode) or (FHeaderPxCache < 0) then
  begin
    FHeaderPxCache := MulDiv(ActiveController.Metric(TyToolWindowHeaderHeightVar,
      TyToolWindowHeaderHeightDef), Font.PixelsPerInch, 96);
    FHeaderPxAnchor := TObject(mdl);
    FHeaderPxVer := ver;
    FHeaderPxPPI := Font.PixelsPerInch;
    FHeaderPxRTL := UseRightToLeftAlignment;
    FHeaderPxMode := mode;
  end;
  tokenPx := FHeaderPxCache;
  { 操作区那一项**不缓存**:子控件增删 / 显隐 / 改尺寸都会触发整窗体自顶向下重排,
    现取就能跟上。底栏模式下由栏统一算(B 期),A 期两种模式都按本窗口算。
    Task 4 把这个 0 换成 Actions.RawPreferredHeight。 }
  actionsPx := 0;
  if actionsPx > tokenPx then Result := actionsPx else Result := tokenPx;
  if Result < 1 then Result := 1;
end;

function TTyToolWindow.HeaderRowRect: TRect;
begin
  Result := Rect(0, 0, ClientWidth, HeaderHeightPx);
end;

function TTyToolWindow.BodyRect: TRect;
begin
  { 查询就调自己的 AdjustClientRect —— 正文区只有一个定义,手摆和对齐摆落在同一处。 }
  Result := ClientRect;
  AdjustClientRect(Result);
end;

procedure TTyToolWindow.AdjustClientRect(var ARect: TRect);
begin
  inherited AdjustClientRect(ARect);
  Inc(ARect.Top, HeaderHeightPx);
  if ARect.Top > ARect.Bottom then ARect.Top := ARect.Bottom;
end;

procedure TTyToolWindow.RelayoutHeader;
begin
  if FRelayouting then Exit;
  FRelayouting := True;
  try
    { 客户区内缩量变了就必须重排,只 Invalidate 会让 alClient 子控件盖住标题行。 }
    Realign;
    inherited Invalidate;
  finally
    FRelayouting := False;
  end;
end;

procedure TTyToolWindow.Invalidate;
var
  old: Integer;
begin
  { 自己的样子变了 —— 丢缓存。子控件打脏到不了这里,缓存正是靠这一点活着。 }
  if FPaintCache <> nil then FPaintCache.Drop;
  { 换主题是这个类唯一听不见的事件:广播过来的只有一个裸 Invalidate
    (tyControls.Controller.pas 的 Changed)。所以缓存键在这里重查一遍,
    而键变了要重排、不是只重画。 }
  old := FHeaderPxCache;
  FHeaderPxCache := -1;
  if (not FRelayouting) and (HeaderHeightPx <> old) and (old >= 0) then
    RelayoutHeader;
  inherited Invalidate;
end;

procedure TTyToolWindow.AutoAdjustLayout(AMode: TLayoutAdjustmentPolicy;
  const AFromPPI, AToPPI, AOldFormWidth, ANewFormWidth: Integer);
begin
  inherited AutoAdjustLayout(AMode, AFromPPI, AToPPI, AOldFormWidth, ANewFormWidth);
  FHeaderPxCache := -1;
  RelayoutHeader;
end;

procedure TTyToolWindow.CMBiDiModeChanged(var Msg: TLMessage);
begin
  inherited;
  FHeaderPxCache := -1;
  RelayoutHeader;
end;

procedure TTyToolWindow.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, hdrS: TTyStyleSet;
  R, hdr: TRect;
  inp: TTyToolWindowHeaderInput;
  g: TTyToolWindowHeaderGeom;
begin
  P := TTyPainter.Create;
  try
    { painter 的位图是 W×H 并 blit 到 ARect 左上,所以内部一切坐标都用 (0,0)-local。 }
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    DrawFrame(P, R, S);
    hdr := Rect(0, 0, R.Right, HeaderHeightPx);
    if (HeaderMode = twhSide) and (hdr.Bottom > hdr.Top) then
    begin
      hdrS := ActiveController.Model.ResolveStyle('TyToolWindowHeader',
        TyStyleClassFor(Self, StyleClass), [tysNormal]);
      if tpBackground in hdrS.Present then
        P.FillBackground(hdr, hdrS.Background, 0);
      inp := Default(TTyToolWindowHeaderInput);
      inp.Mode := twhSide;
      inp.RowWidth := hdr.Right;
      inp.RowHeight := hdr.Bottom;
      inp.Pad := P.Scale(ActiveController.Metric(TyToolWindowHeaderPadVar, TyToolWindowHeaderPadDef));
      inp.Gap := P.Scale(ActiveController.Metric(TyToolWindowHeaderGapVar, TyToolWindowHeaderGapDef));
      { 操作区的宽是 Task 4 的活;没有操作区时标题就占满整条。 }
      inp.ActionsWidth := 0;
      g := TyToolWindowHeaderLayout(inp);
      { 标题拿下整个剩余跨度,放不下由 DrawText 自己出省略号。 }
      if (Caption <> '') and (g.Caption.Right > g.Caption.Left) then
        P.DrawText(g.Caption, Caption, hdrS.FontName, ResolveFontSize(hdrS),
          hdrS.FontWeight, hdrS.TextColor, taLeftJustify, tlCenter, True);
    end;
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyToolWindow.Paint;
var
  w, h: Integer;
begin
  { 设计器重绘少、而且边重绘边流式化,所以只在运行时用缓存。 }
  if csDesigning in ComponentState then
  begin
    RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
    Exit;
  end;
  w := ClientWidth; h := ClientHeight;
  if (w <= 0) or (h <= 0) then Exit;
  if FPaintCache = nil then FPaintCache := TTyPaintCache.Create;
  if FPaintCache.NeedsRender(w, h) then
    RenderTo(FPaintCache.Canvas, Rect(0, 0, w, h), Font.PixelsPerInch);
  FPaintCache.Blit(Canvas);
end;

function TTyToolWindowActions.GetStyleTypeKey: string;
begin
  Result := 'TyToolWindowActions';
end;

function TTyToolWindowBar.GetStyleTypeKey: string;
begin
  Result := 'TyToolWindowBar';
end;

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

function TyToolWindowHeaderLayout(const AInput: TTyToolWindowHeaderInput): TTyToolWindowHeaderGeom;
var
  pad, gap, aw, x: Integer;
begin
  Result := Default(TTyToolWindowHeaderGeom);
  if (AInput.RowWidth <= 0) or (AInput.RowHeight <= 0) then Exit;
  pad := AInput.Pad; if pad < 0 then pad := 0;
  gap := AInput.Gap; if gap < 0 then gap := 0;
  aw := AInput.ActionsWidth; if aw < 0 then aw := 0;
  { 两个内距都要留出来:只扣一个的话,侧栏拖窄时操作区会吃掉前导内距。 }
  if aw > AInput.RowWidth - 2 * pad then aw := AInput.RowWidth - 2 * pad;

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

initialization
  { 运行时 .lfm 按类名实例化流里的子对象,四个都要注册。 }
  RegisterClass(TTyToolWindow);
  RegisterClass(TTyToolWindowActions);
  RegisterClass(TTyToolWindowBar);
  RegisterClass(TTyToolWindowManager);
end.
