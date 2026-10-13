unit test.propertygrid.control;
{$mode objfpc}{$H+}

{ The property grid (#65), part 3: the control around the mapping -- the selection (SelectedObject,
  SelectedComponent, the free notification, design time), the write events (OnPropertyChanging's
  veto, OnPropertyChanged, OnPropertyError), the extension points (OnGetPropertyRow,
  OnEditProperty, PropertyAt, the component-reference candidates), Refresh, ExpandedProperties,
  and the published settings rebuilding at once.

  As in parts 1 and 2, edits go in the way the user makes them (a click, typing, Enter, Space,
  the dropped list, the '…'), and the verdicts are read off the inspected object. }

interface

uses
  Classes, SysUtils, TypInfo, LCLType, Controls, Graphics, Forms, fpcunit, testregistry,
  tyControls.ListBox, tyControls.ValueListEditor, tyControls.PropertyGrid, tyControls.Button,
  tyControls.Edit, tyControls.StrConsts, test.propertygrid.fixtures, test.danglingrefs;

type
  TPropertyGridControlTest = class(TTestCase)
  private
    FForm: TForm;
    FGrid: TPGGrid;
    FObj: TPGBasic;
    FHolder: TPGHolder;
    { what the handlers saw }
    FSeenInstance: TPersistent;
    FSeenName, FSeenValue: string;
    FSeenError: string;
    FChanging, FChanged, FErrors, FEdits, FRowCalls: Integer;
    FChangedName: string;
    FChangedInstance: TPersistent;
    FAllow: Boolean;
    FHandle: Boolean;
    procedure Changing(Sender: TObject; AInstance: TPersistent; const APropName,
      ANewValue: string; var AAllow: Boolean);
    procedure Changed(Sender: TObject; AInstance: TPersistent; const APropName: string);
    procedure Failed(Sender: TObject; AInstance: TPersistent; const APropName: string;
      E: Exception);
    procedure ShapeRow(Sender: TObject; AInstance: TPersistent; APropInfo: PPropInfo;
      ARow: TTyValueRow);
    procedure EditProp(Sender: TObject; ARow: TTyValueRow; AInstance: TPersistent;
      const APropName: string; var AHandled: Boolean);
    procedure HideAlpha(Sender: TObject; AInstance: TPersistent; const APropName: string;
      var AShow: Boolean);
    function Lines(const AText: string): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { selection }
    procedure TestSelectedComponentIsTheSelectionWhenItIsAComponent;
    procedure TestFreeingTheInspectedComponentClearsTheGrid;
    procedure TestFreeingTheFormOfTheInspectedControlClearsTheGrid;
    procedure TestAtDesignTimeTheRowsAreListedButNothingIsWritten;
    procedure TestTheSelectionAndTheSettingsComeBackFromAFormFile;
    { write events }
    procedure TestOnPropertyChangingCanRefuse;
    procedure TestOnPropertyChangedFollowsEachWrite;
    procedure TestASetElementIsAnnouncedAsTheWholeSet;
    procedure TestAFontRowIsAnnouncedOnTheFont;
    procedure TestOnPropertyErrorTakesTheExceptionAndTheRowKeepsItsValue;
    procedure TestAValueThatDoesNotParseGoesToOnPropertyError;
    procedure TestAPickThatRaisesStillClosesTheList;
    { extension points }
    procedure TestOnGetPropertyRowShapesTheRow;
    procedure TestOnEditPropertyCanTakeTheStringsRow;
    procedure TestAnUnhandledRowFallsBackToTheTextDialog;
    procedure TestOnEditPropertyReachesAnyDialogRow;
    procedure TestPropertyAt;
    procedure TestAFormListsTheControlsOnIt;
    procedure TestTheRootItselfIsACandidate;
    { refresh, expansion, settings }
    procedure TestRefreshReReadsAndKeepsTheCurrentRowAndExpansion;
    procedure TestRefreshRebuildsWhenACollectionGrows;
    procedure TestExpansionFollowsTheSelectionToTheNextObject;
    procedure TestAddingAPathExpandsTheRow;
    procedure TestPropertyOrderRebuildsAtOnce;
    procedure TestTypeFilterHiddenPropertiesAndTheFilterEventRebuildAtOnce;
    procedure TestKeyOptionsStayEmpty;
  end;

