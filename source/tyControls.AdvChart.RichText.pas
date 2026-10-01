unit tyControls.AdvChart.RichText;
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

  LCL-free: SysUtils, Math and the AdvChart types. }
interface
uses
  SysUtils, Math,
  tyControls.AdvChart.Types, tyControls.AdvChart.Paint;

{ THE STYLE, DEFAULT AND PIECE RECORDS LIVE IN AdvChart.Paint [Batch 86]: a
  caption carries its laid-out pieces from the label pass to the renderer,
  and the paint list is the layer both of them see. }
type
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
  end;
  TTyRtLine = record
    Tokens: array of TTyRtToken;
    Width, LineHeight: Double;
  end;

  TTyRtBlock = record
    Lines: array of TTyRtLine;
    Width, Height, ContentWidth, ContentHeight, OuterWidth, OuterHeight: Double;
    IsTruncated: Boolean;
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

implementation

uses tyControls.FontUnits, tyControls.AdvChart.Labels;

const
  cGuo = #$E5#$9B#$BD;   // U+56FD: zrender's measure of a font's height

function TyRtStyleDefault: TTyRtStyle;
begin
  Result := Default(TTyRtStyle);
  Result.FontFamily := 'sans-serif';
  Result.FontSizePx := 12;
  Result.FontWeight := 400;
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
    if found and (ts.WidthKind in [rtwNumber, rtwPercent]) then
    begin
      if ts.WidthKind = rtwPercent then outerW := ts.Width / 100 * AWrap.Width + padH
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

function ParseRich(const AText: string; const AStyle: TTyRtStyle;
  const ARich: TTyRtRich; ATopAlign: TTyRtAlign;
  const AMeasurer: ITyTextMeasurer): TTyRtBlock;
var
  wrap: TWrapInfo;
  i, j, k: Integer;
  lnH, lnW, calcH, calcW, padH, remain: Double;
  ts: TTyRtStyle;
  found, truncLine, stop: Boolean;
  fam: string;
  px: Double;
  wt: Integer;
  cut: TStringArray;
  pending: array of record L, T: Integer; end;
