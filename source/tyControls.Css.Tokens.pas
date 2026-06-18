unit tyControls.Css.Tokens;

{$mode objfpc}{$H+}

interface

type
  TTyCssTokenKind = (ctkIdent, ctkHash, ctkNumber, ctkPercent, ctkColon, ctkSemicolon,
      ctkLBrace, ctkRBrace, ctkDot, ctkComma, ctkLParen, ctkRParen, ctkString, ctkFunction,
      ctkAtKeyword, ctkDelim, ctkEOF);

  TTyCssToken = record
    Kind: TTyCssTokenKind;
    Text: string;
    Line, Col: Integer;
  end;

implementation

end.
