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
  (it validates against every mode at once) and raises in ResolveStyle; so does a seed the
  base theme's rules cannot take (only the document's rules are validated), or a variable
  that leads back to itself. So after every load (and every light / dark switch) the
  document is probed (TbProbeDocument): every declaration a paint could evaluate is
  evaluated once against the mode's variables (TbFastProbe), and if that raises, every
  catalog typeKey is resolved with all its variants and states (TbProbeResolve), which has
  the last word and names the typeKey. A failure puts the last version that worked back.

  Ctrl+click (tbpick): every control under Root, and the sample window when it is built, has
  its WindowProc hooked; a left press made with Ctrl held (Command on a Mac) never reaches
  the control and is reported through OnPick with the control's typeKey and StyleClass.
  The strip at the top (Tools) is the tool's, not the preview's: it is not hooked. The
  hooks come off first thing when the frame goes.

  Trying a version (the AI comparison's "Try it in the preview"): BeginTrial loads another
  text the ordinary way, after putting aside what the editor's document left here -- the
  last version that worked, its folder, and a switch refused for it. EndTrial loads that
  back and restores the refusal (a load of a different text clears it). While a trial is
  on, the window does not load the editor's text into the preview (TTbMainForm.RefreshNow);
  a trial the preview refuses ends at once. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Forms, Controls, Menus, Types, Dialogs,
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
  tyControls.Empty, tyControls.Notification, tyControls.Icons.Lucide, tbsamplewin, tbpick;

const
  { the English of the refusals below: what the AI is told (ModeErrorEn) }
  cTbModeFailedEn = 'In %s mode: %s';
  cTbDensityFailedEn = 'In the %s density: %s';

resourcestring
  rsTbDensityClassic = 'Classic';
  rsTbDensityModern = 'Modern';
  rsTbSingleMode = 'One mode only';
  rsTbModeFailed = cTbModeFailedEn;
  rsTbModeLight = 'light';
  rsTbModeDark = 'dark';
  rsTbDensityFailed = cTbDensityFailedEn;
  rsTbSampleMessage = 'Save the changes to this theme?';
  rsTbSampleInputTitle = 'Rename';
  rsTbSampleInputPrompt = 'New name:';
  rsTbSampleNotifyTitle = 'Saved';
  rsTbSampleNotifyText = 'The theme was saved.';
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
  TTbDisabledEntry = record
    Ctl: TControl;
    Was: Boolean;
  end;

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
    FSampleWin: TTbSampleForm;
    FDisabled: array of TTbDisabledEntry;   { what "disable all" changed, to put back }
    FGoodText, FGoodDir: string;
    FLoadedText: string;                  { the user text the model holds now }
    FModeError: string;
    FModeErrorEn: string;                 { the same in English, for the AI }
    FAllDisabled: Boolean;
    FUpdating: Boolean;
    FOnChanged: TNotifyEvent;
    FPicker: TTbPicker;
    FOnPick: TTbPickEvent;
    FInTrial: Boolean;
    FTrialGoodText, FTrialGoodDir: string;
    FTrialModeError, FTrialModeErrorEn: string;
    procedure PickerPick(Sender: TObject; const ATypeKey, AStyleClass: string);
    procedure FillCodeOnlyData;
    procedure UpdateModeNote;
    procedure SyncSwitches;
    procedure RestoreGood;
    function Notify(out AError: string): Boolean;
    function LoadInto(const AText, ABaseDir: string; out AError: string;
      out ATouched: Boolean): Boolean;
    function GetIsDark: Boolean;
    function GetIsModern: Boolean;
    function GetDocumentModeError: string;
    function GetDocumentModeErrorEn: string;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { AText over the base, as an app would load it; url() / @import from ABaseDir.
      False + AError: the preview keeps the last version that loaded (or the base) }
    function LoadDocument(const AText, ABaseDir: string; out AError: string): Boolean;
    { AText shown instead of the document, until EndTrial; False + AError when the preview
      refuses it (the trial is then over already) }
    function BeginTrial(const AText, ABaseDir: string; out AError: string): Boolean;
    { the document's version back, and its refused switch with it }
    procedure EndTrial;
    { False + AError: the document does not resolve in that mode; the mode is unchanged }
    function SetDark(ADark: Boolean; out AError: string): Boolean;
    { False (ModeError says why): the document does not resolve in that density; the
      density is unchanged }
    function SetModern(AModern: Boolean): Boolean;
    procedure SetAllDisabled(ADisabled: Boolean);
    function HasModes: Boolean;
    function BuildSampleDialog: TTyDialog;          { built, not shown }
    function BuildSampleInput: TTyDialog;           { built, not shown }
    function BuildSampleWindow: TTbSampleForm;      { built once, not shown }
    procedure ShowSampleWindow;
    function StyledControlCount: Integer;           { FOR THE TESTS }
    { what the preview shows: every control's typeKey and the sub-parts its code draws
      (tbcoverage's table), the sample window, the two dialogs, the pop-up menu and the
      notification included }
    procedure CollectTypeKeys(ADest: TStrings);
    property Controller: TTyStyleController read FController;
    { the last refused switch; '' after a switch that went through or a good load of a
      different document }
    property ModeError: string read FModeError;
    property ModeErrorEn: string read FModeErrorEn;   { ModeError in English }
    { the refused switch of the EDITOR's version: ModeError, or during a trial what it was
      when the trial began -- a refusal of the version being tried is not about the text
      being written (the problem list) }
    property DocumentModeError: string read GetDocumentModeError;
    property DocumentModeErrorEn: string read GetDocumentModeErrorEn;
    property InTrial: Boolean read FInTrial;
    property AllDisabled: Boolean read FAllDisabled;
    property IsDark: Boolean read GetIsDark;
    property IsModern: Boolean read GetIsModern;
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;  { a switch was used }
    { Ctrl+click on a preview control: its typeKey and StyleClass }
    property OnPick: TTbPickEvent read FOnPick write FOnPick;
    property Picker: TTbPicker read FPicker;         { FOR THE TESTS }
  end;

type
  { what TbFastProbe could tell }
  TTbFastProbe = (tfpClean, tfpRaised, tfpUnknown);

procedure TbApplyController(ARoot: TWinControl; AController: TTyStyleController);
{ The probe every load and switch runs: TbFastProbe, and only when that one does not say
  clean, TbProbeResolve (which then decides, and names the typeKey). AText is the user text
  the model holds, AModern whether the density pack sits on it. }
function TbProbeDocument(AModel: TTyStyleModel; const AText: string; AModern: Boolean;
  out AError: string): Boolean;
{ Each distinct declaration a paint could evaluate, evaluated once against the model's
  variables for its current mode -- without going through ResolveStyle. tfpUnknown for a
  document with @import (its rules are not all in AText). }
function TbFastProbe(AModel: TTyStyleModel; const AText: string; AModern: Boolean): TTbFastProbe;
{ every catalog typeKey, once, with all its variants and every state: every declaration
  any combination would evaluate. False and AError (typeKey[.variant]: why) on a raise }
function TbProbeResolve(AModel: TTyStyleModel; out AError: string): Boolean;

implementation

{$R *.lfm}

uses
  tyControls.Css.Catalog, tyControls.Css.Parser, tyControls.DefaultTheme,
  tyControls.DensityPack, tyControls.ThemeBundle, tyControls.Columns, tbthemesource,
  tbcoverage, tbproblems;

var
  GBaseSheet: TTyCssStylesheet = nil;   { the model's base layer, parsed once }
  GDensitySheet: TTyCssStylesheet = nil;
  GCatalog: TStringList = nil;          { the catalog typeKeys, lower case, sorted }

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

{ Which variant and state set of AKey raises, and why: the old one-by-one walk, run only
  once the combined resolve below has failed }
function LocateFailure(AModel: TTyStyleModel; const AKey: string; AVariants: TStrings): string;
const
  cStates: array[0..5] of TTyStateSet = ([], [tysHover], [tysActive], [tysFocused],
    [tysDisabled], [tysSelected]);
var
  v, s: Integer;
  cls: string;
begin
  for v := -1 to AVariants.Count - 1 do
  begin
    if v < 0 then cls := '' else cls := AVariants[v];
    for s := 0 to High(cStates) do
      try
        AModel.ResolveStyle(AKey, cls, cStates[s]);
      except
        on E: Exception do
        begin
          if cls <> '' then
            Exit(AKey + '.' + cls + ': ' + E.Message);
          Exit(AKey + ': ' + E.Message);
        end;
      end;
  end;
  Result := '';
end;

{ One resolve per typeKey, with every variant the model knows for it as the class and every
  state at once. ResolveLayer applies the type's rule, each variant's, and each state's for
  the type and for each variant -- every rule any single variant / state combination would
  apply -- so every declaration that could ever be evaluated for the typeKey is evaluated
  here once, against the mode's variables (a missing one, a cycle, a bad value all raise).
  Resolving each variant and each state set on its own evaluated the type's rules
  (1 + variants) x 6 times over and took 0.6 to 1.1 s cold; see TestTheProbeIsQuick. }
function TbProbeResolve(AModel: TTyStyleModel; out AError: string): Boolean;
const
  cEveryState: TTyStateSet = [tysSelected, tysHover, tysFocused, tysActive, tysDisabled];
var
  k, v: Integer;
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
      AModel.GetVariantsForType(key, variants);
      cls := '';
      for v := 0 to variants.Count - 1 do
        if variants[v] <> '' then
        begin
          if cls <> '' then cls := cls + ' ';
          cls := cls + variants[v];
        end;
      try
        AModel.ResolveStyle(key, cls, cEveryState);
      except
        on E: Exception do
        begin
          AError := LocateFailure(AModel, key, variants);
          if AError = '' then
            AError := key + ': ' + E.Message;
          Exit(False);
        end;
      end;
    end;
  finally
    variants.Free;
  end;
  Result := True;
end;

type
  { The model's merged variables, as the evaluator reads them (IndexOfName, then Values):
    each name is asked of the model (RawVar) the first time it is looked up and kept, found
    or not, behind a sorted index -- only the names the declarations use are ever read, and
    none of them twice. RawVar says '' for a name the current mode does not define, so it is
    undefined here as it is in the model. }
  TTbVarList = class(TStringList)
  private
    FModel: TTyStyleModel;
    FIndex: TStringList;                  { name -> Objects = its line, or -1: not defined }
  public
    constructor Create(AModel: TTyStyleModel);
    destructor Destroy; override;
    function IndexOfName(const AName: string): Integer; override;
  end;

constructor TTbVarList.Create(AModel: TTyStyleModel);
begin
  inherited Create;
  FModel := AModel;
  FIndex := TStringList.Create;
  FIndex.CaseSensitive := False;          { as TStrings.IndexOfName compares names }
  FIndex.Sorted := True;
end;

destructor TTbVarList.Destroy;
begin
  FIndex.Free;
  inherited Destroy;
end;

function TTbVarList.IndexOfName(const AName: string): Integer;
var
  i: Integer;
  v: string;
begin
  if FIndex.Find(AName, i) then
    Exit(PtrInt(FIndex.Objects[i]));
  v := FModel.RawVar(AName);
  if v = '' then
    Result := -1
  else
    Result := Add(AName + '=' + v);
  FIndex.AddObject(AName, TObject(PtrInt(Result)));
end;

function ParseCss(const ACss: string): TTyCssStylesheet;
var
  p: TTyCssParser;
begin
  p := TTyCssParser.Create(ACss);
  try
    Result := p.Parse;
  finally
    p.Free;
  end;
end;

{ The fast probe. Why it may stand in for resolving every typeKey: ResolveStyle raises only
  when it evaluates a declaration (TyApplyDeclaration against the merged variables), and the
  declarations it can ever evaluate for a catalog typeKey are those of the user layer's
  rules for it and, unless the user layer has a plain rule for it (UserHasTypeKey) or the
  property cascade is on, the base layer's. Both layers are known text: the base is the
  model's own seed (TyBuiltinThemeCss + TyBuiltinBaseModeCss, LoadInto in the model's
  constructor), the user layer is AText plus the density pack. The variables are the
  model's merged set for its current mode, read back one name at a time (RawVar) as the
  declarations ask for them (TTbVarList) -- a name the mode does not define reads '' and
  stays out, so it is undefined here as it is there. One (property, value) pair evaluates
  the same wherever it stands, so each is evaluated once; the many typeKeys that share a
  base rule share the work. That is what makes it fast (the resolve walk evaluates the
  shared base rules once per typeKey and scans every rule list per variant and state).
  Clean is trusted. Raised is not taken on its own word: TbProbeDocument lets the resolve
  walk decide, so a variable this reading got wrong can cost time, never refuse a theme
  the engine takes. test.themebuilder.preview holds the two to the same verdict. }
function TbFastProbe(AModel: TTyStyleModel; const AText: string; AModern: Boolean): TTbFastProbe;
var
  doc: TTyCssStylesheet;
  vars: TTbVarList;
  userBase, seen: TStringList;

  procedure AddUserBase(ASheet: TTyCssStylesheet);
  var
    r, s: Integer;
    rule: TTyCssRule;
  begin
    for r := 0 to ASheet.Rules.Count - 1 do
    begin
      rule := TTyCssRule(ASheet.Rules[r]);
      for s := 0 to High(rule.Selectors) do
        if (rule.Selectors[s].Variant = '') and not rule.Selectors[s].HasState then
          userBase.Add(LowerCase(rule.Selectors[s].TypeName));
    end;
  end;

  { the rule's declarations, when a paint of some catalog typeKey applies it }
  procedure Evaluate(ASheet: TTyCssStylesheet; AIsBase: Boolean);
  var
    r, s, d: Integer;
    rule: TTyCssRule;
    t, key: string;
    applies: Boolean;
    dummy: TTyStyleSet;
  begin
    for r := 0 to ASheet.Rules.Count - 1 do
    begin
      rule := TTyCssRule(ASheet.Rules[r]);
      applies := False;
      for s := 0 to High(rule.Selectors) do
      begin
        t := LowerCase(rule.Selectors[s].TypeName);
        if (GCatalog.IndexOf(t) >= 0)
           and not (AIsBase and not AModel.PropertyCascade and (userBase.IndexOf(t) >= 0)) then
        begin
          applies := True;
          Break;
        end;
      end;
      if not applies then Continue;
      for d := 0 to High(rule.Declarations) do
      begin
        key := rule.Declarations[d].Prop + #0 + rule.Declarations[d].RawValue;
        if seen.IndexOf(key) >= 0 then Continue;
        seen.Add(key);
        dummy := EmptyStyleSet;
        TyApplyDeclaration(dummy, rule.Declarations[d].Prop, rule.Declarations[d].RawValue, vars);
      end;
    end;
  end;

var
  k: Integer;
begin
  if GCatalog = nil then
  begin
    GCatalog := TStringList.Create;
    for k := 0 to High(TyCatalogTypeKeys) do
      GCatalog.Add(LowerCase(TyCatalogTypeKeys[k]));
    GCatalog.Sorted := True;
  end;
  if GBaseSheet = nil then
    GBaseSheet := ParseCss(TyBuiltinThemeCss + LineEnding + TyBuiltinBaseModeCss);
  if AModern and (GDensitySheet = nil) then
    GDensitySheet := ParseCss(TyDensityModernCss);
  try
    doc := ParseCss(AText);
  except
    Exit(tfpUnknown);   { the model holds a text that parses: nothing to learn here }
  end;
  vars := TTbVarList.Create(AModel);
  userBase := TStringList.Create;
  seen := TStringList.Create;
  try
    if Length(doc.Imports) > 0 then
      Exit(tfpUnknown);
    userBase.Sorted := True;
    userBase.Duplicates := dupIgnore;
    AddUserBase(doc);
    if AModern then
      AddUserBase(GDensitySheet);
    seen.Sorted := True;
    seen.CaseSensitive := True;
    try
      Evaluate(GBaseSheet, True);
      Evaluate(doc, False);
      if AModern then
        Evaluate(GDensitySheet, False);
    except
      Exit(tfpRaised);
    end;
    Result := tfpClean;
  finally
    vars.Free;
    userBase.Free;
    seen.Free;
    doc.Free;
  end;
end;

function TbProbeDocument(AModel: TTyStyleModel; const AText: string; AModern: Boolean;
  out AError: string): Boolean;
begin
  AError := '';
  if TbFastProbe(AModel, AText, AModern) = tfpClean then
    Exit(True);
  Result := TbProbeResolve(AModel, AError);
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
  { Ctrl+click: the preview's controls only, not the strip above them }
  FPicker := TTbPicker.Create(Self);
  FPicker.OnPick := @PickerPick;
  FPicker.HookTree(Root);
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
  { the hooks first, while every hooked control is still there }
  FOnPick := nil;
  if FPicker <> nil then
    FPicker.UnhookAll;
  { before the controller (a component of this frame) goes: the windows on it }
  FreeAndNil(FSampleWin);
  FreeAndNil(FDialogOwner);
  FDisabled := nil;
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
  SyncSwitches;
end;

{ the strip shows what the preview is: a switch set from code (the saved settings) moves too }
procedure TTbPreviewFrame.SyncSwitches;
begin
  FUpdating := True;
  try
    DarkSwitch.Checked := IsDark;
    if IsModern then
      DensityCombo.ItemIndex := 1
    else
      DensityCombo.ItemIndex := 0;
    DisableAllCheck.Checked := FAllDisabled;
  finally
    FUpdating := False;
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
    FLoadedText := AText;
    if FController.Density = tdModern then
      FController.Model.LoadFromCssAdditive(TyDensityModernCss);
    { what the controller's Changed would do first: a two-mode theme with no mode chosen
      takes its default one (its @mode-only variables are undefined otherwise) }
    if (FController.Model.Mode = '') and (FController.Model.DefaultModeName <> '') then
      FController.Model.SetMode(FController.Model.DefaultModeName)
    { a document with one mode only is shown in it: a dark left over from the last
      document would leave the switch (and the saved setting) saying dark with nothing
      dark to show }
    else if (Length(FController.Model.ModeNames) = 0) and (FController.Model.Mode <> '') then
      FController.Model.SetMode('');
  except
    on E: Exception do
    begin
      AError := E.Message;
      Exit(False);
    end;
  end;
  { probe BEFORE Changed: Changed has every control re-measure itself, which resolves its
    style -- a theme that does not resolve would raise from there (and from every paint) }
  Result := TbProbeDocument(FController.Model, AText, FController.Density = tdModern, AError);
  if Result then
    Result := Notify(AError);
end;

{ the controller's Changed: repaint, and tell the listeners (the sample window) }
function TTbPreviewFrame.Notify(out AError: string): Boolean;
begin
  AError := '';
  try
    FController.Changed;
    Result := True;
  except
    on E: Exception do
    begin
      AError := E.Message;
      Result := False;
    end;
  end;
end;

function TTbPreviewFrame.LoadDocument(const AText, ABaseDir: string; out AError: string): Boolean;
var
  touched: Boolean;
begin
  Result := LoadInto(AText, ABaseDir, AError, touched);
  if Result then
  begin
    { a refused switch holds until the document changes: the same text loaded again (a
      save, a refresh) resolves in that mode no better than it did }
    if (AText <> FGoodText) or (ABaseDir <> FGoodDir) then
    begin
      FModeError := '';
      FModeErrorEn := '';
    end;
    FGoodText := AText;
    FGoodDir := ABaseDir;
  end
  else if touched then
    { a load that raised left the model as it was, but one that loaded and then failed
      the probe did not: put the last good version back (or the bare base) }
    RestoreGood;
  UpdateModeNote;
end;

function TTbPreviewFrame.GetDocumentModeError: string;
begin
  if FInTrial then Result := FTrialModeError else Result := FModeError;
end;

function TTbPreviewFrame.GetDocumentModeErrorEn: string;
begin
  if FInTrial then Result := FTrialModeErrorEn else Result := FModeErrorEn;
end;

function TTbPreviewFrame.BeginTrial(const AText, ABaseDir: string; out AError: string): Boolean;
begin
  if not FInTrial then
  begin
    { what the editor's document left here; EndTrial puts exactly this back }
    FTrialGoodText := FGoodText;
    FTrialGoodDir := FGoodDir;
    FTrialModeError := FModeError;
    FTrialModeErrorEn := FModeErrorEn;
    FInTrial := True;
  end;
  Result := LoadDocument(AText, ABaseDir, AError);
  if not Result then
    EndTrial;                       { refused: the preview shows the editor's version again }
end;

procedure TTbPreviewFrame.EndTrial;
var
  err: string;
begin
  if not FInTrial then Exit;
  FInTrial := False;
  LoadDocument(FTrialGoodText, FTrialGoodDir, err);
  FModeError := FTrialModeError;   { LoadDocument cleared it: the text changed twice }
  FModeErrorEn := FTrialModeErrorEn;
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

procedure TTbPreviewFrame.CollectTypeKeys(ADest: TStrings);

  procedure Add(const AKey: string);
  var
    i: Integer;
  begin
    for i := 0 to ADest.Count - 1 do
      if SameText(ADest[i], AKey) then
        Exit;
    ADest.Add(AKey);
  end;

  procedure AddControl(AControl: TControl);
  var
    i: Integer;
  begin
    if Supports(AControl, ITyStyleable) then
      Add((AControl as ITyStyleable).GetStyleTypeKey);
    TbPartKeysOfClass(AControl.ClassType, ADest);
    if AControl is TWinControl then
      for i := 0 to TWinControl(AControl).ControlCount - 1 do
        AddControl(TWinControl(AControl).Controls[i]);
  end;

var
  d: TTyDialog;
begin
  AddControl(Root);
  AddControl(BuildSampleWindow);
  d := BuildSampleDialog;
  try
    AddControl(d);
  finally
    d.Free;
  end;
  d := BuildSampleInput;
  try
    AddControl(d);
  finally
    d.Free;
  end;
  TbPartKeysOfClass(SamplePopup.ClassType, ADest);
  Add(TTyNotification.StyleTypeKey);
  Add(TTyNotification.CloseStyleTypeKey);
end;

{ ---- the switches ---- }

function TTbPreviewFrame.SetDark(ADark: Boolean; out AError: string): Boolean;
var
  old, want, ignored: string;
begin
  AError := '';
  if ADark then want := 'dark' else want := 'light';
  old := FController.Mode;
  if SameText(old, want) then Exit(True);
  { switch the model only, probe, and only then tell the controls (see LoadInto) }
  FController.Model.SetMode(want);
  Result := TbProbeDocument(FController.Model, FLoadedText, FController.Density = tdModern,
    AError);
  if Result then
    Result := Notify(AError);
  if not Result then
  begin
    FController.Model.SetMode(old);
    Notify(ignored);
    { the mode's display name, not its internal one: it is read in the problem list; and
      the English, for the AI }
    FModeErrorEn := Format(cTbModeFailedEn, [want, TbAsciiOr(AError, 'it does not resolve')]);
    if ADark then
      AError := Format(rsTbModeFailed, [rsTbModeDark, AError])
    else
      AError := Format(rsTbModeFailed, [rsTbModeLight, AError]);
  end
  else
    FModeErrorEn := '';
  FModeError := AError;
  SyncSwitches;
end;

function TTbPreviewFrame.SetModern(AModern: Boolean): Boolean;
var
  mode, err: string;
  touched: Boolean;

  procedure Apply(AOn: Boolean);
  begin
    { A density change reloads the controller's own theme layer -- there is none here, so
      the base alone: the document goes and is loaded again. The controls keep the height
      they were built with; what changes is the density's tokens (font size, padding). }
    if AOn then
      FController.Density := tdModern
    else
      FController.Density := tdClassic;
    if (mode <> '') and not SameText(FController.Model.Mode, mode) then
      FController.Model.SetMode(mode);
  end;

begin
  Result := True;
  if AModern = IsModern then Exit;
  mode := FController.Mode;
  Apply(AModern);
  { probes before the controls hear of it }
  if not LoadInto(FGoodText, FGoodDir, err, touched) then
  begin
    { the document does not resolve in this density (a variable the density pack sets
      that the document uses otherwise): back to the density it did, and say why }
    Apply(not AModern);
    RestoreGood;
    if AModern then
    begin
      FModeError := Format(rsTbDensityFailed, [rsTbDensityModern, err]);
      FModeErrorEn := Format(cTbDensityFailedEn, ['modern', TbAsciiOr(err, 'it does not resolve')]);
    end
    else
    begin
      FModeError := Format(rsTbDensityFailed, [rsTbDensityClassic, err]);
      FModeErrorEn := Format(cTbDensityFailedEn, ['classic', TbAsciiOr(err, 'it does not resolve')]);
    end;
    Result := False;
  end;
  UpdateModeNote;
end;

procedure TTbPreviewFrame.SetAllDisabled(ADisabled: Boolean);

  procedure Walk(AParent: TWinControl);
  var
    i, n: Integer;
    c: TControl;
  begin
    for i := 0 to AParent.ControlCount - 1 do
    begin
      c := AParent.Controls[i];
      { the pages themselves stay enabled: the tabs must still switch }
      if ((c is TTyCustomControl) or (c is TTyGraphicControl)) and (AParent <> Pages) then
      begin
        n := Length(FDisabled);
        SetLength(FDisabled, n + 1);
        FDisabled[n].Ctl := c;
        FDisabled[n].Was := c.Enabled;
        c.Enabled := False;
      end;
      if c is TWinControl then
        Walk(TWinControl(c));
    end;
  end;

var
  i: Integer;
begin
  if ADisabled = FAllDisabled then Exit;
  FAllDisabled := ADisabled;
  if ADisabled then
  begin
    FDisabled := nil;
    Walk(Pages);
  end
  else
  begin
    for i := High(FDisabled) downto 0 do
      FDisabled[i].Ctl.Enabled := FDisabled[i].Was;
    FDisabled := nil;
  end;
  SyncSwitches;
end;

procedure TTbPreviewFrame.DarkSwitchChange(Sender: TObject);
var
  err: string;
begin
  if FUpdating then Exit;
  SetDark(DarkSwitch.Checked, err);   { refused: SyncSwitches springs the switch back }
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TTbPreviewFrame.DensityComboChange(Sender: TObject);
begin
  if FUpdating then Exit;
  SetModern(DensityCombo.ItemIndex = 1);
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TTbPreviewFrame.DisableAllCheckChange(Sender: TObject);
begin
  if FUpdating then Exit;
  SetAllDisabled(DisableAllCheck.Checked);
end;

{ ---- the pop-ups ---- }

{ The message and input dialogs are built with Application as their owner, and a dialog
  adopts its owner's controller when it shows -- or else the main form's, i.e. the TOOL's
  theme. Moved under a hidden form that carries the preview's controller, it wears the
  preview's theme. }
function TTbPreviewFrame.BuildSampleDialog: TTyDialog;
begin
  Result := TyBuildMessageDialog(rsTbSampleMessage, mtConfirmation, [mbYes, mbNo, mbCancel]);
  if Result.Owner <> nil then
    Result.Owner.RemoveComponent(Result);
  FDialogOwner.InsertComponent(Result);
end;

function TTbPreviewFrame.BuildSampleInput: TTyDialog;
var
  edt: TTyEdit;
begin
  Result := TyBuildInputDialog(rsTbSampleInputTitle, rsTbSampleInputPrompt, 'theme', edt);
  if Result.Owner <> nil then
    Result.Owner.RemoveComponent(Result);
  FDialogOwner.InsertComponent(Result);
end;

procedure TTbPreviewFrame.BtnMessageClick(Sender: TObject);
var
  d: TTyDialog;
begin
  d := BuildSampleDialog;
  try
    d.ShowModal;
  finally
    d.Free;
  end;
end;

procedure TTbPreviewFrame.BtnInputClick(Sender: TObject);
var
  d: TTyDialog;
begin
  d := BuildSampleInput;
  try
    d.ShowModal;
  finally
    d.Free;
  end;
end;

procedure TTbPreviewFrame.BtnPopupClick(Sender: TObject);
var
  p: TPoint;
begin
  p := BtnPopup.ClientToScreen(Point(0, BtnPopup.Height));
  SamplePopup.PopUp(p.X, p.Y);
end;

procedure TTbPreviewFrame.BtnNotifyClick(Sender: TObject);
begin
  SampleNotify.Title := rsTbSampleNotifyTitle;
  SampleNotify.Message := rsTbSampleNotifyText;
  SampleNotify.Show;
end;

function TTbPreviewFrame.BuildSampleWindow: TTbSampleForm;
begin
  if FSampleWin = nil then
  begin
    FSampleWin := TTbSampleForm.Create(Self);
    FSampleWin.UseController(FController);
    FPicker.HookTree(FSampleWin);
  end;
  Result := FSampleWin;
end;

procedure TTbPreviewFrame.PickerPick(Sender: TObject; const ATypeKey, AStyleClass: string);
begin
  if Assigned(FOnPick) then
    FOnPick(Self, ATypeKey, AStyleClass);
end;

procedure TTbPreviewFrame.ShowSampleWindow;
begin
  BuildSampleWindow.Show;
end;

procedure TTbPreviewFrame.BtnSampleWindowClick(Sender: TObject);
begin
  ShowSampleWindow;
end;

finalization
  FreeAndNil(GBaseSheet);
  FreeAndNil(GDensitySheet);
  FreeAndNil(GCatalog);
end.
