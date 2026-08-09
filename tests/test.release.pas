unit test.release;
{$mode objfpc}{$H+}

{ What the release tarball must contain.

  WHY THIS EXISTS. The two release scripts are hand-written copy lists, and every way they can be
  wrong is SILENT. Add-File prints "(skip, not found)" and returns; Add-Tree just skips a file
  whose extension is not listed. Nothing fails, the zip is produced, and the developer cannot see
  the hole because on their machine the .lpk search path finds every file on disk. The user finds
  out when Lazarus refuses to compile a unit the .lpk lists. Three real instances were already
  shipping when this test was written:

    - source/ was copied by extension ('.pas','.inc'), so a package .lfm/.lrs/.res would vanish;
    - designtime/ was copied as two hardcoded FILE NAMES, so a second design-time unit would;
    - examples/ had no image extensions, so examples/theming shipped with a dead url() photo;
    - THIRD-PARTY-NOTICES.md did not ship at all, while the Lucide font bytes it licenses did.

  HOW IT WORKS. It does NOT run the scripts (that needs pwsh/bash + zip and writes dist/). It
  PARSES them into a predicate -- IsShipped(relative path) -- and applies that predicate to
  populations DERIVED from the repo: the files the .lpk manifests name, the assets the shipped
  themes reference. Nothing is copied into the test, so it cannot drift into agreeing with a
  script that has become wrong. The one hardcoded literal is the licence notice, because no
  machine-readable manifest declares a licence obligation.

  ANTI-SHRINK. A parser that silently stops matching would make every assertion vacuously true,
  which is the failure mode this repo has hit before. TheParserStillUnderstandsBothScripts pins
  minimum rule counts, so a rewritten script fails loudly here instead of quietly disarming the
  rest of the file. }

interface

uses
  Classes, SysUtils, StrUtils, fpcunit, testregistry;

type
  { One copy rule from a release script. Exts empty = the whole tree. }
  TShipRule = record
    IsTree: Boolean;
    Rel: string;          { 'source', 'designtime', or a single file path }
    Exts: string;         { '|.pas|.inc|', lowercase, empty = everything }
    SkipDir: string;      { a directory name excluded from the tree ('icons', 'superpowers') }
  end;
  TShipRules = array of TShipRule;

  TReleaseManifestTest = class(TTestCase)
  private
    FPs1, FSh: TShipRules;
    function Ps1Path: string;
    function ShPath: string;
    function ReadScript(const APath: string): string;
    function ParsePs1(const AText: string): TShipRules;
    function ParseSh(const AText: string): TShipRules;
    function IsShipped(const ARules: TShipRules; const ARelPath: string): Boolean;
    { Every <Filename Value="..."/> in a .lpk, repo-relative with forward slashes. }
    procedure CollectLpkFiles(const ALpk: string; ADest: TStrings);
    function RulePaths(const ARules: TShipRules): string;
  protected
    procedure SetUp; override;
  published
    procedure TheParserStillUnderstandsBothScripts;
    procedure EveryFileThePackagesNameIsShipped;
    procedure EveryDesignTimeUnitIsShipped;
    procedure TheThirdPartyNoticeShipsWithTheFontItLicenses;
    procedure EveryAssetAShippedThemeReferencesIsShipped;
    procedure BothScriptsShipTheSameTrees;
    procedure EveryTestUnitThatRegistersTestsIsLinked;
    procedure TheControlDocsIndexLinksEveryPageAndOnlyRealOnes;
  end;

implementation

uses
  FileUtil, test.designregistry;

{ ---------------------------------------------------------------- helpers ---------------- }

