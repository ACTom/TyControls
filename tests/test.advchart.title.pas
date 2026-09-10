unit test.advchart.title;
{$mode objfpc}{$H+}
{ The chart's title -- the first component that is neither a coordinate system
  nor a series.

  MEASURED THROUGH A FAKE, so every number here is exact: the real measurer
  answers whatever this machine's fonts say, and a layout test that depended on
  that would be a test of the font. Ten pixels per character, twelve tall.

  The two that a reasonable reading gets wrong, both upstream's:

    - the auto alignment MOVES THE BOX as well as anchoring the text, and only
      when it is auto. So `left: 'center'` and `left: 'center', textAlign:
      'center'` are two different pictures -- the second draws the block half a
      width to the right of the first;
    - `left: 'center'` and `left: '50%'` put the block in the same place and
      align it differently, because the alignment rule reads the KEYWORD. }
interface
uses
  Classes, SysUtils, Math, fpcunit, testregistry,
  tyControls.AdvChart.Types, tyControls.AdvChart.Option,
  tyControls.AdvChart.Layout, tyControls.AdvChart.Title;

type
  TTitleMeasurer = class(TInterfacedObject, ITyTextMeasurer)
  public
    procedure MeasureLine(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
    function WrapToWidth(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
  end;

  TAdvChartTitleTest = class(TTestCase)
  private
    FOpt: TTyChartOption;
    FM: ITyTextMeasurer;
    procedure SetUp; override;
    procedure TearDown; override;
    { Parse, read title AIndex, lay it out on a 400x300 container at 96 PPI. }
    function Lay(const AText: string; AIndex: Integer = 0): TTyTitleLayout;
    function Spec(const AText: string; AIndex: Integer = 0): TTyTitleSpec;
  published
    procedure TestTheDefaultTitleIsCentredNearTheTop;
    procedure TestNoTitleAtAllLaysOutNothing;
    procedure TestTheSubtextHangsAnItemGapBelowTheTitle;
    procedure TestTheKeywordDecidesTheAlignmentNotThePosition;
    procedure TestAnExplicitTextAlignDoesNotMoveTheBlock;
    procedure TestARightTitleEndsAtTheRightEdge;
    procedure TestABottomTitleSitsOnTheBottomEdge;
    procedure TestTheFrameSurroundsTheTextByItsPadding;
    procedure TestPaddingTakesTheCssShortForms;
    procedure TestSeveralTitlesAreSeveralTitles;
    procedure TestShowFalseDrawsNothing;
    procedure TestTheDefaultSpecIsCoherentOnItsOwn;
    procedure TestTheMarginKeepsSpaceOutsideTheSolvedBox;
  end;

implementation

const
  CharW = 10.0;
  CharH = 12.0;
  Eps = 1e-9;

procedure TTitleMeasurer.MeasureLine(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
var
  i, wide, run, lines: Integer;
begin
  wide := 0;
  run := 0;
  lines := 1;
  for i := 1 to Length(AText) do
    if AText[i] = #10 then
    begin
      if run > wide then wide := run;
      run := 0;
      Inc(lines);
    end
    else
      Inc(run);
  if run > wide then wide := run;
  AW := wide * CharW;
  AH := lines * CharH;
end;

function TTitleMeasurer.WrapToWidth(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
begin
  Result := AText;
end;

procedure TAdvChartTitleTest.SetUp;
begin
  inherited SetUp;
  FOpt := TTyChartOption.Create;
  FM := TTitleMeasurer.Create;
end;

procedure TAdvChartTitleTest.TearDown;
begin
  FM := nil;
  FreeAndNil(FOpt);
  inherited TearDown;
end;

function TAdvChartTitleTest.Spec(const AText: string; AIndex: Integer): TTyTitleSpec;
begin
  AssertTrue('the option parsed: ' + FOpt.Error.Message,
    FOpt.SetOptionText(AText));
  Result := TyTitleSpecOf(FOpt, AIndex);
end;

function TAdvChartTitleTest.Lay(const AText: string; AIndex: Integer): TTyTitleLayout;
var
  f, sf: TTyTitleFont;
begin
  f.Name := 'x';
  f.SizeLogical := 9;
  f.Weight := 700;
  sf := f;
  sf.Weight := 400;
  Result := TyLayoutTitle(Spec(AText, AIndex), TyRectF(0, 0, 400, 300), FM,
    f, sf, 96);
end;

procedure TAdvChartTitleTest.TestTheDefaultTitleIsCentredNearTheTop;
var t: TTyTitleLayout;
begin
  { install.ts:117-118 -- left 'center', top tokens.size.m = 15 -- plus the
    default padding of 5, which getLayoutRect takes as a MARGIN and so adds to
    the top rather than eating into the text. }
  t := Lay('{ "title": { "text": "abcd" } }');
  AssertTrue('it laid out', t.Valid);
  AssertEquals('centred across the container', 200.0, t.TextX, Eps);
  AssertEquals('fifteen down plus the padding', 20.0, t.TextY, Eps);
  AssertEquals('and anchored by its middle', Ord(ttaCentre), Ord(t.Align));
  AssertEquals('from its top', Ord(ttvTop), Ord(t.VAlign));
  AssertEquals('four characters wide', 40.0, t.TextW, Eps);
  AssertFalse('with no second line', t.HasSub);
end;

procedure TAdvChartTitleTest.TestNoTitleAtAllLaysOutNothing;
begin
  AssertEquals('no title component', 0,
    TyTitleCount(TTyChartOption(nil)));
  AssertFalse('an empty text draws nothing',
    Lay('{ "title": { } }').Valid);
  AssertFalse('and so does a chart with no title at all',
    Lay('{ "xAxis": {} }').Valid);
end;

procedure TAdvChartTitleTest.TestTheSubtextHangsAnItemGapBelowTheTitle;
var t: TTyTitleLayout;
begin
  { install.ts:177 -- the subtext's own offset is the TITLE's height plus
    itemGap, not the gap alone. }
  t := Lay('{ "title": { "text": "ab", "subtext": "cdef" } }');
  AssertTrue('there is a second line', t.HasSub);
  AssertEquals('the title first', 20.0, t.TextY, Eps);
  AssertEquals('then its height and the gap', 20.0 + 12.0 + 10.0, t.SubY, Eps);
  AssertEquals('both centred on the same anchor', t.TextX, t.SubX, Eps);

  { AND THE BLOCK IS AS WIDE AS ITS WIDEST LINE, which is what the box was
    solved for -- a title narrower than its own subtitle would be centred on
    the wrong number. }
  AssertEquals('centred on the container regardless', 200.0, t.TextX, Eps);
  AssertEquals('the frame is the wider line plus padding',
    200.0 - 20.0 - 5.0, t.Frame.Left, Eps);
  { AND AS DEEP AS BOTH LINES. Nothing above reads the block's HEIGHT --
    the subtext's own offset is computed from the title's height directly --
    so a version that forgot the second line when sizing the block still
    put both lines in the right place and only the frame came out short. }
  AssertEquals('the frame reaches under the subtitle',
    20.0 + 12.0 + 10.0 + 12.0 + 5.0, t.Frame.Bottom, Eps);
end;

procedure TAdvChartTitleTest.TestTheKeywordDecidesTheAlignmentNotThePosition;
var
  byWord, byPercent: TTyTitleLayout;
begin
  { install.ts:224 reads `left` as the ALIGNMENT when textAlign was not given,
    so a keyword and the percentage that means the same place do not align the
    same way. '50%' is not one of the three words, so it falls to left. }
  byWord := Lay('{ "title": { "text": "abcd", "left": "center" } }');
  byPercent := Lay('{ "title": { "text": "abcd", "left": "50%" } }');
  AssertEquals('the keyword centres the text', Ord(ttaCentre),
    Ord(byWord.Align));
  AssertEquals('the percentage does not', Ord(ttaLeft), Ord(byPercent.Align));

  { LEFT IS READ FIRST, and only a title whose two words DISAGREE can say
    so. With both set to the same thing -- or only one set at all -- reading
    them in either order gives the same answer. }
  AssertEquals('left wins over right', Ord(ttaLeft),
    Ord(Lay('{ "title": { "text": "abcd", "left": "left",'
      + ' "right": "right" } }').Align));

  { And because the auto rule also shifts the box, the two land in different
    places -- 200 is the centre for one and the left edge of the block for the
    other. }
  AssertEquals('centred on the middle', 200.0, byWord.TextX, Eps);
  { The percentage puts the block's LEFT EDGE at half the container, plus the
    padding the solver keeps outside it. }
  AssertEquals('and starting just past it', 205.0, byPercent.TextX, Eps);
  AssertEquals('so their frames differ', 175.0, byWord.Frame.Left, Eps);
  AssertEquals('', 200.0, byPercent.Frame.Left, Eps);
end;

procedure TAdvChartTitleTest.TestAnExplicitTextAlignDoesNotMoveTheBlock;
var
  auto_, explicit_: TTyTitleLayout;
begin
  { THE QUIRK WORTH PINNING. The shift lives inside the `if (!textAlign)`
    branch, so asking for the same alignment the auto rule would have chosen
    gives a DIFFERENT picture: the text is centred on the block's left edge
    instead of on the container. Written out because it is the first thing
    somebody reaches for when the auto result looks wrong to them. }
  auto_ := Lay('{ "title": { "text": "abcd", "left": "center" } }');
  explicit_ := Lay('{ "title": { "text": "abcd", "left": "center",'
    + ' "textAlign": "center" } }');
  AssertEquals('both centre the text', Ord(auto_.Align), Ord(explicit_.Align));
  AssertEquals('the auto one moved the anchor to the middle', 200.0,
    auto_.TextX, Eps);
  AssertEquals('the explicit one left it on the block''s edge', 180.0,
    explicit_.TextX, Eps);
end;

procedure TAdvChartTitleTest.TestARightTitleEndsAtTheRightEdge;
var t: TTyTitleLayout;
begin
  { right: 0 puts the block against the right edge less the padding, and the
    auto rule then anchors the text by its right side and shifts the box a
    whole width -- so the anchor IS the right edge of the block. }
  { `left: 'right'` IS THE IDIOMATIC FORM, and `right: 0` on its own is not:
    the keyword switch consults `left` first and the default puts 'center'
    there, so a title given only a right inset stays centred. }
  t := Lay('{ "title": { "text": "abcd", "left": "right" } }');
  AssertEquals('anchored by its right', Ord(ttaRight), Ord(t.Align));
  AssertEquals('at the right edge less the padding', 395.0, t.TextX, Eps);
  AssertEquals('and the frame ends there plus the padding', 400.0,
    t.Frame.Right, Eps);
end;

procedure TAdvChartTitleTest.TestABottomTitleSitsOnTheBottomEdge;
var t: TTyTitleLayout;
begin
  t := Lay('{ "title": { "text": "abcd", "top": "bottom" } }');
  AssertEquals('anchored by its foot', Ord(ttvBottom), Ord(t.VAlign));
  AssertEquals('sitting on the bottom edge less the padding', 295.0,
    t.TextY, Eps);
  AssertEquals('so the frame reaches the edge', 300.0, t.Frame.Bottom, Eps);
end;

procedure TAdvChartTitleTest.TestTheFrameSurroundsTheTextByItsPadding;
var t: TTyTitleLayout;
begin
  t := Lay('{ "title": { "text": "abcd", "left": 0, "top": 0,'
    + ' "padding": 7 } }');
  AssertEquals('the block starts inside the padding', 7.0, t.TextX, Eps);
  AssertEquals('', 7.0, t.TextY, Eps);
  AssertEquals('and the frame starts at the edge', 0.0, t.Frame.Left, Eps);
  AssertEquals('', 0.0, t.Frame.Top, Eps);
  AssertEquals('reaching the block plus the padding again', 54.0,
    t.Frame.Right, Eps);
  AssertEquals('', 26.0, t.Frame.Bottom, Eps);
end;

procedure TAdvChartTitleTest.TestPaddingTakesTheCssShortForms;
var s: TTyTitleSpec;
begin
  s := Spec('{ "title": { "text": "a", "padding": [1, 2] } }');
  AssertEquals('top', 1.0, s.Padding[0], Eps);
  AssertEquals('right', 2.0, s.Padding[1], Eps);
  AssertEquals('bottom takes the first again', 1.0, s.Padding[2], Eps);
  AssertEquals('left the second', 2.0, s.Padding[3], Eps);

  s := Spec('{ "title": { "text": "a", "padding": [1, 2, 3] } }');
  AssertEquals('three: bottom is its own', 3.0, s.Padding[2], Eps);
  AssertEquals('and left still shares with right', 2.0, s.Padding[3], Eps);
end;

procedure TAdvChartTitleTest.TestSeveralTitlesAreSeveralTitles;
var
  first, second: TTyTitleLayout;
begin
  { The array form is how a chart labels several panels. Reading only the
    first would silently drop the rest. }
  AssertTrue(FOpt.SetOptionText('{ "title": [ { "text": "aa", "left": 0 },'
    + ' { "text": "bbbb", "left": "right" } ] }'));
  AssertEquals('two of them', 2, TyTitleCount(FOpt));
  first := Lay('{ "title": [ { "text": "aa", "left": 0 },'
    + ' { "text": "bbbb", "left": "right" } ] }', 0);
  second := Lay('{ "title": [ { "text": "aa", "left": 0 },'
    + ' { "text": "bbbb", "left": "right" } ] }', 1);
  AssertEquals('the first on the left', Ord(ttaLeft), Ord(first.Align));
  AssertEquals('the second on the right', Ord(ttaRight), Ord(second.Align));
  AssertEquals('and they are different texts', 40.0, second.TextW, Eps);
end;

procedure TAdvChartTitleTest.TestShowFalseDrawsNothing;
begin
  AssertFalse('switched off',
    Lay('{ "title": { "text": "abcd", "show": false } }').Valid);
  AssertTrue('and on again',
    Lay('{ "title": { "text": "abcd", "show": true } }').Valid);

  { AN EXPLICIT null CLEARS THE DEFAULT. Without that, `left: null,
    right: 0` -- the long way of saying flush right -- keeps the default
    'center' and the title stays in the middle while the option that asked
    it to move is read and discarded. }
  AssertEquals('cleared, so the right inset decides', 355.0,
    Lay('{ "title": { "text": "abcd", "left": null,'
      + ' "right": 0 } }').TextX, Eps);
end;

procedure TAdvChartTitleTest.TestTheMarginKeepsSpaceOutsideTheSolvedBox;
var
  bx: TTyBoxSpec;
  r: TTyRectF;
begin
  { The solver's own margin, which the title is the first caller of. Asserted
    here rather than only through a title because it is the SHARED solver and
    the next component to want it -- legend -- will want it for a different
    reason. }
  bx := TyBoxSpec;
  bx.Left := TyBoxPx(0);
  bx.Top := TyBoxPx(0);
  bx.Width := TyBoxPx(50);
  bx.Height := TyBoxPx(20);
  r := TySolveBox(bx, TyFixedContainer(TyRectF(0, 0, 400, 300)), [7]);
  AssertEquals('the margin pushes the near edge in', 7.0, r.Left, Eps);
  AssertEquals('', 7.0, r.Top, Eps);
  AssertEquals('and the size is untouched', 57.0, r.Right, Eps);

  { A CENTRED box ignores the margin: upstream subtracts it and adds it back,
    so a centred block is centred on the container rather than on what is
    left of it. That cancellation is easy to lose by tidying -- and it takes
    an ASYMMETRIC margin to see: with the same number on both sides, centring
    on the container and centring on the gap give the same answer. }
  bx.Left := TyBoxCentre;
  r := TySolveBox(bx, TyFixedContainer(TyRectF(0, 0, 400, 300)),
    [7, 3, 7, 11]);
  AssertEquals('centred on the whole container', 175.0, r.Left, Eps);

  { AND THE SHORT FORMS ARE THE CSS ONES. Two values are vertical then
    HORIZONTAL, not top then right -- read the second way, a title padded
    [7, 3] hangs three pixels lower than it asked and nothing pads its left. }
  bx.Left := TyBoxPx(0);
  bx.Top := TyBoxPx(0);
  r := TySolveBox(bx, TyFixedContainer(TyRectF(0, 0, 400, 300)), [7, 3]);
  AssertEquals('the left inset is the SECOND value', 3.0, r.Left, Eps);
  AssertEquals('and the top the first', 7.0, r.Top, Eps);

  { And the far edge is held off by its own margin. }
  bx.Left := TyBoxAuto;
  bx.Right := TyBoxPx(0);
  r := TySolveBox(bx, TyFixedContainer(TyRectF(0, 0, 400, 300)), [7]);
  AssertEquals('the far edge is inset too', 393.0, r.Right, Eps);
  AssertEquals('', 343.0, r.Left, Eps);
end;

procedure TAdvChartTitleTest.TestTheDefaultSpecIsCoherentOnItsOwn;
var d: TTyTitleSpec;
begin
  { TyTitleSpecDefault is public and a caller may lay one out without ever
    reading an option -- so its box has to be pinned the same way the reader
    would pin it. Two ways of expressing `centred` that only agree after a
    read is one of them being wrong half the time, and it is the half nobody
    looks at. }
  d := TyTitleSpecDefault;
  AssertEquals('the word says centre', 'center', d.LeftWord);
  AssertEquals('and so does the box', Ord(buCentre), Ord(d.Box.Left.Kind));
  AssertEquals('with no competing right edge', Ord(buAuto),
    Ord(d.Box.Right.Kind));
end;

initialization
  RegisterTest(TAdvChartTitleTest);
end.
