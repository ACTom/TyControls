unit test.advchart.labelguides;
{$mode objfpc}{$H+}
{ Label lines beyond label-line.js, held to ECharts 6.1 [R5-C]:

    - the pie's and the funnel's own line under its normal labelLine.lineStyle
      (colour, width, type, cap, join, dashOffset, miterLimit, opacity) and
      the line a state alone shows (labelLine.show false, a state's true);
    - the lines LabelManager._updateLabelLine builds on every other series
      whose elements carry a label: heatmap cells, pictorial bars, graph and
      tree symbols, sunburst sectors, sankey nodes, polar bars, a calendar's
      scatter.

  tools/advchart-oracle/label-guides.js runs the real dist and records every
  routing call (the host's path data and transform) and every label line as
  drawn and under each hover / select payload. The control renders each
  option (zrender's SSR width table measures the words) and every line is
  compared: hidden or not, its points, whether it curves, its style, its z
  against its host; the hosts' paths and transforms against upstream's. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.Painter, tyControls.Types,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint, tyControls.AdvanceChart.Shape,
     tyControls.AdvanceChart.LabelGuide, tyControls.AdvanceChart.Color,
     tyControls.AdvanceChart.Measure, tyControls.AdvanceChart.Render, tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TLgsProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  TAdvChartLabelGuidesTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TLgsProbe;
    FRoot, FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared, FGuides, FHidden, FStyled, FHover, FHosts: Integer;
    FName, FReport: string;
    procedure Miss(const AWhat: string);
    procedure Num(const AWhat: string; AGot: Double; const AHex: string);
    procedure Same(const AWhat: string; AGot, AWant: Boolean);
    function Cases: TJSONArray;
    function CaseOf(const AId: string): TJSONObject;
    procedure Show(ACase: TJSONObject);
    procedure Finish(AMin: Integer);
    procedure CheckPoints(const AWhat: string; const AGot: array of TTyPointF; APts: TJSONArray);
    procedure CheckStyle(const AWhat: string; const AEl: TTyChartElement;
      AStyle: TJSONObject; const AHostFill, AHostStroke: string; AItemColour: TTyChartColor);
    function ItemColour(AGuide: Integer): TTyChartColor;
    procedure CheckGuides(ACase: TJSONObject);
    procedure CheckHover(ACase: TJSONObject);
    procedure RunGroup(const APrefix: array of string; AMin: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestThePiesOwnLineAsUpstream;
    procedure TestTheFunnelsOwnLineAsUpstream;
    procedure TestTheOtherSeriesLinesAsUpstream;
    procedure TestAPieLineInkAndPen;
    procedure TestEndLabelStatesAsUpstream;
    procedure TestThePenReachesThePainter;
  end;

implementation

{ ---------------- the probe ---------------- }

function TLgsProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TLgsProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TLgsProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

{ ---------------- numbers ---------------- }

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

function Fmt(A: Double): string;
begin
  Result := FloatToStrF(A, ffGeneral, 17, 0, DefaultFormatSettings);
end;

function SameNum(A, B: Double): Boolean;
begin
  if IsNan(A) or IsNan(B) then Exit(IsNan(A) and IsNan(B));
  Result := Bits(A) = Bits(B);
end;

function IsNull(D: TJSONData): Boolean;
begin
  Result := (D = nil) or (D.JSONType = jtNull);
end;

function HexArray(A: TJSONArray): TTyDoubleArray;
var i: Integer;
begin
  SetLength(Result, A.Count);
  for i := 0 to A.Count - 1 do Result[i] := FromHex(A.Strings[i]);
end;

function MatOf(A: TJSONData; out M: TTyMat2D): Boolean;
var i: Integer;
begin
  Result := not IsNull(A);
  for i := 0 to 5 do M[i] := 0;
  if not Result then Exit;
  for i := 0 to 5 do M[i] := FromHex(TJSONArray(A).Strings[i]);
end;

function StrOf(AObj: TJSONObject; const AKey: string): string;
var d: TJSONData;
begin
  Result := '';
  if AObj = nil then Exit;
  d := AObj.Find(AKey);
  if (d <> nil) and (d.JSONType = jtString) then Result := d.AsString;
end;

function FixtureDir: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim;
end;

{ ---------------- finding ---------------- }

function FindGuide(AList: TTyPaintList; ASeries, AData: Integer): Integer;
var i: Integer;
begin
  for i := 0 to AList.Count - 1 do
    if (AList.Element(i).Anim.Role = carGuide) and (AList.Element(i).Anim.Series = ASeries)
      and (AList.Element(i).Anim.Index = AData) then
      Exit(i);
  Result := -1;
end;

{ the label a general line was built for: a label on a host, same datum }
function FindLabel(AList: TTyPaintList; ASeries, AData: Integer): Integer;
var i: Integer;
begin
  for i := 0 to AList.Count - 1 do
    if (AList.Element(i).Caption.LmKind > 0) and (AList.Element(i).Anim.Role <> carGuide)
      and (AList.Element(i).Caption.LmHostPlus1 > 0)
      and (AList.Element(i).Datum.SeriesIndex = ASeries)
      and (AList.Element(i).Datum.DataIndex = AData) then
      Exit(i);
  Result := -1;
end;

{ ECHARTS 6'S DEFAULT PALETTE: the port's theme has its own }
function IsPaletteColour(const S: string): Boolean;
begin
  Result := (S = '#5070dd') or (S = '#b6d634') or (S = '#505372') or (S = '#ff994d')
    or (S = '#0ca8df') or (S = '#ffd10a') or (S = '#fb628b') or (S = '#785db0')
    or (S = '#3fbe95');
end;

{ ---------------- the test case ---------------- }

procedure TAdvChartLabelGuidesTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 120 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartLabelGuidesTest.Num(const AWhat: string; AGot: Double;
  const AHex: string);
begin
  Inc(FCompared);
  if not SameNum(AGot, FromHex(AHex)) then
    Miss(Format('%s: %s upstream, %s here', [AWhat, Fmt(FromHex(AHex)), Fmt(AGot)]));
end;

procedure TAdvChartLabelGuidesTest.Same(const AWhat: string; AGot, AWant: Boolean);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Miss(Format('%s: %s upstream, %s here', [AWhat, BoolToStr(AWant, True),
      BoolToStr(AGot, True)]));
end;

function TAdvChartLabelGuidesTest.Cases: TJSONArray;
begin
  Result := TJSONObject(FRoot).Arrays['cases'];
end;

function TAdvChartLabelGuidesTest.CaseOf(const AId: string): TJSONObject;
var i: Integer;
begin
  for i := 0 to Cases.Count - 1 do
    if Cases.Objects[i].Strings['id'] = AId then Exit(Cases.Objects[i]);
  Result := nil;
end;

procedure TAdvChartLabelGuidesTest.Show(ACase: TJSONObject);
var cw, ch: Integer;
begin
  cw := ACase.Integers['W'];
  ch := ACase.Integers['H'];
  FBmp.SetSize(cw, ch);
  FChart.Option := '{}';
  FChart.Option := ACase.Objects['option'].AsJSON;
  FChart.SetBounds(0, 0, cw, ch);
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cw, ch), 96);
end;

procedure TAdvChartLabelGuidesTest.Finish(AMin: Integer);
begin
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
  AssertTrue(Format('enough was compared (%d)', [FCompared]), FCompared > AMin);
end;

procedure TAdvChartLabelGuidesTest.CheckPoints(const AWhat: string;
  const AGot: array of TTyPointF; APts: TJSONArray);
var k: Integer;
begin
  Inc(FCompared);
  if Length(AGot) <> APts.Count then
  begin
    Miss(Format('%s: %d points upstream, %d here', [AWhat, APts.Count, Length(AGot)]));
    Exit;
  end;
  for k := 0 to APts.Count - 1 do
  begin
    Num(AWhat + ' x' + IntToStr(k), AGot[k].X, TJSONArray(APts.Items[k]).Strings[0]);
    Num(AWhat + ' y' + IntToStr(k), AGot[k].Y, TJSONArray(APts.Items[k]).Strings[1]);
  end;
end;

{ THE ITEM'S COLOUR as the port knows it: a general line's host's LgColor,
  a pie's slice fill, a funnel band's fill }
function TAdvChartLabelGuidesTest.ItemColour(AGuide: Integer): TTyChartColor;
var
  i, lb: Integer;
  g, el: TTyChartElement;
begin
  g := FChart.List.Element(AGuide);
  lb := FindLabel(FChart.List, g.Anim.Series, g.Anim.Index);
  if lb >= 0 then
    Exit(FChart.List.Element(FChart.List.Element(lb).Caption.LmHostPlus1 - 1).Caption.LgColor);
  for i := 0 to FChart.List.Count - 1 do
  begin
    el := FChart.List.Element(i);
    if (el.Anim.Role in [carSector, carFunnel]) and (el.Anim.Series = g.Anim.Series)
      and (el.Anim.Index = g.Anim.Index) then
      Exit(el.Style.FillColor);
  end;
  Result := 0;
end;

{ zrender's normalizeLineDash against the width the line strokes at }
function DashOf(AStyle: TJSONObject; AWidth: Double; out ADash: TTyDoubleArray): Boolean;
var
  d: TJSONData;
  i: Integer;
begin
  ADash := nil;
  Result := True;
  if AStyle = nil then Exit;
  d := AStyle.Find('lineDash');
  if IsNull(d) or not (AWidth > 0) then Exit;
  if d.JSONType = jtString then
  begin
    if d.AsString = 'dashed' then
    begin
      SetLength(ADash, 2);
      ADash[0] := 4 * AWidth;
      ADash[1] := 2 * AWidth;
    end
    else if d.AsString = 'dotted' then
    begin
      SetLength(ADash, 1);
      ADash[0] := AWidth;
    end
    else if d.AsString <> 'solid' then
      Result := False;
  end
  else if d.JSONType = jtArray then
  begin
    SetLength(ADash, d.Count);
    for i := 0 to d.Count - 1 do ADash[i] := FromHex(TJSONArray(d).Strings[i]);
  end;
end;

procedure TAdvChartLabelGuidesTest.CheckStyle(const AWhat: string;
  const AEl: TTyChartElement; AStyle: TJSONObject; const AHostFill, AHostStroke: string;
  AItemColour: TTyChartColor);
var
  s: string;
  c: TTyChartColor;
  w: Double;
  dash: TTyDoubleArray;
  k: Integer;
  cap: TTyLineCap;
  join: TTyLineJoin;
begin
  Inc(FStyled);
  { the ink: as written, or the item's colour (the palette's or a visual's
    is the port's own) }
  s := StrOf(AStyle, 'stroke');
  Inc(FCompared);
  if s = '' then
    Miss(AWhat + ': no stroke upstream')
  else if IsPaletteColour(s) or ((s = AHostFill) and (s <> '')) or ((s = AHostStroke) and (s <> ''))
    or (Pos('rgba(', s) = 1) then
  begin
    if AEl.Style.StrokeColor <> AItemColour then
      Miss(Format('%s: stroke %s is the item''s (%.8x here), %.8x drawn', [AWhat, s,
        AItemColour, AEl.Style.StrokeColor]));
  end
  else if not TyTryParseChartColor(s, c) then
    Miss(AWhat + ': stroke ' + s + ' unread')
  else if c <> AEl.Style.StrokeColor then
    Miss(Format('%s: stroke %s upstream, %.8x here', [AWhat, s, AEl.Style.StrokeColor]));
  { the width: zrender's default 1 }
  s := StrOf(AStyle, 'lineWidth');
  if s <> '' then w := FromHex(s) else w := 1;
  Inc(FCompared);
  if not SameNum(AEl.Style.StrokeWidthLogical, w) then
    Miss(Format('%s: line width %s upstream, %s here', [AWhat, Fmt(w), Fmt(AEl.Style.StrokeWidthLogical)]));
  { the opacity: the style's own, 1 by default }
  s := StrOf(AStyle, 'opacity');
  if s <> '' then w := FromHex(s) else w := 1;
  Inc(FCompared);
  if not SameNum(AEl.Style.Alpha, w) then
    Miss(Format('%s: opacity %s upstream, %s here', [AWhat, Fmt(w), Fmt(AEl.Style.Alpha)]));
  { the dash, normalised against the width }
  if not DashOf(AStyle, AEl.Style.StrokeWidthLogical, dash) then
    Miss(AWhat + ': a dash word the test does not know')
  else
  begin
    Inc(FCompared);
    if Length(dash) <> Length(AEl.Style.DashLogical) then
      Miss(Format('%s: %d dash lengths upstream, %d here', [AWhat, Length(dash), Length(AEl.Style.DashLogical)]))
    else
      for k := 0 to High(dash) do
        if not SameNum(dash[k], AEl.Style.DashLogical[k]) then
          Miss(Format('%s: dash %d %s upstream, %s here', [AWhat, k, Fmt(dash[k]), Fmt(AEl.Style.DashLogical[k])]));
  end;
  s := StrOf(AStyle, 'lineDashOffset');
  if s <> '' then w := FromHex(s) else w := 0;
  Inc(FCompared);
  if not SameNum(AEl.Style.DashOffsetLogical, w) then
    Miss(Format('%s: dash offset %s upstream, %s here', [AWhat, Fmt(w), Fmt(AEl.Style.DashOffsetLogical)]));
  { the cap and the join (zrender's butt / miter), the miter limit (10) }
  s := StrOf(AStyle, 'lineCap');
  if s = 'round' then cap := tlcRound
  else if s = 'square' then cap := tlcSquare
  else cap := tlcButt;
  Inc(FCompared);
  if TyStyleLineCap(AEl.Style) <> cap then
    Miss(Format('%s: cap %s upstream, %d here', [AWhat, s, Ord(TyStyleLineCap(AEl.Style))]));
  s := StrOf(AStyle, 'lineJoin');
  if s = 'round' then join := tljRound
  else if s = 'bevel' then join := tljBevel
  else join := tljMiter;
  Inc(FCompared);
  if TyStyleLineJoin(AEl.Style) <> join then
    Miss(Format('%s: join %s upstream, %d here', [AWhat, s, Ord(TyStyleLineJoin(AEl.Style))]));
  s := StrOf(AStyle, 'miterLimit');
  if s <> '' then w := FromHex(s) else w := 10;
  Inc(FCompared);
  if not SameNum(TyStyleMiterLimit(AEl.Style), w) then
    Miss(Format('%s: miter limit %s upstream, %s here', [AWhat, Fmt(w), Fmt(TyStyleMiterLimit(AEl.Style))]));
end;

procedure TAdvChartLabelGuidesTest.CheckGuides(ACase: TJSONObject);
var
  gs, lines: TJSONArray;
  i, g, lb, hi, k, s, d: Integer;
  gr, ln: TJSONObject;
  el, host, lab: TTyChartElement;
  seen: array of Boolean;
  gh: TTyGuideHost;
  m: TTyMat2D;
  hasM: Boolean;
  want: TTyDoubleArray;
begin
  SetLength(seen, FChart.List.Count);
  gs := ACase.Arrays['guides'];
  for i := 0 to gs.Count - 1 do
  begin
    gr := gs.Objects[i];
    s := gr.Integers['s'];
    d := gr.Integers['d'];
    FName := Format('%s guide s%d d%d', [ACase.Strings['id'], s, d]);
    g := FindGuide(FChart.List, s, d);
    Inc(FCompared);
    if g < 0 then
    begin
      Miss('a label line upstream, none here');
      Continue;
    end;
    seen[g] := True;
    el := FChart.List.Element(g);
    Inc(FGuides);
    Same('ignore', el.Ignore, gr.Booleans['ignore']);
    if el.Ignore then Inc(FHidden);
    CheckPoints('points', el.Shape.Points, gr.Arrays['points']);
    Same('curved', Length(el.Shape.Cmds) > 0, gr.Booleans['curved']);
    CheckStyle('style', el, gr.Objects['style'], StrOf(gr, 'hostFill'),
      StrOf(gr, 'hostStroke'), ItemColour(g));
    { a general line: its z against its host's, the host as upstream
      measured it }
    lb := FindLabel(FChart.List, s, d);
    if lb < 0 then Continue;
    hi := FChart.List.Element(lb).Caption.LmHostPlus1 - 1;
    host := FChart.List.Element(hi);
    Inc(FCompared);
    if Sign(el.Z2 - host.Z2) <> Sign(gr.Integers['z2'] - gr.Integers['hostZ2']) then
      Miss(Format('z2 %d against its host''s %d upstream, %d against %d here',
        [gr.Integers['z2'], gr.Integers['hostZ2'], el.Z2, host.Z2]));
    lines := ACase.Arrays['lines'];
    for k := 0 to lines.Count - 1 do
    begin
      ln := lines.Objects[k];
      if (ln.Integers['s'] <> s) or (ln.Integers['d'] <> d) or IsNull(ln.Find('path')) then Continue;
      if not TyGuideHostOf(host.Caption, gh) then
      begin
        Miss('no host path here');
        Break;
      end;
      Inc(FHosts);
      want := HexArray(ln.Arrays['path']);
      Inc(FCompared);
      if Length(want) <> Length(gh.Data) then
        Miss(Format('host path: %d numbers upstream, %d here', [Length(want), Length(gh.Data)]))
      else
        for hi := 0 to High(want) do
          if not SameNum(want[hi], gh.Data[hi]) then
          begin
            Miss(Format('host path number %d: %s upstream, %s here', [hi, Fmt(want[hi]), Fmt(gh.Data[hi])]));
            Break;
          end;
      hasM := MatOf(ln.Find('targetM'), m);
      Same('host transform', gh.HasM, hasM);
      if hasM and gh.HasM then
        for hi := 0 to 5 do Num('host m' + IntToStr(hi), gh.M[hi], ln.Arrays['targetM'].Strings[hi]);
      { the label's transform as the layout left it }
      lab := FChart.List.Element(lb);
      if lab.Caption.LmHasM and MatOf(ln.Find('labelM'), m) then
        for hi := 0 to 5 do Num('label m' + IntToStr(hi), lab.Caption.LmM[hi], ln.Arrays['labelM'].Strings[hi]);
      Break;
    end;
  end;
  { lines here upstream has none of: never drawn in any state }
  for i := 0 to FChart.List.Count - 1 do
    if (FChart.List.Element(i).Anim.Role = carGuide) and not seen[i] then
    begin
      FName := Format('%s guide s%d d%d', [ACase.Strings['id'],
        FChart.List.Element(i).Anim.Series, FChart.List.Element(i).Anim.Index]);
      Same('a line upstream has not is hidden', FChart.List.Element(i).Ignore, True);
    end;
end;

procedure TAdvChartLabelGuidesTest.CheckHover(ACase: TJSONObject);
var
  hv, gs: TJSONArray;
  h, i, g, cw, ch: Integer;
  pl, gr: TJSONObject;
  el: TTyChartElement;
  back: string;
  rest: TStringList;
begin
  hv := ACase.Arrays['hover'];
  cw := ACase.Integers['W'];
  ch := ACase.Integers['H'];
  { THE ITEM'S COLOUR AT REST: a state lifts the slice, never the line's
    default }
  rest := TStringList.Create;
  try
  for i := 0 to FChart.List.Count - 1 do
    if FChart.List.Element(i).Anim.Role = carGuide then
      rest.Values[Format('%d:%d', [FChart.List.Element(i).Anim.Series,
        FChart.List.Element(i).Anim.Index])] := IntToStr(Int64(ItemColour(i)));
  for h := 0 to hv.Count - 1 do
  begin
    pl := hv.Objects[h].Objects['payload'];
    AssertTrue('dispatch', FChart.DispatchAction(pl.AsJSON));
    FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cw, ch), 96);
    gs := hv.Objects[h].Arrays['guides'];
    for i := 0 to gs.Count - 1 do
    begin
      gr := gs.Objects[i];
      FName := Format('%s %s %d, s%d d%d', [ACase.Strings['id'], pl.Strings['type'],
        pl.Integers['dataIndex'], gr.Integers['s'], gr.Integers['d']]);
      g := FindGuide(FChart.List, gr.Integers['s'], gr.Integers['d']);
      Inc(FCompared);
      if g < 0 then
      begin
        Miss('no line here');
        Continue;
      end;
      el := FChart.List.Element(g);
      Inc(FHover);
      Same('ignore', el.Ignore, gr.Booleans['ignore']);
      if el.Ignore then Continue;
      CheckPoints('points', el.Shape.Points, gr.Arrays['points']);
      CheckStyle('style', el, gr.Objects['style'], '', '', TTyChartColor(StrToInt64Def(
        rest.Values[Format('%d:%d', [el.Anim.Series, el.Anim.Index])], 0)));
    end;
    if pl.Strings['type'] = 'select' then back := 'unselect' else back := 'downplay';
    pl.Strings['type'] := back;
    FChart.DispatchAction(pl.AsJSON);
    if back = 'unselect' then pl.Strings['type'] := 'select' else pl.Strings['type'] := 'highlight';
    FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cw, ch), 96);
  end;
  finally
    rest.Free;
  end;
end;

procedure TAdvChartLabelGuidesTest.RunGroup(const APrefix: array of string; AMin: Integer);
var
  c, k: Integer;
  cs: TJSONObject;
  id: string;
  hit: Boolean;
begin
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    id := cs.Strings['id'];
    hit := False;
    for k := 0 to High(APrefix) do
      if Pos(APrefix[k], id) = 1 then hit := True;
    if not hit then Continue;
    FName := id;
    Show(cs);
    CheckGuides(cs);
    CheckHover(cs);
  end;
  Finish(AMin);
end;

procedure TAdvChartLabelGuidesTest.TestThePiesOwnLineAsUpstream;
begin
  RunGroup(['pie.'], 1500);
  AssertTrue(Format('lines compared (%d)', [FGuides]), FGuides >= 100);
  AssertTrue(Format('hidden lines compared (%d)', [FHidden]), FHidden >= 40);
  AssertTrue(Format('lines under a state compared (%d)', [FHover]), FHover >= 40);
end;

procedure TAdvChartLabelGuidesTest.TestTheFunnelsOwnLineAsUpstream;
begin
  RunGroup(['funnel.'], 200);
  AssertTrue(Format('lines compared (%d)', [FGuides]), FGuides >= 18);
  AssertTrue(Format('hidden lines compared (%d)', [FHidden]), FHidden >= 6);
end;

procedure TAdvChartLabelGuidesTest.TestTheOtherSeriesLinesAsUpstream;
begin
  RunGroup(['heatmap', 'pictorial', 'graph', 'tree', 'sunburst', 'sankey',
    'polarbar', 'calendar'], 2000);
  AssertTrue(Format('lines compared (%d)', [FGuides]), FGuides >= 150);
  AssertTrue(Format('host paths compared (%d)', [FHosts]), FHosts >= 150);
end;

{ HAND-WRITTEN: a pie's line takes the slice's colour where its lineStyle
  says none, and its own where it does; the pen's cap and join reach the
  painter (a round cap inks past the end of a butt one) }
procedure TAdvChartLabelGuidesTest.TestAPieLineInkAndPen;
var
  g: Integer;
  el: TTyChartElement;
begin
  FChart.Option := '{}';
  FChart.Option := '{"animation":false,"series":[{"type":"pie","radius":"40%",'
    + '"labelLine":{"lineStyle":{"color":"#123456","width":4,"cap":"round","join":"bevel"}},'
    + '"data":[{"name":"a","value":3},{"name":"b","value":5,'
    + '"labelLine":{"lineStyle":{"color":"#abcdef","cap":"square"}}}]}]}';
  FChart.SetBounds(0, 0, 600, 400);
  FBmp.SetSize(600, 400);
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, 600, 400), 96);
  g := FindGuide(FChart.List, 0, 0);
  AssertTrue('a line for a', g >= 0);
  el := FChart.List.Element(g);
  AssertEquals('a: the series'' colour', $FF123456, el.Style.StrokeColor);
  AssertEquals('a: width 4', 4.0, el.Style.StrokeWidthLogical, 0);
  AssertEquals('a: round', Ord(tlcRound), Ord(TyStyleLineCap(el.Style)));
  AssertEquals('a: bevel', Ord(tljBevel), Ord(TyStyleLineJoin(el.Style)));
  g := FindGuide(FChart.List, 0, 1);
  AssertTrue('a line for b', g >= 0);
  el := FChart.List.Element(g);
  AssertEquals('b: its own colour', $FFABCDEF, el.Style.StrokeColor);
  AssertEquals('b: the series'' width', 4.0, el.Style.StrokeWidthLogical, 0);
  AssertEquals('b: square', Ord(tlcSquare), Ord(TyStyleLineCap(el.Style)));
end;

{ A LINE'S END LABEL IN ITS POLYLINE'S STATES (endlabel-states.js): there
  where any state shows it, hidden at rest unless the normal one does, a
  state's show (the normal one by default) and colour under highlight }
procedure TAdvChartLabelGuidesTest.TestEndLabelStatesAsUpstream;
var
  root: TJSONData;
  sl: TStringList;
  cs, steps: TJSONArray;
  c, s, k, idx, n: Integer;
  cse, st, rest: TJSONObject;
  col: TTyChartColor;

  function EndIdx: Integer;
  var i: Integer;
  begin
    for i := 0 to FChart.List.Count - 1 do
      if FChart.List.Element(i).Anim.Role = carEndLabel then Exit(i);
    Result := -1;
  end;

begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixtureDir + 'advchart-endlabel-states.json');
    root := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  n := 0;
  try
    cs := TJSONObject(root).Arrays['cases'];
    for c := 0 to cs.Count - 1 do
    begin
      cse := cs.Objects[c];
      FChart.Option := '{}';
      FChart.Option := cse.Objects['option'].AsJSON;
      FChart.SetBounds(0, 0, cse.Integers['W'], cse.Integers['H']);
      FBmp.SetSize(cse.Integers['W'], cse.Integers['H']);
      FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cse.Integers['W'], cse.Integers['H']), 96);
      rest := cse.Objects['rest'];
      FName := cse.Strings['id'] + ' at rest';
      idx := EndIdx;
      Same('there', idx >= 0, rest.Booleans['exists']);
      if idx < 0 then Continue;
      Same('hidden', FChart.List.Element(idx).Ignore, rest.Booleans['ignore']);
      steps := cse.Arrays['steps'];
      for s := 0 to steps.Count - 1 do
      begin
        st := steps.Objects[s];
        FName := Format('%s step %d', [cse.Strings['id'], s]);
        AssertTrue('dispatch', FChart.DispatchAction(st.Objects['payload'].AsJSON));
        FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cse.Integers['W'], cse.Integers['H']), 96);
        idx := EndIdx;
        Same('there', idx >= 0, True);
        if idx < 0 then Continue;
        Same('hidden', FChart.List.Element(idx).Ignore, st.Booleans['ignore']);
        Inc(n);
        if not IsNull(st.Find('fill')) then
        begin
          Inc(FCompared);
          if not TyTryParseChartColor(st.Strings['fill'], col) then Miss('fill unread')
          else if col <> FChart.List.Element(idx).Caption.Colour then
            Miss(Format('fill %s upstream, %.8x here', [st.Strings['fill'],
              FChart.List.Element(idx).Caption.Colour]));
        end;
      end;
    end;
  finally
    root.Free;
  end;
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
  AssertTrue(Format('states compared (%d)', [n]), n >= 8);
  if k = 0 then ;
