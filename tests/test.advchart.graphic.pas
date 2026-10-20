unit test.advchart.graphic;
{$mode objfpc}{$H+}
{ THE GRAPHIC COMPONENT, HELD TO UPSTREAM [Batch 122, C13].

  tools/advchart-oracle/graphic.js runs the real ECharts 6.1 build in node
  (server-side, zrender's width table for text) and records, state by
  state -- after the first setOption and after every merge, notMerge,
  resize or pointer step:

    the elements  depth first: id, type, parent, name, the transform props
                  and the global matrix, z / zlevel / z2, silent, ignore,
                  invisible, cursor, draggable, a group's size, the
                  bounding rect, the shape, the PathProxy data, the style,
                  a text's pieces (its TSpans and box rects), a textContent's
                  place, default style and pieces, the event data and info;
    the model     getOption's flat element list (id, type, parentId);
    the order     the display list as owner tags against the series and
                  the axes;
    the pointer   every element handler call (bubbling) and the chart's
                  events;
    transitions   every element's animated props at fixed samples.

  This replays it through the control, bit for bit. Text is measured with
  zrender's width table. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Shape,
     tyControls.AdvanceChart.Paint, tyControls.AdvanceChart.Color,
     tyControls.AdvanceChart.Events, tyControls.AdvanceChart.ZrPath,
     tyControls.AdvanceChart.Anim, tyControls.AdvanceChart.RichText,
     tyControls.AdvanceChart.RichStyle,
     tyControls.AdvanceChart.GfxEl, tyControls.AdvanceChart.Graphic,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TGfxLogEntry = record
    Fn, EventType, Self_, Target: string;
  end;

  TGfxProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    Events: array of TTyChartEvent;
    Log: array of TGfxLogEntry;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
    { the measurer the chart lays its texts out with [R2-F] }
    function NewTextMeasurerForTest: ITyTextMeasurer;
    procedure Down(AX, AY: Integer);
    procedure Move(AX, AY: Integer);
    procedure Up(AX, AY: Integer);
    procedure OnEvent(Sender: TObject; const AEvent: TTyChartEvent);
    function OnElement(Sender: TObject; const AEvent: TTyChartElementEvent): Boolean;
  end;

  TAdvChartGraphicTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TGfxProbe;
    FRoot: TJSONData;
    FBad, FCompared, FEls, FPieces, FSamples, FEventsSeen: Integer;
    FReport, FWhere: string;
    procedure Bad(const AWhat: string);
    procedure Same(const AWhat: string; AGot: Double; AWant: TJSONData);
    procedure SameStr(const AWhat, AGot, AWant: string);
    procedure SameBool(const AWhat: string; AGot, AWant: Boolean);
    procedure SameInt(const AWhat: string; AGot, AWant: Integer);
    procedure SameColour(const AWhat: string; AHas: Boolean; AGot: TTyChartColor;
      AWant: TJSONData);
    procedure SameValue(const AWhat: string; const AGot: TTyAnimValue; AWant: TJSONData);
    procedure SameRect(const AWhat: string; const AGot: TTyXYWH; AWant: TJSONObject);
    procedure SameMatrix(const AWhat: string; AHas: Boolean; const AGot: TTyMat2D;
      AWant: TJSONData);
    procedure Finish(const AWhat: string; AMin: Integer);
    function Cases: TJSONArray;
    function CaseById(const AId: string): TJSONObject;
    function PortOption(AOption: TJSONData): string;
    procedure NewChart(AW, AH: Integer);
    procedure RenderNow;
    procedure Show(ACase: TJSONObject);
    procedure RunStep(AStep: TJSONObject; AState: TJSONObject);
    function Walk: TTyGfxElArray;
    function FindInTree(const AId: string): TTyGfxEl;
    procedure CheckPieces(const AWhat: string; const APieces: TTyRtPieceArray;
      AWant: TJSONArray);
    procedure CheckTextStyle(const AWhat: string; AEl: TTyGfxEl; AWant: TJSONObject);
    procedure CheckEl(AEl: TTyGfxEl; AWant: TJSONObject);
    procedure CheckEls(AWant: TJSONArray);
    procedure CheckModel(AWant: TJSONArray);
    procedure CheckOrder(AWant: TJSONArray);
    procedure CheckPointer(AState: TJSONObject);
    procedure CheckSnap(AEl: TTyGfxEl; ASnap: TJSONObject);
    procedure CheckSamples(AState: TJSONObject; AStart: Double);
    procedure SameD(const AWhat: string; AGot, AWant: Double);
    procedure RunStatic(const AIds: array of string; AWithOrder: Boolean);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheShapesAreUpstreams;
    procedure TestTheTextsAreUpstreams;
    procedure TestThePlacementsAreUpstreams;
    procedure TestTheOrderAndTheFlagsAreUpstreams;
    procedure TestTheMergesAreUpstreams;
    procedure TestTheEventsAreUpstreams;
    procedure TestTheTransitionsAreUpstreams;
    { beyond the fixture }
    procedure TestThePreprocessorShapesTheOption;
    procedure TestATurnedRectIsHitWhereItIsDrawn;
    procedure TestAnImageIsAPatternThroughItsTransform;
    procedure TestAnUnknownTypeStopsTheUpdate;
    procedure TestADraggableElementFollowsThePointer;
  end;

implementation

{ ==================== the probe ==================== }

function TGfxProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TGfxProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TGfxProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function TGfxProbe.NewTextMeasurerForTest: ITyTextMeasurer;
begin
  Result := NewTextMeasurer(96);
end;

procedure TGfxProbe.Down(AX, AY: Integer);
begin
  MouseDown(mbLeft, [], AX, AY);
end;

procedure TGfxProbe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TGfxProbe.Up(AX, AY: Integer);
begin
  MouseUp(mbLeft, [], AX, AY);
end;

procedure TGfxProbe.OnEvent(Sender: TObject; const AEvent: TTyChartEvent);
begin
  if (AEvent.EventType <> 'click') and (AEvent.EventType <> 'mouseover')
    and (AEvent.EventType <> 'mouseout') then Exit;
  if not AEvent.HasParams or (AEvent.Params.ComponentType <> 'graphic') then Exit;
  SetLength(Events, Length(Events) + 1);
  Events[High(Events)] := AEvent;
end;

function TGfxProbe.OnElement(Sender: TObject; const AEvent: TTyChartElementEvent): Boolean;
var
  n: Integer;
  spec: string;
begin
  spec := Copy(AEvent.Handler, 2, MaxInt);
  n := Length(Log);
  SetLength(Log, n + 1);
  Log[n].Fn := Copy(spec, Pos(':', spec) + 1, MaxInt);
  Log[n].EventType := AEvent.EventType;
  Log[n].Self_ := TyGfxIdText(AEvent.Id);
  Log[n].Target := TyGfxIdText(AEvent.TargetId);
  Result := Copy(spec, 1, 5) = 'stop:';
end;

{ ==================== helpers ==================== }

function FixturePath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + AName;
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  Result := 0;
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

function HexOf(A: Double): string;
var q: QWord;
begin
  Move(A, q, SizeOf(q));
  Result := LowerCase(IntToHex(q, 16));
end;

function Txt(A: Double): string;
var fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := FloatToStrF(A, ffGeneral, 17, 0, fs);
end;

function SameBits(A, B: Double): Boolean;
begin
  Result := (HexOf(A) = HexOf(B)) or (IsNan(A) and IsNan(B))
    or ((A = 0) and (B = 0));
end;

function IsNull(AData: TJSONData): Boolean;
begin
  Result := (AData = nil) or (AData.JSONType = jtNull);
end;

function IsHex(AData: TJSONData): Boolean;
var s: string; i: Integer;
begin
  Result := False;
  if (AData = nil) or (AData.JSONType <> jtString) then Exit;
  s := AData.AsString;
  if Length(s) <> 16 then Exit;
  for i := 1 to 16 do
    if not (s[i] in ['0'..'9', 'a'..'f']) then Exit;
  Result := True;
end;

{ PathProxy's data: each command's code, then its numbers }
function PathData(const APath: TTyZrPath): TTyDoubleArray;
const
  cCode: array[TTyZrCmd] of Integer = (1, 2, 3, 4, 5, 6, 7);
var
  i, k, n: Integer;
begin
  Result := nil;
  n := 0;
  for i := 0 to High(APath) do
  begin
    SetLength(Result, n + 1 + TyZrArgCount(APath[i].Cmd));
    Result[n] := cCode[APath[i].Cmd];
    Inc(n);
    for k := 0 to TyZrArgCount(APath[i].Cmd) - 1 do
    begin
      Result[n] := APath[i].V[k];
      Inc(n);
    end;
  end;
end;

function AlignName(A: TTyRtAlign): string;
begin
  case A of
    rtaCenter: Result := 'center';
    rtaRight: Result := 'right';
  else
    Result := 'left';
  end;
end;

{ ==================== the case ==================== }

procedure TAdvChartGraphicTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  AssertTrue('the fixture is where the suite expects it',
    FileExists(FixturePath('advchart-graphic.json')));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath('advchart-graphic.json'));
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FChart := nil;
  FBad := 0;
  FCompared := 0;
  FEls := 0;
  FPieces := 0;
  FSamples := 0;
  FEventsSeen := 0;
  FReport := '';
end;

procedure TAdvChartGraphicTest.TearDown;
begin
  TyChartClearElementHandlers;
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FChart);
  FreeAndNil(FRoot);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartGraphicTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 16000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TAdvChartGraphicTest.Same(const AWhat: string; AGot: Double; AWant: TJSONData);
