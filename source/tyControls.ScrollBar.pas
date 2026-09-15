unit tyControls.ScrollBar;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Math, Controls, Graphics, LCLType, StdCtrls, ExtCtrls,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Animation,
  tyControls.Controller, tyControls.StyleModel;
const
  { 自动隐藏延时的主题令牌。一条轴，没有歧义的零：
      -1 = 关（滚动条一直显示；基础层 light.tycss 就是这个值，经典世代的
           皮肤一行不写、全靠继承它；六个遮盖式滚动条的皮肤
           （win11/macos/fluent/material3/adwaita/ubuntu）写的是 1200）
       0 = 开，停手立即淡出
       N = 开，停手 N 毫秒后淡出
    走已有的 Metric 机制，tycss 不需要新的值类型。负号能活着走完
    ResolveMetric -> TyEvalLength -> ParsePctOrNum -> StrToFloat，理由见
    docs/superpowers/specs/2026-09-14-scrollbar-auto-hide-design.md §2。 }
  TyScrollBarAutoHideVar = '--scrollbar-auto-hide';
  { 「关」这一个值,原来在同一个函数里有三种写法(Exit(-1)、Def = -1、
    themeMs < 0)。给它一个名字，三处都指这里。 }
  TyScrollBarAutoHideOff = -1;
  TyScrollBarAutoHideDef = TyScrollBarAutoHideOff;
  { 属性明说要自动隐藏、而主题没给延时时的回退。macOS 量级。 }
  TyScrollBarAutoHideFallbackMs = 1200;
  { 出现要快——用户正在找它；消失要柔——别打扰。 }
  TyScrollBarFadeInMs  = 120;
  TyScrollBarFadeOutMs = 200;

