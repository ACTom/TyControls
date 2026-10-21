unit test.advchart.datasettransform;
{$mode objfpc}{$H+}
{ DATASET TRANSFORMS -- roadmap D2, batch 133 -- held to upstream.

  tools/advchart-oracle/dataset-transform.js runs the real ECharts 6.1 build
  in node over 128 options and records, per dataset (prepared one after the
  other, as a series would), either the message upstream threw or every
  result in SourceManager._sourceList: its format, whether it is a
  fromTransformResult copy, its header count, its dimension names, its
  detected dimension count, and its rows cell by cell; and, for the options
  with series, the chart drawn over the transformed tables: the grid, the
  category axes' categories, and per series its items (bar rects, line and
  scatter points, pie sectors) and its labels.

  THE REPLAY: the tables are TTyDatasetCache's results read through
  TySourceFieldsOf (what createSource makes of a node) -- every number to
  the bit, every string as it is; a dataset upstream throws on has no
  table here and a reason; the charts are the control's own, text measured
  with zrender's width table. The test's own three transforms (test:scale,
  test:pairs, test:raw) are registered here as the oracle registers them.

  Hand-written beside it: the registry's naming rules; TyJsArraySort against
  a plain stable sort for consistent comparators; the diagnostic a failing
  transform leaves; `reg`, which the port does not have. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.StrConsts,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint, tyControls.AdvanceChart.Shape,
     tyControls.AdvanceChart.Coord, tyControls.AdvanceChart.Builder,
     tyControls.AdvanceChart.Option, tyControls.AdvanceChart.Dataset,
     tyControls.AdvanceChart.DataTransform, tyControls.AdvanceChart.Measure,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TDtProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  TAdvChartDatasetTransformTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TDtProbe;
    FRoot, FTable: TJSONData;
    FBad, FCompared, FCells, FItems, FLabels: Integer;
    FReport, FWhere: string;
    procedure Miss(const AWhat: string);
    procedure Same(const AWhat: string; AGot: Double; const AHex: string);
    procedure SameInt(const AWhat: string; AGot, AWant: Int64);
    procedure SameStr(const AWhat, AGot, AWant: string);
    function Cases: TJSONArray;
    function CaseById(const AId: string): TJSONObject;
    procedure NewChart(AOption: TJSONObject);
    procedure CheckCell(const AWhat: string; AGot: TJSONData; AWant: TJSONData);
    procedure CheckRows(const AWhat: string; ANode: TJSONObject; AWant: TJSONData);
    procedure CheckDatasets(ACase: TJSONObject);
    procedure CheckSeries(ASeries: TJSONObject);
    procedure CheckRender(ACase: TJSONObject);
    procedure Finish(const AWhat: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEveryTableIsUpstreamsTable;
    procedure TestEveryThrowLeavesNoTable;
    procedure TestSeriesOverTransformsDrawAsUpstream;
    procedure TestRegIsRefusedWithAReason;
    procedure TestAFailingTransformIsADiagnostic;
    procedure TestTheRegistryNamesItsTransforms;
    procedure TestTheSortIsStableForAConsistentComparator;
  end;

implementation

{ ==================== the test's own transforms ==================== }

{ 'test:scale': every number times config.k, read through RetrieveValue;
  no dimensions, so result 0 inherits the header }
procedure ScaleTransform(const AParams: TTyTransformParams;
  var AResults: TTyTransformResultArray);
var
  up: TTyExternalSource;
  k: Double;
  data, row: TJSONArray;
  i, d: Integer;
  v: TJSONData;
begin
  up := AParams.Upstream;
  k := TJSONObject(AParams.Config).Find('k').AsFloat;
  data := TJSONArray.Create;
  for i := 0 to up.Count - 1 do
  begin
    row := TJSONArray.Create;
    for d := 0 to up.DimCount - 1 do
    begin
      v := up.RetrieveValue(i, up.Dim(d).Index);
      if v = nil then row.Add(TJSONNull.Create)
      else if v.JSONType = jtNumber then row.Add(TJSONFloatNumber.Create(v.AsFloat * k))
      else row.Add(v.Clone);
    end;
    data.Add(row);
  end;
  TyAddTransformResult(AResults, data);
end;

{ 'test:pairs': [name, value] rows named, and -- unnamed -- a line of two
  words and a line with the count }
procedure PairsTransform(const AParams: TTyTransformParams;
  var AResults: TTyTransformResultArray);
var
  up: TTyExternalSource;
  nameDim, valueDim, i: Integer;
  data, row, cnt: TJSONArray;
  v: TJSONData;
begin
  up := AParams.Upstream;
  nameDim := up.DimensionOf(TJSONObject(AParams.Config).Find('name'));
  valueDim := up.DimensionOf(TJSONObject(AParams.Config).Find('value'));
  data := TJSONArray.Create;
  for i := 0 to up.Count - 1 do
  begin
    row := TJSONArray.Create;
    v := up.RetrieveValue(i, nameDim);
    if v = nil then row.Add(TJSONNull.Create) else row.Add(v.Clone);
    v := up.RetrieveValue(i, valueDim);
    if v = nil then row.Add(TJSONNull.Create) else row.Add(v.Clone);
    data.Add(row);
  end;
  TyAddTransformResult(AResults, data, TJSONArray.Create(['name', 'value']));
  cnt := TJSONArray.Create;
  cnt.Add(TJSONArray.Create(['rows', 'of']));
  cnt.Add(TJSONArray.Create(['count', up.Count]));
  TyAddTransformResult(AResults, cnt);
end;

{ 'test:raw': a raw item, which only a built-in may ask for }
procedure RawTransform(const AParams: TTyTransformParams;
  var AResults: TTyTransformResultArray);
var data: TJSONArray;
begin
  data := TJSONArray.Create;
  try
    data.Add(AParams.Upstream.RawItem(0).Clone);
  except
    data.Free;
    raise;
  end;
  TyAddTransformResult(AResults, data);
end;

{ ==================== the probe ==================== }

procedure TDtProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TDtProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

function TDtProbe.List: TTyPaintList;
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

function Fmt(A: Double): string;
var fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := FloatToStrF(A, ffGeneral, 17, 0, fs);
end;

{ to the bit -- a not-a-number is one whatever its payload }
function SameBits(A, B: Double): Boolean;
begin
  Result := (HexOf(A) = HexOf(B)) or (IsNan(A) and IsNan(B));
end;

function IsNull(AData: TJSONData): Boolean;
begin
  Result := (AData = nil) or (AData.JSONType = jtNull);
end;

function FormatName(AFormat: TTySourceFormat): string;
begin
  case AFormat of
    tsfArrayRows: Result := 'arrayRows';
    tsfObjectRows: Result := 'objectRows';
    tsfKeyedColumns: Result := 'keyedColumns';
    tsfOriginal: Result := 'original';
  else
    Result := 'unknown';
  end;
end;

procedure TAdvChartDatasetTransformTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := nil;
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath('advchart-dataset-transform.json'));
    FRoot := GetJSON(sl.Text);
    sl.LoadFromFile(FixturePath('advchart-grid-bounds.json'));
    FTable := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartDatasetTransformTest.TearDown;
begin
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FChart);
  FreeAndNil(FRoot);
  FreeAndNil(FTable);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartDatasetTransformTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 16000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TAdvChartDatasetTransformTest.Same(const AWhat: string; AGot: Double;
  const AHex: string);
