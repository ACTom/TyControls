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
    procedure TestVerticalVariantsAreNeverListed;
    procedure TestFixedPitchKeepsMonospaceOnly;
    procedure TestScalableDropsBitmapFonts;
    procedure TestBothFiltersIntersect;
  end;

{ What every font picker lists without a filter: Screen.Fonts minus the vertical "@" variants.
  Written out here rather than asked of TyGetFontFamilies, so the tests that compare against it
  are not comparing the code with itself. }
procedure FontsWithoutVerticalVariants(AList: TStrings);

implementation

procedure FontsWithoutVerticalVariants(AList: TStrings);
var i: Integer;
begin
  AList.Clear;
  for i := 0 to Screen.Fonts.Count - 1 do
    if Copy(Screen.Fonts[i], 1, 1) <> '@' then AList.Add(Screen.Fonts[i]);
end;

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
var i: Integer; plain: TStringList;
begin
  plain := TStringList.Create;
  try
    FontsWithoutVerticalVariants(plain);
    TyGetFontFamilies(FList, False, False);
    AssertEquals('row count', plain.Count, FList.Count);
    for i := 0 to FList.Count - 1 do
      AssertEquals('row ' + IntToStr(i), plain[i], FList[i]);
  finally plain.Free; end;
  AssertOrderedSubsetOfScreenFonts;
end;

procedure TFontFamiliesTest.TestVerticalVariantsAreNeverListed;
var fixed, scalable, i: Integer; any: Boolean;
begin
  { "@SimSun" is SimSun with its glyphs turned for vertical text -- and fixed-pitch whenever
    SimSun is, so the fixed-pitch list would pick it up too. }
  for fixed := 0 to 1 do
    for scalable := 0 to 1 do
    begin
      TyGetFontFamilies(FList, fixed = 1, scalable = 1);
      for i := 0 to FList.Count - 1 do
        AssertFalse(Format('fixed=%d scalable=%d: "%s" is a vertical variant',
          [fixed, scalable, FList[i]]), Copy(FList[i], 1, 1) = '@');
    end;
  any := False;
  for i := 0 to Screen.Fonts.Count - 1 do
    if Copy(Screen.Fonts[i], 1, 1) = '@' then any := True;
  if not any then Ignore('no vertical "@" font installed (Windows with a CJK font)');
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
