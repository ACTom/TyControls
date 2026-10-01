unit tbrules;
{ Rules by typeKey and variant, for Ctrl+click in the preview and the coverage check: where
  the rules for "TyButton.primary" are in the text (their selectors, text order), and the
  edit that adds an empty one at the end when there is none.

  Only a selector that is exactly the type and the variant with no state counts:
  TyButton.primary:hover is a rule about hovering, not THE rule for the control. Type and
  variant compare without case, as the engine compares them. The selectors come from the
  forgiving scan (tbcssscan), so a commented-out rule is not found and a selector in a
  comma list is (each one on its own). }
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

implementation

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

end.
