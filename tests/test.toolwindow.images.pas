unit test.toolwindow.images;
{$mode objfpc}{$H+}

{ 栏的图片列表与窗口图标的解析(spec §8):名字是持久键、序号是它的视图;挂起的序号只在
  栏的 Loaded 里解析;换列表先注销旧的;列表被释放 / 被摘走时清引用;运行时改图标 / 提示
  要让栏重画;图标条提示用 StripHint,空了用 Caption,不用 Hint。
  绘制(着色)和 CM_HINTSHOW 在 test.toolwindow.strip。

  几条「旧列表不许还挂着 link」的测试,先用一个不会卡死的判据(旧列表的变更不再到栏),
  判据红了就**故意泄漏**那几个列表再 Fail —— 它们的析构会死循环(imglist.inc:1692-1698),
  释放它们就是把一条红测试变成挂死的整个套件。只有这一个判据红才泄漏;别的断言失败照常
  在 finally 里释放。判据绿了才真的释放,释放得完就是第二道证据。 }

interface

uses
  Classes, SysUtils, Types, TypInfo, Controls, Graphics, Forms, ImgList, fpcunit, testregistry,
  tyControls.Controller, tyControls.ToolWindows, tyControls.Icons.Lucide,
  test.toolwindow.bar;

type
  { 探针:数「栏被请求重画了几次」,记下「被通知了谁的 opRemove」,并开出流式加载的两个入口。 }
  TImagesBar = class(TTyToolWindowBar)
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    InvalidateCount: Integer;
    { 为真时析构不还内存:清零后留成尸体(Corpse),由测试稍后 FreeMem。死对象上的调用
      因此必然 AV —— 还了的内存可能原样留着 csDestroying,悬空回调就静悄悄地什么也不做。 }
    class var KeepCorpse: Boolean;
    class var Corpse: Pointer;
    { 设了 Watched,它的 opRemove 到栏时 WatchedRemoved 置真。 }
    Watched: TComponent;
    WatchedRemoved: Boolean;
    procedure Invalidate; override;
    procedure BeginLoad;
    procedure EndLoad;
    procedure FreeInstance; override;
    procedure CallRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  { 在栏**之前**收到任意组件的 opRemove(后登记的先到),那一刻看栏的生效列表。 }
  TAnyFreeWatcher = class(TComponent)
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    Bar: TTyToolWindowBar;
    Target: TComponent;
    Called: Boolean;
    SeenEffective: TCustomImageList;
  end;

  { 开出 protected 的 MarkAsChanged。 }
  TImageListAccess = class(TCustomImageList);

  { 在栏**之前**收到列表的 opRemove(FreeNotification 表倒序通知,后登记的先到),
    那一刻看栏的生效列表。 }
  TFreeWatcher = class(TComponent)
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    Bar: TTyToolWindowBar;
    Called: Boolean;
    SeenEffective: TCustomImageList;
  end;

  TTyToolWindowImagesTests = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FBar: TImagesBar;
    function NewList(AOwner: TComponent; const ANames: string): TTyLucideImageList;
    function NewWindow: TTyToolWindow;
    { 列表 AList 的一次变更有没有到栏(link 还挂不挂在它身上)。 }
    function ChangeReachesBar(AList: TCustomImageList): Boolean;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheIndexIsATImageIndexAndTheBarPublishesImages;
    procedure TestImageNameResolvesAgainstTheBarsList;
    procedure TestTheIndexIsTheKeyWhenThereIsNoName;
    procedure TestAPendingIndexResolvesInLoadedNotWhileLoading;
    procedure TestAnIndexWaitsForAListAndALaterNameWins;
    procedure TestSwappingTheListUnsubscribesTheOldOneFirst;
    procedure TestFreeingTheSubscribedListClearsTheReference;
    procedure TestAListTakenFromItsOwnerIsUnsubscribed;
    procedure TestAListChangeRepaintsTheStrip;
    procedure TestSwappingTheListDropsTheOldFreeNotification;
    procedure TestAListBeingFreedIsNoLongerEffective;
    procedure TestFreeingTheBarUnhooksItFromALiveList;
    procedure TestAnIndexChangeRepaintsEvenWithoutANameToChange;
    procedure TestRunTimeIconAndHintChangesRepaintTheBar;
    procedure TestStripHintFallsBackToCaptionNeverToHint;
    { spec §8:栏自己没有列表时读取时回落到 Manager.Images。 }
    procedure TestABarWithoutAListReadsTheManagers;
    procedure TestTheFallbackListPaintsTheStrip;
    procedure TestTheBarsOwnListWinsOverTheManagers;
    procedure TestAPendingIndexResolvesWhenTheManagerGetsAList;
    procedure TestSwappingTheManagersListResubscribes;
    procedure TestFreeingTheManagersListLeavesNoEffectiveList;
    procedure TestFreeingTheManagerUnsubscribesItsList;
    procedure TestLeavingTheManagerUnsubscribesItsList;
    procedure TestAManagerBeingFreedIsNoFallback;
  end;

