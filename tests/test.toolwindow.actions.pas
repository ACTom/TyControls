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
  test.toolwindow.window;

type
  TProbeActions = class(TTyToolWindowActions)
  public
    procedure MarkDesigning(AOn: Boolean);
    procedure CallAlignControls;
    procedure CallRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
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
  end;

implementation

procedure TProbeActions.MarkDesigning(AOn: Boolean);
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
    AAct.CallRenderTo(bmp.Canvas, Rect(0, 0, AW, AH), 96);
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
begin
  act := NewActions(FWin);
  NewChild(act, 40, 18);
  act.Align := alClient;        { 用户乱设也没用 }
  AssertEquals('Align 钉死在 alCustom', Ord(alCustom), Ord(act.Align));
  FWin.CallAlignControls;
  AssertEquals('贴标题行尾端,留一个内距', 200 - TyToolWindowHeaderPadDef, act.Left + act.Width);
  AssertEquals('宽就是 raw 首选宽', 2 * TyToolWindowHeaderPadDef + 40, act.Width);
  AssertEquals('在标题行里', 0, act.Top);
  AssertEquals('高就是标题行高', FWin.HeaderHeightPx, act.Height);
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
  NewChild(act, 20, 40);
  { 比 token(26)高的子控件把标题行撑高:行高 = max(token, 操作区 raw 首选高)。 }
  AssertEquals('标题行 = 最高子控件 + 2×内距', 40 + 2 * TyToolWindowHeaderPadDef, FWin.HeaderHeightPx);
  FWin.CallAlignControls;
  AssertEquals('正文跟着往下让', 40 + 2 * TyToolWindowHeaderPadDef, body.Top);
  AssertEquals('操作区占整条标题行高', 40 + 2 * TyToolWindowHeaderPadDef, act.Height);
  { MinHeight 也算:子控件自己矮,下限高,按下限撑。 }
  floored := NewChild(act, 20, 10);
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
  AssertEquals('从右往左读:操作区贴左端(尾端)', TyToolWindowHeaderPadDef, act.Left);
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
  AssertEquals('第一个在标题行尾端', 200 - TyToolWindowHeaderPadDef, first.Left + first.Width);
  AssertEquals('多出来的不被摆动', 3, extra.Left);
  AssertEquals('多出来的不被摆动', 150, extra.Top);
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
  { 边长取 token 本身,不取标题行高:后者本来就是 max(token, 操作区),定义会绕回自己。 }
  AssertEquals('设计期空着:一个 token 边长的方槽(宽)', TyToolWindowHeaderHeightDef, extra.Width);
  AssertEquals('设计期空着:一个 token 边长的方槽(高)', TyToolWindowHeaderHeightDef, extra.Height);
  AssertEquals('第一个照样在标题行里', 200 - TyToolWindowHeaderPadDef, first.Left + first.Width);
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
const
  W = 320;
var
  first, extra, orphan: TProbeActions;
  red, blue: Integer;
begin
  { 提示文字钉成纯红、描边钉成纯蓝、底色钉成白,互相不会数混。 }
  FCtl.StyleOverride := ':root { --border: #0000FF; }' +
    'TyToolWindowActions { background: #FFFFFF; }' +
    'TyToolWindowNote { color: #FF0000; }';
  first := NewActions(FWin);
  extra := NewActions(FWin);
  orphan := NewActions(FForm);
  first.MarkDesigning(True);
  extra.MarkDesigning(True);
  orphan.MarkDesigning(True);
  TallyActionsInk(first, TyToolWindowHeaderHeightDef, TyToolWindowHeaderHeightDef, red, blue);
  AssertTrue('设计期空着的操作区描一个槽位,方便往里拖控件', blue > 0);
  AssertEquals('窗口认的那一个不画提示', 0, red);
  TallyActionsInk(extra, W, TyToolWindowHeaderHeightDef, red, blue);
  AssertTrue('多出来的画提示', red > 0);
  TallyActionsInk(orphan, W, TyToolWindowHeaderHeightDef, red, blue);
  AssertTrue('孤儿画提示', red > 0);
  NewChild(first, 20, 18);
  TallyActionsInk(first, 2 * TyToolWindowHeaderPadDef + 20, TyToolWindowHeaderHeightDef, red, blue);
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

initialization
  RegisterTest(TTyToolWindowActionsTests);
end.
