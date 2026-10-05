unit tyControls.AdvChart.Loading;
{$mode objfpc}{$H+}
{ TTyAdvanceChart -- the loading effect: showLoading's `default` effect,
  read off src/loading/default.ts and held to the real dist by
  tools/advchart-oracle/export-loading.js. [Batch 106, B11]

  WHAT IT IS. A mask over the whole chart (z 10000), a label rect with the
  text as its textContent at position 'right', distance 10, and an arc --
  the spinner -- of `spinnerRadius` stroked `lineWidth` wide with round caps
  (both z 10001). Its configuration goes through zrUtil.defaults: a key that
  is absent OR NULL takes the default, any other value is kept as written.

  WHERE. resize():
      r  = showSpinner ? spinnerRadius : 0
      cx = (W - 2r - (showSpinner && tw ? 10 : 0) - tw) / 2
           - (showSpinner && tw ? 0 : 5 + tw / 2)
           + (showSpinner ? 0 : tw / 2)
           + (tw ? 0 : r)
      cy = H / 2
  tw the text's bounding width. The label rect is (cx - r, cy - r, 2r, 2r),
  so the text's anchor is (cx - r + (10 + 2r), cy) and it hangs left /
  middle off it. Kept with its quirks: the spinner alone sits 5 px left of
  the centre, and the text alone 5 px right of it.

  HOW IT TURNS. Two looping animators on the arc's shape, both
  circularInOut over 1000 ms: endAngle from -pi/2 + 0.1 to 3pi/2, and
  startAngle from -pi/2 to 3pi/2 delayed 300 ms. A clip's clock starts at its
  FIRST STEP -- the first frame after the show, not the show -- and a loop
  restarts from the remainder of the step that ended it (Clip.step), so the
  angles at a moment depend on when the frames came. The arc is drawn
  clockwise from start to end as the canvas draws it: an end behind the
  start goes round the long way.

  PURE: no painter, no LCL. The geometry is in CSS px; the control measures
  the text and scales. }
interface
uses
  SysUtils, Math, fpjson, jsonparser,
  tyControls.AdvChart.Option, tyControls.AdvChart.Paint, tyControls.AdvChart.Color, tyControls.AdvChart.Anim,
  tyControls.AdvChart.Scale, tyControls.AdvChart.Export;

