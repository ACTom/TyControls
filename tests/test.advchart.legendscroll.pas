unit test.advchart.legendscroll;
{$mode objfpc}{$H+}
{ THE LEGEND'S SELECTOR BUTTONS AND THE SCROLLING LEGEND, HELD TO UPSTREAM
  [Batch 98].

  tools/advchart-oracle/legend-scroll.js runs the real ECharts 6.1 build in
  node and records, for 45 cases, the legend as it is drawn after every
  step -- the view group's position and the main rect layoutInner returned,
  the background, every item's global transform and bounding rect, every
  selector button's (and its ink and state), the pager's three parts (their
  places, rects, inks and the page text), the content's clip, the page info
  and scrollDataIndex -- and the events each step published: legendScroll
  actions, page-button and selector clicks, a hovered button, an item
  toggled on a later page, the wheel.

  This replays every case through the control: the option set, the
  pointer through MouseMove / MouseDown / MouseUp and the wheel, the
  actions through DispatchAction, and a render after every step. The text
  is measured with zrender's own SSR width table (read from the text-style
  fixture), so every position is compared BIT FOR BIT. What the pointer
  hits before a step is compared too: the port's display list must answer
  the element zrender found.

  Colours: upstream's defaults are the skin's here (tertiary ink on a
  button and the page text, quaternary hovered, accent50 and accent10 on
  the page arrows); a colour the option wrote is compared exactly. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Types, tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint,
     tyControls.AdvChart.Handlers, tyControls.AdvChart.Events,
     tyControls.AdvChart.Color, tyControls.AdvChart.Option,
     tyControls.AdvChart.ZrPath, tyControls.AdvChart.Legend,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TLsProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Move(AX, AY: Integer);
    procedure ClickAt(AX, AY: Integer);
    procedure Wheel(AX, AY: Integer);
    function List: TTyPaintList;
  end;

  TLsLogger = class
  public
    Log: TStrings;
    procedure Handle(Sender: TObject; const AEvent: TTyChartEvent);
  end;

  TAdvChartLegendScrollTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TLsProbe;
    FRoot, FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FLogger: TLsLogger;
    FBad, FCompared: Integer;
    FReport, FWhere: string;
    procedure Bad(const AWhat: string);
    procedure NewChart(AOption: TJSONObject);
    procedure Frame;
    function Ssr: ITyTextMeasurer;
    procedure Same(const AWhat: string; AGot: Double; const AHex: string);
    procedure CompareState(AState: TJSONObject);
    procedure CompareEvents(AWant: TJSONArray);
    function HitName(AX, AY: Integer): string;
    function CaseById(const AId: string): TJSONObject;
    function PageFmt(const AParams: TTyChartParams): string;
    function ThemeInk(const AKey: string; AHover: Boolean = False): TTyChartColor;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEveryLegendAsUpstreamDrawsIt;
    { what the fixture has no case for }
    procedure TestAPageIconThatParsesToNothingIsAnEmptyBox;
    procedure TestAnImageIconIsItsBox;
    procedure TestTheSelectorTitlesAreTheLocales;
    procedure TestALegendScrollNamingAPlainLegendDoesNothing;
    procedure TestTheSkinsInksAreTheDefaults;
    procedure TestAnItemOutsideTheClipTakesNoPointer;
    procedure TestTheScrollTweensWithTheLegendsUpdateTiming;
    procedure TestAFirstRenderScrollsFromTheUnscrolledContent;
    procedure TestAButtonActsOnItsOwnLegend;
  end;

implementation

{ ==================== the probe ==================== }

function TLsProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TLsProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TLsProbe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TLsProbe.ClickAt(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
  MouseDown(mbLeft, [ssLeft], AX, AY);
  MouseUp(mbLeft, [], AX, AY);
end;

procedure TLsProbe.Wheel(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
  DoMouseWheel([], -120, Point(AX, AY));
end;

function TLsProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

procedure TLsLogger.Handle(Sender: TObject; const AEvent: TTyChartEvent);
begin
  Log.Add(AEvent.EventType + #9 + AEvent.Payload);
end;

{ ==================== plumbing ==================== }

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

function Hx(AArr: TJSONArray; AIndex: Integer): Double;
begin
  Result := FromHex(AArr.Strings[AIndex]);
end;

function ColourOf(const AText: string): TTyChartColor;
begin
  if not TyTryParseChartColor(AText, Result) then Result := 0;
end;

{ upstream's auto id is '<auto id>' in the fixture: any non-empty string here
  (fpjson drops the NULs on parsing); objects compared by key, arrays in order }
function SameJson(AWant, AGot: TJSONData): Boolean;
var
  i, k: Integer;
  wo, go: TJSONObject;
begin
  Result := False;
  if (AWant = nil) or (AGot = nil) then Exit(AWant = AGot);
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
          k := go.IndexOfName(wo.Names[i]);
          if k < 0 then Exit;
          if not SameJson(wo.Items[i], go.Items[k]) then Exit;
        end;
        Result := True;
      end;
  end;
end;

procedure TAdvChartLegendScrollTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
  FLogger := TLsLogger.Create;
  FLogger.Log := TStringList.Create;
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath('advchart-legend-scroll.json'));
    FRoot := GetJSON(sl.Text);
    sl.LoadFromFile(FixturePath('advchart-text-style.json'));
    FMeasure := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  TyChartRegisterFormatter('PageFmt', @PageFmt);
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartLegendScrollTest.TearDown;
begin
  TyChartUnregisterFormatter('PageFmt');
  FChart.Free;
  FChart := nil;
  FLogger.Log.Free;
  FLogger.Free;
  FRoot.Free;
  FMeasure.Free;
  FBmp.Free;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

{ upstream's pageFormatter function in the oracle: 'P' + current + '|T' + total }
function TAdvChartLegendScrollTest.PageFmt(const AParams: TTyChartParams): string;
begin
  Result := 'P' + IntToStr(Round(AParams[0].Values[0])) + '|T'
    + IntToStr(Round(AParams[0].Values[1]));
end;

function TAdvChartLegendScrollTest.Ssr: ITyTextMeasurer;
begin
  Result := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
end;

procedure TAdvChartLegendScrollTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 12000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TAdvChartLegendScrollTest.Same(const AWhat: string; AGot: Double;
  const AHex: string);
begin
  Inc(FCompared);
  if HexOf(AGot) <> LowerCase(AHex) then
    Bad(Format('%s %s, upstream %s', [AWhat, Txt(AGot), Txt(FromHex(AHex))]));
end;

procedure TAdvChartLegendScrollTest.NewChart(AOption: TJSONObject);
const
  cTypes: array[0..7] of string = ('legendscroll', 'legendselectchanged',
    'legendselected', 'legendunselected', 'legendselectall',
    'legendinverseselect', 'highlight', 'downplay');
var i: Integer;
begin
  FChart.Free;
  FChart := TLsProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := Ssr;
  FChart.Option := AOption.AsJSON;
  FChart.SetBounds(0, 0, 600, 400);
  for i := 0 to High(cTypes) do
    FChart.ChartOn(cTypes[i], @FLogger.Handle);
  Frame;
end;

procedure TAdvChartLegendScrollTest.Frame;
begin
  FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
end;

function TAdvChartLegendScrollTest.CaseById(const AId: string): TJSONObject;
var
  arr: TJSONArray;
  i: Integer;
begin
  Result := nil;
  arr := TJSONObject(FRoot).Arrays['cases'];
  for i := 0 to arr.Count - 1 do
    if arr.Objects[i].Strings['id'] = AId then Exit(arr.Objects[i]);
end;

function TAdvChartLegendScrollTest.ThemeInk(const AKey: string;
  AHover: Boolean): TTyChartColor;
begin
  if AHover then
    Result := TTyChartColor(FCtl.Model.ResolveStyle(AKey, '', [tysHover]).TextColor)
  else
    Result := TTyChartColor(FCtl.Model.ResolveStyle(AKey, '', []).TextColor);
end;

{ what the display list puts first under (AX, AY), in the oracle's words }
function TAdvChartLegendScrollTest.HitName(AX, AY: Integer): string;
var
  idx: Integer;
  d: TTyChartDatumRef;
begin
  Result := 'none';
  idx := FChart.List.HitTestElement(AX, AY, 96);
  if idx < 0 then Exit;
  d := FChart.List.Element(idx).Datum;
  case d.Kind of
    ctkLegend: Result := 'item:' + IntToStr(d.DataIndex);
    ctkLegendSelector: Result := 'selector:' + IntToStr(d.DataIndex);
    ctkLegendPager:
      if d.DataIndex = 0 then Result := 'pager:prev' else Result := 'pager:next';
  else
    Result := 'other';
  end;
end;

{ ==================== the comparison ==================== }

procedure TAdvChartLegendScrollTest.CompareEvents(AWant: TJSONArray);
var
  i, p: Integer;
  ev: TJSONObject;
  line, gotType, all_: string;
  got: TJSONData;
begin
  Inc(FCompared);
  if AWant.Count <> FLogger.Log.Count then
  begin
    all_ := '';
    for i := 0 to FLogger.Log.Count - 1 do all_ := all_ + ' | ' + FLogger.Log[i];
    Bad(Format('%d events, upstream %d:%s', [FLogger.Log.Count, AWant.Count, all_]));
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
      if not SameJson(ev.Find('payload'), got) then
        Bad(Format('event %d %s payload %s, upstream %s', [i, gotType, got.AsJSON,
          ev.Find('payload').AsJSON]));
    finally
      got.Free;
    end;
  end;
end;

procedure TAdvChartLegendScrollTest.CompareState(AState: TJSONObject);
var
  lay: TTyLegendLayout;
  arr, t, r: TJSONArray;
  it, sel, part: TJSONObject;
  i, k, j, cnt, hitIdx: Integer;
  gx, gy: Double;
  l: TTyPaintList;
  el: TTyChartElement;
  fill: string;
  want, got: TTyChartColor;
  d, opt: TJSONData;
  scroll: Boolean;

  procedure SameRect(const AWhat: string; const AR: TTyXYWH; AArr: TJSONArray);
  begin
    Same(AWhat + '.x', AR.X, AArr.Strings[0]);
    Same(AWhat + '.y', AR.Y, AArr.Strings[1]);
    Same(AWhat + '.w', AR.W, AArr.Strings[2]);
    Same(AWhat + '.h', AR.H, AArr.Strings[3]);
  end;

  { the element of kind AKind and index AIdx: the hit target }
  function HitOf(AKind: TTyChartTargetKind; AIdx: Integer): Integer;
  var q: Integer;
  begin
    Result := -1;
    for q := 0 to l.Count - 1 do
      if (l.Element(q).Datum.Kind = AKind) and (l.Element(q).Datum.DataIndex = AIdx) then
        Exit(q);
  end;

  { the first text piece's fill of a caption }
  function PieceFill(const AEl: TTyChartElement): TTyChartColor;
  var q: Integer;
  begin
    Result := 0;
    for q := 0 to High(AEl.Caption.RtPieces) do
      if AEl.Caption.RtPieces[q].Kind = rpkText then Exit(AEl.Caption.RtPieces[q].Fill);
  end;

  procedure ComparePart(const AWhat: string; const AP: TTyLegendPagerPart;
    AFix: TJSONObject);
  begin
    Same(AWhat + ' x', AP.X, AFix.Arrays['t'].Strings[0]);
    Same(AWhat + ' y', AP.Y, AFix.Arrays['t'].Strings[1]);
    SameRect(AWhat + ' rect', AP.Local, AFix.Arrays['r']);
  end;

begin
  lay := FChart.LegendLayout(0);
  l := FChart.List;
  if not lay.Valid then
  begin
    Bad('the legend is not laid out');
    Exit;
  end;
  scroll := AState.Strings['type'] = 'legend.scroll';
  if lay.IsScroll <> scroll then Bad('scroll ' + BoolToStr(lay.IsScroll, True));
  { the group and the main rect }
  Same('group x', lay.GroupX, AState.Arrays['group'].Strings[0]);
  Same('group y', lay.GroupY, AState.Arrays['group'].Strings[1]);
  SameRect('mainRect', lay.MainRect, AState.Arrays['mainRect']);
  gx := lay.GroupX;
  gy := lay.GroupY;
  r := AState.Arrays['bg'];
  Same('frame left', lay.Frame.Left, HexOf(gx + Hx(r, 0)));
  Same('frame top', lay.Frame.Top, HexOf(gy + Hx(r, 1)));
  Same('frame right', lay.Frame.Right, HexOf(gx + Hx(r, 0) + Hx(r, 2)));
  Same('frame bottom', lay.Frame.Bottom, HexOf(gy + Hx(r, 1) + Hx(r, 3)));

  { the items: each data index's global transform and bounding rect }
  arr := AState.Arrays['items'];
  cnt := 0;
  for i := 0 to High(lay.Items) do
    if (lay.Items[i].Bounds.Right > lay.Items[i].Bounds.Left) then Inc(cnt);
  if cnt <> arr.Count then Bad(Format('%d items placed, upstream %d', [cnt, arr.Count]));
  for j := 0 to arr.Count - 1 do
  begin
    it := arr.Objects[j];
    i := it.Integers['i'];
    if i > High(lay.Items) then
    begin
      Bad(Format('no item %d', [i]));
      Continue;
    end;
    if lay.Items[i].Text <> it.Strings['name'] then
      Bad(Format('item %d says %s, upstream %s', [i, lay.Items[i].Text, it.Strings['name']]));
    t := it.Arrays['t'];
    r := it.Arrays['r'];
    Same(Format('item %d x', [i]), lay.Items[i].IconBox.Left, t.Strings[0]);
    Same(Format('item %d y', [i]), lay.Items[i].IconBox.Top, t.Strings[1]);
    Same(Format('item %d left', [i]), lay.Items[i].Bounds.Left, HexOf(Hx(t, 0) + Hx(r, 0)));
    Same(Format('item %d top', [i]), lay.Items[i].Bounds.Top, HexOf(Hx(t, 1) + Hx(r, 1)));
    Same(Format('item %d right', [i]), lay.Items[i].Bounds.Right,
      HexOf(Hx(t, 0) + Hx(r, 0) + Hx(r, 2)));
    Same(Format('item %d bottom', [i]), lay.Items[i].Bounds.Bottom,
      HexOf(Hx(t, 1) + Hx(r, 1) + Hx(r, 3)));
  end;

  { the selector's buttons: place, box, words and ink }
  arr := AState.Arrays['selector'];
  if Length(lay.Selector) <> arr.Count then
    Bad(Format('%d selector buttons, upstream %d', [Length(lay.Selector), arr.Count]))
  else
    for k := 0 to arr.Count - 1 do
    begin
      sel := arr.Objects[k];
      if lay.Selector[k].Title <> sel.Strings['title'] then
        Bad(Format('button %d says %s, upstream %s', [k, lay.Selector[k].Title,
          sel.Strings['title']]));
      if lay.Selector[k].IsAll <> (sel.Strings['type'] = 'all') then
        Bad(Format('button %d is the wrong kind', [k]));
      Same(Format('button %d x', [k]), lay.Selector[k].X, sel.Arrays['t'].Strings[0]);
      Same(Format('button %d y', [k]), lay.Selector[k].Y, sel.Arrays['t'].Strings[1]);
      SameRect(Format('button %d rect', [k]), lay.Selector[k].Local, sel.Arrays['r']);
      { the drawn words: the hit target, then the caption }
      hitIdx := HitOf(ctkLegendSelector, k);
      if (hitIdx < 0) or (hitIdx + 1 >= l.Count) then
      begin
        Bad(Format('button %d is not in the display list', [k]));
        Continue;
      end;
      el := l.Element(hitIdx + 1);
      fill := LowerCase(sel.Strings['fill']);
      if fill = '#6d6e73' then want := ThemeInk('TyAdvChartLegendSelector')
      else if fill = '#86878c' then want := ThemeInk('TyAdvChartLegendSelector', True)
      else want := ColourOf(fill);
      got := PieceFill(el);
      Inc(FCompared);
      if got <> want then
        Bad(Format('button %d ink $%s, want $%s (upstream %s, states %s)', [k,
          IntToHex(got, 8), IntToHex(want, 8), fill, sel.Arrays['st'].AsJSON]));
    end;

  if scroll then
  begin
    part := AState.Objects['ctl'];
    if lay.ShowController <> part.Booleans['show'] then
      Bad('showController ' + BoolToStr(lay.ShowController, True));
    ComparePart('prev', lay.PagePrev, part.Objects['prev']);
    ComparePart('page text', lay.PageTextPart, part.Objects['text']);
    ComparePart('next', lay.PageNext, part.Objects['next']);
    if lay.PageText <> part.Objects['text'].Strings['text'] then
      Bad(Format('page text %s, upstream %s', [lay.PageText,
        part.Objects['text'].Strings['text']]));
    { drawn only when shown: the icons' inks and the words' }
    for k := 0 to 1 do
    begin
      hitIdx := HitOf(ctkLegendPager, k);
      if not lay.ShowController then
      begin
        if hitIdx >= 0 then Bad('a hidden pager takes the pointer');
        Continue;
      end;
      if hitIdx < 1 then
      begin
        Bad(Format('page button %d is not in the display list', [k]));
        Continue;
      end;
      if k = 0 then fill := LowerCase(part.Objects['prev'].Strings['fill'])
      else fill := LowerCase(part.Objects['next'].Strings['fill']);
      if fill = '#6578ba' then want := ThemeInk('TyAdvChartLegendPageIcon')
      else if fill = '#e0e4f2' then want := ThemeInk('TyAdvChartLegendPageIconInactive')
      else want := ColourOf(fill);
      el := l.Element(hitIdx - 1);
      Inc(FCompared);
      if (not el.Style.HasFill) or (el.Style.FillColor <> want) then
        Bad(Format('page button %d ink $%s, want $%s (upstream %s)', [k,
          IntToHex(el.Style.FillColor, 8), IntToHex(want, 8), fill]));
      if k = 0 then
      begin
        el := l.Element(hitIdx + 1);
        fill := LowerCase(part.Objects['text'].Strings['fill']);
        if fill = '#6d6e73' then want := ThemeInk('TyAdvChartLegendPageText')
        else want := ColourOf(fill);
        Inc(FCompared);
        if (el.Caption.Text <> lay.PageText) or (el.Caption.Colour <> want) then
          Bad(Format('page text drawn %s in $%s, want $%s', [el.Caption.Text,
            IntToHex(el.Caption.Colour, 8), IntToHex(want, 8)]));
      end;
    end;
    { the clip }
    d := AState.Find('clip');
    if (d = nil) or (d.JSONType = jtNull) then
    begin
      if lay.HasClip then Bad('a clip where upstream has none');
    end
    else if not lay.HasClip then
      Bad('no clip')
    else
    begin
      part := TJSONObject(d);
      t := part.Arrays['t'];
      Same('clip left', lay.Clip.Left, t.Strings[0]);
      Same('clip top', lay.Clip.Top, t.Strings[1]);
      Same('clip right', lay.Clip.Right, HexOf(Hx(t, 0) + FromHex(part.Strings['w'])));
      Same('clip bottom', lay.Clip.Bottom, HexOf(Hx(t, 1) + FromHex(part.Strings['h'])));
    end;
    { the page info }
    part := AState.Objects['page'];
    Inc(FCompared);
    if (lay.PageIndex <> part.Integers['index']) or (lay.PageCount <> part.Integers['count']) then
      Bad(Format('page %d of %d, upstream %d of %d', [lay.PageIndex, lay.PageCount,
        part.Integers['index'], part.Integers['count']]));
    if part.Find('prev').JSONType = jtNull then k := -1 else k := part.Integers['prev'];
    if lay.PagePrevIndex <> k then Bad(Format('prev page at %d, upstream %d', [lay.PagePrevIndex, k]));
    if part.Find('next').JSONType = jtNull then k := -1 else k := part.Integers['next'];
    if lay.PageNextIndex <> k then Bad(Format('next page at %d, upstream %d', [lay.PageNextIndex, k]));
    { scrollDataIndex as the model holds it (the default 0 when unwritten) }
    opt := GetJSON(FChart.GetOptionJson);
    try
      d := nil;
      if (opt is TJSONObject) and (TJSONObject(opt).Find('legend') <> nil) then
      begin
        d := TJSONObject(opt).Find('legend');
        if d is TJSONArray then d := TJSONArray(d).Items[0];
        if d is TJSONObject then d := TJSONObject(d).Find('scrollDataIndex') else d := nil;
      end;
      Inc(FCompared);
      if d = nil then
      begin
        if AState.Find('scrollDataIndex').AsJSON <> '0' then
          Bad('scrollDataIndex unwritten, upstream ' + AState.Find('scrollDataIndex').AsJSON);
      end
      else if not SameJson(AState.Find('scrollDataIndex'), d) then
        Bad('scrollDataIndex ' + d.AsJSON + ', upstream ' + AState.Find('scrollDataIndex').AsJSON);
    finally
      opt.Free;
    end;
  end;

  { the selected map }
  opt := GetJSON(FChart.LegendSelectedText(0));
  try
    Inc(FCompared);
    if not SameJson(AState.Find('selected'), opt) then
      Bad('selected ' + opt.AsJSON + ', upstream ' + AState.Find('selected').AsJSON);
  finally
    opt.Free;
  end;
end;

{ ==================== the replay ==================== }

procedure TAdvChartLegendScrollTest.TestEveryLegendAsUpstreamDrawsIt;
var
  arr, steps: TJSONArray;
  c, s: Integer;
  cs, st: TJSONObject;
  tp, hit: string;
  x, y: Integer;
begin
  arr := TJSONObject(FRoot).Arrays['cases'];
  AssertTrue('the fixture has its 45 cases', arr.Count >= 45);
  for c := 0 to arr.Count - 1 do
  begin
    cs := arr.Objects[c];
    steps := cs.Arrays['steps'];
    FWhere := cs.Strings['id'] + ' init';
    NewChart(cs.Objects['option']);
    FLogger.Log.Clear;
    CompareState(steps.Objects[0].Objects['state']);
    for s := 1 to steps.Count - 1 do
    begin
      st := steps.Objects[s];
      tp := st.Strings['type'];
      FWhere := Format('%s step %d (%s)', [cs.Strings['id'], s, tp]);
      FLogger.Log.Clear;
      if tp = 'action' then
        FChart.DispatchAction(st.Objects['payload'].AsJSON)
      else
      begin
        x := st.Integers['x'];
        y := st.Integers['y'];
        hit := HitName(x, y);
        Inc(FCompared);
        if hit <> st.Strings['hit'] then
          Bad(Format('(%d, %d) hits %s, upstream %s', [x, y, hit, st.Strings['hit']]));
        if tp = 'click' then FChart.ClickAt(x, y)
        else if tp = 'wheel' then FChart.Wheel(x, y)
        else FChart.Move(x, y);
      end;
      Frame;
      CompareEvents(st.Arrays['events']);
      CompareState(st.Objects['state']);
    end;
  end;
  if FBad > 0 then
    Fail(Format('%d of %d comparisons differ:%s', [FBad, FCompared, FReport]));
  AssertTrue('compared', FCompared > 5000);
end;

{ ==================== the hand cases ==================== }

{ upstream (a probe on the real build): 'circle' is not path data -- the icon
  parses to nothing and lays out as the empty rect at the origin; the next
  'path://M0,0L5,5L0,8Z' is fitted into 15 x 15 keeping its 5:8 aspect }
procedure TAdvChartLegendScrollTest.TestAPageIconThatParsesToNothingIsAnEmptyBox;
var lay: TTyLegendLayout;
begin
  NewChart(TJSONObject(GetJSON('{"animation":false,"legend":{"type":"scroll",'
    + '"pageIcons":{"horizontal":["circle","path://M0,0L5,5L0,8Z"]}},'
    + '"xAxis":{"type":"category","data":["a"]},"yAxis":{},"series":['
    + '{"type":"bar","name":"Series 0","data":[1]},{"type":"bar","name":"Series 1","data":[1]},'
    + '{"type":"bar","name":"Series 2","data":[1]},{"type":"bar","name":"Series 3","data":[1]},'
    + '{"type":"bar","name":"Series 4","data":[1]},{"type":"bar","name":"Series 5","data":[1]},'
    + '{"type":"bar","name":"Series 6","data":[1]},{"type":"bar","name":"Series 7","data":[1]},'
    + '{"type":"bar","name":"Series 8","data":[1]},{"type":"bar","name":"Series 9","data":[1]},'
    + '{"type":"bar","name":"Series 10","data":[1]},{"type":"bar","name":"Series 11","data":[1]}]}')));
  lay := FChart.LegendLayout(0);
  AssertTrue('shown', lay.ShowController);
  AssertEquals('prev has no path', 0, Length(lay.PagePrev.Path));
  AssertEquals('prev x', 0.0, lay.PagePrev.Local.X);
  AssertEquals('prev w', 0.0, lay.PagePrev.Local.W);
  AssertEquals('next x', -4.6875, lay.PageNext.Local.X);
  AssertEquals('next w', 9.375, lay.PageNext.Local.W);
  AssertEquals('next h', 15.0, lay.PageNext.Local.H);
  { and the placeholder text follows the empty icon at its own half width
    plus the item gap (upstream: 18.68) }
  AssertEquals('text x from the empty icon', 18.68,
    lay.PageTextPart.X - lay.PagePrev.X, 1e-9);
end;

{ upstream: an 'image://' icon is a ZRImage of the box -- laid out as the
  whole 15 x 15 box (drawn by upstream, not here) }
procedure TAdvChartLegendScrollTest.TestAnImageIconIsItsBox;
var lay: TTyLegendLayout; spec: TTyLegendSpec; opt: TTyChartOption;
  ent: TTyLegendEntryArray; flags: TTyLegendFlags; src: TTyLegendSourceArray;
  deco: TTyLegendDeco; fnt: TTyLegendFont; i: Integer;
  names: array of string;
begin
  opt := TTyChartOption.Create;
  try
    AssertTrue(opt.SetOptionText('{"legend":{"type":"scroll","pageIcons":'
      + '{"horizontal":["image://x.png","path://M0,0L5,5L0,8Z"]}}}'));
    spec := TyLegendSpecOf(opt, 0);
    SetLength(names, 30);
    for i := 0 to 29 do names[i] := 'Series ' + IntToStr(i);
    ent := TyLegendEntries(opt, 0, names);
    SetLength(flags, Length(ent));
    SetLength(src, Length(ent));
    for i := 0 to High(ent) do
    begin
      flags[i] := True;
      src[i] := Default(TTyLegendSource);
      src[i].Found := True;
      src[i].SeriesType := 'bar';
    end;
    fnt := Default(TTyLegendFont);
    fnt.Name := 'sans-serif';
    fnt.SizeLogical := 9;
    deco := Default(TTyLegendDeco);
    deco.Measurer := Ssr;
    deco.PageFontName := 'sans-serif';
    deco.PageFontSize := 9;
    lay := TyLayoutLegend(spec, ent, flags, src, TyRectF(0, 0, 600, 400), Ssr, fnt, 96, deco);
    AssertTrue('laid out', lay.Valid);
    AssertTrue('shown', lay.ShowController);
    AssertTrue('an image', lay.PagePrev.IsImage);
    AssertEquals('image x', -7.5, lay.PagePrev.Local.X);
    AssertEquals('image y', -7.5, lay.PagePrev.Local.Y);
    AssertEquals('image w', 15.0, lay.PagePrev.Local.W);
    AssertEquals('image h', 15.0, lay.PagePrev.Local.H);
  finally
    opt.Free;
  end;
end;

{ ECharts' locale: legend.selector.all / inverse, 'All' and 'Inv' in its
  English; a title the option wrote stays, and a type that is neither has
  no default title }
procedure TAdvChartLegendScrollTest.TestTheSelectorTitlesAreTheLocales;
var opt: TTyChartOption; spec: TTyLegendSpec;
begin
  opt := TTyChartOption.Create;
  try
    AssertTrue(opt.SetOptionText('{"legend":{"selector":true}}'));
    spec := TyLegendSpecOf(opt, 0);
    AssertEquals(2, Length(spec.Selector));
    AssertEquals('All', spec.Selector[0].Title);
    AssertTrue(spec.Selector[0].IsAll);
    AssertEquals('Inv', spec.Selector[1].Title);
    AssertFalse(spec.Selector[1].IsAll);
    AssertTrue('horizontal: auto is the end', spec.SelectorAtEnd);
    AssertTrue(opt.SetOptionText('{"legend":{"orient":"vertical","selector":'
      + '["inverse",{"type":"all","title":"Every"},{"type":"odd"},{"title":"T"}]}}'));
    spec := TyLegendSpecOf(opt, 0);
    AssertEquals(4, Length(spec.Selector));
    AssertEquals('Inv', spec.Selector[0].Title);
    AssertEquals('Every', spec.Selector[1].Title);
    AssertTrue(spec.Selector[1].IsAll);
    AssertEquals('', spec.Selector[2].Title);
    AssertFalse('a type that is neither clicks as the inverse', spec.Selector[2].IsAll);
    AssertEquals('T', spec.Selector[3].Title);
    AssertFalse('vertical: auto is the start', spec.SelectorAtEnd);
    AssertTrue(opt.SetOptionText('{"legend":{"selector":false}}'));
    AssertFalse(TyLegendSpecOf(opt, 0).HasSelector);
    AssertTrue(opt.SetOptionText('{"legend":{"selector":[]}}'));
    AssertTrue('an empty array is a selector', TyLegendSpecOf(opt, 0).HasSelector);
  finally
    opt.Free;
  end;
end;

{ eachComponent with subType 'scroll': a legendScroll naming a plain legend
  writes nothing -- and still publishes its event after the update }
procedure TAdvChartLegendScrollTest.TestALegendScrollNamingAPlainLegendDoesNothing;
begin
  NewChart(TJSONObject(GetJSON('{"animation":false,"legend":[{"type":"scroll"},{}],'
    + '"xAxis":{"type":"category","data":["a"]},"yAxis":{},'
    + '"series":[{"type":"bar","name":"A","data":[1]}]}')));
  FLogger.Log.Clear;
  AssertTrue(FChart.DispatchAction('{"type":"legendScroll","scrollDataIndex":3,"legendIndex":1}'));
  AssertEquals('the event', 1, FLogger.Log.Count);
  AssertTrue('the plain legend took no scrollDataIndex',
    Pos('"scrollDataIndex"', FChart.GetOptionJson) = 0);
  AssertTrue(FChart.DispatchAction('{"type":"legendScroll","scrollDataIndex":3}'));
  AssertTrue('every scroll legend takes it', Pos('"scrollDataIndex"', FChart.GetOptionJson) > 0);
end;

{ the theme rule: the buttons, the arrows and the page text are the skin's
  ink, each through its own key }
procedure TAdvChartLegendScrollTest.TestTheSkinsInksAreTheDefaults;
var
  lay: TTyLegendLayout;
  l: TTyPaintList;
  k: Integer;
  sawText, sawIcon: Boolean;
begin
  NewChart(CaseById('scroll-sel').Objects['option']);
  lay := FChart.LegendLayout(0);
  AssertTrue(lay.ShowController);
  AssertTrue(ThemeInk('TyAdvChartLegendSelector') <> ThemeInk('TyAdvChartLegendSelector', True));
  AssertTrue(ThemeInk('TyAdvChartLegendPageIcon') <> ThemeInk('TyAdvChartLegendPageIconInactive'));
  l := FChart.List;
  sawText := False;
  sawIcon := False;
  for k := 0 to l.Count - 1 do
  begin
    if (l.Element(k).Caption.Text = lay.PageText) and (lay.PageText <> '') then
    begin
      AssertEquals('page text ink', ThemeInk('TyAdvChartLegendPageText'), l.Element(k).Caption.Colour);
      sawText := True;
    end;
    if (l.Element(k).Datum.Kind = ctkLegendPager) and (l.Element(k).Datum.DataIndex = 1) then
    begin
      AssertEquals('the next arrow', ThemeInk('TyAdvChartLegendPageIcon'),
        l.Element(k - 1).Style.FillColor);
      sawIcon := True;
    end;
  end;
  AssertTrue(sawText);
  AssertTrue(sawIcon);
end;

{ zrender's isHover asks the ancestors' clip paths: the item past the window
  is drawn clipped and takes no pointer; the one straddling it takes it only
  inside }
procedure TAdvChartLegendScrollTest.TestAnItemOutsideTheClipTakesNoPointer;
var
  lay: TTyLegendLayout;
  i, outside, straddle: Integer;
  cy: Integer;
begin
  NewChart(CaseById('h-basic').Objects['option']);
  lay := FChart.LegendLayout(0);
  AssertTrue(lay.HasClip);
  outside := -1;
  straddle := -1;
  for i := 0 to High(lay.Items) do
  begin
    if (lay.Items[i].Bounds.Left > lay.Clip.Right) and (outside < 0) then outside := i;
    if (lay.Items[i].Bounds.Left < lay.Clip.Right) and (lay.Items[i].Bounds.Right > lay.Clip.Right) then
      straddle := i;
  end;
  AssertTrue('an item past the window', outside >= 0);
  AssertTrue('an item across its edge', straddle >= 0);
  cy := Round((lay.Items[outside].Bounds.Top + lay.Items[outside].Bounds.Bottom) / 2);
  AssertFalse('past the window: nothing',
    HitName(Round(lay.Items[outside].Bounds.Left) + 3, cy) = 'item:' + IntToStr(outside));
  AssertEquals('inside the window: the straddling item', 'item:' + IntToStr(straddle),
    HitName(Trunc(lay.Clip.Right) - 2, cy));
  AssertFalse('outside it: not the straddling item',
    HitName(Ceil(lay.Clip.Right) + 2, cy) = 'item:' + IntToStr(straddle));
end;

{ updateProps(contentGroup, page position, legendModel): the legend's
  animationDurationUpdate (800, ScrollableLegendModel's default) and the
  global animationEasingUpdate 'cubicInOut', from where the content stands;
  the clock starts at the first step }
procedure TAdvChartLegendScrollTest.TestTheScrollTweensWithTheLegendsUpdateTiming;
var
  opt: TJSONObject;

  function LeftOf(AItem: Integer): Double;
  var q: Integer; l: TTyPaintList;
  begin
    Result := NaN;
    l := FChart.List;
    for q := 0 to l.Count - 1 do
      if (l.Element(q).Datum.Kind = ctkLegend) and (l.Element(q).Datum.DataIndex = AItem) then
        Exit(l.Element(q).Shape.Bounds.Left);
  end;

begin
  opt := TJSONObject(CaseById('h-basic').Objects['option'].Clone);
  try
    opt.Delete('animation');
    FChart.Free;
    FChart := TLsProbe.Create(FForm);
    FChart.Parent := FForm;
    FChart.Controller := FCtl;
    FChart.Measurer := Ssr;
    FChart.AnimationMode := camAlways;
    FChart.AnimNow := 1000;
    FChart.Option := opt.AsJSON;
    FChart.SetBounds(0, 0, 600, 400);
    Frame;
  finally
    opt.Free;
  end;
  AssertEquals('page one: item 6 where it was laid out', 497.96, LeftOf(6), 1e-9);
  AssertTrue(FChart.DispatchAction('{"type":"legendScroll","scrollDataIndex":6}'));
  Frame;
  AssertEquals('before the first step the element holds its final value', 5.0, LeftOf(6), 1e-9);
  FChart.AnimTick(1000);
  Frame;
  AssertEquals('the first step writes the start back', 497.96, LeftOf(6), 1e-9);
  FChart.AnimTick(1400);
  Frame;
  { cubicInOut(0.5) = 0.5: half way }
  AssertEquals('half way at 400 of 800 ms', 251.48, LeftOf(6), 1e-9);
  FChart.AnimTick(1600);
  Frame;
  { cubicInOut(0.75) = 0.5 * (0.5^3 - ... ) = 0.9375 }
  AssertEquals('cubicInOut at three quarters', 497.96 - 492.96 * 0.9375, LeftOf(6), 1e-9);
  FChart.AnimTick(1800);
  Frame;
  AssertEquals('at rest on the page', 5.0, LeftOf(6), 1e-9);
end;

{ the first render: the content group stands at contentPos (unscrolled) and
  updateProps takes it to the page scrollDataIndex names }
procedure TAdvChartLegendScrollTest.TestAFirstRenderScrollsFromTheUnscrolledContent;
var
  opt: TJSONObject;

  function LeftOf(AItem: Integer): Double;
  var q: Integer; l: TTyPaintList;
  begin
    Result := NaN;
    l := FChart.List;
    for q := 0 to l.Count - 1 do
      if (l.Element(q).Datum.Kind = ctkLegend) and (l.Element(q).Datum.DataIndex = AItem) then
        Exit(l.Element(q).Shape.Bounds.Left);
  end;

begin
  opt := TJSONObject(CaseById('h-sdi5').Objects['option'].Clone);
  try
    opt.Delete('animation');
    FChart.Free;
    FChart := TLsProbe.Create(FForm);
    FChart.Parent := FForm;
    FChart.Controller := FCtl;
    FChart.Measurer := Ssr;
    FChart.AnimationMode := camAlways;
    FChart.AnimNow := 1000;
    FChart.Option := opt.AsJSON;
    FChart.SetBounds(0, 0, 600, 400);
    Frame;
  finally
    opt.Free;
  end;
  FChart.AnimTick(1000);
  Frame;
  AssertEquals('the first step: item 5 unscrolled', 415.8, LeftOf(5), 1e-9);
  FChart.AnimTick(1800);
  Frame;
  AssertEquals('then on its page', 5.0, LeftOf(5), 1e-9);
end;

{ the button dispatches with ITS legend's id: legendIndex in the event is
  that legend's, and the other legend's own items follow through the
  write-back to every legend (legendAction.ts) }
procedure TAdvChartLegendScrollTest.TestAButtonActsOnItsOwnLegend;
var
  lay: TTyLegendLayout;
  x, y: Integer;
begin
  NewChart(TJSONObject(GetJSON('{"animation":false,"legend":[{"top":10,"data":["A"]},'
    + '{"selector":true,"bottom":10,"data":["B"]}],'
    + '"xAxis":{"type":"category","data":["a"]},"yAxis":{},'
    + '"series":[{"type":"bar","name":"A","data":[1]},{"type":"bar","name":"B","data":[1]}]}')));
  lay := FChart.LegendLayout(1);
  AssertEquals('legend 1 has the buttons', 2, Length(lay.Selector));
  AssertEquals('legend 0 has none', 0, Length(FChart.LegendLayout(0).Selector));
  x := Round((lay.Selector[1].Box.Left + lay.Selector[1].Box.Right) / 2);
  y := Round((lay.Selector[1].Box.Top + lay.Selector[1].Box.Bottom) / 2);
  FLogger.Log.Clear;
  FChart.ClickAt(x, y);
  Frame;
  AssertEquals(1, FLogger.Log.Count);
  AssertEquals('legendinverseselect' + #9
    + '{"selected":{"A":true,"B":false},"legendIndex":[1],"type":"legendinverseselect"}',
    FLogger.Log[0]);
end;

initialization
  RegisterTest(TAdvChartLegendScrollTest);
end.
