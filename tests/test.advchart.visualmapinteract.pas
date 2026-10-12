unit test.advchart.visualmapinteract;
{$mode objfpc}{$H+}
{ visualMap interaction -- held to upstream to the bit [Batch 116, C7].

  tools/advchart-oracle/visualmap-interact.js runs the real ECharts 6.1
  build through cases of pointer steps (zrender's own Handler: moves, press,
  release and the click after it, the pointer leaving the canvas),
  selectDataRange actions and merges, and records after every step: the
  events (highlight and downplay with their batches, datarangeselected);
  every visualMap's model (a continuous one's range, a piecewise one's
  selected map) and its view -- the interval and handle ends a drag moved,
  the drag and hover flags, the last hover link's items, where the group
  stands, the in-range bar's points, each thumb's place, scale, fill and
  states, each handle label's words, place, alignment and blur, and the
  indicator with its label; a piecewise view's items (fill, label opacity);
  and every data item's hover flag, highlight bits, state list, fill and
  opacity. Two cases run with animation: the indicator's additive slide,
  frame by frame.

  The port is driven the same way -- MouseMove / MouseDown / MouseUp /
  MouseLeave, DispatchAction, SetOption -- with a headless render after
  each step, and compared through its own API: the element under the
  pointer before the step (VisualMapRoleAt), the events the handlers got,
  VisualMapSpec / VisualMapLayout / VisualMapLive / VisualMapSelectedText,
  and ItemStates. Everything to the bit, except the handle labels' opacity:
  upstream fades them over 200 ms (the record is taken after it settles, at
  0.1 or 0.09999999999999998); here the blur flag is compared. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint,
     tyControls.AdvChart.Color, tyControls.AdvChart.States,
     tyControls.AdvChart.Events, tyControls.AdvChart.VisualMap,
     tyControls.AdvChart.VisualMapView, tyControls.AdvChart.JsMath,
     tyControls.AdvanceChart;
