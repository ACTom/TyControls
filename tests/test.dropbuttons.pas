unit test.dropbuttons;
{$mode objfpc}{$H+}
{ Headless fpcunit tests for tyControls.DropButtons (TTyDropDownButton split button +
  TTyMenuButton whole-button drop). The live PopUp needs a GUI, so the tests exercise
  the pure/headless seams only:
    - TyDropArrowHit hit-test with concrete numbers + boundary.
    - DoDropDown (via DropDownForTest) fires OnDropDown and records the would-pop
      intent WITHOUT calling the GUI PopUp (no window handle -> DoDropDown stops after
      recording RequestedPopup).
    - Split-button routing: a click in the arrow zone -> DoDropDown, NOT primary
      OnClick; a click in the primary area -> OnClick, NOT DoDropDown.
    - Property round-trip + FreeNotification nils DropDownMenu.
    - AutoSize:首选宽度必须装得下**画出来的**全部东西(标题 + 主题内边距 + 箭头区),
      并且随皮肤的字体/内边距/箭头度量一起变。断言一律走 CalculatePreferredSize,不走
      Width——父窗体没有句柄时 LCL 的 AutoSizeDelayed 会把自动调整整个吞掉,读 Width
      等于什么都没测。 }
interface
uses
  Classes, SysUtils, TypInfo, Types, Controls, Graphics, Forms, LCLType, LCLMessageGlue,
  BGRABitmap, BGRABitmapTypes, fpcunit, testregistry,
  tyControls.Base, tyControls.Types, tyControls.Controller, tyControls.Menu,
  tyControls.DropButtons, tyControls.ToolBar;

