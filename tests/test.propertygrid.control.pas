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
  Classes, SysUtils, TypInfo, LCLType, Controls, Graphics, Forms, Menus, fpcunit, testregistry,
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
    FDone: Integer;
    FAllow: Boolean;
    FHandle: Boolean;
    FValueAsked: TStringList;   // OnValueChanging: 'key=text'
    FValueAllow: Boolean;
    FValueRewrite: string;
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
    procedure RebuildGrid(Sender: TObject);
    procedure EditingDoneSeen(Sender: TObject);
    procedure ShowInMm(Sender: TObject; AInstance: TPersistent; APropInfo: PPropInfo;
      ARow: TTyValueRow);
    procedure CountAsDialog(Sender: TObject; AInstance: TPersistent; APropInfo: PPropInfo;
      ARow: TTyValueRow);
    procedure EditCount(Sender: TObject; ARow: TTyValueRow; AInstance: TPersistent;
      const APropName: string; var AHandled: Boolean);
    procedure ValueChanging(Sender: TObject; ARow: TTyValueRow; var AText: string;
      var AAllow: Boolean);
    procedure ValueChangingRebuilds(Sender: TObject; ARow: TTyValueRow; var AText: string;
      var AAllow: Boolean);
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
    { #183 }
    procedure TestASetterThatRebuildsTheRowsEndsTheWrite;
    procedure TestTheStringsDialogWritesAfterARebuildWhileItWasUp;
    procedure TestAWriteThatChangesTheStructureRebuildsTheRows;
    procedure TestAStreamedSelectionIsReadAgainOnceLoadingIsOver;
    procedure TestTheGridsOwnLinksOutliveTheSelection;
    procedure TestADisplayValueFromOnGetPropertyRowFollowsTheValue;
    procedure TestOnEditingDoneIsNotAnnouncedWhenAnEditStarts;
    procedure TestOnEditingDoneComesOnceWhenAnEditEnds;
    procedure TestAnEditOnAComponentBeingFreedIsDropped;
    { the value list editor's row API, on the grid }
    procedure TestOnValueChangingIsAskedBeforeThePropertyIsWritten;
    procedure TestAnOnValueChangingHandlerThatRebuildsTheRowsEndsTheWrite;
    procedure TestFindRowGoesByTheGridsPaths;
    procedure TestSaveAndRestoreExpandedGoByTheGridsPaths;
  end;

implementation

type
  { A form with the grid and a button as published fields, for the round trip through a stream. }
  TPGHostForm = class(TForm)
  published
    Grid: TTyPropertyGrid;
    Button1: TTyButton;
  end;

  { The grid read before the component it inspects, whose Loaded comes after the grid's. }
  TPGLoadedHostForm = class(TForm)
  published
    Grid: TTyPropertyGrid;
    Comp: TPGLoadedComp;
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
  FValueAsked := TStringList.Create;
  FValueAllow := True;
  FValueRewrite := '';
end;

procedure TPropertyGridControlTest.TearDown;
begin
  FForm.Free;
  FObj.Free;
  FHolder.Free;
  FValueAsked.Free;
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

procedure TPropertyGridControlTest.ValueChanging(Sender: TObject; ARow: TTyValueRow;
  var AText: string; var AAllow: Boolean);
begin
  FValueAsked.Add(ARow.Key + '=' + AText);
  if FValueRewrite <> '' then AText := FValueRewrite;
  AAllow := FValueAllow;
end;

procedure TPropertyGridControlTest.ValueChangingRebuilds(Sender: TObject; ARow: TTyValueRow;
  var AText: string; var AAllow: Boolean);
begin
  FValueAsked.Add(ARow.Key + '=' + AText);
  FGrid.Rebuild;   // every row, ARow among them, is made anew
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

procedure TPropertyGridControlTest.RebuildGrid(Sender: TObject);
begin
  FGrid.Rebuild;
end;

procedure TPropertyGridControlTest.EditingDoneSeen(Sender: TObject);
begin
  Inc(FDone);
end;

procedure TPropertyGridControlTest.ShowInMm(Sender: TObject; AInstance: TPersistent;
  APropInfo: PPropInfo; ARow: TTyValueRow);
begin
  if (APropInfo^.Name = 'Zeta') or (APropInfo^.Name = 'Width') then
    ARow.DisplayValue := IntToStr(GetOrdProp(AInstance, APropInfo)) + ' mm';
end;

procedure TPropertyGridControlTest.CountAsDialog(Sender: TObject; AInstance: TPersistent;
  APropInfo: PPropInfo; ARow: TTyValueRow);
begin
  if APropInfo^.Name = 'Count' then ARow.EditorKind := vekDialog;
end;

procedure TPropertyGridControlTest.EditCount(Sender: TObject; ARow: TTyValueRow;
  AInstance: TPersistent; const APropName: string; var AHandled: Boolean);
begin
  if not (AInstance is TPGCounted) or (APropName <> 'Count') then Exit;
  TPGCounted(AInstance).Count := 3;   // the application's own dialog, answered
  AHandled := True;
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

{ ================================================================ #183 }

{ The first object's setter rebuilds the rows (the application refreshing the grid from it) while
  the grid is still writing. Freed blocks are poisoned, so a write that went on with the node the
  rebuild freed faults instead of meeting a fresh node in the same memory. }
procedure TPropertyGridControlTest.TestASetterThatRebuildsTheRowsEndsTheWrite;
var a, b: TPGHook;
begin
  a := TPGHook.Create;
  b := TPGHook.Create;
  try
    a.OnSet := @RebuildGrid;
    FGrid.SelectObjects([a, b]);
    FGrid.OnPropertyError := @Failed;
    BeginPoison;
    try
      FGrid.TypeInto(FGrid.RowAt('Value'), '5');
    finally
      EndPoison;
    end;
    AssertEquals('no error reached the application', '', FSeenError);
    AssertEquals('the first object took it', 5, a.Value);
    AssertEquals('the write stopped where the rows were rebuilt', 0, b.Value);
    AssertEquals('the rows read the objects', '', FGrid.RowAt('Value').Value);
  finally
    FGrid.SelectedObject := nil;
    a.Free;
    b.Free;
  end;
end;

{ The rows are rebuilt while the strings dialog is up (a timer, say). OK still writes the list:
  into the same property of the same object, found again by its path. }
procedure TPropertyGridControlTest.TestTheStringsDialogWritesAfterARebuildWhileItWasUp;
begin
  FGrid.SelectedObject := FHolder;
  FGrid.StringsAccept := True;
  FGrid.StringsAnswer := 'x' + LineEnding + 'y';
  FGrid.OnStringsDialog := @RebuildGrid;
  BeginPoison;
  try
    FGrid.InvokeRowDialog(FGrid.FlatOf(FGrid.RowAt('Lines')));
  finally
    EndPoison;
  end;
  AssertEquals('the dialog ran', 1, FGrid.StringsDialogs);
  AssertEquals('the list was written', 'x,y', Lines(FHolder.Lines.Text));
  AssertEquals('through the setter', 1, FHolder.LinesSets);
end;

{ Count resizes the collection beside it. After the grid's own write -- typed, or a handled
  OnEditProperty -- the rows are rebuilt as Refresh would, the current row kept. }
procedure TPropertyGridControlTest.TestAWriteThatChangesTheStructureRebuildsTheRows;
var c: TPGCounted;
begin
  c := TPGCounted.Create;
  try
    FGrid.SelectedObject := c;
    FGrid.ExpandedProperties.Add('Items');
    FGrid.TypeInto(FGrid.RowAt('Count'), '4');
    AssertEquals('the object grew', 4, c.Items.Count);
    AssertTrue('a row for each new item', FGrid.HasRow('Items.[3]'));
    AssertEquals('the new item reads its caption', 'item3', FGrid.RowAt('Items.[3]').Value);
    AssertSame('the current row kept', FGrid.RowAt('Count'), FGrid.CurrentRow);
    FGrid.TypeInto(FGrid.RowAt('Count'), '1');
    AssertFalse('the rows of the items gone are gone', FGrid.HasRow('Items.[1]'));
    FGrid.OnGetPropertyRow := @CountAsDialog;
    FGrid.OnEditProperty := @EditCount;
    FGrid.Rebuild;
    FGrid.InvokeRowDialog(FGrid.FlatOf(FGrid.RowAt('Count')));
    AssertEquals('the handler wrote it', 3, c.Items.Count);
    AssertTrue('and the rows followed', FGrid.HasRow('Items.[2]'));
  finally
    FGrid.SelectedObject := nil;
    c.Free;
  end;
end;

{ The grid comes before the component in the form file, so its Loaded -- the first build -- runs
  before the component's own Loaded sets Level. Once loading is over the rows read it again. }
procedure TPropertyGridControlTest.TestAStreamedSelectionIsReadAgainOnceLoadingIsOver;
var
  src, dst: TPGLoadedHostForm;
  ms: TMemoryStream;
  i: Integer;
  level: TTyValueRow;
begin
  RegisterClasses([TTyPropertyGrid, TPGLoadedComp]);
  src := TPGLoadedHostForm.CreateNew(nil);
  dst := TPGLoadedHostForm.CreateNew(nil);
  ms := TMemoryStream.Create;
  try
    src.Name := 'PGLoadedHostForm1';
    src.Grid := TTyPropertyGrid.Create(src);
    src.Grid.Name := 'Grid';
    src.Grid.Parent := src;
    src.Comp := TPGLoadedComp.Create(src);
    src.Comp.Name := 'Comp';
    src.Grid.SelectedComponent := src.Comp;
    ms.WriteComponent(src);
    ms.Position := 0;
    ms.ReadComponent(dst);
    AssertEquals('the component set itself up', 99, dst.Comp.Level);
    Forms.Application.ProcessMessages;
    level := nil;
    for i := 0 to dst.Grid.RowCount - 1 do
      if dst.Grid.Row(i).Key = 'Level' then level := dst.Grid.Row(i);
    AssertNotNull('Level listed', level);
    AssertEquals('and the row reads what it holds now', '99', level.Value);
  finally
    ms.Free;
    dst.Free;
    src.Free;
  end;
end;

{ The grid inspects the image list (or the menu) it also uses as its own Images (PopupMenu).
  TComponent keeps one free notification per pair, so letting go of one must not let go of the
  other: freed, the list is let go of by both. }
procedure TPropertyGridControlTest.TestTheGridsOwnLinksOutliveTheSelection;
var il: TImageList; pm: TPopupMenu;
begin
  il := TImageList.Create(nil);
  FGrid.Images := il;
  FGrid.SelectedComponent := il;
  FGrid.SelectedObject := FObj;          // the image list leaves the selection
  il.Free;
  AssertNull('the grid let go of its Images', FGrid.Images);
  pm := TPopupMenu.Create(nil);
  FGrid.PopupMenu := pm;
  FGrid.SelectedComponent := pm;
  FGrid.SelectedObject := FObj;
  pm.Free;
  AssertNull('and of its PopupMenu', FGrid.PopupMenu);
  il := TImageList.Create(nil);
  FGrid.SelectedComponent := il;
  FGrid.Images := il;
  FGrid.Images := nil;                    // the grid stops using it; it is still inspected
  BeginPoison;
  try
    il.Free;
    FGrid.Refresh;
  finally
    EndPoison;
  end;
  AssertNull('the selection let go of it', FGrid.SelectedObject);
  AssertEquals('no rows', 0, FGrid.RowCount);
end;

{ Doc section 5.3: OnGetPropertyRow may set DisplayValue. One made from the value has to follow it
  -- on the row edited, and on a row a setter moved -- or the edit looks as if it did nothing. }
procedure TPropertyGridControlTest.TestADisplayValueFromOnGetPropertyRowFollowsTheValue;
begin
  FGrid.OnGetPropertyRow := @ShowInMm;
  FGrid.Rebuild;
  AssertEquals('shown as the handler says', '0 mm', FGrid.RowAt('Zeta').EffectiveValue);
  FGrid.TypeInto(FGrid.RowAt('Zeta'), '42');
  AssertEquals('written', 42, FObj.Zeta);
  AssertEquals('the row edited shows the new value', '42 mm', FGrid.RowAt('Zeta').EffectiveValue);
  FGrid.Select(FGrid.RowAt('AutoGrow'));
  FGrid.Press(VK_SPACE);                 // AutoGrow's setter moves Width to 999
  AssertEquals('a row a setter moved too', '999 mm', FGrid.RowAt('Width').EffectiveValue);
  FObj.Zeta := 7;
  FGrid.Refresh;
  AssertEquals('and after a Refresh', '7 mm', FGrid.RowAt('Zeta').EffectiveValue);
end;

{ LCL's grid: EditingDone is held back while the cell editor is showing and comes when the edit is
  finished (grids.pas, TCustomGrid.EditingDone and TStringCellEditor.EditingDone). The grid lost
  focus to its own editor the moment a cell was clicked, and that was announced instead. Real
  focus, on a shown form. }
procedure TPropertyGridControlTest.TestOnEditingDoneIsNotAnnouncedWhenAnEditStarts;
begin
  FDone := 0;
  FGrid.OnEditingDone := @EditingDoneSeen;
  FForm.Show;
  FGrid.SetFocus;
  AssertTrue('the grid has the focus', FGrid.Focused);
  FGrid.ClickValue(FGrid.RowAt('Zeta'));
  AssertTrue('the editor opened', FGrid.EditingRow >= 0);
  AssertTrue('and took the focus', FGrid.Editor.Focused);
  AssertEquals('not when the edit starts', 0, FDone);
  FGrid.CloseEditor;
end;

{ Each end of an edit announced once: the focus coming back from the dropped list is not another
  end. }
procedure TPropertyGridControlTest.TestOnEditingDoneComesOnceWhenAnEditEnds;
begin
  FDone := 0;
  FGrid.OnEditingDone := @EditingDoneSeen;
  FGrid.ClickValue(FGrid.RowAt('Zeta'));
  AssertTrue('the editor opened', FGrid.EditingRow >= 0);
  AssertEquals('nothing yet', 0, FDone);
  FGrid.Editor.TypeText('5');
  FGrid.Editor.PressKey(VK_RETURN);
  AssertEquals('written', 5, FObj.Zeta);
  AssertEquals('when it is committed', 1, FDone);
  FGrid.PickFromDropdown(FGrid.RowAt('Flag'), 'True');
  AssertTrue('picked', FObj.Flag);
  AssertEquals('and after a pick from a list', 2, FDone);
  FGrid.SelectedObject := FHolder;
  FGrid.StringsAccept := True;
  FGrid.StringsAnswer := 'z';
  FGrid.ClickPaintedEllipsis(FGrid.RowAt('Lines'));
  AssertEquals('the dialog wrote', 'z', Trim(FHolder.Lines.Text));
  AssertEquals('and once it was over', 3, FDone);
end;

{ The rows are rebuilt when a selected component is freed, and a rebuild now writes an edit in
  progress first (#183) -- but not into the component going away. }
procedure TPropertyGridControlTest.TestAnEditOnAComponentBeingFreedIsDropped;
var host: TPGHostComp;
begin
  host := TPGHostComp.Create(nil);
  FGrid.SelectedComponent := host;
  FGrid.OnPropertyChanging := @Changing;
  FGrid.ClickValue(FGrid.RowAt('Tag'));
  AssertTrue('the editor opened', FGrid.EditingRow >= 0);
  FGrid.Editor.TypeText('5');
  BeginPoison;
  try
    host.Free;
    FGrid.Refresh;
  finally
    EndPoison;
  end;
  AssertEquals('nothing was written into it', 0, FChanging);
  AssertEquals('the editor is closed', -1, FGrid.EditingRow);
  AssertNull('the selection let go', FGrid.SelectedObject);
end;

{ The value list editor's OnValueChanging is asked on the grid too, before the write and before
  OnPropertyChanging: about the row, with the text as typed. }
procedure TPropertyGridControlTest.TestOnValueChangingIsAskedBeforeThePropertyIsWritten;
begin
  FGrid.OnValueChanging := @ValueChanging;
  FGrid.OnPropertyChanging := @Changing;
  FAllow := True;
  FValueAllow := False;
  FGrid.TypeInto(FGrid.RowAt('Zeta'), '42');
  AssertEquals('asked about the row, with the text typed', 'Zeta=42', FValueAsked.CommaText);
  AssertEquals('refused: nothing is written', 0, FObj.Zeta);
  AssertEquals('and the write was never started', 0, FChanging);
  AssertEquals('the row keeps its value', '0', FGrid.RowAt('Zeta').Value);
  FValueAllow := True;
  FValueRewrite := '7';
  FGrid.TypeInto(FGrid.RowAt('Zeta'), '42');
  AssertEquals('allowed: the text the handler left is what is written', 7, FObj.Zeta);
  AssertEquals('OnPropertyChanging came after it', 1, FChanging);
  AssertEquals('with that text', '7', FSeenValue);
  AssertEquals('and the row reads the object', '7', FGrid.RowAt('Zeta').Value);
  FGrid.OnValueChanging := nil;
  FGrid.TypeInto(FGrid.RowAt('Zeta'), '42');
  AssertEquals('without a handler the grid writes as ever', 42, FObj.Zeta);
end;

{ A handler that rebuilds the rows takes the row being committed with them: the write stops there,
  as it does when OnPropertyChanging rebuilds them. OnPropertyChanging refuses here, so a write
  that did go on would be seen and still change nothing. }
procedure TPropertyGridControlTest.TestAnOnValueChangingHandlerThatRebuildsTheRowsEndsTheWrite;
begin
  FGrid.OnValueChanging := @ValueChangingRebuilds;
  FGrid.OnPropertyChanging := @Changing;
  FAllow := False;
  FGrid.TypeInto(FGrid.RowAt('Zeta'), '42');
  AssertEquals('the handler was asked', 'Zeta=42', FValueAsked.CommaText);
  AssertEquals('the write was not gone on with on rows that are gone', 0, FChanging);
  AssertEquals('nothing is written', 0, FObj.Zeta);
  AssertEquals('the new row shows the object', '0', FGrid.RowAt('Zeta').Value);
end;

procedure TPropertyGridControlTest.TestFindRowGoesByTheGridsPaths;
var stray: TTyValueRow;
begin
  FGrid.SelectedObject := FHolder;
  AssertSame('a property', FGrid.RowAt('Flags'), FGrid.FindRow('Flags'));
  AssertSame('a set''s element, in any case', FGrid.RowAt('Flags.pfB'), FGrid.FindRow('flags.PFB'));
  AssertSame('a collection item, spelled as the grid spells it', FGrid.RowAt('Items.[1]'),
    FGrid.FindRow('Items[1]'));
  AssertSame('a property of an item', FGrid.RowAt('Items.[1].Caption'),
    FGrid.FindRow('Items[1].Caption'));
  AssertNull('no such property', FGrid.FindRow('Nothing'));
  AssertNull('nothing is selected yet', FGrid.SelectedRow);
  FGrid.Select(FGrid.RowAt('Flags'));
  AssertSame('SelectedRow is the row the selection is on', FGrid.RowAt('Flags'), FGrid.SelectedRow);
  AssertEquals('whose path the grid gives', 'Flags', FGrid.RowPath(FGrid.SelectedRow));
  stray := FGrid.AddRow('Stray', 'x');   // not one of the grid's
  AssertEquals('a row the grid did not build has no path', '', FGrid.RowPath(stray));
  AssertNull('and is not found by its key', FGrid.FindRow('Stray'));
end;

procedure TPropertyGridControlTest.TestSaveAndRestoreExpandedGoByTheGridsPaths;
var open: TStringList;
begin
  FGrid.SelectedObject := FHolder;
  FGrid.ClickTriangle(FGrid.RowAt('Items'));
  FGrid.ClickTriangle(FGrid.RowAt('Items.[0]'));
  open := TStringList.Create;
  try
    FGrid.SaveExpanded(open);
    open.Sort;
    AssertEquals('the open rows, by the grid''s paths', 'Items,Items[0]', open.CommaText);
    AssertEquals('which is what ExpandedProperties holds', open.CommaText,
      FGrid.ExpandedProperties.CommaText);
    open.Clear;
    open.Add('Flags');
    FGrid.RestoreExpanded(open);
    AssertTrue('the listed row is opened', FGrid.RowAt('Flags').Expanded);
    AssertFalse('the others are closed', FGrid.RowAt('Items').Expanded);
    AssertEquals('and ExpandedProperties follows the rows', 'Flags',
      FGrid.ExpandedProperties.CommaText);
  finally
    open.Free;
  end;
end;

initialization
  RegisterTest(TPropertyGridControlTest);
end.
