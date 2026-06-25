unit tyControls.Design;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Graphics, LCLIntf,
  PropEdits, ComponentEditors, ProjectIntf, FormEditingIntf, LazIDEIntf,
  LResources, tyControls.Types,
  tyControls.Base, tyControls.Controller, tyControls.StyleModel,
  tyControls.Button, tyControls.TyLabel, tyControls.Edit,
  tyControls.CheckBox, tyControls.Panel, tyControls.ComboBox,
  tyControls.ScrollBar, tyControls.Form,
  tyControls.ListBox, tyControls.ProgressBar, tyControls.ToggleSwitch,
  tyControls.TrackBar, tyControls.GroupBox, tyControls.PageControl, tyControls.TabSheet,
  tyControls.SpinEdit, tyControls.Memo, tyControls.Menu, tyControls.NativeStyler;
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
  rsDtAppName        = 'TyControls Application';
  rsDtAppDescription = 'A graphical TyControls application. The main form is a themed TTyForm ' +
    '(custom title bar + style controller); the tycontrols package is added automatically.';
  rsDtAboutTitle   = 'About TyControls';
  rsDtAboutTagline = 'Themed LCL control library';
  rsDtAboutVersion = 'Version %s';
  rsDtAboutOK      = 'OK';
  rsDtPageAdd      = 'Add Page';
  rsDtPageDelete   = 'Delete Page';
  rsDtPageShowNext = 'Show Next Page';
  rsDtPageShowPrev = 'Show Previous Page';

var
  // The themed main-form descriptor, reused by the TyControls Application project's
  // CreateStartFiles. Held here so registration owns its (refcounted) lifetime.
  TyMainFormDescriptor: TTyMainFormFileDescriptor;

type
  { Small code-built About form (no .lfm), so the design-time package stays resource-free. }
  TTyAboutForm = class(TForm)
    procedure LinkClick(Sender: TObject);
  end;

procedure TTyAboutForm.LinkClick(Sender: TObject);
begin
  OpenURL(TyHomepageUrl);
end;

procedure ShowTyAboutDialog;
var
  F: TTyAboutForm;
  Hdr: TPanel;
  LLink: TLabel;
  Btn: TButton;
  Accent: TColor;
  sc: Double;
  y, maxW, gap, margin, hdrH, btnH, bw: Integer;

  // Measure at the form's REAL device context (after HandleNeeded) so the window is
  // sized to the actually-rendered text — robust on any HiDPI/scaled display.
  function FW(const S: string; ASize: Integer; ABold: Boolean): Integer;
  begin
    F.Canvas.Font.Assign(F.Font);
    F.Canvas.Font.Size := ASize;
    if ABold then F.Canvas.Font.Style := [fsBold];
    Result := F.Canvas.TextWidth(S);
  end;

  function FH(ASize: Integer): Integer;
  begin
    F.Canvas.Font.Assign(F.Font);
    F.Canvas.Font.Size := ASize;
    Result := F.Canvas.TextHeight('Ag');
  end;

  // One centered row; height = line height + padding, then advance y by a full gap.
  function AddRow(const Cap: string; ASize: Integer; AStyle: TFontStyles; AColor: TColor): TLabel;
  var h: Integer;
  begin
    h := FH(ASize) + gap div 3;
    Result := TLabel.Create(F);
    Result.Parent := F;
    Result.AutoSize := False;
    Result.SetBounds(margin, y, F.ClientWidth - 2 * margin, h);
    Result.Alignment := taCenter;
    Result.Layout := tlCenter;
    Result.Caption := Cap;
    Result.Font.Size := ASize;
    Result.Font.Style := AStyle;
    Result.Font.Color := AColor;
    Inc(y, h + gap);
  end;

