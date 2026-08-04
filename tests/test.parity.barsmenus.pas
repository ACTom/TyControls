unit test.parity.barsmenus;
{$mode objfpc}{$H+}

{ API-parity guards for the bars-and-menus round, written against the LCL declarations
  they mirror:

    C:/lazarus/lcl/comctrls.pp:2398        TToolBar.Indent (a LEADING gap, and nothing else)
    C:/lazarus/lcl/menus.pp:345            TMenuItem.ShowAlwaysCheckable
    C:/lazarus/lcl/include/menuitem.inc:1247  IsCheckItem = Checked or RadioItem
                                              or AutoCheck or ShowAlwaysCheckable
    C:/lazarus/lcl/comctrls.pp:171         TStatusBar.GetPanelIndexAt
    C:/lazarus/lcl/comctrls.pp:179 / :212  TStatusBar.AutoHint / OnHint
    C:/lazarus/lcl/include/statusbar.inc:70-88 / :268-269
                                           DoSetApplicationHint / DoHint / ExecuteAction
    C:/lazarus/lcl/comctrls.pp:45 / :92 / :209
                                           TStatusPanelStyle, TStatusPanel.Style, OnDrawPanel
    C:/lazarus/lcl/comctrls.pp:3992-3993   THeaderSection.MaxWidth / MinWidth
    C:/lazarus/lcl/comctrls.pp:3996        THeaderSection.Visible (default TRUE)
    C:/lazarus/lcl/comctrls.pp:4016        THeaderSections.Insert
    C:/lazarus/lcl/comctrls.pp:4122        THeaderControl.Anchors

  Four of these were the same defect in four places: a member the Object Inspector offers
  (or a name a ported form writes) that the control's own layout / paint path never reads.
  The rest are members that did not exist at all and whose absence had no workaround.

  Everything here is headless -- no shown form, no handle. The paint guards render through
  the controls' own RenderTo into an offscreen bitmap, as the rest of the repo does. }

interface

uses
  Classes, SysUtils, Types, TypInfo, Math, Controls, Graphics, Forms, Menus, ActnList,
  fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Controller,
  tyControls.ToolBar, tyControls.ToolBarEx, tyControls.StatusBar,
  tyControls.HeaderControl, tyControls.Menu;

type
  { Drives the protected align pass without a parent, a handle or the LCL align engine --
    which headless never runs (an unshown form leaves the whole tree unaligned). }
  TToolBarAccess = class(TTyToolBar)
  public
    procedure ForceLayout;
    function PadY: Integer;
  end;

  TToolBarExAccess = class(TTyToolBarEx)
  public
    procedure ForceLayout;
  end;

  { ---- 1. TToolBar.Indent is a LEADING gap, not also a vertical pad ---------- }
  TToolBarIndentParityTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FBar: TToolBarAccess;
    FTool: TTyToolSeparator;
    procedure Build(AIndent: Integer);
  protected
    procedure TearDown; override;
  published
    procedure TestLayoutTakesIndentAndTopPadSeparately;
    procedure TestFirstToolStartsAtIndent;
    procedure TestToolTopIsThePadNotTheIndent;
    procedure TestBarHeightDoesNotFollowTheIndent;
    procedure TestExOverrideUsesThePadToo;
  end;

  { ---- 2. TMenuItem.ShowAlwaysCheckable ------------------------------------ }
  TMenuCheckableProbe = class(TTyMenuView)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TMenuShowAlwaysCheckableTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FMenu: TPopupMenu;
    FView: TMenuCheckableProbe;
    FItem: TMenuItem;
    function Render: TBGRABitmap;
    function SlotInk: Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestBuildRowsCarriesShowAlwaysCheckable;
    procedure TestAutoCheckStillCarries;
    procedure TestPlainItemCarriesNeither;
    procedure TestShowAlwaysCheckableDrawsAnEmptyBox;
    procedure TestPlainItemDrawsNoBox;
  end;

  { ---- 3. TStatusBar.GetPanelIndexAt / AutoHint / OnHint / OnDrawPanel ------ }
  TStatusBarAccess = class(TTyStatusBar)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TStatusBarParityFixture = class(TTestCase)
  protected
    FCtl: TTyStyleController;
    FBar: TStatusBarAccess;
    procedure SetUp; override;
    procedure TearDown; override;
    function Render(AWidth, AHeight: Integer): TBGRABitmap;
  end;

  TStatusBarPanelIndexTest = class(TStatusBarParityFixture)
  published
    procedure TestGetPanelIndexAtFindsThePanel;
    procedure TestGetPanelIndexAtAgreesWithPanelAtPos;
    procedure TestGetPanelIndexAtIsMinusOneInSimpleMode;
  end;

  TStatusBarAutoHintTest = class(TStatusBarParityFixture)
  private
    FHintCalls: Integer;
    procedure HandleHint(Sender: TObject);
    { Dispatch AText as the LCL dispatches an Application.Hint change. }
    function FireHint(const AText: string): Boolean;
  published
    procedure TestHintIsIgnoredWhileAutoHintIsOff;
    procedure TestHintReachesPanelZero;
    procedure TestHintReachesSimpleTextInSimpleMode;
    procedure TestOnHintTakesOverAndTheBarWritesNothing;
    procedure TestANonHintActionIsNotSwallowed;
  end;

  TStatusBarOwnerDrawTest = class(TStatusBarParityFixture)
  private
    FDrawn: Integer;
    FLastRect: TRect;
    FLastPanel: TTyStatusPanel;
    procedure HandleDrawPanel(AStatusBar: TTyStatusBar; APanel: TTyStatusPanel;
      APainter: TTyPainter; const ARect: TRect);
  published
    procedure TestOwnerDrawFiresOnlyForOwnerDrawPanels;
    procedure TestOwnerDrawGetsTheCellRect;
    procedure TestOwnerDrawSuppressesTheDefaultText;
    procedure TestOwnerDrawInkSurvivesTheComposite;
  end;

  { ---- 4. THeaderSection.Visible / MinWidth / MaxWidth, Insert, Anchors ----- }
  THeaderSectionAccess = class(TTyHeaderControl)
  public
    procedure PressDown(X: Integer);
    procedure PressMove(X: Integer);
    procedure PressUp(X: Integer);
  end;

  THeaderSectionModelTest = class(TTestCase)
  private
    FHdr: THeaderSectionAccess;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestADefaultSectionRecordIsVisible;
    procedure TestAddedSectionIsVisible;
    procedure TestHiddenSectionTilesZeroWide;
    procedure TestHiddenSectionIsNotHitTested;
    procedure TestHiddenLastSectionDoesNotAbsorbTheRemainder;
    procedure TestHiddenSectionBoundaryIsNotGrabbable;
    procedure TestHidingAndShowingKeepsWidthAndSort;
    procedure TestMinWidthBelowTheStripFloorIsHonoured;
    procedure TestMaxWidthCapsTheSetter;
    procedure TestMinWidthWinsOverAContradictoryMaxWidth;
    procedure TestDragCannotCrossTheSectionMinWidth;
    procedure TestDragCannotCrossTheSectionMaxWidth;
    procedure TestInsertSectionShiftsTheRestRight;
    procedure TestInsertPastTheEndAppends;
    procedure TestInsertAtNegativePrepends;
    procedure TestAnchorsIsPublished;
  end;

implementation

const
  HdrClient: TRect = (Left: 0; Top: 0; Right: 300; Bottom: 26);

{ ========================================================================== }
{ 1. TToolBar.Indent                                                          }
{ ========================================================================== }

procedure TToolBarAccess.ForceLayout;
var
  r: TRect;
begin
  r := ClientRect;
  AlignControls(nil, r);
end;

function TToolBarAccess.PadY: Integer;
begin
  Result := ContentPadY;
end;

procedure TToolBarExAccess.ForceLayout;
var
  r: TRect;
begin
  r := ClientRect;
  AlignControls(nil, r);
end;

procedure TToolBarIndentParityTest.Build(AIndent: Integer);
begin
  FCtl := TTyStyleController.Create(nil);
  FBar := TToolBarAccess.Create(nil);
  FBar.Controller := FCtl;
  FBar.Font.PixelsPerInch := 96;
  FBar.SetBounds(0, 0, 300, 30);
  FBar.Indent := AIndent;
  FTool := TTyToolSeparator.Create(FBar);
  FTool.Parent := FBar;
  FTool.SetBounds(0, 0, 20, 24);
end;

procedure TToolBarIndentParityTest.TearDown;
begin
  FreeAndNil(FBar);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TToolBarIndentParityTest.TestLayoutTakesIndentAndTopPadSeparately;
var
  rects: TTyRectArray;
  rows: Integer;
  sz: array[0..0] of TSize;
begin
  { The pure solver is where the two used to be ONE argument. Distinct values in, distinct
    values out: a bar indented 20px does not start its row 20px down. }
  sz[0].cx := 40; sz[0].cy := 24;
  rects := TyToolbarLayout(sz, 200, 20, 3, 2, 24, False, rows);
  AssertEquals('rows', 1, rows);
  AssertEquals('left == indent', 20, rects[0].Left);
  AssertEquals('top == top pad', 3, rects[0].Top);
  AssertEquals('bottom == top pad + button height', 27, rects[0].Bottom);
end;

procedure TToolBarIndentParityTest.TestFirstToolStartsAtIndent;
begin
  Build(24);
  FBar.ForceLayout;
  AssertEquals('the leading gap is what Indent means', 24, FTool.Left);
end;

procedure TToolBarIndentParityTest.TestToolTopIsThePadNotTheIndent;
begin
  Build(24);
  FBar.ForceLayout;
  { Indent 24 used to push every tool 24px DOWN as well as 24px right. }
  AssertEquals('tool sits at the vertical pad', FBar.PadY, FTool.Top);
  AssertTrue('and the pad is not the indent', FBar.PadY <> 24);
end;

procedure TToolBarIndentParityTest.TestBarHeightDoesNotFollowTheIndent;
var
  hSmall, hLarge: Integer;
begin
  Build(4);
  FBar.ForceLayout;
  hSmall := FBar.Height;
  FreeAndNil(FBar);
  FreeAndNil(FCtl);
  Build(24);
  FBar.ForceLayout;
  hLarge := FBar.Height;
  { Indent 4 -> 24 used to add 40px of height (Indent*2). A horizontal gap has no business
    in a height at all. }
  AssertEquals('indent does not change the bar height', hSmall, hLarge);
end;

procedure TToolBarIndentParityTest.TestExOverrideUsesThePadToo;
var
  ex: TToolBarExAccess;
  ctl: TTyStyleController;
  tool: TTyToolSeparator;
begin
  { The Ex subclass overrides AlignControls wholesale, so a fix that landed only on the base
    would leave the two bars sitting their tools at different heights. }
  ctl := TTyStyleController.Create(nil);
  ex := TToolBarExAccess.Create(nil);
  try
    ex.Controller := ctl;
    ex.Font.PixelsPerInch := 96;
    ex.SetBounds(0, 0, 300, 30);
    ex.Wrapable := False;
    ex.Indent := 24;
    tool := TTyToolSeparator.Create(ex);
    tool.Parent := ex;
    tool.SetBounds(0, 0, 20, 24);
    ex.ForceLayout;
    AssertEquals('Ex places the tool at the leading gap', 24, tool.Left);
    AssertTrue('Ex does NOT push it down by the indent', tool.Top <> 24);
  finally
    ex.Free;
    ctl.Free;
  end;
end;

{ ========================================================================== }
{ 2. TMenuItem.ShowAlwaysCheckable                                            }
{ ========================================================================== }

procedure TMenuCheckableProbe.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TMenuShowAlwaysCheckableTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  // Black plate, WHITE row text and border: the empty check box is stroked in the row's
  // text colour, so white ink in the left slot is the box and nothing else.
  FCtl.LoadThemeCss(
    'TyMenuView { background: #000000; color: #FFFFFF; padding: 4px; '
    + 'border-width: 0px; border-radius: 0px; }'
    + 'TyMenuItem { background: alpha(#FFFFFF, 0); color: #FFFFFF; '
    + 'border-color: #FFFFFF; border-radius: 0px; padding: 4px; font-size: 12px; }');
  FMenu := TPopupMenu.Create(nil);
  FView := TMenuCheckableProbe.Create(nil);
  FView.Controller := FCtl;
  FView.Font.PixelsPerInch := 96;
  FItem := TMenuItem.Create(FMenu);
  // A caption of spaces: no glyph ink of its own, so the only white in the slot band is
  // the check box. (An empty caption would still measure and centre nothing.)
  FItem.Caption := '   ';
  FMenu.Items.Add(FItem);
end;

procedure TMenuShowAlwaysCheckableTest.TearDown;
begin
  FreeAndNil(FView);
  FreeAndNil(FMenu);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

function TMenuShowAlwaysCheckableTest.Render: TBGRABitmap;
var
  Bmp: TBitmap;
begin
  FView.SetRows(TyBuildMenuRows(FMenu.Items));
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(160, 60);
    Bmp.Canvas.Brush.Color := clBlack;
    Bmp.Canvas.FillRect(0, 0, 160, 60);
    FView.RenderTo(Bmp.Canvas, Rect(0, 0, 160, 60), 96);
    Result := TBGRABitmap.Create(Bmp);
  finally
    Bmp.Free;
  end;
end;

{ White pixels in the LEFT slot column of the first row -- where the check/radio glyph and
  the empty checkable box are drawn, and nothing else is. }
function TMenuShowAlwaysCheckableTest.SlotInk: Integer;
var
  bmp: TBGRABitmap;
  x, y: Integer;
  P: TBGRAPixel;
begin
  Result := 0;
  bmp := Render;
  try
    for y := 0 to Min(bmp.Height, 40) - 1 do
      for x := 0 to Min(bmp.Width, 28) - 1 do
      begin
        P := bmp.GetPixel(x, y);
        if (P.red > 150) and (P.green > 150) and (P.blue > 150) then Inc(Result);
      end;
  finally
    bmp.Free;
  end;
end;

procedure TMenuShowAlwaysCheckableTest.TestBuildRowsCarriesShowAlwaysCheckable;
var
  rows: TTyMenuRowArray;
begin
  FItem.ShowAlwaysCheckable := True;
  rows := TyBuildMenuRows(FMenu.Items);
  AssertEquals('one row', 1, Length(rows));
  AssertTrue('ShowAlwaysCheckable reaches the row model', rows[0].AlwaysCheckable);
end;

procedure TMenuShowAlwaysCheckableTest.TestAutoCheckStillCarries;
var
  rows: TTyMenuRowArray;
begin
  { The other half of LCL's IsCheckItem. Pinned so a future edit cannot swap one flag for
    the other and still look green. }
  FItem.AutoCheck := True;
  rows := TyBuildMenuRows(FMenu.Items);
  AssertTrue('AutoCheck reaches the row model', rows[0].AlwaysCheckable);
end;

procedure TMenuShowAlwaysCheckableTest.TestPlainItemCarriesNeither;
var
  rows: TTyMenuRowArray;
begin
  rows := TyBuildMenuRows(FMenu.Items);
  AssertFalse('a plain command is not checkable', rows[0].AlwaysCheckable);
end;

procedure TMenuShowAlwaysCheckableTest.TestShowAlwaysCheckableDrawsAnEmptyBox;
var
  plain, checkable: Integer;
begin
  plain := SlotInk;
  FItem.ShowAlwaysCheckable := True;
  checkable := SlotInk;
  { The property is only worth anything if it changes pixels: a flag that flips and paints
    nothing is the same lie in a new place. }
  AssertTrue(Format('the box adds ink to the slot (plain=%d checkable=%d)', [plain, checkable]),
    checkable > plain + 8);
end;

procedure TMenuShowAlwaysCheckableTest.TestPlainItemDrawsNoBox;
begin
  AssertTrue('an ordinary command leaves the slot empty', SlotInk < 8);
end;

{ ========================================================================== }
{ 3. TStatusBar                                                               }
{ ========================================================================== }

procedure TStatusBarAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TStatusBarParityFixture.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  // Black plate, white text: any coloured pixel came from an owner-draw handler.
  FCtl.LoadThemeCss(
    'TyStatusBar { background: #000000; color: #FFFFFF; border-width: 0px; '
    + 'border-radius: 0px; font-size: 12px; }');
  FBar := TStatusBarAccess.Create(nil);
  FBar.Controller := FCtl;
  FBar.Font.PixelsPerInch := 96;
  FBar.SizeGrip := False;          // the grip dots would count as ink at the right edge
  FBar.SetBounds(0, 0, 300, 22);
end;

procedure TStatusBarParityFixture.TearDown;
begin
  FreeAndNil(FBar);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

function TStatusBarParityFixture.Render(AWidth, AHeight: Integer): TBGRABitmap;
var
  Bmp: TBitmap;
begin
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(AWidth, AHeight);
    Bmp.Canvas.Brush.Color := clBlack;
    Bmp.Canvas.FillRect(0, 0, AWidth, AHeight);
    FBar.RenderTo(Bmp.Canvas, Rect(0, 0, AWidth, AHeight), 96);
    Result := TBGRABitmap.Create(Bmp);
  finally
    Bmp.Free;
  end;
end;

{ ---- GetPanelIndexAt ----------------------------------------------------- }

procedure TStatusBarPanelIndexTest.TestGetPanelIndexAtFindsThePanel;
begin
  FBar.Panels.Add.Width := 60;
  FBar.Panels.Add.Width := 60;
  FBar.Panels.Add.Width := 60;
  { `if StatusBar1.GetPanelIndexAt(X, Y) = 2 then` is the idiom out of every ported
    OnMouseDown handler, and it did not compile at all. }
  AssertEquals('inside panel 1', 1, FBar.GetPanelIndexAt(70, 10));
  AssertEquals('inside panel 0', 0, FBar.GetPanelIndexAt(10, 10));
end;

procedure TStatusBarPanelIndexTest.TestGetPanelIndexAtAgreesWithPanelAtPos;
var
  x: Integer;
begin
  FBar.Panels.Add.Width := 40;
  FBar.Panels.Add.Width := 90;
  { An alias that disagreed with the thing it aliases would be worse than no alias. }
  for x := -5 to 305 do
    AssertEquals(Format('x=%d', [x]), FBar.PanelAtPos(x, 10), FBar.GetPanelIndexAt(x, 10));
end;

procedure TStatusBarPanelIndexTest.TestGetPanelIndexAtIsMinusOneInSimpleMode;
begin
  FBar.Panels.Add.Width := 60;
  FBar.SimplePanel := True;
  AssertEquals('no panels to be at', -1, FBar.GetPanelIndexAt(10, 10));
end;

{ ---- AutoHint / OnHint --------------------------------------------------- }

procedure TStatusBarAutoHintTest.HandleHint(Sender: TObject);
begin
  Inc(FHintCalls);
end;

function TStatusBarAutoHintTest.FireHint(const AText: string): Boolean;
var
  A: TCustomHintAction;
begin
  { Exactly what TApplication.SetHint builds and executes when Application.Hint changes
    (application.inc:1544-1556). }
  A := TCustomHintAction.Create(nil);
  try
    A.Hint := AText;
    Result := FBar.ExecuteAction(A);
  finally
    A.Free;
  end;
end;

procedure TStatusBarAutoHintTest.TestHintIsIgnoredWhileAutoHintIsOff;
begin
  FBar.Panels.Add.Text := 'untouched';
  FBar.AutoHint := False;
  FireHint('Save the document');
  AssertEquals('AutoHint off leaves the panel alone', 'untouched', FBar.Panels[0].Text);
end;

procedure TStatusBarAutoHintTest.TestHintReachesPanelZero;
begin
  FBar.Panels.Add;
  FBar.Panels.Add.Text := 'second';
  FBar.AutoHint := True;
  AssertTrue('the bar answers the hint action', FireHint('Save the document'));
  AssertEquals('panel 0 shows the hint', 'Save the document', FBar.Panels[0].Text);
  AssertEquals('and only panel 0', 'second', FBar.Panels[1].Text);
end;

procedure TStatusBarAutoHintTest.TestHintReachesSimpleTextInSimpleMode;
begin
  FBar.SimplePanel := True;
  FBar.AutoHint := True;
  FireHint('Ready');
  AssertEquals('SimpleText shows the hint', 'Ready', FBar.SimpleText);
end;

procedure TStatusBarAutoHintTest.TestOnHintTakesOverAndTheBarWritesNothing;
begin
  FBar.Panels.Add.Text := 'mine';
  FBar.AutoHint := True;
  FHintCalls := 0;
  FBar.OnHint := @HandleHint;
  FireHint('Save the document');
  AssertEquals('the handler ran', 1, FHintCalls);
  { LCL's rule: a handler is a takeover, not a notification (statusbar.inc:70-80). A bar
    that fired the event AND then overwrote panel 0 would make the event pointless. }
  AssertEquals('the bar did not also write it', 'mine', FBar.Panels[0].Text);
end;

procedure TStatusBarAutoHintTest.TestANonHintActionIsNotSwallowed;
var
  A: TAction;
begin
  FBar.AutoHint := True;
  A := TAction.Create(nil);
  try
    { Only a hint action is intercepted; anything else must reach the inherited handling,
      or turning AutoHint on would quietly break every other action on the bar. }
    AssertFalse('an unrelated action falls through', FBar.ExecuteAction(A));
  finally
    A.Free;
  end;
end;

{ ---- OnDrawPanel --------------------------------------------------------- }

procedure TStatusBarOwnerDrawTest.HandleDrawPanel(AStatusBar: TTyStatusBar;
  APanel: TTyStatusPanel; APainter: TTyPainter; const ARect: TRect);
var
  f: TTyFill;
begin
  Inc(FDrawn);
  FLastRect := ARect;
  FLastPanel := APanel;
  f := Default(TTyFill);
  f.Kind := tfkSolid;
  f.Color := TyRGBA(255, 0, 0, 255);
  APainter.FillBackground(ARect, f, 0);
end;

procedure TStatusBarOwnerDrawTest.TestOwnerDrawFiresOnlyForOwnerDrawPanels;
var
  bmp: TBGRABitmap;
begin
  FBar.Panels.Add.Width := 100;
  FBar.Panels.Add.Width := 100;
  FBar.Panels[1].Style := psOwnerDraw;
  FBar.OnDrawPanel := @HandleDrawPanel;
  FDrawn := 0;
  bmp := Render(300, 22);
  try
    AssertEquals('exactly one owner-draw cell', 1, FDrawn);
    AssertSame('and it is the one that asked', FBar.Panels[1], FLastPanel);
  finally
    bmp.Free;
  end;
end;

procedure TStatusBarOwnerDrawTest.TestOwnerDrawGetsTheCellRect;
var
  bmp: TBGRABitmap;
begin
  FBar.Panels.Add.Width := 100;
  FBar.Panels.Add.Width := 100;
  FBar.Panels[1].Style := psOwnerDraw;
  FBar.OnDrawPanel := @HandleDrawPanel;
  bmp := Render(300, 22);
  try
    { The panel's own cell, not the whole bar -- a handler given the bar's rect would paint
      over its neighbours. The first panel starts at the bar's padding (6px at 96ppi). }
    AssertEquals('cell left', 106, FLastRect.Left);
    AssertEquals('cell top', 0, FLastRect.Top);
    AssertEquals('cell bottom', 22, FLastRect.Bottom);
    AssertTrue('cell right is past its left', FLastRect.Right > FLastRect.Left);
  finally
    bmp.Free;
  end;
end;

procedure TStatusBarOwnerDrawTest.TestOwnerDrawSuppressesTheDefaultText;
var
  bmp: TBGRABitmap;
  x, y, white: Integer;
  P: TBGRAPixel;
begin
  FBar.Panels.Add.Width := 280;
  FBar.Panels[0].Text := 'MMMMMMMM';
  FBar.Panels[0].Style := psOwnerDraw;
  // No handler assigned: an owner-draw cell with nobody to draw it stays blank rather than
  // falling back to the text, which is what "the app owns this cell" has to mean.
  white := 0;
  bmp := Render(300, 22);
  try
    for y := 0 to bmp.Height - 1 do
      for x := 0 to bmp.Width - 1 do
      begin
        P := bmp.GetPixel(x, y);
        if (P.red > 200) and (P.green > 200) and (P.blue > 200) then Inc(white);
      end;
  finally
    bmp.Free;
  end;
  AssertTrue(Format('psOwnerDraw draws no caption (white=%d)', [white]), white < 10);
end;

procedure TStatusBarOwnerDrawTest.TestOwnerDrawInkSurvivesTheComposite;
var
  bmp: TBGRABitmap;
  x, y, red: Integer;
  P: TBGRAPixel;
begin
  FBar.Panels.Add.Width := 280;
  FBar.Panels[0].Style := psOwnerDraw;
  FBar.OnDrawPanel := @HandleDrawPanel;
  red := 0;
  bmp := Render(300, 22);
  try
    for y := 0 to bmp.Height - 1 do
      for x := 0 to bmp.Width - 1 do
      begin
        P := bmp.GetPixel(x, y);
        if (P.red > 150) and (P.green < 90) and (P.blue < 90) then Inc(red);
      end;
  finally
    bmp.Free;
  end;
  { The handler draws through the PAINTER, mid-pass. A handler that had been handed the
    Canvas instead would have every pixel overwritten by EndPaint's composite -- which is
    the trap this signature exists to avoid, so it is worth a pixel to prove. }
  AssertTrue(Format('the handler''s fill reached the surface (red=%d)', [red]), red > 500);
end;

{ ========================================================================== }
{ 4. THeaderSection                                                           }
{ ========================================================================== }

procedure THeaderSectionAccess.PressDown(X: Integer);
begin
  MouseDown(mbLeft, [], X, 8);
end;

procedure THeaderSectionAccess.PressMove(X: Integer);
begin
  MouseMove([], X, 8);
end;

procedure THeaderSectionAccess.PressUp(X: Integer);
begin
  MouseUp(mbLeft, [], X, 8);
end;

procedure THeaderSectionModelTest.SetUp;
begin
  FHdr := THeaderSectionAccess.Create(nil);
  FHdr.Font.PixelsPerInch := 96;    // logical px == device px
  FHdr.SetBounds(0, 0, 300, 26);
end;

procedure THeaderSectionModelTest.TearDown;
begin
  FreeAndNil(FHdr);
  inherited TearDown;
end;

procedure THeaderSectionModelTest.TestADefaultSectionRecordIsVisible;
var
  S: TTyHeaderSection;
begin
  S := Default(TTyHeaderSection);
  { THeaderSection.Visible is `default true` (comctrls.pp:3996). A value record is born
    zero-filled, so a plain `Visible: Boolean` field would make every section that came out
    of SetLength or Default() invisible -- the storage is inverted precisely so it does not. }
  AssertTrue('a zero-filled section is visible', S.Visible);
end;

procedure THeaderSectionModelTest.TestAddedSectionIsVisible;
begin
  FHdr.AddSection('A', 80);
  AssertTrue('a freshly added section is visible', FHdr.SectionVisible[0]);
end;

procedure THeaderSectionModelTest.TestHiddenSectionTilesZeroWide;
begin
  FHdr.AddSection('A', 80);
  FHdr.AddSection('B', 80);
  FHdr.AddSection('C', 80);
  FHdr.SectionVisible[1] := False;
  AssertEquals('the hidden section paints nothing', 0, FHdr.EffectiveSectionWidth[1]);
  AssertEquals('its neighbour is unchanged', 80, FHdr.EffectiveSectionWidth[0]);
end;

procedure THeaderSectionModelTest.TestHiddenSectionIsNotHitTested;
var
  widths: array[0..2] of Integer;
begin
  { A hidden section tiles zero-wide, so no X can land in it -- the half-open [L, R) span
    of a zero-width rect is empty. }
  widths[0] := 80; widths[1] := 0; widths[2] := 80;
  AssertEquals('x at the hidden section''s position -> its neighbour', 2,
    TyHeaderSectionAtX(widths, HdrClient, 80));
  AssertEquals('x inside section 0', 0, TyHeaderSectionAtX(widths, HdrClient, 40));
end;

procedure THeaderSectionModelTest.TestHiddenLastSectionDoesNotAbsorbTheRemainder;
var
  rects: TTyHeaderRectArray;
  widths: array[0..2] of Integer;
begin
  widths[0] := 80; widths[1] := 80; widths[2] := 0;
  rects := TyHeaderSectionRects(widths, HdrClient);
  { The remainder used to go to the LAST index unconditionally, so hiding the trailing
    section made it reappear as the widest thing on the strip. }
  AssertEquals('the hidden section stays zero-wide', 0, rects[2].Right - rects[2].Left);
  AssertEquals('the last VISIBLE one absorbs instead', 300, rects[1].Right);
end;

procedure THeaderSectionModelTest.TestHiddenSectionBoundaryIsNotGrabbable;
var
  mid: array[0..2] of Integer;
  lead: array[0..2] of Integer;
  tail: array[0..1] of Integer;
begin
  { A hidden section's "right edge" is not a boundary: it either sits exactly on a
    neighbour's or, at the ends, on the control edge. Offering any of them as a drag handle
    lets the user resize a column that is not there.

    The three arrangements are NOT interchangeable, and only two of them actually reach the
    guard -- a middle hole is masked by the nearest-boundary tie-break, so testing only that
    one proved nothing. }
  mid[0] := 80; mid[1] := 0; mid[2] := 80;
  AssertEquals('middle hole: the grab at x=80 belongs to section 0', 0,
    TyHeaderResizeEdgeAtX(mid, HdrClient, 80, 4));

  { Hidden FIRST: its right edge is at x=0, which is the left edge of the strip. }
  lead[0] := 0; lead[1] := 80; lead[2] := 80;
  AssertEquals('leading hole: x=0 grabs nothing', -1,
    TyHeaderResizeEdgeAtX(lead, HdrClient, 0, 4));
  AssertEquals('but the first REAL boundary is still grabbable', 1,
    TyHeaderResizeEdgeAtX(lead, HdrClient, 80, 4));

  { Hidden LAST: section 0 has absorbed the remainder, so its right edge IS the control
    edge -- the one edge that was never resizable. }
  tail[0] := 80; tail[1] := 0;
  AssertEquals('trailing hole: the absorbed right edge grabs nothing', -1,
    TyHeaderResizeEdgeAtX(tail, HdrClient, 300, 4));
end;

procedure THeaderSectionModelTest.TestHidingAndShowingKeepsWidthAndSort;
begin
  FHdr.AddSection('A', 80);
  FHdr.AddSection('B', 137);
  FHdr.Sort[1] := hsdDescending;
  FHdr.SectionVisible[1] := False;
  FHdr.SectionVisible[1] := True;
  { The whole point of hide-vs-delete: a "choose columns" menu must be able to put a column
    back exactly as the user left it. }
  AssertEquals('width survived', 137, FHdr.SectionWidth[1]);
  AssertTrue('sort survived', FHdr.Sort[1] = hsdDescending);
end;

procedure THeaderSectionModelTest.TestMinWidthBelowTheStripFloorIsHonoured;
begin
  FHdr.AddSection('chk', 100);
  FHdr.SectionMinWidth[0] := 12;
  FHdr.SectionWidth[0] := 12;
  { The strip-wide floor is 16. A 24px checkbox column -- or a 12px one -- is a real column,
    and an explicit MinWidth is the statement that this section knows its own floor. }
  AssertEquals('an explicit MinWidth replaces the strip floor', 12, FHdr.SectionWidth[0]);
end;

procedure THeaderSectionModelTest.TestMaxWidthCapsTheSetter;
begin
  FHdr.AddSection('A', 100);
  FHdr.SectionMaxWidth[0] := 120;
  FHdr.SectionWidth[0] := 400;
  AssertEquals('capped at MaxWidth', 120, FHdr.SectionWidth[0]);
  FHdr.SectionMaxWidth[0] := 0;
  FHdr.SectionWidth[0] := 400;
  AssertEquals('0 means unbounded', 400, FHdr.SectionWidth[0]);
end;

procedure THeaderSectionModelTest.TestMinWidthWinsOverAContradictoryMaxWidth;
begin
  FHdr.AddSection('A', 100);
  FHdr.SectionMaxWidth[0] := 30;
  FHdr.SectionMinWidth[0] := 60;
  FHdr.SectionWidth[0] := 100;
  { A section that declared both cannot have both. Floor last, so it never lands below a
    minimum it asked for -- pinning it there would be the silent-wrong-answer version. }
  AssertEquals('MinWidth wins', 60, FHdr.SectionWidth[0]);
end;

procedure THeaderSectionModelTest.TestDragCannotCrossTheSectionMinWidth;
begin
  FHdr.AddSection('A', 100);
  FHdr.AddSection('B', 100);
  FHdr.SectionMinWidth[0] := 70;
  FHdr.PressDown(100);        // grab the boundary between 0 and 1
  FHdr.PressMove(20);         // drag far left
  FHdr.PressUp(20);
  { A constraint the setter honours and the drag ignores is no constraint: the user drags
    straight through it. }
  AssertEquals('the drag stopped at MinWidth', 70, FHdr.SectionWidth[0]);
end;

procedure THeaderSectionModelTest.TestDragCannotCrossTheSectionMaxWidth;
begin
  FHdr.AddSection('A', 100);
  FHdr.AddSection('B', 100);
  FHdr.SectionMaxWidth[0] := 130;
  FHdr.PressDown(100);
  FHdr.PressMove(280);
  FHdr.PressUp(280);
  AssertEquals('the drag stopped at MaxWidth', 130, FHdr.SectionWidth[0]);
end;

procedure THeaderSectionModelTest.TestInsertSectionShiftsTheRestRight;
var
  at: Integer;
begin
  FHdr.AddSection('A', 40);
  FHdr.AddSection('C', 60);
  at := FHdr.InsertSection(1, 'B', 50);
  AssertEquals('landed where asked', 1, at);
  AssertEquals('count', 3, FHdr.SectionCount);
  AssertEquals('0', 'A', FHdr.SectionText[0]);
  AssertEquals('1', 'B', FHdr.SectionText[1]);
  AssertEquals('2', 'C', FHdr.SectionText[2]);
  AssertEquals('the shifted one kept its width', 60, FHdr.SectionWidth[2]);
  AssertEquals('the new one got its width', 50, FHdr.SectionWidth[1]);
  AssertTrue('and it is visible', FHdr.SectionVisible[1]);
end;

procedure THeaderSectionModelTest.TestInsertPastTheEndAppends;
begin
  FHdr.AddSection('A', 40);
  AssertEquals('appends', 1, FHdr.InsertSection(9, 'B', 50));
  AssertEquals('1', 'B', FHdr.SectionText[1]);
end;

procedure THeaderSectionModelTest.TestInsertAtNegativePrepends;
begin
  FHdr.AddSection('A', 40);
  AssertEquals('prepends', 0, FHdr.InsertSection(-3, 'B', 50));
  AssertEquals('0', 'B', FHdr.SectionText[0]);
  AssertEquals('1', 'A', FHdr.SectionText[1]);
end;

procedure THeaderSectionModelTest.TestAnchorsIsPublished;
begin
  { Runtime-settable was never the problem (Anchors is public on TControl); being absent
    from the Object Inspector and from the .lfm was. }
  AssertTrue('Anchors is published on the header strip',
    GetPropInfo(TTyHeaderControl, 'Anchors') <> nil);
end;

initialization
  RegisterTest(TToolBarIndentParityTest);
  RegisterTest(TMenuShowAlwaysCheckableTest);
  RegisterTest(TStatusBarPanelIndexTest);
  RegisterTest(TStatusBarAutoHintTest);
  RegisterTest(TStatusBarOwnerDrawTest);
  RegisterTest(THeaderSectionModelTest);
end.