implementation

const
  { 两份同名不同序的列表:按序号解析到哪一份,名字就不一样。 }
  HouseFolder = 'house' + LineEnding + 'folder';
  FolderHouse = 'folder' + LineEnding + 'house';

procedure TImagesBar.Invalidate;
begin
  Inc(InvalidateCount);
  inherited Invalidate;
end;

procedure TImagesBar.BeginLoad;
begin
  Loading;
end;

procedure TImagesBar.EndLoad;
begin
  Loaded;
end;

procedure TImagesBar.Notification(AComponent: TComponent; Operation: TOperation);
begin
  if (Operation = opRemove) and (Watched <> nil) and (AComponent = Watched) then
    WatchedRemoved := True;
  inherited Notification(AComponent, Operation);
end;

procedure TImagesBar.FreeInstance;
begin
  if not KeepCorpse then
  begin
    inherited FreeInstance;
    Exit;
  end;
  CleanupInstance;
  FillChar(Pointer(Self)^, InstanceSize, 0);   { VMT 也清成 nil:任何虚调用都 AV }
  Corpse := Pointer(Self);
end;

procedure TImagesBar.CallRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TAnyFreeWatcher.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = Target) and (Bar <> nil) then
  begin
    Called := True;
    SeenEffective := Bar.EffectiveImages;
  end;
end;

procedure TFreeWatcher.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent is TCustomImageList) and (Bar <> nil) then
  begin
    Called := True;
    SeenEffective := Bar.EffectiveImages;
  end;
end;

{ 外来的 LCL 列表(没有名字),里面放 ACount 张 16×16 的图:序号在界内,
  换不成名字只因为它是外来的。 }
function NewForeignList(AOwner: TComponent; ACount: Integer): TImageList;
var
  bmp: TBitmap;
  i: Integer;
begin
  Result := TImageList.Create(AOwner);
  Result.Width := 16;
  Result.Height := 16;
  bmp := TBitmap.Create;
  try
    bmp.SetSize(16, 16);
    for i := 1 to ACount do
      Result.Add(bmp, nil);
  finally
    bmp.Free;
  end;
end;

procedure TTyToolWindowImagesTests.SetUp;
begin
  { 控件要有父控件并自带 controller(同 test.toolwindow.bar)。 }
  FForm := TForm.CreateNew(nil);
  FForm.Font.PixelsPerInch := 96;
  FForm.SetBounds(0, 0, 800, 600);
  FCtl := TTyStyleController.Create(FForm);
  FBar := TImagesBar.Create(FForm);
  FBar.Parent := FForm;
  FBar.Controller := FCtl;
  FBar.Font.PixelsPerInch := 96;
  FBar.Height := 400;
end;

procedure TTyToolWindowImagesTests.TearDown;
var
  i: Integer;
  list: TCustomImageList;
  stray: string;
begin
  { 窗体拥有的列表也照「判据红才泄漏」办:不是栏此刻订阅的那一个、变更却还到栏的,
    link 还挂在它上面,跟着窗体释放就死循环 —— 把它从窗体摘下来泄漏掉,再报红。
    各测试自己没接住的换列表(加载中的 fixup、外来列表换本库列表)都落在这里。 }
  stray := '';
  if (FForm <> nil) and (FBar <> nil) then
    for i := FForm.ComponentCount - 1 downto 0 do
      if (FForm.Components[i] is TCustomImageList)
         and (FForm.Components[i] <> FBar.EffectiveImages) then
      begin
        list := TCustomImageList(FForm.Components[i]);
        if ChangeReachesBar(list) then
        begin
          FForm.RemoveComponent(list);
          stray := stray + ' ' + list.ClassName;
        end;
      end;
  FreeAndNil(FForm);
  if stray <> '' then
    Fail('换掉的列表还挂着栏的 link(已泄漏,不然析构死循环):' + stray);
