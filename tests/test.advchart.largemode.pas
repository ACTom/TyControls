unit test.advchart.largemode;
{$mode objfpc}{$H+}
{ Large mode -- held to upstream to the bit [Batch 117, C8].

  tools/advchart-oracle/large-mode.js runs the real ECharts 6.1 build
  through bar, scatter and candlestick series on both sides of their
  thresholds and records, after the first render and after every dataZoom
  step: whether each series was drawn as a batch, the batch's points (the
  Float32 layout), its indices, widths, sizes, symbol type, boost, soft
  clip, sign, style, bounding rect and the view group's clip; and after
  every pointer step and action: the element and the row under the pointer,
  the chart mouse events, the tooltip, and the states of every large
  element and of the normal items a case watches.

  The port is driven the same way -- SetOption, MouseMove / MouseLeave,
  DispatchAction, DispatchDataZoom -- with a headless render after each
  step, and compared through SeriesLargeKind, the paint list's cskLarge
  elements, HitTestAt, the mouse events' params, TooltipShown /
  TooltipShownDatum / TooltipShownWhich and ItemStates. Every number to the
  bit. The default colours of a candlestick are the theme's here, so a
  stroke colour is compared only where the case wrote one. }
interface
uses Classes, SysUtils, Math, DateUtils, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint,
     tyControls.AdvanceChart.Shape, tyControls.AdvanceChart.Large,
     tyControls.AdvanceChart.States, tyControls.AdvanceChart.Events,
     tyControls.AdvanceChart.Symbol, tyControls.AdvanceChart.Data,
     tyControls.AdvanceChart;
type
  TLmProbe = class(TTyAdvanceChart)
  public
    Events: TStringList;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Move(AX, AY: Integer);
    procedure Leave;
    function List: TTyPaintList;
    procedure OnEv(Sender: TObject; const AEvent: TTyChartEvent);
  end;

  TAdvChartLargeModeOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TLmProbe;
    FRoot: TJSONData;
    FBad, FCompared, FSteps: Integer;
    FReport, FName: string;
    procedure Miss(const AWhat: string);
    procedure SameHex(const AWhat: string; AGot: Double; AWant: TJSONData);
    procedure SameStr(const AWhat, AGot, AWant: string);
    procedure SameInt(const AWhat: string; AGot, AWant: Integer);
    procedure SameColour(const AWhat: string; AGot: TTyChartColor; AWant: TJSONData);
    procedure NewChart;
    procedure RenderNow;
    procedure CheckRecord(ARec: TJSONObject; const AOption: TJSONObject);
    procedure CheckStep(AStep: TJSONObject);
    function LargeEls(ASeries: Integer): TTyIntegerArray;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEveryBatchAndEveryHitAsUpstream;
  end;

  { What the oracle does not reach. }
  TAdvChartLargeModeTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TLmProbe;
    procedure Show(const AOption: string; AW: Integer = 600; AH: Integer = 400);
    procedure RenderNow(AW: Integer = 600; AH: Integer = 400);
    function CountLarge(ASeries: Integer): Integer;
    function CountRows(ASeries: Integer): Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheSwitchReadsJavaScriptValues;
    procedure TestTheScansFindTheRightRow;
    procedure TestABatchIsOneElementNotOnePerRow;
    procedure TestTheBatchIsPainted;
    procedure TestTiledCirclesAreSubPathsOfTheirOwn;
    procedure TestLeavingLargeModeBringsTheStatesBack;
    procedure TestAPathSymbolStaysOneElementPerRow;
    procedure TestABatchHasNoEnterAnimation;
    procedure TestAHundredThousandPoints;
  end;

implementation

{ ==================== helpers ==================== }

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-large-mode.json';
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
  if IsNan(A) then Exit('NaN');
  Result := FloatToStrF(A, ffGeneral, 17, 0, fs);
end;

function SymbolWord(AKind: Integer): string;
begin
  case TTySymbolKind(AKind) of
    tsyCircle: Result := 'circle';
    tsyRect: Result := 'rect';
    tsyRoundRect: Result := 'roundRect';
    tsySquare: Result := 'square';
    tsyTriangle: Result := 'triangle';
    tsyDiamond: Result := 'diamond';
    tsyPin: Result := 'pin';
    tsyArrow: Result := 'arrow';
    tsyLine: Result := 'line';
    tsyNone: Result := 'none';
  else
    Result := 'path';
  end;
end;

{ ==================== the probe ==================== }

constructor TLmProbe.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Events := TStringList.Create;
end;

destructor TLmProbe.Destroy;
begin
  Events.Free;
  inherited Destroy;
end;

procedure TLmProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TLmProbe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TLmProbe.Leave;
begin
  MouseLeave;
end;

function TLmProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

procedure TLmProbe.OnEv(Sender: TObject; const AEvent: TTyChartEvent);
begin
  Events.Add(Format('%s'#9'%d'#9'%d'#9'%d', [AEvent.EventType, AEvent.Params.SeriesIndex,
    AEvent.Params.RawDataIndex, AEvent.Params.DataIndex]));
end;

{ ==================== the oracle test ==================== }

procedure TAdvChartLargeModeOracleTest.SetUp;
var sl: TStringList;
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
  FBad := 0;
  FCompared := 0;
  FSteps := 0;
  FReport := '';
end;

procedure TAdvChartLargeModeOracleTest.TearDown;
begin
  FreeAndNil(FRoot);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartLargeModeOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 80 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartLargeModeOracleTest.SameHex(const AWhat: string; AGot: Double;
  AWant: TJSONData);
