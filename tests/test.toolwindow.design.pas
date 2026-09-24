unit test.toolwindow.design;
{$mode objfpc}{$H+}

{ 工具窗口在设计器里的那一面(spec §3.2 / §10.6 / §11),全部无头:
  - 设计期孤儿(Parent 不是栏):显示出来、顶上一行提示、正文让位;运行时照旧藏着。
  - Placement 冲突:设计期在冲突的栏底部让一行提示;Placement 集合一变,每条栏都重排、重画。
  设计期的栏和窗口照 C 期的写法:Owner 带 csDesigning、构造时传下来(FDesignOwner),
  走的是设计器放下控件的真实路径。夹具在 test.toolwindow.manager。 }

interface

uses
  Classes, SysUtils, Types, TypInfo, Controls, Forms, Graphics, LCLType, LCLProc,
  fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Base, tyControls.Controller, tyControls.Panel,
  tyControls.StyleModel, tyControls.Painter, tyControls.StrConsts,
  tyControls.ToolWindows, tyControls.ToolWindows.Layout, tyControls.ToolWindows.Manager,
  test.toolwindow.window, test.toolwindow.bar, test.toolwindow.manager;

type
  TTyToolWindowDesignTests = class(TTyToolWindowManagerFixture)
  private
    FPanel: TTyPanel;
    { 设计期栏里两个窗口:A 不是当前页(藏着、带 csNoDesignVisible),B 是当前页。 }
    function NewDesignPair(out A, B: TProbeWindow): TBarAccess;
    { 窗体上一个设计期面板(Owner = FDesignOwner),孤儿挪到这里。 }
    function DesignPanel: TTyPanel;
    { 把窗口挪到设计期面板上,并给它一个确定的尺寸(对齐引擎无头不跑)。 }
    procedure Orphan(AWin: TProbeWindow);
    { 设计期的 manager(Owner = FDesignOwner)和挂在它上面的一条设计期栏(一个窗口)。 }
    function NewDesignManager: TTyToolWindowManager;
    function DesignBarOn(APlacement: TTyToolWindowPlacement; AManager: TTyToolWindowManager): TBarAccess;
  published
    { spec §3.2:设计期孤儿。 }
    procedure TestAnInactiveWindowMovedOutDropsTheDesignFlag;
    procedure TestAnOrphanWritesVisibleNotJustTheFlag;
    procedure TestTheActiveWindowMovedOutStaysVisible;
    procedure TestTheOrphanNoteIsOneHeaderRowAcross;
    procedure TestTheBodyStartsBelowTheOrphanNote;
    procedure TestAnOrphansActionsSitBelowTheNote;
    procedure TestTheOrphanNoteIsPainted;
    procedure TestARunTimeOrphanStaysHiddenWithNoNote;
    procedure TestAnOrphanBackInItsBarIsTheCurrentPageAgain;
    procedure TestADesignTimeParentOfNilDoesNotRaise;
    procedure TestAnOrphanStreamsWithoutVisible;
    { spec §10.6:设计期 Placement 冲突提示。 }
    procedure TestConflictingBarsReserveANoteLine;
    procedure TestTheActivePageStopsAboveTheConflictNote;
    procedure TestNoConflictNoteAtRunTime;
    procedure TestNoConflictWithoutASharedManager;
    procedure TestTheConflictLineSitsAboveTheStrayLine;
    procedure TestTheConflictNoteIsPainted;
    procedure TestChangingPlacementRepaintsTheOtherBar;
    procedure TestLeavingTheManagerRepaintsBothBars;
    procedure TestJoiningTheManagerRepaintsTheOthers;
    procedure TestFreeingABarRepaintsTheOther;
    procedure TestFreeingTheManagerRepaintsEveryBar;
    procedure TestJoiningWhileLoadingDoesNotRelayout;
    procedure TestTheConflictTextFitsADefaultSideBar;
  end;

implementation

type
  { ParentFont 是 protected:量字要用控件真正用的字号(同 test.toolwindow.bottom)。 }
  TControlAccess = class(TControl);

function BinaryToText(AStream: TMemoryStream): string;
var
  txt: TStringStream;
begin
  txt := TStringStream.Create('');
  try
    AStream.Position := 0;
    ObjectBinaryToText(AStream, txt);
    Result := txt.DataString;
  finally
    txt.Free;
  end;
end;