begin
  Accent := RGBToColor($3B, $82, $F6);   // TyControls default-theme accent
  sc := Screen.PixelsPerInch / 96;
  if sc < 1 then sc := 1;
  F := TTyAboutForm.CreateNew(nil);
  try
    F.Caption := rsDtAboutTitle;
    F.BorderStyle := bsDialog;
    F.Position := poScreenCenter;
    F.HandleNeeded;                       // so F.Canvas measures at the real DPI

    gap := FH(13);                        // generous line spacing ~ one line height
    if gap < Round(20 * sc) then gap := Round(20 * sc);
    margin := gap + gap div 2;

    maxW := FW('TyControls', 22, True);
    if FW(rsDtAboutTagline, 13, False) > maxW then maxW := FW(rsDtAboutTagline, 13, False);
    if FW(Format(rsDtAboutVersion, [TyVersion]), 11, False) > maxW then maxW := FW(Format(rsDtAboutVersion, [TyVersion]), 11, False);
    if FW(TyHomepageUrl, 11, False) > maxW then maxW := FW(TyHomepageUrl, 11, False);
    if maxW < Round(420 * sc) then maxW := Round(420 * sc);   // floor for narrow content
    F.ClientWidth := maxW + 2 * margin;

    hdrH := FH(22) + 2 * gap;
    Hdr := TPanel.Create(F);
    Hdr.Parent := F;
    Hdr.SetBounds(0, 0, F.ClientWidth, hdrH);
    Hdr.BevelOuter := bvNone;
    Hdr.Color := Accent;
    Hdr.Font.Color := clWhite;
    Hdr.Font.Style := [fsBold];
    Hdr.Font.Size := 22;
    Hdr.Caption := 'TyControls';

    y := hdrH + gap;
    AddRow(rsDtAboutTagline, 13, [], clWindowText);
    AddRow(Format(rsDtAboutVersion, [TyVersion]), 11, [], clGrayText);
    LLink := AddRow(TyHomepageUrl, 11, [fsUnderline], clBlue);
    LLink.Cursor := crHandPoint;
    LLink.OnClick := @F.LinkClick;

    Inc(y, gap div 2);
    btnH := FH(11) + gap;
    bw := FW(rsDtAboutOK, 11, False) + 3 * gap;
    Btn := TButton.Create(F);
    Btn.Parent := F;
    Btn.Caption := rsDtAboutOK;
    Btn.ModalResult := mrOk;
    Btn.Default := True;
    Btn.Cancel := True;
    Btn.SetBounds((F.ClientWidth - bw) div 2, y, bw, btnH);
    Inc(y, btnH + gap);
    F.ClientHeight := y;

    F.ShowModal;
  finally
    F.Free;
  end;
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
  // (TitleBar / TitleHeight / ShowMinimize / ShowMaximize). RegisterComponents only
  // covers droppable controls, not base form classes — this is the form-level analog.
  if FormEditingHook <> nil then
    FormEditingHook.RegisterDesignerBaseClass(TTyForm);
  RegisterComponents('TyControls',
    [TTyButton, TTyLabel, TTyEdit, TTyCheckBox, TTyRadioButton,
     TTyPanel, TTyComboBox, TTyScrollBar, TTyStyleController,
     TTyListBox, TTyProgressBar, TTyToggleSwitch, TTyTrackBar, TTyGroupBox,
     TTyPageControl, TTyTabSheet, TTySpinEdit, TTyMemo, TTyTitleBar,
     TTyMenuBar, TTyPopupMenu, TTyNativeStyler]);
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
  // Page management verbs (Add/Delete/Show Next/Prev) for the page control.
  RegisterComponentEditor(TTyPageControl, TTyPageControlEditor);
  // File > New > "TyControls Form": a unit whose form descends from TTyForm, pre-fitted
  // with a top-aligned title bar.
  RegisterProjectFileDescriptor(TTyFormFileDescriptor.Create);
  // The themed main form (title bar + style controller). Registered so its lifetime is
  // refcount-managed; reused by the TyControls Application project below.
  TyMainFormDescriptor := TTyMainFormFileDescriptor.Create;
  RegisterProjectFileDescriptor(TyMainFormDescriptor);
  // File > New > Project > "TyControls Application": a GUI app whose main form is that
  // themed TTyForm, with the tycontrols dependency pre-added.
  RegisterProjectDescriptor(TTyApplicationDescriptor.Create);
end;

end.
