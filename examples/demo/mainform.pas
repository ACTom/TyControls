unit mainform;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, Menus, ComCtrls,
  tyControls.Controller, tyControls.Button, tyControls.TyLabel, tyControls.Edit,
  tyControls.CheckBox, tyControls.Panel, tyControls.ComboBox,
  tyControls.ScrollBar, tyControls.Form, tyControls.ListBox,
  tyControls.ProgressBar, tyControls.ToggleSwitch, tyControls.TrackBar,
  tyControls.GroupBox, tyControls.PageControl, tyControls.TabSheet,
  tyControls.SpinEdit, tyControls.Memo, tyControls.Menu,
  tyControls.BuiltinThemes, tyControls.NativeStyler,
  tyControls.ToolBar, tyControls.StatusBar, tyControls.Splitter,
  tyControls.Calendar, tyControls.DateTimePicker,
  tyControls.TreeView, tyControls.TreeView.Columns;
type

  { TDemoMainForm — ALL controls live in the designer (mainform.lfm), including the docked
    TTyTitleBar, the theme switcher (ThemeCombo + appearance buttons + random), the
    PageControl's pages, TTySpinEdit and TTyMemo. Code only does logic (data + handlers);
    it NEVER creates UI controls (project rule: demo UI is edited in the .lfm only). }

  TDemoMainForm = class(TTyForm)
    BtnDanger: TTyButton;
    BtnPrimary: TTyButton;
    Calendar1: TTyCalendar;
    ChkAgree: TTyCheckBox;
    ComboKind: TTyComboBox;
    DateField1: TTyDateTimePicker;
    EditName: TTyEdit;
    GroupBox1: TTyGroupBox;
    LblHello: TTyLabel;
    ListBox1: TTyListBox;
    Memo1: TTyMemo;
    PanelBox: TTyPanel;
    Progress1: TTyProgressBar;
    RadOne: TTyRadioButton;
    ScrollV: TTyScrollBar;
    SpinKind: TTySpinEdit;
    TabCtrl1: TTyPageControl;
    TimeField1: TTyDateTimePicker;
    Toggle1: TTyToggleSwitch;
    TrackBar1: TTyTrackBar;
    TreeView1: TTreeView;
    TyButton1: TTyButton;
    TyButton2: TTyButton;
    TyButton3: TTyButton;
    TyController: TTyStyleController;
    TyEdit1: TTyEdit;
    TyNativeStyler1: TTyNativeStyler;
    TyPanel1: TTyPanel;
    TyPanel2: TTyPanel;
    TyTabSheet1: TTyTabSheet;
    TyTabSheet2: TTyTabSheet;
    TyTabSheet3: TTyTabSheet;
    TyTitleBar1: TTyTitleBar;
    ToolBar1: TTyToolBar;
    TbBtnNew: TTyButton;
    TbSep1: TTyToolSeparator;
    TbBtnOpen: TTyButton;
    StatusBar1: TTyStatusBar;
    SidePanel: TTyPanel;
    Splitter1: TTySplitter;
    ThemeCombo: TTyComboBox;
    BtnApLight: TTyButton;
    BtnApDark: TTyButton;
    MainMenu1: TMainMenu;
    MnuFile: TMenuItem;
    MnuFileNew: TMenuItem;
    MnuFileOpen: TMenuItem;
    MnuFileSep: TMenuItem;
    MnuFileExit: TMenuItem;
    MnuEdit: TMenuItem;
    MnuEditCut: TMenuItem;
    MnuEditCopy: TMenuItem;
    MnuEditPaste: TMenuItem;
    MnuView: TMenuItem;
    MnuViewToggle: TMenuItem;
    MnuViewMore: TMenuItem;
    MnuViewMoreA: TMenuItem;
    MnuViewMoreB: TMenuItem;
    TyMenuBar1: TTyMenuBar;
    PopupCtx: TTyPopupMenu;
    PopupCtxHello: TMenuItem;
    PopupCtxAgree: TMenuItem;
    TyTree1: TTyTreeView;
    TyColTree: TTyTreeView;
    TyTabSheet4: TTyTabSheet;
    procedure FormCreate(Sender: TObject);
    procedure TyTree1InitNode(Sender: TTyTreeView; ParentNode, Node: PTyTreeNode;
      var InitStates: TTyNodeInitStates);
    procedure TyTree1InitChildren(Sender: TTyTreeView; Node: PTyTreeNode;
      var ChildCount: Cardinal);
    procedure TyTree1GetText(Sender: TTyTreeView; Node: PTyTreeNode;
      var AText: string);
    { Multi-column sortable tree handlers }
    procedure TyColTreeInitNode(Sender: TTyTreeView; ParentNode, Node: PTyTreeNode;
      var InitStates: TTyNodeInitStates);
    procedure TyColTreeInitChildren(Sender: TTyTreeView; Node: PTyTreeNode;
      var ChildCount: Cardinal);
    procedure TyColTreeGetText(Sender: TTyTreeView; Node: PTyTreeNode;
      Column: Integer; TextType: TTyVSTTextType; var CellText: string);
    procedure TyColTreeCompareNodes(Sender: TTyTreeView; Node1, Node2: PTyTreeNode;
      Column: Integer; var CompareResult: Integer);
    procedure GroupBox1Click(Sender: TObject);
    procedure MnuViewToggleClick(Sender: TObject);
    procedure MnuFileExitClick(Sender: TObject);
    procedure PopupCtxHelloClick(Sender: TObject);
    procedure PopupCtxAgreeClick(Sender: TObject);
    procedure TrackBar1Change(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure ApLightClick(Sender: TObject);
    procedure ApDarkClick(Sender: TObject);
    procedure ApAutoClick(Sender: TObject);
    procedure RandomClick(Sender: TObject);
    procedure TyButton1Click(Sender: TObject);
    procedure TyButton3Click(Sender: TObject);
  private
    function ThemeDir: string;
    procedure InitThemes;
    procedure InitColTree;
    procedure ApplyBuiltin(const AName: string);
    procedure SetAppearance(AFollow: TTyThemeFollow; const AMode: string; ASelected: TTyButton);
  end;
var
  DemoMainForm: TDemoMainForm;
implementation
{$R *.lfm}

resourcestring
  // English msgids; Simplified-Chinese in examples/demo/languages/demo.zh_CN.po.
  rsDemoThemeCustom     = 'Custom…';
  rsDemoThemeFilter     = 'TyControls Theme (*.tycss)|*.tycss';
  rsDemoGreetingShown   = 'Hello TyControls';
  rsDemoGreetingHidden  = 'Greeting hidden';
  rsDemoGreetingFromCtx = 'Hello from the context menu';

function TDemoMainForm.ThemeDir: string;
var
  Dir: string;
  i: Integer;
begin
  // 从 exe 所在目录向上逐级查找 themes/(兼容工程目录 / lib/<cpu>-<os>/ / macOS .app 包)。
  Dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  for i := 1 to 8 do
  begin
    if DirectoryExists(Dir + 'themes') then
      Exit(Dir + 'themes' + PathDelim);
    Dir := ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
    if Dir = '' then Break;
  end;
  Result := 'themes' + PathDelim; // 兜底:相对当前目录
end;

procedure TDemoMainForm.TrackBar1Change(Sender: TObject);
begin
  if Assigned(Progress1) then
    Progress1.Position := TrackBar1.Position;
end;

procedure TDemoMainForm.FormCreate(Sender: TObject);
begin
  Randomize;                  // 给「随机换肤」一个种子
  // Controls (incl. the title bar/tabs/spin/memo AND the theme switcher) come from the
  // .lfm. Associate the themed menu bar (shortcut dispatch / macOS global menu), then
  // fill the theme dropdown + set the initial theme/appearance — data only, no UI build.
  MenuBar := TyMenuBar1;
  {$IFDEF DARWIN}
  // macOS: MenuBar moves to the global top-of-screen bar, so the in-window TyMenuBar1 is hidden,
  // freeing the left of the title bar. Left-align the caption to fill that space instead of leaving
  // it floating at the right (where it looks unbalanced once the menu is gone).
  TyTitleBar1.TitleAlignment := taLeftJustify;
  {$ENDIF}
  InitThemes;
  InitColTree;
end;

procedure TDemoMainForm.GroupBox1Click(Sender: TObject);
begin

end;

procedure TDemoMainForm.InitThemes;
var
  names: TStringArray;
  i: Integer;
begin
  // 控件全部来自 .lfm;这里只填数据 + 设初始状态,绝不创建控件。
  TyRegisterBuiltinThemes;
  names := TyBuiltinThemeNames;
  ThemeCombo.Items.Clear;
  for i := 0 to High(names) do ThemeCombo.Items.Add(names[i]);
  ThemeCombo.Items.Add(rsDemoThemeCustom);
  ThemeCombo.ItemIndex := 0;                 // default
  ApplyBuiltin('default');
  SetAppearance(tfFollowSystem, '', nil);   // 初始外观:跟随系统
end;

procedure TDemoMainForm.ApplyBuiltin(const AName: string);
begin
  // 只换主题,不动 Follow/Mode(外观轴由三态独占)。
  TyController.ThemeName := AName;
  ApplyChromeTheme(TyController);
end;

procedure TDemoMainForm.ThemeComboChange(Sender: TObject);
var idx: Integer; dlg: TOpenDialog;
begin
  idx := ThemeCombo.ItemIndex;
  if idx < 0 then Exit;
  if ThemeCombo.Items[idx] = rsDemoThemeCustom then
  begin
    dlg := TOpenDialog.Create(Self);
    try
      dlg.Filter := rsDemoThemeFilter;
      dlg.InitialDir := ThemeDir;
      if dlg.Execute then
      begin
        TyController.ThemeFile := dlg.FileName;   // 自定义文件(REPLACE)
        ApplyChromeTheme(TyController);
      end;
    finally dlg.Free; end;
  end
  else
    ApplyBuiltin(ThemeCombo.Items[idx]);
end;

procedure TDemoMainForm.SetAppearance(AFollow: TTyThemeFollow; const AMode: string;
  ASelected: TTyButton);
begin
  TyController.Follow := AFollow;
  if AFollow = tfManual then TyController.Mode := AMode;   // 跟随系统时 Mode 由 OS 决定
  // 三态互斥:用 ghost 的 Down 选中态高亮当前外观。
  BtnApLight.Down := (ASelected = BtnApLight);
  BtnApDark.Down  := (ASelected = BtnApDark);
  ApplyChromeTheme(TyController);
end;

procedure TDemoMainForm.ApLightClick(Sender: TObject);
begin SetAppearance(tfManual, 'light', BtnApLight); end;

procedure TDemoMainForm.ApDarkClick(Sender: TObject);
begin SetAppearance(tfManual, 'dark', BtnApDark); end;

procedure TDemoMainForm.ApAutoClick(Sender: TObject);
begin
end;

procedure TDemoMainForm.RandomClick(Sender: TObject);
begin

end;

procedure TDemoMainForm.TyButton1Click(Sender: TObject);
begin
  TyButton1.Caption := TyButton1.Caption + '1';
end;

procedure TDemoMainForm.TyButton3Click(Sender: TObject);
begin
  TyButton3.Caption := TyButton3.Caption + '1';
end;

procedure TDemoMainForm.MnuViewToggleClick(Sender: TObject);
begin
  // Demonstrates a checked item driving a control: flip the label text + the check mark.
  MnuViewToggle.Checked := not MnuViewToggle.Checked;
  if MnuViewToggle.Checked then
    LblHello.Caption := rsDemoGreetingShown
  else
    LblHello.Caption := rsDemoGreetingHidden;
end;

procedure TDemoMainForm.MnuFileExitClick(Sender: TObject);
begin
  Close;
end;

procedure TDemoMainForm.PopupCtxHelloClick(Sender: TObject);
begin
  LblHello.Caption := rsDemoGreetingFromCtx;
end;

procedure TDemoMainForm.PopupCtxAgreeClick(Sender: TObject);
begin
  ChkAgree.Checked := not ChkAgree.Checked;
end;

procedure TDemoMainForm.TyTree1InitNode(Sender: TTyTreeView; ParentNode, Node: PTyTreeNode;
  var InitStates: TTyNodeInitStates);
begin
  if Sender.GetNodeLevel(Node) < 4 then
    Include(InitStates, ivsHasChildren);
end;

procedure TDemoMainForm.TyTree1InitChildren(Sender: TTyTreeView; Node: PTyTreeNode;
  var ChildCount: Cardinal);
begin
  ChildCount := 10;
end;

procedure TDemoMainForm.TyTree1GetText(Sender: TTyTreeView; Node: PTyTreeNode;
  var AText: string);
begin
  AText := Format('Node %d  (L%d)', [Node^.Index, Sender.GetNodeLevel(Node)]);
end;

{ ---------------------------------------------------------------------------
  Multi-column sortable tree — small curated file-tree dataset
  3 folders x ~4-5 children.  Data is fully static (no NodeDataSize storage).
  Column 0 = Name (folder/file name)
  Column 1 = Size (bytes as string; '' for folders)
  Column 2 = Modified (date as string)
  --------------------------------------------------------------------------- }

const
  { Top-level folder names }
  ColTreeFolders: array[0..2] of string = ('Documents', 'Pictures', 'Projects');

  { Child names per folder [folder, child] }
  ColTreeChildNames: array[0..2] of array[0..4] of string = (
    ('Report_Q1.docx',  'Budget_2026.xlsx', 'Proposal.pdf',   'Notes.txt',    'Archive.zip'),
    ('Vacation.jpg',    'Logo.png',         'Screenshot.png', 'Portrait.jpg', ''),
    ('ty-controls',     'web-app',          'scripts',        'README.md',    '')
  );

  { Child sizes in bytes [folder, child]; 0 = sub-folder }
  ColTreeChildSizes: array[0..2] of array[0..4] of Integer = (
    (45312, 102400, 233472, 2048, 5242880),
    (3145728, 49152, 204800, 2097152, 0),
    (0, 0, 8192, 4096, 0)
  );

  { Child count per folder (how many are actually used; rest are padding) }
  ColTreeChildCounts: array[0..2] of Integer = (5, 4, 4);

  { Modified dates (stored as Pascal string; TDate = days since 30-Dec-1899) }
  ColTreeFolderDates: array[0..2] of string = ('2026-05-10', '2026-04-22', '2026-06-01');
  ColTreeChildDates: array[0..2] of array[0..4] of string = (
    ('2026-05-08', '2026-04-30', '2026-05-01', '2026-06-10', '2026-03-15'),
    ('2026-01-20', '2026-05-05', '2026-06-12', '2025-12-25', ''),
    ('2026-06-28', '2026-06-15', '2026-05-20', '2026-06-27', '')
  );

{ ---------------------------------------------------------------------------
  Build the 3-column header in code (documented exception: writing a
  TPersistent + TCollection hierarchy by hand in a .lfm is error-prone;
  code path is simpler and equally correct once nodes are initialised before
  the first paint).
  --------------------------------------------------------------------------- }

procedure TDemoMainForm.InitColTree;
{ Build the 3-column header in code (documented exception: writing a
  TPersistent + TCollection hierarchy by hand in a .lfm is error-prone;
  code path is simpler and equally correct). }
var
  col: TTyTreeColumn;
begin
  with TyColTree.Header do
  begin
    Options := [hoVisible, hoColumnResize, hoShowSortGlyphs,
                hoHeaderClickAutoSort, hoDrag];
    MainColumn := 0;
    { Column 0: Name }
    col := Columns.Add as TTyTreeColumn;
    col.Text := 'Name';
    col.Width := 180;
    col.Alignment := taLeftJustify;
    { Column 1: Size }
    col := Columns.Add as TTyTreeColumn;
    col.Text := 'Size';
    col.Width := 80;
    col.Alignment := taRightJustify;
    { Column 2: Modified }
    col := Columns.Add as TTyTreeColumn;
    col.Text := 'Modified';
    col.Width := 120;
    col.Alignment := taLeftJustify;
  end;
  TyColTree.RootNodeCount := 3;
end;

procedure TDemoMainForm.TyColTreeInitNode(Sender: TTyTreeView;
  ParentNode, Node: PTyTreeNode; var InitStates: TTyNodeInitStates);
begin
  { Top-level nodes (folders) always have children. }
  if Sender.GetNodeLevel(Node) = 0 then
    Include(InitStates, ivsHasChildren);
end;

procedure TDemoMainForm.TyColTreeInitChildren(Sender: TTyTreeView;
  Node: PTyTreeNode; var ChildCount: Cardinal);
var
  folderIdx: Integer;
begin
  folderIdx := Integer(Node^.Index);
  if (folderIdx >= 0) and (folderIdx <= 2) then
    ChildCount := Cardinal(ColTreeChildCounts[folderIdx])
  else
    ChildCount := 0;
end;

procedure TDemoMainForm.TyColTreeGetText(Sender: TTyTreeView;
  Node: PTyTreeNode; Column: Integer; TextType: TTyVSTTextType;
  var CellText: string);
var
  level, folderIdx, childIdx: Integer;
  sz: Integer;
begin
  if TextType <> ttNormal then begin CellText := ''; Exit; end;

  level := Sender.GetNodeLevel(Node);
  if level = 0 then
  begin
    { Folder row }
    folderIdx := Integer(Node^.Index);
    case Column of
      0: CellText := ColTreeFolders[folderIdx];
      1: CellText := '';                          { folders have no size }
      2: CellText := ColTreeFolderDates[folderIdx];
    else
      CellText := '';
    end;
  end
  else
  begin
    { File row }
    folderIdx := Integer(Node^.Parent^.Index);
    childIdx  := Integer(Node^.Index);
    case Column of
      0: CellText := ColTreeChildNames[folderIdx][childIdx];
      1: begin
           sz := ColTreeChildSizes[folderIdx][childIdx];
           if sz = 0 then CellText := ''
           else if sz < 1024 then CellText := Format('%d B', [sz])
           else if sz < 1048576 then CellText := Format('%d KB', [sz div 1024])
           else CellText := Format('%d MB', [sz div 1048576]);
         end;
      2: CellText := ColTreeChildDates[folderIdx][childIdx];
    else
      CellText := '';
    end;
  end;
end;

procedure TDemoMainForm.TyColTreeCompareNodes(Sender: TTyTreeView;
  Node1, Node2: PTyTreeNode; Column: Integer; var CompareResult: Integer);
var
  t1, t2: string;
  s1, s2: Integer;
  lv: Integer;
begin
  { Both nodes must be at the same level for sort to compare them.
    Within the same parent the column determines the key. }
  lv := Sender.GetNodeLevel(Node1);
  if lv = 0 then
  begin
    { Folder level: only Name and Modified are meaningful }
    case Column of
      0: CompareResult := CompareStr(
           ColTreeFolders[Integer(Node1^.Index)],
           ColTreeFolders[Integer(Node2^.Index)]);
      2: CompareResult := CompareStr(
           ColTreeFolderDates[Integer(Node1^.Index)],
           ColTreeFolderDates[Integer(Node2^.Index)]);
    else
      CompareResult := 0;
    end;
  end
  else
  begin
    { File level }
    TyColTreeGetText(Sender, Node1, Column, ttNormal, t1);
    TyColTreeGetText(Sender, Node2, Column, ttNormal, t2);
    case Column of
      1: begin
           { Sort by raw byte size for correct numeric ordering }
           s1 := ColTreeChildSizes[Integer(Node1^.Parent^.Index)][Integer(Node1^.Index)];
           s2 := ColTreeChildSizes[Integer(Node2^.Parent^.Index)][Integer(Node2^.Index)];
           if s1 < s2 then CompareResult := -1
           else if s1 > s2 then CompareResult := 1
           else CompareResult := 0;
         end;
    else
      CompareResult := CompareStr(t1, t2);
    end;
  end;
end;

end.