begin
  Inc(FCompared);
  if not SameBits(AGot, FromHex(AHex)) then
    Miss(Format('%s %s here, %s upstream', [AWhat, Fmt(AGot), Fmt(FromHex(AHex))]));
end;

procedure TAdvChartDatasetTransformTest.SameInt(const AWhat: string; AGot, AWant: Int64);
begin
  Inc(FCompared);
  if AGot <> AWant then Miss(Format('%s %d here, %d upstream', [AWhat, AGot, AWant]));
end;

procedure TAdvChartDatasetTransformTest.SameStr(const AWhat, AGot, AWant: string);
begin
  Inc(FCompared);
  if AGot <> AWant then Miss(Format('%s "%s" here, "%s" upstream', [AWhat, AGot, AWant]));
end;

procedure TAdvChartDatasetTransformTest.Finish(const AWhat: string);
begin
  if GetEnvironmentVariable('TY_DATASETTRANSFORM_COUNTS') = '1' then
    WriteLn(Format('%s: %d compared, %d cells, %d items, %d labels',
      [AWhat, FCompared, FCells, FItems, FLabels]));
  AssertTrue(AWhat + ': nothing compared', FCompared > 0);
  AssertEquals(Format('%s: %d of %d comparisons differ:%s',
    [AWhat, FBad, FCompared, FReport]), 0, FBad);
end;

function TAdvChartDatasetTransformTest.Cases: TJSONArray;
begin
  Result := TJSONObject(FRoot).Arrays['cases'];
end;

function TAdvChartDatasetTransformTest.CaseById(const AId: string): TJSONObject;
var i: Integer;
begin
  Result := nil;
  for i := 0 to Cases.Count - 1 do
    if Cases.Objects[i].Strings['id'] = AId then Exit(Cases.Objects[i]);
end;

