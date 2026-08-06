unit umain;

{ Right-to-left mirroring and bidirectional text -- the LOOK-AT-IT example.

  Everything this window shows was built and verified headlessly, by pixel probes and pure
  geometry assertions (tests/test.rtl.pas, test.rtl.bars.pas, test.bidi.pas, test.edit.bidi.pas,
  test.memo.bidi.pas). A specific list of questions is structurally unreachable from a test
  here, and this example exists to make each of them answerable by a human with a mouse:

    - do Arabic letters actually SHAPE (join into their contextual forms) on GTK and Cocoa?
      The Windows answer was measured and pinned; the other two are the platform text engine's
      and only running there answers them;
    - does the status bar's size grip really resize from the BOTTOM-LEFT? It hands the OS
      HTBOTTOMLEFT and no headless test can confirm the OS obeys;
    - which way do submenus actually cascade? DoOpenSubmenu needs a live window handle;
    - anything involving LCL's align engine, which never runs for a form that was never shown;
    - and the whole class of "mirrored control that answers clicks on the old side" that no
      guard anticipated, which is found by clicking around.

  Layout is authored in umain.lfm. This unit does only the three things the .lfm cannot say:
  load and switch themes, answer the two virtual data models (the grid's tree and the tree
  view's nodes), and flip the direction.

  WHY THE DIRECTION SWITCH IS CODE. BiDiMode is deliberately NOT published on any control --
  tests/test.parity.pas (LyingPropertiesStayUnpublished) pins that, because mirroring is
  implemented for a MINORITY of the library and the Object Inspector must not offer a property
  most controls ignore. It works perfectly well from code, which is what DirSwitchChange does.
  That is behaviour, not design, so it belongs here; everything about LAYOUT stayed in the .lfm.

  Non-ASCII sample strings live in the .lfm in Lazarus's numeric escape form ('...'#1575#1604...)
  rather than as raw UTF-8 bytes. That keeps them declarative AND immune to a toolchain that has
  mangled non-ASCII source literals before. The LFM parser turns #NNNN into a widechar and the
  converter writes it back out as UTF-8 (verified by round-tripping this file through
  LRSObjectTextToBinary).

  Two more things about umain.lfm, both learned the hard way. It is NOT Pascal and takes no
  brace comments -- one makes the build fail in the resource step with "Wrong token type:
  Symbol expected", which is why the geometry note that belongs beside the title bar is here
  instead: the skin switcher's Left values stop 3 * TyTitleButtonWidth (= 138 px) short of
  the right edge, because the minimise / maximise / close buttons are painted there and a
  windowed control dropped on top of them wins. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Menus,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.TyLabel, tyControls.Divider, tyControls.Panel,
  tyControls.CheckBox, tyControls.GroupBox, tyControls.CheckGroup, tyControls.RadioGroup,
  tyControls.Button, tyControls.GlyphButtons, tyControls.ColorButton,
  tyControls.ComboBox, tyControls.ToggleSwitch, tyControls.Edit, tyControls.Memo,
  tyControls.IconFont, tyControls.Menu, tyControls.StatusBar,
  tyControls.PageControl, tyControls.TabSheet, tyControls.ScrollBox,
  tyControls.Columns, tyControls.Grid, tyControls.ListView, tyControls.TreeView;

type
  TMainForm = class(TTyForm)
    Surface: TTyFormSurface;
    TitleBar1: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    ThemeCombo: TTyComboBox;

    MenuBar1: TTyMenuBar;
    MainMenu1: TMainMenu;
    MnuFile: TMenuItem;
    MnuFileNew: TMenuItem;
    MnuFileOpen: TMenuItem;
    MnuFileSep: TMenuItem;
    MnuFileRecent: TMenuItem;
    MnuRecent1: TMenuItem;
    MnuRecent2: TMenuItem;
    MnuRecentMore: TMenuItem;
    MnuRecentOld1: TMenuItem;
    MnuRecentOld2: TMenuItem;
    MnuFileSep2: TMenuItem;
    MnuFileExit: TMenuItem;
    MnuEdit: TMenuItem;
    MnuEditCut: TMenuItem;
    MnuEditCopy: TMenuItem;
    MnuEditDisabled: TMenuItem;
    MnuDirection: TMenuItem;
    MnuDirLtr: TMenuItem;
    MnuDirRtl: TMenuItem;
    MnuHelpRight: TMenuItem;
    MnuHelpAbout: TMenuItem;

    Popup1: TTyMenuEx;
    PopHdr: TMenuItem;
    PopFirst: TMenuItem;
    PopSub: TMenuItem;
    PopSub1: TMenuItem;
    PopSub2: TMenuItem;
    PopSubDeep: TMenuItem;
    PopSubDeep1: TMenuItem;
    PopSep: TMenuItem;
    PopShortcut: TMenuItem;

    Icons: TTyIconFont;

    HeadPanel: TTyPanel;
    DirSwitch: TTyToggleSwitch;
    LblDirState: TTyLabel;
    LblLegend: TTyLabel;
    LblTry: TTyLabel;

    Pages: TTyPageControl;

    PgForm: TTyTabSheet;
    DivFormAll: TTyDivider;
    LblAlignLeft: TTyLabel;
    LblAlignRight: TTyLabel;
    LblAlignCenter: TTyLabel;
    ChkPlain: TTyCheckBox;
    ChkFlipped: TTyCheckBox;
    ChkGrayed: TTyCheckBox;
    RadOne: TTyRadioButton;
    RadTwo: TTyRadioButton;
    DivIndent: TTyDivider;
    PanelCap: TTyPanel;
    LblContainerNote: TTyLabel;
    RadGrp: TTyRadioGroup;
    ChkGrp: TTyCheckGroup;
    GrpBox: TTyGroupBox;
    LblGrpField: TTyLabel;
    EdGrp: TTyEdit;
    LblGrpNote: TTyLabel;
    LblGrpAfter: TTyLabel;
    BtnPlain: TTyButton;
    BtnCapLeft: TTyButton;
    BtnGlyphLeft: TTyGlyphButton;
    BtnGlyphRight: TTyGlyphButton;
    BtnColor: TTyColorButton;
    BtnBadge: TTyButton;
    DivGlyphNote: TTyDivider;
    LblFormNote: TTyLabel;

    PgData: TTyTabSheet;
    DivGrid: TTyDivider;
    Grid: TTyStringGrid;
    LblGridNote: TTyLabel;
    DivLv: TTyDivider;
    LV: TTyListView;
    DivTv: TTyDivider;
    Tree: TTyTreeView;
    LblDataNote: TTyLabel;

    PgText: TTyTabSheet;
    DivText: TTyDivider;
    LblArabic: TTyLabel;
    EdArabic: TTyEdit;
    MeArabic: TTyMemo;
    LblHebrew: TTyLabel;
    EdHebrew: TTyEdit;
    MeHebrew: TTyMemo;
    LblMixed: TTyLabel;
    EdMixed: TTyEdit;
    MeMixed: TTyMemo;
    LblChinese: TTyLabel;
    EdChinese: TTyEdit;
    MeChinese: TTyMemo;
    DivChrome: TTyDivider;
    LblTextNote: TTyLabel;
    DivScroll: TTyDivider;
    ScrollDemo: TTyScrollBox;
    SbBtn1: TTyButton;
    SbBtn2: TTyButton;
    SbBtn3: TTyButton;
    SbBtn4: TTyButton;
    SbBtn5: TTyButton;
    SbBtn6: TTyButton;
    LblScrollNote: TTyLabel;
    DivMini: TTyDivider;
    MiniPager: TTyPageControl;
    MpOne: TTyTabSheet;
    LblMpOne: TTyLabel;
    MpTwo: TTyTabSheet;
    LblMpTwo: TTyLabel;
    MpThree: TTyTabSheet;
    LblMpThree: TTyLabel;
    MpFour: TTyTabSheet;
    LblMpFour: TTyLabel;
    LblMiniNote: TTyLabel;

    StatusBar1: TTyStatusBar;

    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure DirSwitchChange(Sender: TObject);
    procedure MenuItemClicked(Sender: TObject);
    procedure MenuFileExitClick(Sender: TObject);
    procedure MenuDirectionClick(Sender: TObject);
    procedure GridCellButtonClick(Sender: TObject; ACol, ARow: Integer);
    procedure GridGetNodeLevel(Sender: TObject; ARow: Integer; var ALevel: Integer);
    procedure GridGetHasChildren(Sender: TObject; ARow: Integer; var AHas: Boolean);
    procedure TreeInitNode(Sender: TTyTreeView; ParentNode, Node: PTyTreeNode;
      var InitStates: TTyNodeInitStates);
    procedure TreeInitChildren(Sender: TTyTreeView; Node: PTyTreeNode;
      var ChildCount: Cardinal);
    procedure TreeGetText(Sender: TTyTreeView; Node: PTyTreeNode; Column: Integer;
      TextType: TTyVSTTextType; var CellText: string);
  private
    FApplying: Boolean;                 { re-entry guard: the menu and the switch drive each other }
    procedure FillGrid;
    procedure ApplyDirection(ARightToLeft: Boolean);
    procedure SetBiDiDeep(AControl: TControl; AMode: TBiDiMode);
    procedure Say(const AText: string);
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

{ ---------------------------------------------------------------- grid data --

  A flat row list with an explicit level column. The grid does NOT own a tree: it asks the
  host for each row's level and whether it has children, and owns only the collapsed set --
  which is why a million-row tree costs nothing to show. Levels here are hand-written so the
  chevron has something to draw and something to indent. }

type
  TDemoRow = record
    Level:  Integer;
    Name:   string;
    Region: string;
    Qty:    string;
    Done:   Boolean;
  end;

const
  DemoRows: array[0..10] of TDemoRow = (
    (Level: 0; Name: 'Middle East'; Region: 'MEA';    Qty: '640'; Done: True),
    (Level: 1; Name: 'Riyadh';      Region: 'SA';     Qty: '270'; Done: True),
    (Level: 1; Name: 'Cairo';       Region: 'EG';     Qty: '215'; Done: False),
    (Level: 1; Name: 'Dubai';       Region: 'AE';     Qty: '155'; Done: True),
    (Level: 0; Name: 'Europe';      Region: 'EU';     Qty: '430'; Done: False),
    (Level: 1; Name: 'Madrid';      Region: 'ES';     Qty: '245'; Done: True),
    (Level: 1; Name: 'Lisbon';      Region: 'PT';     Qty: '185'; Done: False),
    (Level: 0; Name: 'Asia';        Region: 'APAC';   Qty: '905'; Done: True),
    (Level: 1; Name: 'Tokyo';       Region: 'JP';     Qty: '480'; Done: True),
    (Level: 1; Name: 'Seoul';       Region: 'KR';     Qty: '300'; Done: False),
    (Level: 1; Name: 'Taipei';      Region: 'TW';     Qty: '125'; Done: False));

  TreeRoots: array[0..4] of string =
    ('Documents', 'Pictures', 'Music', 'Downloads', 'Projects');

  TreeKinds: array[0..4] of string =
    ('Folder', 'Folder', 'Playlist', 'Folder', 'Workspace');

procedure TMainForm.FillGrid;
var
  r: Integer;
begin
  Grid.BeginUpdate;
  try
    Grid.RowCount := Length(DemoRows);
    for r := 0 to High(DemoRows) do
    begin
      Grid.Cells[0, r] := DemoRows[r].Name;
      Grid.Cells[1, r] := DemoRows[r].Region;
      Grid.Cells[2, r] := DemoRows[r].Qty;
      { A gekCheckBox column stores its state as the column's ValueChecked /
        ValueUnchecked words -- '1' and '' by default. }
      if DemoRows[r].Done then Grid.Cells[3, r] := '1' else Grid.Cells[3, r] := '';
      Grid.Cells[4, r] := 'Open';
    end;
  finally
    Grid.EndUpdate;
  end;
end;

procedure TMainForm.GridGetNodeLevel(Sender: TObject; ARow: Integer; var ALevel: Integer);
begin
  if (ARow >= 0) and (ARow <= High(DemoRows)) then ALevel := DemoRows[ARow].Level;
end;

procedure TMainForm.GridGetHasChildren(Sender: TObject; ARow: Integer; var AHas: Boolean);
begin
  AHas := (ARow >= 0) and (ARow <= High(DemoRows)) and (DemoRows[ARow].Level = 0);
end;

procedure TMainForm.GridCellButtonClick(Sender: TObject; ACol, ARow: Integer);
begin
  { A button CELL. Under RTL it is drawn at the other end of the row -- this handler firing
    for the row you actually pressed is the half a headless test cannot ask about. }
  Say(Format('Grid button cell: column %d, row %d', [ACol, ARow]));
end;

{ ------------------------------------------------------------ tree view data --

  A virtual tree: nodes are never in the .lfm. Two roots' worth of children are synthesised
  on demand. This control does NOT mirror -- its expander stays on the left and its indent
  still grows rightwards -- and that is the point of putting it beside the grid. }

procedure TMainForm.TreeInitNode(Sender: TTyTreeView; ParentNode, Node: PTyTreeNode;
  var InitStates: TTyNodeInitStates);
begin
  if Sender.GetNodeLevel(Node) = 0 then
    Include(InitStates, ivsHasChildren);
end;

procedure TMainForm.TreeInitChildren(Sender: TTyTreeView; Node: PTyTreeNode;
  var ChildCount: Cardinal);
begin
  if Sender.GetNodeLevel(Node) = 0 then ChildCount := 3 else ChildCount := 0;
end;

procedure TMainForm.TreeGetText(Sender: TTyTreeView; Node: PTyTreeNode; Column: Integer;
  TextType: TTyVSTTextType; var CellText: string);
var
  lvl, idx: Integer;
begin
  if TextType <> ttNormal then begin CellText := ''; Exit; end;
  lvl := Sender.GetNodeLevel(Node);
  idx := Integer(Node^.Index);
  if lvl = 0 then
  begin
    if (idx >= 0) and (idx <= High(TreeRoots)) then
      case Column of
        0: CellText := TreeRoots[idx];
        1: CellText := TreeKinds[idx];
      end;
  end
  else
    case Column of
      0: CellText := Format('child %d', [idx + 1]);
      1: CellText := 'File';
    end;
end;

{ ------------------------------------------------------------------ chrome ---- }

procedure TMainForm.Say(const AText: string);
begin
  if StatusBar1.Panels.Count > 0 then
    TTyStatusPanel(StatusBar1.Panels.Items[0]).Text := AText;
end;

procedure TMainForm.FormCreate(Sender: TObject);
var
  names: TStringArray;
  i: Integer;
begin
  { Built-in themes are compiled in, so the switcher works without locating a themes/ folder. }
  TyRegisterBuiltinThemes;
  TyDefaultController.ThemeName := 'default';
  ApplyChromeTheme(TyDefaultController);      { title bar + window rounded corners/shadow }
  names := TyBuiltinThemeNames;
  for i := 0 to High(names) do
    ThemeCombo.Items.Add(names[i]);
  ThemeCombo.ItemIndex := ThemeCombo.Items.IndexOf('default');

  FillGrid;
  Say('Ready - flip "Right-to-left" and start clicking.');
end;

procedure TMainForm.ThemeComboChange(Sender: TObject);
begin
  if ThemeCombo.ItemIndex < 0 then Exit;
  TyDefaultController.ThemeName := ThemeCombo.Items[ThemeCombo.ItemIndex];
  ApplyChromeTheme(TyDefaultController);      { re-theme the shell on every skin change }
end;

procedure TMainForm.DarkSwitchChange(Sender: TObject);
begin
  if DarkSwitch.Checked then
    TyDefaultController.Mode := 'dark'
  else
    TyDefaultController.Mode := 'light';
  ApplyChromeTheme(TyDefaultController);
end;

{ --------------------------------------------------------------- direction ---- }

{ Force BiDiMode on every control in the tree.

  Setting it on the form alone would be ENOUGH for a form whose controls all still have
  ParentBiDiMode = True: LCL propagates through CM_PARENTBIDIMODECHANGED. Walking is
  belt-and-braces -- it also reaches anything that has turned that flag off, and it makes the
  mechanism visible in a file whose whole job is to be read. Note that assigning BiDiMode
  clears ParentBiDiMode on each control, which is exactly what we want here. }
procedure TMainForm.SetBiDiDeep(AControl: TControl; AMode: TBiDiMode);
var
  i: Integer;
  wc: TWinControl;
begin
  if AControl = nil then Exit;
  AControl.BiDiMode := AMode;
  if AControl is TWinControl then
  begin
    wc := TWinControl(AControl);
    for i := 0 to wc.ControlCount - 1 do
      SetBiDiDeep(wc.Controls[i], AMode);
  end;
end;

procedure TMainForm.ApplyDirection(ARightToLeft: Boolean);
var
  m: TBiDiMode;
begin
  if FApplying then Exit;
  FApplying := True;
  try
    if ARightToLeft then m := bdRightToLeft else m := bdLeftToRight;

    { The form first: a TTyPopupMenu has no BiDiMode of its own and reads the control it was
      raised on, so the hosts have to be right before any popup opens. }
    BiDiMode := m;
    SetBiDiDeep(Surface, m);

    { Keep the two ways of asking for the same thing in step. }
    DirSwitch.Checked := ARightToLeft;
    MnuDirLtr.Checked := not ARightToLeft;
    MnuDirRtl.Checked := ARightToLeft;

    if ARightToLeft then
    begin
      LblDirState.Caption := 'Direction: RIGHT-TO-LEFT (bdRightToLeft)';
      if StatusBar1.Panels.Count > 1 then
        TTyStatusPanel(StatusBar1.Panels.Items[1]).Text := 'right-to-left';
      if StatusBar1.Panels.Count > 2 then
        TTyStatusPanel(StatusBar1.Panels.Items[2]).Text := '<- drag the grip';
      Say('Right-to-left. The grip is now at the BOTTOM-LEFT corner - drag it.');
    end
    else
    begin
      LblDirState.Caption := 'Direction: left-to-right (bdLeftToRight)';
      if StatusBar1.Panels.Count > 1 then
        TTyStatusPanel(StatusBar1.Panels.Items[1]).Text := 'left-to-right';
      if StatusBar1.Panels.Count > 2 then
        TTyStatusPanel(StatusBar1.Panels.Items[2]).Text := 'drag the grip ->';
      Say('Left-to-right.');
    end;

    Invalidate;
  finally
    FApplying := False;
  end;
end;

procedure TMainForm.DirSwitchChange(Sender: TObject);
begin
  ApplyDirection(DirSwitch.Checked);
end;

procedure TMainForm.MenuDirectionClick(Sender: TObject);
begin
  ApplyDirection(Sender = MnuDirRtl);
end;

procedure TMainForm.MenuItemClicked(Sender: TObject);
begin
  { Reporting WHICH item was chosen is the point: a mirrored menu that highlights one row and
    activates another is exactly the defect this window exists to expose. }
  if Sender is TMenuItem then
    Say('Menu: ' + StripHotkey(TMenuItem(Sender).Caption));
end;

procedure TMainForm.MenuFileExitClick(Sender: TObject);
begin
  Close;
end;

end.
