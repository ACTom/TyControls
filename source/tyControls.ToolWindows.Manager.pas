unit tyControls.ToolWindows.Manager;
{$mode objfpc}{$H+}

{ 工具窗口栏的协调者 TTyToolWindowManager(spec §2):MoveWindow 和它的异步队列(spec §9.9)、
  跨栏拖动的命中测试(§9.4)、布局的保存 / 读取 / 恢复和时机(§10)。栏、窗口、手势引擎要的
  那一面(注册表、拖动状态、共享图片列表、结构检查、移动事件、一次跨栏移动的提交)在基类
  TTyCustomToolWindowManager(tyControls.ToolWindows);这里碰栏和窗口的内部只经基类的
  protected 方法。 }

interface

uses
  Classes, SysUtils, Types, Controls, Forms,
  tyControls.ToolWindows,
  tyControls.ToolWindows.Layout,      { 跨栏命中测试:TyToolWindowDropAt 和探测矩形 }
  tyControls.ToolWindows.LayoutText;  { 布局串:解析、格式化、版本漂移计划 }

type
  { manager 自己的异步队列里的一项(spec §9.9 / §10.5)。 }
  TTyToolWindowQueuedKind = (twqMove, twqIndex, twqLayout);
  TTyToolWindowQueued = record
    Kind: TTyToolWindowQueuedKind;
    Window: TTyToolWindow;       { twqMove / twqIndex }
    Target: TTyToolWindowBar;    { twqMove }
    Index: Integer;
    Text: string;                { twqLayout:要读的布局串 }
    IsReset: Boolean;            { twqLayout:恢复默认布局,执行时取那一刻的默认布局 }
    { 捕获还在窗口里、已经再排过一次(只再排一次:按钮自己的点击处理那时早就返回了)。 }
    Requeued: Boolean;
    { 已经执行过、或者执行前被作废了(RunQueue 正在跑的那一批里用)。 }
    Dead: Boolean;
  end;
  TTyToolWindowQueue = array of TTyToolWindowQueued;

  { 加载中调 Load / Reset 存下的唯一一份挂起计划(spec §10.5)。 }
  TTyToolLayoutPending = (tlpNone, tlpLoad, tlpReset);

  { 布局串的三组各对应哪条可用栏、它的窗口(Controls 顺序)。没有可用栏的组是 nil。 }
  TTyToolLayoutBars = array[TTyToolLayoutSide] of TTyToolWindowBar;
  TTyToolLayoutWindows = array[TTyToolLayoutSide] of TTyToolWindowArray;

  { 工具窗口栏的协调者(spec §2):可以不放。栏经 Manager 属性注册到它上面;跨侧拖动、
    MoveWindow、布局保存都要它。非可视组件,从 TTyComponent 来(带对象查看器里的 Version)。
    不支持放在数据模块里、栏分布在多个窗体上(spec §10.6)。 }
  TTyToolWindowManager = class(TTyCustomToolWindowManager)
  private
    { 排着的移动(spec §9.9),按调用顺序。FRunning 是 RunQueue 此刻正在执行的那一批:
      执行前把那一项的 Window 置 nil,PurgeQueue 也在这里清(执行中别的项的窗口被释放)。 }
    FQueue: TTyToolWindowQueue;
    FRunning: TTyToolWindowQueue;
    FQueuePosted: Boolean;
    { --- 布局(spec §10) --- }
    { > 0 = 正在应用布局的批次。 }
    FApplying: Integer;
    { 默认布局(ResetLayout 恢复的对象)存成一份布局串:记 = SaveLayoutToString,恢复 = 按这份串
      走 Load 那一条应用路径 —— 不另存一份状态快照,Reset 和 Load 的版本漂移规则(spec §10.3)、
      批次和事件(§10.4)就是同一套。 }
    FDefaultText: string;
    FDefaultCaptured: Boolean;
    { 用户调过 CaptureDefaultLayout:之后加载结束也不再自动覆盖。 }
    FDefaultExplicit: Boolean;
    FOnLayoutApplied: TNotifyEvent;
    { 加载中调 Load / Reset 存下的唯一一份挂起计划(后来的覆盖前面的,spec §10.5)。 }
    FPendingKind: TTyToolLayoutPending;
    FPendingText: string;
  private
    { RunQueue 被调了几次,所有实例合计(探针 RunQueueEntriesForTest 的底;类变量,释放掉的
      manager 上的调用也数得到,而且数的时候不碰那个实例)。 }
    class var FRunQueueEntries: Integer;
  private
    { 一次移动的执行(MoveWindow 同步那一支、排队项执行时),结构检查已过。同栏 = 调顺序,
      不问事件;跨栏先问 OnCanMoveWindow,AMayQueue 且要排队时排队。AIndex 已经换算好
      (MaxInt = 末尾)。接受了就取消此刻的拖动。答 False = 跨栏被否决(或处理器里释放了本
      manager)。 }
    function ExecuteMove(AWindow: TTyToolWindow; ATarget: TTyToolWindowBar; AIndex: Integer;
      AMayQueue: Boolean): Boolean;
    { --- 队列(spec §9.9)--- }
    { 追加一项;窗口和目标栏各 FreeNotification(opRemove 时 PurgeQueue);没排过就
      QueueAsyncCall 一次。 }
    procedure Enqueue(const AItem: TTyToolWindowQueued);
    { 这个窗口还有没执行的排队项(之后对它的 MoveWindow / WindowIndex 也进队列,按调用顺序)。 }
    function HasQueued(AWindow: TTyToolWindow): Boolean;
    { 删掉 Window 或 Target 是 AComponent 的项(含正在执行的那一批里还没轮到的)。 }
    procedure PurgeQueue(AComponent: TComponent);
    { 整个队列作废(排着的布局覆盖之前排队的计划和移动,spec §10.5)。 }
    procedure ClearQueue;
    { 没排过就 QueueAsyncCall(@RunQueue) 一次。 }
    procedure PostQueue;
    procedure RunQueue(Data: PtrInt);
    { 排着的 Load / Reset 执行:要跨栏移动的窗口里有捕获控件、又没再排过 → 再排一次;否则
      重新解析(排着期间窗口可能变了)再应用。 }
    procedure RunQueuedLayout(AItem: TTyToolWindowQueued);
    { 跨栏移动要排队:运行时、窗口所在窗体已经 Showing(同步换父会在窗口自己的按钮点击里
      销毁按钮的句柄,spec §9.9)。 }
    function MustQueue(AWindow: TTyToolWindow): Boolean;
    { --- 布局(spec §10) --- }
    { 可用栏按 Placement 分到三组(每组最多一条:同 Placement 的都不可用),窗口按 Controls 顺序。 }
    function BuildWorld(out ABars: TTyToolLayoutBars;
      out AWindows: TTyToolLayoutWindows): TTyToolLayoutWorld;
    { spec §10.4 的批次:取消拖动、还原最大化、按计划挪窗口 / 调顺序 / 激活 / 设尺寸和收起、
      焦点、OnLayoutApplied。不问 OnCanMoveWindow、不发 OnWindowMoved 和栏事件;窗口的
      OnShow / OnHide 照常。
      **批次中间窗口的 OnShow / OnHide 里不许释放本 manager、栏或窗口**(spec §6.6,用
      Application.ReleaseComponent):批次之后还要按计划的快照接着做,这一段不设生命格 ——
      MoveWindow / 队列 / 事件派发那几处设了(TTyToolWindowLife),处理器返回后不再碰本对象。 }
    procedure ApplyText(const ADoc: TTyToolLayoutDoc; AQueueEvent: Boolean = False);
    { --- 时机(spec §10.5) --- }
    { manager、任一注册栏、或它们的任一窗口还在 csLoading。 }
    function AnyParticipantLoading: Boolean;
    { 还没记过默认布局就记下此刻的样子。 }
    procedure EnsureDefaultCaptured;
    { 挂起计划应用后的 OnLayoutApplied,推到加载结束之后。 }
    procedure LayoutAppliedAsync(Data: PtrInt);
    { 栏所在的窗体此刻 Showing(没有注册栏答 False)。 }
    function FormShowing: Boolean;
    { Load / Reset 此刻要排队:运行时、栏所在的窗体已经 Showing。 }
    function LayoutMustQueue: Boolean;
    { Load / Reset 的共同后半段(格式已查过):加载中挂起、Showing 之后排队、否则同步应用。 }
    function StartLayout(AKind: TTyToolLayoutPending; const AText: string): Boolean;
    { Load / Reset 的门(spec §10.1):设计期、正在释放、没有注册栏答 False;从本 manager 的事件
      处理里重入、布局应用的批次里(某一页的 OnShow / OnHide)也答 False —— 跟 MoveWindow 的
      重入规则(spec §9.9)同一个理由:外层还没做完,里层按半截的状态建计划。 }
    function LayoutCallAllowed: Boolean;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    { spec §10.5:加载结束的收尾之一(另一处是栏的 Loaded)。 }
    procedure Loaded; override;
    { 代码搭的 manager:窗体 Showing 之后第一次改动布局之前记默认布局(spec §10.5)。「改动」是
      布局串里存的每一样(spec §10.2):收起、尺寸、调顺序、跨栏,还有当前页 —— 点图标换了页
      之后 Reset 也要回得去。调用方在**改之前**调。 }
    procedure NoteLayoutChanging(ABar: TTyToolWindowBar); override;
    { spec §10.5:最后一个离开 csLoading 的参与者(manager、注册栏)在自己的 Loaded 最后调它。
      都不在加载中了:记默认布局(加载进来的样子;条件见实现处),再静默应用挂起的计划,
      OnLayoutApplied 推到加载结束之后。继承窗体每一层读完都会走到这里,默认布局取最后一层
      流进来的值。
      **已知限制(继承窗体)**:祖先那一层加载中调的 Load / Reset,挂起计划在祖先层收尾时就
      应用掉了;接着读子孙层,子孙层流进来的值(ExpandedSize、Collapsed、ActiveIndex、窗口
      顺序……)照常写进去,会覆盖刚应用的布局,而计划已经清了,子孙层收尾时不会再应用一次。
      要在继承窗体上读用户布局,请在 FormCreate 里调(那时所有层都读完了)。 }
    procedure TryFinishLoading; override;
    { --- 跨栏拖动(spec §9.4 / §9.7)--- }
    { 源栏 ASource 上拖着它手势里的窗口,屏幕点 AScreen 落在哪条栏的哪个槽位:答源栏自己、
      另一侧栏,或 nil(没有目标)。每次现建探测矩形,交给 TyToolWindowDropAt。 }
    function DropTargetAt(ASource: TTyToolWindowBar; const AScreen: TPoint;
      out ASlot: Integer): TTyToolWindowBar; override;
    function QueueWindowIndex(AWindow: TTyToolWindow; AIndex: Integer): Boolean; override;
    procedure BarRemoved(ABar: TTyToolWindowBar); override;
  public
    destructor Destroy; override;
    { 把 AWindow 挪到 ATargetBar 的窗口序号 AIndex(钳住;-1 = 末尾),spec §9.9。目标就是它
      现在的栏 = 调顺序(不问事件)。返回 False、什么都不改:结构检查不过、从本 manager 的事件
      处理里重入、跨栏且 CanMoveWindow 为 False。设计期同步、不发事件、通知设计器。
      窗体已经 Showing 时跨栏移动排队(返回 True = 已接受,返回那一刻窗口还在旧栏);这个窗口
      还有排着的移动时,同栏的也进同一个队列。排队的执行前重做全部检查,不过就静默丢弃。 }
    function MoveWindow(AWindow: TTyToolWindow; ATargetBar: TTyToolWindowBar;
      AIndex: Integer = -1): Boolean;
    { 探针:队列里还有几项没执行(真实队列的长度)。 }
    function QueuedCountForTest: Integer;
    { 探针:RunQueue 被调了几次,所有实例合计(真实入口的计数;释放掉的 manager 上的调用也数)。 }
    class function RunQueueEntriesForTest: Integer;
    { spec §10.2:可用栏按 left、right、bottom 写一组(尺寸是 ExpandedSize,最大化期间也是它);
      窗口按 Controls 顺序、跳过无名和与可用栏里另一个窗口重名的(保存写出来的串必须能读回来)。
      没有可用栏时是 TYTOOLLAYOUT/1|end。 }
    function SaveLayoutToString: string;
    { spec §10.1:格式错、设计期、正在释放、没有注册栏、从事件处理里重入 → False,什么都不改;
      否则应用(一个批次)并答 True。格式错不抛异常。开头的 UTF-8 BOM 和结尾的空白(CR / LF /
      空格 / Tab)容忍(TyToolLayoutUnwrap),别处照旧严格。 }
    function LoadLayoutFromString(const AText: string): Boolean;
    { 恢复默认布局。还没记过默认布局就先记下此刻的样子。门同 LoadLayoutFromString。 }
    function ResetLayout: Boolean;
    { 把此刻的样子记成默认布局,随时覆盖。 }
    procedure CaptureDefaultLayout;
  published
    { 两侧共用的图片列表:栏自己的 Images 为空时读取时回落到它(spec §8)。只设了 ImageIndex、
      没设 ImageName 的窗口要在两侧之间移动,就得用这一份。 }
    property Images;
    property OnCanMoveWindow;
    property OnWindowMoved;
    { Load / Reset 的批次结束后一次(spec §6.6)。 }
    property OnLayoutApplied: TNotifyEvent read FOnLayoutApplied write FOnLayoutApplied;
  end;

