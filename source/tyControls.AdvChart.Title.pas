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
  end;

  TTyTitleSpec = record
    Show: Boolean;
    Text: string;
    Subtext: string;
    Box: TTyBoxSpec;
    { CSS order: top, right, bottom, left. Kept as four because `padding` takes
      the CSS short forms and collapsing them early would lose them. }
    Padding: array[0..3] of Double;
    ItemGap: Double;
    Align: TTyTitleAlign;
    VAlign: TTyTitleVAlign;
    { WHAT THE OPTION SAID, not what it solved to. The auto-align rules read the
      keyword rather than the number, so `left: 'center'` and `left: '50%'` --
      the same place -- align differently. That is upstream's, and it is why
      these are kept alongside the box rather than folded into it. }
    LeftWord, RightWord, TopWord, BottomWord: string;
    HasBackground: Boolean;
    BorderWidth: Double;
    BorderRadii: TTyCornerRadii;
  end;

  { Where the two lines go, in DEVICE px. Each is an ANCHOR plus the alignment
    to hang off it, which is how the painter's DrawText wants them. }
  TTyTitleLayout = record
    Valid: Boolean;
    HasSub: Boolean;
    { The background box, padding included. }
    Frame: TTyRectF;
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
  APPI: Integer): TTyTitleLayout;

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

{ THE KEYWORD SWITCH, layout.ts:350-367, and the ONE place that turns an edge
  word into a pinned edge.

  It runs after both edges have been resolved as numbers and REPLACES that
  answer, because `left: 'right'` does not mean `the left edge sits at 100%`
  -- which is what a percentage alone answers, and which puts the block
  entirely outside the container. It means `flush right`: the RIGHT edge is
  pinned and the left one is free.

  It consults `left` first and falls to `right` only when left is absent or
  zero, so `left: 'right'` is the idiomatic way to put a title on the right
  and `right: 10` on its own does NOT move it -- the default 'center' is
  still in `left` and wins the test.

  CALLED BY THE DEFAULT TOO. It used to be called only by the reader, with
  the default pinning its own box beside the word it was derived from; the
  second copy was then overwritten on every path that drew, and a mutant that
  broke it changed nothing. One authority, run twice. }
procedure ApplyEdgeWords(var ASpec: TTyTitleSpec);
var w: string;
begin
  w := ASpec.LeftWord;
  if w = '' then w := ASpec.RightWord;
  if (w = 'center') or (w = 'centre') or (w = 'middle') then
  begin
    ASpec.Box.Left := TyBoxCentre;
    ASpec.Box.Right := TyBoxAuto;
  end
  else if w = 'right' then
  begin
    ASpec.Box.Left := TyBoxAuto;
    ASpec.Box.Right := TyBoxPx(0);
  end;
  w := ASpec.TopWord;
  if w = '' then w := ASpec.BottomWord;
  if (w = 'middle') or (w = 'center') or (w = 'centre') then
  begin
    ASpec.Box.Top := TyBoxCentre;
    ASpec.Box.Bottom := TyBoxAuto;
  end
  else if w = 'bottom' then
  begin
    ASpec.Box.Top := TyBoxAuto;
    ASpec.Box.Bottom := TyBoxPx(0);
  end;
end;

function TyTitleSpecDefault: TTyTitleSpec;
var i: Integer;
begin
  Result.Show := True;
  Result.Text := '';
  Result.Subtext := '';
  Result.Box := TyBoxSpec;
  Result.Box.Top := TyBoxPx(cDefaultTop);
  for i := 0 to 3 do Result.Padding[i] := cDefaultPadding;
  Result.ItemGap := cDefaultItemGap;
  Result.Align := ttaAuto;
  Result.VAlign := ttvAuto;
  Result.LeftWord := 'center';
  Result.RightWord := '';
  Result.TopWord := '';
  Result.BottomWord := '';
  Result.HasBackground := False;
  Result.BorderWidth := 0;
  Result.BorderRadii := TyCornerRadii([]);
  ApplyEdgeWords(Result);
end;

function ParseFloatIn(const AText: string; out AValue: Double): Boolean;
var fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := TryStrToFloat(Trim(AText), AValue, fs);
end;

{ A box edge, plus the KEYWORD it was written as ('' when it was a number)
  and whether the option mentioned it at all.

  AN EXPLICIT null CLEARS IT rather than falling back to the default: that
  is how a chart says `not this edge, the other one`, and treating it as
  absent would leave the default `left: 'center'` in place and centre a
  title that asked to be flush right. }
function EdgeIn(ANode: TJSONObject; const AKey: string;
  const ADefault: TTyBoxValue; out AWord: string;
  out AGiven: Boolean): TTyBoxValue;
var
  d: TJSONData;
  s: string;
  v: Double;
