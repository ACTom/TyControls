unit tyControls.ShellListView;
{$mode objfpc}{$H+}
{ TTyShellListView -- a file-system-backed TTyListView.

  Design: docs/superpowers/specs/2026-07-11-phase7-shell-filedialogs-design.md
  Plan  : docs/superpowers/plans/2026-07-11-phase7-shelllistview.md

  This is a PURE ADAPTER. It is a TTyListView in OwnerData mode whose sole backing
  store is a TTyFsEntryArray from tyControls.FileSystem: item index == index into
  FEntries. It overrides only the five data accessors, CommitEdit (the F2-rename
  seam) and DoCompare (raw-value sort), plus the directory/mask/hidden plumbing.
  Paint, scroll, hit-test, marquee, multi-select, type-ahead, header-sort, the F2
  editor, the columns and grouping are all inherited untouched. Theming is inherited
  too (GetStyleTypeKey = 'TyListView' and the TyListView* parts): an adapter that
  draws nothing of its own must not claim a key of its own.

  THE SORTING TRAP (spec + plan both flag it): TTyListView.FSortKind is a single
  scalar shared across columns that parses the DISPLAY string, so a Size column
  showing '10 KB' would sort lexically ('1' < '9' => '10 KB' before '9 KB', WRONG).
  We therefore sort exclusively through OnCompare -> TyFsCompareEntries over the RAW
  Size:Int64 / Modified:TDateTime. See DoCompare for the one subtlety the plan's
  pseudocode omitted (the base re-applies direction to an OnCompare result). }

interface

uses
  Classes, SysUtils, Graphics, LazFileUtils,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Columns, tyControls.ImageCollection, tyControls.FileSystem,
  tyControls.ListView, tyControls.StrConsts;

const
  { The default filter: every file (directories are always shown regardless). }
  TyShellAllFilesMask = '*';
  { FoldersFirst's published default -- a compile-time constant so the `default`
    directive is visible where the property is declared (FPC gotcha). }
  TyShellFoldersFirst = True;