var want: Double;
begin
  Inc(FCompared);
  if IsNull(AWant) then
  begin
    Bad(AWhat + ': upstream has no number');
    Exit;
  end;
  if AWant.JSONType = jtNumber then want := AWant.AsFloat
  else want := FromHex(AWant.AsString);
  if not SameBits(AGot, want) then
    Bad(Format('%s %s, upstream %s', [AWhat, Txt(AGot), Txt(want)]));
end;

procedure TAdvChartGraphicTest.SameD(const AWhat: string; AGot, AWant: Double);
begin
  Inc(FCompared);
  if not SameBits(AGot, AWant) then
    Bad(Format('%s %s, upstream %s', [AWhat, Txt(AGot), Txt(AWant)]));
end;

procedure TAdvChartGraphicTest.SameStr(const AWhat, AGot, AWant: string);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Bad(Format('%s "%s", upstream "%s"', [AWhat, AGot, AWant]));
end;

procedure TAdvChartGraphicTest.SameBool(const AWhat: string; AGot, AWant: Boolean);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Bad(Format('%s %s, upstream %s', [AWhat, BoolToStr(AGot, True), BoolToStr(AWant, True)]));
end;

procedure TAdvChartGraphicTest.SameInt(const AWhat: string; AGot, AWant: Integer);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Bad(Format('%s %d, upstream %d', [AWhat, AGot, AWant]));
end;

procedure TAdvChartGraphicTest.SameColour(const AWhat: string; AHas: Boolean;
  AGot: TTyChartColor; AWant: TJSONData);
var want: TTyChartColor;
begin
  Inc(FCompared);
  if IsNull(AWant) or (AWant.JSONType <> jtString)
    or not TyTryParseChartColor(AWant.AsString, want) then
  begin
    if AHas then Bad(Format('%s %s, upstream no colour', [AWhat, IntToHex(AGot, 8)]));
    Exit;
  end;
  if (not AHas) or (AGot <> want) then
    Bad(Format('%s %s (%s), upstream %s', [AWhat, IntToHex(AGot, 8),
      BoolToStr(AHas, True), AWant.AsString]));
end;

procedure TAdvChartGraphicTest.SameValue(const AWhat: string;
  const AGot: TTyAnimValue; AWant: TJSONData);
var
  i, k, n: Integer;
  row: TJSONData;
