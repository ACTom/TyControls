unit test.advchart.visualmap;
{$mode objfpc}{$H+}
{ visualMap's encoding -- the model, the colours and opacities it writes on
  each datum, its visualMeta and the gradient a line makes of it -- held to
  what ECharts 6.1 itself computes.

  tools/advchart-oracle/visualmap-encode.js runs the real build and records
  zrender's parse and fastLerp, the order V8's sort leaves the visual types
  in, the subtype defaulter, the continuous stop values, and per chart: the
  completed component, every datum's colour and opacity, the series'
  visualMetas, and the polyline's and area's paint.

  EXACT. Colours are compared as zrender holds them -- channels and a double
  alpha -- before the port quantises them, and again as the chart's
  elements carry them after it. Gradient coordinates and offsets bit for
  bit.

  The chart cases get upstream's palette and gradientColor written into
  their option: the theme here is the skin's, and upstream's colours are
  what the fixture recorded. The default ramp itself is tested apart, from
  the accent. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Option,
     tyControls.AdvChart.Shape, tyControls.AdvChart.Paint,
     tyControls.AdvChart.Handlers, tyControls.AdvChart.Color,
     tyControls.AdvChart.Complete, tyControls.AdvChart.Diagnose,
     tyControls.AdvChart.VisualMap, tyControls.AdvanceChart;
type
  TVmProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
    function MarkerColour(ASeries, ARaw: Integer): TTyChartColor;
  end;

  TAdvChartVisualMapOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TVmProbe;
    FRoot: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared: Integer;
    FReport: string;
    procedure Miss(const ACase, AWhat: string);
    procedure CheckChart(ACase: TJSONObject);
    procedure CheckSeries(const AName: string; AOption: TJSONObject;
      ASeries: TJSONObject);
    procedure CheckLine(const AName: string; ASeries: TJSONObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestParseIsZrenders;
    procedure TestFastLerpIsZrenders;
    procedure TestVisualOrderIsV8s;
    procedure TestSubTypeDefaulter;
    procedure TestDefaultRampFromTheAccent;
    procedure TestStopValuesAccumulate;
    procedure TestEveryChartAsUpstreamEncodesIt;
    procedure TestUntypedVisualMapIsNotReportedUntyped;
  end;

implementation

procedure TVmProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TVmProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function TVmProbe.MarkerColour(ASeries, ARaw: Integer): TTyChartColor;
begin
  Result := TooltipParams(TyChartDatum(ASeries, ARaw)).Color;
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-visualmap-encode.json';
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  Result := 0;
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

function Bits(A: Double): QWord;
begin
  Move(A, Result, SizeOf(Result));
end;

{ Bit for bit, so -0 is not 0 and NaN is NaN. }
function SameBits(A: Double; const AHex: string): Boolean;
begin
  Result := Bits(A) = Bits(FromHex(AHex));
end;

function Fmt(A: Double): string;
begin
  Result := FloatToStrF(A, ffGeneral, 17, 0, DefaultFormatSettings);
end;

function ColourText(const C: TTyVisualColor): string;
begin
  if not C.Defined then Exit('undefined');
  Result := Format('(%s,%s,%s,%s)', [Fmt(C.R), Fmt(C.G), Fmt(C.B), Fmt(C.A)]);
end;

{ The fixture's colour record as zrender holds it. }
function FixColour(AObj: TJSONObject): TTyVisualColor;
begin
  if AObj.Booleans['undef'] then Exit(TyVisualUndefined);
  Result := TyVisualRgba(AObj.Integers['r'], AObj.Integers['g'],
    AObj.Integers['b'], FromHex(AObj.Strings['a']));
end;

function SameColour(const C: TTyVisualColor; AObj: TJSONObject): Boolean;
begin
  if AObj.Booleans['undef'] then Exit(not C.Defined);
  Result := C.Defined and (C.R = AObj.Integers['r'])
    and (C.G = AObj.Integers['g']) and (C.B = AObj.Integers['b'])
    and SameBits(C.A, AObj.Strings['a']);
end;

{ The fixture's colour as a mark carries it, packed HERE rather than by the
  port's own TyVisualToChart -- an expectation computed by the code under
  test cannot catch it. Undefined is no fill. }
function PackFix(AObj: TJSONObject): TTyChartColor;
  function B(A: Double): Cardinal;
  begin
    Result := Cardinal(Floor(A + 0.5));
  end;
begin
  if AObj.Booleans['undef'] then Exit(0);
  Result := TTyChartColor((B(FromHex(AObj.Strings['a']) * 255) shl 24)
    or (B(AObj.Integers['r']) shl 16) or (B(AObj.Integers['g']) shl 8)
    or B(AObj.Integers['b']));
end;

function Str(AData: TJSONData): string;
begin
  if (AData = nil) or (AData.JSONType = jtNull) then Result := ''
  else Result := AData.AsString;
end;

procedure TAdvChartVisualMapOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TVmProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := TBGRABitmap.Create(800, 600, BGRA(255, 255, 255, 255));
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartVisualMapOracleTest.TearDown;
begin
  FreeAndNil(FRoot);
  FreeAndNil(FBmp);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartVisualMapOracleTest.Miss(const ACase, AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then
    FReport := FReport + LineEnding + '  ' + ACase + ': ' + AWhat;
end;

{ ==================== the arithmetic ==================== }

procedure TAdvChartVisualMapOracleTest.TestParseIsZrenders;
var
  arr: TJSONArray;
  p: TJSONObject;
  i: Integer;
  c: TTyVisualColor;
  ok: Boolean;
begin
  arr := TJSONObject(FRoot).Arrays['parse'];
  for i := 0 to arr.Count - 1 do
  begin
    p := arr.Objects[i];
    Inc(FCompared);
    ok := TyVisualTryParse(p.Strings['in'], c);
    if ok <> p.Booleans['ok'] then
      Miss(p.Strings['in'], Format('parses %s here', [BoolToStr(ok, True)]))
    else if ok and not ((c.R = p.Integers['r']) and (c.G = p.Integers['g'])
      and (c.B = p.Integers['b']) and SameBits(c.A, p.Strings['a'])) then
      Miss(p.Strings['in'], Format('(%d,%d,%d,%s) upstream, %s here',
        [p.Integers['r'], p.Integers['g'], p.Integers['b'], p.Strings['aText'],
         ColourText(c)]));
  end;
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' parse differently:' + FReport, 0, FBad);
end;

procedure TAdvChartVisualMapOracleTest.TestFastLerpIsZrenders;
var
  arr, cols: TJSONArray;
  p: TJSONObject;
  i, k: Integer;
  stops: TTyVisualColorArray;
  c: TTyVisualColor;
begin
  arr := TJSONObject(FRoot).Arrays['fastLerp'];
  for i := 0 to arr.Count - 1 do
  begin
    p := arr.Objects[i];
    cols := p.Arrays['colors'];
    SetLength(stops, cols.Count);
    for k := 0 to cols.Count - 1 do
      stops[k] := TyVisualParsedStop(cols.Items[k]);
    c := TyVisualFastLerp(FromHex(p.Strings['n']), stops);
    Inc(FCompared);
    if not SameColour(c, p.Objects['result']) then
      Miss(p.Strings['id'] + ' ' + p.Strings['note'],
        Format('%s upstream, %s here', [ColourText(FixColour(p.Objects['result'])),
          ColourText(c)]));
  end;
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' lerp differently:' + FReport, 0, FBad);
end;

procedure TAdvChartVisualMapOracleTest.TestVisualOrderIsV8s;
var
  arr, a: TJSONArray;
  p: TJSONObject;
  i, k: Integer;
  inp, outp: TTyStringArray;
  want, got: string;
begin
  arr := TJSONObject(FRoot).Arrays['sortCases'];
  AssertTrue('enough orders', arr.Count >= 50);
  for i := 0 to arr.Count - 1 do
  begin
    p := arr.Objects[i];
    a := p.Arrays['in'];
    SetLength(inp, a.Count);
    for k := 0 to a.Count - 1 do inp[k] := a.Strings[k];
    outp := TyPrepareVisualTypes(inp);
    want := p.Arrays['out'].AsJSON;
    got := '[';
    for k := 0 to High(outp) do
    begin
      if k > 0 then got := got + ', ';
      got := got + '"' + outp[k] + '"';
    end;
    got := got + ']';
    Inc(FCompared);
    if want <> got then
      Miss(a.AsJSON, want + ' upstream, ' + got + ' here');
  end;
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' sort differently:' + FReport, 0, FBad);
end;

procedure TAdvChartVisualMapOracleTest.TestSubTypeDefaulter;
var
  arr: TJSONArray;
  p: TJSONObject;
  i: Integer;
  opt: TTyChartOption;
  spec: TTyVisualMapSpec;
begin
  arr := TJSONObject(FRoot).Arrays['subtype'];
  for i := 0 to arr.Count - 1 do
  begin
    p := arr.Objects[i];
    opt := TTyChartOption.Create;
    try
      opt.SetOptionText(p.Objects['option'].AsJSON);
      spec := TyVisualMapSpecOf(opt, 0, nil);
      Inc(FCompared);
      if spec.SubType <> p.Strings['subType'] then
        Miss(p.Strings['id'] + ' ' + p.Strings['note'],
          p.Strings['subType'] + ' upstream, ' + spec.SubType + ' here');
    finally
      opt.Free;
    end;
  end;
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' default differently:' + FReport, 0, FBad);
end;