implementation

type
  { A form with the grid and a button as published fields, for the round trip through a stream. }
  TPGHostForm = class(TForm)
  published
    Grid: TTyPropertyGrid;
    Button1: TTyButton;
  end;

procedure TPropertyGridControlTest.SetUp;
begin
  FForm := NewHostForm;
  FGrid := TPGGrid.Create(FForm);
  FGrid.Parent := FForm;
  FGrid.SetBounds(0, 0, 440, 720);
  FObj := TPGBasic.Create;
  FHolder := TPGHolder.Create;
  FForm.Show;
  FGrid.SelectedObject := FObj;
  FSeenInstance := nil;
  FSeenName := '';
  FSeenValue := '';
  FSeenError := '';
  FChanging := 0;
  FChanged := 0;
  FErrors := 0;
  FEdits := 0;
  FRowCalls := 0;
  FChangedName := '';
  FChangedInstance := nil;
  FAllow := True;
  FHandle := False;
end;

procedure TPropertyGridControlTest.TearDown;
begin
  FForm.Free;
  FObj.Free;
  FHolder.Free;
end;

procedure TPropertyGridControlTest.Changing(Sender: TObject; AInstance: TPersistent;
  const APropName, ANewValue: string; var AAllow: Boolean);
begin
  Inc(FChanging);
  FSeenInstance := AInstance;
  FSeenName := APropName;
  FSeenValue := ANewValue;
  AAllow := FAllow;
end;

procedure TPropertyGridControlTest.Changed(Sender: TObject; AInstance: TPersistent;
  const APropName: string);
begin
  Inc(FChanged);
  FChangedInstance := AInstance;
  FChangedName := APropName;
end;

procedure TPropertyGridControlTest.Failed(Sender: TObject; AInstance: TPersistent;
  const APropName: string; E: Exception);
begin
  Inc(FErrors);
  FSeenInstance := AInstance;
  FSeenName := APropName;
  FSeenError := E.ClassName + ': ' + E.Message;
end;

procedure TPropertyGridControlTest.ShapeRow(Sender: TObject; AInstance: TPersistent;
  APropInfo: PPropInfo; ARow: TTyValueRow);
begin
  Inc(FRowCalls);
  if APropInfo^.Name = 'Zeta' then FSeenInstance := AInstance;
  if APropInfo^.Name = 'Alpha' then ARow.ReadOnly := True;
  if APropInfo^.Name = 'Title' then ARow.EditorKind := vekDialog;
  if APropInfo^.Name = 'Kind' then ARow.EnumValues := 'pgkOne' + LineEnding + 'pgkThree';
end;

procedure TPropertyGridControlTest.EditProp(Sender: TObject; ARow: TTyValueRow;
  AInstance: TPersistent; const APropName: string; var AHandled: Boolean);
begin
  Inc(FEdits);
  FSeenInstance := AInstance;
  FSeenName := APropName;
  if not FHandle then Exit;
  if AInstance is TPGHolder then TPGHolder(AInstance).Notes.Text := 'from the handler';
  if AInstance is TPGBasic then TPGBasic(AInstance).Title := 'picked';
  AHandled := True;
end;

procedure TPropertyGridControlTest.HideAlpha(Sender: TObject; AInstance: TPersistent;
  const APropName: string; var AShow: Boolean);
begin
  if APropName = 'Alpha' then AShow := False;
end;

function TPropertyGridControlTest.Lines(const AText: string): string;
begin
  Result := StringReplace(Trim(AText), LineEnding, ',', [rfReplaceAll]);
end;

{ ================================================================ selection }

