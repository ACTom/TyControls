unit test.lucide;
{$mode objfpc}{$H+}

{ The bundled Lucide font.

  Two of these tests are the reason the unit can be trusted at all, and neither is about
  rendering:

  SOURCE-OF-TRUTH DRIFT. tyControls.Icons.Lucide.pas is GENERATED from assets/lucide/. Editing
  the .ttf or the codepoint map without re-running scripts/gen-lucide.py would leave a unit
  that names glyphs the font no longer has -- and nothing would say so until a user saw a blank
  square. TheGeneratedUnitMatchesTheAssets recomputes the digest from the asset bytes.

  THE OPT-IN. The font is ~833KB and it is in the unit rather than an .lrs precisely so smart
  linking can drop it. That only works while NO core unit references this one, which is a
  property of the SOURCE, not of anything a run-time test can observe -- so
  NoCoreUnitReferencesTheBundledFont reads source/ and asserts it. Measured on real
  executables at the time of writing: 979 KB with `uses tyControls.Icons.Lucide`, 0 without.

  The rest pin the promises the unit makes: every name it offers has an outline (the upstream
  map still lists ~20 removed brand logos, which the generator drops), names resolve through
  the registry with an EMPTY Glyphs map, and the singleton actually registers the font. }

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  tyControls.IconFont, tyControls.Icons.Lucide;

type
  TLucideTest = class(TTestCase)
  private
    function AssetsDir: string;
  published
    procedure TheGeneratedUnitMatchesTheAssets;
    procedure TheGeneratedUnitMatchesTheGeneratorThatProducedIt;
    procedure NoCoreUnitReferencesTheBundledFont;
    procedure TheFontRegistersAndIsAvailable;
    procedure NamesResolveWithAnEmptyGlyphMap;
    procedure AResolverDeclinesAnotherFamily;
    procedure EveryOfferedNameHasACodepoint;
    procedure GlyphNameRoundTripsByIndex;
    procedure RemovedBrandLogosAreNotOffered;
    procedure TheComponentConfiguresItselfAndSharesOneRegistration;
    procedure TheDroppableListIsPreWiredToLucideAndStartsEmpty;
    procedure TheEmbeddedLicenceMatchesTheSourceFile;
end;

implementation

uses
  sha1, FileUtil, BGRABitmap, BGRABitmapTypes, tyControls.Types, test.designregistry,
  tyControls.ImageCollection, tyControls.ImageDraw;

function TLucideTest.AssetsDir: string;
begin
  Result := RepoRoot + 'assets' + PathDelim + 'lucide' + PathDelim;
end;

procedure TLucideTest.TheGeneratedUnitMatchesTheAssets;
var
  ttf, cps: TMemoryStream;
  both: TMemoryStream;
  d: TSHA1Digest;
begin
  ttf := TMemoryStream.Create;
  cps := TMemoryStream.Create;
  both := TMemoryStream.Create;
  try
    AssertTrue('assets/lucide/lucide.ttf must exist', FileExists(AssetsDir + 'lucide.ttf'));
    AssertTrue('assets/lucide/codepoints.json must exist',
      FileExists(AssetsDir + 'codepoints.json'));
    ttf.LoadFromFile(AssetsDir + 'lucide.ttf');
    cps.LoadFromFile(AssetsDir + 'codepoints.json');
    both.CopyFrom(ttf, 0);
    both.CopyFrom(cps, 0);
    d := SHA1Buffer(both.Memory^, both.Size);
    AssertEquals('tyControls.Icons.Lucide.pas is out of date -- run '
      + 'python scripts/gen-lucide.py', TyLucideAssetDigest, UpperCase(SHA1Print(d)));
  finally
    both.Free;
    cps.Free;
    ttf.Free;
  end;
end;

procedure TLucideTest.TheGeneratedUnitMatchesTheGeneratorThatProducedIt;
var
  ms: TMemoryStream;
  src: RawByteString;
  d: TSHA1Digest;