type
  TTyScrollBarKind = (sbHorizontal, sbVertical);

  { 自动隐藏的三态。**不能是 Boolean**：Boolean 一旦被碰过就永远脱离主题
    控制，换主题不跟着变——在一个主打换肤的库里这是硬伤。 }
  TTyScrollBarAutoHide = (sbahDefault, sbahNever, sbahAuto);

  TTyScrollBar = class(TTyCustomControl)
  private
    FKind: TTyScrollBarKind;
    FMirrorH: Boolean;
    FMin, FMax, FPosition, FPageSize: Integer;
    FSmallChange, FLargeChange: Integer;
    FOnChange: TNotifyEvent;
    FOnScroll: TScrollEvent;
    FDragGrabOffset: Integer;
    FDragStartTop: Integer;
    FLiveTracking: Boolean;
    { The value the thumb is being DRAGGED to while LiveTracking is off. It is the painted
      position for the duration of the drag and becomes Position on mouse-up; FPosition is
      left alone until then, which is the whole point of the mode. }
    FTrackPos: Integer;
    FAnimEnabled: Boolean;
    FAutoHide: TTyScrollBarAutoHide;
    { 上一次缓动滴答的时刻(0 = 还没开始)。用来算真实经过时间。 }
    FLastTickMs: QWord;
    { 本次位置变化要不要立刻刷自己(只在拖动中置位)。 }
    FNeedImmediateRepaint: Boolean;
    FPosAnim: TTyAnimator;      // 0..1 traversal driving FAnimFrom -> FAnimTo
    FAnimFrom, FAnimTo: Single; // displayed-thumb-position endpoints (Min..Max units)
    FTimer: TTimer;            // lazy; only created when actually animating
    { ——— 自动隐藏。整组字段和上面那套位置缓动毫无关系,别把两边的字段串着用。 }
    FFadeLevel: Single;         // 1 = 完全显示，0 = 完全隐藏
    FFadeAnim: TTyAnimator;     // 0..1 traversal，驱动 FFadeFrom -> FFadeTo
    FFadeFrom, FFadeTo: Single;
    FIdleMs: Integer;           // 距上次「在用」过去了多久
    { 淡入淡出上一拍的时刻(0 = 还没开始)。**不能和位置缓动的 FLastTickMs 共用**
      ——两套定时器各跑各的，串起来只会互相把对方的起点冲掉。 }
    FFadeLastTickMs: QWord;
    { 主题里那个延时令牌解出来的值，连同它是在哪个 model 的哪一版主题上解出来的。
      锚点故意存成 TObject：它只拿来比相等，永远不解引用，所以 controller 换过
      之后那个指针悬着也无所谓。nil = 还没解过。 }
    FAutoHideMsCache: Integer;
    FAutoHideMsVer: Cardinal;
    FAutoHideMsAnchor: TObject;
    { 惰性；等延时和跑淡出两个阶段共用它，一律 16ms 一拍。
      **一拍推进多少毫秒不看 Interval**，看真实经过时间——见 FadeTickElapsedMs。
      **和位置动画的 FTimer 无关**——那套有 FDragging/LiveTracking 的分支，
      掺进来只会把两件事一起弄坏。 }
    FHideTimer: TTimer;
    function TrackRect: TRect;
    function TrackLength: Integer;
    function PosAlong(X, Y: Integer): Integer;
    { True when THIS bar's track runs right-to-left, i.e. MirrorHorizontal is on AND the
      bar is horizontal. Every mirrored site asks this one question, so a vertical bar can
      never accidentally pick up the flag. }
    function Mirrored: Boolean;
    procedure SetMirrorHorizontal(const AValue: Boolean);
    procedure SetAutoHide(const AValue: TTyScrollBarAutoHide);
    procedure ButtonRects(const AClient: TRect; out ALo, AHi: TRect);
    procedure SetKind(const AValue: TTyScrollBarKind);
    procedure SetMin(const AValue: Integer);
    procedure SetMax(const AValue: Integer);
    procedure SetPosition(const AValue: Integer);
    procedure SetPageSize(const AValue: Integer);
    procedure SetSmallChange(const AValue: Integer);
    procedure SetLargeChange(const AValue: Integer);
    { How far one page action moves: LargeChange when set, PageSize otherwise. }
    function EffectiveLargeChange: Integer;
    function GetTrackPosition: Integer;
    procedure EnsureTimer;
    procedure HandleTimer(Sender: TObject);
    procedure EnsureHideTimer;
    { 把延时表装上并起起来,**不碰闲置时钟**。

      和 NoteActivity 的分工要划清:那个说的是「有人在用」——它把闲置清零、
      该淡回来的淡回来;这个只回答「这条条现在该不该有一块表在转」。条刚
      *进入*可自动隐藏的状态(句柄到手、换到一个开自动隐藏的皮肤)不是「有人
      在用」,拿 NoteActivity 来干这活等于每次重绘都给它续一次命,条就再也
      淡不掉了。 }
    procedure ArmAutoHideClock;
    procedure HandleHideTimer(Sender: TObject);
    function AutoHideHeldOpen: Boolean;
    procedure StartFade(ATo: Single; ADurationMs: Integer);
    { RenderTo 真正用的那份样式：主题样式叠上自动隐藏的淡出系数。见实现处。 }
    function PaintStyle: TTyStyleSet;
    { 主题说的延时，按 (model, ThemeVersion) 缓存。见实现处：热路径上一拍要问两次。 }
    function ThemeAutoHideMs: Integer;
  protected
    FDragging: Boolean;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    { 句柄到手的那一刻把延时表起起来。**这是自动隐藏唯一一个「没人碰过它」的
      起表点。**

      从前起表只有 NoteActivity 一条路,而它的每一个调用点要么是用户在条上比划、
      要么是代码改 Position。条在出生期间收到的 NoteActivity 全都早于句柄
      (.lfm 流式化设 AutoHide -> SetAutoHide、宿主把 ScrollBarAutoHide 转发给
      刚建出来的条、宿主头一次 UpdateScrollBar 设 Position ——最后这个连
      NoteActivity 都到不了,0 = 0 在 SetPosition 里就早退了),而 EnsureHideTimer
      在没句柄的时候直接 Exit,建不出表来。句柄随后到位,**从前没有任何东西
      回头重试**:一条摆在屏幕上、谁也没碰过的条,表是 0 块,永远停在
      FadeLevel = 1.0,非得等鼠标移上去(MouseEnter -> NoteActivity)才开始算
      延时——用户报的就是这个。

      有一种情形这里救不了,也不该救:独立摆放的条要是正好是窗体的头一个
      tab stop,一出生就有焦点,而有焦点是「按住不放」的信号之一
      (AutoHideHeldOpen),表起来了头一拍也会把自己停掉。那是设计,不是 bug
      ——键盘焦点停在一个看不见的控件上才是事故。 }
    procedure InitializeWnd; override;
    { 全身只为自动隐藏服务：指针压在条上时它必须一直亮着。 }
    procedure MouseEnter; override;
    { 同上，指针离开那一半：把停掉的延时表重新起起来。 }
    procedure MouseLeave; override;
    { 同上,焦点那一半。 }
    procedure DoEnter; override;
    { 同上，失焦那一半。 }
    procedure DoExit; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
    // Fire OnScroll with ACode and the proposed APos (which the handler may
    // override via the var parameter); then commit Position := APos. This keeps
    // OnChange firing too (via the Position setter). Used by the user-driven
    // keyboard/track-paging paths.
    procedure DoScroll(ACode: TScrollCode; var APos: Integer);
    procedure ScrollTo(ACode: TScrollCode; AProposed: Integer);
    // Current displayed (possibly mid-animation) thumb position, eased between
    // the from/to endpoints. At rest this equals the logical FPosition.
    function DisplayPos: Single;
    // Steppable animation seam (no wall-clock): advance the thumb ease by AMs and
    // return True iff the eased progress changed. The lazy TTimer drives it at
    // runtime; tests drive it directly via an access subclass.
    function AdvanceAnimation(AMs: Integer): Boolean;
    // Force the *animating* path toward AValue (clamped) regardless of handle
    // state. Runtime always routes through SetPosition (which snaps headless);
    // this is the test seam so the animation is reachable without a window.
    procedure SetPositionAnimating(AValue: Integer);
    { 一拍推进多少毫秒(真实经过时间)。测试用受控时钟覆写它。 }
    function TickElapsedMs: Integer; virtual;
    procedure HandleTimerTick;
    { 淡出这一拍该推进多少毫秒(真实经过时间)。TickElapsedMs 的孪生体,连可见性
      一起孪生:那边抽成可覆写的理由这边一字不差 —— 否则「按真实时间推进」这条
      只能靠肉眼在真机上看,而那正是当初写成名义间隔也没人发现的原因。 }
    function FadeTickElapsedMs: Integer; virtual;
    { **缝开在「现在几点」这一层,不在算好的差值那一层。** 位置缓动那边的桩
      (test.controls.scrollbar.pas 的 TFakeClockScroll)覆写的是整个
      TickElapsedMs,那条路上没有别的逻辑;这边不行 —— 至少 1 毫秒的钳位和
      首拍的种子值都长在 FadeTickElapsedMs 里,覆写它等于把被测的那段搬进桩子,
      喂个 0 进去测出来的是桩子会不会返回 0。 }
    function FadeNowMs: QWord; virtual;
    { 延时表这一拍之后还有没有活干。抽出来一是 HandleHideTimer 要用，二是无头
      只够得着这里——没有句柄就不建表，「按住不放就停表」那条逻辑的效果
      (FHideTimer.Enabled)在无头下根本不存在，能验的只有这个判断本身。 }
    function AutoHideTimerNeeded: Boolean;
    { 手动走一拍 HandleHideTimer（无头没有表）。和位置缓动的 HandleTimerTick 同路。 }
    procedure HandleHideTimerTick;
  public
    { 设定位置并**立刻落位**,绝不缓动。

      给"镜像"用:宿主(网格/列表/树)自己滚完之后,把结果同步给滑块。
      内容已经动了,滑块再缓动追上去就是不跟手 —— 用户看到的是内容在动、
      滑块慢半拍。缓动只在"用户点滑道让它跳过去"那种场景才有意义。 }
    procedure SetPositionSnapped(AValue: Integer);
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function GetStyleTypeKey: string; override;
    procedure BeginThumbDrag(AGrabPosAlongTrack: Integer);
    procedure DragThumbTo(APosAlongTrack: Integer);
    procedure EndThumbDrag;
    { True while the user is dragging the thumb with the mouse. }
    property Dragging: Boolean read FDragging;
    { Where the thumb currently SITS, which is Position except in the middle of a
      LiveTracking=False drag -- there the thumb has moved and Position has not yet. A host
      that wants to preview the pending value (a row-number tooltip beside the thumb, say)
      reads this; everything else should keep reading Position. }
    property TrackPosition: Integer read GetTrackPosition;
    { 本条现在实际的自动隐藏延时，毫秒；-1 表示关（一直显示）。
      属性压过主题：sbahNever 恒为 -1；sbahAuto 在主题说关时用回退值。 }
    function EffectiveAutoHideMs: Integer;
    { 0..1 的当前可见度。1 = 完全显示。绘制时乘进样式的 opacity。 }
    property FadeLevel: Single read FFadeLevel;
    { 延时表现在转着没有。**只读**,问的是真表(FHideTimer),不是哪个影子状态。

      开这个口是为了让测试断言「起表这个决定做没做」——只看 FadeLevel 是断不出
      来的:一条从没起过表的条和一条刚起了表还没到点的条,可见度都是 1.0,
      长得一模一样,而这两者正是这次修的 bug 的两边。无头够得着真句柄
      (HandleNeeded 就会走 InitializeWnd),所以不需要假缝。 }
    function AutoHideClockArmed: Boolean;
    { 「有人在用」。滚动、悬停、拖动、聚焦都调它。 }
    procedure NoteActivity;
    { 测试缝：推进 AMs 毫秒。真机由 FHideTimer 驱动，headless 由测试驱动
      ——和位置动画的 HandleTimerTick 是同一个路子。 }
    procedure AutoHideTick(AMs: Integer);
    { 测试缝：问「这一帧的 opacity 是多少」，省得为了一个数去数像素。
      **它不能替代像素测试**：这个口子绕开了 RenderTo，光靠它绿，
      「算对了但没接到绘制上」照样一声不吭——那是本库的默认故障。 }
    function PaintStyleForTest: TTyStyleSet;
    { 换主题时控件收到的就只有这一个广播,所以「自动隐藏关着 -> 条必须看得见」
      这条不变量只能挂在这儿修。见实现处。 }
    procedure Invalidate; override;
  published
    { LIVE TRACKING -- whether dragging the thumb moves Position continuously (True, the
      default and what this bar has always done) or only on mouse-up (False).

      This is the seam LCL's goThumbTracking needs. That flag was left out of TTyGrid.Options
      in 251db2d with the reason "needs a seam in the scroll bar, which always tracks live":
      publishing it while the bar could not honour it would have been a lying property, which
      is the exact defect class test.parity's LyingPropertiesStayUnpublished exists to stop.
      With this property a host CAN honour it -- see docs/controls/scrollbar.md.

      Off, the thumb still follows the mouse (the drag has to feel connected); what is deferred
      is the COMMIT -- Position, OnChange, and OnScroll(scPosition). OnScroll(scTrack) still
      fires on every move with the proposed value, exactly as a native bar keeps sending
      SB_THUMBTRACK; a host that does not want to act on it simply does not. That split is
      what makes the mode useful at all: an expensive host (a grid re-querying a database per
      row) previews on scTrack and only really moves once.

      Only the THUMB DRAG is affected. Arrow buttons, track paging, the wheel and the keyboard
      commit immediately in both modes -- they are discrete steps, not a continuous gesture,
      and native bars do not defer them either. }
    property LiveTracking: Boolean read FLiveTracking write FLiveTracking default True;
    // On by default. When enabled and the control has a window handle, a
    // PROGRAMMATIC Position change (keyboard/wheel/track-click) eases the painted
    // thumb to the new value; with no handle (every render test) or while
    // dragging it snaps, preserving exact-pixel tests and live mouse tracking.
    property AnimationsEnabled: Boolean read FAnimEnabled write FAnimEnabled default True;
    { 这条滚动条要不要在没人用的时候淡出。

      sbahDefault —— 跟主题走（令牌 --scrollbar-auto-hide）。
      sbahNever   —— 永远显示，压过主题。
      sbahAuto    —— 自动隐藏，压过主题；延时仍读主题，主题没给就用
                     TyScrollBarAutoHideFallbackMs。

      延时**故意不给属性**：单控件要不同延时是臆想需求。整体调快调慢改主题。 }
    property AutoHide: TTyScrollBarAutoHide read FAutoHide write SetAutoHide default sbahDefault;
    { RIGHT-TO-LEFT HORIZONTAL BAR: Min sits at the RIGHT end of the track and a rising
      Position walks the thumb LEFTWARDS. That is Windows' behaviour for a mirrored window,
      not a preference — a horizontal bar under WS_EX_LAYOUTRTL comes out reflected. The
      painted bar looks IDENTICAL either way (reflecting a left arrow at one end and a right
      arrow at the other is its own mirror image); what changes is where the thumb is for a
      given Position, which end button decrements, and which way the arrow keys step.
      Vertical bars ignore it entirely.

      OPT-IN, and default False on purpose — it is NOT wired to BiDiMode. Five controls in
      this library embed a horizontal bar (Grid, ListView, Memo, TreeView, ScrollBox) and
      none of them mirrors its CONTENT yet. A bar that put Position=Min on the right while
      the content it drives still began on the left would be a thumb pointing at the wrong
      half of the document — the paint/hit-test split this whole pass exists to remove, just
      moved up one level. A host turns this on in the same commit that mirrors its content.
      TTyScrollBox deliberately leaves it off: see the note on its horizontal bar. }
    property MirrorHorizontal: Boolean read FMirrorH write SetMirrorHorizontal default False;
    property Kind: TTyScrollBarKind read FKind write SetKind default sbVertical;
    property Min: Integer read FMin write SetMin default 0;
    property Max: Integer read FMax write SetMax default 100;
    property Position: Integer read FPosition write SetPosition default 0;
    { PageSize sizes the THUMB (thumb : track = PageSize : (Max-Min)+PageSize). It also
      used to be the only page STEP, so a proportional thumb and a page jump could not
      be chosen independently: shrinking the thumb shrank the page click with it. LCL
      keeps the two apart -- PageSize feeds ScrollInfo.nPage (include/scrollbar.inc:55)
      while LargeChange drives scPageUp/scPageDown (:195,199). }
    property PageSize: Integer read FPageSize write SetPageSize default 10;
    property SmallChange: Integer read FSmallChange write SetSmallChange default 1;
    { The page step: a track click, PgUp/PgDn, scPageUp/scPageDown. LCL: stdctrls.pp:106.

      DIFFERENT DEFAULT, deliberately. LCL's is 1, which would make a track click on
      every bar in this library -- the list box, the grid, the memo, the tree, the
      scroll box all embed one -- crawl by a single unit instead of a screenful. 0 here
      means "page by PageSize", i.e. exactly what this bar did before the property
      existed, so nothing that ships today changes; set it to page by something else. }
    property LargeChange: Integer read FLargeChange write SetLargeChange default 0;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnScroll: TScrollEvent read FOnScroll write FOnScroll;
    { A standalone bar is a keyboard control (arrows / PgUp / PgDn / Home / End in
      KeyDown), so it takes a tab stop like the native TScrollBar does. Declared True to
      match the constructor, so a host's TabStop=False opt-out streams — which is exactly
      what the bars EMBEDDED inside a list/grid/tree/scroll box do, in code. }
    property TabStop default True;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

function TyScrollThumbRect(const ATrack: TRect; AKind: TTyScrollBarKind;
  AMin, AMax, APosition, APageSize: Integer; ARightToLeft: Boolean = False): TRect;