procedure TPropertyGridControlTest.TestSelectedComponentIsTheSelectionWhenItIsAComponent;
var b: TTyButton;
begin
  AssertNull('a plain TPersistent is not a component', FGrid.SelectedComponent);
  b := TTyButton.Create(FForm);
  b.Caption := 'probe';
  FGrid.SelectedComponent := b;
  AssertSame('the same field', b, FGrid.SelectedObject);
  AssertSame('read back', b, FGrid.SelectedComponent);
  AssertEquals('and its rows are listed', 'probe', FGrid.RowAt('Caption').Value);
  FGrid.SelectedComponent := nil;
  AssertNull('cleared', FGrid.SelectedObject);
  AssertEquals('no rows', 0, FGrid.RowCount);
end;

{ The component is freed while the grid shows it. Every freed block is poisoned in between, so a
  read through what the grid kept would meet $7F7F... -- and the grid must have kept nothing. }
procedure TPropertyGridControlTest.TestFreeingTheInspectedComponentClearsTheGrid;
var host: TPGHostComp;
begin
  host := TPGHostComp.Create(nil);
  host.Sub.Level := 3;
  FGrid.SelectedComponent := host;
  FGrid.ExpandedProperties.Add('Sub');
  AssertEquals('listed', '3', FGrid.RowAt('Sub.Level').Value);
  BeginPoison;
  try
    host.Free;
    FGrid.Refresh;
    FGrid.Rebuild;
    FGrid.Repaint;
  finally
    EndPoison;
  end;
  AssertNull('the selection let go', FGrid.SelectedObject);
  AssertNull('SelectedComponent too', FGrid.SelectedComponent);
  AssertEquals('and the rows went with it', 0, FGrid.RowCount);
  AssertTrue('the expanded paths are kept for the next object',
    FGrid.ExpandedProperties.IndexOf('Sub') >= 0);
end;

procedure TPropertyGridControlTest.TestFreeingTheFormOfTheInspectedControlClearsTheGrid;
var other: TForm; b: TTyButton;
begin
  other := TForm.CreateNew(nil);
  b := TTyButton.Create(other);
  b.Parent := other;
  FGrid.SelectedComponent := b;
  AssertTrue('listed', FGrid.RowCount > 0);
  BeginPoison;
  try
    other.Free;   // the button goes with its form, which does not know the grid
    FGrid.Refresh;
  finally
    EndPoison;
  end;
  AssertNull('the selection let go', FGrid.SelectedObject);
  AssertEquals('no rows', 0, FGrid.RowCount);
end;

procedure TPropertyGridControlTest.TestAtDesignTimeTheRowsAreListedButNothingIsWritten;
begin
  FGrid.DesignMode(True);
  try
    FGrid.SelectedObject := nil;
    FGrid.SelectedObject := FObj;
    AssertEquals('listed at design time', '0', FGrid.RowAt('Zeta').Value);
    FGrid.OnPropertyChanging := @Changing;
    FGrid.SetRowValue(FGrid.RowAt('Zeta'), '42');
    AssertEquals('not written', 0, FObj.Zeta);
    AssertEquals('the row did not move either', '0', FGrid.RowAt('Zeta').Value);
    AssertEquals('nobody was asked', 0, FChanging);
    FGrid.Select(FGrid.RowAt('Flag'));
    FGrid.Press(VK_SPACE);
    AssertFalse('Space writes nothing', FObj.Flag);
  finally
    FGrid.DesignMode(False);
  end;
  FGrid.SetRowValue(FGrid.RowAt('Zeta'), '42');
  AssertEquals('and at run time the same call writes', 42, FObj.Zeta);
end;

procedure TPropertyGridControlTest.TestTheSelectionAndTheSettingsComeBackFromAFormFile;
var
  src, dst: TPGHostForm;
  ms: TMemoryStream;
  g: TTyPropertyGrid;
