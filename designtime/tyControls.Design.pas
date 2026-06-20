unit tyControls.Design;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Graphics, LCLIntf,
  PropEdits, ComponentEditors, ProjectIntf, FormEditingIntf,
  LResources, tyControls.Types,
  tyControls.Base, tyControls.Controller, tyControls.StyleModel,
  tyControls.Button, tyControls.TyLabel, tyControls.Edit,
  tyControls.CheckBox, tyControls.Panel, tyControls.ComboBox,
  tyControls.ScrollBar, tyControls.Form,
  tyControls.ListBox, tyControls.ProgressBar, tyControls.ToggleSwitch,
  tyControls.TrackBar, tyControls.GroupBox, tyControls.PageControl, tyControls.TabSheet,
  tyControls.SpinEdit, tyControls.Memo, tyControls.Menu;
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

  // A full-width, horizontally-centered text row (taCenter avoids any text measurement,
  // so it lays out correctly before the form has a handle).
  function AddRow(const ACaption: string; ATop, ASize: Integer;
    AStyle: TFontStyles; AColor: TColor): TLabel;
  begin
    Result := TLabel.Create(F);
    Result.Parent := F;
    Result.AutoSize := False;
    Result.Left := 20;
    Result.Width := F.ClientWidth - 40;
    Result.Height := ASize + 16;
    Result.Alignment := taCenter;
    Result.Layout := tlCenter;
    Result.Caption := ACaption;
    Result.Font.Size := ASize;
    Result.Font.Style := AStyle;
    Result.Font.Color := AColor;
    Result.Top := ATop;
  end;

begin
  Accent := RGBToColor($3B, $82, $F6);   // TyControls default-theme accent
  F := TTyAboutForm.CreateNew(nil);
  try
    F.Caption := 'About TyControls';
    F.BorderStyle := bsDialog;
    F.Position := poScreenCenter;
    F.ClientWidth := 460;
    F.ClientHeight := 234;

    // Branded header band: accent fill, white product name centered.
    Hdr := TPanel.Create(F);
    Hdr.Parent := F;
    Hdr.SetBounds(0, 0, F.ClientWidth, 72);
    Hdr.BevelOuter := bvNone;
    Hdr.Color := Accent;
    Hdr.Font.Color := clWhite;
    Hdr.Font.Style := [fsBold];
    Hdr.Font.Size := 18;
    Hdr.Caption := 'TyControls';

    AddRow('主题化 LCL 控件库', 90, 11, [], clWindowText);
    AddRow('版本 / Version  ' + TyVersion, 118, 10, [], clGrayText);

    LLink := AddRow(TyHomepageUrl, 150, 10, [fsUnderline], clBlue);
    LLink.Cursor := crHandPoint;
    LLink.OnClick := @F.LinkClick;

    Btn := TButton.Create(F);
    Btn.Parent := F;
    Btn.Caption := 'OK';
    Btn.ModalResult := mrOk;
    Btn.Default := True;
    Btn.Cancel := True;
    Btn.SetBounds((F.ClientWidth - 92) div 2, 186, 92, 30);

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
    0: Result := 'Add Page';
    1: Result := 'Delete Page';
    2: Result := 'Show Next Page';
    3: Result := 'Show Previous Page';
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
     TTyMenuBar, TTyPopupMenu]);
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
  // File > New > "TyControls Form": a unit whose form descends from TTyForm.
  RegisterProjectFileDescriptor(TTyFormFileDescriptor.Create);
end;

end.
