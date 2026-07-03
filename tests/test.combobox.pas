unit test.combobox;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry, tyControls.ComboBox;
type
  TComboFilterTest = class(TTestCase)
  published
    procedure TestPrefixFilter;
    procedure TestEmptyPrefixReturnsAll;
    procedure TestNoMatchReturnsEmpty;
  end;
implementation

procedure TComboFilterTest.TestPrefixFilter;
var src, dst: TStringList;
begin
  src := TStringList.Create;
  try
    src.AddStrings(['Alpha','Beta','Alubar','beacon']);
    dst := TyFilterItemsByPrefix(src, 'al');   // case-insensitive
    try
      AssertEquals('two match', 2, dst.Count);
      AssertEquals('Alpha', dst[0]); AssertEquals('Alubar', dst[1]);
    finally dst.Free; end;
  finally src.Free; end;
end;

procedure TComboFilterTest.TestEmptyPrefixReturnsAll;
var src, dst: TStringList;
begin
  src := TStringList.Create;
  try
    src.AddStrings(['a','b','c']);
    dst := TyFilterItemsByPrefix(src, '');
    try AssertEquals('all', 3, dst.Count); finally dst.Free; end;
  finally src.Free; end;
end;

procedure TComboFilterTest.TestNoMatchReturnsEmpty;
var src, dst: TStringList;
begin
  src := TStringList.Create;
  try
    src.AddStrings(['a','b']);
    dst := TyFilterItemsByPrefix(src, 'zzz');
    try AssertEquals('none', 0, dst.Count); finally dst.Free; end;
  finally src.Free; end;
end;

initialization
  RegisterTest(TComboFilterTest);
end.