begin
  RegisterClasses([TTyPropertyGrid, TTyButton]);
  src := TPGHostForm.CreateNew(nil);
  dst := TPGHostForm.CreateNew(nil);
  ms := TMemoryStream.Create;
  try
    src.Name := 'PGHostForm1';
    src.Button1 := TTyButton.Create(src);
    src.Button1.Name := 'Button1';
    src.Button1.Parent := src;
    src.Button1.Caption := 'streamed';
    src.Grid := TTyPropertyGrid.Create(src);
    src.Grid.Name := 'Grid';
    src.Grid.Parent := src;
    src.Grid.PropertyOrder := poDeclared;
    src.Grid.HiddenProperties.Add('Tag');
    src.Grid.ExpandedProperties.Add('Font');
    src.Grid.SelectedComponent := src.Button1;
    ms.WriteComponent(src);
    ms.Position := 0;
    ms.ReadComponent(dst);

    g := dst.Grid;
    AssertNotNull('the grid came back', g);
    AssertSame('pointing at the button of the form it came back on', dst.Button1,
      g.SelectedComponent);
    AssertTrue('built once loading was over', g.RowCount > 0);
    AssertEquals('declared order: the first row is TComponent''s Name', 'Name', g.Row(0).Key);
    AssertTrue('Tag hidden', g.HiddenProperties.IndexOf('Tag') >= 0);
    AssertTrue('Font expanded', g.ExpandedProperties.IndexOf('Font') >= 0);
  finally
    ms.Free;
    dst.Free;
    src.Free;
  end;
end;

{ ================================================================ write events }

procedure TPropertyGridControlTest.TestOnPropertyChangingCanRefuse;
begin
  FGrid.OnPropertyChanging := @Changing;
  FGrid.OnPropertyChanged := @Changed;
  FAllow := False;
  FGrid.TypeInto(FGrid.RowAt('Zeta'), '42');
  AssertEquals('asked once', 1, FChanging);
  AssertSame('about the object', FObj, FSeenInstance);
  AssertEquals('and the property', 'Zeta', FSeenName);
  AssertEquals('with the new value', '42', FSeenValue);
  AssertEquals('refused: not written', 0, FObj.Zeta);
  AssertEquals('the row keeps the old value', '0', FGrid.RowAt('Zeta').Value);
  AssertEquals('nothing changed, nothing announced', 0, FChanged);
  FAllow := True;
  FGrid.TypeInto(FGrid.RowAt('Zeta'), '42');
  AssertEquals('allowed: written', 42, FObj.Zeta);
end;

procedure TPropertyGridControlTest.TestOnPropertyChangedFollowsEachWrite;
begin
  FGrid.OnPropertyChanged := @Changed;
  FGrid.TypeInto(FGrid.RowAt('Zeta'), '42');
  AssertEquals('once', 1, FChanged);
  AssertSame('the object', FObj, FChangedInstance);
  AssertEquals('the property', 'Zeta', FChangedName);
  FGrid.Select(FGrid.RowAt('Flag'));
  FGrid.Press(VK_SPACE);
  AssertEquals('Space is a write too', 2, FChanged);
  AssertEquals('Flag', 'Flag', FChangedName);
  FGrid.PickFromDropdown(FGrid.RowAt('Kind'), 'pgkThree');
  AssertEquals('so is a pick', 3, FChanged);
  AssertEquals('Kind', 'Kind', FChangedName);
end;

procedure TPropertyGridControlTest.TestASetElementIsAnnouncedAsTheWholeSet;
begin
  FGrid.SelectedObject := FHolder;
  FGrid.OnPropertyChanging := @Changing;
  FGrid.OnPropertyChanged := @Changed;
  FGrid.Select(FGrid.RowAt('Flags.pfB'));
  FGrid.Press(VK_SPACE);
  AssertSame('the set''s object', FHolder, FSeenInstance);
  AssertEquals('the set, not the element', 'Flags', FSeenName);
  AssertEquals('the set as it will read', '[pfA,pfB,pfC]', FSeenValue);
  AssertEquals('then Changed', 'Flags', FChangedName);
  FGrid.SelectedObject := nil;
