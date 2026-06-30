unit showcasemain;
{ TTyTreeView showcase — 4 tabbed pages demonstrating:
    1. Virtual (1 000 000 nodes, multi-level lazy expansion)
    2. Columns + sort (4 columns, stable per-node data, header click sorts)
    3. Checkboxes  (tri-state folders / plain-check files / radio group)
    4. Multi-select (full-row, Ctrl/Shift/Ctrl+A, live count in status bar)

  All UI is built in code (no .lfm).  The single TTyStyleController is wired
  to every tree so all pages share the same theme.  Light/Dark toggle buttons
  call TyController.Mode directly (manual follow). }

{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Forms, Controls, Graphics, ImgList,
  tyControls.Controller, tyControls.Form, tyControls.Button,
  tyControls.TyLabel, tyControls.PageControl, tyControls.TabSheet,
  tyControls.StatusBar, tyControls.BuiltinThemes,
  tyControls.TreeView, tyControls.TreeView.Columns;

{ -----------------------------------------------------------------------
  Stable per-node data for the Columns tab (mirrors demo TColNode).
  Lives BEYOND FormCreate so event handlers can declare PRowRec locally.
  ----------------------------------------------------------------------- }
type
  { EditedName holds an in-place edit of the Name column (toEditable). It is a
    ShortString (value-type, copied/freed with the blob — no managed-field
    lifecycle), so the edit lives in the node data, NOT in Node^.Index: sort
    re-stamps Index, but the edited text follows its row. Empty ⇒ show the
    static array name.
    DEFERRED N5: this is a demo-only 63-byte cap — a rename of 64+ characters is
    truncated by the string[63] assignment (a real app would use a plain string
    field + OnFreeNode, but a managed field in a node blob needs the data lifecycle
    handled, which is out of scope for the showcase). }
  TRowRec  = record NameIdx, Kind: Integer; Size: Int64; EditedName: string[63]; end;
  PRowRec  = ^TRowRec;

type
  TShowcaseForm = class(TTyForm)
  private
    { Infrastructure }
    TyController: TTyStyleController;
    StatusBar:    TTyStatusBar;
    ChromeBar:    TTyTitleBar;
    Pages:        TTyPageControl;

    { Per-tab trees }
    VirtualTree:  TTyTreeView;   // Tab 1: Virtual
    ColTree:      TTyTreeView;   // Tab 2: Columns + sort
    CheckTree:    TTyTreeView;   // Tab 3: Checkboxes
    MultiTree:    TTyTreeView;   // Tab 4: Multi-select

    { Explorer-style row icons for the Columns tab (owned by the form) }
    FFileIcons:   TImageList;

    { Helpers }
    function  ThemeDir: string;
    procedure InitTheme;
    procedure BuildTitleBar;
    procedure BuildToolbar(AParent: TWinControl);
    procedure BuildStatusBar;
    procedure BuildPages;

    { Tab 1 — Virtual }
    procedure InitVirtualTab(APage: TTyTabSheet);
    procedure VirtualInitNode    (Sender: TTyTreeView; ParentNode, Node: PTyTreeNode;
                                  var InitStates: TTyNodeInitStates);
    procedure VirtualInitChildren(Sender: TTyTreeView; Node: PTyTreeNode;
                                  var ChildCount: Cardinal);
    procedure VirtualGetText     (Sender: TTyTreeView; Node: PTyTreeNode;
                                  var AText: string);
    procedure VirtualNodeMoved   (Sender: TTyTreeView; Node: PTyTreeNode);

    { Tab 2 — Columns + sort }
    procedure BuildFileIcons;
    procedure InitColTab(APage: TTyTabSheet);
    procedure ColInitNode    (Sender: TTyTreeView; ParentNode, Node: PTyTreeNode;
                              var InitStates: TTyNodeInitStates);
    procedure ColInitChildren(Sender: TTyTreeView; Node: PTyTreeNode;
                              var ChildCount: Cardinal);
    procedure ColGetText     (Sender: TTyTreeView; Node: PTyTreeNode;
                              Column: Integer; TextType: TTyVSTTextType;
                              var CellText: string);
    procedure ColGetImageIndex(Sender: TTyTreeView; Node: PTyTreeNode;
                              Kind: TTyVTImageKind; Column: Integer;
                              var Ghosted: Boolean; var ImageIndex: Integer);
    procedure ColCompareNodes(Sender: TTyTreeView; Node1, Node2: PTyTreeNode;
                              Column: Integer; var CompareResult: Integer);
    procedure ColNewText     (Sender: TTyTreeView; Node: PTyTreeNode;
                              Column: Integer; const NewText: string);
    procedure ColEditing     (Sender: TTyTreeView; Node: PTyTreeNode;
                              Column: Integer; var Allowed: Boolean);

    { Tab 3 — Checkboxes }
    procedure InitCheckTab(APage: TTyTabSheet);
    procedure CheckInitNode    (Sender: TTyTreeView; ParentNode, Node: PTyTreeNode;
                                var InitStates: TTyNodeInitStates);
    procedure CheckInitChildren(Sender: TTyTreeView; Node: PTyTreeNode;
                                var ChildCount: Cardinal);
    procedure CheckGetText     (Sender: TTyTreeView; Node: PTyTreeNode;
                                var AText: string);
    procedure CheckOnChecked   (Sender: TTyTreeView; Node: PTyTreeNode);

    { Tab 4 — Multi-select }
    procedure InitMultiTab(APage: TTyTabSheet);
    procedure MultiInitNode    (Sender: TTyTreeView; ParentNode, Node: PTyTreeNode;
                                var InitStates: TTyNodeInitStates);
    procedure MultiInitChildren(Sender: TTyTreeView; Node: PTyTreeNode;
                                var ChildCount: Cardinal);
    procedure MultiGetText     (Sender: TTyTreeView; Node: PTyTreeNode;
                                var AText: string);
    procedure MultiSelectionChanged(Sender: TObject);

    { Toolbar button handlers }
    procedure LightClick(Sender: TObject);
    procedure DarkClick (Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  ShowcaseForm: TShowcaseForm;

implementation

{ -----------------------------------------------------------------------
  Column-tab data tables (mirrors demo's ColTree* constants).
  4 columns: Name / Type / Size / Modified.
  3 root folders with 4-5 children each.
  ----------------------------------------------------------------------- }
const
  ColFolders: array[0..2] of string = ('Documents', 'Pictures', 'Projects');
  ColFolderDates: array[0..2] of string = ('2026-05-10', '2026-04-22', '2026-06-01');

  ColChildNames: array[0..2] of array[0..4] of string = (
    ('Report_Q1.docx',  'Budget_2026.xlsx', 'Proposal.pdf',   'Notes.txt',    'Archive.zip'),
    ('Vacation.jpg',    'Logo.png',         'Screenshot.png', 'Portrait.jpg', ''),
    ('ty-controls',     'web-app',          'scripts',        'README.md',    '')
  );
  ColChildKinds: array[0..2] of array[0..4] of string = (
    ('Document',  'Spreadsheet', 'PDF',    'Text',   'Archive'),
    ('JPEG',      'PNG',         'PNG',    'JPEG',   ''),
    ('Folder',    'Folder',      'Folder', 'Markdown','')
  );
  ColChildSizes: array[0..2] of array[0..4] of Int64 = (
    (45312, 102400, 233472, 2048, 5242880),
    (3145728, 49152, 204800, 2097152, 0),
    (0, 0, 8192, 4096, 0)
  );
  ColChildDates: array[0..2] of array[0..4] of string = (
    ('2026-05-08', '2026-04-30', '2026-05-01', '2026-06-10', '2026-03-15'),
    ('2026-01-20', '2026-05-05', '2026-06-12', '2025-12-25', ''),
    ('2026-06-28', '2026-06-15', '2026-05-20', '2026-06-27', '')
  );
  ColChildCounts: array[0..2] of Integer = (5, 4, 4);

{ -- Check-tab constants ------------------------------------------------ }
const
  CheckFolders: array[0..2] of string = ('Music', 'Videos', 'Games');
  CheckChildNames: array[0..2] of array[0..3] of string = (
    ('track01.mp3', 'track02.mp3', 'album.flac', 'cover.jpg'),
    ('intro.mp4',   'main.mkv',    'credits.mp4','thumb.png'),
    ('game_a',      'game_b',      'game_c',     'launcher.exe')
  );

{ -----------------------------------------------------------------------
  Helper: locate the themes/ directory by walking up from the exe.
  ----------------------------------------------------------------------- }
function TShowcaseForm.ThemeDir: string;
var Dir: string; i: Integer;
begin
  Dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  for i := 1 to 8 do
  begin
    if DirectoryExists(Dir + 'themes') then
      Exit(Dir + 'themes' + PathDelim);
    Dir := ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
    if Dir = '' then Break;
  end;
  Result := 'themes' + PathDelim;
end;

{ -----------------------------------------------------------------------
  Theme bootstrap
  ----------------------------------------------------------------------- }
procedure TShowcaseForm.InitTheme;
begin
  TyRegisterBuiltinThemes;
  TyController := TTyStyleController.Create(Self);
  TyController.ThemeName := 'default';
  { 'default' is a dual-mode theme; pick a mode so its @mode-only vars resolve.
    (The Light/Dark buttons flip this at runtime.) }
  TyController.Follow := tfManual;
  TyController.Mode   := 'light';
  { Wire the controller to the form so ApplyChromeTheme propagates to all
    child controls that have Controller set to the same instance. }
  Controller := TyController;
  ApplyChromeTheme(TyController);
end;

{ -----------------------------------------------------------------------
  Light / Dark toggle
  ----------------------------------------------------------------------- }
procedure TShowcaseForm.LightClick(Sender: TObject);
begin
  TyController.Follow := tfManual;
  TyController.Mode   := 'light';
  ApplyChromeTheme(TyController);
end;

procedure TShowcaseForm.DarkClick(Sender: TObject);
begin
  TyController.Follow := tfManual;
  TyController.Mode   := 'dark';
  ApplyChromeTheme(TyController);
end;

{ -----------------------------------------------------------------------
  Top toolbar: Light + Dark buttons
  ----------------------------------------------------------------------- }
procedure TShowcaseForm.BuildTitleBar;
begin
  { TTyForm is born borderless (SetupChrome sets BorderStyle=bsNone) with NO title
    bar. Associating a TTyTitleBar arms the chrome engine — drag, edge-resize, and
    the min/max/close buttons. Without it the window can't be moved, sized, or closed. }
  ChromeBar := TTyTitleBar.Create(Self);
  ChromeBar.Parent         := Self;
  ChromeBar.Align          := alTop;
  ChromeBar.Caption        := 'TTyTreeView Feature Showcase';
  ChromeBar.TitleAlignment := taCenter;
  ChromeBar.Controller     := TyController;
  TitleBar := ChromeBar;             // associate -> arms engine + wires caption buttons
  ApplyChromeTheme(TyController);     // re-theme chrome now that the bar exists
end;

{ -----------------------------------------------------------------------
  Light / Dark theme buttons — hosted inside the title bar (left side).
  ----------------------------------------------------------------------- }
procedure TShowcaseForm.BuildToolbar(AParent: TWinControl);
var
  BtnLight, BtnDark: TTyButton;
begin
  BtnLight := TTyButton.Create(Self);
  BtnLight.Parent := AParent;
  BtnLight.SetBounds(8, 4, 76, 24);
  BtnLight.Caption := 'Light';
  BtnLight.StyleClass := 'ghost';
  BtnLight.Anchors := [akLeft, akTop];
  BtnLight.OnClick := @LightClick;
  BtnLight.Controller := TyController;

  BtnDark := TTyButton.Create(Self);
  BtnDark.Parent := AParent;
  BtnDark.SetBounds(88, 4, 76, 24);
  BtnDark.Caption := 'Dark';
  BtnDark.StyleClass := 'ghost';
  BtnDark.Anchors := [akLeft, akTop];
  BtnDark.OnClick := @DarkClick;
  BtnDark.Controller := TyController;
end;

{ -----------------------------------------------------------------------
  Status bar (1 panel, bottom)
  ----------------------------------------------------------------------- }
procedure TShowcaseForm.BuildStatusBar;
var
  Panel: TTyStatusPanel;
begin
  StatusBar := TTyStatusBar.Create(Self);
  StatusBar.Parent := Self;
  StatusBar.Align := alBottom;
  StatusBar.Controller := TyController;
  Panel := StatusBar.Panels.Add;
  Panel.Width := 600;
  Panel.Text := 'Ready';
end;

{ -----------------------------------------------------------------------
  Page control + all tabs
  ----------------------------------------------------------------------- }
procedure TShowcaseForm.BuildPages;
var
  Tab1, Tab2, Tab3, Tab4: TTyTabSheet;
begin
  Pages := TTyPageControl.Create(Self);
  Pages.Parent := Self;
  Pages.Align := alClient;
  Pages.Controller := TyController;

  Tab1 := Pages.AddPage('Virtual (1M nodes)');
  Tab2 := Pages.AddPage('Columns + Sort');
  Tab3 := Pages.AddPage('Checkboxes');
  Tab4 := Pages.AddPage('Multi-Select');

  InitVirtualTab(Tab1);
  InitColTab(Tab2);
  InitCheckTab(Tab3);
  InitMultiTab(Tab4);

  Pages.ActivePageIndex := 0;
end;

{ =======================================================================
  TAB 1 — Virtual tree: 1 000 000 root nodes, 5 levels deep, 10 children
  ======================================================================= }
procedure TShowcaseForm.InitVirtualTab(APage: TTyTabSheet);
var
  Lbl: TTyLabel;
begin
  Lbl := TTyLabel.Create(Self);
  Lbl.Parent := APage;
  Lbl.Align := alTop;
  Lbl.Height := 26;
  Lbl.BorderSpacing.Left := 8;
  Lbl.Caption :=
    'Virtual engine: 1 000 000 root nodes; up to level 4 each has 10 children. ' +
    'All nodes initialised lazily (OnInitNode / OnInitChildren). ' +
    'Drag a node above / onto / below another to move it (toNodeDrag).';
  Lbl.Controller := TyController;

  VirtualTree := TTyTreeView.Create(Self);
  VirtualTree.Parent := APage;
  VirtualTree.Align := alClient;
  VirtualTree.Controller := TyController;
  { Intra-tree node drag-drop: drag a node above/onto/below another to reorder or
    reparent. The label is purely positional (Node N (LM)), so a moved node simply
    re-renders with its new index/level — no node-data write-back needed. }
  VirtualTree.Options := [toNodeDrag];

  VirtualTree.OnInitNode     := @VirtualInitNode;
  VirtualTree.OnInitChildren := @VirtualInitChildren;
  VirtualTree.OnGetText      := @VirtualGetText;
  VirtualTree.OnNodeMoved    := @VirtualNodeMoved;

  { 1 million root nodes — the virtual engine creates no child structure until
    a node is expanded; memory stays constant until the user expands nodes. }
  VirtualTree.RootNodeCount := 1000000;
end;

procedure TShowcaseForm.VirtualInitNode(Sender: TTyTreeView;
  ParentNode, Node: PTyTreeNode; var InitStates: TTyNodeInitStates);
begin
  if Sender.GetNodeLevel(Node) < 4 then
    Include(InitStates, ivsHasChildren);
end;

procedure TShowcaseForm.VirtualInitChildren(Sender: TTyTreeView;
  Node: PTyTreeNode; var ChildCount: Cardinal);
begin
  ChildCount := 10;
end;

procedure TShowcaseForm.VirtualGetText(Sender: TTyTreeView;
  Node: PTyTreeNode; var AText: string);
begin
  AText := Format('Node %d  (L%d)', [Node^.Index, Sender.GetNodeLevel(Node)]);
end;

{ Report a completed intra-tree move in the status bar. The node-data blob (none
  here — text is positional) travels with the node, so there is nothing to write
  back; we just re-read the node's current label and announce it. }
procedure TShowcaseForm.VirtualNodeMoved(Sender: TTyTreeView; Node: PTyTreeNode);
var
  s: string;
begin
  s := '';
  VirtualGetText(Sender, Node, s);
  if (StatusBar <> nil) and (StatusBar.Panels.Count > 0) then
    StatusBar.Panels[0].Text := 'Moved ' + s;
end;

{ =======================================================================
  TAB 2 — Columns + sort
  4 columns: Name / Type / Size / Modified.
  NodeDataSize = SizeOf(TRowRec); stable keys stored at OnInitNode.
  Sort via OnCompareNodes reads PRowRec(GetNodeData(Node)), NEVER Node^.Index.

  Explorer-style row icons are supplied through ColTree.Images (a TImageList)
  + the ColGetImageIndex handler — the same Images / OnGetImageIndex pair a
  real app would use.  The four 16×16 glyphs are drawn here in code (demo art):
    0 = folder   1 = generic file   2 = image file   3 = archive
  ======================================================================= }

{ Icon indices into FFileIcons — keep in sync with BuildFileIcons. }
const
  ICON_FOLDER  = 0;
  ICON_FILE    = 1;
  ICON_IMAGE   = 2;
  ICON_ARCHIVE = 3;

{ Build the 16×16 image list with four simple, theme-neutral glyphs.
  Drawing uses plain LCL TBitmap + Canvas (GDI); a clFuchsia color-key is
  punched out via AddMasked so every glyph sits on a transparent background
  and reads cleanly on both light and dark themes. }
procedure TShowcaseForm.BuildFileIcons;

  function NewGlyph: TBitmap;
  begin
    Result := TBitmap.Create;
    Result.SetSize(16, 16);
    Result.Canvas.Brush.Color := clFuchsia;   { transparency key }
    Result.Canvas.FillRect(0, 0, 16, 16);
    Result.Canvas.Pen.Style := psSolid;
    Result.Canvas.Pen.Width := 1;
  end;

  { White page with a folded top-right corner; caller draws the body lines. }
  procedure DrawPageBody(C: TCanvas);
  begin
    C.Brush.Color := clWhite;
    C.Pen.Color   := $00808080;              { mid grey outline (BGR) }
    { Page outline: x 3..12, y 1..14, with the corner folded in. }
    C.Polygon([Point(3, 1), Point(10, 1), Point(12, 3),
               Point(12, 14), Point(3, 14)]);
    { Folded corner triangle (lighter). }
    C.Brush.Color := $00D8D8D8;
    C.Polygon([Point(10, 1), Point(12, 3), Point(10, 3)]);
  end;

var
  bmp: TBitmap;
  C:   TCanvas;
begin
  FFileIcons := TImageList.Create(Self);   { Owner = form → auto-freed }
  FFileIcons.Width  := 16;
  FFileIcons.Height := 16;

  { 0 — Folder (warm amber, a darker tab lip on top). }
  bmp := NewGlyph;
  try
    C := bmp.Canvas;
    C.Brush.Color := $0033B0E8;   { warm amber body (BGR of #E8B033) }
    C.Pen.Color   := $001E84B8;   { darker amber edge }
    C.RoundRect(1, 5, 15, 14, 3, 3);
    { Back tab lip peeking over the top-left. }
    C.Brush.Color := $0055C8F0;
    C.Pen.Color   := $001E84B8;
    C.Polygon([Point(2, 5), Point(2, 3), Point(6, 3), Point(8, 5)]);
    FFileIcons.AddMasked(bmp, clFuchsia);
  finally
    bmp.Free;
  end;

  { 1 — Generic file (page + two grey text lines). }
  bmp := NewGlyph;
  try
    C := bmp.Canvas;
    DrawPageBody(C);
    C.Pen.Color := $00A0A0A0;
    C.Line(5, 6, 10, 6);
    C.Line(5, 8, 11, 8);
    C.Line(5, 10, 10, 10);
    FFileIcons.AddMasked(bmp, clFuchsia);
  finally
    bmp.Free;
  end;

  { 2 — Image file (page with a tiny sky / hill / sun thumbnail). }
  bmp := NewGlyph;
  try
    C := bmp.Canvas;
    DrawPageBody(C);
    { Sky inset. }
    C.Brush.Color := $00E8C878;   { soft blue (BGR) }
    C.Pen.Color   := $00808080;
    C.Rectangle(5, 6, 11, 12);
    { Sun. }
    C.Brush.Color := $0033CCFF;   { yellow }
    C.Pen.Color   := $0033CCFF;
    C.Ellipse(6, 6, 9, 9);
    { Green hill. }
    C.Brush.Color := $004CA04C;
    C.Pen.Color   := $004CA04C;
    C.Polygon([Point(5, 11), Point(8, 8), Point(10, 11)]);
    FFileIcons.AddMasked(bmp, clFuchsia);
  finally
    bmp.Free;
  end;

  { 3 — Archive (folder-ish box with a vertical zip + slider). }
  bmp := NewGlyph;
  try
    C := bmp.Canvas;
    C.Brush.Color := $004FA8D8;   { muted gold box }
    C.Pen.Color   := $002878A8;
    C.RoundRect(2, 3, 14, 14, 2, 2);
    { Zip teeth down the centre. }
    C.Pen.Color := $002878A8;
    C.Line(8, 3, 8, 13);
    C.Line(7, 5, 9, 5);
    C.Line(7, 7, 9, 7);
    C.Line(7, 9, 9, 9);
    { Slider tab. }
    C.Brush.Color := $00FFFFFF;
    C.Pen.Color   := $002878A8;
    C.Rectangle(7, 9, 10, 12);
    FFileIcons.AddMasked(bmp, clFuchsia);
  finally
    bmp.Free;
  end;
end;

procedure TShowcaseForm.InitColTab(APage: TTyTabSheet);
var
  Lbl: TTyLabel;
  col: TTyTreeColumn;
begin
  Lbl := TTyLabel.Create(Self);
  Lbl.Parent := APage;
  Lbl.Align := alTop;
  Lbl.Height := 26;
  Lbl.BorderSpacing.Left := 8;
  Lbl.Caption :=
    'Data lives in the node (NodeDataSize = SizeOf(TRowRec)). ' +
    'Sort reads PRowRec(GetNodeData(Node)) — never Node^.Index — so column ' +
    'sorts are always stable.  Click a column header to sort.  ' +
    'Each Name shows an Explorer-style icon (folder / file / image / archive) ' +
    'via Images + OnGetImageIndex.  Double-click / F2 a Name to edit it ' +
    '(OnNewText writes the text into the node blob, so it survives re-sorts).';
  Lbl.Controller := TyController;

  { Explorer-style row icons (drawn in code, owned by the form) }
  BuildFileIcons;

  ColTree := TTyTreeView.Create(Self);
  ColTree.Parent := APage;
  ColTree.Align := alClient;
  ColTree.Controller := TyController;

  { Allocate the per-node TRowRec blob }
  ColTree.NodeDataSize := SizeOf(TRowRec);

  { Inline-edit the Name column: double-click / F2 opens a themed editor over the
    cell; OnNewText writes the committed string into the node blob (data-in-node,
    NOT Node^.Index). }
  ColTree.Options := [toEditable];

  { Wire handlers }
  ColTree.OnInitNode      := @ColInitNode;
  ColTree.OnInitChildren  := @ColInitChildren;
  ColTree.OnGetTextWithType := @ColGetText;
  ColTree.OnCompareNodes  := @ColCompareNodes;
  ColTree.OnNewText       := @ColNewText;
  ColTree.OnEditing       := @ColEditing;   { FIX 8: only the Name column edits }

  { Per-row icons in the main (Name) column }
  ColTree.Images          := FFileIcons;
  ColTree.OnGetImageIndex := @ColGetImageIndex;

  { Build header }
  with ColTree.Header do
  begin
    Options := [hoVisible, hoColumnResize, hoShowSortGlyphs,
                hoHeaderClickAutoSort, hoDrag];

    col := Columns.Add as TTyTreeColumn;
    col.Text := 'Name';
    col.Width := 200;
    col.Alignment := taLeftJustify;

    col := Columns.Add as TTyTreeColumn;
    col.Text := 'Type';
    col.Width := 110;
    col.Alignment := taLeftJustify;

    col := Columns.Add as TTyTreeColumn;
    col.Text := 'Size';
    col.Width := 90;
    col.Alignment := taRightJustify;

    col := Columns.Add as TTyTreeColumn;
    col.Text := 'Modified';
    col.Width := 120;
    col.Alignment := taLeftJustify;

    { Set the main (tree) column AFTER the columns exist — SetMainColumn clamps to
      NoColumn(-1) when assigned while Columns.Count = 0. }
    MainColumn := 0;
  end;

  ColTree.RootNodeCount := 3;
end;

procedure TShowcaseForm.ColInitNode(Sender: TTyTreeView;
  ParentNode, Node: PTyTreeNode; var InitStates: TTyNodeInitStates);
var
  level:      Integer;
  data:       PRowRec;
  parentData: PRowRec;
begin
  level := Sender.GetNodeLevel(Node);
  data  := PRowRec(Sender.GetNodeData(Node));
  if level = 0 then
  begin
    Include(InitStates, ivsHasChildren);
    { Store stable folder index in NameIdx; Kind = -1 means "folder". }
    if data <> nil then
    begin
      data^.NameIdx := Integer(Node^.Index);
      data^.Kind    := -1;     { -1 = folder row }
      data^.Size    := 0;
    end;
  end
  else
  begin
    { File / sub-folder row: propagate folder index from parent's stored data. }
    parentData := PRowRec(Sender.GetNodeData(ParentNode));
    if data <> nil then
    begin
      if parentData <> nil then
        data^.NameIdx := parentData^.NameIdx
      else
        data^.NameIdx := Integer(ParentNode^.Index);
      data^.Kind := Integer(Node^.Index);   { child index within folder }
      if (data^.NameIdx >= 0) and (data^.NameIdx <= 2) and
         (data^.Kind >= 0) and (data^.Kind <= 4) then
        data^.Size := ColChildSizes[data^.NameIdx][data^.Kind]
      else
        data^.Size := 0;
    end;
  end;
end;

procedure TShowcaseForm.ColInitChildren(Sender: TTyTreeView;
  Node: PTyTreeNode; var ChildCount: Cardinal);
var
  data:      PRowRec;
  folderIdx: Integer;
begin
  data := PRowRec(Sender.GetNodeData(Node));
  if data <> nil then
    folderIdx := data^.NameIdx
  else
    folderIdx := Integer(Node^.Index);
  if (folderIdx >= 0) and (folderIdx <= 2) then
    ChildCount := Cardinal(ColChildCounts[folderIdx])
  else
    ChildCount := 0;
end;

procedure TShowcaseForm.ColGetText(Sender: TTyTreeView;
  Node: PTyTreeNode; Column: Integer; TextType: TTyVSTTextType;
  var CellText: string);
var
  level, fi, ci: Integer;
  data: PRowRec;
  sz:   Int64;
begin
  if TextType <> ttNormal then begin CellText := ''; Exit; end;
  data  := PRowRec(Sender.GetNodeData(Node));
  level := Sender.GetNodeLevel(Node);
  if level = 0 then
  begin
    { Folder row — read stable index from node data }
    if data <> nil then fi := data^.NameIdx
    else fi := Integer(Node^.Index);
    case Column of
      0: if (data <> nil) and (data^.EditedName <> '') then
           CellText := string(data^.EditedName)   { in-place edit wins }
         else
           CellText := ColFolders[fi];
      1: CellText := 'Folder';
      2: CellText := '';
      3: CellText := ColFolderDates[fi];
    else
      CellText := '';
    end;
  end
  else
  begin
    { File row }
    if data <> nil then begin fi := data^.NameIdx; ci := data^.Kind; end
    else begin fi := Integer(Node^.Parent^.Index); ci := Integer(Node^.Index); end;
    case Column of
      0: if (data <> nil) and (data^.EditedName <> '') then
           CellText := string(data^.EditedName)   { in-place edit wins }
         else
           CellText := ColChildNames[fi][ci];
      1: CellText := ColChildKinds[fi][ci];
      2: begin
           sz := ColChildSizes[fi][ci];
           if sz = 0 then CellText := ''
           else if sz < 1024 then CellText := Format('%d B', [sz])
           else if sz < 1048576 then CellText := Format('%d KB', [sz div 1024])
           else CellText := Format('%d MB', [sz div 1048576]);
         end;
      3: CellText := ColChildDates[fi][ci];
    else
      CellText := '';
    end;
  end;
end;

{ Explorer-style icon for the Name column.  Reads the stored TRowRec (never
  Node^.Index — Sort re-stamps Index) to pick folder / file / image / archive. }
procedure TShowcaseForm.ColGetImageIndex(Sender: TTyTreeView;
  Node: PTyTreeNode; Kind: TTyVTImageKind; Column: Integer;
  var Ghosted: Boolean; var ImageIndex: Integer);
var
  data:    PRowRec;
  fi, ci:  Integer;
  kindStr: string;
begin
  { Icons live only in the main (Name) column.  The renderer passes the main
    column index for multi-column trees (0 here) and -1 for the single-column
    case — accept both, suppress every other column. }
  if (Column > 0) then Exit;

  data := PRowRec(Sender.GetNodeData(Node));

  { Folder rows: level 0, or any child whose stored Kind text is 'Folder'. }
  if Sender.GetNodeLevel(Node) = 0 then
  begin
    ImageIndex := ICON_FOLDER;
    Exit;
  end;

  { File row — map the stored child Kind to a glyph. }
  if data <> nil then begin fi := data^.NameIdx; ci := data^.Kind; end
  else begin fi := Integer(Node^.Parent^.Index); ci := Integer(Node^.Index); end;

  kindStr := '';
  if (fi >= 0) and (fi <= 2) and (ci >= 0) and (ci <= 4) then
    kindStr := ColChildKinds[fi][ci];

  if kindStr = 'Folder' then
    ImageIndex := ICON_FOLDER
  else if (kindStr = 'JPEG') or (kindStr = 'PNG') then
    ImageIndex := ICON_IMAGE
  else if kindStr = 'Archive' then
    ImageIndex := ICON_ARCHIVE
  else
    ImageIndex := ICON_FILE;
end;

procedure TShowcaseForm.ColCompareNodes(Sender: TTyTreeView;
  Node1, Node2: PTyTreeNode; Column: Integer; var CompareResult: Integer);
var
  t1, t2:  string;
  d1, d2:  PRowRec;
  fi1, fi2, ci1, ci2: Integer;
  lv:      Integer;
begin
  lv := Sender.GetNodeLevel(Node1);
  d1 := PRowRec(Sender.GetNodeData(Node1));
  d2 := PRowRec(Sender.GetNodeData(Node2));

  if lv = 0 then
  begin
    if d1 <> nil then fi1 := d1^.NameIdx else fi1 := Integer(Node1^.Index);
    if d2 <> nil then fi2 := d2^.NameIdx else fi2 := Integer(Node2^.Index);
    case Column of
      0: CompareResult := CompareStr(ColFolders[fi1], ColFolders[fi2]);
      3: CompareResult := CompareStr(ColFolderDates[fi1], ColFolderDates[fi2]);
    else
      CompareResult := 0;
    end;
  end
  else
  begin
    if d1 <> nil then begin fi1 := d1^.NameIdx; ci1 := d1^.Kind; end
    else begin fi1 := Integer(Node1^.Parent^.Index); ci1 := Integer(Node1^.Index); end;
    if d2 <> nil then begin fi2 := d2^.NameIdx; ci2 := d2^.Kind; end
    else begin fi2 := Integer(Node2^.Parent^.Index); ci2 := Integer(Node2^.Index); end;
    case Column of
      2: begin
           { Numeric sort by raw bytes }
           if ColChildSizes[fi1][ci1] < ColChildSizes[fi2][ci2] then CompareResult := -1
           else if ColChildSizes[fi1][ci1] > ColChildSizes[fi2][ci2] then CompareResult := 1
           else CompareResult := 0;
         end;
    else
      ColGetText(Sender, Node1, Column, ttNormal, t1);
      ColGetText(Sender, Node2, Column, ttNormal, t2);
      CompareResult := CompareStr(t1, t2);
    end;
  end;
end;

{ Inline-edit commit for the Name column. The tree owns no text (it is virtual):
  write the committed string straight into the node's own blob, then invalidate
  so ColGetText re-reads it. The edit lives in TRowRec.EditedName (data-in-node),
  so it follows the row across sorts — it is NOT keyed on Node^.Index. }
procedure TShowcaseForm.ColNewText(Sender: TTyTreeView; Node: PTyTreeNode;
  Column: Integer; const NewText: string);
var
  data: PRowRec;
begin
  if Column <> 0 then Exit;   { only the Name column is editable }
  data := PRowRec(Sender.GetNodeData(Node));
  if data = nil then Exit;
  { ShortString[63] — truncates a very long entry; ample for a file/folder name. }
  data^.EditedName := ShortString(NewText);
  Sender.Invalidate;   { re-read via ColGetText (EndEditNode also repaints) }
  if (StatusBar <> nil) and (StatusBar.Panels.Count > 0) then
    StatusBar.Panels[0].Text := 'Renamed to "' + NewText + '"';
end;

{ FIX 8: gate which cells open an editor. Only the Name column (0) is writable
  (ColNewText no-ops elsewhere), so veto an edit on Kind/Size/Modified — otherwise
  the editor would open on those columns and silently discard the user's typing. }
procedure TShowcaseForm.ColEditing(Sender: TTyTreeView; Node: PTyTreeNode;
  Column: Integer; var Allowed: Boolean);
begin
  Allowed := (Column = 0);
end;

{ =======================================================================
  TAB 3 — Checkboxes
  - Level 0 folders: ctTriStateCheckBox (auto-tri-state tracking)
  - Level 1 files (folders 0+1): ctCheckBox
  - Level 1 items under folder 2 ("Games"): ctRadioButton (mutual exclusion)
  Options = [toCheckSupport, toAutoTristateTracking]
  OnChecked updates the status bar with the toggled node's name.
  ======================================================================= }
procedure TShowcaseForm.InitCheckTab(APage: TTyTabSheet);
var
  Lbl: TTyLabel;
begin
  Lbl := TTyLabel.Create(Self);
  Lbl.Parent := APage;
  Lbl.Align := alTop;
  Lbl.Height := 26;
  Lbl.BorderSpacing.Left := 8;
  Lbl.Caption :=
    'Folders: tri-state checkboxes (auto-propagate). ' +
    'Music/Videos files: plain checkboxes. ' +
    'Games entries: radio buttons (one active at a time).';
  Lbl.Controller := TyController;

  CheckTree := TTyTreeView.Create(Self);
  CheckTree.Parent := APage;
  CheckTree.Align := alClient;
  CheckTree.Controller := TyController;
  CheckTree.Options := [toCheckSupport, toAutoTristateTracking];

  CheckTree.OnInitNode     := @CheckInitNode;
  CheckTree.OnInitChildren := @CheckInitChildren;
  CheckTree.OnGetText      := @CheckGetText;
  CheckTree.OnChecked      := @CheckOnChecked;

  CheckTree.RootNodeCount := 3;
end;

procedure TShowcaseForm.CheckInitNode(Sender: TTyTreeView;
  ParentNode, Node: PTyTreeNode; var InitStates: TTyNodeInitStates);
begin
  if Sender.GetNodeLevel(Node) = 0 then
  begin
    Include(InitStates, ivsHasChildren);
    Node^.CheckType := ctTriStateCheckBox;
  end
  else
  begin
    { "Games" folder is at root index 2 — use parent's Index (stable at level 0 init) }
    if ParentNode^.Index = 2 then
      Node^.CheckType := ctRadioButton
    else
      Node^.CheckType := ctCheckBox;
  end;
end;

procedure TShowcaseForm.CheckInitChildren(Sender: TTyTreeView;
  Node: PTyTreeNode; var ChildCount: Cardinal);
begin
  ChildCount := 4;
end;

procedure TShowcaseForm.CheckGetText(Sender: TTyTreeView;
  Node: PTyTreeNode; var AText: string);
var
  fi, ci: Integer;
begin
  if Sender.GetNodeLevel(Node) = 0 then
    AText := CheckFolders[Node^.Index]
  else
  begin
    fi := Integer(Node^.Parent^.Index);
    ci := Integer(Node^.Index);
    AText := CheckChildNames[fi][ci];
  end;
end;

procedure TShowcaseForm.CheckOnChecked(Sender: TTyTreeView; Node: PTyTreeNode);
var
  NodeName: string;
begin
  NodeName := '';
  CheckGetText(Sender, Node, NodeName);
  StatusBar.Panels[0].Text := 'Checked: ' + NodeName;
end;

{ =======================================================================
  TAB 4 — Multi-select
  Options = [toMultiSelect, toFullRowSelect]
  OnSelectionChanged updates the status bar with the selected count.
  ======================================================================= }
procedure TShowcaseForm.InitMultiTab(APage: TTyTabSheet);
var
  Lbl: TTyLabel;
begin
  Lbl := TTyLabel.Create(Self);
  Lbl.Parent := APage;
  Lbl.Align := alTop;
  Lbl.Height := 26;
  Lbl.BorderSpacing.Left := 8;
  Lbl.Caption :=
    'Multi-select + full-row highlight. Ctrl+click / Shift+click / Ctrl+A. ' +
    'OnSelectionChanged shows live count in the status bar.';
  Lbl.Controller := TyController;

  MultiTree := TTyTreeView.Create(Self);
  MultiTree.Parent := APage;
  MultiTree.Align := alClient;
  MultiTree.Controller := TyController;
  MultiTree.Options := [toMultiSelect, toFullRowSelect];

  MultiTree.OnInitNode        := @MultiInitNode;
  MultiTree.OnInitChildren    := @MultiInitChildren;
  MultiTree.OnGetText         := @MultiGetText;
  MultiTree.OnSelectionChanged := @MultiSelectionChanged;

  MultiTree.RootNodeCount := 200;
end;

procedure TShowcaseForm.MultiInitNode(Sender: TTyTreeView;
  ParentNode, Node: PTyTreeNode; var InitStates: TTyNodeInitStates);
begin
  if Sender.GetNodeLevel(Node) < 3 then
    Include(InitStates, ivsHasChildren);
end;

procedure TShowcaseForm.MultiInitChildren(Sender: TTyTreeView;
  Node: PTyTreeNode; var ChildCount: Cardinal);
begin
  ChildCount := 5;
end;

procedure TShowcaseForm.MultiGetText(Sender: TTyTreeView;
  Node: PTyTreeNode; var AText: string);
begin
  AText := Format('Item %d  (level %d)', [Node^.Index, Sender.GetNodeLevel(Node)]);
end;

procedure TShowcaseForm.MultiSelectionChanged(Sender: TObject);
var n: Integer;
begin
  n := MultiTree.SelectedCount;
  if n = 0 then
    StatusBar.Panels[0].Text := 'Ready'
  else
    StatusBar.Panels[0].Text := Format('Selected: %d', [n]);
end;

{ =======================================================================
  Form constructor
  ======================================================================= }
constructor TShowcaseForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner, 0);
  Caption  := 'TTyTreeView Feature Showcase';
  Position := poScreenCenter;
  SetBounds(0, 0, 900, 650);

  { 1. Bootstrap theme controller FIRST (all controls below set Controller) }
  InitTheme;

  { 2. Title bar — TTyForm is borderless by design; the bar provides drag /
       min-max-close and arms the edge-resize engine. Theme buttons live in it. }
  BuildTitleBar;
  BuildToolbar(ChromeBar);

  { 3. Status bar }
  BuildStatusBar;

  { 4. Tabbed pages (fills remaining client area via alClient) }
  BuildPages;
end;

end.
