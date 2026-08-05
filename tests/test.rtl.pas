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

  Phase 2 is TTyHeaderControl and phase 4 the tab family; both are here too. From phase 2
  onwards every control mirrors its HIT TEST as well as its paint, which is why each of them
  answers out of the same function that places the thing -- and why these tests assert both
  halves rather than pixels alone.

  Phase 4 adds the TAB family (§3.11), and it is the first batch here that does NOT have that
  safety property: a tab strip has four consumers of one x axis -- the paint, the click hit
  test, the drag-reorder midpoint rule, and the overflow scroll offset. TRtlTabStripTest is
  therefore built mostly out of INVERSE and SYMMETRY assertions rather than "is it on the
  right", because only those catch a strip that mirrored three of the four. Two of them sweep
  every device x across the band and compare against the unmirrored strip's answer at the
  reflected x; one renders and asks the hit test to name the tab the paint just filled.

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
  tyControls.HeaderControl,
  tyControls.Columns, tyControls.Grid, tyControls.Grid.Layout,
  tyControls.TabStrip, tyControls.TabSheet, tyControls.PageControl, tyControls.TabSet,
  tyControls.Ribbon,
  { The strip harness -- caption model plus the protected mouse/key seams -- already exists;
    building a second one here would let the two drift. Same precedent as test.edit.bidi
    reaching into test.edit. }
  test.tabstrip;

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

  { Phase 5: the grid (§3.8). It has more x-axis consumers than anything else in the library,
    so its shim is correspondingly wide -- every one of the questions below is a question the
    grid answers out of the SAME function it paints with, and the shim exists to let a test
    ask both halves. }
  TRtlGridAccess = class(TTyStringGrid)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function  ColLeft(ACol: Integer): Integer;
    function  ColWidth(ACol: Integer): Integer;
    function  ColAt(AX: Integer): Integer;
    function  Hit(AX, AY: Integer): TTyGridHit;
    function  Cell(ACol, ARow: Integer): TRect;
    { The CLIPPED rect. The unclipped one cannot see a band/pane swap that only half
      happened -- the cell is still placed correctly and only vanishes once it is
      intersected with the pane it claims to belong to. }
    function  CellVis(ACol, ARow: Integer): TRect;
    { The single source the three chrome renderers (header sections, group subtotals, footer)
      use to cut a scrolled body column back to the band it may paint in. Reached directly
      because it IS the shared function -- asserting its output is asserting all three. }
    function  ClipCol(ACol: Integer; var ALeft, AWidth: Integer): Boolean;
    function  Divider(AX: Integer): Integer;
    function  Metrics: TTyGridMetrics;
    function  ViewW: Integer;
    function  FrozenW: Integer;
    { The embedded bar is a PRIVATE field, so it is found the way a user would find it --
      among the children. That also makes the assertion stronger: it pins the bar the grid
      actually shows, not a field a refactor could leave behind. }
    function  HBar: TTyScrollBar;
    function  SelBounds: TRect;
    function  FunnelRect(ACol: Integer): TRect;
    function  TreeToggle(ARow: Integer): TRect;
    function  BoxRect(ACol, ARow: Integer): TRect;
    function  BtnRect(ACol, ARow: Integer): TRect;
    function  StarRect(ACol, ARow, AStar: Integer): TRect;
    function  DotsRect(ACol, ARow: Integer): TRect;
    function  HandleRect: TRect;
    function  GroupToggle(APos: Integer): TRect;
    function  Sc(AValue: Integer): Integer;
    procedure PressDown(X, Y: Integer);
    procedure PressMove(X, Y: Integer);
    procedure PressUp(X, Y: Integer);
    procedure ClickAt(X, Y: Integer);
    procedure Key(AKey: Word);
    procedure Remeasure;
    procedure ScrollTo(AX: Integer);
    procedure SetLevel(Sender: TObject; ARow: Integer; var ALevel: Integer);
    procedure SetHasKids(Sender: TObject; ARow: Integer; var AHas: Boolean);
  end;

  { The filter drop-down's row layout is a DECLINE (see TRtlExclusionTest); this reaches the
    predicate that records it. }
  TRtlFilterListAccess = class(TTyGridFilterList)
  public
    function Mirrors: Boolean;
  end;

  { TStripAccess (test.tabstrip) supplies the caption model and the protected mouse/key
    seams. Only the paint seam is missing, and this batch needs it: "which header did the
    ink land in" is the only question that can catch a hit test agreeing with itself and
    with nothing else. }
  TRtlStripAccess    = class(TStripAccess) public procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer); end;
  TRtlSheetAccess    = class(TTyTabSheet)  public procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer); end;

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

  { Phase 4: the tab family (§3.11). TTyPageControl, TTyTabSet and the test strip all share
    TTyCustomTabStrip's header engine, which is where every one of these assertions lands. }
  TRtlTabStripTest = class(TTestCase)
  private
    FForm:  TForm;
    FCtl:   TTyStyleController;
    FStrip: TRtlStripAccess;
    procedure Build(ARtl: Boolean; ACount: Integer = 3; AWidth: Integer = 300;
      AClosable: Boolean = False; const ACss: string = '');
    function  Shot: TBGRABitmap;
    function  ScreenMid(AIndex: Integer): Integer;
  protected
    procedure TearDown; override;
  published
    { layout }
    procedure TabsFillFromTheRightEdgeWhenMirrored;
    procedure MirroredTabsTileWithNoSeamAndKeepTheirWidths;
    procedure ContentSpaceStaysInReadingOrderWhenMirrored;
    { paint <-> hit test }
    procedure TheHitTestNamesTheTabThePaintFilled;
    procedure AnOverflowingMirroredStripStillPaintsInsideTheArrowBand;
    procedure HitTestIsTheExactPixelMirrorOfTheUnmirroredStrip;
    { drag-reorder midpoint }
    procedure DropIndexIsTheExactPixelMirrorOfTheUnmirroredStrip;
    procedure DraggingTowardTheReadingStartMovesTheTabEarlier;
    { close slot }
    procedure CloseSlotSitsOnTheTrailingSideAndItsHitTestFollows;
    procedure TheCaptionYieldsTheEdgeTheCloseSlotActuallyTook;
    { overflow scroll }
    procedure OverflowArrowsSwapEndsAndKeepTheirScrollDirections;
    procedure OverflowChevronsKeepPointingOffTheEndTheySitOn;
    procedure ScrollingForwardSlidesTheMirroredStripTowardTheRight;
    { keyboard }
    procedure ArrowKeysFollowTheEyeAndNotTheXAxis;
    procedure HomeEndAndCtrlTabStayLogicalUnderMirroring;
    { what does NOT move }
    procedure ThePageBodyHasNoHorizontalEdgeToMirror;
    procedure MirroredPageControlMovesItsTabsAndNotItsPages;
    procedure TabSheetIsPixelIdenticalWhicheverWayItReads;
    procedure TabSetInheritsTheMirroredStrip;
  end;

  { Phase 5: TTyCustomGrid / TTyStringGrid (§3.8).

    The scoping document buckets this control as a rewrite of the column axis. That is wrong,
    and the reason matters for how these tests are shaped: the column axis was ALREADY
    collapsed. ColumnLeftPx is the one source and ColumnAtX is written as its inverse through
    that same function -- so the tests that sweep every pixel below are guarding a property
    the control already had, not one this commit invented. What this commit had to build was
    the other four single sources: the row-header gutter (four independent `x < IndicatorWidth`
    expressions), the frozen band boundary (four independent `FrozenWidthPx` thresholds), the
    header funnel (paint and hit each computed their own centre), and the resize edge (the
    divider's x and the drag's delta were unrelated expressions that happened to agree).

    So the assertions come in three shapes, and each catches a different half-mirror:
      * INVERSE sweeps -- every device x across the viewport, hit test versus the reflected
        LTR answer. These catch a paint that mirrored while its hit test did not.
      * PAINT-then-HIT -- render, find the ink, ask the hit test to name what is under it.
        These catch two functions that both mirrored but disagree by a slot.
      * WIDTH and INDEX invariants -- what a reflection must NOT change. These catch the
        mirror that also reversed something logical, e.g. a selection anchor. }
  TRtlGridTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl:  TTyStyleController;
    FG:    TRtlGridAccess;
    procedure Build(ARtl: Boolean; const AWidths: array of Integer;
      ARows: Integer = 6; AWidth: Integer = 400);
    function  Shot(AWidth: Integer = 400; AHeight: Integer = 240): TBGRABitmap;
  protected
    procedure TearDown; override;
  published
    { --- the column axis --- }
    procedure ColumnZeroSitsAgainstTheRightEdgeAndTheRestPackLeftwards;
    procedure MirroredColumnsTileWithNoSeamAndKeepEveryWidth;
    procedure ColumnAtXIsTheExactPixelInverseOfTheMirroredTiling;
    procedure TheHitTestNamesTheColumnThePaintFilled;
    procedure ColumnOrderIsMirroredNotReversed;
    { --- the row-header gutter: four consumers, one source --- }
    procedure TheRowHeaderGutterMovesToTheRightEdge;
    procedure AllFourGutterConsumersMovedTogether;
    procedure RowNumberInkLandsInsideTheMirroredGutter;
    { --- the frozen bands --- }
    procedure FrozenColumnsPinToTheRightEdgeAndDoNotScroll;
    procedure TheBodyBandStartsWhereTheFrozenBandEnds;
    procedure ARightFrozenColumnMovesToTheLeftEdge;
    { --- the scroll origin --- }
    procedure ScrollXZeroShowsTheReadingStartWhicheverWayItReads;
    procedure ScrollingForwardSlidesTheBodyTowardTheRight;
    procedure LeftColNamesTheFirstColumnInsideTheBodyBandEitherWay;
    procedure TheHorizontalBarIsToldToMirrorAndTheVerticalOneIsNot;
    procedure ScrollIntoViewChasesTheCellOutTheCorrectEnd;
    { --- resize and drag --- }
    procedure ResizeGripGrabsTheMirroredColumnEdgeNotTheLtrOne;
    procedure DraggingAwayFromTheReadingStartWidensTheColumn;
    { --- header chrome --- }
    procedure AHeaderClickSortsTheColumnUnderThePointerNotItsLtrTwin;
    procedure TheFilterFunnelIsHitWhereItIsPainted;
    procedure AHeaderGroupSpansItsColumnsInsteadOfInverting;
    { --- cell chrome, all of it derived from one cell rect --- }
    procedure CheckBoxAndButtonCellsAnswerInsideTheMirroredCell;
    procedure TheEllipsisButtonMovesToTheCellsLeadingSideAndItsHitFollows;
    procedure RatingStarsCountFromTheRightAndTheClickAgrees;
    procedure TheTreeChevronMovesToTheCellsRightGutterAndItsHitFollows;
    procedure TheFilterRowNamesTheColumnUnderThePointer;
    procedure CellTextHugsTheCellsReadingStart;
    procedure HeaderCaptionsHugTheirSectionsReadingStart;
    procedure TheFixedColumnStripIsPaintedBesideTheMirroredGutter;
    procedure AScrolledBodyColumnIsClippedAtTheFrozenBandsEdge;
    procedure TheFillHandleHangsOffTheSelectionsTrailingCornerAndDragsFromThere;
    procedure TheGroupRowToggleMovesToTheRightAndStillCollapsesItsGroup;
    { --- keyboard and selection --- }
    procedure ArrowKeysFollowTheEyeAndHomeEndStayLogical;
    procedure ARectangularSelectionStillDescribesTheSameCells;
    { --- what a reflection must not change --- }
    procedure EveryColumnWidthAndTheContentWidthSurviveMirroring;
    procedure MergedCellsSpanForwardInsteadOfCollapsing;
  end;

  { The two controls in these same source files that are deliberately NOT mirrored, because
    they read x back out of a click. Pinned so that mirroring them later is a decision
    somebody makes on purpose, with the hit test in the same commit. }
  TRtlExclusionTest = class(TTestCase)
  published
    procedure DropDownArrowStaysWhereItsHitTestSaysItIs;
    procedure ButtonGroupSegmentsAreNotMirroredWhileSegmentAtReadsRawX;
    procedure ValueListEditorIsNotMirroredWhileItsSplitterIsHitTestedTwice;
    procedure RibbonDeclinesToMirrorTheHeaderBandItInherits;
    procedure TheGridsVerticalBarStaysOnTheRightAndItsViewportOriginStaysAtZero;
    procedure TheGridsFilterDropDownDeclinesToMirrorItsRows;
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
procedure TRtlStripAccess.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);     begin RenderTo(ACanvas, ARect, APPI); end;
procedure TRtlSheetAccess.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);     begin RenderTo(ACanvas, ARect, APPI); end;

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

