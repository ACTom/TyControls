unit test.advchart.style;
{$mode objfpc}{$H+}
{ The four states, and what a datum's style resolves to in each.

  The rule this file exists to disprove is "resolved = the item's value if it
  has one, else the series'". That is exactly right for the normal state, and
  wrong for the other three in ways that are all visible on screen -- an
  unstyled hover is not unstyled, a blur with no opacity still dims, and a
  selected bar that is also hovered is in two states at once. Every one of those
  is a test below. }
interface
uses Classes, SysUtils, Math, fpjson, jsonparser, fpcunit, testregistry,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint,
     tyControls.AdvChart.Style;
type
  TAdvChartStyleTest = class(TTestCase)
  published
    { ---- two slots, not one value ---- }
    procedure TestNormalIsBothSlotsEmpty;
    procedure TestEmphasisAndBlurShareOneSlot;
    procedure TestSelectIsItsOwnSlot;
    procedure TestSelectAndEmphasisAreBothApplied;
    { ---- enter overwrites, leave is guarded ---- }
    procedure TestEnteringEmphasisTakesTheSlotFromBlur;
    procedure TestLeavingEmphasisDoesNotClearABlur;
    procedure TestLeavingBlurDoesNotClearAnEmphasis;
    procedure TestBlurThenEmphasiseTheHoveredOne;
    { ---- reference-counted emphasis ---- }
    procedure TestTwoSourcesBothHaveToLetGo;
    procedure TestAnApiHighlightOutranksTheMouse;
    procedure TestTheMouseCannotReleaseAnApiHighlight;
    procedure TestTheMouseCannotOverrideABlurWhileHeld;
    procedure TestASourceOutOfRangeSharesBitZero;
    { ---- focus and blurScope ---- }
    procedure TestNoFocusMeansNothingIsEverBlurred;
    procedure TestFocusSeriesSparesItsOwnSeries;
    procedure TestFocusSelfBlursEvenItsOwnSeries;
    procedure TestScopeLimitsHowFarTheDimmingReaches;
    { ---- the style record ---- }
    procedure TestAbsentIsNotZero;
    procedure TestOverlayInheritsWhatTheTopLacks;
    procedure TestTheThreeShapesAreNotTheSameKeySet;
    procedure TestTheSameOptionNameMeansDifferentThings;
    { ---- resolution ---- }
    procedure TestNormalIsItemOverSeries;
    procedure TestAnUnstyledEmphasisLiftsTheNormalFill;
    procedure TestADeclaredEmphasisColourWins;
    procedure TestOnlyTheStrokeIsLiftedWhenThereIsNoFill;
    procedure TestFillAndStrokeAreNeverBothLifted;
    procedure TestLiftBrightens;
    procedure TestLiftClampsAndKeepsAlpha;
    procedure TestBlurIsComputedNotLookedUp;
    procedure TestBlurDimsAnElementWithNoOpacity;
    procedure TestZLiftsComeFromNoOptionAtAll;
    { ---- reading a style off the option ---- }
    procedure TestReadingAnAbsentKeyLeavesItAbsent;
    procedure TestReadingHonoursEachShapesOwnKeySet;
    procedure TestColourSpellingsTheOptionActuallyUses;
    procedure TestAnUnreadableColourLeavesTheKeyAlone;
    procedure TestNamedGeometryStaysText;
    procedure TestAWrongTypeIsIgnoredRatherThanCoerced;
  end;
implementation

function Fill(AColor: TTyChartColor): TTyChartStyle;
begin
  Result := TyChartNoStyle;
  TyChartSetColor(Result, cskFill, AColor);
end;

{ ====================== two slots, not one value ====================== }

procedure TAdvChartStyleTest.TestNormalIsBothSlotsEmpty;
var s: TTyChartElementState; l: TTyChartStateList;
begin
  { Normal is not a state anyone enters. It is the absence of the other two. }
  s := TyChartNoState;
  l := TyChartStatesOf(s);
  AssertFalse(l.Emphasis);
  AssertFalse(l.Blur);
  AssertFalse(l.Select);