{ THE ONLY PLACE THE HORIZONTAL AXIS IS EVER FLIPPED.

  AOffset is how far the thumb's near edge sits from the track's near edge; AFreeSpace is
  how far it can travel (track length minus thumb length). Mirroring a scroll bar is exactly
  "measure that offset from the other end", so it is one subtraction — and putting it in a
  function rather than inline is the whole point: TyScrollThumbRect (which PAINTS the thumb)
  and TTyScrollBar.DragThumbTo (which reads a dragged thumb back OUT into a Position) are
  inverse computations written in two different places, and this is the single line they
  share. Flip it here and both flip; there is no arrangement in which the thumb is drawn
  mirrored and the drag/click math is not.

  Vertical bars and left-to-right bars return AOffset untouched, which is why every existing
  caller is bit-for-bit unchanged. }
function TyScrollMirrorOffset(AOffset, AFreeSpace: Integer; AKind: TTyScrollBarKind;
  ARightToLeft: Boolean): Integer;

function TyScrollButtonSize(const AClient: TRect; AKind: TTyScrollBarKind): Integer;
{ NOT mirrored, and deliberately: the track is inset by one button-size at EACH end, so the
  rect is symmetric about the client centre and reflecting it is the identity. (The scoping
  document expected the two end buttons to swap here; the end buttons are not here — they are
  TTyScrollBar.ButtonRects — and they do not swap either. See RenderTo.) }
function TyScrollTrackRect(const AClient: TRect; AKind: TTyScrollBarKind;
  AButtonSize: Integer): TRect;

implementation

function TyScrollMirrorOffset(AOffset, AFreeSpace: Integer; AKind: TTyScrollBarKind;
  ARightToLeft: Boolean): Integer;
begin
  if ARightToLeft and (AKind = sbHorizontal) then
    Result := AFreeSpace - AOffset
  else
    Result := AOffset;
end;

function TyScrollThumbRect(const ATrack: TRect; AKind: TTyScrollBarKind;
  AMin, AMax, APosition, APageSize: Integer; ARightToLeft: Boolean): TRect;
var
  TrackLen, Span, ThumbLen, FreeSpace, Travel, Pos0, Offset: Integer;
  Cross, MinThumb: Integer;
begin
  if AKind = sbVertical then
    TrackLen := ATrack.Bottom - ATrack.Top
  else
    TrackLen := ATrack.Right - ATrack.Left;
  Span := (AMax - AMin) + APageSize;
  if (Span <= 0) or (APageSize <= 0) or (AMax <= AMin) then
  begin
    // degenerate: nothing to scroll, thumb fills the whole track
    Result := ATrack;
    Exit;
  end;
  ThumbLen := (APageSize * TrackLen) div Span;
  if AKind = sbVertical then Cross := ATrack.Right - ATrack.Left else Cross := ATrack.Bottom - ATrack.Top;
  MinThumb := Cross; if MinThumb < 6 then MinThumb := 6;
  if ThumbLen < MinThumb then ThumbLen := MinThumb;
  if ThumbLen > TrackLen then ThumbLen := TrackLen;
  FreeSpace := TrackLen - ThumbLen;
  Travel := AMax - AMin;
  Pos0 := APosition - AMin;
  if Pos0 < 0 then Pos0 := 0;
  if Pos0 > Travel then Pos0 := Travel;
  if Travel <= 0 then
    Offset := 0
  else
    Offset := Integer((Int64(Pos0) * FreeSpace) div Travel);
  Offset := TyScrollMirrorOffset(Offset, FreeSpace, AKind, ARightToLeft);
  if AKind = sbVertical then
    Result := Rect(ATrack.Left, ATrack.Top + Offset,
      ATrack.Right, ATrack.Top + Offset + ThumbLen)
  else
    Result := Rect(ATrack.Left + Offset, ATrack.Top,
      ATrack.Left + Offset + ThumbLen, ATrack.Bottom);
end;

function TyScrollButtonSize(const AClient: TRect; AKind: TTyScrollBarKind): Integer;
begin
  if AKind = sbVertical then
    Result := AClient.Right - AClient.Left
  else
    Result := AClient.Bottom - AClient.Top;
  if Result < 1 then Result := 1;
end;

function TyScrollTrackRect(const AClient: TRect; AKind: TTyScrollBarKind;
  AButtonSize: Integer): TRect;
var
  mainLen: Integer;
begin
  Result := AClient;
  if AKind = sbVertical then
    mainLen := AClient.Bottom - AClient.Top
  else
    mainLen := AClient.Right - AClient.Left;
  if mainLen <= 2 * AButtonSize then Exit;   // too short for two buttons -> whole client, no buttons
  if AKind = sbVertical then
    Result := Rect(AClient.Left, AClient.Top + AButtonSize,
      AClient.Right, AClient.Bottom - AButtonSize)
  else
    Result := Rect(AClient.Left + AButtonSize, AClient.Top,
      AClient.Right - AButtonSize, AClient.Bottom);
end;

constructor TTyScrollBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // KeyDown below implements the whole native keyboard: line, page and end-to-end. None of
  // it could ever run, because LCL defaults TabStop to False and TTyCustomControl.MouseDown
  // gates click-to-focus on it. Controls that EMBED a bar (list box, memo, grid, tree,
  // scroll box) turn it back off on their instance — see the comments there.
  TabStop := True;
  FKind := sbVertical;
  FMin := 0;
  FMax := 100;
  FPosition := 0;
  FPageSize := 10;
  FSmallChange := 1;
  FLargeChange := 0;           // 0 == page by PageSize (see the property comment)
  FMirrorH := False;           // opt-in; see the MirrorHorizontal property comment
  FLiveTracking := True;       // what this bar has always done; see the property comment
  FTrackPos := FPosition;
  FAnimEnabled := True;
  FAutoHide := sbahDefault;    // 跟主题走;与 published 的 default 一致
  { 出生就是全可见。主题关着自动隐藏时这个值再也不会变,这也正是
    「不开这个特性的人一分钱不花」的那条路。 }
  FFadeLevel := 1.0;
  // Thumb-glide animator: 0..1 traversal in ~120ms, decelerating. Start settled
  // at the rest endpoint so DisplayPos == FPosition before any change.
  FPosAnim.Progress := 1;
  FPosAnim.Target := 1;
  FPosAnim.DurationMs := 120;
  FPosAnim.Easing := teEaseOutCubic;
  FAnimFrom := FPosition;
  FAnimTo := FPosition;
  // Scrollbar thickness (cross-axis) follows the density-aware --scrollbar-size
  // token, the SAME token TTyScrollBox.ScrollbarThick reads. Classic resolves to
  // TyScrollbarSize (12); modern density packs raise it. Height (default length)
  // stays a plain constant.
  Width := MulDiv(ActiveController.Metric('--scrollbar-size', TyScrollbarSize), Font.PixelsPerInch, 96);
  Height := 160;
end;

destructor TTyScrollBar.Destroy;
begin
  // FTimer is owned by Self (would be freed by DestroyComponents), but free it
  // explicitly first so the OnTimer callback can never fire mid-teardown.
  FreeAndNil(FTimer);
  { 同理:淡出定时器的回调也不能在拆到一半的对象上跑。 }
  FreeAndNil(FHideTimer);
  inherited Destroy;
end;

function TTyScrollBar.GetStyleTypeKey: string;
begin
  Result := 'TyScrollBar';
end;

function TTyScrollBar.Mirrored: Boolean;
begin
  Result := FMirrorH and (FKind = sbHorizontal);
end;

procedure TTyScrollBar.SetMirrorHorizontal(const AValue: Boolean);
begin
  if FMirrorH = AValue then Exit;
  FMirrorH := AValue;
  { Only the thumb's x moves; the frame, the track and both end buttons are already
    symmetric, so a repaint is the whole update. }
  Invalidate;
end;

procedure TTyScrollBar.SetAutoHide(const AValue: TTyScrollBarAutoHide);
begin
  if FAutoHide = AValue then Exit;
  FAutoHide := AValue;
  { 为什么不是裸字段写:淡出跑完之后定时器会把自己停掉，那一刻没有任何东西
    在推进状态。此时把 AutoHide 改成 sbahNever,「关掉了就恢复全可见」那条臂
    永远轮不到执行，滚动条就永久隐身；sbahDefault -> sbahAuto 同理，没人会去
    把定时器启起来。所以属性变化必须能叫醒一条已经停摆的滚动条：重置空闲计时、
    该淡回来的淡回来、该重新起表的把表起起来,全在 NoteActivity 里。 }
  FIdleMs := 0;
  NoteActivity;
  Invalidate;
end;

function TTyScrollBar.EffectiveAutoHideMs: Integer;
var
  themeMs: Integer;
begin
  if FAutoHide = sbahNever then
    Exit(TyScrollBarAutoHideOff);
  themeMs := ThemeAutoHideMs;
  if FAutoHide = sbahAuto then
  begin
    { 属性明说要隐藏。主题关着（或没说）时不能跟着关，否则这个属性是个谎。

      契约里的「关」只有 TyScrollBarAutoHideOff 一个值；这里放宽到任何负数,
      是因为主题作者手写个 -2 显然也是想关，没道理让它掉进回退。
      **0 不在此列** —— 0 是「停手立即淡出」，是个合法延时，不是关。 }
    if themeMs < 0 then
      Exit(TyScrollBarAutoHideFallbackMs);
    Exit(themeMs);
  end;
  Result := themeMs;   // sbahDefault
end;

