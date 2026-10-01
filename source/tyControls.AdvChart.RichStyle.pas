unit tyControls.AdvChart.RichStyle;
{$mode objfpc}{$H+}
{ FROM AN ECHARTS TEXT OPTION TO ZRENDER'S TEXT BLOCK, and the block laid
  out where a site hangs it.

  AdvChart.RichText is zrender: it takes the styles zrender would receive and
  answers the pieces it would paint. This unit is the half in front of it --
  ECharts' label/labelStyle.ts setTextStyleCommon / setTokenTextStyle, which
  turn a label model (and its parents) into those styles -- and the half
  behind it every site shares: finishing a style with the font the site
  draws in, laying it out at the site's scale, the box it occupies, and a
  measurer that answers that box so a site's own layout (an axis' interval,
  a legend's rows, a title's two lines) sizes the block and not the markup.

  THE RESOLUTION, as upstream does it:
    - the rich names are the union of `rich` keys over the model and every
      parent model, and each rich style cascades over the same chain;
    - a rich style's font parts and text shadow are its own, else the plain
      label's (richInheritPlainLabel, on unless written false), else the
      global textStyle's -- here: else the block's font (which is the plain
      label's over the root's over the skin's), or the global font when
      inheritance is off;
    - align, lineHeight, width, height, verticalAlign (baseline) and
      ellipsis are a style's own only; padding, the border, the radius and
      the background are its own only too, and the block's are dropped when
      the site disables the box (a title);
    - a colour of 'inherit' is the site's inherit colour; a FREE text's
      colour falls back to the root textStyle's, then to the inherit colour;
      an attached label's never does.

  THE SITE finishes the style (TyRtFinish) once it knows the font it draws
  the block in and its inherit colour, and lays it out (TyRtLay) about the
  point it hangs the text from. The plain caption -- one run, no box -- is
  what a text keeps when nothing here makes it Needed.

  PURE: SysUtils, Math, fpjson and the AdvChart units. [Batch 86] }
interface
uses
  SysUtils, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Paint;

