unit test.richedit.control;

{ TTyRichEdit, the viewer (Task 9a): loading and saving through the control, scrolling on the
  height index (only what is seen is laid out, the view stays anchored while estimates are
  corrected), partial invalidation, painting only what the clip meets, pictures left for the
  background, zoom, wrap, Lines, the theme keys.

  Headless: the layout measures with the test device (test.richedit.layoutdevice: every advance
  worked out by rule), no window is made, invalidations are recorded by the probe's
  InvalidateContent, the background work is stepped by hand (StepBackground, FinishLoading) -
  no timer, no message loop. Every bound is a count (blocks laid out, draw calls, node visits,
  bytes on the heap), never a time. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, fpcunit, testregistry, Controls, Graphics, LCLType, Forms,
  ExtCtrls, Menus, BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.StyleModel, tyControls.Controller, tyControls.BuiltinThemes,
  tyControls.ScrollBar, tyControls.Painter, tyControls.TextMenu,
  tyControls.RichEdit.Text, tyControls.RichEdit.Model, tyControls.RichEdit.Commands,
  tyControls.RichEdit.RtfRead, tyControls.RichEdit.RtfWrite, tyControls.RichEdit.Layout,
  tyControls.RichEdit, test.richedit.layoutdevice, test.devicescale.support;

type
  { A layouter whose resampling can be made to fail (a test seam of W2's). }
  TProbeLayouter = class(TTyRichLayouter)
  protected
    function ScaleImage(AImage: TBGRABitmap; AWidth, AHeight: Integer): TBGRABitmap; override;
    function DecodeImage(AStream: TStream; AJpegScale: Integer): TBGRABitmap; override;
  public
    FailScale: Boolean;
    { The decoder raises an access violation (a fatal error, let through by the layouter);
      how many times it was asked to while failing. }
    FailDecode: Boolean;
    FailedDecodes: Integer;
  end;

  TRichProbe = class(TTyRichEdit)
  private
    FLaidParas: Integer;
    FLaidMin, FLaidMax: Integer;
    FBlockPaints, FFramePaints: Integer;
  protected
    function CreateDevice: TTyRichTextDevice; override;
    function CreateLayouter: TTyRichLayouter; override;
    function LayoutBlockAt(AIndex: Integer): TTyBlockLayout; override;
    procedure InvalidateArea(const ARect: TRect); override;
    procedure PaintBlock(ABitmap: TBGRABitmap; AIndex, AX, AY: Integer; const AClip: TRect;
      const AStyle: TTyRichPaintStyle); override;
    procedure PaintSurfaceFrame(APPI: Integer); override;
    function ScrollBarLimit: Integer; override;
    function IdleTicks: QWord; override;
    function HasCaretFocus: Boolean; override;
    procedure WriteClipboard(const ARtf: RawByteString; const AText: string); override;
    function ClipboardFormatList: TTyRichClipFormats; override;
    function ClipboardFlavours: TTyRichClipFlavours; override;
    function ReadClipboardRtf: RawByteString; override;
    function ReadClipboardPicture(AIndex: Integer; out AKind: TTyRichImageKind;
      out ABytes: TBytes): Boolean; override;
    function ReadRtfSource(const ABytes: TBytes; out AEndsWithParagraph: Boolean): TTyRichDocument; override;
    function ReadClipboardText: string; override;
    procedure BeginWait; override;
    procedure EndWait; override;
    procedure ShowTextMenu(const APos: TPoint); override;
    procedure PostCall(ACall: TTyRichQueuedCall); override;
    procedure RemovePostedCall(ACall: TTyRichQueuedCall); override;
    procedure WatchIdle(AOn: Boolean); override;
    procedure IdleStep(Sender: TObject; var Done: Boolean); override;
    function TurnDriver: TTyRichTurnDriver; override;
    function SchedulingClosed: Boolean; override;
  public
    { W8: the idle handler registered and removed, the idle step entered (every probe). }
    class var Watches, Unwatches, IdleEntries: Integer;
    { W8: the timer driver (what Cocoa and the unnamed widgetsets get) on this widgetset;
      queuing raises; the application shut down for scheduling. }
    ForceTimer, FailPost, ClosedApp: Boolean;
    { W8 (L-6): a clock of the test's (FakeClock on), advanced by ClockStep at every reading. }
    FakeClock: Boolean;
    ClockNow: QWord;
    ClockStep: Integer;
    function NextSlice: Int64;
    function IdleOn: Boolean;
    function TimerOf: TTimer;
    procedure HoverOut;
  protected
    function SliceBytes: Int64; override;
  public
    { W9: the slice sizes asked of the loader while LogSlices is on. }
    LogSlices: Boolean;
    SliceLog: array of Int64;
    { W9: a clock of a file that indexes FakeRate bytes a millisecond (0: off): it reads
      ClockNow plus the load's bytes indexed over FakeRate; StallMs is added to ClockNow at
      the StallReadings-th reading from now (0: never). }
    FakeRate: Int64;
    StallMs, StallReadings: Integer;
    { W9: the backstop timer, its tick run by hand, the turns run. }
    function BackstopOf: TTimer;
    procedure BackstopNow;
    function Turns: Int64;
  public
    { W6: Invalidate's calls (what PointerStateChanged asks for), the temporary cursors
      MouseMove set. }
    Invalidates: Integer;
    TempCursors: array of TCursor;
    { W7: the calls queued to the application (the background turn, the selection report) and
      taken off it; counted for every probe, also one already freed. }
    class var Posts, Removes: Integer;
    procedure Invalidate; override;
    procedure SetTempCursor(Value: TCursor); override;
    procedure Enter;
    { The control as the form designer has it (csDesigning), and a character typed there. }
    procedure MakeDesigning;
    procedure TypeChar(const AChar: TUTF8Char);
    function BlinkTimerOf: TTimer;
    function DragTimerOf: TTimer;
    function TurnQueued: Boolean;
    function ReportQueued: Boolean;
    function ImeRect: TRect;
  public
    { The caret is drawn as for a focused control (a test cannot give the focus). }
    ForceFocus: Boolean;
    { The clipboard the copy writes to: what it put and how often (never the system's). }
    ClipRtf: RawByteString;
    ClipText: string;
    ClipWrites, Waits, WaitEnds, MenuShows: Integer;
    FailClip: Boolean;
    { Task 10c: what a paste reads - the copy's two flavours above, a picture and an HTML
      flavour (which the control never asks for) - and how often each was asked for. }
    ClipPicture: TBytes;
    ClipPictureKind: TTyRichImageKind;
    ClipHtml: string;
    FlavourAsks, RtfReads, PictureReads, TextReads, HtmlReads: Integer;
    { W14: a second picture format, tried after the first (V-M3). }
    ClipPicture2: TBytes;
    ClipPictureKind2: TTyRichImageKind;
    { W14 (V-M5): FromFormats - the flavours are the control's own answer from the format
      list ClipFormats (one enumeration, FormatAsks counted) instead of the fields above. }
    FromFormats: Boolean;
    ClipFormats: TTyRichClipFormats;
    FormatAsks: Integer;
    { W14 (V-M8): the RTF read as this document instead of by the engine's reader (nil:
      the reader's; the probe hands it over once). }
    RtfSource: TTyRichDocument;
    RtfSourceEnds: Boolean;
    procedure ClipReset;
    procedure SetCopyWait(AChars: Int64);
    { DoContextPopup's answer: Handled. }
    function PopupAt(X, Y: Integer): Boolean;
    procedure PressAt(X, Y: Integer; AShift: TShiftState = []);
    procedure MoveAt(X, Y: Integer);
    procedure ReleaseAt(X, Y: Integer);
    procedure RightAt(X, Y: Integer);
    { KeyDown's answer: the key left for the form, 0 when the control took it. }
    function KeyResult(AKey: Word; AShift: TShiftState): Word;
    procedure DragTick;
    procedure Blink;
    procedure CaretOn(ACanvas: TCanvas);
    function CursorFor(X, Y: Integer): TCursor;
    function DragOn: Boolean;
    function TextWindow: TRect;
  public
    Invalidated: array of TRect;
    BarLimit: Integer;
    { LayoutBlockAt raises after this many more layouts (0: never); the layouts it gave. }
    RaiseAfter: Integer;
    Given: array of TTyBlockLayout;
    { PaintBlock raises at this many more block paints (0: never). }
    RaiseOnBlock: Integer;
    { The idle clock stands still: a timer turn ends by its cap alone. }
    FrozenClock: Boolean;
    procedure Turn;
    procedure Down;
    procedure Up;
    function Detect(AStream: TStream): TTyRichFormat;
    { The whole frame as the painter draws it with no text clip (the ground under it), into
      ABitmap at the device scale. }
    procedure FullFrame(ABitmap: TBGRABitmap; APPI: Integer);
    procedure DropHandle;
    function Ground: TBGRAPixel;
    procedure ResetCounts;
    procedure PaintPart(ACanvas: TCanvas; const AClip: TRect; ADefer: Boolean);
    function Step: Boolean;
    function Pending: Integer;
    function VBar: TTyScrollBar;
    function HBar: TTyScrollBar;
    function TypeKey: string;
    function Style: TTyRichPaintStyle;
    function Area: TRect;
    procedure Slices(AFirst, AStep: Int64);
    procedure Press(AKey: Word; AShift: TShiftState);
    procedure Wheel(ADelta: Integer; AShift: TShiftState);
    function Device: TTyRichTestDevice;
    function Lay: TProbeLayouter;
    function Surf: TBGRABitmap;
    function Scale: Integer;
    procedure RedrawAll;
    procedure InvalidatePart(const ARect: TRect);
    procedure WheelH(ADelta: Integer);
    procedure Hover(AOn: Boolean);
    property BlockPaints: Integer read FBlockPaints;
    property FramePaints: Integer read FFramePaints;
    property LaidParas: Integer read FLaidParas;
    property LaidMin: Integer read FLaidMin;
    property LaidMax: Integer read FLaidMax;
  end;

  TTyRichEditControlTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FRich: TRichProbe;
    FTemp: string;
    FChanges, FZooms, FLoadCalls, FCancelAt, FRefused: Integer;
    FOther: TStream;
    { The device scale PaintAll's bitmap is made for (the forced scale of a test). }
    FPaintScale: Integer;
    FSelChanges: Integer;
    FLastStepEdits: Integer;
    FRaiseOnce: Boolean;
    procedure Changed(Sender: TObject);
    procedure Zoomed(Sender: TObject);
    procedure LoadCalled(Sender: TObject; ADone, ATotal: Int64; var ACancel: Boolean);
    procedure SaveCancel(Sender: TObject; ADone, ATotal: Int64; var ACancel: Boolean);
    function NewProbe: TRichProbe;
    procedure LoadBig;
    function ScreenLines: Integer;
    function TempFile(const AName: string; const ABytes: TBytes): string;
    function InView(APara: Integer): Boolean;
    procedure SetLinesOf(ACount: Integer; const APrefix: string);
    function Covered(const ARect: TRect): Boolean;
    procedure PaintAll(ADefer: Boolean);
    procedure ReplaceInHandler(Sender: TObject; ADone, ATotal: Int64; var ACancel: Boolean);
    procedure CancelInHandler(Sender: TObject; ADone, ATotal: Int64; var ACancel: Boolean);
    procedure SaveReplace(Sender: TObject; ADone, ATotal: Int64; var ACancel: Boolean);
    procedure NoFallback(Sender: TObject; const ABaseFont: string; ACode: Cardinal;
      var AFontName: string);
    procedure PictureCase(const AWhat: string; APngW, APngH: Integer; AFail: Boolean;
      AZoomAfter: Integer);
    function FileCount: Integer;
    procedure CheckClearAdd(const AList: array of string);
    procedure CheckSurface(const AWhat: string);
    procedure SurfaceSequence(AScale: Integer);
    function PictureDoc(ACount: Integer): Integer;
    function SurfaceCount(const AColor: TBGRAPixel): Integer;
    // 9b
    procedure SelChanged(Sender: TObject);
    { A client point inside the character at APos (on its line, left of its middle). }
    function At(APos: TTyRichPos): TPoint;
    procedure LoadRtfText(const S: string);
    procedure Click(const P: TPoint; AShift: TShiftState = []);
    // W4
    procedure EditInLastStep(Sender: TObject; ADone, ATotal: Int64; var ACancel: Boolean);
    // W6
    procedure InsertInLastStep(Sender: TObject; ADone, ATotal: Int64; var ACancel: Boolean);
    procedure CheckCaretInside(const AWhat: string);
    procedure EndAndClickCase(AScale: Integer; ARtl: Boolean);
    procedure RunAtScaleTwo(const AWhat: string; ACase: TRunMethod);
    // W7
    procedure RaiseOnce(Sender: TObject; ADone, ATotal: Int64; var ACancel: Boolean);
    function HandleForm: TForm;
    procedure LoadW7Plain(AExpectLoading: Boolean = True);
    procedure LoadW7Table(ARows, AInRow: Integer);
    // W8
    procedure SlowHandler(Sender: TObject; ADone, ATotal: Int64; var ACancel: Boolean);
    procedure LoadW8Big(AParas: Integer);
  private
    // W9
    FLoadEnds: Integer;
    FDocNotice: TTyRichChangeEvent;
    procedure CountLoadEnds(Sender: TObject; const AChange: TTyRichChange);
    function TurnSizes: string;
    // W10
    procedure RaiseOnLoadEnd(Sender: TObject; const AChange: TTyRichChange);
    function BarMaxWanted: Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestLoadShowsTheFirstScreenWithoutLayingOutTheRest;
    procedure TestScrollingToTheMiddleLaysOutOnlyNearby;
    procedure TestScrollPositionStaysPutWhenEstimatesAreCorrected;
    procedure TestPartialRepaintCoversOnlyTheChangedParagraph;
    procedure TestZoomChangesDisplayOnly;
    procedure TestTheTypeKeyHangsUnderTheMemo;
    procedure TestSelectionColoursResolveInEveryBuiltinTheme;
    procedure TestALazyRtfPaintsItsFirstScreenWhileLoading;
    procedure TestACancelledLoadIsIncompleteAndNotSavedOverItsFile;
    procedure TestEveryFixtureSavesBackByteForByte;
    procedure TestACancelledSaveLeavesTheFileAsItWas;
    procedure TestAWidthOrZoomChangeLaysOutOnlyTheViewAgain;
    procedure TestARowsHeightGoesOnItsFirstParagraph;
    procedure TestNoWrapExtentGrowsWithWhatWasSeen;
    procedure TestLinesReadTheDocumentWithoutCopyingIt;
    procedure TestAssigningLinesReplacesTheContent;
    procedure TestLinesGoIntoTheFormFileOnlyWhenSetThroughThem;
    procedure TestATallDocumentScrollsToItsLastLine;
    procedure TestAPaintDrawsOnlyTheBlocksInItsClip;
    procedure TestADeferredPaintLeavesPicturesForLater;
    procedure TestKeysAndWheelScrollAndZoom;
    procedure TestReadOnlyStaysOnAndCodeStillChanges;
    // 9a2: the review of 9a
    procedure TestAShortWrappedDocumentSettlesItsScrollBar;
    procedure TestAChangeWhileTheViewIsInvalidIsPainted;
    procedure TestALayoutThatMovesTheViewRepaintsIt;
    procedure TestAChangeOfManyParagraphsLaysOutOnlyTheView;
    procedure TestNumbersAfterAChangedItemAreRepainted;
    procedure TestQueriesSettleTheViewFirst;
    procedure TestProgressHandlersCannotReplaceTheContent;
    procedure TestAPictureIsQueuedOnceAndEveryBoxRepainted;
    procedure TestASaveKeepsWhatTheTargetWas;
    procedure TestAFileOpenForWritingLoads;
    procedure TestPublishedDefaultsAreTheConstructedValues;
    procedure TestLinesTellNoLinesFromOneEmptyLine;
    procedure TestFinishLoadingGoesInSlices;
    procedure TestScrollingAgainstAnEndDoesNothing;
    procedure TestAZoomKeepsThePartOfTheBlockAtTheTop;
    procedure TestAFarScrollIsAJump;
    procedure TestSavingAsTextIsAnExport;
    procedure TestASaveThatCannotWriteNamesTheTarget;
    procedure TestALayoutThatRaisesKeepsNoReference;
    procedure TestStreamingRaisesNoChangeAndABatchIsOneStep;
    procedure TestStyleOverrideTokensReachTheParts;
    procedure TestAChangeInARowDropsItsPendingPicture;
    procedure TestAFallbackFontChangeLaysTheViewOutAgain;
    procedure TestHugeBlocksKeepTheArithmeticInRange;
    // R40
    procedure TestTheBytesBeforeTheRtfAreKept;
    // R39
    procedure TestTheSurfaceEqualsAFullRedraw;
    procedure TestAScrollPaintsOnlyWhatItExposes;
    procedure TestTheSurfaceIsTheClientsSize;
    procedure TestDeviceScaleTwo;
    // fix wave W3
    procedure TestASlicedLoadShowsTheFilesNumbers;
    // 9a3: the second review of the viewer
    procedure TestLinesLoadAndATextInsideAnUpdate;
    procedure TestAPictureComesBackAfterAZoomThereAndBack;
    procedure TestAPreparationThatRaisesIsTriedOnce;
    procedure TestTheTextNeverCoversTheFrame;
    procedure TestContentIsClippedToTheText;
    procedure TestTheSurfaceEqualsAFullRedrawAtScaleTwo;
    procedure TestTheFrameSignatureHoldsWhatTheFrameIsDrawnFrom;
    procedure TestAPressThatLooksTheSameDrawsNothing;
    procedure TestADrawingThatRaisesLeavesNothingStale;
    procedure TestAPaintThatLaysOutAScrollInvalidatesNothing;
    procedure TestAZoomThenAScrollKeepsTheShareAndTheColumn;
    procedure TestAHandleOnAFormNeverShown;
    procedure TestOneTimerTurnStopsAtItsCap;
    procedure TestPositionRectSettlesAndSaysWhereItIs;
    procedure TestARightToLeftControlPutsItsBarLeft;
    procedure TestAChangeThatSwallowsTheAnchor;
    procedure TestAParagraphInsertedAndRemovedOnScreen;
    procedure TestDetectFormatOnShortInput;
    procedure TestALoadThatRaisesKeepsTheOldDocument;
    // 9b: the caret and the selection
    procedure TestEndAndAClickPastALineEndStayOnThatLine;
    procedure TestLeftAndRightStepOverWhatIsOneUnit;
    procedure TestUpAndDownKeepTheWishedXAndCrossATable;
    procedure TestShiftSelectionAndItsCollapse;
    procedure TestWordAndParagraphSelectionAndTheirDrags;
    procedure TestADragOutsideScrollsAndSelects;
    procedure TestTheCaretIsScrolledIntoViewByTheLeastAmount;
    procedure TestASelectionChangeRepaintsOnlyItsLines;
    procedure TestSelectAllInAHugeDocumentLaysOutNothing;
    procedure TestDocumentChangesMoveTheCaretAndTheSelection;
    procedure TestTheViewerTakesItsKeysAndLeavesTheRest;
    procedure TestAClickAndABlinkDrawNoText;
    procedure TestTheSelectionIsPainted;
    procedure TestSelStartAndSelLengthClampToCaretPlaces;
    procedure TestAClickOnAnObjectSelectsIt;
    procedure TestTheCursorAndARightClick;
    procedure TestOneSelectionEventPerAction;
    // 9b: copying, the menu, the input method
    procedure TestCopyPutsRtfAndPlainText;
    procedure TestThePlainTextRules;
    procedure TestAnEmptySelectionCopiesNothing;
    procedure TestAHugeCopyShowsTheWaitCursor;
    procedure TestTheMenuOfAViewer;
    procedure TestTheImeIsToldTheViewerIsReadOnly;
    // fix wave W4
    procedure TestACommandFromTheLastStepsProgressIsAnEdit;
    procedure TestAPlainCopyOfALazyRtfLeavesNothingParsed;
    procedure TestARefusedRtfFlavourCopiesTheTextAlone;
    // fix wave W5
    procedure TestThePlainTextCountsCharactersAsTheStorage;
    procedure TestACopyInsideACellOfANestedRowHasBothFlavours;
    procedure TestAHugeLengthGivesTheTextToTheEnd;
    procedure TestCellsWithoutAParagraphGiveTheirTabs;
    procedure TestACopyWhileLoadingAndAfterACancel;
    procedure TestTheRowBeforeIsHeldWhileTheNextIsCompared;
    procedure TestABigTableReadInPartsCopiesAsAWhole;
    // fix wave W6: the caret and the selection after their review
    procedure TestTheCaretAtALineEndAtScaleTwoAndRightToLeft;
    procedure TestAPressOnAnObjectKeepsItSelected;
    procedure TestDownLeavesATallPictureAndATallRow;
    procedure TestWordStepsStayOutOfACutParagraphsTail;
    procedure TestTheCaretTestsAtScaleTwo;
    procedure TestPageUpAndPageDownMoveTheCaret;
    procedure TestTheCaretIsScrolledAcross;
    procedure TestTheCaretOfACellInARowNotHeld;
    procedure TestADocumentChangeReportsTheSelectionIfItMoved;
    procedure TestWordStepsAcrossParagraphsAndCells;
    procedure TestHomeAndEndOnALineEndedByALineBreak;
    procedure TestTheTimersAndTheCursorOnAHandle;
    procedure TestACollapseOntoTheCaretKeepsItsLine;
    procedure TestAZoomForgetsTheWishedX;
    procedure TestAHugeSelLengthGoesToTheEnd;
    procedure TestThePublicQueriesCarryTheAffinity;
    procedure TestAChangeLeavesTheCaretOnACaretPlace;
    procedure TestAPaintAndABlinkInsideAnUpdate;
    procedure TestAnEditFromTheLastStepMovesTheCaret;
    procedure TestTheReplaceFallbackAndRefusal;
    procedure TestAStateLeavingTheLayerPathRepaints;
    procedure TestAStateFontIsALayoutChange;
    procedure TestAHoverAsksForARepaint;
    // fix wave W7: what the real window found, the re-reviews' items
    procedure TestTheLoadRunsInQueuedTurns;
    procedure TestAStepThatRaisesDoesNotStrandTheLoad;
    procedure TestASnapReportsOutsideThePaintAndTheQuery;
    procedure TestInputAndQueriesWaitForAnUpdate;
    procedure TestAPaintSkippedInAnUpdateIsMadeGood;
    procedure TestACancelNoticeIsTheLoadsOwn;
    procedure TestAPartialRowCopiesAsTheFilesRow;
    procedure TestARowShownWhileLoadingIsLaidOutWhole;
    procedure TestAPressedObjectKeepsItsAnchor;
    procedure TestTheExtentIsTheContentNotTheWrapWidth;
    procedure TestTheColumnSurvivesAZoomWhereItCanScroll;
    procedure TestAJumpLaysOutOnlyTheViewItArrivesAt;
    // fix wave W8
    procedure TestTheDriverIsChosenPerWidgetset;
    procedure TestSchedulingThatFailsEndsTheLoadQuietly;
    procedure TestAPaintSkippedInAnUpdateWithoutAChange;
    procedure TestTheSelectionSettersWaitForAnUpdate;
    procedure TestTheCursorForgetsThePaddingOnLeaving;
    procedure TestASliceBelowTheViewLaysOutNothing;
    procedure TestASlowFileGetsSmallerSlices;
    // fix wave W9
    procedure TestAStallCostsOneHalving;
    procedure TestTheBackstopRunsATurnOnlyWhenTheIdleStepIsStarved;
    procedure TestASlicesCostDoesNotGrowWithTheDocument;
    // fix wave W10
    procedure TestTheLoadsTurnsSetTheBarOncePerInterval;
    procedure TestAnOwedLoadEndRaisesFromItsEntryPoint;
    // on the component palette
    procedure TestInTheDesignerNothingRunsAndNothingIsTyped;
    procedure TestAFormFileHoldsNoContentAndItsSettingsRoundTrip;
  end;

implementation

uses
  LCLIntf, LCLPlatformDef, InterfaceBase, tyControls.StrConsts;

type
  { TTyRichEdit does not publish Lines; a descendant that does stores only what was set as
    lines. The form-file tests of Lines run on one. }
  TLinesRichEdit = class(TTyRichEdit)
  published
    property Lines;
  end;

  // the application's queue of asynchronous calls, run without pumping any message
  TAppQueue = class(TApplication)
  end;

{ Runs the calls queued to the application (QueueAsyncCall) - and nothing else: no message is
  pumped, no window shown. What the loop does between two of its turns. }
procedure RunQueuedCalls;
begin
  TAppQueue(Application).ProcessAsyncCallQueue;
end;

function CoversRect(const AOuter, AInner: TRect): Boolean; forward;

{ Runs the application's idle handlers (what its idle step runs after the queue) - and
  nothing else. True when they all left Done as it was. }
function RunIdleHandlers: Boolean;
var
  done: Boolean;
begin
  done := True;
  TAppQueue(Application).NotifyIdleHandler(done);
  Result := done;
end;

const
  BigLines = 2000000;

var
  GBig: TBytes;

function Sentinel: TBGRAPixel;
begin
  Result := BGRA(255, 0, 255, 255);
end;

function SamePx(const A, B: TBGRAPixel): Boolean;
begin
  Result := (A.red = B.red) and (A.green = B.green) and (A.blue = B.blue) and
    (A.alpha = B.alpha);
end;

{ 'Line 1' .. 'Line 2000000', one a paragraph (LF), made once. }
function BigText: TBytes;
var
  ms: TMemoryStream;
  i: Integer;
  s: RawByteString;
begin
  if GBig = nil then
  begin
    ms := TMemoryStream.Create;
    try
      ms.Size := 30 * BigLines;
      ms.Position := 0;
      for i := 1 to BigLines do
      begin
        s := 'Line ' + IntToStr(i);
        if i < BigLines then s := s + #10;
        ms.WriteBuffer(s[1], Length(s));
      end;
      SetLength(GBig, ms.Position);
      Move(ms.Memory^, GBig[0], ms.Position);
    finally
      ms.Free;
    end;
  end;
  Result := GBig;
end;

{ An RTF file of about ATarget bytes: one font, paragraphs of words. AParas: how many. }
function GeneratedRtf(ATarget: Int64; out AParas: Integer): TBytes;
var
  s: RawByteString;
  ms: TMemoryStream;
begin
  ms := TMemoryStream.Create;
  try
    s := '{\rtf1\ansi\ansicpg1252\deff0{\fonttbl{\f0\fswiss Arial;}}' + #13#10 + '\pard\f0\fs20 ';
    ms.WriteBuffer(s[1], Length(s));
    AParas := 0;
    while ms.Size < ATarget do
    begin
      s := 'Paragraph ' + IntToStr(AParas) + ' of the generated file, with \b some\b0  words.\par' +
        #13#10;
      ms.WriteBuffer(s[1], Length(s));
      Inc(AParas);
    end;
    s := '}' + #13#10;
    ms.WriteBuffer(s[1], Length(s));
    // (a \par that ends the document ends its last paragraph: no empty one follows)
    Result := nil;
    SetLength(Result, ms.Size);
    Move(ms.Memory^, Result[0], ms.Size);
  finally
    ms.Free;
  end;
end;

function PngBytes(AW, AH: Integer; AColor: TBGRAPixel): TBytes;
var
  b: TBGRABitmap;
  st: TBytesStream;
begin
  b := TBGRABitmap.Create(AW, AH, AColor);
  st := TBytesStream.Create;
  try
    b.SaveToStreamAsPng(st);
    Result := Copy(st.Bytes, 0, st.Size);
  finally
    st.Free;
    b.Free;
  end;
end;

function FileBytes(const APath: string): TBytes;
var
  f: TFileStream;
begin
  Result := nil;
  f := TFileStream.Create(APath, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, f.Size);
    if f.Size > 0 then f.ReadBuffer(Result[0], f.Size);
  finally
    f.Free;
  end;
end;

function SameBytes(const A, B: TBytes): Boolean;
begin
  Result := (Length(A) = Length(B)) and ((Length(A) = 0) or CompareMem(@A[0], @B[0], Length(A)));
end;

function StreamBytes(AStream: TMemoryStream): TBytes;
begin
  Result := nil;
  SetLength(Result, AStream.Size);
  if AStream.Size > 0 then Move(AStream.Memory^, Result[0], AStream.Size);
end;

function FixtureDir(const ASub: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'tests' + PathDelim + 'fixtures' +
    PathDelim + ASub + PathDelim;
end;

{ ---- the probe ---- }

function TRichProbe.CreateDevice: TTyRichTextDevice;
begin
  Result := TTyRichTestDevice.Create;
end;

function TProbeLayouter.ScaleImage(AImage: TBGRABitmap; AWidth, AHeight: Integer): TBGRABitmap;
begin
  if FailScale then raise EInvalidOperation.Create('the test''s failing resample');
  Result := inherited ScaleImage(AImage, AWidth, AHeight);
end;

function TProbeLayouter.DecodeImage(AStream: TStream; AJpegScale: Integer): TBGRABitmap;
begin
  if FailDecode then
  begin
    Inc(FailedDecodes);
    raise EAccessViolation.Create('the test''s failing decode');
  end;
  Result := inherited DecodeImage(AStream, AJpegScale);
end;

function TRichProbe.IdleTicks: QWord;
var
  load: TTyRtfLoad;
  done: Int64;
begin
  if FakeRate > 0 then
  begin
    if StallReadings > 0 then
    begin
      Dec(StallReadings);
      if StallReadings = 0 then Inc(ClockNow, StallMs);
    end;
    load := TyRichRtfLoadOf(Document);
    if load <> nil then done := load.BytesIndexed else done := 0;
    Exit(ClockNow + QWord(done div FakeRate));
  end;
  if FakeClock then
  begin
    Inc(ClockNow, ClockStep);
    Exit(ClockNow);
  end;
  if FrozenClock then Result := 0 else Result := inherited IdleTicks;
end;

function TRichProbe.NextSlice: Int64;
begin
  Result := inherited SliceBytes;
end;

function TRichProbe.SliceBytes: Int64;
begin
  Result := inherited SliceBytes;
  if LogSlices then
  begin
    SetLength(SliceLog, Length(SliceLog) + 1);
    SliceLog[High(SliceLog)] := Result;
  end;
end;

function TRichProbe.BackstopOf: TTimer;
begin
  Result := BackstopTimer;
end;

procedure TRichProbe.BackstopNow;
begin
  BackstopTick(nil);
end;

function TRichProbe.Turns: Int64;
begin
  Result := TurnsRun;
end;

procedure TRichProbe.Turn;
begin
  BackgroundTurn;
end;

procedure TRichProbe.Down;
begin
  MouseDown(mbLeft, [], 20, 20);
end;

procedure TRichProbe.Up;
begin
  MouseUp(mbLeft, [], 20, 20);
end;

function TRichProbe.Detect(AStream: TStream): TTyRichFormat;
begin
  Result := DetectFormat(AStream);
end;

procedure TRichProbe.FullFrame(ABitmap: TBGRABitmap; APPI: Integer);
var
  P: TTyPainter;
  sc: TTyCanvasScale;
  s: TTyStyleSet;
begin
  s := CurrentStyle;
  ABitmap.FillRect(0, 0, ABitmap.Width, ABitmap.Height, TyColorToBGRA(s.Background.Color), dmSet);
  P := TTyPainter.Create;
  try
    sc.Scale := DeviceScale;
    sc.DeviceUnits := False;
    P.BeginPaintOnScaled(nil, Rect(0, 0, Width, Height), APPI, ABitmap, sc);
    DrawFrame(P, Rect(0, 0, Width, Height), s);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TRichProbe.DropHandle;
begin
  DestroyHandle;
end;

function TRichProbe.Ground: TBGRAPixel;
begin
  Result := TyColorToBGRA(CurrentStyle.Background.Color);
end;

function TRichProbe.CreateLayouter: TTyRichLayouter;
begin
  Result := TProbeLayouter.Create(CreateDevice, True);
end;

function TRichProbe.Lay: TProbeLayouter;
begin
  Result := Layouter as TProbeLayouter;
end;

function TRichProbe.LayoutBlockAt(AIndex: Integer): TTyBlockLayout;
var
  before: Int64;
begin
  if RaiseAfter > 0 then
  begin
    Dec(RaiseAfter);
    if RaiseAfter = 0 then raise EInvalidOperation.Create('the test''s failing layout');
  end;
  before := Layouter.CacheMisses;
  Result := inherited LayoutBlockAt(AIndex);
  SetLength(Given, Length(Given) + 1);
  Given[High(Given)] := Result;
  if Layouter.CacheMisses > before then
  begin
    Inc(FLaidParas, Result.LastPara - Result.FirstPara + 1);
    if Result.FirstPara < FLaidMin then FLaidMin := Result.FirstPara;
    if Result.LastPara > FLaidMax then FLaidMax := Result.LastPara;
  end;
end;

procedure TRichProbe.InvalidateArea(const ARect: TRect);
begin
  SetLength(Invalidated, Length(Invalidated) + 1);
  Invalidated[High(Invalidated)] := ARect;
  inherited InvalidateArea(ARect);
end;

procedure TRichProbe.PaintBlock(ABitmap: TBGRABitmap; AIndex, AX, AY: Integer;
  const AClip: TRect; const AStyle: TTyRichPaintStyle);
begin
  if RaiseOnBlock > 0 then
  begin
    Dec(RaiseOnBlock);
    if RaiseOnBlock = 0 then raise EInvalidOperation.Create('the test''s failing block');
  end;
  Inc(FBlockPaints);
  inherited PaintBlock(ABitmap, AIndex, AX, AY, AClip, AStyle);
end;

procedure TRichProbe.PaintSurfaceFrame(APPI: Integer);
begin
  Inc(FFramePaints);
  inherited PaintSurfaceFrame(APPI);
end;

function TRichProbe.Surf: TBGRABitmap;
begin
  Result := Surface;
end;

function TRichProbe.Scale: Integer;
begin
  Result := DeviceScale;
end;

procedure TRichProbe.RedrawAll;
begin
  InvalidateSurface;
end;

procedure TRichProbe.InvalidatePart(const ARect: TRect);
begin
  InvalidateContent(ARect);
end;

procedure TRichProbe.WheelH(ADelta: Integer);
begin
  DoMouseWheelHorz([], ADelta, Point(10, 10));
end;

procedure TRichProbe.Hover(AOn: Boolean);
begin
  if AOn then MouseEnter else MouseLeave;
end;

function TRichProbe.ScrollBarLimit: Integer;
begin
  if BarLimit > 0 then Result := BarLimit else Result := inherited ScrollBarLimit;
end;

procedure TRichProbe.ResetCounts;
begin
  FLaidParas := 0;
  FLaidMin := MaxInt;
  FLaidMax := -1;
  Invalidated := nil;
  Invalidates := 0;
  Given := nil;
  FBlockPaints := 0;
  FFramePaints := 0;
  if Layouter <> nil then Device.ResetCounters;
end;

procedure TRichProbe.PaintPart(ACanvas: TCanvas; const AClip: TRect; ADefer: Boolean);
begin
  PaintArea(ACanvas, Rect(0, 0, Width, Height), AClip, Font.PixelsPerInch, ADefer);
end;

function TRichProbe.Step: Boolean;
begin
  Result := StepBackground;
end;

function TRichProbe.Pending: Integer;
begin
  Result := PendingPictureCount;
end;

function TRichProbe.VBar: TTyScrollBar;
begin
  Result := VerticalBar;
end;

function TRichProbe.HBar: TTyScrollBar;
begin
  Result := HorizontalBar;
end;

function TRichProbe.TypeKey: string;
begin
  Result := GetStyleTypeKey;
end;

function TRichProbe.Style: TTyRichPaintStyle;
begin
  Result := Default(TTyRichPaintStyle);
  FillPaintStyle(Result);
end;

function TRichProbe.Area: TRect;
begin
  Result := TextArea(Rect(0, 0, Width, Height), Font.PixelsPerInch);
end;

procedure TRichProbe.Slices(AFirst, AStep: Int64);
begin
  FirstSliceBytes := AFirst;
  StepBytes := AStep;
end;

procedure TRichProbe.Press(AKey: Word; AShift: TShiftState);
begin
  KeyDown(AKey, AShift);
end;

procedure TRichProbe.Wheel(ADelta: Integer; AShift: TShiftState);
begin
  DoMouseWheel(AShift, ADelta, Point(10, 10));
end;

function TRichProbe.Device: TTyRichTestDevice;
begin
  Result := Layouter.Device as TTyRichTestDevice;
end;

function TRichProbe.HasCaretFocus: Boolean;
begin
  Result := ForceFocus or inherited HasCaretFocus;
end;

procedure TRichProbe.WriteClipboard(const ARtf: RawByteString; const AText: string);
begin
  Inc(ClipWrites);
  if FailClip then raise EInvalidOperation.Create('the test''s failing clipboard');
  ClipRtf := ARtf;
  ClipText := AText;
end;

function TRichProbe.ClipboardFormatList: TTyRichClipFormats;
begin
  Inc(FormatAsks);
  Result := Copy(ClipFormats, 0, Length(ClipFormats));
end;

function TRichProbe.ClipboardFlavours: TTyRichClipFlavours;
begin
  Inc(FlavourAsks);
  if FromFormats then Exit(inherited ClipboardFlavours);
  Result := [];
  if ClipRtf <> '' then Include(Result, rcfRtf);
  if (Length(ClipPicture) > 0) or (Length(ClipPicture2) > 0) then Include(Result, rcfPicture);
  if ClipText <> '' then Include(Result, rcfText);
end;

function TRichProbe.ReadRtfSource(const ABytes: TBytes; out AEndsWithParagraph: Boolean): TTyRichDocument;
begin
  if RtfSource = nil then Exit(inherited ReadRtfSource(ABytes, AEndsWithParagraph));
  Result := RtfSource;
  AEndsWithParagraph := RtfSourceEnds;
  RtfSource := nil;
end;

function TRichProbe.ReadClipboardRtf: RawByteString;
begin
  Inc(RtfReads);
  Result := ClipRtf;
end;

function TRichProbe.ReadClipboardPicture(AIndex: Integer; out AKind: TTyRichImageKind;
  out ABytes: TBytes): Boolean;
begin
  Result := AIndex in [0, 1];
  ABytes := nil;
  AKind := ClipPictureKind;
  if not Result then Exit;
  Inc(PictureReads);
  if AIndex = 0 then ABytes := ClipPicture
  else
  begin
    AKind := ClipPictureKind2;
    ABytes := ClipPicture2;
  end;
end;

function TRichProbe.ReadClipboardText: string;
begin
  Inc(TextReads);
  Result := ClipText;
end;

procedure TRichProbe.ClipReset;
begin
  FormatAsks := 0;
  FlavourAsks := 0;
  RtfReads := 0;
  PictureReads := 0;
  TextReads := 0;
  HtmlReads := 0;
  Waits := 0;
  WaitEnds := 0;
end;

procedure TRichProbe.BeginWait;
begin
  Inc(Waits);
end;

procedure TRichProbe.EndWait;
begin
  Inc(WaitEnds);
end;

procedure TRichProbe.ShowTextMenu(const APos: TPoint);
begin
  Inc(MenuShows);
end;

procedure TRichProbe.SetCopyWait(AChars: Int64);
begin
  CopyWaitChars := AChars;
end;

function TRichProbe.PopupAt(X, Y: Integer): Boolean;
begin
  Result := False;
  DoContextPopup(Point(X, Y), Result);
end;

procedure TRichProbe.PressAt(X, Y: Integer; AShift: TShiftState);
begin
  MouseDown(mbLeft, AShift + [ssLeft], X, Y);
end;

procedure TRichProbe.MoveAt(X, Y: Integer);
begin
  MouseMove([ssLeft], X, Y);
end;

procedure TRichProbe.ReleaseAt(X, Y: Integer);
begin
  MouseUp(mbLeft, [], X, Y);
end;

procedure TRichProbe.RightAt(X, Y: Integer);
begin
  MouseDown(mbRight, [ssRight], X, Y);
  MouseUp(mbRight, [], X, Y);
end;

function TRichProbe.KeyResult(AKey: Word; AShift: TShiftState): Word;
begin
  Result := AKey;
  KeyDown(Result, AShift);
end;

procedure TRichProbe.DragTick;
begin
  DragScrollTick(nil);
end;

procedure TRichProbe.Blink;
begin
  BlinkTick(nil);
end;

procedure TRichProbe.CaretOn(ACanvas: TCanvas);
begin
  DrawCaret(ACanvas);
end;

function TRichProbe.CursorFor(X, Y: Integer): TCursor;
begin
  Result := CursorAt(X, Y);
end;

function TRichProbe.DragOn: Boolean;
begin
  Result := Dragging;
end;

function TRichProbe.TextWindow: TRect;
begin
  Result := TextWindowRect;
end;

procedure TRichProbe.PostCall(ACall: TTyRichQueuedCall);
begin
  Inc(Posts);
  if FailPost then raise Exception.Create('the test''s queue that will not take a call');
  inherited PostCall(ACall);
end;

procedure TRichProbe.WatchIdle(AOn: Boolean);
begin
  if AOn then Inc(Watches) else Inc(Unwatches);
  inherited WatchIdle(AOn);
end;

procedure TRichProbe.IdleStep(Sender: TObject; var Done: Boolean);
begin
  Inc(IdleEntries);
  inherited IdleStep(Sender, Done);
end;

function TRichProbe.TurnDriver: TTyRichTurnDriver;
begin
  if ForceTimer then Result := rtdTimer else Result := inherited TurnDriver;
end;

function TRichProbe.SchedulingClosed: Boolean;
begin
  Result := ClosedApp or inherited SchedulingClosed;
end;

function TRichProbe.IdleOn: Boolean;
begin
  Result := IdleWatched;
end;

function TRichProbe.TimerOf: TTimer;
begin
  Result := TurnTimer;
end;

procedure TRichProbe.HoverOut;
begin
  MouseLeave;
end;

procedure TRichProbe.RemovePostedCall(ACall: TTyRichQueuedCall);
begin
  Inc(Removes);
  inherited RemovePostedCall(ACall);
end;

function TRichProbe.TurnQueued: Boolean;
begin
  Result := BackgroundCall.Queued;
end;

function TRichProbe.ReportQueued: Boolean;
begin
  Result := SelectionCall.Queued;
end;

function TRichProbe.ImeRect: TRect;
begin
  Result := ImeCaretBoundClient;
end;

procedure TRichProbe.Invalidate;
begin
  Inc(Invalidates);
  inherited Invalidate;
end;

procedure TRichProbe.SetTempCursor(Value: TCursor);
begin
  SetLength(TempCursors, Length(TempCursors) + 1);
  TempCursors[High(TempCursors)] := Value;
  inherited SetTempCursor(Value);
end;

procedure TRichProbe.Enter;
begin
  DoEnter;
end;

procedure TRichProbe.MakeDesigning;
begin
  SetDesigning(True, False);
end;

procedure TRichProbe.TypeChar(const AChar: TUTF8Char);
var
  k: TUTF8Char;
begin
  k := AChar;
  UTF8KeyPress(k);
end;

function TRichProbe.BlinkTimerOf: TTimer;
begin
  Result := BlinkTimer;
end;

function TRichProbe.DragTimerOf: TTimer;
begin
  Result := DragTimer;
end;

{ ---- the suite ---- }

procedure TTyRichEditControlTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FRich := NewProbe;
  FTemp := '';
  FChanges := 0;
  FZooms := 0;
  FLoadCalls := 0;
  FCancelAt := 0;
  FRefused := 0;
  FPaintScale := 1;
end;

procedure TTyRichEditControlTest.TearDown;
var
  sr: TSearchRec;
begin
  TyForceDeviceScaleForTest(0, False);
  FreeAndNil(FRich);
  FreeAndNil(FCtl);
  if (FTemp <> '') and DirectoryExists(FTemp) then
  begin
    if FindFirst(FTemp + '*', faAnyFile, sr) = 0 then
    try
      repeat
        if (sr.Attr and faDirectory) = 0 then DeleteFile(FTemp + sr.Name);
      until FindNext(sr) <> 0;
    finally
      FindClose(sr);
    end;
    RemoveDir(FTemp);
  end;
end;

function TTyRichEditControlTest.NewProbe: TRichProbe;
begin
  Result := TRichProbe.Create(nil);
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, 400, 300);
  Result.ResetCounts;
end;

procedure TTyRichEditControlTest.Changed(Sender: TObject);
begin
  Inc(FChanges);
end;

procedure TTyRichEditControlTest.Zoomed(Sender: TObject);
begin
  Inc(FZooms);
end;

procedure TTyRichEditControlTest.LoadCalled(Sender: TObject; ADone, ATotal: Int64;
  var ACancel: Boolean);
begin
  Inc(FLoadCalls);
  if (FCancelAt > 0) and (FLoadCalls >= FCancelAt) then ACancel := True;
end;

procedure TTyRichEditControlTest.SaveCancel(Sender: TObject; ADone, ATotal: Int64;
  var ACancel: Boolean);
begin
  Inc(FLoadCalls);
  ACancel := True;
end;

procedure TTyRichEditControlTest.LoadBig;
var
  st: TBytesStream;
begin
  st := TBytesStream.Create(BigText);
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
end;

{ Lines of the base font the text area holds. }
function TTyRichEditControlTest.ScreenLines: Integer;
var
  a: TRect;
begin
  a := FRich.Area;
  Result := (a.Bottom - a.Top) div FRich.Layouter.EstimatedParaHeight(96, FRich.Zoom / 100) + 1;
end;

function TTyRichEditControlTest.TempFile(const AName: string; const ABytes: TBytes): string;
var
  f: TFileStream;
begin
  if FTemp = '' then
  begin
    // the process id: two runs of this suite at once (mutation shards) have folders of their own
    FTemp := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'tyrichedit9a-' +
      IntToStr(GetProcessID) + '-' + IntToHex(Random($7FFFFFFF), 8) + PathDelim;
    ForceDirectories(FTemp);
  end;
  Result := FTemp + AName;
  f := TFileStream.Create(Result, fmCreate);
  try
    if Length(ABytes) > 0 then f.WriteBuffer(ABytes[0], Length(ABytes));
  finally
    f.Free;
  end;
end;

{ ABand is AWant's rows, as wide as the text and reaching into its left padding. }
function SameBand(const AWant, ABand: TRect): Boolean;
begin
  Result := (ABand.Top = AWant.Top) and (ABand.Bottom = AWant.Bottom) and
    (ABand.Right = AWant.Right) and (ABand.Left <= AWant.Left) and (ABand.Left >= 0);
end;

function TTyRichEditControlTest.InView(APara: Integer): Boolean;
var
  r, a: TRect;
begin
  r := FRich.ParagraphRect(APara);
  a := FRich.Area;
  Result := (r.Bottom > r.Top) and (r.Bottom > a.Top) and (r.Top < a.Bottom);
end;

{ The plan's: a 2,000,000-line txt loaded and its first screen painted lays out no more than
  the visible lines and two screens. }
procedure TTyRichEditControlTest.TestLoadShowsTheFirstScreenWithoutLayingOutTheRest;
var
  bmp: TBitmap;
  n: Integer;
begin
  LoadBig;
  AssertEquals('all the lines', BigLines, FRich.Document.Text.ParaCount);
  FRich.ResetCounts;
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(400, 300);
    FRich.RenderTo(bmp.Canvas, Rect(0, 0, 400, 300), 96);
  finally
    bmp.Free;
  end;
  n := ScreenLines;
  AssertTrue(Format('laid out %d paragraphs, a screen is %d lines', [FRich.LaidParas, n]),
    (FRich.LaidParas > 0) and (FRich.LaidParas <= 3 * n + 2));
  AssertEquals('from the top', 0, FRich.LaidMin);
  AssertTrue('the first line is on screen', InView(0));
  AssertTrue('the scroll bar spans the document',
    (FRich.VBar <> nil) and FRich.VBar.Visible and (FRich.VBar.Max > 100 * n));
end;

{ The plan's: the scroll position set to the middle lays out only around it. }
procedure TTyRichEditControlTest.TestScrollingToTheMiddleLaysOutOnlyNearby;
var
  n, mid: Integer;
begin
  LoadBig;
  FRich.UpdateView;
  FRich.ResetCounts;
  FRich.ScrollY := FRich.Document.Text.TotalHeight div 2;
  FRich.UpdateView;
  n := ScreenLines;
  mid := BigLines div 2;
  AssertTrue(Format('the view is at the middle (top %d)', [FRich.TopParagraph]),
    Abs(FRich.TopParagraph - mid) <= 2);
  AssertTrue(Format('laid out %d .. %d', [FRich.LaidMin, FRich.LaidMax]),
    (FRich.LaidMin >= mid - 2 * n) and (FRich.LaidMax <= mid + 3 * n));
  AssertTrue(Format('%d paragraphs laid out', [FRich.LaidParas]), FRich.LaidParas <= 3 * n + 2);
end;

{ The plan's: laying out the paragraphs above (taller than their estimates) does not move the
  first line on screen; the scroll position (the sum of the heights above) moves instead. }
procedure TTyRichEditControlTest.TestScrollPositionStaysPutWhenEstimatesAreCorrected;
var
  s: string;
  i, est: Integer;
  sl: TStringList;
  before: Int64;
begin
  sl := TStringList.Create;
  try
    s := '';
    for i := 1 to 50 do s := s + 'word' + IntToStr(i mod 7) + ' ';
    for i := 0 to 399 do sl.Add(IntToStr(i) + ' ' + s);
    FRich.Lines := sl;
  finally
    sl.Free;
  end;
  // nothing is laid out yet: a position is the estimates' sum
  FRich.ScrollY := 1;
  est := FRich.Layouter.EstimatedParaHeight(96, 1);
  AssertEquals('nothing measured', 0, FRich.Document.Text.MeasuredParaCount);
  FRich.ScrollY := Int64(200) * est;
  AssertEquals('at paragraph 200', 200, FRich.TopParagraph);
  AssertEquals('at its top', 0, FRich.TopOffset);
  // the anchor's position as the estimates put it (ScrollY would lay the view out first)
  before := FRich.Document.Text.ParaTop(FRich.TopParagraph) + FRich.TopOffset;
  FRich.UpdateView;
  AssertTrue('the paragraphs above were laid out taller than estimated',
    FRich.ScrollY > before + 4 * est);
  AssertEquals('the first line stays paragraph 200', 200, FRich.TopParagraph);
  AssertEquals('at the same offset', 0, FRich.TopOffset);
  AssertEquals('on the screen''s top', FRich.Area.Top, FRich.ParagraphRect(200).Top);
  // inside a block too
  FRich.ScrollViewBy(est + 3);
  FRich.UpdateView;
  AssertEquals('scrolled into it', 200, FRich.TopParagraph);
  AssertEquals('by that much', est + 3, FRich.TopOffset);
  AssertEquals('its top above the screen by it', FRich.Area.Top - est - 3,
    FRich.ParagraphRect(200).Top);
end;

{ The plan's: a format changed by code invalidates the changed paragraph's rectangle only; a
  change of its height, it and what is below it. }
procedure TTyRichEditControlTest.TestPartialRepaintCoversOnlyTheChangedParagraph;
var
  sl: TStringList;
  i: Integer;
  f: TTyCharFormat;
  r5, r7, a: TRect;
  t: TTyRichText;
begin
  sl := TStringList.Create;
  try
    for i := 0 to 199 do sl.Add('Line ' + IntToStr(i));
    FRich.Lines := sl;
  finally
    sl.Free;
  end;
  FRich.UpdateView;
  t := FRich.Document.Text;
  r5 := FRich.ParagraphRect(5);
  AssertTrue('paragraph 5 is on screen', r5.Bottom > r5.Top);
  FRich.ResetCounts;
  f := TyDefaultCharFormat;
  f.Color := clRed;
  AssertTrue('a colour from code', FRich.Document.Execute(TTyRichSetCharFormat.Create(
    TyRichRange(t.ParaStart(5), t.ParaLength(5)), [cffColor], f)));
  AssertEquals('one rectangle', 1, Length(FRich.Invalidated));
  AssertTrue('the paragraph''s', SameBand(r5, FRich.Invalidated[0]));
  AssertEquals('one block laid out again', 1, FRich.LaidParas);
  // a taller paragraph moves what is below it
  r7 := FRich.ParagraphRect(7);
  a := FRich.Area;
  FRich.ResetCounts;
  f.SizeHalfPt := 48;
  AssertTrue('a size from code', FRich.Document.Execute(TTyRichSetCharFormat.Create(
    TyRichRange(t.ParaStart(7), t.ParaLength(7)), [cffSize], f)));
  AssertEquals('one rectangle', 1, Length(FRich.Invalidated));
  AssertTrue('from the paragraph to the bottom', SameBand(Rect(a.Left, r7.Top, a.Right,
    a.Bottom), FRich.Invalidated[0]));
  // a change below the view and the blocks it holds invalidates nothing
  FRich.UpdateView;
  FRich.ResetCounts;
  AssertTrue('far below', FRich.Document.Execute(TTyRichSetCharFormat.Create(
    TyRichRange(t.ParaStart(190), t.ParaLength(190)), [cffSize], f)));
  FRich.UpdateView;
  AssertEquals('nothing on screen changed', 0, Length(FRich.Invalidated));
  // nor does a taller paragraph above the view: the first line on screen holds
  FRich.ScrollY := FRich.Document.Text.ParaTop(120);
  FRich.UpdateView;
  r5 := FRich.ParagraphRect(120);
  AssertTrue('paragraph 115 is laid out above the view', FRich.ParagraphRect(115).Bottom <= a.Top);
  FRich.ResetCounts;
  AssertTrue('above', FRich.Document.Execute(TTyRichSetCharFormat.Create(
    TyRichRange(t.ParaStart(115), t.ParaLength(115)), [cffSize], f)));
  FRich.UpdateView;
  AssertEquals('nothing on screen moved', 0, Length(FRich.Invalidated));
  AssertEquals('the same first paragraph', 120, FRich.TopParagraph);
  AssertTrue('in the same place', EqualRect(r5, FRich.ParagraphRect(120)));
end;

{ The plan's: zooming changes what is shown, not the document - no OnChange - and the page's
  layout width scales with it; the zoom is clamped to 10 .. 500 and reports itself. }
procedure TTyRichEditControlTest.TestZoomChangesDisplayOnly;
var
  w100, w200: Integer;
begin
  FRich.Lines.Text := 'One paragraph'#13#10'and another';
  FRich.OnChange := @Changed;
  FRich.OnZoomChange := @Zoomed;
  FRich.WrapMode := rwmPage;
  FRich.UpdateView;
  w100 := FRich.VisibleBlocks[0].Layout.LayoutWidth;
  FRich.Zoom := 200;
  FRich.UpdateView;
  w200 := FRich.VisibleBlocks[0].Layout.LayoutWidth;
  AssertTrue(Format('the page twice as wide (%d, %d)', [w100, w200]), Abs(w200 - 2 * w100) <= 1);
  AssertEquals('no document change', 0, FChanges);
  AssertFalse('not modified', FRich.Modified);
  AssertEquals('one zoom change', 1, FZooms);
  FRich.Zoom := 1000;
  AssertEquals('at most 500', 500, FRich.Zoom);
  FRich.Zoom := 1;
  AssertEquals('at least 10', 10, FRich.Zoom);
  AssertEquals('each reported', 3, FZooms);
  FRich.Zoom := 10;
  AssertEquals('no change, no report', 3, FZooms);
  AssertEquals('still no document change', 0, FChanges);
end;

procedure TTyRichEditControlTest.TestTheTypeKeyHangsUnderTheMemo;
var
  s: TTyStyleSet;
begin
  AssertEquals('its own key', 'TyRichEdit', FRich.TypeKey);
  AssertEquals('under the memo''s', 'TyMemo', TyTypeKeyParent('TyRichEdit'));
  FCtl.LoadThemeCss('TyMemo { background: #123456; color: #654321; padding: 7px; }');
  s := FRich.ScrollBarFrameStyle;
  AssertTrue('the memo''s background', (tpBackground in s.Present) and
    (TyRedOf(s.Background.Color) = $12) and (TyBlueOf(s.Background.Color) = $56));
  AssertEquals('the memo''s padding', 7, FRich.Area.Left);
  AssertTrue('the memo''s text colour', SamePx(BGRA($65, $43, $21, 255), FRich.Style.TextColor));
end;

procedure TTyRichEditControlTest.TestSelectionColoursResolveInEveryBuiltinTheme;
var
  c: TTyStyleController;
  names: TStringArray;
  i, m, k: Integer;
  mode, who: string;
  ground, sel: TTyStyleSet;
  st: TTyRichPaintStyle;
  g, p: TBGRAPixel;
begin
  TyRegisterBuiltinThemes;
  names := TyBuiltinThemeNames;
  AssertTrue('the built-in themes', Length(names) >= 17);
  c := TTyStyleController.Create(nil);
  try
    for i := 0 to High(names) do
      for m := 0 to 1 do
      begin
        if m = 0 then mode := 'light' else mode := 'dark';
        c.ThemeName := names[i];
        c.Mode := mode;
        ground := c.Model.ResolveStyle('TyRichEdit', '', []);
        AssertTrue(names[i] + '/' + mode + ': a ground', tpBackground in ground.Present);
        g := TyColorToBGRA(ground.Background.Color);
        for k := 0 to 1 do
        begin
          if k = 0 then sel := c.Model.ResolveStyle('TyRichEditSelection', '', [])
          else sel := c.Model.ResolveStyle('TyRichEditSelection', '', [tysFocused]);
          who := Format('%s/%s selection %d', [names[i], mode, k]);
          AssertTrue(who + ': resolves', tpBackground in sel.Present);
          p := TyColorToBGRA(sel.Background.Color);
          AssertTrue(who + ': not transparent', p.alpha > 0);
          // laid over the ground it shows
          AssertTrue(who + ': differs from the ground',
            (Abs(p.red - g.red) + Abs(p.green - g.green) + Abs(p.blue - g.blue)) * p.alpha >
            8 * 255);
        end;
      end;
  finally
    c.Free;
  end;
  // the control paints with what its theme says
  FCtl.LoadThemeCss('TyRichEditSelection { background: #FF0000; }' +
    'TyRichEditObject { border-color: #00FF00; }' +
    'TyRichEditPlaceholder { background: #0000FF; border-color: #FFFF00; }');
  st := FRich.Style;
  AssertTrue('selection', SamePx(BGRA(255, 0, 0, 255), st.SelectionBack));
  AssertTrue('object frame', SamePx(BGRA(0, 255, 0, 255), st.ObjectFrame));
  AssertTrue('placeholder fill', SamePx(BGRA(0, 0, 255, 255), st.PlaceholderFill));
  AssertTrue('placeholder frame', SamePx(BGRA(255, 255, 0, 255), st.PlaceholderFrame));
end;

procedure TTyRichEditControlTest.TestALazyRtfPaintsItsFirstScreenWhileLoading;
var
  b: TBytes;
  paras, first, n, steps, x, y, ink: Integer;
  st: TBytesStream;
  bmp: TBitmap;
  bg: TBGRABitmap;
  a: TRect;
begin
  b := GeneratedRtf(2 * 1024 * 1024, paras);
  FRich.Slices(64 * 1024, 64 * 1024);
  FRich.OnChange := @Changed;
  FRich.OnLoadProgress := @LoadCalled;
  st := TBytesStream.Create(b);
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  AssertTrue('still loading', FRich.Loading);
  AssertEquals('the load is one change', 1, FChanges);
  first := FRich.Document.Text.ParaCount;
  AssertTrue(Format('a part (%d of %d)', [first, paras]), (first > 10) and (first < paras div 4));
  FRich.ResetCounts;
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(400, 300);
    bmp.Canvas.Brush.Color := RGBToColor(255, 0, 255);
    bmp.Canvas.FillRect(0, 0, 400, 300);
    FRich.RenderTo(bmp.Canvas, Rect(0, 0, 400, 300), 96);
    bg := TBGRABitmap.Create(bmp);
    try
      a := FRich.Area;
      ink := 0;
      for y := a.Top to a.Bottom - 1 do
        for x := a.Left to a.Right - 1 do
          if not SamePx(bg.GetPixel(x, y), FRich.Style.TextColor) then Continue else Inc(ink);
    finally
      bg.Free;
    end;
  finally
    bmp.Free;
  end;
  AssertTrue('the first screen is painted', ink > 50);
  AssertTrue('while still loading', FRich.Loading);
  n := ScreenLines;
  AssertTrue(Format('only the first blocks laid out (%d)', [FRich.LaidParas]),
    (FRich.LaidParas <= 3 * n + 2) and (FRich.LaidMax <= 3 * n + 2));
  steps := 0;
  while FRich.Loading and (steps < 3) do
  begin
    AssertTrue('a step', FRich.Step);
    Inc(steps);
  end;
  AssertTrue('progress reported', FLoadCalls >= 3);
  AssertTrue('the document grew', FRich.Document.Text.ParaCount > first);
  AssertEquals('slices are no changes of the content', 1, FChanges);
  FRich.FinishLoading;
  AssertFalse('loaded', FRich.Loading);
  AssertFalse('complete', FRich.Incomplete);
  AssertEquals('every paragraph', paras, FRich.Document.Text.ParaCount);
  AssertEquals('still one change', 1, FChanges);
end;

procedure TTyRichEditControlTest.TestACancelledLoadIsIncompleteAndNotSavedOverItsFile;
var
  b: TBytes;
  paras: Integer;
  path: string;
  raised: Boolean;
  ms: TMemoryStream;
begin
  b := GeneratedRtf(2 * 1024 * 1024, paras);
  path := TempFile('big.rtf', b);
  FRich.Slices(64 * 1024, 64 * 1024);
  FRich.OnLoadProgress := @LoadCalled;
  FCancelAt := 2;
  FRich.LoadFromFile(path);
  AssertTrue('loading', FRich.Loading);
  while FRich.Loading and FRich.Step do ;
  AssertFalse('stopped', FRich.Loading);
  AssertTrue('incomplete', FRich.Incomplete);
  AssertTrue('a part', FRich.Document.Text.ParaCount < paras);
  AssertEquals('cancelled where it was asked to', 2, FLoadCalls);
  raised := False;
  try
    FRich.SaveToFile(path);
  except
    on E: ETyRichEdit do raised := True;
  end;
  AssertTrue('not saved over its file', raised);
  AssertTrue('the file is as it was', SameBytes(b, FileBytes(path)));
  raised := False;
  ms := TMemoryStream.Create;
  try
    try
      FRich.SaveToStream(ms);
    except
      on E: ETyRichEdit do raised := True;
    end;
    AssertTrue('nor anywhere', raised);
    AssertEquals('nothing written', 0, ms.Size);
  finally
    ms.Free;
  end;
  // still readable
  FRich.UpdateView;
  AssertTrue('shows its part', FRich.VisibleBlockCount > 0);
end;

{ Loaded through the control, saved through the control: the same bytes - also saved over the
  very file the document reads from, after which it still reads (saved again: the same). }
procedure TTyRichEditControlTest.TestEveryFixtureSavesBackByteForByte;
var
  sr: TSearchRec;
  dirs: array[0..1] of string;
  d, count: Integer;
  orig: TBytes;
  path: string;
  ms: TMemoryStream;
begin
  dirs[0] := 'rtf';
  dirs[1] := 'txt';
  count := 0;
  for d := 0 to 1 do
    if FindFirst(FixtureDir(dirs[d]) + '*', faAnyFile, sr) = 0 then
    try
      repeat
        if (sr.Attr and faDirectory) <> 0 then Continue;
        orig := FileBytes(FixtureDir(dirs[d]) + sr.Name);
        path := TempFile(sr.Name, orig);
        FreeAndNil(FRich);
        FRich := NewProbe;
        FRich.LoadFromFile(path);
        FRich.UpdateView;
        ms := TMemoryStream.Create;
        try
          FRich.SaveToStream(ms);
          AssertTrue(sr.Name + ': saved as it came', SameBytes(orig, StreamBytes(ms)));
          FRich.SaveToFile(path);
          AssertTrue(sr.Name + ': saved over its file', SameBytes(orig, FileBytes(path)));
          ms.Clear;
          FRich.UpdateView;
          FRich.ScrollToEnd;
          FRich.UpdateView;
          FRich.SaveToStream(ms);
          AssertTrue(sr.Name + ': and still reads', SameBytes(orig, StreamBytes(ms)));
        finally
          ms.Free;
        end;
        Inc(count);
      until FindNext(sr) <> 0;
    finally
      FindClose(sr);
    end;
  AssertTrue(Format('the fixtures (%d)', [count]), count >= 50);
end;

procedure TTyRichEditControlTest.TestACancelledSaveLeavesTheFileAsItWas;
var
  b: TBytes;
  paras: Integer;
  path: string;
  raised: Boolean;
  sr: TSearchRec;
  files: Integer;
begin
  b := GeneratedRtf(2 * 1024 * 1024, paras);
  path := TempFile('save.rtf', b);
  FRich.LoadFromFile(path);
  FRich.FinishLoading;
  AssertTrue('changed', FRich.Document.Execute(TTyRichInsertText.Create(0, 'New ')));
  AssertTrue('modified', FRich.Modified);
  FRich.OnSaveProgress := @SaveCancel;
  raised := False;
  try
    FRich.SaveToFile(path);
  except
    on E: ETyRichSaveCancelled do raised := True;
  end;
  AssertTrue('the save was cancelled', raised);
  AssertTrue('asked', FLoadCalls > 0);
  AssertTrue('the file is as it was', SameBytes(b, FileBytes(path)));
  AssertTrue('still modified', FRich.Modified);
  files := 0;
  if FindFirst(FTemp + '*', faAnyFile, sr) = 0 then
  try
    repeat
      if (sr.Attr and faDirectory) = 0 then Inc(files);
    until FindNext(sr) <> 0;
  finally
    FindClose(sr);
  end;
  AssertEquals('no temporary file left', 1, files);
  // a save that completes replaces it
  FRich.OnSaveProgress := nil;
  FRich.SaveToFile(path);
  AssertFalse('saved', FRich.Modified);
  AssertFalse('the new content', SameBytes(b, FileBytes(path)));
end;

{ A width change and a zoom change make every height an estimate again, lay out only the view
  again, and keep its first paragraph on screen. }
procedure TTyRichEditControlTest.TestAWidthOrZoomChangeLaysOutOnlyTheViewAgain;
var
  sl: TStringList;
  i, n, anchor: Integer;
  s: string;
begin
  sl := TStringList.Create;
  try
    s := '';
    for i := 1 to 12 do s := s + 'text' + IntToStr(i) + ' ';
    for i := 0 to 2999 do sl.Add(IntToStr(i) + ' ' + s);
    FRich.Lines := sl;
  finally
    sl.Free;
  end;
  FRich.UpdateView;
  FRich.ScrollY := FRich.Document.Text.TotalHeight div 2;
  FRich.UpdateView;
  anchor := FRich.TopParagraph;
  AssertTrue('in the middle', (anchor > 1000) and (anchor < 2000));
  n := ScreenLines;
  FRich.ResetCounts;
  FRich.Width := 300;
  FRich.UpdateView;
  AssertTrue(Format('a width change lays out %d', [FRich.LaidParas]),
    (FRich.LaidParas > 0) and (FRich.LaidParas <= 3 * n + 2));
  AssertEquals('the same first paragraph', anchor, FRich.TopParagraph);
  AssertTrue('on screen', InView(anchor));
  FRich.ResetCounts;
  FRich.Zoom := 150;
  FRich.UpdateView;
  n := ScreenLines;
  AssertTrue(Format('a zoom change lays out %d', [FRich.LaidParas]),
    (FRich.LaidParas > 0) and (FRich.LaidParas <= 3 * n + 2));
  AssertEquals('the same first paragraph again', anchor, FRich.TopParagraph);
  AssertTrue('on screen again', InView(anchor));
  AssertTrue('measured only around it', FRich.Document.Text.MeasuredParaCount <= 3 * n + 2);
end;

procedure TTyRichEditControlTest.TestARowsHeightGoesOnItsFirstParagraph;
var
  k, p, rows: Integer;
  blk: TTyRichViewBlock;
  t: TTyRichText;
begin
  FRich.LoadFromFile(FixtureDir('rtf') + 're-zh-table.rtf');
  FRich.UpdateView;
  t := FRich.Document.Text;
  rows := 0;
  for k := 0 to FRich.VisibleBlockCount - 1 do
  begin
    blk := FRich.VisibleBlocks[k];
    if not (blk.Layout is TTyRowLayout) or (blk.LastPara = blk.FirstPara) then Continue;
    Inc(rows);
    AssertTrue('the row''s first paragraph is measured', t.ParaMeasured(blk.FirstPara));
    AssertEquals('with the row''s height', Int64(blk.Height), t.ParaHeight(blk.FirstPara));
    for p := blk.FirstPara + 1 to blk.LastPara do
    begin
      AssertTrue('the others are measured', t.ParaMeasured(p));
      AssertEquals('as nothing', Int64(0), t.ParaHeight(p));
    end;
  end;
  AssertTrue('rows of several paragraphs seen', rows > 0);
end;

procedure TTyRichEditControlTest.TestNoWrapExtentGrowsWithWhatWasSeen;
var
  sl: TStringList;
  i, e1: Integer;
begin
  sl := TStringList.Create;
  try
    for i := 0 to 299 do
      if i = 150 then sl.Add(StringOfChar('x', 200)) else sl.Add('short');
    FRich.Lines := sl;
  finally
    sl.Free;
  end;
  FRich.WrapMode := rwmNone;
  FRich.UpdateView;
  e1 := FRich.HorizontalExtent;
  AssertTrue(Format('the extent is what was seen (%d)', [e1]), (e1 > 0) and (e1 < 100));
  AssertTrue('no horizontal bar', (FRich.HBar = nil) or not FRich.HBar.Visible);
  FRich.ScrollY := FRich.Document.Text.ParaTop(150);
  FRich.UpdateView;
  AssertTrue(Format('it grew with the long line (%d)', [FRich.HorizontalExtent]),
    FRich.HorizontalExtent >= 1200);
  AssertTrue('a horizontal bar', (FRich.HBar <> nil) and FRich.HBar.Visible);
  AssertEquals('its range', FRich.HorizontalExtent - (FRich.Area.Right - FRich.Area.Left),
    FRich.HBar.Max);
  FRich.ScrollToTop;
  FRich.UpdateView;
  AssertTrue('it does not shrink', FRich.HorizontalExtent >= 1200);
end;

procedure TTyRichEditControlTest.TestLinesReadTheDocumentWithoutCopyingIt;
var
  heap0, heap1: PtrUInt;
  visits: Int64;
  n: Integer;
  s, last: string;
begin
  LoadBig;
  visits := FRich.Document.Text.NodeVisits;
  heap0 := GetFPCHeapStatus.CurrHeapUsed;
  n := FRich.Lines.Count;
  s := FRich.Lines[1000000];
  last := FRich.Lines[n - 1];
  heap1 := GetFPCHeapStatus.CurrHeapUsed;
  AssertEquals('a line a paragraph', BigLines, n);
  AssertEquals('the middle line', 'Line 1000001', s);
  AssertEquals('the last line', 'Line 2000000', last);
  AssertTrue(Format('no copy of the lines (%d bytes)', [Int64(heap1) - Int64(heap0)]),
    Int64(heap1) - Int64(heap0) < 4096);
  AssertTrue(Format('a few descents (%d nodes)', [FRich.Document.Text.NodeVisits - visits]),
    FRich.Document.Text.NodeVisits - visits < 200);
end;

procedure TTyRichEditControlTest.TestAssigningLinesReplacesTheContent;
begin
  AssertEquals('an empty control has no lines', 0, FRich.Lines.Count);
  FRich.Lines.Text := 'first'#13#10'second'#13#10;
  AssertEquals('two lines', 2, FRich.Lines.Count);
  AssertEquals('two paragraphs', 2, FRich.Document.Text.ParaCount);
  AssertEquals('the second', 'second', FRich.Lines[1]);
  AssertFalse('editable by the user (Task 10a)', FRich.ReadOnly);
  FRich.Lines.Add('third');
  AssertEquals('added', 3, FRich.Lines.Count);
  AssertEquals('at the end', 'third', FRich.Lines[2]);
  AssertTrue('a command: it can be undone', FRich.Document.CanUndo);
  FRich.Lines.Insert(0, 'zero');
  AssertEquals('inserted', 'zero', FRich.Lines[0]);
  FRich.Lines[1] := 'FIRST';
  AssertEquals('replaced', 'FIRST', FRich.Lines[1]);
  FRich.Lines.Delete(3);
  AssertEquals('deleted the last', 3, FRich.Lines.Count);
  AssertEquals('the text', 'zero'#10'FIRST'#10'second', StringReplace(
    StringReplace(FRich.Document.Text.GetText(0, FRich.Document.Text.Length), #13#10, #10,
    [rfReplaceAll]), #13, #10, [rfReplaceAll]));
  FRich.Lines.Text := 'only';
  AssertEquals('assigning replaces', 1, FRich.Lines.Count);
  AssertFalse('a replacement is no undo step', FRich.Document.CanUndo);
  FRich.Lines.Clear;
  AssertEquals('cleared', 0, FRich.Lines.Count);
end;

procedure TTyRichEditControlTest.TestLinesGoIntoTheFormFileOnlyWhenSetThroughThem;
var
  a, b: TTyRichEdit;
  ms, txt: TMemoryStream;
  st: TBytesStream;
  text: string;
begin
  a := TLinesRichEdit.Create(nil);
  b := TLinesRichEdit.Create(nil);
  ms := TMemoryStream.Create;
  txt := TMemoryStream.Create;
  try
    a.Lines.Text := 'first'#13#10'second';
    ms.WriteComponent(a);
    ms.Position := 0;
    ObjectBinaryToText(ms, txt);
    SetString(text, PChar(txt.Memory), txt.Size);
    AssertTrue('the lines are in the form file', Pos('Lines.Strings', text) > 0);
    ms.Position := 0;
    ms.ReadComponent(b);
    AssertEquals('read back', 2, b.Lines.Count);
    AssertEquals('the first', 'first', b.Lines[0]);
    AssertEquals('the second', 'second', b.Lines[1]);
    AssertFalse('read as one replacement, not line by line as commands', b.Document.CanUndo);
    // a file loaded at run time is not stored
    st := TBytesStream.Create(BytesOf('loaded'#13#10'text'));
    try
      a.LoadFromStream(st);
    finally
      st.Free;
    end;
    ms.Clear;
    txt.Clear;
    ms.WriteComponent(a);
    ms.Position := 0;
    ObjectBinaryToText(ms, txt);
    SetString(text, PChar(txt.Memory), txt.Size);
    AssertFalse('a loaded file is not', Pos('Lines.Strings', text) > 0);
    // nor an empty control
    a.Lines.Clear;
    ms.Clear;
    txt.Clear;
    ms.WriteComponent(a);
    ms.Position := 0;
    ObjectBinaryToText(ms, txt);
    SetString(text, PChar(txt.Memory), txt.Size);
    // (the class's own name has the word in it: the property's, here)
    AssertFalse('nor no lines', (Pos('Lines.Strings', text) > 0) or (Pos(' Lines =', text) > 0));
  finally
    txt.Free;
    ms.Free;
    b.Free;
    a.Free;
  end;
end;

{ A document taller than the scroll bar's range is scrolled in steps of several pixels, and the
  bar's end is the last line. }
procedure TTyRichEditControlTest.TestATallDocumentScrollsToItsLastLine;
var
  sl: TStringList;
  i, last: Integer;
begin
  FRich.BarLimit := 1000;
  sl := TStringList.Create;
  try
    for i := 0 to 4999 do sl.Add('Line ' + IntToStr(i));
    FRich.Lines := sl;
  finally
    sl.Free;
  end;
  FRich.UpdateView;
  AssertTrue('within the range', (FRich.VBar.Max > 0) and (FRich.VBar.Max <= 1000));
  FRich.VBar.Position := FRich.VBar.Max div 2;
  FRich.UpdateView;
  AssertTrue(Format('the middle (%d)', [FRich.TopParagraph]),
    Abs(FRich.TopParagraph - 2500) < 50);
  FRich.VBar.Position := FRich.VBar.Max;
  FRich.UpdateView;
  AssertTrue('the last line is on screen', InView(4999));
  AssertTrue('at the bottom', FRich.ParagraphRect(4999).Bottom <= FRich.Area.Bottom);
  AssertEquals('the bar at its end', FRich.VBar.Max, FRich.VBar.Position);
  // two million lines at 500 %
  FreeAndNil(FRich);
  FRich := NewProbe;
  LoadBig;
  FRich.Zoom := 500;
  FRich.UpdateView;
  last := BigLines - 1;
  FRich.VBar.Position := FRich.VBar.Max;
  FRich.UpdateView;
  AssertTrue('the last of two million lines is on screen', InView(last));
  FRich.VBar.Position := 0;
  FRich.UpdateView;
  AssertEquals('and back to the first', 0, FRich.TopParagraph);
end;

procedure TTyRichEditControlTest.TestAPaintDrawsOnlyTheBlocksInItsClip;
var
  sl: TStringList;
  i, all: Integer;
  bmp: TBitmap;
begin
  sl := TStringList.Create;
  try
    for i := 0 to 99 do sl.Add('Line ' + IntToStr(i));
    FRich.Lines := sl;
  finally
    sl.Free;
  end;
  FRich.UpdateView;
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(400, 300);
    FRich.Device.ResetCounters;
    FRich.PaintPart(bmp.Canvas, Rect(0, 0, 400, 300), False);
    all := FRich.Device.DrawCalls;
    AssertTrue(Format('a screen of lines (%d)', [all]), all >= ScreenLines - 2);
    FRich.Device.ResetCounters;
    FRich.PaintPart(bmp.Canvas, Rect(0, 0, 400, 300), True);
    AssertEquals('nothing dirty draws nothing', 0, FRich.Device.DrawCalls);
    FRich.InvalidatePart(FRich.ParagraphRect(5));
    FRich.PaintPart(bmp.Canvas, Rect(0, 0, 400, 300), True);
    AssertEquals('one paragraph dirty draws its one line', 1, FRich.Device.DrawCalls);
  finally
    bmp.Free;
  end;
end;

{ R35: a paint while scrolling decodes no picture: it leaves an empty box and the picture to
  the background work, which makes it ready and invalidates only its box. Pictures in the
  blocks laid out ahead of the view wait there too. }
procedure TTyRichEditControlTest.TestADeferredPaintLeavesPicturesForLater;
var
  d: TTyRichDocument;
  lo: TTyRichLayouter;
  L: TTyBlockLayout;
  st: TTyRichPaintStyle;
  bmp: TBGRABitmap;
  sk: TTyRichSkippedPictures;
  pic: TTyRichPicture;
  box: TRect;
  sl: TStringList;
  i, decodes: Integer;
  canvasBmp: TBitmap;
  t: TTyRichText;
begin
  // the layouter by itself
  d := TTyRichDocument.CreateFromUtf8(BytesOf('a b'));
  lo := TTyRichLayouter.Create(TTyRichTestDevice.Create, True);
  bmp := TBGRABitmap.Create(200, 100, Sentinel);
  try
    pic := TTyRichPicture.Create(rpfPng, PngBytes(20, 10, BGRA(0, 200, 0, 255)), 600, 300);
    AssertTrue('a picture', d.Execute(TTyRichInsertObject.Create(1, pic)));
    L := lo.LayoutBlock(d, 0, 200, 96, 1);
    try
      st := TyRichDefaultPaintStyle;
      st.PlaceholderFill := BGRA(10, 20, 30, 255);
      st.DeferPictures := True;
      L.Paint(bmp, 0, 0, Rect(0, 0, 200, 100), st, 0, 0);
      AssertEquals('nothing decoded', 0, lo.PictureDecodes);
      AssertEquals('one passed over', 1, lo.SkippedPictureCount);
      sk := lo.TakeSkippedPictures;
      AssertEquals('reported', 1, Length(sk));
      box := sk[0].Box;
      AssertEquals('its box (40 x 20 at 96 PPI)', 40, box.Right - box.Left);
      AssertTrue('an empty box there', SamePx(st.PlaceholderFill,
        bmp.GetPixel(box.Left + 5, box.Top + 5)));
      AssertFalse('not ready', lo.PictureReady(sk[0].Picture, 40, 20));
      lo.PreparePicture(sk[0].Picture, 40, 20);
      AssertEquals('decoded when prepared', 1, lo.PictureDecodes);
      AssertTrue('ready', lo.PictureReady(sk[0].Picture, 40, 20));
      sk[0].Picture.Release;
      L.Paint(bmp, 0, 0, Rect(0, 0, 200, 100), st, 0, 0);
      AssertEquals('none passed over now', 0, lo.SkippedPictureCount);
      AssertEquals('no second decode', 1, lo.PictureDecodes);
      AssertTrue('the picture drawn', SamePx(BGRA(0, 200, 0, 255),
        bmp.GetPixel(box.Left + 5, box.Top + 5)));
    finally
      L.Release;
    end;
  finally
    bmp.Free;
    lo.Free;
    d.Free;
  end;
  // the control: a paint of the window leaves it to the background work
  sl := TStringList.Create;
  try
    for i := 0 to 199 do sl.Add('Line ' + IntToStr(i));
    FRich.Lines := sl;
  finally
    sl.Free;
  end;
  t := FRich.Document.Text;
  pic := TTyRichPicture.Create(rpfPng, PngBytes(20, 10, BGRA(0, 0, 200, 255)), 600, 300);
  AssertTrue('a picture on screen', FRich.Document.Execute(TTyRichInsertObject.Create(
    t.ParaStart(2), pic)));
  pic := TTyRichPicture.Create(rpfPng, PngBytes(20, 10, BGRA(200, 0, 0, 255)), 600, 300);
  AssertTrue('one a screen below', FRich.Document.Execute(TTyRichInsertObject.Create(
    t.ParaStart(ScreenLines + 10), pic)));
  FRich.UpdateView;
  AssertEquals('the one ahead waits before any paint', 1, FRich.Pending);
  canvasBmp := TBitmap.Create;
  try
    canvasBmp.PixelFormat := pf32bit;
    canvasBmp.SetSize(400, 300);
    FRich.PaintPart(canvasBmp.Canvas, Rect(0, 0, 400, 300), True);
    AssertEquals('the paint decoded nothing', 0, FRich.Layouter.PictureDecodes);
    AssertEquals('and left the one it met', 2, FRich.Pending);
    FRich.ResetCounts;
    AssertTrue('one piece of work', FRich.Step);
    AssertEquals('one decoded', 1, FRich.Layouter.PictureDecodes);
    AssertEquals('the one ahead invalidates nothing on screen', 0, Length(FRich.Invalidated));
    AssertTrue('the next', FRich.Step);
    AssertEquals('both decoded', 2, FRich.Layouter.PictureDecodes);
    AssertEquals('its box invalidated', 1, Length(FRich.Invalidated));
    AssertEquals('only its box', 20, FRich.Invalidated[0].Bottom - FRich.Invalidated[0].Top);
    AssertFalse('nothing left', FRich.Step);
    FRich.PaintPart(canvasBmp.Canvas, Rect(0, 0, 400, 300), True);
    AssertEquals('drawn now, nothing left over', 0, FRich.Pending);
    { A zoom keeps the decoded pictures (9a3, H2-M7): an enlargement is drawn from the kept
      image at once - nothing waits, nothing is decoded again. (A reduction, whose image the
      layouter let go, waits at its new size: TestAPictureComesBackAfterAZoomThereAndBack.) }
    decodes := FRich.Layouter.PictureDecodes;
    FRich.Zoom := 200;
    FRich.PaintPart(canvasBmp.Canvas, Rect(0, 0, 400, 300), True);
    AssertEquals('an enlargement: nothing waits at the new size', 0, FRich.Pending);
    AssertEquals('nothing decoded by the paint', decodes, FRich.Layouter.PictureDecodes);
  finally
    canvasBmp.Free;
  end;
end;

procedure TTyRichEditControlTest.TestKeysAndWheelScrollAndZoom;
var
  sl: TStringList;
  i, est, perNotch: Integer;
  y0: Int64;
begin
  sl := TStringList.Create;
  try
    for i := 0 to 999 do sl.Add('Line ' + IntToStr(i));
    FRich.Lines := sl;
  finally
    sl.Free;
  end;
  FRich.UpdateView;
  est := FRich.Layouter.EstimatedParaHeight(96, 1);
  FRich.Press(VK_NEXT, []);
  FRich.UpdateView;
  AssertTrue('page down', FRich.ScrollY >= FRich.Area.Bottom - FRich.Area.Top - 2 * est);
  y0 := FRich.ScrollY;
  FRich.Press(VK_PRIOR, []);
  FRich.UpdateView;
  AssertEquals('page up', Int64(0), FRich.ScrollY);
  FRich.Press(VK_END, [ssCtrl]);
  FRich.UpdateView;
  AssertTrue('Ctrl+End: the last line', InView(999));
  FRich.Press(VK_HOME, [ssCtrl]);
  FRich.UpdateView;
  AssertEquals('Ctrl+Home: the first', Int64(0), FRich.ScrollY);
  FRich.Wheel(-120, []);
  FRich.UpdateView;
  perNotch := Mouse.WheelScrollLines;
  if perNotch > 0 then
    AssertEquals('a notch down', Int64(perNotch * est), FRich.ScrollY)
  else
    AssertTrue('a notch down', FRich.ScrollY > 0);
  AssertTrue('paging moved further than a notch', y0 > 0);
  FRich.Wheel(120, [ssCtrl]);
  AssertEquals('Ctrl+wheel zooms in', 110, FRich.Zoom);
  FRich.Wheel(-240, [ssCtrl]);
  AssertEquals('and out, a notch a step', 90, FRich.Zoom);
end;

procedure TTyRichEditControlTest.TestReadOnlyStaysOnAndCodeStillChanges;
begin
  FRich.Lines.Text := 'text';
  AssertFalse('editable by default (Task 10a)', FRich.ReadOnly);
  FRich.ReadOnly := True;
  AssertTrue('read-only once set', FRich.ReadOnly);
  AssertTrue('code still changes the document',
    FRich.Document.Execute(TTyRichInsertText.Create(0, 'more ')));
  AssertEquals('changed', 'more text', FRich.Lines[0]);
end;

{ ---- Task 9a2: the review of 9a (reviewB-H1) ---- }

procedure TTyRichEditControlTest.SetLinesOf(ACount: Integer; const APrefix: string);
var
  sl: TStringList;
  i: Integer;
begin
  sl := TStringList.Create;
  try
    for i := 0 to ACount - 1 do sl.Add(APrefix + IntToStr(i));
    FRich.Lines := sl;
  finally
    sl.Free;
  end;
end;

{ Every pixel of ARect lies in one of the rectangles invalidated since the last ResetCounts. }
function TTyRichEditControlTest.Covered(const ARect: TRect): Boolean;
var
  x, y, i: Integer;
  hit: Boolean;
begin
  Result := False;
  if (ARect.Right <= ARect.Left) or (ARect.Bottom <= ARect.Top) then Exit;
  y := ARect.Top;
  while y < ARect.Bottom do
  begin
    x := ARect.Left;
    while x < ARect.Right do
    begin
      hit := False;
      for i := 0 to High(FRich.Invalidated) do
        if PtInRect(FRich.Invalidated[i], Point(x, y)) then
        begin
          hit := True;
          Break;
        end;
      if not hit then Exit;
      Inc(x, Math.Max(1, (ARect.Right - ARect.Left) div 7));
    end;
    Inc(y);
  end;
  Result := True;
end;

procedure TTyRichEditControlTest.PaintAll(ADefer: Boolean);
var
  bmp: TBitmap;
begin
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(FRich.Width * FPaintScale, FRich.Height * FPaintScale);
    FRich.PaintPart(bmp.Canvas, Rect(0, 0, FRich.Width, FRich.Height), ADefer);
  finally
    bmp.Free;
  end;
end;

procedure TTyRichEditControlTest.ReplaceInHandler(Sender: TObject; ADone, ATotal: Int64;
  var ACancel: Boolean);
begin
  Inc(FLoadCalls);
  try
    FRich.Lines.Text := 'another document';
  except
    on E: ETyRichEdit do Inc(FRefused);
  end;
  try
    FRich.LoadFromStream(FOther);
  except
    on E: ETyRichEdit do Inc(FRefused);
  end;
end;

procedure TTyRichEditControlTest.CancelInHandler(Sender: TObject; ADone, ATotal: Int64;
  var ACancel: Boolean);
begin
  Inc(FLoadCalls);
  FRich.CancelLoad;
end;

procedure TTyRichEditControlTest.NoFallback(Sender: TObject; const ABaseFont: string;
  ACode: Cardinal; var AFontName: string);
begin
end;

{ H-C1: five paragraphs of 60 words - one line each by the estimate, taller than the view
  laid out. The bar comes and stays; a second pass does nothing. A document that fits has
  none; one that fits only without the bar settles without it. }
procedure TTyRichEditControlTest.TestAShortWrappedDocumentSettlesItsScrollBar;
var
  sl: TStringList;
  s, txt: string;
  i, k, barW, wide, narrow, lineH, m: Integer;
  lo: TTyRichLayouter;
  d: TTyRichDocument;
  L1, L2: TTyBlockLayout;
  found: Boolean;
begin
  sl := TStringList.Create;
  try
    s := '';
    for i := 1 to 60 do s := s + 'word' + IntToStr(i mod 7) + ' ';
    for i := 0 to 4 do sl.Add(IntToStr(i) + ' ' + s);
    FRich.Lines := sl;
  finally
    sl.Free;
  end;
  AssertTrue('the estimate fits the view', 5 * FRich.Layouter.EstimatedParaHeight(96, 1) <
    FRich.Area.Bottom - FRich.Area.Top);
  FRich.UpdateView;
  AssertTrue('the bar is shown', (FRich.VBar <> nil) and FRich.VBar.Visible);
  AssertTrue('the text is taller than the view',
    FRich.Document.Text.TotalHeight > FRich.Area.Bottom - FRich.Area.Top);
  barW := FRich.VBar.Width;
  FRich.ResetCounts;
  FRich.UpdateView;
  AssertEquals('settled: nothing invalidated', 0, Length(FRich.Invalidated));
  AssertEquals('settled: nothing laid out', 0, FRich.LaidParas);
  AssertTrue('the bar stays', FRich.VBar.Visible);
  // a document that fits
  FRich.Lines.Text := 'one'#13#10'two';
  FRich.UpdateView;
  AssertFalse('no bar', FRich.VBar.Visible);
  FRich.ResetCounts;
  FRich.UpdateView;
  AssertEquals('nothing invalidated again', 0, Length(FRich.Invalidated));
  AssertEquals('nothing laid out again', 0, FRich.LaidParas);
  { One that fits only without the bar: paragraphs of one line at the full width that wrap
    at the width the bar leaves, as many as the view holds at one line each. }
  wide := TyRichLayoutWidth(rwmWindow, FRich.Area.Right - FRich.Area.Left, FRich.Document, 96, 1);
  narrow := TyRichLayoutWidth(rwmWindow, FRich.Area.Right - FRich.Area.Left - barW,
    FRich.Document, 96, 1);
  lo := TTyRichLayouter.Create(TTyRichTestDevice.Create, True);
  try
    txt := '';
    found := False;
    lineH := 0;
    for k := 1 to 300 do
    begin
      txt := txt + 'ab ';
      d := TTyRichDocument.CreateFromUtf8(BytesOf(txt));
      try
        L1 := lo.LayoutBlock(d, 0, wide, 96, 1);
        L2 := lo.LayoutBlock(d, 0, narrow, 96, 1);
        try
          found := (TTyParaLayout(L1).LineCount = 1) and (TTyParaLayout(L2).LineCount = 2);
          lineH := L1.Height;
        finally
          L1.Release;
          L2.Release;
        end;
      finally
        lo.Document := nil;
        d.Free;
      end;
      if found then Break;
    end;
  finally
    lo.Free;
  end;
  AssertTrue('a text that wraps only at the narrower width', found);
  m := (FRich.Area.Bottom - FRich.Area.Top) div lineH;
  sl := TStringList.Create;
  try
    for i := 1 to m do sl.Add(txt);
    FRich.Lines := sl;
  finally
    sl.Free;
  end;
  FRich.UpdateView;
  AssertFalse('it fits at the full width: it settles without the bar', FRich.VBar.Visible);
  AssertEquals('every line on screen', m - 1, FRich.VisibleBlocks[FRich.VisibleBlockCount - 1].LastPara);
  FRich.ResetCounts;
  FRich.UpdateView;
  AssertEquals('and stays so: nothing invalidated', 0, Length(FRich.Invalidated));
  AssertEquals('nothing laid out', 0, FRich.LaidParas);
end;

{ H-I1: a change made while the view waits for its next layout is painted too. }
procedure TTyRichEditControlTest.TestAChangeWhileTheViewIsInvalidIsPainted;
var
  f: TTyCharFormat;
  t: TTyRichText;
  r3, r5: TRect;
begin
  SetLinesOf(200, 'Line ');
  FRich.UpdateView;
  t := FRich.Document.Text;
  r3 := FRich.ParagraphRect(3);
  FRich.ResetCounts;
  f := TyDefaultCharFormat;
  f.SizeHalfPt := 48;
  AssertTrue('a taller paragraph 7', FRich.Document.Execute(TTyRichSetCharFormat.Create(
    TyRichRange(t.ParaStart(7), t.ParaLength(7)), [cffSize], f)));
  f.Color := clRed;
  AssertTrue('then a colour in paragraph 3', FRich.Document.Execute(TTyRichSetCharFormat.Create(
    TyRichRange(t.ParaStart(3), t.ParaLength(3)), [cffColor], f)));
  AssertTrue('paragraph 3 is painted again', Covered(r3));
  { A paragraph added above while the view still waits: the held blocks below it moved down
    (their layouts are not stale), so they are painted again too. }
  FRich.UpdateView;
  r5 := FRich.ParagraphRect(5);
  FRich.ResetCounts;
  AssertTrue('a taller paragraph 9', FRich.Document.Execute(TTyRichSetCharFormat.Create(
    TyRichRange(t.ParaStart(9), t.ParaLength(9)), [cffSize], f)));
  FRich.Lines.Insert(3, 'new');
  AssertTrue('what moved down is painted again', Covered(r5));
end;

{ H-I2: the end's pull-up moves every block: the whole text area is painted again. }
procedure TTyRichEditControlTest.TestALayoutThatMovesTheViewRepaintsIt;
var
  sl: TStringList;
  i: Integer;
  s: string;
  t: TTyRichText;
  r0: TRect;
begin
  sl := TStringList.Create;
  try
    for i := 0 to 198 do sl.Add('Line ' + IntToStr(i));
    s := '';
    for i := 1 to 60 do s := s + 'word' + IntToStr(i mod 7) + ' ';
    sl.Add(s);
    FRich.Lines := sl;
  finally
    sl.Free;
  end;
  FRich.UpdateView;
  FRich.ScrollToEnd;
  FRich.UpdateView;
  t := FRich.Document.Text;
  r0 := FRich.ParagraphRect(195);
  FRich.ResetCounts;
  AssertTrue('the last paragraph cut to a line', FRich.Document.Execute(TTyRichDelete.Create(
    t.ParaStart(199) + 5, t.ParaLength(199) - 5)));
  FRich.UpdateView;
  AssertTrue('the text moved down', FRich.ParagraphRect(195).Top > r0.Top);
  AssertTrue('the whole text area is painted again', Covered(FRich.Area));
end;

{ H-I3: one change of 20,000 paragraphs into the view, and a load step that appends many
  below a short first slice, lay out no more than the view and two screens. }
procedure TTyRichEditControlTest.TestAChangeOfManyParagraphsLaysOutOnlyTheView;
var
  s: UTF8String;
  i, n, laid, first, paras: Integer;
  t: TTyRichText;
  b: TBytes;
  st: TBytesStream;
begin
  FRich.Lines.Text := 'one'#10'two'#10'three';
  FRich.UpdateView;
  t := FRich.Document.Text;
  s := '';
  for i := 1 to 20000 do s := s + 'x'#10;
  FRich.ResetCounts;
  AssertTrue('inserted', FRich.Document.Execute(TTyRichInsertText.Create(t.ParaStart(1), s)));
  n := ScreenLines;
  laid := FRich.LaidParas;
  AssertTrue(Format('laid out inside the change: %d (a screen is %d lines)', [laid, n]),
    laid <= 3 * n + 2);
  // (the bar the change brings narrows the text: the next pass lays the view out afresh)
  FRich.ResetCounts;
  AssertTrue(Format('held: %d', [FRich.VisibleBlockCount]), FRich.VisibleBlockCount <= 3 * n + 2);
  AssertTrue(Format('and the view after: %d', [FRich.LaidParas]), FRich.LaidParas <= 3 * n + 2);
  // a lazy load: a first slice of a few paragraphs, a step of many
  FreeAndNil(FRich);
  FRich := NewProbe;
  b := GeneratedRtf(512 * 1024, paras);
  FRich.Slices(300, 128 * 1024);
  st := TBytesStream.Create(b);
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  FRich.UpdateView;
  first := FRich.Document.Text.ParaCount;
  AssertTrue(Format('a short first slice (%d)', [first]), first < 10);
  FRich.ResetCounts;
  AssertTrue('a step', FRich.Step);
  n := ScreenLines;
  AssertTrue(Format('the step brought many (%d)', [FRich.Document.Text.ParaCount]),
    FRich.Document.Text.ParaCount > first + 10 * n);
  AssertTrue(Format('laid out in the step: %d', [FRich.LaidParas]), FRich.LaidParas <= 3 * n + 2);
end;

{ H-I4: an item of a numbered list loses its number: the items after it, numbered again by the
  layouter, are laid out again and painted. }
procedure TTyRichEditControlTest.TestNumbersAfterAChangedItemAreRepainted;
var
  pf: TTyParaFormat;
  r: array[0..9] of TRect;
  i, k: Integer;
begin
  SetLinesOf(10, 'Item ');
  pf := TyDefaultParaFormat;
  pf.List.Kind := lkDecimal;
  pf.List.Level := 0;
  pf.List.StartAt := 1;
  AssertTrue('numbered', FRich.Document.Execute(TTyRichSetParaFormat.Create(0, 9, [pffList], pf)));
  FRich.UpdateView;
  for i := 0 to 9 do r[i] := FRich.ParagraphRect(i);
  FRich.ResetCounts;
  pf.List.Kind := lkNone;
  AssertTrue('item 2 unnumbered', FRich.Document.Execute(TTyRichSetParaFormat.Create(2, 2,
    [pffList], pf)));
  for i := 3 to 9 do
    AssertTrue(Format('item %d painted again', [i]), Covered(r[i]));
  for k := 0 to FRich.VisibleBlockCount - 1 do
    AssertFalse(Format('block %d is current', [k]), FRich.VisibleBlocks[k].Layout.Stale);
end;

{ H-I5: the queries lay the view out first; ScrollToEnd puts the anchor where the end is. }
procedure TTyRichEditControlTest.TestQueriesSettleTheViewFirst;
var
  a, b, c: TTyRichPos;
  y0: Int64;
  f: TTyCharFormat;
  t: TTyRichText;
  r: TRect;
  h, i: Integer;
  sl: TStringList;
  s: string;
begin
  SetLinesOf(1000, 'Line ');
  FRich.UpdateView;
  h := FRich.Area.Bottom - FRich.Area.Top;
  a := FRich.PositionAtPoint(20, 20);
  FRich.ScrollViewBy(1000);
  b := FRich.PositionAtPoint(20, 20);
  FRich.UpdateView;
  c := FRich.PositionAtPoint(20, 20);
  AssertTrue('moved', b > a);
  AssertEquals('right after the scroll as after a layout', c, b);
  FRich.ScrollToEnd;
  AssertEquals('ScrollY at the end, as the heights say', FRich.Document.Text.TotalHeight - h,
    FRich.ScrollY);
  FRich.ScrollToEnd;
  y0 := FRich.ScrollY;
  FRich.ScrollToEnd;
  FRich.ScrollViewBy(-100);
  AssertEquals('Ctrl+End then up before a paint moves', y0 - 100, FRich.ScrollY);
  // a taller paragraph above the view: hit tests and rectangles follow before any paint
  FRich.ScrollY := FRich.Document.Text.ParaTop(500);
  FRich.UpdateView;
  r := FRich.ParagraphRect(500);
  t := FRich.Document.Text;
  f := TyDefaultCharFormat;
  f.SizeHalfPt := 48;
  AssertTrue('above', FRich.Document.Execute(TTyRichSetCharFormat.Create(
    TyRichRange(t.ParaStart(495), t.ParaLength(495)), [cffSize], f)));
  AssertTrue('the first line stays where it was', EqualRect(r, FRich.ParagraphRect(500)));
  AssertEquals('and is what a point there hits', t.ParaStart(500),
    FRich.PositionAtPoint(FRich.Area.Left, r.Top + 1));
  { ScrollY after a jump into paragraphs taller than their estimates: what the laid out view
    says at once, not the estimates' sum. }
  sl := TStringList.Create;
  try
    s := '';
    for i := 1 to 50 do s := s + 'word' + IntToStr(i mod 7) + ' ';
    for i := 0 to 399 do sl.Add(IntToStr(i) + ' ' + s);
    FRich.Lines := sl;
  finally
    sl.Free;
  end;
  FRich.ScrollY := Int64(200) * FRich.Layouter.EstimatedParaHeight(96, 1);
  y0 := FRich.ScrollY;
  FRich.UpdateView;
  AssertEquals('ScrollY is the laid out view''s', FRich.ScrollY, y0);
end;

{ H-I6: a progress handler that replaces the content is refused; one that cancels stops the
  load cleanly; a save's handler cannot replace the content either. }
procedure TTyRichEditControlTest.TestProgressHandlersCannotReplaceTheContent;
var
  b: TBytes;
  paras: Integer;
  st: TBytesStream;
  ms: TMemoryStream;
begin
  b := GeneratedRtf(2 * 1024 * 1024, paras);
  FOther := TBytesStream.Create(BytesOf('other'));
  try
    FRich.Slices(64 * 1024, 64 * 1024);
    FRich.OnLoadProgress := @ReplaceInHandler;
    st := TBytesStream.Create(b);
    try
      FRich.LoadFromStream(st);
    finally
      st.Free;
    end;
    AssertTrue('a step', FRich.Step);
    FRich.FinishLoading;
    AssertTrue('the handler ran', FLoadCalls > 0);
    AssertEquals('every replacement refused', 2 * FLoadCalls, FRefused);
    AssertFalse('the load completed', FRich.Loading);
    AssertFalse('complete', FRich.Incomplete);
    AssertEquals('every paragraph of it', paras, FRich.Document.Text.ParaCount);
    // a handler that cancels
    FreeAndNil(FRich);
    FRich := NewProbe;
    FLoadCalls := 0;
    FRich.Slices(64 * 1024, 64 * 1024);
    FRich.OnLoadProgress := @CancelInHandler;
    st := TBytesStream.Create(b);
    try
      FRich.LoadFromStream(st);
    finally
      st.Free;
    end;
    AssertTrue('a step', FRich.Step);
    AssertEquals('asked once', 1, FLoadCalls);
    AssertFalse('stopped', FRich.Loading);
    AssertTrue('incomplete', FRich.Incomplete);
    FRich.UpdateView;
    AssertTrue('still shown', FRich.VisibleBlockCount > 0);
    // a save's handler
    FreeAndNil(FRich);
    FRich := NewProbe;
    FRefused := 0;
    FLoadCalls := 0;
    // the writer asks every 256 KB
    SetLinesOf(30000, 'kept ');
    FRich.OnSaveProgress := @SaveReplace;
    ms := TMemoryStream.Create;
    try
      FRich.SaveToStream(ms, rfRtf);
      AssertTrue('saved', ms.Size > 0);
    finally
      ms.Free;
    end;
    AssertTrue('the handler ran', FLoadCalls > 0);
    AssertEquals('refused', FLoadCalls, FRefused);
    AssertEquals('the content stays', 'kept 0', FRich.Lines[0]);
  finally
    FreeAndNil(FOther);
  end;
end;

procedure TTyRichEditControlTest.SaveReplace(Sender: TObject; ADone, ATotal: Int64;
  var ACancel: Boolean);
begin
  Inc(FLoadCalls);
  try
    FRich.Lines.Text := 'replaced';
  except
    on E: ETyRichEdit do Inc(FRefused);
  end;
end;

{ One picture in the view of 'a b': painted (deferred), made ready, painted again. }
procedure TTyRichEditControlTest.PictureCase(const AWhat: string; APngW, APngH: Integer;
  AFail: Boolean; AZoomAfter: Integer);
var
  pic: TTyRichPicture;
  steps: Integer;
begin
  FreeAndNil(FRich);
  FRich := NewProbe;
  FRich.Lay.FailScale := AFail;
  FRich.Lines.Text := 'a b';
  pic := TTyRichPicture.Create(rpfPng, PngBytes(APngW, APngH, BGRA(0, 0, 200, 255)), 600, 300);
  AssertTrue(AWhat + ': a picture', FRich.Document.Execute(TTyRichInsertObject.Create(1, pic)));
  PaintAll(True);
  AssertEquals(AWhat + ': left for later', 1, FRich.Pending);
  steps := 0;
  while FRich.Step and (steps < 10) do Inc(steps);
  AssertEquals(AWhat + ': made ready once', 1, steps);
  PaintAll(True);
  AssertEquals(AWhat + ': nothing waits after the paint', 0, FRich.Pending);
  if AZoomAfter > 0 then
  begin
    FRich.Zoom := AZoomAfter;
    PaintAll(True);
    AssertTrue(AWhat + ': at the new size at most once', FRich.Pending <= 1);
    steps := 0;
    while FRich.Step and (steps < 10) do Inc(steps);
    AssertTrue(AWhat + ': made ready once more at most', steps <= 1);
    PaintAll(True);
    AssertEquals(AWhat + ': nothing waits at the new size', 0, FRich.Pending);
  end;
end;

{ H-I7 / H-M10: a picture that cannot be reduced, an enlargement, one reduced and then zoomed:
  each queued at most once a size, and nothing waits afterwards. One picture in two places
  has both its boxes painted when it is ready. }
procedure TTyRichEditControlTest.TestAPictureIsQueuedOnceAndEveryBoxRepainted;
var
  pic: TTyRichPicture;
begin
  PictureCase('a failing reduction', 200, 100, True, 0);
  PictureCase('an enlargement', 20, 10, False, 0);
  PictureCase('reduced then zoomed', 200, 100, False, 500);
  FreeAndNil(FRich);
  FRich := NewProbe;
  SetLinesOf(20, 'Line ');
  pic := TTyRichPicture.Create(rpfPng, PngBytes(20, 10, BGRA(0, 0, 200, 255)), 600, 300);
  pic.AddRef;
  AssertTrue('once', FRich.Document.Execute(TTyRichInsertObject.Create(
    FRich.Document.Text.ParaStart(2), pic)));
  AssertTrue('twice', FRich.Document.Execute(TTyRichInsertObject.Create(
    FRich.Document.Text.ParaStart(5), pic)));
  PaintAll(True);
  AssertEquals('one picture, one size: queued once', 1, FRich.Pending);
  FRich.ResetCounts;
  AssertTrue('made ready', FRich.Step);
  AssertEquals('both its boxes', 2, Length(FRich.Invalidated));
  AssertEquals('a box each', 20, FRich.Invalidated[1].Bottom - FRich.Invalidated[1].Top);
  AssertTrue('in two places', FRich.Invalidated[0].Top <> FRich.Invalidated[1].Top);
end;

{$IFDEF MSWINDOWS}
function ReadStream(const APath: string): string;
var
  f: TFileStream;
begin
  Result := '';
  f := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, f.Size);
    if f.Size > 0 then f.ReadBuffer(Result[1], f.Size);
  finally
    f.Free;
  end;
end;
{$ENDIF}

function TTyRichEditControlTest.FileCount: Integer;
var
  sr: TSearchRec;
begin
  Result := 0;
  if FindFirst(FTemp + '*', faAnyFile, sr) = 0 then
  try
    repeat
      if (sr.Attr and faDirectory) = 0 then Inc(Result);
    until FindNext(sr) <> 0;
  finally
    FindClose(sr);
  end;
end;

{ H-I8: a write-protected target is refused before anything is written; a save keeps the
  target's attributes and alternate streams (Windows: ReplaceFileW). The Unix path (mode,
  owner, rename) is compile-checked only. }
procedure TTyRichEditControlTest.TestASaveKeepsWhatTheTargetWas;
{$IFDEF MSWINDOWS}
var
  path: string;
  orig: TBytes;
  raised: Boolean;
  f: TFileStream;
  s: string;
begin
  orig := BytesOf('{\rtf1\ansi\deff0{\fonttbl{\f0 Arial;}}\pard\f0 Saved text.\par}');
  path := TempFile('keep.rtf', orig);
  FRich.LoadFromFile(path);
  AssertTrue('changed', FRich.Document.Execute(TTyRichInsertText.Create(0, 'New ')));
  FileSetAttr(path, faReadOnly);
  try
    raised := False;
    try
      FRich.SaveToFile(path);
    except
      // the control's own refusal, before anything is written - not ReplaceFileW's
      on E: ETyRichEdit do raised := E.Message = Format(rsRichEditCannotWrite, [path]);
    end;
  finally
    FileSetAttr(path, 0);
  end;
  AssertTrue('a write-protected file is refused by the control, by its name', raised);
  AssertTrue('and is as it was', SameBytes(orig, FileBytes(path)));
  AssertEquals('no temporary file left', 1, FileCount);
  AssertTrue('still modified', FRich.Modified);
  // hidden, with a stream of its own
  f := TFileStream.Create(path + ':note', fmCreate);
  try
    s := 'kept';
    f.WriteBuffer(s[1], Length(s));
  finally
    f.Free;
  end;
  FileSetAttr(path, faHidden);
  try
    FRich.SaveToFile(path);
    AssertFalse('saved', FRich.Modified);
    AssertFalse('the new content', SameBytes(orig, FileBytes(path)));
    AssertTrue('still hidden', (FileGetAttr(path) and faHidden) <> 0);
    AssertEquals('its stream kept', 'kept', ReadStream(path + ':note'));
    AssertEquals('no temporary file left', 1, FileCount);
  finally
    FileSetAttr(path, 0);
  end;
end;
{$ELSE}
begin
  Ignore('Windows only (ReplaceFileW); the Unix path is compile-checked');
end;
{$ENDIF}

{ H-I9: a file another handle holds open for writing (a log being written) loads. }
procedure TTyRichEditControlTest.TestAFileOpenForWritingLoads;
var
  path: string;
  w: TFileStream;
begin
  path := TempFile('busy.txt', BytesOf('busy text'));
  w := TFileStream.Create(path, fmOpenReadWrite or fmShareDenyNone);
  try
    FRich.LoadFromFile(path);
    AssertEquals('loaded', 'busy text', FRich.Lines[0]);
  finally
    w.Free;
  end;
end;

function FormText(AComp: TComponent): string;
var
  ms, txt: TMemoryStream;
begin
  ms := TMemoryStream.Create;
  txt := TMemoryStream.Create;
  try
    ms.WriteComponent(AComp);
    ms.Position := 0;
    ObjectBinaryToText(ms, txt);
    SetString(Result, PChar(txt.Memory), txt.Size);
  finally
    txt.Free;
    ms.Free;
  end;
end;

{ H-I10: TabStop and Cursor have the constructor's values as defaults. }
procedure TTyRichEditControlTest.TestPublishedDefaultsAreTheConstructedValues;
var
  a, b: TTyRichEdit;
  ms: TMemoryStream;
begin
  a := TTyRichEdit.Create(nil);
  b := TTyRichEdit.Create(nil);
  ms := TMemoryStream.Create;
  try
    AssertFalse('a fresh control stores no TabStop', Pos('TabStop', FormText(a)) > 0);
    AssertFalse('nor a Cursor', Pos('Cursor', FormText(a)) > 0);
    a.Cursor := crDefault;
    AssertTrue('crDefault is stored', Pos('Cursor', FormText(a)) > 0);
    ms.WriteComponent(a);
    ms.Position := 0;
    ms.ReadComponent(b);
    AssertEquals('and read back', Ord(crDefault), Ord(b.Cursor));
  finally
    ms.Free;
    b.Free;
    a.Free;
  end;
end;

procedure TTyRichEditControlTest.CheckClearAdd(const AList: array of string);
var
  i: Integer;
begin
  FRich.Lines.Clear;
  for i := 0 to High(AList) do FRich.Lines.Add(AList[i]);
  AssertEquals(Format('%d lines', [Length(AList)]), Length(AList), FRich.Lines.Count);
  for i := 0 to High(AList) do AssertEquals(Format('line %d', [i]), AList[i], FRich.Lines[i]);
end;

{ H-I11: no lines and one empty line are told apart. }
procedure TTyRichEditControlTest.TestLinesTellNoLinesFromOneEmptyLine;
var
  a, b: TTyRichEdit;
  ms: TMemoryStream;
begin
  FRich.Lines.Add('');
  AssertEquals('one empty line', 1, FRich.Lines.Count);
  AssertEquals('one paragraph', 1, FRich.Document.Text.ParaCount);
  FRich.Lines.Add('x');
  AssertEquals('two lines', 2, FRich.Lines.Count);
  AssertEquals('the first empty', '', FRich.Lines[0]);
  AssertEquals('the second', 'x', FRich.Lines[1]);
  FRich.Lines.Clear;
  AssertEquals('none', 0, FRich.Lines.Count);
  FRich.Lines.Add('a');
  FRich.Lines.Add('');
  AssertEquals('[a, '''']', 2, FRich.Lines.Count);
  FRich.Lines.Delete(0);
  AssertEquals('the empty line is left', 1, FRich.Lines.Count);
  FRich.Lines.Delete(0);
  AssertEquals('and goes', 0, FRich.Lines.Count);
  CheckClearAdd(['', 'b']);
  CheckClearAdd(['a', '']);
  CheckClearAdd(['']);
  CheckClearAdd(['', '', 'c', '']);
  a := TLinesRichEdit.Create(nil);
  b := TLinesRichEdit.Create(nil);
  ms := TMemoryStream.Create;
  try
    a.Lines.Add('');
    AssertTrue('[''''] is stored', Pos('Lines.Strings', FormText(a)) > 0);
    ms.WriteComponent(a);
    ms.Position := 0;
    ms.ReadComponent(b);
    AssertEquals('and read back as one empty line', 1, b.Lines.Count);
    AssertEquals('empty', '', b.Lines[0]);
  finally
    ms.Free;
    b.Free;
    a.Free;
  end;
end;

{ H-M1: FinishLoading reports its progress in slices, and a cancel there acts. }
procedure TTyRichEditControlTest.TestFinishLoadingGoesInSlices;
var
  b: TBytes;
  paras: Integer;
  st: TBytesStream;
begin
  b := GeneratedRtf(10 * 1024 * 1024, paras);
  FRich.Slices(64 * 1024, 64 * 1024);
  FRich.OnLoadProgress := @LoadCalled;
  st := TBytesStream.Create(b);
  try
    FRich.LoadFromStream(st);
    FLoadCalls := 0;
    FRich.FinishLoading;
    AssertTrue(Format('progress during it (%d)', [FLoadCalls]), FLoadCalls >= 2);
    AssertFalse('loaded', FRich.Loading);
    AssertEquals('all', paras, FRich.Document.Text.ParaCount);
    FreeAndNil(FRich);
    FRich := NewProbe;
    FRich.Slices(64 * 1024, 64 * 1024);
    FRich.OnLoadProgress := @LoadCalled;
    st.Position := 0;
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  FLoadCalls := 0;
  FCancelAt := 1;
  FRich.FinishLoading;
  AssertEquals('cancelled at the first report', 1, FLoadCalls);
  AssertFalse('stopped', FRich.Loading);
  AssertTrue('incomplete', FRich.Incomplete);
end;

{ H-M2: a wheel notch on a document that fits, a scroll up at the top: nothing happens. }
procedure TTyRichEditControlTest.TestScrollingAgainstAnEndDoesNothing;
begin
  FRich.Lines.Text := 'one'#10'two'#10'three';
  FRich.UpdateView;
  FRich.ResetCounts;
  FRich.Wheel(-120, []);
  FRich.ScrollViewBy(-50);
  FRich.ScrollToTop;
  AssertEquals('nothing invalidated', 0, Length(FRich.Invalidated));
  FRich.UpdateView;
  AssertEquals('nothing laid out', 0, FRich.LaidParas);
  AssertEquals('nor invalidated after', 0, Length(FRich.Invalidated));
  AssertTrue('no bar', (FRich.VBar = nil) or not FRich.VBar.Visible);
  AssertEquals('at the top', Int64(0), FRich.ScrollY);
end;

{ H-M3: a zoom keeps the same share of the top block above the view. }
procedure TTyRichEditControlTest.TestAZoomKeepsThePartOfTheBlockAtTheTop;
var
  sl: TStringList;
  s: string;
  i, h, h2: Integer;
  off: Int64;
begin
  sl := TStringList.Create;
  try
    s := '';
    for i := 1 to 2000 do s := s + 'word' + IntToStr(i mod 7) + ' ';
    sl.Add(s);
    for i := 1 to 20 do sl.Add('Line ' + IntToStr(i));
    FRich.Lines := sl;
  finally
    sl.Free;
  end;
  FRich.UpdateView;
  h := FRich.VisibleBlocks[0].Height;
  AssertTrue('a block taller than the view', h > 3 * (FRich.Area.Bottom - FRich.Area.Top));
  FRich.ScrollViewBy(h div 2);
  FRich.UpdateView;
  AssertEquals('half of it above', 0, FRich.TopParagraph);
  off := FRich.TopOffset;
  FRich.Zoom := 200;
  FRich.UpdateView;
  AssertEquals('the same block on top', 0, FRich.TopParagraph);
  h2 := FRich.VisibleBlocks[0].Height;
  AssertTrue(Format('the same share (%d of %d, was %d of %d)', [FRich.TopOffset, h2, off, h]),
    Abs(FRich.TopOffset - off * h2 div h) <= 1);
end;

{ H-M4: a scroll of a hundred screens is a jump: only around its target is laid out. }
procedure TTyRichEditControlTest.TestAFarScrollIsAJump;
var
  n: Integer;
begin
  LoadBig;
  FRich.UpdateView;
  FRich.ResetCounts;
  FRich.ScrollViewBy(100 * (FRich.Area.Bottom - FRich.Area.Top));
  FRich.UpdateView;
  n := ScreenLines;
  AssertTrue(Format('laid out %d', [FRich.LaidParas]), FRich.LaidParas <= 3 * n + 2);
  AssertTrue(Format('about a hundred screens down (%d)', [FRich.TopParagraph]),
    FRich.TopParagraph > 90 * n);
end;

{ H-M6: saving to a stream changes nothing; saving an RTF document as text is an export. }
procedure TTyRichEditControlTest.TestSavingAsTextIsAnExport;
var
  path: string;
  ms: TMemoryStream;
begin
  path := TempFile('doc.rtf', BytesOf('{\rtf1\ansi\deff0{\fonttbl{\f0 Arial;}}\pard\f0 Text.\par}'));
  FRich.LoadFromFile(path);
  AssertTrue('changed', FRich.Document.Execute(TTyRichInsertText.Create(0, 'New ')));
  ms := TMemoryStream.Create;
  try
    FRich.SaveToStream(ms);
    AssertTrue('written', ms.Size > 0);
  finally
    ms.Free;
  end;
  AssertTrue('a stream changes nothing', FRich.Modified);
  FRich.SaveToFile(FTemp + 'out.txt');
  AssertTrue('as text: still modified', FRich.Modified);
  AssertTrue('still an RTF document', FRich.SourceFormat = rfRtf);
  AssertEquals('from its file', ExpandFileName(path), FRich.SourceFile);
  FRich.SaveToFile(path);
  AssertFalse('as RTF: saved', FRich.Modified);
end;

{ H-M7: a save that cannot create its file says which file it was to write. }
procedure TTyRichEditControlTest.TestASaveThatCannotWriteNamesTheTarget;
var
  msg: string;
begin
  TempFile('x', nil);
  FRich.Lines.Text := 'text';
  msg := '';
  try
    FRich.SaveToFile(FTemp + 'missing' + PathDelim + 'target.rtf');
  except
    on E: ETyRichEdit do msg := E.Message;
  end;
  AssertTrue('refused, by the target''s name: ' + msg, Pos('target.rtf', msg) > 0);
  AssertFalse('no temporary name in it', Pos('.tmp', msg) > 0);
end;

{ H-M9: a layout that raises in the middle of a pass leaves no reference behind. }
procedure TTyRichEditControlTest.TestALayoutThatRaisesKeepsNoReference;
var
  raised: Boolean;
  base, i: Integer;
  L: TTyBlockLayout;
begin
  SetLinesOf(400, 'Line ');
  FRich.UpdateView;
  L := FRich.Layouter.LayoutBlock(FRich.Document, 399, FRich.VisibleBlocks[0].Layout.LayoutWidth,
    96, 1);
  // what a layout the view does not hold has: the cache's own (read before letting ours go)
  base := L.RefCount - 1;
  L.Release;
  FRich.ScrollY := FRich.Document.Text.ParaTop(200);
  FRich.ResetCounts;
  FRich.RaiseAfter := 30;
  raised := False;
  try
    FRich.UpdateView;
  except
    on E: EInvalidOperation do raised := True;
  end;
  FRich.RaiseAfter := 0;
  AssertTrue('the layout raised', raised);
  AssertTrue('some were given', Length(FRich.Given) > 10);
  for i := 0 to High(FRich.Given) do
    AssertEquals(Format('layout %d is the cache''s only', [i]), base, FRich.Given[i].RefCount);
  FRich.UpdateView;
  AssertTrue('the view comes back', FRich.VisibleBlockCount > 0);
end;

{ H-M11: no OnChange while a form file is read; AddStrings is one undo step. }
procedure TTyRichEditControlTest.TestStreamingRaisesNoChangeAndABatchIsOneStep;
var
  a, b: TTyRichEdit;
  ms: TMemoryStream;
  sl: TStringList;
begin
  a := TLinesRichEdit.Create(nil);
  b := TLinesRichEdit.Create(nil);
  ms := TMemoryStream.Create;
  try
    a.Lines.Text := 'first'#13#10'second';
    ms.WriteComponent(a);
    ms.Position := 0;
    b.OnChange := @Changed;
    ms.ReadComponent(b);
    AssertEquals('read', 2, b.Lines.Count);
    AssertEquals('no change reported while streaming', 0, FChanges);
  finally
    ms.Free;
    b.Free;
    a.Free;
  end;
  FRich.Lines.Text := 'a';
  sl := TStringList.Create;
  try
    sl.Add('b');
    sl.Add('c');
    sl.Add('d');
    FRich.Lines.AddStrings(sl);
  finally
    sl.Free;
  end;
  AssertEquals('added', 4, FRich.Lines.Count);
  FRich.Document.Undo;
  AssertEquals('one undo takes them all back', 1, FRich.Lines.Count);
  AssertFalse('nothing more to undo', FRich.Document.CanUndo);
end;

{ H-M12: the control's own StyleOverride tokens reach the selection, object and placeholder. }
procedure TTyRichEditControlTest.TestStyleOverrideTokensReachTheParts;
var
  st: TTyRichPaintStyle;
begin
  FRich.StyleOverride := '--selection: #FF0000; --accent: #00FF00; --surface-sunk: #0000FF; ' +
    '--border: #FFFF00;';
  st := FRich.Style;
  AssertTrue('selection', SamePx(BGRA(255, 0, 0, 255), st.SelectionBack));
  AssertTrue('object frame', SamePx(BGRA(0, 255, 0, 255), st.ObjectFrame));
  AssertTrue('placeholder fill', SamePx(BGRA(0, 0, 255, 255), st.PlaceholderFill));
  AssertTrue('placeholder frame', SamePx(BGRA(255, 255, 0, 255), st.PlaceholderFrame));
end;

function HexOf(const ABytes: TBytes): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(ABytes) do Result := Result + LowerCase(IntToHex(ABytes[i], 2));
end;

{ H-M13: a change in a row's later paragraph drops the row's waiting picture. }
procedure TTyRichEditControlTest.TestAChangeInARowDropsItsPendingPicture;
var
  rtf: string;
  st: TBytesStream;
  f: TTyCharFormat;
  t: TTyRichText;
  p: Integer;
begin
  rtf := '{\rtf1\ansi\deff0{\fonttbl{\f0 Arial;}}' +
    '\trowd\cellx3000\cellx6000\pard\intbl a\cell\pard\intbl b {\pict\pngblip\picw200\pich100' +
    '\picwgoal600\pichgoal300 ' + HexOf(PngBytes(200, 100, BGRA(0, 0, 200, 255))) +
    '}\cell\row\pard after\par}';
  st := TBytesStream.Create(BytesOf(rtf));
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  FRich.FinishLoading;
  FRich.UpdateView;
  AssertTrue('a row first', FRich.VisibleBlocks[0].Layout is TTyRowLayout);
  AssertTrue('of two paragraphs', FRich.VisibleBlocks[0].LastPara > FRich.VisibleBlocks[0].FirstPara);
  PaintAll(True);
  AssertEquals('its picture waits', 1, FRich.Pending);
  t := FRich.Document.Text;
  p := FRich.VisibleBlocks[0].LastPara;
  f := TyDefaultCharFormat;
  f.Color := clRed;
  AssertTrue('the second cell''s text changed', FRich.Document.Execute(TTyRichSetCharFormat.Create(
    TyRichRange(t.ParaStart(p), 1), [cffColor], f)));
  AssertEquals('the row''s picture no longer waits', 0, FRich.Pending);
end;

{ W1r-O1: another fallback font: the view is laid out again like after a font change. }
procedure TTyRichEditControlTest.TestAFallbackFontChangeLaysTheViewOutAgain;
begin
  SetLinesOf(200, 'Line ');
  FRich.UpdateView;
  AssertTrue('measured', FRich.Document.Text.MeasuredParaCount > 0);
  FRich.ResetCounts;
  FRich.OnFallbackFont := @NoFallback;
  AssertEquals('every height an estimate again', 0, FRich.Document.Text.MeasuredParaCount);
  AssertTrue('the text painted again', Covered(FRich.Area));
  FRich.UpdateView;
  AssertTrue('laid out again', FRich.LaidParas > 0);
  FRich.ResetCounts;
  FRich.FallbackFonts.Add('Arial');
  AssertEquals('the list too', 0, FRich.Document.Text.MeasuredParaCount);
  AssertTrue('painted again', Covered(FRich.Area));
  FRich.UpdateView;
  AssertTrue('laid out again', FRich.LaidParas > 0);
end;

{ W1r-O2: blocks of CRichMaxBlockPx: tops and positions past an Integer's range. }
procedure TTyRichEditControlTest.TestHugeBlocksKeepTheArithmeticInRange;
var
  sl: TStringList;
  big: string;
  i, k, h: Integer;
  pf: TTyParaFormat;
  r: TRect;
  pos: TTyRichPos;
  t: TTyRichText;
begin
  big := '';
  for i := 1 to 16500 do big := big + 'x'#11;
  sl := TStringList.Create;
  try
    sl.Add('first');
    for i := 1 to 5 do sl.Add(big);
    sl.Add('last');
    FRich.Lines := sl;
  finally
    sl.Free;
  end;
  pf := TyDefaultParaFormat;
  pf.LineSpacing := lsExact;
  pf.LineSpacingValue := 2000000000;
  AssertTrue('exact lines', FRich.Document.Execute(TTyRichSetParaFormat.Create(1, 5,
    [pffLineSpacing], pf)));
  t := FRich.Document.Text;
  h := FRich.Area.Bottom - FRich.Area.Top;
  // each huge paragraph laid out once: their heights are measured
  for k := 1 to 5 do
  begin
    FRich.ScrollY := t.ParaTop(k);
    FRich.UpdateView;
  end;
  AssertEquals('measured', Int64(CRichMaxBlockPx), t.ParaHeight(3));
  FRich.ScrollToEnd;
  AssertEquals('ScrollY past an Integer', t.TotalHeight - h, FRich.ScrollY);
  AssertTrue(Format('it is (%d; paragraph 1 is %d high, %d paragraphs)', [FRich.ScrollY,
    t.ParaHeight(1), t.ParaCount]), FRich.ScrollY > MaxInt);
  AssertTrue('the last line on screen', InView(6));
  FRich.ScrollY := t.ParaTop(2) + 1000;
  for k := 1 to FRich.VisibleBlockCount - 1 do
    AssertEquals(Format('block %d follows the one before', [k]),
      FRich.VisibleBlocks[k - 1].Top + FRich.VisibleBlocks[k - 1].Height, FRich.VisibleBlocks[k].Top);
  AssertEquals('a huge block on top', CRichMaxBlockPx, FRich.VisibleBlocks[1].Height);
  r := FRich.ParagraphRect(2);
  AssertTrue('its rectangle in range', (r.Top < FRich.Area.Top) and (r.Bottom > FRich.Area.Bottom)
    and (r.Top > -MaxInt) and (r.Bottom < MaxInt));
  pos := FRich.PositionAtPoint(FRich.Area.Left + 2, FRich.Area.Top + 2);
  AssertTrue(Format('a point in it is in it (%d)', [pos]), (pos >= t.ParaStart(2)) and
    (pos <= t.ParaStart(2) + t.ParaLength(2)));
end;

{ R40: the bytes before the RTF signature (a UTF-8 BOM, blank lines, spaces) are the file's:
  saved back as they were, to a stream and over the file, after an edit too; rfRtf takes such a
  file as rfAuto does; a text file's BOM is the text reader's and is written once. }
procedure TTyRichEditControlTest.TestTheBytesBeforeTheRtfAreKept;
const
  Body = '{\rtf1\ansi\deff0{\fonttbl{\f0 Arial;}}\pard\f0 Some text.\par}';
var
  prefixes: array[0..2] of RawByteString;
  i: Integer;
  orig, saved: TBytes;
  path: string;
  ms: TMemoryStream;
  st: TBytesStream;
  s: RawByteString;
begin
  prefixes[0] := #$EF#$BB#$BF;
  prefixes[1] := #13#10'   ';
  prefixes[2] := #$EF#$BB#$BF#13#10#9' '#10;
  for i := 0 to 2 do
  begin
    orig := BytesOf(prefixes[i] + Body);
    path := TempFile(Format('prefix%d.rtf', [i]), orig);
    FreeAndNil(FRich);
    FRich := NewProbe;
    FRich.LoadFromFile(path);
    AssertTrue(Format('%d: read as RTF', [i]), FRich.SourceFormat = rfRtf);
    ms := TMemoryStream.Create;
    try
      FRich.SaveToStream(ms);
      AssertTrue(Format('%d: to a stream as it came', [i]), SameBytes(orig, StreamBytes(ms)));
    finally
      ms.Free;
    end;
    FRich.SaveToFile(path);
    AssertTrue(Format('%d: over its file', [i]), SameBytes(orig, FileBytes(path)));
    // after an edit the prefix still comes first
    AssertTrue('changed', FRich.Document.Execute(TTyRichInsertText.Create(0, 'New ')));
    FRich.SaveToFile(path);
    saved := FileBytes(path);
    AssertTrue(Format('%d: an edited save starts with it', [i]),
      (Length(saved) > Length(prefixes[i]) + 5) and
      CompareMem(@saved[0], @prefixes[i][1], Length(prefixes[i])) and
      (saved[Length(prefixes[i])] = Ord('{')));
    // the explicit format reads the same bytes the same way
    FreeAndNil(FRich);
    FRich := NewProbe;
    st := TBytesStream.Create(orig);
    try
      FRich.LoadFromStream(st, rfRtf);
    finally
      st.Free;
    end;
    AssertEquals(Format('%d: rfRtf reads it', [i]), 'Some text.', FRich.Lines[0]);
    ms := TMemoryStream.Create;
    try
      FRich.SaveToStream(ms);
      AssertTrue(Format('%d: and keeps it', [i]), SameBytes(orig, StreamBytes(ms)));
      // saved as text: no prefix
      ms.Clear;
      FRich.SaveToStream(ms, rfText);
      SetString(s, PChar(ms.Memory), ms.Size);
      AssertEquals(Format('%d: as text, the text first', [i]), 1, Pos('Some text.', s));
    finally
      ms.Free;
    end;
    // a replacement forgets it
    FRich.Lines.Text := 'plain';
    ms := TMemoryStream.Create;
    try
      FRich.SaveToStream(ms, rfRtf);
      AssertEquals(Format('%d: a new content has none', [i]), Ord('{'), PByte(ms.Memory)^);
    finally
      ms.Free;
    end;
  end;
  // a text file that starts with a BOM: written once
  orig := BytesOf(#$EF#$BB#$BF'just text'#13#10'two');
  path := TempFile('bom.txt', orig);
  FreeAndNil(FRich);
  FRich := NewProbe;
  FRich.LoadFromFile(FTemp + 'prefix0.rtf');
  FRich.LoadFromFile(path);
  AssertTrue('read as text', FRich.SourceFormat = rfText);
  ms := TMemoryStream.Create;
  try
    FRich.SaveToStream(ms);
    AssertTrue('its BOM written once', SameBytes(orig, StreamBytes(ms)));
    ms.Clear;
    FRich.SaveToStream(ms, rfRtf);
    AssertEquals('the RTF before it is forgotten', Ord('{'), PByte(ms.Memory)^);
  finally
    ms.Free;
  end;
end;

{ ---- R39: the kept surface ---- }

{ The surface as it is, drawn again from nothing at the same position: the same pixels. }
procedure TTyRichEditControlTest.CheckSurface(const AWhat: string);
var
  kept: TBGRABitmap;
  x, y, diff, dx0, dy0, dx1, dy1: Integer;
  a, b: PBGRAPixel;
begin
  PaintAll(True);
  AssertTrue(AWhat + ': a surface', FRich.Surf <> nil);
  kept := FRich.Surf.Duplicate as TBGRABitmap;
  try
    FRich.RedrawAll;
    PaintAll(True);
    diff := 0;
    dx0 := 0; dy0 := 0; dx1 := 0; dy1 := 0;
    for y := 0 to FRich.Height * FRich.Scale - 1 do
    begin
      a := kept.ScanLine[y];
      b := FRich.Surf.ScanLine[y];
      for x := 0 to FRich.Width * FRich.Scale - 1 do
      begin
        if (a^.red <> b^.red) or (a^.green <> b^.green) or (a^.blue <> b^.blue) or
          (a^.alpha <> b^.alpha) then
        begin
          if diff = 0 then
          begin
            dx0 := x; dy0 := y; dx1 := x; dy1 := y;
          end;
          Inc(diff);
          dx0 := Math.Min(dx0, x); dx1 := Math.Max(dx1, x);
          dy0 := Math.Min(dy0, y); dy1 := Math.Max(dy1, y);
        end;
        Inc(a);
        Inc(b);
      end;
    end;
    AssertEquals(Format('%s: pixels that differ from a full redraw (in %d,%d..%d,%d; area %d,%d,%d,%d)',
      [AWhat + Format(' kept %x new %x / kept %x new %x', [PCardinal(kept.ScanLine[dy0] + dx0)^,
      PCardinal(FRich.Surf.ScanLine[dy0] + dx0)^, PCardinal(kept.ScanLine[dy1] + dx1)^,
      PCardinal(FRich.Surf.ScanLine[dy1] + dx1)^]), dx0, dy0, dx1, dy1, FRich.Area.Left, FRich.Area.Top, FRich.Area.Right,
      FRich.Area.Bottom]), 0, diff);
  finally
    kept.Free;
  end;
end;

{ A document of lines, wrapped paragraphs, one paragraph taller than the view, a table row and
  a picture, as RTF. }
function MixedRtf: string;
var
  i, k: Integer;
  s: string;
begin
  Result := '{\rtf1\ansi\deff0{\fonttbl{\f0 Arial;}}';
  for i := 0 to 59 do
  begin
    s := 'Line ' + IntToStr(i);
    if i mod 7 = 3 then
      for k := 1 to 40 do s := s + ' word' + IntToStr(k mod 5);
    if i = 20 then
      for k := 1 to 1500 do s := s + ' tall' + IntToStr(k mod 9);
    Result := Result + '\pard ' + s + '\par' + #13#10;
    if i = 12 then
      Result := Result + '\trowd\cellx2500\cellx5000\pard\intbl cell one\cell\pard\intbl cell two' +
        ' with more words in it\cell\row' + #13#10;
    if i = 30 then
      Result := Result + '\pard {\pict\pngblip\picw40\pich20\picwgoal900\pichgoal450 ' +
        HexOf(PngBytes(40, 20, BGRA(30, 160, 60, 255))) + '}\par' + #13#10;
  end;
  Result := Result + '\pard The last line.\par}';
end;

{ After scrolls by a line, a part of a line, a page, to the end and back, a horizontal scroll,
  invalidations and changes of the document, the kept surface is what a full redraw at the
  same position draws, pixel for pixel. }
procedure TTyRichEditControlTest.TestTheSurfaceEqualsAFullRedraw;
begin
  SurfaceSequence(1);
end;

{ The sequence, at device scale AScale (forced for the canvas and restored by TearDown): every
  move of rows, dirty band and exposed strip is in raster pixels there. Besides the 9a2 steps:
  a picture made ready, a part invalidated and a scroll in one paint, the end's pull-up after
  a deletion, a resize, a zoom there and back, right to left (H2-I5, H2-M11). }
procedure TTyRichEditControlTest.SurfaceSequence(AScale: Integer);
var
  st: TBytesStream;
  est, i, steps: Integer;
  f: TTyCharFormat;
  t: TTyRichText;
begin
  if AScale > 1 then
  begin
    FPaintScale := AScale;
    TyForceDeviceScaleForTest(AScale, True, False);
  end;
  st := TBytesStream.Create(BytesOf(MixedRtf));
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  FRich.FinishLoading;
  CheckSurface('first');
  AssertEquals('at the scale asked for', AScale, FRich.Scale);
  // client pixels: what ScrollViewBy takes
  est := FRich.Layouter.EstimatedParaHeight(96, 1);
  FRich.ScrollViewBy(est);
  CheckSurface('a line down');
  FRich.ScrollViewBy(-est);
  CheckSurface('a line up');
  FRich.ScrollViewBy(est div 2 + 1);
  CheckSurface('part of a line');
  for i := 1 to 12 do
  begin
    FRich.ScrollViewBy(est * 3);
    CheckSurface(Format('a notch %d (rows, a picture, the tall paragraph)', [i]));
  end;
  FRich.ScrollViewBy(FRich.Area.Bottom - FRich.Area.Top - est);
  CheckSurface('a page');
  FRich.ScrollViewBy(-7);
  CheckSurface('seven pixels up inside the tall paragraph');
  FRich.ScrollToEnd;
  CheckSurface('the end');
  FRich.ScrollViewBy(-est);
  CheckSurface('a line above the end');
  FRich.ScrollViewBy(est * 5);
  CheckSurface('against the end');
  FRich.ScrollToTop;
  CheckSurface('the top');
  FRich.ScrollViewBy(est * 2);
  FRich.ScrollViewBy(est);
  CheckSurface('two scrolls before a paint');
  // a part invalidated, nothing changed
  FRich.InvalidatePart(Rect(10, 20, 200, 41));
  CheckSurface('an invalidated part');
  // the document changes: a colour, a height, a paragraph added on screen
  t := FRich.Document.Text;
  f := TyDefaultCharFormat;
  f.Color := clRed;
  AssertTrue('a colour', FRich.Document.Execute(TTyRichSetCharFormat.Create(
    TyRichRange(t.ParaStart(FRich.TopParagraph + 2), 4), [cffColor], f)));
  CheckSurface('a colour');
  f.SizeHalfPt := 40;
  AssertTrue('a size', FRich.Document.Execute(TTyRichSetCharFormat.Create(
    TyRichRange(t.ParaStart(FRich.TopParagraph + 3), 4), [cffSize], f)));
  FRich.ScrollViewBy(est);
  CheckSurface('a size and a scroll');
  AssertTrue('a paragraph', FRich.Document.Execute(TTyRichInsertText.Create(
    t.ParaStart(FRich.TopParagraph + 1), 'new line'#10)));
  CheckSurface('a paragraph');
  // a part invalidated and a scroll in one paint
  FRich.InvalidatePart(Rect(10, 60, 250, 90));
  FRich.ScrollViewBy(est);
  CheckSurface('a part invalidated, then a scroll');
  // the picture's paragraph on screen, the picture made ready between two paints
  FRich.ScrollY := t.ParaTop(31) div FRich.Scale;
  PaintAll(True);
  AssertTrue('the picture waits', FRich.Pending > 0);
  steps := 0;
  while FRich.Step and (steps < 20) do Inc(steps);
  AssertTrue('made ready', steps > 0);
  CheckSurface('a picture made ready');
  // the end's pull-up after a deletion at the end
  FRich.ScrollToEnd;
  CheckSurface('the end again');
  AssertTrue('the last paragraphs deleted', FRich.Document.Execute(TTyRichDelete.Create(
    t.ParaStart(t.ParaCount - 4) - 1, t.Length - t.ParaStart(t.ParaCount - 4) + 1)));
  CheckSurface('pulled up after a deletion at the end');
  // a resize, within a surface block and across blocks
  FRich.SetBounds(0, 0, 410, 296);
  CheckSurface('a resize within a block');
  FRich.SetBounds(0, 0, 330, 250);
  CheckSurface('a resize across blocks');
  FRich.SetBounds(0, 0, 400, 300);
  FRich.ScrollViewBy(-3 * est);
  CheckSurface('the size back and a scroll');
  // a zoom there and back
  FRich.Zoom := 125;
  CheckSurface('zoomed');
  FRich.ScrollViewBy(est);
  CheckSurface('zoomed, a scroll');
  FRich.Zoom := 100;
  CheckSurface('the zoom back');
  // no wrap: a horizontal scroll moves columns
  FRich.WrapMode := rwmNone;
  CheckSurface('no wrap');
  FRich.WheelH(120);
  CheckSurface('a horizontal notch');
  FRich.WheelH(-120);
  CheckSurface('and back');
  // right to left: the bar on the left, the text clip from its edge
  FRich.WrapMode := rwmWindow;
  FRich.BiDiMode := bdRightToLeft;
  CheckSurface('right to left');
  FRich.ScrollViewBy(est);
  CheckSurface('right to left, a line down');
  FRich.ScrollViewBy(-2 * est);
  CheckSurface('right to left, two lines up');
end;

{ A scroll by a line paints only the blocks the exposed band meets, and lays out nothing that
  was held; a paint with nothing dirty paints no block and no frame; a hover (a state that
  changes the frame) paints the frame and lays out nothing. }
procedure TTyRichEditControlTest.TestAScrollPaintsOnlyWhatItExposes;
var
  est: Integer;
begin
  SetLinesOf(1000, 'Line ');
  FCtl.LoadThemeCss('TyRichEdit:hover { border-color: #FF0000; }');
  PaintAll(True);
  est := FRich.Layouter.EstimatedParaHeight(96, 1);
  FRich.ResetCounts;
  FRich.ScrollViewBy(est);
  PaintAll(True);
  AssertTrue(Format('blocks painted for a line: %d', [FRich.BlockPaints]),
    (FRich.BlockPaints >= 1) and (FRich.BlockPaints <= 4));
  AssertEquals('no frame', 0, FRich.FramePaints);
  AssertTrue(Format('laid out: %d', [FRich.LaidParas]), FRich.LaidParas <= 1);
  FRich.ScrollViewBy(5 * est);
  PaintAll(True);
  FRich.ResetCounts;
  FRich.ScrollViewBy(-3 * est);
  PaintAll(True);
  AssertTrue(Format('blocks painted for three lines up: %d', [FRich.BlockPaints]),
    (FRich.BlockPaints >= 3) and (FRich.BlockPaints <= 6));
  AssertEquals('nothing laid out going back', 0, FRich.LaidParas);
  FRich.ResetCounts;
  PaintAll(True);
  AssertEquals('nothing dirty: no block', 0, FRich.BlockPaints);
  AssertEquals('nothing dirty: no frame', 0, FRich.FramePaints);
  FRich.Hover(True);
  PaintAll(True);
  AssertEquals('a hover: the frame', 1, FRich.FramePaints);
  AssertEquals('a hover lays out nothing', 0, FRich.LaidParas);
  // one paragraph changed: its block only
  FRich.ResetCounts;
  FRich.InvalidatePart(FRich.ParagraphRect(FRich.TopParagraph + 5));
  PaintAll(True);
  // its block, and its neighbours for their ink that may reach into it (clipped)
  AssertTrue(Format('one paragraph: %d blocks', [FRich.BlockPaints]),
    (FRich.BlockPaints >= 1) and (FRich.BlockPaints <= 3));
  AssertEquals('one paragraph: one line drawn', 1, FRich.Device.DrawCalls);
end;

{ The surface follows the client: in blocks, never more than a block past it, made again
  when the size changes by more. }
procedure TTyRichEditControlTest.TestTheSurfaceIsTheClientsSize;
begin
  SetLinesOf(50, 'Line ');
  PaintAll(True);
  AssertEquals('wide', 448, FRich.Surf.Width);
  AssertEquals('high', 320, FRich.Surf.Height);
  // the frame is on it all round: its left border as its top one (the text never covers it)
  AssertTrue('a left border', SamePx(FRich.Surf.GetPixel(0, 150), FRich.Surf.GetPixel(200, 0)));
  AssertFalse('not the ground', SamePx(FRich.Surf.GetPixel(0, 150), FRich.Surf.GetPixel(200, 150)));
  FRich.SetBounds(0, 0, 200, 100);
  PaintAll(True);
  AssertEquals('narrower', 256, FRich.Surf.Width);
  AssertEquals('lower', 128, FRich.Surf.Height);
end;

{ At device scale 2 the surface is twice the client, the text is laid out at twice the PPI,
  and what is public stays in client pixels; the picture averaged down is the scale 1 one. }
procedure TTyRichEditControlTest.TestDeviceScaleTwo;
var
  one: TRichProbe;
  bmp1, bmp2: TBitmap;
  b1, b2, half: TBGRABitmap;
  p1, p2: TTyRichPos;
  h1, h2, mismatch: Integer;
  y1, y2: Int64;
begin
  one := NewProbe;
  bmp1 := TBitmap.Create;
  bmp2 := TBitmap.Create;
  try
    SetLinesOf(300, 'Line of text ');
    one.Lines := FRich.Lines;
    bmp1.PixelFormat := pf32bit;
    bmp1.SetSize(400, 300);
    one.PaintPart(bmp1.Canvas, Rect(0, 0, 400, 300), True);
    h1 := one.VisibleBlocks[0].Layout.Height;
    TyForceDeviceScaleForTest(2, True, False);
    try
      bmp2.PixelFormat := pf32bit;
      bmp2.SetSize(800, 600);
      FRich.PaintPart(bmp2.Canvas, Rect(0, 0, 400, 300), True);
      AssertEquals('laid out at scale 2', 2, FRich.Scale);
      AssertTrue('the surface twice the client', (FRich.Surf.Width >= 800) and
        (FRich.Surf.Height >= 600) and (FRich.Surf.Width < 800 + 64) and
        (FRich.Surf.Height < 600 + 64));
      h2 := FRich.VisibleBlocks[0].Layout.Height;
      AssertEquals('a line laid out twice as tall', 2 * h1, h2);
      AssertEquals('in client pixels the same', one.VisibleBlocks[0].Height,
        FRich.VisibleBlocks[0].Height);
      p1 := one.PositionAtPoint(60, 50);
      p2 := FRich.PositionAtPoint(60, 50);
      AssertEquals('a client point hits the same position', p1, p2);
      one.ScrollY := one.Document.Text.ParaTop(100);
      FRich.ScrollY := one.ScrollY;
      AssertEquals('the same paragraph on top', one.TopParagraph, FRich.TopParagraph);
      y1 := one.ScrollY;
      y2 := FRich.ScrollY;
      AssertTrue(Format('ScrollY in client pixels (%d, %d)', [y1, y2]), Abs(y1 - y2) <= 1);
      AssertTrue('the paragraph''s rectangle', EqualRect(one.ParagraphRect(101),
        FRich.ParagraphRect(101)));
      FRich.PaintPart(bmp2.Canvas, Rect(0, 0, 400, 300), True);
    finally
      TyForceDeviceScaleForTest(0, False);
    end;
    one.PaintPart(bmp1.Canvas, Rect(0, 0, 400, 300), True);
    b1 := TBGRABitmap.Create(bmp1);
    b2 := TBGRABitmap.Create(bmp2);
    half := TyHalve(b2);
    try
      mismatch := TyInkMismatch(half, b1);
      AssertTrue(Format('averaged down, it is the scale 1 picture (%d)', [mismatch]),
        mismatch <= CMaxMismatch);
    finally
      half.Free;
      b2.Free;
      b1.Free;
    end;
  finally
    bmp2.Free;
    bmp1.Free;
    one.Free;
  end;
end;

{ ---- fix wave W3 ---- }

function ReadFixtureFile(const AName: string): TBytes;
var
  f: TFileStream;
begin
  Result := nil;
  f := TFileStream.Create(FixtureDir('rtf') + AName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, f.Size);
    if f.Size > 0 then f.ReadBuffer(Result[0], f.Size);
  finally
    f.Free;
  end;
end;

{ The byte after the ACount-th \par of an RTF file (not \pard): a first slice that ends there
  holds the header and ACount paragraphs (a load begun with less reads on to two paragraphs in
  chunks of a megabyte - all of a small file). }
function AfterPars(const B: TBytes; ACount: Integer): Int64;
var
  i: Integer;
begin
  for i := 0 to High(B) - 4 do
    if (B[i] = Ord('\')) and (B[i + 1] = Ord('p')) and (B[i + 2] = Ord('a')) and
      (B[i + 3] = Ord('r')) and not (Chr(B[i + 4]) in ['a'..'z']) then
    begin
      Dec(ACount);
      if ACount = 0 then Exit(i + 5);
    end;
  Result := Length(B);
end;

{ W2r-I1: the list Word saved (word-list.rtf), loaded in small slices (a first slice of two
  paragraphs, steps of 256 bytes): the slices the load appends are no edits, so every
  numbered item shows the number Word showed (word-list.markers.txt) in every slice - not
  the walk's count, which restarts after each body paragraph. }
procedure TTyRichEditControlTest.TestASlicedLoadShowsTheFilesNumbers;
var
  b: TBytes;
  st: TBytesStream;
  marks: array of string;
  i, n, start, steps: Integer;

  procedure Check(const AWhen: string; AUpTo: Integer);
  var
    k: Integer;
    L: TTyBlockLayout;
  begin
    for k := 0 to AUpTo do
      if (marks[k] <> '') and (marks[k][1] in ['0'..'9']) then
      begin
        L := FRich.Layouter.LayoutBlock(FRich.Document, k, 1000, 96, 1);
        try
          AssertEquals(Format('%s: paragraph %d', [AWhen, k]), marks[k],
            string(TTyParaLayout(L).Marker.Text));
        finally
          L.Release;
        end;
      end;
  end;

begin
  b := ReadFixtureFile('word-list.markers.txt');
  marks := nil;
  n := 0;
  start := 0;
  for i := 0 to High(b) do
    if b[i] = 10 then
    begin
      SetLength(marks, n + 1);
      SetLength(marks[n], i - start);
      if i > start then Move(b[start], marks[n][1], i - start);
      Inc(n);
      start := i + 1;
    end;
  AssertEquals('eleven paragraphs', 11, n);
  st := TBytesStream.Create(ReadFixtureFile('word-list.rtf'));
  try
    FRich.Slices(AfterPars(st.Bytes, 2), 256);
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  AssertTrue('loading', FRich.Loading);
  steps := 0;
  while FRich.Loading do
  begin
    // the paragraphs indexed whole so far (the last may still grow)
    Check(Format('slice %d', [steps]), FRich.Document.Text.ParaCount - 2);
    AssertTrue('a step', FRich.Step);
    Inc(steps);
    AssertTrue('runaway', steps < 10000);
  end;
  AssertTrue(Format('in slices (%d)', [steps]), steps >= 5);
  AssertEquals('all of it', 11, FRich.Document.Text.ParaCount);
  Check('loaded', 10);
end;

{ ---- 9a3: the second review of the viewer ---- }

{ H2-I1: Lines.LoadFromStream, Lines.LoadFromFile and a Text inside BeginUpdate .. EndUpdate
  replace the content once, at EndUpdate (the document refuses a replacement inside its own
  update); a batch of Adds is still one undo step (H-M11). }
procedure TTyRichEditControlTest.TestLinesLoadAndATextInsideAnUpdate;
var
  st: TStringStream;
  path: string;
begin
  st := TStringStream.Create('one'#13#10'two'#13#10'three');
  try
    FRich.Lines.LoadFromStream(st);
  finally
    st.Free;
  end;
  AssertEquals('three lines from a stream', 3, FRich.Lines.Count);
  AssertEquals('the second', 'two', FRich.Lines[1]);
  path := TempFile('lines.txt', BytesOf('alpha'#10'beta'));
  FRich.Lines.LoadFromFile(path);
  AssertEquals('two lines from a file', 2, FRich.Lines.Count);
  AssertEquals('its second', 'beta', FRich.Lines[1]);
  FRich.Lines.BeginUpdate;
  try
    FRich.Lines.Text := 'x'#13#10'y'#13#10'z';
    AssertEquals('read back inside the update', 'y', FRich.Lines[1]);
  finally
    FRich.Lines.EndUpdate;
  end;
  AssertEquals('the text inside an update', 3, FRich.Lines.Count);
  AssertEquals('three paragraphs', 3, FRich.Document.Text.ParaCount);
  AssertEquals('the last', 'z', FRich.Lines[2]);
  FRich.Lines.BeginUpdate;
  try
    FRich.Lines.Add('p');
    FRich.Lines.Add('q');
  finally
    FRich.Lines.EndUpdate;
  end;
  AssertEquals('added', 5, FRich.Lines.Count);
  FRich.Document.Undo;
  AssertEquals('a batch of Adds is one undo step', 3, FRich.Lines.Count);
end;

{ A document of 'a b' with ACount pictures of 200 x 100 shown at 40 x 20 (a reduction: the
  layouter keeps only the reduced copy), each its own picture and colour (0, 0, 200 - k).
  Returns the box's pixels. }
function TTyRichEditControlTest.PictureDoc(ACount: Integer): Integer;
var
  k: Integer;
  pic: TTyRichPicture;
begin
  FRich.Lines.Text := 'a b';
  for k := 0 to ACount - 1 do
  begin
    pic := TTyRichPicture.Create(rpfPng, PngBytes(200, 100, BGRA(0, 0, 200 - k, 255)), 600, 300);
    AssertTrue('a picture', FRich.Document.Execute(TTyRichInsertObject.Create(1, pic)));
  end;
  Result := 40 * 20;
end;

{ Pixels of AColor on the surface's client part. }
function TTyRichEditControlTest.SurfaceCount(const AColor: TBGRAPixel): Integer;
var
  x, y: Integer;
  p: PBGRAPixel;
begin
  Result := 0;
  for y := 0 to FRich.Height * FRich.Scale - 1 do
  begin
    p := FRich.Surf.ScanLine[y];
    for x := 0 to FRich.Width * FRich.Scale - 1 do
    begin
      if SamePx(p^, AColor) then Inc(Result);
      Inc(p);
    end;
  end;
end;

{ H-I7 / H2-I2 / H2-M7: a reduced picture after a zoom in and back, and after a PPI there and
  back, is queued again at the old size and shown (the layouter let that size go); a zoom
  keeps the decoded pictures and drops what waited at the old size. }
procedure TTyRichEditControlTest.TestAPictureComesBackAfterAZoomThereAndBack;
var
  box, b0, steps: Integer;
  blue: TBGRAPixel;

  function Settle: Integer;
  begin
    PaintAll(True);
    Result := 0;
    while FRich.Step and (Result < 10) do Inc(Result);
    PaintAll(True);
  end;

begin
  box := PictureDoc(1);
  blue := BGRA(0, 0, 200, 255);
  AssertEquals('made ready once at 100 %', 1, Settle);
  b0 := SurfaceCount(blue);
  AssertEquals('its pixels', box, b0);
  FRich.Zoom := 110;
  AssertEquals('made ready once at 110 %', 1, Settle);
  AssertTrue('larger', SurfaceCount(blue) > b0);
  FRich.Zoom := 100;
  PaintAll(True);
  AssertEquals('100 % again: its size waits again', 1, FRich.Pending);
  steps := 0;
  while FRich.Step and (steps < 10) do Inc(steps);
  AssertEquals('made ready', 1, steps);
  PaintAll(True);
  AssertEquals('its pixels are back', b0, SurfaceCount(blue));
  // a PPI there and back (a window moved to another screen and back)
  FRich.Font.PixelsPerInch := 120;
  AssertEquals('made ready once at 120 dpi', 1, Settle);
  FRich.Font.PixelsPerInch := 96;
  PaintAll(True);
  AssertEquals('96 dpi again: it waits again', 1, FRich.Pending);
  AssertEquals('made ready once more', 1, Settle);
  AssertEquals('and shown', b0, SurfaceCount(blue));
  // a zoom while it waits: the old size no longer waits, the decoded picture stays
  FRich.Zoom := 120;
  PaintAll(True);
  AssertEquals('waits at 120 %', 1, FRich.Pending);
  FRich.Zoom := 130;
  PaintAll(True);
  AssertEquals('only the new size waits', 1, FRich.Pending);
  AssertEquals('the zoom kept the decoded picture', 1, FRich.Layouter.PictureCacheCount);
end;

{ H2-M4: a PreparePicture that raises a fatal error (the layouter lets it through) is tried
  once, not once a paint; a layout parameter change tries it again. }
procedure TTyRichEditControlTest.TestAPreparationThatRaisesIsTriedOnce;
var
  raised: Boolean;
  i: Integer;
begin
  PictureDoc(1);
  FRich.Lay.FailDecode := True;
  PaintAll(True);
  AssertEquals('it waits', 1, FRich.Pending);
  raised := False;
  try
    FRich.Step;
  except
    on E: EAccessViolation do raised := True;
  end;
  AssertTrue('the step raised', raised);
  AssertEquals('decoded once', 1, FRich.Lay.FailedDecodes);
  for i := 1 to 3 do
  begin
    // its box drawn again each time (the deferred paint passes over it, not ready)
    FRich.RedrawAll;
    PaintAll(True);
    AssertEquals(Format('paint %d: not queued again', [i]), 0, FRich.Pending);
  end;
  AssertFalse('nothing to do', FRich.Step);
  AssertEquals('still tried once', 1, FRich.Lay.FailedDecodes);
  // a zoom there and back (the layout parameters changed): the same size is tried again
  FRich.Lay.FailDecode := False;
  FRich.Zoom := 200;
  PaintAll(True);
  FRich.Zoom := 100;
  PaintAll(True);
  AssertEquals('queued again at its size', 1, FRich.Pending);
  AssertTrue('made ready', FRich.Step);
  AssertEquals('nothing waits', 0, FRich.Pending);
end;

{ H2-I3: an empty document's surface is the frame the painter draws with no text clip, pixel
  for pixel: the text clip never covers what the frame inks - a focus ring (wider than the
  border + 1 at 120 dpi), one with an offset, a corner radius larger than the padding. }
procedure TTyRichEditControlTest.TestTheTextNeverCoversTheFrame;
const
  Css: array[0..3] of string = ('outline: 2px #FF0000;', 'outline: 3px #FF0000;',
    'outline: 2px #FF0000; outline-offset: 2px;', 'border-radius: 12px;');
var
  c, ppi, x, y, diff, fx, fy: Integer;
  exp: TBGRABitmap;
begin
  for c := 0 to High(Css) do
    for ppi := 0 to 1 do
    begin
      FreeAndNil(FRich);
      FRich := NewProbe;
      if ppi = 1 then FRich.Font.PixelsPerInch := 120;
      FRich.StyleOverride := Css[c];
      PaintAll(True);
      exp := TBGRABitmap.Create(FRich.Surf.Width, FRich.Surf.Height);
      try
        FRich.FullFrame(exp, FRich.Font.PixelsPerInch);
        diff := 0;
        fx := -1;
        fy := -1;
        for y := 0 to FRich.Height - 1 do
          for x := 0 to FRich.Width - 1 do
            if not SamePx(exp.GetPixel(x, y), FRich.Surf.GetPixel(x, y)) then
            begin
              if diff = 0 then
              begin
                fx := x;
                fy := y;
              end;
              Inc(diff);
            end;
        AssertEquals(Format('%s at %d dpi: pixels of the frame lost (first at %d,%d)',
          [Css[c], FRich.Font.PixelsPerInch, fx, fy]), 0, diff);
      finally
        exp.Free;
      end;
    end;
end;

{ H2-I4 / H2-M5: InvalidateContent is clipped to the text: a block cut by the view's top edge,
  the caret rectangle of its line and that of a line held above the view draw no frame and
  only what is on screen of them; a far rectangle at scale 4 does nothing. }
procedure TTyRichEditControlTest.TestContentIsClippedToTheText;
var
  est: Integer;
  r: TRect;
  t: TTyRichText;
begin
  SetLinesOf(1000, 'Line ');
  PaintAll(True);
  est := FRich.Layouter.EstimatedParaHeight(96, 1);
  FRich.ScrollViewBy(10 * est + est div 2);
  PaintAll(True);
  t := FRich.Document.Text;
  r := FRich.ParagraphRect(FRich.TopParagraph);
  AssertTrue('the top block is cut by the view''s edge', r.Top < FRich.Area.Top);
  FRich.ResetCounts;
  FRich.InvalidatePart(r);
  PaintAll(True);
  AssertEquals('its rectangle: no frame', 0, FRich.FramePaints);
  AssertTrue(Format('its rectangle: %d blocks', [FRich.BlockPaints]), FRich.BlockPaints <= 3);
  r := FRich.PositionRect(t.ParaStart(FRich.TopParagraph));
  AssertTrue('the caret of the cut line is cut too', r.Top < FRich.Area.Top);
  FRich.ResetCounts;
  FRich.InvalidatePart(r);
  PaintAll(True);
  AssertEquals('the caret: no frame', 0, FRich.FramePaints);
  AssertTrue(Format('the caret: %d blocks', [FRich.BlockPaints]), FRich.BlockPaints <= 3);
  r := FRich.PositionRect(t.ParaStart(FRich.TopParagraph - 3));
  AssertTrue('a caret held above the view', (r.Bottom > r.Top) and (r.Bottom <= FRich.Area.Top));
  FRich.ResetCounts;
  FRich.InvalidatePart(r);
  AssertEquals('above the view: nothing invalidated', 0, Length(FRich.Invalidated));
  PaintAll(True);
  AssertEquals('above the view: no frame', 0, FRich.FramePaints);
  AssertEquals('above the view: no block', 0, FRich.BlockPaints);
  // scale 4: a rectangle clamped far above the view (ClientOf's half range) does nothing
  FPaintScale := 4;
  TyForceDeviceScaleForTest(4, True, False);
  PaintAll(True);
  AssertEquals('at scale 4', 4, FRich.Scale);
  FRich.ResetCounts;
  FRich.InvalidatePart(Rect(10, -(MaxInt div 2), 100, -(MaxInt div 2) + 10));
  AssertEquals('far away: nothing invalidated', 0, Length(FRich.Invalidated));
  PaintAll(True);
  AssertEquals('far away: no frame', 0, FRich.FramePaints);
  AssertEquals('far away: no block', 0, FRich.BlockPaints);
end;

{ H2-I5: the pixel sequence at device scale 2. }
procedure TTyRichEditControlTest.TestTheSurfaceEqualsAFullRedrawAtScaleTwo;
begin
  SurfaceSequence(2);
end;

{ H2-M1: a wider ring, a ring's offset, a larger radius: the frame is drawn again. }
procedure TTyRichEditControlTest.TestTheFrameSignatureHoldsWhatTheFrameIsDrawnFrom;
begin
  SetLinesOf(50, 'Line ');
  FRich.StyleOverride := 'outline: 1px #FF0000;';
  PaintAll(True);
  FRich.ResetCounts;
  FRich.StyleOverride := 'outline: 3px #FF0000;';
  PaintAll(True);
  AssertEquals('a wider ring: the frame', 1, FRich.FramePaints);
  AssertTrue('three columns of it', SamePx(BGRA(255, 0, 0, 255), FRich.Surf.GetPixel(2, 150)));
  FRich.ResetCounts;
  FRich.StyleOverride := 'outline: 3px #FF0000; outline-offset: 1px;';
  PaintAll(True);
  AssertEquals('an offset: the frame', 1, FRich.FramePaints);
  FRich.ResetCounts;
  PaintAll(True);
  AssertEquals('nothing changed: no frame', 0, FRich.FramePaints);
end;

{ H2-M2: a press and a release on a theme whose pressed look is the normal one paint nothing;
  a hover that changes the border paints the frame. }
procedure TTyRichEditControlTest.TestAPressThatLooksTheSameDrawsNothing;
begin
  SetLinesOf(1000, 'Line ');
  PaintAll(True);
  FRich.ResetCounts;
  FRich.Down;
  PaintAll(True);
  AssertEquals('a press: no frame', 0, FRich.FramePaints);
  AssertEquals('a press: no block', 0, FRich.BlockPaints);
  FRich.Up;
  PaintAll(True);
  AssertEquals('a release: no frame', 0, FRich.FramePaints);
  AssertEquals('a release: no block', 0, FRich.BlockPaints);
  FCtl.LoadThemeCss('TyRichEdit:hover { border-color: #FF0000; }');
  PaintAll(True);
  FRich.ResetCounts;
  FRich.Hover(True);
  PaintAll(True);
  AssertEquals('a hover that changes the border: the frame', 1, FRich.FramePaints);
end;

{ H2-M3: a block that raises while the surface is drawn leaves it to be drawn whole by the
  next paint, never stale. }
procedure TTyRichEditControlTest.TestADrawingThatRaisesLeavesNothingStale;
var
  est: Integer;
  raised: Boolean;
begin
  SetLinesOf(300, 'Line ');
  PaintAll(True);
  est := FRich.Layouter.EstimatedParaHeight(96, 1);
  FRich.ScrollViewBy(4 * est);
  FRich.RaiseOnBlock := 2;
  raised := False;
  try
    PaintAll(True);
  except
    on E: EInvalidOperation do raised := True;
  end;
  FRich.RaiseOnBlock := 0;
  AssertTrue('the paint raised', raised);
  CheckSurface('after a paint that raised');
end;

{ H2-M6: the paint that lays out a scroll invalidates nothing (it blits the text itself); a
  paint of part of the window still asks for the rest. }
procedure TTyRichEditControlTest.TestAPaintThatLaysOutAScrollInvalidatesNothing;
var
  est: Integer;
  bmp: TBitmap;
begin
  SetLinesOf(1000, 'Line ');
  PaintAll(True);
  est := FRich.Layouter.EstimatedParaHeight(96, 1);
  FRich.ScrollViewBy(est);
  FRich.ResetCounts;
  PaintAll(True);
  AssertEquals('a whole paint: no window invalidation', 0, Length(FRich.Invalidated));
  FRich.ScrollViewBy(est);
  FRich.ResetCounts;
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(FRich.Width, FRich.Height);
    FRich.PaintPart(bmp.Canvas, Rect(0, 0, FRich.Width, 40), True);
  finally
    bmp.Free;
  end;
  AssertTrue('a part: the rest is asked for', Length(FRich.Invalidated) > 0);
end;

{ H2-M8: a zoom then a scroll before the paint keeps H-M3's share as a zoom, a paint and the
  scroll do; a horizontal position keeps its fraction of the extent through a zoom. }
procedure TTyRichEditControlTest.TestAZoomThenAScrollKeepsTheShareAndTheColumn;
var
  sl: TStringList;
  s: string;
  i, h: Integer;
  other: TRichProbe;
  x0, e0, x1, e1: Integer;
begin
  sl := TStringList.Create;
  try
    s := '';
    for i := 1 to 2000 do s := s + 'word' + IntToStr(i mod 7) + ' ';
    sl.Add(s);
    for i := 1 to 20 do sl.Add('Line ' + IntToStr(i));
    FRich.Lines := sl;
  finally
    sl.Free;
  end;
  other := NewProbe;
  try
    other.Lines := FRich.Lines;
    FRich.UpdateView;
    other.UpdateView;
    h := FRich.VisibleBlocks[0].Height;
    FRich.ScrollViewBy(h div 2);
    other.ScrollViewBy(h div 2);
    FRich.UpdateView;
    other.UpdateView;
    FRich.Zoom := 200;
    FRich.UpdateView;
    FRich.ScrollViewBy(40);
    FRich.UpdateView;
    other.Zoom := 200;
    other.ScrollViewBy(40);
    other.UpdateView;
    AssertEquals('the same block on top', FRich.TopParagraph, other.TopParagraph);
    AssertTrue(Format('the same part of it above (%d, %d)', [FRich.TopOffset, other.TopOffset]),
      Abs(FRich.TopOffset - other.TopOffset) <= 1);
  finally
    other.Free;
  end;
  // the column: no wrap, long lines, three notches right
  sl := TStringList.Create;
  try
    s := '';
    for i := 1 to 300 do s := s + 'word' + IntToStr(i mod 7) + ' ';
    for i := 1 to 30 do sl.Add(s);
    FRich.Lines := sl;
  finally
    sl.Free;
  end;
  FRich.Zoom := 100;
  FRich.WrapMode := rwmNone;
  FRich.UpdateView;
  for i := 1 to 3 do FRich.WheelH(120);
  FRich.UpdateView;
  x0 := FRich.ScrollX;
  e0 := FRich.HorizontalExtent;
  AssertTrue('scrolled right', x0 > 0);
  FRich.Zoom := 200;
  FRich.UpdateView;
  x1 := FRich.ScrollX;
  e1 := FRich.HorizontalExtent;
  // within 5 % of the fraction it was
  AssertTrue(Format('the same fraction of the extent (%d of %d, was %d of %d)', [x1, e1, x0, e0]),
    (e1 > 0) and (Abs(Int64(x1) * e0 - Int64(x0) * e1) <= Int64(x0) * e1 div 20));
end;

var
  GWidgetSetReady: Boolean = False;

{ The widgetset a handle needs, once (as test.base does it). }
procedure NeedWidgetSet;
begin
  if GWidgetSetReady then Exit;
  Forms.Application.Initialize;
  GWidgetSetReady := True;
end;

{ H2-M11: a real handle, on a form that is never shown (made as test.base makes one): a turn of
  the background work is queued only with it, InvalidateContent reaches the window's
  invalidation, the handle's destruction releases the surface and takes the turn off the
  queue, and the next paint draws the surface again in full. }
procedure TTyRichEditControlTest.TestAHandleOnAFormNeverShown;
var
  F: TForm;
begin
  PictureDoc(1);
  PaintAll(True);
  AssertEquals('a picture waits', 1, FRich.Pending);
  AssertFalse('no handle, no turn', FRich.TurnQueued);
  FreeAndNil(FRich);
  FRich := NewProbe;
  NeedWidgetSet;
  F := TForm.CreateNew(nil);
  try
    FRich.Parent := F;
    F.HandleNeeded;
    FRich.HandleNeeded;
    AssertTrue('a handle', FRich.HandleAllocated);
    AssertFalse('the form is not shown', F.Visible);
    PictureDoc(1);
    PaintAll(True);
    AssertTrue('a surface', FRich.Surf <> nil);
    AssertEquals('a picture waits', 1, FRich.Pending);
    AssertTrue('with a handle, a turn queued', FRich.TurnQueued);
    { What InvalidateContent hands the window: the rectangle, through the real InvalidateArea
      (LCLIntf.InvalidateRect on the handle). Windows keeps no update region for a window that
      is not visible, so what the window makes of it is not observed here. }
    FRich.Invalidated := nil;
    FRich.InvalidatePart(Rect(20, 30, 120, 50));
    AssertEquals('InvalidateContent reaches the window''s invalidation', 1, Length(FRich.Invalidated));
    AssertTrue('its rectangle', EqualRect(FRich.Invalidated[0], Rect(20, 30, 120, 50)));
    FRich.DropHandle;
    AssertFalse('the handle went', FRich.HandleAllocated);
    AssertTrue('the surface with it', FRich.Surf = nil);
    AssertFalse('and the turn', FRich.TurnQueued);
    FRich.ResetCounts;
    PaintAll(True);
    AssertTrue('the next paint makes it again', FRich.Surf <> nil);
    AssertEquals('drawn in full', 1, FRich.FramePaints);
  finally
    FRich.Parent := nil;
    F.Free;
  end;
end;

{ H-M8: one timer turn does at most CRichIdleMaxSteps pieces whatever the clock says: with the
  clock standing still, five pictures take two turns. }
procedure TTyRichEditControlTest.TestOneTimerTurnStopsAtItsCap;
begin
  PictureDoc(5);
  PaintAll(True);
  AssertEquals('five wait', 5, FRich.Pending);
  FRich.FrozenClock := True;
  FRich.Turn;
  AssertEquals('one turn stops at its cap, with work left', 5 - CRichIdleMaxSteps, FRich.Pending);
  FRich.Turn;
  AssertEquals('the next does the rest', 0, FRich.Pending);
end;

{ H-I12: PositionRect settles the view after a scroll before a paint; a position held above the
  view has its rectangle there (unclipped); one in no held block has none. }
procedure TTyRichEditControlTest.TestPositionRectSettlesAndSaysWhereItIs;
var
  est: Integer;
  t: TTyRichText;
  r1, r2, pr: TRect;
  p: TTyRichPos;
begin
  SetLinesOf(1000, 'Line ');
  FRich.UpdateView;
  t := FRich.Document.Text;
  est := FRich.Layouter.EstimatedParaHeight(96, 1);
  FRich.ScrollViewBy(10 * est);
  p := t.ParaStart(FRich.TopParagraph + 2) + 3;
  r1 := FRich.PositionRect(p);
  FRich.UpdateView;
  r2 := FRich.PositionRect(p);
  AssertTrue('a caret rectangle', (r1.Bottom > r1.Top) and (r1.Right > r1.Left));
  AssertTrue('right after the scroll as after a layout', EqualRect(r1, r2));
  pr := FRich.ParagraphRect(FRich.TopParagraph + 2);
  AssertTrue('in its paragraph''s rows, on screen', (r1.Top >= pr.Top) and (r1.Bottom <= pr.Bottom)
    and (r1.Top >= FRich.Area.Top));
  pr := FRich.ParagraphRect(FRich.TopParagraph - 3);
  r1 := FRich.PositionRect(t.ParaStart(FRich.TopParagraph - 3));
  AssertTrue('held above the view: above it', (r1.Bottom > r1.Top) and (r1.Bottom <= FRich.Area.Top));
  AssertTrue('in its paragraph''s rows', (r1.Top >= pr.Top) and (r1.Bottom <= pr.Bottom));
  r1 := FRich.PositionRect(t.ParaStart(900));
  AssertTrue('in no held block: empty', (r1.Right = r1.Left) and (r1.Bottom = r1.Top));
end;

{ H-I12: right to left the vertical bar is on the left; the text area, the hit test and the
  painted text start right of it. }
procedure TTyRichEditControlTest.TestARightToLeftControlPutsItsBarLeft;
var
  a: TRect;
  x, y, inkX: Integer;
  ground: TBGRAPixel;
begin
  SetLinesOf(1000, 'Line ');
  FRich.BiDiMode := bdRightToLeft;
  PaintAll(True);
  AssertTrue('a bar', (FRich.VBar <> nil) and FRich.VBar.Visible);
  AssertEquals('on the left', 0, FRich.VBar.Left);
  a := FRich.Area;
  AssertTrue('the text right of it', a.Left >= FRich.VBar.Width);
  AssertEquals('a paragraph''s rectangle from there', a.Left, FRich.ParagraphRect(0).Left);
  AssertEquals('a point at the text''s left edge hits the line''s start', Int64(0),
    FRich.PositionAtPoint(a.Left + 1, a.Top + 2));
  // the first line's ink: none between the bar and the text area, some after it
  ground := FRich.Ground;
  inkX := -1;
  for x := FRich.VBar.Width to a.Left + 40 do
  begin
    for y := a.Top to a.Top + FRich.Layouter.EstimatedParaHeight(96, 1) - 1 do
      if not SamePx(FRich.Surf.GetPixel(x, y), ground) then
      begin
        inkX := x;
        Break;
      end;
    if inkX >= 0 then Break;
  end;
  AssertTrue(Format('the text is painted from the text area''s left (ink at %d, area at %d)',
    [inkX, a.Left]), inkX >= a.Left);
end;

{ H-I12: a change that takes in the anchor's paragraph puts the view at the change's start and
  paints it again. }
procedure TTyRichEditControlTest.TestAChangeThatSwallowsTheAnchor;
var
  t: TTyRichText;
  k: Integer;
begin
  SetLinesOf(200, 'Line ');
  FRich.UpdateView;
  t := FRich.Document.Text;
  FRich.ScrollY := t.ParaTop(50) + 3;
  FRich.UpdateView;
  AssertEquals('paragraph 50 on top', 50, FRich.TopParagraph);
  FRich.ResetCounts;
  AssertTrue('45 .. 55 deleted', FRich.Document.Execute(TTyRichDelete.Create(t.ParaStart(45),
    t.ParaStart(56) - t.ParaStart(45))));
  AssertEquals('the view at the change', 45, FRich.TopParagraph);
  AssertEquals('at its top', Int64(0), FRich.TopOffset);
  AssertTrue('painted again', Covered(FRich.Area));
  for k := 0 to FRich.VisibleBlockCount - 1 do
    if (FRich.VisibleBlocks[k].Top <= 0) and
      (FRich.VisibleBlocks[k].Top + FRich.VisibleBlocks[k].Height > 0) then
    begin
      AssertEquals('what followed is on top', 'Line 56', FRich.Lines[FRich.VisibleBlocks[k].FirstPara]);
      Exit;
    end;
  Fail('no block on top');
end;

{ H-I12: a paragraph inserted and removed on screen with a valid view: the rectangles, the
  held blocks' indexes and tops, the heights written, and only from the change down painted. }
procedure TTyRichEditControlTest.TestAParagraphInsertedAndRemovedOnScreen;
var
  old: array[0..7] of TRect;
  i, k, lineH: Integer;
  t: TTyRichText;

  procedure CheckHeld(const AWhen: string);
  var
    m: Integer;
  begin
    for m := 1 to FRich.VisibleBlockCount - 1 do
    begin
      AssertEquals(Format('%s: block %d follows in the document', [AWhen, m]),
        FRich.VisibleBlocks[m - 1].LastPara + 1, FRich.VisibleBlocks[m].FirstPara);
      AssertEquals(Format('%s: and on screen', [AWhen]), FRich.VisibleBlocks[m - 1].Top +
        FRich.VisibleBlocks[m - 1].Height, FRich.VisibleBlocks[m].Top);
    end;
    for m := 0 to FRich.VisibleBlockCount - 1 do
      AssertEquals(Format('%s: height %d written', [AWhen, m]),
        Int64(FRich.VisibleBlocks[m].Height), t.ParaHeight(FRich.VisibleBlocks[m].FirstPara));
  end;

  procedure CheckPainted(const AWhen: string);
  var
    m: Integer;
  begin
    AssertTrue(AWhen + ': from the change down painted again',
      Covered(Rect(FRich.Area.Left, old[3].Top, FRich.Area.Right, FRich.Area.Bottom)));
    for m := 0 to High(FRich.Invalidated) do
      AssertTrue(Format('%s: nothing above it (%d)', [AWhen, FRich.Invalidated[m].Top]),
        FRich.Invalidated[m].Top >= old[3].Top);
  end;

begin
  SetLinesOf(200, 'Line ');
  FRich.UpdateView;
  t := FRich.Document.Text;
  for i := 0 to High(old) do old[i] := FRich.ParagraphRect(i);
  lineH := old[1].Top - old[0].Top;
  FRich.ResetCounts;
  FRich.Lines.Insert(3, 'new');
  CheckPainted('inserted');
  AssertEquals('the new paragraph', 'new', FRich.Lines[3]);
  AssertTrue('at the place of the one it pushed down', EqualRect(old[3], FRich.ParagraphRect(3)));
  for i := 4 to 7 do
  begin
    AssertTrue(Format('paragraph %d a line lower', [i]),
      EqualRect(Rect(old[i - 1].Left, old[i - 1].Top + lineH, old[i - 1].Right,
      old[i - 1].Bottom + lineH), FRich.ParagraphRect(i)));
  end;
  AssertEquals('the top stays', 0, FRich.TopParagraph);
  CheckHeld('inserted');
  FRich.ResetCounts;
  FRich.Lines.Delete(3);
  CheckPainted('removed');
  for i := 0 to High(old) do
    AssertTrue(Format('paragraph %d back in its place', [i]), EqualRect(old[i], FRich.ParagraphRect(i)));
  AssertEquals('Line 3 back', 'Line 3', FRich.Lines[3]);
  CheckHeld('removed');
  k := FRich.VisibleBlockCount;
  AssertTrue('a view held', k > 0);
end;

{ H-I12: DetectFormat on nothing and on 1 to 5 bytes; the position is left where it was; an
  empty stream loads as no lines. }
procedure TTyRichEditControlTest.TestDetectFormatOnShortInput;

  procedure Check(const AData: RawByteString; AWant: TTyRichFormat);
  var
    st: TBytesStream;
  begin
    st := TBytesStream.Create(BytesOf(AData));
    try
      AssertTrue(Format('%d bytes "%s"', [Length(AData), AData]), FRich.Detect(st) = AWant);
      AssertEquals('the position stays', Int64(0), st.Position);
    finally
      st.Free;
    end;
  end;

var
  st: TBytesStream;
begin
  Check('', rfText);
  Check('{', rfText);
  Check('{\', rfText);
  Check('{\r', rfText);
  Check('{\rt', rfText);
  Check('{\rtf', rfRtf);
  Check(#$EF, rfText);
  Check(#$EF#$BB, rfText);
  Check(#$EF#$BB#$BF, rfText);
  Check(#$EF#$BB#$BF'{\rt', rfText);
  Check(' {\rtf', rfRtf);
  Check('x', rfText);
  st := TBytesStream.Create(nil);
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  AssertEquals('an empty stream: no lines', 0, FRich.Lines.Count);
  AssertTrue('read as text', FRich.SourceFormat = rfText);
end;

type
  { A stream whose reads fail past a byte. }
  TFailingStream = class(TBytesStream)
  public
    FailAt: Int64;
    function Read(var Buffer; Count: Longint): Longint; override;
  end;

function TFailingStream.Read(var Buffer; Count: Longint): Longint;
begin
  if Position + Count > FailAt then raise EReadError.Create('the test''s failing stream');
  Result := inherited Read(Buffer, Count);
end;

{ H-I12: a load that raises (a missing file, a stream that fails half way, as text and as RTF)
  leaves the old document, its SourceFile and SourceFormat, and a view that works. }
procedure TTyRichEditControlTest.TestALoadThatRaisesKeepsTheOldDocument;
var
  path, s: string;
  i, n: Integer;
  st: TFailingStream;
  raised: Boolean;
begin
  path := TempFile('old.rtf', BytesOf('{\rtf1\ansi\deff0{\fonttbl{\f0 Arial;}}\pard\f0 Old text.\par}'));
  FRich.LoadFromFile(path);
  FRich.FinishLoading;
  PaintAll(True);
  for n := 0 to 2 do
  begin
    raised := False;
    st := nil;
    try
      try
        case n of
          0: FRich.LoadFromFile(FTemp + 'missing.txt');
          1, 2:
            begin
              if n = 1 then s := '' else s := '{\rtf1\ansi\deff0{\fonttbl{\f0 Arial;}}\pard\f0 ';
              for i := 1 to 500 do s := s + 'new words ';
              if n = 2 then s := s + '\par}';
              st := TFailingStream.Create(BytesOf(s));
              st.FailAt := 1000;
              FRich.LoadFromStream(st);
            end;
        end;
      except
        on E: Exception do raised := True;
      end;
    finally
      st.Free;
    end;
    AssertTrue(Format('%d: the load raised', [n]), raised);
    AssertEquals(Format('%d: the old text', [n]), 'Old text.', FRich.Lines[0]);
    AssertEquals(Format('%d: its file', [n]), ExpandFileName(path), FRich.SourceFile);
    AssertTrue(Format('%d: as RTF', [n]), FRich.SourceFormat = rfRtf);
    FRich.UpdateView;
    AssertTrue(Format('%d: a view', [n]), FRich.VisibleBlockCount > 0);
    AssertEquals(Format('%d: that answers', [n]), Int64(0), FRich.PositionAtPoint(FRich.Area.Left,
      FRich.Area.Top + 1));
    PaintAll(True);
  end;
end;

{ ---- 9b: the caret and the selection ---- }

{ A character as UTF-8, from its number (this file stays ASCII). }
function Utf8Of(ACode: Cardinal): RawByteString;
begin
  if ACode < $80 then Result := AnsiChar(ACode)
  else if ACode < $800 then
    Result := AnsiChar($C0 or (ACode shr 6)) + AnsiChar($80 or (ACode and $3F))
  else if ACode < $10000 then
    Result := AnsiChar($E0 or (ACode shr 12)) + AnsiChar($80 or ((ACode shr 6) and $3F)) +
      AnsiChar($80 or (ACode and $3F))
  else
    Result := AnsiChar($F0 or (ACode shr 18)) + AnsiChar($80 or ((ACode shr 12) and $3F)) +
      AnsiChar($80 or ((ACode shr 6) and $3F)) + AnsiChar($80 or (ACode and $3F));
end;

procedure TTyRichEditControlTest.SelChanged(Sender: TObject);
begin
  Inc(FSelChanges);
end;

function TTyRichEditControlTest.At(APos: TTyRichPos): TPoint;
var
  r, r2: TRect;
begin
  r := FRich.PositionRect(APos);
  r2 := FRich.PositionRect(APos + 1);
  if (r2.Top = r.Top) and (r2.Left > r.Left + 2) then Result.X := r.Left + (r2.Left - r.Left) div 3
  else Result.X := r.Left + 1;
  Result.Y := (r.Top + r.Bottom) div 2;
end;

procedure TTyRichEditControlTest.LoadRtfText(const S: string);
var
  st: TBytesStream;
begin
  st := TBytesStream.Create(BytesOf(S));
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  FRich.FinishLoading;
  FRich.UpdateView;
end;

procedure TTyRichEditControlTest.Click(const P: TPoint; AShift: TShiftState);
begin
  FRich.PressAt(P.X, P.Y, AShift);
  FRich.ReleaseAt(P.X, P.Y);
end;

{ W1's affinity carried by the control: End puts the caret at the end of the line it is on (a
  wrapped line's end is also the next line's start), a click past a line's end does too, and
  Home after End stays on that line - Latin, Chinese and justified text. }
procedure TTyRichEditControlTest.TestEndAndAClickPastALineEndStayOnThatLine;
begin
  EndAndClickCase(1, False);
end;

{ S-I1: the caret is where it is drawn - inside the text, also at the end of a line that
  reaches the right edge; the input method is told that rectangle, and the blink paints that
  rectangle again (drawn, then blinked off). }
procedure TTyRichEditControlTest.CheckCaretInside(const AWhat: string);
var
  r, tw: TRect;
  bmp: TBitmap;
begin
  r := FRich.CaretClientRect;
  tw := FRich.TextWindow;
  AssertTrue(AWhat + ': a caret', (r.Bottom > r.Top) and (r.Right > r.Left));
  AssertTrue(Format('%s: inside the text (%d..%d in %d..%d)', [AWhat, r.Left, r.Right, tw.Left,
    tw.Right]), (r.Left >= tw.Left) and (r.Right <= tw.Right));
  FRich.ForceFocus := True;
  try
    AssertTrue(AWhat + ': the input method is told the same',
      EqualRect(r, (FRich as ITyImeEditable).ImeCaretBoundClient));
    bmp := TBitmap.Create;
    try
      bmp.SetSize(FRich.Width, FRich.Height);
      FRich.CaretOn(bmp.Canvas);
    finally
      bmp.Free;
    end;
    FRich.Invalidated := nil;
    FRich.Blink;
    AssertEquals(AWhat + ': drawn, so blinked off', 1, Length(FRich.Invalidated));
    AssertTrue(AWhat + ': where it was drawn', EqualRect(r, FRich.Invalidated[0]));
    FRich.Blink;
  finally
    FRich.ForceFocus := False;
  end;
end;

{ W1's affinity carried by the control: End puts the caret at the end of the line it is on (a
  wrapped line's end is also the next line's start), a click past a line's end does too, and
  Home after End stays on that line - Latin, Chinese, justified and centred text; the caret
  is drawn inside the text at every such end, and at a right-aligned line's (S-I1). At device
  scale AScale, right to left when ARtl (the bar on the left). }
procedure TTyRichEditControlTest.EndAndClickCase(AScale: Integer; ARtl: Boolean);
var
  more: string;
  rtfMore: string;

  procedure Prepare;
  begin
    if ARtl then FRich.BiDiMode := bdRightToLeft;
    PaintAll(True);
    AssertEquals('the scale', AScale, FRich.Scale);
  end;

  procedure Check(const AWhat: string);
  var
    L: TTyParaLayout;
    ln, lineTop, y, sc: Integer;
    s, e: TTyRichPos;
    a: TRect;
  begin
    Prepare;
    sc := FRich.Scale;
    a := FRich.Area;
    L := FRich.VisibleBlocks[0].Layout as TTyParaLayout;
    AssertTrue(AWhat + ': it wraps', L.LineCount >= 3);
    for ln := 0 to L.LineCount - 2 do
    begin
      s := L.Lines[ln].First;
      e := L.Lines[ln].First + L.Lines[ln].Count;
      lineTop := a.Top + Integer(FRich.VisibleBlocks[0].Top) + L.Lines[ln].Top div sc;
      FRich.SelStart := s;
      FRich.Press(VK_END, []);
      AssertEquals(Format('%s line %d: End', [AWhat, ln]), e, FRich.CaretIndex);
      AssertTrue(Format('%s line %d: End is the line''s end', [AWhat, ln]), FRich.CaretAtLineEnd);
      AssertEquals(Format('%s line %d: End shows on that line', [AWhat, ln]), lineTop,
        FRich.CaretClientRect.Top);
      CheckCaretInside(Format('%s line %d: End', [AWhat, ln]));
      FRich.Press(VK_HOME, []);
      AssertEquals(Format('%s line %d: Home after End', [AWhat, ln]), s, FRich.CaretIndex);
      y := lineTop + (L.Lines[ln].Height div sc) div 2;
      // in the right padding: past every line's end, also a justified one's
      Click(Point(FRich.Width - 1, y));
      AssertEquals(Format('%s line %d: a click past the end', [AWhat, ln]), e, FRich.CaretIndex);
      AssertEquals(Format('%s line %d: the click shows on that line', [AWhat, ln]), lineTop,
        FRich.CaretClientRect.Top);
      CheckCaretInside(Format('%s line %d: the click', [AWhat, ln]));
      FRich.Press(VK_HOME, []);
      AssertEquals(Format('%s line %d: Home after the click', [AWhat, ln]), s, FRich.CaretIndex);
    end;
  end;

var
  s: RawByteString;
  i: Integer;
  r: TRect;
begin
  if AScale > 1 then
  begin
    TyForceDeviceScaleForTest(AScale, True, False);
    FPaintScale := AScale;
  end;
  // lines after the paragraph: a vertical bar (on the left, right to left)
  more := '';
  rtfMore := '';
  for i := 1 to 30 do
  begin
    more := more + LineEnding + 'more';
    rtfMore := rtfMore + '\pard more\par';
  end;
  s := '';
  for i := 1 to 40 do s := s + 'word ';
  FRich.Lines.Text := s + more;
  Check('Latin');
  s := '';
  for i := 1 to 80 do s := s + Utf8Of($4E2D);
  FRich.Lines.Text := s + more;
  Check('Chinese');
  s := '{\rtf1\ansi\deff0{\fonttbl{\f0 Arial;}}\pard\qj ';
  for i := 1 to 25 do s := s + 'alpha beta ';
  LoadRtfText(s + '\par' + rtfMore + '}');
  Check('justified');
  s := '{\rtf1\ansi\deff0{\fonttbl{\f0 Arial;}}\pard\qc ';
  for i := 1 to 25 do s := s + 'alpha beta ';
  LoadRtfText(s + '\par' + rtfMore + '}');
  Check('centred');
  // a right-aligned line ends at the text's right edge
  LoadRtfText('{\rtf1\ansi\deff0{\fonttbl{\f0 Arial;}}\pard\qr right side\par' + rtfMore + '}');
  Prepare;
  FRich.SelStart := 0;
  FRich.Press(VK_END, []);
  AssertEquals('right-aligned: End', Int64(10), FRich.CaretIndex);
  CheckCaretInside('right-aligned: End');
  r := FRich.CaretClientRect;
  Click(Point(FRich.Width - 1, (r.Top + r.Bottom) div 2));
  AssertEquals('right-aligned: a click past the end', Int64(10), FRich.CaretIndex);
  CheckCaretInside('right-aligned: the click');
end;

procedure TTyRichEditControlTest.TestTheCaretAtALineEndAtScaleTwoAndRightToLeft;
begin
  EndAndClickCase(2, False);
  FreeAndNil(FRich);
  TyForceDeviceScaleForTest(0, False);
  FPaintScale := 1;
  FRich := NewProbe;
  EndAndClickCase(1, True);
end;

{ A step is what the layout shows as one: a cluster (a letter and its mark), an escaped byte's
  two characters, an object; a paragraph's separator is one step; a cell merged away is
  passed over (its empty paragraph is a position, but nothing is drawn there). }
procedure TTyRichEditControlTest.TestLeftAndRightStepOverWhatIsOneUnit;
var
  st: TBytesStream;
  t: TTyRichText;

  procedure Step(const AWhat: string; AFrom: TTyRichPos; AKey: Word; AWant: TTyRichPos);
  begin
    FRich.SelStart := AFrom;
    FRich.Press(AKey, []);
    AssertEquals(AWhat, AWant, FRich.CaretIndex);
  end;

begin
  FRich.Lines.Text := 'ae' + Utf8Of($301) + 'x' + #10 + 'cd';
  FRich.UpdateView;
  Step('over a combining mark', 1, VK_RIGHT, 3);
  Step('back over it', 3, VK_LEFT, 1);
  Step('across the separator', 4, VK_RIGHT, 5);
  Step('back across it', 5, VK_LEFT, 4);
  { UTF-16 with a lone surrogate: its two bytes are no text and are escaped, each two
    characters shown as one replacement - a step each }
  st := TBytesStream.Create(BytesOf(#$FF#$FE'a'#0#0#$D8'b'#0));
  try
    FRich.LoadFromStream(st, rfText);
  finally
    st.Free;
  end;
  FRich.UpdateView;
  AssertEquals('two escaped bytes, two characters each', Int64(6), FRich.Document.Text.Length);
  Step('over an escaped byte', 1, VK_RIGHT, 3);
  Step('over the next', 3, VK_RIGHT, 5);
  Step('back over it', 5, VK_LEFT, 3);
  Step('back over the first', 3, VK_LEFT, 1);
  // an object
  PictureDoc(1);
  FRich.UpdateView;
  Step('over an object', 1, VK_RIGHT, 2);
  Step('back over it', 2, VK_LEFT, 1);
  // a row whose second cell is merged into the first
  LoadRtfText('{\rtf1\ansi\deff0{\fonttbl{\f0 Arial;}}\trowd\clmgf\cellx1500\clmrg\cellx3000' +
    '\cellx4500\pard\intbl m\cell\pard\intbl\cell\pard\intbl c\cell\row\pard after\par}');
  t := FRich.Document.Text;
  AssertEquals('four paragraphs', 4, t.ParaCount);
  AssertEquals('the merged-away cell''s paragraph', Int64(2), t.ParaStart(1));
  AssertEquals('the third cell', Int64(3), t.ParaStart(2));
  Step('past the cell merged away', 1, VK_RIGHT, 3);
  Step('back past it', 3, VK_LEFT, 1);
  Step('out of the row', 4, VK_RIGHT, 5);
  Step('into the row', 5, VK_LEFT, 4);
end;

{ Up and Down keep the x of the first of them through a short line; they go down a column of
  cells, into a cell merged into the one beside it, and out of the table. }
procedure TTyRichEditControlTest.TestUpAndDownKeepTheWishedXAndCrossATable;
var
  t: TTyRichText;
  i: Integer;
const
  // the second column: b1, its second paragraph, b2, the merged cell, after; back up
  Want: array[0..6] of Integer = (2, 3, 5, 6, 8, 6, 5);
  // the first column: a1, a2 (below a cell shorter than its row), the merged cell, after
  WantFirst: array[0..3] of Integer = (1, 4, 6, 8);
begin
  FRich.Lines.Text := 'a long first line of text'#10'ab'#10'a long third line of text';
  FRich.UpdateView;
  FRich.SelStart := 20;
  FRich.Press(VK_DOWN, []);
  AssertEquals('down to the short line''s end', Int64(28), FRich.CaretIndex);
  FRich.Press(VK_DOWN, []);
  AssertEquals('down again: the x of the start', Int64(49), FRich.CaretIndex);
  FRich.Press(VK_UP, []);
  FRich.Press(VK_UP, []);
  AssertEquals('and back up', Int64(20), FRich.CaretIndex);
  // a table: two cells a row, the last row merged into one cell
  LoadRtfText('{\rtf1\ansi\deff0{\fonttbl{\f0 Arial;}}\pard top text that is long enough here\par' +
    '\trowd\cellx1500\cellx3000\pard\intbl a1\cell\pard\intbl b1\par\pard\intbl b1x\cell\row' +
    '\trowd\cellx1500\cellx3000\pard\intbl a2\cell\pard\intbl b2\cell\row' +
    '\trowd\clmgf\cellx1500\clmrg\cellx3000\pard\intbl m\cell\pard\intbl\cell\row' +
    '\pard after\par}');
  t := FRich.Document.Text;
  AssertEquals('paragraphs', 9, t.ParaCount);
  // x in the second column (1500 twips = 100 px)
  FRich.SelStart := 20;
  AssertTrue('the start is right of the first column',
    FRich.CaretClientRect.Left - FRich.Area.Left > 100);
  for i := 0 to 4 do
  begin
    FRich.Press(VK_DOWN, []);
    AssertEquals(Format('down %d', [i + 1]), Want[i], t.ParaOfPos(FRich.CaretIndex));
  end;
  FRich.Press(VK_UP, []);
  AssertEquals('up into the merged cell', Want[5], t.ParaOfPos(FRich.CaretIndex));
  FRich.Press(VK_UP, []);
  AssertEquals('up the column', Want[6], t.ParaOfPos(FRich.CaretIndex));
  // the first column: out of a cell whose row is taller than it
  FRich.SelStart := 1;
  for i := 0 to 3 do
  begin
    FRich.Press(VK_DOWN, []);
    AssertEquals(Format('first column, down %d', [i + 1]), WantFirst[i],
      t.ParaOfPos(FRich.CaretIndex));
  end;
end;

{ Shift moves the caret and keeps the anchor, either way; an arrow without it collapses the
  selection to its side; Ctrl steps by words, Home / End by the line. }
procedure TTyRichEditControlTest.TestShiftSelectionAndItsCollapse;
begin
  FRich.Lines.Text := 'hello world';
  FRich.UpdateView;
  FRich.SelStart := 5;
  FRich.Press(VK_RIGHT, [ssShift]);
  FRich.Press(VK_RIGHT, [ssShift]);
  AssertEquals('right: start', Int64(5), FRich.SelStart);
  AssertEquals('right: length', Int64(2), FRich.SelLength);
  FRich.Press(VK_LEFT, [ssShift]);
  FRich.Press(VK_LEFT, [ssShift]);
  FRich.Press(VK_LEFT, [ssShift]);
  FRich.Press(VK_LEFT, [ssShift]);
  AssertEquals('back past the anchor: start', Int64(3), FRich.SelStart);
  AssertEquals('back past the anchor: length', Int64(2), FRich.SelLength);
  AssertEquals('the caret is the start', Int64(3), FRich.CaretIndex);
  FRich.Press(VK_RIGHT, []);
  AssertEquals('Right collapses to the right side', Int64(5), FRich.CaretIndex);
  AssertFalse('nothing selected', FRich.HasSelection);
  FRich.Press(VK_LEFT, [ssShift]);
  FRich.Press(VK_LEFT, []);
  AssertEquals('Left collapses to the left side', Int64(4), FRich.CaretIndex);
  FRich.SelStart := 0;
  FRich.Press(VK_RIGHT, [ssCtrl]);
  AssertEquals('Ctrl+Right: the next word', Int64(6), FRich.CaretIndex);
  FRich.Press(VK_END, []);
  FRich.Press(VK_LEFT, [ssCtrl]);
  AssertEquals('Ctrl+Left: the word''s start', Int64(6), FRich.CaretIndex);
  FRich.Press(VK_HOME, [ssShift]);
  AssertEquals('Shift+Home: from the start', Int64(0), FRich.SelStart);
  AssertEquals('Shift+Home: to the anchor', Int64(6), FRich.SelLength);
  FRich.Press(VK_END, [ssShift, ssCtrl]);
  AssertEquals('Ctrl+Shift+End: from the anchor', Int64(6), FRich.SelStart);
  AssertEquals('Ctrl+Shift+End: to the end', Int64(5), FRich.SelLength);
end;

{ A double click selects the word and a drag after it goes by words, the word clicked staying
  selected; a triple click the paragraph with its separator, a drag after it by paragraphs;
  Shift+click extends from the anchor. }
procedure TTyRichEditControlTest.TestWordAndParagraphSelectionAndTheirDrags;
var
  p: TPoint;
begin
  FRich.Lines.Text := 'alpha beta gamma'#10'second line here';
  FRich.UpdateView;
  p := At(7);
  Click(p);
  FRich.PressAt(p.X, p.Y, [ssDouble]);
  AssertEquals('double click: the word''s start', Int64(6), FRich.SelStart);
  AssertEquals('double click: the word', Int64(4), FRich.SelLength);
  FRich.MoveAt(At(13).X, At(13).Y);
  AssertEquals('dragged on: from the word', Int64(6), FRich.SelStart);
  AssertEquals('dragged on: to the end of the word reached', Int64(10), FRich.SelLength);
  FRich.MoveAt(At(2).X, At(2).Y);
  AssertEquals('dragged back: from the word reached', Int64(0), FRich.SelStart);
  AssertEquals('dragged back: the word clicked stays', Int64(10), FRich.SelLength);
  FRich.ReleaseAt(p.X, p.Y);
  // a triple click
  p := At(8);
  Click(p);
  Click(p, [ssDouble]);
  FRich.PressAt(p.X, p.Y);
  AssertEquals('triple click: the paragraph''s start', Int64(0), FRich.SelStart);
  AssertEquals('triple click: with its separator', Int64(17), FRich.SelLength);
  FRich.MoveAt(At(20).X, At(20).Y);
  AssertEquals('dragged into the next: the last has no separator', Int64(33), FRich.SelLength);
  FRich.ReleaseAt(p.X, p.Y);
  // Shift+click
  Click(At(2));
  Click(At(8), [ssShift]);
  AssertEquals('Shift+click: from the anchor', Int64(2), FRich.SelStart);
  AssertEquals('Shift+click: to the click', Int64(6), FRich.SelLength);
end;

{ A drag held below the text scrolls (the drag timer's handler, driven here) and the selection
  follows; further out it scrolls faster; the button let go, it stops. Disabling the control
  ends a drag. }
procedure TTyRichEditControlTest.TestADragOutsideScrollsAndSelects;
var
  p: TPoint;
  y0, y1, d1, d2: Int64;
  c0, anchor: TTyRichPos;
begin
  SetLinesOf(300, 'Line ');
  FRich.UpdateView;
  anchor := FRich.Document.Text.ParaStart(1);
  p := At(anchor);
  FRich.PressAt(p.X, p.Y);
  AssertTrue('a drag', FRich.DragOn);
  FRich.MoveAt(p.X, FRich.Height + 5);
  y0 := FRich.ScrollY;
  c0 := FRich.CaretIndex;
  FRich.DragTick;
  d1 := FRich.ScrollY - y0;
  AssertTrue('it scrolled', d1 > 0);
  AssertTrue('the selection followed', FRich.CaretIndex > c0);
  AssertEquals('from the anchor', anchor, FRich.SelStart);
  FRich.MoveAt(p.X, FRich.Height + 100);
  y1 := FRich.ScrollY;
  FRich.DragTick;
  d2 := FRich.ScrollY - y1;
  AssertTrue(Format('further out, faster (%d, %d)', [d1, d2]), d2 > d1);
  FRich.ReleaseAt(p.X, FRich.Height + 100);
  AssertFalse('let go', FRich.DragOn);
  y1 := FRich.ScrollY;
  FRich.DragTick;
  AssertEquals('no more scrolling', y1, FRich.ScrollY);
  FRich.PressAt(p.X, p.Y);
  FRich.Enabled := False;
  AssertFalse('disabled: no drag', FRich.DragOn);
  FRich.Enabled := True;
end;

{ After a move the view scrolls by the least that shows the caret's line whole: a line down
  past the bottom puts it at the bottom, one up past the top at the top, a far jump from above
  at the bottom. The wheel scrolls without moving the caret. }
procedure TTyRichEditControlTest.TestTheCaretIsScrolledIntoViewByTheLeastAmount;
var
  a, r: TRect;
  i: Integer;
  y, est: Int64;
  c: TTyRichPos;
begin
  SetLinesOf(300, 'Line ');
  FRich.UpdateView;
  a := FRich.Area;
  est := FRich.Layouter.EstimatedParaHeight(96, 1);
  i := 0;
  while (FRich.ScrollY = 0) and (i < 100) do
  begin
    FRich.Press(VK_DOWN, []);
    Inc(i);
  end;
  r := FRich.CaretClientRect;
  AssertEquals('down past the bottom: the line at the bottom', a.Bottom, r.Bottom);
  AssertTrue('by less than a line', FRich.ScrollY <= est);
  y := FRich.ScrollY;
  i := 0;
  while (FRich.ScrollY = y) and (i < 100) do
  begin
    FRich.Press(VK_UP, []);
    Inc(i);
  end;
  AssertEquals('up past the top: the line at the top', a.Top, FRich.CaretClientRect.Top);
  c := FRich.CaretIndex;
  y := FRich.ScrollY;
  FRich.Wheel(-120, []);
  FRich.UpdateView;
  AssertTrue('the wheel scrolls', FRich.ScrollY <> y);
  AssertEquals('and leaves the caret', c, FRich.CaretIndex);
  FRich.SelStart := FRich.Document.Text.ParaStart(200);
  AssertEquals('a jump from above: at the bottom', a.Bottom, FRich.CaretClientRect.Bottom);
end;

{ One Shift+Down repaints that line's band and nothing else: the invalidated rectangles are in
  its rows, and the paint draws only the blocks next to it. }
procedure TTyRichEditControlTest.TestASelectionChangeRepaintsOnlyItsLines;
var
  t: TTyRichText;
  band: TRect;
  i: Integer;
begin
  SetLinesOf(300, 'Line ');
  t := FRich.Document.Text;
  FRich.SelStart := t.ParaStart(3);
  PaintAll(True);
  band := FRich.ParagraphRect(3);
  FRich.ResetCounts;
  FRich.Press(VK_DOWN, [ssShift]);
  AssertEquals('a line selected', t.ParaStart(4) - t.ParaStart(3), FRich.SelLength);
  AssertTrue('something invalidated', Length(FRich.Invalidated) > 0);
  for i := 0 to High(FRich.Invalidated) do
    AssertTrue(Format('rectangle %d in the line''s band', [i]),
      (FRich.Invalidated[i].Top >= band.Top) and (FRich.Invalidated[i].Bottom <= band.Bottom));
  AssertEquals('nothing laid out', 0, FRich.LaidParas);
  PaintAll(True);
  AssertTrue(Format('only the blocks next to it drawn (%d)', [FRich.BlockPaints]),
    FRich.BlockPaints <= 3);
  AssertEquals('no frame', 0, FRich.FramePaints);
end;

{ Select All in a 2,000,000-line document: no layout, no walk over the paragraphs (a few
  lookups of the held blocks), the view painted once. }
procedure TTyRichEditControlTest.TestSelectAllInAHugeDocumentLaysOutNothing;
var
  t: TTyRichText;
  visits: Int64;
  n: Integer;
begin
  LoadBig;
  t := FRich.Document.Text;
  PaintAll(True);
  n := FRich.VisibleBlockCount;
  FRich.ResetCounts;
  visits := t.NodeVisits;
  FRich.SelectAll;
  AssertEquals('all of it', t.Length, FRich.SelLength);
  AssertEquals('no layout asked for', 0, Length(FRich.Given));
  AssertTrue(Format('a few lookups (%d)', [t.NodeVisits - visits]), t.NodeVisits - visits < 5000);
  PaintAll(True);
  AssertTrue(Format('the view painted once (%d of %d)', [FRich.BlockPaints, n]),
    FRich.BlockPaints <= n);
  AssertEquals('still nothing laid out', 0, FRich.LaidParas);
end;

{ The caret and the anchor follow the document's changes: a change before them shifts them, an
  insertion at the caret leaves it, a deletion around it puts it at the deletion's start, a
  format change leaves them, a new content puts both at 0, a lazy load's slices leave them. }
procedure TTyRichEditControlTest.TestDocumentChangesMoveTheCaretAndTheSelection;
var
  f: TTyCharFormat;
  st: TBytesStream;
  paras, k: Integer;
begin
  FRich.Lines.Text := 'abcdef';
  FRich.UpdateView;
  FRich.SelStart := 4;
  AssertTrue(FRich.Document.Execute(TTyRichInsertText.Create(1, 'XY')));
  AssertEquals('an insertion before', Int64(6), FRich.CaretIndex);
  AssertTrue(FRich.Document.Execute(TTyRichInsertText.Create(6, 'Q')));
  AssertEquals('an insertion at the caret', Int64(6), FRich.CaretIndex);
  AssertTrue(FRich.Document.Execute(TTyRichDelete.Create(0, 2)));
  AssertEquals('a deletion before', Int64(4), FRich.CaretIndex);
  AssertTrue(FRich.Document.Execute(TTyRichDelete.Create(3, 3)));
  AssertEquals('a deletion around it', Int64(3), FRich.CaretIndex);
  FRich.SelStart := 1;
  FRich.SelLength := 2;
  AssertTrue(FRich.Document.Execute(TTyRichInsertText.Create(0, 'zz')));
  AssertEquals('the selection moved: start', Int64(3), FRich.SelStart);
  AssertEquals('the selection moved: length', Int64(2), FRich.SelLength);
  f := TyDefaultCharFormat;
  f.Style := [fsBold];
  AssertTrue(FRich.Document.Execute(TTyRichSetCharFormat.Create(TyRichRange(0, 5), [cffBold], f)));
  AssertEquals('a format change: start', Int64(3), FRich.SelStart);
  AssertEquals('a format change: length', Int64(2), FRich.SelLength);
  FRich.Lines.Text := 'new';
  AssertEquals('a new content: the caret', Int64(0), FRich.CaretIndex);
  AssertFalse('a new content: nothing selected', FRich.HasSelection);
  // a lazy load's slices
  FRich.Slices(4096, 4096);
  st := TBytesStream.Create(GeneratedRtf(200000, paras));
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  AssertTrue('loading', FRich.Loading);
  FRich.SelStart := 10;
  k := 0;
  while FRich.Loading and (k < 1000) do
  begin
    FRich.Step;
    Inc(k);
  end;
  AssertFalse('loaded', FRich.Loading);
  AssertEquals('the slices left the caret', Int64(10), FRich.CaretIndex);
end;

{ Every arrow is the viewer's - also where the caret cannot move (it never reaches the
  parent's focus navigation); Tab, Enter, Esc go on to the form. }
procedure TTyRichEditControlTest.TestTheViewerTakesItsKeysAndLeavesTheRest;
begin
  // the viewer's keys (Task 10a: an editor takes Enter)
  FRich.ReadOnly := True;
  FRich.Lines.Text := 'abc';
  FRich.UpdateView;
  FRich.SelStart := 0;
  AssertEquals('Left at the start', 0, FRich.KeyResult(VK_LEFT, []));
  AssertEquals('Up on the first line', 0, FRich.KeyResult(VK_UP, []));
  FRich.SelStart := 3;
  AssertEquals('Right at the end', 0, FRich.KeyResult(VK_RIGHT, []));
  AssertEquals('Down on the last line', 0, FRich.KeyResult(VK_DOWN, []));
  AssertEquals('Shift+Right at the end', 0, FRich.KeyResult(VK_RIGHT, [ssShift]));
  AssertEquals('Ctrl+A', 0, FRich.KeyResult(VK_A, [ssCtrl]));
  AssertEquals('Tab goes on', VK_TAB, FRich.KeyResult(VK_TAB, []));
  AssertEquals('Shift+Tab goes on', VK_TAB, FRich.KeyResult(VK_TAB, [ssShift]));
  AssertEquals('Enter goes on', VK_RETURN, FRich.KeyResult(VK_RETURN, []));
  AssertEquals('Esc goes on', VK_ESCAPE, FRich.KeyResult(VK_ESCAPE, []));
  AssertEquals('a letter goes on', VK_X, FRich.KeyResult(VK_X, []));
end;

{ A click that only places the caret, and the caret's blink, draw no block and no frame: the
  window is invalidated where the caret was and is (the caret is drawn over the blit), never
  the surface. }
procedure TTyRichEditControlTest.TestAClickAndABlinkDrawNoText;
var
  t: TTyRichText;
  i: Integer;
  r: TRect;
  bmp: TBitmap;
begin
  SetLinesOf(50, 'Line ');
  t := FRich.Document.Text;
  FRich.ForceFocus := True;
  PaintAll(True);
  FRich.ResetCounts;
  Click(At(t.ParaStart(2) + 1));
  AssertEquals('the caret placed', t.ParaStart(2) + 1, FRich.CaretIndex);
  AssertTrue('the caret''s rectangle invalidated', Length(FRich.Invalidated) > 0);
  for i := 0 to High(FRich.Invalidated) do
    AssertTrue(Format('only a caret''s width (%d)', [i]),
      FRich.Invalidated[i].Right - FRich.Invalidated[i].Left <= 2);
  PaintAll(True);
  AssertEquals('the click drew no block', 0, FRich.BlockPaints);
  AssertEquals('nor the frame', 0, FRich.FramePaints);
  // the caret over the blit
  bmp := TBitmap.Create;
  try
    bmp.SetSize(FRich.Width, FRich.Height);
    FRich.PaintPart(bmp.Canvas, Rect(0, 0, FRich.Width, FRich.Height), True);
    FRich.CaretOn(bmp.Canvas);
    r := FRich.CaretClientRect;
    AssertEquals('drawn in the text colour', TyColorToLCL(FRich.CurrentStyle.TextColor),
      bmp.Canvas.Pixels[r.Left, (r.Top + r.Bottom) div 2]);
  finally
    bmp.Free;
  end;
  FRich.ResetCounts;
  FRich.Blink;
  AssertEquals('the blink: one rectangle', 1, Length(FRich.Invalidated));
  AssertTrue('the caret''s', EqualRect(r, FRich.Invalidated[0]));
  FRich.Blink;
  AssertEquals('and back: one rectangle', 2, Length(FRich.Invalidated));
  AssertTrue('the caret''s again', EqualRect(r, FRich.Invalidated[1]));
  PaintAll(True);
  AssertEquals('the blinks drew no block', 0, FRich.BlockPaints);
end;

{ The blocks paint the selection: its colour is on the surface where text is selected, as much
  more as more is selected. }
procedure TTyRichEditControlTest.TestTheSelectionIsPainted;
var
  sel: TBGRAPixel;
  part: Integer;
begin
  // a solid colour of its own: the theme's may be translucent (blended with the ground)
  FRich.StyleOverride := '--selection: #FF0000;';
  FRich.Lines.Text := 'abc def ghi';
  PaintAll(True);
  sel := FRich.Style.SelectionBack;
  AssertEquals('nothing selected', 0, SurfaceCount(sel));
  FRich.SelStart := 4;
  FRich.SelLength := 3;
  PaintAll(True);
  part := SurfaceCount(sel);
  AssertTrue('a part selected', part > 0);
  FRich.SelectAll;
  PaintAll(True);
  AssertTrue('all selected: more', SurfaceCount(sel) > part);
  FRich.CollapseSelection;
  PaintAll(True);
  AssertEquals('none again', 0, SurfaceCount(sel));
end;

{ SelStart and SelLength clamp to the document and to caret places (a cluster's start). }
procedure TTyRichEditControlTest.TestSelStartAndSelLengthClampToCaretPlaces;
begin
  FRich.Lines.Text := 'ae' + Utf8Of($301) + 'x';
  FRich.SelStart := -3;
  AssertEquals('below 0', Int64(0), FRich.SelStart);
  FRich.SelStart := 99;
  AssertEquals('past the end', Int64(4), FRich.SelStart);
  FRich.SelStart := 2;
  AssertEquals('inside a cluster: its start', Int64(1), FRich.SelStart);
  FRich.SelStart := 0;
  FRich.SelLength := 2;
  AssertEquals('an end inside a cluster', Int64(1), FRich.SelLength);
  FRich.SelLength := 99;
  AssertEquals('a length past the end', Int64(4), FRich.SelLength);
  AssertEquals('the caret at the end', Int64(4), FRich.CaretIndex);
end;

{ A click on a picture selects it: the selection is its one character. }
procedure TTyRichEditControlTest.TestAClickOnAnObjectSelectsIt;
var
  r1, r2: TRect;
begin
  PictureDoc(1);
  FRich.UpdateView;
  r1 := FRich.PositionRect(1);
  r2 := FRich.PositionRect(2);
  AssertTrue('the picture is wide', r2.Left - r1.Left > 10);
  Click(Point((r1.Left + r2.Left) div 2, (r1.Top + r1.Bottom) div 2));
  AssertEquals('the picture: start', Int64(1), FRich.SelStart);
  AssertEquals('the picture: its character', Int64(1), FRich.SelLength);
  Click(At(0));
  AssertFalse('a letter: the caret only', FRich.HasSelection);
end;

{ The I-beam over the text, the arrow over the padding; a right click outside the selection
  moves the caret there, inside it keeps the selection. }
procedure TTyRichEditControlTest.TestTheCursorAndARightClick;
var
  a: TRect;
  p: TPoint;
begin
  FRich.Lines.Text := 'alpha beta';
  FRich.UpdateView;
  a := FRich.Area;
  AssertEquals('over the text', Ord(crIBeam), Ord(FRich.CursorFor((a.Left + a.Right) div 2,
    (a.Top + a.Bottom) div 2)));
  AssertEquals('over the padding', Ord(crDefault), Ord(FRich.CursorFor(1, 1)));
  FRich.SelStart := 6;
  FRich.SelLength := 4;
  p := At(7);
  FRich.RightAt(p.X, p.Y);
  AssertEquals('inside: kept', Int64(4), FRich.SelLength);
  p := At(1);
  FRich.RightAt(p.X, p.Y);
  AssertFalse('outside: collapsed', FRich.HasSelection);
  AssertEquals('at the click', Int64(1), FRich.CaretIndex);
end;

{ OnSelectionChange once per action that moves an end, never for one that moves none. }
procedure TTyRichEditControlTest.TestOneSelectionEventPerAction;
var
  p: TPoint;
begin
  FRich.Lines.Text := 'alpha beta gamma';
  FRich.UpdateView;
  FRich.OnSelectionChange := @SelChanged;
  FSelChanges := 0;
  FRich.Press(VK_LEFT, []);
  AssertEquals('a key that moves nothing', 0, FSelChanges);
  FRich.Press(VK_RIGHT, [ssShift]);
  AssertEquals('a key', 1, FSelChanges);
  FRich.Press(VK_END, []);
  AssertEquals('another key', 2, FSelChanges);
  p := At(2);
  FRich.PressAt(p.X, p.Y);
  AssertEquals('a press', 3, FSelChanges);
  FRich.MoveAt(At(8).X, At(8).Y);
  AssertEquals('a move of the drag', 4, FSelChanges);
  FRich.MoveAt(At(8).X, At(8).Y);
  AssertEquals('a move that changes nothing', 4, FSelChanges);
  FRich.ReleaseAt(p.X, p.Y);
  FRich.SelectAll;
  AssertEquals('Select All', 5, FSelChanges);
end;

{ The plan's: a copy puts both flavours through the clipboard seam (never the system's); the
  RTF read back is the range - its paragraphs, their text, the formats of their characters (a
  bold run, a Chinese font), the last paragraph taken without its separator plain. }
procedure TTyRichEditControlTest.TestCopyPutsRtfAndPlainText;
var
  t: TTyRichText;
  b: TTyRichDocument;
  st: TBytesStream;
  runs: TTyRunArray;
  k: Integer;
  zh: RawByteString;
begin
  zh := Utf8Of($4E2D);
  LoadRtfText('{\rtf1\ansi\ansicpg936\deff0{\fonttbl{\f0 Arial;}{\f1\fcharset134 SimSun;}}' +
    '\pard\b Bold\b0  plain \f1\' + 'u20013?\f0  end\par\pard\qc second line\par\pard third\par}');
  t := FRich.Document.Text;
  FRich.SelStart := 2;
  FRich.SelLength := t.ParaStart(1) + 6 - 2;
  FRich.CopyToClipboard;
  AssertEquals('one write', 1, FRich.ClipWrites);
  AssertEquals('the text', 'ld plain ' + zh + ' end' + LineEnding + 'second', FRich.ClipText);
  AssertEquals('the text is SelText', FRich.SelText, FRich.ClipText);
  AssertEquals('RTF', 1, Pos('{\rtf1', FRich.ClipRtf));
  b := TTyRichDocument.Create;
  st := TBytesStream.Create(BytesOf(FRich.ClipRtf));
  try
    TyRichLoadRtfFull(b, st);
    AssertEquals('two paragraphs', 2, b.Text.ParaCount);
    AssertEquals('the first, from its third character', 'ld plain ' + zh + ' end',
      b.Text.GetText(0, b.Text.ParaLength(0)));
    AssertEquals('the second, its first word', 'second', b.Text.GetText(b.Text.ParaStart(1), 6));
    runs := b.RunsOf(0);
    AssertTrue('bold', fsBold in b.Formats.CharFormat(runs[0].Format).Style);
    k := 0;
    while (k < High(runs)) and (runs[k + 1].Start <= 9) do Inc(k);
    AssertEquals('the Chinese character''s font', 'SimSun', b.Formats.CharFormat(runs[k].Format).FontName);
    AssertTrue('a part without its separator takes no centring',
      b.Formats.ParaFormat(b.ParaFormatOf(1)).Align = paraLeft);
  finally
    st.Free;
    b.Free;
  end;
end;

{ The plain text, rule by rule: a paragraph's end and U+000B the platform's line break, an
  object nothing, an escaped byte one U+FFFD; rows whole, cells parted by tabs (a cell merged
  away a tab and nothing else), a row ended by a line break; inside one cell just its text.
  SelText says the same as the copy. }
procedure TTyRichEditControlTest.TestThePlainTextRules;
var
  t: TTyRichText;
  st: TBytesStream;
  fffd: RawByteString;
begin
  fffd := Utf8Of($FFFD);
  FRich.Lines.Text := 'ab'#10'cd';
  FRich.SelectAll;
  AssertEquals('a separator', 'ab' + LineEnding + 'cd', FRich.SelText);
  AssertTrue(FRich.Document.Execute(TTyRichInsertText.Create(1, #11)));
  FRich.SelectAll;
  AssertEquals('a line break inside a paragraph', 'a' + LineEnding + 'b' + LineEnding + 'cd',
    FRich.SelText);
  PictureDoc(1);
  FRich.SelectAll;
  AssertEquals('an object gives nothing', 'a b', FRich.SelText);
  st := TBytesStream.Create(BytesOf(#$FF#$FE'a'#0#0#$D8'b'#0));
  try
    FRich.LoadFromStream(st, rfText);
  finally
    st.Free;
  end;
  FRich.SelectAll;
  AssertEquals('an escaped byte each one replacement', 'a' + fffd + fffd + 'b', FRich.SelText);
  LoadRtfText('{\rtf1\ansi\deff0{\fonttbl{\f0 Arial;}}\pard before\par' +
    '\trowd\cellx1500\cellx3000\pard\intbl one\cell\pard\intbl two\cell\row' +
    '\trowd\clmgf\cellx1500\clmrg\cellx3000\cellx4500\pard\intbl m\cell\pard\intbl\cell' +
    '\pard\intbl c\cell\row\pard after\par}');
  t := FRich.Document.Text;
  AssertEquals('seven paragraphs', 7, t.ParaCount);
  FRich.SelStart := t.ParaStart(1) + 1;
  FRich.SelLength := 4;
  AssertEquals('two cells: the row', 'one'#9'two' + LineEnding, FRich.SelText);
  FRich.SelStart := 3;
  FRich.SelLength := t.ParaStart(3) + 1 - 3;
  AssertEquals('across the table''s top: rows whole, a merged cell its tab',
    'ore' + LineEnding + 'one'#9'two' + LineEnding + 'm'#9#9'c' + LineEnding, FRich.SelText);
  FRich.SelStart := t.ParaStart(2) + 1;
  FRich.SelLength := 2;
  AssertEquals('inside one cell: its text', 'wo', FRich.SelText);
  FRich.CopyToClipboard;
  AssertEquals('the copy''s text is SelText', 'wo', FRich.ClipText);
end;

{ Nothing selected: a copy puts nothing on the clipboard (it keeps what it had). }
procedure TTyRichEditControlTest.TestAnEmptySelectionCopiesNothing;
begin
  FRich.Lines.Text := 'some text';
  FRich.SelStart := 3;
  FRich.CopyToClipboard;
  FRich.Press(VK_C, [ssCtrl]);
  AssertEquals('nothing written', 0, FRich.ClipWrites);
  FRich.SelLength := 2;
  FRich.Press(VK_C, [ssCtrl]);
  AssertEquals('Ctrl+C', 1, FRich.ClipWrites);
  AssertEquals('what was selected', 'e ', FRich.ClipText);
  FRich.Press(VK_INSERT, [ssCtrl]);
  AssertEquals('Ctrl+Insert', 2, FRich.ClipWrites);
end;

{ A copy past the wait threshold shows the wait cursor around it, and puts it back also when
  the clipboard raises; a smaller one does not. }
procedure TTyRichEditControlTest.TestAHugeCopyShowsTheWaitCursor;
var
  raised: Boolean;
begin
  FRich.Lines.Text := 'a text of some twenty characters';
  FRich.SetCopyWait(10);
  FRich.SelStart := 0;
  FRich.SelLength := 3;
  FRich.CopyToClipboard;
  AssertEquals('small: no wait', 0, FRich.Waits);
  FRich.SelLength := 20;
  FRich.CopyToClipboard;
  AssertEquals('big: the wait cursor', 1, FRich.Waits);
  AssertEquals('and back', 1, FRich.WaitEnds);
  FRich.FailClip := True;
  raised := False;
  try
    FRich.CopyToClipboard;
  except
    raised := True;
  end;
  AssertTrue('the clipboard raised', raised);
  AssertEquals('back after a failure too', 2, FRich.WaitEnds);
end;

{ The menu's states for a viewer: Copy with a selection, Select All with text, the editing
  items not available; Copy and Select All act; a user's PopupMenu is shown instead. }
procedure TTyRichEditControlTest.TestTheMenuOfAViewer;
var
  acts: ITyTextEditActions;
  pm: TPopupMenu;
begin
  // the viewer's menu (Task 10a: ReadOnly is False by default)
  FRich.ReadOnly := True;
  FRich.Lines.Text := 'menu text';
  acts := FRich as ITyTextEditActions;
  AssertTrue('read-only', acts.TeIsReadOnly);
  AssertFalse('no undo', acts.TeCanUndo);
  AssertFalse('no redo', acts.TeCanRedo);
  AssertFalse('no paste', acts.TeCanPaste);
  AssertTrue('text', acts.TeHasText);
  AssertFalse('no selection', acts.TeHasSelection);
  acts.TeSelectAll;
  AssertTrue('Select All', FRich.HasSelection);
  AssertTrue('a selection', acts.TeHasSelection);
  acts.TeCopy;
  AssertEquals('Copy', 'menu text', FRich.ClipText);
  acts.TeCut;
  acts.TePaste;
  acts.TeUndo;
  AssertEquals('the editing items change nothing', 'menu text', FRich.Lines[0]);
  AssertTrue('ours when there is none', FRich.PopupAt(5, 5));
  AssertEquals('shown', 1, FRich.MenuShows);
  pm := TPopupMenu.Create(nil);
  try
    FRich.PopupMenu := pm;
    AssertFalse('a user''s menu: left to LCL', FRich.PopupAt(5, 5));
    AssertEquals('ours not shown', 1, FRich.MenuShows);
    FRich.PopupMenu := nil;
  finally
    pm.Free;
  end;
  FRich.Lines.Text := '';
  AssertFalse('no text', acts.TeHasText);
end;

{ The input method is told the viewer is read-only, where the caret is (while focused) and its
  index; nothing it sends changes the text. }
procedure TTyRichEditControlTest.TestTheImeIsToldTheViewerIsReadOnly;
var
  ime: ITyImeEditable;
begin
  FRich.Lines.Text := 'ime text';
  FRich.UpdateView;
  ime := FRich as ITyImeEditable;
  // an editor since Task 10a: the viewer is ReadOnly (10b: the input method is told so)
  AssertFalse('an editor: not read-only', ime.ImeIsReadOnly);
  FRich.ReadOnly := True;
  AssertTrue('read-only', ime.ImeIsReadOnly);
  AssertTrue('the control', ime.ImeTargetControl = FRich);
  FRich.SelStart := 2;
  AssertEquals('the caret''s index', 2, ime.ImeCaretIndex);
  AssertTrue('not focused: no rectangle', IsRectEmpty(ime.ImeCaretBoundClient));
  FRich.ForceFocus := True;
  AssertTrue('focused: the caret''s', EqualRect(FRich.CaretClientRect, ime.ImeCaretBoundClient));
  ime.ImeSessionBegin;
  ime.ImeReplace(0, 1, 'x');
  ime.ImeSessionEnd;
  AssertEquals('the text as it was', 'ime text', FRich.Lines[0]);
end;

{ ---- fix wave W4 ---- }

type
  // How many paragraph values a document holds.
  TW4DocPeek = class(TTyRichDocument)
  public
    function Live: Integer;
  end;

  // A reader's way to set a paragraph (as the RTF reader sets one).
  TW4Put = class(TTyRichDocBuilder)
  public
    class function Put(ADoc: TTyRichDocument; AIndex: Integer; ACell: TTyRichCell): Boolean;
  end;

function TW4DocPeek.Live: Integer;
begin
  Result := LiveParaData;
end;

class function TW4Put.Put(ADoc: TTyRichDocument; AIndex: Integer; ACell: TTyRichCell): Boolean;
var
  runs: TTyRunArray;
begin
  runs := nil;
  SetLength(runs, 1);
  runs[0].Start := 0;
  runs[0].Format := ADoc.DefaultCharFormatId;
  runs[0].Obj := nil;
  Result := SetParagraph(ADoc, AIndex, ADoc.DefaultParaFormatId, runs, ACell);
end;

{ Two texts the same, or where they part. }
procedure AssertSameText(const AMsg, AExpected, AActual: string);
var
  i, n: Integer;
begin
  if AExpected = AActual then Exit;
  n := Min(Length(AExpected), Length(AActual));
  i := 1;
  while (i <= n) and (AExpected[i] = AActual[i]) do Inc(i);
  raise EAssertionFailedError.CreateFmt('%s: %d and %d bytes, apart from byte %d: <%s> / <%s>',
    [AMsg, Length(AExpected), Length(AActual), i, Copy(AExpected, Math.Max(1, i - 20), 60),
     Copy(AActual, Math.Max(1, i - 20), 60)]);
end;

{ Plain paragraphs and two-row tables (one row with a merged cell) up to ATarget bytes - the
  tables apart, so that intervals seldom chain through them. }
function W4TablesRtf(ATarget: Int64): TBytes;
var
  m: TMemoryStream;
  k: Integer;

  procedure Put(const S: RawByteString);
  begin
    if S <> '' then m.WriteBuffer(S[1], Length(S));
  end;

begin
  m := TMemoryStream.Create;
  try
    Put('{\rtf1\ansi\ansicpg936\deff0{\fonttbl{\f0\fnil\fcharset134 SimSun;}}' + #13#10 +
      '\pard\f0\fs24 ');
    k := 0;
    while m.Size < ATarget do
    begin
      Put('\pard before ' + IntToStr(k) + ' with \b bold\b0  words\par' + #13#10);
      Put('\pard a second plain paragraph of some length, ' + IntToStr(k) + '\par' + #13#10);
      Put('\trowd\trgaph108\cellx2400\cellx4800\cellx7200' + #13#10 + '\pard\intbl a' +
        IntToStr(k) + '\cell b\cell c\cell\row' + #13#10);
      Put('\trowd\trgaph108\clmgf\cellx2400\clmrg\cellx4800\cellx7200' + #13#10 +
        '\pard\intbl m\cell\pard\intbl\cell\pard\intbl z\cell\row' + #13#10);
      Put('\pard after ' + IntToStr(k) + '\par' + #13#10);
      Put('\pard and one more plain paragraph after the table\par' + #13#10);
      Inc(k);
    end;
    Put('\pard the end\par}');
    Result := nil;
    SetLength(Result, m.Size);
    Move(m.Memory^, Result[0], m.Size);
  finally
    m.Free;
  end;
end;

procedure TTyRichEditControlTest.EditInLastStep(Sender: TObject; ADone, ATotal: Int64;
  var ACancel: Boolean);
var
  d: TTyRichDocument;
  f: TTyCharFormat;
begin
  d := FRich.Document;
  // only where the load is over: the last step
  if d.Loading or (FLastStepEdits <> 0) then Exit;
  f := TyDefaultCharFormat;
  f.Style := [fsItalic];
  if d.Execute(TTyRichSetCharFormat.Create(TyRichRange(d.Text.ParaStart(1), 1), [cffItalic], f)) then
    FLastStepEdits := 1
  else
    FLastStepEdits := -1;
end;

{ W3r-M1: a change is the load's own only while a step runs AND the document still loads. A
  command run from the progress handler of the LAST step - the document no longer loads there -
  is an edit: a format change of the body paragraph after item "1." of Word's list lowers the
  trust, so item "2." below it is counted (after a body paragraph: "1."), while "1." above it
  stays the file's. The slices are still the load's: without the command, every slice keeps the
  file's numbers. }
procedure TTyRichEditControlTest.TestACommandFromTheLastStepsProgressIsAnEdit;
var
  st: TBytesStream;
  steps: Integer;

  function Marker(AIndex: Integer): string;
  var
    L: TTyBlockLayout;
  begin
    L := FRich.Layouter.LayoutBlock(FRich.Document, AIndex, 1000, 96, 1);
    try
      Result := string(TTyParaLayout(L).Marker.Text);
    finally
      L.Release;
    end;
  end;

  procedure Load(AEdit: Boolean);
  begin
    if AEdit then FRich.OnLoadProgress := @EditInLastStep else FRich.OnLoadProgress := nil;
    st := TBytesStream.Create(ReadFixtureFile('word-list.rtf'));
    try
      FRich.Slices(AfterPars(st.Bytes, 2), 256);
      FRich.LoadFromStream(st);
    finally
      st.Free;
    end;
    steps := 0;
    while FRich.Loading do
    begin
      AssertTrue('a step', FRich.Step);
      Inc(steps);
      AssertTrue('runaway', steps < 10000);
    end;
    AssertTrue(Format('in slices (%d)', [steps]), steps >= 5);
    AssertEquals('all of it', 11, FRich.Document.Text.ParaCount);
  end;

begin
  Load(False);
  AssertEquals('the load''s slices: item 1', '1.', Marker(0));
  AssertEquals('the load''s slices: item 2 the file''s', '2.', Marker(2));
  Load(True);
  AssertEquals('the command ran in the last step''s handler', 1, FLastStepEdits);
  AssertEquals('above the edit: the file''s', '1.', Marker(0));
  AssertEquals('below it: counted, as after any edit', '1.', Marker(2));
end;

{ R42: the plain text of a copy of a lazily read RTF that holds tables comes from one walk: the
  walk decodes each paragraph, and its cell comes from that decode (a value of the moment).
  The document parses no paragraph for it - it keeps no more values after the copy than before
  (the ends, which the copy reads to know its range, read first) - and the load parses an
  interval at most once. The text is the whole parse's. The file has more intervals than the
  load lets pile up, so intervals go during the walk - also the one of the row the walk is in
  (the copy holds the table it compares the next paragraph's cell with). Then every fixture
  read lazily copies the text it copies read whole. }
procedure TTyRichEditControlTest.TestAPlainCopyOfALazyRtfLeavesNothingParsed;
var
  b: TBytes;
  whole, lazy: string;
  d: TTyRichDocument;
  load: TTyRtfLoad;
  live0, parses0, files: Integer;
  sr: TSearchRec;

  procedure LoadAs(const ABytes: TBytes; AWhole: Boolean);
  var
    st: TBytesStream;
  begin
    st := TBytesStream.Create(ABytes);
    try
      if AWhole then TyRichLoadRtfFull(FRich.Document, st) else FRich.LoadFromStream(st);
    finally
      st.Free;
    end;
    FRich.FinishLoading;
  end;

begin
  b := W4TablesRtf(3 * 1024 * 1024);
  LoadAs(b, True);
  FRich.SelectAll;
  whole := FRich.SelText;
  AssertTrue('rows in it', Pos('m'#9#9'z' + LineEnding, whole) > 0);
  LoadAs(b, False);
  d := FRich.Document;
  load := TyRichRtfLoadOf(d);
  AssertTrue('read lazily', (load <> nil) and not load.Whole);
  AssertTrue(Format('more intervals (%d) than the load lets pile up', [load.IntervalCount]),
    load.IntervalCount > 2 * load.MaxResidentIntervals + 2);
  FRich.SelectAll;
  d.RunsOf(0);
  d.RunsOf(d.Text.ParaCount - 1);
  live0 := TW4DocPeek(d).Live;
  parses0 := load.ParseCount;
  lazy := FRich.SelText;
  AssertSameText('the whole parse''s text', whole, lazy);
  AssertTrue(Format('no value left behind: %d before, %d after', [live0, TW4DocPeek(d).Live]),
    TW4DocPeek(d).Live <= live0);
  AssertTrue(Format('an interval parsed at most once: %d parses, %d intervals',
    [load.ParseCount - parses0, load.IntervalCount]), load.ParseCount - parses0 <= load.IntervalCount);
  files := 0;
  if FindFirst(FixtureDir('rtf') + '*.rtf', faAnyFile, sr) = 0 then
  try
    repeat
      b := ReadFixtureFile(sr.Name);
      LoadAs(b, True);
      FRich.SelectAll;
      whole := FRich.SelText;
      LoadAs(b, False);
      FRich.SelectAll;
      AssertSameText(sr.Name, whole, FRich.SelText);
      Inc(files);
    until FindNext(sr) <> 0;
  finally
    FindClose(sr);
  end;
  AssertTrue(Format('the fixtures (%d)', [files]), files >= 12);
end;

{ 9b-C6: a range the RTF writer refuses - a part of a paragraph and a changed row that holds a
  nested table - is copied as its text with an empty RTF flavour: nothing raises out of the
  copy, and the wait cursor it showed is taken back. (The row is set the way a reader sets one.) }
procedure TTyRichEditControlTest.TestARefusedRtfFlavourCopiesTheTextAlone;
const
  Source = '{\rtf1\ansi\ansicpg1252\deff0{\fonttbl{\f0\fswiss\fcharset0 Arial;}}\uc1 ' +
    '\pard\f0\fs24 top\par \trowd\trgaph108\cellx2000\cellx4000 \pard\intbl a\cell b\cell\row ' +
    '\pard bottom\par}';
  RowWords = '\trowd\trgaph108\cellx2000\cellx4000';
var
  st: TBytesStream;
  d: TTyRichDocument;
  t: TTyRichTable;
  ms: TMemoryStream;
  refused: Boolean;
  text: string;
begin
  st := TBytesStream.Create(BytesOf(Source));
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  FRich.FinishLoading;
  d := FRich.Document;
  AssertEquals('four paragraphs', 4, d.Text.ParaCount);
  t := TTyRichTable.Create([2000, 4000]);
  t.AddRow(2, RowWords, [2000, 4000], True);
  AssertTrue('the first cell is set', TW4Put.Put(d, 1, t.Rows[0].Cells[0]));
  AssertTrue('the second cell is set', TW4Put.Put(d, 2, t.Rows[0].Cells[1]));
  // from inside "top" into "b"
  FRich.SelStart := 1;
  FRich.SelLength := d.Text.ParaStart(2) + 1 - 1;
  refused := False;
  ms := TMemoryStream.Create;
  try
    try
      TyRichSaveRtfRange(d, ms, FRich.SelStart, FRich.SelLength);
    except
      on ETyRichRtfWrite do refused := True;
    end;
  finally
    ms.Free;
  end;
  AssertTrue('the writer refuses the range', refused);
  text := FRich.SelText;
  AssertTrue('the row in the text: ' + text, Pos('a'#9'b', text) > 0);
  FRich.SetCopyWait(1);
  FRich.CopyToClipboard;
  AssertEquals('one write', 1, FRich.ClipWrites);
  AssertEquals('the text', text, FRich.ClipText);
  AssertTrue('no RTF flavour', FRich.ClipRtf = '');
  AssertEquals('the wait cursor', 1, FRich.Waits);
  AssertEquals('and back', 1, FRich.WaitEnds);
  // W5: inside the one cell "b" no row is written - both flavours
  FRich.SelStart := d.Text.ParaStart(2);
  FRich.SelLength := 1;
  FRich.CopyToClipboard;
  AssertEquals('inside one cell: the text', 'b', FRich.ClipText);
  AssertEquals('inside one cell: an RTF flavour', 1, Pos('{\rtf1', FRich.ClipRtf));
end;

{ ---- fix wave W5 ---- }

{ A copy's RTF flavour read whole; nil for none. }
function ReadClipRtf(const ARtf: RawByteString): TTyRichDocument;
var
  st: TBytesStream;
begin
  Result := nil;
  if ARtf = '' then Exit;
  Result := TTyRichDocument.Create;
  st := TBytesStream.Create(BytesOf(ARtf));
  try
    TyRichLoadRtfFull(Result, st);
  finally
    st.Free;
  end;
end;

{ The text of a document's paragraphs, parted by the line break the plain text uses. }
function ParasText(ADoc: TTyRichDocument): string;
var
  k: Integer;
  s: RawByteString;
begin
  s := '';
  for k := 0 to ADoc.Text.ParaCount - 1 do
  begin
    if k > 0 then s := s + LineEnding;
    s := s + ADoc.Text.GetText(ADoc.Text.ParaStart(k), ADoc.Text.ParaLength(k));
  end;
  SetCodePage(s, CP_UTF8, False);
  Result := s;
end;

{ Whether a copy's RTF ends with a paragraph's end - what pasting it adds after its text: a
  group with a letter put in before its closing brace is a paragraph of its own after a \par,
  and joins the last paragraph without one. }
function ClipRtfEndsWithBreak(const ARtf: RawByteString): Boolean;
var
  i: Integer;
  a, b: TTyRichDocument;
begin
  i := Length(ARtf);
  while (i > 0) and (ARtf[i] <> '}') do Dec(i);
  a := ReadClipRtf(ARtf);
  b := nil;
  try
    b := ReadClipRtf(Copy(ARtf, 1, i - 1) + '{Z}' + Copy(ARtf, i, MaxInt));
    Result := b.Text.ParaCount > a.Text.ParaCount;
  finally
    b.Free;
    a.Free;
  end;
end;

{ W5 C-I2: the plain text counts characters by the text storage's rule (strict UTF-8: an
  overlong form, a surrogate written in UTF-8 as CESU-8 does, a sequence above U+10FFFF are
  bytes of their own), so it cuts where the selection is - and where the RTF flavour cuts. }
procedure TTyRichEditControlTest.TestThePlainTextCountsCharactersAsTheStorage;
var
  fffd: RawByteString;

  procedure Check(const AWhat: string; const ABytes: RawByteString; AChars: Integer;
    AValid: Boolean = False);
  var
    st: TBytesStream;
    b: TTyRichDocument;
    all: RawByteString;
    expected: string;
    k: Integer;
  begin
    // a UTF-8 file with a BOM: kept as its bytes, a byte that is no text a character
    st := TBytesStream.Create(BytesOf(#$EF#$BB#$BF'x' + ABytes + 'yz'));
    try
      FRich.LoadFromStream(st, rfText);
    finally
      st.Free;
    end;
    AssertEquals(AWhat + ': characters', 1 + AChars + 2, FRich.Document.Text.Length);
    FRich.SelStart := 1 + AChars;
    FRich.SelLength := 2;
    AssertEquals(AWhat + ': the selection', 'yz', FRich.SelText);
    FRich.CopyToClipboard;
    AssertEquals(AWhat + ': the copy''s text', 'yz', FRich.ClipText);
    b := ReadClipRtf(FRich.ClipRtf);
    try
      AssertEquals(AWhat + ': the RTF''s text', 'yz', ParasText(b));
    finally
      b.Free;
    end;
    // all of it: each byte one U+FFFD, in both flavours alike
    FRich.SelectAll;
    FRich.CopyToClipboard;
    all := 'x';
    if AValid then all := all + ABytes
    else
      for k := 1 to AChars do all := all + fffd;
    all := all + 'yz';
    SetCodePage(all, CP_UTF8, False);
    expected := all;
    AssertEquals(AWhat + ': all', expected, FRich.ClipText);
    b := ReadClipRtf(FRich.ClipRtf);
    try
      AssertEquals(AWhat + ': all, the two flavours', FRich.ClipText, ParasText(b));
    finally
      b.Free;
    end;
  end;

begin
  fffd := Utf8Of($FFFD);
  Check('a surrogate (CESU-8)', #$ED#$A0#$80, 3);
  Check('an overlong form', #$E0#$80#$80, 3);
  Check('above U+10FFFF', #$F4#$90#$80#$80, 4);
  Check('an overlong of four', #$F0#$80#$80#$80, 4);
  // a valid one is one character still
  Check('a valid one', Utf8Of($4E2D), 1, True);
end;

{ W5 C-M1: Word's table with a nested one, unchanged: a selection inside a cell of the row
  that holds the nested table copies both flavours (no row is written), and the RTF reads back
  as its text. }
procedure TTyRichEditControlTest.TestACopyInsideACellOfANestedRowHasBothFlavours;
var
  st: TBytesStream;
  d, b: TTyRichDocument;
  k, met: Integer;
  c: TTyRichCell;
begin
  st := TBytesStream.Create(ReadFixtureFile('word-table-merged.rtf'));
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  FRich.FinishLoading;
  d := FRich.Document;
  met := 0;
  for k := 0 to d.Text.ParaCount - 1 do
  begin
    c := d.CellAt(k);
    if (c = nil) or not c.Row.HoldsNestedTable or (d.Text.ParaLength(k) = 0) then Continue;
    FRich.SelStart := d.Text.ParaStart(k);
    FRich.SelLength := d.Text.ParaLength(k);
    FRich.CopyToClipboard;
    AssertEquals(Format('paragraph %d: the text', [k]), FRich.SelText, FRich.ClipText);
    AssertEquals(Format('paragraph %d: an RTF flavour', [k]), 1, Pos('{\rtf1', FRich.ClipRtf));
    b := ReadClipRtf(FRich.ClipRtf);
    try
      AssertEquals(Format('paragraph %d: read back, one paragraph', [k]), 1, b.Text.ParaCount);
      AssertEquals(Format('paragraph %d: read back, its text', [k]), FRich.ClipText, ParasText(b));
    finally
      b.Free;
    end;
    Inc(met);
  end;
  AssertTrue(Format('paragraphs in such a row (%d)', [met]), met >= 2);
end;

{ W5 C-M3: a length past the end - High(Int64) the furthest - gives the text to the end. }
procedure TTyRichEditControlTest.TestAHugeLengthGivesTheTextToTheEnd;
begin
  FRich.Lines.Text := 'ab'#10'cd';
  AssertEquals('from the second character', 'b' + LineEnding + 'cd', FRich.RangeText(1, High(Int64)));
  AssertEquals('all', 'ab' + LineEnding + 'cd', FRich.RangeText(0, High(Int64)));
  AssertEquals('from the end: nothing', '', FRich.RangeText(FRich.Document.Text.Length, High(Int64)));
end;

{ W5 C-M4: a cell the model left without a paragraph (its only one deleted) keeps its tab in
  the plain text - before the row's first paragraph and after its last, as between two. }
procedure TTyRichEditControlTest.TestCellsWithoutAParagraphGiveTheirTabs;
const
  RowDef = '\trowd\trgaph108\cellx1000\cellx2000\cellx3000 ';
  Source = '{\rtf1\ansi\deff0{\fonttbl{\f0 Arial;}}\uc1 \pard\f0\fs24 top\par ' +
    RowDef + '\pard\intbl a\cell b\cell c\cell\row ' +
    RowDef + '\pard\intbl d\cell e\cell f\cell\row \pard bottom\par}';

  procedure Check(const AWhat: string; AFirst, ALast: Integer; const AText: string);
  var
    t: TTyRichText;
  begin
    LoadRtfText(Source);
    t := FRich.Document.Text;
    AssertEquals(AWhat + ': eight paragraphs', 8, t.ParaCount);
    AssertTrue(AWhat + ': deleted', FRich.Document.Execute(TTyRichDelete.Create(t.ParaStart(AFirst),
      t.ParaStart(ALast + 1) - t.ParaStart(AFirst))));
    FRich.SelectAll;
    AssertEquals(AWhat, AText, FRich.SelText);
  end;

begin
  Check('the first cell''s paragraph gone', 1, 1, 'top' + LineEnding + #9'b'#9'c' + LineEnding +
    'd'#9'e'#9'f' + LineEnding + 'bottom');
  Check('the last cell''s paragraph gone', 6, 6, 'top' + LineEnding + 'a'#9'b'#9'c' + LineEnding +
    'd'#9'e'#9 + LineEnding + 'bottom');
  Check('the first two gone', 1, 2, 'top' + LineEnding + #9#9'c' + LineEnding +
    'd'#9'e'#9'f' + LineEnding + 'bottom');
  // a range that starts in the row takes it whole, its empty first cell too
  Check('the first gone, again', 1, 1, 'top' + LineEnding + #9'b'#9'c' + LineEnding +
    'd'#9'e'#9'f' + LineEnding + 'bottom');
  FRich.SelStart := FRich.Document.Text.ParaStart(2);
  FRich.SelLength := FRich.Document.Text.ParaStart(3) + 1 - FRich.SelStart;
  AssertEquals('from c into d: the rows whole', #9'b'#9'c' + LineEnding + 'd'#9'e'#9'f' + LineEnding,
    FRich.SelText);
end;

{ A plain RTF of ACount paragraphs; AFirstSlice: the byte after the 50th. }
function W5PlainRtf(ACount: Integer; out AAfter50: Int64): TBytes;
var
  m: TMemoryStream;
  k: Integer;
  s: RawByteString;
begin
  m := TMemoryStream.Create;
  try
    s := '{\rtf1\ansi\deff0{\fonttbl{\f0 Arial;}}' + #13#10 + '\pard\f0\fs20 ';
    m.WriteBuffer(s[1], Length(s));
    AAfter50 := 0;
    for k := 0 to ACount - 1 do
    begin
      s := '\pard Paragraph ' + IntToStr(k) + ' with \b bold\b0  words in it.\par' + #13#10;
      m.WriteBuffer(s[1], Length(s));
      if k = 49 then AAfter50 := m.Size;
    end;
    s := '}';
    m.WriteBuffer(s[1], 1);
    Result := nil;
    SetLength(Result, m.Size);
    Move(m.Memory^, Result[0], m.Size);
  finally
    m.Free;
  end;
end;

{ W5 C-M5: a copy while the load is still going on, and after it was cancelled (Incomplete):
  Select All takes the last paragraph appended so far, which has no separator in the text yet:
  the text ends without a line break (R45), the RTF with that paragraph's \par (R64, fix wave
  W14: a last paragraph taken whole is a paragraph with its format); a paragraph taken with its
  separator ends with both. }
procedure TTyRichEditControlTest.TestACopyWhileLoadingAndAfterACancel;
var
  src: TBytes;
  first: Int64;
  st: TBytesStream;

  procedure Check(const AWhat: string);
  var
    t: TTyRichText;
    n: Integer;
    b: TTyRichDocument;
  begin
    t := FRich.Document.Text;
    n := t.ParaCount;
    AssertTrue(Format('%s: some paragraphs (%d)', [AWhat, n]), n > 3);
    FRich.SelectAll;
    FRich.CopyToClipboard;
    AssertEquals(AWhat + ': the text is SelText', FRich.SelText, FRich.ClipText);
    AssertTrue(AWhat + ': all - no line break at the end',
      Copy(FRich.ClipText, Length(FRich.ClipText) - Length(LineEnding) + 1, MaxInt) <> LineEnding);
    // (the last paragraph taken whole: the RTF ends it with \par all the same - R64)
    AssertTrue(AWhat + ': all - a paragraph''s end in the RTF', ClipRtfEndsWithBreak(FRich.ClipRtf));
    b := ReadClipRtf(FRich.ClipRtf);
    try
      AssertEquals(AWhat + ': all - the RTF''s text', FRich.ClipText, ParasText(b));
    finally
      b.Free;
    end;
    FRich.SelStart := t.ParaStart(n - 2);
    FRich.SelLength := t.ParaLength(n - 2) + 1;
    FRich.CopyToClipboard;
    AssertTrue(AWhat + ': with its separator - a line break at the end',
      Copy(FRich.ClipText, Length(FRich.ClipText) - Length(LineEnding) + 1, MaxInt) = LineEnding);
    AssertTrue(AWhat + ': with its separator - a paragraph''s end in the RTF',
      ClipRtfEndsWithBreak(FRich.ClipRtf));
  end;

begin
  src := W5PlainRtf(3000, first);
  FRich.Slices(first, 16 * 1024);
  st := TBytesStream.Create(src);
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  AssertTrue('loading', FRich.Loading);
  Check('the first slice');
  AssertTrue('a step', FRich.Step);
  AssertTrue('loading still', FRich.Loading);
  Check('a step later');
  FRich.CancelLoad;
  AssertTrue('incomplete', FRich.Document.Incomplete);
  Check('cancelled');
end;

var
  GPoisonOld: TMemoryManager;
  GPoisoned: Integer;

{ A release with the freed block filled with $A5 first: a read of freed memory then finds no
  pointer it held (dereferenced: an access violation), whatever the heap does with it next. }
function PoisonFreeMem(P: Pointer): PtrUInt;
begin
  if P <> nil then
  begin
    FillChar(P^, GPoisonOld.MemSize(P), $A5);
    InterLockedIncrement(GPoisoned);
  end;
  Result := GPoisonOld.FreeMem(P);
end;

function PoisonFreeMemSize(P: Pointer; ASize: PtrUInt): PtrUInt;
begin
  if P <> nil then
  begin
    FillChar(P^, GPoisonOld.MemSize(P), $A5);
    InterLockedIncrement(GPoisoned);
  end;
  Result := GPoisonOld.FreeMemSize(P, ASize);
end;

procedure PoisonFreedMemory(AOn: Boolean);
var
  mm: TMemoryManager;
begin
  if AOn then
  begin
    GetMemoryManager(GPoisonOld);
    mm := GPoisonOld;
    mm.FreeMem := @PoisonFreeMem;
    mm.FreeMemSize := @PoisonFreeMemSize;
    GPoisoned := 0;
    SetMemoryManager(mm);
  end
  else
    SetMemoryManager(GPoisonOld);
end;

{ W5 C-X1: the plain text compares a paragraph's cell with the one before it after the walk
  let the value of the moment of that one go - and with it, when its interval went too, the
  table its cell is in: the copy holds that table meanwhile. Freed memory is filled with a
  pattern during the copy (a test's release), so a cell read after its table was freed reads
  no row it had - the text would part the row's cells by line breaks, or the read would fault.
  The file is the R42 test's: more intervals than the load keeps, rows in all of them. }
procedure TTyRichEditControlTest.TestTheRowBeforeIsHeldWhileTheNextIsCompared;
var
  b: TBytes;
  whole, lazy: string;
  st: TBytesStream;
  load: TTyRtfLoad;
  keep: Integer;
begin
  b := W4TablesRtf(3 * 1024 * 1024);
  st := TBytesStream.Create(b);
  try
    TyRichLoadRtfFull(FRich.Document, st);
  finally
    st.Free;
  end;
  FRich.SelectAll;
  whole := FRich.SelText;
  st := TBytesStream.Create(b);
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  FRich.FinishLoading;
  load := TyRichRtfLoadOf(FRich.Document);
  AssertTrue('read lazily', (load <> nil) and not load.Whole);
  AssertTrue('intervals go during the copy', load.IntervalCount > 2 * load.MaxResidentIntervals + 2);
  FRich.SelectAll;
  // none kept: the group of the paragraph before goes as soon as the walk decodes one of
  // the next group - and with it the table of a row that ends the group
  keep := load.MaxResidentIntervals;
  load.MaxResidentIntervals := 0;
  PoisonFreedMemory(True);
  try
    lazy := FRich.SelText;
  finally
    PoisonFreedMemory(False);
    load.MaxResidentIntervals := keep;
  end;
  AssertTrue(Format('the copy freed memory (%d blocks)', [GPoisoned]), GPoisoned > 0);
  AssertSameText('the whole parse''s text, with freed memory filled', whole, lazy);
end;

{ W5 C-X2: a table of more than a megabyte read on demand is parsed in parts, a table object
  for each interval's stretch of it (the parts are cut where the index scan took a snapshot,
  which is never inside a row). The plain text of all of it, and of a range across the seam
  of two parts, is the whole parse's; the range's RTF reads back as that text. Rows whose first
  cell holds two paragraphs are among them. }
procedure TTyRichEditControlTest.TestABigTableReadInPartsCopiesAsAWhole;
var
  m: TMemoryStream;
  src: TBytes;
  k, seams, seam: Integer;
  st: TBytesStream;
  d, b: TTyRichDocument;
  c0, c1: TTyRichCell;
  wholeAll, wholeRange: string;
  s0, n0: TTyRichPos;
  R: TTyRichCopyRange;

  procedure Put(const S: RawByteString);
  begin
    if S <> '' then m.WriteBuffer(S[1], Length(S));
  end;

  procedure LoadAs(AWhole: Boolean);
  begin
    st := TBytesStream.Create(src);
    try
      if AWhole then TyRichLoadRtfFull(FRich.Document, st) else FRich.LoadFromStream(st);
    finally
      st.Free;
    end;
    FRich.FinishLoading;
  end;

begin
  m := TMemoryStream.Create;
  try
    Put('{\rtf1\ansi\deff0{\fonttbl{\f0 Arial;}}' + #13#10 + '\pard\f0\fs20 before\par' + #13#10);
    k := 0;
    while m.Size < 3 * 1024 * 1024 div 2 do
    begin
      if k mod 3 = 0 then
        Put('\trowd\trgaph108\cellx2400\cellx4800\cellx7200' + #13#10 + '\pard\intbl first ' +
          IntToStr(k) + '\par second\cell b\cell c\cell\row' + #13#10)
      else
        Put('\trowd\trgaph108\cellx2400\cellx4800\cellx7200' + #13#10 + '\pard\intbl a' +
          IntToStr(k) + '\cell b\cell c\cell\row' + #13#10);
      Inc(k);
    end;
    Put('\pard after\par}');
    SetLength(src, m.Size);
    Move(m.Memory^, src[0], m.Size);
  finally
    m.Free;
  end;
  LoadAs(True);
  FRich.SelectAll;
  wholeAll := FRich.SelText;
  // (two paragraphs of one cell: a line break between them, no tab)
  AssertTrue('a first cell of two paragraphs', Pos(LineEnding + 'first 0' + LineEnding +
    'second'#9'b'#9'c' + LineEnding + 'a1'#9'b'#9'c' + LineEnding, wholeAll) > 0);
  LoadAs(False);
  d := FRich.Document;
  // the seams: a paragraph whose cell is in another table object than the one before
  seams := 0;
  seam := -1;
  c0 := nil;
  for k := 0 to d.Text.ParaCount - 1 do
  begin
    c1 := d.CellAt(k);
    if (c0 <> nil) and (c1 <> nil) and (c0.Table <> c1.Table) then
    begin
      Inc(seams);
      if seam < 0 then seam := k;
      AssertTrue(Format('paragraph %d: a part begins with a row', [k]), c1.Index = 0);
      AssertTrue(Format('paragraph %d: the part before ends with its row', [k]),
        c0.Index = c0.Row.CellCount - 1);
    end;
    c0 := c1;
  end;
  AssertTrue(Format('the table in parts (%d seams)', [seams]), seams >= 2);
  FRich.SelectAll;
  AssertSameText('all of it, read on demand', wholeAll, FRich.SelText);
  // from inside the last row of a part into the first row of the next
  s0 := d.Text.ParaStart(seam - 1) + 1;
  n0 := d.Text.ParaStart(seam) + 1 - s0;
  FRich.SelStart := s0;
  FRich.SelLength := n0;
  FRich.CopyToClipboard;
  AssertEquals('the copy''s text is SelText', FRich.SelText, FRich.ClipText);
  AssertTrue('two rows: ' + FRich.ClipText, Pos(#9'c' + LineEnding, FRich.ClipText) > 0);
  R := TyRichCopyRange(d, s0, n0);
  AssertTrue('the range: two rows across the seam', (R.FirstPara < seam) and (R.LastPara >= seam));
  b := ReadClipRtf(FRich.ClipRtf);
  try
    AssertTrue('an RTF flavour', b <> nil);
    AssertEquals('the RTF''s rows read back', R.LastPara - R.FirstPara + 1, b.Text.ParaCount);
    AssertTrue('in a table', (b.CellAt(0) <> nil) and (b.CellAt(b.Text.ParaCount - 1) <> nil));
    AssertTrue('one table', b.CellAt(0).Table = b.CellAt(b.Text.ParaCount - 1).Table);
  finally
    b.Free;
  end;
  wholeRange := FRich.ClipText;
  LoadAs(True);
  FRich.SelStart := s0;
  FRich.SelLength := n0;
  AssertSameText('the range, as the whole parse gives it', FRich.SelText, wholeRange);
end;

{ ---- fix wave W6 ---- }

{ S-I2 / S-M3: a press on a picture selects it, and it stays selected while the pointer moves
  on it - its left half or its right half; a drag out of it extends from it; a double click on
  its right half selects it (the object under the pointer is the word). }
procedure TTyRichEditControlTest.TestAPressOnAnObjectKeepsItSelected;
var
  r1, r2: TRect;
  y, left, right: Integer;
  p: TPoint;
begin
  PictureDoc(1);
  PaintAll(True);
  r1 := FRich.PositionRect(1);
  r2 := FRich.PositionRect(2);
  AssertTrue('the picture is wide', r2.Left - r1.Left > 10);
  y := (r1.Top + r1.Bottom) div 2;
  left := r1.Left + 3;
  right := r2.Left - 3;
  FRich.PressAt(left, y);
  AssertEquals('pressed: the picture', Int64(1), FRich.SelStart);
  AssertEquals('pressed: its character', Int64(1), FRich.SelLength);
  FRich.MoveAt(left + 2, y);
  AssertEquals('a move inside the left half: still the picture', Int64(1), FRich.SelLength);
  AssertEquals('from its start', Int64(1), FRich.SelStart);
  FRich.MoveAt(right, y);
  AssertEquals('a move inside the right half: still the picture', Int64(1), FRich.SelLength);
  AssertEquals('from its start, again', Int64(1), FRich.SelStart);
  FRich.ReleaseAt(right, y);
  AssertEquals('released: the picture', Int64(1), FRich.SelLength);
  // pressed on its right half, a small move
  FRich.PressAt(right, y);
  FRich.MoveAt(right - 2, y);
  FRich.ReleaseAt(right - 2, y);
  AssertEquals('the right half: the picture', Int64(1), FRich.SelStart);
  AssertEquals('the right half: its character', Int64(1), FRich.SelLength);
  // a drag out of it, right and left: from the picture
  p := At(3);
  FRich.PressAt(left, y);
  FRich.MoveAt(p.X + 2, p.Y);
  AssertEquals('dragged right: from the picture''s start', Int64(1), FRich.SelStart);
  AssertTrue('dragged right: past it', FRich.SelLength >= 2);
  p := At(0);
  FRich.MoveAt(p.X, p.Y);
  AssertEquals('dragged left: to the letter', Int64(0), FRich.SelStart);
  AssertEquals('dragged left: from the picture''s end', Int64(2), FRich.SelLength);
  FRich.ReleaseAt(p.X, p.Y);
  // a double click on its right half: the picture, not the word after it
  Click(At(0));
  FRich.PressAt(right, y);
  FRich.ReleaseAt(right, y);
  FRich.PressAt(right, y, [ssDouble]);
  FRich.ReleaseAt(right, y);
  AssertEquals('double click on the right half: the picture', Int64(1), FRich.SelStart);
  AssertEquals('double click on the right half: its character', Int64(1), FRich.SelLength);
end;

{ S-I3: Down out of a paragraph whose picture is taller than two views (the block after it is
  not held), and out of a row whose short cell stands beside two screens of text; Up back
  into the picture's paragraph; PgDn across the picture. }
procedure TTyRichEditControlTest.TestDownLeavesATallPictureAndATallRow;
var
  pic: TTyRichPicture;
  t: TTyRichText;
  i: Integer;
  s: string;
  r, a: TRect;
begin
  FRich.Lines.Text := 'a b'#10'after the picture';
  pic := TTyRichPicture.Create(rpfPng, PngBytes(20, 200, BGRA(0, 0, 200, 255)), 300, 10000);
  AssertTrue('a picture', FRich.Document.Execute(TTyRichInsertObject.Create(1, pic)));
  PaintAll(True);
  t := FRich.Document.Text;
  a := FRich.Area;
  AssertTrue(Format('the picture''s paragraph is taller than two views (%d)',
    [FRich.VisibleBlocks[0].Height]), FRich.VisibleBlocks[0].Height > 2 * (a.Bottom - a.Top));
  AssertEquals('only its block held', 1, FRich.VisibleBlockCount);
  FRich.SelStart := 0;
  FRich.Press(VK_DOWN, []);
  AssertEquals('Down leaves the picture''s paragraph', 1, t.ParaOfPos(FRich.CaretIndex));
  r := FRich.CaretClientRect;
  AssertTrue('and shows the caret', (r.Bottom > r.Top) and (r.Top >= a.Top) and (r.Bottom <= a.Bottom));
  FRich.Press(VK_UP, []);
  AssertEquals('Up comes back into it', 0, t.ParaOfPos(FRich.CaretIndex));
  FRich.SelStart := 0;
  i := 0;
  while (t.ParaOfPos(FRich.CaretIndex) = 0) and (i < 5) do
  begin
    FRich.Press(VK_NEXT, []);
    Inc(i);
  end;
  AssertEquals('PgDn crosses it', 1, t.ParaOfPos(FRich.CaretIndex));
  // a short cell beside two screens of text
  s := '{\rtf1\ansi\deff0{\fonttbl{\f0 Arial;}}\trowd\cellx1500\cellx4000\pard\intbl label\cell';
  for i := 1 to 40 do s := s + '\pard\intbl line ' + IntToStr(i) + '\par';
  s := s + '\pard\intbl last\cell\row\pard after the row\par}';
  LoadRtfText(s);
  PaintAll(True);
  t := FRich.Document.Text;
  FRich.SelStart := 1;
  FRich.Press(VK_DOWN, []);
  AssertEquals('Down from the short cell leaves the row', t.ParaCount - 1,
    t.ParaOfPos(FRich.CaretIndex));
  r := FRich.CaretClientRect;
  a := FRich.Area;
  AssertTrue('and shows the caret', (r.Bottom > r.Top) and (r.Top >= a.Top) and (r.Bottom <= a.Bottom));
end;

{ S-I4: a cut paragraph (one longer than CRichMaxParaLayoutChars - the cap has no seam: a real
  one) - a word step never ends in its hidden tail: Ctrl+Right at the cut goes to the next
  paragraph, Ctrl+Left from there to the cut, Shift+Ctrl+Right stops at the cut (a copy takes
  no tail) and then goes on to the next paragraph; End and a click past the end stay at the
  cut; Ctrl+End and a collapse of Select All at a document's cut end stop at the cut. }
procedure TTyRichEditControlTest.TestWordStepsStayOutOfACutParagraphsTail;
var
  big: string;
  i: Integer;
  t: TTyRichText;
  cut, next, start: TTyRichPos;
  r: TRect;
begin
  SetLength(big, 150000);
  for i := 1 to Length(big) do
    if i mod 5 = 0 then big[i] := ' ' else big[i] := 'w';
  FRich.Lines.Text := big + LineEnding + 'next line';
  FRich.UpdateView;
  t := FRich.Document.Text;
  AssertTrue('cut', FRich.VisibleBlocks[0].Layout.Truncated);
  cut := FRich.VisibleBlocks[0].Layout.LastCaretPos;
  AssertTrue(Format('the cut is a word''s start (%d)', [cut]), cut mod 5 = 0);
  next := t.ParaStart(1);
  FRich.SelStart := cut;
  FRich.Press(VK_RIGHT, [ssCtrl]);
  AssertEquals('Ctrl+Right at the cut: the next paragraph', next, FRich.CaretIndex);
  FRich.Press(VK_LEFT, [ssCtrl]);
  AssertEquals('Ctrl+Left from there: the cut', cut, FRich.CaretIndex);
  FRich.SelStart := cut - 20;
  start := FRich.SelStart;
  i := 0;
  while (FRich.CaretIndex < cut) and (i < 20) do
  begin
    FRich.Press(VK_RIGHT, [ssShift, ssCtrl]);
    Inc(i);
  end;
  AssertEquals('Shift+Ctrl+Right stops at the cut', cut, FRich.CaretIndex);
  FRich.CopyToClipboard;
  AssertEquals('a copy takes no tail', cut - start, Int64(Length(FRich.ClipText)));
  FRich.Press(VK_RIGHT, [ssShift, ssCtrl]);
  AssertEquals('one more: the next paragraph''s start', next, FRich.CaretIndex);
  FRich.SelStart := cut - 3;
  FRich.Press(VK_END, []);
  AssertEquals('End: the cut', cut, FRich.CaretIndex);
  r := FRich.CaretClientRect;
  Click(Point(FRich.Width - 1, (r.Top + r.Bottom) div 2));
  AssertEquals('a click past the end: the cut', cut, FRich.CaretIndex);
  // a document that ends with a cut paragraph
  FRich.Lines.Text := big;
  FRich.UpdateView;
  t := FRich.Document.Text;
  cut := FRich.VisibleBlocks[0].Layout.LastCaretPos;
  FRich.Press(VK_END, [ssCtrl]);
  AssertEquals('Ctrl+End: the cut', cut, FRich.CaretIndex);
  FRich.Press(VK_RIGHT, [ssCtrl]);
  AssertEquals('Ctrl+Right at the document''s cut: stays', cut, FRich.CaretIndex);
  FRich.SelectAll;
  AssertEquals('Select All takes the tail', t.Length, FRich.SelLength);
  FRich.Press(VK_RIGHT, []);
  AssertEquals('Right collapses at the cut', cut, FRich.CaretIndex);
end;

procedure TTyRichEditControlTest.RunAtScaleTwo(const AWhat: string; ACase: TRunMethod);
begin
  FreeAndNil(FRich);
  FRich := NewProbe;
  TyForceDeviceScaleForTest(2, True, False);
  FPaintScale := 2;
  FRich.Lines.Text := 'x';
  PaintAll(True);
  AssertEquals(AWhat + ': at scale 2', 2, FRich.Scale);
  try
    ACase();
  except
    on E: Exception do
      raise EAssertionFailedError.Create(AWhat + ' at scale 2: ' + E.Message);
  end;
  AssertEquals(AWhat + ': still at scale 2', 2, FRich.Scale);
end;

{ S-I5: the caret and selection tests that turn on hit points and pixels, laid out at device
  scale 2 (the forced scale is restored in TearDown). }
procedure TTyRichEditControlTest.TestTheCaretTestsAtScaleTwo;
begin
  RunAtScaleTwo('Up and Down', @TestUpAndDownKeepTheWishedXAndCrossATable);
  RunAtScaleTwo('word and paragraph drags', @TestWordAndParagraphSelectionAndTheirDrags);
  RunAtScaleTwo('a drag outside', @TestADragOutsideScrollsAndSelects);
  RunAtScaleTwo('scrolled into view', @TestTheCaretIsScrolledIntoViewByTheLeastAmount);
  RunAtScaleTwo('a selection''s bands', @TestASelectionChangeRepaintsOnlyItsLines);
  RunAtScaleTwo('a click on an object', @TestAClickOnAnObjectSelectsIt);
  RunAtScaleTwo('a press on an object', @TestAPressOnAnObjectKeepsItSelected);
  RunAtScaleTwo('the cursor and a right click', @TestTheCursorAndARightClick);
  RunAtScaleTwo('a tall picture and row', @TestDownLeavesATallPictureAndATallRow);
  RunAtScaleTwo('PgUp and PgDn', @TestPageUpAndPageDownMoveTheCaret);
  RunAtScaleTwo('across', @TestTheCaretIsScrolledAcross);
end;

{ S-I5: PgDn scrolls a page and the caret keeps its x and its place in the view; Shift extends;
  where the view cannot move (an end) the caret goes the page itself, to the last or first
  line. }
procedure TTyRichEditControlTest.TestPageUpAndPageDownMoveTheCaret;
var
  t: TTyRichText;
  r0, r1: TRect;
  est: Integer;
  a: TTyRichPos;
begin
  SetLinesOf(300, 'Line ');
  FRich.UpdateView;
  t := FRich.Document.Text;
  est := FRich.Layouter.EstimatedParaHeight(96, 1);
  FRich.SelStart := t.ParaStart(2) + 3;
  r0 := FRich.CaretClientRect;
  FRich.Press(VK_NEXT, []);
  r1 := FRich.CaretClientRect;
  AssertTrue('the view scrolled', FRich.ScrollY > 0);
  AssertTrue(Format('the caret keeps its place in the view (%d, %d)', [r0.Top, r1.Top]),
    Abs(r1.Top - r0.Top) < est);
  AssertEquals('and its x', r0.Left, r1.Left);
  AssertTrue(Format('a page further (%d)', [t.ParaOfPos(FRich.CaretIndex)]),
    t.ParaOfPos(FRich.CaretIndex) >= 2 + ScreenLines - 3);
  FRich.Press(VK_PRIOR, []);
  AssertEquals('PgUp: back', Int64(t.ParaStart(2) + 3), FRich.CaretIndex);
  a := FRich.CaretIndex;
  FRich.Press(VK_NEXT, [ssShift]);
  AssertEquals('Shift+PgDn: from the anchor', a, FRich.SelStart);
  AssertTrue('Shift+PgDn: a page of it', FRich.SelLength > 0);
  // at the end: the last line
  FRich.Press(VK_END, [ssCtrl]);
  FRich.Press(VK_UP, []);
  FRich.Press(VK_UP, []);
  FRich.Press(VK_UP, []);
  AssertEquals('three lines up', 296, t.ParaOfPos(FRich.CaretIndex));
  FRich.Press(VK_NEXT, []);
  AssertEquals('PgDn at the end: the last line', 299, t.ParaOfPos(FRich.CaretIndex));
  // at the top: the first line
  FRich.Press(VK_HOME, [ssCtrl]);
  FRich.Press(VK_DOWN, []);
  FRich.Press(VK_DOWN, []);
  FRich.Press(VK_PRIOR, []);
  AssertEquals('PgUp at the top: the first line', 0, t.ParaOfPos(FRich.CaretIndex));
end;

{ S-I5: the caret is scrolled into view across, with no wrapping and in page mode. }
procedure TTyRichEditControlTest.TestTheCaretIsScrolledAcross;
var
  s: string;
  i: Integer;
  r, tw: TRect;
begin
  s := '';
  for i := 1 to 100 do s := s + 'word ';
  FRich.WrapMode := rwmNone;
  FRich.Lines.Text := s + LineEnding + 'short';
  FRich.UpdateView;
  FRich.SelStart := 0;
  FRich.Press(VK_END, []);
  AssertTrue('no wrapping: End scrolls across', FRich.ScrollX > 0);
  r := FRich.CaretClientRect;
  tw := FRich.TextWindow;
  AssertTrue('the caret in view', (r.Right > r.Left) and (r.Left >= tw.Left) and (r.Right <= tw.Right));
  FRich.Press(VK_HOME, []);
  AssertEquals('Home: back', 0, FRich.ScrollX);
  // a page wider than the window
  FRich.WrapMode := rwmPage;
  FRich.SetBounds(0, 0, 200, 300);
  FRich.UpdateView;
  FRich.SelStart := 0;
  FRich.Press(VK_END, []);
  AssertTrue('page mode: End scrolls across', FRich.ScrollX > 0);
  r := FRich.CaretClientRect;
  tw := FRich.TextWindow;
  AssertTrue('the caret in view', (r.Right > r.Left) and (r.Left >= tw.Left) and (r.Right <= tw.Right));
  FRich.Press(VK_HOME, []);
  AssertEquals('page mode, Home: back', 0, FRich.ScrollX);
end;

{ S-I5: the caret set into a cell of a row far below the view (not held) is scrolled to and
  shown in its column. }
procedure TTyRichEditControlTest.TestTheCaretOfACellInARowNotHeld;
var
  s: string;
  i: Integer;
  t: TTyRichText;
  pos: TTyRichPos;
  r, a: TRect;
begin
  s := '{\rtf1\ansi\deff0{\fonttbl{\f0 Arial;}}';
  for i := 1 to 200 do s := s + '\pard line ' + IntToStr(i) + '\par';
  s := s + '\trowd\cellx1500\cellx3000\pard\intbl a\cell\pard\intbl bcell\cell\row\pard end\par}';
  LoadRtfText(s);
  t := FRich.Document.Text;
  AssertEquals('paragraphs', 203, t.ParaCount);
  AssertFalse('the row is not held', InView(201));
  pos := t.ParaStart(201) + 2;
  FRich.SelStart := pos;
  r := FRich.CaretClientRect;
  a := FRich.Area;
  AssertTrue('shown', (r.Bottom > r.Top) and (r.Top >= a.Top) and (r.Bottom <= a.Bottom));
  AssertTrue('in the second column', r.Left - a.Left >= 100);
  AssertEquals('where PositionRect says', FRich.PositionRect(pos).Top, r.Top);
end;

{ S-I5: OnSelectionChange for a document change that moved the caret, none for one that did
  not. }
procedure TTyRichEditControlTest.TestADocumentChangeReportsTheSelectionIfItMoved;
var
  f: TTyCharFormat;
begin
  FRich.Lines.Text := 'abcdef';
  FRich.UpdateView;
  FRich.SelStart := 3;
  FRich.OnSelectionChange := @SelChanged;
  FSelChanges := 0;
  AssertTrue(FRich.Document.Execute(TTyRichInsertText.Create(0, 'xy')));
  AssertEquals('moved', Int64(5), FRich.CaretIndex);
  AssertEquals('an insertion before the caret: reported', 1, FSelChanges);
  AssertTrue(FRich.Document.Execute(TTyRichInsertText.Create(7, 'z')));
  AssertEquals('an insertion after it: not', 1, FSelChanges);
  f := TyDefaultCharFormat;
  f.Style := [fsBold];
  AssertTrue(FRich.Document.Execute(TTyRichSetCharFormat.Create(TyRichRange(0, 5), [cffBold], f)));
  AssertEquals('a format change: not', 1, FSelChanges);
  FRich.UpdateView;
  AssertEquals('nor what follows', 1, FSelChanges);
end;

{ S-I5 / S-M1: Ctrl+Left / Right across paragraphs; Ctrl+Right at a cell's end passes the
  cell merged away after it, as Right does. }
procedure TTyRichEditControlTest.TestWordStepsAcrossParagraphsAndCells;
begin
  FRich.Lines.Text := 'ab cd'#10'ef gh';
  FRich.UpdateView;
  FRich.SelStart := 5;
  FRich.Press(VK_RIGHT, [ssCtrl]);
  AssertEquals('Ctrl+Right at the end: the next paragraph', Int64(6), FRich.CaretIndex);
  FRich.Press(VK_RIGHT, [ssCtrl]);
  AssertEquals('then its next word', Int64(9), FRich.CaretIndex);
  FRich.Press(VK_LEFT, [ssCtrl]);
  AssertEquals('Ctrl+Left to the paragraph''s start', Int64(6), FRich.CaretIndex);
  FRich.Press(VK_LEFT, [ssCtrl]);
  AssertEquals('Ctrl+Left from it: the last word before', Int64(3), FRich.CaretIndex);
  LoadRtfText('{\rtf1\ansi\deff0{\fonttbl{\f0 Arial;}}\trowd\clmgf\cellx1500\clmrg\cellx3000' +
    '\cellx4500\pard\intbl m\cell\pard\intbl\cell\pard\intbl c\cell\row\pard after\par}');
  FRich.SelStart := 1;
  FRich.Press(VK_RIGHT, [ssCtrl]);
  AssertEquals('Ctrl+Right at a cell''s end: past the cell merged away', Int64(3), FRich.CaretIndex);
  FRich.Press(VK_LEFT, [ssCtrl]);
  AssertEquals('and back', Int64(0), FRich.CaretIndex);
end;

{ S-I5: a line ended by U+000B ends before it: End stops there (no affinity), Home on the
  next line goes to the place after it. }
procedure TTyRichEditControlTest.TestHomeAndEndOnALineEndedByALineBreak;
begin
  FRich.Lines.Text := 'abcdef';
  AssertTrue(FRich.Document.Execute(TTyRichInsertText.Create(3, #11)));
  FRich.UpdateView;
  FRich.SelStart := 1;
  FRich.Press(VK_END, []);
  AssertEquals('End: before the line break', Int64(3), FRich.CaretIndex);
  AssertFalse('a place of its own', FRich.CaretAtLineEnd);
  FRich.SelStart := 6;
  FRich.Press(VK_HOME, []);
  AssertEquals('Home: after it', Int64(4), FRich.CaretIndex);
  FRich.Press(VK_END, []);
  AssertEquals('End of the last line', Int64(7), FRich.CaretIndex);
end;

{ S-I5 / S-M2, on a handle of a form never shown: a drag's move outside the text starts the
  drag timer (its firing is not run); the blink timer is made on entering and goes with the
  window; MouseMove sets the temporary cursor (the arrow over the padding, the I-beam over the
  text), and the control's Cursor - what LCL-Win32 shows on the window's set-cursor message -
  answers the same (W7 K-8: GetCursor), while the Cursor set is the I-beam; it streams as set. }
procedure TTyRichEditControlTest.TestTheTimersAndTheCursorOnAHandle;
var
  F: TForm;
  p: TPoint;
  a: TRect;
begin
  NeedWidgetSet;
  F := TForm.CreateNew(nil);
  try
    FRich.Parent := F;
    F.HandleNeeded;
    FRich.HandleNeeded;
    AssertTrue('a handle', FRich.HandleAllocated);
    AssertFalse('the form is not shown', F.Visible);
    SetLinesOf(100, 'Line ');
    FRich.UpdateView;
    a := FRich.Area;
    // the blink
    AssertTrue('no blink before entering', FRich.BlinkTimerOf = nil);
    FRich.Enter;
    AssertTrue('made on entering', FRich.BlinkTimerOf <> nil);
    AssertTrue('and running', FRich.BlinkTimerOf.Enabled);
    // the drag's timer
    p := At(1);
    FRich.PressAt(p.X, p.Y);
    AssertTrue('a drag', FRich.DragOn);
    AssertTrue('no drag timer inside', FRich.DragTimerOf = nil);
    FRich.MoveAt(p.X, FRich.Height + 5);
    AssertTrue('a move outside: the drag timer', FRich.DragTimerOf <> nil);
    AssertTrue('running', FRich.DragTimerOf.Enabled);
    FRich.MoveAt(p.X, p.Y);
    AssertFalse('back inside: stopped', FRich.DragTimerOf.Enabled);
    FRich.ReleaseAt(p.X, p.Y);
    // the temporary cursor
    FRich.TempCursors := nil;
    FRich.MoveAt(1, 1);
    FRich.MoveAt((a.Left + a.Right) div 2, (a.Top + a.Bottom) div 2);
    AssertEquals('two moves, two cursors', 2, Length(FRich.TempCursors));
    AssertEquals('over the padding: the arrow', Ord(crArrow), Ord(FRich.TempCursors[0]));
    AssertEquals('over the text: the I-beam', Ord(crIBeam), Ord(FRich.TempCursors[1]));
    // the control's Cursor (what LCL-Win32 answers the set-cursor message with)
    FRich.MoveAt(1, 1);
    AssertEquals('Cursor over the padding: the arrow', Ord(crArrow), Ord(FRich.Cursor));
    AssertFalse('streamed after a move over the padding: no Cursor (the default)',
      Pos('Cursor', FormText(FRich)) > 0);
    FRich.MoveAt((a.Left + a.Right) div 2, (a.Top + a.Bottom) div 2);
    AssertEquals('Cursor over the text: the I-beam', Ord(crIBeam), Ord(FRich.Cursor));
    FRich.Cursor := crHandPoint;
    FRich.MoveAt(1, 1);
    AssertEquals('a cursor of the user''s, over the padding', Ord(crHandPoint), Ord(FRich.Cursor));
    AssertTrue('and streamed as set', Pos('crHandPoint', FormText(FRich)) > 0);
    FRich.MoveAt((a.Left + a.Right) div 2, (a.Top + a.Bottom) div 2);
    AssertEquals('a cursor of the user''s, over the text', Ord(crHandPoint), Ord(FRich.Cursor));
    FRich.Cursor := crIBeam;
    FRich.DropHandle;
    AssertTrue('the blink goes with the window', FRich.BlinkTimerOf = nil);
    AssertTrue('so does the drag''s timer', FRich.DragTimerOf = nil);
  finally
    FRich.Parent := nil;
    F.Free;
  end;
end;

{ S-M4: Shift+End on a wrapped line, then Right: the selection collapses onto the caret, which
  stays at that line's end. }
procedure TTyRichEditControlTest.TestACollapseOntoTheCaretKeepsItsLine;
var
  s: string;
  i, top: Integer;
  L: TTyParaLayout;
  e: TTyRichPos;
begin
  s := '';
  for i := 1 to 40 do s := s + 'word ';
  FRich.Lines.Text := s;
  FRich.UpdateView;
  L := FRich.VisibleBlocks[0].Layout as TTyParaLayout;
  AssertTrue('it wraps', L.LineCount >= 2);
  e := L.Lines[0].First + L.Lines[0].Count;
  FRich.SelStart := 0;
  FRich.Press(VK_END, [ssShift]);
  AssertEquals('Shift+End', e, FRich.CaretIndex);
  AssertTrue('at the line''s end', FRich.CaretAtLineEnd);
  top := FRich.CaretClientRect.Top;
  FRich.Press(VK_RIGHT, []);
  AssertFalse('collapsed', FRich.HasSelection);
  AssertEquals('onto the caret', e, FRich.CaretIndex);
  AssertTrue('still the line''s end', FRich.CaretAtLineEnd);
  AssertEquals('on that line', top, FRich.CaretClientRect.Top);
end;

{ S-M5: a zoom forgets the wished x: Down after it goes from where the caret is drawn now. }
procedure TTyRichEditControlTest.TestAZoomForgetsTheWishedX;
var
  t: TTyRichText;
  x, cw: Integer;
begin
  FRich.Lines.Text := 'a long first line of text'#10'short'#10'a long third line of text';
  FRich.UpdateView;
  t := FRich.Document.Text;
  FRich.SelStart := 20;
  FRich.Press(VK_DOWN, []);
  AssertEquals('down to the short line''s end', t.ParaStart(1) + 5, FRich.CaretIndex);
  FRich.Zoom := 200;
  FRich.UpdateView;
  x := FRich.CaretClientRect.Left;
  cw := FRich.PositionRect(t.ParaStart(2) + 4).Left - FRich.PositionRect(t.ParaStart(2) + 3).Left;
  FRich.Press(VK_DOWN, []);
  AssertEquals('down again', 2, t.ParaOfPos(FRich.CaretIndex));
  AssertTrue(Format('under the caret''s x after the zoom (%d, was %d, a letter %d)',
    [FRich.CaretClientRect.Left, x, cw]), Abs(FRich.CaretClientRect.Left - x) <= cw);
end;

{ S-M7: SelLength := High(Int64) is "to the end", -High(Int64) "to the start". }
procedure TTyRichEditControlTest.TestAHugeSelLengthGoesToTheEnd;
begin
  FRich.Lines.Text := 'abcdef';
  FRich.SelStart := 2;
  FRich.SelLength := High(Int64);
  AssertEquals('from the start', Int64(2), FRich.SelStart);
  AssertEquals('to the end', Int64(4), FRich.SelLength);
  AssertEquals('the caret at the end', Int64(6), FRich.CaretIndex);
  FRich.SelStart := 3;
  FRich.SelLength := -High(Int64);
  AssertEquals('back to the start', Int64(0), FRich.SelStart);
  AssertEquals('all before', Int64(3), FRich.SelLength);
end;

{ S-M8: the public pair answers a wrapped line's end both ways: a point past the line's end is
  that place at the line's end; its rectangle is on that line with the flag, on the next
  line's start without. }
procedure TTyRichEditControlTest.TestThePublicQueriesCarryTheAffinity;
var
  s: string;
  i, top0, top1: Integer;
  L: TTyParaLayout;
  e, p: TTyRichPos;
  atEnd: Boolean;
  a: TRect;
begin
  s := '';
  for i := 1 to 40 do s := s + 'word ';
  FRich.Lines.Text := s;
  FRich.UpdateView;
  a := FRich.Area;
  L := FRich.VisibleBlocks[0].Layout as TTyParaLayout;
  e := L.Lines[0].First + L.Lines[0].Count;
  top0 := a.Top + L.Lines[0].Top;
  top1 := a.Top + L.Lines[1].Top;
  p := FRich.PositionAtPoint(FRich.Width - 1, top0 + 2, atEnd);
  AssertEquals('past the line''s end: its end', e, p);
  AssertTrue('at the line''s end', atEnd);
  AssertEquals('without the flag: the same place', e, FRich.PositionAtPoint(FRich.Width - 1, top0 + 2));
  AssertEquals('with the flag: on that line', top0, FRich.PositionRect(e, True).Top);
  AssertEquals('without: the next line''s start', top1, FRich.PositionRect(e).Top);
  p := FRich.PositionAtPoint(a.Left + 1, top1 + 2, atEnd);
  AssertEquals('the next line''s start', e, p);
  AssertFalse('no line''s end there', atEnd);
end;

{ S-M10: a deletion that leaves the caret inside a cluster (before a combining mark): after the
  next paint the caret is on a caret place, reported. }
procedure TTyRichEditControlTest.TestAChangeLeavesTheCaretOnACaretPlace;
begin
  FRich.Lines.Text := 'aXY' + Utf8Of($301) + 'z';
  FRich.UpdateView;
  FRich.SelStart := 2;
  AssertEquals('between X and Y', Int64(2), FRich.CaretIndex);
  FRich.OnSelectionChange := @SelChanged;
  FSelChanges := 0;
  AssertTrue(FRich.Document.Execute(TTyRichDelete.Create(1, 2)));
  AssertEquals('the change moved it: reported', 1, FSelChanges);
  PaintAll(True);
  AssertEquals('after the paint: the cluster''s start', Int64(0), FRich.CaretIndex);
  // W7 K-10: not from inside the paint - by the queued call, after it
  AssertEquals('no handler inside the paint', 1, FSelChanges);
  RunQueuedCalls;
  AssertEquals('reported once more', 2, FSelChanges);
  PaintAll(True);
  RunQueuedCalls;
  AssertEquals('and no more', 2, FSelChanges);
  // the same, put right by a settled query instead of a paint
  FRich.Lines.Text := 'aXY' + Utf8Of($301) + 'z';
  FRich.UpdateView;
  FRich.SelStart := 2;
  AssertTrue(FRich.Document.Execute(TTyRichDelete.Create(1, 2)));
  FRich.CaretClientRect;
  AssertEquals('after a query: the cluster''s start', Int64(0), FRich.CaretIndex);
end;

{ S-M11: between Lines.BeginUpdate and EndUpdate, after paragraphs were removed, a paint shows
  the kept surface as it is (nothing laid out or drawn), a blink does nothing, and nothing
  raises; after EndUpdate the view is right. }
procedure TTyRichEditControlTest.TestAPaintAndABlinkInsideAnUpdate;
var
  i: Integer;
  bmp: TBitmap;
begin
  SetLinesOf(50, 'Line ');
  FRich.ForceFocus := True;
  PaintAll(True);
  // a caret that stays inside the shorter text, drawn (the next blink would paint it away)
  FRich.SelStart := FRich.Document.Text.ParaStart(2) + 2;
  PaintAll(True);
  bmp := TBitmap.Create;
  try
    bmp.SetSize(FRich.Width, FRich.Height);
    FRich.CaretOn(bmp.Canvas);
  finally
    bmp.Free;
  end;
  FRich.Lines.BeginUpdate;
  try
    for i := 1 to 45 do FRich.Lines.Delete(0);
    FRich.ResetCounts;
    PaintAll(True);
    AssertEquals('inside the update: no block drawn', 0, FRich.BlockPaints);
    AssertEquals('nor the frame', 0, FRich.FramePaints);
    AssertEquals('nothing laid out', 0, Length(FRich.Given));
    FRich.Blink;
    FRich.Blink;
    AssertEquals('the blink waits', 0, Length(FRich.Invalidated));
  finally
    FRich.Lines.EndUpdate;
  end;
  AssertEquals('five lines', 5, FRich.Document.Text.ParaCount);
  CheckSurface('after the update');
  FRich.ResetCounts;
  FRich.Blink;
  FRich.Blink;
  AssertTrue('the blink again', Length(FRich.Invalidated) >= 1);
end;

procedure TTyRichEditControlTest.InsertInLastStep(Sender: TObject; ADone, ATotal: Int64;
  var ACancel: Boolean);
var
  d: TTyRichDocument;
begin
  d := FRich.Document;
  if d.Loading or (FLastStepEdits <> 0) then Exit;
  if d.Execute(TTyRichInsertText.Create(0, 'XYZ')) then FLastStepEdits := 1
  else FLastStepEdits := -1;
end;

{ S-X1: a command run from the last load step's progress handler (the document no longer
  loads there) is an edit for the caret and the change report too: the caret moves as for any
  edit, and the change is reported; the slices themselves move nothing and report nothing. }
procedure TTyRichEditControlTest.TestAnEditFromTheLastStepMovesTheCaret;
var
  st: TBytesStream;
  steps: Integer;
begin
  FLastStepEdits := 0;
  FRich.OnChange := @Changed;
  FRich.OnLoadProgress := @InsertInLastStep;
  st := TBytesStream.Create(ReadFixtureFile('word-list.rtf'));
  try
    FRich.Slices(AfterPars(st.Bytes, 2), 256);
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  AssertTrue('loading', FRich.Loading);
  FRich.SelStart := 5;
  FChanges := 0;
  steps := 0;
  while FRich.Loading do
  begin
    AssertTrue('a step', FRich.Step);
    Inc(steps);
    AssertTrue('runaway', steps < 10000);
  end;
  AssertTrue(Format('in slices (%d)', [steps]), steps >= 5);
  AssertEquals('the command ran in the last step''s handler', 1, FLastStepEdits);
  AssertEquals('the caret moved as for any edit', Int64(8), FRich.CaretIndex);
  AssertEquals('the edit was reported, the slices were not', 1, FChanges);
end;

{$IFDEF MSWINDOWS}
var
  GReplaceError: DWord;

procedure W6SetLastError(AError: DWord); stdcall; external 'kernel32' name 'SetLastError';

function W6FailingReplace(AReplaced, AReplacement, ABackup: PWideChar; AFlags: DWord;
  AExclude, AReserved: Pointer): LongBool; stdcall;
begin
  W6SetLastError(GReplaceError);
  Result := False;
end;
{$ENDIF}

{ H2-M9: the replace call made to fail (the seam TyRichReplaceFileW). For a reason other than
  access or sharing (a volume without ReplaceFileW) the plain replace saves: the new content
  is there, no temporary file is left. For access or sharing: the control's own refusal, the
  target untouched, nothing left. The Unix order (owner, then mode) is compile-checked only. }
procedure TTyRichEditControlTest.TestTheReplaceFallbackAndRefusal;
{$IFDEF MSWINDOWS}
const
  Codes: array[0..1] of DWord = (5, 32);
var
  path: string;
  orig, before: TBytes;
  saved: TTyRichReplaceFileFunc;
  raised: Boolean;
  k: Integer;
begin
  orig := BytesOf('{\rtf1\ansi\deff0{\fonttbl{\f0 Arial;}}\pard\f0 Saved text.\par}');
  path := TempFile('fallback.rtf', orig);
  FRich.LoadFromFile(path);
  AssertTrue('changed', FRich.Document.Execute(TTyRichInsertText.Create(0, 'New ')));
  saved := TyRichReplaceFileW;
  try
    TyRichReplaceFileW := @W6FailingReplace;
    GReplaceError := 1; // ERROR_INVALID_FUNCTION
    FRich.SaveToFile(path);
    AssertFalse('saved', FRich.Modified);
    AssertFalse('the new content', SameBytes(orig, FileBytes(path)));
    AssertTrue('its text', Pos('New Saved', ReadStream(path)) > 0);
    AssertEquals('no temporary file left', 1, FileCount);
    for k := 0 to High(Codes) do
    begin
      AssertTrue('changed again', FRich.Document.Execute(TTyRichInsertText.Create(0, 'More ')));
      before := FileBytes(path);
      GReplaceError := Codes[k];
      raised := False;
      try
        FRich.SaveToFile(path);
      except
        on E: ETyRichEdit do raised := E.Message = Format(rsRichEditCannotReplace, [path]);
      end;
      AssertTrue(Format('error %d: the control''s refusal', [Codes[k]]), raised);
      AssertTrue(Format('error %d: the target untouched', [Codes[k]]), SameBytes(before, FileBytes(path)));
      AssertEquals(Format('error %d: no temporary file left', [Codes[k]]), 1, FileCount);
      AssertTrue(Format('error %d: still modified', [Codes[k]]), FRich.Modified);
    end;
  finally
    TyRichReplaceFileW := saved;
  end;
end;
{$ELSE}
begin
  Ignore('Windows only (ReplaceFileW); the Unix path is compile-checked');
end;
{$ENDIF}

{ A3-M1: a hover whose look takes the layer path (an opacity): leaving it asks for a repaint,
  and the paint draws the normal look whole. }
procedure TTyRichEditControlTest.TestAStateLeavingTheLayerPathRepaints;
begin
  SetLinesOf(50, 'Line ');
  FCtl.LoadThemeCss('TyRichEdit:hover { opacity: 0.9; }');
  PaintAll(True);
  FRich.ResetCounts;
  FRich.Hover(True);
  AssertTrue('entering: a repaint asked for', FRich.Invalidates > 0);
  PaintAll(True);
  FRich.ResetCounts;
  FRich.Hover(False);
  AssertTrue('leaving: a repaint asked for', FRich.Invalidates > 0);
  PaintAll(True);
  AssertEquals('the normal look drawn whole', 1, FRich.FramePaints);
end;

{ A3-M2: a state that changes the font asks for a repaint, and the paint lays the text out in
  that font. Both states name a font, so only the value differs (not which properties are
  present); a family, not a size: a size also moves what is given in em (padding), which the
  signature holds anyway, and would not show whether the font itself is in it. }
procedure TTyRichEditControlTest.TestAStateFontIsALayoutChange;
var
  h0: Integer;
begin
  SetLinesOf(50, 'Line ');
  { The theme's hover changes the border: here it keeps it, so a hover that looks the same asks
    for nothing, and what follows sees the font alone. }
  FCtl.LoadThemeCss('TyRichEdit { font-family: Arial; } TyRichEdit:hover { font-family: Arial; ' +
    'border-color: var(--input-border); }');
  PaintAll(True);
  FRich.ResetCounts;
  FRich.Hover(True);
  AssertEquals('a hover that looks the same', 0, FRich.Invalidates);
  FRich.Hover(False);
  FCtl.LoadThemeCss('TyRichEdit { font-family: Arial; } TyRichEdit:hover { font-family: Tahoma; ' +
    'border-color: var(--input-border); }');
  PaintAll(True);
  AssertEquals('the normal font', 'Arial', FRich.Layouter.BaseFontName);
  h0 := FRich.VisibleBlocks[0].Height;
  FRich.ResetCounts;
  FRich.Hover(True);
  AssertTrue('a repaint asked for', FRich.Invalidates > 0);
  PaintAll(True);
  AssertEquals('laid out in the hover''s font', 'Tahoma', FRich.Layouter.BaseFontName);
  AssertTrue('a layout', FRich.VisibleBlocks[0].Height > 0);
  if h0 = 0 then Fail('no block before');
end;

{ A3-M3: PointerStateChanged asks for the window's repaint when the look changes - a hover that
  changes the border, on entering and on leaving - and not for a press that looks the same. }
procedure TTyRichEditControlTest.TestAHoverAsksForARepaint;
begin
  SetLinesOf(50, 'Line ');
  FCtl.LoadThemeCss('TyRichEdit:hover { border-color: #FF0000; }');
  PaintAll(True);
  FRich.ResetCounts;
  FRich.Down;
  FRich.Up;
  AssertEquals('a press that looks the same: none', 0, FRich.Invalidates);
  FRich.Hover(True);
  AssertTrue('entering: a repaint asked for', FRich.Invalidates > 0);
  PaintAll(True);
  FRich.ResetCounts;
  FRich.Hover(False);
  AssertTrue('leaving: a repaint asked for', FRich.Invalidates > 0);
end;

{ ---- fix wave W7 ---- }

{ A small RTF table: a paragraph, ARows rows of three cells (rN a, rN b in bold, rN c), a
  paragraph after it. AInRow: the offset inside row AInRow after its second cell's end and
  before its third's (where a first slice leaves the row's first cell last in the text). }
function W7TableRtf(ARows, AInRow: Integer; out AInside: Int64): TBytes;
var
  s, row: RawByteString;
  k: Integer;
begin
  s := '{\rtf1\ansi\deff0{\fonttbl{\f0 Arial;}}' + #13#10 + '\pard\f0\fs20 before the table\par' + #13#10;
  AInside := 0;
  for k := 0 to ARows - 1 do
  begin
    row := '\trowd\trgaph108\cellx2400\cellx4800\cellx7200' + #13#10 +
      '\pard\intbl r' + IntToStr(k) + ' a\cell r' + IntToStr(k) + ' \b b\b0\cell ';
    if k = AInRow then AInside := Length(s) + Length(row);
    s := s + row + 'r' + IntToStr(k) + ' c\cell\row' + #13#10;
  end;
  s := s + '\pard after the table\par' + #13#10 + '}';
  Result := BytesOf(s);
end;

procedure TTyRichEditControlTest.LoadW7Table(ARows, AInRow: Integer);
var
  b: TBytes;
  inside: Int64;
  st: TBytesStream;
begin
  b := W7TableRtf(ARows, AInRow, inside);
  FRich.Slices(inside, 64);
  st := TBytesStream.Create(b);
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
end;

{ A form never shown with FRich on it, its handle made (the turns of the background work are
  queued only for a control with a window). }
function TTyRichEditControlTest.HandleForm: TForm;
begin
  NeedWidgetSet;
  Result := TForm.CreateNew(nil);
  FRich.Parent := Result;
  Result.HandleNeeded;
  FRich.HandleNeeded;
  AssertTrue('a handle', FRich.HandleAllocated);
  AssertFalse('the form is not shown', Result.Visible);
end;

procedure TTyRichEditControlTest.LoadW7Plain(AExpectLoading: Boolean);
var
  src: TBytes;
  first: Int64;
  st: TBytesStream;
begin
  src := W5PlainRtf(3000, first);
  FRich.Slices(first, 16 * 1024);
  st := TBytesStream.Create(src);
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  if AExpectLoading then AssertTrue('loading', FRich.Loading);
end;

{ K-1 / R49 (L-1): on this widgetset (win32) the load runs one turn per pass of the
  application's loop, scheduled from its idle step. A start registers the idle handler once
  and queues the first turn; a turn with work left queues nothing of its own and leaves the
  one registration; the idle step queues exactly one call, and a second idle step before it
  ran queues no second; the queued call runs one turn; with no work left the idle handler is
  gone. A cancel, a new content, the handle's destruction and the destructor take the idle
  handler and the queued call away: running the idle handlers and the queue by hand then
  enters the control nowhere. (The loop itself - input, paints and timers between two turns -
  is the real-loop probe's and the smoke's to see.) }
procedure TTyRichEditControlTest.TestTheLoadRunsInQueuedTurns;
var
  F: TForm;
  posts, removes, watches, unwatches, idles, turns, n: Integer;
  bytes: Int64;

  procedure NothingEntered(const AWhat: string);
  var
    n0, i0, p0: Integer;
  begin
    n0 := FRich.Document.Text.ParaCount;
    i0 := TRichProbe.IdleEntries;
    p0 := TRichProbe.Posts;
    RunIdleHandlers;
    RunQueuedCalls;
    AssertEquals(AWhat + ': the idle step does not enter it', i0, TRichProbe.IdleEntries);
    AssertEquals(AWhat + ': nothing queued', p0, TRichProbe.Posts);
    AssertEquals(AWhat + ': nothing indexed', n0, FRich.Document.Text.ParaCount);
  end;

begin
  F := HandleForm;
  try
    AssertTrue('win32 is driven from the idle step',
      TyRichTurnDriverFor(WidgetSet.LCLPlatform) = rtdIdle);
    watches := TRichProbe.Watches;
    posts := TRichProbe.Posts;
    LoadW7Plain;
    AssertEquals('a start registers the idle handler once', watches + 1, TRichProbe.Watches);
    AssertTrue('registered', FRich.IdleOn);
    AssertTrue('and queues the first turn', FRich.TurnQueued);
    AssertEquals('one call', posts + 1, TRichProbe.Posts);
    turns := 0;
    while FRich.Loading do
    begin
      AssertTrue(Format('turn %d: queued', [turns]), FRich.TurnQueued);
      posts := TRichProbe.Posts;
      bytes := TyRichRtfLoadOf(FRich.Document).BytesIndexed;
      RunQueuedCalls;
      Inc(turns);
      AssertEquals(Format('turn %d queues no call of its own', [turns]), posts,
        TRichProbe.Posts);
      AssertFalse(Format('turn %d: nothing queued after it', [turns]), FRich.TurnQueued);
      if not FRich.Loading then Break;
      AssertTrue(Format('turn %d indexed', [turns]),
        TyRichRtfLoadOf(FRich.Document).BytesIndexed > bytes);
      AssertTrue(Format('turn %d: still registered', [turns]), FRich.IdleOn);
      AssertEquals(Format('turn %d: one registration', [turns]), watches + 1,
        TRichProbe.Watches);
      // the idle step queues exactly one call; a second one before it ran queues none
      AssertTrue('the idle handlers leave Done', RunIdleHandlers);
      AssertEquals(Format('idle step after turn %d: one call', [turns]), posts + 1,
        TRichProbe.Posts);
      RunIdleHandlers;
      AssertEquals(Format('a second idle step after turn %d: no second', [turns]), posts + 1,
        TRichProbe.Posts);
      AssertTrue('runaway', turns < 10000);
    end;
    AssertTrue(Format('in turns (%d)', [turns]), turns >= 2);
    AssertFalse('the whole file', FRich.Document.Incomplete);
    AssertFalse('no work left: the idle handler is gone', FRich.IdleOn);
    NothingEntered('after the end');
    // a turn with the driver off (nothing registered, as the timer driver leaves it): it
    // registers the idle handler and queues nothing of its own
    FRich.ClosedApp := True;
    LoadW7Plain;
    FRich.ClosedApp := False;
    AssertFalse('closed: not registered', FRich.IdleOn);
    posts := TRichProbe.Posts;
    FRich.Turn;
    AssertTrue('the turn registers the idle handler', FRich.IdleOn);
    AssertEquals('and queues no call of its own', posts, TRichProbe.Posts);
    FRich.CancelLoad;
    // a cancel
    LoadW7Plain;
    AssertTrue('registered again', FRich.IdleOn);
    removes := TRichProbe.Removes;
    unwatches := TRichProbe.Unwatches;
    FRich.CancelLoad;
    AssertFalse('cancelled: nothing queued', FRich.TurnQueued);
    AssertFalse('cancelled: not registered', FRich.IdleOn);
    AssertEquals('taken off the queue', removes + 1, TRichProbe.Removes);
    AssertEquals('the idle handler removed', unwatches + 1, TRichProbe.Unwatches);
    NothingEntered('after a cancel');
    // a new content
    LoadW7Plain;
    FRich.Lines.Text := 'another';
    AssertFalse('a new content: nothing queued', FRich.TurnQueued);
    AssertFalse('a new content: not registered', FRich.IdleOn);
    NothingEntered('after a new content');
    // the handle's destruction
    LoadW7Plain;
    RunQueuedCalls;
    RunIdleHandlers;
    AssertTrue('a turn queued by the idle step', FRich.TurnQueued);
    FRich.DropHandle;
    AssertFalse('no window: nothing queued', FRich.TurnQueued);
    AssertFalse('no window: not registered', FRich.IdleOn);
    NothingEntered('after the handle went');
    AssertTrue('the load waits', FRich.Loading);
    FRich.HandleNeeded;
    AssertTrue('a window again: registered again', FRich.IdleOn);
    AssertTrue('a window again: queued again', FRich.TurnQueued);
    // the destructor
    removes := TRichProbe.Removes;
    unwatches := TRichProbe.Unwatches;
    idles := TRichProbe.IdleEntries;
    n := TRichProbe.Posts;
    FreeAndNil(FRich);
    AssertEquals('the destructor takes the call off the queue', removes + 1, TRichProbe.Removes);
    AssertEquals('and removes the idle handler', unwatches + 1, TRichProbe.Unwatches);
    RunIdleHandlers;
    RunQueuedCalls;
    AssertEquals('freed: the idle step does not enter it', idles, TRichProbe.IdleEntries);
    AssertEquals('freed: nothing queued', n, TRichProbe.Posts);
    FRich := NewProbe;
  finally
    if FRich <> nil then FRich.Parent := nil;
    F.Free;
  end;
end;

{ R49: the driver is chosen per widgetset by one function; the timer driver (Cocoa and every
  widgetset not named) runs here when forced: a start enables the timer, a turn with work left
  keeps it on and queues and registers nothing, the end disables it; the window's going frees
  it. }
procedure TTyRichEditControlTest.TestTheDriverIsChosenPerWidgetset;
var
  F: TForm;
  p: TLCLPlatform;
  posts, watches, turns: Integer;
begin
  for p := Low(TLCLPlatform) to High(TLCLPlatform) do
    if p in [lpWin32, lpGtk2, lpGtk3, lpQt5, lpQt6] then
      AssertTrue(Format('platform %d: the idle step', [Ord(p)]), TyRichTurnDriverFor(p) = rtdIdle)
    else
      AssertTrue(Format('platform %d: the timer', [Ord(p)]), TyRichTurnDriverFor(p) = rtdTimer);
  AssertTrue('Cocoa: the timer', TyRichTurnDriverFor(lpCocoa) = rtdTimer);
  F := HandleForm;
  try
    FRich.ForceTimer := True;
    posts := TRichProbe.Posts;
    watches := TRichProbe.Watches;
    LoadW7Plain;
    AssertTrue('a timer', FRich.TimerOf <> nil);
    AssertTrue('running', FRich.TimerOf.Enabled);
    AssertEquals('1 ms', 1, FRich.TimerOf.Interval);
    turns := 0;
    while FRich.Loading do
    begin
      FRich.Turn;
      Inc(turns);
      if FRich.Loading then AssertTrue('work left: still running', FRich.TimerOf.Enabled);
      AssertTrue('runaway', turns < 10000);
    end;
    AssertFalse('done: stopped', FRich.TimerOf.Enabled);
    AssertEquals('nothing queued', posts, TRichProbe.Posts);
    AssertEquals('nothing registered', watches, TRichProbe.Watches);
    LoadW7Plain;
    AssertTrue('running again', FRich.TimerOf.Enabled);
    FRich.CancelLoad;
    AssertFalse('cancelled: stopped', FRich.TimerOf.Enabled);
    LoadW7Plain;
    FRich.DropHandle;
    AssertTrue('the window went: freed', FRich.TimerOf = nil);
    FRich.HandleNeeded;
    AssertTrue('a window again: running', (FRich.TimerOf <> nil) and FRich.TimerOf.Enabled);
    FRich.FinishLoading;
    AssertFalse('finished: stopped', FRich.TimerOf.Enabled);
  finally
    FRich.ForceTimer := False;
    FRich.Parent := nil;
    F.Free;
  end;
end;

procedure TTyRichEditControlTest.CountLoadEnds(Sender: TObject; const AChange: TTyRichChange);
begin
  if not FRich.Document.Loading and FRich.Document.Incomplete then Inc(FLoadEnds);
  if Assigned(FDocNotice) then FDocNotice(Sender, AChange);
end;

{ L-2, N-5: a queue that will not take a call raises nothing out of the load, a turn or the idle
  step, and leaves nothing registered. Outside a shutdown (in practice: out of memory) the load
  then ends as a cancel ends it - not Loading, Incomplete, the load's own notice once - rather
  than staying Loading with nothing to drive it. An application closed for scheduling (being
  destroyed) gets nothing queued or registered, quietly: the document stays as far as it was
  read. A selection report that cannot be queued is made by the next user action. }
procedure TTyRichEditControlTest.TestSchedulingThatFailsEndsTheLoadQuietly;
var
  F: TForm;
  posts, watches: Integer;
begin
  F := HandleForm;
  try
    FDocNotice := FRich.Document.OnChange;
    FRich.Document.OnChange := @CountLoadEnds;
    // the load's own start cannot queue its first turn
    FRich.FailPost := True;
    FLoadEnds := 0;
    LoadW7Plain(False);
    AssertFalse('the start could not queue: the load ended', FRich.Loading);
    AssertTrue('incomplete', FRich.Document.Incomplete);
    AssertEquals('the load''s notice, once', 1, FLoadEnds);
    AssertFalse('nothing queued', FRich.TurnQueued);
    AssertFalse('nothing registered', FRich.IdleOn);
    AssertTrue('no backstop', (FRich.BackstopOf = nil) or not FRich.BackstopOf.Enabled);
    // the idle step's queuing refused: nothing escapes, the load ends the same way
    FRich.FailPost := False;
    LoadW7Plain;
    RunQueuedCalls;
    AssertTrue('loading', FRich.Loading);
    FRich.FailPost := True;
    FLoadEnds := 0;
    RunIdleHandlers;
    AssertFalse('the idle step: nothing queued', FRich.TurnQueued);
    AssertFalse('the idle step: the driver ended', FRich.IdleOn);
    AssertFalse('the idle step could not queue: the load ended', FRich.Loading);
    AssertTrue('incomplete too', FRich.Document.Incomplete);
    AssertEquals('the load''s notice, once', 1, FLoadEnds);
    FRich.FailPost := False;
    // closed for scheduling (TApplication.Destroy's flags)
    FRich.ClosedApp := True;
    posts := TRichProbe.Posts;
    watches := TRichProbe.Watches;
    LoadW7Plain;
    FRich.Turn;
    AssertEquals('closed: nothing queued', posts, TRichProbe.Posts);
    AssertEquals('closed: nothing registered', watches, TRichProbe.Watches);
    AssertFalse('closed: not registered', FRich.IdleOn);
    AssertTrue('closed: the load waits, quietly', FRich.Loading);
    FRich.ClosedApp := False;
    FRich.CancelLoad;
    FRich.Document.OnChange := FDocNotice;
    // a selection report that cannot be queued: the next user action reports it
    FRich.OnSelectionChange := nil;
    FRich.Lines.Text := 'aXY' + Utf8Of($301) + 'z';
    FRich.UpdateView;
    FRich.SelStart := 2;
    RunQueuedCalls;
    FRich.OnSelectionChange := @SelChanged;
    AssertTrue(FRich.Document.Execute(TTyRichDelete.Create(1, 2)));
    FSelChanges := 0;
    FRich.FailPost := True;
    PaintAll(True);
    AssertEquals('snapped by the paint', Int64(0), FRich.CaretIndex);
    AssertFalse('the report could not be queued', FRich.ReportQueued);
    AssertEquals('and was not made in the paint', 0, FSelChanges);
    FRich.FailPost := False;
    FRich.Press(VK_LEFT, []);
    AssertEquals('the next key reports it', 1, FSelChanges);
  finally
    if Assigned(FDocNotice) then FRich.Document.OnChange := FDocNotice;
    FRich.FailPost := False;
    FRich.ClosedApp := False;
    FRich.Parent := nil;
    F.Free;
  end;
end;

{ L-3: a window paint inside an update that ends with nothing to report (it was skipped: the
  view was behind) is made good when the update ends - the text window is invalidated once; an
  update with no paint inside it invalidates nothing. }
procedure TTyRichEditControlTest.TestAPaintSkippedInAnUpdateWithoutAChange;
var
  i, hits: Integer;
begin
  SetLinesOf(10, 'Line ');
  FRich.Lines.BeginUpdate;
  try
    PaintAll(True);
    FRich.ResetCounts;
  finally
    FRich.Lines.EndUpdate;
  end;
  hits := 0;
  for i := 0 to High(FRich.Invalidated) do
    if CoversRect(FRich.Invalidated[i], FRich.TextWindow) then Inc(hits);
  AssertEquals('nothing changed: the text window is painted again, once', 1, hits);
  FRich.Lines.BeginUpdate;
  try
    FRich.ResetCounts;
  finally
    FRich.Lines.EndUpdate;
  end;
  AssertEquals('no paint inside: nothing invalidated', 0, Length(FRich.Invalidated));
end;

{ L-4: SelectAll, SelStart :=, SelLength := and CaretIndex := between BeginUpdate and EndUpdate,
  after paragraphs were removed, raise nothing and ask the layout nothing; after EndUpdate the
  selection is inside the document and painted. }
procedure TTyRichEditControlTest.TestTheSelectionSettersWaitForAnUpdate;
var
  i: Integer;
  len: TTyRichPos;
  hit: Boolean;
begin
  SetLinesOf(50, 'Line ');
  PaintAll(True);
  FRich.SelStart := FRich.Document.Text.ParaStart(40) + 2;
  PaintAll(True);
  FRich.Lines.BeginUpdate;
  try
    for i := 1 to 45 do FRich.Lines.Delete(0);
    FRich.ResetCounts;
    FRich.SelectAll;
    FRich.SelStart := 3;
    FRich.SelLength := 1000;
    FRich.CaretIndex := 7;
    FRich.SelStart := 1;
    FRich.SelLength := 2;
    FRich.SelectAll;
    AssertEquals('nothing laid out', 0, Length(FRich.Given));
    AssertEquals('nothing painted', 0, Length(FRich.Invalidated));
  finally
    FRich.Lines.EndUpdate;
  end;
  len := FRich.Document.Text.Length;
  AssertEquals('five lines', 5, FRich.Document.Text.ParaCount);
  AssertEquals('the selection starts at 0', Int64(0), FRich.SelStart);
  AssertEquals('and ends at the document''s end', len, FRich.SelLength);
  hit := False;
  for i := 0 to High(FRich.Invalidated) do
    if CoversRect(FRich.Invalidated[i], FRich.TextWindow) then hit := True;
  AssertTrue('after the update: the selection is painted', hit);
  // a selection beyond the final text, set before more was deleted, is clamped at the end
  FRich.Lines.BeginUpdate;
  try
    FRich.SelStart := FRich.Document.Text.Length;
    for i := 1 to 3 do FRich.Lines.Delete(0);
  finally
    FRich.Lines.EndUpdate;
  end;
  AssertTrue('clamped to the final text',
    FRich.SelStart + FRich.SelLength <= FRich.Document.Text.Length);
  // an update that changes nothing: its end alone paints the selection set in it
  PaintAll(True);
  FRich.Lines.BeginUpdate;
  try
    FRich.SelStart := 2;
    FRich.SelLength := 3;
    FRich.ResetCounts;
  finally
    FRich.Lines.EndUpdate;
  end;
  hit := False;
  for i := 0 to High(FRich.Invalidated) do
    if CoversRect(FRich.Invalidated[i], FRich.TextWindow) then hit := True;
  AssertTrue('nothing changed: the selection is painted at the update''s end', hit);
  AssertEquals('the selection', Int64(3), FRich.SelLength);
  PaintAll(True);
  CheckSurface('after the selection set in an update');
end;

{ L-5: the pointer leaving the control forgets that it was over the padding: the I-beam is
  answered until a move over the padding says otherwise. }
procedure TTyRichEditControlTest.TestTheCursorForgetsThePaddingOnLeaving;
var
  F: TForm;
begin
  F := HandleForm;
  try
    SetLinesOf(10, 'Line ');
    FRich.UpdateView;
    FRich.MoveAt(1, 1);
    AssertEquals('over the padding: the arrow', Ord(crArrow), Ord(FRich.Cursor));
    FRich.HoverOut;
    AssertEquals('left: the I-beam', Ord(crIBeam), Ord(FRich.Cursor));
  finally
    FRich.Parent := nil;
    F.Free;
  end;
end;

procedure TTyRichEditControlTest.SlowHandler(Sender: TObject; ADone, ATotal: Int64;
  var ACancel: Boolean);
begin
  // a handler that takes 50 ms by the test's clock
  Inc(FRich.ClockNow, 50);
end;

{ A plain RTF of AParas paragraphs, its first slice the first 50 of them, loading. }
procedure TTyRichEditControlTest.LoadW8Big(AParas: Integer);
var
  src: TBytes;
  first: Int64;
  st: TBytesStream;
begin
  src := W5PlainRtf(AParas, first);
  FRich.FirstSliceBytes := first;
  st := TBytesStream.Create(src);
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  AssertTrue('loading', FRich.Loading);
end;

{ L-6: the slices a load appends below the view cost no layout and no settled query in its
  turns (on a handle of a form never shown); the scroll bar still follows - its range is the
  document's at the end. }
procedure TTyRichEditControlTest.TestASliceBelowTheViewLaysOutNothing;
var
  F: TForm;
  turns, endMax: Integer;
begin
  F := HandleForm;
  try
    FRich.Slices(0, 16 * 1024);
    LoadW8Big(3000);
    PaintAll(True);
    AssertTrue('the view holds blocks', FRich.VisibleBlockCount > 0);
    AssertTrue('the slice ends below the view',
      FRich.VisibleBlocks[FRich.VisibleBlockCount - 1].LastPara < FRich.Document.Text.ParaCount - 1);
    FRich.ResetCounts;
    turns := 0;
    while FRich.Loading do
    begin
      RunQueuedCalls;
      RunIdleHandlers;
      Inc(turns);
      AssertTrue('runaway', turns < 10000);
    end;
    AssertTrue(Format('in turns (%d)', [turns]), turns >= 2);
    AssertEquals('the turns asked for no layout', 0, Length(FRich.Given));
    AssertEquals('and laid out nothing', 0, FRich.LaidParas);
    AssertEquals('nothing drawn', 0, FRich.BlockPaints);
    AssertTrue('a scroll bar', (FRich.VBar <> nil) and FRich.VBar.Visible);
    endMax := FRich.VBar.Max;
    // (a bar unit is a pixel here: the document is far below ScrollBarLimit)
    AssertEquals('the bar''s range at the end is the whole document''s',
      FRich.Document.Text.TotalHeight div FRich.Scale - FRich.VBar.PageSize, Int64(endMax));
    FRich.ScrollToEnd;
    PaintAll(True);
    AssertEquals('scrolled to the end: the last paragraph shown',
      FRich.Document.Text.ParaCount - 1,
      FRich.VisibleBlocks[FRich.VisibleBlockCount - 1].LastPara);
  finally
    FRich.Parent := nil;
    F.Free;
  end;
end;

{ The slice sizes the loader is asked for in the next turn (one a slice). }
function TTyRichEditControlTest.TurnSizes: string;
var
  i: Integer;
begin
  FRich.SliceLog := nil;
  FRich.LogSlices := True;
  try
    FRich.Turn;
  finally
    FRich.LogSlices := False;
  end;
  Result := '';
  for i := 0 to High(FRich.SliceLog) do
  begin
    if Result <> '' then Result := Result + ' ';
    Result := Result + IntToStr(FRich.SliceLog[i] div 1024);
  end;
end;

{ L-6, N-3: a load's turns start at the smallest slice and double it while they are fast (a
  clock that stands); a step by hand is not a turn (StepBytes), the synchronous first slice of
  the load asks no size; a file that indexes slowly keeps the small slices, its first turn
  too, and the turn stays under the budget; the progress handler's time is not the file's. }
procedure TTyRichEditControlTest.TestASlowFileGetsSmallerSlices;
var
  F: TForm;
begin
  F := HandleForm;
  try
    FRich.Slices(0, 256 * 1024);
    // no clock that moves: fast
    FRich.FrozenClock := True;
    FRich.LogSlices := True;
    LoadW8Big(40000);
    FRich.LogSlices := False;
    AssertEquals('the load''s own first slice asks no size', 0, Length(FRich.SliceLog));
    AssertEquals('turn 1 starts small', '16 16 16', TurnSizes);
    AssertEquals('turn 2', '32 32 32', TurnSizes);
    AssertEquals('turn 3', '64 64 64', TurnSizes);
    AssertEquals('turn 4', '128 128 128', TurnSizes);
    AssertEquals('turn 5: the whole step', '256 256 256', TurnSizes);
    AssertEquals('turn 6', '256 256 256', TurnSizes);
    AssertEquals('a step by hand: the whole step', Int64(256 * 1024), FRich.NextSlice);
    FRich.FrozenClock := False;
    // 4 KB a millisecond: a 16 KB slice takes 4 ms, the turn ends at the budget after two
    FRich.FakeRate := 4096;
    FRich.ClockNow := 0;
    LoadW8Big(40000);
    AssertEquals('a slow file: its first turn small too', '16 16', TurnSizes);
    AssertEquals('and the next', '16 16', TurnSizes);
    // a slow handler, a fast file: the handler's time is not the slices'
    FRich.FakeRate := 0;
    FRich.FakeClock := True;
    FRich.ClockStep := 0;
    FRich.OnLoadProgress := @SlowHandler;
    LoadW8Big(40000);
    // (the handler's 50 ms end each turn after its first slice, but do not size the slices)
    AssertEquals('a slow handler: turn 1', '16', TurnSizes);
    AssertEquals('a slow handler: turn 2 doubles', '32', TurnSizes);
    AssertEquals('a slow handler: turn 3 doubles', '64', TurnSizes);
    FRich.OnLoadProgress := nil;
    FRich.CancelLoad;
  finally
    FRich.FakeClock := False;
    FRich.FrozenClock := False;
    FRich.FakeRate := 0;
    FRich.OnLoadProgress := nil;
    FRich.Parent := nil;
    F.Free;
  end;
end;

{ N-4: one stalled turn (500 ms by the clock) halves the slice once, and fast turns bring it back
  to StepBytes; a steady slow rate settles - the size goes down a step a turn until its turns
  sit under the budget, and stays there (no flip-flop). }
procedure TTyRichEditControlTest.TestAStallCostsOneHalving;
var
  F: TForm;
  i: Integer;
  seq: string;
  load: TTyRtfLoad;
  b0, t0: Int64;
begin
  F := HandleForm;
  try
    FRich.Slices(0, 256 * 1024);
    // a fast file: 1 MB a millisecond
    FRich.FakeRate := 1024 * 1024;
    FRich.ClockNow := 0;
    LoadW8Big(200000);
    for i := 1 to 5 do TurnSizes;
    AssertEquals('fast: the whole step', '256 256 256', TurnSizes);
    // the next turn stalls 500 ms after its first slice
    FRich.StallMs := 500;
    FRich.StallReadings := 2;
    AssertEquals('the stalled turn: one slice (it went over the budget)', '256', TurnSizes);
    AssertEquals('after the stall: half', '128 128 128', TurnSizes);
    AssertEquals('one fast turn later: the whole step again', '256 256 256', TurnSizes);
    AssertEquals('and stays', '256 256 256', TurnSizes);
    // the file turns slow and steady: 20 KB a millisecond (a 256 KB slice takes 12.8 ms)
    FRich.FakeRate := 20 * 1024;
    seq := '';
    for i := 1 to 8 do
    begin
      if seq <> '' then seq := seq + ' | ';
      seq := seq + TurnSizes;
    end;
    AssertEquals('down a step a turn, then settled',
      '256 | 128 128 | 64 64 64 | 32 32 32 | 32 32 32 | 32 32 32 | 32 32 32 | 32 32 32', seq);
    // the settled turns sit under the budget
    load := TyRichRtfLoadOf(FRich.Document);
    b0 := load.BytesIndexed;
    TurnSizes;
    t0 := (load.BytesIndexed - b0) * 1000 div FRich.FakeRate;
    AssertTrue(Format('a settled turn is under the budget (%d us)', [t0]),
      t0 <= CRichIdleBudgetMs * 1000);
    FRich.CancelLoad;
  finally
    FRich.FakeRate := 0;
    FRich.StallReadings := 0;
    FRich.Parent := nil;
    F.Free;
  end;
end;

{ N-2: on the idle-driven widgetsets a slow timer runs beside the idle handler while there is
  work (CRichBackstopMs, made with the first start). Its tick (run by hand) runs no turn when a
  turn ran since its last tick; when none did (the idle step starved: an Application.OnIdle
  that sets Done := False) it runs exactly one, taking the queued call off first so that the
  two never follow each other; no work - no timer; a cancel, a new content, the window's going
  and the destructor take it away; the timer driver has none. }
procedure TTyRichEditControlTest.TestTheBackstopRunsATurnOnlyWhenTheIdleStepIsStarved;
var
  F: TForm;
  t, removes, posts: Int64;
begin
  F := HandleForm;
  try
    FRich.Slices(0, 16 * 1024);
    LoadW8Big(40000);
    AssertTrue('a backstop', FRich.BackstopOf <> nil);
    AssertTrue('running beside the idle handler', FRich.BackstopOf.Enabled and FRich.IdleOn);
    AssertEquals('its period', CRichBackstopMs, Integer(FRich.BackstopOf.Interval));
    // the idle path runs turns: the tick runs none
    t := FRich.Turns;
    RunQueuedCalls;
    AssertEquals('the queued turn ran', t + 1, FRich.Turns);
    t := FRich.Turns;
    FRich.BackstopNow;
    AssertEquals('a turn since the last tick: none', t, FRich.Turns);
    RunIdleHandlers;
    RunQueuedCalls;
    t := FRich.Turns;
    FRich.BackstopNow;
    AssertEquals('again: none', t, FRich.Turns);
    // starved: no turn since the last tick - exactly one a tick
    FRich.BackstopNow;
    AssertEquals('starved: one turn', t + 1, FRich.Turns);
    FRich.BackstopNow;
    AssertEquals('starved: one more a tick', t + 2, FRich.Turns);
    // a call queued by the idle step and not run: the tick's turn takes it off
    RunIdleHandlers;
    AssertTrue('a call waits', FRich.TurnQueued);
    removes := TRichProbe.Removes;
    posts := TRichProbe.Posts;
    FRich.BackstopNow;
    AssertEquals('starved again: one turn', t + 3, FRich.Turns);
    AssertFalse('the waiting call was taken off', FRich.TurnQueued);
    AssertEquals('off the queue', removes + 1, Int64(TRichProbe.Removes));
    AssertEquals('and nothing queued by the tick', posts, Int64(TRichProbe.Posts));
    RunQueuedCalls;
    AssertEquals('no turn follows it', t + 3, FRich.Turns);
    // no work: no timer, and a tick does nothing
    while FRich.Loading do FRich.BackstopNow;
    AssertFalse('no work left: the timer stops', FRich.BackstopOf.Enabled);
    t := FRich.Turns;
    FRich.BackstopNow;
    FRich.BackstopNow;
    AssertEquals('no work: no turn', t, FRich.Turns);
    // the removal paths
    LoadW7Plain;
    AssertTrue('running again', FRich.BackstopOf.Enabled);
    FRich.CancelLoad;
    AssertFalse('cancelled: stopped', FRich.BackstopOf.Enabled);
    LoadW7Plain;
    FRich.Lines.Text := 'another';
    AssertFalse('a new content: stopped', FRich.BackstopOf.Enabled);
    LoadW7Plain;
    FRich.DropHandle;
    AssertTrue('the window went: freed', FRich.BackstopOf = nil);
    FRich.HandleNeeded;
    AssertTrue('a window again: running', (FRich.BackstopOf <> nil) and FRich.BackstopOf.Enabled);
    // (the destructor frees it with the window and again itself: FreeAndNil below)
    FreeAndNil(FRich);
    FRich := NewProbe;
    FRich.Parent := F;
    FRich.HandleNeeded;
    // the timer driver has no backstop
    FRich.ForceTimer := True;
    LoadW7Plain;
    AssertTrue('the timer driver: no backstop', FRich.BackstopOf = nil);
    FRich.CancelLoad;
  finally
    if FRich <> nil then
    begin
      FRich.ForceTimer := False;
      FRich.Parent := nil;
    end;
    F.Free;
  end;
end;

{ N-7 (L-6): a slice appended below the view asks the view nothing (no layout, no settle) and
  walks the height tree a bounded number of times, the same at 10,000 paragraphs as at 800,000:
  nothing per slice is proportional to the document (bound: 16 visits a slice, an empirical
  one - see CRichSliceVisitBound). Each document is read in its synchronous
  first slice but the last 100 KB, which come in turns of 16 KB slices. }
procedure TTyRichEditControlTest.TestASlicesCostDoesNotGrowWithTheDocument;

  function VisitsPerSlice(AParas: Integer): Int64;
  var
    F: TForm;
    src: TBytes;
    dummy: Int64;
    st: TBytesStream;
    v0, slices: Int64;
    turns: Integer;
  begin
    FreeAndNil(FRich);
    FRich := NewProbe;
    F := HandleForm;
    try
      src := W5PlainRtf(AParas, dummy);
      FRich.Slices(Length(src) - 100 * 1024, 16 * 1024);
      st := TBytesStream.Create(src);
      try
        FRich.LoadFromStream(st);
      finally
        st.Free;
      end;
      src := nil;
      AssertTrue('loading', FRich.Loading);
      FRich.FrozenClock := True;
      PaintAll(True);
      FRich.ResetCounts;
      FRich.SliceLog := nil;
      FRich.LogSlices := True;
      v0 := FRich.Document.Text.NodeVisits;
      turns := 0;
      while FRich.Loading do
      begin
        FRich.Turn;
        Inc(turns);
        AssertTrue('runaway', turns < 1000);
      end;
      FRich.LogSlices := False;
      slices := Length(FRich.SliceLog);
      AssertTrue(Format('%d paragraphs: in slices (%d)', [AParas, slices]), slices >= 5);
      AssertEquals(Format('%d paragraphs: the slices asked for no layout', [AParas]), 0,
        Length(FRich.Given));
      AssertEquals(Format('%d paragraphs: laid out nothing', [AParas]), 0, FRich.LaidParas);
      AssertEquals(Format('%d paragraphs: drew nothing', [AParas]), 0, FRich.BlockPaints);
      Result := (FRich.Document.Text.NodeVisits - v0) div slices;
    finally
      FRich.Parent := nil;
      F.Free;
    end;
  end;

const
  { Empirical, not derived: twice the larger of the counts measured when it was written (5 and
    8). The tree is 64/128-ary, about 4 levels deep at 800,000 paragraphs: 16 allows a few
    walks from the root per slice and no walk proportional to the document. NodeVisits
    counts only the walks of Text.pas that increment it; a cost per slice that goes through
    another accessor would not show here. }
  CRichSliceVisitBound = 16;
var
  small, big: Int64;
begin
  small := VisitsPerSlice(10000);
  big := VisitsPerSlice(800000);
  AssertTrue(Format('tree visits a slice: %d at 10,000 paragraphs, %d at 800,000', [small, big]),
    (small <= CRichSliceVisitBound) and (big <= CRichSliceVisitBound));
end;

procedure TTyRichEditControlTest.RaiseOnce(Sender: TObject; ADone, ATotal: Int64;
  var ACancel: Boolean);
begin
  Inc(FLoadCalls);
  if FRaiseOnce then
  begin
    FRaiseOnce := False;
    raise EInvalidOperation.Create('the test''s failing progress handler');
  end;
end;

{ K-4: after a turn whose step raised (here: the load's progress handler, once) the driver stays
  on (the idle step goes on queuing turns), and the load runs to its end. }
procedure TTyRichEditControlTest.TestAStepThatRaisesDoesNotStrandTheLoad;
var
  F: TForm;
  raised: Boolean;
  turns: Integer;
begin
  F := HandleForm;
  try
    FRich.OnLoadProgress := @RaiseOnce;
    LoadW7Plain;
    FRaiseOnce := True;
    raised := False;
    try
      FRich.Turn;
    except
      on EInvalidOperation do raised := True;
    end;
    AssertTrue('the handler raised', raised);
    AssertTrue('still loading', FRich.Loading);
    AssertTrue('the driver stays on all the same', FRich.IdleOn);
    turns := 0;
    while FRich.Loading and FRich.IdleOn do
    begin
      RunIdleHandlers;
      RunQueuedCalls;
      Inc(turns);
      AssertTrue('runaway', turns < 10000);
    end;
    AssertFalse('loaded to the end', FRich.Loading);
    AssertFalse('the whole file', FRich.Document.Incomplete);
  finally
    FRich.Parent := nil;
    F.Free;
  end;
end;

{ K-10: a snap (a change left the caret inside a cluster) calls no handler where it runs: a
  paint and a public query only queue the report, which the queued call makes once; a key
  reports once, at its end; the destructor with the report queued reports nothing. }
procedure TTyRichEditControlTest.TestASnapReportsOutsideThePaintAndTheQuery;
var
  raised: Boolean;
  removes: Integer;

  procedure Prepare;
  begin
    FRich.OnSelectionChange := nil;
    FRich.Lines.Text := 'aXY' + Utf8Of($301) + 'z';
    FRich.UpdateView;
    FRich.SelStart := 2;
    RunQueuedCalls;
    FRich.OnSelectionChange := @SelChanged;
    AssertTrue(FRich.Document.Execute(TTyRichDelete.Create(1, 2)));
    FSelChanges := 0;
  end;

begin
  Prepare;
  PaintAll(True);
  AssertEquals('snapped by the paint', Int64(0), FRich.CaretIndex);
  AssertEquals('no handler inside the paint', 0, FSelChanges);
  AssertTrue('the report is queued', FRich.ReportQueued);
  RunQueuedCalls;
  AssertEquals('the queued call reports it', 1, FSelChanges);
  RunQueuedCalls;
  AssertEquals('once', 1, FSelChanges);
  // a public query
  Prepare;
  FRich.PositionRect(0);
  AssertEquals('snapped by the query', Int64(0), FRich.CaretIndex);
  AssertEquals('no handler inside the query', 0, FSelChanges);
  RunQueuedCalls;
  AssertEquals('reported after it', 1, FSelChanges);
  // a key: the snap at its start and its move are one action, one report at its end
  Prepare;
  FRich.Press(VK_RIGHT, []);
  AssertEquals('a key: one report', 1, FSelChanges);
  RunQueuedCalls;
  AssertEquals('and the queued call adds none', 1, FSelChanges);
  // the destructor with the report queued
  Prepare;
  FRich.CaretClientRect;
  AssertTrue('queued', FRich.ReportQueued);
  { freed memory is filled with a pattern meanwhile: a call left on the queue would read the
    freed control (its state, its handler) as that pattern - a fault, never a quiet skip }
  raised := False;
  removes := TRichProbe.Removes;
  PoisonFreedMemory(True);
  try
    FreeAndNil(FRich);
    try
      RunQueuedCalls;
    except
      raised := True;
    end;
  finally
    PoisonFreedMemory(False);
  end;
  AssertEquals('the destructor takes the report off the queue', removes + 1, TRichProbe.Removes);
  AssertFalse('freed: no call into it', raised);
  AssertEquals('freed: nothing reported', 0, FSelChanges);
  FRich := NewProbe;
end;

{ K-9: between Lines.BeginUpdate and EndUpdate, after paragraphs were removed, input that needs
  the layout does nothing (a viewer's key is still taken), the queries answer "not available",
  nothing raises and nothing is laid out; a replacement that keeps the length and the
  paragraph count (what a heuristic on those missed) is held back as well. }
procedure TTyRichEditControlTest.TestInputAndQueriesWaitForAnUpdate;
var
  i: Integer;
  c: TTyRichPos;
  top: Integer;
begin
  SetLinesOf(50, 'Line ');
  FRich.ForceFocus := True;
  PaintAll(True);
  FRich.SelStart := FRich.Document.Text.ParaStart(40) + 2;
  PaintAll(True);
  top := FRich.TopParagraph;
  FRich.Lines.BeginUpdate;
  try
    for i := 1 to 45 do FRich.Lines.Delete(0);
    // (the deletes moved the caret with its text, as they do outside an update)
    c := FRich.CaretIndex;
    FRich.ResetCounts;
    AssertEquals('Down is taken', 0, FRich.KeyResult(VK_DOWN, []));
    AssertEquals('Ctrl+End is taken', 0, FRich.KeyResult(VK_END, [ssCtrl]));
    AssertEquals('Ctrl+A is taken', 0, FRich.KeyResult(VK_A, [ssCtrl]));
    AssertEquals('Tab is still the form''s', VK_TAB, FRich.KeyResult(VK_TAB, []));
    AssertEquals('the keys moved nothing', c, FRich.CaretIndex);
    FRich.Wheel(-120, []);
    FRich.WheelH(120);
    AssertEquals('the wheel scrolled nothing', top, FRich.TopParagraph);
    FRich.PressAt(20, 20);
    AssertFalse('a press starts no drag', FRich.DragOn);
    AssertEquals('and places nothing', c, FRich.CaretIndex);
    FRich.MoveAt(30, 30);
    FRich.ReleaseAt(30, 30);
    AssertEquals('PositionAtPoint: not available', -1, FRich.PositionAtPoint(20, 20));
    AssertTrue('PositionRect: empty', IsRectEmpty(FRich.PositionRect(0)));
    AssertTrue('ParagraphRect: empty', IsRectEmpty(FRich.ParagraphRect(0)));
    AssertTrue('the caret''s rectangle: empty', IsRectEmpty(FRich.CaretClientRect));
    AssertTrue('the input method''s caret: empty', IsRectEmpty(FRich.ImeRect));
    AssertEquals('no visible block', 0, FRich.VisibleBlockCount);
    AssertEquals('ScrollY: not available', -1, FRich.ScrollY);
    FRich.ScrollViewBy(100);
    FRich.ScrollToEnd;
    FRich.ScrollY := 50;
    FRich.UpdateView;
    AssertEquals('the scrolls did nothing', top, FRich.TopParagraph);
    AssertEquals('nothing laid out', 0, Length(FRich.Given));
  finally
    FRich.Lines.EndUpdate;
  end;
  AssertEquals('five lines', 5, FRich.Document.Text.ParaCount);
  AssertTrue('blocks again', FRich.VisibleBlockCount > 0);
  AssertTrue('a caret rectangle again', not IsRectEmpty(FRich.CaretClientRect));
  // the same length, the same paragraphs
  PaintAll(True);
  FRich.Document.BeginUpdate;
  try
    AssertTrue(FRich.Document.Execute(TTyRichDelete.Create(0, 3)));
    AssertTrue(FRich.Document.Execute(TTyRichInsertText.Create(0, 'XYZ')));
    FRich.ResetCounts;
    PaintAll(True);
    AssertEquals('a same-length change: no block drawn', 0, FRich.BlockPaints);
    AssertEquals('nothing laid out', 0, Length(FRich.Given));
    AssertEquals('the input method''s query: nothing', -1, FRich.PositionAtPoint(20, 20));
  finally
    FRich.Document.EndUpdate;
  end;
  CheckSurface('after the same-length update');
end;

function CoversRect(const AOuter, AInner: TRect): Boolean;
begin
  Result := (AOuter.Left <= AInner.Left) and (AOuter.Top <= AInner.Top) and
    (AOuter.Right >= AInner.Right) and (AOuter.Bottom >= AInner.Bottom);
end;

{ K-11: a window paint inside the document's update draws nothing new, and the window counts it
  as done: when the update ends, the window is asked to paint the text window again - here
  with no block held before (a control first painted inside an update). An update with no
  paint inside it asks for nothing more than its change. }
procedure TTyRichEditControlTest.TestAPaintSkippedInAnUpdateIsMadeGood;
var
  i: Integer;
  hit: Boolean;
begin
  FRich.Lines.BeginUpdate;
  try
    for i := 0 to 9 do FRich.Lines.Add('Line ' + IntToStr(i));
    PaintAll(True);
    FRich.ResetCounts;
  finally
    FRich.Lines.EndUpdate;
  end;
  hit := False;
  for i := 0 to High(FRich.Invalidated) do
    if CoversRect(FRich.Invalidated[i], FRich.TextWindow) then hit := True;
  AssertTrue('after the update: the text window is painted again', hit);
  // no paint inside: nothing more (no block is held - the change asks for nothing)
  FRich.Lines.BeginUpdate;
  try
    FRich.Lines.Add('one more');
    FRich.ResetCounts;
  finally
    FRich.Lines.EndUpdate;
  end;
  AssertEquals('no skipped paint: no extra invalidation', 0, Length(FRich.Invalidated));
end;

{ K-6: Word's list (word-list.rtf) cancelled after its first slice, whose last paragraph is the
  item "2." after a body paragraph: the cancel's notice is the load's own - the item keeps the
  file's number (the walk would count "1."), no OnChange, the caret stays. }
procedure TTyRichEditControlTest.TestACancelNoticeIsTheLoadsOwn;
var
  st: TBytesStream;
  L: TTyBlockLayout;
begin
  st := TBytesStream.Create(ReadFixtureFile('word-list.rtf'));
  try
    FRich.Slices(AfterPars(st.Bytes, 3), 256);
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  AssertTrue('loading', FRich.Loading);
  FRich.SelStart := 1;
  FRich.OnChange := @Changed;
  FChanges := 0;
  FRich.CancelLoad;
  AssertTrue('cancelled', FRich.Document.Incomplete);
  AssertEquals('three paragraphs: the last the item', 3, FRich.Document.Text.ParaCount);
  AssertEquals('no OnChange for a cancel', 0, FChanges);
  AssertEquals('the caret stays', Int64(1), FRich.CaretIndex);
  L := FRich.Layouter.LayoutBlock(FRich.Document, 2, 1000, 96, 1);
  try
    AssertEquals('the item''s number is the file''s', '2.', string(TTyParaLayout(L).Marker.Text));
  finally
    L.Release;
  end;
end;

{ K-7 (with K-5): a partial row at the end of a loading and of a cancelled document. What a user
  gets from a copy is the file's whole row, the cells not in the text yet empty: the text has
  a tab for each of them, the RTF the row with those cells empty - the two flavours agree. }
procedure TTyRichEditControlTest.TestAPartialRowCopiesAsTheFilesRow;

  procedure Check(const AWhat: string; const ATail: string; const ACells: array of string);
  var
    b: TTyRichDocument;
    n, k: Integer;
    c: TTyRichCell;
  begin
    FRich.SelectAll;
    FRich.CopyToClipboard;
    AssertEquals(AWhat + ': the text is SelText', FRich.SelText, FRich.ClipText);
    AssertEquals(AWhat + ': the text ends with the row',
      ATail, Copy(FRich.ClipText, Length(FRich.ClipText) - Length(ATail) + 1, MaxInt));
    b := ReadClipRtf(FRich.ClipRtf);
    try
      n := b.Text.ParaCount;
      AssertTrue(AWhat + ': the RTF has the row', n >= 3);
      c := b.CellAt(n - 1);
      AssertTrue(AWhat + ': the RTF ends in a cell', c <> nil);
      AssertEquals(AWhat + ': the row''s cells', 3, c.Row.CellCount);
      for k := 0 to 2 do
      begin
        AssertTrue(Format('%s: RTF cell %d in the row', [AWhat, k]),
          (b.CellAt(n - 3 + k) <> nil) and (b.CellAt(n - 3 + k).Row = c.Row));
        AssertEquals(Format('%s: RTF cell %d', [AWhat, k]), ACells[k],
          string(b.Text.GetText(b.Text.ParaStart(n - 3 + k), b.Text.ParaLength(n - 3 + k))));
      end;
    finally
      b.Free;
    end;
  end;

begin
  LoadW7Table(6, 3);
  AssertTrue('loading', FRich.Loading);
  AssertEquals('the row''s first cell is last', 'r3 a',
    FRich.Lines[FRich.Lines.Count - 1]);
  // (a row's line ends it in the text, as every row's does)
  Check('loading', 'r3 a'#9#9 + LineEnding, ['r3 a', '', '']);
  FRich.CancelLoad;
  AssertTrue('cancelled', FRich.Document.Incomplete);
  Check('cancelled', 'r3 a'#9'r3 b'#9 + LineEnding, ['r3 a', 'r3 b', '']);
end;

{ K-5, the control: a row shown at the end of a loading document with only its first cell is
  laid out again, whole, when its other cells arrive - the slice's change starts at the
  paragraph that was last (the row's first cell), which the view hears. }
procedure TTyRichEditControlTest.TestARowShownWhileLoadingIsLaidOutWhole;
var
  last, k, steps: Integer;
  found: Boolean;
  blk: TTyRichViewBlock;
begin
  LoadW7Table(6, 3);
  AssertTrue('loading', FRich.Loading);
  last := FRich.Document.Text.ParaCount - 1;
  PaintAll(True);
  found := False;
  for k := 0 to FRich.VisibleBlockCount - 1 do
  begin
    blk := FRich.VisibleBlocks[k];
    if blk.LastPara = last then
    begin
      found := True;
      AssertEquals('shown with its first cell alone', last, blk.FirstPara);
    end;
  end;
  AssertTrue('the row is shown', found);
  steps := 0;
  while FRich.Loading do
  begin
    AssertTrue('a step', FRich.Step);
    Inc(steps);
    AssertTrue('runaway', steps < 10000);
  end;
  PaintAll(True);
  found := False;
  for k := 0 to FRich.VisibleBlockCount - 1 do
  begin
    blk := FRich.VisibleBlocks[k];
    if blk.FirstPara = last then
    begin
      found := True;
      AssertEquals('the whole row: one block', last + 2, blk.LastPara);
    end;
  end;
  AssertTrue('the row is shown again', found);
  for k := last to last + 2 do
    AssertTrue(Format('cell %d in the row', [k - last]),
      FRich.Document.CellAt(k).Row = FRich.Document.CellAt(last).Row);
  CheckSurface('the row laid out again');
end;

{ K-12: a press on either half of a picture and a 1 px move keep the anchor at the picture's
  start: a Shift+click after it then keeps the picture in the selection. }
procedure TTyRichEditControlTest.TestAPressedObjectKeepsItsAnchor;
var
  r1, r2: TRect;
  y, x, half: Integer;
  p: TPoint;
begin
  PictureDoc(1);
  PaintAll(True);
  r1 := FRich.PositionRect(1);
  r2 := FRich.PositionRect(2);
  y := (r1.Top + r1.Bottom) div 2;
  for half := 0 to 1 do
  begin
    if half = 0 then x := r1.Left + 3 else x := r2.Left - 3;
    Click(At(0));
    FRich.PressAt(x, y);
    FRich.MoveAt(x + 1, y);
    FRich.ReleaseAt(x + 1, y);
    AssertEquals(Format('half %d: the picture', [half]), Int64(1), FRich.SelStart);
    AssertEquals(Format('half %d: its character', [half]), Int64(1), FRich.SelLength);
    p := At(3);
    FRich.PressAt(p.X, p.Y, [ssShift]);
    FRich.ReleaseAt(p.X, p.Y);
    AssertEquals(Format('half %d: a Shift+click after it keeps it', [half]), Int64(1), FRich.SelStart);
    AssertEquals(Format('half %d: to the click', [half]), Int64(2), FRich.SelLength);
  end;
end;

{ K-2: in window-wrap mode the horizontal extent is the widest content that does not wrap, never
  the wrap width: text that wraps to the window shows no horizontal bar at any zoom, also after
  200 -> 50 -> 100 (the smoke's sequence); a row wider than the window brings the bar, its
  extent follows the zoom up and down and comes back to its first value; page mode scrolls over
  the page's width. }
procedure TTyRichEditControlTest.TestTheExtentIsTheContentNotTheWrapWidth;
var
  s: string;
  i, tw, e1, e: Integer;

  procedure NoBar(const AWhat: string);
  begin
    FRich.UpdateView;
    tw := FRich.Area.Right - FRich.Area.Left;
    AssertTrue(Format('%s: the extent (%d) within the text width (%d)',
      [AWhat, FRich.HorizontalExtent, tw]), FRich.HorizontalExtent <= tw);
    AssertTrue(AWhat + ': no horizontal bar', (FRich.HBar = nil) or not FRich.HBar.Visible);
  end;

  function Near(A, B, ATol: Integer): Boolean;
  begin
    Result := Abs(A - B) <= ATol;
  end;

begin
  // the content's width, not the window's
  FRich.Lines.Text := 'short';
  NoBar('a short line');
  AssertTrue(Format('the extent is the line''s (%d of %d)', [FRich.HorizontalExtent, tw]),
    FRich.HorizontalExtent < tw div 2);
  s := '';
  for i := 1 to 80 do s := s + 'word ';
  FRich.Lines.Text := s + #10 + s + #10 + s;
  NoBar('100%');
  FRich.Zoom := 150;
  NoBar('150%');
  FRich.Zoom := 200;
  NoBar('200%');
  FRich.Zoom := 50;
  NoBar('200 -> 50%');
  FRich.Zoom := 100;
  NoBar('200 -> 50 -> 100%');
  // a row of 800 px (12000 twips) in the same window
  LoadRtfText('{\rtf1\ansi\deff0{\fonttbl{\f0 Arial;}}\pard\f0\fs20 before\par' +
    '\trowd\cellx3000\cellx12000\pard\intbl a\cell b\cell\row\pard after\par}');
  FRich.Zoom := 100;
  FRich.UpdateView;
  tw := FRich.Area.Right - FRich.Area.Left;
  e1 := FRich.HorizontalExtent;
  AssertTrue(Format('the row is wider than the window (%d, %d)', [e1, tw]), e1 > tw);
  AssertTrue('a horizontal bar', (FRich.HBar <> nil) and FRich.HBar.Visible);
  FRich.Zoom := 200;
  FRich.UpdateView;
  e := FRich.HorizontalExtent;
  AssertTrue(Format('200%%: twice as wide (%d, was %d)', [e, e1]), Near(e, 2 * e1, 4));
  AssertTrue('200%: the bar', (FRich.HBar <> nil) and FRich.HBar.Visible);
  FRich.Zoom := 70;
  FRich.UpdateView;
  e := FRich.HorizontalExtent;
  AssertTrue(Format('70%%: narrower (%d, was %d)', [e, e1]), Near(e, Round(0.7 * e1), 4));
  FRich.Zoom := 100;
  FRich.UpdateView;
  AssertTrue(Format('100%% again: the first extent (%d, was %d)', [FRich.HorizontalExtent, e1]),
    Near(FRich.HorizontalExtent, e1, 1));
  // the page: its text width, wider than this window
  FRich.Lines.Text := 'short';
  FRich.WrapMode := rwmPage;
  FRich.UpdateView;
  e := TyRichLayoutWidth(rwmPage, 1, FRich.Document, 96, 1);
  AssertTrue(Format('page mode: the page''s width (%d, page %d)', [FRich.HorizontalExtent, e]),
    Near(FRich.HorizontalExtent, e, 1));
  FRich.WrapMode := rwmWindow;
end;

{ K-2 / H2-M8: a horizontal position survives a zoom at the same fraction (of the extent: the
  same column stays at the left edge) where there is still something to scroll, and is 0
  where there is not. }
procedure TTyRichEditControlTest.TestTheColumnSurvivesAZoomWhereItCanScroll;
var
  e1, x1, tw: Integer;
begin
  LoadRtfText('{\rtf1\ansi\deff0{\fonttbl{\f0 Arial;}}\pard\f0\fs20 before\par' +
    '\trowd\cellx3000\cellx12000\pard\intbl a\cell b\cell\row\pard after\par}');
  FRich.UpdateView;
  tw := FRich.Area.Right - FRich.Area.Left;
  e1 := FRich.HorizontalExtent;
  FRich.HBar.Position := (e1 - tw) div 2;
  x1 := FRich.ScrollX;
  AssertTrue('scrolled across', x1 > 0);
  FRich.Zoom := 200;
  FRich.UpdateView;
  // the same column at the left edge: the same fraction of the extent
  AssertTrue(Format('200%%: the same fraction (%d of %d, was %d of %d)',
    [FRich.ScrollX, FRich.HorizontalExtent, x1, e1]),
    Abs(FRich.ScrollX / FRich.HorizontalExtent - x1 / e1) < 0.02);
  // wrapped text only: nothing to scroll, the position is 0
  FRich.Lines.Text := 'short';
  FRich.UpdateView;
  AssertEquals('nothing to scroll: 0', 0, FRich.ScrollX);
end;

{ K-3: what a jump costs in a document of 1,000,000 lines, by counters (no clock): block
  layouts asked for (and new ones), tree node visits, for Ctrl+End, Ctrl+Home and PgDn, the key
  and the paint after it. A jump lays out the screen it arrives at with the screen the view holds
  above and below it (what LayoutView holds); the counts are written out for the report. }
procedure TTyRichEditControlTest.TestAJumpLaysOutOnlyTheViewItArrivesAt;
var
  ms: TMemoryStream;
  line: RawByteString;
  i: Integer;

  procedure Measure(const AWhat: string; AKey: Word; AShift: TShiftState);
  var
    v0, kv, pv: Int64;
    kGiven, kNew, pGiven, pNew, held: Integer;
  begin
    PaintAll(True);
    FRich.ResetCounts;
    v0 := FRich.Document.Text.NodeVisits;
    FRich.Press(AKey, AShift);
    kGiven := Length(FRich.Given);
    kNew := FRich.LaidParas;
    kv := FRich.Document.Text.NodeVisits - v0;
    FRich.ResetCounts;
    v0 := FRich.Document.Text.NodeVisits;
    PaintAll(True);
    pGiven := Length(FRich.Given);
    pNew := FRich.LaidParas;
    pv := FRich.Document.Text.NodeVisits - v0;
    held := FRich.VisibleBlockCount;
    WriteLn(Format('K-3 %s: key: %d layouts asked, %d new, %d tree visits; paint: %d asked, ' +
      '%d new, %d tree visits; the view holds %d blocks', [AWhat, kGiven, kNew, kv, pGiven, pNew,
      pv, held]));
    // the key lays out at most the view it arrives at (a screen above and below included),
    // and the paint after it nothing new
    AssertTrue(Format('%s: the key laid out %d new blocks, the view holds %d', [AWhat, kNew, held]),
      kNew <= held + 2);
    AssertEquals(AWhat + ': the paint lays out nothing new', 0, pNew);
  end;

begin
  FRich.SetBounds(0, 0, 1200, 800);
  ms := TMemoryStream.Create;
  try
    for i := 0 to 999999 do
    begin
      line := 'Line ' + IntToStr(i) + ' of the counted document, with some words in it.' + #10;
      ms.WriteBuffer(line[1], Length(line));
    end;
    ms.Position := 0;
    FRich.LoadFromStream(ms, rfText);
  finally
    ms.Free;
  end;
  AssertTrue('a million lines', FRich.Document.Text.ParaCount >= 1000000);
  FRich.UpdateView;
  Measure('Ctrl+End', VK_END, [ssCtrl]);
  Measure('Ctrl+Home', VK_HOME, [ssCtrl]);
  Measure('PgDn 1', VK_NEXT, []);
  Measure('PgDn 2', VK_NEXT, []);
  Measure('Ctrl+End again', VK_END, [ssCtrl]);
  Measure('PgUp at the end', VK_PRIOR, []);
end;

{ W10: the range the vertical bar ought to have now: the document's height less a page (a bar
  unit is a pixel here: the document is far below ScrollBarLimit). }
function TTyRichEditControlTest.BarMaxWanted: Integer;
begin
  Result := FRich.Document.Text.TotalHeight div FRich.Scale - FRich.VBar.PageSize;
end;

{ P-1: while a load runs, the range its own turns give the vertical bar reaches the bar at most
  once per CRichLoadBarsMs (100) of the turns' clock: the first turn's at once; the next turns'
  within the interval not (the document grows, the bar's Max stands); the first turn after it
  again, and the interval runs from there. What is not the load's own slice reaches the bar at
  once: a scroll by the user in the middle of the load, an edit after it. The load's end gives
  the bar the whole document's range, though its turns came within one interval. }
procedure TTyRichEditControlTest.TestTheLoadsTurnsSetTheBarOncePerInterval;
var
  F: TForm;
  m, i, turns: Integer;
  h: Int64;
begin
  F := HandleForm;
  try
    FRich.Slices(0, 16 * 1024);
    LoadW8Big(40000);
    PaintAll(True);
    // a clock of the test's that stands between the turns
    FRich.FakeClock := True;
    FRich.ClockStep := 0;
    FRich.ClockNow := 1000;
    FRich.Turn;
    AssertTrue('loading', FRich.Loading);
    AssertTrue('a scroll bar', (FRich.VBar <> nil) and FRich.VBar.Visible);
    AssertEquals('the load''s first turn: its range reaches the bar', BarMaxWanted, FRich.VBar.Max);
    m := FRich.VBar.Max;
    for i := 1 to 3 do
    begin
      Inc(FRich.ClockNow, 30);
      h := FRich.Document.Text.TotalHeight;
      FRich.Turn;
      AssertTrue(Format('turn %d: the document grew', [i]), FRich.Document.Text.TotalHeight > h);
      AssertEquals(Format('turn %d, %d ms after: the bar as it was', [i, 30 * i]), m,
        FRich.VBar.Max);
    end;
    AssertTrue('still loading', FRich.Loading);
    Inc(FRich.ClockNow, 10);
    FRich.Turn;
    AssertEquals('100 ms after: the range reaches the bar', BarMaxWanted, FRich.VBar.Max);
    m := FRich.VBar.Max;
    Inc(FRich.ClockNow, 50);
    FRich.Turn;
    AssertEquals('the interval runs from the last time: the bar as it was', m, FRich.VBar.Max);
    AssertTrue('behind the document', BarMaxWanted <> m);
    // a scroll by the user in the middle of the load: at once, no turn between
    FRich.Wheel(-120, []);
    FRich.UpdateView;
    AssertEquals('a scroll: the range at once', BarMaxWanted, FRich.VBar.Max);
    AssertTrue('and the position', FRich.VBar.Position > 0);
    // the rest within the interval (the clock stands): the end gives the whole range
    m := FRich.VBar.Max;
    turns := 0;
    while FRich.Loading do
    begin
      FRich.Turn;
      Inc(turns);
      AssertTrue('runaway', turns < 10000);
    end;
    AssertTrue(Format('turns to the end (%d)', [turns]), turns >= 2);
    AssertFalse('read whole', FRich.Document.Incomplete);
    AssertTrue('the turns held the bar back', BarMaxWanted <> m);
    AssertEquals('the load''s end: the whole document''s range', BarMaxWanted, FRich.VBar.Max);
    // no load: an edit reaches the bar at once, the clock standing still
    m := FRich.VBar.Max;
    AssertTrue(FRich.Document.Execute(TTyRichDelete.Create(0, 20000)));
    AssertTrue('the edit took paragraphs away', BarMaxWanted <> m);
    AssertEquals('an edit: the range at once', BarMaxWanted, FRich.VBar.Max);
  finally
    FRich.FakeClock := False;
    FRich.Parent := nil;
    F.Free;
  end;
end;

procedure TTyRichEditControlTest.RaiseOnLoadEnd(Sender: TObject; const AChange: TTyRichChange);
begin
  if not FRich.Document.Loading and FRich.Document.Incomplete then
  begin
    Inc(FLoadEnds);
    raise Exception.Create('W10: the user''s change handler');
  end;
end;

{ P-2: a load whose next turn cannot be scheduled ends as a cancel ends it, under no handler of
  the control's: an exception from a user's change handler in that end reaches the caller of
  the entry point that ran it - LoadFromStream, when the load's first turn could not be queued;
  the idle step, when the end was owed from InitializeWnd (a window made for a load running
  without one), where nothing is heard: the load runs until then. Either way the load has
  ended, Incomplete, and the next idle step stops the driver. }
procedure TTyRichEditControlTest.TestAnOwedLoadEndRaisesFromItsEntryPoint;
const
  Msg = 'W10: the user''s change handler';
var
  F: TForm;
  raised: string;
begin
  F := HandleForm;
  FDocNotice := FRich.Document.OnChange;
  try
    FRich.Document.OnChange := @RaiseOnLoadEnd;
    FLoadEnds := 0;
    FRich.FailPost := True;
    raised := '';
    try
      LoadW7Plain(False);
    except
      on E: Exception do raised := E.Message;
    end;
    FRich.FailPost := False;
    AssertEquals('the load''s start: the handler''s exception reached the caller', Msg, raised);
    AssertEquals('the load''s end, once', 1, FLoadEnds);
    AssertFalse('not loading', FRich.Loading);
    AssertTrue('incomplete', FRich.Document.Incomplete);
    FRich.Document.OnChange := FDocNotice;
    RunIdleHandlers;
    AssertFalse('the next idle step: nothing registered', FRich.IdleOn);
    // owed from InitializeWnd
    LoadW7Plain;
    FRich.DropHandle;
    AssertTrue('loading without a window', FRich.Loading);
    FRich.Document.OnChange := @RaiseOnLoadEnd;
    FLoadEnds := 0;
    FRich.FailPost := True;
    FRich.HandleNeeded;
    FRich.FailPost := False;
    AssertEquals('InitializeWnd: nothing heard', 0, FLoadEnds);
    AssertTrue('the load runs until the next entry point', FRich.Loading);
    AssertTrue('the idle step is registered for it', FRich.IdleOn);
    raised := '';
    try
      RunIdleHandlers;
    except
      on E: Exception do raised := E.Message;
    end;
    AssertEquals('the idle step: the handler''s exception reached its caller', Msg, raised);
    AssertEquals('the load''s end, once', 1, FLoadEnds);
    AssertFalse('not loading after the idle step', FRich.Loading);
    AssertTrue('incomplete after the idle step', FRich.Document.Incomplete);
    FRich.Document.OnChange := FDocNotice;
    RunIdleHandlers;
    AssertFalse('then: nothing registered', FRich.IdleOn);
  finally
    FRich.Document.OnChange := FDocNotice;
    FRich.FailPost := False;
    FRich.Parent := nil;
    F.Free;
  end;
end;

{ The control in the form designer (csDesigning, on a window): entering it starts no caret
  blink, a key, a typed character and a press edit, move and select nothing, a drag starts no
  timer, and a load that has work left for the background (what code could do there) queues
  no turn, registers no idle handler and makes no timer - a form file holds no content, so
  nothing there loads. A composition is a read-only one's. }
procedure TTyRichEditControlTest.TestInTheDesignerNothingRunsAndNothingIsTyped;
var
  F: TForm;
  watches, posts: Integer;
  text: string;
begin
  FRich.MakeDesigning;
  F := HandleForm;
  try
    AssertTrue('designing', csDesigning in FRich.ComponentState);
    FRich.Lines.Text := 'abc'#13#10'def';
    FRich.SelStart := 1;
    text := FRich.Text;
    watches := TRichProbe.Watches;
    posts := TRichProbe.Posts;
    FRich.Enter;
    AssertTrue('entering: no blink timer', FRich.BlinkTimerOf = nil);
    AssertEquals('Delete: the key is the designer''s', VK_DELETE, FRich.KeyResult(VK_DELETE, []));
    AssertEquals('Right: the same', VK_RIGHT, FRich.KeyResult(VK_RIGHT, []));
    AssertEquals('Ctrl+A: the same', VK_A, FRich.KeyResult(VK_A, [ssCtrl]));
    FRich.TypeChar('x');
    AssertEquals('nothing typed or deleted', text, FRich.Text);
    AssertEquals('the caret did not move', 1, FRich.SelStart);
    AssertEquals('nothing selected', 0, FRich.SelLength);
    FRich.PressAt(20, 20);
    AssertFalse('a press starts no drag', FRich.DragOn);
    FRich.MoveAt(20, FRich.Height + 5);
    AssertTrue('no drag timer', FRich.DragTimerOf = nil);
    FRich.ReleaseAt(20, FRich.Height + 5);
    AssertEquals('the press placed nothing', 1, FRich.SelStart);
    AssertTrue('a composition is a read-only one''s', FRich.ImeIsReadOnly);
    // a change from code leaves the caret before a combining mark: the query snaps it, and
    // the report a running application gets later is not queued here
    FRich.Lines.Text := 'aXY' + Utf8Of($301) + 'z';
    FRich.UpdateView;
    FRich.SelStart := 2;
    AssertTrue(FRich.Document.Execute(TTyRichDelete.Create(1, 2)));
    FRich.PositionRect(0);
    AssertEquals('the caret was snapped', Int64(0), FRich.CaretIndex);
    AssertFalse('no selection report queued', FRich.ReportQueued);
    AssertEquals('nothing queued', posts, TRichProbe.Posts);
    LoadW7Plain(True);
    AssertFalse('a load: no turn queued', FRich.TurnQueued);
    AssertEquals('no idle handler', watches, TRichProbe.Watches);
    AssertEquals('nothing queued at all', posts, TRichProbe.Posts);
    AssertTrue('no turn timer', FRich.TimerOf = nil);
    AssertTrue('no backstop timer', FRich.BackstopOf = nil);
    FRich.FinishLoading;
    AssertFalse('read to the end by code', FRich.Loading);
    AssertEquals('still nothing queued', posts, TRichProbe.Posts);
  finally
    FRich.Parent := nil;
    F.Free;
  end;
end;

{ What a form file holds: a fresh control writes only its bounds (and TabOrder on a parent);
  content set through Lines or Text is not written (Lines is not published); PlainText,
  ReadOnly, Zoom, WantTabs and WrapMode set before any document exists round-trip. }
procedure TTyRichEditControlTest.TestAFormFileHoldsNoContentAndItsSettingsRoundTrip;
const
  Allowed: array[0..4] of string = ('Left', 'Top', 'Width', 'Height', 'TabOrder');
var
  F: TForm;
  a, b: TTyRichEdit;
  ms: TMemoryStream;
  sl: TStringList;
  i, k, eq: Integer;
  name: string;
  ok: Boolean;
begin
  NeedWidgetSet;
  F := TForm.CreateNew(nil);
  a := TTyRichEdit.Create(F);
  b := TTyRichEdit.Create(nil);
  ms := TMemoryStream.Create;
  sl := TStringList.Create;
  try
    a.Parent := F;
    AssertEquals('the default width', 320, a.Width);
    AssertEquals('the default height', 240, a.Height);
    sl.Text := FormText(a);
    for i := 0 to sl.Count - 1 do
    begin
      eq := Pos(' = ', sl[i]);
      if eq = 0 then Continue;
      name := Trim(Copy(sl[i], 1, eq - 1));
      ok := False;
      for k := 0 to High(Allowed) do
        if name = Allowed[k] then ok := True;
      AssertTrue('a fresh control writes ' + name, ok);
    end;
    a.Lines.Text := 'first'#13#10'second';
    a.SelStart := 2;
    AssertFalse('no content in the form file: Lines', Pos('Lines', FormText(a)) > 0);
    AssertFalse('...nor the text', Pos('first', FormText(a)) > 0);
    a.PlainText := True;
    a.ReadOnly := True;
    a.Zoom := 150;
    a.WantTabs := True;
    a.WrapMode := rwmNone;
    ms.WriteComponent(a);
    ms.Position := 0;
    ms.ReadComponent(b);
    AssertTrue('PlainText', b.PlainText);
    AssertTrue('ReadOnly', b.ReadOnly);
    AssertEquals('Zoom', 150, b.Zoom);
    AssertTrue('WantTabs', b.WantTabs);
    AssertEquals('WrapMode', Ord(rwmNone), Ord(b.WrapMode));
    AssertEquals('read back without content', 0, b.Document.Text.Length);
    AssertFalse('nothing to undo', b.Document.CanUndo);
    AssertFalse('not modified', b.Modified);
    // the PlainText read from the form acts as one set by the user: an RTF file loads as text
    b.LoadFromFile(TempFile('streamed.rtf',
      BytesOf('{\rtf1\ansi\deff0{\fonttbl{\f0 Arial;}}\pard\f0 Text.\par}')));
    b.FinishLoading;
    AssertEquals('the streamed PlainText: an RTF file read as text', '{\rtf1',
      Copy(b.Lines[0], 1, 6));
    AssertTrue('...and still plain', b.PlainText);
  finally
    sl.Free;
    ms.Free;
    b.Free;
    F.Free;
  end;
end;

initialization
  RegisterTest(TTyRichEditControlTest);

end.
