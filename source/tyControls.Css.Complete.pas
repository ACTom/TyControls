unit tyControls.Css.Complete;
{$mode objfpc}{$H+}

{ The PURE logic behind the design-time StyleOverride editor: what to suggest at a caret, and
  which properties are unknown (the resolver silently drops those, so the editor is the only
  place a typo surfaces). Kept in a runtime unit -- no SynEdit, no PropEdits -- so it is
  unit-tested headless; the design-time dialog is a thin shell over it. }

interface

uses
  Classes, tyControls.Types;

{ Fill ADest with completion suggestions for a caret sitting right after ATextBeforeCaret.
  ASelectorMode adds selector heads + pseudo-states (the controller-level override). Order:
    - typing a '--name'          -> known token names (open axis: suggested, not enforced)
    - inside a rule, in a value  -> that property's value hints + the colour functions
    - inside a rule, otherwise   -> known property names
    - outside a rule + selectors -> typeKeys and pseudo-states }
procedure TyCssCompletionItems(const ATextBeforeCaret: string; ASelectorMode: Boolean;
  ADest: TStrings);

{ The property names in ASource the resolver does NOT recognise, one indented per line (''
  when all are known). ASource may be a bare declaration block (control level) or full tycss
  with selectors (controller level). }
function TyCssUnknownProps(const ASource: string): string;

{ A ready-to-insert declaration for AProp: 'prop: <hint>;' where <hint> is the first value hint
  for a closed-keyword property, else 'prop: ;' for the developer to fill. }
function TyCssPropertyTemplate(const AProp: string): string;

{ '' if ASource is syntactically valid tycss (parses + values resolve), else the parse/value
  error message. ASelectorMode = full tycss with selectors (controller); otherwise a bare
  declaration block (control), which is wrapped in a throwaway rule to reuse the same parser. }
function TyCssValidate(const ASource: string; ASelectorMode: Boolean): string;

{ Normalise tycss whitespace: one declaration per line, a space after ':' and none before, the
  body of each rule indented two spaces, a blank line between rules. Idempotent. Does not
  reflow selectors or reorder anything -- purely a tidy. }
function TyCssFormat(const ASource: string): string;

{ Tidy ONE line in place (for format-on-line-leave): keep its leading indent, put a space after
  ':' and none before ':' / ';', collapse internal whitespace, space before an opening brace. No newlines
  added or removed -- so the editor can replace just that line, not reflow the whole document. }
function TyCssFormatLine(const ALine: string): string;

{ Serialise the value of AProp out of a RESOLVED style set as a tycss value string (e.g.
  '#3b82f6', '2px', 'solid'), or '' when the property is not present or is not a simple scalar
  the editor can round-trip (gradients, shadows, ...). Used to seed an inserted declaration with
  the theme's ACTUAL current value -- AStyle comes from ResolveStyle, whose base layer IS the
  default theme, so "theme, then default theme" fallback is already baked in. }
function TyCssPropertyDefault(const AProp: string; const AStyle: TTyStyleSet): string;

implementation

uses
  SysUtils,
  tyControls.StyleModel, tyControls.Css.Values, tyControls.Css.Parser, tyControls.Css.Catalog;

function TrailingIdent(const S: string): string;
var i: Integer;
begin
  i := Length(S);
  while (i >= 1) and (S[i] in ['-', 'a'..'z', 'A'..'Z', '0'..'9']) do Dec(i);
  Result := Copy(S, i + 1, MaxInt);
end;

procedure TyCssCompletionItems(const ATextBeforeCaret: string; ASelectorMode: Boolean;
  ADest: TStrings);
var
  i, depth, boundary: Integer;
  curWord, prop: string;
  colonAfter: Boolean;

  procedure AddAll(const A: array of string);
  var s: string;
  begin
    for s in A do ADest.Add(s);
  end;

begin
  if ADest = nil then Exit;
  curWord := TrailingIdent(ATextBeforeCaret);

  if (Length(curWord) >= 1) and (curWord[1] = '-') then
  begin
    AddAll(TyCatalogTokens);   { typing a --token }
    Exit;
  end;

  depth := 0;
  boundary := 0;
  for i := 1 to Length(ATextBeforeCaret) do
  begin
    case ATextBeforeCaret[i] of
      '{': begin Inc(depth); boundary := i; end;
      '}': begin Dec(depth); boundary := i; end;
      ';': boundary := i;
    end;
  end;

  if depth > 0 then
  begin
    colonAfter := False; prop := '';
    for i := boundary + 1 to Length(ATextBeforeCaret) do
      if ATextBeforeCaret[i] = ':' then begin colonAfter := True; Break; end;
    if colonAfter then
    begin
      prop := Trim(Copy(ATextBeforeCaret, boundary + 1, i - boundary - 1));
      TyStyleValueHints(prop, ADest);
      AddAll(TyKnownColorFns);
    end
    else
      AddAll(TyKnownStyleProps);
    Exit;
  end;

  if ASelectorMode then
  begin
    AddAll(TyCatalogTypeKeys);
    AddAll(TyKnownPseudoStates);
  end;