end;

procedure TAdvChartStyleTest.TestEmphasisAndBlurShareOneSlot;
var s: TTyChartElementState; l: TTyChartStateList;
begin
  s := TyChartNoState;
  TyChartEnterBlur(s);
  TyChartEnterEmphasis(s);
  l := TyChartStatesOf(s);
  AssertTrue('emphasis took the slot', l.Emphasis);
  AssertFalse('so blur is gone', l.Blur);
end;

procedure TAdvChartStyleTest.TestSelectIsItsOwnSlot;
var s: TTyChartElementState;
begin
  { Modelling the four as one enum would make this impossible to express, and
    a selected bar would stop being selected the moment it was hovered. }
  s := TyChartNoState;
  TyChartEnterSelect(s);
  TyChartEnterBlur(s);
  AssertTrue('still selected', TyChartStatesOf(s).Select);
  AssertTrue('and blurred at the same time', TyChartStatesOf(s).Blur);
end;

procedure TAdvChartStyleTest.TestSelectAndEmphasisAreBothApplied;
var s: TTyChartElementState; l: TTyChartStateList;
begin
  s := TyChartNoState;
  TyChartEnterSelect(s);
  TyChartEnterEmphasis(s);
  l := TyChartStatesOf(s);
  AssertTrue(l.Select);
  AssertTrue(l.Emphasis);
end;

{ ================ enter overwrites, leave is guarded ================ }

procedure TAdvChartStyleTest.TestEnteringEmphasisTakesTheSlotFromBlur;
var s: TTyChartElementState;
begin
  s := TyChartNoState;
  TyChartEnterBlur(s);
  TyChartEnterEmphasis(s);
  AssertTrue(TyChartStatesOf(s).Emphasis);
end;

procedure TAdvChartStyleTest.TestLeavingEmphasisDoesNotClearABlur;
var s: TTyChartElementState;
begin
  { The guard. Without it, a hover leaving one element brightens every element
    the same pass had dimmed. }
  s := TyChartNoState;
  TyChartEnterBlur(s);
  TyChartLeaveEmphasis(s);
  AssertTrue('still blurred', TyChartStatesOf(s).Blur);
end;

procedure TAdvChartStyleTest.TestLeavingBlurDoesNotClearAnEmphasis;
var s: TTyChartElementState;
begin
  s := TyChartNoState;
  TyChartEnterEmphasis(s);
  TyChartLeaveBlur(s);
  AssertTrue('still emphasised', TyChartStatesOf(s).Emphasis);
end;

procedure TAdvChartStyleTest.TestBlurThenEmphasiseTheHoveredOne;
var hovered, other: TTyChartElementState;
begin
  { The sequence the asymmetry exists for: dim the whole series, then brighten
    the one under the pointer. Both orders of guard have to be right or the
    hovered element comes out dimmed. }
  hovered := TyChartNoState;
  other := TyChartNoState;
  TyChartEnterBlur(hovered);
  TyChartEnterBlur(other);
  TyChartEnterEmphasis(hovered);
  AssertTrue('the hovered one is emphasised', TyChartStatesOf(hovered).Emphasis);
  AssertFalse('and no longer blurred', TyChartStatesOf(hovered).Blur);
  AssertTrue('its neighbour stays dimmed', TyChartStatesOf(other).Blur);
end;

{ ================== reference-counted emphasis ================== }

procedure TAdvChartStyleTest.TestTwoSourcesBothHaveToLetGo;
var s: TTyChartElementState;
begin
  { A legend hover and an axis-pointer link can hold the same element. One
    letting go must not put it back to normal while the other still holds it. }
  s := TyChartNoState;
  TyChartEnterEmphasisBy(s, 1);
  TyChartEnterEmphasisBy(s, 2);
  TyChartLeaveEmphasisBy(s, 1);
  AssertTrue('one source still holds it', TyChartStatesOf(s).Emphasis);
  TyChartLeaveEmphasisBy(s, 2);
  AssertFalse('and now nothing does', TyChartStatesOf(s).Emphasis);
