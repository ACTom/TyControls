unit test.valuelisteditor;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, LCLType, Controls, Forms, fpcunit, testregistry, TypInfo, Types,
  tyControls.ValueListEditor;
type
  { Drive the input paths to test the numeric filter headlessly. }
  TValueEditAccess = class(TTyValueEdit)
  public
    procedure FeedKey(const AKey: string);      // per-char typing path (UTF8KeyPress -> InjectKey)
    procedure FeedString(const AStr: string);   // bulk path (paste / IME route through InjectStringAt)
    procedure SelAll;
  end;

  TValueListEditorTest = class(TTestCase)
  private
    FFired: Integer;
    FLastRow: TTyValueRow;
    procedure OnValChanged(Sender: TObject; ARow: TTyValueRow);
    procedure OnEditDialogRow(Sender: TObject; ARow: TTyValueRow);
    function MakeWH: TTyValueListEditor;   // Width=100, Height=50
  published
    procedure TestTheRowsAreWhatTheFormFileKeeps;   // #167
    procedure TestInsertAndRead;
    procedure TestSetValueFromIndexFiresEvent;
    procedure TestSetValueFromIndexNoEventWhenUnchanged;
    procedure TestValuesByKey;
    procedure TestValueMayContainAnything;
    procedure TestDeleteRow;
    procedure TestKeyColumnWidthClamp;
    procedure TestReadOnlyBlocksEdit;
    procedure TestOutOfRangeSafe;
    procedure TestAddRowReturnsRow;
    procedure TestNestingAndExpand;
    procedure TestDisplayKeyValueAndStyle;
    procedure TestDialogEditorFiresCallback;
    procedure TestReadOnlyRowBlocksDialog;
    procedure TestExpandRepinsSelectionByIdentity;
    procedure TestCollapseRepinsSelectionByIdentity;
    procedure TestCollapsedChildDeselects;
    procedure TestFontDescriptorParse;
    procedure TestNumericEditorFilter;
    procedure TestCompositeFontStyleSync;
    procedure TestCompositeRowsNotFreelyEditable;
  end;
implementation

procedure TValueEditAccess.FeedKey(const AKey: string);
var k: TUTF8Char;
begin
  k := AKey;
  UTF8KeyPress(k);
end;

procedure TValueEditAccess.FeedString(const AStr: string);
begin
  InjectStringAt(AStr);
end;

procedure TValueEditAccess.SelAll;
begin
  SelectAll;
end;


procedure TValueListEditorTest.OnValChanged(Sender: TObject; ARow: TTyValueRow);
begin
  Inc(FFired);
  FLastRow := ARow;
end;

procedure TValueListEditorTest.OnEditDialogRow(Sender: TObject; ARow: TTyValueRow);
begin
  Inc(FFired);
  ARow.Value := 'picked';   // a real app would show a dialog; here just set the value
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
    AssertEquals('two displayed rows', 2, e.DisplayRowCount);
    AssertEquals('key 0', 'Width', e.Keys[0]);
    AssertEquals('value 0', '100', e.ValueFromIndex[0]);
    AssertEquals('key 1', 'Height', e.Keys[1]);
    AssertEquals('value 1', '50', e.ValueFromIndex[1]);
    AssertEquals('not editing', -1, e.EditingRow);
  finally e.Free; end;
end;

procedure TValueListEditorTest.TestSetValueFromIndexFiresEvent;
var e: TTyValueListEditor;
begin
  e := MakeWH;
  try
    e.OnValueChanged := @OnValChanged;
    e.ValueFromIndex[0] := '200';
    AssertEquals('value updated', '200', e.ValueFromIndex[0]);
    AssertEquals('event fired once', 1, FFired);
    AssertTrue('event passed the row', FLastRow = e.Row(0));
    AssertEquals('event row key', 'Width', FLastRow.Key);
    AssertEquals('event row value', '200', FLastRow.Value);
  finally e.Free; end;
end;

procedure TValueListEditorTest.TestSetValueFromIndexNoEventWhenUnchanged;
var e: TTyValueListEditor;
begin
  e := MakeWH;
  try
    e.OnValueChanged := @OnValChanged;
    e.ValueFromIndex[0] := '100';   // same -> no change, no event
    AssertEquals('no event', 0, FFired);
  finally e.Free; end;