implementation

{ manager 队列里的一项(spec §9.9)。 }
function NewQueued(AKind: TTyToolWindowQueuedKind; AWindow: TTyToolWindow;
  ATarget: TTyToolWindowBar; AIndex: Integer): TTyToolWindowQueued;
begin
  Result := Default(TTyToolWindowQueued);
  Result.Kind := AKind;
  Result.Window := AWindow;
  Result.Target := ATarget;
  Result.Index := AIndex;
end;

{ 捕获此刻在 AWindow 里:窗口里某个按钮自己的点击处理还没走完,同步换父会在里面销毁它的句柄
  (spec §9.9 / §10.5)。排队的移动和布局执行前问这一处。 }
function CaptureInside(AWindow: TTyToolWindow): Boolean;
var
  cap: TControl;
begin
  cap := GetCaptureControl;
  Result := (cap <> nil) and (AWindow <> nil)
    and ((cap = AWindow) or AWindow.ContainsControl(cap));
end;

{ --- TTyToolWindowManager -------------------------------------------------------- }

destructor TTyToolWindowManager.Destroy;
begin
  { 生命格在基类的 BeforeDestruction 里已经判死(先于任何一层析构)。
    队列里排的是本对象的方法:RemoveAsyncCalls 按方法所属的对象匹配。应用关停的后半段
    (AppDoNotCallAsyncQueue 置位之后)它会抛异常,那时队列也不会再跑了。 }
  if (Application <> nil) and not (AppDoNotCallAsyncQueue in Application.Flags) then
    Application.RemoveAsyncCalls(Self);
  FQueue := nil;
  FRunning := nil;
  FQueuePosted := False;
  { 基类的析构取消拖动。 }
  inherited Destroy;