end;

function TyCssUnknownProps(const ASource: string): string;
var
  decls: TTyCssDeclarationArray;
  i, j: Integer;
  p: string;
  known: Boolean;

  function BareDecls(const ASrc: string): string;
  var k, d: Integer; c: Char;
  begin
    Result := ''; d := 0;
    for k := 1 to Length(ASrc) do
    begin
      c := ASrc[k];
      case c of
        '{': Inc(d);
        '}': begin Dec(d); Result := Result + ';'; end;
      else
        if d > 0 then Result := Result + c;   { only the inside of rules }
      end;
    end;
  end;

begin
  Result := '';
  p := BareDecls(ASource);
  if Trim(p) = '' then p := ASource;   { no braces -> a bare control-level block }
  if not TyParseOverride(p, decls) then Exit;
  for i := 0 to High(decls) do
  begin
    if Trim(decls[i].Prop) = '' then Continue;
    known := SameText(decls[i].Prop, 'background-color');   { the accepted alias }
    if not known then
      for j := 0 to High(TyKnownStyleProps) do
        if SameText(decls[i].Prop, TyKnownStyleProps[j]) then begin known := True; Break; end;
    if not known and
       (Pos(LineEnding + '  ' + decls[i].Prop + LineEnding, LineEnding + Result + LineEnding) = 0) then
      Result := Result + '  ' + decls[i].Prop + LineEnding;
  end;
end;

function TyCssPropertyTemplate(const AProp: string): string;
var
  hints: TStringList;
begin
  hints := TStringList.Create;
  try
    TyStyleValueHints(AProp, hints);
    { first WHOLE-keyword hint (skip function prefixes ending in '(') as the placeholder value }
    while (hints.Count > 0) and (hints[0] <> '') and (hints[0][Length(hints[0])] = '(') do
      hints.Delete(0);
    if hints.Count > 0 then
      Result := AProp + ': ' + hints[0] + ';'
    else
      Result := AProp + ': ;';
  finally
    hints.Free;
  end;
end;

function TyCssValidate(const ASource: string; ASelectorMode: Boolean): string;
var
  m: TTyStyleModel;
  src: string;
begin
  Result := '';
  if Trim(ASource) = '' then Exit;
  { A control-level block has no selector; wrap it in a throwaway rule so the same fail-fast
    parser (which validates values, not just syntax) can read it. }
  if ASelectorMode then src := ASource else src := '_ovr { ' + ASource + ' }';
  m := TTyStyleModel.Create;
  try
    try
      m.LoadFromCss(src);   { raises ETyCssError with a message on a bad token / value }
    except
      on E: Exception do Result := E.Message;
    end;
  finally
    m.Free;
  end;
end;

function TyCssFormat(const ASource: string): string;
var
  i, depth: Integer;
  c: Char;
  out_: string;
  atLineStart: Boolean;

  procedure NewLine;
  var d: Integer;
  begin
    out_ := TrimRight(out_) + LineEnding;
    for d := 1 to depth * 2 do out_ := out_ + ' ';
    atLineStart := True;
  end;

  procedure Emit(ch: Char);
  begin
    out_ := out_ + ch;
    atLineStart := False;
  end;

begin
  out_ := ''; depth := 0; atLineStart := True;
  i := 1;
  while i <= Length(ASource) do
  begin
    c := ASource[i];
    case c of
      #10, #13, #9, ' ':
        begin
          { collapse runs of whitespace to a single space, but not at the start of a line }
          if (not atLineStart) and (out_ <> '') and (out_[Length(out_)] <> ' ') then Emit(' ');
        end;
      '{':
        begin
          if (out_ <> '') and (out_[Length(out_)] <> ' ') then Emit(' ');
          Emit('{'); Inc(depth); NewLine;
        end;
      '}':
        begin
          if depth > 0 then Dec(depth);
          NewLine; Emit('}'); NewLine; NewLine;   { blank line between rules }
        end;
      ';':
        begin
          if (out_ <> '') and (out_[Length(out_)] = ' ') then SetLength(out_, Length(out_) - 1);
          Emit(';'); NewLine;
        end;
      ':':
        begin
          if (out_ <> '') and (out_[Length(out_)] = ' ') then SetLength(out_, Length(out_) - 1);
          Emit(':'); Emit(' ');
        end;
    else
      Emit(c);
    end;
    Inc(i);
  end;
  Result := Trim(out_);