end;

procedure TValueListEditorTest.TestValuesByKey;
var e: TTyValueListEditor;
begin
  e := MakeWH;
  try
    AssertEquals('lookup by key', '50', e.Values['Height']);
    e.Values['Height'] := '75';
    AssertEquals('write by key', '75', e.ValueFromIndex[1]);
    AssertEquals('missing key -> empty', '', e.Values['Depth']);
  finally e.Free; end;
end;

procedure TValueListEditorTest.TestValueMayContainAnything;
var e: TTyValueListEditor;
begin
  // Value is a plain field now (no key=value string), so it may contain anything, incl. '='.
  e := MakeWH;
  try
    e.ValueFromIndex[0] := 'a=b=c';
    AssertEquals('value with = kept', 'a=b=c', e.ValueFromIndex[0]);
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
    AssertEquals('display count follows', 1, e.DisplayRowCount);
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
    AssertEquals('past-end value', '', e.ValueFromIndex[99]);
    e.ValueFromIndex[99] := 'x';   // ignored, no crash
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
    AssertEquals('expanded -> 3 displayed', 3, e.DisplayRowCount);
    e.SetExpanded(font, False);
    AssertEquals('collapsed -> 1 displayed', 1, e.DisplayRowCount);
    e.SetExpanded(font, True);
    AssertEquals('re-expanded -> 3 displayed', 3, e.DisplayRowCount);
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

procedure TValueListEditorTest.TestDialogEditorFiresCallback;
var e: TTyValueListEditor; r: TTyValueRow;
begin
  // A vekDialog row's "…" (InvokeRowDialog) routes through OnEditRow (the app shows a dialog
  // and sets the value). Clicking the value cell only enters text edit — not the dialog.
  e := TTyValueListEditor.Create(nil);
  try
    FFired := 0;
    r := e.AddRow('Path', 'C:\old');
    r.EditorKind := vekDialog;
    e.OnEditRow := @OnEditDialogRow;
    e.InvokeRowDialog(0);     // flat 0 = the row; dispatch -> OnEditRow (no handle needed)
    AssertEquals('callback fired', 1, FFired);
    AssertEquals('value set by callback', 'picked', r.Value);
    AssertEquals('not left in edit mode', -1, e.EditingRow);
  finally e.Free; end;
end;

procedure TValueListEditorTest.TestReadOnlyRowBlocksDialog;
var e: TTyValueListEditor; r: TTyValueRow;
begin
  e := TTyValueListEditor.Create(nil);
  try
    FFired := 0;
    r := e.AddRow('Path', 'C:\old');
    r.EditorKind := vekDialog;
    r.ReadOnly := True;        // per-row read-only
    e.OnEditRow := @OnEditDialogRow;
    e.InvokeRowDialog(0);      // must be refused
    AssertEquals('callback NOT fired', 0, FFired);
    AssertEquals('value unchanged', 'C:\old', r.Value);
  finally e.Free; end;
end;

procedure TValueListEditorTest.TestNumericEditorFilter;
var ed: TValueEditAccess;
begin
  // The inline editor restricts typing when NumericMode is set (letters/extra dots swallowed).
  ed := TValueEditAccess.Create(nil);
  try
    ed.NumericMode := vnmInteger;
    ed.Text := '';
    ed.FeedKey('1'); ed.FeedKey('a'); ed.FeedKey('2'); ed.FeedKey('.'); ed.FeedKey('5');
    AssertEquals('integer: letters + dot rejected', '125', ed.Text);

    ed.NumericMode := vnmFloat;
    ed.Text := '';
    ed.FeedKey('3'); ed.FeedKey('.'); ed.FeedKey('.'); ed.FeedKey('1'); ed.FeedKey('x');
    AssertEquals('float: a single dot, no letters', '3.1', ed.Text);

    ed.NumericMode := vnmNone;
    ed.Text := '';
    ed.FeedKey('a'); ed.FeedKey('7');
    AssertEquals('plain: anything allowed', 'a7', ed.Text);

    // Typing '-' / '.' to REPLACE a full selection is allowed (filter runs post-deletion).
    ed.NumericMode := vnmInteger;
    ed.Text := '5'; ed.SelAll; ed.FeedKey('-');
    AssertEquals('minus replaces selection', '-', ed.Text);
    ed.NumericMode := vnmFloat;
    ed.Text := '1.5'; ed.SelAll; ed.FeedKey('.');
    AssertEquals('dot replaces selection', '.', ed.Text);

    // The bulk (paste / IME) path is filtered too, not just per-char typing.
    ed.NumericMode := vnmInteger;
    ed.Text := ''; ed.FeedString('1a2b3');
    AssertEquals('paste scrubbed to digits', '123', ed.Text);
    ed.NumericMode := vnmFloat;
    ed.Text := ''; ed.FeedString('12.34.56');
    AssertEquals('paste keeps a single dot', '12.3456', ed.Text);
  finally ed.Free; end;