begin
  if IsNull(AWant) then
  begin
    Inc(FCompared);
    if AGot.Kind <> avkNull then Bad(AWhat + ': a value, upstream none');
    Exit;
  end;
  case AWant.JSONType of
    jtBoolean:
      begin
        Inc(FCompared);
        if (AGot.Kind <> avkBool) or ((AGot.Num <> 0) <> AWant.AsBoolean) then
          Bad(AWhat + ': not the boolean ' + AWant.AsJSON);
      end;
    jtString:
      if IsHex(AWant) then
      begin
        if AGot.Kind = avkNumber then Same(AWhat, AGot.Num, AWant)
        else Bad(AWhat + ': no number, upstream ' + Txt(FromHex(AWant.AsString)));
      end
      else
      begin
        if AGot.Kind = avkString then SameStr(AWhat, AGot.Str, AWant.AsString)
        else Bad(AWhat + ': no text, upstream ' + AWant.AsString);
      end;
    jtArray:
      begin
        if AGot.Kind <> avkArray then
        begin
          Bad(AWhat + ': no array');
          Exit;
        end;
        if (AWant.Count > 0) and (AWant.Items[0].JSONType = jtArray) then
        begin
          n := 0;
          for i := 0 to AWant.Count - 1 do
          begin
            row := AWant.Items[i];
            for k := 0 to row.Count - 1 do
            begin
              if n <= High(AGot.Arr) then Same(Format('%s[%d][%d]', [AWhat, i, k]), AGot.Arr[n], row.Items[k])
              else Bad(AWhat + ': short');
              Inc(n);
            end;
          end;
        end
        else
        begin
          SameInt(AWhat + ' length', Length(AGot.Arr), AWant.Count);
          for i := 0 to Min(AWant.Count, Length(AGot.Arr)) - 1 do
            Same(Format('%s[%d]', [AWhat, i]), AGot.Arr[i], AWant.Items[i]);
        end;
      end;
  else
    Bad(AWhat + ': an unexpected record ' + AWant.AsJSON);
  end;
end;

procedure TAdvChartGraphicTest.SameRect(const AWhat: string; const AGot: TTyXYWH;
  AWant: TJSONObject);
begin
  Same(AWhat + '.x', AGot.X, AWant.Find('x'));
  Same(AWhat + '.y', AGot.Y, AWant.Find('y'));
  Same(AWhat + '.width', AGot.W, AWant.Find('width'));
  Same(AWhat + '.height', AGot.H, AWant.Find('height'));
end;

procedure TAdvChartGraphicTest.SameMatrix(const AWhat: string; AHas: Boolean;
  const AGot: TTyMat2D; AWant: TJSONData);
var
  k: Integer;
  m: TTyMat2D;
begin
  if not AHas then
  begin
    m[0] := 1; m[1] := 0; m[2] := 0; m[3] := 1; m[4] := 0; m[5] := 0;
  end
  else
    m := AGot;
  if IsNull(AWant) then
  begin
    Inc(FCompared);
    if not ((m[0] = 1) and (m[1] = 0) and (m[2] = 0) and (m[3] = 1) and (m[4] = 0) and (m[5] = 0)) then
      Bad(AWhat + ': a transform, upstream none');
    Exit;
  end;
  for k := 0 to 5 do Same(Format('%s[%d]', [AWhat, k]), m[k], AWant.Items[k]);
end;

procedure TAdvChartGraphicTest.Finish(const AWhat: string; AMin: Integer);
begin
  AssertEquals(Format('%s: %d of %d comparisons differ:%s',
    [AWhat, FBad, FCompared, FReport]), 0, FBad);
  AssertTrue(Format('%s: only %d compared', [AWhat, FCompared]), FCompared >= AMin);
end;

function TAdvChartGraphicTest.Cases: TJSONArray;
begin
  Result := TJSONObject(FRoot).Arrays['cases'];
end;

function TAdvChartGraphicTest.CaseById(const AId: string): TJSONObject;
var i: Integer;
begin
  for i := 0 to Cases.Count - 1 do
    if Cases.Objects[i].Strings['id'] = AId then Exit(Cases.Objects[i]);
  Result := nil;
  Fail('no case ' + AId);
end;

{ the option as the port reads it: {$fn: 'log:A'} is '@log:A' }
function TAdvChartGraphicTest.PortOption(AOption: TJSONData): string;

  function Conv(D: TJSONData): TJSONData;
  var
    i: Integer;
    o: TJSONObject;
    a: TJSONArray;
  begin
    if D is TJSONObject then
    begin
      if (D.Count = 1) and (TJSONObject(D).Find('$fn') <> nil) then
        Exit(TJSONString.Create('@' + TJSONObject(D).Strings['$fn']));
      o := TJSONObject.Create;
      for i := 0 to D.Count - 1 do o.Add(TJSONObject(D).Names[i], Conv(D.Items[i]));
      Exit(o);
    end;
    if D is TJSONArray then
    begin
      a := TJSONArray.Create;
      for i := 0 to D.Count - 1 do a.Add(Conv(D.Items[i]));
      Exit(a);
    end;
    Result := D.Clone;
  end;

var c: TJSONData;
begin
  c := Conv(AOption);
  try
    Result := c.AsJSON;
  finally
    c.Free;
  end;
end;

procedure TAdvChartGraphicTest.NewChart(AW, AH: Integer);
var m: TJSONObject;
begin
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FChart);
  FChart := TGfxProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  m := TJSONObject(FRoot).Objects['measure'];
  FChart.Measurer := TPtToPxMeasurer.Create(
    TZrSsrMeasurer.Create(m.Arrays['ratio'], m.Integers['firstCode']));
  FChart.OnChartEvent := @FChart.OnEvent;
  FChart.AnimationMode := camOff;
  FChart.SetBounds(0, 0, AW, AH);
  TyChartClearElementHandlers;
  TyChartRegisterElementHandler('log:A', @FChart.OnElement);
  TyChartRegisterElementHandler('log:Aover', @FChart.OnElement);
  TyChartRegisterElementHandler('log:Aout', @FChart.OnElement);
  TyChartRegisterElementHandler('log:G', @FChart.OnElement);
  TyChartRegisterElementHandler('stop:C', @FChart.OnElement);
  TyChartRegisterElementHandler('log:S', @FChart.OnElement);
  TyChartRegisterElementHandler('log:I', @FChart.OnElement);
  TyChartRegisterElementHandler('log:N', @FChart.OnElement);
  TyChartRegisterElementHandler('log:T', @FChart.OnElement);
end;

procedure TAdvChartGraphicTest.RenderNow;
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(FChart.Width, FChart.Height, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, FChart.Width, FChart.Height), 96);
  finally
    bmp.Free;
  end;
end;

procedure TAdvChartGraphicTest.Show(ACase: TJSONObject);
begin
  NewChart(ACase.Integers['W'], ACase.Integers['H']);
  FChart.Option := PortOption(ACase.Objects['option']);
  RenderNow;
end;

function TAdvChartGraphicTest.Walk: TTyGfxElArray;
begin
  Result := nil;
  TyGfxTraverse(FChart.GraphicView.Root, Result);
end;

function TAdvChartGraphicTest.FindInTree(const AId: string): TTyGfxEl;
var
  list: TTyGfxElArray;
  i: Integer;