end;

function TTyToolWindowImagesTests.NewList(AOwner: TComponent;
  const ANames: string): TTyLucideImageList;
begin
  Result := TTyLucideImageList.Create(AOwner);
  Result.Names.Text := ANames;
end;

function TTyToolWindowImagesTests.NewWindow: TTyToolWindow;
begin
  Result := TTyToolWindow.Create(FForm);
  Result.Parent := FBar;
end;

function TTyToolWindowImagesTests.ChangeReachesBar(AList: TCustomImageList): Boolean;
var
  before: Integer;
begin
  before := FBar.InvalidateCount;
  { 列表只在记了「变过」时才发变更(TCustomImageList.Change 看 FChanged),空喊一声 Change
    不算。本库的列表走真实路径(改名字),外来的先记一笔再喊(TImageList.Add 不记)。 }
  if AList is TTyLucideImageList then
    TTyLucideImageList(AList).Names.Add('star')
  else
  begin
    TImageListAccess(AList).MarkAsChanged;
    AList.Change;
  end;
  Result := FBar.InvalidateCount <> before;
end;

procedure TTyToolWindowImagesTests.TestTheIndexIsATImageIndexAndTheBarPublishesImages;
var
  pi: PPropInfo;
begin
  { LCL 的 TImageIndexPropertyEditor 按属性类型 TImageIndex 挂上,再顺着 Parent 找
    名叫 Images 的 published 列表(graphpropedits.pas:713-728)。两头缺一头,
    对象查看器里 ImageIndex 就只是个数字框。 }
  pi := GetPropInfo(TTyToolWindow, 'ImageIndex');
  AssertTrue('ImageIndex published', pi <> nil);
  AssertEquals('类型是 ImgList.TImageIndex', 'TImageIndex', pi^.PropType^.Name);
  pi := GetPropInfo(TTyToolWindowBar, 'Images');
  AssertTrue('栏 published Images', pi <> nil);
  AssertTrue('Images 是 TCustomImageList',
    GetTypeData(pi^.PropType)^.ClassType.InheritsFrom(TCustomImageList));
end;

procedure TTyToolWindowImagesTests.TestImageNameResolvesAgainstTheBarsList;
var
  w: TTyToolWindow;
begin
  FBar.Images := NewList(FForm, HouseFolder);
  w := NewWindow;
  w.ImageName := 'folder';
  AssertEquals('按名字解析', 1, FBar.ResolvedImageIndex(w));
  AssertEquals('ImageIndex 是名字的视图', 1, w.ImageIndex);
  w.ImageName := 'no-such-glyph';
  AssertEquals('名字找不到 → -1,不许乱画一个', -1, FBar.ResolvedImageIndex(w));
  { 序号写过一次(换成了名字 'house'),名字再改成找不到的:画的那一格也不许回落到那个序号。 }
  w.ImageIndex := 0;
  AssertEquals('按序号写 = 记下那一格的名字', 'house', w.ImageName);
  w.ImageName := 'no-such-glyph';
  AssertEquals('名字找不到,不回落到写过的序号', -1, FBar.ResolvedImageIndex(w));
  AssertEquals('没有窗口就没有图标', -1, FBar.ResolvedImageIndex(nil));
end;

procedure TTyToolWindowImagesTests.TestTheIndexIsTheKeyWhenThereIsNoName;
var
  w: TTyToolWindow;
  foreign: TImageList;
begin
  w := NewWindow;
  { 栏没有列表:序号挂着,画的就是它。 }
  w.ImageIndex := 2;
  AssertEquals('没有列表时名字不动', '', w.ImageName);
  AssertEquals('没有名字就用序号', 2, FBar.ResolvedImageIndex(w));
  { 外来的 LCL 列表没有名字:序号换不成名字,它自己就是键,照样进 .lfm。列表里有 3 张图,
    序号 2 在界内 —— 换不成名字只能是因为它是外来的,不是因为越界。 }
  foreign := NewForeignList(FForm, 3);
  AssertEquals('前提:序号在界内', 3, foreign.Count);
  FBar.Images := foreign;
  AssertEquals('外来列表换不出名字', '', w.ImageName);
  AssertEquals('序号就是键', 2, FBar.ResolvedImageIndex(w));
  AssertTrue('没有名字时序号进流', IsStoredProp(w, 'ImageIndex'));