var want: Double; ok: Boolean;
begin
  Inc(FCompared);
  want := HexNum(AWant);
  if IsNan(want) or IsNan(AGot) then ok := IsNan(want) and IsNan(AGot)
  else ok := AGot = want;
  if not ok then
    Miss(Format('%s is %s upstream, %s here', [AWhat, Fmt(want), Fmt(AGot)]));
end;

procedure TAdvChartLargeModeOracleTest.SameStr(const AWhat, AGot, AWant: string);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Miss(Format('%s is "%s" upstream, "%s" here', [AWhat, AWant, AGot]));
end;

procedure TAdvChartLargeModeOracleTest.SameInt(const AWhat: string; AGot, AWant: Integer);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Miss(Format('%s is %d upstream, %d here', [AWhat, AWant, AGot]));
end;

{ against zrender's parse ([r, g, b, a] or null): the channels and the alpha
  as a byte }
procedure TAdvChartLargeModeOracleTest.SameColour(const AWhat: string;
  AGot: TTyChartColor; AWant: TJSONData);
var a: TJSONArray;
begin
  Inc(FCompared);
  if not (AWant is TJSONArray) then
  begin
    Miss(AWhat + ': no colour upstream');
    Exit;
  end;
  a := TJSONArray(AWant);
  if ((AGot shr 16) and $FF <> Cardinal(a.Integers[0]))
    or ((AGot shr 8) and $FF <> Cardinal(a.Integers[1]))
    or (AGot and $FF <> Cardinal(a.Integers[2]))
    or ((AGot shr 24) and $FF <> Cardinal(Round(a.Floats[3] * 255))) then
    Miss(Format('%s is rgba(%d,%d,%d,%s) upstream, $%.8x here', [AWhat,
      a.Integers[0], a.Integers[1], a.Integers[2], Fmt(a.Floats[3]), AGot]));
end;

procedure TAdvChartLargeModeOracleTest.NewChart;
begin
  FreeAndNil(FChart);
  FChart := TLmProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, FRoot.FindPath('W').AsInteger, FRoot.FindPath('H').AsInteger);
  FChart.AnimationMode := camOff;
  FChart.ChartOn('mouseover', @FChart.OnEv);
  FChart.ChartOn('mousemove', @FChart.OnEv);
  FChart.ChartOn('mouseout', @FChart.OnEv);
end;

procedure TAdvChartLargeModeOracleTest.RenderNow;
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

