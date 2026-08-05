unit test.rtl;
{ RTL MIRRORING -- the layout half of right-to-left support.

  Its sibling test.bidi.pas guards the TEXT half: word order, shaping, the paragraph's base
  direction. That half asks "which way does this SENTENCE read" and answers it from the
  string. This unit guards the other question, "which way does this FORM read", which is
  answered from the control's BiDiMode and moves BOXES, not glyphs. The two are independent
  on purpose -- an Arabic caption on a left-to-right form reorders its words and stays on the
  left; a Latin caption on a right-to-left form keeps its word order and moves to the right --
  and several of the tests below exist only to pin that independence.

  Scope, deliberately partial: phases 0, 1 and 3 of plans/2026-08-04-rtl-mirroring-scope.md.

  Phases 0 and 1 are the painter's alignment lever plus the five control families that already
  had a left/right switch built. Every control in that batch answers clicks over its WHOLE
  face, so paint and hit test cannot come apart -- which is the entire reason it was a safe
  cut to ship.

  Phase 3 is the scrolling containers and the list boxes, and it is the first batch where that
  is NOT true for free: a scroll bar's thumb is both painted and grabbed, and a check list's
  box is both drawn and clicked. Each of those now has ONE rect function that both halves call
  (TyScrollThumbRect with its ARightToLeft argument, TyCheckBoxSlotRect), and the guards below
  press where the paint actually landed rather than where the arithmetic says it should have.
  Three controls that compute their x a second time from something other than the rect they
  paint into are excluded instead, and TRtlExclusionTest pins all three so a later mirroring
  commit has to face the hit test rather than walk past it.

  Everything is headless: pure geometry functions where there are any, and RenderTo into an
  off-screen bitmap where there are not. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, ExtCtrls, fpcunit, testregistry, Forms,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Controller, tyControls.Base,
  tyControls.TyLabel, tyControls.Divider, tyControls.CheckBox, tyControls.GroupBox,
  tyControls.CheckGroup, tyControls.RadioGroup, tyControls.Button, tyControls.GlyphButtons,
  tyControls.DropButtons, tyControls.ColorButton, tyControls.ButtonGroup, tyControls.Panel,
  tyControls.IconFont,
  tyControls.ScrollBar, tyControls.ScrollBox, tyControls.ScrollPanel, tyControls.ScrollContent,
  tyControls.ListBox, tyControls.CheckListBox, tyControls.ColorListBox,
  tyControls.ValueListEditor,
  tyControls.HeaderControl;

type
  { RenderTo is protected on every one of these; the tests must call it directly, because
    Paint is unreachable without a realised handle the headless runner never creates. }
  TLabelAccess       = class(TTyLabel) public procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer); end;
  TCheckAccess       = class(TTyCheckBox) public procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer); end;
  TRadioAccess       = class(TTyRadioButton) public procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer); end;
  TGroupBoxAccess    = class(TTyGroupBox) public procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer); end;
  TPanelAccess       = class(TTyPanel) public procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer); end;
  TButtonAccess      = class(TTyButton) public procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer); end;
  TGlyphBtnAccess    = class(TTyGlyphButton) public procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer); end;
  TColorBtnAccess    = class(TTyColorButton) public procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer); end;
  TDropBtnAccess     = class(TTyDropDownButton) public procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer); function ArrowW(APPI: Integer): Integer; end;
  { The header strip additionally needs its mouse handlers reachable: it is the first control
    in this programme whose HIT TEST mirrors, so a paint-only probe would miss the half that
    matters. }
  THdrAccess = class(TTyHeaderControl) public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure PressDown(X: Integer); procedure PressMove(X: Integer); procedure PressUp(X: Integer);
  end;

  { Phase 3's access shims. Mouse handlers and RenderTo are protected on every one of these,
    and the scroll box's three layout hooks are too -- driving them directly is also the only
    honest way to test a container headlessly, because LCL's align engine never runs on a form
    that was never shown (TControl.AdjustSize bails on AutoSizeDelayedHandle), so an assertion
    on a child's Left after a SetBounds passes just as happily on the broken code. }
  TBarAccess = class(TTyScrollBar)
  public
    procedure CallMouseDown(X, Y: Integer);
    procedure CallMouseMove(X, Y: Integer);
    procedure CallMouseUp(X, Y: Integer);
    function  CallKeyDown(AKey: Word): Word;
    function  Track: TRect;
  end;

  TBoxAccess = class(TTyScrollBox)
  public
    function VBar: TTyScrollBar;
    function HBar: TTyScrollBar;
    function Viewport: TControl;
    function Frame: Integer;
    { GetLogicalClientRect then AdjustClientRect -- exactly what the align engine asks for,
      and the seam the whole three-hook contract lives behind. }
    function ChildArea: TRect;
  end;

  TPanAccess = class(TTyScrollPanel)
  public
    function PanViewport: TRect;
    function Lead: Integer;
  end;

  TListAccess = class(TTyListBox)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function  Bar: TTyScrollBar;
    procedure Bounds2(AWidth, APPI: Integer; out ALeft, ARight: Integer);
    procedure Remeasure;
  end;

  TCheckListAccess = class(TTyCheckListBox)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure CallMouseDown(X, Y: Integer);
    function  Zone: TRect;
    procedure Bounds2(AWidth, APPI: Integer; out ALeft, ARight: Integer);
  end;

  TColorListAccess = class(TTyColorListBox)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TValueListAccess = class(TTyValueListEditor)
  public
    function Mirrors: Boolean;
  end;

  { The painter lever itself: phase 0. One flag, set at BeginPaint, resolving every
    alignment the caller passes from a reading-order one to a physical one. }
  TRtlPainterTest = class(TTestCase)
  private
    { Draw AText into an AW x AH bitmap with the painter armed (or not) and return it. }
    function Draw(const AText: string; AW, AH: Integer; AHAlign: TAlignment;
      ARtl: Boolean; AMnemonicPos: Integer = 0): TBGRABitmap;
  published
    procedure UnarmedPainterLeavesAlignmentExactlyAsTheCallerWroteIt;
    procedure ArmedPainterMovesALeadingAlignedCaptionToTheRightEdge;
    procedure ArmedPainterMovesATrailingAlignedCaptionToTheLeftEdge;
    procedure CentredTextIsTheFixedPointOfMirroring;
    procedure MnemonicUnderlineTravelsWithTheMirroredCaption;
    procedure CaretQueryAnswersFromTheMirroredBlockNotTheUnmirroredOne;
    procedure CaretAndHitTestStayInversesUnderMirroring;
    procedure MirroringIsTheFormsDirectionNotTheScriptsDirection;
  end;

  { Phase 1, the controls that carry a caption in their WHOLE content rect: the painter
    flag is the entire change, so these guard the wiring rather than any new arithmetic. }
  TRtlCaptionTest = class(TTestCase)
  published
    procedure LabelCaptionMovesToTheRightEdge;
    procedure PanelCaptionMovesToTheRightEdge;
    procedure GroupBoxCaptionBandMovesToTheOtherEndOfTheFrame;
    procedure ButtonCaptionMovesButTheDefaultCentredOneDoesNot;
  end;

  { Phase 1, the check box / radio button pair: the indicator changes sides and the caption
    re-hugs it. The switch predates this work; only which way it points is new. }
  TRtlIndicatorTest = class(TTestCase)
  published
    procedure CheckBoxIndicatorMovesToTheRightEdge;
    procedure CheckBoxCaptionStaysHuggedToTheMirroredIndicator;
    procedure RadioButtonIndicatorMovesToTheRightEdge;
    procedure ExplicitAlignmentIsOverriddenNotIgnored;
    procedure MirroringNeverRewritesTheStoredAlignment;
  end;

  { Phase 1, the pure geometry functions. These are the cheapest and strongest guards in the
    unit: no painter, no handle, no theme -- just the arithmetic. }
  TRtlGeometryTest = class(TTestCase)
  published
    procedure DividerCaptionAndRuleSwapEnds;
    procedure DividerIndentCountsFromTheReadingStart;
    procedure DividerMirroringLeavesNoSeamBetweenCaptionAndRule;
    procedure DividerWithNoCaptionKeepsItsFullWidthRuleInRightRule;
    procedure CheckGroupColumnsFillFromTheRight;
    procedure RadioGroupColumnsFillFromTheRight;
    procedure MirroredColumnsStillTileTheClientRectFlush;
    procedure BadgeCornerFlipsHorizontallyAndNotVertically;
    procedure GlyphLayoutFlipsTheSidePairAndNotTheStackedPair;
  end;

  { Phase 1, the composite controls: real child controls, and the keyboard. }
  TRtlGroupTest = class(TTestCase)
  published
    procedure RadioGroupChildrenInheritTheGroupsDirection;
    procedure RadioGroupChildrenAreLaidOutRightToLeft;
    procedure CheckGroupChildrenAreLaidOutRightToLeft;
    procedure ArrowKeysFollowTheMirroredColumnsNotTheScreenEdges;
    procedure VerticalArrowKeysAreUntouchedByMirroring;
  end;

  { Phase 1, the button descendants that own a slot beside the caption. }
  TRtlButtonSlotTest = class(TTestCase)
  published
    procedure GlyphButtonCaptionMovesToTheOtherSideOfTheIcon;
    procedure ColorButtonSwatchMovesToTheRightEdge;
    procedure BadgeMovesToTheTrailingCornerWhichIsBottomLeftWhenMirrored;
  end;

  { Phase 2: TTyHeaderControl — the first control here whose HIT TEST mirrors, and the reason
    it could. Every consumer of its x axis reads it out of ONE pure function: the paint
    (RenderTo), both hit tests (section-at-x, resize-edge-at-x) and EffectiveSectionWidth all
    call TyHeaderSectionRects and nothing else computes an x. So the direction flag goes into
    that function and the other four follow, rather than four places each being taught to
    mirror and one of them being forgotten -- which is the defect the whole programme is
    hunting (TTyShape's bounding box, TTyTreeView.GetNodeAt, the date picker's month/year).

    HitTestAgreesWithThePaintedTilingAtEveryPixel is the load-bearing one: it walks every
    device x across the strip and asserts the hit test names the section whose PAINTED rect
    covers it. It does not encode any expected geometry, so it survives a change to the
    tiling and fails only if the two halves come apart. }
  TRtlHeaderTest = class(TTestCase)
  published
    procedure SectionsTileFromTheRightEdgeWhenMirrored;
    procedure MirroredTilingIsGaplessAndFlushToBothClientEdges;
    procedure MirroredTilingIsARectForRectReflectionOfTheLtrOne;
    procedure MirroringPreservesEverySectionsPaintedWidthAbsorberIncluded;
    procedure AnOverfullMirroredStripOverrunsTheLeftEdgeNotTheRight;
    procedure HitTestAgreesWithThePaintedTilingAtEveryPixel;
    procedure TheStripsOuterEdgeBelongsToWhicheverSectionIsAgainstIt;
    procedure ResizeGripGrabsTheMirroredBoundaryAndNotTheLtrOne;
    procedure NeitherOuterEdgeIsAResizeBoundaryWhenMirrored;
    procedure SortTriangleMovesToTheCellsLeftGutterWhenMirrored;
    procedure SortTriangleMirrorsHorizontallyAndNotVertically;
    procedure MirroredStripSortsTheSectionUnderTheClickNotItsLtrTwin;
    procedure DraggingAMirroredBoundaryAwayFromTheReadingStartWidensTheSection;
    procedure EffectiveSectionWidthIsUnchangedByMirroring;
    procedure MirroredCaptionRendersAgainstTheRightEdgeOfItsCell;
    procedure SortTriangleIsPaintedInTheMirroredCellsLeftGutter;
    procedure MirroredSortGutterIsReservedOnTheSideTheTriangleMovedTo;
    procedure MirroredDividerIsDrawnOnTheEdgeTheResizeGripGrabs;
  end;

  { The two controls in these same source files that are deliberately NOT mirrored, because
    they read x back out of a click. Pinned so that mirroring them later is a decision
    somebody makes on purpose, with the hit test in the same commit. }
  TRtlExclusionTest = class(TTestCase)
  published
    procedure DropDownArrowStaysWhereItsHitTestSaysItIs;
    procedure ButtonGroupSegmentsAreNotMirroredWhileSegmentAtReadsRawX;
    procedure ValueListEditorIsNotMirroredWhileItsSplitterIsHitTestedTwice;
  end;

  { --------------------------------------------------------------- PHASE 3 -- }

  { Phase 3a, TTyScrollBar. Horizontal only: a mirrored bar puts Min at the RIGHT end and
    walks the thumb leftwards as Position rises. The geometry is three pure functions, so
    most of this is arithmetic with no control at all -- and the ones that DO build a control
    are the ones that matter, because a scroll bar is the first thing in this library where
    the same rect is both painted and clicked. }
  TRtlScrollBarGeometryTest = class(TTestCase)
  published
    procedure MirroredHorizontalThumbStartsAtTheRightEndOfTheTrack;
    procedure MirroredHorizontalThumbEndsAtTheLeftEndOfTheTrack;
    procedure MirroredThumbIsTheExactReflectionOfTheUnmirroredOne;
    procedure VerticalThumbsAreUntouchedByTheMirror;
    procedure TrackAndButtonSizeAreSymmetricSoTheyDoNotMirror;
  end;

  TRtlScrollBarControlTest = class(TTestCase)
  private
    FForm: TForm;
    function MakeBar(AMirror: Boolean): TTyScrollBar;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure MirroringIsOptInAndNotTakenFromTheFormsBiDiMode;
    procedure AMirroredBarGrabsTheThumbWhereItPaintsIt;
    procedure AMirroredBarDoesNotGrabWhereTheUnmirroredThumbUsedToBe;
    procedure DraggingAMirroredThumbLeftRaisesThePosition;
    procedure DragAndPaintStayExactInversesUnderTheMirror;
    procedure TheLeftEndButtonRaisesThePositionOnAMirroredBar;
    procedure ATrackClickPagesTowardsTheClickOnAMirroredBar;
    procedure ArrowKeysFollowTheThumbAndHomeEndStayLogical;
    procedure AVerticalBarIgnoresMirrorHorizontalCompletely;
  end;

  { Phase 3b, TTyScrollBox / TTyScrollPanel. The vertical bar moves to the LEFT edge, which
    is the loudest signal a window gives that it reads right-to-left.

    Half of this suite exists for the three-hook contract the unit's own comments describe
    (ScrollBox.pas:20-31 and the GetLogicalClientRect / AdjustClientRect declarations): the
    client rect owes the gutters their SIZE, the layout area grows to the content, and the
    origin follows the offset. Mirroring touches the third and must not touch the first --
    the recorded symptom of getting that wrong is an akRight child losing a scrollbar's width
    on every single scroll. }
  TRtlScrollBoxTest = class(TTestCase)
  private
    FForm: TForm;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TheVerticalBarDocksToTheLeftEdge;
    procedure TheHorizontalBarStartsAfterTheMirroredGutter;
    procedure TheViewportStartsAfterTheMirroredGutter;
    procedure TheLayoutOriginClearsTheMirroredGutter;
    procedure MirroringChangesTheSideOfTheGuttersAndNotTheirCost;
    procedure TheScrolledOriginStillFollowsTheOffsetWhenMirrored;
    procedure ReDockingAfterAScrollKeepsTheBarsOnTheMirroredSide;
    procedure TheBoxsOwnHorizontalBarDoesNotMirrorItsOrigin;
    procedure AutoPanBandsMoveWithTheMirroredViewport;
  end;

  { Phase 3c, the list boxes. }
  TRtlListBoxTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TheScrollBarDocksToTheLeftEdge;
    procedure RowsGiveUpTheGutterOnTheSideTheBarIsActuallyOn;
    procedure RowTextMovesToTheRightEdge;
    procedure ChangingBiDiModeMovesABarThatAlreadyExists;
    procedure TheCheckBoxAndTheZoneThatTogglesItMoveTogether;
    procedure TheCheckBoxIsPaintedInsideTheZoneThatTogglesIt;
    procedure AMirroredCheckBoxIsNotToggledByAClickWhereItUsedToBe;
    procedure TheColourSwatchMovesToTheRightEdge;
  end;

implementation

const
  cInk = 40;   // alpha above which a pixel counts as ink (matches test.bidi.pas)

procedure TLabelAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);      begin inherited RenderTo(ACanvas, ARect, APPI); end;
procedure TCheckAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);      begin inherited RenderTo(ACanvas, ARect, APPI); end;
procedure TRadioAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);      begin inherited RenderTo(ACanvas, ARect, APPI); end;
procedure TGroupBoxAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);   begin inherited RenderTo(ACanvas, ARect, APPI); end;
procedure TPanelAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);      begin inherited RenderTo(ACanvas, ARect, APPI); end;
procedure TButtonAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);     begin inherited RenderTo(ACanvas, ARect, APPI); end;
procedure TGlyphBtnAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);   begin inherited RenderTo(ACanvas, ARect, APPI); end;
procedure TColorBtnAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);   begin inherited RenderTo(ACanvas, ARect, APPI); end;
procedure TDropBtnAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);    begin inherited RenderTo(ACanvas, ARect, APPI); end;
function  TDropBtnAccess.ArrowW(APPI: Integer): Integer;     begin Result := ArrowZoneWidth(APPI); end;
procedure THdrAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);        begin inherited RenderTo(ACanvas, ARect, APPI); end;
{ Y is fixed at 10 (any row inside a 26px strip behaves alike -- the strip has no vertical
  hit zones at all), so the probes take only the x that is actually under test. }
