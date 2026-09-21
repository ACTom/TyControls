unit tyControls.AdvChart.AxisPointer;
{$mode objfpc}{$H+}
{ The line, or the band, that follows the pointer along an axis.

  WHERE THE OPTION COMES FROM, and this is the part that reads backwards.
  There are three places to write it and the order is NOT the one the names
  suggest:

      <axis>.axisPointer.*   beats
      tooltip.axisPointer.*  beats
      axisPointer.*          (the root component)

  "Tooltip wins" is only true against the ROOT. Upstream resolves a
  tooltip-driven axis as `axis.model.getModel('axisPointer', <volatile>)` --
  the axis' own block is the model, the tooltip layer is merely its PARENT --
  so `xAxis.axisPointer.type: 'shadow'` still beats
  `tooltip.axisPointer.type: 'line'`. And because the fallback is per-leaf and
  null-only, any value the tooltip layer carries SHADOWS the root even when the
  user set the root explicitly: upstream deliberately omits lineStyle and
  shadowStyle from the tooltip defaults so that those two stay reachable.

  ONLY NINE FIELDS CROSS from tooltip to axis -- type, snap, lineStyle,
  shadowStyle, label, animation and three animation details -- so `show`,
  `triggerTooltip`, `handle`, `link` and `zlevel` written under
  `tooltip.axisPointer` are SILENTLY DEAD. A tenth, crossStyle, crosses only
  on the cross path.

  THREE OF THE NINE ARE THEN OVERWRITTEN, which is what makes this worth a
  unit of its own rather than a reader inline:

    * `snap` is recomputed unconditionally from the axis KIND, so
      `tooltip.axisPointer.snap` is dead code and the root one is unreachable;
    * `type: 'cross'` is rewritten to 'line' PER AXIS -- cross is never a
      shape, it is two axes each drawing a line;
    * `label.show` is forced to false for an ordinary tooltip axis and to true
      for a cross one.

  PURE: SysUtils, Math, fpjson and the AdvChart units. No painter, no LCL. }
interface
uses
  SysUtils, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Option,
  tyControls.AdvChart.Paint, tyControls.AdvChart.Color,
  tyControls.AdvChart.Scale;

