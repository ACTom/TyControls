unit umain;

{ Ribbon 综合示例 = 一个 MSO 风格的多标签纯文本编辑器,用来真实检验 Ribbon 组件的完成度。
  标题栏(QAT:保存/撤销/重做)→ Ribbon(文件标签开 backstage;开始/插入/视图 三个标签,分组 +
  命令按钮/下拉/颜色/分段/画廊)→ 多文档标签区(每个文档一个 TTyMemo)→ 状态栏。
  文件的 新建/打开/保存/另存为/关闭/最近文件 走真实磁盘读写;剪切/复制/粘贴/撤销/重做/全选/查找
  接到当前文档;其余(格式刷、B/I/U、对齐、表格、符号…)做占位但界面完整。纯代码创建(无 .lfm)。

  ⚠ LCL 布局坑:同为 alTop 的兄弟控件,后添加的排到顶——所以先建 Ribbon(在下)、标题栏最后建
  (在上);分组也从右往左加。见记忆 lcl-code-created-align-order。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, Forms, Controls, Dialogs, Graphics,
  tyControls.Types, tyControls.Controller, tyControls.Form, tyControls.Hint,
  tyControls.Panel,
  tyControls.TyLabel, tyControls.Button, tyControls.CheckBox, tyControls.ComboBox,
  tyControls.IconFont, tyControls.GlyphButtons, tyControls.DropButtons,
  tyControls.ColorButton, tyControls.ButtonGroup, tyControls.Ribbon,
  tyControls.RibbonQuickAccess, tyControls.RibbonGallery, tyControls.RibbonBackstage,
  tyControls.PageControl, tyControls.TabSheet, tyControls.Memo, tyControls.StatusBar,
  tyControls.Dialogs.Find, tyControls.Dialogs.Color;

const
  CTitleH = 34;

type
  { One open document: its tab sheet + memo + on-disk path. }
  TEditorDoc = class
    Sheet: TTyTabSheet;
    Memo: TTyMemo;
    FilePath: string;
  end;

  TMainForm = class(TTyForm)
  private
    FIcons: TTyIconFont;
    FRibbon: TTyRibbon;
    FDocPages: TTyPageControl;
    FStatus: TTyStatusBar;
    FBackstage: TTyRibbonBackstage;
    FBsPanel: TTyPanel;                       // backstage content host (right of the sidebar)
    FBsTitle: TTyLabel;
    FBsBrowse: TTyGlyphButton;
    FBsRecent: array[0..7] of TTyGlyphButton; // recent-file rows on the 打开 content page
    FFindDlg: TTyFindDialog;
    FReplaceDlg: TTyReplaceDialog;
    FRecent: TStringList;
    FDocList: TList;
    FNewCount: Integer;
    FFontColor: TTyColor;
    // ---- backstage content page ----
    procedure BuildBackstageContent;
    procedure ShowOpenContent;
    procedure HideBsContent;
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
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  MainForm: TMainForm;

implementation

function ThemesDir: string;
var Dir: string; i: Integer;
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
end;

function TMainForm.Big(AGroup: TTyRibbonGroup; const ACap, AGlyph: string; AX, AW: Integer;
  AHandler: TNotifyEvent): TTyGlyphContainerButton;
begin
  Result := TTyGlyphContainerButton.Create(Self);
  Result.Parent := AGroup;
  Result.SetBounds(AX, 4, AW, 66);
  Result.Caption := ACap;
  Result.IconFont := FIcons;
  Result.GlyphName := AGlyph;      // '' -> caption only
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
  Result.IconFont := FIcons;
  Result.GlyphName := AGlyph;      // '' -> caption only (e.g. B / I / U)
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
  Result.IconFont := FIcons;
  Result.GlyphName := AGlyph;
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
  // Groups are added RIGHT-to-LEFT so they flow 剪贴板 | 字体 | 段落 | 编辑 left->right.

  // 编辑
  g := NewGroup(APage, '编辑', 96, False);
  Small(g, '查找', 'find', 6, 4, 88, @DoFind);
  Small(g, '替换', 'replace', 6, 30, 88, @DoReplace);
  Small(g, '全选', 'selectall', 6, 56, 88, @DoSelectAll);

  // 段落
  g := NewGroup(APage, '段落', 150, True);
  alignGrp := TTyButtonGroup.Create(Self);
  alignGrp.Parent := g;
  alignGrp.StyleClass := 'ghost';
  alignGrp.SetBounds(6, 6, 138, 26);
  alignGrp.Items.Add('左'); alignGrp.Items.Add('中'); alignGrp.Items.Add('右'); alignGrp.Items.Add('两端');
  alignGrp.ItemIndex := 0;
  Small(g, '项目符号', 'bullets', 6, 40, 66, @DoNoop);
  Small(g, '编号', 'number', 76, 40, 66, @DoNoop);

  // 字体
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

  // 剪贴板
  g := NewGroup(APage, '剪贴板', 150, False);
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
  // 符号
  g := NewGroup(APage, '符号', 130, False);
  Small(g, '符号', 'symbol', 6, 4, 116, @DoNoop);
  Small(g, '日期时间', 'datetime', 6, 30, 116, @DoInsertDate);

  // 插图 (a styles gallery + 图片)
  g := NewGroup(APage, '样式库', 230, False);
  gal := TTyRibbonGallery.Create(Self);
  gal.Parent := g;
  gal.SetBounds(6, 6, 216, 60);
  gal.Items.Add('样式 1'); gal.Items.Add('样式 2'); gal.Items.Add('样式 3');
  gal.Items.Add('样式 4'); gal.Items.Add('样式 5'); gal.Items.Add('样式 6');
  gal.ItemIndex := 0;

  // 表格 (a drop-down button)
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
  // 窗口
  g := NewGroup(APage, '窗口', 110, False);
  Small(g, '新建窗口', 'newwindow', 6, 4, 98, @DoNoop);
  Small(g, '并排', 'arrange', 6, 30, 98, @DoNoop);

  // 缩放
  g := NewGroup(APage, '缩放', 130, False);
  Small(g, '放大', 'zoomin', 6, 4, 60, @DoNoop);
  Small(g, '缩小', 'zoomout', 68, 4, 60, @DoNoop);
  Small(g, '100%', 'zoom100', 6, 30, 122, @DoNoop);

  // 显示
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
  // Fixed top-level command list with per-row icons (Office File menu). Recent files
  // now live on the 打开 CONTENT page (right of the sidebar), not inline in the sidebar.
  FBackstage.Commands.Clear;
  FBackstage.CommandGlyphs.Clear;
  FBackstage.Commands.Add('新建');   FBackstage.CommandGlyphs.Add('new');    // 0
  FBackstage.Commands.Add('打开');   FBackstage.CommandGlyphs.Add('open');   // 1 -> content page
  FBackstage.Commands.Add('保存');   FBackstage.CommandGlyphs.Add('save');   // 2
  FBackstage.Commands.Add('另存为'); FBackstage.CommandGlyphs.Add('save');   // 3
  FBackstage.Commands.Add('关闭');   FBackstage.CommandGlyphs.Add('close');  // 4
  FBackstage.Commands.Add('退出');   FBackstage.CommandGlyphs.Add('exit');   // 5
  FBackstage.ItemIndex := -1;
end;

// The backstage content host: a themed panel (right of the sidebar) with a title, a
// 浏览… button and up to 8 recent-file rows. Built once; ShowOpenContent fills it.
procedure TMainForm.BuildBackstageContent;
var i: Integer;
begin
  FBsPanel := TTyPanel.Create(Self);
  FBsPanel.Parent := FBackstage;
  FBsPanel.Visible := False;

  FBsTitle := TTyLabel.Create(Self);
  FBsTitle.Parent := FBsPanel;
  FBsTitle.SetBounds(28, 20, 300, 30);
  FBsTitle.Caption := '打开';

  FBsBrowse := TTyGlyphButton.Create(Self);
  FBsBrowse.Parent := FBsPanel;
  FBsBrowse.SetBounds(28, 60, 200, 30);
  FBsBrowse.Caption := '浏览…';
  FBsBrowse.IconFont := FIcons;
  FBsBrowse.GlyphName := 'folder';
  FBsBrowse.OnClick := @DoOpen;

  for i := 0 to High(FBsRecent) do
  begin
    FBsRecent[i] := TTyGlyphButton.Create(Self);
    FBsRecent[i].Parent := FBsPanel;
    FBsRecent[i].StyleClass := 'ghost';
    FBsRecent[i].SetBounds(28, 108 + i * 34, 380, 30);
    FBsRecent[i].IconFont := FIcons;
    FBsRecent[i].GlyphName := 'recent';
    FBsRecent[i].Tag := i;
    FBsRecent[i].OnClick := @DoOpenRecent;
    FBsRecent[i].Visible := False;
  end;
end;

procedure TMainForm.ShowOpenContent;
var r: TRect; i: Integer;
begin
  r := FBackstage.ContentRect;
  FBsPanel.SetBounds(r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top);
  FBsPanel.Anchors := [akLeft, akTop, akRight, akBottom];
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
  FBsPanel.Visible := True;
  FBsPanel.BringToFront;
end;

procedure TMainForm.HideBsContent;
begin
  if FBsPanel <> nil then FBsPanel.Visible := False;
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
  // 打开 (1) shows a content page (recent files + 浏览) and stays open; the rest act + close.
  if AIndex = 1 then
  begin
    ShowOpenContent;
    Exit;
  end;
  HideBsContent;
  case AIndex of
    0: DoNew(Sender);
    2: DoSave(Sender);
    3: DoSaveAs(Sender);
    4: DoCloseDoc(Sender);
    5: begin FBackstage.Close; Close; Exit; end;   // 退出
  end;
  FBackstage.Close;
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
constructor TMainForm.Create(AOwner: TComponent);
var
  Bar: TTyTitleBar;
  QAT: TTyRibbonQuickAccess;
  PgHome, PgInsert, PgView, PgPic: TTyRibbonPage;
  g: TTyRibbonGroup;
begin
  inherited CreateNew(AOwner, 0);
  Caption := 'TyControls 文本编辑器';
  Position := poScreenCenter;
  SetBounds(0, 0, 900, 620);

  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  // Themed ScreenTips: installing a TTyHint swaps LCL's tooltip for the themed
  // TTyHintWindow app-wide, so every button's Hint (set in Big/Small/AddQat) shows
  // as an Office-style ScreenTip instead of the OS tooltip.
  TTyHint.Create(Self);

  FRecent := TStringList.Create;
  FDocList := TList.Create;
  FFontColor := TyRGB(0, 0, 0);

  // Distinct per-command icons from Segoe MDL2 Assets (ships with Win10/11).
  // Each command maps to its own glyph, so the ribbon reads like real Office —
  // not the same star everywhere. Code points are in the font's Private Use Area.
  FIcons := TTyIconFont.Create(Self);
  FIcons.FontFamily := 'Segoe MDL2 Assets';
  FIcons.MapGlyph('new',       $E7C3);   // Page
  FIcons.MapGlyph('open',      $E8E5);   // OpenFile
  FIcons.MapGlyph('save',      $E74E);   // Save
  FIcons.MapGlyph('cut',       $E8C6);   // Cut
  FIcons.MapGlyph('copy',      $E8C8);   // Copy
  FIcons.MapGlyph('paste',     $E77F);   // Paste
  FIcons.MapGlyph('painter',   $E790);   // Brush (format painter)
  FIcons.MapGlyph('undo',      $E7A7);   // Undo
  FIcons.MapGlyph('redo',      $E7A6);   // Redo
  FIcons.MapGlyph('find',      $E721);   // Search
  FIcons.MapGlyph('replace',   $E70F);   // Edit
  FIcons.MapGlyph('selectall', $E8B3);   // SelectAll
  FIcons.MapGlyph('bullets',   $E8FD);   // BulletedList
  FIcons.MapGlyph('number',    $E8EF);   // numbered list
  FIcons.MapGlyph('symbol',    $E76E);   // Emoji2
  FIcons.MapGlyph('datetime',  $E787);   // Calendar
  FIcons.MapGlyph('table',     $E8A9);   // GridView
  FIcons.MapGlyph('crop',      $E7A8);   // Crop
  FIcons.MapGlyph('newwindow', $E78B);   // NewWindow
  FIcons.MapGlyph('arrange',   $E7C4);   // TaskView
  FIcons.MapGlyph('zoomin',    $E8A3);   // ZoomIn
  FIcons.MapGlyph('zoomout',   $E71F);   // Zoom
  FIcons.MapGlyph('zoom100',   $E1CB);   // FitPage
  FIcons.MapGlyph('close',     $E8BB);   // ChromeClose
  FIcons.MapGlyph('exit',      $E7E8);   // Leave
  FIcons.MapGlyph('folder',    $E838);   // OpenLocal (browse)
  FIcons.MapGlyph('recent',    $E823);   // Recent

  FFindDlg := TTyFindDialog.Create(Self);
  FReplaceDlg := TTyReplaceDialog.Create(Self);

  // Backstage (Office "File" view), opened by the File tab.
  FBackstage := TTyRibbonBackstage.Create(Self);
  FBackstage.Controller := TyDefaultController;
  FBackstage.IconFont := FIcons;
  FBackstage.OnCommandSelect := @BackstageSelect;
  FBackstage.OnClose := @BackstageClosed;
  RebuildBackstage;
  BuildBackstageContent;

  // Status bar (bottom).
  FStatus := TTyStatusBar.Create(Self);
  FStatus.Parent := Self;
  FStatus.Align := alBottom;
  FStatus.Panels.Add.Width := 320;
  FStatus.Panels.Add.Width := 140;
  FStatus.Panels.Add.Width := 100;

  // ── alTop stack, created BOTTOM-first (LCL puts the last-added alTop on top) ──

  // 1) The ribbon (below the title bar). File tab -> backstage.
  FRibbon := TTyRibbon.Create(Self);
  FRibbon.Parent := Self;
  FRibbon.Height := 118;
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

  // 2) The title bar LAST → topmost. Hosts the QAT (save / undo / redo).
  Bar := TTyTitleBar.Create(Self);
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := CTitleH;
  Bar.Caption := 'TyControls 文本编辑器';

  // Icon-only Quick Access Toolbar (like Office): 新建 / 打开 / 保存 / 撤销 / 重做.
  QAT := TTyRibbonQuickAccess.Create(Self);
  QAT.Parent := Bar;
  QAT.SetBounds(8, 4, 160, 26);
  // Two-line hints (title + description) render as Office-style ScreenTips.
  AddQat(QAT, '新建'#10'新建一个空白文档', 'new',  @DoNew);
  AddQat(QAT, '打开'#10'打开已有文本文件', 'open', @DoOpen);
  AddQat(QAT, '保存'#10'把当前文档写入磁盘', 'save', @DoSave);
  AddQat(QAT, '撤销'#10'撤销上一步操作', 'undo', @DoUndo);
  AddQat(QAT, '重做'#10'重做被撤销的操作', 'redo', @DoRedo);

  // 3) The document tab area fills the middle (alClient).
  FDocPages := TTyPageControl.Create(Self);
  FDocPages.Parent := Self;
  FDocPages.Align := alClient;
  FDocPages.Controller := TyDefaultController;
  FDocPages.OnChange := @PageChanged;

  ApplyChromeTheme(TyDefaultController);

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