procedure TAdvChartVisualMapOracleTest.TestDefaultRampFromTheAccent;
var
  ramp: TTyVisualColorArray;
  g: TJSONArray;
begin
  { upstream's theme[0] is #5070dd; the port's accent stands in for it }
  ramp := TyVisualDefaultRamp($FF5070DD);
  g := TJSONObject(FRoot).Arrays['gradientColor'];
  AssertEquals('two stops', 2, Length(ramp));
  AssertTrue('the pale end is modifyHSL(accent, lightness 0.9): '
    + ColourText(ramp[0]), SameColour(ramp[0], g.Objects[0]));
  AssertTrue('the dark end is the accent: ' + ColourText(ramp[1]),
    SameColour(ramp[1], g.Objects[1]));
end;

procedure TAdvChartVisualMapOracleTest.TestStopValuesAccumulate;
var
  arr, vals: TJSONArray;
  p: TJSONObject;
  i, k: Integer;
  got: TTyDoubleArray;
  ext: TJSONArray;
begin
  arr := TJSONObject(FRoot).Arrays['stopValues'];
  for i := 0 to arr.Count - 1 do
  begin
    p := arr.Objects[i];
    ext := p.Arrays['extent'];
    got := TyVmStopValues(FromHex(ext.Strings[0]), FromHex(ext.Strings[1]));
    vals := p.Arrays['values'];
    Inc(FCompared);
    if Length(got) <> vals.Count then
    begin
      Miss(p.Strings['chart'], Format('%d values upstream, %d here',
        [vals.Count, Length(got)]));
      Continue;
    end;
    for k := 0 to vals.Count - 1 do
      if not SameBits(got[k], vals.Strings[k]) then
      begin
        Miss(p.Strings['chart'], Format('value %d: %s upstream, %s here',
          [k, Fmt(FromHex(vals.Strings[k])), Fmt(got[k])]));
        Break;
      end;
  end;
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' differ:' + FReport, 0, FBad);
end;

