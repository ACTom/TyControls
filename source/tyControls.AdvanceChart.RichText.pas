unit tyControls.AdvanceChart.RichText;
{$mode objfpc}{$H+}
{ ZRENDER'S TEXT BLOCK: rich text and the plain text box.

  A zrender Text draws its words as a BLOCK -- lines of tokens, each token a
  run in its own style, with an optional box behind the whole block and one
  behind each token, padding, fixed widths and heights, percent widths,
  wrapping and truncation. Plain text (no `rich`) is the same block with one
  style and a simpler placement. This unit is that block, transcribed from
  zrender 6.1 (graphic/helper/parseText.ts parseRichText / parsePlainText /
  wrapText, graphic/Text.ts _updateRichTexts / _placeToken /
  _renderBackground / _updatePlainTexts), and nothing else: the styles it is
  given are the ones zrender would receive -- resolving an ECharts option
  into them is the caller's business.

  WHAT COMES OUT is the list of pieces zrender would paint, in its order: the
  block's rect (when it has one), then for each token in PLACEMENT order its
  rect and its text. Coordinates are local to the text's transform -- an
  attached label's anchor is (0, 0) and its rotation is applied by the
  caller to every piece alike, as zrender applies the Text's transform to
  its children.

  MEASURING goes through ITyTextMeasurer at a pixel size, and a font's
  height is the width of U+56FD, as zrender's getLineHeight takes it.

  LCL-free: SysUtils, Math and the AdvanceChart types. }
interface
uses
  SysUtils, Math,
  tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint;

{ THE STYLE, DEFAULT AND PIECE RECORDS LIVE IN AdvanceChart.Paint [Batch 86]: a
  caption carries its laid-out pieces from the label pass to the renderer,
  and the paint list is the layer both of them see. }
type
  { [R7-H] A VALUE zrender does JS arithmetic with: a number, or a string
    it was handed as written (a width '60'). N is the number -- a string's
    JS number, NaN for a word. }
  TTyRtJs = record
    IsStr: Boolean;
    S: string;
    N: Double;
  end;

  TTyRtToken = record
    StyleIndex: Integer;       // into the rich list; -1 the block style
    StyleName: string;
    Text: string;
    IsLineHolder: Boolean;
    FontFamily: string;
    FontSizePx: Double;
    FontWeight: Integer;
    Width, Height, InnerHeight, ContentWidth, ContentHeight, LineHeight: Double;
    Align: TTyRtAlign;
    VAlign: TTyRtVAlign;
    HasPadding: Boolean;
    Padding: array[0..3] of Double;
    IsPercent: Boolean;
    Percent: Double;
    { [R7-H] the height (padding in) and the line height as zrender holds
      them: a string height stays one ('16' + 4 = '164') }
    HeightV, LineHeightV: TTyRtJs;
  end;
  TTyRtLine = record
    Tokens: array of TTyRtToken;
    Width, LineHeight: Double;
  end;

  TTyRtBlock = record
    Lines: array of TTyRtLine;
    Width, Height, ContentWidth, ContentHeight, OuterWidth, OuterHeight: Double;
    IsTruncated: Boolean;
    { [R7-H] the width, height and outer sizes as zrender holds them }
    WidthV, HeightV, OuterWidthV, OuterHeightV: TTyRtJs;
  end;

  TTyRtResult = record
    Block: TTyRtBlock;
    Pieces: TTyRtPieceArray;
    { the outer box, in the same local frame }
    BoxX, BoxY, BoxW, BoxH: Double;
  end;

{ A style with nothing set: 12px sans-serif, normal, no box. }
function TyRtStyleDefault: TTyRtStyle;

