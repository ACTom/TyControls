unit mainform;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, Menus, ComCtrls,
  tyControls.Controller, tyControls.Types, tyControls.Css.Values,
  tyControls.Button, tyControls.TyLabel, tyControls.Edit,
  tyControls.CheckBox, tyControls.Panel, tyControls.ComboBox,
  tyControls.ScrollBar, tyControls.Form, tyControls.ListBox,
  tyControls.ProgressBar, tyControls.ToggleSwitch, tyControls.TrackBar,
  tyControls.GroupBox, tyControls.PageControl, tyControls.TabSheet,
  tyControls.SpinEdit, tyControls.Memo, tyControls.Menu,
  tyControls.BuiltinThemes, tyControls.ThemeRegistry, tyControls.NativeStyler, tyControls.ToolBar,
  tyControls.StatusBar, tyControls.Splitter, tyControls.TabSet,
  tyControls.Calendar, tyControls.DateTimePicker, tyControls.TreeView,
  tyControls.Columns, tyControls.Dialogs,
  tyControls.Dialogs.SelectPath, tyControls.Dialogs.Color,
  tyControls.Dialogs.Font, tyControls.Dialogs.Find, tyControls.Dialogs.Progress,
  tyControls.Dialogs.About,
  tyControls.LinkLabel, tyControls.ShadowLabel, tyControls.GlowLabel,
  tyControls.IconFont, tyControls.CharImage, tyControls.GlyphButtons,
  tyControls.DropButtons, tyControls.ColorButton, tyControls.ButtonGroup,
  tyControls.Hint,
  tyControls.Gauge, tyControls.Meter, tyControls.CircularProgress,
  tyControls.ActivityIndicator, tyControls.Rating, tyControls.Sparkline,
  tyControls.Chart, tyControls.Grid;
