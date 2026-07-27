unit umain;

{ Ribbon showcase = an MSO-style multi-tab plain-text editor, used to genuinely stress-test
  how complete the Ribbon components are.
  Title bar (QAT: save/undo/redo) -> Ribbon (File tab opens the backstage; Home/Insert/View
  three tabs, with groups + command buttons/drop-downs/color/segmented/gallery) -> multi-document
  tab area (one TTyMemo per document) -> status bar.
  File New/Open/Save/Save As/Close/Recent do real on-disk reads and writes; Cut/Copy/Paste/
  Undo/Redo/Select All/Find act on the current document; everything else (format painter,
  B/I/U, alignment, table, symbol...) is a placeholder but the UI is complete.

  The window, title bar, theme switcher AND the whole ribbon SKELETON are designed in umain.lfm
  (a TTyForm + TTyTitleBar + a TTyRibbon holding its TTyRibbonPage / TTyRibbonGroup children,
  plus the style gallery, the app-menu button and the two ribbon-behaviour check boxes) --
  the same objects the IDE designer produces, since TTyRibbonPage/TTyRibbonGroup mirror
  TTyTabSheet's design-time flags and self-register with their host while streaming.
  Only what genuinely cannot be expressed as .lfm objects is built in FormCreate code (see
  BuildEditor): the command buttons (their icons come from a code-built BGRA collection),
  the loop-filled combo lists, the QAT, the backstage and its content pages, the document
  tabs and the status bar.

  WARNING LCL layout pitfall: the title bar and the ribbon are both alTop siblings, and the
  ribbon groups are alLeft siblings. Same-align siblings are ordered by their Left/Top, and
  code-created ones (all at 0) end up in REVERSE creation order -- which is why every .lfm
  group carries an explicit Left. See memory lcl-code-created-align-order. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, Forms, Controls, Dialogs, Graphics, Menus,
  tyControls.Types, tyControls.Controller, tyControls.BuiltinThemes,
  tyControls.ThemeRegistry, tyControls.Base, tyControls.Painter,
  tyControls.Form, tyControls.Hint, tyControls.Panel,
  tyControls.TyLabel, tyControls.Button, tyControls.CheckBox, tyControls.ComboBox, tyControls.ToggleSwitch,
  tyControls.ImageCollection, tyControls.IconFont, tyControls.Menu,
  tyControls.GlyphButtons, tyControls.DropButtons,
  tyControls.ColorButton, tyControls.ButtonGroup, tyControls.Ribbon,
  tyControls.RibbonQuickAccess, tyControls.RibbonGallery, tyControls.RibbonBackstage,
  tyControls.RibbonAppMenu,
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
    Surface: TTyFormSurface;
    DarkSwitch: TTyToggleSwitch;
    ThemeCombo: TTyComboBox;                   // title-bar built-in skin switcher
    AccentCombo: TTyComboBox;                  // Office-app accent presets (Word/Excel/PPT/…) + custom
    // ---- the ribbon skeleton, authored in umain.lfm ----------------------------------
    // Ribbon > page > group is a real design-time object tree: the pages self-register with
    // the ribbon while streaming, the groups flow left->right by their explicit Left.
    Ribbon: TTyRibbon;
    PgHome: TTyRibbonPage;
    PgInsert: TTyRibbonPage;
    PgView: TTyRibbonPage;
    PgPicTools: TTyRibbonPage;                 // contextual: Context='pic', hidden until shown
    GrpClipboard: TTyRibbonGroup;
    GrpFont: TTyRibbonGroup;
    GrpParagraph: TTyRibbonGroup;
    GrpEdit: TTyRibbonGroup;
    GrpTable: TTyRibbonGroup;
    GrpStyles: TTyRibbonGroup;
    GrpSymbol: TTyRibbonGroup;
    GrpPicture: TTyRibbonGroup;                // ShowCaption=False -> no caption band at all
    GrpShow: TTyRibbonGroup;
    GrpZoom: TTyRibbonGroup;
    GrpWindow: TTyRibbonGroup;
    GrpRibbon: TTyRibbonGroup;
    GrpAppMenu: TTyRibbonGroup;
    GrpAdjust: TTyRibbonGroup;
    Gallery: TTyRibbonGallery;                 // 12 glyph+caption cells, 4 columns when dropped
    GalleryIcons: TTyIconFont;                 // the gallery cells' glyph source
    AppMenu: TTyRibbonAppMenu;                 // dropdown File button (commands + recent list)
    ChkKeyTips: TTyCheckBox;
    ChkCollapse: TTyCheckBox;
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure AccentComboChange(Sender: TObject);
    procedure RibbonFileTab(Sender: TObject);
    procedure GalleryStyleSelect(Sender: TObject);
    procedure AppMenuRecentClick(Sender: TObject; AIndex: Integer);
    procedure ChkKeyTipsClick(Sender: TObject);
    procedure ChkCollapseClick(Sender: TObject);
  private
    FImgColl: TTyImageCollection;   // cross-platform BGRA command icons (uicons)
    FRibbon: TTyRibbon;
    FDocPages: TTyPageControl;
    FStatus: TTyStatusBar;
    FBackstage: TTyRibbonBackstage;
    // The QAT icons + the dark-mode switch sit ON the title bar, so their ink must match the
    // title bar's text colour (white on Office's accent band, dark on a light caption) — not the
    // surface ink, which would be invisible on a coloured caption. See ReinkTitleBar.
    FQatButtons: array of TTyGlyphButton;   // title-bar QAT icons, re-inked to the caption colour
    FQat: TTyRibbonQuickAccess;             // the QAT strip itself, glued right after the caption
    // Backstage content: one panel per command (the sidebar navigates; each command
    // shows its own content on the right — new→templates, open→recent, about→version…).
    FPgInfo, FPgNew, FPgOpen, FPgAbout, FPgOptions: TTyPanel;
    FBsInfoLbl, FBsAboutLbl: TTyLabel;
    FBsBrowse, FBsNewBlank: TTyGlyphButton;
    FBsRecent: array[0..7] of TTyGlyphButton;
    FFindDlg: TTyFindDialog;
    FReplaceDlg: TTyReplaceDialog;
    FRecent: TStringList;
    // The app-menu button's Commands source: a plain TTyPopupMenu whose TOP-LEVEL items are
    // cloned into the dropdown on every drop (a '-' caption stays a separator line).
    FFileMenu: TTyPopupMenu;
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
    procedure DoQuit(Sender: TObject);
    procedure DoNoop(Sender: TObject);
    // ---- events ----
    procedure BackstageSelect(Sender: TObject; AIndex: Integer);
    procedure MemoChanged(Sender: TObject);
    procedure PageChanged(Sender: TObject);
    // ---- ribbon builders (the GROUPS come from umain.lfm; these fill them) ----
    function  Big(AGroup: TTyRibbonGroup; const ACap, AGlyph: string; AX, AW: Integer;
      AHandler: TNotifyEvent): TTyGlyphContainerButton;
    function  Small(AGroup: TTyRibbonGroup; const ACap, AGlyph: string; AX, AY, AW: Integer;
      AHandler: TNotifyEvent): TTyGlyphButton;
    function  AddQat(AQat: TTyRibbonQuickAccess; const AHint, AGlyph: string;
      AHandler: TNotifyEvent): TTyGlyphButton;
    function  AddCommand(AMenu: TTyPopupMenu; const ACaption: string;
      AHandler: TNotifyEvent): TMenuItem;
    procedure BuildHomeTab;
    procedure BuildInsertTab;
    procedure BuildViewTab;
    // Re-tint the title-bar-hosted controls (QAT icons + dark switch) to the caption's text colour.
    procedure ReinkTitleBar;
    // Position the QAT strip immediately after the (measured) caption text — re-run on theme change.
    procedure LayoutQat;
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
{ One TOP-LEVEL item of the app-menu's Commands menu. A '-' caption is a separator row
  (pass nil for its handler); every other row carries the command's own OnClick, which the
  app-menu clones onto its dropdown row so the click still lands here. }
function TMainForm.AddCommand(AMenu: TTyPopupMenu; const ACaption: string;
  AHandler: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(AMenu);
  Result.Caption := ACaption;
  Result.OnClick := AHandler;
  AMenu.Items.Add(Result);
end;

procedure TMainForm.DoLauncher(Sender: TTyRibbonGroup);
begin
  TyShowMessage('“' + Sender.Caption + '" dialog (placeholder)');
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
  Result.GlyphSize := 20;          // Office-QAT proportions (was 16 → looked tiny on a 34px bar)
  Result.Width := 28;              // square; Align=alLeft keeps this width
  // The ghost button's THEME padding (office: 5px 10px) shrinks the content box to ~6px, which
  // CLAMPS the glyph tiny no matter how big GlyphSize is. Override to a small uniform pad so the
  // 20px icon actually fills the box (content = 28 − 2·4 = 20px). This is the real size fix.
  Result.StyleOverride := 'padding: 4px';
  Result.Hint := AHint;
  Result.ShowHint := True;
  Result.OnClick := AHandler;
  SetLength(FQatButtons, Length(FQatButtons) + 1);
  FQatButtons[High(FQatButtons)] := Result;   // collect for ReinkTitleBar
end;

{ Tint the title-bar-hosted controls (QAT icons + dark switch) to the CAPTION's text colour so
  they stay visible on a coloured title bar (Office's accent band → white; a light caption → dark). }
procedure TMainForm.ReinkTitleBar;
var ink: TTyColor; hex: string; i: Integer;
begin
  ink := TyDefaultController.Model.ResolveStyle('TyTitleBar', '', []).TextColor;
  for i := 0 to High(FQatButtons) do
    FQatButtons[i].GlyphColor := ink;
  hex := 'color: #' + IntToHex(TyRedOf(ink), 2) + IntToHex(TyGreenOf(ink), 2) + IntToHex(TyBlueOf(ink), 2);
  if DarkSwitch <> nil then
    DarkSwitch.StyleOverride := hex;   // the '暗色' caption -> caption ink
  LayoutQat;                           // the caption font can change per theme -> reposition the QAT
end;

{ Glue the QAT strip to the caption: measure the caption exactly as the title bar draws it (same
  painter + resolved theme font), then place the QAT just past its right edge. Re-run whenever the
  theme changes (via ReinkTitleBar) because each skin's title font has a different width. }
procedure TMainForm.LayoutQat;
var
  s: TTyStyleSet;
  P: TTyPainter;
  bmp: TBitmap;
  fs, capW, leftPad, gap: Integer;
begin
  if FQat = nil then Exit;
  s  := TyDefaultController.Model.ResolveStyle('TyTitleBar', '', []);
  // Bar carries no explicit font (see umain.lfm) → ParentFont=True: the caption size is the
  // theme's --font-size-base (or the style's own font-size), exactly what the bar draws with.
  fs := TyResolveFontSize(s, True, Bar.Font.Size, TyDefaultController);
  bmp := TBitmap.Create;
  P := TTyPainter.Create;
  try
    bmp.SetSize(8, 8);                                  // scratch: MeasureText needs a paint context
    P.BeginPaint(bmp.Canvas, Rect(0, 0, 8, 8), Bar.Font.PixelsPerInch);
    capW := P.MeasureText(Bar.Caption, s.FontName, fs, s.FontWeight).cx;
    P.EndPaint;
  finally
    P.Free;
    bmp.Free;
  end;
  leftPad := TyTitleBarPad * Bar.Font.PixelsPerInch div 96;   // where the caption text starts (device px)
  gap     := 16 * Bar.Font.PixelsPerInch div 96;             // breathing room between title and QAT
  FQat.Left := leftPad + capW + gap;
end;

{ The GROUPS (caption, width, order, dialog launcher, ShowCaption) are authored in umain.lfm;
  these three routines only fill them with command controls, which need the code-built icon
  collection and loop-filled item lists. }
procedure TMainForm.BuildHomeTab;
var
  fontc, sizec: TTyComboBox;
  col: TTyColorButton;
  alignGrp: TTyButtonGroup;
  i: Integer;
begin
  // Editing
  Small(GrpEdit, 'Find', 'find', 6, 4, 88, @DoFind);
  Small(GrpEdit, 'Replace', 'replace', 6, 30, 88, @DoReplace);
  Small(GrpEdit, 'Select all', 'selectall', 6, 56, 88, @DoSelectAll);

  // Paragraph
  alignGrp := TTyButtonGroup.Create(Self);
  alignGrp.Parent := GrpParagraph;
  alignGrp.StyleClass := 'ghost';
  alignGrp.SetBounds(6, 6, 138, 26);
  alignGrp.Items.Add('Left'); alignGrp.Items.Add('Medium'); alignGrp.Items.Add('Right'); alignGrp.Items.Add('both ends');
  alignGrp.ItemIndex := 0;
  Small(GrpParagraph, 'Bullet list', 'bullets', 6, 40, 66, @DoNoop);
  Small(GrpParagraph, 'No.', 'number', 76, 40, 66, @DoNoop);

  // Font
  fontc := TTyComboBox.Create(Self);
  fontc.Parent := GrpFont;
  fontc.Style := csDropDown;
  fontc.SetBounds(6, 6, 150, 26);
  fontc.Items.Add('DengXian'); fontc.Items.Add('SimSun'); fontc.Items.Add('Microsoft YaHei');
  fontc.Items.Add('Consolas'); fontc.Items.Add('Arial');
  fontc.ItemIndex := 0;
  sizec := TTyComboBox.Create(Self);
  sizec.Parent := GrpFont;
  sizec.Style := csDropDown;
  sizec.SetBounds(162, 6, 60, 26);
  for i := 8 to 16 do sizec.Items.Add(IntToStr(i));
  sizec.Items.Add('18'); sizec.Items.Add('24'); sizec.Items.Add('36');
  sizec.Text := '11';
  // B / I / U show as styled letters (no glyph), like Office.
  Small(GrpFont, 'B', '', 6, 40, 26, @DoNoop);
  Small(GrpFont, 'I', '', 36, 40, 26, @DoNoop);
  Small(GrpFont, 'U', '', 66, 40, 26, @DoNoop);
  col := TTyColorButton.Create(Self);
  col.Parent := GrpFont;
  col.SetBounds(100, 40, 48, 26);
  col.SelectedColor := FFontColor;
  col.OnColorChange := @DoFontColor;

  // Clipboard (with a dialog launcher, like Word)
  Big(GrpClipboard, 'Paste', 'paste', 6, 56, @DoPaste);
  Small(GrpClipboard, 'Cut', 'cut', 66, 4, 78, @DoCut);
  Small(GrpClipboard, 'Copy', 'copy', 66, 30, 78, @DoCopy);
  Small(GrpClipboard, 'Format painter', 'painter', 66, 56, 78, @DoNoop);
end;

procedure TMainForm.BuildInsertTab;
var
  dd: TTyDropDownButton;
  pic: TTyGlyphContainerButton;
begin
  // Symbol
  Small(GrpSymbol, 'Symbol', 'symbol', 6, 4, 116, @DoNoop);
  Small(GrpSymbol, 'Date-time', 'datetime', 6, 30, 116, @DoInsertDate);

  // Style library: the gallery itself (12 items, their glyph names, the icon font, the
  // 4-column dropped grid and OnSelect) is entirely authored in umain.lfm.

  // Table (a drop-down button)
  dd := TTyDropDownButton.Create(Self);
  dd.Parent := GrpTable;
  dd.SetBounds(6, 6, 78, 60);
  dd.Caption := 'Grid';

  // The caption-LESS group (GrpPicture has ShowCaption=False in the .lfm): no bottom caption
  // band and no dialog launcher, so its content owns the group's full height. Compare its
  // bottom edge with the captioned groups beside it.
  pic := Big(GrpPicture, 'Picture', 'crop', 6, 58, @DoNoop);
  pic.Hint := 'This group has ShowCaption = False'#10 +
    'No caption band, no dialog launcher - the content fills the whole group height.';
end;

procedure TMainForm.BuildViewTab;
var
  wrap, statusbar, ctx: TTyCheckBox;
begin
  // Window
  Small(GrpWindow, 'New window', 'newwindow', 6, 4, 98, @DoNoop);
  Small(GrpWindow, 'Side by side', 'arrange', 6, 30, 98, @DoNoop);

  // Zoom
  Small(GrpZoom, 'Zoom in', 'zoomin', 6, 4, 60, @DoNoop);
  Small(GrpZoom, 'Zoom out', 'zoomout', 68, 4, 60, @DoNoop);
  Small(GrpZoom, '100%', 'zoom100', 6, 30, 122, @DoNoop);

  // View options
  wrap := TTyCheckBox.Create(Self);
  wrap.Parent := GrpShow; wrap.SetBounds(6, 6, 128, 22);
  wrap.Caption := 'Word wrap'; wrap.OnClick := @DoWordWrap;
  statusbar := TTyCheckBox.Create(Self);
  statusbar.Parent := GrpShow; statusbar.SetBounds(6, 30, 128, 22);
  statusbar.Caption := 'Status bar'; statusbar.Checked := True;
  ctx := TTyCheckBox.Create(Self);
  ctx.Parent := GrpShow; ctx.SetBounds(6, 54, 128, 22);
  ctx.Caption := 'Picture tools (contextual)'; ctx.OnClick := @DoToggleContext;

  // 'Ribbon itself' (ChkKeyTips / ChkCollapse) and 'App menu' (AppMenu) are .lfm objects;
  // the app menu's command list is filled in BuildEditor, next to the recent-files list.
end;

// ===========================================================================
// Skin switcher (title bar) — built-in dual-mode themes, live re-theme
// ===========================================================================
procedure TMainForm.ThemeComboChange(Sender: TObject);
begin
  if ThemeCombo.ItemIndex < 0 then Exit;
  TyDefaultController.ThemeName := ThemeCombo.Items[ThemeCombo.ItemIndex];
  ApplyChromeTheme(TyDefaultController);   // re-theme the shell on every skin change
  ReinkTitleBar;
end;

procedure TMainForm.DarkSwitchChange(Sender: TObject);
begin
  // Flip the light/dark @mode axis (independent of which theme ThemeCombo picked).
  if DarkSwitch.Checked then
    TyDefaultController.Mode := 'dark'
  else
    TyDefaultController.Mode := 'light';
  ApplyChromeTheme(TyDefaultController);
  ReinkTitleBar;
end;

{ Accent presets: recolour any skin live from the one --accent seed. On the Office skin this turns
  the caption band + ribbon accents into the real Office-app colours, so you can see the SAME Office
  layout Word-blue / Excel-green / PowerPoint-orange / … — plus 跟随主题 (the skin's own accent) and
  自定义… (a colour dialog). Item order matches ACCENT_HEX below. }
procedure TMainForm.AccentComboChange(Sender: TObject);
const
  // '' = 跟随主题 (reset); '?' = 自定义… (dialog); else a preset hex.
  ACCENT_HEX: array[0..6] of string =
    ('', '#2B579A', '#217346', '#B7472A', '#7719AA', '#0F6CBD', '?');
var
  i: Integer;
  sel: string;
  dlg: TTyColorDialog;
begin
  i := AccentCombo.ItemIndex;
  if (i < 0) or (i > High(ACCENT_HEX)) then Exit;
  sel := ACCENT_HEX[i];
  if sel = '' then
    TyDefaultController.ResetAccent                       // 跟随主题
  else if sel = '?' then
  begin
    dlg := TTyColorDialog.Create(nil);
    try
      dlg.Caption := 'Choose accent colour';
      if dlg.Execute then
        TyDefaultController.SetAccent('#' + IntToHex(TyRedOf(dlg.Color), 2)
          + IntToHex(TyGreenOf(dlg.Color), 2) + IntToHex(TyBlueOf(dlg.Color), 2));
    finally
      dlg.Free;
    end;
  end
  else
    TyDefaultController.SetAccent(sel);                   // an Office-app preset
  ApplyChromeTheme(TyDefaultController);
  ReinkTitleBar;
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
  // TTyRibbonAppMenu.RecentItems COPIES what you assign (it never aliases a list you may
  // free), so hand it the new contents whenever the list changes.
  if AppMenu <> nil then AppMenu.RecentItems := FRecent;
end;

procedure TMainForm.RebuildBackstage;
begin
  // Top block (Office File menu) — some show a content page, some act immediately.
  FBackstage.Commands.Clear;
  FBackstage.CommandGlyphs.Clear;
  FBackstage.Commands.Add('Information');   FBackstage.CommandGlyphs.Add('info');   // 0 -> content page
  FBackstage.Commands.Add('New');   FBackstage.CommandGlyphs.Add('new');    // 1 -> content page
  FBackstage.Commands.Add('Open');   FBackstage.CommandGlyphs.Add('open');   // 2 -> content page
  FBackstage.Commands.Add('Save');   FBackstage.CommandGlyphs.Add('save');   // 3 -> act
  FBackstage.Commands.Add('Save as'); FBackstage.CommandGlyphs.Add('saveas'); // 4 -> act
  FBackstage.Commands.Add('Close');   FBackstage.CommandGlyphs.Add('close');  // 5 -> act
  // Bottom-pinned block (with a separator above it) — caller-defined, not hardcoded.
  FBackstage.BottomCommands.Clear;
  FBackstage.BottomCommandGlyphs.Clear;
  FBackstage.BottomCommands.Add('About'); FBackstage.BottomCommandGlyphs.Add('info');     // 6
  FBackstage.BottomCommands.Add('Option'); FBackstage.BottomCommandGlyphs.Add('settings'); // 7
  // A row whose text is a lone '-' draws as a NON-SELECTABLE divider line. It still takes a
  // unified index, so everything below it shifts by one (Sign out is 9, not 8).
  FBackstage.BottomCommands.Add('-'); FBackstage.BottomCommandGlyphs.Add('');              // 8 = divider
  FBackstage.BottomCommands.Add('Sign out'); FBackstage.BottomCommandGlyphs.Add('exit');     // 9
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
  FPgInfo := NewPage('Information');
  FBsInfoLbl := TTyLabel.Create(Self);
  FBsInfoLbl.Parent := FPgInfo;
  FBsInfoLbl.SetBounds(28, 68, 520, 140);

  // New -- a "blank document" template button (placeholder for a template gallery)
  FPgNew := NewPage('New');
  FBsNewBlank := TTyGlyphButton.Create(Self);
  FBsNewBlank.Parent := FPgNew;
  FBsNewBlank.SetBounds(28, 68, 160, 40);
  FBsNewBlank.Caption := 'Blank document';
  FBsNewBlank.Images := FImgColl;
  FBsNewBlank.ImageName := 'new';
  FBsNewBlank.OnClick := @DoNew;

  // Open -- Browse + recent-file rows
  FPgOpen := NewPage('Open');
  FBsBrowse := TTyGlyphButton.Create(Self);
  FBsBrowse.Parent := FPgOpen;
  FBsBrowse.SetBounds(28, 68, 200, 34);
  FBsBrowse.Caption := 'Browse…';
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
  FPgAbout := NewPage('About');
  FBsAboutLbl := TTyLabel.Create(Self);
  FBsAboutLbl.Parent := FPgAbout;
  FBsAboutLbl.SetBounds(28, 68, 520, 180);
  FBsAboutLbl.Caption :=
    'TyControls text editor'#10 +
    'Ribbon overview example'#10#10 +
    'Built on ty-controls (BGRABitmap + .tycss themes)'#10 +
    'Cross-platform vector icons · themed ScreenTips · built-in theme switching';

  // Options (placeholder)
  FPgOptions := NewPage('Option');
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
    s := '(no open document)'
  else
  begin
    if d.FilePath <> '' then s := 'Path:' + d.FilePath else s := '(not saved yet)';
    s := s + #10 + Format('Char count: %d', [Length(d.Memo.Lines.Text)]);
    s := s + #10 + Format('Row count: %d', [d.Memo.Lines.Count]);
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
    else FStatus.Panels[0].Text := 'Not saved'
  else
    FStatus.Panels[0].Text := 'Ready';
  if m <> nil then
    FStatus.Panels[1].Text := Format('Char %d', [Length(m.Lines.Text)])
  else
    FStatus.Panels[1].Text := '';
  FStatus.Panels[2].Text := 'Zoom 100%';
end;

// ===========================================================================
// Actions
// ===========================================================================
procedure TMainForm.DoNew(Sender: TObject);
begin
  Inc(FNewCount);
  NewDoc(Format('New document %d', [FNewCount]));
end;

procedure TMainForm.DoOpen(Sender: TObject);
var dlg: TOpenDialog;
begin
  dlg := TOpenDialog.Create(Self);
  try
    dlg.Filter := 'Text file (*.txt)|*.txt|All files (*.*)|*.*';
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
    dlg.Filter := 'Text file (*.txt)|*.txt|All files (*.*)|*.*';
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

procedure TMainForm.DoQuit(Sender: TObject);
begin
  Close;   // the app menu's last command row
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
    // 8 is the '-' divider row — never selectable, so it never reaches here.
    9: begin FBackstage.Close; Close; end;                             // Exit
  end;
end;

{ OnFileTab fires on EVERY File-tab click, whether or not a Backstage is assigned — it is the
  hook an app WITHOUT a backstage uses to open its own File view. Here the backstage opens on
  top of the window a moment later, so the status text is the proof the event ran first. }
procedure TMainForm.RibbonFileTab(Sender: TObject);
begin
  if FStatus <> nil then
    FStatus.Panels[0].Text := 'File tab clicked - backstage opening';
end;

{ Picking a gallery thumbnail — inline or from the dropped 4-column grid — lands here. }
procedure TMainForm.GalleryStyleSelect(Sender: TObject);
begin
  if FStatus <> nil then
    FStatus.Panels[3].Text := Format('Style %d', [Gallery.ItemIndex + 1]);
end;

{ A recent-files row of the app menu's dropdown: AIndex indexes RecentItems, not the menu. }
procedure TMainForm.AppMenuRecentClick(Sender: TObject; AIndex: Integer);
begin
  if (AIndex >= 0) and (AIndex < FRecent.Count) then
    OpenFile(FRecent[AIndex]);
end;

procedure TMainForm.ChkKeyTipsClick(Sender: TObject);
begin
  Ribbon.KeyTips := ChkKeyTips.Checked;
end;

procedure TMainForm.ChkCollapseClick(Sender: TObject);
begin
  Ribbon.Minimized := ChkCollapse.Checked;
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
  // Every skin — Office included — is compiled IN: TyRegisterBuiltinThemes registers the whole
  // built-in pack ('default'+'system' + every structural skin), so this ribbon example needs no
  // themes/ folder. It DEFAULTS to Office; the combo lists the whole pack, plus any extra theme
  // FILE dropped in themes/ during development (e.g. the green image demo).
  TyRegisterBuiltinThemes;
  names := TyBuiltinThemeNames;                 // default, system, office, xp, win11, … (compiled in)
  for i := 0 to High(names) do
    ThemeCombo.Items.Add(names[i]);
  names := TyRegisterThemeDir(LocalThemesDir);  // extra local theme files, if any (green, …)
  for i := 0 to High(names) do
  begin
    base := LowerCase(names[i]);
    // auto == default; light/dark are the default's single-mode halves; default/system already added.
    if (base = 'auto') or (base = 'light') or (base = 'dark')
       or (base = 'default') or (base = 'system') then Continue;
    if ThemeCombo.Items.IndexOf(names[i]) < 0 then
      ThemeCombo.Items.Add(names[i]);
  end;
  ThemeCombo.ItemIndex := ThemeCombo.Items.IndexOf('office');
  TyDefaultController.ThemeName := 'office';   // default to Office

  // Office-app accent presets (item order MUST match ACCENT_HEX in AccentComboChange).
  AccentCombo.Items.Add('Follow theme');
  AccentCombo.Items.Add('Word Blue');
  AccentCombo.Items.Add('Excel Green');
  AccentCombo.Items.Add('PowerPoint Orange');
  AccentCombo.Items.Add('OneNote Purple');
  AccentCombo.Items.Add('Outlook Blue');
  AccentCombo.Items.Add('Custom…');
  AccentCombo.ItemIndex := 0;

  ApplyChromeTheme(TyDefaultController);   // theme the window chrome + background

  // Everything the .lfm cannot express (icon-fed command buttons, the QAT, the backstage,
  // the document tabs, the status bar) is wired onto the streamed skeleton here.
  BuildEditor;
end;

{ Fill in the streamed shell. Runs from FormCreate, AFTER umain.lfm (title bar + the whole
  ribbon/page/group skeleton) has streamed and the built-in 'default' theme is active. }
procedure TMainForm.BuildEditor;
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
  FStatus.Parent := Surface;
  FStatus.Align := alBottom;
  FStatus.Panels.Add.Width := 320;
  FStatus.Panels.Add.Width := 140;
  FStatus.Panels.Add.Width := 100;
  FStatus.Panels.Add.Width := 140;   // 3 = the gallery's last pick (GalleryStyleSelect)
  FStatus.Panels.Add.Width := 180;   // 4 = a standing reminder that KeyTips are on
  FStatus.Panels[3].Text := 'Style 1';
  FStatus.Panels[4].Text := 'Press Alt for KeyTips';

  // The ribbon, its four pages and their groups all stream from umain.lfm — including the
  // contextual "Picture tools" page (Context='pic', hidden until DoToggleContext shows it).
  // Only the theme controller, the backstage link and the dialog-launcher handler are wired
  // here; the launcher ARROWS themselves are switched on in the .lfm (ShowDialogLauncher).
  FRibbon := Ribbon;
  FRibbon.Controller := TyDefaultController;   // register as a theme listener (live re-theme)
  FRibbon.Backstage := FBackstage;
  GrpClipboard.OnDialogLauncher := @DoLauncher;
  GrpFont.OnDialogLauncher := @DoLauncher;
  GrpParagraph.OnDialogLauncher := @DoLauncher;

  BuildHomeTab;
  BuildInsertTab;
  BuildViewTab;
  Big(GrpAdjust, 'Clip', 'crop', 6, 56, @DoNoop);   // the contextual page's only group

  // TTyRibbonAppMenu (View tab) composes its OWN dropdown out of two sources it never
  // mutates: the top-level items of Commands, then a separator, then one row per
  // RecentItems entry. That is the alternative to the FileTab+Backstage route above —
  // the same app, one big File view vs one small File menu.
  FFileMenu := TTyPopupMenu.Create(Self);
  AddCommand(FFileMenu, 'New', @DoNew);
  AddCommand(FFileMenu, 'Open...', @DoOpen);
  AddCommand(FFileMenu, 'Save', @DoSave);
  AddCommand(FFileMenu, '-', nil);          // a separator row inside the commands block
  AddCommand(FFileMenu, 'Exit', @DoQuit);
  AppMenu.Commands := FFileMenu;
  AppMenu.RecentItems := FRecent;           // re-assigned by AddRecent (RecentItems copies)

  // Icon-only Quick Access Toolbar (like Office) on the title bar: New / Open / Save /
  // Undo / Redo. Width = 5 buttons flush (alLeft, no layout spacing); Left is glued right
  // after the measured caption by LayoutQat (run here + on every theme change).
  FQat := TTyRibbonQuickAccess.Create(Self);
  FQat.Parent := Bar;
  FQat.SetBounds(Bar.ClientWidth, 3, 5 * 28 + 8, 28);   // 5 flush buttons + tiny slack; Left set by LayoutQat
  // Two-line hints (title + description) render as Office-style ScreenTips.
  AddQat(FQat, 'New'#10'Create a new blank document', 'new',  @DoNew);
  AddQat(FQat, 'Open'#10'Open an existing text file', 'open', @DoOpen);
  AddQat(FQat, 'Save'#10'Write the current document to disk', 'save', @DoSave);
  AddQat(FQat, 'Undo'#10'Undo the last action', 'undo', @DoUndo);
  AddQat(FQat, 'Redo'#10'Redo the undone action', 'redo', @DoRedo);

  // The document tab area fills the middle (alClient).
  FDocPages := TTyPageControl.Create(Self);
  FDocPages.Parent := Surface;
  FDocPages.Align := alClient;
  FDocPages.Controller := TyDefaultController;
  FDocPages.OnChange := @PageChanged;

  ApplyChromeTheme(TyDefaultController);   // re-theme the fully-built shell
  ReinkTitleBar;                           // QAT icons + switch -> caption ink (visible on Office's band)

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