{ 把窗口按 AW×AH 画出来,只留 ARegion 那一块(窗口坐标),先铺 Wipe 当底漆(同 RenderRegion)。 }
function RenderWinRegion(AWin: TProbeWindow; AW, AH: Integer; const ARegion: TRect): TBitmap;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := pf32bit;
  Result.SetSize(ARegion.Right - ARegion.Left, ARegion.Bottom - ARegion.Top);
  Result.Canvas.Brush.Color := Wipe;
  Result.Canvas.FillRect(0, 0, Result.Width, Result.Height);
  AWin.CallRenderTo(Result.Canvas,
    Rect(-ARegion.Left, -ARegion.Top, AW - ARegion.Left, AH - ARegion.Top), 96);
end;

function TTyToolWindowDesignTests.NewDesignPair(out A, B: TProbeWindow): TBarAccess;
begin
  Result := NewDesignBar;
  A := NewWindowIn(Result, FDesignOwner);
  A.Name := 'A';
  B := NewWindowIn(Result, FDesignOwner);
  B.Name := 'B';
end;

function TTyToolWindowDesignTests.DesignPanel: TTyPanel;
begin
  if FPanel = nil then
  begin
    if FDesignOwner = nil then
    begin
      FDesignOwner := TDesignOwner.Create(nil);
      FDesignOwner.MarkDesigning;
    end;
    FPanel := TTyPanel.Create(FDesignOwner);
    FPanel.Parent := FForm;
    FPanel.Controller := FCtl;
    FPanel.Font.PixelsPerInch := 96;
    FPanel.SetBounds(300, 0, 300, 300);
  end;
  Result := FPanel;
end;

procedure TTyToolWindowDesignTests.Orphan(AWin: TProbeWindow);
begin
  AWin.Parent := DesignPanel;
  AWin.SetBounds(0, 0, 200, 150);
end;

procedure TTyToolWindowDesignTests.TestAnInactiveWindowMovedOutDropsTheDesignFlag;
var
  a, b: TProbeWindow;
begin
  NewDesignPair(a, b);
  AssertTrue('前提:非当前页带着 csNoDesignVisible', csNoDesignVisible in a.ControlStyle);
  AssertFalse('前提:非当前页设计期看不见', a.IsControlVisible);
  Orphan(a);
  AssertFalse('孤儿摘掉 csNoDesignVisible', csNoDesignVisible in a.ControlStyle);
  AssertTrue('设计器里看得见', a.IsControlVisible);
end;

procedure TTyToolWindowDesignTests.TestAnOrphanWritesVisibleNotJustTheFlag;
var
  a, b: TProbeWindow;
begin
  { 只摘标志的话 IsControlVisible 照样为真(它把设计期那一半算进去),但句柄的显隐由写
    Visible 那一下触发(CM_VISIBLECHANGED)—— Visible 原来是 False,不写就一直是 False。 }
  NewDesignPair(a, b);
  AssertFalse('前提:非当前页的 Visible 是 False', a.Visible);
  Orphan(a);
  AssertTrue('孤儿的 Visible 被写成 True', a.Visible);
end;

procedure TTyToolWindowDesignTests.TestTheActiveWindowMovedOutStaysVisible;
var
  a, b: TProbeWindow;
begin
  NewDesignPair(a, b);
  AssertTrue('前提:当前页显示着', b.Visible);
  Orphan(b);
  AssertTrue('当前页挪出去照样看得见', b.IsControlVisible and b.Visible);
  AssertFalse('没有 csNoDesignVisible', csNoDesignVisible in b.ControlStyle);
end;

procedure TTyToolWindowDesignTests.TestTheOrphanNoteIsOneHeaderRowAcross;
var
  a, b: TProbeWindow;
  n: TRect;
begin
  NewDesignPair(a, b);
  AssertTrue('在栏里没有孤儿提示', IsRectEmpty(a.OrphanNoteRect));
  Orphan(a);
  n := a.OrphanNoteRect;
  AssertFalse('设计期孤儿有提示行', IsRectEmpty(n));
  AssertEquals('贴顶', 0, n.Top);
  AssertEquals('高 = --toolwindow-header-height(默认主题 26,按字体 PPI)',
    MulDiv(TyToolWindowHeaderHeightDef, a.Font.PixelsPerInch, 96), n.Bottom - n.Top);
  AssertEquals('宽 = 客户区宽', a.ClientWidth, n.Right - n.Left);
  AssertEquals('孤儿没有标题行', Ord(twhNone), Ord(a.HeaderMode));
