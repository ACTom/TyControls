unit umain;

{ TTyToolWindowBar / TTyToolWindowManager demo -- an IDE-style workbench:
    - left side bar: Explorer / Search; right side bar: Outline; under the editor: a bottom bar
      with Problems / Output / Terminal. The editor and the bottom bar share one alClient panel
      (EditorHost), so the bottom bar sits under the editor only (the VS Code look).
    - drag a side-bar icon to the other side bar; drag icons / tabs within a bar to reorder;
      drag a bar's inner edge to resize it, or past half its minimum to collapse it.
    - the layout (sizes, collapsed, order, current page) is read in FormCreate and saved in
      FormClose; the Layout menu saves / loads / resets it without restarting.
    - right-click a side-bar icon: "Move to Other Side" (ContextWindow + UsableBar + MoveWindow);
      right-click a bottom-bar tab: maximize / restore, hide the panel.
    - two buttons call the manager from INSIDE a tool window: Outline's "move to the other side"
      and Explorer's "reset layout". Once the form is showing, those calls are queued -- the
      Output log shows MoveWindow returning while Outline is still in its old bar.
    - the Diagnostics menu exists for checks only a real machine can make: a modal dialog or a
      popup menu opening in the middle of a drag, and a disabled current page.
  Every event goes to the Output page's log. The window, the bars, their windows and every
  menu are designed in umain.lfm (a TTyForm + TTyTitleBar); the code here is event handlers,
  theme setup and the layout file. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, Controls, Menus, ExtCtrls, Dialogs,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.Panel, tyControls.ComboBox, tyControls.ToggleSwitch, tyControls.Menu,
  tyControls.Edit, tyControls.ListBox, tyControls.Memo, tyControls.TreeView,
  tyControls.GlyphButtons, tyControls.Icons.Lucide, tyControls.Dialogs,
  tyControls.ToolWindows, tyControls.ToolWindows.Manager;

type
  TDiagAction = (daNone, daDialog, daMenu);

  TMainForm = class(TTyForm)
    Surface: TTyFormSurface;
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    ThemeCombo: TTyComboBox;
    MainMenuBar: TTyMenuBar;
    LeftBar: TTyToolWindowBar;
    ExplorerWin: TTyToolWindow;
    ExplorerActions: TTyToolWindowActions;
    BtnResetLayout: TTySpeedButton;
    ExplorerTree: TTyTreeView;
    SearchWin: TTyToolWindow;
    SearchEdit: TTyEdit;
    SearchList: TTyListBox;
    RightBar: TTyToolWindowBar;
    OutlineWin: TTyToolWindow;
    OutlineActions: TTyToolWindowActions;
    BtnOutlineMove: TTySpeedButton;
    OutlineList: TTyListBox;
    EditorHost: TTyPanel;
    BottomBar: TTyToolWindowBar;
    ProblemsWin: TTyToolWindow;
    ProblemsList: TTyListBox;
    OutputWin: TTyToolWindow;
    OutputActions: TTyToolWindowActions;
    OutputFilter: TTyEdit;
    BtnOutputClear: TTySpeedButton;
    OutputMemo: TTyMemo;
    TerminalWin: TTyToolWindow;
    TerminalActions: TTyToolWindowActions;
    BtnTermNew: TTySpeedButton;
    BtnTermClose: TTySpeedButton;
    BtnTermMore: TTySpeedButton;
    TerminalMemo: TTyMemo;
    EditorMemo: TTyMemo;
    ToolMgr: TTyToolWindowManager;
    Icons: TTyLucideImageList;
    LucideFont: TTyLucideIconFont;
    MainMenu1: TMainMenu;
    MnuFile: TMenuItem;
    MnuFileExit: TMenuItem;
    MnuView: TMenuItem;
    MnuViewBottom: TMenuItem;
    MnuViewSep1: TMenuItem;
    MnuViewDensity: TMenuItem;
    MnuDensityClassic: TMenuItem;
    MnuDensityModern: TMenuItem;
    MnuLayout: TMenuItem;
    MnuLayoutSave: TMenuItem;
    MnuLayoutLoad: TMenuItem;
    MnuLayoutReset: TMenuItem;
    MnuDiag: TMenuItem;
    MnuDiagDialog: TMenuItem;
    MnuDiagMenu: TMenuItem;
    MnuDiagSep1: TMenuItem;
    MnuDiagDisable: TMenuItem;
    StripMenu: TTyPopupMenu;
    MnuStripMove: TMenuItem;
    PanelMenu: TTyPopupMenu;
    MnuPanelMax: TMenuItem;
    MnuPanelHide: TMenuItem;
    DiagTimer: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormDestroy(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure MnuFileExitClick(Sender: TObject);
    procedure MnuViewBottomClick(Sender: TObject);
    procedure MnuDensityClassicClick(Sender: TObject);
    procedure MnuDensityModernClick(Sender: TObject);
    procedure MnuLayoutSaveClick(Sender: TObject);
    procedure MnuLayoutLoadClick(Sender: TObject);
    procedure MnuLayoutResetClick(Sender: TObject);
    procedure MnuDiagDialogClick(Sender: TObject);
    procedure MnuDiagMenuClick(Sender: TObject);
    procedure MnuDiagDisableClick(Sender: TObject);
    procedure DiagTimerTimer(Sender: TObject);
    procedure SideBarContextPopup(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
    procedure MnuStripMoveClick(Sender: TObject);
    procedure BottomBarContextPopup(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
    procedure MnuPanelMaxClick(Sender: TObject);
    procedure MnuPanelHideClick(Sender: TObject);
    procedure BtnOutlineMoveClick(Sender: TObject);
    procedure BtnResetLayoutClick(Sender: TObject);
    procedure BtnOutputClearClick(Sender: TObject);
    procedure OutputFilterChange(Sender: TObject);
    procedure BtnTermNewClick(Sender: TObject);
    procedure BtnTermCloseClick(Sender: TObject);
    procedure BtnTermMoreClick(Sender: TObject);
    procedure ToolMgrWindowMoved(Sender: TObject; AWindow: TTyToolWindow;
      ASourceBar: TTyToolWindowBar; AOldIndex: Integer);
    procedure ToolMgrLayoutApplied(Sender: TObject);
    procedure BarChange(Sender: TObject);
    procedure BottomBarCollapse(Sender: TObject);
    procedure BottomBarExpand(Sender: TObject);
  private
    FLogLines: TStringList;
    FDiagAction: TDiagAction;
    { The window and the target the strip menu was opened for (worked out in the side bar's
      OnContextPopup, which fires before the bar pops its PopupMenu up). }
    FStripWindow: TTyToolWindow;
    FStripTarget: TTyToolWindowBar;
    procedure Log(const S: string);
    procedure RefreshLog;
    { Caption of the panel menu's first item follows the bottom bar's state. }
    procedure UpdatePanelMenu;
    { The usable bar on the other side of ABar (left <-> right); nil for the bottom bar or when
      that side has no usable bar. }
    function OtherSideOf(ABar: TTyToolWindowBar): TTyToolWindowBar;
    function LayoutFile: string;
    procedure SaveLayoutFile;
    procedure LoadLayoutFile;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

resourcestring
  rsReady           = 'Ready';
  rsActiveFmt       = '%s: active = %s';
  rsNoWindow        = '(none)';
  rsCollapsedFmt    = '%s: collapsed';
  rsExpandedFmt     = '%s: expanded';
  rsMovedFmt        = 'moved %s from %s (#%d)';
  rsLayoutApplied   = 'layout applied';
  rsLayoutSavedFmt  = 'layout saved to %s';
  rsLayoutMissing   = 'no saved layout yet';
  rsLayoutRejected  = 'the saved layout was not applied';
  rsLayoutErrorFmt  = 'layout file error: %s';
  rsResetRejected   = 'ResetLayout returned False';
  rsMoveCalledFmt   = 'MoveWindow returned %s; Outline is in %s right now';
  rsMoveNoTarget    = 'no usable bar on the other side';
  rsMaximize        = 'Maximize';
  rsRestore         = 'Restore';
  rsDiagArmedFmt    = 'in 3 s: %s -- start dragging an icon now and keep the button down';
  rsDiagDialogName  = 'a modal dialog';
  rsDiagMenuName    = 'a popup menu';
  rsDiagDialog      = 'This dialog opened in the middle of whatever you were doing. ' +
                      'A drag in progress should have been cancelled.';
  rsDiagDisabledFmt = 'Output page enabled = %s';
  rsTermNew         = '(a real app would open a new terminal here)';
  rsTermClose       = '(a real app would close this terminal here)';
  rsTermMore        = '(a real app would show more terminal actions here)';

procedure TMainForm.FormCreate(Sender: TObject);
var
  names: TStringArray;
  i: Integer;
begin
  // Built-in themes are compiled in, so the switcher works without locating a themes/ folder.
  TyRegisterBuiltinThemes;
  names := TyBuiltinThemeNames;
  for i := 0 to High(names) do
    ThemeCombo.Items.Add(names[i]);
  ThemeCombo.ItemIndex := ThemeCombo.Items.IndexOf('default');
  TyDefaultController.ThemeName := 'default';
  ApplyChromeTheme(TyDefaultController);
  // Initial checks live here, not in the .lfm (a streamed Checked would fire handlers early).
  MnuDensityClassic.Checked := TyDefaultController.Density = tdClassic;
  MnuDensityModern.Checked := TyDefaultController.Density = tdModern;
  FLogLines := TStringList.Create;
  Log(rsReady);
  // Read the user's layout in FormCreate: the form is not showing yet, so it applies at once.
  // The pages made current while the .lfm loaded got no OnShow; the layout fires OnShow /
  // OnHide only for the pages it shows or hides. A window that fills itself in OnShow needs
  // filling here too.
  LoadLayoutFile;
  // After the layout, not before: it may have collapsed the bottom bar, and a layout fires no
  // OnCollapse / OnExpand. ToolMgrLayoutApplied does the same for later loads and resets; this
  // line covers the first run, when there is no layout file.
  MnuViewBottom.Checked := not BottomBar.Collapsed;
end;

procedure TMainForm.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  SaveLayoutFile;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  FreeAndNil(FLogLines);
end;

procedure TMainForm.ThemeComboChange(Sender: TObject);
begin
  if ThemeCombo.ItemIndex < 0 then Exit;
  TyDefaultController.ThemeName := ThemeCombo.Items[ThemeCombo.ItemIndex];
  ApplyChromeTheme(TyDefaultController);
end;

procedure TMainForm.DarkSwitchChange(Sender: TObject);
begin
  if DarkSwitch.Checked then
    TyDefaultController.Mode := 'dark'
  else
    TyDefaultController.Mode := 'light';
  ApplyChromeTheme(TyDefaultController);
end;

{ ---- log ---- }

procedure TMainForm.Log(const S: string);
begin
  if FLogLines = nil then Exit;
  FLogLines.Add(S);
  RefreshLog;
end;

procedure TMainForm.RefreshLog;
var
  i: Integer;
  key: string;
  shown: TStringList;
begin
  if FLogLines = nil then Exit;
  key := LowerCase(Trim(OutputFilter.Text));
  shown := TStringList.Create;
  try
    for i := 0 to FLogLines.Count - 1 do
      if (key = '') or (Pos(key, LowerCase(FLogLines[i])) > 0) then
        shown.Add(FLogLines[i]);
    OutputMemo.Lines.Assign(shown);
  finally
    shown.Free;
  end;
end;

procedure TMainForm.OutputFilterChange(Sender: TObject);
begin
  RefreshLog;
end;

procedure TMainForm.BtnOutputClearClick(Sender: TObject);
begin
  if FLogLines = nil then Exit;
  FLogLines.Clear;
  RefreshLog;
end;

{ ---- events of the bars and the manager ---- }

procedure TMainForm.BarChange(Sender: TObject);
var
  b: TTyToolWindowBar;
  nm: string;
begin
  // Not fired at start-up, at design time or while a layout is applied.
  b := Sender as TTyToolWindowBar;
  if b.ActiveWindow <> nil then nm := b.ActiveWindow.Name else nm := rsNoWindow;
  Log(Format(rsActiveFmt, [b.Name, nm]));
end;

procedure TMainForm.BottomBarCollapse(Sender: TObject);
begin
  // The tab row's hide button and a snap-collapse on the edge land here too.
  MnuViewBottom.Checked := False;
  Log(Format(rsCollapsedFmt, [BottomBar.Name]));
end;

procedure TMainForm.BottomBarExpand(Sender: TObject);
begin
  MnuViewBottom.Checked := True;
  Log(Format(rsExpandedFmt, [BottomBar.Name]));
end;

procedure TMainForm.ToolMgrWindowMoved(Sender: TObject; AWindow: TTyToolWindow;
  ASourceBar: TTyToolWindowBar; AOldIndex: Integer);
begin
  // Gestures, MoveWindow and WindowIndex report here; reading a layout does not.
  Log(Format(rsMovedFmt, [AWindow.Name, ASourceBar.Name, AOldIndex]));
end;

procedure TMainForm.ToolMgrLayoutApplied(Sender: TObject);
begin
  // A layout (Load / Reset) fires no OnCollapse / OnExpand: whatever mirrors the bars' state
  // is brought up to date here, once, after the whole layout is in place.
  MnuViewBottom.Checked := not BottomBar.Collapsed;
  Log(rsLayoutApplied);
end;

{ ---- View menu ---- }

procedure TMainForm.MnuFileExitClick(Sender: TObject);
begin
  Close;
end;

procedure TMainForm.MnuViewBottomClick(Sender: TObject);
begin
  // A collapsed bottom bar leaves nothing on screen to bring it back: the app gives the switch.
  BottomBar.Collapsed := not BottomBar.Collapsed;
  MnuViewBottom.Checked := not BottomBar.Collapsed;
end;

procedure TMainForm.MnuDensityClassicClick(Sender: TObject);
begin
  TyDefaultController.Density := tdClassic;
  MnuDensityClassic.Checked := True;
end;

procedure TMainForm.MnuDensityModernClick(Sender: TObject);
begin
  TyDefaultController.Density := tdModern;
  MnuDensityModern.Checked := True;
end;

{ ---- layout ---- }

function TMainForm.LayoutFile: string;
begin
  Result := GetAppConfigDir(False) + 'toolwindows.layout';
end;

procedure TMainForm.SaveLayoutFile;
var
  sl: TStringList;
begin
  sl := TStringList.Create;
  try
    try
      ForceDirectories(GetAppConfigDir(False));
      sl.Text := ToolMgr.SaveLayoutToString;
      sl.SaveToFile(LayoutFile);
      Log(Format(rsLayoutSavedFmt, [LayoutFile]));
    except
      on E: Exception do Log(Format(rsLayoutErrorFmt, [E.Message]));
    end;
  finally
    sl.Free;
  end;
end;

procedure TMainForm.LoadLayoutFile;
var
  sl: TStringList;
begin
  if not FileExists(LayoutFile) then
  begin
    Log(rsLayoutMissing);
    Exit;
  end;
  sl := TStringList.Create;
  try
    try
      sl.LoadFromFile(LayoutFile);
      // The trailing line break TStringList adds is stripped by LoadLayoutFromString itself.
      if not ToolMgr.LoadLayoutFromString(sl.Text) then Log(rsLayoutRejected);
    except
      on E: Exception do Log(Format(rsLayoutErrorFmt, [E.Message]));
    end;
  finally
    sl.Free;
  end;
end;

procedure TMainForm.MnuLayoutSaveClick(Sender: TObject);
begin
  SaveLayoutFile;
end;

procedure TMainForm.MnuLayoutLoadClick(Sender: TObject);
begin
  LoadLayoutFile;
end;

procedure TMainForm.MnuLayoutResetClick(Sender: TObject);
begin
  if not ToolMgr.ResetLayout then Log(rsResetRejected);
end;

{ ---- moving windows ---- }

function TMainForm.OtherSideOf(ABar: TTyToolWindowBar): TTyToolWindowBar;
begin
  Result := nil;
  if ABar = nil then Exit;
  case ABar.Placement of
    twpLeft:  Result := ToolMgr.UsableBar(twpRight);
    twpRight: Result := ToolMgr.UsableBar(twpLeft);
  end;
end;

procedure TMainForm.SideBarContextPopup(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
var
  b: TTyToolWindowBar;
begin
  // The bar only gets here -- and only pops StripMenu up -- when the right-click is on an icon;
  // anywhere else the request bubbles to the form. ContextWindow says which icon.
  b := Sender as TTyToolWindowBar;
  FStripWindow := b.ContextWindow;
  FStripTarget := OtherSideOf(b);
  MnuStripMove.Enabled := (FStripWindow <> nil) and (FStripTarget <> nil)
    and ToolMgr.CanMoveWindow(FStripWindow, FStripTarget);
end;

procedure TMainForm.MnuStripMoveClick(Sender: TObject);
begin
  if (FStripWindow = nil) or (FStripTarget = nil) then Exit;
  ToolMgr.MoveWindow(FStripWindow, FStripTarget);
end;

procedure TMainForm.BtnOutlineMoveClick(Sender: TObject);
var
  target: TTyToolWindowBar;
  ok: Boolean;
begin
  // The button sits inside the window it moves. The form is showing, so MoveWindow queues the
  // move: it answers True while Outline is still in its old bar, and "moved" follows later.
  target := OtherSideOf(OutlineWin.Bar);
  if target = nil then
  begin
    Log(rsMoveNoTarget);
    Exit;
  end;
  ok := ToolMgr.MoveWindow(OutlineWin, target);
  Log(Format(rsMoveCalledFmt, [BoolToStr(ok, True), OutlineWin.Bar.Name]));
end;

procedure TMainForm.BtnResetLayoutClick(Sender: TObject);
begin
  // Also inside a tool window: the reset is queued for the same reason.
  if not ToolMgr.ResetLayout then Log(rsResetRejected);
end;

{ ---- bottom panel menu ---- }

procedure TMainForm.UpdatePanelMenu;
begin
  if BottomBar.Maximized then MnuPanelMax.Caption := rsRestore
  else MnuPanelMax.Caption := rsMaximize;
end;

procedure TMainForm.BottomBarContextPopup(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
begin
  // A right-click on a tab reaches the bar's OnContextPopup (ContextWindow = that tab's window),
  // then the bar pops PanelMenu up. Elsewhere on the tab row nothing pops up.
  UpdatePanelMenu;
end;

procedure TMainForm.MnuPanelMaxClick(Sender: TObject);
begin
  BottomBar.Maximized := not BottomBar.Maximized;
end;

procedure TMainForm.MnuPanelHideClick(Sender: TObject);
begin
  BottomBar.Collapsed := True;
end;

{ ---- terminal buttons (they only fill the actions area) ---- }

procedure TMainForm.BtnTermNewClick(Sender: TObject);
begin
  TerminalMemo.Lines.Add(rsTermNew);
end;

procedure TMainForm.BtnTermCloseClick(Sender: TObject);
begin
  TerminalMemo.Lines.Add(rsTermClose);
end;

procedure TMainForm.BtnTermMoreClick(Sender: TObject);
begin
  TerminalMemo.Lines.Add(rsTermMore);
end;

{ ---- diagnostics ---- }

procedure TMainForm.MnuDiagDialogClick(Sender: TObject);
begin
  FDiagAction := daDialog;
  Log(Format(rsDiagArmedFmt, [rsDiagDialogName]));
  DiagTimer.Enabled := False;
  DiagTimer.Enabled := True;
end;

procedure TMainForm.MnuDiagMenuClick(Sender: TObject);
begin
  FDiagAction := daMenu;
  Log(Format(rsDiagArmedFmt, [rsDiagMenuName]));
  DiagTimer.Enabled := False;
  DiagTimer.Enabled := True;
end;

procedure TMainForm.DiagTimerTimer(Sender: TObject);
var
  act: TDiagAction;
begin
  DiagTimer.Enabled := False;
  act := FDiagAction;
  FDiagAction := daNone;
  case act of
    daDialog: TyMessageDlg(rsDiagDialog, mtInformation, [mbOK]);
    daMenu:
      begin
        UpdatePanelMenu;
        PanelMenu.PopUp(Mouse.CursorPos.X, Mouse.CursorPos.Y);
      end;
  end;
end;

procedure TMainForm.MnuDiagDisableClick(Sender: TObject);
begin
  // The docs say: disable the controls in a page, never the tool window itself. This shows why
  // -- with the current page disabled, the tab row it draws stops answering too.
  OutputWin.Enabled := not OutputWin.Enabled;
  MnuDiagDisable.Checked := not OutputWin.Enabled;
  Log(Format(rsDiagDisabledFmt, [BoolToStr(OutputWin.Enabled, True)]));
end;

end.
