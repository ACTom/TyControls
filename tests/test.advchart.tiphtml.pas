unit test.advchart.tiphtml;
{$mode objfpc}{$H+}
{ [R2-I8] AN HTML TOOLTIP.

  Upstream's renderMode 'auto' is 'html' in a browser: a formatter's string
  is the box's innerHTML, and params.marker is an inline-block span. The
  port draws its own box (spec section 55), so it reads that html itself
  (tyControls.AdvanceChart.TipHtml) into the lines and runs it measures and
  paints. Three suites:

    TAdvChartTipHtmlTest        the reader: what lines and runs a piece of
                                html becomes -- the gallery's formatters'
                                shapes, CSS's rules for the rest (the layout
                                is the browser's, not ECharts': there is no
                                node oracle for it);
    TAdvChartTipHtmlOracleTest  what the box is handed, upstream's
                                (tools/advchart-oracle/tooltip-html.js):
                                getTooltipMarker's html span and
                                formatTpl(html, params, true)'s encoding;
    TAdvChartTipHtmlChartTest   the chart: html mode by default, richText
                                when written (or when 'auto' is asked to be
                                node's), the marker a formatter is handed,
                                OnTooltipHtml first and the built-in reading
                                after it, an override of TooltipHtmlLines,
                                and the gallery's scatter-nutrients-matrix
                                box without its markup. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.AdvanceChart, tyControls.FontUnits,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint,
     tyControls.AdvanceChart.Data, tyControls.AdvanceChart.Handlers,
     tyControls.AdvanceChart.Tooltip, tyControls.AdvanceChart.TipHtml,
     tyControls.AdvanceChart.Color;

type
  TThProbe = class(TTyAdvanceChart)
  public
    { an override of the reading: when set, every html is one line saying
      'OVR' -- and the built-in reading is not asked }
    OverrideOn: Boolean;
    OverrideCalls: Integer;
    function Lines: TTyTooltipLineArray;
    function FmtText: string;
    procedure MoveTo(AX, AY: Integer);
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  protected
    function TooltipHtmlLines(const AHtml: string;
      const AInk: TTyTooltipInk): TTyTooltipLineArray; override;
  end;

  TAdvChartTipHtmlTest = class(TTestCase)
  private
    function Ink: TTyTooltipInk;
    function LineText(const ALine: TTyTooltipLine): string;
    function Read(const AHtml: string): TTyTooltipLineArray;
  published
    procedure TestABrBreaksTheLine;
    procedure TestOnlyABrMakesAnEmptyLine;
    procedure TestWhitespaceCollapses;
    procedure TestInlineStylesAreTheRunsInk;
    procedure TestTheMarkerSpanIsADot;
    procedure TestTheSubItemMarkerIsTheSmallDot;
    procedure TestBlockMarginsCollapse;
    procedure TestABordersRuleSitsInTheGap;
    procedure TestEntitiesAreDecoded;
    procedure TestUnknownTagsAreTheirText;
    procedure TestHiddenContentDrawsNothing;
    procedure TestALessThanThatIsNoTagIsText;
    procedure TestPreKeepsItsSpaces;
    procedure TestFloatRightIsTheValueColumn;
    procedure TestHeadingsAndParagraphsCarryTheirMargins;
    procedure TestMeasureStacksTheGapsAndTallerLines;
  end;

  TAdvChartTipHtmlOracleTest = class(TTestCase)
  private
    FRoot: TJSONData;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheHtmlMarkerIsUpstreams;
    procedure TestEncodeHtmlIsUpstreams;
    procedure TestATemplatesValuesAreEncodedAsUpstream;
  end;

  TAdvChartTipHtmlChartTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TThProbe;
    FMarkers: string;
    FEventCalls: Integer;
    FEventOrder: string;
    FHandle: Boolean;
    function Tip(const AParams: TTyChartParams): string;
    procedure OnHtml(Sender: TObject; const AHtml: string;
      const AInk: TTyTooltipInk; var ALines: TTyTooltipLineArray;
      var AHandled: Boolean);
    procedure Show(const AOption: string);
    procedure Render;
    function AllText: string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestHtmlModeReadsTheTemplate;
    procedure TestRichTextModeDrawsTheMarkupAsWritten;
    procedure TestAutoIsRichTextWhenAskedToBeNodes;
    procedure TestTheFormatterIsHandedTheHtmlMarker;
    procedure TestTheEventGoesFirst;
    procedure TestAnUnhandledEventFallsThroughToTheReading;
    procedure TestAnOverrideReplacesTheReading;
    procedure TestTheNutrientsBoxHasNoMarkup;
    procedure TestAComponentsNameIsTextInHtml;
  end;

implementation

uses ucallbacks, ugenerated;

const
  cInkSize = 10;   // points: 13.33 px
  cInkLine = 16;
  cInkColour = $FF333333;

function FixturePath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + AName;
end;

function ReadText(const APath: string): string;
var sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(APath);
    Result := sl.Text;
  finally
    sl.Free;
  end;
end;

{ ==================== the probe ==================== }

function TThProbe.Lines: TTyTooltipLineArray;
begin
  Result := TooltipLines;
end;

procedure TThProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TThProbe.MoveTo(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

function TThProbe.FmtText: string;
begin
  Result := TooltipFormatterText;
end;

function TThProbe.TooltipHtmlLines(const AHtml: string;
  const AInk: TTyTooltipInk): TTyTooltipLineArray;
begin
  if not OverrideOn then Exit(inherited TooltipHtmlLines(AHtml, AInk));
  Inc(OverrideCalls);
  Result := nil;
  SetLength(Result, 1);
  SetLength(Result[0].Runs, 1);
  Result[0].Runs[0].Kind := ttrText;
  Result[0].Runs[0].Text := 'OVR';
  Result[0].Runs[0].FontName := AInk.NameFontName;
  Result[0].Runs[0].FontSizeLogical := AInk.NameSizeLogical;
  Result[0].Runs[0].Colour := AInk.NameColour;
end;

{ ==================== the reader ==================== }

function TAdvChartTipHtmlTest.Ink: TTyTooltipInk;
begin
  Result := Default(TTyTooltipInk);
  Result.NameFontName := 'Arial';
  Result.NameSizeLogical := cInkSize;
  Result.NameWeight := 400;
  Result.NameColour := cInkColour;
  Result.ValueFontName := 'Arial';
  Result.ValueSizeLogical := cInkSize;
  Result.ValueWeight := 900;
  Result.ValueColour := cInkColour;
  Result.LineHeightLogical := cInkLine;
  Result.MarkerSizeLogical := 10;
  Result.MarkerGapLogical := 4;
  Result.GutterLogical := 20;
  Result.GutterCloseLogical := 10;
end;

function TAdvChartTipHtmlTest.LineText(const ALine: TTyTooltipLine): string;
var i: Integer;
begin
  Result := '';
  for i := 0 to High(ALine.Runs) do
    if ALine.Runs[i].Kind = ttrText then Result := Result + ALine.Runs[i].Text
    else Result := Result + '[box]';
end;

function TAdvChartTipHtmlTest.Read(const AHtml: string): TTyTooltipLineArray;
begin
  Result := TyTooltipHtmlLines(AHtml, Ink);
end;

procedure TAdvChartTipHtmlTest.TestABrBreaksTheLine;
var l: TTyTooltipLineArray; i: Integer;
begin
  { funnel's '{a} <br/>{b} : {c}%' and every spelling of br }
  l := Read('Series <br/>Name : 5%<br>x<br />y</br>z');
  AssertEquals('five lines', 5, Length(l));
  AssertEquals('the space before the br is dropped', 'Series', LineText(l[0]));
  AssertEquals('Name : 5%', LineText(l[1]));
  AssertEquals('x', LineText(l[2]));
  AssertEquals('y', LineText(l[3]));
  AssertEquals('</br> is a br too', 'z', LineText(l[4]));
  for i := 0 to High(l) do
  begin
    AssertEquals('one run', 1, Length(l[i].Runs));
    AssertEquals('the ink''s font', 'Arial', l[i].Runs[0].FontName);
    AssertEquals('the ink''s size, as the ink carries it', cInkSize, l[i].Runs[0].FontSizeLogical);
    AssertEquals('the ink''s weight', 400, l[i].Runs[0].FontWeight);
    AssertEquals('the ink''s colour', IntToHex(cInkColour, 8), IntToHex(l[i].Runs[0].Colour, 8));
    AssertEquals('the ink''s line', 0.0, l[i].HeightLogical, 0);
    AssertEquals('no gap', 0.0, l[i].GapBeforeLogical, 0);
    AssertFalse('a line', l[i].Spacer);
  end;
end;

procedure TAdvChartTipHtmlTest.TestOnlyABrMakesAnEmptyLine;
var l: TTyTooltipLineArray;
begin
  { the air-quality formatter ends on a <br>: no line after it }
  l := Read('a<br>b<br>');
  AssertEquals('a br at the end adds no line', 2, Length(l));
  l := Read('a<br><br>b');
  AssertEquals('two brs: an empty line between', 3, Length(l));
  AssertEquals('the empty line has nothing on it', 0, Length(l[1].Runs));
  l := Read('a<br><div>b</div>');
  AssertEquals('a block after a br: no empty line', 2, Length(l));
  l := Read('<div>a</div><br>b');
  AssertEquals('a br after a block is an empty line', 3, Length(l));
  l := Read('<div></div><div>a</div>');
  AssertEquals('an empty block is no line', 1, Length(l));
end;

procedure TAdvChartTipHtmlTest.TestWhitespaceCollapses;
var l: TTyTooltipLineArray;
begin
  { mbti's formatter: spans, newlines and runs of spaces between them }
  l := Read('<span style="color:#2D9A69;font-weight:bold">INFJ</span> /'#10
    + '                            <span style="color:undefined;font-weight:bold">x</span> :'#10
    + '                            42%');
  AssertEquals('one line: a newline is a space', 1, Length(l));
  AssertEquals('INFJ / x : 42%', LineText(l[0]));
  AssertEquals('four runs', 4, Length(l[0].Runs));
  AssertEquals('the first span''s colour', IntToHex($FF2D9A69, 8), IntToHex(l[0].Runs[0].Colour, 8));
  AssertEquals('bold', 700, l[0].Runs[0].FontWeight);
  AssertEquals(' / ', l[0].Runs[1].Text);
  AssertEquals('a colour that is none is the inherited one', IntToHex(cInkColour, 8),
    IntToHex(l[0].Runs[2].Colour, 8));
  AssertEquals('still bold', 700, l[0].Runs[2].FontWeight);
  AssertEquals(' : 42%', l[0].Runs[3].Text);
  l := Read('  a  '#9' b  ');
  AssertEquals('the ends trimmed, the middle one space', 'a b', LineText(l[0]));
end;

procedure TAdvChartTipHtmlTest.TestInlineStylesAreTheRunsInk;
var l: TTyTooltipLineArray;
begin
  l := Read('<b>B</b><strong>S</strong><i>I</i>'
    + '<span style="font-size:18px;color:rgb(10,20,30);font-family:''Courier New'', monospace">C</span>'
    + '<span style="font-weight:600;font-style:italic;font-size:1.5em">E</span>'
    + '<font color="#00ff00">F</font><span style="font-family:sans-serif">G</span>');
  AssertEquals('one line', 1, Length(l));
  AssertEquals('BSICEFG', LineText(l[0]));
  AssertEquals('b and strong are one run', 'BS', l[0].Runs[0].Text);
  AssertEquals('bold', 700, l[0].Runs[0].FontWeight);
  AssertEquals('italic', 400 or $10000, l[0].Runs[1].FontWeight);
  AssertEquals('a pixel size', TyFontSizeFromPx(18), l[0].Runs[2].FontSizeLogical);
  AssertEquals('rgb()', IntToHex($FF0A141E, 8), IntToHex(l[0].Runs[2].Colour, 8));
  AssertEquals('the first family that is not generic', 'Courier New', l[0].Runs[2].FontName);
  AssertEquals('em of the ink''s size',
    TyFontSizeFromPx(TyFontPxOf(cInkSize) * 1.5), l[0].Runs[3].FontSizeLogical);
  AssertEquals('a numeric weight with italic', 600 or $10000, l[0].Runs[3].FontWeight);
  AssertEquals('font color', IntToHex($FF00FF00, 8), IntToHex(l[0].Runs[4].Colour, 8));
  AssertEquals('a generic family is the ink''s font', 'Arial', l[0].Runs[5].FontName);
  { THE LINE TAKES ITS TALLEST: 1.5em = 20 px -> round(20 * 72 / 96 * 3 / 2) }
  AssertEquals('the line''s height', Round(20 * 72 / 96 * 3 / 2), l[0].HeightLogical, 0);
end;

procedure TAdvChartTipHtmlTest.TestTheMarkerSpanIsADot;
var l: TTyTooltipLineArray;
begin
  { flame-graph's `${params.marker} ${name}: (...)` in html mode }
  l := Read(TyTooltipHtmlMarker('#5470c6', False) + ' root: (5 samples, 100%)');
  AssertEquals('one line', 1, Length(l));
  AssertEquals('a box and the text', 2, Length(l[0].Runs));
  AssertTrue('the span is a box', l[0].Runs[0].Kind = ttrBox);
  AssertEquals('10 wide', 10.0, l[0].Runs[0].BoxWLogical, 0);
  AssertEquals('10 high', 10.0, l[0].Runs[0].BoxHLogical, 0);
  AssertEquals('radius 10 (CSS clamps it to a circle)', 10.0, l[0].Runs[0].BoxRadiusLogical, 0);
  AssertEquals('margin-right 4', 4.0, l[0].Runs[0].MarginRLogical, 0);
  AssertEquals('no left margin', 0.0, l[0].Runs[0].MarginLLogical, 0);
  AssertEquals('its background', IntToHex($FF5470C6, 8), IntToHex(l[0].Runs[0].Colour, 8));
  AssertEquals('the space after a box is kept', ' root: (5 samples, 100%)', l[0].Runs[1].Text);
  AssertEquals('a 10px box fits the ink''s line', 0.0, l[0].HeightLogical, 0);
end;

procedure TAdvChartTipHtmlTest.TestTheSubItemMarkerIsTheSmallDot;
var l: TTyTooltipLineArray;
begin
  l := Read(TyTooltipHtmlMarker('rgba(84,112,198,0.5)', True) + 'open');
  AssertTrue('a box', l[0].Runs[0].Kind = ttrBox);
  AssertEquals(4.0, l[0].Runs[0].BoxWLogical, 0);
  AssertEquals(4.0, l[0].Runs[0].BoxRadiusLogical, 0);
  AssertEquals('margin-left 3', 3.0, l[0].Runs[0].MarginLLogical, 0);
  AssertEquals('margin-right 8', 8.0, l[0].Runs[0].MarginRLogical, 0);
  AssertEquals('an rgba background', IntToHex($805470C6, 8), IntToHex(l[0].Runs[0].Colour, 8));
end;

procedure TAdvChartTipHtmlTest.TestBlockMarginsCollapse;
var l: TTyTooltipLineArray;
begin
  { scatter-nutrients-matrix's shape }
  l := Read('<div style="margin: 10px 0"><div style="font-size: 16px; color: #aaa">POINTS ON V LINE</div>'
    + '<div style="margin: 10px 0">Apple<br/><span style="color:#c23531">protein</span>: 3<br/>'
    + '<span style="color:#2f4554">fat</span>: 5</div></div>');
  AssertEquals('four lines and the bottom margin', 5, Length(l));
  AssertEquals('POINTS ON V LINE', LineText(l[0]));
  AssertEquals('the outer and the first child''s top margins collapse', 10.0, l[0].GapBeforeLogical, 0);
  AssertEquals('#aaa', IntToHex($FFAAAAAA, 8), IntToHex(l[0].Runs[0].Colour, 8));
  AssertEquals('16px', TyFontSizeFromPx(16), l[0].Runs[0].FontSizeLogical);
  AssertEquals('its line: round(16 * 72 / 96 * 3 / 2)', 18.0, l[0].HeightLogical, 0);
  AssertEquals('Apple', LineText(l[1]));
  AssertEquals('the second block''s top margin', 10.0, l[1].GapBeforeLogical, 0);
  AssertEquals('protein: 3', LineText(l[2]));
  AssertEquals('the field''s colour', IntToHex($FFC23531, 8), IntToHex(l[2].Runs[0].Colour, 8));
  AssertEquals('then the ink''s', IntToHex(cInkColour, 8), IntToHex(l[2].Runs[1].Colour, 8));
  AssertEquals(0.0, l[2].GapBeforeLogical, 0);
  AssertEquals('fat: 5', LineText(l[3]));
  AssertTrue('the bottom margins, collapsed into one spacer', l[4].Spacer);
  AssertEquals(10.0, l[4].GapBeforeLogical, 0);
  { siblings: the larger of the two, not their sum }
  l := Read('<div style="margin:10px 0">a</div><div style="margin-top:6px;margin-bottom:0">b</div>');
  AssertEquals('10 against 6: 10', 10.0, l[1].GapBeforeLogical, 0);
  { a padding stops the collapse }
  l := Read('<div style="margin-bottom:10px;padding-bottom:5px">a</div><div style="margin-top:4px">b</div>');
  AssertEquals('5 + max(10, 4)', 15.0, l[1].GapBeforeLogical, 0);
end;

procedure TAdvChartTipHtmlTest.TestABordersRuleSitsInTheGap;
var l: TTyTooltipLineArray;
begin
  { air-quality's title }
  l := Read('<div style="border-bottom: 1px solid rgba(255,255,255,.3); '
    + 'font-size: 18px;padding-bottom: 7px;margin-bottom: 7px">Beijing 1: 55</div>'
    + 'AQI: 55<br>PM2.5: 9<br>');
  AssertEquals('three lines', 3, Length(l));
  AssertEquals('Beijing 1: 55', LineText(l[0]));
  AssertEquals('18px: round(18 * 72 / 96 * 3 / 2)', 20.0, l[0].HeightLogical, 0);
  AssertEquals('AQI: 55', LineText(l[1]));
  AssertEquals('padding 7, the border 1, margin 7', 15.0, l[1].GapBeforeLogical, 0);
  AssertEquals('one rule', 1, Length(l[1].Rules));
  AssertEquals('under the padding: 8 above the next line', -8.0, l[1].Rules[0].OffsetLogical, 0);
  AssertEquals('1 thick', 1.0, l[1].Rules[0].WidthLogical, 0);
  AssertEquals('its colour', IntToHex($4DFFFFFF, 8), IntToHex(l[1].Rules[0].Colour, 8));
  AssertEquals(0, Length(l[2].Rules));
  { a border with no style is none }
  l := Read('<div style="border-bottom: 1px #000">a</div>b');
  AssertEquals(0, Length(l[1].Rules));
  { hr: half an em each side, a rule between }
  l := Read('a<hr>b');
  AssertEquals(2, Length(l));
  AssertEquals(1, Length(l[1].Rules));
  AssertEquals(TyFontPxOf(cInkSize) + 2, l[1].GapBeforeLogical, 1e-9);
end;

procedure TAdvChartTipHtmlTest.TestEntitiesAreDecoded;
var l: TTyTooltipLineArray;
begin
  { the treemap formatters' &nbsp;&nbsp; }
  l := Read('<div class="tooltip-title">a/b</div>2012 Amount: &nbsp;&nbsp;$1,000<br>Change: &nbsp;&nbsp;5%');
  AssertEquals('a/b', LineText(l[0]));
  AssertEquals('nbsp is not collapsed', '2012 Amount: '#$C2#$A0#$C2#$A0'$1,000', LineText(l[1]));
  l := Read('a&lt;b&gt;&amp;&quot;&#39;&#x41;&#66;&apos;&foo;&amp x');
  AssertEquals('named, numeric; an unknown or unterminated one as written',
    'a<b>&"''AB''&foo;&amp x', LineText(l[0]));
  AssertEquals('an encoded tag is text, not a tag', '<b>x</b>', LineText(Read('&lt;b&gt;x&lt;/b&gt;')[0]));
end;

procedure TAdvChartTipHtmlTest.TestUnknownTagsAreTheirText;
var l: TTyTooltipLineArray;
begin
  l := Read('<foo x="1">bar</foo><a href="#">link</a><table><tr><th>H</th><td>a</td><td>b</td></tr>'
    + '<tr><td>c</td></tr></table>');
  AssertEquals('three lines', 3, Length(l));
  AssertEquals('an unknown tag is its text', 'barlink', LineText(l[0]));
  AssertEquals('cells side by side', 'H a b', LineText(l[1]));
  AssertEquals('a th is bold', 700, l[1].Runs[0].FontWeight);
  AssertEquals('c', LineText(l[2]));
  AssertTrue('no markup anywhere', Pos('<', LineText(l[0]) + LineText(l[1])) = 0);
end;

procedure TAdvChartTipHtmlTest.TestHiddenContentDrawsNothing;
var l: TTyTooltipLineArray;
begin
  l := Read('a<span style="display:none">b<br>c</span>d<!-- x<br> --><script>y<z</script>'
    + '<style>.q{color:red}</style>e<img src="x.png">f');
  AssertEquals('one line', 1, Length(l));
  AssertEquals('adef', LineText(l[0]));
end;

procedure TAdvChartTipHtmlTest.TestALessThanThatIsNoTagIsText;
begin
  AssertEquals('a < b and 1<2 <', LineText(Read('a < b and 1<2 <')[0]));
end;

procedure TAdvChartTipHtmlTest.TestPreKeepsItsSpaces;
var l: TTyTooltipLineArray; em: Double;
begin
  em := TyFontPxOf(cInkSize);
  l := Read('x<pre>a  b'#10'c</pre>y');
  AssertEquals(4, Length(l));
  AssertEquals('x', LineText(l[0]));
  AssertEquals('spaces kept', 'a  b', LineText(l[1]));
  AssertEquals('pre''s margin: 1em', em, l[1].GapBeforeLogical, 1e-9);
  AssertEquals('a newline breaks', 'c', LineText(l[2]));
  AssertEquals('y', LineText(l[3]));
  AssertEquals(em, l[3].GapBeforeLogical, 1e-9);
end;

procedure TAdvChartTipHtmlTest.TestFloatRightIsTheValueColumn;
var l: TTyTooltipLineArray;
begin
  { upstream's own html markup floats the value right }
  l := Read('<span style="margin-left:2px">Mon</span>'
    + '<span style="float:right;margin-left:20px;font-weight:900">120</span>');
  AssertEquals(2, Length(l[0].Runs));
  AssertFalse('the name in the flow', l[0].Runs[0].AlignRight);
  AssertTrue('the value against the right edge', l[0].Runs[1].AlignRight);
  AssertEquals(900, l[0].Runs[1].FontWeight);
end;

procedure TAdvChartTipHtmlTest.TestHeadingsAndParagraphsCarryTheirMargins;
var l: TTyTooltipLineArray; em: Double;
begin
  em := TyFontPxOf(cInkSize);
  l := Read('<h3>T</h3><p>a</p><p>b</p>');
  AssertEquals('three lines and the last margin', 4, Length(l));
  AssertEquals('h3 is bold', 700, l[0].Runs[0].FontWeight);
  AssertEquals('h3 is 1.17em', TyFontSizeFromPx(em * 1.17), l[0].Runs[0].FontSizeLogical);
  AssertEquals('h3''s top margin: 1em of its own size', em * 1.17, l[0].GapBeforeLogical, 1e-9);
  AssertEquals('h3''s bottom and p''s top collapse', Max(em * 1.17, em), l[1].GapBeforeLogical, 1e-9);
  AssertEquals('p to p: one em', em, l[2].GapBeforeLogical, 1e-9);
  AssertTrue(l[3].Spacer);
end;

type
  TFixedMeasurer = class(TInterfacedObject, ITyTextMeasurer)
    procedure MeasureLine(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
    function WrapToWidth(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
  end;

procedure TFixedMeasurer.MeasureLine(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
begin
  AW := 7 * Length(AText);
  AH := 14;
end;

function TFixedMeasurer.WrapToWidth(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
begin
  Result := AText;
end;

procedure TAdvChartTipHtmlTest.TestMeasureStacksTheGapsAndTallerLines;
var
  l: TTyTooltipLineArray;
  w, h: Double;
  m: ITyTextMeasurer;
begin
  m := TFixedMeasurer.Create;
  l := Read('<div style="margin:10px 0;padding-left:6px"><span style="font-size:24px">T</span></div>'
    + TyTooltipHtmlMarker('#000000', False) + 'ab');
  { at 192 PPI everything doubles }
  TyTooltipMeasure(l, Ink, m, 192, 1, 2, 3, 4, w, h);
  AssertEquals('two lines', 2, Length(l));
  AssertEquals('the first line''s top: its gap', 20.0, l[0].ExtraTopPx, 1e-9);
  AssertEquals('its height: round(24 * 72 / 96 * 3 / 2) = 27', 54.0, l[0].HPx, 1e-9);
  AssertEquals('indented by the padding', 12.0, l[0].Runs[0].X, 1e-9);
  AssertEquals('the second: gap 10 and the first line''s extra height',
    20.0 + 20.0 + (54.0 - cInkLine * 2), l[1].ExtraTopPx, 1e-9);
  AssertEquals('its own line', cInkLine * 2.0, l[1].HPx, 1e-9);
  AssertEquals('the box: margin, side, margin', (0 + 10 + 4) * 2.0, l[1].Runs[0].W, 1e-9);
  AssertEquals('the text after it', 28.0, l[1].Runs[1].X, 1e-9);
  AssertEquals('the box: paddings, two rows, the extra', 2 + 2 * cInkLine * 2.0 + l[1].ExtraTopPx + 4, h, 1e-9);
  AssertEquals('the width: the widest line', 1 + Max(12.0 + 7, 28.0 + 14) + 3, w, 1e-9);
end;

{ ==================== the oracle ==================== }

procedure TAdvChartTipHtmlOracleTest.SetUp;
begin
  inherited SetUp;
  FRoot := GetJSON(ReadText(FixturePath('advchart-tooltip-html.json')));
end;

procedure TAdvChartTipHtmlOracleTest.TearDown;
begin
  FreeAndNil(FRoot);
  inherited TearDown;
end;

procedure TAdvChartTipHtmlOracleTest.TestTheHtmlMarkerIsUpstreams;
var
  a: TJSONArray;
  i: Integer;
  o: TJSONObject;
  c: TTyChartColor;
begin
  a := TJSONObject(FRoot).Arrays['markers'];
  AssertTrue('markers', a.Count >= 10);
  for i := 0 to a.Count - 1 do
  begin
    o := a.Objects[i];
    AssertEquals(o.Strings['color'] + ' ' + o.Strings['type'], o.Strings['html'],
      TyTooltipHtmlMarker(o.Strings['color'], o.Strings['type'] = 'subItem'));
    { and the colour text a packed colour is written back as }
    AssertTrue(TyTryParseChartColor(o.Strings['color'], c));
    AssertEquals('the colour text of ' + o.Strings['color'], o.Strings['color'],
      TyTooltipColourText(c));
  end;
end;

procedure TAdvChartTipHtmlOracleTest.TestEncodeHtmlIsUpstreams;
var a: TJSONArray; i: Integer;
begin
  a := TJSONObject(FRoot).Arrays['encode'];
  for i := 0 to a.Count - 1 do
    AssertEquals(a.Objects[i].Strings['in'], a.Objects[i].Strings['out'],
      TyChartEncodeHtml(a.Objects[i].Strings['in']));
end;

procedure TAdvChartTipHtmlOracleTest.TestATemplatesValuesAreEncodedAsUpstream;
var
  a, ps: TJSONArray;
  i, k: Integer;
  params: TTyChartParams;
  v: TJSONData;
begin
  a := TJSONObject(FRoot).Arrays['tpl'];
  for i := 0 to a.Count - 1 do
  begin
    ps := a.Objects[i].Arrays['params'];
    params := nil;
    SetLength(params, ps.Count);
    for k := 0 to ps.Count - 1 do
    begin
      params[k] := TyChartBlankParams;
      params[k].SeriesName := ps.Objects[k].Strings['seriesName'];
      params[k].Name := ps.Objects[k].Strings['name'];
      v := ps.Objects[k].Find('value');
      params[k].Raw.Shape := rshScalar;
      if v.JSONType = jtNumber then
      begin
        params[k].Raw.Scalar.Kind := dvkNumber;
        params[k].Raw.Scalar.Num := v.AsFloat;
      end
      else
      begin
        params[k].Raw.Scalar.Kind := dvkText;
        params[k].Raw.Scalar.Text := v.AsString;
      end;
    end;
    AssertEquals(a.Objects[i].Strings['id'], a.Objects[i].Strings['out'],
      TyChartFormatTemplate(a.Objects[i].Strings['tpl'], params, True));
  end;
end;

{ ==================== the chart ==================== }

const
  cBar = '{"animation":false,"color":["#5470c6","#91cc75"],%s'
    + '"xAxis":{"type":"category","data":["a<1>","b","c"]},"yAxis":{},'
    + '"series":[{"type":"bar","name":"s&t","data":[3,5,2]}]}';

procedure TAdvChartTipHtmlChartTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TThProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.AnimationMode := camOff;
  FChart.SetBounds(0, 0, 400, 300);
  FMarkers := '';
  FEventCalls := 0;
  FEventOrder := '';
  FHandle := False;
  TyChartRegisterFormatter('thTip', @Tip);
end;

procedure TAdvChartTipHtmlChartTest.TearDown;
begin
  TyChartUnregisterFormatter('thTip');
  FreeAndNil(FChart);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

function TAdvChartTipHtmlChartTest.Tip(const AParams: TTyChartParams): string;
var i: Integer;
begin
  Result := '';
  for i := 0 to High(AParams) do
  begin
    FMarkers := FMarkers + '|' + AParams[i].Marker;
    Result := Result + AParams[i].Marker + '<b>' + AParams[i].Name + '</b>: '
      + FloatToStr(AParams[i].Values[0]) + '<br/>';
  end;
end;

procedure TAdvChartTipHtmlChartTest.OnHtml(Sender: TObject; const AHtml: string;
  const AInk: TTyTooltipInk; var ALines: TTyTooltipLineArray;
  var AHandled: Boolean);
begin
  Inc(FEventCalls);
  FEventOrder := FEventOrder + 'E';
  if FHandle then
  begin
    SetLength(ALines, 1);
    SetLength(ALines[0].Runs, 1);
    ALines[0].Runs[0].Kind := ttrText;
    ALines[0].Runs[0].Text := 'MINE';
    ALines[0].Runs[0].FontName := AInk.NameFontName;
    ALines[0].Runs[0].FontSizeLogical := AInk.NameSizeLogical;
    AHandled := True;
  end;
end;

procedure TAdvChartTipHtmlChartTest.Show(const AOption: string);
begin
  FChart.Option := AOption;
  AssertEquals('the option parses', '', FChart.OptionError);
  Render;
end;

procedure TAdvChartTipHtmlChartTest.Render;
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(400, 300, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, 400, 300), 96);
  finally
    bmp.Free;
  end;
end;

function TAdvChartTipHtmlChartTest.AllText: string;
var l: TTyTooltipLineArray; i, j: Integer;
begin
  Result := '';
  l := FChart.Lines;
  for i := 0 to High(l) do
  begin
    if i > 0 then Result := Result + '/';
    for j := 0 to High(l[i].Runs) do
      if l[i].Runs[j].Kind = ttrText then Result := Result + l[i].Runs[j].Text
      else Result := Result + '[box]';
  end;
end;

procedure TAdvChartTipHtmlChartTest.TestHtmlModeReadsTheTemplate;
begin
  Show(Format(cBar, ['"tooltip":{"formatter":"{a}<br/>{b}: {c}"},']));
  FChart.DispatchAction('{"type":"showTip","seriesIndex":0,"dataIndex":0}');
  Render;
  AssertEquals('the formatter''s text: the values encoded (formatTpl(.., true))',
    's&amp;t<br/>a&lt;1&gt;: 3', FChart.FmtText);
  AssertEquals('read as html: two lines, the entities decoded', 's&t/a<1>: 3', AllText);
end;

procedure TAdvChartTipHtmlChartTest.TestRichTextModeDrawsTheMarkupAsWritten;
begin
  Show(Format(cBar, ['"tooltip":{"formatter":"{a}<br/>{b}: {c}","renderMode":"richText"},']));
  FChart.DispatchAction('{"type":"showTip","seriesIndex":0,"dataIndex":0}');
  Render;
  AssertEquals('richText draws the string as it is -- upstream''s formatTpl encodes there too',
    's&amp;t<br/>a&lt;1&gt;: 3', AllText);
  AssertEquals('one line', 1, Length(FChart.Lines));
end;

procedure TAdvChartTipHtmlChartTest.TestAutoIsRichTextWhenAskedToBeNodes;
begin
  FChart.TooltipAutoRichText := True;
  Show(Format(cBar, ['"tooltip":{"formatter":"{a}<br/>{b}"},']));
  FChart.DispatchAction('{"type":"showTip","seriesIndex":0,"dataIndex":0}');
  Render;
  AssertEquals('''auto'' as node: richText', 's&amp;t<br/>a&lt;1&gt;', AllText);
  { a written 'html' is html whatever 'auto' means }
  Show(Format(cBar, ['"tooltip":{"formatter":"{a}<br/>{b}","renderMode":"html"},']));
  FChart.DispatchAction('{"type":"showTip","seriesIndex":0,"dataIndex":0}');
  Render;
  AssertEquals('a written html', 's&t/a<1>', AllText);
end;

procedure TAdvChartTipHtmlChartTest.TestTheFormatterIsHandedTheHtmlMarker;
var l: TTyTooltipLineArray;
begin
  Show(Format(cBar, ['"tooltip":{"formatter":"@thTip"},']));
  FChart.DispatchAction('{"type":"showTip","seriesIndex":0,"dataIndex":1}');
  Render;
  AssertEquals('getTooltipMarker''s html span in the item''s colour',
    '|' + TyTooltipHtmlMarker('#5470c6', False), FMarkers);
  l := FChart.Lines;
  AssertEquals('one line (the trailing br adds none)', 1, Length(l));
  AssertTrue('the span drawn as a box', l[0].Runs[0].Kind = ttrBox);
  AssertEquals(IntToHex($FF5470C6, 8), IntToHex(l[0].Runs[0].Colour, 8));
  AssertEquals('then the bold name', 'b', l[0].Runs[1].Text);
  AssertEquals(700, l[0].Runs[1].FontWeight and $FFFF);
  AssertEquals(': 5', l[0].Runs[2].Text);
end;

procedure TAdvChartTipHtmlChartTest.TestTheEventGoesFirst;
begin
  FChart.OnTooltipHtml := @OnHtml;
  FHandle := True;
  Show(Format(cBar, ['"tooltip":{"formatter":"{a}<br/>{b}"},']));
  FChart.DispatchAction('{"type":"showTip","seriesIndex":0,"dataIndex":0}');
  Render;
  AssertEquals('asked once per show', 1, FEventCalls);
  AssertEquals('its lines drawn', 'MINE', AllText);
end;

procedure TAdvChartTipHtmlChartTest.TestAnUnhandledEventFallsThroughToTheReading;
begin
  FChart.OnTooltipHtml := @OnHtml;
  FHandle := False;
  Show(Format(cBar, ['"tooltip":{"formatter":"{a}<br/>{b}"},']));
  FChart.DispatchAction('{"type":"showTip","seriesIndex":0,"dataIndex":0}');
  Render;
  AssertEquals('asked', 1, FEventCalls);
  AssertEquals('the built-in reading after it', 's&t/a<1>', AllText);
  { richText never asks }
  FEventCalls := 0;
  Show(Format(cBar, ['"tooltip":{"formatter":"{a}<br/>{b}","renderMode":"richText"},']));
  FChart.DispatchAction('{"type":"showTip","seriesIndex":0,"dataIndex":0}');
  Render;
  AssertEquals('richText is not html', 0, FEventCalls);
end;

procedure TAdvChartTipHtmlChartTest.TestAnOverrideReplacesTheReading;
begin
  FChart.OverrideOn := True;
  Show(Format(cBar, ['"tooltip":{"formatter":"{a}<br/>{b}"},']));
  FChart.DispatchAction('{"type":"showTip","seriesIndex":0,"dataIndex":0}');
  Render;
  AssertEquals('the override ran', 1, FChart.OverrideCalls);
  AssertEquals('its lines drawn', 'OVR', AllText);
end;

{ THE DEMO'S BOX: scatter-nutrients-matrix as the demo sets it up -- its
  callbacks registered, GalleryPrepare, 900 x 600 -- the pointer in the
  first grid. The formatter answers html (POINTS ON V LINE, the point's
  name, a coloured field per row); the box draws it with no markup. }
procedure TAdvChartTipHtmlChartTest.TestTheNutrientsBoxHasNoMarkup;
var
  dir, text, all: string;
  bmp: TBGRABitmap;
  l: TTyTooltipLineArray;
  i, j, coloured: Integer;
  got: Boolean;
  pts: array[0..2] of TPoint;
begin
  dir := '';
  for i := 0 to 5 do
  begin
    if DirectoryExists(ExtractFilePath(ParamStr(0)) + dir + 'examples' + PathDelim + 'advchart') then
      Break;
    dir := dir + '..' + PathDelim;
  end;
  dir := ExtractFilePath(ParamStr(0)) + dir + 'examples' + PathDelim + 'advchart' + PathDelim;
  RegisterGalleryCallbacks;
  GalleryDataDir := dir + 'data' + PathDelim;
  text := ReadText(dir + 'gallery' + PathDelim + 'scatter-nutrients-matrix.json');
  GalleryPrepare('scatter-nutrients-matrix', text);
  FChart.SetBounds(0, 0, 900, 600);
  FChart.Option := text;
  AssertEquals('the option parses', '', FChart.OptionError);
  pts[0] := Point(200, 120);
  pts[1] := Point(240, 150);
  pts[2] := Point(160, 100);
  got := False;
  for i := 0 to High(pts) do
  begin
    bmp := TBGRABitmap.Create(900, 600, BGRA(255, 255, 255, 255));
    try
      FChart.Render(bmp.Canvas, Rect(0, 0, 900, 600), 96);
      FChart.MoveTo(pts[i].X, pts[i].Y);
      FChart.Render(bmp.Canvas, Rect(0, 0, 900, 600), 96);
    finally
      bmp.Free;
    end;
    l := FChart.Lines;
    if Length(l) = 0 then Continue;
    got := True;
    AssertTrue('the formatter answered html', Pos('<div', FChart.FmtText) > 0);
    all := '';
    coloured := 0;
    for j := 0 to High(l) do
    begin
      all := all + '/';
      if Length(l[j].Runs) > 0 then
        all := all + l[j].Runs[0].Text;
      if (Length(l[j].Runs) > 1) and (l[j].Runs[0].Colour <> l[j].Runs[1].Colour) then
        Inc(coloured);
    end;
    AssertTrue('no markup: ' + all, (Pos('<', all) = 0) and (Pos('>', all) = 0));
    AssertTrue('POINTS ON ... first: ' + all, Pos('/POINTS ON ', all) = 1);
    AssertEquals('#aaa', IntToHex($FFAAAAAA, 8), IntToHex(l[0].Runs[0].Colour, 8));
    AssertTrue('the fields in their colours: ' + all, coloured >= 2);
    AssertTrue('the top margin', l[0].GapBeforeLogical >= 10);
  end;
  AssertTrue('a box at one of the points', got);
end;

{ setTooltipConfig's encodeHTMLContent: in html mode a component item's
  content -- its name -- is encodeHTML'd before it is the box's html, so a
  name with markup in it is shown as written, not read as a tag }
procedure TAdvChartTipHtmlChartTest.TestAComponentsNameIsTextInHtml;
const
  cM = '{"animation":false,"tooltip":{%s},'
    + '"matrix":{"x":{"data":["A<B>&amp;","C"]},"y":{"data":["P"]},"tooltip":{"show":true}}}';
begin
  Show(Format(cM, ['']));
  AssertTrue('taken', FChart.DispatchAction('{"type":"showTip","matrixIndex":0,"name":"A<B>&amp;"}'));
  Render;
  AssertEquals('the name as written', 'A<B>&amp;', AllText);
  { richText: the content is not encoded, and drawn as it is }
  Show(Format(cM, ['"renderMode":"richText"']));
  AssertTrue('taken', FChart.DispatchAction('{"type":"showTip","matrixIndex":0,"name":"A<B>&amp;"}'));
  Render;
  AssertEquals('richText: as written too', 'A<B>&amp;', AllText);
end;

initialization
  RegisterTest(TAdvChartTipHtmlTest);
  RegisterTest(TAdvChartTipHtmlOracleTest);
  RegisterTest(TAdvChartTipHtmlChartTest);
end.