begin
  list := Walk;
  for i := 0 to High(list) do
    if TyGfxIdText(list[i].Id) = AId then Exit(list[i]);
  Result := nil;
end;

procedure TAdvChartGraphicTest.CheckPieces(const AWhat: string;
  const APieces: TTyRtPieceArray; AWant: TJSONArray);
var
  i: Integer;
  w: TJSONObject;
  p: TTyRtPiece;
  px: Double;
  weight: Integer;
  family: string;
  italic: Boolean;
  where: string;
begin
  SameInt(AWhat + ' pieces', Length(APieces), AWant.Count);
  for i := 0 to Min(Length(APieces), AWant.Count) - 1 do
  begin
    Inc(FPieces);
    w := AWant.Objects[i];
    p := APieces[i];
    where := Format('%s piece %d', [AWhat, i]);
    if w.Strings['k'] = 't' then
    begin
      if p.Kind <> rpkText then
      begin
        Bad(where + ': not a text');
        Continue;
      end;
      SameStr(where + ' text', p.Text, w.Get('text', ''));
      Same(where + ' x', p.X, w.Find('x'));
      Same(where + ' y', p.Y, w.Find('y'));
      TyGfxParseFont(w.Get('font', ''), px, weight, family, italic);
      SameD(where + ' font size', p.FontSizePx, px);
      SameBool(where + ' bold', p.FontWeight >= 600, weight >= 600);
      SameStr(where + ' family', p.FontFamily, family);
      SameStr(where + ' align', AlignName(p.TextAlign), w.Get('align', 'left'));
      SameStr(where + ' baseline', 'middle', w.Get('base', 'middle'));
      SameColour(where + ' fill', p.HasFill, p.Fill, w.Find('fill'));
      SameColour(where + ' stroke', p.HasStroke, p.Stroke, w.Find('stroke'));
      if p.HasStroke and not IsNull(w.Find('stroke')) then
        Same(where + ' lineWidth', p.LineWidth, w.Find('lineWidth'));
      Same(where + ' opacity', p.Opacity, w.Find('opacity'));
    end
    else if w.Strings['k'] = 'r' then
    begin
      if p.Kind <> rpkRect then
      begin
        Bad(where + ': not a rect');
        Continue;
      end;
      Same(where + ' x', p.X, w.Find('x'));
      Same(where + ' y', p.Y, w.Find('y'));
      Same(where + ' width', p.W, w.Find('width'));
      Same(where + ' height', p.H, w.Find('height'));
      SameColour(where + ' fill', p.HasFill, p.Fill, w.Find('fill'));
      SameColour(where + ' stroke', p.HasStroke, p.Stroke, w.Find('stroke'));
    end;
  end;
end;

procedure TAdvChartGraphicTest.CheckTextStyle(const AWhat: string; AEl: TTyGfxEl;
  AWant: TJSONObject);
var
  font: string;
  v: TTyAnimValue;
begin
  SameStr(AWhat + ' text', AEl.Style.Get('text', ''), AWant.Get('text', ''));
  font := TyGfxMakeFont(AEl.Style);
  if IsNull(AWant.Find('font')) then SameStr(AWhat + ' font', font, '')
  else SameStr(AWhat + ' font', font, AWant.Strings['font']);
  v := AEl.StyleValue('fill');
  if v.Kind = avkString then SameStr(AWhat + ' fill', v.Str, AWant.Get('fill', ''))
  else SameBool(AWhat + ' no fill', True, IsNull(AWant.Find('fill')));
  v := AEl.StyleValue('align');
  if (v.Kind = avkString) and not IsNull(AWant.Find('align')) then
    SameStr(AWhat + ' align', v.Str, AWant.Strings['align'])
  else
    SameBool(AWhat + ' no align', v.Kind <> avkString, IsNull(AWant.Find('align')));
end;

procedure TAdvChartGraphicTest.CheckEl(AEl: TTyGfxEl; AWant: TJSONObject);
const
  cT: array[0..10] of string = ('x', 'y', 'rotation', 'scaleX', 'scaleY',
    'originX', 'originY', 'skewX', 'skewY', 'anchorX', 'anchorY');
  cImg: array[0..3] of string = ('x', 'y', 'width', 'height');
var
  t, sh, st, lab, inner, def, rect: TJSONObject;
  k, i: Integer;
  parentId, s: string;
  path: TTyDoubleArray;
  want: TJSONArray;
  d: TJSONData;
  tc: TTyGfxEl;
  wantInfo: TJSONData;
  meas: ITyTextMeasurer;