end;

procedure TTyToolWindowImagesTests.TestAPendingIndexResolvesInLoadedNotWhileLoading;
var
  w: TTyToolWindow;
  b: TTyLucideImageList;
begin
  { 模拟流式:加载中栏先拿到列表 A,窗口读进序号 1,之后引用又被 fixup 成列表 B。
    判据:加载中不解析(名字还空着),Loaded 之后按 **B** 解析 —— 在加载中就解析的话,
    拿到的是 A[1] = 'folder',到了 B 里是第 0 格。 }
  FBar.BeginLoad;
  FBar.Images := NewList(FForm, HouseFolder);
  w := NewWindow;
  w.ImageIndex := 1;
  AssertEquals('加载中不碰列表', '', w.ImageName);
  b := NewList(FForm, FolderHouse);
  FBar.Images := b;
  FBar.EndLoad;
  AssertEquals('Loaded 里按最终的列表解析', 'house', w.ImageName);
  { 之后 B 前面插进一格:画的那一格跟着名字走到第 2 格,和写进来的序号 1 分得开 ——
    没解析(还画序号)、按 A 解析('folder' 此刻在第 1 格)都答不出 2。 }
  b.Names.Insert(0, 'star');
  AssertEquals('画的是最终列表里名字所在的那一格', 2, FBar.ResolvedImageIndex(w));
  AssertFalse('有了名字,序号不再进流', IsStoredProp(w, 'ImageIndex'));
end;

procedure TTyToolWindowImagesTests.TestAnIndexWaitsForAListAndALaterNameWins;
var
  w1, w2, w3: TTyToolWindow;
begin
  w1 := NewWindow;
  w2 := NewWindow;
  w1.ImageIndex := 1;
  { 先按序号、后按名字:后写的算,栏拿到列表时挂起的序号不许把名字盖掉。 }
  w2.ImageIndex := 1;
  w2.ImageName := 'house';
  FBar.Images := NewList(FForm, HouseFolder);
  AssertEquals('列表来了,挂起的序号换成名字', 'folder', w1.ImageName);
  AssertEquals('后写的名字留着', 'house', w2.ImageName);
  { 不在栏里时写的序号,进了有列表的栏就换。 }
  w3 := TTyToolWindow.Create(FForm);
  w3.ImageIndex := 0;
  AssertEquals('没有栏时挂着', '', w3.ImageName);
  w3.Parent := FBar;
  AssertEquals('进栏就换', 'house', w3.ImageName);
end;

procedure TTyToolWindowImagesTests.TestSwappingTheListUnsubscribesTheOldOneFirst;
var
  a, b: TTyLucideImageList;
  leak: Boolean;
begin
  a := NewList(nil, HouseFolder);
  b := NewList(nil, FolderHouse);
  leak := False;
  try
    FBar.Images := a;
    FBar.Images := b;
    if ChangeReachesBar(a) then
    begin
      { 故意泄漏 a、b:link 还挂在 a 上而 Sender 已经不是 a,释放就死循环。 }
      leak := True;
      Fail('换列表后旧列表的变更还到栏:link 没从旧列表注销(旧列表析构会死循环)');
    end;
    AssertTrue('新列表的变更到栏', ChangeReachesBar(b));
  finally
    if not leak then
    begin
      { 判据绿了才释放 —— 这一句能返回就是第二道证据。 }
      a.Free;
      FBar.Images := nil;
      b.Free;
    end;
  end;
end;

procedure TTyToolWindowImagesTests.TestFreeingTheSubscribedListClearsTheReference;
var
  a, b: TTyLucideImageList;
  w: TTyToolWindow;
  before: Integer;
