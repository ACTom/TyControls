unit test.themebundle;
{$mode objfpc}{$H+}
{ C — Theme bundle source tests (theme-system v2, Phase 2).

  Covers ITyThemeSource over a directory and over a .zip:
    * manifest (theme.json) parse-and-store: name / entry / dualMode;
    * a synthesized default manifest when no theme.json is present;
    * dir-source RootCss + ReadText + OpenAsset;
    * zip-source RootCss + ReadText + OpenAsset (in-memory TUnZipper);
    * THE parity guard: the SAME tiny CSS-only theme, loaded once as a folder bundle
      and once as a .zip of that folder, resolves to a BYTE-IDENTICAL style dump. This
      proves the source abstraction is transport-agnostic and that LoadFromSource over a
      zip produces the same pixels as over a dir (and as a plain LoadFromFile).

  The .zip is built in SetUp with TZipper from the committed dir fixture (no binary blob
  in git). The fixture (tests/fixtures/sample-theme/) is CSS-only by design: zipped IMAGE
  assets are a documented Phase 2 follow-up (the painter still wants a file path), so the
  parity is exercised on CSS + manifest only. }
interface
uses
  Classes, SysUtils, fpcunit, testregistry, zipper,
  tyControls.Types, tyControls.StyleModel, tyControls.ThemeBundle;
type
  TThemeBundleTest = class(TTestCase)
  private
    FFixtureDir: string;   // tests/fixtures/sample-theme/
    FZipPath: string;      // a temp .zip built from the fixture dir
    function DumpModel(AModel: TTyStyleModel): string;
    function DumpSource(ASource: ITyThemeSource): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    // manifest
    procedure TestDirManifestParsed;
    procedure TestDefaultManifestWhenNoJson;
    procedure TestParseManifestMalformedFallsBack;
    // dir source
    procedure TestDirRootCss;
    procedure TestDirReadTextAndOpenAsset;
    procedure TestDirAssetBaseDirIsFolder;
    // zip source
    procedure TestZipRootCssEqualsDir;
    procedure TestZipReadTextAndOpenAsset;
    procedure TestZipManifestParsed;
    procedure TestZipAssetBaseDirEmpty;
    // the parity guard
    procedure TestDirVsZipResolveIdentically;
    procedure TestSourceMatchesLoadFromFile;
  end;

implementation

const
  // A representative resolve grid (typeKey | variant | stateIndex). Covers base, a
  // variant, and a few states across the three controls the fixture styles.
  cStates: array[0..2] of TTyStateSet = ([], [tysHover], [tysFocused]);

function FixtureRoot: string;
begin
  // Relative to the test exe (in /tests) so it is CWD-independent.
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + 'sample-theme' + PathDelim;
end;

procedure ZipDir(const ADir, AZipPath: string);
var
  z: TZipper;
  files: TStringList;
  sr: TSearchRec;
begin
  files := TStringList.Create;
  z := TZipper.Create;
  try
    z.FileName := AZipPath;
    if FindFirst(ADir + '*', faAnyFile, sr) = 0 then
    begin
      repeat
        if (sr.Attr and faDirectory) = 0 then
          // archive name = bare file name (flat bundle), forward-slash by convention
          z.Entries.AddFileEntry(ADir + sr.Name, sr.Name);
      until FindNext(sr) <> 0;
      FindClose(sr);
    end;
    z.ZipAllFiles;
  finally
    z.Free;
    files.Free;
  end;
end;

procedure TThemeBundleTest.SetUp;
begin
  FFixtureDir := FixtureRoot;
  FZipPath := IncludeTrailingPathDelimiter(GetTempDir) + 'tybundle_' +
    IntToStr(PtrUInt(Self)) + '.zip';
  if FileExists(FZipPath) then DeleteFile(FZipPath);
  ZipDir(FFixtureDir, FZipPath);
end;

procedure TThemeBundleTest.TearDown;
begin
  if FileExists(FZipPath) then DeleteFile(FZipPath);
end;

function TThemeBundleTest.DumpModel(AModel: TTyStyleModel): string;
const
  cKeys: array[0..3] of string = ('TyButton', 'TyButton.primary', 'TyLabel', 'TyEdit');
var
  sl: TStringList;
  i, si, bar: Integer;
  key, variant: string;
  s: TTyStyleSet;
