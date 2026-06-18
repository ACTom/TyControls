unit tyControls.ThemeBundle;
{$mode objfpc}{$H+}
{ C — Theme bundle sources (theme-system v2, Phase 2).

  Abstracts "where a theme's bytes come from" behind ITyThemeSource so a directory
  bundle and a .zip bundle are interchangeable: an application can load a theme from a
  folder of files or from a single packaged .zip, and url()/@import resolve relative to
  the bundle ROOT either way.

  Two implementations:
    * TTyThemeDirSource — root = a folder; the entry stylesheet is <dir>/<entry>
      (entry from theme.json, default theme.tycss). Assets/imports resolve as files
      under the dir. AssetBaseDir returns the dir, so the model reuses its existing
      file-based url()/@import resolution (GThemeBaseDir) verbatim — directory bundles
      are byte-identical to a plain LoadFromFile(<dir>/theme.tycss), so the golden is
      untouched.
    * TTyThemeZipSource — root = a .zip; entries (CSS + theme.json) are read in-memory
      via FPC's TUnZipper (OnCreateStream/OnDoneStream), no temp files. CSS-only and
      manifest-only zips work fully. AssetBaseDir is empty (a zip has no on-disk dir),
      so IMAGE assets inside a zip are NOT yet resolved by the painter — that is a
      documented Phase 2 follow-up (extract-to-temp + rewrite ImagePath, zero painter
      change). Ship CSS+manifest zip now.

  theme.json (manifest) is parsed-and-stored: name / author / version / extends / entry /
  dualMode. Phase 2 ACTS only on `entry` (which stylesheet is the root); `extends` and
  `dualMode` are stored but inert (extends -> @import sugar and dualMode -> @mode are
  later phases). A bundle with no theme.json gets a synthesized default manifest
  (name = folder/zip basename, entry = theme.tycss). }
interface
uses
  Classes, SysUtils, fpjson, jsonparser, zipper;

const
  cTyDefaultThemeEntry = 'theme.tycss';   // root stylesheet name when manifest omits 'entry'

type
  { Parsed theme.json. Loaded=False means "no/empty manifest" — defaults synthesized. }
  TTyThemeManifest = record
    Loaded:   Boolean;   // True if a non-empty theme.json was parsed
    Name:     string;
    Author:   string;
    Version:  string;
    Extends:  string;    // optional base theme name/path (P3+ compose; stored, inert in P2)
    Entry:    string;    // root stylesheet (default theme.tycss)
    DualMode: Boolean;   // declares @mode light/dark present (P3 consumes; inert in P2)
  end;

  { A theme's byte source. RootCss is the entry stylesheet text; ReadText/OpenAsset
    resolve a relative path (for @import / url()) against the bundle root. AssetBaseDir
    is the on-disk directory the model can use for its existing file-based resolution
    ('' = none, e.g. a zip). RootName is a human-readable id for diagnostics. }
  ITyThemeSource = interface
    ['{2C8F1B4A-7E3D-4C6A-9F21-5B0D8A4E1C73}']
    function RootCss: string;
    function ReadText(const ARelPath: string; out S: string): Boolean;
    function OpenAsset(const ARelPath: string; out Stream: TStream): Boolean;
    function Manifest: TTyThemeManifest;
    function RootName: string;
    function AssetBaseDir: string;
  end;

  { Directory-rooted bundle. Entry sheet = <dir>/<manifest.entry> (default theme.tycss). }
  TTyThemeDirSource = class(TInterfacedObject, ITyThemeSource)
  private
    FDir: string;            // root folder, trailing path delim
    FManifest: TTyThemeManifest;
    function NormRel(const ARelPath: string): string;
  public
    constructor Create(const ADir: string);
    function RootCss: string;
    function ReadText(const ARelPath: string; out S: string): Boolean;
    function OpenAsset(const ARelPath: string; out Stream: TStream): Boolean;
    function Manifest: TTyThemeManifest;
    function RootName: string;
    function AssetBaseDir: string;
  end;

  { Zip-rooted bundle. All entries are extracted to memory once at construction. CSS +
    theme.json are read from those buffers; image assets are present in-memory but the
    painter still wants a file path, so zipped IMAGE assets are a Phase 2 follow-up. }
  TTyThemeZipSource = class(TInterfacedObject, ITyThemeSource)
  private
    FZipPath: string;
    FNames: TStringList;     // entry name (normalized to /) -> index; Objects = TMemoryStream
    FManifest: TTyThemeManifest;
    FCurStream: TMemoryStream;          // scratch slot for the OnCreateStream callback
    procedure DoCreateStream(Sender: TObject; var AStream: TStream;
      AItem: TFullZipFileEntry);
    procedure DoDoneStream(Sender: TObject; var AStream: TStream;
      AItem: TFullZipFileEntry);
    function NormRel(const ARelPath: string): string;
    function FindEntry(const ARelPath: string): TMemoryStream;
    function EntryText(AStm: TMemoryStream): string;
  public
    constructor Create(const AZipFile: string);
    destructor Destroy; override;
    function RootCss: string;
    function ReadText(const ARelPath: string; out S: string): Boolean;
    function OpenAsset(const ARelPath: string; out Stream: TStream): Boolean;
    function Manifest: TTyThemeManifest;
    function RootName: string;
    function AssetBaseDir: string;
  end;

