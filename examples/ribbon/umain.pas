unit umain;

{ Ribbon showcase = an MSO-style multi-tab plain-text editor, used to genuinely stress-test
  how complete the Ribbon components are.
  Title bar (QAT: save/undo/redo) -> Ribbon (File tab opens the backstage; Home/Insert/View
  three tabs, with groups + command buttons/drop-downs/color/segmented/gallery) -> multi-document
  tab area (one TTyMemo per document) -> status bar.
  File New/Open/Save/Save As/Close/Recent do real on-disk reads and writes; Cut/Copy/Paste/
  Undo/Redo/Select All/Find act on the current document; everything else (format painter,
  B/I/U, alignment, table, symbol...) is a placeholder but the UI is complete.

  The window, title bar and theme switcher are designed in umain.lfm (a TTyForm + TTyTitleBar).
  Everything else -- the ribbon, its pages/groups/command buttons, the QAT, the backstage, the
  document tabs and the status bar -- is a dynamic control tree that cannot be expressed as .lfm
  objects (icons assigned from a code-built collection, command lists filled in loops, ribbon
  pages/groups created via method calls), so it is built in FormCreate code (see BuildEditor).

  WARNING LCL layout pitfall: the title bar and the ribbon are both alTop siblings. The title
  bar now streams from the .lfm FIRST, so the ribbon is given an explicit Top to dock BELOW it;
  ribbon groups are likewise added right-to-left. See memory lcl-code-created-align-order. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, Forms, Controls, Dialogs, Graphics,
  tyControls.Types, tyControls.Controller, tyControls.BuiltinThemes, tyControls.ThemeRegistry,
  tyControls.Form, tyControls.Hint, tyControls.Panel,
  tyControls.TyLabel, tyControls.Button, tyControls.CheckBox, tyControls.ComboBox, tyControls.ToggleSwitch,
  tyControls.ImageCollection, tyControls.GlyphButtons, tyControls.DropButtons,
  tyControls.ColorButton, tyControls.ButtonGroup, tyControls.Ribbon,
  tyControls.RibbonQuickAccess, tyControls.RibbonGallery, tyControls.RibbonBackstage,
  tyControls.PageControl, tyControls.TabSheet, tyControls.Memo, tyControls.StatusBar,
  tyControls.Dialogs, tyControls.Dialogs.Find, tyControls.Dialogs.Color,
  uicons;

type
  { One open document: its tab sheet + memo + on-disk path. }
  TEditorDoc = class
    Sheet: TTyTabSheet;
    Memo: TTyMemo;
    FilePath: string;
  end;

  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    ThemeCombo: TTyComboBox;                   // title-bar built-in skin switcher
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
  private
    FImgColl: TTyImageCollection;   // cross-platform BGRA command icons (uicons)
    FRibbon: TTyRibbon;
    FDocPages: TTyPageControl;
    FStatus: TTyStatusBar;
    FBackstage: TTyRibbonBackstage;
    // Backstage content: one panel per command (the sidebar navigates; each command
    // shows its own content on the right — new→templates, open→recent, about→version…).
    FPgInfo, FPgNew, FPgOpen, FPgAbout, FPgOptions: TTyPanel;
    FBsInfoLbl, FBsAboutLbl: TTyLabel;
    FBsBrowse, FBsNewBlank: TTyGlyphButton;
    FBsRecent: array[0..7] of TTyGlyphButton;
    FFindDlg: TTyFindDialog;
    FReplaceDlg: TTyReplaceDialog;
    FRecent: TStringList;
    FDocList: TList;
    FNewCount: Integer;
    FFontColor: TTyColor;
    // ---- editor construction (dynamic tree; was the old constructor body) ----
    procedure BuildEditor;
    // ---- backstage content page ----
    procedure BuildBackstageContent;
    procedure ShowBsPage(APage: TTyPanel);
    procedure HideBsContent;
    procedure RefreshOpenPage;
    procedure RefreshInfoPage;
    procedure BackstageClosed(Sender: TObject);
    procedure DoOpenRecent(Sender: TObject);
    // ---- documents ----
    function  ActiveDoc: TEditorDoc;
    function  ActiveMemo: TTyMemo;
    function  NewDoc(const ACaption: string): TEditorDoc;
    procedure OpenFile(const APath: string);
    procedure AddRecent(const APath: string);
    procedure RebuildBackstage;
    procedure UpdateStatus;
    // ---- actions ----
    procedure DoNew(Sender: TObject);
    procedure DoOpen(Sender: TObject);
    procedure DoSave(Sender: TObject);
    procedure DoSaveAs(Sender: TObject);
    procedure DoCloseDoc(Sender: TObject);
    procedure DoCut(Sender: TObject);
    procedure DoCopy(Sender: TObject);
    procedure DoPaste(Sender: TObject);
    procedure DoSelectAll(Sender: TObject);
    procedure DoUndo(Sender: TObject);
    procedure DoRedo(Sender: TObject);
    procedure DoFind(Sender: TObject);
    procedure DoReplace(Sender: TObject);
    procedure DoInsertDate(Sender: TObject);
    procedure DoFontColor(Sender: TObject);
    procedure DoWordWrap(Sender: TObject);
    procedure DoToggleContext(Sender: TObject);
    procedure DoLauncher(Sender: TTyRibbonGroup);
    procedure DoNoop(Sender: TObject);
    // ---- events ----
    procedure BackstageSelect(Sender: TObject; AIndex: Integer);
    procedure MemoChanged(Sender: TObject);
    procedure PageChanged(Sender: TObject);
    // ---- ribbon builders ----
    function  NewGroup(APage: TTyRibbonPage; const ACaption: string; AWidth: Integer;
      ALauncher: Boolean): TTyRibbonGroup;
    function  Big(AGroup: TTyRibbonGroup; const ACap, AGlyph: string; AX, AW: Integer;
      AHandler: TNotifyEvent): TTyGlyphContainerButton;
    function  Small(AGroup: TTyRibbonGroup; const ACap, AGlyph: string; AX, AY, AW: Integer;
      AHandler: TNotifyEvent): TTyGlyphButton;
    function  AddQat(AQat: TTyRibbonQuickAccess; const AHint, AGlyph: string;
      AHandler: TNotifyEvent): TTyGlyphButton;
    procedure BuildHomeTab(APage: TTyRibbonPage);
    procedure BuildInsertTab(APage: TTyRibbonPage);
    procedure BuildViewTab(APage: TTyRibbonPage);
  public
    destructor Destroy; override;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

{ Locate the repo themes/ folder by walking up from the exe until themes/auto.tycss is found,
  so the ribbon skin switcher lists the structural skins (office, xp, win11, …) — not just the
  two compiled-in themes. Empty if not found (e.g. a stand-alone deployed exe). }
function LocalThemesDir: string;
var Dir: string; i: Integer;
begin
  Dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  for i := 1 to 8 do
  begin
    if FileExists(Dir + 'themes' + PathDelim + 'auto.tycss') then
      Exit(Dir + 'themes' + PathDelim);
    Dir := ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
    if Dir = '' then Break;
  end;
  Result := '';
end;

// ===========================================================================
// Ribbon builders
// ===========================================================================
function TMainForm.NewGroup(APage: TTyRibbonPage; const ACaption: string; AWidth: Integer;
  ALauncher: Boolean): TTyRibbonGroup;
begin
  Result := TTyRibbonGroup.Create(Self);
  Result.Parent := APage;      // alLeft (add right-to-left)
  Result.Caption := ACaption;
  Result.Width := AWidth;
  Result.ShowDialogLauncher := ALauncher;
  if ALauncher then Result.OnDialogLauncher := @DoLauncher;   // the launcher IS clickable
end;

procedure TMainForm.DoLauncher(Sender: TTyRibbonGroup);
begin
  TyShowMessage('“' + Sender.Caption + '”对话框(占位)');
end;

function TMainForm.Big(AGroup: TTyRibbonGroup; const ACap, AGlyph: string; AX, AW: Integer;
  AHandler: TNotifyEvent): TTyGlyphContainerButton;
begin
  Result := TTyGlyphContainerButton.Create(Self);
  Result.Parent := AGroup;
  Result.SetBounds(AX, 4, AW, 66);
  Result.Caption := ACap;
  Result.Images := FImgColl;
  Result.ImageName := AGlyph;      // '' -> caption only
  Result.Hint := ACap;             // ScreenTip
  Result.ShowHint := True;
  Result.OnClick := AHandler;
end;

function TMainForm.Small(AGroup: TTyRibbonGroup; const ACap, AGlyph: string; AX, AY, AW: Integer;
  AHandler: TNotifyEvent): TTyGlyphButton;
begin
  Result := TTyGlyphButton.Create(Self);
  Result.Parent := AGroup;
  Result.SetBounds(AX, AY, AW, 24);
  Result.Caption := ACap;
  Result.Images := FImgColl;
  Result.ImageName := AGlyph;      // '' -> caption only (e.g. B / I / U)
  Result.Hint := ACap;             // ScreenTip
  Result.ShowHint := True;
  Result.OnClick := AHandler;
end;

{ A Quick-Access button is ICON-ONLY (no caption): a fixed ~28px square showing
  just the glyph, with the command name as a ScreenTip. }
function TMainForm.AddQat(AQat: TTyRibbonQuickAccess; const AHint, AGlyph: string;
  AHandler: TNotifyEvent): TTyGlyphButton;
begin
  Result := AQat.AddButton('');    // no caption -> pure icon
  Result.StyleClass := 'ghost';    // flat: no frame at rest, subtle hover (Office QAT)
  Result.Images := FImgColl;
  Result.ImageName := AGlyph;
  Result.GlyphSize := 16;
  Result.Width := 28;              // square-ish (Align=alLeft keeps this width)
  Result.Hint := AHint;
  Result.ShowHint := True;
  Result.OnClick := AHandler;
end;

procedure TMainForm.BuildHomeTab(APage: TTyRibbonPage);
var
  g: TTyRibbonGroup;
  fontc, sizec: TTyComboBox;
  col: TTyColorButton;
  alignGrp: TTyButtonGroup;
  i: Integer;
begin
  // Groups are added RIGHT-to-LEFT so they flow Clipboard | Font | Paragraph | Editing left->right.

  // Editing
  g := NewGroup(APage, '编辑', 96, False);
  Small(g, '查找', 'find', 6, 4, 88, @DoFind);
  Small(g, '替换', 'replace', 6, 30, 88, @DoReplace);
  Small(g, '全选', 'selectall', 6, 56, 88, @DoSelectAll);

  // Paragraph
  g := NewGroup(APage, '段落', 150, True);
  alignGrp := TTyButtonGroup.Create(Self);
  alignGrp.Parent := g;
  alignGrp.StyleClass := 'ghost';
  alignGrp.SetBounds(6, 6, 138, 26);
  alignGrp.Items.Add('左'); alignGrp.Items.Add('中'); alignGrp.Items.Add('右'); alignGrp.Items.Add('两端');
  alignGrp.ItemIndex := 0;
  Small(g, '项目符号', 'bullets', 6, 40, 66, @DoNoop);
  Small(g, '编号', 'number', 76, 40, 66, @DoNoop);

  // Font
  g := NewGroup(APage, '字体', 240, True);
  fontc := TTyComboBox.Create(Self);
  fontc.Parent := g;
  fontc.Style := csDropDown;
  fontc.SetBounds(6, 6, 150, 26);
  fontc.Items.Add('等线'); fontc.Items.Add('宋体'); fontc.Items.Add('微软雅黑');
  fontc.Items.Add('Consolas'); fontc.Items.Add('Arial');
  fontc.ItemIndex := 0;
  sizec := TTyComboBox.Create(Self);
  sizec.Parent := g;
  sizec.Style := csDropDown;
  sizec.SetBounds(162, 6, 60, 26);
  for i := 8 to 16 do sizec.Items.Add(IntToStr(i));
  sizec.Items.Add('18'); sizec.Items.Add('24'); sizec.Items.Add('36');
  sizec.Text := '11';
  // B / I / U show as styled letters (no glyph), like Office.
  Small(g, 'B', '', 6, 40, 26, @DoNoop);
  Small(g, 'I', '', 36, 40, 26, @DoNoop);
  Small(g, 'U', '', 66, 40, 26, @DoNoop);
  col := TTyColorButton.Create(Self);
  col.Parent := g;
  col.SetBounds(100, 40, 48, 26);
  col.SelectedColor := FFontColor;
  col.OnColorChange := @DoFontColor;

  // Clipboard (with a dialog launcher, like Word)
  g := NewGroup(APage, '剪贴板', 150, True);
  Big(g, '粘贴', 'paste', 6, 56, @DoPaste);
  Small(g, '剪切', 'cut', 66, 4, 78, @DoCut);
  Small(g, '复制', 'copy', 66, 30, 78, @DoCopy);
  Small(g, '格式刷', 'painter', 66, 56, 78, @DoNoop);
end;

procedure TMainForm.BuildInsertTab(APage: TTyRibbonPage);
var
  g: TTyRibbonGroup;
  gal: TTyRibbonGallery;
  dd: TTyDropDownButton;
begin
  // Symbol
  g := NewGroup(APage, '符号', 130, False);
  Small(g, '符号', 'symbol', 6, 4, 116, @DoNoop);
  Small(g, '日期时间', 'datetime', 6, 30, 116, @DoInsertDate);

  // Illustrations (a styles gallery + picture)
  g := NewGroup(APage, '样式库', 230, False);
  gal := TTyRibbonGallery.Create(Self);
  gal.Parent := g;
  gal.SetBounds(6, 6, 216, 60);
  gal.Items.Add('样式 1'); gal.Items.Add('样式 2'); gal.Items.Add('样式 3');
  gal.Items.Add('样式 4'); gal.Items.Add('样式 5'); gal.Items.Add('样式 6');
  gal.ItemIndex := 0;

  // Table (a drop-down button)
  g := NewGroup(APage, '表格', 90, False);
  dd := TTyDropDownButton.Create(Self);
  dd.Parent := g;
  dd.SetBounds(6, 6, 78, 60);
  dd.Caption := '表格';
end;

procedure TMainForm.BuildViewTab(APage: TTyRibbonPage);
var
  g: TTyRibbonGroup;
  wrap, statusbar, ctx: TTyCheckBox;
begin
  // Window
  g := NewGroup(APage, '窗口', 110, False);
  Small(g, '新建窗口', 'newwindow', 6, 4, 98, @DoNoop);
  Small(g, '并排', 'arrange', 6, 30, 98, @DoNoop);

  // Zoom
  g := NewGroup(APage, '缩放', 130, False);
  Small(g, '放大', 'zoomin', 6, 4, 60, @DoNoop);
  Small(g, '缩小', 'zoomout', 68, 4, 60, @DoNoop);
  Small(g, '100%', 'zoom100', 6, 30, 122, @DoNoop);

  // View options
  g := NewGroup(APage, '显示', 140, False);
  wrap := TTyCheckBox.Create(Self);
  wrap.Parent := g; wrap.SetBounds(6, 6, 128, 22);
  wrap.Caption := '自动换行'; wrap.OnClick := @DoWordWrap;
  statusbar := TTyCheckBox.Create(Self);
  statusbar.Parent := g; statusbar.SetBounds(6, 30, 128, 22);
  statusbar.Caption := '状态栏'; statusbar.Checked := True;
  ctx := TTyCheckBox.Create(Self);
  ctx.Parent := g; ctx.SetBounds(6, 54, 128, 22);
  ctx.Caption := '图片工具(上下文)'; ctx.OnClick := @DoToggleContext;
end;

// ===========================================================================
// Skin switcher (title bar) — built-in dual-mode themes, live re-theme
// ===========================================================================
procedure TMainForm.ThemeComboChange(Sender: TObject);
begin
  if ThemeCombo.ItemIndex < 0 then Exit;
  TyDefaultController.ThemeName := ThemeCombo.Items[ThemeCombo.ItemIndex];
  ApplyChromeTheme(TyDefaultController);   // re-theme the shell on every skin change
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

// ===========================================================================
// Documents
// ===========================================================================
function TMainForm.ActiveDoc: TEditorDoc;
var i: Integer;
begin
  Result := nil;
  if (FDocPages = nil) or (FDocPages.ActivePage = nil) then Exit;
  for i := 0 to FDocList.Count - 1 do
    if TEditorDoc(FDocList[i]).Sheet = FDocPages.ActivePage then
      Exit(TEditorDoc(FDocList[i]));
end;

function TMainForm.ActiveMemo: TTyMemo;
var d: TEditorDoc;
begin
  d := ActiveDoc;
  if d <> nil then Result := d.Memo else Result := nil;
end;

function TMainForm.NewDoc(const ACaption: string): TEditorDoc;
begin
  Result := TEditorDoc.Create;
  Result.Sheet := FDocPages.AddPage(ACaption);
  Result.Memo := TTyMemo.Create(Self);
  Result.Memo.Parent := Result.Sheet;
  Result.Memo.Align := alClient;
  Result.Memo.OnChange := @MemoChanged;
  FDocList.Add(Result);
  FDocPages.ActivePage := Result.Sheet;
  UpdateStatus;
end;

procedure TMainForm.OpenFile(const APath: string);
var d: TEditorDoc;
begin
  if not FileExists(APath) then Exit;
  d := NewDoc(ExtractFileName(APath));
  d.FilePath := APath;
  d.Memo.Lines.LoadFromFile(APath);
  AddRecent(APath);
  UpdateStatus;
end;

procedure TMainForm.AddRecent(const APath: string);
var i: Integer;
begin
  i := FRecent.IndexOf(APath);
  if i >= 0 then FRecent.Delete(i);
  FRecent.Insert(0, APath);
  while FRecent.Count > 8 do FRecent.Delete(FRecent.Count - 1);
  // The recent list is read live by ShowOpenContent — no sidebar rebuild needed.
end;

procedure TMainForm.RebuildBackstage;
begin
  // Top block (Office File menu) — some show a content page, some act immediately.
  FBackstage.Commands.Clear;
  FBackstage.CommandGlyphs.Clear;
  FBackstage.Commands.Add('信息');   FBackstage.CommandGlyphs.Add('info');   // 0 -> content page
  FBackstage.Commands.Add('新建');   FBackstage.CommandGlyphs.Add('new');    // 1 -> content page
  FBackstage.Commands.Add('打开');   FBackstage.CommandGlyphs.Add('open');   // 2 -> content page
  FBackstage.Commands.Add('保存');   FBackstage.CommandGlyphs.Add('save');   // 3 -> act
  FBackstage.Commands.Add('另存为'); FBackstage.CommandGlyphs.Add('saveas'); // 4 -> act
  FBackstage.Commands.Add('关闭');   FBackstage.CommandGlyphs.Add('close');  // 5 -> act
  // Bottom-pinned block (with a separator above it) — caller-defined, not hardcoded.
  FBackstage.BottomCommands.Clear;
  FBackstage.BottomCommandGlyphs.Clear;
  FBackstage.BottomCommands.Add('关于'); FBackstage.BottomCommandGlyphs.Add('info');     // 6
  FBackstage.BottomCommands.Add('选项'); FBackstage.BottomCommandGlyphs.Add('settings'); // 7
  FBackstage.BottomCommands.Add('退出'); FBackstage.BottomCommandGlyphs.Add('exit');     // 8
  FBackstage.ItemIndex := -1;
end;

// Build the backstage content: ONE panel per command (parented to the backstage, over
// the content area right of the sidebar). The sidebar navigates; ShowBsPage swaps which
// panel is visible. Demonstrates the "one content page per command" model (a PageControl would work
// too, but panels avoid a redundant tab header since the sidebar is the navigation).
procedure TMainForm.BuildBackstageContent;
  function NewPage(const ATitle: string): TTyPanel;
  var lbl: TTyLabel;
  begin
    Result := TTyPanel.Create(Self);
    Result.Parent := FBackstage;
    Result.Visible := False;
    lbl := TTyLabel.Create(Self);
    lbl.Parent := Result;
    lbl.SetBounds(28, 22, 460, 34);
    lbl.Caption := ATitle;
  end;
var i: Integer;
begin
  // Info
  FPgInfo := NewPage('信息');
  FBsInfoLbl := TTyLabel.Create(Self);
  FBsInfoLbl.Parent := FPgInfo;
  FBsInfoLbl.SetBounds(28, 68, 520, 140);

  // New -- a "blank document" template button (placeholder for a template gallery)
  FPgNew := NewPage('新建');
  FBsNewBlank := TTyGlyphButton.Create(Self);
  FBsNewBlank.Parent := FPgNew;
  FBsNewBlank.SetBounds(28, 68, 160, 40);
  FBsNewBlank.Caption := '空白文档';
  FBsNewBlank.Images := FImgColl;
  FBsNewBlank.ImageName := 'new';
  FBsNewBlank.OnClick := @DoNew;

  // Open -- Browse + recent-file rows
  FPgOpen := NewPage('打开');
  FBsBrowse := TTyGlyphButton.Create(Self);
  FBsBrowse.Parent := FPgOpen;
  FBsBrowse.SetBounds(28, 68, 200, 34);
  FBsBrowse.Caption := '浏览…';
  FBsBrowse.Images := FImgColl;
  FBsBrowse.ImageName := 'folder';
  FBsBrowse.OnClick := @DoOpen;
  for i := 0 to High(FBsRecent) do
  begin
    FBsRecent[i] := TTyGlyphButton.Create(Self);
    FBsRecent[i].Parent := FPgOpen;
    FBsRecent[i].StyleClass := 'ghost';
    FBsRecent[i].SetBounds(28, 116 + i * 34, 460, 30);
    FBsRecent[i].Images := FImgColl;
    FBsRecent[i].ImageName := 'recent';
    FBsRecent[i].Tag := i;
    FBsRecent[i].OnClick := @DoOpenRecent;
    FBsRecent[i].Visible := False;
  end;

  // About
  FPgAbout := NewPage('关于');
  FBsAboutLbl := TTyLabel.Create(Self);
  FBsAboutLbl.Parent := FPgAbout;
  FBsAboutLbl.SetBounds(28, 68, 520, 180);
  FBsAboutLbl.Caption :=
    'TyControls 文本编辑器'#10 +
    'Ribbon 综合示例'#10#10 +
    '基于 ty-controls(BGRABitmap + .tycss 主题)'#10 +
    '跨平台矢量图标 · 主题化 ScreenTips · 内置主题切换';

  // Options (placeholder)
  FPgOptions := NewPage('选项');
end;

procedure TMainForm.ShowBsPage(APage: TTyPanel);
var r: TRect;
begin
  if APage = nil then Exit;
  HideBsContent;
  r := FBackstage.ContentRect;
  APage.SetBounds(r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top);
  APage.Anchors := [akLeft, akTop, akRight, akBottom];
  APage.Visible := True;
  APage.BringToFront;
end;

procedure TMainForm.HideBsContent;
  procedure H(P: TTyPanel);
  begin
    if P <> nil then P.Visible := False;
  end;
begin
  H(FPgInfo); H(FPgNew); H(FPgOpen); H(FPgAbout); H(FPgOptions);
end;

procedure TMainForm.RefreshOpenPage;
var i: Integer;
begin
  for i := 0 to High(FBsRecent) do
    if i < FRecent.Count then
    begin
      FBsRecent[i].Caption := ExtractFileName(FRecent[i]);
      FBsRecent[i].Hint := FRecent[i];
      FBsRecent[i].ShowHint := True;
      FBsRecent[i].Visible := True;
    end
    else
      FBsRecent[i].Visible := False;
end;

procedure TMainForm.RefreshInfoPage;
var d: TEditorDoc; s: string;
begin
  d := ActiveDoc;
  if d = nil then
    s := '(无打开的文档)'
  else
  begin
    if d.FilePath <> '' then s := '路径:' + d.FilePath else s := '(尚未保存)';
    s := s + #10 + Format('字符数:%d', [Length(d.Memo.Lines.Text)]);
    s := s + #10 + Format('行数:%d', [d.Memo.Lines.Count]);
  end;
  if FBsInfoLbl <> nil then FBsInfoLbl.Caption := s;
end;

procedure TMainForm.BackstageClosed(Sender: TObject);
begin
  HideBsContent;
  if FBackstage <> nil then FBackstage.ItemIndex := -1;   // fresh selection next open
end;

procedure TMainForm.DoOpenRecent(Sender: TObject);
var i: Integer;
begin
  if not (Sender is TTyGlyphButton) then Exit;
  i := TTyGlyphButton(Sender).Tag;
  if (i >= 0) and (i < FRecent.Count) then
  begin
    FBackstage.Close;
    OpenFile(FRecent[i]);
  end;
end;

procedure TMainForm.UpdateStatus;
var m: TTyMemo; d: TEditorDoc;
begin
  if FStatus = nil then Exit;
  d := ActiveDoc;
  m := ActiveMemo;
  if d <> nil then
    if d.FilePath <> '' then FStatus.Panels[0].Text := d.FilePath
    else FStatus.Panels[0].Text := '未保存'
  else
    FStatus.Panels[0].Text := '就绪';
  if m <> nil then
    FStatus.Panels[1].Text := Format('字符 %d', [Length(m.Lines.Text)])
  else
    FStatus.Panels[1].Text := '';
  FStatus.Panels[2].Text := '缩放 100%';
end;

// ===========================================================================
// Actions
// ===========================================================================
procedure TMainForm.DoNew(Sender: TObject);
begin
  Inc(FNewCount);
  NewDoc(Format('新文档 %d', [FNewCount]));
end;

procedure TMainForm.DoOpen(Sender: TObject);
var dlg: TOpenDialog;
begin
  dlg := TOpenDialog.Create(Self);
  try
    dlg.Filter := '文本文件 (*.txt)|*.txt|所有文件 (*.*)|*.*';
    if dlg.Execute then OpenFile(dlg.FileName);
  finally
    dlg.Free;
  end;
end;

procedure TMainForm.DoSave(Sender: TObject);
var d: TEditorDoc;
begin
  d := ActiveDoc;
  if d = nil then Exit;
  if d.FilePath = '' then DoSaveAs(Sender)
  else
  begin
    d.Memo.Lines.SaveToFile(d.FilePath);
    AddRecent(d.FilePath);
    UpdateStatus;
  end;
end;

procedure TMainForm.DoSaveAs(Sender: TObject);
var d: TEditorDoc; dlg: TSaveDialog;
begin
  d := ActiveDoc;
  if d = nil then Exit;
  dlg := TSaveDialog.Create(Self);
  try
    dlg.Filter := '文本文件 (*.txt)|*.txt|所有文件 (*.*)|*.*';
    dlg.DefaultExt := 'txt';
    if dlg.Execute then
    begin
      d.FilePath := dlg.FileName;
      d.Memo.Lines.SaveToFile(d.FilePath);
      d.Sheet.Caption := ExtractFileName(d.FilePath);
      AddRecent(d.FilePath);
      UpdateStatus;
    end;
  finally
    dlg.Free;
  end;
end;

procedure TMainForm.DoCloseDoc(Sender: TObject);
var d: TEditorDoc; i: Integer;
begin
  d := ActiveDoc;
  if d = nil then Exit;
  i := FDocList.IndexOf(d);
  if i >= 0 then FDocList.Delete(i);
  FDocPages.RemovePage(FDocPages.ActivePageIndex);
  d.Free;   // frees the sheet+memo via ownership? sheet is owned by form; free the record
  UpdateStatus;
end;

procedure TMainForm.DoCut(Sender: TObject);
begin if ActiveMemo <> nil then ActiveMemo.CutToClipboard; end;
procedure TMainForm.DoCopy(Sender: TObject);
begin if ActiveMemo <> nil then ActiveMemo.CopyToClipboard; end;
procedure TMainForm.DoPaste(Sender: TObject);
begin if ActiveMemo <> nil then ActiveMemo.PasteFromClipboard; end;
procedure TMainForm.DoSelectAll(Sender: TObject);
begin if ActiveMemo <> nil then ActiveMemo.SelectAll; end;
procedure TMainForm.DoUndo(Sender: TObject);
begin if ActiveMemo <> nil then ActiveMemo.Undo; end;
procedure TMainForm.DoRedo(Sender: TObject);
begin if ActiveMemo <> nil then ActiveMemo.Redo; end;

procedure TMainForm.DoFind(Sender: TObject);
var m: TTyMemo; p: Integer; s: string;
begin
  m := ActiveMemo;
  if m = nil then Exit;
  if not FFindDlg.Execute then Exit;
  if FFindDlg.FindText = '' then Exit;
  s := m.Lines.Text;
  p := PosEx(FFindDlg.FindText, s, m.SelStart + m.SelLength + 1);
  if p = 0 then p := Pos(FFindDlg.FindText, s);   // wrap to top
  if p > 0 then
  begin
    m.SelStart := p - 1;
    m.SelLength := Length(FFindDlg.FindText);
  end;
end;

procedure TMainForm.DoReplace(Sender: TObject);
var m: TTyMemo; s: string;
begin
  m := ActiveMemo;
  if m = nil then Exit;
  if not FReplaceDlg.Execute then Exit;
  if FReplaceDlg.FindText = '' then Exit;
  s := m.Lines.Text;
  s := StringReplace(s, FReplaceDlg.FindText, FReplaceDlg.ReplaceText, [rfReplaceAll]);
  m.Lines.Text := s;
  UpdateStatus;
end;

procedure TMainForm.DoInsertDate(Sender: TObject);
begin
  if ActiveMemo <> nil then
    ActiveMemo.SelText := FormatDateTime('yyyy-mm-dd hh:nn', Now);
end;

procedure TMainForm.DoFontColor(Sender: TObject);
begin
  if Sender is TTyColorButton then
    FFontColor := TTyColorButton(Sender).SelectedColor;
end;

procedure TMainForm.DoWordWrap(Sender: TObject);
begin
  if (ActiveMemo <> nil) and (Sender is TTyCheckBox) then
    ActiveMemo.WordWrap := TTyCheckBox(Sender).Checked;
end;

procedure TMainForm.DoToggleContext(Sender: TObject);
begin
  if (Sender is TTyCheckBox) and TTyCheckBox(Sender).Checked then
    FRibbon.ShowContext('pic')
  else
    FRibbon.HideContext('pic');
end;

procedure TMainForm.DoNoop(Sender: TObject);
begin
  // placeholder command (looks complete; no action wired)
end;

// ===========================================================================
// Events
// ===========================================================================
procedure TMainForm.BackstageSelect(Sender: TObject; AIndex: Integer);
begin
  if AIndex < 0 then Exit;
  // Content-page commands stay open + show their panel; action commands act + close.
  case AIndex of
    0: begin RefreshInfoPage; ShowBsPage(FPgInfo); end;                // Info
    1: ShowBsPage(FPgNew);                                             // New
    2: begin RefreshOpenPage; ShowBsPage(FPgOpen); end;                // Open
    3: begin HideBsContent; DoSave(Sender);     FBackstage.Close; end; // Save
    4: begin HideBsContent; DoSaveAs(Sender);   FBackstage.Close; end; // Save As
    5: begin HideBsContent; DoCloseDoc(Sender); FBackstage.Close; end; // Close
    6: ShowBsPage(FPgAbout);                                           // About
    7: ShowBsPage(FPgOptions);                                         // Options
    8: begin FBackstage.Close; Close; end;                             // Exit
  end;
end;

procedure TMainForm.MemoChanged(Sender: TObject);
begin
  UpdateStatus;
end;

procedure TMainForm.PageChanged(Sender: TObject);
begin
  UpdateStatus;
end;

// ===========================================================================
// Construction
// ===========================================================================
procedure TMainForm.FormCreate(Sender: TObject);
var
  names: TStringArray;
  i: Integer;
  base: string;
begin
  // The compiled-in pair (default + system) PLUS every skin FILE in themes/ (office, xp, win11,
  // material3, …) — all pickable from the one combo, so you can see Office's accent title bar etc.
  TyRegisterBuiltinThemes;
  names := TyBuiltinThemeNames;
  for i := 0 to High(names) do
    ThemeCombo.Items.Add(names[i]);
  names := TyRegisterThemeDir(LocalThemesDir);
  for i := 0 to High(names) do
  begin
    base := LowerCase(names[i]);
    // auto == default; light/dark are just the default's single-mode halves — skip as picks.
    if (base = 'auto') or (base = 'light') or (base = 'dark') then Continue;
    if ThemeCombo.Items.IndexOf(names[i]) < 0 then
      ThemeCombo.Items.Add(names[i]);
  end;
  ThemeCombo.ItemIndex := ThemeCombo.Items.IndexOf('default');
  TyDefaultController.ThemeName := 'default';
  ApplyChromeTheme(TyDefaultController);   // theme the window chrome + background

  // The rest of the editor is a dynamic control tree that can't live in the .lfm.
  BuildEditor;
end;

{ Build the whole editor shell in code (was the old constructor body). Runs from FormCreate,
  AFTER the .lfm (Bar + ThemeCombo) has streamed and the built-in 'default' theme is active. }
procedure TMainForm.BuildEditor;
var
  QAT: TTyRibbonQuickAccess;
  PgHome, PgInsert, PgView, PgPic: TTyRibbonPage;
  g: TTyRibbonGroup;
begin
  // Themed ScreenTips: installing a TTyHint swaps LCL's tooltip for the themed
  // TTyHintWindow app-wide, so every button's Hint (set in Big/Small/AddQat) shows
  // as an Office-style ScreenTip instead of the OS tooltip.
  TTyHint.Create(Self);

  FRecent := TStringList.Create;
  FDocList := TList.Create;
  FFontColor := TyRGB(0, 0, 0);

  // Cross-platform command icons: hand-drawn BGRA vector glyphs (uicons), NOT a
  // system icon font — so they render identically on Windows 7/10/11, macOS and
  // Linux. Buttons draw them tinted to the theme text color (theme-adaptive).
  FImgColl := TTyImageCollection.Create(Self);
  BuildEditorIcons(FImgColl);

  FFindDlg := TTyFindDialog.Create(Self);
  FReplaceDlg := TTyReplaceDialog.Create(Self);

  // Backstage (Office "File" view), opened by the File tab.
  FBackstage := TTyRibbonBackstage.Create(Self);
  FBackstage.Controller := TyDefaultController;
  FBackstage.Images := FImgColl;
  FBackstage.OnCommandSelect := @BackstageSelect;
  FBackstage.OnClose := @BackstageClosed;
  FBackstage.DefaultItemIndex := 0;   // open on Info with its content shown (Office-like)
  RebuildBackstage;
  BuildBackstageContent;

  // Status bar (bottom).
  FStatus := TTyStatusBar.Create(Self);
  FStatus.Parent := Self;
  FStatus.Align := alBottom;
  FStatus.Panels.Add.Width := 320;
  FStatus.Panels.Add.Width := 140;
  FStatus.Panels.Add.Width := 100;

  // The ribbon docks below the title bar. Both are alTop siblings; because the title bar
  // now streams from the .lfm FIRST, give the ribbon an explicit Top so LCL stacks it
  // BELOW the bar rather than on top of it (see memory lcl-code-created-align-order).
  FRibbon := TTyRibbon.Create(Self);
  FRibbon.Parent := Self;
  FRibbon.Top := Bar.Height;
  FRibbon.Controller := TyDefaultController;   // register as a theme listener (live re-theme)
  FRibbon.Height := 140;   // room for 3 small-button rows above the group caption band
  FRibbon.FileTab := True;
  FRibbon.FileTabCaption := '文件';
  FRibbon.Backstage := FBackstage;

  PgHome := FRibbon.AddPage('开始');
  BuildHomeTab(PgHome);
  PgInsert := FRibbon.AddPage('插入');
  BuildInsertTab(PgInsert);
  PgView := FRibbon.AddPage('视图');
  BuildViewTab(PgView);
  // Contextual "picture tools" tab (toggled on the View tab).
  PgPic := FRibbon.AddPage('图片工具');
  PgPic.Context := 'pic';
  g := NewGroup(PgPic, '调整', 120, False);
  Big(g, '裁剪', 'crop', 6, 56, @DoNoop);

  // Icon-only Quick Access Toolbar (like Office) on the title bar: New / Open / Save /
  // Undo / Redo. Placed to the right of the bar caption so they do not overlap it.
  QAT := TTyRibbonQuickAccess.Create(Self);
  QAT.Parent := Bar;
  QAT.SetBounds(240, 4, 152, 26);
  // Two-line hints (title + description) render as Office-style ScreenTips.
  AddQat(QAT, '新建'#10'新建一个空白文档', 'new',  @DoNew);
  AddQat(QAT, '打开'#10'打开已有文本文件', 'open', @DoOpen);
  AddQat(QAT, '保存'#10'把当前文档写入磁盘', 'save', @DoSave);
  AddQat(QAT, '撤销'#10'撤销上一步操作', 'undo', @DoUndo);
  AddQat(QAT, '重做'#10'重做被撤销的操作', 'redo', @DoRedo);

  // The document tab area fills the middle (alClient).
  FDocPages := TTyPageControl.Create(Self);
  FDocPages.Parent := Self;
  FDocPages.Align := alClient;
  FDocPages.Controller := TyDefaultController;
  FDocPages.OnChange := @PageChanged;

  ApplyChromeTheme(TyDefaultController);   // re-theme the fully-built shell

  // Start with one empty document.
  DoNew(Self);
end;

destructor TMainForm.Destroy;
var i: Integer;
begin
  for i := 0 to FDocList.Count - 1 do
    TEditorDoc(FDocList[i]).Free;
  FDocList.Free;
  FRecent.Free;
  inherited Destroy;
end;

end.
