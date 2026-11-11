unit test.statusbar;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, Controls, Graphics, Forms, LCLType, LMessages,
  fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Controller, tyControls.Base,
  tyControls.StatusBar;
type
  TStatusBarGeomTest = class(TTestCase)
  published
    procedure TestPanelRectsFixed;
    procedure TestPanelRectsFillPanel;
    procedure TestPanelRectsPadding;
    procedure TestPanelRectsFillFirstOnly;
    procedure TestPanelRectsOverflowAndEmpty;
  end;

  { Access subclass that re-exposes protected RenderTo as public }
  TTyStatusBarPixAccess = class(TTyStatusBar)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TStatusBarPixelTest = class(TTestCase)
  published
    procedure TestBodyPixelIsDark;
  end;

  { The bar's protected seams, and the mouse as LCL delivers it: MouseDown and MouseUp are the
    two virtuals a press and a release arrive through. }
  TStatusBarProbe = class(TTyStatusBar)
  protected
    function StartWindowResize(AEdge: Integer): Boolean; override;
  public
    { Stands in for the OS: True makes a press on the grip or the bottom strip a window resize,
      as it is on a resizable window on Windows. }
    WindowTakesResize: Boolean;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Press(X, Y: Integer; AButton: TMouseButton = mbLeft);
    procedure Release(X, Y: Integer; AButton: TMouseButton = mbLeft);
    procedure PressAndRelease(X, Y: Integer; AButton: TMouseButton = mbLeft);
    { One LCL layout pass over the bar's children, as a live window runs it after any child
      moved, resized or changed Visible (headless nothing calls it). }
    procedure LayoutPass;
    procedure Designing;
    function PreferredHeight: Integer;
  public
    Invalidations: Integer;   // how often the whole bar was asked to repaint
    procedure Invalidate; override;
  end;

  { A plain graphic child: something to put in a panel. Registered, so a form file can name it. }
  TStatusBarTestBox = class(TGraphicControl)
  protected
    procedure BoundsChanged; override;
  public
    { Fired from inside SetBounds, where a live LCL starts the parent's layout pass. }
    OnMoved: TNotifyEvent;
    procedure Designing;
  end;

  { A bar 300 x 22 at 96 PPI on a form of its own size (so the bar is the window's bottom
    edge and corner), with three panels: 100 wide, the fill panel, 80 wide. Left to right
    their cells are [6,106) [106,214) [214,294); mirrored [194,294) [86,194) [6,86). }
  TStatusBarPanelFixture = class(TTestCase)
  protected
    FCtl: TTyStyleController;
    FForm: TForm;
    FBar: TStatusBarProbe;
    FClicks: TStringList;     // the Index of every panel OnPanelClick reported, in order
    FDrawn: array of TRect;   // the rect OnDrawPanel was handed, by panel index
    procedure SetUp; override;
    procedure TearDown; override;
    procedure HandlePanelClick(Sender: TObject; APanel: TTyStatusPanel);
    procedure HandleMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer);
    procedure HandleClick(Sender: TObject);
    procedure HandleBoxMoved(Sender: TObject);
    procedure HandleNoteRect(AStatusBar: TTyCustomStatusBar; APanel: TTyStatusPanel;
      APainter: TTyPainter; const ARect: TRect);
    procedure HandleDrawAsText(AStatusBar: TTyCustomStatusBar; APanel: TTyStatusPanel;
      APainter: TTyPainter; const ARect: TRect);
    procedure HandleDrawByHand(AStatusBar: TTyCustomStatusBar; APanel: TTyStatusPanel;
      APainter: TTyPainter; const ARect: TRect);
    function NewBox(AWidth, AHeight: Integer): TStatusBarTestBox;
    function Render(APPI: Integer = 96): TBGRABitmap;
    { The first and last column of AShot, inside [AFrom, ATo), that holds text ink; -1 when
      there is none. }
    procedure InkSpan(AShot: TBGRABitmap; AFrom, ATo: Integer; out AFirst, ALast: Integer);
    procedure AssertRect(const AMsg: string; const AExpected, AActual: TRect);
  end;

  TStatusBarPanelClickTest = class(TStatusBarPanelFixture)
  published
    procedure TestAClickReportsThePanelItLandedOn;
    procedure TestAPressDraggedOntoAnotherPanelIsNotAClick;
    procedure TestOnlyTheLeftButtonClicksAPanel;
    procedure TestSimplePanelModeReportsNoPanelClicks;
    procedure TestAClickOnAChildControlIsNotAPanelClick;
    procedure TestAPressTheWindowTookForAResizeIsNotAPanelClick;
    procedure TestTheSizeGripIsNotPartOfAPanel;
    procedure TestTheMirroredSizeGripIsNotPartOfAPanel;
    procedure TestAPanelDeletedUnderThePressIsNotClicked;
    procedure TestAReleaseCountsOnlyForTheLastPress;
    procedure TestThePanelClickComesAfterOnMouseUp;
    procedure TestARealClickFiresOnClickAndThenThePanelClick;
  end;

  TStatusBarPanelRectTest = class(TStatusBarPanelFixture)
  private
    procedure CheckEveryColumn(const ATag: string);
    procedure CheckPaintCells(const ATag: string; APPI: Integer);
  published
    procedure TestPanelRectAgreesWithPanelAtPosAtEveryColumn;
    procedure TestPanelRectAgreesWithPanelAtPosAtEveryColumnMirrored;
    procedure TestPanelRectIsTheCellThePaintHandsOut;
    procedure TestPanelRectFollowsTheReadingDirection;
    procedure TestPanelRectIsEmptyForABadIndexAndInSimplePanelMode;
    procedure TestPanelTextRectIsNeverInsideOut;
  end;

  TStatusBarPanelControlTest = class(TStatusBarPanelFixture)
  private
    function LoadForm(const AText: string): TForm;
    procedure CheckLoadedForm(const ATag, AText: string);
  published
    procedure TestAssigningAControlMakesItAChildOfTheBar;
    procedure TestAssigningAControlTakesItsAlignAway;
    procedure TestTheControlSitsAtTheLeadingEdgeOfItsCellVerticallyCentred;
    procedure TestMirroredTheControlSitsAtTheRightOfItsCell;
    procedure TestTheControlFollowsItsCellWhenAPanelChangesWidth;
    procedure TestTheControlFollowsItsCellWhenTheBarIsResized;
    procedure TestTheControlFollowsItsCellWhenTheDirectionChanges;
    procedure TestTheControlFollowsItsCellWhenThePPIChanges;
    procedure TestALayoutPassPutsTheControlBack;
    procedure TestALayoutPassRepaintsTheBarOnlyWhenAControlChanged;
    procedure TestTheControlIsClampedToItsCellAndGetsItsOwnSizeBack;
    procedure TestASizeTheApplicationSetsIsItsOwnSizeFromThenOn;
    procedure TestANewControlInThePanelBringsItsOwnSize;
    procedure TestALayoutPassStartedByThePlacementKeepsTheOwnSize;
    procedure TestAnAutoSizeControlKeepsItsSize;
    procedure TestSimplePanelModeLeavesTheControlNoRoom;
    procedure TestTheDesignerKeepsTheControlsSizeInSimplePanelMode;
    procedure TestTheTextStartsAfterAVisibleControl;
    procedure TestAHiddenControlTakesNoRoom;
    procedure TestAControlWithNoWidthTakesNoRoom;
    procedure TestTheDesignerMakesRoomForAHiddenControl;
    procedure TestMirroredTheTextEndsBeforeTheControl;
    procedure TestTheGapComesFromTheTheme;
    procedure TestThePaintedTextStartsAfterTheControl;
    procedure TestAPaintAtAnotherPPIScalesTheControlsRoom;
    procedure TestTheTextKeepsItsAlignmentInTheSpaceThatIsLeft;
    procedure TestOneControlServesOnePanel;
    procedure TestAControlTakenByAnotherBarLeavesThisOne;
    procedure TestFreeingTheControlClearsThePanel;
    procedure TestAControlMovedOffTheBarLeavesItsPanel;
    procedure TestDeletingThePanelKeepsTheControl;
    procedure TestTheBarAndItsParentsCannotSitInAPanel;
    procedure TestAPanelChangeRepaintsTheBar;
    procedure TestTheBarAcceptsControlsInTheDesigner;
    procedure TestBorderWidthStillPadsTheBar;
    procedure TestAChildResolvesTheBarsThemedBackground;
    procedure TestAFormFileLoadsWithTheControlBeforeTheBar;
    procedure TestAFormFileLoadsWithTheControlAfterTheBar;
    procedure TestAFormFileLoadsWithTheControlInsideTheBar;
    procedure TestAFormFileNamingTheBarAsItsOwnControlStillLoads;
    procedure TestThePanelsControlSurvivesAStreamRoundTrip;
  end;

  TStatusBarPanelInkTest = class(TStatusBarPanelFixture)
  private
    procedure FillPanelsForText;
    procedure CheckOwnerDrawMatchesText(const ATag: string; AHandler: TTyDrawPanelEvent);
  published
    procedure TestPanelTextStyleIsTheStyleThePanelTextIsDrawnWith;
    procedure TestPanelTextStyleFollowsTheBarsState;
    procedure TestPanelFontSizeFollowsTheStyle;
    procedure TestPanelFontHeightPxFollowsThePPI;
    procedure TestDrawPanelTextMatchesATextPanelPixelForPixel;
    procedure TestDrawPanelTextMatchesATextPanelMirrored;
    procedure TestDrawPanelTextMatchesATextPanelUnderAStyleOverride;
    procedure TestAHandlerDrawingWithTheExposedInkMatchesATextPanel;
    procedure TestDrawPanelTextMatchesATextPanelWithAControlInIt;
  end;
