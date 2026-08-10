unit tyControls.Css.Complete;
{$mode objfpc}{$H+}

{ The PURE logic behind the design-time StyleOverride editor: what to suggest at a caret, and
  which properties are unknown (the resolver silently drops those, so the editor is the only
  place a typo surfaces). Kept in a runtime unit -- no SynEdit, no PropEdits -- so it is
  unit-tested headless; the design-time dialog is a thin shell over it. }

interface

uses
  Classes;

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

end.
