unit test.themelint;
{ E23 (DX) — lint / strict mode tests. Exercises TyLintCss across its four diagnostic
  categories (unknown property, undefined variable, missing asset, low contrast), the
  non-raising contract (a bad value/parse never throws — it becomes a warning), the
  @import flatten path, and the headline sanity guard: the shipped light.tycss lints
  clean (empty result). All assertions are headless. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry,
  tyControls.ThemeLint;

type
  TThemeLintTest = class(TTestCase)
  private
    function ThemesDir: string;
    function ThemePath(const AName: string): string;
    // True if ANY warning contains ASub (case-sensitive substring match).
    function HasWarning(const AWarnings: TTyLintResult; const ASub: string): Boolean;
    function CountWarnings(const AWarnings: TTyLintResult; const ASub: string): Integer;
    function JoinWarnings(const AWarnings: TTyLintResult): string;
  published
    // (1) unknown property
    procedure TestUnknownProperty;
    procedure TestKnownPropertyNotFlagged;
    procedure TestUnknownPropDoesNotMaskUndefinedVar;
    // (2) undefined variable
    procedure TestUndefinedVarInVarRef;
    procedure TestUndefinedVarBareLeaf;
    procedure TestDefinedVarNotFlagged;
    procedure TestDynamicTokensNotFlagged;
    procedure TestVarDefinedOnlyInModeBlock;
    // (3) missing asset
    procedure TestMissingAsset;
    procedure TestPresentAssetNotFlagged;
    procedure TestAssetsSkippedWithoutBaseDir;
    // (4) low contrast
    procedure TestLowContrast;
    procedure TestHighContrastNotFlagged;
    procedure TestTransparentBgNoContrastFalsePositive;
    // non-raising / robustness
    procedure TestCleanCssEmpty;
    procedure TestParseErrorBecomesWarningNotRaise;
    procedure TestMissingImportReported;
    procedure TestImportedVarsResolve;
    // the headline sanity guard
    procedure TestLightThemeLintsClean;
  end;

implementation

function TThemeLintTest.ThemesDir: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes' + PathDelim;
end;

function TThemeLintTest.ThemePath(const AName: string): string;
begin
  Result := ThemesDir + AName;
end;

function TThemeLintTest.HasWarning(const AWarnings: TTyLintResult; const ASub: string): Boolean;
var i: Integer;
begin
  Result := False;
  for i := 0 to High(AWarnings) do
    if Pos(ASub, AWarnings[i]) > 0 then Exit(True);
end;

function TThemeLintTest.CountWarnings(const AWarnings: TTyLintResult; const ASub: string): Integer;
var i: Integer;
begin
  Result := 0;
  for i := 0 to High(AWarnings) do
    if Pos(ASub, AWarnings[i]) > 0 then Inc(Result);
end;

function TThemeLintTest.JoinWarnings(const AWarnings: TTyLintResult): string;
var i: Integer;
begin
  Result := '';
  for i := 0 to High(AWarnings) do
    Result := Result + '[' + AWarnings[i] + ']';
end;

{ ── (1) unknown property ──────────────────────────────────────────────────── }

procedure TThemeLintTest.TestUnknownProperty;
var w: TTyLintResult;
begin
  // 'frobnicate' is not a known property; 'color' is. Only the former is flagged.
  w := TyLintCss(':root { --c: #112233; }'
              + 'TyButton { color: var(--c); frobnicate: 7px; }');
  AssertTrue('flags unknown property frobnicate: ' + JoinWarnings(w),
    HasWarning(w, 'unknown property ''frobnicate'''));
  AssertEquals('exactly one unknown-property warning', 1,
    CountWarnings(w, 'unknown property'));
end;

procedure TThemeLintTest.TestKnownPropertyNotFlagged;
var w: TTyLintResult;
begin
  // every property here is recognised by TyApplyDeclaration -> no unknown-property warning
  w := TyLintCss(':root { --a: #3B82F6; --s: #FFFFFF; --o: #1F2937; }'
    + 'TyButton { background: var(--s); color: var(--o); border-color: var(--a);'
    + ' border-width: 1px; border-radius: 6px; padding: 6px;'
    + ' font-size: 9px; font-weight: bold; opacity: 0.5; }');
  AssertEquals('no unknown-property warnings: ' + JoinWarnings(w), 0,
    CountWarnings(w, 'unknown property'));
end;

procedure TThemeLintTest.TestUnknownPropDoesNotMaskUndefinedVar;
var w: TTyLintResult;
begin
  // The value references an UNDEFINED var AND the property is unknown. The undefined-var
  // eval must NOT swallow the unknown-property signal (the engine fact: catch eval excs).
  w := TyLintCss('TyButton { frobnicate: var(--nope); }');
  AssertTrue('still flags unknown property despite bad value: ' + JoinWarnings(w),
    HasWarning(w, 'unknown property ''frobnicate'''));
  AssertTrue('also flags the undefined variable: ' + JoinWarnings(w),
    HasWarning(w, 'undefined variable --nope'));
end;

{ ── (2) undefined variable ────────────────────────────────────────────────── }

procedure TThemeLintTest.TestUndefinedVarInVarRef;
var w: TTyLintResult;
begin
  w := TyLintCss('TyButton { color: var(--ghost); }');
  AssertTrue('flags undefined var in var(): ' + JoinWarnings(w),
    HasWarning(w, 'undefined variable --ghost'));
end;

procedure TThemeLintTest.TestUndefinedVarBareLeaf;
var w: TTyLintResult;
begin
  // bare '--name' leaf inside a function arg (e.g. darken(--surface, 4%)) is also a ref
  w := TyLintCss('TyButton { background: darken(--missing, 4%); }');
  AssertTrue('flags undefined bare-leaf var: ' + JoinWarnings(w),
    HasWarning(w, 'undefined variable --missing'));
end;

procedure TThemeLintTest.TestDefinedVarNotFlagged;
var w: TTyLintResult;
begin
  // --derived references --base; both defined -> no undefined-variable warning
  w := TyLintCss(':root { --base: #3B82F6; --derived: lighten(--base, 8%); }'
    + 'TyButton { background: var(--derived); }');
  AssertEquals('no undefined-variable warnings: ' + JoinWarnings(w), 0,
    CountWarnings(w, 'undefined variable'));
end;

procedure TThemeLintTest.TestDynamicTokensNotFlagged;
var w: TTyLintResult;
begin
  // system-accent / system-mode / transparent / none / ty-mode are dynamic, not "undefined"
  w := TyLintCss(':root { --accent: system-accent; --m: system-mode; }'
    + 'TyButton { background: transparent; border-style: none;'
    + ' color: elevate(var(--accent), 8%); }');
  AssertEquals('dynamic tokens never reported undefined: ' + JoinWarnings(w), 0,
    CountWarnings(w, 'undefined variable'));
end;

procedure TThemeLintTest.TestVarDefinedOnlyInModeBlock;
var w: TTyLintResult;
begin
  // --tint is declared ONLY inside an @mode block; a shared-body reference to it is valid.
  w := TyLintCss(':root { --accent: #3B82F6; }'
    + 'TyButton { background: var(--tint); }'
    + '@mode dark { :root { --tint: #0B1120; } }');
  AssertEquals('mode-only var is defined: ' + JoinWarnings(w), 0,
    CountWarnings(w, 'undefined variable'));
end;

{ ── (3) missing asset ─────────────────────────────────────────────────────── }

procedure TThemeLintTest.TestMissingAsset;
var w: TTyLintResult; dir: string;
begin
  dir := GetTempDir(False);   // a real dir, but the asset file does not exist in it
  w := TyLintCss('TyPanel { background-image: url(no_such_image.png) slice(4 4 4 4); }', dir);
  AssertTrue('flags missing asset: ' + JoinWarnings(w),
    HasWarning(w, 'missing asset ''no_such_image.png'''));
end;

procedure TThemeLintTest.TestPresentAssetNotFlagged;
var w: TTyLintResult; dir, assetPath: string; sl: TStringList;
begin
  dir := IncludeTrailingPathDelimiter(GetTempDir(False));
  assetPath := dir + 'ty_lint_present_' + IntToStr(PtrUInt(Self)) + '.png';
  sl := TStringList.Create;
  try
    sl.Text := 'not-really-a-png-but-the-file-exists';
    sl.SaveToFile(assetPath);
    w := TyLintCss('TyPanel { background-image: url('
      + ExtractFileName(assetPath) + ') slice(4 4 4 4); }', dir);
    AssertEquals('present asset not flagged: ' + JoinWarnings(w), 0,
      CountWarnings(w, 'missing asset'));
  finally
    if FileExists(assetPath) then DeleteFile(assetPath);
    sl.Free;
  end;
end;

procedure TThemeLintTest.TestAssetsSkippedWithoutBaseDir;
var w: TTyLintResult;
begin
  // No base dir -> assets are not checkable -> no missing-asset false alarm.
  w := TyLintCss('TyPanel { background-image: url(whatever.png) slice(4 4 4 4); }');
  AssertEquals('no missing-asset warnings without base dir: ' + JoinWarnings(w), 0,
    CountWarnings(w, 'missing asset'));
end;

{ ── (4) low contrast ──────────────────────────────────────────────────────── }

procedure TThemeLintTest.TestLowContrast;
var w: TTyLintResult;
begin
  // near-black ink on near-black bg -> luminance delta ~0 -> flagged
  w := TyLintCss('TyButton { background: #111111; color: #131313; }');
  AssertTrue('flags low contrast: ' + JoinWarnings(w),
    HasWarning(w, 'low contrast on ''TyButton'''));
end;

procedure TThemeLintTest.TestHighContrastNotFlagged;
var w: TTyLintResult;
begin
  // dark ink on white surface -> large delta -> not flagged
  w := TyLintCss('TyButton { background: #FFFFFF; color: #1F2937; }');
  AssertEquals('high contrast not flagged: ' + JoinWarnings(w), 0,
    CountWarnings(w, 'low contrast'));
end;

procedure TThemeLintTest.TestTransparentBgNoContrastFalsePositive;
var w: TTyLintResult;
begin
  // a transparent/no background gives no real contrast signal -> never flagged even if the
  // ink happens to match the (nonexistent) fill. This mirrors TyLabel/TyGroupBox in themes.
  w := TyLintCss('TyLabel { background: transparent; color: #000000; }');
  AssertEquals('transparent bg never low-contrast: ' + JoinWarnings(w), 0,
    CountWarnings(w, 'low contrast'));
end;

{ ── non-raising / robustness ──────────────────────────────────────────────── }

procedure TThemeLintTest.TestCleanCssEmpty;
var w: TTyLintResult;
begin
  // A fully-valid little theme -> EMPTY result.
  w := TyLintCss(':root { --a: #3B82F6; --s: #FFFFFF; --o: #1F2937; --b: #D1D5DB; }'
    + 'TyButton { background: var(--s); color: var(--o); border-color: var(--b);'
    + ' border-width: 1px; border-radius: 6px; padding: 6px; }'
    + 'TyButton:hover { background: darken(var(--s), 4%); }');
  AssertEquals('clean CSS yields no warnings: ' + JoinWarnings(w), 0, Length(w));
end;

procedure TThemeLintTest.TestParseErrorBecomesWarningNotRaise;
var w: TTyLintResult;
begin
  // An unterminated rule must be a WARNING, not an exception (TyLintCss never raises).
  w := TyLintCss('TyButton { color: #FF0000 ');   // no ';' / no closing brace
  AssertTrue('a parse error is reported as a warning: ' + JoinWarnings(w),
    HasWarning(w, 'parse error'));
end;

procedure TThemeLintTest.TestMissingImportReported;
var w: TTyLintResult; dir: string;
begin
  dir := GetTempDir(False);
  // @import a file that does not exist -> a non-raising 'missing @import' warning.
  w := TyLintCss('@import "definitely_not_here.tycss";'
    + 'TyButton { color: #FF0000; }', dir);
  AssertTrue('missing @import reported: ' + JoinWarnings(w),
    HasWarning(w, 'missing @import ''definitely_not_here.tycss'''));
end;

procedure TThemeLintTest.TestImportedVarsResolve;
var w: TTyLintResult; dir, basePath: string; sl: TStringList;
begin
  dir := IncludeTrailingPathDelimiter(GetTempDir(False));
  basePath := dir + 'ty_lint_base_' + IntToStr(PtrUInt(Self)) + '.tycss';
  sl := TStringList.Create;
  try
    // the imported base defines --accent; the importer references it -> NOT undefined.
    sl.Text := ':root { --accent: #3B82F6; }';
    sl.SaveToFile(basePath);
    w := TyLintCss('@import "' + ExtractFileName(basePath) + '";'
      + 'TyButton { background: var(--accent); }', dir);
    AssertEquals('imported var is defined: ' + JoinWarnings(w), 0,
      CountWarnings(w, 'undefined variable'));
    AssertEquals('no missing-import warning for a present file: ' + JoinWarnings(w), 0,
      CountWarnings(w, 'missing @import'));
  finally
    if FileExists(basePath) then DeleteFile(basePath);
    sl.Free;
  end;
end;

{ ── the headline sanity guard ─────────────────────────────────────────────── }

procedure TThemeLintTest.TestLightThemeLintsClean;
var w: TTyLintResult; sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(ThemePath('light.tycss'));
    w := TyLintCss(sl.Text, ThemesDir);
    AssertEquals('shipped light.tycss lints clean: ' + JoinWarnings(w), 0, Length(w));
  finally
    sl.Free;
  end;
end;

initialization
  RegisterTest(TThemeLintTest);
end.