begin
  Result := Default(TTyRtBlock);
  if AText = '' then Exit;
  wrap := Default(TWrapInfo);
  wrap.Active := (AStyle.Overflow in [rtoBreak, rtoBreakAll]) and (AStyle.WidthKind = rtwNumber);
  if wrap.Active then
  begin
    wrap.Width := AStyle.Width;
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
        if found and ts.HasHeight then InnerHeight := ts.Height
        else InnerHeight := ContentHeight;
        Height := InnerHeight;
        if HasPadding then Height := Height + Padding[0] + Padding[2];
        if found and ts.HasLineHeight then LineHeight := ts.LineHeight
        else if AStyle.HasLineHeight then LineHeight := AStyle.LineHeight
        else LineHeight := Height;
        if found and (ts.Align <> rtaNone) then Align := ts.Align else Align := ATopAlign;
        if found and (ts.VAlign <> rtvNone) then VAlign := ts.VAlign else VAlign := rtvMiddle;
      end;
      { lineOverflow 'truncate': the lines the height holds }
      if truncLine and AStyle.HasHeight
        and (calcH + Result.Lines[i].Tokens[j].LineHeight > AStyle.Height) then
      begin
        if j > 0 then
        begin
          SetLength(Result.Lines[i].Tokens, j);
          Result.Lines[i].Width := lnW;
          Result.Lines[i].LineHeight := lnH;
          calcH := calcH + lnH;
          calcW := Max(calcW, lnW);
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
          Percent := ts.Width;
          SetLength(pending, Length(pending) + 1);
          pending[High(pending)].L := i;
          pending[High(pending)].T := j;
          ContentWidth := MeasureW(AMeasurer, Text, FontFamily, FontSizePx, FontWeight);
        end
        else
        begin
          if (AStyle.Overflow = rtoTruncate) and (AStyle.WidthKind = rtwNumber) then
            remain := AStyle.Width - lnW
          else
            remain := NaN;
          if not IsNan(remain) and (remain < Width) then
          begin
            if (found and (ts.WidthKind = rtwNumber)) or (remain < padH) then
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
        lnH := Max(lnH, LineHeight);
      end;
    end;
    if stop then Break;
    Result.Lines[i].Width := lnW;
    Result.Lines[i].LineHeight := lnH;
    calcH := calcH + lnH;
    calcW := Max(calcW, lnW);
  end;
  if AStyle.WidthKind = rtwNumber then Result.Width := AStyle.Width else Result.Width := calcW;
  if AStyle.HasHeight then Result.Height := AStyle.Height else Result.Height := calcH;
  Result.ContentWidth := calcW;
  Result.ContentHeight := calcH;
  Result.OuterWidth := Result.Width;
  Result.OuterHeight := Result.Height;
  if AStyle.HasPadding then
  begin
    Result.OuterWidth := Result.OuterWidth + AStyle.Padding[1] + AStyle.Padding[3];
    Result.OuterHeight := Result.OuterHeight + AStyle.Padding[0] + AStyle.Padding[2];
  end;
  { percent widths LAST, against the block's width, the token's own padding
    lost and the line's width already summed }
  for k := 0 to High(pending) do
    with Result.Lines[pending[k].L].Tokens[pending[k].T] do
      Width := Trunc(Percent) / 100 * Result.Width;
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

function NeedBackground(const S: TTyRtStyle): Boolean;
begin
  Result := S.HasBackground or S.HasLineHeight
    or ((S.BorderWidth <> 0) and S.HasBorderColor);
end;

procedure AddPiece(var R: TTyRtResult; const P: TTyRtPiece);
begin
  SetLength(R.Pieces, Length(R.Pieces) + 1);
  R.Pieces[High(R.Pieces)] := P;
end;

{ _renderBackground: the box; strokeFirst and the doubled width when it has
  both a fill and a border }
function RectPiece(const S: TTyRtStyle; AX, AY, AW, AH: Double; ALine,
  AToken: Integer; AOpacityFallback: Double): TTyRtPiece;
var k: Integer;
begin
  Result := Default(TTyRtPiece);
  Result.Kind := rpkRect;
  Result.Line := ALine;
  Result.Token := AToken;
  Result.X := AX;
  Result.Y := AY;
  Result.W := AW;
  Result.H := AH;
  Result.HasFill := S.HasBackground;
  Result.Fill := S.Background;
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
  end;
  for k := 0 to 3 do Result.Radius[k] := S.Radius[k];
  if S.HasOpacity then Result.Opacity := S.Opacity else Result.Opacity := AOpacityFallback;
  Result.Drawn := Result.HasFill or Result.HasStroke;
end;

function TyRtLayout(const AText: string; const AStyle: TTyRtStyle;
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
    p: TTyRtPiece;
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
      AddPiece(Result, RectPiece(ts, rx0, y - tk.Height / 2, tk.Width, tk.Height,
        ALine, AIdx, IfThen(AStyle.HasOpacity, AStyle.Opacity, 1)));
      tokenBg := ts.HasBackground;
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
    end;
    if found and ts.HasOpacity then p.Opacity := ts.Opacity
    else if AStyle.HasOpacity then p.Opacity := AStyle.Opacity
    else p.Opacity := 1;
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
    lh, contentH, height, width, contentW, textX, textY, bx, by, fontH: Double;
    k, keep: Integer;
    cut: TStringArray;
    p: TTyRtPiece;
    useDefaultFill, bgDrawn: Boolean;
    wr: TWrapResult;
  begin
    fontH := FontHeight(AMeasurer, AStyle.FontFamily, AStyle.FontSizePx, AStyle.FontWeight);
    if AStyle.HasLineHeight then lh := AStyle.LineHeight
    else lh := fontH;
    lines := nil;
    if AText <> '' then
    begin
      if (AStyle.Overflow in [rtoBreak, rtoBreakAll]) and (AStyle.WidthKind = rtwNumber) then
      begin
        wr := WrapText(AText, AStyle.FontFamily, AStyle.FontSizePx, AStyle.FontWeight,
          AStyle.Width, AStyle.Overflow = rtoBreakAll, 0, AMeasurer);
        SetLength(lines, Length(wr.Lines));
        for k := 0 to High(wr.Lines) do lines[k] := wr.Lines[k];
      end
      else
        lines := AText.Split([#10]);
    end;
    contentH := Length(lines) * lh;
    if AStyle.HasHeight then height := AStyle.Height else height := contentH;
    if AStyle.LineOverflowTruncate and (contentH > height) then
    begin
      keep := Floor(height / lh);
      if keep < Length(lines) then
      begin
        SetLength(lines, Max(keep, 0));
        Result.Block.IsTruncated := True;
      end;
      contentH := Length(lines) * lh;
    end;
    if (AStyle.Overflow = rtoTruncate) and (AStyle.WidthKind = rtwNumber) then
      for k := 0 to High(lines) do
      begin
        cut := TyZrPlainTextLines(lines[k], AStyle.Width, MaxDouble, AStyle.MinChar,
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
    if AStyle.WidthKind = rtwNumber then width := AStyle.Width else width := contentW;
    Result.Block.Width := width;
    Result.Block.Height := height;
    Result.Block.ContentWidth := contentW;
    Result.Block.ContentHeight := contentH;
    Result.Block.OuterWidth := width;
    Result.Block.OuterHeight := height;
    if AStyle.HasPadding then
    begin
      Result.Block.OuterWidth := width + AStyle.Padding[1] + AStyle.Padding[3];
      Result.Block.OuterHeight := height + AStyle.Padding[0] + AStyle.Padding[2];
    end;
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
      AddPiece(Result, RectPiece(AStyle, bx, by, Result.Block.OuterWidth,
        Result.Block.OuterHeight, -1, -1, 1));
      bgDrawn := AStyle.HasBackground;
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
    for k := 0 to High(lines) do
    begin
      p := Default(TTyRtPiece);
      p.Kind := rpkText;
      p.Line := k;
      p.Token := -1;
      p.X := textX;
      p.Y := textY;
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
      end;
      if AStyle.HasOpacity then p.Opacity := AStyle.Opacity else p.Opacity := 1;
      p.ShadowBlur := AStyle.ShadowBlur;
      p.ShadowColor := AStyle.ShadowColor;
      p.ShadowOffsetX := AStyle.ShadowOffsetX;
      p.ShadowOffsetY := AStyle.ShadowOffsetY;
      p.HasShadow := p.ShadowBlur > 0;
      AddPiece(Result, p);
      textY := textY + lh;
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
  xRight := xLeft + Result.Block.Width;
  blockBg := False;
  if NeedBackground(AStyle) then
  begin
    AddPiece(Result, RectPiece(AStyle, boxX, boxY, Result.Block.OuterWidth,
      Result.Block.OuterHeight, -1, -1, 1));
    blockBg := AStyle.HasBackground;
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
