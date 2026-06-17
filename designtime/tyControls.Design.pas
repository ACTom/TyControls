unit tyControls.Design;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, PropEdits, ComponentEditors, ProjectIntf,
  tyControls.Base, tyControls.Controller, tyControls.StyleModel,
  tyControls.Button, tyControls.TyLabel, tyControls.Edit,
  tyControls.CheckBox, tyControls.Panel, tyControls.ComboBox,
  tyControls.ScrollBar, tyControls.Form,
  tyControls.ListBox, tyControls.ProgressBar, tyControls.ToggleSwitch,
  tyControls.TrackBar, tyControls.GroupBox, tyControls.TabControl,
  tyControls.SpinEdit, tyControls.Memo;
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

  { File > New entry that creates a unit whose form descends from TTyForm, so the
    developer gets the custom window chrome (title bar + content panel) by design,
    with WYSIWYG layout in the form designer. The chrome sub-components are
    code-created by TTyForm, so the generated .lfm stays minimal. }
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
begin
  Proc('primary');
  Proc('danger');
  Proc('close');
  Proc('min');
  Proc('max');
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
  Result := 'A form descending from TTyForm — custom window chrome ' +
    '(title bar + content panel), with WYSIWYG content layout in the designer.';
end;

procedure Register;
begin
  RegisterComponents('TyControls',
    [TTyButton, TTyLabel, TTyEdit, TTyCheckBox, TTyRadioButton,
     TTyPanel, TTyComboBox, TTyScrollBar, TTyStyleController,
     TTyListBox, TTyProgressBar, TTyToggleSwitch, TTyTrackBar, TTyGroupBox,
     TTyTabControl, TTySpinEdit, TTyMemo]);
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