implementation
procedure TStatusBarGeomTest.TestPanelRectsFixed;
var r: TTyRectArray;
begin
  r := TyStatusPanelRects([50, 80], 200, 0);
  AssertEquals('count', 2, Length(r));
  AssertEquals('p0.left', 0, r[0].Left);   AssertEquals('p0.right', 50, r[0].Right);
  // The LAST panel always runs to the right edge, whatever width it was given -- the
  // native bar does this, and without it a strip of bare parent shows past it.
  AssertEquals('p1.left', 50, r[1].Left);  AssertEquals('p1.right', 200, r[1].Right);
  AssertEquals('p0.top sentinel', 0, r[0].Top); AssertEquals('p0.bottom sentinel', 0, r[0].Bottom);
end;
procedure TStatusBarGeomTest.TestPanelRectsFillPanel;
var r: TTyRectArray;
begin
  // a panel with Width<=0 fills the remaining width (first such panel only)
  r := TyStatusPanelRects([50, 0, 40], 200, 0);
  AssertEquals('fill panel right', 160, r[1].Right);   // 50 + (200-50-40)=110 -> 50..160
  AssertEquals('p2 left', 160, r[2].Left);             AssertEquals('p2 right', 200, r[2].Right);
end;
procedure TStatusBarGeomTest.TestPanelRectsPadding;
var r: TTyRectArray;
begin
  r := TyStatusPanelRects([50, 80], 200, 10);
  AssertEquals('p0.left', 10, r[0].Left);   AssertEquals('p0.right', 60, r[0].Right);
  AssertEquals('p1.left', 60, r[1].Left);   AssertEquals('p1.right', 190, r[1].Right);
end;
procedure TStatusBarGeomTest.TestPanelRectsFillFirstOnly;
var r: TTyRectArray;
begin
  // two <=0 panels: only the FIRST fills; the second gets zero width
  r := TyStatusPanelRects([0, 0, 40], 200, 0);
  AssertEquals('fill panel right', 160, r[0].Right);          // 200-40
  AssertEquals('second <=0 zero width', r[1].Left, r[1].Right);
  AssertEquals('p2 left', 160, r[2].Left);                   AssertEquals('p2 right', 200, r[2].Right);
end;
procedure TStatusBarGeomTest.TestPanelRectsOverflowAndEmpty;
var r: TTyRectArray;
begin
  // fixed widths exceed total + a fill panel -> fill clamps to 0
  r := TyStatusPanelRects([150, 0, 120], 200, 0);
  AssertEquals('overflow fill collapses', r[1].Left, r[1].Right);
  // empty input -> empty result
  r := TyStatusPanelRects([], 200, 0);
  AssertEquals('empty', 0, Length(r));
end;
{ TTyStatusBarPixAccess }

procedure TTyStatusBarPixAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

{ TStatusBarPixelTest }