end;

procedure TTyToolWindowManager.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  { 窗口、栏都可能在队列里(spec §9.9)。 }
  if Operation = opRemove then
    PurgeQueue(AComponent);
end;

procedure TTyToolWindowManager.BarRemoved(ABar: TTyToolWindowBar);
begin
  PurgeQueue(ABar);
end;

function TTyToolWindowManager.QueueWindowIndex(AWindow: TTyToolWindow; AIndex: Integer): Boolean;
begin
  Result := HasQueued(AWindow);
  if Result then Enqueue(NewQueued(twqIndex, AWindow, nil, AIndex));
end;

{ --- 布局(spec §10) --- }

const
  { 布局串的组和栏的 Placement 一一对应。 }
  LayoutSideOf: array[TTyToolWindowPlacement] of TTyToolLayoutSide = (tlsLeft, tlsRight, tlsBottom);

function TTyToolWindowManager.BuildWorld(out ABars: TTyToolLayoutBars;
  out AWindows: TTyToolLayoutWindows): TTyToolLayoutWorld;
var
  i, k: Integer;
  b: TTyToolWindowBar;
  side: TTyToolLayoutSide;
begin
  Result := Default(TTyToolLayoutWorld);
  for side := Low(TTyToolLayoutSide) to High(TTyToolLayoutSide) do
  begin
    ABars[side] := nil;
    AWindows[side] := nil;
    Result[side].Active := -1;
  end;
  for i := 0 to High(FBars) do
  begin
    b := FBars[i];
    if not IsBarUsable(b) then Continue;
    side := LayoutSideOf[b.Placement];
    ABars[side] := b;
    AWindows[side] := BarWindows(b);
    Result[side].Usable := True;
    SetLength(Result[side].Names, Length(AWindows[side]));
    for k := 0 to High(AWindows[side]) do
      Result[side].Names[k] := AWindows[side][k].Name;
    Result[side].Active := b.IndexOfWindow(b.ActiveWindow);
  end;
end;

function TTyToolWindowManager.SaveLayoutToString: string;
var
  bars: TTyToolLayoutBars;
  wins: TTyToolLayoutWindows;
  world: TTyToolLayoutWorld;
  doc: TTyToolLayoutDoc;
  side, other: TTyToolLayoutSide;
  k, j, n: Integer;
  nm: string;
  dup: Boolean;
