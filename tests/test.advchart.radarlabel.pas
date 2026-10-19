unit test.advchart.radarlabel;
{$mode objfpc}{$H+}
{ A RADAR SERIES' DATA LABELS, held to ECharts 6.1. [R2-A b1, spec 218]

  tools/advchart-oracle/radar-label.js runs the real dist and records every
  point label RadarView hangs on a symbol -- its words, where the computed
  transform puts it, its turn, the alignment and the painted ink and halo,
  the symbol it hangs on -- with each row's ring (a missing value is a point
  at the centre), the labels under a highlight, and the fade of an enter
  and of an update.

  The control renders each option (text measured with zrender's SSR width
  table) and every label is found by its datum and its point (the host's
  LabelSub) and compared bit for bit; an empty text upstream (NaN, no
  formatter) paints nothing and has no label here. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.StyleModel,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Color, tyControls.AdvChart.Anim, tyControls.AdvChart.AnimView,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TRlProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
    function Frame: TTyPaintList;
  end;

  TAdvChartRadarLabelOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TRlProbe;
    FRoot, FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared, FSeen, FEmpty, FGuides: Integer;
    FReport, FName: string;
    procedure NewChart(AAnimate: Boolean);
    procedure Miss(const AWhat: string);
    procedure Num(const AWhat: string; AGot: Double; const AHex: string);
    procedure Str(const AWhat, AGot, AWant: string);
    procedure Same(const AWhat: string; AGot, AWant: Boolean);
    procedure Ink(const AWhat: string; AGot: TTyChartColor; AWant: TJSONData;
      AOutside: Boolean = False);
    procedure Show(ACase: TJSONObject);
    function LabelAt(AList: TTyPaintList; AS_, AD, ADim: Integer;
      out AEl: TTyChartElement): Boolean;
    function GuideMatches(AS_, AD: Integer; AGuide: TJSONObject): Boolean;
    procedure Finish(AMin: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheLabelsAsUpstream;
    procedure TestTheRingsAsUpstream;
    procedure TestTheHoverAsUpstream;
    procedure TestTheFadeAsUpstream;
  end;

implementation

const
  cW = 600;
  cH = 400;

function TRlProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TRlProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TRlProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function TRlProbe.Frame: TTyPaintList;
begin
  Result := AnimFrame;
end;

{ ---------------- numbers ---------------- }

function FromHex(const AHex: string): Double;
var q: QWord;
begin
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

function IsNull(D: TJSONData): Boolean;
begin
  Result := (D = nil) or (D.JSONType = jtNull);
end;

function AlignName(AH: TTyTextAnchorH): string;
begin
  case AH of
    tahCentre: Result := 'center';
    tahRight: Result := 'right';
  else
    Result := 'left';
  end;
end;

function VAlignName(AV: TTyTextAnchorV): string;
begin
  case AV of
    tavMiddle: Result := 'middle';
    tavBottom: Result := 'bottom';
  else
    Result := 'top';
  end;
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-radar-label.json';
end;

{ ---------------- plumbing ---------------- }

procedure TAdvChartRadarLabelOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := GetJSON(sl.Text);
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
      + 'advchart-text-style.json');
    FMeasure := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FChart := nil;
  FBad := 0;
  FCompared := 0;
  FSeen := 0;
  FEmpty := 0;
  FGuides := 0;
  FReport := '';
end;

procedure TAdvChartRadarLabelOracleTest.TearDown;
begin
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FRoot);
  FreeAndNil(FMeasure);
  FreeAndNil(FBmp);
  inherited TearDown;
end;

procedure TAdvChartRadarLabelOracleTest.NewChart(AAnimate: Boolean);
begin
  FreeAndNil(FChart);
  FChart := TRlProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  if AAnimate then FChart.AnimationMode := camAlways
  else FChart.AnimationMode := camOff;
  FChart.SetBounds(0, 0, cW, cH);
end;

procedure TAdvChartRadarLabelOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartRadarLabelOracleTest.Num(const AWhat: string; AGot: Double;
  const AHex: string);
