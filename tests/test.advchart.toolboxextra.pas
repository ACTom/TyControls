unit test.advchart.toolboxextra;
{$mode objfpc}{$H+}
{ THE TOOLBOX'S LINE KEYS, ITS TITLE'S BOX AND FONT, ITS ICONS' TOOLTIP,
  HELD TO UPSTREAM [R5-D].

  tools/advchart-oracle/toolbox-extra.js runs the real ECharts 6.1 build in
  node (the harness of tooltip-actions.js): iconStyle and emphasis.iconStyle
  with borderType / borderDashOffset / borderCap / borderJoin /
  borderMiterLimit; a title with textBackgroundColor, textBorderRadius,
  textPadding and its own font; toolbox.tooltip shown (the icon's name by
  default, a template over name and title, a position) and not shown (a
  hover on an icon dispatches showTip and leaves the box another target
  showed). Per step it records the showtip / hidetip events, each icon's
  states and line style, the title shown (its font, colours, box, the text's
  place) and the tooltip box (what, its text, its top-left).

  This replays the steps through TTyAdvanceChart (the probe of
  test.advchart.tooltipactions: the SSR width table, the box 80 x 40) and
  reads the toolbox's elements from the paint list: the icons (the
  toolbox's z, z2 0, in feature order), the title's caption and its box
  (z2 1). The title's width is the measurer's (a font's), so the box is
  compared by its height, its top and its centre, the text by its anchor. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Types, tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint,
     tyControls.AdvanceChart.Shape, tyControls.AdvanceChart.Color,
     tyControls.AdvanceChart.Events,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax,
     test.advchart.tooltipactions;
type
  TTxProbe = class(TTaProbe)
  public
    function Icons: TTyPaintList;
    function TitleCaption(out AEl: TTyChartElement): Boolean;
    function TitleBox(out AEl: TTyChartElement): Boolean;
  end;

  TAdvChartToolboxExtraOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FRoot, FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared: Integer;
    FReport, FWhere: string;
    FLog: TStrings;
    procedure Bad(const AWhat: string);
    procedure Near(const AWhat: string; AGot, AWant: Double);
    procedure OnEvent(Sender: TObject; const AEvent: TTyChartEvent);
    procedure RunCase(const AId: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheIconsLineKeysAsUpstream;
    procedure TestTheTitlesBoxAsUpstream;
    procedure TestAnUnevenTitlePaddingAsUpstream;
    procedure TestTheIconsTooltipAsUpstream;
    procedure TestATooltipTemplateAsUpstream;
    procedure TestTheTooltipOffAsUpstream;
  end;

  { [R5-D] tools/advchart-oracle/magictype-defaults.js: the changeMagicType
    payload's series -- the old series' option with its type's defaults
    under the generated keys -- after line, bar and stack clicks }
  TAdvChartMagicTypeDefaultsOracleTest = class(TTestCase)
  private
    FPays: TStringList;
    procedure OnEvent(Sender: TObject; const AEvent: TTyChartEvent);
  published
    procedure TestTheNewSeriesKeepTheOldDefaultsAsUpstream;
  end;

implementation

const
  cW = 600;
  cH = 400;

function FixturePath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + AName;
end;

function TTxProbe.Icons: TTyPaintList;
var
  i: Integer;
  el: TTyChartElement;
begin
  Result := TTyPaintList.Create;
  if SeriesList = nil then Exit;
  for i := 0 to SeriesList.Count - 1 do
  begin
    el := SeriesList.Element(i);
    if (el.Datum.SeriesIndex >= 0) or (el.Z <> 6) or (el.Z2 <> 0) then Continue;
    if el.Style.StrokeWidthLogical <= 0 then Continue;
    Result.Add(el);
  end;
end;

function TTxProbe.TitleCaption(out AEl: TTyChartElement): Boolean;
var i: Integer;
begin
  Result := False;
  AEl := Default(TTyChartElement);
  if SeriesList = nil then Exit;
  for i := 0 to SeriesList.Count - 1 do
    if (SeriesList.Element(i).Z = 6) and (SeriesList.Element(i).Z2 = 1)
      and (SeriesList.Element(i).Caption.Text <> '') then
    begin
      AEl := SeriesList.Element(i);
      Exit(True);
    end;
end;

function TTxProbe.TitleBox(out AEl: TTyChartElement): Boolean;
var i: Integer;
begin
  Result := False;
  AEl := Default(TTyChartElement);
  if SeriesList = nil then Exit;
  for i := 0 to SeriesList.Count - 1 do
    if (SeriesList.Element(i).Z = 6) and (SeriesList.Element(i).Z2 = 1)
      and (SeriesList.Element(i).Caption.Text = '') and SeriesList.Element(i).Style.HasFill then
    begin
      AEl := SeriesList.Element(i);
      Exit(True);
    end;
end;

{ zrender's normalizeLineDash of what the style holds, as text }
function DashText(AType: TJSONData; AWidth: Double): string;
var
  w: Byte;
  a: TTyDoubleArray;
  i: Integer;
begin
  a := TyLineDashOf(AType, AWidth, w);
  Result := '';
  for i := 0 to High(a) do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + FloatToStr(a[i]);
  end;
end;

function ArrText(const A: TTyDoubleArray): string;
var i: Integer;
begin
  Result := '';
  for i := 0 to High(A) do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + FloatToStr(A[i]);
  end;
end;

procedure TAdvChartToolboxExtraOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  FLog := TStringList.Create;
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath('advchart-toolbox-extra.json'));
    FRoot := GetJSON(sl.Text);
    sl.LoadFromFile(FixturePath('advchart-text-style.json'));
    FMeasure := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartToolboxExtraOracleTest.TearDown;
begin
  FLog.Free;
  FRoot.Free;
  FMeasure.Free;
  FBmp.Free;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

procedure TAdvChartToolboxExtraOracleTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 20000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TAdvChartToolboxExtraOracleTest.Near(const AWhat: string; AGot, AWant: Double);
begin
  Inc(FCompared);
  if Abs(AGot - AWant) > 1e-6 then
    Bad(Format('%s %g, upstream %g', [AWhat, AGot, AWant]));
end;

procedure TAdvChartToolboxExtraOracleTest.OnEvent(Sender: TObject;
  const AEvent: TTyChartEvent);
begin
  if (AEvent.EventType <> 'showtip') and (AEvent.EventType <> 'hidetip') then Exit;
  FLog.Add(AEvent.EventType);
end;

procedure TAdvChartToolboxExtraOracleTest.RunCase(const AId: string);
const
  cCap: array[0..2] of string = ('butt', 'round', 'square');
  cJoin: array[0..2] of string = ('miter', 'round', 'bevel');
var
  cases, steps, icons, ev: TJSONArray;
  cs, st, state, ic, sty, tt, tip: TJSONObject;
  probe: TTxProbe;
  i, j: Integer;
  op, want: string;
  now_, lw, fs: Double;
  list: TTyPaintList;
  el, box: TTyChartElement;
  d: TJSONData;
  c: TTyChartColor;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  cs := nil;
  for i := 0 to cases.Count - 1 do
    if cases.Objects[i].Strings['id'] = AId then cs := cases.Objects[i];
  AssertTrue('no case ' + AId, cs <> nil);
  probe := TTxProbe.Create(FForm);
  try
    probe.Parent := FForm;
    probe.Controller := FCtl;
    probe.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
      TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
      TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
    probe.TooltipNow := 0;
    probe.SetBounds(0, 0, cW, cH);
    probe.Option := cs.Objects['option'].AsJSON;
    probe.OnChartEvent := @OnEvent;
    probe.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
    now_ := 0;
    steps := cs.Arrays['steps'];
    for j := 0 to steps.Count - 1 do
    begin
      st := steps.Objects[j];
      op := st.Strings['op'];
      FWhere := Format('%s step %d (%s)', [AId, j, op]);
      FLog.Clear;
      if (op = 'move') or (op = 'leave') then
        now_ := now_ + TJSONObject(FRoot).Objects['clock'].Floats['stepDt']
      else if op = 'idle' then
        now_ := now_ + st.Floats['ms'];
      probe.TooltipNow := now_;
      probe.TooltipTick(now_);
      if op = 'move' then probe.Move(st.Arrays['at'].Integers[0], st.Arrays['at'].Integers[1])
      else if op = 'leave' then probe.Leave;
      { the zrender frame the oracle runs after every step: the icons' hover
        states land in it }
      probe.ToolboxFrame;
      probe.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
      { the events, by type }
      ev := st.Arrays['events'];
      Inc(FCompared);
      want := '';
      for i := 0 to ev.Count - 1 do want := want + TJSONArray(ev.Items[i]).Strings[1] + ',';
      FLog.Delimiter := ',';
      FLog.StrictDelimiter := True;
      if FLog.DelimitedText + ',' <> want then
        if not ((FLog.Count = 0) and (want = '')) then
          Bad(Format('events %s, upstream %s', [FLog.DelimitedText, want]));
      state := st.Objects['state'];
      { the icons }
      icons := state.Arrays['icons'];
      list := probe.Icons;
      try
        Inc(FCompared);
        if list.Count <> icons.Count then
          Bad(Format('%d icons, upstream %d', [list.Count, icons.Count]))
        else
          for i := 0 to icons.Count - 1 do
          begin
            ic := icons.Objects[i];
            sty := ic.Objects['style'];
            el := list.Element(i);
            lw := sty.Floats['lineWidth'];
            Near(Format('icon %d width', [i]), el.Style.StrokeWidthLogical, lw);
            Inc(FCompared);
            if ArrText(el.Style.DashLogical) <> DashText(sty.Find('lineDash'), lw) then
              Bad(Format('icon %d dash [%s], upstream [%s]', [i, ArrText(el.Style.DashLogical),
                DashText(sty.Find('lineDash'), lw)]));
            Near(Format('icon %d dash offset', [i]), el.Style.DashOffsetLogical, sty.Floats['lineDashOffset']);
            Inc(FCompared);
            if cCap[el.Style.LineCap] <> sty.Strings['lineCap'] then
              Bad(Format('icon %d cap %s, upstream %s', [i, cCap[el.Style.LineCap], sty.Strings['lineCap']]));
            want := 'miter';
            if sty.Find('lineJoin').JSONType = jtString then want := sty.Strings['lineJoin'];
            Inc(FCompared);
            if cJoin[el.Style.LineJoin] <> want then
              Bad(Format('icon %d join %s, upstream %s', [i, cJoin[el.Style.LineJoin], want]));
            if el.Style.MiterLimit > 0 then
              Near(Format('icon %d miter', [i]), el.Style.MiterLimit, sty.Floats['miterLimit'])
            else
              Near(Format('icon %d miter', [i]), 10, sty.Floats['miterLimit']);
          end;
      finally
        list.Free;
      end;
      { the title }
      d := state.Find('title');
      Inc(FCompared);
      if probe.TitleCaption(el) <> (d.JSONType = jtObject) then
        Bad(Format('a title %s, upstream %s', [BoolToStr(probe.TitleCaption(el), True),
          BoolToStr(d.JSONType = jtObject, True)]))
      else if d.JSONType = jtObject then
      begin
        tt := TJSONObject(d);
        Inc(FCompared);
        if el.Caption.Text <> tt.Strings['text'] then
          Bad(Format('title %s, upstream %s', [el.Caption.Text, tt.Strings['text']]));
        { the font: '<style> <weight> <size>px <family>' -- the size only
          where the option wrote one (unwritten it is the skin's, a design
          difference) }
        want := tt.Strings['font'];
        want := Copy(want, 1, Pos('px', want) - 1);
        want := Copy(want, LastDelimiter(' ', want) + 1, MaxInt);
        fs := StrToFloat(want);
        if Pos('Microsoft YaHei', tt.Strings['font']) = 0 then
        begin
          Inc(FCompared);
          if el.Caption.FontSizeLogical <> Round(fs) then
            Bad(Format('title size %d, upstream %s', [el.Caption.FontSizeLogical, tt.Strings['font']]));
        end;
        if Pos('italic', tt.Strings['font']) = 1 then
        begin
          Inc(FCompared);
          if (el.Caption.FontWeight and TyFontItalic) = 0 then Bad('title not italic, upstream ' + tt.Strings['font']);
        end;
        if Pos(' bold ', tt.Strings['font']) > 0 then
        begin
          Inc(FCompared);
          if (el.Caption.FontWeight and $FFFF) < 600 then Bad('title not bold, upstream ' + tt.Strings['font']);
        end;
        if Pos('px serif', tt.Strings['font']) > 0 then
        begin
          Inc(FCompared);
          if el.Caption.FontName <> 'serif' then Bad('title font ' + el.Caption.FontName + ', upstream ' + tt.Strings['font']);
        end;
        { the text's anchor: centre and the top of its line }
        Near('title x', el.Caption.X, tt.Floats['textX']);
        Near('title top', el.Caption.Y, tt.Floats['textY'] - fs / 2);
        { the box }
        Inc(FCompared);
        if probe.TitleBox(box) <> (tt.Find('box').JSONType = jtArray) then
          Bad(Format('a title box %s, upstream %s', [BoolToStr(probe.TitleBox(box), True),
            BoolToStr(tt.Find('box').JSONType = jtArray, True)]))
        else if tt.Find('box').JSONType = jtArray then
        begin
          Near('box top', TyShapeBounds(box.Shape).Top, tt.Arrays['box'].Floats[1]);
          Near('box height', TyShapeBounds(box.Shape).Bottom - TyShapeBounds(box.Shape).Top,
            tt.Arrays['box'].Floats[3]);
          Near('box centre', (TyShapeBounds(box.Shape).Left + TyShapeBounds(box.Shape).Right) / 2,
            tt.Arrays['box'].Floats[0] + tt.Arrays['box'].Floats[2] / 2);
          if TyTryParseChartColor(tt.Strings['backgroundColor'], c) then
          begin
            Inc(FCompared);
            if box.Style.FillColor <> c then
              Bad(Format('box fill %.8x, upstream %s', [box.Style.FillColor, tt.Strings['backgroundColor']]));
          end;
        end;
      end;
      { the tooltip }
      d := state.Find('tip');
      Inc(FCompared);
      if probe.TooltipShown <> (d.JSONType = jtObject) then
        Bad(Format('a box %s, upstream %s', [BoolToStr(probe.TooltipShown, True),
          BoolToStr(d.JSONType = jtObject, True)]))
      else if d.JSONType = jtObject then
      begin
        tip := TJSONObject(d);
        if Pos('toolbox:', tip.Strings['which']) = 1 then
        begin
          Inc(FCompared);
          if probe.TooltipShownWhich <> tip.Strings['which'] then
            Bad(Format('the box shows %s, upstream %s', [probe.TooltipShownWhich, tip.Strings['which']]));
          Inc(FCompared);
          if probe.TooltipFormatterText <> tip.Strings['text'] then
            Bad(Format('the text %s, upstream %s', [probe.TooltipFormatterText, tip.Strings['text']]));
        end
        else
        begin
          Inc(FCompared);
          if probe.Which <> tip.Strings['which'] then
            Bad(Format('the box shows %s, upstream %s', [probe.Which, tip.Strings['which']]));
        end;
        Near('box x', probe.TooltipBox.Left, tip.Arrays['box'].Floats[0]);
        Near('box y', probe.TooltipBox.Top, tip.Arrays['box'].Floats[1]);
      end;
    end;
  finally
    probe.Free;
  end;
  AssertTrue(AId + ': nothing compared', FCompared > 0);
  AssertEquals(Format('%s: %d of %d comparisons differ:%s',
    [AId, FBad, FCompared, FReport]), 0, FBad);
end;

procedure TAdvChartToolboxExtraOracleTest.TestTheIconsLineKeysAsUpstream;
begin
  RunCase('icon-line');
end;

procedure TAdvChartToolboxExtraOracleTest.TestAnUnevenTitlePaddingAsUpstream;
begin
  RunCase('title-pad');
end;

procedure TAdvChartToolboxExtraOracleTest.TestTheTitlesBoxAsUpstream;
begin
  RunCase('title-box');
end;

procedure TAdvChartToolboxExtraOracleTest.TestTheIconsTooltipAsUpstream;
begin
  RunCase('tooltip');
end;

procedure TAdvChartToolboxExtraOracleTest.TestATooltipTemplateAsUpstream;
begin
  RunCase('tooltip-fmt');
end;

procedure TAdvChartToolboxExtraOracleTest.TestTheTooltipOffAsUpstream;
begin
  RunCase('tooltip-off');
end;

{ a JSON value with its objects' keys sorted, numbers as %.10g }
function CanonJ(AData: TJSONData): string;
var
  i: Integer;
  keys: TStringList;
  o: TJSONObject;
begin
  if AData = nil then Exit('undefined');
  case AData.JSONType of
    jtNull: Result := 'null';
    jtBoolean: if AData.AsBoolean then Result := 'true' else Result := 'false';
    jtNumber: Result := FloatToStrF(AData.AsFloat, ffGeneral, 10, 0, DefaultFormatSettings);
    jtString: Result := '"' + AData.AsString + '"';
    jtArray:
      begin
        Result := '[';
        for i := 0 to AData.Count - 1 do
        begin
          if i > 0 then Result := Result + ',';
          Result := Result + CanonJ(AData.Items[i]);
        end;
        Result := Result + ']';
      end;
    jtObject:
      begin
        o := TJSONObject(AData);
        keys := TStringList.Create;
        try
          keys.Sorted := True;
          for i := 0 to o.Count - 1 do keys.Add(o.Names[i]);
          Result := '{';
          for i := 0 to keys.Count - 1 do
          begin
            if i > 0 then Result := Result + ',';
            Result := Result + keys[i] + ':' + CanonJ(o.Find(keys[i]));
          end;
          Result := Result + '}';
        finally
          keys.Free;
        end;
      end;
  else
    Result := '?';
  end;
end;

procedure TAdvChartMagicTypeDefaultsOracleTest.OnEvent(Sender: TObject;
  const AEvent: TTyChartEvent);
begin
  if AEvent.EventType = 'magictypechanged' then FPays.Add(AEvent.Payload);
end;

procedure TAdvChartMagicTypeDefaultsOracleTest.TestTheNewSeriesKeepTheOldDefaultsAsUpstream;
const
  { the keys the port writes its own way: the data (its store's), the marks
    (absent rather than []) }
  cSkip: array[0..3] of string = ('data', 'markPoint', 'markLine', 'seriesIndex');
var
  root: TJSONData;
  sl: TStringList;
  cs, click, want, gotS: TJSONObject;
  clicks, wantArr, gotArr: TJSONArray;
  form: TForm;
  ctl: TTyStyleController;
  chart: TTxProbe;
  bmp: TBGRABitmap;
  pay: TJSONData;
  c, s, k, si, bad, compared: Integer;
  key, report: string;
  skip: Boolean;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath('advchart-magictype-defaults.json'));
    root := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FPays := TStringList.Create;
  form := TForm.CreateNew(nil);
  ctl := TTyStyleController.Create(nil);
  bmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  bad := 0;
  compared := 0;
  report := '';
  try
    ctl.Mode := 'light';
    ctl.ThemeName := 'default';
    cs := TJSONObject(root).Arrays['cases'].Objects[0];
    chart := TTxProbe.Create(form);
    chart.Parent := form;
    chart.Controller := ctl;
    chart.SetBounds(0, 0, cW, cH);
    chart.Option := cs.Objects['option'].AsJSON;
    chart.OnChartEvent := @OnEvent;
    chart.Render(bmp.Canvas, Rect(0, 0, cW, cH), 96);
    clicks := cs.Arrays['clicks'];
    for c := 0 to clicks.Count - 1 do
    begin
      click := clicks.Objects[c];
      FPays.Clear;
      AssertTrue('the icon ' + click.Strings['icon'],
        chart.ToolboxClick(0, 'magicType', click.Strings['icon']));
      chart.Render(bmp.Canvas, Rect(0, 0, cW, cH), 96);
      AssertEquals(click.Strings['icon'] + ': one magictypechanged', 1, FPays.Count);
      pay := GetJSON(FPays[0]);
      try
        gotArr := TJSONObject(pay).Objects['newOption'].Arrays['series'];
        wantArr := click.Arrays['series'];
        for s := 0 to wantArr.Count - 1 do
        begin
          want := wantArr.Objects[s];
          si := want.Integers['seriesIndex'];
          if (si >= gotArr.Count) or not (gotArr.Items[si] is TJSONObject) then
          begin
            Inc(bad);
            report := report + Format('%s: series %d not in the payload; ', [click.Strings['icon'], si]);
            Continue;
          end;
          gotS := TJSONObject(gotArr.Items[si]);
          { every key upstream hands the series, and none it does not }
          for k := 0 to want.Count - 1 do
          begin
            key := want.Names[k];
            skip := False;
            for si := 0 to High(cSkip) do if cSkip[si] = key then skip := True;
            si := want.Integers['seriesIndex'];
            if skip then Continue;
            Inc(compared);
            if CanonJ(gotS.Find(key)) <> CanonJ(want.Items[k]) then
            begin
              Inc(bad);
              if bad <= 20 then
                report := report + Format('%s: series %d %s %s, upstream %s; ',
                  [click.Strings['icon'], si, key, CanonJ(gotS.Find(key)), CanonJ(want.Items[k])]);
            end;
          end;
          for k := 0 to gotS.Count - 1 do
          begin
            key := gotS.Names[k];
            skip := False;
            for si := 0 to High(cSkip) do if cSkip[si] = key then skip := True;
            si := want.Integers['seriesIndex'];
            if skip or (want.Find(key) <> nil) then Continue;
            Inc(bad);
            if bad <= 20 then
              report := report + Format('%s: series %d %s here, not upstream; ',
                [click.Strings['icon'], si, key]);
          end;
        end;
      finally
        pay.Free;
      end;
    end;
  finally
    bmp.Free;
    form.Free;
    ctl.Free;
    FPays.Free;
    root.Free;
  end;
  AssertTrue('nothing compared', compared > 100);
  AssertEquals(Format('%d of %d differ: %s', [bad, compared, report]), 0, bad);
end;

initialization
  RegisterTest(TAdvChartToolboxExtraOracleTest);
  RegisterTest(TAdvChartMagicTypeDefaultsOracleTest);
end.