begin
  world := BuildWorld(bars, wins);
  doc := Default(TTyToolLayoutDoc);
  for side := Low(TTyToolLayoutSide) to High(TTyToolLayoutSide) do
  begin
    if bars[side] = nil then Continue;
    doc[side].Present := True;
    { 最大化期间也是还原高度(spec §10.2 / §10.7)。 }
    doc[side].Size := bars[side].ExpandedSize;
    doc[side].Collapsed := bars[side].Collapsed;
    for k := 0 to High(wins[side]) do
    begin
      nm := wins[side][k].Name;
      if nm = '' then Continue;
      { 与可用栏里另一个窗口重名(CompareText):写出来读的时候会被当成重复拒掉整串(spec §10.2
        「保存写出来的串必须能读回来」;判重的范围 = 读取时按名字找的范围,即所有可用栏)。 }
      dup := False;
      for other := Low(TTyToolLayoutSide) to High(TTyToolLayoutSide) do
        for j := 0 to High(world[other].Names) do
          if ((other <> side) or (j <> k)) and (CompareText(world[other].Names[j], nm) = 0) then
            dup := True;
      if dup then Continue;
      n := Length(doc[side].Names);
      SetLength(doc[side].Names, n + 1);
      doc[side].Names[n] := nm;
      if wins[side][k] = bars[side].ActiveWindow then doc[side].Active := nm;
    end;
  end;
  Result := TyToolLayoutFormat(doc);
end;

function TTyToolWindowManager.LayoutCallAllowed: Boolean;
begin
  { FApplying:批次里某一页的 OnShow / OnHide 再调 Load / Reset —— 里层批次按外层还没做完的
    样子建计划,外层接着按自己那份计划(窗口快照)做,两份计划叠在一起。 }
  Result := ([csDesigning, csDestroying] * ComponentState = []) and (Length(FBars) > 0)
    and (FEventDepth = 0) and (FApplying = 0);
end;

function TTyToolWindowManager.FormShowing: Boolean;
var
  form: TCustomForm;
begin
  Result := False;
  if Length(FBars) = 0 then Exit;
  form := GetParentForm(FBars[0]);
  Result := (form <> nil) and form.Showing;
end;

function TTyToolWindowManager.LayoutMustQueue: Boolean;
begin
  Result := not (csDesigning in ComponentState) and FormShowing;
end;

{ Load / Reset 的共同后半段(格式已经查过):加载中挂起;Showing 之后排队;否则同步应用。 }
function TTyToolWindowManager.StartLayout(AKind: TTyToolLayoutPending; const AText: string): Boolean;
var
  item: TTyToolWindowQueued;
  doc: TTyToolLayoutDoc;
begin
  Result := True;
  { 接受了的调用在入口就取消此刻的拖动(spec §9.7):排队的那一份要等抽消息才应用,这段时间里
    用户不该还拖着一个马上要被挪走的窗口。同步的那一份 ApplyText 第 1 步还会再取消一次(幂等)。 }
  CancelDrag;
  { 加载中(frame、继承窗体、Loaded 里调的):存成唯一的挂起计划,最后一个 Loaded 应用。 }
  if AnyParticipantLoading then
  begin
    FPendingKind := AKind;
    FPendingText := AText;
    Exit;
  end;
  { 还没记过默认布局就记下此刻的样子(spec §10.5),在排队 / 应用之前:FormCreate 里搭好之后
    第一次 Load / Reset,记下的就是搭好的样子;Showing 之后才第一次调的,此刻就是用户一直看着的
    样子(那之前的每一次改动都会先经 NoteLayoutChanging 记)。排队的也在这里记,不等执行 ——
    执行时已经是排着期间又改过的样子。 }
  EnsureDefaultCaptured;
  if LayoutMustQueue then
  begin
    { 同步应用会在窗口里的按钮自己的点击里销毁它的句柄(「恢复布局」按钮放在操作区里)。
      覆盖之前排队的计划和移动。 }
    ClearQueue;
    item := NewQueued(twqLayout, nil, nil, 0);
    item.Text := AText;
    item.IsReset := AKind = tlpReset;
    Enqueue(item);
    Exit;
  end;
  if AKind = tlpReset then
    Result := TyToolLayoutParse(FDefaultText, doc)
  else
    Result := TyToolLayoutParse(AText, doc);
  if Result then ApplyText(doc);
end;

function TTyToolWindowManager.LoadLayoutFromString(const AText: string): Boolean;
var
  doc: TTyToolLayoutDoc;
  text: string;
begin
  { 存储层带进来的外壳(开头的 BOM、结尾的换行和空白:TStringList.Text、读回来的文件)先去掉,
    中间照旧严格。格式先查(加载中也立即查,spec §10.5)。 }
  text := TyToolLayoutUnwrap(AText);
  Result := LayoutCallAllowed and TyToolLayoutParse(text, doc);
  if Result then Result := StartLayout(tlpLoad, text);
end;

procedure TTyToolWindowManager.CaptureDefaultLayout;
begin
  { 批次里(某一页的 OnShow / OnHide)记下的是应用了一半的样子。 }
  if FApplying > 0 then Exit;
  FDefaultText := SaveLayoutToString;
  FDefaultCaptured := True;
  FDefaultExplicit := True;
end;

procedure TTyToolWindowManager.EnsureDefaultCaptured;
begin
  if FDefaultCaptured then Exit;
  FDefaultText := SaveLayoutToString;
  FDefaultCaptured := True;
end;

function TTyToolWindowManager.ResetLayout: Boolean;
begin
  Result := LayoutCallAllowed and StartLayout(tlpReset, '');
end;

function TTyToolWindowManager.AnyParticipantLoading: Boolean;
var
  i, k: Integer;
begin
  Result := True;
  if csLoading in ComponentState then Exit;
  for i := 0 to High(FBars) do
  begin
    if csLoading in FBars[i].ComponentState then Exit;
    for k := 0 to FBars[i].ControlCount - 1 do
      if csLoading in FBars[i].Controls[k].ComponentState then Exit;
  end;
  Result := False;
end;

procedure TTyToolWindowManager.NoteLayoutChanging(ABar: TTyToolWindowBar);
var
  form: TCustomForm;
begin
  if FDefaultCaptured or (FApplying > 0) or (ABar = nil) then Exit;
  if [csLoading, csDesigning, csDestroying] * (ComponentState + ABar.ComponentState) <> [] then
    Exit;
  { 窗体第一次 Showing 之前的改动算搭建(spec §10.5)。 }
  form := GetParentForm(ABar);
  if (form = nil) or not form.Showing then Exit;
  EnsureDefaultCaptured;
end;

procedure TTyToolWindowManager.Loaded;
begin
  inherited Loaded;
  TryFinishLoading;