end;

procedure TAdvChartStyleTest.TestAnApiHighlightOutranksTheMouse;
var s: TTyChartElementState;
begin
  s := TyChartNoState;
  TyChartEnterEmphasisBy(s, 1);
  TyChartLeaveEmphasisByMouse(s);
  AssertTrue('the pointer leaving does not release an API highlight',
    TyChartStatesOf(s).Emphasis);
end;

procedure TAdvChartStyleTest.TestTheMouseCannotReleaseAnApiHighlight;
var s: TTyChartElementState;
begin
  { And the mouse takes no bit of its own, so entering by mouse while an API
    source holds the element changes nothing that a later release could undo. }
  s := TyChartNoState;
  TyChartEnterEmphasisBy(s, 3);
  TyChartEnterEmphasisByMouse(s);
  TyChartLeaveEmphasisByMouse(s);
  AssertTrue(TyChartStatesOf(s).Emphasis);
  TyChartLeaveEmphasisBy(s, 3);
  AssertFalse('only the API source can', TyChartStatesOf(s).Emphasis);
end;

procedure TAdvChartStyleTest.TestTheMouseCannotOverrideABlurWhileHeld;
var s: TTyChartElementState;
begin
  { The mouse ENTER guard, which the release test above cannot see: entering by
    mouse when the element is already emphasised is indistinguishable from not
    entering at all. The difference only shows when a held element has since
    been blurred -- a focus pass can do that, and the pointer must not quietly
    undo it. Mutation found the earlier test green with the guard removed. }
  s := TyChartNoState;
  TyChartEnterEmphasisBy(s, 3);
  TyChartEnterBlur(s);
  TyChartEnterEmphasisByMouse(s);
  AssertTrue('the pointer did not take the slot back', TyChartStatesOf(s).Blur);
  AssertFalse(TyChartStatesOf(s).Emphasis);
end;

procedure TAdvChartStyleTest.TestASourceOutOfRangeSharesBitZero;
var s: TTyChartElementState;
begin
  { Thirty-two bits and no more. A thirty-third source shares bit 0 rather than
    losing its highlight, which is what upstream does when it runs out. }
  s := TyChartNoState;
  TyChartEnterEmphasisBy(s, 99);
  AssertTrue(TyChartStatesOf(s).Emphasis);
  { It must really HOLD bit 0, not merely be waved through: another source
    letting go of a different bit must not release it. Asserting only that it
    can be released through bit 0 passes even when the out-of-range source
    registered nothing at all, which mutation duly demonstrated. }
  TyChartLeaveEmphasisBy(s, 5);
  AssertTrue('another source letting go does not release it',
    TyChartStatesOf(s).Emphasis);
  TyChartLeaveEmphasisBy(s, 0);
  AssertFalse('released through the bit it shares', TyChartStatesOf(s).Emphasis);
end;

{ ====================== focus and blurScope ====================== }

procedure TAdvChartStyleTest.TestNoFocusMeansNothingIsEverBlurred;
begin
  { The default. A chart does not go grey the first time a pointer crosses it,
    and that is because the whole mechanism is off until a focus is asked for. }
  AssertFalse(TyChartShouldBlur(cfNone, cbsGlobal, False, False));
  AssertFalse(TyChartShouldBlur(cfNone, cbsSeries, False, False));
end;

procedure TAdvChartStyleTest.TestFocusSeriesSparesItsOwnSeries;
begin
  AssertFalse('a sibling in the same series stays bright',
    TyChartShouldBlur(cfSeries, cbsGlobal, True, True));
  AssertTrue('another series dims',
    TyChartShouldBlur(cfSeries, cbsGlobal, False, True));
end;

procedure TAdvChartStyleTest.TestFocusSelfBlursEvenItsOwnSeries;
begin
  { focus self spares only the hovered element itself, which the caller
    un-blurs by index afterwards -- so at this level even its own series dims. }
  AssertTrue(TyChartShouldBlur(cfSelf, cbsGlobal, True, True));