end;

procedure TValueListEditorTest.TestExpandRepinsSelectionByIdentity;
var e: TTyValueListEditor; b: TTyValueRow;
begin
  // Selecting C, then expanding a node ABOVE it must keep C selected (its numeric index shifts).
  e := TTyValueListEditor.Create(nil);
  try
    e.SetBounds(0, 0, 200, 200); e.Font.PixelsPerInch := 96;
    e.AddRow('A', '1');
    b := e.AddRow('B', '(node)');
    b.AddChild('b1', 'x'); b.AddChild('b2', 'y');
    e.AddRow('C', '3');
    e.SetExpanded(b, False);              // flat: [A, B, C]
    AssertEquals('3 displayed while collapsed', 3, e.DisplayRowCount);
    e.ItemIndex := 2;                     // select C
    AssertEquals('C selected', 2, e.ItemIndex);
    e.SetExpanded(b, True);               // flat: [A, B, b1, b2, C] -> C now at 4
    AssertEquals('5 displayed while expanded', 5, e.DisplayRowCount);
    AssertEquals('C re-pinned by identity', 4, e.ItemIndex);
  finally e.Free; end;
end;

procedure TValueListEditorTest.TestCollapseRepinsSelectionByIdentity;
var e: TTyValueListEditor; b: TTyValueRow;
begin
  e := TTyValueListEditor.Create(nil);
  try
    e.SetBounds(0, 0, 200, 200); e.Font.PixelsPerInch := 96;
    e.AddRow('A', '1');
    b := e.AddRow('B', '(node)');
    b.AddChild('b1', 'x'); b.AddChild('b2', 'y');
    e.AddRow('C', '3');
    e.UpdateRows;                         // expanded by default: [A, B, b1, b2, C]
    e.ItemIndex := 4;                     // select C
    e.SetExpanded(b, False);              // -> [A, B, C], C back to 2
    AssertEquals('C re-pinned on collapse', 2, e.ItemIndex);
  finally e.Free; end;
end;

procedure TValueListEditorTest.TestCollapsedChildDeselects;
var e: TTyValueListEditor; b: TTyValueRow;
begin
  // A selected child that collapses out of view clears the selection (not a stale index).
  e := TTyValueListEditor.Create(nil);
  try
    e.SetBounds(0, 0, 200, 200); e.Font.PixelsPerInch := 96;
    b := e.AddRow('B', '(node)');
    b.AddChild('b1', 'x'); b.AddChild('b2', 'y');
    e.UpdateRows;                         // [B, b1, b2]
    e.ItemIndex := 1;                     // select b1
    AssertEquals('b1 selected', 1, e.ItemIndex);
    e.SetExpanded(b, False);              // b1 gone
    AssertEquals('selection cleared', -1, e.ItemIndex);
  finally e.Free; end;
end;

procedure TValueListEditorTest.TestFontDescriptorParse;
var nm: string; sz: Integer;
begin
  // Well-formed 'Name, Size'
  AssertTrue('simple ok', TyParseFontDescriptor('Arial, 12', nm, sz));
  AssertEquals('name', 'Arial', nm); AssertEquals('size', 12, sz);
  // Family name with spaces
  AssertTrue('spaced name ok', TyParseFontDescriptor('Times New Roman, 9', nm, sz));
  AssertEquals('spaced name', 'Times New Roman', nm); AssertEquals('spaced size', 9, sz);
  // Family name that itself contains commas: last integer token is the size
  AssertTrue('comma name ok', TyParseFontDescriptor('Font, With, Commas, 14', nm, sz));
  AssertEquals('comma name kept', 'Font, With, Commas', nm); AssertEquals('comma size', 14, sz);
  // No numeric token: whole thing is the name, size NOT forced (returns False)
  AssertFalse('no size', TyParseFontDescriptor('JustAName', nm, sz));
  AssertEquals('name is whole', 'JustAName', nm);
  // Garbled tail is not an integer: keep whole as name, no size
  AssertFalse('non-int tail', TyParseFontDescriptor('Bad, xyz', nm, sz));
  AssertEquals('garbled kept whole', 'Bad, xyz', nm);
