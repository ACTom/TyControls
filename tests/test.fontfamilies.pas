unit test.fontfamilies;
{ TyGetFontFamilies against the fonts actually installed on this machine. The answers are the
  system's, so every assertion first checks the font is there and is skipped otherwise; on a
  stock Windows 10/11 Courier New / Consolas are fixed-pitch TrueType, Arial / Segoe UI are
  proportional, and Fixedsys / Terminal / MS Sans Serif are bitmap fonts. }
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Forms, fpcunit, testregistry, tyControls.FontFamilies;
type
  TFontFamiliesTest = class(TTestCase)
  private
    FList: TStringList;
    function Installed(const AName: string): Boolean;
    procedure AssertOrderedSubsetOfScreenFonts;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestNoFilterIsScreenFonts;
    procedure TestFixedPitchKeepsMonospaceOnly;
    procedure TestScalableDropsBitmapFonts;
    procedure TestBothFiltersIntersect;
  end;
implementation

procedure TFontFamiliesTest.SetUp;
begin
  FList := TStringList.Create;
end;

procedure TFontFamiliesTest.TearDown;
begin
  FreeAndNil(FList);
end;

function TFontFamiliesTest.Installed(const AName: string): Boolean;
begin
  Result := Screen.Fonts.IndexOf(AName) >= 0;
end;

{ The filtered list is Screen.Fonts with rows taken out -- same spelling, same order. }
procedure TFontFamiliesTest.AssertOrderedSubsetOfScreenFonts;
var i, j: Integer;
begin
  j := 0;
  for i := 0 to FList.Count - 1 do
  begin
    while (j < Screen.Fonts.Count) and (Screen.Fonts[j] <> FList[i]) do Inc(j);
    AssertTrue('"' + FList[i] + '" is a Screen.Fonts row, in Screen.Fonts order',
      j < Screen.Fonts.Count);
    Inc(j);
  end;
end;

procedure TFontFamiliesTest.TestNoFilterIsScreenFonts;
var i: Integer;
begin
  TyGetFontFamilies(FList, False, False);
  AssertEquals('row count', Screen.Fonts.Count, FList.Count);
  for i := 0 to FList.Count - 1 do
    AssertEquals('row ' + IntToStr(i), Screen.Fonts[i], FList[i]);
end;

procedure TFontFamiliesTest.TestFixedPitchKeepsMonospaceOnly;
begin
  if not (Installed('Courier New') and Installed('Arial')) then
    Ignore('needs Courier New and Arial installed');
  TyGetFontFamilies(FList, True);
  AssertTrue('Courier New is fixed-pitch', FList.IndexOf('Courier New') >= 0);
  if Installed('Consolas') then
    AssertTrue('Consolas is fixed-pitch', FList.IndexOf('Consolas') >= 0);
  AssertTrue('Arial is proportional', FList.IndexOf('Arial') < 0);
  if Installed('Segoe UI') then
    AssertTrue('Segoe UI is proportional', FList.IndexOf('Segoe UI') < 0);
  AssertTrue('a filter, not the whole list', FList.Count < Screen.Fonts.Count);
  AssertOrderedSubsetOfScreenFonts;
end;

procedure TFontFamiliesTest.TestScalableDropsBitmapFonts;
const
  Bitmaps: array[0..2] of string = ('Fixedsys', 'Terminal', 'MS Sans Serif');
var
  b: string;
  any: Boolean;
begin
  if not Installed('Arial') then Ignore('needs Arial installed');
  TyGetFontFamilies(FList, False, True);
  AssertTrue('Arial is scalable', FList.IndexOf('Arial') >= 0);
  any := False;
  for b in Bitmaps do
    if Installed(b) then
    begin
      any := True;
      AssertTrue(b + ' is a bitmap font', FList.IndexOf(b) < 0);
    end;
  if not any then Ignore('no known bitmap font installed (Windows only)');
  AssertOrderedSubsetOfScreenFonts;
end;

procedure TFontFamiliesTest.TestBothFiltersIntersect;
begin
  if not (Installed('Courier New') and Installed('Arial') and Installed('Fixedsys')) then
    Ignore('needs Courier New, Arial and the bitmap Fixedsys installed');
  TyGetFontFamilies(FList, True, True);
  AssertTrue('Courier New: fixed-pitch AND scalable', FList.IndexOf('Courier New') >= 0);
  AssertTrue('Fixedsys: fixed-pitch but a bitmap font', FList.IndexOf('Fixedsys') < 0);
  AssertTrue('Arial: scalable but proportional', FList.IndexOf('Arial') < 0);
end;

initialization
  RegisterTest(TFontFamiliesTest);
end.