type
  { zrender's widths, from the fixture's table }
  TVmiMeasurer = class(TInterfacedObject, ITyTextMeasurer)
  public
    Names: TStringList;
    W, H: array of Double;
    Missed: string;
    constructor Create;
    destructor Destroy; override;
    procedure Add(const AText: string; AW, AH: Double);
    procedure MeasureLine(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
    function WrapToWidth(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
  end;

  TVmiProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    Events: TStringList;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Down(AX, AY: Integer);
    procedure Move(AX, AY: Integer);
    procedure Up(AX, AY: Integer);
    procedure Leave;
    procedure LoseCapture;
    function List: TTyPaintList;
    function Count(const AType: string): Integer;
    procedure OnEv(Sender: TObject; const AEvent: TTyChartEvent);
  end;

  TAdvChartVisualMapInteractOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TVmiProbe;
    FRoot: TJSONData;
    FMeas: TVmiMeasurer;
    FMeasRef: ITyTextMeasurer;
    FBad, FCompared, FSteps: Integer;
    FReport, FName: string;
    procedure Miss(const AWhat: string);
    procedure SameHex(const AWhat: string; AGot: Double; AObj: TJSONObject;
      const AKey: string; AIndex: Integer = -1);
    procedure SameStr(const AWhat, AGot, AWant: string);
    procedure SameBool(const AWhat: string; AGot, AWant: Boolean);
    procedure SameColour(const AWhat: string; AR, AG, AB, AA: Double; AWant: TJSONData);
    procedure NewChart(AAnimated: Boolean);
    procedure RenderNow;
    procedure CheckEvents(AStep: TJSONObject);
    procedure CheckVm(AIndex: Integer; AVm: TJSONObject; AAnimated: Boolean);
    procedure CheckSeries(AStep: TJSONObject);
    function SeriesOfId(const AId: string): Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEveryDragHoverAndClickActsAsUpstream;
  end;

  { What the oracle does not reach. }
  TAdvChartVisualMapInteractTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TVmiProbe;
    procedure Show(const AOption: string);
    procedure RenderNow;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestALostCaptureEndsAHandleDrag;
    procedure TestAPressOnAHandleIsNotAPan;
    procedure TestSelectDataRangeByIdAndName;
    procedure TestABatchOfAnotherTypeIsRefused;
    procedure TestAHighlightBatchIsOneEventWithEveryItem;
    procedure TestTheIndicatorIsDrawnWhereItIs;
    procedure TestAClickAfterAHoverLinkNeedsNoRepaint;
  end;

implementation

const
  T0 = 1700000000000.0;

{ ==================== the measurer ==================== }

constructor TVmiMeasurer.Create;
begin
  inherited Create;
  Names := TStringList.Create;
  Names.CaseSensitive := True;
end;

destructor TVmiMeasurer.Destroy;
begin
  Names.Free;
  inherited Destroy;
end;

procedure TVmiMeasurer.Add(const AText: string; AW, AH: Double);
var k: Integer;
begin
  if Names.IndexOf(AText) >= 0 then Exit;
  k := Names.Add(AText);
  SetLength(W, k + 1);
  SetLength(H, k + 1);
  W[k] := AW;
  H[k] := AH;
end;

procedure TVmiMeasurer.MeasureLine(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
var k: Integer;
begin
  k := Names.IndexOf(AText);
  if k < 0 then
  begin
    if Pos('"' + AText + '"', Missed) = 0 then Missed := Missed + ' "' + AText + '"';
    AW := 0;
    AH := 12;
    Exit;
  end;
  AW := W[k];
  AH := H[k];
end;

function TVmiMeasurer.WrapToWidth(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
begin
  Result := AText;
end;

{ ==================== the probe ==================== }

function TVmiProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Exit(Measurer);
  Result := inherited NewTextMeasurer(APPI);
end;

constructor TVmiProbe.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Events := TStringList.Create;
end;

destructor TVmiProbe.Destroy;
begin
  Events.Free;
  inherited Destroy;
end;

procedure TVmiProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TVmiProbe.Down(AX, AY: Integer);
begin
  MouseDown(mbLeft, [], AX, AY);
end;

procedure TVmiProbe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TVmiProbe.Up(AX, AY: Integer);
begin
  MouseUp(mbLeft, [], AX, AY);
end;

procedure TVmiProbe.Leave;
begin
  MouseLeave;
end;

procedure TVmiProbe.LoseCapture;
begin
  CaptureChanged;
end;

function TVmiProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function TVmiProbe.Count(const AType: string): Integer;
var i: Integer;
begin
  Result := 0;
  for i := 0 to Events.Count - 1 do
    if Copy(Events[i], 1, Length(AType) + 1) = AType + #9 then Inc(Result);
end;

procedure TVmiProbe.OnEv(Sender: TObject; const AEvent: TTyChartEvent);
begin
  Events.Add(AEvent.EventType + #9 + AEvent.Payload);
end;

{ ==================== the fixture's numbers ==================== }

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-visualmap-interact.json';
end;

function HexNum(AData: TJSONData): Double;
var q: QWord;
begin
  if (AData = nil) or (AData.JSONType = jtNull) then Exit(NaN);
  q := StrToQWord('$' + AData.AsString);
  Result := 0;
  System.Move(q, Result, SizeOf(Result));
end;

function Fmt(A: Double): string;
var fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := FloatToStrF(A, ffGeneral, 17, 0, fs);
end;

function NoNul(const S: string): string;
begin
  Result := StringReplace(S, #0, '', [rfReplaceAll]);
end;

function AlignWord(AH: TTyTextAnchorH): string;
begin
  case AH of
    tahCentre: Result := 'center';
    tahRight: Result := 'right';
  else
    Result := 'left';
  end;
end;

function VAlignWord(AV: TTyTextAnchorV): string;
begin
  case AV of
    tavMiddle: Result := 'middle';
    tavBottom: Result := 'bottom';
  else
    Result := 'top';
  end;
end;

{ the numbers of a JS array literal as written: '[0,95]' -> '0', '95' }
function ArrayWords(const AJson, AKey: string): TStringList;
var p, q: Integer; body: string;
begin
  Result := TStringList.Create;
  p := Pos('"' + AKey + '":[', AJson);
  if p = 0 then Exit;
  p := p + Length(AKey) + 4;
  q := p;
  while (q <= Length(AJson)) and (AJson[q] <> ']') do Inc(q);
  body := Copy(AJson, p, q - p);
  Result.Delimiter := ',';
  Result.StrictDelimiter := True;
  Result.DelimitedText := body;
end;

{ ==================== the oracle test ==================== }

procedure TAdvChartVisualMapInteractOracleTest.SetUp;
var sl: TStringList; ms: TJSONArray; k: Integer;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := nil;
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FMeas := TVmiMeasurer.Create;
  FMeasRef := FMeas;
  ms := TJSONObject(FRoot).Arrays['measure'];
  for k := 0 to ms.Count - 1 do
    FMeas.Add(ms.Objects[k].Strings['string'], HexNum(ms.Objects[k].Find('width')),
      HexNum(ms.Objects[k].Find('height')));
  FBad := 0;
  FCompared := 0;
  FSteps := 0;
  FReport := '';
end;

procedure TAdvChartVisualMapInteractOracleTest.TearDown;
begin
  FreeAndNil(FRoot);
  if FChart <> nil then FChart.Measurer := nil;
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartVisualMapInteractOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 80 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartVisualMapInteractOracleTest.SameHex(const AWhat: string;
  AGot: Double; AObj: TJSONObject; const AKey: string; AIndex: Integer);
var d: TJSONData; want: Double; ok: Boolean;
begin
  Inc(FCompared);
  d := AObj.Find(AKey);
  if (AIndex >= 0) and (d is TJSONArray) then
  begin
    if AIndex < TJSONArray(d).Count then d := TJSONArray(d).Items[AIndex] else d := nil;
  end;
  want := HexNum(d);
  if IsNan(want) or IsNan(AGot) then ok := IsNan(want) and IsNan(AGot)
  else ok := AGot = want;
  if not ok then
    Miss(Format('%s is %s upstream, %s here', [AWhat, Fmt(want), Fmt(AGot)]));
end;

procedure TAdvChartVisualMapInteractOracleTest.SameStr(const AWhat, AGot, AWant: string);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Miss(Format('%s is "%s" upstream, "%s" here', [AWhat, AWant, AGot]));
end;

procedure TAdvChartVisualMapInteractOracleTest.SameBool(const AWhat: string;
  AGot, AWant: Boolean);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Miss(Format('%s is %s upstream, %s here', [AWhat, BoolToStr(AWant, True),
      BoolToStr(AGot, True)]));
end;

{ a colour against zrender's parse of the element's fill ([r, g, b, a] or
  null): channels and alpha exactly }
procedure TAdvChartVisualMapInteractOracleTest.SameColour(const AWhat: string;
  AR, AG, AB, AA: Double; AWant: TJSONData);
var a: TJSONArray;
begin
  Inc(FCompared);
  if not (AWant is TJSONArray) then
  begin
    if not IsNan(AR) then Miss(AWhat + ': no fill upstream, one here');
    Exit;
  end;
  a := TJSONArray(AWant);
  if IsNan(AR) then
  begin
    Miss(AWhat + ': a fill upstream, none here');
    Exit;
  end;
  if (AR <> a.Items[0].AsFloat) or (AG <> a.Items[1].AsFloat)
    or (AB <> a.Items[2].AsFloat) or (AA <> a.Items[3].AsFloat) then
    Miss(Format('%s is rgba(%s,%s,%s,%s) upstream, rgba(%s,%s,%s,%s) here',
      [AWhat, Fmt(a.Items[0].AsFloat), Fmt(a.Items[1].AsFloat), Fmt(a.Items[2].AsFloat),
       Fmt(a.Items[3].AsFloat), Fmt(AR), Fmt(AG), Fmt(AB), Fmt(AA)]));
end;

procedure TAdvChartVisualMapInteractOracleTest.NewChart(AAnimated: Boolean);
begin
  FreeAndNil(FChart);
  FChart := TVmiProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := FMeasRef;
  FChart.SetBounds(0, 0, FRoot.FindPath('W').AsInteger, FRoot.FindPath('H').AsInteger);
  if AAnimated then
  begin
    FChart.AnimationMode := camAlways;
    FChart.AnimNow := T0;
  end
  else
    FChart.AnimationMode := camOff;
  FChart.ChartOn('highlight', @FChart.OnEv);
  FChart.ChartOn('downplay', @FChart.OnEv);
  FChart.ChartOn('datarangeselected', @FChart.OnEv);
end;

procedure TAdvChartVisualMapInteractOracleTest.RenderNow;
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(FRoot.FindPath('W').AsInteger, FRoot.FindPath('H').AsInteger,
    BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, bmp.Width, bmp.Height), 96);
  finally
    bmp.Free;
  end;
end;

function TAdvChartVisualMapInteractOracleTest.SeriesOfId(const AId: string): Integer;
var s: Integer;
begin
  for s := 0 to 9 do
    if NoNul(FChart.ComponentModelId('series', s)) = NoNul(AId) then Exit(s);
  Result := -1;
end;

{ the events the handlers got against the recorded ones, in order: the type,
  a batch's series, indices and key, a datarangeselected's visualMap, `from`
  and selection }
procedure TAdvChartVisualMapInteractOracleTest.CheckEvents(AStep: TJSONObject);
var
  want: TJSONArray;
  w, wb: TJSONObject;
  i, j, k, tab: Integer;
  t, payload, what: string;
  p, b, sel, x: TJSONData;
  words: TStringList;
  pa, wsel: TJSONArray;
  idx: string;
begin
  want := AStep.Arrays['events'];
  Inc(FCompared);
  if FChart.Events.Count <> want.Count then
  begin
    Miss(Format('%d events upstream, %d here', [want.Count, FChart.Events.Count]));
    for i := 0 to FChart.Events.Count - 1 do Miss('  here: ' + NoNul(FChart.Events[i]));
    for i := 0 to want.Count - 1 do Miss('  upstream: ' + want.Items[i].AsJSON);
    Exit;
  end;
  for i := 0 to want.Count - 1 do
  begin
    w := TJSONObject(want.Items[i]);
    tab := Pos(#9, FChart.Events[i]);
    t := Copy(FChart.Events[i], 1, tab - 1);
    payload := Copy(FChart.Events[i], tab + 1, MaxInt);
    what := Format('event %d', [i]);
    SameStr(what + ' type', t, w.Strings['type']);
    if t <> w.Strings['type'] then Continue;
    p := GetJSON(payload);
    try
      if t = 'datarangeselected' then
      begin
        x := TJSONObject(p).Find('visualMapId');
        k := -1;
        if x <> nil then
          for j := 0 to 9 do
            if NoNul(FChart.ComponentModelId('visualMap', j)) = NoNul(x.AsString) then k := j;
        SameStr(what + ' visualMap', IntToStr(k), IntToStr(w.Get('vm', -1)));
        SameBool(what + ' from', TJSONObject(p).Find('from') <> nil, w.Booleans['from']);
        sel := TJSONObject(p).Find('selected');
        if w.Find('selectedText') <> nil then
        begin
          { the numbers as written: JavaScript's shortest form on both sides }
          words := ArrayWords(payload, 'selected');
          try
            wsel := w.Arrays['selectedText'];
            SameStr(what + ' selected count', IntToStr(words.Count), IntToStr(wsel.Count));
            for j := 0 to wsel.Count - 1 do
              if j < words.Count then SameStr(what + ' selected ' + IntToStr(j), words[j], wsel.Strings[j])
              else Miss(what + ' selected: too few');
          finally
            words.Free;
          end;
        end
        else if w.Find('selected') is TJSONArray then
        begin
          { [[key, value]] in the object's key order }
          wsel := w.Arrays['selected'];
          if not (sel is TJSONObject) then
          begin
            Miss(what + ': no selected map here');
            Continue;
          end;
          SameStr(what + ' selected keys', IntToStr(TJSONObject(sel).Count), IntToStr(wsel.Count));
          for j := 0 to Min(wsel.Count, TJSONObject(sel).Count) - 1 do
          begin
            SameStr(what + ' selected key ' + IntToStr(j), TJSONObject(sel).Names[j],
              TJSONArray(wsel.Items[j]).Items[0].AsString);
            SameStr(what + ' selected value ' + IntToStr(j), TJSONObject(sel).Items[j].AsJSON,
              TJSONArray(wsel.Items[j]).Items[1].AsJSON);
          end;
        end;
        Continue;
      end;
      { highlight / downplay }
      b := TJSONObject(p).Find('batch');
      if w.Find('batch') is TJSONArray then
      begin
        if not (b is TJSONArray) then
        begin
          Miss(what + ': a batch upstream, none here');
          Continue;
        end;
        pa := TJSONArray(b);
        SameStr(what + ' batch length', IntToStr(pa.Count), IntToStr(w.Arrays['batch'].Count));
        for j := 0 to Min(pa.Count, w.Arrays['batch'].Count) - 1 do
        begin
          wb := TJSONObject(w.Arrays['batch'].Items[j]);
          x := TJSONObject(pa.Items[j]).Find('seriesId');
          if x <> nil then k := SeriesOfId(x.AsString) else k := -1;
          SameStr(what + ' item ' + IntToStr(j) + ' series', IntToStr(k), IntToStr(wb.Get('s', -1)));
          x := TJSONObject(pa.Items[j]).Find('dataIndexInside');
          if x <> nil then idx := x.AsJSON else idx := 'null';
          SameStr(what + ' item ' + IntToStr(j) + ' indices', StringReplace(idx, ' ', '', [rfReplaceAll]),
            StringReplace(wb.Find('idx').AsJSON, ' ', '', [rfReplaceAll]));
          x := TJSONObject(pa.Items[j]).Find('highlightKey');
          if x <> nil then idx := x.AsString else idx := '';
          SameStr(what + ' item ' + IntToStr(j) + ' key', idx, wb.Get('key', ''));
        end;
      end;
    finally
      p.Free;
    end;
  end;
end;

procedure TAdvChartVisualMapInteractOracleTest.CheckVm(AIndex: Integer; AVm: TJSONObject;
  AAnimated: Boolean);
var
  spec: TTyVisualMapSpec;
  L: TTyVisualMapLayout;
  live: TTyVmLive;
  what, s: string;
  m, h, il, ind: TJSONObject;
  i, j, n: Integer;
  pts: TJSONArray;
  hi: TJSONArray;
  r, g, b, a: Double;
  sel, x: TJSONData;
  ws: TJSONArray;
begin
  what := 'vm' + IntToStr(AIndex);
  spec := FChart.VisualMapSpec(AIndex);
  L := FChart.VisualMapLayout(AIndex);
  live := FChart.VisualMapLive(AIndex);
  m := AVm.Objects['model'];
  if AVm.Strings['subType'] = 'piecewise' then
  begin
    { the model's selected map, in key order }
    sel := GetJSON(FChart.VisualMapSelectedText(AIndex));
    try
      ws := m.Arrays['selected'];
      if not (sel is TJSONObject) then
      begin
        Miss(what + ': no selected map');
        Exit;
      end;
      SameStr(what + ' selected keys', IntToStr(TJSONObject(sel).Count), IntToStr(ws.Count));
      for j := 0 to Min(ws.Count, TJSONObject(sel).Count) - 1 do
      begin
        SameStr(what + ' selected key ' + IntToStr(j), TJSONObject(sel).Names[j],
          TJSONArray(ws.Items[j]).Items[0].AsString);
        SameStr(what + ' selected value ' + IntToStr(j), TJSONObject(sel).Items[j].AsJSON,
          TJSONArray(ws.Items[j]).Items[1].AsJSON);
      end;
    finally
      sel.Free;
    end;
    { the items in view order }
    n := 0;
    for i := 0 to High(L.Items) do
    begin
      if L.Items[i].IsText then Continue;
      if n >= AVm.Arrays['items'].Count then
      begin
        Miss(what + ': more items here');
        Break;
      end;
      h := TJSONObject(AVm.Arrays['items'].Items[n]);
      SameStr(what + ' item ' + IntToStr(n) + ' piece', IntToStr(L.Items[i].PieceIndex),
        IntToStr(h.Integers['piece']));
      SameColour(what + ' item ' + IntToStr(n) + ' fill', L.Items[i].Fill.R, L.Items[i].Fill.G,
        L.Items[i].Fill.B, L.Items[i].Fill.A, h.Find('fill'));
      x := h.Find('labelOpacity');
      if L.Items[i].HasLabel then
      begin
        if (x = nil) or (x.JSONType = jtNull) then Miss(what + ': a label here only')
        else if x.AsFloat <> L.Items[i].LabelOpacity then
          Miss(Format('%s item %d label opacity is %s upstream, %s here',
            [what, n, Fmt(x.AsFloat), Fmt(L.Items[i].LabelOpacity)]));
      end;
      Inc(n);
    end;
    SameStr(what + ' items', IntToStr(n), IntToStr(AVm.Arrays['items'].Count));
    Exit;
  end;
  { ---- continuous ---- }
  SameHex(what + ' range0', spec.Range0, m, 'range', 0);
  SameHex(what + ' range1', spec.Range1, m, 'range', 1);
  SameBool(what + ' alive', live.Alive, True);
  if not live.Alive then Exit;
  SameHex(what + ' interval0', live.Interval[0], AVm, 'interval', 0);
  SameHex(what + ' interval1', live.Interval[1], AVm, 'interval', 1);
  SameHex(what + ' end0', live.Ends[0], AVm, 'handleEnds', 0);
  SameHex(what + ' end1', live.Ends[1], AVm, 'handleEnds', 1);
  SameBool(what + ' dragging', live.Dragging, AVm.Booleans['dragging']);
  SameBool(what + ' hovering', live.Hovering, AVm.Booleans['hovering']);
  SameBool(what + ' firstShow', live.FirstShow, AVm.Booleans['firstShow']);
  { the hover link's items: [[series, [inner...]]] }
  hi := AVm.Arrays['hoverIdx'];
  s := '[';
  for i := 0 to High(live.HoverIdx) do
  begin
    if i > 0 then s := s + ',';
    s := s + '[' + IntToStr(live.HoverIdx[i].SeriesIndex) + ',[';
    for j := 0 to High(live.HoverIdx[i].Inner) do
    begin
      if j > 0 then s := s + ',';
      s := s + IntToStr(live.HoverIdx[i].Inner[j]);
    end;
    s := s + ']]';
  end;
  s := s + ']';
  SameStr(what + ' hover link', s, StringReplace(hi.AsJSON, ' ', '', [rfReplaceAll]));
  SameHex(what + ' group x', L.GroupX, AVm, 'group', 0);
  SameHex(what + ' group y', L.GroupY, AVm, 'group', 1);
  pts := AVm.Arrays['inPts'];
  for i := 0 to Min(3, High(L.InPoints)) do
  begin
    SameHex(what + ' in-range point ' + IntToStr(i) + ' x', L.InPoints[i].X, AVm, 'inPts', 2 * i);
    SameHex(what + ' in-range point ' + IntToStr(i) + ' y', L.InPoints[i].Y, AVm, 'inPts', 2 * i + 1);
  end;
  if pts.Count <> 2 * Length(L.InPoints) then Miss(what + ': the in-range bar has another shape');
  SameStr(what + ' handles', IntToStr(Length(L.Handles)), IntToStr(AVm.Arrays['handles'].Count));
  for i := 0 to Min(High(L.Handles), AVm.Arrays['handles'].Count - 1) do
  begin
    h := TJSONObject(AVm.Arrays['handles'].Items[i]);
    s := what + ' handle ' + IntToStr(i);
    SameHex(s + ' x', L.Handles[i].Local[4], h, 'x');
    SameHex(s + ' y', L.Handles[i].Local[5], h, 'y');
    SameHex(s + ' scale', L.Handles[i].Local[0], h, 'scale');
    if live.ThumbFill[i].Defined then
      SameColour(s + ' fill', live.ThumbFill[i].R, live.ThumbFill[i].G, live.ThumbFill[i].B,
        live.ThumbFill[i].A, h.Find('fill'))
    else
      SameColour(s + ' fill', NaN, NaN, NaN, NaN, h.Find('fill'));
    SameStr(s + ' hover', IntToStr(live.ThumbHover[i]), IntToStr(h.Integers['hover']));
    SameBool(s + ' emphasis', live.ThumbEmph[i], h.Booleans['emph']);
    il := h.Objects['label'];
    SameStr(s + ' label', live.Labels[i].Text, il.Strings['text']);
    SameHex(s + ' label x', live.Labels[i].X, il, 'x');
    SameHex(s + ' label y', live.Labels[i].Y, il, 'y');
    SameStr(s + ' label align', AlignWord(live.Labels[i].AlignH), il.Strings['align']);
    SameBool(s + ' label blur', live.LabelBlurOn[i], il.Booleans['blur']);
  end;
  { the indicator, where it is now }
  ind := AVm.Objects['indicator'];
  SameBool(what + ' indicator shown', live.IndVisible, not ind.Booleans['invisible']);
  SameHex(what + ' indicator x', live.IndX, ind, 'x');
  SameHex(what + ' indicator y', live.IndY, ind, 'y');
  if TyTryParseCssRgba(live.IndFill, r, g, b, a) then
    SameColour(what + ' indicator fill', r, g, b, a, ind.Find('fill'))
  else
    SameColour(what + ' indicator fill', NaN, NaN, NaN, NaN, ind.Find('fill'));
  il := AVm.Objects['indLabel'];
  SameBool(what + ' indicator label shown', live.IndLabelVisible, not il.Booleans['invisible']);
  SameStr(what + ' indicator label', live.IndLabel.Text, il.Strings['text']);
  SameHex(what + ' indicator label x', live.IndLabel.X, il, 'x');
  SameHex(what + ' indicator label y', live.IndLabel.Y, il, 'y');
  if live.IndLabelVisible then
  begin
    SameStr(what + ' indicator label align', AlignWord(live.IndLabel.AlignH), il.Get('align', ''));
    SameStr(what + ' indicator label vertical align', VAlignWord(live.IndLabel.AlignV),
      il.Get('verticalAlign', ''));
  end;
end;

procedure TAdvChartVisualMapInteractOracleTest.CheckSeries(AStep: TJSONObject);
var
  ser, list: TJSONArray;
  s, i, inner: Integer;
  w: TJSONObject;
  item: TTyStItem;
  what: string;
  hover, op: Double;
  hbo: Boolean;
  c: TTyChartColor;
  wf: TJSONData;
begin
  ser := AStep.Arrays['series'];
  for s := 0 to ser.Count - 1 do
  begin
    if not (ser.Items[s] is TJSONArray) then Continue;
    list := TJSONArray(ser.Items[s]);
    for i := 0 to list.Count - 1 do
    begin
      w := TJSONObject(list.Items[i]);
      inner := w.Integers['i'];
      what := Format('series %d item %d', [s, inner]);
      if not FChart.ItemStates(s, inner, item) then
      begin
        Miss(what + ': no element here');
        Continue;
      end;
      if item.HasGroup then hover := item.GroupHover else hover := item.Host.HoverState;
      SameStr(what + ' hover', IntToStr(Round(hover)), IntToStr(w.Integers['hover']));
      hbo := (item.Host.HighByOuter <> 0) or (item.HasGroup and (item.GroupHbo <> 0));
      SameBool(what + ' held by an action', hbo, w.Booleans['hbo']);
      SameStr(what + ' states', TyStNamesText(item.Host.States), w.Strings['states']);
      { the drawn fill, packed: the channels and the alpha as a byte }
      c := item.Host.Cur.Color[stkFill];
      wf := w.Find('fill');
      Inc(FCompared);
      if wf is TJSONArray then
      begin
        if ((c shr 16) and $FF <> TJSONArray(wf).Items[0].AsInteger)
          or ((c shr 8) and $FF <> TJSONArray(wf).Items[1].AsInteger)
          or (c and $FF <> TJSONArray(wf).Items[2].AsInteger)
          or ((c shr 24) and $FF <> Round(TJSONArray(wf).Items[3].AsFloat * 255)) then
          Miss(Format('%s fill is %s upstream, %s here', [what, w.Strings['fillText'],
            IntToHex(c, 8)]));
      end;
      if item.Host.Cur.Has[stkOpacity] then op := item.Host.Cur.Num[stkOpacity] else op := 1;
      Inc(FCompared);
      if Abs(op - w.Floats['opacity']) > 1e-12 then
        Miss(Format('%s opacity is %s upstream, %s here', [what, Fmt(w.Floats['opacity']), Fmt(op)]));
    end;
  end;
end;

procedure TAdvChartVisualMapInteractOracleTest.TestEveryDragHoverAndClickActsAsUpstream;
var
  cases, steps, vms: TJSONArray;
  c, st: TJSONObject;
  ci, si, k: Integer;
  t, role, want: string;
  animated: Boolean;
  x, y: Integer;
  nowMs: Double;
  d: TJSONData;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for ci := 0 to cases.Count - 1 do
  begin
    c := TJSONObject(cases.Items[ci]);
    animated := c.Booleans['animated'];
    NewChart(animated);
    steps := c.Arrays['steps'];
    for si := 0 to steps.Count - 1 do
    begin
      st := TJSONObject(steps.Items[si]);
      FName := c.Strings['id'] + '/' + IntToStr(si) + ' ' + st.Strings['t'];
      t := st.Strings['t'];
      nowMs := T0 + 3000 + st.Floats['now'];
      FChart.Events.Clear;
      if animated and (t <> 'init') then FChart.AnimNow := nowMs;
      if t = 'init' then
      begin
        FChart.SetOption(c.Objects['option'].AsJSON, True);
        RenderNow;
        if animated then
        begin
          { the enter animation runs out, as the oracle's first frames }
          for k := 1 to 12 do
          begin
            FChart.AnimTick(T0 + 250 * k);
            RenderNow;
          end;
          FChart.AnimNow := nowMs;
          FChart.AnimTick(nowMs);
          RenderNow;
          if FChart.AnimClipCount > 0 then Miss('the enter animation still runs');
        end;
        { the first render's events are not the step's }
        FChart.Events.Clear;
      end
      else
      begin
        d := st.Find('x');
        if (d <> nil) and (d.JSONType = jtNumber) then
        begin
          x := st.Integers['x'];
          y := st.Integers['y'];
          { what the pointer is over before the step }
          role := FChart.VisualMapRoleAt(x, y);
          d := st.Find('hover');
          if (d <> nil) and (d.JSONType = jtString) and (Copy(d.AsString, 1, 2) = 'vm') then
            want := d.AsString
          else
            want := '';
          SameStr('the element under the pointer', role, want);
        end;
        if t = 'move' then FChart.Move(x, y)
        else if t = 'down' then FChart.Down(x, y)
        else if t = 'up' then FChart.Up(x, y)
        else if t = 'out' then FChart.Leave
        else if t = 'action' then
        begin
          if not FChart.DispatchAction(st.Objects['payload'].AsJSON) then
            Miss('the action was refused');
        end
        else if t = 'set' then
          FChart.SetOption(st.Objects['option'].AsJSON, st.Booleans['notMerge'])
        else if t <> 'frame' then
          Miss('an unknown step');
        if animated then FChart.AnimTick(nowMs);
        RenderNow;
      end;
      Inc(FSteps);
      CheckEvents(st);
      vms := st.Arrays['vms'];
      for k := 0 to vms.Count - 1 do
        CheckVm(k, TJSONObject(vms.Items[k]), animated);
      if not animated then CheckSeries(st);
    end;
  end;
  FName := '';
  if FMeas.Missed <> '' then Miss('texts the table does not measure:' + FMeas.Missed);
  AssertTrue('every step was compared', FSteps > 200);
  AssertEquals(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), 0, FBad);
end;

{ ==================== by hand ==================== }

procedure TAdvChartVisualMapInteractTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TVmiProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, 600, 400);
  FChart.AnimationMode := camOff;
  FChart.ChartOn('highlight', @FChart.OnEv);
  FChart.ChartOn('downplay', @FChart.OnEv);
  FChart.ChartOn('datarangeselected', @FChart.OnEv);
end;

procedure TAdvChartVisualMapInteractTest.TearDown;
begin
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartVisualMapInteractTest.RenderNow;
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, 600, 400), 96);
  finally
    bmp.Free;
  end;
end;

const
  cBar = '{"animation":false,"grid":{"left":60,"right":140,"top":40,"bottom":70},'
    + '"xAxis":{"type":"category","data":["a","b","c","d","e"]},"yAxis":{"type":"value"},'
    + '"series":[{"type":"bar","data":[10,30,50,70,90]}],';

procedure TAdvChartVisualMapInteractTest.Show(const AOption: string);
begin
  FChart.SetOption(AOption, True);
  RenderNow;
  FChart.Events.Clear;
end;

{ the thumb's centre on the canvas }
function ThumbAt(AChart: TTyAdvanceChart; AHandle: Integer): TPoint;
var
  L: TTyVisualMapLayout;
  pr: TTyXYWH;
  cx, cy: Double;
  M: TTyMat2D;
begin
  L := AChart.VisualMapLayout(0);
  M := L.Handles[AHandle].Thumb;
  pr := L.Handles[AHandle].PathRect;
  cx := pr.X + pr.W / 2;
  cy := pr.Y + pr.H / 2;
  Result := Point(Round(M[0] * cx + M[2] * cy + M[4] + L.GroupX),
    Round(M[1] * cx + M[3] * cy + M[5] + L.GroupY));
end;

procedure TAdvChartVisualMapInteractTest.TestALostCaptureEndsAHandleDrag;
var p: TPoint; before: Double;
begin
  Show(cBar + '"visualMap":{"type":"continuous","min":0,"max":100,"calculable":true,'
    + '"realtime":false,"right":20,"top":"middle"}}');
  p := ThumbAt(FChart, 1);
  AssertEquals('the press is on the upper thumb', 'vm0.handle1', FChart.VisualMapRoleAt(p.X, p.Y));
  before := FChart.VisualMapSpec(0).Range1;
  FChart.Move(p.X, p.Y);
  FChart.Down(p.X, p.Y);
  FChart.Move(p.X, p.Y + 20);
  AssertEquals('a drag that is not realtime has not dispatched', 0,
    FChart.Count('datarangeselected'));
  AssertTrue('it drags', FChart.VisualMapLive(0).Dragging);
  { another window takes the mouse: the release is where it was last }
  FChart.LoseCapture;
  AssertEquals('the release dispatched', 1, FChart.Count('datarangeselected'));
  AssertFalse('the drag is over', FChart.VisualMapLive(0).Dragging);
  AssertTrue('and its range went into the model', FChart.VisualMapSpec(0).Range1 < before);
end;

procedure TAdvChartVisualMapInteractTest.TestAPressOnAHandleIsNotAPan;
var p: TPoint; lo, hi: Double;
begin
  Show(cBar + '"dataZoom":[{"type":"inside"}],"visualMap":{"type":"continuous","min":0,"max":100,'
    + '"calculable":true,"right":20,"top":"middle"}}');
  p := ThumbAt(FChart, 0);
  FChart.Move(p.X, p.Y);
  FChart.Down(p.X, p.Y);
  FChart.Move(p.X, p.Y - 30);
  FChart.Up(p.X, p.Y - 30);
  AssertTrue('the lower end moved up', FChart.VisualMapSpec(0).Range0 > 0);
  AssertTrue(FChart.DataZoomInsideRange(0, lo, hi));
  AssertEquals('the zoom did not pan: start', 0, lo, 0);
  AssertEquals('the zoom did not pan: end', 100, hi, 0);
end;

procedure TAdvChartVisualMapInteractTest.TestSelectDataRangeByIdAndName;
begin
  Show(cBar + '"visualMap":[{"type":"continuous","id":"a","min":0,"max":100},'
    + '{"type":"continuous","name":"b","min":0,"max":100,"right":80}]}');
  AssertTrue(FChart.DispatchAction('{"type":"selectDataRange","visualMapId":"a","selected":[20,40]}'));
  AssertEquals('by id: the first', 20, FChart.VisualMapSpec(0).Range0, 0);
  AssertEquals('not the second', 0, FChart.VisualMapSpec(1).Range0, 0);
  AssertTrue(FChart.DispatchAction('{"type":"selectDataRange","visualMapName":"b","selected":[30,60]}'));
  AssertEquals('by name: the second', 30, FChart.VisualMapSpec(1).Range0, 0);
  AssertEquals('the first kept', 20, FChart.VisualMapSpec(0).Range0, 0);
  AssertTrue(FChart.DispatchAction('{"type":"selectDataRange","visualMapIndex":[0,1],"selected":[5,95]}'));
  AssertEquals('by a list of indices', 5, FChart.VisualMapSpec(0).Range0, 0);
  AssertEquals('both', 5, FChart.VisualMapSpec(1).Range0, 0);
end;

procedure TAdvChartVisualMapInteractTest.TestABatchOfAnotherTypeIsRefused;
begin
  Show(cBar + '"visualMap":{"type":"continuous","min":0,"max":100}}');
  { [Batch 141] select batches are taken now; restore takes none }
  AssertFalse('a restore batch is not taken',
    FChart.DispatchAction('{"type":"restore","batch":[{"seriesIndex":0,"dataIndex":1}]}'));
end;

procedure TAdvChartVisualMapInteractTest.TestAHighlightBatchIsOneEventWithEveryItem;
var item: TTyStItem; p: TJSONData;
begin
  Show(cBar + '"visualMap":{"type":"continuous","min":0,"max":100}}');
  AssertTrue(FChart.DispatchAction('{"type":"highlight","highlightKey":"k","batch":['
    + '{"seriesIndex":0,"dataIndexInside":[1,2]},{"seriesIndex":0,"dataIndexInside":[4]}]}'));
  RenderNow;
  AssertEquals('one event', 1, FChart.Events.Count);
  p := GetJSON(Copy(FChart.Events[0], Pos(#9, FChart.Events[0]) + 1, MaxInt));
  try
    AssertEquals('with both items', 2, TJSONObject(p).Arrays['batch'].Count);
    AssertEquals('the indices of the second item', '[4]',
      StringReplace(TJSONObject(TJSONObject(p).Arrays['batch'].Items[1]).Arrays['dataIndexInside'].AsJSON,
        ' ', '', [rfReplaceAll]));
    AssertEquals('each item took the outer key', 'k',
      TJSONObject(TJSONObject(p).Arrays['batch'].Items[1]).Strings['highlightKey']);
    AssertTrue('and its batch is null',
      TJSONObject(TJSONObject(p).Arrays['batch'].Items[1]).Find('batch').JSONType = jtNull);
  finally
    p.Free;
  end;
  AssertTrue(FChart.ItemStates(0, 2, item));
  AssertEquals('the second item is held', 2, item.Host.HoverState);
  AssertTrue(FChart.ItemStates(0, 4, item));
  AssertEquals('the fifth too', 2, item.Host.HoverState);
  AssertTrue(FChart.ItemStates(0, 3, item));
  AssertEquals('not the fourth', 0, item.Host.HoverState);
end;

procedure TAdvChartVisualMapInteractTest.TestTheIndicatorIsDrawnWhereItIs;
var
  L: TTyVisualMapLayout;
  live: TTyVmLive;
  list: TTyPaintList;
  i, n: Integer;
  bx, by: Double;
begin
  Show(cBar + '"visualMap":{"type":"continuous","min":0,"max":100,"right":20,"top":"middle"}}');
  L := FChart.VisualMapLayout(0);
  { the middle of the bar }
  bx := L.GroupX + L.Bar[0] * (L.ItemW / 2) + L.Bar[2] * (L.ItemH / 2) + L.Bar[4];
  by := L.GroupY + L.Bar[1] * (L.ItemW / 2) + L.Bar[3] * (L.ItemH / 2) + L.Bar[5];
  FChart.Move(Round(bx), Round(by));
  RenderNow;
  live := FChart.VisualMapLive(0);
  AssertTrue('the indicator shows', live.IndVisible);
  list := FChart.List;
  n := 0;
  for i := 0 to list.Count - 1 do
    if (list.Element(i).Caption.Text = live.IndLabel.Text) and (live.IndLabel.Text <> '') then Inc(n);
  AssertEquals('its label is drawn once', 1, n);
end;

{ [Milestone D9-D14] hoverLink shows the indicator and highlights the items
  in range when the pointer is on the bar, and takes both away when it
  leaves -- each a change of what the visualMap draws. The pointer's next
  event must still find what is under it: zrender's storage is current the
  moment the states change, and a press usually comes before the paint the
  move asked for (input outranks WM_PAINT). }
procedure TAdvChartVisualMapInteractTest.TestAClickAfterAHoverLinkNeedsNoRepaint;
var
  L: TTyVisualMapLayout;
  bx, by: Double;
begin
  FChart.ChartOn('click', @FChart.OnEv);
  FChart.ChartOn('mouseover', @FChart.OnEv);
  Show(cBar + '"visualMap":{"type":"continuous","min":0,"max":100,"right":20,"top":"middle"}}');
  AssertEquals('the last bar is under (420, 300)', 4, FChart.HitTestAt(420, 300).DataIndex);
  L := FChart.VisualMapLayout(0);
  bx := L.GroupX + L.Bar[0] * (L.ItemW / 2) + L.Bar[2] * (L.ItemH / 2) + L.Bar[4];
  by := L.GroupY + L.Bar[1] * (L.ItemW / 2) + L.Bar[3] * (L.ItemH / 2) + L.Bar[5];
  { on the bar: the indicator and the highlight; no paint after it }
  FChart.Move(Round(bx), Round(by));
  AssertTrue('the indicator shows', FChart.VisualMapLive(0).IndVisible);
  AssertEquals('still the last bar there', 4, FChart.HitTestAt(420, 300).DataIndex);
  { off it, onto the last bar (the series' mouseover shows the indicator at
    its value), and a click there -- still no paint }
  FChart.Move(420, 300);
  AssertTrue('the indicator from the series', FChart.VisualMapLive(0).IndVisible);
  FChart.Down(420, 300);
  FChart.Up(420, 300);
  AssertEquals('the click found the bar', 1, FChart.Count('click'));
  AssertEquals('one mouseover on it', 1, FChart.Count('mouseover'));
end;

initialization
  RegisterTest(TAdvChartVisualMapInteractOracleTest);
  RegisterTest(TAdvChartVisualMapInteractTest);
end.