function TTyScrollBar.ThemeAutoHideMs: Integer;
{ --scrollbar-auto-hide 的解析结果，缓存在 (model, ThemeVersion) 上。

  为什么值得缓存：ResolveMetric **即使缓存命中**也要先拼一个
  AName + '|' + IntToStr(ADefault) 的 key 再 IndexOf ——每次调用一个堆字符串。
  而这个函数在常见路径上一拍要被问两次(AutoHideTick 一次、HandleHideTimer 的
  停表判断一次)，60fps × 最多 12 条内嵌条，静止不动的条也能烧掉每秒上千次
  字符串分配。TTyMemo 已经在逐帧开销上栽过一次(0.5 秒一键)。

  为什么是版本锚而不是「主题变了就作废」：**没有主题变更通知这回事**。
  TTyStyleController.Changed 广播出来的只有一个裸 Invalidate，全 source/ 没有
  StyleChanged 钩子。照字面写「变更时作废」，做出来的是一个永远供应旧主题
  延时的缓存。库里现成的做法就是拿 ThemeVersion 当锚(tyControls.Base.pas:767、
  :1670)。

  键里除了版本还有 model 身份：版本号是**每个 model 各自算的**，两个 controller
  都只加载过一次主题的话版本号一模一样，只按版本号键控会把 A 的延时端给 B ——
  而 Controller 是个 published 属性，中途换得掉。

  **缓存只盖住主题这一半。** 属性那一半(sbahNever/sbahAuto 的回退)留在
  EffectiveAutoHideMs 里没有缓存：那几步是整数比较，缓存它省不下什么，却要
  SetAutoHide 记得去作废它——忘了作废正是缓存变成 bug 的方式。 }
var
  { ActiveController，不是裸 Controller——后者在没挂 controller 时会 AV。
    全拎进局部变量:命中那条路是本函数存在的全部理由,别在上面反复问。 }
  ctrl: TTyStyleController;
  mdl: TTyStyleModel;
  ver: Cardinal;
begin
  ctrl := ActiveController;
  mdl := ctrl.Model;
  ver := mdl.ThemeVersion;
  { 存下去的是 TObject:那个字段只拿来比相等,永远不解引用。 }
  if (FAutoHideMsAnchor = TObject(mdl)) and (FAutoHideMsVer = ver) then
    Exit(FAutoHideMsCache);
  FAutoHideMsCache := ctrl.Metric(TyScrollBarAutoHideVar, TyScrollBarAutoHideDef);
  FAutoHideMsVer := ver;
  FAutoHideMsAnchor := TObject(mdl);
  Result := FAutoHideMsCache;
end;

function TTyScrollBar.AutoHideHeldOpen: Boolean;
begin
  { 任一成立就「按住不放」，延时表根本不起。
    注意 Focused 只对独立摆放的条有意义：6 个宿主的内嵌条一律 TabStop=False。 }
  Result := FHover or FDragging or (csDesigning in ComponentState)
            or (HandleAllocated and Focused);
end;

procedure TTyScrollBar.NoteActivity;
begin
  FIdleMs := 0;
  if EffectiveAutoHideMs < 0 then
  begin
    { 关着的时候**没有任何东西**会再推进淡入淡出 —— 定时器不起,淡入就算装上了
      也永远跑不起来。所以「回到全可见」必须在这里当场做掉,否则一条已经淡掉的
      条,在主题或属性把自动隐藏关掉之后会永久隐身。关闭臂就在 AutoHideTick 里,
      喂它一拍即可,不必抄一遍。 }
    AutoHideTick(0);
    Exit;
  end;
  { 光看可见度不够。淡出「装上了膛但还没推进」的那一拍,可见度还正好是 1.0,
    膛里装的却是 0.0 —— 只判 FFadeLevel < 1.0 的话这里什么也不做,那发淡出
    下一拍照常打出去。而淡出跑动期间不计闲置、跑完可见度又成了 0,条就一直
    不见了:用户看到的是「滚了一下,条反而没了」。所以还要问一句:有没有一发
    反方向的动画正在跑。 }
  if (FFadeLevel < 1.0) or (FFadeAnim.Running and (FFadeTo < 1.0)) then
    StartFade(1.0, TyScrollBarFadeInMs);
  EnsureHideTimer;
  if FHideTimer <> nil then FHideTimer.Enabled := True;
end;

procedure TTyScrollBar.StartFade(ATo: Single; ADurationMs: Integer);
begin
  { 「已经在那儿了」只有在**没有反方向的动画在跑**的时候才等于「无事可做」。
    只比可见度的话,装了膛还没推进的那一拍(可见度 1.0、目标 0.0)会在这里
    早退,上面那句重定向就白写了。 }
  if SameValue(FFadeLevel, ATo, 0.001) and
     (not FFadeAnim.Running or SameValue(FFadeTo, ATo, 0.001)) then Exit;
  FFadeFrom := FFadeLevel;
  FFadeTo := ATo;
  FFadeAnim := TyAnimatorInit(ADurationMs, teEaseOutCubic);
end;

function TTyScrollBar.PaintStyle: TTyStyleSet;
{ 主题给的那份样式，乘上自动隐藏的当前可见度。

  为什么乘进 opacity 而不是各自改颜色：TTyPainter.Opacity 是**画笔级**的
  ——EndPaint 对整张 FBmp 做一次 ApplyGlobalOpacity。所以这一个值一路管到
  边框、滑块和两头的箭头，不用挨个去调它们的 alpha；而且它淡下去的方向是
  「朝父控件的底色」而不是「朝透明」(见 EndPaint 里 OpacityBase 那段：
  朝透明淡在 Win10 的 DWM 玻璃窗上会把玻璃露出来)。

  完全可见时**原样**交出去，一个字段都不碰：多写一个 tpOpacity 进去，
  EndPaint 就从「不合成」那条路挪到「合成」那条路上，而没开自动隐藏的条
  一个像素都不许变。守它的是 test.scrollbar.autohide 的
  AtRestTheThemeStyleIsHandedOverUntouched。

  乘法不是摆设：主题给 TyScrollBar:disabled 写了 opacity(light/dark/green/
  system/showcase 都有),一条禁用的条淡出时要的是两者相乘,而不是拿淡出
  系数把主题那个值顶掉。 }
var
  base: Single;
begin
  Result := CurrentStyle;
  if SameValue(FFadeLevel, 1.0, 0.001) then Exit;
  { record 是非托管的：契约是 Present 那个集合——它没说有 tpOpacity，
    Result.Opacity 里是什么就不归契约管，不能直接乘上去。
    (今天 EmptyStyleSet 恰好把它种成 1.0，所以直接乘也能给出同一个答案；
    这句防的是「哪天种子变了、或者换一条不经过 EmptyStyleSet 的路进来」，
    那种事不会在这个单元里报错，只会让滚动条整条消失。) }
  if tpOpacity in Result.Present then base := Result.Opacity else base := 1.0;
  Result.Opacity := base * FFadeLevel;
  Include(Result.Present, tpOpacity);
end;

function TTyScrollBar.PaintStyleForTest: TTyStyleSet;
begin
  Result := PaintStyle;
end;

procedure TTyScrollBar.AutoHideTick(AMs: Integer);
var
  delay: Integer;
begin
  delay := EffectiveAutoHideMs;
  if delay < 0 then
  begin
    { 关着。任何残留的淡出都要收回来，否则改主题/改属性之后条会停在半透明。

      **停动画这一下不能挂在「可见度不对」里面**:可见度正好是 1.0、动画却还在
      跑的状态是够得着的 —— 淡出刚装上膛(Progress=0)可见度就是 1.0,淡入跑到
      Progress=0.9333 时缓动值 0.9997 也落在容差里。漏掉的话:定时器那句「没事
      干就歇」永远不成立,一条关着自动隐藏的条上挂着个 60fps 的空转定时器;
      哪天又把自动隐藏打开,膛里那发陈旧的淡出还会接着打出去。 }
    FFadeAnim.SetTargetImmediate(1.0);
    if not SameValue(FFadeLevel, 1.0, 0.001) then
    begin
      FFadeLevel := 1.0;
      Invalidate;
    end;
    Exit;
  end;

  if FFadeAnim.Running then
  begin
    if FFadeAnim.Advance(AMs) then
    begin
      FFadeLevel := TyLerpF(FFadeFrom, FFadeTo, FFadeAnim.Eased);
      Invalidate;
    end;
    if not FFadeAnim.Running then FFadeLevel := FFadeTo;
    Exit;   { 动画期间不计闲置——否则淡入刚跑一半就被判定该淡出 }
  end;

  if AutoHideHeldOpen then
  begin
    FIdleMs := 0;
    Exit;
  end;

  Inc(FIdleMs, AMs);
  if (FIdleMs >= delay) and (FFadeLevel > 0.0) then
    StartFade(0.0, TyScrollBarFadeOutMs);
end;

procedure TTyScrollBar.EnsureHideTimer;
begin
  { 设计期不淡(AutoHideHeldOpen 已经恒真),无窗口时也不建表——无头测试直接
    喂 AutoHideTick,建了也只是个永远空转的定时器。 }
  if (csDesigning in ComponentState) or not HandleAllocated then Exit;
  if FHideTimer = nil then
  begin
    FHideTimer := TTimer.Create(Self);
    FHideTimer.Enabled := False;
    FHideTimer.Interval := 16;   // ~60fps
    FHideTimer.OnTimer := @HandleHideTimer;
  end;
end;

procedure TTyScrollBar.ArmAutoHideClock;
begin
  { 真正的门是第二句 AutoHideTimerNeeded:已经淡到 0 又没人按住的条起表也没活干,
    头一拍就会把自己停掉——那一拍是白烧的,而且 HandleHideTimer 停表时顺手清掉
    FFadeLastTickMs,看着像什么都没发生过,查起来更费事。

    头一句是**热路径的短路**,不是第二道保险:AutoHideTimerNeeded 最后问的就是
    同一个 EffectiveAutoHideMs >= 0,所以单独摘掉头一句,行为上几乎看不出来
    ——变异测试证实过,全量 7103 条一条不红。它在这儿是因为 Invalidate 一秒钟
    要走几十次,而自动隐藏关着的条应该在**第一个字段读**上就出去,不该先绕过
    FFadeAnim.Running、再绕过 AutoHideHeldOpen(那里面还有一次 Focused,要问
    widgetset)。顺带也真挡住一种状态:淡出刚装上膛还没推进(可见度仍是 1.0)
    的那一刻主题把自动隐藏关掉,AutoHideTimerNeeded 会在 FFadeAnim.Running 上
    答 True —— 没这一句就会给一条主人已经关掉特性的条挂上表(下一拍自己会停,
    所以测不出来,但那一拍本来就不该有)。

    **这里不碰 FIdleMs**,理由见声明处。 }
  if EffectiveAutoHideMs < 0 then Exit;
  if not AutoHideTimerNeeded then Exit;
  EnsureHideTimer;
  if FHideTimer <> nil then FHideTimer.Enabled := True;
