unit test.css.addons;
{$mode objfpc}{$H+}

{ The add-on registry: an add-on package registers its own tycss and the core's vocabulary
  (tokens, typeKeys) grows with it. }

interface

uses
  Classes, SysUtils, fpcunit, testregistry;

type
  TTyCssAddOnsTest = class(TTestCase)
  protected
    procedure TearDown; override;
  published
    procedure TestTheVocabularyOfLightIsTheCatalog;
    procedure TestARegisteredCssJoinsTheCatalog;
    procedure TestReRegisteringReplaces;
    procedure TestNoAddOnIsTheCatalogAlone;
    procedure TestAListenerHearsARegistration;
    procedure TestCommentsAndUsagesAreNotVocabulary;
  end;

implementation

uses
  tyControls.Css.Catalog, tyControls.Css.AddOns;

var
  GHeard: Integer;

procedure Heard;
begin
  Inc(GHeard);
end;

function LightText: string;
var
  sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes' + PathDelim +
      'light.tycss');
    Result := sl.Text;
  finally
    sl.Free;
  end;
end;

function Has(const A: TStringArray; const S: string): Boolean;
var
  i: Integer;
begin
  for i := 0 to High(A) do
    if A[i] = S then
      Exit(True);
  Result := False;
end;

procedure AssertAscending(const AMsg: string; const A: TStringArray);
var
  i: Integer;
begin
  for i := 1 to High(A) do
    TTestCase.AssertTrue(AMsg + ' ascending at ' + IntToStr(i), A[i - 1] < A[i]);
end;

procedure TTyCssAddOnsTest.TearDown;
begin
  TyUnregisterAddOnCss('t1');
  TyUnregisterAddOnCss('t2');
  TyRemoveAddOnCssListener(@Heard);
  inherited TearDown;
end;

procedure TTyCssAddOnsTest.TestTheVocabularyOfLightIsTheCatalog;
var
  v: TTyCssVocabulary;
  i: Integer;
begin
  v := TyCssVocabularyOf(LightText);
  AssertEquals('token count', Length(TyCatalogTokens), Length(v.Tokens));
  AssertEquals('typeKey count', Length(TyCatalogTypeKeys), Length(v.TypeKeys));
  for i := 0 to High(v.Tokens) do
    AssertEquals('token ' + IntToStr(i), TyCatalogTokens[i], v.Tokens[i]);
  for i := 0 to High(v.TypeKeys) do
    AssertEquals('typeKey ' + IntToStr(i), TyCatalogTypeKeys[i], v.TypeKeys[i]);
end;

procedure TTyCssAddOnsTest.TestARegisteredCssJoinsTheCatalog;
var
  t, k: TStringArray;
begin
  TyRegisterAddOnCss('t1', ':root{--zz-a:1px} TyZzThing{color:red}');
  t := TyCatalogAllTokens;
  k := TyCatalogAllTypeKeys;
  AssertTrue('--zz-a joined', Has(t, '--zz-a'));
  AssertTrue('TyZzThing joined', Has(k, 'TyZzThing'));
  AssertTrue('the catalog stays', Has(t, '--accent'));
  AssertAscending('tokens', t);
  AssertAscending('typeKeys', k);
end;

procedure TTyCssAddOnsTest.TestReRegisteringReplaces;
begin
  TyRegisterAddOnCss('t1', 'FIRST{}');
  TyRegisterAddOnCss('t1', 'SECOND{}');
  AssertEquals('only the second', 'SECOND{}', TyAddOnCss);
  TyRegisterAddOnCss('t2', 'THIRD{}');
  AssertEquals('registration order', 'SECOND{}' + LineEnding + 'THIRD{}', TyAddOnCss);
end;

procedure TTyCssAddOnsTest.TestNoAddOnIsTheCatalogAlone;
var
  t, k: TStringArray;
  i: Integer;
begin
  AssertEquals('no css', '', TyAddOnCss);
  t := TyCatalogAllTokens;
  k := TyCatalogAllTypeKeys;
  AssertEquals('token count', Length(TyCatalogTokens), Length(t));
  AssertEquals('typeKey count', Length(TyCatalogTypeKeys), Length(k));
  for i := 0 to High(t) do
    AssertEquals('token ' + IntToStr(i), TyCatalogTokens[i], t[i]);
  for i := 0 to High(k) do
    AssertEquals('typeKey ' + IntToStr(i), TyCatalogTypeKeys[i], k[i]);
end;

procedure TTyCssAddOnsTest.TestAListenerHearsARegistration;
begin
  GHeard := 0;
  TyAddAddOnCssListener(@Heard);
  TyRegisterAddOnCss('t1', 'a{}');
  AssertEquals('heard once', 1, GHeard);
  TyRemoveAddOnCssListener(@Heard);
  TyRegisterAddOnCss('t1', 'b{}');
  AssertEquals('not after removal', 1, GHeard);
end;

procedure TTyCssAddOnsTest.TestCommentsAndUsagesAreNotVocabulary;
var
  v: TTyCssVocabulary;
begin
  v := TyCssVocabularyOf('/* TyInComment --in-comment: 1 */ TyReal{--b : 2; --b:3; ' +
    'color: var(--used); x: TyNot_this} Ty1 TyAb2 TyAb2');
  AssertEquals('one token, de-duplicated', 1, Length(v.Tokens));
  AssertEquals('--b', '--b', v.Tokens[0]);
  AssertEquals('typeKeys', 2, Length(v.TypeKeys));
  AssertEquals('TyAb2', 'TyAb2', v.TypeKeys[0]);
  AssertEquals('TyReal', 'TyReal', v.TypeKeys[1]);
end;

initialization
  RegisterTest(TTyCssAddOnsTest);

end.