end;

function TyCssFormatLine(const ALine: string): string;
var
  i: Integer;
  indent, body, out_: string;
  c: Char;
begin
  { keep the leading indent verbatim }
  i := 1;
  while (i <= Length(ALine)) and (ALine[i] in [' ', #9]) do Inc(i);
  indent := Copy(ALine, 1, i - 1);
  body := Copy(ALine, i, MaxInt);

  out_ := '';
  i := 1;
  while i <= Length(body) do
  begin
    c := body[i];
    case c of
      #9, ' ':
        if (out_ <> '') and (out_[Length(out_)] <> ' ') then out_ := out_ + ' ';
      ':':
        begin
          if (out_ <> '') and (out_[Length(out_)] = ' ') then SetLength(out_, Length(out_) - 1);
          out_ := out_ + ': ';
        end;
      ';':
        begin
          if (out_ <> '') and (out_[Length(out_)] = ' ') then SetLength(out_, Length(out_) - 1);
          out_ := out_ + '; ';
        end;
      '{':
        begin
          if (out_ <> '') and (out_[Length(out_)] <> ' ') then out_ := out_ + ' ';
          out_ := out_ + '{ ';
        end;
    else
      out_ := out_ + c;
    end;
    Inc(i);
  end;
  Result := indent + TrimRight(out_);
end;

function TyCssPropertyDefault(const AProp: string; const AStyle: TTyStyleSet): string;
  function ColStr(c: TTyColor): string;
  var a, r, g, b: Byte;
  begin
    a := (c shr 24) and $FF; r := (c shr 16) and $FF; g := (c shr 8) and $FF; b := c and $FF;
    if a = $FF then Result := LowerCase(Format('#%.2x%.2x%.2x', [r, g, b]))
    else Result := LowerCase(Format('#%.2x%.2x%.2x%.2x', [r, g, b, a]));
  end;
  function OpacityStr(v: Single): string;
  var fs: TFormatSettings;
  begin
    fs := DefaultFormatSettings; fs.DecimalSeparator := '.';
    Result := Trim(Format('%.3f', [v], fs));
    while (Length(Result) > 1) and (Result[Length(Result)] = '0') do SetLength(Result, Length(Result) - 1);
    if (Result <> '') and (Result[Length(Result)] = '.') then Result := Result + '0';
  end;
var
  p: string;
begin
  Result := '';
  p := LowerCase(Trim(AProp));
  if (p = 'color') and (tpTextColor in AStyle.Present) then Result := ColStr(AStyle.TextColor)
  else if (p = 'border-color') and (tpBorderColor in AStyle.Present) then Result := ColStr(AStyle.BorderColor)
  else if (p = 'border-width') and (tpBorderWidth in AStyle.Present) then Result := IntToStr(AStyle.BorderWidth) + 'px'
  else if (p = 'border-radius') and (tpBorderRadius in AStyle.Present) then Result := IntToStr(AStyle.BorderRadius) + 'px'
  else if (p = 'font-size') and (tpFontSize in AStyle.Present) then Result := IntToStr(AStyle.FontSize) + 'px'
  else if (p = 'font-family') and (tpFontName in AStyle.Present) then Result := AStyle.FontName
  else if (p = 'border-style') and (tpBorderStyle in AStyle.Present) then
    case AStyle.BorderStyle of
      tbsNone: Result := 'none'; tbsSolid: Result := 'solid';
      tbsOutset: Result := 'outset'; tbsInset: Result := 'inset';
    end
  else if (p = 'render-style') and (tpRenderStyle in AStyle.Present) then
    case AStyle.RenderStyle of
      trsFlat: Result := 'flat'; trsBevel3D: Result := 'bevel3d'; trsInset3D: Result := 'inset3d';
    end
  else if (p = 'font-weight') and (tpFontWeight in AStyle.Present) then
  begin
    if AStyle.FontWeight = 700 then Result := 'bold'
    else if AStyle.FontWeight = 400 then Result := 'normal'
    else Result := IntToStr(AStyle.FontWeight);
  end
  else if (p = 'opacity') and (tpOpacity in AStyle.Present) then Result := OpacityStr(AStyle.Opacity)
  else if (p = 'padding') and (tpPadding in AStyle.Present) then
    Result := Format('%dpx %dpx %dpx %dpx',
      [AStyle.Padding.Top, AStyle.Padding.Right, AStyle.Padding.Bottom, AStyle.Padding.Left]);
  { everything else (background/shadow/glass/outline/window-shadow) is not a simple scalar -> '' }
end;

end.
