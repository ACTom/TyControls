unit tyControls.AdvChart.Style;
{$mode objfpc}{$H+}
{ The four states, and what a datum's style resolves to in each of them.

  FOUR STATES, TWO SLOTS. normal / emphasis / blur / select is NOT a four-value
  enum, and modelling it as one is the mistake this unit exists to avoid.
  Emphasis and blur share one slot and are mutually exclusive; SELECT IS ITS OWN
  slot and composes with either. A selected bar that is also hovered is in both
  at once, and normal is not a state anyone enters -- it is both slots empty.

  ENTER OVERWRITES, LEAVE IS GUARDED. Entering emphasis takes the slot whatever
  was in it; leaving emphasis clears the slot ONLY if emphasis is what is in it.
  That asymmetry is the whole mechanism behind "blur the series, then emphasise
  the hovered point": the blur pass cannot undo the emphasis, and the emphasis
  leaving later cannot silently clear a blur it never set.

  EMPHASIS IS REFERENCE-COUNTED. A legend hover, a user highlight action and an
  axis-pointer link can each hold an element highlighted at the same time, so
  the mask has one bit per source and the element stays emphasised while any bit
  is set. Mouse hover deliberately does NOT take a bit: it applies only when the
  mask is empty, which is how an API highlight outranks the pointer.

  AND THE STYLE FALLBACK IS NOT "ITEM ELSE SERIES". That rule is exactly right
  for the normal state and wrong for the other three, in five ways that are all
  visible on screen. The largest: an emphasis with no style of its own is not
  unstyled -- it is the normal colour LIFTED, which is the default hover
  appearance of every bar, slice and symbol. Blur's opacity is likewise computed
  from the normal one rather than looked up. See TyChartResolveStyle.

  PURE: SysUtils, Math and the AdvChart units. No LCL. }
interface
uses SysUtils, Math, fpjson, tyControls.AdvChart.Types, tyControls.AdvChart.Paint;

type
  { The exclusive slot. }
  TTyChartHoverState = (chsNormal, chsBlur, chsEmphasis);

  { What state one element is in. Two slots, not one value. }
  TTyChartElementState = record
    Hover: TTyChartHoverState;
    Selected: Boolean;
    { One bit per source holding this element highlighted. Zero means no API
      highlight, which is the only condition under which a mouse hover applies. }
    HighByOuter: Cardinal;
  end;

  { Which states are applied, innermost first. A state list rather than a single
    value because select composes with the other two. }
  TTyChartStateList = record
    Select: Boolean;
    Emphasis: Boolean;
    Blur: Boolean;
  end;

  { How far a hover reaches. }
  TTyChartFocus = (cfNone, cfSelf, cfSeries);
  { How wide the dimming goes. }
  TTyChartBlurScope = (cbsCoordinateSystem, cbsSeries, cbsGlobal);

  { One canvas-side style property. Named for what the PAINTER does with it
    rather than for the option key, because three different option keys map onto
    some of these -- itemStyle.color, lineStyle.color and areaStyle.color are
    fill, stroke and fill again. }
  TTyChartStyleKey = (
    cskFill, cskStroke, cskLineWidth, cskOpacity,
    cskShadowBlur, cskShadowOffsetX, cskShadowOffsetY, cskShadowColor,
    cskLineDash, cskLineDashOffset, cskLineCap, cskLineJoin, cskMiterLimit
  );

  { A sparse style: every key carries a present flag, because ABSENT and SET TO
    ZERO are different answers all the way down. A border width of 0 means "do
    not stroke"; an absent one means "whatever the layer below said". Collapsing
    the two is how a style layer silently stops inheriting. }
  TTyChartStyle = record
    Has: array[TTyChartStyleKey] of Boolean;
    Num: array[TTyChartStyleKey] of Double;
    Color: array[TTyChartStyleKey] of TTyChartColor;
    Text: array[TTyChartStyleKey] of string;
  end;

  { Which of the three option shapes a key set came from. They are not the same
    set and not the same names: lineStyle has no fill at all, and areaStyle has
    neither stroke nor width nor dash. }
  TTyChartStyleKind = (cskItem, cskLine, cskArea);

{ ---- the state slots ---- }
function TyChartNoState: TTyChartElementState;

{ Takes the slot whatever is in it. }
procedure TyChartEnterEmphasis(var AState: TTyChartElementState);
{ Clears the slot ONLY if emphasis is what is in it, so a blurred element is
  left blurred rather than quietly promoted to normal. }