{ Build a default manifest (no theme.json): name from a basename hint, entry=theme.tycss. }
function TyDefaultManifest(const ANameHint: string): TTyThemeManifest;

{ Parse a theme.json text into a manifest. Missing fields fall back to the defaults
  seeded from ANameHint. A blank/invalid JSON yields the default manifest with
  Loaded=False (callers treat a bundle with no/broken manifest as "defaults"). }
function TyParseThemeManifest(const AJson, ANameHint: string): TTyThemeManifest;

implementation

function TyDefaultManifest(const ANameHint: string): TTyThemeManifest;
begin
  Result := Default(TTyThemeManifest);
  Result.Loaded   := False;
  Result.Name     := ANameHint;
  Result.Entry    := cTyDefaultThemeEntry;
  Result.DualMode := False;
end;

function TyParseThemeManifest(const AJson, ANameHint: string): TTyThemeManifest;
var
  data: TJSONData;
  obj: TJSONObject;
begin
  Result := TyDefaultManifest(ANameHint);
  if Trim(AJson) = '' then
    Exit;
  data := nil;
  try
    try
      data := GetJSON(AJson);
    except
      on E: Exception do
        Exit;   // malformed theme.json -> default manifest (do not crash a load)
    end;
    if not (data is TJSONObject) then
      Exit;
    obj := TJSONObject(data);
    Result.Loaded := True;
    Result.Name     := obj.Get('name',     Result.Name);
    Result.Author   := obj.Get('author',   Result.Author);
    Result.Version  := obj.Get('version',  Result.Version);
    Result.Extends  := obj.Get('extends',  Result.Extends);
    Result.Entry    := obj.Get('entry',    Result.Entry);
    Result.DualMode := obj.Get('dualMode', Result.DualMode);
    if Trim(Result.Entry) = '' then
      Result.Entry := cTyDefaultThemeEntry;
  finally
    data.Free;
  end;
end;

{ ── TTyThemeDirSource ──────────────────────────────────────────────────────── }

constructor TTyThemeDirSource.Create(const ADir: string);
var
  jsonPath, jsonTxt: string;
  sl: TStringList;
begin
  inherited Create;
  FDir := IncludeTrailingPathDelimiter(ADir);
  // Load the manifest if present; otherwise synthesize defaults from the folder name.
  jsonPath := FDir + 'theme.json';
  jsonTxt := '';
  if FileExists(jsonPath) then
  begin
    sl := TStringList.Create;
    try
      sl.LoadFromFile(jsonPath);
      jsonTxt := sl.Text;
    finally
      sl.Free;
    end;
  end;
  FManifest := TyParseThemeManifest(jsonTxt,
    ExtractFileName(ExcludeTrailingPathDelimiter(FDir)));
