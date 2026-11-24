unit usplitform;

{ The split cell form: how many columns and rows the cell at the caret is split into. The rich
  edit's TTyRichEditSplitCell asks it through OnChooseSize; the form only asks, the action
  splits. It starts from the numbers it is given: 2 x 1 for a plain cell, the columns and rows
  a merged cell covers (splitting a merged cell back is the common wish). Built from the
  package's controls (no native dialog). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, tyControls.Controller, tyControls.Form,
  tyControls.FormSurface, tyControls.TyLabel, tyControls.SpinEdit, tyControls.Button;

type
  TSplitForm = class(TTyForm)
    Surface: TTyFormSurface;
    Bar: TTyTitleBar;
    LblColumns: TTyLabel;
    SpnColumns: TTySpinEdit;
    LblRows: TTyLabel;
    SpnRows: TTySpinEdit;
    BtnOk: TTyButton;
    BtnCancel: TTyButton;
    procedure FormCreate(Sender: TObject);
  end;

{ Asks for the columns and rows to split into (ACols, ARows in: where the form starts);
  False: cancelled. }
function AskSplit(var ACols, ARows: Integer): Boolean;

implementation

{$R *.lfm}

function AskSplit(var ACols, ARows: Integer): Boolean;
var
  f: TSplitForm;
begin
  f := TSplitForm.Create(Application);
  try
    f.SpnColumns.Value := ACols;
    f.SpnRows.Value := ARows;
    Result := f.ShowModal = mrOk;
    if Result then
    begin
      ACols := f.SpnColumns.Value;
      ARows := f.SpnRows.Value;
    end;
  finally
    f.Free;
  end;
end;

procedure TSplitForm.FormCreate(Sender: TObject);
begin
  ApplyChromeTheme(TyDefaultController);
end;

end.
