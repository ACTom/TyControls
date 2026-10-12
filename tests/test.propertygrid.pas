unit test.propertygrid;
{$mode objfpc}{$H+}

{ The property grid (#65), part 1: an object's published properties of the simple types -- which
  rows appear, in what order, with which editor and text, and what the user's edits write back.

  The edits are driven the way the user makes them (click the value cell, type, Enter; F2; the
  dropped list; Space on a boolean) and every assertion that matters is on the INSPECTED OBJECT,
  not on the row: a grid whose rows look right but whose object never changed is the failure
  this suite exists for. }

interface

uses
  Classes, SysUtils, TypInfo, LCLType, Controls, Graphics, Forms, fpcunit, testregistry,
  tyControls.ListBox, tyControls.ValueListEditor, tyControls.PropertyGrid,
  test.propertygrid.fixtures;

type
  { The mapping: rows, order, filters, editors, display text. }
  TPropertyRowsTest = class(TTestCase)
  private
    FForm: TForm;
    FGrid: TPGGrid;
    FObj: TPGBasic;
    FFilterSeen: TPersistent;
    procedure HideZeta(Sender: TObject; AInstance: TPersistent; const APropName: string;
      var AShow: Boolean);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestRowsAreThePublishedPropertiesSortedByName;
    procedure TestDeclaredOrderFollowsTheClass;
    procedure TestEventsAreHiddenUntilTheFilterAsks;
    procedure TestTypeFilterDropsAKind;
    procedure TestHiddenPropertiesByName;
    procedure TestOnFilterPropertyHidesAndSeesTheInstance;
    procedure TestEachTypeGetsItsEditor;
    procedure TestEnumOptionsAreEveryName;
    procedure TestDisplayText;
    procedure TestFloatsUseADotWhateverTheLocale;
    procedure TestReadOnlyPropertyIsAReadOnlyRow;
    procedure TestEachRowPointsAtItsNode;
  end;

  { The write path, driven through the control. }
  TPropertyGridEditTest = class(TTestCase)
  private
    FForm: TForm;
    FGrid: TPGGrid;
    FObj: TPGBasic;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTypedIntegerIsWritten;
    procedure TestTheRowReadsBackWhatTheObjectHolds;
    procedure TestTypedFloatIsParsedWithADot;
    procedure TestTypedStringIsWritten;
    procedure TestTypedUnicodeStringIsWritten;
    procedure TestTypedCharIsWritten;
    procedure TestTwoCharactersAreRefusedAndNothingIsWritten;
    procedure TestOutOfRangeIsRefusedAndNothingIsWritten;
    procedure TestBigIntegersRoundTrip;
    procedure TestDateIsTypedInTheLocalFormat;
    procedure TestSpaceFlipsABoolean;
    procedure TestBooleanFromTheDropdown;
    procedure TestEnumFromTheDropdown;
    procedure TestColourFromTheDropdown;
    procedure TestColourFromTheDialog;
    procedure TestASetterThatMovesAnotherPropertyRefreshesItsRow;
    procedure TestASetterThatRaisesLeavesTheRowAlone;
    procedure TestReadOnlyRowDoesNotOpen;
  end;

implementation

{ ================================================================ the mapping }

procedure TPropertyRowsTest.SetUp;
begin
  FForm := NewHostForm;
  FGrid := TPGGrid.Create(FForm);
  FGrid.Parent := FForm;
  FGrid.SetBounds(0, 0, 440, 720);
  FObj := TPGBasic.Create;
  FFilterSeen := nil;
end;

procedure TPropertyRowsTest.TearDown;
begin
  FForm.Free;   // the grid first: it must not outlive... nothing it inspects is freed before it
  FObj.Free;
end;

procedure TPropertyRowsTest.HideZeta(Sender: TObject; AInstance: TPersistent;
  const APropName: string; var AShow: Boolean);
begin
  FFilterSeen := AInstance;
  if APropName = 'Zeta' then AShow := False;
end;

procedure TPropertyRowsTest.TestRowsAreThePublishedPropertiesSortedByName;
begin
  FGrid.SelectedObject := FObj;
  { CompareText order: 'beta' sorts among the B's, not after every capital (which is where the
    case-sensitive sort GetPropList offers would put it). OnPing is an event: hidden. }
  AssertEquals('every published non-event property, by name',
    'Alpha,AutoGrow,beta,Big,Boom,Day,Fixed,Flag,Huge,Kind,Letter,Money,Ratio,Small,Tint,Title,'
    + 'Unsigned,When,Wide,Width,Zeta',
    FGrid.RootKeys);