begin
  Inc(FCompared);
  if Bits(AGot) <> Bits(FromHex(AHex)) then
    Miss(Format('%s %s upstream, %s here', [AWhat, Fmt(FromHex(AHex)), Fmt(AGot)]));
end;

procedure TAdvChartRadarLabelOracleTest.Str(const AWhat, AGot, AWant: string);
begin
  Inc(FCompared);
  if AGot <> AWant then Miss(Format('%s "%s" upstream, "%s" here', [AWhat, AWant, AGot]));
end;

procedure TAdvChartRadarLabelOracleTest.Same(const AWhat: string; AGot, AWant: Boolean);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Miss(Format('%s %s upstream, %s here', [AWhat, BoolToStr(AWant, True), BoolToStr(AGot, True)]));
end;

{ a painted colour: the string upstream's TSpan holds, null for none }
procedure TAdvChartRadarLabelOracleTest.Ink(const AWhat: string; AGot: TTyChartColor;
  AWant: TJSONData; AOutside: Boolean);
var c: TTyChartColor;
begin
  Inc(FCompared);
  if IsNull(AWant) then
  begin
    if (AGot shr 24) <> 0 then Miss(Format('%s none upstream, $%.8x here', [AWhat, AGot]));
    Exit;
  end;
  if not TyTryParseChartColor(AWant.AsString, c) then
  begin
    Miss(AWhat + ' unparsed ' + AWant.AsString);
    Exit;
  end;
  { THE THEME'S OWN OUTSIDE INK is the port's voice for upstream's
    automatic #333 (test.advchart.insidelabel) }
  if AOutside and (c = TTyChartColor($FF333333)) then
    c := TTyChartColor(FCtl.Model.ResolveStyle('TyAdvChartLabel', '', []).TextColor);
  if c <> AGot then
    Miss(Format('%s %s ($%.8x) upstream, $%.8x here', [AWhat, AWant.AsString, c, AGot]));
end;

procedure TAdvChartRadarLabelOracleTest.Show(ACase: TJSONObject);
begin
  NewChart(False);
  FChart.Option := ACase.Objects['option'].AsJSON;
  AssertEquals(ACase.Strings['id'] + ': the option parses', '', FChart.OptionError);
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cW, cH), 96);
end;

{ the label of series AS_, row AD, on the point of spoke ADim: a caption
  whose host carries LabelSub ADim + 1 }
function TAdvChartRadarLabelOracleTest.LabelAt(AList: TTyPaintList; AS_, AD,
  ADim: Integer; out AEl: TTyChartElement): Boolean;
var
  i, h: Integer;
  el: TTyChartElement;
begin
  Result := False;
  AEl := Default(TTyChartElement);
  for i := 0 to AList.Count - 1 do
  begin
    el := AList.Element(i);
    if (el.Anim.Role <> carLabel) or (el.Datum.SeriesIndex <> AS_)
      or (el.Datum.DataIndex <> AD) then Continue;
    h := el.Caption.LmHostPlus1 - 1;
    if (h < 0) or (h >= AList.Count) then Continue;
    if AList.Element(h).Caption.LabelSub <> ADim + 1 then Continue;
    AEl := el;
    Exit(True);
  end;
end;

{ a label line of the datum (AS_, AD) at exactly the recorded points, and
  as shown or hidden }
function TAdvChartRadarLabelOracleTest.GuideMatches(AS_, AD: Integer;
  AGuide: TJSONObject): Boolean;
var
  i, k: Integer;
  el: TTyChartElement;
  pts: TJSONArray;
  ok: Boolean;
begin
  Result := False;
  pts := AGuide.Arrays['points'];
  for i := 0 to FChart.List.Count - 1 do
  begin
    el := FChart.List.Element(i);
    if (el.Anim.Role <> carGuide) or (el.Anim.Series <> AS_) or (el.Anim.Index <> AD) then Continue;
    if (Length(el.Shape.Points) <> pts.Count) or (el.Ignore <> AGuide.Booleans['ignore']) then Continue;
    ok := True;
    for k := 0 to pts.Count - 1 do
      if (Bits(el.Shape.Points[k].X) <> Bits(FromHex(TJSONArray(pts.Items[k]).Strings[0])))
        or (Bits(el.Shape.Points[k].Y) <> Bits(FromHex(TJSONArray(pts.Items[k]).Strings[1]))) then
        ok := False;
    if ok then Exit(True);
  end;