begin
  { TheGeneratedUnitMatchesTheAssets pins the INPUTS. This pins the TRANSFORMATION -- and that
    half had no guard at all: `gen-lucide.py --check` is the only thing that ever compared the
    unit against the code that produced it, and NOTHING runs it. There is no CI here, and a
    repo-wide grep finds --check only in the script's own docstring. So a hand-edit of the
    generated 690KB unit, or a generator change nobody re-ran, shipped in silence.

    Line endings are normalised on both sides because the .py is a text file under git and a
    checkout with a different core.autocrlf must not turn this red for no reason. }
  ms := TMemoryStream.Create;
  try
    AssertTrue('scripts/gen-lucide.py must exist',
      FileExists(RepoRoot + 'scripts' + PathDelim + 'gen-lucide.py'));
    ms.LoadFromFile(RepoRoot + 'scripts' + PathDelim + 'gen-lucide.py');
    SetLength(src, ms.Size);
    if ms.Size > 0 then Move(ms.Memory^, src[1], ms.Size);
  finally
    ms.Free;
  end;
  src := StringReplace(src, #13#10, #10, [rfReplaceAll]);
  if src = '' then d := SHA1Buffer(src, 0) else d := SHA1Buffer(src[1], Length(src));
  AssertEquals('tyControls.Icons.Lucide.pas was produced by a DIFFERENT gen-lucide.py -- '
    + 'run python scripts/gen-lucide.py', TyLucideGeneratorDigest, UpperCase(SHA1Print(d)));
end;

procedure TLucideTest.NoCoreUnitReferencesTheBundledFont;
var
  files: TStringList;
  src: TStringList;
  i: Integer;
  fn, bad: string;
begin
  files := FindAllFiles(RepoRoot + 'source', '*.pas', False);
  src := TStringList.Create;
  try
    bad := '';
    for i := 0 to files.Count - 1 do
    begin
      fn := ExtractFileName(files[i]);
      if SameText(fn, 'tyControls.Icons.Lucide.pas') then Continue;   { itself }
      src.LoadFromFile(files[i]);
      if Pos('tyControls.Icons.Lucide', src.Text) > 0 then
        bad := bad + LineEnding + '  ' + fn;
    end;
    { A single `uses` from anywhere in the core drags 833KB of font into EVERY application,
      the way tyControls.BuiltinThemes already drags in 476KB of theme data. The dependency
      has to point one way: from the application inwards. }
    AssertEquals('core units referencing the optional bundled font:' + bad, '', bad);
  finally
    src.Free;
    files.Free;
  end;
end;

procedure TLucideTest.TheFontRegistersAndIsAvailable;
begin
  AssertEquals('family', 'lucide', TyLucideFamily);
  AssertTrue('the singleton registered the embedded bytes: ' + TyLucideFont.LoadError,
    TyLucideFont.Available);
  AssertEquals('and no error was recorded', '', TyLucideFont.LoadError);
end;

procedure TLucideTest.NamesResolveWithAnEmptyGlyphMap;
var
  f: TTyIconFont;
begin
  { The headline of the whole slice. Before the resolver, using a bundled font meant pasting
    two thousand 'name=HEX' lines into Glyphs. }
  AssertEquals('the singleton maps nothing by hand', 0, TyLucideFont.Glyphs.Count);
  AssertTrue('yet a name resolves', TyLucideFont.HasGlyph(TyIconHouse));

  { ...and on a component the application made itself, given only the family. }
  f := TTyIconFont.Create(nil);
  try
    f.FontFamily := TyLucideFamily;
    AssertEquals('resolved on a plain component', TyLucideCodepoint('zoom-in'),
      f.CodepointOf('zoom-in'));
    AssertTrue('non-zero', f.CodepointOf('zoom-in') > 0);
  finally
    f.Free;
  end;
end;

procedure TLucideTest.AResolverDeclinesAnotherFamily;
var
  f: TTyIconFont;
begin
  f := TTyIconFont.Create(nil);
  try
    f.FontFamily := 'SomeOtherIconFont';
    { Declining by family is what lets a second bundled font coexist rather than the first one
      answering for names it does not have. }
    AssertEquals('lucide does not answer for another family', 0, f.CodepointOf('house'));
  finally
    f.Free;
  end;
end;

procedure TLucideTest.EveryOfferedNameHasACodepoint;
var
  i: Integer;
  nm: string;
  bad, n: Integer;
begin
  bad := 0;
  n := 0;
  for i := 0 to TyLucideGlyphCount - 1 do
  begin
    nm := TyLucideGlyphName(i);
    if nm = '' then begin Inc(bad); Continue; end;
    if TyLucideCodepoint(nm) = 0 then Inc(bad);
    Inc(n);
  end;
  AssertEquals('every index yields a name', TyLucideGlyphCount, n);
  AssertEquals('every offered name has a codepoint', 0, bad);
end;

procedure TLucideTest.GlyphNameRoundTripsByIndex;
begin
  AssertEquals('below the range', '', TyLucideGlyphName(-1));
  AssertEquals('above the range', '', TyLucideGlyphName(TyLucideGlyphCount));
  AssertTrue('the first name is non-empty', TyLucideGlyphName(0) <> '');
  AssertTrue('the last name is non-empty', TyLucideGlyphName(TyLucideGlyphCount - 1) <> '');
  { The table is sorted -- TyLucideCodepoint binary-searches it. }
  AssertTrue('sorted', CompareText(TyLucideGlyphName(0),
    TyLucideGlyphName(TyLucideGlyphCount - 1)) < 0);
end;

procedure TLucideTest.RemovedBrandLogosAreNotOffered;
const
  Gone: array[0..3] of string = ('github', 'twitter', 'facebook', 'slack');
var
  i: Integer;
  bad: string;
begin
  { Lucide keeps a codepoint forever once allocated, so codepoints.json still lists the brand
    logos v1.0 REMOVED. Their glyf records are empty; offering the name would mean HasGlyph
    answering True and the user getting a blank square, which is a worse failure than the name
    not existing. The generator checks the outline and drops them. }
  bad := '';
  for i := Low(Gone) to High(Gone) do
    if TyLucideCodepoint(Gone[i]) <> 0 then
      bad := bad + ' ' + Gone[i];
  AssertEquals('names whose glyph the font no longer contains are still offered:' + bad,
    '', bad);
end;

procedure TLucideTest.TheComponentConfiguresItselfAndSharesOneRegistration;
var
  a, b: TTyLucideIconFont;
begin
  { Dropped on a form, it needs no properties set: family, embedded bytes and the name
    resolver are all its own doing. }
  a := TTyLucideIconFont.Create(nil);
  b := TTyLucideIconFont.Create(nil);
  try
    AssertEquals('family set by the component', TyLucideFamily, a.FontFamily);
    AssertTrue('and it reports the SHARED registration, not just "I have a family": '
      + a.LoadError, a.Available);
    AssertTrue('a second instance is equally usable', b.Available);
    AssertTrue('both resolve names with nothing in Glyphs', a.HasGlyph(TyIconHouse));
    AssertEquals('and neither maps anything by hand', 0, b.Glyphs.Count);

    { The registration belongs to the unit, not to an instance: freeing the first component
      must not unregister the font out from under the second. That is the whole reason
      TTyIconPackFont keeps a keeper. }
    FreeAndNil(a);
    AssertTrue('the survivor still has a font', b.Available);
    AssertTrue('and can still resolve', b.CodepointOf(TyIconHouse) > 0);
  finally
    a.Free;
    b.Free;
  end;
  { And the code-path singleton is the same class, so the two entry points cannot drift. }
  AssertTrue('TyLucideFont is the component class',
    TyLucideFont is TTyLucideIconFont);
end;

procedure TLucideTest.TheDroppableListIsPreWiredToLucideAndStartsEmpty;
var
  list: TTyLucideImageList;
begin
  { The third way in: a droppable image list that needs no font wiring. It IS a
    TTyVirtualImageList (so it takes the on-demand vector path, not the baked one), its IconFont
    is the shared bundled font, and it starts empty so the developer fills only what they use. }
  list := TTyLucideImageList.Create(nil);
  try
    AssertFalse('it is our on-demand list, not a baked one', TyImageIsBaked(list));
    AssertSame('IconFont is the shared bundled font', TObject(TyLucideFont), TObject(list.IconFont));
    AssertEquals('Names start empty', 0, list.Names.Count);
    AssertEquals('so there are no images yet', 0, TyImageCount(list));
    { Fill one name and it becomes one addressable image, keyed by that name. }
    list.Names.Text := TyIconHouse;
    AssertEquals('adding a name adds an image', 1, TyImageCount(list));
    AssertEquals('and the name resolves to slot 0', 0, TyImageIndexOfName(list, TyIconHouse));
  finally
    list.Free;
  end;
end;

procedure TLucideTest.TheEmbeddedLicenceMatchesTheSourceFile;
var
  path, fileText, embedded: string;
  sl: TStringList;
begin
  { The design-time editor shows TyLucideLicense (embedded from assets/lucide/LICENSE by
    gen-lucide-license.ps1). This is the drift guard: edit the LICENSE and forget to re-run the
    generator, and the embedded text no longer matches -> red. Normalise line endings + trailing
    newline (the generator strips the trailing one; TStringList.Text adds one). }
  path := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'assets' + PathDelim + 'lucide'
    + PathDelim + 'LICENSE';
  AssertTrue('assets/lucide/LICENSE must exist for the sync check', FileExists(path));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(path);
    fileText := TrimRight(StringReplace(sl.Text, #13#10, #10, [rfReplaceAll]));
    embedded := TrimRight(StringReplace(TyLucideLicense, #13#10, #10, [rfReplaceAll]));
    AssertEquals('embedded TyLucideLicense must equal assets/lucide/LICENSE verbatim',
      fileText, embedded);
  finally
    sl.Free;
  end;
end;

initialization
  RegisterTest(TLucideTest);

end.
