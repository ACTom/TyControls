unit tyControls.Design.NewItems;
{$mode objfpc}{$H+}
{ The IDE's File > New integration: the TyControls Form / Main Form / Dialog unit
  templates and the TyControls Application project descriptor, plus the one procedure
  that registers them (RegisterNewItems, called from tyControls.Design.Register).

  Split out of tyControls.Design when that unit passed nineteen hundred lines. }
interface
uses
  Classes, SysUtils, Controls, Forms,
  ProjectIntf, LazIDEIntf,
  tyControls.Form, tyControls.Dialogs;

type
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

{ Registers the File > New unit templates and the project descriptor; called once from
  tyControls.Design.Register. }
procedure RegisterNewItems;

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

var
  // The themed main-form descriptor, reused by the TyControls Application project's
  // CreateStartFiles. Held here so registration owns its (refcounted) lifetime.
  TyMainFormDescriptor: TTyMainFormFileDescriptor;

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

{ ---- registration ---- }

procedure RegisterNewItems;
begin
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