type
  TTyRtResolveOpt = record
    { hung on a host (a series or marker label): no root colour, and the
      host's default ink }
    Attached: Boolean;
    { the title's: the block's padding, border and background are dropped }
    DisableBox: Boolean;
  end;

function TyRtResolveOpt(AAttached: Boolean; ADisableBox: Boolean = False): TTyRtResolveOpt;

{ Nothing written at the root; the font as given. }
function TyRtGlobalOf(ARoot: TJSONObject; const AFontFamily: string;
  AFontSizeLogical, AFontWeight: Integer): TTyRtGlobal;

{ WHETHER A LABEL NODE ASKS FOR THE BLOCK AT ALL: a `rich`, a box, a size, a
  line height, an overflow or a text shadow. The cheap question a site asks
  before paying for the resolution. }
function TyRtNodeWantsBlock(ANode: TJSONObject): Boolean;

{ THE STYLES FROM A MODEL CHAIN, the most specific node first (an item's
  label, its series' label, ...). Nil nodes are skipped. The block's font is
  NOT set -- the site's is final and comes in through TyRtFinish. }
function TyRtResolve(const AChain: array of TJSONObject;
  const AGlobal: TTyRtGlobal; const AOpt: TTyRtResolveOpt): TTyRtBlockStyle;

{ Whether a resolved style needs the block: rich, or anything the one-run
  caption cannot draw -- a box, a size, a line height, a text shadow. A site
  that overrides part of the style asks again. }
function TyRtNeedsBlock(const ABlock: TTyRtBlockStyle): Boolean;

{ THE STYLE AS THE SITE DRAWS IT: the block in AFamily / ASizeLogical /
  AWeight, each rich style's missing font parts from that (or from the
  global font when it does not inherit), and the inherit colours bound to
  AInherit -- or dropped where the site has none. }
procedure TyRtFinish(var ABlock: TTyRtBlockStyle; const AFamily: string;
  ASizeLogical, AWeight: Integer; const AGlobal: TTyRtGlobal;
  AHasInherit: Boolean; AInherit: TTyChartColor);

{ What the host hands the text: its ink, its halo and its alignment. }
function TyRtDefaultOf(AHasFill: Boolean; AFill: TTyChartColor;
  AHasStroke: Boolean; AStroke: TTyChartColor; AAutoStroke: Boolean;
  AH: TTyTextAnchorH; AV: TTyTextAnchorV): TTyRtDefault;

{ THE PIECES, laid out about (0, 0) in CSS px. AMeasurer measures in device
  px, AScale of them to a CSS px; the style's own numbers (padding, width,
  radius...) are CSS px as written. }
function TyRtLay(const AText: string; const ABlock: TTyRtBlockStyle;
  const ADefault: TTyRtDefault; AScale: Double;
  const AMeasurer: ITyTextMeasurer): TTyRtPieceArray;

{ THE BOX THE PIECES OCCUPY in their own frame: zrender's Text
  getBoundingRect, the union of every child -- an undrawn rect included, a
  stroked rect grown by its stroke as painted, a text by its content box
  grown by a stroke a style gave it (not the host's auto stroke). W < 0 when
  there is nothing. }
function TyRtBounds(const APieces: TTyRtPieceArray): TTyXYWH;

{ The same box hung at (AX, AY), turned and scaled: its axis-aligned bounds
  in device px -- what the pointer and the label layout see. }
function TyRtDeviceBox(const APieces: TTyRtPieceArray;
  AX, AY, ARotationRad, AScale: Double): TTyRectF;

{ THE SAME PIECES IN ANOTHER INK: every text whose fill (stroke) came from
  the host's default takes AFill (AStroke, AStrokeWidth; none when
  AStrokeWidth <= 0). A hover's ink, or the skin's for a free text. }
function TyRtReink(const APieces: TTyRtPieceArray; AFill: TTyChartColor;
  AReStroke: Boolean; AStroke: TTyChartColor; AStrokeWidth: Double): TTyRtPieceArray;

{ A MEASURER ANSWERING THE BLOCK'S BOX: for any text and font it is asked
  about, the size TyRtBounds gives the text laid out in ABlock over that
  font, in device px. A site whose layout measures its text (an axis, a
  legend, a title) hands this in and lays out the block, not the markup. }
function TyRtBlockMeasurer(const AInner: ITyTextMeasurer;
  const ABlock: TTyRtBlockStyle; const AGlobal: TTyRtGlobal;
  AScale: Double): ITyTextMeasurer;

type
  { WHERE THE BOX SITS, not only how big it is: the block measurer answers
    this too. The box of AText hung by AH / AV about (0, 0), in device px.
    A block's box can overhang its anchor -- a stroked rect grows by half its
    stroke on every side -- and a site that sets the box beside something
    (a legend's icon, whose group swallows the overhang on the icon's side)
    needs where it starts, not only its size. }
  ITyTextBoxMeasurer = interface
    ['{7B1D5E63-2C4A-4F08-A9E3-5D0C61B2F84A}']
    function MeasureBox(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; AH: TTyTextAnchorH;
      AV: TTyTextAnchorV): TTyRectF;
  end;

implementation

uses tyControls.FontUnits, tyControls.AdvChart.Option,
     tyControls.AdvChart.Color, tyControls.AdvChart.RichText;

function TyRtResolveOpt(AAttached: Boolean; ADisableBox: Boolean): TTyRtResolveOpt;
begin
  Result.Attached := AAttached;
  Result.DisableBox := ADisableBox;
end;

{ ---- reading values ---- }

function JNull(A: TJSONData): Boolean; inline;
begin
  Result := (A = nil) or (A.JSONType = jtNull);
end;

{ Model.get over the chain: the first node whose value is not null }
function Get(const AChain: array of TJSONObject; const AKey: string): TJSONData;
var i: Integer;
begin
  for i := 0 to High(AChain) do
    if AChain[i] <> nil then
    begin
      Result := AChain[i].Find(AKey);
      if not JNull(Result) then Exit;
    end;
  Result := nil;
end;

function NumOf(A: TJSONData; out AV: Double): Boolean;
begin
  Result := (A <> nil) and (A.JSONType = jtNumber) and not IsNan(A.AsFloat)
    and not IsInfinite(A.AsFloat);
  if Result then AV := A.AsFloat else AV := 0;
end;

function StrOf(A: TJSONData): string;
begin
  if (A <> nil) and (A.JSONType = jtString) then Result := A.AsString
  else Result := '';
end;

type
  TColourRead = (crNone, crColour, crNone_, crInherit);

{ a colour as a style holds it: a colour, 'none'/'transparent' (set and
  drawing nothing), 'inherit'/'auto', or not a colour at all }
function ColourRead(A: TJSONData; out AC: TTyChartColor): TColourRead;
var s: string;
begin
  AC := 0;
  Result := crNone;
  if (A = nil) or (A.JSONType <> jtString) then Exit;
  s := A.AsString;
  if s = '' then Exit;
  if (s = 'inherit') or (s = 'auto') then Exit(crInherit);
  if (s = 'none') or (s = 'transparent') then Exit(crNone_);
  if TyTryParseChartColor(s, AC) then Result := crColour
  else Result := crNone_;
end;

{ zrender's parseFontSize and the SSR measure's reading of it: a number is
  px, '14' and '14px' are 14, anything else 12 }
function FontPxOf(A: TJSONData): Double;
begin
  Result := TyFontPxOf(TyOptFontSize(A, TyFontSizeFromPx(12)));
end;

procedure SpreadPadding(A: TJSONData; var S: TTyRtStyle);
var
  v: array[0..3] of Double;
  n, k: Integer;
  x: Double;
begin
  if A = nil then Exit;
  if NumOf(A, x) then
  begin
    for k := 0 to 3 do S.Padding[k] := x;
    S.HasPadding := True;
    Exit;
  end;
  if A.JSONType <> jtArray then Exit;
  n := A.Count;
  if n = 0 then Exit;
  for k := 0 to 3 do v[k] := 0;
  for k := 0 to Min(n, 4) - 1 do NumOf(A.Items[k], v[k]);
  { normalizeCssArray: [a] -> a four times, [v, h], [t, h, b] }
  case n of
    1: begin v[1] := v[0]; v[2] := v[0]; v[3] := v[0]; end;
    2: begin v[2] := v[0]; v[3] := v[1]; end;
    3: v[3] := v[1];
  end;
  for k := 0 to 3 do S.Padding[k] := v[k];
  S.HasPadding := True;
end;

procedure SpreadRadius(A: TJSONData; var S: TTyRtStyle);
var
  v: array[0..3] of Double;
  n, k: Integer;
  x: Double;
begin
  if A = nil then Exit;
  if NumOf(A, x) then
  begin
    for k := 0 to 3 do S.Radius[k] := x;
    Exit;
  end;
  if A.JSONType <> jtArray then Exit;
  n := A.Count;
  if n = 0 then Exit;
  for k := 0 to 3 do v[k] := 0;
  for k := 0 to Min(n, 4) - 1 do NumOf(A.Items[k], v[k]);
  { roundRect.ts: the CSS spread of fewer than four }
  case n of
    1: begin v[1] := v[0]; v[2] := v[0]; v[3] := v[0]; end;
    2: begin v[2] := v[0]; v[3] := v[1]; end;
    3: v[3] := v[1];
  end;
  for k := 0 to 3 do S.Radius[k] := v[k];
end;

function AlignOfWord(const S: string): TTyRtAlign;
begin
  if S = '' then Exit(rtaNone);
  if (S = 'center') or (S = 'middle') then Result := rtaCenter
  else if S = 'right' then Result := rtaRight
  else Result := rtaLeft;
end;

function VAlignOfWord(const S: string): TTyRtVAlign;
begin
  if S = '' then Exit(rtvNone);
  if (S = 'middle') or (S = 'center') then Result := rtvMiddle
  else if S = 'bottom' then Result := rtvBottom
  else Result := rtvTop;
end;

function TyRtGlobalOf(ARoot: TJSONObject; const AFontFamily: string;
  AFontSizeLogical, AFontWeight: Integer): TTyRtGlobal;
var
  ts: TJSONObject;
  d: TJSONData;
  c: TTyChartColor;
  x: Double;
begin
  Result := Default(TTyRtGlobal);
  Result.FontFamily := AFontFamily;
  Result.FontSizeLogical := AFontSizeLogical;
  Result.FontWeight := AFontWeight;
  if ARoot = nil then Exit;
  d := ARoot.Find('richInheritPlainLabel');
  if (d <> nil) and (d.JSONType = jtBoolean) then
    Result.InheritPlainOff := not d.AsBoolean;
  d := ARoot.Find('textStyle');
  if not (d is TJSONObject) then Exit;
  ts := TJSONObject(d);
  if ColourRead(ts.Find('color'), c) = crColour then
  begin
    Result.HasColour := True;
    Result.Colour := c;
  end;
  case ColourRead(ts.Find('textBorderColor'), c) of
    crColour: begin Result.HasStroke := True; Result.Stroke := c; end;
    crNone_: begin Result.HasStroke := True; Result.StrokeNone := True; end;
  end;
  if NumOf(ts.Find('textBorderWidth'), x) then
  begin
    Result.HasLineWidth := True;
    Result.LineWidth := x;
  end;
  if NumOf(ts.Find('opacity'), x) then
  begin
    Result.HasOpacity := True;
    Result.Opacity := x;
  end;
  if ColourRead(ts.Find('textShadowColor'), c) = crColour then
  begin
    Result.HasShadowColor := True;
    Result.ShadowColor := c;
  end;
  NumOf(ts.Find('textShadowBlur'), Result.ShadowBlur);
  NumOf(ts.Find('textShadowOffsetX'), Result.ShadowOffsetX);
  NumOf(ts.Find('textShadowOffsetY'), Result.ShadowOffsetY);
end;

function TyRtNodeWantsBlock(ANode: TJSONObject): Boolean;
const
  cKeys: array[0..13] of string = ('rich', 'padding', 'backgroundColor',
    'borderColor', 'borderWidth', 'width', 'height', 'lineHeight', 'overflow',
    'lineOverflow', 'textShadowBlur', 'textShadowOffsetX', 'textShadowOffsetY',
    'borderRadius');
var k: Integer;
begin
  Result := False;
  if ANode = nil then Exit;
  for k := 0 to High(cKeys) do
    if not JNull(ANode.Find(cKeys[k])) then Exit(True);
end;

{ ---- setTokenTextStyle ---- }

{ AOwn: the style's own chain (a rich name's cascade, or the label chain
  for the block); APlain: the plain label's chain, for a rich style that
  inherits; nil for the block. }
