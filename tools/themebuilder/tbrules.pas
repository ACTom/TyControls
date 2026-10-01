unit tbrules;
{ Rules by typeKey and variant, for Ctrl+click in the preview and the coverage check: where
  the rules for "TyButton.primary" are in the text (their selectors, text order), and the
  edit that adds one when there is none.

  Only a selector that is exactly the type and the variant with no state counts:
  TyButton.primary:hover is a rule about hovering, not THE rule for the control. Type and
  variant compare without case, as the engine compares them. The selectors come from the
  forgiving scan (tbcssscan), so a commented-out rule is not found and a selector in a
  comma list is (each one on its own).

  A rule with no variant and no state is not just one more rule to the engine: the first
  one the user layer has for a typeKey takes the WHOLE base layer away from that typeKey --
  its plain rule, its states, its variants (StyleModel.UserHasTypeKey; the theme owns the
  control once it dresses it). An empty one would leave the control with no fill, no
  border, no ink. So a plain rule is not added empty when the base has rules for the
  typeKey: TbOwnRuleEdits adds the base's rules for it as the document's own -- the plain
  rule with the base's declarations, then each base rule for a variant or a state with
  only this typeKey's selectors, in the base's order -- and the control looks as it did.
  They go before the document's first rule for the typeKey (a `TyEdit:focus` the document
  already has must still come after the base's `TyEdit:focus` it was written over), else
  at the end. A variant rule (`TyButton.primary`) takes nothing away and is added empty. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, tbcssscan;

function TbSelectorText(const ATypeKey, AVariant: string): string;   { 'TyButton.primary' }
{ offsets of the selectors that are exactly ATypeKey[.AVariant] with no state, text order }
function TbFindRuleSelectors(AScan: TTbCssScan; const ATypeKey, AVariant: string): TTbOffsets;
{ an empty rule at the end; ACaret: where the caret goes in TbApplyEdits(AScan.Text, Result) }
function TbNewRuleEdits(AScan: TTbCssScan; const AEol, ATypeKey, AVariant: string;
  out ACaret: Integer): TTbTextEdits;
{ The base layer's rules for ATypeKey (TyBuiltinThemeCss) as the document's own: the plain
  rule (every declaration of every base rule with a plain selector for it, in order), then
  the variant and state rules with only ATypeKey's selectors. '' when the base has no rule
  for it. ACaretAt: the offset in the result where the first declaration starts (or the
  empty line of the plain rule) }
function TbBaseRulesText(const ATypeKey, AEol: string; out ACaretAt: Integer): string;
{ the plain rule for ATypeKey that keeps the look: TbBaseRulesText before the document's
  first rule for the typeKey, else at the end; an empty rule (TbNewRuleEdits) when the base
  has none. ACaret as for TbNewRuleEdits }
function TbOwnRuleEdits(AScan: TTbCssScan; const AEol, ATypeKey: string;
  out ACaret: Integer): TTbTextEdits;

implementation

uses
  tyControls.DefaultTheme;

var
  GBaseScan: TTbCssScan = nil;   { TyBuiltinThemeCss, scanned once }

function BaseScan: TTbCssScan;
begin
  if GBaseScan = nil then
    GBaseScan := TbScanCss(TyBuiltinThemeCss);
  Result := GBaseScan;
end;

function SelectorRefText(const ARef: TTbSelectorRef): string;
begin
  Result := TbSelectorText(ARef.TypeName, ARef.Variant);
  if ARef.State <> '' then
    Result := Result + ':' + ARef.State;
end;

function TbBaseRulesText(const ATypeKey, AEol: string; out ACaretAt: Integer): string;
var
  scan: TTbCssScan;
  b, s: Integer;
  blk: TTbBlock;
  plain, others, sels, decls: string;
  hasPlain, any: Boolean;

  function DeclLines(ABlock: Integer): string;
  var
    k: Integer;
  begin
    Result := '';
    for k := 0 to High(scan.Block(ABlock).Decls) do
      Result := Result + '  ' + scan.Block(ABlock).Decls[k].Name + ': '
        + scan.DeclValue(ABlock, k) + ';' + AEol;
  end;

begin
  ACaretAt := 0;
  scan := BaseScan;
  plain := '';
  others := '';
  any := False;
  for b := 0 to scan.Count - 1 do
  begin
    blk := scan.Block(b);
    if blk.Kind <> tbkRule then Continue;
    hasPlain := False;
    sels := '';
    for s := 0 to High(blk.Selectors) do
      if SameText(blk.Selectors[s].TypeName, ATypeKey) then
      begin
        any := True;
        if (blk.Selectors[s].Variant = '') and (blk.Selectors[s].State = '') then
          hasPlain := True
        else
        begin
          if sels <> '' then sels := sels + ', ';
          sels := sels + SelectorRefText(blk.Selectors[s]);
        end;
      end;
    if not (hasPlain or (sels <> '')) then Continue;
    decls := DeclLines(b);
    if hasPlain then
      plain := plain + decls;
    if sels <> '' then
      others := others + AEol + sels + ' {' + AEol + decls + '}' + AEol;
  end;
  if not any then
    Exit('');
  Result := ATypeKey + ' {' + AEol;
  ACaretAt := Length(Result) + 3;    { after the indent of the first line inside }
  if plain = '' then
    Result := Result + '  ' + AEol   { the base has rules for its states or variants only }
  else
    Result := Result + plain;
  Result := Result + '}' + AEol + others;
  { no final break: the caller puts the text between others }
  SetLength(Result, TbEndInsertPos(Result) - 1);
end;

function TbOwnRuleEdits(AScan: TTbCssScan; const AEol, ATypeKey: string;
  out ACaret: Integer): TTbTextEdits;
var
  text: string;
  at, b, s, p: Integer;
  blk: TTbBlock;
begin
  text := TbBaseRulesText(ATypeKey, AEol, at);
  if text = '' then
    Exit(TbNewRuleEdits(AScan, AEol, ATypeKey, '', ACaret));
  { before the document's first rule for this typeKey: its rules for states and variants
    were written over the base's, and must still come after them }
  p := 0;
  for b := 0 to AScan.Count - 1 do
  begin
    blk := AScan.Block(b);
    if blk.Kind <> tbkRule then Continue;
    for s := 0 to High(blk.Selectors) do
      if SameText(blk.Selectors[s].TypeName, ATypeKey) then
      begin
        p := blk.HeadStart;
        Break;
      end;
    if p > 0 then Break;
  end;
  SetLength(Result, 1);
  if p > 0 then
  begin
    Result[0] := TbEdit(p, p, text + AEol + AEol);
    ACaret := p + at - 1;
  end
  else if TbIsBlank(AScan.Text) then
  begin
    Result[0] := TbEdit(1, Length(AScan.Text) + 1, text + AEol);
    ACaret := at;
  end
  else
  begin
    p := TbEndInsertPos(AScan.Text);
    Result[0] := TbEdit(p, p, AEol + AEol + text);
    ACaret := p + Length(AEol + AEol) + at - 1;
  end;
end;

function TbSelectorText(const ATypeKey, AVariant: string): string;
begin
  Result := ATypeKey;
  if AVariant <> '' then
    Result := Result + '.' + AVariant;
end;

function TbFindRuleSelectors(AScan: TTbCssScan; const ATypeKey, AVariant: string): TTbOffsets;
var
  b, s: Integer;
  blk: TTbBlock;
begin
  Result := nil;
  for b := 0 to AScan.Count - 1 do
  begin
    blk := AScan.Block(b);
    if blk.Kind <> tbkRule then Continue;
    for s := 0 to High(blk.Selectors) do
      if SameText(blk.Selectors[s].TypeName, ATypeKey)
         and SameText(blk.Selectors[s].Variant, AVariant)
         and (blk.Selectors[s].State = '') then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := blk.Selectors[s].Start;
      end;
  end;
end;

function TbNewRuleEdits(AScan: TTbCssScan; const AEol, ATypeKey, AVariant: string;
  out ACaret: Integer): TTbTextEdits;
var
  sel, head: string;
  p: Integer;
begin
  sel := TbSelectorText(ATypeKey, AVariant);
  { the caret goes on the empty line between the braces, indented }
  head := sel + ' {' + AEol + '  ';
  SetLength(Result, 1);
  if TbIsBlank(AScan.Text) then
  begin
    Result[0] := TbEdit(1, Length(AScan.Text) + 1, head + AEol + '}' + AEol);
    ACaret := 1 + Length(head);
  end
  else
  begin
    p := TbEndInsertPos(AScan.Text);
    Result[0] := TbEdit(p, p, AEol + AEol + head + AEol + '}');
    ACaret := p + Length(AEol + AEol + head);
  end;
end;

finalization
  FreeAndNil(GBaseScan);
end.