end;

procedure TAdvChartRadarLabelOracleTest.Finish(AMin: Integer);
begin
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
  AssertTrue(Format('enough was compared (%d)', [FCompared]), FCompared > AMin);
end;

{ ---------------- the cases ---------------- }

procedure TAdvChartRadarLabelOracleTest.TestTheLabelsAsUpstream;
var
  cases, labs: TJSONArray;
  c, i, h: Integer;
  cs, lb: TJSONObject;
  el, host: TTyChartElement;
  shown: Integer;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    Show(cs);
    labs := cs.Arrays['labels'];
    shown := 0;
    for i := 0 to labs.Count - 1 do
    begin
      lb := labs.Objects[i];
      FName := Format('%s s%d d%d dim%d "%s"', [cs.Strings['id'], lb.Integers['s'],
        lb.Integers['d'], lb.Integers['dim'], lb.Strings['text']]);
      { AN EMPTY TEXT PAINTS NOTHING upstream; here there is no label }
      if lb.Strings['text'] = '' then
      begin
        Inc(FEmpty);
        Inc(FCompared);
        if LabelAt(FChart.List, lb.Integers['s'], lb.Integers['d'], lb.Integers['dim'], el) then
          Miss('an empty text upstream, a label here');
        Continue;
      end;
      Inc(FCompared);
      if not LabelAt(FChart.List, lb.Integers['s'], lb.Integers['d'], lb.Integers['dim'], el) then
      begin
        Miss('a label upstream, none here');
        Continue;
      end;
      Inc(FSeen);
      Str('text', el.Caption.Text, lb.Strings['text']);
      Same('ignore', el.Ignore, lb.Booleans['ignore']);
      Num('x', el.Caption.X, lb.Strings['x']);
      Num('y', el.Caption.Y, lb.Strings['y']);
      Num('rotation', el.Caption.RotationRad, lb.Strings['rotation']);
      Str('align', AlignName(el.Caption.AnchorH), lb.Strings['align']);
      Str('verticalAlign', VAlignName(el.Caption.AnchorV), lb.Strings['verticalAlign']);
      { an ignored label is painted nothing upstream: no ink to compare }
      if not lb.Booleans['ignore'] then
      begin
        Ink('fill', el.Caption.Colour, lb.Find('fill'), not el.Caption.LmInkInside);
        if IsNull(lb.Find('stroke')) then
        begin
          Inc(FCompared);
          if (el.Caption.StrokeWidthLogical > 0) and ((el.Caption.StrokeColour shr 24) <> 0) then
            Miss('no halo upstream, one here');
        end
        else
        begin
          Ink('stroke', el.Caption.StrokeColour, lb.Find('stroke'));
          Num('lineWidth', el.Caption.StrokeWidthLogical, lb.Strings['lineWidth']);
        end;
      end;
      Num('opacity', el.Style.Alpha, lb.Strings['opacity']);
      { the symbol it hangs on }
      h := el.Caption.LmHostPlus1 - 1;
      host := FChart.List.Element(h);
      Num('host x', host.Caption.LgG[5], lb.Strings['hostX']);
      Num('host y', host.Caption.LgG[6], lb.Strings['hostY']);
      { ITS LABEL LINE, routed from the symbol: one of the datum's lines
        with these very points }
      if not IsNull(lb.Find('guide')) then
      begin
        Inc(FCompared);
        if not GuideMatches(lb.Integers['s'], lb.Integers['d'], lb.Objects['guide']) then
          Miss('its label line upstream, none with those points here')
        else
          Inc(FGuides);
      end;
    end;
    { and no label here that upstream has not }
    FName := cs.Strings['id'];
    h := 0;
    for i := 0 to labs.Count - 1 do
      if labs.Objects[i].Strings['text'] <> '' then Inc(h);
    shown := 0;
    for i := 0 to FChart.List.Count - 1 do
      if FChart.List.Element(i).Anim.Role = carLabel then Inc(shown);
    Inc(FCompared);
    if shown <> h then Miss(Format('%d labels upstream, %d here', [h, shown]));
  end;
  Finish(1500);
  AssertTrue(Format('labels compared (%d)', [FSeen]), FSeen >= 110);
  AssertTrue(Format('empty texts compared (%d)', [FEmpty]), FEmpty >= 3);
  AssertTrue(Format('label lines compared (%d)', [FGuides]), FGuides >= 5);