procedure TAdvChartDatasetTransformTest.NewChart(AOption: TJSONObject);
begin
  if FChart <> nil then
  begin
    FChart.Measurer := nil;
    FreeAndNil(FChart);
  end;
  FChart := TDtProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FTable).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FTable).Objects['ratios'].Integers['firstCode']));
  FChart.Option := AOption.AsJSON;
  FChart.SetBounds(0, 0, TJSONObject(FRoot).Integers['W'], TJSONObject(FRoot).Integers['H']);
end;

{ ==================== the tables ==================== }

{ A cell as the fixture writes it: a number its hex, 's:' a string, 'b:' a
  boolean, 'j:' anything else as JSON, null null }
procedure TAdvChartDatasetTransformTest.CheckCell(const AWhat: string;
  AGot: TJSONData; AWant: TJSONData);
var
  w: string;
  jd: TJSONData;
begin
  Inc(FCompared);
  Inc(FCells);
  if IsNull(AWant) then
  begin
    if not IsNull(AGot) then Miss(AWhat + ': ' + AGot.AsJSON + ' here, null upstream');
    Exit;
  end;
  w := AWant.AsString;
  if AGot = nil then
  begin
    Miss(AWhat + ': nothing here, ' + w + ' upstream');
    Exit;
  end;
  if Copy(w, 1, 2) = 's:' then
  begin
    if (AGot.JSONType <> jtString) or (AGot.AsString <> Copy(w, 3, MaxInt)) then
      Miss(Format('%s: %s here, %s upstream', [AWhat, AGot.AsJSON, w]));
  end
  else if Copy(w, 1, 2) = 'b:' then
  begin
    if (AGot.JSONType <> jtBoolean) or (BoolToStr(AGot.AsBoolean, 'true', 'false') <> Copy(w, 3, MaxInt)) then
      Miss(Format('%s: %s here, %s upstream', [AWhat, AGot.AsJSON, w]));
  end
  else if Copy(w, 1, 2) = 'j:' then
  begin
    jd := GetJSON(Copy(w, 3, MaxInt));
    try
      if AGot.AsJSON <> jd.AsJSON then
        Miss(Format('%s: %s here, %s upstream', [AWhat, AGot.AsJSON, w]));
    finally
      jd.Free;
    end;
  end
  else if (AGot.JSONType <> jtNumber) or not SameBits(AGot.AsFloat, FromHex(w)) then
    Miss(Format('%s: %s here, %s upstream', [AWhat, AGot.AsJSON, Fmt(FromHex(w))]));
end;

procedure TAdvChartDatasetTransformTest.CheckRows(const AWhat: string;
  ANode: TJSONObject; AWant: TJSONData);
var
  rows, want, wr, pairs: TJSONArray;
  r, c: Integer;
  got: TJSONData;
  obj: TJSONObject;
begin
  if IsNull(AWant) then Exit;   // a table of columns: no rows to list
  want := TJSONArray(AWant);
  rows := nil;
  if ANode.Find('source') is TJSONArray then rows := TJSONArray(ANode.Find('source'));
  if rows = nil then
  begin
    SameInt(AWhat + ' rows (no list here)', 0, want.Count);
    Exit;
  end;
  SameInt(AWhat + ' rows', rows.Count, want.Count);
  if rows.Count <> want.Count then Exit;
  for r := 0 to want.Count - 1 do
  begin
    got := rows.Items[r];
    if IsNull(want.Items[r]) then
    begin
      Inc(FCompared);
      if not IsNull(got) then Miss(Format('%s row %d: not null here', [AWhat, r]));
      Continue;
    end;
    if want.Items[r] is TJSONObject then
    begin
      pairs := TJSONObject(want.Items[r]).Arrays['o'];
      Inc(FCompared);
      if not (got is TJSONObject) or (TJSONObject(got).Count <> pairs.Count) then
      begin
        Miss(Format('%s row %d: %s here', [AWhat, r, got.AsJSON]));
        Continue;
      end;
      obj := TJSONObject(got);
      for c := 0 to pairs.Count - 1 do
      begin
        SameStr(Format('%s row %d key %d', [AWhat, r, c]), obj.Names[c],
          pairs.Arrays[c].Strings[0]);
        CheckCell(Format('%s row %d .%s', [AWhat, r, obj.Names[c]]), obj.Items[c],
          pairs.Arrays[c].Items[1]);
      end;
      Continue;
    end;
    if want.Items[r] is TJSONArray then
    begin
      wr := TJSONArray(want.Items[r]);
      Inc(FCompared);
      if not (got is TJSONArray) or (TJSONArray(got).Count <> wr.Count) then
      begin
        Miss(Format('%s row %d: %s here, %s upstream', [AWhat, r, got.AsJSON, wr.AsJSON]));
        Continue;
      end;
      for c := 0 to wr.Count - 1 do
        CheckCell(Format('%s row %d cell %d', [AWhat, r, c]), TJSONArray(got).Items[c], wr.Items[c]);
      Continue;
    end;
    CheckCell(Format('%s row %d', [AWhat, r]), got, want.Items[r]);
  end;