type
  { Probe subclass: drives a full headless "press then click" at a device-x. LCL
    synthesises Click AFTER the mouse-up, so a real click is MouseDown(X) then Click;
    the split button reads the down-X in Click to route arrow vs primary. Also
    re-exposes the protected RenderTo so the paint path (DrawContent: arrow + divider)
    runs deterministically without a window handle. }
  TDropDownAccess = class(TTyDropDownButton)
  public
    procedure PressAndClickAt(X: Integer);
    { Press in the arrow zone but release OUTSIDE the control (no Click fires), then a
      later keyboard-style Click. Verifies FDownX is cleared so the key click is primary. }
    procedure AbortedArrowPressThenKeyClick(AArrowX: Integer);
    procedure DoRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    { The protected preferred-size calculation — what AutoSize would resize to. }
    procedure CallPreferred(out AW, AH: Integer);
    { The caption measurement the size floor's HEIGHT is derived from. }
    procedure CallMeasure(APPI: Integer; out AW, AH: Integer);
    { The hit-test half of the arrow zone, so a test can probe it at the pixel the PAINT
      half put the divider on. }
    function CallIsInArrowZone(AX: Integer): Boolean;
    { The resolved theme's right padding — the gap the two halves used to differ by. A test
      asserts it is non-zero, or it would be pinning nothing. }
    function CallPadRight: Integer;
  end;

  { Probe subclass exposing TTyMenuButton's protected RenderTo. }
  TMenuButtonAccess = class(TTyMenuButton)
  public
    procedure DoRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure CallPreferred(out AW, AH: Integer);
    procedure CallMeasure(APPI: Integer; out AW, AH: Integer);
  end;

  TDropDownButtonTest = class(TTestCase)
  private
    FDropped: Integer;
    FClicked: Integer;
    procedure HandleDropDown(Sender: TObject);
    procedure HandleClick(Sender: TObject);
  published
    procedure TestArrowHitConcreteNumbers;
    procedure TestArrowHitBoundaryAndDegenerate;
    procedure TestTypeKeyReusesButton;
    procedure TestPropertyRoundTrip;
    procedure TestDoDropDownFiresEventAndRecordsIntent;
    procedure TestDoDropDownNoMenuNoIntent;
    procedure TestArrowClickDropsNotPrimaryClick;
    procedure TestPrimaryClickFiresOnClickNotDrop;
    procedure TestAbortedArrowPressDoesNotMisrouteKeyClick;
    procedure TestFreeNotificationNilsMenu;
    procedure TestPaintSmoke;
  end;

  TMenuButtonTest = class(TTestCase)
  private
    FDropped: Integer;
    FClicked: Integer;
    procedure HandleDropDown(Sender: TObject);
    procedure HandleClick(Sender: TObject);
  published
    procedure TestTypeKeyReusesButton;
    procedure TestClickDropsAndFiresOnClick;
    procedure TestDoDropDownNoMenuNoIntent;
    procedure TestFreeNotificationNilsMenu;
    procedure TestPropertyRoundTrip;
    procedure TestPaintSmoke;
  end;

  { AutoSize / 首选宽度。两个下拉按钮画的都是「标题 + 箭头区」,所以量出来的宽度必须
    把箭头区也算进去——不然 AutoSize 会按纯标题收窄,箭头把标题挤没,省略号照旧。
    (一个会说谎的 AutoSize 比没有 AutoSize 更糟。) }
  TDropButtonsAutoSizeTest = class(TTestCase)
  published
    procedure TestAutoSizePublishedButOffByDefault;
    procedure TestSplitPreferredReservesTheArrowZone;
    procedure TestSplitPreferredGrowsWithTheCaption;
    procedure TestSplitRoomierThemeWidensPreferredWidth;
    procedure TestMenuPreferredReservesTheThemeArrowZone;
    procedure TestMenuPreferredGrowsWithTheCaption;
    procedure TestMenuRoomierThemeWidensPreferredWidth;
    procedure TestPreferredHeightIsAlwaysZero;
  end;

  { SIZE FLOOR(Constraints.Min*)。手写的 Height 和主题的 --control-height 都只是**请求**;
    真正**做得到**的尺寸由字体、内边距和箭头区决定,而这三样只有控件自己同时知道。
    Linux/Qt6 上同一个 9pt 中文标题会走一张 ink 更高的回落字体,DrawText 又是裁剪 + tlCenter,
    所以盒子矮了掉的是标题的**下半截**——只在那个平台上,而且悄无声息。
    这里一律断言 Constraints,不断言 Width/Height:下限跟 AutoSize 开不开无关,而且父窗体
    没句柄时 AutoSizeDelayed 会把真正的 resize 整个吞掉。 }
  TDropButtonsFloorTest = class(TTestCase)
  published
    procedure TestSplitArrowZoneIsPartOfTheWidthFloor;
    procedure TestMenuFloorTracksTheThemeArrowMetric;
    procedure TestFloorFitsTheCaption;
    procedure TestSmallerFontLowersTheFloor;
    procedure TestFloorSurvivesAHeightPinningToolBar;
  end;

  { WHERE the arrow zone begins — drawn and hit-tested, pinned against each other.

    The two used to be computed separately: the paint measured back from the padded CONTENT
    box, the hit test from the CONTROL's right edge, so they stood exactly one right-padding
    apart. The drawn divider, and the slice of drawn arrow beside it, ran the PRIMARY action.

    Every probe here sits ON the boundary — the divider column that the paint actually
    produced, read back out of the rendered pixels, and the column one to its left. A CENTRE
    probe is worthless for this: the two zones overlapped in the middle, which is exactly how
    the divergence survived. The theme below therefore also has a DELIBERATELY NON-ZERO
    horizontal padding, and the test asserts that it does: with padding 0 the two rules
    coincide and every assertion here would pass no matter which one the code used. }
  TDropArrowZoneEdgeTest = class(TTestCase)
  private
    FDropped: Integer;
    FClicked: Integer;
    procedure HandleDropDown(Sender: TObject);
    procedure HandleClick(Sender: TObject);
  published
    procedure TestDrawnDividerIsTheFirstHitPixel;
    procedure TestClickAtTheDrawnDividerRoutesToTheMenu;
    procedure TestRealWindowClickOnTheDrawnEdgeOpensTheMenu;
    procedure TestZoneLeftIsPureAndRefusesAnArrowThatCannotFit;
  end;

implementation

const
  { 内边距和字号都写死,断言才能算出确定的数字,而不是跟着当前主题走。border-width:0
    是为了让宽度里只剩「文字 + 内边距 + 箭头区」这三项。 }
  cDropTightCss =
    ':root { --drop-arrow-width: 18px; }' +
    'TyButton { background: #FFFFFF; color: #000000; border-width: 0px; padding: 4px 4px; font-size: 12px; }';
  { 同上,只是左右内边距 4px -> 30px(每边 +26,共 +52)。 }
  cDropRoomyCss =
    ':root { --drop-arrow-width: 18px; }' +
    'TyButton { background: #FFFFFF; color: #000000; border-width: 0px; padding: 4px 30px; font-size: 12px; }';
  { 同 cDropTightCss,只是箭头度量 18px -> 40px(+22),字体和内边距一个没动。 }
  cDropWideArrowCss =
    ':root { --drop-arrow-width: 40px; }' +
    'TyButton { background: #FFFFFF; color: #000000; border-width: 0px; padding: 4px 4px; font-size: 12px; }';

procedure TDropDownAccess.PressAndClickAt(X: Integer);
begin
  MouseDown(mbLeft, [], X, 0);   // records the down-X
  Click;                          // native click synthesised after the up; routes on down-X
end;

procedure TDropDownAccess.AbortedArrowPressThenKeyClick(AArrowX: Integer);
begin
  MouseDown(mbLeft, [], AArrowX, 0);      // press in the arrow zone
  MouseUp(mbLeft, [], Width + 20, 0);     // release OUTSIDE -> no Click; FDownX must clear
  Click;                                   // keyboard-style Click -> must route PRIMARY
end;

procedure TDropDownAccess.DoRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TDropDownAccess.CallPreferred(out AW, AH: Integer);
begin
  AW := 0; AH := 0;
  CalculatePreferredSize(AW, AH, True);
end;

procedure TDropDownAccess.CallMeasure(APPI: Integer; out AW, AH: Integer);
begin
  MeasureCaption(APPI, AW, AH);
end;

function TDropDownAccess.CallIsInArrowZone(AX: Integer): Boolean;
begin
  Result := IsInArrowZone(AX);
end;

function TDropDownAccess.CallPadRight: Integer;
begin
  Result := CurrentStyle.Padding.Right;
end;

procedure TMenuButtonAccess.CallMeasure(APPI: Integer; out AW, AH: Integer);
begin
  MeasureCaption(APPI, AW, AH);
end;

procedure TMenuButtonAccess.DoRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TMenuButtonAccess.CallPreferred(out AW, AH: Integer);
begin
  AW := 0; AH := 0;
  CalculatePreferredSize(AW, AH, True);
end;

{ TDropDownButtonTest }

procedure TDropDownButtonTest.HandleDropDown(Sender: TObject);
begin
  Inc(FDropped);
end;

procedure TDropDownButtonTest.HandleClick(Sender: TObject);
begin
  Inc(FClicked);
end;

procedure TDropDownButtonTest.TestArrowHitConcreteNumbers;
begin
  // 100px control, 20px arrow zone => arrow zone is x in [80..99].
  AssertTrue('x=90 is in the 20px arrow zone', TyDropArrowHit(90, 100, 20));
  AssertTrue('x=99 (last px) is in the arrow zone', TyDropArrowHit(99, 100, 20));
  AssertFalse('x=50 (primary area) is NOT an arrow hit', TyDropArrowHit(50, 100, 20));
  AssertFalse('x=79 (just left of the zone) is NOT an arrow hit', TyDropArrowHit(79, 100, 20));
end;

procedure TDropDownButtonTest.TestArrowHitBoundaryAndDegenerate;
begin
  // Boundary: the first arrow pixel is exactly (Width - ArrowWidth).
  AssertTrue('x=80 (first arrow px) is a hit', TyDropArrowHit(80, 100, 20));
  // Degenerate widths never trap a click as an arrow hit.
  AssertFalse('zero arrow width -> never a hit', TyDropArrowHit(50, 100, 0));
  AssertFalse('arrow >= control width -> never a hit', TyDropArrowHit(50, 100, 100));
  AssertFalse('non-positive control width -> never a hit', TyDropArrowHit(0, 0, 18));
end;

procedure TDropDownButtonTest.TestTypeKeyReusesButton;
var B: TTyDropDownButton;
begin
  B := TTyDropDownButton.Create(nil);
  try
    // Reuses the TyButton token (no new .tycss); GetStyleTypeKey is inherited.
    AssertEquals('TyButton', (B as ITyStyleable).GetStyleTypeKey);
  finally
    B.Free;
  end;
end;

procedure TDropDownButtonTest.TestPropertyRoundTrip;
var
  B: TTyDropDownButton;
  M: TTyPopupMenu;
begin
  B := TTyDropDownButton.Create(nil);
  M := TTyPopupMenu.Create(nil);
  try
    AssertEquals('default arrow width', TyDefaultDropArrowWidth, B.ArrowWidth);
    AssertTrue('DropDownMenu published', IsPublishedProp(B, 'DropDownMenu'));
    AssertTrue('ArrowWidth published', IsPublishedProp(B, 'ArrowWidth'));
    AssertTrue('OnDropDown published', IsPublishedProp(B, 'OnDropDown'));
    B.ArrowWidth := 24;
    AssertEquals('arrow width round-trips', 24, B.ArrowWidth);
    B.DropDownMenu := M;
    AssertSame('menu round-trips', M, B.DropDownMenu);
    B.ArrowWidth := -5;
    AssertEquals('negative arrow width clamps to 0', 0, B.ArrowWidth);
  finally
    B.Free;
    M.Free;
  end;
end;

procedure TDropDownButtonTest.TestDoDropDownFiresEventAndRecordsIntent;
var
  B: TTyDropDownButton;
  M: TTyPopupMenu;
begin
  // With a menu assigned, DoDropDown fires OnDropDown and records that it WOULD pop
  // (RequestedPopup). No window handle here, so it never touches the GUI PopUp.
  FDropped := 0;
  B := TTyDropDownButton.Create(nil);
  M := TTyPopupMenu.Create(nil);
  try
    B.DropDownMenu := M;
    B.OnDropDown := @HandleDropDown;
    B.DropDownForTest;
    AssertEquals('OnDropDown fired once', 1, FDropped);
    AssertTrue('would-pop recorded (menu present)', B.RequestedPopup);
  finally
    B.Free;
    M.Free;
  end;
end;

procedure TDropDownButtonTest.TestDoDropDownNoMenuNoIntent;
var B: TTyDropDownButton;
begin
  // OnDropDown still fires (a handler may assign a menu), but with none assigned there
  // is nothing to pop, so RequestedPopup stays False.
  FDropped := 0;
  B := TTyDropDownButton.Create(nil);
  try
    B.OnDropDown := @HandleDropDown;
    B.DropDownForTest;
    AssertEquals('OnDropDown still fires without a menu', 1, FDropped);
    AssertFalse('no menu -> no would-pop', B.RequestedPopup);
  finally
    B.Free;
  end;
end;

procedure TDropDownButtonTest.TestArrowClickDropsNotPrimaryClick;
var
  F: TCustomForm;
  B: TDropDownAccess;
  M: TTyPopupMenu;
begin
  // A left click in the arrow zone routes to DoDropDown and NOT the primary OnClick.
  FDropped := 0;
  FClicked := 0;
  F := TCustomForm.CreateNew(nil);
  M := TTyPopupMenu.Create(F);
  try
    B := TDropDownAccess.Create(F);
    B.Parent := F;
    B.SetBounds(0, 0, 100, 30);
    B.ArrowWidth := 18;   // at 96 PPI the arrow zone is the rightmost 18px: x in [82..99]
    B.DropDownMenu := M;
    B.OnDropDown := @HandleDropDown;
    B.OnClick := @HandleClick;
    B.PressAndClickAt(95);   // firmly inside the arrow zone
    AssertEquals('arrow click fired the drop', 1, FDropped);
    AssertEquals('arrow click did NOT fire primary OnClick', 0, FClicked);
  finally
    F.Free;
  end;
end;

procedure TDropDownButtonTest.TestPrimaryClickFiresOnClickNotDrop;
var
  F: TCustomForm;
  B: TDropDownAccess;
  M: TTyPopupMenu;
begin
  // A left click in the primary (caption) area fires the normal OnClick and does NOT
  // drop the menu.
  FDropped := 0;
  FClicked := 0;
  F := TCustomForm.CreateNew(nil);
  M := TTyPopupMenu.Create(F);
  try
    B := TDropDownAccess.Create(F);
    B.Parent := F;
    B.SetBounds(0, 0, 100, 30);
    B.ArrowWidth := 18;
    B.DropDownMenu := M;
    B.OnDropDown := @HandleDropDown;
    B.OnClick := @HandleClick;
    B.PressAndClickAt(20);   // firmly in the caption area
    AssertEquals('primary click fired OnClick', 1, FClicked);
    AssertEquals('primary click did NOT drop', 0, FDropped);
  finally
    F.Free;
  end;
end;

procedure TDropDownButtonTest.TestAbortedArrowPressDoesNotMisrouteKeyClick;
var
  F: TCustomForm;
  B: TDropDownAccess;
  M: TTyPopupMenu;
begin
  // Regression: a press in the arrow zone released OUTSIDE the control leaves no Click;
  // a LATER keyboard-style Click (no fresh MouseDown) must be treated as PRIMARY, not
  // misrouted to the drop-down by a stale FDownX.
  FDropped := 0;
  FClicked := 0;
  F := TCustomForm.CreateNew(nil);
  M := TTyPopupMenu.Create(F);
  try
    B := TDropDownAccess.Create(F);
    B.Parent := F;
    B.SetBounds(0, 0, 100, 30);
    B.ArrowWidth := 18;
    B.DropDownMenu := M;
    B.OnDropDown := @HandleDropDown;
    B.OnClick := @HandleClick;
    B.AbortedArrowPressThenKeyClick(92);   // 92 is inside the rightmost 18px arrow zone
    AssertEquals('key click after aborted press fired PRIMARY OnClick', 1, FClicked);
    AssertEquals('key click after aborted press did NOT drop', 0, FDropped);
  finally
    F.Free;
  end;
end;

procedure TDropDownButtonTest.TestFreeNotificationNilsMenu;
var
  B: TTyDropDownButton;
  M: TTyPopupMenu;
begin
  B := TTyDropDownButton.Create(nil);
  try
    M := TTyPopupMenu.Create(nil);
    B.DropDownMenu := M;
    AssertSame('menu wired', M, B.DropDownMenu);
    M.Free;   // FreeNotification must nil the reference
    AssertTrue('freeing the menu nils DropDownMenu', B.DropDownMenu = nil);
  finally
    B.Free;
  end;
end;

procedure TDropDownButtonTest.TestPaintSmoke;
var
  B: TDropDownAccess;
  Bmp: TBitmap;
begin
  // DrawContent must not crash with no menu / no handle: run the paint path directly.
  B := TDropDownAccess.Create(nil);
  Bmp := TBitmap.Create;
  try
    B.Caption := 'Save';
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(100, 30);
    // RenderTo -> DrawContent draws the caption + arrow triangle + divider.
    B.DoRenderTo(Bmp.Canvas, Rect(0, 0, 100, 30), 96);
    AssertTrue('drop-down button painted without exception', True);
  finally
    Bmp.Free;
    B.Free;
  end;
end;

{ TMenuButtonTest }

procedure TMenuButtonTest.HandleDropDown(Sender: TObject);
begin
  Inc(FDropped);
end;

procedure TMenuButtonTest.HandleClick(Sender: TObject);
begin
  Inc(FClicked);
end;

procedure TMenuButtonTest.TestTypeKeyReusesButton;
var B: TTyMenuButton;
begin
  B := TTyMenuButton.Create(nil);
  try
    AssertEquals('TyButton', (B as ITyStyleable).GetStyleTypeKey);
  finally
    B.Free;
  end;
end;

procedure TMenuButtonTest.TestClickDropsAndFiresOnClick;
var
  B: TTyMenuButton;
  M: TTyPopupMenu;
begin
  // The whole button IS the drop: Click routes to DoDropDown (firing OnDropDown and
  // recording the would-pop), AND still runs the inherited OnClick contract.
  FDropped := 0;
  FClicked := 0;
  B := TTyMenuButton.Create(nil);
  M := TTyPopupMenu.Create(nil);
  try
    B.DropDownMenu := M;
    B.OnDropDown := @HandleDropDown;
    B.OnClick := @HandleClick;
    B.Click;
    AssertEquals('click fired the drop', 1, FDropped);
    AssertEquals('click still fired OnClick', 1, FClicked);
    AssertTrue('would-pop recorded', B.RequestedPopup);
  finally
    B.Free;
    M.Free;
  end;
end;

procedure TMenuButtonTest.TestDoDropDownNoMenuNoIntent;
var B: TTyMenuButton;
begin
  FDropped := 0;
  B := TTyMenuButton.Create(nil);
  try
    B.OnDropDown := @HandleDropDown;
    B.DropDownForTest;
    AssertEquals('OnDropDown fires without a menu', 1, FDropped);
    AssertFalse('no menu -> no would-pop', B.RequestedPopup);
  finally
    B.Free;
  end;
end;

procedure TMenuButtonTest.TestFreeNotificationNilsMenu;
var
  B: TTyMenuButton;
  M: TTyPopupMenu;
begin
  B := TTyMenuButton.Create(nil);
  try
    M := TTyPopupMenu.Create(nil);
    B.DropDownMenu := M;
    AssertSame('menu wired', M, B.DropDownMenu);
    M.Free;
    AssertTrue('freeing the menu nils DropDownMenu', B.DropDownMenu = nil);
  finally
    B.Free;
  end;
end;

procedure TMenuButtonTest.TestPropertyRoundTrip;
var
  B: TTyMenuButton;
  M: TTyPopupMenu;
begin
  B := TTyMenuButton.Create(nil);
  M := TTyPopupMenu.Create(nil);
  try
    AssertTrue('DropDownMenu published', IsPublishedProp(B, 'DropDownMenu'));
    AssertTrue('OnDropDown published', IsPublishedProp(B, 'OnDropDown'));
    B.DropDownMenu := M;
    AssertSame('menu round-trips', M, B.DropDownMenu);
  finally
    B.Free;
    M.Free;
  end;
end;

procedure TMenuButtonTest.TestPaintSmoke;
var
  B: TMenuButtonAccess;
  Bmp: TBitmap;
begin
  B := TMenuButtonAccess.Create(nil);
  Bmp := TBitmap.Create;
  try
    B.Caption := 'Options';
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(100, 30);
    B.DoRenderTo(Bmp.Canvas, Rect(0, 0, 100, 30), 96);
    AssertTrue('menu button painted without exception', True);
  finally
    Bmp.Free;
    B.Free;
  end;
end;

{ TDropButtonsAutoSizeTest }

procedure TDropButtonsAutoSizeTest.TestAutoSizePublishedButOffByDefault;
{ AutoSize 必须是 published(.lfm 和对象查看器里能设),但默认仍是 False —— 已经排好版
  的按钮不会因为这次改动挪一个像素,想要自适应的人自己打开。 }
var
  D: TTyDropDownButton;
  M: TTyMenuButton;
begin
  D := TTyDropDownButton.Create(nil);
  M := TTyMenuButton.Create(nil);
  try
    AssertTrue('split button: AutoSize is published', IsPublishedProp(D, 'AutoSize'));
    AssertFalse('split button: but OFF by default', D.AutoSize);
    AssertTrue('menu button: AutoSize is published', IsPublishedProp(M, 'AutoSize'));
    AssertFalse('menu button: but OFF by default', M.AutoSize);
  finally
    D.Free;
    M.Free;
  end;
end;

procedure TDropButtonsAutoSizeTest.TestSplitPreferredReservesTheArrowZone;
{ 分割按钮把标题画在箭头区左边,所以首选宽度必须整条箭头区都算进去。用同一个标题、同一
  套主题,只改 ArrowWidth:宽度差必须**正好**等于箭头区的差,证明量的和画的是同一段。 }
var
  Ctl: TTyStyleController;
  B: TDropDownAccess;
  bare, w18, w40, h: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss(cDropTightCss);
    B := TDropDownAccess.Create(nil);
    try
      B.Controller := Ctl;
      B.Font.PixelsPerInch := 96;
      B.Caption := 'Save';

      B.ArrowWidth := 0;    // 没有箭头区 = 纯基类宽度(标题 + 内边距)
      B.CallPreferred(bare, h);
      AssertTrue('a caption plus paddings is a positive width', bare > 0);

      B.ArrowWidth := 18;
      B.CallPreferred(w18, h);
      AssertEquals('the 18px arrow zone is reserved in full', bare + 18, w18);

      B.ArrowWidth := 40;
      B.CallPreferred(w40, h);
      AssertEquals('a wider arrow zone widens the button by exactly that much',
        bare + 40, w40);
    finally
      B.Free;
    end;
  finally
    Ctl.Free;
  end;
end;

procedure TDropButtonsAutoSizeTest.TestSplitPreferredGrowsWithTheCaption;
{ 长标题要更宽——这正是整件事的目的。顺带守一条:'&' 是画成下划线的,不占宽度,所以
  量的时候也不能算进去。 }
var
  Ctl: TTyStyleController;
  B: TDropDownAccess;
  short, long, plain, mnemonic, h: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss(cDropTightCss);
    B := TDropDownAccess.Create(nil);
    try
      B.Controller := Ctl;
      B.Font.PixelsPerInch := 96;

      B.Caption := 'OK';
      B.CallPreferred(short, h);
      B.Caption := 'Save the current work order as a template';
      B.CallPreferred(long, h);
      AssertTrue(Format('a longer caption wants more width (%d -> %d)', [short, long]),
        long > short);

      B.Caption := 'Save';
      B.CallPreferred(plain, h);
      B.Caption := '&Save';
      B.CallPreferred(mnemonic, h);
      AssertEquals('a mnemonic marker is drawn as an underline, so it adds no width',
        plain, mnemonic);
    finally
      B.Free;
    end;
  finally
    Ctl.Free;
  end;
end;

procedure TDropButtonsAutoSizeTest.TestSplitRoomierThemeWidensPreferredWidth;
{ 这就是这轮要修的那个 bug:'xp' 皮肤把 TyButton 的左右内边距从 6px 提到 12px,按 default
  皮肤量好宽度的按钮就把标题挤掉了。换一套内边距更大的主题,首选宽度必须跟着变大——而且
  差值正好是多出来的内边距。 }
var
  Ctl: TTyStyleController;
  B: TDropDownAccess;
  tight, roomy, h: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    B := TDropDownAccess.Create(nil);
    try
      B.Controller := Ctl;
      B.Font.PixelsPerInch := 96;
      B.AutoSize := True;
      B.ArrowWidth := 18;
      B.Caption := 'Save';

      Ctl.LoadThemeCss(cDropTightCss);
      B.CallPreferred(tight, h);

      Ctl.LoadThemeCss(cDropRoomyCss);
      B.CallPreferred(roomy, h);

      AssertTrue(Format('a roomier skin widens the split button (%d -> %d)', [tight, roomy]),
        roomy > tight);
      // 每边多 26px,共 +52;字体、标题、箭头区都没动。
      AssertEquals('the extra width is exactly the extra padding', tight + 52, roomy);
    finally
      B.Free;
    end;
  finally
    Ctl.Free;
  end;
end;

procedure TDropButtonsAutoSizeTest.TestMenuPreferredReservesTheThemeArrowZone;
{ TTyMenuButton 的箭头区宽度来自主题度量 '--drop-arrow-width'(不是 published 属性)。
  只改这一个度量、别的全不动,首选宽度必须跟着变——证明量的读的是画的那个度量,而不是
  代码里写死的常量。 }
var
  Ctl: TTyStyleController;
  B: TMenuButtonAccess;
  narrow, wide, h: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    B := TMenuButtonAccess.Create(nil);
    try
      B.Controller := Ctl;
      B.Font.PixelsPerInch := 96;
      B.Caption := 'Options';

      Ctl.LoadThemeCss(cDropTightCss);        // --drop-arrow-width: 18px
      B.CallPreferred(narrow, h);

      Ctl.LoadThemeCss(cDropWideArrowCss);    // --drop-arrow-width: 40px
      B.CallPreferred(wide, h);

      AssertEquals('a skin that widens the arrow metric widens the button by that delta',
        narrow + 22, wide);
    finally
      B.Free;
    end;
  finally
    Ctl.Free;
  end;
end;

procedure TDropButtonsAutoSizeTest.TestMenuPreferredGrowsWithTheCaption;
var
  Ctl: TTyStyleController;
  B: TMenuButtonAccess;
  short, long, h: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss(cDropTightCss);
    B := TMenuButtonAccess.Create(nil);
    try
      B.Controller := Ctl;
      B.Font.PixelsPerInch := 96;

      B.Caption := 'File';
      B.CallPreferred(short, h);
      B.Caption := 'Recently opened documents';
      B.CallPreferred(long, h);
      AssertTrue(Format('a longer caption wants more width (%d -> %d)', [short, long]),
        long > short);
      // 箭头区在两次里是同一个值,所以差的只可能是文字。
      AssertTrue('and the arrow zone is still reserved on top of the caption',
        short > 18);
    finally
      B.Free;
    end;
  finally
    Ctl.Free;
  end;
end;

procedure TDropButtonsAutoSizeTest.TestMenuRoomierThemeWidensPreferredWidth;
var
  Ctl: TTyStyleController;
  B: TMenuButtonAccess;
  tight, roomy, h: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    B := TMenuButtonAccess.Create(nil);
    try
      B.Controller := Ctl;
      B.Font.PixelsPerInch := 96;
      B.AutoSize := True;
      B.Caption := 'Options';

      Ctl.LoadThemeCss(cDropTightCss);
      B.CallPreferred(tight, h);

      Ctl.LoadThemeCss(cDropRoomyCss);
      B.CallPreferred(roomy, h);

      AssertTrue(Format('a roomier skin widens the menu button (%d -> %d)', [tight, roomy]),
        roomy > tight);
      AssertEquals('the extra width is exactly the extra padding', tight + 52, roomy);
    finally
      B.Free;
    end;
  finally
    Ctl.Free;
  end;
end;

procedure TDropButtonsAutoSizeTest.TestPreferredHeightIsAlwaysZero;
{ 0 = LCL 的「本轴无意见」。按钮只横向长;高度归排版的人管。控件再报一个高度,就会和
  钉高度的父容器(TTyToolBar 把每个子控件钉到 ButtonHeight)来回顶,最后 LCL 以
  "TControl.ChangeBounds loop detected" 中止——demo 曾经就是这样开机即死。 }
var
  Ctl: TTyStyleController;
  D: TDropDownAccess;
  M: TMenuButtonAccess;
  w, h: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss(cDropTightCss);
    D := TDropDownAccess.Create(nil);
    M := TMenuButtonAccess.Create(nil);
    try
      D.Controller := Ctl;
      M.Controller := Ctl;
      D.Caption := '';
      M.Caption := '';
      D.CallPreferred(w, h);
      AssertEquals('split button proposes no height (empty caption)', 0, h);
      M.CallPreferred(w, h);
      AssertEquals('menu button proposes no height (empty caption)', 0, h);

      D.Caption := 'A very long caption indeed';
      M.Caption := 'A very long caption indeed';
      D.AutoSize := True;
      M.AutoSize := True;
      D.CallPreferred(w, h);
      AssertEquals('split button still proposes no height', 0, h);
      M.CallPreferred(w, h);
      AssertEquals('menu button still proposes no height', 0, h);
    finally
      D.Free;
      M.Free;
    end;
  finally
    Ctl.Free;
  end;
end;

{ ---- TDropButtonsFloorTest ---- }

procedure TDropButtonsFloorTest.TestSplitArrowZoneIsPartOfTheWidthFloor;
var
  Ctl: TTyStyleController;
  D: TDropDownAccess;
  w18, h18: Integer;
begin
  { 箭头区不是装饰:分割按钮把标题画在箭头区**左边**,所以一条被压到只装得下标题的按钮,
    箭头会直接把标题吃掉。下限必须连箭头区一起守住,而且必须正好是 DrawContent 让出的那
    一段——所以这里断的是差值,不是"大于"。 }
  Ctl := TTyStyleController.Create(nil);
  D := TDropDownAccess.Create(nil);
  try
    Ctl.LoadThemeCss(cDropTightCss);
    D.Controller := Ctl;
    D.Font.PixelsPerInch := 96;
    D.Caption := 'Export';
    D.ArrowWidth := 18;
    D.Invalidate;                       // 换肤送到控件手上的就是一个裸 Invalidate
    w18 := D.Constraints.MinWidth;
    h18 := D.Constraints.MinHeight;

    D.ArrowWidth := 0;                  // setter 自带 Invalidate,下限跟着重量
    AssertEquals('dropping the arrow zone lowers the width floor by exactly 18',
      w18 - 18, D.Constraints.MinWidth);
    AssertEquals('the arrow sits BESIDE the caption, so the height floor does not move',
      h18, D.Constraints.MinHeight);
  finally
    D.Free; Ctl.Free;
  end;
end;

procedure TDropButtonsFloorTest.TestMenuFloorTracksTheThemeArrowMetric;
var
  Ctl: TTyStyleController;
  M: TMenuButtonAccess;
  narrow: Integer;
begin
  { TTyMenuButton 的箭头区是**主题度量**('--drop-arrow-width'),不是属性。皮肤把它调宽,
    最小宽度就得跟着宽——下限必须是推导出来的,写死一个常数在这里就等于"换了皮肤照旧截"。 }
  Ctl := TTyStyleController.Create(nil);
  M := TMenuButtonAccess.Create(nil);
  try
    M.Controller := Ctl;
    M.Font.PixelsPerInch := 96;
    M.Caption := 'Export';

    Ctl.LoadThemeCss(cDropTightCss);        // --drop-arrow-width: 18px
    M.Invalidate;
    narrow := M.Constraints.MinWidth;

    Ctl.LoadThemeCss(cDropWideArrowCss);    // 同样的字体和内边距,只有箭头 18 -> 40
    M.Invalidate;
    AssertEquals('a 22px wider arrow metric raises the width floor by exactly 22',
      narrow + 22, M.Constraints.MinWidth);
  finally
    M.Free; Ctl.Free;
  end;
end;

procedure TDropButtonsFloorTest.TestFloorFitsTheCaption;
var
  Ctl: TTyStyleController;
  D: TDropDownAccess;
  M: TMenuButtonAccess;
  tw, th: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  D := TDropDownAccess.Create(nil);
  M := TMenuButtonAccess.Create(nil);
  try
    Ctl.LoadThemeCss(cDropTightCss);
    D.Controller := Ctl; D.Font.PixelsPerInch := 96; D.Caption := '新建';
    M.Controller := Ctl; M.Font.PixelsPerInch := 96; M.Caption := '新建';
    D.Invalidate;
    M.Invalidate;
    D.CallMeasure(96, tw, th);

    AssertTrue(Format('the split button''s height floor covers the caption ink (%d >= %d)',
      [D.Constraints.MinHeight, th]), D.Constraints.MinHeight >= th);
    AssertTrue(Format('and the menu button''s does too (%d >= %d)',
      [M.Constraints.MinHeight, th]), M.Constraints.MinHeight >= th);

    { 提一个不可能的尺寸,钳制必须赢——把下限放进 Constraints 而不是"提议尺寸",图的就是
      这个:它在 SetBounds 里钳,不参与协商。 }
    D.Height := 4;
    D.Width := 4;
    AssertTrue('a too-short request is clamped up', D.Height >= th);
    AssertTrue('a too-narrow request is clamped up', D.Width >= tw);
  finally
    M.Free; D.Free; Ctl.Free;
  end;
end;

procedure TDropButtonsFloorTest.TestSmallerFontLowersTheFloor;
var
  Ctl: TTyStyleController;
  D: TDropDownAccess;
  bigH, bigW: Integer;
begin
  { 下限必须是**推导**出来的,不是一堵墙:字号和内边距调小,它就该跟着降。不然"嫌大就改
    CSS"这句话根本兑现不了。 }
  Ctl := TTyStyleController.Create(nil);
  D := TDropDownAccess.Create(nil);
  try
    D.Controller := Ctl;
    D.Font.PixelsPerInch := 96;
    D.Caption := '新建';

    Ctl.LoadThemeCss('TyButton { font-size: 20px; padding: 8px; }');
    D.Invalidate;
    bigH := D.Constraints.MinHeight;
    bigW := D.Constraints.MinWidth;

    Ctl.LoadThemeCss('TyButton { font-size: 8px; padding: 1px; }');
    D.Invalidate;
    AssertTrue(Format('a smaller font+padding lowers the height floor (%d -> %d)',
      [bigH, D.Constraints.MinHeight]), D.Constraints.MinHeight < bigH);
    AssertTrue(Format('...and the width floor with it (%d -> %d)',
      [bigW, D.Constraints.MinWidth]), D.Constraints.MinWidth < bigW);
  finally
    D.Free; Ctl.Free;
  end;
end;

procedure TDropButtonsFloorTest.TestFloorSurvivesAHeightPinningToolBar;
var
  F: TForm;
  Bar: TTyToolBar;
  D: TTyDropDownButton;
  M: TTyMenuButton;
begin
  { 下限绝不能把"提议高度"那场仗重新打起来:工具条把每个子控件钉到 ButtonHeight,子控件再
    提议一个自己的高度,两边来回顶,LCL 最后以 "ChangeBounds loop detected" 中止 —— demo
    当初就是这么在启动时死掉的。Constraints 在 SetBounds 里钳,不协商。
    **跑到这一行本身就是断言**。 }
  F := TForm.CreateNew(nil);
  try
    Bar := TTyToolBar.Create(F);
    Bar.Parent := F;
    Bar.ButtonHeight := 40;
    D := TTyDropDownButton.Create(Bar);
    D.Parent := Bar;
    D.Caption := '新建';
    D.AutoSize := True;
    M := TTyMenuButton.Create(Bar);
    M.Parent := Bar;
    M.Caption := '打开';
    M.AutoSize := True;
    Bar.ButtonHeight := 41;            // 真要是循环了,进程在这里就没了
    AssertTrue(Format('the bar asks for a height the split button''s floor can honour (%d)',
      [D.Constraints.MinHeight]), D.Constraints.MinHeight <= 40);
    AssertTrue(Format('and the menu button''s too (%d)', [M.Constraints.MinHeight]),
      M.Constraints.MinHeight <= 40);
  finally
    F.Free;
  end;
end;

{ TDropArrowZoneEdgeTest }

{ The one test here that needs a real HWND. The console runner never calls
  Application.Initialize, so the widgetset's window classes are unregistered and CreateHandle
  fails with 1407. Lazy + local, the same pattern test.base and test.combobox.simple use. }
var
  WidgetSetReady: Boolean = False;

procedure NeedWidgetSet;
begin
  if WidgetSetReady then Exit;
  Forms.Application.Initialize;
  WidgetSetReady := True;
end;

const
  { A theme built for this one question. border-width 0 so the frame contributes no ink;
    background BLACK and the divider colour (border-color) PURE GREEN so the divider column
    is the only green in the bitmap; the chevron and caption RED so neither can be mistaken
    for it. The padding is 4px 10px — the LEFT/RIGHT 10 is the whole point: it is the gap the
    paint and the hit test used to disagree by. }
  cDropEdgeCss =
    ':root { --drop-arrow-width: 18px; }' +
    'TyButton { background: #000000; color: #FF0000; border-color: #00FF00; ' +
    'border-width: 0px; padding: 4px 10px; font-size: 12px; }';
  cEdgeW = 140;
  cEdgeH = 28;

{ The x of the drawn split divider, read out of a real render of B — never computed from the
  same arithmetic the code under test uses, or the probe would agree with a fork of it. -1
  when no divider was drawn. }
function DrawnDividerX(B: TDropDownAccess): Integer;
var
  bmp: TBitmap;
  img: TBGRABitmap;
  x, y: Integer;
  P: TBGRAPixel;
begin
  Result := -1;
  bmp := TBitmap.Create;
  img := nil;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(cEdgeW, cEdgeH);
    bmp.Canvas.Brush.Style := bsSolid;
    bmp.Canvas.Brush.Color := clWhite;
    bmp.Canvas.FillRect(0, 0, cEdgeW, cEdgeH);
    B.DoRenderTo(bmp.Canvas, Rect(0, 0, cEdgeW, cEdgeH), 96);
    img := TBGRABitmap.Create(bmp);
    for x := 0 to cEdgeW - 1 do
      for y := 0 to cEdgeH - 1 do
      begin
        P := img.GetPixel(x, y);
        // Green ink, and not the red chevron/caption: the divider and nothing else.
        if (P.green > 150) and (P.red < 100) and (P.blue < 100) then
          Exit(x);
      end;
  finally
    img.Free;
    bmp.Free;
  end;
end;

procedure TDropArrowZoneEdgeTest.HandleDropDown(Sender: TObject);
begin
  Inc(FDropped);
end;

procedure TDropArrowZoneEdgeTest.HandleClick(Sender: TObject);
begin
  Inc(FClicked);
end;

procedure TDropArrowZoneEdgeTest.TestDrawnDividerIsTheFirstHitPixel;
var
  Ctl: TTyStyleController;
  B: TDropDownAccess;
  divX, padRight: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  B := nil;
  try
    Ctl.LoadThemeCss(cDropEdgeCss);
    B := TDropDownAccess.Create(nil);
    B.Controller := Ctl;
    B.Font.PixelsPerInch := 96;    // Scale() 1:1, so logical px == device px
    B.Caption := 'Save';
    B.SetBounds(0, 0, cEdgeW, cEdgeH);

    { The test is only meaningful with a real right padding — with 0 the drawn zone and a
      control-edge-relative zone coincide and every assertion below passes either way. }
    padRight := B.CallPadRight;
    AssertTrue('the fixture theme must have a NON-ZERO right padding, or this test cannot '
      + 'tell the two rules apart', padRight > 0);

    divX := DrawnDividerX(B);
    AssertTrue('sanity: a split button drew its divider somewhere', divX >= 0);
    { Where the paint really put it: back from the CONTENT box, not the control edge. Stated
      as a number so a reader can see the gap this test exists for -- the old hit rule
      started the zone at cEdgeW - 18 = 122, ten px to the right of this. }
    AssertEquals('the divider sits one right-padding in from the control edge',
      cEdgeW - padRight - 18, divX);

    // THE EDGE PROBE. One px either side of the drawn boundary; never the middle.
    AssertTrue('the drawn divider IS the first pixel that answers as arrow',
      B.CallIsInArrowZone(divX));
    AssertFalse('and the pixel just left of it is still the primary area',
      B.CallIsInArrowZone(divX - 1));
    // The far end: the right padding carries no ink but still belongs to the arrow.
    AssertTrue('the last pixel of the control is in the zone',
      B.CallIsInArrowZone(cEdgeW - 1));
  finally
    B.Free;
    Ctl.Free;
  end;
end;

procedure TDropArrowZoneEdgeTest.TestClickAtTheDrawnDividerRoutesToTheMenu;
var
  Ctl: TTyStyleController;
  B: TDropDownAccess;
  divX: Integer;
begin
  { The probe above asks the hit test; this one asks the ROUTER, which is what a user
    actually experiences: press on the drawn divider and the menu must be what happens. }
  Ctl := TTyStyleController.Create(nil);
  B := nil;
  FDropped := 0; FClicked := 0;
  try
    Ctl.LoadThemeCss(cDropEdgeCss);
    B := TDropDownAccess.Create(nil);
    B.Controller := Ctl;
    B.Font.PixelsPerInch := 96;
    B.Caption := 'Save';
    B.SetBounds(0, 0, cEdgeW, cEdgeH);
    B.OnDropDown := @HandleDropDown;
    B.OnClick := @HandleClick;

    divX := DrawnDividerX(B);
    AssertTrue('sanity: the divider was drawn', divX >= 0);

    B.PressAndClickAt(divX);
    AssertEquals('a press ON the drawn divider drops the menu', 1, FDropped);
    AssertEquals('and never runs the primary action', 0, FClicked);

    B.PressAndClickAt(divX - 1);
    AssertEquals('one px to its left is the primary action', 1, FClicked);
    AssertEquals('and does not drop', 1, FDropped);
  finally
    B.Free;
    Ctl.Free;
  end;
end;

procedure TDropArrowZoneEdgeTest.TestRealWindowClickOnTheDrawnEdgeOpensTheMenu;
var
  Ctl: TTyStyleController;
  F: TForm;
  B: TDropDownAccess;
  divX: Integer;
begin
  { The headless probes drive MouseDown/Click directly. This one goes through the control's
    real WindowProc on a real HWND (LCLSendMouse*Msg is the path the widgetset itself uses),
    because the whole defect class here is "the drawing is right and the WINDOW answers
    something else" — and that is precisely what a handle-less test cannot see.

    DropDownMenu is left nil ON PURPOSE: with a live handle DoDropDown would call the real
    PopUp, which spins a modal menu loop and would hang the suite. OnDropDown fires either
    way, so the routing is still what is being measured. }
  NeedWidgetSet;
  Ctl := TTyStyleController.Create(nil);
  F := TForm.CreateNew(nil);
  FDropped := 0; FClicked := 0;
  try
    Ctl.LoadThemeCss(cDropEdgeCss);
    F.SetBounds(0, 0, 300, 120);
    B := TDropDownAccess.Create(F);
    B.Parent := F;
    B.Controller := Ctl;
    B.Font.PixelsPerInch := 96;
    B.Caption := 'Save';
    B.SetBounds(10, 10, cEdgeW, cEdgeH);
    B.OnDropDown := @HandleDropDown;
    B.OnClick := @HandleClick;
    F.HandleNeeded;
    B.HandleNeeded;
    AssertTrue('sanity: the button really has a window', B.HandleAllocated);
    AssertTrue('sanity: no menu is assigned, so nothing can pop modally',
      B.DropDownMenu = nil);

    divX := DrawnDividerX(B);
    AssertTrue('sanity: the divider was drawn', divX >= 0);

    LCLSendMouseDownMsg(B, divX, cEdgeH div 2, mbLeft, []);
    LCLSendMouseUpMsg(B, divX, cEdgeH div 2, mbLeft, []);
    AssertEquals('a real click on the drawn arrow edge opens the menu', 1, FDropped);
    AssertEquals('and the primary action stays out of it', 0, FClicked);

    LCLSendMouseDownMsg(B, divX - 1, cEdgeH div 2, mbLeft, []);
    LCLSendMouseUpMsg(B, divX - 1, cEdgeH div 2, mbLeft, []);
    AssertEquals('one px to its left is still the primary action', 1, FClicked);
    AssertEquals('and does not drop', 1, FDropped);
  finally
    F.Free;
    Ctl.Free;
  end;
end;

procedure TDropArrowZoneEdgeTest.TestZoneLeftIsPureAndRefusesAnArrowThatCannotFit;
begin
  { The shared rule on its own, with no control around it. Content box [10..130) of a 140
    control, 18px arrow -> the zone opens at 112, NOT at 122 (which is what measuring from
    the control edge gives). }
  AssertEquals('the zone opens one arrow-width in from the CONTENT edge',
    112, TyDropArrowZoneLeft(10, 130, 18));
  AssertEquals('a zero arrow has no zone', -1, TyDropArrowZoneLeft(10, 130, 0));
  AssertEquals('a negative arrow has no zone', -1, TyDropArrowZoneLeft(10, 130, -4));
  AssertEquals('an empty content box has no zone', -1, TyDropArrowZoneLeft(130, 130, 18));
  AssertEquals('an inverted content box has no zone', -1, TyDropArrowZoneLeft(130, 10, 18));
  { REFUSE, do not halve: an arrow at least as wide as the content box is a misconfiguration,
    and the conservative answer leaves the primary action the whole face. The PAINT applies
    the identical test, so an arrow that cannot be hit is never drawn either. }
  AssertEquals('an arrow exactly as wide as the content box is refused',
    -1, TyDropArrowZoneLeft(10, 130, 120));
  AssertEquals('and a wider one too', -1, TyDropArrowZoneLeft(10, 130, 121));
  AssertEquals('one px narrower fits, and opens at the content left',
    11, TyDropArrowZoneLeft(10, 130, 119));
end;

initialization
  RegisterTest(TDropDownButtonTest);
  RegisterTest(TMenuButtonTest);
  RegisterTest(TDropButtonsAutoSizeTest);
  RegisterTest(TDropButtonsFloorTest);
  RegisterTest(TDropArrowZoneEdgeTest);
end.