end;

procedure TPropertyRowsTest.TestDeclaredOrderFollowsTheClass;
begin
  FGrid.PropertyRows.Order := poDeclared;
  FGrid.SelectedObject := FObj;
  AssertEquals('the class''s own order',
    'Zeta,Alpha,beta,Ratio,Small,Money,When,Day,Big,Huge,Unsigned,Letter,Wide,Title,Flag,Kind,'
    + 'Tint,Fixed,AutoGrow,Width,Boom',
    FGrid.RootKeys);
end;

procedure TPropertyRowsTest.TestEventsAreHiddenUntilTheFilterAsks;
var h: TPGHandlers; r: TTyValueRow;
begin
  AssertFalse('tkMethod is not in the default filter', tkMethod in FGrid.PropertyRows.TypeFilter);
  FGrid.SelectedObject := FObj;
  AssertFalse('so OnPing is not listed', FGrid.HasRow('OnPing'));
  h := TPGHandlers.Create;
  try
    FObj.OnPing := @h.Ping;
    FGrid.PropertyRows.TypeFilter := FGrid.PropertyRows.TypeFilter + [tkMethod];
    FGrid.Rebuild;
    r := FGrid.RowAt('OnPing');
    AssertEquals('with tkMethod the handler shows by name', 'Ping', r.Value);
    AssertTrue('read-only', r.ReadOnly);
    FGrid.SelectedObject := nil;
  finally
    h.Free;
  end;
end;

procedure TPropertyRowsTest.TestTypeFilterDropsAKind;
begin
  FGrid.PropertyRows.TypeFilter := TyPropertyGridDefaultTypeFilter - [tkFloat];
  FGrid.SelectedObject := FObj;
  AssertFalse('no Ratio', FGrid.HasRow('Ratio'));
  AssertFalse('no When (a TDateTime is a float)', FGrid.HasRow('When'));
  AssertTrue('integers stay', FGrid.HasRow('Zeta'));
end;

procedure TPropertyRowsTest.TestHiddenPropertiesByName;
begin
  FGrid.PropertyRows.HiddenProperties.Add('alpha');   // case-insensitive
  FGrid.SelectedObject := FObj;
  AssertFalse('hidden', FGrid.HasRow('Alpha'));
  AssertTrue('the rest stay', FGrid.HasRow('AutoGrow'));
end;

procedure TPropertyRowsTest.TestOnFilterPropertyHidesAndSeesTheInstance;
begin
  FGrid.PropertyRows.OnFilterProperty := @HideZeta;
  FGrid.SelectedObject := FObj;
  AssertFalse('the handler hid Zeta', FGrid.HasRow('Zeta'));
  AssertTrue('and nothing else', FGrid.HasRow('Alpha'));
  AssertSame('the handler is told whose property it is', FObj, FFilterSeen);
end;

procedure TPropertyRowsTest.TestEachTypeGetsItsEditor;

  procedure Check(const AName: string; AKind: TTyValueEditorKind);
  begin
    AssertEquals(AName, GetEnumName(TypeInfo(TTyValueEditorKind), Ord(AKind)),
      GetEnumName(TypeInfo(TTyValueEditorKind), Ord(FGrid.RowAt(AName).EditorKind)));
  end;

begin
  FGrid.SelectedObject := FObj;
  Check('Zeta', vekInteger);
  Check('Unsigned', vekInteger);
  Check('Big', vekInteger);
  Check('Huge', vekInteger);
  Check('Ratio', vekFloat);
  Check('Small', vekFloat);
  Check('Money', vekFloat);
  Check('When', vekText);       // a date is typed as text in the local format
  Check('Alpha', vekText);
  Check('Title', vekText);
  Check('Letter', vekText);
  Check('Flag', vekBoolean);
  Check('Kind', vekEnum);
  Check('Tint', vekColor);
end;

procedure TPropertyRowsTest.TestEnumOptionsAreEveryName;
begin
  FGrid.SelectedObject := FObj;
  AssertEquals('every name of the enumeration, in order',
    'pgkOne' + LineEnding + 'pgkTwo' + LineEnding + 'pgkThree', FGrid.RowAt('Kind').EnumValues);