end;

procedure TAdvChartDatasetTransformTest.CheckDatasets(ACase: TJSONObject);
var
  opt: TTyChartOption;
  cache: TTyDatasetCache;
  dss, res, dims: TJSONArray;
  ds, rec: TJSONObject;
  k, r, d, n: Integer;
  node: TJSONObject;
  fields: TTySourceFields;
  tag, nm: string;
begin
  opt := TTyChartOption.Create;
  cache := TTyDatasetCache.Create;
  try
    AssertTrue(FWhere + ': the option parses', opt.SetOptionText(ACase.Objects['option'].AsJSON));
    dss := ACase.Arrays['datasets'];
    for k := 0 to dss.Count - 1 do
    begin
      ds := dss.Objects[k];
      tag := Format('dataset %d', [k]);
      n := cache.ResultCount(opt, k);
      if not IsNull(ds.Find('error')) then
      begin
        { upstream threw: no table here, and a reason }
        Inc(FCompared);
        if (n <> 0) or (cache.ErrorOf(k) = '') then
          Miss(Format('%s: %d results and reason "%s" here, upstream threw "%s"',
            [tag, n, cache.ErrorOf(k), ds.Strings['error']]));
        Continue;
      end;
      SameStr(tag + ' reason', cache.ErrorOf(k), '');
      res := ds.Arrays['results'];
      SameInt(tag + ' results', n, res.Count);
      if n <> res.Count then Continue;
      for r := 0 to res.Count - 1 do
      begin
        rec := res.Objects[r];
        tag := Format('dataset %d result %d', [k, rec.Integers['r']]);
        node := cache.ResultNode(opt, k, rec.Integers['r']);
        if node = nil then
        begin
          Miss(tag + ': none here');
          Continue;
        end;
        Inc(FItems);
        fields := TySourceFieldsOf(node);
        SameStr(tag + ' format', FormatName(fields.Format), rec.Strings['format']);
        Inc(FCompared);
        if cache.ResultIsClone(opt, k, rec.Integers['r']) <> rec.Booleans['clone'] then
          Miss(tag + ': the copy flag');
        SameInt(tag + ' startIndex', fields.StartIndex, rec.Integers['startIndex']);
        if IsNull(rec.Find('detected')) then
          SameInt(tag + ' detected', fields.DetectedCount, -1)
        else
          SameInt(tag + ' detected', fields.DetectedCount, rec.Integers['detected']);
        Inc(FCompared);
        if IsNull(rec.Find('dims')) then
        begin
          if fields.DimsDefined then Miss(tag + ': dimensions here, none upstream');
        end
        else
        begin
          dims := rec.Arrays['dims'];
          if not fields.DimsDefined or (Length(fields.Dims) <> dims.Count) then
            Miss(Format('%s: %d dimensions here, %s upstream', [tag, Length(fields.Dims), dims.AsJSON]))
          else
            for d := 0 to dims.Count - 1 do
            begin
              if fields.Dims[d].HasName then nm := fields.Dims[d].Name else nm := '<none>';
              if IsNull(dims.Items[d]) then SameStr(Format('%s dim %d', [tag, d]), nm, '<none>')
              else SameStr(Format('%s dim %d', [tag, d]), nm, dims.Strings[d]);
            end;
        end;
        CheckRows(tag, node, rec.Find('rows'));
      end;
    end;
  finally
    cache.Free;
    opt.Free;
  end;
end;

procedure TAdvChartDatasetTransformTest.TestEveryTableIsUpstreamsTable;
var
  i, n: Integer;
  c: TJSONObject;
begin
  n := 0;
  FCells := 0;
  FItems := 0;
  for i := 0 to Cases.Count - 1 do
  begin
    c := Cases.Objects[i];
    if (c.Strings['group'] = 'error') or (c.Find('deviation') <> nil)
      or (c.Find('datasets') = nil) then Continue;
    FWhere := c.Strings['id'];
    CheckDatasets(c);
    Inc(n);
  end;
  AssertTrue('the table cases', n >= 80);
  AssertTrue('the results', FItems >= 190);
  AssertTrue('the cells', FCells >= 12000);
  Finish('tables');
end;

procedure TAdvChartDatasetTransformTest.TestEveryThrowLeavesNoTable;
var
  i, n: Integer;
  c: TJSONObject;
  opt: TTyChartOption;
  cache: TTyDatasetCache;
