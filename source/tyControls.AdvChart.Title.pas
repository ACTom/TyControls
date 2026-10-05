unit tyControls.AdvChart.Title;
{$mode objfpc}{$H+}
{ The chart's title and subtitle -- the first component that is neither a
  coordinate system nor a series.

  IT DOES NOT SHRINK ANYTHING. A title floats over the container and the grid's
  own default top gap is what leaves room for it, which is upstream's
  arrangement rather than a simplification: two components that each shrank the
  other would need an order to be argued about, and ECharts argues it by giving
  every component the same container and sensible defaults.

  A TITLE IS A LIST. `title` may be an object or an array of them, and the array
  form is how a chart labels several panels at once. Everything here takes an
  index for that reason.

  PORTED FROM src/component/title/install.ts, ECharts 6.1.0.

  THE ONE THING THAT READS ODDLY, and it is upstream's: `textAlign` is derived
  from `left`/`right` only when it was NOT given, and the derivation also SHIFTS
  the solved box -- right by its whole width, centre by half. Set textAlign
  explicitly and no shift happens, so `left: 'center'` and
  `left: 'center', textAlign: 'center'` are two different pictures. Transcribed,
  because the second is the one people write when the first looks wrong to them
  and they would be surprised twice if it silently agreed.

  PURE: SysUtils, Math, fpjson and the AdvChart units. Text is MEASURED through
  the injected measurer and DRAWN by the control; nothing here touches a
  painter, and the fonts arrive resolved from the theme. }
interface
uses
  SysUtils, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Option,
  tyControls.AdvChart.Shape, tyControls.AdvChart.Layout;

