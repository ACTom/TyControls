unit tyControls.Design;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Forms, Controls, Dialogs, Menus, StdCtrls, ExtCtrls, Graphics, LCLIntf, LCLType,
  PropEdits, ComponentEditors, ProjectIntf, FormEditingIntf, LazIDEIntf,
  LResources, tyControls.Types, tyControls.Component,
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
  tyControls.Dialogs.FileDialog, tyControls.PreviewBox, tyControls.ImageView,
  tyControls.Chart, tyControls.HtmlLabel,
  tyControls.Bevel, tyControls.Divider, tyControls.PaintPanel, tyControls.SizeBox,
  tyControls.RadioGroup, tyControls.CheckGroup, tyControls.ToolGroupPanel,
  tyControls.ScrollBox, tyControls.ScrollPanel, tyControls.ExPanel,
  tyControls.GridPanel, tyControls.GridCell, tyControls.RelativePanel,
  tyControls.ToolBarEx, tyControls.ControlBar, tyControls.CoolBar,
  tyControls.HeaderControl, tyControls.ListGroupPanel,
  tyControls.Shape, tyControls.StarShape, tyControls.Arrow,
  tyControls.Card, tyControls.Tag, tyControls.Badge, tyControls.Grid,
  tyControls.Alert, tyControls.Notification, tyControls.Empty, tyControls.Segmented,
  tyControls.Pagination, tyControls.Steps, tyControls.Breadcrumb,
  tyControls.Transfer, tyControls.TreeSelect, tyControls.Cascader, tyControls.Popover,
  tyControls.ListView, tyControls.ShellListView, tyControls.ShellTreeView,
  tyControls.FilterComboBox, tyControls.ShellComboBox;
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

  { Editor for the read-only `Version` property: shows TyVersion in the Object Inspector and
    opens the About dialog (version + clickable homepage link) when the '...' button is clicked. }
  TTyVersionEditor = class(TStringPropertyEditor)
  public
    function GetAttributes: TPropertyAttributes; override;
    procedure Edit; override;
  end;

  { Read-only `Purpose` property on TTyFormSurface: the OI shows a one-line summary and the '...'
    button explains WHY the surface exists and why it must not be deleted or re-laid-out. Together
    with `Version` it is the only property left visible on the surface (see Register). }
  TTySurfacePurposeEditor = class(TStringPropertyEditor)
  public
    function GetAttributes: TPropertyAttributes; override;
    procedure Edit; override;
  end;

  { File > New entry that creates a unit whose form descends from TTyForm —a borderless
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

  { File > New entry that creates a unit whose form descends from TTyDialog —a themed, close-only,
    non-resizable modal dialog base, with BorderIcons = [biSystemMenu] (close button only), ready for
    the user to design content + buttons on and show modally.
    The generated .lfm is BARE —no title bar, no content surface. TTyDialog builds its own title bar
    and bottom button bar in CreateNew (emitting one here gave the dialog TWO stacked title bars), and
    being non-resizable it has no WS_THICKFRAME edge band for a surface to cover. }
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
    'form and the title bar already associated to it —the root window for a TyControls application.';
  rsDtDialogName        = 'TyControls Dialog';
  rsDtDialogDescription = 'A themed custom-drawn modal dialog (TTyDialog): borderless, ' +
    'close-only, non-resizable, centered —design your own dialog content and buttons.';
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
  rsDtSurfacePurposeTitle = 'Why this control exists';
  rsDtSurfacePurposeText =
    'TyFormSurface is the content host of a TTyForm —the panel every control on the form lives on.' +
    LineEnding + LineEnding +
    'A borderless, resizable window cannot paint its own outermost pixels: the compositor gives it a ' +
    'backing surface smaller than the window, which leaves an unpainted band along the right and ' +
    'bottom edges. A CHILD window has no such limit and paints edge to edge, so TTyForm renders its ' +
    'themed background onto this surface instead of onto itself.' + LineEnding + LineEnding +
    'Your controls must live on the surface. Graphic (windowless) controls such as TTyLabel paint ' +
    'onto their parent, so one placed directly on the form is hidden behind the surface.' +
    LineEnding + LineEnding +
    'Keep exactly one surface per form, leave it filling the form, and do not delete it.';

var
  // The themed main-form descriptor, reused by the TyControls Application project's
  // CreateStartFiles. Held here so registration owns its (refcounted) lifetime.
  TyMainFormDescriptor: TTyMainFormFileDescriptor;

{ The design-time 'Version' property (OI '...' button) now opens the library's OWN themed
  TTyAboutDialog —so what you see at design time is exactly the dialog consumers ship, custom
  title bar and all —instead of the old code-built native TForm. Empty fields (here: copyright)
  are omitted by the dialog. }
procedure ShowTyAboutDialog;
begin
  TyShowAbout(rsDtAboutTitle, 'TyControls', Format(rsDtAboutVersion, [TyVersion]),
    rsDtAboutTagline, '', rsDtAboutLicense, TyHomepageUrl);
end;

function TTyVersionEditor.GetAttributes: TPropertyAttributes;
begin
  Result := [paReadOnly, paDialog];   // greyed value + '...' button that opens the dialog
end;

procedure TTyVersionEditor.Edit;
begin
  ShowTyAboutDialog;
end;

function TTySurfacePurposeEditor.GetAttributes: TPropertyAttributes;
begin
  Result := [paReadOnly, paDialog];   // greyed value + '...' button that opens the explanation
end;

procedure TTySurfacePurposeEditor.Edit;
begin
  MessageDlg(rsDtSurfacePurposeTitle, rsDtSurfacePurposeText, mtInformation, [mbOK], 0);
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
  // TTyFormSurface needs no extra unit: tyControls.Form re-exports it (see that unit) precisely so
  // every designed form can carry this field with only `uses tyControls.Form`.
  fields := '    Surface: TTyFormSurface;' + LE
          + '    TyTitleBar1: TTyTitleBar;' + LE;
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
  { The content host wraps ALL of the form's controls (title bar included): a borderless resizable
    window cannot paint its outermost pixels, and graphic controls only render when hosted on it.
    See TTyFormSurface.Purpose. }
  s := s
    + '  TitleBar = TyTitleBar1' + LE
    + '  object Surface: TTyFormSurface' + LE
    + '    Left = 0' + LE
    + '    Height = 320' + LE
    + '    Top = 0' + LE
    + '    Width = 480' + LE
    + '    Align = alClient' + LE
    + '    object TyTitleBar1: TTyTitleBar' + LE
    + '      Left = 0' + LE
    + '      Height = 32' + LE
    + '      Top = 0' + LE
    + '      Width = 480' + LE
    + '      Align = alTop' + LE
    + '      Caption = ''' + ResourceName + '''' + LE;
  if FWithController then
    s := s + '      Controller = TyStyleController1' + LE;
  s := s
    + '    end' + LE
    + '  end' + LE;
  // The style controller is non-visual —it stays on the FORM, not inside the surface.
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
  { Full override (the base hard-codes TTyForm). No published fields: TTyDialog brings its own title
    bar and button bar from CreateNew, and there is no surface (see GetResourceSource). }
  Result :=
     'type' + LE
    + '  T' + ResourceName + ' = class(TTyDialog)' + LE
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
  { Full override (the base hard-codes TTyForm). Unlike the FORM template this emits NO title bar and
    NO content surface, because TTyDialog is not TTyForm:
      - TTyDialog.CreateNew already BUILDS and associates its own title bar (and a bottom button bar).
        Emitting one here produced a second, stacked title bar and hijacked the `TitleBar =` binding.
      - A dialog is Resizable=False, so it has no WS_THICKFRAME and none of the unpaintable edge band
        the surface exists to cover —controls sit directly on the dialog, as they always have. }
  Result :=
     'object ' + ResourceName + ': T' + ResourceName + LE
    + '  Left = 300' + LE
    + '  Height = 320' + LE
    + '  Top = 200' + LE
    + '  Width = 480' + LE
    + '  BorderIcons = [biSystemMenu]' + LE
    + '  Caption = ''' + ResourceName + '''' + LE
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
  // covers droppable controls, not base form classes —this is the form-level analog.
  if FormEditingHook <> nil then
  begin
    FormEditingHook.RegisterDesignerBaseClass(TTyForm);
    // TTyDialog is a distinct designer base class (close-only modal dialog): register it so
    // `class(TTyDialog)` resolves as an ancestor and the OI shows its chrome, same as TTyForm.
    FormEditingHook.RegisterDesignerBaseClass(TTyDialog);
  end;
  // The palette is split into functional groups so no single tab is overcrowded. NOTE: the
  // gen-icons.ps1 drift-guard parses EVERY RegisterComponents('TyControls...', [...]) group and
  // requires each registered class to have a generated icon —a new control must land in one of
  // these groups (and get its icon + $classes/CClasses entry), never a standalone unlisted class.
  // === Palette groups, organised by control TYPE (same class set as before) ===
  // Core (non-visual).
  RegisterComponents('TyControls',
    [TTyStyleController, TTyNativeStyler]);
  // Buttons.
  RegisterComponents('TyControls Buttons',
    [TTyButton, TTyGlyphButton, TTyGlyphContainerButton, TTySpeedButton,
     TTyDropDownButton, TTyMenuButton, TTyColorButton, TTyButtonGroup]);
  // Labels.
  RegisterComponents('TyControls Labels',
    [TTyLabel, TTyHtmlLabel, TTyLinkLabel, TTyShadowLabel, TTyGlowLabel,
     TTyTag, TTyBadge]);
  // Text edits: single/multi-line, formatted, calculator, spin.
  RegisterComponents('TyControls Edits',
    [TTyEdit, TTyNumericEdit, TTyCurrencyEdit, TTyMaskEdit, TTyURLEdit, TTyComboEdit,
     TTyTrackEdit, TTyCalcEdit, TTyCalcCurrencyEdit, TTyCalculator,
     TTyMemo, TTySpinEdit, TTyUpDown]);
  // Checks / radios / switches + their groups.
  RegisterComponents('TyControls Choices',
    [TTyCheckBox, TTyRadioButton, TTyToggleSwitch, TTyRadioGroup, TTyCheckGroup, TTySegmented]);
  // Combo boxes & list boxes.
  RegisterComponents('TyControls Lists',
    [TTyComboBox, TTyMRUComboBox, TTyComboBoxEx, TTyOfficeComboBox, TTyAdvancedComboBox,
     TTyCheckComboBox,
     TTyListBox, TTyCheckListBox, TTyOfficeListBox, TTyAdvancedListBox, TTyValueListEditor,
     TTyTransfer, TTyTreeSelect, TTyCascader]);
  // Rich pickers: colour / font / filter / shell selectors.
  RegisterComponents('TyControls Pickers',
    [TTyColorBox, TTyColorComboBox, TTyColorListBox, TTyColorGrid, TTyLColorPicker,
     TTyHSColorPicker, TTyFontComboBox, TTyFontListBox, TTyFontSizeComboBox,
     TTyFilterComboBox, TTyShellComboBox]);
  // Instruments & indicators.
  RegisterComponents('TyControls Gauges',
    [TTyGauge, TTyMeter, TTyLevelMeter, TTyDial, TTyGearDial, TTyAnalogClock,
     TTyCircularProgress, TTyActivityIndicator, TTyActivityBar, TTyGearActivityIndicator,
     TTySparkline, TTyRating]);
  // Bars: sliders / progress / scroll / status / tool bars + header.
  RegisterComponents('TyControls Bars',
    [TTyTrackBar, TTyProgressBar, TTyScrollBar, TTyStatusBar,
     TTyToolBar, TTyToolSeparator, TTyToolBarEx, TTyControlBar, TTyCoolBar,
     TTyAlert, TTyPagination, TTySteps, TTyBreadcrumb, TTyHeaderControl]);
  // Containers & layout.
  RegisterComponents('TyControls Containers',
    [TTyPanel, TTyGroupBox, TTyBevel, TTyDivider, TTySplitter, TTyPaintPanel, TTySizeBox,
     TTyScrollBox, TTyScrollPanel, TTyExPanel, TTyGridPanel, TTyRelativePanel,
     TTyToolGroupPanel, TTyListGroupPanel,
     TTyPageControl, TTyTabSheet, TTyTabSet, TTyTitleBar,
     TTyCard, TTyEmpty]);
  // Cells are created/owned by the grid, not dragged from the palette —register the
  // class (for streaming + OI selection) without a palette button.
  RegisterNoIcon([TTyGridCell]);
  // Data views + shell/file views + date/time.
  RegisterComponents('TyControls Data Views',
    [TTyTreeView, TTyListView, TTyShellListView, TTyShellTreeView, TTyPreviewBox, TTyImageView,
     TTyCalendar, TTyDateTimePicker,
     TTyDrawGrid, TTyStringGrid]);
  // Menus.
  RegisterComponents('TyControls Menus',
    [TTyMenuBar, TTyPopupMenu, TTyImagesMenu, TTyMenuEx]);
  // Office-style ribbon parts.
  RegisterComponents('TyControls Ribbon',
    [TTyRibbon, TTyRibbonPage, TTyRibbonGroup, TTyRibbonAppMenu,
     TTyRibbonQuickAccess, TTyRibbonGallery, TTyRibbonBackstage]);
  // Icon-font, images, hints.
  RegisterComponents('TyControls Images',
    [TTyIconFont, TTyCharImage, TTyGlyphImageList, TTyImage,
     TTyImageCollection, TTyVirtualImageList, TTyHint, TTyBalloonHint, TTyPopover]);
  // Decorative vector shapes + charts.
  RegisterComponents('TyControls Shapes & Charts',
    [TTyShape, TTyStarShape, TTyArrow, TTyChart]);
  // Dialogs: message / input family / pickers / find-replace / progress / about / file.
  RegisterComponents('TyControls Dialogs',
    [TTyMessage, TTyInputDialog, TTyPasswordDialog, TTyTextDialog,
     TTySelectValueDialog, TTySelectPathDialog,
     TTyColorDialog, TTyFontDialog,
     TTyFindDialog, TTyReplaceDialog, TTyProgressDialog, TTyAboutDialog,
     TTyOpenDialog, TTySaveDialog, TTyOpenPictureDialog, TTySavePictureDialog,
     TTyOpenPreviewDialog, TTySavePreviewDialog, TTyNotification]);
  { The content host MUST be a registered component class, or deleting it is unrecoverable. The
    designer records a delete by SERIALIZING the component to LFM text (TDesigner.AddUndoAction ->
    CopySelectionToStream) and undoes it by PASTING that text back —so undo runs through the same
    registry paste does. RegisterNoIcon, not RegisterComponents: registered (so undo works) but with
    no palette icon, since the surface only ever comes from the form template.
    Pasting a stray surface is NOT blocked: the designer's paste reaches its parent without routing
    through the SetParent a guard could hook, so the guards we tried only ever caught the form itself
    while every other container let one through —half a fence, so they were removed. Harmless in
    practice: the surface is not on the palette, so a stray one only appears if you deliberately copy
    it, and a form ignores any surface that is not its own. }
  RegisterNoIcon([TTyFormSurface]);
  // StyleClass dropdown applies to ALL styleable controls: registering on the two
  // base classes covers every TyControls control through inheritance.
  RegisterPropertyEditor(TypeInfo(string), TTyGraphicControl, 'StyleClass',
    TTyStyleClassPropertyEditor);
  RegisterPropertyEditor(TypeInfo(string), TTyCustomControl, 'StyleClass',
    TTyStyleClassPropertyEditor);
  // Version: read-only version display + design-time About dialog, on every registered class.
  // FIVE base classes cover the whole library through inheritance: the two control bases take
  // every visual control, TTyComponent every non-visual one (TTyStyleController included —
  // it descends from TTyComponent), and the last two are the odd ancestries that cannot
  // (TTyPopupMenu descends from TPopupMenu, TTyForm from TForm), so they need their own line.
  // tests/test.version.pas READS THESE LINES: it parses this file for the registrations and
  // asserts every registered component descends from one of them, so a component that gains
  // the property off this tree —and would therefore show a dead entry in the OI —is caught.
  RegisterPropertyEditor(TypeInfo(string), TTyGraphicControl, 'Version', TTyVersionEditor);
  RegisterPropertyEditor(TypeInfo(string), TTyCustomControl, 'Version', TTyVersionEditor);
  RegisterPropertyEditor(TypeInfo(string), TTyComponent, 'Version', TTyVersionEditor);
  RegisterPropertyEditor(TypeInfo(string), TTyPopupMenu, 'Version', TTyVersionEditor);
  RegisterPropertyEditor(TypeInfo(string), TTyForm, 'Version', TTyVersionEditor);
  // BorderStyle is locked to bsNone (TTyForm is a borderless custom-chrome window) —
  // hide it from the Object Inspector so it is neither shown nor editable.
  RegisterPropertyEditor(TypeInfo(TFormBorderStyle), TTyForm, 'BorderStyle', THiddenPropertyEditor);
  { TTyFormSurface is a FIXED alClient content host, not something to configure —editing its Align,
    bounds, Visible, Font, Controller—would only break it (the Controller belongs on the FORM, which
    themes the whole window). So hide EVERY inherited property and leave just the two informational
    ones. Mechanics: an empty PropertyName matches any property of that type on the class, and for
    tkClass the match follows inheritance —so TypeInfo(TPersistent) alone covers Font / Constraints /
    BorderSpacing / PopupMenu / Action / Controller / AnchorSide*. The two by-NAME registrations below
    win over these blanket ones (a named match always beats an unnamed one, whatever the order). }
  RegisterPropertyEditor(TypeInfo(string), TTyFormSurface, '', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TTranslateString), TTyFormSurface, '', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(Boolean), TTyFormSurface, '', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(Integer), TTyFormSurface, '', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TPersistent), TTyFormSurface, '', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TAlign), TTyFormSurface, '', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TAnchors), TTyFormSurface, '', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TCursor), TTyFormSurface, '', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TTabOrder), TTyFormSurface, '', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(THelpType), TTyFormSurface, '', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(THelpContext), TTyFormSurface, '', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TNotifyEvent), TTyFormSurface, '', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TMouseEvent), TTyFormSurface, '', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TMouseMoveEvent), TTyFormSurface, '', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TMouseWheelEvent), TTyFormSurface, '', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TMouseWheelUpDownEvent), TTyFormSurface, '', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TContextPopupEvent), TTyFormSurface, '', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TKeyEvent), TTyFormSurface, '', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TKeyPressEvent), TTyFormSurface, '', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TUTF8KeyPressEvent), TTyFormSurface, '', THiddenPropertyEditor);
  { The blanket rules above lose to any BY-NAME registration the IDE (or we) already made for the
    same property —a named match always beats an unnamed one. So hide those explicitly BY NAME too;
    with PersistentClass = TTyFormSurface they beat the IDE's TControl/TComponent-level editors (a
    more specific class always wins), whatever the registration order. }
  RegisterPropertyEditor(TypeInfo(TBasicAction), TTyFormSurface, 'Action', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TAnchors), TTyFormSurface, 'Anchors', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TSizeConstraints), TTyFormSurface, 'Constraints', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TTyStyleController), TTyFormSurface, 'Controller', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TFont), TTyFormSurface, 'Font', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TTranslateString), TTyFormSurface, 'Hint', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TComponentName), TTyFormSurface, 'Name', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TPopupMenu), TTyFormSurface, 'PopupMenu', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(string), TTyFormSurface, 'StyleClass', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(string), TTyFormSurface, 'StyleOverride', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TTabOrder), TTyFormSurface, 'TabOrder', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(PtrInt), TTyFormSurface, 'Tag', THiddenPropertyEditor);
  // ———nd re-expose ONLY these two (named beats the blanket hides above; same class + named beats
  // the named hides too only because these are registered for the SAME class with the SAME
  // specificity —so they must be the LAST word: Version/Purpose are never in the hide list).
  RegisterPropertyEditor(TypeInfo(string), TTyFormSurface, 'Version', TTyVersionEditor);
  RegisterPropertyEditor(TypeInfo(string), TTyFormSurface, 'Purpose', TTySurfacePurposeEditor);
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
  // New-item (so it doesn't appear in File > New) —it only makes sense as an application's
  // root window. The instance is kept alive for the whole IDE session because the "TyControls
  // Application" descriptor (CreateStartFiles) points File>New's project template at it.
  // TProjectFileDescriptor descends from TPersistent (not a refcounted interface), so nothing
  // owns this one now; the OS reclaims it at IDE shutdown —a benign one-per-session singleton.
  TyMainFormDescriptor := TTyMainFormFileDescriptor.Create;
  // File > New > Project > "TyControls Application": a GUI app whose main form is that
  // themed TTyForm, with the tycontrols dependency pre-added.
  RegisterProjectDescriptor(TTyApplicationDescriptor.Create);
end;

end.