end;

procedure TPropertyGridControlTest.TestAFontRowIsAnnouncedOnTheFont;
var b: TTyButton;
begin
  b := TTyButton.Create(FForm);
  b.Font.Size := 9;
  FGrid.SelectedObject := b;
  FGrid.OnPropertyChanging := @Changing;
  FGrid.OnPropertyChanged := @Changed;
  FGrid.TypeInto(FGrid.RowAt('Font.Size'), '12');
  AssertSame('the font is the object that has Size', b.Font, FSeenInstance);
  AssertEquals('Size', 'Size', FSeenName);
  AssertEquals('12', '12', FSeenValue);
  AssertSame('Changed names the same font', b.Font, FChangedInstance);
  AssertEquals('written', 12, b.Font.Size);
end;

procedure TPropertyGridControlTest.TestOnPropertyErrorTakesTheExceptionAndTheRowKeepsItsValue;
begin
  FGrid.OnPropertyError := @Failed;
  FGrid.OnPropertyChanged := @Changed;
  FGrid.TypeInto(FGrid.RowAt('Boom'), '5');   // raises nothing: the handler has it
  AssertEquals('the setter ran', 1, FObj.BoomTries);
  AssertEquals('the handler had it once', 1, FErrors);
  AssertSame('on the object', FObj, FSeenInstance);
  AssertEquals('for the property', 'Boom', FSeenName);
  AssertEquals('the setter''s own exception', 'Exception: boom', FSeenError);
  AssertEquals('the row keeps the old value', '0', FGrid.RowAt('Boom').Value);
  AssertEquals('nothing announced as changed', 0, FChanged);
  AssertEquals('the editor is closed', -1, FGrid.EditingRow);
end;

procedure TPropertyGridControlTest.TestAValueThatDoesNotParseGoesToOnPropertyError;
begin
  FGrid.OnPropertyError := @Failed;
  FGrid.TypeInto(FGrid.RowAt('Letter'), 'ZZ');
  AssertEquals('reported', 1, FErrors);
  AssertEquals('as a conversion error', 'EConvertError', Copy(FSeenError, 1, Length('EConvertError')));
  AssertEquals('untouched', 'A', FObj.Letter);
  AssertEquals('row untouched', 'A', FGrid.RowAt('Letter').Value);
end;

procedure TPropertyGridControlTest.TestAPickThatRaisesStillClosesTheList;
var trap: TPGTrap; raised: Boolean;
begin
  trap := TPGTrap.Create;
  try
    FGrid.SelectedObject := trap;
    raised := False;
    try
      FGrid.PickFromDropdown(FGrid.RowAt('Mode'), 'pgkThree');
    except
      on E: Exception do raised := E.Message = 'no mode change';
    end;
    AssertTrue('the setter''s exception reached the caller', raised);
    AssertEquals('the setter ran', 1, trap.ModeTries);
    AssertNull('the list is closed', FGrid.Dropped);
    AssertEquals('and nothing is being edited', -1, FGrid.EditingRow);
    AssertEquals('the row keeps the old value', 'pgkOne', FGrid.RowAt('Mode').Value);
    FGrid.SelectedObject := nil;
  finally
    trap.Free;
  end;
end;

{ ================================================================ extension points }

procedure TPropertyGridControlTest.TestOnGetPropertyRowShapesTheRow;
begin
  FGrid.OnGetPropertyRow := @ShapeRow;
  FGrid.Rebuild;
  AssertEquals('once per property row', 21, FRowCalls);
  AssertSame('told whose property it is', FObj, FSeenInstance);
  AssertTrue('Alpha made read-only', FGrid.RowAt('Alpha').ReadOnly);
  FGrid.ClickValue(FGrid.RowAt('Alpha'));
  AssertEquals('so a click opens nothing', -1, FGrid.EditingRow);
  AssertEquals('Kind offers what the handler left', 'pgkOne,pgkThree',
    Lines(FGrid.RowAt('Kind').EnumValues));