type

  { TDemoMainForm — ALL controls live in the designer (mainform.lfm), including the docked
    TTyTitleBar, the theme switcher (ThemeCombo + appearance buttons + random), the
    PageControl's pages, TTySpinEdit and TTyMemo. Code only does logic (data + handlers);
    it NEVER creates UI controls (project rule: demo UI is edited in the .lfm only). }

  TDemoMainForm = class(TTyForm)
    Surface: TTyFormSurface;
    BtnDanger: TTyButton;
    BtnDlgAbout: TTyButton;
    BtnPrimary: TTyButton;
    Calendar1: TTyCalendar;
    ChkAgree: TTyCheckBox;
    ComboKind: TTyComboBox;
    TabSet2: TTyTabSet;
    TriCheck: TTyCheckBox;
    EditCombo: TTyComboBox;
    TabSet1: TTyTabSet;
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
    TyAboutDlg: TTyAboutDialog;
    TyButton1: TTyButton;
    TyButton2: TTyButton;
    TyButton3: TTyButton;
    TyButton4: TTyButton;
    BtnDlgInput: TTyButton;
    BtnDlgPassword: TTyButton;
    BtnDlgText: TTyButton;
    BtnDlgSelValue: TTyButton;
    BtnDlgColor: TTyButton;
    BtnDlgFont: TTyButton;
    BtnDlgFind: TTyButton;
    BtnDlgReplace: TTyButton;
    BtnDlgProgress: TTyButton;
    BtnMsgWarn: TTyButton;
    BtnMsgError: TTyButton;
    BtnMsgConfirm: TTyButton;
    FindDlg: TTyFindDialog;
    ReplaceDlg: TTyReplaceDialog;
    ProgressDlg: TTyProgressDialog;
    TyController: TTyStyleController;
    TyEdit1: TTyEdit;
    TyMessage1: TTyMessage;
    TyNativeStyler1: TTyNativeStyler;
    TyPanel1: TTyPanel;
    TySelectPathDialog1: TTySelectPathDialog;
    TyTabSheet1: TTyTabSheet;
    TyTabSheet2: TTyTabSheet;
    TyTabSheet3: TTyTabSheet;
    TyTabSheet5: TTyTabSheet;
    TyTitleBar1: TTyTitleBar;
    ToolBar1: TTyToolBar;
    TbBtnNew: TTyButton;
    TbSep1: TTyToolSeparator;
    TbBtnOpen: TTyButton;
    TbSep2: TTyToolSeparator;
    LblDensity: TTyLabel;
    DensityCombo: TTyComboBox;
    TbSep3: TTyToolSeparator;
    ChkHotReload: TTyCheckBox;
    StatusBar1: TTyStatusBar;
    SidePanel: TTyPanel;
    Splitter1: TTySplitter;
    ThemeCombo: TTyComboBox;
    BtnApLight: TTyButton;
    BtnApDark: TTyButton;
    BtnApAuto: TTyButton;
    BtnAccent: TTyButton;
    BtnAccentReset: TTyButton;
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
    TyTabSheet6: TTyTabSheet;
    TyTabSheet7: TTyTabSheet;
    DemoIconFont: TTyIconFont;
    DemoHint: TTyHint;
    DemoGlyphBtn: TTyGlyphButton;
    DemoGlyphContainer: TTyGlyphContainerButton;
    DemoSpeed1: TTySpeedButton;
    DemoSpeed2: TTySpeedButton;
    DemoSpeed3: TTySpeedButton;
    DemoDropBtn: TTyDropDownButton;
    DemoMenuBtn: TTyMenuButton;
    DemoColorBtn: TTyColorButton;
    DemoBtnGroup: TTyButtonGroup;
    DemoLinkLabel: TTyLinkLabel;
    DemoShadowLabel: TTyShadowLabel;
    DemoGlowLabel: TTyGlowLabel;
    DemoCharImage: TTyCharImage;
    HintNote: TTyLabel;
    ChkNativeFontName: TTyCheckBox;
    ChkNativeFontSize: TTyCheckBox;
    ChkNativeSkipTree: TTyCheckBox;
    TyTabSheetGauges: TTyTabSheet;
    LblGauge: TTyLabel;
    DemoGauge: TTyGauge;
    LblMeter: TTyLabel;
    DemoMeter: TTyMeter;
    LblCircular: TTyLabel;
    DemoCircular: TTyCircularProgress;
    LblActivity: TTyLabel;
    DemoActivity: TTyActivityIndicator;
    DemoRating: TTyRating;
    LblSpark: TTyLabel;
    DemoSpark: TTySparkline;
    DemoChart: TTyChart;
    TyTabSheetGrid: TTyTabSheet;
    LblGridHint: TTyLabel;
    DemoGrid: TTyStringGrid;
    procedure BtnDlgAboutClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    { Assign the string-typed captions (tab sheets, group box) from resourcestrings — the
      LFM translator cannot reach them. See the resourcestring block. }
    procedure LocalizeTexts;
    procedure TyButton4Click(Sender: TObject);
    procedure TyTree1InitNode(Sender: TTyTreeView; ParentNode, Node: PTyTreeNode;
      var InitStates: TTyNodeInitStates);
    procedure TyTree1InitChildren(Sender: TTyTreeView; Node: PTyTreeNode;
      var ChildCount: Cardinal);
    procedure TyTree1GetText(Sender: TTyTreeView; Node: PTyTreeNode;
      var AText: string);
    { Fills the NATIVE LCL TreeView on the 'Native' tab. Built in code, not streamed:
      TTreeNodes stores design-time nodes as an `Items.Data` binary blob and, although LCL
      does define that pseudo-property (TTreeNodes.DefineProperties), the IDE's LFM checker
      does not honour DefineProperties — it rejects the whole form with "identifier Data not
      found in class TTreeNodes" and offers to strip it, so the demo would not open in the
      IDE. Building here also keeps the labels translatable; the blob hid untranslated text. }
    procedure BuildNativeTree;
    { Multi-column sortable tree handlers }
    procedure TyColTreeInitNode(Sender: TTyTreeView; ParentNode, Node: PTyTreeNode;
      var InitStates: TTyNodeInitStates);
    procedure TyColTreeInitChildren(Sender: TTyTreeView; Node: PTyTreeNode;
      var ChildCount: Cardinal);
    procedure TyColTreeGetText(Sender: TTyTreeView; Node: PTyTreeNode;
      Column: Integer; TextType: TTyVSTTextType; var CellText: string);
    procedure TyColTreeCompareNodes(Sender: TTyTreeView; Node1, Node2: PTyTreeNode;
      Column: Integer; var CompareResult: Integer);
    procedure TyColTreeChecked(Sender: TTyTreeView; Node: PTyTreeNode);
    procedure TyColTreeSelectionChanged(Sender: TObject);
    procedure GroupBox1Click(Sender: TObject);
    procedure MnuViewToggleClick(Sender: TObject);
    procedure MnuFileExitClick(Sender: TObject);
    procedure PopupCtxHelloClick(Sender: TObject);
    procedure PopupCtxAgreeClick(Sender: TObject);
    procedure TrackBar1Change(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    { The two other theme axes the controller owns, on the toolbar next to the theme box:
      density (classic / modern geometry) and the theme-file watch. }
    procedure DensityComboChange(Sender: TObject);
    procedure ChkHotReloadChange(Sender: TObject);
    { 'Native' tab: the styler's opt-in font propagation + its per-control hook. }
    procedure ChkNativeFontChange(Sender: TObject);
    procedure ChkNativeSkipTreeChange(Sender: TObject);
    procedure NativeStylerStyleControl(Sender: TObject; AControl: TControl;
      var AHandled: Boolean);
    procedure ApLightClick(Sender: TObject);
    procedure ApDarkClick(Sender: TObject);
    procedure ApAutoClick(Sender: TObject);
    procedure RandomClick(Sender: TObject);
    procedure PickAccent(Sender: TObject);
    procedure ResetAccentClick(Sender: TObject);
    procedure TyButton1Click(Sender: TObject);
    procedure TyButton3Click(Sender: TObject);
    procedure BtnDlgInputClick(Sender: TObject);
    procedure BtnDlgPasswordClick(Sender: TObject);
    procedure BtnDlgTextClick(Sender: TObject);
    procedure BtnDlgSelValueClick(Sender: TObject);
    procedure BtnDlgColorClick(Sender: TObject);
    procedure BtnDlgFontClick(Sender: TObject);
    procedure BtnDlgFindClick(Sender: TObject);
    procedure BtnDlgReplaceClick(Sender: TObject);
    procedure BtnDlgProgressClick(Sender: TObject);
    procedure BtnMsgWarnClick(Sender: TObject);
    procedure BtnMsgErrorClick(Sender: TObject);
    procedure BtnMsgConfirmClick(Sender: TObject);
    procedure FindDlgFind(Sender: TObject);
    procedure ReplaceDlgReplace(Sender: TObject);
    procedure ProgressDlgCancel(Sender: TObject);
  private
    function ThemeDir: string;
    procedure InitThemes;
    procedure InitColTree;
    procedure InitInstruments;   // the sparkline series (no published Values property)
    procedure InitDemoGrid;      // the 'Grid' tab's columns + rows
    { One TTyMessage variant: set DlgType/Buttons, run it, then put the component back
      exactly as the .lfm streamed it so the plain 'MessageBox' button is unaffected. }
    procedure ShowMessageVariant(ADlgType: TMsgDlgType; AButtons: TMsgDlgButtons;
      const AMsg: string);
    procedure ApplyBuiltin(const AName: string);
    procedure UpdateAccentBtn;   // enable "Reset" only while a user accent override is active
    procedure UpdateHotReloadChk;  // the file watch only arms while a theme FILE is loaded
    procedure PickCustomTheme(Data: PtrInt);   // deferred: opening the modal file dialog straight from
                                               // the combo's OnChange crashes on Qt6 (the still-open
                                               // dropdown popup is the modal's focus-restore target)
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
  { TTyTabSheet.Caption and TTyGroupBox.Caption are declared `string`, not TCaption, and LCL's
    LFM translator only walks TCaption properties — so these never translate from the .lfm no
    matter what the .po says. Push them in from resourcestrings instead (LocalizeTexts). }
  rsDemoTab1     = 'Tab 1';
  rsDemoTab2     = 'Tab 2';
  rsDemoTab3     = 'Tab 3';
  rsDemoTabTree  = 'Tree';
  rsDemoTabNative = 'Native';
  rsDemoTabCmd   = 'Command buttons';
  rsDemoTabIcons = 'Icons · text';
  rsDemoTabGauges = 'Gauges';
  rsDemoTabGrid  = 'Grid';
  rsDemoOptions  = 'Options';
  rsDemoNativeNode = 'Item %d';
  { Message-box variants — the text is what makes the DlgType icon read as the right one. }
  rsDemoMsgWarn    = 'Disk space is running low.';
  rsDemoMsgError   = 'The file could not be opened.';
  rsDemoMsgConfirm = 'Save the changes before closing?';
  rsWatchingFmt   = 'Watching %s';
  rsWatchOff      = 'Theme watch off';
  rsDensityFmt    = 'Density: %s';
  rsAccentTitle   = 'Accent';
  rsDlgInput      = 'Input';
  rsDlgInputAsk   = 'Enter some text:';
  rsDlgPassword   = 'Password';
  rsDlgPasswordAsk = 'Enter a password:';
  rsPwdCharsFmt   = 'Password: %d chars';
  rsDlgText       = 'Text';
  rsDlgTextAsk    = 'Enter a note:';
  rsDlgSelValue   = 'SelValue';
  rsDlgSelValueAsk = 'Pick a value:';
  rsSelectedFmt   = 'Selected: %s';
  rsDlgColor      = 'Color';
  rsWorkingFmt    = 'Working… %d%%';
  rsProgCancelled = 'Progress: cancelled';
  rsProgDone      = 'Progress: done';
  rsAnswerOk      = 'OK';
  rsAnswerCancel  = 'Cancel';
  rsAnswerYes     = 'Yes';
  rsAnswerNo      = 'No';
  rsMessageFmt    = 'Message: %s';
  rsFindFmt       = 'Find: %s';
  rsReplaceFmt    = 'Replace "%s" -> "%s"';
  rsReplaceAll    = ' (all)';
  rsProgCancelReq = 'Progress: cancel requested';
  rsVirtNodeFmt   = 'Node %d  (L%d)';
  rsFolderDocuments = 'Documents';
  rsFolderPictures  = 'Pictures';
  rsFolderProjects  = 'Projects';
  rsColName     = 'Name';
  rsColSize     = 'Size';
  rsColModified = 'Modified';
  rsCheckedFmt  = 'Checked: %s';
  rsReady       = 'Ready';
  rsSelCountFmt = 'Selected: %d item(s)';
  rsColOrder    = 'Order';
  rsColRegion   = 'Region';
  rsColProduct  = 'Product';
  rsColAmount   = 'Amount';
  rsRegionNorth = 'North';
  rsRegionSouth = 'South';
  rsRegionEast  = 'East';
  rsRegionWest  = 'West';
  rsProdWidget  = 'Widget';
  rsProdGadget  = 'Gadget';
  rsProdSprocket = 'Sprocket';
  rsProdCog     = 'Cog';
  rsProdFlange  = 'Flange';

function TDemoMainForm.ThemeDir: string;
var
  Dir: string;
  i: Integer;
begin
  // Walk up from the exe directory looking for themes/ (handles the project dir / lib/<cpu>-<os>/ / a macOS .app bundle).
  Dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  for i := 1 to 8 do
  begin
    if DirectoryExists(Dir + 'themes') then
      Exit(Dir + 'themes' + PathDelim);
    Dir := ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
    if Dir = '' then Break;
  end;
  Result := 'themes' + PathDelim; // fallback: relative to the current directory
end;

procedure TDemoMainForm.TrackBar1Change(Sender: TObject);
begin
  if Assigned(Progress1) then
    Progress1.Position := TrackBar1.Position;
end;

procedure TDemoMainForm.LocalizeTexts;
begin
  TyTabSheet1.Caption := rsDemoTab1;
  TyTabSheet2.Caption := rsDemoTab2;
  TyTabSheet3.Caption := rsDemoTab3;
  TyTabSheet4.Caption := rsDemoTabTree;
  TyTabSheet5.Caption := rsDemoTabNative;
  TyTabSheet6.Caption := rsDemoTabCmd;
  TyTabSheet7.Caption := rsDemoTabIcons;
  TyTabSheetGauges.Caption := rsDemoTabGauges;
  TyTabSheetGrid.Caption := rsDemoTabGrid;
  GroupBox1.Caption := rsDemoOptions;
end;

procedure TDemoMainForm.FormCreate(Sender: TObject);
begin
  LocalizeTexts;
  BuildNativeTree;            // the 'Native' tab's LCL TreeView — see BuildNativeTree's note
  Randomize;                  // seed the "random theme" button
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
  InitInstruments;            // the sparkline series — its samples are not a published property
  InitDemoGrid;               // the 'Grid' tab's columns + rows (same reason as InitColTree)
end;

procedure TDemoMainForm.BtnDlgAboutClick(Sender: TObject);
begin
  TyAboutDlg.Execute;
end;

procedure TDemoMainForm.TyButton4Click(Sender: TObject);
begin
  TySelectPathDialog1.Execute;
end;

procedure TDemoMainForm.GroupBox1Click(Sender: TObject);
begin

end;

procedure TDemoMainForm.InitThemes;
var
  names: TStringArray;
  i: Integer;
  base: string;
begin
  // All controls come from the .lfm; this only fills data + sets initial state, never creates controls.
  TyRegisterBuiltinThemes;                    // default + system + every structural skin (all compiled in)
  names := TyBuiltinThemeNames;               // default, system, classic, office, xp, win11, … (compiled in)
  ThemeCombo.Items.Clear;
  for i := 0 to High(names) do ThemeCombo.Items.Add(names[i]);
  // Publish any extra theme FILE dropped in themes/ (curated palettes, the green image demo) too.
  names := TyRegisterThemeDir(ThemeDir);
  for i := 0 to High(names) do
  begin
    base := LowerCase(names[i]);
    if (base = 'auto') or (base = 'light') or (base = 'dark')
       or (base = 'default') or (base = 'system') then Continue;
    if ThemeCombo.Items.IndexOf(names[i]) < 0 then ThemeCombo.Items.Add(names[i]);
  end;
  ThemeCombo.Items.Add(rsDemoThemeCustom);
  ThemeCombo.ItemIndex := 0;                 // default
  ApplyBuiltin('default');
  SetAppearance(tfFollowSystem, '', BtnApAuto);   // initial appearance: follow the system
end;

procedure TDemoMainForm.ApplyBuiltin(const AName: string);
begin
  // Swap the theme only; leave Follow/Mode alone (the appearance axis is owned by the tri-state buttons).
  TyController.ThemeName := AName;
  ApplyChromeTheme(TyController);
  UpdateAccentBtn;   // a theme switch clears any accent override (D2)
  UpdateHotReloadChk;  // ThemeName clears ThemeFile, so there is nothing left to watch
end;

procedure TDemoMainForm.UpdateAccentBtn;
begin
  BtnAccentReset.Enabled := TyController.AccentOverride <> '';
end;

{ HotReload polls a theme FILE, so a compiled-in built-in has nothing on disk to watch:
  the switch arms only while ThemeFile is set, and disarms itself the moment a built-in
  theme replaces the file. That dependency is the thing worth seeing. }
procedure TDemoMainForm.UpdateHotReloadChk;
begin
  ChkHotReload.Enabled := TyController.ThemeFile <> '';
  if (not ChkHotReload.Enabled) and ChkHotReload.Checked then
    ChkHotReload.Checked := False;    // OnChange disarms the controller
end;

procedure TDemoMainForm.ChkHotReloadChange(Sender: TObject);
begin
  TyController.HotReload := ChkHotReload.Checked;
  if ChkHotReload.Checked then
    StatusBar1.Panels[0].Text := Format(rsWatchingFmt, [ExtractFileName(TyController.ThemeFile)])
  else
    StatusBar1.Panels[0].Text := rsWatchOff;
end;

{ The density axis: same skin, other geometry pack. Switching it reloads the theme layer, so
  every control on the form re-measures (heights, paddings, tab and row bands) at once. }
procedure TDemoMainForm.DensityComboChange(Sender: TObject);
begin
  // Streaming ItemIndex fires OnChange while the .lfm is still being read, and TyController
  // is declared after the surface — so it is not there yet on that first call.
  if TyController = nil then Exit;
  if DensityCombo.ItemIndex = 1 then
    TyController.Density := tdModern
  else
    TyController.Density := tdClassic;
  ApplyChromeTheme(TyController);
  StatusBar1.Panels[0].Text := Format(rsDensityFmt, [DensityCombo.Text]);
end;

{ 'Native' tab. The styler always recolours; family and size are opt-in because pushing a
  theme font onto arbitrary third-party controls is the risky half. Apply re-walks now. }
procedure TDemoMainForm.ChkNativeFontChange(Sender: TObject);
begin
  TyNativeStyler1.ApplyFontName := ChkNativeFontName.Checked;
  TyNativeStyler1.ApplyFontSize := ChkNativeFontSize.Checked;
  TyNativeStyler1.Apply;
end;

procedure TDemoMainForm.ChkNativeSkipTreeChange(Sender: TObject);
begin
  TyNativeStyler1.Apply;   // unticking it re-styles the tree; ticking it leaves it where it is
end;

{ The per-control hook, fired for every candidate BEFORE the styler touches it. Setting
  AHandled opts that one control out — the rest of the form still follows the theme. }
procedure TDemoMainForm.NativeStylerStyleControl(Sender: TObject; AControl: TControl;
  var AHandled: Boolean);
begin
  AHandled := ChkNativeSkipTree.Checked and (AControl = TreeView1);
end;

{ Runtime accent picker: recolour any theme on the fly (independent of light/dark). The whole
  interactive palette re-derives from the one --accent seed; the pick clears on a theme switch. }
procedure TDemoMainForm.PickAccent(Sender: TObject);
var col: TColor; alpha: Byte; c: TTyColor; hex: string;
begin
  alpha := 255;
  if TyController.AccentOverride <> '' then          // seed the picker with the current pick
  begin
    c := TyParseColor(TyController.AccentOverride);
    col := RGBToColor(TyRedOf(c), TyGreenOf(c), TyBlueOf(c));
  end
  else
    col := RGBToColor($33, $66, $CC);
  if TySelectColor(rsAccentTitle, col, alpha) then
  begin
    hex := '#' + IntToHex(Red(col), 2) + IntToHex(Green(col), 2) + IntToHex(Blue(col), 2);
    TyController.SetAccent(hex);                      // recolours every registered control + chrome
    ApplyChromeTheme(TyController);
    UpdateAccentBtn;
  end;
end;

procedure TDemoMainForm.ResetAccentClick(Sender: TObject);
begin
  TyController.ResetAccent;                           // back to the theme's own accent
  ApplyChromeTheme(TyController);
  UpdateAccentBtn;
end;

procedure TDemoMainForm.ThemeComboChange(Sender: TObject);
var idx: Integer;
begin
  idx := ThemeCombo.ItemIndex;
  if idx < 0 then Exit;
  if ThemeCombo.Items[idx] = rsDemoThemeCustom then
    // Defer the modal so the combo's dropdown popup finishes closing first: opening it synchronously
    // here makes the popup the modal's focus-restore target, and on Qt6 restoring focus to the now-
    // hidden popup raises EInvalidOperation '[TCustomForm.SetFocus] Cannot focus' (the codebase's
    // ColorComboBox / ValueListEditor open their dialogs the same deferred way for the same reason).
    Application.QueueAsyncCall(@PickCustomTheme, 0)
  else
    ApplyBuiltin(ThemeCombo.Items[idx]);
end;

procedure TDemoMainForm.PickCustomTheme(Data: PtrInt);
var dlg: TOpenDialog;
begin
  // The dropdown is still open at this deferred point (its own DeferredCloseUp is queued AFTER this
  // one), so close it synchronously now -- before the modal -- or the still-open popup becomes the
  // modal's focus-restore target and Qt6 crashes / freezes on close.
  ThemeCombo.CloseUp;
  dlg := TOpenDialog.Create(Self);
  try
    dlg.Filter := rsDemoThemeFilter;
    dlg.InitialDir := ThemeDir;
    if dlg.Execute then
    begin
      TyController.ThemeFile := dlg.FileName;   // custom file (REPLACE)
      ApplyChromeTheme(TyController);
      UpdateAccentBtn;                          // REPLACE clears the accent override (D2)
      UpdateHotReloadChk;                       // a file theme is what HotReload can watch
    end;
  finally dlg.Free; end;
end;

procedure TDemoMainForm.SetAppearance(AFollow: TTyThemeFollow; const AMode: string;
  ASelected: TTyButton);
begin
  TyController.Follow := AFollow;
  if AFollow = tfManual then TyController.Mode := AMode;   // when following the system, the OS decides Mode
  // Mutually exclusive tri-state: highlight the current appearance via the ghost buttons' Down state.
  BtnApLight.Down := (ASelected = BtnApLight);
  BtnApDark.Down  := (ASelected = BtnApDark);
  BtnApAuto.Down  := (ASelected = BtnApAuto);
  ApplyChromeTheme(TyController);
end;

procedure TDemoMainForm.ApLightClick(Sender: TObject);
begin SetAppearance(tfManual, 'light', BtnApLight); end;

procedure TDemoMainForm.ApDarkClick(Sender: TObject);
begin SetAppearance(tfManual, 'dark', BtnApDark); end;

{ The third state the tri-state was always missing: hand the appearance back to the OS. From
  here Mode is owned by the system scheme, and TTyForm's live hook re-pulls it when it flips. }
procedure TDemoMainForm.ApAutoClick(Sender: TObject);
begin SetAppearance(tfFollowSystem, '', BtnApAuto); end;

procedure TDemoMainForm.RandomClick(Sender: TObject);
begin

end;

procedure TDemoMainForm.TyButton1Click(Sender: TObject);
begin
  TyMessage1.Execute;
end;

procedure TDemoMainForm.TyButton3Click(Sender: TObject);
begin
  TyButton3.Caption := TyButton3.Caption + '1';
end;

{ ---------------------------------------------------------------------------
  Dialog demo handlers — one per PanelBox button. Each shows the result in
  LblHello.Caption or StatusBar1.Panels[0].Text so the effect is visible.
  --------------------------------------------------------------------------- }

procedure TDemoMainForm.BtnDlgInputClick(Sender: TObject);
var s: string;
begin
  s := LblHello.Caption;
  if TyInputQuery(rsDlgInput, rsDlgInputAsk, s) then
    LblHello.Caption := s;
end;

procedure TDemoMainForm.BtnDlgPasswordClick(Sender: TObject);
var pwd: string;
begin
  pwd := TyPasswordBox(rsDlgPassword, rsDlgPasswordAsk);
  if pwd <> '' then
    StatusBar1.Panels[0].Text := Format(rsPwdCharsFmt, [Length(pwd)]);
end;

procedure TDemoMainForm.BtnDlgTextClick(Sender: TObject);
var note: string;
begin
  note := LblHello.Caption;
  if TyTextQuery(rsDlgText, rsDlgTextAsk, note) then
    LblHello.Caption := TrimRight(note);   // TyTextQuery result ends with a LineEnding
end;

procedure TDemoMainForm.BtnDlgSelValueClick(Sender: TObject);
var items: TStringList; idx: Integer;
begin
  items := TStringList.Create;
  try
    items.Add('Alpha');
    items.Add('Beta');
    items.Add('Gamma');
    items.Add('Delta');
    idx := 0;
    if TySelectValue(rsDlgSelValue, rsDlgSelValueAsk, items, idx) then
      LblHello.Caption := Format(rsSelectedFmt, [items[idx]]);
  finally
    items.Free;
  end;
end;

procedure TDemoMainForm.BtnDlgColorClick(Sender: TObject);
var col: TColor; alpha: Byte;
begin
  col := LblHello.Font.Color;
  alpha := 255;
  if TySelectColor(rsDlgColor, col, alpha) then
  begin
    LblHello.Font.Color := col;
    LblHello.Invalidate;
  end;
end;

procedure TDemoMainForm.BtnDlgFontClick(Sender: TObject);
begin
  if TyFontDialog(LblHello.Font) then
    LblHello.Invalidate;   // font updated in-place
end;

procedure TDemoMainForm.BtnDlgFindClick(Sender: TObject);
begin
  FindDlg.Execute;   // modeless — returns immediately, OnFind fires on Find
end;

procedure TDemoMainForm.BtnDlgReplaceClick(Sender: TObject);
begin
  ReplaceDlg.Execute;
end;

procedure TDemoMainForm.BtnDlgProgressClick(Sender: TObject);
var i, j: Integer; x: Double;
begin
  ProgressDlg.Min := 0;
  ProgressDlg.Max := 100;
  ProgressDlg.Cancelable := True;
  ProgressDlg.Show;
  try
    for i := 0 to 100 do
    begin
      if ProgressDlg.Cancelled then Break;
      // small busy-wait so the bar visibly advances
      x := 0;
      for j := 1 to 400000 do x := x + Sqrt(j);
      ProgressDlg.SetProgress(i, Format(rsWorkingFmt, [i]));
    end;
  finally
    ProgressDlg.Close;
  end;
  if ProgressDlg.Cancelled then
    StatusBar1.Panels[0].Text := rsProgCancelled
  else
    StatusBar1.Panels[0].Text := rsProgDone;
end;

{ TTyMessage is streamed with the plain information/OK pair; DlgType picks the icon and
  Buttons picks the row, and Execute hands back which one was pressed. }
procedure TDemoMainForm.ShowMessageVariant(ADlgType: TMsgDlgType;
  AButtons: TMsgDlgButtons; const AMsg: string);
var
  mr: TModalResult;
  oldMsg, answer: string;
begin
  mr := mrNone;
  oldMsg := TyMessage1.Msg;
  TyMessage1.DlgType := ADlgType;
  TyMessage1.Buttons := AButtons;
  TyMessage1.Msg := AMsg;
  try
    mr := TyMessage1.Execute;
  finally
    // put the component back the way the .lfm streamed it, so the plain 'MessageBox'
    // button next door keeps popping the information/OK box it always did
    TyMessage1.Msg := oldMsg;
    TyMessage1.DlgType := mtInformation;
    TyMessage1.Buttons := [mbOK];
  end;
  case mr of
    mrOk:     answer := rsAnswerOk;
    mrCancel: answer := rsAnswerCancel;
    mrYes:    answer := rsAnswerYes;
    mrNo:     answer := rsAnswerNo;
  else
    answer := IntToStr(mr);
  end;
  StatusBar1.Panels[0].Text := Format(rsMessageFmt, [answer]);
end;

procedure TDemoMainForm.BtnMsgWarnClick(Sender: TObject);
begin
  ShowMessageVariant(mtWarning, [mbOK], rsDemoMsgWarn);
end;

procedure TDemoMainForm.BtnMsgErrorClick(Sender: TObject);
begin
  ShowMessageVariant(mtError, [mbOK], rsDemoMsgError);
end;

procedure TDemoMainForm.BtnMsgConfirmClick(Sender: TObject);
begin
  ShowMessageVariant(mtConfirmation, [mbYes, mbNo], rsDemoMsgConfirm);
end;

procedure TDemoMainForm.FindDlgFind(Sender: TObject);
begin
  StatusBar1.Panels[0].Text := Format(rsFindFmt, [FindDlg.FindText]);
end;

procedure TDemoMainForm.ReplaceDlgReplace(Sender: TObject);
var s: string;
begin
  s := Format(rsReplaceFmt, [ReplaceDlg.FindText, ReplaceDlg.ReplaceText]);
  if frReplaceAll in ReplaceDlg.Options then s := s + rsReplaceAll;
  StatusBar1.Panels[0].Text := s;
end;

procedure TDemoMainForm.ProgressDlgCancel(Sender: TObject);
begin
  // MUST NOT Free ProgressDlg here — the busy loop reads Cancelled and calls Close.
  StatusBar1.Panels[0].Text := rsProgCancelReq;
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

procedure TDemoMainForm.BuildNativeTree;
var
  i, j: Integer;
  root: TTreeNode;
begin
  TreeView1.Items.BeginUpdate;
  try
    TreeView1.Items.Clear;
    for i := 1 to 4 do
    begin
      root := TreeView1.Items.Add(nil, Format(rsDemoNativeNode, [i]));
      for j := 1 to 3 do
        TreeView1.Items.AddChild(root, Format(rsDemoNativeNode, [i * 10 + j]));
    end;
    if TreeView1.Items.Count > 0 then TreeView1.Items[0].Expand(False);
  finally
    TreeView1.Items.EndUpdate;
  end;
end;

procedure TDemoMainForm.TyTree1GetText(Sender: TTyTreeView; Node: PTyTreeNode;
  var AText: string);
begin
  AText := Format(rsVirtNodeFmt, [Node^.Index, Sender.GetNodeLevel(Node)]);
end;

{ ---------------------------------------------------------------------------
  Multi-column sortable tree — small curated file-tree dataset
  3 folders x ~4-5 children.
  Column 0 = Name (folder/file name)
  Column 1 = Size (bytes as string; '' for folders)
  Column 2 = Modified (date as string)

  FIX 6: Each node stores a STABLE key in its data blob (TColNode) so that
  after a column sort (which re-stamps Node^.Index with the new position) the
  data handlers still read the original source-array indices and the rows show
  the correct content.  Without this, GetText/Compare/InitChildren all keyed on
  the mutable Node^.Index, making every sort appear to do nothing.
  --------------------------------------------------------------------------- }

type
  TColNode  = record FolderIdx, ChildIdx: Integer; end;
  PColNode  = ^TColNode;

{ Display names for the folder table: a typed const cannot hold resourcestrings,
  so the mapper translates at the moment the name becomes visible text. }
function ColTreeFolderDisplay(AIndex: Integer): string;
begin
  case AIndex of
    0: Result := rsFolderDocuments;
    1: Result := rsFolderPictures;
  else Result := rsFolderProjects;
  end;
end;

const

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
  col: TTyColumn;
begin
  { FIX 6: each node stores a stable TColNode key so sort does not scramble data }
  TyColTree.NodeDataSize := SizeOf(TColNode);
  { E4: enable checkboxes + multi-select + full-row hit + tri-state tracking }
  TyColTree.Options := [toCheckSupport, toMultiSelect, toAutoTristateTracking,
                        toFullRowSelect];
  { E4: wire status display handlers }
  TyColTree.OnChecked          := @TyColTreeChecked;
  TyColTree.OnSelectionChanged := @TyColTreeSelectionChanged;

  with TyColTree.Header do
  begin
    Options := [hoVisible, hoColumnResize, hoShowSortGlyphs,
                hoHeaderClickAutoSort, hoDrag];
    MainColumn := 0;
    { Column 0: Name }
    col := Columns.Add as TTyColumn;
    col.Text := rsColName;
    col.Width := 180;
    col.Alignment := taLeftJustify;
    { Column 1: Size }
    col := Columns.Add as TTyColumn;
    col.Text := rsColSize;
    col.Width := 80;
    col.Alignment := taRightJustify;
    { Column 2: Modified }
    col := Columns.Add as TTyColumn;
    col.Text := rsColModified;
    col.Width := 120;
    col.Alignment := taLeftJustify;
  end;
  TyColTree.RootNodeCount := 3;
end;

procedure TDemoMainForm.TyColTreeInitNode(Sender: TTyTreeView;
  ParentNode, Node: PTyTreeNode; var InitStates: TTyNodeInitStates);
var
  level: Integer;
  data:  PColNode;
  parentData: PColNode;
begin
  level := Sender.GetNodeLevel(Node);
  data  := PColNode(Sender.GetNodeData(Node));
  if level = 0 then
  begin
    { Top-level nodes (folders) always have children. }
    Include(InitStates, ivsHasChildren);
    { E4: folder → tri-state checkbox so it reflects children state }
    Node^.CheckType := ctTriStateCheckBox;
    { FIX 6: store stable key — Node^.Index is still the original position here }
    if data <> nil then
    begin
      data^.FolderIdx := Integer(Node^.Index);
      data^.ChildIdx  := -1;
    end;
  end
  else
  begin
    { E4: level-1 children —
        "Projects" folder (index 2) uses radio buttons (one active project);
        Documents + Pictures use plain checkboxes. }
    { FIX 6: read parent's STORED FolderIdx so it survives parent reorder too }
    parentData := PColNode(Sender.GetNodeData(ParentNode));
    if (parentData <> nil) and (parentData^.FolderIdx = 2) then
      Node^.CheckType := ctRadioButton
    else
      Node^.CheckType := ctCheckBox;
    { FIX 6: store stable child key — use parent's stored FolderIdx when available }
    if data <> nil then
    begin
      if parentData <> nil then
        data^.FolderIdx := parentData^.FolderIdx
      else
        data^.FolderIdx := Integer(ParentNode^.Index);
      data^.ChildIdx  := Integer(Node^.Index);
    end;
  end;
end;

procedure TDemoMainForm.TyColTreeInitChildren(Sender: TTyTreeView;
  Node: PTyTreeNode; var ChildCount: Cardinal);
var
  data:      PColNode;
  folderIdx: Integer;
begin
  { FIX 6: use stored FolderIdx so expand still works after folder row is sorted }
  data := PColNode(Sender.GetNodeData(Node));
  if data <> nil then
    folderIdx := data^.FolderIdx
  else
    folderIdx := Integer(Node^.Index);  { fallback (shouldn't happen) }
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
  data: PColNode;
  sz: Integer;
begin
  if TextType <> ttNormal then begin CellText := ''; Exit; end;

  { FIX 6: read stable keys from the node data blob, not from Node^.Index
    (which is re-stamped by the sort engine to reflect the new position). }
  data := PColNode(Sender.GetNodeData(Node));
  level := Sender.GetNodeLevel(Node);
  if level = 0 then
  begin
    { Folder row }
    if data <> nil then folderIdx := data^.FolderIdx
    else folderIdx := Integer(Node^.Index);
    case Column of
      0: CellText := ColTreeFolderDisplay(folderIdx);
      1: CellText := '';                          { folders have no size }
      2: CellText := ColTreeFolderDates[folderIdx];
    else
      CellText := '';
    end;
  end
  else
  begin
    { File row }
    if data <> nil then
    begin
      folderIdx := data^.FolderIdx;
      childIdx  := data^.ChildIdx;
    end
    else
    begin
      folderIdx := Integer(Node^.Parent^.Index);
      childIdx  := Integer(Node^.Index);
    end;
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
  t1, t2:    string;
  s1, s2:    Integer;
  lv:        Integer;
  d1, d2:    PColNode;
  fi1, fi2:  Integer;
  ci1, ci2:  Integer;
begin
  { Both nodes must be at the same level for sort to compare them.
    Within the same parent the column determines the key.
    FIX 6: read stable keys from the node data blob. }
  lv := Sender.GetNodeLevel(Node1);
  d1 := PColNode(Sender.GetNodeData(Node1));
  d2 := PColNode(Sender.GetNodeData(Node2));
  if lv = 0 then
  begin
    if d1 <> nil then fi1 := d1^.FolderIdx else fi1 := Integer(Node1^.Index);
    if d2 <> nil then fi2 := d2^.FolderIdx else fi2 := Integer(Node2^.Index);
    { Folder level: only Name and Modified are meaningful }
    case Column of
      0: CompareResult := CompareStr(ColTreeFolderDisplay(fi1), ColTreeFolderDisplay(fi2));
      2: CompareResult := CompareStr(ColTreeFolderDates[fi1], ColTreeFolderDates[fi2]);
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
           if d1 <> nil then begin fi1 := d1^.FolderIdx; ci1 := d1^.ChildIdx; end
           else begin fi1 := Integer(Node1^.Parent^.Index); ci1 := Integer(Node1^.Index); end;
           if d2 <> nil then begin fi2 := d2^.FolderIdx; ci2 := d2^.ChildIdx; end
           else begin fi2 := Integer(Node2^.Parent^.Index); ci2 := Integer(Node2^.Index); end;
           s1 := ColTreeChildSizes[fi1][ci1];
           s2 := ColTreeChildSizes[fi2][ci2];
           if s1 < s2 then CompareResult := -1
           else if s1 > s2 then CompareResult := 1
           else CompareResult := 0;
         end;
    else
      CompareResult := CompareStr(t1, t2);
    end;
  end;
end;

{ E4: update StatusBar panel 0 after a checkbox toggle.
  Shows the name of the toggled node (column 0 text). }
procedure TDemoMainForm.TyColTreeChecked(Sender: TTyTreeView; Node: PTyTreeNode);
var
  nodeName: string;
begin
  nodeName := '';
  TyColTreeGetText(Sender, Node, 0, ttNormal, nodeName);
  StatusBar1.Panels[0].Text := Format(rsCheckedFmt, [nodeName]);
end;

{ E4: update StatusBar panel 0 after the multi-select set changes. }
procedure TDemoMainForm.TyColTreeSelectionChanged(Sender: TObject);
var
  n: Integer;
begin
  n := TyColTree.SelectedCount;
  if n = 0 then
    StatusBar1.Panels[0].Text := rsReady
  else
    StatusBar1.Panels[0].Text := Format(rsSelCountFmt, [n]);
end;

{ ---------------------------------------------------------------------------
  'Gauges' and 'Grid' tabs — every control and every setting comes from the
  .lfm; only the two things a .lfm cannot carry are built here.
  --------------------------------------------------------------------------- }

procedure TDemoMainForm.InitInstruments;
{ The sparkline keeps its samples in a private array reached through SetValues — it has no
  published series property, so this one series is the tab's only code-built data. }
const
  cSparkSeries: array[0..15] of Double =
    (12, 15, 11, 18, 22, 19, 25, 21, 28, 24, 30, 27, 33, 29, 36, 31);
begin
  DemoSpark.SetValues(cSparkSeries);
end;

procedure TDemoMainForm.InitDemoGrid;
{ Columns are a TCollection and the rows are data: same documented exception as InitColTree —
  hand-writing a TPersistent hierarchy into the .lfm is error-prone, the code path is simpler
  and equally correct as long as it runs before the first paint. }
var
  col: TTyColumn;
  r: Integer;

  function GridRegion(AIndex: Integer): string;
  begin
    case AIndex mod 4 of
      0: Result := rsRegionNorth;
      1: Result := rsRegionSouth;
      2: Result := rsRegionEast;
    else Result := rsRegionWest;
    end;
  end;

  function GridProduct(AIndex: Integer): string;
  begin
    case AIndex mod 5 of
      0: Result := rsProdWidget;
      1: Result := rsProdGadget;
      2: Result := rsProdSprocket;
      3: Result := rsProdCog;
    else Result := rsProdFlange;
    end;
  end;

begin
  with DemoGrid.Header do
  begin
    Options := [hoVisible, hoColumnResize, hoShowSortGlyphs, hoHeaderClickAutoSort];
    col := Columns.Add as TTyColumn;
    col.Text := rsColOrder;
    col.Width := 120;
    col := Columns.Add as TTyColumn;
    col.Text := rsColRegion;
    col.Width := 100;
    col := Columns.Add as TTyColumn;
    col.Text := rsColProduct;
    col.Width := 130;
    col := Columns.Add as TTyColumn;
    col.Text := rsColAmount;
    col.Width := 110;
    col.Alignment := taRightJustify;
  end;
  DemoGrid.RowCount := 20;
  for r := 0 to DemoGrid.RowCount - 1 do
  begin
    DemoGrid.Cells[0, r] := Format('SO-%d', [1001 + r]);
    DemoGrid.Cells[1, r] := GridRegion(r);
    DemoGrid.Cells[2, r] := GridProduct(r);
    DemoGrid.Cells[3, r] := Format('%.2f', [120.5 + r * 37.25]);
  end;
end;

end.