end;

procedure TTyToolWindowManager.TryFinishLoading;
var
  kind: TTyToolLayoutPending;
  text: string;
  doc: TTyToolLayoutDoc;
  bars: array of TTyToolWindowBar;
  i: Integer;
begin
  if AnyParticipantLoading or ([csDesigning, csDestroying] * ComponentState <> []) then Exit;
  { 默认布局 = 流进来的值(LCL 先读完所有流、解析完所有引用,才开始第一个 Loaded,各 Loaded
    的先后不影响)。继承窗体每一层都走到这里,取最后一层的(那时窗体都还没显示);用户自己
    记过的(CaptureDefaultLayout)不动。另外两种情形不记:
    - 还没有注册栏(.lfm 里只有 manager,栏在 FormCreate 里用代码挂):记下的是空布局,之后
      Reset 什么都恢复不了。不置「记过」,代码搭的那一套照代码搭的规矩记(第一次 Load / Reset
      之前、Showing 之后第一次改动之前)。
    - 窗体已经显示着、默认布局也记过了(显示之后运行时建了一个带栏、指向本 manager 的
      frame):那一份是用户看见过、可能已经改过之后记的,新加进来的栏不该把它覆盖掉。
      没记过就照记。 }
  if not FDefaultExplicit and (Length(FBars) > 0)
     and (not FDefaultCaptured or not FormShowing) then
  begin
    FDefaultText := SaveLayoutToString;
    FDefaultCaptured := True;
  end;
  kind := FPendingKind;
  if kind = tlpNone then Exit;
  text := FPendingText;
  { 应用之前就清:计划只应用一次。应用中途抛异常(某条栏进批次失败、重排里用户的 OnResize
    抛……)这份计划就丢了,不留到下一次收尾再试 —— 下一次(继承窗体的下一层)时窗口已经是
    另一个样子,半截的计划再应用一遍只会更乱。 }
  FPendingKind := tlpNone;
  FPendingText := '';
  { Reset 用的是刚记下的默认布局。 }
  if kind = tlpReset then text := FDefaultText;
  if not TyToolLayoutParse(text, doc) then Exit;
  { 这时窗体的 OnCreate 还没跑:批次内一个用户事件都不发(连 OnShow / OnHide),视同流式加载。 }
  bars := Copy(FBars);
  for i := 0 to High(bars) do BarBeginSilent(bars[i]);
  try
    ApplyText(doc, True);
  finally
    for i := High(bars) downto 0 do BarEndSilent(bars[i]);
  end;
end;

procedure TTyToolWindowManager.LayoutAppliedAsync(Data: PtrInt);
var
  life: TTyToolWindowLife;
begin
  if not Assigned(FOnLayoutApplied) then Exit;
  EnterEvent(life);
  try
    FOnLayoutApplied(Self);
  finally
    LeaveEvent(life);
  end;
end;

procedure TTyToolWindowManager.RunQueuedLayout(AItem: TTyToolWindowQueued);
var
  text: string;
  doc: TTyToolLayoutDoc;
  bars: TTyToolLayoutBars;
  wins: TTyToolLayoutWindows;
  plan: TTyToolLayoutPlan;
  side: TTyToolLayoutSide;
  k: Integer;
  w: TTyToolWindow;
begin
  if not LayoutCallAllowed then Exit;
  if AItem.IsReset then text := FDefaultText else text := AItem.Text;
  if not TyToolLayoutParse(text, doc) then Exit;
  { 捕获在某个要跨栏移动的窗口里(按钮自己的点击处理还没走完):再排一次,只一次。
    没有捕获就不建计划。 }
  if (GetCaptureControl <> nil) and not AItem.Requeued then
  begin
    plan := TyToolLayoutPlanFor(BuildWorld(bars, wins), doc);
    for side := Low(TTyToolLayoutSide) to High(TTyToolLayoutSide) do
      for k := 0 to High(plan[side].Order) do
      begin
        if plan[side].Order[k].Side = side then Continue;
        w := wins[plan[side].Order[k].Side][plan[side].Order[k].Index];
        if CaptureInside(w) then
        begin
          AItem.Requeued := True;
          AItem.Dead := False;
          Enqueue(AItem);
          Exit;
        end;
      end;
  end;
  ApplyText(doc);
end;

procedure TTyToolWindowManager.ApplyText(const ADoc: TTyToolLayoutDoc; AQueueEvent: Boolean);
var
  bars: TTyToolLayoutBars;
  wins: TTyToolLayoutWindows;
  plan: TTyToolLayoutPlan;
  touched: array of TTyToolWindowBar;
  form: TCustomForm;
  focus: TWinControl;
  focusWin, w, target: TTyToolWindow;
  b: TTyToolWindowBar;
  side: TTyToolLayoutSide;
  i, k, entered: Integer;
