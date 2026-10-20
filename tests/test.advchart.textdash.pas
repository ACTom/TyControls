unit test.advchart.textdash;
{$mode objfpc}{$H+}
{ A TEXT'S DASHED STROKE AND ITS PHASE [R2-F].

  tools/advchart-oracle/text-dash.js records, on ECharts 6.1, the TSpans
  zrender makes of graphic texts (plain and rich) -- the lineDash as
  written, the lineDashOffset, the pattern normalizeLineDash makes against
  the lineWidth -- and the gallery's graphic-stroke-animation sampled on the
  animation clock: a looping keyframe animation of the text's lineDash
  ([0, 200] to [200, 0]) and lineDashOffset (0 to 200). This holds the
  control's text pieces to them bit for bit.

  The picture is the painter's (the halo is the glyphs' outline, F4c), so
  what it draws is held by what the dashes mean: the gallery's text shows
  no stroke while its dash has no length, half of it at [100, 100], all of
  it at [200, 0].

  [R2-I2] And a series' own dash and phase -- lineStyle.type / dashOffset,
  itemStyle.borderType / borderDashOffset, the item's over the series' --
  on bars, a line, scatter symbols, radar rings, graph edges, lines,
  parallel lines, tree edges and map regions, and a text box's border (a
  label's borderType / borderDashOffset, a graphic text's borderDash /
  borderDashOffset): the element's pattern and phase bit for bit. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint,
     tyControls.AdvanceChart.Render, tyControls.AdvanceChart.RichText,
     tyControls.AdvanceChart.GfxEl, tyControls.AdvanceChart.Graphic,
     tyControls.AdvanceChart.Geo, tyControls.AdvanceChart.Color,
     tyControls.AdvanceChart,
     test.advchart.graphic;
type
  TAdvChartTextDashOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TGfxProbe;
    FRoot: TJSONData;
    FBad, FCompared: Integer;
    FReport, FWhere: string;
    procedure Bad(const AWhat: string);
    procedure NewChart(AW, AH: Integer);
    procedure RenderNow;
    function TextEl(const AId: string): TTyGfxEl;
    procedure CheckSpans(AEl: TTyGfxEl; ASpans: TJSONArray);
    procedure CheckStroke(const AWhat: string; const APattern: TTyDoubleArray;
      AOffset: Double; AItem: TJSONObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheGraphicTextsAreUpstreams;
    procedure TestTheGalleryAnimationIsUpstreams;
    procedure TestTheSeriesDashesAreUpstreams;
  private
    procedure CheckGradient(const AWhat: string; const AGot: TTyChartGradient;
      AWant: TJSONObject);
  end;

  { What the dashes draw. }
  TAdvChartTextDashTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TGfxProbe;
    function DarkAt(ATime: Double): Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheGalleryStrokeIsDrawnAsItsDashSays;
    procedure TestAGraphicTextsPhaseMovesItsDashes;
    procedure TestAPathsAndAMarkLinesPhaseMoveTheirDashes;
    procedure TestASeriesAndATextBoxsPhaseMoveTheirDashes;
  end;

function TyTextDashGalleryFile(const AName: string): string;

implementation

const
  cT0 = 1700000000000;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-text-dash.json';
end;

function LoadText(const APath: string): string;
var sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(APath);
    Result := sl.Text;
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

function SameBits(A, B: Double): Boolean;
begin
  Result := CompareMem(@A, @B, SizeOf(Double));
end;

{ the examples tree, walking up from the test binary }
function TyTextDashGalleryFile(const AName: string): string;
var d: string; i: Integer;
begin
  Result := '';
  d := ExtractFilePath(ParamStr(0));
  for i := 0 to 5 do
  begin
    if DirectoryExists(d + 'examples' + PathDelim + 'advchart' + PathDelim + 'gallery') then
      Exit(d + 'examples' + PathDelim + 'advchart' + PathDelim + 'gallery' + PathDelim
        + AName + '.json');
    d := d + '..' + PathDelim;
  end;
end;

{ ==================== the oracle ==================== }

procedure TAdvChartTextDashOracleTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  FRoot := GetJSON(LoadText(FixturePath));
  FChart := nil;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartTextDashOracleTest.TearDown;
begin
  FreeAndNil(FChart);
  FreeAndNil(FRoot);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartTextDashOracleTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then FReport := FReport + LineEnding + '  ' + FWhere + ': ' + AWhat;
end;

procedure TAdvChartTextDashOracleTest.NewChart(AW, AH: Integer);
begin
  FreeAndNil(FChart);
  FChart := TGfxProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.AnimationMode := camOff;
  FChart.SetBounds(0, 0, AW, AH);
end;

procedure TAdvChartTextDashOracleTest.RenderNow;
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(FChart.Width, FChart.Height, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, FChart.Width, FChart.Height), 96);
  finally
    bmp.Free;
  end;
