unit tyControls.FileSystem;

{ Pure, headless file-system model for the ty-controls shell/file-dialog family.

  This unit is the single source of truth every shell view (list, tree, combo,
  file dialog) reads from: a view's item index is always an index into the
  TTyFsEntryArray this unit hands back. It enumerates, filters, sorts and
  describes directory entries and computes portable "places"/parent/breadcrumb
  helpers. It has NO LCL widget dependency, so it is 100% headless-testable.

  Cross-platform contract (hard):
    * Every filesystem touch goes through a LazFileUtils *UTF8 wrapper
      (FindFirstUTF8 / FindNextUTF8 / FindCloseUTF8 / DirectoryExistsUTF8 /
      ExpandFileNameUTF8). Bare SysUtils.FindFirst corrupts non-ASCII names on
      Windows.
    * "Hidden" is one portable predicate: (Attr and faHidden), with the FPC
      not-portable hint suppressed -- a real FILE_ATTRIBUTE_HIDDEN on Windows,
      synthesised from a leading dot by the FPC RTL (LinuxToWinAttr) on Unix.
      There is deliberately no Name[1]='.' branch.
    * Masks go through Masks.MatchesWindowsMaskList (DefaultWindowsQuirks) so
      '*.*' / 'foo.*' behave file-dialog style; '*.*' and '' normalise to '*'.
    * Case rules go through CompareFilenames (OS-aware).
    * The ONLY conditional platform logic in the unit is in TyFsRoots (drive
      letters via GetLogicalDriveStrings vs a Unix '/' + home + a heuristic
      mount-point scan). There is never a 'Drive: Char' API. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, LazFileUtils, FileUtil, Masks, LazUTF8
  {$IFDEF MSWINDOWS}, Windows{$ENDIF};

type
  { One enumerated directory entry. All fields are RAW values (not display
    strings): a view formats Size/Modified for display but sorts on these. }
  TTyFsEntry = record
    Name, FullPath: string;
    IsDir, IsHidden: Boolean;
    Size: Int64;
    Modified: TDateTime;
    Attr: LongInt;
    TypeName: string;        { heuristic kind label, not an OS-registered description }
  end;
  TTyFsEntryArray = array of TTyFsEntry;

  { What kinds of entries an enumeration keeps. Absence of fotFolders drops
    directories, absence of fotFiles drops files, absence of fotHidden drops
    hidden entries. }
  TTyFsObjectType  = (fotFolders, fotFiles, fotHidden);
  TTyFsObjectTypes = set of TTyFsObjectType;

  { Which raw field a comparison/sort keys on. }
  TTyFsSortKey = (fskName, fskSize, fskType, fskModified);

  { Whether a file MASK matches case-sensitively.

    mcsPlatformDefault follows the filesystem's own rule (FileUtil's compile-time
    FilenamesCaseSensitive: False on Windows/macOS, True on Linux); the other two
    say so outright regardless of host. Mirrors LCL's TMaskCaseSensitivity
    (C:/lazarus/lcl/shellctrls.pas:46) name for name, so ported code reads the
    same -- but see TTyShellListView.MaskCaseSensitivity for why our DEFAULT
    differs from LCL's. }
  TTyMaskCaseSensitivity = (mcsPlatformDefault, mcsCaseInsensitive, mcsCaseSensitive);

  { How a directory's entries are ordered before they reach a view.
    LCL's TFileSortType (shellctrls.pas:44), value for value. fstCustom defers to
    the consumer's own comparator. }
  TTyFsFileSortType = (fstNone, fstAlphabet, fstFoldersFirst, fstCustom);

  { Per-entry veto raised while a view populates itself: set ACanAdd False to drop
    this one entry. LCL's TAddItemEvent (shellctrls.pas:77-78) hands back a raw
    TSearchRec; ours hands the already-decoded TTyFsEntry, which carries every
    field TSearchRec does plus IsDir/IsHidden/TypeName. }
  TTyFsAddItemEvent = procedure(Sender: TObject; const ABasePath: string;
    const AEntry: TTyFsEntry; var ACanAdd: Boolean) of object;

  { A consumer's own ordering over two raw entries (LCL's TFileItemCompareEvent,
    shellctrls.pas:73). Negative / zero / positive, as any comparator. }
  TTyFsCompareEvent = function(const A, B: TTyFsEntry): Integer of object;

  { A navigable "place": a Windows drive, the Unix root, the user home, a
    mounted volume, or a curated place. }
  TTyFsRootKind = (rkDrive, rkRoot, rkHome, rkVolume, rkPlace);
  TTyFsRoot     = record Path, Display: string; Kind: TTyFsRootKind; end;
  TTyFsRootArray = array of TTyFsRoot;

  { One parsed segment of an LCL filter string: a human caption and the
    associated ';'-separated pattern list. }
  TTyFsFilterSpec = record Caption, Patterns: string; end;
  TTyFsFilterSpecArray = array of TTyFsFilterSpec;

{ Enumerate ADir into a flat array (the OwnerData backing store).

  Walks AppendPathDelim(ADir)+'*' with faAnyFile via FindFirstUTF8/FindNextUTF8,
  skips '.'/'..', and for each survivor sets IsDir=(Attr and faDirectory),
  IsHidden=(Attr and faHidden). Drops hidden unless fotHidden is set, folders
  unless fotFolders, files unless fotFiles. AMask filters FILES ONLY --
  directories are always shown. Name/FullPath/Size/Modified/Attr/TypeName are
  filled from the search record; TypeName via TyFsTypeName.

  ACaseSens selects how AMask is matched. It defaults to False -- this library's
  file-dialog convention, and the behaviour every existing caller already had, so
  adding the parameter changed nothing for them. A caller that wants the host
  filesystem's own rule passes TyFsMaskCaseSensitive(mcsPlatformDefault).

  Portable primitive: FindFirstUTF8 (FindCloseUTF8 always runs in try/finally).
  A non-existent or unreadable directory never raises -- it returns an empty
  array (sentinel: Length(Result)=0). }
function TyFsReadDirectory(const ADir, AMask: string; AOptions: TTyFsObjectTypes;
  ACaseSens: Boolean = False): TTyFsEntryArray;

{ Resolve a TTyMaskCaseSensitivity to the Boolean TyFsMatchesFilter takes.
  mcsPlatformDefault reads FileUtil's compile-time FilenamesCaseSensitive, so the
  answer is the host filesystem's own rule and needs no IFDEF at the call site. }
function TyFsMaskCaseSensitive(AValue: TTyMaskCaseSensitivity): Boolean;

{ True when AName matches APatterns (a ';'-separated pattern list).

  Thin wrapper over Masks.MatchesWindowsMaskList with DefaultWindowsQuirks so
  '*.*' / 'foo.*' behave the way a file dialog expects. An empty or '*.*'
  pattern list normalises to AllFilesMask '*' (matches everything). ACaseSens
  selects case-sensitive matching. }
function TyFsMatchesFilter(const AName, APatterns: string; ACaseSens: Boolean): Boolean;

{ Parse an LCL filter string ('Desc (*.ext)|*.ext;*.e2|All files|*.*') into an
  array of (Caption, Patterns) pairs, splitting on '|' and pairing caption then
  patterns. A malformed / odd-segment string never crashes: a trailing caption
  with no patterns yields a spec whose Patterns is ''. An empty filter returns
  an empty array. }
function TyFsParseFilter(const AFilter: string): TTyFsFilterSpecArray;

{ The pattern list of the AIndex-th filter segment (AIndex is 1-based, the LCL
  FilterIndex convention). Out-of-range indices clamp to the first/last segment.
  Returns '' when the filter has no segments. }
function TyFsFilterPatterns(const AFilter: string; AIndex: Integer): string;

{ Compare two entries for a shell sort. Folders always sort before files when
  AFoldersFirst is set -- independent of AAscending. Otherwise the entries are
  ordered by AKey over their RAW values (Name via CompareFilenames, Size as
  Int64, Modified as TDateTime, TypeName case-insensitively). AAscending only
  flips the comparison between two comparable values, never the folders-first
  placement. Returns 0 when the keyed values are equal (a stable sort then
  preserves input order). }
function TyFsCompareEntries(const A, B: TTyFsEntry; AKey: TTyFsSortKey;
  AAscending, AFoldersFirst: Boolean): Integer;

{ In-place, STABLE sort of AEntries using TyFsCompareEntries (bottom-up merge
  sort). For flat consumers (file list box / tree); the ListView keeps its own
  order array and only calls TyFsCompareEntries. A length < 2 array is left
  untouched. }
procedure TyFsSortEntries(var AEntries: TTyFsEntryArray; AKey: TTyFsSortKey;
  AAscending, AFoldersFirst: Boolean);

{ The same in-place STABLE sort, ordered by a caller's own comparator instead of a
  key/direction/folders-first triple. A sibling rather than a wrapper because the
  two take genuinely different orderings: TyFsCompareEntries needs three arguments
  that no method-pointer signature carries. A nil comparator, or a length < 2
  array, leaves AEntries untouched. }
procedure TyFsSortEntriesBy(var AEntries: TTyFsEntryArray; ACompare: TTyFsCompareEvent);

{ True when APath holds at least one entry the AOptions set would keep -- the
  generalisation of TyFsHasSubdir to a tree that also shows files. Stops at the
  FIRST survivor, so it stays the cheap has-children probe a lazy tree stamps its
  expand arrow from, and it honours fotHidden (TyFsHasSubdir does not, which is why
  a folder holding only a hidden subdirectory used to show an arrow that expanded
  to nothing). A non-existent / unreadable directory returns False, never raises. }
function TyFsHasEntry(const APath: string; AOptions: TTyFsObjectTypes): Boolean;

{ The portable list of navigable "places", always with at least one element.

  Windows: one rkDrive per logical drive (GetLogicalDriveStrings); Path 'C:\',
  Display 'C:'. Unix: '/' (rkRoot), the user home (rkHome), then existing
  directories under /media/$USER, /run/media/$USER, /mnt, /Volumes (rkVolume).
  Never raises; never returns an empty array. This is the unit's only
  conditional platform branch. }
function TyFsRoots: TTyFsRootArray;

{ True when APath contains at least one subdirectory. Stops at the FIRST one
  found via FindFirstUTF8 with faDirectory (skipping '.'/'..') -- it never
  enumerates the whole directory, so it is the cheap has-children probe a lazy
  directory tree stamps its expand arrow from. A non-existent / unreadable
  directory returns False, never raises. }
function TyFsHasSubdir(const APath: string): Boolean;

{ The parent directory of APath, via ExtractFileDir(ChompPathDelim(APath)).
  Stable at a root: a drive/filesystem root maps to itself (or '' for ''). }
function TyFsParent(const APath: string): string;

{ The cumulative ancestor PATHS from root to leaf -- each crumb is a real navigable
  path, not a bare label, so a look-in combo can jump straight to it:
    '/home/tom'    -> ['/', '/home', '/home/tom']
    'C:\Users\Tom' -> ['C:\', 'C:\Users', 'C:\Users\Tom']
  The drive root keeps its trailing separator ('C:\'); every other crumb has none.
  The consumer derives a display label per crumb via ExtractFileName (or shows the
  root crumb verbatim). An empty path returns an empty array. }
function TyFsBreadcrumb(const APath: string): TStringArray;

{ Resolve a name typed into a Save dialog against ADir with an optional default
  extension. If ATyped has no directory part it is expanded against ADir via
  ExpandFileNameUTF8; a path that already carries a directory is kept as typed.
  ADefaultExt (a leading dot is added if missing) is appended only when the
  resolved name has no extension. An empty ATyped returns ''. }
function TyFsResolveSaveName(const ADir, ATyped, ADefaultExt: string): string;

{ A heuristic kind label for AEntry: 'Folder' for a directory, else
  UpperCase(extension-without-dot)+' File' when there is an extension, else
  'File'. Not an OS-registered type description. }
function TyFsTypeName(const AEntry: TTyFsEntry): string;

implementation

{ Split S on Sep into its (possibly empty) segments. }
function SplitOnChar(const S: string; Sep: Char): TStringArray;
var
  i, start, n: Integer;
begin
  Result := nil;
  n := 0;
  start := 1;
  for i := 1 to Length(S) do
    if S[i] = Sep then
    begin
      SetLength(Result, n + 1);
      Result[n] := Copy(S, start, i - start);
      Inc(n);
      start := i + 1;
    end;
  { the final (or only) segment }
  SetLength(Result, n + 1);
  Result[n] := Copy(S, start, Length(S) - start + 1);
end;

function TyFsTypeName(const AEntry: TTyFsEntry): string;
var
  ext: string;
begin
  if AEntry.IsDir then
    Exit('Folder');
  ext := ExtractFileExt(AEntry.Name);
  if (ext <> '') and (ext <> '.') then
  begin
    Delete(ext, 1, 1);                { drop the leading dot }
    Result := UpperCase(ext) + ' File'
  end
  else
    Result := 'File';
end;

function TyFsMatchesFilter(const AName, APatterns: string; ACaseSens: Boolean): Boolean;
var
  pat: string;
begin
  pat := Trim(APatterns);
  if (pat = '') or (pat = '*.*') then
    pat := '*';                       { AllFilesMask }
  Result := MatchesWindowsMaskList(AName, pat, ';', ACaseSens);
end;

function TyFsMaskCaseSensitive(AValue: TTyMaskCaseSensitivity): Boolean;
begin
  case AValue of
    mcsCaseSensitive:   Result := True;
    mcsCaseInsensitive: Result := False;
  else
    { FilenamesCaseSensitive is a compile-time const in FileUtil, so this is the
      unit's second platform branch -- but a constant one, not an IFDEF. }
    Result := FilenamesCaseSensitive;
  end;
end;

function TyFsReadDirectory(const ADir, AMask: string; AOptions: TTyFsObjectTypes;
  ACaseSens: Boolean = False): TTyFsEntryArray;
var
  sr: TSearchRec;
  base: string;
  isDir, isHidden: Boolean;
  n: Integer;
  e: TTyFsEntry;
begin
  Result := nil;
  n := 0;
  base := AppendPathDelim(ADir);
  { faAnyFile enumerates everything; we filter by option/mask below. A missing
    or unreadable directory returns a non-zero code -> the empty array. }
  if FindFirstUTF8(base + '*', faAnyFile, sr) = 0 then
    try
      repeat
        if (sr.Name = '.') or (sr.Name = '..') then
          Continue;
        isDir    := (sr.Attr and faDirectory) <> 0;
        {$push}{$warn symbol_platform off}
        isHidden := (sr.Attr and faHidden) <> 0;
        {$pop}
        if isHidden and not (fotHidden in AOptions) then
          Continue;
        if isDir and not (fotFolders in AOptions) then
          Continue;
        if (not isDir) and not (fotFiles in AOptions) then
          Continue;
        { AMask applies to FILES only; directories are always shown. The case rule
          is the caller's (default False = the file-dialog convention); it used to
          be a hard-coded False, so an app that needed exact-case matching had no
          way to ask for it. }
        if (not isDir) and not TyFsMatchesFilter(sr.Name, AMask, ACaseSens) then
          Continue;

        e.Name     := sr.Name;
        e.FullPath := base + sr.Name;
        e.IsDir    := isDir;
        e.IsHidden := isHidden;
        e.Size     := sr.Size;
        { DOS-packed timestamp -> TDateTime; guard so a bogus stamp never raises. }
        try
          e.Modified := FileDateToDateTime(sr.Time);
        except
          e.Modified := 0;
        end;
        e.Attr     := sr.Attr;
        e.TypeName := TyFsTypeName(e);

        SetLength(Result, n + 1);
        Result[n] := e;
        Inc(n);
      until FindNextUTF8(sr) <> 0;
    finally
      FindCloseUTF8(sr);
    end;
end;

function TyFsParseFilter(const AFilter: string): TTyFsFilterSpecArray;
var
  parts: TStringArray;
  i, n: Integer;
  spec: TTyFsFilterSpec;
begin
  Result := nil;
  if Trim(AFilter) = '' then
    Exit;
  parts := SplitOnChar(AFilter, '|');
  n := 0;
  i := 0;
  while i < Length(parts) do
  begin
    spec.Caption := parts[i];
    if (i + 1) < Length(parts) then
      spec.Patterns := parts[i + 1]
    else
      spec.Patterns := '';            { odd trailing caption: no patterns, never crash }
    SetLength(Result, n + 1);
    Result[n] := spec;
    Inc(n);
    Inc(i, 2);
  end;
end;

function TyFsFilterPatterns(const AFilter: string; AIndex: Integer): string;
var
  specs: TTyFsFilterSpecArray;
begin
  Result := '';
  specs := TyFsParseFilter(AFilter);
  if Length(specs) = 0 then
    Exit;
  if AIndex < 1 then
    AIndex := 1;
  if AIndex > Length(specs) then
    AIndex := Length(specs);
  Result := specs[AIndex - 1].Patterns;
end;

function TyFsCompareEntries(const A, B: TTyFsEntry; AKey: TTyFsSortKey;
  AAscending, AFoldersFirst: Boolean): Integer;
var
  cmp: Integer;
begin
  { Folders before files, ALWAYS -- placement is independent of direction. }
  if AFoldersFirst and (A.IsDir <> B.IsDir) then
  begin
    if A.IsDir then
      Result := -1
    else
      Result := 1;
    Exit;
  end;

  cmp := 0;
  case AKey of
    fskName:
      cmp := CompareFilenames(A.Name, B.Name);
    fskSize:
      if A.Size < B.Size then cmp := -1
      else if A.Size > B.Size then cmp := 1
      else cmp := 0;
    fskModified:
      if A.Modified < B.Modified then cmp := -1
      else if A.Modified > B.Modified then cmp := 1
      else cmp := 0;
    fskType:
      cmp := CompareText(A.TypeName, B.TypeName);
  end;

  { Direction only flips the comparison between two comparable values. }
  if not AAscending then
    cmp := -cmp;
  Result := cmp;
end;

procedure TyFsSortEntries(var AEntries: TTyFsEntryArray; AKey: TTyFsSortKey;
  AAscending, AFoldersFirst: Boolean);
var
  tmp: TTyFsEntryArray;
  n, width, i, lo, mid, hi: Integer;

  { Stable merge of [lo,mid) and [mid,hi) into tmp, then back into AEntries. }
  procedure MergeRun(ALo, AMid, AHi: Integer);
  var
    a, b, k: Integer;
  begin
    a := ALo;
    b := AMid;
    k := ALo;
    while (a < AMid) and (b < AHi) do
    begin
      { take the left run on a tie (<= 0) to stay stable }
      if TyFsCompareEntries(AEntries[a], AEntries[b], AKey, AAscending, AFoldersFirst) <= 0 then
      begin
        tmp[k] := AEntries[a];
        Inc(a);
      end
      else
      begin
        tmp[k] := AEntries[b];
        Inc(b);
      end;
      Inc(k);
    end;
    while a < AMid do
    begin
      tmp[k] := AEntries[a];
      Inc(a);
      Inc(k);
    end;
    while b < AHi do
    begin
      tmp[k] := AEntries[b];
      Inc(b);
      Inc(k);
    end;
    for k := ALo to AHi - 1 do
      AEntries[k] := tmp[k];
  end;

begin
  n := Length(AEntries);
  if n < 2 then
    Exit;
  SetLength(tmp, n);
  width := 1;
  while width < n do
  begin
    i := 0;
    while i < n do
    begin
      lo := i;
      mid := i + width;
      if mid > n then mid := n;
      hi := i + 2 * width;
      if hi > n then hi := n;
      MergeRun(lo, mid, hi);
      Inc(i, 2 * width);
    end;
    width := width * 2;
  end;
end;

procedure TyFsSortEntriesBy(var AEntries: TTyFsEntryArray; ACompare: TTyFsCompareEvent);
var
  tmp: TTyFsEntryArray;
  n, width, i, lo, mid, hi: Integer;

  { Stable merge of [lo,mid) and [mid,hi) into tmp, then back into AEntries. }
  procedure MergeRun(ALo, AMid, AHi: Integer);
  var
    a, b, k: Integer;
  begin
    a := ALo;
    b := AMid;
    k := ALo;
    while (a < AMid) and (b < AHi) do
    begin
      { take the left run on a tie (<= 0) to stay stable }
      if ACompare(AEntries[a], AEntries[b]) <= 0 then
      begin
        tmp[k] := AEntries[a];
        Inc(a);
      end
      else
      begin
        tmp[k] := AEntries[b];
        Inc(b);
      end;
      Inc(k);
    end;
    while a < AMid do
    begin
      tmp[k] := AEntries[a];
      Inc(a);
      Inc(k);
    end;
    while b < AHi do
    begin
      tmp[k] := AEntries[b];
      Inc(b);
      Inc(k);
    end;
    for k := ALo to AHi - 1 do
      AEntries[k] := tmp[k];
  end;

begin
  if not Assigned(ACompare) then
    Exit;
  n := Length(AEntries);
  if n < 2 then
    Exit;
  SetLength(tmp, n);
  width := 1;
  while width < n do
  begin
    i := 0;
    while i < n do
    begin
      lo := i;
      mid := i + width;
      if mid > n then mid := n;
      hi := i + 2 * width;
      if hi > n then hi := n;
      MergeRun(lo, mid, hi);
      Inc(i, 2 * width);
    end;
    width := width * 2;
  end;
end;

function TyFsRoots: TTyFsRootArray;
{$IFDEF MSWINDOWS}
var
  buf: array[0..255] of AnsiChar;
  p: PAnsiChar;
  drive: string;
  n: Integer;
begin
  Result := nil;
  n := 0;
  FillChar(buf{%H-}, SizeOf(buf), 0);
  { GetLogicalDriveStrings fills a double-null-terminated list: 'C:\'#0'D:\'#0#0 }
  if GetLogicalDriveStrings(Length(buf) - 1, @buf[0]) > 0 then
  begin
    p := @buf[0];
    while p^ <> #0 do
    begin
      drive := p;                     { copies up to the null: e.g. 'C:\' }
      SetLength(Result, n + 1);
      Result[n].Path    := drive;
      Result[n].Display := ChompPathDelim(drive);   { 'C:' }
      Result[n].Kind    := rkDrive;
      Inc(n);
      Inc(p, Length(drive) + 1);      { step past this entry and its null }
    end;
  end;
  { Guarantee at least one root even if the API returned nothing. }
  if n = 0 then
  begin
    SetLength(Result, 1);
    Result[0].Path    := 'C:\';
    Result[0].Display := 'C:';
    Result[0].Kind    := rkDrive;
  end;
end;
{$ELSE}
var
  home, user: string;
  n: Integer;

  procedure AddRoot(const APath, ADisplay: string; AKind: TTyFsRootKind);
  begin
    SetLength(Result, n + 1);
    Result[n].Path    := APath;
    Result[n].Display := ADisplay;
    Result[n].Kind    := AKind;
    Inc(n);
  end;

  { Add every immediate subdirectory of ABase as an rkVolume (mounted media). }
  procedure ScanMounts(const ABase: string);
  var
    sr: TSearchRec;
    base: string;
  begin
    if not DirectoryExistsUTF8(ABase) then
      Exit;
    base := AppendPathDelim(ABase);
    if FindFirstUTF8(base + '*', faDirectory, sr) = 0 then
      try
        repeat
          if ((sr.Attr and faDirectory) <> 0) and (sr.Name <> '.') and (sr.Name <> '..') then
            AddRoot(base + sr.Name, sr.Name, rkVolume);
        until FindNextUTF8(sr) <> 0;
      finally
        FindCloseUTF8(sr);
      end;
  end;

begin
  Result := nil;
  n := 0;
  AddRoot('/', '/', rkRoot);          { the filesystem root is always present }
  home := ChompPathDelim(GetUserDir);
  if (home <> '') and DirectoryExistsUTF8(home) then
    AddRoot(home, ExtractFileName(home), rkHome);
  user := GetEnvironmentVariable('USER');
  if user <> '' then
  begin
    ScanMounts('/media/' + user);
    ScanMounts('/run/media/' + user);
  end;
  ScanMounts('/mnt');
  ScanMounts('/Volumes');             { macOS mounts }
end;
{$ENDIF}

function TyFsHasSubdir(const APath: string): Boolean;
var
  sr: TSearchRec;
  base: string;
begin
  Result := False;
  base := AppendPathDelim(APath);
  { faDirectory is a "may include" filter, not exclusive -- FindFirst still hands
    back files, so each survivor's attr is re-checked. Break on the first real
    subdirectory: this must stay cheap (it runs once per node during lazy init). }
  if FindFirstUTF8(base + '*', faDirectory, sr) = 0 then
    try
      repeat
        if ((sr.Attr and faDirectory) <> 0) and (sr.Name <> '.') and (sr.Name <> '..') then
        begin
          Result := True;
          Break;
        end;
      until FindNextUTF8(sr) <> 0;
    finally
      FindCloseUTF8(sr);
    end;
end;

function TyFsHasEntry(const APath: string; AOptions: TTyFsObjectTypes): Boolean;
var
  sr: TSearchRec;
  base: string;
  isDir, isHidden: Boolean;
begin
  Result := False;
  if AOptions * [fotFolders, fotFiles] = [] then
    Exit;                             { nothing would be kept -- do not touch disk }
  base := AppendPathDelim(APath);
  { faAnyFile then filter, same shape as TyFsReadDirectory, but breaking at the
    first survivor: this runs once per node during lazy init and must stay cheap. }
  if FindFirstUTF8(base + '*', faAnyFile, sr) = 0 then
    try
      repeat
        if (sr.Name = '.') or (sr.Name = '..') then
          Continue;
        isDir := (sr.Attr and faDirectory) <> 0;
        {$push}{$warn symbol_platform off}
        isHidden := (sr.Attr and faHidden) <> 0;
        {$pop}
        if isHidden and not (fotHidden in AOptions) then
          Continue;
        if isDir and not (fotFolders in AOptions) then
          Continue;
        if (not isDir) and not (fotFiles in AOptions) then
          Continue;
        Result := True;
        Break;
      until FindNextUTF8(sr) <> 0;
    finally
      FindCloseUTF8(sr);
    end;
end;

function TyFsParent(const APath: string): string;
begin
  Result := ExtractFileDir(ChompPathDelim(APath));
end;

function TyFsBreadcrumb(const APath: string): TStringArray;
var
  i, n: Integer;

  procedure Emit(const APart: string);
  begin
    if APart = '' then Exit;
    { Never repeat the crumb just added (e.g. a bare root, whose prefix and whole-path
      crumbs coincide). }
    if (n > 0) and (Result[n - 1] = APart) then Exit;
    SetLength(Result, n + 1);
    Result[n] := APart;
    Inc(n);
  end;

  { Normalise a cumulative prefix into a crumb. Keep the trailing separator ONLY for a
    root -- a bare '/' or a drive root 'X:\'; otherwise drop it. The input's own
    separators are preserved (never the host PathDelim), so a '/'-path yields '/' crumbs
    and a '\'-path yields '\' crumbs regardless of which OS runs this. }
  function Crumb(const APrefix: string): string;
  var
    L: Integer;
  begin
    Result := APrefix;
    L := Length(Result);
    if L = 0 then Exit;
    if (L = 1) and (Result[1] in AllowDirectorySeparators) then Exit;   { unix root '/' }
    if (L >= 2) and (Result[L] in AllowDirectorySeparators)
       and (Result[L - 1] = DriveDelim) then Exit;                      { drive root 'C:\' }
    if Result[L] in AllowDirectorySeparators then
      SetLength(Result, L - 1);                                         { strip trailing sep }
  end;

begin
  Result := nil;
  n := 0;
  if APath = '' then Exit;
  { A crumb at every separator boundary (the cumulative prefix up to and including it),
    then the whole path -- each a real navigable path, not a bare label. Crumb() applies
    the root rules; Emit() drops the duplicate a bare root produces. }
  for i := 1 to Length(APath) do
    if APath[i] in AllowDirectorySeparators then
      Emit(Crumb(Copy(APath, 1, i)));
  Emit(Crumb(APath));
end;

function TyFsResolveSaveName(const ADir, ATyped, ADefaultExt: string): string;
var
  defExt: string;
begin
  Result := '';
  if ATyped = '' then
    Exit;
  { No directory part -> resolve against ADir; otherwise keep the typed path. }
  if ExtractFilePath(ATyped) = '' then
    Result := ExpandFileNameUTF8(ATyped, ADir)
  else
    Result := ATyped;
  { Append the default extension only when none is present. }
  if (ExtractFileExt(Result) = '') and (ADefaultExt <> '') then
  begin
    defExt := ADefaultExt;
    if defExt[1] <> '.' then
      defExt := '.' + defExt;
    Result := Result + defExt;
  end;
end;

end.
