unit test.advchart.sankeyroamtween;
{$mode objfpc}{$H+}
{ A SANKEY'S VIEW GROUP TWEENS in a setOption that changes its zoom /
  center, held to upstream. [R6-C]

  tests/fixtures/advchart-sankey-roam-tween.json, from the real ECharts 6.1
  build under the hand-driven clock (tools/advchart-oracle/
  sankey-roam-tween.js): SankeyView._updateViewCoordSys updates the series'
  view group past its first render (updateProps at the series' update
  timing).

  TestTheViewGroupAsUpstream: at every sample the group's x / y / scaleX /
  scaleY (the series' 'viewGroup' proxy, bit for bit) and every node's box
  as the frame draws it (sorted, 1e-9). }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Shape,
     tyControls.AdvanceChart.Paint, tyControls.AdvanceChart.Measure,
     tyControls.AdvanceChart.Anim, tyControls.AdvanceChart.AnimView,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TSrtProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function Frame: TTyPaintList;
  end;

  TAdvChartSankeyRoamTweenTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FMeasure: TJSONData;
    FBmp: TBGRABitmap;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheViewGroupAsUpstream;
  end;

implementation

const
  cW = 400;
  cH = 300;

function TSrtProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TSrtProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TSrtProbe.Frame: TTyPaintList;
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

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

function Hex(A: Double): string;
var q: QWord;
begin
  Move(A, q, SizeOf(q));
  Result := LowerCase(IntToHex(q, 16));
end;

procedure TAdvChartSankeyRoamTweenTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  FMeasure := LoadJson('advchart-text-style.json');
end;

procedure TAdvChartSankeyRoamTweenTest.TearDown;
begin
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FBmp);
  FreeAndNil(FMeasure);
  inherited TearDown;
end;

function Box4(X, Y, W, H: Double): string;
begin
  Result := Format('%.9f %.9f %.9f %.9f', [X, Y, W, H]);
end;

procedure TAdvChartSankeyRoamTweenTest.TestTheViewGroupAsUpstream;
const
  cKeys: array[0..3] of string = ('x', 'y', 'scaleX', 'scaleY');
var
  fix: TJSONData;
  cs, smp, grp, nodes: TJSONArray;
  c, sm: TJSONObject;
  i, s, k, nBad, nCmp, moving: Integer;
  chart: TSrtProbe;
  t0, gap, t, kk: Double;
  p: TTyChartAnimProxy;
  v: TTyAnimValue;
  got, want: string;
  frm: TTyPaintList;
  el: TTyChartElement;
  b: TTyRectF;
  wl, gl: TStringList;
  bad: string;
  rest: TTyChartAnim;
begin
  fix := LoadJson('advchart-sankey-roam-tween.json');
  wl := TStringList.Create;
  gl := TStringList.Create;
  nBad := 0;
  nCmp := 0;
  moving := 0;
  bad := '';
  try
    t0 := TJSONObject(fix).Objects['clock'].Floats['T0'];
    gap := TJSONObject(fix).Objects['clock'].Floats['gap'];
    cs := TJSONObject(fix).Arrays['charts'];
    for i := 0 to cs.Count - 1 do
    begin
      c := cs.Objects[i];
      chart := TSrtProbe.Create(FForm);
      try
        chart.Parent := FForm;
        chart.Controller := FCtl;
        chart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
          TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
          TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
        chart.AnimationMode := camAlways;
        chart.AnimNow := t0;
        chart.Option := c.Arrays['steps'].Objects[0].AsJSON;
        chart.SetBounds(0, 0, cW, cH);
        chart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
        kk := 16;
        while kk <= 5000 do
        begin
          chart.AnimTick(t0 + kk);
          kk := kk + 250;
        end;
        t := t0 + gap;
        chart.AnimNow := t;
        AssertTrue(c.Strings['id'] + ' merges', chart.SetOption(c.Arrays['steps'].Objects[1].AsJSON,
          '{"notMerge":false}'));
        smp := c.Arrays['samples'];
        for s := 0 to smp.Count - 1 do
        begin
          sm := smp.Objects[s];
          if s > 0 then chart.AnimTick(t + sm.Floats['t']);
          FBmp.Fill(BGRA(255, 255, 255, 255));
          chart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
          grp := sm.Arrays['group'];
          { THE GROUP: its proxy where it tweens; at rest none, the group at
            its final values }
          p := chart.AnimFindProxy(0, -1, 'viewGroup');
          { (no proxy: the group at rest, as the series' elements carry it) }
          frm := chart.Frame;
          rest := Default(TTyChartAnim);
          for k := 0 to frm.Count - 1 do
            if (frm.Element(k).Anim.Role = carSankeyClip) and (frm.Element(k).Anim.Series = 0) then
            begin
              rest := frm.Element(k).Anim;
              Break;
            end;
          for k := 0 to 3 do
          begin
            Inc(nCmp);
            if p <> nil then
            begin
              v := p.GetAnimProp(cKeys[k]);
              if v.Kind = avkNumber then got := Hex(v.Num) else got := '(none)';
            end
            else
              case k of
                0: got := Hex(rest.VX);
                1: got := Hex(rest.VY);
                2: got := Hex(rest.VSX);
              else
                got := Hex(rest.VSY);
              end;
            if got <> grp.Strings[k] then
            begin
              Inc(nBad);
              if Length(bad) < 3000 then
                bad := bad + LineEnding + Format('  %s t=%s %s: %s here, upstream %g', [c.Strings['id'],
                  sm.Strings['t'], cKeys[k], got, FromHex(grp.Strings[k])]);
            end;
          end;
          if (p <> nil) and not p.AtFinal then Inc(moving);
          { THE NODES as drawn }
          nodes := sm.Arrays['nodes'];
          wl.Clear;
          for k := 0 to nodes.Count - 1 do
            wl.Add(Box4(FromHex(nodes.Arrays[k].Strings[0]), FromHex(nodes.Arrays[k].Strings[1]),
              FromHex(nodes.Arrays[k].Strings[2]), FromHex(nodes.Arrays[k].Strings[3])));
          gl.Clear;
          frm := chart.Frame;
          for k := 0 to frm.Count - 1 do
          begin
            el := frm.Element(k);
            if (el.Datum.SeriesIndex <> 0) or el.Datum.IsEdge or (el.Anim.Role <> carSankeyClip) then Continue;
            if not (el.Shape.Kind in [cskRect, cskRoundRect]) then Continue;
            { a node fills; its label's box does not }
            if not el.Style.HasFill or ((el.Style.FillColor shr 24) = 0) then Continue;
            b := TyShapeBounds(el.Shape);
            gl.Add(Box4(b.Left, b.Top, b.Right - b.Left, b.Bottom - b.Top));
          end;
          wl.Sort;
          gl.Sort;
          Inc(nCmp);
          if wl.Text <> gl.Text then
          begin
            Inc(nBad);
            if Length(bad) < 3000 then
              bad := bad + LineEnding + Format('  %s t=%s nodes: %s here, upstream %s', [c.Strings['id'],
                sm.Strings['t'], Copy(gl.CommaText, 1, 120), Copy(wl.CommaText, 1, 120)]);
          end;
        end;
      finally
        chart.Free;
      end;
    end;
  finally
    wl.Free;
    gl.Free;
    fix.Free;
  end;
  AssertTrue(Format('%d of %d differ from upstream:%s', [nBad, nCmp, bad]), nBad = 0);
  AssertTrue('samples in flight', moving >= 12);
end;

initialization
  RegisterTest(TAdvChartSankeyRoamTweenTest);
end.