end;

procedure TValueListEditorTest.TestCompositeFontStyleSync;
var e: TTyValueListEditor; font, style, size, bold, under: TTyValueRow;
begin
  // Editing a leaf (Bold) re-summarises its composite ancestors upward: Style, then Font.
  e := TTyValueListEditor.Create(nil);
  try
    font := e.AddRow('Font', 'Segoe UI, 9');
    font.EditorKind := vekFont;
    font.AddChild('Name', 'Segoe UI');
    size := font.AddChild('Size', '9');
    style := font.AddChild('Style', 'Regular');
    bold := style.AddChild('Bold', 'False');
    style.AddChild('Italic', 'False');
    under := style.AddChild('Underline', 'False');
    e.UpdateRows;

    e.SetRowValue(bold, 'True');
    AssertEquals('style reflects bold', 'Bold', style.Value);
    AssertEquals('font reflects style', 'Segoe UI, 9 Bold', font.Value);

    e.SetRowValue(under, 'True');   // a second (Underline) flag joins in the fixed order
    AssertEquals('style lists bold + underline', 'Bold, Underline', style.Value);
    AssertEquals('font reflects both flags', 'Segoe UI, 9 Bold Underline', font.Value);

    e.SetRowValue(bold, 'False');
    AssertEquals('only underline remains', 'Underline', style.Value);
    AssertEquals('font keeps underline', 'Segoe UI, 9 Underline', font.Value);

    e.SetRowValue(under, 'False');
    AssertEquals('style back to regular', 'Regular', style.Value);
    AssertEquals('font drops the style suffix', 'Segoe UI, 9', font.Value);

    e.SetRowValue(size, '14');
    AssertEquals('font reflects the size change', 'Segoe UI, 14', font.Value);
  finally e.Free; end;
end;

procedure TValueListEditorTest.TestCompositeRowsNotFreelyEditable;
var e: TTyValueListEditor; font, style, leaf, dlg: TTyValueRow;
begin
  // Dialog-backed rows (vekFont / vekDialog) have READ-ONLY inline text — clickable/copyable but
  // edited only via the "…" dialog (so a derived Font value can't desync from its children, and a
  // vekDialog value is set by its handler). A Style composite refuses inline editing entirely.
  e := TTyValueListEditor.Create(nil);
  try
    e.SetBounds(0, 0, 220, 220); e.Font.PixelsPerInch := 96;
    font := e.AddRow('Font', 'Segoe UI, 9'); font.EditorKind := vekFont;
    font.AddChild('Name', 'Segoe UI');
    font.AddChild('Size', '9');
    style := font.AddChild('Style', 'Regular');   // flat 3
    style.AddChild('Bold', 'False');
    style.AddChild('Italic', 'False');
    leaf := e.AddRow('LeafFont', 'Arial, 10'); leaf.EditorKind := vekFont;   // no children
    dlg := e.AddRow('About', 'v2.2.0');          dlg.EditorKind := vekDialog;
    e.UpdateRows;   // flat: Font0 Name1 Size2 Style3 Bold4 Italic5 LeafFont6 About7

    e.BeginEdit(0);
    AssertEquals('font composite entered edit', 0, e.EditingRow);
    AssertTrue('font composite inline text is read-only', e.InlineEditor.ReadOnly);

    e.BeginEdit(3);   // Style composite: closes the Font editor, then refuses
    AssertEquals('style composite refuses inline edit', -1, e.EditingRow);

    e.BeginEdit(6);
    AssertEquals('leaf font entered edit', 6, e.EditingRow);
    AssertTrue('leaf font inline text is read-only too', e.InlineEditor.ReadOnly);

    e.BeginEdit(7);
    AssertEquals('vekDialog row entered edit', 7, e.EditingRow);
    AssertTrue('vekDialog inline text is read-only', e.InlineEditor.ReadOnly);
  finally e.Free; end;