begin
  sl := TStringList.Create;
  try
    for i := 0 to High(cKeys) do
    begin
      bar := Pos('.', cKeys[i]);
      if bar = 0 then begin key := cKeys[i]; variant := ''; end
      else begin key := Copy(cKeys[i], 1, bar - 1); variant := Copy(cKeys[i], bar + 1, MaxInt); end;
      for si := 0 to High(cStates) do
      begin
        s := AModel.ResolveStyle(key, variant, cStates[si]);
        // Serialize the fields the fixture exercises (bg/text/border/radius/padding/outline).
        sl.Add(Format('%s.%s/%d => bgK%d/%s txt%s bd%s/%d rad%d pad%d,%d,%d,%d ol%s/%d',
          [key, variant, si,
           Ord(s.Background.Kind), IntToHex(Cardinal(s.Background.Color), 8),
           IntToHex(Cardinal(s.TextColor), 8),
           IntToHex(Cardinal(s.BorderColor), 8), s.BorderWidth,
           s.BorderRadius,
           s.Padding.Left, s.Padding.Top, s.Padding.Right, s.Padding.Bottom,
           IntToHex(Cardinal(s.OutlineColor), 8), s.OutlineWidth]));
      end;
    end;
    Result := sl.Text;
  finally
    sl.Free;
  end;
end;

function TThemeBundleTest.DumpSource(ASource: ITyThemeSource): string;
var
  m: TTyStyleModel;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromSource(ASource);
    Result := DumpModel(m);
  finally
    m.Free;
  end;
end;

{ ── manifest ───────────────────────────────────────────────────────────────── }

procedure TThemeBundleTest.TestDirManifestParsed;
var
  src: ITyThemeSource;
  man: TTyThemeManifest;
begin
  src := TTyThemeDirSource.Create(FFixtureDir);
  man := src.Manifest;
  AssertTrue('manifest loaded from theme.json', man.Loaded);
  AssertEquals('manifest name', 'sample', man.Name);
  AssertEquals('manifest entry', 'theme.tycss', man.Entry);
  AssertFalse('manifest dualMode false', man.DualMode);
end;

procedure TThemeBundleTest.TestDefaultManifestWhenNoJson;
var
  man: TTyThemeManifest;
begin
  // No theme.json: synthesize defaults from the name hint, entry = theme.tycss.
  man := TyDefaultManifest('mytheme');
  AssertFalse('not loaded (synthesized)', man.Loaded);
  AssertEquals('name = hint', 'mytheme', man.Name);
  AssertEquals('entry default', 'theme.tycss', man.Entry);
end;

procedure TThemeBundleTest.TestParseManifestMalformedFallsBack;
var
  man: TTyThemeManifest;
begin
  // Broken JSON must NOT crash a load: fall back to the default manifest (Loaded=False).
  man := TyParseThemeManifest('{ this is not valid json ', 'hint');
  AssertFalse('malformed -> not loaded', man.Loaded);
  AssertEquals('falls back to hint name', 'hint', man.Name);
  AssertEquals('falls back to default entry', 'theme.tycss', man.Entry);
end;

{ ── dir source ─────────────────────────────────────────────────────────────── }

procedure TThemeBundleTest.TestDirRootCss;
var
  src: ITyThemeSource;
begin
  src := TTyThemeDirSource.Create(FFixtureDir);
  AssertTrue('RootCss non-empty', Trim(src.RootCss) <> '');
  AssertTrue('RootCss has TyButton', Pos('TyButton', src.RootCss) > 0);
end;

procedure TThemeBundleTest.TestDirReadTextAndOpenAsset;
var
  src: ITyThemeSource;
  txt: string;
  stm: TStream;
begin
  src := TTyThemeDirSource.Create(FFixtureDir);
  AssertTrue('ReadText theme.tycss', src.ReadText('theme.tycss', txt));
  AssertTrue('ReadText content', Pos(':root', txt) > 0);
  AssertFalse('ReadText missing -> False', src.ReadText('does-not-exist.css', txt));

  stm := nil;
  try
    AssertTrue('OpenAsset theme.json', src.OpenAsset('theme.json', stm));
    AssertTrue('OpenAsset stream non-nil', stm <> nil);
    AssertTrue('OpenAsset stream has bytes', stm.Size > 0);
  finally
    stm.Free;
  end;
  stm := nil;
  AssertFalse('OpenAsset missing -> False', src.OpenAsset('nope.bin', stm));