procedure TyChartLeaveEmphasis(var AState: TTyChartElementState);
procedure TyChartEnterBlur(var AState: TTyChartElementState);
procedure TyChartLeaveBlur(var AState: TTyChartElementState);
procedure TyChartEnterSelect(var AState: TTyChartElementState);
procedure TyChartLeaveSelect(var AState: TTyChartElementState);

{ Reference-counted emphasis. ADigit names the source, 0..31; a source outside
  that range shares bit 0, which is what upstream does when it runs out. }
procedure TyChartEnterEmphasisBy(var AState: TTyChartElementState; ADigit: Integer);
procedure TyChartLeaveEmphasisBy(var AState: TTyChartElementState; ADigit: Integer);
{ The mouse path: applies only while no source holds the element, so an API
  highlight is never undone by the pointer leaving. }
procedure TyChartEnterEmphasisByMouse(var AState: TTyChartElementState);
procedure TyChartLeaveEmphasisByMouse(var AState: TTyChartElementState);

{ Which states are actually applied. Select composes; emphasis and blur do not. }
function TyChartStatesOf(const AState: TTyChartElementState): TTyChartStateList;

{ Should this element be dimmed, given what is hovered?

  focus none means nothing is ever blurred -- the entire mechanism is off unless
  a focus is asked for. blurScope decides how far the dimming reaches, and its
  default is the coordinate system rather than the whole chart. }
function TyChartShouldBlur(AFocus: TTyChartFocus; AScope: TTyChartBlurScope;
  ASameSeries, ASameCoordSys: Boolean): Boolean;

{ ---- style ---- }
function TyChartNoStyle: TTyChartStyle;
function TyChartStyleHas(const AStyle: TTyChartStyle; AKey: TTyChartStyleKey): Boolean;
procedure TyChartSetNum(var AStyle: TTyChartStyle; AKey: TTyChartStyleKey; AValue: Double);
procedure TyChartSetColor(var AStyle: TTyChartStyle; AKey: TTyChartStyleKey;
  AValue: TTyChartColor);
procedure TyChartSetText(var AStyle: TTyChartStyle; AKey: TTyChartStyleKey;
  const AValue: string);
procedure TyChartClearKey(var AStyle: TTyChartStyle; AKey: TTyChartStyleKey);

{ Lay ATop over ABase: every key ATop has wins, every key it lacks is
  inherited. Absent is not the same as zero, which is why this cannot be a
  field-by-field copy. }
function TyChartOverlay(const ABase, ATop: TTyChartStyle): TTyChartStyle;

{ The option key for one canvas key in one of the three shapes, or '' when that
  shape has no such key. Exposed because the mapping is the part a reader will
  want to check against the documentation. }
function TyChartStyleOptionKey(AKind: TTyChartStyleKind;
  AKey: TTyChartStyleKey): string;

{ A CSS colour as the option writes it, or False when it is not one.

  Handles the four spellings an ECharts option actually carries: '#rgb',
  '#rrggbb', '#rrggbbaa' and rgb()/rgba(). A NAMED colour is deliberately not
  handled: the list is 148 entries, upstream resolves them in a browser, and
  option text in the wild spells colours in hex. An unrecognised string leaves
  the key ABSENT rather than falling back to black -- absent means the layer
  below keeps deciding, black means a misspelt colour paints something that
  looks deliberate. }
function TyChartParseColor(const AText: string; out AColor: TTyChartColor): Boolean;

{ Read one style object -- an itemStyle, a lineStyle or an areaStyle -- into the
  sparse record. False when it read nothing.

  ABSENT STAYS ABSENT. Only keys the object actually carries get their Has flag,
  because absent and set-to-zero are different answers all the way down: a
  border width of 0 means "do not stroke" and a missing one means "whatever the
  layer below said". Filling the gaps with defaults is how a style layer
  silently stops inheriting.

  AKind picks which option names are looked for, and the three sets are NOT the
  same: a lineStyle has no fill, an areaStyle has no stroke, width or dash, and
  `color` is the FILL for an item and the STROKE for a line. }
function TyChartReadStyle(AData: TJSONData; AKind: TTyChartStyleKind;
  out AStyle: TTyChartStyle): Boolean;

{ Ten per cent brighter, clamped.

  Called "lift" upstream and it takes a NEGATIVE level to brighten, which is
  worth stating because the name and the sign both point the other way. This is
  the default hover appearance of every bar, slice and scatter symbol, so
  getting the direction wrong is not subtle. }
