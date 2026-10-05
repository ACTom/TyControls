unit test.advchart.convertjitter;
{$mode objfpc}{$H+}
{ THE COORDINATE CONVERSIONS, THE JITTER AND customValues, HELD TO UPSTREAM
  [Batch 110, C2].

  tools/advchart-oracle/convert-jitter.js runs the real ECharts 6.1 build in
  node (animation off, Math.random the port's xorshift32 from its seed,
  reset before every chart) and records:

    convert   per chart, thousands of probes: chart.convertToPixel /
              convertFromPixel / containPixel with a finder and a value as
              written -- every finder form, values of every JavaScript type,
              grid corners and just past them, round trips -- and what came
              back (nothing, a number, a point, a boolean, or the TypeError
              upstream raises on a null value), with the coordinate system
              that answered;
    jitter    every scatter item's layout after the jitter, and whether its
              symbol was drawn;
    custom    every axis' tick marks, split lines and split areas
              (getTicksCoords with each model) and its labels in the axis
              group: value, text, anchor, hidden.

  This replays it through the control, bit for bit: the probes through the
  typed API with the exact doubles the oracle wrote (and the JSON text API
  on the probes whose numbers print safely), the jitter as the centres of
  the drawn symbols, the axes through the grid's layout specs.

  THE MACHINE'S ZONE. The oracle runs at UTC. A calendar reads a date
  string on the local wall clock just as upstream does, so those agree in
  any zone; a calendar value given as a number, or as a string naming its
  own zone, lands on a zone-dependent day and is compared only at UTC -- and
  a calendar's time out of a pixel is upstream's moved by this machine's
  offset. On a time axis it is the other way round: a date string with no
  zone is the local one, compared only at UTC. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Paint, tyControls.AdvChart.Coord,
     tyControls.AdvChart.Builder, tyControls.AdvChart.Layout,
     tyControls.AdvChart.OptionMerge, tyControls.AdvChart.Graph,
     tyControls.AdvChart.Convert, tyControls.AdvChart.Jitter,
     tyControls.AdvanceChart;
type
  TCjProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  TAdvChartConvertJitterTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TCjProbe;
    FRoot: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared, FSkipped: Integer;
    FReport, FWhere: string;
    procedure Bad(const AWhat: string);
    procedure Same(const AWhat: string; AGot: Double; const AHex: string);
    procedure NewChart(AOption: TJSONObject);
    procedure Frame;
    function Cases: TJSONArray;
    procedure Finish(const AWhat: string; AMin: Integer);
    procedure CheckProbe(ACase, AProbe: TJSONObject; AText: Boolean);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEveryConversionIsUpstreams;
    procedure TestTheJsonTextFormsAnswerTheSame;
    procedure TestTheJitterPlacesWhereUpstreamDoes;
    procedure TestCustomValuesMakeUpstreamsTicksAndLabels;
    { beyond the fixture }
    procedure TestTheFinderReadsItsKeysAsUpstream;
    procedure TestTheJitterDrawsTheForceLayoutsNumbers;
    procedure TestTheAvoidingPlacementClimbsPastEveryCircle;
    procedure TestAConversionFollowsANewOptionBeforeAPaint;
    procedure TestTheJsonFormsPrintAsJsonPrints;
    procedure TestCustomLabelsLeaveACategoryAxisTicksAlone;
  end;

implementation

const
  cW = 600;
  cH = 400;

procedure TCjProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TCjProbe.List: TTyPaintList;
begin
  Result := SeriesList;
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

function HexOf(A: Double): string;
var q: QWord;
begin
  Move(A, q, SizeOf(q));
  Result := LowerCase(IntToHex(q, 16));
end;

function Txt(A: Double): string;
begin
  Result := FloatToStrF(A, ffGeneral, 17, 0, DefaultFormatSettings);
end;

function SameBits(A, B: Double): Boolean;
begin
  Result := (HexOf(A) = HexOf(B)) or (IsNan(A) and IsNan(B));
end;

{ within a printing's rounding: the same sign, then a relative 1e-9 }
function Near(A, B: Double): Boolean;
begin
  if SameBits(A, B) or (A = B) then Exit(True);
  if IsNan(A) or IsNan(B) or IsInfinite(A) or IsInfinite(B) then Exit(False);
  if (A < 0) <> (B < 0) then Exit(Abs(A - B) <= 1e-9);
  Result := Abs(A - B) <= 1e-9 * Max(1, Abs(B));
end;

{ the oracle's input: every number written as an object whose one key is
  "h", its hex }
function Decode(AData: TJSONData): TJSONData;
var
  o: TJSONObject;
  i: Integer;
begin
  case AData.JSONType of
    jtArray:
      begin
        Result := TJSONArray.Create;
        for i := 0 to AData.Count - 1 do
          TJSONArray(Result).Add(Decode(AData.Items[i]));
      end;
    jtObject:
      begin
        o := TJSONObject(AData);
        if (o.Count = 1) and (o.Names[0] = 'h') and (o.Items[0].JSONType = jtString) then
          Exit(TJSONFloatNumber.Create(FromHex(o.Items[0].AsString)));
        Result := TJSONObject.Create;
        for i := 0 to o.Count - 1 do
          TJSONObject(Result).Add(o.Names[i], Decode(o.Items[i]));
      end;
  else
    Result := AData.Clone;
  end;
end;

{ a date with no zone: the local wall clock }
function LocalDateText(const S: string): Boolean;
var p: Integer;
begin
  Result := False;
  if (Length(S) < 7) or not (S[1] in ['0'..'9']) or not (S[5] in ['-', '/']) then Exit;
  if UpCase(S[Length(S)]) = 'Z' then Exit;
  p := Length(S);
  while (p > 11) and not (S[p] in ['+', '-']) do Dec(p);
  Result := not ((p > 11) and (S[p] in ['+', '-']));
end;

function HasLocalDate(AData: TJSONData): Boolean;
var i: Integer;
begin
  Result := False;
  case AData.JSONType of
    jtString: Result := LocalDateText(AData.AsString);
    jtArray, jtObject:
      for i := 0 to AData.Count - 1 do
        if HasLocalDate(AData.Items[i]) then Exit(True);
  end;
end;

{ a number, or a string naming its zone (the oracle's `in`: a number is an
  object holding `h`) }
function HasZonedDate(AData: TJSONData): Boolean;
var
  i: Integer;
  s: string;
begin
  Result := False;
  case AData.JSONType of
    jtString:
      begin
        s := AData.AsString;
        Result := (Length(s) >= 7) and (s[1] in ['0'..'9']) and not LocalDateText(s);
      end;
    jtObject:
      if (AData.Count = 1) and (TJSONObject(AData).Names[0] = 'h') then Exit(True)
      else
        for i := 0 to AData.Count - 1 do
          if HasZonedDate(AData.Items[i]) then Exit(True);
    jtArray:
      for i := 0 to AData.Count - 1 do
        if HasZonedDate(AData.Items[i]) then Exit(True);
  end;
end;

{ the element a calendar reads its date from: the value, or the first
  element of an array }
function CalendarDateOf(AIn: TJSONData): TJSONData;
begin
  Result := AIn;
  if (AIn.JSONType = jtArray) and (AIn.Count > 0) then Result := AIn.Items[0];
end;

procedure TAdvChartConvertJitterTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath('advchart-convert-jitter.json'));
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FBad := 0;
  FCompared := 0;
  FSkipped := 0;
  FReport := '';
end;

procedure TAdvChartConvertJitterTest.TearDown;
begin
  FChart.Free;
  FChart := nil;
  FRoot.Free;
  FBmp.Free;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

procedure TAdvChartConvertJitterTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 12000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TAdvChartConvertJitterTest.Same(const AWhat: string; AGot: Double;
  const AHex: string);
begin
  Inc(FCompared);
  if not SameBits(AGot, FromHex(AHex)) then
    Bad(Format('%s %s, upstream %s', [AWhat, Txt(AGot), Txt(FromHex(AHex))]));
end;

procedure TAdvChartConvertJitterTest.Finish(const AWhat: string; AMin: Integer);
begin
  AssertTrue(Format('%s: only %d compared', [AWhat, FCompared]), FCompared >= AMin);
  AssertEquals(Format('%s: %d of %d comparisons differ (%d zone-skipped):%s',
    [AWhat, FBad, FCompared, FSkipped, FReport]), 0, FBad);
end;

procedure TAdvChartConvertJitterTest.NewChart(AOption: TJSONObject);
begin
  FChart.Free;
  FChart := TCjProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Option := AOption.AsJSON;
  FChart.SetBounds(0, 0, cW, cH);
  Frame;
end;

procedure TAdvChartConvertJitterTest.Frame;
begin
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

function TAdvChartConvertJitterTest.Cases: TJSONArray;
begin
  Result := TJSONObject(FRoot).Arrays['cases'];
end;

function KindName(AKind: TTyConvertKind): string;
begin
  case AKind of
    cvkNumber: Result := 'num';
    cvkArray: Result := 'arr';
    cvkError: Result := 'throw';
  else
    Result := 'none';
  end;
end;

{ ==================== the conversions ==================== }

procedure TAdvChartConvertJitterTest.CheckProbe(ACase, AProbe: TJSONObject;
  AText: Boolean);
var
  op, k, by, s: string;
  finder, value: TJSONData;
  outNode: TJSONObject;
  r: TTyConvertResult;
  got: Boolean;
  i: Integer;
  shift: Double;
  arr: TJSONArray;
  parsed: TJSONData;
begin
  op := AProbe.Strings['op'];
  outNode := AProbe.Objects['out'];
  k := outNode.Strings['k'];
  by := '';
  if AProbe.Find('by') <> nil then by := AProbe.Strings['by'];
  FWhere := ACase.Strings['id'] + ' ' + op + ' ' + AProbe.Objects['finder'].Strings['text']
    + ' ' + AProbe.Objects['value'].Strings['text'];
  { THE ZONE: see the unit header }
  shift := 0;
  if GetLocalTimeOffset <> 0 then
  begin
    if (by = 'calendar') and (op = 'to')
      and HasZonedDate(CalendarDateOf(AProbe.Objects['value'].Find('in'))) then
    begin
      Inc(FSkipped);
      Exit;
    end;
    if (by = 'grid') and HasLocalDate(AProbe.Objects['value'].Find('in')) then
    begin
      Inc(FSkipped);
      Exit;
    end;
    if (by = 'calendar') and (op = 'from') then shift := GetLocalTimeOffset * 60000.0;
  end;
  if AText then
  begin
    { the JSON text API, against what the typed one is held to }
    if op = 'contain' then
    begin
      got := FChart.ContainPixel(AProbe.Objects['finder'].Strings['text'],
        AProbe.Objects['value'].Strings['text']);
      Inc(FCompared);
      if got <> outNode.Booleans['v'] then
        Bad(Format('contains %s, upstream %s', [BoolToStr(got, True),
          BoolToStr(outNode.Booleans['v'], True)]));
      Exit;
    end;
    if op = 'to' then
      s := FChart.ConvertToPixel(AProbe.Objects['finder'].Strings['text'],
        AProbe.Objects['value'].Strings['text'])
    else
      s := FChart.ConvertFromPixel(AProbe.Objects['finder'].Strings['text'],
        AProbe.Objects['value'].Strings['text']);
    Inc(FCompared);
    if (k = 'none') or (k = 'throw') then
    begin
      if s <> '' then Bad(Format('JSON %s, upstream %s', [s, k]));
      Exit;
    end;
    parsed := nil;
    try
      try
        parsed := GetJSON(s);
      except
        parsed := nil;
      end;
      if parsed = nil then
      begin
        Bad('JSON "' + s + '" does not parse');
        Exit;
      end;
      if k = 'num' then
      begin
        if parsed.JSONType = jtNull then
        begin
          if not IsNan(FromHex(outNode.Strings['v'])) and not IsInfinite(FromHex(outNode.Strings['v'])) then
            Bad('JSON null, upstream ' + Txt(FromHex(outNode.Strings['v'])));
        end
        else if (parsed.JSONType <> jtNumber)
          or not Near(parsed.AsFloat - shift, FromHex(outNode.Strings['v'])) then
          Bad('JSON ' + s + ', upstream ' + Txt(FromHex(outNode.Strings['v'])));
      end
      else
      begin
        arr := outNode.Arrays['v'];
        if (parsed.JSONType <> jtArray) or (parsed.Count <> arr.Count) then
          Bad('JSON ' + s + ' is not a pair')
        else
          for i := 0 to arr.Count - 1 do
            if parsed.Items[i].JSONType = jtNull then
            begin
              if not IsNan(FromHex(arr.Strings[i])) and not IsInfinite(FromHex(arr.Strings[i])) then
                Bad(Format('JSON [%d] null, upstream %s', [i, Txt(FromHex(arr.Strings[i]))]));
            end
            else if not Near(parsed.Items[i].AsFloat, FromHex(arr.Strings[i])) then
              Bad(Format('JSON [%d] %s, upstream %s', [i, Txt(parsed.Items[i].AsFloat),
                Txt(FromHex(arr.Strings[i]))]));
      end;
    finally
      parsed.Free;
    end;
    Exit;
  end;
  finder := Decode(AProbe.Objects['finder'].Find('in'));
  value := Decode(AProbe.Objects['value'].Find('in'));
  try
    if op = 'contain' then
    begin
      got := FChart.ContainPixelData(finder, value);
      Inc(FCompared);
      if k = 'throw' then
      begin
        if got then Bad('contains, upstream throws');
      end
      else if got <> outNode.Booleans['v'] then
        Bad(Format('contains %s, upstream %s', [BoolToStr(got, True),
          BoolToStr(outNode.Booleans['v'], True)]));
      Exit;
    end;
    if op = 'to' then r := FChart.ConvertToPixelData(finder, value)
    else r := FChart.ConvertFromPixelData(finder, value);
    Inc(FCompared);
    if KindName(r.Kind) <> k then
    begin
      Bad(Format('%s here, upstream %s', [KindName(r.Kind), k]));
      Exit;
    end;
    if k = 'num' then
      Same('the number', r.Values[0] - shift, outNode.Strings['v'])
    else if k = 'arr' then
    begin
      arr := outNode.Arrays['v'];
      if Length(r.Values) <> arr.Count then
        Bad(Format('%d numbers, upstream %d', [Length(r.Values), arr.Count]))
      else
        for i := 0 to arr.Count - 1 do
          Same(Format('[%d]', [i]), r.Values[i], arr.Strings[i]);
    end;
  finally
    finder.Free;
    value.Free;
  end;
end;

procedure TAdvChartConvertJitterTest.TestEveryConversionIsUpstreams;
var
  c, p: Integer;
  cs: TJSONObject;
  probes: TJSONArray;
  kinds: array[0..4] of Integer;
  k: string;
begin
  FillChar(kinds, SizeOf(kinds), 0);
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    if cs.Strings['kind'] <> 'convert' then Continue;
    FWhere := cs.Strings['id'];
    NewChart(cs.Objects['option']);
    probes := cs.Arrays['probes'];
    for p := 0 to probes.Count - 1 do
    begin
      CheckProbe(cs, probes.Objects[p], False);
      k := probes.Objects[p].Objects['out'].Strings['k'];
      if k = 'none' then Inc(kinds[0])
      else if k = 'num' then Inc(kinds[1])
      else if k = 'arr' then Inc(kinds[2])
      else if k = 'bool' then Inc(kinds[3])
      else Inc(kinds[4]);
    end;
  end;
  AssertTrue('every kind of answer is in the fixture', (kinds[0] > 50) and (kinds[1] > 200)
    and (kinds[2] > 500) and (kinds[3] > 500) and (kinds[4] > 5));
  Finish('conversions', 3000);
end;

procedure TAdvChartConvertJitterTest.TestTheJsonTextFormsAnswerTheSame;
var
  c, p: Integer;
  cs, pr: TJSONObject;
  probes: TJSONArray;
begin
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    if cs.Strings['kind'] <> 'convert' then Continue;
    FWhere := cs.Strings['id'];
    NewChart(cs.Objects['option']);
    probes := cs.Arrays['probes'];
    for p := 0 to probes.Count - 1 do
    begin
      pr := probes.Objects[p];
      if not pr.Objects['value'].Booleans['textSafe'] then Continue;
      if not pr.Objects['finder'].Booleans['textSafe'] then Continue;
      CheckProbe(cs, pr, True);
    end;
  end;
  Finish('the JSON text forms', 2000);
end;

{ ==================== the jitter ==================== }

procedure TAdvChartConvertJitterTest.TestTheJitterPlacesWhereUpstreamDoes;
var
  c, s, i, e, si, raw, n, moved: Integer;
  cs, ser, item: TJSONObject;
  items: TJSONArray;
  lst: TTyPaintList;
  el, body: TTyChartElement;
  drawn: Boolean;
begin
  moved := 0;
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    if cs.Strings['kind'] <> 'jitter' then Continue;
    NewChart(cs.Objects['option']);
    { AND PAINTED AGAIN: every pass starts from the seed and no points, so
      a repaint is upstream's first render still }
    Frame;
    lst := FChart.List;
    for s := 0 to cs.Arrays['series'].Count - 1 do
    begin
      ser := cs.Arrays['series'].Objects[s];
      si := ser.Integers['seriesIndex'];
      items := ser.Arrays['items'];
      for i := 0 to items.Count - 1 do
      begin
        item := items.Objects[i];
        raw := item.Integers['i'];
        FWhere := Format('%s series %d item %d', [cs.Strings['id'], si, raw]);
        n := 0;
        body := Default(TTyChartElement);
        if lst <> nil then
          for e := 0 to lst.Count - 1 do
          begin
            el := lst.Element(e);
            if (el.Datum.Kind <> ctkSeries) or el.Datum.IsEdge
              or (el.Datum.SeriesIndex <> si) or (el.Datum.RawDataIndex <> raw) then Continue;
            if el.Caption.FontSizeLogical > 0 then Continue;
            if el.Anim.Role = carRipple then Continue;
            body := el;
            Inc(n);
          end;
        drawn := item.Booleans['drawn'];
        Inc(FCompared);
        if drawn <> (n > 0) then
        begin
          Bad(Format('drawn %s upstream, %d elements here', [BoolToStr(drawn, True), n]));
          Continue;
        end;
        if not drawn then Continue;
        if not (body.Shape.Kind in [cskCircle, cskEllipse]) then
        begin
          Bad('not a circle');
          Continue;
        end;
        Same('x', body.Shape.CX, item.Arrays['layout'].Strings[0]);
        Same('y', body.Shape.CY, item.Arrays['layout'].Strings[1]);
        if Frac(body.Shape.CX) <> 0 then Inc(moved);
      end;
    end;
  end;
  AssertTrue(Format('enough jittered points (%d)', [moved]), moved >= 100);
  Finish('the jitter', 600);
end;

{ ==================== customValues ==================== }

function LabelAt(ASpec: PTyAxisLayoutSpec; ATick: Double): Integer;
var i: Integer;
begin
  for i := 0 to High(ASpec^.TickValues) do
    if ASpec^.TickValues[i] = ATick then Exit(i);
  Result := -1;
end;

procedure TAdvChartConvertJitterTest.TestCustomValuesMakeUpstreamsTicksAndLabels;
var
  c, a, q, p, labels, hidden: Integer;
  cs, ax, rec, lab: TJSONObject;
  axis: TTyAxis;
  spec: PTyAxisLayoutSpec;
  vals, coords, drawn, labs: TJSONArray;
  tick: Double;

  procedure Marks(const AName: string; const AMarks: TTyAxisMarkArray;
    ARec: TJSONObject; ADrawn: Boolean);
  var k: Integer;
  begin
    vals := ARec.Arrays['values'];
    coords := ARec.Arrays['coords'];
    Inc(FCompared);
    if Length(AMarks) <> vals.Count then
    begin
      Bad(Format('%s: %d here, upstream %d', [AName, Length(AMarks), vals.Count]));
      Exit;
    end;
    for k := 0 to vals.Count - 1 do
    begin
      Same(Format('%s %d value', [AName, k]), AMarks[k].Value, vals.Strings[k]);
      Same(Format('%s %d at', [AName, k]), AMarks[k].Coord, coords.Strings[k]);
      if ADrawn then
      begin
        drawn := ARec.Arrays['drawn'];
        Inc(FCompared);
        if AMarks[k].Drawn <> drawn.Booleans[k] then
          Bad(Format('%s %d drawn %s, upstream %s', [AName, k,
            BoolToStr(AMarks[k].Drawn, True), BoolToStr(drawn.Booleans[k], True)]));
      end;
    end;
  end;

begin
  labels := 0;
  hidden := 0;
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    if cs.Strings['kind'] <> 'custom' then Continue;
    NewChart(cs.Objects['option']);
    for a := 0 to cs.Arrays['axes'].Count - 1 do
    begin
      ax := cs.Arrays['axes'].Objects[a];
      FWhere := Format('%s %s%d', [cs.Strings['id'], ax.Strings['dim'], ax.Integers['index']]);
      axis := FChart.Build.Axis(ax.Strings['dim'] + 'Axis', ax.Integers['index']);
      if axis = nil then
      begin
        Bad('no axis');
        Continue;
      end;
      spec := FChart.Build.Grid(0).SpecFor(axis);
      if spec = nil then
      begin
        Bad('no spec');
        Continue;
      end;
      rec := ax.Objects['ticks'];
      Marks('tick', spec^.TickMarks, rec, True);
      Marks('split line', spec^.SplitLineMarks, ax.Objects['splitLines'], True);
      Marks('split area edge', spec^.SplitAreaMarks, ax.Objects['splitAreas'], False);
      { the labels, matched by tick value }
      labs := ax.Arrays['labels'];
      q := 0;
      for p := 0 to High(spec^.Placements) do
        if spec^.Placements[p].Built then Inc(q);
      Inc(FCompared);
      if q <> labs.Count then
        Bad(Format('%d labels built here, upstream %d', [q, labs.Count]));
      for q := 0 to labs.Count - 1 do
      begin
        lab := labs.Objects[q];
        tick := FromHex(lab.Strings['tick']);
        p := LabelAt(spec, tick);
        if (p < 0) or (p > High(spec^.Placements)) then
        begin
          Bad('no label for ' + Txt(tick));
          Continue;
        end;
        Inc(labels);
        Inc(FCompared);
        if spec^.Labels[p] <> lab.Strings['text'] then
          Bad(Format('label %s says "%s", upstream "%s"', [Txt(tick), spec^.Labels[p],
            lab.Strings['text']]));
        Same('label x ' + Txt(tick), spec^.Placements[p].X, lab.Strings['x']);
        Same('label y ' + Txt(tick), spec^.Placements[p].Y, lab.Strings['y']);
        Inc(FCompared);
        if lab.Booleans['hidden'] then Inc(hidden);
        if spec^.Placements[p].Shown = lab.Booleans['hidden'] then
          Bad(Format('label %s hidden %s upstream', [Txt(tick),
            BoolToStr(lab.Booleans['hidden'], True)]));
      end;
    end;
  end;
  AssertTrue(Format('enough labels (%d)', [labels]), labels >= 50);
  AssertTrue(Format('some hidden (%d)', [hidden]), hidden >= 2);
  Finish('customValues', 400);
end;

{ ==================== beyond the fixture ==================== }

procedure TAdvChartConvertJitterTest.TestTheFinderReadsItsKeysAsUpstream;
var
  keys: TTyOptionKeys;
  d: TJSONData;

  function Models(const AFinderJson, AMainType: string): string;
  var
    d: TJSONData;
    pf: TTyParsedFinder;
    m: TTyIntegerArray;
    i: Integer;
  begin
    d := GetJSON(AFinderJson);
    try
      pf := TyParseFinder(d, keys);
    finally
      d.Free;
    end;
    m := TyFinderModels(pf, AMainType);
    Result := '';
    for i := 0 to High(m) do
    begin
      if i > 0 then Result := Result + ',';
      Result := Result + IntToStr(m[i]);
    end;
  end;

begin
  { series 0 'a'/'A', 1 a hole, 2 '5'/'B', 3 'c'/'C'; an xAxisId main type }
  SetLength(keys, 2);
  keys[0].MainType := 'series';
  SetLength(keys[0].Items, 4);
  keys[0].Items[0].Exists := True;
  keys[0].Items[0].Id := 'a';
  keys[0].Items[0].Name := 'A';
  keys[0].Items[1].Exists := False;
  keys[0].Items[2].Exists := True;
  keys[0].Items[2].Id := '5';
  keys[0].Items[2].Name := 'B';
  keys[0].Items[3].Exists := True;
  keys[0].Items[3].Id := 'c';
  keys[0].Items[3].Name := 'C';
  keys[1].MainType := 'xAxisId';
  SetLength(keys[1].Items, 1);
  keys[1].Items[0].Exists := True;
  AssertEquals('a string is its first', '0', Models('"series"', 'series'));
  AssertEquals('a list keeps its order and its repeats', '3,0,3', Models('{"seriesIndex":[3,0,3]}', 'series'));
  AssertEquals('a hole is nothing', '', Models('{"seriesIndex":1}', 'series'));
  AssertEquals('''all'' skips the hole', '0,2,3', Models('{"seriesIndex":"all"}', 'series'));
  AssertEquals('''2'' is a property key', '2', Models('{"seriesIndex":"2"}', 'series'));
  AssertEquals('''02'' is not', '', Models('{"seriesIndex":"02"}', 'series'));
  AssertEquals('[[3]] prints as 3', '3', Models('{"seriesIndex":[[3]]}', 'series'));
  AssertEquals('2.5 is no key', '', Models('{"seriesIndex":2.5}', 'series'));
  AssertEquals('-0 prints as 0', '0', Models('{"seriesIndex":-0}', 'series'));
  AssertEquals('''none''', '', Models('{"seriesIndex":"none"}', 'series'));
  AssertEquals('false', '', Models('{"seriesIndex":false}', 'series'));
  AssertEquals('true is no key', '', Models('{"seriesIndex":true}', 'series'));
  AssertEquals('null is nothing given', '', Models('{"seriesIndex":null}', 'series'));
  AssertEquals('index over id', '0', Models('{"seriesId":"c","seriesIndex":0}', 'series'));
  AssertEquals('null index: the id', '3', Models('{"seriesIndex":null,"seriesId":"c"}', 'series'));
  AssertEquals('a number id prints', '2', Models('{"seriesId":5}', 'series'));
  AssertEquals('a number in an id list never matches', '', Models('{"seriesId":[5]}', 'series'));
  AssertEquals('a string in an id list does', '2', Models('{"seriesId":["5","zz"]}', 'series'));
  AssertEquals('the list is matched in model order', '0,3', Models('{"seriesName":["C","A"]}', 'series'));
  AssertEquals('id over name', '3', Models('{"seriesName":"A","seriesId":"c"}', 'series'));
  AssertEquals('the longest main type: xAxisId + Index', '0', Models('{"xAxisIdIndex":0}', 'xAxisId'));
  AssertEquals('xAxisIdIndex is not an xAxis query', '', Models('{"xAxisIdIndex":0}', 'xAxis'));
  AssertEquals('a lower-case suffix is no key', '', Models('{"seriesindex":0}', 'series'));
  AssertEquals('a key with a dash is no key', '', Models('{"se-riesIndex":0}', 'se-ries'));
  d := GetJSON('{"dataIndex":2}');
  try
    AssertTrue('dataIndex is kept aside', TyParseFinder(d, keys).HasDataIndex);
  finally
    d.Free;
  end;
end;

procedure TAdvChartConvertJitterTest.TestTheJitterDrawsTheForceLayoutsNumbers;
var
  a, b: LongWord;
  i: Integer;
  pass: TTyJitterPass;
begin
  { the oracle's seed and generator are the force layout's }
  AssertEquals('the seed', TyGraphForceSeed(0), TyJitterSeed);
  a := TyJitterSeed;
  b := TyGraphForceSeed(0);
  for i := 1 to 1000 do
    AssertTrue('draw ' + IntToStr(i), TyJitterRandom(a) = TyGraphRandom(b));
  { and a pass starts from it again }
  pass := TTyJitterPass.Create;
  try
    pass.Random;
    pass.Random;
    AssertTrue('drawn', pass.State <> TyJitterSeed);
    pass.Reset;
    AssertEquals('a reset pass starts at the seed', TyJitterSeed, pass.State);
  finally
    pass.Free;
  end;
end;

procedure TAdvChartConvertJitterTest.TestTheAvoidingPlacementClimbsPastEveryCircle;
var
  items: array of TTyJitterItem;
  y, r: Double;
begin
  { two circles of radius 5 stacked at float 0 and 9, a third point of
    radius 5 at fixed 0, float 0, margin 2: upward it clears the first
    (0 + 12 = 12), then meets the second (9 + 12 = 21) and starts over }
  SetLength(items, 2);
  items[0].Fixed := 0;
  items[0].Float := 0;
  items[0].R := 5;
  items[1].Fixed := 0;
  items[1].Float := 9;
  items[1].R := 5;
  y := TyJitterPlace(items, 2, 0, 0, 5, 100, 2, 1);
  AssertEquals('up past both', 21, y, 0);
  y := TyJitterPlace(items, 2, 0, 0, 5, 100, 2, -1);
  AssertEquals('down past the first', -12, y, 0);
  { off to the side by 3: sqrt(12^2 - 3^2) above each }
  r := Sqrt(144 - 9);
  y := TyJitterPlace(items, 2, 3, 0, 5, 100, 2, 1);
  AssertEquals('beside', 9 + r, y, 0);
  { half the jitter is the limit: past it, the largest Double }
  y := TyJitterPlace(items, 2, 0, 0, 5, 30, 2, 1);
  AssertEquals('gives up', MaxDouble, y, 0);
  { AND FROM THE TOP AGAIN after every move: a later circle pushes the
    point back onto an earlier one it had cleared }
  items[0].Fixed := 0;
  items[0].Float := 20;
  items[1].Fixed := 0;
  items[1].Float := 0;
  y := TyJitterPlace(items, 2, 0, 0, 5, 100, 2, 1);
  AssertEquals('past the second, then past the first again', 32, y, 0);
  { a not-a-number neighbour meets nothing }
  items[0].Fixed := NaN;
  y := TyJitterPlace(items, 1, 0, 0, 5, 100, 2, 1);
  AssertEquals('NaN fixed: untouched', 0, y, 0);
end;

procedure TAdvChartConvertJitterTest.TestAConversionFollowsANewOptionBeforeAPaint;
var r: TTyConvertResult;
begin
  FChart := TCjProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, cW, cH);
  FChart.Option := '{"animation":false,"grid":{"left":0,"right":0,"top":0,"bottom":0,'
    + '"outerBoundsMode":"none"},"xAxis":{"type":"value","min":0,"max":10},'
    + '"yAxis":{"type":"value","min":0,"max":10},"series":[{"type":"scatter","data":[[1,1]]}]}';
  r := FChart.ConvertToPixel('grid', [5, 5]);
  AssertTrue('never rendered: nothing', r.Kind = cvkNone);
  Frame;
  r := FChart.ConvertToPixel('grid', [5, 5]);
  AssertTrue('rendered: a point', r.Kind = cvkArray);
  AssertEquals('x', 300, r.Values[0], 0);
  AssertEquals('y', 200, r.Values[1], 0);
  FChart.Option := '{"animation":false,"grid":{"left":0,"right":0,"top":0,"bottom":0,'
    + '"outerBoundsMode":"none"},"xAxis":{"type":"value","min":0,"max":20},'
    + '"yAxis":{"type":"value","min":0,"max":10},"series":[{"type":"scatter","data":[[1,1]]}]}';
  r := FChart.ConvertToPixel('grid', [5, 5]);
  AssertEquals('the new option, before any paint', 150, r.Values[0], 0);
  AssertEquals('the pixel back', 10, FChart.ConvertFromPixel('xAxis', 300).Values[0], 0);
  AssertTrue('the plot contains its centre', FChart.ContainPixel('grid', 300, 200));
  AssertFalse('and not a point past it', FChart.ContainPixel('grid', 600.5, 200));
end;

procedure TAdvChartConvertJitterTest.TestTheJsonFormsPrintAsJsonPrints;
var fd, vd: TJSONData;
begin
  FChart := TCjProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, cW, cH);
  FChart.Option := '{"animation":false,"grid":{"left":0,"right":0,"top":0,"bottom":0,'
    + '"outerBoundsMode":"none"},"xAxis":{"type":"category","data":["a","b"]},'
    + '"yAxis":{"type":"value","min":0,"max":10},"series":[{"type":"bar","data":[1,2]}]}';
  Frame;
  AssertEquals('a pair', '[150,200]', FChart.ConvertToPixel('{"seriesIndex":0}', '["a",5]'));
  AssertEquals('a bare word is a main type', '[450,0]', FChart.ConvertToPixel('series', '["b",10]'));
  AssertEquals('a coordinate that is not a number prints null', '[null,200]',
    FChart.ConvertToPixel('"grid"', '["z",5]'));
  AssertEquals('one axis: a number', '450', FChart.ConvertToPixel('{"xAxisIndex":0}', '"b"'));
  AssertEquals('nothing answered', '', FChart.ConvertToPixel('{"seriesIndex":7}', '[1,2]'));
  AssertEquals('upstream throws on null', '', FChart.ConvertToPixel('"grid"', 'null'));
  fd := TJSONString.Create('grid');
  vd := TJSONNull.Create;
  try
    AssertTrue('the typed form says it threw',
      FChart.ConvertToPixelData(fd, vd).Kind = cvkError);
  finally
    fd.Free;
    vd.Free;
  end;
  AssertEquals('the pixel back', '1', FChart.ConvertFromPixel('"xAxis"', '450'));
  AssertEquals('text that is no JSON is no value', '', FChart.ConvertToPixel('"grid"', '[1,'));
  AssertTrue('contains', FChart.ContainPixel('"grid"', '[10,10]'));
  AssertFalse('an axis contains nothing', FChart.ContainPixel('{"xAxisIndex":0}', '[10,10]'));
end;

{ upstream's ticks on a category axis walk makeCategoryLabelsActually -- the
  auto interval of the axis' OWN labels -- whatever axisLabel.customValues
  says; the fixture writes the interval out (an auto one is measured in a
  font the port does not share), so this holds the measured path to the
  same chart without the custom labels }
procedure TAdvChartConvertJitterTest.TestCustomLabelsLeaveACategoryAxisTicksAlone;
const
  { the grid shrinks for the labels: the category's own coordinates have to
    be taken again on the final rect }
  cBase = '{"animation":false,"grid":{"containLabel":true},'
    + '"xAxis":{"type":"category","splitLine":{"show":true},'
    + '"data":[%s]%s},"yAxis":{"type":"value"},'
    + '"series":[{"type":"line","data":[%s]}]}';
var
  cats, vals: string;
  i: Integer;
  plain, custom: TTyAxisMarkArray;
  plainLines, customLines: TTyAxisMarkArray;
  plainStep, customStep: Integer;
  spec: PTyAxisLayoutSpec;

  procedure Take(const AExtra: string; out AMarks, ALines: TTyAxisMarkArray;
    out AStep: Integer);
  begin
    FChart.Free;
    FChart := TCjProbe.Create(FForm);
    FChart.Parent := FForm;
    FChart.Controller := FCtl;
    FChart.SetBounds(0, 0, cW, cH);
    FChart.Option := Format(cBase, [cats, AExtra, vals]);
    Frame;
    spec := FChart.Build.Grid(0).SpecFor(FChart.Build.Axis('xAxis', 0));
    AMarks := Copy(spec^.TickMarks);
    ALines := Copy(spec^.SplitLineMarks);
    AStep := spec^.LabelStep;
  end;

begin
  cats := '';
  vals := '';
  for i := 0 to 59 do
  begin
    if i > 0 then
    begin
      cats := cats + ',';
      vals := vals + ',';
    end;
    cats := cats + '"category ' + IntToStr(i) + '"';
    vals := vals + IntToStr(i * 100000);
  end;
  Take('', plain, plainLines, plainStep);
  Take(',"axisLabel":{"customValues":[0,10,33,59]}', custom, customLines, customStep);
  AssertTrue('the plain axis is thinned', Length(plain) < 30);
  AssertEquals('as many ticks', Length(plain), Length(custom));
  for i := 0 to High(plain) do
  begin
    AssertEquals('tick ' + IntToStr(i), plain[i].Value, custom[i].Value, 0);
    AssertEquals('tick at ' + IntToStr(i), plain[i].Coord, custom[i].Coord, 0);
  end;
  AssertEquals('as many split lines', Length(plainLines), Length(customLines));
  AssertEquals('the same stride for the line symbols', plainStep, customStep);
  AssertEquals('four labels built', 4, Length(spec^.Labels));
  { the category's own coordinates, which its interval is measured over,
    are the final rect's: the grid shrank for the labels after they were
    first taken }
  AssertEquals('the categories kept', 60, Length(spec^.CatLocalCoords));
  for i := 0 to High(spec^.CatLocalCoords) do
    AssertEquals('category ' + IntToStr(i) + ' on the final rect',
      FChart.Build.Axis('xAxis', 0).DataToLocal(spec^.CatTickValues[i]),
      spec^.CatLocalCoords[i], 0);
end;

initialization
  RegisterTest(TAdvChartConvertJitterTest);
end.
