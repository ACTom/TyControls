unit tyControls.AdvanceChart.TipHtml;
{$mode objfpc}{$H+}
{ [R2-I8] A TOOLTIP'S HTML, read the way a browser would read it.

  WHY THIS EXISTS. Upstream picks its tooltip renderer with
  getTooltipRenderMode: 'auto' (the default) is 'html' wherever there is a
  DOM, so on every page of the gallery the box is a <div> and a formatter's
  answer is set as its innerHTML -- `<br/>`, `<b>`, a coloured <span>, the
  marker span params.marker carries. Without a DOM (node) 'auto' is
  'richText' and the same string is drawn as zrender rich text, the markup
  shown as it was written. The port draws its box itself (spec section 55),
  and until this unit it drew every formatter's answer the richText way --
  the raw markup -- which is not what the pages' authors ever saw.

  WHAT IS READ. The subset the gallery's formatters and upstream's own
  markers produce, laid out as CSS lays out a `white-space: nowrap` box
  (TooltipHTMLContent's cssText):
    - line breaks: <br>; block boxes -- <div>, <p>, the headings, <ul>, <ol>,
      <li>, <table>, <tr>, <hr> and anything styled `display: block` -- start
      and end a line; an empty line is one a <br> made, never one a block
      boundary left;
    - whitespace collapses to one space and is dropped at a line's ends
      (<pre> and `white-space: pre*` keep it, and break at newlines);
    - inline styles: color, font-size (px, pt, em, %), font-weight, font-style,
      font-family, line-height, float: right (the value column of upstream's
      own markup), display: none;
    - <b> / <strong> / <th> bold, <i> / <em> italic, <font color>;
    - an inline-block with a width, a height and a background -- the marker
      span -- is a box of that size and colour, its border-radius kept, its
      horizontal margins around it;
    - a block's vertical margins (adjacent ones collapse, as CSS's do), its
      paddings, its top and bottom borders (drawn as rules across the box)
      and its left margin and padding (an indent); <p> and the headings carry
      the UA stylesheet's margins and sizes;
    - entities: the named ones of HTML 4 that formatters write and the
      numeric ones; an unknown name stays as written, as a browser leaves it;
    - comments, <script>, <style>, <head>, <title> and <template> draw
      nothing.
  ANY OTHER TAG IS ITS TEXT: the tag is dropped and what it contains is drawn
  in the style around it. Raw markup never reaches the box.

  WHAT IS NOT. Baseline alignment (every run sits centred in its line),
  wrapping (the box never wraps -- nowrap), widths and heights of blocks,
  backgrounds and side borders of blocks, text-align, images, list bullets.

  PURE: SysUtils, Math and the AdvanceChart units -- no LCL, no painter. The
  lines it answers are the ones TyTooltipMeasure measures and the control
  paints, so a test reads exactly what will be drawn. }
interface
uses
  SysUtils, Math,
  tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint,
  tyControls.AdvanceChart.Tooltip, tyControls.AdvanceChart.Handlers;

