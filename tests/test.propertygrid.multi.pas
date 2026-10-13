unit test.propertygrid.multi;
{$mode objfpc}{$H+}

{ The property grid (#65), phase 2 Task 1: several objects at once (plan D1).

  The rows are the properties every selected object has (same name, same type); a value they do
  not agree on is an empty cell; an edit is written into every one of them, after
  OnPropertyChanging has said yes for each. As before, every edit goes in the way the user makes
  it (a click and typing, Enter, Space, the dropped list) and every verdict is read off the
  inspected objects. }

interface

uses
  Classes, SysUtils, TypInfo, LCLType, Controls, Graphics, Forms, Menus, fpcunit, testregistry,
  tyControls.ValueListEditor, tyControls.PropertyGrid, tyControls.Button,
  test.propertygrid.fixtures, test.danglingrefs;

type
  TPropertyGridMultiTest = class(TTestCase)
  private
    FForm: TForm;
    FGrid: TPGGrid;
    FB1, FB2, FB3: TTyButton;
    FP1, FP2, FP3: TPGPart;
    FOther: TPGPartOther;
    FRefuse: TPersistent;      // the object OnPropertyChanging refuses, nil = none
    FAsked, FAnnounced: TList;
    FErrorOn: TPersistent;
    FErrors: Integer;
    procedure Changing(Sender: TObject; AInstance: TPersistent; const APropName,
      ANewValue: string; var AAllow: Boolean);
    procedure Changed(Sender: TObject; AInstance: TPersistent; const APropName: string);
    procedure Failed(Sender: TObject; AInstance: TPersistent; const APropName: string;
      E: Exception);
    function NewButton(const AName, ACaption: string): TTyButton;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestOnlyWhatEveryObjectHasIsListed;
    procedure TestOneObjectWithoutASetterMakesTheRowReadOnly;
    procedure TestAValueTheyShareShowsOneTheyDoNotIsEmpty;
    procedure TestTypingWritesEveryObject;
    procedure TestAPickWritesEveryObject;
    procedure TestOneRefusalAndNoneIsWritten;
    procedure TestASetterThatRaisesStopsAtThatObject;
    procedure TestSpaceUnifiesABooleanTheyDisagreeOn;
    procedure TestSpaceOnASetElementFlipsItInEachObjectsOwnSet;
    procedure TestAFontSizeIsWrittenIntoEveryFont;
    procedure TestASubObjectExpandsOnlyWhenItIsOneClass;
    procedure TestACollectionIsShownButNotOpened;
    procedure TestAReferencePicksFromTheFirstObjectsListAndSetsAll;
    procedure TestFreeingOneLeavesTheOthers;
    procedure TestTheSelectionApi;
  end;

implementation

procedure TPropertyGridMultiTest.SetUp;
begin
  FForm := NewHostForm;
  FForm.Name := 'MultiHost';
  FGrid := TPGGrid.Create(FForm);
  FGrid.Parent := FForm;
  FGrid.SetBounds(0, 0, 440, 720);
  FB1 := NewButton('Button1', 'one');
  FB2 := NewButton('Button2', 'two');
  FB3 := NewButton('Button3', 'three');
  FP1 := TPGPart.Create;
  FP2 := TPGPart.Create;
  FP3 := TPGPart.Create;
  FOther := TPGPartOther.Create;
  FAsked := TList.Create;
  FAnnounced := TList.Create;
  FRefuse := nil;
  FErrorOn := nil;
  FErrors := 0;
  FForm.Show;
end;

procedure TPropertyGridMultiTest.TearDown;
begin
  FForm.Free;
  FP1.Free;
  FP2.Free;
  FP3.Free;
  FOther.Free;
  FAsked.Free;
  FAnnounced.Free;
end;

function TPropertyGridMultiTest.NewButton(const AName, ACaption: string): TTyButton;
begin
  Result := TTyButton.Create(FForm);
  Result.Name := AName;
  Result.Parent := FForm;
  Result.SetBounds(10, 730, 80, 24);
  Result.Caption := ACaption;
  Result.Font.Name := 'Arial';
  Result.Font.Size := 9;
end;

procedure TPropertyGridMultiTest.Changing(Sender: TObject; AInstance: TPersistent;
  const APropName, ANewValue: string; var AAllow: Boolean);
begin
  FAsked.Add(AInstance);
  AAllow := AInstance <> FRefuse;
end;

procedure TPropertyGridMultiTest.Changed(Sender: TObject; AInstance: TPersistent;
  const APropName: string);
begin
  FAnnounced.Add(AInstance);
end;

procedure TPropertyGridMultiTest.Failed(Sender: TObject; AInstance: TPersistent;
  const APropName: string; E: Exception);
begin
  Inc(FErrors);
  FErrorOn := AInstance;
end;

{ ================================================================ the rows }

procedure TPropertyGridMultiTest.TestOnlyWhatEveryObjectHasIsListed;
begin
  FGrid.SelectObjects([FP1, FOther]);
  AssertEquals('the properties both have, by name', 'Active,Caption,Level,Note', FGrid.RootKeys);
  AssertFalse('Special is TPGPart''s alone', FGrid.HasRow('Special'));
  AssertFalse('Kind: the same name, but a TPGKind on one and an Integer on the other',
    FGrid.HasRow('Kind'));
  FGrid.SelectObjects([FP1, FP2]);
  AssertTrue('two of one class share everything', FGrid.HasRow('Kind'));
  AssertTrue('Special too', FGrid.HasRow('Special'));
end;

procedure TPropertyGridMultiTest.TestOneObjectWithoutASetterMakesTheRowReadOnly;
begin
  FP1.Note := 'n';
  FOther.SetNoteDirectly('n');
  FGrid.SelectObjects([FP1, FOther]);
  AssertTrue('TPGPartOther.Note has no setter', FGrid.RowAt('Note').ReadOnly);
  FGrid.ClickValue(FGrid.RowAt('Note'));
  AssertEquals('so a click opens nothing', -1, FGrid.EditingRow);
  AssertFalse('Level is writable in both', FGrid.RowAt('Level').ReadOnly);
end;

procedure TPropertyGridMultiTest.TestAValueTheyShareShowsOneTheyDoNotIsEmpty;
begin
  FGrid.SelectObjects([FB1, FB2, FB3]);
  AssertEquals('one, two, three: no caption stands for all', '', FGrid.RowAt('Caption').Value);
  AssertEquals('the same font everywhere is shown', 'Arial, 9', FGrid.RowAt('Font').Value);
  AssertEquals('and its size', '9', FGrid.RowAt('Font.Size').Value);
  FB3.Caption := 'one';
  FB2.Caption := 'one';
  FGrid.Refresh;
  AssertEquals('once they agree, the value is back', 'one', FGrid.RowAt('Caption').Value);
end;

procedure TPropertyGridMultiTest.TestTypingWritesEveryObject;
begin
  FGrid.SelectObjects([FB1, FB2, FB3]);
  FGrid.OnPropertyChanging := @Changing;
  FGrid.OnPropertyChanged := @Changed;
  FGrid.ClickValue(FGrid.RowAt('Caption'));
  AssertEquals('the editor opens on the empty cell', '', FGrid.Editor.Text);
  FGrid.Editor.TypeText('same');
  FGrid.Editor.PressKey(VK_RETURN);
  AssertEquals('button 1', 'same', FB1.Caption);
  AssertEquals('button 2', 'same', FB2.Caption);
  AssertEquals('button 3', 'same', FB3.Caption);
  AssertEquals('the row reads what they all read', 'same', FGrid.RowAt('Caption').Value);
  AssertEquals('each was asked', 3, FAsked.Count);
  AssertSame('in order: 1', FB1, TObject(FAsked[0]));
  AssertSame('2', FB2, TObject(FAsked[1]));
  AssertSame('3', FB3, TObject(FAsked[2]));
  AssertEquals('each was announced', 3, FAnnounced.Count);
  AssertSame('the last one announced is button 3', FB3, TObject(FAnnounced[2]));
end;

procedure TPropertyGridMultiTest.TestAPickWritesEveryObject;
begin
  FP2.Kind := pgkThree;
  FGrid.SelectObjects([FP1, FP2]);
  AssertEquals('pgkOne and pgkThree', '', FGrid.RowAt('Kind').Value);
  FGrid.PickFromDropdown(FGrid.RowAt('Kind'), 'pgkTwo');
  AssertTrue('first', FP1.Kind = pgkTwo);
  AssertTrue('second', FP2.Kind = pgkTwo);
  AssertEquals('row', 'pgkTwo', FGrid.RowAt('Kind').Value);
end;

procedure TPropertyGridMultiTest.TestOneRefusalAndNoneIsWritten;
begin
  FGrid.SelectObjects([FB1, FB2, FB3]);
  FGrid.OnPropertyChanging := @Changing;
  FGrid.OnPropertyChanged := @Changed;
  FRefuse := FB2;
  FGrid.TypeInto(FGrid.RowAt('Caption'), 'same');
  AssertEquals('button 1 untouched', 'one', FB1.Caption);
  AssertEquals('button 2, the refused one, untouched', 'two', FB2.Caption);
  AssertEquals('button 3 untouched', 'three', FB3.Caption);
  AssertEquals('nothing announced', 0, FAnnounced.Count);
  AssertEquals('the row is still empty', '', FGrid.RowAt('Caption').Value);
end;

procedure TPropertyGridMultiTest.TestASetterThatRaisesStopsAtThatObject;
begin
  FP2.Refuse := True;
  FGrid.SelectObjects([FP1, FP2, FP3]);
  FGrid.OnPropertyError := @Failed;
  FGrid.OnPropertyChanged := @Changed;
  FGrid.TypeInto(FGrid.RowAt('Guarded'), '7');
  AssertEquals('the first took it, and keeps it', 7, FP1.Guarded);
  AssertEquals('the second''s setter ran and raised', 1, FP2.GuardedTries);
  AssertEquals('so it holds its old value', 0, FP2.Guarded);
  AssertEquals('the third was never tried', 0, FP3.GuardedTries);
  AssertEquals('one error', 1, FErrors);
  AssertSame('naming the object that failed', FP2, FErrorOn);
  AssertEquals('the row shows the objects: 7, 0, 0 do not agree', '', FGrid.RowAt('Guarded').Value);
  AssertEquals('nothing announced as changed', 0, FAnnounced.Count);
end;

procedure TPropertyGridMultiTest.TestSpaceUnifiesABooleanTheyDisagreeOn;
begin
  FP1.Active := True;
  FGrid.SelectObjects([FP1, FP2, FP3]);
  AssertEquals('True, False, False', '', FGrid.RowAt('Active').Value);
  FGrid.Select(FGrid.RowAt('Active'));
  FGrid.Press(VK_SPACE);
  AssertTrue('first', FP1.Active);
  AssertTrue('second', FP2.Active);
  AssertTrue('third', FP3.Active);
  AssertEquals('row', 'True', FGrid.RowAt('Active').Value);
  FGrid.Press(VK_SPACE);
  AssertFalse('and all off again', FP1.Active or FP2.Active or FP3.Active);
end;

procedure TPropertyGridMultiTest.TestSpaceOnASetElementFlipsItInEachObjectsOwnSet;
begin
  FP1.Flags := [pfA];
  FP2.Flags := [pfB];
  FGrid.SelectObjects([FP1, FP2]);
  AssertEquals('the sets differ', '', FGrid.RowAt('Flags').Value);
  AssertEquals('pfA: in one, not the other', '', FGrid.RowAt('Flags.pfA').Value);
  AssertEquals('pfD: in neither', 'False', FGrid.RowAt('Flags.pfD').Value);
  FGrid.Select(FGrid.RowAt('Flags.pfA'));
  FGrid.Press(VK_SPACE);
  AssertTrue('the first keeps its own set, pfA on', FP1.Flags = [pfA]);
  AssertTrue('the second gains pfA and keeps pfB', FP2.Flags = [pfA, pfB]);
  AssertEquals('pfA now agrees', 'True', FGrid.RowAt('Flags.pfA').Value);
end;

procedure TPropertyGridMultiTest.TestAFontSizeIsWrittenIntoEveryFont;
begin
  FB2.Font.Name := 'Courier New';
  FB2.Font.Size := 10;
  FB3.Font.Size := 11;
  FGrid.SelectObjects([FB1, FB2, FB3]);
  AssertEquals('9, 10, 11', '', FGrid.RowAt('Font.Size').Value);
  FGrid.TypeInto(FGrid.RowAt('Font.Size'), '14');
  AssertEquals('button 1', 14, FB1.Font.Size);
  AssertEquals('button 2', 14, FB2.Font.Size);
  AssertEquals('button 3', 14, FB3.Font.Size);
  AssertEquals('each keeps its own face', 'Courier New', FB2.Font.Name);
  AssertEquals('button 1''s face', 'Arial', FB1.Font.Name);
  AssertEquals('row', '14', FGrid.RowAt('Font.Size').Value);
end;

procedure TPropertyGridMultiTest.TestASubObjectExpandsOnlyWhenItIsOneClass;
begin
  FGrid.SelectObjects([FP1, FP2]);
  AssertTrue('two TPGInner: expanded into their properties', FGrid.HasRow('Inner.Level'));
  FGrid.TypeInto(FGrid.RowAt('Inner.Level'), '6');
  AssertEquals('written into the first''s', 6, TPGInner(FP1.Inner).Level);
  AssertEquals('and the second''s', 6, TPGInner(FP2.Inner).Level);
  FP2.UseInnerB;
  FGrid.Refresh;
  AssertEquals('a TPGInner and a TPGInnerB', 0, FGrid.RowAt('Inner').ChildCount);
  AssertTrue('read-only', FGrid.RowAt('Inner').ReadOnly);
  AssertEquals('and no class name stands for both', '', FGrid.RowAt('Inner').Value);
end;

procedure TPropertyGridMultiTest.TestACollectionIsShownButNotOpened;
begin
  FGrid.SelectObjects([FP1, FP2]);
  AssertEquals('shown as (…)', TyPropertyGridSeveral, FGrid.RowAt('Items').Value);
  AssertTrue('read-only', FGrid.RowAt('Items').ReadOnly);
  AssertEquals('not expanded: the items cannot be matched up', 0, FGrid.RowAt('Items').ChildCount);
  FGrid.SelectObjects([FP1]);
  AssertEquals('one object: its items again', 1, FGrid.RowAt('Items').ChildCount);
end;

procedure TPropertyGridMultiTest.TestAReferencePicksFromTheFirstObjectsListAndSetsAll;
var pop: TPopupMenu;
begin
  pop := TPopupMenu.Create(FForm);
  pop.Name := 'PopupMenu1';
  FGrid.SelectObjects([FB1, FB2]);
  FGrid.PickFromDropdown(FGrid.RowAt('PopupMenu'), 'PopupMenu1');
  AssertSame('button 1', pop, FB1.PopupMenu);
  AssertSame('button 2', pop, FB2.PopupMenu);
  AssertEquals('row', 'PopupMenu1', FGrid.RowAt('PopupMenu').Value);
end;

{ One of three is freed while the grid shows them. Every freed block is poisoned in between, so a
  read through what the grid kept of it would meet $7F7F... -- the grid must have let it go. }
procedure TPropertyGridMultiTest.TestFreeingOneLeavesTheOthers;
begin
  FGrid.SelectObjects([FB1, FB2, FB3]);
  FGrid.ExpandedProperties.Add('Font');
  BeginPoison;
  try
    FB2.Free;
    FB2 := nil;
    FGrid.Refresh;
    FGrid.Rebuild;
    FGrid.Repaint;
    FGrid.TypeInto(FGrid.RowAt('Caption'), 'left');
  finally
    EndPoison;
  end;
  AssertEquals('two are left', 2, FGrid.SelectedCount);
  AssertSame('the first', FB1, FGrid.SelectedObjects[0]);
  AssertSame('the third', FB3, FGrid.SelectedObjects[1]);
  AssertEquals('and still written', 'left', FB1.Caption);
  AssertEquals('both', 'left', FB3.Caption);
  AssertTrue('the expansion stays', FGrid.RowAt('Font').Expanded);
end;

procedure TPropertyGridMultiTest.TestTheSelectionApi;
var raised: Boolean;
begin
  FGrid.SelectObjects([FB1, nil, FB2, FB1]);
  AssertEquals('nil and the repeat dropped', 2, FGrid.SelectedCount);
  AssertSame('SelectedObject is the first', FB1, FGrid.SelectedObject);
  AssertNull('SelectedComponent is for one object only', FGrid.SelectedComponent);
  raised := False;
  try
    if FGrid.SelectedObjects[2] = nil then Fail('unreachable');
  except
    on E: EListError do raised := True;
  end;
  AssertTrue('out of range raises', raised);
  FGrid.SelectedObject := FB3;
  AssertEquals('setting SelectedObject selects it alone', 1, FGrid.SelectedCount);
  AssertSame('a component alone is SelectedComponent', FB3, FGrid.SelectedComponent);
  FGrid.SelectObjects([]);
  AssertEquals('empty', 0, FGrid.SelectedCount);
  AssertNull('nothing', FGrid.SelectedObject);
  AssertEquals('no rows', 0, FGrid.RowCount);
end;

initialization
  RegisterTest(TPropertyGridMultiTest);
end.