function Slashes(const S: string): string;
begin
  Result := StringReplace(S, '\', '/', [rfReplaceAll]);
end;

{ The single-quoted string starting at or after AFrom; '' when there is none before AStop. }
function QuotedAt(const S: string; AFrom, AStop: Integer; out ANext: Integer): string;
var
  i, j: Integer;
begin
  Result := '';
  ANext := AFrom;
  i := AFrom;
  while (i <= AStop) and (S[i] <> '''') do Inc(i);
  if i > AStop then Exit;
  j := i + 1;
  while (j <= Length(S)) and (S[j] <> '''') do Inc(j);
  if j > Length(S) then Exit;
  Result := Copy(S, i + 1, j - i - 1);
  ANext := j + 1;
end;

function TReleaseManifestTest.Ps1Path: string;
begin
  Result := RepoRoot + 'scripts' + PathDelim + 'make-release.ps1';
end;

function TReleaseManifestTest.ShPath: string;
begin
  Result := RepoRoot + 'scripts' + PathDelim + 'make-release.sh';
end;

function TReleaseManifestTest.ReadScript(const APath: string): string;
var
  sl: TStringList;
begin
  if not FileExists(APath) then
    raise Exception.Create('release script not found: ' + APath);
  sl := TStringList.Create;
  try
    sl.LoadFromFile(APath);
    Result := sl.Text;
  finally
    sl.Free;
  end;
end;

{ ---------------------------------------------------------------- parsing ---------------- }

{ make-release.ps1: `Add-Tree '<rel>' @(<exts>) ['<skip>']` and `Add-File '<rel>'`, plus the
  root block, which is a comma-separated list of quoted names piped into Add-File. Deliberately
  tolerant about layout (the examples rule spans two lines) and deliberately strict about the
  call names, so a renamed helper trips the anti-shrink guard rather than parsing as nothing. }
function TReleaseManifestTest.ParsePs1(const AText: string): TShipRules;

  procedure Push(const R: TShipRule);
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := R;
  end;

var
  i, lineEnd, p, nxt, closeIdx: Integer;
  r: TShipRule;
  extBlock, e, seg: string;
begin
  Result := nil;

  { Add-Tree: rel, then the @( ... ) extension list, then an optional skip pattern. }
  i := 1;
  repeat
    p := PosEx('Add-Tree', AText, i);
    if p = 0 then Break;
    i := p + 8;
    { The call may wrap, so scan to the end of the @( ) block rather than to end-of-line. }
    closeIdx := PosEx(')', AText, p);
    if closeIdx = 0 then Break;
    lineEnd := PosEx(LineEnding, AText, closeIdx);
    if lineEnd = 0 then lineEnd := Length(AText);
    FillChar(r, SizeOf(r), 0);
    r.IsTree := True;
    r.Rel := QuotedAt(AText, p, closeIdx, nxt);
    if r.Rel = '' then Continue;
    extBlock := Copy(AText, PosEx('@(', AText, p), closeIdx - PosEx('@(', AText, p) + 1);
    r.Exts := '';
    repeat
      e := QuotedAt(extBlock, 1, Length(extBlock), nxt);
      if e = '' then Break;
      r.Exts := r.Exts + '|' + LowerCase(e);
      Delete(extBlock, 1, nxt - 1);
    until False;
    if r.Exts <> '' then r.Exts := r.Exts + '|';
    { A skip pattern, when present, is the quoted string AFTER the closing paren. }
    seg := Copy(AText, closeIdx + 1, lineEnd - closeIdx);
    r.SkipDir := QuotedAt(seg, 1, Length(seg), nxt);
    Push(r);
  until False;

  { Add-File '<rel>' -- direct calls only; the piped root list is handled below. }
  i := 1;
  repeat
    p := PosEx('Add-File ''', AText, i);
    if p = 0 then Break;
    i := p + 9;
    FillChar(r, SizeOf(r), 0);
    r.IsTree := False;
    r.Rel := QuotedAt(AText, p, Length(AText), nxt);
    if r.Rel <> '' then Push(r);
  until False;

  { The root block: every quoted name before `| ForEach-Object { Add-File $_ }`. }
  p := Pos('| ForEach-Object { Add-File $_ }', AText);
  if p > 0 then
  begin
    i := p;
    { back up to the Write-Host that opens the block }
    while (i > 1) and (PosEx('Write-Host', Copy(AText, i, 10)) <> 1) do Dec(i);
    seg := Copy(AText, i, p - i);
    { skip the Write-Host's own quoted banner }
    QuotedAt(seg, 1, Length(seg), nxt);
    Delete(seg, 1, nxt - 1);
    repeat
      e := QuotedAt(seg, 1, Length(seg), nxt);
      if e = '' then Break;
      Delete(seg, 1, nxt - 1);
      FillChar(r, SizeOf(r), 0);
      r.IsTree := False;
      r.Rel := e;
      Push(r);
    until False;
  end;
end;

{ make-release.sh: `add_tree <dir> "<skip>" [ext ...]` and `add_file <path>`, both unquoted
  paths. No extensions = the whole tree, the same convention as the PowerShell twin. }
function TReleaseManifestTest.ParseSh(const AText: string): TShipRules;

  procedure Push(const R: TShipRule);
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := R;
  end;

var
  lines: TStringList;
  i, k: Integer;
  ln: string;
  parts: TStringArray;
  r: TShipRule;
begin
  Result := nil;
  lines := TStringList.Create;
  try
    lines.Text := AText;
    for i := 0 to lines.Count - 1 do
    begin
      ln := Trim(lines[i]);
      if StartsStr('#', ln) then Continue;                { a comment, not a rule }
      if StartsStr('add_tree ', ln) then
      begin
        parts := ln.Split([' '], TStringSplitOptions.ExcludeEmpty);
        if Length(parts) < 2 then Continue;
        FillChar(r, SizeOf(r), 0);
        r.IsTree := True;
        r.Rel := parts[1];
        if Length(parts) >= 3 then
          r.SkipDir := StringReplace(parts[2], '"', '', [rfReplaceAll]);
        r.Exts := '';
        for k := 3 to High(parts) do
          r.Exts := r.Exts + '|.' + LowerCase(parts[k]);
        if r.Exts <> '' then r.Exts := r.Exts + '|';
        Push(r);
      end
      else if StartsStr('add_file ', ln) then
      begin
        parts := ln.Split([' '], TStringSplitOptions.ExcludeEmpty);
        if Length(parts) < 2 then Continue;
        FillChar(r, SizeOf(r), 0);
        r.IsTree := False;
        r.Rel := parts[1];
        Push(r);
      end;
    end;
  finally
    lines.Free;
  end;
end;

{ Would the scripts copy ARelPath (repo-relative, forward slashes)? }
function TReleaseManifestTest.IsShipped(const ARules: TShipRules;
  const ARelPath: string): Boolean;
var
  i: Integer;
  rel, ext, treePrefix: string;
begin
  rel := Slashes(ARelPath);
  ext := LowerCase(ExtractFileExt(rel));
  { The build/dev directories every tree rule drops. }
  if (Pos('/lib/', '/' + rel) > 0) or (Pos('/backup/', '/' + rel) > 0) then Exit(False);
  for i := 0 to High(ARules) do
  begin
    if not ARules[i].IsTree then
    begin
      if SameText(Slashes(ARules[i].Rel), rel) then Exit(True);
      Continue;
    end;
    treePrefix := Slashes(ARules[i].Rel) + '/';
    if not StartsText(treePrefix, rel) then Continue;
    if (ARules[i].SkipDir <> '') and (Pos('/icons/', '/' + rel) > 0)
       and (Pos('icons', ARules[i].SkipDir) > 0) then Continue;
    if (ARules[i].SkipDir <> '') and (Pos('/superpowers/', '/' + rel) > 0)
       and (Pos('superpowers', ARules[i].SkipDir) > 0) then Continue;
    if ARules[i].Exts = '' then Exit(True);             { whole tree }
    if Pos('|' + ext + '|', ARules[i].Exts) > 0 then Exit(True);
  end;
  Result := False;
end;

function TReleaseManifestTest.RulePaths(const ARules: TShipRules): string;
var
  i: Integer;
  sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.Duplicates := dupIgnore;
    sl.Sorted := True;
    for i := 0 to High(ARules) do
      if ARules[i].IsTree then sl.Add(Slashes(ARules[i].Rel));
    Result := sl.CommaText;
  finally
    sl.Free;
  end;
end;

procedure TReleaseManifestTest.CollectLpkFiles(const ALpk: string; ADest: TStrings);
var
  sl: TStringList;
  txt, v: string;
  p, q: Integer;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(RepoRoot + ALpk);
    txt := sl.Text;
  finally
    sl.Free;
  end;
  p := 1;
  repeat
    p := PosEx('<Filename Value="', txt, p);
    if p = 0 then Break;
    Inc(p, Length('<Filename Value="'));
    q := PosEx('"', txt, p);
    if q = 0 then Break;
    v := Slashes(Copy(txt, p, q - p));
    p := q + 1;
    { .lpk paths are relative to the package file, which sits at the repo root. }
    while StartsStr('./', v) do Delete(v, 1, 2);
    if (v <> '') and (ExtractFileExt(v) <> '') then ADest.Add(v);
  until False;
end;

procedure TReleaseManifestTest.SetUp;
begin
  FPs1 := ParsePs1(ReadScript(Ps1Path));
  FSh := ParseSh(ReadScript(ShPath));
end;

{ ---------------------------------------------------------------- the guards ------------- }

procedure TReleaseManifestTest.TheParserStillUnderstandsBothScripts;
var
  trees, files, i: Integer;
begin
  { Without this, a rewritten script that the parser no longer recognises would make every
    other assertion in this file vacuously true. }
  trees := 0; files := 0;
  for i := 0 to High(FPs1) do
    if FPs1[i].IsTree then Inc(trees) else Inc(files);
  AssertTrue(Format('make-release.ps1: parsed %d tree rules, expected at least 5', [trees]),
    trees >= 5);
  AssertTrue(Format('make-release.ps1: parsed %d file rules, expected at least 8', [files]),
    files >= 8);

  trees := 0; files := 0;
  for i := 0 to High(FSh) do
    if FSh[i].IsTree then Inc(trees) else Inc(files);
  AssertTrue(Format('make-release.sh: parsed %d tree rules, expected at least 5', [trees]),
    trees >= 5);
  AssertTrue(Format('make-release.sh: parsed %d file rules, expected at least 8', [files]),
    files >= 8);

  { And the predicate must actually discriminate, or "everything ships" would pass too. }
  AssertTrue('a runtime unit ships', IsShipped(FPs1, 'source/tyControls.Form.pas'));
  AssertFalse('the test suite does not', IsShipped(FPs1, 'tests/test.release.pas'));
  AssertFalse('nor do the scripts', IsShipped(FPs1, 'scripts/make-release.ps1'));
end;

procedure TReleaseManifestTest.EveryFileThePackagesNameIsShipped;
var
  named: TStringList;
  i: Integer;
  bad: string;
begin
  { The invariant that matters: a .lpk whose <Filename> is absent from the archive fails at
    COMPILE time for whoever installs the release, and at no earlier point for anyone. }
  named := TStringList.Create;
  try
    CollectLpkFiles('tycontrols.lpk', named);
    CollectLpkFiles('tycontrols_dt.lpk', named);
    AssertTrue('the .lpk files name some units', named.Count > 50);
    bad := '';
    for i := 0 to named.Count - 1 do
      if not IsShipped(FPs1, named[i]) then bad := bad + LineEnding + '  ' + named[i];
    AssertEquals('files a package lists but the release does not ship:' + bad, '', bad);
  finally
    named.Free;
  end;
end;

procedure TReleaseManifestTest.EveryDesignTimeUnitIsShipped;
var
  units: TStringList;
  i: Integer;
  rel, bad: string;
begin
  { designtime/ used to be copied as two hardcoded file names. A second unit -- which the icon
    browser work is about to add -- would have been dropped in silence. }
  units := TStringList.Create;
  try
    CollectDesignSourceFiles(units);
    bad := '';
    for i := 0 to units.Count - 1 do
    begin
      rel := 'designtime/' + ExtractFileName(units[i]);
      if not IsShipped(FPs1, rel) then bad := bad + LineEnding + '  ' + rel;
    end;
    AssertEquals('design-time units the release does not ship:' + bad, '', bad);
  finally
    units.Free;
  end;
end;

procedure TReleaseManifestTest.TheThirdPartyNoticeShipsWithTheFontItLicenses;
begin
  { The one hardcoded literal in this file, and it is spent deliberately: no manifest anywhere
    declares a licence obligation, so it cannot be derived. The release ships
    source/tyControls.Icons.Lucide.pas, which embeds the ISC/MIT-licensed Lucide font bytes;
    THIRD-PARTY-NOTICES.md is what discharges that. assets/lucide/ is NOT expected to ship --
    nothing reads it at run time, and its only consumers (the suite, the generator) are
    themselves excluded from the archive. }
  AssertTrue('the bundled font unit ships',
    IsShipped(FPs1, 'source/tyControls.Icons.Lucide.pas'));
  AssertTrue('so THIRD-PARTY-NOTICES.md must too (ps1)',
    IsShipped(FPs1, 'THIRD-PARTY-NOTICES.md'));
  AssertTrue('so THIRD-PARTY-NOTICES.md must too (sh)',
    IsShipped(FSh, 'THIRD-PARTY-NOTICES.md'));
  AssertTrue('and the notice file exists', FileExists(RepoRoot + 'THIRD-PARTY-NOTICES.md'));
end;

procedure TReleaseManifestTest.EveryAssetAShippedThemeReferencesIsShipped;
var
  css: TStringList;
  txt, ref, dir, rel, bad: string;
  files: TStringList;
  i, p, q, checked: Integer;
begin
  checked := 0;
  { A .tycss url() names a file NEXT TO IT. Shipping the stylesheet without the image gives a
    release whose theme renders with no background -- which is exactly what examples/theming
    did before the image extensions were added to the examples rule. }
  bad := '';
  files := FindAllFiles(RepoRoot + 'themes', '*.tycss', True);
  css := FindAllFiles(RepoRoot + 'examples', '*.tycss', True);
  try
    files.AddStrings(css);
    for i := 0 to files.Count - 1 do
    begin
      with TStringList.Create do
      try
        LoadFromFile(files[i]);
        txt := Text;
      finally
        Free;
      end;
      { Both sides EXPANDED before the prefix is taken. RepoRoot is '<exedir>/../', so it still
        contains the '..' segment, while FindAllFiles hands back a normalised path -- subtracting
        one length from the other sliced into the middle of the path and produced a directory
        that exists nowhere. That made the whole scan find zero assets, i.e. pass vacuously,
        which is what the checked>=1 assertion below now refuses to let happen again. }
      dir := Slashes(ExtractFilePath(ExpandFileName(files[i])));
      dir := Copy(dir, Length(Slashes(IncludeTrailingPathDelimiter(ExpandFileName(RepoRoot)))) + 1,
                  MaxInt);
      p := 1;
      repeat
        p := PosEx('url(', txt, p);
        if p = 0 then Break;
        Inc(p, 4);
        q := PosEx(')', txt, p);
        if q = 0 then Break;
        ref := Trim(Copy(txt, p, q - p));
        p := q + 1;
        ref := StringReplace(StringReplace(ref, '"', '', [rfReplaceAll]), '''', '', [rfReplaceAll]);
        if (ref = '') or (Pos('://', ref) > 0) then Continue;   { not a repo file }
        rel := dir + Slashes(ref);
        if not FileExists(RepoRoot + rel) then Continue;        { a broken ref is another test }
        Inc(checked);
        if not IsShipped(FPs1, rel) then
          bad := bad + LineEnding + '  ' + rel + '  (referenced by ' + ExtractFileName(files[i]) + ')';
      until False;
    end;
    { Anti-vacuity: if the scan finds nothing to check, "no bad assets" is not a result. There
      is at least examples/theming's background photo and the green theme's own copy. }
    AssertTrue('the url() scan found no local assets at all -- it stopped working',
      checked >= 1);
    AssertEquals(Format('assets a shipped stylesheet references but the release drops (%d checked):',
      [checked]) + bad, '', bad);
  finally
    css.Free;
    files.Free;
  end;
end;

procedure TReleaseManifestTest.BothScriptsShipTheSameTrees;
begin
  { The two scripts are edited by hand and only one of them tends to get edited. Comparing the
    TREE ROOTS catches the realistic drift without pinning cosmetic differences in how each
    language spells its extension list. }
  AssertEquals('make-release.ps1 and make-release.sh copy different trees',
    RulePaths(FPs1), RulePaths(FSh));
end;

procedure TReleaseManifestTest.EveryTestUnitThatRegistersTestsIsLinked;
var
  files, lpr: TStringList;
  i: Integer;
  testUnit, uses_, bad: string;
begin
  { A test unit is linked by exactly one thing: its name in tytests.lpr's uses clause. Forget it
    and the unit is never linked, its initialization never runs, RegisterTest never fires -- and
    the suite reports GREEN with those assertions simply absent. A unit that registers nothing
    (test.designregistry is the helper) exempts itself by not calling RegisterTest. }
  lpr := TStringList.Create;
  files := FindAllFiles(RepoRoot + 'tests', 'test.*.pas', False);
  try
    lpr.LoadFromFile(RepoRoot + 'tests' + PathDelim + 'tytests.lpr');
    uses_ := LowerCase(lpr.Text);
    bad := '';
    for i := 0 to files.Count - 1 do
    begin
      with TStringList.Create do
      try
        LoadFromFile(files[i]);
        if Pos('RegisterTest(', Text) = 0 then Continue;
      finally
        Free;
      end;
      testUnit := LowerCase(ChangeFileExt(ExtractFileName(files[i]), ''));
      { whole-identifier match: ',' or whitespace on both sides in the uses clause }
      if (Pos(' ' + testUnit + ',', uses_) = 0) and (Pos(' ' + testUnit + ';', uses_) = 0)
         and (Pos(LineEnding + '  ' + testUnit + ',', uses_) = 0) then
        bad := bad + LineEnding + '  ' + testUnit;
    end;
    AssertEquals('test units that register tests but are not in tytests.lpr'
      + ' (their assertions never run):' + bad, '', bad);
  finally
    files.Free;
    lpr.Free;
  end;
end;

procedure TReleaseManifestTest.TheControlDocsIndexLinksEveryPageAndOnlyRealOnes;
var
  pages, linked: TStringList;
  idx, nm, orphan, dead: string;
  i, p, q: Integer;
begin
  { docs/ ships whole, so a page with no link is not DROPPED -- it is unreachable, which for a
    reader is the same thing. Both directions, because a link with no page is a 404 in the
    rendered docs. tyControls.FileSystem was the orphan when this was written. }
  pages := TStringList.Create;
  linked := TStringList.Create;
  try
    pages.Sorted := True; pages.Duplicates := dupIgnore;
    linked.Sorted := True; linked.Duplicates := dupIgnore;

    with FindAllFiles(RepoRoot + 'docs' + PathDelim + 'controls', '*.md', False) do
    try
      for i := 0 to Count - 1 do
      begin
        nm := LowerCase(ChangeFileExt(ExtractFileName(Strings[i]), ''));
        if nm <> 'readme' then pages.Add(nm);
      end;
    finally
      Free;
    end;

    with TStringList.Create do
    try
      LoadFromFile(RepoRoot + 'docs' + PathDelim + 'controls' + PathDelim + 'README.md');
      idx := Text;
    finally
      Free;
    end;
    p := 1;
    repeat
      p := PosEx('](', idx, p);
      if p = 0 then Break;
      Inc(p, 2);
      q := PosEx(')', idx, p);
      if q = 0 then Break;
      nm := LowerCase(Copy(idx, p, q - p));
      p := q + 1;
      { only same-directory page links: no URLs, no sub-paths, no anchors }
      if (Pos('/', nm) > 0) or (Pos(':', nm) > 0) or (Pos('#', nm) > 0) then Continue;
      if not EndsStr('.md', nm) then Continue;
      linked.Add(ChangeFileExt(nm, ''));
    until False;

    AssertTrue('the index links no pages at all -- the scan stopped working', linked.Count > 50);

    orphan := ''; dead := '';
    for i := 0 to pages.Count - 1 do
      if linked.IndexOf(pages[i]) < 0 then orphan := orphan + ' ' + pages[i];
    for i := 0 to linked.Count - 1 do
      if pages.IndexOf(linked[i]) < 0 then dead := dead + ' ' + linked[i];
    AssertEquals('doc pages nothing links to (unreachable from the index):' + orphan, '', orphan);
    AssertEquals('index links with no page behind them:' + dead, '', dead);
  finally
    linked.Free;
    pages.Free;
  end;
end;

initialization
  RegisterTest(TReleaseManifestTest);

end.
