unit tyControls.Design;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Graphics, LCLIntf,
  PropEdits, ComponentEditors, ProjectIntf, FormEditingIntf, LazIDEIntf,
  LResources, tyControls.Types,
  tyControls.Base, tyControls.Controller, tyControls.StyleModel,
  tyControls.Button, tyControls.TyLabel, tyControls.Edit, tyControls.NumericEdit,
  tyControls.CurrencyEdit, tyControls.MaskEdit, tyControls.URLEdit, tyControls.ComboEdit,
  tyControls.TrackEdit, tyControls.ColorBox, tyControls.ColorListBox, tyControls.FontComboBox,
  tyControls.FontListBox, tyControls.FontSizeComboBox, tyControls.CheckListBox,
  tyControls.ColorComboBox, tyControls.MRUComboBox, tyControls.ComboBoxEx,
  tyControls.OfficeListBox, tyControls.OfficeComboBox,
  tyControls.ColorGrid, tyControls.LColorPicker, tyControls.HSColorPicker,
  tyControls.AdvancedListBox, tyControls.AdvancedComboBox, tyControls.CheckComboBox,
  tyControls.ValueListEditor, tyControls.Calculator, tyControls.CalcEdit,
  tyControls.CalcCurrencyEdit,
  tyControls.CheckBox, tyControls.Panel, tyControls.ComboBox,
  tyControls.ScrollBar, tyControls.Form,
  tyControls.ListBox, tyControls.ProgressBar, tyControls.Gauge,
  tyControls.CircularProgress, tyControls.ActivityIndicator, tyControls.ActivityBar,
  tyControls.Meter, tyControls.LevelMeter, tyControls.Dial, tyControls.AnalogClock,
  tyControls.Sparkline, tyControls.Rating, tyControls.GearDial,
  tyControls.GearActivityIndicator, tyControls.UpDown,
  tyControls.LinkLabel, tyControls.ShadowLabel, tyControls.GlowLabel,
  tyControls.Hint, tyControls.BalloonHint,
  tyControls.IconFont, tyControls.CharImage, tyControls.GlyphImageList,
  tyControls.Image, tyControls.ImageCollection,
  tyControls.GlyphButtons, tyControls.DropButtons, tyControls.ColorButton,
  tyControls.ButtonGroup, tyControls.Ribbon, tyControls.RibbonAppMenu,
  tyControls.RibbonQuickAccess, tyControls.RibbonGallery, tyControls.RibbonBackstage,
  tyControls.ToggleSwitch,
  tyControls.TrackBar, tyControls.GroupBox, tyControls.PageControl, tyControls.TabSheet,
  tyControls.SpinEdit, tyControls.Memo, tyControls.Menu, tyControls.NativeStyler,
  tyControls.Splitter, tyControls.StatusBar, tyControls.ToolBar,
  tyControls.Calendar, tyControls.DateTimePicker, tyControls.TabSet,
  tyControls.TreeView, tyControls.Dialogs, tyControls.Dialogs.SelectPath,
  tyControls.Dialogs.Color, tyControls.Dialogs.Font,
  tyControls.Dialogs.Find, tyControls.Dialogs.Progress, tyControls.Dialogs.About,
  tyControls.Bevel, tyControls.Divider, tyControls.PaintPanel, tyControls.SizeBox;