begin
  Inc(FEls);
  meas := FChart.Measurer;
  FWhere := FWhere + ' ' + AWant.Strings['id'];
  try
    SameStr('id', TyGfxIdText(AEl.Id), AWant.Strings['id']);
    SameStr('type', AEl.ZrType, AWant.Strings['type']);
    SameStr('gtype', AEl.GType, AWant.Strings['gtype']);
    if (AEl.Parent <> nil) and (AEl.Parent <> FChart.GraphicView.Root) then
      parentId := TyGfxIdText(AEl.Parent.Id)
    else
      parentId := '';
    if IsNull(AWant.Find('parent')) then SameStr('parent', parentId, '')
    else SameStr('parent', parentId, AWant.Strings['parent']);
    SameStr('name', AEl.Name, AWant.Get('name', ''));
    t := AWant.Objects['t'];
    for k := 0 to High(cT) do Same(cT[k], AEl.GetAnimProp(cT[k]).Num, t.Find(cT[k]));
    SameMatrix('transform', AEl.HasTransform, AEl.Transform, AWant.Find('transform'));
    SameBool('silent', AEl.Silent, AWant.Booleans['silent']);
    SameBool('ignore', AEl.Ignore, AWant.Booleans['ignore']);
    SameBool('invisible', AEl.Invisible, AWant.Booleans['invisible']);
    d := AWant.Find('draggable');
    if (d <> nil) and (d.JSONType = jtBoolean) then
      SameBool('draggable', AEl.Draggable <> '', d.AsBoolean)
    else if (d <> nil) and (d.JSONType = jtString) then
      SameStr('draggable', AEl.Draggable, d.AsString);
    if not AEl.IsGroup then
    begin
      SameStr('cursor', AEl.Cursor, AWant.Get('cursor', ''));
      Same('z', AEl.Z, AWant.Find('z'));
      Same('zlevel', AEl.ZLevel, AWant.Find('zlevel'));
      Same('z2', AEl.Z2, AWant.Find('z2'));
    end
    else
    begin
      Same('size.width', AEl.InnerW, AWant.Objects['size'].Find('width'));
      Same('size.height', AEl.InnerH, AWant.Objects['size'].Find('height'));
    end;
    SameRect('rect', TyGfxRect(AEl, meas), AWant.Objects['rect']);
    SameBool('eventData', AEl.HasEventData, AWant.Booleans['eventData']);
    d := AWant.Find('info');
    if IsNull(d) then SameBool('no info', AEl.Info = nil, True)
    else
    begin
      wantInfo := GetJSON(d.AsString);
      try
        if AEl.Info = nil then Bad('no info, upstream ' + d.AsString)
        else SameStr('info', AEl.Info.AsJSON, wantInfo.AsJSON);
      finally
        wantInfo.Free;
      end;
    end;
    sh := nil;
    if AWant.Find('shape') is TJSONObject then sh := AWant.Objects['shape'];
    if sh <> nil then
      for i := 0 to sh.Count - 1 do
        SameValue('shape.' + sh.Names[i], AEl.GetAnimProp('shape.' + sh.Names[i]), sh.Items[i]);
    if AWant.Find('path') is TJSONArray then
    begin
      want := AWant.Arrays['path'];
      path := PathData(TyGfxPath(AEl));
      SameInt('path length', Length(path), want.Count);
      for i := 0 to Min(Length(path), want.Count) - 1 do
        Same(Format('path[%d]', [i]), path[i], want.Items[i]);
    end;
    st := nil;
    if AWant.Find('style') is TJSONObject then st := AWant.Objects['style'];
    if st <> nil then
    begin
      case AEl.Kind of
        gkText: CheckTextStyle('style', AEl, st);
        gkImage:
          begin
            SameStr('style.image', AEl.Style.Get('image', ''), st.Get('image', ''));
            for k := 0 to 3 do
            begin
              s := cImg[k];
              d := st.Find(s);
              if IsNull(d) then SameBool('style.' + s + ' none', IsNull(AEl.Style.Find(s)), True)
              else SameValue('style.' + s, AEl.StyleValue(s), d);
            end;
            SameValue('style.opacity', AEl.StyleValue('opacity'), st.Find('opacity'));
          end;
      else
        SameValue('style.fill', AEl.StyleValue('fill'), st.Find('fill'));
        SameValue('style.stroke', AEl.StyleValue('stroke'), st.Find('stroke'));
        SameValue('style.lineWidth', AEl.StyleValue('lineWidth'), st.Find('lineWidth'));
        SameValue('style.opacity', AEl.StyleValue('opacity'), st.Find('opacity'));
        if not IsNull(st.Find('lineDash')) then
          SameValue('style.lineDash', AEl.StyleValue('lineDash'), st.Find('lineDash'));
      end;
    end;
    if AWant.Find('pieces') is TJSONArray then
      CheckPieces('text', TyGfxTextLayout(AEl, meas).Pieces, AWant.Arrays['pieces']);
    { the textContent }
    tc := AEl.TextContent;
    if AWant.Find('label') is TJSONObject then
    begin
      lab := AWant.Objects['label'];
      if tc = nil then
        Bad('no textContent')
      else
      begin
        SameMatrix('label transform', tc.HasTransform, tc.Transform, lab.Find('transform'));
        inner := lab.Objects['inner'];
        Same('label inner.x', tc.InX, inner.Find('x'));
        Same('label inner.y', tc.InY, inner.Find('y'));
        Same('label inner.rotation', tc.InRot, inner.Find('rotation'));
        Same('label inner.originX', tc.InOX, inner.Find('originX'));
        Same('label inner.originY', tc.InOY, inner.Find('originY'));
        def := lab.Objects['def'];
        SameStr('label def.fill', tc.DefFill, def.Get('fill', ''));
        SameStr('label def.stroke', tc.DefStroke, def.Get('stroke', ''));
        SameBool('label def.autoStroke', tc.DefAutoStroke, def.Booleans['autoStroke']);
        SameStr('label def.align', tc.DefAlign, def.Get('align', ''));
        SameStr('label def.verticalAlign', tc.DefVAlign, def.Get('verticalAlign', ''));
        CheckTextStyle('label style', tc, lab.Objects['style']);
        CheckPieces('label', TyGfxTextLayout(tc, meas).Pieces, lab.Arrays['pieces']);
        rect := lab.Objects['rect'];
        SameRect('label rect', TyGfxRect(tc, meas), rect);
        Same('label z', tc.Z, lab.Find('z'));
        Same('label z2', tc.Z2, lab.Find('z2'));
        Same('label zlevel', tc.ZLevel, lab.Find('zlevel'));
        SameBool('label ignore', tc.Ignore, lab.Booleans['ignore']);
        SameBool('label silent', tc.Silent, lab.Booleans['silent']);
      end;
    end
    else if not AEl.IsGroup then
      SameBool('no textContent', tc = nil, True);
  finally
    FWhere := Copy(FWhere, 1, Length(FWhere) - Length(AWant.Strings['id']) - 1);
  end;
end;

procedure TAdvChartGraphicTest.CheckEls(AWant: TJSONArray);
var
  list: TTyGfxElArray;
  i: Integer;
begin
  list := Walk;
  SameInt('elements', Length(list), AWant.Count);
  for i := 0 to Min(Length(list), AWant.Count) - 1 do
    CheckEl(list[i], AWant.Objects[i]);
end;

procedure TAdvChartGraphicTest.CheckModel(AWant: TJSONArray);
var
  m: TTyGfxModel;
  i: Integer;
  o, w: TJSONObject;
  has: Boolean;
begin
  m := FChart.GraphicModel;
  if m = nil then
  begin
    SameInt('model', 0, AWant.Count);
    Exit;
  end;
  SameInt('model length', m.Elements.Count, AWant.Count);
  for i := 0 to Min(m.Elements.Count, AWant.Count) - 1 do
  begin
    o := TJSONObject(m.Elements.Items[i]);
    w := AWant.Objects[i];
    SameStr(Format('model[%d].id', [i]), TyGfxIdText(TyGfxIdOf(o.Find('id'), has)), w.Get('id', ''));
    SameStr(Format('model[%d].type', [i]), o.Get('type', ''), w.Get('type', ''));
    if IsNull(w.Find('parentId')) then
      SameBool(Format('model[%d] no parent', [i]), IsNull(o.Find('parentId')), True)
    else
      SameStr(Format('model[%d].parentId', [i]), TyGfxIdText(TyGfxIdOf(o.Find('parentId'), has)),
        w.Strings['parentId']);
  end;