end;

procedure TTyToolWindowDesignTests.TestTheBodyStartsBelowTheOrphanNote;
var
  a, b: TProbeWindow;
  body: TBodyChild;
begin
  NewDesignPair(a, b);
  body := TBodyChild.Create(FDesignOwner);
  body.Parent := a;
  body.Align := alClient;
  Orphan(a);
  a.CallAlignControls;
  AssertEquals('正文区从提示行下面开始', a.OrphanNoteRect.Bottom, a.BodyRect.Top);
  AssertEquals('alClient 的正文控件也在提示行下面', a.OrphanNoteRect.Bottom, body.Top);
end;

procedure TTyToolWindowDesignTests.TestAnOrphansActionsSitBelowTheNote;
var
  a, b: TProbeWindow;
  act: TTyToolWindowActions;
begin
  NewDesignPair(a, b);
  act := a.EnsureActions;
  Orphan(a);
  a.CallAlignControls;
  AssertTrue('前提:设计期孤儿的操作区看得见', act.IsControlVisible);
  AssertTrue('操作区排在提示行下面', act.Top >= a.OrphanNoteRect.Bottom);
end;

procedure TTyToolWindowDesignTests.TestTheOrphanNoteIsPainted;
var
  a, b: TProbeWindow;
  n, below: TRect;
  bmp: TBitmap;
  pix, wipeLeft: Integer;
begin
  FCtl.StyleOverride := 'TyToolWindow { background: #FF00FF; }';
  NewDesignPair(a, b);
  Orphan(a);
  n := a.OrphanNoteRect;
  bmp := RenderWinRegion(a, a.ClientWidth, a.ClientHeight, n);
  try
    TallyPixels(bmp, Ground, Wipe, pix, wipeLeft);
  finally
    bmp.Free;
  end;
  AssertEquals('提示行整块都画到', 0, wipeLeft);
  AssertTrue('提示行里画了字', pix > 0);
  below := Rect(0, n.Bottom, a.ClientWidth, a.ClientHeight);
  bmp := RenderWinRegion(a, a.ClientWidth, a.ClientHeight, below);
  try
    TallyPixels(bmp, Ground, Wipe, pix, wipeLeft);
  finally
    bmp.Free;
  end;
  AssertEquals('正文区整块都画到', 0, wipeLeft);
  AssertEquals('正文区(没放子控件)一个墨迹都没有', 0, pix);
end;

procedure TTyToolWindowDesignTests.TestARunTimeOrphanStaysHiddenWithNoNote;
var
  a, b: TProbeWindow;
  p: TTyPanel;
begin
  a := NewWindow;
  b := NewWindow;
  AssertSame('前提:第二个是当前页', b, FBar.ActiveWindow);
  p := TTyPanel.Create(FForm);
  p.Parent := FForm;
  p.Controller := FCtl;
  b.Parent := p;
  b.SetBounds(0, 0, 200, 150);
  AssertFalse('运行时孤儿藏着', b.Visible);
  AssertTrue('运行时没有提示行', IsRectEmpty(b.OrphanNoteRect));
  AssertEquals('运行时正文不让位', 0, b.BodyRect.Top);
  a.Parent := p;
  AssertFalse('非当前页挪出去也藏着', a.Visible);
end;

procedure TTyToolWindowDesignTests.TestAnOrphanBackInItsBarIsTheCurrentPageAgain;
var
  d: TBarAccess;
  a, b: TProbeWindow;
begin
  d := NewDesignPair(a, b);
  Orphan(a);
  a.Parent := d;
  AssertSame('回到栏里成为当前页', a, d.ActiveWindow);
  AssertTrue('提示行没了', IsRectEmpty(a.OrphanNoteRect));
  AssertEquals('按侧栏排标题行', Ord(twhSide), Ord(a.HeaderMode));
  AssertTrue('另一页又藏起来', csNoDesignVisible in b.ControlStyle);
  AssertFalse('当前页不带标志', csNoDesignVisible in a.ControlStyle);
end;

procedure TTyToolWindowDesignTests.TestADesignTimeParentOfNilDoesNotRaise;
var
  a, b: TProbeWindow;
begin
  NewDesignPair(a, b);
  a.Parent := nil;
  AssertNull('摘下来了', a.Parent);
  b.Parent := nil;
  AssertNull('当前页也摘得下来', b.Parent);
end;