begin
  a := NewList(nil, HouseFolder);
  b := nil;
  try
    FBar.Images := a;
    w := NewWindow;
    w.ImageName := 'house';
    before := FBar.InvalidateCount;
    FreeAndNil(a);
    AssertNull('列表释放后引用清掉', FBar.Images);
    AssertNull('生效列表也没了', FBar.EffectiveImages);
    AssertTrue('列表释放后栏重画(图标没了)', FBar.InvalidateCount > before);
    AssertEquals('没有列表,名字解析不出来', -1, FBar.ResolvedImageIndex(w));
    AssertEquals('名字这个持久键留着', 'house', w.ImageName);
    { 之后换上的列表照常订阅。 }
    b := NewList(nil, HouseFolder);
    FBar.Images := b;
    AssertTrue('新列表的变更到栏', ChangeReachesBar(b));
    AssertEquals('名字在新列表里解析', 0, FBar.ResolvedImageIndex(w));
  finally
    FBar.Images := nil;
    a.Free;
    b.Free;
  end;
end;

procedure TTyToolWindowImagesTests.TestAListTakenFromItsOwnerIsUnsubscribed;
var
  a, b: TTyLucideImageList;
  leak: Boolean;
begin
  { RemoveComponent 同样广播 opRemove,而列表还活着。栏照 LCL 惯例清引用 —— 那就必须同时
    从它身上注销:跳过注销的话 link 还挂在它上面,再订阅别的列表就是那个死循环。 }
  a := NewList(FForm, HouseFolder);
  b := nil;
  leak := False;
  try
    FBar.Images := a;
    FForm.RemoveComponent(a);
    AssertNull('摘走的列表不再是栏的 Images', FBar.Images);
    b := NewList(nil, FolderHouse);
    FBar.Images := b;
    if ChangeReachesBar(a) then
    begin
      { 故意泄漏 a、b,理由同上。 }
      leak := True;
      Fail('摘走的列表的变更还到栏:link 没从它身上注销(它析构时会死循环)');
    end;
    { 互相的 FreeNotification 也撤了:它日后释放不再通知本栏。 }
    FBar.Watched := a;
    FreeAndNil(a);
    AssertFalse('摘走的列表释放时不再通知栏', FBar.WatchedRemoved);
  finally
    FBar.Watched := nil;
    if not leak then
    begin
      a.Free;
      FBar.Images := nil;
      b.Free;
    end;
  end;
end;

procedure TTyToolWindowImagesTests.TestAListChangeRepaintsTheStrip;
var
  a: TTyLucideImageList;
begin
  a := NewList(FForm, HouseFolder);
  FBar.Images := a;
  AssertTrue('列表内容变了,图标条要重画', ChangeReachesBar(a));
end;

procedure TTyToolWindowImagesTests.TestSwappingTheListDropsTheOldFreeNotification;
var
  a, b: TTyLucideImageList;
  leak: Boolean;
begin
  { FreeNotification 跟着订阅走:换掉的旧列表日后释放,不再通知本栏。 }
  a := NewList(nil, HouseFolder);
  b := NewList(nil, FolderHouse);
  leak := False;
  try
    FBar.Images := a;
    FBar.Images := b;
    if ChangeReachesBar(a) then
    begin
      leak := True;                    { 理由同 TestSwappingTheListUnsubscribesTheOldOneFirst }
      Fail('换列表后旧列表的变更还到栏:link 没从旧列表注销');
    end;
    FBar.Watched := a;
    FreeAndNil(a);
    AssertFalse('换掉的旧列表释放时不再通知栏', FBar.WatchedRemoved);
    { 反面:订阅着的那一个释放时要通知到 —— 引用靠它清。 }
    FBar.Watched := b;
    FreeAndNil(b);
    AssertTrue('订阅着的列表释放时通知栏', FBar.WatchedRemoved);
    AssertNull('引用清掉', FBar.Images);
  finally
    FBar.Watched := nil;
    if not leak then
    begin
      FBar.Images := nil;
      a.Free;
      b.Free;
    end;
  end;
end;

procedure TTyToolWindowImagesTests.TestAListBeingFreedIsNoLongerEffective;
var
  a: TTyLucideImageList;
  watcher: TFreeWatcher;
