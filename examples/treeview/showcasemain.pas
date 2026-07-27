unit showcasemain;
{ TTyTreeView showcase — 5 tabbed pages demonstrating:
    1. Virtual (1 000 000 nodes, multi-level lazy expansion)
    2. Columns + sort (4 columns, stable per-node data, header click sorts)
    3. Checkboxes  (tri-state folders / plain-check files / radio group)
    4. Multi-select (full-row, Ctrl/Shift/Ctrl+A, live count in status bar)
    5. Drag to move (small, reparent-safe, toNodeDrag)

  The window, the title bar (with the Light / Dark buttons + the built-in-theme
  switcher), the page control, its five pages, the per-tab description labels, the
  five trees and the status bar are all DESIGNED in showcasemain.lfm (a TTyForm +
  TTyTitleBar).  The code here is theme setup + event handlers + the tree
  configuration (columns / options / images / node-data population) that is NOT a
  simple published property, exactly as before — it just now operates on the
  streamed controls instead of creating them.

  Skin switching: the Light / Dark buttons flip TyDefaultController.Mode; the
  ThemeCombo swaps TyDefaultController.ThemeName.  All three drive the SAME
  controller (the global TyDefaultController) so every page stays in sync. }

{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Math, Forms, Controls, Graphics, ImgList,
  tyControls.Controller, tyControls.Form, tyControls.Button,
  tyControls.TyLabel, tyControls.PageControl, tyControls.TabSheet,
  tyControls.StatusBar, tyControls.ComboBox, tyControls.BuiltinThemes,
  tyControls.Panel, tyControls.CheckBox, tyControls.TrackBar,
  tyControls.TreeView, tyControls.Columns,
  tyControls.Types, tyControls.StyleModel;

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
    { Streamed from showcasemain.lfm }
    Surface:     TTyFormSurface;
    ChromeBar:   TTyTitleBar;
    BtnLight:    TTyButton;
    BtnDark:     TTyButton;
    ThemeCombo:  TTyComboBox;
    Pages:       TTyPageControl;
    PgVirtual:   TTyTabSheet;
    LblVirtual:  TTyLabel;
    VirtualBar:  TTyPanel;
    BtnGoToNode: TTyButton;
    VirtualTree: TTyTreeView;   // Tab 1: Virtual
    PgCol:       TTyTabSheet;
    LblCol:      TTyLabel;
    ColBar:         TTyPanel;
    BtnExpandAll:   TTyButton;
    BtnCollapseAll: TTyButton;
    ColTree:     TTyTreeView;   // Tab 2: Columns + sort
    PgCheck:     TTyTabSheet;
    LblCheck:    TTyLabel;
    CheckTree:   TTyTreeView;   // Tab 3: Checkboxes
    PgMulti:     TTyTabSheet;
    LblMulti:    TTyLabel;
    MultiBar:    TTyPanel;
    ChkButtons:  TTyCheckBox;
    ChkLines:    TTyCheckBox;
    ChkRoot:     TTyCheckBox;
    LblIndent:   TTyLabel;
    TrkIndent:   TTyTrackBar;
    MultiTree:   TTyTreeView;   // Tab 4: Multi-select
    PgDrag:      TTyTabSheet;
    LblDrag:     TTyLabel;
    DragBar:        TTyPanel;
    BtnDragDelete:  TTyButton;
    BtnDragClear:   TTyButton;
    BtnDragRebuild: TTyButton;
    DragTree:    TTyTreeView;   // Tab 5: Drag to move
    PgOwnerDraw: TTyTabSheet;
    LblDraw:     TTyLabel;
    DrawTree:    TTyTreeView;   // Tab 6: Owner-draw
    StatusBar:   TTyStatusBar;
    { .lfm-bound handlers (must stay published) }
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure LightClick(Sender: TObject);
    procedure DarkClick (Sender: TObject);
    { .lfm-bound button / strip handlers (public API + display-property demos) }
    procedure BtnGoToNodeClick   (Sender: TObject);
    procedure BtnExpandAllClick  (Sender: TObject);
    procedure BtnCollapseAllClick(Sender: TObject);
    procedure MultiLookChange    (Sender: TObject);
    procedure TrkIndentChange    (Sender: TObject);
    procedure BtnDragDeleteClick (Sender: TObject);
    procedure BtnDragClearClick  (Sender: TObject);
    procedure BtnDragRebuildClick(Sender: TObject);
    { .lfm-bound Tab 6 (Owner-draw) tree handlers }
    procedure DrawInitNode    (Sender: TTyTreeView; ParentNode, Node: PTyTreeNode;
                               var InitStates: TTyNodeInitStates);
    procedure DrawInitChildren(Sender: TTyTreeView; Node: PTyTreeNode;
                               var ChildCount: Cardinal);
    procedure DrawGetText     (Sender: TTyTreeView; Node: PTyTreeNode;
                               var AText: string);
    procedure DrawMeasureItem (Sender: TTyTreeView; ACanvas: TCanvas;
                               Node: PTyTreeNode; var ANodeHeight: Integer);
    procedure DrawDrawNode    (Sender: TTyTreeView; ACanvas: TCanvas;
                               Node: PTyTreeNode; Column: Integer;
                               const ACellRect: TRect);
    procedure DrawAfterCellPaint(Sender: TTyTreeView; ACanvas: TCanvas;
                               Node: PTyTreeNode; Column: Integer;
                               const ACellRect: TRect);
    procedure DrawChange      (Sender: TTyTreeView; Node: PTyTreeNode);
  private
    { Explorer-style row icons for the Columns tab (owned by the form) }
    FFileIcons:   TImageList;
    { Running total of nodes released through DragTree.OnFreeNode. }
    FFreedNodes:  Integer;

    { Per-tab tree configuration (kept in code — columns / options / images /
      node-data population are not simple published properties). }
    procedure InitVirtualTab;
    procedure InitColTab;
    procedure BuildFileIcons;
    procedure InitCheckTab;
    procedure InitMultiTab;
    procedure InitDragTab;
    procedure BuildDragNodes;

    { Status-bar helpers: panel 0 carries the running commentary, panel 1 the
      focused row (so OnFocusChanged and OnSelectionChanged don't overwrite
      each other). }
    procedure SetStatus   (const AText: string);
    procedure SetFocusInfo(const AText: string);

    { Tab 1 — Virtual }
    procedure VirtualInitNode    (Sender: TTyTreeView; ParentNode, Node: PTyTreeNode;
                                  var InitStates: TTyNodeInitStates);
    procedure VirtualInitChildren(Sender: TTyTreeView; Node: PTyTreeNode;
                                  var ChildCount: Cardinal);
    procedure VirtualGetText     (Sender: TTyTreeView; Node: PTyTreeNode;
                                  var AText: string);
    procedure VirtualExpanding   (Sender: TTyTreeView; Node: PTyTreeNode;
                                  var Allowed: Boolean);
    procedure VirtualExpanded    (Sender: TTyTreeView; Node: PTyTreeNode);
    procedure VirtualCollapsed   (Sender: TTyTreeView; Node: PTyTreeNode);
    procedure VirtualNodeClick   (Sender: TTyTreeView; Node: PTyTreeNode);
    procedure VirtualNodeDblClick(Sender: TTyTreeView; Node: PTyTreeNode);

    { Tab 2 — Columns + sort }
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
    procedure ColEditCancelled(Sender: TTyTreeView; Node: PTyTreeNode;
                              Column: Integer);
    procedure ColHeaderClick (Sender: TTyTreeView; Column: Integer);
    procedure ColColumnResized(Sender: TTyTreeView; Column: Integer);
    procedure ColColumnReorder(Sender: TTyTreeView;
                              OldPosition, NewPosition: Integer);

    { Tab 3 — Checkboxes }
    procedure CheckInitNode    (Sender: TTyTreeView; ParentNode, Node: PTyTreeNode;
                                var InitStates: TTyNodeInitStates);
    procedure CheckInitChildren(Sender: TTyTreeView; Node: PTyTreeNode;
                                var ChildCount: Cardinal);
    procedure CheckGetText     (Sender: TTyTreeView; Node: PTyTreeNode;
                                var AText: string);
    procedure CheckOnChecked   (Sender: TTyTreeView; Node: PTyTreeNode);
    procedure CheckChecking     (Sender: TTyTreeView; Node: PTyTreeNode;
                                 var Allowed: Boolean);

    { Tab 4 — Multi-select }
    procedure MultiInitNode    (Sender: TTyTreeView; ParentNode, Node: PTyTreeNode;
                                var InitStates: TTyNodeInitStates);
    procedure MultiInitChildren(Sender: TTyTreeView; Node: PTyTreeNode;
                                var ChildCount: Cardinal);
    procedure MultiGetText     (Sender: TTyTreeView; Node: PTyTreeNode;
                                var AText: string);
    procedure MultiSelectionChanged(Sender: TObject);
    procedure MultiFocusChanged(Sender: TTyTreeView; Node: PTyTreeNode);
    procedure MultiIncrementalSearch(Sender: TTyTreeView; Node: PTyTreeNode;
                                const ASearchText: string; var AMatch: Boolean);

    { Tab 5 — Drag to move (small, reparent-safe) }
    procedure DragGetText   (Sender: TTyTreeView; Node: PTyTreeNode;
                             var AText: string);
    procedure DragNodeMoved (Sender: TTyTreeView; Node: PTyTreeNode);
    procedure DragDragOver  (Sender: TTyTreeView; Src, Target: PTyTreeNode;
                             Mode: TTyTreeDropMode; var Allowed: Boolean);
    procedure DragFreeNode  (Sender: TTyTreeView; Node: PTyTreeNode);

    { Tab 6 — Owner-draw helpers (shared geometry / colours for the two
      per-cell paint hooks). }
    function  DrawRowPercent(Sender: TTyTreeView; Node: PTyTreeNode): Integer;
    function  DrawPillRect(const ACellRect: TRect): TRect;
    function  OwnerDrawInk: TColor;
  end;

var
  ShowcaseForm: TShowcaseForm;

implementation

{$R *.lfm}

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

{ OnFocusChanged is not OnSelectionChanged: the FOCUSED row is the one the keyboard acts
  on, and with toMultiSelect it moves independently of the selection (Ctrl+arrows move
  focus without selecting; Ctrl+Space then toggles that row into the set). Panel 1 keeps
  it so the two never overwrite each other. }
procedure TShowcaseForm.MultiFocusChanged(Sender: TTyTreeView; Node: PTyTreeNode);
begin
  if Node = nil then
    SetFocusInfo('')
  else
    SetFocusInfo(Format('Focused: item %d (level %d)',
      [Node^.Index, Sender.GetNodeLevel(Node)]));
end;

{ The built-in incremental search matches a PREFIX. Handling the event replaces that
  test wholesale -- here with a substring match, so typing "23" also finds "Item 123". }
procedure TShowcaseForm.MultiIncrementalSearch(Sender: TTyTreeView;
  Node: PTyTreeNode; const ASearchText: string; var AMatch: Boolean);
var
  rowText: string;
begin
  rowText := '';
  MultiGetText(Sender, Node, rowText);
  AMatch := (ASearchText <> '') and
            (Pos(LowerCase(ASearchText), LowerCase(rowText)) > 0);
end;

{ The three checkboxes drive display properties that are usually set once at design time
  and then never seen changing. Flipping them live is the point. }
procedure TShowcaseForm.MultiLookChange(Sender: TObject);
begin
  MultiTree.ShowButtons   := ChkButtons.Checked;
  MultiTree.ShowTreeLines := ChkLines.Checked;
  MultiTree.ShowRoot      := ChkRoot.Checked;
  SetStatus(Format('ShowButtons = %s, ShowTreeLines = %s, ShowRoot = %s',
    [BoolToStr(ChkButtons.Checked, True), BoolToStr(ChkLines.Checked, True),
     BoolToStr(ChkRoot.Checked, True)]));
end;

procedure TShowcaseForm.TrkIndentChange(Sender: TObject);
begin
  MultiTree.Indent := TrkIndent.Position;
  SetStatus(Format('Indent = %d px per level', [TrkIndent.Position]));
end;

{ =======================================================================
  Form bootstrap — all controls stream from the .lfm; FormCreate wires the
  theme, adds the status panel and configures each streamed tree.
  ======================================================================= }
procedure TShowcaseForm.FormCreate(Sender: TObject);
var
  names: TStringArray;
  i:     Integer;
  Panel: TTyStatusPanel;
begin
  { Built-in themes are compiled in, so the switcher works without locating a
    themes/ folder. }
  TyRegisterBuiltinThemes;
  names := TyBuiltinThemeNames;
  for i := 0 to High(names) do
    ThemeCombo.Items.Add(names[i]);
  ThemeCombo.ItemIndex := ThemeCombo.Items.IndexOf('default');

  { 'default' is a dual-mode theme; seed a mode so its @mode-only vars resolve.
    The Light/Dark buttons flip this at runtime; the combo swaps ThemeName. All
    three drive the SAME controller (the global TyDefaultController). }
  TyDefaultController.ThemeName := 'default';
  TyDefaultController.Follow    := tfManual;
  TyDefaultController.Mode      := 'light';
  ApplyChromeTheme(TyDefaultController);   // theme the window chrome + background

  { Status bar: two panels (the bar is streamed; the panels are data, added
    here). Panel 0 is the running commentary every handler writes to; panel 1
    is reserved for the focused row, so OnFocusChanged and OnSelectionChanged
    can both stay visible instead of overwriting one another. }
  Panel := StatusBar.Panels.Add;
  Panel.Width := 580;
  Panel.Text  := 'Ready';

  Panel := StatusBar.Panels.Add;
  Panel.Width := 300;
  Panel.Text  := '';

  { Configure each streamed tree (columns / options / images / node-data
    population stay in code, exactly as before). }
  InitVirtualTab;
  InitColTab;
  InitCheckTab;
  InitMultiTab;
  InitDragTab;

  Pages.ActivePageIndex := 0;
end;

{ -----------------------------------------------------------------------
  Status-bar plumbing
  ----------------------------------------------------------------------- }
procedure TShowcaseForm.SetStatus(const AText: string);
begin
  if (StatusBar <> nil) and (StatusBar.Panels.Count > 0) then
    StatusBar.Panels[0].Text := AText;
end;

procedure TShowcaseForm.SetFocusInfo(const AText: string);
begin
  if (StatusBar <> nil) and (StatusBar.Panels.Count > 1) then
    StatusBar.Panels[1].Text := AText;
end;

procedure TShowcaseForm.ThemeComboChange(Sender: TObject);
begin
  if ThemeCombo.ItemIndex < 0 then Exit;
  TyDefaultController.ThemeName := ThemeCombo.Items[ThemeCombo.ItemIndex];
  ApplyChromeTheme(TyDefaultController);   // re-theme the shell on every skin change
end;

{ -----------------------------------------------------------------------
  Light / Dark toggle
  ----------------------------------------------------------------------- }
procedure TShowcaseForm.LightClick(Sender: TObject);
begin
  TyDefaultController.Follow := tfManual;
  TyDefaultController.Mode   := 'light';
  ApplyChromeTheme(TyDefaultController);
end;

procedure TShowcaseForm.DarkClick(Sender: TObject);
begin
  TyDefaultController.Follow := tfManual;
  TyDefaultController.Mode   := 'dark';
  ApplyChromeTheme(TyDefaultController);
end;

{ =======================================================================
  TAB 1 — Virtual tree: 1 000 000 root nodes, 5 levels deep, 10 children
  ======================================================================= }
procedure TShowcaseForm.InitVirtualTab;
begin
  { NOTE: intra-tree node drag (toNodeDrag) is deliberately NOT enabled here. The
    1M root nodes form one flat sibling list; a drop calls ReindexSiblings over the
    whole list (O(siblings), same class as DeleteNode) which would freeze the UI on
    a list this size. The drag-to-move demo lives on its own small tab instead (see
    InitDragTab). This tab stays a pure virtual-engine / lazy-init showcase. }
  VirtualTree.Options := [];

  VirtualTree.OnInitNode     := @VirtualInitNode;
  VirtualTree.OnInitChildren := @VirtualInitChildren;
  VirtualTree.OnGetText      := @VirtualGetText;

  { Expand/collapse lifecycle. OnExpanding is the VETO hook (it runs before any
    child is materialised, so a refused expansion costs nothing); OnExpanded /
    OnCollapsed are the after-the-fact notifications. OnNodeClick /
    OnNodeDblClick are the plain interaction hooks. }
  VirtualTree.OnExpanding    := @VirtualExpanding;
  VirtualTree.OnExpanded     := @VirtualExpanded;
  VirtualTree.OnCollapsed    := @VirtualCollapsed;
  VirtualTree.OnNodeClick    := @VirtualNodeClick;
  VirtualTree.OnNodeDblClick := @VirtualNodeDblClick;

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

{ OnExpanding runs BEFORE OnInitChildren, so a veto here is free: the ten child
  nodes are never allocated. Level 3 is the last expandable level (VirtualInitNode
  stops flagging children at level 4), so refusing it makes level 4 unreachable —
  exactly the shape of an app that gates a branch behind a permission check. }
procedure TShowcaseForm.VirtualExpanding(Sender: TTyTreeView;
  Node: PTyTreeNode; var Allowed: Boolean);
begin
  if (Node <> nil) and (Sender.GetNodeLevel(Node) = 3) then
  begin
    Allowed := False;
    SetStatus(Format('Level-3 expansion vetoed (OnExpanding) — Node %d stays shut',
      [Node^.Index]));
  end;
end;

procedure TShowcaseForm.VirtualExpanded(Sender: TTyTreeView; Node: PTyTreeNode);
begin
  if Node = nil then Exit;
  SetStatus(Format('Expanded Node %d  (OnExpanded)', [Node^.Index]));
end;

procedure TShowcaseForm.VirtualCollapsed(Sender: TTyTreeView; Node: PTyTreeNode);
begin
  if Node = nil then Exit;
  SetStatus(Format('Collapsed Node %d  (OnCollapsed)', [Node^.Index]));
end;

procedure TShowcaseForm.VirtualNodeClick(Sender: TTyTreeView; Node: PTyTreeNode);
var
  s: string;
begin
  if Node = nil then Exit;
  s := '';
  VirtualGetText(Sender, Node, s);
  SetStatus('Clicked ' + s + '  (OnNodeClick)');
end;

procedure TShowcaseForm.VirtualNodeDblClick(Sender: TTyTreeView; Node: PTyTreeNode);
var
  s: string;
begin
  if Node = nil then Exit;
  s := '';
  VirtualGetText(Sender, Node, s);
  SetStatus('Double-clicked ' + s + '  (OnNodeDblClick)');
end;

{ ScrollIntoView on a 1M-row list: walk the ROOT sibling chain (never GetNext —
  that descends into whatever the user has expanded) to the 1000th node, focus
  it and let the control bring it into view. }
procedure TShowcaseForm.BtnGoToNodeClick(Sender: TObject);
var
  n: PTyTreeNode;
  i: Integer;
begin
  n := VirtualTree.GetFirstChild(nil);
  i := 0;
  while (n <> nil) and (i < 999) do
  begin
    n := VirtualTree.GetNextSibling(n);
    Inc(i);
  end;
  if n = nil then
  begin
    SetStatus('Node 1000 not found');
    Exit;
  end;
  VirtualTree.FocusedNode := n;
  VirtualTree.ScrollIntoView(n);
  SetStatus('ScrollIntoView: jumped to root node 1000 (Index 999)');
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

procedure TShowcaseForm.InitColTab;
var
  col: TTyColumn;
begin
  { Explorer-style row icons (drawn in code, owned by the form) }
  BuildFileIcons;

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
  ColTree.OnEditCancelled := @ColEditCancelled;

  { Header notifications: the tab already ENABLES the sort / resize / reorder
    gestures — these report what the user actually did with them. }
  ColTree.OnHeaderClick    := @ColHeaderClick;
  ColTree.OnColumnResized  := @ColColumnResized;
  ColTree.OnColumnReorder  := @ColColumnReorder;

  { Per-row icons in the main (Name) column }
  ColTree.Images          := FFileIcons;
  ColTree.OnGetImageIndex := @ColGetImageIndex;

  { Build header }
  with ColTree.Header do
  begin
    { hoHotTrack highlights the header section under the cursor (the body's own
      row hover comes from ColTree.HotTrack, set in the .lfm); hoAutoResize makes
      AutoSizeIndex's column absorb whatever width is left over. }
    Options := [hoVisible, hoColumnResize, hoShowSortGlyphs,
                hoHeaderClickAutoSort, hoDrag, hoAutoResize, hoHotTrack];

    col := Columns.Add as TTyColumn;
    col.Text := 'Name';
    col.Width := 200;
    col.Alignment := taLeftJustify;
    { Pinned: the default set includes coDraggable — drop it and this column can
      no longer be dragged out of first place (it still resizes and still sorts). }
    col.Options := [coVisible, coResizable, coAllowClick];

    col := Columns.Add as TTyColumn;
    col.Text := 'Type';
    col.Width := 110;
    col.Alignment := taLeftJustify;

    col := Columns.Add as TTyColumn;
    col.Text := 'Size';
    col.Width := 90;
    col.Alignment := taRightJustify;
    { Clamped drag range + a caption that follows the (right-aligned) data. }
    col.MinWidth := 60;
    col.MaxWidth := 140;
    col.CaptionAlignment := taRightJustify;

    col := Columns.Add as TTyColumn;
    col.Text := 'Modified';
    col.Width := 120;
    col.Alignment := taLeftJustify;

    { Set the main (tree) column AFTER the columns exist — SetMainColumn clamps to
      NoColumn(-1) when assigned while Columns.Count = 0. Same for AutoSizeIndex:
      it names the LAST column, which only exists once the Adds above have run. }
    MainColumn    := 0;
    AutoSizeIndex := 3;
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

{ The other half of the edit lifecycle: Esc (or a programmatic CancelEdit) closes
  the editor WITHOUT firing OnNewText, so the node blob is left untouched. }
procedure TShowcaseForm.ColEditCancelled(Sender: TTyTreeView; Node: PTyTreeNode;
  Column: Integer);
begin
  SetStatus('Rename cancelled (Esc) — OnEditCancelled, nothing written to the node');
end;

{ Header notifications. OnHeaderClick fires AFTER the automatic sort has run
  (hoHeaderClickAutoSort), so the header already carries the new SortColumn /
  SortDirection when we read them here. }
procedure TShowcaseForm.ColHeaderClick(Sender: TTyTreeView; Column: Integer);
var
  dir: string;
begin
  if (Column < 0) or (Column >= ColTree.Header.Columns.Count) then Exit;
  if ColTree.Header.SortDirection = sdAscending then dir := 'ascending'
  else dir := 'descending';
  SetStatus(Format('Sorted by %s, %s  (OnHeaderClick)',
    [TTyColumn(ColTree.Header.Columns.Items[Column]).Text, dir]));
end;

procedure TShowcaseForm.ColColumnResized(Sender: TTyTreeView; Column: Integer);
begin
  if (Column < 0) or (Column >= ColTree.Header.Columns.Count) then Exit;
  SetStatus(Format('Column %d resized to %d px  (OnColumnResized)',
    [Column, TTyColumn(ColTree.Header.Columns.Items[Column]).Width]));
end;

procedure TShowcaseForm.ColColumnReorder(Sender: TTyTreeView;
  OldPosition, NewPosition: Integer);
begin
  SetStatus(Format('Column moved %d -> %d  (OnColumnReorder)',
    [OldPosition, NewPosition]));
end;

{ FullExpand / FullCollapse: the programmatic counterparts of clicking every
  expand button. Safe here because the tab's tree is tiny — never call FullExpand
  on the 1M-node tab. }
procedure TShowcaseForm.BtnExpandAllClick(Sender: TObject);
begin
  ColTree.FullExpand(nil);
  SetStatus('FullExpand(nil) — every branch open');
end;

procedure TShowcaseForm.BtnCollapseAllClick(Sender: TObject);
begin
  ColTree.FullCollapse(nil);
  SetStatus('FullCollapse(nil) — back to the three root folders');
end;

{ =======================================================================
  TAB 3 — Checkboxes
  - Level 0 folders: ctTriStateCheckBox (auto-tri-state tracking)
  - Level 1 files (folders 0+1): ctCheckBox
  - Level 1 items under folder 2 ("Games"): ctRadioButton (mutual exclusion)
  Options = [toCheckSupport, toAutoTristateTracking]
  OnChecked updates the status bar with the toggled node's name.
  ======================================================================= }
procedure TShowcaseForm.InitCheckTab;
begin
  CheckTree.Options := [toCheckSupport, toAutoTristateTracking];

  CheckTree.OnInitNode     := @CheckInitNode;
  CheckTree.OnInitChildren := @CheckInitChildren;
  CheckTree.OnGetText      := @CheckGetText;
  CheckTree.OnChecked      := @CheckOnChecked;
  CheckTree.OnChecking     := @CheckChecking;

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
{ OnChecking is the VETO half of the check pair: it runs before the state flips and can
  refuse it, while OnChecked only reports what already happened. Here the first root is
  a locked branch -- a permission-gated group in a real app. }
procedure TShowcaseForm.CheckChecking(Sender: TTyTreeView; Node: PTyTreeNode;
  var Allowed: Boolean);
begin
  if (Sender.GetNodeLevel(Node) = 0) and (Node^.Index = 0) then
  begin
    Allowed := False;
    SetStatus('Group 0 is locked - OnChecking refused the toggle');
  end;
end;

procedure TShowcaseForm.InitMultiTab;
begin
  MultiTree.Options := [toMultiSelect, toFullRowSelect];

  MultiTree.OnInitNode        := @MultiInitNode;
  MultiTree.OnInitChildren    := @MultiInitChildren;
  MultiTree.OnGetText         := @MultiGetText;
  MultiTree.OnSelectionChanged := @MultiSelectionChanged;
  { toIncrementalSearch makes the control type-to-find; OnIncrementalSearch then
    decides what "matches" means (the default is a prefix test). SearchTimeout comes
    from the .lfm. }
  MultiTree.Options := MultiTree.Options + [toIncrementalSearch];
  MultiTree.OnFocusChanged      := @MultiFocusChanged;
  MultiTree.OnIncrementalSearch := @MultiIncrementalSearch;

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
  TAB 5 — Drag to move (small, reparent-safe)
  A deliberately SMALL static tree (3 groups × ~3 items = ~12 nodes, 2 levels)
  with toNodeDrag enabled — the safe home for the drag demo. Each node carries a
  STABLE label id in its node-data blob (assigned once at build time); DragGetText
  reads that id, so a node keeps its caption when reparented or reordered (NOT a
  [parent][childIndex] lookup, which would go out of bounds after a reparent).
  ======================================================================= }
const
  { 12 stable captions, indexed by the id stored in each node's data blob. }
  DragLabels: array[0..11] of string = (
    'Fruits', 'Apple', 'Banana', 'Cherry',
    'Animals', 'Cat', 'Dog', 'Otter',
    'Colors', 'Red', 'Green', 'Blue');
type
  { one Integer per node: the stable index into DragLabels. }
  PDragRec = ^TDragRec;
  TDragRec = record
    LabelId: Integer;
  end;

procedure TShowcaseForm.InitDragTab;
begin
  DragTree.Options := [toNodeDrag];
  DragTree.NodeDataSize := SizeOf(TDragRec);
  DragTree.OnGetText   := @DragGetText;
  DragTree.OnNodeMoved := @DragNodeMoved;
  { OnDragOver vets every hover position, so a drop can be refused before it happens;
    OnFreeNode fires for every node the control releases, however it dies (Delete,
    Clear, or the form going away). }
  DragTree.OnDragOver  := @DragDragOver;
  DragTree.OnFreeNode  := @DragFreeNode;

  BuildDragNodes;
end;

{ Split out of InitDragTab so the Rebuild button can put the tree back after Clear. }
procedure TShowcaseForm.BuildDragNodes;
var
  group:   PTyTreeNode;
  child:   PTyTreeNode;
  data:    PDragRec;
  g, c, id: Integer;
begin
  { Build the small tree eagerly (no lazy init needed at this size). Three groups,
    each with three children; the label id is just the node's position in
    DragLabels at build time and never changes thereafter. }
  DragTree.Clear;
  for g := 0 to 2 do
  begin
    group := DragTree.AddChild(nil);
    id := g * 4;
    data := PDragRec(DragTree.GetNodeData(group));
    if data <> nil then data^.LabelId := id;
    for c := 1 to 3 do
    begin
      child := DragTree.AddChild(group);
      data := PDragRec(DragTree.GetNodeData(child));
      if data <> nil then data^.LabelId := id + c;
    end;
    DragTree.Expanded[group] := True;
  end;
end;

procedure TShowcaseForm.DragGetText(Sender: TTyTreeView;
  Node: PTyTreeNode; var AText: string);
var
  data: PDragRec;
begin
  data := PDragRec(Sender.GetNodeData(Node));
  if (data <> nil) and (data^.LabelId >= Low(DragLabels)) and
     (data^.LabelId <= High(DragLabels)) then
    AText := DragLabels[data^.LabelId]
  else
    AText := '?';
end;

{ Announce a completed move in the status bar (the stable label travels with the
  node, so we just re-read its caption). }
{ OnDragOver runs for every hover position, so the tree can refuse a drop before it
  happens rather than undoing it afterwards. dmOn means "make it a CHILD of the
  target", which only makes sense for a branch -- so it is refused on a leaf, while
  dmAbove / dmBelow (pure reordering) always pass. }
procedure TShowcaseForm.DragDragOver(Sender: TTyTreeView; Src, Target: PTyTreeNode;
  Mode: TTyTreeDropMode; var Allowed: Boolean);
begin
  if (Mode = dmOn) and (Target <> nil) and (Sender.GetNodeLevel(Target) > 0) then
  begin
    Allowed := False;
    SetStatus('OnDragOver: refused - a leaf cannot take children (drop ABOVE or BELOW instead)');
  end;
end;

{ Fires for EVERY node the control releases, whoever caused it: Delete, Clear, or the
  form closing. A real app frees managed node data here; the showcase just counts. }
procedure TShowcaseForm.DragFreeNode(Sender: TTyTreeView; Node: PTyTreeNode);
begin
  Inc(FFreedNodes);
end;

procedure TShowcaseForm.BtnDragDeleteClick(Sender: TObject);
var
  node: PTyTreeNode;
  before: Integer;
begin
  node := DragTree.FocusedNode;
  if node = nil then
  begin
    SetStatus('Nothing to delete - click a row first');
    Exit;
  end;
  before := FFreedNodes;
  DragTree.DeleteNode(node);   // a branch takes its children with it
  SetStatus(Format('Deleted - OnFreeNode released %d node(s), %d in total',
    [FFreedNodes - before, FFreedNodes]));
end;

procedure TShowcaseForm.BtnDragClearClick(Sender: TObject);
var
  before: Integer;
begin
  before := FFreedNodes;
  DragTree.Clear;
  SetStatus(Format('Cleared - OnFreeNode released %d node(s), %d in total. '
    + 'The centred text is the control''s own EmptyListMessage.',
    [FFreedNodes - before, FFreedNodes]));
end;

procedure TShowcaseForm.BtnDragRebuildClick(Sender: TObject);
begin
  BuildDragNodes;
  SetStatus('Rebuilt the three groups');
end;

procedure TShowcaseForm.DragNodeMoved(Sender: TTyTreeView; Node: PTyTreeNode);
var
  s: string;
begin
  s := '';
  DragGetText(Sender, Node, s);
  if (StatusBar <> nil) and (StatusBar.Panels.Count > 0) then
    StatusBar.Panels[0].Text := 'Moved ' + s;
end;


{ =======================================================================
  Tab 6 — Owner-draw
  toOwnerDraw hands each CELL to OnDrawNode after the theme has painted the row
  background, the expand button and the tree lines, so the example only replaces the
  CONTENT. OnAfterCellPaint then runs for every cell whether or not the option is on,
  which makes it the place for an overlay that must survive either mode.
  ======================================================================= }

{ Level 0 = a build (tall row, progress pill), level 1 = a stage (short row). }
procedure TShowcaseForm.DrawInitNode(Sender: TTyTreeView;
  ParentNode, Node: PTyTreeNode; var InitStates: TTyNodeInitStates);
begin
  if Sender.GetNodeLevel(Node) = 0 then
    Include(InitStates, ivsHasChildren);
end;

procedure TShowcaseForm.DrawInitChildren(Sender: TTyTreeView;
  Node: PTyTreeNode; var ChildCount: Cardinal);
begin
  ChildCount := 4;
end;

{ Still needed with toOwnerDraw: the control uses it for incremental search, for
  accessibility and as the fallback if the paint hook does nothing. }
procedure TShowcaseForm.DrawGetText(Sender: TTyTreeView; Node: PTyTreeNode;
  var AText: string);
begin
  if Sender.GetNodeLevel(Node) = 0 then
    AText := Format('Build #%d', [Node^.Index + 1])
  else
    AText := Format('Stage %d', [Node^.Index + 1]);
end;

{ toVariableNodeHeight makes the control ask per row instead of using one height. }
procedure TShowcaseForm.DrawMeasureItem(Sender: TTyTreeView; ACanvas: TCanvas;
  Node: PTyTreeNode; var ANodeHeight: Integer);
begin
  if Sender.GetNodeLevel(Node) = 0 then ANodeHeight := 40 else ANodeHeight := 22;
end;

{ A deterministic 0..100 per build, so the pills do not dance on every repaint. }
function TShowcaseForm.DrawRowPercent(Sender: TTyTreeView; Node: PTyTreeNode): Integer;
begin
  Result := ((Node^.Index * 37) mod 101);
end;

{ The pill occupies the right end of the cell, vertically centred. }
function TShowcaseForm.DrawPillRect(const ACellRect: TRect): TRect;
const
  PillW = 120;
  PillH = 10;
begin
  Result.Right  := ACellRect.Right - 12;
  Result.Left   := Result.Right - PillW;
  Result.Top    := (ACellRect.Top + ACellRect.Bottom - PillH) div 2;
  Result.Bottom := Result.Top + PillH;
end;

{ Read the ink from the THEME rather than hard-coding one, so the owner-drawn text
  follows every skin and both modes exactly like the rows around it. }
function TShowcaseForm.OwnerDrawInk: TColor;
begin
  Result := TyColorToLCL(
    TyDefaultController.Model.ResolveStyle('TyTreeView', '', []).TextColor);
end;

procedure TShowcaseForm.DrawDrawNode(Sender: TTyTreeView; ACanvas: TCanvas;
  Node: PTyTreeNode; Column: Integer; const ACellRect: TRect);
var
  txt:  string;
  pill: TRect;
  pct:  Integer;
  ink:  TColor;
begin
  ink := OwnerDrawInk;
  DrawGetText(Sender, Node, txt);

  ACanvas.Brush.Style := bsClear;
  ACanvas.Font.Color  := ink;
  ACanvas.Font.Bold   := Sender.GetNodeLevel(Node) = 0;
  ACanvas.TextOut(ACellRect.Left + 4,
    (ACellRect.Top + ACellRect.Bottom - ACanvas.TextHeight('Hg')) div 2, txt);
  ACanvas.Font.Bold := False;

  { Only builds carry a progress pill; the stages are plain text rows. }
  if Sender.GetNodeLevel(Node) <> 0 then Exit;
  pill := DrawPillRect(ACellRect);
  if pill.Left <= ACellRect.Left + ACanvas.TextWidth(txt) + 16 then Exit;  // no room

  pct := DrawRowPercent(Sender, Node);
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := TyColorToLCL(
    TyDefaultController.Model.ResolveStyle('TyProgressBar', '', []).Background.Color);
  ACanvas.FillRect(pill);
  ACanvas.Brush.Color := TyColorToLCL(
    TyDefaultController.Model.ResolveStyle('TyButton', 'primary', []).Background.Color);
  ACanvas.FillRect(Rect(pill.Left, pill.Top,
    pill.Left + Round((pill.Right - pill.Left) * pct / 100), pill.Bottom));
  ACanvas.Brush.Style := bsClear;
end;

{ Runs for EVERY cell, with or without toOwnerDraw -- an overlay hook rather than a
  replacement one. Every fifth build gets a NEW badge. }
procedure TShowcaseForm.DrawAfterCellPaint(Sender: TTyTreeView; ACanvas: TCanvas;
  Node: PTyTreeNode; Column: Integer; const ACellRect: TRect);
var
  badge: TRect;
begin
  if Sender.GetNodeLevel(Node) <> 0 then Exit;
  if (Node^.Index mod 5) <> 0 then Exit;

  badge.Left   := ACellRect.Left + 4;
  badge.Top    := ACellRect.Top + 2;
  badge.Right  := badge.Left + 34;
  badge.Bottom := badge.Top + 14;
  if badge.Right > ACellRect.Right then Exit;

  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := TyColorToLCL(
    TyDefaultController.Model.ResolveStyle('TyBadge', '', []).Background.Color);
  ACanvas.FillRect(badge);
  ACanvas.Brush.Style := bsClear;
  ACanvas.Font.Color  := clWhite;
  ACanvas.TextOut(badge.Left + 5, badge.Top, 'NEW');
end;

procedure TShowcaseForm.DrawChange(Sender: TTyTreeView; Node: PTyTreeNode);
var
  txt: string;
begin
  if Node = nil then Exit;
  DrawGetText(Sender, Node, txt);
  if Sender.GetNodeLevel(Node) = 0 then
    SetStatus(Format('%s - %d%% (owner-drawn pill), OnChange',
      [txt, DrawRowPercent(Sender, Node)]))
  else
    SetStatus(Format('%s - OnChange', [txt]));
end;


end.