procedure TokenStyle(const AOwn: array of TJSONObject;
  const APlain: array of TJSONObject; AHasPlain: Boolean; AInherit: Boolean;
  const AGlobal: TTyRtGlobal; const AOpt: TTyRtResolveOpt; AIsBlock: Boolean;
  var S: TTyRtStyle);
var
  d: TJSONData;
  c: TTyChartColor;
  x: Double;
  s_: string;
  plainToo: Boolean;
  fs: TFormatSettings;

  { own ?? plain ?? global, or own ?? global }
  function WithGlobal(const AKey: string): TJSONData;
  begin
    Result := Get(AOwn, AKey);
    if (Result = nil) and plainToo then Result := Get(APlain, AKey);
  end;

begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  plainToo := AHasPlain and AInherit;
  { the fill: own, 'inherit' the site's; a free text's falls to the root
    colour, then (normal state) to the inherit colour }
  case ColourRead(Get(AOwn, 'color'), c) of
    crColour: begin S.HasFill := True; S.Fill := c; end;
    crNone_: begin S.HasFill := True; S.FillNone := True; end;
    crInherit: S.FillInherit := True;
  end;
  if not AOpt.Attached and not S.HasFill and not S.FillInherit then
  begin
    if AGlobal.HasColour then
    begin
      S.HasFill := True;
      S.Fill := AGlobal.Colour;
    end
    else
      S.FillInherit := True;
  end;
  case ColourRead(Get(AOwn, 'textBorderColor'), c) of
    crColour: begin S.HasStroke := True; S.Stroke := c; end;
    crNone_: begin S.HasStroke := True; S.StrokeNone := True; end;
    crInherit: S.StrokeInherit := True;
  end;
  if not AOpt.Attached and not S.HasStroke and not S.StrokeInherit
    and AGlobal.HasStroke then
  begin
    S.HasStroke := True;
    S.StrokeNone := AGlobal.StrokeNone;
    S.Stroke := AGlobal.Stroke;
  end;
  if NumOf(Get(AOwn, 'textBorderWidth'), x) then
  begin
    S.HasLineWidth := True;
    S.LineWidth := x;
  end
  else if AGlobal.HasLineWidth then
  begin
    S.HasLineWidth := True;
    S.LineWidth := AGlobal.LineWidth;
  end;
  if NumOf(Get(AOwn, 'opacity'), x) then
  begin
    S.HasOpacity := True;
    S.Opacity := x;
  end
  else if AGlobal.HasOpacity then
  begin
    S.HasOpacity := True;
    S.Opacity := AGlobal.Opacity;
  end;

  { TEXT_PROPS_WITH_GLOBAL: the font parts (a block's are the site's) and
    the text shadow }
  if not AIsBlock then
  begin
    d := Get(AOwn, 'fontSize');
    if d <> nil then
    begin
      S.OwnFontSize := True;
      S.FontSizePx := FontPxOf(d);
    end;
    d := Get(AOwn, 'fontWeight');
    if d <> nil then
    begin
      S.OwnFontWeight := True;
      S.FontWeight := TyFontWeightOf(d, 400);
    end;
    d := Get(AOwn, 'fontFamily');
    if StrOf(d) <> '' then
    begin
      S.OwnFontFamily := True;
      S.FontFamily := StrOf(d);
    end;
    s_ := StrOf(Get(AOwn, 'fontStyle'));
    S.FontItalic := (s_ = 'italic') or (s_ = 'oblique');
  end;
  if ColourRead(WithGlobal('textShadowColor'), c) = crColour then
  begin
    S.HasShadowColor := True;
    S.ShadowColor := c;
  end
  else if AGlobal.HasShadowColor then
  begin
    S.HasShadowColor := True;
    S.ShadowColor := AGlobal.ShadowColor;
  end;
  if not NumOf(WithGlobal('textShadowBlur'), S.ShadowBlur) then
    S.ShadowBlur := AGlobal.ShadowBlur;
  if not NumOf(WithGlobal('textShadowOffsetX'), S.ShadowOffsetX) then
    S.ShadowOffsetX := AGlobal.ShadowOffsetX;
  if not NumOf(WithGlobal('textShadowOffsetY'), S.ShadowOffsetY) then
    S.ShadowOffsetY := AGlobal.ShadowOffsetY;

  { TEXT_PROPS_SELF }
  S.Align := AlignOfWord(StrOf(Get(AOwn, 'align')));
  d := Get(AOwn, 'verticalAlign');
  if d = nil then d := Get(AOwn, 'baseline');
  S.VAlign := VAlignOfWord(StrOf(d));
  if NumOf(Get(AOwn, 'lineHeight'), x) then
  begin
    S.HasLineHeight := True;
    S.LineHeight := x;
  end;
  d := Get(AOwn, 'width');
  if NumOf(d, x) then
  begin
    S.WidthKind := rtwNumber;
    S.Width := x;
  end
  else if (d <> nil) and (d.JSONType = jtString) then
  begin
    s_ := Trim(d.AsString);
    if s_ = 'auto' then S.WidthKind := rtwAuto
    else if (s_ <> '') and (s_[Length(s_)] = '%')
      and TryStrToFloat(Copy(s_, 1, Length(s_) - 1), x, fs) then
    begin
      S.WidthKind := rtwPercent;
      S.Width := x;
    end;
  end;
  if NumOf(Get(AOwn, 'height'), x) then
  begin
    S.HasHeight := True;
    S.Height := x;
  end;
  d := Get(AOwn, 'ellipsis');
  if (d <> nil) and (d.JSONType = jtString) then
  begin
    S.HasEllipsis := True;
    S.Ellipsis := d.AsString;
  end;

  { TEXT_PROPS_BOX, never the block's when the site disables the box }
  if not (AIsBlock and AOpt.DisableBox) then
  begin
    SpreadPadding(Get(AOwn, 'padding'), S);
    if NumOf(Get(AOwn, 'borderWidth'), x) then S.BorderWidth := x;
    SpreadRadius(Get(AOwn, 'borderRadius'), S);
    case ColourRead(Get(AOwn, 'backgroundColor'), c) of
      crColour: begin S.HasBackground := True; S.Background := c; end;
      crInherit: S.BackgroundInherit := True;
    end;
    case ColourRead(Get(AOwn, 'borderColor'), c) of
      crColour: begin S.HasBorderColor := True; S.BorderColor := c; end;
      crInherit: S.BorderColorInherit := True;
    end;
  end;
end;

function TyRtResolve(const AChain: array of TJSONObject;
  const AGlobal: TTyRtGlobal; const AOpt: TTyRtResolveOpt): TTyRtBlockStyle;
var
  i, k, n: Integer;
  d, rd: TJSONData;
  names: array of string;
  own: array of TJSONObject;
  found: Boolean;
  s_: string;
begin
  Result := Default(TTyRtBlockStyle);
  Result.Style := TyRtStyleDefault;
  { the rich names: the union over the chain, the most specific first }
  names := nil;
  for i := 0 to High(AChain) do
  begin
    if AChain[i] = nil then Continue;
    rd := AChain[i].Find('rich');
    if JNull(rd) then Continue;
    if (rd.JSONType = jtBoolean) and not rd.AsBoolean then Continue;
    Result.IsRich := True;
    if rd.JSONType <> jtObject then Continue;
    for k := 0 to rd.Count - 1 do
    begin
      found := False;
      for n := 0 to High(names) do
        if names[n] = TJSONObject(rd).Names[k] then found := True;
      if not found then
      begin
        SetLength(names, Length(names) + 1);
        names[High(names)] := TJSONObject(rd).Names[k];
      end;
    end;
  end;
  { richInheritPlainLabel: the chain's, else the root's; unset is on }
  d := Get(AChain, 'richInheritPlainLabel');
  if (d <> nil) and (d.JSONType = jtBoolean) then Result.InheritPlain := d.AsBoolean
  else Result.InheritPlain := not AGlobal.InheritPlainOff;

  SetLength(Result.Rich, Length(names));
  for n := 0 to High(names) do
  begin
    { the name's cascade: rich[name] on every node of the chain }
    SetLength(own, 0);
    for i := 0 to High(AChain) do
    begin
      if AChain[i] = nil then Continue;
      rd := AChain[i].Find('rich');
      if not (rd is TJSONObject) then Continue;
      d := TJSONObject(rd).Find(names[n]);
      if not (d is TJSONObject) then Continue;
      SetLength(own, Length(own) + 1);
      own[High(own)] := TJSONObject(d);
    end;
    Result.Rich[n].Name := names[n];
    Result.Rich[n].Style := Default(TTyRtStyle);
    TokenStyle(own, AChain, True, Result.InheritPlain, AGlobal, AOpt, False,
      Result.Rich[n].Style);
  end;

  { the block }
  TokenStyle(AChain, AChain, False, False, AGlobal, AOpt, True, Result.Style);
  s_ := StrOf(Get(AChain, 'overflow'));
  if s_ = 'truncate' then Result.Style.Overflow := rtoTruncate
  else if s_ = 'break' then Result.Style.Overflow := rtoBreak
  else if s_ = 'breakAll' then Result.Style.Overflow := rtoBreakAll;
  Result.Style.LineOverflowTruncate := StrOf(Get(AChain, 'lineOverflow')) = 'truncate';

  Result.Needed := TyRtNeedsBlock(Result);
end;

function TyRtNeedsBlock(const ABlock: TTyRtBlockStyle): Boolean;
var bs: TTyRtStyle;
begin
  { A BLOCK IS NEEDED for what the one-run caption cannot draw. An overflow
    with no width to overflow (a lineOverflow with no height) changes
    nothing in zrender either, so it alone keeps the caption. }
  bs := ABlock.Style;
  Result := ABlock.IsRich or bs.HasPadding or bs.HasBackground
    or bs.BackgroundInherit
    or ((bs.BorderWidth > 0) and (bs.HasBorderColor or bs.BorderColorInherit))
    or (bs.WidthKind <> rtwNone) or bs.HasHeight or bs.HasLineHeight
    or (bs.ShadowBlur > 0) or (bs.ShadowOffsetX <> 0) or (bs.ShadowOffsetY <> 0);
end;

{ ---- finishing ---- }

procedure Bind(var S: TTyRtStyle; AHas: Boolean; AC: TTyChartColor);
begin
  if S.FillInherit and not S.HasFill and AHas then
  begin
    S.HasFill := True;
    S.Fill := AC;
  end;
  if S.StrokeInherit and not S.HasStroke and AHas then
  begin
    S.HasStroke := True;
    S.Stroke := AC;
  end;
  if S.BackgroundInherit and not S.HasBackground and AHas then
  begin
    S.HasBackground := True;
    S.Background := AC;
  end;
  if S.BorderColorInherit and not S.HasBorderColor and AHas then
  begin
    S.HasBorderColor := True;
    S.BorderColor := AC;
  end;
  S.FillInherit := False;
  S.StrokeInherit := False;
  S.BackgroundInherit := False;
  S.BorderColorInherit := False;
end;

function PxOfLogical(ASizeLogical: Integer): Double;
begin
  if ASizeLogical <= 0 then Exit(12);
  Result := TyFontPxOf(ASizeLogical);
end;

procedure TyRtFinish(var ABlock: TTyRtBlockStyle; const AFamily: string;
  ASizeLogical, AWeight: Integer; const AGlobal: TTyRtGlobal;
  AHasInherit: Boolean; AInherit: TTyChartColor);
var
  k, gw: Integer;
  bpx, gpx: Double;
  s: TTyRtStyle;
  gfam: string;
begin
  bpx := PxOfLogical(ASizeLogical);
  { a skin that names no weight means the normal one }
  if AWeight <= 0 then AWeight := 400;
  { A GLOBAL THAT KNOWS NO FONT (a site whose root side was read without the
    skin's) is the block's }
  gfam := AGlobal.FontFamily;
  if AGlobal.FontSizeLogical > 0 then gpx := PxOfLogical(AGlobal.FontSizeLogical)
  else
  begin
    gpx := bpx;
    gfam := AFamily;
  end;
  gw := AGlobal.FontWeight;
  if gw <= 0 then gw := 400;
  ABlock.Style.FontFamily := AFamily;
  ABlock.Style.FontSizePx := bpx;
  ABlock.Style.FontWeight := AWeight;
  Bind(ABlock.Style, AHasInherit, AInherit);
  { a dynamic array is shared by every copy of the record: the rich styles
    are made this copy's own before they are written }
  ABlock.Rich := Copy(ABlock.Rich);
  for k := 0 to High(ABlock.Rich) do
  begin
    s := ABlock.Rich[k].Style;
    if not s.OwnFontFamily then
      if ABlock.InheritPlain then s.FontFamily := AFamily
      else s.FontFamily := gfam;
    if not s.OwnFontSize then
      if ABlock.InheritPlain then s.FontSizePx := bpx
      else s.FontSizePx := gpx;
    if not s.OwnFontWeight then
      if ABlock.InheritPlain then s.FontWeight := AWeight
      else s.FontWeight := gw;
    if s.FontSizePx <= 0 then s.FontSizePx := bpx;
    Bind(s, AHasInherit, AInherit);
    ABlock.Rich[k].Style := s;
  end;
end;

function TyRtDefaultOf(AHasFill: Boolean; AFill: TTyChartColor;
  AHasStroke: Boolean; AStroke: TTyChartColor; AAutoStroke: Boolean;
  AH: TTyTextAnchorH; AV: TTyTextAnchorV): TTyRtDefault;
begin
  Result := Default(TTyRtDefault);
  Result.HasFill := AHasFill;
  Result.Fill := AFill;
  Result.HasStroke := AHasStroke;
  Result.Stroke := AStroke;
  Result.AutoStroke := AAutoStroke;
  case AH of
    tahCentre: Result.Align := rtaCenter;
    tahRight: Result.Align := rtaRight;
  else
    Result.Align := rtaLeft;
  end;
  case AV of
    tavMiddle: Result.VAlign := rtvMiddle;
    tavBottom: Result.VAlign := rtvBottom;
  else
    Result.VAlign := rtvTop;
  end;
end;

{ ---- laying out ---- }

type
  { device px in, CSS px out }
  TScaledMeasurer = class(TInterfacedObject, ITyTextMeasurer)
  private
    FInner: ITyTextMeasurer;
    FScale: Double;
  public
    constructor Create(const AInner: ITyTextMeasurer; AScale: Double);
    procedure MeasureLine(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
    function WrapToWidth(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
  end;

constructor TScaledMeasurer.Create(const AInner: ITyTextMeasurer; AScale: Double);
begin
  inherited Create;
  FInner := AInner;
  FScale := AScale;
end;

procedure TScaledMeasurer.MeasureLine(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
begin
  FInner.MeasureLine(AText, AFontName, AFontSizeLogical, AWeight, AW, AH);
  AW := AW / FScale;
  AH := AH / FScale;
end;

function TScaledMeasurer.WrapToWidth(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
begin
  Result := FInner.WrapToWidth(AText, AFontName, AFontSizeLogical, AWeight,
    AMaxWidth * FScale);
end;

function TyRtLay(const AText: string; const ABlock: TTyRtBlockStyle;
  const ADefault: TTyRtDefault; AScale: Double;
  const AMeasurer: ITyTextMeasurer): TTyRtPieceArray;
var m: ITyTextMeasurer;
begin
  Result := nil;
  if AMeasurer = nil then Exit;
  if (AScale > 0) and (Abs(AScale - 1) > 1e-12) then
    m := TScaledMeasurer.Create(AMeasurer, AScale)
  else
    m := AMeasurer;
  Result := TyRtLayout(AText, ABlock.Style, ABlock.Rich, ABlock.IsRich, ADefault,
    0, 0, m).Pieces;
end;

function AdjustX(AX, AW: Double; AAlign: TTyRtAlign): Double;
begin
  case AAlign of
    rtaRight: Result := AX - AW;
    rtaCenter: Result := AX - AW / 2;
  else
    Result := AX;
  end;
end;

function TyRtBounds(const APieces: TTyRtPieceArray): TTyXYWH;
var
  i: Integer;
  x0, y0, x1, y1, px, py, pw, ph, g: Double;
  any: Boolean;
begin
  any := False;
  x0 := 0; y0 := 0; x1 := 0; y1 := 0;
  for i := 0 to High(APieces) do
  begin
    if APieces[i].Kind = rpkRect then
    begin
      px := APieces[i].X;
      py := APieces[i].Y;
      pw := APieces[i].W;
      ph := APieces[i].H;
      if pw < 0 then begin px := px + pw; pw := -pw; end;
      if ph < 0 then begin py := py + ph; ph := -ph; end;
      { Path.getBoundingRect: a stroke grows the box by its width. The
        floor of four it gives an unfilled path is strokeContainThreshold,
        which zrender sets to 0 on a text's box rect (Text.ts:952) }
      if APieces[i].HasStroke and (APieces[i].LineWidth > 0) then
      begin
        g := APieces[i].LineWidth;
        px := px - g / 2;
        py := py - g / 2;
        pw := pw + g;
        ph := ph + g;
      end;
    end
    else
    begin
      pw := APieces[i].W;
      ph := APieces[i].H;
      px := AdjustX(APieces[i].X, pw, APieces[i].TextAlign);
      py := APieces[i].Y - ph / 2;
      { tSpanCreateBoundingRect2: a stroke the style gave grows the TSpan's
        box by its width; the auto stroke is left out (Text.ts:656-676, 885) }
      if APieces[i].HasStroke and not APieces[i].DefaultStroke
        and (APieces[i].LineWidth > 0) then
      begin
        g := APieces[i].LineWidth;
        px := px - g / 2;
        py := py - g / 2;
        pw := pw + g;
        ph := ph + g;
      end;
    end;
    if not any then
    begin
      x0 := px; y0 := py; x1 := px + pw; y1 := py + ph;
      any := True;
    end
    else
    begin
      x0 := Min(x0, px); y0 := Min(y0, py);
      x1 := Max(x1, px + pw); y1 := Max(y1, py + ph);
    end;
  end;
  if not any then Exit(TyXYWH(0, 0, -1, -1));
  Result := TyXYWH(x0, y0, x1 - x0, y1 - y0);
end;

function TyRtDeviceBox(const APieces: TTyRtPieceArray;
  AX, AY, ARotationRad, AScale: Double): TTyRectF;
var
  b: TTyXYWH;
  gx, gy: array[0..3] of Double;
  k: Integer;
begin
  b := TyRtBounds(APieces);
  if b.W < 0 then Exit(TyRectF(AX, AY, AX, AY));
  TyRtPoint(AX, AY, ARotationRad, AScale, b.X, b.Y, gx[0], gy[0]);
  TyRtPoint(AX, AY, ARotationRad, AScale, b.X + b.W, b.Y, gx[1], gy[1]);
  TyRtPoint(AX, AY, ARotationRad, AScale, b.X + b.W, b.Y + b.H, gx[2], gy[2]);
  TyRtPoint(AX, AY, ARotationRad, AScale, b.X, b.Y + b.H, gx[3], gy[3]);
  Result := TyRectF(gx[0], gy[0], gx[0], gy[0]);
  for k := 1 to 3 do
  begin
    Result.Left := Min(Result.Left, gx[k]);
    Result.Top := Min(Result.Top, gy[k]);
    Result.Right := Max(Result.Right, gx[k]);
    Result.Bottom := Max(Result.Bottom, gy[k]);
  end;
end;

function TyRtReink(const APieces: TTyRtPieceArray; AFill: TTyChartColor;
  AReStroke: Boolean; AStroke: TTyChartColor; AStrokeWidth: Double): TTyRtPieceArray;
var i: Integer;
begin
  Result := Copy(APieces);
  for i := 0 to High(Result) do
  begin
    if Result[i].Kind <> rpkText then Continue;
    if Result[i].DefaultFill then
    begin
      Result[i].HasFill := True;
      Result[i].Fill := AFill;
    end;
    if AReStroke and Result[i].DefaultStroke then
    begin
      Result[i].HasStroke := AStrokeWidth > 0;
      Result[i].Stroke := AStroke;
      Result[i].LineWidth := AStrokeWidth;
    end;
  end;
end;

type
  TBlockMeasurer = class(TInterfacedObject, ITyTextMeasurer, ITyTextBoxMeasurer)
  private
    FInner: ITyTextMeasurer;
    FBlock: TTyRtBlockStyle;
    FGlobal: TTyRtGlobal;
    FScale: Double;
    function Bounds(const AText, AFontName: string; AFontSizeLogical,
      AWeight: Integer; AH: TTyTextAnchorH; AV: TTyTextAnchorV): TTyXYWH;
  public
    function MeasureBox(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; AH: TTyTextAnchorH;
      AV: TTyTextAnchorV): TTyRectF;
    constructor Create(const AInner: ITyTextMeasurer; const ABlock: TTyRtBlockStyle;
      const AGlobal: TTyRtGlobal; AScale: Double);
    procedure MeasureLine(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
    function WrapToWidth(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
  end;

constructor TBlockMeasurer.Create(const AInner: ITyTextMeasurer;
  const ABlock: TTyRtBlockStyle; const AGlobal: TTyRtGlobal; AScale: Double);
begin
  inherited Create;
  FInner := AInner;
  FBlock := ABlock;
  FGlobal := AGlobal;
  if AScale > 0 then FScale := AScale else FScale := 1;
end;

function TBlockMeasurer.Bounds(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; AH: TTyTextAnchorH;
  AV: TTyTextAnchorV): TTyXYWH;
var b: TTyRtBlockStyle;
begin
  b := FBlock;
  { an 'inherit' background is a rect whatever its colour: bound to any
    colour, the box is the one the site will draw }
  TyRtFinish(b, AFontName, AFontSizeLogical, AWeight, FGlobal, True, $FF000000);
  Result := TyRtBounds(TyRtLay(AText, b, TyRtDefaultOf(False, 0, False, 0, False,
    AH, AV), FScale, FInner));
end;

procedure TBlockMeasurer.MeasureLine(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
var box: TTyXYWH;
begin
  AW := 0;
  AH := 0;
  box := Bounds(AText, AFontName, AFontSizeLogical, AWeight, tahLeft, tavTop);
  if box.W < 0 then Exit;
  AW := box.W * FScale;
  AH := box.H * FScale;
end;

function TBlockMeasurer.MeasureBox(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; AH: TTyTextAnchorH;
  AV: TTyTextAnchorV): TTyRectF;
var box: TTyXYWH;
begin
  box := Bounds(AText, AFontName, AFontSizeLogical, AWeight, AH, AV);
  if box.W < 0 then Exit(TyRectF(0, 0, 0, 0));
  Result := TyRectF(box.X * FScale, box.Y * FScale, (box.X + box.W) * FScale,
    (box.Y + box.H) * FScale);
end;

function TBlockMeasurer.WrapToWidth(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
begin
  Result := FInner.WrapToWidth(AText, AFontName, AFontSizeLogical, AWeight, AMaxWidth);
end;

function TyRtBlockMeasurer(const AInner: ITyTextMeasurer;
  const ABlock: TTyRtBlockStyle; const AGlobal: TTyRtGlobal;
  AScale: Double): ITyTextMeasurer;
begin
  if (AInner = nil) or not ABlock.Needed then Exit(AInner);
  Result := TBlockMeasurer.Create(AInner, ABlock, AGlobal, AScale);
end;

end.