begin
  { 正在释放的列表不是生效列表 —— 栏自己的 opRemove 还没到时也不是(C 期回落
    Manager.Images 时,manager 清引用和栏收通知谁先谁后说不准)。观察者在栏之后登记
    FreeNotification,于是先于栏收到通知。 }
  a := NewList(nil, HouseFolder);
  watcher := TFreeWatcher.Create(nil);
  try
    FBar.Images := a;
    watcher.Bar := FBar;
    a.FreeNotification(watcher);
    FreeAndNil(a);
    AssertTrue('前提:观察者收到了通知', watcher.Called);
    AssertNull('释放中的列表不是生效列表', watcher.SeenEffective);
    AssertNull('之后引用清掉', FBar.Images);
  finally
    a.Free;
    watcher.Free;
  end;
end;

procedure TTyToolWindowImagesTests.TestFreeingTheBarUnhooksItFromALiveList;
var
  list: TTyLucideImageList;
  corpse: Pointer;
begin
  { 栏先于列表析构:link 得跟着栏走,不然列表的下一次变更打到死栏身上。栏留成清零的
    尸体(见 TImagesBar.FreeInstance),悬空回调必然 AV,不会碰巧没事。 }
  list := NewList(nil, HouseFolder);
  try
    FBar.Images := list;
    NewWindow.ImageName := 'house';
    TImagesBar.Corpse := nil;
    TImagesBar.KeepCorpse := True;
    try
      FreeAndNil(FBar);
    finally
      TImagesBar.KeepCorpse := False;
    end;
    AssertTrue('前提:栏留成了尸体', TImagesBar.Corpse <> nil);
    list.Names.Add('star');          { 触发 Change }
    AssertEquals('栏走后列表照常变更', 3, list.Names.Count);
  finally
    list.Free;                       { 能正常返回:link 表里没有死 link 要清 }
    corpse := TImagesBar.Corpse;
    TImagesBar.Corpse := nil;
    if corpse <> nil then FreeMem(corpse);
  end;
end;

procedure TTyToolWindowImagesTests.TestAnIndexChangeRepaintsEvenWithoutANameToChange;
var
  w: TTyToolWindow;
  before: Integer;
begin
  { 外来列表没有名字:ImageIndex 2 → 3 时名字一直是 '',重画只能来自 SetImageIndex 自己。 }
  FBar.Images := NewForeignList(FForm, 4);
  w := NewWindow;
  w.ImageIndex := 2;
  AssertEquals('前提:名字一直空着', '', w.ImageName);
  before := FBar.InvalidateCount;
  w.ImageIndex := 3;
  AssertEquals('前提:名字还是空的', '', w.ImageName);
  AssertTrue('序号变了,栏重画', FBar.InvalidateCount > before);
  { 本库的列表:名字跟着变,SetImageName 已经重画过,不再重画第二次。 }
  FBar.Images := NewList(FForm, HouseFolder);
  w.ImageName := 'house';
  before := FBar.InvalidateCount;
  w.ImageIndex := 1;
  AssertEquals('前提:名字换了', 'folder', w.ImageName);
  AssertEquals('名字变了只重画一次', before + 1, FBar.InvalidateCount);
end;

procedure TTyToolWindowImagesTests.TestRunTimeIconAndHintChangesRepaintTheBar;
var
  w: TTyToolWindow;
  before: Integer;
begin
  FBar.Images := NewList(FForm, HouseFolder);
  w := NewWindow;
  before := FBar.InvalidateCount;
  w.ImageName := 'folder';
  AssertTrue('改 ImageName 让栏重画', FBar.InvalidateCount > before);
  before := FBar.InvalidateCount;
  w.ImageIndex := 0;
  AssertTrue('改 ImageIndex 让栏重画', FBar.InvalidateCount > before);
  before := FBar.InvalidateCount;
  w.StripHint := 'Files';
  AssertTrue('改 StripHint 让栏重画', FBar.InvalidateCount > before);
  before := FBar.InvalidateCount;
  w.StripHint := 'Files';
  AssertEquals('值没变不重画', before, FBar.InvalidateCount);
end;

procedure TTyToolWindowImagesTests.TestStripHintFallsBackToCaptionNeverToHint;
var
  w: TTyToolWindow;
begin
  w := NewWindow;
  w.Caption := 'Explorer';
  w.Hint := 'window hint';
  AssertEquals('StripHint 空 → Caption,不是 Hint', 'Explorer', FBar.StripHintText(w));
  w.StripHint := 'Files and folders';
  AssertEquals('设了 StripHint 就用它', 'Files and folders', FBar.StripHintText(w));
  AssertEquals('没有窗口就没有提示', '', FBar.StripHintText(nil));