procedure TTyToolWindowDesignTests.TestAnOrphanStreamsWithoutVisible;
var
  a, b: TProbeWindow;
  ms: TMemoryStream;
  txt: string;
begin
  { 设计期孤儿的 Visible 被写成 True,但它是 stored False:不进 .lfm。整棵设计期窗体无头
    建不起来(设计期的 TForm 要句柄),这里只流孤儿自己 —— 写的是同一份 published 表。 }
  NewDesignPair(a, b);
  Orphan(a);
  AssertTrue('前提:孤儿显示着', a.Visible);
  ms := TMemoryStream.Create;
  try
    ms.WriteComponent(a);
    txt := BinaryToText(ms);
    AssertTrue('前提:写出来的是这个窗口', Pos('object A: TProbeWindow', txt) > 0);
    AssertEquals('Visible 不进 .lfm', 0, Pos('Visible', txt));
  finally
    ms.Free;
  end;
end;


function TTyToolWindowDesignTests.NewDesignManager: TTyToolWindowManager;
begin
  if FDesignOwner = nil then
  begin
    FDesignOwner := TDesignOwner.Create(nil);
    FDesignOwner.MarkDesigning;
  end;
  Result := TTyToolWindowManager.Create(FDesignOwner);
end;

function TTyToolWindowDesignTests.DesignBarOn(APlacement: TTyToolWindowPlacement;
  AManager: TTyToolWindowManager): TBarAccess;
begin
  Result := NewDesignBar;
  Result.Placement := APlacement;
  if APlacement = twpBottom then Result.Width := 600 else Result.Height := 400;
  NewWindowIn(Result, FDesignOwner);
  if AManager <> nil then Result.Manager := AManager;
end;

procedure TTyToolWindowDesignTests.TestConflictingBarsReserveANoteLine;
var
  m: TTyToolWindowManager;
  a, b: TBarAccess;
  L: TTyToolWindowBarLayout;
begin
  m := NewDesignManager;
  a := DesignBarOn(twpLeft, m);
  b := DesignBarOn(twpLeft, m);
  L := a.BarLayout;
  AssertFalse('A 有冲突提示行', IsRectEmpty(L.ConflictNote));
  AssertEquals('行高 = --toolwindow-header-height', TyToolWindowHeaderHeightDef,
    L.ConflictNote.Bottom - L.ConflictNote.Top);
  AssertEquals('内容区停在提示行上面', L.ConflictNote.Top, L.Content.Bottom);
  AssertFalse('B 同样有', IsRectEmpty(b.BarLayout.ConflictNote));
end;

procedure TTyToolWindowDesignTests.TestTheActivePageStopsAboveTheConflictNote;
var
  m: TTyToolWindowManager;
  a: TBarAccess;
begin
  m := NewDesignManager;
  a := DesignBarOn(twpLeft, m);
  DesignBarOn(twpLeft, m);
  LayOut(a);
  AssertTrue('当前页不盖提示行',
    a.ActiveWindow.BoundsRect.Bottom <= a.BarLayout.ConflictNote.Top);
end;

procedure TTyToolWindowDesignTests.TestNoConflictNoteAtRunTime;
var
  m: TTyToolWindowManager;
  a, b: TBarAccess;
begin
  m := NewManager;
  a := NewBarOn(twpLeft, ['A1']);
  b := NewBarOn(twpLeft, ['B1']);
  a.Manager := m;
  b.Manager := m;
  AssertFalse('前提:运行时照样冲突', m.IsBarUsable(a));
  AssertTrue('运行时没有提示行', IsRectEmpty(a.BarLayout.ConflictNote));
  AssertTrue('另一条也没有', IsRectEmpty(b.BarLayout.ConflictNote));
end;

procedure TTyToolWindowDesignTests.TestNoConflictWithoutASharedManager;
var
  a, b, c, d: TBarAccess;
begin
  a := DesignBarOn(twpLeft, nil);
  b := DesignBarOn(twpLeft, nil);
  AssertTrue('没有 manager:不冲突', IsRectEmpty(a.BarLayout.ConflictNote)
    and IsRectEmpty(b.BarLayout.ConflictNote));
  c := DesignBarOn(twpLeft, NewDesignManager);
  d := DesignBarOn(twpLeft, NewDesignManager);
  AssertTrue('各自一个 manager:不冲突', IsRectEmpty(c.BarLayout.ConflictNote)
    and IsRectEmpty(d.BarLayout.ConflictNote));
end;

