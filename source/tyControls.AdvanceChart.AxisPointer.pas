unit tyControls.AdvanceChart.AxisPointer;
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

  PURE: SysUtils, Math, fpjson and the AdvanceChart units. No painter, no LCL. }
interface
uses
  SysUtils, Math, fpjson,
  tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Option,
  tyControls.AdvanceChart.Paint, tyControls.AdvanceChart.Color,
  tyControls.AdvanceChart.Scale;

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
    { [R5-A] the label's fontStyle (TyFontStyleCode): the nearest block's,
      else the root textStyle's }
    FontStyle: Byte;
    { [R7-N] THE LABEL MODEL AS createTextStyle READS IT: every key of the
      levels' `label` blocks, the first level to write one (not null)
      winning it, and `rich` per style name and key -- the model chain's
      getShallow and getModel(['rich', name]). JSON text, '' when no level
      wrote a label. }
    Json: string;
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
    { [R7-AA] the width is +Infinity: it strokes at the width the canvas had
      (a dash word under it is refused: solid) }
    LineWidthInf: Boolean;
    LineDash: TTyOptDash;
    LineDashExplicit: TTyDoubleArray;
    LineDashWritten: Boolean;
    { The band. }
    HasShadowColour: Boolean;
    ShadowColour: TTyChartColor;
    { [R7-X] THE REST OF buildElStyle'S STYLE: getLineStyle's opacity,
      shadow, dash phase, cap, join and miterLimit (LineLook), getAreaStyle's
      opacity and shadow (BandLook), each key off the chain the colour,
      width and type are read from -- the axis' block, the tooltip's (one
      level's whole), the axisPointer component's -- and below it the
      option root's lineStyle / shadowStyle (GlobalModel, every model's
      parent: the component's defaults hold the colour, width and type).
      Alpha (as written; 1 unwritten), the shadow's four, LineCap,
      LineJoin, MiterLimit (0 the default 10) and DashOffsetLogical of a
      TTyChartElementStyle. }
    LineLook: TTyChartElementStyle;
    BandLook: TTyChartElementStyle;
    LabelSpec: TTyAxisPointerLabelSpec;
    { [R2-I7] `triggerTooltip` as the axis' own model (its block over the
      root) says it, default true -- what an axis collected for its own
      `show` triggers the tooltip with. A tooltip axis is handed its own
      (the trigger), so this is not read for one. }
    TriggerTooltip: Boolean;
    { [R5-D] `triggerEmphasis` as the axis' own model says it, default true:
      whether the rows the shown pointer stands on are highlighted
      (axisTrigger.dispatchHighDownActually). Like triggerTooltip it is not
      one of the fields the tooltip hands its axes, so tooltip.axisPointer's
      is never read: the axis block, then the root component. }
    TriggerEmphasis: Boolean;
  end;

{ [R5-D] axisPointerModel.getModel('handle'): the axis' own
  axisPointer.handle over the axisPointer component's, key by key, over
  AxisPointerModel's defaults (show false, the default icon, size 45, margin
  50, throttle 40). getItemStyle's keys: color (unwritten: the skin's
  accent, upstream's accent40), borderColor, borderWidth, opacity. }
type
  TTyAxisPointerHandle = record
    Show: Boolean;
    Icon: string;
    SizeW, SizeH: Double;
    Margin: Double;
    Throttle: Double;
    HasColour: Boolean;
    Colour: TTyChartColor;
    { a colour written as 'none' (or one that does not parse): no fill }
    NoFill: Boolean;
    HasBorderColour: Boolean;
    BorderColour: TTyChartColor;
    BorderWidth: Double;
    Opacity: Double;
    { [R5-F] getItemStyle's shadow keys (the four _renderHandle lists) }
    HasShadow: Boolean;
    Shadow: TTyChartShadow;
  end;

const
  TyAxisPointerHandleIcon = 'M10.7,11.9v-1.3H9.3v1.3c-4.9,0.3-8.8,4.4-8.8,9.4c0,5,3.9,9.1,8.8,9.4h1.3c4.9-0.3,8.8-4.4,8.8-9.4C19.5,16.3,15.6,12.2,10.7,11.9z M13.3,24.4H6.7v-1.2h6.6z M13.3,22H6.7v-1.2h6.6z M13.3,19.6H6.7v-1.2h6.6z';

function TyAxisPointerHandleOf(AOption: TTyChartOption;
  const AAxisMainType: string; AAxisIndex: Integer): TTyAxisPointerHandle;

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
  AFromTooltip, ATriggerTooltip, ACross: Boolean;
  ACoordTip: TJSONObject = nil): TTyAxisPointerSpec;

{ `label.precision` the way upstream's round reads it: 'auto'; a number; a
  string Number() reads ('3' is three, '' is nought); true and false as one
  and nought. What Number() cannot read -- 'abc', an object -- prints the
  value's own ToString. }
function TyLabelPrecisionOf(AData: TJSONData): TTyLabelPrecision;

{ The type the TOOLTIP asked for, read on its own -- which is how a caller
  learns it said 'cross' before that word is rewritten away per axis. }
function TyTooltipAxisPointerType(AOption: TTyChartOption;
  ACoordTip: TJSONObject = nil): TTyAxisPointerType;

{ Which axis an 'axis' trigger points at: 'x', 'y', or '' for auto.
  `tooltip.axisPointer.axis`, default 'auto'. }
function TyTooltipAxisPointerAxis(AOption: TTyChartOption;
  ACoordTip: TJSONObject = nil): string;
{ The same on a polar: 'radius', 'angle', or '' for auto [Batch 111] }
function TyTooltipPolarPointerAxis(AOption: TTyChartOption;
  ACoordTip: TJSONObject = nil): string;
{ [R5-D] ACoordTip IN ALL FOUR: the coordinate system's own `tooltip`
  (grid, polar, singleAxis -- nil for none). collectAxesInfo reads
  coordSysModel.getModel('tooltip', globalTooltipModel), so every key of it
  is asked first and the global tooltip's only where it is missing or null
  -- `axisPointer.type` / `axis`, and the fields makeAxisPointerModel copies
  (a whole lineStyle at the first level that has one). }

{ The band a shadow covers, CLAMPED TO THE AXIS EXTENT rather than centred and
  overflowing -- so the band at the first or last category is HALF WIDTH, and
  asymmetric rather than shifted inward, because the two ends clamp
  independently.

  AExtentA/AExtentB are the axis' pixel ends in whatever order it has them;
  the clamp normalises. Answers False when there is no band to draw. }
function TyAxisPointerBand(AAtPx, ABandWidthPx, AExtentA, AExtentB: Double;
  out ALoPx, AHiPx: Double): Boolean;

implementation

uses jsonparser, tyControls.AdvanceChart.States;

{ ---- reading one axisPointer block ---- }

type
  TTyPointerLevel = (apnAll, apnTooltip, apnRootUnderTooltip);

{ [R2-I7] JavaScript truthiness of an option value }
function PtrTruthy(AData: TJSONData): Boolean;
begin
  Result := False;
  if AData = nil then Exit;
  case AData.JSONType of
    jtBoolean: Result := AData.AsBoolean;
    jtNumber: Result := (AData.AsFloat <> 0) and not IsNan(AData.AsFloat);
    jtString: Result := AData.AsString <> '';
    jtNull: Result := False;
  else
    Result := True;
  end;
end;

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

{ [R7-N] one level's `label` into the merged label model (AJson): a key
  the merge does not hold yet is this level's, a null claims nothing, and
  `rich` merges per style name and key }
procedure MergeLabelJson(ALabel: TJSONObject; var AJson: string);
var
  m, mr, src, dst, one: TJSONObject;
  d, parsed: TJSONData;
  i, j, k: Integer;
  key, name: string;
begin
  if (ALabel = nil) or (ALabel.Count = 0) then Exit;
  m := nil;
  try
    if AJson <> '' then
    begin
      parsed := GetJSON(AJson);
      if parsed is TJSONObject then m := TJSONObject(parsed)
      else
      begin
        parsed.Free;
        m := TJSONObject.Create;
      end;
    end
    else
      m := TJSONObject.Create;
    for i := 0 to ALabel.Count - 1 do
    begin
      key := ALabel.Names[i];
      d := ALabel.Items[i];
      if d.JSONType = jtNull then Continue;
      if (key = 'rich') and (d is TJSONObject) then
      begin
        if m.Find('rich') = nil then m.Add('rich', TJSONObject.Create);
        if not (m.Find('rich') is TJSONObject) then Continue;
        mr := TJSONObject(m.Find('rich'));
        src := TJSONObject(d);
        for j := 0 to src.Count - 1 do
        begin
          name := src.Names[j];
          if not (src.Items[j] is TJSONObject) then
          begin
            if (mr.Find(name) = nil) and (src.Items[j].JSONType <> jtNull) then
              mr.Add(name, src.Items[j].Clone);
            Continue;
          end;
          one := TJSONObject(src.Items[j]);
          if mr.Find(name) = nil then mr.Add(name, TJSONObject.Create);
          if not (mr.Find(name) is TJSONObject) then Continue;
          dst := TJSONObject(mr.Find(name));
          for k := 0 to one.Count - 1 do
            if (one.Items[k].JSONType <> jtNull) and (dst.Find(one.Names[k]) = nil) then
              dst.Add(one.Names[k], one.Items[k].Clone);
        end;
        Continue;
      end;
      if m.Find(key) = nil then m.Add(key, d.Clone);
    end;
    AJson := m.AsJSON;
  finally
    m.Free;
  end;
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
  MergeLabelJson(lbl, ASpec.Json);

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
  if Claim(lbl, 'fontStyle', ASeen, 'label.') then
    ASpec.FontStyle := TyFontStyleCode(lbl.Find('fontStyle'));
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
    end
    { [R7-AC] a string no parser reads: the label's span keeps the fill the
      canvas had [was: not written, the skin's] }
    else if (d.JSONType = jtString) and (d.AsString <> '') and (d.AsString <> 'none')
      and not TyColourIsHandler(d.AsString) then
    begin
      ASpec.HasColour := True;
      ASpec.Colour := cTyCanvasColourLeft;
    end;
  end;
  if Claim(lbl, 'backgroundColor', ASeen, 'label.') then
  begin
    d := lbl.Find('backgroundColor');
    if (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, c) then
    begin
      ASpec.HasBackground := True;
      ASpec.Background := c;
    end
    { [R7-AC] and its box the fill (buildLabelElOption's backgroundColor:
      the box drawn, in what the canvas had) }
    else if (d.JSONType = jtString) and (d.AsString <> '') and (d.AsString <> 'none')
      and not TyColourIsHandler(d.AsString) then
    begin
      ASpec.HasBackground := True;
      ASpec.Background := cTyCanvasColourLeft;
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
{ [R7-X] THE STYLE MODELS' CHAIN: getModel('lineStyle') /
  getModel('shadowStyle') of the axis' pointer model -- the axis' block,
  then the volatile model's (makeAxisPointerModel clones the tooltip's
  block whole: only the first tooltip level that has one), then the
  axisPointer component's, each key from the first block that writes it
  (null falls through) }
type
  TTyPtrBlocks = array of TJSONObject;
  TTyPtrChain = record
    Pen, Band: TTyPtrBlocks;
    TipPen, TipBand: Boolean;
  end;

procedure ChainTake(ANode: TJSONObject; const AKey: string; ATip: Boolean;
  var ATaken: Boolean; var AList: TTyPtrBlocks);
var d: TJSONData;
begin
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if not (d is TJSONObject) then Exit;
  if ATip then
  begin
    if ATaken then Exit;
    ATaken := True;
  end;
  SetLength(AList, Length(AList) + 1);
  AList[High(AList)] := TJSONObject(d);
end;

procedure MergePointerNode(ANode: TJSONObject; const AStyleKey: string;
  ALevel: TTyPointerLevel;
  var ASpec: TTyAxisPointerSpec; var ASeen: TTyStringArray;
  var AChain: TTyPtrChain);
var
  d: TJSONData;
begin
  if ANode = nil then Exit;

  if (ALevel <> apnTooltip) and Claim(ANode, 'show', ASeen) then
  begin
    d := ANode.Find('show');
    { [R2-I7] TRUTHINESS, as saveTooltipAxisInfo tests it: 'auto' is its own
      word, anything else truthy shows and anything falsy does not }
    if (d.JSONType = jtString) and (d.AsString = 'auto') then
      ASpec.Show := apsAuto
    else if PtrTruthy(d) then ASpec.Show := apsYes
    else ASpec.Show := apsNo;
  end;
  { [R2-I7] the axis' own model's triggerTooltip: the axis block, then the
    root; never the tooltip's (not one of the nine fields) }
  if (ALevel <> apnTooltip) and Claim(ANode, 'triggerTooltip', ASeen) then
    ASpec.TriggerTooltip := PtrTruthy(ANode.Find('triggerTooltip'));
  { [R5-D] triggerEmphasis the same way }
  if (ALevel <> apnTooltip) and Claim(ANode, 'triggerEmphasis', ASeen) then
    ASpec.TriggerEmphasis := PtrTruthy(ANode.Find('triggerEmphasis'));
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

  { [R7-X] the pen and the band onto the chain, resolved key by key below
    [was: the first level's block whole, at every level] }
  ChainTake(ANode, AStyleKey, ALevel = apnTooltip, AChain.TipPen, AChain.Pen);
  ChainTake(ANode, 'shadowStyle', ALevel = apnTooltip, AChain.TipBand, AChain.Band);

  ReadLabel(ANode, ASpec.LabelSpec, ASeen);
end;

{ [R7-X] the chain's keys into the spec: the colour, the width and the type
  where a block of it writes them (the component's defaults are the skin's),
  the rest down to the option root's block (ARootPen, ARootBand) }
procedure ResolvePointerChain(const AChain: TTyPtrChain; ARootPen, ARootBand: TJSONObject;
  var ASpec: TTyAxisPointerSpec);
var
  i: Integer;
  st: TTyOptStyle;
  d: TJSONData;
  all: TTyPtrBlocks;
  joinHas: Boolean;
  sh: TTyChartShadow;

  function Writes(ABlock: TJSONObject; const AKey: string): Boolean;
  begin
    d := ABlock.Find(AKey);
    Result := (d <> nil) and (d.JSONType <> jtNull);
  end;

  { opacity, as written, and the shadow's four off AList }
  procedure Looks(const AList: TTyPtrBlocks; var AStyle: TTyChartElementStyle);
  begin
    AStyle.Alpha := 1;
    d := TyStFind(AList, ['opacity']);
    if (d <> nil) and (d.JSONType = jtNumber) and not IsNan(d.AsFloat) then
      AStyle.Alpha := d.AsFloat;
    if TyStReadShadow(AList, [], [], sh) then TyStyleSetShadow(AStyle, sh);
  end;

begin
  for i := 0 to High(AChain.Pen) do
    if Writes(AChain.Pen[i], 'color') then
    begin
      st := TyReadOptLineStyleOf(AChain.Pen[i]);
      if st.Color.Written and not st.Color.IsNone and not st.Color.IsAuto then
      begin
        ASpec.HasLineColour := True;
        ASpec.LineColour := st.Color.Color;
      end;
      Break;
    end;
  for i := 0 to High(AChain.Pen) do
    if Writes(AChain.Pen[i], 'width') then
    begin
      st := TyReadOptLineStyleOf(AChain.Pen[i]);
      if st.WidthInf then
      begin
        ASpec.HasLineWidth := True;
        ASpec.LineWidthInf := True;
        ASpec.LineWidthLogical := 1;
      end
      else if not IsNan(st.BorderWidthLogical) then
      begin
        ASpec.HasLineWidth := True;
        ASpec.LineWidthLogical := Max(Double(0), Min(Double(64),
          st.BorderWidthLogical));
      end;
      Break;
    end;
  for i := 0 to High(AChain.Pen) do
    if Writes(AChain.Pen[i], 'type') then
    begin
      st := TyReadOptLineStyleOf(AChain.Pen[i]);
      if st.Dash <> todNone then
      begin
        ASpec.LineDash := st.Dash;
        ASpec.LineDashExplicit := st.DashLogical;
        ASpec.LineDashWritten := True;
      end;
      Break;
    end;
  for i := 0 to High(AChain.Band) do
    if Writes(AChain.Band[i], 'color') then
    begin
      st := TyReadOptLineStyleOf(AChain.Band[i]);
      if st.Color.Written and not st.Color.IsNone and not st.Color.IsAuto then
      begin
        ASpec.HasShadowColour := True;
        ASpec.ShadowColour := st.Color.Color;
      end;
      Break;
    end;
  { the pen's other keys, down to the root's block }
  SetLength(all, Length(AChain.Pen) + 1);
  for i := 0 to High(AChain.Pen) do all[i] := AChain.Pen[i];
  all[High(all)] := ARootPen;
  ASpec.LineLook := Default(TTyChartElementStyle);
  Looks(all, ASpec.LineLook);
  TyStTakePenKeys(ASpec.LineLook, all, [], True, [spkEnds], joinHas);
  ASpec.LineLook.DashOffsetLogical := TyOptPenOffset(TyStFind(all, ['dashOffset']));
  if IsNan(ASpec.LineLook.DashOffsetLogical) then ASpec.LineLook.DashOffsetLogical := 0;
  { and the band's }
  SetLength(all, Length(AChain.Band) + 1);
  for i := 0 to High(AChain.Band) do all[i] := AChain.Band[i];
  all[High(all)] := ARootBand;
  ASpec.BandLook := Default(TTyChartElementStyle);
  Looks(all, ASpec.BandLook);
end;

{ the option root's block AKey, or nil }
function RootBlock(AOption: TTyChartOption; const AKey: string): TJSONObject;
var d: TJSONData;
begin
  Result := nil;
  if not (AOption.Root is TJSONObject) then Exit;
  d := TJSONObject(AOption.Root).Find(AKey);
  if d is TJSONObject then Result := TJSONObject(d);
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

{ [R5-D] tooltip.axisPointer.<AKey>: the coordinate system's, else the
  global tooltip's (Model.get falls to the parent on null) }
function TipPointerKey(AOption: TTyChartOption; ACoordTip: TJSONObject;
  const AKey: string): TJSONData;
var ap: TJSONObject;
begin
  Result := nil;
  ap := PointerNodeIn(ACoordTip);
  if ap <> nil then Result := ap.Find(AKey);
  if (Result <> nil) and (Result.JSONType <> jtNull) then Exit;
  Result := nil;
  ap := PointerNodeIn(TooltipNode(AOption));
  if ap <> nil then Result := ap.Find(AKey);
end;

function TyTooltipAxisPointerType(AOption: TTyChartOption;
  ACoordTip: TJSONObject): TTyAxisPointerType;
var
  d: TJSONData;
begin
  { THE TOOLTIP'S OWN DEFAULT IS 'line' AND IT WINS AT RUNTIME. Both upstream
    declarations say 'line', and the tooltip's materialises into the volatile
    layer, which shadows the root -- so `axisPointer: {type:'shadow'}` written
    at the ROOT has no effect on a tooltip axis pointer at all. There is no
    per-axis-kind default table anywhere in 6.1: every shadow in an ECharts
    bar demo was written by its author. }
  Result := aptLine;
  d := TipPointerKey(AOption, ACoordTip, 'type');
  if (d <> nil) and (d.JSONType = jtString) then
    Result := PointerTypeOf(d.AsString);
end;

function TyTooltipAxisPointerAxis(AOption: TTyChartOption;
  ACoordTip: TJSONObject): string;
var
  d: TJSONData;
  s: string;
begin
  Result := '';
  d := TipPointerKey(AOption, ACoordTip, 'axis');
  if (d = nil) or (d.JSONType <> jtString) then Exit;
  s := d.AsString;
  if (s = 'x') or (s = 'y') then Result := s;
end;

function TyTooltipPolarPointerAxis(AOption: TTyChartOption;
  ACoordTip: TJSONObject): string;
var
  d: TJSONData;
  s: string;
begin
  Result := '';
  d := TipPointerKey(AOption, ACoordTip, 'axis');
  if (d = nil) or (d.JSONType <> jtString) then Exit;
  s := d.AsString;
  if (s = 'radius') or (s = 'angle') then Result := s;
end;

function TyAxisPointerSpecOf(AOption: TTyChartOption;
  const AAxisMainType: string; AAxisIndex: Integer; AAxisIsCategory: Boolean;
  AFromTooltip, ATriggerTooltip, ACross: Boolean;
  ACoordTip: TJSONObject): TTyAxisPointerSpec;
var
  seen: TTyStringArray;
  tip: TJSONObject;
  penKey: string;
  chain: TTyPtrChain;
begin
  Result := Default(TTyAxisPointerSpec);
  Result.LineLook.Alpha := 1;
  Result.BandLook.Alpha := 1;
  chain := Default(TTyPtrChain);
  Result.Show := apsAuto;
  Result.PointerType := aptLine;
  Result.LineDash := todDashed;
  Result.LabelSpec.MarginLogical := 3;
  Result.TriggerTooltip := True;
  Result.TriggerEmphasis := True;
  { [R2-I7] THE ROOT COMPONENT'S DEFAULT IS A SHOWN LABEL. Only the volatile
    tooltip layer turns it off (below); an axis collected for its own `show`
    reads the root's `label.show: true`. }
  Result.LabelSpec.Show := True;
  if AOption = nil then Exit;
  seen := nil;

  { ---- the axis' own block, which outranks everything ---- }
  MergePointerNode(PointerNodeIn(
    AOption.ComponentAt(AAxisMainType, AAxisIndex)), 'lineStyle', apnAll,
    Result, seen, chain);

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
    { [R5-D] the coordinate system's tooltip first: each field the first
      level that has it }
    if ACoordTip <> nil then
      MergePointerNode(PointerNodeIn(ACoordTip), penKey, apnTooltip, Result, seen, chain);
    if tip <> nil then
      MergePointerNode(PointerNodeIn(tip), penKey, apnTooltip, Result, seen, chain);
  end;

  { ---- and the root component, reachable for whatever is still unclaimed ---- }
  if AFromTooltip then
    MergePointerNode(PointerNodeIn(AOption.Root), 'lineStyle',
      apnRootUnderTooltip, Result, seen, chain)
  else
    MergePointerNode(PointerNodeIn(AOption.Root), 'lineStyle', apnAll,
      Result, seen, chain);
  { [R7-X] the pen and the band key by key, the option root's blocks under
    them (a root crossStyle is on no chain) }
  ResolvePointerChain(chain, RootBlock(AOption, 'lineStyle'),
    RootBlock(AOption, 'shadowStyle'), Result);
  { [R5-A] the label's text style falls to the root textStyle (labelStyle's
    global one): its fontStyle where no block wrote one }
  if (Result.LabelSpec.FontStyle = TyFontStyleUnset) and (AOption.Root is TJSONObject)
    and (TJSONObject(AOption.Root).Find('textStyle') is TJSONObject) then
    Result.LabelSpec.FontStyle := TyFontStyleCode(TJSONObject(TJSONObject(
      AOption.Root).Find('textStyle')).Find('fontStyle'));

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

function TyAxisPointerHandleOf(AOption: TTyChartOption;
  const AAxisMainType: string; AAxisIndex: Integer): TTyAxisPointerHandle;
var
  own, root, glob: TJSONObject;

  function HandleIn(AAp: TJSONObject): TJSONObject;
  var d: TJSONData;
  begin
    Result := nil;
    if AAp = nil then Exit;
    d := AAp.Find('handle');
    if d is TJSONObject then Result := TJSONObject(d);
  end;

  { Model.get through the parent: the axis' key, else the component's;
    [R7-AA] else, for a key AxisPointerModel's handle has no default for
    (its border, opacity, shadow), the option root's `handle` --
    getModel('handle') climbs to the GlobalModel [was: never read] }
  function Key(const AName: string): TJSONData;
  begin
    Result := nil;
    if own <> nil then Result := own.Find(AName);
    if (Result <> nil) and (Result.JSONType <> jtNull) then Exit;
    Result := nil;
    if root <> nil then Result := root.Find(AName);
    if (Result <> nil) and (Result.JSONType = jtNull) then Result := nil;
    if (Result = nil) and (glob <> nil) and (AName <> 'show') and (AName <> 'icon')
      and (AName <> 'size') and (AName <> 'margin') and (AName <> 'throttle')
      and (AName <> 'color') then
    begin
      Result := glob.Find(AName);
      if (Result <> nil) and (Result.JSONType = jtNull) then Result := nil;
    end;
  end;

  function Num(const AName: string; ADefault: Double): Double;
  var d: TJSONData;
  begin
    Result := ADefault;
    d := Key(AName);
    if d is TJSONNumber then Result := d.AsFloat;
  end;

var
  d: TJSONData;
  c: TTyChartColor;
begin
  Result := Default(TTyAxisPointerHandle);
  Result.Icon := TyAxisPointerHandleIcon;
  Result.SizeW := 45;
  Result.SizeH := 45;
  Result.Margin := 50;
  Result.Throttle := 40;
  Result.Opacity := 1;
  if AOption = nil then Exit;
  own := HandleIn(PointerNodeIn(AOption.ComponentAt(AAxisMainType, AAxisIndex)));
  root := HandleIn(PointerNodeIn(AOption.Root));
  glob := nil;
  if AOption.Root is TJSONObject then glob := HandleIn(TJSONObject(AOption.Root));
  d := Key('show');
  Result.Show := (d <> nil) and (((d.JSONType = jtBoolean) and d.AsBoolean)
    or ((d.JSONType = jtNumber) and (d.AsFloat <> 0))
    or ((d.JSONType = jtString) and (d.AsString <> '')));
  d := Key('icon');
  if (d <> nil) and (d.JSONType = jtString) then Result.Icon := d.AsString;
  { size: a number, or [w, h] }
  d := Key('size');
  if d is TJSONNumber then
  begin
    Result.SizeW := d.AsFloat;
    Result.SizeH := d.AsFloat;
  end
  else if (d is TJSONArray) and (d.Count >= 2) then
  begin
    if TJSONArray(d).Items[0] is TJSONNumber then Result.SizeW := TJSONArray(d).Items[0].AsFloat;
    if TJSONArray(d).Items[1] is TJSONNumber then Result.SizeH := TJSONArray(d).Items[1].AsFloat;
  end;
  Result.Margin := Num('margin', 50);
  { `handleModel.get('throttle') || 0` }
  Result.Throttle := Num('throttle', 40);
  if IsNan(Result.Throttle) then Result.Throttle := 0;
  d := Key('color');
  if (d <> nil) and (d.JSONType = jtString) then
  begin
    if TyTryParseChartColor(d.AsString, c) and not TyChartColorIsNone(d.AsString) then
    begin
      Result.HasColour := True;
      Result.Colour := c;
    end
    { [R7-AE] a colour no parser reads (not '' nor 'none'): the canvas
      refuses it and fills with the one it had [was: no fill] }
    else if (d.AsString <> '') and not TyChartColorIsNone(d.AsString) then
    begin
      Result.HasColour := True;
      Result.Colour := cTyCanvasColourLeft;
    end
    else
      Result.NoFill := True;
  end;
  d := Key('borderColor');
  if (d <> nil) and (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, c)
    and not TyChartColorIsNone(d.AsString) then
  begin
    Result.HasBorderColour := True;
    Result.BorderColour := c;
  end
  { [R7-AE] the same for its border [was: none] }
  else if (d <> nil) and (d.JSONType = jtString) and (d.AsString <> '')
    and not TyChartColorIsNone(d.AsString) then
  begin
    Result.HasBorderColour := True;
    Result.BorderColour := cTyCanvasColourLeft;
  end;
  Result.BorderWidth := Num('borderWidth', 0);
  { [R7-AE] a string is JavaScript's Number of it ('Infinity' a pen the
    canvas refuses; one of no number strokes nothing) [was: nought] }
  d := Key('borderWidth');
  if (d <> nil) and (d.JSONType = jtString) then
  begin
    Result.BorderWidth := TyOptJsNumber(d);
    if IsNan(Result.BorderWidth) then Result.BorderWidth := 0;
  end;
  Result.Opacity := Num('opacity', 1);
  { [R5-F] the shadow [was: not read] }
  Result.HasShadow := TyShadowOfValues(Key('shadowBlur'), Key('shadowOffsetX'),
    Key('shadowOffsetY'), Key('shadowColor'), Result.Shadow);
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
