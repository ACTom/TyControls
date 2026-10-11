unit test.combobox;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, StdCtrls, fpcunit, testregistry, tyControls.ComboBox;
type
  TComboFilterTest = class(TTestCase)
  published
    procedure TestPrefixFilter;
    procedure TestEmptyPrefixReturnsAll;
    procedure TestNoMatchReturnsEmpty;
  end;

  TComboEditableTest = class(TTestCase)
  published
    procedure TestEditorPresentOnlyInDropDown;
    procedure TestFreeTextSurvivesItemsChange;
    procedure TestMaxLengthForwardedToEditor;
    procedure TestMaxLengthBeforeStyleSwitch;
    procedure TestCharCaseSyncsText;
    procedure TestASelectionFromCodeReachesTheField;
  end;
implementation

procedure TComboFilterTest.TestPrefixFilter;
var src, dst: TStringList;
begin
  src := TStringList.Create;
  try
    src.AddStrings(['Alpha','Beta','Alubar','beacon']);
    dst := TyFilterItemsByPrefix(src, 'al');   // case-insensitive
    try
      AssertEquals('two match', 2, dst.Count);
      AssertEquals('Alpha', dst[0]); AssertEquals('Alubar', dst[1]);
    finally dst.Free; end;
  finally src.Free; end;
end;

procedure TComboFilterTest.TestEmptyPrefixReturnsAll;
var src, dst: TStringList;
begin
  src := TStringList.Create;
  try
    src.AddStrings(['a','b','c']);
    dst := TyFilterItemsByPrefix(src, '');
    try AssertEquals('all', 3, dst.Count); finally dst.Free; end;
  finally src.Free; end;
end;

procedure TComboFilterTest.TestNoMatchReturnsEmpty;
var src, dst: TStringList;
begin
  src := TStringList.Create;
  try
    src.AddStrings(['a','b']);
    dst := TyFilterItemsByPrefix(src, 'zzz');
    try AssertEquals('none', 0, dst.Count); finally dst.Free; end;
  finally src.Free; end;
end;

procedure TComboEditableTest.TestEditorPresentOnlyInDropDown;
var c: TTyComboBox;
begin
  c := TTyComboBox.Create(nil);
  try
    AssertFalse('list-mode: no editor visible', c.EditorVisibleForTest);
    c.Style := csDropDown;
    AssertTrue('dropdown-mode: editor visible', c.EditorVisibleForTest);
  finally c.Free; end;
end;

{ The ribbon example's font box: csDropDown, ItemIndex := 0 from code. The field stayed
  empty, and picking row 0 could not fill it either (already selected: no change, no commit). }
procedure TComboEditableTest.TestASelectionFromCodeReachesTheField;
var c: TTyComboBox; changes: Integer;
begin
  c := TTyComboBox.Create(nil);
  try
    c.Style := csDropDown;
    c.Items.AddStrings(['DengXian', 'SimSun', 'Arial']);
    c.ItemIndex := 0;
    AssertEquals('ItemIndex := 0 shows the row', 'DengXian', c.EditorTextForTest);
    c.ItemIndex := 2;
    AssertEquals('another row', 'Arial', c.EditorTextForTest);
    AssertFalse('seeding is not typing: no suggestion list', c.DroppedDown);
    c.ItemIndex := -1;
    AssertEquals('no selection, empty field', '', c.EditorTextForTest);
    AssertEquals('Text agrees', '', c.Text);
  finally c.Free; end;
end;

procedure TComboEditableTest.TestFreeTextSurvivesItemsChange;
var c: TTyComboBox;
begin
  c := TTyComboBox.Create(nil);
  try
    c.Style := csDropDown;
    c.Items.AddStrings(['Alpha','Beta']);
    c.Text := 'Gam';                 // free text, not in Items
    c.Items.Add('Gamma');            // triggers ItemsChanged->ResyncIndexFromText
    AssertEquals('free text preserved', 'Gam', c.Text);
    AssertEquals('no item selected', -1, c.ItemIndex);
  finally c.Free; end;
end;

procedure TComboEditableTest.TestMaxLengthForwardedToEditor;
var c: TTyComboBox;
begin
  c := TTyComboBox.Create(nil);
  try
    c.Style := csDropDown;
    c.MaxLength := 5;
    AssertEquals('editor MaxLength forwarded', 5, c.EditorMaxLengthForTest);
  finally c.Free; end;
end;

procedure TComboEditableTest.TestMaxLengthBeforeStyleSwitch;
var c: TTyComboBox;
begin
  c := TTyComboBox.Create(nil);
  try
    c.MaxLength := 5;                // set BEFORE switching to editable style
    c.Style := csDropDown;
    AssertEquals('editor MaxLength holds across style switch', 5, c.EditorMaxLengthForTest);
  finally c.Free; end;
end;

procedure TComboEditableTest.TestCharCaseSyncsText;
var c: TTyComboBox;
begin
  c := TTyComboBox.Create(nil);
  try
    c.Style := csDropDown;
    c.Text := 'hello';              // free text pushed into the editor
    c.CharCase := ecUppercase;      // TTyEdit re-cases in place without OnChange
    AssertEquals('Text re-read after CharCase change', 'HELLO', c.Text);
  finally c.Free; end;
end;

initialization
  RegisterTest(TComboFilterTest);
  RegisterTest(TComboEditableTest);
end.