end;

procedure TAdvChartStyleTest.TestScopeLimitsHowFarTheDimmingReaches;
begin
  { Scope coordinateSystem is the DEFAULT, so a second grid keeps its colours
    while the hovered one dims. Global is what dims the whole chart. }
  AssertFalse('another coordinate system is left alone',
    TyChartShouldBlur(cfSelf, cbsCoordinateSystem, False, False));
  AssertTrue('while the same one dims',
    TyChartShouldBlur(cfSelf, cbsCoordinateSystem, False, True));
  AssertTrue('and global reaches everything',
    TyChartShouldBlur(cfSelf, cbsGlobal, False, False));
  AssertFalse('scope series ignores anything outside it',
    TyChartShouldBlur(cfSelf, cbsSeries, False, True));
end;

{ ======================== the style record ======================== }

procedure TAdvChartStyleTest.TestAbsentIsNotZero;
var s: TTyChartStyle;
begin
  { A border width of 0 means "do not stroke"; an absent one means "whatever the
    layer below said". Collapsing the two is how a style layer silently stops
    inheriting. }
  s := TyChartNoStyle;
  AssertFalse('nothing is set', TyChartStyleHas(s, cskLineWidth));
  TyChartSetNum(s, cskLineWidth, 0);
  AssertTrue('now it is, and it is zero', TyChartStyleHas(s, cskLineWidth));
  AssertEquals(0, s.Num[cskLineWidth], 0);
end;

procedure TAdvChartStyleTest.TestOverlayInheritsWhatTheTopLacks;
var base, top, r: TTyChartStyle;
begin
  base := TyChartNoStyle;
  TyChartSetColor(base, cskFill, $FF112233);
  TyChartSetNum(base, cskLineWidth, 2);
  top := TyChartNoStyle;
  TyChartSetColor(top, cskFill, $FFAABBCC);
  r := TyChartOverlay(base, top);
  AssertEquals('the top wins where it spoke', TTyChartColor($FFAABBCC), r.Color[cskFill]);
  AssertTrue('and the base is inherited where it did not',
    TyChartStyleHas(r, cskLineWidth));
  AssertEquals(2, r.Num[cskLineWidth], 0);
end;

procedure TAdvChartStyleTest.TestTheThreeShapesAreNotTheSameKeySet;
begin
  { An area has six keys and no more -- no stroke, no width, no dash. Offering
    them would let a validator accept a chart that cannot be drawn. }
  AssertEquals('', TyChartStyleOptionKey(cskArea, cskStroke));
  AssertEquals('', TyChartStyleOptionKey(cskArea, cskLineWidth));
  AssertEquals('', TyChartStyleOptionKey(cskArea, cskLineDash));
  AssertEquals('color', TyChartStyleOptionKey(cskArea, cskFill));
  { A line has no fill. }
  AssertEquals('', TyChartStyleOptionKey(cskLine, cskFill));
  AssertEquals('and its own colour is the stroke', 'color',
    TyChartStyleOptionKey(cskLine, cskStroke));
end;

procedure TAdvChartStyleTest.TestTheSameOptionNameMeansDifferentThings;
begin
  { `color` is the FILL on an item and the STROKE on a line. A single
    option-name-to-canvas-key table would have to pick one and be wrong for the
    other half of the chart. }
  AssertEquals('color', TyChartStyleOptionKey(cskItem, cskFill));
  AssertEquals('color', TyChartStyleOptionKey(cskLine, cskStroke));
  { And the width key is spelled differently in the two shapes. }
  AssertEquals('borderWidth', TyChartStyleOptionKey(cskItem, cskLineWidth));
  AssertEquals('width', TyChartStyleOptionKey(cskLine, cskLineWidth));
  AssertEquals('borderType', TyChartStyleOptionKey(cskItem, cskLineDash));
  AssertEquals('type', TyChartStyleOptionKey(cskLine, cskLineDash));