type
  TTyStyleClassPropertyEditor = class(TStringPropertyEditor)
  public
    function GetAttributes: TPropertyAttributes; override;
    procedure GetValues(Proc: TGetStrProc); override;
  end;

  { Manages TTyPageControl pages in the designer (no header click-switch on a
    custom-drawn control). Verbs: Add / Delete / Show Next / Show Previous Page. }
  TTyPageControlEditor = class(TDefaultComponentEditor)
  private
    function PC: TTyPageControl;
  public
    function GetVerbCount: Integer; override;
    function GetVerb(Index: Integer): string; override;
    procedure ExecuteVerb(Index: Integer); override;
  end;

  { Previews a dialog component when it is double-clicked in the designer (verb 0),
    mirroring LCL's TCommonDialogComponentEditor. Modal wrappers call Execute; the two
    modeless ones (Find/Replace, Progress) call a guard-free PreviewInDesigner because
    their Execute/Show early-exit under csDesigning. }
  TTyDialogComponentEditor = class(TComponentEditor)
  public
    function GetVerbCount: Integer; override;
    function GetVerb(Index: Integer): string; override;
    procedure ExecuteVerb(Index: Integer); override;
  end;

  { Read-only `About` property: shows TyVersion in the Object Inspector and opens the
    About dialog (version + clickable homepage link) when the '...' button is clicked. }
  TTyAboutEditor = class(TStringPropertyEditor)
  public
    function GetAttributes: TPropertyAttributes; override;
    procedure Edit; override;
  end;

  { File > New entry that creates a unit whose form descends from TTyForm — a borderless
    form with a persistent chrome engine. The generated form comes WITH a top-aligned
    TTyTitleBar already associated (TitleBar = TyTitleBar1). FWithController=True (the
    TyControls Application main form) additionally drops a TTyStyleController and wires the
    form + title bar to it; the plain form leaves the controller unset so it can be pointed
    at the main window's controller later. }
  TTyFormFileDescriptor = class(TFileDescPascalUnitWithResource)
  protected
    FWithController: Boolean;
  public
    constructor Create; override;
    function GetInterfaceUsesSection: string; override;
    function GetInterfaceSource(const Filename, SourceName, ResourceName: string): string; override;
    function GetResourceSource(const ResourceName: string): string; override;
    function GetLocalizedName: string; override;
    function GetLocalizedDescription: string; override;
  end;

  { The main form for a "TyControls Application" project: a themed TTyForm carrying its own
    TTyStyleController, with both the form and the title bar associated to it. }
  TTyMainFormFileDescriptor = class(TTyFormFileDescriptor)
  public
    constructor Create; override;
    function GetLocalizedName: string; override;
    function GetLocalizedDescription: string; override;
  end;

  { File > New entry that creates a unit whose form descends from TTyDialog — a themed,
    close-only, non-resizable modal dialog base. The generated form comes WITH a top-aligned
    TTyTitleBar already associated and BorderIcons = [biSystemMenu] (close button only), so the
    user can design custom dialog content + buttons and show it modally. }
  TTyDialogFileDescriptor = class(TTyFormFileDescriptor)
  public
    constructor Create; override;
    function GetInterfaceUsesSection: string; override;
    function GetInterfaceSource(const Filename, SourceName, ResourceName: string): string; override;
    function GetResourceSource(const ResourceName: string): string; override;
    function GetLocalizedName: string; override;
    function GetLocalizedDescription: string; override;
  end;

  { File > New > Project > "TyControls Application": a normal LCL GUI app whose main form is
    a themed TTyForm (title bar + style controller), with the tycontrols package dependency
    pre-added. Mirrors the IDE's built-in Application descriptor. }
  TTyApplicationDescriptor = class(TProjectDescriptor)
  public
    constructor Create; override;
    function GetLocalizedName: string; override;
    function GetLocalizedDescription: string; override;
    function InitProject(AProject: TLazProject): TModalResult; override;
    function CreateStartFiles(AProject: TLazProject): TModalResult; override;
  end;

procedure Register;

implementation

resourcestring
  rsDtFormName        = 'TyControls Form';
  rsDtFormDescription = 'A borderless form descending from TTyForm, with a top-aligned ' +
    'TTyTitleBar already attached (drag to move, double-click to maximize). Point its ' +
    'Controller at your main window''s style controller to theme it, or lay out your controls ' +
    'below the bar.';
  rsDtMainFormName        = 'TyControls Main Form';
  rsDtMainFormDescription = 'A themed TTyForm carrying its own TTyStyleController, with the ' +
    'form and the title bar already associated to it — the root window for a TyControls application.';
  rsDtDialogName        = 'TyControls Dialog';
  rsDtDialogDescription = 'A themed custom-drawn modal dialog (TTyDialog): borderless, ' +
    'close-only, non-resizable, centered — design your own dialog content and buttons.';
  rsDtAppName        = 'TyControls Application';
  rsDtAppDescription = 'A graphical TyControls application. The main form is a themed TTyForm ' +
    '(custom title bar + style controller); the tycontrols package is added automatically.';
  rsDtAboutTitle   = 'About TyControls';
  rsDtAboutTagline = 'BGRABitmap-drawn, .tycss-themed LCL control library';
  rsDtAboutVersion = 'Version %s';
  rsDtAboutLicense = 'Modified LGPL (LCL-compatible linking exception)';
  rsDtPageAdd      = 'Add Page';
  rsDtPageDelete   = 'Delete Page';
  rsDtPageShowNext = 'Show Next Page';
  rsDtPageShowPrev = 'Show Previous Page';
  rsDtDialogPreview = 'Preview';

var
  // The themed main-form descriptor, reused by the TyControls Application project's
  // CreateStartFiles. Held here so registration owns its (refcounted) lifetime.
  TyMainFormDescriptor: TTyMainFormFileDescriptor;

{ The design-time 'About' property (OI '...' button) now opens the library's OWN themed
  TTyAboutDialog — so what you see at design time is exactly the dialog consumers ship, custom
  title bar and all — instead of the old code-built native TForm. Empty fields (here: copyright)
  are omitted by the dialog. }
procedure ShowTyAboutDialog;
begin
  TyShowAbout(rsDtAboutTitle, 'TyControls', Format(rsDtAboutVersion, [TyVersion]),
    rsDtAboutTagline, '', rsDtAboutLicense, TyHomepageUrl);
end;

function TTyAboutEditor.GetAttributes: TPropertyAttributes;
begin
  Result := [paReadOnly, paDialog];   // greyed value + '...' button that opens the dialog
end;

procedure TTyAboutEditor.Edit;
begin
  ShowTyAboutDialog;
end;

function TTyStyleClassPropertyEditor.GetAttributes: TPropertyAttributes;
begin
  Result := (inherited GetAttributes) + [paValueList, paMultiSelect];
end;

procedure TTyStyleClassPropertyEditor.GetValues(Proc: TGetStrProc);
var
  comp: TPersistent;
  sty: ITyStyleable;
  ctrl: TTyStyleController;
  model: TTyStyleModel;
  list: TStringList;
  i: Integer;
begin
  // Dynamic + per control type: list exactly the variants the active theme defines for
  // THIS control's typeKey, read from its controller's model (else the global default,
  // which always carries the built-in defaults). No more hard-coded cross-control list.
  comp := GetComponent(0);
  if not Supports(comp, ITyStyleable, sty) then Exit;
  // Both base classes expose a published Controller but share no ancestor.
  ctrl := nil;
  if comp is TTyGraphicControl then ctrl := TTyGraphicControl(comp).Controller
  else if comp is TTyCustomControl then ctrl := TTyCustomControl(comp).Controller;
  if ctrl <> nil then model := ctrl.Model else model := TyDefaultController.Model;
  list := TStringList.Create;
  try
    list.Sorted := True;            // stable display order
    list.Duplicates := dupIgnore;
    model.GetVariantsForType(sty.GetStyleTypeKey, list);
    for i := 0 to list.Count - 1 do
      Proc(list[i]);
  finally
    list.Free;
  end;
end;

function TTyPageControlEditor.PC: TTyPageControl;
begin
  Result := Component as TTyPageControl;
end;

function TTyPageControlEditor.GetVerbCount: Integer;
begin
  Result := 4;
end;

function TTyPageControlEditor.GetVerb(Index: Integer): string;
begin
  case Index of
    0: Result := rsDtPageAdd;
    1: Result := rsDtPageDelete;
    2: Result := rsDtPageShowNext;
    3: Result := rsDtPageShowPrev;
  else
    Result := '';
  end;
end;

procedure TTyPageControlEditor.ExecuteVerb(Index: Integer);
var
  Hook: TPropertyEditorHook;
  NewPage: TTyTabSheet;
  NewName: string;
  DelP: TPersistent;
begin
  case Index of
    0: begin
         Hook := nil;
         if not GetHook(Hook) then Exit;
         NewPage := TTyTabSheet.Create(PC.Owner);
         NewPage.Parent := PC;                       // SetParent -> RegisterPage
         NewName := GetDesigner.CreateUniqueComponentName(NewPage.ClassName);
         NewPage.Caption := NewName;
         NewPage.Name := NewName;
         PC.ActivePage := NewPage;
         Hook.PersistentAdded(NewPage, True);
         Modified;
       end;
    1: begin
         if (PC.ActivePageIndex < 0) or (PC.PageCount = 0) then Exit;
         Hook := nil;
         if not GetHook(Hook) then Exit;
         DelP := TPersistent(PC.ActivePage);
         Hook.DeletePersistent(DelP);
       end;
    2: if PC.PageCount > 0 then
         PC.ActivePageIndex := (PC.ActivePageIndex + 1) mod PC.PageCount;
    3: if PC.PageCount > 0 then
         PC.ActivePageIndex := (PC.ActivePageIndex + PC.PageCount - 1) mod PC.PageCount;
  end;
end;

{ TTyDialogComponentEditor }

function TTyDialogComponentEditor.GetVerbCount: Integer;
begin
  Result := 1;
end;

function TTyDialogComponentEditor.GetVerb(Index: Integer): string;
begin
  if Index = 0 then Result := rsDtDialogPreview
  else Result := inherited GetVerb(Index);
end;

procedure TTyDialogComponentEditor.ExecuteVerb(Index: Integer);
begin
  if Index <> 0 then begin inherited ExecuteVerb(Index); Exit; end;
  // Modeless components early-exit under csDesigning, so use their guard-free preview.
  // TTyReplaceDialog IS a TTyFindDialog, so that branch covers it (must precede none).
  if      Component is TTyProgressDialog then TTyProgressDialog(Component).PreviewInDesigner
  else if Component is TTyFindDialog     then TTyFindDialog(Component).PreviewInDesigner
  else if Component is TTyMessage        then TTyMessage(Component).Execute
  else if Component is TTyInputDialog    then TTyInputDialog(Component).Execute
  else if Component is TTyPasswordDialog then TTyPasswordDialog(Component).Execute
  else if Component is TTyTextDialog     then TTyTextDialog(Component).Execute
  else if Component is TTySelectValueDialog then TTySelectValueDialog(Component).Execute
  else if Component is TTySelectPathDialog  then TTySelectPathDialog(Component).Execute
  else if Component is TTyColorDialog    then TTyColorDialog(Component).Execute
  else if Component is TTyFontDialog     then TTyFontDialog(Component).Execute
  else if Component is TTyAboutDialog    then TTyAboutDialog(Component).Execute;
end;

{ TTyFormFileDescriptor }

constructor TTyFormFileDescriptor.Create;
begin
  inherited Create;
  FWithController := False;
  Name := 'TyControls form';        // internal id (File > New list)
  ResourceClass := TTyForm;         // generated class descends from TTyForm
  UseCreateFormStatements := True;  // add to the project's auto-create forms
  // Auto-add the runtime package dependency so the generated `uses tyControls.Form`
  // resolves in a fresh project (otherwise the IDE only adds LCL via its fallback).
  RequiredPackages := 'tycontrols';
end;

function TTyFormFileDescriptor.GetInterfaceUsesSection: string;
begin
  Result := inherited GetInterfaceUsesSection + ', tyControls.Form';
  if FWithController then
    Result := Result + ', tyControls.Controller';
end;

function TTyFormFileDescriptor.GetInterfaceSource(const Filename, SourceName,
  ResourceName: string): string;
const
  LE = LineEnding;
var
  fields: string;
begin
  // Declare the pre-placed components as published fields so the generated class matches the
  // .lfm GetResourceSource emits (the IDE binds streamed components to these fields by name).
  fields := '    TyTitleBar1: TTyTitleBar;' + LE;
  if FWithController then
    fields := fields + '    TyStyleController1: TTyStyleController;' + LE;
  Result :=
     'type' + LE
    + '  T' + ResourceName + ' = class(TTyForm)' + LE
    + fields
    + '  private' + LE
    + LE
    + '  public' + LE
    + LE
    + '  end;' + LE
    + LE
    + 'var' + LE
    + '  ' + ResourceName + ': T' + ResourceName + ';' + LE
    + LE;
end;

function TTyFormFileDescriptor.GetResourceSource(const ResourceName: string): string;
const
  LE = LineEnding;
var
  s: string;
begin
  // A non-empty result OVERRIDES the IDE's automatic .lfm generation. The form class is
  // T<ResourceName> (the convention GetInterfaceSource + the IDE both use). Modelled on a
  // real IDE-generated TTyForm + title-bar .lfm (examples/demo/chromeform.lfm); the form-level
  // `TitleBar =` / `Controller =` are forward refs the LFM reader resolves via fixups.
  s :=
     'object ' + ResourceName + ': T' + ResourceName + LE
    + '  Left = 300' + LE
    + '  Height = 320' + LE
    + '  Top = 200' + LE
    + '  Width = 480' + LE
    + '  Caption = ''' + ResourceName + '''' + LE;
  if FWithController then
    s := s + '  Controller = TyStyleController1' + LE;
  s := s
    + '  TitleBar = TyTitleBar1' + LE
    + '  object TyTitleBar1: TTyTitleBar' + LE
    + '    Left = 0' + LE
    + '    Height = 32' + LE
    + '    Top = 0' + LE
    + '    Width = 480' + LE
    + '    Align = alTop' + LE
    + '    Caption = ''' + ResourceName + '''' + LE;
  if FWithController then
    s := s + '    Controller = TyStyleController1' + LE;
  s := s + '  end' + LE;
  if FWithController then
    s := s
      + '  object TyStyleController1: TTyStyleController' + LE
      + '    Left = 64' + LE
      + '    Top = 48' + LE
      + '  end' + LE;
  Result := s + 'end' + LE;
end;

function TTyFormFileDescriptor.GetLocalizedName: string;
begin
  Result := rsDtFormName;
end;

function TTyFormFileDescriptor.GetLocalizedDescription: string;
begin
  Result := rsDtFormDescription;
end;

{ TTyMainFormFileDescriptor }

constructor TTyMainFormFileDescriptor.Create;
begin
  inherited Create;
  FWithController := True;
  Name := 'TyControls main form';   // internal id (distinct from the plain form)
end;

function TTyMainFormFileDescriptor.GetLocalizedName: string;
begin
  Result := rsDtMainFormName;
end;

function TTyMainFormFileDescriptor.GetLocalizedDescription: string;
begin
  Result := rsDtMainFormDescription;
end;

{ TTyDialogFileDescriptor }

constructor TTyDialogFileDescriptor.Create;
begin
  inherited Create;
  Name := 'TyControls dialog';      // internal id (distinct from the forms)
  ResourceClass := TTyDialog;       // generated class descends from TTyDialog
end;

function TTyDialogFileDescriptor.GetInterfaceUsesSection: string;
begin
  // Base adds tyControls.Form (TTyTitleBar); the dialog form also needs tyControls.Dialogs
  // so `class(TTyDialog)` resolves in the generated unit.
  Result := inherited GetInterfaceUsesSection + ', tyControls.Dialogs';
end;

function TTyDialogFileDescriptor.GetInterfaceSource(const Filename, SourceName,
  ResourceName: string): string;
const
  LE = LineEnding;
begin
  // NOTE: full override (base hard-codes TTyForm). Keep in sync with
  // TTyFormFileDescriptor.GetInterfaceSource — only the ancestor class differs
  // (class(TTyDialog) vs class(TTyForm)), and there is no controller field.
  // The pre-placed title bar is the only published field.
  Result :=
     'type' + LE
    + '  T' + ResourceName + ' = class(TTyDialog)' + LE
    + '    TyTitleBar1: TTyTitleBar;' + LE
    + '  private' + LE
    + LE
    + '  public' + LE
    + LE
    + '  end;' + LE
    + LE
    + 'var' + LE
    + '  ' + ResourceName + ': T' + ResourceName + ';' + LE
    + LE;
end;

function TTyDialogFileDescriptor.GetResourceSource(const ResourceName: string): string;
const
  LE = LineEnding;
begin
  // NOTE: full override (base hard-codes TTyForm). Keep in sync with
  // TTyFormFileDescriptor.GetResourceSource — only the ancestor class + the added
  // BorderIcons = [biSystemMenu] line differ (and there is no controller object). The
  // form-level `TitleBar =` is a forward ref the LFM reader resolves via fixups.
  Result :=
     'object ' + ResourceName + ': T' + ResourceName + LE
    + '  Left = 300' + LE
    + '  Height = 320' + LE
    + '  Top = 200' + LE
    + '  Width = 480' + LE
    + '  BorderIcons = [biSystemMenu]' + LE
    + '  Caption = ''' + ResourceName + '''' + LE
    + '  TitleBar = TyTitleBar1' + LE
    + '  object TyTitleBar1: TTyTitleBar' + LE
    + '    Left = 0' + LE
    + '    Height = 32' + LE
    + '    Top = 0' + LE
    + '    Width = 480' + LE
    + '    Align = alTop' + LE
    + '    Caption = ''' + ResourceName + '''' + LE
    + '  end' + LE
    + 'end' + LE;
end;

function TTyDialogFileDescriptor.GetLocalizedName: string;
begin
  Result := rsDtDialogName;
end;

function TTyDialogFileDescriptor.GetLocalizedDescription: string;
begin
  Result := rsDtDialogDescription;
end;

{ TTyApplicationDescriptor }

constructor TTyApplicationDescriptor.Create;
begin
  inherited Create;
  Name := 'TyControls Application';
  // Inherit the user's IDE-wide default project compiler options, like a normal Application.
  Flags := Flags + [pfUseDefaultCompilerOptions];
end;

function TTyApplicationDescriptor.GetLocalizedName: string;
begin
  Result := rsDtAppName;
end;

function TTyApplicationDescriptor.GetLocalizedDescription: string;
begin
  Result := rsDtAppDescription;
end;

function TTyApplicationDescriptor.InitProject(AProject: TLazProject): TModalResult;
const
  LE = LineEnding;
var
  MainFile: TLazProjectFile;
  NewSource: string;
begin
  Result := inherited InitProject(AProject);

  MainFile := AProject.CreateProjectFile('project1.lpr');
  MainFile.IsPartOfProject := True;
  AProject.AddFile(MainFile, False);
  AProject.MainFileID := 0;          // the .lpr is the main file
  AProject.UseAppBundle := True;
  AProject.UseManifest := True;
  AProject.Scaled := True;
  AProject.LoadDefaultIcon;

  NewSource :=
     'program Project1;' + LE + LE
    + '{$mode objfpc}{$H+}' + LE + LE
    + 'uses' + LE
    + '  {$IFDEF UNIX}' + LE
    + '  cthreads,' + LE
    + '  {$ENDIF}' + LE
    + '  {$IFDEF HASAMIGA}' + LE
    + '  athreads,' + LE
    + '  {$ENDIF}' + LE
    + '  Interfaces, // this includes the LCL widgetset' + LE
    + '  Forms' + LE
    + '  { you can add units after this };' + LE + LE
    + 'begin' + LE
    + '  RequireDerivedFormResource := True;' + LE
    + '  Application.Scaled := True;' + LE
    + '  {$PUSH}{$WARN 5044 OFF}' + LE
    + '  Application.MainFormOnTaskbar := True;' + LE
    + '  {$POP}' + LE
    + '  Application.Initialize;' + LE
    + '  Application.Run;' + LE
    + 'end.' + LE + LE;
  AProject.MainFile.SetSourceText(NewSource, True);

  AProject.AddPackageDependency('LCL');
  AProject.AddPackageDependency('tycontrols');   // the main form descends from TTyForm
  AProject.LazCompilerOptions.Win32GraphicApp := True;
  AProject.LazCompilerOptions.UnitOutputDirectory := 'lib' + PathDelim + '$(TargetCPU)-$(TargetOS)';
  AProject.LazCompilerOptions.TargetFilename := 'project1';

  Result := mrOK;
end;

function TTyApplicationDescriptor.CreateStartFiles(AProject: TLazProject): TModalResult;
begin
  // Create + open the themed main form. UseCreateFormStatements makes the IDE add
  // `Application.CreateForm(...)` + the unit to the .lpr automatically.
  Result := LazarusIDE.DoNewEditorFile(TyMainFormDescriptor, '', '',
    [nfIsPartOfProject, nfOpenInEditor, nfCreateDefaultSrc]);
end;

procedure Register;
begin
  // Register the component-palette icons (24x24 PNG per class, generated by
  // tools/genicons -> scripts/gen-icons.ps1). The IDE looks each up by class name;
  // this MUST run before RegisterComponents so the palette finds them.
  {$I tycontrols_icons.lrs}
  // Make TTyForm a recognized designer base class. Without this the form designer
  // cannot resolve `class(TTyForm)` as an ancestor and silently falls back to TForm
  // (sourcefilemanager FindBaseComponentClass -> StandardDesignerBaseClasses[TForm]),
  // so the Object Inspector shows none of TTyForm's published chrome properties
  // (TitleBar / TitleHeight / BorderIcons / Resizable). RegisterComponents only
  // covers droppable controls, not base form classes — this is the form-level analog.
  if FormEditingHook <> nil then
  begin
    FormEditingHook.RegisterDesignerBaseClass(TTyForm);
    // TTyDialog is a distinct designer base class (close-only modal dialog): register it so
    // `class(TTyDialog)` resolves as an ancestor and the OI shows its chrome, same as TTyForm.
    FormEditingHook.RegisterDesignerBaseClass(TTyDialog);
  end;
  // The palette is split into functional groups so no single tab is overcrowded. NOTE: the
  // gen-icons.ps1 drift-guard parses EVERY RegisterComponents('TyControls...', [...]) group and
  // requires each registered class to have a generated icon — a new control must land in one of
  // these groups (and get its icon + $classes/CClasses entry), never a standalone unlisted class.
  // Standard: everyday inputs, labels, panels.
  RegisterComponents('TyControls',
    [TTyButton, TTyLabel, TTyLinkLabel, TTyShadowLabel, TTyGlowLabel,
     TTyEdit, TTyNumericEdit, TTyCurrencyEdit, TTyMaskEdit, TTyURLEdit, TTyComboEdit, TTyTrackEdit,
     TTyCalculator, TTyCalcEdit, TTyCalcCurrencyEdit,
     TTyMemo, TTyCheckBox, TTyRadioButton,
     TTyComboBox, TTyMRUComboBox, TTyComboBoxEx, TTyOfficeComboBox, TTyAdvancedComboBox,
     TTyCheckComboBox,
     TTyListBox, TTyCheckListBox, TTyOfficeListBox, TTyAdvancedListBox, TTyValueListEditor,
     TTySpinEdit, TTyUpDown, TTyToggleSwitch, TTyTrackBar, TTyProgressBar, TTyScrollBar,
     TTyPanel, TTyGroupBox, TTyStyleController]);
  // Rich pickers: colour / font / value selectors (Phase 4 B/C/E).
  RegisterComponents('TyControls Pickers',
    [TTyColorBox, TTyColorComboBox, TTyColorListBox, TTyColorGrid, TTyLColorPicker,
     TTyHSColorPicker, TTyFontComboBox, TTyFontListBox, TTyFontSizeComboBox]);
  // Command / specialized buttons.
  RegisterComponents('TyControls Buttons',
    [TTyGlyphButton, TTyGlyphContainerButton, TTySpeedButton,
     TTyDropDownButton, TTyMenuButton, TTyColorButton, TTyButtonGroup]);
  // Instruments & indicators.
  RegisterComponents('TyControls Gauges',
    [TTyGauge, TTyMeter, TTyLevelMeter, TTyDial, TTyGearDial, TTyAnalogClock,
     TTyCircularProgress, TTyActivityIndicator, TTyActivityBar, TTyGearActivityIndicator,
     TTySparkline, TTyRating]);
  // Layout, tabs, bars, complex views.
  RegisterComponents('TyControls Containers',
    [TTyPageControl, TTyTabSheet, TTyTabSet, TTySplitter,
     TTyStatusBar, TTyToolBar, TTyToolSeparator, TTyTitleBar,
     TTyMenuBar, TTyPopupMenu, TTyCalendar, TTyDateTimePicker, TTyTreeView,
     TTyBevel, TTyDivider, TTyPaintPanel, TTySizeBox]);
  // Office-style ribbon parts.
  RegisterComponents('TyControls Ribbon',
    [TTyRibbon, TTyRibbonPage, TTyRibbonGroup, TTyRibbonAppMenu,
     TTyRibbonQuickAccess, TTyRibbonGallery, TTyRibbonBackstage]);
  // Icon-font, images, hints, styler.
  RegisterComponents('TyControls Images',
    [TTyIconFont, TTyCharImage, TTyGlyphImageList, TTyImage,
     TTyImageCollection, TTyVirtualImageList,
     TTyHint, TTyBalloonHint, TTyNativeStyler]);
  // Dialogs palette group. TTyMessage (S1) + the S2 input-family components.
  RegisterComponents('TyControls Dialogs',
    [TTyMessage, TTyInputDialog, TTyPasswordDialog, TTyTextDialog,
     TTySelectValueDialog, TTySelectPathDialog,
     TTyColorDialog, TTyFontDialog,
     TTyFindDialog, TTyReplaceDialog, TTyProgressDialog, TTyAboutDialog]);
  // StyleClass dropdown applies to ALL styleable controls: registering on the two
  // base classes covers every TyControls control through inheritance.
  RegisterPropertyEditor(TypeInfo(string), TTyGraphicControl, 'StyleClass',
    TTyStyleClassPropertyEditor);
  RegisterPropertyEditor(TypeInfo(string), TTyCustomControl, 'StyleClass',
    TTyStyleClassPropertyEditor);
  // About: read-only version display + design-time About dialog, on every registered class
  // (the two control bases cover all visual controls; the rest are non-visual / the form).
  RegisterPropertyEditor(TypeInfo(string), TTyGraphicControl, 'About', TTyAboutEditor);
  RegisterPropertyEditor(TypeInfo(string), TTyCustomControl, 'About', TTyAboutEditor);
  RegisterPropertyEditor(TypeInfo(string), TTyStyleController, 'About', TTyAboutEditor);
  RegisterPropertyEditor(TypeInfo(string), TTyPopupMenu, 'About', TTyAboutEditor);
  RegisterPropertyEditor(TypeInfo(string), TTyForm, 'About', TTyAboutEditor);
  // BorderStyle is locked to bsNone (TTyForm is a borderless custom-chrome window) —
  // hide it from the Object Inspector so it is neither shown nor editable.
  RegisterPropertyEditor(TypeInfo(TFormBorderStyle), TTyForm, 'BorderStyle', THiddenPropertyEditor);
  // Page management verbs (Add/Delete/Show Next/Prev) for the page control.
  RegisterComponentEditor(TTyPageControl, TTyPageControlEditor);
  // Double-click a dialog component in the designer to preview it (verb 0 = Preview),
  // mirroring LCL's TCommonDialogComponentEditor.
  RegisterComponentEditor(
    [TTyMessage, TTyInputDialog, TTyPasswordDialog, TTyTextDialog,
     TTySelectValueDialog, TTySelectPathDialog, TTyColorDialog, TTyFontDialog,
     TTyFindDialog, TTyReplaceDialog, TTyProgressDialog, TTyAboutDialog],
    TTyDialogComponentEditor);
  // File > New > "TyControls Form": a unit whose form descends from TTyForm, pre-fitted
  // with a top-aligned title bar.
  RegisterProjectFileDescriptor(TTyFormFileDescriptor.Create);
  // File > New > "TyControls Dialog": a unit whose form descends from TTyDialog (close-only,
  // non-resizable modal), pre-fitted with a top-aligned title bar.
  RegisterProjectFileDescriptor(TTyDialogFileDescriptor.Create);
  // The themed main form (title bar + style controller). Intentionally NOT registered as a
  // New-item (so it doesn't appear in File > New) — it only makes sense as an application's
  // root window. The instance is kept alive for the whole IDE session because the "TyControls
  // Application" descriptor (CreateStartFiles) points File>New's project template at it.
  // TProjectFileDescriptor descends from TPersistent (not a refcounted interface), so nothing
  // owns this one now; the OS reclaims it at IDE shutdown — a benign one-per-session singleton.
  TyMainFormDescriptor := TTyMainFormFileDescriptor.Create;
  // File > New > Project > "TyControls Application": a GUI app whose main form is that
  // themed TTyForm, with the tycontrols dependency pre-added.
  RegisterProjectDescriptor(TTyApplicationDescriptor.Create);
end;

end.
