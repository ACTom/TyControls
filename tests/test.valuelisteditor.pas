unit test.valuelisteditor;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry,
  tyControls.ValueListEditor;
type
  TValueListEditorTest = class(TTestCase)
  private
    FFired: Integer;
    FLastRow: Integer;
    FLastKey, FLastValue: string;
    procedure OnValChanged(Sender: TObject; ARow: Integer; const AKey, AValue: string);
    function MakeWH: TTyValueListEditor;   // Width=100, Height=50
  published
    procedure TestInsertAndRead;
    procedure TestSetValueFiresEvent;
    procedure TestSetValueNoEventWhenUnchanged;
    procedure TestValueOfByName;
    procedure TestEmptyValueStoredCleanly;
    procedure TestDeleteRow;
    procedure TestKeyColumnWidthClamp;
    procedure TestReadOnlyBlocksEdit;
    procedure TestOutOfRangeSafe;
    procedure TestSetValueOnSortedListNoCrash;
    procedure TestValueMayContainEquals;
  end;
implementation

procedure TValueListEditorTest.OnValChanged(Sender: TObject; ARow: Integer;
  const AKey, AValue: string);
begin
  Inc(FFired);
  FLastRow := ARow;
  FLastKey := AKey;
  FLastValue := AValue;
end;

function TValueListEditorTest.MakeWH: TTyValueListEditor;
begin
  FFired := 0; FLastRow := -9; FLastKey := ''; FLastValue := '';
  Result := TTyValueListEditor.Create(nil);
  Result.InsertRow('Width', '100');
  Result.InsertRow('Height', '50');
end;

procedure TValueListEditorTest.TestInsertAndRead;
var e: TTyValueListEditor;
begin
  e := MakeWH;
  try
    AssertEquals('two rows', 2, e.RowCount);
    AssertEquals('key 0', 'Width', e.Keys[0]);
    AssertEquals('value 0', '100', e.Values[0]);
    AssertEquals('key 1', 'Height', e.Keys[1]);
    AssertEquals('value 1', '50', e.Values[1]);
    AssertEquals('not editing', -1, e.EditingRow);
  finally e.Free; end;
end;

procedure TValueListEditorTest.TestSetValueFiresEvent;
var e: TTyValueListEditor;
begin
  e := MakeWH;
  try
    e.OnValueChanged := @OnValChanged;
    e.Values[0] := '200';
    AssertEquals('value updated', '200', e.Values[0]);
    AssertEquals('event fired once', 1, FFired);
    AssertEquals('event row', 0, FLastRow);
    AssertEquals('event key', 'Width', FLastKey);
    AssertEquals('event value', '200', FLastValue);
    AssertEquals('key preserved', 'Width', e.Keys[0]);
  finally e.Free; end;
end;

procedure TValueListEditorTest.TestSetValueNoEventWhenUnchanged;
var e: TTyValueListEditor;
begin
  e := MakeWH;
  try
    e.OnValueChanged := @OnValChanged;
    e.Values[0] := '100';   // same as current -> no change, no event
    AssertEquals('no event', 0, FFired);
  finally e.Free; end;
end;

procedure TValueListEditorTest.TestValueOfByName;
var e: TTyValueListEditor;
begin
  e := MakeWH;
  try
    AssertEquals('lookup by key', '50', e.ValueOf['Height']);
    e.ValueOf['Height'] := '75';
    AssertEquals('write by key', '75', e.Values[1]);
    AssertEquals('missing key -> empty', '', e.ValueOf['Depth']);
  finally e.Free; end;
end;

procedure TValueListEditorTest.TestEmptyValueStoredCleanly;
var e: TTyValueListEditor;
begin
  e := MakeWH;
  try
    e.Values[0] := '';
    AssertEquals('key kept', 'Width', e.Keys[0]);
    AssertEquals('value empty', '', e.Values[0]);
    AssertEquals('line is key=', 'Width=', e.Items[0]);
  finally e.Free; end;
end;

procedure TValueListEditorTest.TestDeleteRow;
var e: TTyValueListEditor;
begin
  e := MakeWH;
  try
    e.DeleteRow(0);
    AssertEquals('one row left', 1, e.RowCount);
    AssertEquals('remaining key', 'Height', e.Keys[0]);
  finally e.Free; end;
end;

procedure TValueListEditorTest.TestKeyColumnWidthClamp;
var e: TTyValueListEditor;
begin
  e := MakeWH;
  try
    AssertEquals('default', 100, e.KeyColumnWidth);
    e.KeyColumnWidth := 5;      // clamped up to the 16 minimum
    AssertEquals('clamped low', 16, e.KeyColumnWidth);
    e.KeyColumnWidth := 180;
    AssertEquals('set wide', 180, e.KeyColumnWidth);
  finally e.Free; end;
end;

procedure TValueListEditorTest.TestReadOnlyBlocksEdit;
var e: TTyValueListEditor;
begin
  e := MakeWH;
  try
    e.ReadOnly := True;
    e.BeginEdit(0);             // must be a no-op (and never touch a handle)
    AssertEquals('no edit started', -1, e.EditingRow);
  finally e.Free; end;
end;

procedure TValueListEditorTest.TestOutOfRangeSafe;
var e: TTyValueListEditor;
begin
  e := MakeWH;
  try
    AssertEquals('negative key', '', e.Keys[-1]);
    AssertEquals('past-end value', '', e.Values[99]);
    e.Values[99] := 'x';       // ignored, no crash
    e.DeleteRow(99);           // ignored, no crash
    AssertEquals('still two rows', 2, e.RowCount);
  finally e.Free; end;
end;

procedure TValueListEditorTest.TestSetValueOnSortedListNoCrash;
var e: TTyValueListEditor;
begin
  // Regression: committing a value must not raise SSortedListError when the inherited Sorted
  // is on (TStringList.Put forbids indexed writes on a sorted list). SetValue forces it unsorted.
  e := MakeWH;                 // Width=100, Height=50
  try
    e.Sorted := True;          // hostile: reorders to Height=50, Width=100
    e.Values[0] := '999';      // editing row 0 (now Height) would crash before the fix
    AssertEquals('value updated', '999', e.Values[0]);
    AssertEquals('row 0 is Height after sort', 'Height', e.Keys[0]);
  finally e.Free; end;
end;

procedure TValueListEditorTest.TestValueMayContainEquals;
var e: TTyValueListEditor;
begin
  // Only the FIRST '=' separates key from value, so a value may itself contain '=' and the
  // exact key is preserved on commit (SetValue keeps the prefix up to the first '=').
  e := MakeWH;
  try
    e.Values[0] := 'a=b=c';
    AssertEquals('value with = round-trips', 'a=b=c', e.Values[0]);
    AssertEquals('key preserved', 'Width', e.Keys[0]);
    AssertEquals('line is Width=a=b=c', 'Width=a=b=c', e.Items[0]);
  finally e.Free; end;
end;

initialization
  RegisterTest(TValueListEditorTest);
end.