end;

{ ========================== resolution ========================== }

procedure TAdvChartStyleTest.TestNormalIsItemOverSeries;
var series, item, r: TTyChartStyle; st: TTyChartStateList;
begin
  series := Fill($FF102030);
  TyChartSetNum(series, cskLineWidth, 1);
  item := Fill($FF405060);
  st := Default(TTyChartStateList);
  r := TyChartResolveStyle(TyChartOverlay(series, item), TyChartNoStyle, st);
  AssertEquals('the item''s colour', TTyChartColor($FF405060), r.Color[cskFill]);
  AssertEquals('and the series'' width', 1, r.Num[cskLineWidth], 0);
end;

procedure TAdvChartStyleTest.TestAnUnstyledEmphasisLiftsTheNormalFill;
var normal, r: TTyChartStyle; st: TTyChartStateList;
begin
  { THE divergence. Nobody wrote emphasis.itemStyle.color anywhere, and the
    answer is not "no value" -- it is the normal colour brightened. This is the
    default hover appearance of every bar, slice and symbol in the library. }
  normal := Fill($FF5470C6);
  st := Default(TTyChartStateList);
  st.Emphasis := True;
  r := TyChartResolveStyle(normal, TyChartNoStyle, st);
  AssertTrue('it has a fill', TyChartStyleHas(r, cskFill));
  AssertTrue('and it is not the normal one', r.Color[cskFill] <> TTyChartColor($FF5470C6));
  AssertEquals('it is the normal one lifted',
    TyChartLiftColor($FF5470C6), r.Color[cskFill]);
end;

procedure TAdvChartStyleTest.TestADeclaredEmphasisColourWins;
var normal, state, r: TTyChartStyle; st: TTyChartStateList;
begin
  normal := Fill($FF5470C6);
  state := Fill($FFFF0000);
  st := Default(TTyChartStateList);
  st.Emphasis := True;
  r := TyChartResolveStyle(normal, state, st);
  AssertEquals('no lifting when it was told what to be',
    TTyChartColor($FFFF0000), r.Color[cskFill]);
end;

procedure TAdvChartStyleTest.TestOnlyTheStrokeIsLiftedWhenThereIsNoFill;
var normal, r: TTyChartStyle; st: TTyChartStateList;
begin
  { A line has no fill to brighten, so the stroke is what gets lifted. }
  normal := TyChartNoStyle;
  TyChartSetColor(normal, cskStroke, $FF5470C6);
  st := Default(TTyChartStateList);
  st.Emphasis := True;
  r := TyChartResolveStyle(normal, TyChartNoStyle, st);
  AssertEquals(TyChartLiftColor($FF5470C6), r.Color[cskStroke]);
  AssertFalse('and no fill was invented', TyChartStyleHas(r, cskFill));
end;