procedure TTyToolWindowDesignTests.TestTheConflictLineSitsAboveTheStrayLine;
var
  m: TTyToolWindowManager;
  a: TBarAccess;
  stray: TBodyChild;
  L: TTyToolWindowBarLayout;
begin
  m := NewDesignManager;
  a := DesignBarOn(twpLeft, m);
  DesignBarOn(twpLeft, m);
  stray := TBodyChild.Create(FDesignOwner);
  a.InsertControl(stray);
  L := a.BarLayout;
  AssertFalse('漏入提示行在', IsRectEmpty(L.StrayNote));
  AssertFalse('冲突提示行在', IsRectEmpty(L.ConflictNote));
  AssertEquals('冲突行紧贴在漏入行上面', L.StrayNote.Top, L.ConflictNote.Bottom);
  AssertEquals('内容区停在冲突行上面', L.ConflictNote.Top, L.Content.Bottom);
end;

procedure TTyToolWindowDesignTests.TestTheConflictNoteIsPainted;
var
  m: TTyToolWindowManager;
  a: TBarAccess;
  L: TTyToolWindowBarLayout;
  bmp: TBitmap;
  pix, wipeLeft: Integer;
begin
  FCtl.StyleOverride := 'TyToolWindowBar { background: #FF00FF; }';
  m := NewDesignManager;
  a := DesignBarOn(twpLeft, m);
  DesignBarOn(twpLeft, m);
  L := a.BarLayout;
  bmp := RenderRegion(a, a.ClientWidth, a.ClientHeight, L.ConflictNote, Wipe);
  try
    TallyPixels(bmp, Ground, Wipe, pix, wipeLeft);
  finally
    bmp.Free;
  end;
  AssertEquals('提示行整块都画到', 0, wipeLeft);
  AssertTrue('提示行里画了字', pix > 0);
end;

procedure TTyToolWindowDesignTests.TestChangingPlacementRepaintsTheOtherBar;
var
  m: TTyToolWindowManager;
  a, b: TBarAccess;
  inv, aln: Integer;
begin
  m := NewDesignManager;
  a := DesignBarOn(twpLeft, m);
  b := DesignBarOn(twpLeft, m);
  AssertFalse('前提:冲突', IsRectEmpty(a.BarLayout.ConflictNote));
  inv := a.Invalidates;
  aln := a.AlignCount;
  b.Placement := twpRight;
  AssertTrue('A 重画了', a.Invalidates > inv);
  AssertTrue('A 重排了(提示行占内容区,只重画的话当前页还盖着旧位置)', a.AlignCount > aln);
  AssertTrue('A 的提示没了', IsRectEmpty(a.BarLayout.ConflictNote));
end;

procedure TTyToolWindowDesignTests.TestLeavingTheManagerRepaintsBothBars;
var
  m: TTyToolWindowManager;
  a, b: TBarAccess;
  ia, ib, la, lb: Integer;
begin
  m := NewDesignManager;
  a := DesignBarOn(twpLeft, m);
  b := DesignBarOn(twpLeft, m);
  ia := a.Invalidates; la := a.AlignCount;
  ib := b.Invalidates; lb := b.AlignCount;
  b.Manager := nil;
  AssertTrue('A 重画了', a.Invalidates > ia);
  AssertTrue('A 重排了', a.AlignCount > la);
  AssertTrue('A 的提示没了', IsRectEmpty(a.BarLayout.ConflictNote));
  AssertTrue('B 自己也重画了', b.Invalidates > ib);
  AssertTrue('B 自己也重排了', b.AlignCount > lb);
  AssertTrue('B 的提示没了', IsRectEmpty(b.BarLayout.ConflictNote));
end;

procedure TTyToolWindowDesignTests.TestJoiningTheManagerRepaintsTheOthers;
var
  m: TTyToolWindowManager;
  a, c: TBarAccess;
  inv, aln: Integer;
begin
  m := NewDesignManager;
  a := DesignBarOn(twpLeft, m);
  DesignBarOn(twpRight, m);
  AssertTrue('前提:不冲突', IsRectEmpty(a.BarLayout.ConflictNote));
  c := DesignBarOn(twpLeft, nil);
  inv := a.Invalidates;
  aln := a.AlignCount;
  c.Manager := m;
  AssertTrue('A 重画了', a.Invalidates > inv);
  AssertTrue('A 重排了', a.AlignCount > aln);
  AssertFalse('A 有提示了', IsRectEmpty(a.BarLayout.ConflictNote));