begin
  { 1. 取消拖动。 }
  CancelDrag;
  { 2. 最大化的底栏先还原(spec §10.4 第 2 步)。 }
  for i := 0 to High(FBars) do
    if FBars[i].Placement = twpBottom then FBars[i].Maximized := False;
  { 3. 记下焦点控件,以及它原来在哪个工具窗口里。 }
  form := nil;
  if Length(FBars) > 0 then form := GetParentForm(FBars[0]);
  if form <> nil then focus := form.ActiveControl else focus := nil;
  focusWin := nil;
  if focus <> nil then
    for i := 0 to High(FBars) do
      for k := 0 to FBars[i].WindowCount - 1 do
        if FBars[i].Windows[k].ContainsControl(focus) then focusWin := FBars[i].Windows[k];
  { 4. 计划;所有注册栏进批次、停对齐。 }
  plan := TyToolLayoutPlanFor(BuildWorld(bars, wins), ADoc);
  touched := Copy(FBars);
  entered := 0;
  Inc(FApplying);
  try
    try
      { 进了门的才出门:第 k 条进门时抛异常,finally 只还前 k 条 —— 按数组长度还的话,没进门的
        那几条会多解一层对齐锁;而进门写在 try 外面的话,前 k 条从此停着对齐、批次层数卡在 1。 }
      for i := 0 to High(touched) do
      begin
        BarEnterBatch(touched[i]);
        entered := i + 1;
      end;
      { 5a. 窗口挪到各自的栏(静默换父:不走直接改 Parent 的簿记、不注册即激活)。 }
      for side := Low(TTyToolLayoutSide) to High(TTyToolLayoutSide) do
      begin
        b := bars[side];
        if b = nil then Continue;
        for k := 0 to High(plan[side].Order) do
        begin
          w := wins[plan[side].Order[k].Side][plan[side].Order[k].Index];
          if w.Parent = b then Continue;
          QuietReparent(w, b);
        end;
      end;
      { 5b. 顺序、尺寸、收起、当前页。收起的栏先收起再切页(不显示任何一页);展开的先切页再
        展开(只显示新的当前页一次)—— 哪一种都不会让一页先显示再藏掉。 }
      for side := Low(TTyToolLayoutSide) to High(TTyToolLayoutSide) do
      begin
        b := bars[side];
        if b = nil then Continue;
        for k := 0 to High(plan[side].Order) do
          BarPlace(b, wins[plan[side].Order[k].Side][plan[side].Order[k].Index], k);
        if plan[side].Active >= 0 then
          target := wins[plan[side].Order[plan[side].Active].Side]
            [plan[side].Order[plan[side].Active].Index]
        else
          target := nil;
        if plan[side].Apply then b.ExpandedSize := plan[side].Size;
        if plan[side].Apply and plan[side].Collapsed then b.Collapsed := True;
        { 切页走 SwitchCore(不是 ActivateWindow):目标就是此刻的当前页时,带着 Visible 挪进来的
          别的窗口照样要藏起来。批次里它不挪焦点。
          目标已经不在这条栏里:前面某一页的 OnShow 里用户直接改了它的 Parent(MoveWindow / Load
          在批次里答 False,直接改 Parent 拦不住)—— 不切,切过去等于让本栏的当前页是别的栏的窗口。 }
        if (target = nil) or (b.IndexOfWindow(target) >= 0) then
          BarSwitch(b, target);
        if plan[side].Apply and not plan[side].Collapsed then b.Collapsed := False;
      end;
    finally
      { 6. 倒序恢复对齐、出批次。 }
      for i := entered - 1 downto 0 do
        BarLeaveBatch(touched[i]);
    end;
  finally
    Dec(FApplying);
  end;
  { 7. 焦点(spec §10.4 第 7 步):原控件还聚焦得上就还给它;否则它原来所在的窗口现在在哪条栏,
    那条栏收起了或者没有能聚焦的当前页就交给 Tab 顺序里栏后面那一个,展开着就进当前页的正文。
    原控件不在任何工具窗口里就不动。
    窗体还没显示(FormCreate 里读布局)时这一步照做,而且安全:
    - 被藏起来的控件不会留在 ActiveControl 上 —— 窗口藏起来、换父那一下 LCL 自己 RemoveFocus
      清掉了(wincontrol.inc:8418-8420、6438);
    - SelectNext / FocusFirst 在看不见的窗体上挑不到任何控件(FindNextControl 要 IsVisible,
      wincontrol.inc:4658-4661),也就走不到会抛异常的 SetFocus → TCustomForm.SetFocus;
    - 原控件还聚焦得上(跟着窗口挪到别的栏、仍是当前页)时把 ActiveControl 还给它 —— 换父时
      LCL 已经把它清了,不还的话窗体显示时焦点落到别处。 }
  if (form <> nil) and (focus <> nil) then
  begin
    if focus.CanFocus then
    begin
      if form.ActiveControl <> focus then form.ActiveControl := focus;
    end
    else if (focusWin <> nil) and (focusWin.Bar <> nil) then
    begin
      b := focusWin.Bar;
      if b.Collapsed or (b.ActiveWindow = nil) or not b.ActiveWindow.CanFocus then
        form.SelectNext(b, True, True)
      else
        b.ActiveWindow.FocusFirst;
    end;
  end;
  { 8. 一次 OnLayoutApplied;处理器里再调 Load / Reset / MoveWindow 答 False。挂起计划在
    加载结束时应用,那时窗体的 OnCreate 还没跑:推到之后(spec §10.4)。 }
  if AQueueEvent then
    Application.QueueAsyncCall(@LayoutAppliedAsync, 0)
  else
    LayoutAppliedAsync(0);
end;

{ --- 跨栏拖动的命中测试(spec §9.4) --- }

{ 控件客户区的屏幕矩形。没有句柄时 ClientToScreen 是父链 Left / Top 的累加,同一窗体上的
  栏互相换算照样一致。 }
function ClientScreenRect(AControl: TWinControl): TRect;
var
  p: TPoint;
begin
  p := AControl.ClientToScreen(Point(0, 0));
  Result := Rect(p.X, p.Y, p.X + AControl.ClientWidth, p.Y + AControl.ClientHeight);
end;

{ spec §9.4:栏的 ClientRect 与每一级祖先 ClientRect 的交集(屏幕坐标)。 }
function VisibleScreenRect(AControl: TWinControl): TRect;
var
  p: TWinControl;
begin
  Result := ClientScreenRect(AControl);
  p := AControl.Parent;
  while p <> nil do
  begin
    Types.IntersectRect(Result, Result, ClientScreenRect(p));
    p := p.Parent;
  end;
end;

{ spec §9.4 的「IsVisible」,只看到顶层窗体为止:拖动的时候源栏所在的顶层窗体一定显示着,两边
  同一个顶层窗体(GetParentForm 默认答顶层的),那一级对两边一样。(IsVisible 把窗体也算进去,
  无头的窗体永远不可见。)嵌在别的控件里的窗体(Parent <> nil)不是那一级:它自己藏着,里面的栏
  就看不见,照样往上查。 }
function VisibleInForm(AControl: TControl): Boolean;
var
  c: TControl;
begin
  c := AControl;
  while (c <> nil) and not ((c is TCustomForm) and (c.Parent = nil)) do
  begin
    if not c.IsControlVisible then Exit(False);
    c := c.Parent;
  end;
  Result := True;
end;

