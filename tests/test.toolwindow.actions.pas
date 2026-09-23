unit test.toolwindow.actions;
{$mode objfpc}{$H+}

{ TTyToolWindowActions:操作区自己的排列、raw 首选尺寸、它在所在窗口标题行里的位置,
  以及「一个窗口只认第一个操作区」。窗口本体在 test.toolwindow.window。

  无头跑的时候窗体没有句柄,LCL 自己一次都不对齐 —— 摆窗口和摆操作区都按 LCL 的顺序
  自己请一遍(CallAlignControls,传**没扣过**的客户区),拿到的就是真机同值。 }

interface

uses
  Classes, SysUtils, Types, TypInfo, Controls, Forms, Graphics, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Base, tyControls.Controller, tyControls.ToolWindows,
  tyControls.ToolWindows.Layout,
  test.toolwindow.window;

type
  TProbeActions = class(TTyToolWindowActions)
  public
    procedure MarkDesigning(AOn: Boolean);
    procedure CallAlignControls;
    procedure CallRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  { 设计期里藏起来的子控件照样看得见 —— 但那是**子控件自己的** csDesigning 说了算
    (TControl.IsControlVisible),所以子控件也得能单独标成设计期。 }
  TDesignChild = class(TBodyChild)
  public
    procedure MarkDesigning(AOn: Boolean);
  end;

  TTyToolWindowActionsTests = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FBar: TTyToolWindowBar;
    FWin: TProbeWindow;
    function NewActions(AParent: TWinControl): TProbeActions;
    function NewChild(AParent: TWinControl; AW, AH: Integer): TBodyChild;
    { 把操作区画进一张 AW×AH 的位图,数两种墨:纯红(提示文字)和纯蓝(槽位描边)。
      颜色由各条测试自己的 StyleOverride 钉死,别的像素一律不算。 }
    procedure TallyActionsInk(AAct: TProbeActions; AW, AH: Integer;
      out ARed, ABlue: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestConstructionPinsTheStyleAndTheStreamingContract;
    procedure TestAnEmptyActionsAreaTakesNoWidthAtRunTime;
    procedure TestPreferredWidthIsPadsPlusChildrenPlusGaps;
    procedure TestTheAreaIgnoresAlignAndSitsAtTheTrailingEndOfTheHeader;
    procedure TestATallChildGrowsTheHeaderRow;
    procedure TestTheFlowCentresEachChildAndClipsTheLeadingOnesWhenNarrow;
    procedure TestTheFlowIsMirroredUnderRightToLeft;
    procedure TestRightToLeftPutsTheActionsLeftAndTheCaptionRightOfIt;
    procedure TestChildClassAllowedRejectsTheWorkbenchClasses;
    procedure TestOnlyTheFirstActionsAreaGoesIntoTheHeader;
    procedure TestAStrayAreaSitsAtTheBodyTopLeftAtDesignTime;
    procedure TestAnOrphanIsHiddenAtRunTimeOnly;
    procedure TestDesignTimeDrawsTheSlotAndTheNoteOnlyWhereTheyBelong;
    procedure TestAnActionsChangeDropsTheWindowPaintCache;
    procedure TestEnsureActionsCreatesOnceAndOwnsItLikeADesignContainer;
    procedure TestWithoutAHeaderTheActionsSitTopLeftAtRawSize;
    procedure TestTheFlowFloorsEachChildAtItsMinHeight;
    procedure TestDesignTimeCountsChildrenTheUserHid;
    procedure TestAStrayAreaIsWideEnoughForItsNoteAtDesignTimeOnly;
    procedure TestTheNoteOfAStrayAreaNeverSitsUnderItsChildren;
    procedure TestEnsureActionsMeasuresWithTheWindowController;
    procedure TestAChildMinWidthWidensItsSlotInTheFlow;
    procedure TestTheAreaOwnConstraintsReachTheHeader;
    procedure TestDraggingIntoADesignTimeOrphanReappliesItsFloor;
  end;

implementation

procedure TProbeActions.MarkDesigning(AOn: Boolean);
begin
  SetDesigning(AOn, False);
end;

procedure TDesignChild.MarkDesigning(AOn: Boolean);
begin
  SetDesigning(AOn, False);
end;

procedure TProbeActions.CallAlignControls;
var
  r: TRect;
begin
  { 同 TProbeWindow.CallAlignControls:传没扣过的客户区,AlignControls 自己调 AdjustClientRect。 }
  r := ClientRect;
  AlignControls(nil, r);
end;

procedure TProbeActions.CallRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TTyToolWindowActionsTests.SetUp;
begin
  { 控件必须有父控件并自带 controller,否则读的是进程级主题:单跑绿、全量红。 }
  FForm := TForm.CreateNew(nil);
  { 挂在窗体上的孤儿从这里继承密度。不钉的话无头是 72、widgetset 初始化之后是机器 DPI ——
    200% 的机器上孤儿的最小高(token × 2)就超过测试里给的 50,视 suite 顺序而红。 }
  FForm.Font.PixelsPerInch := 96;
  FCtl := TTyStyleController.Create(FForm);
  FBar := TTyToolWindowBar.Create(FForm);
  FBar.Parent := FForm;
  FBar.Controller := FCtl;
  FBar.SetBounds(0, 0, 240, 400);
  FWin := TProbeWindow.Create(FForm);
  FWin.Parent := FBar;
  FWin.Controller := FCtl;
  { 这里的数全跟着 PPI 走,无头默认不是 96。操作区是后建的,插进窗口时从它这里
    继承字体(连同 PixelsPerInch)。 }
  FWin.Font.PixelsPerInch := 96;
  FWin.SetBounds(0, 0, 200, 300);
end;

procedure TTyToolWindowActionsTests.TearDown;
begin
  FreeAndNil(FForm);
end;

function TTyToolWindowActionsTests.NewActions(AParent: TWinControl): TProbeActions;
begin
  Result := TProbeActions.Create(FForm);
  Result.Parent := AParent;
  { 窗口把 controller 推给操作区是 Task 5 那条推送链的活;这里自己接。 }
  Result.Controller := FCtl;
end;

function TTyToolWindowActionsTests.NewChild(AParent: TWinControl; AW, AH: Integer): TBodyChild;
begin
  Result := TBodyChild.Create(FForm);
  Result.Parent := AParent;
  Result.SetBounds(0, 0, AW, AH);
end;

procedure TTyToolWindowActionsTests.TallyActionsInk(AAct: TProbeActions; AW, AH: Integer;
  out ARed, ABlue: Integer);
var
  bmp: TBitmap;
  re: TBGRABitmap;
  px: TBGRAPixel;
  x, y: Integer;
begin
  ARed := 0;
  ABlue := 0;
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(AW, AH);
    { 按控件自己字体的密度画,跟 Paint 一样 —— 孤儿挂在窗体上,它的密度不是窗口钉的 96,
      按 96 画的话量出来的尺寸和画出来的字就是两套尺度。 }
    AAct.CallRenderTo(bmp.Canvas, Rect(0, 0, AW, AH), AAct.Font.PixelsPerInch);
    re := TBGRABitmap.Create(bmp);
    try
      { 只比 RGB,pf32bit 读回来的 alpha 不可信。文字和 1px 描边都带抗锯齿、跟白底混过,
        所以按「哪个通道明显占上风」数,不按纯色数。 }
      for y := 0 to AH - 1 do
        for x := 0 to AW - 1 do
        begin
          px := re.GetPixel(x, y);
          if (px.red > px.green + 40) and (px.red > px.blue + 40) then Inc(ARed);
          if (px.blue > px.red + 40) and (px.blue > px.green + 40) then Inc(ABlue);
        end;
    finally
      re.Free;
    end;
  finally
    bmp.Free;
  end;
end;

procedure TTyToolWindowActionsTests.TestConstructionPinsTheStyleAndTheStreamingContract;
const
  Bounds: array[0..3] of string = ('Left', 'Top', 'Width', 'Height');
var
  act: TTyToolWindowActions;
  i: Integer;
begin
  act := TTyToolWindowActions.Create(FForm);
  { 两个 KeepChild 标志:用户在对象查看器里开 AutoSize,TWinControl.DoAutoSize 会把
    子控件往左上挪,和自己的排列互相覆盖。 }
  AssertTrue('要能装子控件', csAcceptsControls in act.ControlStyle);
  AssertTrue('设计器里不许拖动改尺寸 —— 位置归窗口管', csDesignFixedBounds in act.ControlStyle);
  AssertTrue('自己不抢焦点', csNoFocus in act.ControlStyle);
  AssertTrue('AutoSize 不许挪子控件的左边', csAutoSizeKeepChildLeft in act.ControlStyle);
  AssertTrue('AutoSize 不许挪子控件的上边', csAutoSizeKeepChildTop in act.ControlStyle);
  AssertEquals('出生就是 alCustom —— 位置由所在窗口的 CustomAlignPosition 定',
    Ord(alCustom), Ord(act.Align));
  AssertFalse('Align 不进对象查看器', IsPublishedProp(act, 'Align'));
  AssertFalse('Anchors 不进对象查看器', IsPublishedProp(act, 'Anchors'));
  act.Controller := FCtl;
  act.Parent := FWin;
  { 窗口里的操作区,位置尺寸每次都由标题行排出来,进了 .lfm 只会跟算出来的漂开。 }
  for i := Low(Bounds) to High(Bounds) do
    AssertFalse(Bounds[i] + ' 在窗口里由标题行说了算,不许进 .lfm', IsStoredProp(act, Bounds[i]));
  AssertFalse('Controller 由窗口推送,不进 .lfm', IsStoredProp(act, 'Controller'));
  { 孤儿(粘贴、撤销删除后被建到窗体上)的位置是用户摆的,不存就丢。 }
  act.Parent := FForm;
  for i := Low(Bounds) to High(Bounds) do
    AssertTrue(Bounds[i] + ' 不在窗口里时照常存', IsStoredProp(act, Bounds[i]));
  AssertFalse('Controller 在哪儿都不存', IsStoredProp(act, 'Controller'));
end;

procedure TTyToolWindowActionsTests.TestAnEmptyActionsAreaTakesNoWidthAtRunTime;
var
  act: TProbeActions;
  sz: TSize;
  w, h: Integer;
begin
  act := NewActions(FWin);
  sz := act.PreferredSizeAt(96);
  AssertEquals('运行时一个可见子控件都没有 → 宽 0', 0, sz.cx);
  AssertEquals('也不许把标题行撑高', 0, sz.cy);
  { LCL 那条路也答同一个数 —— 必须是 raw:非 raw 的 GetPreferredSize 会把 0 换成
    75px 的默认宽(control.inc:5609-5643),空操作区会平白吃掉一截标题。 }
  w := -1;
  h := -1;
  act.GetPreferredSize(w, h, True);
  AssertEquals('raw 首选宽也是 0', 0, w);
  AssertEquals('标题行里不给它留位置', 0, FWin.HeaderInput(96, 200).ActionsWidth);
  AssertEquals('标题行高退化成 token', TyToolWindowHeaderHeightDef, FWin.HeaderHeightPx);
end;

procedure TTyToolWindowActionsTests.TestPreferredWidthIsPadsPlusChildrenPlusGaps;
var
  act: TProbeActions;
  b2: TBodyChild;
  w, h: Integer;
begin
  act := NewActions(FWin);
  NewChild(act, 20, 18);
  b2 := NewChild(act, 30, 18);
  { 2×pad + 20 + 30 + 1×gap,pad/gap 取 light.tycss 的经典值 6/4。 }
  AssertEquals('宽 = 2×内距 + 子控件宽之和 + (n-1)×间距',
    2 * TyToolWindowHeaderPadDef + 50 + TyToolWindowHeaderGapDef, act.PreferredSizeAt(96).cx);
  AssertEquals('高 = 最高子控件 + 2×内距',
    18 + 2 * TyToolWindowHeaderPadDef, act.PreferredSizeAt(96).cy);
  w := 0;
  h := 0;
  act.GetPreferredSize(w, h, True);
  AssertEquals('LCL 那条路(raw)答同一个宽', act.PreferredSizeAt(96).cx, w);
  AssertEquals('按给定 PPI 缩放', 2 * act.PreferredSizeAt(96).cx, act.PreferredSizeAt(192).cx);
  b2.Visible := False;
  AssertEquals('隐藏的子控件不算',
    2 * TyToolWindowHeaderPadDef + 20, act.PreferredSizeAt(96).cx);
  AssertEquals('窗口排标题行时拿的就是这个宽',
    2 * TyToolWindowHeaderPadDef + 20, FWin.HeaderInput(96, 200).ActionsWidth);
end;

procedure TTyToolWindowActionsTests.TestTheAreaIgnoresAlignAndSitsAtTheTrailingEndOfTheHeader;
var
  act: TProbeActions;
  btn: TBodyChild;
begin
  act := NewActions(FWin);
  { 12px 高:raw 高 24 < token 26。拿 18px 的话 raw 高 30 > 26,「高 = 标题行高」和
    「高 = 自己的 raw 高」恰好是同一个数,分不出操作区到底是不是被标题行撑满的。 }
  btn := NewChild(act, 40, 12);
  act.Align := alClient;        { 用户乱设也没用 }
  AssertEquals('Align 钉死在 alCustom', Ord(alCustom), Ord(act.Align));
  FWin.CallAlignControls;
  { spec §3.4:「操作区自带内边距,宽为 0 时尾端补一个 header-pad」。这里原先断言的是
    200 - pad —— 那是几何层无条件多留的一个 pad,测试把 bug 本身钉住了。 }
  AssertEquals('贴到标题行的右端,不再补尾端 pad(§3.4:操作区自带内边距)', 200, act.Left + act.Width);
  AssertEquals('宽就是 raw 首选宽', 2 * TyToolWindowHeaderPadDef + 40, act.Width);
  AssertEquals('在标题行里', 0, act.Top);
  AssertEquals('前提:标题行就是 token 高', TyToolWindowHeaderHeightDef, FWin.HeaderHeightPx);
  AssertEquals('高被标题行撑满(token 26),不是自己的 raw 高 24', TyToolWindowHeaderHeightDef, act.Height);
  { 用户看得见的那个数:最后一个按钮离窗口右边正好一个 pad(它自己的内边距),不是两个。 }
  act.CallAlignControls;
  AssertEquals('最后一个按钮离右边一个 pad,不是两个(§3.4)',
    200 - TyToolWindowHeaderPadDef, act.Left + btn.Left + btn.Width);
end;

procedure TTyToolWindowActionsTests.TestATallChildGrowsTheHeaderRow;
var
  act: TProbeActions;
  body, floored: TBodyChild;
begin
  body := TBodyChild.Create(FForm);
  body.Parent := FWin;
  body.Align := alClient;
  act := NewActions(FWin);
  { 最高的放在**中间**:放在最后的话,「取最后一个可见子控件的高」这种错实现照样绿。 }
  floored := NewChild(act, 20, 12);
  NewChild(act, 20, 40);
  NewChild(act, 20, 18);
  { 比 token(26)高的子控件把标题行撑高:行高 = max(token, 操作区 raw 首选高)。 }
  AssertEquals('标题行 = 最高子控件 + 2×内距', 40 + 2 * TyToolWindowHeaderPadDef, FWin.HeaderHeightPx);
  FWin.CallAlignControls;
  AssertEquals('正文跟着往下让', 40 + 2 * TyToolWindowHeaderPadDef, body.Top);
  AssertEquals('操作区占整条标题行高', 40 + 2 * TyToolWindowHeaderPadDef, act.Height);
  { MinHeight 也算:子控件自己矮,下限高,按下限撑。挑的是**第一个**,同样不是最后一个。 }
  floored.Constraints.MinHeight := 50;
  AssertTrue('前提:子控件此刻真的比下限矮(否则下面一条证明不了下限)', floored.Height < 50);
  AssertEquals('MinHeight 撑高标题行', 50 + 2 * TyToolWindowHeaderPadDef, FWin.HeaderHeightPx);
end;

procedure TTyToolWindowActionsTests.TestTheFlowCentresEachChildAndClipsTheLeadingOnesWhenNarrow;
var
  act: TProbeActions;
  a, b: TBodyChild;
  content: Integer;
begin
  act := NewActions(FWin);
  a := NewChild(act, 30, 18);
  b := NewChild(act, 30, 12);
  content := 2 * TyToolWindowHeaderPadDef + 60 + TyToolWindowHeaderGapDef;
  act.SetBounds(0, 0, content, 26);
  act.CallAlignControls;
  AssertEquals('放得下时从前导内距开始', TyToolWindowHeaderPadDef, a.Left);
  AssertEquals('按 Controls[] 顺序、隔一个间距',
    TyToolWindowHeaderPadDef + 30 + TyToolWindowHeaderGapDef, b.Left);
  AssertEquals('第一个垂直居中', (26 - 18) div 2, a.Top);
  AssertEquals('第二个也按自己的高居中', (26 - 12) div 2, b.Top);
  { 窄到放不下:整排贴尾端,裁掉的是开头的控件 —— 尾端的操作最常用。 }
  act.SetBounds(0, 0, 50, 26);
  act.CallAlignControls;
  AssertEquals('最后一个仍然贴着尾端内距', 50 - TyToolWindowHeaderPadDef, b.Left + b.Width);
  AssertEquals('第一个被推到左边外面', 50 - content + TyToolWindowHeaderPadDef, a.Left);
  AssertTrue('被裁掉的是开头那个', a.Left < 0);
end;

procedure TTyToolWindowActionsTests.TestTheFlowIsMirroredUnderRightToLeft;
var
  act: TProbeActions;
  a, b: TBodyChild;
  content: Integer;
begin
  act := NewActions(FWin);
  a := NewChild(act, 30, 18);
  b := NewChild(act, 20, 18);
  { 方向从窗口一路继承下来,用户只会在窗体上设一次。 }
  FWin.BiDiMode := bdRightToLeft;
  AssertTrue('操作区跟着窗口从右往左', act.IsRightToLeft);
  content := 2 * TyToolWindowHeaderPadDef + 50 + TyToolWindowHeaderGapDef;
  act.SetBounds(0, 0, content, 26);
  act.CallAlignControls;
  AssertEquals('第一个排在右端(前导边)', content - TyToolWindowHeaderPadDef - 30, a.Left);
  AssertEquals('第二个在它左边', TyToolWindowHeaderPadDef, b.Left);
  { 窄了照样贴尾端 —— 从右往左读,尾端在左;被裁的仍是开头那个,从右边伸出去。 }
  act.SetBounds(0, 0, 40, 26);
  act.CallAlignControls;
  AssertEquals('最后一个贴着左边(尾端)的内距', TyToolWindowHeaderPadDef, b.Left);
  AssertTrue('开头那个从右边伸出去', a.Left + a.Width > 40);
end;

procedure TTyToolWindowActionsTests.TestRightToLeftPutsTheActionsLeftAndTheCaptionRightOfIt;
var
  act: TProbeActions;
  g: TTyToolWindowHeaderGeom;
begin
  { Task 3 时标题占整条、镜像前后同一个矩形,RTL 只有接线断言守着。操作区一进来,
    镜像就是看得见的位置差。 }
  act := NewActions(FWin);
  NewChild(act, 40, 18);
  FWin.BiDiMode := bdRightToLeft;
  FWin.CallAlignControls;
  AssertEquals('从右往左读:操作区贴到左端(尾端),不补 pad(§3.4:操作区自带内边距)', 0, act.Left);
  AssertEquals('宽不变', 2 * TyToolWindowHeaderPadDef + 40, act.Width);
  g := FWin.HeaderGeomAt(Rect(0, 0, 200, 300), 96);
  AssertTrue('标题在操作区右边,中间隔一个间距',
    g.Caption.Left >= act.Left + act.Width + TyToolWindowHeaderGapDef);
  AssertEquals('标题拿下右边那一截,到前导内距为止', 200 - TyToolWindowHeaderPadDef, g.Caption.Right);
end;

procedure TTyToolWindowActionsTests.TestChildClassAllowedRejectsTheWorkbenchClasses;
var
  act: TProbeActions;
  inner: TTyToolWindowActions;
  raised: Boolean;
begin
  act := NewActions(FWin);
  { 用子类问:拿 = 比类的实现会放过 TProbeWindow / TProbeActions 这样的派生类。 }
  AssertFalse('不许装工具窗口', act.CheckChildClassAllowed(TProbeWindow, False));
  AssertFalse('不许装栏', act.CheckChildClassAllowed(TTyToolWindowBar, False));
  AssertFalse('不许装另一个操作区', act.CheckChildClassAllowed(TProbeActions, False));
  AssertTrue('普通控件照收', act.CheckChildClassAllowed(TBodyChild, False));
  inner := TTyToolWindowActions.Create(FForm);
  raised := False;
  try
    inner.Parent := act;
  except
    on EInvalidOperation do raised := True;
  end;
  AssertTrue('运行时硬塞进去要被 LCL 拦下', raised);
  AssertTrue('拦下之后它不在里面', inner.Parent <> TWinControl(act));
end;

procedure TTyToolWindowActionsTests.TestOnlyTheFirstActionsAreaGoesIntoTheHeader;
var
  first, extra: TProbeActions;
begin
  { 第一个矮到撑不高标题行(12 + 2×6 < 26),多出来的那个比 token 高(30 + 2×6 = 42):
    行高只要算进了它就不是 26。 }
  first := NewActions(FWin);
  NewChild(first, 40, 12);
  extra := NewActions(FWin);
  NewChild(extra, 90, 30);
  extra.SetBounds(3, 150, 10, 10);
  AssertTrue('Actions 是 Controls[] 里的第一个', FWin.Actions = TTyToolWindowActions(first));
  AssertEquals('标题行只给第一个留宽',
    2 * TyToolWindowHeaderPadDef + 40, FWin.HeaderInput(96, 200).ActionsWidth);
  AssertEquals('标题行高也只看第一个', TyToolWindowHeaderHeightDef, FWin.HeaderHeightPx);
  AssertTrue('第一个照常露面', first.IsControlVisible);
  AssertFalse('多出来的运行时不露面', extra.IsControlVisible);
  AssertTrue('只是不露面,Visible 本身没被改写(不会写进 .lfm)', extra.Visible);
  FWin.CallAlignControls;
  AssertEquals('第一个贴到标题行右端(§3.4:操作区自带内边距,尾端不补 pad)', 200, first.Left + first.Width);
  AssertEquals('多出来的不被摆动', 3, extra.Left);
  AssertEquals('多出来的不被摆动', 150, extra.Top);
  { 上面那两条标题行断言在运行时被「多出来的不露面」遮住了:「取所有可见操作区的最大值」
    这种错实现照样绿。设计期多出来的那个看得见,再问一遍。 }
  extra.MarkDesigning(True);
  AssertTrue('前提:设计期多出来的那个看得见', extra.IsControlVisible);
  AssertEquals('设计期标题行也只给第一个留宽',
    2 * TyToolWindowHeaderPadDef + 40, FWin.HeaderInput(96, 200).ActionsWidth);
  AssertEquals('设计期标题行高也只看第一个', TyToolWindowHeaderHeightDef, FWin.HeaderHeightPx);
end;

procedure TTyToolWindowActionsTests.TestAStrayAreaSitsAtTheBodyTopLeftAtDesignTime;
var
  first, extra: TProbeActions;
  body: TRect;
  hdr: Integer;
begin
  first := NewActions(FWin);
  NewChild(first, 40, 40);
  extra := NewActions(FWin);
  extra.MarkDesigning(True);
  AssertTrue('设计期看得见,好让人发现它', extra.IsControlVisible);
  hdr := FWin.HeaderHeightPx;
  AssertEquals('前提:标题行被第一个撑到比 token 高', 40 + 2 * TyToolWindowHeaderPadDef, hdr);
  FWin.CallAlignControls;
  body := FWin.BodyRect;
  AssertEquals('正文区左上角(左)', body.Left, extra.Left);
  AssertEquals('正文区左上角(上)——在标题行下面', hdr, extra.Top);
  { 边长取 token 本身,不取标题行高:后者本来就是 max(token, 操作区),定义会绕回自己。
    摆出来的宽要放得下提示文字,另见 TestAStrayAreaIsWideEnoughForItsNoteAtDesignTimeOnly。 }
  AssertEquals('设计期空着:raw 是一个 token 边长的方槽(宽)',
    TyToolWindowHeaderHeightDef, extra.PreferredSizeAt(96).cx);
  AssertEquals('设计期空着:raw 是一个 token 边长的方槽(高)',
    TyToolWindowHeaderHeightDef, extra.PreferredSizeAt(96).cy);
  AssertEquals('摆出来的高 = max(raw 高, token),不是标题行高', TyToolWindowHeaderHeightDef, extra.Height);
  AssertEquals('第一个照样在标题行里,贴到右端(§3.4)', 200, first.Left + first.Width);
end;

procedure TTyToolWindowActionsTests.TestAnOrphanIsHiddenAtRunTimeOnly;
var
  orphan: TProbeActions;
begin
  orphan := NewActions(FForm);
  AssertFalse('孤儿运行时不露面', orphan.IsControlVisible);
  AssertTrue('只是不露面,Visible 本身没被改写', orphan.Visible);
  orphan.MarkDesigning(True);
  AssertTrue('设计期看得见', orphan.IsControlVisible);
  orphan.MarkDesigning(False);
  orphan.Parent := FWin;
  AssertTrue('放回窗口里就是那个操作区,照常露面', orphan.IsControlVisible);
end;

procedure TTyToolWindowActionsTests.TestDesignTimeDrawsTheSlotAndTheNoteOnlyWhereTheyBelong;
var
  first, extra, orphan: TProbeActions;
  red, blue: Integer;
begin
  { 提示文字钉成纯红、描边钉成纯蓝、底色钉成白,互相不会数混。
    每一个都按**窗口(或用户)实际给它的尺寸**画 —— 画进一张随手挑的宽位图,证明的只是
    「文字存在」,证明不了「看得见」。 }
  FCtl.StyleOverride := ':root { --border: #0000FF; }' +
    'TyToolWindowActions { background: #FFFFFF; }' +
    'TyToolWindowNote { color: #FF0000; }';
  first := NewActions(FWin);
  extra := NewActions(FWin);
  orphan := NewActions(FForm);
  first.MarkDesigning(True);
  extra.MarkDesigning(True);
  orphan.MarkDesigning(True);
  orphan.SetBounds(0, 0, 75, 50);   { 撤销删除后建到窗体上的就是 LCL 默认的 75×50 }
  FWin.CallAlignControls;
  AssertTrue('前提:窗口给了第一个一块地方', (first.Width > 0) and (first.Height > 0));
  TallyActionsInk(first, first.Width, first.Height, red, blue);
  AssertTrue('设计期空着的操作区描一个槽位,方便往里拖控件', blue > 0);
  AssertEquals('窗口认的那一个不画提示', 0, red);
  TallyActionsInk(extra, extra.Width, extra.Height, red, blue);
  AssertTrue('多出来的画提示', red > 0);
  TallyActionsInk(orphan, orphan.Width, orphan.Height, red, blue);
  AssertTrue('孤儿画提示', red > 0);
  NewChild(first, 20, 18);
  FWin.CallAlignControls;
  TallyActionsInk(first, first.Width, first.Height, red, blue);
  AssertEquals('有了子控件就不再描槽位', 0, blue);
end;

procedure TTyToolWindowActionsTests.TestAnActionsChangeDropsTheWindowPaintCache;
var
  act: TProbeActions;
begin
  { 操作区变宽 / 变高,标题的省略号和标题行那条底色都跟着变,而窗口的尺寸一个像素
    没动 —— NeedsRender 答「不用」,运行时 blit 的就是旧的那一帧;设计期不走缓存,
    在设计器里看是好的。 }
  act := NewActions(FWin);
  NewChild(act, 20, 18);
  FWin.CallAlignControls;
  FWin.PrimeCache(200, 300);
  FWin.CallAlignControls;
  AssertFalse('什么都没变的重排不丢缓存', FWin.CacheWouldRender(200, 300));
  NewChild(act, 20, 40);
  FWin.CallAlignControls;
  AssertTrue('操作区变了,缓存里那一帧的标题行作废', FWin.CacheWouldRender(200, 300));
end;

procedure TTyToolWindowActionsTests.TestEnsureActionsCreatesOnceAndOwnsItLikeADesignContainer;
var
  act, again, a1: TTyToolWindowActions;
  w2: TProbeWindow;
  loose: TTyToolWindow;
  i, n: Integer;
begin
  { 先放一个正文子控件占住 TabOrder 0 —— 否则新建的那个本来就是 0,这条证明不了什么。 }
  NewChild(FWin, 10, 10).TabOrder := 0;
  AssertTrue('开始时没有操作区', FWin.Actions = nil);
  act := FWin.EnsureActions;
  AssertTrue('没有就建一个', act <> nil);
  AssertTrue('Owner 是窗口的 Owner —— 窗体拥有,设计期容器的契约', act.Owner = TComponent(FForm));
  AssertTrue('Parent 是窗口', act.Parent = TWinControl(FWin));
  AssertEquals('TabOrder 0', 0, act.TabOrder);
  again := FWin.EnsureActions;
  AssertTrue('再调一次返回同一个', again = act);
  n := 0;
  for i := 0 to FWin.ControlCount - 1 do
    if FWin.Controls[i] is TTyToolWindowActions then Inc(n);
  AssertEquals('只建了一个', 1, n);
  AssertTrue('建完之后 Actions 就是它', FWin.Actions = act);
  AssertTrue('窗口把自己的控制器给了它', act.Controller = FCtl);
  NewChild(act, 40, 18);
  AssertEquals('标题行给它留了位置',
    2 * TyToolWindowHeaderPadDef + 40, FWin.HeaderInput(96, 200).ActionsWidth);
  { 已经有(不止一个)的时候返回第一个,不另建。 }
  w2 := TProbeWindow.Create(FForm);
  w2.Parent := FBar;
  a1 := NewActions(w2);
  NewActions(w2);
  AssertTrue('已有就返回第一个', w2.EnsureActions = a1);
  AssertEquals('不另建', 2, w2.ControlCount);
  { 代码里 Create(nil) 的窗口:LCL 不释放没有 Owner 的子控件(TWinControl.Destroy 只把它们
    摘下来),所以照 TTyPageControl 建页的规矩回落到窗口自己。 }
  loose := TTyToolWindow.Create(nil);
  try
    AssertTrue('窗口没有 Owner 时由窗口自己拥有,不泄漏', loose.EnsureActions.Owner = TComponent(loose));
  finally
    loose.Free;
  end;
end;

procedure TTyToolWindowActionsTests.TestWithoutAHeaderTheActionsSitTopLeftAtRawSize;
var
  act: TProbeActions;
begin
  { 孤儿窗口(不在栏里)没有标题行:不问栏、不问几何(它对 twhNone 什么都不排,问了就是
    0×0),操作区按 raw 首选尺寸放在左上角(spec §3.2)。 }
  FWin.Parent := FForm;
  AssertTrue('前提:没有标题行', FWin.HeaderMode = twhNone);
  act := NewActions(FWin);
  NewChild(act, 40, 18);
  FWin.CallAlignControls;
  AssertEquals('左上角(左)', 0, act.Left);
  AssertEquals('左上角(上)', 0, act.Top);
  AssertEquals('raw 首选宽', 2 * TyToolWindowHeaderPadDef + 40, act.Width);
  AssertEquals('raw 首选高', 18 + 2 * TyToolWindowHeaderPadDef, act.Height);
end;

procedure TTyToolWindowActionsTests.TestTheFlowFloorsEachChildAtItsMinHeight;
var
  act: TProbeActions;
  c: TBodyChild;
begin
  act := NewActions(FWin);
  c := NewChild(act, 30, 10);
  c.Constraints.MinHeight := 20;
  AssertTrue('前提:子控件此刻真的比下限矮', c.Height < 20);
  act.SetBounds(0, 0, 2 * TyToolWindowHeaderPadDef + 30, 26);
  act.CallAlignControls;
  AssertEquals('排出来的高不低于 MinHeight', 20, c.Height);
  { 高度本身 LCL 的约束也会钳上去,看不出排列有没有按下限算;居中的位置看得出来。 }
  AssertEquals('按下限的高居中,不是按自己那 10px', (26 - 20) div 2, c.Top);
end;

procedure TTyToolWindowActionsTests.TestDesignTimeCountsChildrenTheUserHid;
var
  act: TProbeActions;
  k1, k2: TDesignChild;
  content: Integer;
begin
  act := NewActions(FWin);
  k1 := TDesignChild.Create(FForm);
  k1.Parent := act;
  k1.SetBounds(0, 0, 20, 18);
  k2 := TDesignChild.Create(FForm);
  k2.Parent := act;
  k2.SetBounds(0, 0, 30, 18);
  act.MarkDesigning(True);
  k1.MarkDesigning(True);
  k2.MarkDesigning(True);
  k2.Visible := False;
  { 设计器里 Visible=False 的控件照样画出来、照样能点 —— 不给它留位置,它就叠在别人身上。 }
  content := 2 * TyToolWindowHeaderPadDef + 50 + TyToolWindowHeaderGapDef;
  AssertEquals('设计期藏起来的子控件照样算宽', content, act.PreferredSizeAt(96).cx);
  act.SetBounds(0, 0, content, 26);
  act.CallAlignControls;
  AssertEquals('照样排进这一排', TyToolWindowHeaderPadDef + 20 + TyToolWindowHeaderGapDef, k2.Left);
  k2.MarkDesigning(False);
  k1.MarkDesigning(False);
  act.MarkDesigning(False);
  AssertEquals('运行时就不算了', 2 * TyToolWindowHeaderPadDef + 20, act.PreferredSizeAt(96).cx);
end;

procedure TTyToolWindowActionsTests.TestAStrayAreaIsWideEnoughForItsNoteAtDesignTimeOnly;
const
  Wide = 4000;
var
  first, extra, orphan, runtime: TProbeActions;
  fitRed, fullRed, blue: Integer;
begin
  { 设计期的多余操作区和孤儿:尺寸取 max(raw, 提示宽 + 2×pad) × max(raw 高, token)。
    判据是「按给它的尺寸画出来的提示,和画进一张宽得离谱的位图一样多」—— 少了就是
    被省略号截掉了。 }
  FCtl.StyleOverride := 'TyToolWindowActions { background: #FFFFFF; }' +
    'TyToolWindowNote { color: #FF0000; }';
  first := NewActions(FWin);
  NewChild(first, 40, 40);     { 标题行撑到 52,好分辨「token 高」和「标题行高」 }
  extra := NewActions(FWin);
  extra.MarkDesigning(True);
  FWin.CallAlignControls;
  AssertTrue('比 raw 那个方槽宽', extra.Width > TyToolWindowHeaderHeightDef);
  AssertEquals('高 = max(raw 高, token),不是标题行高', TyToolWindowHeaderHeightDef, extra.Height);
  TallyActionsInk(extra, extra.Width, extra.Height, fitRed, blue);
  TallyActionsInk(extra, Wide, extra.Height, fullRed, blue);
  AssertTrue('前提:提示真的画出来了', fullRed > 0);
  AssertEquals('多出来的:按窗口给的尺寸画,提示一个字都不少', fullRed, fitRed);

  orphan := NewActions(FForm);
  orphan.MarkDesigning(True);
  orphan.SetBounds(10, 10, 75, 50);   { 撤销删除后建到窗体上的就是 LCL 默认的 75×50 }
  AssertTrue('孤儿被撑宽', orphan.Width > 75);
  AssertEquals('高已经够了就不动', 50, orphan.Height);
  TallyActionsInk(orphan, orphan.Width, orphan.Height, fitRed, blue);
  TallyActionsInk(orphan, Wide, orphan.Height, fullRed, blue);
  AssertEquals('孤儿:按它的尺寸画,提示一个字都不少', fullRed, fitRed);

  { 运行时它们本来就不露面,尺寸也不碰。 }
  runtime := NewActions(FForm);
  runtime.SetBounds(10, 10, 75, 50);
  AssertEquals('运行时的孤儿保持原宽', 75, runtime.Width);
  AssertEquals('运行时的孤儿保持原高', 50, runtime.Height);
end;

procedure TTyToolWindowActionsTests.TestTheNoteOfAStrayAreaNeverSitsUnderItsChildren;
var
  first, extra, bare: TProbeActions;
  a, b: TBodyChild;
  note, tmp: TRect;
  row, fitRed, fullRed, blue: Integer;
begin
  { 粘贴一个现成的操作区,进来的就是带按钮的多余操作区(spec §4 点名的场景)。提示要排在
    子控件那一排的后面:[子控件那一排][gap][提示][pad],RTL 整体镜像。
    判据是矩形不相交,不是数墨迹 —— RenderTo 不画子控件,数墨迹永远看不见重叠。
    NoteRect 就是 RenderTo 画提示用的那个框(同一个函数),不是另算的。 }
  FCtl.StyleOverride := 'TyToolWindowActions { background: #FFFFFF; }' +
    'TyToolWindowNote { color: #FF0000; }';
  first := NewActions(FWin);
  NewChild(first, 20, 12);
  extra := NewActions(FWin);
  a := NewChild(extra, 30, 18);
  b := NewChild(extra, 24, 18);
  bare := NewActions(FWin);          { 同一句提示、没有子控件:拿它的宽当「pad + 提示宽 + pad」 }
  extra.MarkDesigning(True);
  bare.MarkDesigning(True);
  FWin.CallAlignControls;            { 窗口给尺寸,设计期下限在这一步起作用 }
  extra.CallAlignControls;           { 它自己排子控件 }
  row := 2 * TyToolWindowHeaderPadDef + 30 + 24 + TyToolWindowHeaderGapDef;
  AssertEquals('宽 = raw 首选宽 + gap + 提示宽 + pad',
    row + TyToolWindowHeaderGapDef + (bare.Width - TyToolWindowHeaderPadDef), extra.Width);
  note := extra.NoteRect;
  AssertTrue('提示要有地方', note.Right > note.Left);
  AssertFalse('提示不压第一个子控件', IntersectRect(tmp, note, a.BoundsRect));
  AssertFalse('提示不压第二个子控件', IntersectRect(tmp, note, b.BoundsRect));
  AssertTrue('子控件从前导边照常排', a.Left = TyToolWindowHeaderPadDef);
  AssertTrue('提示在子控件那一排后面', note.Left >= b.Left + b.Width);
  TallyActionsInk(extra, extra.Width, extra.Height, fitRed, blue);
  TallyActionsInk(extra, 4000, extra.Height, fullRed, blue);
  AssertTrue('前提:提示真的画出来了', fullRed > 0);
  AssertEquals('按窗口给的尺寸画,提示一个字都不少', fullRed, fitRed);
  { 从右往左读:整体镜像 —— 子控件到右边,提示在它们左边。 }
  FWin.BiDiMode := bdRightToLeft;
  FWin.CallAlignControls;
  extra.CallAlignControls;
  note := extra.NoteRect;
  AssertTrue('RTL:提示要有地方', note.Right > note.Left);
  AssertFalse('RTL:提示不压第一个子控件', IntersectRect(tmp, note, a.BoundsRect));
  AssertFalse('RTL:提示不压第二个子控件', IntersectRect(tmp, note, b.BoundsRect));
  AssertTrue('RTL:子控件在右边', a.Left + a.Width = extra.Width - TyToolWindowHeaderPadDef);
  AssertTrue('RTL:提示在子控件那一排左边', note.Right <= b.Left);
end;

procedure TTyToolWindowActionsTests.TestEnsureActionsMeasuresWithTheWindowController;
var
  act: TTyToolWindowActions;
begin
  { 专门**不**手工设控制器(NewActions 设了,会把这个缺口遮住):窗口按自己的控制器读
    pad 给操作区留位,操作区若按 TyDefaultController 量自己,留的宽就是另一套主题下的。 }
  FCtl.StyleOverride := ':root { --toolwindow-header-pad: 10px; }';
  act := FWin.EnsureActions;
  NewChild(act, 40, 18);
  AssertEquals('前提:窗口读到的是改过的 pad', 10, FWin.HeaderInput(96, 200).Pad);
  AssertEquals('操作区按窗口的控制器量:2×10 + 40', 2 * 10 + 40, act.PreferredSizeAt(96).cx);
  AssertEquals('标题行留的宽也是这个', 2 * 10 + 40, FWin.HeaderInput(96, 200).ActionsWidth);
end;

procedure TTyToolWindowActionsTests.TestAChildMinWidthWidensItsSlotInTheFlow;
var
  act: TProbeActions;
  a, b: TBodyChild;
begin
  { TTyButton 按标题设 MinWidth(Button.pas:702),SetBounds 会把它撑得比 Width 宽。
    只按 Width 排的话,撑宽的那个压到下一个身上,首选宽也少算一截。 }
  act := NewActions(FWin);
  a := NewChild(act, 20, 18);
  a.Constraints.MinWidth := 40;
  b := NewChild(act, 30, 18);
  AssertTrue('前提:子控件此刻真的比下限窄', a.Width < 40);
  AssertEquals('首选宽按 max(Width, MinWidth)',
    2 * TyToolWindowHeaderPadDef + 40 + 30 + TyToolWindowHeaderGapDef, act.PreferredSizeAt(96).cx);
  act.SetBounds(0, 0, act.PreferredSizeAt(96).cx, 26);
  act.CallAlignControls;
  AssertEquals('第一个按下限的宽排', 40, a.Width);
  AssertEquals('第二个排在撑宽之后的那个后面,不压上去',
    TyToolWindowHeaderPadDef + 40 + TyToolWindowHeaderGapDef, b.Left);
end;

procedure TTyToolWindowActionsTests.TestTheAreaOwnConstraintsReachTheHeader;
var
  act: TProbeActions;
begin
  { 操作区自己的 Constraints 是 published 的,LCL 却在 CustomAlignPosition 之后才施加
    (wincontrol.inc:3081-3082):标题行按没抬过的宽留位,施加之后它伸出行外、压住标题。 }
  act := NewActions(FWin);
  NewChild(act, 20, 12);
  act.Constraints.MinWidth := 80;
  act.Constraints.MinHeight := 40;
  AssertEquals('首选宽抬到自己的 MinWidth', 80, act.PreferredSizeAt(96).cx);
  AssertEquals('首选高抬到自己的 MinHeight', 40, act.PreferredSizeAt(96).cy);
  AssertEquals('标题行按抬过的宽留位', 80, FWin.HeaderInput(96, 200).ActionsWidth);
  AssertEquals('标题行按抬过的高', 40, FWin.HeaderHeightPx);
  FWin.CallAlignControls;
  AssertEquals('施加完约束仍是这个宽', 80, act.Width);
  AssertEquals('施加完约束仍贴着行的右端,不伸出去', 200, act.Left + act.Width);
end;

procedure TTyToolWindowActionsTests.TestDraggingIntoADesignTimeOrphanReappliesItsFloor;
var
  orphan: TProbeActions;
  a, b: TBodyChild;
  bare, row: Integer;
  note, tmp: TRect;
begin
  { 没人摆孤儿:ConstrainedResize 只在它自己的边界被设时才跑。设计期往里拖子控件之后,
    下限得由它自己排子控件那一遍重新施加,否则提示停在省略号。 }
  orphan := NewActions(FForm);
  orphan.MarkDesigning(True);
  orphan.SetBounds(10, 10, 75, 50);
  bare := orphan.Width;              { pad + 提示宽 + pad }
  AssertTrue('前提:空着的孤儿已经撑到放得下提示', bare > 75);
  a := NewChild(orphan, 30, 18);
  b := NewChild(orphan, 24, 18);
  AssertEquals('前提:拖进来的那一刻没人改它的尺寸', bare, orphan.Width);
  orphan.CallAlignControls;          { LCL 对孤儿只会请它自己排子控件 }
  row := 2 * TyToolWindowHeaderPadDef + 30 + 24 + TyToolWindowHeaderGapDef;
  AssertEquals('排子控件那一遍把下限重新施加:raw 宽 + gap + 提示宽 + pad',
    row + TyToolWindowHeaderGapDef + (bare - TyToolWindowHeaderPadDef), orphan.Width);
  orphan.CallAlignControls;          { 尺寸变了之后 LCL 按新客户区再请的那一遍 }
  note := orphan.NoteRect;
  AssertTrue('提示要有地方', note.Right > note.Left);
  AssertFalse('提示不压第一个子控件', IntersectRect(tmp, note, a.BoundsRect));
  AssertFalse('提示不压第二个子控件', IntersectRect(tmp, note, b.BoundsRect));
end;

initialization
  RegisterTest(TTyToolWindowActionsTests);
end.