{ ==================== the charts ==================== }

function KindsText(const AMaps: TTyVisualMappingArray): string;
var i: Integer;
begin
  Result := '[';
  for i := 0 to High(AMaps) do
  begin
    if i > 0 then Result := Result + ', ';
    Result := Result + '"' + AMaps[i].Kind + '"';
  end;
  Result := Result + ']';
end;

function KeysText(const AKeys: TTyStringArray): string;
var i: Integer;
begin
  Result := '[';
  for i := 0 to High(AKeys) do
  begin
    if i > 0 then Result := Result + ', ';
    Result := Result + '"' + AKeys[i] + '"';
  end;
  Result := Result + ']';
end;

function ObjKeysText(AObj: TJSONObject): string;
var i: Integer;
begin
  Result := '[';
  if AObj <> nil then
    for i := 0 to AObj.Count - 1 do
    begin
      if i > 0 then Result := Result + ', ';
      Result := Result + '"' + AObj.Names[i] + '"';
    end;
  Result := Result + ']';
end;

function ItemNode(AOption: TJSONObject; ASeries, ARow: Integer): TJSONObject;
var d: TJSONData; s: TJSONData;
begin
  Result := nil;
  d := AOption.Find('series');
  if d = nil then Exit;
  if d.JSONType = jtArray then
  begin
    if ASeries >= TJSONArray(d).Count then Exit;
    s := TJSONArray(d).Items[ASeries];
  end
  else
    s := d;
  if s.JSONType <> jtObject then Exit;
  d := TJSONObject(s).Find('data');
  if (d = nil) or (d.JSONType <> jtArray) or (ARow >= TJSONArray(d).Count) then Exit;
  d := TJSONArray(d).Items[ARow];
  if d.JSONType = jtObject then Result := TJSONObject(d);