begin
  n := 0;
  for i := 0 to Cases.Count - 1 do
  begin
    c := Cases.Objects[i];
    if c.Strings['group'] <> 'error' then Continue;
    FWhere := c.Strings['id'];
    Inc(n);
    if c.Find('optionError') <> nil then
    begin
      { upstream refuses the whole option; here dataset 1 has no table }
      opt := TTyChartOption.Create;
      cache := TTyDatasetCache.Create;
      try
        AssertTrue(FWhere + ': the option parses', opt.SetOptionText(c.Objects['option'].AsJSON));
        SameInt('dataset 1 results', cache.ResultCount(opt, 1), 0);
        Inc(FCompared);
        if cache.ErrorOf(1) = '' then Miss('no reason here');
      finally
        cache.Free;
        opt.Free;
      end;
      Continue;
    end;
    CheckDatasets(c);
  end;
  AssertTrue('the error cases', n >= 35);
  Finish('throws');
end;

procedure TAdvChartDatasetTransformTest.CheckSeries(ASeries: TJSONObject);
var
  si, k, i, n, d: Integer;
  typ, tag: string;
  items, labs: TJSONArray;
  it: TJSONArray;
  lst: TTyPaintList;
  e: TTyChartElement;
  b: TTyRectF;
  x, y, w, h, cl, cr, ct, cb: Double;
  g: TTyXYWH;
  pts: TTyPointFArray;
  found: Boolean;
  want: array of Integer;