{ the series' large elements, in the order they were added }
function TAdvChartLargeModeOracleTest.LargeEls(ASeries: Integer): TTyIntegerArray;
var list: TTyPaintList; k: Integer; el: TTyChartElement;
begin
  Result := nil;
  list := FChart.List;
  if list = nil then Exit;
  for k := 0 to list.Count - 1 do
  begin
    el := list.Element(k);
    if (el.Shape.Kind = cskLarge) and (el.Datum.SeriesIndex = ASeries) then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := k;
    end;
  end;
end;

{ one record: every series' mode and count, and every large element }
procedure TAdvChartLargeModeOracleTest.CheckRecord(ARec: TJSONObject;
  const AOption: TJSONObject);
var
  series, els, want: TJSONArray;
  s, e, si, j, n: Integer;
  sr, er: TJSONObject;
  got: TTyIntegerArray;
  el: TTyChartElement;
  g: TTyLargeGeom;
  isLarge, pinned: Boolean;
  what, kind, key: string;
  sopt: TJSONData;
  pts: TTyDoubleArray;
  st: TTyDataStore;
begin
  series := ARec.Arrays['series'];
  for s := 0 to series.Count - 1 do
  begin
    sr := series.Objects[s];
    si := sr.Integers['seriesIndex'];
    what := Format('series %d', [si]);
    isLarge := sr.Strings['mode'] = 'large';
    Inc(FCompared);
    if (FChart.SeriesLargeKind(si) <> lgkNone) <> isLarge then
    begin
      Miss(Format('%s is %s upstream, large %s here', [what, sr.Strings['mode'],
        BoolToStr(FChart.SeriesLargeKind(si) <> lgkNone, True)]));
      Continue;
    end;
    st := FChart.SeriesStore(si);
    if st <> nil then SameInt(what + ' count', st.Count, sr.Integers['count'])
    else Miss(what + ': no store');
    got := LargeEls(si);
    els := sr.Arrays['els'];
    SameInt(what + ' large elements', Length(got), els.Count);
    if Length(got) <> els.Count then Continue;
    { the case wrote the series' colours itself }
    sopt := AOption.FindPath('series[' + IntToStr(si) + '].itemStyle');
    pinned := sopt <> nil;
    for e := 0 to els.Count - 1 do
    begin
      er := els.Objects[e];
      el := FChart.List.Element(got[e]);
      g := el.Shape.Large;
      kind := er.Strings['kind'];
      what := Format('series %d %s %d', [si, kind, e]);
      if kind = 'barBg' then
        SameStr(what + ' kind', 'bar silent ' + BoolToStr(el.Silent, True), 'bar silent True')
      else if kind = 'bar' then
        SameStr(what + ' kind', 'bar silent ' + BoolToStr(el.Silent, True), 'bar silent False');
      if (kind = 'bar') or (kind = 'barBg') then
        SameInt(what + ' is a bar batch', Ord(g.Kind), Ord(lgkBar))
      else if kind = 'symbol' then
        SameInt(what + ' is a symbol batch', Ord(g.Kind), Ord(lgkSymbol))
      else
        SameInt(what + ' is a candle batch', Ord(g.Kind), Ord(lgkCandle));
      { the bounding rect }
      want := er.Arrays['bbox'];
      SameHex(what + ' bbox x', g.Box.X, want.Items[0]);
      SameHex(what + ' bbox y', g.Box.Y, want.Items[1]);
      SameHex(what + ' bbox w', g.Box.W, want.Items[2]);
      SameHex(what + ' bbox h', g.Box.H, want.Items[3]);
      { the points: a candle's are the series' }
      if kind = 'candle' then want := sr.Arrays['largePoints']
      else want := er.Arrays['points'];
      pts := g.Pts;
      SameInt(what + ' points', Length(pts), want.Count);
      if Length(pts) = want.Count then
      begin
        n := 0;
        for j := 0 to want.Count - 1 do
        begin
          if IsNan(pts[j]) and IsNan(HexNum(want.Items[j])) then Continue;
          if pts[j] <> HexNum(want.Items[j]) then
          begin
            Inc(n);
            if n <= 3 then
              Miss(Format('%s point %d is %s upstream, %s here', [what, j,
                Fmt(HexNum(want.Items[j])), Fmt(pts[j])]));
          end;
        end;
        Inc(FCompared, want.Count);
        if n > 3 then Miss(Format('%s: %d points differ', [what, n]));
      end;
      { the style }
      if er.Objects['style'].Find('fill').JSONType <> jtNull then
      begin
        if (kind <> 'barBg') then
          SameColour(what + ' fill', el.Style.FillColor, er.Objects['style'].Find('fill'));
      end
      else
      begin
        Inc(FCompared);
        if el.Style.HasFill then Miss(what + ': a fill here, none upstream');
      end;
      SameHex(what + ' opacity', el.Style.Alpha, er.Objects['style'].Find('opacity'));
      if er.Objects['style'].Find('stroke').JSONType <> jtNull then
      begin
        SameHex(what + ' line width', el.Style.StrokeWidthLogical,
          er.Objects['style'].Find('lineWidth'));
        { the theme's colours are not upstream's: only a colour the case
          wrote itself is compared -- a candle's by its sign's keys }
        if pinned then
        begin
          if kind <> 'candle' then key := 'borderColor'
          else if g.Sign > 0 then key := 'borderColor'
          else if g.Sign < 0 then key := 'borderColor0'
          else key := 'borderColorDoji';
          if TJSONObject(sopt).Find(key) <> nil then
            SameColour(what + ' stroke', el.Style.StrokeColor, er.Objects['style'].Find('stroke'));
        end;
      end
      else
      begin
        Inc(FCompared);
        if el.Style.StrokeWidthLogical > 0 then Miss(what + ': a pen here, none upstream');
      end;
      if (kind = 'bar') or (kind = 'barBg') then
      begin
        SameHex(what + ' bar width', g.BarW, er.Find('barWidth'));
        SameInt(what + ' base dim', g.BaseDim, er.Integers['baseDim']);
        want := er.Arrays['indices'];
        SameInt(what + ' indices', Length(g.Idx), want.Count);
        if Length(g.Idx) = want.Count then
          for j := 0 to want.Count - 1 do
            if g.Idx[j] <> want.Integers[j] then
            begin
              Miss(Format('%s index %d is %d upstream, %d here', [what, j,
                want.Integers[j], g.Idx[j]]));
              Break;
            end;
      end
      else if kind = 'symbol' then
      begin
        SameHex(what + ' width', g.SymW, er.Arrays['size'].Items[0]);
        SameHex(what + ' height', g.SymH, er.Arrays['size'].Items[1]);
        SameStr(what + ' symbol', SymbolWord(g.SymKind), er.Strings['symbolType']);
        SameStr(what + ' boost', BoolToStr(g.Boost, True), BoolToStr(er.Booleans['boost'], True));
        if er.Find('softClip').JSONType = jtNull then
          SameStr(what + ' soft clip', BoolToStr(g.SoftOn, True), 'False')
        else
        begin
          SameStr(what + ' soft clip', BoolToStr(g.SoftOn, True), 'True');
          SameHex(what + ' soft x', g.Soft.X, er.Arrays['softClip'].Items[0]);
          SameHex(what + ' soft y', g.Soft.Y, er.Arrays['softClip'].Items[1]);
          SameHex(what + ' soft w', g.Soft.W, er.Arrays['softClip'].Items[2]);
          SameHex(what + ' soft h', g.Soft.H, er.Arrays['softClip'].Items[3]);
        end;
      end
      else
        SameInt(what + ' sign', g.Sign, er.Integers['sign']);
      { the view group's clip }
      if sr.Find('clip').JSONType = jtNull then
        SameStr(what + ' clip', BoolToStr(g.ClipOn, True), 'False')
      else
      begin
        SameStr(what + ' clip', BoolToStr(g.ClipOn, True), 'True');
        SameHex(what + ' clip x', g.Clip.X, sr.Arrays['clip'].Items[0]);
        SameHex(what + ' clip y', g.Clip.Y, sr.Arrays['clip'].Items[1]);
        SameHex(what + ' clip w', g.Clip.W, sr.Arrays['clip'].Items[2]);
        SameHex(what + ' clip h', g.Clip.H, sr.Arrays['clip'].Items[3]);
      end;
    end;
  end;
end;

procedure TAdvChartLargeModeOracleTest.CheckStep(AStep: TJSONObject);
var
  hv, tip, er: TJSONObject;
  ev, normal: TJSONArray;
  el, j, s, k: Integer;
  d: TTyChartDatumRef;
  e: TTyChartElement;
  kind, gotKind, which: string;
  parts: TStringList;
  item: TTyStItem;
  got, want: string;
begin
  { the element and the row under the pointer }
  if AStep.Find('hover').JSONType = jtObject then
  begin
    hv := AStep.Objects['hover'];
    kind := hv.Strings['kind'];
    d := FChart.HitTestAt(AStep.Integers['x'], AStep.Integers['y'], el);
    gotKind := 'none';
    if el >= 0 then
    begin
      e := FChart.List.Element(el);
      if e.Shape.Kind = cskLarge then
        case e.Shape.Large.Kind of
          lgkBar: gotKind := 'bar';
          lgkSymbol: gotKind := 'symbol';
          lgkCandle: gotKind := 'candle';
        else
          gotKind := '?';
        end
      else if TyChartDatumValid(d) then gotKind := 'item'
      else gotKind := 'other';
    end;
    SameStr('the hovered element', gotKind, kind);
    if (gotKind = kind) and (kind <> 'other') then
    begin
      SameInt('its series', e.Datum.SeriesIndex, hv.Integers['seriesIndex']);
      if kind = 'candle' then
        SameInt('its sign', e.Shape.Large.Sign, hv.Integers['sign']);
      if hv.Find('dataIndex').JSONType = jtNull then
        SameStr('its row', BoolToStr(TyChartDatumValid(d), True), 'False')
      else
        SameInt('its row', d.DataIndex, hv.Integers['dataIndex']);
    end;
  end
  else if AStep.Find('x').JSONType <> jtNull then
  begin
    d := FChart.HitTestAt(AStep.Integers['x'], AStep.Integers['y'], el);
    Inc(FCompared);
    if el >= 0 then Miss(Format('something under (%d, %d) here, nothing upstream',
      [AStep.Integers['x'], AStep.Integers['y']]));
  end;
  { the chart's mouse events }
  ev := AStep.Arrays['events'];
  SameInt('events', FChart.Events.Count, ev.Count);
  if FChart.Events.Count = ev.Count then
  begin
    parts := TStringList.Create;
    try
      parts.Delimiter := #9;
      parts.StrictDelimiter := True;
      for j := 0 to ev.Count - 1 do
      begin
        er := ev.Objects[j];
        parts.DelimitedText := FChart.Events[j];
        got := Format('%s %s:%s/%s', [parts[0], parts[1], parts[2], parts[3]]);
        want := Format('%s %d:%d/%d', [er.Strings['type'], er.Integers['seriesIndex'],
          er.Integers['dataIndex'], er.Integers['dataIndexInside']]);
        SameStr(Format('event %d', [j]), got, want);
      end;
    finally
      parts.Free;
    end;
  end
  else
    for j := 0 to FChart.Events.Count - 1 do
      Miss('  here: ' + FChart.Events[j]);
  { the tooltip }
  tip := AStep.Objects['tooltip'];
  SameStr('the tooltip shown', BoolToStr(FChart.TooltipShown, True),
    BoolToStr(tip.Booleans['shown'], True));
  if tip.Booleans['shown'] and FChart.TooltipShown then
  begin
    which := tip.Strings['which'];
    if Copy(which, 1, 5) = 'axis:' then
      SameStr('the tooltip', FChart.TooltipShownWhich, which)
    else
    begin
      d := FChart.TooltipShownDatum;
      SameStr('the tooltip', Format('item:%d:%d', [d.SeriesIndex, d.RawDataIndex]), which);
      SameInt('the tooltip row', d.DataIndex, tip.Integers['inner']);
    end;
  end;
  { no large element has a state, nothing of one is held }
  for j := 0 to AStep.Arrays['states'].Count - 1 do
  begin
    er := AStep.Arrays['states'].Objects[j];
    s := er.Integers['seriesIndex'];
    for k := 0 to 2 do
    begin
      Inc(FCompared);
      if FChart.ItemStates(s, k, item) and (TyStNamesText(item.Host.States) <> '') then
        Miss(Format('series %d row %d of a large batch has states %s',
          [s, k, TyStNamesText(item.Host.States)]));
    end;
  end;
  { the normal items the case watches }
  normal := AStep.Arrays['normal'];
  for j := 0 to normal.Count - 1 do
  begin
    er := normal.Objects[j];
    if not FChart.ItemStates(er.Integers['seriesIndex'], er.Integers['dataIndex'], item) then
    begin
      Miss(Format('no states for series %d row %d', [er.Integers['seriesIndex'],
        er.Integers['dataIndex']]));
      Continue;
    end;
    got := TyStNamesText(item.Host.States);
    want := '';
    for k := 0 to er.Arrays['states'].Count - 1 do
    begin
      if want <> '' then want := want + ',';
      want := want + er.Arrays['states'].Strings[k];
    end;
    SameStr(Format('series %d row %d states', [er.Integers['seriesIndex'],
      er.Integers['dataIndex']]), got, want);
  end;
end;

procedure TAdvChartLargeModeOracleTest.TestEveryBatchAndEveryHitAsUpstream;
var
  cases, steps, recs: TJSONArray;
  c, st, opt: TJSONObject;
  ci, si, ri: Integer;
  t: string;
  nowMs: Double;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for ci := 0 to cases.Count - 1 do
  begin
    c := TJSONObject(cases.Items[ci]);
    opt := c.Objects['option'];
    FName := c.Strings['id'] + ' init';
    NewChart;
    FChart.TooltipNow := 0;
    FChart.SetOption(opt.AsJSON, True);
    RenderNow;
    recs := c.Arrays['records'];
    CheckRecord(recs.Objects[0], opt);
    ri := 1;
    steps := c.Arrays['steps'];
    for si := 0 to steps.Count - 1 do
    begin
      st := TJSONObject(steps.Items[si]);
      t := st.Strings['t'];
      FName := c.Strings['id'] + '/' + IntToStr(si) + ' ' + t;
      nowMs := (si + 1) * 1000;
      FChart.TooltipNow := nowMs;
      FChart.Events.Clear;
      if t = 'move' then
        FChart.Move(st.Integers['x'], st.Integers['y'])
      else if t = 'leave' then
        FChart.Leave
      else if t = 'action' then
        FChart.DispatchAction(st.Objects['payload'].AsJSON)
      else if t = 'zoom' then
        FChart.DispatchDataZoom(0, st.Objects['payload'].Floats['start'],
          st.Objects['payload'].Floats['end']);
      FChart.TooltipTick(nowMs + 500);
      FChart.TooltipNow := nowMs + 500;
      RenderNow;
      Inc(FSteps);
      CheckStep(st);
      if (t = 'zoom') and (ri < recs.Count) then
      begin
        CheckRecord(recs.Objects[ri], opt);
        Inc(ri);
      end;
    end;
    FreeAndNil(FChart);
  end;
  if FBad > 0 then
    Fail(Format('%d of %d comparisons over %d cases and %d steps differ:%s',
      [FBad, FCompared, cases.Count, FSteps, FReport]));
  AssertTrue('the oracle was compared', FCompared > 10000);
end;

{ ==================== hand-written ==================== }

procedure TAdvChartLargeModeTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := nil;
end;

procedure TAdvChartLargeModeTest.TearDown;
begin
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartLargeModeTest.Show(const AOption: string; AW, AH: Integer);
begin
  FreeAndNil(FChart);
  FChart := TLmProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, AW, AH);
  FChart.AnimationMode := camOff;
  FChart.SetOption(AOption, True);
  RenderNow(AW, AH);
end;

procedure TAdvChartLargeModeTest.RenderNow(AW, AH: Integer);
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(AW, AH, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, AW, AH), 96);
  finally
    bmp.Free;
  end;
end;

function TAdvChartLargeModeTest.CountLarge(ASeries: Integer): Integer;
var k: Integer; el: TTyChartElement;
begin
  Result := 0;
  for k := 0 to FChart.List.Count - 1 do
  begin
    el := FChart.List.Element(k);
    if (el.Shape.Kind = cskLarge) and (el.Datum.SeriesIndex = ASeries) then Inc(Result);
  end;
end;

function TAdvChartLargeModeTest.CountRows(ASeries: Integer): Integer;
var k: Integer; el: TTyChartElement;
begin
  Result := 0;
  for k := 0 to FChart.List.Count - 1 do
  begin
    el := FChart.List.Element(k);
    if (el.Datum.SeriesIndex = ASeries) and (el.Datum.DataIndex >= 0) then Inc(Result);
  end;
end;

function Bars(N: Integer; const AExtra: string): string;
var i: Integer; cats, vals: string;
begin
  cats := '';
  vals := '';
  for i := 0 to N - 1 do
  begin
    if i > 0 then
    begin
      cats := cats + ',';
      vals := vals + ',';
    end;
    cats := cats + '"c' + IntToStr(i) + '"';
    vals := vals + IntToStr(1 + (i * 37) mod 90);
  end;
  Result := '{"animation":false,"grid":{"left":60,"right":40,"top":40,"bottom":40},'
    + '"xAxis":{"type":"category","data":[' + cats + ']},"yAxis":{"type":"value"},'
    + '"series":[{"type":"bar"' + AExtra + ',"data":[' + vals + ']}]}';
end;

function Scatter(N: Integer; const AExtra: string): string;
var i: Integer; s, chunk: string; seed: Cardinal;
begin
  s := '';
  chunk := '';
  seed := 7;
  for i := 0 to N - 1 do
  begin
    if i > 0 then chunk := chunk + ',';
    seed := seed * 1103515245 + 12345;
    chunk := chunk + '[' + IntToStr((seed shr 8) mod 1000);
    seed := seed * 1103515245 + 12345;
    chunk := chunk + ',' + IntToStr((seed shr 8) mod 1000) + ']';
    { in chunks, so the whole text is not copied once per point }
    if (i mod 500 = 499) or (i = N - 1) then
    begin
      s := s + chunk;
      chunk := '';
    end;
  end;
  Result := '{"animation":false,"grid":{"left":60,"right":40,"top":40,"bottom":40},'
    + '"xAxis":{"type":"value"},"yAxis":{"type":"value"},'
    + '"series":[{"type":"scatter"' + AExtra + ',"data":[' + s + ']}]}';
end;

procedure TAdvChartLargeModeTest.TestTheSwitchReadsJavaScriptValues;
var
  t, n, f, z: TJSONData;
begin
  t := GetJSON('true');
  n := GetJSON('null');
  f := GetJSON('"10"');
  z := GetJSON('0');
  try
    AssertTrue('a candlestick is large by default', TyLargeIsOn('candlestick', nil, nil, 600));
    AssertFalse('one under its 600', TyLargeIsOn('candlestick', nil, nil, 599));
    AssertFalse('a bar is not large by default', TyLargeIsOn('bar', nil, nil, 100000));
    AssertTrue('a bar with large on at 400', TyLargeIsOn('bar', t, nil, 400));
    AssertFalse('and not at 399', TyLargeIsOn('bar', t, nil, 399));
    AssertTrue('a scatter at 2000', TyLargeIsOn('scatter', t, nil, 2000));
    AssertFalse('large null is off', TyLargeIsOn('candlestick', n, nil, 5000));
    AssertFalse('large 0 is off', TyLargeIsOn('candlestick', z, nil, 5000));
    AssertTrue('a threshold string compares as a number', TyLargeIsOn('bar', t, f, 10));
    AssertFalse('under it', TyLargeIsOn('bar', t, f, 9));
    AssertTrue('a null threshold is 0', TyLargeIsOn('bar', t, n, 0));
    AssertFalse('a line has no large mode', TyLargeIsOn('line', t, z, 100));
    AssertFalse('nor an effectScatter', TyLargeIsOn('effectScatter', t, z, 100));
  finally
    t.Free;
    n.Free;
    f.Free;
    z.Free;
  end;
end;

procedure TAdvChartLargeModeTest.TestTheScansFindTheRightRow;
var g: TTyLargeGeom;
begin
  { two bars overlapping: the forward scan answers the first }
  g := Default(TTyLargeGeom);
  g.Kind := lgkBar;
  g.BaseDim := 0;
  g.BarW := 10;
  g.Pts := TTyDoubleArray.Create(100, 200, -50, 105, 200, -80);
  g.Idx := TTyIntegerArray.Create(0, 1);
  TyLargeSetBox(g);
  AssertEquals('the first rect holding the point', 0, TyLargeBarScan(g, 107, 180));
  AssertEquals('only the second reaches here', 1, TyLargeBarScan(g, 107, 140));
  AssertEquals('an edge is inside', 0, TyLargeBarScan(g, 100, 150));
  AssertEquals('past both', -1, TyLargeBarScan(g, 116, 180));
  AssertTrue('contained', TyLargeContains(g, 107, 140));
  { the clip cuts the hover, not the scan }
  g.ClipOn := True;
  g.Clip.X := 0;
  g.Clip.Y := 160;
  g.Clip.W := 400;
  g.Clip.H := 100;
  AssertFalse('clipped away', TyLargeContains(g, 107, 140));
  AssertEquals('the scan still answers', 1, TyLargeIndexAt(g, 107, 140));
  { two symbols overlapping: the top-down scan answers the last }
  g := Default(TTyLargeGeom);
  g.Kind := lgkSymbol;
  g.SymW := 10;
  g.SymH := 10;
  g.HitMin := 4;
  g.Pts := TTyDoubleArray.Create(100, 100, 104, 100);
  TyLargeSetBox(g);
  AssertEquals('the later point', 1, TyLargeIndexAt(g, 102, 100));
  AssertEquals('the earlier where only it reaches', 0, TyLargeIndexAt(g, 96, 100));
  { under 4 px the box is 4 wide but the bounding rect only the size }
  g.SymW := 2;
  g.SymH := 2;
  g.Pts := TTyDoubleArray.Create(100, 100);
  TyLargeSetBox(g);
  AssertEquals('inside both', 0, TyLargeIndexAt(g, 101, 100));
  AssertEquals('inside the 4 px box, past the bounding rect', -1, TyLargeIndexAt(g, 101.5, 100));
  AssertEquals('the scan alone would say yes', 0, TyLargeSymbolScan(g, 101.5, 100));
  { a not-a-number poisons the bounding rect }
  g.SymW := 10;
  g.SymH := 10;
  g.Pts := TTyDoubleArray.Create(100, 100, NaN, 50);
  TyLargeSetBox(g);
  AssertTrue('the box is not a number', IsNan(g.Box.X));
  AssertFalse('nothing is hovered', TyLargeContains(g, 100, 100));
  { a candle's stroke answers within half of max(width, 5) }
  g := Default(TTyLargeGeom);
  g.Kind := lgkCandle;
  g.Sign := 1;
  g.StrokeHit := 5;
  g.Pts := TTyDoubleArray.Create(1, 100.5, 200, 150, -1, 120.5, 210, 160, NaN, 0, 0, 0);
  TyLargeSetBox(g);
  AssertTrue('on the up line', TyLargeContains(g, 102.5, 170));
  AssertFalse('past half the width', TyLargeContains(g, 103.5, 170));
  AssertFalse('the down line is the other path', TyLargeContains(g, 120.5, 170));
  AssertEquals('no row at all', -1, TyLargeIndexAt(g, 100.5, 170));
  AssertEquals('Float32', Double(Single(0.1)), TyLargeF32(0.1));
  AssertTrue('past the largest single', IsInfinite(TyLargeF32(3.5e38)));
end;

procedure TAdvChartLargeModeTest.TestABatchIsOneElementNotOnePerRow;
begin
  Show(Bars(1000, ',"large":true,"showBackground":true'));
  AssertTrue('large', FChart.SeriesLargeKind(0) = lgkBar);
  AssertEquals('a bar batch and its background', 2, CountLarge(0));
  AssertEquals('no element per row', 0, CountRows(0));
  Show(Scatter(5000, ',"large":true'));
  AssertTrue('large', FChart.SeriesLargeKind(0) = lgkSymbol);
  AssertEquals('one symbol batch', 1, CountLarge(0));
  AssertEquals('no element per row', 0, CountRows(0));
  Show(Scatter(5000, ''));
  AssertTrue('not large without `large`', FChart.SeriesLargeKind(0) = lgkNone);
  AssertEquals('an element per row', 5000, CountRows(0));
end;

procedure TAdvChartLargeModeTest.TestTheBatchIsPainted;
var bmp: TBGRABitmap; p: TBGRAPixel; g: TTyLargeGeom; k, x, y: Integer;
begin
  Show('{"animation":false,"color":["#ff0000"],"grid":{"left":60,"right":40,"top":40,"bottom":40},'
    + '"xAxis":{"type":"category","data":["a","b","c"]},"yAxis":{"type":"value","max":10},'
    + '"series":[{"type":"bar","large":true,"largeThreshold":0,"data":[10,10,10]}]}');
  g := Default(TTyLargeGeom);
  for k := 0 to FChart.List.Count - 1 do
    if FChart.List.Element(k).Shape.Kind = cskLarge then g := FChart.List.Element(k).Shape.Large;
  AssertTrue('a batch', g.Kind = lgkBar);
  x := Round(g.Pts[3] + g.BarW / 2);
  y := 200;
  bmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, 600, 400), 96);
    p := bmp.GetPixel(x, y);
    AssertTrue(Format('the second bar is red at (%d, %d): %d %d %d', [x, y, p.red, p.green, p.blue]),
      (p.red > 200) and (p.green < 60) and (p.blue < 60));
    p := bmp.GetPixel(Round(g.Pts[0] + g.BarW + 2), y);
    AssertTrue('the gap beside it is not', p.green > 200);
  finally
    bmp.Free;
  end;
end;

{ [R2-F] A GRADIENT BATCH IS DRAWN IN TILES, every row of a tile traced into
  one path (64 px tiles from the layer's corner). zrender's Circle.buildPath
  moves to (cx + r, cy) before its arc; BGRA's circle is an arc with no
  move, so each circle used to join the one before into one polygon --
  three points in one tile filled the triangle between them. }
procedure TAdvChartLargeModeTest.TestTiledCirclesAreSubPathsOfTheirOwn;
var
  bmp: TBGRABitmap;
  g: TTyLargeGeom;
  k, cx, cy, ink: Integer;
  p: TBGRAPixel;
begin
  Show('{"animation":false,"grid":{"left":40,"right":40,"top":40,"bottom":40},'
    + '"xAxis":{"type":"value","min":0,"max":10},"yAxis":{"type":"value","min":0,"max":10},'
    + '"series":[{"type":"scatter","large":true,"largeThreshold":1,"symbolSize":6,'
    + '"itemStyle":{"color":{"type":"linear","x":0,"y":0,"x2":1,"y2":0,"colorStops":['
    + '{"offset":0,"color":"#ff0000"},{"offset":1,"color":"#0000ff"}]}},'
    + '"data":[[1,0.6],[1.6,0.6],[1.3,1.1]]}]}');
  g := Default(TTyLargeGeom);
  for k := 0 to FChart.List.Count - 1 do
    if FChart.List.Element(k).Shape.Kind = cskLarge then g := FChart.List.Element(k).Shape.Large;
  AssertTrue('a batch of symbols', g.Kind = lgkSymbol);
  { the triangle's centroid, far from every circle }
  cx := Round((g.Pts[0] + g.Pts[2] + g.Pts[4]) / 3);
  cy := Round((g.Pts[1] + g.Pts[3] + g.Pts[5]) / 3);
  bmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, 600, 400), 96);
    AssertTrue(Format('the three in one tile (%d, %d)', [cx, cy]),
      (cx div 64 = Round(g.Pts[0]) div 64) and (cy div 64 = Round(g.Pts[1]) div 64)
      and (cx div 64 = Round(g.Pts[2]) div 64) and (cy div 64 = Round(g.Pts[5]) div 64));
    p := bmp.GetPixel(cx, cy);
    AssertTrue(Format('nothing between the circles at (%d, %d): %d %d %d',
      [cx, cy, p.red, p.green, p.blue]), (p.red > 240) and (p.green > 240) and (p.blue > 240));
    { and every circle is drawn: its centre inked }
    ink := 0;
    for k := 0 to 2 do
    begin
      p := bmp.GetPixel(Round(g.Pts[2 * k]), Round(g.Pts[2 * k + 1]));
      if p.green < 100 then Inc(ink);
    end;
    AssertEquals('three circles drawn', 3, ink);
  finally
    bmp.Free;
  end;
end;

procedure TAdvChartLargeModeTest.TestLeavingLargeModeBringsTheStatesBack;
var item: TTyStItem; el: Integer; d: TTyChartDatumRef; k: Integer; g: TTyLargeGeom;
begin
  Show(Bars(30, ',"large":true,"largeThreshold":20'));
  AssertTrue('large', FChart.SeriesLargeKind(0) = lgkBar);
  AssertFalse('no states in large mode', FChart.ItemStates(0, 3, item));
  g := Default(TTyLargeGeom);
  for k := 0 to FChart.List.Count - 1 do
    if FChart.List.Element(k).Shape.Kind = cskLarge then g := FChart.List.Element(k).Shape.Large;
  d := FChart.HitTestAt(Round(g.Pts[9] + g.BarW / 2), 355, el);
  AssertEquals('the batch names the row', 3, d.DataIndex);
  FChart.SetOption(Bars(10, ',"large":true,"largeThreshold":20'), True);
  RenderNow;
  AssertTrue('normal again', FChart.SeriesLargeKind(0) = lgkNone);
  AssertTrue('an item has its record again', FChart.ItemStates(0, 3, item));
  AssertTrue('and its element', item.Host.Exists);
end;

procedure TAdvChartLargeModeTest.TestAPathSymbolStaysOneElementPerRow;
begin
  Show(Scatter(60, ',"large":true,"largeThreshold":10,"symbol":"path://M0,0L10,0L5,10Z"'));
  AssertTrue('drawn one by one', FChart.SeriesLargeKind(0) = lgkNone);
  AssertEquals('an element per row', 60, CountRows(0));
end;

{ UPSTREAM ANIMATES NO LARGE BATCH: BarView's _renderLarge, LargeSymbolDraw
  and the candle's createLarge make no enter animation, the clip path a
  large view sets has none either. The same bars one by one grow. }
procedure TAdvChartLargeModeTest.TestABatchHasNoEnterAnimation;
var opt: string;
begin
  opt := StringReplace(Bars(30, ',"large":true,"largeThreshold":20'), '"animation":false,', '', []);
  FreeAndNil(FChart);
  FChart := TLmProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, 600, 400);
  FChart.AnimationMode := camAlways;
  FChart.AnimNow := 1700000000000;
  FChart.SetOption(opt, True);
  RenderNow;
  AssertTrue('large', FChart.SeriesLargeKind(0) = lgkBar);
  AssertEquals('nothing animates', 0, FChart.AnimClipCount);
  FChart.AnimTick(1700000000100);
  RenderNow;
  AssertEquals('the batch is drawn', 1, CountLarge(0));
  { and the same bars under the threshold grow }
  opt := StringReplace(Bars(19, ',"large":true,"largeThreshold":20'), '"animation":false,', '', []);
  FreeAndNil(FChart);
  FChart := TLmProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, 600, 400);
  FChart.AnimationMode := camAlways;
  FChart.AnimNow := 1700000000000;
  FChart.SetOption(opt, True);
  RenderNow;
  AssertTrue('normal', FChart.SeriesLargeKind(0) = lgkNone);
  AssertEquals('every bar grows', 19, FChart.AnimClipCount);
