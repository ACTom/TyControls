unit test.accordion;
{$mode objfpc}{$H+}

{ TTyAccordion: the distribution of the stack's height (pure), the drag of a boundary, the
  saved layout text, and the container with TTyExPanel sections in it. The panel's side of
  the contract (ITyExPanelHost) is in test.expanel.section.

  The form has no handle, so LCL never aligns anything by itself: a test that needs the
  stack laid out asks for it (Lay, which is what LCL's alignment pass ends in). }

interface

uses
  Classes, SysUtils, Types, TypInfo, Graphics, Forms, Controls, LCLType,
  fpcunit, testregistry, BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Base, tyControls.StyleModel,
  tyControls.ExPanel, tyControls.Accordion;

type
  TAccProbe = class(TTyAccordion)
  public
    Eases: Boolean;
    FocusTo: TTyCustomExPanel;
    FocusCalls: Integer;
    function CanAnimate: Boolean; override;
    procedure FocusSection(ASection: TTyCustomExPanel); override;
    procedure Lay;
    procedure Step(AMs: Integer);
    procedure Down(X, Y: Integer);
    procedure MoveTo(X, Y: Integer);
    procedure Up(X, Y: Integer);
    procedure Leave;
    procedure MarkDesigning(AOn: Boolean);
    procedure Shot(ABmp: TBGRABitmap);
  end;

  TSecProbe = class(TTyExPanel)
  public
    procedure Key(AKey: Word; AShift: TShiftState = []);
    function KeyLeft(AKey: Word; AShift: TShiftState = []): Word;
    procedure MarkDesigning(AOn: Boolean);
  end;

  TPlainChild = class(TCustomControl);

  TTyAccordionTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FAcc: TAccProbe;
    FA, FB, FC: TSecProbe;
    FChanges, FExpands, FCollapses: Integer;
    function NewSection(const AName: string; AWeight: Integer): TSecProbe;
    procedure Three;
    procedure NoteChange(Sender: TObject);
    procedure NoteExpand(Sender: TObject);
    procedure NoteCollapse(Sender: TObject);
    function Heights: string;
    function Tops: string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { the distribution }
    procedure TestFixedAndCollapsedTakeTheirSize;
    procedure TestExpandedShareTheRestByWeight;
    procedure TestTheSharesAddUpToTheRoomExactly;
    procedure TestASplitterIsCountedOnlyBetweenTwoExpandedNeighbours;
    procedure TestAMinimumIsKeptAndTheOthersShareWhatIsLeft;
    procedure TestPinningOneSectionCanPinTheNext;
    procedure TestWhenTheMinimumsDoNotFitEveryoneGetsTheirs;
    procedure TestAWeightBelowOneCountsAsOne;
    procedure TestTheDistributionOfNothing;
    { the drag, as arithmetic }
    procedure TestADragStopsAtTheMinimums;
    { the layout text }
    procedure TestALayoutTextRoundTrips;
    procedure TestALayoutTextIsReadStrictly;
    procedure TestALaterVersionsKeysAreSkipped;
    procedure TestTheWrapperStorageAddsIsTakenOff;
    { the stack }
    procedure TestSectionsStackTopToBottomAtFullWidth;
    procedure TestACollapsedSectionTakesItsHeader;
    procedure TestAChildThatIsNoSectionKeepsItsHeight;
    procedure TestAHiddenSectionLeavesTheStack;
    procedure TestTheStackStaysInsideTheFrame;
    procedure TestRightToLeftDoesNotMoveTheStack;
    procedure TestTheOrderIsTheChildrensOrder;
    procedure TestTheStripAndTheMinimumReadTheirTokens;
    procedure TestMinBodyHeightOverridesTheTheme;
    { toggling }
    procedure TestCollapsingASectionGivesItsRoomToTheOthers;
    procedure TestExpandingGivesTheSectionItsShareBack;
    procedure TestAToggleFiresTheSectionsEventsAndOnLayoutChanged;
    procedure TestANewWeightOrHeaderHeightIsLaidOutAtOnce;
    { the move to a new distribution }
    procedure TestWithoutAWindowAToggleSnaps;
    procedure TestAToggleEasesOverTheSectionsDuration;
    procedure TestTheStackStaysWholeOnTheWay;
    procedure TestADurationOfZeroSnaps;
    procedure TestAToggleOnTheWayStartsFromWhereTheStackIs;
    { the drag strips }
    procedure TestAStripLiesBetweenTwoOpenNeighbours;
    procedure TestDraggingAStripMovesHeightBetweenItsTwoSections;
    procedure TestADragUpdatesBothWeightsAndKeepsTheOthersPlace;
    procedure TestADragRespectsTheMinimumBody;
    procedure TestADragKeepsACollapsedSectionsShare;
    procedure TestADragFiresOnLayoutChangedOnceWhenItEnds;
    procedure TestMoveSplitterIsADragInOneCall;
    procedure TestTheStripLendsTheSizeCursor;
    procedure TestTheStripIsPaintedByItsState;
    procedure TestADisabledStackDoesNotDrag;
    { keyboard }
    procedure TestUpAndDownMoveBetweenTheHeaders;
    procedure TestUpAndDownSkipWhatCannotTakeTheFocus;
    procedure TestTheStackLeavesOtherKeysAlone;
    procedure TestTheHeadersAreTabStopsAndTheStackIsNot;
    { the saved layout }
    procedure TestTheLayoutIsSavedByName;
    procedure TestALoadedLayoutIsApplied;
    procedure TestUnknownNamesAreIgnoredAndMissingSectionsKeepTheirState;
    procedure TestABadLayoutChangesNothing;
    procedure TestALoadFiresOnLayoutChangedOnce;
    procedure TestTheDesignerDoesNotLoadLayouts;
    procedure TestSectionsWithoutANameOfTheirOwnAreNotSaved;
    { streaming }
    procedure TestTheOrderAndTheWeightsSurviveStreaming;
    procedure TestMinBodyHeightIsStoredOnlyWhenSet;
    { the designer }
    procedure TestInTheDesignerADraggedSectionTakesItsNewPlace;
    procedure TestInTheDesignerAResizedSectionTakesItsNewWeight;
    procedure TestAtRunTimeAMovedSectionIsPutBack;
    { housekeeping }
    procedure TestAFreedSectionLeavesTheStack;
    procedure TestASectionMadeWhereAFreedOneWasIsNotTakenForIt;
    procedure TestTheDefaultThemeStylesTheStack;
  end;

implementation

const
  { White and frameless, with the two tokens at values that are not their defaults: the
    least body 30, the strip 6. The sections' headers are pinned at 20. }
  CTheme =
    ':root { --accordion-min-body-height: 30px; --accordion-splitter-size: 6px; }' +
    'TyAccordion { background: #FFFFFF; color: #000000; border-width: 0px; ' +
    '  border-radius: 0px; padding: 0px; }' +
    'TyExPanel { background: #FFFFFF; color: #000000; border-width: 0px; ' +
    '  border-radius: 0px; padding: 0px; }' +
    'TyExPanelHeader { color: #000000; }';

function Item(AKind: TTyAccordionItemKind; ASize, AMin, AWeight: Integer): TTyAccordionItem;
begin
  Result.Kind := AKind;
  Result.Size := ASize;
  Result.MinSize := AMin;
  Result.Weight := AWeight;
end;

function Open(AWeight: Integer; AMin: Integer = 50): TTyAccordionItem;
begin
  Result := Item(aikExpanded, 20, AMin, AWeight);
end;

function Shut: TTyAccordionItem;
begin
  Result := Item(aikCollapsed, 20, 0, 0);
end;

function Fixed(AHeight: Integer): TTyAccordionItem;
begin
  Result := Item(aikFixed, AHeight, 0, 0);
end;

function HeightsOf(const ASlots: TTyAccordionSlots): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(ASlots) do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + IntToStr(ASlots[i].Height);
  end;
end;

function TopsOf(const ASlots: TTyAccordionSlots): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(ASlots) do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + IntToStr(ASlots[i].Top);
  end;
end;

function IsRed(const p: TBGRAPixel): Boolean;
begin
  Result := (p.red > 200) and (p.green < 60) and (p.blue < 60);
end;

function IsBlue(const p: TBGRAPixel): Boolean;
begin
  Result := (p.blue > 200) and (p.green < 60) and (p.red < 60);
end;

{ TAccProbe }

function TAccProbe.CanAnimate: Boolean;
begin
  Result := Eases;
end;

procedure TAccProbe.FocusSection(ASection: TTyCustomExPanel);
begin
  FocusTo := ASection;
  Inc(FocusCalls);
end;

procedure TAccProbe.Lay;
var
  r: TRect;
begin
  r := ClientRect;
  AlignControls(nil, r);
end;

procedure TAccProbe.Step(AMs: Integer);
begin
  AnimationStep(AMs);
end;

procedure TAccProbe.Down(X, Y: Integer);
begin
  MouseDown(mbLeft, [], X, Y);
end;

procedure TAccProbe.MoveTo(X, Y: Integer);
begin
  MouseMove([], X, Y);
end;

procedure TAccProbe.Up(X, Y: Integer);
begin
  MouseUp(mbLeft, [], X, Y);
end;

procedure TAccProbe.Leave;
begin
  MouseLeave;
end;

procedure TAccProbe.MarkDesigning(AOn: Boolean);
begin
  SetDesigning(AOn, False);
end;

procedure TAccProbe.Shot(ABmp: TBGRABitmap);
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

{ TSecProbe }

procedure TSecProbe.Key(AKey: Word; AShift: TShiftState);
begin
  KeyDown(AKey, AShift);
end;

function TSecProbe.KeyLeft(AKey: Word; AShift: TShiftState): Word;
begin
  KeyDown(AKey, AShift);
  Result := AKey;
end;

procedure TSecProbe.MarkDesigning(AOn: Boolean);
begin
  SetDesigning(AOn, False);
end;

{ TTyAccordionTest }

procedure TTyAccordionTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.Font.PixelsPerInch := 96;
  FForm.SetBounds(0, 0, 400, 600);
  FCtl := TTyStyleController.Create(FForm);
  FCtl.LoadThemeCss(CTheme);
  FAcc := TAccProbe.Create(FForm);
  FAcc.Name := 'Acc';
  FAcc.Parent := FForm;
  FAcc.Controller := FCtl;
  FAcc.Font.PixelsPerInch := 96;
  FAcc.SetBounds(0, 0, 200, 400);
  FA := nil;
  FB := nil;
  FC := nil;
  FChanges := 0;
  FExpands := 0;
  FCollapses := 0;
end;

procedure TTyAccordionTest.TearDown;
begin
  FreeAndNil(FForm);
end;

function TTyAccordionTest.NewSection(const AName: string; AWeight: Integer): TSecProbe;
begin
  Result := TSecProbe.Create(FForm);
  Result.Name := AName;
  Result.Parent := FAcc;
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.HeaderHeight := 20;
  Result.ExpandedHeight := AWeight;
end;

procedure TTyAccordionTest.Three;
begin
  { weights 100 : 100 : 200 }
  FA := NewSection('SecA', 100);
  FB := NewSection('SecB', 100);
  FC := NewSection('SecC', 200);
  FAcc.Lay;
end;

procedure TTyAccordionTest.NoteChange(Sender: TObject);
begin
  Inc(FChanges);
end;

procedure TTyAccordionTest.NoteExpand(Sender: TObject);
begin
  Inc(FExpands);
end;

procedure TTyAccordionTest.NoteCollapse(Sender: TObject);
begin
  Inc(FCollapses);
end;

function TTyAccordionTest.Heights: string;
begin
  Result := Format('%d,%d,%d', [FA.Height, FB.Height, FC.Height]);
end;

function TTyAccordionTest.Tops: string;
begin
  Result := Format('%d,%d,%d', [FA.Top, FB.Top, FC.Top]);
end;

{ ---- the distribution ---- }

procedure TTyAccordionTest.TestFixedAndCollapsedTakeTheirSize;
var
  s: TTyAccordionSlots;
begin
  s := TyAccordionDistribute([Shut, Fixed(33), Shut], 400, 6);
  AssertEquals('each its own size', '20,33,20', HeightsOf(s));
  AssertEquals('one under the other, no strips', '0,20,53', TopsOf(s));
end;

procedure TTyAccordionTest.TestExpandedShareTheRestByWeight;
var
  s: TTyAccordionSlots;
begin
  { 400, less a header of 20 and a fixed 30, less one strip of 10: 340 for 1 : 3 }
  s := TyAccordionDistribute([Shut, Open(100), Open(300), Fixed(30)], 400, 10);
  AssertEquals('1 : 3 of 340', '20,85,255,30', HeightsOf(s));
  AssertEquals('the strip after the first open one', '0,20,115,370', TopsOf(s));
  { the weights are a proportion, not pixels }
  s := TyAccordionDistribute([Shut, Open(7), Open(21), Fixed(30)], 400, 10);
  AssertEquals('the same proportion on another scale', '20,85,255,30', HeightsOf(s));
  s := TyAccordionDistribute([Shut, Open(300), Open(100), Fixed(30)], 400, 10);
  AssertEquals('and the other way round', '20,255,85,30', HeightsOf(s));
end;

procedure TTyAccordionTest.TestTheSharesAddUpToTheRoomExactly;
var
  s: TTyAccordionSlots;
  h, i, sum: Integer;
begin
  { thirds of 100 do not come out even }
  s := TyAccordionDistribute([Open(1, 0), Open(1, 0), Open(1, 0)], 100, 0);
  AssertEquals('33 + 34 + 33', '33,34,33', HeightsOf(s));
  for h := 200 to 260 do
  begin
    s := TyAccordionDistribute([Open(3), Shut, Open(7), Open(11), Fixed(17)], h, 5);
    sum := 5;   // the one strip, between the two open neighbours
    for i := 0 to High(s) do Inc(sum, s[i].Height);
    AssertEquals('room of ' + IntToStr(h), h, sum);
    AssertEquals('the last one ends at the bottom, room of ' + IntToStr(h), h,
      s[High(s)].Top + s[High(s)].Height);
  end;
end;

procedure TTyAccordionTest.TestASplitterIsCountedOnlyBetweenTwoExpandedNeighbours;
var
  s: TTyAccordionSlots;
begin
  { open, shut, open: no two open neighbours, no strip }
  s := TyAccordionDistribute([Open(1), Shut, Open(1)], 220, 10);
  AssertEquals('no strip: 100 each', '100,20,100', HeightsOf(s));
  AssertEquals('one right under the other', '0,100,120', TopsOf(s));
  { open, open, shut: one strip }
  s := TyAccordionDistribute([Open(1), Open(1), Shut], 230, 10);
  AssertEquals('one strip: 100 each again', '100,100,20', HeightsOf(s));
  AssertEquals('the strip between the two open ones only', '0,110,210', TopsOf(s));
  { three open: two strips }
  s := TyAccordionDistribute([Open(1), Open(1), Open(1)], 320, 10);
  AssertEquals('two strips', '0,110,220', TopsOf(s));
end;

procedure TTyAccordionTest.TestAMinimumIsKeptAndTheOthersShareWhatIsLeft;
var
  s: TTyAccordionSlots;
begin
  { 10 : 190 : 100 of 300 would give the first one 10; it is kept at 50, and the other two
    share 250 as 190 : 100 }
  s := TyAccordionDistribute([Open(10), Open(190), Open(100)], 300, 0);
  AssertEquals('pinned at 50, then 164 and 86', '50,164,86', HeightsOf(s));
  { with a lower minimum nothing is pinned }
  s := TyAccordionDistribute([Open(10, 5), Open(190, 5), Open(100, 5)], 300, 0);
  AssertEquals('plain shares', '10,190,100', HeightsOf(s));
end;

procedure TTyAccordionTest.TestPinningOneSectionCanPinTheNext;
var
  s: TTyAccordionSlots;
begin
  { 1 : 30 : 69 of 100, each at least 30. The first is under at once; the second is at
    exactly 30 and is not. With the first pinned, 70 is left for 30 : 69, which puts the
    second at 21 -- under, so it is pinned too, and the third gets what is left. }
  s := TyAccordionDistribute([Open(1, 30), Open(30, 30), Open(69, 30)], 100, 0);
  AssertEquals('two pinned, the third takes the rest', '30,30,40', HeightsOf(s));
end;

procedure TTyAccordionTest.TestWhenTheMinimumsDoNotFitEveryoneGetsTheirs;
var
  s: TTyAccordionSlots;
begin
  { 100 high: a header of 20 leaves 80, the two minimums ask for 110 }
  s := TyAccordionDistribute([Open(5, 50), Shut, Open(1, 60)], 100, 4);
  AssertEquals('each its minimum, whatever the weights', '50,20,60', HeightsOf(s));
  AssertEquals('and the stack runs past the bottom', '0,50,70', TopsOf(s));
end;

procedure TTyAccordionTest.TestAWeightBelowOneCountsAsOne;
var
  s: TTyAccordionSlots;
begin
  s := TyAccordionDistribute([Open(0, 0), Open(-5, 0), Open(2, 0)], 100, 0);
  AssertEquals('0 and -5 are 1 each: 1 : 1 : 2', '25,25,50', HeightsOf(s));
end;

procedure TTyAccordionTest.TestTheDistributionOfNothing;
var
  s: TTyAccordionSlots;
begin
  s := TyAccordionDistribute([], 100, 4);
  AssertEquals('no children, no slots', 0, Length(s));
  s := TyAccordionDistribute([Shut, Shut], 10, 4);
  AssertEquals('headers that do not fit keep their size', '20,20', HeightsOf(s));
end;

{ ---- the drag, as arithmetic ---- }

procedure TTyAccordionTest.TestADragStopsAtTheMinimums;
begin
  AssertEquals('room both ways: as asked', 30, TyAccordionDragDelta(100, 120, 50, 50, 30));
  AssertEquals('and up', -30, TyAccordionDragDelta(100, 120, 50, 50, -30));
  AssertEquals('down: until the lower one is at its minimum', 70,
    TyAccordionDragDelta(100, 120, 50, 50, 500));
  AssertEquals('up: until the upper one is at its minimum', -50,
    TyAccordionDragDelta(100, 120, 50, 50, -500));
  AssertEquals('the two minimums are each section''s own', 100,
    TyAccordionDragDelta(100, 120, 60, 20, 500));
  AssertEquals('and the upper one''s', -40, TyAccordionDragDelta(100, 120, 60, 20, -500));
  AssertEquals('a section already under its minimum is not taken further', 0,
    TyAccordionDragDelta(40, 120, 50, 50, -10));
  AssertEquals('but may grow', 10, TyAccordionDragDelta(40, 120, 50, 50, 10));
  AssertEquals('nor the lower one', 0, TyAccordionDragDelta(100, 40, 50, 50, 10));
end;

{ ---- the layout text ---- }

procedure TTyAccordionTest.TestALayoutTextRoundTrips;
var
  doc, back: TTyAccordionLayoutDoc;
  text: string;
begin
  doc := nil;
  SetLength(doc, 2);
  doc[0].Name := 'Folders';
  doc[0].Weight := 240;
  doc[0].Collapsed := False;
  doc[1].Name := 'Outline';
  doc[1].Weight := 7;
  doc[1].Collapsed := True;
  text := TyAccordionLayoutFormat(doc);
  AssertEquals('the text', 'TYACCORDION/1|Folders=240,0|Outline=7,1|end', text);
  AssertTrue('reads back', TyAccordionLayoutParse(text, back));
  AssertEquals('two sections', 2, Length(back));
  AssertEquals('first name', 'Folders', back[0].Name);
  AssertEquals('first weight', 240, back[0].Weight);
  AssertFalse('first open', back[0].Collapsed);
  AssertEquals('second name', 'Outline', back[1].Name);
  AssertEquals('second weight', 7, back[1].Weight);
  AssertTrue('second collapsed', back[1].Collapsed);
  AssertEquals('an empty stack', 'TYACCORDION/1|end', TyAccordionLayoutFormat(nil));
  AssertTrue('reads back too', TyAccordionLayoutParse('TYACCORDION/1|end', back));
  AssertEquals('as no sections', 0, Length(back));
end;

procedure TTyAccordionTest.TestALayoutTextIsReadStrictly;
var
  doc: TTyAccordionLayoutDoc;
  long: string;

  procedure Bad(const AWhat, AText: string);
  begin
    AssertFalse(AWhat, TyAccordionLayoutParse(AText, doc));
    AssertEquals(AWhat + ': nothing comes back', 0, Length(doc));
  end;

begin
  AssertTrue('setup: the good one', TyAccordionLayoutParse('TYACCORDION/1|A=10,0|B=20,1|end', doc));
  Bad('empty', '');
  Bad('another format', 'TYTOOLLAYOUT/1|A=10,0|end');
  Bad('another version', 'TYACCORDION/2|A=10,0|end');
  Bad('the tag in another case', 'tyaccordion/1|A=10,0|end');
  Bad('cut before the end', 'TYACCORDION/1|A=10,0|B=20,1');
  Bad('cut inside a value', 'TYACCORDION/1|A=10,0|B=2');
  Bad('the tag alone', 'TYACCORDION/1');
  Bad('an empty segment', 'TYACCORDION/1|A=10,0||end');
  Bad('end in the middle', 'TYACCORDION/1|A=10,0|end|B=20,1|end');
  Bad('no value', 'TYACCORDION/1|A|end');
  Bad('no name', 'TYACCORDION/1|=10,0|end');
  Bad('one field', 'TYACCORDION/1|A=10|end');
  Bad('three fields', 'TYACCORDION/1|A=10,0,0|end');
  Bad('a weight that is no number', 'TYACCORDION/1|A=x,0|end');
  Bad('a signed weight', 'TYACCORDION/1|A=-10,0|end');
  Bad('a weight with a blank', 'TYACCORDION/1|A= 10,0|end');
  Bad('a weight of six digits', 'TYACCORDION/1|A=100000,0|end');
  Bad('an empty weight', 'TYACCORDION/1|A=,0|end');
  Bad('a flag that is neither 0 nor 1', 'TYACCORDION/1|A=10,2|end');
  Bad('an empty flag', 'TYACCORDION/1|A=10,|end');
  Bad('a name twice', 'TYACCORDION/1|A=10,0|A=20,1|end');
  Bad('a name twice in another case', 'TYACCORDION/1|Abc=10,0|aBC=20,1|end');
  { too long, and otherwise a good layout: the long segment is a later version's key }
  long := 'TYACCORDION/1|A=10,0|@pad=' + StringOfChar('x', TyAccordionLayoutMaxLength) + '|end';
  Bad('too long', long);
  AssertTrue('the same text, short enough, is a layout',
    TyAccordionLayoutParse('TYACCORDION/1|A=10,0|@pad=' + StringOfChar('x', 100) + '|end', doc));
  AssertTrue('five digits are fine', TyAccordionLayoutParse('TYACCORDION/1|A=99999,0|end', doc));
  AssertEquals('99999', 99999, doc[0].Weight);
end;

procedure TTyAccordionTest.TestALaterVersionsKeysAreSkipped;
var
  doc: TTyAccordionLayoutDoc;
begin
  AssertTrue('a key that is no component name does not spoil the text',
    TyAccordionLayoutParse('TYACCORDION/1|A=10,0|@gap=whatever,it,says|B=20,1|end', doc));
  AssertEquals('the two sections', 2, Length(doc));
  AssertEquals('the second one', 'B', doc[1].Name);
end;

procedure TTyAccordionTest.TestTheWrapperStorageAddsIsTakenOff;
begin
  AssertEquals('a BOM in front', 'TYACCORDION/1|end',
    TyAccordionLayoutUnwrap(#$EF#$BB#$BF + 'TYACCORDION/1|end'));
  AssertEquals('white space behind', 'TYACCORDION/1|end',
    TyAccordionLayoutUnwrap('TYACCORDION/1|end' + #13#10 + ' ' + #9));
  AssertEquals('nothing in the middle', 'TYACCORDION/1| end',
    TyAccordionLayoutUnwrap('TYACCORDION/1| end'));
  AssertEquals('nor in front', ' TYACCORDION/1|end',
    TyAccordionLayoutUnwrap(' TYACCORDION/1|end'));
end;

{ ---- the stack ---- }

procedure TTyAccordionTest.TestSectionsStackTopToBottomAtFullWidth;
begin
  Three;
  { 400 less two strips of 6: 388 for 100 : 100 : 200 }
  AssertEquals('by weight', '97,97,194', Heights);
  AssertEquals('a strip between each two', '0,103,206', Tops);
  AssertEquals('A: the full width', 200, FA.Width);
  AssertEquals('B: the full width', 200, FB.Width);
  AssertEquals('C: from the left edge', 0, FC.Left);
  AssertEquals('the last one ends at the bottom', 400, FC.Top + FC.Height);
  { a taller stack: the same proportions }
  FAcc.Height := 812;
  FAcc.Lay;
  AssertEquals('by weight of 800', '200,200,400', Heights);
  AssertEquals('a narrower one: the children follow', 200, FA.Width);
  FAcc.Width := 150;
  FAcc.Lay;
  AssertEquals('narrower', 150, FB.Width);
end;

procedure TTyAccordionTest.TestACollapsedSectionTakesItsHeader;
begin
  FA := NewSection('SecA', 100);
  FB := NewSection('SecB', 100);
  FC := NewSection('SecC', 200);
  FB.Collapsed := True;
  FAcc.Lay;
  { no two open neighbours: 400 - 20 = 380 for 100 : 200 }
  AssertEquals('B is its header, A and C share the rest', '127,20,253', Heights);
  AssertEquals('one right under the other', '0,127,147', Tops);
end;

procedure TTyAccordionTest.TestAChildThatIsNoSectionKeepsItsHeight;
var
  bar: TPlainChild;
begin
  FA := NewSection('SecA', 100);
  bar := TPlainChild.Create(FForm);
  bar.Parent := FAcc;
  bar.SetBounds(40, 300, 77, 33);
  FB := NewSection('SecB', 300);
  FAcc.Lay;
  AssertEquals('its own height', 33, bar.Height);
  AssertEquals('the stack''s width', 200, bar.Width);
  AssertEquals('at the left edge', 0, bar.Left);
  { 400 - 33 = 367 for 1 : 3, and no strip: the two sections are not neighbours }
  AssertEquals('A', 92, FA.Height);
  AssertEquals('the bar under A', 92, bar.Top);
  AssertEquals('B under the bar', 125, FB.Top);
  AssertEquals('B', 275, FB.Height);
end;

procedure TTyAccordionTest.TestAHiddenSectionLeavesTheStack;
begin
  Three;
  FB.Visible := False;
  FAcc.Lay;
  { A and C are neighbours now: one strip, 394 for 100 : 200 }
  AssertEquals('A', 131, FA.Height);
  AssertEquals('C right after the strip', 137, FC.Top);
  AssertEquals('C', 263, FC.Height);
  FB.Visible := True;
  FAcc.Lay;
  AssertEquals('shown again, it is back where it was', '97,97,194', Heights);
  AssertEquals('in its place', '0,103,206', Tops);
end;

procedure TTyAccordionTest.TestTheStackStaysInsideTheFrame;
begin
  FCtl.LoadThemeCss(
    ':root { --accordion-min-body-height: 30px; --accordion-splitter-size: 6px; }' +
    'TyAccordion { background: #FFFFFF; border-color: #808080; border-width: 3px; padding: 0px; }' +
    'TyExPanel { background: #FFFFFF; color: #000000; border-width: 0px; padding: 0px; }');
  FA := NewSection('SecA', 100);
  FB := NewSection('SecB', 100);
  FAcc.Lay;
  AssertEquals('off the left border', 3, FA.Left);
  AssertEquals('off the top border', 3, FA.Top);
  AssertEquals('off the right border', 197, FA.Left + FA.Width);
  AssertEquals('off the bottom border', 397, FB.Top + FB.Height);
  { 394 less a strip: 388 for two }
  AssertEquals('the room is the inside', 194, FA.Height);
end;

procedure TTyAccordionTest.TestRightToLeftDoesNotMoveTheStack;
begin
  Three;
  FAcc.BiDiMode := bdRightToLeft;
  FAcc.Lay;
  AssertEquals('a column reads the same either way', '97,97,194', Heights);
  AssertEquals('same tops', '0,103,206', Tops);
  AssertEquals('same left', 0, FB.Left);
end;

procedure TTyAccordionTest.TestTheOrderIsTheChildrensOrder;
begin
  Three;
  AssertEquals('three sections', 3, FAcc.SectionCount);
  AssertTrue('in the order they were made', (FAcc.Section(0) = FA) and (FAcc.Section(1) = FB)
    and (FAcc.Section(2) = FC));
  { C to the front: the stack is laid out again without being asked }
  FAcc.MoveSection(FC, 0);
  AssertTrue('C, A, B', (FAcc.Section(0) = FC) and (FAcc.Section(1) = FA)
    and (FAcc.Section(2) = FB));
  AssertEquals('C on top', 0, FC.Top);
  AssertEquals('at its weight', 194, FC.Height);
  AssertEquals('A under it', 200, FA.Top);
  AssertEquals('B last', 303, FB.Top);
  { wherever a section is put by hand, the order decides }
  FB.Top := 0;
  FAcc.Lay;
  AssertEquals('B is put back', 303, FB.Top);
end;

procedure TTyAccordionTest.TestTheStripAndTheMinimumReadTheirTokens;
begin
  Three;
  AssertEquals('setup: a strip of 6', 6, FB.Top - (FA.Top + FA.Height));
  AssertEquals('setup: a least body of 30', 30, FAcc.MinBodyHeight);
  FCtl.LoadThemeCss(
    ':root { --accordion-min-body-height: 44px; --accordion-splitter-size: 10px; }' +
    'TyAccordion { background: #FFFFFF; border-width: 0px; padding: 0px; }' +
    'TyExPanel { background: #FFFFFF; color: #000000; border-width: 0px; padding: 0px; }');
  FAcc.Lay;
  AssertEquals('the theme''s strip', 10, FB.Top - (FA.Top + FA.Height));
  AssertEquals('the theme''s least body', 44, FAcc.MinBodyHeight);
  { and on this one stack alone }
  FAcc.StyleOverride := '--accordion-splitter-size: 2px; --accordion-min-body-height: 9px;';
  FAcc.Lay;
  AssertEquals('its own strip', 2, FB.Top - (FA.Top + FA.Height));
  AssertEquals('its own least body', 9, FAcc.MinBodyHeight);
end;

procedure TTyAccordionTest.TestMinBodyHeightOverridesTheTheme;
begin
  { weights 1 : 99 : 100, so A's share is far under any minimum }
  FA := NewSection('SecA', 1);
  FB := NewSection('SecB', 99);
  FC := NewSection('SecC', 100);
  FAcc.Lay;
  AssertEquals('the theme: header 20 and body 30', 50, FA.Height);
  FAcc.MinBodyHeight := 70;
  AssertEquals('set: header 20 and body 70, laid out at once', 90, FA.Height);
  AssertEquals('read back', 70, FAcc.MinBodyHeight);
  FAcc.MinBodyHeight := 0;
  AssertEquals('0 is a value: the header alone', 20, FA.Height);
  FAcc.MinBodyHeight := -1;
  AssertEquals('below 0 gives it back to the theme', 30, FAcc.MinBodyHeight);
  AssertEquals('and the stack follows', 50, FA.Height);
end;

{ ---- toggling ---- }

procedure TTyAccordionTest.TestCollapsingASectionGivesItsRoomToTheOthers;
begin
  Three;
  FB.Collapsed := True;
  { nobody asked for a layout: the section told the stack }
  AssertEquals('B is its header, A and C share the rest', '127,20,253', Heights);
  AssertEquals('one right under the other', '0,127,147', Tops);
  AssertEquals('B''s weight is still 100', 100, FB.ExpandedHeight);
end;

procedure TTyAccordionTest.TestExpandingGivesTheSectionItsShareBack;
begin
  Three;
  FB.Collapsed := True;
  FB.Collapsed := False;
  AssertEquals('as before', '97,97,194', Heights);
  AssertEquals('in place', '0,103,206', Tops);
  { every one collapsed, then one opened: it takes all that is left }
  FA.Collapsed := True;
  FB.Collapsed := True;
  FC.Collapsed := True;
  AssertEquals('three headers', '20,20,20', Heights);
  FB.Collapsed := False;
  AssertEquals('B takes the room', '20,360,20', Heights);
end;

procedure TTyAccordionTest.TestAToggleFiresTheSectionsEventsAndOnLayoutChanged;
begin
  Three;
  FB.OnCollapse := @NoteCollapse;
  FB.OnExpand := @NoteExpand;
  FAcc.OnLayoutChanged := @NoteChange;
  FB.Collapsed := True;
  AssertEquals('the section''s OnCollapse is the application''s', 1, FCollapses);
  AssertEquals('the stack says its layout changed', 1, FChanges);
  FB.Collapsed := False;
  AssertEquals('OnExpand', 1, FExpands);
  AssertEquals('changed again', 2, FChanges);
  FB.Collapsed := False;
  AssertEquals('no change, no event', 2, FChanges);
end;

procedure TTyAccordionTest.TestANewWeightOrHeaderHeightIsLaidOutAtOnce;
begin
  Three;
  FA.ExpandedHeight := 200;
  { 388 for 200 : 100 : 200 }
  AssertEquals('a new weight', '155,78,155', Heights);
  FB.Collapsed := True;
  FB.HeaderHeight := 40;
  AssertEquals('a collapsed section follows its header', 40, FB.Height);
  AssertEquals('and the others what is left', 360, FA.Height + FC.Height);
end;

{ ---- the move to a new distribution ---- }

procedure TTyAccordionTest.TestWithoutAWindowAToggleSnaps;
begin
  Three;
  FB.AnimationDuration := 200;
  FB.Collapsed := True;
  AssertFalse('nothing on its way', FAcc.Animating);
  AssertEquals('there at once', '127,20,253', Heights);
end;

procedure TTyAccordionTest.TestAToggleEasesOverTheSectionsDuration;
var
  mid: Integer;
begin
  Three;
  FAcc.Eases := True;
  FB.AnimationDuration := 200;
  FB.Collapsed := True;
  AssertTrue('on its way', FAcc.Animating);
  AssertEquals('at the start nothing has moved', '97,97,194', Heights);
  FAcc.Step(100);
  mid := FB.Height;
  AssertTrue('half the time: B is between 97 and 20, was ' + IntToStr(mid),
    (mid < 97) and (mid > 20));
  AssertTrue('still on its way', FAcc.Animating);
  { the gaps beside B are closing with it: B is collapsed, so they are not strips to drag }
  AssertTrue('setup: there still is a gap above B', FB.Top > FA.Top + FA.Height);
  AssertEquals('and it is no strip', 0, FAcc.SplitterCount);
  AssertEquals('nothing to hit there', -1, FAcc.SplitterAt(50, FB.Top - 1));
  FAcc.Step(100);
  AssertFalse('the time is up', FAcc.Animating);
  AssertEquals('and the stack is where it was going', '127,20,253', Heights);
  { a section with another duration takes that long: after the same 100 it is done }
  FA.AnimationDuration := 100;
  FA.Collapsed := True;
  AssertTrue('on its way again', FAcc.Animating);
  FAcc.Step(100);
  AssertFalse('100 was all it had', FAcc.Animating);
  AssertEquals('A and B headers, C the rest', '20,20,360', Heights);
end;

procedure TTyAccordionTest.TestTheStackStaysWholeOnTheWay;
var
  i: Integer;
begin
  Three;
  FAcc.Eases := True;
  FB.AnimationDuration := 160;
  FB.Collapsed := True;
  for i := 1 to 9 do
  begin
    FAcc.Step(16);
    AssertEquals('step ' + IntToStr(i) + ': A starts at the top', 0, FA.Top);
    AssertTrue('step ' + IntToStr(i) + ': B is under A', FB.Top >= FA.Top + FA.Height);
    AssertTrue('step ' + IntToStr(i) + ': C is under B', FC.Top >= FB.Top + FB.Height);
    AssertEquals('step ' + IntToStr(i) + ': C ends at the bottom', 400, FC.Top + FC.Height);
  end;
end;

procedure TTyAccordionTest.TestADurationOfZeroSnaps;
begin
  Three;
  FAcc.Eases := True;
  FB.AnimationDuration := 0;
  FB.Collapsed := True;
  AssertFalse('nothing on its way', FAcc.Animating);
  AssertEquals('there at once', '127,20,253', Heights);
end;

procedure TTyAccordionTest.TestAToggleOnTheWayStartsFromWhereTheStackIs;
var
  mid: Integer;
begin
  Three;
  FAcc.Eases := True;
  FB.AnimationDuration := 200;
  FB.Collapsed := True;
  FAcc.Step(100);
  mid := FB.Height;
  FB.Collapsed := False;
  AssertEquals('turned round: it starts from where it was', mid, FB.Height);
  FAcc.Step(200);
  AssertFalse('done', FAcc.Animating);
  AssertEquals('back where it started', '97,97,194', Heights);
end;

{ ---- the drag strips ---- }

procedure TTyAccordionTest.TestAStripLiesBetweenTwoOpenNeighbours;
begin
  Three;
  AssertEquals('two strips', 2, FAcc.SplitterCount);
  AssertTrue('the first between A and B',
    EqualRect(Rect(0, 97, 200, 103), FAcc.SplitterRect(0)));
  AssertTrue('the second between B and C',
    EqualRect(Rect(0, 200, 200, 206), FAcc.SplitterRect(1)));
  AssertEquals('a point on the first', 0, FAcc.SplitterAt(50, 99));
  AssertEquals('a point on the second', 1, FAcc.SplitterAt(50, 205));
  AssertEquals('a point on a section', -1, FAcc.SplitterAt(50, 50));
  AssertEquals('the row under a strip is the next section', -1, FAcc.SplitterAt(50, 103));
  FB.Collapsed := True;
  AssertEquals('B collapsed: no two open neighbours', 0, FAcc.SplitterCount);
  AssertEquals('and no strip to hit', -1, FAcc.SplitterAt(50, 99));
end;

procedure TTyAccordionTest.TestDraggingAStripMovesHeightBetweenItsTwoSections;
begin
  Three;
  FAcc.Down(50, 99);
  FAcc.MoveTo(50, 119);
  AssertEquals('20 down: A grew by 20, B gave 20, C did not move', '117,77,194', Heights);
  AssertEquals('the strip went with the boundary', 117, FAcc.SplitterRect(0).Top);
  FAcc.MoveTo(50, 89);
  AssertEquals('10 up from where the drag began', '87,107,194', Heights);
  FAcc.Up(50, 89);
  AssertEquals('released: it stays', '87,107,194', Heights);
  FAcc.MoveTo(50, 150);
  AssertEquals('a move after the release drags nothing', '87,107,194', Heights);
end;

procedure TTyAccordionTest.TestADragUpdatesBothWeightsAndKeepsTheOthersPlace;
begin
  Three;
  FAcc.Down(50, 99);
  FAcc.MoveTo(50, 119);
  FAcc.Up(50, 119);
  AssertEquals('A''s weight is its height', 117, FA.ExpandedHeight);
  AssertEquals('B''s too', 77, FB.ExpandedHeight);
  AssertEquals('C''s is its height as well: one scale for all', 194, FC.ExpandedHeight);
  { a taller stack keeps what the user set, in proportion }
  FAcc.Height := 788;
  FAcc.Lay;
  AssertEquals('twice the room, twice the heights', '234,154,388', Heights);
end;

procedure TTyAccordionTest.TestADragRespectsTheMinimumBody;
begin
  Three;
  FAcc.Down(50, 99);
  FAcc.MoveTo(50, 390);
  { B keeps its header 20 and body 30 }
  AssertEquals('down: B stops at 50', '144,50,194', Heights);
  FAcc.MoveTo(50, -300);
  AssertEquals('up: A stops at 50', '50,144,194', Heights);
  FAcc.Up(50, -300);
  FAcc.MinBodyHeight := 0;
  FAcc.Down(50, FAcc.SplitterRect(0).Top + 1);
  FAcc.MoveTo(50, -300);
  AssertEquals('with no least body: down to the header', 20, FA.Height);
  FAcc.Up(50, -300);
end;

procedure TTyAccordionTest.TestADragKeepsACollapsedSectionsShare;
begin
  { four of weight 100; D collapsed while A/B is dragged }
  FA := NewSection('SecA', 100);
  FB := NewSection('SecB', 100);
  FC := NewSection('SecC', 100);
  NewSection('SecD', 100).Collapsed := True;
  FAcc.Lay;
  { 400 - 20 - 2 strips: 368 for three }
  AssertEquals('setup', '123,122,123', Heights);
  FAcc.MoveSplitter(0, 20);
  AssertEquals('dragged', '143,102,123', Heights);
  { the weights are heights now (368 in all, where they were 300): D's 100 went with them }
  AssertEquals('D still weighs a third of the other three', 123, FAcc.Section(3).ExpandedHeight);
  FAcc.Section(3).Collapsed := False;
  { 400 - 3 strips = 382 for 143 : 102 : 123 : 123 }
  AssertEquals('opened, D gets a quarter of the room', 96, FAcc.Section(3).Height);
end;

procedure TTyAccordionTest.TestADragFiresOnLayoutChangedOnceWhenItEnds;
begin
  Three;
  FAcc.OnLayoutChanged := @NoteChange;
  FAcc.Down(50, 99);
  FAcc.MoveTo(50, 109);
  FAcc.MoveTo(50, 119);
  AssertEquals('not while dragging', 0, FChanges);
  FAcc.Up(50, 119);
  AssertEquals('once, at the end', 1, FChanges);
  { a press and a release that moved nothing changed nothing }
  FAcc.Down(50, FAcc.SplitterRect(0).Top + 1);
  FAcc.Up(50, FAcc.SplitterRect(0).Top + 1);
  AssertEquals('a click on a strip is no change', 1, FChanges);
end;

procedure TTyAccordionTest.TestMoveSplitterIsADragInOneCall;
begin
  Three;
  FAcc.OnLayoutChanged := @NoteChange;
  FAcc.MoveSplitter(1, -30);
  AssertEquals('the second boundary, 30 up', '97,67,224', Heights);
  AssertEquals('one change', 1, FChanges);
  FAcc.MoveSplitter(1, -500);
  AssertEquals('within the minimum', '97,50,241', Heights);
  FAcc.MoveSplitter(7, 10);
  AssertEquals('no such boundary: nothing', '97,50,241', Heights);
end;

procedure TTyAccordionTest.TestTheStripLendsTheSizeCursor;
begin
  Three;
  FAcc.Cursor := crHandPoint;
  FAcc.MoveTo(50, 99);
  AssertEquals('on a strip: the size cursor', Ord(crVSplit), Ord(FAcc.Cursor));
  FAcc.MoveTo(150, 99);
  AssertEquals('still on it', Ord(crVSplit), Ord(FAcc.Cursor));
  FAcc.Leave;
  AssertEquals('off it: the stack''s own cursor is back', Ord(crHandPoint), Ord(FAcc.Cursor));
  FAcc.MoveTo(50, 203);
  AssertEquals('on the other strip', Ord(crVSplit), Ord(FAcc.Cursor));
  { held while the drag goes on, wherever the pointer is }
  FAcc.Down(50, 203);
  FAcc.MoveTo(50, 250);
  FAcc.Leave;
  AssertEquals('kept during a drag', Ord(crVSplit), Ord(FAcc.Cursor));
  FAcc.Up(300, 250);
  AssertEquals('released outside: given back', Ord(crHandPoint), Ord(FAcc.Cursor));
end;

procedure TTyAccordionTest.TestTheStripIsPaintedByItsState;
var
  shot: TBGRABitmap;

  function CountIn(const AR: TRect; ABlue: Boolean): Integer;
  var
    x, y: Integer;
  begin
    Result := 0;
    for y := AR.Top to AR.Bottom - 1 do
      for x := AR.Left to AR.Right - 1 do
        if (ABlue and IsBlue(shot.GetPixel(x, y)))
           or (not ABlue and IsRed(shot.GetPixel(x, y))) then Inc(Result);
  end;

begin
  FCtl.LoadThemeCss(
    ':root { --accordion-min-body-height: 30px; --accordion-splitter-size: 6px; }' +
    'TyAccordion { background: #FFFFFF; border-width: 0px; padding: 0px; }' +
    'TyAccordionSplitter { background: none; }' +
    'TyAccordionSplitter:hover { background: #FF0000; }' +
    'TyAccordionSplitter:active { background: #0000FF; }' +
    'TyExPanel { background: #FFFFFF; color: #000000; border-width: 0px; padding: 0px; }');
  Three;
  shot := TBGRABitmap.Create(200, 400);
  try
    FAcc.Shot(shot);
    AssertEquals('at rest: nothing', 0, CountIn(Rect(0, 0, 200, 400), False));
    FAcc.MoveTo(50, 99);
    FAcc.Shot(shot);
    AssertEquals('under the pointer: the first strip, all of it', 200 * 6,
      CountIn(Rect(0, 97, 200, 103), False));
    AssertEquals('and only it', 200 * 6, CountIn(Rect(0, 0, 200, 400), False));
    FAcc.MoveTo(50, 203);
    FAcc.Shot(shot);
    AssertEquals('the pointer on the second: the second', 200 * 6,
      CountIn(Rect(0, 200, 200, 206), False));
    AssertEquals('the first is at rest again', 0, CountIn(Rect(0, 97, 200, 103), False));
    FAcc.Down(50, 203);
    FAcc.Shot(shot);
    AssertEquals('pressed: the active look', 200 * 6, CountIn(Rect(0, 200, 200, 206), True));
    FAcc.Up(50, 203);
    FAcc.Leave;
    FAcc.Shot(shot);
    AssertEquals('released and left: nothing', 0,
      CountIn(Rect(0, 0, 200, 400), False) + CountIn(Rect(0, 0, 200, 400), True));
  finally
    shot.Free;
  end;
end;

procedure TTyAccordionTest.TestADisabledStackDoesNotDrag;
begin
  Three;
  FAcc.Enabled := False;
  FAcc.MoveTo(50, 99);
  AssertEquals('no size cursor', Ord(crDefault), Ord(FAcc.Cursor));
  FAcc.Down(50, 99);
  FAcc.MoveTo(50, 150);
  FAcc.Up(50, 150);
  AssertEquals('and no drag', '97,97,194', Heights);
end;

{ ---- keyboard ---- }

procedure TTyAccordionTest.TestUpAndDownMoveBetweenTheHeaders;
begin
  Three;
  AssertEquals('Down on A is taken', 0, FA.KeyLeft(VK_DOWN));
  AssertTrue('and goes to B', FAcc.FocusTo = FB);
  AssertEquals('Up on C is taken', 0, FC.KeyLeft(VK_UP));
  AssertTrue('and goes to B', FAcc.FocusTo = FB);
  FB.Key(VK_UP);
  AssertTrue('Up on B goes to A', FAcc.FocusTo = FA);
  FB.Key(VK_DOWN);
  AssertTrue('Down on B goes to C', FAcc.FocusTo = FC);
  { at the ends the key is still the stack's, and the focus stays }
  FAcc.FocusCalls := 0;
  AssertEquals('Up on the first is taken', 0, FA.KeyLeft(VK_UP));
  AssertEquals('Down on the last is taken', 0, FC.KeyLeft(VK_DOWN));
  AssertEquals('and nothing is focused', 0, FAcc.FocusCalls);
  { a collapsed section's header is a header like the others }
  FB.Collapsed := True;
  FA.Key(VK_DOWN);
  AssertTrue('Down on A goes to the collapsed B', FAcc.FocusTo = FB);
end;

procedure TTyAccordionTest.TestUpAndDownSkipWhatCannotTakeTheFocus;
var
  bar: TPlainChild;
begin
  FA := NewSection('SecA', 100);
  bar := TPlainChild.Create(FForm);
  bar.Parent := FAcc;
  FB := NewSection('SecB', 100);
  FC := NewSection('SecC', 100);
  FAcc.Lay;
  FA.Key(VK_DOWN);
  AssertTrue('over a child that is no section', FAcc.FocusTo = FB);
  FB.Enabled := False;
  FA.Key(VK_DOWN);
  AssertTrue('over a disabled section', FAcc.FocusTo = FC);
  FC.Key(VK_UP);
  AssertTrue('and back over it', FAcc.FocusTo = FA);
  FB.Enabled := True;
  FB.Visible := False;
  FAcc.FocusTo := nil;
  FA.Key(VK_DOWN);
  AssertTrue('over a hidden section', FAcc.FocusTo = FC);
end;

procedure TTyAccordionTest.TestTheStackLeavesOtherKeysAlone;
const
  Mods: array[0..3] of TShiftStateEnum = (ssShift, ssCtrl, ssAlt, ssMeta);
var
  host: ITyExPanelHost;
  k: Word;
  m: Integer;
begin
  Three;
  AssertEquals('a letter', Ord('A'), FA.KeyLeft(Ord('A')));
  AssertEquals('Ctrl+Down is somebody''s shortcut', VK_DOWN, FA.KeyLeft(VK_DOWN, [ssCtrl]));
  AssertEquals('Alt+Up too', VK_UP, FB.KeyLeft(VK_UP, [ssAlt]));
  AssertEquals('and nothing was focused', 0, FAcc.FocusCalls);
  { asked directly, the stack says the same of every modifier }
  host := FAcc;
  for m := 0 to 3 do
  begin
    k := VK_DOWN;
    host.SectionKeyDown(FA, k, [Mods[m]]);
    AssertEquals('a chord is left alone, modifier ' + IntToStr(m), VK_DOWN, k);
  end;
  AssertEquals('still nothing focused', 0, FAcc.FocusCalls);
  host := nil;
  { the header's own keys never come to the stack }
  FA.Key(VK_SPACE);
  AssertTrue('Space toggled A', FA.Collapsed);
  AssertEquals('and focused nothing', 0, FAcc.FocusCalls);
end;

procedure TTyAccordionTest.TestTheHeadersAreTabStopsAndTheStackIsNot;
var
  list: TFPList;
  pi: PPropInfo;
begin
  Three;
  FA.TabStop := True;
  FC.TabStop := True;
  AssertFalse('the stack is no tab stop', FAcc.TabStop);
  pi := GetPropInfo(TTyAccordion, 'TabStop');
  AssertTrue('TabStop is published', pi <> nil);
  AssertEquals('at the constructed value', Ord(FAcc.TabStop), pi^.Default);
  list := TFPList.Create;
  try
    FAcc.GetTabOrderList(list);
    AssertTrue('A before C in the tab order',
      (list.IndexOf(FA) >= 0) and (list.IndexOf(FA) < list.IndexOf(FC)));
  finally
    list.Free;
  end;
end;

{ ---- the saved layout ---- }

procedure TTyAccordionTest.TestTheLayoutIsSavedByName;
begin
  Three;
  FB.Collapsed := True;
  AssertEquals('names, weights, states, in stack order',
    'TYACCORDION/1|SecA=100,0|SecB=100,1|SecC=200,0|end', FAcc.SaveLayoutToString);
  FC.ExpandedHeight := 1234567;
  FA.ExpandedHeight := -3;
  AssertEquals('a weight is kept within what reads back',
    'TYACCORDION/1|SecA=1,0|SecB=100,1|SecC=99999,0|end', FAcc.SaveLayoutToString);
end;

procedure TTyAccordionTest.TestALoadedLayoutIsApplied;
var
  text: string;
begin
  Three;
  FB.Collapsed := True;
  FA.ExpandedHeight := 300;
  FC.ExpandedHeight := 100;
  text := FAcc.SaveLayoutToString;
  { another state altogether }
  FB.Collapsed := False;
  FA.Collapsed := True;
  FC.ExpandedHeight := 500;
  AssertTrue('applied', FAcc.LoadLayoutFromString(text));
  AssertFalse('A is open again', FA.Collapsed);
  AssertTrue('B is collapsed again', FB.Collapsed);
  AssertEquals('A''s weight', 300, FA.ExpandedHeight);
  AssertEquals('C''s weight', 100, FC.ExpandedHeight);
  { laid out without being asked: 380 for 3 : 1 }
  AssertEquals('and the stack shows it', '285,20,95', Heights);
  AssertTrue('the storage''s wrapper is let through',
    FAcc.LoadLayoutFromString(#$EF#$BB#$BF + text + #13#10));
  AssertEquals('same again', '285,20,95', Heights);
end;

procedure TTyAccordionTest.TestUnknownNamesAreIgnoredAndMissingSectionsKeepTheirState;
begin
  Three;
  FC.Collapsed := True;
  AssertTrue('a text for other sections too is applied',
    FAcc.LoadLayoutFromString('TYACCORDION/1|Gone=500,1|seca=40,1|end'));
  AssertTrue('A, found whatever the case of its name', FA.Collapsed);
  AssertEquals('A''s weight', 40, FA.ExpandedHeight);
  AssertFalse('B is not in the text: as it was', FB.Collapsed);
  AssertEquals('B''s weight as it was', 100, FB.ExpandedHeight);
  AssertTrue('C is not in the text: as it was', FC.Collapsed);
  AssertEquals('C''s weight as it was', 200, FC.ExpandedHeight);
  AssertEquals('three sections still', 3, FAcc.SectionCount);
end;

procedure TTyAccordionTest.TestABadLayoutChangesNothing;
begin
  Three;
  FAcc.OnLayoutChanged := @NoteChange;
  AssertFalse('cut short', FAcc.LoadLayoutFromString('TYACCORDION/1|SecA=40,1|SecB=7,1'));
  AssertFalse('a bad value after a good one',
    FAcc.LoadLayoutFromString('TYACCORDION/1|SecA=40,1|SecB=x,1|end'));
  AssertFalse('not a layout at all', FAcc.LoadLayoutFromString('hello'));
  AssertFalse('A untouched', FA.Collapsed);
  AssertEquals('A''s weight untouched', 100, FA.ExpandedHeight);
  AssertEquals('the stack untouched', '97,97,194', Heights);
  AssertEquals('and no event', 0, FChanges);
end;

procedure TTyAccordionTest.TestALoadFiresOnLayoutChangedOnce;
begin
  Three;
  FAcc.OnLayoutChanged := @NoteChange;
  FA.OnCollapse := @NoteCollapse;
  FB.OnCollapse := @NoteCollapse;
  AssertTrue(FAcc.LoadLayoutFromString('TYACCORDION/1|SecA=40,1|SecB=7,1|SecC=3,0|end'));
  AssertEquals('one change for the whole text', 1, FChanges);
  AssertEquals('each section that collapsed said so', 2, FCollapses);
  AssertEquals('two headers and the rest', '20,20,360', Heights);
end;

procedure TTyAccordionTest.TestTheDesignerDoesNotLoadLayouts;
begin
  Three;
  FAcc.MarkDesigning(True);
  AssertFalse('refused', FAcc.LoadLayoutFromString('TYACCORDION/1|SecA=40,1|end'));
  AssertFalse('A untouched', FA.Collapsed);
  FAcc.MarkDesigning(False);
  AssertTrue('at run time it is taken', FAcc.LoadLayoutFromString('TYACCORDION/1|SecA=40,1|end'));
  AssertTrue('A collapsed', FA.Collapsed);
end;

procedure TTyAccordionTest.TestSectionsWithoutANameOfTheirOwnAreNotSaved;
var
  other: TComponent;
  twin, nameless: TSecProbe;
begin
  Three;
  { a section owned by something else may carry a name the form already has }
  other := TComponent.Create(nil);
  try
    twin := TSecProbe.Create(other);
    twin.Name := 'SecB';
    twin.Parent := FAcc;
    nameless := TSecProbe.Create(other);
    nameless.Parent := FAcc;
    AssertEquals('five sections', 5, FAcc.SectionCount);
    AssertEquals('only the ones that can be found again',
      'TYACCORDION/1|SecA=100,0|SecC=200,0|end', FAcc.SaveLayoutToString);
    AssertTrue('and the text reads back', FAcc.LoadLayoutFromString(FAcc.SaveLayoutToString));
    { a name two sections share is nobody's }
    AssertTrue(FAcc.LoadLayoutFromString('TYACCORDION/1|SecB=40,1|end'));
    AssertFalse('B untouched', FB.Collapsed);
    AssertFalse('its twin untouched', twin.Collapsed);
  finally
    other.Free;
  end;
end;

{ ---- streaming ---- }

procedure TTyAccordionTest.TestTheOrderAndTheWeightsSurviveStreaming;
var
  src, back: TForm;
  ms: TMemoryStream;
  acc: TAccProbe;

  function Sec(const AName: string; AWeight: Integer): TSecProbe;
  begin
    Result := TSecProbe.Create(src);
    Result.Name := AName;
    Result.Parent := acc;
    Result.HeaderHeight := 20;
    Result.ExpandedHeight := AWeight;
  end;

begin
  { a form of its own, with nothing on it but the stack: what a form file holds }
  src := TForm.CreateNew(nil);
  back := TForm.CreateNew(nil);
  ms := TMemoryStream.Create;
  try
    src.Font.PixelsPerInch := 96;
    back.Font.PixelsPerInch := 96;
    acc := TAccProbe.Create(src);
    acc.Name := 'Acc';
    acc.Parent := src;
    acc.SetBounds(0, 0, 200, 400);
    FA := Sec('SecA', 100);
    FB := Sec('SecB', 100);
    FC := Sec('SecC', 200);
    acc.Lay;
    acc.MoveSection(FC, 0);
    FB.Collapsed := True;
    FA.ExpandedHeight := 300;
    ms.WriteComponent(src);
    ms.Position := 0;
    ms.ReadComponent(back);
    acc := back.FindComponent('Acc') as TAccProbe;
    AssertTrue('the stack came back', acc <> nil);
    AssertEquals('with its three sections', 3, acc.SectionCount);
    AssertEquals('C first', 'SecC', acc.Section(0).Name);
    AssertEquals('then A', 'SecA', acc.Section(1).Name);
    AssertEquals('then B', 'SecB', acc.Section(2).Name);
    AssertEquals('C''s weight, though it is open', 200, acc.Section(0).ExpandedHeight);
    AssertEquals('A''s weight', 300, acc.Section(1).ExpandedHeight);
    AssertTrue('B collapsed', acc.Section(2).Collapsed);
    AssertEquals('B''s weight', 100, acc.Section(2).ExpandedHeight);
    acc.Controller := FCtl;
    acc.Lay;
    { 400 - 20 - one strip of 6: 374 for 200 : 300 }
    AssertEquals('laid out in that order: C', 0, acc.Section(0).Top);
    AssertEquals('C by its weight', 150, acc.Section(0).Height);
    AssertEquals('A by its weight', 224, acc.Section(1).Height);
    AssertEquals('B at the bottom', 380, acc.Section(2).Top);
  finally
    ms.Free;
    back.Free;
    src.Free;
  end;
end;

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

procedure TTyAccordionTest.TestMinBodyHeightIsStoredOnlyWhenSet;
begin
  AssertEquals('following the theme: not written', 0,
    Pos('MinBodyHeight', ComponentText(FAcc)));
  FAcc.MinBodyHeight := 30;
  AssertTrue('set, even to the theme''s value: written',
    Pos('MinBodyHeight = 30', ComponentText(FAcc)) > 0);
  FAcc.MinBodyHeight := -1;
  AssertEquals('given back to the theme: not written', 0,
    Pos('MinBodyHeight', ComponentText(FAcc)));
end;

{ ---- the designer ---- }

procedure TTyAccordionTest.TestInTheDesignerADraggedSectionTakesItsNewPlace;
begin
  Three;
  FAcc.MarkDesigning(True);
  { C dragged up over A: its middle is above A's }
  FC.Top := -150;
  FAcc.Lay;
  AssertTrue('C, A, B', (FAcc.Section(0) = FC) and (FAcc.Section(1) = FA)
    and (FAcc.Section(2) = FB));
  AssertEquals('C on top', 0, FC.Top);
  AssertEquals('A under it', 200, FA.Top);
  { C dragged down so that its middle is between A's and B's }
  FC.Top := 180;
  FAcc.Lay;
  AssertTrue('A, C, B', (FAcc.Section(0) = FA) and (FAcc.Section(1) = FC)
    and (FAcc.Section(2) = FB));
  { and past the last one }
  FA.Top := 390;
  FAcc.Lay;
  AssertTrue('C, B, A', (FAcc.Section(0) = FC) and (FAcc.Section(1) = FB)
    and (FAcc.Section(2) = FA));
  AssertEquals('A at the bottom', 400, FA.Top + FA.Height);
end;

procedure TTyAccordionTest.TestInTheDesignerAResizedSectionTakesItsNewWeight;
begin
  Three;
  FAcc.MarkDesigning(True);
  { A's bottom grip pulled down by 97: twice its height }
  FA.Height := 194;
  FAcc.Lay;
  AssertEquals('its new height is its weight', 194, FA.ExpandedHeight);
  AssertEquals('on the scale of the others'' heights: B', 97, FB.ExpandedHeight);
  AssertEquals('and C', 194, FC.ExpandedHeight);
  { 388 for 194 : 97 : 194 }
  AssertEquals('and the stack is laid out by them', '155,78,155', Heights);
  AssertTrue('in the same order', (FAcc.Section(0) = FA) and (FAcc.Section(2) = FC));
end;

procedure TTyAccordionTest.TestAtRunTimeAMovedSectionIsPutBack;
begin
  Three;
  FC.Top := -150;
  FA.Height := 194;
  FAcc.Lay;
  AssertTrue('the order is as it was', (FAcc.Section(0) = FA) and (FAcc.Section(2) = FC));
  AssertEquals('the weights are as they were', 100, FA.ExpandedHeight);
  AssertEquals('and the stack', '97,97,194', Heights);
  AssertEquals('in place', '0,103,206', Tops);
end;

{ ---- housekeeping ---- }

procedure TTyAccordionTest.TestAFreedSectionLeavesTheStack;
begin
  Three;
  FAcc.Eases := True;
  FB.AnimationDuration := 200;
  FB.Collapsed := True;
  FAcc.Step(50);
  { freed on the way, with the stack remembering where it was }
  FreeAndNil(FB);
  FAcc.Step(50);
  FAcc.Step(200);
  FAcc.Lay;
  AssertEquals('two sections', 2, FAcc.SectionCount);
  { one strip: 394 for 100 : 200 }
  AssertEquals('A', 131, FA.Height);
  AssertEquals('C', 263, FC.Height);
  FAcc.MarkDesigning(True);
  FAcc.Lay;
  AssertEquals('the designer''s check goes over what is left', 131, FA.Height);
end;

procedure TTyAccordionTest.TestASectionMadeWhereAFreedOneWasIsNotTakenForIt;
var
  was: Pointer;
  d: TSecProbe;
  at0: Integer;
begin
  { The stack remembers its children by address. Free one and make another of the same
    class straight away, and the heap gives the new one the old address -- which is the
    case this is about. When it does not, there is nothing to tell here. }
  Three;
  FAcc.MarkDesigning(True);
  FAcc.Lay;
  was := Pointer(FB);
  FreeAndNil(FB);
  { made as the designer makes one -- created and parented, nothing set on it that would
    have the stack laid out before the designer's check sees it }
  d := TSecProbe.Create(FForm);
  d.Name := 'SecD';
  d.Parent := FAcc;
  if Pointer(d) <> was then
    Ignore('the heap did not hand the freed address out again');
  { the designer's check: the new section is new, not the old one "dragged" to the top }
  FAcc.Lay;
  AssertTrue('the new section is last, where new children go',
    (FAcc.Section(0) = FA) and (FAcc.Section(1) = FC) and (FAcc.Section(2) = d));
  AssertEquals('and the weights are as they were', 100, FA.ExpandedHeight);
  FAcc.MarkDesigning(False);
  { the same on the way to a new distribution: the new section is not eased in from where
    the old one stood }
  FAcc.Eases := True;
  FA.AnimationDuration := 200;
  FA.Collapsed := True;
  was := Pointer(d);
  FreeAndNil(d);
  d := NewSection('SecE', 100);
  if Pointer(d) <> was then
    Ignore('the heap did not hand the freed address out again');
  FAcc.Lay;
  { a child the move knows nothing of is put where it is going at once; taken for the old
    one, it would start from where that one stood }
  at0 := d.Top;
  FAcc.Step(200);
  AssertFalse('setup: the move is over', FAcc.Animating);
  AssertEquals('the new section was where it belongs from the start', d.Top, at0);
end;

procedure TTyAccordionTest.TestTheDefaultThemeStylesTheStack;
var
  m: TTyStyleModel;
  box, rest, hot, held: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    box := m.ResolveStyle('TyAccordion', '', []);
    AssertTrue('the container has a surface', tpBackground in box.Present);
    AssertFalse('and no frame of its own', TyBorderVisible(box));
    rest := m.ResolveStyle('TyAccordionSplitter', '', []);
    hot := m.ResolveStyle('TyAccordionSplitter', '', [tysHover]);
    held := m.ResolveStyle('TyAccordionSplitter', '', [tysActive]);
    AssertFalse('a strip at rest is not filled',
      (tpBackground in rest.Present) and (rest.Background.Kind <> tfkNone));
    AssertTrue('under the pointer it is',
      (tpBackground in hot.Present) and (hot.Background.Kind <> tfkNone));
    AssertTrue('and while it is dragged',
      (tpBackground in held.Present) and (held.Background.Kind <> tfkNone));
    AssertEquals('the strip''s thickness', TyAccordionSplitterDef,
      m.ResolveMetric(TyAccordionSplitterVar, -1));
    AssertEquals('the least body', TyAccordionMinBodyDef,
      m.ResolveMetric(TyAccordionMinBodyVar, -1));
  finally
    m.Free;
  end;
end;

initialization
  { the streaming test reads these back by class name }
  RegisterClasses([TAccProbe, TSecProbe, TPlainChild]);
  RegisterTest(TTyAccordionTest);
end.