end;

{ the paint order as owner tags: the graphic elements under the axes, the
  axes, then the list's graphic and series elements in paint order }
procedure TAdvChartGraphicTest.CheckOrder(AWant: TJSONArray);
var
  tags: TStringList;
  wantTags: TStringList;
  i, k: Integer;
  list: TTyPaintList;
  el: TTyChartElement;
  src: TTyGfxEl;
  t: string;

  procedure Push(AList: TStringList; const ATag: string);
  begin
    if (AList.Count = 0) or (AList[AList.Count - 1] <> ATag) then AList.Add(ATag);
  end;

  function TagOf(AIndex: Integer): string;
  begin
    src := FChart.GraphicPaintSource(AIndex);
    if src.Host <> nil then Result := 'g:' + TyGfxIdText(src.Host.Id) + '#label'
    else Result := 'g:' + TyGfxIdText(src.Id);
  end;

begin
  tags := TStringList.Create;
  wantTags := TStringList.Create;
  try
    list := FChart.List;
    { under the axes, in their own order }
    for i := 0 to list.Count - 1 do
    begin
      k := list.PaintOrder(i);
      el := list.Element(k);
      if (el.Datum.Kind = ctkGraphic) and el.GfxUnder then Push(tags, TagOf(el.Datum.DataIndex));
    end;
    Push(tags, 'a');
    for i := 0 to list.Count - 1 do
    begin
      k := list.PaintOrder(i);
      el := list.Element(k);
      if el.Datum.Kind = ctkGraphic then
      begin
        if not el.GfxUnder then Push(tags, TagOf(el.Datum.DataIndex));
      end
      else if (el.Datum.Kind = ctkSeries) and (el.Datum.SeriesIndex >= 0) then
        Push(tags, 's' + IntToStr(el.Datum.SeriesIndex));
    end;
    for i := 0 to AWant.Count - 1 do
    begin
      t := AWant.Strings[i];
      if (Copy(t, 1, 2) = 'g:') or (t = 'a') or ((t <> '') and (t[1] = 's')) then Push(wantTags, t);
    end;
    if wantTags.IndexOf('a') < 0 then
    begin
      { no axes: the 'a' the port's sequence has is nothing }
      i := tags.IndexOf('a');
      if i >= 0 then tags.Delete(i);
      for i := tags.Count - 1 downto 1 do
        if tags[i] = tags[i - 1] then tags.Delete(i);
    end;
    SameStr('order', tags.CommaText, wantTags.CommaText);
  finally
    tags.Free;
    wantTags.Free;
  end;
end;

procedure TAdvChartGraphicTest.CheckPointer(AState: TJSONObject);
var
  log, evs: TJSONArray;
  i: Integer;
  w: TJSONObject;
  wantInfo: TJSONData;
begin
  log := AState.Arrays['log'];
  SameInt('handler calls', Length(FChart.Log), log.Count);
  for i := 0 to Min(Length(FChart.Log), log.Count) - 1 do
  begin
    w := log.Objects[i];
    SameStr(Format('call %d fn', [i]), FChart.Log[i].Fn, w.Get('fn', ''));
    SameStr(Format('call %d type', [i]), FChart.Log[i].EventType, w.Get('type', ''));
    SameStr(Format('call %d self', [i]), FChart.Log[i].Self_, w.Get('self', ''));
    SameStr(Format('call %d target', [i]), FChart.Log[i].Target, w.Get('target', ''));
  end;
  evs := AState.Arrays['events'];
  SameInt('chart events', Length(FChart.Events), evs.Count);
  for i := 0 to Min(Length(FChart.Events), evs.Count) - 1 do
  begin
    Inc(FEventsSeen);
    w := evs.Objects[i];
    SameStr(Format('event %d type', [i]), FChart.Events[i].EventType, w.Get('type', ''));
    SameStr(Format('event %d componentType', [i]), FChart.Events[i].Params.ComponentType,
      w.Get('componentType', ''));
    SameInt(Format('event %d componentIndex', [i]), FChart.Events[i].Params.ComponentIndex,
      w.Get('componentIndex', -1));
    SameStr(Format('event %d name', [i]), FChart.Events[i].Params.Name, w.Get('name', ''));
    if IsNull(w.Find('info')) then
      SameStr(Format('event %d info', [i]), FChart.Events[i].Params.Info, '')
    else
    begin
      wantInfo := GetJSON(w.Strings['info']);
      try
        SameStr(Format('event %d info', [i]), FChart.Events[i].Params.Info, wantInfo.AsJSON);
      finally
        wantInfo.Free;
      end;
    end;
  end;
end;

procedure TAdvChartGraphicTest.CheckSnap(AEl: TTyGfxEl; ASnap: TJSONObject);
var
  i: Integer;
  key: string;
  own, want: TJSONData;
begin
  for i := 0 to ASnap.Count - 1 do
  begin
    key := ASnap.Names[i];
    { an object the option left in the shape or the style (its enterFrom,
      its leaveTo -- zrender copies every key across): as JSON }
    own := nil;
    if Copy(key, 1, 6) = 'shape.' then own := AEl.Shape.Find(Copy(key, 7, MaxInt))
    else if Copy(key, 1, 6) = 'style.' then own := AEl.Style.Find(Copy(key, 7, MaxInt));
    if own is TJSONObject then
    begin
      want := GetJSON(ASnap.Items[i].AsString);
      try
        SameStr(key, own.AsJSON, want.AsJSON);
      finally
        want.Free;
      end;
      Continue;
    end;
    SameValue(key, AEl.GetAnimProp(key), ASnap.Items[i]);
  end;
end;

procedure TAdvChartGraphicTest.CheckSamples(AState: TJSONObject; AStart: Double);
var
  samples: TJSONArray;
  i, k: Integer;
  smp, els, snap: TJSONObject;
  el: TTyGfxEl;
  list: TTyGfxElArray;
  ids: TStringList;
  t: Double;
  saveWhere: string;
begin
  samples := AState.Arrays['samples'];
  saveWhere := FWhere;
  for i := 0 to samples.Count - 1 do
  begin
    smp := samples.Objects[i];
    t := smp.Floats['t'];
    FWhere := saveWhere + Format(' t=%s', [Txt(t)]);
    FChart.AnimNow := AStart + t;
    FChart.AnimTick(AStart + t);
    Inc(FSamples);
    els := smp.Objects['els'];
    { the elements present }
    list := Walk;
    ids := TStringList.Create;
    try
      for k := 0 to High(list) do ids.Add(TyGfxIdText(list[k].Id));
      ids.Sort;
      SameInt('present', ids.Count, els.Count);
      for k := 0 to els.Count - 1 do
        if ids.IndexOf(els.Names[k]) < 0 then Bad('missing ' + els.Names[k]);
    finally
      ids.Free;
    end;
    for k := 0 to els.Count - 1 do
    begin
      el := FindInTree(els.Names[k]);
      if el = nil then Continue;
      snap := TJSONObject(els.Items[k]);
      FWhere := saveWhere + Format(' t=%s %s', [Txt(t), els.Names[k]]);
      CheckSnap(el, snap);
    end;
  end;
  FWhere := saveWhere;
end;

procedure TAdvChartGraphicTest.RunStep(AStep: TJSONObject; AState: TJSONObject);
var
  p: TJSONArray;
  d: TJSONData;
begin
  FChart.Events := nil;
  FChart.Log := nil;
  d := AStep.Find('merge');
  if d <> nil then
  begin
    FChart.SetOption(PortOption(d), False);
    RenderNow;
    Exit;
  end;
  d := AStep.Find('notMerge');
  if d <> nil then
  begin
    FChart.SetOption(PortOption(d), True);
    RenderNow;
    Exit;
  end;
  d := AStep.Find('resize');
  if d <> nil then
  begin
    FChart.SetBounds(0, 0, d.Items[0].AsInteger, d.Items[1].AsInteger);
    RenderNow;
    Exit;
  end;
  p := nil;
  if AState.Find('point') is TJSONArray then p := AState.Arrays['point'];
  if AStep.Find('click') <> nil then
  begin
    FChart.Move(p.Integers[0], p.Integers[1]);
    FChart.Down(p.Integers[0], p.Integers[1]);
    FChart.Up(p.Integers[0], p.Integers[1]);
  end
  else if AStep.Find('move') <> nil then
    FChart.Move(p.Integers[0], p.Integers[1])
  else if AStep.Find('leave') <> nil then
    FChart.Move(-10, -10);
end;

procedure TAdvChartGraphicTest.RunStatic(const AIds: array of string; AWithOrder: Boolean);
var
  c, st: TJSONObject;
  steps, states: TJSONArray;
  i, k: Integer;
begin
  for k := 0 to High(AIds) do
  begin
    c := CaseById(AIds[k]);
    FWhere := AIds[k];
    Show(c);
    states := c.Arrays['states'];
    steps := c.Arrays['steps'];
    FWhere := AIds[k] + ' state 0';
    CheckEls(states.Objects[0].Arrays['els']);
    CheckModel(states.Objects[0].Arrays['model']);
    if AWithOrder then CheckOrder(states.Objects[0].Arrays['order']);
    for i := 0 to steps.Count - 1 do
    begin
      st := states.Objects[i + 1];
      FWhere := Format('%s step %d', [AIds[k], i]);
      RunStep(steps.Objects[i], st);
      CheckEls(st.Arrays['els']);
      CheckModel(st.Arrays['model']);
      if AWithOrder then CheckOrder(st.Arrays['order']);
      CheckPointer(st);
    end;
  end;
end;

{ ==================== the fixture ==================== }

procedure TAdvChartGraphicTest.TestTheShapesAreUpstreams;
begin
  RunStatic(['rects', 'rounds', 'polys', 'lines', 'images'], False);
  Finish('the shapes', 1500);
end;

procedure TAdvChartGraphicTest.TestTheTextsAreUpstreams;
begin
  RunStatic(['texts', 'rich', 'text-hv', 'text-content', 'legacy-text'], False);
  Finish('the texts', 800);
  AssertTrue('pieces compared', FPieces >= 30);
end;

procedure TAdvChartGraphicTest.TestThePlacementsAreUpstreams;
begin
  RunStatic(['positions', 'groups', 'transforms'], False);
  Finish('the placements', 1000);
end;

procedure TAdvChartGraphicTest.TestTheOrderAndTheFlagsAreUpstreams;
var c: TJSONObject;
begin
  RunStatic(['z-order', 'flags', 'forms'], True);
  { the compound path: the update stopped at it, as the throw does }
  c := CaseById('compound');
  FWhere := 'compound';
  Show(c);
  SameBool('the throw is an error', FChart.GraphicView.Error <> '', not IsNull(c.Find('throws')));
  CheckEls(c.Arrays['states'].Objects[0].Arrays['els']);
  CheckModel(c.Arrays['states'].Objects[0].Arrays['model']);
  Finish('the order and the flags', 500);
end;

procedure TAdvChartGraphicTest.TestTheMergesAreUpstreams;
begin
  RunStatic(['actions', 'relayout', 'relayout-unset'], True);
  Finish('the merges', 500);
end;

procedure TAdvChartGraphicTest.TestTheEventsAreUpstreams;
begin
  RunStatic(['events'], False);
  Finish('the events', 300);
  AssertTrue('chart events compared', FEventsSeen >= 3);
end;

procedure TAdvChartGraphicTest.TestTheTransitionsAreUpstreams;
var
  ids: array[0..3] of string = ('enter', 'update', 'relocate', 'leave');
  k, i: Integer;
  c, st: TJSONObject;
  steps, states, samplesMs: TJSONArray;
  t0, clock, start: Double;
  si: Integer;
begin
  t0 := TJSONObject(FRoot).Objects['clock'].Floats['T0'];
  for k := 0 to High(ids) do
  begin
    c := CaseById(ids[k]);
    FWhere := ids[k];
    NewChart(c.Integers['W'], c.Integers['H']);
    FChart.AnimationMode := camAlways;
    FChart.AnimNow := t0;
    FChart.Option := PortOption(c.Objects['option']);
    RenderNow;
    samplesMs := c.Arrays['samplesMs'];
    states := c.Arrays['states'];
    steps := c.Arrays['steps'];
    start := t0;
    FWhere := ids[k] + ' state 0';
    CheckSamples(states.Objects[0], start);
    CheckModel(states.Objects[0].Arrays['model']);
    clock := start + samplesMs.Floats[samplesMs.Count - 1];
    si := 1;
    for i := 0 to steps.Count - 1 do
    begin
      if steps.Objects[i].Find('wait') <> nil then
      begin
        clock := clock + steps.Objects[i].Floats['wait'];
        FChart.AnimNow := clock;
        FChart.AnimTick(clock);
        Continue;
      end;
      FChart.AnimNow := clock;
      st := states.Objects[si];
      FWhere := Format('%s step %d', [ids[k], i]);
      RunStep(steps.Objects[i], st);
      start := clock;
      CheckSamples(st, start);
      CheckModel(st.Arrays['model']);
      clock := start + samplesMs.Floats[samplesMs.Count - 1];
      Inc(si);
    end;
  end;
  Finish('the transitions', 1000);
  AssertTrue('samples compared', FSamples >= 40);
end;

{ ==================== beyond the fixture ==================== }

procedure TAdvChartGraphicTest.TestThePreprocessorShapesTheOption;
var
  o: TJSONObject;
  g: TJSONData;
begin
  o := TJSONObject(GetJSON('{"graphic": {"type": "rect"}}'));
  try
    TyGraphicPreprocess(o);
    g := o.Find('graphic');
    AssertTrue('a bare element: one component', (g is TJSONArray) and (g.Count = 1));
    AssertTrue('its elements the element',
      TJSONObject(g.Items[0]).Arrays['elements'].Objects[0].Strings['type'] = 'rect');
  finally
    o.Free;
  end;
  o := TJSONObject(GetJSON('{"graphic": [{"type": "rect"}, {"type": "circle"}]}'));
  try
    TyGraphicPreprocess(o);
    AssertEquals('an array of elements: one component of two', 2,
      TJSONObject(o.Arrays['graphic'].Items[0]).Arrays['elements'].Count);
  finally
    o.Free;
  end;
  o := TJSONObject(GetJSON('{"graphic": [{"elements": [{"type": "rect"}]}, {"elements": []}]}'));
  try
    TyGraphicPreprocess(o);
    AssertEquals('components: the first only', 1, o.Arrays['graphic'].Count);
  finally
    o.Free;
  end;
end;

procedure TAdvChartGraphicTest.TestATurnedRectIsHitWhereItIsDrawn;
var
  el: TTyChartElement;
  i: Integer;
  found: Boolean;
begin
  NewChart(400, 300);
  { a 100 x 20 rect turned 90 degrees about its own corner at (200, 100):
    it runs down from y 100 to 200 at x 180..200 }
  FChart.Option := '{"animation": false, "graphic": [{"type": "rect", "id": "r", "x": 200, "y": 100,'
    + ' "rotation": -1.5707963267948966, "shape": {"width": 100, "height": 20}, "style": {"fill": "#f00"}}]}';
  RenderNow;
  found := False;
  for i := 0 to FChart.GraphicPaintCount - 1 do
  begin
    el := FChart.GraphicPaintElement(i);
    found := True;
    AssertTrue('inside the turned rect', TyShapeContains(el.Shape, 190, 150, 0));
    AssertFalse('where the upright rect would be', TyShapeContains(el.Shape, 250, 110, 0));
  end;
  AssertTrue('the rect was built', found);
end;

procedure TAdvChartGraphicTest.TestAnImageIsAPatternThroughItsTransform;
var
  el: TTyChartElement;
  img: string;
begin
  NewChart(400, 300);
  img := TJSONObject(FRoot).Strings['image'];
  FChart.Option := '{"animation": false, "graphic": [{"type": "image", "x": 10, "y": 20, "scaleX": 2,'
    + ' "style": {"image": "' + img + '", "width": 30, "height": 40}}]}';
  RenderNow;
  AssertEquals('one element', 1, FChart.GraphicPaintCount);
  el := FChart.GraphicPaintElement(0);
  AssertTrue('a pattern fill', el.Style.FillPattern.Present and el.Style.FillPattern.HasMatrix);
  AssertTrue('the unit square', el.Style.FillPattern.UnitImage);
  AssertEquals('scaled across: 2 x 30', 60, el.Style.FillPattern.Matrix[0], 1e-9);
  AssertEquals('down: 40', 40, el.Style.FillPattern.Matrix[3], 1e-9);
  AssertEquals('placed at x 10', 10, el.Style.FillPattern.Matrix[4], 1e-9);
  AssertEquals('placed at y 20', 20, el.Style.FillPattern.Matrix[5], 1e-9);
end;

procedure TAdvChartGraphicTest.TestAnUnknownTypeStopsTheUpdate;
begin
  NewChart(400, 300);
  FChart.Option := '{"animation": false, "graphic": [{"type": "rect", "id": "a"},'
    + ' {"type": "star", "id": "b"}, {"type": "circle", "id": "c"}]}';
  RenderNow;
  AssertTrue('an error', Pos('star', FChart.GraphicView.Error) > 0);
  AssertTrue('the element before it made', FChart.GraphicView.Find('a') <> nil);
  AssertTrue('none after it', FChart.GraphicView.Find('c') = nil);
end;

procedure TAdvChartGraphicTest.TestADraggableElementFollowsThePointer;
var el, h: TTyGfxEl;
begin
  NewChart(400, 300);
  FChart.Option := '{"animation": false, "graphic": [{"type": "rect", "id": "d", "x": 20, "y": 30,'
    + ' "draggable": true, "shape": {"width": 60, "height": 40}, "style": {"fill": "#f00"}},'
    + ' {"type": "group", "id": "g", "x": 200, "y": 100, "scaleX": 2, "draggable": "horizontal",'
    + ' "children": [{"type": "rect", "id": "c", "shape": {"width": 30, "height": 30}}]}]}';
  RenderNow;
  el := FChart.GraphicView.Find('d');
  FChart.Move(40, 50);
  FChart.Down(40, 50);
  FChart.Move(70, 60);
  FChart.Up(70, 60);
  AssertEquals('dragged 30 across', 50, el.X, 1e-12);
  AssertEquals('and 10 down', 40, el.Y, 1e-12);
  RenderNow;
  { a press on the child moves its draggable group, along x only }
  h := FChart.GraphicView.Find('g');
  FChart.Move(230, 115);
  FChart.Down(230, 115);
  FChart.Move(250, 140);
  FChart.Up(250, 140);
  AssertEquals('the group moved 20 across', 220, h.X, 1e-12);
  AssertEquals('not down', 100, h.Y, 1e-12);
end;

initialization
  RegisterTest(TAdvChartGraphicTest);
end.
