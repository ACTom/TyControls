unit test.toolwindow.hide;
{$mode objfpc}{$H+}

{ 一侧没有窗口时隐藏(spec §6.9,E 期)与拖动时的放置预览(spec §9.4 / §9.8)。夹具在
  test.toolwindow.manager(TTyToolWindowManagerFixture)。 }

interface

uses
  Classes, SysUtils, Types, TypInfo, Controls, Forms, Graphics, LCLType, LCLProc, LMessages,
  fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Base, tyControls.Controller, tyControls.StrConsts,
  tyControls.Painter,
  tyControls.ToolWindows, tyControls.ToolWindows.Layout, tyControls.ToolWindows.Manager,
  test.toolwindow.window, test.toolwindow.bar, test.toolwindow.manager;

type
  TTyToolWindowHideTests = class(TTyToolWindowManagerFixture)
  private
    { 窗体上一条 APlacement 的空栏(照 NewBarOn,只是不加窗口)。 }
    function NewEmptyBar(APlacement: TTyToolWindowPlacement): TBarAccess;
    function Chrome(ABar: TBarAccess): Integer;
  published
    { --- Task 7:HideWhenEmpty(spec §6.9) --- }
    procedure TestHiddenAsEmptyAnswersPerBar;
    procedure TestAHiddenBarIsZeroWideAndLaysOutNothing;
    procedure TestAKeptEmptyBarShowsItsStrip;
    procedure TestAHiddenBarAllowsAZeroMinimumWidth;
    procedure TestTheBottomBarIgnoresTheProperty;
    procedure TestTheLastWindowLeavingHidesTheBar;
    procedure TestHidingNeverWritesCollapsedOrExpandedSize;
    procedure TestTogglingThePropertyRederives;
    procedure TestAHiddenBarStaysUsable;
    procedure TestAHiddenBarGivesItsShareBack;
    procedure TestALayoutHidesAndShowsBars;
    procedure TestHideWhenEmptyStreamsOnlyWhenOff;
    procedure TestDesignTimeNeverHides;
  end;

implementation

type
  { 流式化的根(同 test.toolwindow.window 的 TToolWindowHostForm,那一个在实现段里拿不到)。 }
  THideHostForm = class(TForm)
  end;

function TTyToolWindowHideTests.NewEmptyBar(APlacement: TTyToolWindowPlacement): TBarAccess;
begin
  Result := TBarAccess.Create(FForm);
  Result.Placement := APlacement;
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  if APlacement = twpBottom then Result.Width := 600 else Result.Height := 400;
end;

function TTyToolWindowHideTests.Chrome(ABar: TBarAccess): Integer;
begin
  Result := ABar.ChromeInsetPx;
end;

{ --- Task 7 --------------------------------------------------------------------- }

procedure TTyToolWindowHideTests.TestHiddenAsEmptyAnswersPerBar;
var
  b: TBarAccess;
begin
  b := NewEmptyBar(twpLeft);
  AssertTrue('运行时左栏,没有窗口', b.HiddenAsEmpty);
  b := NewEmptyBar(twpRight);
  AssertTrue('运行时右栏,没有窗口', b.HiddenAsEmpty);
  b := NewEmptyBar(twpLeft);
  b.HideWhenEmpty := False;
  AssertFalse('HideWhenEmpty 关掉', b.HiddenAsEmpty);
  b := NewBarOn(twpLeft, ['Solo']);
  AssertFalse('有一个窗口', b.HiddenAsEmpty);
  b := NewEmptyBar(twpLeft);
  b.InsertControl(TBodyChild.Create(FForm));
  AssertTrue('漏进来的非窗口子控件不算窗口', b.HiddenAsEmpty);
  b := NewDesignBar;
  AssertFalse('设计期不隐藏', b.HiddenAsEmpty);
  b := NewEmptyBar(twpBottom);
  AssertFalse('底栏不管(高本来就是 0)', b.HiddenAsEmpty);
  b := NewEmptyBar(twpLeft);
  b.Collapsed := True;
  AssertTrue('收起着也照样隐藏', b.HiddenAsEmpty);
end;

procedure TTyToolWindowHideTests.TestAHiddenBarIsZeroWideAndLaysOutNothing;
var
  b: TBarAccess;
  L: TTyToolWindowBarLayout;
begin
  b := NewEmptyBar(twpLeft);
  AssertEquals('推导宽 0', 0, b.CallDerivedAxisPx);
  AssertEquals('Width = 0', 0, b.Width);
  AssertTrue('Visible 不写', b.Visible);
  L := b.BarLayout;
  AssertTrue('没有图标条', IsRectEmpty(L.Strip));
  AssertTrue('没有排图标的那一段', IsRectEmpty(L.Cells));
  AssertTrue('没有边缘区', IsRectEmpty(L.Edge));
  AssertTrue('没有内容区', IsRectEmpty(L.Content));