procedure THdrAccess.PressDown(X: Integer);  begin MouseDown(mbLeft, [], X, 10); end;
procedure THdrAccess.PressMove(X: Integer);  begin MouseMove([], X, 10); end;
procedure THdrAccess.PressUp(X: Integer);    begin MouseUp(mbLeft, [], X, 10); end;

procedure TBarAccess.CallMouseDown(X, Y: Integer); begin MouseDown(mbLeft, [], X, Y); end;
procedure TBarAccess.CallMouseMove(X, Y: Integer); begin MouseMove([], X, Y); end;
procedure TBarAccess.CallMouseUp(X, Y: Integer);   begin MouseUp(mbLeft, [], X, Y); end;
function  TBarAccess.CallKeyDown(AKey: Word): Word;
begin
  Result := AKey;
  KeyDown(Result, []);
end;
function TBarAccess.Track: TRect;
begin
  { The bar's own TrackRect is private; this is the same call it makes. }
  Result := TyScrollTrackRect(ClientRect, Kind, TyScrollButtonSize(ClientRect, Kind));
end;

function TBoxAccess.VBar: TTyScrollBar;
var i: Integer;
begin
  Result := nil;
  for i := 0 to ControlCount - 1 do
    if (Controls[i] is TTyScrollBar) and (TTyScrollBar(Controls[i]).Kind = sbVertical) then
      Exit(TTyScrollBar(Controls[i]));
end;

function TBoxAccess.HBar: TTyScrollBar;
var i: Integer;
begin
  Result := nil;
  for i := 0 to ControlCount - 1 do
    if (Controls[i] is TTyScrollBar) and (TTyScrollBar(Controls[i]).Kind = sbHorizontal) then
      Exit(TTyScrollBar(Controls[i]));
end;

function TBoxAccess.Viewport: TControl;
var i: Integer;
begin
  Result := nil;
  for i := 0 to ControlCount - 1 do
    if Controls[i] is TTyScrollContent then Exit(Controls[i]);
end;

function TBoxAccess.Frame: Integer;
begin
  Result := FrameInset;
end;

function TBoxAccess.ChildArea: TRect;
begin
  Result := GetLogicalClientRect;
  AdjustClientRect(Result);
end;

function TPanAccess.PanViewport: TRect;
begin
  Result := AutoPanViewport;
end;

function TPanAccess.Lead: Integer;
begin
  Result := LeadingInset;
end;

procedure TListAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

function TListAccess.Bar: TTyScrollBar;
var i: Integer;
begin
  Result := nil;
  for i := 0 to ControlCount - 1 do
    if Controls[i] is TTyScrollBar then Exit(TTyScrollBar(Controls[i]));
end;

procedure TListAccess.Bounds2(AWidth, APPI: Integer; out ALeft, ARight: Integer);
begin
  RowContentBounds(AWidth, APPI, ALeft, ARight);
end;

procedure TListAccess.Remeasure;
begin
  UpdateScrollBar;
end;

procedure TCheckListAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TCheckListAccess.CallMouseDown(X, Y: Integer);
begin
  MouseDown(mbLeft, [ssLeft], X, Y);
end;

function TCheckListAccess.Zone: TRect;
begin
  Result := CheckZoneRect;
end;

procedure TCheckListAccess.Bounds2(AWidth, APPI: Integer; out ALeft, ARight: Integer);
begin
  RowContentBounds(AWidth, APPI, ALeft, ARight);
end;

procedure TColorListAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

function TValueListAccess.Mirrors: Boolean;
begin
  Result := RtlRowLayout;
end;

{ Press an arrow key the way a user does: on the FOCUSED CHILD. The group's navigation lives
  behind the OnKeyDown it wires onto every hosted radio (tyControls.RadioGroup.pas:311), so
  driving it from there exercises the whole route -- key to relay to MoveSelection -- rather
  than a private helper the keyboard might one day stop reaching. }
procedure PressArrow(AGroup: TTyRadioGroup; AChild: TControl; AKey: Word);
var
  k: Word;
  h: TKeyEvent;
begin
  k := AKey;
  h := TTyRadioButton(AChild).OnKeyDown;
  if Assigned(h) then h(AChild, k, []);
end;

{ ---------------------------------------------------------------- helpers -- }

{ The x-span of every pixel whose alpha clears cInk. L = -1 when there is no ink at all,
  which every caller asserts against before reading the span -- an empty bitmap otherwise
  compares "further right" than anything and turns a blank render into a pass. }
procedure InkSpanX(A: TBGRABitmap; out L, R: Integer);
var
  x, y: Integer;
begin
  L := A.Width; R := -1;
  for y := 0 to A.Height - 1 do
    for x := 0 to A.Width - 1 do
      if A.GetPixel(x, y).alpha > cInk then
      begin
        if x < L then L := x;
        if x > R then R := x;
      end;
  if R < 0 then L := -1;
end;

{ The x-span of pixels in which ONE channel dominates -- the way every control probe below
  finds its piece of a composite.

  Deliberately a dominance test rather than "matches this colour" or "is dark", because the
  host a control's RenderTo composites onto is not a reliable reference here: a pf32bit
  TBitmap round-tripped back through TBGRABitmap comes back with the GDI fill LOST (the
  background reads 0,0,0 whatever colour it was painted). That is the same class of trap the
  library's own notes record about BGRA/TPicture round-trips, and probing "dark ink" against
  it silently matches the whole bitmap. Channel dominance is true of a saturated theme colour
  and false of black, white and every grey, so it survives whatever the background turns out
  to be -- which is why the themes these tests load use pure red / green / blue. }
type
  TChannel = (chRed, chGreen, chBlue);

procedure ChannelSpanX(A: TBGRABitmap; ACh: TChannel; out L, R: Integer);
var
  x, y, mine, o1, o2: Integer;
  p: TBGRAPixel;
begin
  L := A.Width; R := -1;
  for y := 0 to A.Height - 1 do
    for x := 0 to A.Width - 1 do
    begin
      p := A.GetPixel(x, y);
      case ACh of
        chRed:   begin mine := p.red;   o1 := p.green; o2 := p.blue;  end;
        chGreen: begin mine := p.green; o1 := p.red;   o2 := p.blue;  end;
      else       begin mine := p.blue;  o1 := p.red;   o2 := p.green; end;
      end;
      if (mine > 150) and (o1 < 110) and (o2 < 110) then
      begin
        if x < L then L := x;
        if x > R then R := x;
      end;
    end;
  if R < 0 then L := -1;
end;

{ Is there ink of ACh anywhere in device column X? ChannelSpanX answers "where is the ink"
  and is blind to everything between its two ends, which is no use for a probe whose subject
  is a set of one-pixel vertical rules: two dividers and their two absences all live inside
  the same span. }
function ChannelInColumn(A: TBGRABitmap; ACh: TChannel; X: Integer): Boolean;
var
  y, mine, o1, o2: Integer;
  p: TBGRAPixel;
begin
  Result := False;
  if (X < 0) or (X >= A.Width) then Exit;
  for y := 0 to A.Height - 1 do
  begin
    p := A.GetPixel(X, y);
    case ACh of
      chRed:   begin mine := p.red;   o1 := p.green; o2 := p.blue;  end;
      chGreen: begin mine := p.green; o1 := p.red;   o2 := p.blue;  end;
    else       begin mine := p.blue;  o1 := p.red;   o2 := p.green; end;
    end;
    if (mine > 150) and (o1 < 110) and (o2 < 110) then Exit(True);
  end;
end;

{ An AW x AH host bitmap for RenderTo. Its colour is not asserted on anywhere (see
  ChannelSpanX); it is filled only so the canvas is initialised. }
function NewHost(AW, AH: Integer): TBitmap;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := pf32bit;
  Result.SetSize(AW, AH);
  Result.Canvas.Brush.Color := clWhite;
  Result.Canvas.FillRect(0, 0, AW, AH);
end;

{ ------------------------------------------------------------ TRtlPainterTest }

function TRtlPainterTest.Draw(const AText: string; AW, AH: Integer; AHAlign: TAlignment;
  ARtl: Boolean; AMnemonicPos: Integer = 0): TBGRABitmap;
var
  host: TBitmap;
  p: TTyPainter;
begin
  host := TBitmap.Create;
  p := TTyPainter.Create;
  try
    host.SetSize(AW, AH);
    p.BeginPaint(host.Canvas, Rect(0, 0, AW, AH), 96, ARtl);
    p.DrawText(Rect(0, 0, AW, AH), AText, 'Arial', 12, 400, TyRGBA(0, 0, 0, 255),
      AHAlign, tlCenter, False, AMnemonicPos);
    Result := TBGRABitmap.Create(AW, AH);
    Result.PutImage(0, 0, p.Bitmap, dmSet);
    p.EndPaint;
  finally
    p.Free;
    host.Free;
  end;
end;

{ The default, and the reason every one of the 5000-odd existing pixel assertions still
  holds: BidiFlipAlignment's False row is the identity, so an unarmed painter is the painter
  that was there before. Stated as its own test because "the default is False" is the whole
  safety property of making this a parameter instead of something read off the control. }
procedure TRtlPainterTest.UnarmedPainterLeavesAlignmentExactlyAsTheCallerWroteIt;
var
  bmp: TBGRABitmap;
  l, r: Integer;
begin
  bmp := Draw('Ag', 200, 30, taLeftJustify, False);
  try
    InkSpanX(bmp, l, r);
    AssertTrue('caption drew something', l >= 0);
    AssertTrue('left-aligned text starts near the left edge', l < 8);
    AssertTrue('and does not reach the right edge', r < 100);
  finally
    bmp.Free;
  end;
end;

{ Phase 0 itself. taLeftJustify means "the reading start", so on a right-to-left form it
  resolves to the RIGHT edge -- and because every DrawText in the library funnels through
  the one function that does this, arming a control mirrors all of its text at once. }
procedure TRtlPainterTest.ArmedPainterMovesALeadingAlignedCaptionToTheRightEdge;
var
  bmp: TBGRABitmap;
  l, r: Integer;
begin
  bmp := Draw('Ag', 200, 30, taLeftJustify, True);
  try
    InkSpanX(bmp, l, r);
    AssertTrue('caption drew something', l >= 0);
    AssertTrue('mirrored leading-aligned text ends near the right edge', r > 200 - 8);
    AssertTrue('and no longer touches the left edge', l > 100);
  finally
    bmp.Free;
  end;
end;

{ The other direction, so a mutant that hard-codes taRightJustify instead of flipping is
  caught rather than half-caught. }
procedure TRtlPainterTest.ArmedPainterMovesATrailingAlignedCaptionToTheLeftEdge;
var
  bmp: TBGRABitmap;
  l, r: Integer;
begin
  bmp := Draw('Ag', 200, 30, taRightJustify, True);
  try
    InkSpanX(bmp, l, r);
    AssertTrue('caption drew something', l >= 0);
    AssertTrue('mirrored trailing-aligned text starts near the left edge', l < 8);
    AssertTrue('and no longer reaches the right edge', r < 100);
  finally
    bmp.Free;
  end;
end;

{ taCenter has no reading direction, so it must survive the flip untouched -- which is also
  why the great majority of buttons in an existing UI render byte-identically when mirrored
  (TTyButton.Alignment defaults to taCenter). }
procedure TRtlPainterTest.CentredTextIsTheFixedPointOfMirroring;
var
  ltr, rtl: TBGRABitmap;
  ll, lr, rl, rr: Integer;
begin
  ltr := Draw('Ag', 200, 30, taCenter, False);
  rtl := Draw('Ag', 200, 30, taCenter, True);
  try
    InkSpanX(ltr, ll, lr);
    InkSpanX(rtl, rl, rr);
    AssertTrue('centred caption drew something', ll >= 0);
    AssertEquals('centred text does not move when mirrored (left edge)', ll, rl);
    AssertEquals('centred text does not move when mirrored (right edge)', lr, rr);
  finally
    ltr.Free;
    rtl.Free;
  end;
end;

{ The mnemonic underline is placed by a SECOND reading of the alignment, a few lines below
  the one that places the glyphs. Mirroring them from one resolved value is what keeps them
  together; this is the test that fails if a later change flips only the text. }
procedure TRtlPainterTest.MnemonicUnderlineTravelsWithTheMirroredCaption;
var
  plain, marked: TBGRABitmap;
  pl, pr, ml, mr: Integer;
begin
  { The same caption with and without an underline. The underline can only ADD ink, so if it
    landed at the unmirrored position the marked render's span would reach further LEFT than
    the plain one's -- a whole box away, not a pixel. }
  plain  := Draw('Save', 200, 30, taLeftJustify, True, 0);
  marked := Draw('Save', 200, 30, taLeftJustify, True, 1);
  try
    InkSpanX(plain, pl, pr);
    InkSpanX(marked, ml, mr);
    AssertTrue('both captions drew something', (pl >= 0) and (ml >= 0));
    { First: the underlined caption is mirrored AT ALL. Without this the two comparisons
      below are satisfied by an unmirrored pair just as well as by a mirrored one -- they
      only say the underline agrees with the text, not that either of them moved. }
    AssertTrue('the underlined caption is at the right edge like its plain twin',
      (mr > 200 - 8) and (ml > 100));
    AssertTrue('the underline did not land back at the unmirrored position',
      ml >= pl - 2);
    AssertTrue('and it stayed inside the mirrored caption', mr <= pr + 2);
  finally
    plain.Free;
    marked.Free;
  end;
end;

{ TextCaretX answers "where on screen is character N". It is the seam a text control will
  eventually use, and a caret computed from an UNmirrored block would point at a glyph that
  is no longer there -- the paint/hit-test split this project has been bitten by repeatedly,
  arriving through the one door nobody watches. }
procedure TRtlPainterTest.CaretQueryAnswersFromTheMirroredBlockNotTheUnmirroredOne;
var
  host: TBitmap;
  p: TTyPainter;
  xLtr, xRtl: Integer;
begin
  host := TBitmap.Create;
  p := TTyPainter.Create;
  try
    host.SetSize(200, 30);
    p.BeginPaint(host.Canvas, Rect(0, 0, 200, 30), 96, False);
    xLtr := p.TextCaretX(Rect(0, 0, 200, 30), 'Save', 'Arial', 12, 400, taLeftJustify, 0);
    p.EndPaint;
    p.BeginPaint(host.Canvas, Rect(0, 0, 200, 30), 96, True);
    xRtl := p.TextCaretX(Rect(0, 0, 200, 30), 'Save', 'Arial', 12, 400, taLeftJustify, 0);
    p.EndPaint;
    AssertTrue('unmirrored caret sits at the left edge', xLtr < 8);
    AssertTrue('mirrored caret moved with the text block', xRtl > 100);
  finally
    p.Free;
    host.Free;
  end;
end;

{ The pair has to be mirrored TOGETHER or not at all. TextCaretX says where character n is;
  TextCharIndexAtX says which character is at x. Mirror one and not the other and every click
  lands on the wrong glyph -- which is the paint/hit-test split in its purest form, and the
  reason both queries flip in the same commit as the drawing does. Asserted as the round
  trip, so it holds whatever the actual coordinates turn out to be. }
procedure TRtlPainterTest.CaretAndHitTestStayInversesUnderMirroring;
var
  host: TBitmap;
  p: TTyPainter;
  i, x, back: Integer;
begin
  host := TBitmap.Create;
  p := TTyPainter.Create;
  try
    host.SetSize(200, 30);
    p.BeginPaint(host.Canvas, Rect(0, 0, 200, 30), 96, True);
    for i := 0 to 3 do
    begin
      { Probe the MIDDLE of each character rather than its leading edge: a caret sits on a
        boundary, and asking which character owns a boundary is ambiguous by construction. }
      x := (p.TextCaretX(Rect(0, 0, 200, 30), 'Save', 'Arial', 12, 400, taLeftJustify, i)
          + p.TextCaretX(Rect(0, 0, 200, 30), 'Save', 'Arial', 12, 400, taLeftJustify, i + 1)) div 2;
      back := p.TextCharIndexAtX(Rect(0, 0, 200, 30), 'Save', 'Arial', 12, 400, taLeftJustify, x);
      AssertEquals('the mirrored hit test inverts the mirrored caret', i, back);
    end;
    p.EndPaint;
  finally
    p.Free;
    host.Free;
  end;
end;

{ The independence the whole design rests on. An Arabic caption on a LEFT-to-right form
  keeps its words in bidi order AND stays on the left; the script does not get a vote on
  layout. Conflating the two would move every Arabic label in an otherwise English UI. }
procedure TRtlPainterTest.MirroringIsTheFormsDirectionNotTheScriptsDirection;
var
  bmp: TBGRABitmap;
  l, r: Integer;
begin
  { U+0628 U+062A -- BEH TEH, the pair test.bidi.pas uses. Right-to-left script, unarmed
    painter, leading alignment: it must sit on the LEFT. }
  bmp := Draw(#$D8#$A8#$D8#$AA, 200, 30, taLeftJustify, False);
  try
    InkSpanX(bmp, l, r);
    AssertTrue('the Arabic caption drew something', l >= 0);
    AssertTrue('right-to-left SCRIPT does not move a caption on a left-to-right FORM',
      l < 8);
  finally
    bmp.Free;
  end;
end;

{ ------------------------------------------------------------ TRtlCaptionTest }

procedure TRtlCaptionTest.LabelCaptionMovesToTheRightEdge;
var
  Ctl: TTyStyleController;
  Form: TForm;
  C: TLabelAccess;
  host: TBitmap;
  shot: TBGRABitmap;
  l, r: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  host := NewHost(200, 26);
  try
    Ctl.LoadThemeCss('TyLabel { color: #00FF00; padding: 0px; }');
    C := TLabelAccess.Create(Form);
    C.Parent := Form;
    C.Controller := Ctl;
    C.Font.PixelsPerInch := 96;
    C.Caption := 'Name';
    C.Alignment := taLeftJustify;
    C.BiDiMode := bdRightToLeft;
    C.RenderTo(host.Canvas, Rect(0, 0, 200, 26), 96);
    shot := TBGRABitmap.Create(host);
    try
      ChannelSpanX(shot, chGreen, l, r);
      AssertTrue('the label drew its caption', l >= 0);
      AssertTrue('a leading-aligned label caption sits at the RIGHT edge when mirrored',
        r > 200 - 10);
      AssertTrue('and has left the left edge', l > 100);
    finally
      shot.Free;
    end;
  finally
    host.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

procedure TRtlCaptionTest.PanelCaptionMovesToTheRightEdge;
var
  Ctl: TTyStyleController;
  Form: TForm;
  C: TPanelAccess;
  host: TBitmap;
  shot: TBGRABitmap;
  l, r: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  host := NewHost(200, 26);
  try
    { A panel's Alignment defaults to taCenter, which mirroring deliberately leaves alone --
      so the property has to be set for there to be anything to see. }
    Ctl.LoadThemeCss('TyPanel { background: #FFFFFF; color: #00FF00; border-width: 0px; padding: 0px; }');
    C := TPanelAccess.Create(Form);
    C.Parent := Form;
    C.Controller := Ctl;
    C.Font.PixelsPerInch := 96;
    C.Caption := 'Name';
    C.Alignment := taLeftJustify;
    C.BiDiMode := bdRightToLeft;
    C.RenderTo(host.Canvas, Rect(0, 0, 200, 26), 96);
    shot := TBGRABitmap.Create(host);
    try
      ChannelSpanX(shot, chGreen, l, r);
      AssertTrue('the panel drew its caption', l >= 0);
      AssertTrue('a leading-aligned panel caption sits at the RIGHT edge when mirrored',
        r > 200 - 10);
      AssertTrue('and has left the left edge', l > 100);
    finally
      shot.Free;
    end;
  finally
    host.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

{ The group box's caption is not merely aligned inside a box: it carries an ERASE BAND that
  breaks the top border, and the band's x is computed separately from the text's. Probing the
  caption ink catches both, because the text rect is derived from the band's left edge --
  leave the band unmirrored and the caption comes back a whole width, not a few pixels. }
procedure TRtlCaptionTest.GroupBoxCaptionBandMovesToTheOtherEndOfTheFrame;
var
  Ctl: TTyStyleController;
  Form: TForm;
  C: TGroupBoxAccess;
  host: TBitmap;
  shot: TBGRABitmap;
  l, r: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  host := NewHost(200, 60);
  try
    Ctl.LoadThemeCss('TyGroupBox { background: #FFFFFF; color: #00FF00; border-width: 0px; padding: 0px; }');
    C := TGroupBoxAccess.Create(Form);
    C.Parent := Form;
    C.Controller := Ctl;
    C.Font.PixelsPerInch := 96;
    C.Caption := 'Options';
    C.Alignment := taLeftJustify;
    C.BiDiMode := bdRightToLeft;
    C.RenderTo(host.Canvas, Rect(0, 0, 200, 60), 96);
    shot := TBGRABitmap.Create(host);
    try
      ChannelSpanX(shot, chGreen, l, r);
      AssertTrue('the group box drew its caption', l >= 0);
      AssertTrue('the caption band moved to the right end of the frame', r > 200 - 20);
      AssertTrue('and vacated the left end', l > 100);
    finally
      shot.Free;
    end;
  finally
    host.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

{ Both halves of the button answer in one test, because the interesting fact about buttons
  is the negative one: taCenter is the default, taCenter is the fixed point, so mirroring a
  form full of ordinary buttons changes nothing at all. }
procedure TRtlCaptionTest.ButtonCaptionMovesButTheDefaultCentredOneDoesNot;
var
  Ctl: TTyStyleController;
  Form: TForm;
  C: TButtonAccess;
  host: TBitmap;
  shot: TBGRABitmap;
  cl, cr, ll, lr: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  try
    Ctl.LoadThemeCss('TyButton { background: #FFFFFF; color: #00FF00; border-width: 0px; padding: 0px; }');
    C := TButtonAccess.Create(Form);
    C.Parent := Form;
    C.Controller := Ctl;
    C.Font.PixelsPerInch := 96;
    C.Caption := 'OK';
    C.BiDiMode := bdRightToLeft;

    host := NewHost(200, 26);                    // default Alignment = taCenter
    try
      C.RenderTo(host.Canvas, Rect(0, 0, 200, 26), 96);
      shot := TBGRABitmap.Create(host);
      try
        ChannelSpanX(shot, chGreen, cl, cr);
      finally
        shot.Free;
      end;
    finally
      host.Free;
    end;
    AssertTrue('the centred button drew its caption', cl >= 0);
    AssertTrue('a centred caption stays centred when mirrored',
      (cl > 60) and (cr < 140));

    C.Alignment := taLeftJustify;
    host := NewHost(200, 26);
    try
      C.RenderTo(host.Canvas, Rect(0, 0, 200, 26), 96);
      shot := TBGRABitmap.Create(host);
      try
        ChannelSpanX(shot, chGreen, ll, lr);
      finally
        shot.Free;
      end;
    finally
      host.Free;
    end;
    AssertTrue('the aligned button drew its caption', ll >= 0);
    AssertTrue('an explicitly leading-aligned caption moves to the right', lr > 200 - 10);
  finally
    Form.Free;
    Ctl.Free;
  end;
end;

{ ---------------------------------------------------------- TRtlIndicatorTest }

{ Shared setup for the indicator probes: an accent-blue indicator on a white control, so the
  box is findable by colour and the caption is not. }
const
  cCheckCss =
    'TyCheckBox { background: #FFFFFF; color: #00FF00; border-width: 0px; padding: 0px; }' +
    'TyCheckBox:active { background: #0000FF; color: #FFFFFF; }' +
    'TyRadioButton { background: #FFFFFF; color: #00FF00; border-width: 0px; padding: 0px; }' +
    'TyRadioButton:active { background: #0000FF; color: #FFFFFF; }';

procedure TRtlIndicatorTest.CheckBoxIndicatorMovesToTheRightEdge;
var
  Ctl: TTyStyleController;
  Form: TForm;
  C: TCheckAccess;
  host: TBitmap;
  shot: TBGRABitmap;
  l, r: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  host := NewHost(120, 24);
  try
    Ctl.LoadThemeCss(cCheckCss);
    C := TCheckAccess.Create(Form);
    C.Parent := Form;
    C.Controller := Ctl;
    C.Font.PixelsPerInch := 96;
    C.Caption := '';
    C.Checked := True;
    C.BiDiMode := bdRightToLeft;
    C.RenderTo(host.Canvas, Rect(0, 0, 120, 24), 96);
    shot := TBGRABitmap.Create(host);
    try
      ChannelSpanX(shot, chBlue, l, r);
      AssertTrue('the indicator was drawn', l >= 0);
      AssertTrue('the check indicator sits against the RIGHT edge when mirrored',
        r > 120 - 4);
      AssertTrue('and is no longer at the left edge', l > 80);
    finally
      shot.Free;
    end;
  finally
    host.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

{ The caption must follow the indicator across, not stay behind it. "Hugged" is the property
  that makes the pair read as one control instead of two things at opposite ends of a row. }
procedure TRtlIndicatorTest.CheckBoxCaptionStaysHuggedToTheMirroredIndicator;
var
  Ctl: TTyStyleController;
  Form: TForm;
  C: TCheckAccess;
  host: TBitmap;
  shot: TBGRABitmap;
  boxL, boxR, capL, capR: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  host := NewHost(160, 24);
  try
    Ctl.LoadThemeCss(cCheckCss);
    C := TCheckAccess.Create(Form);
    C.Parent := Form;
    C.Controller := Ctl;
    C.Font.PixelsPerInch := 96;
    C.Caption := 'Enable';
    C.Checked := True;
    C.BiDiMode := bdRightToLeft;
    C.RenderTo(host.Canvas, Rect(0, 0, 160, 24), 96);
    shot := TBGRABitmap.Create(host);
    try
      ChannelSpanX(shot, chBlue, boxL, boxR);
      ChannelSpanX(shot, chGreen, capL, capR);
      AssertTrue('indicator and caption both drew', (boxL >= 0) and (capL >= 0));
      AssertTrue('the caption is on the indicator''s left when mirrored', capR < boxL);
      { Hugged, not merely on that side: the gap is the themed --checkbox-gap, a handful of
        pixels, so anything approaching half the control means the caption stayed put and
        only the box moved. }
      AssertTrue('the caption hugs the indicator rather than the far edge',
        boxL - capR < 24);
    finally
      shot.Free;
    end;
  finally
    host.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

procedure TRtlIndicatorTest.RadioButtonIndicatorMovesToTheRightEdge;
var
  Ctl: TTyStyleController;
  Form: TForm;
  C: TRadioAccess;
  host: TBitmap;
  shot: TBGRABitmap;
  l, r: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  host := NewHost(120, 24);
  try
    Ctl.LoadThemeCss(cCheckCss);
    C := TRadioAccess.Create(Form);
    C.Parent := Form;
    C.Controller := Ctl;
    C.Font.PixelsPerInch := 96;
    C.Caption := '';
    C.Checked := True;
    C.BiDiMode := bdRightToLeft;
    C.RenderTo(host.Canvas, Rect(0, 0, 120, 24), 96);
    shot := TBGRABitmap.Create(host);
    try
      ChannelSpanX(shot, chBlue, l, r);
      AssertTrue('the dot was drawn', l >= 0);
      AssertTrue('the radio indicator sits against the RIGHT edge when mirrored',
        r > 120 - 4);
      AssertTrue('and is no longer at the left edge', l > 80);
    finally
      shot.Free;
    end;
  finally
    host.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

{ THE design decision, made assertable.

  Alignment is a property the author can set, so mirroring had two possible meanings: flip
  the DEFAULT the author did not write, or OVERRIDE whatever they did write. This library
  takes the second, because LCL does (grids.pas:4006 flips a column's own alignment;
  checklst.pas:199 flips the indicator side unconditionally) and because the first is not
  expressible: TLeftRight has no "unset" member, so taRightJustify-because-it-is-the-default
  and taRightJustify-because-the-author-typed-it are the same value.

  So: an author who moved the indicator to the right in a left-to-right form gets it on the
  LEFT in a right-to-left one. Both ends of the switch flip. }
procedure TRtlIndicatorTest.ExplicitAlignmentIsOverriddenNotIgnored;
var
  Ctl: TTyStyleController;
  Form: TForm;
  C: TCheckAccess;
  host: TBitmap;
  shot: TBGRABitmap;
  l, r: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  host := NewHost(120, 24);
  try
    Ctl.LoadThemeCss(cCheckCss);
    C := TCheckAccess.Create(Form);
    C.Parent := Form;
    C.Controller := Ctl;
    C.Font.PixelsPerInch := 96;
    C.Caption := '';
    C.Checked := True;
    C.Alignment := taLeftJustify;   // "indicator on the RIGHT", in a left-to-right form
    C.BiDiMode := bdRightToLeft;
    C.RenderTo(host.Canvas, Rect(0, 0, 120, 24), 96);
    shot := TBGRABitmap.Create(host);
    try
      ChannelSpanX(shot, chBlue, l, r);
      AssertTrue('the indicator was drawn', l >= 0);
      AssertTrue('an explicitly right-side indicator mirrors to the LEFT', l < 4);
      AssertTrue('and has vacated the right edge', r < 40);
    finally
      shot.Free;
    end;
  finally
    host.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

{ Overriding happens per FRAME. The stored property is what the author wrote and what the
  streamer must write back out -- a mirroring pass that rewrote it would corrupt the .lfm the
  first time a right-to-left form was saved from the designer. }
procedure TRtlIndicatorTest.MirroringNeverRewritesTheStoredAlignment;
var
  Form: TForm;
  C: TCheckAccess;
  host: TBitmap;
begin
  Form := TForm.CreateNew(nil);
  host := NewHost(120, 24);
  try
    C := TCheckAccess.Create(Form);
    C.Parent := Form;
    C.Font.PixelsPerInch := 96;
    C.Alignment := taLeftJustify;
    C.BiDiMode := bdRightToLeft;
    C.RenderTo(host.Canvas, Rect(0, 0, 120, 24), 96);
    AssertTrue('Alignment still reads back what the author set',
      C.Alignment = taLeftJustify);
    C.BiDiMode := bdLeftToRight;
    C.RenderTo(host.Canvas, Rect(0, 0, 120, 24), 96);
    AssertTrue('and is unchanged after a left-to-right frame too',
      C.Alignment = taLeftJustify);
  finally
    host.Free;
    Form.Free;
  end;
end;

{ ----------------------------------------------------------- TRtlGeometryTest }

procedure TRtlGeometryTest.DividerCaptionAndRuleSwapEnds;
var
  ltr, rtl: TTyDividerLayout;
begin
  ltr := TyDividerLayout(200, 20, 40, taLeftJustify, TyDividerIndentAuto, 6, 4, 1, False);
  rtl := TyDividerLayout(200, 20, 40, taLeftJustify, TyDividerIndentAuto, 6, 4, 1, True);
  AssertEquals('left-to-right: caption starts at the left edge', 0, ltr.CaptionRect.Left);
  AssertEquals('left-to-right: the rule runs to the right edge', 200, ltr.RightRule.Right);
  AssertTrue('left-to-right: no left rule segment', ltr.LeftRule.Right <= ltr.LeftRule.Left);

  AssertEquals('mirrored: caption ends at the right edge', 200, rtl.CaptionRect.Right);
  AssertEquals('mirrored: caption is the same width', 40,
    rtl.CaptionRect.Right - rtl.CaptionRect.Left);
  AssertEquals('mirrored: the rule now runs from the left edge', 0, rtl.LeftRule.Left);
  AssertTrue('mirrored: no right rule segment', rtl.RightRule.Right <= rtl.RightRule.Left);
end;

{ LeftIndent keeps its name and changes its meaning to "from the reading start". Renaming it
  would break every .lfm that carries one, so the behaviour moves and the name does not --
  plans/2026-08-04-rtl-mirroring-scope.md §6.3 item 6. }
procedure TRtlGeometryTest.DividerIndentCountsFromTheReadingStart;
var
  rtl: TTyDividerLayout;
begin
  rtl := TyDividerLayout(200, 20, 40, taLeftJustify, 30, 6, 4, 1, True);
  AssertEquals('an indent of 30 leaves 30px between the caption and the RIGHT edge',
    170, rtl.CaptionRect.Right);
  AssertEquals('and the caption keeps its width', 40,
    rtl.CaptionRect.Right - rtl.CaptionRect.Left);
end;

{ A reflection of a flush layout is flush. Asserted rather than argued because the obvious
  alternative implementation -- flipping an index and re-running the arithmetic -- is exactly
  where a one-pixel seam or overlap appears, and a hairline seam in a divider is invisible in
  review and obvious on screen. }
procedure TRtlGeometryTest.DividerMirroringLeavesNoSeamBetweenCaptionAndRule;
var
  ltr, rtl: TTyDividerLayout;
begin
  ltr := TyDividerLayout(201, 20, 41, taCenter, TyDividerIndentAuto, 6, 4, 1, False);
  rtl := TyDividerLayout(201, 20, 41, taCenter, TyDividerIndentAuto, 6, 4, 1, True);
  { Odd width and odd caption on purpose: that is where the integer halving of taCenter
    puts the rounding, and where a reflection that is off by one shows up. }
  AssertEquals('the gap from the left rule to the caption is preserved',
    ltr.CaptionRect.Left - ltr.LeftRule.Right,
    rtl.CaptionRect.Left - rtl.LeftRule.Right);
  AssertEquals('the gap from the caption to the right rule is preserved',
    ltr.RightRule.Left - ltr.CaptionRect.Right,
    rtl.RightRule.Left - rtl.CaptionRect.Right);
  AssertEquals('both rule segments keep their lengths (left)',
    ltr.LeftRule.Right - ltr.LeftRule.Left, rtl.RightRule.Right - rtl.RightRule.Left);
  AssertEquals('both rule segments keep their lengths (right)',
    ltr.RightRule.Right - ltr.RightRule.Left, rtl.LeftRule.Right - rtl.LeftRule.Left);
end;

{ The captionless case returns its full-width rule in RightRule by a documented convention,
  and a full-width band is its own reflection -- so mirroring must leave that convention
  alone rather than shuffle the band into LeftRule for right-to-left dividers only. }
procedure TRtlGeometryTest.DividerWithNoCaptionKeepsItsFullWidthRuleInRightRule;
var
  rtl: TTyDividerLayout;
begin
  rtl := TyDividerLayout(200, 20, 0, taLeftJustify, TyDividerIndentAuto, 6, 4, 1, True);
  AssertEquals('the full-width rule still arrives in RightRule (left)', 0, rtl.RightRule.Left);
  AssertEquals('the full-width rule still arrives in RightRule (right)', 200, rtl.RightRule.Right);
  AssertTrue('LeftRule stays empty', rtl.LeftRule.Right <= rtl.LeftRule.Left);
end;

procedure TRtlGeometryTest.CheckGroupColumnsFillFromTheRight;
var
  c0, c1: TRect;
begin
  { 4 items, 2 columns, row-major: items 0 and 1 share the first row. }
  c0 := TyCheckGroupCellRect(Rect(0, 0, 200, 100), 4, 2, 0, 24, clHorizontalThenVertical, True);
  c1 := TyCheckGroupCellRect(Rect(0, 0, 200, 100), 4, 2, 1, 24, clHorizontalThenVertical, True);
  AssertEquals('item 0 takes the RIGHTMOST column', 200, c0.Right);
  AssertEquals('item 1 follows it leftwards', 0, c1.Left);
  AssertTrue('item 1 is entirely left of item 0', c1.Right <= c0.Left);
  AssertEquals('rows are not mirrored -- item 0 is still on the first row', c0.Top, c1.Top);
end;

procedure TRtlGeometryTest.RadioGroupColumnsFillFromTheRight;
var
  c0, c1: TRect;
begin
  c0 := TyRadioGroupCellRect(Rect(0, 0, 200, 100), 4, 2, 0, 22, clHorizontalThenVertical, True);
  c1 := TyRadioGroupCellRect(Rect(0, 0, 200, 100), 4, 2, 1, 22, clHorizontalThenVertical, True);
  AssertEquals('item 0 takes the RIGHTMOST column', 200, c0.Right);
  AssertEquals('item 1 follows it leftwards', 0, c1.Left);
  AssertTrue('item 1 is entirely left of item 0', c1.Right <= c0.Left);
  AssertEquals('rows are not mirrored', c0.Top, c1.Top);
end;

{ The remainder-absorbing last column exists so the cells tile [Left, Right) with no gap and
  no overlap. A mirrored layout owes the same guarantee, and an odd width is where it would
  be lost. }
procedure TRtlGeometryTest.MirroredColumnsStillTileTheClientRectFlush;
var
  i: Integer;
  cell, prev: TRect;
begin
  prev := Rect(0, 0, 0, 0);
  for i := 0 to 2 do
  begin
    cell := TyCheckGroupCellRect(Rect(0, 0, 101, 100), 3, 3, i, 24, clHorizontalThenVertical, True);
    if i = 0 then
      AssertEquals('the first item reaches the right edge', 101, cell.Right)
    else
      AssertEquals('each cell starts exactly where the previous one ended',
        prev.Left, cell.Right);
    prev := cell;
  end;
  AssertEquals('the last item reaches the left edge', 0, prev.Left);
end;

procedure TRtlGeometryTest.BadgeCornerFlipsHorizontallyAndNotVertically;
begin
  AssertTrue('unflipped is the identity',
    TyBidiFlipBadgePosition(bpBottomRight, False) = bpBottomRight);
  AssertTrue('the default trailing corner becomes bottom-left',
    TyBidiFlipBadgePosition(bpBottomRight, True) = bpBottomLeft);
  AssertTrue('and back again',
    TyBidiFlipBadgePosition(bpBottomLeft, True) = bpBottomRight);
  AssertTrue('the top pair flips the same way',
    TyBidiFlipBadgePosition(bpTopLeft, True) = bpTopRight);
  AssertTrue('top stays top',
    TyBidiFlipBadgePosition(bpTopRight, True) = bpTopLeft);
end;

procedure TRtlGeometryTest.GlyphLayoutFlipsTheSidePairAndNotTheStackedPair;
begin
  AssertTrue('unflipped is the identity', TyBidiFlipGlyphLayout(glLeft, False) = glLeft);
  AssertTrue('glyph-left becomes glyph-right', TyBidiFlipGlyphLayout(glLeft, True) = glRight);
  AssertTrue('and back again', TyBidiFlipGlyphLayout(glRight, True) = glLeft);
  AssertTrue('glyph-top is unaffected -- up is not a reading direction',
    TyBidiFlipGlyphLayout(glTop, True) = glTop);
  AssertTrue('nor is glyph-bottom', TyBidiFlipGlyphLayout(glBottom, True) = glBottom);
end;

{ -------------------------------------------------------------- TRtlGroupTest }

{ The groups lean on LCL propagating BiDiMode down to children that have ParentBiDiMode on,
  because that is what makes each hosted check box flip its OWN indicator without the group
  reaching inside it. If this ever stopped holding, the columns would reverse and every
  indicator would stay on the left -- so it is asserted, not assumed. }
procedure TRtlGroupTest.RadioGroupChildrenInheritTheGroupsDirection;
var
  Form: TForm;
  G: TTyRadioGroup;
begin
  Form := TForm.CreateNew(nil);
  try
    G := TTyRadioGroup.Create(Form);
    G.Parent := Form;
    G.Items.Add('A');
    G.Items.Add('B');
    G.BiDiMode := bdRightToLeft;
    AssertTrue('the group reads right-to-left', G.IsRightToLeft);
    AssertTrue('and so does its first child', G.Buttons[0].IsRightToLeft);
    AssertTrue('and its second', G.Buttons[1].IsRightToLeft);
  finally
    Form.Free;
  end;
end;

procedure TRtlGroupTest.RadioGroupChildrenAreLaidOutRightToLeft;
var
  Form: TForm;
  G: TTyRadioGroup;
begin
  Form := TForm.CreateNew(nil);
  try
    G := TTyRadioGroup.Create(Form);
    G.Parent := Form;
    G.SetBounds(0, 0, 200, 120);
    G.Columns := 2;
    G.Items.Add('A');
    G.Items.Add('B');
    G.BiDiMode := bdRightToLeft;
    AssertTrue('item 0 sits in the right half', G.Buttons[0].Left > 80);
    AssertTrue('item 1 sits to its left', G.Buttons[1].Left < G.Buttons[0].Left);
  finally
    Form.Free;
  end;
end;

procedure TRtlGroupTest.CheckGroupChildrenAreLaidOutRightToLeft;
var
  Form: TForm;
  G: TTyCheckGroup;
  a, b: TTyCheckBox;
begin
  Form := TForm.CreateNew(nil);
  try
    G := TTyCheckGroup.Create(Form);
    G.Parent := Form;
    G.SetBounds(0, 0, 200, 120);
    G.Columns := 2;
    G.Items.Add('A');
    G.Items.Add('B');
    G.BiDiMode := bdRightToLeft;
    a := G.Buttons[0];
    b := G.Buttons[1];
    AssertTrue('both hosted boxes exist', (a <> nil) and (b <> nil));
    AssertTrue('item 0 sits in the right half', a.Left > 80);
    AssertTrue('item 1 sits to its left', b.Left < a.Left);
    AssertTrue('and each hosted box reads right-to-left itself', a.IsRightToLeft);
  finally
    Form.Free;
  end;
end;

{ The keyboard half, and the one most likely to be left behind: every instance of this bug
  is a single missing minus sign, invisible in review, and it makes the left arrow walk the
  selection backwards for exactly the users who cannot tell you why. }
procedure TRtlGroupTest.ArrowKeysFollowTheMirroredColumnsNotTheScreenEdges;
var
  Form: TForm;
  G: TTyRadioGroup;
begin
  Form := TForm.CreateNew(nil);
  try
    G := TTyRadioGroup.Create(Form);
    G.Parent := Form;
    G.SetBounds(0, 0, 200, 120);
    G.Columns := 2;
    G.Items.Add('A');
    G.Items.Add('B');
    G.ItemIndex := 0;
    G.BiDiMode := bdRightToLeft;
    { Item 0 is on the right, item 1 to its left. The LEFT arrow must therefore move
      FORWARD, to item 1 -- the direction the eye travels, not the direction x grows. }
    PressArrow(G, G.Buttons[0], VK_LEFT);
    AssertEquals('the left arrow steps towards the next item when mirrored', 1, G.ItemIndex);
    PressArrow(G, G.Buttons[1], VK_RIGHT);
    AssertEquals('and the right arrow steps back', 0, G.ItemIndex);
  finally
    Form.Free;
  end;
end;

{ Only the horizontal axis has a reading direction. Mirroring the vertical one would be the
  same class of error as mirroring Home/End. }
procedure TRtlGroupTest.VerticalArrowKeysAreUntouchedByMirroring;
var
  Form: TForm;
  G: TTyRadioGroup;
begin
  Form := TForm.CreateNew(nil);
  try
    G := TTyRadioGroup.Create(Form);
    G.Parent := Form;
    G.SetBounds(0, 0, 200, 120);
    G.Columns := 1;
    G.Items.Add('A');
    G.Items.Add('B');
    G.ItemIndex := 0;
    G.BiDiMode := bdRightToLeft;
    PressArrow(G, G.Buttons[0], VK_DOWN);
    AssertEquals('down still means down', 1, G.ItemIndex);
    PressArrow(G, G.Buttons[1], VK_UP);
    AssertEquals('and up still means up', 0, G.ItemIndex);
  finally
    Form.Free;
  end;
end;

{ --------------------------------------------------------- TRtlButtonSlotTest }

{ No glyph FAMILY is installed in a headless run, so the icon itself renders as an empty
  transparent square -- but the SPLIT still happens, and the caption lands in whatever is
  left. So the caption's position is the readable evidence that the glyph slot changed
  sides. }
procedure TRtlButtonSlotTest.GlyphButtonCaptionMovesToTheOtherSideOfTheIcon;
var
  Ctl: TTyStyleController;
  Form: TForm;
  B: TGlyphBtnAccess;
  F: TTyIconFont;
  host: TBitmap;
  shot: TBGRABitmap;
  ltrL, ltrR, rtlL, rtlR: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  F := TTyIconFont.Create(nil);
  try
    Ctl.LoadThemeCss('TyButton { background: #FFFFFF; color: #00FF00; border-width: 0px; padding: 0px; }');
    F.MapGlyph('save', $F0C7);
    B := TGlyphBtnAccess.Create(Form);
    B.Parent := Form;
    B.Controller := Ctl;
    B.Font.PixelsPerInch := 96;
    B.IconFont := F;
    B.GlyphName := 'save';
    B.Caption := 'Save';
    B.GlyphSize := 16;
    B.GlyphLayout := glLeft;

    host := NewHost(160, 26);
    try
      B.RenderTo(host.Canvas, Rect(0, 0, 160, 26), 96);
      shot := TBGRABitmap.Create(host);
      try
        ChannelSpanX(shot, chGreen, ltrL, ltrR);
      finally
        shot.Free;
      end;
    finally
      host.Free;
    end;

    B.BiDiMode := bdRightToLeft;
    host := NewHost(160, 26);
    try
      B.RenderTo(host.Canvas, Rect(0, 0, 160, 26), 96);
      shot := TBGRABitmap.Create(host);
      try
        ChannelSpanX(shot, chGreen, rtlL, rtlR);
      finally
        shot.Free;
      end;
    finally
      host.Free;
    end;

    AssertTrue('the caption drew both ways', (ltrL >= 0) and (rtlL >= 0));
    AssertTrue('a glyph-left button puts its caption right of the icon slot', ltrL >= 16);
    AssertTrue('mirrored, the icon slot moves right and the caption follows it left',
      rtlL < ltrL);
    AssertTrue('and the caption now clears the icon slot on the other side',
      rtlR <= 160 - 16);
  finally
    F.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

procedure TRtlButtonSlotTest.ColorButtonSwatchMovesToTheRightEdge;
var
  Ctl: TTyStyleController;
  Form: TForm;
  B: TColorBtnAccess;
  host: TBitmap;
  shot: TBGRABitmap;
  l, r, capL, capR: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  host := NewHost(160, 26);
  try
    Ctl.LoadThemeCss('TyButton { background: #FFFFFF; color: #00FF00; border-width: 0px; padding: 0px; }');
    B := TColorBtnAccess.Create(Form);
    B.Parent := Form;
    B.Controller := Ctl;
    B.Font.PixelsPerInch := 96;
    B.Caption := 'Colour';
    B.SelectedColor := TyRGBA(255, 0, 0, 255);
    B.BiDiMode := bdRightToLeft;
    B.RenderTo(host.Canvas, Rect(0, 0, 160, 26), 96);
    shot := TBGRABitmap.Create(host);
    try
      ChannelSpanX(shot, chRed, l, r);
      ChannelSpanX(shot, chGreen, capL, capR);
      AssertTrue('the swatch was drawn', l >= 0);
      AssertTrue('the swatch sits against the RIGHT edge when mirrored', r > 160 - 6);
      AssertTrue('and has vacated the left edge', l > 100);
      { The caption is asserted separately from the swatch on purpose: the swatch rect and
        the caption rect are two expressions, and moving one without the other leaves the
        caption in a rect that starts past the right edge -- which draws NOTHING at all, and
        would pass a test that only ever looked at the swatch. }
      AssertTrue('the caption was drawn', capL >= 0);
      AssertTrue('the caption moved to the swatch''s left', capR < l);
    finally
      shot.Free;
    end;
  finally
    host.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

{ The badge names a corner, and a corner has a reading-order meaning: bpBottomRight is "the
  trailing corner", which is bottom-LEFT on a mirrored button. Rendered rather than only
  table-tested, because a lookup nobody calls is not a behaviour. }
procedure TRtlButtonSlotTest.BadgeMovesToTheTrailingCornerWhichIsBottomLeftWhenMirrored;
var
  Ctl: TTyStyleController;
  Form: TForm;
  B: TButtonAccess;
  host: TBitmap;
  shot: TBGRABitmap;
  l, r: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  host := NewHost(160, 40);
  try
    Ctl.LoadThemeCss(
      'TyButton { background: #FFFFFF; color: #101010; border-width: 0px; padding: 0px; }' +
      'TyBadge { background: #E01B24; color: #FFFFFF; padding: 0px 4px; }');
    B := TButtonAccess.Create(Form);
    B.Parent := Form;
    B.Controller := Ctl;
    B.Font.PixelsPerInch := 96;
    B.Caption := '';
    B.ShowBadge := True;
    B.BadgeValue := 7;
    B.BiDiMode := bdRightToLeft;
    B.RenderTo(host.Canvas, Rect(0, 0, 160, 40), 96);
    shot := TBGRABitmap.Create(host);
    try
      ChannelSpanX(shot, chRed, l, r);
      AssertTrue('the badge was drawn', l >= 0);
      AssertTrue('the default trailing corner is the LEFT one when mirrored', l < 8);
      AssertTrue('and the badge has vacated the right corner', r < 80);
    finally
      shot.Free;
    end;
  finally
    host.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

{ ------------------------------------------------------------- TRtlHeaderTest }

{ One fixture for every header probe. Red is the ink (caption AND sort triangle both take
  the resolved text colour), green is the divider, white is everything else -- so a red-channel
  span finds the section's CONTENT and nothing structural. Both type keys are defined because
  the strip resolves its frame from 'TyHeaderControl' and each section from
  'TyTreeHeaderSection', and a section style with no colour of its own would silently fall
  back to the strip's. }
const
  cHdrCss =
    'TyHeaderControl { background: #FFFFFF; color: #FF0000; border-width: 0px; border-color: #00FF00; }' +
    'TyTreeHeaderSection { background: #FFFFFF; color: #FF0000; border-width: 0px; }';

  { The widths every geometry probe below tiles: 60+70+40 = 170 in a 300px client, so the
    LAST section is also the ABSORBER and takes the 130px remainder. Mirroring has to move a
    section whose painted width is not its set width, which is the case a symmetric example
    would not have caught. }
  cHdrClient: TRect = (Left: 0; Top: 0; Right: 300; Bottom: 26);

procedure TRtlHeaderTest.SectionsTileFromTheRightEdgeWhenMirrored;
var
  r: TTyHeaderRectArray;
begin
  r := TyHeaderSectionRects([60, 70, 40], cHdrClient, True);
  AssertEquals('three rects either way', 3, Length(r));
  AssertEquals('section 0 starts 60px in from the RIGHT edge', 240, r[0].Left);
  AssertEquals('and ends on it', 300, r[0].Right);
  AssertEquals('section 1 sits to its left', 170, r[1].Left);
  AssertEquals('section 1 right', 240, r[1].Right);
  AssertEquals('the absorbing section 2 takes the rest, at the far left', 0, r[2].Left);
  AssertEquals('section 2 right', 170, r[2].Right);
  { Vertical is untouched: mirroring is a horizontal reflection, and a control that also
    flipped top/bottom would still pass every x assertion above. }
  AssertEquals('top comes from the client, unmirrored', 0, r[1].Top);
  AssertEquals('bottom likewise', 26, r[1].Bottom);
end;

procedure TRtlHeaderTest.MirroredTilingIsGaplessAndFlushToBothClientEdges;
var
  r: TTyHeaderRectArray;
  i: Integer;
begin
  r := TyHeaderSectionRects([60, 70, 40], cHdrClient, True);
  AssertEquals('the first section is flush with the client''s right edge',
    cHdrClient.Right, r[0].Right);
  AssertEquals('the last is flush with its left edge', cHdrClient.Left, r[High(r)].Left);
  { A one-pixel seam between two sections is a hairline of background showing through a strip
    that is meant to be solid, and it is invisible in a screenshot at 100%. Assert it away. }
  for i := 1 to High(r) do
    AssertEquals(Format('no seam between mirrored sections %d and %d', [i - 1, i]),
      r[i - 1].Left, r[i].Right);
end;

procedure TRtlHeaderTest.MirroredTilingIsARectForRectReflectionOfTheLtrOne;
var
  ltr, rtl: TTyHeaderRectArray;
  i: Integer;
begin
  ltr := TyHeaderSectionRects([60, 70, 40], cHdrClient);
  rtl := TyHeaderSectionRects([60, 70, 40], cHdrClient, True);
  { The strongest statement available about the implementation: the mirrored tiling is the
    LTR one reflected, not a second tiling derived by running the loop backwards. A reverse
    accumulation could produce the rects above and still round its remainder differently, or
    drift by one at a boundary; a reflection cannot, because there is only one tiling. }
  for i := 0 to High(ltr) do
  begin
    AssertEquals(Format('section %d left is the reflection of its LTR right', [i]),
      cHdrClient.Left + cHdrClient.Right - ltr[i].Right, rtl[i].Left);
    AssertEquals(Format('section %d right is the reflection of its LTR left', [i]),
      cHdrClient.Left + cHdrClient.Right - ltr[i].Left, rtl[i].Right);
  end;
end;

procedure TRtlHeaderTest.MirroringPreservesEverySectionsPaintedWidthAbsorberIncluded;
var
  ltr, rtl: TTyHeaderRectArray;
  i: Integer;
begin
  ltr := TyHeaderSectionRects([60, 70, 40], cHdrClient);
  rtl := TyHeaderSectionRects([60, 70, 40], cHdrClient, True);
  for i := 0 to High(ltr) do
    AssertEquals(Format('section %d keeps its painted width when mirrored', [i]),
      ltr[i].Right - ltr[i].Left, rtl[i].Right - rtl[i].Left);
  { Named separately because it is the one that would break first: the remainder is computed
    from a running x, and a mirroring that re-ran the accumulation would hand it to whichever
    section it reached last rather than to the absorber. }
  AssertEquals('the absorber still absorbs', 170, rtl[2].Right - rtl[2].Left);
end;

procedure TRtlHeaderTest.AnOverfullMirroredStripOverrunsTheLeftEdgeNotTheRight;
var
  r: TTyHeaderRectArray;
begin
  // 200+150 = 350 in a 300px client: nothing absorbs, and the surplus has to go somewhere.
  r := TyHeaderSectionRects([200, 150], cHdrClient, True);
  AssertEquals('section 0 still starts at the right edge', 300, r[0].Right);
  AssertEquals('and keeps its own 200', 100, r[0].Left);
  AssertEquals('section 1 keeps its own 150 too', 100, r[1].Right);
  AssertTrue('the overrun leaves by the LEFT edge, which is where reading ends',
    r[1].Left < cHdrClient.Left);
end;

procedure TRtlHeaderTest.HitTestAgreesWithThePaintedTilingAtEveryPixel;
var
  r: TTyHeaderRectArray;
  x, i, owner: Integer;
begin
  { The guard this control exists to make possible. It asserts no coordinates of its own:
    for every device x it asks which section the PAINT covers that pixel with, then asks the
    HIT TEST, and requires the same answer. A mirroring that moved one and not the other --
    the defect in TTyShape, TTyTreeView.GetNodeAt and the date picker -- is red here on the
    very first pixel, and no future change to the tiling can make it stale. }
  r := TyHeaderSectionRects([60, 70, 40], cHdrClient, True);
  for x := cHdrClient.Left to cHdrClient.Right - 1 do
  begin
    owner := -1;
    for i := 0 to High(r) do
      if (x >= r[i].Left) and (x < r[i].Right) then owner := i;
    AssertEquals(Format('x=%d must hit the section painted there', [x]),
      owner, TyHeaderSectionAtX([60, 70, 40], cHdrClient, x, True));
  end;
  { And the contrast, so this cannot pass by mirroring nothing at all: the leftmost pixel
    belongs to opposite ends of the section list in the two directions. }
  AssertEquals('mirrored, the leftmost pixel is the LAST section',
    2, TyHeaderSectionAtX([60, 70, 40], cHdrClient, 0, True));
  AssertEquals('unmirrored it is still the first',
    0, TyHeaderSectionAtX([60, 70, 40], cHdrClient, 0));
end;

procedure TRtlHeaderTest.TheStripsOuterEdgeBelongsToWhicheverSectionIsAgainstIt;
begin
  { x == the client's right edge is outside every half-open span, and the strip claims it
    anyway so a section is never one pixel short of its own border. WHICH section that is
    depends on the direction: the last index when the tiling runs rightward, the first when
    it runs leftward. }
  AssertEquals('unmirrored, the right edge belongs to the last section',
    2, TyHeaderSectionAtX([60, 70, 40], cHdrClient, 300));
  AssertEquals('mirrored, it belongs to the first',
    0, TyHeaderSectionAtX([60, 70, 40], cHdrClient, 300, True));
end;

procedure TRtlHeaderTest.ResizeGripGrabsTheMirroredBoundaryAndNotTheLtrOne;
begin
  { Mirrored spans: [240,300) [170,240) [0,170). A section's grabbable boundary is the one it
    shares with its SUCCESSOR, which is its left edge here -- 240 for section 0, 170 for 1. }
  AssertEquals('exactly on section 0''s mirrored boundary', 0,
    TyHeaderResizeEdgeAtX([60, 70, 40], cHdrClient, 240, 4, True));
  AssertEquals('within the grip of it', 0,
    TyHeaderResizeEdgeAtX([60, 70, 40], cHdrClient, 242, 4, True));
  AssertEquals('section 1''s mirrored boundary', 1,
    TyHeaderResizeEdgeAtX([60, 70, 40], cHdrClient, 172, 4, True));
  AssertEquals('mid-cell grabs nothing', -1,
    TyHeaderResizeEdgeAtX([60, 70, 40], cHdrClient, 200, 4, True));
  { The failure mode with teeth: a strip that paints mirrored but still offers its LTR grips
    puts a resize cursor over blank cell middles and none over the dividers the user sees. }
  AssertEquals('the LTR boundary at x=60 is no longer a boundary', -1,
    TyHeaderResizeEdgeAtX([60, 70, 40], cHdrClient, 60, 4, True));
  AssertEquals('nor is the LTR one at x=130', -1,
    TyHeaderResizeEdgeAtX([60, 70, 40], cHdrClient, 130, 4, True));
end;

procedure TRtlHeaderTest.NeitherOuterEdgeIsAResizeBoundaryWhenMirrored;
begin
  { The strip's own edges are the control's, not a divider: dragging one would resize the
    strip's outermost section against nothing. Mirroring moves which physical edge that is,
    so both have to be checked -- the left one is the new "last section's outer edge". }
  AssertEquals('the right edge is the control''s', -1,
    TyHeaderResizeEdgeAtX([60, 70, 40], cHdrClient, 300, 4, True));
  AssertEquals('and so is the left', -1,
    TyHeaderResizeEdgeAtX([60, 70, 40], cHdrClient, 0, 4, True));
end;

procedure TRtlHeaderTest.SortTriangleMovesToTheCellsLeftGutterWhenMirrored;
var
  cell: TRect;
  ltr, rtl: TTyHeaderTriangle;
begin
  cell := Rect(100, 0, 200, 26);
  ltr := TyHeaderSortTriangle(cell, hsdAscending, 8);
  rtl := TyHeaderSortTriangle(cell, hsdAscending, 8, True);
  AssertTrue('unmirrored the glyph sits in the cell''s right gutter',
    ltr[2].X > (cell.Left + cell.Right) div 2);
  AssertTrue('mirrored it sits in the LEFT one',
    rtl[2].X < (cell.Left + cell.Right) div 2);
  { Reflected, not merely "somewhere on the other side": the gutter has to be the same width
    on both, or a sorted column's caption gets a different amount of room in each direction. }
  AssertEquals('the mirrored apex is the reflection of the unmirrored one',
    cell.Left + cell.Right - ltr[2].X, rtl[2].X);
end;

procedure TRtlHeaderTest.SortTriangleMirrorsHorizontallyAndNotVertically;
var
  cell: TRect;
  asc, desc: TTyHeaderTriangle;
begin
  { Ascending must still point UP in a mirrored strip. Sort direction is not a reading
    direction, and a reflection applied to the wrong axis would turn every ▲ into a ▼ --
    a wrong answer that still looks like a deliberate glyph. }
  cell := Rect(100, 0, 200, 26);
  asc  := TyHeaderSortTriangle(cell, hsdAscending, 8, True);
  desc := TyHeaderSortTriangle(cell, hsdDescending, 8, True);
  AssertTrue('mirrored ascending still points up', asc[2].Y < asc[0].Y);
  AssertTrue('mirrored descending still points down', desc[2].Y > desc[0].Y);
  AssertEquals('and the Y coordinates are the unmirrored ones',
    TyHeaderSortTriangle(cell, hsdAscending, 8)[2].Y, asc[2].Y);
end;

procedure TRtlHeaderTest.MirroredStripSortsTheSectionUnderTheClickNotItsLtrTwin;
var
  Form: TForm;
  H: THdrAccess;
begin
  Form := TForm.CreateNew(nil);
  try
    H := THdrAccess.Create(Form);
    H.Parent := Form;
    H.Font.PixelsPerInch := 96;
    H.SetBounds(0, 0, 300, 26);
    H.AddSection('A', 60);
    H.AddSection('B', 70);
    H.AddSection('C', 40);
    H.BiDiMode := bdRightToLeft;
    { x=20 is deep inside the LEFTMOST painted cell, which mirrored is section 2. In an
      unmirrored strip the same click lands on section 0 -- so this one assertion separates
      "mirrored" from "mirrored in paint only". }
    H.PressDown(20);
    H.PressUp(20);
    AssertTrue('the click sorted the section painted under it',
      H.Sort[2] = hsdAscending);
    AssertTrue('and left section 0, its unmirrored twin, alone',
      H.Sort[0] = hsdNone);
    { The other end, so a hit test that simply reversed every index would not pass either. }
    H.PressDown(290);
    H.PressUp(290);
    AssertTrue('a click at the right edge sorts section 0', H.Sort[0] = hsdAscending);
  finally
    Form.Free;
  end;
end;

procedure TRtlHeaderTest.DraggingAMirroredBoundaryAwayFromTheReadingStartWidensTheSection;
var
  Form: TForm;
  H: THdrAccess;
begin
  Form := TForm.CreateNew(nil);
  try
    H := THdrAccess.Create(Form);
    H.Parent := Form;
    H.Font.PixelsPerInch := 96;
    H.SetBounds(0, 0, 300, 26);
    H.AddSection('A', 60);
    H.AddSection('B', 70);
    H.AddSection('C', 40);
    H.BiDiMode := bdRightToLeft;
    { Section 0 is pinned to the right edge and grows LEFTWARD, so the drag delta's sign is
      inverted along with the tiling. Leave that behind and the divider runs away from the
      pointer at twice the speed -- the strip still resizes, so nothing crashes and nothing
      is obviously wrong until someone tries to use it. }
    H.PressDown(240);
    H.PressMove(220);
    AssertEquals('dragging the boundary away from the right edge widens the section',
      80, H.SectionWidth[0]);
    H.PressMove(250);
    AssertEquals('and dragging it back toward that edge narrows it',
      50, H.SectionWidth[0]);
    H.PressUp(250);
  finally
    Form.Free;
  end;
end;

procedure TRtlHeaderTest.EffectiveSectionWidthIsUnchangedByMirroring;
var
  Form: TForm;
  H: THdrAccess;
  i, before: Integer;
begin
  { The fourth consumer of the tiling, and the one that reads only a WIDTH out of it. A
    reflection preserves widths, so the right answer is "no change" -- which is exactly why
    it needs a guard: it is the consumer whose breakage would be silent. }
  Form := TForm.CreateNew(nil);
  try
    H := THdrAccess.Create(Form);
    H.Parent := Form;
    H.Font.PixelsPerInch := 96;
    H.SetBounds(0, 0, 300, 26);
    H.AddSection('A', 60);
    H.AddSection('B', 70);
    H.AddSection('C', 40);
    for i := 0 to 2 do
    begin
      before := H.EffectiveSectionWidth[i];
      H.BiDiMode := bdRightToLeft;
      AssertEquals(Format('section %d''s painted width survives mirroring', [i]),
        before, H.EffectiveSectionWidth[i]);
      H.BiDiMode := bdLeftToRight;
    end;
    AssertEquals('and the absorber is still the one that grew', 170, H.EffectiveSectionWidth[2]);
  finally
    Form.Free;
  end;
end;

procedure TRtlHeaderTest.MirroredCaptionRendersAgainstTheRightEdgeOfItsCell;
var
  Ctl: TTyStyleController;
  Form: TForm;
  H: THdrAccess;
  host: TBitmap;
  shot: TBGRABitmap;
  l, r: Integer;
begin
  { ONE section spanning the whole strip, so the tiling is its own mirror and the only thing
    left to move is the caption inside it. That isolates the painter opt-in (BeginPaint's
    ARightToLeft) from the geometry: this test fails if the strip never armed the painter,
    and passes unchanged whatever the tiling does. }
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  host := NewHost(300, 26);
  try
    Ctl.LoadThemeCss(cHdrCss);
    H := THdrAccess.Create(Form);
    H.Parent := Form;
    H.Controller := Ctl;
    H.Font.PixelsPerInch := 96;
    H.SetBounds(0, 0, 300, 26);
    H.AddSection('Name', 300);
    H.BiDiMode := bdRightToLeft;
    H.RenderTo(host.Canvas, Rect(0, 0, 300, 26), 96);
    shot := TBGRABitmap.Create(host);
    try
      ChannelSpanX(shot, chRed, l, r);
      AssertTrue('the strip drew its caption', l >= 0);
      AssertTrue('a leading-aligned caption sits against the cell''s RIGHT edge when mirrored',
        r > 300 - 12);
      AssertTrue('and has left the left edge', l > 150);
    finally
      shot.Free;
    end;
  finally
    host.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

procedure TRtlHeaderTest.SortTriangleIsPaintedInTheMirroredCellsLeftGutter;
var
  Ctl: TTyStyleController;
  Form: TForm;
  H: THdrAccess;
  host: TBitmap;
  shot: TBGRABitmap;
  l, r: Integer;
begin
  { Captions are blank on purpose: the triangle is drawn in the same resolved text colour, so
    the red span IS the triangle and nothing else. Section 0 is the sorted one, which mirrored
    is painted at [240,300) -- so this pins the tiling and the gutter side TOGETHER, which is
    the pair a paint-only mirroring would get half right. }
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  host := NewHost(300, 26);
  try
    Ctl.LoadThemeCss(cHdrCss);
    H := THdrAccess.Create(Form);
    H.Parent := Form;
    H.Controller := Ctl;
    H.Font.PixelsPerInch := 96;
    H.SetBounds(0, 0, 300, 26);
    H.AddSection('', 60);
    H.AddSection('', 70);
    H.AddSection('', 40);
    H.Sort[0] := hsdAscending;
    H.BiDiMode := bdRightToLeft;
    H.RenderTo(host.Canvas, Rect(0, 0, 300, 26), 96);
    shot := TBGRABitmap.Create(host);
    try
      ChannelSpanX(shot, chRed, l, r);
      AssertTrue('the sort triangle was drawn', l >= 0);
      AssertTrue('it is inside section 0''s mirrored cell, which starts at x=240', l >= 240);
      AssertTrue('and in that cell''s LEFT gutter, not against the strip edge', r < 270);
    finally
      shot.Free;
    end;
  finally
    host.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

procedure TRtlHeaderTest.MirroredSortGutterIsReservedOnTheSideTheTriangleMovedTo;
var
  Ctl: TTyStyleController;
  Form: TForm;
  H: THdrAccess;
  host: TBitmap;
  shot: TBGRABitmap;
  l, r: Integer;
begin
  { The caption slot and the triangle have to move TOGETHER. Reserving the gutter on the
    right while painting the glyph on the left is the failure this pins: the strip looks
    almost right -- triangle in the correct corner, caption on the correct side -- and the
    caption is simply short of its edge by the width of a gutter that is not there, sitting
    on top of the triangle at the other end once the text is long enough.

    One full-width sorted section, so the tiling is its own mirror and the only thing under
    test is where the gutter went. }
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  host := NewHost(300, 26);
  try
    Ctl.LoadThemeCss(cHdrCss);
    H := THdrAccess.Create(Form);
    H.Parent := Form;
    H.Controller := Ctl;
    H.Font.PixelsPerInch := 96;
    H.SetBounds(0, 0, 300, 26);
    H.AddSection('Name', 300);
    H.Sort[0] := hsdAscending;
    H.BiDiMode := bdRightToLeft;
    H.RenderTo(host.Canvas, Rect(0, 0, 300, 26), 96);
    shot := TBGRABitmap.Create(host);
    try
      { Caption and triangle share the resolved text colour, so the span runs from the
        triangle at the far left to the caption's right edge. }
      ChannelSpanX(shot, chRed, l, r);
      AssertTrue('the strip drew something', l >= 0);
      AssertTrue('the triangle took the left gutter', l < 20);
      AssertTrue('and the caption still reaches its own right edge, the gutter having gone '
        + 'with the triangle', r > 285);
    finally
      shot.Free;
    end;
  finally
    host.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

procedure TRtlHeaderTest.MirroredDividerIsDrawnOnTheEdgeTheResizeGripGrabs;
var
  Ctl: TTyStyleController;
  Form: TForm;
  H: THdrAccess;
  host: TBitmap;
  shot: TBGRABitmap;

  procedure Shoot(ARtl: Boolean);
  begin
    if ARtl then H.BiDiMode := bdRightToLeft else H.BiDiMode := bdLeftToRight;
    host.Canvas.Brush.Color := clWhite;
    host.Canvas.FillRect(0, 0, 300, 26);
    H.RenderTo(host.Canvas, Rect(0, 0, 300, 26), 96);
    FreeAndNil(shot);
    shot := TBGRABitmap.Create(host);
  end;

begin
  { A divider the user can see but cannot grab, and a grip over blank cell middle, is the
    same paint/hit-test split this control was chosen to avoid -- it just shows up in the
    cursor rather than in the click. TyHeaderResizeEdgeAtX reads its boundary off rects[i]
    and so does this, so the assertion below is the pixel half of
    ResizeGripGrabsTheMirroredBoundaryAndNotTheLtrOne. }
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  host := NewHost(300, 26);
  shot := nil;
  try
    Ctl.LoadThemeCss(cHdrCss);
    H := THdrAccess.Create(Form);
    H.Parent := Form;
    H.Controller := Ctl;
    H.Font.PixelsPerInch := 96;
    H.SetBounds(0, 0, 300, 26);
    H.AddSection('', 60);
    H.AddSection('', 70);
    H.AddSection('', 40);

    Shoot(False);
    AssertTrue('unmirrored, section 0''s divider is the last pixel inside it',
      ChannelInColumn(shot, chGreen, 59));
    AssertTrue('and section 1''s likewise', ChannelInColumn(shot, chGreen, 129));

    Shoot(True);
    { Mirrored spans are [240,300) [170,240) [0,170); the shared edges the grip answers to
      are 240 and 170. }
    AssertTrue('mirrored, section 0''s divider is on the boundary the grip grabs (x=240)',
      ChannelInColumn(shot, chGreen, 240));
    AssertTrue('and section 1''s at x=170', ChannelInColumn(shot, chGreen, 170));
    AssertFalse('the LTR divider column at x=59 is bare', ChannelInColumn(shot, chGreen, 59));
    AssertFalse('and so is x=129', ChannelInColumn(shot, chGreen, 129));
  finally
    shot.Free;
    host.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

{ ---------------------------------------------------------- TRtlExclusionTest }

{ TTyDropDownButton splits its face into a caption zone and an arrow zone, and decides which
  one was pressed by reading the x of the click back through TyDropArrowHit
  (tyControls.DropButtons.pas:170). That makes it the one control in this batch that is NOT
  safe to mirror in the paint path alone: an arrow drawn on the left while the hit test still
  answers on the right is "drawn right, answers wrong", which this library has already shipped
  three times (TTyShape's bounding box, TTyTreeView.GetNodeAt, the date picker's year field).

  So the arrow stays on the right for now, and this test pins BOTH halves together: whoever
  mirrors it has to move the paint and the hit test in the same commit, because moving either
  one alone turns this red. }
procedure TRtlExclusionTest.DropDownArrowStaysWhereItsHitTestSaysItIs;
var
  Ctl: TTyStyleController;
  Form: TForm;
  B: TDropBtnAccess;
  host: TBitmap;
  shot: TBGRABitmap;
  l, r: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  host := NewHost(160, 26);
  try
    Ctl.LoadThemeCss('TyButton { background: #FFFFFF; color: #00FF00; border-width: 0px; padding: 0px; }');
    B := TDropBtnAccess.Create(Form);
    B.Parent := Form;
    B.Controller := Ctl;
    B.Font.PixelsPerInch := 96;
    B.SetBounds(0, 0, 160, 26);
    B.Caption := '';
    B.BiDiMode := bdRightToLeft;
    B.RenderTo(host.Canvas, Rect(0, 0, 160, 26), 96);
    shot := TBGRABitmap.Create(host);
    try
      ChannelSpanX(shot, chGreen, l, r);
      AssertTrue('the divider and chevron drew', l >= 0);
      AssertTrue('the arrow zone is still painted on the right', l > 80);
    finally
      shot.Free;
    end;
    { And the hit test agrees with the paint, which is the point. }
    AssertTrue('a click near the right edge still opens the drop-down',
      TyDropArrowHit(158, 160, B.ArrowW(96)));
    AssertTrue('and a click near the left edge is still the primary action',
      not TyDropArrowHit(2, 160, B.ArrowW(96)));
  finally
    host.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

{ TTyButtonGroup maps a click's raw x straight onto a segment index (TySegmentAt, called
  from MouseDown and MouseMove). Reversing the segments in the paint alone would select the
  segment at the mirror-image position of the one under the pointer -- the same defect as
  above, and worse for being silent on a control whose whole purpose is choosing. Excluded
  for now; pinned here so the exclusion is a decision rather than an oversight. }
procedure TRtlExclusionTest.ButtonGroupSegmentsAreNotMirroredWhileSegmentAtReadsRawX;
var
  Form: TForm;
  G: TTyButtonGroup;
begin
  Form := TForm.CreateNew(nil);
  try
    G := TTyButtonGroup.Create(Form);
    G.Parent := Form;
    G.SetBounds(0, 0, 200, 26);
    G.Items.Add('One');
    G.Items.Add('Two');
    G.BiDiMode := bdRightToLeft;
    AssertEquals('the leftmost pixels still belong to segment 0',
      0, TySegmentAt(4, 200, 2));
    AssertEquals('and the rightmost to segment 1',
      1, TySegmentAt(196, 200, 2));
  finally
    Form.Free;
  end;
end;

procedure TRtlExclusionTest.ValueListEditorIsNotMirroredWhileItsSplitterIsHitTestedTwice;
var
  Form: TForm;
  V: TValueListAccess;
begin
  { The third exclusion, and the one phase 3 had to make. TTyValueListEditor is a TTyListBox,
    so it inherits a row rect that now changes sides -- but its splitter drag, its column
    click and its expander triangles are hit-tested from ContentLeftDp / SplitXDp
    (tyControls.ValueListEditor.pas:536, :576, :1542), a SECOND computation of the geometry
    its PaintItemContent derives from ARowRect (:1426). Mirroring one and not the other puts
    the divider a scrollbar's width from where it is grabbed. }
  Form := TForm.CreateNew(nil);
  try
    V := TValueListAccess.Create(Form);
    V.Parent := Form;
    V.BiDiMode := bdRightToLeft;
    AssertTrue('the form really is mirrored', V.IsRightToLeft);
    AssertFalse('but the property inspector opts out until its two x computations are one',
      V.Mirrors);
  finally
    Form.Free;
  end;
end;

{ ------------------------------------------------ TRtlScrollBarGeometryTest -- }

procedure TRtlScrollBarGeometryTest.MirroredHorizontalThumbStartsAtTheRightEndOfTheTrack;
var
  t: TRect;
  ltr, rtl: TRect;
begin
  { Position = Min. Left to right that is the left end; mirrored it is the right end -- the
    origin moved, which is the entire behavioural claim. }
  t := Rect(0, 0, 200, 12);
  ltr := TyScrollThumbRect(t, sbHorizontal, 0, 100, 0, 10, False);
  rtl := TyScrollThumbRect(t, sbHorizontal, 0, 100, 0, 10, True);
  AssertEquals('unmirrored, Min sits at the track start', 0, ltr.Left);
  AssertEquals('mirrored, Min sits at the track END', 200, rtl.Right);
  AssertEquals('and the thumb is the same length either way',
    ltr.Right - ltr.Left, rtl.Right - rtl.Left);
end;

procedure TRtlScrollBarGeometryTest.MirroredHorizontalThumbEndsAtTheLeftEndOfTheTrack;
var
  t, rtl: TRect;
begin
  t := Rect(0, 0, 200, 12);
  rtl := TyScrollThumbRect(t, sbHorizontal, 0, 100, 100, 10, True);
  AssertEquals('mirrored, Max sits at the track START', 0, rtl.Left);
end;

procedure TRtlScrollBarGeometryTest.MirroredThumbIsTheExactReflectionOfTheUnmirroredOne;
var
  t, a, b: TRect;
  p: Integer;
begin
  { Not "roughly opposite": the mirrored rect is the unmirrored one reflected in the track,
    at every position. An off-by-one here is the gap that makes a thumb unable to reach one
    end of its own track. The track deliberately does not start at 0 so a mirror written as
    "Right - Offset" without the track's own Left would fail. }
  t := Rect(17, 0, 217, 12);
  for p := 0 to 100 do
  begin
    a := TyScrollThumbRect(t, sbHorizontal, 0, 100, p, 10, False);
    b := TyScrollThumbRect(t, sbHorizontal, 0, 100, p, 10, True);
    AssertEquals('reflected left edge at position ' + IntToStr(p),
      t.Left + t.Right - a.Right, b.Left);
    AssertEquals('reflected right edge at position ' + IntToStr(p),
      t.Left + t.Right - a.Left, b.Right);
  end;
end;

procedure TRtlScrollBarGeometryTest.VerticalThumbsAreUntouchedByTheMirror;
var
  t, a, b: TRect;
  p: Integer;
begin
  { The flag is horizontal-only by construction, and this is what says so. A vertical bar in
    a mirrored window keeps every pixel: it changes which EDGE of its host it docks to, and
    that is the host's decision, not the bar's. }
  t := Rect(0, 0, 12, 200);
  for p := 0 to 100 do
  begin
    a := TyScrollThumbRect(t, sbVertical, 0, 100, p, 10, False);
    b := TyScrollThumbRect(t, sbVertical, 0, 100, p, 10, True);
    AssertTrue('vertical thumb identical at position ' + IntToStr(p),
      (a.Left = b.Left) and (a.Top = b.Top) and (a.Right = b.Right) and (a.Bottom = b.Bottom));
  end;
end;

procedure TRtlScrollBarGeometryTest.TrackAndButtonSizeAreSymmetricSoTheyDoNotMirror;
var
  c, t: TRect;
begin
  { The scoping document expected the two end buttons to swap inside TyScrollTrackRect. They
    are not in it -- it insets by one button-size at EACH end, so it is symmetric about the
    centre and reflecting it is the identity. Pinned so the next reader does not go hunting
    for a mirror that would have been a no-op. }
  c := Rect(0, 0, 200, 12);
  t := TyScrollTrackRect(c, sbHorizontal, TyScrollButtonSize(c, sbHorizontal));
  AssertEquals('the track is inset equally at both ends',
    t.Left - c.Left, c.Right - t.Right);
end;

{ ------------------------------------------------- TRtlScrollBarControlTest -- }

procedure TRtlScrollBarControlTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
end;

procedure TRtlScrollBarControlTest.TearDown;
begin
  FreeAndNil(FForm);
end;

function TRtlScrollBarControlTest.MakeBar(AMirror: Boolean): TTyScrollBar;
begin
  Result := TBarAccess.Create(FForm);
  Result.Parent := FForm;
  Result.Kind := sbHorizontal;
  Result.SetBounds(0, 0, 200, 12);
  Result.Min := 0;
  Result.Max := 100;
  Result.PageSize := 10;
  Result.SmallChange := 1;
  Result.LargeChange := 0;
  Result.MirrorHorizontal := AMirror;
end;

procedure TRtlScrollBarControlTest.MirroringIsOptInAndNotTakenFromTheFormsBiDiMode;
var
  B: TTyScrollBar;
  ltr: TRect;
begin
  { The one guard that keeps this phase from breaking four controls it is not allowed to
    touch. TTyGrid, TTyListView, TTyMemo and TTyTreeView each embed a horizontal bar and none
    of them mirrors its CONTENT; if the bar read BiDiMode it would put Position = Min on the
    right of a document that still begins on the left, which is the same paint/hit-test split
    one level up. A host opts in when it mirrors what the bar scrolls. }
  FForm.BiDiMode := bdRightToLeft;
  B := TBarAccess.Create(FForm);
  B.Parent := FForm;
  B.Kind := sbHorizontal;
  B.SetBounds(0, 0, 200, 12);
  B.Min := 0; B.Max := 100; B.PageSize := 10;
  B.Position := 0;
  AssertTrue('the bar really did inherit the mirrored form', B.IsRightToLeft);
  AssertFalse('but mirroring its track is opt-in', B.MirrorHorizontal);
  { Asserting the PROPERTY is not enough -- a bar that quietly ORed IsRightToLeft into its
    internal decision would leave the property False and still mirror. So press where an
    unmirrored Position=Min thumb is: it has to be there, and grabbable. }
  ltr := TyScrollThumbRect(TBarAccess(B).Track, sbHorizontal, 0, 100, 0, 10, False);
  TBarAccess(B).CallMouseDown((ltr.Left + ltr.Right) div 2, 6);
  AssertTrue('and Min is still where an unmirrored bar puts it: grabbable at the LEFT end',
    B.Dragging);
  TBarAccess(B).CallMouseUp((ltr.Left + ltr.Right) div 2, 6);
end;

procedure TRtlScrollBarControlTest.AMirroredBarGrabsTheThumbWhereItPaintsIt;
var
  B: TTyScrollBar;
  thumb: TRect;
begin
  { PAINT AND HIT TEST, THE SAME CALL. RenderTo builds its thumb from TyScrollThumbRect and
    so does MouseDown; this asserts the consequence -- a press in the middle of the PAINTED
    thumb starts a drag. }
  B := MakeBar(True);
  B.Position := 40;
  thumb := TyScrollThumbRect(TBarAccess(B).Track, sbHorizontal, 0, 100, 40, 10, True);
  TBarAccess(B).CallMouseDown((thumb.Left + thumb.Right) div 2, 6);
  AssertTrue('pressing the painted thumb starts a drag', B.Dragging);
  TBarAccess(B).CallMouseUp((thumb.Left + thumb.Right) div 2, 6);
end;

procedure TRtlScrollBarControlTest.AMirroredBarDoesNotGrabWhereTheUnmirroredThumbUsedToBe;
var
  B: TTyScrollBar;
  ghost: TRect;
begin
  { The negative half, and the one that actually fails when only the paint is mirrored: the
    place the thumb WOULD have been is now bare track, and pressing it must page rather than
    grab. Without this, a mirror applied to the drawing alone still passes the test above. }
  B := MakeBar(True);
  B.Position := 40;
  ghost := TyScrollThumbRect(TBarAccess(B).Track, sbHorizontal, 0, 100, 40, 10, False);
  TBarAccess(B).CallMouseDown((ghost.Left + ghost.Right) div 2, 6);
  AssertFalse('the old, unmirrored thumb position is not grabbable', B.Dragging);
  TBarAccess(B).CallMouseUp((ghost.Left + ghost.Right) div 2, 6);
end;

procedure TRtlScrollBarControlTest.DraggingAMirroredThumbLeftRaisesThePosition;
var
  B: TTyScrollBar;
  thumb: TRect;
  grab: Integer;
begin
  B := MakeBar(True);
  B.Position := 50;
  thumb := TyScrollThumbRect(TBarAccess(B).Track, sbHorizontal, 0, 100, 50, 10, True);
  grab := (thumb.Left + thumb.Right) div 2;
  TBarAccess(B).CallMouseDown(grab, 6);
  AssertTrue('drag started', B.Dragging);
  TBarAccess(B).CallMouseMove(grab - 40, 6);
  AssertTrue('dragging the thumb LEFT raises Position on a mirrored bar (was ' +
    IntToStr(B.Position) + ')', B.Position > 50);
  TBarAccess(B).CallMouseUp(grab - 40, 6);
end;

procedure TRtlScrollBarControlTest.DragAndPaintStayExactInversesUnderTheMirror;
var
  B: TTyScrollBar;
  t, thumb: TRect;
  p, got: Integer;
begin
  { Grab a mirrored thumb dead centre and put it back down where it was: the position must be
    the one it started at. This is the round trip through both directions of the mirror -- the
    painted rect out, the dragged rect back in -- and it is what would break if either side
    used its own copy of the flip. }
  B := MakeBar(True);
  t := TBarAccess(B).Track;
  for p := 0 to 20 do
  begin
    B.Position := p * 5;
    thumb := TyScrollThumbRect(t, sbHorizontal, 0, 100, B.Position, 10, True);
    TBarAccess(B).CallMouseDown(thumb.Left + 2, 6);
    if not B.Dragging then Fail('press on the thumb at position ' + IntToStr(p * 5) +
      ' did not grab it');
    got := B.Position;
    TBarAccess(B).CallMouseMove(thumb.Left + 2, 6);
    AssertEquals('a zero-distance drag at position ' + IntToStr(got) + ' must not move it',
      got, B.Position);
    TBarAccess(B).CallMouseUp(thumb.Left + 2, 6);
  end;
end;

procedure TRtlScrollBarControlTest.TheLeftEndButtonRaisesThePositionOnAMirroredBar;
var
  B: TTyScrollBar;
  bs: Integer;
begin
  { The end buttons keep their GLYPHS (reflecting a left arrow at one end and a right arrow at
    the other gives back the same picture, which is why a mirrored Windows scroll bar looks
    identical). What changes is which way each one steps: the thumb travels toward the button
    you pressed, and on a mirrored bar the left-hand end is the high end. }
  B := MakeBar(True);
  B.Position := 50;
  bs := TyScrollButtonSize(B.ClientRect, sbHorizontal);
  TBarAccess(B).CallMouseDown(bs div 2, 6);
  AssertEquals('the LEFT end button steps toward Max when mirrored', 51, B.Position);
  B.Position := 50;
  TBarAccess(B).CallMouseDown(200 - bs div 2, 6);
  AssertEquals('and the right end button steps toward Min', 49, B.Position);
end;

procedure TRtlScrollBarControlTest.ATrackClickPagesTowardsTheClickOnAMirroredBar;
var
  B: TTyScrollBar;
  thumb: TRect;
begin
  B := MakeBar(True);
  B.Position := 50;
  thumb := TyScrollThumbRect(TBarAccess(B).Track, sbHorizontal, 0, 100, 50, 10, True);
  { Bare track to the LEFT of the thumb. The thumb has to come to the click, and on a mirrored
    bar moving left means moving up. }
  TBarAccess(B).CallMouseDown(thumb.Left - 8, 6);
  AssertTrue('clicking left of a mirrored thumb pages toward Max (got ' +
    IntToStr(B.Position) + ')', B.Position > 50);
end;

procedure TRtlScrollBarControlTest.ArrowKeysFollowTheThumbAndHomeEndStayLogical;
var
  B: TTyScrollBar;
begin
  B := MakeBar(True);
  B.Position := 50;
  TBarAccess(B).CallKeyDown(VK_LEFT);
  AssertEquals('Left moves the thumb left, which on a mirrored bar is up-Position',
    51, B.Position);
  TBarAccess(B).CallKeyDown(VK_RIGHT);
  AssertEquals('and Right brings it back', 50, B.Position);
  { Home and End are the LOGICAL ends, not the visual ones -- §6.3 item 3. They do not flip. }
  TBarAccess(B).CallKeyDown(VK_HOME);
  AssertEquals('Home is still Min', 0, B.Position);
  TBarAccess(B).CallKeyDown(VK_END);
  AssertEquals('End is still Max', 100, B.Position);
end;

procedure TRtlScrollBarControlTest.AVerticalBarIgnoresMirrorHorizontalCompletely;
var
  B: TTyScrollBar;
  thumb: TRect;
begin
  B := TBarAccess.Create(FForm);
  B.Parent := FForm;
  B.Kind := sbVertical;
  B.SetBounds(0, 0, 12, 200);
  B.Min := 0; B.Max := 100; B.PageSize := 10;
  B.MirrorHorizontal := True;      // set, and deliberately inert
  B.Position := 0;
  thumb := TyScrollThumbRect(TBarAccess(B).Track, sbVertical, 0, 100, 0, 10, True);
  AssertEquals('a vertical thumb at Min is still at the TOP', TBarAccess(B).Track.Top,
    thumb.Top);
  B.Position := 50;
  TBarAccess(B).CallKeyDown(VK_UP);
  AssertEquals('and Up still decrements', 49, B.Position);
end;

{ ------------------------------------------------------- TRtlScrollBoxTest -- }

procedure TRtlScrollBoxTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
end;

procedure TRtlScrollBoxTest.TearDown;
begin
  FreeAndNil(FForm);
end;

{ A box with content that overflows on the chosen axes, already measured and docked. }
function MakeBox(AParent: TWinControl; ARtl: Boolean; AChildW, AChildH: Integer;
  AWithViewport: Boolean = False): TBoxAccess;
var
  c: TTyPanel;
  vp: TTyScrollContent;
begin
  Result := TBoxAccess.Create(AParent);
  Result.Parent := AParent;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, 300, 200);
  if ARtl then Result.BiDiMode := bdRightToLeft;
  if AWithViewport then
  begin
    vp := TTyScrollContent.Create(Result);
    vp.Parent := Result;
    c := TTyPanel.Create(vp);
    c.Parent := vp;
  end
  else
  begin
    c := TTyPanel.Create(Result);
    c.Parent := Result;
  end;
  c.SetBounds(0, 0, AChildW, AChildH);
  Result.UpdateScrollRange;
end;

procedure TRtlScrollBoxTest.TheVerticalBarDocksToTheLeftEdge;
var
  B: TBoxAccess;
begin
  { THE HEADLINE. A vertical scroll bar on the left edge is the single loudest thing a window
    does to say it reads right-to-left, and it is why this phase outranks the cheaper ones.
    MeasureAndDock writes the bounds itself (SetBounds, not Align), so this is real geometry
    and not an align pass that headless never runs. }
  B := MakeBox(FForm, True, 100, 600);
  AssertTrue('the vertical bar is up', B.VBar.Visible);
  AssertEquals('and it is docked at the LEFT edge, inside the frame',
    B.Frame, B.VBar.Left);
end;

procedure TRtlScrollBoxTest.TheHorizontalBarStartsAfterTheMirroredGutter;
var
  B: TBoxAccess;
begin
  B := MakeBox(FForm, True, 800, 600);
  AssertTrue('both bars are up', B.VBar.Visible and B.HBar.Visible);
  AssertEquals('the horizontal bar starts where the content does, past the vertical gutter',
    B.Frame + B.VBar.Width, B.HBar.Left);
  AssertEquals('and it still stops short of the corner, which has changed ends',
    300 - B.Frame, B.HBar.Left + B.HBar.Width);
end;

procedure TRtlScrollBoxTest.TheViewportStartsAfterTheMirroredGutter;
var
  B: TBoxAccess;
begin
  { The clipping viewport is the window children are actually parented into, so if it stays
    put nothing else mattering moves either. }
  B := MakeBox(FForm, True, 100, 600, True);
  AssertTrue('the box claimed the viewport', B.Viewport <> nil);
  AssertEquals('the viewport begins after the mirrored gutter',
    B.Frame + B.VBar.Width, B.Viewport.Left);
end;

procedure TRtlScrollBoxTest.TheLayoutOriginClearsTheMirroredGutter;
var
  B: TBoxAccess;
  area: TRect;
begin
  B := MakeBox(FForm, True, 100, 600);
  area := B.ChildArea;
  AssertEquals('children are laid out starting past the left-hand bar',
    B.Frame + B.VBar.Width, area.Left);
end;

procedure TRtlScrollBoxTest.MirroringChangesTheSideOfTheGuttersAndNotTheirCost;
var
  L, R: TBoxAccess;
begin
  { THE TRAP, PINNED. The scoping document asks GetClientRect's `Dec(Result.Right, barW)` to
    become `Inc(Result.Left, barW)` when mirrored. TControl.GetClientWidth is literally
    ClientRect.Right, so that change makes a mirrored box report the FULL width as its client
    width while its layout rect is a scrollbar narrower -- and LCL banks a child's anchor
    baseline from the first and lays it out against the second, re-banking the difference on
    every ScrollBy. That is the recorded "an akRight child loses 12 px per scroll until it
    disappears". Mirroring moves the ORIGIN, in AdjustClientRect; the SIZE is side-independent
    and must come out identical. }
  L := MakeBox(FForm, False, 800, 600);
  R := MakeBox(FForm, True,  800, 600);
  AssertEquals('ClientWidth is unchanged by mirroring',  L.ClientWidth,  R.ClientWidth);
  AssertEquals('ClientHeight is unchanged by mirroring', L.ClientHeight, R.ClientHeight);
  AssertEquals('and so is the width of the child layout area',
    L.ChildArea.Right - L.ChildArea.Left, R.ChildArea.Right - R.ChildArea.Left);
  AssertEquals('and its height',
    L.ChildArea.Bottom - L.ChildArea.Top, R.ChildArea.Bottom - R.ChildArea.Top);
end;

procedure TRtlScrollBoxTest.TheScrolledOriginStillFollowsTheOffsetWhenMirrored;
var
  B: TBoxAccess;
  area: TRect;
  lead: Integer;
begin
  { Hook three of the three, under the mirror. The gutter is a fixed slide and the offset is a
    moving one; both land on the same rect, and an implementation that applied the slide to
    Left alone would shrink the layout area by a bar as well as move it -- which is the same
    12-px-per-scroll shape from the other direction. }
  B := MakeBox(FForm, True, 800, 600);
  lead := B.Frame + B.VBar.Width;
  area := B.ChildArea;
  AssertEquals('unscrolled, the origin is the frame plus the mirrored gutter', lead, area.Left);
  B.ScrollTo(120, 90);
  AssertEquals('the offset took', 120, B.ScrollX);
  area := B.ChildArea;
  AssertEquals('the horizontal origin moved with the scroll and kept the gutter',
    lead - 120, area.Left);
  AssertEquals('the vertical origin moved with the scroll', B.Frame - 90, area.Top);
end;

procedure TRtlScrollBoxTest.ReDockingAfterAScrollKeepsTheBarsOnTheMirroredSide;
var
  B: TBoxAccess;
begin
  { ScrollBy moves EVERY child, the two bars included, so the box re-docks them straight
    afterwards -- from a second copy of the placement. Both copies have to agree about the
    side or the bar snaps back to the right on the first drag. }
  B := MakeBox(FForm, True, 800, 600);
  B.ScrollTo(60, 60);
  AssertEquals('the vertical bar is still on the left after a scroll', 0, B.VBar.Left);
  AssertEquals('and the horizontal bar still starts after its gutter',
    B.VBar.Width, B.HBar.Left);
end;

procedure TRtlScrollBoxTest.TheBoxsOwnHorizontalBarDoesNotMirrorItsOrigin;
var
  B: TBoxAccess;
  bar: TTyScrollBar;
  ltr: TRect;
begin
  { DELIBERATE, and the reasoning is worth keeping next to the assertion. §6.3 item 1 pins
    child Align/Anchors layout as NOT mirrored -- LCL's align engine has no BiDi outside the
    ChildSizing table path, and diverging from it would misplace every ported .lfm. So the
    children inside this box are still laid out left to right, the content's own origin is
    still its left edge, and a bar that put Position = Min on the RIGHT would be pointing at
    the wrong end of the document it scrolls. The bar mirrors when its content does. }
  B := MakeBox(FForm, True, 800, 600);
  bar := B.HBar;
  AssertFalse('the box does not mirror the bar whose content it has not mirrored',
    bar.MirrorHorizontal);
  { And behaviourally, not merely by the property: offset 0 is the content's left edge, so
    the thumb has to be at the bar's left edge and grabbable there. }
  bar.Position := bar.Min;
  ltr := TyScrollThumbRect(TBarAccess(bar).Track, sbHorizontal, bar.Min, bar.Max,
    bar.Min, bar.PageSize, False);
  TBarAccess(bar).CallMouseDown((ltr.Left + ltr.Right) div 2, bar.Height div 2);
  AssertTrue('a scroll offset of 0 puts the thumb at the LEFT end, where it is grabbable',
    bar.Dragging);
  TBarAccess(bar).CallMouseUp((ltr.Left + ltr.Right) div 2, bar.Height div 2);
end;

procedure TRtlScrollBoxTest.AutoPanBandsMoveWithTheMirroredViewport;
var
  P: TPanAccess;
  c: TTyPanel;
  vp: TRect;
begin
  { The auto-pan bands are measured against a viewport rect. ClientRect gives up the bar's
    width but always starts at 0, so on a mirrored panel the real viewport is that rect slid
    across -- leave it and the left band arms the pan ON TOP of the scroll bar while the band
    the user can actually reach at the right edge sits outside the rect entirely, i.e.
    permanently at full speed. }
  P := TPanAccess.Create(FForm);
  P.Parent := FForm;
  P.Font.PixelsPerInch := 96;
  P.SetBounds(0, 0, 300, 200);
  P.BiDiMode := bdRightToLeft;
  c := TTyPanel.Create(P);
  c.Parent := P;
  c.SetBounds(0, 0, 100, 600);
  P.UpdateScrollRange;
  vp := P.PanViewport;
  AssertTrue('precondition: the panel reserved a mirrored gutter', P.Lead > 0);
  AssertEquals('the pan viewport starts after the mirrored gutter', P.Lead, vp.Left);
  AssertEquals('and still ends at the right edge of the panel', 300, vp.Right);
end;

{ --------------------------------------------------------- TRtlListBoxTest -- }

procedure TRtlListBoxTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
end;

procedure TRtlListBoxTest.TearDown;
begin
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
end;

procedure TRtlListBoxTest.TheScrollBarDocksToTheLeftEdge;
var
  L: TListAccess;
  i: Integer;
begin
  { The list box's bar is a real child with a real Align, and LCL's align engine is not
    BiDi-aware (§1.2), so alRight stays the right-hand edge on a mirrored form. The side has
    to be chosen explicitly, and UpdateScrollBar is where. }
  L := TListAccess.Create(FForm);
  L.Parent := FForm;
  L.Font.PixelsPerInch := 96;
  L.SetBounds(0, 0, 200, 100);
  L.ItemHeight := 20;
  for i := 1 to 40 do L.Items.Add('Row ' + IntToStr(i));
  L.BiDiMode := bdRightToLeft;
  L.Remeasure;
  AssertTrue('the bar exists and is up', (L.Bar <> nil) and L.Bar.Visible);
  AssertTrue('and it docks to the LEFT edge when mirrored', L.Bar.Align = alLeft);
end;

procedure TRtlListBoxTest.RowsGiveUpTheGutterOnTheSideTheBarIsActuallyOn;
var
  L: TListAccess;
  i, lL, lR, rL, rR: Integer;
begin
  { The row rect and the bar have to give up the SAME side. Take the gutter off the wrong one
    and the rows run under the bar while a strip of empty box sits opposite -- and every
    hit test built on the row's leading edge lands a bar's width out. }
  L := TListAccess.Create(FForm);
  L.Parent := FForm;
  L.Font.PixelsPerInch := 96;
  L.SetBounds(0, 0, 200, 100);
  L.ItemHeight := 20;
  for i := 1 to 40 do L.Items.Add('Row ' + IntToStr(i));
  L.Remeasure;
  L.Bounds2(200, 96, lL, lR);
  L.BiDiMode := bdRightToLeft;
  L.Remeasure;
  L.Bounds2(200, 96, rL, rR);
  AssertTrue('precondition: a bar is showing', L.Bar.Visible);
  AssertTrue('unmirrored, the row gives up its right end to the bar', lR < 200);
  AssertEquals('mirrored, the row gives up its LEFT end by the bar''s width instead',
    lL + L.Bar.Width, rL);
  AssertEquals('and gets back the right end it used to give up',
    lR + L.Bar.Width, rR);
  AssertEquals('so the rows are exactly as wide either way', lR - lL, rR - rL);
end;

procedure TRtlListBoxTest.RowTextMovesToTheRightEdge;
var
  Lb: TListAccess;
  host: TBitmap;
  shot: TBGRABitmap;
  l, r: Integer;
begin
  host := NewHost(200, 30);
  try
    FCtl.LoadThemeCss('TyListBox { background: #FFFFFF; border-width: 0px; padding: 0px; }' +
      'TyListItem { color: #00FF00; padding: 0px; }');
    Lb := TListAccess.Create(FForm);
    Lb.Parent := FForm;
    Lb.Controller := FCtl;
    Lb.Font.PixelsPerInch := 96;
    Lb.SetBounds(0, 0, 200, 30);
    Lb.ItemHeight := 24;
    Lb.Items.Add('Name');
    Lb.BiDiMode := bdRightToLeft;
    Lb.RenderTo(host.Canvas, Rect(0, 0, 200, 30), 96);
    shot := TBGRABitmap.Create(host);
    try
      ChannelSpanX(shot, chGreen, l, r);
      AssertTrue('the row drew its text', l >= 0);
      AssertTrue('a mirrored row hugs the RIGHT edge', r > 200 - 12);
      AssertTrue('and has left the left edge', l > 100);
    finally
      shot.Free;
    end;
  finally
    host.Free;
  end;
end;

procedure TRtlListBoxTest.ChangingBiDiModeMovesABarThatAlreadyExists;
var
  L: TListAccess;
  i: Integer;
begin
  { The bar's Align is written by UpdateScrollBar, and LCL's CMBiDiModeChanged invalidates,
    notifies the children and calls AdjustSize -- none of which re-runs it. Phase 1 found the
    same defect in the groups: the indicators flipped and the columns did not. }
  L := TListAccess.Create(FForm);
  L.Parent := FForm;
  L.Font.PixelsPerInch := 96;
  L.SetBounds(0, 0, 200, 100);
  L.ItemHeight := 20;
  for i := 1 to 40 do L.Items.Add('Row ' + IntToStr(i));
  L.Remeasure;
  AssertTrue('precondition: the bar starts on the right', L.Bar.Align = alRight);
  L.BiDiMode := bdRightToLeft;      // no explicit UpdateScrollBar: the message must do it
  AssertTrue('turning the form around moved the bar that was already there',
    L.Bar.Align = alLeft);
end;

procedure TRtlListBoxTest.TheCheckBoxAndTheZoneThatTogglesItMoveTogether;
var
  C: TCheckListAccess;
  pad, sh, cl, cr: Integer;
  slot, zone, ghost: TRect;
begin
  { The strongest guard in the phase, because this control is the one place in the family
    where a click reads X. The square and the column around it come from one function now
    (TyCheckBoxSlotRect); before, they were a Left+pad+size rect in the painter and a
    Padding.Left+pad+size+pad WIDTH in the hit test, agreeing only because both counted from
    zero. Mirroring moves the leading edge twice -- the bar changes sides and the column with
    it -- so "both count from zero" stops being true. }
  C := TCheckListAccess.Create(FForm);
  C.Parent := FForm;
  C.Font.PixelsPerInch := 96;
  C.SetBounds(0, 0, 200, 100);
  C.ItemHeight := 20;
  C.Items.Add('One');
  C.BiDiMode := bdRightToLeft;
  pad := 4;              { device px at 96 ppi }
  sh  := C.ItemHeight;   { ditto }
  C.Bounds2(C.ClientWidth, 96, cl, cr);
  slot := TyCheckBoxSlotRect(Rect(cl, 0, cr, sh), pad, True);
  zone := C.Zone;
  AssertTrue('a mirrored check box sits at the trailing end of the row',
    slot.Right > (cl + cr) div 2);
  AssertTrue('and the toggle zone contains the box it was built from',
    (zone.Left <= slot.Left) and (zone.Right >= slot.Right));
  { Containment alone is too cheap: a zone left un-mirrored spans from x=0 to just past where
    the box USED to be, and a box drawn at the other end still falls inside a zone that wide.
    So the zone also has to have LET GO of the old column. }
  ghost := TyCheckBoxSlotRect(Rect(cl, 0, cr, sh), pad, False);
  AssertFalse('and has let go of the column the box no longer occupies',
    (zone.Left <= ghost.Left) and (zone.Right >= ghost.Right));
end;

procedure TRtlListBoxTest.TheCheckBoxIsPaintedInsideTheZoneThatTogglesIt;
var
  C: TCheckListAccess;
  host: TBitmap;
  shot: TBGRABitmap;
  zone: TRect;
  l, r: Integer;
begin
  { The two guards either side of this one reason about the ZONE (a rect) and about a CLICK
    (a toggle). Neither ever looks at where the square actually landed on the canvas, so a
    mirror applied to the hit test and NOT to the painter slips between them: the zone moves,
    the click that lands in it toggles, and the user is clicking empty row while the box sits
    at the other end. This closes that by probing the painted pixels and requiring them inside
    the zone -- which fails for a mirror applied to either half alone. }
  host := NewHost(200, 30);
  try
    FCtl.LoadThemeCss('TyListBox { background: #FFFFFF; border-width: 0px; padding: 0px; }' +
      'TyListItem { color: #000000; padding: 0px; }' +
      'TyCheckBox { background: #0000FF; border-width: 0px; }');
    C := TCheckListAccess.Create(FForm);
    C.Parent := FForm;
    C.Controller := FCtl;
    C.Font.PixelsPerInch := 96;
    C.SetBounds(0, 0, 200, 30);
    C.ItemHeight := 24;
    C.Items.Add('One');
    C.BiDiMode := bdRightToLeft;
    C.RenderTo(host.Canvas, Rect(0, 0, 200, 30), 96);
    zone := C.Zone;
    shot := TBGRABitmap.Create(host);
    try
      ChannelSpanX(shot, chBlue, l, r);
      AssertTrue('the check box was actually painted', l >= 0);
      AssertTrue('a mirrored check box is painted at the RIGHT end of the row (l=' +
        IntToStr(l) + ')', l > 100);
      AssertTrue('and the painted box lies inside the zone that toggles it (box ' +
        IntToStr(l) + '..' + IntToStr(r) + ', zone ' + IntToStr(zone.Left) + '..' +
        IntToStr(zone.Right) + ')',
        (l >= zone.Left) and (r <= zone.Right));
    finally
      shot.Free;
    end;
  finally
    host.Free;
  end;
end;

procedure TRtlListBoxTest.AMirroredCheckBoxIsNotToggledByAClickWhereItUsedToBe;
var
  C: TCheckListAccess;
  pad, sh, cl, cr: Integer;
  slot: TRect;
begin
  { The behavioural half: press the painted box and it toggles; press its unmirrored ghost and
    it does not. A paint-only mirror passes neither. }
  C := TCheckListAccess.Create(FForm);
  C.Parent := FForm;
  C.Font.PixelsPerInch := 96;
  C.SetBounds(0, 0, 200, 100);
  C.ItemHeight := 20;
  C.Items.Add('One');
  C.BiDiMode := bdRightToLeft;
  pad := 4;              { device px at 96 ppi }
  sh  := C.ItemHeight;   { ditto }
  C.Bounds2(C.ClientWidth, 96, cl, cr);
  slot := TyCheckBoxSlotRect(Rect(cl, 0, cr, sh), pad, True);

  C.CallMouseDown((slot.Left + slot.Right) div 2, sh div 2);
  AssertTrue('clicking the box where it is painted toggles the row', C.Checked[0]);

  C.Checked[0] := False;
  slot := TyCheckBoxSlotRect(Rect(cl, 0, cr, sh), pad, False);   // where it USED to be
  C.CallMouseDown((slot.Left + slot.Right) div 2, sh div 2);
  AssertFalse('and clicking where it used to be does not', C.Checked[0]);
end;

procedure TRtlListBoxTest.TheColourSwatchMovesToTheRightEdge;
var
  K: TColorListAccess;
  host: TBitmap;
  shot: TBGRABitmap;
  l, r: Integer;
begin
  host := NewHost(200, 30);
  try
    FCtl.LoadThemeCss('TyListBox { background: #FFFFFF; border-width: 0px; padding: 0px; }' +
      'TyListItem { color: #000000; padding: 0px; }');
    K := TColorListAccess.Create(FForm);
    K.Parent := FForm;
    K.Controller := FCtl;
    K.Font.PixelsPerInch := 96;
    K.SetBounds(0, 0, 200, 30);
    K.ItemHeight := 24;
    K.Items.Clear;
    K.AddColor('Red', TColor($0000FF));    // BGR: pure red
    K.BiDiMode := bdRightToLeft;
    K.RenderTo(host.Canvas, Rect(0, 0, 200, 30), 96);
    shot := TBGRABitmap.Create(host);
    try
      ChannelSpanX(shot, chRed, l, r);
      AssertTrue('the swatch was drawn', l >= 0);
      AssertTrue('a mirrored swatch sits at the RIGHT end of the row', l > 150);
    finally
      shot.Free;
    end;
  finally
    host.Free;
  end;
end;

initialization
  RegisterTest(TRtlPainterTest);
  RegisterTest(TRtlCaptionTest);
  RegisterTest(TRtlIndicatorTest);
  RegisterTest(TRtlGeometryTest);
  RegisterTest(TRtlGroupTest);
  RegisterTest(TRtlButtonSlotTest);
  RegisterTest(TRtlHeaderTest);
  RegisterTest(TRtlExclusionTest);
  RegisterTest(TRtlScrollBarGeometryTest);
  RegisterTest(TRtlScrollBarControlTest);
  RegisterTest(TRtlScrollBoxTest);
  RegisterTest(TRtlListBoxTest);
end.