end;


{ #167: the rows are what the form file keeps, one Key=Value line each under Items -- Items
  held the view's keys, came back as blank rows, and AddRow wiped them. }
procedure TValueListEditorTest.TestTheRowsAreWhatTheFormFileKeeps;
var
  a, b: TTyValueListEditor;
  ms: TMemoryStream;
  txt: TStringStream;
begin
  a := TTyValueListEditor.Create(nil);
  b := TTyValueListEditor.Create(nil);
  ms := TMemoryStream.Create;
  txt := TStringStream.Create('');
  try
    a.AddRow('Name', 'Bob');
    a.AddRow('Age', '7');
    AssertFalse('the view''s key list is not what is written', IsStoredProp(a, 'Items'));
    ms.WriteComponent(a);
    ms.Position := 0;
    ObjectBinaryToText(ms, txt);
    AssertTrue('a row is a Key=Value line: ' + txt.DataString, Pos('''Name=Bob''', txt.DataString) > 0);
    { Read back from a form file's text -- the editor root above would also carry its own inline
      editor, which a form never writes (its owner is the list, not the form). }
    txt.Free;
    txt := TStringStream.Create('object Vle: TTyValueListEditor' + LineEnding +
      '  Items.Strings = (' + LineEnding + '    ''Name=Bob''' + LineEnding +
      '    ''Age=7''' + LineEnding + '  )' + LineEnding + 'end' + LineEnding);
    ms.Clear;
    ObjectTextToBinary(txt, ms);
    ms.Position := 0;
    ms.ReadComponent(b);
    AssertEquals('read back as rows', 2, b.RowCount);
    AssertEquals('their keys', 'Name', b.Keys[0]);
    AssertEquals('their values', 'Bob', b.Values['Name']);
    b.AddRow('X', '1');
    AssertEquals('and AddRow keeps them', 3, b.RowCount);
  finally
    txt.Free;
    ms.Free;
    b.Free;
    a.Free;
  end;
end;


type
  { #195: the end of an edit, and the keys and the click that reach a row's dialog and children. }
  TVLE195 = class(TTyValueListEditor)
  public
    procedure Press(AKey: Word; AShift: TShiftState);
    procedure ClickAt(X, Y: Integer);
    function EllipsisOf(AFlat: Integer): TRect;
  end;

  TVLE195Test = class(TTestCase)
  private
    FForm: TForm;
    FEd: TVLE195;
    FRow: TTyValueRow;
    FDialogs, FDone: Integer;
    procedure EditRow(Sender: TObject; ARow: TTyValueRow);
    procedure Done(Sender: TObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAltArrowsOpenAndCloseARow;
    procedure TestCtrlEnterRunsARowsDialog;
    procedure TestCtrlEnterInTheTextRunsTheDialog;
    procedure TestOneClickOnThePaintedEllipsisRunsTheDialog;
    procedure TestOnEditingDoneWaitsForTheEndOfAnEdit;
    procedure TestOnEditingDoneComesOnceAfterADialog;
  end;

var
  VLE195WidgetSet: Boolean = False;

procedure TVLE195.Press(AKey: Word; AShift: TShiftState);
begin
  KeyDown(AKey, AShift);
end;

procedure TVLE195.ClickAt(X, Y: Integer);
begin
  MouseDown(mbLeft, [], X, Y);
  MouseUp(mbLeft, [], X, Y);
end;

function TVLE195.EllipsisOf(AFlat: Integer): TRect;
begin
  Result := DialogButtonRect(AFlat);
end;

procedure TVLE195Test.EditRow(Sender: TObject; ARow: TTyValueRow);
begin
  Inc(FDialogs);
end;

procedure TVLE195Test.Done(Sender: TObject);
begin
  Inc(FDone);
end;

procedure TVLE195Test.SetUp;
begin
  if not VLE195WidgetSet then
  begin
    Forms.Application.Initialize;
    VLE195WidgetSet := True;
  end;
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(-4000, -4000, 400, 300);
  FEd := TVLE195.Create(FForm);
  FEd.Parent := FForm;
  FEd.SetBounds(0, 0, 300, 200);
  FRow := FEd.AddRow('Dialog', 'value');
  FRow.EditorKind := vekDialog;
  FEd.AddRow('Text', 'plain');
  FEd.OnEditRow := @EditRow;
  FEd.OnEditingDone := @Done;
  FDialogs := 0;
  FDone := 0;
  FForm.Visible := True;
  Forms.Application.ProcessMessages;
end;

procedure TVLE195Test.TearDown;
begin
  FreeAndNil(FForm);
end;

procedure TVLE195Test.TestAltArrowsOpenAndCloseARow;
var parent: TTyValueRow; before: Integer;
begin
  parent := FEd.AddRow('Parent', '');
  parent.AddChild('Child', 'c');
  before := FEd.Items.Count;
  FEd.ItemIndex := before - 1;
  FEd.SetExpanded(parent, False);
  FEd.ItemIndex := before - 1;
  before := FEd.Items.Count;
  FEd.Press(VK_RIGHT, [ssAlt]);
  AssertEquals('Alt+Right opens the row', before + 1, FEd.Items.Count);
  FEd.Press(VK_LEFT, [ssAlt]);
  AssertEquals('Alt+Left closes it', before, FEd.Items.Count);
end;

procedure TVLE195Test.TestCtrlEnterRunsARowsDialog;
begin
  FEd.ItemIndex := 0;
  FEd.Press(VK_RETURN, [ssCtrl]);
  AssertEquals('on a dialog row, Ctrl+Enter runs it', 1, FDialogs);
  FEd.ItemIndex := 1;
  FEd.Press(VK_RETURN, [ssCtrl]);
  AssertEquals('not on a text row', 1, FDialogs);
  FEd.ReadOnly := True;
  FEd.ItemIndex := 0;
  FEd.Press(VK_RETURN, [ssCtrl]);
  AssertEquals('nor on a read-only editor', 1, FDialogs);
end;

procedure TVLE195Test.TestCtrlEnterInTheTextRunsTheDialog;
var k: Word;
begin
  FEd.BeginEdit(0);
  AssertNotNull('setup: the inline editor', FEd.InlineEditor);
  k := VK_RETURN;
  FEd.InlineEditor.OnKeyDown(FEd.InlineEditor, k, [ssCtrl]);
  AssertEquals('Ctrl+Enter in the row''s text runs its dialog', 1, FDialogs);
  AssertEquals('and takes the key', 0, k);
end;

procedure TVLE195Test.TestOneClickOnThePaintedEllipsisRunsTheDialog;
var r: TRect;
begin
  r := FEd.EllipsisOf(0);
  AssertTrue('setup: a dialog row has the button', r.Right > r.Left);
  FEd.ClickAt((r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2);
  AssertEquals('one click on it runs the dialog', 1, FDialogs);
  AssertTrue('a text row has none', FEd.EllipsisOf(1).Right <= FEd.EllipsisOf(1).Left);
  FEd.ClickAt(r.Left - 20, (r.Top + r.Bottom) div 2);
  AssertEquals('elsewhere in the cell it opens the text', 1, FDialogs);
end;

procedure TVLE195Test.TestOnEditingDoneWaitsForTheEndOfAnEdit;
begin
  FEd.SetFocus;
  Forms.Application.ProcessMessages;
  AssertTrue('setup: the editor has the focus', FEd.Focused);
  FEd.BeginEdit(1);   // the focus goes to the inline editor: LCL's kill-focus calls EditingDone
  Forms.Application.ProcessMessages;
  AssertTrue('setup: and the inline editor took it', FEd.InlineEditor.Focused);
  AssertEquals('an edit starting announces nothing', 0, FDone);
  FEd.EndEdit(True);
  AssertEquals('its commit does, once', 1, FDone);
  FEd.BeginEdit(1);
  FEd.EndEdit(False);
  AssertEquals('Esc ends nothing the program has to hear about', 1, FDone);
end;

procedure TVLE195Test.TestOnEditingDoneComesOnceAfterADialog;
begin
  FEd.ItemIndex := 0;
  FEd.Press(VK_RETURN, [ssCtrl]);
  AssertEquals('setup: the dialog ran', 1, FDialogs);
  AssertEquals('it ends the edit, once', 1, FDone);
end;

initialization
  RegisterTest(TVLE195Test);
  RegisterTest(TValueListEditorTest);
end.