end;

{ --- Manager.Images 回落(spec §8) -------------------------------------------------- }

procedure TTyToolWindowImagesTests.TestABarWithoutAListReadsTheManagers;
var
  m: TTyToolWindowManager;
  list: TTyLucideImageList;
  w: TTyToolWindow;
begin
  list := NewList(FForm, HouseFolder);
  m := TTyToolWindowManager.Create(FForm);
  m.Images := list;
  FBar.Manager := m;
  w := NewWindow;
  w.ImageName := 'folder';
  AssertSame('栏没有列表:生效列表是 manager 的', list, FBar.EffectiveImages);
  AssertEquals('名字在 manager 的列表里解析', 1, FBar.ResolvedImageIndex(w));
  AssertEquals('ImageIndex 视图也是那一格', 1, w.ImageIndex);
end;

procedure TTyToolWindowImagesTests.TestTheFallbackListPaintsTheStrip;
const
  W = 300;
  H = 400;
var
  m: TTyToolWindowManager;
  w1, w2: TTyToolWindow;
  cell: TRect;
  bmp: TBitmap;
  ink: Integer;
begin
  { 图标条钉成品红底、静止墨蓝(test.toolwindow.bar 的 StripTheme)。 }
  FCtl.StyleOverride := StripTheme;
  m := TTyToolWindowManager.Create(FForm);
  m.Images := NewList(FForm, HouseFolder);
  FBar.Manager := m;
  w1 := NewWindow;
  w1.ImageName := 'folder';
  w2 := NewWindow;
  FBar.ActiveWindow := w2;
  cell := FBar.StripItemRect(0);
  AssertTrue('前提:第一格排上了', not IsRectEmpty(cell));
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(cell.Right - cell.Left, cell.Bottom - cell.Top);
    bmp.Canvas.Brush.Color := Wipe;
    bmp.Canvas.FillRect(0, 0, bmp.Width, bmp.Height);
    FBar.CallRenderTo(bmp.Canvas, Rect(-cell.Left, -cell.Top, W - cell.Left, H - cell.Top), 96);
    ink := CountInk(bmp, Ground, RestInk);
  finally
    bmp.Free;
  end;
  AssertTrue('静止格里画出了 manager 列表里的图标', ink > 0);
end;

procedure TTyToolWindowImagesTests.TestTheBarsOwnListWinsOverTheManagers;
var
  m: TTyToolWindowManager;
  own: TTyLucideImageList;
  w: TTyToolWindow;
begin
  m := TTyToolWindowManager.Create(FForm);
  m.Images := NewList(FForm, HouseFolder);
  own := NewList(FForm, FolderHouse);
  FBar.Images := own;
  FBar.Manager := m;
  w := NewWindow;
  w.ImageName := 'folder';
  AssertSame('栏自己的列表优先', own, FBar.EffectiveImages);
  AssertEquals('按栏自己的列表解析', 0, FBar.ResolvedImageIndex(w));
end;

procedure TTyToolWindowImagesTests.TestAPendingIndexResolvesWhenTheManagerGetsAList;
var
  m: TTyToolWindowManager;
  w: TTyToolWindow;
begin
  m := TTyToolWindowManager.Create(FForm);
  FBar.Manager := m;
  w := NewWindow;
  w.ImageIndex := 1;
  AssertEquals('前提:哪儿都没有列表,名字还空着', '', w.ImageName);
  m.Images := NewList(FForm, HouseFolder);
  AssertEquals('manager 拿到列表:挂起的序号换成名字', 'folder', w.ImageName);
end;

procedure TTyToolWindowImagesTests.TestSwappingTheManagersListResubscribes;
var
  m: TTyToolWindowManager;
  a, b: TTyLucideImageList;
  leak: Boolean;
