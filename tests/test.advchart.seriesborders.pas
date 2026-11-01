unit test.advchart.seriesborders;
{$mode objfpc}{$H+}
{ THE PENS OF A SERIES' PATHS, held to upstream. [R6-D]

  tests/fixtures/advchart-series-borders.json, from the real ECharts 6.1
  build (tools/advchart-oracle/series-borders.js): per case settled (an
  action, where one, dispatched and settled), the set of stroke / width /
  dash / dash offset of every stroked path under the series' views -- or of
  the part the case names: a radar item's symbols, a gauge's pointer or
  progress arc, a chord's ribbons -- getItemStyle's border keys and
  getLineStyle's, an item's own over its series', the views' own rules
  (a radar symbol's and a gauge icon's setColor, pointer.itemStyle,
  progress.itemStyle) and the states' styles over them.

  The ends -- lineCap / lineJoin / miterLimit -- go with each pen.

  TestThePensAsUpstream: the same set off the port's frame -- every stroked
  element of a series that is no text and no label line, of that part --
  and, for a part, how many elements it has and how many of them stroke. A
  stroke upstream that is a word zrender cannot parse ('source', a chord's
  default colour) is the canvas' to keep the last element's colour for and
  the port's to draw none: it is not compared. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint,
     tyControls.AdvanceChart.Measure, tyControls.AdvanceChart.Anim,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TBorderProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function Frame: TTyPaintList;
  end;

  TAdvChartSeriesBordersTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FChart: TBorderProbe;
    procedure Draw;
    procedure Settle(AStart: Double);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestThePensAsUpstream;
  end;

implementation

const
  cW = 400;
  cH = 300;
  T0 = 1700000000000.0;
  T1 = T0 + 10000;

function TBorderProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TBorderProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TBorderProbe.Frame: TTyPaintList;
begin
  Result := AnimFrame;
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

procedure TAdvChartSeriesBordersTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  FMeasure := LoadJson('advchart-text-style.json');
end;

procedure TAdvChartSeriesBordersTest.TearDown;
begin
  FreeAndNil(FChart);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FBmp);
  FreeAndNil(FMeasure);
  inherited TearDown;
end;

procedure TAdvChartSeriesBordersTest.Draw;
begin
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

procedure TAdvChartSeriesBordersTest.Settle(AStart: Double);
var t: Integer;
begin
  t := 16;
  while t <= 5000 do
  begin
    FChart.AnimNow := AStart + t;
    FChart.AnimTick(AStart + t);
    Inc(t, 250);
  end;
  Draw;
end;

function NumText(AV: Double): string;
begin
  Result := FloatToStr(AV);
end;