function TyChartLiftColor(AColor: TTyChartColor): TTyChartColor;

const
  { What a hovered element gains, and a selected one, in paint order. Neither
    comes from any option path -- they are constants in the state machinery, and
    a port that waits to find them in the option tree will never find them. }
  TyChartEmphasisZ2Lift = 10;
  TyChartSelectZ2Lift = 9;
  { A blurred element's opacity is its normal one scaled by this, NOT a value
    looked up anywhere. With no normal opacity the normal one is 1. }
  TyChartBlurOpacityFactor = 0.1;

{ Resolve one datum's style in one state.

  ANormal is what the normal state resolved to -- series value overlaid with the
  per-datum override, which for the normal state really is "the item slot if
  present, else the series value".

  AStateStyle is whatever the option declared for THIS state, which is usually
  nothing at all.

  The three states then diverge from that rule, and each divergence is visible:

    EMPHASIS with no declared fill takes the normal fill LIFTED. Only if it has
    no declared stroke either AND the normal had a stroke does the stroke get
    lifted instead -- fill first, stroke only as the fallback's fallback, never
    both.

    BLUR scales the normal opacity rather than reading one, so an element with
    no opacity at all still dims.

    SELECT adds nothing of its own beyond what was declared. }
function TyChartResolveStyle(const ANormal, AStateStyle: TTyChartStyle;
  const AStates: TTyChartStateList): TTyChartStyle;