begin
  a := NewList(nil, HouseFolder);
  b := NewList(nil, FolderHouse);
  leak := False;
  m := TTyToolWindowManager.Create(FForm);
  try
    FBar.Manager := m;
    m.Images := a;
    AssertTrue('前提:manager 的列表的变更到栏', ChangeReachesBar(a));
    m.Images := b;
    if ChangeReachesBar(a) then
    begin
      { 故意泄漏 a、b(见单元头)。 }
      leak := True;
      Fail('换了 manager 的列表后旧列表的变更还到栏:link 没注销');
    end;
    AssertTrue('新列表的变更到栏', ChangeReachesBar(b));
  finally
    if not leak then
    begin
      a.Free;
      m.Images := nil;
      b.Free;
    end;
  end;
end;

procedure TTyToolWindowImagesTests.TestFreeingTheManagersListLeavesNoEffectiveList;
var
  m: TTyToolWindowManager;
  a: TTyLucideImageList;
  watcher: TAnyFreeWatcher;
begin
  { 观察者在栏、manager 之后登记,先于它们收到列表的 opRemove:那一刻 manager 还引用着它。 }
  a := NewList(nil, HouseFolder);
  watcher := TAnyFreeWatcher.Create(nil);
  m := TTyToolWindowManager.Create(FForm);
  try
    m.Images := a;
    FBar.Manager := m;
    watcher.Bar := FBar;
    watcher.Target := a;
    a.FreeNotification(watcher);
    FreeAndNil(a);            { 这一句能返回就是「析构没死循环」 }
    AssertTrue('前提:观察者收到了通知', watcher.Called);
    AssertNull('释放中的 manager 列表不是生效列表', watcher.SeenEffective);
    AssertNull('之后 manager 的引用清掉', m.Images);
    AssertNull('栏没有生效列表', FBar.EffectiveImages);
  finally
    a.Free;
    watcher.Free;
  end;
end;

procedure TTyToolWindowImagesTests.TestFreeingTheManagerUnsubscribesItsList;
var
  m: TTyToolWindowManager;
  a: TTyLucideImageList;
  leak: Boolean;
begin
  a := NewList(nil, HouseFolder);
  leak := False;
  try
    m := TTyToolWindowManager.Create(FForm);
    m.Images := a;
    FBar.Manager := m;
    AssertTrue('前提:到栏', ChangeReachesBar(a));
    m.Free;
    AssertNull('manager 走了:没有生效列表', FBar.EffectiveImages);
    if ChangeReachesBar(a) then
    begin
      leak := True;
      Fail('manager 被释放后它的列表的变更还到栏:link 没注销');
    end;
  finally
    if not leak then a.Free;
  end;
end;

procedure TTyToolWindowImagesTests.TestLeavingTheManagerUnsubscribesItsList;
var
  m: TTyToolWindowManager;
  a: TTyLucideImageList;
  leak: Boolean;
begin
  a := NewList(nil, HouseFolder);
  leak := False;
  m := TTyToolWindowManager.Create(FForm);
  try
    m.Images := a;
    FBar.Manager := m;
    AssertTrue('前提:到栏', ChangeReachesBar(a));
    FBar.Manager := nil;
    AssertNull('离开 manager:没有生效列表', FBar.EffectiveImages);
    if ChangeReachesBar(a) then
    begin
      leak := True;
      Fail('离开 manager 后它的列表的变更还到栏:link 没注销');
    end;
  finally
    if not leak then
    begin
      m.Images := nil;
      a.Free;
    end;
  end;
end;

procedure TTyToolWindowImagesTests.TestAManagerBeingFreedIsNoFallback;
var
  m: TTyToolWindowManager;
  a: TTyLucideImageList;
  watcher: TAnyFreeWatcher;
begin
  { 观察者在栏之后登记到 manager 上,先于栏收到 manager 的 opRemove:那一刻栏还指着它、
    它还引用着活的列表。 }
  a := NewList(nil, HouseFolder);
  watcher := TAnyFreeWatcher.Create(nil);
  try
    m := TTyToolWindowManager.Create(nil);
    m.Images := a;
    FBar.Manager := m;
    watcher.Bar := FBar;
    watcher.Target := m;
    m.FreeNotification(watcher);
    m.Free;
    AssertTrue('前提:观察者收到了通知', watcher.Called);
    AssertNull('正在释放的 manager 不回落', watcher.SeenEffective);
  finally
    watcher.Free;
    a.Free;
  end;
end;

initialization
  RegisterTest(TTyToolWindowImagesTests);
end.