end;

function TTyScrollBar.AutoHideClockArmed: Boolean;
begin
  Result := (FHideTimer <> nil) and FHideTimer.Enabled;
end;

procedure TTyScrollBar.InitializeWnd;
begin
  inherited InitializeWnd;
  { 两个时钟都从这一刻起算。一条刚拿到句柄的条没有「已经闲置过的时间」——
    出生那一段它根本还不在屏幕上;FFadeLastTickMs 同理,留着出生前的旧戳的话
    头一拍会把那一整段报成经过时间,闲置时钟一步跨过延时,条一露面就开始淡。 }
  FIdleMs := 0;
  FFadeLastTickMs := 0;
  ArmAutoHideClock;
end;

function TTyScrollBar.AutoHideTimerNeeded: Boolean;
{ 三条,顺序是有讲究的。

  **跑着的淡入淡出排第一,这一条不是风格问题,是 Task 3 那个搁浅 bug 的完整重演。**
  一条已经淡到 0、表也停了的条,指针移到它(看不见的)那块地方上:MouseEnter ->
  NoteActivity 把淡入装上膛、把表起起来。要是先问「按住没有」,起起来的表**头一拍
  就把自己停掉**,而指针一直搁在那儿,再没有第二个 MouseEnter —— 条就在指针底下
  永远不出现。半路上被压住的淡出同理,会卡在半透明。

  「按住不放」要停表:指针停在滚动条上是个极其常见的鼠标停靠位置，而按住的时候
  本来就没有任何东西要推进(AutoHideTick 那条臂只是把闲置时钟清成 0)，让它以
  16ms 转下去纯属白烧。离开/失焦/松手三处各自调 NoteActivity 把表起回来;
  **单就那三处而言**,万一哪处漏了坏的方向是「条多留一会儿」,随便碰一下就恢复
  ——这句只管重启那三处,不管上面那个顺序,别拿它去给重排这几行背书。

  最后才问延时。它也不只是「省一次主题解析」:自动隐藏关掉(换主题或改属性)
  的那一刻表要是正转着,没有这一条它就**再也停不下来** —— 一条主人压根没开
  这个特性的滚动条上挂着个 60fps 的空转定时器,而构造函数许诺的是「不开这个
  特性的人一分钱不花」。 }
begin
  if FFadeAnim.Running then Exit(True);
  if AutoHideHeldOpen then Exit(False);
  Result := (EffectiveAutoHideMs >= 0) and (FFadeLevel > 0.0);
end;

procedure TTyScrollBar.HandleHideTimerTick;
begin
  HandleHideTimer(nil);
end;

procedure TTyScrollBar.HandleHideTimer(Sender: TObject);
begin
  { 按**真实经过的时间**推进,不是 FHideTimer.Interval 那个标称的 16。理由和
    200 行开外的 HandleTimer 一模一样:界面忙的时候定时器会被饿死,而**网格滚动
    中正是这段代码在跑的时候** —— 按标称累加的话 200 毫秒的淡出要爬将近一秒,
    1200 毫秒的延时能拖成好几秒。 }
  AutoHideTick(FadeTickElapsedMs);
  if not AutoHideTimerNeeded then
  begin
    { 停表必须把时刻戳一起清掉。下次起表可能是几分钟之后(指针一直压在条上),
      带着旧戳的话头一拍会把那整段时间报出来:闲置时钟一步跨过延时,指针刚一
      离开条就没了。位置缓动那边 HandleTimer 出于同样的理由清 FLastTickMs。 }
    FFadeLastTickMs := 0;
    { 判空:表是惰性建的(无头根本不建),而这个回调还能从 HandleHideTimerTick
      进来。和位置缓动的 HandleTimer 同一处理。 }
    if FHideTimer <> nil then FHideTimer.Enabled := False;
  end;
end;

function TTyScrollBar.FadeNowMs: QWord;
begin
  Result := GetTickCount64;
end;

function TTyScrollBar.FadeTickElapsedMs: Integer;
{ TickElapsedMs 的孪生体,自带时刻戳。**不能共用 FLastTickMs** ——那是位置缓动
  的,两套定时器各跑各的,共用一个戳就是互相把对方的起点冲掉。

  钳到至少 1 毫秒:除了讲得通,它还是挡住 0 毫秒步长的那道闸 —— TTyAnimator.Advance
  把 AMs <= 0 当成「直接吸附到 Target」,一个 0 毫秒的滴答会把淡出变成跳变。
  而 0 毫秒的一拍不是假想:两拍落在同一个 GetTickCount64 刻度里就是 0。 }
var
  nowMs: QWord;
begin
  nowMs := FadeNowMs;
  if FFadeLastTickMs = 0 then
    Result := 16
  else
    Result := Integer(nowMs - FFadeLastTickMs);
  FFadeLastTickMs := nowMs;
  if Result < 1 then Result := 1;
end;

procedure TTyScrollBar.MouseEnter;
begin
  { 不调 inherited 会吞掉 LCL 那层的 hover 状态。而「指针在不在条上」这件事
    inherited 已经记在 FHover 里了(TTyCustomControl.MouseEnter/MouseLeave 是
    全库仅有的两处写入),本控件画滑块时读的也是它 —— 所以这里不再另存一份,
    AutoHideHeldOpen 直接问 FHover。两个字段记同一件事,迟早会不一致。

    MouseLeave 从前不必重写,理由是「指针在条上的每一拍,按住不放那条臂都把闲置
    时钟清成 0 了,离开的那一刻它本来就是 0」。**那条理由现在不成立了**:按住的
    时候延时表是停的(见 AutoHideTimerNeeded),根本没有「每一拍」这回事,指针
    一走也就没人把表起回来。见 MouseLeave。 }
  inherited MouseEnter;
  NoteActivity;
end;

procedure TTyScrollBar.MouseLeave;
begin
  { 先 inherited:FHover 由它清(全库只有 TTyCustomControl.MouseEnter/MouseLeave
    写这个字段),清完 AutoHideHeldOpen 才答「没按住」。

    然后 NoteActivity —— 这是本方法存在的全部理由:表在指针压上来的时候停了,
    这里不把它起回来的话,条就一直留在屏幕上。顺带把闲置从「离开这一刻」重新
    起算,那本来就是该有的语义。

    NoteActivity 里 FHideTimer.Enabled := True 是**下一拍**才生效的(16ms 之后),
    所以哪怕这一刻 FHover 还没清干净也不要紧:等表真转起来的时候,状态早就稳了。
    DoExit 那一半就是靠这个才不必去操心 LCL 什么时候把 Focused 翻成 False。 }
  inherited MouseLeave;
  NoteActivity;
end;

procedure TTyScrollBar.DoEnter;
begin
  { 焦点不只是「不计时」,还得**把条叫回来**。独立摆放的条 TabStop=True:等它
    淡到 0、定时器把自己停掉之后再 Tab 过来,按住不放那条臂连跑的机会都没有
    (没人推它了),键盘焦点就停在一个看不见的控件上 —— 这是可访问性事故,
    不是设计。悬停那一半由 MouseEnter 拿到,焦点这一半得自己写。

    从前说「不写对应的 DoExit」,理由和 MouseLeave 那条一样,也和它一起作废了:
    见 DoExit。 }
  inherited DoEnter;
  NoteActivity;
end;

procedure TTyScrollBar.DoExit;
begin
  { 和 MouseLeave 同理,焦点这一半。逐条 trace 过确实需要:六个宿主的内嵌条虽然
    TabStop=False,MouseDown 里那句 if CanFocus then SetFocus 照样能把焦点给它,
    于是「点一下条、再去点别处」就走到这里;有焦点的那段延时表是停的,这里不
    起回来的话条就一直留着。 }
  inherited DoExit;
  NoteActivity;
end;

procedure TTyScrollBar.Invalidate;
begin
  { 换主题是这个类唯一听不见的事件:TTyStyleController.Changed 广播出来的就是
    一个光秃秃的 Invalidate(它自己的注释也这么写),全库没有 StyleChanged 钩子。
    于是「自动隐藏的主题下淡到 0、定时器把自己停了,再换到一个不自动隐藏的主题」
    会让条永久隐身:没有任何东西会再推它一拍。属性那条路(SetAutoHide ->
    NoteActivity)早就防了同一个坑,主题这半边只能挂在这里。

    为什么不用 AddChangeListener:全库的控件没有一个用它(只有 TTyNativeStyler
    那种非可视组件在用,它自己管 controller 的加和摘),而控件的 Controller 可以
    中途换、还能是 nil 回落到进程级的 TyDefaultController —— 把每一根滚动条的
    方法指针塞进那张全局表,哪回忘了摘就是野指针。

    重绘是热路径,所以三个条件的**顺序**是有讲究的:前两个都只是读字段,常态
    (可见度就是 1.0)在第二个条件上就短路了,要读主题的那个条件只有在条真的
    淡着的时候才走得到。(那次解析现在带缓存了——见 ThemeAutoHideMs——但命中
    也不是免费的,顺序照旧。)
    not FFadeAnim.Running 也是必须的:正在跑的淡入淡出不能被这里掐断。 }
  if (not FFadeAnim.Running) and (FFadeLevel < 1.0) and (EffectiveAutoHideMs < 0) then
  begin
    FFadeAnim.SetTargetImmediate(1.0);
    FFadeLevel := 1.0;
  end
  { **换主题的另一半方向,从前这里是空的。** 上面那条管「换到一个不自动隐藏的
    主题」,可反过来——换到一个自动隐藏的皮肤——同样没有任何东西会去起表:
    条没被碰过就没有 NoteActivity,句柄早就有了所以 InitializeWnd 也过去了,
    于是新皮肤明明写了 1200,条却一直亮着。跟上面那条是同一个根:换主题只有
    Invalidate 这一个广播。

    顺序是为热路径挑的,不是随手写的:重绘一秒钟几十次,而绝大多数重绘发生在
    表已经转着的条上——先读 FHideTimer.Enabled 这个字段,那种情形一次比较就
    短路了;自动隐藏关着的条落到 ArmAutoHideClock,头一句就是带缓存的
    EffectiveAutoHideMs,同样立刻出来。 }
  else if (FHideTimer = nil) or (not FHideTimer.Enabled) then
    ArmAutoHideClock;
  inherited Invalidate;