end;

function TAdvChartTextDashOracleTest.TextEl(const AId: string): TTyGfxEl;
var
  list: TTyGfxElArray;
  i: Integer;
begin
  Result := nil;
  if FChart.GraphicView = nil then Exit;
  list := nil;
  TyGfxTraverse(FChart.GraphicView.Root, list);
  for i := 0 to High(list) do
    if (list[i].Kind = gkText) and (TyGfxIdText(list[i].Id) = AId) then Exit(list[i]);
end;

{ the text's pieces against its TSpans, in order: the words, the pattern
  normalizeLineDash makes of the piece's lineDash against its lineWidth,
  and -- where it is dashed -- the phase }
procedure TAdvChartTextDashOracleTest.CheckSpans(AEl: TTyGfxEl; ASpans: TJSONArray);
var
  rt: TTyRtResult;
  pcs: array of TTyRtPiece;
  i, k: Integer;
  sp: TJSONObject;
  pat: TTyDoubleArray;
  want: TJSONData;
  dashed: Boolean;
  wantOff: Double;
begin
  rt := TyGfxTextLayout(AEl, FChart.NewTextMeasurerForTest);
  pcs := nil;
  for i := 0 to High(rt.Pieces) do
    if rt.Pieces[i].Kind = rpkText then
    begin
      SetLength(pcs, Length(pcs) + 1);
      pcs[High(pcs)] := rt.Pieces[i];
    end;
  Inc(FCompared);
  if Length(pcs) <> ASpans.Count then
  begin
    Bad(Format('%d pieces, upstream %d TSpans', [Length(pcs), ASpans.Count]));
    Exit;
  end;
  for i := 0 to High(pcs) do
  begin
    sp := ASpans.Objects[i];
    Inc(FCompared);
    if (sp.Find('text') <> nil) and (sp.Find('text').JSONType = jtString)
      and (pcs[i].Text <> sp.Strings['text']) then
      Bad(Format('piece %d "%s", upstream "%s"', [i, pcs[i].Text, sp.Strings['text']]));
    want := sp.Find('pattern');
    dashed := pcs[i].HasStroke and TyNormalizeLineDash(pcs[i].LineDash, pcs[i].LineWidth, pat);
    Inc(FCompared);
    if (want = nil) or (want.JSONType = jtNull) then
    begin
      if dashed then Bad(Format('piece %d dashed (%s), upstream solid', [i, pcs[i].LineDash]));
      Continue;
    end;
    if not dashed or (Length(pat) <> want.Count) then
    begin
      Bad(Format('piece %d "%s" at %g, upstream %s', [i, pcs[i].LineDash, pcs[i].LineWidth,
        want.AsJSON]));
      Continue;
    end;
    for k := 0 to High(pat) do
    begin
      Inc(FCompared);
      if not SameBits(pat[k], FromHex(TJSONArray(want).Strings[k])) then
        Bad(Format('piece %d dash %d %.17g, upstream %.17g', [i, k, pat[k],
          FromHex(TJSONArray(want).Strings[k])]));
    end;
    wantOff := 0;
    if (sp.Find('lineDashOffset') <> nil) and (sp.Find('lineDashOffset').JSONType = jtString) then
      wantOff := FromHex(sp.Strings['lineDashOffset']);
    Inc(FCompared);
    if not SameBits(pcs[i].LineDashOffset, wantOff) then
      Bad(Format('piece %d phase %.17g, upstream %.17g', [i, pcs[i].LineDashOffset, wantOff]));
  end;
end;