end;

procedure TPropertyRowsTest.TestDisplayText;
begin
  FGrid.SelectedObject := FObj;
  AssertEquals('a colour by its name, not as a number', 'clRed', FGrid.RowAt('Tint').Value);
  AssertEquals('enum', 'pgkTwo', FGrid.RowAt('Kind').Value);
  AssertEquals('boolean', 'False', FGrid.RowAt('Flag').Value);
  AssertEquals('string', 'start', FGrid.RowAt('Alpha').Value);
  AssertEquals('a Cardinal above MaxInt is not negative', '4000000000', FGrid.RowAt('Unsigned').Value);
  AssertEquals('Int64', '-5000000000', FGrid.RowAt('Big').Value);
  AssertEquals('QWord above High(Int64)', '18000000000000000000', FGrid.RowAt('Huge').Value);
  AssertEquals('char', 'A', FGrid.RowAt('Letter').Value);
  AssertEquals('wide char, as UTF-8', '中', FGrid.RowAt('Wide').Value);
  AssertEquals('a Single shows its own precision, not 0.100000001490116', '0.1',
    FGrid.RowAt('Small').Value);
  AssertEquals('currency', '12.25', FGrid.RowAt('Money').Value);
  AssertEquals('a date-time in the local format', DateTimeToStr(FObj.When), FGrid.RowAt('When').Value);
  AssertEquals('a date in the local format', DateToStr(FObj.Day), FGrid.RowAt('Day').Value);
end;

procedure TPropertyRowsTest.TestFloatsUseADotWhateverTheLocale;
var saved: TFormatSettings;
begin
  saved := DefaultFormatSettings;
  try
    DefaultFormatSettings.DecimalSeparator := ',';
    DefaultFormatSettings.ThousandSeparator := '.';
    FGrid.SelectedObject := FObj;
    AssertEquals('1.5 with a comma locale', '1.5', FGrid.RowAt('Ratio').Value);
  finally
    DefaultFormatSettings := saved;
  end;
end;

procedure TPropertyRowsTest.TestReadOnlyPropertyIsAReadOnlyRow;
begin
  FGrid.SelectedObject := FObj;
  AssertTrue('no setter: read-only', FGrid.RowAt('Fixed').ReadOnly);
  AssertEquals('and still shown', '17', FGrid.RowAt('Fixed').Value);
  AssertFalse('a property with a setter is not', FGrid.RowAt('Zeta').ReadOnly);
end;

procedure TPropertyRowsTest.TestEachRowPointsAtItsNode;
var r: TTyValueRow; n: TTyPropertyNode;
begin
  FGrid.SelectedObject := FObj;
  r := FGrid.RowAt('Ratio');
  n := FGrid.PropertyRows.NodeOf(r);
  AssertNotNull('the row''s Data is a node', n);
  AssertTrue('Data is that node', r.Data = Pointer(n));
  AssertEquals('of the property', 'Ratio', n.PropInfo^.Name);
  AssertSame('on the inspected object', FObj, n.Instance);
  AssertSame('and the node knows its row', r, n.Row);
end;

{ ================================================================ the write path }

procedure TPropertyGridEditTest.SetUp;
begin
  FForm := NewHostForm;
  FGrid := TPGGrid.Create(FForm);
  FGrid.Parent := FForm;
  FGrid.SetBounds(0, 0, 440, 720);
  FObj := TPGBasic.Create;
  FForm.Show;
  FGrid.SelectedObject := FObj;
end;

procedure TPropertyGridEditTest.TearDown;
begin
  FForm.Free;
  FObj.Free;
end;

procedure TPropertyGridEditTest.TestTypedIntegerIsWritten;
begin
  FGrid.TypeInto(FGrid.RowAt('Zeta'), '42');
  AssertEquals('the object took it', 42, FObj.Zeta);
  AssertEquals('the row shows it', '42', FGrid.RowAt('Zeta').Value);
end;

procedure TPropertyGridEditTest.TestTheRowReadsBackWhatTheObjectHolds;
begin
  FGrid.TypeInto(FGrid.RowAt('Zeta'), '007');
  AssertEquals('the object holds 7', 7, FObj.Zeta);
  AssertEquals('and the row says so, not what was typed', '7', FGrid.RowAt('Zeta').Value);
end;

