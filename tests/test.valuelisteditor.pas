unit test.valuelisteditor;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry,
  tyControls.ValueListEditor;
type
  TValueListEditorTest = class(TTestCase)
  private
    FFired: Integer;
    FLastRow: TTyValueRow;
    procedure OnValChanged(Sender: TObject; ARow: TTyValueRow);
    function MakeWH: TTyValueListEditor;   // Width=100, Height=50
  published
    procedure TestInsertAndRead;
    procedure TestSetValueFiresEvent;
    procedure TestSetValueNoEventWhenUnchanged;
    procedure TestValueOfByName;
    procedure TestValueMayContainAnything;
    procedure TestDeleteRow;
    procedure TestKeyColumnWidthClamp;
    procedure TestReadOnlyBlocksEdit;
    procedure TestOutOfRangeSafe;
    procedure TestAddRowReturnsRow;
    procedure TestNestingAndExpand;
    procedure TestDisplayKeyValueAndStyle;
  end;
implementation

procedure TValueListEditorTest.OnValChanged(Sender: TObject; ARow: TTyValueRow);
begin
  Inc(FFired);
  FLastRow := ARow;
end;

function TValueListEditorTest.MakeWH: TTyValueListEditor;
begin
  FFired := 0; FLastRow := nil;
  Result := TTyValueListEditor.Create(nil);
  Result.InsertRow('Width', '100');
  Result.InsertRow('Height', '50');
end;

procedure TValueListEditorTest.TestInsertAndRead;
var e: TTyValueListEditor;
begin
  e := MakeWH;
  try
    AssertEquals('two root rows', 2, e.RowCount);
    AssertEquals('two visible rows', 2, e.VisibleRowCount);
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
    AssertTrue('event passed the row', FLastRow = e.Row(0));
    AssertEquals('event row key', 'Width', FLastRow.Key);
    AssertEquals('event row value', '200', FLastRow.Value);
  finally e.Free; end;
end;

procedure TValueListEditorTest.TestSetValueNoEventWhenUnchanged;
var e: TTyValueListEditor;
begin
  e := MakeWH;
  try
    e.OnValueChanged := @OnValChanged;
    e.Values[0] := '100';   // same -> no change, no event
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

procedure TValueListEditorTest.TestValueMayContainAnything;
var e: TTyValueListEditor;
begin
  // Value is a plain field now (no key=value string), so it may contain anything, incl. '='.
  e := MakeWH;
  try
    e.Values[0] := 'a=b=c';
    AssertEquals('value with = kept', 'a=b=c', e.Values[0]);
    AssertEquals('key preserved', 'Width', e.Keys[0]);
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
    AssertEquals('visible follows', 1, e.VisibleRowCount);
  finally e.Free; end;
end;

procedure TValueListEditorTest.TestKeyColumnWidthClamp;
var e: TTyValueListEditor;
begin
  e := MakeWH;
  try
    AssertEquals('default', 110, e.KeyColumnWidth);
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
    e.BeginEdit(0);             // a no-op (and never touches a handle)
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
    AssertTrue('row(99) nil', e.Row(99) = nil);
    AssertEquals('still two rows', 2, e.RowCount);
  finally e.Free; end;
end;

procedure TValueListEditorTest.TestAddRowReturnsRow;
var e: TTyValueListEditor; r: TTyValueRow;
begin
  e := TTyValueListEditor.Create(nil);
  try
    r := e.AddRow('Enabled', 'True');
    AssertTrue('returns a row', r <> nil);
    r.EditorKind := vekBoolean;
    r.ReadOnly := True;
    AssertTrue('same row back', e.Row(0) = r);
    AssertEquals('kind stored', Ord(vekBoolean), Ord(e.Row(0).EditorKind));
    AssertTrue('readonly stored', e.Row(0).ReadOnly);
  finally e.Free; end;
end;

procedure TValueListEditorTest.TestNestingAndExpand;
var e: TTyValueListEditor; font: TTyValueRow;
begin
  e := TTyValueListEditor.Create(nil);
  try
    font := e.AddRow('Font', '(TFont)');
    font.AddChild('Color', 'clRed');
    font.AddChild('Size', '9');
    e.UpdateRows;                         // children added directly -> refresh the visible list
    AssertEquals('one root row', 1, e.RowCount);
    AssertTrue('has children', font.HasChildren);
    AssertEquals('child count', 2, font.ChildCount);
    AssertEquals('expanded -> 3 visible', 3, e.VisibleRowCount);
    e.SetExpanded(font, False);
    AssertEquals('collapsed -> 1 visible', 1, e.VisibleRowCount);
    e.SetExpanded(font, True);
    AssertEquals('re-expanded -> 3 visible', 3, e.VisibleRowCount);
  finally e.Free; end;
end;

procedure TValueListEditorTest.TestDisplayKeyValueAndStyle;
var e: TTyValueListEditor; r: TTyValueRow;
begin
  e := TTyValueListEditor.Create(nil);
  try
    r := e.AddRow('color', '$FF0000');
    AssertEquals('effective key = key by default', 'color', r.EffectiveKey);
    AssertEquals('effective value = value by default', '$FF0000', r.EffectiveValue);
    r.DisplayKey := '颜色';
    r.DisplayValue := '红色';
    AssertEquals('display key overrides', '颜色', r.EffectiveKey);
    AssertEquals('display value overrides', '红色', r.EffectiveValue);
    AssertEquals('actual key untouched', 'color', r.Key);
    AssertEquals('actual value untouched', '$FF0000', r.Value);
  finally e.Free; end;
end;

initialization
  RegisterTest(TValueListEditorTest);
end.
