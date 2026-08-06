unit tyControls.ShellComboBox;

{ A "look in" combo: the field shows the current directory's clean label (with its
  drive/folder glyph), and the drop-down lists the directory's breadcrumb ancestor
  chain (root -> current, indented by depth, each with a glyph) followed by the other
  roots (drives / places). Picking a row navigates the host to that directory.

  Locked to csDropDownList (pick-only): an editable csDropDown popup prefix-FILTERS its
  rows, so the visible row index would no longer line up with the model array (the
  ColorBox lesson). Each row carries its 0-based model index in Items.Objects[]
  (TObject(PtrInt(i))); the picked path is read back through it.

  ICONS: a depth-0 row is always a root (drive glyph); a deeper breadcrumb row is a
  folder (folder glyph). The glyphs are fixed-palette CONTENT icons (a folder vs a
  drive), authored in a private TTyImageCollection and index-addressed through a
  TTyVirtualImageList -- same theme-exemption rationale as TTyShellTreeView /
  TTyShellListView (the ctor runs before the Controller/theme is resolved). Hierarchy is
  shown by PIXEL indentation in the row draw, not by leading spaces in the item text. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Graphics,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter,
  tyControls.ComboBox, tyControls.ListBox, tyControls.ImageCollection,
  tyControls.FileSystem;

const
  TyLookInIconSize   = 16;   { icon-list edge, px; 128px masters render down to this }
  TyLookInDriveGlyph = 0;    { a depth-0 row (a root) }
  TyLookInFolderGlyph = 1;   { a deeper breadcrumb row (a folder) }

type
  { One look-in row: a navigable Path, a friendly Display label, and its Depth in the
    breadcrumb chain (0 = a root; other roots appended after the chain are also Depth 0). }
  TTyLookInPlace = record
    Path, Display: string;
    Depth: Integer;
  end;
  TTyLookInPlaceArray = array of TTyLookInPlace;