procedure TPropertyGridEditTest.TestTypedFloatIsParsedWithADot;
var saved: TFormatSettings;
begin
  saved := DefaultFormatSettings;
  try
    DefaultFormatSettings.DecimalSeparator := ',';   // a German desktop
    DefaultFormatSettings.ThousandSeparator := '.';
    FGrid.TypeInto(FGrid.RowAt('Ratio'), '2.25');
    AssertEquals('2.25, not 225 and not an error', 2.25, FObj.Ratio, 1e-12);
    AssertEquals('row', '2.25', FGrid.RowAt('Ratio').Value);
  finally
    DefaultFormatSettings := saved;
  end;
end;

procedure TPropertyGridEditTest.TestTypedStringIsWritten;
begin
  FGrid.Select(FGrid.RowAt('Alpha'));
  FGrid.Press(VK_F2);                                // the keyboard way in
  AssertTrue('F2 opened the cell', FGrid.EditingRow >= 0);
  FGrid.Editor.TypeText('hello');
  FGrid.Editor.PressKey(VK_RETURN);
  AssertEquals('the object took it', 'hello', FObj.Alpha);
end;

procedure TPropertyGridEditTest.TestTypedUnicodeStringIsWritten;
begin
  FGrid.TypeInto(FGrid.RowAt('Title'), 'abc');
  AssertEquals('a UnicodeString property', UnicodeString('abc'), FObj.Title);
end;