end;

procedure TPropertyGridControlTest.TestOnEditPropertyCanTakeTheStringsRow;
begin
  FGrid.SelectedObject := FHolder;
  FGrid.OnEditProperty := @EditProp;
  FHandle := True;
  FGrid.StringsAccept := True;
  FGrid.StringsAnswer := 'from the dialog';
  FGrid.ClickValue(FGrid.RowAt('Notes'));
  FGrid.Editor.ClickEllipsis;
  AssertEquals('the handler was asked', 1, FEdits);
  AssertSame('about the holder', FHolder, FSeenInstance);
  AssertEquals('and Notes', 'Notes', FSeenName);
  AssertEquals('handled: the built-in dialog stays shut', 0, FGrid.StringsDialogs);
  AssertEquals('what the handler wrote', 'from the handler', Trim(FHolder.Notes.Text));
  FGrid.SelectedObject := nil;
end;

procedure TPropertyGridControlTest.TestAnUnhandledRowFallsBackToTheTextDialog;
begin
  FGrid.SelectedObject := FHolder;
  FGrid.OnEditProperty := @EditProp;
  FHandle := False;
  FGrid.StringsAccept := True;
  FGrid.StringsAnswer := 'from the dialog';
  FGrid.ClickValue(FGrid.RowAt('Notes'));
  FGrid.Editor.ClickEllipsis;
  AssertEquals('asked first', 1, FEdits);
  AssertEquals('then the built-in dialog', 1, FGrid.StringsDialogs);
  AssertEquals('which wrote', 'from the dialog', Trim(FHolder.Notes.Text));
  FGrid.SelectedObject := nil;
end;

procedure TPropertyGridControlTest.TestOnEditPropertyReachesAnyDialogRow;
begin
  FGrid.OnGetPropertyRow := @ShapeRow;   // Title becomes a dialog row
  FGrid.OnEditProperty := @EditProp;
  FHandle := True;
  FGrid.Rebuild;
  AssertTrue('a dialog row', FGrid.RowAt('Title').EditorKind = vekDialog);
  FGrid.ClickValue(FGrid.RowAt('Title'));
  FGrid.Editor.ClickEllipsis;
  AssertEquals('asked', 1, FEdits);
  AssertEquals('about Title', 'Title', FSeenName);
  AssertEquals('the handler wrote the property', UnicodeString('picked'), FObj.Title);
  AssertEquals('and the row was re-read from it', 'picked', FGrid.RowAt('Title').Value);
end;

procedure TPropertyGridControlTest.TestPropertyAt;
var inst: TPersistent; nm: string; b: TTyButton;
begin
  AssertTrue('a plain row', FGrid.PropertyAt(FGrid.RowAt('Zeta'), inst, nm));
  AssertSame('its object', FObj, inst);
  AssertEquals('its property', 'Zeta', nm);
  FGrid.SelectedObject := FHolder;
  AssertTrue('a set element', FGrid.PropertyAt(FGrid.RowAt('Flags.pfB'), inst, nm));
  AssertEquals('stands for the set', 'Flags', nm);
  AssertTrue('a sub-object''s property', FGrid.PropertyAt(FGrid.RowAt('Inner.Level'), inst, nm));
  AssertSame('on the sub-object', FHolder.Inner, inst);
  AssertTrue('an item''s property', FGrid.PropertyAt(FGrid.RowAt('Items.[1].Size'), inst, nm));
  AssertSame('on that item', FHolder.Items.Items[1], inst);
  AssertFalse('a collection item''s own row is no property',
    FGrid.PropertyAt(FGrid.RowAt('Items.[1]'), inst, nm));
  AssertNull('and says so', inst);
  b := TTyButton.Create(FForm);
  FGrid.SelectedObject := b;
  AssertTrue('a font row', FGrid.PropertyAt(FGrid.RowAt('Font.Size'), inst, nm));
  AssertSame('on the font', b.Font, inst);
  AssertEquals('Size', 'Size', nm);
  AssertFalse('nil is nothing', FGrid.PropertyAt(nil, inst, nm));
