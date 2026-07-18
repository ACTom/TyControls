unit test.segmented;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, LCLType, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Controller, tyControls.Segmented;

type
  { Pure-rules tests: the geometry and the selection/keyboard rules take only integers,
    so they run with no window handle, no theme and no control instance at all. }
  TTySegmentedRulesTest = class(TTestCase)
  published
    procedure TestSegmentsTileTheBand;
    procedure TestEqualWidthsWhenTheBandDivides;
    procedure TestBandInsetByPadOnAllSides;
    procedure TestWidthsDifferByAtMostOnePx;
    procedure TestIndexOutOfRangeIsEmpty;
    procedure TestZeroCountIsEmpty;
    procedure TestZeroSizeIsEmpty;
    procedure TestPadEatsWholeTrack;
    procedure TestIndexAtIsTheInverseOfItemRect;
    procedure TestIndexAtGutterAndOutsideAreNone;
    procedure TestValidIndexRejectsOutOfRange;
    procedure TestStepMovesOneSegment;
    procedure TestStepClampsAtTheEnds;
    procedure TestStepFromNoneEntersTheRow;
    procedure TestStepOnAnEmptyRowIsNone;
    procedure TestPreferredWidthRoundTrips;
    procedure TestPreferredWidthHonoursMinItemWidth;
    procedure TestPreferredWidthOfAnEmptyTrackIsPadOnly;
  end;

  { Headless control behaviour: typeKey, defaults, theme-driven geometry, the click and
    keyboard selection rules, AutoSize measurement, and graceful degradation when the
    theme leaves a key undefined. }
  TTySegmentedControlTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FForm: TForm;
    FChanged: Integer;      // OnChange fire count
    procedure HandleChange(Sender: TObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTypeKey;
    procedure TestDefaults;
    procedure TestSegmentRectUsesTheBuiltInPadFallback;
    procedure TestSegmentRectFollowsThemePadMetric;
    procedure TestSegmentAtIsTheInverseOfSegmentRect;
    procedure TestClickSelectsTheSegment;
    procedure TestClickInTheGutterKeepsTheSelection;
    procedure TestDisabledIgnoresAClick;
    procedure TestOnChangeFiresOnceForACodeSet;
    procedure TestReselectingTheSameSegmentIsSilent;
    procedure TestOutOfRangeItemIndexIsNone;
    procedure TestShrinkingItemsResetsAStrandedSelectionSilently;
    procedure TestArrowsMoveTheSelection;
    procedure TestArrowsClampAtTheEnds;
    procedure TestArrowFromNoneEntersTheRow;
    procedure TestHomeAndEndJumpToTheEnds;
    procedure TestDisabledLeavesKeysAlone;
    procedure TestAnEmptyRowLeavesKeysAlone;
    procedure TestPadMetricRetunesThePreferredSize;
    procedure TestTrackFontIsMeasuredIntoTheSegments;
    procedure TestBackgroundlessTrackIsInert;
    procedure TestPreferredWidthHonoursTheMinWidthMetric;
    procedure TestPreferredWidthGrowsWithALongerLabel;
    procedure TestSelectedSegmentTakesTheSelectedStyle;
    procedure TestUnselectedSegmentDoesNotTakeIt;
    procedure TestDisabledKeepsTheSelectedChip;
    procedure TestHoveredSegmentTakesTheHoverStyle;
    procedure TestUndefinedTrackKeyDrawsNothing;
    procedure TestUndefinedItemKeyStillDrawsLabelsInTheTrackInk;
  end;

implementation

type
  { Reaches the protected paint / measure / input seams. }
  TSegAccess = class(TTySegmented)
  public
    function StyleTypeKey: string;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure ClickAt(X, Y: Integer);
    procedure MoveTo(X, Y: Integer);
    { True = the control consumed the key (zeroed it), so it never reaches the form. }
    function PressKey(AKey: Word): Boolean;
    { The size AutoSize would fit the track to. Called directly rather than through
      AutoSize itself: LCL's AutoSizeDelayed suppresses every re-fit while the parent form
      has no handle (the headless runner never realises one), so driving AutoSize here
      would assert on inert plumbing instead of on this control's measurement. }
    procedure PreferredSize(out AWidth, AHeight: Integer);
  end;

function TSegAccess.StyleTypeKey: string;
begin
  Result := GetStyleTypeKey;
end;

procedure TSegAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TSegAccess.ClickAt(X, Y: Integer);
begin
  MouseDown(mbLeft, [], X, Y);
  MouseUp(mbLeft, [], X, Y);
end;

procedure TSegAccess.MoveTo(X, Y: Integer);
begin
  MouseMove([], X, Y);
end;

function TSegAccess.PressKey(AKey: Word): Boolean;
var
  k: Word;
begin
  k := AKey;
  KeyDown(k, []);
  Result := k = 0;
end;

procedure TSegAccess.PreferredSize(out AWidth, AHeight: Integer);
begin
  AWidth := 0;
  AHeight := 0;
  CalculatePreferredSize(AWidth, AHeight, True);
end;

{ Build a themed, parented, 96-PPI segmented control with ACount lettered segments. Shared
  by nearly every control test, which otherwise repeat the same six lines. }
function MakeSeg(AForm: TForm; ACtl: TTyStyleController; ACount: Integer): TSegAccess;
var
  i: Integer;
begin
  Result := TSegAccess.Create(AForm);
  Result.Parent := AForm;
  Result.Controller := ACtl;
  Result.Font.PixelsPerInch := 96;
  for i := 0 to ACount - 1 do
    Result.Items.Add(Chr(Ord('A') + i));
end;

{ TTySegmentedRulesTest }

procedure TTySegmentedRulesTest.TestSegmentsTileTheBand;
var
  a, b, c: TRect;
begin
  // 300x30, pad 2, 3 segments. The segments must tile the padded band with no seam a
  // click could fall into: each one's right edge IS the next one's left edge.
  a := TySegmentedItemRect(300, 30, 3, 2, 0);
  b := TySegmentedItemRect(300, 30, 3, 2, 1);
  c := TySegmentedItemRect(300, 30, 3, 2, 2);
  AssertEquals('first segment starts at the pad', 2, a.Left);
  AssertEquals('no seam between 0 and 1', a.Right, b.Left);
  AssertEquals('no seam between 1 and 2', b.Right, c.Left);
  AssertEquals('last segment ends at the pad', 298, c.Right);
end;

procedure TTySegmentedRulesTest.TestEqualWidthsWhenTheBandDivides;
var
  i: Integer;
  R: TRect;
begin
  // 302 wide, pad 1 -> a 300px band over 3 segments divides exactly: 100px each.
  for i := 0 to 2 do
  begin
    R := TySegmentedItemRect(302, 30, 3, 1, i);
    AssertEquals(Format('segment %d is an exact third', [i]), 100, R.Right - R.Left);
  end;
end;

procedure TTySegmentedRulesTest.TestBandInsetByPadOnAllSides;
var
  R: TRect;
begin
  // The pad is a track inset on all FOUR sides — that sliver of visible track around the
  // chips is what makes the control read as a thumb in a groove.
  R := TySegmentedItemRect(300, 30, 3, 4, 0);
  AssertEquals('inset from the left', 4, R.Left);
  AssertEquals('inset from the top', 4, R.Top);
  AssertEquals('inset from the bottom', 26, R.Bottom);
  R := TySegmentedItemRect(300, 30, 3, 4, 2);
  AssertEquals('inset from the right', 296, R.Right);
end;

procedure TTySegmentedRulesTest.TestWidthsDifferByAtMostOnePx;
var
  i, w, minW, maxW: Integer;
  R: TRect;
begin
  // A band of 100 over 3 segments cannot divide evenly. Integer division spreads the
  // remainder rather than dumping it: no segment is ever more than a pixel off its
  // neighbours, and they still tile exactly (asserted above).
  minW := MaxInt;
  maxW := 0;
  for i := 0 to 2 do
  begin
    R := TySegmentedItemRect(100, 30, 3, 0, i);
    w := R.Right - R.Left;
    if w < minW then minW := w;
    if w > maxW then maxW := w;
  end;
  AssertTrue(Format('widths within 1px (%d..%d)', [minW, maxW]), maxW - minW <= 1);
  // And the tiling still covers the whole band.
  AssertEquals('the band is fully covered', 100, TySegmentedItemRect(100, 30, 3, 0, 2).Right);
end;

procedure TTySegmentedRulesTest.TestIndexOutOfRangeIsEmpty;
var
  R: TRect;
begin
  R := TySegmentedItemRect(300, 30, 3, 2, 3);
  AssertEquals('index past the last segment', 0, R.Right - R.Left);
  R := TySegmentedItemRect(300, 30, 3, 2, -1);
  AssertEquals('negative index', 0, R.Right - R.Left);
end;

procedure TTySegmentedRulesTest.TestZeroCountIsEmpty;
var
  R: TRect;
begin
  R := TySegmentedItemRect(300, 30, 0, 2, 0);
  AssertEquals('no segments, no rect', 0, R.Right - R.Left);
  AssertEquals('and nothing to hit', -1, TySegmentedIndexAt(300, 30, 0, 2, 150, 15));
end;

procedure TTySegmentedRulesTest.TestZeroSizeIsEmpty;
var
  R: TRect;
begin
  R := TySegmentedItemRect(0, 30, 3, 2, 0);
  AssertEquals('zero width', 0, R.Right - R.Left);
  R := TySegmentedItemRect(300, 0, 3, 2, 0);
  AssertEquals('zero height', 0, R.Bottom - R.Top);
end;

procedure TTySegmentedRulesTest.TestPadEatsWholeTrack;
var
  R: TRect;
begin
  // Padding wider/taller than the track: nothing fits — an empty rect, never an inverted
  // one, and nothing to click.
  R := TySegmentedItemRect(10, 30, 3, 8, 0);
  AssertEquals('pad eats the width', 0, R.Right - R.Left);
  R := TySegmentedItemRect(300, 10, 3, 8, 0);
  AssertEquals('pad eats the height', 0, R.Bottom - R.Top);
  AssertEquals('nothing to hit either', -1, TySegmentedIndexAt(10, 30, 3, 8, 5, 15));
end;

procedure TTySegmentedRulesTest.TestIndexAtIsTheInverseOfItemRect;
var
  i, hit: Integer;
  R: TRect;
begin
  // The contract that keeps the click and the paint honest: the centre of every painted
  // segment hit-tests back to that same segment, and so do its exact edges.
  for i := 0 to 3 do
  begin
    R := TySegmentedItemRect(300, 30, 4, 2, i);
    hit := TySegmentedIndexAt(300, 30, 4, 2, (R.Left + R.Right) div 2, 15);
    AssertEquals(Format('centre of segment %d', [i]), i, hit);
    hit := TySegmentedIndexAt(300, 30, 4, 2, R.Left, 15);
    AssertEquals(Format('left edge of segment %d belongs to it', [i]), i, hit);
    hit := TySegmentedIndexAt(300, 30, 4, 2, R.Right - 1, 15);
    AssertEquals(Format('last px of segment %d belongs to it', [i]), i, hit);
  end;
end;

procedure TTySegmentedRulesTest.TestIndexAtGutterAndOutsideAreNone;
begin
  // The track's padding gutter belongs to no segment, so a click there is inert rather
  // than "the nearest one".
  AssertEquals('left gutter', -1, TySegmentedIndexAt(300, 30, 3, 6, 3, 15));
  AssertEquals('top gutter', -1, TySegmentedIndexAt(300, 30, 3, 6, 150, 3));
  AssertEquals('bottom gutter', -1, TySegmentedIndexAt(300, 30, 3, 6, 150, 27));
  AssertEquals('right gutter', -1, TySegmentedIndexAt(300, 30, 3, 6, 297, 15));
  // Outside the control entirely.
  AssertEquals('past the right edge', -1, TySegmentedIndexAt(300, 30, 3, 2, 400, 15));
  AssertEquals('above the top edge', -1, TySegmentedIndexAt(300, 30, 3, 2, 150, -5));
end;

procedure TTySegmentedRulesTest.TestValidIndexRejectsOutOfRange;
begin
  // The house ItemIndex rule: out of range means NONE, it is not clamped onto an end
  // segment (a caller asking for segment 7 of 3 wanted one that is not there).
  AssertEquals('in range', 1, TySegmentedValidIndex(1, 3));
  AssertEquals('first', 0, TySegmentedValidIndex(0, 3));
  AssertEquals('last', 2, TySegmentedValidIndex(2, 3));
  AssertEquals('past the end is none, not the last', -1, TySegmentedValidIndex(3, 3));
  AssertEquals('far past the end is none', -1, TySegmentedValidIndex(99, 3));
  AssertEquals('negative is none', -1, TySegmentedValidIndex(-1, 3));
  AssertEquals('nothing is selectable in an empty row', -1, TySegmentedValidIndex(0, 0));
end;

procedure TTySegmentedRulesTest.TestStepMovesOneSegment;
begin
  AssertEquals('right', 1, TySegmentedStepIndex(0, 3, 1));
  AssertEquals('left', 0, TySegmentedStepIndex(1, 3, -1));
  AssertEquals('a zero step stays put', 1, TySegmentedStepIndex(1, 3, 0));
end;

procedure TTySegmentedRulesTest.TestStepClampsAtTheEnds;
begin
  // No wrap: the row is short and wholly visible, so running off the end should stop
  // rather than teleport the selection across the control.
  AssertEquals('right at the last segment stays', 2, TySegmentedStepIndex(2, 3, 1));
  AssertEquals('left at the first segment stays', 0, TySegmentedStepIndex(0, 3, -1));
end;

procedure TTySegmentedRulesTest.TestStepFromNoneEntersTheRow;
begin
  // Entering from nowhere lands on the segment the step comes FROM.
  AssertEquals('right enters at the first', 0, TySegmentedStepIndex(-1, 3, 1));
  AssertEquals('left enters at the last', 2, TySegmentedStepIndex(-1, 3, -1));
  // An index stranded past the end counts as "none" for this purpose too.
  AssertEquals('a stranded index re-enters', 0, TySegmentedStepIndex(9, 3, 1));
end;

procedure TTySegmentedRulesTest.TestStepOnAnEmptyRowIsNone;
begin
  AssertEquals('no segments to step onto', -1, TySegmentedStepIndex(-1, 0, 1));
  AssertEquals('and none going left', -1, TySegmentedStepIndex(0, 0, -1));
end;

procedure TTySegmentedRulesTest.TestPreferredWidthRoundTrips;
var
  w, i: Integer;
  R: TRect;
begin
  // The contract: a track of TySegmentedPreferredWidth(...) gives every segment exactly
  // the natural width — the widest label plus its own padding.
  w := TySegmentedPreferredWidth(3, 50, 8, 8, 2, 48);
  AssertEquals('pad + 3*(text + segment padding) + pad', 202, w);
  for i := 0 to 2 do
  begin
    R := TySegmentedItemRect(w, 30, 3, 2, i);
    AssertEquals(Format('segment %d fits the label exactly', [i]), 66, R.Right - R.Left);
  end;
end;

procedure TTySegmentedRulesTest.TestPreferredWidthHonoursMinItemWidth;
begin
  // Single-glyph options ('A'/'B'/'C') would otherwise measure to a few px each and be
  // unclickable; the floor keeps every segment a real target.
  AssertEquals('the floor wins over a tiny label', 144,
    TySegmentedPreferredWidth(3, 4, 0, 0, 0, 48));
  // ...and a label wider than the floor wins over the floor.
  AssertEquals('a wide label wins over the floor', 300,
    TySegmentedPreferredWidth(3, 100, 0, 0, 0, 48));
end;

procedure TTySegmentedRulesTest.TestPreferredWidthOfAnEmptyTrackIsPadOnly;
begin
  AssertEquals('an empty control is just its own track padding', 4,
    TySegmentedPreferredWidth(0, 50, 8, 8, 2, 48));
end;

{ TTySegmentedControlTest }

procedure TTySegmentedControlTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FForm := TForm.CreateNew(nil);
  FChanged := 0;
end;

procedure TTySegmentedControlTest.TearDown;
begin
  FForm.Free;
  FCtl.Free;
end;

procedure TTySegmentedControlTest.HandleChange(Sender: TObject);
begin
  Inc(FChanged);
end;

procedure TTySegmentedControlTest.TestTypeKey;
var
  T: TSegAccess;
begin
  T := TSegAccess.Create(FForm);
  T.Parent := FForm;
  try
    AssertEquals('TySegmented', T.StyleTypeKey);
  finally
    T.Free;
  end;
end;

procedure TTySegmentedControlTest.TestDefaults;
var
  T: TTySegmented;
begin
  T := TTySegmented.Create(FForm);
  try
    AssertEquals('no segments by default', 0, T.Count);
    AssertEquals('nothing selected by default', -1, T.ItemIndex);
    AssertTrue('focusable: the arrow keys are the point of it', T.TabStop);
    AssertEquals('default width 240', 240, T.Width);
    AssertEquals('default height 30', 30, T.Height);
  finally
    T.Free;
  end;
end;

procedure TTySegmentedControlTest.TestSegmentRectUsesTheBuiltInPadFallback;
var
  T: TSegAccess;
  R: TRect;
begin
  // A theme that sets no --segmented-pad falls back to the named built-in constant —
  // which is the token's default, not a magic number in the geometry.
  FCtl.LoadThemeCss('TySegmented { background: #EEEEEE; color: #111111; }');
  T := MakeSeg(FForm, FCtl, 3);
  try
    T.SetBounds(0, 0, 300, 30);
    R := T.TySegmentRect(0);
    AssertEquals('track pad falls back to the built-in default', TySegmentedPad, R.Left);
    AssertEquals('and on the far side too', 300 - TySegmentedPad, T.TySegmentRect(2).Right);
  finally
    T.Free;
  end;
end;

procedure TTySegmentedControlTest.TestSegmentRectFollowsThemePadMetric;
var
  T: TSegAccess;
  R: TRect;
begin
  // --segmented-pad is a skin-tunable metric: a theme that sets it moves the geometry
  // (and with it the hit-test), proving the inset is not baked into the control.
  FCtl.LoadThemeCss(
    ':root { --segmented-pad: 6px; }' +
    'TySegmented { background: #EEEEEE; color: #111111; }');
  T := MakeSeg(FForm, FCtl, 3);
  try
    T.SetBounds(0, 0, 300, 30);
    R := T.TySegmentRect(0);
    AssertEquals('left inset takes the themed pad', 6, R.Left);
    AssertEquals('top inset too', 6, R.Top);
    AssertEquals('bottom inset too', 24, R.Bottom);
    AssertEquals('and the last segment stops a pad short', 294, T.TySegmentRect(2).Right);
  finally
    T.Free;
  end;
end;

procedure TTySegmentedControlTest.TestSegmentAtIsTheInverseOfSegmentRect;
var
  T: TSegAccess;
  i: Integer;
  R: TRect;
begin
  // Through the live theme this time: what the control paints is what it hit-tests.
  FCtl.LoadThemeCss(
    ':root { --segmented-pad: 3px; }' +
    'TySegmented { background: #EEEEEE; color: #111111; }');
  T := MakeSeg(FForm, FCtl, 3);
  try
    T.SetBounds(0, 0, 300, 30);
    for i := 0 to 2 do
    begin
      R := T.TySegmentRect(i);
      AssertEquals(Format('centre of segment %d hits it', [i]), i,
        T.TySegmentAt((R.Left + R.Right) div 2, 15));
    end;
  finally
    T.Free;
  end;
end;

procedure TTySegmentedControlTest.TestClickSelectsTheSegment;
var
  T: TSegAccess;
  R: TRect;
begin
  FCtl.LoadThemeCss('TySegmented { background: #EEEEEE; color: #111111; }');
  T := MakeSeg(FForm, FCtl, 3);
  try
    T.SetBounds(0, 0, 300, 30);
    T.OnChange := @HandleChange;
    R := T.TySegmentRect(1);
    T.ClickAt((R.Left + R.Right) div 2, 15);
    AssertEquals('the clicked segment is selected', 1, T.ItemIndex);
    AssertEquals('and announced once', 1, FChanged);
  finally
    T.Free;
  end;
end;

procedure TTySegmentedControlTest.TestClickInTheGutterKeepsTheSelection;
var
  T: TSegAccess;
begin
  // The visible sliver of track around the chips is not a segment: clicking it must not
  // clear a selection the user can plainly see.
  FCtl.LoadThemeCss(
    ':root { --segmented-pad: 6px; }' +
    'TySegmented { background: #EEEEEE; color: #111111; }');
  T := MakeSeg(FForm, FCtl, 3);
  try
    T.SetBounds(0, 0, 300, 30);
    T.ItemIndex := 1;
    T.OnChange := @HandleChange;
    T.ClickAt(2, 15);   // inside the 6px left gutter
    AssertEquals('the selection is untouched', 1, T.ItemIndex);
    AssertEquals('and nothing was announced', 0, FChanged);
  finally
    T.Free;
  end;
end;

procedure TTySegmentedControlTest.TestDisabledIgnoresAClick;
var
  T: TSegAccess;
  R: TRect;
begin
  FCtl.LoadThemeCss('TySegmented { background: #EEEEEE; color: #111111; }');
  T := MakeSeg(FForm, FCtl, 3);
  try
    T.SetBounds(0, 0, 300, 30);
    T.ItemIndex := 0;
    T.OnChange := @HandleChange;
    T.Enabled := False;
    R := T.TySegmentRect(2);
    T.ClickAt((R.Left + R.Right) div 2, 15);
    AssertEquals('a disabled control does not select', 0, T.ItemIndex);
    AssertEquals('and announces nothing', 0, FChanged);
  finally
    T.Free;
  end;
end;

procedure TTySegmentedControlTest.TestOnChangeFiresOnceForACodeSet;
var
  T: TSegAccess;
begin
  // OnChange means "the selection changed", by any route — a code set counts (this is
  // TTyListBox.ItemIndex's contract, the pair this control borrows).
  FCtl.LoadThemeCss('TySegmented { background: #EEEEEE; color: #111111; }');
  T := MakeSeg(FForm, FCtl, 3);
  try
    T.OnChange := @HandleChange;
    T.ItemIndex := 2;
    AssertEquals('announced once', 1, FChanged);
    AssertEquals('and it took', 2, T.ItemIndex);
  finally
    T.Free;
  end;
end;

procedure TTySegmentedControlTest.TestReselectingTheSameSegmentIsSilent;
var
  T: TSegAccess;
  R: TRect;
begin
  FCtl.LoadThemeCss('TySegmented { background: #EEEEEE; color: #111111; }');
  T := MakeSeg(FForm, FCtl, 3);
  try
    T.SetBounds(0, 0, 300, 30);
    T.ItemIndex := 1;
    T.OnChange := @HandleChange;
    T.ItemIndex := 1;
    AssertEquals('setting the same index is not a change', 0, FChanged);
    R := T.TySegmentRect(1);
    T.ClickAt((R.Left + R.Right) div 2, 15);
    AssertEquals('nor is clicking the segment already selected', 0, FChanged);
  finally
    T.Free;
  end;
end;

procedure TTySegmentedControlTest.TestOutOfRangeItemIndexIsNone;
var
  T: TSegAccess;
begin
  FCtl.LoadThemeCss('TySegmented { background: #EEEEEE; color: #111111; }');
  T := MakeSeg(FForm, FCtl, 3);
  try
    T.ItemIndex := 7;
    AssertEquals('past the end means none, not the last segment', -1, T.ItemIndex);
    T.ItemIndex := -5;
    AssertEquals('and so does any negative', -1, T.ItemIndex);
  finally
    T.Free;
  end;
end;

procedure TTySegmentedControlTest.TestShrinkingItemsResetsAStrandedSelectionSilently;
var
  T: TSegAccess;
begin
  FCtl.LoadThemeCss('TySegmented { background: #EEEEEE; color: #111111; }');
  T := MakeSeg(FForm, FCtl, 3);
  try
    T.ItemIndex := 2;
    T.OnChange := @HandleChange;
    T.Items.Delete(2);   // the selected segment is gone
    AssertEquals('the stranded selection resets to none', -1, T.ItemIndex);
    // Editing Items is the host's own action, not a user selection: it must not hand the
    // host back a "something was picked" event it never asked about.
    AssertEquals('a list edit is not a selection change', 0, FChanged);
  finally
    T.Free;
  end;
end;

procedure TTySegmentedControlTest.TestArrowsMoveTheSelection;
var
  T: TSegAccess;
begin
  FCtl.LoadThemeCss('TySegmented { background: #EEEEEE; color: #111111; }');
  T := MakeSeg(FForm, FCtl, 3);
  try
    T.ItemIndex := 0;
    T.OnChange := @HandleChange;
    AssertTrue('Right is consumed', T.PressKey(VK_RIGHT));
    AssertEquals('Right moves on', 1, T.ItemIndex);
    AssertTrue('Left is consumed', T.PressKey(VK_LEFT));
    AssertEquals('Left moves back', 0, T.ItemIndex);
    AssertEquals('each move announced', 2, FChanged);
  finally
    T.Free;
  end;
end;

procedure TTySegmentedControlTest.TestArrowsClampAtTheEnds;
var
  T: TSegAccess;
begin
  FCtl.LoadThemeCss('TySegmented { background: #EEEEEE; color: #111111; }');
  T := MakeSeg(FForm, FCtl, 3);
  try
    T.ItemIndex := 2;
    T.OnChange := @HandleChange;
    T.PressKey(VK_RIGHT);
    AssertEquals('no wrap off the right end', 2, T.ItemIndex);
    T.ItemIndex := 0;
    FChanged := 0;
    T.PressKey(VK_LEFT);
    AssertEquals('no wrap off the left end', 0, T.ItemIndex);
    AssertEquals('a blocked move is not a change', 0, FChanged);
  finally
    T.Free;
  end;
end;

procedure TTySegmentedControlTest.TestArrowFromNoneEntersTheRow;
var
  T: TSegAccess;
begin
  FCtl.LoadThemeCss('TySegmented { background: #EEEEEE; color: #111111; }');
  T := MakeSeg(FForm, FCtl, 3);
  try
    AssertEquals('nothing selected to start', -1, T.ItemIndex);
    T.PressKey(VK_RIGHT);
    AssertEquals('Right enters at the first segment', 0, T.ItemIndex);
    T.ItemIndex := -1;
    T.PressKey(VK_LEFT);
    AssertEquals('Left enters at the last segment', 2, T.ItemIndex);
  finally
    T.Free;
  end;
end;

procedure TTySegmentedControlTest.TestHomeAndEndJumpToTheEnds;
var
  T: TSegAccess;
begin
  FCtl.LoadThemeCss('TySegmented { background: #EEEEEE; color: #111111; }');
  T := MakeSeg(FForm, FCtl, 3);
  try
    T.ItemIndex := 1;
    AssertTrue('End is consumed', T.PressKey(VK_END));
    AssertEquals('End takes the last', 2, T.ItemIndex);
    AssertTrue('Home is consumed', T.PressKey(VK_HOME));
    AssertEquals('Home takes the first', 0, T.ItemIndex);
  finally
    T.Free;
  end;
end;

procedure TTySegmentedControlTest.TestDisabledLeavesKeysAlone;
var
  T: TSegAccess;
begin
  FCtl.LoadThemeCss('TySegmented { background: #EEEEEE; color: #111111; }');
  T := MakeSeg(FForm, FCtl, 3);
  try
    T.ItemIndex := 0;
    T.Enabled := False;
    // Not merely ignored — NOT CONSUMED: a disabled control must let the key travel on to
    // whatever else the form would do with it.
    AssertFalse('the key is left for the form', T.PressKey(VK_RIGHT));
    AssertEquals('and the selection is untouched', 0, T.ItemIndex);
  finally
    T.Free;
  end;
end;

procedure TTySegmentedControlTest.TestAnEmptyRowLeavesKeysAlone;
var
  T: TSegAccess;
begin
  FCtl.LoadThemeCss('TySegmented { background: #EEEEEE; color: #111111; }');
  T := MakeSeg(FForm, FCtl, 0);
  try
    AssertFalse('nothing to move: the key travels on', T.PressKey(VK_RIGHT));
    AssertEquals('still nothing selected', -1, T.ItemIndex);
  finally
    T.Free;
  end;
end;

procedure TTySegmentedControlTest.TestPadMetricRetunesThePreferredSize;
var
  T: TSegAccess;
  w0, h0, w5, h5: Integer;
begin
  // The same control, the same labels, two themes: the pad token alone must move the
  // measurement by exactly twice itself on each axis. Comparing two measures in the SAME
  // font sidesteps any dependence on actual glyph extents.
  FCtl.LoadThemeCss(
    ':root { --segmented-pad: 0px; }' +
    'TySegmented { background: #EEEEEE; color: #111111; }' +
    'TySegmentedItem { color: #111111; font-size: 12px; }');
  T := MakeSeg(FForm, FCtl, 3);
  try
    T.PreferredSize(w0, h0);
    FCtl.LoadThemeCss(
      ':root { --segmented-pad: 5px; }' +
      'TySegmented { background: #EEEEEE; color: #111111; }' +
      'TySegmentedItem { color: #111111; font-size: 12px; }');
    T.PreferredSize(w5, h5);
    AssertEquals('the pad adds to the width on both sides', w0 + 10, w5);
    AssertEquals('and to the height on both sides', h0 + 10, h5);
  finally
    T.Free;
  end;
end;

procedure TTySegmentedControlTest.TestPreferredWidthHonoursTheMinWidthMetric;
var
  T: TSegAccess;
  w, h: Integer;
begin
  // Single-glyph labels measure to a few px, so the floor is what decides the width —
  // and --segmented-min-width is the theme's handle on it.
  FCtl.LoadThemeCss(
    ':root { --segmented-pad: 0px; }' +
    'TySegmented { background: #EEEEEE; color: #111111; }' +
    'TySegmentedItem { color: #111111; font-size: 12px; }');
  T := MakeSeg(FForm, FCtl, 3);
  try
    T.PreferredSize(w, h);
    AssertEquals('three segments at the built-in floor', 3 * TySegmentedMinWidth, w);
    FCtl.LoadThemeCss(
      ':root { --segmented-pad: 0px; --segmented-min-width: 30px; }' +
      'TySegmented { background: #EEEEEE; color: #111111; }' +
      'TySegmentedItem { color: #111111; font-size: 12px; }');
    T.PreferredSize(w, h);
    AssertEquals('the theme retunes the floor', 90, w);
  finally
    T.Free;
  end;
end;

procedure TTySegmentedControlTest.TestPreferredWidthGrowsWithALongerLabel;
var
  T: TSegAccess;
  narrowW, wideW, h: Integer;
begin
  // With the floor out of the way the labels drive the width, measured in the THEME's
  // font. Every segment takes the WIDEST label's width, so one long option widens all.
  FCtl.LoadThemeCss(
    ':root { --segmented-pad: 0px; --segmented-min-width: 0px; }' +
    'TySegmented { background: #EEEEEE; color: #111111; }' +
    'TySegmentedItem { color: #111111; font-size: 12px; }');
  T := MakeSeg(FForm, FCtl, 0);
  try
    T.Items.Add('A');
    T.PreferredSize(narrowW, h);
    T.Items[0] := 'a much longer segment label';
    T.PreferredSize(wideW, h);
    AssertTrue('a longer label needs a wider track', wideW > narrowW);
  finally
    T.Free;
  end;
end;

{ Render T into a fresh 300x30 white bitmap and hand back the re-read BGRA copy. The
  caller frees the result. }
function RenderSeg(T: TSegAccess): TBGRABitmap;
var
  Bmp: TBitmap;
begin
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(300, 30);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 300, 30);
    T.RenderTo(Bmp.Canvas, Rect(0, 0, 300, 30), 96);
    Result := TBGRABitmap.Create(Bmp);
  finally
    Bmp.Free;
  end;
end;

{ True when any pixel in ARect is strongly blue — the #3B82F6 chip these tests theme with.
  A structural probe, not an exact-pixel one: the headless runner draws text in BGRA's own
  default font, so nothing here may depend on glyph extents. }
function HasBlueChip(R: TBGRABitmap; const ARect: TRect): Boolean;
var
  x, y: Integer;
  px: TBGRAPixel;
begin
  Result := False;
  for y := ARect.Top to ARect.Bottom - 1 do
    for x := ARect.Left to ARect.Right - 1 do
    begin
      px := R.GetPixel(x, y);
      if (px.blue > 180) and (px.red < 120) then Exit(True);
    end;
end;

procedure TTySegmentedControlTest.TestSelectedSegmentTakesTheSelectedStyle;
var
  T: TSegAccess;
  Reread: TBGRABitmap;
begin
  // The whole point of the control: the selected segment carries tysSelected, so the
  // theme's ':selected' rule (the very state TTyButton.Down injects) paints its chip.
  FCtl.LoadThemeCss(
    ':root { --segmented-pad: 0px; }' +
    'TySegmented { background: #FFFFFF; color: #111111; }' +
    'TySegmentedItem { color: #111111; }' +
    'TySegmentedItem:selected { background: #3B82F6; color: #FFFFFF; }');
  T := MakeSeg(FForm, FCtl, 3);
  try
    T.SetBounds(0, 0, 300, 30);
    T.ItemIndex := 1;
    Reread := RenderSeg(T);
    try
      AssertTrue('the selected segment is filled by the :selected rule',
        HasBlueChip(Reread, T.TySegmentRect(1)));
    finally
      Reread.Free;
    end;
  finally
    T.Free;
  end;
end;

procedure TTySegmentedControlTest.TestUnselectedSegmentDoesNotTakeIt;
var
  T: TSegAccess;
  Reread: TBGRABitmap;
begin
  // The other half of the same rule — without this, "everything is blue" would pass above.
  FCtl.LoadThemeCss(
    ':root { --segmented-pad: 0px; }' +
    'TySegmented { background: #FFFFFF; color: #111111; }' +
    'TySegmentedItem { color: #111111; }' +
    'TySegmentedItem:selected { background: #3B82F6; color: #FFFFFF; }');
  T := MakeSeg(FForm, FCtl, 3);
  try
    T.SetBounds(0, 0, 300, 30);
    T.ItemIndex := 1;
    Reread := RenderSeg(T);
    try
      AssertFalse('the resting segments keep the track',
        HasBlueChip(Reread, T.TySegmentRect(0)));
      AssertFalse('all of them',
        HasBlueChip(Reread, T.TySegmentRect(2)));
    finally
      Reread.Free;
    end;
  finally
    T.Free;
  end;
end;

procedure TTySegmentedControlTest.TestDisabledKeepsTheSelectedChip;
var
  T: TSegAccess;
  Reread: TBGRABitmap;
begin
  // A deliberate deviation from TTyButton.Down (which drops :selected when disabled): the
  // selection is the only thing this control says, so a greyed-out one must still show
  // WHICH option is in force — "you cannot change this", not "nothing is selected". The
  // cascade layers :disabled over :selected, so the chip survives and only the ink greys.
  FCtl.LoadThemeCss(
    ':root { --segmented-pad: 0px; }' +
    'TySegmented { background: #FFFFFF; color: #111111; }' +
    'TySegmentedItem:selected { background: #3B82F6; color: #FFFFFF; }' +
    'TySegmentedItem:disabled { color: #888888; }');
  T := MakeSeg(FForm, FCtl, 3);
  try
    T.SetBounds(0, 0, 300, 30);
    T.ItemIndex := 1;
    T.Enabled := False;
    Reread := RenderSeg(T);
    try
      AssertTrue('a disabled control still shows its selected chip',
        HasBlueChip(Reread, T.TySegmentRect(1)));
      AssertFalse('and still only that one',
        HasBlueChip(Reread, T.TySegmentRect(0)));
    finally
      Reread.Free;
    end;
  finally
    T.Free;
  end;
end;

procedure TTySegmentedControlTest.TestHoveredSegmentTakesTheHoverStyle;
var
  T: TSegAccess;
  Reread: TBGRABitmap;
  R: TRect;
begin
  // Hover is per SEGMENT, not per track: the pointer lights up the one segment under it.
  FCtl.LoadThemeCss(
    ':root { --segmented-pad: 0px; }' +
    'TySegmented { background: #FFFFFF; color: #111111; }' +
    'TySegmentedItem { color: #111111; }' +
    'TySegmentedItem:hover { background: #3B82F6; }');
  T := MakeSeg(FForm, FCtl, 3);
  try
    T.SetBounds(0, 0, 300, 30);
    R := T.TySegmentRect(1);
    T.MoveTo((R.Left + R.Right) div 2, 15);
    Reread := RenderSeg(T);
    try
      AssertTrue('the hovered segment lights up', HasBlueChip(Reread, T.TySegmentRect(1)));
      AssertFalse('its neighbour does not', HasBlueChip(Reread, T.TySegmentRect(0)));
    finally
      Reread.Free;
    end;
  finally
    T.Free;
  end;
end;

procedure TTySegmentedControlTest.TestUndefinedTrackKeyDrawsNothing;
var
  T: TSegAccess;
  Reread: TBGRABitmap;
begin
  // A theme that gives the track no BACKGROUND must degrade, not invent a look: nothing of
  // ours is drawn at all — not even the segments, whose own key IS defined here.
  // The TySegmented rule below is deliberately present-but-backgroundless rather than absent:
  // the compiled-in base layer (themes/light.tycss) backs every typeKey a theme omits, so
  // "leave the rule out" would silently stop testing degradation the moment the base defines
  // TySegmented (it now does). Any user rule for a typeKey suppresses the whole base layer for
  // it (TTyStyleModel.UserHasTypeKey), so this is how you get a genuinely background-less key.
  FCtl.LoadThemeCss('TySegmented { color: #000000; }' + LineEnding
    + 'TySegmentedItem:selected { background: #3B82F6; color: #FFFFFF; }');
  T := MakeSeg(FForm, FCtl, 3);
  try
    T.SetBounds(0, 0, 300, 30);
    T.ItemIndex := 1;
    Reread := RenderSeg(T);
    try
      AssertFalse('no track key -> no chips anywhere',
        HasBlueChip(Reread, Rect(0, 0, 300, 30)));
    finally
      Reread.Free;
    end;
  finally
    T.Free;
  end;
end;

procedure TTySegmentedControlTest.TestUndefinedItemKeyStillDrawsLabelsInTheTrackInk;
var
  T: TSegAccess;
  Reread: TBGRABitmap;
  R: TRect;
  x, y: Integer;
  px: TBGRAPixel;
  found: Boolean;
begin
  // The other degradation half: a segment key carrying no COLOUR gets no chips (no background
  // to draw one from) but its labels still appear, in the TRACK's own ink.
  // White track, GREEN ink, and a TySegmentedItem rule with neither background nor color: any
  // green pixel in a segment can only be a label that inherited the track's colour — never a
  // hard-coded fallback. (The item rule must be PRESENT to suppress the base layer's own
  // TySegmentedItem, which does define a colour; omitting it would inherit that instead and
  // test nothing. Same reason as TestUndefinedTrackKeyDrawsNothing.)
  FCtl.LoadThemeCss('TySegmented { background: #FFFFFF; color: #10B981; font-size: 12px; }'
    + LineEnding + 'TySegmentedItem { border-radius: 0; }');
  T := MakeSeg(FForm, FCtl, 3);
  try
    T.SetBounds(0, 0, 300, 30);
    Reread := RenderSeg(T);
    try
      R := T.TySegmentRect(1);
      found := False;
      for y := R.Top to R.Bottom - 1 do
        for x := R.Left to R.Right - 1 do
        begin
          px := Reread.GetPixel(x, y);
          if (px.green > 120) and (px.green > px.red + 30) and (px.green > px.blue + 30) then
          begin
            found := True;
            Break;
          end;
        end;
      AssertTrue('the label inherits the track ink', found);
    finally
      Reread.Free;
    end;
  finally
    T.Free;
  end;
end;

{ Adversarial-review finding (CONFIRMED): AutoSize measured labels in the segment's OWN font, but
  the paint draws them in the TRACK-inherited font (ItemTextStyle). A theme that fonts TySegmented
  but not TySegmentedItem then under-measured and clipped. Guard: a bigger TRACK font widens. }
procedure TTySegmentedControlTest.TestTrackFontIsMeasuredIntoTheSegments;

  function PrefWidth(ATrackFontPx: Integer): Integer;
  var Ctl: TTyStyleController; T: TSegAccess; w, h: Integer;
  begin
    Ctl := TTyStyleController.Create(nil);
    try
      Ctl.LoadThemeCss(Format('TySegmented { background: #FFF; color: #000; font-size: %dpx; }'
        + 'TySegmentedItem { }', [ATrackFontPx]));   // empty item rule -> suppresses base, inherits
      T := MakeSeg(FForm, Ctl, 3);
      T.Items.Clear; T.Items.Add('Monday'); T.Items.Add('Wednesday'); T.Items.Add('Saturday');
      T.PreferredSize(w, h);
      Result := w;
    finally Ctl.Free; end;
  end;

var wSmall, wBig: Integer;
begin
  wSmall := PrefWidth(8);
  wBig := PrefWidth(24);
  AssertTrue(Format('a bigger track font widens the segments (8px -> %d, 24px -> %d)',
    [wSmall, wBig]), wBig > wSmall);
end;

{ Adversarial-review finding (CONFIRMED): a track with no themed background paints NOTHING but
  still hit-tested, selected, and fired OnChange — invisible-but-clickable. Input must agree. }
procedure TTySegmentedControlTest.TestBackgroundlessTrackIsInert;
var
  T: TSegAccess;
begin
  FCtl.LoadThemeCss('TySegmented { color: #000000; }'
    + 'TySegmentedItem:selected { background: #3B82F6; }');   // no track bg -> draws nothing
  T := MakeSeg(FForm, FCtl, 3);
  T.OnChange := @HandleChange;
  T.SetBounds(0, 0, 300, 30);
  T.ClickAt(150, 15);   // squarely inside segment 1's band
  AssertEquals('an invisible track selects nothing on a click', -1, T.ItemIndex);
  AssertEquals('...and fires no OnChange', 0, FChanged);
end;

initialization
  RegisterTest(TTySegmentedRulesTest);
  RegisterTest(TTySegmentedControlTest);
end.
