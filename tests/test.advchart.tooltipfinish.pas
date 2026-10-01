unit test.advchart.tooltipfinish;
{$mode objfpc}{$H+}
{ THE TOOLTIP'S FINISHING TOUCHES, HELD TO UPSTREAM [Batch 100, roadmap B5].

  tools/advchart-oracle/tooltip-finish.js runs the real ECharts 6.1 build in
  node with a live TooltipView (env.node off, getDom stubbed, a virtual
  clock in place of setTimeout) and records:
    component  whether a box shows at all for eight spellings of the root
               `tooltip` -- none, {}, [], [{}], {show: false}, a string, null,
               and a series tooltip with no root one;
    position   where TooltipRichContent.moveTo puts the box for every form of
               `position` (none, an array, a word, an object, a function by
               name), align / verticalAlign and confine -- with the content
               size fixed, so the answer does not depend on measuring text;
               plus the hovered element's rect and a function's arguments;
    timers     after each step of a pointer script on the virtual clock: is
               the box up, for what, placed from which pointer;
    content    the rows of the box over a markPoint / markLine / markArea, a
               heatmap cell, a sunburst sector, a treemap rectangle and a
               sankey node or link (or the template's text), and its border.

  This replays all four through the control: the option set, the pointer
  through MouseMove / MouseLeave, the clock through TooltipNow and
  TooltipTick, a render after every step. The text is measured with
  zrender's SSR width table so the layout under the pointer is upstream's.
  The placement is also checked against TyTooltipPlace on its own, fed the
  fixture's inputs, so a wrong rule and a wrong wiring fail separately. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Types, tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint,
     tyControls.AdvChart.Handlers, tyControls.AdvChart.Color,
     tyControls.AdvChart.Option, tyControls.AdvChart.Tooltip,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TTfProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
    procedure TooltipContentSize(var AW, AH: Double); override;
  public
    Measurer: ITyTextMeasurer;
    FixedW, FixedH: Double;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Move(AX, AY: Integer);
    procedure Leave;
    function ContentOf(const ADatum: TTyChartDatumRef): TTyTooltipBlock;
    function SpecOf(const ADatum: TTyChartDatumRef): TTyTooltipSpec;
    function ParamsOf(const ADatum: TTyChartDatumRef): TTyChartCallbackParams;
    function OptionPointerCount: Integer;
    function OptionPointerValue: Double;
  end;

  TAdvChartTooltipFinishTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TTfProbe;
    FRoot, FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared: Integer;
    FReport, FWhere: string;
    FCalls: TStrings;
    procedure Bad(const AWhat: string);
    procedure Same(const AWhat: string; AGot: Double; const AHex: string);
    procedure NewChart(AOption: TJSONObject);
    procedure Frame;
    function Ssr: ITyTextMeasurer;
    function Section(const AName: string): TJSONArray;
    function CaseById(const ASection, AId: string): TJSONObject;
    procedure Finish(const AWhat: string);
    procedure RecordCall(const AArgs: TTyChartTooltipPosArgs);
    { the oracle's HANDLERS, in Pascal }
    function PosArgs(const AArgs: TTyChartTooltipPosArgs): TTyChartTooltipPos;
    function PosPct(const AArgs: TTyChartTooltipPosArgs): TTyChartTooltipPos;
    function PosTop(const AArgs: TTyChartTooltipPosArgs): TTyChartTooltipPos;
    function PosBox(const AArgs: TTyChartTooltipPosArgs): TTyChartTooltipPos;
    function PosNull(const AArgs: TTyChartTooltipPosArgs): TTyChartTooltipPos;
    function PosFar(const AArgs: TTyChartTooltipPosArgs): TTyChartTooltipPos;
    procedure ComparePlacementCase(ACase: TJSONObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { the fixture, all of it }
    procedure TestOnlyATooltipComponentShowsABox;
    procedure TestEveryPositionAsUpstreamPlacesIt;
    procedure TestThePlacementRuleOnItsOwn;
    procedure TestTheTimersAsUpstreamRunsThem;
    procedure TestTheNewTargetsSayWhatUpstreamSays;
    { what the fixture does not reach }
    procedure TestAnUnregisteredPositionHandlerIsTheDefault;
    procedure TestTheMachineClockArmsATimer;
    procedure TestARebuildTakesTheBoxAway;
    procedure TestAnUnwrittenConfineIsTrueAndAWrittenOneIsObeyed;
    procedure TestAnOptionsShownPointerHoldsUntilThePointerMoves;
  end;

implementation

const
  cW = 600;
  cH = 400;

{ ==================== the probe ==================== }

function TTfProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TTfProbe.TooltipContentSize(var AW, AH: Double);
begin
  if FixedW > 0 then AW := FixedW;
  if FixedH > 0 then AH := FixedH;
end;

procedure TTfProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TTfProbe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TTfProbe.Leave;
begin
  MouseLeave;
end;

function TTfProbe.ContentOf(const ADatum: TTyChartDatumRef): TTyTooltipBlock;
begin
  Result := TooltipContent(ADatum, TooltipSpecFor(ADatum));
end;

function TTfProbe.SpecOf(const ADatum: TTyChartDatumRef): TTyTooltipSpec;
begin
  Result := TooltipSpecFor(ADatum);
end;

function TTfProbe.ParamsOf(const ADatum: TTyChartDatumRef): TTyChartCallbackParams;
begin
  Result := TooltipParams(ADatum);
end;

function TTfProbe.OptionPointerCount: Integer;
begin
  Result := Length(OptionPointerHits);
end;

function TTfProbe.OptionPointerValue: Double;
var h: TTyAxisHitArray;
begin
  h := OptionPointerHits;
  if Length(h) = 0 then Result := NaN else Result := h[0].Value;
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

{ fpjson drops \u0000: the fixture's NULs are read as #1, and the port's
  strings are compared the same way }
function NulAsOne(const S: string): string;
begin
  Result := StringReplace(S, #0, #1, [rfReplaceAll]);
end;

procedure TAdvChartTooltipFinishTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  FCalls := TStringList.Create;
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath('advchart-tooltip-finish.json'));
    FRoot := GetJSON(StringReplace(sl.Text, '\u0000', '\u0001', [rfReplaceAll]));
    sl.LoadFromFile(FixturePath('advchart-text-style.json'));
    FMeasure := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  TyChartRegisterPositionHandler('PosArgs', @PosArgs);
  TyChartRegisterPositionHandler('PosPct', @PosPct);
  TyChartRegisterPositionHandler('PosTop', @PosTop);
  TyChartRegisterPositionHandler('PosBox', @PosBox);
  TyChartRegisterPositionHandler('PosNull', @PosNull);
  TyChartRegisterPositionHandler('PosFar', @PosFar);
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartTooltipFinishTest.TearDown;
begin
  TyChartClearPositionHandlers;
  FChart.Free;
  FChart := nil;
  FCalls.Free;
  FRoot.Free;
  FMeasure.Free;
  FBmp.Free;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

function TAdvChartTooltipFinishTest.Ssr: ITyTextMeasurer;
begin
  Result := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
end;

procedure TAdvChartTooltipFinishTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 12000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TAdvChartTooltipFinishTest.Same(const AWhat: string; AGot: Double;
  const AHex: string);
begin
  Inc(FCompared);
  if HexOf(AGot) <> LowerCase(AHex) then
    Bad(Format('%s %s, upstream %s', [AWhat, Txt(AGot), Txt(FromHex(AHex))]));
end;

procedure TAdvChartTooltipFinishTest.Finish(const AWhat: string);
begin
  AssertTrue(AWhat + ': nothing compared', FCompared > 0);
  AssertEquals(Format('%s: %d of %d comparisons differ:%s',
    [AWhat, FBad, FCompared, FReport]), 0, FBad);
end;

procedure TAdvChartTooltipFinishTest.NewChart(AOption: TJSONObject);
begin
  FChart.Free;
  FChart := TTfProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := Ssr;
  FChart.TooltipNow := 0;
  FChart.Option := AOption.AsJSON;
  FChart.SetBounds(0, 0, cW, cH);
  Frame;
end;

procedure TAdvChartTooltipFinishTest.Frame;
begin
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

function TAdvChartTooltipFinishTest.Section(const AName: string): TJSONArray;
begin
  Result := TJSONObject(FRoot).Arrays[AName];
end;

function TAdvChartTooltipFinishTest.CaseById(const ASection,
  AId: string): TJSONObject;
var
  arr: TJSONArray;
  i: Integer;
begin
  Result := nil;
  arr := Section(ASection);
  for i := 0 to arr.Count - 1 do
    if arr.Objects[i].Strings['id'] = AId then Exit(arr.Objects[i]);
end;

{ ==================== the handlers ==================== }

function Hx4(const A: array of Double): string;
var i: Integer;
begin
  Result := '';
  for i := 0 to High(A) do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + HexOf(A[i]);
  end;
end;

procedure TAdvChartTooltipFinishTest.RecordCall(const AArgs: TTyChartTooltipPosArgs);
var
  s: string;
  i: Integer;
begin
  s := 'point=' + Hx4([AArgs.PointX, AArgs.PointY]);
  if AArgs.HasRect then
    s := s + ' rect=' + Hx4([AArgs.RectX, AArgs.RectY, AArgs.RectW, AArgs.RectH])
  else
    s := s + ' rect=null';
  s := s + ' view=' + Hx4([AArgs.ViewW, AArgs.ViewH]);
  s := s + ' content=' + Hx4([AArgs.ContentW, AArgs.ContentH]);
  if AArgs.IsAxis then
  begin
    s := s + ' params=[';
    for i := 0 to High(AArgs.Params) do
      s := s + Format('(%d,%d)', [AArgs.Params[i].SeriesIndex, AArgs.Params[i].DataIndex]);
    s := s + ']';
  end
  else if Length(AArgs.Params) = 1 then
    s := s + Format(' params=(%d,%d)', [AArgs.Params[0].SeriesIndex,
      AArgs.Params[0].DataIndex])
  else
    s := s + ' params=?';
  FCalls.Add(s);
end;

function TAdvChartTooltipFinishTest.PosArgs(
  const AArgs: TTyChartTooltipPosArgs): TTyChartTooltipPos;
begin
  RecordCall(AArgs);
  Result := Default(TTyChartTooltipPos);
  Result.Kind := ctpPoint;
  Result.X := TyChartPosNum(AArgs.PointX - AArgs.ContentW / 2);
  if AArgs.HasRect then Result.Y := TyChartPosNum(AArgs.RectY - AArgs.ContentH)
  else Result.Y := TyChartPosNum(AArgs.PointY - 10);
end;

function TAdvChartTooltipFinishTest.PosPct(
  const AArgs: TTyChartTooltipPosArgs): TTyChartTooltipPos;
begin
  RecordCall(AArgs);
  Result := Default(TTyChartTooltipPos);
  Result.Kind := ctpPoint;
  Result.X := TyChartPosText('10%');
  Result.Y := TyChartPosText('50%');
end;

function TAdvChartTooltipFinishTest.PosTop(
  const AArgs: TTyChartTooltipPosArgs): TTyChartTooltipPos;
begin
  RecordCall(AArgs);
  Result := Default(TTyChartTooltipPos);
  Result.Kind := ctpSide;
  Result.Side := 'top';
end;

function TAdvChartTooltipFinishTest.PosBox(
  const AArgs: TTyChartTooltipPosArgs): TTyChartTooltipPos;
begin
  RecordCall(AArgs);
  Result := Default(TTyChartTooltipPos);
  Result.Kind := ctpBox;
  Result.Right := TyChartPosNum(10);
  Result.Bottom := TyChartPosText('10%');
end;

function TAdvChartTooltipFinishTest.PosNull(
  const AArgs: TTyChartTooltipPosArgs): TTyChartTooltipPos;
begin
  RecordCall(AArgs);
  Result := Default(TTyChartTooltipPos);
  Result.Kind := ctpDefault;
end;

function TAdvChartTooltipFinishTest.PosFar(
  const AArgs: TTyChartTooltipPosArgs): TTyChartTooltipPos;
begin
  RecordCall(AArgs);
  Result := Default(TTyChartTooltipPos);
  Result.Kind := ctpPoint;
  Result.X := TyChartPosNum(AArgs.ViewW - 5);
  Result.Y := TyChartPosNum(-30);
end;

{ the oracle's call record in the form RecordCall writes }
function CallText(ACall: TJSONObject): string;
var
  r, pa: TJSONData;
  i: Integer;
begin
  Result := 'point=' + LowerCase(ACall.Arrays['point'].Strings[0]) + ','
    + LowerCase(ACall.Arrays['point'].Strings[1]);
  r := ACall.Find('rect');
  if (r = nil) or (r.JSONType = jtNull) then Result := Result + ' rect=null'
  else
    Result := Result + ' rect=' + LowerCase(TJSONArray(r).Strings[0]) + ','
      + LowerCase(TJSONArray(r).Strings[1]) + ',' + LowerCase(TJSONArray(r).Strings[2])
      + ',' + LowerCase(TJSONArray(r).Strings[3]);
  Result := Result + ' view=' + LowerCase(ACall.Arrays['viewSize'].Strings[0]) + ','
    + LowerCase(ACall.Arrays['viewSize'].Strings[1]);
  Result := Result + ' content=' + LowerCase(ACall.Arrays['contentSize'].Strings[0]) + ','
    + LowerCase(ACall.Arrays['contentSize'].Strings[1]);
  pa := ACall.Find('params');
  if pa is TJSONArray then
  begin
    Result := Result + ' params=[';
    for i := 0 to pa.Count - 1 do
      Result := Result + Format('(%d,%d)', [TJSONArray(pa).Objects[i].Integers['seriesIndex'],
        TJSONArray(pa).Objects[i].Integers['dataIndex']]);
    Result := Result + ']';
  end
  else
    Result := Result + Format(' params=(%d,%d)', [TJSONObject(pa).Integers['seriesIndex'],
      TJSONObject(pa).Integers['dataIndex']]);
end;

{ THE ONE DOCUMENTED DIFFERENCE: upstream resolves an unwritten confine on
  the RAW renderMode ('auto' unless written: false); the port, a richText
  renderer that cannot draw outside the control, confines it. So where the
  case wrote neither a confine nor renderMode 'richText', the port's answer
  is upstream's confined -- confine being _updatePosition's last step, that
  is upstream's result clamped. }
procedure ExpectedXY(ACase: TJSONObject; out AX, AY: string);
var
  tt, rm: TJSONData;
  x, y, w, h: Double;
begin
  AX := ACase.Arrays['result'].Strings[0];
  AY := ACase.Arrays['result'].Strings[1];
  tt := ACase.Objects['option'].Find('tooltip');
  if not (tt is TJSONObject) then Exit;
  if TJSONObject(tt).Find('confine') <> nil then Exit;
  rm := TJSONObject(tt).Find('renderMode');
  if (rm <> nil) and (rm.JSONType = jtString) and (rm.AsString = 'richText') then Exit;
  x := FromHex(AX);
  y := FromHex(AY);
  w := ACase.Arrays['size'].Floats[0];
  h := ACase.Arrays['size'].Floats[1];
  x := Max(Min(x + w, cW) - w, 0);
  y := Max(Min(y + h, cH) - h, 0);
  AX := HexOf(x);
  AY := HexOf(y);
end;

{ ==================== the component ==================== }

procedure TAdvChartTooltipFinishTest.TestOnlyATooltipComponentShowsABox;
var
  arr: TJSONArray;
  c: TJSONObject;
  i: Integer;
begin
  { no tooltip key, `tooltip: []`, a root string, null, a series tooltip
    alone: no TooltipView upstream, no box -- [{}] and {} each have one }
  arr := Section('component');
  for i := 0 to arr.Count - 1 do
  begin
    c := arr.Objects[i];
    FWhere := c.Strings['id'];
    NewChart(c.Objects['option']);
    FChart.Move(c.Arrays['at'].Integers[0], c.Arrays['at'].Integers[1]);
    Frame;
    Inc(FCompared);
    if FChart.TooltipShown <> c.Booleans['shown'] then
      Bad('shown ' + BoolToStr(FChart.TooltipShown, True));
    Inc(FCompared);
    if TyRectFIsValid(FChart.TooltipBox) <> c.Booleans['shown'] then
      Bad('a box painted ' + BoolToStr(TyRectFIsValid(FChart.TooltipBox), True));
  end;
  Finish('component');
end;

{ ==================== the position ==================== }

procedure TAdvChartTooltipFinishTest.ComparePlacementCase(ACase: TJSONObject);
var
  at, size, res, r, calls: TJSONArray;
  hit: TJSONData;
  box, rect: TTyRectF;
  i: Integer;
  want, ex, ey: string;
begin
  FWhere := ACase.Strings['id'];
  at := ACase.Arrays['at'];
  size := ACase.Arrays['size'];
  res := ACase.Arrays['result'];
  FCalls.Clear;
  NewChart(ACase.Objects['option']);
  FChart.FixedW := size.Floats[0];
  FChart.FixedH := size.Floats[1];
  FChart.Move(at.Integers[0], at.Integers[1]);
  Frame;
  { what the pointer is over }
  hit := ACase.Find('hit');
  if (hit <> nil) and (hit.JSONType = jtObject) then
  begin
    want := Format('item:%d:%d', [TJSONObject(hit).Integers['seriesIndex'],
      TJSONObject(hit).Integers['dataIndex']]);
    Inc(FCompared);
    if FChart.TooltipShownWhich <> want then
      Bad('shows ' + FChart.TooltipShownWhich + ', upstream ' + want);
  end
  else
  begin
    Inc(FCompared);
    if Copy(FChart.TooltipShownWhich, 1, 5) <> 'axis:' then
      Bad('shows ' + FChart.TooltipShownWhich + ', upstream an axis tooltip');
  end;
  box := FChart.TooltipBox;
  if not TyRectFIsValid(box) then
  begin
    Bad('no box');
    Exit;
  end;
  ExpectedXY(ACase, ex, ey);
  Same('x', box.Left, ex);
  Same('y', box.Top, ey);
  { the element rect it was placed around }
  rect := FChart.TooltipTargetRect;
  if ACase.Find('rect').JSONType = jtArray then
  begin
    r := ACase.Arrays['rect'];
    if not TyRectFIsValid(rect) then Bad('no element rect')
    else
    begin
      Same('rect x', rect.Left, r.Strings[0]);
      Same('rect y', rect.Top, r.Strings[1]);
      Same('rect w', rect.Right - rect.Left, r.Strings[2]);
      Same('rect h', rect.Bottom - rect.Top, r.Strings[3]);
    end;
  end;
  { a function's arguments: one call per paint here (upstream: per show) --
    the first is compared }
  calls := ACase.Arrays['calls'];
  if calls.Count > 0 then
  begin
    Inc(FCompared);
    if FCalls.Count = 0 then Bad('the handler was never called')
    else if FCalls[0] <> CallText(calls.Objects[0]) then
      Bad('called with ' + FCalls[0] + LineEnding + '    upstream ' + CallText(calls.Objects[0]));
  end;
end;

procedure TAdvChartTooltipFinishTest.TestEveryPositionAsUpstreamPlacesIt;
var
  arr: TJSONArray;
  i: Integer;
begin
  arr := Section('position');
  for i := 0 to arr.Count - 1 do
    ComparePlacementCase(arr.Objects[i]);
  Finish('position');
end;

procedure TAdvChartTooltipFinishTest.TestThePlacementRuleOnItsOwn;
var
  arr, r: TJSONArray;
  c, hit: TJSONObject;
  opt: TTyChartOption;
  spec: TTyTooltipSpec;
  pin: TTyTooltipPlaceIn;
  p: TTyPointF;
  i: Integer;
  border: TJSONData;
  ex, ey: string;
begin
  { TyTooltipPlace fed the fixture's own inputs: the pointer, the size, the
    element rect, the border width _updatePosition read -- no control }
  arr := Section('position');
  opt := TTyChartOption.Create;
  try
    for i := 0 to arr.Count - 1 do
    begin
      c := arr.Objects[i];
      FWhere := c.Strings['id'] + ' (pure)';
      AssertTrue(FWhere, opt.SetOptionText(c.Objects['option'].AsJSON));
      pin := Default(TTyTooltipPlaceIn);
      pin.PointX := c.Arrays['at'].Floats[0];
      pin.PointY := c.Arrays['at'].Floats[1];
      pin.ContentW := c.Arrays['size'].Floats[0];
      pin.ContentH := c.Arrays['size'].Floats[1];
      pin.ViewW := cW;
      pin.ViewH := cH;
      pin.Gap := 20;
      border := c.Find('border');
      if (border <> nil) and (border.JSONType = jtNumber) then
        pin.BorderWidth := border.AsFloat
      else
        pin.BorderWidth := 1;
      if c.Find('rect').JSONType = jtArray then
      begin
        r := c.Arrays['rect'];
        pin.HasRect := True;
        pin.Rect := TyXYWH(FromHex(r.Strings[0]), FromHex(r.Strings[1]),
          FromHex(r.Strings[2]), FromHex(r.Strings[3]));
      end;
      if c.Find('hit').JSONType = jtObject then
      begin
        hit := c.Objects['hit'];
        spec := TyTooltipSpecOf(opt, hit.Integers['seriesIndex'], hit.Integers['dataIndex']);
        SetLength(pin.Params, 1);
        pin.Params[0] := TyChartBlankParams;
        pin.Params[0].SeriesIndex := hit.Integers['seriesIndex'];
        pin.Params[0].DataIndex := hit.Integers['dataIndex'];
      end
      else
      begin
        spec := TyTooltipSpecOf(opt, -1, -1);
        pin.IsAxis := True;
      end;
      p := TyTooltipPlace(spec, pin);
      ExpectedXY(c, ex, ey);
      Same('x', p.X, ex);
      Same('y', p.Y, ey);
    end;
  finally
    opt.Free;
  end;
  Finish('the placement rule');
end;

{ ==================== the timers ==================== }

procedure TAdvChartTooltipFinishTest.TestTheTimersAsUpstreamRunsThem;
var
  arr, steps: TJSONArray;
  c, st: TJSONObject;
  i, k: Integer;
  t: Double;
  ty, which, want: string;
  vis: Boolean;
  anc: TJSONData;
  p: TPoint;
begin
  arr := Section('timers');
  for i := 0 to arr.Count - 1 do
  begin
    c := arr.Objects[i];
    NewChart(c.Objects['option']);
    steps := c.Arrays['steps'];
    for k := 0 to steps.Count - 1 do
    begin
      st := steps.Objects[k];
      t := st.Floats['t'];
      ty := st.Strings['type'];
      FWhere := Format('%s step %d (%s at %s ms)', [c.Strings['id'], k, ty, Txt(t)]);
      FChart.TooltipNow := t;
      if ty = 'move' then
        FChart.Move(st.Arrays['at'].Integers[0], st.Arrays['at'].Integers[1])
      else if ty = 'leave' then
        FChart.Leave
      else
        FChart.TooltipTick(t);
      Frame;
      vis := st.Booleans['visible'];
      Inc(FCompared);
      if FChart.TooltipShown <> vis then
        Bad('shown ' + BoolToStr(FChart.TooltipShown, True) + ', upstream '
          + BoolToStr(vis, True));
      { WHAT IS PAINTED is the shown box, not the hover: after a move onto
        nothing the box waiting out hideDelay is still drawn }
      Inc(FCompared);
      if TyRectFIsValid(FChart.TooltipBox) <> vis then
        Bad('a box painted ' + BoolToStr(TyRectFIsValid(FChart.TooltipBox), True));
      if not vis then Continue;
      want := st.Strings['which'];
      which := FChart.TooltipShownWhich;
      Inc(FCompared);
      if which <> want then Bad('shows ' + which + ', upstream ' + want);
      anc := st.Find('anchor');
      if anc is TJSONArray then
      begin
        p := FChart.TooltipAnchor;
        Inc(FCompared);
        if (p.X <> TJSONArray(anc).Integers[0]) or (p.Y <> TJSONArray(anc).Integers[1]) then
          Bad(Format('placed from (%d, %d), upstream (%d, %d)', [p.X, p.Y,
            TJSONArray(anc).Integers[0], TJSONArray(anc).Integers[1]]));
      end;
    end;
  end;
  Finish('timers');
end;

{ ==================== the content ==================== }

type
  TTfRow = record
    Marker, Name, Value: string;   // '' and a flag for null
    HasMarker, HasName, HasValue: Boolean;
  end;
  TTfRows = array of TTfRow;

function RowsOf(ABlock: TTyTooltipBlock): TTfRows;
var
  ink: TTyTooltipInk;
  lines: TTyTooltipLineArray;
  i, j, k, n: Integer;
  row: TTfRow;
begin
  Result := nil;
  ink := Default(TTyTooltipInk);
  ink.NameWeight := 400;
  ink.ValueWeight := 900;
  ink.MarkerSizeLogical := 10;
  lines := TyTooltipFlatten(ABlock, ink);
  n := 0;
  for i := 0 to High(lines) do
  begin
    for k := 1 to lines[i].BlankLinesBefore do
    begin
      SetLength(Result, n + 1);
      Result[n] := Default(TTfRow);
      Inc(n);
    end;
    row := Default(TTfRow);
    for j := 0 to High(lines[i].Runs) do
      if lines[i].Runs[j].Kind = ttrMarker then
      begin
        row.HasMarker := True;
        if lines[i].Runs[j].MarkerSizeLogical = 10 then row.Marker := 'item'
        else row.Marker := 'subItem';
      end
      else if lines[i].Runs[j].FontWeight = 900 then
      begin
        row.HasValue := True;
        row.Value := lines[i].Runs[j].Text;
      end
      else
      begin
        row.HasName := True;
        row.Name := lines[i].Runs[j].Text;
      end;
    SetLength(Result, n + 1);
    Result[n] := row;
    Inc(n);
  end;
end;

function RowText(const R: TTfRow): string;
  function Q(AHas: Boolean; const S: string): string;
  begin
    if AHas then Result := '"' + NulAsOne(S) + '"' else Result := 'null';
  end;
begin
  Result := '{' + Q(R.HasMarker, R.Marker) + ' ' + Q(R.HasName, R.Name) + ' '
    + Q(R.HasValue, R.Value) + '}';
end;

function WantRowText(ARow: TJSONObject): string;
  function Q(const AKey: string): string;
  var d: TJSONData;
  begin
    d := ARow.Find(AKey);
    if (d = nil) or (d.JSONType = jtNull) then Result := 'null'
    else Result := '"' + d.AsString + '"';
  end;
begin
  Result := '{' + Q('marker') + ' ' + Q('name') + ' ' + Q('value') + '}';
end;

procedure TAdvChartTooltipFinishTest.TestTheNewTargetsSayWhatUpstreamSays;
var
  arr, want: TJSONArray;
  c, hit: TJSONObject;
  i, k: Integer;
  d: TTyChartDatumRef;
  block: TTyTooltipBlock;
  rows: TTfRows;
  got, exp, kind, whichWant, text: string;
  spec: TTyTooltipSpec;
  prm: TTyChartCallbackParams;
  border: TTyChartColor;
  none: Boolean;
begin
  arr := Section('content');
  for i := 0 to arr.Count - 1 do
  begin
    c := arr.Objects[i];
    FWhere := c.Strings['id'];
    NewChart(c.Objects['option']);
    FChart.Move(c.Arrays['at'].Integers[0], c.Arrays['at'].Integers[1]);
    Frame;
    none := (c.Find('none') <> nil) and c.Booleans['none'];
    Inc(FCompared);
    if FChart.TooltipShown = none then
    begin
      d := FChart.HitTestAt(c.Arrays['at'].Integers[0], c.Arrays['at'].Integers[1]);
      Bad(Format('shown %s (the pointer is over series %d row %d kind %d edge %s)',
        [BoolToStr(FChart.TooltipShown, True), d.SeriesIndex, d.DataIndex,
         Ord(d.Kind), BoolToStr(d.IsEdge, True)]));
      Continue;
    end;
    if none then Continue;
    { the target }
    hit := c.Objects['hit'];
    kind := hit.Strings['componentType'];
    if kind = 'series' then
    begin
      if (hit.Find('dataType').JSONType = jtString) and (hit.Strings['dataType'] = 'edge') then
        whichWant := Format('edge:%d:%d', [hit.Integers['seriesIndex'], hit.Integers['dataIndex']])
      else
        whichWant := Format('item:%d:%d', [hit.Integers['seriesIndex'], hit.Integers['dataIndex']]);
    end
    else
      whichWant := Format('%s:%d:%d', [kind, hit.Integers['seriesIndex'], hit.Integers['dataIndex']]);
    Inc(FCompared);
    if FChart.TooltipShownWhich <> whichWant then
    begin
      Bad('shows ' + FChart.TooltipShownWhich + ', upstream ' + whichWant);
      Continue;
    end;
    d := FChart.TooltipShownDatum;
    spec := FChart.SpecOf(d);
    if c.Booleans['template'] then
    begin
      { a template formatter: the text }
      Inc(FCompared);
      AssertTrue(FWhere + ': a formatter', spec.HasFormatter);
      prm := FChart.ParamsOf(d);
      text := TyChartFormatTemplate(spec.Formatter, TyChartOneParams(prm));
      if NulAsOne(text) <> c.Strings['text'] then
        Bad('says "' + text + '", upstream "' + c.Strings['text'] + '"');
    end
    else
    begin
      Inc(FCompared);
      if spec.HasFormatter then Bad('a formatter where upstream has none: ' + spec.Formatter);
      block := FChart.ContentOf(d);
      try
        if block = nil then
        begin
          Bad('no content');
          Continue;
        end;
        rows := RowsOf(block);
      finally
        block.Free;
      end;
      want := c.Arrays['lines'];
      got := '';
      exp := '';
      for k := 0 to High(rows) do got := got + RowText(rows[k]);
      for k := 0 to want.Count - 1 do exp := exp + WantRowText(want.Objects[k]);
      Inc(FCompared);
      if got <> exp then Bad('rows ' + got + LineEnding + '    upstream ' + exp);
    end;
    { the border: where the option wrote the colour, exactly (a palette
      colour is the skin's here) }
    text := c.Strings['border'];
    if (Length(text) = 7) and (text[1] = '#')
      and (Pos(LowerCase(text), LowerCase(c.Objects['option'].AsJSON)) > 0) then
    begin
      prm := FChart.ParamsOf(d);
      border := 0;
      TyTryParseChartColor(text, border);
      Inc(FCompared);
      if prm.Color <> border then
        Bad(Format('border %s, upstream %s', [IntToHex(prm.Color, 8), text]));
    end;
  end;
  Finish('content');
end;

{ ==================== beyond the fixture ==================== }

procedure TAdvChartTooltipFinishTest.TestAnUnregisteredPositionHandlerIsTheDefault;
var
  spec: TTyTooltipSpec;
  pin: TTyTooltipPlaceIn;
  p: TTyPointF;
begin
  { a name nobody registered answers no position: the default placement,
    20 down and right -- a function that silently does nothing would put
    the box at nought }
  spec := TyTooltipSpecDefault;
  spec.PositionHandler := '@NobodyRegisteredThis';
  pin := Default(TTyTooltipPlaceIn);
  pin.PointX := 100;
  pin.PointY := 80;
  pin.ContentW := 50;
  pin.ContentH := 30;
  pin.ViewW := 600;
  pin.ViewH := 400;
  pin.Gap := 20;
  p := TyTooltipPlace(spec, pin);
  AssertEquals('x', 120.0, p.X);
  AssertEquals('y', 100.0, p.Y);
end;

procedure TAdvChartTooltipFinishTest.TestTheMachineClockArmsATimer;
var o: TJSONObject;
begin
  { NaN is the machine's clock, and only then is there a timer: a delay
    waiting on a machine clock nobody steps would never show the box }
  o := TJSONObject(GetJSON('{"animation":false,"tooltip":{"showDelay":40},'
    + '"xAxis":{"type":"category","data":["A","B","C","D"]},'
    + '"yAxis":{"type":"value","min":0,"max":100},'
    + '"series":[{"type":"bar","name":"Sales","data":[20,40,60,80]}]}'));
  try
    NewChart(o);
  finally
    o.Free;
  end;
  FChart.TooltipNow := NaN;
  FChart.Move(259, 269);
  AssertFalse('not shown before the delay', FChart.TooltipShown);
  { the clock is the machine's: TooltipTick with a time far past the delay
    fires it }
  FChart.TooltipTick(FChart.TooltipNow);
  FChart.TooltipTick(1e15);
  AssertTrue('shown once the delay has passed', FChart.TooltipShown);
end;

procedure TAdvChartTooltipFinishTest.TestARebuildTakesTheBoxAway;
var o: TJSONObject;
begin
  { a hovered datum is a pair of subscripts into a build: a rebuild drops
    the box with it, alwaysShowContent or not (upstream keeps it and shows
    again at the last pointer) }
  o := TJSONObject(GetJSON('{"animation":false,"tooltip":{"alwaysShowContent":true},'
    + '"xAxis":{"type":"category","data":["A","B","C","D"]},'
    + '"yAxis":{"type":"value","min":0,"max":100},'
    + '"series":[{"type":"bar","name":"Sales","data":[20,40,60,80]}]}'));
  try
    NewChart(o);
  finally
    o.Free;
  end;
  FChart.Move(259, 269);
  AssertTrue('shown', FChart.TooltipShown);
  FChart.Leave;
  AssertTrue('alwaysShowContent keeps it past the leave', FChart.TooltipShown);
  FChart.Invalidate;
  AssertFalse('a rebuild drops it', FChart.TooltipShown);
end;

procedure TAdvChartTooltipFinishTest.TestAnUnwrittenConfineIsTrueAndAWrittenOneIsObeyed;
var
  opt: TTyChartOption;
  spec: TTyTooltipSpec;
begin
  { upstream resolves an unwritten confine on the RAW renderMode -- 'auto'
    by default, so false; the port is a richText renderer that cannot draw
    outside the control, so unwritten is true. Written, it is `!!confine`. }
  opt := TTyChartOption.Create;
  try
    AssertTrue(opt.SetOptionText('{"tooltip":{}}'));
    spec := TyTooltipSpecOf(opt, -1, -1);
    AssertTrue('unwritten: true', spec.Confine);
    AssertFalse('and not written', spec.ConfineSet);
    AssertTrue(opt.SetOptionText('{"tooltip":{"confine":0}}'));
    spec := TyTooltipSpecOf(opt, -1, -1);
    AssertFalse('0 is false', spec.Confine);
    AssertTrue(opt.SetOptionText('{"tooltip":{"confine":"yes"}}'));
    spec := TyTooltipSpecOf(opt, -1, -1);
    AssertTrue('a string is true', spec.Confine);
    AssertTrue(opt.SetOptionText('{"tooltip":{"confine":false},'
      + '"series":[{"type":"bar","tooltip":{"confine":null}}]}'));
    spec := TyTooltipSpecOf(opt, 0, -1);
    AssertFalse('a null falls through to the global false', spec.Confine);
  finally
    opt.Free;
  end;
end;

procedure TAdvChartTooltipFinishTest.TestAnOptionsShownPointerHoldsUntilThePointerMoves;
var o: TJSONObject;
begin
  { A1 deferred this: an axis' `axisPointer: {status: 'show', value}` is
    drawn before anything moves (BaseAxisPointer.render reads both off the
    model) -- and the first pointer event rewrites every status
    (axisTrigger's updateModelActually), so it is gone after a move. The
    label's text is held to upstream by test.advchart.handlerwiring. }
  o := TJSONObject(GetJSON('{"animation":false,'
    + '"xAxis":{"type":"category","data":["c0","c1","c2","c3"],'
    + '"axisPointer":{"show":true,"status":"show","value":"c2"}},'
    + '"yAxis":{"type":"value"},"series":[{"type":"bar","data":[2,4,6,8]}]}'));
  try
    NewChart(o);
  finally
    o.Free;
  end;
  AssertEquals('one pointer, from the option', 1, FChart.OptionPointerCount);
  AssertEquals('at c2', 2.0, FChart.OptionPointerValue);
  FChart.Move(5, 5);
  AssertEquals('gone after the first move', 0, FChart.OptionPointerCount);
  { and an option set brings it back }
  FChart.SetOption('{"yAxis":{"min":0}}', False);
  Frame;
  AssertEquals('back after setOption', 1, FChart.OptionPointerCount);
  { status 'hide', or no value, or an axis with no pointer: none }
  o := TJSONObject(GetJSON('{"animation":false,'
    + '"xAxis":{"type":"category","data":["c0","c1"],'
    + '"axisPointer":{"status":"show","value":"c1"}},'
    + '"yAxis":{"type":"value"},"series":[{"type":"bar","data":[2,4]}]}'));
  try
    NewChart(o);
  finally
    o.Free;
  end;
  AssertEquals('no pointer of its own and no axis tooltip: none', 0,
    FChart.OptionPointerCount);
end;

initialization
  RegisterTest(TAdvChartTooltipFinishTest);
end.
