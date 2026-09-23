unit test.toolwindow.images;
{$mode objfpc}{$H+}

{ 栏的图片列表与窗口图标的解析(spec §8):名字是持久键、序号是它的视图;挂起的序号只在
  栏的 Loaded 里解析;换列表先注销旧的;列表被释放 / 被摘走时清引用;运行时改图标 / 提示
  要让栏重画;图标条提示用 StripHint,空了用 Caption,不用 Hint。
  绘制(着色)在 Task 6b,CM_HINTSHOW 在 Task 7。

  几条「旧列表不许还挂着 link」的测试,先用一个不会卡死的判据(旧列表的变更不再到栏),
  判据红了就**故意泄漏**那几个列表再 Fail —— 它们的析构会死循环(imglist.inc:1692-1698),
  释放它们就是把一条红测试变成挂死的整个套件。判据绿了才真的释放,释放得完就是第二道证据。 }

interface

uses
  Classes, SysUtils, TypInfo, Controls, Forms, ImgList, fpcunit, testregistry,
  tyControls.Controller, tyControls.ToolWindows, tyControls.Icons.Lucide;

type
  { 探针:数「栏被请求重画了几次」,并开出流式加载的两个入口。 }
  TImagesBar = class(TTyToolWindowBar)
  public
    InvalidateCount: Integer;
    procedure Invalidate; override;
    procedure BeginLoad;
    procedure EndLoad;
  end;

  TTyToolWindowImagesTests = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FBar: TImagesBar;
    function NewList(AOwner: TComponent; const ANames: string): TTyLucideImageList;
    function NewWindow: TTyToolWindow;
    { 列表 AList 的一次变更有没有到栏(link 还挂不挂在它身上)。 }
    function ChangeReachesBar(AList: TTyLucideImageList): Boolean;
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
    procedure TestRunTimeIconAndHintChangesRepaintTheBar;
    procedure TestStripHintFallsBackToCaptionNeverToHint;
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
begin
  FreeAndNil(FForm);
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

function TTyToolWindowImagesTests.ChangeReachesBar(AList: TTyLucideImageList): Boolean;
var
  before: Integer;
begin
  before := FBar.InvalidateCount;
  AList.Names.Add('star');
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
  { 外来的 LCL 列表没有名字:序号换不成名字,它自己就是键,照样进 .lfm。 }
  foreign := TImageList.Create(FForm);
  FBar.Images := foreign;
  AssertEquals('外来列表换不出名字', '', w.ImageName);
  AssertEquals('序号就是键', 2, FBar.ResolvedImageIndex(w));
  AssertTrue('没有名字时序号进流', IsStoredProp(w, 'ImageIndex'));
end;

procedure TTyToolWindowImagesTests.TestAPendingIndexResolvesInLoadedNotWhileLoading;
var
  w: TTyToolWindow;
begin
  { 模拟流式:加载中栏先拿到列表 A,窗口读进序号 1,之后引用又被 fixup 成列表 B。
    判据:加载中不解析(名字还空着),Loaded 之后按 **B** 解析 —— 在加载中就解析的话,
    拿到的是 A[1] = 'folder',到了 B 里是第 0 格。 }
  FBar.BeginLoad;
  FBar.Images := NewList(FForm, HouseFolder);
  w := NewWindow;
  w.ImageIndex := 1;
  AssertEquals('加载中不碰列表', '', w.ImageName);
  FBar.Images := NewList(FForm, FolderHouse);
  FBar.EndLoad;
  AssertEquals('Loaded 里按最终的列表解析', 'house', w.ImageName);
  AssertEquals('画的是最终列表里的那一格', 1, FBar.ResolvedImageIndex(w));
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
begin
  a := NewList(nil, HouseFolder);
  b := NewList(nil, FolderHouse);
  FBar.Images := a;
  FBar.Images := b;
  if ChangeReachesBar(a) then
  begin
    { 故意泄漏 a、b:link 还挂在 a 上而 Sender 已经不是 a,释放就死循环。 }
    Fail('换列表后旧列表的变更还到栏:link 没从旧列表注销(旧列表析构会死循环)');
  end;
  AssertTrue('新列表的变更到栏', ChangeReachesBar(b));
  { 判据绿了才释放 —— 这一句能返回就是第二道证据。 }
  a.Free;
  FBar.Images := nil;
  b.Free;
end;

procedure TTyToolWindowImagesTests.TestFreeingTheSubscribedListClearsTheReference;
var
  a, b: TTyLucideImageList;
  w: TTyToolWindow;
begin
  a := NewList(nil, HouseFolder);
  FBar.Images := a;
  w := NewWindow;
  w.ImageName := 'house';
  a.Free;
  AssertNull('列表释放后引用清掉', FBar.Images);
  AssertNull('生效列表也没了', FBar.EffectiveImages);
  AssertEquals('没有列表,名字解析不出来', -1, FBar.ResolvedImageIndex(w));
  AssertEquals('名字这个持久键留着', 'house', w.ImageName);
  { 之后换上的列表照常订阅。 }
  b := NewList(nil, HouseFolder);
  FBar.Images := b;
  AssertTrue('新列表的变更到栏', ChangeReachesBar(b));
  AssertEquals('名字在新列表里解析', 0, FBar.ResolvedImageIndex(w));
  FBar.Images := nil;
  b.Free;
end;

procedure TTyToolWindowImagesTests.TestAListTakenFromItsOwnerIsUnsubscribed;
var
  a, b: TTyLucideImageList;
begin
  { RemoveComponent 同样广播 opRemove,而列表还活着。栏照 LCL 惯例清引用 —— 那就必须同时
    从它身上注销:跳过注销的话 link 还挂在它上面,再订阅别的列表就是那个死循环。 }
  a := NewList(FForm, HouseFolder);
  FBar.Images := a;
  FForm.RemoveComponent(a);
  AssertNull('摘走的列表不再是栏的 Images', FBar.Images);
  b := NewList(nil, FolderHouse);
  FBar.Images := b;
  if ChangeReachesBar(a) then
  begin
    { 故意泄漏 a、b,理由同上。 }
    Fail('摘走的列表的变更还到栏:link 没从它身上注销(它析构时会死循环)');
  end;
  a.Free;
  FBar.Images := nil;
  b.Free;
end;

procedure TTyToolWindowImagesTests.TestAListChangeRepaintsTheStrip;
var
  a: TTyLucideImageList;
begin
  a := NewList(FForm, HouseFolder);
  FBar.Images := a;
  AssertTrue('列表内容变了,图标条要重画', ChangeReachesBar(a));
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

initialization
  RegisterTest(TTyToolWindowImagesTests);
end.