begin
  si := ASeries.Integers['index'];
  typ := ASeries.Strings['type'];
  items := ASeries.Arrays['items'];
  lst := FChart.List;
  tag := Format('s%d %s', [si, typ]);
  if lst = nil then
  begin
    Miss(tag + ': no paint list');
    Exit;
  end;
  if typ = 'bar' then
  begin
    g := FChart.Build.Grid(0).PlotXYWH;
    for k := 0 to items.Count - 1 do
    begin
      if IsNull(items.Items[k]) then Continue;
      it := TJSONArray(items.Items[k]);
      x := FromHex(it.Strings[0]);
      y := FromHex(it.Strings[1]);
      w := FromHex(it.Strings[2]);
      h := FromHex(it.Strings[3]);
      if IsNan(x) or IsNan(y) or IsNan(w) or IsNan(h) then Continue;
      { the layout as the grid clips it }
      cl := Max(Min(x, x + w), g.X);
      cr := Min(Max(x, x + w), g.X + g.W);
      ct := Max(Min(y, y + h), g.Y);
      cb := Min(Max(y, y + h), g.Y + g.H);
      if (cr <= cl) or (cb <= ct) then Continue;
      found := False;
      for i := 0 to lst.Count - 1 do
      begin
        e := lst.Element(i);
        if e.Datum.IsEdge or (e.Datum.SeriesIndex <> si) or (e.Datum.RawDataIndex <> k)
          or (e.Caption.FontSizeLogical > 0) or (e.Anim.Role = carLabel) then Continue;
        found := True;
        Inc(FItems);
        b := TyShapeBounds(e.Shape);
        Inc(FCompared);
        if (b.Left <> cl) or (b.Right <> cr) or (b.Top <> ct) or (b.Bottom <> cb) then
          Miss(Format('%s[%d] bar %s,%s %sx%s upstream, %s,%s..%s,%s here',
            [tag, k, Fmt(x), Fmt(y), Fmt(w), Fmt(h), Fmt(b.Left), Fmt(b.Top),
             Fmt(b.Right), Fmt(b.Bottom)]));
        Break;
      end;
      if not found then Miss(Format('%s[%d]: no bar here', [tag, k]));
    end;
  end
  else if typ = 'scatter' then
  begin
    n := 0;
    for i := 0 to lst.Count - 1 do
    begin
      e := lst.Element(i);
      if e.Datum.IsEdge or (e.Datum.SeriesIndex <> si) or (e.Datum.RawDataIndex < 0)
        or (e.Caption.FontSizeLogical > 0) or (e.Shape.Kind <> cskCircle) then Continue;
      k := e.Datum.RawDataIndex;
      if k >= items.Count then Continue;
      Inc(FItems);
      Same(Format('%s[%d] x', [tag, k]), e.Shape.CX, TJSONArray(items.Items[k]).Strings[0]);
      Same(Format('%s[%d] y', [tag, k]), e.Shape.CY, TJSONArray(items.Items[k]).Strings[1]);
      Inc(n);
    end;
    { a point that is not a number draws no symbol }
    want := nil;
    for k := 0 to items.Count - 1 do
    begin
      it := TJSONArray(items.Items[k]);
      if IsNan(FromHex(it.Strings[0])) or IsNan(FromHex(it.Strings[1])) then Continue;
      SetLength(want, Length(want) + 1);
    end;
    SameInt(tag + ' points', n, Length(want));
  end
  else if typ = 'line' then
  begin
    { the polyline, vertex by vertex, as singles: every run of two numbers
      or more is a segment -- a point that is not a number is a gap, and a
      point alone between two gaps draws no line }
    pts := nil;
    for i := 0 to lst.Count - 1 do
    begin
      e := lst.Element(i);
      if e.Datum.IsEdge or (e.Datum.SeriesIndex <> si) or (e.Datum.RawDataIndex <> -1)
        or e.Silent or (e.Shape.Kind <> cskPolyline) then Continue;
      n := Length(pts);
      SetLength(pts, n + Length(e.Shape.Points));
      for k := 0 to High(e.Shape.Points) do pts[n + k] := e.Shape.Points[k];
    end;
    want := nil;
    k := 0;
    while k < items.Count do
    begin
      i := k;
      while (i < items.Count) and not IsNan(FromHex(TJSONArray(items.Items[i]).Strings[0]))
        and not IsNan(FromHex(TJSONArray(items.Items[i]).Strings[1])) do Inc(i);
      if i - k >= 2 then
        for d := k to i - 1 do
        begin
          SetLength(want, Length(want) + 1);
          want[High(want)] := d;
        end;
      k := i + 1;
    end;
    SameInt(tag + ' vertices', Length(pts), Length(want));
    if Length(pts) = Length(want) then
      for k := 0 to High(want) do
      begin
        Inc(FItems);
        Inc(FCompared);
        it := TJSONArray(items.Items[want[k]]);
        if (pts[k].X <> Single(FromHex(it.Strings[0]))) or (pts[k].Y <> Single(FromHex(it.Strings[1]))) then
          Miss(Format('%s vertex %d is %s,%s here', [tag, want[k], Fmt(pts[k].X), Fmt(pts[k].Y)]));
      end;
  end
  else if typ = 'pie' then
  begin
    for k := 0 to items.Count - 1 do
    begin
      if IsNull(items.Items[k]) then Continue;
      it := TJSONArray(items.Items[k]);
      found := False;
      for i := 0 to lst.Count - 1 do
      begin
        e := lst.Element(i);
        if (e.Datum.SeriesIndex <> si) or (e.Datum.DataIndex <> k)
          or (e.Shape.Kind <> cskSector) then Continue;
        found := True;
        Inc(FItems);
        Same(Format('%s[%d] cx', [tag, k]), e.Shape.CX, it.Strings[0]);
        Same(Format('%s[%d] cy', [tag, k]), e.Shape.CY, it.Strings[1]);
        Same(Format('%s[%d] r0', [tag, k]), e.Shape.R0, it.Strings[2]);
        Same(Format('%s[%d] r', [tag, k]), e.Shape.R1, it.Strings[3]);
        Same(Format('%s[%d] start', [tag, k]), e.Shape.StartRad, it.Strings[4]);
        Same(Format('%s[%d] end', [tag, k]), e.Shape.EndRad, it.Strings[5]);
        Break;
      end;
      if not found then Miss(Format('%s[%d]: no sector here', [tag, k]));
    end;
  end;
  { the labels: each upstream text on its item, and no more here }
  labs := ASeries.Arrays['labels'];
  n := 0;
  for i := 0 to lst.Count - 1 do
    if (lst.Element(i).Anim.Role = carLabel) and (lst.Element(i).Datum.SeriesIndex = si) then Inc(n);
  SameInt(tag + ' labels', n, labs.Count);
  for k := 0 to labs.Count - 1 do
  begin
    d := labs.Objects[k].Integers['d'];
    found := False;
    for i := 0 to lst.Count - 1 do
    begin
      e := lst.Element(i);
      if (e.Anim.Role <> carLabel) or (e.Datum.SeriesIndex <> si) or (e.Datum.DataIndex <> d) then Continue;
      found := True;
      Inc(FLabels);
      SameStr(Format('%s[%d] label', [tag, d]), e.Caption.Text, labs.Objects[k].Strings['text']);
      Break;
    end;
    if not found then Miss(Format('%s[%d]: no label "%s" here', [tag, d, labs.Objects[k].Strings['text']]));
  end;
end;

procedure TAdvChartDatasetTransformTest.CheckRender(ACase: TJSONObject);
var
  rend: TJSONObject;
  arr, cats: TJSONArray;
  g: TTyXYWH;
  bmp: TBGRABitmap;
  i, k: Integer;
  ax: TTyAxis;
  cw, ch: Integer;