{ The look-in rows for directory ADir: first the breadcrumb chain (TyFsBreadcrumb, one
  row per crumb, Depth 0..N), then every TyFsRoots root whose Path differs from the
  chain's own root crumb (so the current drive/root is not listed twice), each Depth 0.

  Each crumb's Display is a friendly label: the matching TyFsRoots.Display when a root's
  Path SameFileName's the crumb; else ExtractFileName(ExcludeTrailingPathDelimiter(crumb));
  else the crumb verbatim (a bare drive root 'C:\'). ADir = '' yields only the roots. }
function TyLookInPlaces(const ADir: string): TTyLookInPlaceArray;

type
  TTyShellComboBox = class(TTyComboBox)
  private
    FDirectory: string;             { current directory, trailing-separator-normalised }
    FPlaces: TTyLookInPlaceArray;   { the model behind the current Items; row <-> Objects[]=PtrInt(index) }
    FUpdating: Boolean;             { set while SetDirectory rebuilds Items, so DoSelect
                                      does not misfire OnSelectPath during the repopulate }
    FOnSelectPath: TNotifyEvent;
    FIcons: TTyImageCollection;     { owned; the 128px folder/drive BGRA masters }
    FImages: TTyVirtualImageList;   { owned; the glyph list the popup + field draw from }
    procedure SetDirectory(const AValue: string);
    procedure BuildGlyphs;
  protected
    { A row was committed by the user. Navigate to its path (rebuild + reselect) and fire
      OnSelectPath when the path actually changed. }
    procedure DoSelect; override;
    { Draw the current directory's glyph + clean label (no indentation) into the field. }
    procedure PaintFieldContent(P: TTyPainter; const ATextRect: TRect; const AStyle: TTyStyleSet); override;
    { The drop-down list draws each row's glyph + indented label. }
    function CreatePopupList: TTyListBox; override;
    { Always pick-only -- ignore any attempt to make the field editable. }
    procedure SetStyle(AValue: TTyComboBoxStyle); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { The Path of the currently-selected row (via Objects[] -> FPlaces), else FDirectory. }
    function SelectedPath: string;
    { The Depth of model row AModel (0 when out of range) -- the popup list reads it to
      pick each row's glyph + indentation. }
    function DepthOfModel(AModel: Integer): Integer;
    { The glyph index for a row at ADepth: a root (0) is a drive, deeper is a folder. }
    function GlyphForDepth(ADepth: Integer): Integer;
    { The glyph list the popup rows + the field draw from (fixed-palette folder/drive). }
    property LookInImages: TTyVirtualImageList read FImages;
  published
    { The current directory. Writing it rebuilds the drop-down and selects the current-dir
      row; fires no event. Early-exits when the new path SameFileName's the current one
      (re-entrancy guard: DoSelect -> SetDirectory -> host navigates -> host sets Directory
      back -> must not loop). }
    property Directory: string read FDirectory write SetDirectory;
    { The user picked a place -- the host navigates to SelectedPath. }
    property OnSelectPath: TNotifyEvent read FOnSelectPath write FOnSelectPath;
  end;

implementation

{ A friendly label for APath given a roots snapshot: a matching root's Display, else the
  leaf name, else the path verbatim. Shared by TyLookInPlaces and PaintFieldContent. }
function TyLookInLabelFor(const APath: string; const ARoots: TTyFsRootArray): string;
var
  i: Integer;
begin
  for i := 0 to High(ARoots) do
    if SameFileName(ARoots[i].Path, APath) then
      Exit(ARoots[i].Display);
  Result := ExtractFileName(ExcludeTrailingPathDelimiter(APath));
  if Result = '' then
    Result := APath;
end;

function TyLookInPlaces(const ADir: string): TTyLookInPlaceArray;
var
  crumbs: TStringArray;
  roots: TTyFsRootArray;
  i, n: Integer;
  firstCrumb: string;
begin
  Result := nil;
  n := 0;
  crumbs := TyFsBreadcrumb(ADir);
  roots := TyFsRoots;
  { 1. The breadcrumb chain: root -> current, Depth = position in the chain. }
  for i := 0 to High(crumbs) do
  begin
    SetLength(Result, n + 1);
    Result[n].Path := crumbs[i];
    Result[n].Display := TyLookInLabelFor(crumbs[i], roots);
    Result[n].Depth := i;
    Inc(n);
  end;
  { 2. The other roots (Path <> the chain's own root crumb), Depth 0. }
  if Length(crumbs) > 0 then
    firstCrumb := crumbs[0]
  else
    firstCrumb := '';
  for i := 0 to High(roots) do
  begin
    if (firstCrumb <> '') and SameFileName(roots[i].Path, firstCrumb) then
      Continue;
    SetLength(Result, n + 1);
    Result[n].Path := roots[i].Path;
    Result[n].Display := roots[i].Display;
    Result[n].Depth := 0;
    Inc(n);
  end;
end;

{ Draw one look-in row into ARect on P.Bitmap: the row is indented ADepth levels, then an
  optional glyph (AGlyphIndex in AImages), then the label. The field calls this with
  ADepth = 0 (no indent) but the current dir's own glyph. Mirrors TyDrawAdvancedRow. }
procedure TyDrawLookInRow(P: TTyPainter; const ARect: TRect; const AText: string;
  AGlyphIndex, ADepth: Integer; AImages: TTyVirtualImageList; const AStyle: TTyStyleSet;
  AFontSize: Integer);
var
  x, sz, rowH, pad: Integer;
  bmp: TBGRABitmap;
  textR: TRect;
begin
  pad := P.Scale(4);
  rowH := ARect.Bottom - ARect.Top;
  x := ARect.Left + pad + ADepth * P.Scale(14);   { pixel indentation per depth level }
  if (AImages <> nil) and (AGlyphIndex >= 0) and (AGlyphIndex < AImages.Count) then
  begin
    sz := rowH - P.Scale(8);
    if sz < 8 then sz := 8;
    bmp := AImages.CachedIndex(AGlyphIndex, sz);   { borrowed; do NOT free }
    if bmp <> nil then
      P.Bitmap.PutImage(x, ARect.Top + ((rowH - bmp.Height) div 2), bmp,
        dmDrawWithTransparency);
    x := x + sz + pad;
  end;
  textR := Rect(x, ARect.Top, ARect.Right - pad, ARect.Bottom);
  P.DrawText(textR, AText, AStyle.FontName, AFontSize, AStyle.FontWeight,
    AStyle.TextColor, taLeftJustify, tlCenter, True);
end;

type
  { Drop-down list for TTyShellComboBox: draws each row's glyph + indented label via the
    TTyListBox.PaintItemContent hook. Its Owner is the combo (CreatePopupList does
    Create(Self)); it reads each row's model index from its own Objects[] (copied from the
    combo via Items.Assign) and asks the combo for the depth + glyph + image list. }
  TTyShellComboPopupList = class(TTyComboPopupList)
  protected
    procedure PaintItemContent(P: TTyPainter; const ARowRect: TRect; AIndex: Integer;
      const AStyle: TTyStyleSet); override;
  end;

procedure TTyShellComboPopupList.PaintItemContent(P: TTyPainter; const ARowRect: TRect;
  AIndex: Integer; const AStyle: TTyStyleSet);
var
  combo: TTyShellComboBox;
  model, depth: Integer;
begin
  { Owner-draw first: the glyph branch below replaces the whole row, so an inherited call
    would be too late. Inert unless the combo has both an owner-draw Style and a handler. }
  if TyComboCollectRowOwnerDraw(Self, ARowRect, AIndex) then Exit;
  if Owner is TTyShellComboBox then
  begin
    combo := TTyShellComboBox(Owner);
    model := PtrInt(Items.Objects[AIndex]);
    depth := combo.DepthOfModel(model);
    TyDrawLookInRow(P, ARowRect, Items[AIndex], combo.GlyphForDepth(depth), depth,
      combo.LookInImages, AStyle, ResolveFontSize(AStyle));
  end
  else
    inherited PaintItemContent(P, ARowRect, AIndex, AStyle);
end;

{ TTyShellComboBox }

constructor TTyShellComboBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BuildGlyphs;
end;

destructor TTyShellComboBox.Destroy;
begin
  FImages.Free;
  FIcons.Free;
  inherited Destroy;
end;

{ Build a folder glyph + a drive glyph as 128px BGRA masters in a private
  TTyImageCollection, exposed index-addressed through a TTyVirtualImageList. Fixed
  palette (content icons, not theme tokens); the order matches the TyLookIn*Glyph
  constants: drive (0), folder (1). }
procedure TTyShellComboBox.BuildGlyphs;
const
  G = 128;

  function Shade(const C: TBGRAPixel; AFactor: Single): TBGRAPixel;
  begin
    Result := BGRA(Round(C.red * AFactor), Round(C.green * AFactor),
                   Round(C.blue * AFactor), C.alpha);
  end;

  procedure AddDrive(const AName: string; ABody: TBGRAPixel);
  var
    bmp: TBGRABitmap;
  begin
    bmp := TBGRABitmap.Create(G, G, BGRAPixelTransparent);
    try
      bmp.FillRoundRectAntialias(14, 40, 114, 100, 10, 10, ABody);            { chassis }
      bmp.FillRectAntialias(14, 40, 114, 66, BGRA(255, 255, 255, 30));        { top band }
      bmp.FillRoundRectAntialias(26, 78, 90, 86, 3, 3, Shade(ABody, 0.45));   { media slot }
      bmp.FillEllipseAntialias(100, 82, 5, 5, BGRA(120, 220, 140, 255));      { activity LED }
      FIcons.AddBitmap(AName, bmp);
    finally
      bmp.Free;
    end;
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

begin
  FIcons := TTyImageCollection.Create(nil);
  AddDrive('drive',   BGRA(96, 116, 150));    { steel blue  -> TyLookInDriveGlyph (0) }
  AddFolder('folder', BGRA(226, 176, 66));    { warm amber  -> TyLookInFolderGlyph (1) }

  FImages := TTyVirtualImageList.Create(nil);
  FImages.Collection := FIcons;
  FImages.Names.Text := 'drive' + LineEnding + 'folder';
end;

function TTyShellComboBox.DepthOfModel(AModel: Integer): Integer;
begin
  if (AModel >= 0) and (AModel <= High(FPlaces)) then
    Result := FPlaces[AModel].Depth
  else
    Result := 0;
end;

function TTyShellComboBox.GlyphForDepth(ADepth: Integer): Integer;
begin
  if ADepth = 0 then
    Result := TyLookInDriveGlyph
  else
    Result := TyLookInFolderGlyph;
end;

function TTyShellComboBox.SelectedPath: string;
var
  modelIdx: Integer;
begin
  if (ItemIndex >= 0) and (ItemIndex < Items.Count) then
  begin
    modelIdx := PtrInt(Items.Objects[ItemIndex]);
    if (modelIdx >= 0) and (modelIdx <= High(FPlaces)) then
      Exit(FPlaces[modelIdx].Path);
  end;
  Result := FDirectory;
end;

procedure TTyShellComboBox.SetDirectory(const AValue: string);
var
  p2: string;
  i, sel: Integer;
begin
  p2 := ExcludeTrailingPathDelimiter(Trim(AValue));
  { Re-entrancy guard: navigating back to the same directory must not rebuild + loop. }
  if SameFileName(p2, FDirectory) then
    Exit;
  FDirectory := p2;
  FUpdating := True;
  try
    FPlaces := TyLookInPlaces(p2);
    Items.Clear;
    { Plain Display -- hierarchy is drawn as pixel indentation from Depth (via Objects[]),
      not as leading spaces in the item text. }
    for i := 0 to High(FPlaces) do
      Items.AddObject(FPlaces[i].Display, TObject(PtrInt(i)));
    { Select the row whose Path is the current directory (the last breadcrumb); -1 if none. }
    sel := -1;
    for i := 0 to High(FPlaces) do
      if SameFileName(FPlaces[i].Path, FDirectory) then
      begin
        sel := i;
        Break;
      end;
    ItemIndex := sel;
  finally
    FUpdating := False;
  end;
  Invalidate;
end;

procedure TTyShellComboBox.DoSelect;
var
  modelIdx: Integer;
  picked: string;
begin
  inherited DoSelect;   { preserve base OnSelect semantics }
  if FUpdating then
    Exit;
  if (ItemIndex < 0) or (ItemIndex >= Items.Count) then
    Exit;
  modelIdx := PtrInt(Items.Objects[ItemIndex]);
  if (modelIdx < 0) or (modelIdx > High(FPlaces)) then
    Exit;
  picked := FPlaces[modelIdx].Path;
  if not SameFileName(picked, FDirectory) then
  begin
    SetDirectory(picked);   { rebuild; its own early-exit prevents a second pass }
    if Assigned(FOnSelectPath) then
      FOnSelectPath(Self);
  end;
end;

procedure TTyShellComboBox.PaintFieldContent(P: TTyPainter; const ATextRect: TRect;
  const AStyle: TTyStyleSet);
var
  lbl: string;
  depth: Integer;
begin
  if FDirectory = '' then
  begin
    inherited PaintFieldContent(P, ATextRect, AStyle);
    Exit;
  end;
  lbl := TyLookInLabelFor(FDirectory, TyFsRoots);
  { The current dir is always the last breadcrumb -> a valid selected row -> its depth
    picks the field glyph; the field itself is never indented (ADepth = 0). }
  if (ItemIndex >= 0) and (ItemIndex < Items.Count) then
    depth := DepthOfModel(PtrInt(Items.Objects[ItemIndex]))
  else
    depth := 1;   { fall back to a folder glyph }
  TyDrawLookInRow(P, ATextRect, lbl, GlyphForDepth(depth), 0, FImages, AStyle,
    ResolveFontSize(AStyle));
end;

function TTyShellComboBox.CreatePopupList: TTyListBox;
begin
  Result := TTyShellComboPopupList.Create(Self);
end;

procedure TTyShellComboBox.SetStyle(AValue: TTyComboBoxStyle);
begin
  { Pick-only, and ONLY pick-only: a FILTERED editable popup would desync the row<->place
    mapping, so the edit box is what has to go. Owner-draw is a different question and used
    to be lost with it, because this flattened every value to csDropDownList. }
  inherited SetStyle(TyComboStylePickOnly(AValue));
end;

initialization
  { So a .lfm that streams a TTyShellComboBox resolves the class. }
  RegisterClass(TTyShellComboBox);

end.
