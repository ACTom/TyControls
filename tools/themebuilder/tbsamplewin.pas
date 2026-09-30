unit tbsamplewin;
{ A real window in the preview's theme: the title bar, its buttons, the frame and the shadow
  only show on a top-level window, so the preview opens one. It is put on the preview's
  controller (UseController) and repaints its chrome when that controller changes. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.FormSurface, tyControls.TyLabel,
  tyControls.Edit, tyControls.CheckBox, tyControls.Button;

type
  TTbSampleForm = class(TTyForm)
    Surface: TTyFormSurface;
    Bar: TTyTitleBar;
    LblText: TTyLabel;
    EdtName: TTyEdit;
    ChkRemember: TTyCheckBox;
    BtnOk: TTyButton;
    BtnCancel: TTyButton;
    procedure BtnCloseClick(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    FListening: TTyStyleController;
    procedure ControllerChanged(Sender: TObject);
  public
    procedure UseController(AController: TTyStyleController);
  end;

implementation

{$R *.lfm}

uses
  tbpreview;

procedure TTbSampleForm.UseController(AController: TTyStyleController);
begin
  if FListening <> nil then
    FListening.RemoveChangeListener(@ControllerChanged);
  FListening := nil;
  Controller := AController;
  TbApplyController(Surface, AController);
  ApplyChromeTheme(AController);
  if AController <> nil then
  begin
    AController.AddChangeListener(@ControllerChanged);
    FListening := AController;
  end;
end;

procedure TTbSampleForm.ControllerChanged(Sender: TObject);
begin
  ApplyChromeTheme(Controller);
end;

procedure TTbSampleForm.BtnCloseClick(Sender: TObject);
begin
  Close;
end;

procedure TTbSampleForm.FormDestroy(Sender: TObject);
begin
  if FListening <> nil then
    FListening.RemoveChangeListener(@ControllerChanged);
  FListening := nil;
end;

end.
