unit test.advchart.seriespenends;
{$mode objfpc}{$H+}
{ THE PEN'S ENDS OF A SERIES' PATHS, held to upstream. [R6-C]

  tests/fixtures/advchart-series-pen-ends.json, from the real ECharts 6.1
  build (tools/advchart-oracle/series-pen-ends.js): per case at rest, the
  set of lineCap / lineJoin / miterLimit of every stroked path under the
  series' views -- getItemStyle's borderCap / borderJoin / borderMiterLimit,
  getLineStyle's cap / join / miterLimit, an item's own over its series',
  and the views' own (a funnel joins round, a line's polyline bevels).

  TestThePenEndsAsUpstream: the same set off the port's list -- every
  stroked element of a series that is no text and no label line (a gauge's
  pointer alone), its LineCap / LineJoin / MiterLimit (nought the canvas'
  10). }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint,
     tyControls.AdvanceChart.Measure,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TPenProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function Frame: TTyPaintList;
  end;

  TAdvChartSeriesPenEndsTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FMeasure: TJSONData;
    FBmp: TBGRABitmap;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestThePenEndsAsUpstream;
  end;

implementation

const
  cW = 400;
  cH = 300;

function TPenProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TPenProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TPenProbe.Frame: TTyPaintList;
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

procedure TAdvChartSeriesPenEndsTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  FMeasure := LoadJson('advchart-text-style.json');
end;

procedure TAdvChartSeriesPenEndsTest.TearDown;
begin
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FBmp);
  FreeAndNil(FMeasure);
  inherited TearDown;
end;

function CapWord(A: Byte): string;
begin
  case A of
    1: Result := 'round';
    2: Result := 'square';
  else
    Result := 'butt';
  end;
end;

function JoinWord(A: Byte): string;
begin
  case A of
    1: Result := 'round';
    2: Result := 'bevel';
  else
    Result := 'miter';
  end;
end;

procedure TAdvChartSeriesPenEndsTest.TestThePenEndsAsUpstream;
var
  fix: TJSONData;
  cs, ends: TJSONArray;
  c: TJSONObject;
  i, k: Integer;
  chart: TPenProbe;
  lst: TTyPaintList;
  el: TTyChartElement;
  got: TStringList;
  want, have, id, bad: string;
  ml: Double;
  nBad, nCases: Integer;
  unstroked: Boolean;
begin
  fix := LoadJson('advchart-series-pen-ends.json');
  got := TStringList.Create;
  got.Sorted := True;
  got.Duplicates := dupIgnore;
  nBad := 0;
  nCases := 0;
  bad := '';
  try
    cs := TJSONObject(fix).Arrays['charts'];
    for i := 0 to cs.Count - 1 do
    begin
      c := cs.Objects[i];
      id := c.Strings['id'];
      chart := TPenProbe.Create(FForm);
      try
        chart.Parent := FForm;
        chart.Controller := FCtl;
        chart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
          TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
          TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
        chart.Option := c.Objects['option'].AsJSON;
        AssertEquals(id + ' parses', '', chart.OptionError);
        chart.SetBounds(0, 0, cW, cH);
        FBmp.Fill(BGRA(255, 255, 255, 255));
        chart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
        lst := chart.Frame;
        got.Clear;
        for k := 0 to lst.Count - 1 do
        begin
          el := lst.Element(k);
          if GetEnvironmentVariable('TY_PEN_DUMP') = id then
            WriteLn(id + ' el ' + IntToStr(k) + ' role ' + IntToStr(Ord(el.Anim.Role)) + ' kind '
              + IntToStr(Ord(el.Datum.Kind)) + ' s ' + IntToStr(el.Datum.SeriesIndex) + ' i '
              + IntToStr(el.Datum.DataIndex) + ' edge ' + BoolToStr(el.Datum.IsEdge, True) + ' lw '
              + FloatToStr(el.Style.StrokeWidthLogical) + ' sa ' + IntToStr(el.Style.StrokeColor shr 24)
              + ' cap ' + IntToStr(el.Style.LineCap) + ' join ' + IntToStr(el.Style.LineJoin) + ' ml '
              + FloatToStr(el.Style.MiterLimit) + ' ut ' + IntToStr(el.Anim.UtTag) + ' as '
              + IntToStr(el.Anim.Series) + ' text "' + el.Caption.Text + '"');
          if el.Ignore or el.IsGuide or (el.Anim.Role = carLabel) then Continue;
          { a series' element: its datum's, or a tagged item path's (a
            radar's symbols carry none) }
          if not (((el.Datum.Kind = ctkSeries) and (el.Datum.SeriesIndex >= 0))
            or ((el.Anim.UtTag = 1) and (el.Anim.Series >= 0))) then Continue;
          { THREE PENS THE PORT DOES NOT DRAW (a radar's symbols, a gauge's
            pointer take no border width; a chord's ribbon no lineStyle
            stroke -- other gaps, see spec 250): their ends as set }
          unstroked := (el.Anim.Role = carGaugePointer)
            or ((el.Anim.Role = carNone) and (el.Anim.UtTag = 1) and (el.Anim.Sub > 0))
            or ((el.Anim.Role = carChord) and el.Datum.IsEdge);
          if not unstroked then
          begin
            if not (el.Style.StrokeWidthLogical > 0) then Continue;
            if ((el.Style.StrokeColor shr 24) = 0) and (el.Style.StrokeGradient.Kind = cgkNone) then Continue;
          end;
          if (id = 'gauge') and (el.Anim.Role <> carGaugePointer) then Continue;
          if el.Style.MiterLimit > 0 then ml := el.Style.MiterLimit else ml := 10;
          got.Add(CapWord(el.Style.LineCap) + '/' + JoinWord(el.Style.LineJoin) + '/'
            + FloatToStr(ml));
        end;
        ends := c.Arrays['ends'];
        want := '';
        for k := 0 to ends.Count - 1 do want := want + ',' + ends.Strings[k];
        have := '';
        for k := 0 to got.Count - 1 do have := have + ',' + got[k];
        Inc(nCases);
        if have <> want then
        begin
          Inc(nBad);
          bad := bad + LineEnding + Format('  %s: %s here, upstream %s', [id, Copy(have, 2, MaxInt),
            Copy(want, 2, MaxInt)]);
        end;
      finally
        chart.Free;
      end;
    end;
  finally
    got.Free;
    fix.Free;
  end;
  AssertTrue('cases', nCases >= 20);
  AssertTrue(Format('%d of %d differ from upstream:%s', [nBad, nCases, bad]), nBad = 0);
end;

initialization
  RegisterTest(TAdvChartSeriesPenEndsTest);
end.
