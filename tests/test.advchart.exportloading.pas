unit test.advchart.exportloading;
{$mode objfpc}{$H+}
{ EXPORT AND LOADING, held to upstream. [Batch 106, B11]

  Against tests/fixtures/advchart-export-loading.json
  (tools/advchart-oracle/export-loading.js):
    - every loading case: the mask, the label rect, the arc's centre and
      radius, the text's anchor and the text width the layout used, BIT FOR
      BIT, with zrender's own width table as the measurer; the arc's first
      angles; the text, the size and the colours the cfg wrote;
    - every spinner timeline: the arc's two angles after each step, BIT FOR
      BIT, and the clips running, hides and shows between the steps;
    - every export case: the views the export drew (excludeComponents), the
      image size at the pixel ratio, and the background the chain chose --
      the skin's ground where upstream's is 'transparent', the alpha a
      transparent one leaves, a colour, the opaque black a value the canvas
      cannot take leaves, a gradient.
  And by hand: an excluded view is absent in the pixels; the window comes
  back after an export at another size; the encodings; the mask, the text
  and the arc in the pixels, in the theme's colours; camOff holds the
  spinner. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes, base64,
     tyControls.Controller, tyControls.Types, tyControls.FontUnits,
     tyControls.Painter,
     tyControls.StrConsts,
     tyControls.AdvChart.Types, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Paint, tyControls.AdvChart.Measure,
     tyControls.AdvChart.Color,
     tyControls.AdvChart.Export, tyControls.AdvChart.Loading,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TElProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Hover(AX, AY: Integer);
    function Views: TTyChartViews;
    function Geo(out AGeo: TTyLoadingGeometry): Boolean;
    function Cfg: TTyLoadingCfg;
    function Arc(out AStart, AEnd: Double): Boolean;
    function Clips: Integer;
    function List: TTyPaintList;
    procedure RenderWindow(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TAdvChartExportLoadingTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TElProbe;
    FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared: Integer;
    FReport: string;
    procedure Miss(const AWhere: string);
    procedure Verdict(const AWhat: string);
    procedure NewChart(AW, AH: Integer);
    function Draw: TBGRABitmap;
    procedure Load(const AOption: string);
    procedure ShowCall(ACall: TJSONObject);
    procedure CheckHex(const AWhere, AHex: string; AValue: Double);
    procedure RunLoadingCase(C: TJSONObject);
    procedure RunTimeline(T: TJSONObject);
    function ExportCase(const AId: string): TJSONObject;
    function BarCentre(ASeries, ARow: Integer): TPoint;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestLoadingGeometryAsUpstream;
    procedure TestSpinnerTimelinesAsUpstream;
    procedure TestExportViewsAsUpstream;
    procedure TestExportBackgroundAsUpstream;
    procedure TestExcludedViewsAreAbsentInThePixels;
    procedure TestExportPutsTheWindowBack;
    procedure TestExportLeavesTheHoverOut;
    procedure TestEncodings;
    procedure TestLoadingPixelsInTheThemesColours;
    procedure TestLoadingCfgColoursAndHide;
    procedure TestLoadingIsInTheExport;
    procedure TestSpinnerHeldUnderCamOff;
    procedure TestOptionsThatAreNotJson;
    procedure TestExportAtTheControlsPPI;
    procedure TestLoadingOnTheCachedPath;
  end;

implementation

const
  cW = 400;
  cH = 300;
  OPT_PLAIN = '{"animation":false,"xAxis":{"type":"category","data":["a","b","c"]},'
    + '"yAxis":{"type":"value"},"series":[{"type":"bar","data":[3,5,2]}]}';

var
  GFix: TJSONData = nil;

function Fix: TJSONObject;
var sl: TStringList;
begin
  if GFix = nil then
  begin
    sl := TStringList.Create;
    try
      sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
        + 'advchart-export-loading.json');
      GFix := GetJSON(sl.Text);
    finally
      sl.Free;
    end;
  end;
  Result := TJSONObject(GFix);
end;

function T0: Double;
begin
  Result := Fix.Objects['clock'].Floats['T0'];
end;

function Hex(A: Double): string;
var q: QWord;
begin
  Move(A, q, SizeOf(q));
  Result := LowerCase(IntToHex(q, 16));
end;

function Fmt(A: Double): string;
begin
  Result := FloatToStrF(A, ffGeneral, 17, 0, DefaultFormatSettings);
end;

function PixelNear(const A: TBGRAPixel; R, G, B, AA, ATol: Integer): Boolean;
begin
  Result := (Abs(A.red - R) <= ATol) and (Abs(A.green - G) <= ATol)
    and (Abs(A.blue - B) <= ATol) and (Abs(A.alpha - AA) <= ATol);
end;

function PixText(const A: TBGRAPixel): string;
begin
  Result := Format('(%d,%d,%d,%d)', [A.red, A.green, A.blue, A.alpha]);
end;

function DiffCount(A, B: TBGRABitmap): Integer;
var x, y: Integer; p, q: TBGRAPixel;
begin
  if (A.Width <> B.Width) or (A.Height <> B.Height) then Exit(MaxInt);
  Result := 0;
  for y := 0 to A.Height - 1 do
    for x := 0 to A.Width - 1 do
    begin
      p := A.GetPixel(x, y);
      q := B.GetPixel(x, y);
      if (p.red <> q.red) or (p.green <> q.green) or (p.blue <> q.blue)
        or (p.alpha <> q.alpha) then Inc(Result);
    end;
end;

{ AColour filled over APixel by the painter, as the chart's mask is }
function Over(const APixel: TBGRAPixel; AColour: TTyColor): TBGRAPixel;
var
  bmp: TBGRABitmap;
  P: TTyPainter;
begin
  bmp := TBGRABitmap.Create(4, 4, APixel);
  P := TTyPainter.Create;
  try
    P.BeginPaintOn(nil, Rect(0, 0, 4, 4), 96, bmp);
    P.BeginPath;
    P.RectPath(0, 0, 4, 4);
    P.FillPath(AColour);
    P.EndPaint;
    Result := bmp.GetPixel(1, 1);
  finally
    P.Free;
    bmp.Free;
  end;
end;

{ ==================== the probe ==================== }

function TElProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TElProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TElProbe.Hover(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

function TElProbe.Views: TTyChartViews;
begin
  Result := LastViewsDrawn;
end;

function TElProbe.Geo(out AGeo: TTyLoadingGeometry): Boolean;
begin
  Result := LoadingGeometry(AGeo);
end;

function TElProbe.Cfg: TTyLoadingCfg;
begin
  Result := LoadingCfg;
end;

function TElProbe.Arc(out AStart, AEnd: Double): Boolean;
begin
  Result := LoadingArcAngles(AStart, AEnd);
end;

function TElProbe.Clips: Integer;
begin
  Result := LoadingClipCount;
end;

function TElProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

procedure TElProbe.RenderWindow(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderCached(ACanvas, ARect, APPI);
end;

{ ==================== plumbing ==================== }

procedure TAdvChartExportLoadingTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := nil;
  sl := TStringList.Create;
  try
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
      + 'advchart-text-style.json');
    FMeasure := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FChart := nil;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartExportLoadingTest.TearDown;
begin
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FBmp);
  FreeAndNil(FMeasure);
  inherited TearDown;
end;

procedure TAdvChartExportLoadingTest.Miss(const AWhere: string);
begin
  Inc(FBad);
  if FBad <= 40 then FReport := FReport + LineEnding + '  ' + AWhere;
end;

procedure TAdvChartExportLoadingTest.Verdict(const AWhat: string);
begin
  AssertTrue(AWhat + ': ' + IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' differ from upstream:' + FReport, FBad = 0);
  AssertTrue(AWhat + ': something was compared', FCompared > 0);
end;

procedure TAdvChartExportLoadingTest.NewChart(AW, AH: Integer);
begin
  FreeAndNil(FChart);
  FChart := TElProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  { the tests render at 96: an export with no ratio is laid out at the
    control's own PPI, which is the screen's }
  FChart.Font.PixelsPerInch := 96;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  FChart.AnimNow := T0;
  FChart.SetBounds(0, 0, AW, AH);
end;

function TAdvChartExportLoadingTest.Draw: TBGRABitmap;
begin
  FreeAndNil(FBmp);
  FBmp := TBGRABitmap.Create(FChart.Width, FChart.Height, BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, FChart.Width, FChart.Height), 96);
  Result := FBmp;
end;

procedure TAdvChartExportLoadingTest.Load(const AOption: string);
begin
  FChart.Option := AOption;
  AssertEquals('the option parses', '', FChart.OptionError);
  Draw;
end;

procedure TAdvChartExportLoadingTest.ShowCall(ACall: TJSONObject);
var
  name, cfg: TJSONData;
  cfgText: string;
begin
  name := ACall.Find('name');
  cfg := ACall.Find('cfg');
  cfgText := '';
  if cfg <> nil then cfgText := cfg.AsJSON;
  if name = nil then FChart.ShowLoading(cfgText)
  else if name is TJSONObject then FChart.ShowLoading(name.AsJSON)
  else FChart.ShowLoading(name.AsString, cfgText);
end;

procedure TAdvChartExportLoadingTest.CheckHex(const AWhere, AHex: string;
  AValue: Double);
begin
  Inc(FCompared);
  if Hex(AValue) <> AHex then Miss(AWhere + ': ' + Fmt(AValue) + ' (' + Hex(AValue)
    + '), upstream ' + AHex);
end;

function TAdvChartExportLoadingTest.ExportCase(const AId: string): TJSONObject;
var arr: TJSONArray; i: Integer;
begin
  arr := Fix.Arrays['exports'];
  for i := 0 to arr.Count - 1 do
    if arr.Objects[i].Strings['id'] = AId then Exit(arr.Objects[i]);
  Result := nil;
  Fail('no export case ' + AId);
end;

function TAdvChartExportLoadingTest.BarCentre(ASeries, ARow: Integer): TPoint;
var
  k: Integer;
  b: TTyRectF;
begin
  k := FChart.List.IndexOfDatum(ASeries, ARow);
  AssertTrue('the bar is in the list', k >= 0);
  b := TyShapeBounds(FChart.List.Element(k).Shape);
  Result := Point(Round((b.Left + b.Right) / 2), Round((b.Top + b.Bottom) / 2));
end;

{ ==================== loading geometry ==================== }

procedure TAdvChartExportLoadingTest.RunLoadingCase(C: TJSONObject);
var
  id, want: string;
  geo: TTyLoadingGeometry;
  sa, ea: Double;
  cfg: TTyLoadingCfg;
  t: TJSONObject;
  d: TJSONData;
  px: Double;
  col: TTyChartColor;
begin
  id := C.Strings['id'];
  NewChart(C.Integers['W'], C.Integers['H']);
  Load('{"animation":false,"series":[]}');
  if C.Booleans['before'] then FChart.ShowLoading('');
  ShowCall(C.Objects['call']);
  if C.Find('resize') is TJSONObject then
    FChart.SetBounds(0, 0, C.Objects['resize'].Integers['width'],
      C.Objects['resize'].Integers['height']);
  Draw;
  Inc(FCompared);
  if FChart.LoadingShown <> C.Booleans['shown'] then
  begin
    Miss(id + ': shown ' + BoolToStr(FChart.LoadingShown, True));
    Exit;
  end;
  if not C.Booleans['shown'] then Exit;
  if not FChart.Geo(geo) then
  begin
    Miss(id + ': no geometry');
    Exit;
  end;
  CheckHex(id + ': mask x', C.Objects['mask'].Objects['x'].Strings['hex'], 0);
  CheckHex(id + ': mask width', C.Objects['mask'].Objects['width'].Strings['hex'], geo.Width);
  CheckHex(id + ': mask height', C.Objects['mask'].Objects['height'].Strings['hex'], geo.Height);
  CheckHex(id + ': rect x', C.Objects['rect'].Objects['x'].Strings['hex'], geo.RectX);
  CheckHex(id + ': rect y', C.Objects['rect'].Objects['y'].Strings['hex'], geo.RectY);
  CheckHex(id + ': rect width', C.Objects['rect'].Objects['width'].Strings['hex'], geo.RectW);
  CheckHex(id + ': rect height', C.Objects['rect'].Objects['height'].Strings['hex'], geo.RectH);
  t := C.Objects['text'];
  CheckHex(id + ': text x', t.Objects['x'].Strings['hex'], geo.TextX);
  CheckHex(id + ': text y', t.Objects['y'].Strings['hex'], geo.TextY);
  CheckHex(id + ': text width', TJSONObject(t.Arrays['rect'].Items[2]).Strings['hex'],
    geo.TextWidth);
  cfg := FChart.Cfg;
  { the words: String(text) }
  d := t.Find('text');
  if d.JSONType = jtString then want := d.AsString
  else if d.JSONType = jtNumber then want := IntToStr(d.AsInteger)
  else want := '';
  Inc(FCompared);
  if cfg.Text <> want then Miss(id + ': text "' + cfg.Text + '", upstream "' + want + '"');
  { the size the layout measured with, px, against the font string's
    (the theme's 9pt is 12px, upstream's default) }
  if cfg.HasFontSize then px := TyFontPxOf(cfg.FontSizeLogical) else px := 12;
  if t.Find('font').JSONType = jtString then
  begin
    Inc(FCompared);
    if Pos(' ' + Fmt(px) + 'px ', t.Strings['font']) = 0 then
      Miss(id + ': font size ' + Fmt(px) + ', upstream ' + t.Strings['font']);
  end;
  if C.Find('arc') is TJSONObject then
  begin
    CheckHex(id + ': arc cx', C.Objects['arc'].Objects['cx'].Strings['hex'], geo.CX);
    CheckHex(id + ': arc cy', C.Objects['arc'].Objects['cy'].Strings['hex'], geo.CY);
    CheckHex(id + ': arc r', C.Objects['arc'].Objects['r'].Strings['hex'], geo.R);
    Inc(FCompared);
    if not FChart.Arc(sa, ea) then Miss(id + ': no arc')
    else
    begin
      CheckHex(id + ': startAngle', C.Objects['arc'].Objects['startAngle'].Strings['hex'], sa);
      CheckHex(id + ': endAngle', C.Objects['arc'].Objects['endAngle'].Strings['hex'], ea);
    end;
    Inc(FCompared);
    if Abs(cfg.LineWidth - C.Objects['arc'].Floats['lineWidth']) > 0 then
      Miss(id + ': lineWidth ' + Fmt(cfg.LineWidth));
  end
  else
  begin
    Inc(FCompared);
    if FChart.Arc(sa, ea) or cfg.ShowSpinner then Miss(id + ': an arc upstream does not have');
  end;
  { the colours the cfg wrote are the colours used }
  d := C.Objects['call'].Find('cfg');
  if d is TJSONObject then
  begin
    if TJSONObject(d).Find('textColor') <> nil then
    begin
      Inc(FCompared);
      if not (TyTryParseChartColor(t.Strings['fill'], col)
        and (cfg.TextColor.Kind = likColour) and (cfg.TextColor.Colour = col)) then
        Miss(id + ': textColor');
    end;
    if TJSONObject(d).Find('maskColor') <> nil then
    begin
      Inc(FCompared);
      if not (TyTryParseChartColor(C.Objects['mask'].Strings['fill'], col)
        and (cfg.MaskColor.Kind = likColour) and (cfg.MaskColor.Colour = col)) then
        Miss(id + ': maskColor');
    end;
    if (TJSONObject(d).Find('color') <> nil) and (C.Find('arc') is TJSONObject) then
    begin
      Inc(FCompared);
      if not (TyTryParseChartColor(C.Objects['arc'].Strings['stroke'], col)
        and (cfg.Color.Kind = likColour) and (cfg.Color.Colour = col)) then
        Miss(id + ': color');
    end;
  end;
end;

procedure TAdvChartExportLoadingTest.TestLoadingGeometryAsUpstream;
var arr: TJSONArray; i: Integer;
begin
  arr := Fix.Arrays['loading'];
  for i := 0 to arr.Count - 1 do
    try
      RunLoadingCase(arr.Objects[i]);
    except
      on E: Exception do
        Miss(arr.Objects[i].Strings['id'] + ': raised ' + E.ClassName + ' ' + E.Message);
    end;
  Verdict('loading geometry');
end;

{ ==================== the spinner's timelines ==================== }

procedure TAdvChartExportLoadingTest.RunTimeline(T: TJSONObject);
var
  id: string;
  samples, events: TJSONArray;
  s, e: Integer;
  at: Double;
  smp: TJSONObject;
  sa, ea: Double;
begin
  id := T.Strings['id'];
  NewChart(cW, cH);
  Load('{"animation":false,"series":[]}');
  FChart.ShowLoading('');
  samples := T.Arrays['samples'];
  events := T.Arrays['events'];
  e := 0;
  for s := 0 to samples.Count - 1 do
  begin
    smp := samples.Objects[s];
    at := smp.Floats['t'];
    while (e < events.Count) and (events.Objects[e].Floats['before'] <= at) do
    begin
      FChart.AnimNow := T0 + events.Objects[e].Floats['before'];
      if events.Objects[e].Strings['op'] = 'hide' then FChart.HideLoading
      else FChart.ShowLoading('');
      Inc(e);
    end;
    FChart.AnimNow := T0 + at;
    FChart.AnimTick(T0 + at);
    Inc(FCompared);
    if FChart.LoadingShown <> smp.Booleans['shown'] then
    begin
      Miss(id + ' @' + Fmt(at) + ': shown');
      Continue;
    end;
    Inc(FCompared);
    if FChart.Clips <> smp.Integers['clips'] then
      Miss(id + ' @' + Fmt(at) + ': ' + IntToStr(FChart.Clips) + ' clips, upstream '
        + IntToStr(smp.Integers['clips']));
    if not smp.Booleans['shown'] then Continue;
    if not FChart.Arc(sa, ea) then
    begin
      Miss(id + ' @' + Fmt(at) + ': no arc');
      Continue;
    end;
    CheckHex(id + ' @' + Fmt(at) + ' start', smp.Strings['start'], sa);
    CheckHex(id + ' @' + Fmt(at) + ' end', smp.Strings['end'], ea);
  end;
end;

procedure TAdvChartExportLoadingTest.TestSpinnerTimelinesAsUpstream;
var arr: TJSONArray; i: Integer;
begin
  arr := Fix.Arrays['timelines'];
  for i := 0 to arr.Count - 1 do RunTimeline(arr.Objects[i]);
  Verdict('spinner timelines');
end;

{ ==================== export: views and sizes ==================== }

function JoinPresent(A: TJSONArray): string;
var i: Integer;
begin
  Result := '';
  for i := 0 to A.Count - 1 do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + A.Strings[i];
  end;
end;

procedure TAdvChartExportLoadingTest.TestExportViewsAsUpstream;
var
  arr: TJSONArray;
  i: Integer;
  c: TJSONObject;
  id, opts, want, got, window: string;
  bmp: TBGRABitmap;
begin
  arr := Fix.Arrays['exports'];
  for i := 0 to arr.Count - 1 do
  begin
    c := arr.Objects[i];
    id := c.Strings['id'];
    if c.Find('theme').JSONType <> jtNull then Continue;
    NewChart(c.Integers['W'], c.Integers['H']);
    Load(c.Objects['option'].AsJSON);
    window := TyChartViewsText(FChart.Views);
    if c.Find('opts').JSONType = jtNull then opts := '' else opts := c.Objects['opts'].AsJSON;
    { a series view is no component view: upstream throws, the port leaves
      'series' out and hides the rest }
    if id = 'full-series' then want := JoinPresent(ExportCase('full-none').Arrays['present'])
    else if id = 'full-legend-series' then
      want := JoinPresent(ExportCase('full-legend').Arrays['present'])
    else want := JoinPresent(c.Arrays['present']);
    bmp := FChart.RenderToBitmap(opts);
    try
      got := TyChartViewsText(FChart.Views);
      Inc(FCompared);
      if got <> want then Miss(id + ': drew ' + got + ', upstream ' + want);
      if c.Find('imageW').JSONType = jtNumber then
      begin
        Inc(FCompared);
        if (bmp = nil) or (bmp.Width <> c.Integers['imageW'])
          or (bmp.Height <> c.Integers['imageH']) then
          Miss(id + ': image size');
      end;
    finally
      bmp.Free;
    end;
    { and the window draws every view again }
    Draw;
    Inc(FCompared);
    if TyChartViewsText(FChart.Views) <> window then
      Miss(id + ': the window after it drew ' + TyChartViewsText(FChart.Views)
        + ', before ' + window);
  end;
  Verdict('export views');
end;

{ ==================== export: the background ==================== }

procedure TAdvChartExportLoadingTest.TestExportBackgroundAsUpstream;
var
  arr: TJSONArray;
  i: Integer;
  c, bg: TJSONObject;
  id, opts: string;
  bmp, shown: TBGRABitmap;
  p, q: TBGRAPixel;
  fin: TJSONData;
  col: TTyChartColor;
  ok: Boolean;
begin
  arr := Fix.Arrays['exports'];
  for i := 0 to arr.Count - 1 do
  begin
    c := arr.Objects[i];
    id := c.Strings['id'];
    if Pos('bg-', id) <> 1 then Continue;
    if c.Find('theme').JSONType <> jtNull then Continue;
    NewChart(c.Integers['W'], c.Integers['H']);
    Load(c.Objects['option'].AsJSON);
    shown := Draw;
    if c.Find('opts').JSONType = jtNull then opts := '' else opts := c.Objects['opts'].AsJSON;
    bmp := FChart.RenderToBitmap(opts);
    try
      AssertTrue(id + ': an image', bmp <> nil);
      { left of the grid, under nothing }
      p := bmp.GetPixel(3, 150);
      bg := c.Objects['bg'];
      fin := bg.Find('chosen');
      Inc(FCompared);
      if fin.JSONType = jtNull then
      begin
        { upstream: the painter's 'transparent'; the port: the skin's ground,
          what the window shows }
        q := shown.GetPixel(3, 150);
        ok := PixelNear(p, q.red, q.green, q.blue, 255, 0);
      end
      else if not bg.Booleans['paints'] then
        ok := p.alpha = 0
      else if fin.JSONType = jtObject then
        { red at the left of a left-to-right red to blue }
        ok := (p.alpha = 255) and (p.red > 240) and (p.blue < 15)
      else if TyTryParseChartColor(fin.AsString, col) then
      begin
        if (col shr 24) = 0 then ok := p.alpha = 0
        else ok := PixelNear(p, (col shr 16) and $FF, (col shr 8) and $FF, col and $FF,
          col shr 24, 1);
      end
      else
        ok := PixelNear(p, 0, 0, 0, 255, 0);
      if not ok then Miss(id + ': pixel ' + PixText(p) + ' for ' + fin.AsJSON);
    finally
      bmp.Free;
    end;
  end;
  Verdict('export background');
end;

{ ==================== export: by hand ==================== }

procedure TAdvChartExportLoadingTest.TestExcludedViewsAreAbsentInThePixels;
const
  FULL = '{"animation":false,"title":{"text":"Sales","left":"center"%s},'
    + '"legend":{"top":30%s},"grid":{"top":70,"bottom":80},'
    + '"xAxis":{"type":"category","data":["Mon","Tue","Wed"]},"yAxis":{"type":"value"},'
    + '"series":[{"name":"A","type":"bar","data":[120,200,150]}]}';
var
  a, b: TBGRABitmap;
  x, y, inked: Integer;
begin
  { an option with axes only, both hidden, on nothing: not a pixel of ink }
  NewChart(cW, cH);
  Load('{"animation":false,"xAxis":{"type":"category","data":["a","b","c"]},'
    + '"yAxis":{"type":"value","min":0,"max":10},"series":[]}');
  a := FChart.RenderToBitmap('{"backgroundColor":"transparent"}');
  b := FChart.RenderToBitmap('{"backgroundColor":"transparent",'
    + '"excludeComponents":["xAxis","yAxis"]}');
  try
    inked := 0;
    for y := 0 to b.Height - 1 do
      for x := 0 to b.Width - 1 do
        if b.GetPixel(x, y).alpha <> 0 then Inc(inked);
    AssertEquals('the axes excluded leave nothing', 0, inked);
    inked := 0;
    for y := 0 to a.Height - 1 do
      for x := 0 to a.Width - 1 do
        if a.GetPixel(x, y).alpha <> 0 then Inc(inked);
    AssertTrue('and drawn they are there', inked > 100);
  finally
    a.Free;
    b.Free;
  end;
  { a title excluded is the title not shown; a legend likewise }
  NewChart(cW, cH);
  Load(Format(FULL, [',"show":false', '']));
  a := FChart.RenderToBitmap('');
  Load(Format(FULL, ['', '']));
  b := FChart.RenderToBitmap('{"excludeComponents":["title"]}');
  try
    AssertEquals('title excluded = title hidden', 0, DiffCount(a, b));
  finally
    a.Free;
    b.Free;
  end;
  Load(Format(FULL, ['', ',"show":false']));
  a := FChart.RenderToBitmap('');
  Load(Format(FULL, ['', '']));
  b := FChart.RenderToBitmap('{"excludeComponents":["legend"]}');
  try
    AssertEquals('legend excluded = legend hidden', 0, DiffCount(a, b));
  finally
    a.Free;
    b.Free;
  end;
  { and excluding them changes the picture }
  a := FChart.RenderToBitmap('');
  b := FChart.RenderToBitmap('{"excludeComponents":["legend","title"]}');
  try
    AssertTrue('the exclusion is seen', DiffCount(a, b) > 0);
  finally
    a.Free;
    b.Free;
  end;
end;

procedure TAdvChartExportLoadingTest.TestExportPutsTheWindowBack;
var
  before: TBGRABitmap;
  bmp: TBGRABitmap;
  pt: TPoint;
  d: TTyChartDatumRef;
  k, legendEls: Integer;
begin
  NewChart(cW, cH);
  Load('{"animation":false,"title":{"text":"T"},"legend":{},'
    + '"xAxis":{"type":"category","data":["a","b","c"]},"yAxis":{"type":"value"},'
    + '"series":[{"name":"S","type":"bar","data":[3,5,2]}]}');
  before := TBGRABitmap.Create(cW, cH);
  try
    before.PutImage(0, 0, FBmp, dmSet);
    pt := BarCentre(0, 1);
    d := FChart.HitTestAt(pt.X, pt.Y);
    AssertEquals('the bar is hit', 1, d.DataIndex);
    bmp := FChart.RenderToBitmap('{"pixelRatio":2,"excludeComponents":["legend"]}');
    try
      AssertEquals('twice as wide', 2 * cW, bmp.Width);
      AssertEquals('twice as tall', 2 * cH, bmp.Height);
    finally
      bmp.Free;
    end;
    { before any repaint, the hit test answers from the window's layout }
    d := FChart.HitTestAt(pt.X, pt.Y);
    AssertEquals('the same bar, at once', 0, d.SeriesIndex);
    AssertEquals('the same row, at once', 1, d.DataIndex);
    AssertTrue('the export drew no legend', not (cvLegend in FChart.Views));
    { the window's list is back whole: its legend items are hit targets
      again, the export's exclusion gone with it }
    legendEls := 0;
    for k := 0 to FChart.List.Count - 1 do
      if FChart.List.Element(k).Datum.Kind = ctkLegend then Inc(legendEls);
    AssertTrue('the legend is in the window''s list again', legendEls > 0);
    Draw;
    AssertEquals('the window is as before', 0, DiffCount(before, FBmp));
    AssertTrue('and has its legend', cvLegend in FChart.Views);
  finally
    before.Free;
  end;
end;

procedure TAdvChartExportLoadingTest.TestExportLeavesTheHoverOut;
var
  a, b: TBGRABitmap;
  pt: TPoint;
begin
  NewChart(cW, cH);
  Load('{"animation":false,"tooltip":{"trigger":"axis"},'
    + '"xAxis":{"type":"category","data":["a","b","c"]},"yAxis":{"type":"value"},'
    + '"series":[{"type":"bar","data":[3,5,2]}]}');
  a := FChart.RenderToBitmap('');
  pt := BarCentre(0, 1);
  FChart.Hover(pt.X, pt.Y);
  Draw;
  b := FChart.RenderToBitmap('');
  try
    AssertEquals('a hover is the window''s, not the export''s', 0, DiffCount(a, b));
  finally
    a.Free;
    b.Free;
  end;
end;

procedure TAdvChartExportLoadingTest.TestEncodings;
var
  bytes, again: TBytes;
  ms: TMemoryStream;
  img: TBGRABitmap;
  url, raw, fn: string;
  pt: TPoint;
begin
  NewChart(cW, cH);
  Load(OPT_PLAIN);
  pt := BarCentre(0, 1);
  { a PNG keeps the alpha a transparent background leaves }
  bytes := FChart.SaveToBytes('{"backgroundColor":"transparent"}');
  again := FChart.SaveToBytes('{"backgroundColor":"transparent"}');
  AssertTrue('a PNG', (Length(bytes) > 8) and (bytes[0] = $89) and (bytes[1] = Ord('P')));
  AssertTrue('the same bytes twice', (Length(bytes) = Length(again))
    and CompareMem(@bytes[0], @again[0], Length(bytes)));
  ms := TMemoryStream.Create;
  img := TBGRABitmap.Create;
  try
    ms.WriteBuffer(bytes[0], Length(bytes));
    ms.Position := 0;
    img.LoadFromStream(ms);
    AssertEquals('png width', cW, img.Width);
    AssertEquals('the ground is clear', 0, img.GetPixel(3, 150).alpha);
    AssertEquals('the bar is opaque', 255, img.GetPixel(pt.X, pt.Y).alpha);
  finally
    img.Free;
    ms.Free;
  end;
  { a JPEG is the canvas over black }
  bytes := FChart.SaveToBytes('{"type":"jpeg","backgroundColor":"transparent"}');
  AssertTrue('a JPEG', (Length(bytes) > 2) and (bytes[0] = $FF) and (bytes[1] = $D8));
  ms := TMemoryStream.Create;
  img := TBGRABitmap.Create;
  try
    ms.WriteBuffer(bytes[0], Length(bytes));
    ms.Position := 0;
    img.LoadFromStream(ms);
    AssertTrue('the clear ground is black: ' + PixText(img.GetPixel(3, 150)),
      PixelNear(img.GetPixel(3, 150), 0, 0, 0, 255, 12));
  finally
    img.Free;
    ms.Free;
  end;
  { 'jpg' is no type a canvas makes: a PNG }
  bytes := FChart.SaveToBytes('{"type":"jpg"}');
  AssertEquals('jpg is a PNG', $89, bytes[0]);
  { the data URL }
  url := FChart.GetDataURL('');
  AssertEquals('png url', 'data:image/png;base64,', Copy(url, 1, 22));
  raw := DecodeStringBase64(Copy(url, 23, MaxInt));
  AssertEquals('it decodes to a PNG', #137'PNG', Copy(raw, 1, 4));
  url := FChart.GetDataURL('{"type":"jpeg"}');
  AssertEquals('jpeg url', 'data:image/jpeg;base64,', Copy(url, 1, 23));
  { a file by its extension, unless the options say }
  fn := GetTempDir + 'ty-b11-export.jpg';
  FChart.SaveToFile(fn);
  ms := TMemoryStream.Create;
  try
    ms.LoadFromFile(fn);
    AssertEquals('.jpg is a JPEG', $FF, PByte(ms.Memory)[0]);
  finally
    ms.Free;
  end;
  FChart.SaveToFile(fn, '{"type":"png"}');
  ms := TMemoryStream.Create;
  try
    ms.LoadFromFile(fn);
    AssertEquals('type png wins', $89, PByte(ms.Memory)[0]);
  finally
    ms.Free;
  end;
  DeleteFile(fn);
  { SaveToPng is still the export }
  fn := GetTempDir + 'ty-b11-export.jpg';
  FChart.SaveToPng(fn);
  ms := TMemoryStream.Create;
  try
    ms.LoadFromFile(fn);
    AssertEquals('SaveToPng is a PNG whatever the name', $89, PByte(ms.Memory)[0]);
  finally
    ms.Free;
  end;
  DeleteFile(fn);
  { nothing to draw }
  FChart.SetBounds(0, 0, 0, 0);
  AssertEquals('no pixels', 'data:,', FChart.GetDataURL(''));
  AssertEquals('no bytes', 0, Length(FChart.SaveToBytes('')));
end;

{ ==================== loading in the pixels ==================== }

procedure TAdvChartExportLoadingTest.TestLoadingPixelsInTheThemesColours;
var
  pt: TPoint;
  bar, p, q: TBGRAPixel;
  mask, ink, spin: TTyColor;
  a, x, y, dark: Integer;
  geo: TTyLoadingGeometry;
  plain: TBGRABitmap;
begin
  NewChart(cW, cH);
  Load(OPT_PLAIN);
  plain := TBGRABitmap.Create(cW, cH);
  try
    plain.PutImage(0, 0, FBmp, dmSet);
    pt := BarCentre(0, 1);
    bar := FBmp.GetPixel(pt.X, pt.Y);
    FChart.ShowLoading('');
    Draw;
    p := FBmp.GetPixel(pt.X, pt.Y);
    mask := FCtl.Model.ResolveStyle('TyAdvChartLoading', '', []).Background.Color;
    ink := FCtl.Model.ResolveStyle('TyAdvChartLoading', '', []).TextColor;
    spin := FCtl.Model.ResolveStyle('TyAdvChartLoadingSpinner', '', []).BorderColor;
    a := TyAlphaOf(mask);
    AssertTrue('the theme has a mask', a > 0);
    { the bar under the mask: the theme's mask over it, as the painter
      blends }
    q := Over(bar, mask);
    AssertTrue('the bar under the mask ' + PixText(p) + ', the theme''s mask over '
      + PixText(bar) + ' is ' + PixText(q), PixelNear(p, q.red, q.green, q.blue, 255, 2));
    AssertTrue('the geometry', FChart.Geo(geo));
    { the arc at its first angles: a short stroke at the top of its circle }
    p := FBmp.GetPixel(Round(geo.CX), Round(geo.CY - geo.R));
    AssertTrue('the arc in the spinner colour ' + PixText(p),
      PixelNear(p, TyRedOf(spin), TyGreenOf(spin), TyBlueOf(spin), 255, 40));
    p := FBmp.GetPixel(Round(geo.CX), Round(geo.CY + geo.R));
    AssertTrue('not round the bottom yet ' + PixText(p),
      not PixelNear(p, TyRedOf(spin), TyGreenOf(spin), TyBlueOf(spin), 255, 40));
    { the words, in the theme's ink, right of the arc }
    dark := 0;
    for y := Round(geo.CY) - 6 to Round(geo.CY) + 6 do
      for x := Round(geo.TextX) to Round(geo.TextX + geo.TextWidth) do
      begin
        p := FBmp.GetPixel(x, y);
        if (Abs(p.red - TyRedOf(ink)) < 60) and (Abs(p.green - TyGreenOf(ink)) < 60)
          and (Abs(p.blue - TyBlueOf(ink)) < 60) then Inc(dark);
      end;
    AssertTrue('the text is drawn (' + IntToStr(dark) + ')', dark >= 5);
    { hidden, the chart is as it was }
    FChart.HideLoading;
    AssertTrue('hidden', not FChart.LoadingShown);
    Draw;
    AssertEquals('hidden is gone', 0, DiffCount(plain, FBmp));
  finally
    plain.Free;
  end;
end;

procedure TAdvChartExportLoadingTest.TestLoadingCfgColoursAndHide;
var
  pt: TPoint;
  bar, p, q: TBGRAPixel;
  geo: TTyLoadingGeometry;
begin
  NewChart(cW, cH);
  Load(OPT_PLAIN);
  pt := BarCentre(0, 1);
  bar := FBmp.GetPixel(pt.X, pt.Y);
  FChart.ShowLoading('{"maskColor":"rgba(0,0,0,0.5)","color":"#00ff00","text":""}');
  Draw;
  p := FBmp.GetPixel(pt.X, pt.Y);
  q := Over(bar, $80000000);
  AssertTrue('half black over the bar ' + PixText(p) + ', want ' + PixText(q),
    PixelNear(p, q.red, q.green, q.blue, 255, 2));
  AssertTrue('the geometry', FChart.Geo(geo));
  p := FBmp.GetPixel(Round(geo.CX), Round(geo.CY - geo.R));
  AssertTrue('a green arc ' + PixText(p), (p.green > 200) and (p.red < 60) and (p.blue < 60));
  { 'none': no mask at all }
  FChart.ShowLoading('{"maskColor":"none","showSpinner":false,"text":""}');
  Draw;
  p := FBmp.GetPixel(pt.X, pt.Y);
  AssertTrue('no mask ' + PixText(p), PixelNear(p, bar.red, bar.green, bar.blue, 255, 0));
  { an unknown name hides the effect shown before and shows nothing }
  FChart.ShowLoading('nope', '{"text":"z"}');
  AssertTrue('nothing shown', not FChart.LoadingShown);
  { text as String(value) }
  FChart.ShowLoading('{"text":true}');
  AssertEquals('true', 'true', FChart.Cfg.Text);
  FChart.ShowLoading('{"text":[1,null,"a"]}');
  AssertEquals('an array joins', '1,,a', FChart.Cfg.Text);
  FChart.ShowLoading('{"text":{"a":1}}');
  AssertEquals('an object', '[object Object]', FChart.Cfg.Text);
  FChart.ShowLoading('{"text":2.5}');
  AssertEquals('a number', '2.5', FChart.Cfg.Text);
  FChart.ShowLoading('5');
  AssertEquals('no object is no cfg', rsTyChartLoading, FChart.Cfg.Text);
end;

procedure TAdvChartExportLoadingTest.TestLoadingIsInTheExport;
var
  pt: TPoint;
  a, b: TBGRABitmap;
  pa, pb: TBGRAPixel;
begin
  NewChart(cW, cH);
  Load(OPT_PLAIN);
  pt := BarCentre(0, 1);
  a := FChart.RenderToBitmap('');
  FChart.ShowLoading('{"maskColor":"rgba(0,0,0,0.5)"}');
  b := FChart.RenderToBitmap('{"excludeComponents":["xAxis","yAxis"]}');
  try
    pa := Over(a.GetPixel(pt.X, pt.Y), $80000000);
    pb := b.GetPixel(pt.X, pt.Y);
    AssertTrue('the mask is in the export, whatever is excluded ' + PixText(pb),
      PixelNear(pb, pa.red, pa.green, pa.blue, 255, 2));
  finally
    a.Free;
    b.Free;
  end;
end;

procedure TAdvChartExportLoadingTest.TestSpinnerHeldUnderCamOff;
var
  sa, ea, sa0, ea0: Double;
  smp: TJSONObject;
  i: Integer;
  samples: TJSONArray;
begin
  NewChart(cW, cH);
  Load('{"animation":false,"series":[]}');
  FChart.AnimationMode := camOff;
  FChart.ShowLoading('');
  FChart.Arc(sa0, ea0);
  FChart.AnimTick(T0);
  FChart.AnimTick(T0 + 500);
  FChart.Arc(sa, ea);
  AssertEquals('held: start', Hex(sa0), Hex(sa));
  AssertEquals('held: end', Hex(ea0), Hex(ea));
  { out of camOff the clips start at their first step }
  FChart.AnimationMode := camAuto;
  FChart.AnimTick(T0 + 600);
  FChart.AnimTick(T0 + 700);
  FChart.Arc(sa, ea);
  samples := Fix.Arrays['timelines'].Objects[0].Arrays['samples'];
  smp := nil;
  for i := 0 to samples.Count - 1 do
    if samples.Objects[i].Integers['t'] = 100 then smp := samples.Objects[i];
  AssertTrue('the sample', smp <> nil);
  AssertEquals('100 ms in: end', smp.Strings['end'], Hex(ea));
  AssertEquals('100 ms in: start', smp.Strings['start'], Hex(sa));
  { the option's animation: false does not stop it (upstream's neither) }
  AssertEquals('two clips', 2, FChart.Clips);
end;

procedure TAdvChartExportLoadingTest.TestOptionsThatAreNotJson;
var raised: Boolean;
begin
  NewChart(cW, cH);
  Load(OPT_PLAIN);
  raised := False;
  try
    FChart.RenderToBitmap('{bad').Free;
  except
    on EArgumentException do raised := True;
  end;
  AssertTrue('export options that are no JSON raise', raised);
  raised := False;
  try
    FChart.ShowLoading('{bad');
  except
    on EArgumentException do raised := True;
  end;
  AssertTrue('a loading cfg that is no JSON raises', raised);
  { valid JSON that is no object is no options }
  FChart.RenderToBitmap('"legend"').Free;
  FChart.RenderToBitmap('null').Free;
end;

{ A RATIO IS PER LOGICAL PX: a control at 192 PPI is half as many CSS px
  as it is device px }
procedure TAdvChartExportLoadingTest.TestExportAtTheControlsPPI;
var bmp: TBGRABitmap;
begin
  NewChart(cW, cH);
  Load(OPT_PLAIN);
  FChart.Font.PixelsPerInch := 192;
  bmp := FChart.RenderToBitmap('{"pixelRatio":1}');
  try
    AssertEquals('ratio 1 at 192: width', cW div 2, bmp.Width);
    AssertEquals('ratio 1 at 192: height', cH div 2, bmp.Height);
  finally
    bmp.Free;
  end;
  bmp := FChart.RenderToBitmap('');
  try
    AssertEquals('no ratio: the control''s own width', cW, bmp.Width);
    AssertEquals('no ratio: the control''s own height', cH, bmp.Height);
  finally
    bmp.Free;
  end;
  bmp := FChart.RenderToBitmap('{"pixelRatio":3}');
  try
    AssertEquals('ratio 3 at 192', 600, bmp.Width);
  finally
    bmp.Free;
  end;
end;

{ THE WINDOW'S PATH: the static layer cached, the effect in the dynamic one }
procedure TAdvChartExportLoadingTest.TestLoadingOnTheCachedPath;
var
  pt: TPoint;
  bar, p: TBGRAPixel;
begin
  NewChart(cW, cH);
  Load(OPT_PLAIN);
  pt := BarCentre(0, 1);
  bar := FBmp.GetPixel(pt.X, pt.Y);
  FChart.ShowLoading('{"maskColor":"rgba(0,0,0,0.5)"}');
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.RenderWindow(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
  { the dynamic layer is its own transparent bitmap blended over the
    blitted static one -- a plain alpha blend, not the painter's own; the
    canvas proxy of a TBGRABitmap keeps no alpha worth reading }
  p := FBmp.GetPixel(pt.X, pt.Y);
  AssertTrue('the mask on the cached path ' + PixText(p) + ', bar ' + PixText(bar),
    (Abs(p.red - bar.red div 2) <= 2) and (Abs(p.green - bar.green div 2) <= 2)
    and (Abs(p.blue - bar.blue div 2) <= 2));
  FChart.HideLoading;
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.RenderWindow(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
  p := FBmp.GetPixel(pt.X, pt.Y);
  AssertTrue('and gone when hidden ' + PixText(p), (p.red = bar.red)
    and (p.green = bar.green) and (p.blue = bar.blue));
end;

initialization
  RegisterTest(TAdvChartExportLoadingTest);
finalization
  FreeAndNil(GFix);
end.
