unit tyControls.DB.Common;
{$mode objfpc}{$H+}
{ What every data-aware control in tycontrols_db shares.

  The data link itself is LCL's: TFieldDataLink, TDBLookup and ChangeDataSource sit in the
  interface of DBCtrls and are the same in Lazarus 3.0 and 4.4, so the controls use them as
  they are. What LCL keeps to itself is here. }
interface

uses
  DB;

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

implementation

function TyFieldIsEditable(AField: TField): Boolean;
begin
  Result := (AField <> nil) and (AField.FieldKind <> fkCalculated) and not AField.Calculated
    and (AField.DataType <> ftAutoInc) and (AField.FieldKind <> fkLookup);
end;

function TyFieldCanAcceptKey(AField: TField; AKey: Char): Boolean;
begin
  Result := TyFieldIsEditable(AField) and AField.IsValidChar(AKey);
end;

end.
