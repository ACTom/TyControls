unit test.darktext;
{ Dark-mode readability guard: EVERY control's text must contrast with the surface it sits on, in
  every skin's dark mode — not just the core controls a skin restyles. For each skin, take the menu
  popup (a solid themed surface) as the reference surface and flag any control whose resolved text
  colour has too little contrast against it. Catches the "menu/tree/tabset text is black and
  invisible on a dark surface" bug (a skin's @mode blocks replacing the base @mode vars). }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry,
  tyControls.Types, tyControls.StyleModel;
type
  TDarkTextTest = class(TTestCase)
  published
    procedure TestExtraControlsReadableInSkinDark;
    procedure TestSkinIdentitySurvivesImport;
  end;

implementation

function Lum(c: TTyColor): Integer;
begin
  Result := (TyRedOf(c) * 299 + TyGreenOf(c) * 587 + TyBlueOf(c) * 114) div 1000;
end;

function SkinPath(const AName: string): string;
{ green still lives in themes/ (it references url(assets/…)); the structural skins moved to themes/builtin/. }
var themesDir: string;
begin
  themesDir := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes' + PathDelim;
  if SameText(AName, 'green') then
    Result := themesDir + 'green.tycss'
  else
    Result := themesDir + 'builtin' + PathDelim + AName + '.tycss';
end;

procedure TDarkTextTest.TestExtraControlsReadableInSkinDark;
const
  KEYS: array[0..13] of string = (
    'TyMenuItem', 'TyMenuBar', 'TyMenuView', 'TyListItem', 'TyListBox', 'TyTab',
    'TyTabSheet', 'TyTreeNode', 'TyTreeView', 'TyTreeHeader', 'TyStatusBar', 'TyToolBar',
    'TyGroupBox', 'TyCalendarCell');
  SKINS: array[0..14] of string = (
    'win10', 'win11', 'macos', 'adwaita', 'breeze', 'ubuntu', 'office', 'antdesign',
    'bootstrap', 'material3', 'fluent', 'xp', 'aero', 'classic', 'green');
  MIN_CONTRAST = 55;
var
  failed: string;
  i, k: Integer;
  m: TTyStyleModel;
  s: TTyStyleSet;
  surfLum, txtLum: Integer;
begin
  failed := '';
  for i := 0 to High(SKINS) do
  begin
    m := TTyStyleModel.Create;
    try
      m.LoadFromFile(SkinPath(SKINS[i]));
      if m.DefaultModeName = '' then Continue;
      m.SetMode('dark');
      // Reference surface = the menu popup (a solid themed surface most floating controls sit on).
      s := m.ResolveStyle('TyMenuView', '', []);
      if not (tpBackground in s.Present) then Continue;
      surfLum := Lum(s.Background.Color);
      for k := 0 to High(KEYS) do
      begin
        s := m.ResolveStyle(KEYS[k], '', []);
        if not (tpTextColor in s.Present) then Continue;
        txtLum := Lum(s.TextColor);
        if Abs(txtLum - surfLum) < MIN_CONTRAST then
          failed := failed + Format('%s/%s ink=#%.2x%.2x%.2x on surfLum=%d; ',
            [SKINS[i], KEYS[k], TyRedOf(s.TextColor), TyGreenOf(s.TextColor), TyBlueOf(s.TextColor), surfLum]);
      end;
    finally
      m.Free;
    end;
  end;
  AssertEquals('every control''s text contrasts with the surface in each skin dark mode', '', failed);
end;

procedure TDarkTextTest.TestSkinIdentitySurvivesImport;
{ @import "auto.tycss" precedes the skin's own palette + rules, so the skin (later, "new wins")
  must still win: its brand accent and its distinctive control geometry are NOT clobbered by auto. }
var m: TTyStyleModel; s: TTyStyleSet;
begin
  // win11: dark brand accent #60CDFF (primary fill), 5px button radius (auto's is 6).
  m := TTyStyleModel.Create;
  try
    m.LoadFromFile(SkinPath('win11'));
    m.SetMode('dark');
    s := m.ResolveStyle('TyButton', 'primary', []);
    AssertEquals('win11 keeps its dark accent R', $60, TyRedOf(s.Background.Color));
    AssertEquals('win11 keeps its dark accent G', $CD, TyGreenOf(s.Background.Color));
    s := m.ResolveStyle('TyButton', '', []);
    AssertEquals('win11 keeps its 5px button radius (not auto''s 6)', 5, s.BorderRadius);
  finally m.Free; end;
  // antdesign light: brand blue #1677FF primary.
  m := TTyStyleModel.Create;
  try
    m.LoadFromFile(SkinPath('antdesign'));
    m.SetMode('light');
    s := m.ResolveStyle('TyButton', 'primary', []);
    AssertEquals('antdesign keeps its accent R', $16, TyRedOf(s.Background.Color));
    AssertEquals('antdesign keeps its accent G', $77, TyGreenOf(s.Background.Color));
  finally m.Free; end;
end;

initialization
  RegisterTest(TDarkTextTest);
end.
