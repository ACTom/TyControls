unit test.advchart.select;
{$mode objfpc}{$H+}
{ SELECTION, HELD TO UPSTREAM [Batch 88].

  tools/advchart-oracle/select-legend.js drives the real ECharts 6.1 build
  through scripted steps -- pointer moves, clicks (move, down, up, click at
  one point, then one frame) and dispatchAction -- and records, after every
  frame, the events published (in order, with their payloads) and every data
  item's state: the flags (hoverState, selected, __highByOuter), the state
  list zrender applied, z2, fill / stroke / lineWidth / opacity, a slice's
  translation and radius, a symbol's scale, and its label and label line.

  This replays the selection batch's cases through the control's own paths:
  MouseMove / MouseDown / MouseUp for the pointer and DispatchAction for the
  actions, a render after every step (the frame). It compares:
    the events -- type and order, every payload field of an action event
      (the legacy pie / map events included), and the click's params;
    each series' selectedMap (key order too) and getSelectedDataIndices;
    each item's state list, flags and proxy;
    what is DRAWN, from the display list: the mark's fill / stroke / width /
      opacity, its z2 against its rest z2, a slice's offset, radius and
      angles, a bar's rect, a symbol's centre and scale, a label's place,
      visibility, ink and z2, a label line's offset, a line's polyline.
  Colours are the skin's: a fixture colour that is the item's rest colour is
  the port's rest colour, its lift is the lift of the port's, the select
  border tokens.color.primary is the skin's title ink, any other colour is
  the declared one and compared exactly. z2 is compared as the distance from
  rest (the port's rest z2 are its own). Geometry the state machine computes
  (the select offset, the emphasis radius, the symbol scale) is compared bit
  for bit on the machine's values; positions read back from the display list
  to 1e-9 (an offset added to a centre is not always the offset again).

  The highlight / blur and legend cases of the same fixture are B2's and
  B3's. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint,
     tyControls.AdvChart.Shape,
     tyControls.AdvChart.Handlers, tyControls.AdvChart.Events,
     tyControls.AdvChart.Style, tyControls.AdvChart.Color,
     tyControls.AdvChart.States,
     tyControls.AdvChart.Measure, tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TSelProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Move(AX, AY: Integer);
    procedure ClickAt(AX, AY: Integer);
    function List: TTyPaintList;
    function Primary: TTyChartColor;
    function HoverSeries: Integer;
    function HoverRow: Integer;
  end;

  TSelLogger = class
  public
    Log: TStrings;
    Payloads: TList;
    procedure Handle(Sender: TObject; const AEvent: TTyChartEvent);
  end;

  TAdvChartSelectOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TSelProbe;
    FRoot: TJSONData;
    FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FLogger: TSelLogger;
    FBad, FCompared, FCases: Integer;
    FReport, FWhere: string;
    { the init step's elements where nothing was applied, by series and
      inner row; a pie's centre }
    FRestHost, FRestGuide: array of array of TTyChartElement;
    FRestHas, FRestGuideHas: array of array of Boolean;
    FPieHas: array of Boolean;
    FPieCX, FPieCY: array of Double;
    procedure SetUp; override;
    procedure TearDown; override;
    procedure Bad(const AWhat: string);
    procedure NewChart(AOption: TJSONObject);
    procedure CompareEvents(AWant: TJSONArray);
    procedure CompareState(AState: TJSONObject; AInit: Boolean);
    procedure CompareItem(ASeries: Integer; AItem: TJSONObject; AInit: Boolean);
    procedure ComparePoly(ASeries: Integer; APoly: TJSONObject);
    function HostOf(ASeries, ARow: Integer; out AEl: TTyChartElement): Boolean;
    function LabelOf(ASeries, ARow: Integer; out AEl: TTyChartElement): Boolean;
    function GuideOf(ASeries, ARow: Integer; out AEl: TTyChartElement): Boolean;
    procedure RunCases(const AIds: array of string; AMinSteps: Integer);
  published
    procedure TestSelectionAsUpstream;
    procedure TestAnUnregisteredLegacyEventIsNotPublished;
    procedure TestTheZ2CreepsAndAnEmptyListRestores;
    procedure TestABatchOrAnUnknownActionIsRefused;
    { the rules the fixture has no case for (each found by a surviving
      mutant) }
    procedure TestSelectedModeTrueIsSingle;
    procedure TestAToggleSelectPublishesNoLegacyEvent;
    procedure TestTheMapKeepsJavaScriptsKeyOrder;
    procedure TestANameQueryTakesTheFirstItemOfThatName;
    procedure TestADataIndexIsRawUnderAFilter;
    procedure TestAnItemHighlightedByActionIgnoresTheHover;
  private
    procedure Plain(const AOption: string);
    function Indices(ASeries: Integer): string;
  end;

implementation

const
  { THE SELECTION BATCH'S CASES. The rest of the fixture (highlight-*,
    focus-*, emphasis-label, line-focus, legend-*) is B2's and B3's. }
  cB1Cases: array[0..16] of string = ('pie-single', 'pie-multiple',
    'pie-series', 'pie-off', 'pie-offset', 'pie-select-style',
    'pie-hover-creep', 'pie-dup-names', 'bar-single', 'bar-multiple-style',
    'bar-series', 'bar-off', 'line-select', 'action-select-bar',
    'action-select-single', 'action-select-pie', 'emphasis-disabled');
  cPrimary = '#3c3c41';

{ ==================== the probe ==================== }

function TSelProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TSelProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TSelProbe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

{ upstream's click step: a move, the press, the release and its click at one
  point -- and only then a frame }
procedure TSelProbe.ClickAt(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
  MouseDown(mbLeft, [ssLeft], AX, AY);
  MouseUp(mbLeft, [], AX, AY);
end;

function TSelProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function TSelProbe.Primary: TTyChartColor;
begin
  Result := StPrimaryInk;
end;

function TSelProbe.HoverSeries: Integer;
begin
  if EvHover.HdKind = 1 then Result := EvHover.HdSeries else Result := -1;
end;

function TSelProbe.HoverRow: Integer;
begin
  if EvHover.HdKind = 1 then Result := EvHover.HdRow else Result := -1;
end;

{ ==================== the log ==================== }

procedure TSelLogger.Handle(Sender: TObject; const AEvent: TTyChartEvent);
var o: TJSONObject;
begin
  if AEvent.Payload <> '' then
    Log.Add(AEvent.EventType + #9 + AEvent.Payload)
  else
  begin
    { a mouse event: the params upstream's click carries }
    o := TJSONObject.Create;
    try
      o.Add('componentType', AEvent.Params.ComponentType);
      o.Add('seriesIndex', AEvent.Params.SeriesIndex);
      o.Add('dataIndex', AEvent.Params.RawDataIndex);
      o.Add('name', AEvent.Params.Name);
      Log.Add(AEvent.EventType + #9 + o.AsJSON);
    finally
      o.Free;
    end;
  end;
end;

{ ==================== JSON equality ==================== }

{ upstream's auto id ('\0P\00') is written '<auto id>' in the fixture }
function SameJson(AWant, AGot: TJSONData; AOrdered: Boolean): Boolean;
var
  i, k: Integer;
  wo, go: TJSONObject;
begin
  Result := False;
  if (AWant = nil) or (AGot = nil) then Exit(AWant = AGot);
  { fpjson drops the NULs of '\u0000P\u00000' on parsing: any string here,
    the raw text is checked in its own test }
  if (AWant.JSONType = jtString) and (AWant.AsString = '<auto id>') then
    Exit((AGot.JSONType = jtString) and (AGot.AsString <> ''));
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
          if not SameJson(TJSONArray(AWant).Items[i], TJSONArray(AGot).Items[i],
            AOrdered) then Exit;
        Result := True;
      end;
    jtObject:
      begin
        wo := TJSONObject(AWant);
        go := TJSONObject(AGot);
        if wo.Count <> go.Count then Exit;
        for i := 0 to wo.Count - 1 do
        begin
          if AOrdered then
          begin
            if go.Names[i] <> wo.Names[i] then Exit;
            k := i;
          end
          else
            k := go.IndexOfName(wo.Names[i]);
          if k < 0 then Exit;
          if not SameJson(wo.Items[i], go.Items[k], AOrdered) then Exit;
        end;
        Result := True;
      end;
  end;
end;

function ColourOf(const AText: string): TTyChartColor;
begin
  if not TyTryParseChartColor(AText, Result) then Result := 0;
end;

function Hex(AColor: TTyChartColor): string;
begin
  Result := '$' + IntToHex(AColor, 8);
end;

{ ==================== plumbing ==================== }

function FixturePath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + AName;
end;

procedure TAdvChartSelectOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
  FLogger := TSelLogger.Create;
  FLogger.Log := TStringList.Create;
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath('advchart-select-legend.json'));
    FRoot := GetJSON(sl.Text);
    sl.LoadFromFile(FixturePath('advchart-text-style.json'));
    FMeasure := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FBad := 0;
  FCompared := 0;
  FCases := 0;
  FReport := '';
end;

procedure TAdvChartSelectOracleTest.TearDown;
begin
  FLogger.Log.Free;
  FLogger.Free;
  FRoot.Free;
  FMeasure.Free;
  FBmp.Free;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

procedure TAdvChartSelectOracleTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 9000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TAdvChartSelectOracleTest.NewChart(AOption: TJSONObject);
const
  cTypes: array[0..12] of string = ('select', 'unselect', 'toggleselect',
    'selectchanged', 'highlight', 'downplay', 'mapselectchanged',
    'pieselectchanged', 'mapselected', 'pieselected', 'mapunselected',
    'pieunselected', 'click');
var i: Integer;
begin
  FChart.Free;
  FChart := TSelProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  FChart.Option := AOption.AsJSON;
  FChart.SetBounds(0, 0, 600, 400);
  { the fixture registered a handler for every published type, the legacy
    ones included (they only fire with one), and click }
  for i := 0 to High(cTypes) do
    AssertTrue('registered ' + cTypes[i],
      FChart.ChartOn(cTypes[i], @FLogger.Handle) > 0);
  FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
end;

function TAdvChartSelectOracleTest.HostOf(ASeries, ARow: Integer;
  out AEl: TTyChartElement): Boolean;
var k: Integer; el: TTyChartElement; l: TTyPaintList;
begin
  Result := False;
  AEl := Default(TTyChartElement);
  l := FChart.List;
  if l = nil then Exit;
  for k := 0 to l.Count - 1 do
  begin
    el := l.Element(k);
    if (el.Datum.Kind <> ctkSeries) or (el.Datum.SeriesIndex <> ASeries)
      or (el.Datum.DataIndex <> ARow) or el.Datum.IsEdge then Continue;
    if (el.Caption.FontSizeLogical > 0) or el.IsGuide or el.Silent then Continue;
    AEl := el;
    Exit(True);
  end;
end;

function TAdvChartSelectOracleTest.LabelOf(ASeries, ARow: Integer;
  out AEl: TTyChartElement): Boolean;
var k: Integer; el: TTyChartElement; l: TTyPaintList;
begin
  Result := False;
  AEl := Default(TTyChartElement);
  l := FChart.List;
  if l = nil then Exit;
  for k := 0 to l.Count - 1 do
  begin
    el := l.Element(k);
    if (el.Datum.Kind <> ctkSeries) or (el.Datum.SeriesIndex <> ASeries)
      or (el.Datum.DataIndex <> ARow) then Continue;
    if el.Caption.FontSizeLogical <= 0 then Continue;
    AEl := el;
    Exit(True);
  end;
end;

function TAdvChartSelectOracleTest.GuideOf(ASeries, ARow: Integer;
  out AEl: TTyChartElement): Boolean;
var k: Integer; el: TTyChartElement; l: TTyPaintList;
begin
  Result := False;
  AEl := Default(TTyChartElement);
  l := FChart.List;
  if l = nil then Exit;
  for k := 0 to l.Count - 1 do
  begin
    el := l.Element(k);
    if not el.IsGuide or (el.Datum.SeriesIndex <> ASeries)
      or (el.Datum.DataIndex <> ARow) then Continue;
    AEl := el;
    Exit(True);
  end;
end;

{ ==================== the events ==================== }

procedure TAdvChartSelectOracleTest.CompareEvents(AWant: TJSONArray);
var
  i, p: Integer;
  ev: TJSONObject;
  line, gotType: string;
  got: TJSONData;
  ok: Boolean;
begin
  Inc(FCompared);
  if AWant.Count <> FLogger.Log.Count then
  begin
    line := '';
    for i := 0 to FLogger.Log.Count - 1 do
      line := line + ' | ' + Copy(FLogger.Log[i], 1, Pos(#9, FLogger.Log[i]) - 1);
    Bad(Format('%d events, upstream %d:%s', [FLogger.Log.Count, AWant.Count, line]));
    Exit;
  end;
  for i := 0 to AWant.Count - 1 do
  begin
    ev := AWant.Objects[i];
    line := FLogger.Log[i];
    p := Pos(#9, line);
    gotType := Copy(line, 1, p - 1);
    if gotType <> ev.Strings['type'] then
    begin
      Bad(Format('event %d is %s, upstream %s', [i, gotType, ev.Strings['type']]));
      Continue;
    end;
    got := GetJSON(Copy(line, p + 1, MaxInt));
    try
      ok := SameJson(ev.Find('payload'), got, False);
      if not ok then
        Bad(Format('event %d %s payload' + LineEnding + '    here     %s'
          + LineEnding + '    upstream %s', [i, gotType, got.AsJSON,
          ev.Find('payload').AsJSON]));
    finally
      got.Free;
    end;
  end;
end;

{ ==================== the state ==================== }

{ the port's colour for an upstream one, on an item whose rest colours are
  AFixRest (upstream) and APortRest (the port's) }
function MapColour(const AFix, AFixRest: string; APortRest,
  APrimary: TTyChartColor): TTyChartColor;
var c: TTyChartColor;
begin
  if (AFixRest <> '') and (AFix = AFixRest) then Exit(APortRest);
  c := ColourOf(AFix);
  if (AFixRest <> '') and (c = TyChartLiftColor(ColourOf(AFixRest))) then
    Exit(TyChartLiftColor(APortRest));
  if c = ColourOf(cPrimary) then Exit(APrimary);
  if c = TyChartLiftColor(ColourOf(cPrimary)) then Exit(TyChartLiftColor(APrimary));
  Result := c;
end;

function StatesText(AArr: TJSONArray): string;
var i: Integer;
begin
  Result := '';
  for i := 0 to AArr.Count - 1 do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + AArr.Strings[i];
  end;
end;

procedure TAdvChartSelectOracleTest.CompareItem(ASeries: Integer;
  AItem: TJSONObject; AInit: Boolean);
var
  i: Integer;
  st: TTyStItem;
  el, lab, guide: TTyChartElement;
  restObj, lr, gj: TJSONObject;
  want, restFill, restStroke: TTyChartColor;
  fixRestFill, fixRestStroke, what: string;
  d: TJSONData;
  v, restZ2: Double;
begin
  i := AItem.Integers['i'];
  what := Format('s%d i%d ', [ASeries, i]);
  if not FChart.ItemStates(ASeries, i, st) then
  begin
    Bad(what + 'no state record');
    Exit;
  end;
  if not HostOf(ASeries, i, el) then
  begin
    Bad(what + 'no mark in the display list');
    Exit;
  end;
  { THE REST PICTURE is the machine's Rest, read off the freshly built mark;
    the init step's elements stand in only for what it does not keep (a
    symbol's radius, a pie's centre), and only where nothing was applied }
  if AInit and (AItem.Arrays['st'].Count = 0) then
  begin
    FRestHost[ASeries][i] := el;
    FRestHas[ASeries][i] := True;
  end;
  restObj := AItem.Objects['rest'];

  { ---- flags and the list ---- }
  if TyStNamesText(st.Host.States) <> StatesText(AItem.Arrays['st']) then
    Bad(what + Format('states [%s], upstream [%s]',
      [TyStNamesText(st.Host.States), StatesText(AItem.Arrays['st'])]));
  if st.Host.HoverState <> AItem.Integers['hs'] then
    Bad(what + Format('hoverState %d, upstream %d', [st.Host.HoverState, AItem.Integers['hs']]));
  if st.Host.Selected <> AItem.Booleans['sel'] then
    Bad(what + Format('selected %s, upstream %s', [BoolToStr(st.Host.Selected, True),
      BoolToStr(AItem.Booleans['sel'], True)]));
  if st.Host.Proxy <> AItem.Booleans['px'] then
    Bad(what + 'proxy differs');
  if (st.Host.HighByOuter <> 0) <> (AItem.Integers['hbo'] <> 0) then
    Bad(what + '__highByOuter differs');

  { ---- z2, as the distance from rest, on the machine and on the mark ---- }
  restZ2 := st.Host.Rest.Num[stkZ2];
  if Round(st.Host.Cur.Num[stkZ2] - restZ2)
    <> AItem.Integers['z2'] - restObj.Integers['z2'] then
    Bad(what + Format('z2 rest + %d, upstream rest + %d',
      [Round(st.Host.Cur.Num[stkZ2] - restZ2),
       AItem.Integers['z2'] - restObj.Integers['z2']]));
  if el.Z2 - Round(restZ2) <> AItem.Integers['z2'] - restObj.Integers['z2'] then
    Bad(what + Format('drawn z2 rest + %d, upstream rest + %d',
      [el.Z2 - Round(restZ2), AItem.Integers['z2'] - restObj.Integers['z2']]));

  { ---- colours, as drawn ---- }
  restFill := st.Host.Rest.Color[stkFill];
  restStroke := st.Host.Rest.Color[stkStroke];
  fixRestFill := restObj.Get('fill', '');
  if AItem.Find('fill') <> nil then
  begin
    want := MapColour(AItem.Strings['fill'], fixRestFill, restFill, FChart.Primary);
    if not el.Style.HasFill or (el.Style.FillColor <> want) then
      Bad(what + Format('fill %s, want %s (upstream %s)',
        [Hex(el.Style.FillColor), Hex(want), AItem.Strings['fill']]));
  end;
  fixRestStroke := restObj.Get('stroke', '');
  if (AItem.Find('stroke') <> nil) and (AItem.Strings['stroke'] <> fixRestStroke) then
  begin
    want := MapColour(AItem.Strings['stroke'], fixRestStroke, restStroke,
      FChart.Primary);
    if el.Style.StrokeColor <> want then
      Bad(what + Format('stroke %s, want %s (upstream %s)',
        [Hex(el.Style.StrokeColor), Hex(want), AItem.Strings['stroke']]));
    if el.Style.StrokeWidthLogical <> AItem.Floats['lineWidth'] then
      Bad(what + Format('lineWidth %g, upstream %g',
        [el.Style.StrokeWidthLogical, AItem.Floats['lineWidth']]));
  end
  else if TyStHasColour(st.Host.Rest, stkStroke) then
  begin
    { the port's own rest stroke, kept }
    if (el.Style.StrokeColor <> restStroke)
      or (el.Style.StrokeWidthLogical <> st.Host.Rest.Num[stkLineWidth]) then
      Bad(what + 'the stroke left rest');
  end
  else if (el.Style.StrokeWidthLogical > 0) and (el.Style.StrokeColor <> 0) then
    Bad(what + 'a stroke where rest has none');
  if el.Style.Alpha <> AItem.Floats['opacity'] then
    Bad(what + Format('opacity %g, upstream %g', [el.Style.Alpha, AItem.Floats['opacity']]));

  { ---- geometry ---- }
  if AItem.Find('a0') <> nil then
  begin
    { a slice: the machine's offset exactly, the drawn centre to 1e-9 against
      a slice of the same pie at rest }
    if st.Host.Cur.Num[stkX] <> AItem.Floats['x'] then
      Bad(what + Format('x %.17g, upstream %.17g', [st.Host.Cur.Num[stkX], AItem.Floats['x']]));
    if st.Host.Cur.Num[stkY] <> AItem.Floats['y'] then
      Bad(what + Format('y %.17g, upstream %.17g', [st.Host.Cur.Num[stkY], AItem.Floats['y']]));
    if FPieHas[ASeries] and ((Abs(el.Shape.CX - FPieCX[ASeries] - AItem.Floats['x']) > 1e-9)
      or (Abs(el.Shape.CY - FPieCY[ASeries] - AItem.Floats['y']) > 1e-9)) then
      Bad(what + 'the drawn slice is not where the offset puts it');
    if el.Shape.R1 <> AItem.Floats['r'] then
      Bad(what + Format('r %.17g, upstream %.17g', [el.Shape.R1, AItem.Floats['r']]));
    if st.Host.Rest.Num[stkR] <> restObj.Floats['r'] then
      Bad(what + 'rest r differs');
    if (el.Shape.StartRad <> AItem.Floats['a0']) or (el.Shape.EndRad <> AItem.Floats['a1']) then
      Bad(what + Format('angles %.17g..%.17g, upstream %.17g..%.17g',
        [el.Shape.StartRad, el.Shape.EndRad, AItem.Floats['a0'], AItem.Floats['a1']]));
  end;
  if AItem.Find('bx') <> nil then
  begin
    v := AItem.Floats['bx'];
    if (Abs(el.Shape.Bounds.Left - Min(v, v + AItem.Floats['bw'])) > 1e-9)
      or (Abs(el.Shape.Bounds.Right - Max(v, v + AItem.Floats['bw'])) > 1e-9)
      or (Abs(el.Shape.Bounds.Top - Min(AItem.Floats['by'], AItem.Floats['by'] + AItem.Floats['bh'])) > 1e-9)
      or (Abs(el.Shape.Bounds.Bottom - Max(AItem.Floats['by'], AItem.Floats['by'] + AItem.Floats['bh'])) > 1e-9) then
      Bad(what + Format('bar rect %g,%g..%g,%g', [el.Shape.Bounds.Left,
        el.Shape.Bounds.Top, el.Shape.Bounds.Right, el.Shape.Bounds.Bottom]));
  end;
  if AItem.Find('sx') <> nil then
  begin
    { a symbol: the rest half size times the machine's scale, exactly }
    v := restObj.Floats['sx'] * st.Host.Cur.Num[stkScale];
    if v <> AItem.Floats['sx'] then
      Bad(what + Format('symbol scale %.17g, upstream %.17g', [v, AItem.Floats['sx']]));
    if FRestHas[ASeries][i] and (Abs(el.Shape.R1
      - FRestHost[ASeries][i].Shape.R1 * AItem.Floats['sx'] / restObj.Floats['sx']) > 1e-9) then
      Bad(what + Format('drawn symbol radius %g', [el.Shape.R1]));
    if (Abs(el.Shape.CX - AItem.Floats['gx']) > 1e-9)
      or (Abs(el.Shape.CY - AItem.Floats['gy']) > 1e-9) then
      Bad(what + Format('symbol at %g,%g, upstream %g,%g', [el.Shape.CX, el.Shape.CY,
        AItem.Floats['gx'], AItem.Floats['gy']]));
    if st.Host.HoverState <> AItem.Integers['ghs'] then
      Bad(what + 'group hoverState differs');
  end;

  { ---- the label ---- }
  d := AItem.Find('label');
  if (d is TJSONObject) <> st.Label_.Exists then
    Bad(what + 'label presence differs')
  else if d is TJSONObject then
  begin
    lr := TJSONObject(d);
    if not LabelOf(ASeries, i, lab) then
    begin
      Bad(what + 'no label in the display list');
      Exit;
    end;
    if TyStNamesText(st.Label_.States) <> StatesText(lr.Arrays['st']) then
      Bad(what + Format('label states [%s], upstream [%s]',
        [TyStNamesText(st.Label_.States), StatesText(lr.Arrays['st'])]));
    if lab.Ignore <> lr.Booleans['ignore'] then
      Bad(what + Format('label ignore %s, upstream %s', [BoolToStr(lab.Ignore, True),
        BoolToStr(lr.Booleans['ignore'], True)]));
    if (st.Label_.Rest.Num[stkIgnore] <> 0) <> lr.Objects['rest'].Booleans['ignore'] then
      Bad(what + 'label rest ignore differs');
    if lab.Z2 - Round(st.Label_.Rest.Num[stkZ2])
      <> lr.Integers['z2'] - lr.Objects['rest'].Integers['z2'] then
      Bad(what + Format('label z2 rest + %d, upstream rest + %d',
        [lab.Z2 - Round(st.Label_.Rest.Num[stkZ2]),
         lr.Integers['z2'] - lr.Objects['rest'].Integers['z2']]));
    if (lr.Find('fill') <> nil) and (lab.Caption.Colour <> ColourOf(lr.Strings['fill'])) then
      Bad(what + Format('label ink %s, upstream %s', [Hex(lab.Caption.Colour), lr.Strings['fill']]));
    { the place: the offset from rest to 1e-9 (upstream adds the offset to
      the laid-out place, so neither side's difference is the offset
      exactly), a pie label's laid-out rest to 1e-6 }
    if (Abs((lab.Caption.X - st.Label_.Rest.Num[stkX])
        - (lr.Floats['x'] - lr.Objects['rest'].Floats['x'])) > 1e-9)
      or (Abs((lab.Caption.Y - st.Label_.Rest.Num[stkY])
        - (lr.Floats['y'] - lr.Objects['rest'].Floats['y'])) > 1e-9) then
      Bad(what + Format('label offset %.9g,%.9g, upstream %.9g,%.9g',
        [lab.Caption.X - st.Label_.Rest.Num[stkX], lab.Caption.Y - st.Label_.Rest.Num[stkY],
         lr.Floats['x'] - lr.Objects['rest'].Floats['x'],
         lr.Floats['y'] - lr.Objects['rest'].Floats['y']]));
    if (AItem.Find('a0') <> nil)
      and ((Abs(st.Label_.Rest.Num[stkX] - lr.Objects['rest'].Floats['x']) > 1e-6)
        or (Abs(st.Label_.Rest.Num[stkY] - lr.Objects['rest'].Floats['y']) > 1e-6)) then
      Bad(what + Format('pie label at rest %.9g,%.9g, upstream %.9g,%.9g',
        [st.Label_.Rest.Num[stkX], st.Label_.Rest.Num[stkY],
         lr.Objects['rest'].Floats['x'], lr.Objects['rest'].Floats['y']]));
  end;

  { ---- the label line ---- }
  d := AItem.Find('guide');
  if d is TJSONObject then
  begin
    gj := TJSONObject(d);
    if not st.Guide.Exists or not GuideOf(ASeries, i, guide) then
      Bad(what + 'no label line')
    else
    begin
      if TyStNamesText(st.Guide.States) <> StatesText(gj.Arrays['st']) then
        Bad(what + 'label line states differ');
      if (st.Guide.Cur.Num[stkX] <> gj.Floats['x'])
        or (st.Guide.Cur.Num[stkY] <> gj.Floats['y']) then
        Bad(what + Format('label line offset %.17g,%.17g, upstream %.17g,%.17g',
          [st.Guide.Cur.Num[stkX], st.Guide.Cur.Num[stkY], gj.Floats['x'], gj.Floats['y']]));
      if FRestGuideHas[ASeries][i] and ((Abs(guide.Shape.Points[0].X
        - FRestGuide[ASeries][i].Shape.Points[0].X - gj.Floats['x']) > 1e-9)
        or (Abs(guide.Shape.Points[0].Y - FRestGuide[ASeries][i].Shape.Points[0].Y
        - gj.Floats['y']) > 1e-9)) then
        Bad(what + 'the drawn label line is not where the offset puts it');
    end;
  end;
  if AInit and (AItem.Arrays['st'].Count = 0) and GuideOf(ASeries, i, guide) then
  begin
    FRestGuide[ASeries][i] := guide;
    FRestGuideHas[ASeries][i] := True;
  end;
  if AInit and (AItem.Arrays['st'].Count = 0) and (AItem.Find('a0') <> nil)
    and not FPieHas[ASeries] then
  begin
    FPieHas[ASeries] := True;
    FPieCX[ASeries] := el.Shape.CX;
    FPieCY[ASeries] := el.Shape.CY;
  end;
end;

procedure TAdvChartSelectOracleTest.ComparePoly(ASeries: Integer; APoly: TJSONObject);
var
  poly, area_: TTyStItem;
  want: TTyChartColor;
  what: string;
begin
  what := Format('s%d polyline ', [ASeries]);
  if not FChart.LineStates(ASeries, poly, area_) then
  begin
    Bad(what + 'no state record');
    Exit;
  end;
  if TyStNamesText(poly.Host.States) <> StatesText(APoly.Arrays['st']) then
    Bad(what + Format('states [%s], upstream [%s]', [TyStNamesText(poly.Host.States),
      StatesText(APoly.Arrays['st'])]));
  if poly.Host.HoverState <> APoly.Integers['hs'] then
    Bad(what + 'hoverState differs');
  if Round(poly.Host.Cur.Num[stkZ2] - poly.Host.Rest.Num[stkZ2])
    <> APoly.Integers['z2'] - APoly.Objects['rest'].Integers['z2'] then
    Bad(what + 'z2 differs');
  want := MapColour(APoly.Strings['stroke'], APoly.Objects['rest'].Strings['stroke'],
    poly.Host.Rest.Color[stkStroke], FChart.Primary);
  if not TyStHasColour(poly.Host.Cur, stkStroke) or (poly.Host.Cur.Color[stkStroke] <> want) then
    Bad(what + Format('stroke %s, want %s', [Hex(poly.Host.Cur.Color[stkStroke]), Hex(want)]));
  if poly.Host.Cur.Num[stkLineWidth] <> APoly.Floats['lineWidth'] then
    Bad(what + 'lineWidth differs');
end;

procedure TAdvChartSelectOracleTest.CompareState(AState: TJSONObject; AInit: Boolean);
var
  ser: TJSONArray;
  so: TJSONObject;
  i, k, s: Integer;
  got: TJSONData;
  idx: TTyIntegerArray;
  line: string;
begin
  ser := AState.Arrays['series'];
  if AInit then
  begin
    FRestHost := nil;
    FRestGuide := nil;
    FRestHas := nil;
    FRestGuideHas := nil;
    FPieHas := nil;
    SetLength(FRestHost, ser.Count);
    SetLength(FRestGuide, ser.Count);
    SetLength(FRestHas, ser.Count);
    SetLength(FRestGuideHas, ser.Count);
    SetLength(FPieHas, ser.Count);
    SetLength(FPieCX, ser.Count);
    SetLength(FPieCY, ser.Count);
  end;
  for k := 0 to ser.Count - 1 do
  begin
    so := ser.Objects[k];
    s := so.Integers['s'];
    if AInit then
    begin
      SetLength(FRestHost[s], so.Arrays['items'].Count);
      SetLength(FRestGuide[s], so.Arrays['items'].Count);
      SetLength(FRestHas[s], so.Arrays['items'].Count);
      SetLength(FRestGuideHas[s], so.Arrays['items'].Count);
    end;
    { the model }
    got := GetJSON(FChart.SelectedMapText(s));
    try
      if not SameJson(so.Find('selectedMap'), got, True) then
        Bad(Format('s%d selectedMap %s, upstream %s', [s, got.AsJSON,
          so.Find('selectedMap').AsJSON]));
    finally
      got.Free;
    end;
    idx := FChart.SelectedDataIndices(s);
    line := '[';
    for i := 0 to High(idx) do
    begin
      if i > 0 then line := line + ',';
      line := line + IntToStr(idx[i]);
    end;
    line := line + ']';
    got := GetJSON(line);
    try
      if not SameJson(so.Find('selectedIndices'), got, True) then
        Bad(Format('s%d selected indices %s, upstream %s', [s, line,
          so.Find('selectedIndices').AsJSON]));
    finally
      got.Free;
    end;
    { the items }
    for i := 0 to so.Arrays['items'].Count - 1 do
      CompareItem(s, so.Arrays['items'].Objects[i], AInit);
    if (so.Find('poly') <> nil) and (so.Find('poly').JSONType = jtObject) then
      ComparePoly(s, so.Objects['poly']);
  end;
end;

procedure TAdvChartSelectOracleTest.RunCases(const AIds: array of string;
  AMinSteps: Integer);
var
  cases, steps: TJSONArray;
  cs, st, hit: TJSONObject;
  c, s, k: Integer;
  kind: string;
  found: Boolean;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    found := False;
    for k := 0 to High(AIds) do
      if AIds[k] = cs.Strings['id'] then found := True;
    if not found then Continue;
    Inc(FCases);
    NewChart(cs.Objects['option']);
    steps := cs.Arrays['steps'];
    for s := 0 to steps.Count - 1 do
    begin
      st := steps.Objects[s];
      kind := st.Strings['type'];
      FWhere := Format('%s step %d (%s)', [cs.Strings['id'], s, kind]);
      FLogger.Log.Clear;
      if kind = 'move' then FChart.Move(st.Integers['x'], st.Integers['y'])
      else if kind = 'click' then FChart.ClickAt(st.Integers['x'], st.Integers['y'])
      else if kind = 'action' then
        AssertTrue(FWhere + ' dispatched', FChart.DispatchAction(st.Objects['payload'].AsJSON));
      { the frame }
      FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
      { the hover found the item upstream's hover found }
      if (kind <> 'init') and (kind <> 'action') then
      begin
        if (st.Find('hit') is TJSONObject) and (st.Objects['hit'].Find('dp') is TJSONObject) then
        begin
          hit := st.Objects['hit'].Objects['dp'];
          if (FChart.HoverSeries <> hit.Integers['s']) or (FChart.HoverRow <> hit.Integers['i']) then
            Bad(Format('the pointer is over s%d i%d, upstream s%d i%d',
              [FChart.HoverSeries, FChart.HoverRow, hit.Integers['s'], hit.Integers['i']]));
        end
        else if FChart.HoverSeries >= 0 then
          Bad('the pointer is over an item, upstream over none');
      end;
      CompareEvents(st.Arrays['events']);
      CompareState(st.Objects['state'], kind = 'init');
    end;
  end;
end;

{ ==================== tests ==================== }

procedure TAdvChartSelectOracleTest.TestSelectionAsUpstream;
begin
  RunCases(cB1Cases, 80);
  AssertTrue(Format('%d mismatches over %d steps:%s', [FBad, FCompared, FReport]), FBad = 0);
  AssertEquals('every selection case ran', Length(cB1Cases), FCases);
  AssertTrue(Format('only %d steps compared', [FCompared]), FCompared >= 80);
end;

{ ISSILENT: a legacy event is published only to a handler that asked for
  it -- the catch-all does not count as asking }
procedure TAdvChartSelectOracleTest.TestAnUnregisteredLegacyEventIsNotPublished;
var
  log: TStringList;
  i: Integer;
  got: TJSONData;
begin
  FChart := TSelProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Option := '{"animation":false,"series":[{"type":"pie","selectedMode":"single",'
    + '"data":[{"name":"a","value":1},{"name":"b","value":2}]}]}';
  FChart.SetBounds(0, 0, 600, 400);
  FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
  FChart.OnChartEvent := @FLogger.Handle;
  AssertTrue(FChart.DispatchAction('{"type":"select","seriesIndex":0,"name":"b"}'));
  log := TStringList(FLogger.Log);
  AssertEquals('select and selectchanged only', 2, log.Count);
  for i := 0 to log.Count - 1 do
    AssertTrue('no legacy event: ' + log[i], Pos('pie', log[i]) <> 1);
  FLogger.Log.Clear;
  FChart.ChartOn('pieselected', @FLogger.Handle);
  AssertTrue(FChart.DispatchAction('{"type":"select","seriesIndex":0,"name":"a"}'));
  { the catch-all and the registration: select, selectchanged, then
    pieselected twice (once to each) }
  AssertEquals(4, FLogger.Log.Count);
  AssertEquals('pieselected', Copy(FLogger.Log[2], 1, Pos(#9, FLogger.Log[2]) - 1));
  { upstream's auto id of an unnamed series, '\0series\00\0' + 0, as written
    (fpjson drops the NULs when it parses it back) }
  AssertTrue('the auto id: ' + FLogger.Log[2],
    Pos('"seriesId":"\u0000series\u00000\u00000"', FLogger.Log[2]) > 0);
  got := GetJSON(Copy(FLogger.Log[2], Pos(#9, FLogger.Log[2]) + 1, MaxInt));
  try
    AssertEquals('the name of the payload''s item', 'a', TJSONObject(got).Strings['name']);
    AssertEquals('the map', '{ "a" : true }', TJSONObject(got).Objects['selected'].AsJSON);
  finally
    got.Free;
  end;
end;

{ THE CREEP, outside the fixture's own case: a selected bar hovered on and
  off three times climbs 1 -> 10 -> 20 -> 29 -> 39 -> 48 -> 58 -> 67, and an
  unselect after the hover leaves puts it back at rest. }
procedure TAdvChartSelectOracleTest.TestTheZ2CreepsAndAnEmptyListRestores;
const cWant: array[0..6] of Integer = (20, 29, 39, 48, 58, 67, 77);
var
  st: TTyStItem;
  el: TTyChartElement;
  i, rest: Integer;
begin
  FChart := TSelProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Option := '{"animation":false,"xAxis":{"type":"category","data":["a","b"]},'
    + '"yAxis":{"type":"value"},"series":[{"type":"bar","selectedMode":"single",'
    + '"data":[10,20]}]}';
  FChart.SetBounds(0, 0, 600, 400);
  FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
  AssertTrue(HostOf(0, 1, el));
  rest := el.Z2;
  AssertTrue(FChart.DispatchAction('{"type":"select","seriesIndex":0,"dataIndex":1}'));
  FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
  AssertTrue(FChart.ItemStates(0, 1, st));
  AssertEquals('select: rest + 9', rest + 9, Round(st.Host.Cur.Num[stkZ2]));
  for i := 0 to 6 do
  begin
    if i mod 2 = 0 then FChart.Move(Round((el.Shape.Bounds.Left + el.Shape.Bounds.Right) / 2),
      Round(el.Shape.Bounds.Bottom - 2))
    else FChart.Move(2, 2);
    FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
    AssertTrue(FChart.ItemStates(0, 1, st));
    AssertEquals(Format('switch %d', [i]), rest + cWant[i] - 1,
      Round(st.Host.Cur.Num[stkZ2]));
    AssertTrue(HostOf(0, 1, el));
    AssertEquals('drawn', rest + cWant[i] - 1, el.Z2);
  end;
  FChart.Move(2, 2);
  AssertTrue(FChart.DispatchAction('{"type":"unselect","seriesIndex":0,"dataIndex":1}'));
  FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
  AssertTrue(FChart.ItemStates(0, 1, st));
  AssertEquals('no state: rest', rest, Round(st.Host.Cur.Num[stkZ2]));
  AssertTrue(HostOf(0, 1, el));
  AssertEquals('drawn at rest', rest, el.Z2);
end;

procedure TAdvChartSelectOracleTest.TestABatchOrAnUnknownActionIsRefused;
begin
  FChart := TSelProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Option := '{"series":[{"type":"pie","data":[{"name":"a","value":1}]}]}';
  FChart.SetBounds(0, 0, 600, 400);
  FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
  AssertFalse('not JSON', FChart.DispatchAction('select'));
  AssertFalse('no type', FChart.DispatchAction('{"seriesIndex":0}'));
  AssertFalse('unknown', FChart.DispatchAction('{"type":"nosuch"}'));
  AssertFalse('case matters', FChart.DispatchAction('{"type":"toggleselect"}'));
  AssertFalse('a batch', FChart.DispatchAction('{"type":"select","batch":[{"dataIndex":0}]}'));
  AssertTrue(FChart.DispatchAction('{"type":"toggleSelect","dataIndex":0}'));
end;

procedure TAdvChartSelectOracleTest.Plain(const AOption: string);
begin
  FChart := TSelProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Option := AOption;
  FChart.SetBounds(0, 0, 600, 400);
  FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
end;

function TAdvChartSelectOracleTest.Indices(ASeries: Integer): string;
var idx: TTyIntegerArray; i: Integer;
begin
  idx := FChart.SelectedDataIndices(ASeries);
  Result := '';
  for i := 0 to High(idx) do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + IntToStr(idx[i]);
  end;
end;

{ `selectedMode: true` is 'single' (Series.ts:711: === 'single' || === true):
  the last index of the payload, the map replaced }
procedure TAdvChartSelectOracleTest.TestSelectedModeTrueIsSingle;
begin
  Plain('{"animation":false,"xAxis":{"type":"category","data":["a","b","c"]},'
    + '"yAxis":{"type":"value"},"series":[{"type":"bar","selectedMode":true,'
    + '"data":[1,2,3]}]}');
  AssertTrue(FChart.DispatchAction('{"type":"select","seriesIndex":0,"dataIndex":[0,2]}'));
  AssertEquals('{"c":true}', FChart.SelectedMapText(0));
  AssertEquals('2', Indices(0));
  AssertTrue(FChart.DispatchAction('{"type":"select","seriesIndex":0,"dataIndex":1}'));
  AssertEquals('{"b":true}', FChart.SelectedMapText(0));
end;

{ dataSelectAction.ts:104-113: a click -> *selectchanged, an action select
  -> *selected, unselect -> *unselected; a toggleSelect nothing, even when
  it leaves a slice selected }
procedure TAdvChartSelectOracleTest.TestAToggleSelectPublishesNoLegacyEvent;
const
  cLegacy: array[0..5] of string = ('mapselectchanged', 'pieselectchanged',
    'mapselected', 'pieselected', 'mapunselected', 'pieunselected');
var i: Integer;
begin
  Plain('{"animation":false,"series":[{"type":"pie","selectedMode":"multiple",'
    + '"data":[{"name":"a","value":1},{"name":"b","value":2}]}]}');
  for i := 0 to High(cLegacy) do FChart.ChartOn(cLegacy[i], @FLogger.Handle);
  FChart.ChartOn('toggleselect', @FLogger.Handle);
  FChart.ChartOn('selectchanged', @FLogger.Handle);
  AssertTrue(FChart.DispatchAction('{"type":"toggleSelect","seriesIndex":0,"name":"a"}'));
  AssertEquals('a is selected', '0', Indices(0));
  AssertEquals('toggleselect and selectchanged, no legacy event: ' + FLogger.Log.Text,
    2, FLogger.Log.Count);
  FLogger.Log.Clear;
  AssertTrue(FChart.DispatchAction('{"type":"unselect","seriesIndex":0,"name":"b"}'));
  { b was never selected, a still is: the pie is in the selection }
  AssertEquals('selectchanged, mapunselected, pieunselected: ' + FLogger.Log.Text,
    3, FLogger.Log.Count);
  AssertEquals('mapunselected', Copy(FLogger.Log[1], 1, Pos(#9, FLogger.Log[1]) - 1));
end;

{ selectedMap and _selectedDataIndicesMap are JavaScript objects: integer-like
  keys come first, ascending, the others after in insertion order -- and
  getSelectedDataIndices walks the keys in that order }
procedure TAdvChartSelectOracleTest.TestTheMapKeepsJavaScriptsKeyOrder;
begin
  Plain('{"animation":false,"series":[{"type":"pie","selectedMode":"multiple",'
    + '"data":[{"name":"b","value":1},{"name":"10","value":2},'
    + '{"name":"2","value":3},{"name":"02","value":4}]}]}');
  AssertTrue(FChart.DispatchAction('{"type":"select","seriesIndex":0,"name":"b"}'));
  AssertTrue(FChart.DispatchAction('{"type":"select","seriesIndex":0,"name":"10"}'));
  AssertTrue(FChart.DispatchAction('{"type":"select","seriesIndex":0,"name":"02"}'));
  AssertTrue(FChart.DispatchAction('{"type":"select","seriesIndex":0,"name":"2"}'));
  { '02' is no array index: it stays where it was inserted }
  AssertEquals('{"2":true,"10":true,"b":true,"02":true}', FChart.SelectedMapText(0));
  AssertEquals('2,1,0,3', Indices(0));
end;

{ indexOfName: the FIRST inner index of that name }
procedure TAdvChartSelectOracleTest.TestANameQueryTakesTheFirstItemOfThatName;
begin
  Plain('{"animation":false,"series":[{"type":"pie","selectedMode":"multiple",'
    + '"data":[{"name":"a","value":1},{"name":"b","value":2},{"name":"a","value":3}]}]}');
  AssertTrue(FChart.DispatchAction('{"type":"select","seriesIndex":0,"name":"a"}'));
  AssertEquals('0', Indices(0));
end;

{ `dataIndex` is RAW (indexOfRawIndex), `dataIndexInside` the shown data's:
  under a dataZoom that filters the first two categories they part }
procedure TAdvChartSelectOracleTest.TestADataIndexIsRawUnderAFilter;
var st: TTyStItem;
begin
  Plain('{"animation":false,"xAxis":{"type":"category","data":["a","b","c","d","e","f"]},'
    + '"yAxis":{"type":"value"},"dataZoom":[{"type":"inside","startValue":2,"endValue":5}],'
    + '"series":[{"type":"bar","selectedMode":"multiple","data":[1,2,3,4,5,6]}]}');
  AssertEquals('the store is filtered', 4, FChart.SeriesStore(0).Count);
  AssertTrue(FChart.DispatchAction('{"type":"select","seriesIndex":0,"dataIndex":3}'));
  AssertEquals('raw 3', '3', Indices(0));
  AssertEquals('{"d":true}', FChart.SelectedMapText(0));
  AssertTrue(FChart.DispatchAction('{"type":"select","seriesIndex":0,"dataIndexInside":0}'));
  AssertEquals('inner 0 is raw 2', '3,2', Indices(0));
  FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
  AssertTrue(FChart.ItemStates(0, 1, st));
  AssertEquals('inner 1 is d, selected', 'select', TyStNamesText(st.Host.States));
end;

{ states.ts:360-372: the pointer neither enters nor leaves an element whose
  __highByOuter is set -- a highlighted bar stays lit when the pointer
  crosses it, until the downplay }
procedure TAdvChartSelectOracleTest.TestAnItemHighlightedByActionIgnoresTheHover;
var st: TTyStItem; el: TTyChartElement;
begin
  Plain('{"animation":false,"xAxis":{"type":"category","data":["a","b"]},'
    + '"yAxis":{"type":"value"},"series":[{"type":"bar","data":[10,20]}]}');
  AssertTrue(HostOf(0, 1, el));
  AssertTrue(FChart.DispatchAction('{"type":"highlight","seriesIndex":0,"dataIndex":1}'));
  FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
  FChart.Move(Round((el.Shape.Bounds.Left + el.Shape.Bounds.Right) / 2),
    Round(el.Shape.Bounds.Bottom - 2));
  FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
  FChart.Move(2, 2);
  FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
  AssertTrue(FChart.ItemStates(0, 1, st));
  AssertEquals('still lit after the pointer left', 'emphasis', TyStNamesText(st.Host.States));
  AssertTrue(st.Host.HighByOuter <> 0);
  AssertTrue(FChart.DispatchAction('{"type":"downplay","seriesIndex":0,"dataIndex":1}'));
  FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
  AssertTrue(FChart.ItemStates(0, 1, st));
  AssertEquals('downplayed', '', TyStNamesText(st.Host.States));
end;

initialization
  RegisterTest(TAdvChartSelectOracleTest);
end.