{ 嵌在 AParent 里面、看得见的别的栏(递归,嵌套栏里面的不再往下找):落在它们上面的点不算
  AParent 这个候选。 }
procedure CollectNestedBars(AParent: TWinControl; var AHoles: TTyToolWindowRects);
var
  i: Integer;
  c: TControl;
begin
  for i := 0 to AParent.ControlCount - 1 do
  begin
    c := AParent.Controls[i];
    if not (c is TWinControl) then Continue;
    if c is TTyToolWindowBar then
    begin
      if VisibleInForm(c) then
      begin
        SetLength(AHoles, Length(AHoles) + 1);
        AHoles[High(AHoles)] := ClientScreenRect(TWinControl(c));
      end;
    end
    else
      CollectNestedBars(TWinControl(c), AHoles);
  end;
end;

{ 一条栏的探测矩形(屏幕坐标)。IsSource / Allowed 由调用方填。 }
function DropProbeOf(ABar: TTyToolWindowBar): TTyToolWindowDropProbe;
var
  L: TTyToolWindowBarLayout;
  o: TPoint;
  holes: TTyToolWindowRects;
  i: Integer;
begin
  Result := Default(TTyToolWindowDropProbe);
  Result.Visible := VisibleScreenRect(ABar);
  holes := nil;
  CollectNestedBars(ABar, holes);
  Result.Holes := holes;
  L := ABar.BarLayout;
  o := ABar.ClientToScreen(Point(0, 0));
  Result.Cells := L.Cells;
  Types.OffsetRect(Result.Cells, o.X, o.Y);
  Result.Slots := Copy(L.Slots);
  for i := 0 to High(Result.Slots) do
    Types.OffsetRect(Result.Slots[i].ItemRect, o.X, o.Y);
  Result.Count := ABar.WindowCount;
end;

function TTyToolWindowManager.DropTargetAt(ASource: TTyToolWindowBar; const AScreen: TPoint;
  out ASlot: Integer): TTyToolWindowBar;
var
  probes: TTyToolWindowDropProbes;
  bars: array of TTyToolWindowBar;
  form: TCustomForm;
  hit: TControl;
  b: TTyToolWindowBar;
  i, n: Integer;
begin
  Result := nil;
  ASlot := -1;
  form := GetParentForm(ASource);
  { 非模态浮动窗体盖在上面(spec §9.4):有句柄时问 LCL 这一点上是谁;nil 就信几何。 }
  if ASource.HandleAllocated then
  begin
    hit := FindControlAtPosition(AScreen, True);
    if (hit <> nil) and (GetParentForm(hit) <> form) then Exit;
  end;
  { 源栏永远是第一个候选(栏内调顺序,冲突不冲突都一样)。 }
  probes := nil;
  bars := nil;
  SetLength(probes, 1);
  SetLength(bars, 1);
  probes[0] := DropProbeOf(ASource);
  probes[0].IsSource := True;
  bars[0] := ASource;
  { 源栏自己冲突时不再找别的候选(spec §9.4)。禁用的侧栏不是放置目标:MoveWindow 这个 API
    照常可用,只是拖放不往用户看着是灰的栏里放(spec §9.4 候选栏要 IsVisible;禁用同理 ——
    图标条画成 :disabled,落上去却挪得进去,用户会以为是 bug)。「可用」「同一个窗体」两条
    CanMoveWindow 的结构检查(DragAllows)也会拒,这里先筛掉,不为不可能的目标建探测矩形。 }
  if IsBarUsable(ASource) then
    for i := 0 to High(FBars) do
    begin
      b := FBars[i];
      if (b = ASource) or (b.Placement = twpBottom) or not IsBarUsable(b)
         or not VisibleInForm(b) or not b.IsEnabled or (csDestroying in b.ComponentState)
         or (GetParentForm(b) <> form) then Continue;
      n := Length(probes);
      SetLength(probes, n + 1);
      SetLength(bars, n + 1);
      probes[n] := DropProbeOf(b);
      { 先不问:命中哪一条再只问那一条(下面)。 }
      probes[n].Allowed := True;
      bars[n] := b;
    end;
  i := TyToolWindowDropAt(probes, AScreen, ASlot);
  { 只问命中的那一条(每条每次手势只问一次,引擎缓存):指针落在嵌套栏的洞里、源栏上、别处时
    一条都不问 —— 按「指针在不在它的可见矩形里」问的话,洞里、叠在上面的源栏上都会去问底下那条。
    问完之后手势可能已经被处理器收尾了,由调用方看引擎的状态;这里之后不再碰 Self。 }
  if (i > 0) and not DragAllows(ASource, bars[i]) then i := -1;
  if i >= 0 then Result := bars[i] else ASlot := -1;
end;

{ --- MoveWindow 与队列(spec §9.9) --- }

function TTyToolWindowManager.MoveWindow(AWindow: TTyToolWindow; ATargetBar: TTyToolWindowBar;
  AIndex: Integer): Boolean;
var
  src: TTyToolWindowBar;
begin
  Result := False;
  { 从本 manager 的事件处理里重入(spec §9.9);布局应用的批次里(某一页的 OnShow / OnHide)也一样:
    批次按自己的窗口快照做,中途被挪走的窗口会让它把别的栏的窗口当成本栏的当前页。 }
  if (FEventDepth > 0) or (FApplying > 0) then Exit;
  if not StructureAllows(AWindow, ATargetBar, src) then Exit;
  { -1 = 末尾(PlaceWindow / ReorderWindow 钳到 N-1)。只在入口换算这一次:排着的项执行时、
    MoveNow 里都拿换算过的值。 }
  if AIndex < 0 then AIndex := MaxInt;
  { 这个窗口还有排着的移动:这一次(同栏也算)排在它后面,按调用顺序执行。执行时重新检查。
    接受了的调用在入口就取消此刻的拖动(spec §9.7),排队的、同栏调顺序的也一样 —— 等到排队项
    执行时才取消的话,这段时间里用户还拖着一个马上要被挪走的窗口。 }
  if HasQueued(AWindow) then
  begin
    CancelDrag;
    Enqueue(NewQueued(twqMove, AWindow, ATargetBar, AIndex));
    Exit(True);
  end;
  Result := ExecuteMove(AWindow, ATargetBar, AIndex, True);