procedure TAdvChartStyleTest.TestFillAndStrokeAreNeverBothLifted;
var normal, r: TTyChartStyle; st: TTyChartStateList;
begin
  { A body and its outline brightening together reads as a different colour
    rather than as a highlight, so the stroke is only the fallback's fallback. }
  normal := Fill($FF5470C6);
  TyChartSetColor(normal, cskStroke, $FF000000);
  st := Default(TTyChartStateList);
  st.Emphasis := True;
  r := TyChartResolveStyle(normal, TyChartNoStyle, st);
  AssertEquals('the fill lifted', TyChartLiftColor($FF5470C6), r.Color[cskFill]);
  AssertEquals('the stroke untouched', TTyChartColor($FF000000), r.Color[cskStroke]);
end;

procedure TAdvChartStyleTest.TestLiftBrightens;
begin
  { Called "lift" and driven by a NEGATIVE level, and it makes the colour
    LIGHTER. Both the name and the sign point the other way, so the direction is
    pinned here rather than left to a reader's assumption. }
  AssertEquals('each channel is ten per cent up',
    TTyChartColor($FF6E6E6E), TyChartLiftColor($FF646464));
  AssertTrue('a dark colour gets lighter, not darker',
    (TyChartLiftColor($FF202020) and $FF) > $20);
end;

procedure TAdvChartStyleTest.TestLiftClampsAndKeepsAlpha;
begin
  { White has nowhere to go and must not wrap round to black. }
  AssertEquals(TTyChartColor($FFFFFFFF), TyChartLiftColor($FFFFFFFF));
  AssertEquals('black has no channel to lift', TTyChartColor($FF000000),
    TyChartLiftColor($FF000000));
  AssertEquals('and alpha is not a colour channel',
    Cardinal($80), (TyChartLiftColor($80646464) shr 24) and $FF);
end;

procedure TAdvChartStyleTest.TestBlurIsComputedNotLookedUp;
var normal, r: TTyChartStyle; st: TTyChartStateList;
begin
  normal := Fill($FF5470C6);
  TyChartSetNum(normal, cskOpacity, 0.8);
  st := Default(TTyChartStateList);
  st.Blur := True;
  r := TyChartResolveStyle(normal, TyChartNoStyle, st);
  AssertEquals('a tenth of the normal opacity', 0.08, r.Num[cskOpacity], 1e-9);
end;

procedure TAdvChartStyleTest.TestBlurDimsAnElementWithNoOpacity;
var normal, r: TTyChartStyle; st: TTyChartStateList;
begin
  { Most elements declare no opacity at all. If blur only scaled a value it
    found, they would not dim -- which is most of the chart staying bright. }
  normal := Fill($FF5470C6);
  st := Default(TTyChartStateList);
  st.Blur := True;
  r := TyChartResolveStyle(normal, TyChartNoStyle, st);
  AssertTrue('it got one', TyChartStyleHas(r, cskOpacity));
  AssertEquals(0.1, r.Num[cskOpacity], 1e-9);
end;

procedure TAdvChartStyleTest.TestZLiftsComeFromNoOptionAtAll;
var st: TTyChartStateList;
begin
  { These are constants in the state machinery. A port that waits to find them
    in the option tree will never find them, and hovered elements will sit
    behind their neighbours. }
  st := Default(TTyChartStateList);
  AssertEquals('normal lifts nothing', 0, TyChartZ2Lift(st));
  st.Select := True;
  AssertEquals(9, TyChartZ2Lift(st));
  st.Emphasis := True;
  AssertEquals('emphasis outranks select when both apply', 10, TyChartZ2Lift(st));
end;

{ ============ reading a style off the option ============ }

function ReadJson(const AText: string; AKind: TTyChartStyleKind;
  out AStyle: TTyChartStyle): Boolean;
var d: TJSONData;
begin
  d := GetJSON(AText);
  try
    Result := TyChartReadStyle(d, AKind, AStyle);
  finally
    d.Free;
  end;
end;

procedure TAdvChartStyleTest.TestReadingAnAbsentKeyLeavesItAbsent;
var st: TTyChartStyle;
begin
  { ABSENT AND ZERO ARE DIFFERENT ANSWERS all the way down: a border width of 0
    means "do not stroke", a missing one means "whatever the layer below said".
    A reader that filled the gaps with defaults would make every style opaque
    to the layer under it -- which is how a style stack silently stops
    inheriting. }
  AssertTrue(ReadJson('{"borderWidth": 0}', cskItem, st));
  AssertTrue('a written zero is present', st.Has[cskLineWidth]);
  AssertEquals(0.0, st.Num[cskLineWidth], 1e-9);
  AssertFalse('and nothing else is', st.Has[cskFill]);
  AssertFalse(st.Has[cskOpacity]);
end;

procedure TAdvChartStyleTest.TestReadingHonoursEachShapesOwnKeySet;
var st: TTyChartStyle;
begin
  { `color` is the FILL for an item and the STROKE for a line -- the same option
    name, a different canvas key. Reading a line's colour into the fill is a
    bug you would only see as "the line is invisible". }
  AssertTrue(ReadJson('{"color": "#ff0000"}', cskItem, st));
  AssertTrue('an item colours its fill', st.Has[cskFill]);
  AssertFalse(st.Has[cskStroke]);

  AssertTrue(ReadJson('{"color": "#ff0000"}', cskLine, st));
  AssertTrue('a line colours its stroke', st.Has[cskStroke]);
  AssertFalse(st.Has[cskFill]);

  { An areaStyle has no stroke, no width and no dash AT ALL. Accepting one would
    let a validator pass a chart that cannot be drawn. }
  AssertFalse('an area has no borderColor to read',
    ReadJson('{"borderColor": "#ff0000", "borderWidth": 2}', cskArea, st));
  AssertFalse(st.Has[cskStroke]);
  AssertFalse(st.Has[cskLineWidth]);
end;

procedure TAdvChartStyleTest.TestColourSpellingsTheOptionActuallyUses;
var c: TTyChartColor;
begin
  AssertTrue(TyChartParseColor('#ff0000', c));
  AssertEquals('opaque red', TTyChartColor($FFFF0000), c);

  { #rgb DOUBLES each nibble. Shifting instead would turn #f0a into f0 00 a0 --
    a different colour that looks close enough to pass a glance. }
  AssertTrue(TyChartParseColor('#f0a', c));
  AssertEquals(TTyChartColor($FFFF00AA), c);

  { Alpha comes LAST in CSS and FIRST in the stored word. }
  AssertTrue(TyChartParseColor('#ff000080', c));
  AssertEquals(TTyChartColor($80FF0000), c);

  AssertTrue(TyChartParseColor('rgb(255, 0, 0)', c));
  AssertEquals(TTyChartColor($FFFF0000), c);

  { rgba's alpha is 0..1, not 0..255, and it is written with a '.' whatever the
    machine's locale says. }
  AssertTrue(TyChartParseColor('rgba(255,0,0,0.5)', c));
  AssertEquals(TTyChartColor($80FF0000), c);
end;

procedure TAdvChartStyleTest.TestAnUnreadableColourLeavesTheKeyAlone;
var
  st: TTyChartStyle;
  c: TTyChartColor;
begin
  { NOT black. Leaving it absent means the layer below keeps deciding; falling
    back to black means a misspelt colour paints something that looks
    deliberate. Named colours are deliberately not supported -- 148 entries
    upstream resolves in a browser, and option text in the wild is hex. }
  AssertFalse(TyChartParseColor('steelblue', c));
  AssertFalse(TyChartParseColor('#gg0000', c));
  AssertFalse(TyChartParseColor('', c));

  AssertFalse('nothing readable, nothing read',
    ReadJson('{"color": "steelblue"}', cskItem, st));
  AssertFalse(st.Has[cskFill]);
end;

procedure TAdvChartStyleTest.TestNamedGeometryStaysText;
var st: TTyChartStyle;
begin
  { 'dashed' is a NAME, and what it means in pixels depends on the width -- a
    painter decision. Turning it into a dash array here would put that decision
    in the layer that knows the least about it. }
  AssertTrue(ReadJson('{"type": "dashed", "cap": "round"}', cskLine, st));
  AssertEquals('dashed', st.Text[cskLineDash]);
  AssertEquals('round', st.Text[cskLineCap]);
end;

procedure TAdvChartStyleTest.TestAWrongTypeIsIgnoredRatherThanCoerced;
var st: TTyChartStyle;
begin
  { A half-written option is the normal state in an editor. A number where a
    colour belongs is not a colour, and coercing it would invent one. }
  AssertFalse(ReadJson('{"color": 5}', cskItem, st));
  AssertFalse(st.Has[cskFill]);
  AssertFalse(ReadJson('{"borderWidth": "2"}', cskItem, st));
  AssertFalse(st.Has[cskLineWidth]);
  AssertFalse('and a non-object reads nothing at all',
    ReadJson('[1, 2]', cskItem, st));
end;

initialization
  RegisterTest(TAdvChartStyleTest);
end.