end;

procedure TAdvChartRadarLabelOracleTest.TestTheRingsAsUpstream;
var
  cases, rows, pts: TJSONArray;
  c, r, i, k, n: Integer;
  cs, rw: TJSONObject;
  el: TTyChartElement;
  found: Boolean;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  n := 0;
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    Show(cs);
    rows := cs.Arrays['rows'];
    for r := 0 to rows.Count - 1 do
    begin
      rw := rows.Objects[r];
      FName := Format('%s ring s%d d%d', [cs.Strings['id'], rw.Integers['s'], rw.Integers['d']]);
      pts := rw.Arrays['points'];
      found := False;
      for i := 0 to FChart.List.Count - 1 do
      begin
        el := FChart.List.Element(i);
        if (el.Anim.Role <> carRadarLine) or (el.Datum.SeriesIndex <> rw.Integers['s'])
          or (el.Datum.DataIndex <> rw.Integers['d']) then Continue;
        found := True;
        Inc(n);
        Inc(FCompared);
        if Length(el.Shape.Points) <> pts.Count then
          Miss(Format('%d points upstream, %d here', [pts.Count, Length(el.Shape.Points)]))
        else
          for k := 0 to pts.Count - 1 do
          begin
            Num('x' + IntToStr(k), el.Shape.Points[k].X, TJSONArray(pts.Items[k]).Strings[0]);
            Num('y' + IntToStr(k), el.Shape.Points[k].Y, TJSONArray(pts.Items[k]).Strings[1]);
          end;
        Break;
      end;
      Inc(FCompared);
      if not found then Miss('a ring upstream, none here');
    end;
  end;
  Finish(300);
  AssertTrue(Format('rings compared (%d)', [n]), n >= 20);
end;

{ the labels under a highlight: shown or not, and their ink }
procedure TAdvChartRadarLabelOracleTest.TestTheHoverAsUpstream;
var
  cases, labs: TJSONArray;
  c, i, n: Integer;
  cs, lb, pl: TJSONObject;
  el: TTyChartElement;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  n := 0;
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    if IsNull(cs.Find('hover')) then Continue;
    Show(cs);
    pl := cs.Objects['hover'].Objects['payload'];
    AssertTrue('highlight', FChart.DispatchAction(pl.AsJSON));
    FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cW, cH), 96);
    labs := cs.Objects['hover'].Arrays['labels'];
    for i := 0 to labs.Count - 1 do
    begin
      lb := labs.Objects[i];
      FName := Format('%s highlight s%d d%d dim%d', [cs.Strings['id'], lb.Integers['s'],
        lb.Integers['d'], lb.Integers['dim']]);
      Inc(FCompared);
      if not LabelAt(FChart.List, lb.Integers['s'], lb.Integers['d'], lb.Integers['dim'], el) then
      begin
        Miss('a label upstream, none here');
        Continue;
      end;
      Inc(n);
      Same('ignore', el.Ignore, lb.Booleans['ignore']);
      if lb.Booleans['ignore'] then Continue;
      Ink('fill', el.Caption.Colour, lb.Find('fill'), not el.Caption.LmInkInside);
      if IsNull(lb.Find('stroke')) then
      begin
        Inc(FCompared);
        if (el.Caption.StrokeWidthLogical > 0) and ((el.Caption.StrokeColour shr 24) <> 0) then
          Miss('no halo upstream, one here');
      end
      else
      begin
        Ink('stroke', el.Caption.StrokeColour, lb.Find('stroke'));
        Num('lineWidth', el.Caption.StrokeWidthLogical, lb.Strings['lineWidth']);
      end;
    end;
  end;
  Finish(60);
  AssertTrue(Format('hovered labels compared (%d)', [n]), n >= 20);
