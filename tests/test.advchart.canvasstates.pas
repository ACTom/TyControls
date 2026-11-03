unit test.advchart.canvasstates;
{$mode objfpc}{$H+}
{ VALUES THE CANVAS REFUSES INSIDE A STATE, held to upstream. [R7-Y]

  tests/fixtures/advchart-canvas-states.json, from the real ECharts 6.1 build
  (tools/advchart-oracle/canvas-states.js): zrender's canvas painter on a
  recording context whose setters refuse what a browser's refuse. An
  emphasis, blur or select state entered by dispatchAction brushes its style
  through the same setters as the element's own: a negative shadowBlur, a cap
  or join that is no canvas word, a miterLimit not above nought, a dash phase
  or width that is no finite number, a colour no parser reads -- each refused,
  the canvas keeping what the element brushed before it left; a transition
  tweening a blur below nought is refused frame by frame.

  Per case, sample and tracked element, every fill / stroke of its path and
  the context then: the port's element in the frame is compared on its fill,
  pen colour, effective width, dash and phase, cap / join / miterLimit, the
  shadow it casts and its alpha: TestTheStateValuesAsUpstream. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint,
     tyControls.AdvanceChart.Shape, tyControls.AdvanceChart.Color,
     tyControls.AdvanceChart.Geo, tyControls.AdvanceChart;
type
  TCsProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    { through the cached path: a state's change patches the list }
    procedure Cached(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function Frame: TTyPaintList;
  end;

  TAdvChartCanvasStatesOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TCsProbe;
    FRoot: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared: Integer;
    FReport: string;
    procedure Miss(const AWhat: string);
    function ElOf(const AKey: string): Integer;
    procedure Run(ACached, AOff: Boolean);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheStateValuesAsUpstream;
    procedure TestTheStateValuesThroughTheCacheAsUpstream;
    procedure TestTheStateValuesWithoutAnimationAsUpstream;
  end;

implementation

const
  cT0 = 1700000000000.0;
  cCap: array[0..2] of string = ('butt', 'round', 'square');
  cJoin: array[0..2] of string = ('miter', 'round', 'bevel');

procedure TCsProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TCsProbe.Cached(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderCached(ACanvas, ARect, APPI);
end;

function TCsProbe.Frame: TTyPaintList;
begin
  Result := AnimFrame;
  if Result = nil then Result := SeriesList;
end;

function HexD(const S: string): Double;
var q: QWord;
begin
  q := StrToQWord('$' + S);
  Move(q, Result, SizeOf(Result));
end;

procedure TAdvChartCanvasStatesOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  sl := TStringList.Create;
  try
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + 'advchart-canvas-states.json');
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FBmp := TBGRABitmap.Create(FRoot.FindPath('W').AsInteger, FRoot.FindPath('H').AsInteger,
    BGRA(255, 255, 255, 255));
end;

procedure TAdvChartCanvasStatesOracleTest.TearDown;
begin
  FreeAndNil(FChart);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FRoot);
  FreeAndNil(FBmp);
  inherited TearDown;
end;

procedure TAdvChartCanvasStatesOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if GetEnvironmentVariable('TY_CS_TRACE') <> '' then WriteLn('MISS ', AWhat);
  if Length(FReport) < 6000 then FReport := FReport + LineEnding + AWhat;
end;

{ the frame's element a key names: s a scatter's symbol, b a bar, ln a
  polyline, ls a line's symbol, p a sector }
function TAdvChartCanvasStatesOracleTest.ElOf(const AKey: string): Integer;
var
  L: TTyPaintList;
  k, s, r, p: Integer;
  pre: string;
  role: TTyChartAnimRole;
  el: TTyChartElement;
begin
  Result := -1;
  p := 1;
  while (p <= Length(AKey)) and (AKey[p] in ['a'..'z']) do Inc(p);
  pre := Copy(AKey, 1, p - 1);
  s := StrToInt(Copy(AKey, p, Pos('.', AKey) - p));
  if pre <> 'g' then r := StrToInt(Copy(AKey, Pos('.', AKey) + 1, MaxInt));
  { a map region's path (its displayables numbered after the row) }
  if pre = 'g' then
  begin
    r := StrToInt(Copy(AKey, Pos('.', AKey) + 1, Pos('.', Copy(AKey, Pos('.', AKey) + 1, MaxInt)) - 1));
    L := FChart.Frame;
    for k := 0 to L.Count - 1 do
    begin
      el := L.Element(k);
      if (el.Anim.Role = carMapRegion) and (el.Datum.SeriesIndex = s) and (el.Datum.DataIndex = r)
        and (el.Caption.FontSizeLogical = 0) then
        Exit(k);
    end;
    Exit;
  end;
  if pre = 'b' then role := carBar
  else if pre = 'p' then role := carSector
  else if pre = 'ln' then role := carLineRun
  else if pre = 'ls' then role := carLineSymbol
  else role := carSymbol;
  L := FChart.Frame;
  for k := 0 to L.Count - 1 do
  begin
    el := L.Element(k);
    if (el.Anim.Role = role) and (el.Datum.SeriesIndex = s)
      and ((el.Datum.DataIndex = r) or (role = carLineRun))
      and not el.Datum.IsEdge and (el.Caption.FontSizeLogical = 0) then
      Exit(k);
  end;
end;

{ the colours a canvas holds alike: the same, or both of no alpha }
function SameInk(A, B: TTyChartColor): Boolean;
begin
  Result := (A = B) or (((A shr 24) = 0) and ((B shr 24) = 0));
end;

procedure RegisterMaps(ARoot: TJSONData);
var maps: TJSONArray; i: Integer;
begin
  TyChartClearMaps;
  maps := TJSONObject(ARoot).Arrays['maps'];
  for i := 0 to maps.Count - 1 do
    TyChartRegisterMap(maps.Objects[i].Strings['name'], maps.Objects[i].Strings['text'], '');
end;

procedure TAdvChartCanvasStatesOracleTest.TestTheStateValuesAsUpstream;
begin
  Run(False, False);
end;

{ the window's path: the cache kept, a state's change patching the list
  where it stands (StPatchList) rather than building it again }
procedure TAdvChartCanvasStatesOracleTest.TestTheStateValuesThroughTheCacheAsUpstream;
begin
  Run(True, False);
end;

{ camOff: no proxy, the states written onto the list itself (StWriteHost)
  and a change patched there -- the cases of no transition only }
procedure TAdvChartCanvasStatesOracleTest.TestTheStateValuesWithoutAnimationAsUpstream;
begin
  Run(True, True);
end;

procedure TAdvChartCanvasStatesOracleTest.Run(ACached, AOff: Boolean);
var
  cs, frames, els, ops, ld: TJSONArray;
  c, fr, rec, o: TJSONObject;
  i, j, k, idx, q, n: Integer;
  id, key, where, op: string;
  t, sc, lw, plw, ldo, pldo, sb, ml, pml, ga, pa: Double;
  el: TTyChartElement;
  wc: TTyChartColor;
  m: array[0..5] of Double;
  pdash: TTyDoubleArray;
begin
  FBad := 0;
  FCompared := 0;
  FReport := '';
  RegisterMaps(FRoot);
  cs := TJSONObject(FRoot).Arrays['charts'];
  for i := 0 to cs.Count - 1 do
  begin
    c := cs.Objects[i];
    id := c.Strings['id'];
    if AOff and (Pos('tween', id) > 0) then Continue;
    if GetEnvironmentVariable('TY_CS_TRACE') <> '' then WriteLn('case ', id);
    FreeAndNil(FChart);
    FChart := TCsProbe.Create(FForm);
    FChart.Parent := FForm;
    FChart.Controller := FCtl;
    FChart.SetBounds(0, 0, FBmp.Width, FBmp.Height);
    if AOff then FChart.AnimationMode := camOff
    else FChart.AnimationMode := camAlways;
    FChart.AnimNow := cT0;
    FChart.SetOption(c.Objects['option'].AsJSON, True);
    AssertEquals(id + ' parses', '', FChart.OptionError);
    FBmp.Fill(BGRA(255, 255, 255, 255));
    if ACached then FChart.Cached(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96)
    else FChart.Render(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96);
    frames := c.Arrays['frames'];
    for j := 0 to frames.Count - 1 do
    begin
      fr := frames.Objects[j];
      t := fr.Floats['t'];
      if (c.Find('acts') <> nil) and (c.Objects['acts'].Find(IntToStr(j)) <> nil) then
      begin
        FChart.AnimNow := cT0 + t;
        for q := 0 to c.Objects['acts'].Arrays[IntToStr(j)].Count - 1 do
          FChart.DispatchAction(c.Objects['acts'].Arrays[IntToStr(j)].Objects[q].AsJSON);
      end;
      if t > 0 then FChart.AnimTick(cT0 + t);
      if ACached then FChart.Cached(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96)
      else FChart.Render(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96);
      els := fr.Arrays['els'];
      for k := 0 to els.Count - 1 do
      begin
        rec := els.Objects[k];
        key := rec.Strings['key'];
        where := Format('%s t=%g %s', [id, t, key]);
        ops := rec.Arrays['ops'];
        if ops.Count = 0 then Continue;
        idx := ElOf(key);
        if idx < 0 then
        begin
          Miss(where + ': no element');
          Continue;
        end;
        el := FChart.Frame.Element(idx);
        for q := 0 to ops.Count - 1 do
        begin
          o := ops.Objects[q];
          op := o.Strings['op'];
          for n := 0 to 5 do m[n] := HexD(o.Arrays['m'].Strings[n]);
          { the line scale of the transform the op is made under }
          sc := Sqrt(Abs(m[0] * m[3] - m[1] * m[2]));
          { the alpha }
          ga := HexD(o.Strings['ga']);
          pa := TyCanvasPartAlpha(el.Style, op = 'fill');
          Inc(FCompared);
          if Abs(pa - ga) > 1e-9 then
            Miss(Format('%s %s: alpha %g, upstream %g', [where, op, pa, ga]));
          if op = 'fill' then
          begin
            Inc(FCompared);
            if o.Strings['fs'] = '[grad]' then
            begin
              if el.Style.FillGradient.Kind = cgkNone then
                Miss(Format('%s: fill %x, upstream a gradient', [where, el.Style.FillColor]));
            end
            else if TyTryParseChartColor(o.Strings['fs'], wc) then
            begin
              if not el.Style.HasFill or (el.Style.FillGradient.Kind <> cgkNone)
                or not SameInk(el.Style.FillColor, wc) then
                Miss(Format('%s: fill %x (has %s), upstream %s', [where, el.Style.FillColor,
                  BoolToStr(el.Style.HasFill, True), o.Strings['fs']]));
            end;
          end
          else
          begin
            { the pen: its width, colour, dash and phase, cap, join, miterLimit }
            Inc(FCompared);
            lw := HexD(o.Strings['lw']) * sc;
            plw := el.Style.StrokeWidthLogical;
            if (el.Style.PenScale > 0) and (el.Style.PenScale <> 1) then plw := plw * el.Style.PenScale;
            if not (el.Style.StrokeWidthLogical > 0) or (Abs(plw - lw) > 1e-6) then
              Miss(Format('%s: stroke width %g, upstream %g', [where, plw, lw]));
            if (o.Strings['ss'] <> '[grad]') and TyTryParseChartColor(o.Strings['ss'], wc) then
            begin
              Inc(FCompared);
              if (el.Style.StrokeGradient.Kind <> cgkNone) or not SameInk(el.Style.StrokeColor, wc) then
                Miss(Format('%s: stroke %x, upstream %s', [where, el.Style.StrokeColor, o.Strings['ss']]));
            end;
            ld := o.Arrays['ld'];
            pdash := el.Style.DashLogical;
            if el.Style.DashWord <> 0 then
              pdash := TyDashOfWord(el.Style.DashWord, el.Style.StrokeWidthLogical);
            Inc(FCompared);
            if Length(pdash) * Ord(ld.Count > 0) <> ld.Count then
              Miss(Format('%s: dash of %d, upstream %s', [where, Length(pdash), ld.AsJSON]))
            else if ld.Count > 0 then
            begin
              for n := 0 to ld.Count - 1 do
                if Abs(pdash[n] - HexD(ld.Strings[n]) * sc) > 1e-6 then
                begin
                  Miss(Format('%s: dash %g at %d, upstream %g', [where, pdash[n], n,
                    HexD(ld.Strings[n]) * sc]));
                  Break;
                end;
              ldo := HexD(o.Strings['ldo']) * sc;
              pldo := el.Style.DashOffsetLogical;
              if IsNan(pldo) then pldo := -1e300;
              Inc(FCompared);
              if Abs(pldo - ldo) > 1e-6 then
                Miss(Format('%s: dash phase %g, upstream %g', [where, pldo, ldo]));
            end;
            pml := el.Style.MiterLimit;
            if not (pml > 0) then pml := 10;
            ml := HexD(o.Strings['ml']);
            Inc(FCompared);
            if (cCap[el.Style.LineCap mod 3] <> o.Strings['cap'])
              or (cJoin[el.Style.LineJoin mod 3] <> o.Strings['join']) or (pml <> ml) then
              Miss(Format('%s: cap %s join %s miterLimit %g (%d %d), upstream %s %s %g', [where,
                cCap[el.Style.LineCap mod 3], cJoin[el.Style.LineJoin mod 3], pml,
                el.Style.LineCap, el.Style.LineJoin, o.Strings['cap'], o.Strings['join'], ml]));
          end;
          { the shadow it casts (a refused blur or colour kept) }
          sb := HexD(o.Strings['sb']);
          if TyTryParseChartColor(o.Strings['sc'], wc) and (sb > 0) and ((wc shr 24) <> 0) then
          begin
            Inc(FCompared);
            if not TyStyleHasShadow(el.Style) or (el.Style.ShadowColor <> wc)
              or (Abs(el.Style.ShadowBlur - sb) > 1e-9) then
              Miss(Format('%s %s: shadow %x blur %g, want %s blur %g', [where, op,
                el.Style.ShadowColor, el.Style.ShadowBlur, o.Strings['sc'], sb]));
          end
          else if (sb = 0) and (HexD(o.Strings['sox']) = 0) and (HexD(o.Strings['soy']) = 0) then
          begin
            Inc(FCompared);
            if TyStyleHasShadow(el.Style) then
              Miss(Format('%s %s: a shadow in %x blur %g, upstream casts none', [where, op,
                el.Style.ShadowColor, el.Style.ShadowBlur]));
          end;
        end;
      end;
    end;
  end;
  FreeAndNil(FChart);
  TyChartClearMaps;
  if FBad > 0 then
    Fail(Format('%d of %d differ:%s', [FBad, FCompared, FReport]));
  AssertTrue('compared', FCompared > 50);
end;

initialization
  RegisterTest(TAdvChartCanvasStatesOracleTest);
end.