procedure TAdvChartTextDashOracleTest.TestTheGraphicTextsAreUpstreams;
var
  cases, texts: TJSONArray;
  cs, t: TJSONObject;
  c, k: Integer;
  el: TTyGfxEl;
begin
  cases := TJSONObject(FRoot).Arrays['static'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    FWhere := cs.Strings['id'];
    NewChart(400, 300);
    FChart.SetOption('{"animation":false,' + Copy(cs.Objects['option'].AsJSON, 2, MaxInt), True);
    RenderNow;
    texts := cs.Arrays['texts'];
    for k := 0 to texts.Count - 1 do
    begin
      t := texts.Objects[k];
      el := TextEl(t.Strings['id']);
      if el = nil then
      begin
        Bad('no text ' + t.Strings['id']);
        Continue;
      end;
      CheckSpans(el, t.Arrays['spans']);
    end;
  end;
  AssertTrue(Format('comparisons made (%d)', [FCompared]), FCompared >= 40);
  if FBad > 0 then
    Fail(Format('%d of %d comparisons differ from upstream:%s', [FBad, FCompared, FReport]));
end;

procedure TAdvChartTextDashOracleTest.TestTheGalleryAnimationIsUpstreams;
var
  anim, smp: TJSONObject;
  samples: TJSONArray;
  i: Integer;
  t: Double;
  el: TTyGfxEl;
  list: TTyGfxElArray;
begin
  anim := TJSONObject(FRoot).Objects['anim'];
  AssertTrue('the gallery file', FileExists(TyTextDashGalleryFile(anim.Strings['gallery'])));
  NewChart(anim.Integers['W'], anim.Integers['H']);
  FChart.AnimationMode := camAlways;
  FChart.AnimNow := cT0;
  FChart.SetOption(LoadText(TyTextDashGalleryFile(anim.Strings['gallery'])), True);
  RenderNow;
  samples := anim.Arrays['samples'];
  for i := 0 to samples.Count - 1 do
  begin
    smp := samples.Objects[i];
    t := smp.Floats['t'];
    FWhere := Format('t=%g', [t]);
    FChart.AnimNow := cT0 + t;
    FChart.AnimTick(cT0 + t);
    list := nil;
    TyGfxTraverse(FChart.GraphicView.Root, list);
    el := nil;
    if Length(list) > 0 then
      for el in list do
        if el.Kind = gkText then Break;
    if (el = nil) or (el.Kind <> gkText) then
    begin
      Bad('no text');
      Continue;
    end;
    CheckSpans(el, smp.Arrays['spans']);
  end;
  AssertTrue(Format('comparisons made (%d)', [FCompared]), FCompared >= 60);
  if FBad > 0 then
    Fail(Format('%d of %d comparisons differ from upstream:%s', [FBad, FCompared, FReport]));
end;

{ [R2-I2] one stroke against upstream's: the pattern normalizeLineDash
  makes, and the phase (none written is 0) }
procedure TAdvChartTextDashOracleTest.CheckStroke(const AWhat: string;
  const APattern: TTyDoubleArray; AOffset: Double; AItem: TJSONObject);
var
  want: TJSONData;
  k: Integer;
  wantOff: Double;
begin
  want := AItem.Find('pattern');
  Inc(FCompared);
  if (want = nil) or (want.JSONType = jtNull) then
  begin
    if Length(APattern) > 0 then Bad(AWhat + ': dashed here, solid upstream');
    Exit;
  end;
  if Length(APattern) <> want.Count then
  begin
    Bad(Format('%s: %d dash lengths, upstream %s', [AWhat, Length(APattern), want.AsJSON]));
    Exit;
  end;
  for k := 0 to High(APattern) do
  begin
    Inc(FCompared);
    if not SameBits(APattern[k], FromHex(TJSONArray(want).Strings[k])) then
      Bad(Format('%s: dash %d %.17g, upstream %.17g', [AWhat, k, APattern[k],
        FromHex(TJSONArray(want).Strings[k])]));
  end;
  wantOff := 0;
  if (AItem.Find('lineDashOffset') <> nil) and (AItem.Find('lineDashOffset').JSONType = jtString) then
    wantOff := FromHex(AItem.Strings['lineDashOffset']);
  Inc(FCompared);
  if not SameBits(AOffset, wantOff) then
    Bad(Format('%s: phase %.17g, upstream %.17g', [AWhat, AOffset, wantOff]));
end;

{ [R2-I4] a gradient pen against the record: type, x, y, x2, y2 (linear) or
  r (radial), global, and the stops in order }
procedure TAdvChartTextDashOracleTest.CheckGradient(const AWhat: string;
  const AGot: TTyChartGradient; AWant: TJSONObject);
var
  stops, st: TJSONArray;
  q: Integer;
  c: TTyChartColor;
begin
  Inc(FCompared);
  if AWant.Strings['type'] = 'radial' then
  begin
    if AGot.Kind <> cgkRadial then
    begin
      Bad(AWhat + ': not a radial pen');
      Exit;
    end;
    if (AGot.X <> AWant.Floats['x']) or (AGot.Y <> AWant.Floats['y'])
      or (AGot.R <> AWant.Floats['r']) then
      Bad(Format('%s: radial (%g, %g, %g), upstream %s', [AWhat, AGot.X, AGot.Y, AGot.R,
        AWant.AsJSON]));
  end
  else
  begin
    if AGot.Kind <> cgkLinear then
    begin
      Bad(AWhat + ': not a linear pen');
      Exit;
    end;
    if (AGot.X <> AWant.Floats['x']) or (AGot.Y <> AWant.Floats['y'])
      or (AGot.X2 <> AWant.Floats['x2']) or (AGot.Y2 <> AWant.Floats['y2']) then
      Bad(Format('%s: linear (%g, %g, %g, %g), upstream %s', [AWhat, AGot.X, AGot.Y,
        AGot.X2, AGot.Y2, AWant.AsJSON]));
  end;
  if AGot.Global <> AWant.Booleans['global'] then Bad(AWhat + ': global differs');
  stops := AWant.Arrays['stops'];
  if Length(AGot.Stops) <> stops.Count then
  begin
    Bad(Format('%s: %d stops, upstream %d', [AWhat, Length(AGot.Stops), stops.Count]));
    Exit;
  end;
  for q := 0 to stops.Count - 1 do
  begin
    st := TJSONArray(stops.Items[q]);
    if not TyTryParseChartColor(st.Strings[1], c) or (AGot.Stops[q].Color <> c)
      or (AGot.Stops[q].Offset <> st.Floats[0]) then
      Bad(Format('%s: stop %d (%g, %s), upstream %s', [AWhat, q, AGot.Stops[q].Offset,
        IntToHex(AGot.Stops[q].Color, 8), st.AsJSON]));
  end;
end;

procedure TAdvChartTextDashOracleTest.TestTheSeriesDashesAreUpstreams;
var
  cases, items, maps: TJSONArray;
  cs, it: TJSONObject;
  c, k, j, s, idx, n, seen: Integer;
  role, what: string;
  el: TTyChartElement;
  found: Boolean;
  want: TTyChartAnimRole;
  rt: TTyRtResult;
  bx: TTyRtPieceArray;
  pat: TTyDoubleArray;
  gel: TTyGfxEl;
  wantColour: TTyChartColor;

  procedure Bordered(const APieces: TTyRtPieceArray);
  var q: Integer;
  begin
    bx := nil;
    for q := 0 to High(APieces) do
      if (APieces[q].Kind = rpkRect) and APieces[q].HasStroke then
      begin
        SetLength(bx, Length(bx) + 1);
        bx[High(bx)] := APieces[q];
      end;
  end;

begin
  maps := TJSONObject(FRoot).Arrays['maps'];
  for k := 0 to maps.Count - 1 do
    AssertTrue('the map registers', TyChartRegisterMap(maps.Objects[k].Strings['name'],
      maps.Objects[k].Strings['text']));
  try
    cases := TJSONObject(FRoot).Arrays['series'];
    seen := 0;
    for c := 0 to cases.Count - 1 do
    begin
      cs := cases.Objects[c];
      FWhere := cs.Strings['id'];
      NewChart(400, 300);
      FChart.SetOption('{"animation":false,' + Copy(cs.Objects['option'].AsJSON, 2, MaxInt), True);
      RenderNow;
      items := cs.Arrays['items'];
      Inc(FCompared);
      if items.Count = 0 then Bad('no strokes upstream');
      for k := 0 to items.Count - 1 do
      begin
        it := items.Objects[k];
        role := it.Strings['role'];
        s := it.Integers['s'];
        if it.Find('i').JSONType = jtNumber then idx := it.Integers['i'] else idx := -1;
        what := Format('%s s%d %s', [role, s, it.Find('i').AsJSON]);
        if (role = 'labelBox') or (role = 'graphicBox') then
        begin
          { a text's box: its stroked rects, the block's first }
          if role = 'graphicBox' then
          begin
            gel := TextEl(it.Strings['i']);
            if gel = nil then
            begin
              Bad(what + ': no such text');
              Continue;
            end;
            rt := TyGfxTextLayout(gel, FChart.NewTextMeasurerForTest);
            Bordered(rt.Pieces);
          end
          else
          begin
            found := False;
            for j := 0 to FChart.List.Count - 1 do
            begin
              el := FChart.List.Element(j);
              if (el.Anim.Role = carLabel) and (el.Datum.SeriesIndex = s)
                and (el.Datum.DataIndex = idx) then
              begin
                found := True;
                Break;
              end;
            end;
            if not found then
            begin
              Bad(what + ': no label');
              Continue;
            end;
            Bordered(el.Caption.RtPieces);
          end;
          n := it.Integers['n'];
          Inc(FCompared);
          if n > High(bx) then
          begin
            Bad(Format('%s: box %d, here %d bordered rects', [what, n, Length(bx)]));
            Continue;
          end;
          Inc(FCompared);
          if not SameBits(bx[n].LineWidth, FromHex(it.Strings['lineWidth'])) then
            Bad(Format('%s box %d: width %g, upstream %g', [what, n, bx[n].LineWidth,
              FromHex(it.Strings['lineWidth'])]));
          if not TyNormalizeLineDash(bx[n].BorderDash, bx[n].LineWidth, pat) then pat := nil;
          CheckStroke(Format('%s box %d', [what, n]), pat, bx[n].BorderDashOffset, it);
          Inc(seen);
          Continue;
        end;
        { [R2-I3] an SVG map's own stroked shape: the n-th, in the list's
          order, of the drawn shapes that stroke }
        if role = 'svg' then
        begin
          found := False;
          n := 0;
          for j := 0 to FChart.List.Count - 1 do
          begin
            el := FChart.List.Element(j);
            if (el.ZrHit.SvgNode <= 0) or el.ZrHit.SvgLabel or (el.Caption.FontSizeLogical > 0)
              or not (el.Style.StrokeWidthLogical > 0) or ((el.Style.StrokeColor shr 24) = 0) then
              Continue;
            if n = idx then
            begin
              found := True;
              Break;
            end;
            Inc(n);
          end;
          Inc(FCompared);
          if not found then
          begin
            Bad(what + ': no such shape');
            Continue;
          end;
          Inc(FCompared);
          if not SameBits(el.Style.StrokeWidthLogical, FromHex(it.Strings['lineWidth'])) then
            Bad(Format('%s: width %g, upstream %g', [what, el.Style.StrokeWidthLogical,
              FromHex(it.Strings['lineWidth'])]));
          CheckStroke(what, el.Style.DashLogical, el.Style.DashOffsetLogical, it);
          Inc(seen);
          Continue;
        end;
        if role = 'bar' then want := carBar
        else if role = 'line' then want := carLineRun
        else if role = 'symbol' then want := carSymbol
        { [R2-I3] a graph node's Symbol path }
        else if role = 'node' then want := carSymbol
        else if role = 'radar' then want := carRadarLine
        else if role = 'edge' then want := carGraphEdge
        else if role = 'lines' then want := carLinesLine
        else if role = 'parallel' then want := carParallelLine
        else if role = 'treeEdge' then want := carTreeEdge
        else if role = 'region' then want := carMapRegion
        else
        begin
          Bad(what + ': a role the test does not know');
          Continue;
        end;
        found := False;
        for j := 0 to FChart.List.Count - 1 do
        begin
          el := FChart.List.Element(j);
          if (el.Anim.Role <> want) or (el.Anim.Series <> s) then Continue;
          if (idx >= 0) and (el.Anim.Index <> idx) then Continue;
          found := True;
          Break;
        end;
        Inc(FCompared);
        if not found then
        begin
          Bad(what + ': no such element');
          Continue;
        end;
        Inc(FCompared);
        if not SameBits(el.Style.StrokeWidthLogical, FromHex(it.Strings['lineWidth'])) then
          Bad(Format('%s: width %g, upstream %g', [what, el.Style.StrokeWidthLogical,
            FromHex(it.Strings['lineWidth'])]));
        CheckStroke(what, el.Style.DashLogical, el.Style.DashOffsetLogical, it);
        { [R2-I3] the pen's colour, where the record says it }
        if (it.Find('stroke') <> nil) and (it.Find('stroke').JSONType = jtString) then
        begin
          Inc(FCompared);
          if not TyTryParseChartColor(it.Strings['stroke'], wantColour) then
            Bad(what + ': cannot read the stroke ' + it.Strings['stroke'])
          else if el.Style.StrokeColor <> wantColour then
            Bad(Format('%s: stroke %s, upstream %s', [what, IntToHex(el.Style.StrokeColor, 8),
              it.Strings['stroke']]));
        end;
        { [R2-I4] a pen that is a gradient: its kind, its numbers, its stops }
        if (it.Find('strokeGrad') <> nil) and (it.Find('strokeGrad').JSONType = jtObject) then
          CheckGradient(what, el.Style.StrokeGradient, it.Objects['strokeGrad']);
        Inc(seen);
      end;
    end;
  finally
    for k := 0 to maps.Count - 1 do TyChartUnregisterMap(maps.Objects[k].Strings['name']);
  end;
  AssertTrue(Format('strokes compared (%d)', [seen]), seen >= 25);
  if FBad > 0 then
    Fail(Format('%d of %d comparisons differ from upstream:%s', [FBad, FCompared, FReport]));
end;

{ ==================== the picture ==================== }

procedure TAdvChartTextDashTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := nil;
end;

procedure TAdvChartTextDashTest.TearDown;
begin
  FreeAndNil(FChart);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

{ the dark pixels of a frame at ATime after the option went in }
function TAdvChartTextDashTest.DarkAt(ATime: Double): Integer;
var
  bmp: TBGRABitmap;
  x, y: Integer;
  p: TBGRAPixel;
begin
  Result := 0;
  FChart.AnimNow := cT0 + ATime;
  FChart.AnimTick(cT0 + ATime);
  bmp := TBGRABitmap.Create(FChart.Width, FChart.Height, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, FChart.Width, FChart.Height), 96);
    for y := 0 to bmp.Height - 1 do
      for x := 0 to bmp.Width - 1 do
      begin
        p := bmp.GetPixel(x, y);
        if (p.red < 160) and (p.green < 160) and (p.blue < 160) then Inc(Result);
      end;
  finally
    bmp.Free;
  end;
end;

{ THE ACCEPTANCE CASE: the gallery's stroke animation. Its fill is
  transparent until 70 %, so the dark ink is the stroke: none while the
  dash has no length ([0, 200] at 0), about half the outline at
  [100, 100], all of it at [200, 0]. Before the phase and the text's own
  dash were read, the stroke was the whole outline all along. }
procedure TAdvChartTextDashTest.TestTheGalleryStrokeIsDrawnAsItsDashSays;
var
  f: string;
  none, half, full: Integer;
begin
  f := TyTextDashGalleryFile('graphic-stroke-animation');
  AssertTrue('the gallery file', FileExists(f));
  FChart := TGfxProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, 800, 500);
  FChart.AnimationMode := camAlways;
  FChart.AnimNow := cT0;
  FChart.SetOption(LoadText(f), True);
  none := DarkAt(0);
  half := DarkAt(1050);
  full := DarkAt(2100);
  AssertTrue(Format('the whole outline at [200, 0] (%d px)', [full]), full > 500);
  AssertTrue(Format('nothing at [0, 200]: %d px against %d', [none, full]), none < full div 20);
  AssertTrue(Format('part of it at [100, 100]: %d px between %d and %d', [half, none, full]),
    (half > full div 5) and (half < full * 9 div 10));
end;

{ a graphic text's lineDashOffset: a whole period is the dashes unmoved,
  half a period moves them }
procedure TAdvChartTextDashTest.TestAGraphicTextsPhaseMovesItsDashes;
var
  a, b, c: TBGRABitmap;
  x, y, same, diff: Integer;

  function Frame(AOffset: Integer): TBGRABitmap;
  begin
    FreeAndNil(FChart);
    FChart := TGfxProbe.Create(FForm);
    FChart.Parent := FForm;
    FChart.Controller := FCtl;
    FChart.SetBounds(0, 0, 400, 200);
    FChart.AnimationMode := camOff;
    FChart.SetOption('{"graphic":[{"type":"text","x":20,"y":40,"style":{"text":"Dash",'
      + '"fontSize":60,"fontWeight":"bold","fill":"transparent","stroke":"#000",'
      + '"lineWidth":2,"lineDash":[12,12],"lineDashOffset":' + IntToStr(AOffset) + '}}]}', True);
    Result := TBGRABitmap.Create(400, 200, BGRA(255, 255, 255, 255));
    FChart.Render(Result.Canvas, Rect(0, 0, 400, 200), 96);
  end;

begin
  a := Frame(0);
  b := nil;
  c := nil;
  try
    b := Frame(24);
    c := Frame(12);
    same := 0;
    diff := 0;
    for y := 0 to 199 do
      for x := 0 to 399 do
      begin
        if a.GetPixel(x, y) <> b.GetPixel(x, y) then Inc(same);
        if a.GetPixel(x, y) <> c.GetPixel(x, y) then Inc(diff);
      end;
    AssertEquals('a whole period is the dashes unmoved', 0, same);
    AssertTrue(Format('half a period moves them (%d px)', [diff]), diff > 200);
  finally
    a.Free;
    b.Free;
    c.Free;
  end;
end;

{ [R2-F] THE PAINTER'S PHASE ON A PATH: a graphic polyline's lineDashOffset
  and a markLine's lineStyle.dashOffset (getLineDash hands both to the
  canvas) -- a whole period is the dashes unmoved, half of one moves them }