type
  { Resolved, never 'auto' by the time a caller sees a layout. }
  TTyTitleAlign = (ttaAuto, ttaLeft, ttaCentre, ttaRight);
  TTyTitleVAlign = (ttvAuto, ttvTop, ttvMiddle, ttvBottom);

  { The font one of the two lines is drawn in. Resolved from the theme by the
    control and handed in, like every other visual value in this layer. }
  TTyTitleFont = record
    Name: string;
    SizeLogical: Integer;
    Weight: Integer;
    { the author's colour (textStyle / subtextStyle, else the root
      textStyle's) as a chart colour; the theme's where neither is written }
    HasColour: Boolean;
    Colour: Cardinal;
  end;

  TTyTitleSpec = record
    Show: Boolean;
    Text: string;
    Subtext: string;
    { THE BOX AS UPSTREAM'S MODEL HOLDS IT: the raw option values over the
      defaults (left 'center', top 15), merged by mergeLayoutParam's
      ignoreSize rule -- a right of its own nulls the default left. }
    Box: TTyRawBox;
    { CSS order: top, right, bottom, left. Kept as four because `padding` takes
      the CSS short forms and collapsing them early would lose them. }
    Padding: array[0..3] of Double;
    ItemGap: Double;
    Align: TTyTitleAlign;
    VAlign: TTyTitleVAlign;
    { WHAT THE MODEL SAYS, not what it solved to: `left || right` and
      `top || bottom` of the merged box, as their strings. The auto-align
      rules read the word rather than the number, so `left: 'center'` and
      `left: '50%'` -- the same place -- align differently. }
    WordH, WordV: string;
    HasBackground: Boolean;
    BorderWidth: Double;
    BorderRadii: TTyCornerRadii;
  end;

  { Where the two lines go, in DEVICE px. Each is an ANCHOR plus the alignment
    to hang off it, which is how the painter's DrawText wants them. }
  TTyTitleLayout = record
    Valid: Boolean;
    HasSub: Boolean;
    { The background box, padding included -- and as upstream builds it, x, y,
      width, height: the group's position plus its own local box less the
      padding, and the block's size plus the padding. }
    Frame: TTyRectF;
    FrameX, FrameY, FrameW, FrameH: Double;
    TextX, TextY: Double;
    SubX, SubY: Double;
    TextW, TextH: Double;
    SubW, SubH: Double;
    Align: TTyTitleAlign;
    VAlign: TTyTitleVAlign;
  end;

{ How many titles the option carries. An object counts as one. }
function TyTitleCount(AOption: TTyChartOption): Integer;
function TyTitleSpecDefault: TTyTitleSpec;
function TyTitleSpecOf(AOption: TTyChartOption; AIndex: Integer): TTyTitleSpec;

{ Lay one out against AContainer. Both fonts are handed in because this layer
  never asks the theme anything; APPI scales the LOGICAL gaps in the spec.

  Answers Valid = False when there is nothing to draw. }
function TyLayoutTitle(const ASpec: TTyTitleSpec; const AContainer: TTyRectF;
  const AMeasurer: ITyTextMeasurer; const AFont, ASubFont: TTyTitleFont;
  APPI: Integer; const ATextMeter: ITyTextMeasurer = nil;
  const ASubMeter: ITyTextMeasurer = nil): TTyTitleLayout;

implementation

const
  { title's defaultOption, install.ts:106-138. `top` is tokens.size.m. }
  cDefaultTop = 15.0;
  cDefaultPadding = 5.0;
  cDefaultItemGap = 10.0;

function ObjOf(AData: TJSONData): TJSONObject;
begin
  if (AData <> nil) and (AData is TJSONObject) then
    Result := TJSONObject(AData)
  else
    Result := nil;
end;

function TyTitleCount(AOption: TTyChartOption): Integer;
begin
  Result := 0;
  if AOption = nil then Exit;
  Result := AOption.ComponentCount('title');
end;

{ title's defaultOption's box: `left: 'center'`, `top: 15`. }
function DefaultBox: TTyRawBox;
begin
  Result := Default(TTyRawBox);
  Result.Left := TyBoxRawStr('center');
  Result.Top := TyBoxRawNum(cDefaultTop);
end;

function TyTitleSpecDefault: TTyTitleSpec;
var i: Integer;
begin
  Result.Show := True;
  Result.Text := '';
  Result.Subtext := '';
  Result.Box := DefaultBox;
  for i := 0 to 3 do Result.Padding[i] := cDefaultPadding;
  Result.ItemGap := cDefaultItemGap;
  Result.Align := ttaAuto;
  Result.VAlign := ttvAuto;
  Result.WordH := TyBoxWord(Result.Box.Left, Result.Box.Right);
  Result.WordV := TyBoxWord(Result.Box.Top, Result.Box.Bottom);
  Result.HasBackground := False;
  Result.BorderWidth := 0;
  Result.BorderRadii := TyCornerRadii([]);
end;

function StrIn(ANode: TJSONObject; const AKey: string): string;
var d: TJSONData;
begin
  Result := '';
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if (d = nil) or (d.JSONType <> jtString) then Exit;
  Result := d.AsString;
end;

function NumIn(ANode: TJSONObject; const AKey: string; ADefault: Double): Double;
var d: TJSONData;
begin
  Result := ADefault;
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if (d = nil) or (d.JSONType <> jtNumber) then Exit;
  Result := d.AsFloat;
end;

{ textAlign: 'middle' is read as 'center' (install.ts), and a word it does
  not know -- `centre` among them -- is no alignment. }
function AlignOf(const AText: string): TTyTitleAlign;
begin
  if (AText = 'center') or (AText = 'middle') then
    Result := ttaCentre
  else if AText = 'right' then
    Result := ttaRight
  else if AText = 'left' then
    Result := ttaLeft
  else
    Result := ttaAuto;
end;

function VAlignOf(const AText: string): TTyTitleVAlign;
begin
  if (AText = 'middle') or (AText = 'center') then
    Result := ttvMiddle
  else if AText = 'bottom' then
    Result := ttvBottom
  else if AText = 'top' then
    Result := ttvTop
  else
    Result := ttvAuto;
end;

{ padding, in the CSS short forms ECharts accepts. }
procedure ReadPadding(ANode: TJSONObject; var APadding: array of Double);
var
  d: TJSONData;
  arr: TJSONArray;
  i, n: Integer;
  v: array[0..3] of Double;
begin
  if ANode = nil then Exit;
  d := ANode.Find('padding');
  if (d = nil) or (d.JSONType = jtNull) then Exit;
  if d.JSONType = jtNumber then
  begin
    for i := 0 to 3 do APadding[i] := d.AsFloat;
    Exit;
  end;
  if not (d is TJSONArray) then Exit;
  arr := TJSONArray(d);
  n := arr.Count;
  if n = 0 then Exit;
  for i := 0 to 3 do v[i] := 0;
  for i := 0 to Min(3, n - 1) do
    if arr.Items[i].JSONType = jtNumber then v[i] := arr.Items[i].AsFloat;
  case n of
    1: for i := 0 to 3 do APadding[i] := v[0];
    2: begin
         APadding[0] := v[0]; APadding[2] := v[0];
         APadding[1] := v[1]; APadding[3] := v[1];
       end;
    3: begin
         APadding[0] := v[0];
         APadding[1] := v[1]; APadding[3] := v[1];
         APadding[2] := v[2];
       end;
  else
    for i := 0 to 3 do APadding[i] := v[i];
  end;
end;

function TyTitleSpecOf(AOption: TTyChartOption; AIndex: Integer): TTyTitleSpec;
var
  node: TJSONObject;
  d: TJSONData;
begin
  Result := TyTitleSpecDefault;
  if AOption = nil then Exit;
  node := ObjOf(AOption.ComponentAt('title', AIndex));
  if node = nil then Exit;

  d := node.Find('show');
  if (d <> nil) and (d.JSONType = jtBoolean) then Result.Show := d.AsBoolean;
  Result.Text := StrIn(node, 'text');
  Result.Subtext := StrIn(node, 'subtext');

  Result.Box := TyMergeBoxIgnoreSize(node, DefaultBox);
  Result.WordH := TyBoxWord(Result.Box.Left, Result.Box.Right);
  Result.WordV := TyBoxWord(Result.Box.Top, Result.Box.Bottom);

  ReadPadding(node, Result.Padding);
  Result.ItemGap := NumIn(node, 'itemGap', Result.ItemGap);
  Result.Align := AlignOf(StrIn(node, 'textAlign'));
  { textBaseline is the older spelling and wins when both are present --
    retrieve2 takes the first defined. }
  Result.VAlign := VAlignOf(StrIn(node, 'textBaseline'));
  if Result.VAlign = ttvAuto then
    Result.VAlign := VAlignOf(StrIn(node, 'textVerticalAlign'));

  d := node.Find('backgroundColor');
  Result.HasBackground := (d <> nil) and (d.JSONType = jtString)
    and (d.AsString <> '') and (d.AsString <> 'transparent');
  Result.BorderWidth := NumIn(node, 'borderWidth', 0);
  d := node.Find('borderRadius');
  if (d <> nil) and (d.JSONType = jtNumber) then
    Result.BorderRadii := TyCornerRadii([d.AsFloat]);
end;

{ ==================== the layout ==================== }

function TyLayoutTitle(const ASpec: TTyTitleSpec; const AContainer: TTyRectF;
  const AMeasurer: ITyTextMeasurer; const AFont, ASubFont: TTyTitleFont;
  APPI: Integer; const ATextMeter: ITyTextMeasurer;
  const ASubMeter: ITyTextMeasurer): TTyTitleLayout;
var
  raw: TTyRawBox;
  r: TTyXYWH;
  gw, gh, gap, gx, gy, lx, ly: Double;
  pad: array[0..3] of Double;
  i: Integer;
  word_: string;
  scale: Double;
begin
  Result := Default(TTyTitleLayout);
  if not ASpec.Show then Exit;
  if (ASpec.Text = '') and (ASpec.Subtext = '') then Exit;
  if AMeasurer = nil then Exit;
  if not TyRectFIsValid(AContainer) then Exit;

  if APPI > 0 then scale := APPI / 96 else scale := 1;
  for i := 0 to 3 do pad[i] := ASpec.Padding[i] * scale;
  gap := ASpec.ItemGap * scale;

  { A LINE WHOSE STYLE MAKES IT A BLOCK is measured as the block: a rich
    title's height is its tallest token's line, not its markup's [Batch 86] }
  if ASpec.Text <> '' then
    if ATextMeter <> nil then
      ATextMeter.MeasureLine(ASpec.Text, AFont.Name, AFont.SizeLogical,
        AFont.Weight, Result.TextW, Result.TextH)
    else
      AMeasurer.MeasureLine(ASpec.Text, AFont.Name, AFont.SizeLogical,
        AFont.Weight, Result.TextW, Result.TextH);
  Result.HasSub := ASpec.Subtext <> '';
  if Result.HasSub then
    if ASubMeter <> nil then
      ASubMeter.MeasureLine(ASpec.Subtext, ASubFont.Name, ASubFont.SizeLogical,
        ASubFont.Weight, Result.SubW, Result.SubH)
    else
      AMeasurer.MeasureLine(ASpec.Subtext, ASubFont.Name, ASubFont.SizeLogical,
        ASubFont.Weight, Result.SubW, Result.SubH);

  { The two stacked, with itemGap between -- install.ts:177. The subtext's own
    offset is the TITLE's height plus the gap, so an empty title still leaves
    its line: upstream adds the element either way and only skips the empty
    subtext, and a chart with `subtext` and no `text` is meant to hang where
    the second line would be. }
  gw := Max(Result.TextW, Result.SubW);
  gh := Result.TextH;
  if Result.HasSub then gh := gh + gap + Result.SubH;
  if (gw <= 0) or (gh <= 0) then Exit;

  { getLayoutRect on the merged option with the measured block as the size }
  raw := ASpec.Box;
  raw.Width := TyBoxRawNum(gw);
  raw.Height := TyBoxRawNum(gh);
  r := TyGetLayoutRect(raw, AContainer.Left, AContainer.Top,
    AContainer.Right - AContainer.Left, AContainer.Bottom - AContainer.Top,
    [pad[0], pad[1], pad[2], pad[3]]);
  gx := r.X;
  gy := r.Y;

  Result.Align := ASpec.Align;
  Result.VAlign := ASpec.VAlign;

  { AUTO ALIGNMENT ALSO MOVES THE BOX, install.ts:222-237, and only when it is
    auto. The box was solved for a left-anchored block; aligning the text
    centre or right without moving the anchor would draw it half or wholly
    outside its own frame. }
  if Result.Align = ttaAuto then
  begin
    word_ := ASpec.WordH;
    Result.Align := AlignOf(word_);
    if Result.Align = ttaAuto then Result.Align := ttaLeft;
    if Result.Align = ttaRight then
      gx := gx + r.W
    else if Result.Align = ttaCentre then
      gx := gx + r.W / 2;
  end;

  if Result.VAlign = ttvAuto then
  begin
    word_ := ASpec.WordV;
    Result.VAlign := VAlignOf(word_);
    if Result.VAlign = ttvBottom then
      gy := gy + r.H
    else if Result.VAlign = ttvMiddle then
      gy := gy + r.H / 2;
    if Result.VAlign = ttvAuto then Result.VAlign := ttvTop;
  end;

  Result.TextX := gx;
  Result.TextY := gy;
  Result.SubX := gx;
  Result.SubY := gy + (Result.TextH + gap);

  { THE FRAME is the block plus the padding, wherever the alignment left the
    anchor -- upstream's order: the group's own box (which the alignment
    moved to -w/2 or -w) less the padding, then placed at the group. The
    vertical half keeps the block whole: upstream aligns each line on its
    own for middle and bottom, which is not done here. }
  case Result.Align of
    ttaCentre: lx := -gw / 2;
    ttaRight: lx := -gw;
  else
    lx := 0;
  end;
  case Result.VAlign of
    ttvMiddle: ly := -gh / 2;
    ttvBottom: ly := -gh;
  else
    ly := 0;
  end;
  Result.FrameX := gx + (lx - pad[3]);
  Result.FrameY := gy + (ly - pad[0]);
  Result.FrameW := gw + pad[1] + pad[3];
  Result.FrameH := gh + pad[0] + pad[2];
  Result.Frame := TyRectF(Result.FrameX, Result.FrameY,
    Result.FrameX + Result.FrameW, Result.FrameY + Result.FrameH);

  Result.Valid := True;
end;

end.