{ THE BLOCK AND ITS PIECES. ARich: the text takes the rich path (zrender
  chooses it whenever `style.rich` is set, tokens or not). ABaseX/Y: the
  text's own x/y -- 0, 0 for an attached label. }
function TyRtLayout(const AText: string; const AStyle: TTyRtStyle;
  const ARichStyles: TTyRtRich; ARich: Boolean; const ADefault: TTyRtDefault;
  ABaseX, ABaseY: Double; const AMeasurer: ITyTextMeasurer): TTyRtResult;

{ [R7-H] whether the block or a rich style holds a width, height or line
  height written as a string: the only styles whose layout can meet NaN or
  join a size to a place }
function TyRtHasStringSize(const AStyle: TTyRtStyle; const ARich: TTyRtRich): Boolean;

{ [R7-H] roundRect.ts' corner radii, each at least 0 and each pair cut down
  to fit the rect's size as numbers (AW, AH; NaN cuts nothing) }
procedure TyRtClampRadii(AW, AH: Double; var R1, R2, R3, R4: Double);

{ [R7-H] THE PATH'S OWN BOUNDS of a rect piece whose size was a string
  (PathEdges): zrender's path runs to the joined edges -- a plain rect's
  fromLine(x, y, x + w, y + h), a rounded one's corners and arcs -- so its
  bounds are those, not the rect canvas draws. False for any other piece. }
function TyRtPathBounds(const APiece: TTyRtPiece; out AX0, AY0, AX1, AY1: Double): Boolean;

{ [R7-L] ZRENDER'S Text.getBoundingRect OF THE TEXT AS LAID OUT, before
  anything at NaN is dropped: each child's own box -- a rect's path bounds
  (PathProxy's fromLine, Math.min / max: NaN where a corner is), grown by a
  stroke; a TSpan's at `style.x || 0`, `style.y || 0` (a TSpan at NaN is
  bounded where it would stand at 0) -- unioned as BoundingRect.union does
  it (Math.min; once the box's x or width is not finite, the other's width).
  The box may hold NaN: an x, y, width or height upstream reads as NaN is
  NaN here, for a label layout that compares it as JS does. A text with no
  string size is TyRtBounds' box in every finite case but the last bit. The
  traps are masked inside. }
function TyRtLayoutJsBox(const AText: string; const AStyle: TTyRtStyle;
  const ARichStyles: TTyRtRich; ARich: Boolean; const ADefault: TTyRtDefault;
  ABaseX, ABaseY: Double; const AMeasurer: ITyTextMeasurer): TTyXYWH;
{ [R7-L] whether AR holds a NaN or an infinity }
function TyRtBoxIsFinite(const AR: TTyXYWH): Boolean;

{ WHETHER THE TEXT HOLDS A TAG zrender's parser takes -- a name of letters,
  digits and underscores, a bar, and a closing brace somewhere after it. A
  text without one lays out the same rich or plain. [Batch 104] }
function TyRtHasMarkup(const AText: string): Boolean;

implementation

uses tyControls.FontUnits, tyControls.AdvanceChart.Labels, tyControls.AdvanceChart.Symbol,
  tyControls.AdvanceChart.Data, tyControls.AdvanceChart.Scale;

const
  cGuo = #$E5#$9B#$BD;   // U+56FD: zrender's measure of a font's height

function TyRtStyleDefault: TTyRtStyle;
begin
  Result := Default(TTyRtStyle);
  Result.FontFamily := 'sans-serif';
  Result.FontSizePx := 12;
  Result.FontWeight := 400;
end;

{ ---- [R7-H] JS values ---- }

function JNum(A: Double): TTyRtJs;
begin
  Result.IsStr := False;
  Result.S := '';
  Result.N := A;
end;

function JStr(const A: string): TTyRtJs;
begin
  Result.IsStr := True;
  Result.S := A;
  Result.N := TyJsToNumber(A);
end;

function JText(const A: TTyRtJs): string;
begin
  if A.IsStr then Result := A.S else Result := TyJsNumberToString(A.N);
end;

{ `a + b`: joined when either is a string, else the sum }
function JAdd(const A, B: TTyRtJs): TTyRtJs;
begin
  if A.IsStr or B.IsStr then Result := JStr(JText(A) + JText(B))
  else Result := JNum(A.N + B.N);
end;

{ `a > b`: two strings compare as strings, else as numbers (false against
  NaN -- the caller has the traps masked) }
function JGreater(const A, B: TTyRtJs): Boolean;
begin
  if A.IsStr and B.IsStr then Result := UnicodeString(UTF8Decode(A.S)) > UnicodeString(UTF8Decode(B.S))
  else Result := A.N > B.N;
end;

{ Math.max: NaN when either is }
function JsMax(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if A > B then Result := A else Result := B;
end;

{ Math.min: NaN when either is }
function JsMin(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if A < B then Result := A else Result := B;
end;

{ parseInt(AText, 10) }
function JsParseInt(const AText: string): Double;
var
  i, j: Integer;
  neg: Boolean;
begin
  i := 1;
  while (i <= Length(AText)) and (AText[i] in [' ', #9, #10, #11, #12, #13]) do Inc(i);
  neg := False;
  if (i <= Length(AText)) and (AText[i] in ['+', '-']) then
  begin
    neg := AText[i] = '-';
    Inc(i);
  end;
  j := i;
  Result := 0;
  while (j <= Length(AText)) and (AText[j] in ['0'..'9']) do
  begin
    Result := Result * 10 + (Ord(AText[j]) - Ord('0'));
    Inc(j);
  end;
  if j = i then Exit(NaN);
  if neg then Result := -Result;
end;

{ the block's width, height and line height as zrender is handed them: a
  number, a string, or nothing (AHas False). A site's own number
  (rtwNumber) wins over the text it replaced. }
function BlockWidthOf(const S: TTyRtStyle; out AHas: Boolean): TTyRtJs;
begin
  AHas := True;
  if S.WidthKind = rtwNumber then Exit(JNum(S.Width));
  if S.WidthIsText and (S.WidthKind <> rtwNone) then Exit(JStr(S.WidthText));
  AHas := False;
  Result := JNum(0);
end;

function HeightOf(const S: TTyRtStyle): TTyRtJs;
begin
  if S.HeightIsText then Result := JStr(S.HeightText) else Result := JNum(S.Height);
end;

function LineHeightOf(const S: TTyRtStyle): TTyRtJs;
begin
  if S.LineHeightIsText then Result := JStr(S.LineHeightText) else Result := JNum(S.LineHeight);
end;

{ whether anything of the style is a string: only then can the layout meet
  NaN, and only then are the traps masked }
function AnyText(const S: TTyRtStyle; const ARich: TTyRtRich): Boolean;
var i: Integer;
begin
  Result := TyRtHasStringSize(S, ARich);
end;

function TyRtHasStringSize(const AStyle: TTyRtStyle; const ARich: TTyRtRich): Boolean;
var i: Integer;
begin
  Result := AStyle.WidthIsText or AStyle.HeightIsText or AStyle.LineHeightIsText;
  for i := 0 to High(ARich) do
    if ARich[i].Style.WidthIsText or ARich[i].Style.HeightIsText
      or ARich[i].Style.LineHeightIsText then Exit(True);
end;

function Fin(A: Double): Boolean; inline;
begin
  Result := not (IsNan(A) or IsInfinite(A));
end;

{ the ellipsis a truncation appends: the style's, else '...' }
function EllipsisOf(const S: TTyRtStyle): string;
begin
  if S.HasEllipsis then Result := S.Ellipsis else Result := '...';
end;

{ ---- measuring ---- }

function MeasureW(const AMeasurer: ITyTextMeasurer; const AText, AFamily: string;
  APx: Double; AWeight: Integer): Double;
var h: Double;
begin
  Result := 0;
  if (AText = '') or (AMeasurer = nil) then Exit;
  AMeasurer.MeasureLine(AText, AFamily, TyFontSizeFromPx(APx), AWeight, Result, h);
end;

function FontHeight(const AMeasurer: ITyTextMeasurer; const AFamily: string;
  APx: Double; AWeight: Integer): Double;
begin
  Result := MeasureW(AMeasurer, cGuo, AFamily, APx, AWeight);
end;

{ ---- wrapText (parseText.ts 706-841) ---- }

type
  TWrapResult = record
    AccumWidth: Double;
    Lines: array of string;
    Widths: array of Double;
  end;

function IsWordBreakCode(ACode: Integer): Boolean;
begin
  { "alphabetic" ranges are words; everything else, and these, break }
  if (ACode = Ord(',')) or (ACode = Ord('&')) or (ACode = Ord('?'))
    or (ACode = Ord('/')) or (ACode = Ord(';')) or (ACode = Ord(']'))
    or (ACode = Ord(' ')) then Exit(True);
  Result := not (((ACode >= $20) and (ACode <= $24F))
    or ((ACode >= $370) and (ACode <= $10FF))
    or ((ACode >= $1200) and (ACode <= $13FF))
    or ((ACode >= $1E00) and (ACode <= $206F)));
end;

function WrapText(const AText, AFamily: string; APx: Double; AWeight: Integer;
  ALineWidth: Double; ABreakAll: Boolean; ALastAccum: Double;
  const AMeasurer: ITyTextMeasurer): TWrapResult;
var
  u: UnicodeString;
  i, code: Integer;
  ch: UnicodeString;
  line, currentWord: UnicodeString;
  currentWordWidth, accumWidth, chWidth: Double;
  inWord, over: Boolean;

  procedure Push(const S: UnicodeString; AW: Double);
  begin
    SetLength(Result.Lines, Length(Result.Lines) + 1);
    Result.Lines[High(Result.Lines)] := UTF8Encode(S);
    SetLength(Result.Widths, Length(Result.Widths) + 1);
    Result.Widths[High(Result.Widths)] := AW;
  end;

  function CharW(ACode: Integer; const S: UnicodeString): Double;
  begin
    if (ACode >= 0) and (ACode <= 127) then
      Result := MeasureW(AMeasurer, UTF8Encode(S), AFamily, APx, AWeight)
    else
      Result := MeasureW(AMeasurer, cGuo, AFamily, APx, AWeight);
    { a control character is one whole size, as zrender's table has it }
    if (ACode < 32) or (ACode = 127) then Result := APx;
  end;

begin
  Result := Default(TWrapResult);
  u := UTF8Decode(AText);
  line := '';
  currentWord := '';
  currentWordWidth := 0;
  accumWidth := 0;
  for i := 1 to Length(u) do
  begin
    ch := u[i];
    code := Ord(u[i]);
    if ch = #10 then
    begin
      if currentWord <> '' then
      begin
        line := line + currentWord;
        accumWidth := accumWidth + currentWordWidth;
      end;
      Push(line, accumWidth);
      line := '';
      currentWord := '';
      currentWordWidth := 0;
      accumWidth := 0;
      Continue;
    end;
    chWidth := CharW(code, ch);
    if ABreakAll then inWord := False else inWord := not IsWordBreakCode(code);
    if Length(Result.Lines) = 0 then
      over := ALastAccum + accumWidth + chWidth > ALineWidth
    else
      over := accumWidth + chWidth > ALineWidth;
    if over then
    begin
      if accumWidth = 0 then
      begin
        if inWord then
        begin
          Push(currentWord, currentWordWidth);
          currentWord := ch;
          currentWordWidth := chWidth;
        end
        else
          Push(ch, chWidth);
      end
      else if (line <> '') or (currentWord <> '') then
      begin
        if inWord then
        begin
          if line = '' then
          begin
            line := currentWord;
            currentWord := '';
            currentWordWidth := 0;
            accumWidth := currentWordWidth;
          end;
          Push(line, accumWidth - currentWordWidth);
          currentWord := currentWord + ch;
          currentWordWidth := currentWordWidth + chWidth;
          line := '';
          accumWidth := currentWordWidth;
        end
        else
        begin
          if currentWord <> '' then
          begin
            line := line + currentWord;
            currentWord := '';
            currentWordWidth := 0;
          end;
          Push(line, accumWidth);
          line := ch;
          accumWidth := chWidth;
        end;
      end;
      Continue;
    end;
    accumWidth := accumWidth + chWidth;
    if inWord then
    begin
      currentWord := currentWord + ch;
      currentWordWidth := currentWordWidth + chWidth;
    end
    else
    begin
      if currentWord <> '' then
      begin
        line := line + currentWord;
        currentWord := '';
        currentWordWidth := 0;
      end;
      line := line + ch;
    end;
  end;
  if currentWord <> '' then line := line + currentWord;
  if line <> '' then Push(line, accumWidth);
  if Length(Result.Lines) = 1 then accumWidth := accumWidth + ALastAccum;
  Result.AccumWidth := accumWidth;
end;

{ ---- styles ---- }

function StyleOf(const ARich: TTyRtRich; AIndex: Integer; const ABlock: TTyRtStyle;
  out AFound: Boolean): TTyRtStyle;
begin
  AFound := (AIndex >= 0) and (AIndex <= High(ARich));
  if AFound then Result := ARich[AIndex].Style
  else Result := Default(TTyRtStyle);
end;

{ the token's font: its own when it named one, else the block's -- ECharts
  always hands a rich style its four font parts, so FontSizePx > 0 marks it }
procedure TokenFont(const ATokenStyle: TTyRtStyle; AFound: Boolean;
  const ABlock: TTyRtStyle; out AFamily: string; out APx: Double; out AWeight: Integer);
begin
  if AFound and (ATokenStyle.FontSizePx > 0) then
  begin
    AFamily := ATokenStyle.FontFamily;
    APx := ATokenStyle.FontSizePx;
    AWeight := ATokenStyle.FontWeight;
  end
  else
  begin
    AFamily := ABlock.FontFamily;
    APx := ABlock.FontSizePx;
    AWeight := ABlock.FontWeight;
  end;
end;

function IndexOfName(const ARich: TTyRtRich; const AName: string): Integer;
var i: Integer;
begin
  for i := 0 to High(ARich) do
    if ARich[i].Name = AName then Exit(i);
  Result := -1;
end;

{ ---- parseRichText (parseText.ts 385-580) ---- }

type
  TWrapInfo = record
    Active: Boolean;
    Width, AccumWidth: Double;
    BreakAll: Boolean;
  end;

procedure PushTokens(var ABlock: TTyRtBlock; const AStr: string;
  const AStyle: TTyRtStyle; const ARich: TTyRtRich; var AWrap: TWrapInfo;
  AStyleIndex: Integer; const AStyleName: string; const AMeasurer: ITyTextMeasurer);
var
  ts: TTyRtStyle;
  found, newLine, isEmptyStr: Boolean;
  strLines: array of string;
  widths: array of Double;
  hasWidths: Boolean;
  fam: string;
  px, padH, outerW: Double;
  wt, i, n, k: Integer;
  tok: TTyRtToken;
  wr: TWrapResult;
  parts: TStringArray;
begin
  isEmptyStr := AStr = '';
  ts := StyleOf(ARich, AStyleIndex, AStyle, found);
  TokenFont(ts, found, AStyle, fam, px, wt);
  newLine := False;
  hasWidths := False;
  strLines := nil;
  widths := nil;
  if AWrap.Active then
  begin
    if found and ts.HasPadding then padH := ts.Padding[1] + ts.Padding[3]
    else padH := 0;
    { `tokenStyle.width != null && !== 'auto'`: parsePercent of it -- a
      percentage parseFloat / 100 of the wrap's width, any other string its
      parseFloat [R7-H: was a number or a percentage only] }
    if found and (ts.WidthKind in [rtwNumber, rtwPercent, rtwText]) then
    begin
      if ts.WidthKind = rtwPercent then outerW := ts.Width / 100 * AWrap.Width + padH
      else if ts.WidthKind = rtwText then outerW := TyJsParseFloat(ts.WidthText) + padH
      else outerW := ts.Width + padH;
      if (Length(ABlock.Lines) > 0) and (outerW + AWrap.AccumWidth > AWrap.Width) then
        newLine := True;
      AWrap.AccumWidth := outerW;
    end
    else
    begin
      wr := WrapText(AStr, fam, px, wt, AWrap.Width, AWrap.BreakAll,
        AWrap.AccumWidth, AMeasurer);
      AWrap.AccumWidth := wr.AccumWidth + padH;
      SetLength(strLines, Length(wr.Lines));
      for k := 0 to High(wr.Lines) do strLines[k] := wr.Lines[k];
      widths := Copy(wr.Widths);
      hasWidths := True;
    end;
  end;
  if not hasWidths then
  begin
    parts := AStr.Split([#10]);
    SetLength(strLines, Length(parts));
    for k := 0 to High(parts) do strLines[k] := parts[k];
    if Length(parts) = 0 then
    begin
      SetLength(strLines, 1);
      strLines[0] := '';
    end;
  end;
  for i := 0 to High(strLines) do
  begin
    tok := Default(TTyRtToken);
    tok.StyleIndex := AStyleIndex;
    tok.StyleName := AStyleName;
    tok.Text := strLines[i];
    tok.IsLineHolder := (tok.Text = '') and not isEmptyStr;
    if found and (ts.WidthKind = rtwNumber) then tok.Width := ts.Width
    else if hasWidths and (i <= High(widths)) then tok.Width := widths[i]
    else tok.Width := MeasureW(AMeasurer, tok.Text, fam, px, wt);
    if (i = 0) and not newLine then
    begin
      if Length(ABlock.Lines) = 0 then SetLength(ABlock.Lines, 1);
      n := Length(ABlock.Lines[High(ABlock.Lines)].Tokens);
      if (n = 1) and ABlock.Lines[High(ABlock.Lines)].Tokens[0].IsLineHolder then
        ABlock.Lines[High(ABlock.Lines)].Tokens[0] := tok
      else if (tok.Text <> '') or (n = 0) or isEmptyStr then
      begin
        SetLength(ABlock.Lines[High(ABlock.Lines)].Tokens, n + 1);
        ABlock.Lines[High(ABlock.Lines)].Tokens[n] := tok;
      end;
    end
    else
    begin
      SetLength(ABlock.Lines, Length(ABlock.Lines) + 1);
      SetLength(ABlock.Lines[High(ABlock.Lines)].Tokens, 1);
      ABlock.Lines[High(ABlock.Lines)].Tokens[0] := tok;
    end;
  end;
end;

// STYLE_REG = /\{([a-zA-Z0-9_]+)\|([^}]*)\}/g, walked as exec walks it
procedure Tokenise(var ABlock: TTyRtBlock; const AText: string;
  const AStyle: TTyRtStyle; const ARich: TTyRtRich; var AWrap: TWrapInfo;
  const AMeasurer: ITyTextMeasurer);
var
  pos, lastIndex, k, nameEnd, close: Integer;
  name: string;
  matched: Boolean;
begin
  lastIndex := 1;
  pos := 1;
  while pos <= Length(AText) do
  begin
    matched := False;
    if AText[pos] = '{' then
    begin
      k := pos + 1;
      while (k <= Length(AText)) and (AText[k] in ['a'..'z', 'A'..'Z', '0'..'9', '_']) do
        Inc(k);
      nameEnd := k;
      if (nameEnd > pos + 1) and (nameEnd <= Length(AText)) and (AText[nameEnd] = '|') then
      begin
        close := nameEnd + 1;
        while (close <= Length(AText)) and (AText[close] <> '}') do Inc(close);
        if close <= Length(AText) then
        begin
          matched := True;
          name := Copy(AText, pos + 1, nameEnd - pos - 1);
          if pos > lastIndex then
            PushTokens(ABlock, Copy(AText, lastIndex, pos - lastIndex), AStyle, ARich,
              AWrap, -1, '', AMeasurer);
          PushTokens(ABlock, Copy(AText, nameEnd + 1, close - nameEnd - 1), AStyle,
            ARich, AWrap, IndexOfName(ARich, name), name, AMeasurer);
          lastIndex := close + 1;
          pos := close + 1;
        end;
      end;
    end;
    if not matched then Inc(pos);
  end;
  if lastIndex <= Length(AText) then
    PushTokens(ABlock, Copy(AText, lastIndex, MaxInt), AStyle, ARich, AWrap, -1, '',
      AMeasurer);
end;

function LayoutIn(const AText: string; const AStyle: TTyRtStyle;
  const ARichStyles: TTyRtRich; ARich: Boolean; const ADefault: TTyRtDefault;
  ABaseX, ABaseY: Double; const AMeasurer: ITyTextMeasurer): TTyRtResult; forward;

function TyRtLayout(const AText: string; const AStyle: TTyRtStyle;
  const ARichStyles: TTyRtRich; ARich: Boolean; const ADefault: TTyRtDefault;
  ABaseX, ABaseY: Double; const AMeasurer: ITyTextMeasurer): TTyRtResult;
var
  mask: TFPUExceptionMask;
  i, n: Integer;
  keep: Boolean;
begin
  { [R7-H] A STRING SIZE CAN LAY THE TEXT OUT AT NaN, and JS compares NaN
    as false where FPC traps: the layout then runs with the traps masked,
    and what is laid out at NaN -- not drawn by canvas -- is dropped on the
    way out, so no NaN leaves the engine. }
  if not AnyText(AStyle, ARichStyles) then
    Exit(LayoutIn(AText, AStyle, ARichStyles, ARich, ADefault, ABaseX, ABaseY,
      AMeasurer));
  mask := SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
    exOverflow, exUnderflow, exPrecision]);
  try
    Result := LayoutIn(AText, AStyle, ARichStyles, ARich, ADefault, ABaseX,
      ABaseY, AMeasurer);
    n := 0;
    for i := 0 to High(Result.Pieces) do
    begin
      with Result.Pieces[i] do
        if Kind = rpkRect then
          { [R7-L] canvas draws an unrounded rect at its numbers (rect()
            takes '-600' as -600); the rounded path runs through the
            joined edges, and at NaN nothing is drawn }
          keep := Fin(X) and Fin(Y) and Fin(W) and Fin(H)
            and (not (PathEdges and Rounded) or (Fin(EdgeX1) and Fin(EdgeY1)))
        else
          keep := Fin(X) and Fin(Y);
      if not keep then Continue;
      Result.Pieces[n] := Result.Pieces[i];
      Inc(n);
    end;
    SetLength(Result.Pieces, n);
    if not (Fin(Result.BoxX) and Fin(Result.BoxY) and Fin(Result.BoxW)
      and Fin(Result.BoxH)) then
    begin
      Result.BoxX := 0;
      Result.BoxY := 0;
      Result.BoxW := 0;
      Result.BoxH := 0;
    end;
  finally
    ClearExceptions(False);
    {$IFDEF CPUX86_64}
    { and the SSE flags ClearExceptions leaves on this CPU (Graph.pas
      UnmaskFP) }
    SetMXCSR(GetMXCSR and not LongWord($3F));
    {$ENDIF}
    SetExceptionMask(mask);
  end;
end;

procedure TyRtClampRadii(AW, AH: Double; var R1, R2, R3, R4: Double);
var total: Double;
begin
  R1 := Max(0.0, R1);
  R2 := Max(0.0, R2);
  R3 := Max(0.0, R3);
  R4 := Max(0.0, R4);
  if IsNan(AW) or IsNan(AH) then Exit;
  total := R1 + R2;
  if total > AW then begin R1 := R1 * AW / total; R2 := R2 * AW / total; end;
  total := R3 + R4;
  if total > AW then begin R3 := R3 * AW / total; R4 := R4 * AW / total; end;
  total := R2 + R3;
  if total > AH then begin R2 := R2 * AH / total; R3 := R3 * AH / total; end;
  total := R1 + R4;
  if total > AH then begin R1 := R1 * AH / total; R4 := R4 * AH / total; end;
end;

function TyRtPathBounds(const APiece: TTyRtPiece; out AX0, AY0, AX1, AY1: Double): Boolean;
var
  r1, r2, r3, r4: Double;
  xs, ys: array[0..5] of Double;
  k: Integer;
begin
  { [R7-L] an unrounded rect whose joined edge is NaN (a negative numeric
    string) is canvas' rect at its numbers: no path bounds here (they are
    NaN upstream -- TyRtLayoutJsBox has them) }
  Result := (APiece.Kind = rpkRect) and APiece.PathEdges
    and Fin(APiece.EdgeX1) and Fin(APiece.EdgeY1);
  AX0 := 0; AY0 := 0; AX1 := 0; AY1 := 0;
  if not Result then Exit;
  r1 := APiece.Radius[0];
  r2 := APiece.Radius[1];
  r3 := APiece.Radius[2];
  r4 := APiece.Radius[3];
  { [R7-L] the rounded path whenever borderRadius is truthy ([0, 0] too) }
  if not APiece.Rounded and (r1 + r2 + r3 + r4 <= 0) then
  begin
    { Rect.buildPath with no radius: ctx.rect, whose path is fromLine }
    AX0 := Min(APiece.X, APiece.EdgeX1);
    AX1 := Max(APiece.X, APiece.EdgeX1);
    AY0 := Min(APiece.Y, APiece.EdgeY1);
    AY1 := Max(APiece.Y, APiece.EdgeY1);
    Exit;
  end;
  TyRtClampRadii(APiece.W, APiece.H, r1, r2, r3, r4);
  { the corners' points; each arc is a quarter turn between two of them }
  xs[0] := APiece.X; xs[1] := APiece.X + r1; xs[2] := APiece.X + r4;
  xs[3] := APiece.EdgeX1; xs[4] := APiece.EdgeX1 - r2; xs[5] := APiece.EdgeX1 - r3;
  ys[0] := APiece.Y; ys[1] := APiece.Y + r1; ys[2] := APiece.Y + r2;
  ys[3] := APiece.EdgeY1; ys[4] := APiece.EdgeY1 - r3; ys[5] := APiece.EdgeY1 - r4;
  AX0 := xs[0]; AX1 := xs[0]; AY0 := ys[0]; AY1 := ys[0];
  for k := 1 to 5 do
  begin
    AX0 := Min(AX0, xs[k]); AX1 := Max(AX1, xs[k]);
    AY0 := Min(AY0, ys[k]); AY1 := Max(AY1, ys[k]);
  end;
end;

function TyRtBoxIsFinite(const AR: TTyXYWH): Boolean;
begin
  Result := Fin(AR.X) and Fin(AR.Y) and Fin(AR.W) and Fin(AR.H);
end;

function AdjustX(AX, AW: Double; AAlign: TTyRtAlign): Double; forward;

{ a child's own box, as zrender bounds it (see TyRtLayoutJsBox); traps
  masked }
procedure PieceJsBox(const P: TTyRtPiece; out AX, AY, AW, AH: Double);
var
  x0, y0, x1, y1, ex, ey, r1, r2, r3, r4, g: Double;
  xs, ys: array[0..5] of Double;
  k: Integer;
begin
  if P.Kind = rpkRect then
  begin
    { the rect's path: fromLine(x, y, x + w, y + h); a size that was a
      string joins its edge (EdgeX1 / EdgeY1) }
    if P.PathEdges then
    begin
      ex := P.EdgeX1;
      ey := P.EdgeY1;
    end
    else
    begin
      ex := P.X + P.W;
      ey := P.Y + P.H;
    end;
    r1 := P.Radius[0]; r2 := P.Radius[1]; r3 := P.Radius[2]; r4 := P.Radius[3];
    if P.PathEdges and (P.Rounded or (r1 + r2 + r3 + r4 > 0)) then
    begin
      { a rounded one runs through its corners' points (TyRtPathBounds) }
      TyRtClampRadii(P.W, P.H, r1, r2, r3, r4);
      xs[0] := P.X; xs[1] := P.X + r1; xs[2] := P.X + r4;
      xs[3] := ex; xs[4] := ex - r2; xs[5] := ex - r3;
      ys[0] := P.Y; ys[1] := P.Y + r1; ys[2] := P.Y + r2;
      ys[3] := ey; ys[4] := ey - r3; ys[5] := ey - r4;
      x0 := xs[0]; x1 := xs[0]; y0 := ys[0]; y1 := ys[0];
      for k := 1 to 5 do
      begin
        x0 := JsMin(x0, xs[k]); x1 := JsMax(x1, xs[k]);
        y0 := JsMin(y0, ys[k]); y1 := JsMax(y1, ys[k]);
      end;
    end
    else
    begin
      x0 := JsMin(P.X, ex); x1 := JsMax(P.X, ex);
      y0 := JsMin(P.Y, ey); y1 := JsMax(P.Y, ey);
    end;
    AX := x0;
    AY := y0;
    AW := x1 - x0;
    AH := y1 - y0;
    { Path.getBoundingRect: the stroke, strokeContainThreshold 0 }
    if P.HasStroke and (P.LineWidth > 0) then
    begin
      g := P.LineWidth;
      AX := AX - g / 2;
      AY := AY - g / 2;
      AW := AW + g;
      AH := AH + g;
    end;
  end
  else
  begin
    { tSpanCreateBoundingRect2: style.x || 0 }
    AW := P.W;
    AH := P.H;
    if IsNan(P.X) then AX := AdjustX(0, AW, P.TextAlign)
    else AX := AdjustX(P.X, AW, P.TextAlign);
    if IsNan(P.Y) then AY := 0 - AH / 2 else AY := P.Y - AH / 2;
    if P.HasStroke and not P.DefaultStroke and (P.LineWidth > 0) then
    begin
      g := P.LineWidth;
      AX := AX - g / 2;
      AY := AY - g / 2;
      AW := AW + g;
      AH := AH + g;
    end;
  end;
end;

function TyRtLayoutJsBox(const AText: string; const AStyle: TTyRtStyle;
  const ARichStyles: TTyRtRich; ARich: Boolean; const ADefault: TTyRtDefault;
  ABaseX, ABaseY: Double; const AMeasurer: ITyTextMeasurer): TTyXYWH;
var
  mask: TFPUExceptionMask;
  res: TTyRtResult;
  i: Integer;
  bx, by, bw, bh, x, y: Double;
  any: Boolean;

  procedure Union(OX, OY, OW, OH: Double);
  begin
    { BoundingRect.union, `this` the box so far }
    x := JsMin(OX, Result.X);
    y := JsMin(OY, Result.Y);
    if Fin(Result.X) and Fin(Result.W) then
      Result.W := JsMax(OX + OW, Result.X + Result.W) - x
    else
      Result.W := OW;
    if Fin(Result.Y) and Fin(Result.H) then
      Result.H := JsMax(OY + OH, Result.Y + Result.H) - y
    else
      Result.H := OH;
    Result.X := x;
    Result.Y := y;
  end;

begin
  Result.X := 0; Result.Y := 0; Result.W := 0; Result.H := 0;
  mask := SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
    exOverflow, exUnderflow, exPrecision]);
  try
    res := LayoutIn(AText, AStyle, ARichStyles, ARich, ADefault, ABaseX, ABaseY,
      AMeasurer);
    any := False;
    for i := 0 to High(res.Pieces) do
    begin
      PieceJsBox(res.Pieces[i], bx, by, bw, bh);
      if not any then
      begin
        Result.X := bx; Result.Y := by; Result.W := bw; Result.H := bh;
        any := True;
      end;
      Union(bx, by, bw, bh);
    end;
  finally
    ClearExceptions(False);
    {$IFDEF CPUX86_64}
    SetMXCSR(GetMXCSR and not LongWord($3F));
    {$ENDIF}
    SetExceptionMask(mask);
  end;
end;

function TyRtHasMarkup(const AText: string): Boolean;
var pos, k, close: Integer;
begin
  Result := False;
  for pos := 1 to Length(AText) do
  begin
    if AText[pos] <> '{' then Continue;
    k := pos + 1;
    while (k <= Length(AText)) and (AText[k] in ['a'..'z', 'A'..'Z', '0'..'9', '_']) do
      Inc(k);
    if (k = pos + 1) or (k > Length(AText)) or (AText[k] <> '|') then Continue;
    close := k + 1;
    while (close <= Length(AText)) and (AText[close] <> '}') do Inc(close);
    if close <= Length(AText) then Exit(True);
  end;
end;

function ParseRich(const AText: string; const AStyle: TTyRtStyle;
  const ARich: TTyRtRich; ATopAlign: TTyRtAlign;
  const AMeasurer: ITyTextMeasurer): TTyRtBlock;
var
  wrap: TWrapInfo;
  i, j, k: Integer;
  lnH, lnW, calcH, calcW, padH, remain, iw, ih: Double;
  ts: TTyRtStyle;
  found, truncLine, stop: Boolean;
  fam: string;
  px: Double;
  wt: Integer;
  cut: TStringArray;
  pending: array of record L, T: Integer; end;
  topW, topH, th: TTyRtJs;
  hasTopW: Boolean;
begin
  Result := Default(TTyRtBlock);
  Result.WidthV := JNum(0);
  Result.HeightV := JNum(0);
  Result.OuterWidthV := JNum(0);
  Result.OuterHeightV := JNum(0);
  if AText = '' then Exit;
  { [R7-H] topWidth / topHeight as written: a string stays one }
  topW := BlockWidthOf(AStyle, hasTopW);
  topH := HeightOf(AStyle);
  wrap := Default(TWrapInfo);
  wrap.Active := (AStyle.Overflow in [rtoBreak, rtoBreakAll]) and hasTopW;
  if wrap.Active then
  begin
    wrap.Width := topW.N;
    wrap.BreakAll := AStyle.Overflow = rtoBreakAll;
  end;
  Tokenise(Result, AText, AStyle, ARich, wrap, AMeasurer);
  calcH := 0;
  calcW := 0;
  pending := nil;
  truncLine := AStyle.LineOverflowTruncate;
  stop := False;
  for i := 0 to High(Result.Lines) do
  begin
    lnH := 0;
    lnW := 0;
    for j := 0 to High(Result.Lines[i].Tokens) do
    begin
      with Result.Lines[i].Tokens[j] do
      begin
        ts := StyleOf(ARich, StyleIndex, AStyle, found);
        HasPadding := found and ts.HasPadding;
        if HasPadding then
        begin
          for k := 0 to 3 do Padding[k] := ts.Padding[k];
          padH := Padding[1] + Padding[3];
        end
        else
          padH := 0;
        TokenFont(ts, found, AStyle, fam, px, wt);
        FontFamily := fam;
        FontSizePx := px;
        FontWeight := wt;
        ContentHeight := FontHeight(AMeasurer, fam, px, wt);
        { [R7-H] retrieve2(tokenStyle.height, contentHeight), the padding
          ADDED to it (a string height joins it) }
        if found and ts.HasHeight then th := HeightOf(ts)
        else th := JNum(ContentHeight);
        InnerHeight := th.N;
        if HasPadding then th := JAdd(th, JNum(Padding[0] + Padding[2]));
        HeightV := th;
        Height := th.N;
        { retrieve3(tokenStyle.lineHeight, style.lineHeight, tokenHeight) }
        if found and ts.HasLineHeight then LineHeightV := LineHeightOf(ts)
        else if AStyle.HasLineHeight then LineHeightV := LineHeightOf(AStyle)
        else LineHeightV := th;
        LineHeight := LineHeightV.N;
        if found and (ts.Align <> rtaNone) then Align := ts.Align else Align := ATopAlign;
        if found and (ts.VAlign <> rtvNone) then VAlign := ts.VAlign else VAlign := rtvMiddle;
      end;
      { lineOverflow 'truncate': the lines the height holds }
      { `calculatedHeight + token.lineHeight > topHeight`: a string line
        height joins, two strings compare as strings [R7-H] }
      if truncLine and AStyle.HasHeight
        and JGreater(JAdd(JNum(calcH), Result.Lines[i].Tokens[j].LineHeightV), topH) then
      begin
        if j > 0 then
        begin
          SetLength(Result.Lines[i].Tokens, j);
          Result.Lines[i].Width := lnW;
          Result.Lines[i].LineHeight := lnH;
          calcH := calcH + lnH;
          calcW := JsMax(calcW, lnW);
          if i < High(Result.Lines) then Result.IsTruncated := True;
          SetLength(Result.Lines, i + 1);
        end
        else
        begin
          Result.IsTruncated := True;
          SetLength(Result.Lines, i);
        end;
        stop := True;
        Break;
      end;
      with Result.Lines[i].Tokens[j] do
      begin
        if found and (ts.WidthKind = rtwPercent) then
        begin
          IsPercent := True;
          { parseInt(percentWidth, 10) [R7-H: of the text as written] }
          if ts.WidthIsText then Percent := JsParseInt(ts.WidthText)
          else Percent := Trunc(ts.Width);
          SetLength(pending, Length(pending) + 1);
          pending[High(pending)].L := i;
          pending[High(pending)].T := j;
          ContentWidth := MeasureW(AMeasurer, Text, FontFamily, FontSizePx, FontWeight);
        end
        else
        begin
          { [R2-F] a width not written ('auto' or none) and a picture that
            is there (parseText: isImageReady -- the port's are at once):
            as wide as the picture at the token's height, at least }
          if found and (ts.WidthKind in [rtwNone, rtwAuto]) and (ts.BgImage <> '')
            and Assigned(TySymbolImageSize) and TySymbolImageSize(ts.BgImage, iw, ih)
            and (ih > 0) then
            Width := Math.Max(Width, iw * Height / ih);
          { `topWidth - lineWidth`: NaN against a width that is a word, and
            then nothing is truncated (remainTruncWidth < width is false) }
          if (AStyle.Overflow = rtoTruncate) and hasTopW then
            remain := topW.N - lnW
          else
            remain := NaN;
          if not IsNan(remain) and (remain < Width) then
          begin
            { !tokenWidthNotSpecified: a number, or a string that is no
              percentage and not 'auto' [R7-H] }
            if (found and (ts.WidthKind in [rtwNumber, rtwText])) or (remain < padH) then
            begin
              Text := '';
              Width := 0;
              ContentWidth := 0;
            end
            else
            begin
              cut := TyZrPlainTextLines(Text, remain - padH, MaxDouble, AStyle.MinChar,
                EllipsisOf(AStyle), AMeasurer,
                FontFamily, TyFontSizeFromPx(FontSizePx), FontWeight, False);
              if (Length(cut) > 0) and (cut[0] <> Text) then Result.IsTruncated := True;
              if Length(cut) > 0 then Text := cut[0] else Text := '';
              Width := MeasureW(AMeasurer, Text, FontFamily, FontSizePx, FontWeight);
              ContentWidth := Width;
            end;
          end
          else
            ContentWidth := MeasureW(AMeasurer, Text, FontFamily, FontSizePx, FontWeight);
        end;
        Width := Width + padH;
        lnW := lnW + Width;
        { Math.max: a line height that is a word is NaN [R7-H] }
        lnH := JsMax(lnH, LineHeight);
      end;
    end;
    if stop then Break;
    Result.Lines[i].Width := lnW;
    Result.Lines[i].LineHeight := lnH;
    calcH := calcH + lnH;
    calcW := JsMax(calcW, lnW);
  end;
  { [R7-H] retrieve2(topWidth, calculatedWidth) and the same for the
    height, the padding then ADDED: a string joins it ('60' + 0 = '600') --
    always, padding or none }
  if hasTopW then Result.WidthV := topW else Result.WidthV := JNum(calcW);
  if AStyle.HasHeight then Result.HeightV := topH else Result.HeightV := JNum(calcH);
  Result.Width := Result.WidthV.N;
  Result.Height := Result.HeightV.N;
  Result.ContentWidth := calcW;
  Result.ContentHeight := calcH;
  if AStyle.HasPadding then
  begin
    Result.OuterWidthV := JAdd(Result.WidthV, JNum(AStyle.Padding[1] + AStyle.Padding[3]));
    Result.OuterHeightV := JAdd(Result.HeightV, JNum(AStyle.Padding[0] + AStyle.Padding[2]));
  end
  else
  begin
    Result.OuterWidthV := JAdd(Result.WidthV, JNum(0));
    Result.OuterHeightV := JAdd(Result.HeightV, JNum(0));
  end;
  Result.OuterWidth := Result.OuterWidthV.N;
  Result.OuterHeight := Result.OuterHeightV.N;
  { percent widths LAST, against the block's width, the token's own padding
    lost and the line's width already summed: parseInt of the percentage
    [R7-H: of its text] }
  for k := 0 to High(pending) do
    with Result.Lines[pending[k].L].Tokens[pending[k].T] do
      Width := Percent / 100 * Result.Width;
end;

{ ---- placing ---- }

function AdjustX(AX, AW: Double; AAlign: TTyRtAlign): Double;
begin
  case AAlign of
    rtaRight: Result := AX - AW;
    rtaCenter: Result := AX - AW / 2;
  else
    Result := AX;
  end;
end;

function AdjustY(AY, AH: Double; AVAlign: TTyRtVAlign): Double;
begin
  case AVAlign of
    rtvMiddle: Result := AY - AH / 2;
    rtvBottom: Result := AY - AH;
  else
    Result := AY;
  end;
end;

{ `style.lineHeight` as JS reads it: a string that is not empty, a number
  that is not 0 [R7-H: was any line height written] }
function LineHeightTruthy(const S: TTyRtStyle): Boolean;
begin
  if S.LineHeightIsText then Result := S.LineHeightText <> ''
  else Result := S.HasLineHeight and (S.LineHeight <> 0);
end;

function NeedBackground(const S: TTyRtStyle): Boolean;
begin
  { ([R7-AC] a border of 'Infinity' is truthy too) }
  Result := S.HasBackground or (S.BgImage <> '') or LineHeightTruthy(S)
    or (((S.BorderWidth <> 0) or S.BorderWidthInf) and S.HasBorderColor);
end;

procedure AddPiece(var R: TTyRtResult; const P: TTyRtPiece);
begin
  SetLength(R.Pieces, Length(R.Pieces) + 1);
  R.Pieces[High(R.Pieces)] := P;
end;

{ _renderBackground: the box; strokeFirst and the doubled width when it has
  both a fill and a border }
function RectPiece(const S: TTyRtStyle; AX, AY: Double; const AW, AH: TTyRtJs;
  ALine, AToken: Integer; AOpacityFallback: Double): TTyRtPiece;
var k: Integer;
begin
  Result := Default(TTyRtPiece);
  Result.Kind := rpkRect;
  Result.Line := ALine;
  Result.Token := AToken;
  Result.X := AX;
  Result.Y := AY;
  { [R7-H] canvas takes a string size as its number; the path adds it to
    the corner as a string (TTyRtPiece.PathEdges) }
  Result.W := AW.N;
  Result.H := AH.N;
  Result.PathEdges := AW.IsStr or AH.IsStr;
  Result.EdgeX1 := JAdd(JNum(AX), AW).N;
  Result.EdgeY1 := JAdd(JNum(AY), AH).N;
  Result.HasFill := S.HasBackground;
  Result.Fill := S.Background;
  Result.NoHit := S.BorderWidthInf and S.HasBorderColor;
  if (S.BorderWidth <> 0) and S.HasBorderColor then
  begin
    Result.HasStroke := True;
    Result.Stroke := S.BorderColor;
    Result.LineWidth := S.BorderWidth;
    if Result.HasFill then
    begin
      Result.StrokeFirst := True;
      Result.LineWidth := Result.LineWidth * 2;
    end;
    { [R2-I2] rectStyle.lineDash = style.borderDash, lineDashOffset =
      style.borderDashOffset || 0 }
    Result.BorderDash := S.BorderDash;
    Result.BorderDashOffset := S.BorderDashOffset;
    if IsNan(Result.BorderDashOffset) then Result.BorderDashOffset := 0;
  end
  { [R7-AC] A BORDER OF 'Infinity': stroked all the same, at the lineWidth
    the canvas had (it refuses Infinity, doubled or not) -- marked for the
    paint order (CanvasLeft 8), no width until it is settled [was: not
    stroked] }
  else if S.BorderWidthInf and S.HasBorderColor then
  begin
    Result.HasStroke := True;
    Result.Stroke := S.BorderColor;
    Result.LineWidth := 0;
    Result.CanvasLeft := Result.CanvasLeft or 8;
    if Result.HasFill then Result.StrokeFirst := True;
    Result.BorderDash := S.BorderDash;
    Result.BorderDashOffset := S.BorderDashOffset;
    if IsNan(Result.BorderDashOffset) then Result.BorderDashOffset := 0;
  end;
  for k := 0 to 3 do Result.Radius[k] := S.Radius[k];
  Result.Rounded := S.RadiusTruthy or (S.Radius[0] + S.Radius[1] + S.Radius[2]
    + S.Radius[3] > 0);
  if S.HasOpacity then Result.Opacity := S.Opacity else Result.Opacity := AOpacityFallback;
  Result.Drawn := Result.HasFill or Result.HasStroke;
  { [R5-A] the box's canvas shadow: style.shadowBlur || 0, the offsets alike,
    shadowColor || 'transparent' -- where the text style names none its
    prototype's '#000' }
  { ([R7-AC] a colour no parser reads too: the canvas' shadowColor) }
  if (not S.HasBoxShadowColor) or ((S.BoxShadowColor shr 24) <> 0)
    or (S.BoxShadowColor = cTyCanvasColourLeft) then
  begin
    if (not IsNan(S.BoxShadowBlur)) and (S.BoxShadowBlur > 0) then
      Result.ShadowBlur := S.BoxShadowBlur;
    if not IsNan(S.BoxShadowOffsetX) then Result.ShadowOffsetX := S.BoxShadowOffsetX;
    if not IsNan(S.BoxShadowOffsetY) then Result.ShadowOffsetY := S.BoxShadowOffsetY;
    if S.HasBoxShadowColor then Result.ShadowColor := S.BoxShadowColor
    else Result.ShadowColor := $FF000000;
    Result.HasShadow := (Result.ShadowBlur > 0) or (Result.ShadowOffsetX <> 0)
      or (Result.ShadowOffsetY <> 0);
  end;
  { [R2-F] a picture: a ZRImage of the box after the rect -- which is made
    only for a lineHeight or a border, and then takes the opacity (the
    common style is the rect's), the picture keeping its own 1 }
  if S.BgImage <> '' then
  begin
    Result.Image := S.BgImage;
    Result.Drawn := True;
    if LineHeightTruthy(S) or ((S.BorderWidth <> 0) and S.HasBorderColor) then
      Result.ImageOpacity := 1
    else
      Result.ImageOpacity := Result.Opacity;
  end;
end;

function LayoutIn(const AText: string; const AStyle: TTyRtStyle;
  const ARichStyles: TTyRtRich; ARich: Boolean; const ADefault: TTyRtDefault;
  ABaseX, ABaseY: Double; const AMeasurer: ITyTextMeasurer): TTyRtResult;
var
  textAlign: TTyRtAlign;
  vAlign: TTyRtVAlign;
  boxX, boxY, xLeft, xRight, lineTop, remained, lx, rx, w: Double;
  i, idx, ridx: Integer;
  blockBg: Boolean;

  procedure PlaceToken(ALine, AIdx: Integer; AX: Double; AAlign: TTyRtAlign);
  var
    tk: TTyRtToken;
    ts: TTyRtStyle;
    found, tokenBg, useDefaultFill: Boolean;
    y, rx0: Double;
    p, rp: TTyRtPiece;
  begin
    tk := Result.Block.Lines[ALine].Tokens[AIdx];
    ts := StyleOf(ARichStyles, tk.StyleIndex, AStyle, found);
    y := lineTop + Result.Block.Lines[ALine].LineHeight / 2;
    if tk.VAlign = rtvTop then y := lineTop + tk.Height / 2
    else if tk.VAlign = rtvBottom then
      y := lineTop + Result.Block.Lines[ALine].LineHeight - tk.Height / 2;
    tokenBg := False;
    if found and not tk.IsLineHolder and NeedBackground(ts) then
    begin
      case AAlign of
        rtaRight: rx0 := AX - tk.Width;
        rtaCenter: rx0 := AX - tk.Width / 2;
      else
        rx0 := AX;
      end;
      rp := RectPiece(ts, rx0, y - tk.Height / 2, JNum(tk.Width), tk.HeightV,
        ALine, AIdx, IfThen(AStyle.HasOpacity, AStyle.Opacity, 1));
      { [R7-L] the token's rect takes the token's own opacity }
      rp.OwnOpacity := ts.HasOpacity;
      AddPiece(Result, rp);
      tokenBg := ts.HasBackground or (ts.BgImage <> '');
    end;
    if tk.HasPadding then
    begin
      case AAlign of
        rtaRight: AX := AX - tk.Padding[1];
        rtaCenter: AX := AX + tk.Padding[3] / 2 - tk.Padding[1] / 2;
      else
        AX := AX + tk.Padding[3];
      end;
      y := y - (tk.Height / 2 - tk.Padding[0] - tk.InnerHeight / 2);
    end;
    p := Default(TTyRtPiece);
    p.Kind := rpkText;
    p.Line := ALine;
    p.Token := AIdx;
    p.X := AX;
    p.Y := y;
    p.Text := tk.Text;
    p.TextAlign := AAlign;
    p.FontFamily := tk.FontFamily;
    p.FontSizePx := tk.FontSizePx;
    p.FontWeight := tk.FontWeight;
    { the TSpan's own box: its content, hung by its alignment }
    p.W := tk.ContentWidth;
    p.H := tk.ContentHeight;
    useDefaultFill := False;
    p.TokenFill := found and ts.HasFill;
    p.TokenStroke := found and ts.HasStroke;
    if found and ts.HasFill then
    begin
      p.HasFill := not ts.FillNone;
      p.Fill := ts.Fill;
    end
    else if AStyle.HasFill then
    begin
      p.HasFill := not AStyle.FillNone;
      p.Fill := AStyle.Fill;
    end
    else
    begin
      useDefaultFill := True;
      p.HasFill := ADefault.HasFill;
      p.Fill := ADefault.Fill;
    end;
    p.DefaultFill := useDefaultFill;
    if found and ts.HasStroke then
    begin
      p.HasStroke := not ts.StrokeNone;
      p.Stroke := ts.Stroke;
    end
    else if AStyle.HasStroke then
    begin
      p.HasStroke := not AStyle.StrokeNone;
      p.Stroke := AStyle.Stroke;
    end
    else if not tokenBg and not blockBg
      and (not ADefault.AutoStroke or useDefaultFill) and ADefault.HasStroke then
    begin
      p.HasStroke := True;
      p.Stroke := ADefault.Stroke;
      p.DefaultStroke := True;
    end;
    if p.HasStroke then
    begin
      if found and ts.HasLineWidth then p.LineWidth := ts.LineWidth
      else if AStyle.HasLineWidth then p.LineWidth := AStyle.LineWidth
      else p.LineWidth := 2;
      { [F4c] the token's textBorderType, else the block's }
      if found and (ts.LineDash <> '') then p.LineDash := ts.LineDash
      else p.LineDash := AStyle.LineDash;
      { [R2-F] the phase is the block's, whatever the token says
        (Text.ts: style.lineDashOffset || 0) }
      if AStyle.HasLineDashOffset then p.LineDashOffset := AStyle.LineDashOffset;
    end;
    if found and ts.HasOpacity then p.Opacity := ts.Opacity
    else if AStyle.HasOpacity then p.Opacity := AStyle.Opacity
    else p.Opacity := 1;
    { [R7-L] retrieve3's first: the token's own }
    p.OwnOpacity := found and ts.HasOpacity;
    { each shadow part: the token's, else the block's, else none }
    if found and (ts.ShadowBlur <> 0) then p.ShadowBlur := ts.ShadowBlur
    else p.ShadowBlur := AStyle.ShadowBlur;
    if found and ts.HasShadowColor then p.ShadowColor := ts.ShadowColor
    else p.ShadowColor := AStyle.ShadowColor;
    if found and (ts.ShadowOffsetX <> 0) then p.ShadowOffsetX := ts.ShadowOffsetX
    else p.ShadowOffsetX := AStyle.ShadowOffsetX;
    if found and (ts.ShadowOffsetY <> 0) then p.ShadowOffsetY := ts.ShadowOffsetY
    else p.ShadowOffsetY := AStyle.ShadowOffsetY;
    p.HasShadow := p.ShadowBlur > 0;
    AddPiece(Result, p);
  end;

  procedure PlainLayout;
  var
    lines: TStringArray;
    lh, contentH, height, contentW, textX, textY, bx, by, fontH, q: Double;
    k, keep: Integer;
    cut: TStringArray;
    p: TTyRtPiece;
    useDefaultFill, bgDrawn, hasW: Boolean;
    wr: TWrapResult;
    widthV, heightV, lhV, textYV, padHV, padVV: TTyRtJs;
  begin
    fontH := FontHeight(AMeasurer, AStyle.FontFamily, AStyle.FontSizePx, AStyle.FontWeight);
    { [R7-H] the width, height and line height as zrender holds them: a
      string stays one where it is added, and is its number elsewhere }
    if AStyle.HasLineHeight then lhV := LineHeightOf(AStyle)
    else lhV := JNum(fontH);
    lh := lhV.N;
    widthV := BlockWidthOf(AStyle, hasW);
    lines := nil;
    if AText <> '' then
    begin
      if (AStyle.Overflow in [rtoBreak, rtoBreakAll]) and hasW then
      begin
        wr := WrapText(AText, AStyle.FontFamily, AStyle.FontSizePx, AStyle.FontWeight,
          widthV.N, AStyle.Overflow = rtoBreakAll, 0, AMeasurer);
        SetLength(lines, Length(wr.Lines));
        for k := 0 to High(wr.Lines) do lines[k] := wr.Lines[k];
      end
      else
        lines := AText.Split([#10]);
    end;
    contentH := Length(lines) * lh;
    if AStyle.HasHeight then heightV := HeightOf(AStyle) else heightV := JNum(contentH);
    height := heightV.N;
    if AStyle.LineOverflowTruncate and (contentH > height) then
    begin
      { lines.slice(0, Math.floor(height / lineHeight)): NaN slices to
        nothing, an infinity keeps every line }
      q := height / lh;
      if IsNan(q) then keep := 0
      else if IsInfinite(q) then
      begin
        if q > 0 then keep := Length(lines) else keep := 0;
      end
      else
        keep := Floor(q);
      { Array.slice: a negative end counts from the end -- a height under
        nought (a cell shorter than its padding) keeps all the lines but
        the last [Batch 145] }
      if keep < 0 then keep := Max(Length(lines) + keep, 0);
      if keep < Length(lines) then
      begin
        SetLength(lines, Max(keep, 0));
        Result.Block.IsTruncated := True;
      end;
      contentH := Length(lines) * lh;
    end;
    { truncateSingleLine: `!containerWidth` -- a width that is a word is
      NaN, and keeps nothing (nor counts as truncated) [R7-H] }
    if (AText <> '') and (AStyle.Overflow = rtoTruncate) and hasW and IsNan(widthV.N - 1) then
      for k := 0 to High(lines) do lines[k] := ''
    else if (AText <> '') and (AStyle.Overflow = rtoTruncate) and hasW then
      for k := 0 to High(lines) do
      begin
        cut := TyZrPlainTextLines(lines[k], widthV.N, MaxDouble, AStyle.MinChar,
          EllipsisOf(AStyle), AMeasurer,
          AStyle.FontFamily, TyFontSizeFromPx(AStyle.FontSizePx), AStyle.FontWeight, False);
        if Length(cut) > 0 then
        begin
          if cut[0] <> lines[k] then Result.Block.IsTruncated := True;
          lines[k] := cut[0];
        end;
      end;
    contentW := 0;
    for k := 0 to High(lines) do
      contentW := Max(contentW, MeasureW(AMeasurer, lines[k], AStyle.FontFamily,
        AStyle.FontSizePx, AStyle.FontWeight));
    if not hasW then widthV := JNum(contentW);
    { outerWidth += paddingH, always: a string joins it [R7-H] }
    if AStyle.HasPadding then
    begin
      padHV := JNum(AStyle.Padding[1] + AStyle.Padding[3]);
      padVV := JNum(AStyle.Padding[0] + AStyle.Padding[2]);
    end
    else
    begin
      padHV := JNum(0);
      padVV := JNum(0);
    end;
    Result.Block.WidthV := widthV;
    Result.Block.HeightV := heightV;
    Result.Block.OuterWidthV := JAdd(widthV, padHV);
    Result.Block.OuterHeightV := JAdd(heightV, padVV);
    Result.Block.Width := widthV.N;
    Result.Block.Height := height;
    Result.Block.ContentWidth := contentW;
    Result.Block.ContentHeight := contentH;
    Result.Block.OuterWidth := Result.Block.OuterWidthV.N;
    Result.Block.OuterHeight := Result.Block.OuterHeightV.N;
    textX := ABaseX;
    textY := AdjustY(ABaseY, contentH, vAlign);
    bx := AdjustX(ABaseX, Result.Block.OuterWidth, textAlign);
    by := AdjustY(ABaseY, Result.Block.OuterHeight, vAlign);
    Result.BoxX := bx;
    Result.BoxY := by;
    Result.BoxW := Result.Block.OuterWidth;
    Result.BoxH := Result.Block.OuterHeight;
    bgDrawn := False;
    if NeedBackground(AStyle) then
    begin
      AddPiece(Result, RectPiece(AStyle, bx, by, Result.Block.OuterWidthV,
        Result.Block.OuterHeightV, -1, -1, 1));
      bgDrawn := AStyle.HasBackground or (AStyle.BgImage <> '');
    end;
    textY := textY + lh / 2;
    if AStyle.HasPadding then
    begin
      case textAlign of
        rtaRight: textX := ABaseX - AStyle.Padding[1];
        rtaCenter: textX := ABaseX + AStyle.Padding[3] / 2 - AStyle.Padding[1] / 2;
      else
        textX := ABaseX + AStyle.Padding[3];
      end;
      if vAlign = rtvTop then textY := textY + AStyle.Padding[0]
      else if vAlign = rtvBottom then textY := textY - AStyle.Padding[2];
    end;
    { [R7-H] `textY += lineHeight` after each line: a string line height
      joins it, and the next line sits at the joined number }
    textYV := JNum(textY);
    for k := 0 to High(lines) do
    begin
      p := Default(TTyRtPiece);
      p.Kind := rpkText;
      p.Line := k;
      p.Token := -1;
      p.X := textX;
      p.Y := textYV.N;
      p.Text := lines[k];
      p.TextAlign := textAlign;
      p.FontFamily := AStyle.FontFamily;
      p.FontSizePx := AStyle.FontSizePx;
      p.FontWeight := AStyle.FontWeight;
      { EVERY LINE'S BOX IS THE BLOCK'S WIDEST, one font height tall
        (Text.ts:658-676) }
      p.W := contentW;
      p.H := fontH;
      useDefaultFill := False;
      if AStyle.HasFill then
      begin
        p.HasFill := not AStyle.FillNone;
        p.Fill := AStyle.Fill;
      end
      else
      begin
        useDefaultFill := True;
        p.HasFill := ADefault.HasFill;
        p.Fill := ADefault.Fill;
      end;
      p.DefaultFill := useDefaultFill;
      if AStyle.HasStroke then
      begin
        p.HasStroke := not AStyle.StrokeNone;
        p.Stroke := AStyle.Stroke;
      end
      else if not bgDrawn and (not ADefault.AutoStroke or useDefaultFill)
        and ADefault.HasStroke then
      begin
        p.HasStroke := True;
        p.Stroke := ADefault.Stroke;
        p.DefaultStroke := True;
      end;
      if p.HasStroke then
      begin
        if AStyle.HasLineWidth then p.LineWidth := AStyle.LineWidth else p.LineWidth := 2;
        p.LineDash := AStyle.LineDash;
        if AStyle.HasLineDashOffset then p.LineDashOffset := AStyle.LineDashOffset;
      end;
      if AStyle.HasOpacity then p.Opacity := AStyle.Opacity else p.Opacity := 1;
      p.ShadowBlur := AStyle.ShadowBlur;
      p.ShadowColor := AStyle.ShadowColor;
      p.ShadowOffsetX := AStyle.ShadowOffsetX;
      p.ShadowOffsetY := AStyle.ShadowOffsetY;
      p.HasShadow := p.ShadowBlur > 0;
      AddPiece(Result, p);
      textYV := JAdd(textYV, lhV);
    end;
  end;

begin
  Result := Default(TTyRtResult);
  textAlign := AStyle.Align;
  if textAlign = rtaNone then textAlign := ADefault.Align;
  vAlign := AStyle.VAlign;
  if vAlign = rtvNone then vAlign := ADefault.VAlign;
  if not ARich then
  begin
    if textAlign = rtaNone then textAlign := rtaLeft;
    if vAlign = rtvNone then vAlign := rtvTop;
    PlainLayout;
    Exit;
  end;
  Result.Block := ParseRich(AText, AStyle, ARichStyles, textAlign, AMeasurer);
  boxX := AdjustX(ABaseX, Result.Block.OuterWidth, textAlign);
  boxY := AdjustY(ABaseY, Result.Block.OuterHeight, vAlign);
  Result.BoxX := boxX;
  Result.BoxY := boxY;
  Result.BoxW := Result.Block.OuterWidth;
  Result.BoxH := Result.Block.OuterHeight;
  xLeft := boxX;
  lineTop := boxY;
  if AStyle.HasPadding then
  begin
    xLeft := xLeft + AStyle.Padding[3];
    lineTop := lineTop + AStyle.Padding[0];
  end;
  { `xLeft + contentWidth`: a width that is a string joins it [R7-H] }
  xRight := JAdd(JNum(xLeft), Result.Block.WidthV).N;
  blockBg := False;
  if NeedBackground(AStyle) then
  begin
    AddPiece(Result, RectPiece(AStyle, boxX, boxY, Result.Block.OuterWidthV,
      Result.Block.OuterHeightV, -1, -1, 1));
    blockBg := AStyle.HasBackground or (AStyle.BgImage <> '');
  end;
  for i := 0 to High(Result.Block.Lines) do
  begin
    remained := Result.Block.Lines[i].Width;
    lx := xLeft;
    rx := xRight;
    idx := 0;
    ridx := High(Result.Block.Lines[i].Tokens);
    while (idx <= ridx) and (Result.Block.Lines[i].Tokens[idx].Align in [rtaNone, rtaLeft]) do
    begin
      w := Result.Block.Lines[i].Tokens[idx].Width;
      PlaceToken(i, idx, lx, rtaLeft);
      remained := remained - w;
      lx := lx + w;
      Inc(idx);
    end;
    while (ridx >= idx) and (Result.Block.Lines[i].Tokens[ridx].Align = rtaRight) do
    begin
      w := Result.Block.Lines[i].Tokens[ridx].Width;
      PlaceToken(i, ridx, rx, rtaRight);
      remained := remained - w;
      rx := rx - w;
      Dec(ridx);
    end;
    lx := lx + (Result.Block.Width - (lx - xLeft) - (xRight - rx) - remained) / 2;
    while idx <= ridx do
    begin
      w := Result.Block.Lines[i].Tokens[idx].Width;
      PlaceToken(i, idx, lx + w / 2, rtaCenter);
      lx := lx + w;
      Inc(idx);
    end;
    lineTop := lineTop + Result.Block.Lines[i].LineHeight;
  end;
end;

end.