begin
  rend := ACase.Objects['render'];
  cw := TJSONObject(FRoot).Integers['W'];
  ch := TJSONObject(FRoot).Integers['H'];
  NewChart(ACase.Objects['option']);
  bmp := TBGRABitmap.Create(cw, ch, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, cw, ch), 96);
  finally
    bmp.Free;
  end;
  if not IsNull(rend.Find('rect')) then
  begin
    arr := rend.Arrays['rect'];
    g := FChart.Build.Grid(0).PlotXYWH;
    Same('grid x', g.X, arr.Strings[0]);
    Same('grid y', g.Y, arr.Strings[1]);
    Same('grid w', g.W, arr.Strings[2]);
    Same('grid h', g.H, arr.Strings[3]);
  end;
  arr := rend.Arrays['axes'];
  for i := 0 to arr.Count - 1 do
  begin
    if IsNull(arr.Objects[i].Find('categories')) then Continue;
    cats := arr.Objects[i].Arrays['categories'];
    ax := FChart.Build.Axis(arr.Objects[i].Strings['dim'] + 'Axis', arr.Objects[i].Integers['index']);
    Inc(FCompared);
    if (ax = nil) or (ax.Categories = nil) then
    begin
      Miss(arr.Objects[i].Strings['dim'] + ': no category axis here');
      Continue;
    end;
    SameInt(arr.Objects[i].Strings['dim'] + ' categories', ax.Categories.Count, cats.Count);
    if ax.Categories.Count = cats.Count then
      for k := 0 to cats.Count - 1 do
        SameStr(Format('%s category %d', [arr.Objects[i].Strings['dim'], k]),
          ax.Categories.CategoryAt(k), cats.Strings[k]);
  end;
  arr := rend.Arrays['series'];
  for i := 0 to arr.Count - 1 do CheckSeries(arr.Objects[i]);
end;

procedure TAdvChartDatasetTransformTest.TestSeriesOverTransformsDrawAsUpstream;
var
  i, n: Integer;
  c: TJSONObject;
begin
  n := 0;
  FItems := 0;
  FLabels := 0;
  for i := 0 to Cases.Count - 1 do
  begin
    c := Cases.Objects[i];
    if (c.Find('render') = nil) or (c.Objects['render'].Find('error') <> nil) then Continue;
    FWhere := c.Strings['id'];
    CheckRender(c);
    Inc(n);
  end;
  AssertTrue('the render cases', n >= 10);
  AssertTrue('the items', FItems >= 60);
  AssertTrue('the labels', FLabels >= 30);
  Finish('render');
end;

procedure TAdvChartDatasetTransformTest.TestRegIsRefusedWithAReason;
var
  c: TJSONObject;
  opt: TTyChartOption;
  cache: TTyDatasetCache;
begin
  c := CaseById('f-reg');
  AssertNotNull('the case', c);
  { upstream matches the expression: the header and six rows }
  AssertEquals('upstream kept rows', 7,
    c.Arrays['datasets'].Objects[1].Arrays['results'].Objects[0].Arrays['rows'].Count);
  opt := TTyChartOption.Create;
  cache := TTyDatasetCache.Create;
  try
    AssertTrue(opt.SetOptionText(c.Objects['option'].AsJSON));
    AssertNotNull('the root is there', cache.ResultNode(opt, 0, 0));
    AssertEquals('no table here', 0, cache.ResultCount(opt, 1));
    AssertEquals('and the reason', rsTyDsCondReg, cache.ErrorOf(1));
  finally
    cache.Free;
    opt.Free;
  end;
end;

procedure TAdvChartDatasetTransformTest.TestAFailingTransformIsADiagnostic;
var
  c, o: TJSONObject;
  i: Integer;
  all, want: string;
  bmp: TBGRABitmap;
begin
  c := CaseById('r-error');
  AssertNotNull('the case', c);
  AssertTrue('upstream refuses the option', c.Objects['render'].Find('error') <> nil);
  NewChart(c.Objects['option']);
  bmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, 600, 400), 96);
  finally
    bmp.Free;
  end;
  all := '';
  for i := 0 to FChart.DiagnosticCount - 1 do all := all + FChart.Diagnostic(i) + '|';
  want := Format(rsTyChartDatasetNoTable, [1, Format(rsTyDsUnknownType, ['nope'])]);
  AssertTrue('the diagnostic: ' + all, Pos(want, all) > 0);
  for i := 0 to FChart.List.Count - 1 do
    AssertFalse('the series draws nothing',
      (FChart.List.Element(i).Datum.SeriesIndex = 0) and (FChart.List.Element(i).Datum.RawDataIndex >= 0));
  { a dataset no series reads is not resolved and says nothing }
  o := TJSONObject(GetJSON('{"animation":false,"dataset":[{"source":[[1, 2]]},'
    + '{"transform":{"type":"nope"}}],"xAxis":{},"yAxis":{},'
    + '"series":[{"type":"scatter","datasetIndex":0}]}'));
  try
    NewChart(o);
  finally
    o.Free;
  end;
  bmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, 600, 400), 96);
  finally
    bmp.Free;
  end;
  for i := 0 to FChart.DiagnosticCount - 1 do
    AssertTrue('nothing about dataset 1', Pos('dataset[1]', FChart.Diagnostic(i)) = 0);
