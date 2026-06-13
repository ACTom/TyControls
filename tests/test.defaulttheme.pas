unit test.defaulttheme;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry,
  tyControls.Types, tyControls.StyleModel, tyControls.DefaultTheme;
type
  TBuiltinThemeTest = class(TTestCase)
  private
    function NormalizeCss(const S: string): string;
  published
    procedure TestBuiltinMatchesLightTheme;
    procedure TestBuiltinCoversAllTypeKeys;
  end;
implementation

function TBuiltinThemeTest.NormalizeCss(const S: string): string;
{ Robust to line-ending and trailing-whitespace differences. }
var sl: TStringList; i: Integer;
begin
  sl := TStringList.Create;
  try
    sl.Text := S;
    for i := 0 to sl.Count - 1 do
      sl[i] := TrimRight(sl[i]);
    Result := Trim(sl.Text);
  finally
    sl.Free;
  end;
end;

procedure TBuiltinThemeTest.TestBuiltinMatchesLightTheme;
{ The embedded built-in skin must stay identical to themes/light.tycss. }
var
  path: string;
  fileText: TStringList;
begin
  path := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes'
    + PathDelim + 'light.tycss';
  AssertTrue('light.tycss must exist for sync check', FileExists(path));
  fileText := TStringList.Create;
  try
    fileText.LoadFromFile(path);
    AssertEquals('built-in skin must equal themes/light.tycss',
      NormalizeCss(fileText.Text), NormalizeCss(TyBuiltinThemeCss));
  finally
    fileText.Free;
  end;
end;

procedure TBuiltinThemeTest.TestBuiltinCoversAllTypeKeys;
{ Parsing the built-in CSS into a model's user layer must resolve every styled
  typeKey with its key property present. }
var
  m: TTyStyleModel;
  procedure AssertBg(const Key: string; AStates: TTyStateSet);
  begin
    AssertTrue(Key + ' must set Background',
      tpBackground in m.ResolveStyle(Key, '', AStates).Present);
  end;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss(TyBuiltinThemeCss);
    AssertBg('TyButton', []);
    AssertBg('TyEdit', []);
    AssertBg('TyCheckBox', []);
    AssertBg('TyRadioButton', []);
    AssertBg('TyPanel', []);
    AssertBg('TyComboBox', []);
    AssertBg('TyScrollBar', []);
    AssertBg('TyTitleBar', []);
    AssertBg('TyListBox', []);
    AssertBg('TyListItem', [tysActive]);
    AssertBg('TyProgressBar', []);
    AssertBg('TyProgressFill', []);
    AssertBg('TyToggleSwitch', [tysActive]);
    AssertBg('TyTrackBar', []);
    AssertBg('TyTrackThumb', []);
    AssertBg('TyTabControl', []);
    AssertBg('TyTab', [tysActive]);
    AssertTrue('TyGroupBox must set BorderColor',
      tpBorderColor in m.ResolveStyle('TyGroupBox', '', []).Present);
    AssertTrue('TyLabel must set TextColor',
      tpTextColor in m.ResolveStyle('TyLabel', '', []).Present);
  finally
    m.Free;
  end;
end;

initialization
  RegisterTest(TBuiltinThemeTest);
end.
