unit test.advchart.dataedge;
{$mode objfpc}{$H+}
{ The data edges the port read its own way -- held to upstream [R2-G].

  tools/advchart-oracle/data-edge.js runs ECharts 6.1 at 600 x 400 and
  records:
    tree       completeTreeValue's JavaScript: per data index the store
               value, the raw value a label's {c} prints, the label, and the
               sector or the treemap rect;
    vmdim      a visualMap on a column no axis reads: whether each item is
               drawn and its fill;
    intdim     a column declared 'int': the axis' columns as written, an
               off-axis one an Int32Array (through the visualMap's fill);
    timeinf    +-Infinity on a time dimension: kept, the axis blank;
    logbase    `logBase || 10`: the y extent, ticks, labels and points;
    calmargin  calendar label margins written as strings: each label's
               text, alignment and where its span's middle lands;
    tz         three zones with history (Shanghai, Berlin, New York), each
               run in its own process: the zone's offset changes, and what a
               time axis and a calendar read from local date strings. The
               test puts the recorded zone in TyLocalOffsetHook. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.FontUnits,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Option,
     tyControls.AdvanceChart.Paint, tyControls.AdvanceChart.Shape,
     tyControls.AdvanceChart.Data, tyControls.AdvanceChart.Scale,
     tyControls.AdvanceChart.Coord, tyControls.AdvanceChart.Layout,
     tyControls.AdvanceChart.Builder, tyControls.AdvanceChart.Sunburst,
     tyControls.AdvanceChart.Treemap, tyControls.AdvanceChart.Calendar,
     tyControls.AdvanceChart, tyControls.StrConsts,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  { a calendar label one zrender line high: the font size, ten px a
    character (the widths do not enter where the middle is) }
  TDeCalMeasurer = class(TInterfacedObject, ITyTextMeasurer)
  public
    procedure MeasureLine(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
    function WrapToWidth(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
  end;

  TAdvChartDataEdgeOracleTest = class(TTestCase)
  private
    FRoot, FTable: TJSONData;
    FOpt: TTyChartOption;
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TCatProbe;
    FBmp: TBGRABitmap;
    FBad, FCompared: Integer;
    FReport, FName: string;
    FSavedSource: TTyDateTimeNameSource;
    procedure Miss(const AWhat: string);
    procedure SameH(const AWhat: string; AGot: Double; AWant: TJSONData);
    procedure Verdict(AMinimum: Integer);
    function Cases(const AGroup: string): TJSONArray;
    function OptionTextOf(ACase: TJSONObject): string;
    procedure Draw(ACase: TJSONObject);
    function ItemElement(ASeries, AIndex: Integer): Integer;
    procedure CheckItems(ACase: TJSONObject; AFills: Boolean);
    procedure UseZone(const AZone: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTreeValuesCompleteAsJavaScriptAddsThem;
    procedure TestAVisualMapReadsAColumnNoAxisReadsAsUpstream;
    procedure TestAnIntColumnOffTheAxesIsAnInt32Array;
    procedure TestAnInfiniteTimeIsKeptAndBlanksTheAxis;
    procedure TestTheLogBaseIsUsedAsWritten;
    procedure TestStringCalendarMarginsConcatenate;
    procedure TestLocalTimeReadsTheZoneAtTheDate;
    procedure TestTheSystemZoneRoundTrips;
  end;

implementation

{ ---- the recorded zone ---- }

var
  GZoneAt, GZoneOff: array of Double;
  GZoneFirst: Double;

function ZoneHook(AUtcMs: Double): Double;
var lo, hi, mid: Integer;
begin
  Result := GZoneFirst;
  if IsNan(AUtcMs) then Exit;
  { the last change at or before the instant }
  lo := 0;
  hi := High(GZoneAt);
  if (hi < 0) or (AUtcMs < GZoneAt[0]) then Exit;
  while lo < hi do
  begin
    mid := (lo + hi + 1) div 2;
    if GZoneAt[mid] <= AUtcMs then lo := mid else hi := mid - 1;
  end;
  Result := GZoneOff[lo];
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-data-edge.json';
end;

function LoadJson(const APath: string): TJSONData;
var sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(APath);
    Result := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  Result := 0;
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

{ a {n, t} record's double; nil and anything else not a number }
function H(A: TJSONData): Double;
begin
  if (A <> nil) and (A.JSONType = jtObject) and (TJSONObject(A).Find('n') <> nil) then
    Exit(FromHex(TJSONObject(A).Strings['n']));
  if (A <> nil) and (A.JSONType = jtString) then Exit(FromHex(A.AsString));
  Result := NaN;
end;

function Bits(A: Double): QWord;
begin
  Result := 0;
  Move(A, Result, SizeOf(Result));
end;

function SameBits(A, B: Double): Boolean;
begin
  if IsNan(A) or IsNan(B) then Exit(IsNan(A) and IsNan(B));
  Result := Bits(A) = Bits(B);
end;

function Fmt(A: Double): string;
begin
  if IsNan(A) then Exit('NaN');
  Result := FloatToStrF(A, ffGeneral, 17, 0, DefaultFormatSettings);
end;

{ ---- the calendar's measurer ---- }

procedure TDeCalMeasurer.MeasureLine(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
begin
  AW := 10 * Length(AText);
  AH := TyFontPxOf(AFontSizeLogical);
end;

function TDeCalMeasurer.WrapToWidth(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
begin
  Result := AText;
end;

{ ---- the harness ---- }

procedure TAdvChartDataEdgeOracleTest.SetUp;
begin
  inherited SetUp;
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  FRoot := LoadJson(FixturePath);
  FTable := LoadJson(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-grid-bounds.json');
  FOpt := TTyChartOption.Create;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TCatProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  { zrender's width table: a grid shrinks by its labels as upstream's does }
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FTable).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FTable).Objects['ratios'].Integers['firstCode']));
  FBmp := nil;
  FBad := 0;
  FCompared := 0;
  FReport := '';
  TyLocalOffsetHook := nil;
  { upstream's English names }
  FSavedSource := TyDateTimeNameSource;
  TyDateTimeNameSource := dnTranslation;
end;

procedure TAdvChartDataEdgeOracleTest.TearDown;
begin
  TyDateTimeNameSource := FSavedSource;
  TyLocalOffsetHook := nil;
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FBmp);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FOpt);
  FreeAndNil(FTable);
  FreeAndNil(FRoot);
  inherited TearDown;
end;

procedure TAdvChartDataEdgeOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartDataEdgeOracleTest.SameH(const AWhat: string; AGot: Double;
  AWant: TJSONData);
begin
  Inc(FCompared);
  if not SameBits(AGot, H(AWant)) then
    Miss(Format('%s %s here, upstream %s', [AWhat, Fmt(AGot), Fmt(H(AWant))]));
end;

procedure TAdvChartDataEdgeOracleTest.Verdict(AMinimum: Integer);
begin
  AssertTrue(Format('enough was compared (%d)', [FCompared]), FCompared >= AMinimum);
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' differ from upstream:' + FReport, 0, FBad);
end;

function TAdvChartDataEdgeOracleTest.Cases(const AGroup: string): TJSONArray;
var
  all: TJSONArray;
  i: Integer;
begin
  Result := TJSONArray.Create;
  all := TJSONObject(FRoot).Arrays['cases'];
  for i := 0 to all.Count - 1 do
    if all.Objects[i].Strings['group'] = AGroup then
      Result.Add(all.Objects[i].Clone);
end;

function TAdvChartDataEdgeOracleTest.OptionTextOf(ACase: TJSONObject): string;
begin
  if ACase.Find('optionText') <> nil then Result := ACase.Strings['optionText']
  else Result := ACase.Objects['option'].AsJSON;
end;

procedure TAdvChartDataEdgeOracleTest.Draw(ACase: TJSONObject);
begin
  FName := ACase.Strings['id'];
  FreeAndNil(FBmp);
  FBmp := TBGRABitmap.Create(ACase.Integers['W'], ACase.Integers['H'], BGRAWhite);
  FChart.Option := OptionTextOf(ACase);
  AssertEquals(FName + ' parses', '', FChart.OptionError);
  FChart.SetBounds(0, 0, ACase.Integers['W'], ACase.Integers['H']);
  FChart.Render(FBmp.Canvas, Rect(0, 0, ACase.Integers['W'], ACase.Integers['H']), 96);
end;

{ the mark of one data item: the first element of the series at that index
  that is no caption }
function TAdvChartDataEdgeOracleTest.ItemElement(ASeries, AIndex: Integer): Integer;
var
  i: Integer;
  el: TTyChartElement;
begin
  Result := -1;
  for i := 0 to FChart.List.Count - 1 do
  begin
    el := FChart.List.Element(i);
    if (el.Datum.Kind = ctkSeries) and (el.Datum.SeriesIndex = ASeries)
      and (el.Datum.DataIndex = AIndex) and not el.Datum.IsEdge
      and (el.Caption.Text = '') then Exit(i);
  end;
end;

{ per item: the store's columns that the port keeps (the axes'), and --
  AFills -- whether the mark is filled and with what }
procedure TAdvChartDataEdgeOracleTest.CheckItems(ACase: TJSONObject; AFills: Boolean);
var
  items: TJSONArray;
  it, fill: TJSONObject;
  st: TTyDataStore;
  k, e: Integer;
  el: TTyChartElement;
  drawn: Boolean;
  c: TTyChartColor;
begin
  items := ACase.Arrays['items'];
  st := FChart.SeriesStore(0);
  AssertTrue(FName + ': a store', st <> nil);
  for k := 0 to items.Count - 1 do
  begin
    it := items.Objects[k];
    { the two coordinate columns }
    if st.Count > k then
    begin
      SameH(Format('item %d x', [k]), st.Get(0, k), it.Arrays['store'].Items[0]);
      SameH(Format('item %d y', [k]), st.Get(1, k), it.Arrays['store'].Items[1]);
    end
    else
      Miss(Format('item %d: not in the store', [k]));
    if not AFills then Continue;
    e := ItemElement(0, k);
    if e >= 0 then el := FChart.List.Element(e);
    drawn := (e >= 0) and not el.Ignore and el.Style.HasFill;
    Inc(FCompared);
    if drawn <> it.Booleans['drawn'] then
    begin
      Miss(Format('item %d drawn %s, upstream %s', [k, BoolToStr(drawn, True),
        BoolToStr(it.Booleans['drawn'], True)]));
      Continue;
    end;
    if not drawn then Continue;
    fill := it.Objects['fill'];
    c := el.Style.FillColor;
    Inc(FCompared);
    if (Integer((c shr 16) and $FF) <> fill.Integers['r'])
      or (Integer((c shr 8) and $FF) <> fill.Integers['g'])
      or (Integer(c and $FF) <> fill.Integers['b']) then
      Miss(Format('item %d fill %d/%d/%d, upstream %d/%d/%d', [k, (c shr 16) and $FF,
        (c shr 8) and $FF, c and $FF, fill.Integers['r'], fill.Integers['g'],
        fill.Integers['b']]));
  end;
end;

procedure TAdvChartDataEdgeOracleTest.UseZone(const AZone: string);
var
  zones, tr: TJSONArray;
  z: TJSONObject;
  i, k: Integer;
begin
  zones := TJSONObject(FRoot).Arrays['zones'];
  for i := 0 to zones.Count - 1 do
  begin
    z := zones.Objects[i];
    if z.Strings['zone'] <> AZone then Continue;
    tr := z.Arrays['transitions'];
    GZoneFirst := tr.Objects[0].Floats['off'];
    SetLength(GZoneAt, tr.Count - 1);
    SetLength(GZoneOff, tr.Count - 1);
    for k := 1 to tr.Count - 1 do
    begin
      GZoneAt[k - 1] := tr.Objects[k].Floats['at'];
      GZoneOff[k - 1] := tr.Objects[k].Floats['off'];
    end;
    TyLocalOffsetHook := @ZoneHook;
    Exit;
  end;
  Fail('no zone ' + AZone + ' in the fixture');
end;

{ ==================== tree ==================== }

procedure TAdvChartDataEdgeOracleTest.TestTreeValuesCompleteAsJavaScriptAddsThem;
var
  arr, rows: TJSONArray;
  cs, row: TJSONObject;
  c, k, i: Integer;
  sun: TTySunburstSolved;
  tm: TTyTreemapSolved;
  isSun: Boolean;
  lab: string;
  found: Boolean;
begin
  { before: string values were numbers and summed -- '5' and '3' made 8;
    JavaScript's `sum += childValue` from the number 0 made '053' }
  arr := Cases('tree');
  try
    for c := 0 to arr.Count - 1 do
    begin
      cs := arr.Objects[c];
      FName := cs.Strings['id'];
      AssertTrue(FName + ' parses', FOpt.SetOptionText(OptionTextOf(cs)));
      isSun := TJSONObject(TJSONArray(cs.Objects['option'].Arrays['series']).Items[0])
        .Strings['type'] = 'sunburst';
      rows := cs.Arrays['rows'];
      if isSun then
      begin
        sun := TySunburstSolve(FOpt, 0, TyRectF(0, 0, cs.Integers['W'], cs.Integers['H']), 96, 0);
        Inc(FCompared);
        if Length(sun.Nodes) <> rows.Count then
        begin
          Miss(Format('%d rows here, %d upstream', [Length(sun.Nodes), rows.Count]));
          Continue;
        end;
        for k := 0 to rows.Count - 1 do
        begin
          row := rows.Objects[k];
          SameH(Format('row %d value', [k]), sun.Nodes[k].Value, row.Find('value'));
          if row.Find('sector') <> nil then
          begin
            SameH(Format('row %d start', [k]), sun.Nodes[k].StartRad,
              row.Objects['sector'].Find('startAngle'));
            SameH(Format('row %d end', [k]), sun.Nodes[k].EndRad,
              row.Objects['sector'].Find('endAngle'));
            SameH(Format('row %d r0', [k]), sun.Nodes[k].R0, row.Objects['sector'].Find('r0'));
            SameH(Format('row %d r', [k]), sun.Nodes[k].R, row.Objects['sector'].Find('r'));
          end;
        end;
        { the labels: {c} prints the raw value as JavaScript left it }
        Draw(cs);
        for k := 0 to rows.Count - 1 do
        begin
          row := rows.Objects[k];
          if row.Find('label').JSONType = jtNull then Continue;
          { a piece with no angles: upstream's text has no place, and the
            port draws neither }
          if (row.Find('sector') = nil)
            or IsNan(H(row.Objects['sector'].Find('startAngle')))
            or IsNan(H(row.Objects['sector'].Find('endAngle'))) then Continue;
          lab := row.Strings['label'];
          found := False;
          for i := 0 to FChart.List.Count - 1 do
            if (FChart.List.Element(i).Datum.SeriesIndex = 0)
              and (FChart.List.Element(i).Datum.DataIndex = k)
              and (FChart.List.Element(i).Caption.Text <> '') then
            begin
              found := True;
              Inc(FCompared);
              if FChart.List.Element(i).Caption.Text <> lab then
                Miss(Format('row %d label "%s", upstream "%s"', [k,
                  FChart.List.Element(i).Caption.Text, lab]));
              Break;
            end;
          if not found then Miss(Format('row %d: no label, upstream "%s"', [k, lab]));
        end;
      end
      else
      begin
        tm := TyTreemapSolve(FOpt, 0, TyRectF(0, 0, cs.Integers['W'], cs.Integers['H']), 96);
        Inc(FCompared);
        if Length(tm.Nodes) <> rows.Count then
        begin
          Miss(Format('%d rows here, %d upstream', [Length(tm.Nodes), rows.Count]));
          Continue;
        end;
        for k := 0 to rows.Count - 1 do
        begin
          row := rows.Objects[k];
          SameH(Format('row %d value', [k]), tm.Nodes[k].Value, row.Find('value'));
          if (row.Find('rect') <> nil) and tm.Nodes[k].HasLayout then
          begin
            SameH(Format('row %d x', [k]), tm.Nodes[k].X, row.Objects['rect'].Find('x'));
            SameH(Format('row %d y', [k]), tm.Nodes[k].Y, row.Objects['rect'].Find('y'));
            SameH(Format('row %d w', [k]), tm.Nodes[k].W, row.Objects['rect'].Find('width'));
            SameH(Format('row %d h', [k]), tm.Nodes[k].H, row.Objects['rect'].Find('height'));
          end
          else if row.Find('rect') <> nil then
            Miss(Format('row %d: no layout here', [k]));
        end;
      end;
    end;
  finally
    arr.Free;
  end;
  Verdict(150);
end;

{ ==================== vmdim ==================== }

procedure TAdvChartDataEdgeOracleTest.TestAVisualMapReadsAColumnNoAxisReadsAsUpstream;
var
  arr: TJSONArray;
  c: Integer;
begin
  { before: the column was parsed as data whatever its type -- on a column
    upstream guesses (or is told) is ordinal, '' and null are nought in the
    visual's arithmetic, and those items were left unpainted here }
  arr := Cases('vmdim');
  try
    for c := 0 to arr.Count - 1 do
    begin
      Draw(arr.Objects[c]);
      CheckItems(arr.Objects[c], True);
    end;
  finally
    arr.Free;
  end;
  Verdict(80);
end;

{ ==================== intdim ==================== }

procedure TAdvChartDataEdgeOracleTest.TestAnIntColumnOffTheAxesIsAnInt32Array;
var
  arr: TJSONArray;
  c: Integer;
begin
  arr := Cases('intdim');
  try
    for c := 0 to arr.Count - 1 do
    begin
      Draw(arr.Objects[c]);
      CheckItems(arr.Objects[c], True);
    end;
  finally
    arr.Free;
  end;
  Verdict(40);
  { and the conversion itself }
  AssertEquals('1.7', 1, TyToInt32(1.7), 0);
  AssertEquals('-2.7', -2, TyToInt32(-2.7), 0);
  AssertEquals('2^32 + 1 wraps', 1, TyToInt32(4294967297), 0);
  AssertEquals('2^31 + 1 is negative', -2147483647, TyToInt32(2147483649), 0);
  AssertEquals('-2^31 - 1 wraps up', 2147483647, TyToInt32(-2147483649), 0);
  AssertEquals('NaN', 0, TyToInt32(NaN), 0);
  AssertEquals('Infinity', 0, TyToInt32(Infinity), 0);
  AssertEquals('1e20', 1661992960, TyToInt32(1e20), 0);
  AssertEquals('-0 is 0', 0, Bits(TyToInt32(-0.5)));
end;

{ ==================== timeinf ==================== }

procedure TAdvChartDataEdgeOracleTest.TestAnInfiniteTimeIsKeptAndBlanksTheAxis;
var
  arr, items: TJSONArray;
  cs, it: TJSONObject;
  c, k: Integer;
  ax: TTyAxis;
  st: TTyDataStore;
  placed: Boolean;
begin
  { before: an infinity on a time dimension read as no value; the axis took
    the finite rest, where upstream keeps it and the axis has no extent }
  arr := Cases('timeinf');
  try
    for c := 0 to arr.Count - 1 do
    begin
      cs := arr.Objects[c];
      Draw(cs);
      ax := FChart.Build.Grid(0).XAxis(0);
      Inc(FCompared);
      if ax.Scale.Blank <> cs.Booleans['xBlank'] then
        Miss(Format('x blank %s, upstream %s', [BoolToStr(ax.Scale.Blank, True),
          BoolToStr(cs.Booleans['xBlank'], True)]));
      items := cs.Arrays['items'];
      st := FChart.SeriesStore(0);
      for k := 0 to items.Count - 1 do
      begin
        it := items.Objects[k];
        SameH(Format('item %d x', [k]), st.Get(0, k), it.Arrays['store'].Items[0]);
        placed := not (IsNan(ax.DataToCoord(st.Get(0, k))) or IsInfinite(ax.DataToCoord(st.Get(0, k))));
        Inc(FCompared);
        if placed <> it.Booleans['placed'] then
          Miss(Format('item %d placed %s, upstream %s', [k, BoolToStr(placed, True),
            BoolToStr(it.Booleans['placed'], True)]));
      end;
    end;
  finally
    arr.Free;
  end;
  Verdict(15);
end;

{ ==================== logbase ==================== }

procedure TAdvChartDataEdgeOracleTest.TestTheLogBaseIsUsedAsWritten;
var
  arr, items, ticks, labels: TJSONArray;
  cs, ya, lab, want, ten: TJSONObject;
  c, k, i, p, built, devs: Integer;
  ax: TTyAxis;
  spec: PTyAxisLayoutSpec;
  e: TTyRange;
  v: Double;
begin
  { before: a logBase written as text ('2') was ten; 0, null and '' are ten
    upstream (`|| 10`) and stay so. A base the logarithm cannot use (1,
    under 1, negative, a word) is a recorded deviation: upstream's axis is
    broken there, and the port draws the base-ten one -- lb-null's record }
  arr := Cases('logbase');
  devs := 0;
  ten := nil;
  try
    for c := 0 to arr.Count - 1 do
      if arr.Objects[c].Strings['id'] = 'lb-null' then ten := arr.Objects[c];
    AssertTrue('the base-ten control', ten <> nil);
    for c := 0 to arr.Count - 1 do
    begin
      cs := arr.Objects[c];
      Draw(cs);
      ax := FChart.Build.Grid(0).YAxis(0);
      want := cs;
      if cs.Find('deviation') <> nil then
      begin
        want := ten;
        Inc(devs);
      end;
      ya := want.Objects['yAxis'];
      Inc(FCompared);
      if ax.Scale.Blank <> ya.Booleans['blank'] then
        Miss('blank ' + BoolToStr(ax.Scale.Blank, True));
      e := ax.Scale.GetExtent;
      SameH('extent start', e.Start, ya.Arrays['extent'].Items[0]);
      SameH('extent stop', e.Stop, ya.Arrays['extent'].Items[1]);
      spec := FChart.Build.Grid(0).SpecFor(ax);
      ticks := ya.Arrays['ticks'];
      Inc(FCompared);
      if Length(spec^.TickValues) <> ticks.Count then
        Miss(Format('%d ticks here, %d upstream', [Length(spec^.TickValues), ticks.Count]))
      else
        for k := 0 to ticks.Count - 1 do
          SameH(Format('tick %d', [k]), spec^.TickValues[k], ticks.Items[k]);
      labels := ya.Arrays['labels'];
      built := 0;
      for i := 0 to High(spec^.Placements) do
        if spec^.Placements[i].Built then Inc(built);
      Inc(FCompared);
      if built <> labels.Count then
        Miss(Format('%d labels here, %d upstream', [built, labels.Count]));
      for k := 0 to labels.Count - 1 do
      begin
        lab := labels.Objects[k];
        v := H(lab.Find('value'));
        p := -1;
        for i := 0 to High(spec^.TickValues) do
          if SameBits(spec^.TickValues[i], v) then
          begin
            p := i;
            Break;
          end;
        Inc(FCompared);
        if (p < 0) or (p > High(spec^.Placements)) then
          Miss('no label at ' + Fmt(v))
        else if spec^.Placements[p].Text <> lab.Strings['text'] then
          Miss(Format('label at %s "%s", upstream "%s"', [Fmt(v), spec^.Placements[p].Text,
            lab.Strings['text']]));
      end;
      { the points: the y of every value through the axis }
      items := want.Arrays['items'];
      for k := 0 to items.Count - 1 do
        SameH(Format('item %d y', [k]), ax.DataToCoord(H(items.Objects[k].Arrays['store'].Items[1])),
          items.Objects[k].Arrays['layout'].Items[1]);
    end;
  finally
    arr.Free;
  end;
  AssertEquals('the deviations', 4, devs);
  Verdict(80);
end;

{ ==================== calmargin ==================== }

procedure TAdvChartDataEdgeOracleTest.TestStringCalendarMarginsConcatenate;
var
  arr, texts: TJSONArray;
  cs, t: TJSONObject;
  c, k, i: Integer;
  spec: TTyCalendarSpec;
  cal: TTyCalendar;
  list: TTyPaintList;
  ink: TTyCalendarInk;
  els: array of TTyChartElement;
  el: TTyChartElement;
  lh, dy, mx, my, ux, uy: Double;
begin
  { before: a string margin was read as its number everywhere -- upstream
    adds it to a coordinate past the end, which concatenates ('240' + '5'
    is 2405), and zrender's own `textY += lineHeight / 2` concatenates once
    more for a top-aligned month label }
  ink := Default(TTyCalendarInk);
  ink.LabelFontSizeLogical := TyFontSizeFromPx(12);
  ink.LabelFontWeight := 400;
  ink.YearFontName := 'sans-serif';
  arr := Cases('calmargin');
  try
    for c := 0 to arr.Count - 1 do
    begin
      cs := arr.Objects[c];
      FName := cs.Strings['id'];
      AssertTrue(FName + ' parses', FOpt.SetOptionText(OptionTextOf(cs)));
      spec := TyCalendarSpecOf(FOpt, 0);
      cal := TTyCalendar.Create(spec);
      list := TTyPaintList.Create;
      try
        cal.UTC := True;
        cal.Resize(TyRectF(0, 0, cs.Integers['W'], cs.Integers['H']), 96);
        TyBuildCalendar(cal, ink, TDeCalMeasurer.Create, 96, list);
        els := nil;
        for i := 0 to list.Count - 1 do
          if list.Element(i).Caption.Text <> '' then
          begin
            SetLength(els, Length(els) + 1);
            els[High(els)] := list.Element(i);
          end;
        texts := cs.Arrays['texts'];
        k := 0;
        for i := 0 to texts.Count - 1 do
        begin
          t := texts.Objects[i];
          ux := H(TJSONArray(t.Find('mid')).Items[0]);
          uy := H(TJSONArray(t.Find('mid')).Items[1]);
          { a span upstream cannot place is a text the port does not draw }
          if IsNan(ux) or IsNan(uy) then Continue;
          Inc(FCompared);
          if k > High(els) then
          begin
            Miss(Format('"%s" not drawn', [t.Strings['text']]));
            Continue;
          end;
          el := els[k];
          Inc(k);
          if el.Caption.Text <> t.Strings['text'] then
            Miss(Format('text "%s", upstream "%s"', [el.Caption.Text, t.Strings['text']]));
          { the line's middle from the anchor: half a line down from a top,
            up from a bottom, turned with the text }
          lh := TyFontPxOf(el.Caption.FontSizeLogical);
          case el.Caption.AnchorV of
            tavTop: dy := lh / 2;
            tavBottom: dy := -lh / 2;
          else
            dy := 0;
          end;
          mx := el.Caption.X + dy * Sin(el.Caption.RotationRad);
          my := el.Caption.Y + dy * Cos(el.Caption.RotationRad);
          Inc(FCompared, 2);
          if Abs(mx - ux) > 1e-9 then
            Miss(Format('"%s" middle x %s, upstream %s', [t.Strings['text'], Fmt(mx), Fmt(ux)]));
          if Abs(my - uy) > 1e-9 then
            Miss(Format('"%s" middle y %s, upstream %s', [t.Strings['text'], Fmt(my), Fmt(uy)]));
        end;
        Inc(FCompared);
        if k <> Length(els) then
          Miss(Format('%d texts drawn here, %d upstream', [Length(els), k]));
      finally
        list.Free;
        cal.Free;
      end;
    end;
  finally
    arr.Free;
  end;
  Verdict(60);
end;

{ ==================== tz ==================== }

procedure TAdvChartDataEdgeOracleTest.TestLocalTimeReadsTheZoneAtTheDate;
var
  arr, vals, ticks, labels, days: TJSONArray;
  cs, xa, lab, day, ri: TJSONObject;
  c, k, i, p: Integer;
  ax: TTyAxis;
  spec: PTyAxisLayoutSpec;
  st: TTyDataStore;
  v, ms: Double;
  cspec: TTyCalendarSpec;
  cal: TTyCalendar;
  dv: TTyDataValue;
  pt: TTyPointF;
  info: TTyCalRangeInfo;
begin
  { before: every local date was read with TODAY's offset -- Shanghai's
    1900 (local mean time, +8:05:43) and 1988 summer (+9), Berlin's and New
    York's summers, and the skipped and repeated hours of a change }
  arr := Cases('tz');
  try
    for c := 0 to arr.Count - 1 do
    begin
      cs := arr.Objects[c];
      UseZone(cs.Strings['zone']);
      FName := cs.Strings['id'];
      if cs.Find('calendar') <> nil then
      begin
        AssertTrue(FName + ' parses', FOpt.SetOptionText(OptionTextOf(cs)));
        cspec := TyCalendarSpecOf(FOpt, 0);
        cal := TTyCalendar.Create(cspec);
        try
          cal.UTC := False;
          cal.Resize(TyRectF(0, 0, cs.Integers['W'], cs.Integers['H']), 96);
          ri := cs.Objects['calendar'];
          info := cal.Range;
          SameH('range start', info.Start.Time, ri.Find('start'));
          SameH('range end', info.Stop.Time, ri.Find('end'));
          SameH('weeks', info.Weeks, ri.Find('weeks'));
          SameH('allDay', info.AllDay, ri.Find('allDay'));
          SameH('fweek', info.FWeek, ri.Find('fweek'));
          SameH('lweek', info.LWeek, ri.Find('lweek'));
          days := cs.Arrays['days'];
          for k := 0 to days.Count - 1 do
          begin
            day := days.Objects[k];
            dv := Default(TTyDataValue);
            dv.Kind := dvkText;
            dv.Text := day.Strings['text'];
            ms := cal.ParseDate(dv);
            SameH(day.Strings['text'] + ' time', ms, day.Find('time'));
            pt := cal.DatePoint(ms, True);
            SameH(day.Strings['text'] + ' x', pt.X, day.Arrays['point'].Items[0]);
            SameH(day.Strings['text'] + ' y', pt.Y, day.Arrays['point'].Items[1]);
          end;
        finally
          cal.Free;
        end;
        Continue;
      end;
      Draw(cs);
      st := FChart.SeriesStore(0);
      vals := cs.Arrays['values'];
      for k := 0 to vals.Count - 1 do
        SameH(Format('value %d', [k]), st.Get(0, k), vals.Items[k]);
      ax := FChart.Build.Grid(0).XAxis(0);
      xa := cs.Objects['xAxis'];
      spec := FChart.Build.Grid(0).SpecFor(ax);
      ticks := xa.Arrays['ticks'];
      Inc(FCompared);
      if Length(spec^.TickValues) <> ticks.Count then
        Miss(Format('%d ticks here, %d upstream', [Length(spec^.TickValues), ticks.Count]))
      else
        for k := 0 to ticks.Count - 1 do
          SameH(Format('tick %d', [k]), spec^.TickValues[k], ticks.Items[k]);
      labels := xa.Arrays['labels'];
      for k := 0 to labels.Count - 1 do
      begin
        lab := labels.Objects[k];
        v := H(lab.Find('value'));
        p := -1;
        for i := 0 to High(spec^.TickValues) do
          if SameBits(spec^.TickValues[i], v) then
          begin
            p := i;
            Break;
          end;
        Inc(FCompared);
        if (p < 0) or (p > High(spec^.Labels)) then
          Miss('no label at ' + Fmt(v))
        else if StringReplace(spec^.Labels[p], LineEnding, #10, [rfReplaceAll])
          <> lab.Strings['text'] then
          Miss(Format('label at %s "%s", upstream "%s"', [Fmt(v), spec^.Labels[p],
            lab.Strings['text']]));
      end;
    end;
  finally
    arr.Free;
    TyLocalOffsetHook := nil;
  end;
  Verdict(500);
end;

procedure TAdvChartDataEdgeOracleTest.TestTheSystemZoneRoundTrips;
var
  t, u, w: Double;
  k: Integer;
begin
  { the system's zone, whatever it is here: a wall clock read back is the
    instant it came from, except within a change; and today's offset is
    GetLocalTimeOffset's }
  TyLocalOffsetHook := nil;
  AssertEquals('today''s offset', -GetLocalTimeOffset * 60000.0,
    TyLocalOffsetAt(TyDateTimeToMs(Now, False)), 0);
  for k := 0 to 400 do
  begin
    t := 86400000.0 * (k * 97) - 2208988800000.0;   { 1900 onwards }
    w := TyUtcToLocalMs(t);
    u := TyLocalToUtcMs(w);
    { a wall clock in a repeated hour reads back to the earlier instant }
    if u <> t then
      AssertEquals('only a repeated hour reads back elsewhere', w, TyUtcToLocalMs(u), 0);
  end;
end;

initialization
  RegisterTest(TAdvChartDataEdgeOracleTest);
end.
