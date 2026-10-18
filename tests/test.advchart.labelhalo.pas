unit test.advchart.labelhalo;
{$mode objfpc}{$H+}
{ A label's halo -- a stroke along the glyphs' outlines [F4c].

  tools/advchart-oracle/label-halo.js records, on ECharts 6.1, the text style
  a label's textBorderType makes (lineDash as written, the global
  textStyle's under the label's, a rich token's own) and the pattern
  zrender's normalizeLineDash draws it with; this holds the control's
  captions and rich pieces to that pattern.

  The picture is no upstream's -- the glyphs are the painter's -- so the
  halo's shape is held by what zrender's strokeText guarantees: one stroke,
  so a translucent halo is laid once and never darkens where it meets
  itself (the old one stamped the glyphs at whole-pixel offsets, and the
  stamps compounded); a dashed one leaves gaps a solid one does not. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint,
     tyControls.AdvChart.Render, tyControls.AdvanceChart;
type
  THaloProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  TAdvChartLabelHaloTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: THaloProbe;
    FBmp: TBGRABitmap;
    procedure Show(const AOption: string);
    function LabelEl(const AText: string; out AEl: TTyChartElement): Boolean;
    function PieceEl(const AText: string; out AEl: TTyChartElement): Boolean;
    function RedPixels(AMinGreen: Integer; out ADarkest: Integer): Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheDashesAreUpstreams;
    procedure TestATranslucentHaloDoesNotDarken;
    procedure TestADashedHaloLeavesGaps;
    procedure TestTheHaloReachesHalfItsWidthOut;
  end;

implementation

const
  cW = 400;
  cH = 300;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-label-halo.json';
end;

function LoadJson(const APath: string): TJSONData;
var sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(APath);
    Result := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  Result := 0;
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

procedure THaloProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function THaloProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

procedure TAdvChartLabelHaloTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(cW, cH, BGRAWhite);
  FChart := nil;
end;

procedure TAdvChartLabelHaloTest.TearDown;
begin
  FreeAndNil(FChart);
  FreeAndNil(FBmp);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartLabelHaloTest.Show(const AOption: string);
begin
  FreeAndNil(FChart);
  FChart := THaloProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.AnimationMode := camOff;
  FChart.Option := AOption;
  FChart.SetBounds(0, 0, cW, cH);
  FBmp.Fill(BGRAWhite);
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

function TAdvChartLabelHaloTest.LabelEl(const AText: string;
  out AEl: TTyChartElement): Boolean;
var
  lst: TTyPaintList;
  k: Integer;
begin
  Result := False;
  AEl := Default(TTyChartElement);
  lst := FChart.List;
  if lst = nil then Exit;
  { the series' label: the caption with these words that has a halo (an
    axis' tick of the same words has none) }
  for k := 0 to lst.Count - 1 do
    if (lst.Element(k).Caption.Text = AText)
      and (lst.Element(k).Caption.StrokeWidthLogical > 0) then
    begin
      AEl := lst.Element(k);
      Exit(True);
    end;
  for k := 0 to lst.Count - 1 do
    if lst.Element(k).Caption.Text = AText then
    begin
      AEl := lst.Element(k);
      Exit(True);
    end;
end;

{ the element whose block has a text piece of these words }
function TAdvChartLabelHaloTest.PieceEl(const AText: string;
  out AEl: TTyChartElement): Boolean;
var
  lst: TTyPaintList;
  k, q: Integer;
  e: TTyChartElement;
begin
  Result := False;
  AEl := Default(TTyChartElement);
  lst := FChart.List;
  if lst = nil then Exit;
  for k := 0 to lst.Count - 1 do
  begin
    e := lst.Element(k);
    for q := 0 to High(e.Caption.RtPieces) do
      if (e.Caption.RtPieces[q].Kind = rpkText) and (e.Caption.RtPieces[q].Text = AText) then
      begin
        AEl := e;
        Exit(True);
      end;
  end;
end;

{ pixels where red leads green by 40 or more (the halo's ink), and the
  lowest green among them }
function TAdvChartLabelHaloTest.RedPixels(AMinGreen: Integer; out ADarkest: Integer): Integer;
var
  x, y: Integer;
  p: TBGRAPixel;
begin
  Result := 0;
  ADarkest := 255;
  for y := 0 to cH - 1 do
    for x := 0 to cW - 1 do
    begin
      p := FBmp.GetPixel(x, y);
      if (p.red > 200) and (p.red - p.green >= 40) and (p.red - p.blue >= 40)
        and (Abs(p.green - p.blue) <= 8) then
      begin
        Inc(Result);
        if p.green < ADarkest then ADarkest := p.green;
      end;
    end;
  if AMinGreen = 0 then;
end;

procedure TAdvChartLabelHaloTest.TestTheDashesAreUpstreams;
var
  root: TJSONData;
  cases, texts: TJSONArray;
  cs, t: TJSONObject;
  c, k, q, bad, compared: Integer;
  el: TTyChartElement;
  pat: TTyDoubleArray;
  want: TJSONData;
  ok: Boolean;
  report, dash: string;
  w: Double;
begin
  root := LoadJson(FixturePath);
  try
    cases := TJSONObject(root).Arrays['cases'];
    bad := 0;
    compared := 0;
    report := '';
    for c := 0 to cases.Count - 1 do
    begin
      cs := cases.Objects[c];
      Show(cs.Objects['option'].AsJSON);
      texts := cs.Arrays['texts'];
      for k := 0 to texts.Count - 1 do
      begin
        t := texts.Objects[k];
        want := t.Find('pattern');
        dash := '';
        w := 0;
        if texts.Count = 1 then
        begin
          if not LabelEl('5', el) then
          begin
            Inc(bad);
            report := report + LineEnding + '  ' + cs.Strings['id'] + ': no label';
            Continue;
          end;
          dash := el.Caption.StrokeType;
          w := el.Caption.StrokeWidthLogical;
        end
        else
        begin
          { a rich label: its text pieces, matched by their words }
          if not PieceEl(t.Strings['text'], el) then
          begin
            Inc(bad);
            report := report + LineEnding + '  ' + cs.Strings['id'] + ': no rich label';
            Continue;
          end;
          for q := 0 to High(el.Caption.RtPieces) do
            if (el.Caption.RtPieces[q].Kind = rpkText)
              and (el.Caption.RtPieces[q].Text = t.Strings['text']) then
            begin
              dash := el.Caption.RtPieces[q].LineDash;
              w := el.Caption.RtPieces[q].LineWidth;
            end;
        end;
        ok := TyNormalizeLineDash(dash, w, pat);
        Inc(compared);
        if (want = nil) or (want.JSONType = jtNull) then
        begin
          if ok then
          begin
            Inc(bad);
            report := report + LineEnding + Format('  %s "%s": dashed (%s) here, solid upstream',
              [cs.Strings['id'], t.Strings['text'], dash]);
          end;
        end
        else if (not ok) or (Length(pat) <> TJSONArray(want).Count) then
        begin
          Inc(bad);
          report := report + LineEnding + Format('  %s "%s": "%s" at %g here, upstream %s',
            [cs.Strings['id'], t.Strings['text'], dash, w, want.AsJSON]);
        end
        else
          for q := 0 to High(pat) do
            if pat[q] <> FromHex(TJSONArray(want).Strings[q]) then
            begin
              Inc(bad);
              report := report + LineEnding + Format('  %s "%s": dash %d %g, upstream %g',
                [cs.Strings['id'], t.Strings['text'], q, pat[q],
                 FromHex(TJSONArray(want).Strings[q])]);
            end;
      end;
    end;
    AssertTrue(Format('enough was compared (%d)', [compared]), compared >= 10);
    AssertEquals(IntToStr(bad) + ' of ' + IntToStr(compared) + ' differ:' + report, 0, bad);
  finally
    root.Free;
  end;
end;

const
  cHaloBar = '{"animation": false, "xAxis": {"type": "category", "data": ["a"]},'
    + ' "yAxis": {"type": "value", "max": 10}, "series": [{"type": "bar", "data": [5],'
    + ' "itemStyle": {"color": "#ffffff"}, "label": {"show": true, "position": "top",'
    + ' "fontSize": 40, "color": "#000000", "formatter": "W8", %s}}]}';

procedure TAdvChartLabelHaloTest.TestATranslucentHaloDoesNotDarken;
var n, darkest: Integer;
begin
  { half-transparent red over white is (255, 128, 128) wherever it is laid
    once; laid twice it is (255, 64, 64) }
  Show(Format(cHaloBar, ['"textBorderColor": "rgba(255,0,0,0.5)", "textBorderWidth": 8']));
  n := RedPixels(0, darkest);
  AssertTrue(Format('the halo is drawn (%d px)', [n]), n > 100);
  AssertTrue(Format('and laid once: its darkest green is %d', [darkest]), darkest >= 118);
end;

procedure TAdvChartLabelHaloTest.TestADashedHaloLeavesGaps;
var
  solid, dashed, dotted, darkest: Integer;
  el: TTyChartElement;
begin
  Show(Format(cHaloBar, ['"textBorderColor": "#ff0000", "textBorderWidth": 4']));
  solid := RedPixels(0, darkest);
  Show(Format(cHaloBar, ['"textBorderColor": "#ff0000", "textBorderWidth": 4, "textBorderType": "dashed"']));
  dashed := RedPixels(0, darkest);
  AssertTrue('the label is there', LabelEl('W8', el));
  AssertEquals('it is dashed', 'dashed', el.Caption.StrokeType);
  Show(Format(cHaloBar, ['"textBorderColor": "#ff0000", "textBorderWidth": 4, "textBorderType": "dotted"']));
  dotted := RedPixels(0, darkest);
  AssertTrue(Format('a solid halo (%d px)', [solid]), solid > 100);
  AssertTrue(Format('a dashed one is drawn (%d px)', [dashed]), dashed > 20);
  AssertTrue(Format('with gaps: %d px against %d', [dashed, solid]), dashed < solid * 0.9);
  AssertTrue(Format('a dotted one with more (%d px)', [dotted]), (dotted > 10) and (dotted < dashed));
end;

procedure TAdvChartLabelHaloTest.TestTheHaloReachesHalfItsWidthOut;
var narrow, wide, darkest: Integer;
begin
  { a stroke w wide centred on the outline shows w / 2 outside it: twice
    the width, about twice the ink outside the glyphs }
  Show(Format(cHaloBar, ['"textBorderColor": "#ff0000", "textBorderWidth": 4']));
  narrow := RedPixels(0, darkest);
  Show(Format(cHaloBar, ['"textBorderColor": "#ff0000", "textBorderWidth": 8']));
  wide := RedPixels(0, darkest);
  AssertTrue(Format('a wider stroke reaches further: %d px against %d', [wide, narrow]),
    wide > narrow * 1.5);
end;

initialization
  RegisterTest(TAdvChartLabelHaloTest);
end.