end;

function TTyToolWindowManager.ExecuteMove(AWindow: TTyToolWindow; ATarget: TTyToolWindowBar;
  AIndex: Integer; AMayQueue: Boolean): Boolean;
var
  src: TTyToolWindowBar;
  life: TTyToolWindowLife;
begin
  src := AWindow.Bar;
  if src = ATarget then
  begin
    { 同一条栏就是调顺序:同步(不重建句柄),不问事件。 }
    CancelDrag;
    BarReorder(src, AWindow, AIndex);
    Exit(True);
  end;
  EnterLife(life);
  try
    Result := CanMoveWindow(AWindow, ATarget);
    { OnCanMoveWindow 里把本 manager 释放了:到此为止,不再碰任何成员。 }
    Result := Result and life.Alive;
    if not Result then Exit;
    CancelDrag;
    if AMayQueue and MustQueue(AWindow) then
      Enqueue(NewQueued(twqMove, AWindow, ATarget, AIndex))
    else
      MoveNow(AWindow, ATarget, AIndex);
  finally
    LeaveLife(life);
  end;
end;

function TTyToolWindowManager.QueuedCountForTest: Integer;
begin
  Result := Length(FQueue);
end;

class function TTyToolWindowManager.RunQueueEntriesForTest: Integer;
begin
  Result := FRunQueueEntries;
end;

function TTyToolWindowManager.MustQueue(AWindow: TTyToolWindow): Boolean;
var
  form: TCustomForm;
begin
  Result := False;
  if csDesigning in ComponentState then Exit;
  form := GetParentForm(AWindow);
  Result := (form <> nil) and form.Showing;
end;

procedure TTyToolWindowManager.PostQueue;
begin
  if FQueuePosted then Exit;
  FQueuePosted := True;
  Application.QueueAsyncCall(@RunQueue, 0);
end;

procedure TTyToolWindowManager.Enqueue(const AItem: TTyToolWindowQueued);
begin
  SetLength(FQueue, Length(FQueue) + 1);
  FQueue[High(FQueue)] := AItem;
  if AItem.Window <> nil then AItem.Window.FreeNotification(Self);
  if AItem.Target <> nil then AItem.Target.FreeNotification(Self);
  PostQueue;
end;

function TTyToolWindowManager.HasQueued(AWindow: TTyToolWindow): Boolean;
var
  i: Integer;
begin
  Result := False;
  if AWindow = nil then Exit;
  for i := 0 to High(FQueue) do
    if FQueue[i].Window = AWindow then Exit(True);
  for i := 0 to High(FRunning) do
    if not FRunning[i].Dead and (FRunning[i].Window = AWindow) then Exit(True);
end;

procedure TTyToolWindowManager.PurgeQueue(AComponent: TComponent);
var
  i: Integer;
begin
  if AComponent = nil then Exit;
  for i := High(FQueue) downto 0 do
    if (FQueue[i].Window = AComponent) or (FQueue[i].Target = AComponent) then
      Delete(FQueue, i, 1);
  { 正在执行的那一批:还没轮到的项作废。 }
  for i := 0 to High(FRunning) do
    if (FRunning[i].Window = AComponent) or (FRunning[i].Target = AComponent) then
    begin
      FRunning[i].Dead := True;
      FRunning[i].Window := nil;
      FRunning[i].Target := nil;
    end;
end;

procedure TTyToolWindowManager.ClearQueue;
var
  i: Integer;
begin
  FQueue := nil;
  for i := 0 to High(FRunning) do
    FRunning[i].Dead := True;
end;

procedure TTyToolWindowManager.RunQueue(Data: PtrInt);
const
  Busy = [csLoading, csDestroying];
var
  it: TTyToolWindowQueued;
  src: TTyToolWindowBar;
  i: Integer;
  life: TTyToolWindowLife;
begin
  Inc(FRunQueueEntries);
  FQueuePosted := False;
  { 执行中有人抽消息(处理器里弹了模态框……)、又跑到这里:这一批还没完。不在这里重排 —— 重排的
    那一次在下一轮抽消息里又进来、又重排,模态框的消息循环就一直空转;外层跑完自己补排。 }
  if FRunning <> nil then Exit;
  FRunning := FQueue;
  FQueue := nil;
  EnterLife(life);
  try
    for i := 0 to High(FRunning) do
    begin
      it := FRunning[i];
      if it.Dead then Continue;                        { 执行中被 PurgeQueue 作废了 }
      FRunning[i].Dead := True;                        { 轮到了:不再算「还排着」 }
      case it.Kind of
        twqLayout:
          RunQueuedLayout(it);
        twqMove:
          { 捕获还在窗口里(按钮自己的点击处理还没走完):再排一次,只一次。 }
          if CaptureInside(it.Window) and not it.Requeued then
          begin
            it.Requeued := True;
            Enqueue(it);
          end
          { 排着期间什么都可能变了:重做全部检查,不过就静默丢弃(不发事件)。 }
          else if StructureAllows(it.Window, it.Target, src) then
            ExecuteMove(it.Window, it.Target, it.Index, False);
        twqIndex:
          { 同 StructureAllows:窗口、它的栏、本 manager 都不在加载 / 释放中。 }
          if (it.Window.Bar <> nil)
             and (Busy * (ComponentState + it.Window.ComponentState
                          + it.Window.Bar.ComponentState) = []) then
            BarReorder(it.Window.Bar, it.Window, it.Index);
      end;
      { 某个处理器里把本 manager 释放了(spec §6.6 不许):立即退出,一个成员都不再碰。 }
      if not life.Alive then Exit;
    end;
  finally
    if life.Alive then
    begin
      LeaveLife(life);
      FRunning := nil;
      { 执行中排进来的(再排的、处理器里新调的):这一批跑完,补排一轮。 }
      if FQueue <> nil then PostQueue;
    end;
  end;
end;

initialization
  { 运行时 .lfm 按类名实例化流里的组件。 }
  RegisterClass(TTyToolWindowManager);
end.