end;

{ the enter fades every label in from nought; an update fades them in again
  -- RadarView makes its symbols anew, labels and all }
procedure TAdvChartRadarLabelOracleTest.TestTheFadeAsUpstream;
const
  cT0 = 1000000;
var
  fade, sm: TJSONObject;
  samples, op: TJSONArray;
  i, k, d, dim, h: Integer;
  el: TTyChartElement;
  base: Double;
begin
  fade := TJSONObject(FRoot).Objects['fade'];
  NewChart(True);
  FChart.AnimNow := cT0;
  FChart.Option := fade.Objects['option'].AsJSON;
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cW, cH), 96);
  samples := fade.Arrays['samples'];
  for i := 0 to samples.Count - 1 do
  begin
    sm := samples.Objects[i];
    if (sm.Strings['phase'] = 'update') and (sm.Integers['t'] = 0) then
    begin
      FChart.AnimTick(cT0 + 5000);
      FChart.AnimNow := cT0 + 5000;
      FChart.SetOption(fade.Objects['update'].AsJSON);
      FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cW, cH), 96);
    end;
    if sm.Strings['phase'] = 'update' then base := cT0 + 5000 else base := cT0;
    { t 0 is the frame setOption flushed: every new clip steps there }
    FChart.AnimTick(base + sm.Integers['t']);
    op := sm.Arrays['opacity'];
    for k := 0 to op.Count - 1 do
    begin
      { two rows of three, in order }
      d := k div 3;
      dim := k mod 3;
      FName := Format('%s t%d d%d dim%d', [sm.Strings['phase'], sm.Integers['t'], d, dim]);
      Inc(FCompared);
      if not LabelAt(FChart.Frame, 0, d, dim, el) then
      begin
        Miss('a label upstream, none in the frame');
        Continue;
      end;
      { a frame draws a label faded to nought as no words at all }
      if el.Caption.Text = '' then Num('opacity', 0, op.Strings[k])
      else Num('opacity', el.Style.Alpha, op.Strings[k]);
      if sm.Strings['phase'] = 'enter' then
      begin
        Num('x', el.Caption.X, sm.Arrays['x'].Strings[k]);
        Num('y', el.Caption.Y, sm.Arrays['y'].Strings[k]);
      end
      else
      begin
        { [R2-I2] an update slides the symbol from its old point and the
          label rides it: carried by the symbol's move (a sum, not
          upstream's product of transforms -- within 1e-9) }
        Inc(FCompared);
        if Abs(el.Caption.X - FromHex(sm.Arrays['x'].Strings[k])) > 1e-9 then
          Miss(Format('x %s upstream, %s here', [Fmt(FromHex(sm.Arrays['x'].Strings[k])), Fmt(el.Caption.X)]));
        Inc(FCompared);
        if Abs(el.Caption.Y - FromHex(sm.Arrays['y'].Strings[k])) > 1e-9 then
          Miss(Format('y %s upstream, %s here', [Fmt(FromHex(sm.Arrays['y'].Strings[k])), Fmt(el.Caption.Y)]));
      end;
      { [R2-I2] the symbol it hangs on, where the frame draws it }
      h := el.Caption.LmHostPlus1 - 1;
      Num('host x', FChart.Frame.Element(h).Caption.LgG[5], sm.Arrays['hostX'].Strings[k]);
      Num('host y', FChart.Frame.Element(h).Caption.LgG[6], sm.Arrays['hostY'].Strings[k]);
    end;
  end;
  Finish(150);
end;

initialization
  RegisterTest(TAdvChartRadarLabelOracleTest);
end.