end;

procedure TThemeBundleTest.TestDirAssetBaseDirIsFolder;
var
  src: ITyThemeSource;
begin
  src := TTyThemeDirSource.Create(FFixtureDir);
  AssertTrue('dir source AssetBaseDir non-empty', src.AssetBaseDir <> '');
end;

{ ── zip source ─────────────────────────────────────────────────────────────── }

procedure TThemeBundleTest.TestZipRootCssEqualsDir;
var
  dir, zip: ITyThemeSource;
begin
  dir := TTyThemeDirSource.Create(FFixtureDir);
  zip := TTyThemeZipSource.Create(FZipPath);
  // Same entry bytes from both transports (line endings normalize via TStringList).
  AssertEquals('zip RootCss = dir RootCss', dir.RootCss, zip.RootCss);
end;

procedure TThemeBundleTest.TestZipReadTextAndOpenAsset;
var
  zip: ITyThemeSource;
  txt: string;
  stm: TStream;
begin
  zip := TTyThemeZipSource.Create(FZipPath);
  AssertTrue('zip ReadText theme.tycss', zip.ReadText('theme.tycss', txt));
  AssertTrue('zip ReadText content', Pos(':root', txt) > 0);
  AssertFalse('zip ReadText missing -> False', zip.ReadText('absent.css', txt));

  stm := nil;
  try
    AssertTrue('zip OpenAsset theme.json', zip.OpenAsset('theme.json', stm));
    AssertTrue('zip OpenAsset non-nil', stm <> nil);
    AssertTrue('zip OpenAsset has bytes', stm.Size > 0);
  finally
    stm.Free;
  end;
end;

procedure TThemeBundleTest.TestZipManifestParsed;
var
  zip: ITyThemeSource;
  man: TTyThemeManifest;
begin
  zip := TTyThemeZipSource.Create(FZipPath);
  man := zip.Manifest;
  AssertTrue('zip manifest loaded', man.Loaded);
  AssertEquals('zip manifest name', 'sample', man.Name);
  AssertEquals('zip manifest entry', 'theme.tycss', man.Entry);
end;

procedure TThemeBundleTest.TestZipAssetBaseDirEmpty;
var
  zip: ITyThemeSource;
begin
  zip := TTyThemeZipSource.Create(FZipPath);
  // A zip has no on-disk dir; the model resolves CSS only (zipped images are a follow-up).
  AssertEquals('zip AssetBaseDir empty', '', zip.AssetBaseDir);
end;

{ ── parity guard ───────────────────────────────────────────────────────────── }

procedure TThemeBundleTest.TestDirVsZipResolveIdentically;
var
  dir, zip: ITyThemeSource;
  dumpDir, dumpZip: string;
begin
  dir := TTyThemeDirSource.Create(FFixtureDir);
  zip := TTyThemeZipSource.Create(FZipPath);
  dumpDir := DumpSource(dir);
  dumpZip := DumpSource(zip);
  AssertEquals('dir and zip resolve to identical styles', dumpDir, dumpZip);
end;

procedure TThemeBundleTest.TestSourceMatchesLoadFromFile;
var
  dir: ITyThemeSource;
  mFile, mSrc: TTyStyleModel;
  dumpFile, dumpSrc: string;
begin
  // A directory bundle must be byte-identical to a plain LoadFromFile of its entry sheet
  // (the back-compat / golden guard: the source abstraction adds no value drift).
  dir := TTyThemeDirSource.Create(FFixtureDir);
  mFile := TTyStyleModel.Create;
  mSrc := TTyStyleModel.Create;
  try
    mFile.LoadFromFile(FFixtureDir + 'theme.tycss');
    mSrc.LoadFromSource(dir);
    dumpFile := DumpModel(mFile);
    dumpSrc := DumpModel(mSrc);
    AssertEquals('LoadFromSource(dir) = LoadFromFile(entry)', dumpFile, dumpSrc);
  finally
    mFile.Free;
    mSrc.Free;
  end;
end;

initialization
  RegisterTest(TThemeBundleTest);
end.
