unit tyControls.DB.Common;
{$mode objfpc}{$H+}
{ What every data-aware control in tycontrols_db shares.

  The data link itself is LCL's: TFieldDataLink, TDBLookup and ChangeDataSource sit in the
  interface of DBCtrls and are the same in Lazarus 3.0 and 4.4, so the controls use them as
  they are. What LCL keeps to itself is here, and so are the few steps every control takes the
  same way (the controls derive from different base controls, so they cannot share a class). }
interface

uses
  DB, DBCtrls;

{ May the user change AField through a control? Not when it is nil, computed (a calculated
  field, or one flagged Calculated), an auto-increment counter or a lookup field. The same
  answer as LCL's FieldIsEditable, which DBCtrls keeps in its implementation section -- except
  that a calculated field is recognised by its FieldKind: FCL never sets the Calculated flag
  itself, so LCL's test lets every fkCalculated field through. }
function TyFieldIsEditable(AField: TField): Boolean;
{ May AKey be typed into AField: editable, and a character the field takes (a letter is not a
  digit of an integer field). LCL's FieldCanAcceptKey. }
function TyFieldCanAcceptKey(AField: TField; AKey: Char): Boolean;

type
  TTyDBLoadedKind = (lvNone, lvText, lvNumber, lvBool, lvIndex, lvDate);

  { The value a control showed when DataChange last loaded it, kept per kind, so "did the
    user change it" is a comparison and not a guess from OnChange -- which every control here
    fires on loads too, and the numeric edits fire again on focus changes when they reformat.
    The zero value (lvNone) is "nothing loaded yet". }
  TTyDBLoadedValue = record
    Kind: TTyDBLoadedKind;
    Text: string;
    Number: Double;
    Bool: Boolean;
    Index: Integer;
    Date: TDateTime;
    IsNull: Boolean;
  end;

function TyDBLoadedText(const AText: string): TTyDBLoadedValue;
function TyDBLoadedNumber(AValue: Double; AIsNull: Boolean): TTyDBLoadedValue;
function TyDBLoadedIndex(AIndex: Integer): TTyDBLoadedValue;

{ The user changed the control's value: put the dataset in dsEdit and mark the link modified,
  so UpdateData writes it back (on EditingDone, on leaving the control, or on a Post made
  elsewhere). When the dataset cannot be edited -- the control or the field is read-only,
  AutoEdit is off and nobody is editing -- the control goes back to the field's value.

  AInUserEdit is the control's flag for "this is the user's change, keep it": TDataSet.Edit
  announces deRecordChange, which reaches the control as DataChange, and a DataChange that
  reloaded the field there would throw away the very change that asked for the edit. Every
  control's DataChange returns at once while it is set. (LCL's TDBEdit unhooks OnDataChange
  around its clipboard edits for the same reason.) }
procedure TyDBUserChanged(ALink: TFieldDataLink; var AInUserEdit: Boolean);
{ About to let the user change the value (an erasing key, a step): True when the field is one a
  control may change and the dataset is now in dsEdit. A control asks BEFORE it changes, the way
  LCL's TDBEdit does, and drops the gesture when the answer is False; what it cannot ask for in
  advance ends in TyDBUserChanged.

  AInUserEdit is held here too. The control still shows the field, so the reload TDataSet.Edit
  sets off would show the same value -- but it would show it through the control's setter,
  which puts the caret at the end and drops the selection the key is about to replace (a
  masked edit rebuilds its whole text). }
function TyDBEditAllowed(ALink: TFieldDataLink; var AInUserEdit: Boolean): Boolean;
{ The same for a typed character: the field takes it (TyFieldCanAcceptKey) and editing could
  begin. AKey is one UTF-8 character; anything longer than a byte is checked as #255, LCL's
  stand-in for "some non-ASCII character". }
function TyDBKeyAllowed(ALink: TFieldDataLink; const AKey: string;
  var AInUserEdit: Boolean): Boolean;
{ The user picked a value in a choice (a check box, a switch, a radio group, a segmented
  control, a rating, a lookup list): TyDBUserChanged, and then the value goes into the record
  at once, as LCL's TDBCheckBox and TDBLookupListBox write theirs. A choice has no half-typed
  state to wait for, and the control that took it -- a radio group's child button -- is not
  always the one that later gets EditingDone or loses focus. }
procedure TyDBChoiceChanged(ALink: TFieldDataLink; var AInUserEdit: Boolean);

{ ValueChecked / ValueUnchecked: words separated by ';'. Does the list hold AText (spaces
  around a word ignored, case ignored, as LCL's TDBCheckBox matches)? An empty word matches
  nothing, so an empty field is neither checked nor unchecked. }
function TyDBWordListHas(const AWords, AText: string): Boolean;
{ The word a choice writes back: the first in the list, trimmed. }
function TyDBFirstWord(const AWords: string): string;

{ A number field's value, read and written as the number it is -- never through Text, whose
  form follows the locale's DecimalSeparator while the controls always show a '.'. Integer
  fields go through AsLargeInt (the value is rounded on the way in), currency and BCD fields
  through AsCurrency, everything else through AsFloat. }
function TyDBReadNumber(AField: TField): Double;
procedure TyDBWriteNumber(AField: TField; AValue: Double);

implementation

uses
  SysUtils, LazUTF8;

function TyFieldIsEditable(AField: TField): Boolean;
begin
  Result := (AField <> nil) and (AField.FieldKind <> fkCalculated) and not AField.Calculated
    and (AField.DataType <> ftAutoInc) and (AField.FieldKind <> fkLookup);
end;

function TyFieldCanAcceptKey(AField: TField; AKey: Char): Boolean;
begin
  Result := TyFieldIsEditable(AField) and AField.IsValidChar(AKey);
end;

function TyDBLoadedText(const AText: string): TTyDBLoadedValue;
begin
  Result := Default(TTyDBLoadedValue);
  Result.Kind := lvText;
  Result.Text := AText;
end;

function TyDBLoadedNumber(AValue: Double; AIsNull: Boolean): TTyDBLoadedValue;
begin
  Result := Default(TTyDBLoadedValue);
  Result.Kind := lvNumber;
  Result.Number := AValue;
  Result.IsNull := AIsNull;
end;

function TyDBLoadedIndex(AIndex: Integer): TTyDBLoadedValue;
begin
  Result := Default(TTyDBLoadedValue);
  Result.Kind := lvIndex;
  Result.Index := AIndex;
end;

{ ALink.Edit with the control's DataChange held off (see TyDBUserChanged). }
function StartEdit(ALink: TFieldDataLink; var AInUserEdit: Boolean): Boolean;
begin
  AInUserEdit := True;
  try
    Result := ALink.Edit;
  finally
    AInUserEdit := False;
  end;
end;

procedure TyDBUserChanged(ALink: TFieldDataLink; var AInUserEdit: Boolean);
begin
  if StartEdit(ALink, AInUserEdit) then
    ALink.Modified
  else
    ALink.Reset;
end;

function TyDBEditAllowed(ALink: TFieldDataLink; var AInUserEdit: Boolean): Boolean;
begin
  Result := TyFieldIsEditable(ALink.Field) and StartEdit(ALink, AInUserEdit);
end;

function TyDBKeyAllowed(ALink: TFieldDataLink; const AKey: string;
  var AInUserEdit: Boolean): Boolean;
var
  ch: Char;
begin
  if Length(AKey) = 1 then ch := AKey[1] else ch := #255;
  Result := TyFieldCanAcceptKey(ALink.Field, ch) and StartEdit(ALink, AInUserEdit);
end;

procedure TyDBChoiceChanged(ALink: TFieldDataLink; var AInUserEdit: Boolean);
begin
  TyDBUserChanged(ALink, AInUserEdit);
  if ALink.Editing then
    ALink.UpdateRecord;
end;

function TyDBWordListHas(const AWords, AText: string): Boolean;
var
  rest, w: string;
  p: Integer;
begin
  Result := False;
  rest := AWords;
  while rest <> '' do
  begin
    p := Pos(';', rest);
    if p = 0 then p := Length(rest) + 1;
    w := Trim(Copy(rest, 1, p - 1));
    Delete(rest, 1, p);
    if (w <> '') and (UTF8CompareText(w, Trim(AText)) = 0) then Exit(True);
  end;
end;

function TyDBFirstWord(const AWords: string): string;
var
  p: Integer;
begin
  p := Pos(';', AWords);
  if p = 0 then p := Length(AWords) + 1;
  Result := Trim(Copy(AWords, 1, p - 1));
end;

function IsIntegerField(AField: TField): Boolean;
begin
  Result := AField.DataType in [ftSmallint, ftInteger, ftWord, ftAutoInc, ftLargeint];
end;

function IsCurrencyField(AField: TField): Boolean;
begin
  Result := AField.DataType in [ftCurrency, ftBCD, ftFMTBcd];
end;

function TyDBReadNumber(AField: TField): Double;
begin
  if IsIntegerField(AField) then
    Result := AField.AsLargeInt
  else if IsCurrencyField(AField) then
    Result := AField.AsCurrency
  else
    Result := AField.AsFloat;
end;

procedure TyDBWriteNumber(AField: TField; AValue: Double);
begin
  if IsIntegerField(AField) then
    AField.AsLargeInt := Round(AValue)
  else if IsCurrencyField(AField) then
    AField.AsCurrency := AValue
  else
    AField.AsFloat := AValue;
end;

end.
