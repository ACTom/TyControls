unit test.db.common;
{$mode objfpc}{$H+}

{ tyControls.DB.Common (issue #34): the two field predicates LCL keeps private, and the fixture
  every data-aware suite stands on.

  Each predicate test changes ONE property of an otherwise editable field, so a clause dropped
  from TyFieldIsEditable turns exactly the test about it red rather than none of them. }

interface

uses
  Classes, SysUtils, DB, BufDataset, fpcunit, testregistry,
  dbfixtures, tyControls.DB.Common;

type
  TDBCommonTest = class(TTestCase)
  private
    FFix: TDbFixture;
    FKinds: TBufDataset;   { one field of each kind the predicates tell apart }
    function KindField(const AName: string): TField;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheFixtureHasTwoFullRowsAndAnEmptyOne;
    procedure TestTheFixtureForgetsASourceFreedUnderIt;
    procedure TestNoFieldIsNotEditable;
    procedure TestAPlainDataFieldIsEditable;
    procedure TestACalculatedFieldIsNotEditable;
    procedure TestAFieldFlaggedCalculatedIsNotEditable;
    procedure TestAnAutoIncrementFieldIsNotEditable;
    procedure TestALookupFieldIsNotEditable;
    procedure TestANumericFieldRefusesLetters;
    procedure TestAFieldThatIsNotEditableRefusesEveryKey;
  end;

implementation

{ People's own fields are all plain fkData; this second table has the kinds that are not. It is
  opened, because a predicate that only works on fields of a closed dataset answers nothing a
  control will ask. }
procedure TDBCommonTest.SetUp;

  function AddField(AClass: TFieldClass; const AName: string; AKind: TFieldKind): TField;
  begin
    Result := AClass.Create(FKinds);
    Result.FieldName := AName;
    Result.FieldKind := AKind;
    if Result is TStringField then Result.Size := 20;
    Result.DataSet := FKinds;
  end;

var
  look: TField;
begin
  FFix := NewDbFixture(nil);
  FKinds := TBufDataset.Create(nil);
  AddField(TAutoIncField, 'ID', fkData);
  AddField(TStringField, 'Name', fkData);
  AddField(TIntegerField, 'CityID', fkData);
  AddField(TStringField, 'Flagged', fkData).Calculated := True;
  AddField(TStringField, 'Calc', fkCalculated);
  look := AddField(TStringField, 'City', fkLookup);
  look.LookupDataSet := FFix.Cities;
  look.KeyFields := 'CityID';
  look.LookupKeyFields := 'ID';
  look.LookupResultField := 'Name';
  FKinds.CreateDataset;
end;

procedure TDBCommonTest.TearDown;
begin
  FreeAndNil(FKinds);
  FreeAndNil(FFix);
end;

function TDBCommonTest.KindField(const AName: string): TField;
begin
  Result := FKinds.FieldByName(AName);
end;

procedure TDBCommonTest.TestTheFixtureHasTwoFullRowsAndAnEmptyOne;
var
  i: Integer;
begin
  AssertTrue('People is open', FFix.DS.Active);
  AssertTrue('and browsing, not editing', FFix.DS.State = dsBrowse);
  AssertTrue('Src shows People', FFix.Src.DataSet = FFix.DS);
  AssertTrue('CitySrc shows Cities', FFix.CitySrc.DataSet = FFix.Cities);
  AssertEquals('three people', 3, FFix.DS.RecordCount);
  AssertEquals('three cities', 3, FFix.Cities.RecordCount);
  AssertEquals('People has the fourteen fields of the plan', 14, FFix.DS.FieldCount);

  AssertEquals('on row 1', 1, FFix.DS.FieldByName('ID').AsInteger);
  for i := 0 to FFix.DS.FieldCount - 1 do
    AssertFalse('row 1 has a value in ' + FFix.DS.Fields[i].FieldName,
      FFix.DS.Fields[i].IsNull);
  AssertEquals(CFixNames[1], FFix.DS.FieldByName('Name').AsString);
  AssertEquals(CFixAmounts[1], FFix.DS.FieldByName('Amount').AsFloat, 0);
  AssertTrue('Born is a date', FFix.DS.FieldByName('Born').DataType = ftDate);
  AssertEquals(FixBorn(1), FFix.DS.FieldByName('Born').AsDateTime, 0);
  AssertTrue('Pic holds bytes', TBlobField(FFix.DS.FieldByName('Pic')).BlobSize > 0);

  FFix.DS.Next;
  AssertEquals(CFixNames[2], FFix.DS.FieldByName('Name').AsString);
  AssertEquals(CFixActives[2], FFix.DS.FieldByName('Active').AsBoolean);

  FFix.DS.Next;
  AssertEquals('row 3 has its ID', 3, FFix.DS.FieldByName('ID').AsInteger);
  for i := 0 to FFix.DS.FieldCount - 1 do
    if FFix.DS.Fields[i].FieldName <> 'ID' then
      AssertTrue('row 3 has no ' + FFix.DS.Fields[i].FieldName, FFix.DS.Fields[i].IsNull);
end;

procedure TDBCommonTest.TestTheFixtureForgetsASourceFreedUnderIt;
begin
  { C7 frees the data source under a live control; the fixture must not free it again. }
  FFix.Src.Free;
  AssertNull('the fixture forgot Src', FFix.Src);
  FFix.DS.Free;
  AssertNull('and People', FFix.DS);
  FreeAndNil(FFix);   { would be a double free without the notification }
end;

procedure TDBCommonTest.TestNoFieldIsNotEditable;
begin
  AssertFalse(TyFieldIsEditable(nil));
  AssertFalse(TyFieldCanAcceptKey(nil, 'a'));
end;

procedure TDBCommonTest.TestAPlainDataFieldIsEditable;
begin
  AssertTrue('a string field', TyFieldIsEditable(FFix.DS.FieldByName('Name')));
  AssertTrue('an integer field', TyFieldIsEditable(FFix.DS.FieldByName('Qty')));
  AssertTrue('a blob field', TyFieldIsEditable(FFix.DS.FieldByName('Pic')));
  AssertTrue('the key a lookup reads', TyFieldIsEditable(KindField('CityID')));
end;

procedure TDBCommonTest.TestACalculatedFieldIsNotEditable;
begin
  AssertTrue('precondition: FCL leaves the Calculated flag of an fkCalculated field off',
    not KindField('Calc').Calculated);
  AssertFalse(TyFieldIsEditable(KindField('Calc')));
end;

procedure TDBCommonTest.TestAFieldFlaggedCalculatedIsNotEditable;
begin
  { LCL's own test reads the flag; a field someone flagged keeps that answer here. }
  AssertTrue('precondition: a data field', KindField('Flagged').FieldKind = fkData);
  AssertFalse(TyFieldIsEditable(KindField('Flagged')));
end;

procedure TDBCommonTest.TestAnAutoIncrementFieldIsNotEditable;
begin
  AssertTrue('precondition: a data field', KindField('ID').FieldKind = fkData);
  AssertTrue('precondition: an auto-increment one', KindField('ID').DataType = ftAutoInc);
  AssertFalse(TyFieldIsEditable(KindField('ID')));
end;

procedure TDBCommonTest.TestALookupFieldIsNotEditable;
begin
  AssertTrue('precondition: a lookup field', KindField('City').FieldKind = fkLookup);
  AssertFalse('precondition: not flagged Calculated', KindField('City').Calculated);
  AssertFalse(TyFieldIsEditable(KindField('City')));
end;

procedure TDBCommonTest.TestANumericFieldRefusesLetters;
var
  qty, name: TField;
begin
  qty := FFix.DS.FieldByName('Qty');
  name := FFix.DS.FieldByName('Name');
  AssertFalse('a letter into an integer', TyFieldCanAcceptKey(qty, 'a'));
  AssertTrue('a digit into an integer', TyFieldCanAcceptKey(qty, '7'));
  AssertTrue('a minus sign into an integer', TyFieldCanAcceptKey(qty, '-'));
  AssertTrue('a letter into a string', TyFieldCanAcceptKey(name, 'a'));
end;

procedure TDBCommonTest.TestAFieldThatIsNotEditableRefusesEveryKey;
begin
  AssertTrue('precondition: the field itself takes the letter',
    KindField('Calc').IsValidChar('a'));
  AssertFalse('a calculated field', TyFieldCanAcceptKey(KindField('Calc'), 'a'));
  AssertFalse('a lookup field', TyFieldCanAcceptKey(KindField('City'), 'a'));
end;

initialization
  RegisterTest(TDBCommonTest);
end.
