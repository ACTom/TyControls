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
    procedure TestSelectedInkDiffersFromRest;
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
  st: TTyStyleSet;
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
        begin
          st := c.Model.ResolveStyle(CSurfaceKeys[k], '', []);
          AssertTrue(Format('%s/%s: %s 必须经基础层拿到底色', [names[i], mode, CSurfaceKeys[k]]),
            tpBackground in st.Present);
          { 声明了 background 不等于会画: `background: none` 两个条件都满足,然后一笔不落
            —— TyGridCell 就是故意这么写的,所以这不是假想的失败模式。 }
          AssertTrue(Format('%s/%s: %s 的底色必须是真能画出来的填充,解成 none 等于没底色',
            [names[i], mode, CSurfaceKeys[k]]), st.Background.Kind <> tfkNone);
        end;
      end;
  finally
    c.Free;
  end;
end;

procedure TTyToolWindowThemeTests.TestSelectedInkDiffersFromRest;
{ golden 的 STATES 停在 tysDisabled,:selected 压根不在那张网格里 —— 图标条和
  标签行「哪个是当前」全靠墨色区分,而这里是它们唯一的守卫。 }
var
  m: TTyStyleModel;
  procedure CheckKey(const AKey, AWhere: string);
  var
    rest, sel: TTyStyleSet;
  begin
    rest := m.ResolveStyle(AKey, '', []);
    sel := m.ResolveStyle(AKey, '', [tysSelected]);
    AssertTrue(AKey + ': 当前项的墨色必须和静止态不同,否则' + AWhere + '上看不出选中',
      sel.TextColor <> rest.TextColor);
  end;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromFile(ThemePath('light.tycss'));
    CheckKey('TyToolWindowStripItem', '图标条');
    CheckKey('TyToolWindowTab', '标签行');
  finally
    m.Free;
  end;
end;

initialization
  RegisterTest(TTyToolWindowThemeTests);
end.
