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
    { E 期(spec §12):角标、放置预览两个键。 }
    procedure TestBadgeAndDropZoneReachEveryBuiltinTheme;
    procedure TestTheBadgeDefaultsToTheTyBadgeTokens;
    procedure TestTheBadgeColourGoesThroughItsToken;
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

function SameFill(const A, B: TTyFill): Boolean;
begin
  Result := (A.Kind = B.Kind) and (A.Color = B.Color);
end;

procedure TTyToolWindowThemeTests.TestBadgeAndDropZoneReachEveryBuiltinTheme;
var
  c: TTyStyleController;
  names: TStringArray;
  badge, zone, zoneHot: TTyStyleSet;
  i, md: Integer;
  mode, where: string;
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
        where := names[i] + '/' + mode + ': ';
        badge := c.Model.ResolveStyle(TyToolWindowBadgeKey, '', [tysNormal]);
        AssertTrue(where + '角标要有底色', (tpBackground in badge.Present)
          and (badge.Background.Kind <> tfkNone));
        AssertTrue(where + '角标要有墨色', tpTextColor in badge.Present);
        zone := c.Model.ResolveStyle(TyToolWindowDropZoneKey, '', [tysNormal]);
        zoneHot := c.Model.ResolveStyle(TyToolWindowDropZoneKey, '', [tysHover]);
        AssertTrue(where + '放置预览要有底色', (tpBackground in zone.Present)
          and (zone.Background.Kind <> tfkNone));
        AssertTrue(where + '放置预览要有边框色', tpBorderColor in zone.Present);
        AssertTrue(where + '放置预览的 :hover 底色要和静止态不同',
          not SameFill(zone.Background, zoneHot.Background));
      end;
  finally
    c.Free;
  end;
end;

procedure TTyToolWindowThemeTests.TestTheBadgeDefaultsToTheTyBadgeTokens;
var
  m: TTyStyleModel;
  tw, tb: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromFile(ThemePath('light.tycss'));
    tw := m.ResolveStyle(TyToolWindowBadgeKey, '', [tysNormal]);
    tb := m.ResolveStyle('TyBadge', '', [tysNormal]);
    AssertTrue('底色同 TyBadge(--accent)', SameFill(tb.Background, tw.Background));
    AssertTrue('墨色同 TyBadge(--on-accent)', tb.TextColor = tw.TextColor);
    AssertEquals('字重同 TyBadge', tb.FontWeight, tw.FontWeight);
  finally
    m.Free;
  end;
end;

procedure TTyToolWindowThemeTests.TestTheBadgeColourGoesThroughItsToken;
var
  c: TTyStyleController;
  before, after: TTyStyleSet;
begin
  c := TTyStyleController.Create(nil);
  try
    before := c.Model.ResolveStyle(TyToolWindowBadgeKey, '', [tysNormal]);
    c.StyleOverride := ':root { --toolwindow-badge-bg: #123456; }';
    after := c.Model.ResolveStyle(TyToolWindowBadgeKey, '', [tysNormal]);
    AssertFalse('皮肤改 --toolwindow-badge-bg,角标底色跟着变',
      SameFill(before.Background, after.Background));
    AssertTrue('就是那个颜色', after.Background.Color = TTyColor($FF123456));
  finally
    c.Free;
  end;
end;

initialization
  RegisterTest(TTyToolWindowThemeTests);
end.
