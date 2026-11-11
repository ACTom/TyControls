unit test.tabstrip.states;
{ TTyCustomTabStrip: per-tab state -- modified, preview, pinned, hint, ink -- supplied by
  OnGetTabState, and middle-click close.

  Three things are guarded here more than any single answer:

    * the slot is ONE rect: what TabSlotRect names is where the mark is painted and where a
      click acts, on every band edge and mirrored;
    * what the slot SHOWS and what a click on it DOES are two rules -- the first follows the
      pointer (a modified tab's dot gives way to the close glyph under it), the second never
      does (a pin does not close, wherever the pointer was before);
    * nothing the event answered is kept: the handlers here answer BY CAPTION, so an answer
      remembered by index is wrong the moment a tab moves or goes. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, TypInfo, Controls, Forms, Graphics, LCLType,
  BGRABitmap, BGRABitmapTypes, ComCtrls,
  fpcunit, testregistry,
  tyControls.Types, tyControls.Controller, tyControls.Painter,
  tyControls.TabStrip, tyControls.PageControl, tyControls.TabSheet, tyControls.TabSet,
  test.tabstrip, test.tabstrip.axis;
type
  TStateStrip = class(TAxisStrip)
  protected
    procedure TabsChanged; override;
  public
    ChangedCalls: Integer;
    procedure RemoveTabForStates(AIndex: Integer);
    property OnShowHint;
  end;

  { An OnShowHint handler that marks what it was handed, to show it still gets its turn. }
  THintMarker = class
  public
    procedure Handle(Sender: TObject; HintInfo: PHintInfo);
  end;

  { Answers OnGetTabState by CAPTION: a caption listed in ModifiedCaps ('|Beta|Gamma|') is
    modified, and so on. Keyed by caption so that a strip which remembered an answer by index
    is caught out by a reorder or a close. }
  TStateProbe = class
  public
    Calls: Integer;
    ModifiedCaps, PinnedCaps, PreviewCaps, InkCaps: string;
    Ink: TTyColor;
    HintPrefix: string;      // '' = no hints; else the hint is HintPrefix + caption
    HintCaps: string;        // '' = every tab has one; else only the captions listed
    PreviewIndex: Integer;   // one tab by index, for twins that share a caption; -1 = none
    constructor Create;
    procedure Handle(Sender: TObject; AIndex: Integer; var AState: TTyTabState);
  end;

  { The two published strips, with their mouse reachable. }
  TStateTabSet = class(TTyTabSet)
  public
    procedure Press(ABtn: TMouseButton; const APt: TPoint);
    procedure Release(ABtn: TMouseButton; const APt: TPoint);
    procedure MoveTo(const APt: TPoint; AShift: TShiftState = []);
  end;

  TStatePager = class(TTyPageControl)
  public
    procedure Press(ABtn: TMouseButton; const APt: TPoint);
    procedure Release(ABtn: TMouseButton; const APt: TPoint);
  end;

  TPinProbe = class
  public
    Count, LastIndex: Integer;
    constructor Create;
    procedure Handle(Sender: TObject; AIndex: Integer);
  end;

  TTabStatesTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FStrip: TStateStrip;
    FProbe: TStateProbe;
    FClose: TStripCloseProbe;
    FPin: TPinProbe;
    procedure Build(AClosable: Boolean; APos: TTabPosition = tpTop; ARtl: Boolean = False;
      const ACss: string = '');
    function  Shot: TBGRABitmap;
    { The centre of a rect, and a point on the tab's caption (well clear of the slot). }
    function  Mid(const R: TRect): TPoint;
    function  OnCaption(AIndex: Integer): TPoint;
    procedure Hover(AIndex: Integer);
    procedure Click(const APt: TPoint; ABtn: TMouseButton = mbLeft);
    { Which pixels of the slot carry ink, as rows of '#' and '.', relative to the slot --
      so the marks of two tabs can be compared wherever the tabs are. }
    function  SlotMask(AIndex: Integer): string;
    function  InkBounds(bmp: TBGRABitmap; const AWithin: TRect): TRect;
    { Two more tabs that share one caption, at 3 and 4, on a strip wide enough that nothing
      overflows: whatever differs between them is the state of one of them. }
    procedure AddTwins;
    function  TabWidth(AIndex: Integer): Integer;
    { The ink inside a tab, relative to the tab. }
    function  TabMask(AIndex: Integer): string;
    { How far the top row of a tab's ink starts to the right of its bottom row: 0 for upright
      capitals, positive for slanted ones. }
    function  Slant(AIndex: Integer): Integer;
    { Pixels of ARect that are clearly green -- an ink no theme rule here gives. }
    function  GreenIn(const ARect: TRect): Integer;
    { Five tabs on a strip they fit on: Alpha Beta Gamma Delta Epsilon. }
    procedure BuildFive;
    function  Order: string;
    { Press on tab AFrom's caption, carry it to x = AToX along the band, let go. }
    procedure Drag(AFrom, AToX: Integer);
    { What LCL would be told to show at APt: the text, the rect to ask again on leaving. }
    function  AskHint(const APt: TPoint; out ARect: TRect): string;
    function  TouchesATab(const ARect: TRect): Boolean;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { --- the event --------------------------------------------------------------------- }
    procedure StateComesFromTheEventAndIsNothingWithoutOne;
    procedure StateIsAskedEveryTimeAndNeverKept;
    procedure StateFollowsItsTabThroughAReorderAndAClose;
    procedure InvalidateTabStatesTakesTheTabsChangedPath;
    { --- the slot ---------------------------------------------------------------------- }
    procedure AModifiedOrPinnedTabHasASlotWithoutCloseButtons;
    procedure TheSlotIsWhereTheCloseGlyphWouldBe;
    procedure TheSlotShowsDotPinOrCloseForEveryCombination;
    procedure TheSlotPaintsTheMarkItNames;
    procedure TheSlotHitRectIsThePaintedRectOnEveryBand;
    procedure TheSlotFollowsItsTabWhenTheStripScrollsOrFolds;
    procedure TheCaptionStepsAsideForTheSlot;
    { --- clicks ------------------------------------------------------------------------ }
    procedure AClickOnThePinFiresOnTabPinClickAndDoesNotClose;
    procedure APinWithoutAHandlerDoesNothing;
    procedure TheDotTurnsIntoCloseUnderThePointerAndCloses;
    procedure ADotWithoutCloseButtonsIsPartOfTheTab;
    procedure TheSlotHoverFollowsWhatAClickWouldDo;
    { --- middle click ------------------------------------------------------------------ }
    procedure MiddleClickClosesOnReleaseThroughOnTabClose;
    procedure MiddleClickHonoursTheVeto;
    procedure MiddleClickNeedsTheReleaseOnTheSameTab;
    procedure MiddleClickNeedsClosingEnabled;
    procedure MiddleClickLeavesAPinnedTab;
    procedure MiddleClickCloseCanBeSwitchedOff;
    { --- preview ----------------------------------------------------------------------- }
    procedure APreviewCaptionIsItalicInTheBuiltInTheme;
    procedure ThePreviewFontStyleIsTheThemesToken;
    procedure ThePreviewLookIsAVariantOfTheTabStyle;
    procedure APreviewCaptionIsMeasuredWithTheFontItIsDrawnIn;
    procedure APreviewTabFadesBetweenItsOwnLooks;
    { --- ink --------------------------------------------------------------------------- }
    procedure TextColorInksTheCaptionAndTheDot;
    procedure TextColorLeavesTheCloseGlyphAndThePinToTheTheme;
    procedure TextColorIsNotUsedOnADisabledStrip;
    procedure TheDotIsAsLargeAsTheThemeSays;
    { --- the order stays the host's; a drag keeps a pinned block whole ----------------- }
    procedure PinnedDropIndexStopsAtThePinnedBoundary;
    procedure ADragDoesNotCarryAnUnpinnedTabInFrontOfAPinnedOne;
    procedure ADragDoesNotCarryAPinnedTabBehindAnUnpinnedOne;
    procedure WithoutPinnedTabsADragGoesWhereItIsTaken;
    procedure TheStripNeverReordersByItself;
    { --- hints ------------------------------------------------------------------------- }
    procedure TheHintOverATabIsThatTabsOwn;
    procedure ATabWithoutAHintShowsTheStripsAndStillAsksAgainOnLeaving;
    procedure OffTheTabsTheHintRectReachesNoTab;
    procedure OnShowHintStillHasTheLastWord;
    { --- the two published strips ------------------------------------------------------ }
    procedure TabSetAndPageControlPublishTheStateMembers;
    procedure ATabSetOfStringsCarriesStates;
    procedure APageControlCarriesStates;
  end;

implementation

const
  { One ink, one ground, no hover or selected look of its own: a mark is then the only thing
    that can differ between two tabs' slots. Square, borderless tabs keep rects exact. }
  StateCss =
    'TyTabControl  { background: #FFFFFF; border-width: 0px; border-radius: 0px; }' +
    'TyPageControl { background: #FFFFFF; border-width: 0px; border-radius: 0px; }' +
    'TyTabSet      { background: #FFFFFF; border-width: 0px; border-radius: 0px; }' +
    'TyTabSheet    { background: #FFFFFF; border-width: 0px; border-radius: 0px; }' +
    'TyTab         { background: #FFFFFF; color: #101010; font-size: 12px; ' +
                    'border-width: 0px; border-radius: 0px; }' +
    'TyTabClose    { background: #FFFFFF; border-radius: 0px; }';
  { The built-in metrics the slot is laid out with (logical px = device px at 96). }
  CloseSize = 14;
  CloseGap  = 6;
  CloseMargin = 6;
  AllPositions: array[0..3] of TTabPosition = (tpTop, tpBottom, tpLeft, tpRight);

function Listed(const AList, ACaption: string): Boolean;
begin
  Result := Pos('|' + ACaption + '|', AList) > 0;
end;

{ TStateStrip }

procedure TStateStrip.TabsChanged;
begin
  Inc(ChangedCalls);
  inherited TabsChanged;
end;

procedure TStateStrip.RemoveTabForStates(AIndex: Integer);
begin
  RemoveTabData(AIndex);
end;

{ TStateProbe }

constructor TStateProbe.Create;
begin
  inherited Create;
  PreviewIndex := -1;
end;

procedure TStateProbe.Handle(Sender: TObject; AIndex: Integer; var AState: TTyTabState);
var
  cap: string;
begin
  Inc(Calls);
  cap := (Sender as TTyCustomTabStrip).TabCaption(AIndex);
  if Listed(ModifiedCaps, cap) then AState.Modified := True;
  if Listed(PinnedCaps, cap) then AState.Pinned := True;
  if Listed(PreviewCaps, cap) or (AIndex = PreviewIndex) then AState.Preview := True;
  if Listed(InkCaps, cap) then AState.TextColor := Ink;
  if (HintPrefix <> '') and ((HintCaps = '') or Listed(HintCaps, cap)) then
    AState.Hint := HintPrefix + cap;
end;

{ THintMarker }

procedure THintMarker.Handle(Sender: TObject; HintInfo: PHintInfo);
begin
  HintInfo^.HintStr := HintInfo^.HintStr + ' (seen)';
end;

{ TStateTabSet / TStatePager }

procedure TStateTabSet.Press(ABtn: TMouseButton; const APt: TPoint);
begin
  MouseDown(ABtn, [], APt.X, APt.Y);
end;

procedure TStateTabSet.Release(ABtn: TMouseButton; const APt: TPoint);
begin
  MouseUp(ABtn, [], APt.X, APt.Y);
end;

procedure TStateTabSet.MoveTo(const APt: TPoint; AShift: TShiftState);
begin
  MouseMove(AShift, APt.X, APt.Y);
end;

procedure TStatePager.Press(ABtn: TMouseButton; const APt: TPoint);
begin
  MouseDown(ABtn, [], APt.X, APt.Y);
end;

procedure TStatePager.Release(ABtn: TMouseButton; const APt: TPoint);
begin
  MouseUp(ABtn, [], APt.X, APt.Y);
end;

{ TPinProbe }

constructor TPinProbe.Create;
begin
  inherited Create;
  Count := 0;
  LastIndex := -1;
end;

procedure TPinProbe.Handle(Sender: TObject; AIndex: Integer);
begin
  Inc(Count);
  LastIndex := AIndex;
end;

{ TTabStatesTest }

procedure TTabStatesTest.SetUp;
begin
  FProbe := TStateProbe.Create;
  FClose := TStripCloseProbe.Create;
  FPin := TPinProbe.Create;
end;

procedure TTabStatesTest.TearDown;
begin
  if FForm <> nil then FForm.Free;
  FForm := nil; FStrip := nil; FCtl := nil;
  FreeAndNil(FProbe);
  FreeAndNil(FClose);
  FreeAndNil(FPin);
end;

procedure TTabStatesTest.Build(AClosable: Boolean; APos: TTabPosition; ARtl: Boolean;
  const ACss: string);
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 640, 480);
  FCtl := TTyStyleController.Create(FForm);
  FCtl.LoadThemeCss(StateCss + ACss);
  FStrip := TStateStrip.Create(FForm);
  FStrip.Parent := FForm;
  FStrip.Controller := FCtl;
  FStrip.Font.PixelsPerInch := 96;
  FStrip.TabHeight := 28;
  FStrip.SetBounds(0, 0, 420, 300);
  FStrip.TabsClosable := AClosable;
  FStrip.AddCap('Alpha');
  FStrip.AddCap('Beta');
  FStrip.AddCap('Gamma');
  if ARtl then FStrip.BiDiMode := bdRightToLeft;
  FStrip.TabPosition := APos;
  FStrip.OnGetTabState := @FProbe.Handle;
  FStrip.OnTabClose := @FClose.Handle;
end;

function TTabStatesTest.Shot: TBGRABitmap;
var
  host: TBitmap;
begin
  host := TBitmap.Create;
  try
    host.PixelFormat := pf32bit;
    host.SetSize(FStrip.Width, FStrip.Height);
    host.Canvas.Brush.Color := clWhite;
    host.Canvas.FillRect(0, 0, FStrip.Width, FStrip.Height);
    FStrip.Render(host.Canvas, Rect(0, 0, FStrip.Width, FStrip.Height), 96);
    Result := TBGRABitmap.Create(host);
  finally
    host.Free;
  end;
end;

function TTabStatesTest.Mid(const R: TRect): TPoint;
begin
  Result := Point((R.Left + R.Right) div 2, (R.Top + R.Bottom) div 2);
end;

function TTabStatesTest.OnCaption(AIndex: Integer): TPoint;
var
  r: TRect;
begin
  { The slot is at the tab's trailing end; a point four pixels inside the leading end of a
    top band (left, or right when mirrored) is on the caption box whatever the slot holds.
    Only meant for a top/bottom band. }
  r := FStrip.TabRect(AIndex);
  if FStrip.BiDiMode = bdRightToLeft then
    Result := Point(r.Right - 4, (r.Top + r.Bottom) div 2)
  else
    Result := Point(r.Left + 4, (r.Top + r.Bottom) div 2);
end;

procedure TTabStatesTest.Hover(AIndex: Integer);
var
  p: TPoint;
begin
  p := OnCaption(AIndex);
  FStrip.CallMouseMove(p.X, p.Y);
end;

procedure TTabStatesTest.Click(const APt: TPoint; ABtn: TMouseButton);
begin
  FStrip.CallMouseDown(ABtn, APt.X, APt.Y);
  FStrip.CallMouseUp(ABtn, APt.X, APt.Y);
end;

function TTabStatesTest.SlotMask(AIndex: Integer): string;
var
  bmp: TBGRABitmap;
  r: TRect;
  x, y: Integer;
  p: TBGRAPixel;
begin
  Result := '';
  r := FStrip.TabSlotRect(AIndex);
  bmp := Shot;
  try
    for y := r.Top to r.Bottom - 1 do
    begin
      for x := r.Left to r.Right - 1 do
      begin
        p := bmp.GetPixel(x, y);
        if (Integer(p.red) + p.green + p.blue) < 3 * 200 then
          Result := Result + '#'
        else
          Result := Result + '.';
      end;
      Result := Result + LineEnding;
    end;
  finally
    bmp.Free;
  end;
end;

function TTabStatesTest.InkBounds(bmp: TBGRABitmap; const AWithin: TRect): TRect;
var
  x, y: Integer;
  p: TBGRAPixel;
  found: Boolean;
begin
  Result := Rect(0, 0, 0, 0);
  found := False;
  for y := AWithin.Top to AWithin.Bottom - 1 do
    for x := AWithin.Left to AWithin.Right - 1 do
    begin
      p := bmp.GetPixel(x, y);
      if (Integer(p.red) + p.green + p.blue) < 3 * 200 then
        if not found then
        begin
          Result := Rect(x, y, x + 1, y + 1);
          found := True;
        end
        else
        begin
          if x < Result.Left then Result.Left := x;
          if x + 1 > Result.Right then Result.Right := x + 1;
          if y < Result.Top then Result.Top := y;
          if y + 1 > Result.Bottom then Result.Bottom := y + 1;
        end;
    end;
end;

procedure TTabStatesTest.AddTwins;
begin
  FStrip.SetBounds(0, 0, 620, 300);
  FStrip.AddCap('HHHH');
  FStrip.AddCap('HHHH');
end;

function TTabStatesTest.TabWidth(AIndex: Integer): Integer;
begin
  Result := FStrip.TabRect(AIndex).Right - FStrip.TabRect(AIndex).Left;
end;

function TTabStatesTest.TabMask(AIndex: Integer): string;
var
  bmp: TBGRABitmap;
  r: TRect;
  x, y: Integer;
  p: TBGRAPixel;
begin
  Result := '';
  r := FStrip.TabRect(AIndex);
  bmp := Shot;
  try
    for y := r.Top to r.Bottom - 1 do
    begin
      for x := r.Left to r.Right - 1 do
      begin
        p := bmp.GetPixel(x, y);
        if (Integer(p.red) + p.green + p.blue) < 3 * 200 then
          Result := Result + '#'
        else
          Result := Result + '.';
      end;
      Result := Result + LineEnding;
    end;
  finally
    bmp.Free;
  end;
end;

function TTabStatesTest.Slant(AIndex: Integer): Integer;
var
  bmp: TBGRABitmap;
  ink, topRow, bottomRow: TRect;
begin
  bmp := Shot;
  try
    ink := InkBounds(bmp, FStrip.TabRect(AIndex));
    AssertFalse('the caption has ink', IsRectEmpty(ink));
    topRow := InkBounds(bmp, Rect(ink.Left, ink.Top, ink.Right, ink.Top + 1));
    bottomRow := InkBounds(bmp, Rect(ink.Left, ink.Bottom - 1, ink.Right, ink.Bottom));
    Result := topRow.Left - bottomRow.Left;
  finally
    bmp.Free;
  end;
end;

function TTabStatesTest.GreenIn(const ARect: TRect): Integer;
var
  bmp: TBGRABitmap;
  x, y: Integer;
  p: TBGRAPixel;
begin
  Result := 0;
  bmp := Shot;
  try
    for y := ARect.Top to ARect.Bottom - 1 do
      for x := ARect.Left to ARect.Right - 1 do
      begin
        p := bmp.GetPixel(x, y);
        if (Integer(p.green) - p.red > 100) and (Integer(p.green) - p.blue > 100) then
          Inc(Result);
      end;
  finally
    bmp.Free;
  end;
end;

procedure TTabStatesTest.BuildFive;
begin
  Build(False);
  FStrip.SetBounds(0, 0, 620, 300);
  FStrip.AddCap('Delta');
  FStrip.AddCap('Epsilon');
end;

function TTabStatesTest.Order: string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to FStrip.TabCount - 1 do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + FStrip.TabCaption(i);
  end;
end;

procedure TTabStatesTest.Drag(AFrom, AToX: Integer);
var
  p: TPoint;
begin
  p := OnCaption(AFrom);
  FStrip.CallMouseDown(mbLeft, p.X, p.Y);
  FStrip.CallMouseMove(AToX, p.Y, [ssLeft]);
  FStrip.CallMouseUp(mbLeft, AToX, p.Y);
  FStrip.CallMouseLeave;
end;

function TTabStatesTest.AskHint(const APt: TPoint; out ARect: TRect): string;
var
  info: THintInfo;
begin
  { As TApplication.ShowHintWindow fills it in before it asks the control. }
  info := Default(THintInfo);
  info.HintControl := FStrip;
  info.CursorPos := APt;
  info.CursorRect := Rect(0, 0, FStrip.Width, FStrip.Height);
  info.HintStr := FStrip.Hint;
  AssertEquals('the control agrees to show a hint',
    0, FStrip.Perform(CM_HINTSHOW, 0, LPARAM(PtrUInt(@info))));
  ARect := info.CursorRect;
  Result := info.HintStr;
end;

function TTabStatesTest.TouchesATab(const ARect: TRect): Boolean;
var
  i: Integer;
  r, x: TRect;
begin
  Result := False;
  for i := 0 to FStrip.TabCount - 1 do
  begin
    r := FStrip.TabRect(i);
    x := Rect(0, 0, 0, 0);
    if IntersectRect(x, ARect, r) then Exit(True);
  end;
end;

{ --- the event ------------------------------------------------------------------------ }

procedure TTabStatesTest.StateComesFromTheEventAndIsNothingWithoutOne;
var
  st: TTyTabState;
begin
  Build(False);
  FProbe.ModifiedCaps := '|Beta|';
  FProbe.PinnedCaps := '|Gamma|';
  FProbe.HintPrefix := 'C:\src\';
  FProbe.InkCaps := '|Beta|';
  FProbe.Ink := TyRGB(200, 0, 0);

  st := FStrip.TabState(1);
  AssertTrue('Beta is modified', st.Modified);
  AssertFalse('Beta is not pinned', st.Pinned);
  AssertEquals('Beta''s hint', 'C:\src\Beta', st.Hint);
  AssertEquals('Beta''s ink', Cardinal(TyRGB(200, 0, 0)), Cardinal(st.TextColor));

  st := FStrip.TabState(2);
  AssertFalse('Gamma is not modified', st.Modified);
  AssertTrue('Gamma is pinned', st.Pinned);
  AssertEquals('an ink nobody set has alpha 0: the theme''s', 0, TyAlphaOf(st.TextColor));

  { Out of range: nothing, and the handler is not asked about a tab that is not there. }
  FProbe.Calls := 0;
  st := FStrip.TabState(7);
  AssertFalse(st.Modified or st.Pinned or st.Preview);
  AssertEquals('', st.Hint);
  AssertEquals('no call for an index out of range', 0, FProbe.Calls);

  FStrip.OnGetTabState := nil;
  st := FStrip.TabState(1);
  AssertFalse('no handler: nothing', st.Modified or st.Pinned or st.Preview);
  AssertEquals('', st.Hint);
  AssertEquals(0, TyAlphaOf(st.TextColor));
end;

procedure TTabStatesTest.StateIsAskedEveryTimeAndNeverKept;
begin
  Build(False);
  AssertEquals('nothing yet', Ord(tsmNone), Ord(FStrip.TabSlotMark(1)));
  AssertTrue('no slot yet', IsRectEmpty(FStrip.TabSlotRect(1)));
  { The host's data changes and the strip is not told: the next question still gets the
    new answer, because there is no old one to give. }
  FProbe.ModifiedCaps := '|Beta|';
  AssertEquals('asked again', Ord(tsmModified), Ord(FStrip.TabSlotMark(1)));
  AssertFalse('and laid out again', IsRectEmpty(FStrip.TabSlotRect(1)));
  FProbe.ModifiedCaps := '';
  AssertEquals(Ord(tsmNone), Ord(FStrip.TabSlotMark(1)));
  AssertTrue(IsRectEmpty(FStrip.TabSlotRect(1)));
end;

procedure TTabStatesTest.StateFollowsItsTabThroughAReorderAndAClose;
var
  p: TPoint;
  mid0: Integer;
begin
  Build(True);
  FProbe.PinnedCaps := '|Gamma|';
  FProbe.ModifiedCaps := '|Beta|';
  AssertEquals(Ord(tsmModified), Ord(FStrip.TabSlotMark(1)));
  AssertEquals(Ord(tsmPin), Ord(FStrip.TabSlotMark(2)));

  { Drag Beta in front of Alpha: Beta is now tab 0 and takes its dot with it. }
  p := OnCaption(1);
  mid0 := (FStrip.TabRect(0).Left + FStrip.TabRect(0).Right) div 2;
  FStrip.CallMouseDown(mbLeft, p.X, p.Y);
  FStrip.CallMouseMove(mid0 - 4, p.Y, [ssLeft]);
  FStrip.CallMouseUp(mbLeft, mid0 - 4, p.Y);
  FStrip.CallMouseLeave;
  AssertEquals('the drag moved Beta', 'Beta', FStrip.TabCaption(0));
  AssertEquals('the dot went with Beta', Ord(tsmModified), Ord(FStrip.TabSlotMark(0)));
  AssertEquals('and left Alpha', Ord(tsmClose), Ord(FStrip.TabSlotMark(1)));

  { Close Alpha (tab 1): Gamma is tab 1 now, and it is the pinned one. }
  Click(Mid(FStrip.TabSlotRect(1)));
  AssertEquals('Alpha closed', 2, FStrip.TabCount);
  AssertEquals('Gamma', FStrip.TabCaption(1));
  AssertEquals('the pin went with Gamma', Ord(tsmPin), Ord(FStrip.TabSlotMark(1)));
end;

procedure TTabStatesTest.InvalidateTabStatesTakesTheTabsChangedPath;
var
  before: Integer;
begin
  Build(False);
  before := FStrip.ChangedCalls;
  FStrip.InvalidateTabStates;
  AssertEquals('one pass through TabsChanged: relayout where the band can grow, repaint',
    before + 1, FStrip.ChangedCalls);
  { A handler leaving -- or arriving -- changes what every tab is, with no call from the host. }
  FStrip.OnGetTabState := nil;
  AssertEquals('taking the handler away is a change too', before + 2, FStrip.ChangedCalls);
end;

{ --- the slot ------------------------------------------------------------------------- }

procedure TTabStatesTest.AModifiedOrPinnedTabHasASlotWithoutCloseButtons;
var
  w0, w1, w2: Integer;
  slot, tab: TRect;
begin
  Build(False);
  w0 := FStrip.TabRect(0).Right - FStrip.TabRect(0).Left;
  w1 := FStrip.TabRect(1).Right - FStrip.TabRect(1).Left;
  w2 := FStrip.TabRect(2).Right - FStrip.TabRect(2).Left;
  AssertTrue('no close buttons, no state: no slot', IsRectEmpty(FStrip.TabSlotRect(1)));

  FProbe.ModifiedCaps := '|Beta|';
  FProbe.PinnedCaps := '|Gamma|';
  AssertEquals('an untouched tab keeps its width',
    w0, FStrip.TabRect(0).Right - FStrip.TabRect(0).Left);
  AssertEquals('the modified tab grows by the slot',
    w1 + CloseSize + CloseGap, FStrip.TabRect(1).Right - FStrip.TabRect(1).Left);
  AssertEquals('the pinned tab grows by the slot',
    w2 + CloseSize + CloseGap, FStrip.TabRect(2).Right - FStrip.TabRect(2).Left);
  AssertTrue('and the untouched one still has none', IsRectEmpty(FStrip.TabSlotRect(0)));

  slot := FStrip.TabSlotRect(1);
  tab := FStrip.TabRect(1);
  AssertEquals('slot width', CloseSize, slot.Right - slot.Left);
  AssertEquals('slot height', CloseSize, slot.Bottom - slot.Top);
  AssertEquals('at the trailing end, the margin in', tab.Right - CloseMargin, slot.Right);
  AssertFalse('the pinned tab has one too', IsRectEmpty(FStrip.TabSlotRect(2)));
end;

procedure TTabStatesTest.TheSlotIsWhereTheCloseGlyphWouldBe;
var
  plain, slot, tab: TRect;
  dxPlain, dyPlain: Integer;
begin
  { A closable strip's close rect, relative to its tab ... }
  Build(True);
  FStrip.OnGetTabState := nil;
  plain := FStrip.ToScreenRect(FStrip.TyTabCloseRect(1));
  tab := FStrip.TabRect(1);
  dxPlain := tab.Right - plain.Right;
  dyPlain := plain.Top - tab.Top;
  AssertEquals('TabSlotRect is the close rect as drawn', plain.Left, FStrip.TabSlotRect(1).Left);
  AssertEquals(plain.Top, FStrip.TabSlotRect(1).Top);
  AssertEquals(plain.Right, FStrip.TabSlotRect(1).Right);
  AssertEquals(plain.Bottom, FStrip.TabSlotRect(1).Bottom);
  TearDown;
  SetUp;
  { ... is where a strip with no close buttons puts the dot. }
  Build(False);
  FProbe.ModifiedCaps := '|Beta|';
  slot := FStrip.TabSlotRect(1);
  tab := FStrip.TabRect(1);
  AssertEquals('same distance from the trailing edge', dxPlain, tab.Right - slot.Right);
  AssertEquals('same distance from the top', dyPlain, slot.Top - tab.Top);
  AssertEquals('same size', plain.Right - plain.Left, slot.Right - slot.Left);
end;

procedure TTabStatesTest.TheSlotShowsDotPinOrCloseForEveryCombination;

  procedure Check(AClosable, AModified, APinned: Boolean; ARest, AHot: TTyTabSlotMark);
  var
    tag: string;
  begin
    tag := Format('closable=%d modified=%d pinned=%d', [Ord(AClosable), Ord(AModified), Ord(APinned)]);
    Build(AClosable);
    if AModified then FProbe.ModifiedCaps := '|Beta|';
    if APinned then FProbe.PinnedCaps := '|Beta|';
    AssertEquals(tag + ', pointer elsewhere', Ord(ARest), Ord(FStrip.TabSlotMark(1)));
    Hover(0);
    AssertEquals(tag + ', pointer on another tab', Ord(ARest), Ord(FStrip.TabSlotMark(1)));
    Hover(1);
    AssertEquals(tag + ', pointer on the tab', Ord(AHot), Ord(FStrip.TabSlotMark(1)));
    FStrip.CallMouseLeave;
    AssertEquals(tag + ', pointer gone', Ord(ARest), Ord(FStrip.TabSlotMark(1)));
    TearDown;
    SetUp;
  end;

begin
  { no close buttons }
  Check(False, False, False, tsmNone,     tsmNone);
  Check(False, True,  False, tsmModified, tsmModified);   // nothing to turn back into
  Check(False, False, True,  tsmPin,      tsmPin);
  Check(False, True,  True,  tsmModified, tsmPin);
  { close buttons }
  Check(True,  False, False, tsmClose,    tsmClose);
  Check(True,  True,  False, tsmModified, tsmClose);
  Check(True,  False, True,  tsmPin,      tsmPin);
  Check(True,  True,  True,  tsmModified, tsmPin);
end;

procedure TTabStatesTest.TheSlotPaintsTheMarkItNames;
var
  closeMask, dotMask, pinMask, s: string;
  bmp: TBGRABitmap;
  slot, ink: TRect;
  c: TPoint;
  p: TBGRAPixel;
begin
  { The three marks, each painted in a tab whose slot nothing else can change. }
  Build(True);
  closeMask := SlotMask(2);
  AssertTrue('a close glyph has ink', Pos('#', closeMask) > 0);

  FProbe.ModifiedCaps := '|Beta|';
  dotMask := SlotMask(1);
  AssertTrue('a dot has ink', Pos('#', dotMask) > 0);
  AssertTrue('a dot is not a close glyph', dotMask <> closeMask);
  AssertEquals('the tab beside it still shows its close glyph', closeMask, SlotMask(2));

  { A dot: a filled disc in the middle of the slot, the theme's size across. }
  bmp := Shot;
  try
    slot := FStrip.TabSlotRect(1);
    ink := InkBounds(bmp, slot);
    c := Mid(slot);
    p := bmp.GetPixel(c.X, c.Y);
    AssertTrue('solid in the middle', (p.red < 60) and (p.green < 60) and (p.blue < 60));
    AssertTrue('8px across (--tab-modified-dot-size), give or take the antialiased rim',
      (ink.Right - ink.Left >= 7) and (ink.Right - ink.Left <= 8));
    AssertTrue('as tall as it is wide', (ink.Bottom - ink.Top) = (ink.Right - ink.Left));
    AssertTrue('centred across', Abs((ink.Left - slot.Left) - (slot.Right - ink.Right)) <= 1);
    AssertTrue('centred down', Abs((ink.Top - slot.Top) - (slot.Bottom - ink.Bottom)) <= 1);
  finally
    bmp.Free;
  end;

  FProbe.ModifiedCaps := '';
  FProbe.PinnedCaps := '|Beta|';
  pinMask := SlotMask(1);
  AssertTrue('a pin has ink', Pos('#', pinMask) > 0);
  AssertTrue('a pin is not a close glyph', pinMask <> closeMask);
  AssertTrue('a pin is not a dot', pinMask <> dotMask);

  { Under the pointer the modified tab shows exactly what its neighbour shows: the close
    glyph, the same pixels. (No hover look in this theme, and the pointer is on the caption,
    so nothing else in the slot changes.) }
  FProbe.PinnedCaps := '';
  FProbe.ModifiedCaps := '|Beta|';
  Hover(1);
  s := SlotMask(1);
  AssertEquals('hot: the close glyph', closeMask, s);
  FStrip.CallMouseLeave;
  AssertEquals('pointer gone: the dot again', dotMask, SlotMask(1));

  { Pinned and modified: the dot, and the pin under the pointer. }
  FProbe.PinnedCaps := '|Beta|';
  AssertEquals('pinned + modified: the dot', dotMask, SlotMask(1));
  Hover(1);
  AssertEquals('pinned + modified, hot: the pin', pinMask, SlotMask(1));
end;

procedure TTabStatesTest.TheSlotHitRectIsThePaintedRectOnEveryBand;
var
  i, k: Integer;
  rtl: Boolean;
  bmp: TBGRABitmap;
  tab, slot, ink: TRect;
  tag: string;
  outside: TPoint;
begin
  for rtl := False to True do
    for i := 0 to High(AllPositions) do
    begin
      tag := Format('position %d rtl %d: ', [Ord(AllPositions[i]), Ord(rtl)]);
      Build(False, AllPositions[i], rtl);
      { No captions: whatever ink lies inside a tab is its mark. }
      for k := FStrip.TabCount - 1 downto 0 do FStrip.RemoveTabForStates(k);
      FStrip.AddCap('');
      FStrip.AddCap('');
      FStrip.TabIndex := 0;
      FProbe.PinnedCaps := '||';       // every (empty) caption is pinned
      FStrip.OnTabPinClick := @FPin.Handle;

      bmp := Shot;
      try
        tab := FStrip.TabRect(1);
        slot := FStrip.TabSlotRect(1);
        ink := InkBounds(bmp, tab);
        AssertFalse(tag + 'the pin is painted', IsRectEmpty(ink));
        AssertTrue(tag + 'the slot lies in its tab',
          (slot.Left >= tab.Left) and (slot.Right <= tab.Right)
          and (slot.Top >= tab.Top) and (slot.Bottom <= tab.Bottom));
        AssertTrue(tag + 'the pin is painted inside the slot',
          (ink.Left >= slot.Left) and (ink.Right <= slot.Right)
          and (ink.Top >= slot.Top) and (ink.Bottom <= slot.Bottom));
      finally
        bmp.Free;
      end;

      { The four corners of the slot act; one pixel outside each side does not. }
      FPin.Count := 0;
      Click(Point(slot.Left, slot.Top));
      Click(Point(slot.Right - 1, slot.Bottom - 1));
      AssertEquals(tag + 'both corners of the slot are the pin', 2, FPin.Count);
      AssertEquals(tag + 'a pin click does not select', 0, FStrip.TabIndex);
      if slot.Left - 1 >= tab.Left then outside := Point(slot.Left - 1, slot.Top)
      else outside := Point(slot.Right, slot.Top);
      Click(outside);
      AssertEquals(tag + 'one pixel beside the slot is the tab', 2, FPin.Count);
      AssertEquals(tag + 'and selects it', 1, FStrip.TabIndex);
      TearDown;
      SetUp;
    end;
end;

procedure TTabStatesTest.TheSlotFollowsItsTabWhenTheStripScrollsOrFolds;
var
  i: Integer;
  bmp: TBGRABitmap;
  tab, slot, ink: TRect;
begin
  { Eight tabs on a strip that holds about three: the last one is reached by scrolling. }
  Build(False);
  for i := FStrip.TabCount - 1 downto 0 do FStrip.RemoveTabForStates(i);
  for i := 1 to 8 do FStrip.AddCap('');
  FStrip.SetBounds(0, 0, 220, 300);
  FStrip.TabIndex := 0;
  FProbe.PinnedCaps := '||';
  FStrip.OnTabPinClick := @FPin.Handle;
  AssertTrue('fixture: the strip overflows', FStrip.TyMaxHeaderScroll > 0);
  FStrip.ScrollTabIntoView(7);
  AssertTrue('fixture: it scrolled', FStrip.HeaderScroll > 0);
  tab := FStrip.TabRect(7);
  slot := FStrip.TabSlotRect(7);
  AssertTrue('scrolled: the slot is still inside its tab as drawn',
    (slot.Left >= tab.Left) and (slot.Right <= tab.Right));
  bmp := Shot;
  try
    ink := InkBounds(bmp, tab);
    AssertFalse('scrolled: the pin is painted', IsRectEmpty(ink));
    AssertTrue('scrolled: in the slot',
      (ink.Left >= slot.Left) and (ink.Right <= slot.Right)
      and (ink.Top >= slot.Top) and (ink.Bottom <= slot.Bottom));
  finally
    bmp.Free;
  end;
  Click(Mid(slot));
  AssertEquals('scrolled: and a click there is the pin of tab 7', 7, FPin.LastIndex);

  { The same eight folded into rows: the last tab is on a later row, slot and all. }
  FStrip.MultiLine := True;
  AssertTrue('fixture: the run folded', FStrip.RowCount > 1);
  tab := FStrip.TabRect(7);
  slot := FStrip.TabSlotRect(7);
  AssertTrue('fixture: tab 7 is below the first row', tab.Top >= FStrip.TabRect(0).Bottom);
  AssertTrue('folded: the slot is on its tab''s row',
    (slot.Top >= tab.Top) and (slot.Bottom <= tab.Bottom)
    and (slot.Left >= tab.Left) and (slot.Right <= tab.Right));
  bmp := Shot;
  try
    ink := InkBounds(bmp, tab);
    AssertTrue('folded: the pin is painted in the slot',
      (not IsRectEmpty(ink)) and (ink.Left >= slot.Left) and (ink.Right <= slot.Right)
      and (ink.Top >= slot.Top) and (ink.Bottom <= slot.Bottom));
  finally
    bmp.Free;
  end;
  FPin.LastIndex := -1;
  Click(Mid(slot));
  AssertEquals('folded: and a click there is the pin of tab 7', 7, FPin.LastIndex);
end;

procedure TTabStatesTest.TheCaptionStepsAsideForTheSlot;
var
  bmp: TBGRABitmap;
  tab, slot, ink: TRect;
  plainOffset, plainWidth: Integer;
begin
  Build(False);
  bmp := Shot;
  try
    tab := FStrip.TabRect(1);
    ink := InkBounds(bmp, tab);
    plainOffset := ink.Left - tab.Left;
    plainWidth := ink.Right - ink.Left;
  finally
    bmp.Free;
  end;
  { The slot is added to the tab; the caption's own box is what it was, so the caption is
    where it was in it -- not centred across a tab that now holds a dot as well. }
  FProbe.ModifiedCaps := '|Beta|';
  bmp := Shot;
  try
    tab := FStrip.TabRect(1);
    slot := FStrip.TabSlotRect(1);
    ink := InkBounds(bmp, Rect(tab.Left, tab.Top, slot.Left, tab.Bottom));
    AssertEquals('the caption starts where it did', plainOffset, ink.Left - tab.Left);
    AssertEquals('and is all there', plainWidth, ink.Right - ink.Left);
    AssertTrue('clear of the slot', ink.Right < slot.Left);
  finally
    bmp.Free;
  end;
end;

{ --- clicks --------------------------------------------------------------------------- }

procedure TTabStatesTest.AClickOnThePinFiresOnTabPinClickAndDoesNotClose;
begin
  Build(True);
  FProbe.PinnedCaps := '|Beta|';
  FStrip.OnTabPinClick := @FPin.Handle;

  Click(Mid(FStrip.TabSlotRect(1)));
  AssertEquals('the pin was clicked', 1, FPin.Count);
  AssertEquals('on Beta', 1, FPin.LastIndex);
  AssertEquals('nothing asked to close', 0, FClose.Count);
  AssertEquals('nothing closed', 3, FStrip.TabCount);
  AssertEquals('and the selection stayed', 0, FStrip.TabIndex);

  { The same click on the tab beside it, which is not pinned, closes. }
  Click(Mid(FStrip.TabSlotRect(2)));
  AssertEquals('the pin handler heard nothing more', 1, FPin.Count);
  AssertEquals('the close handler did', 1, FClose.Count);
  AssertEquals(2, FClose.LastIndex);
  AssertEquals(2, FStrip.TabCount);
end;

procedure TTabStatesTest.APinWithoutAHandlerDoesNothing;
begin
  Build(True);
  FProbe.PinnedCaps := '|Beta|';
  Click(Mid(FStrip.TabSlotRect(1)));
  AssertEquals('no close', 0, FClose.Count);
  AssertEquals('no tab gone', 3, FStrip.TabCount);
  AssertEquals('no selection', 0, FStrip.TabIndex);
end;

procedure TTabStatesTest.TheDotTurnsIntoCloseUnderThePointerAndCloses;
var
  p: TPoint;
begin
  Build(True);
  FProbe.ModifiedCaps := '|Beta|';
  p := Mid(FStrip.TabSlotRect(1));
  FStrip.CallMouseMove(p.X, p.Y);
  AssertEquals('under the pointer the slot is the close glyph',
    Ord(tsmClose), Ord(FStrip.TabSlotMark(1)));
  Click(p);
  AssertEquals('and a click on it closes, as usual', 1, FClose.Count);
  AssertEquals(1, FClose.LastIndex);
  AssertEquals(2, FStrip.TabCount);
end;

procedure TTabStatesTest.ADotWithoutCloseButtonsIsPartOfTheTab;
begin
  Build(False);
  FProbe.ModifiedCaps := '|Beta|';
  Click(Mid(FStrip.TabSlotRect(1)));
  AssertEquals('nothing asked to close', 0, FClose.Count);
  AssertEquals(3, FStrip.TabCount);
  AssertEquals('the click selected the tab, as a click on its caption does', 1, FStrip.TabIndex);
end;

procedure TTabStatesTest.TheSlotHoverFollowsWhatAClickWouldDo;
var
  p: TPoint;
begin
  { A pin on a strip without close buttons is still a button ... }
  Build(False);
  FProbe.PinnedCaps := '|Beta|';
  FProbe.ModifiedCaps := '|Gamma|';
  p := Mid(FStrip.TabSlotRect(1));
  FStrip.CallMouseMove(p.X, p.Y);
  AssertEquals('the pin lights up', 1, FStrip.TyTabHoverClose);
  { ... and a dot there is not. }
  p := Mid(FStrip.TabSlotRect(2));
  FStrip.CallMouseMove(p.X, p.Y);
  AssertEquals('a dot nothing can be done with does not', -1, FStrip.TyTabHoverClose);
end;

{ --- middle click --------------------------------------------------------------------- }

procedure TTabStatesTest.MiddleClickClosesOnReleaseThroughOnTabClose;
var
  p: TPoint;
begin
  Build(True);
  AssertTrue('on by default', FStrip.MiddleClickClose);
  p := OnCaption(1);
  FStrip.CallMouseDown(mbMiddle, p.X, p.Y);
  AssertEquals('the press alone closes nothing', 3, FStrip.TabCount);
  AssertEquals(0, FClose.Count);
  FStrip.CallMouseUp(mbMiddle, p.X, p.Y);
  AssertEquals('the release asks OnTabClose', 1, FClose.Count);
  AssertEquals('about the tab under the pointer', 1, FClose.LastIndex);
  AssertEquals('and the tab goes', 2, FStrip.TabCount);
  AssertEquals('Gamma', FStrip.TabCaption(1));
end;

procedure TTabStatesTest.MiddleClickHonoursTheVeto;
begin
  Build(True);
  FClose.Veto := True;
  Click(OnCaption(1), mbMiddle);
  AssertEquals('asked', 1, FClose.Count);
  AssertEquals('refused: the tab stays', 3, FStrip.TabCount);
end;

procedure TTabStatesTest.MiddleClickNeedsTheReleaseOnTheSameTab;
var
  p, q: TPoint;
begin
  Build(True);
  p := OnCaption(1);
  q := OnCaption(2);
  FStrip.CallMouseDown(mbMiddle, p.X, p.Y);
  FStrip.CallMouseUp(mbMiddle, q.X, q.Y);
  AssertEquals('released on another tab: nothing', 0, FClose.Count);
  { A release with no press of its own does nothing either. }
  FStrip.CallMouseUp(mbMiddle, p.X, p.Y);
  AssertEquals('a release without its press: nothing', 0, FClose.Count);
  { The pointer left in between: the press is forgotten. }
  FStrip.CallMouseDown(mbMiddle, p.X, p.Y);
  FStrip.CallMouseLeave;
  FStrip.CallMouseUp(mbMiddle, p.X, p.Y);
  AssertEquals('left and came back: nothing', 0, FClose.Count);
  AssertEquals(3, FStrip.TabCount);
end;

procedure TTabStatesTest.MiddleClickNeedsClosingEnabled;
begin
  Build(False);
  Click(OnCaption(1), mbMiddle);
  AssertEquals('no close buttons: a middle click closes nothing', 0, FClose.Count);
  AssertEquals(3, FStrip.TabCount);
  FStrip.TabsClosable := True;
  Click(OnCaption(1), mbMiddle);
  AssertEquals('with them, it does', 1, FClose.Count);
  AssertEquals(2, FStrip.TabCount);
end;

procedure TTabStatesTest.MiddleClickLeavesAPinnedTab;
begin
  Build(True);
  FProbe.PinnedCaps := '|Beta|';
  Click(OnCaption(1), mbMiddle);
  AssertEquals('a pinned tab is not closed by a middle click', 0, FClose.Count);
  AssertEquals(3, FStrip.TabCount);
  Click(OnCaption(2), mbMiddle);
  AssertEquals('the unpinned one beside it is', 1, FClose.Count);
  AssertEquals(2, FClose.LastIndex);
end;

procedure TTabStatesTest.MiddleClickCloseCanBeSwitchedOff;
begin
  Build(True);
  FStrip.MiddleClickClose := False;
  Click(OnCaption(1), mbMiddle);
  AssertEquals(0, FClose.Count);
  AssertEquals(3, FStrip.TabCount);
  FStrip.MiddleClickClose := True;
  Click(OnCaption(1), mbMiddle);
  AssertEquals(1, FClose.Count);
end;

{ --- preview -------------------------------------------------------------------------- }

const
  { Takes the slant out, so a test can look at one thing at a time. }
  UprightPreviewCss = ':root { --tab-preview-font-style: normal; }';

procedure TTabStatesTest.APreviewCaptionIsItalicInTheBuiltInTheme;
begin
  { The test theme writes no preview rule and no token: what a preview tab gets here is
    what the base theme gives every theme. }
  Build(False);
  AddTwins;
  AssertEquals('twins, neither a preview: the same pixels', TabMask(4), TabMask(3));
  AssertEquals('upright capitals', 0, Slant(3));

  FProbe.PreviewIndex := 3;
  AssertTrue('the preview tab''s caption leans', Slant(3) >= 1);
  AssertEquals('its twin still stands', 0, Slant(4));
  AssertTrue('and the two no longer look alike', TabMask(3) <> TabMask(4));
end;

procedure TTabStatesTest.ThePreviewFontStyleIsTheThemesToken;
begin
  { A theme that says "normal" gets an upright preview caption ... }
  Build(False, tpTop, False, UprightPreviewCss);
  AddTwins;
  FProbe.PreviewIndex := 3;
  AssertEquals('the theme took the slant away', 0, Slant(3));
  AssertEquals('so preview and twin are the same pixels', TabMask(4), TabMask(3));
  TearDown;
  SetUp;
  { ... and one control can say so for itself, over a theme that slants. }
  Build(False);
  AddTwins;
  FProbe.PreviewIndex := 3;
  AssertTrue('the theme slants', Slant(3) >= 1);
  FStrip.StyleOverride := '--tab-preview-font-style: normal;';
  AssertEquals('this strip does not', 0, Slant(3));
  FStrip.StyleOverride := '';
  AssertTrue('back to the theme', Slant(3) >= 1);
end;

procedure TTabStatesTest.ThePreviewLookIsAVariantOfTheTabStyle;
begin
  Build(False, tpTop, False, UprightPreviewCss + 'TyTab.preview { color: #00FF00; }');
  AddTwins;
  AssertEquals('no preview tab: nothing green', 0, GreenIn(FStrip.BandRect));
  FProbe.PreviewIndex := 3;
  AssertTrue('TyTab.preview reached the preview tab''s caption',
    GreenIn(FStrip.TabRect(3)) > 10);
  AssertEquals('and only it', 0, GreenIn(FStrip.TabRect(4)));
end;

procedure TTabStatesTest.APreviewCaptionIsMeasuredWithTheFontItIsDrawnIn;
const
  Pad = 12;   { --tab-padding, each side }
var
  bmp: TBGRABitmap;
  inkP, inkT: TRect;
  wP, wT, slackP, slackT: Integer;
  meas: TBitmap;
  S: TTyStyleSet;
  upright, italic: Integer;
begin
  { A preview look with a much larger, bolder font: the tab has to be measured in THAT
    font, and the caption drawn in it. }
  Build(False, tpTop, False,
    UprightPreviewCss + 'TyTab.preview { font-size: 20px; font-weight: 700; }');
  AddTwins;
  FProbe.PreviewIndex := 3;
  wP := TabWidth(3);
  wT := TabWidth(4);
  AssertTrue('the preview tab is measured in its own font', wP > wT + 15);
  bmp := Shot;
  try
    inkP := InkBounds(bmp, FStrip.TabRect(3));
    inkT := InkBounds(bmp, FStrip.TabRect(4));
  finally
    bmp.Free;
  end;
  AssertTrue('and drawn in it', (inkP.Bottom - inkP.Top) >= (inkT.Bottom - inkT.Top) + 3);
  { What is left of the tab around the ink is the padding, for both: a caption measured in
    one font and drawn in another would leave too much, or none. }
  slackT := wT - (inkT.Right - inkT.Left);
  slackP := wP - (inkP.Right - inkP.Left);
  AssertTrue(Format('the twin''s caption sits in its padding (%d)', [slackT]),
    Abs(slackT - 2 * Pad) <= 6);
  AssertTrue(Format('and so does the preview caption (%d)', [slackP]),
    Abs(slackP - 2 * Pad) <= 6);
  TearDown;
  SetUp;

  { The slant itself is measured too: the preview tab differs from its twin by exactly what
    the italic face differs from the upright one. }
  Build(False);
  AddTwins;
  FProbe.PreviewIndex := 3;
  S := FCtl.Model.ResolveStyle('TyTab', '', [tysNormal]);
  meas := TBitmap.Create;
  try
    meas.SetSize(1, 1);
    TyConfigureMeasureFont(meas.Canvas, S.FontName, S.FontSize, S.FontWeight, 96);
    upright := meas.Canvas.TextWidth('HHHH');
    TyConfigureMeasureFont(meas.Canvas, S.FontName, S.FontSize, S.FontWeight or TyFontItalic, 96);
    italic := meas.Canvas.TextWidth('HHHH');
  finally
    meas.Free;
  end;
  AssertEquals('the italic caption is measured as italic',
    italic - upright, TabWidth(3) - TabWidth(4));
end;

procedure TTabStatesTest.APreviewTabFadesBetweenItsOwnLooks;
var
  bmp: TBGRABitmap;
  tab: TRect;
  p: TBGRAPixel;
begin
  { A preview look with grounds of its own: black at rest, red when selected. The selected
    tab's cross-fade has to run between THOSE two, not between the plain tab's. }
  Build(False, tpTop, False,
    'TyTab.preview { background: #000000; color: #FFFFFF; }' +
    'TyTab.preview:active { background: #FF0000; color: #FFFFFF; }');
  FProbe.PreviewCaps := '|Beta|';
  FStrip.TabIndex := 1;
  tab := FStrip.TabRect(1);
  bmp := Shot;
  try
    p := bmp.GetPixel(tab.Left + 2, tab.Top + 2);
    AssertTrue('settled: the preview tab''s selected ground',
      (p.red > 240) and (p.green < 15) and (p.blue < 15));
  finally
    bmp.Free;
  end;
  FStrip.DoArmFade;
  FStrip.DoAdvance(40);
  AssertTrue('fixture: the fade is in flight', (FStrip.FadeEased > 0) and (FStrip.FadeEased < 1));
  bmp := Shot;
  try
    p := bmp.GetPixel(tab.Left + 2, tab.Top + 2);
    AssertTrue('in flight: somewhere between black and red -- no white of the plain tab in it',
      (p.green < 15) and (p.blue < 15) and (p.red > 15) and (p.red < 240));
  finally
    bmp.Free;
  end;
end;

{ --- ink ------------------------------------------------------------------------------ }

procedure TTabStatesTest.TextColorInksTheCaptionAndTheDot;
var
  bmp: TBGRABitmap;
  c: TPoint;
  p: TBGRAPixel;
begin
  Build(False);
  FProbe.ModifiedCaps := '|Alpha|Beta|';
  FProbe.InkCaps := '|Beta|';
  FProbe.Ink := TyRGB(0, 255, 0);
  FStrip.TabIndex := 2;    { neither of the two is the selected tab }

  AssertTrue('the caption is in the state''s ink', GreenIn(FStrip.TabRect(1)) > 10);
  AssertEquals('a tab without one keeps the theme''s', 0, GreenIn(FStrip.TabRect(0)));
  bmp := Shot;
  try
    c := Mid(FStrip.TabSlotRect(1));
    p := bmp.GetPixel(c.X, c.Y);
    AssertTrue('the dot shares the caption''s ink',
      (p.green > 240) and (p.red < 20) and (p.blue < 20));
    c := Mid(FStrip.TabSlotRect(0));
    p := bmp.GetPixel(c.X, c.Y);
    AssertTrue('the other dot is the theme''s ink',
      (p.green < 60) and (p.red < 60) and (p.blue < 60));
  finally
    bmp.Free;
  end;

  { Selected, and under the pointer: the same ink. }
  FStrip.TabIndex := 1;
  AssertTrue('selected: still its ink', GreenIn(FStrip.TabRect(1)) > 10);
  FStrip.TabIndex := 2;
  Hover(1);
  AssertTrue('under the pointer: still its ink', GreenIn(FStrip.TabRect(1)) > 10);
  FStrip.CallMouseLeave;

  { Alpha 0 is "not set", whatever the other three bytes say. }
  FProbe.Ink := TyRGBA(0, 255, 0, 0);
  AssertEquals('an ink with no alpha is the theme''s', 0, GreenIn(FStrip.TabRect(1)));
end;

procedure TTabStatesTest.TextColorLeavesTheCloseGlyphAndThePinToTheTheme;
begin
  Build(True);
  FProbe.InkCaps := '|Beta|Gamma|';
  FProbe.Ink := TyRGB(0, 255, 0);
  FProbe.PinnedCaps := '|Gamma|';
  AssertTrue('fixture: Beta''s caption is green', GreenIn(FStrip.TabRect(1)) > 10);
  AssertTrue('the close glyph is drawn', Pos('#', SlotMask(1)) > 0);
  AssertEquals('in the theme''s ink', 0, GreenIn(FStrip.TabSlotRect(1)));
  AssertTrue('the pin is drawn', Pos('#', SlotMask(2)) > 0);
  AssertEquals('in the theme''s ink', 0, GreenIn(FStrip.TabSlotRect(2)));
end;

procedure TTabStatesTest.TextColorIsNotUsedOnADisabledStrip;
begin
  Build(False);
  FProbe.InkCaps := '|Beta|';
  FProbe.Ink := TyRGB(0, 255, 0);
  AssertTrue('enabled: the state''s ink', GreenIn(FStrip.TabRect(1)) > 10);
  FStrip.Enabled := False;
  AssertEquals('disabled: the theme''s', 0, GreenIn(FStrip.TabRect(1)));
end;

procedure TTabStatesTest.TheDotIsAsLargeAsTheThemeSays;

  function DotWidth: Integer;
  var
    bmp: TBGRABitmap;
    ink: TRect;
  begin
    bmp := Shot;
    try
      ink := InkBounds(bmp, FStrip.TabSlotRect(1));
      Result := ink.Right - ink.Left;
    finally
      bmp.Free;
    end;
  end;

begin
  Build(False, tpTop, False, ':root { --tab-modified-dot-size: 4px; }');
  FProbe.ModifiedCaps := '|Beta|';
  AssertTrue('a 4px dot', (DotWidth >= 3) and (DotWidth <= 4));
  { And one strip can have its own. }
  FStrip.StyleOverride := '--tab-modified-dot-size: 12px;';
  AssertTrue('a 12px dot on this strip', (DotWidth >= 11) and (DotWidth <= 12));
end;

{ --- the order stays the host's; a drag keeps a pinned block whole -------------------- }

procedure TTabStatesTest.PinnedDropIndexStopsAtThePinnedBoundary;
begin
  BuildFive;
  { Alpha Beta | Gamma Delta Epsilon -- the host has put its two pinned tabs first. }
  FProbe.PinnedCaps := '|Alpha|Beta|';
  AssertEquals('unpinned Delta to the very front: behind the last pinned tab',
    2, FStrip.TyPinnedDropIndex(3, 0));
  AssertEquals('to the middle of the pinned block: the same place',
    2, FStrip.TyPinnedDropIndex(3, 1));
  AssertEquals('to the place right behind the block: there', 2, FStrip.TyPinnedDropIndex(3, 2));
  AssertEquals('toward the back: wherever it is taken', 4, FStrip.TyPinnedDropIndex(3, 4));
  AssertEquals('unpinned Gamma, already at the boundary, stays', 2, FStrip.TyPinnedDropIndex(2, 0));

  AssertEquals('pinned Alpha to the very back: the last place in the block',
    1, FStrip.TyPinnedDropIndex(0, 4));
  AssertEquals('pinned Alpha inside the block: wherever it is taken',
    1, FStrip.TyPinnedDropIndex(0, 1));
  AssertEquals('pinned Beta, already at the boundary, stays', 1, FStrip.TyPinnedDropIndex(1, 3));
  AssertEquals('pinned Beta toward the front: wherever it is taken',
    0, FStrip.TyPinnedDropIndex(1, 0));

  { A pinned tab the host left further back: each tab stops at the nearest one of the other
    kind on its own way, and what is already out of place may be put right. }
  FProbe.PinnedCaps := '|Alpha|Gamma|';      { Alpha* Beta Gamma* Delta Epsilon }
  AssertEquals('unpinned Epsilon stops behind Gamma', 3, FStrip.TyPinnedDropIndex(4, 0));
  AssertEquals('unpinned Beta may not pass Alpha', 1, FStrip.TyPinnedDropIndex(1, 0));
  AssertEquals('pinned Gamma may not pass Delta', 2, FStrip.TyPinnedDropIndex(2, 4));
  AssertEquals('pinned Gamma may come forward past Beta', 1, FStrip.TyPinnedDropIndex(2, 1));
  AssertEquals('unpinned Beta may go back past Gamma', 2, FStrip.TyPinnedDropIndex(1, 2));

  { Nothing pinned: nothing to stop at. }
  FProbe.PinnedCaps := '';
  AssertEquals(0, FStrip.TyPinnedDropIndex(3, 0));
  AssertEquals(4, FStrip.TyPinnedDropIndex(0, 4));
end;

procedure TTabStatesTest.ADragDoesNotCarryAnUnpinnedTabInFrontOfAPinnedOne;
var
  reorder: TStripReorderProbe;
begin
  BuildFive;
  FProbe.PinnedCaps := '|Alpha|Beta|';
  reorder := TStripReorderProbe.Create;
  try
    FStrip.OnReorder := @reorder.Handle;
    Drag(3, 2);     { Delta, carried to the strip's left edge }
    AssertEquals('Delta stops right behind the pinned tabs',
      'Alpha,Beta,Delta,Gamma,Epsilon', Order);
    AssertEquals('one move is reported', 1, reorder.Count);
    AssertEquals(3, reorder.LastFrom);
    AssertEquals('to where it stopped, not to where it was aimed', 2, reorder.LastTo);

    Drag(2, 2);     { Delta again: it is at the boundary and has nowhere to go }
    AssertEquals('nothing moves', 'Alpha,Beta,Delta,Gamma,Epsilon', Order);
    AssertEquals('and nothing is reported', 1, reorder.Count);
  finally
    reorder.Free;
  end;
end;

procedure TTabStatesTest.ADragDoesNotCarryAPinnedTabBehindAnUnpinnedOne;
var
  reorder: TStripReorderProbe;
begin
  BuildFive;
  FProbe.PinnedCaps := '|Alpha|Beta|';
  reorder := TStripReorderProbe.Create;
  try
    FStrip.OnReorder := @reorder.Handle;
    Drag(0, FStrip.Width - 2);     { Alpha, carried to the strip's right edge }
    AssertEquals('Alpha stops at the end of the pinned block',
      'Beta,Alpha,Gamma,Delta,Epsilon', Order);
    AssertEquals(1, reorder.Count);
    AssertEquals(0, reorder.LastFrom);
    AssertEquals(1, reorder.LastTo);

    Drag(1, FStrip.Width - 2);     { Alpha again, from the boundary }
    AssertEquals('nothing moves', 'Beta,Alpha,Gamma,Delta,Epsilon', Order);
    AssertEquals(1, reorder.Count);
  finally
    reorder.Free;
  end;
end;

procedure TTabStatesTest.WithoutPinnedTabsADragGoesWhereItIsTaken;
begin
  BuildFive;
  Drag(3, 2);
  AssertEquals('to the very front', 'Delta,Alpha,Beta,Gamma,Epsilon', Order);
  Drag(0, FStrip.Width - 2);
  AssertEquals('to the very back', 'Alpha,Beta,Gamma,Epsilon,Delta', Order);
end;

procedure TTabStatesTest.TheStripNeverReordersByItself;
var
  bmp: TBGRABitmap;
begin
  { The request was "pinned tabs sort first". The order of the tabs is the host's: a tab
    that becomes pinned stays where the host has it until the host moves it. }
  BuildFive;
  FProbe.PinnedCaps := '|Delta|';
  FStrip.InvalidateTabStates;
  bmp := Shot;
  bmp.Free;
  Click(OnCaption(4));
  AssertEquals('Alpha,Beta,Gamma,Delta,Epsilon', Order);
  AssertEquals('and the indexes mean what they meant', 4, FStrip.TabIndex);
end;

{ --- hints ---------------------------------------------------------------------------- }

procedure TTabStatesTest.TheHintOverATabIsThatTabsOwn;
var
  r: TRect;
begin
  Build(False);
  FStrip.Hint := 'the strip';
  FProbe.HintPrefix := 'C:\src\';
  AssertEquals('C:\src\Beta', AskHint(OnCaption(1), r));
  AssertTrue('asked again on leaving Beta', EqualRect(r, FStrip.TabRect(1)));
  AssertEquals('C:\src\Gamma', AskHint(OnCaption(2), r));
  AssertTrue('asked again on leaving Gamma', EqualRect(r, FStrip.TabRect(2)));
end;

procedure TTabStatesTest.ATabWithoutAHintShowsTheStripsAndStillAsksAgainOnLeaving;
var
  r: TRect;
begin
  Build(False);
  FStrip.Hint := 'the strip';
  FProbe.HintPrefix := 'C:\src\';
  FProbe.HintCaps := '|Beta|';
  AssertEquals('Alpha has no hint of its own', 'the strip', AskHint(OnCaption(0), r));
  AssertTrue('but reaching Beta from it asks again', EqualRect(r, FStrip.TabRect(0)));
  AssertEquals('C:\src\Beta', AskHint(OnCaption(1), r));
end;

procedure TTabStatesTest.OffTheTabsTheHintRectReachesNoTab;
var
  r, band, last, body: TRect;
  p: TPoint;
  i: Integer;
  rtl: Boolean;
  tag: string;
begin
  for rtl := False to True do
    for i := 0 to High(AllPositions) do
    begin
      tag := Format('position %d rtl %d: ', [Ord(AllPositions[i]), Ord(rtl)]);
      Build(False, AllPositions[i], rtl);
      FStrip.Hint := 'the strip';
      FProbe.HintPrefix := 'C:\src\';
      band := FStrip.BandRect;
      last := FStrip.TabRect(2);
      { On the band, past the last tab (which is to the LEFT of it on a mirrored row). }
      if FStrip.BandIsVertical then
        p := Point((band.Left + band.Right) div 2, last.Bottom + 10)
      else if rtl then
        p := Point(last.Left - 10, (band.Top + band.Bottom) div 2)
      else
        p := Point(last.Right + 10, (band.Top + band.Bottom) div 2);
      AssertEquals(tag + 'off the tabs: the strip''s own hint', 'the strip', AskHint(p, r));
      AssertTrue(tag + 'the rect holds the pointer', PtInRect(r, p));
      AssertFalse(tag + 'and reaches no tab, so reaching one asks again', TouchesATab(r));
      { On the body, level with the middle tab: the tab is straight above, below or beside. }
      body := FStrip.DisplayRect;
      if FStrip.BandIsVertical then
        p := Point((body.Left + body.Right) div 2, Mid(FStrip.TabRect(1)).Y)
      else
        p := Point(Mid(FStrip.TabRect(1)).X, (body.Top + body.Bottom) div 2);
      AssertEquals(tag + 'the body', 'the strip', AskHint(p, r));
      AssertTrue(tag + 'the body: the rect holds the pointer', PtInRect(r, p));
      AssertFalse(tag + 'the body: it reaches no tab', TouchesATab(r));
      TearDown;
      SetUp;
    end;
end;

procedure TTabStatesTest.OnShowHintStillHasTheLastWord;
var
  marker: THintMarker;
  r: TRect;
begin
  Build(False);
  FProbe.HintPrefix := 'C:\src\';
  marker := THintMarker.Create;
  try
    FStrip.OnShowHint := @marker.Handle;
    AssertEquals('the handler is handed the tab''s hint, and may change it',
      'C:\src\Beta (seen)', AskHint(OnCaption(1), r));
  finally
    marker.Free;
  end;
end;

{ --- the two published strips --------------------------------------------------------- }

procedure TTabStatesTest.TabSetAndPageControlPublishTheStateMembers;

  procedure Check(AClass: TClass);
  var
    pi: PPropInfo;
  begin
    pi := GetPropInfo(AClass, 'MiddleClickClose');
    AssertNotNull(AClass.ClassName + ' publishes MiddleClickClose', pi);
    AssertEquals(AClass.ClassName + ': declared default True, as constructed',
      Ord(True), pi^.Default);
    pi := GetPropInfo(AClass, 'OnGetTabState');
    AssertNotNull(AClass.ClassName + ' publishes OnGetTabState', pi);
    AssertTrue('an event', pi^.PropType^.Kind = tkMethod);
    pi := GetPropInfo(AClass, 'OnTabPinClick');
    AssertNotNull(AClass.ClassName + ' publishes OnTabPinClick', pi);
    AssertTrue('an event', pi^.PropType^.Kind = tkMethod);
  end;

var
  t: TTyTabSet;
  p: TTyPageControl;
begin
  Check(TTyTabSet);
  Check(TTyPageControl);
  t := TTyTabSet.Create(nil);
  p := TTyPageControl.Create(nil);
  try
    AssertTrue('a tab set is built with middle-click close on', t.MiddleClickClose);
    AssertTrue('and so is a page control', p.MiddleClickClose);
  finally
    p.Free;
    t.Free;
  end;
end;

procedure TTabStatesTest.ATabSetOfStringsCarriesStates;
var
  t: TStateTabSet;
  r: TRect;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 640, 480);
  t := TStateTabSet.Create(FForm);
  t.Parent := FForm;
  t.Font.PixelsPerInch := 96;
  t.SetBounds(0, 0, 600, 32);
  t.Tabs.AddStrings(['Alpha', 'Beta', 'Gamma', 'Delta']);
  t.TabIndex := 0;
  t.TabsClosable := True;
  t.OnGetTabState := @FProbe.Handle;
  t.OnTabPinClick := @FPin.Handle;
  t.OnTabClose := @FClose.Handle;
  FProbe.PinnedCaps := '|Alpha|';
  FProbe.ModifiedCaps := '|Gamma|';

  AssertEquals('strings have no state of their own; the event gives it',
    Ord(tsmPin), Ord(t.TabSlotMark(0)));
  AssertEquals(Ord(tsmModified), Ord(t.TabSlotMark(2)));
  AssertEquals(Ord(tsmClose), Ord(t.TabSlotMark(1)));

  { The pin is a button of its own. }
  r := t.TabSlotRect(0);
  t.Press(mbLeft, Point((r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2));
  t.Release(mbLeft, Point((r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2));
  AssertEquals(1, FPin.Count);
  AssertEquals('nothing closed', 4, t.Tabs.Count);

  { A middle click closes Beta: the string goes, and Gamma's dot is now at index 1. }
  r := t.TabRect(1);
  t.Press(mbMiddle, Point(r.Left + 4, (r.Top + r.Bottom) div 2));
  t.Release(mbMiddle, Point(r.Left + 4, (r.Top + r.Bottom) div 2));
  AssertEquals('asked', 1, FClose.Count);
  AssertEquals('Alpha,Gamma,Delta', t.Tabs.CommaText);
  AssertEquals('the dot is where Gamma is', Ord(tsmModified), Ord(t.TabSlotMark(1)));

  { A drag of Delta to the front stops behind pinned Alpha. }
  r := t.TabRect(2);
  t.Press(mbLeft, Point(r.Left + 4, (r.Top + r.Bottom) div 2));
  t.MoveTo(Point(2, (r.Top + r.Bottom) div 2), [ssLeft]);
  t.Release(mbLeft, Point(2, (r.Top + r.Bottom) div 2));
  AssertEquals('Alpha,Delta,Gamma', t.Tabs.CommaText);
end;

procedure TTabStatesTest.APageControlCarriesStates;
var
  p: TStatePager;
  r: TRect;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 640, 480);
  p := TStatePager.Create(FForm);
  p.Parent := FForm;
  p.Font.PixelsPerInch := 96;
  p.SetBounds(0, 0, 600, 300);
  p.AddPage('Alpha');
  p.AddPage('Beta');
  p.AddPage('Gamma');
  p.OnGetTabState := @FProbe.Handle;
  p.OnTabPinClick := @FPin.Handle;
  p.OnTabClose := @FClose.Handle;
  FProbe.PinnedCaps := '|Beta|';
  FProbe.ModifiedCaps := '|Gamma|';

  { No close buttons: only the two tabs with something to show have a slot. }
  AssertTrue(IsRectEmpty(p.TabSlotRect(0)));
  AssertEquals(Ord(tsmPin), Ord(p.TabSlotMark(1)));
  AssertEquals(Ord(tsmModified), Ord(p.TabSlotMark(2)));
  r := p.TabSlotRect(1);
  p.Press(mbLeft, Point((r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2));
  p.Release(mbLeft, Point((r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2));
  AssertEquals('the pin of a page''s tab', 1, FPin.Count);
  AssertEquals(1, FPin.LastIndex);
  AssertEquals('the page shown is still the first', 0, p.ActivePageIndex);

  { A middle click closes a page only where pages can be closed. }
  r := p.TabRect(2);
  p.Press(mbMiddle, Point(r.Left + 4, (r.Top + r.Bottom) div 2));
  p.Release(mbMiddle, Point(r.Left + 4, (r.Top + r.Bottom) div 2));
  AssertEquals('no close buttons: the page stays', 3, p.PageCount);
  p.TabsClosable := True;
  r := p.TabRect(2);
  p.Press(mbMiddle, Point(r.Left + 4, (r.Top + r.Bottom) div 2));
  p.Release(mbMiddle, Point(r.Left + 4, (r.Top + r.Bottom) div 2));
  AssertEquals('asked about Gamma', 2, FClose.LastIndex);
  AssertEquals('and the page is gone', 2, p.PageCount);
  AssertEquals('Beta', p.Pages[1].Caption);
end;

initialization
  RegisterTest(TTabStatesTest);
end.
