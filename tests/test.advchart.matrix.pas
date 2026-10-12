unit test.advchart.matrix;
{$mode objfpc}{$H+}
{ THE MATRIX COORDINATE SYSTEM, part one (D12 MX1, batch 145), held to what
  ECharts 6.1 lays out and draws.

  tools/advchart-oracle/matrix.js runs the real dist and records, per
  matrix: the box after the init merge, the rect, both header trees (every
  cell's kind, ordinal, level, first leaf, locator pair, span, unit and
  rect, its value after the unique renaming, every level's unit), every
  element of the matrix's view in order (shape, style, z2, and a cell
  label's anchor, lines and clip), and probes through dataToLayout and
  dataToPoint; per heatmap and scatter on a matrix, every row's cell or
  point. Text is measured with zrender's width table on both sides.

  THREE LEVELS:
  1. the pure unit -- TTyMatrix from the option, laid out on 800 x 600,
     drawn by TyBuildMatrix with a sentinel ink -- bit for bit;
  2. the chart -- the matrices the control built (a collecting tree's
     names from its series), the heatmap cells and the scatter symbols;
  3. a few rules said directly. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.FontUnits,
     tyControls.AdvChart.Types, tyControls.AdvChart.Option,
     tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Color, tyControls.AdvChart.Coord,
     tyControls.AdvChart.Matrix, tyControls.AdvChart.Export, tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TMxProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
    procedure Hover(AX, AY: Integer);
  end;

  TAdvChartMatrixOracleTest = class(TTestCase)
  private
    FRoot: TJSONData;
    FOpt: TTyChartOption;
    FMeas: ITyTextMeasurer;
    FBad, FCompared, FCells, FEls, FLabels, FProbes: Integer;
    FReport, FName: string;
    procedure Miss(const AWhat: string);
    procedure SameD(const AWhat: string; AGot, AWant: Double);
    procedure SameH(const AWhat: string; AGot: Double; AWant: TJSONData);
    function OptionOf(ACase: TJSONObject): TJSONObject;
    function Pure(ACase: TJSONObject): Boolean;
    procedure CheckTrees(M: TTyMatrix; AM: TJSONObject);
    procedure CheckProbes(M: TTyMatrix; AM: TJSONObject);
    procedure CheckPicture(M: TTyMatrix; AM: TJSONObject);
    procedure RunPure(AWhat: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheTreesAndTheLayoutAsUpstream;
    procedure TestThePositionsAsUpstream;
    procedure TestThePictureAsUpstream;
  end;

  TAdvChartMatrixChartTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TMxProbe;
    FBmp: TBGRABitmap;
    FRoot: TJSONData;
    FBad, FCompared, FHeat, FSym: Integer;
    FReport, FName: string;
    procedure Miss(const AWhat: string);
    procedure LoadOption(const AJson: string);
    procedure CheckFill(const AWhat: string; const AEl: TTyChartElement;
      const AFill: string);
    procedure RunSeries(AGallery: Boolean);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheSeriesAsUpstream;
    procedure TestTheGallerySeriesAsUpstream;
    procedure TestEveryMatrixGalleryEntryRenders;
    procedure TestTheMatrixDrawsUnderTheSeries;
    procedure TestAPieOnAMatrixIsNotBuiltYet;
    procedure TestThePPIScalesThePixels;
    procedure TestHoveringAMatrixSeriesRaisesNothing;
    procedure TestAHugeMatrixIsRefusedNotWalked;
  end;

implementation

const
  cW = 800;
  cH = 600;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-matrix.json';
end;

function GalleryPath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'examples'
    + PathDelim + 'advchart' + PathDelim + 'gallery' + PathDelim + AName + '.json';
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

function H(A: TJSONData): Double;
begin
  if (A = nil) or (A.JSONType <> jtString) then Exit(NaN);
  Result := FromHex(A.AsString);
end;

function Bits(A: Double): QWord;
begin
  Move(A, Result, SizeOf(Result));
end;

function SameBits(A, B: Double): Boolean;
begin
  if IsNan(A) or IsNan(B) then Exit(IsNan(A) and IsNan(B));
  Result := Bits(A) = Bits(B);
end;

function Fmt(A: Double): string;
begin
  if IsNan(A) then Exit('NaN');
  Result := FloatToStrF(A, ffGeneral, 17, 0, DefaultFormatSettings);
end;

function TestInk: TTyMatrixInk;
begin
  Result.CellBorder := $FF0A0B0C;
  Result.Divider := $FF0D0E0F;
  Result.OuterBorder := $FF101112;
  Result.LabelColour := $FF131415;
end;

{ a fixture colour as the port should hold it: upstream's tokens are the
  sentinel ink, 'none' and null nothing (alpha 0) }
function WantColour(const S: string; ALabel: Boolean): TTyChartColor;
begin
  Result := 0;
  if (S = '') or (S = 'none') then Exit;
  if S = '#cfd2d7' then Exit(TestInk.CellBorder);
  if S = '#b7b9be' then Exit(TestInk.Divider);
  if S = '#54555a' then
  begin
    if ALabel then Exit(TestInk.LabelColour) else Exit(TestInk.OuterBorder);
  end;
  if not TyTryParseChartColor(S, Result) then Result := 0;
end;

function StrIn(AObj: TJSONObject; const AKey: string): string;
var d: TJSONData;
begin
  Result := '';
  d := AObj.Find(AKey);
  if (d <> nil) and (d.JSONType = jtString) then Result := d.AsString;
end;

function PxOfFont(const AFont: string): Double;
var p, q: Integer;
begin
  Result := 12;
  p := Pos('px', AFont);
  if p <= 1 then Exit;
  q := p - 1;
  while (q > 1) and (AFont[q - 1] in ['0'..'9', '.']) do Dec(q);
  Result := StrToFloatDef(Copy(AFont, q, p - q), 12, DefaultFormatSettings);
end;

{ ==================== the probe ==================== }

function TMxProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TMxProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TMxProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

procedure TMxProbe.Hover(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

{ ==================== the pure unit ==================== }

procedure TAdvChartMatrixOracleTest.SetUp;
var m: TJSONObject;
begin
  inherited SetUp;
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  FRoot := LoadJson(FixturePath);
  m := TJSONObject(FRoot).Objects['measure'];
  FMeas := TZrSsrMeasurer.Create(m.Arrays['ratio'], m.Integers['firstCode']);
  FOpt := TTyChartOption.Create;
  FBad := 0;
  FCompared := 0;
  FCells := 0;
  FEls := 0;
  FLabels := 0;
  FProbes := 0;
  FReport := '';
end;

procedure TAdvChartMatrixOracleTest.TearDown;
begin
  FMeas := nil;
  FreeAndNil(FOpt);
  FreeAndNil(FRoot);
  inherited TearDown;
end;

procedure TAdvChartMatrixOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartMatrixOracleTest.SameD(const AWhat: string; AGot, AWant: Double);
begin
  Inc(FCompared);
  if not SameBits(AGot, AWant) then
    Miss(Format('%s: %s here, %s upstream', [AWhat, Fmt(AGot), Fmt(AWant)]));
end;

procedure TAdvChartMatrixOracleTest.SameH(const AWhat: string; AGot: Double;
  AWant: TJSONData);
begin
  SameD(AWhat, AGot, H(AWant));
end;

function TAdvChartMatrixOracleTest.OptionOf(ACase: TJSONObject): TJSONObject;
var d: TJSONData;
begin
  d := ACase.Find('gallery');
  if (d <> nil) and (d.JSONType = jtString) then
    Result := TJSONObject(LoadJson(GalleryPath(d.AsString)))
  else
    Result := TJSONObject(ACase.Objects['option'].Clone);
end;

{ a case the pure unit can lay out on its own: no tree collects from series }
function TAdvChartMatrixOracleTest.Pure(ACase: TJSONObject): Boolean;
var
  ms: TJSONArray;
  k: Integer;
begin
  Result := True;
  ms := ACase.Arrays['matrices'];
  for k := 0 to ms.Count - 1 do
    if ms.Objects[k].Arrays['dims'].Objects[0].Booleans['collect']
      or ms.Objects[k].Arrays['dims'].Objects[1].Booleans['collect'] then Exit(False);
end;

procedure TAdvChartMatrixOracleTest.CheckTrees(M: TTyMatrix; AM: TJSONObject);
var
  di, k, j: Integer;
  dim, cj, lv, rc: TJSONObject;
  cells, levels: TJSONArray;
  d: TTyMatrixDim;
  c: TTyMatrixCell;
  w: string;
begin
  rc := AM.Objects['rect'];
  SameH('rect x', M.Rect.X, rc.Find('x'));
  SameH('rect y', M.Rect.Y, rc.Find('y'));
  SameH('rect width', M.Rect.W, rc.Find('width'));
  SameH('rect height', M.Rect.H, rc.Find('height'));
  Inc(FCompared);
  if M.Z <> AM.Integers['z'] then Miss(Format('z %d, upstream %d', [M.Z, AM.Integers['z']]));
  for di := 0 to 1 do
  begin
    dim := AM.Arrays['dims'].Objects[di];
    d := M.Dims[di];
    w := Format('dim %d', [di]);
    Inc(FCompared, 3);
    if d.Show <> dim.Booleans['show'] then Miss(w + ': show differs');
    if d.LeafCount <> dim.Integers['leaves'] then
      Miss(Format('%s: %d leaves, upstream %d', [w, d.LeafCount, dim.Integers['leaves']]));
    levels := dim.Arrays['levels'];
    if d.LevelCount <> levels.Count then
    begin
      Miss(Format('%s: %d levels, upstream %d', [w, d.LevelCount, levels.Count]));
      Continue;
    end;
    for k := 0 to levels.Count - 1 do
    begin
      lv := levels.Objects[k];
      SameH(Format('%s level %d xy', [w, k]), d.Levels[k].XY, lv.Find('xy'));
      SameH(Format('%s level %d wh', [w, k]), d.Levels[k].WH, lv.Find('wh'));
    end;
    cells := dim.Arrays['cells'];
    Inc(FCompared);
    if d.CellCount <> cells.Count then
    begin
      Miss(Format('%s: %d cells, upstream %d', [w, d.CellCount, cells.Count]));
      Continue;
    end;
    for k := 0 to cells.Count - 1 do
    begin
      Inc(FCells);
      cj := cells.Objects[k];
      c := d.Cells[k];
      w := Format('dim %d cell %d', [di, k]);
      Inc(FCompared, 8);
      if (c.Kind = tmkLeaf) <> (cj.Strings['kind'] = 'leaf') then Miss(w + ': the kind differs');
      if c.Ordinal <> cj.Integers['ordinal'] then Miss(w + ': the ordinal differs');
      if c.Level <> cj.Integers['level'] then Miss(w + ': the level differs');
      if c.FirstLeaf <> cj.Integers['firstLeaf'] then Miss(w + ': the first leaf differs');
      for j := 0 to 1 do
      begin
        if c.Id[j] <> cj.Arrays['id'].Integers[j] then
          Miss(Format('%s: id[%d] %d, upstream %d', [w, j, c.Id[j], cj.Arrays['id'].Integers[j]]));
        if c.Span[j] <> cj.Arrays['span'].Integers[j] then
          Miss(Format('%s: span[%d] %d, upstream %d', [w, j, c.Span[j], cj.Arrays['span'].Integers[j]]));
      end;
      if c.Value <> StrIn(cj, 'value') then
        Miss(Format('%s: value "%s", upstream "%s"', [w, c.Value, StrIn(cj, 'value')]));
      SameH(w + ' xy', c.XY, cj.Find('xy'));
      SameH(w + ' wh', c.WH, cj.Find('wh'));
      rc := cj.Objects['rect'];
      SameH(w + ' rect x', c.Rect.X, rc.Find('x'));
      SameH(w + ' rect y', c.Rect.Y, rc.Find('y'));
      SameH(w + ' rect width', c.Rect.W, rc.Find('width'));
      SameH(w + ' rect height', c.Rect.H, rc.Find('height'));
    end;
  end;
end;

procedure TAdvChartMatrixOracleTest.CheckProbes(M: TTyMatrix; AM: TJSONObject);
var
  probes: TJSONArray;
  pr, rc: TJSONObject;
  inp: TJSONArray;
  k: Integer;
  r: TTyXYWH;
  p: TTyPointF;
  w: string;
begin
  probes := AM.Arrays['probes'];
  for k := 0 to probes.Count - 1 do
  begin
    Inc(FProbes);
    pr := probes.Objects[k];
    inp := pr.Arrays['input'];
    w := 'probe ' + inp.AsJSON;
    M.DataToLayoutXYWH(M.ParseCoord(0, inp.Items[0]), M.ParseCoord(1, inp.Items[1]), r);
    rc := pr.Objects['rect'];
    SameH(w + ' x', r.X, rc.Find('x'));
    SameH(w + ' y', r.Y, rc.Find('y'));
    SameH(w + ' width', r.W, rc.Find('width'));
    SameH(w + ' height', r.H, rc.Find('height'));
    p := M.DataToPoint([M.ParseCoord(0, inp.Items[0]), M.ParseCoord(1, inp.Items[1])]);
    SameH(w + ' point x', p.X, pr.Arrays['point'].Items[0]);
    SameH(w + ' point y', p.Y, pr.Arrays['point'].Items[1]);
  end;
end;

procedure TAdvChartMatrixOracleTest.CheckPicture(M: TTyMatrix; AM: TJSONObject);
var
  list: TTyPaintList;
  els, lines: TJSONArray;
  ej, sh, st, lb, cl: TJSONObject;
  e, cap: TTyChartElement;
  k, at, j, np: Integer;
  w, s: string;
  lw, op, tx, ty: Double;
  wantStroke: Boolean;
  c: TTyChartColor;
  texts: array of TTyRtPiece;
  g: TTyRtGlobal;
begin
  list := TTyPaintList.Create;
  try
    g := Default(TTyRtGlobal);
    g.FontFamily := 'sans-serif';
    g.FontSizeLogical := TyFontSizeFromPx(12);
    g.FontWeight := 400;
    TyBuildMatrix(M, TestInk, g, FMeas, 96, list);
    els := AM.Arrays['els'];
    at := 0;
    for k := 0 to els.Count - 1 do
    begin
      ej := els.Objects[k];
      w := Format('el %d (%s %s)', [k, ej.Strings['role'], StrIn(ej, 'target')]);
      Inc(FEls);
      Inc(FCompared);
      if at >= list.Count then
      begin
        Miss(w + ': the port has no element here');
        Exit;
      end;
      e := list.Element(at);
      Inc(at);
      sh := ej.Objects['shape'];
      st := ej.Objects['style'];
      if ej.Strings['k'] = 'rect' then
      begin
        if e.Shape.Kind <> cskRect then
        begin
          Miss(w + ': not a rect here');
          Exit;
        end;
        SameH(w + ' x', e.Shape.Bounds.Left, sh.Find('x'));
        SameH(w + ' y', e.Shape.Bounds.Top, sh.Find('y'));
        SameD(w + ' right', e.Shape.Bounds.Right, H(sh.Find('x')) + H(sh.Find('width')));
        SameD(w + ' bottom', e.Shape.Bounds.Bottom, H(sh.Find('y')) + H(sh.Find('height')));
      end
      else
      begin
        if (e.Shape.Kind <> cskPolyline) or (Length(e.Shape.Points) <> 2) then
        begin
          Miss(w + ': not a line here');
          Exit;
        end;
        SameH(w + ' x1', e.Shape.Points[0].X, sh.Find('x1'));
        SameH(w + ' y1', e.Shape.Points[0].Y, sh.Find('y1'));
        SameH(w + ' x2', e.Shape.Points[1].X, sh.Find('x2'));
        SameH(w + ' y2', e.Shape.Points[1].Y, sh.Find('y2'));
      end;
      { the paint order: z and z2 }
      Inc(FCompared, 2);
      if e.Z <> ej.Integers['z'] then Miss(Format('%s: z %d, upstream %d', [w, e.Z, ej.Integers['z']]));
      if e.Z2 <> ej.Integers['z2'] then Miss(Format('%s: z2 %d, upstream %d', [w, e.Z2, ej.Integers['z2']]));
      { the ink }
      s := StrIn(st, 'fill');
      c := WantColour(s, False);
      Inc(FCompared);
      if ej.Strings['k'] = 'rect' then
      begin
        if (c shr 24) = 0 then
        begin
          if e.Style.HasFill and ((e.Style.FillColor shr 24) <> 0) then
            Miss(w + ': a fill here, none upstream');
        end
        else if (not e.Style.HasFill) or (e.Style.FillColor <> c) then
          Miss(Format('%s: fill %s upstream, %.8x here', [w, s, e.Style.FillColor]));
      end;
      lw := H(st.Find('lineWidth'));
      s := StrIn(st, 'stroke');
      c := WantColour(s, False);
      wantStroke := ((c shr 24) <> 0) and (lw > 0);
      Inc(FCompared);
      if wantStroke then
      begin
        if (e.Style.StrokeWidthLogical <> lw) or (e.Style.StrokeColor <> c) then
          Miss(Format('%s: stroke %s %s upstream, %.8x %s here', [w, s, Fmt(lw),
            e.Style.StrokeColor, Fmt(e.Style.StrokeWidthLogical)]));
      end
      else if (e.Style.StrokeWidthLogical > 0) and ((e.Style.StrokeColor shr 24) <> 0) then
        Miss(w + ': a stroke here, none upstream');
      op := 1;
      if (st.Find('opacity') <> nil) and (st.Find('opacity').JSONType = jtNumber) then
        op := st.Floats['opacity'];
      Inc(FCompared);
      if Abs(e.Style.Alpha - op) > 1e-12 then
        Miss(Format('%s: opacity %s upstream, %s here', [w, Fmt(op), Fmt(e.Style.Alpha)]));
      Inc(FCompared);
      if wantStroke and ((st.Find('lineDash') <> nil) and (st.Find('lineDash').JSONType <> jtNull))
        <> (Length(e.Style.DashLogical) > 0) then
        Miss(w + ': the dash differs');

      { the label: its own element right after the cell }
      cap := Default(TTyChartElement);
      if (at < list.Count) and (list.Element(at).Caption.Text <> '') then
      begin
        cap := list.Element(at);
        Inc(at);
      end;
      lb := nil;
      if (ej.Find('label') <> nil) and (ej.Find('label').JSONType = jtObject) then
        lb := ej.Objects['label'];
      if (lb <> nil) and (lb.Arrays['lines'].Count = 0) then lb := nil;
      Inc(FCompared);
      if (lb = nil) <> (cap.Caption.Text = '') then
      begin
        if lb = nil then Miss(w + ': a label "' + cap.Caption.Text + '" here, none upstream')
        else Miss(w + ': a label "' + StrIn(lb, 'text') + '" upstream, none here');
        Continue;
      end;
      if lb = nil then Continue;
      Inc(FLabels);
      Inc(FCompared, 4);
      if cap.Caption.Text <> StrIn(lb, 'text') then
        Miss(Format('%s: label "%s" upstream, "%s" here', [w, StrIn(lb, 'text'), cap.Caption.Text]));
      tx := H(lb.Arrays['t'].Items[4]);
      ty := H(lb.Arrays['t'].Items[5]);
      SameD(w + ' label x', cap.Caption.X, tx);
      SameD(w + ' label y', cap.Caption.Y, ty);
      if cap.Z2 <> lb.Integers['z2'] then
        Miss(Format('%s: label z2 %d, upstream %d', [w, cap.Z2, lb.Integers['z2']]));
      if cap.Caption.Colour <> WantColour(StrIn(lb, 'fill'), True) then
        Miss(Format('%s: label ink %s upstream, %.8x here', [w, StrIn(lb, 'fill'), cap.Caption.Colour]));
      if Abs(TyFontPxOf(cap.Caption.FontSizeLogical) - PxOfFont(StrIn(lb, 'font'))) > 1e-9 then
        Miss(Format('%s: label font %s upstream, %s px here', [w, StrIn(lb, 'font'),
          Fmt(TyFontPxOf(cap.Caption.FontSizeLogical))]));
      { the lines }
      texts := nil;
      for np := 0 to High(cap.Caption.RtPieces) do
        if cap.Caption.RtPieces[np].Kind = rpkText then
        begin
          SetLength(texts, Length(texts) + 1);
          texts[High(texts)] := cap.Caption.RtPieces[np];
        end;
      lines := lb.Arrays['lines'];
      Inc(FCompared);
      if Length(texts) <> lines.Count then
      begin
        Miss(Format('%s: %d lines here, %d upstream', [w, Length(texts), lines.Count]));
        Continue;
      end;
      for j := 0 to lines.Count - 1 do
      begin
        Inc(FCompared);
        if texts[j].Text <> lines.Objects[j].Strings['text'] then
          Miss(Format('%s line %d: "%s" upstream, "%s" here', [w, j,
            lines.Objects[j].Strings['text'], texts[j].Text]));
        SameH(Format('%s line %d x', [w, j]), texts[j].X, lines.Objects[j].Find('x'));
        SameH(Format('%s line %d y', [w, j]), texts[j].Y, lines.Objects[j].Find('y'));
      end;
      { the clip, in the text's frame upstream }
      Inc(FCompared);
      if (lb.Find('clip') = nil) or (lb.Find('clip').JSONType = jtNull) then
      begin
        if cap.HasClip then Miss(w + ': a clip here, none upstream');
      end
      else
      begin
        cl := lb.Objects['clip'];
        if not cap.HasClip then Miss(w + ': no clip here')
        else if (Abs(cap.ClipRect.Left - (tx + H(cl.Find('x')))) > 1e-9)
          or (Abs(cap.ClipRect.Top - (ty + H(cl.Find('y')))) > 1e-9)
          or (Abs(cap.ClipRect.Right - (tx + H(cl.Find('x')) + H(cl.Find('width')))) > 1e-9)
          or (Abs(cap.ClipRect.Bottom - (ty + H(cl.Find('y')) + H(cl.Find('height')))) > 1e-9) then
          Miss(w + ': the clip differs');
      end;
    end;
    Inc(FCompared);
    if at <> list.Count then
      Miss(Format('%d elements here, %d matched upstream', [list.Count, at]));
  finally
    list.Free;
  end;
end;

{ AWhat: 0 the trees, 1 the probes, 2 the picture }
procedure TAdvChartMatrixOracleTest.RunPure(AWhat: Integer);
var
  cases, ms: TJSONArray;
  cs, opt: TJSONObject;
  c, k: Integer;
  m: TTyMatrix;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    if not Pure(cs) then Continue;
    FName := cs.Strings['id'];
    opt := OptionOf(cs);
    try
      FOpt.SetOptionText('{}');
      FOpt.SetOptionText(opt.AsJSON);
    finally
      opt.Free;
    end;
    ms := cs.Arrays['matrices'];
    Inc(FCompared);
    if FOpt.ComponentCount('matrix') <> ms.Count then
    begin
      Miss(Format('%d matrices, upstream %d', [FOpt.ComponentCount('matrix'), ms.Count]));
      Continue;
    end;
    for k := 0 to ms.Count - 1 do
    begin
      FName := Format('%s matrix %d', [cs.Strings['id'], k]);
      m := TTyMatrix.Create(FOpt, k);
      try
        m.Resize(TyRectF(0, 0, cW, cH), 96);
        case AWhat of
          0: CheckTrees(m, ms.Objects[k]);
          1: CheckProbes(m, ms.Objects[k]);
        else
          CheckPicture(m, ms.Objects[k]);
        end;
      finally
        m.Free;
      end;
    end;
  end;
end;

procedure TAdvChartMatrixOracleTest.TestTheTreesAndTheLayoutAsUpstream;
begin
  RunPure(0);
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue(Format('the header cells were compared (%d of %d)', [FCells, FCompared]), FCells >= 380);
end;

procedure TAdvChartMatrixOracleTest.TestThePositionsAsUpstream;
begin
  RunPure(1);
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue(Format('the probes were compared (%d of %d)', [FProbes, FCompared]), FProbes >= 1000);
end;

procedure TAdvChartMatrixOracleTest.TestThePictureAsUpstream;
begin
  RunPure(2);
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue(Format('the elements were compared (%d, %d labels, %d comparisons)',
    [FEls, FLabels, FCompared]), (FEls >= 2000) and (FLabels >= 280));
end;

{ ==================== the chart ==================== }

procedure TAdvChartMatrixChartTest.SetUp;
var m: TJSONObject;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TMxProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  FRoot := LoadJson(FixturePath);
  m := TJSONObject(FRoot).Objects['measure'];
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(m.Arrays['ratio'],
    m.Integers['firstCode']));
  FBad := 0;
  FCompared := 0;
  FHeat := 0;
  FSym := 0;
  FReport := '';
end;

procedure TAdvChartMatrixChartTest.TearDown;
begin
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FRoot);
  FBmp.Free;
  FChart.Controller := nil;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

procedure TAdvChartMatrixChartTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartMatrixChartTest.LoadOption(const AJson: string);
begin
  FChart.Option := '{}';
  FChart.Option := AJson;
  FChart.SetBounds(0, 0, cW, cH);
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cW, cH), 96);
end;

{ the fill a row's mark paints: none where upstream's style has none (a
  visualMap that maps a gap writes an undefined colour) }
procedure TAdvChartMatrixChartTest.CheckFill(const AWhat: string;
  const AEl: TTyChartElement; const AFill: string);
var want: TTyChartColor;
begin
  Inc(FCompared);
  if (AFill = '') or (AFill = 'none') then
  begin
    if AEl.Style.HasFill and ((AEl.Style.FillColor shr 24) <> 0) then
      Miss(Format('%s: no fill upstream, %.8x here', [AWhat, AEl.Style.FillColor]));
    Exit;
  end;
  if not TyTryParseChartColor(AFill, want) then Exit;
  if (not AEl.Style.HasFill) or (AEl.Style.FillColor <> want) then
    Miss(Format('%s: fill %s upstream, %.8x here', [AWhat, AFill, AEl.Style.FillColor]));
end;

procedure TAdvChartMatrixChartTest.RunSeries(AGallery: Boolean);
var
  cases, series, rows, ms, cells: TJSONArray;
  cs, opt, se, row, sh, lb, mj, cj: TJSONObject;
  c, s, k, j, si, di, n, mi: Integer;
  lst: TTyPaintList;
  e: TTyChartElement;
  d: TJSONData;
  markAt, capAt: array of Integer;
  m: TTyMatrix;
  b: TTyRectF;
  heat, wantDrawn: Boolean;
  w: string;
  x, y: Double;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    d := cs.Find('gallery');
    if AGallery <> ((d <> nil) and (d.JSONType = jtString)) then Continue;
    if cs.Arrays['series'].Count = 0 then Continue;
    FName := cs.Strings['id'];
    if AGallery then opt := TJSONObject(LoadJson(GalleryPath(d.AsString)))
    else opt := TJSONObject(cs.Objects['option'].Clone);
    try
      { UPSTREAM'S OWN PALETTE AND RAMP where the option names none }
      if opt.Find('color') = nil then
        opt.Add('color', GetJSON('["#5070dd","#b6d634","#505372","#ff994d",'
          + '"#0ca8df","#ffd10a","#fb628b","#785db0","#3fbe95"]'));
      if opt.Find('gradientColor') = nil then
        opt.Add('gradientColor', GetJSON('["rgba(212,220,247,1)","#5070dd"]'));
      try
        LoadOption(opt.AsJSON);
      except
        on Ex: Exception do
        begin
          Miss(Ex.ClassName + ': ' + Ex.Message);
          Continue;
        end;
      end;
    finally
      opt.Free;
    end;
    { the matrices as the chart built them }
    ms := cs.Arrays['matrices'];
    for mi := 0 to ms.Count - 1 do
    begin
      mj := ms.Objects[mi];
      m := FChart.MatrixLayout(mi);
      w := Format('matrix %d', [mi]);
      Inc(FCompared);
      if m = nil then
      begin
        Miss(w + ': not built');
        Continue;
      end;
      Inc(FCompared, 4);
      if not (SameBits(m.Rect.X, H(mj.Objects['rect'].Find('x')))
        and SameBits(m.Rect.Y, H(mj.Objects['rect'].Find('y')))
        and SameBits(m.Rect.W, H(mj.Objects['rect'].Find('width')))
        and SameBits(m.Rect.H, H(mj.Objects['rect'].Find('height')))) then
        Miss(w + ': the rect differs');
      for di := 0 to 1 do
      begin
        cells := mj.Arrays['dims'].Objects[di].Arrays['cells'];
        Inc(FCompared);
        if m.Dims[di].CellCount <> cells.Count then
        begin
          Miss(Format('%s dim %d: %d cells, upstream %d', [w, di, m.Dims[di].CellCount, cells.Count]));
          Continue;
        end;
        for k := 0 to cells.Count - 1 do
        begin
          cj := cells.Objects[k];
          Inc(FCompared, 3);
          if m.Dims[di].Cells[k].Value <> StrIn(cj, 'value') then
            Miss(Format('%s dim %d cell %d: "%s", upstream "%s"', [w, di, k,
              m.Dims[di].Cells[k].Value, StrIn(cj, 'value')]));
          if not (SameBits(m.Dims[di].Cells[k].Rect.X, H(cj.Objects['rect'].Find('x')))
            and SameBits(m.Dims[di].Cells[k].Rect.W, H(cj.Objects['rect'].Find('width')))) then
            Miss(Format('%s dim %d cell %d: the rect across differs', [w, di, k]));
          if not (SameBits(m.Dims[di].Cells[k].Rect.Y, H(cj.Objects['rect'].Find('y')))
            and SameBits(m.Dims[di].Cells[k].Rect.H, H(cj.Objects['rect'].Find('height')))) then
            Miss(Format('%s dim %d cell %d: the rect down differs', [w, di, k]));
        end;
      end;
    end;
    { the series }
    lst := FChart.List;
    series := cs.Arrays['series'];
    for s := 0 to series.Count - 1 do
    begin
      se := series.Objects[s];
      si := se.Integers['seriesIndex'];
      heat := se.Strings['type'] = 'heatmap';
      FName := Format('%s series %d', [cs.Strings['id'], si]);
      rows := se.Arrays['rows'];
      n := lst.Count;
      markAt := nil;
      capAt := nil;
      SetLength(markAt, rows.Count + 1);
      SetLength(capAt, rows.Count + 1);
      for k := 0 to High(markAt) do
      begin
        markAt[k] := -1;
        capAt[k] := -1;
      end;
      for k := 0 to n - 1 do
      begin
        e := lst.Element(k);
        if (e.Datum.SeriesIndex <> si) or (e.Datum.DataIndex < 0)
          or (e.Datum.DataIndex > High(markAt)) then Continue;
        { a label is its own element (the host keeps the words it was given) }
        if (e.Caption.FontSizeLogical > 0) and (e.Caption.Text <> '') then
          capAt[e.Datum.DataIndex] := k
        else if markAt[e.Datum.DataIndex] < 0 then markAt[e.Datum.DataIndex] := k;
      end;
      for j := 0 to rows.Count - 1 do
      begin
        row := rows.Objects[j];
        di := row.Integers['index'];
        w := Format('row %d', [di]);
        wantDrawn := row.Booleans['drawn'];
        { a heatmap row whose y names nothing: upstream makes a rect of NaN y,
          which paints nothing; the port makes none }
        if wantDrawn and heat and IsNan(H(row.Objects['shape'].Find('y'))) then wantDrawn := False;
        if wantDrawn and not heat and ((row.Find('point') = nil) or (row.Find('point').JSONType = jtNull)
          or IsNan(H(row.Arrays['point'].Items[0])) or IsNan(H(row.Arrays['point'].Items[1]))) then
          wantDrawn := False;
        Inc(FCompared);
        if wantDrawn <> (markAt[di] >= 0) then
        begin
          if wantDrawn then Miss(w + ': drawn upstream, not here')
          else Miss(w + ': drawn here, not upstream');
          Continue;
        end;
        if not wantDrawn then Continue;
        e := lst.Element(markAt[di]);
        if heat then
        begin
          Inc(FHeat);
          sh := row.Objects['shape'];
          Inc(FCompared, 4);
          if not (SameBits(e.Shape.Bounds.Left, H(sh.Find('x')))
            and SameBits(e.Shape.Bounds.Top, H(sh.Find('y')))
            and SameBits(e.Shape.Bounds.Right, H(sh.Find('x')) + H(sh.Find('width')))
            and SameBits(e.Shape.Bounds.Bottom, H(sh.Find('y')) + H(sh.Find('height')))) then
            Miss(Format('%s: cell (%s, %s, %s, %s) upstream, (%s, %s, %s, %s) here', [w,
              Fmt(H(sh.Find('x'))), Fmt(H(sh.Find('y'))), Fmt(H(sh.Find('width'))),
              Fmt(H(sh.Find('height'))), Fmt(e.Shape.Bounds.Left), Fmt(e.Shape.Bounds.Top),
              Fmt(e.Shape.Bounds.Right), Fmt(e.Shape.Bounds.Bottom)]));
          Inc(FCompared);
          if e.Z2 <> 1 then Miss(Format('%s: z2 %d, upstream 1', [w, e.Z2]));
          CheckFill(w, e, StrIn(row, 'fill'));
        end
        else
        begin
          Inc(FSym);
          b := TyShapeBounds(e.Shape);
          x := H(row.Arrays['point'].Items[0]);
          y := H(row.Arrays['point'].Items[1]);
          Inc(FCompared, 2);
          if (Abs((b.Left + b.Right) / 2 - x) > 1e-9) or (Abs((b.Top + b.Bottom) / 2 - y) > 1e-9) then
            Miss(Format('%s: a symbol at (%s, %s) upstream, (%s, %s) here', [w, Fmt(x), Fmt(y),
              Fmt((b.Left + b.Right) / 2), Fmt((b.Top + b.Bottom) / 2)]));
          if Abs((b.Right - b.Left) - row.Arrays['size'].Floats[0]) > 1e-9 then
            Miss(Format('%s: a symbol %s wide upstream, %s here', [w,
              Fmt(row.Arrays['size'].Floats[0]), Fmt(b.Right - b.Left)]));
          CheckFill(w, e, StrIn(row, 'fill'));
        end;
        { the label's words }
        lb := nil;
        if (row.Find('label') <> nil) and (row.Find('label').JSONType = jtObject) then
          lb := row.Objects['label'];
        if (lb <> nil) and (lb.Arrays['lines'].Count = 0) then lb := nil;
        Inc(FCompared);
        if (lb = nil) <> (capAt[di] < 0) then
        begin
          if lb = nil then Miss(w + ': a label here, none upstream')
          else Miss(w + ': label "' + StrIn(lb, 'text') + '" upstream, none here');
          Continue;
        end;
        if lb = nil then Continue;
        e := lst.Element(capAt[di]);
        Inc(FCompared);
        if e.Caption.Text <> StrIn(lb, 'text') then
          Miss(Format('%s: label "%s" upstream, "%s" here', [w, StrIn(lb, 'text'), e.Caption.Text]));
        if heat then
        begin
          Inc(FCompared, 2);
          if not (SameBits(e.Caption.X, H(lb.Arrays['t'].Items[4]))
            and SameBits(e.Caption.Y, H(lb.Arrays['t'].Items[5]))) then
            Miss(Format('%s: label at (%s, %s) upstream, (%s, %s) here', [w,
              Fmt(H(lb.Arrays['t'].Items[4])), Fmt(H(lb.Arrays['t'].Items[5])),
              Fmt(e.Caption.X), Fmt(e.Caption.Y)]));
        end;
      end;
    end;
  end;
end;

procedure TAdvChartMatrixChartTest.TestTheSeriesAsUpstream;
begin
  RunSeries(False);
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue(Format('the cells and symbols were compared (%d, %d)', [FHeat, FSym]),
    (FHeat >= 25) and (FSym >= 15));
end;

procedure TAdvChartMatrixChartTest.TestTheGallerySeriesAsUpstream;
begin
  RunSeries(True);
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue(Format('the gallery cells and symbols were compared (%d, %d)', [FHeat, FSym]),
    (FHeat >= 400) and (FSym >= 100));
end;

{ EVERY GALLERY ENTRY ON A MATRIX RENDERS, those part one cannot draw
  (custom, graph, pie, grids and merged cells in a matrix) included: the
  matrix is drawn, nothing raises. }
procedure TAdvChartMatrixChartTest.TestEveryMatrixGalleryEntryRenders;
const
  cFiles: array[0..11] of string = ('matrix-confusion', 'matrix-correlation-heatmap',
    'matrix-correlation-scatter', 'matrix-covariance', 'matrix-graph', 'matrix-mbti',
    'matrix-mini-bar-data-collection', 'matrix-mini-bar-geo', 'matrix-periodic-table',
    'matrix-pie', 'matrix-simple', 'matrix-stock');
var
  k, j, z50: Integer;
  opt: TJSONData;
begin
  for k := 0 to High(cFiles) do
  begin
    opt := LoadJson(GalleryPath(cFiles[k]));
    try
      try
        LoadOption(opt.AsJSON);
      except
        on E: Exception do
          Fail(cFiles[k] + ' raised ' + E.ClassName + ': ' + E.Message);
      end;
    finally
      opt.Free;
    end;
    AssertNotNull(cFiles[k] + ': its matrix is built', FChart.MatrixLayout(0));
    z50 := 0;
    for j := 0 to FChart.List.Count - 1 do
      if FChart.List.Element(j).Z = -50 then Inc(z50);
    AssertTrue(cFiles[k] + ': the matrix is drawn', z50 > 0);
  end;
end;

procedure TAdvChartMatrixChartTest.TestTheMatrixDrawsUnderTheSeries;
var
  k, lastMatrix, firstCell: Integer;
  lst: TTyPaintList;
begin
  LoadOption('{"matrix": {"x": {"data": ["a", "b"]}, "y": {"data": ["p"]}},'
    + ' "visualMap": {"show": false, "min": 0, "max": 9, "dimension": 2},'
    + ' "series": {"type": "heatmap", "coordinateSystem": "matrix",'
    + ' "data": [["a", "p", 1], ["b", "p", 5]]}}');
  lst := FChart.List;
  lastMatrix := -1;
  firstCell := MaxInt;
  for k := 0 to lst.Count - 1 do
  begin
    if lst.Element(k).Z = -50 then lastMatrix := Max(lastMatrix, k);
    if (lst.Element(k).Datum.SeriesIndex = 0) and (lst.Element(k).Caption.FontSizeLogical = 0) then
      firstCell := Min(firstCell, k);
  end;
  AssertTrue('the matrix is in the list', lastMatrix >= 0);
  AssertTrue('the cells are in the list', firstCell < MaxInt);
  AssertTrue('a heatmap cell is above every matrix element (z 2 over -50)',
    lst.Element(firstCell).Z > lst.Element(lastMatrix).Z);
  AssertTrue('the matrix view counts as drawn', cvMatrix in FChart.LastViewsDrawn);
end;

procedure TAdvChartMatrixChartTest.TestAPieOnAMatrixIsNotBuiltYet;
var
  k: Integer;
  said: Boolean;
begin
  LoadOption('{"matrix": {"x": {"data": ["a"]}, "y": {"data": ["p"]}},'
    + ' "series": {"type": "pie", "coordinateSystem": "matrix", "coord": ["a", "p"],'
    + ' "data": [1, 2]}}');
  said := False;
  for k := 0 to FChart.DiagnosticCount - 1 do
    if Pos('"matrix"', FChart.Diagnostic(k)) > 0 then said := True;
  AssertTrue('a pie on a matrix says its coordinate system is not built', said);
  AssertNotNull('the matrix itself is', FChart.MatrixLayout(0));
end;

procedure TAdvChartMatrixChartTest.TestThePPIScalesThePixels;
var
  m: TTyMatrix;
  opt: TTyChartOption;
begin
  opt := TTyChartOption.Create;
  try
    opt.SetOptionText('{"matrix": {"left": 40, "top": "10%", "width": 300, "height": "50%",'
      + ' "x": {"data": [{"value": "a", "size": 100}, "b"], "levelSize": 20},'
      + ' "y": {"data": ["p", "q"]}}}');
    m := TTyMatrix.Create(opt, 0);
    try
      m.Resize(TyRectF(0, 0, 1600, 1200), 192);
      AssertEquals('a px left doubles', 80, m.Rect.X, 0);
      AssertEquals('a percentage of the canvas stays one', 120, m.Rect.Y, 0);
      AssertEquals('a px width doubles', 600, m.Rect.W, 0);
      AssertEquals('a percentage height stays one', 600, m.Rect.H, 0);
      AssertEquals('a leaf size doubles', 200, m.Dims[0].Cells[0].WH, 0);
      AssertEquals('a level size doubles', 40, m.Dims[0].Levels[0].WH, 0);
    finally
      m.Free;
    end;
  finally
    opt.Free;
  end;
end;

{ THE INTERACTION IS PART TWO, but the pointer already meets these marks:
  hovering a heatmap cell, a scatter symbol and a header cell, with a
  tooltip on, must not raise }
procedure TAdvChartMatrixChartTest.TestHoveringAMatrixSeriesRaisesNothing;
var
  m: TTyMatrix;
  p: TTyPointF;
begin
  LoadOption('{"tooltip": {}, "matrix": {"x": {"data": ["a", "b"]}, "y": {"data": ["p", "q"]}},'
    + ' "visualMap": {"show": false, "min": 0, "max": 9, "dimension": 2},'
    + ' "series": [{"type": "heatmap", "coordinateSystem": "matrix",'
    + ' "data": [["a", "p", 1], ["b", "q", 5]]},'
    + ' {"type": "scatter", "coordinateSystem": "matrix", "data": [["b", "p", 3]]}]}');
  m := FChart.MatrixLayout(0);
  AssertNotNull('the matrix', m);
  p := m.DataToPoint([0, 0]);
  FChart.Hover(Round(p.X), Round(p.Y));
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cW, cH), 96);
  p := m.DataToPoint([1, 0]);
  FChart.Hover(Round(p.X), Round(p.Y));
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cW, cH), 96);
  p := m.DataToPoint([0, -1]);
  FChart.Hover(Round(p.X), Round(p.Y));
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cW, cH), 96);
  AssertTrue('hovered three places', True);