procedure TPropertyGridEditTest.TestTypedCharIsWritten;
begin
  FGrid.TypeInto(FGrid.RowAt('Letter'), 'Z');
  AssertEquals('char', 'Z', FObj.Letter);
  FGrid.TypeInto(FGrid.RowAt('Letter'), '#9');
  AssertEquals('#n spelling', #9, FObj.Letter);
  AssertEquals('and a control character reads back as #n', '#9', FGrid.RowAt('Letter').Value);
end;

procedure TPropertyGridEditTest.TestTwoCharactersAreRefusedAndNothingIsWritten;
var raised: Boolean;
begin
  raised := False;
  try
    FGrid.TypeInto(FGrid.RowAt('Letter'), 'ZZ');
  except
    on E: EConvertError do raised := True;
  end;
  AssertTrue('refused with EConvertError (no OnPropertyError handler: it propagates)', raised);
  AssertEquals('the object is untouched', 'A', FObj.Letter);
  AssertEquals('and so is the row', 'A', FGrid.RowAt('Letter').Value);
end;

procedure TPropertyGridEditTest.TestOutOfRangeIsRefusedAndNothingIsWritten;
var raised: Boolean;
begin
  raised := False;
  try
    FGrid.TypeInto(FGrid.RowAt('Unsigned'), '-1');
  except
    on E: ERangeError do raised := True;
  end;
  AssertTrue('a Cardinal refuses -1', raised);
  AssertEquals('untouched', 4000000000, FObj.Unsigned);
  AssertEquals('row untouched', '4000000000', FGrid.RowAt('Unsigned').Value);
end;

procedure TPropertyGridEditTest.TestBigIntegersRoundTrip;
begin
  FGrid.TypeInto(FGrid.RowAt('Big'), '-9000000000');
  AssertEquals('Int64', -9000000000, FObj.Big);
  FGrid.TypeInto(FGrid.RowAt('Huge'), '18446744073709551615');
  AssertTrue('QWord max', FObj.Huge = High(QWord));
  FGrid.TypeInto(FGrid.RowAt('Unsigned'), '4294967295');
  AssertEquals('Cardinal max', 4294967295, FObj.Unsigned);
end;

procedure TPropertyGridEditTest.TestDateIsTypedInTheLocalFormat;
var want: TDateTime;
begin
  want := EncodeDate(2024, 2, 29) + EncodeTime(13, 5, 0, 0);
  FGrid.TypeInto(FGrid.RowAt('When'), DateTimeToStr(want));
  AssertEquals('the date-time landed', DateTimeToStr(want), DateTimeToStr(FObj.When));
  FGrid.TypeInto(FGrid.RowAt('Day'), DateToStr(EncodeDate(2025, 12, 31)));
  AssertEquals('the date landed', DateToStr(EncodeDate(2025, 12, 31)), DateToStr(FObj.Day));
end;

procedure TPropertyGridEditTest.TestSpaceFlipsABoolean;
begin
  FGrid.Select(FGrid.RowAt('Flag'));
  FGrid.Press(VK_SPACE);
  AssertTrue('Space turned it on', FObj.Flag);
  AssertEquals('row', 'True', FGrid.RowAt('Flag').Value);
  FGrid.Press(VK_SPACE);
  AssertFalse('and off again', FObj.Flag);
end;

procedure TPropertyGridEditTest.TestBooleanFromTheDropdown;
begin
  FGrid.PickFromDropdown(FGrid.RowAt('Flag'), 'True');
  AssertTrue('picked True', FObj.Flag);
end;

procedure TPropertyGridEditTest.TestEnumFromTheDropdown;
begin
  FGrid.PickFromDropdown(FGrid.RowAt('Kind'), 'pgkThree');
  AssertTrue('picked pgkThree', FObj.Kind = pgkThree);
  AssertEquals('row', 'pgkThree', FGrid.RowAt('Kind').Value);
end;

procedure TPropertyGridEditTest.TestColourFromTheDropdown;
var lst: TTyListBox; i: Integer;
begin
  FGrid.ClickValue(FGrid.RowAt('Tint'));
  lst := FGrid.Dropped;
  AssertNotNull('the swatches dropped', lst);
  i := lst.Items.IndexOf('Blue');
  if i < 0 then i := 0;
  lst.SelectItem(i);
  AssertTrue('the object''s colour changed', FObj.Tint <> clRed);
  AssertEquals('and the row names it', ColorToString(FObj.Tint), FGrid.RowAt('Tint').Value);
end;

procedure TPropertyGridEditTest.TestColourFromTheDialog;
var lst: TTyListBox;
begin
  FGrid.ColorAnswer := TColor($123456);
  FGrid.ClickValue(FGrid.RowAt('Tint'));
  lst := FGrid.Dropped;
  AssertNotNull('dropped', lst);
  lst.SelectItem(lst.Items.Count - 1);        // "more…"
  Forms.Application.ProcessMessages;          // the dialog runs on a queued call
  AssertEquals('the dialog''s colour', $123456, FObj.Tint);
  AssertEquals('row', ColorToString(TColor($123456)), FGrid.RowAt('Tint').Value);
end;

procedure TPropertyGridEditTest.TestASetterThatMovesAnotherPropertyRefreshesItsRow;
begin
  AssertEquals('before', '10', FGrid.RowAt('Width').Value);
  FGrid.Select(FGrid.RowAt('AutoGrow'));
  FGrid.Press(VK_SPACE);
  AssertTrue('AutoGrow on', FObj.AutoGrow);
  AssertEquals('its setter moved Width', 999, FObj.Width);
  AssertEquals('and the Width row was re-read', '999', FGrid.RowAt('Width').Value);
end;

procedure TPropertyGridEditTest.TestASetterThatRaisesLeavesTheRowAlone;
var raised: Boolean;
begin
  raised := False;
  try
    FGrid.TypeInto(FGrid.RowAt('Boom'), '5');
  except
    on E: Exception do raised := E.Message = 'boom';
  end;
  AssertEquals('the setter ran', 1, FObj.BoomTries);
  AssertTrue('its exception reached the caller', raised);
  AssertEquals('the row keeps the old value', '0', FGrid.RowAt('Boom').Value);
  AssertEquals('the editor is closed', -1, FGrid.EditingRow);
end;

procedure TPropertyGridEditTest.TestReadOnlyRowDoesNotOpen;
var raised: Boolean;
begin
  FGrid.ClickValue(FGrid.RowAt('Fixed'));
  AssertEquals('a click opens nothing', -1, FGrid.EditingRow);
  FGrid.Select(FGrid.RowAt('Fixed'));
  FGrid.Press(VK_F2);
  AssertEquals('nor does F2', -1, FGrid.EditingRow);
  raised := False;
  try
    FGrid.SetRowValue(FGrid.RowAt('Fixed'), '3');
  except
    on E: EPropertyError do raised := True;
  end;
  AssertTrue('through the API it is refused', raised);
  AssertEquals('the object is untouched', 17, FObj.Fixed);
  AssertEquals('and so is the row', '17', FGrid.RowAt('Fixed').Value);
end;

initialization
  RegisterTest(TPropertyRowsTest);
  RegisterTest(TPropertyGridEditTest);
end.
