unit test.expanel.section;
{$mode objfpc}{$H+}

{ TTyExPanel as a section: the action area at the trailing end of its header, the keyboard on
  the header, the focus ring, the borderless variant, and what the panel does when a container
  that stacks sections owns its height (ITyExPanelHost). The stacking container itself is in
  test.accordion.

  The form has no handle, so LCL never aligns anything by itself: where a test needs the
  children placed it asks for the alignment the way LCL does (CallAlign, the client rect
  passed in whole). }

interface

uses
  Classes, SysUtils, Types, TypInfo, Graphics, Forms, Controls, LCLType, LMessages,
  fpcunit, testregistry, BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Base, tyControls.StyleModel,
  tyControls.BuiltinThemes, tyControls.Panel, tyControls.ExPanel;

type
  TSectionProbe = class(TTyExPanel)
  public
    FakeFocus: Boolean;
    Pointer: TPoint;
    function CurrentStates: TTyStateSet; override;
    function PointerPos: TPoint; override;
    procedure CallAlign;
    function AlignAnswer(AControl: TControl): TRect;
    procedure ClickAt(X, Y: Integer);
    procedure MoveTo(X, Y: Integer);
    procedure Leave;
    procedure Key(AKey: Word; AShift: TShiftState = []);
    function KeyLeft(AKey: Word; AShift: TShiftState = []): Word;
    procedure Enter;
    procedure Exit_;
    procedure Shot(ABmp: TBGRABitmap);
    function BodyTop: Integer;
  end;

  TActionsProbe = class(TTyExPanelActions)
  public
    procedure MarkDesigning(AOn: Boolean);
    procedure CallAlign;
    procedure Shot(ABmp: TBGRABitmap);
  end;

  { A focusable child, for the tab order. }
  TTabChild = class(TCustomControl)
  public
    constructor Create(AOwner: TComponent); override;
  end;

  { What a stacking container is to the panel, and a record of what the panel told it. }
  THostProbe = class(TCustomControl, ITyExPanelHost)
  public
    NToggled, NChanged, NKeys: Integer;
    LastKey: Word;
    TakeKeys: Boolean;
    procedure SectionToggled(ASection: TTyCustomExPanel);
    procedure SectionChanged(ASection: TTyCustomExPanel);
    procedure SectionKeyDown(ASection: TTyCustomExPanel; var Key: Word; Shift: TShiftState);
  end;

  TTyExPanelSectionTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FPanel: TSectionProbe;
    FExpands, FCollapses: Integer;
    FEatKeys: Boolean;
    function NewPanel(AParent: TWinControl): TSectionProbe;
    function NewChild(AParent: TWinControl; AW, AH: Integer): TTabChild;
    procedure Flat;
    procedure NoteExpand(Sender: TObject);
    procedure NoteCollapse(Sender: TObject);
    procedure EatKey(Sender: TObject; var Key: Word; Shift: TShiftState);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { the header's parts }
    procedure TestTheHeaderWithoutActionsIsTheHeaderItWas;
    procedure TestTheActionsSitAtTheTrailingEndInsideTheFrame;
    procedure TestTheCaptionGivesWayBeforeTheActions;
    procedure TestTheHeaderMirrors;
    { the action area's own row }
    procedure TestTheFlowIsPadsChildrenAndGaps;
    procedure TestTheFlowCentresAndClipsToTheHeight;
    procedure TestTheFlowKeepsTheTrailingChildrenWhenNarrow;
    procedure TestTheFlowMirrors;
    { the action area in a panel }
    procedure TestTheActionsSnapIntoTheHeader;
    procedure TestTheActionsStayInsideTheBorder;
    procedure TestTheAlignmentPassIsGivenTheSameBox;
    procedure TestAHiddenAreaTakesNoRoom;
    procedure TestTheActionsReadTheirTokens;
    procedure TestAnEmptyAreaTakesNoWidthAtRunTimeAndASlotAtDesignTime;
    procedure TestOnlyTheFirstAreaIsTheHeaders;
    procedure TestAnAreaOutsideAPanelIsHiddenAtRunTimeOnly;
    procedure TestEnsureHeaderActionsCreatesOne;
    procedure TestTheAreaTakesThePanelsController;
    procedure TestTheAreaRefusesPanelsAndAreas;
    procedure TestTheBodyStillStartsUnderTheHeader;
    procedure TestAddingAButtonMakesRoomAtOnce;
    procedure TestTheAreaLaysItsChildrenOutInARow;
    procedure TestAChildCountsAtItsMinimumWidth;
    procedure TestAnAreaWithItsOwnBackgroundDrawsNoBand;
    procedure TestAnEmptyAreaShowsItsSlotInTheDesignerOnly;
    { clicks }
    procedure TestHitTestTellsTheParts;
    procedure TestAClickOnTheActionsNeverToggles;
    { ActionsVisibility }
    procedure TestActionsVisibilityIsAlwaysByDefault;
    procedure TestHoverOnlyActionsShowWhileThePointerIsOnTheHeader;
    procedure TestHoverOnlyActionsStayWhileThePointerIsOnThem;
    procedure TestHoverOnlyActionsShowWhileTheFocusIsInside;
    procedure TestThePointerOnTheActionsLightsTheHeader;
    procedure TestTheCaptionTakesTheRoomOfHiddenActions;
    { keyboard }
    procedure TestSpaceAndEnterToggle;
    procedure TestLeftCollapsesAndRightExpands;
    procedure TestTheArrowsMirrorUnderRightToLeft;
    procedure TestTheHeaderKeysAreTaken;
    procedure TestOtherKeysAndChordsAreLeftAlone;
    procedure TestOnKeyDownComesFirstAndCanTakeTheKey;
    procedure TestADisabledPanelIgnoresTheKeys;
    procedure TestTabStopKeepsItsDefault;
    { focus ring }
    procedure TestAFocusedHeaderDrawsItsRingAroundTheBand;
    procedure TestACollapsedHeadersRingStaysInsideTheFrame;
    procedure TestTheRingGoesOnUnderTheActions;
    procedure TestAHeaderBorderIsALineAlongItsTopEdge;
    procedure TestTheDefaultThemeGivesTheHeaderAFocusRing;
    { tab order }
    procedure TestTheActionsComeFirstInTheTabOrder;
    procedure TestACollapsedPanelKeepsItsActionsInTheTabOrder;
    { the borderless variant }
    procedure TestEveryBuiltinThemeCarriesTheEmbeddedSection;
    procedure TestTheFileThemesCarryTheEmbeddedSection;
    procedure TestAnEmbeddedSectionHasNoSideInset;
    { streaming }
    procedure TestAnOldFormReadsAndWritesAsItDid;
    procedure TestActionsVisibilityStreamsWhenSet;
    procedure TestTheActionsStreamWithThePanel;
    { a container that owns the height }
    procedure TestAHostedPanelLeavesItsHeightToTheHost;
    procedure TestAHostedPanelKeepsItsWeightWhenItCollapses;
    procedure TestTheApplicationsEventsStillFireWhenHosted;
    procedure TestAWeightChangeReachesTheHost;
    procedure TestAHostedPanelStoresItsWeightExpanded;
    procedure TestKeysTheHeaderDoesNotUseGoToTheHost;
    procedure TestWithoutAHostThePanelSizesItselfAsBefore;
  end;

implementation

const
  { A theme with nothing rounded and nothing inset, so the numbers below are the header's
    own: white surface, no border, the tokens at values that are not their defaults. }
  CFlat =
    ':root { --expander-actions-pad: 3px; --expander-actions-gap: 5px; }' +
    'TyExPanel { background: #FFFFFF; color: #000000; border-width: 0px; ' +
    '  border-radius: 0px; padding: 0px; }' +
    'TyExPanelHeader { color: #000000; }';

function IsRed(const p: TBGRAPixel): Boolean;
begin
  Result := (p.red > 200) and (p.green < 60) and (p.blue < 60);
end;

function RedIn(ABmp: TBGRABitmap; const AR: TRect): Integer;
var
  x, y: Integer;
begin
  Result := 0;
  for y := AR.Top to AR.Bottom - 1 do
    for x := AR.Left to AR.Right - 1 do
      if IsRed(ABmp.GetPixel(x, y)) then Inc(Result);
end;

{ TSectionProbe }

function TSectionProbe.CurrentStates: TTyStateSet;
begin
  Result := inherited CurrentStates;
  if FakeFocus then
  begin
    Exclude(Result, tysNormal);
    Include(Result, tysFocused);
  end;
end;

function TSectionProbe.PointerPos: TPoint;
begin
  Result := Pointer;
end;

procedure TSectionProbe.CallAlign;
var
  r: TRect;
begin
  r := ClientRect;
  AlignControls(nil, r);
end;

function TSectionProbe.AlignAnswer(AControl: TControl): TRect;
var
  l, t, w, h: Integer;
  r: TRect;
  info: TAlignInfo;
begin
  { what LCL's alignment pass asks for an alCustom child, and nothing else }
  l := AControl.Left;
  t := AControl.Top;
  w := AControl.Width;
  h := AControl.Height;
  r := ClientRect;
  info := Default(TAlignInfo);
  CustomAlignPosition(AControl, l, t, w, h, r, info);
  Result := Bounds(l, t, w, h);
end;

procedure TSectionProbe.ClickAt(X, Y: Integer);
begin
  MouseDown(mbLeft, [], X, Y);
  MouseUp(mbLeft, [], X, Y);
end;

procedure TSectionProbe.MoveTo(X, Y: Integer);
begin
  Pointer := Point(X, Y);
  MouseMove([], X, Y);
end;

procedure TSectionProbe.Leave;
begin
  MouseLeave;
end;

procedure TSectionProbe.Key(AKey: Word; AShift: TShiftState);
begin
  KeyDown(AKey, AShift);
end;

function TSectionProbe.KeyLeft(AKey: Word; AShift: TShiftState): Word;
begin
  KeyDown(AKey, AShift);
  Result := AKey;
end;

procedure TSectionProbe.Enter;
begin
  DoEnter;
end;

procedure TSectionProbe.Exit_;
begin
  DoExit;
end;

procedure TSectionProbe.Shot(ABmp: TBGRABitmap);
var
  host: TBitmap;
begin
  host := TBitmap.Create;
  try
    host.PixelFormat := pf32bit;
    host.SetSize(ABmp.Width, ABmp.Height);
    host.Canvas.Brush.Color := clWhite;
    host.Canvas.FillRect(0, 0, ABmp.Width, ABmp.Height);
    RenderTo(host.Canvas, Rect(0, 0, ABmp.Width, ABmp.Height), 96);
    ABmp.Assign(host);
  finally
    host.Free;
  end;
end;

function TSectionProbe.BodyTop: Integer;
var
  r: TRect;
begin
  r := Rect(0, 0, Width, Height);
  AdjustClientRect(r);
  Result := r.Top;
end;

{ TActionsProbe }

procedure TActionsProbe.MarkDesigning(AOn: Boolean);
begin
  SetDesigning(AOn, False);
end;

procedure TActionsProbe.CallAlign;
var
  r: TRect;
begin
  r := ClientRect;
  AlignControls(nil, r);
end;

procedure TActionsProbe.Shot(ABmp: TBGRABitmap);
var
  host: TBitmap;
begin
  host := TBitmap.Create;
  try
    host.PixelFormat := pf32bit;
    host.SetSize(ABmp.Width, ABmp.Height);
    host.Canvas.Brush.Color := clWhite;
    host.Canvas.FillRect(0, 0, ABmp.Width, ABmp.Height);
    RenderTo(host.Canvas, Rect(0, 0, ABmp.Width, ABmp.Height), 96);
    ABmp.Assign(host);
  finally
    host.Free;
  end;
end;

{ TTabChild }

constructor TTabChild.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TabStop := True;
end;

{ THostProbe }

procedure THostProbe.SectionToggled(ASection: TTyCustomExPanel);
begin
  Inc(NToggled);
end;

procedure THostProbe.SectionChanged(ASection: TTyCustomExPanel);
begin
  Inc(NChanged);
end;

procedure THostProbe.SectionKeyDown(ASection: TTyCustomExPanel; var Key: Word;
  Shift: TShiftState);
begin
  Inc(NKeys);
  LastKey := Key;
  if TakeKeys then Key := 0;
end;

{ TTyExPanelSectionTest }

procedure TTyExPanelSectionTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.Font.PixelsPerInch := 96;
  FForm.SetBounds(0, 0, 400, 400);
  { its own controller: read from the process-wide theme, a test is green alone and red in
    a full run }
  FCtl := TTyStyleController.Create(FForm);
  FPanel := NewPanel(FForm);
  FExpands := 0;
  FCollapses := 0;
  FEatKeys := False;
end;

procedure TTyExPanelSectionTest.TearDown;
begin
  FreeAndNil(FForm);
end;

function TTyExPanelSectionTest.NewPanel(AParent: TWinControl): TSectionProbe;
begin
  Result := TSectionProbe.Create(FForm);
  Result.Parent := AParent;
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.Pointer := Point(-1, -1);
  Result.SetBounds(0, 0, 200, 140);
  Result.HeaderHeight := 26;
end;

function TTyExPanelSectionTest.NewChild(AParent: TWinControl; AW, AH: Integer): TTabChild;
begin
  Result := TTabChild.Create(FForm);
  Result.Parent := AParent;
  Result.SetBounds(0, 0, AW, AH);
end;

procedure TTyExPanelSectionTest.Flat;
begin
  FCtl.LoadThemeCss(CFlat);
end;

procedure TTyExPanelSectionTest.NoteExpand(Sender: TObject);
begin
  Inc(FExpands);
end;

procedure TTyExPanelSectionTest.NoteCollapse(Sender: TObject);
begin
  Inc(FCollapses);
end;

procedure TTyExPanelSectionTest.EatKey(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if FEatKeys then Key := 0;
end;

{ ---- the header's parts ---- }

procedure TTyExPanelSectionTest.TestTheHeaderWithoutActionsIsTheHeaderItWas;
var
  g: TTyExPanelHeaderGeom;
  hdr: TRect;
begin
  hdr := Rect(0, 0, 200, 26);
  { BorderWidth 2 moves the chevron in; the caption stops 9 short of the end }
  g := TyExPanelHeaderLayout(hdr, hdr, 2, 9, 0, False);
  AssertEquals('the chevron starts after the inset', 2, g.Chevron.Left);
  AssertEquals('and is as wide as the band is high', 28, g.Chevron.Right);
  AssertEquals('the chevron is the band''s height', 26, g.Chevron.Bottom - g.Chevron.Top);
  AssertEquals('the caption starts after the chevron', 28, g.Caption.Left);
  AssertEquals('and ends at the trailing pad', 191, g.Caption.Right);
  AssertEquals('no actions: nothing wide', 0, g.Actions.Right - g.Actions.Left);
end;

procedure TTyExPanelSectionTest.TestTheActionsSitAtTheTrailingEndInsideTheFrame;
var
  g: TTyExPanelHeaderGeom;
begin
  { a 3px frame: the actions live in the band's part inside it }
  g := TyExPanelHeaderLayout(Rect(0, 0, 200, 26), Rect(3, 3, 197, 26), 2, 9, 40, False);
  AssertEquals('right: inside the frame and the inset', 195, g.Actions.Right);
  AssertEquals('left: its width before that', 155, g.Actions.Left);
  AssertEquals('top: under the frame''s top line', 3, g.Actions.Top);
  AssertEquals('bottom: the band''s', 26, g.Actions.Bottom);
  AssertEquals('the caption ends where the actions start', 155, g.Caption.Right);
  AssertEquals('and still starts after the chevron', 28, g.Caption.Left);
end;

procedure TTyExPanelSectionTest.TestTheCaptionGivesWayBeforeTheActions;
var
  g: TTyExPanelHeaderGeom;
begin
  { 100 wide, a 26 chevron: 74 left. Actions of 60 leave the caption 14. }
  g := TyExPanelHeaderLayout(Rect(0, 0, 100, 26), Rect(0, 0, 100, 26), 0, 0, 60, False);
  AssertEquals('the actions keep their width', 60, g.Actions.Right - g.Actions.Left);
  AssertEquals('the caption has what is left', 14, g.Caption.Right - g.Caption.Left);
  { actions of 90 do not fit beside the chevron: the caption is gone, the chevron stays whole }
  g := TyExPanelHeaderLayout(Rect(0, 0, 100, 26), Rect(0, 0, 100, 26), 0, 0, 90, False);
  AssertEquals('the caption is empty', 0, g.Caption.Right - g.Caption.Left);
  AssertEquals('the actions stop at the chevron', 26, g.Actions.Left);
  AssertEquals('and still end at the trailing end', 100, g.Actions.Right);
end;

procedure TTyExPanelSectionTest.TestTheHeaderMirrors;
var
  g: TTyExPanelHeaderGeom;
begin
  g := TyExPanelHeaderLayout(Rect(0, 0, 200, 26), Rect(3, 3, 197, 26), 2, 9, 40, True);
  AssertEquals('the chevron is at the right end', 198, g.Chevron.Right);
  AssertEquals('the chevron keeps its width', 26, g.Chevron.Right - g.Chevron.Left);
  AssertEquals('the actions are at the left end', 5, g.Actions.Left);
  AssertEquals('the actions keep their width', 40, g.Actions.Right - g.Actions.Left);
  AssertEquals('the caption starts after the actions', 45, g.Caption.Left);
  AssertEquals('and ends before the chevron', 172, g.Caption.Right);
end;

{ ---- the action area's own row ---- }

procedure TTyExPanelSectionTest.TestTheFlowIsPadsChildrenAndGaps;
var
  f: TTyExPanelFlow;
begin
  f := TyExPanelActionsFlow([20, 30], [16, 16], 200, 26, 3, 5, False);
  AssertEquals('pad + 20 + gap + 30 + pad', 3 + 20 + 5 + 30 + 3, f.Size.cx);
  AssertEquals('two children', 2, Length(f.Rects));
  AssertEquals('the first starts after the pad', 3, f.Rects[0].Left);
  AssertEquals('the second after the first and the gap', 28, f.Rects[1].Left);
  AssertEquals('the second keeps its width', 30, f.Rects[1].Right - f.Rects[1].Left);
  f := TyExPanelActionsFlow([], [], 200, 26, 3, 5, False);
  AssertEquals('nothing in it: nothing wide', 0, f.Size.cx);
end;

procedure TTyExPanelSectionTest.TestTheFlowCentresAndClipsToTheHeight;
var
  f: TTyExPanelFlow;
begin
  f := TyExPanelActionsFlow([20, 20], [16, 40], 200, 26, 3, 5, False);
  AssertEquals('a short child is centred', 5, f.Rects[0].Top);
  AssertEquals('and keeps its height', 21, f.Rects[0].Bottom);
  { 40 in 26: seven above, seven below, cut by the area's own bounds }
  AssertEquals('a tall child is centred too, past the top', -7, f.Rects[1].Top);
  AssertEquals('and past the bottom', 33, f.Rects[1].Bottom);
end;

procedure TTyExPanelSectionTest.TestTheFlowKeepsTheTrailingChildrenWhenNarrow;
var
  f: TTyExPanelFlow;
begin
  { the row is 61 wide, the room 40: the last child still ends a pad before the end }
  f := TyExPanelActionsFlow([20, 30], [16, 16], 40, 26, 3, 5, False);
  AssertEquals('the last child ends at the trailing pad', 37, f.Rects[1].Right);
  AssertEquals('the first is pushed out at the leading end', -18, f.Rects[0].Left);
end;

procedure TTyExPanelSectionTest.TestTheFlowMirrors;
var
  f: TTyExPanelFlow;
begin
  f := TyExPanelActionsFlow([20, 30], [16, 16], 100, 26, 3, 5, True);
  AssertEquals('the first child is at the right', 97, f.Rects[0].Right);
  AssertEquals('the second to its left', 72, f.Rects[1].Right);
  AssertEquals('the second keeps its width', 42, f.Rects[1].Left);
end;

{ ---- the action area in a panel ---- }

procedure TTyExPanelSectionTest.TestTheActionsSnapIntoTheHeader;
var
  act: TTyCustomExPanelActions;
begin
  Flat;
  act := FPanel.EnsureHeaderActions;
  NewChild(act, 20, 20);
  NewChild(act, 30, 20);
  { wherever it was put: the header places it }
  act.SetBounds(50, 60, 10, 10);
  FPanel.CallAlign;
  AssertEquals('its width is its children''s row', 3 + 20 + 5 + 30 + 3, act.Width);
  AssertEquals('at the trailing end', 200, act.Left + act.Width);
  AssertEquals('at the top', 0, act.Top);
  AssertEquals('as high as the header', 26, act.Height);
  AssertTrue('the panel knows it', FPanel.HeaderActions = act);
  AssertTrue('and reports the same box', EqualRect(act.BoundsRect, FPanel.ActionsRect));
end;

procedure TTyExPanelSectionTest.TestTheActionsStayInsideTheBorder;
var
  act: TTyCustomExPanelActions;
begin
  FCtl.LoadThemeCss(
    'TyExPanel { background: #FFFFFF; color: #000000; border-color: #808080; ' +
    '  border-width: 3px; border-radius: 0px; padding: 0px; }');
  act := FPanel.EnsureHeaderActions;
  NewChild(act, 20, 20);
  FPanel.CallAlign;
  AssertEquals('right of it: the border', 197, act.Left + act.Width);
  AssertEquals('above it: the border', 3, act.Top);
  AssertEquals('down to the band''s bottom', 26, act.Top + act.Height);
  { collapsed, the band is the whole panel and the frame's bottom line runs through it }
  FPanel.Collapsed := True;
  FPanel.CallAlign;
  AssertEquals('collapsed: it stops above the bottom border', 23, act.Top + act.Height);
end;

procedure TTyExPanelSectionTest.TestTheAlignmentPassIsGivenTheSameBox;
var
  act: TTyCustomExPanelActions;
  r: TRect;
begin
  { The panel places the area itself as things change; LCL's alignment asks the panel too,
    and has to be told the same place, or the two would move it back and forth. }
  Flat;
  act := FPanel.EnsureHeaderActions;
  NewChild(act, 20, 20);
  r := FPanel.AlignAnswer(act);
  AssertEquals('left', 174, r.Left);
  AssertEquals('top: in the header, not in the body', 0, r.Top);
  AssertEquals('width', 26, r.Right - r.Left);
  AssertEquals('height', 26, r.Bottom - r.Top);
  AssertTrue('the box the panel reports', EqualRect(r, FPanel.ActionsRect));
end;

procedure TTyExPanelSectionTest.TestAHiddenAreaTakesNoRoom;
var
  act: TTyCustomExPanelActions;
begin
  Flat;
  act := FPanel.EnsureHeaderActions;
  NewChild(act, 20, 20);
  FPanel.CallAlign;
  AssertEquals('setup: the caption ends at the actions', 174, FPanel.HeaderGeom.Caption.Right);
  act.Visible := False;
  AssertFalse('hidden by the application: not showing', FPanel.ActionsShowing);
  AssertEquals('and the caption has the whole header', 200, FPanel.HeaderGeom.Caption.Right);
  AssertEquals('a click where it was is a click on the header', Ord(ephHeader),
    Ord(FPanel.HitTest(190, 13)));
  act.Visible := True;
  AssertTrue('shown again', FPanel.ActionsShowing);
  AssertEquals('the caption gives the room back', 174, FPanel.HeaderGeom.Caption.Right);
end;

procedure TTyExPanelSectionTest.TestTheActionsReadTheirTokens;
var
  act: TTyCustomExPanelActions;
  w: Integer;
begin
  Flat;
  act := FPanel.EnsureHeaderActions;
  NewChild(act, 20, 20);
  NewChild(act, 30, 20);
  FPanel.CallAlign;
  w := act.Width;
  FCtl.LoadThemeCss(
    ':root { --expander-actions-pad: 10px; --expander-actions-gap: 1px; }' +
    'TyExPanel { background: #FFFFFF; color: #000000; border-width: 0px; padding: 0px; }');
  FPanel.CallAlign;
  AssertEquals('setup: pad 3, gap 5', 61, w);
  AssertEquals('pad 10, gap 1', 10 + 20 + 1 + 30 + 10, act.Width);
end;

procedure TTyExPanelSectionTest.TestAnEmptyAreaTakesNoWidthAtRunTimeAndASlotAtDesignTime;
var
  act: TActionsProbe;
begin
  Flat;
  act := TActionsProbe.Create(FForm);
  act.Parent := FPanel;
  FPanel.CallAlign;
  AssertEquals('run time, nothing in it: no width', 0, act.Width);
  AssertEquals('and the caption runs to the end', 200, FPanel.HeaderGeom.Caption.Right);
  act.MarkDesigning(True);
  FPanel.CallAlign;
  AssertEquals('design time: a slot as wide as the header is high', 26, act.Width);
  AssertEquals('at the trailing end', 200, act.Left + act.Width);
end;

procedure TTyExPanelSectionTest.TestOnlyTheFirstAreaIsTheHeaders;
var
  a1, a2: TActionsProbe;
begin
  Flat;
  a1 := TActionsProbe.Create(FForm);
  a1.Parent := FPanel;
  NewChild(a1, 20, 20);
  a2 := TActionsProbe.Create(FForm);
  a2.Parent := FPanel;
  NewChild(a2, 20, 20);
  AssertTrue('the first is the header''s', FPanel.HeaderActions = a1);
  AssertTrue('the first shows', a1.IsControlVisible);
  AssertFalse('a second does not show at run time', a2.IsControlVisible);
  a2.MarkDesigning(True);
  AssertTrue('at design time it does, so that it can be deleted', a2.IsControlVisible);
  FPanel.CallAlign;
  AssertEquals('and sits at the top of the body', 26, a2.Top);
  AssertEquals('at its start', 0, a2.Left);
  { the first one gone, the second is the header's }
  a2.MarkDesigning(False);
  a1.Free;
  AssertTrue('the second takes over', FPanel.HeaderActions = a2);
  AssertTrue('and shows', a2.IsControlVisible);
end;

procedure TTyExPanelSectionTest.TestAnAreaOutsideAPanelIsHiddenAtRunTimeOnly;
var
  act: TActionsProbe;
begin
  act := TActionsProbe.Create(FForm);
  act.Parent := FForm;
  AssertFalse('on a form it has no header to sit in', act.IsControlVisible);
  act.MarkDesigning(True);
  AssertTrue('the designer still shows it', act.IsControlVisible);
  act.MarkDesigning(False);
  act.Parent := FPanel;
  AssertTrue('in a panel it shows', act.IsControlVisible);
end;

procedure TTyExPanelSectionTest.TestEnsureHeaderActionsCreatesOne;
var
  a, b: TTyCustomExPanelActions;
begin
  AssertTrue('none to begin with', FPanel.HeaderActions = nil);
  a := FPanel.EnsureHeaderActions;
  AssertTrue('made', a <> nil);
  AssertTrue('in the panel', a.Parent = FPanel);
  AssertTrue('owned by the form, so that it streams', a.Owner = FForm);
  b := FPanel.EnsureHeaderActions;
  AssertTrue('asked again: the same one', a = b);
  AssertEquals('its Align is the header''s business', Ord(alCustom), Ord(a.Align));
  a.Align := alClient;
  AssertEquals('and cannot be changed', Ord(alCustom), Ord(a.Align));
end;

procedure TTyExPanelSectionTest.TestTheAreaTakesThePanelsController;
var
  act: TTyCustomExPanelActions;
  other: TTyStyleController;
begin
  act := FPanel.EnsureHeaderActions;
  AssertTrue('the panel''s controller', act.Controller = FCtl);
  other := TTyStyleController.Create(FForm);
  FPanel.Controller := other;
  AssertTrue('and its next one', act.Controller = other);
end;

type
  TActionsAccess = class(TTyExPanelActions)
  public
    function Allows(AClass: TClass): Boolean;
  end;

function TActionsAccess.Allows(AClass: TClass): Boolean;
begin
  Result := ChildClassAllowed(AClass);
end;

procedure TTyExPanelSectionTest.TestTheAreaRefusesPanelsAndAreas;
var
  act: TActionsAccess;
begin
  act := TActionsAccess.Create(FForm);
  act.Parent := FPanel;
  AssertTrue('a button-like control goes in', act.Allows(TTabChild));
  AssertFalse('a collapsible panel does not', act.Allows(TTyExPanel));
  AssertFalse('nor another action area', act.Allows(TTyExPanelActions));
end;

procedure TTyExPanelSectionTest.TestTheBodyStillStartsUnderTheHeader;
var
  act: TTyCustomExPanelActions;
begin
  Flat;
  act := FPanel.EnsureHeaderActions;
  NewChild(act, 20, 40);
  FPanel.CallAlign;
  AssertEquals('a tall action does not push the body down', 26, FPanel.BodyTop);
  AssertEquals('it is cut at the header''s height', 26, act.Height);
end;

procedure TTyExPanelSectionTest.TestAddingAButtonMakesRoomAtOnce;
var
  act: TTyCustomExPanelActions;
  one: TTabChild;
begin
  Flat;
  act := FPanel.EnsureHeaderActions;
  one := NewChild(act, 20, 20);
  { no layout pass is asked for: the area tells the header itself }
  AssertEquals('one button: its row', 3 + 20 + 3, act.Width);
  AssertEquals('at the trailing end', 200, act.Left + act.Width);
  NewChild(act, 30, 20);
  AssertEquals('a second one: the row grew', 3 + 20 + 5 + 30 + 3, act.Width);
  AssertEquals('still at the trailing end', 200, act.Left + act.Width);
  one.Visible := False;
  AssertEquals('one hidden: the row shrank', 3 + 30 + 3, act.Width);
end;

procedure TTyExPanelSectionTest.TestTheAreaLaysItsChildrenOutInARow;
var
  act: TActionsProbe;
  a, b: TTabChild;
begin
  Flat;
  act := TActionsProbe.Create(FForm);
  act.Parent := FPanel;
  a := NewChild(act, 20, 16);
  b := NewChild(act, 30, 10);
  { wherever they were put, and whatever they ask for }
  a.SetBounds(70, 9, 20, 16);
  b.Align := alClient;
  FPanel.CallAlign;
  act.CallAlign;
  AssertEquals('the first after the pad', 3, a.Left);
  AssertEquals('centred on the band', 5, a.Top);
  AssertEquals('the second after the gap', 28, b.Left);
  AssertEquals('at its own width, whatever its Align says', 30, b.Width);
  AssertEquals('centred at its own height', 8, b.Top);
  AssertEquals('which it keeps', 10, b.Height);
  FPanel.BiDiMode := bdRightToLeft;
  FPanel.CallAlign;
  act.CallAlign;
  AssertEquals('right to left the area is at the left end', 0, act.Left);
  AssertEquals('and its first child at its right', act.Width - 3, a.Left + a.Width);
  AssertEquals('the second to the left of it', act.Width - 28, b.Left + b.Width);
end;

procedure TTyExPanelSectionTest.TestAChildCountsAtItsMinimumWidth;
var
  act: TActionsProbe;
  a, b: TTabChild;
begin
  Flat;
  act := TActionsProbe.Create(FForm);
  act.Parent := FPanel;
  a := NewChild(act, 20, 16);
  b := NewChild(act, 30, 16);
  FPanel.CallAlign;
  AssertEquals('setup: the row of 20 and 30', 61, act.Width);
  { a button sets its minimum from its caption; its Width follows only when it is next placed }
  a.Constraints.MinWidth := 44;
  FPanel.CallAlign;
  act.CallAlign;
  AssertEquals('the row is measured with the minimum', 3 + 44 + 5 + 30 + 3, act.Width);
  AssertEquals('and the next child starts after it', 3 + 44 + 5, b.Left);
end;

procedure TTyExPanelSectionTest.TestAnAreaWithItsOwnBackgroundDrawsNoBand;
var
  act: TActionsProbe;
  part: TBGRABitmap;
begin
  { the header has a red top line; an area with no background carries it on, one with a
    background of its own is not a piece of the header }
  FCtl.LoadThemeCss(
    'TyExPanel { background: #FFFFFF; color: #000000; border-width: 0px; padding: 0px; }' +
    'TyExPanelHeader { color: #000000; border-color: #FF0000; border-width: 2px; }');
  act := TActionsProbe.Create(FForm);
  act.Parent := FPanel;
  NewChild(act, 30, 10);
  FPanel.CallAlign;
  part := TBGRABitmap.Create(act.Width, act.Height);
  try
    act.Shot(part);
    AssertTrue('setup: without a background the line is carried on',
      RedIn(part, Rect(0, 0, act.Width, 2)) > 0);
    FCtl.LoadThemeCss(
      'TyExPanel { background: #FFFFFF; color: #000000; border-width: 0px; padding: 0px; }' +
      'TyExPanelHeader { color: #000000; border-color: #FF0000; border-width: 2px; }' +
      'TyExPanelActions { background: #00FF00; }');
    act.Shot(part);
    AssertEquals('with its own background: no line', 0, RedIn(part, Rect(0, 0, act.Width, 26)));
    AssertTrue('its own background instead', part.GetPixel(5, 1).green > 200);
  finally
    part.Free;
  end;
end;

procedure TTyExPanelSectionTest.TestAnEmptyAreaShowsItsSlotInTheDesignerOnly;
var
  act: TActionsProbe;
  part: TBGRABitmap;
begin
  FCtl.LoadThemeCss(
    ':root { --border: #FF0000; }' +
    'TyExPanel { background: #FFFFFF; color: #000000; border-width: 0px; padding: 0px; }');
  act := TActionsProbe.Create(FForm);
  act.Parent := FPanel;
  act.MarkDesigning(True);
  FPanel.CallAlign;
  AssertEquals('setup: the slot', 26, act.Width);
  part := TBGRABitmap.Create(26, 26);
  try
    act.Shot(part);
    AssertTrue('design time, empty: the slot is outlined',
      RedIn(part, Rect(0, 0, 26, 1)) >= 20);
    NewChild(act, 20, 20);
    act.Shot(part);
    AssertEquals('with a child in it: no outline', 0, RedIn(part, Rect(0, 0, 26, 26)));
    act.Controls[0].Free;
    act.MarkDesigning(False);
    act.Shot(part);
    AssertEquals('run time: no outline', 0, RedIn(part, Rect(0, 0, 26, 26)));
  finally
    part.Free;
  end;
end;

{ ---- clicks ---- }

procedure TTyExPanelSectionTest.TestHitTestTellsTheParts;
var
  act: TTyCustomExPanelActions;
begin
  Flat;
  act := FPanel.EnsureHeaderActions;
  NewChild(act, 20, 20);
  FPanel.CallAlign;
  AssertEquals('the caption', Ord(ephHeader), Ord(FPanel.HitTest(60, 13)));
  AssertEquals('the chevron', Ord(ephHeader), Ord(FPanel.HitTest(10, 13)));
  AssertEquals('the actions', Ord(ephActions), Ord(FPanel.HitTest(act.Left + 2, 13)));
  AssertEquals('the last column before them', Ord(ephHeader),
    Ord(FPanel.HitTest(act.Left - 1, 13)));
  AssertEquals('the body', Ord(ephBody), Ord(FPanel.HitTest(60, 80)));
  AssertEquals('outside', Ord(ephNone), Ord(FPanel.HitTest(60, 200)));
end;

procedure TTyExPanelSectionTest.TestAClickOnTheActionsNeverToggles;
var
  act: TTyCustomExPanelActions;
begin
  Flat;
  act := FPanel.EnsureHeaderActions;
  NewChild(act, 20, 20);
  FPanel.CallAlign;
  FPanel.ClickAt(act.Left + 2, 13);
  AssertFalse('a click on the actions leaves it open', FPanel.Collapsed);
  FPanel.ClickAt(act.Left - 1, 13);
  AssertTrue('a click just before them closes it', FPanel.Collapsed);
  FPanel.CallAlign;
  FPanel.ClickAt(act.Left + 2, 13);
  AssertTrue('and a click on the actions leaves it closed', FPanel.Collapsed);
  FPanel.ClickAt(60, 13);
  AssertFalse('the caption opens it again', FPanel.Collapsed);
end;

{ ---- ActionsVisibility ---- }

procedure TTyExPanelSectionTest.TestActionsVisibilityIsAlwaysByDefault;
var
  act: TTyCustomExPanelActions;
begin
  Flat;
  AssertEquals('default', Ord(eavAlways), Ord(FPanel.ActionsVisibility));
  act := FPanel.EnsureHeaderActions;
  NewChild(act, 20, 20);
  FPanel.CallAlign;
  AssertTrue('showing with the pointer nowhere near', FPanel.ActionsShowing);
  AssertEquals('at their width', 26, act.Width);
end;

procedure TTyExPanelSectionTest.TestHoverOnlyActionsShowWhileThePointerIsOnTheHeader;
var
  act: TTyCustomExPanelActions;
begin
  Flat;
  act := FPanel.EnsureHeaderActions;
  NewChild(act, 20, 20);
  FPanel.ActionsVisibility := eavHoverOrFocus;
  FPanel.CallAlign;
  AssertFalse('pointer away: not showing', FPanel.ActionsShowing);
  AssertEquals('and no width', 0, act.Width);
  FPanel.MoveTo(60, 13);
  AssertTrue('pointer on the header: showing', FPanel.ActionsShowing);
  AssertEquals('placed at their width without waiting for a layout', 26, act.Width);
  AssertEquals('at the trailing end', 200, act.Left + act.Width);
  FPanel.MoveTo(60, 80);
  AssertFalse('pointer on the body: gone', FPanel.ActionsShowing);
  AssertEquals('no width again', 0, act.Width);
  FPanel.MoveTo(60, 13);
  FPanel.Pointer := Point(-1, -1);
  FPanel.Leave;
  AssertFalse('pointer out of the panel: gone', FPanel.ActionsShowing);
end;

procedure TTyExPanelSectionTest.TestHoverOnlyActionsStayWhileThePointerIsOnThem;
var
  act: TTyCustomExPanelActions;
begin
  Flat;
  act := FPanel.EnsureHeaderActions;
  NewChild(act, 20, 20);
  FPanel.ActionsVisibility := eavHoverOrFocus;
  FPanel.MoveTo(60, 13);
  { onto a button: the panel is told the pointer left it, and the pointer is still in the band }
  FPanel.Pointer := Point(act.Left + 5, 13);
  FPanel.Leave;
  AssertTrue('the pointer is on the actions: they stay', FPanel.ActionsShowing);
  AssertEquals('at their width', 26, act.Width);
  { off the button and out of the panel: the button's leave comes up to the panel }
  FPanel.Perform(CM_MOUSEENTER, 0, LParam(act));
  FPanel.Pointer := Point(act.Left + 5, -4);
  FPanel.Perform(CM_MOUSELEAVE, 0, LParam(act));
  AssertFalse('the pointer left through the actions: gone', FPanel.ActionsShowing);
end;

procedure TTyExPanelSectionTest.TestHoverOnlyActionsShowWhileTheFocusIsInside;
var
  act: TTyCustomExPanelActions;
begin
  Flat;
  act := FPanel.EnsureHeaderActions;
  NewChild(act, 20, 20);
  FPanel.ActionsVisibility := eavHoverOrFocus;
  FPanel.CallAlign;
  AssertEquals('setup: hidden', 0, act.Width);
  FPanel.Enter;
  AssertTrue('the focus came into the section: showing', FPanel.ActionsShowing);
  AssertEquals('at their width', 26, act.Width);
  FPanel.Exit_;
  AssertFalse('the focus left: gone', FPanel.ActionsShowing);
  AssertEquals('no width', 0, act.Width);
end;

procedure TTyExPanelSectionTest.TestThePointerOnTheActionsLightsTheHeader;
var
  act: TTyCustomExPanelActions;
  body: TTabChild;
begin
  Flat;
  act := FPanel.EnsureHeaderActions;
  NewChild(act, 20, 20);
  FPanel.CallAlign;
  AssertFalse('setup: not hot', FPanel.HeaderHot);
  { straight onto the actions from above: only the child's enter reaches the panel }
  FPanel.Pointer := Point(act.Left + 5, 13);
  FPanel.Perform(CM_MOUSEENTER, 0, LParam(act));
  AssertTrue('the actions are part of the header', FPanel.HeaderHot);
  FPanel.Pointer := Point(act.Left + 5, -4);
  FPanel.Perform(CM_MOUSELEAVE, 0, LParam(act));
  AssertFalse('and off them it is not hot', FPanel.HeaderHot);
  { a control of the body is not the header: its enter, passed up the same way, lights nothing }
  body := NewChild(FPanel, 50, 20);
  FPanel.Pointer := Point(20, 80);
  FPanel.Perform(CM_MOUSEENTER, 0, LParam(body));
  AssertFalse('the pointer on a body control does not light the header', FPanel.HeaderHot);
  FPanel.Perform(CM_MOUSELEAVE, 0, LParam(body));
  { a move the panel sees itself over that stretch (no child window there) counts the same }
  FPanel.MoveTo(act.Left + 5, 13);
  AssertTrue('the stretch of the actions is header', FPanel.HeaderHot);
end;

procedure TTyExPanelSectionTest.TestTheCaptionTakesTheRoomOfHiddenActions;
var
  act: TTyCustomExPanelActions;
begin
  Flat;
  act := FPanel.EnsureHeaderActions;
  NewChild(act, 20, 20);
  FPanel.CallAlign;
  AssertEquals('showing: the caption ends at the actions', 174, FPanel.HeaderGeom.Caption.Right);
  FPanel.ActionsVisibility := eavHoverOrFocus;
  AssertEquals('hidden: it runs to the end', 200, FPanel.HeaderGeom.Caption.Right);
  AssertEquals('changing the property re-placed them', 0, act.Width);
  FPanel.ActionsVisibility := eavAlways;
  AssertEquals('and back', 26, act.Width);
end;

{ ---- keyboard ---- }

procedure TTyExPanelSectionTest.TestSpaceAndEnterToggle;
begin
  FPanel.Key(VK_SPACE);
  AssertTrue('Space closes', FPanel.Collapsed);
  FPanel.Key(VK_SPACE);
  AssertFalse('Space opens', FPanel.Collapsed);
  FPanel.Key(VK_RETURN);
  AssertTrue('Enter closes', FPanel.Collapsed);
  FPanel.Key(VK_RETURN);
  AssertFalse('Enter opens', FPanel.Collapsed);
end;

procedure TTyExPanelSectionTest.TestLeftCollapsesAndRightExpands;
begin
  FPanel.Key(VK_RIGHT);
  AssertFalse('Right on an open panel leaves it open', FPanel.Collapsed);
  FPanel.Key(VK_LEFT);
  AssertTrue('Left closes', FPanel.Collapsed);
  FPanel.Key(VK_LEFT);
  AssertTrue('Left on a closed panel leaves it closed', FPanel.Collapsed);
  FPanel.Key(VK_RIGHT);
  AssertFalse('Right opens', FPanel.Collapsed);
end;

procedure TTyExPanelSectionTest.TestTheArrowsMirrorUnderRightToLeft;
begin
  FPanel.BiDiMode := bdRightToLeft;
  FPanel.Key(VK_LEFT);
  AssertFalse('Left on an open panel leaves it open', FPanel.Collapsed);
  FPanel.Key(VK_RIGHT);
  AssertTrue('Right closes', FPanel.Collapsed);
  FPanel.Key(VK_RIGHT);
  AssertTrue('Right on a closed panel leaves it closed', FPanel.Collapsed);
  FPanel.Key(VK_LEFT);
  AssertFalse('Left opens', FPanel.Collapsed);
end;

procedure TTyExPanelSectionTest.TestTheHeaderKeysAreTaken;
begin
  AssertEquals('Space', 0, FPanel.KeyLeft(VK_SPACE));
  AssertEquals('Enter', 0, FPanel.KeyLeft(VK_RETURN));
  AssertEquals('Left', 0, FPanel.KeyLeft(VK_LEFT));
  { taken even when there is nothing to do: left to LCL, an arrow moves the focus to a sibling }
  AssertEquals('Left again', 0, FPanel.KeyLeft(VK_LEFT));
  AssertEquals('Right', 0, FPanel.KeyLeft(VK_RIGHT));
end;

procedure TTyExPanelSectionTest.TestOtherKeysAndChordsAreLeftAlone;
begin
  AssertEquals('a letter is not the header''s', Ord('A'), FPanel.KeyLeft(Ord('A')));
  AssertEquals('Up is not, outside a stack', VK_UP, FPanel.KeyLeft(VK_UP));
  AssertEquals('Ctrl+Space is a chord', VK_SPACE, FPanel.KeyLeft(VK_SPACE, [ssCtrl]));
  AssertEquals('Alt+Left is a chord', VK_LEFT, FPanel.KeyLeft(VK_LEFT, [ssAlt]));
  AssertEquals('Shift+Enter is a chord', VK_RETURN, FPanel.KeyLeft(VK_RETURN, [ssShift]));
  AssertEquals('Meta+Space is a chord', VK_SPACE, FPanel.KeyLeft(VK_SPACE, [ssMeta]));
  AssertFalse('and none of them toggled', FPanel.Collapsed);
end;

procedure TTyExPanelSectionTest.TestOnKeyDownComesFirstAndCanTakeTheKey;
begin
  FPanel.OnKeyDown := @EatKey;
  FEatKeys := True;
  FPanel.Key(VK_SPACE);
  AssertFalse('the handler took Space: no toggle', FPanel.Collapsed);
  FEatKeys := False;
  FPanel.Key(VK_SPACE);
  AssertTrue('the handler let it through: toggled', FPanel.Collapsed);
end;

procedure TTyExPanelSectionTest.TestADisabledPanelIgnoresTheKeys;
begin
  FPanel.Enabled := False;
  FPanel.Key(VK_SPACE);
  FPanel.Key(VK_LEFT);
  AssertFalse('disabled: the keys do nothing', FPanel.Collapsed);
  FPanel.Enabled := True;
  FPanel.Key(VK_LEFT);
  AssertTrue('enabled again: they do', FPanel.Collapsed);
end;

procedure TTyExPanelSectionTest.TestTabStopKeepsItsDefault;
var
  pi: PPropInfo;
begin
  AssertFalse('a panel is not a tab stop until the form says so', FPanel.TabStop);
  pi := GetPropInfo(TTyExPanel, 'TabStop');
  AssertTrue('published', pi <> nil);
  AssertEquals('and the declared default is the constructed value', Ord(FPanel.TabStop),
    pi^.Default);
end;

{ ---- focus ring ---- }

const
  CRing =
    'TyExPanel { background: #FFFFFF; color: #000000; border-width: 0px; ' +
    '  border-radius: 0px; padding: 0px; }' +
    'TyExPanelHeader { color: #000000; }' +
    'TyExPanelHeader:focus { outline: 2px #FF0000; }';

procedure TTyExPanelSectionTest.TestAFocusedHeaderDrawsItsRingAroundTheBand;
var
  shot: TBGRABitmap;
begin
  FCtl.LoadThemeCss(CRing);
  shot := TBGRABitmap.Create(200, 140);
  try
    FPanel.Shot(shot);
    AssertEquals('not focused: no ring', 0, RedIn(shot, Rect(0, 0, 200, 140)));
    FPanel.FakeFocus := True;
    FPanel.Shot(shot);
    AssertEquals('top edge of the band', 200 * 2, RedIn(shot, Rect(0, 0, 200, 2)));
    AssertEquals('bottom edge of the band', 200 * 2, RedIn(shot, Rect(0, 24, 200, 26)));
    AssertEquals('left edge of the band', 2 * 22, RedIn(shot, Rect(0, 2, 2, 24)));
    AssertEquals('right edge of the band', 2 * 22, RedIn(shot, Rect(198, 2, 200, 24)));
    AssertEquals('nothing inside it', 0, RedIn(shot, Rect(2, 2, 198, 24)));
    AssertEquals('and nothing round the body: the ring is the header''s', 0,
      RedIn(shot, Rect(0, 26, 200, 140)));
  finally
    shot.Free;
  end;
end;

procedure TTyExPanelSectionTest.TestACollapsedHeadersRingStaysInsideTheFrame;
var
  shot: TBGRABitmap;
begin
  { a 3px grey frame; collapsed, the band is the whole panel and the frame's bottom line
    runs through it }
  FCtl.LoadThemeCss(
    'TyExPanel { background: #FFFFFF; color: #000000; border-color: #808080; ' +
    '  border-width: 3px; border-radius: 0px; padding: 0px; }' +
    'TyExPanelHeader { color: #000000; }' +
    'TyExPanelHeader:focus { outline: 2px #FF0000; }');
  FPanel.FakeFocus := True;
  shot := TBGRABitmap.Create(200, 140);
  try
    FPanel.Shot(shot);
    AssertEquals('open: the ring''s top is under the frame''s', 194 * 2,
      RedIn(shot, Rect(3, 3, 197, 5)));
    AssertEquals('open: its bottom is the band''s', 194 * 2, RedIn(shot, Rect(3, 24, 197, 26)));
    AssertEquals('open: nothing on the frame', 0, RedIn(shot, Rect(0, 0, 200, 3)));
  finally
    shot.Free;
  end;
  FPanel.Collapsed := True;
  AssertEquals('setup: collapsed to the header', 26, FPanel.Height);
  shot := TBGRABitmap.Create(200, 26);
  try
    FPanel.Shot(shot);
    AssertEquals('collapsed: its bottom is above the frame''s bottom line', 194 * 2,
      RedIn(shot, Rect(3, 21, 197, 23)));
    AssertEquals('collapsed: nothing on the frame''s bottom line', 0,
      RedIn(shot, Rect(0, 23, 200, 26)));
  finally
    shot.Free;
  end;
end;

procedure TTyExPanelSectionTest.TestTheRingGoesOnUnderTheActions;
var
  act: TActionsProbe;
  shot: TBGRABitmap;
begin
  FCtl.LoadThemeCss(CRing);
  act := TActionsProbe.Create(FForm);
  act.Parent := FPanel;
  NewChild(act, 30, 10);
  FPanel.CallAlign;
  AssertEquals('setup: the area is 38 wide', 38, act.Width);
  shot := TBGRABitmap.Create(act.Width, act.Height);
  try
    act.Shot(shot);
    AssertEquals('not focused: the area draws no ring', 0, RedIn(shot, Rect(0, 0, 38, 26)));
    FPanel.FakeFocus := True;
    act.Shot(shot);
    AssertEquals('its stretch of the top edge', 38 * 2, RedIn(shot, Rect(0, 0, 38, 2)));
    AssertEquals('its stretch of the bottom edge', 38 * 2, RedIn(shot, Rect(0, 24, 38, 26)));
    AssertEquals('the band''s right edge, which is the area''s', 2 * 22,
      RedIn(shot, Rect(36, 2, 38, 24)));
    AssertEquals('and no left edge of its own', 0, RedIn(shot, Rect(0, 2, 36, 24)));
  finally
    shot.Free;
  end;
end;

procedure TTyExPanelSectionTest.TestAHeaderBorderIsALineAlongItsTopEdge;
var
  act: TActionsProbe;
  shot, part: TBGRABitmap;
begin
  FCtl.LoadThemeCss(
    'TyExPanel { background: #FFFFFF; color: #000000; border-width: 0px; ' +
    '  border-radius: 0px; padding: 0px; }' +
    'TyExPanelHeader { color: #000000; border-color: #FF0000; border-width: 2px; }');
  act := TActionsProbe.Create(FForm);
  act.Parent := FPanel;
  NewChild(act, 30, 10);
  FPanel.CallAlign;
  shot := TBGRABitmap.Create(200, 140);
  part := TBGRABitmap.Create(act.Width, act.Height);
  try
    FPanel.Shot(shot);
    AssertEquals('two rows of it across the top of the band', 200 * 2,
      RedIn(shot, Rect(0, 0, 200, 2)));
    AssertEquals('and nowhere else', 0, RedIn(shot, Rect(0, 2, 200, 140)));
    act.Shot(part);
    AssertEquals('the action area carries its stretch of the line', act.Width * 2,
      RedIn(part, Rect(0, 0, act.Width, 2)));
    AssertEquals('and nothing more', 0, RedIn(part, Rect(0, 2, act.Width, act.Height)));
    { inside a frame the line starts under the frame's own }
    FCtl.LoadThemeCss(
      'TyExPanel { background: #FFFFFF; color: #000000; border-color: #808080; ' +
      '  border-width: 3px; border-radius: 0px; padding: 0px; }' +
      'TyExPanelHeader { color: #000000; border-color: #FF0000; border-width: 2px; }');
    FPanel.Shot(shot);
    AssertEquals('framed: under the frame''s top line, between its sides', 194 * 2,
      RedIn(shot, Rect(3, 3, 197, 5)));
    AssertEquals('framed: not on the frame', 0, RedIn(shot, Rect(0, 0, 200, 3)));
  finally
    part.Free;
    shot.Free;
  end;
end;

procedure TTyExPanelSectionTest.TestTheDefaultThemeGivesTheHeaderAFocusRing;
var
  m: TTyStyleModel;
  plain, focused: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    plain := m.ResolveStyle('TyExPanelHeader', '', []);
    focused := m.ResolveStyle('TyExPanelHeader', '', [tysFocused]);
    AssertFalse('no ring at rest', (tpOutline in plain.Present) and (plain.OutlineWidth > 0));
    AssertTrue('a ring when focused', (tpOutline in focused.Present) and (focused.OutlineWidth > 0));
    { and the section look: a plain header has no line, an embedded one is divided by it }
    AssertFalse('a plain header has no line', TyBorderVisible(plain));
    AssertTrue('an embedded header has one',
      TyBorderVisible(m.ResolveStyle('TyExPanelHeader', 'embedded', [])));
  finally
    m.Free;
  end;
end;

{ ---- tab order ---- }

procedure TTyExPanelSectionTest.TestTheActionsComeFirstInTheTabOrder;
var
  act: TTyCustomExPanelActions;
  body, btn: TTabChild;
  list: TFPList;
begin
  { the body's control is made first, so the tab list has it first }
  body := NewChild(FPanel, 50, 20);
  act := FPanel.EnsureHeaderActions;
  btn := NewChild(act, 20, 20);
  list := TFPList.Create;
  try
    FPanel.GetTabOrderList(list);
    AssertEquals('both', 2, list.Count);
    AssertTrue('the header''s action first', list[0] = Pointer(btn));
    AssertTrue('the body after it', list[1] = Pointer(body));
  finally
    list.Free;
  end;
end;

procedure TTyExPanelSectionTest.TestACollapsedPanelKeepsItsActionsInTheTabOrder;
var
  act: TTyCustomExPanelActions;
  btn: TTabChild;
  list: TFPList;
begin
  NewChild(FPanel, 50, 20);
  act := FPanel.EnsureHeaderActions;
  btn := NewChild(act, 20, 20);
  FPanel.Collapsed := True;
  list := TFPList.Create;
  try
    FPanel.GetTabOrderList(list);
    AssertEquals('the body is out, the action is not', 1, list.Count);
    AssertTrue('the action', list[0] = Pointer(btn));
  finally
    list.Free;
  end;
end;

{ ---- the borderless variant ---- }

procedure TTyExPanelSectionTest.TestEveryBuiltinThemeCarriesTheEmbeddedSection;
{ A variant does not survive a skin's own rule for the type key (see
  TestEveryBuiltinCarriesTheEmbeddedEditVariant in test.builtinthemes): a skin that restyles
  TyExPanel must say .embedded again. So: under every built-in theme, in both modes, an
  embedded section has no frame, and its header is a band of its own. }
var
  n: TStringArray;
  i, md: Integer;
  m: TTyStyleModel;
  emb, hdr, plainHdr: TTyStyleSet;
  bad: string;
begin
  n := TyBuiltinThemeNames;
  bad := '';
  for i := 0 to High(n) do
  begin
    m := TTyStyleModel.Create;
    try
      m.LoadFromCss(TyBuiltinThemeCss(n[i]));
      for md := 0 to 1 do
      begin
        if md = 0 then m.SetMode('light') else m.SetMode('dark');
        emb := m.ResolveStyle('TyExPanel', 'embedded', []);
        hdr := m.ResolveStyle('TyExPanelHeader', 'embedded', []);
        plainHdr := m.ResolveStyle('TyExPanelHeader', '', []);
        if TyBorderVisible(emb) then
          bad := bad + Format(' %s/%d:border', [n[i], md]);
        if TyEffectiveCorners(emb).TL <> 0 then
          bad := bad + Format(' %s/%d:radius', [n[i], md]);
        if (tpShadow in emb.Present) and (TyAlphaOf(emb.ShadowColor) > 0) then
          bad := bad + Format(' %s/%d:shadow', [n[i], md]);
        if not (tpBackground in emb.Present) then
          bad := bad + Format(' %s/%d:no-surface', [n[i], md]);
        if not (tpBackground in hdr.Present) then
          bad := bad + Format(' %s/%d:no-band', [n[i], md]);
        if TyBorderVisible(plainHdr) then
          bad := bad + Format(' %s/%d:plain-header-lined', [n[i], md]);
        if tpBackground in plainHdr.Present then
          bad := bad + Format(' %s/%d:plain-header-tinted', [n[i], md]);
      end;
    finally
      m.Free;
    end;
  end;
  AssertEquals('themes where an embedded section is not a frameless band:' + bad, '', bad);
end;

procedure TTyExPanelSectionTest.TestTheFileThemesCarryTheEmbeddedSection;
{ dark.tycss and green.tycss are not compiled in, and each writes a TyExPanel rule. }
const
  Names: array[0..1] of string = ('dark.tycss', 'green.tycss');
var
  i: Integer;
  m: TTyStyleModel;
  plain, emb: TTyStyleSet;
  path: string;
begin
  for i := 0 to High(Names) do
  begin
    path := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes' + PathDelim + Names[i];
    AssertTrue('the theme file is there: ' + path, FileExists(path));
    m := TTyStyleModel.Create;
    try
      m.LoadFromFile(path);
      plain := m.ResolveStyle('TyExPanel', '', []);
      emb := m.ResolveStyle('TyExPanel', 'embedded', []);
      AssertTrue(Names[i] + ': setup, a plain panel has a frame', TyBorderVisible(plain));
      AssertFalse(Names[i] + ': an embedded one has none', TyBorderVisible(emb));
      AssertEquals(Names[i] + ': and no rounding', 0, TyEffectiveCorners(emb).TL);
    finally
      m.Free;
    end;
  end;
end;

procedure TTyExPanelSectionTest.TestAnEmbeddedSectionHasNoSideInset;
begin
  { the default theme, as an application gets it }
  FPanel.StyleClass := 'embedded';
  AssertEquals('embedded: the body reaches the left edge', 0, FPanel.BodyRect.Left);
  AssertEquals('and the right edge', 200, FPanel.BodyRect.Right);
  AssertEquals('and the bottom', 140, FPanel.BodyRect.Bottom);
  FPanel.StyleClass := '';
  AssertTrue('plain: the frame keeps the body off the edge', FPanel.BodyRect.Left > 0);
end;

{ ---- streaming ---- }

function ComponentText(AComp: TComponent): string;
var
  bin: TMemoryStream;
  txt: TStringStream;
begin
  bin := TMemoryStream.Create;
  txt := TStringStream.Create('');
  try
    bin.WriteComponent(AComp);
    bin.Position := 0;
    ObjectBinaryToText(bin, txt);
    Result := txt.DataString;
  finally
    txt.Free;
    bin.Free;
  end;
end;

procedure ReadComponentText(const AText: string; AComp: TComponent);
var
  bin: TMemoryStream;
  txt: TStringStream;
begin
  bin := TMemoryStream.Create;
  txt := TStringStream.Create(AText);
  try
    ObjectTextToBinary(txt, bin);
    bin.Position := 0;
    bin.ReadComponent(AComp);
  finally
    txt.Free;
    bin.Free;
  end;
end;

procedure TTyExPanelSectionTest.TestAnOldFormReadsAndWritesAsItDid;
const
  { what 3.0 wrote for a panel: none of the new properties }
  COld =
    'object P1: TTyExPanel' + LineEnding +
    '  Left = 8' + LineEnding +
    '  Height = 150' + LineEnding +
    '  Top = 8' + LineEnding +
    '  Width = 220' + LineEnding +
    '  TabOrder = 1' + LineEnding +
    '  Caption = ''Options''' + LineEnding +
    '  HeaderHeight = 30' + LineEnding +
    '  AnimationDuration = 0' + LineEnding +
    'end' + LineEnding;
var
  p: TTyExPanel;
  again: string;
begin
  p := TTyExPanel.Create(FForm);
  p.Parent := FForm;
  ReadComponentText(COld, p);
  AssertEquals('read: its caption', 'Options', p.Caption);
  AssertEquals('read: its header', 30, p.HeaderHeight);
  AssertFalse('read: open', p.Collapsed);
  AssertEquals('read: no action area appears by itself', 0, p.ControlCount);
  AssertEquals('read: actions always', Ord(eavAlways), Ord(p.ActionsVisibility));
  again := ComponentText(p);
  AssertEquals('written back, it is the text it was', COld, again);
end;

procedure TTyExPanelSectionTest.TestActionsVisibilityStreamsWhenSet;
var
  p, q: TTyExPanel;
  txt: string;
begin
  p := TTyExPanel.Create(FForm);
  p.Name := 'P2';
  p.Parent := FForm;
  txt := ComponentText(p);
  AssertEquals('the default is not written', 0, Pos('ActionsVisibility', txt));
  p.ActionsVisibility := eavHoverOrFocus;
  txt := ComponentText(p);
  AssertTrue('a set value is', Pos('ActionsVisibility = eavHoverOrFocus', txt) > 0);
  p.Name := '';
  q := TTyExPanel.Create(FForm);
  q.Parent := FForm;
  ReadComponentText(txt, q);
  AssertEquals('and read back', Ord(eavHoverOrFocus), Ord(q.ActionsVisibility));
end;

procedure TTyExPanelSectionTest.TestTheActionsStreamWithThePanel;
var
  host, back: TForm;
  p: TTyExPanel;
  act: TTyCustomExPanelActions;
  btn: TTabChild;
  ms: TMemoryStream;
  q: TTyExPanel;
begin
  host := TForm.CreateNew(nil);
  back := TForm.CreateNew(nil);
  ms := TMemoryStream.Create;
  try
    p := TTyExPanel.Create(host);
    p.Name := 'Sec';
    p.Parent := host;
    act := p.EnsureHeaderActions;
    act.Name := 'SecActions';
    btn := TTabChild.Create(host);
    btn.Name := 'Btn';
    btn.Parent := act;
    ms.WriteComponent(host);
    ms.Position := 0;
    ms.ReadComponent(back);
    q := back.FindComponent('Sec') as TTyExPanel;
    AssertTrue('the panel came back', q <> nil);
    AssertTrue('with its action area', q.HeaderActions <> nil);
    AssertEquals('by its name', 'SecActions', q.HeaderActions.Name);
    AssertEquals('one area, not two', 1, q.ControlCount);
    AssertEquals('and the button in it', 1, q.HeaderActions.ControlCount);
    AssertEquals('the button', 'Btn', q.HeaderActions.Controls[0].Name);
  finally
    ms.Free;
    back.Free;
    host.Free;
  end;
end;

{ ---- a container that owns the height ---- }

procedure TTyExPanelSectionTest.TestAHostedPanelLeavesItsHeightToTheHost;
var
  host: THostProbe;
  p: TSectionProbe;
begin
  host := THostProbe.Create(FForm);
  host.Parent := FForm;
  p := NewPanel(host);
  p.SetBounds(0, 0, 200, 90);
  p.Collapsed := True;
  AssertEquals('the host was told', 1, host.NToggled);
  AssertEquals('and the panel did not size itself', 90, p.Height);
  p.Collapsed := False;
  AssertEquals('told again', 2, host.NToggled);
  AssertEquals('still the height the host gave', 90, p.Height);
end;

procedure TTyExPanelSectionTest.TestAHostedPanelKeepsItsWeightWhenItCollapses;
var
  host: THostProbe;
  p: TSectionProbe;
begin
  host := THostProbe.Create(FForm);
  host.Parent := FForm;
  p := NewPanel(host);
  p.ExpandedHeight := 300;
  { the host gave it 90 of its 300: collapsing must not make 90 the weight }
  p.SetBounds(0, 0, 200, 90);
  p.Collapsed := True;
  AssertEquals('the weight is what it was', 300, p.ExpandedHeight);
end;

procedure TTyExPanelSectionTest.TestTheApplicationsEventsStillFireWhenHosted;
var
  host: THostProbe;
  p: TSectionProbe;
begin
  host := THostProbe.Create(FForm);
  host.Parent := FForm;
  p := NewPanel(host);
  p.OnExpand := @NoteExpand;
  p.OnCollapse := @NoteCollapse;
  p.Collapsed := True;
  AssertEquals('OnCollapse is the application''s', 1, FCollapses);
  p.Collapsed := False;
  AssertEquals('OnExpand too', 1, FExpands);
end;

procedure TTyExPanelSectionTest.TestAWeightChangeReachesTheHost;
var
  host: THostProbe;
  p: TSectionProbe;
begin
  host := THostProbe.Create(FForm);
  host.Parent := FForm;
  p := NewPanel(host);
  host.NChanged := 0;
  p.ExpandedHeight := 300;
  AssertEquals('a new weight: told', 1, host.NChanged);
  p.ExpandedHeight := 300;
  AssertEquals('the same weight: not told', 1, host.NChanged);
  p.HeaderHeight := 40;
  AssertEquals('a new header height: told', 2, host.NChanged);
end;

procedure TTyExPanelSectionTest.TestAHostedPanelStoresItsWeightExpanded;
var
  host: THostProbe;
  p, lone: TSectionProbe;
begin
  host := THostProbe.Create(FForm);
  host.Parent := FForm;
  p := NewPanel(host);
  p.Name := 'Hosted';
  p.ExpandedHeight := 300;
  AssertTrue('in a stack the weight is stored while the panel is open',
    Pos('ExpandedHeight = 300', ComponentText(p)) > 0);
  lone := NewPanel(FForm);
  lone.Name := 'Lone';
  lone.ExpandedHeight := 300;
  AssertEquals('on its own an open panel stores none, as before', 0,
    Pos('ExpandedHeight', ComponentText(lone)));
end;

procedure TTyExPanelSectionTest.TestKeysTheHeaderDoesNotUseGoToTheHost;
var
  host: THostProbe;
  p: TSectionProbe;
begin
  host := THostProbe.Create(FForm);
  host.Parent := FForm;
  p := NewPanel(host);
  AssertEquals('Down is offered, and left alone when the host does not want it', VK_DOWN,
    p.KeyLeft(VK_DOWN));
  AssertEquals('offered once', 1, host.NKeys);
  AssertEquals('as Down', VK_DOWN, host.LastKey);
  host.TakeKeys := True;
  AssertEquals('taken when the host takes it', 0, p.KeyLeft(VK_UP));
  AssertEquals('as Up', VK_UP, host.LastKey);
  { the header's own keys never get that far }
  host.NKeys := 0;
  p.Key(VK_SPACE);
  p.Key(VK_LEFT);
  AssertEquals('Space and Left are the header''s', 0, host.NKeys);
end;

procedure TTyExPanelSectionTest.TestWithoutAHostThePanelSizesItselfAsBefore;
begin
  FPanel.SetBounds(0, 0, 200, 90);
  FPanel.Collapsed := True;
  AssertEquals('it closes to its header', 26, FPanel.Height);
  AssertEquals('and remembers the height it had', 90, FPanel.ExpandedHeight);
  FPanel.Collapsed := False;
  AssertEquals('and opens to it', 90, FPanel.Height);
end;

initialization
  { the streaming tests read these back by class name }
  RegisterClasses([TTyExPanel, TTyExPanelActions, TTabChild]);
  RegisterTest(TTyExPanelSectionTest);
end.