type
  { [R2-I8] Replace the built-in reading of a tooltip's html: AHtml is the
    text a formatter (or a component's content) answered, AInk the tooltip's
    own inks -- the style the text starts in. Set ALines to the lines to draw
    and AHandled to True; left unhandled, the built-in reading
    (TyTooltipHtmlLines) runs after you. }
  TTyChartTooltipHtmlEvent = procedure(Sender: TObject; const AHtml: string;
    const AInk: TTyTooltipInk; var ALines: TTyTooltipLineArray;
    var AHandled: Boolean) of object;

{ The lines a browser would show for AHtml, styled from AInk's name ink. }
function TyTooltipHtmlLines(const AHtml: string;
  const AInk: TTyTooltipInk): TTyTooltipLineArray;

{ params.marker in html mode -- format.getTooltipMarker with renderMode
  'html': an inline-block span, 10 x 10 with radius 10 and a 4px right margin
  for an item, 4 x 4 with radius 4 between a 3px left and an 8px right margin
  (vertical-align: middle) for a sub-item, its background the colour's text
  through encodeHTML. }
function TyTooltipHtmlMarker(const AColourText: string; ASub: Boolean): string;

{ A colour as upstream's colour strings spell a packed one: '#rrggbb' when
  opaque, else 'rgba(r,g,b,a)' with the alpha it was parsed from. }
function TyTooltipColourText(AColour: TTyChartColor): string;

{ zrender's encodeHTML: & < > " ' as &amp; &lt; &gt; &quot; &#39;. }
function TyTooltipEncodeHtml(const AText: string): string;

{ The text an html fragment's entities stand for: named (&nbsp; is U+00A0)
  and numeric (&#NNN; &#xHH;); an unknown name is left as written. }
function TyTooltipDecodeEntities(const AText: string): string;

{ [spec 237] THE TEXT A BROWSER SHOWS FOR AHtml, without its styles: the
  lines TyTooltipHtmlLines lays out, each its text runs joined (a marker or
  a box is no text), the lines joined by ASep (an empty line a <br> made
  stays an empty line). }
function TyHtmlPlainText(const AHtml: string; const ASep: string = #10): string;

{ [spec 237] THE TABLES IN AHtml, for the data view's grids: every <table>
  that is not inside another, in order -- its <caption>'s text, its header
  row (the first row when it is in a <thead> or all its cells are <th>) and
  every other row, each cell's text as TyHtmlPlainText reads it, its lines
  joined by a space (a table nested in a cell is part of that cell's text).
  AOutside is AHtml with those tables cut out (each leaves a block break). }
function TyHtmlTables(const AHtml: string;
  out AOutside: string): TTyChartDataViewTables;

{ [spec 237] AHtml with its tables' cells as ATables holds them now (as the
  user left the grids TyHtmlTables made of it): each cell whose text
  differs has its content replaced by the new text, encoded; every other
  byte stays as written -- what upstream's contentToOption reads off the
  DOM after the user edited it. Cells past the html's own are left out. }
function TyHtmlSetCells(const AHtml: string;
  const ATables: TTyChartDataViewTables): string;

implementation

uses
  tyControls.AdvanceChart.Color, tyControls.AdvanceChart.Scale, tyControls.FontUnits;

const
  { tyControls.Types' TyFontItalic: the italic flag above a font weight. Not
    imported -- that unit uses Graphics, and this layer stays free of the
    LCL. }
  cItalicFlag = $10000;

{ ============================ small helpers ============================ }

function TyTooltipEncodeHtml(const AText: string): string;
begin
  Result := TyChartEncodeHtml(AText);
end;

function TyTooltipColourText(AColour: TTyChartColor): string;
begin
  if (AColour shr 24) = $FF then
    Result := '#' + LowerCase(IntToHex(AColour and $FFFFFF, 6))
  else
    Result := 'rgba(' + IntToStr((AColour shr 16) and $FF) + ','
      + IntToStr((AColour shr 8) and $FF) + ',' + IntToStr(AColour and $FF) + ','
      + TyJsNumberToString(TyChartColorAlpha(AColour)) + ')';
end;

function TyTooltipHtmlMarker(const AColourText: string; ASub: Boolean): string;
begin
  if AColourText = '' then Exit('');
  if ASub then
    Result := '<span style="display:inline-block;vertical-align:middle;margin-right:8px;margin-left:3px;'
      + 'border-radius:4px;width:4px;height:4px;background-color:'
      + TyTooltipEncodeHtml(AColourText) + ';"></span>'
  else
    Result := '<span style="display:inline-block;margin-right:4px;'
      + 'border-radius:10px;width:10px;height:10px;background-color:'
      + TyTooltipEncodeHtml(AColourText) + ';"></span>';
end;

function Utf8Of(ACode: Cardinal): string;
begin
  if (ACode = 0) or (ACode > $10FFFF) or ((ACode >= $D800) and (ACode <= $DFFF)) then
    ACode := $FFFD;
  if ACode < $80 then
    Result := Chr(ACode)
  else if ACode < $800 then
    Result := Chr($C0 or (ACode shr 6)) + Chr($80 or (ACode and $3F))
  else if ACode < $10000 then
    Result := Chr($E0 or (ACode shr 12)) + Chr($80 or ((ACode shr 6) and $3F))
      + Chr($80 or (ACode and $3F))
  else
    Result := Chr($F0 or (ACode shr 18)) + Chr($80 or ((ACode shr 12) and $3F))
      + Chr($80 or ((ACode shr 6) and $3F)) + Chr($80 or (ACode and $3F));
end;

type
  TEntity = record
    Name: string;
    Code: Cardinal;
  end;

const
  { The names a formatter writes in practice: markup, spacing, punctuation,
    the currency and maths signs. A name not here stays as written -- a
    browser shows an unknown entity as its text, too. }
  cEntities: array[0..47] of TEntity = (
    (Name: 'amp'; Code: 38), (Name: 'lt'; Code: 60), (Name: 'gt'; Code: 62),
    (Name: 'quot'; Code: 34), (Name: 'apos'; Code: 39), (Name: 'nbsp'; Code: 160),
    (Name: 'ensp'; Code: $2002), (Name: 'emsp'; Code: $2003),
    (Name: 'thinsp'; Code: $2009), (Name: 'zwnj'; Code: $200C),
    (Name: 'zwj'; Code: $200D), (Name: 'ndash'; Code: $2013),
    (Name: 'mdash'; Code: $2014), (Name: 'lsquo'; Code: $2018),
    (Name: 'rsquo'; Code: $2019), (Name: 'ldquo'; Code: $201C),
    (Name: 'rdquo'; Code: $201D), (Name: 'bull'; Code: $2022),
    (Name: 'hellip'; Code: $2026), (Name: 'middot'; Code: 183),
    (Name: 'copy'; Code: 169), (Name: 'reg'; Code: 174),
    (Name: 'trade'; Code: $2122), (Name: 'deg'; Code: 176),
    (Name: 'plusmn'; Code: 177), (Name: 'times'; Code: 215),
    (Name: 'divide'; Code: 247), (Name: 'minus'; Code: $2212),
    (Name: 'le'; Code: $2264), (Name: 'ge'; Code: $2265),
    (Name: 'ne'; Code: $2260), (Name: 'asymp'; Code: $2248),
    (Name: 'infin'; Code: $221E), (Name: 'micro'; Code: 181),
    (Name: 'para'; Code: 182), (Name: 'sect'; Code: 167),
    (Name: 'cent'; Code: 162), (Name: 'pound'; Code: 163),
    (Name: 'yen'; Code: 165), (Name: 'euro'; Code: $20AC),
    (Name: 'larr'; Code: $2190), (Name: 'uarr'; Code: $2191),
    (Name: 'rarr'; Code: $2192), (Name: 'darr'; Code: $2193),
    (Name: 'harr'; Code: $2194), (Name: 'frac12'; Code: 189),
    (Name: 'sup2'; Code: 178), (Name: 'laquo'; Code: 171));

function TyTooltipDecodeEntities(const AText: string): string;
var
  i, j, k: Integer;
  name: string;
  code: Cardinal;
  ok: Boolean;
begin
  Result := '';
  i := 1;
  while i <= Length(AText) do
  begin
    if AText[i] <> '&' then
    begin
      Result := Result + AText[i];
      Inc(i);
      Continue;
    end;
    j := i + 1;
    while (j <= Length(AText)) and (j - i <= 32)
      and (AText[j] in ['a'..'z', 'A'..'Z', '0'..'9', '#']) do Inc(j);
    ok := False;
    code := 0;
    if (j <= Length(AText)) and (AText[j] = ';') and (j > i + 1) then
    begin
      name := Copy(AText, i + 1, j - i - 1);
      if name[1] = '#' then
      begin
        if (Length(name) > 2) and (name[2] in ['x', 'X']) then
          ok := TryStrToDWord('$' + Copy(name, 3, MaxInt), code)
        else if Length(name) > 1 then
          ok := TryStrToDWord(Copy(name, 2, MaxInt), code);
        if ok and (Pos('-', name) > 0) then ok := False;
      end
      else
        for k := 0 to High(cEntities) do
          { entity names are case-sensitive in HTML }
          if cEntities[k].Name = name then
          begin
            code := cEntities[k].Code;
            ok := True;
            Break;
          end;
    end;
    if ok then
    begin
      Result := Result + Utf8Of(code);
      i := j + 1;
    end
    else
    begin
      Result := Result + '&';
      Inc(i);
    end;
  end;
end;

{ A CSS length in px. AEmPx is what 1em is (the font size in px); APctOf
  what 100% is (-1: a percentage is not a length here). False when the text
  is not a length. }
function CssLength(const AText: string; AEmPx, APctOf: Double;
  out APx: Double): Boolean;
var
  s, num, unitS: string;
  i: Integer;
  v: Double;
begin
  Result := False;
  APx := 0;
  s := LowerCase(Trim(AText));
  if s = '' then Exit;
  if s = '0' then Exit(True);
  i := 1;
  while (i <= Length(s)) and (s[i] in ['0'..'9', '.', '-', '+']) do Inc(i);
  num := Copy(s, 1, i - 1);
  unitS := Trim(Copy(s, i, MaxInt));
  if num = '' then Exit;
  if not TryStrToFloat(num, v, DefaultFormatSettings) then Exit;
  if (unitS = 'px') or (unitS = '') then APx := v
  else if unitS = 'pt' then APx := v * 96 / 72
  else if (unitS = 'em') or (unitS = 'rem') then APx := v * AEmPx
  else if unitS = '%' then
  begin
    if APctOf < 0 then Exit;
    APx := v * APctOf / 100;
  end
  else Exit;
  Result := not (IsNan(APx) or IsInfinite(APx));
end;

{ The first word of a CSS value: '1px solid #ccc' word by word. }
function CssWords(const AText: string): TStringArray;
var
  s, w: string;
  i, depth: Integer;
begin
  Result := nil;
  s := Trim(AText);
  w := '';
  depth := 0;
  for i := 1 to Length(s) do
  begin
    if s[i] = '(' then Inc(depth);
    if s[i] = ')' then Dec(depth);
    if (s[i] in [' ', #9, #10, #13]) and (depth <= 0) then
    begin
      if w <> '' then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := w;
        w := '';
      end;
    end
    else
      w := w + s[i];
  end;
  if w <> '' then
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := w;
  end;
end;

{ ============================ the reader ============================ }

type
  { What an element inherits and what it says about itself. }
  TStyle = record
    FontName: string;
    { the size as the run carries it: the ink's own value until a size is
      written, so plain text is the very run the richText path makes }
    SizeLogical: Integer;
    SizePx: Double;
    Weight: Integer;
    Italic: Boolean;
    Colour: TTyChartColor;
    { a written line-height, logical px; 0: none }
    LineHeight: Double;
    Right: Boolean;
    Hidden: Boolean;
    Pre: Boolean;
  end;

  { An element's own box, read from its style attribute and its tag. }
  TBox = record
    Display: (bdInline, bdBlock, bdInlineBlock, bdNone);
    MT, MB, ML, MR, PT, PB, PL: Double;
    BT, BB: Double;
    BTColour, BBColour: TTyChartColor;
    W, H, Radius: Double;
    HasW, HasH, HasBg, RadiusPct: Boolean;
    Bg: TTyChartColor;
  end;

  TFrame = record
    Tag: string;
    Style: TStyle;
    Box: TBox;
    Indent: Double;
  end;

  TGapKind = (gkMargin, gkFixed, gkRule);
  TGapItem = record
    Kind: TGapKind;
    Size: Double;
    Colour: TTyChartColor;
  end;

  TReader = class
  private
    FInk: TTyTooltipInk;
    FLines: TTyTooltipLineArray;
    FCur: TTyTooltipLine;
    FCurHas: Boolean;
    { the last thing put on the current line was a collapsible space }
    FSpaceEnds: Boolean;
    FGap: array of TGapItem;
    FStack: array of TFrame;
    function Top: TStyle;
    function Indent: Double;
    procedure PushGap(AKind: TGapKind; ASize: Double; AColour: TTyChartColor);
    procedure TakeGap(var ALine: TTyTooltipLine);
    procedure TrimLineEnd;
    procedure FinishLine(AForce: Boolean);
    procedure AddText(const AText: string);
    procedure AddBox(const AStyle: TStyle; const ABox: TBox);
    procedure OpenTag(const ATag, AAttrs: string; ASelfClose: Boolean);
    procedure CloseTag(const ATag: string);
    procedure ReadStyle(const ADecls: string; var AStyle: TStyle; var ABox: TBox);
    function LineHeightOf(const ALine: TTyTooltipLine): Double;
  public
    constructor Create(const AInk: TTyTooltipInk);
    procedure Run(const AHtml: string);
    property Lines: TTyTooltipLineArray read FLines;
  end;

const
  cBlockTags: array[0..30] of string = ('div', 'p', 'h1', 'h2', 'h3', 'h4',
    'h5', 'h6', 'ul', 'ol', 'li', 'table', 'tr', 'thead', 'tbody', 'tfoot',
    'blockquote', 'pre', 'section', 'article', 'header', 'footer', 'nav',
    'aside', 'main', 'figure', 'figcaption', 'address', 'center', 'dl', 'dd');
  cVoidTags: array[0..13] of string = ('br', 'hr', 'img', 'input', 'meta',
    'link', 'wbr', 'col', 'area', 'base', 'embed', 'param', 'source', 'track');
  cRawTags: array[0..5] of string = ('script', 'style', 'head', 'title',
    'template', 'textarea');

function InList(const S: string; const AList: array of string): Boolean;
var i: Integer;
begin
  for i := 0 to High(AList) do
    if AList[i] = S then Exit(True);
  Result := False;
end;

function SameRunStyle(const A, B: TTyTooltipRun): Boolean;
begin
  Result := (A.Kind = ttrText) and (B.Kind = ttrText)
    and (A.FontName = B.FontName) and (A.FontSizeLogical = B.FontSizeLogical)
    and (A.FontWeight = B.FontWeight) and (A.Colour = B.Colour)
    and (A.AlignRight = B.AlignRight)
    and (A.LineHeightLogical = B.LineHeightLogical);
end;

constructor TReader.Create(const AInk: TTyTooltipInk);
var f: TFrame;
begin
  inherited Create;
  FInk := AInk;
  f := Default(TFrame);
  f.Tag := '#root';
  f.Style.FontName := AInk.NameFontName;
  f.Style.SizeLogical := AInk.NameSizeLogical;
  f.Style.SizePx := TyFontPxOf(AInk.NameSizeLogical);
  f.Style.Weight := AInk.NameWeight;
  f.Style.Colour := AInk.NameColour;
  SetLength(FStack, 1);
  FStack[0] := f;
  FCur := Default(TTyTooltipLine);
end;

function TReader.Top: TStyle;
begin
  Result := FStack[High(FStack)].Style;
end;

function TReader.Indent: Double;
begin
  Result := FStack[High(FStack)].Indent;
end;

procedure TReader.PushGap(AKind: TGapKind; ASize: Double; AColour: TTyChartColor);
begin
  if (AKind <> gkRule) and (ASize = 0) then Exit;
  SetLength(FGap, Length(FGap) + 1);
  FGap[High(FGap)].Kind := AKind;
  FGap[High(FGap)].Size := ASize;
  FGap[High(FGap)].Colour := AColour;
end;

{ THE SPACE BETWEEN TWO LINES, as CSS stacks it: adjacent margins collapse
  to the largest (the most negative pulling back), a padding or a border
  between them stops the collapse, and a border is drawn where it falls.
  The rules are written relative to the line's top, so they come out
  negative -- above it, in its gap. }
procedure TReader.TakeGap(var ALine: TTyTooltipLine);
var
  i, n: Integer;
  pos, maxPos, minNeg: Double;
  inMargin: Boolean;
  offs: array of Double;
  ruleAt: array of Integer;
begin
  ALine.GapBeforeLogical := 0;
  ALine.Rules := nil;
  if Length(FGap) = 0 then Exit;
  pos := 0;
  maxPos := 0;
  minNeg := 0;
  inMargin := False;
  offs := nil;
  ruleAt := nil;
  for i := 0 to High(FGap) do
    case FGap[i].Kind of
      gkMargin:
        begin
          if not inMargin then
          begin
            inMargin := True;
            maxPos := 0;
            minNeg := 0;
          end;
          if FGap[i].Size > maxPos then maxPos := FGap[i].Size;
          if FGap[i].Size < minNeg then minNeg := FGap[i].Size;
        end;
    else
      begin
        if inMargin then
        begin
          pos := pos + maxPos + minNeg;
          inMargin := False;
        end;
        if FGap[i].Kind = gkRule then
        begin
          n := Length(offs);
          SetLength(offs, n + 1);
          SetLength(ruleAt, n + 1);
          offs[n] := pos;
          ruleAt[n] := i;
          pos := pos + FGap[i].Size;
        end
        else
          pos := pos + FGap[i].Size;
      end;
    end;
  if inMargin then pos := pos + maxPos + minNeg;
  if pos < 0 then pos := 0;
  ALine.GapBeforeLogical := pos;
  SetLength(ALine.Rules, Length(offs));
  for i := 0 to High(offs) do
  begin
    ALine.Rules[i].OffsetLogical := offs[i] - pos;
    ALine.Rules[i].WidthLogical := FGap[ruleAt[i]].Size;
    ALine.Rules[i].Colour := FGap[ruleAt[i]].Colour;
  end;
  FGap := nil;
end;

procedure TReader.TrimLineEnd;
var n: Integer; t: string;
begin
  while Length(FCur.Runs) > 0 do
  begin
    n := High(FCur.Runs);
    if FCur.Runs[n].Kind <> ttrText then Break;
    t := FCur.Runs[n].Text;
    while (t <> '') and (t[Length(t)] = ' ') do SetLength(t, Length(t) - 1);
    FCur.Runs[n].Text := t;
    if t <> '' then Break;
    SetLength(FCur.Runs, n);
  end;
end;

function TReader.LineHeightOf(const ALine: TTyTooltipLine): Double;
var
  i: Integer;
  h: Double;
  own: Boolean;
begin
  { THE INK'S LINE unless something on it is not the ink's: a run with a
    written line-height takes it, a run of another size takes the port's
    rule for the ink -- round(px * 3 / 2) in the ink's units -- at that
    size, a box its own height. 0 says "the ink's", so a line of plain text
    is exactly the line the richText path makes. }
  own := False;
  h := FInk.LineHeightLogical;
  for i := 0 to High(ALine.Runs) do
    case ALine.Runs[i].Kind of
      ttrText:
        if ALine.Runs[i].LineHeightLogical > 0 then
        begin
          own := True;
          h := Max(h, ALine.Runs[i].LineHeightLogical);
        end
        else if ALine.Runs[i].FontSizeLogical <> FInk.NameSizeLogical then
        begin
          own := True;
          h := Max(h, Round(TyFontPxOf(ALine.Runs[i].FontSizeLogical)
            * 72 / 96 * 3 / 2));
        end;
      ttrBox:
        if ALine.Runs[i].BoxHLogical > FInk.LineHeightLogical then
        begin
          own := True;
          h := Max(h, ALine.Runs[i].BoxHLogical);
        end;
    end;
  if own then Result := h else Result := 0;
end;

{ End the current line. AForce: a <br> -- the line is kept even when
  nothing is on it; a block boundary drops an empty one. }
procedure TReader.FinishLine(AForce: Boolean);
begin
  TrimLineEnd;
  if FCurHas or AForce then
  begin
    if not FCurHas then FCur.IndentLogical := Indent;
    TakeGap(FCur);
    FCur.HeightLogical := LineHeightOf(FCur);
    SetLength(FLines, Length(FLines) + 1);
    FLines[High(FLines)] := FCur;
  end;
  FCur := Default(TTyTooltipLine);
  FCurHas := False;
  FSpaceEnds := False;
end;

procedure TReader.AddText(const AText: string);
var
  st: TStyle;
  s, piece: string;
  i: Integer;
  rn: TTyTooltipRun;

  procedure Emit(const AStr: string);
  var n: Integer;
  begin
    if AStr = '' then Exit;
    rn := Default(TTyTooltipRun);
    rn.Kind := ttrText;
    rn.Text := AStr;
    rn.FontName := st.FontName;
    rn.FontSizeLogical := st.SizeLogical;
    rn.FontWeight := st.Weight;
    if st.Italic then rn.FontWeight := rn.FontWeight or cItalicFlag;
    rn.Colour := st.Colour;
    rn.AlignRight := st.Right;
    rn.LineHeightLogical := st.LineHeight;
    if not FCurHas then FCur.IndentLogical := Indent;
    n := Length(FCur.Runs);
    if (n > 0) and SameRunStyle(FCur.Runs[n - 1], rn) then
      FCur.Runs[n - 1].Text := FCur.Runs[n - 1].Text + AStr
    else
    begin
      SetLength(FCur.Runs, n + 1);
      FCur.Runs[n] := rn;
    end;
    FCurHas := True;
  end;

begin
  st := Top;
  if st.Hidden then Exit;
  s := TyTooltipDecodeEntities(AText);
  if st.Pre then
  begin
    { PRESERVED: every space is drawn and a newline breaks the line }
    piece := '';
    for i := 1 to Length(s) do
      if s[i] = #10 then
      begin
        Emit(piece);
        piece := '';
        FinishLine(True);
      end
      else if s[i] = #13 then
      else if s[i] = #9 then piece := piece + '        '
      else piece := piece + s[i];
    Emit(piece);
    FSpaceEnds := False;
    Exit;
  end;
  { COLLAPSED: a rn of spaces, tabs and newlines is one space, and none at
    the start of a line or after a space already there }
  piece := '';
  for i := 1 to Length(s) do
    if s[i] in [' ', #9, #10, #13, #12] then
    begin
      if FSpaceEnds then Continue;
      if (not FCurHas) and (piece = '') then Continue;
      piece := piece + ' ';
      FSpaceEnds := True;
    end
    else
    begin
      piece := piece + s[i];
      FSpaceEnds := False;
    end;
  Emit(piece);
end;

procedure TReader.AddBox(const AStyle: TStyle; const ABox: TBox);
var
  rn: TTyTooltipRun;
  r: Double;
  n: Integer;
begin
  if AStyle.Hidden then Exit;
  rn := Default(TTyTooltipRun);
  rn.Kind := ttrBox;
  rn.Colour := ABox.Bg;
  if not ABox.HasBg then rn.Colour := 0;
  rn.BoxWLogical := Max(0, ABox.W);
  rn.BoxHLogical := Max(0, ABox.H);
  r := ABox.Radius;
  if ABox.RadiusPct then r := Min(rn.BoxWLogical, rn.BoxHLogical) * r / 100;
  rn.BoxRadiusLogical := Max(0, r);
  rn.MarginLLogical := ABox.ML;
  rn.MarginRLogical := ABox.MR;
  rn.MarkerSizeLogical := rn.BoxWLogical;
  if not FCurHas then FCur.IndentLogical := Indent;
  n := Length(FCur.Runs);
  SetLength(FCur.Runs, n + 1);
  FCur.Runs[n] := rn;
  FCurHas := True;
  FSpaceEnds := False;
end;

procedure TReader.ReadStyle(const ADecls: string; var AStyle: TStyle;
  var ABox: TBox);
var
  decls: TStringArray;
  i, p, k: Integer;
  prop, val, low: string;
  px: Double;
  c: TTyChartColor;
  words: TStringArray;

  procedure Edges(const AVal: string; var T, R, B, L: Double; AKeepNeg: Boolean);
  var w: TStringArray; v: array[0..3] of Double; j: Integer;
  begin
    w := CssWords(AVal);
    if (Length(w) = 0) or (Length(w) > 4) then Exit;
    for j := 0 to High(w) do
      if not CssLength(w[j], AStyle.SizePx, -1, v[j]) then
      begin
        if LowerCase(w[j]) = 'auto' then v[j] := 0 else Exit;
      end;
    case Length(w) of
      1: begin T := v[0]; R := v[0]; B := v[0]; L := v[0]; end;
      2: begin T := v[0]; B := v[0]; R := v[1]; L := v[1]; end;
      3: begin T := v[0]; R := v[1]; L := v[1]; B := v[2]; end;
      4: begin T := v[0]; R := v[1]; B := v[2]; L := v[3]; end;
    end;
    if not AKeepNeg then
    begin
      T := Max(0, T); R := Max(0, R); B := Max(0, B); L := Max(0, L);
    end;
  end;

  procedure Border(const AVal: string; var AW: Double; var AColour: TTyChartColor);
  var w: TStringArray; j: Integer; wd: Double; col: TTyChartColor; styled: Boolean;
  begin
    w := CssWords(AVal);
    wd := 3;  // CSS's 'medium'
    col := AStyle.Colour;
    styled := False;
    for j := 0 to High(w) do
    begin
      if LowerCase(w[j]) = 'none' then begin AW := 0; Exit; end;
      if InList(LowerCase(w[j]), ['solid', 'dashed', 'dotted', 'double',
        'groove', 'ridge', 'inset', 'outset']) then styled := True
      else if LowerCase(w[j]) = 'thin' then wd := 1
      else if LowerCase(w[j]) = 'medium' then wd := 3
      else if LowerCase(w[j]) = 'thick' then wd := 5
      else if CssLength(w[j], AStyle.SizePx, -1, px) then wd := Max(0, px)
      else if TyTryParseChartColor(w[j], col) then ;
    end;
    { a border without a style is none, as CSS has it }
    if not styled then begin AW := 0; Exit; end;
    AW := wd;
    AColour := col;
  end;

var
  dummyR: Double;
  bw, sz: Double;
begin
  decls := ADecls.Split([';']);
  for i := 0 to High(decls) do
  begin
    p := Pos(':', decls[i]);
    if p = 0 then Continue;
    prop := LowerCase(Trim(Copy(decls[i], 1, p - 1)));
    val := Trim(Copy(decls[i], p + 1, MaxInt));
    k := Pos('!important', LowerCase(val));
    if k > 0 then val := Trim(Copy(val, 1, k - 1));
    low := LowerCase(val);
    if prop = 'color' then
    begin
      if TyTryParseChartColor(val, c) then AStyle.Colour := c;
    end
    else if prop = 'font-size' then
    begin
      sz := -1;
      if low = 'xx-small' then sz := 9
      else if low = 'x-small' then sz := 10
      else if low = 'small' then sz := 13
      else if low = 'medium' then sz := 16
      else if low = 'large' then sz := 18
      else if low = 'x-large' then sz := 24
      else if low = 'xx-large' then sz := 32
      else if low = 'smaller' then sz := AStyle.SizePx / 1.2
      else if low = 'larger' then sz := AStyle.SizePx * 1.2
      else if CssLength(val, AStyle.SizePx, AStyle.SizePx, px) then sz := px;
      if sz > 0 then
      begin
        AStyle.SizePx := sz;
        AStyle.SizeLogical := TyFontSizeFromPx(sz);
      end;
    end
    else if prop = 'font-weight' then
    begin
      if (low = 'bold') or (low = 'bolder') then AStyle.Weight := 700
      else if (low = 'normal') or (low = 'lighter') then AStyle.Weight := 400
      else if TryStrToInt(low, k) and (k >= 1) and (k <= 1000) then AStyle.Weight := k;
    end
    else if prop = 'font-style' then
      AStyle.Italic := (low = 'italic') or (Pos('oblique', low) = 1)
    else if prop = 'font-family' then
    begin
      words := val.Split([',']);
      for k := 0 to High(words) do
      begin
        words[k] := Trim(words[k]);
        if (Length(words[k]) >= 2) and (words[k][1] in ['"', '''']) then
          words[k] := Copy(words[k], 2, Length(words[k]) - 2);
        { the generic families are the ink's font: the theme chose it }
        if InList(LowerCase(words[k]), ['serif', 'sans-serif', 'monospace',
          'cursive', 'fantasy', 'system-ui', 'inherit', 'initial', '']) then
          Continue;
        AStyle.FontName := words[k];
        Break;
      end;
    end
    else if prop = 'line-height' then
    begin
      if low = 'normal' then AStyle.LineHeight := 0
      else if TryStrToFloat(low, px, DefaultFormatSettings) then
        AStyle.LineHeight := px * AStyle.SizePx
      else if CssLength(val, AStyle.SizePx, AStyle.SizePx, px) then
        AStyle.LineHeight := px;
    end
    else if prop = 'float' then
      AStyle.Right := low = 'right'
    else if prop = 'white-space' then
      AStyle.Pre := Pos('pre', low) = 1
    else if prop = 'display' then
    begin
      if low = 'none' then ABox.Display := bdNone
      else if low = 'inline-block' then ABox.Display := bdInlineBlock
      else if low = 'inline' then ABox.Display := bdInline
      else if (low = 'block') or (low = 'list-item') or (low = 'flex')
        or (low = 'table') or (low = 'grid') then ABox.Display := bdBlock;
    end
    else if prop = 'width' then
      ABox.HasW := CssLength(val, AStyle.SizePx, -1, ABox.W)
    else if prop = 'height' then
      ABox.HasH := CssLength(val, AStyle.SizePx, -1, ABox.H)
    else if (prop = 'background-color') or (prop = 'background') then
    begin
      words := CssWords(val);
      for k := 0 to High(words) do
        if TyTryParseChartColor(words[k], c) then
        begin
          ABox.Bg := c;
          ABox.HasBg := True;
        end;
    end
    else if prop = 'border-radius' then
    begin
      words := CssWords(val);
      if Length(words) > 0 then
      begin
        if (Length(words[0]) > 1) and (words[0][Length(words[0])] = '%') then
        begin
          ABox.RadiusPct := TryStrToFloat(Copy(words[0], 1, Length(words[0]) - 1),
            ABox.Radius, DefaultFormatSettings);
          if not ABox.RadiusPct then ABox.Radius := 0;
        end
        else if CssLength(words[0], AStyle.SizePx, -1, px) then
        begin
          ABox.Radius := px;
          ABox.RadiusPct := False;
        end;
      end;
    end
    else if prop = 'margin' then
      Edges(val, ABox.MT, ABox.MR, ABox.MB, ABox.ML, True)
    else if prop = 'margin-top' then
    begin
      if CssLength(val, AStyle.SizePx, -1, px) then ABox.MT := px;
    end
    else if prop = 'margin-bottom' then
    begin
      if CssLength(val, AStyle.SizePx, -1, px) then ABox.MB := px;
    end
    else if prop = 'margin-left' then
    begin
      if CssLength(val, AStyle.SizePx, -1, px) then ABox.ML := px;
    end
    else if prop = 'margin-right' then
    begin
      if CssLength(val, AStyle.SizePx, -1, px) then ABox.MR := px;
    end
    else if prop = 'padding' then
    begin
      dummyR := 0;
      Edges(val, ABox.PT, dummyR, ABox.PB, ABox.PL, False);
    end
    else if prop = 'padding-top' then
    begin
      if CssLength(val, AStyle.SizePx, -1, px) then ABox.PT := Max(0, px);
    end
    else if prop = 'padding-bottom' then
    begin
      if CssLength(val, AStyle.SizePx, -1, px) then ABox.PB := Max(0, px);
    end
    else if prop = 'padding-left' then
    begin
      if CssLength(val, AStyle.SizePx, -1, px) then ABox.PL := Max(0, px);
    end
    else if prop = 'border' then
    begin
      bw := 0;
      c := AStyle.Colour;
      Border(val, bw, c);
      ABox.BT := bw; ABox.BB := bw;
      ABox.BTColour := c; ABox.BBColour := c;
    end
    else if prop = 'border-top' then
    begin
      bw := 0;
      c := AStyle.Colour;
      Border(val, bw, c);
      ABox.BT := bw;
      ABox.BTColour := c;
    end
    else if prop = 'border-bottom' then
    begin
      bw := 0;
      c := AStyle.Colour;
      Border(val, bw, c);
      ABox.BB := bw;
      ABox.BBColour := c;
    end;
  end;
end;

function AttrValue(const AAttrs, AName: string; out AValue: string): Boolean;
var
  i, n, j: Integer;
  name: string;
  q: Char;
begin
  Result := False;
  AValue := '';
  i := 1;
  n := Length(AAttrs);
  while i <= n do
  begin
    while (i <= n) and (AAttrs[i] in [' ', #9, #10, #13, #12, '/']) do Inc(i);
    j := i;
    while (i <= n) and not (AAttrs[i] in [' ', #9, #10, #13, #12, '=', '/', '>']) do Inc(i);
    name := LowerCase(Copy(AAttrs, j, i - j));
    if name = '' then
    begin
      Inc(i);
      Continue;
    end;
    while (i <= n) and (AAttrs[i] in [' ', #9, #10, #13, #12]) do Inc(i);
    AValue := '';
    if (i <= n) and (AAttrs[i] = '=') then
    begin
      Inc(i);
      while (i <= n) and (AAttrs[i] in [' ', #9, #10, #13, #12]) do Inc(i);
      if (i <= n) and (AAttrs[i] in ['"', '''']) then
      begin
        q := AAttrs[i];
        Inc(i);
        j := i;
        while (i <= n) and (AAttrs[i] <> q) do Inc(i);
        AValue := Copy(AAttrs, j, i - j);
        Inc(i);
      end
      else
      begin
        j := i;
        while (i <= n) and not (AAttrs[i] in [' ', #9, #10, #13, #12, '>']) do Inc(i);
        AValue := Copy(AAttrs, j, i - j);
      end;
    end;
    if name = AName then
    begin
      AValue := TyTooltipDecodeEntities(AValue);
      Exit(True);
    end;
  end;
  AValue := '';
end;

procedure TReader.OpenTag(const ATag, AAttrs: string; ASelfClose: Boolean);
var
  f: TFrame;
  st: TStyle;
  box: TBox;
  v: string;
  c: TTyChartColor;
  em: Double;
  isBlock: Boolean;

  procedure Heading(AScale, AMargin: Double);
  begin
    st.SizePx := st.SizePx * AScale;
    st.SizeLogical := TyFontSizeFromPx(st.SizePx);
    st.Weight := 700;
    box.MT := AMargin * st.SizePx;
    box.MB := box.MT;
  end;

begin
  if ATag = 'br' then
  begin
    { a <br> ends the line it is on, the empty one included }
    if not Top.Hidden then FinishLine(True);
    Exit;
  end;
  st := Top;
  box := Default(TBox);
  em := st.SizePx;
  isBlock := InList(ATag, cBlockTags);
  if isBlock then box.Display := bdBlock else box.Display := bdInline;
  { the UA stylesheet's part: weights, sizes and margins }
  if (ATag = 'b') or (ATag = 'strong') or (ATag = 'th') then st.Weight := 700
  else if (ATag = 'i') or (ATag = 'em') or (ATag = 'cite') or (ATag = 'var')
    or (ATag = 'dfn') or (ATag = 'address') then st.Italic := True
  else if ATag = 'small' then
  begin
    st.SizePx := st.SizePx / 1.2;
    st.SizeLogical := TyFontSizeFromPx(st.SizePx);
  end
  else if ATag = 'big' then
  begin
    st.SizePx := st.SizePx * 1.2;
    st.SizeLogical := TyFontSizeFromPx(st.SizePx);
  end
  else if ATag = 'p' then
  begin
    box.MT := em;
    box.MB := em;
  end
  else if ATag = 'h1' then Heading(2, 0.67)
  else if ATag = 'h2' then Heading(1.5, 0.83)
  else if ATag = 'h3' then Heading(1.17, 1)
  else if ATag = 'h4' then Heading(1, 1.33)
  else if ATag = 'h5' then Heading(0.83, 1.67)
  else if ATag = 'h6' then Heading(0.67, 2.33)
  else if (ATag = 'ul') or (ATag = 'ol') then
  begin
    box.MT := em;
    box.MB := em;
    box.PL := 40;
  end
  else if ATag = 'blockquote' then
  begin
    box.MT := em;
    box.MB := em;
    box.ML := 40;
  end
  else if ATag = 'dd' then box.ML := 40
  else if ATag = 'pre' then
  begin
    st.Pre := True;
    box.MT := em;
    box.MB := em;
  end
  else if ATag = 'font' then
  begin
    if AttrValue(AAttrs, 'color', v) and TyTryParseChartColor(Trim(v), c) then
      st.Colour := c;
  end
  else if ATag = 'td' then
    { cells side by side, a space between them }
    AddText(' ');
  if AttrValue(AAttrs, 'style', v) then ReadStyle(v, st, box);
  if AttrValue(AAttrs, 'hidden', v) then box.Display := bdNone;
  if box.Display = bdNone then st.Hidden := True;

  if ATag = 'hr' then
  begin
    if st.Hidden then Exit;
    FinishLine(False);
    { the UA's hr: 0.5em above and below, a 1px inset border on each side --
      drawn as one 2px rule in the colour around it (grey in a browser) }
    PushGap(gkMargin, 0.5 * em, 0);
    PushGap(gkRule, 2, $FF808080);
    PushGap(gkMargin, 0.5 * em, 0);
    Exit;
  end;
  if InList(ATag, cVoidTags) and (box.Display <> bdInlineBlock) then Exit;

  if box.Display = bdInlineBlock then
  begin
    if box.HasW or box.HasH or box.HasBg then
    begin
      { THE MARKER'S SHAPE: a sized inline-block draws as itself, whatever
        it contains -- upstream's marker span contains nothing }
      AddBox(st, box);
      if ASelfClose or InList(ATag, cVoidTags) then Exit;
      f := Default(TFrame);
      f.Tag := ATag;
      f.Style := st;
      f.Style.Hidden := True;
      f.Box := Default(TBox);
      f.Indent := Indent;
      SetLength(FStack, Length(FStack) + 1);
      FStack[High(FStack)] := f;
      Exit;
    end;
    box.Display := bdInline;
  end;

  if (box.Display = bdBlock) and not st.Hidden then
  begin
    FinishLine(False);
    PushGap(gkMargin, box.MT, 0);
    if box.BT > 0 then
    begin
      PushGap(gkRule, box.BT, box.BTColour);
    end;
    PushGap(gkFixed, box.PT, 0);
  end;
  if ASelfClose then
  begin
    if (box.Display = bdBlock) and not st.Hidden then
    begin
      PushGap(gkFixed, box.PB, 0);
      if box.BB > 0 then PushGap(gkRule, box.BB, box.BBColour);
      PushGap(gkMargin, box.MB, 0);
    end;
    Exit;
  end;
  f := Default(TFrame);
  f.Tag := ATag;
  f.Style := st;
  f.Box := box;
  f.Indent := Indent;
  if box.Display = bdBlock then f.Indent := f.Indent + Max(0, box.ML) + box.PL;
  SetLength(FStack, Length(FStack) + 1);
  FStack[High(FStack)] := f;
end;

procedure TReader.CloseTag(const ATag: string);
var
  i, k: Integer;
  f: TFrame;
begin
  if ATag = 'br' then
  begin
    { </br> is a <br> to a browser }
    if not Top.Hidden then FinishLine(True);
    Exit;
  end;
  k := -1;
  for i := High(FStack) downto 1 do
    if FStack[i].Tag = ATag then
    begin
      k := i;
      Break;
    end;
  if k < 0 then Exit;
  { what is left open inside closes with it }
  for i := High(FStack) downto k do
  begin
    f := FStack[i];
    SetLength(FStack, i);
    if (f.Box.Display = bdBlock) and not f.Style.Hidden then
    begin
      FinishLine(False);
      PushGap(gkFixed, f.Box.PB, 0);
      if f.Box.BB > 0 then PushGap(gkRule, f.Box.BB, f.Box.BBColour);
      PushGap(gkMargin, f.Box.MB, 0);
    end;
  end;
end;

procedure TReader.Run(const AHtml: string);
var
  i, j, n, k: Integer;
  text, tag, attrs, low: string;
  closing, selfClose: Boolean;
  q: Char;
  spacer: TTyTooltipLine;
begin
  n := Length(AHtml);
  i := 1;
  text := '';
  while i <= n do
  begin
    if AHtml[i] <> '<' then
    begin
      text := text + AHtml[i];
      Inc(i);
      Continue;
    end;
    { a comment }
    if Copy(AHtml, i, 4) = '<!--' then
    begin
      AddText(text);
      text := '';
      k := Pos('-->', Copy(AHtml, i + 4, MaxInt));
      if k = 0 then Break;
      i := i + 4 + k + 2;
      Continue;
    end;
    { a declaration or a processing instruction }
    if (i < n) and (AHtml[i + 1] in ['!', '?']) then
    begin
      AddText(text);
      text := '';
      while (i <= n) and (AHtml[i] <> '>') do Inc(i);
      Inc(i);
      Continue;
    end;
    closing := (i < n) and (AHtml[i + 1] = '/');
    j := i + 1;
    if closing then Inc(j);
    { not a tag at all: '<' and a space, a digit, the end -- text, as a
      browser reads it }
    if (j > n) or not (AHtml[j] in ['a'..'z', 'A'..'Z']) then
    begin
      text := text + '<';
      Inc(i);
      Continue;
    end;
    AddText(text);
    text := '';
    k := j;
    while (k <= n) and not (AHtml[k] in [' ', #9, #10, #13, #12, '/', '>']) do Inc(k);
    tag := LowerCase(Copy(AHtml, j, k - j));
    { the attributes, quotes respected, to the closing '>' }
    j := k;
    while (k <= n) and (AHtml[k] <> '>') do
    begin
      if AHtml[k] in ['"', ''''] then
      begin
        q := AHtml[k];
        Inc(k);
        while (k <= n) and (AHtml[k] <> q) do Inc(k);
      end;
      Inc(k);
    end;
    attrs := Copy(AHtml, j, k - j);
    selfClose := (attrs <> '') and (attrs[Length(attrs)] = '/');
    i := k + 1;
    if closing then
    begin
      CloseTag(tag);
      Continue;
    end;
    if InList(tag, cRawTags) then
    begin
      { its content is not drawn: skip to its end tag }
      low := LowerCase(AHtml);
      k := Pos('</' + tag, Copy(low, i, MaxInt));
      if k = 0 then Break;
      i := i + k - 1;
      while (i <= n) and (AHtml[i] <> '>') do Inc(i);
      Inc(i);
      Continue;
    end;
    OpenTag(tag, attrs, selfClose);
  end;
  AddText(text);
  { the end closes everything still open }
  while Length(FStack) > 1 do CloseTag(FStack[High(FStack)].Tag);
  FinishLine(False);
  { A GAP NOTHING FOLLOWS -- the last block's bottom margin, padding and
    border -- is still the box's: the container's padding stops it
    collapsing away. It is a spacer line: its gap and its rules, no line
    of its own. }
  if Length(FGap) > 0 then
  begin
    spacer := Default(TTyTooltipLine);
    spacer.Spacer := True;
    TakeGap(spacer);
    if (spacer.GapBeforeLogical > 0) or (Length(spacer.Rules) > 0) then
    begin
      SetLength(FLines, Length(FLines) + 1);
      FLines[High(FLines)] := spacer;
    end;
  end;
end;

function TyTooltipHtmlLines(const AHtml: string;
  const AInk: TTyTooltipInk): TTyTooltipLineArray;
var r: TReader;
begin
  r := TReader.Create(AInk);
  try
    r.Run(AHtml);
    Result := r.Lines;
  finally
    r.Free;
  end;
end;

{ ============================ [spec 237] the data view ============================ }

function TyHtmlPlainText(const AHtml: string; const ASep: string): string;
var
  lines: TTyTooltipLineArray;
  i, j, k: Integer;
  ln: string;
  first: Boolean;
begin
  Result := '';
  lines := TyTooltipHtmlLines(AHtml, Default(TTyTooltipInk));
  first := True;
  for i := 0 to High(lines) do
  begin
    if lines[i].Spacer then Continue;
    ln := '';
    for j := 0 to High(lines[i].Runs) do
      if lines[i].Runs[j].Kind = ttrText then ln := ln + lines[i].Runs[j].Text;
    { the empty lines a <br> left before this one }
    if not first then
      for k := 1 to lines[i].BlankLinesBefore do Result := Result + ASep;
    if not first then Result := Result + ASep;
    Result := Result + ln;
    first := False;
  end;
end;

type
  { where one cell's content lies in the html: Copy(html, S, E - S) }
  THtmlCellSpan = record
    S, E: Integer;
  end;
  THtmlRowSpans = array of THtmlCellSpan;
  { per table, per row (the header row too), per cell }
  THtmlSpans = array of array of THtmlRowSpans;

  { one table being read: its rows, whether each sat in a <thead> and was
    all <th>, and where its cells lie }
  THtmlTableAcc = record
    Caption: string;
    Rows: array of TTyStringArray;
    InHead, AllTh: array of Boolean;
    Spans: array of THtmlRowSpans;
  end;

function ReadHtmlTables(const AHtml: string; out AOutside: string;
  out ASpans: THtmlSpans): TTyChartDataViewTables;
var
  n, i, j, k, depth, tagStart, cellStart: Integer;
  tag, low: string;
  closing: Boolean;
  q: Char;
  acc: THtmlTableAcc;
  inRow, inCell, inCap, inHead, cellTh: Boolean;
  cellHtml, capHtml, chunk: string;

  procedure Add(const S: string);
  begin
    { a piece of the html: the cell's or the caption's when inside one,
      the outside text's when outside every table }
    if depth = 0 then AOutside := AOutside + S
    else if inCell then cellHtml := cellHtml + S
    else if inCap then capHtml := capHtml + S;
  end;

  procedure EndCell;
  var r: Integer;
  begin
    if not inCell then Exit;
    inCell := False;
    r := High(acc.Rows);
    SetLength(acc.Rows[r], Length(acc.Rows[r]) + 1);
    acc.Rows[r][High(acc.Rows[r])] := Trim(TyHtmlPlainText(cellHtml, ' '));
    SetLength(acc.Spans[r], Length(acc.Spans[r]) + 1);
    acc.Spans[r][High(acc.Spans[r])].S := cellStart;
    acc.Spans[r][High(acc.Spans[r])].E := tagStart;
    if not cellTh then acc.AllTh[r] := False;
    cellHtml := '';
  end;

  procedure StartRow;
  var r: Integer;
  begin
    EndCell;
    r := Length(acc.Rows);
    SetLength(acc.Rows, r + 1);
    SetLength(acc.InHead, r + 1);
    SetLength(acc.AllTh, r + 1);
    SetLength(acc.Spans, r + 1);
    acc.InHead[r] := inHead;
    acc.AllTh[r] := True;
    inRow := True;
  end;

  procedure EndRow;
  begin
    EndCell;
    inRow := False;
  end;

  procedure EndTable;
  var
    t, r, first: Integer;
  begin
    EndRow;
    t := Length(Result);
    SetLength(Result, t + 1);
    SetLength(ASpans, t + 1);
    ASpans[t] := acc.Spans;
    Result[t].Caption := acc.Caption;
    first := 0;
    if (Length(acc.Rows) > 0) and (Length(acc.Rows[0]) > 0)
      and (acc.InHead[0] or acc.AllTh[0]) then
    begin
      Result[t].Header := acc.Rows[0];
      first := 1;
    end;
    SetLength(Result[t].Rows, Length(acc.Rows) - first);
    for r := first to High(acc.Rows) do Result[t].Rows[r - first] := acc.Rows[r];
  end;

begin
  Result := nil;
  ASpans := nil;
  AOutside := '';
  n := Length(AHtml);
  low := LowerCase(AHtml);
  depth := 0;
  tagStart := 1;
  cellStart := 1;
  inRow := False;
  inCell := False;
  inCap := False;
  inHead := False;
  cellTh := False;
  cellHtml := '';
  capHtml := '';
  acc := Default(THtmlTableAcc);
  i := 1;
  while i <= n do
  begin
    if AHtml[i] <> '<' then
    begin
      j := i;
      while (j <= n) and (AHtml[j] <> '<') do Inc(j);
      Add(Copy(AHtml, i, j - i));
      i := j;
      Continue;
    end;
    tagStart := i;
    { a comment, a declaration: as written, where it stands }
    if Copy(AHtml, i, 4) = '<!--' then
    begin
      k := Pos('-->', Copy(AHtml, i + 4, MaxInt));
      if k = 0 then j := n + 1 else j := i + 4 + k + 2;
      Add(Copy(AHtml, i, j - i));
      i := j;
      Continue;
    end;
    closing := (i < n) and (AHtml[i + 1] = '/');
    j := i + 1;
    if closing then Inc(j);
    if (j > n) or not (AHtml[j] in ['a'..'z', 'A'..'Z']) then
    begin
      Add('<');
      Inc(i);
      Continue;
    end;
    k := j;
    while (k <= n) and not (AHtml[k] in [' ', #9, #10, #13, #12, '/', '>']) do Inc(k);
    tag := LowerCase(Copy(AHtml, j, k - j));
    while (k <= n) and (AHtml[k] <> '>') do
    begin
      if AHtml[k] in ['"', ''''] then
      begin
        q := AHtml[k];
        Inc(k);
        while (k <= n) and (AHtml[k] <> q) do Inc(k);
      end;
      Inc(k);
    end;
    chunk := Copy(AHtml, i, k - i + 1);
    i := k + 1;
    { a raw element (script, style ...): its content is no markup }
    if not closing and InList(tag, cRawTags) then
    begin
      k := Pos('</' + tag, Copy(low, i, MaxInt));
      if k = 0 then j := n + 1
      else
      begin
        j := i + k - 1;
        while (j <= n) and (AHtml[j] <> '>') do Inc(j);
        Inc(j);
      end;
      Add(chunk + Copy(AHtml, i, j - i));
      i := j;
      Continue;
    end;
    if tag = 'table' then
    begin
      if closing then
      begin
        if depth = 0 then Continue;
        if depth = 1 then
        begin
          EndTable;
          depth := 0;
          { the table was a block: the text on either side does not run
            together }
          AOutside := AOutside + '<div></div>';
        end
        else
        begin
          Add(chunk);
          Dec(depth);
        end;
      end
      else if depth = 0 then
      begin
        depth := 1;
        acc := Default(THtmlTableAcc);
        inRow := False;
        inCell := False;
        inCap := False;
        inHead := False;
        AOutside := AOutside + '<div></div>';
      end
      else
      begin
        Add(chunk);
        Inc(depth);
      end;
      Continue;
    end;
    if depth <> 1 then
    begin
      Add(chunk);
      Continue;
    end;
    { the outer table's own structure }
    if tag = 'caption' then
    begin
      if closing then
      begin
        if inCap then acc.Caption := Trim(TyHtmlPlainText(capHtml, ' '));
        inCap := False;
      end
      else
      begin
        EndRow;
        inCap := True;
        capHtml := '';
      end;
    end
    else if (tag = 'thead') or (tag = 'tbody') or (tag = 'tfoot') then
    begin
      EndRow;
      inHead := (tag = 'thead') and not closing;
    end
    else if tag = 'tr' then
    begin
      if closing then EndRow else StartRow;
    end
    else if (tag = 'td') or (tag = 'th') then
    begin
      if closing then EndCell
      else
      begin
        if not inRow then StartRow else EndCell;
        inCell := True;
        cellTh := tag = 'th';
        cellHtml := '';
        cellStart := i;
      end;
    end
    else
      Add(chunk);
  end;
  { an unclosed table ends with the text }
  tagStart := n + 1;
  if depth > 0 then EndTable;
end;

function TyHtmlTables(const AHtml: string;
  out AOutside: string): TTyChartDataViewTables;
var spans: THtmlSpans;
begin
  Result := ReadHtmlTables(AHtml, AOutside, spans);
end;

function TyHtmlSetCells(const AHtml: string;
  const ATables: TTyChartDataViewTables): string;
type
  TRepl = record
    S, E: Integer;
    Text: string;
  end;
var
  old: TTyChartDataViewTables;
  spans: THtmlSpans;
  outside: string;
  repl: array of TRepl;
  t, r, c, k, j: Integer;
  oldRows, newRows: TTyChartDataViewRows;
  tmp: TRepl;

  function AllRows(const ATable: TTyChartDataViewTable): TTyChartDataViewRows;
  var i: Integer;
  begin
    Result := nil;
    if Length(ATable.Header) > 0 then
    begin
      SetLength(Result, 1);
      Result[0] := ATable.Header;
    end;
    for i := 0 to High(ATable.Rows) do
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := ATable.Rows[i];
    end;
  end;

begin
  old := ReadHtmlTables(AHtml, outside, spans);
  repl := nil;
  for t := 0 to Min(High(old), High(ATables)) do
  begin
    oldRows := AllRows(old[t]);
    newRows := AllRows(ATables[t]);
    for r := 0 to Min(High(oldRows), High(newRows)) do
      for c := 0 to Min(High(oldRows[r]), High(newRows[r])) do
        if (newRows[r][c] <> oldRows[r][c]) and (r <= High(spans[t]))
          and (c <= High(spans[t][r])) then
        begin
          k := Length(repl);
          SetLength(repl, k + 1);
          repl[k].S := spans[t][r][c].S;
          repl[k].E := spans[t][r][c].E;
          repl[k].Text := TyTooltipEncodeHtml(newRows[r][c]);
        end;
  end;
  { the latest first, so the earlier places stand }
  for k := 1 to High(repl) do
  begin
    tmp := repl[k];
    j := k - 1;
    while (j >= 0) and (repl[j].S < tmp.S) do
    begin
      repl[j + 1] := repl[j];
      Dec(j);
    end;
    repl[j + 1] := tmp;
  end;
  Result := AHtml;
  for k := 0 to High(repl) do
    Result := Copy(Result, 1, repl[k].S - 1) + repl[k].Text
      + Copy(Result, repl[k].E, MaxInt);
end;

end.