end;

procedure TTyToolWindowHideTests.TestAKeptEmptyBarShowsItsStrip;
var
  b: TBarAccess;
begin
  b := NewEmptyBar(twpLeft);
  b.HideWhenEmpty := False;
  AssertEquals('HideWhenEmpty = False:图标条 + 2 × chrome(A 期的样子)',
    StripPx + 2 * Chrome(b), b.CallDerivedAxisPx);
end;

procedure TTyToolWindowHideTests.TestAHiddenBarAllowsAZeroMinimumWidth;
var
  b: TBarAccess;
  minW, minH, maxW, maxH: TConstraintSize;
begin
  b := NewEmptyBar(twpLeft);
  minW := 0;
  minH := 0;
  maxW := 0;
  maxH := 0;
  b.CallConstrainedResize(minW, minH, maxW, maxH);
  AssertEquals('隐藏时下限 0(否则 LCL 把宽 0 钳回图标条宽)', 0, minW);
  b.HideWhenEmpty := False;
  b.CallConstrainedResize(minW, minH, maxW, maxH);
  AssertEquals('对照:不隐藏时下限是图标条', StripPx + 2 * Chrome(b), minW);
end;

procedure TTyToolWindowHideTests.TestTheBottomBarIgnoresTheProperty;
var
  b: TBarAccess;
  withWin: Integer;
begin
  b := NewEmptyBar(twpBottom);
  AssertEquals('空底栏高 0', 0, b.CallDerivedAxisPx);
  b.HideWhenEmpty := False;
  AssertEquals('关掉也是 0', 0, b.CallDerivedAxisPx);
  NewWindowIn(b, FForm);
  withWin := b.CallDerivedAxisPx;
  b.HideWhenEmpty := True;
  AssertEquals('有窗口时两种设置一样', withWin, b.CallDerivedAxisPx);
end;

procedure TTyToolWindowHideTests.TestTheLastWindowLeavingHidesTheBar;
var
  m: TTyToolWindowManager;
  l, r: TBarAccess;
  outline: TTyToolWindow;
begin
  m := NewManager;
  l := NewBarOn(twpLeft, ['Outline']);
  r := NewBarOn(twpRight, ['Other']);
  l.Manager := m;
  r.Manager := m;
  outline := l.Windows[0];
  AssertTrue('前提:挪得过去', m.MoveWindow(outline, r));
  AssertEquals('最后一个窗口走了:左栏宽 0', 0, l.Width);
  AssertTrue('再挪回来', m.MoveWindow(outline, l));
  AssertEquals('左栏出现:图标条 + 2 × chrome + 边缘区 + 内容',
    StripPx + 2 * Chrome(l) + EdgePx + TyToolWindowDefaultExpandedSize, l.Width);
end;

procedure TTyToolWindowHideTests.TestHidingNeverWritesCollapsedOrExpandedSize;
var
  m: TTyToolWindowManager;
  l, r: TBarAccess;
  outline: TTyToolWindow;
begin
  m := NewManager;
  l := NewBarOn(twpLeft, ['Outline']);
  r := NewBarOn(twpRight, ['Other']);
  l.Manager := m;
  r.Manager := m;
  outline := l.Windows[0];
  l.ExpandedSize := 200;
  l.Collapsed := True;
  m.MoveWindow(outline, r);
  AssertEquals('前提:隐藏了', 0, l.Width);
  AssertTrue('隐藏期间 Collapsed 不被写', l.Collapsed);
  AssertEquals('ExpandedSize 不变', 200, l.ExpandedSize);
  m.MoveWindow(outline, l);
  AssertFalse('挪回来照 §9.5 展开目标栏', l.Collapsed);
  AssertEquals('ExpandedSize 还是 200', 200, l.ExpandedSize);
end;

procedure TTyToolWindowHideTests.TestTogglingThePropertyRederives;
var
  b: TBarAccess;
begin
  b := NewEmptyBar(twpRight);
  AssertEquals('前提:隐藏', 0, b.Width);
  b.HideWhenEmpty := False;
  AssertTrue('关掉:宽 > 0', b.Width > 0);
  b.HideWhenEmpty := True;
  AssertEquals('打开:宽 0', 0, b.Width);
end;

procedure TTyToolWindowHideTests.TestAHiddenBarStaysUsable;
var
  m: TTyToolWindowManager;
  l, r: TBarAccess;
