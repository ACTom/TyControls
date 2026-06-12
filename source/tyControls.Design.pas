unit tyControls.Design;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, PropEdits,
  tyControls.Controller, tyControls.StyleModel,
  tyControls.Button, tyControls.TyLabel, tyControls.Edit,
  tyControls.CheckBox, tyControls.Panel, tyControls.ComboBox,
  tyControls.ScrollBar, tyControls.Form;
type
  TTyStyleClassPropertyEditor = class(TStringPropertyEditor)
  public
    function GetAttributes: TPropertyAttributes; override;
    procedure GetValues(Proc: TGetStrProc); override;
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

procedure Register;
begin
  RegisterComponents('TyControls',
    [TTyButton, TTyLabel, TTyEdit, TTyCheckBox, TTyRadioButton,
     TTyPanel, TTyComboBox, TTyScrollBar, TTyTitleBar,
     TTyFormChrome, TTyStyleController]);
  RegisterPropertyEditor(TypeInfo(string), TTyButton, 'StyleClass',
    TTyStyleClassPropertyEditor);
end;

end.