type
  { `'cross'` is here because the OPTION can say it; no shape ever does. }
  TTyAxisPointerType = (aptLine, aptShadow, aptCross, aptNone);

  { `'auto'` is not a third boolean: it means "only when something else asks
    for this axis" -- a tooltip, or a handle -- and that is decided elsewhere. }
  TTyAxisPointerShow = (apsAuto, apsYes, apsNo);

  TTyAxisPointerLabelSpec = record
    Show: Boolean;
    { Whether the OPTION said so. The volatile tooltip layer forces a default
      either way, and an explicit value has to survive that. }
    ShowWritten: Boolean;
    Formatter: string;
    HasFormatter: Boolean;
    { `label.precision` as written. NOT written is 'auto' -- the scale's own
      interval precision, so a pointer on an axis stepping by one reads 3.00
      -- and it is this flag, not a zero Precision, that says so: the zero
      value of the record then means the default. }
    HasPrecision: Boolean;
    Precision: TTyLabelPrecision;
    MarginLogical: Double;
    HasColour: Boolean;
    Colour: TTyChartColor;
    HasBackground: Boolean;
    Background: TTyChartColor;
    HasBorderColour: Boolean;
    BorderColour: TTyChartColor;
    HasBorderWidth: Boolean;
    BorderWidthLogical: Double;
    HasBorderRadius: Boolean;
    BorderRadiusLogical: Double;
    HasPadding: Boolean;
    PadLeft, PadTop, PadRight, PadBottom: Double;
  end;

  TTyAxisPointerSpec = record
    Show: TTyAxisPointerShow;
    PointerType: TTyAxisPointerType;
    { Whether `type` was written anywhere, so a caller can tell a default
      'line' from a chosen one. }
    TypeWritten: Boolean;
    Snap: Boolean;
    SnapWritten: Boolean;
    { The pen. Empty dash = solid. }
    HasLineColour: Boolean;
    LineColour: TTyChartColor;
    HasLineWidth: Boolean;
    LineWidthLogical: Double;
    LineDash: TTyOptDash;
    LineDashExplicit: TTyDoubleArray;
    LineDashWritten: Boolean;
    { The band. }
    HasShadowColour: Boolean;
    ShadowColour: TTyChartColor;
    LabelSpec: TTyAxisPointerLabelSpec;
  end;

{ The resolved spec for one axis.

  AAxisMainType / AAxisIndex address the axis' own option block ('xAxis', 2).
  AAxisIsCategory decides snap's default. AFromTooltip says the axis is being
  driven by a tooltip -- which is what lets the tooltip layer in at all, and
  what forces the label off. ATriggerTooltip is `tooltip.trigger = 'axis'` for
  a base axis and FALSE for the other arm of a cross.

  ACross says the tooltip asked for a cross. It changes three things, and they
  are not cosmetic: it inverts the label default, it swaps crossStyle in as the
  pen for the non-triggering arm, and (in the caller) it puts a pointer on the
  other axis as well. }
function TyAxisPointerSpecOf(AOption: TTyChartOption;
  const AAxisMainType: string; AAxisIndex: Integer; AAxisIsCategory: Boolean;
  AFromTooltip, ATriggerTooltip, ACross: Boolean): TTyAxisPointerSpec;

{ `label.precision` the way upstream's round reads it: 'auto'; a number; a
  string Number() reads ('3' is three, '' is nought); true and false as one
  and nought. What Number() cannot read -- 'abc', an object -- prints the
  value's own ToString. }
function TyLabelPrecisionOf(AData: TJSONData): TTyLabelPrecision;

{ The type the TOOLTIP asked for, read on its own -- which is how a caller
  learns it said 'cross' before that word is rewritten away per axis. }
function TyTooltipAxisPointerType(AOption: TTyChartOption): TTyAxisPointerType;

{ Which axis an 'axis' trigger points at: 'x', 'y', or '' for auto.
  `tooltip.axisPointer.axis`, default 'auto'. }
function TyTooltipAxisPointerAxis(AOption: TTyChartOption): string;

{ The band a shadow covers, CLAMPED TO THE AXIS EXTENT rather than centred and
  overflowing -- so the band at the first or last category is HALF WIDTH, and
  asymmetric rather than shifted inward, because the two ends clamp
  independently.

  AExtentA/AExtentB are the axis' pixel ends in whatever order it has them;
  the clamp normalises. Answers False when there is no band to draw. }
function TyAxisPointerBand(AAtPx, ABandWidthPx, AExtentA, AExtentB: Double;
  out ALoPx, AHiPx: Double): Boolean;

implementation

{ ---- reading one axisPointer block ---- }

type
  TTyPointerLevel = (apnAll, apnTooltip, apnRootUnderTooltip);

function PointerTypeOf(const AText: string): TTyAxisPointerType;
begin
  if AText = 'shadow' then Exit(aptShadow);
  if AText = 'cross' then Exit(aptCross);
  if AText = 'none' then Exit(aptNone);
  Result := aptLine;
end;

procedure ReadLabel(ANode: TJSONObject; var ASpec: TTyAxisPointerLabelSpec;
  var ASeen: TTyStringArray); forward;

function TyLabelPrecisionOf(AData: TJSONData): TTyLabelPrecision;
var s: string; v: Double; code: Integer;
begin
  Result := TyLabelPrecision(lpNotANumber);
  if AData = nil then Exit;
  case AData.JSONType of
    jtNumber: Result := TyLabelPrecision(lpDigits, AData.AsFloat);
    jtBoolean:
      if AData.AsBoolean then Result := TyLabelPrecision(lpDigits, 1)
      else Result := TyLabelPrecision(lpDigits, 0);
    jtString:
      begin
        s := Trim(AData.AsString);
        if AData.AsString = 'auto' then Result := TyLabelPrecision(lpAuto)
        else if s = '' then Result := TyLabelPrecision(lpDigits, 0)
        else
        begin
          Val(s, v, code);
          if code = 0 then Result := TyLabelPrecision(lpDigits, v);
        end;
      end;
    jtArray:
      { Number([]) is nought, Number([3]) three, anything longer NaN. }
      if TJSONArray(AData).Count = 0 then Result := TyLabelPrecision(lpDigits, 0)
      else if (TJSONArray(AData).Count = 1)
        and (TJSONArray(AData).Items[0].JSONType = jtNumber) then
        Result := TyLabelPrecision(lpDigits, TJSONArray(AData).Items[0].AsFloat);
  end;
end;

{ First level to mention a key wins it -- which is what upstream's per-leaf
  null-only fallback comes to when the levels are visited innermost first. }
function Claim(ANode: TJSONObject; const AKey: string;
  var ASeen: TTyStringArray; const APrefix: string = ''): Boolean;
var i: Integer;
begin
  { THE PREFIX IS NOT DECORATION. `show` is a key of the axisPointer block AND
    a key of its label, and one flat list of claimed names makes the pointer's
    `show` swallow the label's -- so a written `label.show` was blocked by a
    level that had merely mentioned `show` two lines above it. One namespace
    for two vocabularies is the whole bug. }
  Result := False;
  if ANode = nil then Exit;
  for i := 0 to High(ASeen) do
    if ASeen[i] = APrefix + AKey then Exit;
  { A NULL IS NOT A VALUE. Upstream falls back per leaf only when a level's
    value is null or absent, so `formatter: null` on the axis lets the
    tooltip's formatter through; claiming it here blocked every level below. }
  if (ANode.Find(AKey) = nil) or (ANode.Find(AKey).JSONType = jtNull) then Exit;
  SetLength(ASeen, Length(ASeen) + 1);
  ASeen[High(ASeen)] := APrefix + AKey;
  Result := True;
end;

procedure ReadLabel(ANode: TJSONObject; var ASpec: TTyAxisPointerLabelSpec;
  var ASeen: TTyStringArray);
var
  d: TJSONData;
  lbl: TJSONObject;
  a: TJSONArray;
  c: TTyChartColor;
  v: array[0..3] of Double;
  i, n: Integer;
begin
  if ANode = nil then Exit;
  d := ANode.Find('label');
  if not (d is TJSONObject) then Exit;
  lbl := TJSONObject(d);

  if Claim(lbl, 'show', ASeen, 'label.') then
  begin
    d := lbl.Find('show');
    if d.JSONType = jtBoolean then
    begin
      ASpec.Show := d.AsBoolean;
      ASpec.ShowWritten := True;
    end;
  end;
  if Claim(lbl, 'formatter', ASeen, 'label.') then
  begin
    d := lbl.Find('formatter');
    if (d.JSONType = jtString) and (d.AsString <> '') then
    begin
      ASpec.Formatter := d.AsString;
      ASpec.HasFormatter := True;
    end;
  end;
  if Claim(lbl, 'precision', ASeen, 'label.') then
  begin
    d := lbl.Find('precision');
    ASpec.HasPrecision := True;
    ASpec.Precision := TyLabelPrecisionOf(d);
  end;
  if Claim(lbl, 'margin', ASeen, 'label.') then
  begin
    d := lbl.Find('margin');
    if d.JSONType = jtNumber then
      ASpec.MarginLogical := Max(Double(0), Min(Double(400), d.AsFloat));
  end;
  if Claim(lbl, 'color', ASeen, 'label.') then
  begin
    d := lbl.Find('color');
    if (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, c) then
    begin
      ASpec.HasColour := True;
      ASpec.Colour := c;
    end;
  end;
  if Claim(lbl, 'backgroundColor', ASeen, 'label.') then
  begin
    d := lbl.Find('backgroundColor');
    if (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, c) then
    begin
      ASpec.HasBackground := True;
      ASpec.Background := c;
    end;
  end;
  if Claim(lbl, 'borderColor', ASeen, 'label.') then
  begin
    d := lbl.Find('borderColor');
    if (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, c) then
    begin
      ASpec.HasBorderColour := True;
      ASpec.BorderColour := c;
    end;
  end;
  if Claim(lbl, 'borderWidth', ASeen, 'label.') then
  begin
    d := lbl.Find('borderWidth');
    if d.JSONType = jtNumber then
    begin
      ASpec.HasBorderWidth := True;
      ASpec.BorderWidthLogical := Max(Double(0), Min(Double(64), d.AsFloat));
    end;
  end;
  if Claim(lbl, 'borderRadius', ASeen, 'label.') then
  begin
    d := lbl.Find('borderRadius');
    if d.JSONType = jtNumber then
    begin
      ASpec.HasBorderRadius := True;
      ASpec.BorderRadiusLogical := Max(Double(0), Min(Double(256), d.AsFloat));
    end;
  end;
  if Claim(lbl, 'padding', ASeen, 'label.') then
  begin
    d := lbl.Find('padding');
    if d.JSONType = jtNumber then
    begin
      ASpec.HasPadding := True;
      ASpec.PadTop := d.AsFloat;
      ASpec.PadRight := ASpec.PadTop;
      ASpec.PadBottom := ASpec.PadTop;
      ASpec.PadLeft := ASpec.PadTop;
    end
    else if d is TJSONArray then
    begin
      a := TJSONArray(d);
      n := a.Count;
      if (n >= 1) and (n <= 4) then
      begin
        for i := 0 to 3 do v[i] := 0;
        for i := 0 to n - 1 do
        begin
          { TYPE-CHECKED: Floats[] coerces and RAISES on a string. }
          if a.Items[i].JSONType <> jtNumber then Exit;
          v[i] := a.Floats[i];
        end;
        ASpec.HasPadding := True;
        case n of
          1: begin ASpec.PadTop := v[0]; ASpec.PadRight := v[0];
                   ASpec.PadBottom := v[0]; ASpec.PadLeft := v[0]; end;
          2: begin ASpec.PadTop := v[0]; ASpec.PadBottom := v[0];
                   ASpec.PadRight := v[1]; ASpec.PadLeft := v[1]; end;
          3: begin ASpec.PadTop := v[0]; ASpec.PadRight := v[1];
                   ASpec.PadLeft := v[1]; ASpec.PadBottom := v[2]; end;
        else
          ASpec.PadTop := v[0]; ASpec.PadRight := v[1];
          ASpec.PadBottom := v[2]; ASpec.PadLeft := v[3];
        end;
      end;
    end;
  end;
end;

{ One level of the chain. AStyleKey is which block supplies the pen --
  'lineStyle' everywhere except the non-triggering arm of a cross, where the
  tooltip's `crossStyle` crosses over as the pen instead. }
{ ALevel says which of this block's keys the level is allowed to write.

    apnAll      the axis' own block, and the root when no tooltip is involved
    apnTooltip  `tooltip.axisPointer` -- `show` is not one of the nine fields
                that cross, and `snap` is cloned and then overwritten, so
                neither may be written from here
    apnRootUnderTooltip  the root, reachable for everything the tooltip layer
                did not claim EXCEPT snap, which is recomputed per axis and
                therefore unreachable from the root on a tooltip axis }
procedure MergePointerNode(ANode: TJSONObject; const AStyleKey: string;
  ALevel: TTyPointerLevel;
  var ASpec: TTyAxisPointerSpec; var ASeen: TTyStringArray);
var
  d: TJSONData;
  st: TTyOptStyle;
  sh: TTyOptStyle;
  c: TTyChartColor;
begin
  if ANode = nil then Exit;

  if (ALevel <> apnTooltip) and Claim(ANode, 'show', ASeen) then
  begin
    d := ANode.Find('show');
    if d.JSONType = jtBoolean then
    begin
      if d.AsBoolean then ASpec.Show := apsYes else ASpec.Show := apsNo;
    end
    else if (d.JSONType = jtString) and (d.AsString = 'auto') then
      ASpec.Show := apsAuto;
  end;
  if Claim(ANode, 'type', ASeen) then
  begin
    d := ANode.Find('type');
    if d.JSONType = jtString then
    begin
      ASpec.PointerType := PointerTypeOf(d.AsString);
      ASpec.TypeWritten := True;
    end;
  end;
  if (ALevel = apnAll) and Claim(ANode, 'snap', ASeen) then
  begin
    d := ANode.Find('snap');
    if d.JSONType = jtBoolean then
    begin
      ASpec.Snap := d.AsBoolean;
      ASpec.SnapWritten := True;
    end;
  end;

  if Claim(ANode, AStyleKey, ASeen) then
  begin
    st := TyReadOptStyle(ANode, AStyleKey);
    if st.Color.Written and not st.Color.IsNone and not st.Color.IsAuto then
    begin
      ASpec.HasLineColour := True;
      ASpec.LineColour := st.Color.Color;
    end;
    if not IsNan(st.BorderWidthLogical) then
    begin
      ASpec.HasLineWidth := True;
      ASpec.LineWidthLogical := Max(Double(0), Min(Double(64),
        st.BorderWidthLogical));
    end;
    if st.Dash <> todNone then
    begin
      ASpec.LineDash := st.Dash;
      ASpec.LineDashExplicit := st.DashLogical;
      ASpec.LineDashWritten := True;
    end;
  end;

  if Claim(ANode, 'shadowStyle', ASeen) then
  begin
    sh := TyReadOptStyle(ANode, 'shadowStyle');
    if sh.Color.Written and not sh.Color.IsNone and not sh.Color.IsAuto then
    begin
      ASpec.HasShadowColour := True;
      ASpec.ShadowColour := sh.Color.Color;
    end;
  end;

  ReadLabel(ANode, ASpec.LabelSpec, ASeen);
end;

{ The `axisPointer` object under a component, or nil. }
function PointerNodeIn(ANode: TJSONData): TJSONObject;
var d: TJSONData;
begin
  Result := nil;
  if not (ANode is TJSONObject) then Exit;
  d := TJSONObject(ANode).Find('axisPointer');
  if d is TJSONObject then Result := TJSONObject(d);
end;

function TooltipNode(AOption: TTyChartOption): TJSONObject;
var d: TJSONData;
begin
  Result := nil;
  if AOption = nil then Exit;
  d := AOption.ComponentAt('tooltip', 0);
  if d is TJSONObject then Result := TJSONObject(d);
end;

function TyTooltipAxisPointerType(AOption: TTyChartOption): TTyAxisPointerType;
var
  tip: TJSONObject;
  ap: TJSONObject;
  d: TJSONData;
begin
  { THE TOOLTIP'S OWN DEFAULT IS 'line' AND IT WINS AT RUNTIME. Both upstream
    declarations say 'line', and the tooltip's materialises into the volatile
    layer, which shadows the root -- so `axisPointer: {type:'shadow'}` written
    at the ROOT has no effect on a tooltip axis pointer at all. There is no
    per-axis-kind default table anywhere in 6.1: every shadow in an ECharts
    bar demo was written by its author. }
  Result := aptLine;
  tip := TooltipNode(AOption);
  if tip = nil then Exit;
  ap := PointerNodeIn(tip);
  if ap = nil then Exit;
  d := ap.Find('type');
  if (d <> nil) and (d.JSONType = jtString) then
    Result := PointerTypeOf(d.AsString);
end;

function TyTooltipAxisPointerAxis(AOption: TTyChartOption): string;
var
  tip, ap: TJSONObject;
  d: TJSONData;
  s: string;
begin
  Result := '';
  tip := TooltipNode(AOption);
  if tip = nil then Exit;
  ap := PointerNodeIn(tip);
  if ap = nil then Exit;
  d := ap.Find('axis');
  if (d = nil) or (d.JSONType <> jtString) then Exit;
  s := d.AsString;
  if (s = 'x') or (s = 'y') then Result := s;
end;

function TyAxisPointerSpecOf(AOption: TTyChartOption;
  const AAxisMainType: string; AAxisIndex: Integer; AAxisIsCategory: Boolean;
  AFromTooltip, ATriggerTooltip, ACross: Boolean): TTyAxisPointerSpec;
var
  seen: TTyStringArray;
  tip: TJSONObject;
  penKey: string;
begin
  Result := Default(TTyAxisPointerSpec);
  Result.Show := apsAuto;
  Result.PointerType := aptLine;
  Result.LineDash := todDashed;
  Result.LabelSpec.MarginLogical := 3;
  if AOption = nil then Exit;
  seen := nil;

  { ---- the axis' own block, which outranks everything ---- }
  MergePointerNode(PointerNodeIn(
    AOption.ComponentAt(AAxisMainType, AAxisIndex)), 'lineStyle', apnAll,
    Result, seen);

  { ---- the tooltip's, but only nine of its keys and only for a tooltip
         axis. `show`, `triggerTooltip`, `handle`, `link` and `zlevel` written
         here are silently dead upstream, so they are not read. ---- }
  if AFromTooltip then
  begin
    tip := TooltipNode(AOption);
    { THE PEN COMES FROM crossStyle on the NON-TRIGGERING ARM of a cross, and
      from lineStyle everywhere else. The gate is `not triggerTooltip`, so for
      the common `tooltip: {axisPointer: {type:'cross'}}` written WITHOUT
      `trigger: 'axis'` both arms take crossStyle -- a default cross is one
      arm at the border shade and the other at a darker one, both dashed. }
    if ACross and not ATriggerTooltip then penKey := 'crossStyle'
    else penKey := 'lineStyle';
    if tip <> nil then
      MergePointerNode(PointerNodeIn(tip), penKey, apnTooltip, Result, seen);
  end;

  { ---- and the root component, reachable for whatever is still unclaimed ---- }
  if AFromTooltip then
    MergePointerNode(PointerNodeIn(AOption.Root), 'lineStyle',
      apnRootUnderTooltip, Result, seen)
  else
    MergePointerNode(PointerNodeIn(AOption.Root), 'lineStyle', apnAll,
      Result, seen);

  if not AFromTooltip then Exit;

  { ---- the three overwrites ---- }

  { CROSS IS NEVER A SHAPE. It is rewritten to a line PER AXIS, and the drawing
    layer upstream has only two builders -- `line` and `shadow`. A root
    `axisPointer: {type:'cross'}` on a non-tooltip axis reaches that table
    unrewritten and throws; a port must coerce it here or reject it. }
  if Result.PointerType = aptCross then Result.PointerType := aptLine;

  { SNAP IS RECOMPUTED FROM THE AXIS KIND, unconditionally -- which is what
    makes `tooltip.axisPointer.snap` dead code and the root's unreachable. The
    axis' OWN snap still wins, because it was claimed first and this only fills
    what nobody wrote.

    The rule, in upstream's own words: a category axis does not auto-snap,
    otherwise a tick with no value could not be hovered; a value, time or log
    axis does, when the tooltip is what asked for it. }
  if not Result.SnapWritten then
    Result.Snap := (not AAxisIsCategory) and ATriggerTooltip;

  { AND THE LABEL IS OFF, unless this is a cross -- which INVERTS the default
    rather than nudging it. An explicit `label.show` survives either way. }
  if not Result.LabelSpec.ShowWritten then
    Result.LabelSpec.Show := ACross;
end;

function TyAxisPointerBand(AAtPx, ABandWidthPx, AExtentA, AExtentB: Double;
  out ALoPx, AHiPx: Double): Boolean;
var lo, hi: Double;
begin
  ALoPx := 0;
  AHiPx := 0;
  Result := False;
  if IsNan(AAtPx) or IsNan(ABandWidthPx) then Exit;
  if ABandWidthPx <= 0 then Exit;
  { The extent arrives in the axis' own order, which for a y axis is usually
    descending. Normalising is not cosmetic: the clamp below is written as
    min-of-the-low-end and max-of-the-high-end precisely so it cannot depend
    on which way round they came. }
  lo := Min(AExtentA, AExtentB);
  hi := Max(AExtentA, AExtentB);
  { CLAMPED, NOT CENTRED-AND-OVERFLOWING. At the first or last category the
    band is HALF WIDTH -- and asymmetric rather than shifted inward, because
    the two ends clamp independently. A port that centred the rect and then
    clipped it would move the band, not shorten it. }
  ALoPx := Max(lo, AAtPx - ABandWidthPx / 2);
  AHiPx := Min(hi, AAtPx + ABandWidthPx / 2);
  Result := AHiPx > ALoPx;
end;

end.