procedure TAdvChartTextDashTest.TestAPathsAndAMarkLinesPhaseMoveTheirDashes;
const
  cPath = '{"graphic":[{"type":"polyline","shape":{"points":[[20,50],[380,50]]},'
    + '"style":{"stroke":"#000","lineWidth":4,"lineDash":[12,12],"lineDashOffset":%d,"fill":null}}]}';
  cMark = '{"animation":false,"xAxis":{"type":"category","data":["a","b"]},"yAxis":{"max":10},'
    + '"series":[{"type":"line","data":[1,2],"lineStyle":{"color":"#ffffff"},"symbol":"none",'
    + '"markLine":{"symbol":"none","label":{"show":false},"lineStyle":{"color":"#000","width":4,'
    + '"type":[12,12],"dashOffset":%d},"data":[{"yAxis":5}]}}]}';

  function Frame(const AOpt: string; AOffset: Integer): TBGRABitmap;
  begin
    FreeAndNil(FChart);
    FChart := TGfxProbe.Create(FForm);
    FChart.Parent := FForm;
    FChart.Controller := FCtl;
    FChart.SetBounds(0, 0, 400, 200);
    FChart.AnimationMode := camOff;
    FChart.SetOption(Format(AOpt, [AOffset]), True);
    Result := TBGRABitmap.Create(400, 200, BGRA(255, 255, 255, 255));
    FChart.Render(Result.Canvas, Rect(0, 0, 400, 200), 96);
  end;

  procedure Check(const AWhat, AOpt: string);
  var
    a, b, c: TBGRABitmap;
    x, y, same, diff: Integer;
  begin
    a := Frame(AOpt, 0);
    b := nil;
    c := nil;
    try
      b := Frame(AOpt, 24);
      c := Frame(AOpt, 12);
      same := 0;
      diff := 0;
      for y := 0 to 199 do
        for x := 0 to 399 do
        begin
          if a.GetPixel(x, y) <> b.GetPixel(x, y) then Inc(same);
          if a.GetPixel(x, y) <> c.GetPixel(x, y) then Inc(diff);
        end;
      AssertEquals(AWhat + ': a whole period is the dashes unmoved', 0, same);
      AssertTrue(Format('%s: half a period moves them (%d px)', [AWhat, diff]), diff > 200);
    finally
      a.Free;
      b.Free;
      c.Free;
    end;
  end;