end;

{ Whether the data item wrote itemStyle.<AKey>. }
function ItemHas(AOption: TJSONObject; ASeries, ARow: Integer;
  const AKey: string): Boolean;
var o: TJSONObject;
begin
  o := ItemNode(AOption, ASeries, ARow);
  Result := (o <> nil) and (o.FindPath('itemStyle.' + AKey) <> nil);
end;

{ The data item's own itemStyle.color, when the option wrote one. }
function ItemColour(AOption: TJSONObject; ASeries, ARow: Integer;
  out AText: string): Boolean;
var d: TJSONData; s: TJSONData;
begin
  Result := False;
  AText := '';
  d := AOption.Find('series');
  if d = nil then Exit;
  if d.JSONType = jtArray then
  begin
    if ASeries >= TJSONArray(d).Count then Exit;
    s := TJSONArray(d).Items[ASeries];
  end
  else
    s := d;
  if s.JSONType <> jtObject then Exit;
  d := TJSONObject(s).Find('data');
  if (d = nil) or (d.JSONType <> jtArray) or (ARow >= TJSONArray(d).Count) then Exit;
  d := TJSONArray(d).Items[ARow];
  if d.JSONType <> jtObject then Exit;
  d := TJSONObject(d).FindPath('itemStyle.color');
  if (d = nil) or (d.JSONType <> jtString) then Exit;
  AText := d.AsString;
  Result := True;
end;

procedure TAdvChartVisualMapOracleTest.CheckSeries(const AName: string;
  AOption: TJSONObject; ASeries: TJSONObject);
var
  rows, metas, stops: TJSONArray;
  r, m, st: TJSONObject;
  si, i, k, raw, found: Integer;
  row: TTyVisualRow;
  got: TTyVisualMetaArray;
  typ, itemText, nm: string;
  itemC: TTyVisualColor;
  lst: TTyPaintList;
  e, el: TTyChartElement;
  want: TTyChartColor;
  wantAlpha: Double;
begin
  si := ASeries.Integers['index'];
  typ := ASeries.Strings['type'];
  nm := AName + ' s' + IntToStr(si);
  rows := ASeries.Arrays['rows'];
  lst := FChart.List;
  for i := 0 to rows.Count - 1 do
  begin
    r := rows.Objects[i];
    raw := r.Integers['i'];
    Inc(FCompared);
    if not FChart.VisualRow(si, raw, row) then
    begin
      Miss(nm, Format('row %d: no visual row', [raw]));
      Continue;
    end;
    { visualMap: false -- nothing written }
    if (r.Find('skip') <> nil) and r.Booleans['skip'] then
    begin
      if row.ColorSet or row.OpacitySet then
        Miss(nm, Format('row %d opted out, and was written here', [raw]));
    end
    else
    begin
      { THE COLOUR AS zrender HOLDS IT: the item's own colour over the
        mapped one }
      if ItemColour(AOption, si, raw, itemText) then
      begin
        if not (TyVisualTryParse(itemText, itemC) and SameColour(itemC, r.Objects['color'])) then
          Miss(nm, Format('row %d: the item colour %s is not upstream''s', [raw, itemText]));
      end
      else if not row.ColorSet then
        Miss(nm, Format('row %d: no colour written here', [raw]))
      else if not SameColour(row.Color, r.Objects['color']) then
        Miss(nm, Format('row %d: %s upstream, %s here', [raw,
          ColourText(FixColour(r.Objects['color'])), ColourText(row.Color)]));
      { AND ITS OPACITY. A scatter's 0.8 is its series default, which the
        element check below holds. }
      if (typ <> 'scatter') and not ItemHas(AOption, si, raw, 'opacity') then
      begin
        if r.Find('opacity').JSONType = jtNull then
        begin
          if row.OpacitySet then
            Miss(nm, Format('row %d: opacity %s written here', [raw, Fmt(row.Opacity)]));
        end
        else if not (row.OpacitySet and SameBits(row.Opacity, r.Strings['opacity'])) then
          Miss(nm, Format('row %d: opacity %s upstream, %s here', [raw,
            r.Strings['opacityText'], Fmt(row.Opacity)]));
      end;
    end;

    { THE SAME DATUM AS DRAWN: a bar's or a scatter's element, quantised }
    if (typ = 'bar') or (typ = 'scatter') then
    begin
      found := 0;
      el := Default(TTyChartElement);
      if lst <> nil then
        for k := 0 to lst.Count - 1 do
        begin
          e := lst.Element(k);
          if e.Datum.IsEdge or (e.Datum.SeriesIndex <> si)
            or (e.Datum.RawDataIndex <> raw) then Continue;
          if e.Caption.FontSizeLogical > 0 then Continue;
          Inc(found);
          el := e;
        end;
      if found = 1 then
      begin
        want := PackFix(r.Objects['color']);
        if r.Find('opacity').JSONType = jtNull then wantAlpha := 1
        else wantAlpha := FromHex(r.Strings['opacity']);
        Inc(FCompared);
        if (el.Style.FillColor <> want) or (el.Style.HasFill <> (want <> 0)) then
          Miss(nm, Format('row %d: drawn in $%.8x, upstream $%.8x', [raw,
            el.Style.FillColor, want]))
        else if el.Style.FillGradient.Kind <> cgkNone then
          Miss(nm, Format('row %d: drawn with a gradient', [raw]))
        else if el.Style.Alpha <> wantAlpha then
          Miss(nm, Format('row %d: alpha %s, upstream %s', [raw,
            Fmt(el.Style.Alpha), Fmt(wantAlpha)]));
      end;
    end;
  end;

  { THE TOOLTIP MARKER is the item's colour }
  if ASeries.Find('tooltipMarker') <> nil then
  begin
    m := ASeries.Objects['tooltipMarker'];
    want := PackFix(m.Objects['color']);
    Inc(FCompared);
    if FChart.MarkerColour(si, m.Integers['row']) <> want then
      Miss(nm, Format('marker of row %d: $%.8x here, upstream $%.8x',
        [m.Integers['row'], FChart.MarkerColour(si, m.Integers['row']), want]));
  end;

  { THE visualMetas }
  metas := ASeries.Arrays['visualMeta'];
  got := FChart.VisualMetas(si);
  Inc(FCompared);
  if Length(got) <> metas.Count then
  begin
    Miss(nm, Format('%d visualMetas upstream, %d here', [metas.Count, Length(got)]));
    Exit;
  end;
  for i := 0 to metas.Count - 1 do
  begin
    m := metas.Objects[i];
    Inc(FCompared);
    if (got[i].VisualMap <> m.Integers['vm'])
      or (got[i].Dimension <> m.Integers['dimension'])
      or (got[i].CoordDim <> Str(m.Find('coordDim'))) then
    begin
      Miss(nm, Format('meta %d: vm %d dim %d "%s" upstream, vm %d dim %d "%s" here',
        [i, m.Integers['vm'], m.Integers['dimension'], Str(m.Find('coordDim')),
         got[i].VisualMap, got[i].Dimension, got[i].CoordDim]));
      Continue;
    end;
    if not (SameColour(got[i].Outer0, m.Arrays['outerColors'].Objects[0])
      and SameColour(got[i].Outer1, m.Arrays['outerColors'].Objects[1])) then
      Miss(nm, Format('meta %d: outer colours %s %s here', [i,
        ColourText(got[i].Outer0), ColourText(got[i].Outer1)]));
    stops := m.Arrays['stops'];
    if Length(got[i].Stops) <> stops.Count then
    begin
      Miss(nm, Format('meta %d: %d stops upstream, %d here', [i, stops.Count,
        Length(got[i].Stops)]));
      Continue;
    end;
    for k := 0 to stops.Count - 1 do
    begin
      st := stops.Objects[k];
      if not SameBits(got[i].Stops[k].Value, st.Strings['value']) then
      begin
        Miss(nm, Format('meta %d stop %d: value %s upstream, %s here', [i, k,
          st.Strings['valueText'], Fmt(got[i].Stops[k].Value)]));
        Break;
      end;
      if not SameColour(got[i].Stops[k].Color, st.Objects['color']) then
      begin
        Miss(nm, Format('meta %d stop %d (%s): %s upstream, %s here', [i, k,
          st.Strings['valueText'], ColourText(FixColour(st.Objects['color'])),
          ColourText(got[i].Stops[k].Color)]));
        Break;
      end;
    end;
  end;

  if typ = 'line' then CheckLine(nm, ASeries);
end;

{ A line's pen and area against the visual fill and against the elements. }
procedure TAdvChartVisualMapOracleTest.CheckLine(const AName: string;
  ASeries: TJSONObject);
var
  fill: TTyVisualLineFill;
  lst: TTyPaintList;
  e: TTyChartElement;
  si, k: Integer;
  poly, area: TJSONObject;
  g: TTyChartGradient;

  function SameFill(ARec: TJSONObject; const AWhat: string): Boolean;
  var st: TJSONArray; j: Integer; lo, hi: string;
  begin
    Result := False;
    if ARec.Strings['kind'] = 'color' then
    begin
      if (fill.Kind <> vlfSolid) or not SameColour(fill.Solid, ARec.Objects['color']) then
        Miss(AName, AWhat + ': one colour upstream, not here')
      else
        Result := True;
      Exit;
    end;
    if fill.Kind <> vlfGradient then
    begin
      Miss(AName, AWhat + ': a gradient upstream, none here');
      Exit;
    end;
    if fill.Vertical then
    begin
      lo := ARec.Strings['y'];
      hi := ARec.Strings['y2'];
    end
    else
    begin
      lo := ARec.Strings['x'];
      hi := ARec.Strings['x2'];
    end;
    if (fill.Vertical <> (ARec.Strings['x2'] = ARec.Strings['x']))
      or not SameBits(fill.Lo, lo) or not SameBits(fill.Hi, hi) then
    begin
      Miss(AName, Format('%s: %s..%s here, upstream x %s y %s x2 %s y2 %s',
        [AWhat, Fmt(fill.Lo), Fmt(fill.Hi), ARec.Strings['xText'],
         ARec.Strings['yText'], ARec.Strings['x2Text'], ARec.Strings['y2Text']]));
      Exit;
    end;
    st := ARec.Arrays['stops'];
    if Length(fill.Stops) <> st.Count then
    begin
      Miss(AName, Format('%s: %d stops upstream, %d here', [AWhat, st.Count,
        Length(fill.Stops)]));
      Exit;
    end;
    for j := 0 to st.Count - 1 do
      if not (SameBits(fill.Stops[j].Offset, st.Objects[j].Strings['offset'])
        and SameColour(fill.Stops[j].Color, st.Objects[j].Objects['color'])) then
      begin
        Miss(AName, Format('%s stop %d: %s %s upstream, %s %s here', [AWhat, j,
          st.Objects[j].Strings['offsetText'],
          ColourText(FixColour(st.Objects[j].Objects['color'])),
          Fmt(fill.Stops[j].Offset), ColourText(fill.Stops[j].Color)]));
        Exit;
      end;
    Result := True;
  end;

  { the element's gradient is the fill's, quantised }
  function SameGradient(const AG: TTyChartGradient): Boolean;
  var j: Integer;
  begin
    g := TyVisualLineGradient(fill);
    Result := (AG.Kind = g.Kind) and (AG.Global = g.Global) and (AG.X = g.X)
      and (AG.Y = g.Y) and (AG.X2 = g.X2) and (AG.Y2 = g.Y2)
      and (Length(AG.Stops) = Length(g.Stops));
    if Result then
      for j := 0 to High(g.Stops) do
        if (AG.Stops[j].Offset <> g.Stops[j].Offset)
          or (AG.Stops[j].Color <> g.Stops[j].Color) then Exit(False);
  end;

var written: Boolean; c: TTyChartColor;
begin
  si := ASeries.Integers['index'];
  fill := FChart.VisualLineFill(si);
  poly := ASeries.Objects['polyline'];
  written := ASeries.Booleans['lineStyleColorWritten'];
  lst := FChart.List;
  Inc(FCompared);
  if not written then SameFill(poly, 'polyline');
  area := nil;
  if ASeries.Find('area').JSONType = jtObject then area := ASeries.Objects['area'];
  if area <> nil then
  begin
    Inc(FCompared);
    SameFill(area, 'area');
  end;
  { and what was drawn with it }
  if lst = nil then Exit;
  for k := 0 to lst.Count - 1 do
  begin
    e := lst.Element(k);
    if (e.Datum.SeriesIndex <> si) or (e.Datum.DataIndex <> -1) then Continue;
    if e.Shape.Kind = cskPolyline then
    begin
      Inc(FCompared);
      if written then
      begin
        TyTryParseChartColor(poly.Objects['color'].Strings['css'], c);
        if (e.Style.StrokeColor <> c) or (e.Style.StrokeGradient.Kind <> cgkNone) then
          Miss(AName, 'the polyline does not keep its authored colour');
      end
      else if fill.Kind = vlfGradient then
      begin
        if not SameGradient(e.Style.StrokeGradient) then
          Miss(AName, 'the polyline is not drawn with the gradient');
      end
      else if fill.Kind = vlfSolid then
      begin
        if e.Style.StrokeColor <> TyVisualToChart(fill.Solid) then
          Miss(AName, 'the polyline is not drawn in the one colour');
      end;
    end
    else if (e.Shape.Kind = cskPolygon) and (area <> nil) then
    begin
      Inc(FCompared);
      if (fill.Kind = vlfGradient) and not SameGradient(e.Style.FillGradient) then
        Miss(AName, 'the area is not filled with the gradient');
    end;
  end;
end;

procedure TAdvChartVisualMapOracleTest.CheckChart(ACase: TJSONObject);
const
  cPalette = '["#5070dd","#b6d634","#505372","#ff994d","#0ca8df","#ffd10a",'
    + '"#fb628b","#785db0","#3fbe95"]';
var
  name: string;
  opt: TJSONObject;
  vms, series, g: TJSONArray;
  vm, tgt: TJSONObject;
  i: Integer;
  spec: TTyVisualMapSpec;
  st: TTyVisualState;
const
  cStates: array[TTyVisualState] of string = ('inRange', 'outOfRange');
begin
  name := ACase.Strings['id'];
  { upstream's own palette and ramp, so the theme is out of the comparison }
  opt := TJSONObject(ACase.Objects['option'].Clone);
  try
    if opt.Find('color') = nil then opt.Add('color', GetJSON(cPalette));
    if opt.Find('gradientColor') = nil then
    begin
      g := TJSONArray.Create;
      for i := 0 to TJSONObject(FRoot).Arrays['gradientColor'].Count - 1 do
        g.Add(TJSONObject(FRoot).Arrays['gradientColor'].Objects[i].Strings['css']);
      opt.Add('gradientColor', g);
    end;
    FChart.Option := opt.AsJSON;
    AssertEquals(name + ' parses', '', FChart.OptionError);
    FChart.SetBounds(0, 0, ACase.Integers['width'], ACase.Integers['height']);
    try
      FChart.Render(FBmp.Canvas, Rect(0, 0, ACase.Integers['width'],
        ACase.Integers['height']), 96);
    except
      on E: Exception do
      begin
        Miss(name, E.ClassName + ': ' + E.Message);
        Exit;
      end;
    end;

    { THE COMPONENTS, completed }
    vms := ACase.Arrays['visualMaps'];
    Inc(FCompared);
    if FChart.VisualMapCount <> vms.Count then
      Miss(name, Format('%d visualMaps upstream, %d here', [vms.Count,
        FChart.VisualMapCount]));
    for i := 0 to vms.Count - 1 do
    begin
      vm := vms.Objects[i];
      spec := FChart.VisualMapSpec(vm.Integers['index']);
      Inc(FCompared);
      if spec.SubType <> vm.Strings['subType'] then
        Miss(name, 'subtype ' + spec.SubType);
      if not (SameBits(spec.Extent0, vm.Arrays['extent'].Strings[0])
        and SameBits(spec.Extent1, vm.Arrays['extent'].Strings[1])) then
        Miss(name, Format('extent %s..%s here', [Fmt(spec.Extent0), Fmt(spec.Extent1)]));
      if not (SameBits(spec.Range0, vm.Arrays['range'].Strings[0])
        and SameBits(spec.Range1, vm.Arrays['range'].Strings[1])) then
        Miss(name, Format('range %s..%s here', [Fmt(spec.Range0), Fmt(spec.Range1)]));
      if spec.RangeAuto <> vm.Booleans['rangeAuto'] then
        Miss(name, 'rangeAuto differs');
      tgt := vm.Objects['target'];
      for st := Low(TTyVisualState) to High(TTyVisualState) do
      begin
        if KeysText(spec.Keys[st]) <> ObjKeysText(tgt.Objects[cStates[st]]) then
          Miss(name, Format('target.%s keys %s upstream, %s here', [cStates[st],
            ObjKeysText(tgt.Objects[cStates[st]]), KeysText(spec.Keys[st])]));
        if KindsText(spec.States[st]) <> vm.Objects['order'].Arrays[cStates[st]].AsJSON then
          Miss(name, Format('%s applied as %s upstream, %s here', [cStates[st],
            vm.Objects['order'].Arrays[cStates[st]].AsJSON,
            KindsText(spec.States[st])]));
      end;
    end;

    series := ACase.Arrays['series'];
    for i := 0 to series.Count - 1 do
      CheckSeries(name, opt, series.Objects[i]);
  finally
    opt.Free;
  end;
end;

procedure TAdvChartVisualMapOracleTest.TestEveryChartAsUpstreamEncodesIt;
var
  cases: TJSONArray;
  c: Integer;
begin
  cases := TJSONObject(FRoot).Arrays['charts'];
  for c := 0 to cases.Count - 1 do
    CheckChart(cases.Objects[c]);
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
  AssertTrue(Format('enough was compared (%d)', [FCompared]), FCompared > 400);
end;

procedure TAdvChartVisualMapOracleTest.TestUntypedVisualMapIsNotReportedUntyped;
var
  diags: TTyOptDiagArray;
  i: Integer;
begin
  { dataset-encode0 writes its visualMap with no type: ECharts defaults it,
    so it is neither "has no type" nor a subtree left unvalidated }
  diags := TyOptDiagnose('{"visualMap": {"orient": "horizontal", "min": 10,'
    + ' "max": 100, "text": ["High", "Low"], "dimension": 0,'
    + ' "inRange": {"color": ["#65B581", "#FFCE34"]}, "bogusKey": 1},'
    + ' "series": [{"type": "bar", "data": [1]}], "xAxis": {}, "yAxis": {}}');
  for i := 0 to High(diags) do
    AssertFalse('an untyped visualMap is not "no type": ' + diags[i].Text,
      diags[i].Kind = odkNoSeriesType);
  { validated as the continuous variant: its unknown key is reported, its
    known ones are not }
  for i := 0 to High(diags) do
    if Pos('bogusKey', diags[i].Path) > 0 then Exit;
  Fail('the untyped visualMap''s subtree was not validated');
end;

initialization
  RegisterTest(TAdvChartVisualMapOracleTest);
end.