end;

{ ONE NUMBER MUST NOT MAKE A HUNDRED MILLION RECTANGLES: a `length` past
  the cap is no tree, and a body past its cap is not drawn (the headers
  are) }
procedure TAdvChartMatrixChartTest.TestAHugeMatrixIsRefusedNotWalked;
var
  m: TTyMatrix;
  opt: TTyChartOption;
  list: TTyPaintList;
  g: TTyRtGlobal;
  n: Integer;
begin
  opt := TTyChartOption.Create;
  list := TTyPaintList.Create;
  try
    opt.SetOptionText('{"matrix": {"x": {"length": 10000000}, "y": {"length": 2}}}');
    m := TTyMatrix.Create(opt, 0);
    try
      AssertEquals('a length past the cap is no tree', 0, m.Dims[0].LeafCount);
      AssertEquals('the other one stands', 2, m.Dims[1].LeafCount);
    finally
      m.Free;
    end;
    opt.SetOptionText('{"matrix": {"x": {"length": 600, "label": {"show": false}},'
      + ' "y": {"length": 600, "label": {"show": false}}}}');
    m := TTyMatrix.Create(opt, 0);
    try
      m.Resize(TyRectF(0, 0, cW, cH), 96);
      g := Default(TTyRtGlobal);
      g.FontSizeLogical := TyFontSizeFromPx(12);
      n := TyBuildMatrix(m, TestInk, g, nil, 96, list);
      AssertTrue(Format('the body of 360000 cells is not drawn (%d elements)', [n]),
        (n > 1200) and (n < 1300));
    finally
      m.Free;
    end;
  finally
    list.Free;
    opt.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartMatrixOracleTest);
  RegisterTest(TAdvChartMatrixChartTest);
end.
