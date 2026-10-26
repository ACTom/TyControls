unit test.editinputfilter;
{ #122: a numeric edit's paste and input-method commit take the typed key's filter, so
  letters cannot get in that way either; and TTyEdit.Text := applies CharCase, as LCL's
  RealSetText does (customedit.inc:546). }
{$mode objfpc}{$H+}
interface

uses
  Classes, SysUtils, StdCtrls, fpcunit, testregistry,
  tyControls.Edit, tyControls.NumericEdit, tyControls.CurrencyEdit;

type
  { InjectStringAt is the one funnel a paste and an IME commit both arrive through. }
  TNumericPasteProbe = class(TTyNumericEdit)
  public
    procedure Paste(const S: string);
  end;

  TCurrencyPasteProbe = class(TTyCurrencyEdit)
  public
    procedure Paste(const S: string);
  end;

  TEditInputFilterTest = class(TTestCase)
  published
    procedure TestAPasteKeepsOnlyTheNumber;
    procedure TestNoSeparatorWithoutDecimals;
    procedure TestAMultiByteCommitIsDropped;
    procedure TestADescendantFiltersToo;
    procedure TestTextTakesUppercase;
    procedure TestTextTakesLowercase;
  end;

implementation

procedure TNumericPasteProbe.Paste(const S: string);
begin
  InjectStringAt(S);
end;

procedure TCurrencyPasteProbe.Paste(const S: string);
begin
  InjectStringAt(S);
end;

procedure TEditInputFilterTest.TestAPasteKeepsOnlyTheNumber;
var
  p: TNumericPasteProbe;
begin
  p := TNumericPasteProbe.Create(nil);
  try
    p.Text := '';
    p.Paste('-1,234.50 kg');
    AssertEquals('only what a key could type', '-1234.50', p.Text);
  finally
    p.Free;
  end;
end;

procedure TEditInputFilterTest.TestNoSeparatorWithoutDecimals;
var
  p: TNumericPasteProbe;
begin
  p := TNumericPasteProbe.Create(nil);
  try
    p.Decimals := 0;
    p.Text := '';
    p.Paste('12.5');
    AssertEquals('no decimals, no separator', '125', p.Text);
  finally
    p.Free;
  end;
end;

procedure TEditInputFilterTest.TestAMultiByteCommitIsDropped;
var
  p: TNumericPasteProbe;
begin
  p := TNumericPasteProbe.Create(nil);
  try
    p.Text := '';
    p.Paste('4' + #$E4#$BA#$94 + '2');   // '4', a CJK numeral, '2'
    AssertEquals('the CJK character goes whole', '42', p.Text);
  finally
    p.Free;
  end;
end;

procedure TEditInputFilterTest.TestADescendantFiltersToo;
var
  p: TCurrencyPasteProbe;
begin
  p := TCurrencyPasteProbe.Create(nil);
  try
    p.Text := '';
    p.Paste('abc7');
    AssertEquals('a currency edit inherits the filter', '7', p.Text);
  finally
    p.Free;
  end;
end;

procedure TEditInputFilterTest.TestTextTakesUppercase;
var
  e: TTyEdit;
begin
  e := TTyEdit.Create(nil);
  try
    e.CharCase := ecUppercase;
    e.Text := 'abc';
    AssertEquals('converted, as LCL''s', 'ABC', e.Text);
  finally
    e.Free;
  end;
end;

procedure TEditInputFilterTest.TestTextTakesLowercase;
var
  e: TTyEdit;
begin
  e := TTyEdit.Create(nil);
  try
    e.CharCase := ecLowerCase;
    e.Text := 'MiXeD';
    AssertEquals('converted, as LCL''s', 'mixed', e.Text);
  finally
    e.Free;
  end;
end;

initialization
  RegisterTest(TEditInputFilterTest);
end.
