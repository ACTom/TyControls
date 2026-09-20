unit test.toolwindow.theme;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry,
  tyControls.Types, tyControls.StyleModel, tyControls.Controller, tyControls.BuiltinThemes,
  tyControls.ToolWindows;

type
  TTyToolWindowThemeTests = class(TTestCase)
  private
    function ThemePath(const AFile: string): string;
  published
    procedure TestEveryLengthTokenIsDeclaredAndEqualsTheControlDefault;
    procedure TestSurfaceKeysReachEveryBuiltinTheme;
    procedure TestStripItemSelectedDiffersFromRest;
  end;

implementation

type
  TTokenCase = record Name: string; Def: Integer; end;

const
  CTokens: array[0..13] of TTokenCase = (
    (Name: TyToolWindowButtonSizeVar;         Def: TyToolWindowButtonSizeDef),
    (Name: TyToolWindowContentMinVar;         Def: TyToolWindowContentMinDef),
    (Name: TyToolWindowDropSizeVar;           Def: TyToolWindowDropSizeDef),
    (Name: TyToolWindowEdgeSizeVar;           Def: TyToolWindowEdgeSizeDef),
    (Name: TyToolWindowGlyphSizeVar;          Def: TyToolWindowGlyphSizeDef),
    (Name: TyToolWindowHeaderGapVar;          Def: TyToolWindowHeaderGapDef),
    (Name: TyToolWindowHeaderHeightVar;       Def: TyToolWindowHeaderHeightDef),
    (Name: TyToolWindowHeaderPadVar;          Def: TyToolWindowHeaderPadDef),
    (Name: TyToolWindowIndicatorSizeVar;      Def: TyToolWindowIndicatorSizeDef),
    (Name: TyToolWindowStripIndicatorSizeVar; Def: TyToolWindowStripIndicatorSizeDef),
    (Name: TyToolWindowStripItemSizeVar;      Def: TyToolWindowStripItemSizeDef),
    (Name: TyToolWindowStripSizeVar;          Def: TyToolWindowStripSizeDef),
    (Name: TyToolWindowTabAreaMinVar;         Def: TyToolWindowTabAreaMinDef),
    (Name: TyToolWindowTabPadVar;             Def: TyToolWindowTabPadDef));

  CSurfaceKeys: array[0..3] of string = (
    'TyToolWindowBar', 'TyToolWindow', 'TyToolWindowStrip', 'TyToolWindowHeader');

function TTyToolWindowThemeTests.ThemePath(const AFile: string): string;
begin
  { Resolve against the executable, not the working directory -- the suite is run
    from several places and a bare '../themes' silently misses. }
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes' + PathDelim + AFile;
end;

procedure TTyToolWindowThemeTests.TestEveryLengthTokenIsDeclaredAndEqualsTheControlDefault;
const
  cSentinel = -12345;
var
  m: TTyStyleModel;
  i, got: Integer;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromFile(ThemePath('light.tycss'));
    for i := 0 to High(CTokens) do
    begin
      got := m.ResolveMetric(CTokens[i].Name, cSentinel);
      AssertTrue(CTokens[i].Name + ' 必须在 light.tycss 的 :root 里声明 —— 拿回哨兵值'
        + '说明它压根没定义,或者解析不成长度', got <> cSentinel);
      AssertEquals(CTokens[i].Name + ' 的经典值必须等于控件常量', CTokens[i].Def, got);
    end;
  finally
    m.Free;
  end;
end;

procedure TTyToolWindowThemeTests.TestSurfaceKeysReachEveryBuiltinTheme;
var
  c: TTyStyleController;
  names: TStringArray;
  i, k, md: Integer;
  mode: string;
begin
  TyRegisterBuiltinThemes;
  c := TTyStyleController.Create(nil);
  try
    names := TyBuiltinThemeNames;
    AssertTrue('有内置主题可查', Length(names) > 0);
    for i := 0 to High(names) do
      for md := 0 to 1 do
      begin
        if md = 0 then mode := 'light' else mode := 'dark';
        c.ThemeName := names[i];
        c.Mode := mode;
        for k := 0 to High(CSurfaceKeys) do
          AssertTrue(Format('%s/%s: %s 必须经基础层拿到底色', [names[i], mode, CSurfaceKeys[k]]),
            tpBackground in c.Model.ResolveStyle(CSurfaceKeys[k], '', []).Present);
      end;
  finally
    c.Free;
  end;
end;

procedure TTyToolWindowThemeTests.TestStripItemSelectedDiffersFromRest;
var
  m: TTyStyleModel;
  rest, sel: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromFile(ThemePath('light.tycss'));
    rest := m.ResolveStyle('TyToolWindowStripItem', '', []);
    sel := m.ResolveStyle('TyToolWindowStripItem', '', [tysSelected]);
    AssertTrue('当前图标的墨色必须和静止态不同,否则图标条上看不出选中',
      sel.TextColor <> rest.TextColor);
  finally
    m.Free;
  end;
end;

initialization
  RegisterTest(TTyToolWindowThemeTests);
end.