end;

{ Decision (a) of the Task 1-3 review: inspecting a form, a reference picks from the form's own
  components (its ActiveControl is one of its controls) and the form itself -- not from the
  form's Owner, which has nothing to offer. }
procedure TPropertyGridControlTest.TestAFormListsTheControlsOnIt;
var other: TForm; b: TTyButton; e: TTyEdit;
begin
  other := TForm.CreateNew(nil);
  try
    other.Name := 'Host';
    b := TTyButton.Create(other);
    b.Name := 'Button1';
    b.Parent := other;
    e := TTyEdit.Create(other);
    e.Name := 'Edit1';
    e.Parent := other;
    FGrid.SelectedObject := other;
    AssertEquals('(none), the form''s controls and the form itself',
      rsTyPropGridNone + ',Button1,Edit1,Host', Lines(FGrid.RowAt('ActiveControl').EnumValues));
    FGrid.SelectedObject := nil;
  finally
    other.Free;
  end;
end;

procedure TPropertyGridControlTest.TestTheRootItselfIsACandidate;
var host: TPGHostComp;
begin
  FForm.Name := 'HostForm';
  host := TPGHostComp.Create(FForm);
  host.Name := 'HostComp';
  FGrid.SelectedObject := host;
  AssertEquals('the form''s components (the inspected one among them) and the form',
    rsTyPropGridNone + ',HostComp,HostForm', Lines(FGrid.RowAt('Ref').EnumValues));
  FGrid.PickFromDropdown(FGrid.RowAt('Ref'), 'HostForm');
  AssertSame('the form can be picked', FForm, host.Ref);
  FGrid.SelectedObject := nil;
  host.Ref := nil;
end;

{ ================================================================ refresh, expansion, settings }

procedure TPropertyGridControlTest.TestRefreshReReadsAndKeepsTheCurrentRowAndExpansion;
var r: TTyValueRow;
begin
  FGrid.SelectedObject := FHolder;
  FGrid.ClickTriangle(FGrid.RowAt('Inner'));
  AssertTrue('the click expanded Inner', FGrid.RowAt('Inner').Expanded);
  FGrid.Select(FGrid.RowAt('Inner.Level'));
  FHolder.Inner.Level := 99;                  // behind the grid's back
  AssertEquals('not seen yet', '5', FGrid.RowAt('Inner.Level').Value);
  r := FGrid.RowAt('Inner.Level');
  FGrid.Refresh;
  AssertEquals('re-read', '99', FGrid.RowAt('Inner.Level').Value);
  AssertSame('the same rows: nothing was rebuilt', r, FGrid.RowAt('Inner.Level'));
  AssertTrue('Inner still expanded', FGrid.RowAt('Inner').Expanded);
  AssertSame('and still the current row', FGrid.RowAt('Inner.Level'), FGrid.CurrentRow);
  FGrid.SelectedObject := nil;
end;

procedure TPropertyGridControlTest.TestRefreshRebuildsWhenACollectionGrows;
var it: TPGItem;
begin
  FGrid.SelectedObject := FHolder;
  FGrid.ClickTriangle(FGrid.RowAt('Items'));
  FGrid.Select(FGrid.RowAt('Items.[1]'));
  it := TPGItem(FHolder.Items.Add);
  it.Caption := 'third';
  FGrid.Refresh;
  AssertEquals('the new item has its row', 'third', FGrid.RowAt('Items.[2]').Value);
  AssertEquals('the count', Format(rsTyPropGridItems, [3]), FGrid.RowAt('Items').Value);
  AssertTrue('Items still expanded', FGrid.RowAt('Items').Expanded);
  AssertSame('the current row is the same item''s', FGrid.RowAt('Items.[1]'), FGrid.CurrentRow);
  FGrid.SelectedObject := nil;
end;

procedure TPropertyGridControlTest.TestExpansionFollowsTheSelectionToTheNextObject;
var b1, b2: TTyButton;
begin
  b1 := TTyButton.Create(FForm);
  b2 := TTyButton.Create(FForm);
  FGrid.SelectedObject := b1;
  AssertFalse('collapsed at first', FGrid.RowAt('Font').Expanded);
  FGrid.ClickTriangle(FGrid.RowAt('Font'));
  AssertTrue('the click expanded it', FGrid.RowAt('Font').Expanded);
  FGrid.SelectedObject := b2;
  AssertTrue('the next button''s Font is expanded too', FGrid.RowAt('Font').Expanded);
  AssertTrue('the path is on the list', FGrid.ExpandedProperties.IndexOf('Font') >= 0);
  FGrid.SelectedObject := FObj;                // no Font here
  FGrid.SelectedObject := b1;
  AssertTrue('kept across an object without it', FGrid.RowAt('Font').Expanded);
  FGrid.ClickTriangle(FGrid.RowAt('Font'));
  FGrid.SelectedObject := b2;
  AssertFalse('collapsing is followed as well', FGrid.RowAt('Font').Expanded);
end;

procedure TPropertyGridControlTest.TestAddingAPathExpandsTheRow;
var b: TTyButton; before: Integer;
begin
  b := TTyButton.Create(FForm);
  FGrid.SelectedObject := b;
  before := FGrid.DisplayRowCount;
  FGrid.ExpandedProperties.Add('Constraints');
  AssertTrue('expanded at once', FGrid.RowAt('Constraints').Expanded);
  AssertTrue('its rows are shown', FGrid.DisplayRowCount > before);
  FGrid.ExpandedProperties.Clear;
  AssertFalse('and collapsed when the path goes', FGrid.RowAt('Constraints').Expanded);
end;

procedure TPropertyGridControlTest.TestPropertyOrderRebuildsAtOnce;
begin
  AssertEquals('alphabetical by default', 'Alpha', FGrid.Row(0).Key);
  FGrid.PropertyOrder := poDeclared;
  AssertEquals('declared, no Rebuild called', 'Zeta', FGrid.Row(0).Key);
  FGrid.PropertyOrder := poAlphabetical;
  AssertEquals('and back', 'Alpha', FGrid.Row(0).Key);
end;

procedure TPropertyGridControlTest.TestTypeFilterHiddenPropertiesAndTheFilterEventRebuildAtOnce;
begin
  AssertTrue('the default filter', FGrid.TypeFilter = TyPropertyGridDefaultTypeFilter);
  FGrid.TypeFilter := FGrid.TypeFilter + [tkMethod];
  AssertTrue('events shown at once', FGrid.HasRow('OnPing'));
  FGrid.HiddenProperties.Add('Zeta');
  AssertFalse('hidden at once', FGrid.HasRow('Zeta'));
  FGrid.OnFilterProperty := @HideAlpha;
  FGrid.Rebuild;
  AssertFalse('the event hides Alpha', FGrid.HasRow('Alpha'));
  AssertTrue('and nothing else', FGrid.HasRow('Ratio'));
end;

procedure TPropertyGridControlTest.TestKeyOptionsStayEmpty;
var n: Integer;
begin
  AssertTrue('fixed at []', FGrid.KeyOptions = []);
  AssertNull('and not published', GetPropInfo(TTyPropertyGrid, 'KeyOptions'));
  n := FGrid.RowCount;
  FGrid.Select(FGrid.RowAt('Zeta'));
  FGrid.Press(VK_INSERT);
  FGrid.Press(VK_DELETE, [ssModifier]);
  AssertEquals('Insert and Ctrl+Delete leave the rows alone', n, FGrid.RowCount);
end;

initialization
  RegisterTest(TPropertyGridControlTest);
end.