type
  { The kind buckets a file/folder is classified into. The ordinal doubles as the
    glyph index in the built-in image list AND as the canonical group order, so the
    two must stay in lockstep with the Names list built in BuildGlyphs. }
  TTyShellKind = (skFolder, skText, skImage, skSheet, skExecutable, skFile);

  { ===================================================================
    TTyShellListView
    =================================================================== }
  TTyShellListView = class(TTyListView)
  private
    FDirectory:    string;
    FEntries:      TTyFsEntryArray;      { the ONLY backing store; item index == subscript }
    FMask:         string;               { current file filter, default '*' }
    FObjectTypes:  TTyFsObjectTypes;     { default [fotFolders, fotFiles] }
    FFoldersFirst: Boolean;              { default True }
    FShowHidden:   Boolean;              { mirror of the fotHidden bit in FObjectTypes }
    FGroupByKind:  Boolean;
    FIcons:        TTyImageCollection;   { owned; the kind-glyph masters (freed in destructor) }
    FImages:       TTyVirtualImageList;  { owned; exposes FIcons as Small/LargeImages }
    FGroupTypes:   TStringList;   { distinct TypeName -> group index (= list position). Grouping
                                    is BY TYPE (matching the Type column), not by the coarser kind
                                    bucket that drives the glyphs -- so a .txt and a .md, which the
                                    Type column shows as different, are different groups too. }
    FOnFileActivate: TTyListItemEvent;
    FOnDirectoryChange: TNotifyEvent;

    procedure BuildColumns;
    procedure BuildGlyphs;
    { The one real directory read: fills FEntries then ItemsChanged. Self-guards the
      streaming / designer states so it never touches disk mid-stream or in the IDE. }
    procedure ReloadEntries;
    procedure RebuildKindGroups;
    procedure ShellCompare(AIndex1, AIndex2, AColumn: Integer;
      var ACompare: Integer);
    procedure ShellActivate(AIndex: Integer);
    procedure SetMask(const AValue: string);
    procedure SetShowHidden(AValue: Boolean);
    procedure SetFoldersFirst(AValue: Boolean);
    procedure SetGroupByKind(AValue: Boolean);
  protected
    { The shell's ordering and activation, as overrides of the base virtuals. }
    function  CompareItems(AItemA, AItemB: Integer): Integer; override;
    procedure DoItemActivate(AIndex: Integer); override;
    { The five inherited data accessors, all backed by FEntries -- never disk. }
    function GetItemCount: Integer; override;
    function GetItemText(AIndex, AColumn: Integer): string; override;
    function GetItemImageIndex(AIndex, AColumn: Integer): Integer; override;
    function GetItemGroup(AItemIndex: Integer): Integer; override;
    { The F2-rename seam: OwnerData's base default writes nowhere, so override it to
      rename on disk. Abandons on a blank / unchanged / path-bearing name. }
    procedure CommitEdit(AIndex: Integer; const AText: string); override;
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    { Read APath from disk into FEntries and refresh (re-sorts under AutoSort). }
    procedure LoadDirectory(const APath: string);
    { Re-read the current directory from disk.

      BREAKING: this used to be called Refresh, with `reintroduce` hiding TControl.Refresh.
      Refresh means "repaint now" (Invalidate + Update) on every other control in the LCL
      and in this library, so a shell list was the one control where a routine repaint call
      hit the filesystem -- and a caller who wanted a repaint had no way to ask for one.
      UpdateView is LCL's own name for the re-enumerate, and Refresh now means what it
      means everywhere else. }
    procedure UpdateView;
    { The focused entry's FullPath, or '' when nothing is focused. }
    function  SelectedFile: string;
    { The FullPath of the entry at ITEM index AIndex, or '' when out of range. }
    function  FileAt(AIndex: Integer): string;
    { The raw backing array, read-only -- a dialog reads the selected set from it. }
    property  Entries: TTyFsEntryArray read FEntries;
  published
    { Setting Directory reads that path from disk (LoadDirectory). }
    property Directory: string read FDirectory write LoadDirectory;
    { The file filter (';'-separated masks). Changing it re-reads. }
    property Mask: string read FMask write SetMask;
    { Whether hidden entries are enumerated (toggles the fotHidden bit + re-reads). }
    property ShowHidden: Boolean read FShowHidden write SetShowHidden default False;
    { Whether folders sort ahead of files in BOTH directions. }
    property FoldersFirst: Boolean read FFoldersFirst write SetFoldersFirst default TyShellFoldersFirst;
    { Partition the view into one collapsible band per kind present. Off by default. }
    property GroupByKind: Boolean read FGroupByKind write SetGroupByKind default False;
    { Fires on Enter / double-click over a FILE (folders navigate instead). }
    property OnFileActivate: TTyListItemEvent read FOnFileActivate write FOnFileActivate;
    { Fires after LoadDirectory (re)loads a directory -- the seam a host uses to keep a
      path box / companion tree in sync when the list navigates into a folder itself. }
    property OnDirectoryChange: TNotifyEvent read FOnDirectoryChange write FOnDirectoryChange;
  end;

{ bytes -> '512 B' / '1.2 KB' / '3.4 MB' / ... . Pure and exported: the unit words come
  from the resourcestring table, and a test that cannot call this cannot prove they are
  actually used rather than merely declared. }
function TyFormatFileSize(ABytes: Int64): string;

implementation

{ ---------------------------------------------------------------------------
  Local helpers -- size formatter + kind classification
  --------------------------------------------------------------------------- }

{ One-decimal scaled size, locale-independent (built by hand rather than via
  FormatFloat so the decimal separator is always '.'). }
function TyFmtScaled(AValue, AUnit: Int64; const ASuffix: string): string;
var
  whole, frac: Int64;
begin
  whole := AValue div AUnit;
  frac  := ((AValue mod AUnit) * 10) div AUnit;   { one decimal, truncated }
  Result := IntToStr(whole) + '.' + IntToStr(frac) + ' ' + ASuffix;
end;

{ bytes -> '512 B' / '1.2 KB' / '3.4 MB' / ... . LazFileUtils has no FormatFileSize,
  so this is the unit's tiny local formatter. }
function TyFormatFileSize(ABytes: Int64): string;
const
  KB = Int64(1024);
  MB = KB * 1024;
  GB = MB * 1024;
  TB = GB * 1024;
begin
  { The unit words are USER-FACING TEXT and were hard-coded English, so a Chinese or
    German build showed '1.2 KB' in a column of otherwise translated headers. LCL renders
    this column through LCLStrConsts for the same reason. }
  if ABytes < 0 then ABytes := 0;
  if ABytes < KB then Result := IntToStr(ABytes) + ' ' + rsTyFileSizeBytes
  else if ABytes < MB then Result := TyFmtScaled(ABytes, KB, rsTyFileSizeKB)
  else if ABytes < GB then Result := TyFmtScaled(ABytes, MB, rsTyFileSizeMB)
  else if ABytes < TB then Result := TyFmtScaled(ABytes, GB, rsTyFileSizeGB)
  else                     Result := TyFmtScaled(ABytes, TB, rsTyFileSizeTB);
end;

{ True when AExt (lowercase, no leading dot) is in AList (space-separated, lowercase). }
function TyExtInList(const AExt, AList: string): Boolean;
begin
  Result := (AExt <> '') and (Pos(' ' + AExt + ' ', ' ' + AList + ' ') > 0);
end;

const
  { Extension buckets. Deliberately modest and cross-platform; anything unmatched is
    a generic file (skFile). Scripts/binaries live under skExecutable, not skText. }
  TextExts  = 'txt md markdown log ini cfg conf xml json yaml yml csv tsv rtf tex ' +
              'pas pp inc lpr lfm dpr c h cpp hpp cc py js ts html htm css sql';
  ImageExts = 'png jpg jpeg gif bmp ico svg webp tif tiff heic';
  SheetExts = 'xls xlsx xlsm xlsb ods numbers';
  ExecExts  = 'exe msi com bat cmd ps1 sh app dll so dylib bin run';

function TyShellKindOf(const AEntry: TTyFsEntry): TTyShellKind;
var
  ext: string;
begin
  if AEntry.IsDir then Exit(skFolder);
  ext := LowerCase(ExtractFileExt(AEntry.Name));
  if (ext <> '') and (ext[1] = '.') then Delete(ext, 1, 1);
  if      TyExtInList(ext, TextExts)  then Result := skText
  else if TyExtInList(ext, ImageExts) then Result := skImage
  else if TyExtInList(ext, SheetExts) then Result := skSheet
  else if TyExtInList(ext, ExecExts)  then Result := skExecutable
  else                                     Result := skFile;
end;

{ Column index -> the raw field its sort keys on. Getting this map wrong (or dropping
  it) is the silent mis-sort the spec warns about. }
function TyColumnSortKey(AColumn: Integer): TTyFsSortKey;
begin
  case AColumn of
    1: Result := fskSize;
    2: Result := fskType;
    3: Result := fskModified;
  else
    Result := fskName;      { column 0, and any stray index }
  end;
end;

{ ---------------------------------------------------------------------------
  Lifecycle
  --------------------------------------------------------------------------- }

constructor TTyShellListView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  FMask         := TyShellAllFilesMask;
  FShowHidden   := False;
  FObjectTypes  := [fotFolders, fotFiles];
  FFoldersFirst := TyShellFoldersFirst;
  FGroupByKind  := False;
  SetLength(FEntries, 0);
  FGroupTypes := TStringList.Create;

  OwnerData := True;

  BuildColumns;
  Header.Options := [hoVisible, hoColumnResize, hoShowSortGlyphs, hoHeaderClickAutoSort];

  { Sorting and activation are OVERRIDES now (CompareItems / DoItemActivate), not handlers
    wired to the published OnCompare / OnItemActivate slots. Claiming those slots meant an
    application that assigned either one silently replaced the shell behaviour -- the list
    stopped sorting folders first, or stopped navigating on double-click -- with nothing to
    indicate the two uses were fighting over one slot. }

  BuildGlyphs;

  { Default to a name-ascending view. TyFsReadDirectory returns entries in raw FS order,
    which is not a sensible default for a file list; the plan's constructor list did not
    pin this, so we choose Name/ascending (documented as a deviation). }
  SortColumn    := 0;
  SortDirection := sdAscending;
end;

destructor TTyShellListView.Destroy;
begin
  { FImages/FIcons are created with no owner (see BuildGlyphs) so we free them. Freeing
    FImages fires its FreeNotification, which nils the inherited Small/LargeImages refs. }
  FImages.Free;
  FIcons.Free;
  FGroupTypes.Free;
  inherited Destroy;
end;

procedure TTyShellListView.BuildColumns;

  procedure AddCol(const AText: string; AWidth: Integer; AAlign: TAlignment);
  var
    c: TTyColumn;
  begin
    c := Header.Columns.Add as TTyColumn;
    c.Text      := AText;
    c.Width     := AWidth;
    c.Alignment := AAlign;
  end;

begin
  AddCol('Name',     220, taLeftJustify);
  AddCol('Size',      90, taRightJustify);
  AddCol('Type',     120, taLeftJustify);
  AddCol('Modified', 140, taLeftJustify);
end;

{ Build a small set of BGRA kind glyphs at a 128px master (downsampling stays crisp;
  see the icon-cache lesson) and expose them as the Small + Large image lists.

  THEME EXEMPTION (deliberate, documented, and consistent with examples/listview): these
  glyphs use a FIXED tasteful palette rather than theme tokens. They are CONTENT (file
  kinds), not control chrome, and the constructor runs before the Controller/theme is
  resolved -- theming them would introduce a "no theme at construct time + rebuild on
  theme change" complexity that is not worth it for what is really content. An app can
  override the whole set via SmallImages/LargeImages. }
procedure TTyShellListView.BuildGlyphs;
const
  G = 128;   { master edge, px }

  function Shade(const C: TBGRAPixel; AFactor: Single): TBGRAPixel;
  begin
    Result := BGRA(Round(C.red * AFactor), Round(C.green * AFactor),
                   Round(C.blue * AFactor), C.alpha);
  end;

  procedure AddFolder(const AName: string; ABody: TBGRAPixel);
  var
    bmp: TBGRABitmap;
  begin
    bmp := TBGRABitmap.Create(G, G, BGRAPixelTransparent);
    try
      bmp.FillRoundRectAntialias(8, 20, 60, 46, 6, 6, Shade(ABody, 0.82));   { tab }
      bmp.FillRoundRectAntialias(8, 34, 120, 112, 8, 8, ABody);             { body }
      bmp.FillRectAntialias(8, 34, 120, 42, BGRA(255, 255, 255, 40));       { top lip }
      FIcons.AddBitmap(AName, bmp);
    finally
      bmp.Free;
    end;
  end;

  { A page with a folded top-right corner; AKind selects the content overlay:
    0 blank, 1 text lines, 2 image, 3 grid, 4 executable chevron. }
  procedure AddPage(const AName: string; ABody: TBGRAPixel; AKind: Integer);
  const
    L = 22; T = 8; R = 106; B = 120; Fold = 26;
  var
    bmp: TBGRABitmap;
    i, y: Integer;
  begin
    bmp := TBGRABitmap.Create(G, G, BGRAPixelTransparent);
    try
      bmp.FillPolyAntialias([PointF(L, T), PointF(R - Fold, T), PointF(R, T + Fold),
                             PointF(R, B), PointF(L, B)], ABody);
      bmp.FillPolyAntialias([PointF(R - Fold, T), PointF(R, T + Fold),
                             PointF(R - Fold, T + Fold)], Shade(ABody, 0.72));
      case AKind of
        1:  { text: a few lines }
          for i := 0 to 3 do
          begin
            y := 52 + i * 14;
            bmp.FillRectAntialias(36, y, 92 - i * 14, y + 6,
              BGRA(255, 255, 255, 200 - i * 30));
          end;
        2:  { image: a sun over two peaks }
          begin
            bmp.FillEllipseAntialias(50, 60, 9, 9, BGRA(255, 255, 255, 220));
            bmp.FillPolyAntialias([PointF(34, 104), PointF(60, 70), PointF(86, 104)],
              BGRA(255, 255, 255, 190));
            bmp.FillPolyAntialias([PointF(60, 104), PointF(78, 82), PointF(96, 104)],
              BGRA(255, 255, 255, 140));
          end;
        3:  { sheet: a small grid }
          begin
            bmp.FillRectAntialias(36, 50, 92, 100, BGRA(255, 255, 255, 60));
            for i := 0 to 2 do
              bmp.FillRectAntialias(36, 50 + i * 17, 92, 52 + i * 17, BGRA(255, 255, 255, 190));
            for i := 0 to 2 do
              bmp.FillRectAntialias(36 + i * 19, 50, 38 + i * 19, 100, BGRA(255, 255, 255, 190));
          end;
        4:  { executable: a terminal chevron '>_' }
          begin
            bmp.FillPolyAntialias([PointF(38, 58), PointF(58, 74), PointF(38, 90),
                                   PointF(38, 82), PointF(48, 74), PointF(38, 66)],
              BGRA(255, 255, 255, 210));
            bmp.FillRectAntialias(62, 84, 88, 90, BGRA(255, 255, 255, 210));
          end;
      end;
      FIcons.AddBitmap(AName, bmp);
    finally
      bmp.Free;
    end;
  end;

begin
  FIcons := TTyImageCollection.Create(nil);
  { Order MUST match Ord(TTyShellKind): folder, text, image, sheet, exec, file. }
  AddFolder('folder', BGRA(226, 176, 66));      // 0 skFolder
  AddPage('text',  BGRA(72, 128, 200), 1);      // 1 skText
  AddPage('image', BGRA(190, 96, 176), 2);      // 2 skImage
  AddPage('sheet', BGRA(72, 160, 100), 3);      // 3 skSheet
  AddPage('exec',  BGRA(120, 128, 140), 4);     // 4 skExecutable
  AddPage('file',  BGRA(150, 156, 164), 0);     // 5 skFile (blank page)

  FImages := TTyVirtualImageList.Create(nil);
  FImages.Collection := FIcons;
  FImages.Names.Text := 'folder' + LineEnding + 'text'  + LineEnding +
                        'image'  + LineEnding + 'sheet' + LineEnding +
                        'exec'   + LineEnding + 'file';

  { One list serves both sizes: the collection scales + caches per requested size. }
  SmallImages := FImages;
  LargeImages := FImages;
end;

procedure TTyShellListView.Loaded;
begin
  inherited Loaded;
  { Do the deferred initial read now that every streamed property is in place. }
  ReloadEntries;
end;

{ ---------------------------------------------------------------------------
  Directory intake
  --------------------------------------------------------------------------- }

procedure TTyShellListView.ReloadEntries;
begin
  { Never touch disk mid-stream (properties arrive in arbitrary order -> Loaded does the
    one real read) or in the IDE designer. At runtime neither flag is set, so a code
    LoadDirectory / property write reads immediately. }
  if ComponentState * [csLoading, csDesigning] <> [] then Exit;
  FEntries := TyFsReadDirectory(FDirectory, FMask, FObjectTypes);
  { Grouped view: the set of present kinds may have changed, so rebuild the group
    collection + kind->group map BEFORE ItemsChanged rebuilds the (grouped) order. }
  if FGroupByKind then
    RebuildKindGroups;
  ItemsChanged;   { inherited: resizes order/rank/selection, re-sorts under AutoSort }
end;

procedure TTyShellListView.LoadDirectory(const APath: string);
begin
  FDirectory := APath;
  ReloadEntries;
  { Entering a directory starts with NOTHING selected. ItemsChanged only resizes the
    selection arrays, so without this the focus/selection would linger at the position
    of the just-double-clicked folder and auto-pick the same-row item in the new dir.
    (Refresh re-reads the same dir via ReloadEntries directly, so it keeps its selection.) }
  ClearSelection;
  ItemIndex := -1;
  { One sync point for consumers: fires whether the load came from a property write,
    a tree-driven LoadDirectory, or the user diving into a folder (HandleItemActivate).
    A file dialog keeps its path box / tree in step from here. }
  if Assigned(FOnDirectoryChange) then
    FOnDirectoryChange(Self);
end;

procedure TTyShellListView.UpdateView;
begin
  ReloadEntries;
end;

{ ---------------------------------------------------------------------------
  The five data accessors -- FEntries only, never disk
  --------------------------------------------------------------------------- }

function TTyShellListView.GetItemCount: Integer;
begin
  { Called every paint / scroll / sort: it MUST stay O(1) and disk-free. }
  Result := Length(FEntries);
end;

function TTyShellListView.GetItemText(AIndex, AColumn: Integer): string;
begin
  Result := '';
  if (AIndex < 0) or (AIndex > High(FEntries)) then Exit;
  case AColumn of
    0: Result := FEntries[AIndex].Name;
    1: if not FEntries[AIndex].IsDir then
         Result := TyFormatFileSize(FEntries[AIndex].Size);   { folders have no size }
    2: Result := FEntries[AIndex].TypeName;
    3: if FEntries[AIndex].Modified <> 0 then
         Result := FormatDateTime('yyyy-mm-dd hh:nn', FEntries[AIndex].Modified);
  end;
end;

function TTyShellListView.GetItemImageIndex(AIndex, AColumn: Integer): Integer;
begin
  { The kind glyph lives in the main column only; other columns carry no icon. }
  if AColumn > 0 then Exit(-1);
  if (AIndex < 0) or (AIndex > High(FEntries)) then Exit(-1);
  Result := Ord(TyShellKindOf(FEntries[AIndex]));
end;

function TTyShellListView.GetItemGroup(AItemIndex: Integer): Integer;
begin
  { Only consulted while GroupByKind is on; returns the group index of this entry's TYPE
    (its Type-column value), or -1 for the implicit bucket if the type has no group. }
  Result := -1;
  if not FGroupByKind then Exit;
  if (AItemIndex < 0) or (AItemIndex > High(FEntries)) then Exit;
  { The group of an entry is its Type-column value, looked up in the rebuilt group list. }
  Result := FGroupTypes.IndexOf(FEntries[AItemIndex].TypeName);
end;

{ ---------------------------------------------------------------------------
  F2 rename -> RenameFileUTF8
  --------------------------------------------------------------------------- }

procedure TTyShellListView.CommitEdit(AIndex: Integer; const AText: string);
var
  newPath: string;
begin
  { OwnerData's base default writes nowhere; this is where a rename actually lands.
    (It renames on disk directly and does not route through OnEdited.) }
  if (AIndex < 0) or (AIndex > High(FEntries)) then Exit;
  if AText = '' then Exit;                             { blank -> abandon }
  if AText = FEntries[AIndex].Name then Exit;          { unchanged (case-sensitive, so a
                                                         case-only rename is allowed) }
  { A rename must stay a leaf name: reject anything carrying a path separator (it would
    move the file, or escape the directory). RenameFileUTF8 handles other illegal chars
    by failing, in which case we simply do not refresh. }
  if (Pos('/', AText) > 0) or (Pos('\', AText) > 0) then Exit;
  newPath := AppendPathDelim(FDirectory) + AText;
  if RenameFileUTF8(FEntries[AIndex].FullPath, newPath) then
    Refresh;   { re-read; the row may move under the active sort }
end;

{ ---------------------------------------------------------------------------
  Sort -- RAW values through TyFsCompareEntries
  --------------------------------------------------------------------------- }

{ Sort on the RAW values, never the display strings (the whole point of the adapter). }
function TTyShellListView.CompareItems(AItemA, AItemB: Integer): Integer;
begin
  { An application handler wins: it is the caller's ordering, and the whole point of
    taking the event slot back from the constructor was that the app owns it. Without
    this the slot was published, assignable, and unreachable -- the exact defect the
    override was meant to remove, reintroduced one level down. }
  if Assigned(OnCompare) then
    Exit(inherited CompareItems(AItemA, AItemB));
  Result := 0;
  ShellCompare(AItemA, AItemB, SortColumn, Result);
  { The base's stable tie-break, which an override replaces and therefore has to redo:
    equal keys must fall back to item index or the merge sort is not stable and two
    same-named entries can swap places between sorts. }
  if Result = 0 then
    Result := AItemA - AItemB;
end;

{ A folder navigates; a file fires OnFileActivate. inherited last, so an application that
  also wants the raw OnItemActivate still gets it. }
procedure TTyShellListView.DoItemActivate(AIndex: Integer);
begin
  ShellActivate(AIndex);
  inherited DoItemActivate(AIndex);
end;

procedure TTyShellListView.ShellCompare(AIndex1, AIndex2,
  AColumn: Integer; var ACompare: Integer);
var
  asc: Boolean;
begin
  if (AIndex1 < 0) or (AIndex1 > High(FEntries)) or
     (AIndex2 < 0) or (AIndex2 > High(FEntries)) then
  begin
    ACompare := 0;
    Exit;
  end;
  asc := SortDirection = sdAscending;
  { TyFsCompareEntries already applies folders-first (immune to direction) AND the
    direction itself. }
  ACompare := TyFsCompareEntries(FEntries[AIndex1], FEntries[AIndex2],
                TyColumnSortKey(AColumn), asc, FFoldersFirst);
  { There used to be a pre-negation here, cancelling a flip the base applied to any
    OnCompare result on the assumption that a user handler is direction-agnostic. Ours is
    not -- TyFsCompareEntries honours the direction itself and its folders-first placement
    has to survive it. Now that this is reached through a CompareItems OVERRIDE there is no
    base flip to cancel, so the cancellation is gone with it. Leaving it in double-flipped
    descending: folders fell to the bottom and files came out ascending. }
end;

{ ---------------------------------------------------------------------------
  Activation -- folder navigates, file fires OnFileActivate
  --------------------------------------------------------------------------- }

procedure TTyShellListView.ShellActivate(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex > High(FEntries)) then Exit;
  if FEntries[AIndex].IsDir then
    LoadDirectory(FEntries[AIndex].FullPath)
  else if Assigned(FOnFileActivate) then
    FOnFileActivate(Self, AIndex);
end;

{ ---------------------------------------------------------------------------
  Grouping by kind
  --------------------------------------------------------------------------- }

{ Rebuild the inherited Groups collection to one band per kind PRESENT in FEntries (in
  canonical kind order) and record the kind->group-index map GetItemGroup reads. }
procedure TTyShellListView.RebuildKindGroups;
var
  i, gi: Integer;
  fileTypes: TStringList;
  folderLabel: string;
begin
  { Groups are BY TYPE (the Type column's value), not by the coarse kind bucket that drives
    the glyphs: a .txt and a .md are shown as different types, so they group separately.
    Folders share one 'Folder' group, placed first; the remaining file types follow in
    alphabetical order so the group order is stable across re-sorts. }
  FGroupTypes.Clear;
  folderLabel := '';
  fileTypes := TStringList.Create;
  try
    fileTypes.Sorted := True;
    fileTypes.Duplicates := dupIgnore;
    for i := 0 to High(FEntries) do
      if FEntries[i].IsDir then
        folderLabel := FEntries[i].TypeName   { the shared 'Folder' label }
      else
        fileTypes.Add(FEntries[i].TypeName);

    if folderLabel <> '' then
      FGroupTypes.Add(folderLabel);           { group 0 }
    for i := 0 to fileTypes.Count - 1 do
      FGroupTypes.Add(fileTypes[i]);
  finally
    fileTypes.Free;
  end;

  Groups.Clear;
  for gi := 0 to FGroupTypes.Count - 1 do
    Groups.Add.Caption := FGroupTypes[gi];
end;

{ ---------------------------------------------------------------------------
  Public queries
  --------------------------------------------------------------------------- }

function TTyShellListView.SelectedFile: string;
begin
  Result := FileAt(ItemIndex);
end;

function TTyShellListView.FileAt(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex <= High(FEntries)) then
    Result := FEntries[AIndex].FullPath
  else
    Result := '';
end;

{ ---------------------------------------------------------------------------
  Setters
  --------------------------------------------------------------------------- }

procedure TTyShellListView.SetMask(const AValue: string);
begin
  if FMask = AValue then Exit;
  FMask := AValue;
  ReloadEntries;
end;

procedure TTyShellListView.SetShowHidden(AValue: Boolean);
begin
  if FShowHidden = AValue then Exit;
  FShowHidden := AValue;
  if AValue then
    Include(FObjectTypes, fotHidden)
  else
    Exclude(FObjectTypes, fotHidden);
  ReloadEntries;
end;

procedure TTyShellListView.SetFoldersFirst(AValue: Boolean);
begin
  if FFoldersFirst = AValue then Exit;
  FFoldersFirst := AValue;
  { Folders-first is applied inside the comparator, so a re-sort is enough (FEntries is
    unchanged). Falls back to a repaint when no sort column is active. }
  if SortColumn >= 0 then Sort else Invalidate;
end;

procedure TTyShellListView.SetGroupByKind(AValue: Boolean);
begin
  if FGroupByKind = AValue then Exit;
  FGroupByKind := AValue;
  if AValue then
  begin
    { Populate Groups + the kind map BEFORE enabling grouped layout: GroupView's setter
      immediately rebuilds the grouped order, which reads both. }
    RebuildKindGroups;
    GroupView := True;
  end
  else
  begin
    GroupView := False;
    Groups.Clear;
  end;
end;

initialization
  { So a .lfm that streams a TTyShellListView resolves the class. Header/Columns already
    register themselves in tyControls.Columns. }
  RegisterClass(TTyShellListView);

end.