procedure TStatusBarPixelTest.TestBodyPixelIsDark;
{ Theme: background: #202020 (32,32,32), color: #FFFFFF, border-color: #404040.
  Control: 200x22 statusbar with one panel Text='Hi'.
  The body background #202020 should appear throughout most of the bar.
  Assert a body pixel (x=10, y=11 — well inside, away from hairlines and text)
  has all channels < 60. The top hairline (y=0) should be slightly lighter
  (#404040 = 64 each); assert its red channel >= 40.
}
var
  Ctl: TTyStyleController;
  Form: TForm;
  Bar: TTyStatusBarPixAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  PxBody, PxHairline: TBGRAPixel;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyStatusBar { background: #202020; color: #FFFFFF; border-color: #404040; }');

    Bar := TTyStatusBarPixAccess.Create(Form);
    Bar.Parent := Form;
    Bar.Controller := Ctl;
    Bar.SetBounds(0, 0, 200, 22);
    Bar.Font.PixelsPerInch := 96;
    Bar.SizeGrip := False;
    Bar.Panels.Add.Text := 'Hi';

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(200, 22);
    // Pre-fill white so background rendering is unambiguous (canvas default is undefined)
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 200, 22);
    Bar.RenderTo(Bmp.Canvas, Rect(0, 0, 200, 22), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      // Mid-body pixel at x=150, y=11 — far from text (panel width=50, text in x=8..50),
      // far from top hairline (y=0), and size grip is disabled.
      PxBody := Reread.GetPixel(150, 11);
      // Top hairline (y=0): #404040 = 64 per channel
      PxHairline := Reread.GetPixel(150, 0);
      AssertTrue(
        Format('body pixel should be dark (r=%d g=%d b=%d alpha=%d at x=150,y=11, expected < 60; hairline r=%d)',
          [PxBody.red, PxBody.green, PxBody.blue, PxBody.alpha, PxHairline.red]),
        (PxBody.red < 60) and (PxBody.green < 60) and (PxBody.blue < 60));

      // Top hairline (y=0): #404040 = 64 per channel — lighter than body (#202020 = 32)
      AssertTrue(
        Format('hairline rendered (hairline.red=%d, expected >=55)',
          [PxHairline.red]),
        PxHairline.red >= 55);

      AssertTrue(
        Format('top hairline should be lighter than body (hairline.red=%d > body.red=%d)',
          [PxHairline.red, PxBody.red]),
        PxHairline.red > PxBody.red);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

{ ---------------------------------------------------------------- the probes -- }

function TStatusBarProbe.StartWindowResize(AEdge: Integer): Boolean;
begin
  Result := WindowTakesResize and (AEdge <> 0);
end;

procedure TStatusBarProbe.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TStatusBarProbe.Press(X, Y: Integer; AButton: TMouseButton);
begin
  MouseDown(AButton, [], X, Y);
end;

procedure TStatusBarProbe.Release(X, Y: Integer; AButton: TMouseButton);
begin
  MouseUp(AButton, [], X, Y);
end;

procedure TStatusBarProbe.PressAndRelease(X, Y: Integer; AButton: TMouseButton);
begin
  Press(X, Y, AButton);
  Release(X, Y, AButton);
end;

procedure TStatusBarProbe.LayoutPass;
var
  r: TRect;
begin
  r := ClientRect;          // not inset first: AlignControls calls AdjustClientRect itself
  AlignControls(nil, r);
end;

procedure TStatusBarProbe.Designing;
begin
  SetDesigning(True, False);
end;

function TStatusBarProbe.PreferredHeight: Integer;
var
  w: Integer;
begin
  w := 0;
  Result := 0;
  CalculatePreferredSize(w, Result, True);
end;

procedure TStatusBarProbe.Invalidate;
begin
  Inc(Invalidations);
  inherited Invalidate;
end;

procedure TStatusBarTestBox.Designing;
begin
  SetDesigning(True, False);
end;

procedure TStatusBarTestBox.BoundsChanged;
begin
  inherited BoundsChanged;
  if Assigned(OnMoved) then OnMoved(Self);
end;

{ --------------------------------------------------------------- the fixture -- }

const
  { White plate, green text, red rules: text ink is whatever lost its red, so the rules and
    the top hairline never count as text. }
  CPanelCss =
    'TyStatusBar { background: #FFFFFF; color: #00C000; border-color: #FF0000; ' +
    'border-width: 1px; font-size: 12px; }';

procedure TStatusBarPanelFixture.SetUp;
begin
  inherited SetUp;
  FClicks := TStringList.Create;
  FCtl := TTyStyleController.Create(nil);
  FCtl.LoadThemeCss(CPanelCss);
  FForm := TForm.CreateNew(nil);
  FBar := TStatusBarProbe.Create(FForm);
  FBar.Parent := FForm;
  FBar.Controller := FCtl;
  FBar.Font.PixelsPerInch := 96;
  FBar.SizeGrip := False;
  FBar.SetBounds(0, 0, 300, 22);
  FForm.ClientWidth := 300;
  FForm.ClientHeight := 22;
  FBar.Panels.Add.Width := 100;
  FBar.Panels[0].Text := 'Ready';
  FBar.Panels.Add.Width := 0;
  FBar.Panels[1].Text := 'Building';
  FBar.Panels.Add.Width := 80;
  FBar.Panels[2].Text := 'Ln 12';
  FBar.OnPanelClick := @HandlePanelClick;
end;

procedure TStatusBarPanelFixture.TearDown;
begin
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FClicks);
  inherited TearDown;
end;

procedure TStatusBarPanelFixture.HandlePanelClick(Sender: TObject; APanel: TTyStatusPanel);
begin
  if Sender <> FBar then
    FClicks.Add('?')            // the sender is the bar, whoever fired it
  else
    FClicks.Add(IntToStr(APanel.Index));
end;

procedure TStatusBarPanelFixture.HandleMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  FClicks.Add('up');
end;

procedure TStatusBarPanelFixture.HandleClick(Sender: TObject);
begin
  FClicks.Add('click');
end;

procedure TStatusBarPanelFixture.HandleBoxMoved(Sender: TObject);
begin
  FBar.LayoutPass;
end;

procedure TStatusBarPanelFixture.HandleNoteRect(AStatusBar: TTyCustomStatusBar;
  APanel: TTyStatusPanel; APainter: TTyPainter; const ARect: TRect);
begin
  if Length(FDrawn) <= APanel.Index then SetLength(FDrawn, APanel.Index + 1);
  FDrawn[APanel.Index] := ARect;
end;

procedure TStatusBarPanelFixture.HandleDrawAsText(AStatusBar: TTyCustomStatusBar;
  APanel: TTyStatusPanel; APainter: TTyPainter; const ARect: TRect);
begin
  AStatusBar.DrawPanelText(APainter, AStatusBar.PanelTextRect(APanel.Index), APanel.Text,
    APanel.Alignment);
end;

procedure TStatusBarPanelFixture.HandleDrawByHand(AStatusBar: TTyCustomStatusBar;
  APanel: TTyStatusPanel; APainter: TTyPainter; const ARect: TRect);
var
  S: TTyStyleSet;
begin
  { What a handler does that draws its own text beside an icon: the bar's ink and font, read
    off the bar, into the painter's own text call. }
  S := AStatusBar.PanelTextStyle;
  APainter.DrawText(AStatusBar.PanelTextRect(APanel.Index), APanel.Text, S.FontName,
    AStatusBar.PanelFontSize, S.FontWeight, S.TextColor, APanel.Alignment, tlCenter, True);
end;

function TStatusBarPanelFixture.NewBox(AWidth, AHeight: Integer): TStatusBarTestBox;
begin
  Result := TStatusBarTestBox.Create(FForm);
  Result.SetBounds(200, 3, AWidth, AHeight);
  Result.Parent := FForm;
end;

function TStatusBarPanelFixture.Render(APPI: Integer): TBGRABitmap;
var
  host: TBitmap;
begin
  host := TBitmap.Create;
  try
    host.PixelFormat := pf32bit;
    host.SetSize(FBar.Width, FBar.Height);
    host.Canvas.Brush.Color := clWhite;
    host.Canvas.FillRect(0, 0, FBar.Width, FBar.Height);
    FBar.RenderTo(host.Canvas, Rect(0, 0, FBar.Width, FBar.Height), APPI);
    Result := TBGRABitmap.Create(host);
  finally
    host.Free;
  end;
end;

procedure TStatusBarPanelFixture.InkSpan(AShot: TBGRABitmap; AFrom, ATo: Integer;
  out AFirst, ALast: Integer);
var
  x, y: Integer;
begin
  AFirst := -1;
  ALast := -1;
  for x := AFrom to ATo - 1 do
    for y := 2 to AShot.Height - 3 do
      if AShot.GetPixel(x, y).red < 160 then
      begin
        if AFirst < 0 then AFirst := x;
        ALast := x;
        Break;
      end;
end;

procedure TStatusBarPanelFixture.AssertRect(const AMsg: string; const AExpected, AActual: TRect);
begin
  AssertEquals(AMsg,
    Format('(%d,%d)-(%d,%d)', [AExpected.Left, AExpected.Top, AExpected.Right, AExpected.Bottom]),
    Format('(%d,%d)-(%d,%d)', [AActual.Left, AActual.Top, AActual.Right, AActual.Bottom]));
end;

{ ------------------------------------------------------------ OnPanelClick -- }

procedure TStatusBarPanelClickTest.TestAClickReportsThePanelItLandedOn;
begin
  FBar.PressAndRelease(150, 11);
  AssertEquals('the fill panel', '1', FClicks.CommaText);
  FBar.PressAndRelease(20, 11);
  FBar.PressAndRelease(250, 11);
  AssertEquals('then the first and the last', '1,0,2', FClicks.CommaText);
  FBar.PressAndRelease(2, 11);     // the bar's own padding: no panel there
  AssertEquals('a click beside the panels reports nothing', '1,0,2', FClicks.CommaText);
end;

procedure TStatusBarPanelClickTest.TestAPressDraggedOntoAnotherPanelIsNotAClick;
begin
  FBar.Press(20, 11);
  FBar.Release(150, 11);
  AssertEquals('down on one panel, up on the next', '', FClicks.CommaText);
  FBar.Press(150, 11);
  FBar.Release(190, 4);
  AssertEquals('down and up on the same panel, wherever on it', '1', FClicks.CommaText);
end;

procedure TStatusBarPanelClickTest.TestOnlyTheLeftButtonClicksAPanel;
begin
  FBar.PressAndRelease(150, 11, mbRight);
  AssertEquals('the right button', '', FClicks.CommaText);
  FBar.Press(150, 11, mbLeft);
  FBar.Release(150, 11, mbRight);
  AssertEquals('a right release under a held left button', '', FClicks.CommaText);
  FBar.Release(150, 11, mbLeft);
  AssertEquals('the left button', '1', FClicks.CommaText);
end;

procedure TStatusBarPanelClickTest.TestSimplePanelModeReportsNoPanelClicks;
begin
  FBar.SimplePanel := True;
  FBar.PressAndRelease(150, 11);
  AssertEquals('there are no panels to click in SimplePanel mode', '', FClicks.CommaText);
  FBar.SimplePanel := False;
  FBar.PressAndRelease(150, 11);
  AssertEquals('and there are again without it', '1', FClicks.CommaText);
end;

procedure TStatusBarPanelClickTest.TestAClickOnAChildControlIsNotAPanelClick;
var
  box: TStatusBarTestBox;
begin
  { Disabled, because that is the child LCL does not hand the mouse to: its press arrives at
    the bar, at a point the child covers. }
  box := NewBox(16, 12);
  box.Parent := FBar;
  box.SetBounds(120, 5, 16, 12);
  box.Enabled := False;
  FBar.PressAndRelease(125, 10);
  AssertEquals('a click on the child', '', FClicks.CommaText);
  FBar.PressAndRelease(150, 10);
  AssertEquals('a click on the panel beside it', '1', FClicks.CommaText);
  FBar.Press(150, 10);
  FBar.Release(125, 10);
  AssertEquals('a press on the panel let go over the child', '1', FClicks.CommaText);
  box.Visible := False;
  FBar.PressAndRelease(125, 10);
  AssertEquals('a hidden child is not in the way', '1,1', FClicks.CommaText);
end;

procedure TStatusBarPanelClickTest.TestAPressTheWindowTookForAResizeIsNotAPanelClick;
begin
  FBar.SizeGrip := True;
  FBar.WindowTakesResize := True;
  FBar.PressAndRelease(150, 21);     // the strip along the window's bottom edge
  AssertEquals('the press resized the window', '', FClicks.CommaText);
  FBar.PressAndRelease(150, 8);
  AssertEquals('above the strip it is the panel''s', '1', FClicks.CommaText);
  FBar.WindowTakesResize := False;   // a window that cannot be resized: nothing takes the press
  FBar.PressAndRelease(150, 21);
  AssertEquals('a press the window did not take is a click', '1,1', FClicks.CommaText);
end;

procedure TStatusBarPanelClickTest.TestTheSizeGripIsNotPartOfAPanel;
begin
  { (288, 8) is on the last panel, inside the grip's corner box [282,300) x [4,22) and above
    the bottom strip. Nothing takes the press for a resize here, as on Linux and macOS. }
  FBar.SizeGrip := True;
  FBar.PressAndRelease(288, 8);
  AssertEquals('a click on the painted grip', '', FClicks.CommaText);
  FBar.PressAndRelease(230, 8);
  AssertEquals('the rest of that panel still clicks', '2', FClicks.CommaText);
  FBar.SizeGrip := False;
  FBar.PressAndRelease(288, 8);
  AssertEquals('with no grip the corner is the panel''s', '2,2', FClicks.CommaText);
end;

procedure TStatusBarPanelClickTest.TestTheMirroredSizeGripIsNotPartOfAPanel;
begin
  FBar.SizeGrip := True;
  FBar.BiDiMode := bdRightToLeft;    // the grip is bottom-left now, over the last panel
  FBar.PressAndRelease(10, 8);
  AssertEquals('a click on the mirrored grip', '', FClicks.CommaText);
  FBar.PressAndRelease(288, 8);
  AssertEquals('the right corner is the first panel, and no grip', '0', FClicks.CommaText);
  FBar.SizeGrip := False;
  FBar.PressAndRelease(10, 8);
  AssertEquals('with no grip the left corner is the last panel''s', '0,2', FClicks.CommaText);
end;

procedure TStatusBarPanelClickTest.TestAPanelDeletedUnderThePressIsNotClicked;
begin
  FBar.Press(150, 11);
  FBar.Panels.Delete(1);             // (150, 11) is on what was panel 2 now, index 1
  FBar.Release(150, 11);
  AssertEquals('the panel that was pressed is gone', '', FClicks.CommaText);
  FBar.PressAndRelease(150, 11);
  AssertEquals('a whole click on the one that took its place', '1', FClicks.CommaText);
end;

procedure TStatusBarPanelClickTest.TestAReleaseCountsOnlyForTheLastPress;
begin
  FBar.Press(150, 11);               // on the fill panel; its release never arrives
  FBar.Press(2, 11);                 // the next press is on the bar's padding
  FBar.Release(150, 11);
  AssertEquals('the press this release belongs to was on no panel', '', FClicks.CommaText);
  FBar.SizeGrip := True;
  FBar.Press(150, 11);
  FBar.WindowTakesResize := True;
  FBar.Press(150, 21);               // taken for a resize
  FBar.Release(150, 11);
  AssertEquals('nor does a press the window took leave the one before it armed', '',
    FClicks.CommaText);
  FBar.PressAndRelease(150, 11);
  AssertEquals('a whole click still counts', '1', FClicks.CommaText);
end;

procedure TStatusBarPanelClickTest.TestThePanelClickComesAfterOnMouseUp;
begin
  FBar.OnMouseUp := @HandleMouseUp;
  FBar.PressAndRelease(150, 11);
  AssertEquals('the release is over before the panel click runs', 'up,1', FClicks.CommaText);
end;

var
  ClickWidgetSet: Boolean = False;

procedure TStatusBarPanelClickTest.TestARealClickFiresOnClickAndThenThePanelClick;

  function At(X, Y: Integer): PtrInt;
  begin
    Result := PtrInt((Y shl 16) or (X and $FFFF));
  end;

begin
  { The two messages the widgetset posts for a click, through LCL's own handlers: that is
    where OnClick comes from, and it has to keep coming. The press takes the mouse capture,
    which needs a window handle, which needs the widgetset. }
  if not ClickWidgetSet then
  begin
    Forms.Application.Initialize;
    ClickWidgetSet := True;
  end;
  FBar.OnClick := @HandleClick;
  FBar.OnMouseUp := @HandleMouseUp;
  FBar.Perform(LM_LBUTTONDOWN, MK_LBUTTON, At(150, 11));
  FBar.Perform(LM_LBUTTONUP, 0, At(150, 11));
  AssertEquals('OnClick, OnMouseUp, OnPanelClick', 'click,up,1', FClicks.CommaText);
  FBar.Perform(LM_LBUTTONDOWN, MK_LBUTTON, At(150, 11));
  FBar.Perform(LM_LBUTTONUP, 0, At(20, 11));
  AssertEquals('let go over another panel: a click on the bar, on no panel',
    'click,up,1,click,up', FClicks.CommaText);
end;

{ --------------------------------------------------------------- PanelRect -- }

procedure TStatusBarPanelRectTest.CheckEveryColumn(const ATag: string);
const
  CRows: array[0..4] of Integer = (-1, 0, 11, 21, 22);
var
  x, r, i, hit, want: Integer;
  seen: array[-1..2] of Integer;
begin
  for i := -1 to 2 do seen[i] := 0;
  for r := 0 to High(CRows) do
    for x := -3 to FBar.Width + 2 do
    begin
      want := -1;
      for i := 0 to FBar.Panels.Count - 1 do
        if PtInRect(FBar.PanelRect(i), Types.Point(x, CRows[r])) then
        begin
          AssertEquals(Format('%s: one cell at most holds (%d,%d)', [ATag, x, CRows[r]]), -1, want);
          want := i;
        end;
      hit := FBar.PanelAtPos(x, CRows[r]);
      AssertEquals(Format('%s: PanelAtPos(%d,%d)', [ATag, x, CRows[r]]), want, hit);
      Inc(seen[hit]);
    end;
  for i := -1 to 2 do
    AssertTrue(Format('%s: the sweep met panel %d', [ATag, i]), seen[i] > 0);
end;

procedure TStatusBarPanelRectTest.TestPanelRectAgreesWithPanelAtPosAtEveryColumn;
begin
  CheckEveryColumn('left to right');
end;

procedure TStatusBarPanelRectTest.TestPanelRectAgreesWithPanelAtPosAtEveryColumnMirrored;
begin
  FBar.BiDiMode := bdRightToLeft;
  CheckEveryColumn('mirrored');
end;

procedure TStatusBarPanelRectTest.CheckPaintCells(const ATag: string; APPI: Integer);
var
  i: Integer;
  shot: TBGRABitmap;
begin
  SetLength(FDrawn, 0);
  shot := Render(APPI);
  shot.Free;
  AssertEquals(ATag + ': every panel was handed a cell', 3, Length(FDrawn));
  for i := 0 to 2 do
    AssertRect(Format('%s: panel %d', [ATag, i]), FDrawn[i], FBar.PanelRect(i));
end;

procedure TStatusBarPanelRectTest.TestPanelRectIsTheCellThePaintHandsOut;
var
  i: Integer;
begin
  for i := 0 to 2 do FBar.Panels[i].Style := psOwnerDraw;
  FBar.OnDrawPanel := @HandleNoteRect;
  CheckPaintCells('left to right', 96);
  FBar.BiDiMode := bdRightToLeft;
  CheckPaintCells('mirrored', 96);
  FBar.BiDiMode := bdLeftToRight;
  FBar.Font.PixelsPerInch := 144;
  FBar.SetBounds(0, 0, 450, 33);
  CheckPaintCells('at 150%', 144);
  AssertRect('and at 150% the first cell is the scaled one', Rect(9, 0, 159, 33),
    FBar.PanelRect(0));
end;

procedure TStatusBarPanelRectTest.TestPanelRectFollowsTheReadingDirection;
begin
  AssertRect('panel 0', Rect(6, 0, 106, 22), FBar.PanelRect(0));
  AssertRect('panel 1', Rect(106, 0, 214, 22), FBar.PanelRect(1));
  AssertRect('panel 2', Rect(214, 0, 294, 22), FBar.PanelRect(2));
  FBar.BiDiMode := bdRightToLeft;
  AssertRect('mirrored panel 0', Rect(194, 0, 294, 22), FBar.PanelRect(0));
  AssertRect('mirrored panel 1', Rect(86, 0, 194, 22), FBar.PanelRect(1));
  AssertRect('mirrored panel 2', Rect(6, 0, 86, 22), FBar.PanelRect(2));
end;

procedure TStatusBarPanelRectTest.TestPanelRectIsEmptyForABadIndexAndInSimplePanelMode;
begin
  AssertRect('below the first', Rect(0, 0, 0, 0), FBar.PanelRect(-1));
  AssertRect('past the last', Rect(0, 0, 0, 0), FBar.PanelRect(3));
  AssertFalse('a real panel has a cell', IsRectEmpty(FBar.PanelRect(2)));
  FBar.SimplePanel := True;
  AssertRect('no cells in SimplePanel mode', Rect(0, 0, 0, 0), FBar.PanelRect(2));
  AssertRect('and no text boxes', Rect(0, 0, 0, 0), FBar.PanelTextRect(2));
end;

procedure TStatusBarPanelRectTest.TestPanelTextRectIsNeverInsideOut;
var
  box: TStatusBarTestBox;
  r: TRect;
begin
  { A control that fills its cell leaves the text an empty box at the cell's far end, not one
    whose left edge has passed its right. }
  box := NewBox(50, 12);
  FBar.Panels[0].Width := 30;        // the cell is [6,36), its text box [8,34)
  FBar.Panels[0].Control := box;
  AssertRect('left to right', Rect(34, 0, 34, 22), FBar.PanelTextRect(0));
  FBar.BiDiMode := bdRightToLeft;    // the cell is [264,294), its text box [266,292)
  AssertRect('mirrored', Rect(266, 0, 266, 22), FBar.PanelTextRect(0));
  { And a cell with no width at all: the second of two fill panels. }
  FBar.BiDiMode := bdLeftToRight;
  FBar.Panels[2].Width := 0;
  r := FBar.PanelTextRect(2);
  AssertEquals('a collapsed cell has no text box', r.Left, r.Right);
end;

{ ------------------------------------------------------- a control in a panel -- }

procedure TStatusBarPanelControlTest.TestAssigningAControlMakesItAChildOfTheBar;
var
  box: TStatusBarTestBox;
begin
  box := NewBox(16, 12);
  AssertSame('it starts on the form', FForm, box.Parent);
  FBar.Panels[1].Control := box;
  AssertSame('the panel holds it', box, FBar.Panels[1].Control);
  AssertSame('and it is the bar''s child', FBar, box.Parent);
end;

procedure TStatusBarPanelControlTest.TestAssigningAControlTakesItsAlignAway;
var
  box: TStatusBarTestBox;
begin
  { The cell places it; an Align would have LCL place it as well, on every layout pass. }
  box := NewBox(16, 12);
  box.Align := alRight;
  FBar.Panels[1].Control := box;
  AssertTrue('alNone', box.Align = alNone);
end;

procedure TStatusBarPanelControlTest.TestTheControlSitsAtTheLeadingEdgeOfItsCellVerticallyCentred;
var
  a, b: TStatusBarTestBox;
begin
  a := NewBox(16, 12);
  b := NewBox(20, 8);
  FBar.Panels[1].Control := a;
  FBar.Panels[2].Control := b;
  AssertRect('16 x 12 in the fill panel', Bounds(108, 5, 16, 12), a.BoundsRect);
  AssertRect('20 x 8 in the last panel', Bounds(216, 7, 20, 8), b.BoundsRect);
end;

procedure TStatusBarPanelControlTest.TestMirroredTheControlSitsAtTheRightOfItsCell;
var
  box: TStatusBarTestBox;
begin
  FBar.BiDiMode := bdRightToLeft;
  box := NewBox(16, 12);
  FBar.Panels[1].Control := box;
  AssertRect('its right edge two px inside the cell [86,194)', Bounds(176, 5, 16, 12),
    box.BoundsRect);
end;

procedure TStatusBarPanelControlTest.TestTheControlFollowsItsCellWhenAPanelChangesWidth;
var
  box: TStatusBarTestBox;
begin
  box := NewBox(16, 12);
  FBar.Panels[1].Control := box;
  AssertEquals('before', 108, box.Left);
  FBar.Panels[0].Width := 60;
  AssertEquals('the cell starts 40 px earlier', 68, box.Left);
end;

procedure TStatusBarPanelControlTest.TestTheControlFollowsItsCellWhenTheBarIsResized;
var
  box: TStatusBarTestBox;
begin
  box := NewBox(16, 12);
  FBar.Panels[2].Control := box;
  AssertRect('before', Bounds(216, 5, 16, 12), box.BoundsRect);
  FBar.SetBounds(0, 0, 400, 30);
  AssertRect('the last cell moved right and the bar grew taller', Bounds(316, 9, 16, 12),
    box.BoundsRect);
end;

procedure TStatusBarPanelControlTest.TestTheControlFollowsItsCellWhenTheDirectionChanges;
var
  box: TStatusBarTestBox;
begin
  box := NewBox(16, 12);
  FBar.Panels[1].Control := box;
  AssertEquals('left to right', 108, box.Left);
  FBar.BiDiMode := bdRightToLeft;
  AssertEquals('mirrored', 176, box.Left);
end;

procedure TStatusBarPanelControlTest.TestTheControlFollowsItsCellWhenThePPIChanges;
var
  box: TStatusBarTestBox;
begin
  FBar.SetBounds(0, 0, 600, 44);
  box := NewBox(16, 12);
  FBar.Panels[1].Control := box;
  AssertRect('at 96', Bounds(108, 16, 16, 12), box.BoundsRect);
  FBar.Font.PixelsPerInch := 192;
  AssertEquals('the cells are laid out at 200% now', 212, FBar.PanelRect(1).Left);
  AssertRect('the cell and the inset doubled; the control''s size is its own',
    Bounds(216, 16, 16, 12), box.BoundsRect);
end;

procedure TStatusBarPanelControlTest.TestALayoutPassPutsTheControlBack;
var
  box: TStatusBarTestBox;
begin
  box := NewBox(16, 12);
  FBar.Panels[1].Control := box;
  box.SetBounds(150, 0, 16, 12);     // dragged in the designer, or moved by an anchor
  FBar.LayoutPass;
  AssertRect('back in its cell', Bounds(108, 5, 16, 12), box.BoundsRect);
end;

procedure TStatusBarPanelControlTest.TestALayoutPassRepaintsTheBarOnlyWhenAControlChanged;
var
  box: TStatusBarTestBox;
  n: Integer;
begin
  { Hiding a control invalidates the control's own rectangle, and the panel's text moves
    into more than that: the bar has to repaint whole. LCL answers a Visible change with a
    layout pass, which is where the bar notices. }
  box := NewBox(16, 12);
  FBar.Panels[1].Control := box;
  FBar.LayoutPass;
  n := FBar.Invalidations;
  FBar.LayoutPass;
  AssertEquals('a pass that found nothing changed repaints nothing', n, FBar.Invalidations);
  box.Visible := False;
  FBar.LayoutPass;
  AssertTrue('a pass that found the control hidden repaints the bar', FBar.Invalidations > n);
  n := FBar.Invalidations;
  box.SetBounds(box.Left, box.Top, 30, 12);
  FBar.LayoutPass;
  AssertTrue('and so does one that found it resized', FBar.Invalidations > n);
end;

procedure TStatusBarPanelControlTest.TestTheControlIsClampedToItsCellAndGetsItsOwnSizeBack;
var
  box: TStatusBarTestBox;
begin
  box := NewBox(50, 40);
  FBar.Panels[0].Width := 30;        // the cell is [6,36): 26 px between the insets
  FBar.Panels[0].Control := box;
  AssertRect('clamped both ways', Bounds(8, 0, 26, 22), box.BoundsRect);
  FBar.Panels[0].Width := 100;
  AssertRect('its own width again once there is room', Bounds(8, 0, 50, 22), box.BoundsRect);
  FBar.SetBounds(0, 0, 300, 60);
  AssertRect('and its own height', Bounds(8, 10, 50, 40), box.BoundsRect);
end;

procedure TStatusBarPanelControlTest.TestASizeTheApplicationSetsIsItsOwnSizeFromThenOn;
var
  box: TStatusBarTestBox;
begin
  box := NewBox(16, 12);
  FBar.Panels[1].Control := box;
  box.SetBounds(box.Left, box.Top, 24, 10);
  AssertEquals('the text makes room for the new width at once', 136,
    FBar.PanelTextRect(1).Left);
  FBar.LayoutPass;
  AssertRect('and the next pass centres the new height', Bounds(108, 6, 24, 10), box.BoundsRect);
  FBar.SetBounds(0, 0, 200, 22);     // the fill cell is [106,114) now
  AssertEquals('clamped', 4, box.Width);
  FBar.SetBounds(0, 0, 300, 22);
  AssertRect('back to the size the application gave it', Bounds(108, 6, 24, 10),
    box.BoundsRect);
end;

procedure TStatusBarPanelControlTest.TestANewControlInThePanelBringsItsOwnSize;
var
  first, second: TStatusBarTestBox;
begin
  { The second control comes at exactly the size the first was squeezed to: that is its own
    size, not a squeezed one, and it must not grow into the first one's when there is room. }
  first := NewBox(50, 40);
  FBar.Panels[0].Width := 30;
  FBar.Panels[0].Control := first;
  AssertRect('the first, squeezed', Bounds(8, 0, 26, 22), first.BoundsRect);
  second := NewBox(26, 22);
  FBar.Panels[0].Control := second;
  FBar.Panels[0].Width := 100;
  AssertRect('the second keeps the size it came with', Bounds(8, 0, 26, 22), second.BoundsRect);
  AssertRect('and the first is left where it was', Bounds(8, 0, 26, 22), first.BoundsRect);
end;

procedure TStatusBarPanelControlTest.TestALayoutPassStartedByThePlacementKeepsTheOwnSize;
var
  box: TStatusBarTestBox;
begin
  { In a live window, moving the control starts a layout pass, and the pass comes back to the
    bar while it is still placing. It must not take the squeezed size for the control's own. }
  box := NewBox(50, 40);
  box.OnMoved := @HandleBoxMoved;
  FBar.Panels[0].Width := 30;
  FBar.Panels[0].Control := box;
  AssertRect('squeezed', Bounds(8, 0, 26, 22), box.BoundsRect);
  FBar.Panels[0].Width := 100;
  AssertRect('and back to its own width', Bounds(8, 0, 50, 22), box.BoundsRect);
end;

procedure TStatusBarPanelControlTest.TestAnAutoSizeControlKeepsItsSize;
var
  box: TStatusBarTestBox;
begin
  { Its size is its own business: clamping it would have the two of them resize it in turn. }
  box := NewBox(50, 40);
  box.AutoSize := True;
  FBar.Panels[0].Width := 30;
  FBar.Panels[0].Control := box;
  AssertRect('placed, not resized', Bounds(8, -9, 50, 40), box.BoundsRect);
end;

procedure TStatusBarPanelControlTest.TestSimplePanelModeLeavesTheControlNoRoom;
var
  box: TStatusBarTestBox;
begin
  box := NewBox(16, 12);
  FBar.Panels[1].Control := box;
  FBar.SimplePanel := True;
  AssertEquals('no cell, no width', 0, box.Width);
  AssertEquals('and no height', 0, box.Height);
  FBar.SimplePanel := False;
  AssertRect('the panels are back, and so is the control', Bounds(108, 5, 16, 12),
    box.BoundsRect);
end;

procedure TStatusBarPanelControlTest.TestTheDesignerKeepsTheControlsSizeInSimplePanelMode;
var
  box: TStatusBarTestBox;
begin
  { What the designer shows is what the form file gets: a control saved 0 x 0 would come back
    with no size of its own. }
  FBar.Designing;
  box := NewBox(16, 12);
  FBar.Panels[1].Control := box;
  FBar.SimplePanel := True;
  AssertEquals('width', 16, box.Width);
  AssertEquals('height', 12, box.Height);
end;

procedure TStatusBarPanelControlTest.TestTheTextStartsAfterAVisibleControl;
var
  box: TStatusBarTestBox;
begin
  AssertRect('no control: the cell less its two-px insets', Rect(108, 0, 212, 22),
    FBar.PanelTextRect(1));
  box := NewBox(16, 12);
  FBar.Panels[1].Control := box;
  AssertRect('after the control and the theme''s 4 px gap', Rect(128, 0, 212, 22),
    FBar.PanelTextRect(1));
end;

procedure TStatusBarPanelControlTest.TestAHiddenControlTakesNoRoom;
var
  box: TStatusBarTestBox;
begin
  box := NewBox(16, 12);
  FBar.Panels[1].Control := box;
  box.Visible := False;
  AssertEquals('hidden', 108, FBar.PanelTextRect(1).Left);
  box.Visible := True;
  AssertEquals('shown again', 128, FBar.PanelTextRect(1).Left);
end;

procedure TStatusBarPanelControlTest.TestAControlWithNoWidthTakesNoRoom;
var
  box: TStatusBarTestBox;
begin
  box := NewBox(0, 12);
  FBar.Panels[1].Control := box;
  AssertEquals('no gap for a control that is not there to see', 108, FBar.PanelTextRect(1).Left);
  box.SetBounds(box.Left, box.Top, 1, 12);
  AssertEquals('one px of control and the gap', 113, FBar.PanelTextRect(1).Left);
end;

procedure TStatusBarPanelControlTest.TestTheDesignerMakesRoomForAHiddenControl;
var
  box: TStatusBarTestBox;
begin
  { The designer draws a control whatever its Visible says, so the text must not run under it. }
  box := NewBox(16, 12);
  box.Designing;
  FBar.Panels[1].Control := box;
  box.Visible := False;
  AssertEquals(128, FBar.PanelTextRect(1).Left);
end;

procedure TStatusBarPanelControlTest.TestMirroredTheTextEndsBeforeTheControl;
var
  box: TStatusBarTestBox;
begin
  FBar.BiDiMode := bdRightToLeft;
  box := NewBox(16, 12);
  FBar.Panels[1].Control := box;
  AssertRect('the cell is [86,194), the control [176,192)', Rect(88, 0, 172, 22),
    FBar.PanelTextRect(1));
end;

procedure TStatusBarPanelControlTest.TestTheGapComesFromTheTheme;
var
  box: TStatusBarTestBox;
begin
  box := NewBox(16, 12);
  FBar.Panels[1].Control := box;
  FCtl.StyleOverride := ':root { --statusbar-control-gap: 10px; }';
  AssertEquals('the theme''s gap', 134, FBar.PanelTextRect(1).Left);
  FBar.StyleOverride := '--statusbar-control-gap: 1px';
  AssertEquals('this bar''s own', 125, FBar.PanelTextRect(1).Left);
  FBar.StyleOverride := '';
  FBar.SetBounds(0, 0, 600, 44);
  FBar.Font.PixelsPerInch := 192;
  AssertEquals('and it scales with the bar: 212 + 4 + 16 + 20', 252, FBar.PanelTextRect(1).Left);
end;

procedure TStatusBarPanelControlTest.TestThePaintedTextStartsAfterTheControl;
var
  box: TStatusBarTestBox;
  shot: TBGRABitmap;
  bare, withBox, hidden, last: Integer;
begin
  shot := Render;
  try InkSpan(shot, 106, 214, bare, last); finally shot.Free; end;
  AssertTrue('the panel drew its text', bare >= 108);
  box := NewBox(16, 12);
  FBar.Panels[1].Control := box;
  shot := Render;
  try InkSpan(shot, 106, 214, withBox, last); finally shot.Free; end;
  AssertEquals('the text moved over by the control and the gap', bare + 20, withBox);
  box.Visible := False;
  shot := Render;
  try InkSpan(shot, 106, 214, hidden, last); finally shot.Free; end;
  AssertEquals('and back when the control is hidden', bare, hidden);
end;

procedure TStatusBarPanelControlTest.TestAPaintAtAnotherPPIScalesTheControlsRoom;
var
  box: TStatusBarTestBox;

  function FirstInkAt192: Integer;
  var
    host: TBitmap;
    shot: TBGRABitmap;
    last: Integer;
  begin
    { The bar itself stays 300 x 22 at 96 PPI; this is a preview of it at twice the size. }
    host := TBitmap.Create;
    try
      host.PixelFormat := pf32bit;
      host.SetSize(600, 44);
      host.Canvas.Brush.Color := clWhite;
      host.Canvas.FillRect(0, 0, 600, 44);
      FBar.RenderTo(host.Canvas, Rect(0, 0, 600, 44), 192);
      shot := TBGRABitmap.Create(host);
      try
        InkSpan(shot, 212, 428, Result, last);
      finally
        shot.Free;
      end;
    finally
      host.Free;
    end;
  end;

var
  bare, withBox: Integer;
begin
  bare := FirstInkAt192;
  AssertTrue('the preview drew the panel''s text', bare >= 216);
  box := NewBox(16, 12);
  FBar.Panels[1].Control := box;
  withBox := FirstInkAt192;
  AssertEquals('the control''s 16 px and the 4 px gap, both doubled', bare + 40, withBox);
end;

procedure TStatusBarPanelControlTest.TestTheTextKeepsItsAlignmentInTheSpaceThatIsLeft;
var
  box: TStatusBarTestBox;

  procedure Span(out AFirst, ALast: Integer);
  var
    shot: TBGRABitmap;
  begin
    shot := Render;
    try InkSpan(shot, 106, 214, AFirst, ALast); finally shot.Free; end;
  end;

var
  c0, c1, r0, r1, e0, e1: Integer;
begin
  box := NewBox(16, 12);
  box.Visible := False;
  FBar.Panels[1].Control := box;
  FBar.Panels[1].Alignment := taCenter;
  Span(c0, e0);
  box.Visible := True;
  Span(c1, e1);
  { Centred in [128,212) instead of [108,212): the middle moved 10 px. }
  AssertTrue(Format('centred text moved half the lost room (%d -> %d)', [c0, c1]),
    Abs((c1 - c0) - 10) <= 1);
  AssertTrue(Format('...as a whole (%d -> %d)', [e0, e1]), Abs((e1 - e0) - 10) <= 1);
  FBar.Panels[1].Alignment := taRightJustify;
  box.Visible := False;
  Span(c0, r0);
  box.Visible := True;
  Span(c1, r1);
  AssertEquals('right-aligned text ends where it did', r0, r1);
  AssertEquals('and starts where it did: it never reached the control', c0, c1);
  AssertTrue('clear of the control', c1 >= 128);
end;

procedure TStatusBarPanelControlTest.TestOneControlServesOnePanel;
var
  box: TStatusBarTestBox;
begin
  box := NewBox(16, 12);
  FBar.Panels[0].Control := box;
  AssertEquals('in panel 0', 8, box.Left);
  FBar.Panels[1].Control := box;
  AssertTrue('panel 0 let go of it', FBar.Panels[0].Control = nil);
  AssertSame('panel 1 has it', box, FBar.Panels[1].Control);
  AssertEquals('and it moved there', 108, box.Left);
end;

procedure TStatusBarPanelControlTest.TestAControlTakenByAnotherBarLeavesThisOne;
var
  box: TStatusBarTestBox;
  other: TStatusBarProbe;
begin
  box := NewBox(16, 12);
  FBar.Panels[1].Control := box;
  other := TStatusBarProbe.Create(FForm);
  other.Parent := FForm;
  other.Font.PixelsPerInch := 96;
  other.SetBounds(0, 30, 300, 22);
  other.Panels.Add.Width := 100;
  other.Panels[0].Control := box;
  AssertSame('the other bar has it', other, box.Parent);
  AssertTrue('this bar''s panel let go of it', FBar.Panels[1].Control = nil);
  AssertEquals('and its text has the cell to itself', 108, FBar.PanelTextRect(1).Left);
end;

procedure TStatusBarPanelControlTest.TestFreeingTheControlClearsThePanel;
var
  box: TStatusBarTestBox;
  shot: TBGRABitmap;
begin
  box := TStatusBarTestBox.Create(nil);   // no owner: nobody else is told it is gone
  box.SetBounds(0, 0, 16, 12);
  FBar.Panels[1].Control := box;
  AssertEquals('placed', 108, box.Left);
  box.Free;
  AssertTrue('the panel no longer points at it', FBar.Panels[1].Control = nil);
  AssertEquals('the text has the cell to itself', 108, FBar.PanelTextRect(1).Left);
  shot := Render;                         // and the paint does not go looking for it
  shot.Free;
end;

procedure TStatusBarPanelControlTest.TestAControlMovedOffTheBarLeavesItsPanel;
var
  box: TStatusBarTestBox;
begin
  box := NewBox(16, 12);
  FBar.Panels[1].Control := box;
  box.Parent := FForm;
  AssertTrue('the panel let go of it', FBar.Panels[1].Control = nil);
  box.SetBounds(40, 40, 16, 12);
  FBar.Panels[0].Width := 60;             // the cells move; the control is the form's now
  AssertRect('and the bar leaves it alone', Bounds(40, 40, 16, 12), box.BoundsRect);
end;

procedure TStatusBarPanelControlTest.TestDeletingThePanelKeepsTheControl;
var
  box: TStatusBarTestBox;
begin
  box := NewBox(16, 12);
  FBar.Panels[1].Control := box;
  FBar.Panels.Delete(1);
  AssertSame('still the bar''s child', FBar, box.Parent);
  AssertEquals('one child', 1, FBar.ControlCount);
  FBar.Panels[0].Width := 60;
  AssertRect('where the panel left it', Bounds(108, 5, 16, 12), box.BoundsRect);
  box.Free;
  AssertEquals('and it frees like any child', 0, FBar.ControlCount);
end;

procedure TStatusBarPanelControlTest.TestTheBarAndItsParentsCannotSitInAPanel;

  function Refused(AControl: TControl): Boolean;
  begin
    Result := False;
    try
      FBar.Panels[1].Control := AControl;
    except
      on E: EInvalidOperation do Result := True;
    end;
  end;

var
  box: TStatusBarTestBox;
begin
  AssertTrue('the bar itself', Refused(FBar));
  AssertTrue('the panel holds nothing', FBar.Panels[1].Control = nil);
  AssertTrue('the form the bar is on', Refused(FForm));
  AssertTrue('still nothing', FBar.Panels[1].Control = nil);
  AssertSame('and the bar is where it was', FForm, FBar.Parent);
  box := NewBox(16, 12);
  AssertFalse('any other control is welcome', Refused(box));
  AssertSame(box, FBar.Panels[1].Control);
end;

procedure TStatusBarPanelControlTest.TestAPanelChangeRepaintsTheBar;
var
  n: Integer;
begin
  n := FBar.Invalidations;
  FBar.Panels[0].Text := 'Saved';
  AssertTrue('a new text', FBar.Invalidations > n);
  n := FBar.Invalidations;
  FBar.Panels.Add;
  AssertTrue('a new panel', FBar.Invalidations > n);
end;

procedure TStatusBarPanelControlTest.TestTheBarAcceptsControlsInTheDesigner;
begin
  AssertTrue('csAcceptsControls: the designer drops a control into the bar',
    csAcceptsControls in FBar.ControlStyle);
end;

procedure TStatusBarPanelControlTest.TestBorderWidthStillPadsTheBar;
var
  plain: Integer;
begin
  { Accepting controls must not cost the bar its BorderWidth: it draws its own content, so
    the width is padding and the bar's AutoSize height grows by it, as before. }
  plain := FBar.PreferredHeight;
  FBar.BorderWidth := 10;
  AssertTrue(Format('20 px more padding than the bar has room for grows it (%d -> %d)',
    [plain, FBar.PreferredHeight]), FBar.PreferredHeight >= plain + 10);
end;

procedure TStatusBarPanelControlTest.TestAChildResolvesTheBarsThemedBackground;
var
  box: TStatusBarTestBox;
  c: TTyColor;
begin
  box := NewBox(16, 12);
  FBar.Panels[1].Control := box;
  AssertTrue(TyResolveParentBg(box, c));
  AssertEquals('the fixture''s white bar', Integer(TyRGB(255, 255, 255)), Integer(c));
  FCtl.LoadThemeCss('TyStatusBar { background: #102030; color: #FFFFFF; }');
  AssertTrue(TyResolveParentBg(box, c));
  AssertEquals('the new theme''s bar', Integer(TyRGB($10, $20, $30)), Integer(c));
end;

const
  CFormHead =
    'object F: TForm' + LineEnding +
    '  Left = 10' + LineEnding +
    '  Top = 10' + LineEnding +
    '  ClientWidth = 320' + LineEnding +
    '  ClientHeight = 120' + LineEnding;
  CFormBox =
    '  object Ind: TStatusBarTestBox' + LineEnding +
    '    Left = 200' + LineEnding +
    '    Top = 50' + LineEnding +
    '    Width = 16' + LineEnding +
    '    Height = 12' + LineEnding +
    '  end' + LineEnding;
  CFormBarHead =
    '  object Bar: TTyStatusBar' + LineEnding +
    '    Left = 0' + LineEnding +
    '    Top = 98' + LineEnding +
    '    Width = 320' + LineEnding +
    '    Height = 22' + LineEnding +
    '    Panels = <' + LineEnding +
    '      item' + LineEnding +
    '        Text = ''Ready''' + LineEnding +
    '        Width = 100' + LineEnding +
    '      end' + LineEnding +
    '      item' + LineEnding +
    '        Text = ''Building''' + LineEnding +
    '        Width = 0' + LineEnding +
    '        Control = Ind' + LineEnding +
    '      end>' + LineEnding;
  CFormBarTail = '  end' + LineEnding;
  CFormTail = 'end' + LineEnding;

function TStatusBarPanelControlTest.LoadForm(const AText: string): TForm;
var
  txt: TStringStream;
  bin: TMemoryStream;
begin
  Result := TForm.CreateNew(nil);
  txt := TStringStream.Create(AText);
  bin := TMemoryStream.Create;
  try
    try
      ObjectTextToBinary(txt, bin);
      bin.Position := 0;
      bin.ReadComponent(Result);
    except
      Result.Free;
      raise;
    end;
  finally
    bin.Free;
    txt.Free;
  end;
end;

procedure TStatusBarPanelControlTest.CheckLoadedForm(const ATag, AText: string);
var
  f: TForm;
  bar: TTyStatusBar;
  ind: TControl;
  ppi: Integer;
begin
  f := LoadForm(AText);
  try
    bar := f.FindComponent('Bar') as TTyStatusBar;
    ind := f.FindComponent('Ind') as TControl;
    AssertNotNull(ATag + ': the bar loaded', bar);
    AssertNotNull(ATag + ': the control loaded', ind);
    AssertEquals(ATag + ': both panels', 2, bar.Panels.Count);
    AssertSame(ATag + ': the panel found its control', ind, bar.Panels[1].Control);
    AssertSame(ATag + ': which is the bar''s child', bar, ind.Parent);
    { Whatever PPI the bar was born at: the placement is asked of the bar, not assumed. }
    ppi := bar.Font.PixelsPerInch;
    AssertEquals(ATag + ': in its cell once the form is loaded',
      bar.PanelRect(1).Left + MulDiv(2, ppi, 96), ind.Left);
    AssertEquals(ATag + ': vertically centred', (bar.Height - 12) div 2, ind.Top);
    AssertEquals(ATag + ': at its own width', 16, ind.Width);
    AssertEquals(ATag + ': and height', 12, ind.Height);
  finally
    f.Free;
  end;
end;

procedure TStatusBarPanelControlTest.TestAFormFileLoadsWithTheControlBeforeTheBar;
begin
  CheckLoadedForm('control first', CFormHead + CFormBox + CFormBarHead + CFormBarTail + CFormTail);
end;

procedure TStatusBarPanelControlTest.TestAFormFileLoadsWithTheControlAfterTheBar;
begin
  CheckLoadedForm('bar first', CFormHead + CFormBarHead + CFormBarTail + CFormBox + CFormTail);
end;

procedure TStatusBarPanelControlTest.TestAFormFileLoadsWithTheControlInsideTheBar;
begin
  { How the designer writes it back: the control is the bar's child by then. }
  CheckLoadedForm('control inside', CFormHead + CFormBarHead + CFormBox + CFormBarTail + CFormTail);
end;

procedure TStatusBarPanelControlTest.TestAFormFileNamingTheBarAsItsOwnControlStillLoads;
var
  f: TForm;
  bar: TTyStatusBar;
begin
  { A hand-edited form file. A setter that raises while the references are resolved stops the
    whole form from loading, so here the bad reference is dropped instead. }
  f := LoadForm(StringReplace(CFormHead + CFormBarHead + CFormBarTail + CFormTail,
    'Control = Ind', 'Control = Bar', []));
  try
    bar := f.FindComponent('Bar') as TTyStatusBar;
    AssertNotNull('the bar loaded', bar);
    AssertEquals('with both panels', 2, bar.Panels.Count);
    AssertTrue('and without the control it cannot hold', bar.Panels[1].Control = nil);
    AssertSame('still on the form', f, bar.Parent);
  finally
    f.Free;
  end;
end;

procedure TStatusBarPanelControlTest.TestThePanelsControlSurvivesAStreamRoundTrip;
var
  box: TStatusBarTestBox;
  bin: TMemoryStream;
  txt: TStringStream;
begin
  FForm.Name := 'F';
  FBar.Name := 'Bar';
  FBar.Controller := nil;            // the controller is not on the form; nothing to write
  box := NewBox(16, 12);
  box.Name := 'Ind';
  FBar.Panels.Delete(2);
  FBar.Panels[1].Control := box;
  bin := TMemoryStream.Create;
  txt := TStringStream.Create('');
  try
    bin.WriteComponent(FForm);
    bin.Position := 0;
    ObjectBinaryToText(bin, txt);
    AssertTrue('the panel names its control in the form file: ' + txt.DataString,
      Pos('Control = Ind', txt.DataString) > 0);
    AssertTrue('and the control is written inside the bar',
      Pos('object Ind: TStatusBarTestBox', txt.DataString) > Pos('object Bar: TStatusBarProbe', txt.DataString));
    CheckLoadedForm('round trip', StringReplace(txt.DataString, 'TStatusBarProbe',
      'TTyStatusBar', [rfReplaceAll]));
  finally
    txt.Free;
    bin.Free;
  end;
end;

{ ------------------------------------------------------------ the panel's ink -- }

procedure TStatusBarPanelInkTest.FillPanelsForText;
begin
  { Left, right and centred; the last one too long for its cell, so the ellipsis is in play. }
  FBar.Panels[0].Text := 'Ready';
  FBar.Panels[1].Text := 'Line 12, Col 4';
  FBar.Panels[1].Alignment := taRightJustify;
  FBar.Panels[2].Text := 'A status text much too long for its cell';
  FBar.Panels[2].Alignment := taCenter;
end;

procedure TStatusBarPanelInkTest.CheckOwnerDrawMatchesText(const ATag: string;
  AHandler: TTyDrawPanelEvent);
var
  asText, asOwner: TBGRABitmap;
  i, x, y, first, last, diff: Integer;
begin
  asOwner := nil;
  asText := Render;
  try
    for i := 0 to 2 do
    begin
      InkSpan(asText, FBar.PanelRect(i).Left, FBar.PanelRect(i).Right, first, last);
      AssertTrue(Format('%s: text panel %d drew its text', [ATag, i]), first >= 0);
    end;
    for i := 0 to 2 do FBar.Panels[i].Style := psOwnerDraw;
    FBar.OnDrawPanel := AHandler;
    asOwner := Render;
    diff := 0;
    for y := 0 to asText.Height - 1 do
      for x := 0 to asText.Width - 1 do
        if asText.GetPixel(x, y) <> asOwner.GetPixel(x, y) then Inc(diff);
    AssertEquals(ATag + ': pixels that differ between the text panels and the handler''s', 0, diff);
  finally
    asOwner.Free;
    asText.Free;
    for i := 0 to 2 do FBar.Panels[i].Style := psText;
    FBar.OnDrawPanel := nil;
  end;
end;

procedure TStatusBarPanelInkTest.TestPanelTextStyleIsTheStyleThePanelTextIsDrawnWith;

  function BlueInk: Integer;
  var
    shot: TBGRABitmap;
    x, y: Integer;
    p: TBGRAPixel;
  begin
    Result := 0;
    shot := Render;
    try
      for y := 2 to shot.Height - 3 do
        for x := 0 to shot.Width - 1 do
        begin
          p := shot.GetPixel(x, y);
          if (p.blue > 150) and (p.red < 100) and (p.green < 100) then Inc(Result);
        end;
    finally
      shot.Free;
    end;
  end;

begin
  AssertEquals('the theme''s green', Integer(TyRGB(0, $C0, 0)), Integer(FBar.PanelTextStyle.TextColor));
  AssertEquals('and nothing blue on the bar', 0, BlueInk);
  FBar.StyleOverride := 'color: #0000FF';
  AssertEquals('this bar''s own blue', Integer(TyRGB(0, 0, 255)), Integer(FBar.PanelTextStyle.TextColor));
  AssertTrue('which is what the panels are drawn in', BlueInk > 20);
end;

procedure TStatusBarPanelInkTest.TestPanelTextStyleFollowsTheBarsState;
begin
  { A disabled bar draws its panels in the theme's disabled ink, and that is the ink a
    handler is given: the style is the one the paint resolves, not the bar's at rest. }
  FCtl.LoadThemeCss(CPanelCss + ' TyStatusBar:disabled { background: #FFFFFF; ' +
    'color: #0000C0; border-color: #FF0000; border-width: 1px; font-size: 12px; }');
  FillPanelsForText;
  AssertEquals('enabled', Integer(TyRGB(0, $C0, 0)), Integer(FBar.PanelTextStyle.TextColor));
  FBar.Enabled := False;
  AssertEquals('disabled', Integer(TyRGB(0, 0, $C0)), Integer(FBar.PanelTextStyle.TextColor));
  CheckOwnerDrawMatchesText('disabled', @HandleDrawByHand);
end;

procedure TStatusBarPanelInkTest.TestPanelFontSizeFollowsTheStyle;
begin
  AssertEquals('the theme''s font-size', 12, FBar.PanelFontSize);
  FBar.StyleOverride := 'font-size: 20px';
  AssertEquals('this bar''s own', 20, FBar.PanelFontSize);
end;

procedure TStatusBarPanelInkTest.TestPanelFontHeightPxFollowsThePPI;
begin
  { A theme font-size of 12 is a 16 px font height at 96 PPI: the painter's rule, which is
    why the handler is given the height and does not have to know it. }
  AssertEquals('at 100%', 16, FBar.PanelFontHeightPx);
  AssertEquals('the painter''s own answer', TyFontHeightPx(FBar.PanelFontSize, 96),
    FBar.PanelFontHeightPx);
  FBar.Font.PixelsPerInch := 192;
  AssertEquals('at 200%', 32, FBar.PanelFontHeightPx);
  FBar.StyleOverride := 'font-size: 9px';
  AssertEquals('and it follows the size', 24, FBar.PanelFontHeightPx);
end;

procedure TStatusBarPanelInkTest.TestDrawPanelTextMatchesATextPanelPixelForPixel;
begin
  FillPanelsForText;
  CheckOwnerDrawMatchesText('left to right', @HandleDrawAsText);
end;

procedure TStatusBarPanelInkTest.TestDrawPanelTextMatchesATextPanelMirrored;
begin
  FillPanelsForText;
  FBar.BiDiMode := bdRightToLeft;
  CheckOwnerDrawMatchesText('mirrored', @HandleDrawAsText);
end;

procedure TStatusBarPanelInkTest.TestDrawPanelTextMatchesATextPanelUnderAStyleOverride;
var
  plain, styled: TBGRABitmap;
  x, y, diff: Integer;
begin
  FillPanelsForText;
  plain := Render;
  try
    FBar.StyleOverride := 'color: #0000FF; font-size: 15px; font-weight: bold';
    styled := Render;
    try
      diff := 0;
      for y := 0 to plain.Height - 1 do
        for x := 0 to plain.Width - 1 do
          if plain.GetPixel(x, y) <> styled.GetPixel(x, y) then Inc(diff);
      AssertTrue('the override changed what the panels look like', diff > 50);
    finally
      styled.Free;
    end;
  finally
    plain.Free;
  end;
  CheckOwnerDrawMatchesText('with a StyleOverride', @HandleDrawAsText);
end;

procedure TStatusBarPanelInkTest.TestAHandlerDrawingWithTheExposedInkMatchesATextPanel;
begin
  FillPanelsForText;
  FBar.StyleOverride := 'color: #0000FF; font-size: 15px; font-weight: bold';
  CheckOwnerDrawMatchesText('by hand', @HandleDrawByHand);
end;

procedure TStatusBarPanelInkTest.TestDrawPanelTextMatchesATextPanelWithAControlInIt;
begin
  FillPanelsForText;
  FBar.Panels[1].Alignment := taLeftJustify;
  FBar.Panels[1].Control := NewBox(16, 12);
  CheckOwnerDrawMatchesText('with a control in the cell', @HandleDrawAsText);
end;

initialization
  RegisterTest(TStatusBarGeomTest);
  RegisterTest(TStatusBarPixelTest);
  RegisterTest(TStatusBarPanelClickTest);
  RegisterTest(TStatusBarPanelRectTest);
  RegisterTest(TStatusBarPanelControlTest);
  RegisterTest(TStatusBarPanelInkTest);
  { A form file has to find these two by name. }
  RegisterClass(TTyStatusBar);
  RegisterClass(TStatusBarTestBox);
end.