begin
  Result := ADefault;
  AWord := '';
  AGiven := False;
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if d = nil then Exit;
  AGiven := True;
  if d.JSONType = jtNull then Exit(TyBoxAuto);
  if d.JSONType = jtNumber then
  begin
    { A ZERO IS FALSY UPSTREAM, and the auto-align rules test truthiness. So
      `left: 0` does not make the text left-aligned -- it falls through to
      `right`, and with neither set the text ends up left-aligned anyway by a
      different route. The word is left empty here to keep that distinction. }
    AWord := '';
    Exit(TyBoxPx(d.AsFloat));
  end;
  if d.JSONType <> jtString then Exit;
  s := Trim(d.AsString);
  if s = '' then Exit;
  AWord := s;
  if (s = 'center') or (s = 'centre') or (s = 'middle') then Exit(TyBoxCentre);
  if (s = 'left') or (s = 'top') then Exit(TyBoxPx(0));
  { 'right' and 'bottom' resolve to 100% here and are then OVERRIDDEN by the
    keyword switch in the caller. Kept faithful rather than short-circuited
    because the number is what a chart sees if it ever asks for the edge
    without the switch -- and because upstream computes it too. }
  if (s = 'right') or (s = 'bottom') then Exit(TyBoxPercent(100));
  if s[Length(s)] = '%' then
  begin
    if ParseFloatIn(Copy(s, 1, Length(s) - 1), v) then Exit(TyBoxPercent(v));
    AWord := '';
    Exit;
  end;
  if ParseFloatIn(s, v) then Exit(TyBoxPx(v));
  AWord := '';
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

function AlignOf(const AText: string): TTyTitleAlign;
begin
  if (AText = 'center') or (AText = 'centre') or (AText = 'middle') then
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
  w: string;
  given: Boolean;
begin
  Result := TyTitleSpecDefault;
  if AOption = nil then Exit;
  node := ObjOf(AOption.ComponentAt('title', AIndex));
  if node = nil then Exit;

  d := node.Find('show');
  if (d <> nil) and (d.JSONType = jtBoolean) then Result.Show := d.AsBoolean;
  Result.Text := StrIn(node, 'text');
  Result.Subtext := StrIn(node, 'subtext');

  Result.Box.Left := EdgeIn(node, 'left', Result.Box.Left, w, given);
  if given then Result.LeftWord := w;
  Result.Box.Right := EdgeIn(node, 'right', Result.Box.Right, w, given);
  Result.RightWord := w;
  Result.Box.Top := EdgeIn(node, 'top', Result.Box.Top, w, given);
  Result.TopWord := w;
  Result.Box.Bottom := EdgeIn(node, 'bottom', Result.Box.Bottom, w, given);
  Result.BottomWord := w;

  ApplyEdgeWords(Result);

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
  APPI: Integer): TTyTitleLayout;
var
  spec: TTyBoxSpec;
  box: TTyRectF;
  gw, gh, gap: Double;
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

  if ASpec.Text <> '' then
    AMeasurer.MeasureLine(ASpec.Text, AFont.Name, AFont.SizeLogical,
      AFont.Weight, Result.TextW, Result.TextH);
  Result.HasSub := ASpec.Subtext <> '';
  if Result.HasSub then
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

  spec := ASpec.Box;
  spec.Width := TyBoxPx(gw);
  spec.Height := TyBoxPx(gh);
  box := TySolveBox(spec, TyFixedContainer(AContainer),
    [pad[0], pad[1], pad[2], pad[3]]);
  if not TyRectFIsValid(box) then Exit;

  Result.Align := ASpec.Align;
  Result.VAlign := ASpec.VAlign;

  { AUTO ALIGNMENT ALSO MOVES THE BOX, install.ts:222-237, and only when it is
    auto. The box was solved for a left-anchored block; aligning the text
    centre or right without moving the anchor would draw it half or wholly
    outside its own frame. }
  if Result.Align = ttaAuto then
  begin
    word_ := ASpec.LeftWord;
    if word_ = '' then word_ := ASpec.RightWord;
    Result.Align := AlignOf(word_);
    if Result.Align = ttaAuto then Result.Align := ttaLeft;
    if Result.Align = ttaRight then
      box.Left := box.Left + TyRectFWidth(box)
    else if Result.Align = ttaCentre then
      box.Left := box.Left + TyRectFWidth(box) / 2;
  end;

  if Result.VAlign = ttvAuto then
  begin
    word_ := ASpec.TopWord;
    if word_ = '' then word_ := ASpec.BottomWord;
    Result.VAlign := VAlignOf(word_);
    if Result.VAlign = ttvBottom then
      box.Top := box.Top + TyRectFHeight(box)
    else if Result.VAlign = ttvMiddle then
      box.Top := box.Top + TyRectFHeight(box) / 2;
    if Result.VAlign = ttvAuto then Result.VAlign := ttvTop;
  end;

  Result.TextX := box.Left;
  Result.TextY := box.Top;
  Result.SubX := box.Left;
  Result.SubY := box.Top + Result.TextH + gap;

  { The frame is the BLOCK plus the padding, wherever the alignment left the
    anchor -- so it follows the text rather than staying where the box was
    solved. }
  case Result.Align of
    ttaCentre: Result.Frame := TyRectF(box.Left - gw / 2, 0, box.Left + gw / 2, 0);
    ttaRight: Result.Frame := TyRectF(box.Left - gw, 0, box.Left, 0);
  else
    Result.Frame := TyRectF(box.Left, 0, box.Left + gw, 0);
  end;
  case Result.VAlign of
    ttvMiddle:
      begin
        Result.Frame.Top := box.Top - gh / 2;
        Result.Frame.Bottom := box.Top + gh / 2;
      end;
    ttvBottom:
      begin
        Result.Frame.Top := box.Top - gh;
        Result.Frame.Bottom := box.Top;
      end;
  else
    Result.Frame.Top := box.Top;
    Result.Frame.Bottom := box.Top + gh;
  end;
  Result.Frame.Left := Result.Frame.Left - pad[3];
  Result.Frame.Right := Result.Frame.Right + pad[1];
  Result.Frame.Top := Result.Frame.Top - pad[0];
  Result.Frame.Bottom := Result.Frame.Bottom + pad[2];

  Result.Valid := True;
end;

end.
