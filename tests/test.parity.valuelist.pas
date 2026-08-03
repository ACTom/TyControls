unit test.parity.valuelist;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry,
  tyControls.ValueListEditor;
type
  { LCL / Delphi API-parity guards for TTyValueListEditor's two value indexers.

    C:\lazarus\lcl\valedit.pas:201-202 declares
      property Keys[Index: Integer]: string      read GetKey   write SetKey;
      property Values[const Key: string]: string  read GetValue write SetValue;

    so on every other TValueListEditor `VLE.Values['Name'] := 'Bob'` is THE way to read and
    write a row, and Values[] takes a KEY. Ours used to take a ROW NUMBER, with the keyed form
    hidden under ValueOf[] -- which meant Values[0] named two different rows on the two
    libraries and ported code that compiled at all did the wrong thing in silence.

    These guards pin the SHAPE (Values by key, ValueFromIndex by root-row number) and the three
    behaviours ported code leans on: the key lookup folds case, writing an unknown key appends
    the row, and reading an unknown key yields ''. Each is a place where a plausible
    implementation compiles and answers wrongly, so none of them is self-evident from the
    declaration alone. }
  TValueListParityTest = class(TTestCase)
  private
    FFired: Integer;
    FLastRow: TTyValueRow;
    procedure OnValChanged(Sender: TObject; ARow: TTyValueRow);
    function MakeWH: TTyValueListEditor;   // Width=100, Height=50
  published
    procedure TestValuesAreIndexedByKey;
    procedure TestValuesAndValueFromIndexAreDifferentLookups;
    procedure TestValuesWriteByKeyHitsThatRowAndFiresEvent;
    procedure TestValuesKeyLookupFoldsCase;
    procedure TestValuesWriteOfUnknownKeyAppendsRow;
    procedure TestValuesReadOfUnknownKeyIsEmpty;
    procedure TestValueFromIndexIsRowIndexed;
  end;

implementation

procedure TValueListParityTest.OnValChanged(Sender: TObject; ARow: TTyValueRow);
begin
  Inc(FFired);
  FLastRow := ARow;
end;

function TValueListParityTest.MakeWH: TTyValueListEditor;
begin
  FFired := 0; FLastRow := nil;
  Result := TTyValueListEditor.Create(nil);
  Result.InsertRow('Width', '100');
  Result.InsertRow('Height', '50');
end;

procedure TValueListParityTest.TestValuesAreIndexedByKey;
var e: TTyValueListEditor;
begin
  e := MakeWH;
  try
    AssertEquals('Values[key] reads that key''s row', '100', e.Values['Width']);
    AssertEquals('...and so does the second key', '50', e.Values['Height']);
  finally e.Free; end;
end;

procedure TValueListParityTest.TestValuesAndValueFromIndexAreDifferentLookups;
var e: TTyValueListEditor;
begin
  { The two indexers must not be able to collapse into each other. A row whose KEY is the
    digit '0' -- and whose value differs from root row 0's -- is the case that tells them
    apart: with a key-indexed Values[] the two reads below disagree, and any implementation
    that resolves the key as a row number (the exact confusion this rename removes) makes
    them agree. The plain lookups in the test above would survive such a regression whenever
    the keys happen not to look like numbers; this one cannot. }
  e := MakeWH;
  try
    e.InsertRow('0', 'key-is-zero');
    AssertEquals('Values[''0''] = the row KEYED ''0''', 'key-is-zero', e.Values['0']);
    AssertEquals('ValueFromIndex[0] = root row 0', '100', e.ValueFromIndex[0]);
  finally e.Free; end;
end;

procedure TValueListParityTest.TestValuesWriteByKeyHitsThatRowAndFiresEvent;
var e: TTyValueListEditor;
begin
  e := MakeWH;
  try
    e.OnValueChanged := @OnValChanged;
    e.Values['Height'] := '75';
    AssertEquals('read back by key', '75', e.Values['Height']);
    AssertEquals('the KEYED row changed', '75', e.ValueFromIndex[1]);
    AssertEquals('the other row did not', '100', e.ValueFromIndex[0]);
    AssertEquals('no row appended', 2, e.RowCount);
    AssertEquals('event fired once', 1, FFired);
    AssertTrue('event carried the keyed row', FLastRow = e.Row(1));
  finally e.Free; end;
end;

procedure TValueListParityTest.TestValuesKeyLookupFoldsCase;
var e: TTyValueListEditor;
begin
  { LCL resolves the key through Strings.IndexOfName (valedit.pas:1094/1105), which compares
    with TStringList.DoCompareText on a list whose CaseSensitive is never set -- i.e. False.
    A case-SENSITIVE lookup here would compile and then read '' for a ported Values['height'],
    and worse, a ported write would APPEND a second 'height' row beside the 'Height' one. }
  e := MakeWH;
  try
    AssertEquals('lower-case key finds it', '50', e.Values['height']);
    AssertEquals('upper-case key finds it', '50', e.Values['HEIGHT']);
    e.Values['hEiGhT'] := '75';
    AssertEquals('the existing row was written', '75', e.ValueFromIndex[1]);
    AssertEquals('no duplicate row appended', 2, e.RowCount);
  finally e.Free; end;
end;

procedure TValueListParityTest.TestValuesWriteOfUnknownKeyAppendsRow;
var e: TTyValueListEditor;
begin
  { LCL's setter falls through to Strings.Add when the key is absent (valedit.pas:1110-1114),
    so ported code populates the editor by assigning to keys that do not exist yet. Dropping
    the write instead would be silent data loss. }
  e := MakeWH;
  try
    e.OnValueChanged := @OnValChanged;
    e.Values['Depth'] := '7';
    AssertEquals('row appended', 3, e.RowCount);
    AssertEquals('appended with that key', 'Depth', e.Keys[2]);
    AssertEquals('appended with that value', '7', e.Values['Depth']);
    AssertEquals('and it is visible', 3, e.VisibleRowCount);
    { Appending is a row ADD, not a value CHANGE -- AddRow / InsertRow are silent too, and a
      handler that repaints "the row that changed" has no prior row to be told about. }
    AssertEquals('append fires no OnValueChanged', 0, FFired);
  finally e.Free; end;
end;

procedure TValueListParityTest.TestValuesReadOfUnknownKeyIsEmpty;
var e: TTyValueListEditor;
begin
  e := MakeWH;
  try
    AssertEquals('unknown key reads empty', '', e.Values['Depth']);
    AssertEquals('reading did not create it', 2, e.RowCount);
  finally e.Free; end;
end;

procedure TValueListParityTest.TestValueFromIndexIsRowIndexed;
var e: TTyValueListEditor;
begin
  e := MakeWH;
  try
    AssertEquals('root row 0', '100', e.ValueFromIndex[0]);
    AssertEquals('root row 1', '50', e.ValueFromIndex[1]);
    e.ValueFromIndex[0] := '200';
    AssertEquals('written by row number', '200', e.ValueFromIndex[0]);
    AssertEquals('same row seen through its key', '200', e.Values['Width']);
    AssertEquals('out of range reads empty', '', e.ValueFromIndex[99]);
    { The row form addresses EXISTING rows only: unlike the key setter it must never append,
      or a stray index would quietly grow the list with an empty-keyed row. }
    e.ValueFromIndex[99] := 'x';
    AssertEquals('out-of-range write appended nothing', 2, e.RowCount);
  finally e.Free; end;
end;

initialization
  RegisterTest(TValueListParityTest);
end.