{ How much a state adds to an element's paint order. }
function TyChartZ2Lift(const AStates: TTyChartStateList): Integer;

implementation

{ ==================== the state slots ==================== }

function TyChartNoState: TTyChartElementState;
begin
  Result.Hover := chsNormal;
  Result.Selected := False;
  Result.HighByOuter := 0;
end;

procedure TyChartEnterEmphasis(var AState: TTyChartElementState);
begin
  AState.Hover := chsEmphasis;
end;

procedure TyChartLeaveEmphasis(var AState: TTyChartElementState);
begin
  { Guarded. A blurred element must stay blurred -- clearing unconditionally is
    how a hover leaving one element brightens a dozen others. }
  if AState.Hover = chsEmphasis then AState.Hover := chsNormal;
end;

procedure TyChartEnterBlur(var AState: TTyChartElementState);
begin
  AState.Hover := chsBlur;
end;

procedure TyChartLeaveBlur(var AState: TTyChartElementState);
begin
  if AState.Hover = chsBlur then AState.Hover := chsNormal;
end;

procedure TyChartEnterSelect(var AState: TTyChartElementState);
begin
  AState.Selected := True;
end;

procedure TyChartLeaveSelect(var AState: TTyChartElementState);
begin
  AState.Selected := False;
end;

function DigitMask(ADigit: Integer): Cardinal;
begin
  { Out of range shares bit 0, which is what upstream does once it runs out of
    bits rather than dropping the highlight. }
  if (ADigit < 0) or (ADigit > 31) then ADigit := 0;
  Result := Cardinal(1) shl ADigit;
end;

procedure TyChartEnterEmphasisBy(var AState: TTyChartElementState; ADigit: Integer);
begin
  AState.HighByOuter := AState.HighByOuter or DigitMask(ADigit);
  TyChartEnterEmphasis(AState);
end;

procedure TyChartLeaveEmphasisBy(var AState: TTyChartElementState; ADigit: Integer);
begin
  AState.HighByOuter := AState.HighByOuter and not DigitMask(ADigit);
  { Only when the LAST source lets go. Two components highlighting the same
    element and one leaving must not put it back to normal. }
  if AState.HighByOuter = 0 then TyChartLeaveEmphasis(AState);
end;

procedure TyChartEnterEmphasisByMouse(var AState: TTyChartElementState);
begin
  { Deliberately does not take a bit: an API highlight outranks the pointer, and
    the pointer must not be able to release one. }
  if AState.HighByOuter = 0 then TyChartEnterEmphasis(AState);
end;

procedure TyChartLeaveEmphasisByMouse(var AState: TTyChartElementState);
begin
  if AState.HighByOuter = 0 then TyChartLeaveEmphasis(AState);
end;

function TyChartStatesOf(const AState: TTyChartElementState): TTyChartStateList;
begin
  Result.Select := AState.Selected;
  Result.Emphasis := AState.Hover = chsEmphasis;
  Result.Blur := AState.Hover = chsBlur;
end;

function TyChartShouldBlur(AFocus: TTyChartFocus; AScope: TTyChartBlurScope;
  ASameSeries, ASameCoordSys: Boolean): Boolean;
begin
  { No focus, no blur. The whole mechanism is off by default -- an option that
    says nothing dims nothing, which is why a chart does not go grey the first
    time a pointer crosses it. }
  if AFocus = cfNone then Exit(False);
  case AScope of
    cbsSeries:
      if not ASameSeries then Exit(False);
    cbsCoordinateSystem:
      if not ASameCoordSys then Exit(False);
    { Global reaches everything, so nothing is skipped for scope. }
  end;
  { focus series spares the hovered element's own series; focus self spares only
    the element, which the caller un-blurs afterwards by index. }
  if (AFocus = cfSeries) and ASameSeries then Exit(False);
  Result := True;
end;

{ ==================== style ==================== }

function TyChartNoStyle: TTyChartStyle;
var k: TTyChartStyleKey;
begin
  for k := Low(TTyChartStyleKey) to High(TTyChartStyleKey) do
  begin
    Result.Has[k] := False;
    Result.Num[k] := 0;
    Result.Color[k] := 0;
    Result.Text[k] := '';
  end;
end;

function TyChartStyleHas(const AStyle: TTyChartStyle; AKey: TTyChartStyleKey): Boolean;
begin
  Result := AStyle.Has[AKey];
end;

procedure TyChartSetNum(var AStyle: TTyChartStyle; AKey: TTyChartStyleKey; AValue: Double);
begin
  AStyle.Has[AKey] := True;
  AStyle.Num[AKey] := AValue;
end;

procedure TyChartSetColor(var AStyle: TTyChartStyle; AKey: TTyChartStyleKey;
  AValue: TTyChartColor);
begin
  AStyle.Has[AKey] := True;
  AStyle.Color[AKey] := AValue;
end;

procedure TyChartSetText(var AStyle: TTyChartStyle; AKey: TTyChartStyleKey;
  const AValue: string);
begin
  AStyle.Has[AKey] := True;
  AStyle.Text[AKey] := AValue;
end;

procedure TyChartClearKey(var AStyle: TTyChartStyle; AKey: TTyChartStyleKey);
begin
  AStyle.Has[AKey] := False;
  AStyle.Num[AKey] := 0;
  AStyle.Color[AKey] := 0;
  AStyle.Text[AKey] := '';
end;

function TyChartOverlay(const ABase, ATop: TTyChartStyle): TTyChartStyle;
var k: TTyChartStyleKey;
begin
  Result := ABase;
  for k := Low(TTyChartStyleKey) to High(TTyChartStyleKey) do
    if ATop.Has[k] then
    begin
      Result.Has[k] := True;
      Result.Num[k] := ATop.Num[k];
      Result.Color[k] := ATop.Color[k];
      Result.Text[k] := ATop.Text[k];
    end;
end;

function TyChartStyleOptionKey(AKind: TTyChartStyleKind;
  AKey: TTyChartStyleKey): string;
begin
  Result := '';
  case AKind of
    cskItem:
      case AKey of
        cskFill: Result := 'color';
        cskStroke: Result := 'borderColor';
        cskLineWidth: Result := 'borderWidth';
        cskOpacity: Result := 'opacity';
        cskShadowBlur: Result := 'shadowBlur';
        cskShadowOffsetX: Result := 'shadowOffsetX';
        cskShadowOffsetY: Result := 'shadowOffsetY';
        cskShadowColor: Result := 'shadowColor';
        cskLineDash: Result := 'borderType';
        cskLineDashOffset: Result := 'borderDashOffset';
        cskLineCap: Result := 'borderCap';
        cskLineJoin: Result := 'borderJoin';
        cskMiterLimit: Result := 'borderMiterLimit';
      end;
    cskLine:
      { No fill: a line style has nothing to fill. Its colour is the STROKE,
        which is why the same option name maps to a different canvas key here
        than it does for an item. }
      case AKey of
        cskStroke: Result := 'color';
        cskLineWidth: Result := 'width';
        cskOpacity: Result := 'opacity';
        cskShadowBlur: Result := 'shadowBlur';
        cskShadowOffsetX: Result := 'shadowOffsetX';
        cskShadowOffsetY: Result := 'shadowOffsetY';
        cskShadowColor: Result := 'shadowColor';
        cskLineDash: Result := 'type';
        cskLineDashOffset: Result := 'dashOffset';
        cskLineCap: Result := 'cap';
        cskLineJoin: Result := 'join';
        cskMiterLimit: Result := 'miterLimit';
      end;
    cskArea:
      { Six keys and no more: an area has no stroke, no width and no dash of any
        kind. Offering them would let an option validator accept a chart that
        cannot be drawn. }
      case AKey of
        cskFill: Result := 'color';
        cskOpacity: Result := 'opacity';
        cskShadowBlur: Result := 'shadowBlur';
        cskShadowOffsetX: Result := 'shadowOffsetX';
        cskShadowOffsetY: Result := 'shadowOffsetY';
        cskShadowColor: Result := 'shadowColor';
      end;
  end;
end;

function HexNibble(C: Char; out AValue: Integer): Boolean;
begin
  Result := True;
  case C of
    '0'..'9': AValue := Ord(C) - Ord('0');
    'a'..'f': AValue := Ord(C) - Ord('a') + 10;
    'A'..'F': AValue := Ord(C) - Ord('A') + 10;
  else
    AValue := 0;
    Result := False;
  end;
end;

function TyChartParseColor(const AText: string; out AColor: TTyChartColor): Boolean;
var
  t: string;
  i, n, hi, lo: Integer;
  comp: array[0..3] of Integer;
  part: string;
  alphaF: Double;
  fs: TFormatSettings;

  function HexPair(APos: Integer; out AByte: Integer): Boolean;
  begin
    Result := HexNibble(t[APos], hi) and HexNibble(t[APos + 1], lo);
    AByte := hi * 16 + lo;
  end;

begin
  AColor := 0;
  Result := False;
  t := Trim(AText);
  if t = '' then Exit;

  if t[1] = '#' then
  begin
    comp[0] := 255;
    case Length(t) of
      4:
        begin
          { #rgb -- each nibble DOUBLED, not shifted: #f0a is ff00aa, and
            shifting would give f0 00 a0, which is a different colour. }
          for i := 1 to 3 do
          begin
            if not HexNibble(t[i + 1], hi) then Exit;
            comp[i] := hi * 17;
          end;
        end;
      7:
        for i := 1 to 3 do
          if not HexPair(i * 2, comp[i]) then Exit;
      9:
        begin
          for i := 1 to 3 do
            if not HexPair(i * 2, comp[i]) then Exit;
          { #rrggbbAA -- alpha LAST in CSS, first in the stored word. }
          if not HexPair(8, comp[0]) then Exit;
        end;
    else
      Exit;
    end;
    AColor := TTyChartColor((Cardinal(comp[0]) shl 24) or
      (Cardinal(comp[1]) shl 16) or (Cardinal(comp[2]) shl 8) or Cardinal(comp[3]));
    Exit(True);
  end;

  if (Pos('rgb(', LowerCase(t)) = 1) or (Pos('rgba(', LowerCase(t)) = 1) then
  begin
    i := Pos('(', t);
    n := Pos(')', t);
    if (i = 0) or (n <= i) then Exit;
    t := Copy(t, i + 1, n - i - 1);
    comp[0] := 255;
    for i := 1 to 3 do
    begin
      n := Pos(',', t);
      if n = 0 then
      begin
        part := t;
        t := '';
      end
      else
      begin
        part := Copy(t, 1, n - 1);
        t := Copy(t, n + 1, MaxInt);
      end;
      part := Trim(part);
      if part = '' then Exit;
      comp[i] := StrToIntDef(part, -1);
      if (comp[i] < 0) or (comp[i] > 255) then Exit;
    end;
    part := Trim(t);
    if part <> '' then
    begin
      { The alpha of rgba() is 0..1, not 0..255, and it is written with a '.'
        whatever the machine's locale says. }
      fs := DefaultFormatSettings;
      fs.DecimalSeparator := '.';
      if not TryStrToFloat(part, alphaF, fs) then Exit;
      if alphaF < 0 then alphaF := 0;
      if alphaF > 1 then alphaF := 1;
      comp[0] := Round(alphaF * 255);
    end;
    AColor := TTyChartColor((Cardinal(comp[0]) shl 24) or
      (Cardinal(comp[1]) shl 16) or (Cardinal(comp[2]) shl 8) or Cardinal(comp[3]));
    Exit(True);
  end;
end;

function TyChartReadStyle(AData: TJSONData; AKind: TTyChartStyleKind;
  out AStyle: TTyChartStyle): Boolean;
var
  obj: TJSONObject;
  k: TTyChartStyleKey;
  name: string;
  d: TJSONData;
  c: TTyChartColor;
begin
  AStyle := Default(TTyChartStyle);
  Result := False;
  if (AData = nil) or not (AData is TJSONObject) then Exit;
  obj := TJSONObject(AData);
  for k := Low(TTyChartStyleKey) to High(TTyChartStyleKey) do
  begin
    name := TyChartStyleOptionKey(AKind, k);
    { '' means this shape has no such key -- an areaStyle really has no stroke.
      Reading one anyway would accept a chart that cannot be drawn. }
    if name = '' then Continue;
    d := obj.Find(name);
    if (d = nil) or (d.JSONType = jtNull) then Continue;
    case k of
      cskFill, cskStroke, cskShadowColor:
        begin
          if d.JSONType <> jtString then Continue;
          if not TyChartParseColor(d.AsString, c) then Continue;
          AStyle.Color[k] := c;
          AStyle.Has[k] := True;
          Result := True;
        end;
      cskLineDash, cskLineCap, cskLineJoin:
        begin
          { These are NAMES upstream -- 'dashed', 'round', 'bevel' -- and the
            renderer turns a name into geometry. Kept as text so this layer
            does not have to know the dash pattern for 'dotted' at a given
            width, which is a painter decision. }
          if d.JSONType <> jtString then Continue;
          AStyle.Text[k] := d.AsString;
          AStyle.Has[k] := True;
          Result := True;
        end;
    else
      begin
        if d.JSONType <> jtNumber then Continue;
        AStyle.Num[k] := d.AsFloat;
        AStyle.Has[k] := True;
        Result := True;
      end;
    end;
  end;
end;

function TyChartLiftColor(AColor: TTyChartColor): TTyChartColor;

  function Lift(AByte: Cardinal): Cardinal;
  var v: Integer;
  begin
    { level is -0.1, and the branch for a negative level multiplies by
      (1 - level) -- so a NEGATIVE level brightens. Truncated, not rounded,
      because the source truncates. }
    v := Trunc(AByte * 1.1);
    if v > 255 then v := 255;
    if v < 0 then v := 0;
    Result := Cardinal(v);
  end;

var
  r, g, b, a: Cardinal;
begin
  { Alpha is untouched: only the three colour channels are lifted. }
  a := (AColor shr 24) and $FF;
  r := (AColor shr 16) and $FF;
  g := (AColor shr 8) and $FF;
  b := AColor and $FF;
  Result := TTyChartColor((a shl 24) or (Lift(r) shl 16) or (Lift(g) shl 8) or Lift(b));
end;

function TyChartResolveStyle(const ANormal, AStateStyle: TTyChartStyle;
  const AStates: TTyChartStateList): TTyChartStyle;
var
  normalOpacity: Double;
begin
  Result := TyChartOverlay(ANormal, AStateStyle);

  if AStates.Emphasis then
  begin
    { An emphasis that declared no colour is NOT unstyled. Fill first: if the
      state has no fill of its own and the normal had one, the normal one is
      lifted. Only when there is no fill to lift at all does the stroke get
      lifted instead -- never both, because an outline and a body brightening
      together reads as a different colour rather than as a highlight. }
    if (not AStateStyle.Has[cskFill]) and ANormal.Has[cskFill] then
      TyChartSetColor(Result, cskFill, TyChartLiftColor(ANormal.Color[cskFill]))
    else if (not AStateStyle.Has[cskStroke]) and ANormal.Has[cskStroke]
            and (not ANormal.Has[cskFill]) then
      TyChartSetColor(Result, cskStroke, TyChartLiftColor(ANormal.Color[cskStroke]));
  end;

  if AStates.Blur then
  begin
    { Computed, not looked up. An element with no opacity of its own still dims,
      because the normal opacity it is scaled from defaults to fully opaque. }
    if ANormal.Has[cskOpacity] then normalOpacity := ANormal.Num[cskOpacity]
    else normalOpacity := 1;
    TyChartSetNum(Result, cskOpacity, normalOpacity * TyChartBlurOpacityFactor);
  end;
end;

function TyChartZ2Lift(const AStates: TTyChartStateList): Integer;
begin
  { Emphasis outranks select when both apply: a hovered selected bar comes to
    the very front rather than settling between the two. }
  if AStates.Emphasis then Exit(TyChartEmphasisZ2Lift);
  if AStates.Select then Exit(TyChartSelectZ2Lift);
  Result := 0;
end;

end.