begin
  Check('a polyline', cPath);
  Check('a markLine', cMark);
end;

{ [R2-I2] A SERIES' OWN PHASE AND A TEXT BOX'S: a bar's
  itemStyle.borderDashOffset, a line's lineStyle.dashOffset, a graphic
  text's box (borderDash / borderDashOffset) and a label's box (borderType /
  borderDashOffset) -- a whole period is the dashes unmoved, half of one
  moves them }
procedure TAdvChartTextDashTest.TestASeriesAndATextBoxsPhaseMoveTheirDashes;
const
  cBar = '{"animation":false,"xAxis":{"type":"category","data":["a"],"show":false},'
    + '"yAxis":{"max":10,"show":false},"series":[{"type":"bar","barWidth":120,"data":[8],'
    + '"itemStyle":{"color":"#ffffff","borderColor":"#000","borderWidth":4,"borderType":[12,12],'
    + '"borderDashOffset":%d}}]}';
  cLine = '{"animation":false,"xAxis":{"type":"category","data":["a","b"],"show":false},'
    + '"yAxis":{"max":10,"show":false},"series":[{"type":"line","symbol":"none","data":[5,5],'
    + '"lineStyle":{"color":"#000","width":4,"type":[12,12],"dashOffset":%d}}]}';
  cBox = '{"graphic":[{"type":"text","x":40,"y":30,"style":{"text":"Box","fontSize":40,'
    + '"fill":"transparent","padding":30,"borderColor":"#000","borderWidth":4,'
    + '"borderDash":[12,12],"borderDashOffset":%d}}]}';
  cLabelBox = '{"animation":false,"xAxis":{"type":"category","data":["a"],"show":false},'
    + '"yAxis":{"max":10,"show":false},"series":[{"type":"bar","barWidth":4,"data":[2],'
    + '"itemStyle":{"color":"#ffffff"},"label":{"show":true,"position":"top","fontSize":30,'
    + '"color":"transparent","padding":20,"borderColor":"#000","borderWidth":4,'
    + '"borderType":[12,12],"borderDashOffset":%d}}]}';

  function Frame(const AOpt: string; AOffset: Integer): TBGRABitmap;
  begin
    FreeAndNil(FChart);
    FChart := TGfxProbe.Create(FForm);
    FChart.Parent := FForm;
    FChart.Controller := FCtl;
    FChart.SetBounds(0, 0, 400, 200);
    FChart.AnimationMode := camOff;
    FChart.SetOption(Format(AOpt, [AOffset]), True);
    Result := TBGRABitmap.Create(400, 200, BGRA(255, 255, 255, 255));
    FChart.Render(Result.Canvas, Rect(0, 0, 400, 200), 96);
  end;

  procedure Check(const AWhat, AOpt: string);
  var
    a, b, c: TBGRABitmap;
    x, y, same, diff: Integer;
  begin
    a := Frame(AOpt, 0);
    b := nil;
    c := nil;
    try
      b := Frame(AOpt, 24);
      c := Frame(AOpt, 12);
      same := 0;
      diff := 0;
      for y := 0 to 199 do
        for x := 0 to 399 do
        begin
          if a.GetPixel(x, y) <> b.GetPixel(x, y) then Inc(same);
          if a.GetPixel(x, y) <> c.GetPixel(x, y) then Inc(diff);
        end;
      AssertEquals(AWhat + ': a whole period is the dashes unmoved', 0, same);
      AssertTrue(Format('%s: half a period moves them (%d px)', [AWhat, diff]), diff > 200);
    finally
      a.Free;
      b.Free;
      c.Free;
    end;
  end;

begin
  Check('a bar', cBar);
  Check('a line', cLine);
  Check('a graphic text''s box', cBox);
  Check('a label''s box', cLabelBox);
end;

initialization
  RegisterTest(TAdvChartTextDashOracleTest);
  RegisterTest(TAdvChartTextDashTest);
end.
