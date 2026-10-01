unit tbexport;
{ Exporting a theme bundle: what the library's reader (ThemeBundle.pas) reads -- the entry
  stylesheet theme.tycss (cTyDefaultThemeEntry; TyRegisterThemeFolder only ever looks for
  that name), a manifest theme.json (name, author, version, entry, dualMode), and the files
  the text refers to, at the same relative paths.

  Two formats. A FOLDER bundle carries everything. A ZIP bundle can only carry a theme that
  refers to no other file: the library's zip reader hands the model the entry text only --
  the model expands @import from the disk (StyleModel ExpandSheet never asks the source) and
  the painter wants a file path for an image -- so an @import in a zip does not load, and an
  image in a zip is never drawn. Exporting such a theme as a zip is refused.

  Which files: what the runtime would read, by its rules. @import is relative to the file
  that imports it (each level from its own folder); url() is always relative to the ENTRY's
  folder, in an imported file too (StyleModel resolves it against the theme's base folder).
  A reference that is absolute, or climbs out of the theme's folder (a '..' segment), or to a
  file that is not there, or that cannot be resolved because the document was never saved,
  stops the export and is listed.

  The bundle is written beside the target (<target>.tbtmp<pid>), read back through the
  library's own readers (TTyThemeDirSource / TTyThemeZipSource), loaded into a fresh style
  model and probed in every mode the way the preview probes a document (TbProbeDocument) --
  in the classic density, then with the modern density pack over it.
  Only when all of that passes is it moved to the target; on any failure the temporary
  bundle is deleted -- no half bundle is ever left, and a zip that was there is untouched. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils;

resourcestring
  rsTbExportBadRef = '%s: %s';
  rsTbExportAbsolute = 'an absolute path; move the file next to the theme';
  rsTbExportOutside = 'outside the theme''s folder';
  rsTbExportUnsaved = 'save the theme first: paths are read from its folder';
  rsTbExportMissing = 'not found';
  rsTbExportEntryClash = 'the bundle''s own %s goes there -- rename this file';
  rsTbExportCaseClash = 'also written as %s: a system that tells capitals from small letters finds only one of the two -- write it the same way everywhere';
  rsTbExportNoTarget = 'Choose where to export to.';
  rsTbExportFolderNotEmpty = '%s is not an empty folder.';
  rsTbExportNoParent = 'The folder %s does not exist.';
  rsTbExportNotAFile = '%s is a folder.';
  rsTbExportZipRefs = 'A zip bundle cannot carry the files this theme refers to (the library reads neither @import nor images from a zip). Export a folder.';
  rsTbExportVerifyFailed = 'The bundle did not load back';
  rsTbExportMoveFailed = 'Could not move the bundle to %s: %s';

type
  TTbBundleFormat = (tbfFolder, tbfZip);
  TTbBundleFile = record
    Source: string;     { on disk, expanded }
    Archive: string;    { in the bundle, '/' separated, as the text refers to it }
  end;
  TTbBundleFiles = array of TTbBundleFile;
  TTbBundleInfo = record
    Name, Author, Version: string;
    DualMode: Boolean;
  end;

{ the files AText (the entry, in ABaseDir) refers to, @import chains followed. False and
  AError (one line per reference) when one cannot go in the bundle }
function TbCollectBundleFiles(const AText, ABaseDir: string; out AFiles: TTbBundleFiles;
  out AError: string): Boolean;
function TbManifestJson(const AInfo: TTbBundleInfo): string;
{ write, read back, load, probe, move into place; False and AError, with nothing left behind }
function TbExportBundle(const AEntry: string; const AFiles: TTbBundleFiles;
  const AInfo: TTbBundleInfo; AFormat: TTbBundleFormat; const ATarget: string;
  out AError: string): Boolean;

var
  { FOR THE TESTS: how the bundle (and an old target) is moved; RenameFile when nil }
  TbExportRenameForTest: function(const AFrom, ATo: string): Boolean = nil;

implementation

uses
  fpjson, zipper, FileUtil, LazFileUtils,
  tyControls.Css.Tokens, tyControls.Css.Lexer, tyControls.StyleModel, tyControls.ThemeBundle,
  tyControls.DensityPack, tbcssscan, tbpreview;

{ ---- collecting ---- }

function ReadFileBytes(const AFileName: string): string;
var
  fs: TFileStream;
begin
  Result := '';
  fs := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, fs.Size);
    if fs.Size > 0 then
      fs.ReadBuffer(Result[1], fs.Size);
  finally
    fs.Free;
  end;
end;

procedure WriteFileBytes(const AFileName, ABytes: string);
var
  fs: TFileStream;
begin
  fs := TFileStream.Create(AFileName, fmCreate);
  try
    if ABytes <> '' then
      fs.WriteBuffer(ABytes[1], Length(ABytes));
  finally
    fs.Free;
  end;
end;

{ the paths of the top-level @import statements, as written }
function ImportPaths(const AText: string): TStringArray;
var
  lex: TTyCssLexer;
  t: TTyCssToken;
  path: string;
begin
  Result := nil;
  lex := TTyCssLexer.Create(AText);
  try
    while True do
    begin
      t := lex.Next;
      if t.Kind = ctkEOF then Break;
      if (t.Kind <> ctkAtKeyword) or not SameText(t.Text, 'import') then Continue;
      t := lex.Next;
      path := '';
      if t.Kind = ctkString then
        path := t.Text
      else if (t.Kind = ctkFunction) and SameText(t.Text, 'url') then
      begin
        { url(...): a string, or the bare path in pieces up to the ')' }
        t := lex.Next;
        while not (t.Kind in [ctkRParen, ctkSemicolon, ctkEOF]) do
        begin
          if t.Kind = ctkString then
            path := path + t.Text
          else if t.Kind = ctkHash then
            path := path + '#' + t.Text
          else
            path := path + t.Text;
          t := lex.Next;
        end;
      end;
      if path <> '' then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := path;
      end;
    end;
  finally
    lex.Free;
  end;
end;

{ the url() paths in the values of every block, unquoted; data: URLs left out }
function UrlPaths(const AText: string): TStringArray;
var
  s: TTbCssScan;
  b, d, p, q: Integer;
  v, low, path: string;
begin
  Result := nil;
  s := TbScanCss(AText);
  try
    for b := 0 to s.Count - 1 do
      for d := 0 to High(s.Block(b).Decls) do
      begin
        v := s.DeclValue(b, d);
        low := LowerCase(v);
        p := Pos('url(', low);
        while p > 0 do
        begin
          q := p + 4;
          while (q <= Length(v)) and (v[q] <> ')') do
            Inc(q);
          path := Trim(Copy(v, p + 4, q - p - 4));
          if (Length(path) >= 2) and (path[1] in ['"', '''']) and (path[Length(path)] = path[1]) then
            path := Copy(path, 2, Length(path) - 2);
          path := Trim(path);
          if (path <> '') and not SameText(Copy(path, 1, 5), 'data:') then
          begin
            SetLength(Result, Length(Result) + 1);
            Result[High(Result)] := path;
          end;
          p := Pos('url(', Copy(low, q, MaxInt));
          if p > 0 then
            p := p + q - 1;
        end;
      end;
  finally
    s.Free;
  end;
end;

function HasDotDot(const APath: string): Boolean;
var
  parts: string;
  i, start: Integer;
begin
  parts := StringReplace(APath, '\', '/', [rfReplaceAll]);
  start := 1;
  for i := 1 to Length(parts) + 1 do
    if (i > Length(parts)) or (parts[i] = '/') then
    begin
      if Copy(parts, start, i - start) = '..' then
        Exit(True);
      start := i + 1;
    end;
  Result := False;
end;

{ 'a\b/./c' -> 'a/b/c' }
function NormArchive(const APath: string): string;
begin
  Result := StringReplace(APath, '\', '/', [rfReplaceAll]);
  while Pos('/./', Result) > 0 do
    Result := StringReplace(Result, '/./', '/', [rfReplaceAll]);
  while Copy(Result, 1, 2) = './' do
    Delete(Result, 1, 2);
end;

function IsAbsoluteRef(const APath: string): Boolean;
begin
  Result := (APath <> '') and ((APath[1] in ['/', '\']) or FilenameIsAbsolute(APath));
end;

function TbCollectBundleFiles(const AText, ABaseDir: string; out AFiles: TTbBundleFiles;
  out AError: string): Boolean;
var
  base: string;
  seen: TStringList;     { expanded paths already in AFiles (or expanded, for an import) }
  spelled: TStringList;  { for each of seen, the bundle path it was first written as }
  errors: string;

  procedure Fail(const APath, AWhy: string);
  begin
    if errors <> '' then errors := errors + LineEnding;
    errors := errors + Format(rsTbExportBadRef, [APath, AWhy]);
  end;

  function Key(const AFull: string): string;
  begin
    {$IFDEF MSWINDOWS}
    Result := LowerCase(AFull);
    {$ELSE}
    Result := AFull;
    {$ENDIF}
  end;

  { APath as written; AArchive where it goes; False when it cannot go in (and says why) }
  function Check(const APath, AArchive: string; out AFull: string): Boolean;
  begin
    Result := False;
    AFull := '';
    if IsAbsoluteRef(APath) then
      Fail(APath, rsTbExportAbsolute)
    else if HasDotDot(APath) then
      Fail(APath, rsTbExportOutside)
    else if base = '' then
      Fail(APath, rsTbExportUnsaved)
    else
    begin
      AFull := ExpandFileName(base + StringReplace(AArchive, '/', PathDelim, [rfReplaceAll]));
      if not FileExists(AFull) then
        Fail(APath, rsTbExportMissing)
      else
        Result := True;
    end;
  end;

  { AFull is in already. On a system that does not tell capitals from small letters the same
    file may be written two ways (Assets/a.png, assets/a.png); one bundle path has to do for
    both, and on one that does tell them apart the other would not be found -- refused }
  function AlreadyIn(const AFull, AArchive, APath: string): Boolean;
  var
    k: Integer;
  begin
    k := seen.IndexOf(Key(AFull));
    Result := k >= 0;
    if Result and (spelled[k] <> AArchive) then
      Fail(APath, Format(rsTbExportCaseClash, [spelled[k]]));
  end;

  procedure AddFile(const AFull, AArchive: string);
  var
    n: Integer;
  begin
    seen.Add(Key(AFull));
    spelled.Add(AArchive);
    n := Length(AFiles);
    SetLength(AFiles, n + 1);
    AFiles[n].Source := AFull;
    AFiles[n].Archive := AArchive;
  end;

  { the imports of AText (a file at APrefix in the bundle), each followed down once }
  procedure Imports(const AText, APrefix: string);
  var
    paths: TStringArray;
    i: Integer;
    arch, full: string;
  begin
    paths := ImportPaths(AText);
    for i := 0 to High(paths) do
    begin
      arch := NormArchive(APrefix + NormArchive(paths[i]));
      if not Check(paths[i], arch, full) then Continue;
      if AlreadyIn(full, arch, paths[i]) then Continue;   { a diamond, or a cycle }
      AddFile(full, arch);
      Imports(ReadFileBytes(full), Copy(arch, 1, LastDelimiter('/', arch)));
    end;
  end;

  procedure Urls(const AText: string);
  var
    paths: TStringArray;
    i: Integer;
    arch, full: string;
  begin
    paths := UrlPaths(AText);
    for i := 0 to High(paths) do
    begin
      arch := NormArchive(paths[i]);       { always from the entry's folder }
      if Check(paths[i], arch, full) and not AlreadyIn(full, arch, paths[i]) then
        AddFile(full, arch);
    end;
  end;

var
  i, n: Integer;
begin
  AFiles := nil;
  errors := '';
  if ABaseDir <> '' then
    base := IncludeTrailingPathDelimiter(ExpandFileName(ABaseDir))
  else
    base := '';
  seen := TStringList.Create;
  spelled := TStringList.Create;
  try
    Urls(AText);
    Imports(AText, '');
    { the url()s inside the imported stylesheets: still from the entry's folder }
    n := Length(AFiles);
    for i := 0 to n - 1 do
      if SameText(ExtractFileExt(AFiles[i].Source), '.tycss') then
        Urls(ReadFileBytes(AFiles[i].Source));
    { the entry is written as theme.tycss and the manifest as theme.json, whatever the
      document's own name: a file the theme refers to by either name would be overwritten
      (or overwrite the entry) -- refused, not renamed: renaming means rewriting the
      reference, and what is exported is the text a save would write }
    for i := 0 to High(AFiles) do
      if SameText(AFiles[i].Archive, cTyDefaultThemeEntry) or SameText(AFiles[i].Archive, 'theme.json') then
        Fail(AFiles[i].Archive, Format(rsTbExportEntryClash, [LowerCase(AFiles[i].Archive)]));
  finally
    seen.Free;
    spelled.Free;
  end;
  AError := errors;
  Result := errors = '';
end;

{ ---- the manifest ---- }

function TbManifestJson(const AInfo: TTbBundleInfo): string;
var
  obj: TJSONObject;
begin
  obj := TJSONObject.Create;
  try
    obj.Add('name', AInfo.Name);
    obj.Add('author', AInfo.Author);
    obj.Add('version', AInfo.Version);
    obj.Add('entry', cTyDefaultThemeEntry);
    obj.Add('dualMode', AInfo.DualMode);
    Result := obj.FormatJSON;
  finally
    obj.Free;
  end;
end;

{ ---- writing ---- }

{ ADir holds anything at all -- a file, a folder, hidden ones too. The first entry answers:
  a target that is a big folder (a drive's root, a home folder) is not walked whole. }
function FolderHasAnything(const ADir: string): Boolean;
var
  sr: TSearchRec;
begin
  Result := False;
  if FindFirst(IncludeTrailingPathDelimiter(ADir) + AllFilesMask, faAnyFile, sr) = 0 then
  try
    repeat
      if (sr.Name <> '.') and (sr.Name <> '..') then
        Exit(True);
    until FindNext(sr) <> 0;
  finally
    FindClose(sr);
  end;
end;

function CheckTarget(AFormat: TTbBundleFormat; const ATarget: string; out AError: string): Boolean;
var
  parent: string;
begin
  Result := False;
  AError := '';
  if Trim(ATarget) = '' then
  begin
    AError := rsTbExportNoTarget;
    Exit;
  end;
  parent := ExtractFileDir(ExcludeTrailingPathDelimiter(ATarget));
  if (parent <> '') and not DirectoryExists(parent) then
  begin
    AError := Format(rsTbExportNoParent, [parent]);
    Exit;
  end;
  if AFormat = tbfFolder then
  begin
    if FileExists(ATarget) then
    begin
      AError := Format(rsTbExportFolderNotEmpty, [ATarget]);
      Exit;
    end;
    { the tool never deletes a folder of the user's: only an empty one is taken }
    if DirectoryExists(ATarget) and FolderHasAnything(ATarget) then
    begin
      AError := Format(rsTbExportFolderNotEmpty, [ATarget]);
      Exit;
    end;
  end
  else if DirectoryExists(ATarget) then
  begin
    AError := Format(rsTbExportNotAFile, [ATarget]);
    Exit;
  end;
  Result := True;
end;

procedure WriteBundle(AFormat: TTbBundleFormat; const ATemp, AEntry: string;
  const AFiles: TTbBundleFiles; const AInfo: TTbBundleInfo);
var
  i: Integer;
  dest: string;
  z: TZipper;
  sEntry, sJson: TStringStream;
begin
  if AFormat = tbfFolder then
  begin
    if not ForceDirectories(ATemp) then
      raise Exception.CreateFmt(rsTbExportNoParent, [ATemp]);
    WriteFileBytes(IncludeTrailingPathDelimiter(ATemp) + cTyDefaultThemeEntry, AEntry);
    WriteFileBytes(IncludeTrailingPathDelimiter(ATemp) + 'theme.json', TbManifestJson(AInfo));
    for i := 0 to High(AFiles) do
    begin
      dest := IncludeTrailingPathDelimiter(ATemp)
        + StringReplace(AFiles[i].Archive, '/', PathDelim, [rfReplaceAll]);
      ForceDirectories(ExtractFileDir(dest));
      WriteFileBytes(dest, ReadFileBytes(AFiles[i].Source));
    end;
  end
  else
  begin
    sEntry := TStringStream.Create(AEntry);
    sJson := TStringStream.Create(TbManifestJson(AInfo));
    z := TZipper.Create;
    try
      z.FileName := ATemp;
      z.Entries.AddFileEntry(sEntry, cTyDefaultThemeEntry);
      z.Entries.AddFileEntry(sJson, 'theme.json');
      z.ZipAllFiles;
    finally
      z.Free;
      sEntry.Free;
      sJson.Free;
    end;
  end;
end;

function ModeCaption(const AMode: string): string;
begin
  if SameText(AMode, 'light') then
    Result := rsTbModeLight
  else if SameText(AMode, 'dark') then
    Result := rsTbModeDark
  else
    Result := AMode;
end;

function VerifyBundle(AFormat: TTbBundleFormat; const ATemp, AEntry: string;
  const AFiles: TTbBundleFiles; const AInfo: TTbBundleInfo; out AError: string): Boolean;
var
  src: ITyThemeSource;
  man: TTyThemeManifest;
  model: TTyStyleModel;
  stm: TStream;
  modes: TStringArray;
  i: Integer;
  why, err, css: string;
begin
  Result := False;
  AError := '';
  why := '';
  if AFormat = tbfFolder then
    src := TTyThemeDirSource.Create(ATemp)
  else
    src := TTyThemeZipSource.Create(ATemp);
  man := src.Manifest;
  if not man.Loaded then
    why := 'theme.json'
  else if man.Entry <> cTyDefaultThemeEntry then
    why := 'entry ' + man.Entry
  else if (man.Name <> AInfo.Name) or (man.Author <> AInfo.Author)
          or (man.Version <> AInfo.Version) or (man.DualMode <> AInfo.DualMode) then
    why := 'theme.json';
  css := src.RootCss;
  if (why = '') and (css = '') and not TbIsBlank(AEntry) then
    why := cTyDefaultThemeEntry;
  if why = '' then
    for i := 0 to High(AFiles) do
    begin
      stm := nil;
      if not src.OpenAsset(AFiles[i].Archive, stm) then
      begin
        why := AFiles[i].Archive;
        Break;
      end;
      stm.Free;
    end;
  if why = '' then
  begin
    model := TTyStyleModel.Create;
    try
      try
        model.LoadFromSource(src);
        modes := model.ModeNames;
        if Length(modes) = 0 then
        begin
          SetLength(modes, 1);
          modes[0] := '';
        end;
        for i := 0 to High(modes) do
        begin
          model.SetMode(modes[i]);
          { the preview's own standard: what a paint in that mode would evaluate }
          if not TbProbeDocument(model, css, False, err) then
          begin
            if modes[i] <> '' then
              why := Format(rsTbModeFailed, [ModeCaption(modes[i]), err])
            else
              why := err;
            Break;
          end;
        end;
        { and in the modern density, as an application that switches to it loads it: the
          density pack over the theme (TTbPreviewFrame.LoadInto) -- a theme that uses one
          of its variables as something else does not resolve there }
        if why = '' then
        begin
          model.LoadFromCssAdditive(TyDensityModernCss);
          for i := 0 to High(modes) do
          begin
            model.SetMode(modes[i]);
            if not TbProbeDocument(model, css, True, err) then
            begin
              if modes[i] <> '' then
                err := Format(rsTbModeFailed, [ModeCaption(modes[i]), err]);
              why := Format(rsTbDensityFailed, [rsTbDensityModern, err]);
              Break;
            end;
          end;
        end;
      except
        on E: Exception do
          why := E.Message;
      end;
    finally
      model.Free;
    end;
  end;
  src := nil;
  if why <> '' then
  begin
    AError := rsTbExportVerifyFailed + ': ' + why;
    Exit;
  end;
  Result := True;
end;

function MoveFile(const AFrom, ATo: string): Boolean;
begin
  if Assigned(TbExportRenameForTest) then
    Result := TbExportRenameForTest(AFrom, ATo)
  else
    Result := RenameFile(AFrom, ATo);
end;

{ why the last move failed, in the system's words }
function MoveFailure(const ATarget: string): string;
begin
  Result := Format(rsTbExportMoveFailed, [ATarget, SysErrorMessage(GetLastOSError)]);
end;

{ ABase, else ABase with a number before its extension that is not taken }
function FreeName(const ABase, AExt: string): string;
var
  n: Integer;
begin
  Result := ABase + AExt;
  n := 1;
  while FileExists(Result) or DirectoryExists(Result) do
  begin
    Result := ABase + '.' + IntToStr(n) + AExt;
    Inc(n);
  end;
end;

function CommitBundle(AFormat: TTbBundleFormat; const ATemp, ATarget: string;
  out AError: string): Boolean;
var
  bak, aside: string;
begin
  Result := False;
  AError := '';
  if AFormat = tbfFolder then
  begin
    { The user's empty folder is moved aside, not deleted: if the bundle cannot be moved in,
      it goes back as it was. }
    aside := '';
    if DirectoryExists(ATarget) then
    begin
      aside := FreeName(ATarget, '.tbold');
      if not MoveFile(ATarget, aside) then
      begin
        AError := MoveFailure(ATarget);
        Exit;
      end;
    end;
    if not MoveFile(ATemp, ATarget) then
    begin
      AError := MoveFailure(ATarget);
      if aside <> '' then
        MoveFile(aside, ATarget);
      Exit;
    end;
    if aside <> '' then
      RemoveDir(aside);             { empty: CheckTarget made sure }
  end
  else
  begin
    if FileExists(ATarget) then
    begin
      { the old zip moved aside under a name nobody uses -- a .tbbak that is there already
        is somebody's file (a backup of an earlier crash, the user's own) and stays }
      bak := FreeName(ATarget, '.tbbak');
      if not MoveFile(ATarget, bak) then
      begin
        AError := MoveFailure(ATarget);
        Exit;
      end;
      if not MoveFile(ATemp, ATarget) then
      begin
        AError := MoveFailure(ATarget);
        MoveFile(bak, ATarget);     { the old zip back as it was }
        Exit;
      end;
      DeleteFile(bak);
    end
    else if not MoveFile(ATemp, ATarget) then
    begin
      AError := MoveFailure(ATarget);
      Exit;
    end;
  end;
  Result := True;
end;

procedure RemoveTemp(AFormat: TTbBundleFormat; const ATemp: string);
begin
  try
    if AFormat = tbfFolder then
    begin
      if DirectoryExists(ATemp) then
        DeleteDirectory(ATemp, False);
    end
    else if FileExists(ATemp) then
      DeleteFile(ATemp);
  except
    { cleaning up must not raise over the error being reported }
  end;
end;

function TbExportBundle(const AEntry: string; const AFiles: TTbBundleFiles;
  const AInfo: TTbBundleInfo; AFormat: TTbBundleFormat; const ATarget: string;
  out AError: string): Boolean;
var
  temp, target: string;
begin
  AError := '';
  Result := False;
  target := ExcludeTrailingPathDelimiter(Trim(ATarget));
  if not CheckTarget(AFormat, target, AError) then Exit;
  if (AFormat = tbfZip) and (Length(AFiles) > 0) then
  begin
    AError := rsTbExportZipRefs;
    Exit;
  end;
  temp := target + '.tbtmp' + IntToStr(GetProcessID);
  RemoveTemp(AFormat, temp);           { what a crash may have left }
  try
    WriteBundle(AFormat, temp, AEntry, AFiles, AInfo);
    if VerifyBundle(AFormat, temp, AEntry, AFiles, AInfo, AError) then
      Result := CommitBundle(AFormat, temp, target, AError);
  except
    on E: Exception do
    begin
      AError := E.Message;
      Result := False;
    end;
  end;
  if not Result then
    RemoveTemp(AFormat, temp);
end;

end.
