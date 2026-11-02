unit test.advchart.axisstringsize;
{$mode objfpc}{$H+}
{ [R7-L] AN AXIS LABEL WHOSE SIZE IS WRITTEN AS A STRING, over a box, held to
  ECharts 6.1: zrender lays the plate out at NaN (x + '50%0'), the label's
  box is NaN on that axis, and BoundingRect.intersect -- every comparison
  with NaN false -- makes two labels meet wherever their other axis does.
  fixMinMaxLabelShow and axisLabel.hideOverlap hide labels by it, and a
  name a NaN box moves is left at NaN (not drawn).

  tools/advchart-oracle/axis-string-size.js records, per case, which of the
  axis labels each axis shows, whether each name is placed at a finite
  point, and grid 0's rect. Where that rect is NaN (outerBoundsMode 'auto'
  or 'same': the outer bounds shrink by a NaN overflow) the series, axis
  lines and names are NaN upstream, and which labels show follows from
  that grid; the port lays the grid out on the labels it draws -- such an
  axis is not compared, only counted as left (user doc section 12).

  Measured with zrender's SSR width table, as test.advchart.richwiring. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms,
     tyControls.Controller, tyControls.Types,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint,
     tyControls.AdvanceChart.Layout, tyControls.AdvanceChart.Builder,
     tyControls.AdvanceChart.Coord, tyControls.AdvanceChart.LabelLayout,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TAsProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TAdvChartAxisStringSizeOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TAsProbe;
    FRoot: TJSONData;
    FBmp: TBitmap;
    FBad, FCompared, FLeft, FHidden, FNaNNames: Integer;
    FReport: string;
    procedure Miss(const AWhat: string);
    procedure RunCase(ACase: TJSONObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheLabelsAndNamesAsUpstream;
    procedure TestALabelLayoutAtNaNLeavesTheHostsTrapsAlone;
  end;

implementation

function TAsProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer = nil then Exit(inherited NewTextMeasurer(APPI));
  Result := Measurer;
end;

procedure TAsProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-axis-string-size.json';
end;

procedure TAdvChartAxisStringSizeOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TAsProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := TBitmap.Create;
  FBmp.SetSize(600, 400);
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FRoot).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FRoot).Objects['ratios'].Integers['firstCode']));
  FBad := 0;
  FCompared := 0;
  FLeft := 0;
  FHidden := 0;
  FNaNNames := 0;
  FReport := '';
end;

procedure TAdvChartAxisStringSizeOracleTest.TearDown;
begin
  FChart.Measurer := nil;
  FRoot.Free;
  FBmp.Free;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

procedure TAdvChartAxisStringSizeOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 80 then FReport := FReport + LineEnding + '  ' + AWhat;
end;

procedure TAdvChartAxisStringSizeOracleTest.RunCase(ACase: TJSONObject);
var
  gb: TTyGridBuild;
  axes: TJSONArray;
  a, lb, nm: TJSONObject;
  i, k, q: Integer;
  ax: TTyAxis;
  spec: PTyAxisLayoutSpec;
  used: array of Boolean;
  found, gridNaN: Boolean;
  where: string;
