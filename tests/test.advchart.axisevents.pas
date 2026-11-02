unit test.advchart.axisevents;
{$mode objfpc}{$H+}
{ WHAT AN AXIS' PART TELLS A MOUSE EVENT, held to upstream. [R7-I]

  tests/fixtures/advchart-axis-events.json, from the real ECharts 6.1 build
  (tools/advchart-oracle/axis-events.js): per case, every axis text that
  carries an eventData (triggerEvent), probed at the centre of its rect
  where findHover finds that text, and the eventData there --
  makeAxisEventDataBase (componentType, componentIndex, <mainType>Index)
  and the part's own: an AxisBuilder's name (targetType 'axisName', the
  name as the builder took it, before truncation) and labels (targetType
  'axisLabel', value the rawLabel -- scale.getLabel of the tick, not the
  text the formatter made --, tickIndex its index among the axis' labels,
  dataIndex on a category axis), an angle axis' labels (value, nothing
  else), a radar's indicators (the radar's index; the name as
  axisName.formatter made it; the indicator's own triggerEvent over the
  radar's).

  A text that answers the pointer without triggerEvent (a single axis'
  by default, tooltip.show, an indicator's own tooltip.show) is probed too
  and carries no eventData ('quiet').

  TestTheEventDataAsUpstream: EventTargetAt at each probe, its params
  written as the oracle's keys. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Handlers,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TAxisEventsProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function EventLineAt(AX, AY: Integer): string;
  end;

  TAdvChartAxisEventsOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FChart: TAxisEventsProbe;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheEventDataAsUpstream;
  end;

implementation

const
  cW = 400;
  cH = 300;

function TAxisEventsProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TAxisEventsProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function Field(const AKey, AValue: string): string;
begin
  Result := AKey + '=' + AValue + ';';
end;

{ the target's eventData as the oracle's keys, in their order }
function TAxisEventsProbe.EventLineAt(AX, AY: Integer): string;
var
  t: TTyChartEventTarget;
  p: TTyChartCallbackParams;
begin
  t := EventTargetAt(AX, AY);
  if t.Id = 0 then Exit('none');
  { a part found, no eventData: no series' item either }
  if not t.HasData then
  begin
    if t.HdKind in [1, 2, 16, 31] then Exit('a series');
    Exit('quiet');
  end;
  p := t.Params;
  Result := Field('componentType', p.ComponentType)
    + Field('componentIndex', IntToStr(p.ComponentIndex))
    + Field(p.ComponentType + 'Index', IntToStr(p.AxisIndex))
    + Field('targetType', p.TargetType);
  if p.TargetType = 'axisName' then Result := Result + Field('name', p.Name);
  if p.TargetType = 'axisLabel' then Result := Result + Field('value', p.ValueText);
  if p.TickIndex >= 0 then Result := Result + Field('tickIndex', IntToStr(p.TickIndex));
  if p.DataIndex >= 0 then Result := Result + Field('dataIndex', IntToStr(p.DataIndex));
end;

function UpstreamLine(AEv: TJSONData): string;
var
  ct: string;
  d: TJSONData;
  E: TJSONObject;

  procedure Add(const AKey: string);
  begin
    d := E.Find(AKey);
    if (d = nil) or (d.JSONType = jtNull) then Exit;
    if d.JSONType = jtNumber then Result := Result + Field(AKey, IntToStr(Round(d.AsFloat)))
    else Result := Result + Field(AKey, d.AsString);
  end;

begin
  if not (AEv is TJSONObject) then Exit('quiet');
  E := TJSONObject(AEv);
  Result := '';
  ct := E.Strings['componentType'];
  Add('componentType');
  Add('componentIndex');
  Add(ct + 'Index');
  Add('targetType');
  Add('name');
  Add('value');
  Add('tickIndex');
  Add('dataIndex');
end;

function LoadJson(const AName: string): TJSONData;
var sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + AName);
    Result := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
end;

procedure TAdvChartAxisEventsOracleTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  FMeasure := LoadJson('advchart-text-style.json');
end;

procedure TAdvChartAxisEventsOracleTest.TearDown;
begin
  FreeAndNil(FChart);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FBmp);
  FreeAndNil(FMeasure);
  inherited TearDown;
end;

procedure TAdvChartAxisEventsOracleTest.TestTheEventDataAsUpstream;
var
  fix: TJSONData;
  cs, probes: TJSONArray;
  c, p: TJSONObject;
  i, k, nBad, nCmp: Integer;
  id, want, have, bad: string;
begin
  fix := LoadJson('advchart-axis-events.json');
  nBad := 0;
  nCmp := 0;
  bad := '';
  try
    cs := TJSONObject(fix).Arrays['charts'];
    for i := 0 to cs.Count - 1 do
    begin
      c := cs.Objects[i];
      id := c.Strings['id'];
      FreeAndNil(FChart);
      FChart := TAxisEventsProbe.Create(FForm);
      FChart.Parent := FForm;
      FChart.Controller := FCtl;
      FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
        TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
        TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
      FChart.SetBounds(0, 0, cW, cH);
      FChart.Option := c.Objects['option'].AsJSON;
      AssertEquals(id + ' parses', '', FChart.OptionError);
      FBmp.Fill(BGRA(255, 255, 255, 255));
      FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
      probes := c.Arrays['probes'];
      for k := 0 to probes.Count - 1 do
      begin
        p := probes.Objects[k];
        want := UpstreamLine(p.Find('ev'));
        have := FChart.EventLineAt(p.Integers['x'], p.Integers['y']);
        Inc(nCmp);
        if have <> want then
        begin
          Inc(nBad);
          if Length(bad) < 6000 then
            bad := bad + LineEnding + Format('  %s %s (%d,%d): %s; upstream %s',
              [id, p.Strings['own'], p.Integers['x'], p.Integers['y'], have, want]);
        end;
      end;
    end;
  finally
    fix.Free;
  end;
  AssertTrue(Format('enough was compared (%d)', [nCmp]), nCmp >= 80);
  AssertEquals(IntToStr(nBad) + ' of ' + IntToStr(nCmp) + ' differ:' + bad, 0, nBad);
end;

initialization
  RegisterTest(TAdvChartAxisEventsOracleTest);
end.