end;

{ A SPEED CHECK, NOT A BENCHMARK. Measured and printed; the bounds are
  loose enough for a busy machine (other trees run their suites beside this
  one) and tight enough to catch the batch painted as ONE path through the
  painter, which took over two minutes for these hundred thousand points --
  BGRA's scanline fill sorts every crossing of the path on every row.

  The figures beside it, on the machine this was written on: 10 000 points
  drawn one element each (large off) about 0.8 s a paint, as a batch about
  0.27 s, a bordered batch about 0.5 s; 100 000 as a batch about 2.3 s for
  the first paint (the build included), 100 hit tests about 30 ms. }
procedure TAdvChartLargeModeTest.TestAHundredThousandPoints;
var
  opt: string;
  t0, tSet, tPaint, tSecond, tHover: QWord;
  el, i, nn: Integer;
  d: TTyChartDatumRef;
begin
  { the batch against an element per point, at ten thousand -- all of it at
    once: a large scatter of 1e4 rows is progressive by default, by 5000
    [Batch 119], and `progressive: 0` keeps the one batch measured here }
  for nn := 0 to 2 do
  begin
    case nn of
      0: opt := Scatter(10000, '');
      1: opt := Scatter(10000, ',"large":true,"progressive":0');
    else
      opt := Scatter(10000, ',"large":true,"progressive":0,"itemStyle":{"borderColor":"#000","borderWidth":1}');
    end;
    FreeAndNil(FChart);
    FChart := TLmProbe.Create(FForm);
    FChart.Parent := FForm;
    FChart.Controller := FCtl;
    FChart.SetBounds(0, 0, 800, 600);
    FChart.AnimationMode := camOff;
    t0 := GetTickCount64;
    FChart.SetOption(opt, True);
    RenderNow(800, 600);
    tSet := GetTickCount64 - t0;
    t0 := GetTickCount64;
    RenderNow(800, 600);
    tSecond := GetTickCount64 - t0;
    case nn of
      0: WriteLn(Format('  [large] 10k points, an element each: first paint %d ms, then %d ms', [tSet, tSecond]));
      1: WriteLn(Format('  [large] 10k points, one batch: first paint %d ms, then %d ms', [tSet, tSecond]));
    else
      WriteLn(Format('  [large] 10k points, one bordered batch: first paint %d ms, then %d ms', [tSet, tSecond]));
    end;
  end;
  opt := Scatter(100000, ',"large":true,"progressive":0');
  FreeAndNil(FChart);
  FChart := TLmProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, 800, 600);
  FChart.AnimationMode := camOff;
  t0 := GetTickCount64;
  FChart.SetOption(opt, True);
  tSet := GetTickCount64 - t0;
  t0 := GetTickCount64;
  RenderNow(800, 600);
  tPaint := GetTickCount64 - t0;
  t0 := GetTickCount64;
  RenderNow(800, 600);
  tSecond := GetTickCount64 - t0;
  AssertEquals('one batch', 1, CountLarge(0));
  AssertEquals('no element per row', 0, CountRows(0));
  t0 := GetTickCount64;
  for i := 0 to 99 do
    d := FChart.HitTestAt(100 + i * 6, 300, el);
  tHover := GetTickCount64 - t0;
  WriteLn(Format('  [large] 100k points: setOption %d ms, first paint %d ms, then %d ms, 100 hit tests %d ms',
    [tSet, tPaint, tSecond, tHover]));
  AssertTrue(Format('the first paint took %d ms', [tPaint]), tPaint < 60000);
  AssertTrue(Format('100 hit tests took %d ms', [tHover]), tHover < 10000);
  if d.SeriesIndex < -1 then ;
end;

initialization
  RegisterTest(TAdvChartLargeModeOracleTest);
  RegisterTest(TAdvChartLargeModeTest);
end.