type
  { ONE COLOUR OF THE EFFECT: the theme's (the key absent or null), a
    colour, or nothing at all -- 'none', or a value no canvas reads. }
  TTyLoadInkKind = (likTheme, likColour, likNone);
  TTyLoadInk = record
    Kind: TTyLoadInkKind;
    Colour: TTyChartColor;
  end;

  TTyLoadingCfg = record
    Text: string;
    TextColor, Color, MaskColor: TTyLoadInk;
    { an author's size, px-encoded (TyOptFontSize); unset is the theme's }
    HasFontSize: Boolean;
    FontSizeLogical: Integer;
    HasFontWeight: Boolean;
    FontWeight: Integer;
    { '' is the theme's family }
    FontFamily: string;
    ShowSpinner: Boolean;
    SpinnerRadius: Double;
    LineWidth: Double;
  end;

  { resize()'s answers, CSS px }
  TTyLoadingGeometry = record
    Width, Height: Double;
    CX, CY, R: Double;
    RectX, RectY, RectW, RectH: Double;
    TextX, TextY: Double;
    TextWidth: Double;
  end;

const
  TyLoadingDefaultRadius = 10;
  TyLoadingDefaultLineWidth = 5;
  TyLoadingTextDistance = 10;
  TyLoadingPeriodMs = 1000;
  TyLoadingStartDelayMs = 300;
  TyLoadingEasing = 'circularInOut';

{ The cfg from its JSON text, ADefaultText for an absent or null `text`.
  '' and any text that is valid JSON but no object are no cfg (every
  default). False only for text that does not parse. }
function TyLoadingCfgOf(const AJson, ADefaultText: string;
  out ACfg: TTyLoadingCfg): Boolean;
{ A cfg with every default. }
function TyLoadingCfgDefault(const ADefaultText: string): TTyLoadingCfg;

procedure TyLoadingLayout(AWidth, AHeight, ATextWidth: Double;
  AShowSpinner: Boolean; ARadius: Double; out AGeo: TTyLoadingGeometry);

{ The arc's angles at the show: -pi/2, -pi/2 + 0.1; and where both loops
  go: 3pi/2. }
function TyLoadingStartAngle0: Double;
function TyLoadingEndAngle0: Double;
function TyLoadingTargetAngle: Double;

{ The spinner's two loops on AArc -- an element on its driver, whose
  'shape.startAngle' and 'shape.endAngle' this sets to their first values. }
procedure TyLoadingStartSpinner(AArc: TTyAnimBag);

implementation

const
  cTenth: Double = 0.1;

function TyLoadingStartAngle0: Double;
begin
  Result := -Pi / 2;
end;

function TyLoadingEndAngle0: Double;
begin
  Result := -Pi / 2 + cTenth;
end;

function TyLoadingTargetAngle: Double;
begin
  Result := Pi * 3 / 2;
end;

function TyLoadingCfgDefault(const ADefaultText: string): TTyLoadingCfg;
begin
  Result := Default(TTyLoadingCfg);
  Result.Text := ADefaultText;
  Result.TextColor.Kind := likTheme;
  Result.Color.Kind := likTheme;
  Result.MaskColor.Kind := likTheme;
  Result.ShowSpinner := True;
  Result.SpinnerRadius := TyLoadingDefaultRadius;
  Result.LineWidth := TyLoadingDefaultLineWidth;
end;

{ JavaScript's String(value) for what a JSON text can hold }
function JsStringOf(AData: TJSONData): string;
var i: Integer;
begin
  case AData.JSONType of
    jtString: Result := AData.AsString;
    jtNumber: Result := TyJsNumberToString(AData.AsFloat);
    jtBoolean: if AData.AsBoolean then Result := 'true' else Result := 'false';
    jtNull: Result := 'null';
    jtArray:
      begin
        { Array.prototype.join(','): null and undefined are empty }
        Result := '';
        for i := 0 to AData.Count - 1 do
        begin
          if i > 0 then Result := Result + ',';
          if AData.Items[i].JSONType <> jtNull then
            Result := Result + JsStringOf(AData.Items[i]);
        end;
      end;
  else
    Result := '[object Object]';
  end;
end;

{ fill / stroke as a canvas takes them: a colour it reads, else nothing
  ('none' is zrender's own no-paint; another string leaves the canvas'
  previous style, which the port does not keep) }
function InkOf(AData: TJSONData): TTyLoadInk;
var c: TTyChartColor;
begin
  Result.Kind := likTheme;
  Result.Colour := 0;
  if (AData = nil) or (AData.JSONType = jtNull) then Exit;
  Result.Kind := likNone;
  if (AData.JSONType = jtString) and TyTryParseChartColor(AData.AsString, c) then
  begin
    Result.Kind := likColour;
    Result.Colour := c;
  end;
end;

function NumberOr(AData: TJSONData; ADefault: Double): Double;
begin
  Result := ADefault;
  if (AData <> nil) and (AData.JSONType = jtNumber)
    and not IsNan(AData.AsFloat) and not IsInfinite(AData.AsFloat) then
    Result := AData.AsFloat;
end;

function TyLoadingCfgOf(const AJson, ADefaultText: string;
  out ACfg: TTyLoadingCfg): Boolean;
var
  root, d: TJSONData;
  o: TJSONObject;
  nLine, nCol: Integer;
begin
  ACfg := TyLoadingCfgDefault(ADefaultText);
  Result := True;
  if Trim(AJson) = '' then Exit;
  if TyJsonNestingExceeds(AJson, TyOptionMaxNesting, nLine, nCol) then Exit(False);
  try
    root := GetJSON(AJson);
  except
    Exit(False);
  end;
  try
    if not (root is TJSONObject) then Exit;
    o := TJSONObject(root);
    d := o.Find('text');
    if (d <> nil) and (d.JSONType <> jtNull) then ACfg.Text := JsStringOf(d);
    ACfg.TextColor := InkOf(o.Find('textColor'));
    ACfg.Color := InkOf(o.Find('color'));
    ACfg.MaskColor := InkOf(o.Find('maskColor'));
    d := o.Find('fontSize');
    if (d <> nil) and (d.JSONType <> jtNull) then
    begin
      ACfg.FontSizeLogical := TyOptFontSize(d, 0);
      ACfg.HasFontSize := ACfg.FontSizeLogical > 0;
    end;
    d := o.Find('fontWeight');
    if (d <> nil) and (d.JSONType <> jtNull) then
    begin
      ACfg.FontWeight := TyFontWeightOf(d, 0);
      ACfg.HasFontWeight := ACfg.FontWeight > 0;
    end;
    d := o.Find('fontFamily');
    if (d <> nil) and (d.JSONType = jtString) then ACfg.FontFamily := d.AsString;
    d := o.Find('showSpinner');
    if (d <> nil) and (d.JSONType <> jtNull) then ACfg.ShowSpinner := TyJsTruthy(d);
    ACfg.SpinnerRadius := NumberOr(o.Find('spinnerRadius'), TyLoadingDefaultRadius);
    ACfg.LineWidth := NumberOr(o.Find('lineWidth'), TyLoadingDefaultLineWidth);
  finally
    root.Free;
  end;
end;

procedure TyLoadingLayout(AWidth, AHeight, ATextWidth: Double;
  AShowSpinner: Boolean; ARadius: Double; out AGeo: TTyLoadingGeometry);
var
  r, tw, gap, both, alone, noText, cx, cy: Double;
  hasText: Boolean;
begin
  AGeo := Default(TTyLoadingGeometry);
  tw := ATextWidth;
  { `textWidth` as a condition: not 0, not NaN }
  hasText := (tw <> 0) and not IsNan(tw);
  if AShowSpinner then r := ARadius else r := 0;
  { the four terms in upstream's order, each the value the ternary gives }
  if AShowSpinner and hasText then gap := TyLoadingTextDistance else gap := 0;
  if AShowSpinner and hasText then both := 0 else both := 5 + tw / 2;
  if AShowSpinner then alone := 0 else alone := tw / 2;
  if hasText then noText := 0 else noText := r;
  cx := (AWidth - r * 2 - gap - tw) / 2 - both + alone + noText;
  cy := AHeight / 2;
  AGeo.Width := AWidth;
  AGeo.Height := AHeight;
  AGeo.CX := cx;
  AGeo.CY := cy;
  AGeo.R := r;
  AGeo.RectX := cx - r;
  AGeo.RectY := cy - r;
  AGeo.RectW := r * 2;
  AGeo.RectH := r * 2;
  { calculateTextPosition 'right': x += distance + width; y += height / 2 }
  AGeo.TextX := AGeo.RectX + (TyLoadingTextDistance + AGeo.RectW);
  AGeo.TextY := AGeo.RectY + AGeo.RectH / 2;
  AGeo.TextWidth := tw;
end;

procedure TyLoadingStartSpinner(AArc: TTyAnimBag);
begin
  AArc.SetNum('shape.startAngle', TyLoadingStartAngle0);
  AArc.SetNum('shape.endAngle', TyLoadingEndAngle0);
  AArc.Animate('shape', True).WhenWithKeys(TyLoadingPeriodMs, ['endAngle'],
    [TyAnimNum(TyLoadingTargetAngle)]).Start(TyLoadingEasing);
  AArc.Animate('shape', True).WhenWithKeys(TyLoadingPeriodMs, ['startAngle'],
    [TyAnimNum(TyLoadingTargetAngle)]).Delay(TyLoadingStartDelayMs)
    .Start(TyLoadingEasing);
end;

end.