{ How many channel-dominant pixels fall in the half-open x range [AX0, AX1). The same
  dominance rule as ChannelSpanX, counted rather than bounded, because "is any of this
  control's ink in THIS slot" is a different question from "how far does its ink reach" --
  and a composite whose pieces share a colour (a tab caption and its close glyph both paint
  in TyTab's colour) can only be taken apart by slot. }
function ChannelInkCount(A: TBGRABitmap; ACh: TChannel; AX0, AX1: Integer): Integer;
var
  x, y, mine, o1, o2: Integer;
  p: TBGRAPixel;
begin
  Result := 0;
  if AX0 < 0 then AX0 := 0;
  if AX1 > A.Width then AX1 := A.Width;
  for y := 0 to A.Height - 1 do
    for x := AX0 to AX1 - 1 do
    begin
      p := A.GetPixel(x, y);
      case ACh of
        chRed:   begin mine := p.red;   o1 := p.green; o2 := p.blue;  end;
        chGreen: begin mine := p.green; o1 := p.red;   o2 := p.blue;  end;
      else       begin mine := p.blue;  o1 := p.red;   o2 := p.green; end;
      end;
      if (mine > 150) and (o1 < 110) and (o2 < 110) then Inc(Result);
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

{ ----------------------------------------------------------- TRtlTabStripTest }

const
  { One loud colour, on the ACTIVE header only, so a render probe can answer "which tab did
    the paint fill" as a colour search rather than a diff. Everything else in frame is white
    (the box and the inactive headers), near-black (the captions) or the LCL form colour the
    strip lays down first -- none of which is red-dominant, which is what ChannelSpanX tests. }
  cTabCss =
    'TyTabControl { background: #FFFFFF; border-width: 0px; border-radius: 0px; }' +
    'TyPageControl { background: #FFFFFF; border-width: 0px; border-radius: 0px; }' +
    'TyTabSet     { background: #FFFFFF; border-width: 0px; border-radius: 0px; }' +
    'TyTab        { background: #FFFFFF; color: #101010; font-size: 12px; }' +
    'TyTab:active { background: #FF0000; color: #101010; }';

  { The same strip with the CAPTION as the loud colour instead of the active background, for
    the one test that asks where the text landed rather than which header was filled. }
  cTabInkCss =
    'TyTabControl { background: #FFFFFF; border-width: 0px; border-radius: 0px; }' +
    'TyTab        { background: #FFFFFF; color: #0000FF; font-size: 12px; }' +
    'TyTab:active { background: #FFFFFF; color: #0000FF; }';

procedure TRtlTabStripTest.Build(ARtl: Boolean; ACount: Integer; AWidth: Integer;
  AClosable: Boolean; const ACss: string);
var
  i: Integer;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 640, 400);
  FCtl := TTyStyleController.Create(FForm);
  if ACss <> '' then FCtl.LoadThemeCss(ACss) else FCtl.LoadThemeCss(cTabCss);
  FStrip := TRtlStripAccess.Create(FForm);
  FStrip.Parent := FForm;
  FStrip.Controller := FCtl;
  FStrip.Font.PixelsPerInch := 96;
  FStrip.SetBounds(0, 0, AWidth, 120);
  FStrip.TabsClosable := AClosable;
  for i := 1 to ACount do FStrip.AddCap('Tab ' + IntToStr(i));
  { Last, so the strip is fully populated when the direction changes -- the same order a
    host uses, and the order that would expose a layout cached before the flip. }
  if ARtl then FStrip.BiDiMode := bdRightToLeft;
end;

function TRtlTabStripTest.Shot: TBGRABitmap;
var
  host: TBitmap;
begin
  host := NewHost(FStrip.Width, FStrip.Height);
  try
    FStrip.Render(host.Canvas, Rect(0, 0, FStrip.Width, FStrip.Height), 96);
    Result := TBGRABitmap.Create(host);
  finally
    host.Free;
  end;
end;

{ TabRect, not TyTabHeaderRect: the former is the rect AS DRAWN and therefore the one a
  pointer coordinate lives in; the latter is content space, which on a mirrored strip is a
  reading-order coordinate and not a screen one. Every gesture below goes through this. }
function TRtlTabStripTest.ScreenMid(AIndex: Integer): Integer;
var
  r: TRect;
begin
  r := FStrip.TabRect(AIndex);
  Result := (r.Left + r.Right) div 2;
end;

procedure TRtlTabStripTest.TearDown;
begin
  if FForm <> nil then FForm.Free;
  FForm := nil;
end;

{ The headline: the first tab is the RIGHTMOST one and the strip packs leftwards. Stated
  against the control's own right edge rather than against the other tabs, so a mutant that
  merely reverses the collection order (tab 2 first, still starting at x=0) does not pass. }
procedure TRtlTabStripTest.TabsFillFromTheRightEdgeWhenMirrored;
var
  r0, r1, r2: TRect;
begin
  Build(True, 3, 300);
  r0 := FStrip.TabRect(0);
  r1 := FStrip.TabRect(1);
  r2 := FStrip.TabRect(2);
  AssertEquals('tab 0 ends at the control''s right edge', FStrip.Width, r0.Right);
  AssertTrue('tab 1 sits to the LEFT of tab 0', r1.Right = r0.Left);
  AssertTrue('tab 2 sits to the LEFT of tab 1', r2.Right = r1.Left);
  AssertTrue('and the strip has not run off the left edge', r2.Left > 0);
end;

{ A reflection of a gapless tiling is gapless, which is the whole reason the mirroring is
  expressed as BidiFlipRect over the finished layout instead of a reversed accumulation loop
  -- an index-flipped loop has to re-derive every width and is where an off-by-one seam (a
  1px stripe of page body showing between two headers) would come from. }
procedure TRtlTabStripTest.MirroredTabsTileWithNoSeamAndKeepTheirWidths;
var
  i: Integer;
  content, screen: TRect;
begin
  Build(True, 5, 400);
  for i := 0 to 4 do
  begin
    content := FStrip.TyTabHeaderRect(i);
    screen  := FStrip.TabRect(i);
    AssertEquals('tab ' + IntToStr(i) + ' keeps its width under mirroring',
      content.Right - content.Left, screen.Right - screen.Left);
    if i > 0 then
      AssertEquals('no seam between tab ' + IntToStr(i - 1) + ' and tab ' + IntToStr(i),
        FStrip.TabRect(i - 1).Left, screen.Right);
  end;
end;

{ CONTENT space is the reading-order accumulation and stays that way: tab 0 first, and
  TyHeaderStripWidth still the last rect's right edge. Pinned because the mirroring
  deliberately lives in the content -> screen transform rather than in RebuildLayout, and a
  later hand that "fixes" RebuildLayout to lay out backwards would silently break
  TyHeaderStripWidth, TyMaxHeaderScroll and ScrollTabs, which all read content space. }
procedure TRtlTabStripTest.ContentSpaceStaysInReadingOrderWhenMirrored;
begin
  Build(True, 3, 300);
  AssertEquals('content space starts at 0', 0, FStrip.TyTabHeaderRect(0).Left);
  AssertTrue('tab 0 still precedes tab 1 in content space',
    FStrip.TyTabHeaderRect(0).Left < FStrip.TyTabHeaderRect(1).Left);
  AssertEquals('and the strip width is still the last content rect''s right edge',
    FStrip.TyTabHeaderRect(2).Right, FStrip.TyHeaderStripWidth);
end;

{ "Drawn on the right, answers on the left" is the defect this whole programme exists around,
  and this is the test that would see it: render, find the pixels the ACTIVE header style
  filled, and ask the hit test which tab owns that spot. Run for all three tabs because the
  middle one of a three-tab strip is near its own mirror image and would pass by accident. }
procedure TRtlTabStripTest.TheHitTestNamesTheTabThePaintFilled;
var
  i, l, r: Integer;
  bmp: TBGRABitmap;
begin
  Build(True, 3, 300);
  for i := 0 to 2 do
  begin
    FStrip.TabIndex := i;
    bmp := Shot;
    try
      ChannelSpanX(bmp, chRed, l, r);
      AssertTrue('the active header was filled for tab ' + IntToStr(i), l >= 0);
      AssertEquals('the hit test names the tab the paint filled, tab ' + IntToStr(i),
        i, FStrip.IndexOfTabAt((l + r) div 2, FStrip.HeaderMidY));
      { And the fill is where the geometry says, not merely self-consistent. }
      AssertTrue('the fill lies inside that tab''s drawn rect, tab ' + IntToStr(i),
        (l >= FStrip.TabRect(i).Left) and (r < FStrip.TabRect(i).Right));
    finally
      bmp.Free;
    end;
  end;
end;

{ The overflowing case has its own paint step -- the headers are clipped to the band BETWEEN
  the two arrows so a scrolled header cannot paint over them -- and that clip is derived from
  the two arrow rects, which just changed ends. Derived the old way it names an INVERTED
  rectangle and every header disappears: a catastrophic, obvious-in-person bug that no
  geometry assertion sees, because the geometry is still perfectly right. So this one renders
  and looks for ink, and checks it landed between the arrows rather than under them. }
procedure TRtlTabStripTest.AnOverflowingMirroredStripStillPaintsInsideTheArrowBand;
var
  bmp: TBGRABitmap;
  l, r, arrowW: Integer;
begin
  Build(True, 12, 160);
  AssertTrue('precondition: the strip overflows', FStrip.TyMaxHeaderScroll > 0);
  FStrip.TabIndex := 0;
  arrowW := FStrip.TyTabScrollLeftRect.Right - FStrip.TyTabScrollLeftRect.Left;
  AssertTrue('precondition: an arrow band is reserved', arrowW > 0);
  bmp := Shot;
  try
    ChannelSpanX(bmp, chRed, l, r);
    AssertTrue('the active header is still painted when the strip overflows', l >= 0);
    AssertTrue('and it stays inside the band between the two arrows',
      (l >= arrowW) and (r < FStrip.Width - arrowW));
    AssertEquals('and the hit test still names the tab the paint filled',
      0, FStrip.IndexOfTabAt((l + r) div 2, FStrip.HeaderMidY));
  finally
    bmp.Free;
  end;
end;

{ The strongest guard in the batch, and the only shape that catches a strip which mirrored
  three of its four x consumers: sweep EVERY device x across the band and require the
  mirrored strip's answer at x to equal the unmirrored strip's answer at the reflected x.
  Deliberately run on an OVERFLOWING strip with a non-zero scroll, so the arrow bands (which
  are not tabs and must answer -1 on both sides) and the scroll origin are in the sweep too. }
procedure TRtlTabStripTest.HitTestIsTheExactPixelMirrorOfTheUnmirroredStrip;
var
  ltr: array of Integer;
  x, w, midY: Integer;
begin
  Build(False, 12, 160);
  AssertTrue('precondition: the strip overflows', FStrip.TyMaxHeaderScroll > 0);
  FStrip.SetHeaderScroll(37);
  AssertTrue('precondition: and is scrolled', FStrip.HeaderScroll > 0);
  w := FStrip.Width;
  midY := FStrip.HeaderMidY;
  SetLength(ltr, w);
  for x := 0 to w - 1 do ltr[x] := FStrip.IndexOfTabAt(x, midY);
  FForm.Free; FForm := nil;

  Build(True, 12, 160);
  FStrip.SetHeaderScroll(37);
  AssertEquals('precondition: the same scroll offset on both', 37, FStrip.HeaderScroll);
  for x := 0 to w - 1 do
    AssertEquals('hit test at x=' + IntToStr(x) + ' must mirror x=' + IntToStr(w - 1 - x),
      ltr[w - 1 - x], FStrip.IndexOfTabAt(x, midY));
end;

{ The same sweep for the DRAG-REORDER resolver, which is the consumer §3.11 names and the one
  a render test cannot see: TyDropIndexAt answers by MIDPOINT, so it never returns "no tab"
  and a wrong answer looks exactly like a right one until a tab lands in the wrong slot. }
procedure TRtlTabStripTest.DropIndexIsTheExactPixelMirrorOfTheUnmirroredStrip;
var
  ltr: array of Integer;
  x, w: Integer;
begin
  Build(False, 4, 260);
  w := FStrip.Width;
  SetLength(ltr, w);
  for x := 0 to w - 1 do ltr[x] := FStrip.TyDropIndexAt(x, 96);
  FForm.Free; FForm := nil;

  Build(True, 4, 260);
  for x := 0 to w - 1 do
    AssertEquals('drop index at x=' + IntToStr(x) + ' must mirror x=' + IntToStr(w - 1 - x),
      ltr[w - 1 - x], FStrip.TyDropIndexAt(x, 96));
end;

{ The behavioural half, chosen to be a coordinate at which every wrong version of the
  midpoint rule gives a DIFFERENT answer: dragging the last tab toward the reading start (in
  a mirrored strip, rightwards) past its neighbour's drawn midpoint must move it one slot
  EARLIER. Leaving the rule unflipped answers "no move"; flipping the rects but not the rule
  answers index 0. Both turn this red. }
procedure TRtlTabStripTest.DraggingTowardTheReadingStartMovesTheTabEarlier;
var
  cap0, cap1, cap2: string;
  y: Integer;
begin
  Build(True, 3, 300);
  cap0 := FStrip.TabCaption(0);
  cap1 := FStrip.TabCaption(1);
  cap2 := FStrip.TabCaption(2);
  y := FStrip.HeaderMidY;

  FStrip.CallMouseDown(mbLeft, ScreenMid(2), y, [ssLeft]);
  FStrip.CallMouseMove(ScreenMid(1) + 1, y, [ssLeft]);
  FStrip.CallMouseUp(mbLeft, ScreenMid(1) + 1, y, [ssLeft]);

  AssertEquals('caption[0] unchanged', cap0, FStrip.TabCaption(0));
  AssertEquals('the dragged tab is now at index 1', cap2, FStrip.TabCaption(1));
  AssertEquals('and its old neighbour moved up', cap1, FStrip.TabCaption(2));
end;

{ The close (x) sits at the header's TRAILING edge, which is the left one when the strip
  reads right-to-left -- and, more to the point, the click that closes a tab has to land
  where the glyph was drawn. Both halves are asserted together because a close slot painted
  on one side and hit-tested on the other is the same class of bug as the arrow zone
  TRtlExclusionTest is guarding. }
procedure TRtlTabStripTest.CloseSlotSitsOnTheTrailingSideAndItsHitTestFollows;
var
  hdr, cls: TRect;
  probe: TStripCloseProbe;
begin
  Build(True, 3, 300, True);
  hdr := FStrip.TabRect(1);
  cls := FStrip.ToScreenRect(FStrip.TyTabCloseRect(1));
  AssertTrue('the close slot is non-empty', cls.Right > cls.Left);
  AssertTrue('it is inside its own header',
    (cls.Left >= hdr.Left) and (cls.Right <= hdr.Right));
  AssertTrue('and on the header''s left half, its trailing side when mirrored',
    cls.Right <= (hdr.Left + hdr.Right) div 2);

  probe := TStripCloseProbe.Create;
  try
    FStrip.OnTabClose := @probe.Handle;
    probe.Veto := True;             // keep the tab so the assertion is about the hit, not the removal
    FStrip.CallMouseDown(mbLeft, (cls.Left + cls.Right) div 2,
      (cls.Top + cls.Bottom) div 2);
    AssertEquals('a click on the drawn close slot fires OnTabClose once', 1, probe.Count);
    AssertEquals('for the tab it was drawn on', 1, probe.LastIndex);
  finally
    FStrip.OnTabClose := nil;
    probe.Free;
  end;
end;

{ The caption box is clipped off the close glyph, and the edge it gives up is the edge the
  close slot is ON -- which the reflection moved. Clipping the same edge as before leaves the
  caption squeezed into the few pixels of margin OUTSIDE the close slot and the rest of the
  header empty; the tab still looks plausible in a thumbnail, which is why this needs a probe
  and not an eyeball. One tab, so the caption ink in a given x range can only be this tab's,
  and the close glyph is excluded by scanning strictly outside the close slot. }
procedure TRtlTabStripTest.TheCaptionYieldsTheEdgeTheCloseSlotActuallyTook;
var
  bmp: TBGRABitmap;
  hdr, cls: TRect;
  beyond, before: Integer;
begin
  { A blue caption on a white header: TyTab's colour paints both the caption and the close
    glyph, so the two are told apart by WHERE they are, not by what colour they are. }
  Build(True, 1, 300, True, cTabInkCss);
  hdr := FStrip.TabRect(0);
  cls := FStrip.ToScreenRect(FStrip.TyTabCloseRect(0));
  AssertTrue('precondition: a close slot exists inside the header',
    (cls.Right > cls.Left) and (cls.Left >= hdr.Left) and (cls.Right <= hdr.Right));

  bmp := Shot;
  try
    beyond := ChannelInkCount(bmp, chBlue, cls.Right, hdr.Right);
    before := ChannelInkCount(bmp, chBlue, hdr.Left, cls.Left);
    AssertTrue('the caption occupies the header BEYOND the close slot', beyond > 0);
    AssertEquals('and nothing is drawn in the sliver on the far side of it', 0, before);
  finally
    bmp.Free;
  end;
end;

{ The two overflow arrows change ENDS, and each keeps the direction it scrolls. The back
  arrow leads the strip, so it belongs at the reading start -- the right edge here. Its field
  is still called FScrollLeftRect (renaming a published-adjacent member is a breaking change
  the plan rules out in §6.3.6), which is exactly why the direction is asserted by BEHAVIOUR
  and not by the name. }
procedure TRtlTabStripTest.OverflowArrowsSwapEndsAndKeepTheirScrollDirections;
var
  back, fwd: TRect;
  after: Integer;
begin
  Build(True, 12, 160);
  AssertTrue('precondition: the strip overflows', FStrip.TyMaxHeaderScroll > 0);
  back := FStrip.TyTabScrollLeftRect;
  fwd  := FStrip.TyTabScrollRightRect;
  AssertTrue('both arrows are drawn', (back.Right > back.Left) and (fwd.Right > fwd.Left));
  AssertEquals('the back arrow ends at the right edge', FStrip.Width, back.Right);
  AssertEquals('the forward arrow starts at the left edge', 0, fwd.Left);

  FStrip.CallMouseDown(mbLeft, (fwd.Left + fwd.Right) div 2, (fwd.Top + fwd.Bottom) div 2);
  after := FStrip.HeaderScroll;
  AssertTrue('clicking the forward arrow scrolls forward', after > 0);
  FStrip.CallMouseDown(mbLeft, (back.Left + back.Right) div 2, (back.Top + back.Bottom) div 2);
  AssertTrue('and clicking the back arrow scrolls back', FStrip.HeaderScroll < after);
end;

{ The chevrons turn round WITH the ends, and the net effect of doing both is that the arrow
  at each physical end is drawn identically whichever way the strip reads: the left end always
  shows the left-pointing one. Swapping the ends and not the glyphs leaves both chevrons
  pointing inward -- the "grip drawn on one side, grabbed on the other" defect of §5.5 -- and
  it is invisible to every geometry assertion, because the geometry is right.

  Asserted as an exact pixel comparison of the two arrow bands between an unmirrored and a
  mirrored render, which needs no assumption about how a chevron is shaped. The ink check
  stops an all-white comparison from passing the test vacuously. }
procedure TRtlTabStripTest.OverflowChevronsKeepPointingOffTheEndTheySitOn;
var
  ltr, rtl: TBGRABitmap;
  arrowW, w, bandH, x, y, diff: Integer;

  function Band(A: TBGRABitmap; AX0, AX1: Integer): Integer;
  begin
    Result := ChannelInkCount(A, chBlue, AX0, AX1);
  end;

begin
  Build(False, 12, 160, False, cTabInkCss);
  arrowW := FStrip.TyTabScrollLeftRect.Right;
  w      := FStrip.Width;
  bandH  := FStrip.TabHeight;
  AssertTrue('precondition: an arrow band is reserved', arrowW > 0);
  ltr := Shot;
  try
    FForm.Free; FForm := nil;
    Build(True, 12, 160, False, cTabInkCss);
    rtl := Shot;
    try
      AssertTrue('precondition: the left arrow actually drew a chevron',
        Band(ltr, 0, arrowW) > 0);
      diff := 0;
      for y := 0 to bandH - 1 do
        for x := 0 to w - 1 do
          if (x < arrowW) or (x >= w - arrowW) then
            if ltr.GetPixel(x, y) <> rtl.GetPixel(x, y) then Inc(diff);
      AssertEquals('both arrow bands are drawn identically whichever way the strip reads',
        0, diff);
    finally
      rtl.Free;
    end;
  finally
    ltr.Free;
  end;
end;

{ Scroll origin, the fourth consumer. The offset stays a reading-order quantity -- 0 is
  "showing the first tab" whichever way the strip reads -- so increasing it must slide the
  band toward the RIGHT here, the opposite of the unmirrored strip. Getting this wrong is
  §5.4 of the plan: the first frame looks right and it only goes wrong once you scroll. }
procedure TRtlTabStripTest.ScrollingForwardSlidesTheMirroredStripTowardTheRight;
var
  before: Integer;
  last: TRect;
begin
  Build(True, 12, 160);
  AssertTrue('precondition: the strip overflows', FStrip.TyMaxHeaderScroll > 0);
  AssertEquals('precondition: scroll starts at 0', 0, FStrip.HeaderScroll);
  before := FStrip.TabRect(0).Left;
  FStrip.SetHeaderScroll(40);
  AssertTrue('scrolling forward pushes tab 0 off the right side',
    FStrip.TabRect(0).Left > before);

  FStrip.ScrollTabIntoView(11);
  last := FStrip.TabRect(11);
  AssertTrue('and scrolling the last tab into view lands it inside the control',
    (last.Left >= 0) and (last.Right <= FStrip.Width));

  { ScrollTabs counts in TABS and works entirely in content space, so it needs no mirror of
    its own -- pinned here rather than assumed, because "positive Delta moves toward later
    tabs" is a sentence somebody could later decide means "moves right". }
  FStrip.ScrollTabs(-11);
  AssertEquals('stepping back 11 tabs returns to the start of the strip',
    0, FStrip.HeaderScroll);
end;

{ §6.3.1: a page is an ordinary container and its children are not mirrored -- and the page
  SURFACE itself has no left/right feature to mirror either, so TTyTabSheet was deliberately
  left untouched by this batch. Pinned as an exact pixel comparison, which is the only form
  of "we changed nothing here" that stays true when somebody edits the page's RenderTo. }
procedure TRtlTabStripTest.TabSheetIsPixelIdenticalWhicheverWayItReads;
var
  Form: TForm;
  Ctl: TTyStyleController;
  Sheet: TRtlSheetAccess;
  host: TBitmap;
  a, b: TBGRABitmap;
  x, y, diff: Integer;
begin
  Form := TForm.CreateNew(nil);
  try
    Ctl := TTyStyleController.Create(Form);
    Ctl.LoadThemeCss('TyTabSheet { background: #FF0000; border: 2px solid #0000FF; }');
    Sheet := TRtlSheetAccess.Create(Form);
    Sheet.Parent := Form;
    Sheet.Controller := Ctl;
    Sheet.Font.PixelsPerInch := 96;
    Sheet.SetBounds(0, 0, 120, 60);

    host := NewHost(120, 60);
    try
      Sheet.Render(host.Canvas, Rect(0, 0, 120, 60), 96);
      a := TBGRABitmap.Create(host);
    finally
      host.Free;
    end;
    try
      Sheet.BiDiMode := bdRightToLeft;
      host := NewHost(120, 60);
      try
        Sheet.Render(host.Canvas, Rect(0, 0, 120, 60), 96);
        b := TBGRABitmap.Create(host);
      finally
        host.Free;
      end;
      try
        diff := 0;
        for y := 0 to 59 do
          for x := 0 to 119 do
            if a.GetPixel(x, y) <> b.GetPixel(x, y) then Inc(diff);
        AssertEquals('the page surface is byte-identical in both directions', 0, diff);
      finally
        b.Free;
      end;
    finally
      a.Free;
    end;
  finally
    Form.Free;
  end;
end;

{ Arrow keys in a tab strip are LAYOUT direction, not text direction (§6.3.4 draws that
  line): the user presses the key that points at the tab they can see. So Left advances on a
  mirrored strip. Clamping at the ends is asserted too, because "swap the two branches" and
  "swap the two branches and lose a clamp" are one keystroke apart. }
procedure TRtlTabStripTest.ArrowKeysFollowTheEyeAndNotTheXAxis;
var
  k: Word;
begin
  Build(True, 3, 300);
  FStrip.TabIndex := 0;
  k := VK_LEFT;  FStrip.CallKeyDown(k);
  AssertEquals('Left moves to the next tab, which is the one to its left', 1, FStrip.TabIndex);
  AssertEquals('and the key is consumed', 0, k);
  k := VK_RIGHT; FStrip.CallKeyDown(k);
  AssertEquals('Right moves back', 0, FStrip.TabIndex);
  k := VK_RIGHT; FStrip.CallKeyDown(k);
  AssertEquals('and clamps at the first tab', 0, FStrip.TabIndex);
  FStrip.TabIndex := 2;
  k := VK_LEFT;  FStrip.CallKeyDown(k);
  AssertEquals('Left clamps at the last tab', 2, FStrip.TabIndex);
end;

{ Home / End / Ctrl+Tab are LOGICAL ends and a logical cycle, not visual ones, so mirroring
  must leave all three alone (§6.3.3). Asserted because the flip lives in the same case
  statement and is one label away from catching them. }
procedure TRtlTabStripTest.HomeEndAndCtrlTabStayLogicalUnderMirroring;
var
  k: Word;
begin
  Build(True, 3, 300);
  FStrip.TabIndex := 1;
  k := VK_END;  FStrip.CallKeyDown(k);
  AssertEquals('End goes to the LAST tab', 2, FStrip.TabIndex);
  k := VK_HOME; FStrip.CallKeyDown(k);
  AssertEquals('Home goes to the FIRST tab', 0, FStrip.TabIndex);
end;

{ TabPosition has no left-edge or right-edge tabs -- the band is always the top one
  (docs/KNOWN_GAPS.md records the gap) -- so the page body's horizontal edges have nothing
  to mirror, and AdjustClientRect keeps insetting only the top. Pinned so that nobody builds
  a mirroring branch for a feature that does not exist (§6.3.7), and so that the day left/
  right tabs DO arrive, this test is the thing that has to be rewritten on purpose. }
procedure TRtlTabStripTest.ThePageBodyHasNoHorizontalEdgeToMirror;
var
  ltrBody, rtlBody: TRect;
begin
  Build(False, 3, 300);
  ltrBody := FStrip.DisplayRect;
  FForm.Free; FForm := nil;

  Build(True, 3, 300);
  rtlBody := FStrip.DisplayRect;
  AssertEquals('body left edge unmoved',   ltrBody.Left,   rtlBody.Left);
  AssertEquals('body right edge unmoved',  ltrBody.Right,  rtlBody.Right);
  AssertEquals('body top edge unmoved',    ltrBody.Top,    rtlBody.Top);
  AssertEquals('body bottom edge unmoved', ltrBody.Bottom, rtlBody.Bottom);
end;

{ TTyPageControl contributes no geometry of its own -- it forwards to the strip engine -- so
  the pager mirrors its HEADER and nothing else. Its pages are ordinary containers whose own
  children are not mirrored (§6.3.1); asserted through IndexOfPageAt, which answers over the
  whole body width and must keep doing so from both sides. }
procedure TRtlTabStripTest.MirroredPageControlMovesItsTabsAndNotItsPages;
var
  Form: TForm;
  PC: TTyPageControl;
  bodyBefore, bodyAfter: TRect;
begin
  Form := TForm.CreateNew(nil);
  try
    PC := TTyPageControl.Create(Form);
    PC.Parent := Form;
    PC.Font.PixelsPerInch := 96;
    PC.SetBounds(0, 0, 300, 200);
    PC.AddPage('One');
    PC.AddPage('Two');
    bodyBefore := PC.DisplayRect;
    PC.BiDiMode := bdRightToLeft;
    bodyAfter := PC.DisplayRect;

    AssertEquals('the pager''s first tab moved to the right edge',
      PC.Width, PC.TabRect(0).Right);
    AssertTrue('and its second tab is to the left of it',
      PC.TabRect(1).Right = PC.TabRect(0).Left);
    AssertEquals('the page body is unchanged (left)',  bodyBefore.Left,  bodyAfter.Left);
    AssertEquals('the page body is unchanged (right)', bodyBefore.Right, bodyAfter.Right);
    AssertEquals('a point near the body''s left edge still names the active page',
      0, PC.IndexOfPageAt(4, bodyAfter.Top + 4));
    AssertEquals('and so does one near its right edge',
      0, PC.IndexOfPageAt(PC.Width - 4, bodyAfter.Top + 4));
  finally
    Form.Free;
  end;
end;

{ TTyTabSet adds a caption list and nothing geometric, so it inherits the mirrored strip
  whole. Asserted rather than assumed: it is the one member of the family with no page body,
  and the baseline rail it draws instead of a frame is laid out from the same band. }
procedure TRtlTabStripTest.TabSetInheritsTheMirroredStrip;
var
  Form: TForm;
  TS: TTyTabSet;
  r0: TRect;
begin
  Form := TForm.CreateNew(nil);
  try
    TS := TTyTabSet.Create(Form);
    TS.Parent := Form;
    TS.Font.PixelsPerInch := 96;
    TS.SetBounds(0, 0, 300, 32);
    TS.Tabs.Add('A');
    TS.Tabs.Add('B');
    TS.Tabs.Add('C');
    TS.BiDiMode := bdRightToLeft;
    r0 := TS.TabRect(0);
    AssertEquals('tab 0 ends at the right edge', TS.Width, r0.Right);
    AssertTrue('tab 2 is further left than tab 0', TS.TabRect(2).Left < r0.Left);
    AssertEquals('and a click in tab 0 as drawn selects tab 0',
      0, TS.IndexOfTabAt((r0.Left + r0.Right) div 2, (r0.Top + r0.Bottom) div 2));
  finally
    Form.Free;
  end;
end;

{ --------------------------------------------------------------- TRtlGridTest }

procedure TRtlGridAccess.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin RenderTo(ACanvas, ARect, APPI); end;
function TRtlGridAccess.ColLeft(ACol: Integer): Integer;
begin Result := ColumnLeftPx(ACol); end;
function TRtlGridAccess.ColWidth(ACol: Integer): Integer;
begin Result := ColumnWidthPx(ACol); end;
function TRtlGridAccess.ColAt(AX: Integer): Integer;
begin Result := ColumnAtX(AX); end;
function TRtlGridAccess.Hit(AX, AY: Integer): TTyGridHit;
begin Result := CellAt(AX, AY); end;
function TRtlGridAccess.Cell(ACol, ARow: Integer): TRect;
begin Result := CellRect(ACol, ARow); end;
function TRtlGridAccess.CellVis(ACol, ARow: Integer): TRect;
begin Result := CellVisibleRect(ACol, ARow); end;
function TRtlGridAccess.ClipCol(ACol: Integer; var ALeft, AWidth: Integer): Boolean;
begin Result := ClipColToBody(GridMetrics, ACol, ALeft, AWidth); end;
function TRtlGridAccess.Divider(AX: Integer): Integer;
begin Result := DividerAtX(AX); end;
function TRtlGridAccess.Metrics: TTyGridMetrics;
begin Result := GridMetrics; end;
function TRtlGridAccess.ViewW: Integer;
begin Result := ViewportW; end;
function TRtlGridAccess.FrozenW: Integer;
begin Result := FrozenWidthPx; end;
function TRtlGridAccess.HBar: TTyScrollBar;
var i: Integer;
begin
  Result := nil;
  for i := 0 to ControlCount - 1 do
    if (Controls[i] is TTyScrollBar)
       and (TTyScrollBar(Controls[i]).Kind = sbHorizontal) then
      Exit(TTyScrollBar(Controls[i]));
end;
function TRtlGridAccess.SelBounds: TRect;
begin Result := SelectionBoundsRect; end;
procedure TRtlGridAccess.SetLevel(Sender: TObject; ARow: Integer; var ALevel: Integer);
begin if ARow > 0 then ALevel := 1 else ALevel := 0; end;
procedure TRtlGridAccess.SetHasKids(Sender: TObject; ARow: Integer; var AHas: Boolean);
begin AHas := True; end;
function TRtlFilterListAccess.Mirrors: Boolean;
begin Result := RtlRowLayout; end;
function TRtlGridAccess.FunnelRect(ACol: Integer): TRect;
begin Result := HeaderFilterRect(ACol, ScaleI(Header.Height)); end;
function TRtlGridAccess.TreeToggle(ARow: Integer): TRect;
begin Result := TreeToggleRect(ARow); end;
function TRtlGridAccess.BoxRect(ACol, ARow: Integer): TRect;
begin Result := CheckBoxRect(ACol, ARow); end;
function TRtlGridAccess.BtnRect(ACol, ARow: Integer): TRect;
begin Result := CellButtonRect(ACol, ARow); end;
function TRtlGridAccess.StarRect(ACol, ARow, AStar: Integer): TRect;
begin Result := RatingStarRect(ACol, ARow, AStar); end;
function TRtlGridAccess.DotsRect(ACol, ARow: Integer): TRect;
begin Result := EllipsisRect(ACol, ARow); end;
function TRtlGridAccess.HandleRect: TRect;
begin Result := FillHandleRect; end;
function TRtlGridAccess.GroupToggle(APos: Integer): TRect;
begin Result := GroupToggleRect(APos); end;
function TRtlGridAccess.Sc(AValue: Integer): Integer;
begin Result := ScaleI(AValue); end;
procedure TRtlGridAccess.PressDown(X, Y: Integer);
begin MouseDown(mbLeft, [], X, Y); end;
procedure TRtlGridAccess.PressMove(X, Y: Integer);
begin MouseMove([ssLeft], X, Y); end;
procedure TRtlGridAccess.PressUp(X, Y: Integer);
begin MouseUp(mbLeft, [], X, Y); end;
procedure TRtlGridAccess.ClickAt(X, Y: Integer);
begin MouseDown(mbLeft, [], X, Y); MouseUp(mbLeft, [], X, Y); end;
procedure TRtlGridAccess.Key(AKey: Word);
var k: Word;
begin k := AKey; KeyDown(k, []); end;
procedure TRtlGridAccess.Remeasure;
begin UpdateScrollBars; end;
procedure TRtlGridAccess.ScrollTo(AX: Integer);
begin ScrollX := AX; end;

procedure TRtlGridTest.Build(ARtl: Boolean; const AWidths: array of Integer;
  ARows: Integer; AWidth: Integer);
var
  i, r, c: Integer;
  col: TTyColumn;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 640, 480);
  FCtl := TTyStyleController.Create(nil);
  { No sheet is loaded over the stock theme anywhere in this class. The one test that reads
    pixels out of a chrome band measures the band's WIDTH instead of giving it a loud colour,
    which keeps it honest about what a user sees and avoids this repo's recorded trap: a sheet
    naming a couple of keys and nothing else drops every token the rest of the control needs. }
  FG := TRtlGridAccess.Create(FForm);
  FG.Parent := FForm;
  FG.Controller := FCtl;
  FG.Font.PixelsPerInch := 96;
  { The bar must never appear on its own in these fixtures: a vertical bar narrows the
    viewport, and the viewport width is the mirror's axis of reflection. Left to "auto" a
    fixture that grows a row would silently reflect about a different number than its LTR
    twin, and every coordinate assertion below would be off by the bar's width for a reason
    that has nothing to do with mirroring. }
  FG.VertScrollBarMode := gsbNever;
  FG.SetBounds(0, 0, AWidth, 240);
  for i := 0 to High(AWidths) do
  begin
    col := FG.Header.Columns.Add as TTyColumn;
    col.Width := AWidths[i];
    col.Text := Chr(Ord('A') + i);
  end;
  FG.RowCount := ARows;
  for r := 0 to ARows - 1 do
    for c := 0 to High(AWidths) do
      FG.Cells[c, r] := Chr(Ord('a') + c) + IntToStr(r);
  if ARtl then FG.BiDiMode := bdRightToLeft;
  FG.Remeasure;
end;

function TRtlGridTest.Shot(AWidth, AHeight: Integer): TBGRABitmap;
var
  Bmp: TBitmap;
begin
  Bmp := TBitmap.Create;
  try
    Bmp.SetSize(AWidth, AHeight);
    FG.Render(Bmp.Canvas, Rect(0, 0, AWidth, AHeight), 96);
    Result := TBGRABitmap.Create(Bmp);
  finally
    Bmp.Free;
  end;
end;

procedure TRtlGridTest.TearDown;
begin
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

{ --- the column axis ------------------------------------------------------- }

{ The headline claim, and the cheapest thing to get wrong in a way that looks right: it is
  not enough that the columns are in some mirrored order, the FIRST one has to be flush
  against the reading start. Widths are deliberately unequal so a fixture that is accidentally
  symmetric cannot pass. }
procedure TRtlGridTest.ColumnZeroSitsAgainstTheRightEdgeAndTheRestPackLeftwards;
begin
  Build(True, [60, 90, 50]);
  AssertEquals('column 0 ends flush against the viewport''s right edge',
    FG.ViewW, FG.ColLeft(0) + FG.ColWidth(0));
  AssertEquals('column 1 ends where column 0 begins',
    FG.ColLeft(0), FG.ColLeft(1) + FG.ColWidth(1));
  AssertEquals('column 2 ends where column 1 begins',
    FG.ColLeft(1), FG.ColLeft(2) + FG.ColWidth(2));
  AssertTrue('and the columns run right to left, not left to right',
    (FG.ColLeft(0) > FG.ColLeft(1)) and (FG.ColLeft(1) > FG.ColLeft(2)));
end;

{ A reflection of a gapless tiling is gapless -- that is the whole argument for reflecting
  the finished layout instead of accumulating backwards, so it needs an assertion rather than
  a comment. A backwards accumulation that rounds anywhere grows a 1px seam here. }
procedure TRtlGridTest.MirroredColumnsTileWithNoSeamAndKeepEveryWidth;
var
  i: Integer;
  Ltr: array[0..2] of Integer;
begin
  Build(False, [60, 90, 50]);
  for i := 0 to 2 do Ltr[i] := FG.ColWidth(i);
  TearDown;
  Build(True, [60, 90, 50]);
  for i := 0 to 2 do
    AssertEquals(Format('column %d keeps its width', [i]), Ltr[i], FG.ColWidth(i));
  for i := 0 to 1 do
    AssertEquals(Format('no seam between columns %d and %d', [i, i + 1]),
      FG.ColLeft(i), FG.ColLeft(i + 1) + FG.ColWidth(i + 1));
end;

{ THE inverse sweep. ColumnAtX is written as ColumnLeftPx's inverse THROUGH that same
  function, so this ought to be free -- and that is exactly why it is worth pinning: the day
  someone "optimises" ColumnAtX into its own accumulation loop, this is the test that turns
  red instead of the users. Every device x, both directions, compared against the reflection
  of the unmirrored grid's answer. }
procedure TRtlGridTest.ColumnAtXIsTheExactPixelInverseOfTheMirroredTiling;
var
  x, vw: Integer;
  Ltr: array of Integer;
begin
  Build(False, [60, 90, 50]);
  vw := FG.ViewW;
  SetLength(Ltr, vw);
  for x := 0 to vw - 1 do Ltr[x] := FG.ColAt(x);
  TearDown;
  Build(True, [60, 90, 50]);
  AssertEquals('same viewport, so the reflection axis is the same', vw, FG.ViewW);
  for x := 0 to vw - 1 do
    AssertEquals(Format('x=%d answers the mirror of the unmirrored grid''s answer', [x]),
      Ltr[vw - 1 - x], FG.ColAt(x));
end;

{ Paint-then-hit. The sweep above proves the hit test mirrors; this proves it mirrors the
  same way the INK did. The two can disagree -- that is the failure this whole programme
  exists around -- so the probe reads a pixel the header actually filled and asks the hit
  test to name it. }
procedure TRtlGridTest.TheHitTestNamesTheColumnThePaintFilled;
var
  Bmp: TBGRABitmap;
  hdrY, i, mid: Integer;
  h: TTyGridHit;
begin
  Build(True, [60, 90, 50]);
  FG.Header.Options := FG.Header.Options + [hoVisible];
  Bmp := Shot;
  try
    hdrY := FG.Metrics.FrozenTop div 2;
    if hdrY < 2 then hdrY := 2;
    for i := 0 to 2 do
    begin
      mid := FG.ColLeft(i) + FG.ColWidth(i) div 2;
      AssertTrue(Format('column %d was painted somewhere on screen', [i]),
        (mid >= 0) and (mid < Bmp.Width));
      h := FG.Hit(mid, hdrY);
      AssertEquals(Format('the header hit at the middle of the painted column %d names it',
        [i]), i, h.Col);
    end;
    { And the cell band, which goes through a different branch of CellAt. }
    for i := 0 to 2 do
    begin
      mid := FG.ColLeft(i) + FG.ColWidth(i) div 2;
      h := FG.Hit(mid, FG.Metrics.FrozenTop + 4);
      AssertEquals(Format('and so does the cell hit for column %d', [i]), i, h.Col);
    end;
  finally
    Bmp.Free;
  end;
end;

{ A reflection is not a reversal. Reversing the ORDER would put column 2 where column 0's
  mirror image is only when every width is equal -- which is why the widths here are not.
  This separates "mirrored" from "I reversed the index and called it mirroring". }
procedure TRtlGridTest.ColumnOrderIsMirroredNotReversed;
begin
  Build(True, [60, 90, 50]);
  { Reversal would give column 0 the width-50 slot at the right; reflection gives it its own
    60px, and the left edge lands 60 short of the viewport, not 50. }
  AssertEquals('column 0 occupies its own width against the right edge',
    FG.ViewW - 60, FG.ColLeft(0));
  AssertEquals('and column 2 is the one flush with the left edge',
    FG.ViewW - 60 - 90 - 50, FG.ColLeft(2));
end;

{ --- the row-header gutter ------------------------------------------------- }

procedure TRtlGridTest.TheRowHeaderGutterMovesToTheRightEdge;
var
  h: TTyGridHit;
  bodyY: Integer;
begin
  Build(True, [60, 90, 50]);
  FG.ShowIndicator := True;
  FG.IndicatorWidth := 30;
  bodyY := FG.Metrics.FrozenTop + 4;
  h := FG.Hit(FG.ViewW - 4, bodyY);
  AssertTrue('a click at the right edge lands in the row-header gutter',
    h.Part = ghpIndicator);
  h := FG.Hit(4, bodyY);
  AssertTrue('and one at the left edge does not', h.Part <> ghpIndicator);
end;

{ FOUR expressions used to say `x < ScaleI(FIndicatorWidth)`, in four functions, and they
  agreed because they were all measured from x=0. Mirrored they must all move together, and
  a test that only exercised one of them would pass with three of the four still on the old
  side. This drives every one: the hit test, the row-height divider, the drag-row gesture,
  and (in the sibling test below) the paint. }
procedure TRtlGridTest.AllFourGutterConsumersMovedTogether;
var
  M: TTyGridMetrics;
  rowBottom, gx, lx, before: Integer;
begin
  Build(True, [60, 90, 50]);
  FG.ShowIndicator := True;
  FG.IndicatorWidth := 30;
  FG.ShowRowNumbers := True;
  M := FG.Metrics;
  gx := FG.ViewW - 4;      { inside the mirrored gutter }
  lx := 4;                 { where the gutter used to be }

  { 1. the hit test }
  AssertTrue('CellAt answers the gutter on the right',
    FG.Hit(gx, M.FrozenTop + 4).Part = ghpIndicator);

  { 2. the row-height grip, which is only offered inside the gutter. Driven through the
       MOUSE rather than through RowDividerAtY, because that function is private -- and
       because the height actually changing is the honest evidence. }
  rowBottom := TyGridRowRect(FG.FixedRows, M).Bottom;
  FG.PressDown(gx, rowBottom);
  FG.PressMove(gx, rowBottom + 12);
  FG.PressUp(gx, rowBottom + 12);
  AssertTrue('a drag inside the mirrored gutter resizes the row',
    FG.RowHeights[FG.FixedRows] > 0);
  AssertTrue('and it actually grew', FG.RowHeights[FG.FixedRows] > 12);

  { 3. the same drag where the gutter USED to be must do nothing at all. }
  before := FG.RowHeights[FG.FixedRows];
  FG.PressDown(lx, rowBottom);
  FG.PressMove(lx, rowBottom + 24);
  FG.PressUp(lx, rowBottom + 24);
  AssertEquals('and the same drag on the left edge changes nothing',
    before, FG.RowHeights[FG.FixedRows]);
end;

{ The paint half of the same four. Ink, not arithmetic: a gutter whose numbers still render
  on the left is exactly the "painted one side, answers the other" defect, and no geometry
  assertion above would notice. }
procedure TRtlGridTest.RowNumberInkLandsInsideTheMirroredGutter;
var
  Bmp, Bare: TBGRABitmap;
  M: TTyGridMetrics;

  { Pixels that DIFFER between two shots of the same grid, one with row numbers and one
    without -- i.e. the numbers themselves. Comparing the two shots rather than counting
    "non-background" pixels is what makes this probe honest: the strip where the gutter used
    to be is full of cell text either way, so an absolute ink count there is large no matter
    which side the numbers went to, and a mirror that moved nothing would still pass. }
  function Delta(AL, AR, ATop, ABot: Integer): Integer;
  var x, y: Integer;
  begin
    Result := 0;
    for y := ATop to ABot - 1 do
      for x := AL to AR - 1 do
        if Bmp.GetPixel(x, y) <> Bare.GetPixel(x, y) then Inc(Result);
  end;

var
  leftInk, rightInk, x, y, firstX, inner: Integer;
begin
  Build(True, [60, 90, 50]);
  FG.ShowIndicator := True;
  FG.IndicatorWidth := 30;
  M := FG.Metrics;
  Bare := Shot;
  try
    FG.ShowRowNumbers := True;
    Bmp := Shot;
    try
      rightInk := Delta(FG.ViewW - 30, FG.ViewW, M.FrozenTop + 1, M.FrozenTop + 18);
      leftInk  := Delta(0, 30, M.FrozenTop + 1, M.FrozenTop + 18);
      AssertTrue('turning row numbers on puts ink in the gutter on the right',
        rightInk > 0);
      AssertEquals('and puts none in the strip where the gutter used to be',
        0, leftInk);

      { WHICH SIDE OF THE GUTTER, not merely which gutter. The number hugs the edge that
        faces the DATA, with the slot's 4px breathing gap between the two -- mirrored, that
        is the gutter's left edge. A slot that was moved to the correct band but inset on the
        wrong end still paints inside the gutter and still satisfies both counts above; it
        differs by four pixels, which is exactly the size of miss this repo has let through
        before. }
      inner := FG.ViewW - 30;
      firstX := -1;
      for x := inner to FG.ViewW - 1 do
      begin
        for y := M.FrozenTop + 1 to M.FrozenTop + 17 do
          if Bmp.GetPixel(x, y) <> Bare.GetPixel(x, y) then
          begin
            firstX := x;
            Break;
          end;
        if firstX >= 0 then Break;
      end;
      AssertTrue('the number was found', firstX >= 0);
      AssertTrue('and the breathing gap is between it and the data, not at the window edge',
        firstX - inner >= 3);
    finally
      Bmp.Free;
    end;
  finally
    Bare.Free;
  end;
end;

{ --- the frozen bands ------------------------------------------------------ }

procedure TRtlGridTest.FrozenColumnsPinToTheRightEdgeAndDoNotScroll;
var
  before: Integer;
begin
  Build(True, [60, 90, 50, 80, 70], 6, 200);
  FG.FixedCols := 1;
  FG.Remeasure;
  before := FG.ColLeft(0);
  AssertEquals('the frozen column is flush with the reading start',
    FG.ViewW, before + FG.ColWidth(0));
  FG.ScrollTo(40);
  AssertEquals('and scrolling does not move it', before, FG.ColLeft(0));
  AssertTrue('while a body column does move', FG.ColLeft(2) <> 0);
  { The other half of the band swap, from the LEFT-frozen side: CellPane has to name the
    band GridMetrics made thick, or the frozen column is intersected with an empty pane and
    disappears while ColLeft above still reads perfectly. }
  AssertFalse('and the frozen column still has visible pixels',
    IsRectEmpty(FG.CellVis(0, 0)));
  AssertEquals('all of them', FG.ColWidth(0),
    FG.CellVis(0, 0).Right - FG.CellVis(0, 0).Left);
end;

{ The boundary between the two bands -- decision (2). Mirrored, the frozen strip is against
  the right edge and the scrolling band is what is left, so gpBody's RIGHT edge is the seam.
  Four expressions used to read FrozenWidthPx as a left-hand threshold; if any one of them
  stayed, a body column scrolled under the frozen strip is either hit-testable through it or
  clipped away on the wrong side. }
procedure TRtlGridTest.TheBodyBandStartsWhereTheFrozenBandEnds;
var
  M: TTyGridMetrics;
  body: TRect;
  h: TTyGridHit;
begin
  Build(True, [60, 90, 50, 80, 70], 6, 200);
  FG.FixedCols := 1;
  FG.Remeasure;
  FG.ScrollTo(60);
  M := FG.Metrics;
  body := TyGridPaneRect(M, gpBody);
  AssertEquals('the body band ends where the frozen strip begins',
    FG.ViewW - FG.FrozenW, body.Right);
  AssertEquals('and it starts at the viewport''s left edge', 0, body.Left);
  { A pixel just inside the frozen strip must answer the frozen column, never the body
    column scrolled underneath it. }
  h := FG.Hit(body.Right + 2, M.FrozenTop + 4);
  AssertEquals('a pixel inside the frozen strip answers the frozen column', 0, h.Col);
end;

{ TTyCustomGrid has a right-frozen band too (FixedColsRight), which the scoping document
  never mentions. Mirrored it swaps sides with the left one -- and the two halves of that
  swap live in different functions (GridMetrics' band thicknesses and CellPane's pane
  names). Change one and the cell is clipped against the opposite band, producing an empty
  rect and a column that silently vanishes. }
procedure TRtlGridTest.ARightFrozenColumnMovesToTheLeftEdge;
var
  last: Integer;
begin
  Build(True, [60, 90, 50, 80, 70], 6, 200);
  FG.FixedColsRight := 1;
  FG.Remeasure;
  last := FG.Header.Columns.Count - 1;
  AssertEquals('the right-frozen column is flush with the viewport''s LEFT edge',
    0, FG.ColLeft(last));
  { The swap has TWO halves in two different functions -- GridMetrics decides how THICK each
    band is, CellPane decides which band a column belongs to -- and the unclipped rect above
    sees neither. Only the CLIPPED rect does: get one half without the other and the cell is
    intersected with the band on the opposite side, which is empty, and the column silently
    disappears while every coordinate still reads correctly. }
  AssertFalse('its VISIBLE rect is not empty -- both halves of the band swap happened',
    IsRectEmpty(FG.CellVis(last, 0)));
  AssertEquals('and nothing of it was clipped away', FG.ColWidth(last),
    FG.CellVis(last, 0).Right - FG.CellVis(last, 0).Left);
  FG.ScrollTo(30);
  AssertEquals('scrolling leaves it there', 0, FG.ColLeft(last));
end;

{ A body column scrolled under the frozen strip must be cut back to the band it is allowed
  to paint in -- and mirrored, the side it overflows is the RIGHT one. The unmirrored rule
  clips only the left, which leaves the header section, the group subtotal and the footer
  cell of a scrolled column painting straight over the frozen column pinned beside them:
  two numbers on top of each other, and nothing in the geometry that looks wrong.

  Asserted on ClipColToBody itself because that IS the shared source the three renderers
  call; a pixel probe would test one of the three and let the other two rot. }
procedure TRtlGridTest.AScrolledBodyColumnIsClippedAtTheFrozenBandsEdge;
var
  l, w, seam: Integer;
begin
  Build(True, [60, 90, 50, 80, 70], 6, 200);
  FG.FixedCols := 1;
  FG.Remeasure;
  FG.ScrollTo(30);
  seam := FG.ViewW - FG.FrozenW;

  l := FG.ColLeft(1);
  w := FG.ColWidth(1);
  AssertTrue('precondition: column 1 really does run under the frozen strip',
    l + w > seam);
  AssertTrue('and it survives the clip', FG.ClipCol(1, l, w));
  AssertEquals('clipped exactly at the frozen band''s edge', seam, l + w);
  AssertTrue('and nothing was taken off its other end', l = FG.ColLeft(1));

  { The frozen column itself is never clipped -- it IS the band. }
  l := FG.ColLeft(0);
  w := FG.ColWidth(0);
  AssertTrue('the frozen column survives', FG.ClipCol(0, l, w));
  AssertEquals('untouched', FG.ColWidth(0), w);
end;

{ --- the scroll origin ----------------------------------------------------- }

{ DECISION (1), pinned. FScrollX keeps its meaning: it is how far the body has scrolled AWAY
  from the reading start, so ScrollX = 0 shows column 0 -- which mirrored is at the RIGHT.
  That is Windows' own answer for a mirrored horizontal bar (Position = Min shows the reading
  start), and it is the only choice under which the same number means the same thing in both
  directions, so a form that saves and restores ScrollX survives a BiDiMode change. }
procedure TRtlGridTest.ScrollXZeroShowsTheReadingStartWhicheverWayItReads;
var
  ltrLeft: Integer;
begin
  Build(False, [60, 90, 50, 80, 70], 6, 200);
  AssertEquals('unmirrored, ScrollX=0 puts column 0 at the left edge', 0, FG.ColLeft(0));
  ltrLeft := FG.ColLeft(0);
  TearDown;
  Build(True, [60, 90, 50, 80, 70], 6, 200);
  AssertEquals('mirrored, ScrollX=0 puts column 0 flush with the RIGHT edge',
    FG.ViewW, FG.ColLeft(0) + FG.ColWidth(0));
  AssertTrue('which is not where it was', FG.ColLeft(0) <> ltrLeft);
end;

procedure TRtlGridTest.ScrollingForwardSlidesTheBodyTowardTheRight;
var
  before: Integer;
begin
  Build(True, [60, 90, 50, 80, 70], 6, 200);
  before := FG.ColLeft(3);
  FG.ScrollTo(40);
  AssertEquals('increasing ScrollX slides the body toward the right by that much',
    before + 40, FG.ColLeft(3));
end;

{ LeftCol is the grid''s public answer to "where is the viewport", and hosts persist it
  alongside ScrollX. It is a LOGICAL answer -- the first scrollable column with pixels in the
  body band -- so mirroring must not change it for a given scroll offset, and the numbers
  below are asserted against the unmirrored grid to say exactly that.

  It is also the one x-axis consumer whose comparison operator carries the direction: written
  against screen coordinates it answers the column at the far END of the strip, because in a
  mirrored tiling every column''s screen right edge is large. That answer is not obviously
  wrong -- it is a valid column index -- which is why this needs a guard rather than a look. }
procedure TRtlGridTest.LeftColNamesTheFirstColumnInsideTheBodyBandEitherWay;
var
  ltrUnscrolled, ltrScrolled: Integer;
begin
  Build(False, [60, 90, 50, 80, 70], 6, 200);
  FG.FixedCols := 1;
  FG.Remeasure;
  ltrUnscrolled := FG.LeftCol;
  FG.ScrollTo(95);
  ltrScrolled := FG.LeftCol;
  AssertEquals('precondition: scrolling past column 1 moves LeftCol on',
    ltrUnscrolled + 1, ltrScrolled);
  TearDown;

  Build(True, [60, 90, 50, 80, 70], 6, 200);
  FG.FixedCols := 1;
  FG.Remeasure;
  AssertEquals('mirrored, an unscrolled grid names the same first body column',
    ltrUnscrolled, FG.LeftCol);
  FG.ScrollTo(95);
  AssertEquals('and the same one after the same scroll', ltrScrolled, FG.LeftCol);
end;

{ TTyScrollBar deliberately does not read BiDiMode -- it mirrors only when a host sets
  MirrorHorizontal, precisely so the grid can make this call for itself. The vertical bar is
  a different matter and is pinned NOT to move; see TRtlExclusionTest. }
procedure TRtlGridTest.TheHorizontalBarIsToldToMirrorAndTheVerticalOneIsNot;
begin
  Build(True, [60, 90, 50, 80, 70], 6, 200);
  FG.HorzScrollBarMode := gsbAlways;
  FG.Remeasure;
  AssertNotNull('the grid has an embedded horizontal bar', FG.HBar);
  AssertTrue('the grid turns its horizontal bar''s mirroring on',
    FG.HBar.MirrorHorizontal);
  TearDown;
  Build(False, [60, 90, 50, 80, 70], 6, 200);
  FG.HorzScrollBarMode := gsbAlways;
  FG.Remeasure;
  AssertFalse('and leaves it off when the grid reads left to right',
    FG.HBar.MirrorHorizontal);
end;

{ ScrollIntoView compares a cell rect against the body band. Mirrored, "past the end" is the
  LEFT edge, and the branch that adds to ScrollX is the one testing the other side. Written
  as a reflection rather than a second pair of branches, so this test is really asking
  whether the reflection was applied to BOTH rects. }
procedure TRtlGridTest.ScrollIntoViewChasesTheCellOutTheCorrectEnd;
var
  after: Integer;
begin
  Build(True, [60, 90, 50, 80, 70], 6, 200);
  AssertEquals('starts unscrolled', 0, FG.ScrollX);
  FG.ScrollIntoView(4, 0);
  after := FG.ScrollX;
  AssertTrue('bringing the last column into view scrolls forward', after > 0);
  AssertTrue('and it is now inside the viewport',
    (FG.ColLeft(4) >= 0) and (FG.ColLeft(4) + FG.ColWidth(4) <= FG.ViewW));
  FG.ScrollIntoView(0, 0);
  AssertEquals('and coming back to column 0 returns to the reading start', 0, FG.ScrollX);
end;

{ --- resize and drag ------------------------------------------------------- }

{ The resize grip is a column's TRAILING edge -- right in LTR, LEFT once mirrored. Getting
  this wrong is not subtle in behaviour but is invisible in a screenshot: the grip is offered
  on the boundary between the same two columns either way, and the only symptom is that the
  drag widens the neighbour. }
procedure TRtlGridTest.ResizeGripGrabsTheMirroredColumnEdgeNotTheLtrOne;
begin
  Build(True, [60, 90, 50]);
  FG.Header.Options := FG.Header.Options + [hoColumnResize];
  AssertEquals('the grip for column 0 is on its left edge once mirrored',
    0, FG.Divider(FG.ColLeft(0)));
  AssertEquals('and its right edge -- the viewport edge -- is not a grip at all',
    -1, FG.Divider(FG.ColLeft(0) + FG.ColWidth(0)));
  AssertEquals('column 1''s grip is likewise on its left edge',
    1, FG.Divider(FG.ColLeft(1)));
end;

procedure TRtlGridTest.DraggingAwayFromTheReadingStartWidensTheColumn;
var
  edge: Integer;
begin
  Build(True, [60, 90, 50]);
  FG.Header.Options := FG.Header.Options + [hoColumnResize];
  edge := FG.ColLeft(0);
  FG.PressDown(edge, 4);
  FG.PressMove(edge - 20, 4);
  AssertEquals('dragging the grip away from the right edge widens column 0',
    80, FG.Header.Columns.Items[0].Width);
  FG.PressMove(edge + 10, 4);
  AssertEquals('and dragging it back toward that edge narrows it',
    50, FG.Header.Columns.Items[0].Width);
  FG.PressUp(edge + 10, 4);
end;

{ --- header chrome --------------------------------------------------------- }

procedure TRtlGridTest.AHeaderClickSortsTheColumnUnderThePointerNotItsLtrTwin;
var
  hdrY: Integer;
begin
  { Width 200 = exactly the three columns, so the strip is full and the two probe x's below
    are real screen coordinates rather than coordinates derived from the very function under
    test. A wider fixture leaves blank space, and mirrored that blank space is on the LEFT --
    x=4 would then be nowhere at all and the test would fail for the wrong reason. }
  Build(True, [60, 90, 50], 6, 200);
  FG.Header.Options := FG.Header.Options + [hoVisible, hoHeaderClickAutoSort];
  hdrY := 4;
  { x deep inside the LEFTMOST painted header cell, which mirrored is column 2. Unmirrored
    the same x is column 0 -- so this single assertion separates "mirrored" from "mirrored
    in the paint only". }
  FG.ClickAt(4, hdrY);
  AssertEquals('the click sorted the column painted under it',
    2, FG.Header.SortColumn);
  FG.ClickAt(FG.ViewW - 4, hdrY);
  AssertEquals('and a click at the right edge sorts column 0',
    0, FG.Header.SortColumn);
end;

{ The funnel had TWO independent expressions for its centre: RenderHeaderSections computed
  `r.Right - 10 - gs` and HeaderFilterRect computed `l + w - 10 - gs`. They agreed because
  r.Right happened to equal l + w -- an agreement by coincidence, the same shape as
  TTyCheckListBox's toggle in phase 3. Unified into HeaderFunnelCenterX before mirroring;
  this pins that the hit rect really is centred on the painted glyph. }
procedure TRtlGridTest.TheFilterFunnelIsHitWhereItIsPainted;
var
  fr: TRect;
  h: TTyGridHit;
begin
  Build(True, [60, 90, 50]);
  FG.Header.Options := FG.Header.Options + [hoVisible];
  FG.ShowFilterButtons := True;
  fr := FG.FunnelRect(1);
  AssertFalse('column 1 has a funnel', IsRectEmpty(fr));
  { The funnel sits at the section's TRAILING edge, which mirrored is its left. }
  AssertTrue('the funnel is in the left half of the mirrored section',
    (fr.Left + fr.Right) div 2 < FG.ColLeft(1) + FG.ColWidth(1) div 2);
  AssertTrue('and inside that section, not the next one along',
    ((fr.Left + fr.Right) div 2 >= FG.ColLeft(1))
    and ((fr.Left + fr.Right) div 2 < FG.ColLeft(1) + FG.ColWidth(1)));
  h := FG.Hit((fr.Left + fr.Right) div 2, 4);
  AssertEquals('and the header hit under the funnel names the same column', 1, h.Col);
end;

{ A header group spans first..last column. Mirrored, first is on the RIGHT, so the naive
  `Rect(Left(first), .., Left(last)+Width(last), ..)` is an INVERTED rect and the whole group
  band paints nothing. ColumnSpanX takes the union instead; this is the guard on that. }
procedure TRtlGridTest.AHeaderGroupSpansItsColumnsInsteadOfInverting;
var
  Bmp: TBGRABitmap;
  g: TTyGridHeaderGroup;
  ink, x: Integer;
  bg, px: TBGRAPixel;
begin
  Build(True, [60, 90, 50]);
  FG.Header.Options := FG.Header.Options + [hoVisible];
  g := FG.HeaderGroups.Add as TTyGridHeaderGroup;
  g.FirstCol := 0;
  g.LastCol := 1;
  g.Text := 'G';
  FG.GroupHeaderHeight := 18;
  Bmp := Shot;
  try
    { Ink anywhere along the band the group is supposed to cover. An inverted rect draws
      nothing at all, which is the failure this catches. }
    ink := 0;
    bg := Bmp.GetPixel(2, 9);
    for x := FG.ColLeft(1) to FG.ColLeft(0) + FG.ColWidth(0) - 1 do
    begin
      px := Bmp.GetPixel(x, 9);
      if (px.red <> bg.red) or (px.green <> bg.green) or (px.blue <> bg.blue) then Inc(ink);
    end;
    AssertTrue('the group band paints across the columns it spans', ink > 0);
  finally
    Bmp.Free;
  end;
end;

{ --- cell chrome ----------------------------------------------------------- }

{ Every one of these slots derives from CellRect, so mirroring the column axis moves them as
  a block. That is the property being pinned -- not that somebody remembered each of them,
  but that none of them needed remembering. }
procedure TRtlGridTest.CheckBoxAndButtonCellsAnswerInsideTheMirroredCell;
var
  box, cell: TRect;
begin
  Build(True, [60, 90, 50]);
  { A check cell is an EDITOR kind, not a display kind -- CheckBoxRect answers only where
    EditorKindFor says gekCheckBox. }
  FG.DefaultEditorKind := gekCheckBox;
  cell := FG.Cell(1, 1);
  box := FG.BoxRect(1, 1);
  AssertFalse('the check box has a rect', IsRectEmpty(box));
  AssertTrue('and it is inside the mirrored cell, not its unmirrored twin',
    (box.Left >= cell.Left) and (box.Right <= cell.Right));
  AssertEquals('a click in the middle of the box names that cell''s column',
    1, FG.Hit((box.Left + box.Right) div 2, (box.Top + box.Bottom) div 2).Col);
end;

{ The ellipsis button is pinned to the cell's TRAILING edge, which mirrored is its left.
  Paint and hit both read EllipsisRect, so the assertion that matters is where that one rect
  moved to -- and that a click there still reaches the right cell. }
procedure TRtlGridTest.TheEllipsisButtonMovesToTheCellsLeadingSideAndItsHitFollows;
var
  cell, dots: TRect;
begin
  Build(True, [60, 90, 50]);
  (FG.Header.Columns.Items[1] as TTyGridColumn).EditorKind := gekEllipsis;
  cell := FG.Cell(1, 1);
  dots := FG.DotsRect(1, 1);
  AssertFalse('the ellipsis button has a rect', IsRectEmpty(dots));
  AssertTrue('and it sits in the left half of the mirrored cell',
    (dots.Left + dots.Right) div 2 < (cell.Left + cell.Right) div 2);
  AssertEquals('a click on it lands in the cell it belongs to',
    1, FG.Hit((dots.Left + dots.Right) div 2, (dots.Top + dots.Bottom) div 2).Col);
end;

{ Rating stars are the one cell slot with an ORDER inside the cell, so they catch a mirror
  that moved the block but left the sequence running the old way. Star 1 must be nearest the
  reading start, and SetRatingByPoint must agree -- it hit-tests through RatingStarRect, the
  same function the paint uses. }
procedure TRtlGridTest.RatingStarsCountFromTheRightAndTheClickAgrees;
var
  s1, s3, cell: TRect;
begin
  Build(True, [60, 90, 50]);
  FG.DefaultCellDisplay := gcdRating;
  FG.DefaultEditorKind := gekRating;
  cell := FG.Cell(1, 1);
  s1 := FG.StarRect(1, 1, 1);
  s3 := FG.StarRect(1, 1, 3);
  AssertFalse('star 1 has a rect', IsRectEmpty(s1));
  AssertFalse('star 3 has a rect', IsRectEmpty(s3));
  AssertTrue('star 1 is nearer the reading start than star 3', s1.Left > s3.Left);
  AssertTrue('and both are inside the mirrored cell',
    (s3.Left >= cell.Left) and (s1.Right <= cell.Right));
  FG.ClickAt((s3.Left + s3.Right) div 2, (s3.Top + s3.Bottom) div 2);
  AssertEquals('clicking the third star from the reading start sets 3',
    '3', FG.Cells[1, 1]);
end;

{ The tree chevron is the only cell slot whose position depends on a LEVEL, i.e. on an
  accumulation. Mirrored, the indent grows leftwards from the cell's right edge, and the text
  has to yield the same side -- that is one computation (TreeContentLeft feeding a rect that
  is reflected once), which is why the chevron and the caption cannot end up on opposite
  sides. Paint and hit both read TreeToggleRect. }
procedure TRtlGridTest.TheTreeChevronMovesToTheCellsRightGutterAndItsHitFollows;
var
  cell, tg: TRect;
begin
  Build(True, [120, 90, 50]);
  FG.TreeColumn := 0;
  FG.TreeIndent := 16;
  FG.OnGetNodeLevel := @FG.SetLevel;
  FG.OnGetHasChildren := @FG.SetHasKids;
  FG.Remeasure;
  cell := FG.Cell(0, 0);
  tg := FG.TreeToggle(0);
  AssertFalse('the root node has a chevron', IsRectEmpty(tg));
  AssertTrue('and it sits in the RIGHT gutter of the mirrored cell',
    tg.Left > (cell.Left + cell.Right) div 2);
  AssertTrue('inside the cell', (tg.Left >= cell.Left) and (tg.Right <= cell.Right));
  { A child's chevron indents AWAY from the reading start, i.e. leftwards. }
  AssertTrue('a deeper node indents leftwards, not rightwards',
    FG.TreeToggle(1).Left < tg.Left);
end;

{ The inline filter row is its own band and is hit-tested before the cell branch. Its column
  comes from ColumnAtX like everything else, so this is really asking whether the band
  survived the mirror at all. }
procedure TRtlGridTest.TheFilterRowNamesTheColumnUnderThePointer;
var
  h: TTyGridHit;
  fy: Integer;
begin
  Build(True, [60, 90, 50]);
  FG.Header.Options := FG.Header.Options + [hoVisible];
  FG.ShowFilterRow := True;
  fy := FG.Metrics.FrozenTop - 4;
  h := FG.Hit(FG.ColLeft(1) + 4, fy);
  AssertTrue('the filter row is hit-testable', h.Part = ghpFilterRow);
  AssertEquals('and names the column painted under the pointer', 1, h.Col);
  h := FG.Hit(FG.ColLeft(0) + 4, fy);
  AssertEquals('a pointer near the right edge is column 0', 0, h.Col);
end;

{ The painter's alignment flag, seen from inside a mirrored grid. The cell RECT alone puts
  the text in the right cell -- what puts it against the right EDGE of that cell is the flag
  BeginPaintOn carries, and a grid that forgot it looks very nearly correct: every column is
  where it should be and only the words sit against the far side of their own cell. Probed by
  differencing two shots, so what is measured is the glyphs and nothing else. }
procedure TRtlGridTest.CellTextHugsTheCellsReadingStart;
var
  Bmp, Bare: TBGRABitmap;
  cell: TRect;
  x, y, firstX, lastX: Integer;
  differs: Boolean;
begin
  Build(True, [60, 90, 50]);
  cell := FG.Cell(1, 1);
  FG.Cells[1, 1] := '';
  Bare := Shot;
  try
    FG.Cells[1, 1] := 'W';
    Bmp := Shot;
    try
      firstX := -1;
      lastX := -1;
      for x := cell.Left to cell.Right - 1 do
      begin
        differs := False;
        for y := cell.Top to cell.Bottom - 1 do
          if Bmp.GetPixel(x, y) <> Bare.GetPixel(x, y) then
          begin
            differs := True;
            Break;
          end;
        if differs then
        begin
          if firstX < 0 then firstX := x;
          lastX := x;
        end;
      end;
      AssertTrue('the cell text was drawn at all', firstX >= 0);
      AssertTrue('and it hugs the cell''s RIGHT edge -- its reading start',
        (cell.Right - lastX) < (firstX - cell.Left));
    finally
      Bmp.Free;
    end;
  finally
    Bare.Free;
  end;
end;

{ THE SECOND ALIGNMENT PATH, and the reason the one above is not enough. Cell text goes
  through TTyCustomGrid.DrawCellText, which renders into its own cached bitmap and therefore
  never touches TTyPainter.DrawText -- it has to flip its own alignment. Header captions,
  header-group captions, group-row keys and footer totals go the OTHER way, through
  P.DrawText, and are flipped by the flag BeginPaintOn carries. Two mechanisms, two mutants;
  a test that probed only one of them would let the other ship. }
procedure TRtlGridTest.HeaderCaptionsHugTheirSectionsReadingStart;
var
  Bmp, Bare: TBGRABitmap;
  sec: TRect;
  x, y, firstX, lastX: Integer;
  differs: Boolean;
begin
  Build(True, [60, 90, 50]);
  FG.Header.Options := FG.Header.Options + [hoVisible];
  sec := Rect(FG.ColLeft(1), 0, FG.ColLeft(1) + FG.ColWidth(1), 0);
  FG.Header.Columns.Items[1].Text := '';
  Bare := Shot;
  try
    FG.Header.Columns.Items[1].Text := 'W';
    Bmp := Shot;
    try
      firstX := -1;
      lastX := -1;
      for x := sec.Left to sec.Right - 1 do
      begin
        differs := False;
        for y := 1 to FG.Metrics.FrozenTop - 2 do
          if Bmp.GetPixel(x, y) <> Bare.GetPixel(x, y) then
          begin
            differs := True;
            Break;
          end;
        if differs then
        begin
          if firstX < 0 then firstX := x;
          lastX := x;
        end;
      end;
      AssertTrue('the header caption was drawn at all', firstX >= 0);
      AssertTrue('and it hugs its section''s RIGHT edge -- the reading start',
        (sec.Right - lastX) < (firstX - sec.Left));
    finally
      Bmp.Free;
    end;
  finally
    Bare.Free;
  end;
end;

{ The fixed-column strip is the one chrome band whose two edges come from DIFFERENT places:
  the gutter''s inner edge and the frozen band''s outer one. Written in screen coordinates it
  reads `Rect(indW, .., M.FrozenLeft, ..)` -- and mirrored, M.FrozenLeft holds the RIGHT
  frozen band, so that rect is inverted and the strip vanishes entirely. Written in reading
  space and reflected once, it cannot.

  Measured as the WIDTH of the unbroken chrome run at the reading edge rather than by giving
  the two bands loud colours of their own: the stock theme paints the gutter and the strip in
  one colour, which is what turns this into a single number -- 80px of chrome (a 20px gutter
  plus a 60px frozen column) against 20px if the strip went missing. Nothing is loaded over
  the theme, so the measurement is of what a user actually sees.

  RowCount is 0 and the grid lines are off so that nothing paints INTO the band and breaks the
  run: cell text and a column's own divider would each cross it. }
procedure TRtlGridTest.TheFixedColumnStripIsPaintedBesideTheMirroredGutter;
var
  Bmp: TBGRABitmap;
  M: TTyGridMetrics;
  x, y, band: Integer;   { 'run' is a TTestCase method -- do not shadow it }
  chrome: TBGRAPixel;
begin
  Build(True, [60, 90, 50], 0, 200);
  FG.ShowIndicator := True;
  FG.IndicatorWidth := 20;
  FG.FixedCols := 1;
  FG.GridLineStyle := glsNone;
  FG.Remeasure;
  M := FG.Metrics;
  AssertEquals('precondition: gutter + one frozen column', 80, FG.FrozenW);
  Bmp := Shot(200, 240);
  try
    y := M.FrozenTop + 4;
    chrome := Bmp.GetPixel(FG.ViewW - 4, y);
    AssertTrue('precondition: the chrome band is not the cell background',
      chrome <> Bmp.GetPixel(4, y));
    band := 0;
    x := FG.ViewW - 1;
    while (x >= 0) and (Bmp.GetPixel(x, y) = chrome) do
    begin
      Inc(band);
      Dec(x);
    end;
    AssertEquals('the chrome at the reading edge is the gutter AND the fixed strip',
      FG.FrozenW, band);
  finally
    Bmp.Free;
  end;
end;

{ --- keyboard and selection ------------------------------------------------ }

{ Left and right are LAYOUT direction here, not text direction, so they flip -- \xa76.3 item 4
  draws exactly that line. Home and End are LOGICAL ends and do not: End goes to the last
  column whichever side of the screen that column is on. }
procedure TRtlGridTest.ArrowKeysFollowTheEyeAndHomeEndStayLogical;
begin
  Build(True, [60, 90, 50]);
  FG.Col := 1;
  FG.Row := 1;
  FG.Key(VK_LEFT);
  AssertEquals('mirrored, the left arrow moves FORWARD through the columns', 2, FG.Col);
  FG.Key(VK_RIGHT);
  AssertEquals('and the right arrow moves back', 1, FG.Col);
  FG.Key(VK_HOME);
  AssertEquals('Home is logical: the first column, wherever it is drawn', 0, FG.Col);
  FG.Key(VK_END);
  AssertEquals('End is logical too', 2, FG.Col);
end;

{ A rectangular selection is stored as column INDICES. Mirroring must not touch them: the
  anchor and the opposite corner have to describe the same cells, or every host reading
  Selection gets a different answer on a mirrored form. }
procedure TRtlGridTest.ARectangularSelectionStillDescribesTheSameCells;
var
  sel, bounds: TRect;
begin
  Build(True, [60, 90, 50]);
  FG.SelectRange(0, 1, 2, 3);
  sel := FG.Selection;
  AssertEquals('the anchor column is unchanged by mirroring', 0, sel.Left);
  AssertEquals('and so is the opposite corner', 2, sel.Right);
  AssertEquals('rows likewise', 1, sel.Top);
  AssertEquals('rows likewise', 3, sel.Bottom);
  { The PIXEL bounds, on the other hand, must not be an inverted rect -- index 0 is on the
    right now, so naively pairing tl.Left with br.Right gives Left > Right and the selection
    frame plus its fill handle disappear. }
  bounds := FG.SelBounds;
  AssertTrue('and its pixel bounds are a real rect, not an inverted one',
    bounds.Right > bounds.Left);
end;

{ The fill handle is the one affordance that is deliberately drawn HALF OUTSIDE the thing it
  belongs to, so "is it inside the selection" cannot be the assertion -- the assertion is
  which corner it hangs off. Paint and hit both read FillHandleRect, so the second half of
  this test (a drag that actually fills) is what proves the click target moved with the ink
  rather than merely that a rect moved. }
procedure TRtlGridTest.TheFillHandleHangsOffTheSelectionsTrailingCornerAndDragsFromThere;
var
  b, h, target: TRect;
begin
  Build(True, [60, 90, 50]);
  FG.Cells[0, 0] := 'X';
  FG.SelectRange(0, 0, 0, 0);
  b := FG.SelBounds;
  h := FG.HandleRect;
  AssertFalse('the selection has a fill handle', IsRectEmpty(h));
  AssertTrue('which hangs off its LEFT corner once mirrored -- the trailing one',
    h.Left < b.Left);
  AssertTrue('and not off the right one', h.Right < b.Right);

  { And a drag started on it really fills. If the handle had stayed on the selection''s right
    the press below would land on a plain cell, reset the selection and fill nothing -- which
    is the whole failure mode, and it leaves no mark on any static geometry. }
  target := FG.Cell(0, 2);
  FG.PressDown((h.Left + h.Right) div 2, (h.Top + h.Bottom) div 2);
  FG.PressMove((target.Left + target.Right) div 2, (target.Top + target.Bottom) div 2);
  FG.PressUp((target.Left + target.Right) div 2, (target.Top + target.Bottom) div 2);
  AssertEquals('dragging the handle down filled the rows below', 'X', FG.Cells[0, 2]);
end;

{ A group row''s triangle is measured from the client edge and indented per level, so it is
  the one piece of chrome in the grid that is NOT derived from a column rect -- which is
  exactly why it can be left behind. Paint and hit both read GroupToggleRect; the click at
  the end is what says so. }
procedure TRtlGridTest.TheGroupRowToggleMovesToTheRightAndStillCollapsesItsGroup;
var
  tg: TRect;
  gi: Integer;
begin
  Build(True, [60, 90, 50], 4);
  FG.Cells[0, 0] := 'A';
  FG.Cells[0, 1] := 'B';
  FG.Cells[0, 2] := 'A';
  FG.Cells[0, 3] := 'B';
  FG.GroupByColumn(0);
  AssertTrue('precondition: display position 0 is a group row', FG.IsGroupRow(0, gi));

  tg := FG.GroupToggle(0);
  AssertFalse('the group row has a toggle', IsRectEmpty(tg));
  AssertTrue('which sits in the RIGHT half of the row once mirrored',
    tg.Left > FG.ViewW div 2);
  AssertEquals('flush against the reading start, less its indent',
    FG.ViewW, tg.Right + FG.Sc(4));

  AssertFalse('precondition: the group starts expanded', FG.GroupInfo(gi).Collapsed);
  FG.ClickAt((tg.Left + tg.Right) div 2, (tg.Top + tg.Bottom) div 2);
  AssertTrue('clicking the mirrored toggle collapses its group',
    FG.GroupInfo(gi).Collapsed);
end;

{ --- invariants ------------------------------------------------------------ }

{ A reflection preserves widths exactly. This is the consumer whose breakage would be
  silent -- nothing on screen looks wrong when a column is one pixel narrower than it says
  it is, and the auto-fit and fill-distribute paths both read these numbers. }
procedure TRtlGridTest.EveryColumnWidthAndTheContentWidthSurviveMirroring;
var
  i: Integer;
  wLtr: array[0..2] of Integer;
  cwLtr: Integer;
begin
  Build(False, [60, 90, 50]);
  for i := 0 to 2 do wLtr[i] := FG.ColWidth(i);
  cwLtr := FG.GridWidth;
  TearDown;
  Build(True, [60, 90, 50]);
  for i := 0 to 2 do
    AssertEquals(Format('column %d width', [i]), wLtr[i], FG.ColWidth(i));
  AssertEquals('and the total content width', cwLtr, FG.GridWidth);
end;

{ A merged cell spans forward from its base. Mirrored, "forward" is leftwards, so the base
  cell's rect has to grow on its LEFT -- assigning to Result.Right the way the unmirrored
  code did produces Right < Left and the merged block renders as nothing. }
procedure TRtlGridTest.MergedCellsSpanForwardInsteadOfCollapsing;
var
  base, one: TRect;
begin
  Build(True, [60, 90, 50]);
  FG.MergeCells(0, 0, 2, 1);
  base := FG.Cell(0, 0);
  one := FG.Cell(1, 1);
  AssertTrue('the merged rect is not inverted', base.Right > base.Left);
  AssertEquals('it still ends flush against the reading start',
    FG.ViewW, base.Right);
  AssertTrue('and it reaches back over the column it swallowed',
    base.Left <= one.Left);
  AssertEquals('covering exactly two columns'' worth',
    FG.ColWidth(0) + FG.ColWidth(1), base.Right - base.Left);
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

{ TTyRibbon is the third subclass of the tab-strip engine, and mirroring the engine put it in
  the same position TTyDropDownButton is in above: the base's headers would move while the
  ribbon's OWN chrome -- the File tab it paints at x=0, the collapse chevron, the Alt KeyTip
  chips, and the two `X >= HeaderLeftInset` tests in its MouseDown -- would not. So the
  ribbon declines, in one place (HeaderRightToLeft), and this pins the decline: whoever
  mirrors the ribbon has to move that chrome and those hit tests in the same commit, because
  deleting the override alone turns this red. }
procedure TRtlExclusionTest.RibbonDeclinesToMirrorTheHeaderBandItInherits;
var
  Form: TForm;
  Rib: TTyRibbon;
  before, after: TRect;
begin
  Form := TForm.CreateNew(nil);
  try
    Rib := TTyRibbon.Create(Form);
    Rib.Parent := Form;
    Rib.Font.PixelsPerInch := 96;
    Rib.SetBounds(0, 0, 400, 120);
    Rib.AddPage('Home');
    Rib.AddPage('Insert');
    before := Rib.TabRect(0);
    Rib.BiDiMode := bdRightToLeft;
    after := Rib.TabRect(0);
    AssertTrue('precondition: the ribbon draws a first tab', before.Right > before.Left);
    AssertEquals('the ribbon''s first tab does not move (left)',  before.Left,  after.Left);
    AssertEquals('the ribbon''s first tab does not move (right)', before.Right, after.Right);
    AssertEquals('and it still starts at the reading-left of the band',
      0, Rib.IndexOfTabAt((after.Left + after.Right) div 2,
                          (after.Top + after.Bottom) div 2));
  finally
    Form.Free;
  end;
end;

{ THE GRID'S VERTICAL SCROLL BAR DOES NOT MOVE, and this is a decision rather than an
  omission -- pinned here so the next person makes it again on purpose.

  Everything the grid paints lives in a viewport whose width is ViewportW and whose ORIGIN
  is x=0; the mirror is a reflection of [0, ViewportW) onto itself, which is why LTR output
  came out byte-identical. Docking the vertical bar on the left would move that origin to
  the bar's width, and roughly fifteen full-width band expressions currently read
  `Rect(0, .., M.ClientW, ..)` -- row bands, the header fill, the filter row, grid lines, the
  footer, the fast-scroll blit. Each would need the same constant added, which is fifteen more
  chances to mirror fourteen. The scoping document ranks a bar left on the wrong side as the
  MOST visible and therefore the SAFEST omission (\xa75 item 7), and that is the trade taken.

  Two assertions, because either alone would let the other half drift: the origin is still
  zero, and the bar is still on the right. Move one without the other and this turns red. }
procedure TRtlExclusionTest.TheGridsVerticalBarStaysOnTheRightAndItsViewportOriginStaysAtZero;
var
  Form: TForm;
  Ctl: TTyStyleController;
  G: TRtlGridAccess;
  i: Integer;
  bar: TTyScrollBar;
begin
  Form := TForm.CreateNew(nil);
  Ctl := TTyStyleController.Create(nil);
  try
    G := TRtlGridAccess.Create(Form);
    G.Parent := Form;
    G.Controller := Ctl;
    G.Font.PixelsPerInch := 96;
    G.SetBounds(0, 0, 300, 120);
    G.Header.Columns.Add;
    G.RowCount := 200;                 { forces the vertical bar }
    G.VertScrollBarMode := gsbAlways;
    G.BiDiMode := bdRightToLeft;
    G.Remeasure;

    AssertEquals('the paint origin is still the viewport''s left edge',
      0, TyGridPaneRect(G.Metrics, gpTopLeft).Left);
    AssertTrue('and the viewport is narrower than the control by the bar''s width',
      G.ViewW < G.ClientWidth);

    bar := nil;
    for i := 0 to G.ControlCount - 1 do
      if (G.Controls[i] is TTyScrollBar)
         and (TTyScrollBar(G.Controls[i]).Kind = sbVertical) then
        bar := TTyScrollBar(G.Controls[i]);
    AssertNotNull('the grid shows a vertical bar', bar);
    AssertEquals('which is still docked against the right edge',
      G.ClientWidth, bar.Left + bar.Width);
  finally
    Form.Free;
    Ctl.Free;
  end;
end;

{ The filter drop-down is a TTyCheckListBox whose PaintItemContent pins a count column to
  ARowRect.Right, while the base class puts its toggle at the row's READING start. Mirrored,
  those two land on the same side and the count sits on top of the check box. One rect
  function short of being mirrorable, exactly like TTyValueListEditor in phase 3. }
procedure TRtlExclusionTest.TheGridsFilterDropDownDeclinesToMirrorItsRows;
var
  Form: TForm;
  L: TRtlFilterListAccess;
begin
  Form := TForm.CreateNew(nil);
  try
    L := TRtlFilterListAccess.Create(Form);
    L.Parent := Form;
    L.BiDiMode := bdRightToLeft;
    AssertFalse('the filter list declines to mirror its rows', L.Mirrors);
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
  RegisterTest(TRtlTabStripTest);
  RegisterTest(TRtlGridTest);
  RegisterTest(TRtlExclusionTest);
  RegisterTest(TRtlScrollBarGeometryTest);
  RegisterTest(TRtlScrollBarControlTest);
  RegisterTest(TRtlScrollBoxTest);
  RegisterTest(TRtlListBoxTest);
end.
