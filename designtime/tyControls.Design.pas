unit tyControls.Design;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, PropEdits, ComponentEditors, ProjectIntf, FormEditingIntf,
  tyControls.Base, tyControls.Controller, tyControls.StyleModel,
  tyControls.Button, tyControls.TyLabel, tyControls.Edit,
  tyControls.CheckBox, tyControls.Panel, tyControls.ComboBox,
  tyControls.ScrollBar, tyControls.Form,
  tyControls.ListBox, tyControls.ProgressBar, tyControls.ToggleSwitch,
  tyControls.TrackBar, tyControls.GroupBox, tyControls.TabControl,
  tyControls.SpinEdit, tyControls.Memo, tyControls.Menu;
type
  TTyStyleClassPropertyEditor = class(TStringPropertyEditor)
  public
    function GetAttributes: TPropertyAttributes; override;
    procedure GetValues(Proc: TGetStrProc); override;
  end;

  { Adds an "Edit Tabs..." verb to the TTyTabControl context menu / Object
    Inspector, opening the standard collection editor on the Tabs collection. }
  TTyTabControlEditor = class(TDefaultComponentEditor)
  public
    function GetVerbCount: Integer; override;
    function GetVerb(Index: Integer): string; override;
    procedure ExecuteVerb(Index: Integer); override;
  end;

  { File > New entry that creates a unit whose form descends from TTyForm — a
    borderless form with a persistent chrome engine. The form is empty by default;
    drop a TTyTitleBar onto it and it auto-associates to the TitleBar property. }
  TTyFormFileDescriptor = class(TFileDescPascalUnitWithResource)
  public
    constructor Create; override;
    function GetInterfaceUsesSection: string; override;
    function GetLocalizedName: string; override;
    function GetLocalizedDescription: string; override;
  end;

procedure Register;

implementation

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

function TTyTabControlEditor.GetVerbCount: Integer;
begin
  Result := 1;
end;

function TTyTabControlEditor.GetVerb(Index: Integer): string;
begin
  if Index = 0 then
    Result := 'Edit Tabs...'
  else
    Result := '';
end;

procedure TTyTabControlEditor.ExecuteVerb(Index: Integer);
begin
  if Index = 0 then
    EditCollection(Component, TTyTabControl(Component).Tabs, 'Tabs');
end;

{ TTyFormFileDescriptor }

constructor TTyFormFileDescriptor.Create;
begin
  inherited Create;
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
end;

function TTyFormFileDescriptor.GetLocalizedName: string;
begin
  Result := 'TyControls Form';
end;

function TTyFormFileDescriptor.GetLocalizedDescription: string;
begin
  Result := 'A borderless form descending from TTyForm. Drop a TTyTitleBar onto ' +
    'it to get a draggable custom title bar; lay out your controls below it.';
end;

procedure Register;
begin
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
     TTyTabControl, TTySpinEdit, TTyMemo, TTyTitleBar,
     TTyMenuBar, TTyPopupMenu]);
  // StyleClass dropdown applies to ALL styleable controls: registering on the two
  // base classes covers every TyControls control through inheritance.
  RegisterPropertyEditor(TypeInfo(string), TTyGraphicControl, 'StyleClass',
    TTyStyleClassPropertyEditor);
  RegisterPropertyEditor(TypeInfo(string), TTyCustomControl, 'StyleClass',
    TTyStyleClassPropertyEditor);
  // The IDE shows the standard collection dialog for any published TCollection
  // property by default; register explicitly for discoverability, and add an
  // "Edit Tabs..." component verb so the editor is reachable from the context menu.
  RegisterPropertyEditor(TypeInfo(TTyTabCollection), TTyTabControl, 'Tabs',
    TCollectionPropertyEditor);
  RegisterComponentEditor(TTyTabControl, TTyTabControlEditor);
  // File > New > "TyControls Form": a unit whose form descends from TTyForm.
  RegisterProjectFileDescriptor(TTyFormFileDescriptor.Create);
end;

end.