end;

procedure TTyToolWindowDesignTests.TestFreeingABarRepaintsTheOther;
var
  m: TTyToolWindowManager;
  a, b: TBarAccess;
  inv, aln: Integer;
begin
  m := NewDesignManager;
  a := DesignBarOn(twpLeft, m);
  b := DesignBarOn(twpLeft, m);
  inv := a.Invalidates;
  aln := a.AlignCount;
  b.Free;
  AssertTrue('A 重画了', a.Invalidates > inv);
  AssertTrue('A 重排了', a.AlignCount > aln);
  AssertTrue('A 的提示没了', IsRectEmpty(a.BarLayout.ConflictNote));
end;

procedure TTyToolWindowDesignTests.TestFreeingTheManagerRepaintsEveryBar;
var
  m: TTyToolWindowManager;
  a, b: TBarAccess;
  ia, ib, la, lb: Integer;
begin
  m := NewDesignManager;
  a := DesignBarOn(twpLeft, m);
  b := DesignBarOn(twpLeft, m);
  ia := a.Invalidates; la := a.AlignCount;
  ib := b.Invalidates; lb := b.AlignCount;
  m.Free;
  AssertTrue('A 重画了', a.Invalidates > ia);
  AssertTrue('A 重排了', a.AlignCount > la);
  AssertTrue('B 重画了', b.Invalidates > ib);
  AssertTrue('B 重排了', b.AlignCount > lb);
  AssertTrue('提示都没了', IsRectEmpty(a.BarLayout.ConflictNote)
    and IsRectEmpty(b.BarLayout.ConflictNote));
end;

procedure TTyToolWindowDesignTests.TestJoiningWhileLoadingDoesNotRelayout;
var
  m: TTyToolWindowManager;
  a, b: TBarAccess;
  la, lb: Integer;
begin
  { 流式 fixup 里 SetManager 挂上去(spec §10.6):不抛异常,也不因为 AddBar 重排 ——
    加载中的冲突由栏的 Loaded 带上。 }
  m := NewDesignManager;
  a := DesignBarOn(twpLeft, nil);
  b := DesignBarOn(twpLeft, nil);
  a.BeginLoad;
  b.BeginLoad;
  try
    la := a.AlignCount;
    lb := b.AlignCount;
    a.Manager := m;
    b.Manager := m;
    AssertEquals('加载中 A 不因为挂 manager 重排', la, a.AlignCount);
    AssertEquals('加载中 B 不因为挂 manager 重排', lb, b.AlignCount);
  finally
    a.EndLoad;
    b.EndLoad;
  end;
  AssertFalse('加载完照样画提示', IsRectEmpty(a.BarLayout.ConflictNote));
end;

procedure TTyToolWindowDesignTests.TestTheConflictTextFitsADefaultSideBar;
var
  m: TTyToolWindowManager;
  a: TBarAccess;
  L: TTyToolWindowBarLayout;
  S: TTyStyleSet;
  bw, bh, rw, fs, room: Integer;
begin
  { 开工前问题 3 的文案:默认主题、96 PPI、ExpandedSize = 240 的设计期左栏里放得下,不出
    省略号。两种量法取大(Painter.pas 的约定),同栏画提示用的字号。 }
  m := NewDesignManager;
  a := DesignBarOn(twpLeft, m);
  DesignBarOn(twpLeft, m);
  AssertEquals('前提:默认展开尺寸', 240, a.ExpandedSize);
  L := a.BarLayout;
  S := FCtl.Model.ResolveStyle(TyToolWindowNoteKey, '', [tysNormal]);
  fs := TyResolveFontSize(S, TControlAccess(a).ParentFont, a.Font.Size, FCtl);
  TyMeasureTextBlock(rsTyToolWindowBarConflict, S.FontName, fs, S.FontWeight, 96, 0, 0, bw, bh);
  rw := TyMeasureRenderedTextWidth(rsTyToolWindowBarConflict, S.FontName, fs, S.FontWeight, 96);
  if rw > bw then bw := rw;
  room := L.ConflictNote.Right - L.ConflictNote.Left - 2 * TyToolWindowHeaderPadDef;
  AssertTrue(Format('提示 %d px 放得进 %d px', [bw, room]), bw <= room);
end;

initialization
  RegisterClasses([TTyPanel]);
  RegisterTest(TTyToolWindowDesignTests);
end.