end;

function TTyThemeDirSource.NormRel(const ARelPath: string): string;
begin
  // Zip entries use '/', author markup may use either; map to the OS separator and
  // strip stray spaces (the CSS lexer can insert them around dots in url() paths).
  Result := StringReplace(Trim(ARelPath), ' ', '', [rfReplaceAll]);
  Result := StringReplace(Result, '/', PathDelim, [rfReplaceAll]);
  Result := StringReplace(Result, '\', PathDelim, [rfReplaceAll]);
end;

function TTyThemeDirSource.RootCss: string;
var
  sl: TStringList;
  p: string;
begin
  Result := '';
  p := FDir + FManifest.Entry;
  if not FileExists(p) then
    Exit;
  sl := TStringList.Create;
  try
    sl.LoadFromFile(p);
    Result := sl.Text;
  finally
    sl.Free;
  end;
end;

function TTyThemeDirSource.ReadText(const ARelPath: string; out S: string): Boolean;
var
  sl: TStringList;
  p: string;
begin
  S := '';
  p := FDir + NormRel(ARelPath);
  if not FileExists(p) then
    Exit(False);
  sl := TStringList.Create;
  try
    sl.LoadFromFile(p);
    S := sl.Text;
  finally
    sl.Free;
  end;
  Result := True;
end;

function TTyThemeDirSource.OpenAsset(const ARelPath: string; out Stream: TStream): Boolean;
var
  p: string;
begin
  Stream := nil;
  p := FDir + NormRel(ARelPath);
  if not FileExists(p) then
    Exit(False);
  Stream := TFileStream.Create(p, fmOpenRead or fmShareDenyWrite);
  Result := True;
end;

function TTyThemeDirSource.Manifest: TTyThemeManifest;
begin
  Result := FManifest;
end;

function TTyThemeDirSource.RootName: string;
begin
  Result := FDir + FManifest.Entry;
end;

function TTyThemeDirSource.AssetBaseDir: string;
begin
  Result := FDir;   // a real folder: the model resolves url()/@import as files under it
end;

{ ── TTyThemeZipSource ──────────────────────────────────────────────────────── }

constructor TTyThemeZipSource.Create(const AZipFile: string);
var
  uz: TUnZipper;
  jsonStm: TMemoryStream;
  jsonTxt: string;
begin
  inherited Create;
  FZipPath := AZipFile;
  FNames := TStringList.Create;
  FNames.CaseSensitive := False;       // case-fold lookups (zip is case-sensitive; assets often aren't)
  FNames.OwnsObjects := True;          // the cached TMemoryStream buffers are owned here
  uz := TUnZipper.Create;
  try
    uz.FileName := FZipPath;
    uz.OnCreateStream := @DoCreateStream;
    uz.OnDoneStream := @DoDoneStream;
    uz.Examine;
    uz.UnZipAllFiles;                  // extracts every entry to an in-memory buffer
  finally
    uz.Free;
  end;
  // Manifest from theme.json if present, else defaults from the zip basename.
  jsonTxt := '';
  jsonStm := FindEntry('theme.json');
  if jsonStm <> nil then
  begin
    SetString(jsonTxt, PChar(jsonStm.Memory), jsonStm.Size);
  end;
  FManifest := TyParseThemeManifest(jsonTxt,
    ChangeFileExt(ExtractFileName(FZipPath), ''));
end;

destructor TTyThemeZipSource.Destroy;
begin
  FNames.Free;        // OwnsObjects frees the cached TMemoryStream buffers
  inherited Destroy;
end;

procedure TTyThemeZipSource.DoCreateStream(Sender: TObject; var AStream: TStream;
  AItem: TFullZipFileEntry);
begin
  // Hand the unzipper a fresh memory buffer to write the decompressed entry into.
  FCurStream := TMemoryStream.Create;
  AStream := FCurStream;
end;

procedure TTyThemeZipSource.DoDoneStream(Sender: TObject; var AStream: TStream;
  AItem: TFullZipFileEntry);
var
  ms: TMemoryStream;
  key: string;
begin
  // Take ownership of the buffer (the unzipper nils AStream after this callback, so it
  // will NOT free it). Cache it under the entry's normalized name.
  ms := AStream as TMemoryStream;
  ms.Position := 0;
  key := NormRel(AItem.ArchiveFileName);
  // last-writer-wins on a duplicate name (zips normally have none)
  if FNames.IndexOf(key) >= 0 then
    FNames.Delete(FNames.IndexOf(key));
  FNames.AddObject(key, ms);
  FCurStream := nil;
end;

function TTyThemeZipSource.NormRel(const ARelPath: string): string;
begin
  // Canonical lookup key: forward slashes, no spaces, lower-cased compare via FNames'
  // CaseSensitive=False. (Entry names in a zip use '/'.)
  Result := StringReplace(Trim(ARelPath), ' ', '', [rfReplaceAll]);
  Result := StringReplace(Result, '\', '/', [rfReplaceAll]);
  while (Result <> '') and (Result[1] = '/') do
    Delete(Result, 1, 1);   // drop a leading slash so 'a/b' and '/a/b' match
end;

function TTyThemeZipSource.FindEntry(const ARelPath: string): TMemoryStream;
var
  idx: Integer;
begin
  Result := nil;
  idx := FNames.IndexOf(NormRel(ARelPath));
  if idx >= 0 then
    Result := TMemoryStream(FNames.Objects[idx]);
end;

function TTyThemeZipSource.EntryText(AStm: TMemoryStream): string;
var
  sl: TStringList;
begin
  // Decode the raw entry bytes THROUGH a TStringList so line endings normalize exactly
  // as a TTyThemeDirSource's TStringList.LoadFromFile does — a directory bundle and a zip
  // of it then yield byte-identical text (the dir-vs-zip parity guard).
  sl := TStringList.Create;
  try
    AStm.Position := 0;
    sl.LoadFromStream(AStm);
    Result := sl.Text;
  finally
    sl.Free;
  end;
end;

function TTyThemeZipSource.RootCss: string;
var
  stm: TMemoryStream;
begin
  Result := '';
  stm := FindEntry(FManifest.Entry);
  if stm <> nil then
    Result := EntryText(stm);
end;

function TTyThemeZipSource.ReadText(const ARelPath: string; out S: string): Boolean;
var
  stm: TMemoryStream;
begin
  S := '';
  stm := FindEntry(ARelPath);
  if stm = nil then
    Exit(False);
  S := EntryText(stm);
  Result := True;
end;

function TTyThemeZipSource.OpenAsset(const ARelPath: string; out Stream: TStream): Boolean;
var
  stm: TMemoryStream;
  copy: TMemoryStream;
begin
  Stream := nil;
  stm := FindEntry(ARelPath);
  if stm = nil then
    Exit(False);
  // Hand back an independent copy the caller owns (the cached buffer stays ours).
  copy := TMemoryStream.Create;
  stm.Position := 0;
  copy.CopyFrom(stm, stm.Size);
  copy.Position := 0;
  Stream := copy;
  Result := True;
end;

function TTyThemeZipSource.Manifest: TTyThemeManifest;
begin
  Result := FManifest;
end;

function TTyThemeZipSource.RootName: string;
begin
  Result := FZipPath + '!' + FManifest.Entry;
end;

function TTyThemeZipSource.AssetBaseDir: string;
begin
  Result := '';   // a zip has no on-disk dir; zipped IMAGE assets are a P2 follow-up
end;

end.
