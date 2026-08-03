unit umain;

{ TTyListView demo.

  On the left is collection mode: a 30-row file listing, four columns, with five switchable
  view styles, click-to-sort headers, Ctrl/Shift multi-select, rubber-band selection, and
  type-to-locate. The data deliberately mixes in a few "folders" -- they have no size and no
  modified time, to demonstrate that "an unparseable cell always sorts last, regardless of
  ascending/descending": when sorting by size descending, the top should be the largest file,
  not a run of blanks.

  On the right is virtual mode: ItemCount = 100000, with not a single row object created. Text
  is generated on demand in OnGetItemText, and sorting merely permutes the internal display
  order. Switching, scrolling and sorting should all be instantaneous.

  Both sides recolour with the theme -- this control introduces no new theme tokens; the frame,
  rows and header reuse TyTreeView / TyTreeNode / TyTreeHeader respectively. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Forms, Controls, Math,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Controller, tyControls.Form, tyControls.TyLabel, tyControls.Divider,
  tyControls.Button, tyControls.CheckBox, tyControls.ComboBox, tyControls.ToggleSwitch, tyControls.Columns,
  tyControls.BuiltinThemes,
  tyControls.ImageCollection, tyControls.ListView.Layout, tyControls.ListView;

type
  TMainForm = class(TTyForm)
    Surface: TTyFormSurface;
    TitleBar1: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    ThemeCombo: TTyComboBox;

    DivLeft: TTyDivider;
    BtnReport: TTyButton;
    BtnList: TTyButton;
    BtnIcon: TTyButton;
    BtnSmallIcon: TTyButton;
    BtnTile: TTyButton;
    ChkGrid: TTyCheckBox;
    ChkMulti: TTyCheckBox;
    ChkBoxes: TTyCheckBox;
    ChkGroup: TTyCheckBox;
    LV1: TTyListView;
    LblStatus: TTyLabel;
    LblHint: TTyLabel;

    DivRight: TTyDivider;
    BtnSortVirtual: TTyButton;
    BtnJumpEnd: TTyButton;
    BtnGrow: TTyButton;
    LV2: TTyListView;
    LblVirtual: TTyLabel;
    LblVirtualNote: TTyLabel;

    DivExtras: TTyDivider;
    BtnSelectAll: TTyButton;
    BtnClearSel: TTyButton;
    ChkHeaders: TTyCheckBox;
    ChkCustomSort: TTyCheckBox;
    ChkGroupVirtual: TTyCheckBox;
    LblExtras: TTyLabel;

    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure BtnReportClick(Sender: TObject);
    procedure BtnListClick(Sender: TObject);
    procedure BtnIconClick(Sender: TObject);
    procedure BtnSmallIconClick(Sender: TObject);
    procedure BtnTileClick(Sender: TObject);
    procedure ChkGridChange(Sender: TObject);
    procedure ChkMultiChange(Sender: TObject);
    procedure ChkBoxesChange(Sender: TObject);
    procedure ChkGroupChange(Sender: TObject);
    procedure LV1SelectItem(Sender: TObject; AIndex: Integer; ASelected: Boolean);
    procedure LV1Change(Sender: TObject; AIndex: Integer; AChange: TTyItemChange);
    procedure LV1ColumnClick(Sender: TObject; AColumn: Integer);
    procedure LV1ItemActivate(Sender: TObject; AIndex: Integer);
    procedure LV2GetItemText(Sender: TObject; AIndex, AColumn: Integer; var AText: string);
    procedure LV2SelectItem(Sender: TObject; AIndex: Integer; ASelected: Boolean);
    procedure LV2GetItemState(Sender: TObject; AIndex: Integer;
      var AStates: TTyListItemStates);
    procedure LV2ItemChecked(Sender: TObject; AIndex: Integer);
    procedure LV1ItemChecked(Sender: TObject; AIndex: Integer);
    procedure LV1Edited(Sender: TObject; AIndex: Integer; var AText: string);
    procedure LV1Editing(Sender: TObject; AIndex: Integer; var AAllow: Boolean);
    procedure LV1Compare(Sender: TObject; AIndex1, AIndex2, AColumn: Integer;
      var ACompare: Integer);
    procedure LV1GroupCollapsed(Sender: TObject; AGroup: Integer);
    procedure LV2GetItemImage(Sender: TObject; AIndex, AColumn: Integer;
      var AImageIndex: Integer);
    procedure LV2GetItemGroup(Sender: TObject; AIndex: Integer; var AGroup: Integer);
    procedure BtnSortVirtualClick(Sender: TObject);
    procedure BtnJumpEndClick(Sender: TObject);
    procedure BtnGrowClick(Sender: TObject);
    procedure BtnSelectAllClick(Sender: TObject);
    procedure BtnClearSelClick(Sender: TObject);
    procedure ChkHeadersChange(Sender: TObject);
    procedure ChkCustomSortChange(Sender: TObject);
    procedure ChkGroupVirtualChange(Sender: TObject);
  private
    FIcons: TTyImageCollection;
    FImages: TTyVirtualImageList;
    { The virtual list's check state lives HERE, not in the control. OwnerData means the
      control caches nothing: it asks OnGetItemState and tells us to flip via OnItemChecked.
      Forget to flip it and the box looks stuck. }
    FVChecked: array of Boolean;
    procedure BuildIcons;
    procedure BuildColumns;
    procedure BuildGroups;
    procedure BuildRows;
    procedure BuildVirtual;
    procedure UpdateStatus;
    { Row helpers for the left list, shared by OnCompare and OnEditing. }
    function IsFolderRow(AIndex: Integer): Boolean;
    function CellText(AIndex, AColumn: Integer): string;
    { The right list's synthetic value for a row. Int64 inside, so the multiply still fits
      after "Add 50,000 rows" has pushed the count past 271,000. }
    function VirtualValue(AIndex: Integer): Integer;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

function ThemesDir: string;
var
  Dir: string;
  i: Integer;
begin
  Dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  for i := 1 to 8 do
  begin
    if DirectoryExists(Dir + 'themes') then Exit(Dir + 'themes' + PathDelim);
    Dir := ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
    if Dir = '' then Break;
  end;
  Result := 'themes' + PathDelim;
end;

{ ---------------------------------------------------------------------------
  Setup
  --------------------------------------------------------------------------- }

{ Glyphs drawn with BGRA, so the example needs no asset files.

  MASTER SIZE MATTERS. TTyImageCollection keeps ONE master per name and resamples it to
  whatever size the view asks for. The large-icon view wants 48 logical px -- 96 at 200%
  DPI -- so a 32px master gets UPSAMPLED and looks soft. Drawing the masters at 128px means
  every size the control asks for is a DOWNSAMPLE, which rmFineResample does crisply.

  AddBitmap copies, so the caller frees. }
procedure TMainForm.BuildIcons;
const
  G = 128;   { master edge, in px }

  { A slightly darker shade of the body colour, for the folder tab and the page fold. }
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
      { tab, then body over it }
      bmp.FillRoundRectAntialias(8, 20, 60, 46, 6, 6, Shade(ABody, 0.82));
      bmp.FillRoundRectAntialias(8, 34, 120, 112, 8, 8, ABody);
      { a lighter lip along the top of the body }
      bmp.FillRectAntialias(8, 34, 120, 42, BGRA(255, 255, 255, 40));
      FIcons.AddBitmap(AName, bmp);
    finally
      bmp.Free;
    end;
  end;

  { A page with a folded top-right corner, plus per-kind content. }
  procedure AddPage(const AName: string; ABody: TBGRAPixel; AKind: Integer);
  const
    L = 22; T = 8; R = 106; B = 120; Fold = 26;
  var
    bmp: TBGRABitmap;
    i, y: Integer;
  begin
    bmp := TBGRABitmap.Create(G, G, BGRAPixelTransparent);
    try
      { page body, with the folded corner cut out }
      bmp.FillPolyAntialias([PointF(L, T), PointF(R - Fold, T), PointF(R, T + Fold),
                             PointF(R, B), PointF(L, B)], ABody);
      { the fold itself }
      bmp.FillPolyAntialias([PointF(R - Fold, T), PointF(R, T + Fold),
                             PointF(R - Fold, T + Fold)], Shade(ABody, 0.72));
      case AKind of
        0:  { document: text lines }
          for i := 0 to 3 do
          begin
            y := 52 + i * 14;
            bmp.FillRectAntialias(36, y, 92 - i * 14, y + 6,
              BGRA(255, 255, 255, 200 - i * 30));
          end;
        1:  { sheet: a small grid }
          begin
            bmp.FillRectAntialias(36, 50, 92, 100, BGRA(255, 255, 255, 60));
            for i := 0 to 2 do
              bmp.FillRectAntialias(36, 50 + i * 17, 92, 52 + i * 17, BGRA(255, 255, 255, 190));
            for i := 0 to 2 do
              bmp.FillRectAntialias(36 + i * 19, 50, 38 + i * 19, 100, BGRA(255, 255, 255, 190));
          end;
      else  { image: a sun over a mountain }
        begin
          bmp.FillEllipseAntialias(50, 60, 9, 9, BGRA(255, 255, 255, 220));
          bmp.FillPolyAntialias([PointF(34, 104), PointF(60, 70), PointF(86, 104)],
            BGRA(255, 255, 255, 190));
          bmp.FillPolyAntialias([PointF(60, 104), PointF(78, 82), PointF(96, 104)],
            BGRA(255, 255, 255, 140));
        end;
      end;
      FIcons.AddBitmap(AName, bmp);
    finally
      bmp.Free;
    end;
  end;

begin
  FIcons := TTyImageCollection.Create(Self);
  AddFolder('folder',   BGRA(226, 176, 66));      // 0
  AddPage('document', BGRA(72, 128, 200), 0);     // 1
  AddPage('sheet',    BGRA(72, 160, 100), 1);     // 2
  AddPage('image',    BGRA(190, 96, 176), 2);     // 3

  FImages := TTyVirtualImageList.Create(Self);
  FImages.Collection := FIcons;
  FImages.Names.Text := 'folder' + LineEnding + 'document' + LineEnding +
                        'sheet' + LineEnding + 'image';

  { One list serves both: the collection scales (and caches) whatever size the view asks for. }
  LV1.LargeImages := FImages;
  LV1.SmallImages := FImages;
  { The virtual list uses the SAME image list. It has no row objects to carry an ImageIndex,
    so the index itself arrives from OnGetItemImage, row by row, as the rows come on screen. }
  LV2.SmallImages := FImages;
end;

procedure TMainForm.BuildColumns;
var
  c: TTyColumn;
begin
  { Columns are code-created, like examples/treeview: a TCollection streams as anonymous
    `item ... end` blocks, so hand-writing them into the .lfm buys nothing. }
  c := LV1.Header.Columns.Add as TTyColumn;
  c.Text := 'Name';  c.Width := 260;
  c := LV1.Header.Columns.Add as TTyColumn;
  c.Text := 'Size';  c.Width := 110;  c.Alignment := taRightJustify;
  c := LV1.Header.Columns.Add as TTyColumn;
  c.Text := 'Type';  c.Width := 120;
  c := LV1.Header.Columns.Add as TTyColumn;
  c.Text := 'Modified time'; c.Width := 180;

  LV1.Header.Options := LV1.Header.Options + [hoVisible, hoColumnResize,
    hoShowSortGlyphs, hoHeaderClickAutoSort, hoHotTrack];

  c := LV2.Header.Columns.Add as TTyColumn;
  c.Text := 'Row number';  c.Width := 120;  c.Alignment := taRightJustify;
  c := LV2.Header.Columns.Add as TTyColumn;
  c.Text := 'Value';    c.Width := 300;
  LV2.Header.Options := LV2.Header.Options + [hoVisible, hoColumnResize, hoShowSortGlyphs];
end;

procedure TMainForm.BuildGroups;

  procedure AddGroup(const ACaption: string);
  begin
    LV1.Groups.Add.Caption := ACaption;
  end;

begin
  { One group per kind; the index lines up with the item's ImageIndex/GroupIndex. }
  AddGroup('Folder');       // 0
  AddGroup('Text document');     // 1
  AddGroup('Spreadsheet');     // 2
  AddGroup('Image');         // 3

  { A band can start life folded: Collapsed is a plain published property of the group, so
    the list opens with "Image" already closed the first time Group is ticked. Clicking a
    band toggles it back and fires OnGroupCollapsed. }
  LV1.Groups[3].Collapsed := True;
end;

procedure TMainForm.BuildRows;

  procedure AddFile(const AName, ASize, AKind, AWhen: string; AImage: Integer);
  begin
    with LV1.Items.Add do
    begin
      Caption := AName;
      SubItems.Add(ASize);
      SubItems.Add(AKind);
      SubItems.Add(AWhen);
      ImageIndex := AImage;
      GroupIndex := AImage;   { groups are indexed to match the kind icon }
    end;
  end;

  { A folder has no size and no timestamp. Under lskNumber / lskDateTime those cells do
    not parse, and an unparseable cell sorts LAST in BOTH directions -- that is the point
    of the hint label under the list. }
  procedure AddFolder(const AName: string);
  begin
    with LV1.Items.Add do
    begin
      Caption := AName;
      SubItems.Add('');
      SubItems.Add('Folder');
      SubItems.Add('');
      ImageIndex := 0;
      GroupIndex := 0;   { folders group }
    end;
  end;

const
  Kinds: array[0..2] of string = ('Text document', 'Spreadsheet', 'Image');
var
  i: Integer;
begin
  { Every Items.Add would otherwise re-order, re-rank and re-sort the whole list. BeginUpdate
    parks that until EndUpdate, which calls ItemsChanged once -- one relayout for thirty rows
    instead of thirty. Always in a try..finally: an exception mid-load must not leave the
    control permanently frozen. }
  LV1.BeginUpdate;
  try
    AddFolder('assets');
    AddFolder('build');
    AddFolder('docs');

    AddFile('README.md',        '4096',    'Text document', '2026-07-10 08:30', 1);
    AddFile('CHANGELOG.md',     '18944',   'Text document', '2026-07-09 17:02', 1);
    AddFile('budget-2026.xlsx', '284672',  'Spreadsheet', '2026-06-28 11:45', 2);
    AddFile('logo.png',         '90112',   'Image',     '2026-05-14 09:12', 3);
    AddFile('screenshot.png',   '1638400', 'Image',     '2026-07-08 21:37', 3);
    AddFile('notes.txt',        '512',     'Text document', '2026-07-01 07:05', 1);

    for i := 1 to 21 do
      AddFile(Format('sample-%.2d.%s', [i, Copy('txtxlspng', 1 + (i mod 3) * 3, 3)]),
              IntToStr(1024 * (i * i + 7)),
              Kinds[i mod 3],
              Format('2026-%.2d-%.2d %.2d:%.2d', [1 + (i mod 12), 1 + (i mod 27),
                                                  (i * 3) mod 24, (i * 7) mod 60]),
              1 + (i mod 3));
  finally
    LV1.EndUpdate;
  end;
end;

procedure TMainForm.BuildVirtual;

  procedure AddGroup(const ACaption: string);
  begin
    LV2.Groups.Add.Caption := ACaption;
  end;

begin
  { 100,000 rows, zero row objects. The only allocation is our own check-state array. }
  LV2.OwnerData := True;
  LV2.ItemCount := 100000;
  LV2.SortKind := lskText;
  LV2.Checkboxes := True;
  SetLength(FVChecked, LV2.ItemCount);

  { Groups are NEVER virtualised -- there are only ever a handful of them, so they stay a
    real collection even here. Only the mapping is virtual: OnGetItemGroup is asked, per row,
    which band it belongs to. Bucketing by the value (not by the row number) keeps all four
    bands meaningful after "Add 50,000 rows" has changed the count. }
  AddGroup('Value 0 – 249,999');          // 0
  AddGroup('Value 250,000 – 499,999');    // 1
  AddGroup('Value 500,000 – 749,999');    // 2
  AddGroup('Value 750,000 – 999,999');    // 3
end;

procedure TMainForm.FormCreate(Sender: TObject);
var
  names: TStringArray;
  i: Integer;
begin
  { Built-in themes are compiled in, so the switcher works without locating a themes/ folder. }
  TyRegisterBuiltinThemes;
  names := TyBuiltinThemeNames;
  for i := 0 to High(names) do
    ThemeCombo.Items.Add(names[i]);
  ThemeCombo.ItemIndex := ThemeCombo.Items.IndexOf('default');
  TyDefaultController.ThemeName := 'default';

  LV1.ReadOnly := False;        { F2 renames; the default is read-only on purpose }
  LV1.OnItemChecked := @LV1ItemChecked;
  LV1.OnEdited := @LV1Edited;
  LV1.OnEditing := @LV1Editing;              { the veto half of the rename contract }
  LV1.OnGroupCollapsed := @LV1GroupCollapsed;
  LV2.OnGetItemState := @LV2GetItemState;
  LV2.OnItemChecked := @LV2ItemChecked;
  LV2.OnGetItemImage := @LV2GetItemImage;    { the only icon source OwnerData has }
  LV2.OnGetItemGroup := @LV2GetItemGroup;

  BuildIcons;
  BuildColumns;
  BuildGroups;
  BuildRows;
  BuildVirtual;
  UpdateStatus;

  ApplyChromeTheme(TyDefaultController);
end;

procedure TMainForm.ThemeComboChange(Sender: TObject);
begin
  if ThemeCombo.ItemIndex < 0 then Exit;
  TyDefaultController.ThemeName := ThemeCombo.Items[ThemeCombo.ItemIndex];
  ApplyChromeTheme(TyDefaultController);   { re-theme the shell on every skin change }
end;

procedure TMainForm.DarkSwitchChange(Sender: TObject);
begin
  // Flip the light/dark @mode axis (independent of which theme ThemeCombo picked).
  if DarkSwitch.Checked then
    TyDefaultController.Mode := 'dark'
  else
    TyDefaultController.Mode := 'light';
  ApplyChromeTheme(TyDefaultController);
end;

{ ---------------------------------------------------------------------------
  Left list — view styles, options, sorting, status
  --------------------------------------------------------------------------- }

procedure TMainForm.BtnReportClick(Sender: TObject);    begin LV1.ViewStyle := lvsReport;    end;
procedure TMainForm.BtnListClick(Sender: TObject);      begin LV1.ViewStyle := lvsList;      end;
procedure TMainForm.BtnIconClick(Sender: TObject);      begin LV1.ViewStyle := lvsIcon;      end;
procedure TMainForm.BtnSmallIconClick(Sender: TObject); begin LV1.ViewStyle := lvsSmallIcon; end;
procedure TMainForm.BtnTileClick(Sender: TObject);      begin LV1.ViewStyle := lvsTile;      end;

procedure TMainForm.ChkGridChange(Sender: TObject);
begin
  LV1.GridLines := ChkGrid.Checked;
end;

procedure TMainForm.ChkMultiChange(Sender: TObject);
begin
  LV1.MultiSelect := ChkMulti.Checked;
  UpdateStatus;
end;

procedure TMainForm.ChkBoxesChange(Sender: TObject);
begin
  LV1.Checkboxes := ChkBoxes.Checked;
end;

procedure TMainForm.ChkGroupChange(Sender: TObject);
begin
  { Items already carry a GroupIndex, so turning this on partitions them by kind.
    Click a group header to collapse/expand it -- the selection survives. }
  LV1.GroupView := ChkGroup.Checked;
end;

procedure TMainForm.LV1ItemChecked(Sender: TObject; AIndex: Integer);
begin
  { Collection mode: the control already wrote Items[AIndex].States for us. }
  UpdateStatus;
end;

procedure TMainForm.LV1Edited(Sender: TObject; AIndex: Integer; var AText: string);
begin
  { AIndex is an ITEM index and stays valid across a re-sort. Returning AText unchanged
    lets the control write it into Items[AIndex].Caption. Blank it to abandon. }
  LblStatus.Caption := Format('Renamed item index %d → %s', [AIndex, AText]);
end;

{ The two row predicates the escape-hatch events share. A "folder" row is the one whose
  Type cell (SubItems[1]) reads 'Folder'. }
function TMainForm.IsFolderRow(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex < LV1.Items.Count) and
            (LV1.Items[AIndex].SubItems.Count > 1) and
            (LV1.Items[AIndex].SubItems[1] = 'Folder');
end;

{ Column 0 is the caption, columns 1..N are SubItems -- the same mapping the control's own
  GetItemText uses, which is why a comparator can lean on it. }
function TMainForm.CellText(AIndex, AColumn: Integer): string;
begin
  Result := '';
  if (AIndex < 0) or (AIndex >= LV1.Items.Count) then Exit;
  if AColumn <= 0 then
    Result := LV1.Items[AIndex].Caption
  else if AColumn - 1 < LV1.Items[AIndex].SubItems.Count then
    Result := LV1.Items[AIndex].SubItems[AColumn - 1];
end;

procedure TMainForm.ChkCustomSortChange(Sender: TObject);
begin
  { Assigning OnCompare REPLACES the built-in comparator outright -- the control does not
    fall back to SortKind for pairs the handler ignores. Clearing it hands sorting back. }
  if ChkCustomSort.Checked then
  begin
    LV1.OnCompare := @LV1Compare;
    { A comparator has nothing to compare until a column is chosen, and the list starts
      unsorted -- so pick Name here, or ticking the box would appear to do nothing. }
    if LV1.SortColumn < 0 then
    begin
      LV1.SortColumn := 0;
      LV1.SortKind := lskText;
    end;
  end
  else
    LV1.OnCompare := nil;
  LV1.Sort;
end;

{ Custom comparator: folders first, then whatever SortKind would have done.
  Two traps live here, and both are the reason this is worth demonstrating:
    1. Because OnCompare wins outright, "leave ACompare at 0 and let SortKind decide" does
       NOT work -- 0 only means "tie", and the control breaks ties by item index. So the
       fallback leg calls TyListCompareCells, the very function the built-in path uses.
    2. The control NEGATES a user comparator's answer when SortDirection is descending
       (the built-in one bakes direction in; this one does not). The fallback leg therefore
       passes sdAscending and lets the control flip it -- while the folders-first leg
       pre-flips itself, so folders stay on top in BOTH directions. }
procedure TMainForm.LV1Compare(Sender: TObject; AIndex1, AIndex2, AColumn: Integer;
  var ACompare: Integer);
var
  f1, f2: Boolean;
begin
  f1 := IsFolderRow(AIndex1);
  f2 := IsFolderRow(AIndex2);
  if f1 <> f2 then
  begin
    if f1 then ACompare := -1 else ACompare := 1;
    if LV1.SortDirection = sdDescending then ACompare := -ACompare;
    Exit;
  end;
  ACompare := TyListCompareCells(CellText(AIndex1, AColumn), CellText(AIndex2, AColumn),
                                 LV1.SortKind, sdAscending);
end;

{ The veto half of the rename contract: BeginEdit asks BEFORE it opens the editor, so
  AAllow := False means the editor never appears at all. }
procedure TMainForm.LV1Editing(Sender: TObject; AIndex: Integer; var AAllow: Boolean);
begin
  AAllow := not IsFolderRow(AIndex);
  if not AAllow then
    LblStatus.Caption := 'OnEditing vetoed the rename — folders are not editable';
end;

{ Fires AFTER a band click flipped Collapsed and the order was rebuilt. AGroup is a GROUP
  index into Groups -- never a display position, never an item index. }
procedure TMainForm.LV1GroupCollapsed(Sender: TObject; AGroup: Integer);
var
  state: string;
begin
  if (AGroup < 0) or (AGroup >= LV1.Groups.Count) then Exit;
  if LV1.Groups[AGroup].Collapsed then state := 'collapsed' else state := 'expanded';
  LblStatus.Caption := Format('Group %d (%s) is now %s',
    [AGroup, LV1.Groups[AGroup].Caption, state]);
end;

procedure TMainForm.ChkHeadersChange(Sender: TObject);
begin
  { A report list can run headerless -- the rows reclaim the whole band. }
  LV1.ShowColumnHeaders := ChkHeaders.Checked;
end;

procedure TMainForm.BtnSelectAllClick(Sender: TObject);
begin
  { SelectAll is a deliberate no-op while MultiSelect is off: untick "Multi-select" and
    nothing happens. }
  LV1.SelectAll;
  UpdateStatus;
end;

procedure TMainForm.BtnClearSelClick(Sender: TObject);
begin
  { ClearSelection drops the multi-selection AND the focused item (ItemIndex goes to -1). }
  LV1.ClearSelection;
  UpdateStatus;
end;

procedure TMainForm.LV1ColumnClick(Sender: TObject; AColumn: Integer);
begin
  { AutoSort has already sorted once using the old SortKind; here we pick the right comparator
    for the clicked column and sort again. Size is numeric, modified time is an ISO date, the
    rest sort as text. }
  case AColumn of
    1: LV1.SortKind := lskNumber;
    3: LV1.SortKind := lskDateTime;
  else
    LV1.SortKind := lskText;
  end;
  LV1.Sort;
end;

procedure TMainForm.LV1SelectItem(Sender: TObject; AIndex: Integer; ASelected: Boolean);
begin
  { Fires for the row that gained the selection AND for every row that lost it, so the
    status line is right after a Ctrl+click removes a row too. }
  UpdateStatus;
end;

procedure TMainForm.LV1Change(Sender: TObject; AIndex: Integer; AChange: TTyItemChange);
begin
  { AIndex is the item that changed (-1 for a bulk change); AChange says whether it was
    the text, the image or the state. The status line summarises all three. }
  UpdateStatus;
end;

procedure TMainForm.LV1ItemActivate(Sender: TObject; AIndex: Integer);
begin
  { AIndex is an ITEM index and stays valid across a re-sort. }
  LblStatus.Caption := Format('Double-click opened: %s (item index = %d)',
    [LV1.Items[AIndex].Caption, AIndex]);
end;

procedure TMainForm.UpdateStatus;
var
  focus, picks: string;
  idx, shown: Integer;
begin
  if (LV1.ItemIndex >= 0) and (LV1.ItemIndex < LV1.Items.Count) then
    focus := Format('%s(item index = %d)', [LV1.Items[LV1.ItemIndex].Caption, LV1.ItemIndex])
  else
    focus := 'None';
  { The selection iterator: seed it with -1 for "before the first", then keep calling until
    it returns False. It yields ITEM indices in ascending order, whatever the sort order is,
    so the names below never scramble when a header is clicked. }
  picks := '';
  idx := -1;
  shown := 0;
  while (shown < 3) and LV1.GetNextSelected(idx) do
  begin
    if picks <> '' then picks := picks + ', ';
    picks := picks + LV1.Items[idx].Caption;
    Inc(shown);
  end;
  if picks <> '' then picks := '   ·   ' + picks;
  LblStatus.Caption := Format('Focus: %s   Selected: %d item(s)   Sort: column %d%s',
    [focus, LV1.SelCount, LV1.SortColumn, picks]);
end;

{ ---------------------------------------------------------------------------
  Right list — 100,000 rows, owner data
  --------------------------------------------------------------------------- }

function TMainForm.VirtualValue(AIndex: Integer): Integer;
begin
  { Int64 for the multiply: at 271,000 rows a plain Integer product already overflows, and
    "Add 50,000 rows" gets there in four clicks. }
  Result := Integer((Int64(AIndex) * 7919) mod 1000000);
end;

procedure TMainForm.LV2GetItemText(Sender: TObject; AIndex, AColumn: Integer;
  var AText: string);
begin
  { Called only for the rows actually on screen. AIndex is a stable item index, so a
    sort cannot make this return the wrong row's text. }
  case AColumn of
    0: AText := IntToStr(AIndex);
    1: AText := Format('Row %d · value %.6d', [AIndex, VirtualValue(AIndex)]);
  end;
end;

{ The only icon source a virtual list has: there are no row objects to hold an ImageIndex,
  so the index is produced on demand, exactly like the text, and only for the rows on
  screen. AColumn is asked for the main column alone. }
procedure TMainForm.LV2GetItemImage(Sender: TObject; AIndex, AColumn: Integer;
  var AImageIndex: Integer);
begin
  if AColumn = 0 then
    AImageIndex := AIndex mod 4;
end;

{ Grouping under OwnerData. The bands themselves are a real collection (built in
  BuildVirtual); this event is the only thing that is virtual about them -- it answers, per
  row, which band owns it. Returning a value outside 0..Groups.Count-1 drops the row into
  the implicit headerless bucket at the bottom. }
procedure TMainForm.LV2GetItemGroup(Sender: TObject; AIndex: Integer; var AGroup: Integer);
begin
  AGroup := VirtualValue(AIndex) div 250000;
end;

procedure TMainForm.LV2SelectItem(Sender: TObject; AIndex: Integer; ASelected: Boolean);
begin
  { Only the row that was CHOSEN names itself here; the abandoned one also arrives, with
    ASelected = False, and would otherwise overwrite the caption with a stale index. }
  if ASelected and (AIndex >= 0) then
    LblVirtual.Caption := Format('ItemCount = %d, row objects = 0   ·   focused item index = %d',
      [LV2.ItemCount, AIndex]);
end;

{ OwnerData: the control asks us for every row's state, and never remembers the answer. }
procedure TMainForm.LV2GetItemState(Sender: TObject; AIndex: Integer;
  var AStates: TTyListItemStates);
begin
  if (AIndex >= 0) and (AIndex < Length(FVChecked)) and FVChecked[AIndex] then
    Include(AStates, lisChecked);
end;

{ ...so the flip has to happen HERE. Skip this and the checkbox never appears to toggle:
  the control computes `not Checked[i]`, and Checked[i] is whatever LV2GetItemState says. }
procedure TMainForm.LV2ItemChecked(Sender: TObject; AIndex: Integer);
var
  i, n: Integer;
begin
  if (AIndex < 0) or (AIndex >= Length(FVChecked)) then Exit;
  FVChecked[AIndex] := not FVChecked[AIndex];
  n := 0;
  for i := 0 to High(FVChecked) do
    if FVChecked[i] then Inc(n);
  LblVirtual.Caption := Format('ItemCount = %d, row objects = 0   ·   %d item(s) checked',
    [LV2.ItemCount, n]);
end;

procedure TMainForm.BtnSortVirtualClick(Sender: TObject);
begin
  { Sorting 100k virtual rows permutes an Integer array. Nothing is allocated per row. }
  LV2.SortColumn := 1;
  if LV2.SortDirection = sdAscending then
    LV2.SortDirection := sdDescending
  else
    LV2.SortDirection := sdAscending;
  LV2.Sort;
end;

procedure TMainForm.BtnJumpEndClick(Sender: TObject);
begin
  LV2.ItemIndex := LV2.ItemCount - 1;   { focus-selects, and scrolls it into view }
  LV2.ScrollIntoView(LV2.ItemIndex);
  LV2.SetFocus;
end;

procedure TMainForm.BtnGrowClick(Sender: TObject);
var
  n: Integer;
begin
  if LV2.ItemCount >= 1000000 then
  begin
    LblVirtual.Caption := Format('ItemCount = %d — that is enough rows for one demo',
      [LV2.ItemCount]);
    Exit;
  end;
  n := LV2.ItemCount + 50000;
  { OUR store grows first: the control caches nothing and will read it on the next paint. }
  SetLength(FVChecked, n);
  LV2.ItemCount := n;
  { ItemsChanged is what an OwnerData host calls after its own store changed shape: it
    resizes the order / rank / selection arrays, clamps focus and re-applies the sort.
    Setting ItemCount already triggered it -- this is the call you need when the count did
    NOT change but the rows behind it did. }
  LV2.ItemsChanged;
  LblVirtual.Caption := Format('ItemCount = %d, row objects = 0   ·   still one relayout',
    [LV2.ItemCount]);
end;

procedure TMainForm.ChkGroupVirtualChange(Sender: TObject);
begin
  { Same GroupView switch as the left list -- only the source of each row's band differs:
    a real GroupIndex there, OnGetItemGroup here. }
  LV2.GroupView := ChkGroupVirtual.Checked;
end;

end.