end;

procedure TTyScrollBar.EnsureTimer;
begin
  if FTimer = nil then
  begin
    FTimer := TTimer.Create(Self);
    FTimer.Enabled := False;
    FTimer.Interval := 16;  // ~60fps
    FTimer.OnTimer := @HandleTimer;
  end;
end;

{ 这一拍该推进多少毫秒 = 距上一拍的**真实**经过时间。
  抽成可覆写的,是为了让测试能喂一个受控时钟 —— 否则"按真实时间推进"
  这条只能靠肉眼在真机上看,而这正是当初写成名义间隔也没人发现的原因。 }
function TTyScrollBar.TickElapsedMs: Integer;
var
  nowMs: QWord;
begin
  nowMs := GetTickCount64;
  if FLastTickMs = 0 then
    Result := 16
  else
    Result := Integer(nowMs - FLastTickMs);
  FLastTickMs := nowMs;
  if Result < 1 then Result := 1;
end;

procedure TTyScrollBar.HandleTimerTick;
begin
  HandleTimer(nil);
end;

procedure TTyScrollBar.HandleTimer(Sender: TObject);
var
  elapsed: Integer;
begin
  { 按**真实经过的时间**推进,不能按定时器的名义间隔累加。

    界面忙的时候(例如大网格重绘一帧要上百毫秒)定时器会被饿死:
    按名义 16ms 一步的话,120ms 的缓动要七八次滴答才走完,而每次滴答实际隔了
    上百毫秒 —— 缓动被拉成将近一秒,看起来就是"滑块慢一拍才跟上"。
    按真实时间推进时,一次迟到的滴答会把该走的进度一次补齐。 }
  elapsed := TickElapsedMs;
  if AdvanceAnimation(elapsed) then
    Invalidate;
  if not FPosAnim.Running then
  begin
    { 定时器是**惰性创建**的(SetPositionAnimating 这个测试缝就不建它),
      所以这里必须判空 —— 从前是直接 FTimer.Enabled,靠"只有定时器自己会调
      HandleTimer"这个隐含前提撑着。 }
    if FTimer <> nil then FTimer.Enabled := False;
    FLastTickMs := 0;
  end;
end;

function TTyScrollBar.AdvanceAnimation(AMs: Integer): Boolean;
begin
  Result := FPosAnim.Advance(AMs);
end;

function TTyScrollBar.DisplayPos: Single;
begin
  { Mid-drag with LiveTracking off, the thumb is ahead of Position on purpose -- that gap IS
    the mode. Everything that PAINTS the thumb goes through here, so putting the exception in
    this one function is what keeps the hit test and the paint agreeing: MouseDown's thumb-rect
    test uses FPosition, and during such a drag the hit test is irrelevant (we already have the
    capture), while at rest FTrackPos = FPosition and the two are the same number again. }
  if FDragging and not FLiveTracking then
    Exit(FTrackPos);
  Result := TyLerpF(FAnimFrom, FAnimTo, FPosAnim.Eased);
end;

procedure TTyScrollBar.SetPositionAnimating(AValue: Integer);
var
  Clamped: Integer;
begin
  Clamped := AValue;
  if Clamped < FMin then Clamped := FMin;
  if Clamped > FMax then Clamped := FMax;
  // Arm the ease from the currently displayed thumb position to the new target,
  // independent of handle state (test seam). FPosition still tracks the logical
  // value for Min/Max/value semantics.
  FAnimFrom := DisplayPos;
  FAnimTo := Clamped;
  FPosAnim.Progress := 0;
  FPosAnim.Target := 1;
  FPosition := Clamped;
  Invalidate;
end;

procedure TTyScrollBar.SetPositionSnapped(AValue: Integer);
var
  Clamped: Integer;
begin
  Clamped := AValue;
  if Clamped < FMin then Clamped := FMin;
  if Clamped > FMax then Clamped := FMax;

  { 无条件停掉可能正在跑的缓动 —— 哪怕位置没变也要停,
    否则上一次的缓动会继续把滑块拖向一个**过时**的目标。 }
  FAnimFrom := Clamped;
  FAnimTo := Clamped;
  FPosAnim.SetTargetImmediate(1);
  if FTimer <> nil then FTimer.Enabled := False;

  if FPosition = Clamped then
  begin
    Invalidate;
    Exit;
  end;
  FPosition := Clamped;
  Invalidate;
  if Assigned(FOnChange) then FOnChange(Self);

  { 镜像过来的位置一样算「在用」。这条路**绕开了 Position 的 setter**,所以
    唤醒必须在这里单独写一遍 —— 全库只有 TTyGrid 走它(其余五个宿主都是
    Position := ),而网格恰恰是最该看见滚动条出来的那个控件。

    这条路跳过位置缓动,是因为内容已经被宿主挪走了、滑块再缓动追过去就不跟手;
    那跟「这条滚动条该不该看得见」是两码事,别把两件事连坐。

    网格有两处调用写着 if not Dragging then ——那时候条本来就被 FDragging
    按住不放,这里不会重复唤醒,别当成冗余顺手删掉。 }
  NoteActivity;
end;

procedure TTyScrollBar.SetKind(const AValue: TTyScrollBarKind);
begin
  if FKind = AValue then Exit;
  FKind := AValue;
  Invalidate;
end;

procedure TTyScrollBar.SetMin(const AValue: Integer);
begin
  if FMin = AValue then Exit;
  FMin := AValue;
  if FPosition < FMin then FPosition := FMin;
  Invalidate;
end;

procedure TTyScrollBar.SetMax(const AValue: Integer);
begin
  if FMax = AValue then Exit;
  FMax := AValue;
  if FPosition > FMax then FPosition := FMax;
  Invalidate;
end;

procedure TTyScrollBar.SetPosition(const AValue: Integer);
var
  Clamped: Integer;
begin
  Clamped := AValue;
  if Clamped < FMin then Clamped := FMin;
  if Clamped > FMax then Clamped := FMax;
  if FPosition = Clamped then Exit;
  // Decide how the PAINTED thumb reaches the new value:
  if FDragging then
  begin
    // Live drag: the thumb must track the mouse, so snap instantly.
    FAnimFrom := Clamped;
    FAnimTo := Clamped;
    FPosAnim.SetTargetImmediate(1);
    FNeedImmediateRepaint := True;
  end
  else if FAnimEnabled and HandleAllocated then
  begin
    // Programmatic change with a window: ease the thumb from where it is now to
    // the new value. (Headless render tests have no handle -> they snap below.)
    FAnimFrom := DisplayPos;
    FAnimTo := Clamped;
    FPosAnim.Progress := 0;
    FPosAnim.Target := 1;
    EnsureTimer;
    FLastTickMs := 0;          { 重新起算,别把上一段动画的时刻带进来 }
    FTimer.Enabled := True;
  end
  else
  begin
    // Headless (no handle) or animations off: snap so DisplayPos == new
    // immediately, keeping the existing exact-pixel scrollbar tests green.
    FAnimFrom := Clamped;
    FAnimTo := Clamped;
    FPosAnim.SetTargetImmediate(1);
  end;
  FPosition := Clamped;
  Invalidate;

  { 拖动中**立刻把自己重画掉**,不要排队等下一轮消息循环。

    滑块是独立的窗口化控件,本来有自己的 WM_PAINT;但 WM_PAINT 优先级最低,
    宿主(大网格一帧要几十毫秒)一忙,滑块的重绘就被挤到后面 —— 表现就是
    "内容在动、滑块慢半拍"。自己这块表面很小(实测整屏 blit 才 0.8ms,
    滑块只有它的百分之一),同步刷一次完全不心疼。

    只在拖动时这么做:程序性变化走正常的排队重绘,不必抢。 }
  if FNeedImmediateRepaint then
  begin
    FNeedImmediateRepaint := False;
    if HandleAllocated then Update;
  end;

  if Assigned(FOnChange) then
    FOnChange(Self);

  { 位置变了就是「在用」——哪怕这一下是宿主代码赋的值。滚轮、键盘、点滑道
    都经过这里,所以唤醒写在这一处就够,不必在每个手势里各来一遍。
    **SetPositionSnapped 不经过这里**:宿主自己滚完内容、再把位置镜像给滑块的
    那条路是单独的一条,接线是宿主那一步的事。 }
  NoteActivity;
end;

procedure TTyScrollBar.SetPageSize(const AValue: Integer);
begin
  if FPageSize = AValue then Exit;
  if AValue < 0 then
    FPageSize := 0
  else
    FPageSize := AValue;
  Invalidate;
end;

procedure TTyScrollBar.SetSmallChange(const AValue: Integer);
begin
  if AValue < 1 then
    FSmallChange := 1
  else
    FSmallChange := AValue;
end;

procedure TTyScrollBar.SetLargeChange(const AValue: Integer);
begin
  // Negative is meaningless (a page action would scroll backwards); 0 is the "follow
  // PageSize" sentinel, so it is the floor rather than 1.
  if AValue < 0 then
    FLargeChange := 0
  else
    FLargeChange := AValue;
end;

{ FTrackPos is only meaningful for the duration of a deferred drag; outside one the pending
  value IS the committed value, and deriving that here rather than keeping the field in sync
  from every setter leaves exactly one place that can be wrong. }
function TTyScrollBar.GetTrackPosition: Integer;
begin
  if FDragging and not FLiveTracking then
    Result := FTrackPos
  else
    Result := FPosition;
end;

function TTyScrollBar.EffectiveLargeChange: Integer;
begin
  if FLargeChange > 0 then Result := FLargeChange else Result := FPageSize;
  if Result < 1 then Result := 1;   // a page action that moves nothing is a dead control
end;

procedure TTyScrollBar.DoScroll(ACode: TScrollCode; var APos: Integer);
begin
  if Assigned(FOnScroll) then
    FOnScroll(Self, ACode, APos);
end;

procedure TTyScrollBar.ScrollTo(ACode: TScrollCode; AProposed: Integer);
var
  P: Integer;
begin
  // Clamp the proposed value first, let the OnScroll handler optionally adjust
  // it (honoring its var parameter), then commit through the Position setter
  // (which clamps again and fires OnChange).
  P := AProposed;
  if P < FMin then P := FMin;
  if P > FMax then P := FMax;
  DoScroll(ACode, P);
  Position := P;
end;

function TTyScrollBar.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
begin
  // Let the published OnMouseWheel/Up/Down events fire first; if a handler marks
  // the wheel handled, honor that and do not step.
  Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
  if Result then Exit;
  if not Enabled then Exit;
  // Convention: wheel-up (WheelDelta > 0) scrolls content up -> Position
  // DECREASES by SmallChange; wheel-down increases it. (Standard scrollbar.)
  Position := Position - Sign(WheelDelta) * FSmallChange;
  Result := True;
end;

procedure TTyScrollBar.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, ThumbS: TTyStyleSet;
  R, Track, ThumbR, LoR, HiR: TRect;
  ThumbFill: TTyFill;
  ThumbStates: TTyStateSet;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    { PaintStyle，不是 CurrentStyle：自动隐藏的淡出**只有这一个入口**进绘制。
      DrawFrame 把 S.Opacity 交给画笔，而画笔的 opacity 是整张位图一起算的，
      所以下面的滑块和箭头不用各自再乘一遍(见滑块那处的注释)。 }
    S := PaintStyle;
    { 彻底隐身那一格短路掉，**不走画笔的 opacity**。

      走的话就掉进 EndPaint 的合成分支：那条路先按 TyResolveParentBg 给的
      **一个居中采样色**铺一层不透明底，再把 alpha 全零的 FBmp 盖上去——
      TyFillParentBg 刚刚画进去的渐变切片/图片切片全被扔掉，留在屏幕上的是
      一块平板。而滚动条是窗口化控件，没有别的东西会来重画这块矩形，所以
      用户看到的就是这块平板，一直摆在那儿，不是 200 毫秒的过场。

      之前没人撞上是因为 --disabled-opacity 是 0.5，永远到不了 0；自动隐藏
      是头一个把 opacity 一路压到 0 的特性。

      短路之后这一格干脆不画自己：把父控件的背景按**本控件这块矩形**原样
      铺一遍就收工——既是像素级准确的背景，又省掉整趟绘制。 }
    if (tpOpacity in S.Present) and (S.Opacity <= 0.0) then
    begin
      TyFillParentBg(Self, P, R, S);
      P.EndPaint;
      Exit;
    end;
    DrawFrame(P, R, S);
    Track := TyScrollTrackRect(R, FKind, TyScrollButtonSize(R, FKind));
    // The PAINTED thumb uses the displayed (possibly mid-animation) position; at
    // rest DisplayPos == FPosition so headless renders are pixel-identical. The
    // track-paging hit math, drag math and BeginThumbDrag keep using FPosition.
    ThumbR := TyScrollThumbRect(Track, FKind, FMin, FMax, Round(DisplayPos), FPageSize, Mirrored);
    // Thumb fill is its own sub-element typeKey (TyScrollThumb). Feed the control's
    // hover/press state so TyScrollThumb:hover/:active render (matches the pre-typeKey
    // behavior where the thumb borrowed the parent's state-resolved TextColor).
    ThumbStates := [];
    if FPressed then
      Include(ThumbStates, tysActive)
    else if FHover then
      Include(ThumbStates, tysHover);
    { 这里**不用**再乘一遍淡出系数。滑块和上面的边框画进的是同一张 FBmp，
      而 EndPaint 的 ApplyGlobalOpacity 是对整张图做的，所以 DrawFrame 那一下
      已经把滑块一起管了；在这儿再乘一次只会把它压得比条身更淡。
      (RenderTo 也根本不读 ThumbS.Opacity——只取 Background.Color 和
      BorderRadius。哪天滑块被挪去单开一个 painter，就要自己接淡出了：
      test.scrollbar.autohide 的 FadeReachesThePaintedPixels 数的是整块像素，
      到时候会红。) }
    ThumbS := ActiveController.Model.ResolveStyle('TyScrollThumb', '', ThumbStates);
    ThumbFill := Default(TTyFill);
    ThumbFill.Kind := tfkSolid;
    ThumbFill.Color := ThumbS.Background.Color;
    P.FillBackground(ThumbR, ThumbFill, ThumbS.BorderRadius);
    ButtonRects(R, LoR, HiR);
    if (LoR.Right > LoR.Left) then   // buttons exist
    begin
      if FKind = sbVertical then
      begin
        // v3/C5 overridable. Triangles: a scroll-bar end button steps the view, the same role
        // the spin buttons have, and Windows draws both from the same triangular idiom.
        TyDrawGlyph(P, ActiveController, TySquareGlyphBox(LoR), tgTriangleUp,   S.TextColor, 2, 1);
        TyDrawGlyph(P, ActiveController, TySquareGlyphBox(HiR), tgTriangleDown, S.TextColor, 2, 1);
      end
      else
      begin
        { The GLYPHS do not swap under MirrorHorizontal, and that is not an omission.
          Reflecting a pair "left arrow at the left end, right arrow at the right end" gives
          back the same picture, which is why Windows' mirrored horizontal bar is visually
          indistinguishable from its unmirrored one. What the mirror moves is the MEANING:
          the left-end button now steps Position UP (see MouseDown), because that is the
          direction the thumb travels when it goes left. Drawing tgArrowRight on the left
          would make the button point away from where it sends the thumb. }
        TyDrawGlyph(P, ActiveController, TySquareGlyphBox(LoR), tgTriangleLeft,  S.TextColor, 2, 1);
        TyDrawGlyph(P, ActiveController, TySquareGlyphBox(HiR), tgTriangleRight, S.TextColor, 2, 1);
      end;
    end;
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyScrollBar.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

function TTyScrollBar.TrackRect: TRect;
begin
  // Inset client by a button-size at each end so the thumb/drag/paging
  // operate on the track between the (Task 5) end arrow buttons.
  Result := TyScrollTrackRect(ClientRect, FKind, TyScrollButtonSize(ClientRect, FKind));
end;

procedure TTyScrollBar.ButtonRects(const AClient: TRect; out ALo, AHi: TRect);
var
  bs, mainLen: Integer;
begin
  bs := TyScrollButtonSize(AClient, FKind);
  if FKind = sbVertical then
    mainLen := AClient.Bottom - AClient.Top
  else
    mainLen := AClient.Right - AClient.Left;
  if mainLen <= 2 * bs then
  begin
    ALo := Rect(0, 0, 0, 0);
    AHi := Rect(0, 0, 0, 0);
    Exit;   // no buttons
  end;
  if FKind = sbVertical then
  begin
    ALo := Rect(AClient.Left, AClient.Top, AClient.Right, AClient.Top + bs);
    AHi := Rect(AClient.Left, AClient.Bottom - bs, AClient.Right, AClient.Bottom);
  end
  else
  begin
    ALo := Rect(AClient.Left, AClient.Top, AClient.Left + bs, AClient.Bottom);
    AHi := Rect(AClient.Right - bs, AClient.Top, AClient.Right, AClient.Bottom);
  end;
end;

function TTyScrollBar.TrackLength: Integer;
var
  Track: TRect;
begin
  // Derive from the inset track so drag and paint share the same rect basis
  // (TyScrollThumbRect is now computed against the inset track).
  Track := TrackRect;
  if FKind = sbVertical then
    Result := Track.Bottom - Track.Top
  else
    Result := Track.Right - Track.Left;
end;

procedure TTyScrollBar.BeginThumbDrag(AGrabPosAlongTrack: Integer);
var
  ThumbR: TRect;
  ThumbStart: Integer;
begin
  ThumbR := TyScrollThumbRect(TrackRect, FKind, FMin, FMax, FPosition, FPageSize, Mirrored);
  if FKind = sbVertical then
    ThumbStart := ThumbR.Top
  else
    ThumbStart := ThumbR.Left;
  FDragging := True;
  FDragStartTop := ThumbStart;
  FDragGrabOffset := AGrabPosAlongTrack - ThumbStart;
  // The pending value starts where the committed one is; with LiveTracking off this is
  // what the thumb is painted from until mouse-up.
  FTrackPos := FPosition;
  // Sync the displayed thumb to the logical position on grab so DisplayPos ==
  // FPosition at drag start (subsequent drag SetPosition calls snap).
  FAnimFrom := FPosition;
  FAnimTo := FPosition;
  FPosAnim.SetTargetImmediate(1);
end;

procedure TTyScrollBar.DragThumbTo(APosAlongTrack: Integer);
var
  Track, ThumbR: TRect;
  ThumbLen, FreeSpace, NewTop, Travel, NewPos, TrackStart, Off: Integer;
begin
  if not FDragging then Exit;
  Track := TrackRect;
  ThumbR := TyScrollThumbRect(Track, FKind, FMin, FMax, FPosition, FPageSize, Mirrored);
  if FKind = sbVertical then
    ThumbLen := ThumbR.Bottom - ThumbR.Top
  else
    ThumbLen := ThumbR.Right - ThumbR.Left;
  FreeSpace := TrackLength - ThumbLen;
  if FreeSpace < 1 then FreeSpace := 1;
  // The thumb lives in [TrackStart, TrackStart+FreeSpace] in CLIENT coords,
  // because the track is inset by a button-size at each end.
  if FKind = sbVertical then
    TrackStart := Track.Top
  else
    TrackStart := Track.Left;
  NewTop := APosAlongTrack - FDragGrabOffset;
  if NewTop < TrackStart then NewTop := TrackStart;
  if NewTop > TrackStart + FreeSpace then NewTop := TrackStart + FreeSpace;
  Travel := FMax - FMin;
  { The inverse of TyScrollThumbRect, through the same one-line mirror it uses. NewTop is a
    real CLIENT coordinate either way (the thumb follows the cursor whichever end the origin
    is at); what the mirror decides is only how that distance-from-the-left is read back as a
    distance-from-the-ORIGIN. }
  Off := TyScrollMirrorOffset(NewTop - TrackStart, FreeSpace, FKind, Mirrored);
  NewPos := FMin + Integer((Int64(Off) * Travel) div FreeSpace);
  // Live drag tracking fires scTrack with the proposed value (handler may
  // adjust it); commit through the Position setter (clamps + OnChange).
  if NewPos < FMin then NewPos := FMin;
  if NewPos > FMax then NewPos := FMax;
  DoScroll(scTrack, NewPos);
  if FLiveTracking then
    Position := NewPos
  else
  begin
    { Deferred commit. The thumb still has to MOVE -- a drag whose thumb sat still would read
      as a dead control -- so record the pending value and repaint from it (RenderTo paints
      DisplayPos, which returns FTrackPos for the duration of this drag). Position, OnChange
      and scPosition all wait for EndThumbDrag.

      Repaint synchronously, for the same reason the live path does: the bar is its own window
      and WM_PAINT is the lowest-priority message, so on a busy host a queued repaint lands a
      frame or two after the mouse and the thumb visibly lags the cursor. }
    if FTrackPos <> NewPos then
    begin
      FTrackPos := NewPos;
      Invalidate;
      if HandleAllocated then Update;
    end;
  end;
end;

procedure TTyScrollBar.EndThumbDrag;
var
  P: Integer;
  wasDragging: Boolean;
begin
  wasDragging := FDragging;
  if FDragging then
  begin
    { Final committed value of the drag: scPosition then scEndScroll.

      With LiveTracking off this is the ONLY place the drag reaches Position, so the proposed
      value is the pending one, not the (still untouched) current one. Position is written
      unconditionally in that case -- the `if P <> FPosition` short-circuit below is about a
      handler having ADJUSTED an already-committed value, and here there is nothing committed
      yet. FDragging is still True, so the setter snaps rather than gliding, and the content
      lands exactly where the thumb was let go. }
    if FLiveTracking then
      P := FPosition
    else
      P := FTrackPos;
    DoScroll(scPosition, P);
    if (P <> FPosition) or not FLiveTracking then
      Position := P;
    P := FPosition;
    DoScroll(scEndScroll, P);
    if P <> FPosition then
      Position := P;
  end;
  FDragging := False;
  FTrackPos := FPosition;
  { 松手也要把延时表起回来:按住的那段表是停的(AutoHideTimerNeeded)。

    **只在真有一次拖动结束的时候**。MouseUp 是无条件调 EndThumbDrag 的,箭头
    点击、滑道翻页的那次抬起也会走到这里,而那些路本来就没人按住表;它们该有的
    「在用」由 ScrollTo -> Position -> NoteActivity 给。

    放在这里而不是 MouseUp,是因为 EndThumbDrag 是公开的:宿主自己驱动拖动的话
    松手就只经过这里。source/ 里现在还没有哪个宿主这么用,是留给以后的。

    上面那几句 Position := 有时候也会顺带 NoteActivity,但那是在 FDragging 还
    是 True 的时候,而且只在值真变了的时候才走 —— 原地放手的拖动一次都不走。 }
  if wasDragging then NoteActivity;
end;

function TTyScrollBar.PosAlong(X, Y: Integer): Integer;
begin
  { Stays a raw CLIENT coordinate under mirroring. The scoping document proposed turning this
    into TrackRect.Right - X, "one line"; it is the wrong line. Everything downstream of this
    -- BeginThumbDrag's ThumbR.Left, DragThumbTo's clamp against Track.Left, the thumb rect
    the click is tested against -- is in client coordinates, so flipping here would leave the
    grab offset measured from one end and the thumb from the other. The flip belongs where
    the offset becomes a POSITION, which is TyScrollMirrorOffset, and it is applied there. }
  if FKind = sbVertical then
    Result := Y
  else
    Result := X;
end;

procedure TTyScrollBar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  ThumbR, LoR, HiR: TRect;
  Back, Fwd: TScrollCode;
  BackSign: Integer;
begin
  if not Enabled then Exit;
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    { WHICH WAY THE LOW END OF THE BAR STEPS. On a mirrored horizontal bar the origin is the
      right end, so the LEFT-hand button and the track left of the thumb are the direction
      Position INCREASES -- the same swap the thumb's own arithmetic makes. Resolving it once
      into a pair of (code, step) values keeps the six call sites below from each having to
      remember it. BackSign is the sign the LEFT/TOP side moves Position in; the right/bottom
      side is its negation. }
    if Mirrored then
    begin
      Back := scLineDown;  Fwd := scLineUp;    BackSign := +1;
    end
    else
    begin
      Back := scLineUp;    Fwd := scLineDown;  BackSign := -1;
    end;
    ButtonRects(ClientRect, LoR, HiR);
    if PtInRect(LoR, Point(X, Y)) then
    begin
      ScrollTo(Back, Position + BackSign * FSmallChange);
      try if CanFocus then SetFocus; except end;
      Exit;
    end;
    if PtInRect(HiR, Point(X, Y)) then
    begin
      ScrollTo(Fwd, Position - BackSign * FSmallChange);
      try if CanFocus then SetFocus; except end;
      Exit;
    end;
    { THE HIT TEST AND THE PAINT ARE THE SAME CALL. RenderTo builds its thumb from
      TyScrollThumbRect and so does this, with the same Mirrored argument -- there is no
      second copy of the geometry that could be mirrored on one side only. (The painted rect
      uses DisplayPos so the thumb can glide; at rest, and always while dragging, that equals
      FPosition.) }
    ThumbR := TyScrollThumbRect(TrackRect, FKind, FMin, FMax, FPosition, FPageSize, Mirrored);
    if PtInRect(ThumbR, Point(X, Y)) then
    begin
      BeginThumbDrag(PosAlong(X, Y));
      { A control with no window cannot hold a capture, and LCL does not say so gently:
        SetCaptureControl forces the handle into existence and the widgetset RAISES when the
        window class is not registered -- which in a headless runner is any process that has
        not already built a form. The drag itself is pure arithmetic and works without one,
        so the only thing that raise ever did was put the hit test out of reach of a guard. }
      if HandleAllocated then MouseCapture := True;
    end
    else
    begin
      // click on the track: page one PageSize toward the click
      if (FKind = sbVertical) and (Y < ThumbR.Top) then
        ScrollTo(scPageUp, Position - EffectiveLargeChange)
      else if (FKind = sbVertical) and (Y >= ThumbR.Bottom) then
        ScrollTo(scPageDown, Position + EffectiveLargeChange)
      else if (FKind = sbHorizontal) and (X < ThumbR.Left) then
        ScrollTo(Back, Position + BackSign * EffectiveLargeChange)
      else if (FKind = sbHorizontal) and (X >= ThumbR.Right) then
        ScrollTo(Fwd, Position - BackSign * EffectiveLargeChange);
    end;
    try
      if CanFocus then SetFocus;
    except
    end;
  end;
end;

procedure TTyScrollBar.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  if not Enabled then Exit;
  inherited MouseMove(Shift, X, Y);
  if FDragging then
    DragThumbTo(PosAlong(X, Y));
end;

procedure TTyScrollBar.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    EndThumbDrag;
    MouseCapture := False;
  end;
end;

procedure TTyScrollBar.KeyDown(var Key: Word; Shift: TShiftState);
var
  Dec1, Inc1: Word;
begin
  if not Enabled then Exit;
  inherited KeyDown(Key, Shift);
  if FKind = sbVertical then
  begin
    Dec1 := VK_UP;
    Inc1 := VK_DOWN;
  end
  else if Mirrored then
  begin
    { The arrow keys on a scroll bar are a LAYOUT direction, not a text direction, so they
      follow the mirror (plans/2026-08-04-rtl-mirroring-scope.md §6.3 item 4 draws exactly
      this line: keys that move through a laid-out thing flip, keys that move through a
      STRING do not). Left steps the thumb left, which on a mirrored bar is up-Position.
      Home/End below stay logical -- they mean first/last, not leftmost/rightmost. }
    Dec1 := VK_RIGHT;
    Inc1 := VK_LEFT;
  end
  else
  begin
    Dec1 := VK_LEFT;
    Inc1 := VK_RIGHT;
  end;
  if Key = Dec1 then
  begin
    ScrollTo(scLineUp, Position - FSmallChange);
    Key := 0;
  end
  else if Key = Inc1 then
  begin
    ScrollTo(scLineDown, Position + FSmallChange);
    Key := 0;
  end
  else
    case Key of
      VK_PRIOR: begin ScrollTo(scPageUp, Position - EffectiveLargeChange); Key := 0; end;
      VK_NEXT:  begin ScrollTo(scPageDown, Position + EffectiveLargeChange); Key := 0; end;
      VK_HOME:  begin ScrollTo(scTop, FMin); Key := 0; end;
      VK_END:   begin ScrollTo(scBottom, FMax); Key := 0; end;
    end;
end;

end.