begin
  FChart.Option := ACase.Objects['option'].AsJSON;
  FChart.SetBounds(0, 0, ACase.Integers['W'], ACase.Integers['H']);
  FChart.Render(FBmp.Canvas, Rect(0, 0, ACase.Integers['W'], ACase.Integers['H']), 96);
  gridNaN := ACase.Booleans['gridNaN'];
  if (FChart.Build = nil) or (FChart.Build.GridCount = 0) then
  begin
    Miss(ACase.Strings['name'] + ': no grid built');
    Exit;
  end;
  gb := FChart.Build.Grid(0);
  axes := ACase.Arrays['axes'];
  for i := 0 to axes.Count - 1 do
  begin
    a := axes.Objects[i];
    if a.Strings['axis'] = 'xAxis0' then ax := gb.XAxis(0)
    else ax := gb.YAxis(0);
    where := ACase.Strings['name'] + ' ' + a.Strings['axis'];
    if gridNaN then
    begin
      Inc(FLeft);
      Continue;
    end;
    spec := gb.SpecFor(ax);
    if spec = nil then
    begin
      Miss(where + ': no axis here');
      Continue;
    end;
    { every label upstream built, by its text, shown or hidden as there }
    SetLength(used, Length(spec^.Placements));
    for q := 0 to High(used) do used[q] := False;
    for k := 0 to a.Arrays['labels'].Count - 1 do
    begin
      lb := a.Arrays['labels'].Objects[k];
      found := False;
      for q := 0 to High(spec^.Placements) do
        if not used[q] and (spec^.Placements[q].Text = lb.Strings['text']) then
        begin
          used[q] := True;
          found := True;
          Inc(FCompared);
          if spec^.Placements[q].Shown <> lb.Booleans['shown'] then
            Miss(Format('%s label "%s": shown %s upstream, %s here', [where,
              lb.Strings['text'], BoolToStr(lb.Booleans['shown'], True),
              BoolToStr(spec^.Placements[q].Shown, True)]));
          if not lb.Booleans['shown'] then Inc(FHidden);
          Break;
        end;
      if not found and lb.Booleans['shown'] then
        Miss(Format('%s label "%s": shown upstream, not built here', [where,
          lb.Strings['text']]));
    end;
    { the name: drawn where upstream placed it at a finite point }
    if (a.Find('name') = nil) or (a.Find('name').JSONType <> jtObject) then Continue;
    nm := a.Objects['name'];
    Inc(FCompared);
    if not nm.Booleans['placed'] then Inc(FNaNNames);
    if spec^.NamePlacement.Shown <> nm.Booleans['placed'] then
      Miss(Format('%s name "%s": placed %s upstream, drawn %s here', [where,
        nm.Strings['text'], BoolToStr(nm.Booleans['placed'], True),
        BoolToStr(spec^.NamePlacement.Shown, True)]));
  end;
end;

procedure TAdvChartAxisStringSizeOracleTest.TestTheLabelsAndNamesAsUpstream;
var
  cases: TJSONArray;
  c: Integer;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
    RunCase(cases.Objects[c]);
  AssertTrue(Format('%d of %d differ from upstream:%s', [FBad, FCompared, FReport]),
    FBad = 0);
  { reached: the hidden ends, a name at NaN, the grids left }
  AssertTrue(Format('only %d compared', [FCompared]), FCompared >= 60);
  AssertTrue(Format('only %d hidden labels', [FHidden]), FHidden >= 9);
  AssertTrue(Format('%d names at NaN', [FNaNNames]), FNaNNames >= 1);
  AssertEquals('axes left to the grid at NaN', 4, FLeft);
end;

{ A LAYOUT AT NaN MASKS THE TRAPS AND HANDS THEM BACK CLEAN: the host's
  division by zero is still EZeroDivide (the sticky SSE flags cleared) }
function DivideByZero: string;
var zero, r: Double;
begin
  zero := 0;
  Result := '';
  try
    r := 1 / zero;
    Result := 'nothing, ' + FloatToStr(r);
  except
    on E: Exception do Result := E.ClassName;
  end;
end;

procedure TAdvChartAxisStringSizeOracleTest.TestALabelLayoutAtNaNLeavesTheHostsTrapsAlone;
var
  items: TTyLabelLayoutItemArray;
  i: Integer;
  cases: TJSONArray;
begin
  SetLength(items, 2);
  for i := 0 to 1 do
  begin
    items[i] := Default(TTyLabelLayoutItem);
    items[i].RawLocal := TyXYWH(-10, -6, 20, 12);
    items[i].InnerX := 100 + i * 50;
    items[i].InnerY := 100;
    items[i].ScaleX := 1;
    items[i].ScaleY := 1;
    items[i].LabelX := items[i].InnerX;
    items[i].LabelY := 100;
    items[i].HideOverlap := True;
    items[i].Move := tlmShiftX;
  end;
  items[1].RawLocal.X := NaN;
  TyLayoutLabels(items, 0, 0, 600, 400);
  AssertTrue('the label at NaN is hidden behind the one at its height', items[1].Ignore);
  AssertFalse('the first is kept', items[0].Ignore);
  AssertEquals('the host''s division by zero after the label layout', 'EZeroDivide',
    DivideByZero);
  { and after an axis whose labels' boxes are at NaN (the ends, the names) }
  cases := TJSONObject(FRoot).Arrays['cases'];
  for i := 0 to cases.Count - 1 do
    if cases.Objects[i].Strings['name'] = 'y-word-none' then
      RunCase(cases.Objects[i]);
  AssertEquals('the case ran clean', 0, FBad);
  AssertEquals('the host''s division by zero after the axes', 'EZeroDivide',
    DivideByZero);
end;

initialization
  RegisterTest(TAdvChartAxisStringSizeOracleTest);
end.
