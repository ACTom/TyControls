unit test.advchart.timeformat;
{$mode objfpc}{$H+}
{ THE TIME AXIS FORMATTER, HELD TO UPSTREAM [Batch 104, roadmap B7].

  tools/advchart-oracle/time-format.js runs the real ECharts 6.1 build in
  node (TZ = UTC) and records:
    format   echarts.time.format over the 24 tokens alone and together, the
             tokens nobody knows, braces round and inside tokens, the
             rounding of a fractional instant, the invalid date, useUTC off;
    dict     parseTimeAxisLabelFormatter, cut out of the dist and run on its
             own: every unit's leveled list, the cascade, the primary;
    charts   what a time axis draws for the default formatter over every
             span from years to milliseconds, a string, the dictionary in
             every form, and the primary's rich styling: each label's
             formatted text, whether it is drawn, its level, and the rich
             pieces its Text turns into;
    tooltip  a string tooltip.formatter under an axis trigger on a time axis
             (time-formatted first), the axis tooltip's header, and a time
             value in an item tooltip.

  This replays them: the format and the dictionary through the Time unit,
  the charts and the tooltip through the control with zrender's SSR width
  table. The fixture's useUTC-off cases are written so that they read the
  same on any fixed-offset clock -- zone-less date strings in the charts, and
  in the format cases the instant shifted here by the machine's own offset --
  so they replay on this machine too. Upstream's names are English; the port
  takes them from TyDateTimeNames, pinned here to the library's own
  (English) resourcestrings. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Types, tyControls.Controller, tyControls.StrConsts,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint,
     tyControls.AdvChart.Option, tyControls.AdvChart.Color,
     tyControls.AdvChart.Handlers, tyControls.AdvChart.Tooltip,
     tyControls.AdvChart.Time, tyControls.AdvChart.Coord, tyControls.AdvChart.Scale,
     tyControls.AdvChart.Builder, tyControls.AdvChart.Layout,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TTmfProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Move(AX, AY: Integer);
    function ContentOf(const ADatum: TTyChartDatumRef): TTyTooltipBlock;
    function FormatterText: string;
  end;

  TAdvChartTimeFormatOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TTmfProbe;
    FRoot, FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared: Integer;
    FReport, FWhere: string;
    FSavedSource: TTyDateTimeNameSource;
    procedure Bad(const AWhat: string);
    procedure Finish(const AWhat: string);
    function Section(const AName: string): TJSONArray;
    procedure NewChart(AOption: TJSONData);
    function LocalShift: Double;
    procedure CheckPieces(ACase, ALabel: TJSONObject; const APlace: TTyAxisLabelPlacement);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheTokensAndTemplatesAreUpstreams;
    procedure TestEveryFormatAsUpstream;
    procedure TestEveryDictionaryAsUpstream;
    procedure TestEveryTimeAxisDrawsWhatUpstreamDraws;
    procedure TestTheTooltipFormatsTimeAsUpstream;
    { hand-written: what the fixture cannot say }
    procedure TestThePrimaryTakesTheSkinsColourAndWeight;
    procedure TestAnAuthorsColourBeatsTheSkinsPrimary;
    procedure TestUseUtcDecidesTheClock;
  end;

implementation

uses tyControls.FontUnits, tyControls.AdvChart.RichStyle;

const
  cW = 600;
  cH = 400;

{ ==================== the probe ==================== }

function TTmfProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TTmfProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TTmfProbe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

function TTmfProbe.ContentOf(const ADatum: TTyChartDatumRef): TTyTooltipBlock;
begin
  Result := TooltipContent(ADatum, TooltipSpecFor(ADatum));
end;

function TTmfProbe.FormatterText: string;
begin
  Result := TooltipFormatterText;
end;

{ ==================== helpers ==================== }

function FixturePath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + AName;
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  Result := 0;
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

function UnitOf(const AName: string): TTyTimeUnit;
var u: TTyTimeUnit;
begin
  for u := Low(TTyTimeUnit) to High(TTyTimeUnit) do
    if TyTimeUnitName(u) = AName then Exit(u);
  raise Exception.Create('no unit ' + AName);
end;

{ every author colour the option writes as `color` }
procedure CollectColours(AData: TJSONData; AOut: TStrings);
var i: Integer;
begin
  if AData is TJSONObject then
  begin
    for i := 0 to AData.Count - 1 do
      if (TJSONObject(AData).Names[i] = 'color') and (AData.Items[i].JSONType = jtString) then
        AOut.Add(LowerCase(AData.Items[i].AsString))
      else
        CollectColours(AData.Items[i], AOut);
  end
  else if AData is TJSONArray then
    for i := 0 to AData.Count - 1 do CollectColours(AData.Items[i], AOut);
end;

{ A TSPAN WITH NO fontWeight OF ITS OWN is drawn in its font string's:
  'style weight size family' -- the block's weight }
function FontStringWeight(const AFont: string): Integer;
var s: string; p: Integer; d: TJSONData;
begin
  s := AFont;
  p := Pos(' ', s);
  Delete(s, 1, p);
  p := Pos(' ', s);
  if p > 0 then s := Copy(s, 1, p - 1);
  d := TJSONString.Create(s);
  try
    if (s <> '') and (s[1] in ['0'..'9']) then Result := StrToIntDef(s, 400)
    else Result := TyFontWeightOf(d, 400);
  finally
    d.Free;
  end;
end;

function ColourOf(const S: string): TTyChartColor;
begin
  if not TyTryParseChartColor(S, Result) then Result := 0;
end;

procedure TAdvChartTimeFormatOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  { upstream's names are its English locale; the port's come from the
    library's rule, pinned to its own resourcestrings, which are English
    until a catalogue says otherwise }
  FSavedSource := TyDateTimeNameSource;
  TyDateTimeNameSource := dnTranslation;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath('advchart-time-format.json'));
    FRoot := GetJSON(sl.Text);
    sl.LoadFromFile(FixturePath('advchart-text-style.json'));
    FMeasure := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartTimeFormatOracleTest.TearDown;
begin
  FChart.Free;
  FChart := nil;
  FRoot.Free;
  FMeasure.Free;
  FBmp.Free;
  FForm.Free;
  FCtl.Free;
  TyDateTimeNameSource := FSavedSource;
  inherited TearDown;
end;

procedure TAdvChartTimeFormatOracleTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 12000 then
    FReport := FReport + LineEnding + '  ' + FWhere + ': ' + AWhat;
end;

procedure TAdvChartTimeFormatOracleTest.Finish(const AWhat: string);
begin
  AssertTrue(AWhat + ': something was compared', FCompared > 0);
  AssertEquals(Format('%s: %d of %d differ:%s', [AWhat, FBad, FCompared, FReport]), 0, FBad);
end;

function TAdvChartTimeFormatOracleTest.Section(const AName: string): TJSONArray;
begin
  Result := TJSONObject(FRoot).Arrays[AName];
end;

procedure TAdvChartTimeFormatOracleTest.NewChart(AOption: TJSONData);
begin
  FChart.Free;
  FChart := TTmfProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  FChart.Option := AOption.AsJSON;
  AssertEquals(FWhere + ': the option parses', '', FChart.OptionError);
  FChart.SetBounds(0, 0, cW, cH);
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

{ THE MACHINE'S OFFSET, as the port applies it: the fixture's useUTC-off
  answers are the UTC wall clock, which this machine's local clock reads at
  the instant this much earlier (or later). }
function TAdvChartTimeFormatOracleTest.LocalShift: Double;
begin
  Result := GetLocalTimeOffset * 60000.0;
end;

{ ==================== tokens and templates ==================== }

procedure TAdvChartTimeFormatOracleTest.TestTheTokensAndTemplatesAreUpstreams;
var
  tokens: TJSONArray;
  seed, full: TJSONObject;
  i: Integer;
  u: TTyTimeUnit;
  all, want: string;
  day, span: Double;
begin
  FWhere := 'tokens';
  { THE 24 TOKENS IN UPSTREAM'S ORDER: each replaced over what the ones before
    left, so a template naming all of them, at an instant where each says
    something different, reads them in the fixture's order }
  tokens := TJSONObject(FRoot).Arrays['tokens'];
  AssertEquals('24 tokens', 24, tokens.Count);
  all := '';
  for i := 0 to tokens.Count - 1 do
  begin
    if i > 0 then all := all + '|';
    all := all + '{' + tokens.Strings[i] + '}';
  end;
  for i := 0 to Section('format').Count - 1 do
    if Section('format').Objects[i].Strings['id'] = 'invalid-nan' then
      want := Section('format').Objects[i].Strings['tpl'];
  AssertEquals('the fixture''s every-token template is the token list', want, all);
  seed := TJSONObject(FRoot).Objects['constants'].Objects['seed'];
  for u := Low(TTyTimeUnit) to High(TTyTimeUnit) do
  begin
    Inc(FCompared);
    if TyTimeSeed(u) <> seed.Strings[TyTimeUnitName(u)] then
      Bad(TyTimeUnitName(u) + ' seed ' + TyTimeSeed(u));
  end;
  { the full templates TimeScale.getLabel picks from (the millisecond one is
    beyond the port's reach: its interval table stops at a second) }
  full := TJSONObject(FRoot).Objects['constants'].Objects['full'];
  day := 86400000;
  span := day * 400;
  Inc(FCompared);
  if TyTimeFullLabel(day, 0, span, 6, True, 0, 0)
    <> TyFormatTime(day, full.Strings['day'], True) then Bad('the day-precision label');
  Inc(FCompared);
  if TyTimeFullLabel(day, 0, day, 6, True, 0, 0)
    <> TyFormatTime(day, full.Strings['second'], True) then Bad('the second-precision label');
  Finish('tokens');
end;

{ ==================== format ==================== }

procedure TAdvChartTimeFormatOracleTest.TestEveryFormatAsUpstream;
var
  arr: TJSONArray;
  c: TJSONObject;
  i: Integer;
  ms: Double;
  utc: Boolean;
  got: string;
begin
  arr := Section('format');
  for i := 0 to arr.Count - 1 do
  begin
    c := arr.Objects[i];
    FWhere := c.Strings['id'];
    ms := FromHex(c.Strings['ms']);
    utc := c.Booleans['utc'];
    { a local answer is the UTC wall clock: read on this machine's clock at
      the instant whose local wall says the same }
    if not utc and not (IsNan(ms) or IsInfinite(ms)) then ms := ms + LocalShift;
    got := TyFormatTime(ms, c.Strings['tpl'], utc);
    Inc(FCompared);
    if got <> c.Strings['out'] then
      Bad(Format('%s says "%s", upstream "%s"', [c.Strings['tpl'], got, c.Strings['out']]));
  end;
  Finish('format');
end;

{ ==================== the dictionary ==================== }

procedure TAdvChartTimeFormatOracleTest.TestEveryDictionaryAsUpstream;
var
  arr, want: TJSONArray;
  c, dict: TJSONObject;
  i, k: Integer;
  f: TTyTimeLabelFormatter;
  lu, uu: TTyTimeUnit;
  lst: TTyTimeTemplates;
  wantText: string;
begin
  arr := Section('dict');
  for i := 0 to arr.Count - 1 do
  begin
    c := arr.Objects[i];
    FWhere := c.Strings['id'];
    f := TyTimeLabelFormatterOf(c.Find('formatter'));
    Inc(FCompared);
    if c.Strings['kind'] = 'string' then
    begin
      if (f.Kind <> tfkString) or (f.Template <> c.Strings['template']) then
        Bad('not the string template');
      Continue;
    end;
    if f.Kind <> tfkDict then
    begin
      Bad('not a dictionary');
      Continue;
    end;
    if f.Dict.Highlight <> c.Booleans['highlight'] then Bad('highlight');
    dict := c.Objects['dict'];
    for lu := Low(TTyTimeUnit) to High(TTyTimeUnit) do
      for uu := lu downto Low(TTyTimeUnit) do
      begin
        want := dict.Objects[TyTimeUnitName(lu)].Arrays[TyTimeUnitName(uu)];
        lst := f.Dict.Lists[lu, uu];
        Inc(FCompared);
        if Length(lst.Texts) <> want.Count then
        begin
          Bad(Format('%s/%s: %d templates, upstream %d', [TyTimeUnitName(lu),
            TyTimeUnitName(uu), Length(lst.Texts), want.Count]));
          Continue;
        end;
        for k := 0 to want.Count - 1 do
        begin
          { a null in an author's array: String() 'null', and falsy }
          if want.Items[k].JSONType = jtNull then wantText := 'null'
          else wantText := want.Items[k].AsString;
          if lst.Texts[k] <> wantText then
            Bad(Format('%s/%s[%d] "%s", upstream "%s"', [TyTimeUnitName(lu),
              TyTimeUnitName(uu), k, lst.Texts[k], wantText]));
          if lst.Falsy[k] <> ((want.Items[k].JSONType = jtNull) or (wantText = '')) then
            Bad(Format('%s/%s[%d] falsy', [TyTimeUnitName(lu), TyTimeUnitName(uu), k]));
        end;
      end;
  end;
  Finish('dict');
end;

{ ==================== the charts ==================== }

procedure TAdvChartTimeFormatOracleTest.CheckPieces(ACase, ALabel: TJSONObject;
  const APlace: TTyAxisLabelPlacement);
var
  want: TJSONArray;
  w: TJSONObject;
  texts: array of Integer;
  i, k, n, r, wantWeight, gotWeight: Integer;
  colours: TStringList;
  sized: Boolean;
  fill: string;
begin
  want := ALabel.Arrays['pieces'];
  colours := TStringList.Create;
  try
    CollectColours(ACase.Objects['option'], colours);
    sized := Pos('"fontSize"', ACase.Objects['option'].AsJSON) > 0;
    { ONE PLAIN RUN where the port keeps the caption: upstream's single TSpan
      says the label's text in the label's own weight }
    if Length(APlace.Rt) = 0 then
    begin
      Inc(FCompared);
      { an empty label draws nothing at all }
      if APlace.Text = '' then
      begin
        if want.Count <> 0 then Bad('nothing drawn where upstream draws ' + want.AsJSON);
        Exit;
      end;
      if (want.Count <> 1) or (want.Objects[0].Strings['kind'] <> 'text')
        or (want.Objects[0].Strings['text'] <> APlace.Text)
        or not (want.Objects[0].Find('fontWeight').JSONType = jtNull) then
        Bad('a plain caption where upstream draws ' + want.AsJSON);
      Exit;
    end;
    { the text pieces, in order }
    texts := nil;
    for i := 0 to High(APlace.Rt) do
      if APlace.Rt[i].Kind = rpkText then
      begin
        SetLength(texts, Length(texts) + 1);
        texts[High(texts)] := i;
      end;
    n := 0;
    for k := 0 to want.Count - 1 do
    begin
      w := want.Objects[k];
      if w.Strings['kind'] = 'rect' then
      begin
        { a box: where it is and the author's fill }
        Inc(FCompared);
        i := -1;
        for r := 0 to High(APlace.Rt) do
          if (APlace.Rt[r].Kind = rpkRect) and APlace.Rt[r].Drawn then i := r;
        if i < 0 then
        begin
          Bad('no box piece');
          Continue;
        end;
        if (Abs(APlace.Rt[i].X - FromHex(w.Strings['x'])) > 1e-6)
          or (Abs(APlace.Rt[i].Y - FromHex(w.Strings['y'])) > 1e-6)
          or (Abs(APlace.Rt[i].W - FromHex(w.Strings['width'])) > 1e-6)
          or (Abs(APlace.Rt[i].H - FromHex(w.Strings['height'])) > 1e-6) then
          Bad(Format('box %g %g %g %g, upstream %s', [APlace.Rt[i].X, APlace.Rt[i].Y,
            APlace.Rt[i].W, APlace.Rt[i].H, w.Strings['rectText']]));
        if not APlace.Rt[i].HasFill or (APlace.Rt[i].Fill <> ColourOf(w.Strings['fill'])) then
          Bad('box fill');
        Continue;
      end;
      Inc(FCompared);
      if n > High(texts) then
      begin
        Bad('upstream has more text pieces: ' + w.AsJSON);
        Continue;
      end;
      i := texts[n];
      Inc(n);
      if APlace.Rt[i].Text <> w.Strings['text'] then
        Bad(Format('piece "%s", upstream "%s"', [APlace.Rt[i].Text, w.Strings['text']]));
      { THE WEIGHT as the port reads upstream's value; a null is the block's
        (the skin's 0 is normal) }
      gotWeight := APlace.Rt[i].FontWeight;
      if gotWeight = 0 then gotWeight := 400;
      if w.Find('fontWeight').JSONType = jtNull then
        wantWeight := FontStringWeight(w.Strings['font'])
      else
        wantWeight := TyFontWeightOf(w.Find('fontWeight'), 400);
      if gotWeight <> wantWeight then
        Bad(Format('"%s" weight %d, upstream %d', [w.Strings['text'], gotWeight, wantWeight]));
      { THE SIZE AND THE PLACE where the author wrote a size or none was
        needed: the skin's label size is upstream's 12 px }
      if sized and (w.Find('fontSize').JSONType = jtNumber)
        and (Abs(APlace.Rt[i].FontSizePx - w.Floats['fontSize']) > 1e-9) then
        Bad(Format('"%s" size %g, upstream %g', [w.Strings['text'],
          APlace.Rt[i].FontSizePx, w.Floats['fontSize']]));
      if (Abs(APlace.Rt[i].X - FromHex(w.Strings['x'])) > 1e-6)
        or (Abs(APlace.Rt[i].Y - FromHex(w.Strings['y'])) > 1e-6) then
        Bad(Format('"%s" at %g, %g, upstream %s, %s', [w.Strings['text'], APlace.Rt[i].X,
          APlace.Rt[i].Y, w.Strings['xText'], w.Strings['yText']]));
      { THE AUTHOR'S COLOURS: where upstream's piece wears one the port's must
        be that one; where it wears the theme's, the port's is the skin's }
      fill := LowerCase(w.Strings['fill']);
      if colours.IndexOf(fill) >= 0 then
      begin
        if not APlace.Rt[i].HasFill or (APlace.Rt[i].Fill <> ColourOf(fill)) then
          Bad(Format('"%s" not in the author''s %s', [w.Strings['text'], fill]));
      end
      else if APlace.Rt[i].HasFill then
        for r := 0 to colours.Count - 1 do
          if APlace.Rt[i].Fill = ColourOf(colours[r]) then
            Bad(Format('"%s" in the author''s %s where upstream''s is the theme''s',
              [w.Strings['text'], colours[r]]));
    end;
    Inc(FCompared);
    if n <> Length(texts) then
      Bad(Format('%d text pieces, upstream %d', [Length(texts), n]));
  finally
    colours.Free;
  end;
end;

procedure TAdvChartTimeFormatOracleTest.TestEveryTimeAxisDrawsWhatUpstreamDraws;
var
  arr, labels: TJSONArray;
  c, l: TJSONObject;
  i, k: Integer;
  gb: TTyGridBuild;
  ax: TTyAxis;
  spec: PTyAxisLayoutSpec;
  v: Double;
  ticks: TTyScaleTickArray;
begin
  arr := Section('charts');
  for i := 0 to arr.Count - 1 do
  begin
    c := arr.Objects[i];
    FWhere := c.Strings['id'];
    NewChart(c.Objects['option']);
    gb := FChart.Build.Grid(0);
    if c.Strings['axis'] = 'x' then ax := gb.XAxis(0) else ax := gb.YAxis(0);
    spec := gb.SpecFor(ax);
    ticks := ax.Scale.GetTicks;
    labels := c.Arrays['labels'];
    Inc(FCompared);
    if Length(spec^.Labels) <> labels.Count then
    begin
      Bad(Format('%d labels, upstream %d', [Length(spec^.Labels), labels.Count]));
      Continue;
    end;
    for k := 0 to labels.Count - 1 do
    begin
      l := labels.Objects[k];
      FWhere := c.Strings['id'] + '#' + IntToStr(k);
      { the instant: a zone-less string is this machine's local wall }
      v := FromHex(l.Strings['value']);
      if not c.Booleans['utc'] then v := v + LocalShift;
      Inc(FCompared);
      if spec^.TickValues[k] <> v then
        Bad(Format('tick %s, upstream %s', [FloatToStr(spec^.TickValues[k]), l.Strings['valueText']]));
      Inc(FCompared);
      if spec^.Placements[k].Text <> l.Strings['text'] then
        Bad(Format('says "%s", upstream "%s"', [spec^.Placements[k].Text, l.Strings['text']]));
      Inc(FCompared);
      if spec^.LabelLevel[k] <> l.Integers['level'] then
        Bad(Format('level %d, upstream %d', [spec^.LabelLevel[k], l.Integers['level']]));
      Inc(FCompared);
      if ticks[k].TimeUnit <> UnitOf(l.Strings['unit']) then
        Bad('unit, upstream ' + l.Strings['unit']);
      Inc(FCompared);
      if spec^.Placements[k].Shown <> l.Booleans['shown'] then
        Bad(Format('shown %s, upstream %s', [BoolToStr(spec^.Placements[k].Shown, True),
          BoolToStr(l.Booleans['shown'], True)]));
      if spec^.Placements[k].Shown and l.Booleans['shown'] then
        CheckPieces(c, l, spec^.Placements[k]);
    end;
  end;
  Finish('charts');
end;

{ ==================== the tooltip ==================== }

procedure TAdvChartTimeFormatOracleTest.TestTheTooltipFormatsTimeAsUpstream;
var
  arr, want: TJSONArray;
  c: TJSONObject;
  i, j, k: Integer;
  px: TJSONArray;
  block: TTyTooltipBlock;
  lines: TTyTooltipLineArray;
  ink: TTyTooltipInk;
  got, exp: string;
begin
  arr := Section('tooltip');
  for i := 0 to arr.Count - 1 do
  begin
    c := arr.Objects[i];
    FWhere := c.Strings['id'];
    NewChart(c.Objects['option']);
    px := c.Arrays['px'];
    FChart.Move(px.Integers[0], px.Integers[1]);
    FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
    Inc(FCompared);
    if not FChart.TooltipShown then
    begin
      Bad('no box');
      Continue;
    end;
    if c.Find('formatter').JSONType = jtString then
    begin
      { the formatter's text: time-formatted first under a time axis }
      Inc(FCompared);
      if FChart.FormatterText <> c.Strings['html'] then
        Bad(Format('says "%s", upstream "%s"', [FChart.FormatterText, c.Strings['html']]));
      Continue;
    end;
    if c.Strings['trigger'] = 'axis' then
    begin
      { the header: TimeScale.getLabel }
      Inc(FCompared);
      if FChart.TooltipShownWhich <> 'axis:' + c.Strings['header'] then
        Bad(Format('shows %s, upstream header %s', [FChart.TooltipShownWhich, c.Strings['header']]));
      Continue;
    end;
    { an item: the texts of the box, in order }
    block := FChart.ContentOf(FChart.TooltipShownDatum);
    try
      AssertNotNull(FWhere + ': content', block);
      ink := Default(TTyTooltipInk);
      ink.NameWeight := 400;
      ink.ValueWeight := 900;
      ink.MarkerSizeLogical := 10;
      lines := TyTooltipFlatten(block, ink);
    finally
      block.Free;
    end;
    got := '';
    for j := 0 to High(lines) do
      for k := 0 to High(lines[j].Runs) do
        if (lines[j].Runs[k].Kind <> ttrMarker) and (lines[j].Runs[k].Text <> '') then
          got := got + '[' + lines[j].Runs[k].Text + ']';
    exp := '';
    want := c.Arrays['texts'];
    for j := 0 to want.Count - 1 do exp := exp + '[' + want.Strings[j] + ']';
    Inc(FCompared);
    if got <> exp then Bad(Format('says %s, upstream %s', [got, exp]));
  end;
  Finish('tooltip');
end;

{ ==================== by hand ==================== }

function PrimaryPiece(const ASpec: TTyAxisLayoutSpec; out APiece: TTyRtPiece): Boolean;
var i, k: Integer;
begin
  Result := False;
  for i := 0 to High(ASpec.Placements) do
    if ASpec.Placements[i].Shown and (Pos('{primary|', ASpec.Placements[i].Text) = 1) then
      for k := 0 to High(ASpec.Placements[i].Rt) do
        if ASpec.Placements[i].Rt[k].Kind = rpkText then
        begin
          APiece := ASpec.Placements[i].Rt[k];
          Exit(True);
        end;
end;

const
  cDays = '{"animation":false,"useUTC":true,%s"xAxis":{"type":"time"%s},'
    + '"yAxis":{"type":"value"},"series":[{"type":"line","data":'
    + '[[1705708800000,1],[1707696000000,2]]}]}';

procedure TAdvChartTimeFormatOracleTest.TestThePrimaryTakesTheSkinsColourAndWeight;
var p: TTyRtPiece; o: TJSONData;
begin
  { UPSTREAM'S DEFAULT IS `rich.primary: { fontWeight: 'bold' }`; here the
    skin's primary label rule says the weight -- and, being the skin, the
    colour too, where nobody wrote one. A skin that paints its level markers
    red and black gets exactly that on the `{primary|Feb}` piece. }
  FWhere := 'skin';
  FCtl.StyleOverride :=
    'TyAdvChartAxisLabelPrimary { color: #FF0000; font-weight: 900; }';
  o := GetJSON(Format(cDays, ['', '']));
  try
    NewChart(o);
  finally
    o.Free;
  end;
  AssertTrue('a primary piece', PrimaryPiece(FChart.Build.Grid(0).SpecFor(
    FChart.Build.Grid(0).XAxis(0))^, p));
  AssertEquals('the skin''s weight', 900, p.FontWeight);
  AssertTrue('the skin''s colour', p.HasFill and (p.Fill = $FFFF0000));
  { and the author's rich.primary over it }
  o := GetJSON(Format(cDays, ['', ',"axisLabel":{"rich":{"primary":{"fontWeight":"normal"}}}']));
  try
    NewChart(o);
  finally
    o.Free;
  end;
  AssertTrue('a primary piece', PrimaryPiece(FChart.Build.Grid(0).SpecFor(
    FChart.Build.Grid(0).XAxis(0))^, p));
  AssertEquals('the author''s weight', 400, p.FontWeight);
  AssertTrue('the skin''s colour still', p.HasFill and (p.Fill = $FFFF0000));
end;

procedure TAdvChartTimeFormatOracleTest.TestAnAuthorsColourBeatsTheSkinsPrimary;
var p: TTyRtPiece; o: TJSONData;
begin
  { WHERE THE AUTHOR COLOURED THE LABEL the primary inherits it, as upstream's
    tag inherits the label's fill: the skin's primary colour is the stand-in
    for the theme's label colour and nothing more. The root textStyle's
    colour is a free text's rich colour and beats both. }
  FWhere := 'author';
  FCtl.StyleOverride :=
    'TyAdvChartAxisLabelPrimary { color: #FF0000; font-weight: 700; }';
  o := GetJSON(Format(cDays, ['', ',"axisLabel":{"color":"#336699"}']));
  try
    NewChart(o);
  finally
    o.Free;
  end;
  AssertTrue('a primary piece', PrimaryPiece(FChart.Build.Grid(0).SpecFor(
    FChart.Build.Grid(0).XAxis(0))^, p));
  AssertTrue('the label''s colour', p.HasFill and (p.Fill = $FF336699));
  o := GetJSON(Format(cDays, ['"textStyle":{"color":"#AA0000"},', '']));
  try
    NewChart(o);
  finally
    o.Free;
  end;
  AssertTrue('a primary piece', PrimaryPiece(FChart.Build.Grid(0).SpecFor(
    FChart.Build.Grid(0).XAxis(0))^, p));
  AssertTrue('the root colour', p.HasFill and (p.Fill = $FFAA0000));
  o := GetJSON(Format(cDays, ['', ',"axisLabel":{"color":"#336699","rich":{"primary":{"color":"#00AA00"}}}']));
  try
    NewChart(o);
  finally
    o.Free;
  end;
  AssertTrue('a primary piece', PrimaryPiece(FChart.Build.Grid(0).SpecFor(
    FChart.Build.Grid(0).XAxis(0))^, p));
  AssertTrue('the tag''s own colour', p.HasFill and (p.Fill = $FF00AA00));
end;

procedure TAdvChartTimeFormatOracleTest.TestUseUtcDecidesTheClock;
const
  { typed: an untyped real constant can land in a Single }
  cMs: Double = 1709276880000;  // 2024-03-01 07:08 UTC
var off: Double;
begin
  { THE SAME INSTANT ON TWO CLOCKS: useUTC reads the UTC wall, its absence the
    machine's. On a machine at UTC the two agree, so the local answer is
    asked at the instant whose local wall is that UTC wall -- the shift the
    fixture's local cases replay with -- and the UTC answer at the instant
    itself; each is wrong under the other clock unless the machine is at
    UTC. }
  off := GetLocalTimeOffset * 60000.0;
  AssertEquals('UTC', '2024-03-01 07:08', TyFormatTime(cMs, '{yyyy}-{MM}-{dd} {HH}:{mm}', True));
  AssertEquals('local', '2024-03-01 07:08',
    TyFormatTime(cMs + off, '{yyyy}-{MM}-{dd} {HH}:{mm}', False));
  if off <> 0 then
    AssertTrue('the clocks differ here',
      TyFormatTime(cMs, '{HH}:{mm}', True) <> TyFormatTime(cMs, '{HH}:{mm}', False));
end;

initialization
  RegisterTest(TAdvChartTimeFormatOracleTest);
end.