end;

procedure TAdvChartDatasetTransformTest.TestTheRegistryNamesItsTransforms;
var
  f: TTyDataTransformFunc;
  b: Boolean;
begin
  AssertFalse('no name', TyRegisterDataTransform('', @ScaleTransform));
  AssertFalse('no namespace', TyRegisterDataTransform('plain', @ScaleTransform));
  AssertFalse('two colons', TyRegisterDataTransform('a:b:c', @ScaleTransform));
  AssertFalse('nothing to call', TyRegisterDataTransform('ns:none', nil));
  AssertTrue('filter is a built-in', TyFindDataTransform('filter', f, b) and b);
  AssertTrue('sort is a built-in', TyFindDataTransform('sort', f, b) and b);
  AssertTrue('boxplot is a built-in', TyFindDataTransform('boxplot', f, b) and b);
  AssertFalse('a built-in is called without its namespace', TyFindDataTransform('echarts:filter', f, b));
  AssertTrue('an outside one keeps its namespace', TyFindDataTransform('test:scale', f, b) and not b);
  AssertFalse('and is not found without it', TyFindDataTransform('scale', f, b));
  AssertTrue(TyRegisterDataTransform('echarts:d2probe', @PairsTransform));
  AssertTrue(TyFindDataTransform('d2probe', f, b) and b);
  AssertTrue('the first', f = @PairsTransform);
  AssertTrue(TyRegisterDataTransform('echarts:d2probe', @ScaleTransform));
  AssertTrue(TyFindDataTransform('d2probe', f, b));
  AssertTrue('a second registration replaces the first', f = @ScaleTransform);
end;

type
  TKeyCmp = class
  public
    Keys: TTyIntegerArray;
    function Compare(A, B: Integer): Integer;
  end;

function TKeyCmp.Compare(A, B: Integer): Integer;
begin
  Result := Keys[A] - Keys[B];
end;

procedure TAdvChartDatasetTransformTest.TestTheSortIsStableForAConsistentComparator;
var
  cmp: TKeyCmp;
  got, want: TTyIntegerArray;
  n, i, j, t, key, trial, range: Integer;
  x: LongWord;

  procedure Step;
  begin
    x := x xor (x shl 13);
    x := x xor (x shr 17);
    x := x xor (x shl 5);
  end;

begin
  cmp := TKeyCmp.Create;
  try
    x := 2463534242;
    for trial := 0 to 199 do
    begin
      { a size from 0 to 700 and few or many distinct keys }
      Step;
      n := Integer(x mod 701);
      Step;
      range := 1 + Integer(x mod 50);
      if trial mod 4 = 0 then range := n + 1;
      SetLength(cmp.Keys, n);
      SetLength(got, n);
      for i := 0 to n - 1 do
      begin
        Step;
        key := Integer(x mod LongWord(range));
        { long ascending or descending stretches, for the galloping }
        if trial mod 5 = 1 then key := (i div 37) * 3 + key mod 3
        else if trial mod 5 = 2 then key := n - i + key mod 2;
        cmp.Keys[i] := key;
        got[i] := i;
      end;
      want := Copy(got, 0, n);
      { a plain stable insertion sort }
      for i := 1 to n - 1 do
      begin
        t := want[i];
        j := i - 1;
        while (j >= 0) and (cmp.Keys[want[j]] > cmp.Keys[t]) do
        begin
          want[j + 1] := want[j];
          Dec(j);
        end;
        want[j + 1] := t;
      end;
      TyJsArraySort(got, @cmp.Compare);
      for i := 0 to n - 1 do
        if got[i] <> want[i] then
          Fail(Format('trial %d (n %d, %d keys): position %d holds %d, a stable sort %d',
            [trial, n, range, i, got[i], want[i]]));
    end;
  finally
    cmp.Free;
  end;
end;

initialization
  TyRegisterDataTransform('test:scale', @ScaleTransform);
  TyRegisterDataTransform('test:pairs', @PairsTransform);
  TyRegisterDataTransform('test:raw', @RawTransform);
  RegisterTest(TAdvChartDatasetTransformTest);
end.