{ stroke|width|dash|offset|cap/join/miterLimit, as the oracle writes it (the
  dash normalizeLineDash'd against the width) }
function PenOf(const AEl: TTyChartElement): string;
var
  c: Cardinal;
  dash: TTyDoubleArray;
  i: Integer;
  ds: string;
begin
  if AEl.Style.StrokeGradient.Kind <> cgkNone then Result := 'grad'
  else
  begin
    c := Cardinal(AEl.Style.StrokeColor);
    Result := LowerCase(Format('#%.2x%.2x%.2x%.2x', [(c shr 16) and $FF, (c shr 8) and $FF,
      c and $FF, c shr 24]));
  end;
  if AEl.Style.DashWord <> 0 then
    dash := TyDashOfWord(AEl.Style.DashWord, AEl.Style.StrokeWidthLogical)
  else
    dash := AEl.Style.DashLogical;
  ds := '';
  for i := 0 to High(dash) do
  begin
    if i > 0 then ds := ds + ',';
    ds := ds + NumText(dash[i]);
  end;
  if ds = '' then ds := 'solid';
  Result := Result + '|' + NumText(AEl.Style.StrokeWidthLogical) + '|' + ds + '|'
    + NumText(AEl.Style.DashOffsetLogical) + '|';
  case AEl.Style.LineCap of
    1: Result := Result + 'round';
    2: Result := Result + 'square';
  else
    Result := Result + 'butt';
  end;
  case AEl.Style.LineJoin of
    1: Result := Result + '/round';
    2: Result := Result + '/bevel';
  else
    Result := Result + '/miter';
  end;
  if AEl.Style.MiterLimit > 0 then Result := Result + '/' + NumText(AEl.Style.MiterLimit)
  else Result := Result + '/10';
end;

function PartOf(const AEl: TTyChartElement): string;
begin
  Result := '';
  if (AEl.Anim.Role = carNone) and (AEl.Anim.UtTag = 1) and (AEl.Anim.Sub > 0) then
    Result := 'symbol'
  else if AEl.Anim.Role = carGaugePointer then Result := 'pointer'
  else if AEl.Anim.Role = carGaugeProgress then Result := 'progress'
  else if (AEl.Anim.Role = carChord) and AEl.Datum.IsEdge then Result := 'ribbon';
end;

procedure TAdvChartSeriesBordersTest.TestThePensAsUpstream;
var
  fix: TJSONData;
  cs, pens: TJSONArray;
  c: TJSONObject;
  i, k, seen, n, nBad, nCases, nParts: Integer;
  lst: TTyPaintList;
  el: TTyChartElement;
  got: TStringList;
  want, have, id, bad, part: string;
  act: TJSONData;
begin
  fix := LoadJson('advchart-series-borders.json');
  got := TStringList.Create;
  got.Sorted := True;
  got.Duplicates := dupIgnore;
  nBad := 0;
  nCases := 0;
  nParts := 0;
  bad := '';
  try
    cs := TJSONObject(fix).Arrays['charts'];
    for i := 0 to cs.Count - 1 do
    begin
      c := cs.Objects[i];
      id := c.Strings['id'];
      part := c.Strings['part'];
      FreeAndNil(FChart);
      FChart := TBorderProbe.Create(FForm);
      FChart.Parent := FForm;
      FChart.Controller := FCtl;
      FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
        TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
        TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
      FChart.AnimationMode := camAlways;
      FChart.AnimNow := T0;
      FChart.SetBounds(0, 0, cW, cH);
      FChart.Option := c.Objects['option'].AsJSON;
      AssertEquals(id + ' parses', '', FChart.OptionError);
      Draw;
      Settle(T0);
      act := c.Find('action');
      if (act <> nil) and (act.JSONType = jtObject) then
      begin
        FChart.AnimNow := T1;
        FChart.DispatchAction(act.AsJSON);
        Settle(T1);
      end;
      lst := FChart.Frame;
      got.Clear;
      seen := 0;
      n := 0;
      for k := 0 to lst.Count - 1 do
      begin
        el := lst.Element(k);
        if GetEnvironmentVariable('TY_BORDER_DUMP') = id then
          WriteLn(id + ' el ' + IntToStr(k) + ' role ' + IntToStr(Ord(el.Anim.Role)) + ' kind '
            + IntToStr(Ord(el.Datum.Kind)) + ' s ' + IntToStr(el.Datum.SeriesIndex) + ' i '
            + IntToStr(el.Datum.DataIndex) + ' edge ' + BoolToStr(el.Datum.IsEdge, True) + ' ign '
            + BoolToStr(el.Ignore, True) + ' pen ' + PenOf(el) + ' ut ' + IntToStr(el.Anim.UtTag)
            + ' sub ' + IntToStr(el.Anim.Sub) + ' text "' + el.Caption.Text + '"');
        if el.Ignore or el.IsGuide or (el.Anim.Role = carLabel) then Continue;
        if el.Caption.FontSizeLogical > 0 then Continue;
        if not (((el.Datum.Kind = ctkSeries) and (el.Datum.SeriesIndex >= 0))
          or ((el.Anim.UtTag = 1) and (el.Anim.Series >= 0))) then Continue;
        if (part <> '') and (PartOf(el) <> part) then Continue;
        Inc(seen);
        if not (el.Style.StrokeWidthLogical > 0) then Continue;
        if ((el.Style.StrokeColor shr 24) = 0) and (el.Style.StrokeGradient.Kind = cgkNone) then Continue;
        Inc(n);
        got.Add(PenOf(el));
      end;
      pens := c.Arrays['pens'];
      want := '';
      for k := 0 to pens.Count - 1 do
        { a word the canvas cannot take strokes with the last element's
          colour there: no pen here }
        if Copy(pens.Strings[k], 1, 2) <> 'x:' then want := want + ' ' + pens.Strings[k];
      have := '';
      for k := 0 to got.Count - 1 do have := have + ' ' + got[k];
      Inc(nCases);
      if part <> '' then
      begin
        Inc(nParts);
        if (seen <> c.Integers['seen']) and (have = want) then
          have := have + Format(' (%d elements, upstream %d)', [seen, c.Integers['seen']]);
      end;
      if have <> want then
      begin
        Inc(nBad);
        bad := bad + LineEnding + Format('  %s: %s here, upstream %s', [id, Trim(have),
          Trim(want)]);
      end;
    end;
  finally
    got.Free;
    fix.Free;
  end;
  AssertTrue('cases', nCases >= 40);
  AssertTrue('parts', nParts >= 25);
  AssertTrue(Format('%d of %d differ from upstream:%s', [nBad, nCases, bad]), nBad = 0);
end;

initialization
  RegisterTest(TAdvChartSeriesBordersTest);
end.