end;

{ THE PEN'S ENDS AND CORNERS REACH THE PAINTER: a thick open polyline
  inks past its ends with a round or a square cap and not with a butt one;
  a bevel join inks less than a miter at a sharp corner }
procedure TAdvChartLabelGuidesTest.TestThePenReachesThePainter;

  function Ink(ACap, AJoin: Byte): Integer;
  var
    b: TBGRABitmap;
    p: TTyPainter;
    el: TTyChartElement;
    x, y: Integer;
  begin
    b := TBGRABitmap.Create(200, 140, BGRA(255, 255, 255, 255));
    try
      el := TyChartElement(TyShapePolyline([TyPointF(50, 110), TyPointF(100, 20),
        TyPointF(150, 110)]));
      el.Style.HasFill := False;
      el.Style.StrokeColor := $FF000000;
      el.Style.StrokeWidthLogical := 16;
      el.Style.LineCap := ACap;
      el.Style.LineJoin := AJoin;
      p := TTyPainter.Create;
      try
        p.BeginPaintOn(nil, Rect(0, 0, 200, 140), 96, b);
        TyRenderElement(p, el);
        p.EndPaint;
      finally
        p.Free;
      end;
      { the ink: every pixel's darkness }
      Result := 0;
      for y := 0 to b.Height - 1 do
        for x := 0 to b.Width - 1 do
          Inc(Result, 255 - b.GetPixel(x, y).red);
    finally
      b.Free;
    end;
  end;

var butt, rnd, square, miter, bevel: Integer;
begin
  butt := Ink(cTyCapButt, cTyJoinMiter);
  rnd := Ink(cTyCapRound, cTyJoinMiter);
  square := Ink(cTyCapSquare, cTyJoinMiter);
  AssertTrue(Format('a round cap inks past a butt one (%d, %d)', [rnd, butt]), rnd > butt + 100 * 255);
  AssertTrue(Format('a square cap inks past a round one (%d, %d)', [square, rnd]), square > rnd + 20 * 255);
  miter := Ink(cTyCapButt, cTyJoinMiter);
  bevel := Ink(cTyCapButt, cTyJoinBevel);
  AssertTrue(Format('a bevel join inks less than a miter (%d, %d)', [bevel, miter]), bevel < miter - 20 * 255);
end;

{ ---------------- plumbing ---------------- }

procedure TAdvChartLabelGuidesTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TLgsProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
  AssertTrue('the fixture is where the suite expects it',
    FileExists(FixtureDir + 'advchart-label-guides.json'));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixtureDir + 'advchart-label-guides.json');
    FRoot := GetJSON(sl.Text);
    sl.LoadFromFile(FixtureDir + 'advchart-text-style.json');
    FMeasure := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  FBad := 0;
  FCompared := 0;
  FReport := '';
  FGuides := 0;
  FHidden := 0;
  FStyled := 0;
  FHover := 0;
  FHosts := 0;
end;

procedure TAdvChartLabelGuidesTest.TearDown;
begin
  FreeAndNil(FRoot);
  FreeAndNil(FMeasure);
  FreeAndNil(FBmp);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

initialization
  RegisterTest(TAdvChartLabelGuidesTest);
end.