begin
  m := NewManager;
  l := NewBarOn(twpLeft, ['Explorer', 'Search']);
  r := NewEmptyBar(twpRight);
  l.Manager := m;
  r.Manager := m;
  AssertTrue('前提:右栏隐藏', r.HiddenAsEmpty);
  AssertTrue('隐藏的栏照样可用', m.IsBarUsable(r));
  AssertSame('UsableBar 答它', r, m.UsableBar(twpRight));
  AssertTrue('MoveWindow 过去答 True', m.MoveWindow(l.Windows[0], r));
  AssertTrue('右栏出现', r.Width > 0);
end;

procedure TTyToolWindowHideTests.TestAHiddenBarGivesItsShareBack;
var
  m: TTyToolWindowManager;
  l, r: TBarAccess;
  hiddenW, aloneW: Integer;
begin
  { 窄到左栏自己都要收窄:隐藏的右栏还按图标条扣固定部分的话,左栏会少一截。 }
  FForm.SetBounds(0, 0, 250, 600);
  m := NewManager;
  l := NewBarOn(twpLeft, ['Explorer']);
  r := NewBarOn(twpRight, ['Outline']);
  l.Manager := m;
  r.Manager := m;
  m.MoveWindow(r.Windows[0], l);
  AssertTrue('前提:右栏隐藏了', r.HiddenAsEmpty);
  hiddenW := l.Width;
  r.Visible := False;
  aloneW := l.Width;
  AssertTrue('前提:左栏自己也收窄着', aloneW < StripPx + 2 * Chrome(l) + EdgePx
    + TyToolWindowDefaultExpandedSize);
  AssertEquals('隐藏的栏分空间为 0:左栏拿到它不跟右栏分时的宽', aloneW, hiddenW);
end;

procedure TTyToolWindowHideTests.TestALayoutHidesAndShowsBars;
var
  m: TTyToolWindowManager;
  l, r: TBarAccess;
  withRight, emptyRight: string;
begin
  m := NewManager;
  l := NewBarOn(twpLeft, ['Explorer', 'Search']);
  r := NewBarOn(twpRight, ['Outline']);
  l.Manager := m;
  r.Manager := m;
  withRight := m.SaveLayoutToString;
  m.MoveWindow(r.Windows[0], l);
  emptyRight := m.SaveLayoutToString;
  AssertTrue('前提:读回有窗口的那份', m.LoadLayoutFromString(withRight));
  AssertTrue('右栏有窗口:出现', r.Width > 0);
  AssertTrue('前提:读回空右栏的那份', m.LoadLayoutFromString(emptyRight));
  AssertEquals('右栏空了:宽 0', 0, r.Width);
  AssertTrue(m.LoadLayoutFromString(withRight));
  AssertTrue('再读回来:又出现', r.Width > 0);
end;

procedure TTyToolWindowHideTests.TestHideWhenEmptyStreamsOnlyWhenOff;
var
  src, dst: TForm;
  ms: TMemoryStream;
  txt: TStringStream;
  bar, dbar: TTyToolWindowBar;
  b: TTyToolWindowBar;
begin
  b := TTyToolWindowBar.Create(nil);
  try
    AssertEquals('HideWhenEmpty 的 default 等于构造值', Ord(b.HideWhenEmpty),
      GetPropInfo(b, 'HideWhenEmpty')^.Default);
    AssertTrue('构造值 True', b.HideWhenEmpty);
  finally
    b.Free;
  end;
  src := THideHostForm.CreateNew(nil);
  src.Name := 'HostForm1';
  dst := THideHostForm.CreateNew(nil);
  ms := TMemoryStream.Create;
  txt := TStringStream.Create('');
  try
    bar := TTyToolWindowBar.Create(src);
    bar.Name := 'Bar';
    bar.Parent := src;
    ms.WriteComponent(src);
    ms.Position := 0;
    ObjectBinaryToText(ms, txt);
    AssertEquals('True 不写进 .lfm', 0, Pos('HideWhenEmpty', txt.DataString));
    bar.HideWhenEmpty := False;
    ms.Clear;
    ms.WriteComponent(src);
    ms.Position := 0;
    ms.ReadComponent(dst);
    dbar := dst.FindComponent('Bar') as TTyToolWindowBar;
    AssertFalse('False 写进去、读回来', dbar.HideWhenEmpty);
  finally
    txt.Free;
    ms.Free;
    dst.Free;
    src.Free;
  end;
end;

procedure TTyToolWindowHideTests.TestDesignTimeNeverHides;
var
  d: TBarAccess;
begin
  d := NewDesignBar;
  AssertEquals('设计期空左栏按展开算', StripPx + 2 * Chrome(d) + EdgePx
    + TyToolWindowDefaultExpandedSize, d.Width);
  AssertFalse('照旧画「添加工具窗口」', IsRectEmpty(d.BarLayout.EmptyNote));
end;

initialization
  RegisterClass(THideHostForm);
  RegisterTest(TTyToolWindowHideTests);
end.
