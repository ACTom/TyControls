unit tbpreview;
{ The preview: a frame with the controls laid out by family on eight pages, all on a style
  controller of their OWN (not the tool's). The editor's text is loaded into it the way an
  application loads a theme -- over the base theme, url() and @import from the document's
  folder -- so a theme written badly only breaks the preview, never the tool around it.

  Controls do not inherit a controller from their parent (ActiveController is "mine, else
  the default"), so after the .lfm is read every Ty control under Root is handed this
  frame's controller one by one (TbApplyController). The strip at the top (Tools) stays on
  the tool's theme: it is part of the tool, not of the preview.

  Loading never leaves the preview broken. The model loads fail-fast (a load that raises
  keeps the old layer), but a load can pass and still raise when a control paints: a
  variable defined only in the dark block and used in light mode survives the model's check
  (it validates against every mode at once) and raises in ResolveStyle. So after every load
  (and every light / dark switch) every catalog typeKey, each of its variants and six state
  sets are resolved once (TbProbeResolve); a failure puts the last version that worked back. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Forms, Controls, Menus, Types,
  tyControls.Types, tyControls.StyleModel, tyControls.Controller, tyControls.Base,
  tyControls.Form, tyControls.Dialogs, tyControls.Panel, tyControls.Button,
  tyControls.GlyphButtons, tyControls.DropButtons, tyControls.TyLabel, tyControls.LinkLabel,
  tyControls.CheckBox, tyControls.ToggleSwitch, tyControls.Tag, tyControls.Badge,
  tyControls.Divider, tyControls.Edit, tyControls.Memo, tyControls.ComboBox,
  tyControls.SpinEdit, tyControls.DateTimePicker, tyControls.TrackBar, tyControls.Rating,
  tyControls.ListBox, tyControls.CheckListBox, tyControls.TreeView, tyControls.ListView,
  tyControls.Grid, tyControls.ValueListEditor, tyControls.GroupBox, tyControls.Card,
  tyControls.ExPanel, tyControls.PageControl, tyControls.TabSheet, tyControls.TabSet,
  tyControls.ScrollBox, tyControls.Splitter, tyControls.Menu, tyControls.ToolBar,
  tyControls.StatusBar, tyControls.Breadcrumb, tyControls.ScrollBar, tyControls.ProgressBar,
  tyControls.CircularProgress, tyControls.ActivityIndicator, tyControls.Alert,
  tyControls.Empty, tyControls.Notification, tyControls.Icons.Lucide;

resourcestring
  rsTbDensityClassic = 'Classic';
  rsTbDensityModern = 'Modern';
  rsTbSingleMode = 'One mode only';
  { the sample data the .lfm cannot hold, or holds untranslated }
  rsTbSampleItem1 = 'Apples';
  rsTbSampleItem2 = 'Pears';
  rsTbSampleItem3 = 'Cherries';
  rsTbSampleItem4 = 'Plums';
  rsTbSampleItem5 = 'Grapes';
  rsTbSampleMemo1 = 'The first line of a memo.';
  rsTbSampleMemo2 = 'A second line, a little longer than the first one.';
  rsTbSampleMemo3 = 'A third.';
  rsTbSampleColName = 'Name';
  rsTbSampleColSize = 'Size';
  rsTbSampleColKind = 'Kind';
  rsTbSampleFile1 = 'theme.tycss';
  rsTbSampleFile2 = 'background.jpg';
  rsTbSampleFile3 = 'notes.txt';
  rsTbSampleKindTheme = 'Theme';
  rsTbSampleKindImage = 'Image';
  rsTbSampleKindText = 'Text';
  rsTbSampleColRegion = 'Region';
  rsTbSampleColQty = 'Quantity';
  rsTbSampleColAmount = 'Amount';
  rsTbSampleTotal = 'Total';
  rsTbSampleNorth = 'North';
  rsTbSampleSouth = 'South';
  rsTbSampleEast = 'East';
  rsTbSampleWest = 'West';
  rsTbSampleKeyName = 'Name';
  rsTbSampleKeyAuthor = 'Author';
  rsTbSampleKeyVersion = 'Version';
  rsTbSampleKeyModes = 'Modes';
  rsTbSampleValName = 'My theme';
  rsTbSampleValAuthor = 'Me';
  rsTbSampleValModes = 'light, dark';
  rsTbSampleTab1 = 'Overview';
  rsTbSampleTab2 = 'Details';
  rsTbSampleTab3 = 'History';
  rsTbSampleStatus1 = 'Ready';
  rsTbSampleStatus2 = 'Ln 1, Col 1';
  rsTbSampleStatus3 = 'UTF-8';
  rsTbSampleCrumb1 = 'Home';
  rsTbSampleCrumb2 = 'Themes';
  rsTbSampleCrumb3 = 'My theme';

type
  TTbPreviewFrame = class(TFrame)
    Tools: TTyPanel;
    DarkSwitch: TTyToggleSwitch;
    DensityCombo: TTyComboBox;
    DisableAllCheck: TTyCheckBox;
    ModeNote: TTyLabel;
    Root: TTyPanel;
    Pages: TTyPageControl;
    TabBasic: TTyTabSheet;
    BtnDefault: TTyButton;
    BtnPrimary: TTyButton;
    BtnDanger: TTyButton;
    BtnGhost: TTyButton;
    BtnDisabled: TTyButton;
    BtnPrimaryDisabled: TTyButton;
    SpdGhost: TTySpeedButton;
    DdbMore: TTyDropDownButton;
    LblNormal: TTyLabel;
    LblDisabled: TTyLabel;
    LnkSample: TTyLinkLabel;
    ChkOn: TTyCheckBox;
    ChkOff: TTyCheckBox;
    ChkDisabled: TTyCheckBox;
    RadOn: TTyRadioButton;
    RadOff: TTyRadioButton;
    TglOn: TTyToggleSwitch;
    TglOff: TTyToggleSwitch;
    TagPlain: TTyTag;
    TagAccent: TTyTag;
    TagDanger: TTyTag;
    BadgeSample: TTyBadge;
    DivSample: TTyDivider;
    TabInputs: TTyTabSheet;
    EdtText: TTyEdit;
    EdtHint: TTyEdit;
    EdtDisabled: TTyEdit;
    EdtReadOnly: TTyEdit;
    MemoSample: TTyMemo;
    CmbSample: TTyComboBox;
    SpnSample: TTySpinEdit;
    DtpSample: TTyDateTimePicker;
    TrkSample: TTyTrackBar;
    RatSample: TTyRating;
    TabLists: TTyTabSheet;
    LstSample: TTyListBox;
    ClbSample: TTyCheckListBox;
    TreSample: TTyTreeView;
    LvwSample: TTyListView;
    TabGrids: TTyTabSheet;
    GrdSample: TTyStringGrid;
    VleSample: TTyValueListEditor;
    TabContainers: TTyTabSheet;
    PnlSample: TTyPanel;
    GrpSample: TTyGroupBox;
    CrdSample: TTyCard;
    ExpSample: TTyExPanel;
    TabsSample: TTyTabSet;
    InnerPages: TTyPageControl;
    InnerOne: TTyTabSheet;
    InnerTwo: TTyTabSheet;
    InnerThree: TTyTabSheet;
    SbxSample: TTyScrollBox;
    SbxContent: TTyPanel;
    SplHost: TTyPanel;
    SplLeft: TTyPanel;
    SplSample: TTySplitter;
    SplRight: TTyPanel;
    TabMenus: TTyTabSheet;
    MnbSample: TTyMenuBar;
    TbrSample: TTyToolBar;
    TbnOne: TTyToolButton;
    TbnDown: TTyToolButton;
    TbnSep: TTyToolSeparator;
    TbnThree: TTyToolButton;
    TbnDisabled: TTyToolButton;
    StbSample: TTyStatusBar;
    BtnPopup: TTyButton;
    BrcSample: TTyBreadcrumb;
    TabChrome: TTyTabSheet;
    LblChromeNote: TTyLabel;
    BtnSampleWindow: TTyButton;
    ScbH: TTyScrollBar;
    ScbV: TTyScrollBar;
    ScbDisabled: TTyScrollBar;
    TabFeedback: TTyTabSheet;
    PrgSample: TTyProgressBar;
    PrgDisabled: TTyProgressBar;
    CprSample: TTyCircularProgress;
    ActSample: TTyActivityIndicator;
    AlrInfo: TTyAlert;
    AlrSuccess: TTyAlert;
    AlrWarning: TTyAlert;
    AlrError: TTyAlert;
    EmpSample: TTyEmpty;
    BtnMessage: TTyButton;
    BtnInput: TTyButton;
    BtnNotify: TTyButton;
    SampleMenu: TMainMenu;
    SmFile: TMenuItem;
    SmNew: TMenuItem;
    SmOpen: TMenuItem;
    SmSep: TMenuItem;
    SmRecent: TMenuItem;
    SmRecentOne: TMenuItem;
    SmRecentTwo: TMenuItem;
    SmEdit: TMenuItem;
    SmUndo: TMenuItem;
    SmWrap: TMenuItem;
    SmPaste: TMenuItem;
    SmView: TMenuItem;
    SmZoom: TMenuItem;
    SamplePopup: TTyPopupMenu;
    SpCut: TMenuItem;
    SpCopy: TMenuItem;
    SpSep: TMenuItem;
    SpChecked: TMenuItem;
    SpDisabled: TMenuItem;
    SampleNotify: TTyNotification;
    LucideFont: TTyLucideIconFont;
    procedure DarkSwitchChange(Sender: TObject);
    procedure DensityComboChange(Sender: TObject);
    procedure DisableAllCheckChange(Sender: TObject);
    procedure BtnPopupClick(Sender: TObject);
    procedure BtnSampleWindowClick(Sender: TObject);
    procedure BtnMessageClick(Sender: TObject);
    procedure BtnInputClick(Sender: TObject);
    procedure BtnNotifyClick(Sender: TObject);
  private
    FController: TTyStyleController;
    FDialogOwner: TTyForm;
    FGoodText, FGoodDir: string;
    FModeError: string;
    FAllDisabled: Boolean;
    FUpdating: Boolean;
    FOnChanged: TNotifyEvent;
    procedure FillCodeOnlyData;
    procedure UpdateModeNote;
    procedure RestoreGood;
    function LoadInto(const AText, ABaseDir: string; out AError: string;
      out ATouched: Boolean): Boolean;
    function GetIsDark: Boolean;
    function GetIsModern: Boolean;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { AText over the base, as an app would load it; url() / @import from ABaseDir.
      False + AError: the preview keeps the last version that loaded (or the base) }
    function LoadDocument(const AText, ABaseDir: string; out AError: string): Boolean;
    function HasModes: Boolean;
    function StyledControlCount: Integer;           { FOR THE TESTS }
    property Controller: TTyStyleController read FController;
    property ModeError: string read FModeError;     { the last rejected switch, '' after a good load }
    property AllDisabled: Boolean read FAllDisabled;
    property IsDark: Boolean read GetIsDark;
    property IsModern: Boolean read GetIsModern;
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;  { a switch was used }
  end;

procedure TbApplyController(ARoot: TWinControl; AController: TTyStyleController);
{ every catalog typeKey x its variants x six state sets; False and AError on the first raise }
function TbProbeResolve(AModel: TTyStyleModel; out AError: string): Boolean;

implementation

{$R *.lfm}

uses
  tyControls.Css.Catalog, tyControls.DensityPack, tyControls.ThemeBundle, tyControls.Columns,
  tbthemesource;

procedure TbApplyController(ARoot: TWinControl; AController: TTyStyleController);

  procedure SetOne(AControl: TControl);
  begin
    { the two Ty bases share no ancestor that publishes Controller }
    if AControl is TTyCustomControl then
    begin
      if TTyCustomControl(AControl).Controller <> AController then
        TTyCustomControl(AControl).Controller := AController;
    end
    else if AControl is TTyGraphicControl then
    begin
      if TTyGraphicControl(AControl).Controller <> AController then
        TTyGraphicControl(AControl).Controller := AController;
    end;
  end;

  procedure Walk(AParent: TWinControl);
  var
    i: Integer;
  begin
    for i := 0 to AParent.ControlCount - 1 do
    begin
      SetOne(AParent.Controls[i]);
      if AParent.Controls[i] is TWinControl then
        Walk(TWinControl(AParent.Controls[i]));
    end;
  end;

begin
  if ARoot = nil then Exit;
  SetOne(ARoot);
  Walk(ARoot);
end;

function TbProbeResolve(AModel: TTyStyleModel; out AError: string): Boolean;
const
  cStates: array[0..5] of TTyStateSet = ([], [tysHover], [tysActive], [tysFocused],
    [tysDisabled], [tysSelected]);
var
  k, v, s: Integer;
  variants: TStringList;
  key, cls: string;
begin
  AError := '';
  variants := TStringList.Create;
  try
    for k := 0 to High(TyCatalogTypeKeys) do
    begin
      key := TyCatalogTypeKeys[k];
      variants.Clear;
      variants.Add('');
      AModel.GetVariantsForType(key, variants);
      for v := 0 to variants.Count - 1 do
        for s := 0 to High(cStates) do
        begin
          cls := variants[v];
          try
            AModel.ResolveStyle(key, cls, cStates[s]);
          except
            on E: Exception do
            begin
              if cls <> '' then key := key + '.' + cls;
              AError := key + ': ' + E.Message;
              Exit(False);
            end;
          end;
        end;
    end;
  finally
    variants.Free;
  end;
  Result := True;
end;

{ ---- TTbPreviewFrame ---- }

constructor TTbPreviewFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);          { the .lfm is read and Loaded has run }
  FController := TTyStyleController.Create(Self);
  FDialogOwner := TTyForm.CreateNew(Self);
  FDialogOwner.Controller := FController;
  FillCodeOnlyData;                  { before the controller is pushed: combined controls pass it on }
  TbApplyController(Root, FController);
  SamplePopup.Controller := FController;
  SampleNotify.Controller := FController;
  FUpdating := True;
  try
    DensityCombo.Items.Add(rsTbDensityClassic);
    DensityCombo.Items.Add(rsTbDensityModern);
    DensityCombo.ItemIndex := 0;
  finally
    FUpdating := False;
  end;
  UpdateModeNote;
end;

destructor TTbPreviewFrame.Destroy;
begin
  { before the controller (a component of this frame) goes: the window on it }
  FreeAndNil(FDialogOwner);
  inherited Destroy;
end;

procedure TTbPreviewFrame.FillCodeOnlyData;

  procedure AddCol(AHeader: TTyHeader; const AText: string; AWidth: Integer);
  var
    c: TTyColumn;
  begin
    c := AHeader.Columns.Add as TTyColumn;
    c.Text := AText;
    c.Width := AWidth;
  end;

  procedure AddRow(const AName, ASize, AKind: string);
  var
    it: TTyListItem;
  begin
    it := LvwSample.Items.Add;
    it.Caption := AName;
    it.SubItems.Add(ASize);
    it.SubItems.Add(AKind);
  end;

  procedure StatusPanel(const AText: string; AWidth: Integer);
  var
    p: TTyStatusPanel;
  begin
    p := StbSample.Panels.Add;
    p.Text := AText;
    p.Width := AWidth;
  end;

  procedure GridRow(ARow: Integer; const ARegion: string; AQty: Integer; AAmount: Double);
  begin
    GrdSample.Cells[0, ARow] := ARegion;
    GrdSample.Cells[1, ARow] := IntToStr(AQty);
    GrdSample.Cells[2, ARow] := Format('%.2f', [AAmount]);
  end;

begin
  LstSample.Items.Add(rsTbSampleItem1);
  LstSample.Items.Add(rsTbSampleItem2);
  LstSample.Items.Add(rsTbSampleItem3);
  LstSample.Items.Add(rsTbSampleItem4);
  LstSample.Items.Add(rsTbSampleItem5);
  LstSample.ItemIndex := 1;
  ClbSample.Items.Add(rsTbSampleItem1);
  ClbSample.Items.Add(rsTbSampleItem2);
  ClbSample.Items.Add(rsTbSampleItem3);
  ClbSample.Items.Add(rsTbSampleItem4);
  ClbSample.Checked[0] := True;
  ClbSample.Checked[2] := True;
  CmbSample.Items.Add(rsTbSampleItem1);
  CmbSample.Items.Add(rsTbSampleItem2);
  CmbSample.Items.Add(rsTbSampleItem3);
  CmbSample.ItemIndex := 0;
  MemoSample.Lines.Add(rsTbSampleMemo1);
  MemoSample.Lines.Add(rsTbSampleMemo2);
  MemoSample.Lines.Add(rsTbSampleMemo3);

  AddCol(LvwSample.Header, rsTbSampleColName, 180);
  AddCol(LvwSample.Header, rsTbSampleColSize, 90);
  AddCol(LvwSample.Header, rsTbSampleColKind, 120);
  AddRow(rsTbSampleFile1, '24 KB', rsTbSampleKindTheme);
  AddRow(rsTbSampleFile2, '310 KB', rsTbSampleKindImage);
  AddRow(rsTbSampleFile3, '2 KB', rsTbSampleKindText);

  AddCol(GrdSample.Header, rsTbSampleColRegion, 160);
  AddCol(GrdSample.Header, rsTbSampleColQty, 100);
  AddCol(GrdSample.Header, rsTbSampleColAmount, 120);
  GrdSample.RowCount := 5;
  GrdSample.FixedRows := 1;
  GridRow(0, rsTbSampleTotal, 118, 5930.5);
  GridRow(1, rsTbSampleNorth, 42, 2100);
  GridRow(2, rsTbSampleSouth, 17, 845.5);
  GridRow(3, rsTbSampleEast, 35, 1750);
  GridRow(4, rsTbSampleWest, 24, 1235);

  VleSample.Values[rsTbSampleKeyName] := rsTbSampleValName;
  VleSample.Values[rsTbSampleKeyAuthor] := rsTbSampleValAuthor;
  VleSample.Values[rsTbSampleKeyVersion] := '1.0';
  VleSample.Values[rsTbSampleKeyModes] := rsTbSampleValModes;

  TabsSample.Tabs.Add(rsTbSampleTab1);
  TabsSample.Tabs.Add(rsTbSampleTab2);
  TabsSample.Tabs.Add(rsTbSampleTab3);
  TabsSample.TabIndex := 0;

  StatusPanel(rsTbSampleStatus1, 200);
  StatusPanel(rsTbSampleStatus2, 120);
  StatusPanel(rsTbSampleStatus3, 0);

  BrcSample.Items.Add(rsTbSampleCrumb1);
  BrcSample.Items.Add(rsTbSampleCrumb2);
  BrcSample.Items.Add(rsTbSampleCrumb3);
end;

procedure TTbPreviewFrame.UpdateModeNote;
begin
  if HasModes then
  begin
    DarkSwitch.Enabled := True;
    ModeNote.Caption := '';
  end
  else
  begin
    DarkSwitch.Enabled := False;
    ModeNote.Caption := rsTbSingleMode;
  end;
end;

function TTbPreviewFrame.HasModes: Boolean;
begin
  Result := Length(FController.Model.ModeNames) > 0;
end;

function TTbPreviewFrame.GetIsDark: Boolean;
begin
  Result := SameText(FController.Mode, 'dark');
end;

function TTbPreviewFrame.GetIsModern: Boolean;
begin
  Result := FController.Density = tdModern;
end;

{ ATouched: the model took the text (and may now be in a state that does not resolve);
  False when the load raised before that, leaving the model exactly as it was }
function TTbPreviewFrame.LoadInto(const AText, ABaseDir: string; out AError: string;
  out ATouched: Boolean): Boolean;
var
  src: ITyThemeSource;
begin
  AError := '';
  ATouched := False;
  src := TTbTextThemeSource.Create(AText, ABaseDir);
  try
    FController.Model.LoadFromSource(src);   { fail-fast: on a raise the old layer stays }
    ATouched := True;
    if FController.Density = tdModern then
      FController.Model.LoadFromCssAdditive(TyDensityModernCss);
    FController.Changed;                     { repaint + seed the mode of a dual-mode theme }
  except
    on E: Exception do
    begin
      AError := E.Message;
      Exit(False);
    end;
  end;
  Result := TbProbeResolve(FController.Model, AError);
end;

function TTbPreviewFrame.LoadDocument(const AText, ABaseDir: string; out AError: string): Boolean;
var
  touched: Boolean;
begin
  Result := LoadInto(AText, ABaseDir, AError, touched);
  if Result then
  begin
    FGoodText := AText;
    FGoodDir := ABaseDir;
    FModeError := '';
  end
  else if touched then
    { a load that raised left the model as it was, but one that loaded and then failed
      the probe did not: put the last good version back (or the bare base) }
    RestoreGood;
  UpdateModeNote;
end;

procedure TTbPreviewFrame.RestoreGood;
var
  err: string;
  touched: Boolean;
begin
  if not LoadInto(FGoodText, FGoodDir, err, touched) then
    LoadInto('', '', err, touched);
end;

function TTbPreviewFrame.StyledControlCount: Integer;

  function CountIn(AParent: TWinControl): Integer;
  var
    i: Integer;
    c: TControl;
  begin
    Result := 0;
    for i := 0 to AParent.ControlCount - 1 do
    begin
      c := AParent.Controls[i];
      if ((c is TTyCustomControl) and (TTyCustomControl(c).Controller = FController))
         or ((c is TTyGraphicControl) and (TTyGraphicControl(c).Controller = FController)) then
        Inc(Result);
      if c is TWinControl then
        Inc(Result, CountIn(TWinControl(c)));
    end;
  end;

begin
  Result := CountIn(Root);
  if Root.Controller = FController then
    Inc(Result);
end;

{ ---- the switches and the pop-ups (filled in by the next step) ---- }

procedure TTbPreviewFrame.DarkSwitchChange(Sender: TObject);
begin
end;

procedure TTbPreviewFrame.DensityComboChange(Sender: TObject);
begin
end;

procedure TTbPreviewFrame.DisableAllCheckChange(Sender: TObject);
begin
end;

procedure TTbPreviewFrame.BtnPopupClick(Sender: TObject);
begin
end;

procedure TTbPreviewFrame.BtnSampleWindowClick(Sender: TObject);
begin
end;

procedure TTbPreviewFrame.BtnMessageClick(Sender: TObject);
begin
end;

procedure TTbPreviewFrame.BtnInputClick(Sender: TObject);
begin
end;

procedure TTbPreviewFrame.BtnNotifyClick(Sender: TObject);
begin
end;

end.
