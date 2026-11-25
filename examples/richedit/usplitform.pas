unit usplitform;

{ The split cell form: how many columns and rows the cell at the caret is split into. The rich
  edit's TTyRichEditSplitCell asks it through OnChooseSize, which hands over the rows the cell
  covers and the numbers to start from (what a merged cell covers - splitting it back is the
  common wish - else the action's 2 x 1); the form only asks, the action splits.

  The form takes only numbers the cell can be split into, as far as it can know them: columns
  1 to CRichMaxTableCols, rows 1 to CMaxRows, and for a cell over several rows only a number
  that divides them - the line under the boxes says which, and turns to the reason while a
  number is wrong, OK greyed. What only the table knows (a row's cells over the limit with the
  new ones) the control still refuses; the main form shows that in the status bar, as every
  refusal (OnEditRefused). Built from the package's controls (no native dialog). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, tyControls.Controller, tyControls.Form,
  tyControls.FormSurface, tyControls.TyLabel, tyControls.SpinEdit, tyControls.Button,
  tyControls.RichEdit.Model;

const
  // rows a plain cell is split into at most: a sensible bound for a form, far under the table's
  CMaxRows = 100;

type
  TSplitForm = class(TTyForm)
    Surface: TTyFormSurface;
    Bar: TTyTitleBar;
    LblColumns: TTyLabel;
    SpnColumns: TTySpinEdit;
    LblRows: TTyLabel;
    SpnRows: TTySpinEdit;
    LblHint: TTyLabel;
    BtnOk: TTyButton;
    BtnCancel: TTyButton;
    procedure FormCreate(Sender: TObject);
    procedure NumbersChanged(Sender: TObject);
  private
    FCellRows: Integer;
    function Divisors: string;
  public
    { The cell covers ACellRows rows; the boxes start at ACols x ARows. }
    procedure Prepare(ACellRows, ACols, ARows: Integer);
    { The numbers typed, and whether the cell can be split into them. }
    function Numbers(out ACols, ARows: Integer): Boolean;
  end;

{ Asks for the columns and rows to split a cell over ACellRows rows into (ACols, ARows in:
  where the form starts); False: cancelled. }
function AskSplit(ACellRows: Integer; var ACols, ARows: Integer): Boolean;

implementation

{$R *.lfm}

resourcestring
  rsSpCoversRows = 'The cell covers %d rows: the rows must divide them (%s).';
  rsSpBadColumns = 'Give 1 to %d columns.';
  rsSpBadRows    = 'Give 1 to %d rows.';
  rsSpNotDivide  = '%d does not divide the %d rows the cell covers: give %s.';

function AskSplit(ACellRows: Integer; var ACols, ARows: Integer): Boolean;
var
  f: TSplitForm;
begin
  f := TSplitForm.Create(Application);
  try
    f.Prepare(ACellRows, ACols, ARows);
    Result := (f.ShowModal = mrOk) and f.Numbers(ACols, ARows);
  finally
    f.Free;
  end;
end;

procedure TSplitForm.FormCreate(Sender: TObject);
begin
  ApplyChromeTheme(TyDefaultController);
  SpnColumns.MaxValue := CRichMaxTableCols;
  SpnRows.MaxValue := CMaxRows;
end;

procedure TSplitForm.Prepare(ACellRows, ACols, ARows: Integer);
begin
  if ACellRows < 1 then ACellRows := 1;
  FCellRows := ACellRows;
  if FCellRows > 1 then SpnRows.MaxValue := FCellRows;
  SpnColumns.Value := ACols;
  SpnRows.Value := ARows;
  NumbersChanged(nil);
end;

{ The numbers that divide the rows the cell covers: "1, 2, 4". }
function TSplitForm.Divisors: string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to FCellRows do
    if FCellRows mod i = 0 then
    begin
      if Result <> '' then Result := Result + ', ';
      Result := Result + IntToStr(i);
    end;
end;

{ What is typed is read as it is typed (the boxes commit their value only when left). }
function TSplitForm.Numbers(out ACols, ARows: Integer): Boolean;
begin
  if not TryStrToInt(Trim(SpnColumns.Text), ACols) then ACols := 0;
  if not TryStrToInt(Trim(SpnRows.Text), ARows) then ARows := 0;
  Result := (ACols >= 1) and (ACols <= CRichMaxTableCols) and (ARows >= 1) and
    (ARows <= SpnRows.MaxValue) and ((FCellRows = 1) or (FCellRows mod ARows = 0));
end;

{ A box changed: the line under them says what holds, or what is wrong; OK only for numbers the
  cell can be split into. }
procedure TSplitForm.NumbersChanged(Sender: TObject);
var
  c, r: Integer;
  ok: Boolean;
begin
  ok := Numbers(c, r);
  if (c < 1) or (c > CRichMaxTableCols) then
    LblHint.Caption := Format(rsSpBadColumns, [CRichMaxTableCols])
  else if (FCellRows > 1) and (r >= 1) and (FCellRows mod r <> 0) then
    LblHint.Caption := Format(rsSpNotDivide, [r, FCellRows, Divisors])
  else if (r < 1) or (r > SpnRows.MaxValue) then
    LblHint.Caption := Format(rsSpBadRows, [SpnRows.MaxValue])
  else if FCellRows > 1 then
    LblHint.Caption := Format(rsSpCoversRows, [FCellRows, Divisors])
  else
    LblHint.Caption := '';
  BtnOk.Enabled := ok;
end;

end.
