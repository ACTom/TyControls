unit test.advchart.tooltipparams;
{$mode objfpc}{$H+}
{ WHAT A TOOLTIP FORMATTER IS GIVEN OVER A SUNBURST, A TREEMAP AND A
  SANKEY, HELD TO UPSTREAM [fix batch R2-E].

  tools/advchart-oracle/tooltip-params.js runs the real ECharts 6.1 build in
  node: the tooltip's formatter is a function that keeps what it is given,
  the pointer goes onto a node (an edge) through zrender's Handler. The
  series' own getDataParams: a sunburst's and a treemap's treePathInfo
  (from the virtual root, named as the series, down to the node; each value
  the one completeTreeValue settled), a sankey node's layout value where it
  wrote none, an edge's `source > target` name and its own value.

  This replays every aim through TTyAdvanceChart's MouseMove with the
  formatter a registered handler, and compares the last params it was
  given: componentType, componentSubType, componentIndex, seriesType,
  seriesIndex, seriesName, seriesId (where the option wrote one), name,
  dataIndex, dataType (upstream's 'main' is the port's ''), the value as
  String() prints it, and treePathInfo key by key. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Events, tyControls.AdvanceChart.Handlers,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax, test.advchart.tooltipactions;
type
  TAdvChartTooltipParamsOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FRoot, FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared: Integer;
    FReport, FWhere: string;
    FHas: Boolean;
    FLast: TTyChartCallbackParams;
    function TipParams(const AParams: TTyChartParams): string;
    procedure Bad(const AWhat: string);
    procedure SameText_(const AWhat, AGot, AWant: string);
    function Ssr: ITyTextMeasurer;
    procedure RunCase(const AId: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestASunburstsParamsAsUpstream;
    procedure TestATreemapsParamsAsUpstream;
    procedure TestASankeysParamsAsUpstream;
  end;

implementation

const
  cW = 600;
  cH = 400;
  cNulMark = #$E2#$90#$80;

function FixturePath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + AName;
end;

function SameJson(AWant, AGot: TJSONData): Boolean;
var
  i: Integer;
  wo, go: TJSONObject;
begin
  Result := False;
  if (AWant = nil) or (AGot = nil) then Exit(AWant = AGot);
  if AWant.JSONType <> AGot.JSONType then Exit;
  case AWant.JSONType of
    jtNull: Result := True;
    jtBoolean: Result := AWant.AsBoolean = AGot.AsBoolean;
    jtNumber: Result := AWant.AsFloat = AGot.AsFloat;
    jtString: Result := AWant.AsString = AGot.AsString;
    jtArray:
      begin
        if AWant.Count <> AGot.Count then Exit;
        for i := 0 to AWant.Count - 1 do
          if not SameJson(TJSONArray(AWant).Items[i], TJSONArray(AGot).Items[i]) then Exit;
        Result := True;
      end;
    jtObject:
      begin
        wo := TJSONObject(AWant);
        go := TJSONObject(AGot);
        if wo.Count <> go.Count then Exit;
        for i := 0 to wo.Count - 1 do
        begin
          if go.IndexOfName(wo.Names[i]) < 0 then Exit;
          if not SameJson(wo.Items[i], go.Find(wo.Names[i])) then Exit;
        end;
        Result := True;
      end;
  end;
end;

function Nul(const A: string): string;
begin
  Result := StringReplace(A, #0, cNulMark, [rfReplaceAll]);
end;

procedure TAdvChartTooltipParamsOracleTest.SetUp;
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
    sl.LoadFromFile(FixturePath('advchart-tooltip-params.json'));
    FRoot := GetJSON(sl.Text);
    sl.LoadFromFile(FixturePath('advchart-text-style.json'));
    FMeasure := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  TyChartRegisterFormatter('tipParams', @TipParams);
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartTooltipParamsOracleTest.TearDown;
begin
  TyChartUnregisterFormatter('tipParams');
  FRoot.Free;
  FMeasure.Free;
  FBmp.Free;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

function TAdvChartTooltipParamsOracleTest.TipParams(const AParams: TTyChartParams): string;
begin
  FHas := Length(AParams) > 0;
  if FHas then FLast := AParams[0];
  Result := 'tip';
end;

function TAdvChartTooltipParamsOracleTest.Ssr: ITyTextMeasurer;
begin
  Result := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
end;

procedure TAdvChartTooltipParamsOracleTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 20000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TAdvChartTooltipParamsOracleTest.SameText_(const AWhat, AGot, AWant: string);
begin
  Inc(FCompared);
  if AGot <> AWant then Bad(Format('%s %s, upstream %s', [AWhat, AGot, AWant]));
end;

procedure TAdvChartTooltipParamsOracleTest.RunCase(const AId: string);
var
  cases, steps: TJSONArray;
  cs, st, p: TJSONObject;
  i, j: Integer;
  chart: TTaProbe;
  want, got: TJSONData;
  dt: string;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  cs := nil;
  for i := 0 to cases.Count - 1 do
    if cases.Objects[i].Strings['id'] = AId then cs := cases.Objects[i];
  AssertTrue('no case ' + AId, cs <> nil);
  chart := TTaProbe.Create(FForm);
  try
    chart.Parent := FForm;
    chart.Controller := FCtl;
    chart.Measurer := Ssr;
    chart.TooltipNow := 0;
    chart.SetBounds(0, 0, cW, cH);
    chart.Option := cs.Objects['option'].AsJSON;
    chart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
    steps := cs.Arrays['steps'];
    for j := 0 to steps.Count - 1 do
    begin
      st := steps.Objects[j];
      p := st.Objects['params'];
      FWhere := Format('%s %s', [AId, st.Strings['aim']]);
      { off everything, then onto the item: a new show }
      chart.Leave;
      chart.TooltipNow := (j + 1) * 1000;
      chart.TooltipTick((j + 1) * 1000);
      chart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
      FHas := False;
      chart.Move(st.Arrays['at'].Integers[0], st.Arrays['at'].Integers[1]);
      chart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
      Inc(FCompared);
      if not FHas then
      begin
        Bad('the formatter was not called');
        Continue;
      end;
      SameText_('componentType', FLast.ComponentType, p.Strings['componentType']);
      SameText_('componentSubType', FLast.ComponentSubType, p.Strings['componentSubType']);
      SameText_('componentIndex', IntToStr(FLast.ComponentIndex), IntToStr(p.Integers['componentIndex']));
      SameText_('seriesType', FLast.SeriesType, p.Strings['seriesType']);
      SameText_('seriesIndex', IntToStr(FLast.SeriesIndex), IntToStr(p.Integers['seriesIndex']));
      SameText_('seriesName', Nul(FLast.SeriesName), p.Strings['seriesName']);
      { an id the option wrote; upstream's own (NUL-led) the port does not
        make up }
      if Pos(cNulMark, p.Strings['seriesId']) = 0 then
        SameText_('seriesId', FLast.SeriesId, p.Strings['seriesId']);
      SameText_('name', Nul(FLast.Name), p.Strings['name']);
      SameText_('dataIndex', IntToStr(FLast.DataIndex), IntToStr(p.Integers['dataIndex']));
      dt := p.Strings['dataType'];
      if dt = 'main' then dt := '';
      SameText_('dataType', FLast.DataType, dt);
      SameText_('value', FLast.ValueText, p.Strings['valueText']);
      want := p.Find('treePathInfo');
      Inc(FCompared);
      if (want = nil) or (want.JSONType = jtNull) then
      begin
        if FLast.TreePathInfo <> '' then
          Bad('treePathInfo ' + FLast.TreePathInfo + ', upstream none');
        Continue;
      end;
      if FLast.TreePathInfo = '' then
      begin
        Bad('no treePathInfo, upstream ' + want.AsJSON);
        Continue;
      end;
      got := GetJSON(Nul(FLast.TreePathInfo));
      try
        if not SameJson(want, got) then
          Bad('treePathInfo ' + got.AsJSON + ', upstream ' + want.AsJSON);
      finally
        got.Free;
      end;
    end;
  finally
    chart.Free;
  end;
  if GetEnvironmentVariable('TY_TOOLTIPPARAMS_COUNTS') = '1' then
    WriteLn(StdErr, AId, ': ', FCompared, ' comparisons');
  AssertTrue(AId + ': nothing compared', FCompared > 0);
  AssertEquals(Format('%s: %d of %d comparisons differ:%s', [AId, FBad, FCompared, FReport]), 0, FBad);
end;

procedure TAdvChartTooltipParamsOracleTest.TestASunburstsParamsAsUpstream;
begin
  RunCase('sunburst');
end;

procedure TAdvChartTooltipParamsOracleTest.TestATreemapsParamsAsUpstream;
begin
  RunCase('treemap');
end;

procedure TAdvChartTooltipParamsOracleTest.TestASankeysParamsAsUpstream;
begin
  RunCase('sankey');
end;

initialization
  RegisterTest(TAdvChartTooltipParamsOracleTest);
end.
