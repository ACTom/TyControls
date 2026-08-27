unit test.dialogs.imagecollectioneditor;
{$mode objfpc}{$H+}
{ The image-collection manager dialog, tested through its construct-only builder and
  public action seams -- no window is ever shown. The working-copy contract is the
  load-bearing assertion: edits touch only the copy, CommitTo applies them, and a
  discarded dialog leaves the source exactly as it was. }
interface

uses
  Classes, SysUtils, Types, Controls, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.ImageCollection, tyControls.Dialogs.ImageCollectionEditor;

type
  TImageCollectionEditorTest = class(TTestCase)
  private
    FSource: TTyImageCollection;
    FTempPng: string;
    function NewEditor: TTyImageCollectionEditorForm;
    procedure AddMaster(const AName: string; ASize: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure LoadShowsEveryMasterWithItsSize;
    procedure AddFromFileNamesAfterTheFile;
    procedure ReplaceKeepsTheName;
    procedure RenameRenamesTheWholeFamily;
    procedure MoveAndDeleteKeepOrderAndSelectionSane;
    procedure CommitAppliesAndNoCommitLeavesTheSourceAlone;
  end;

implementation

procedure TImageCollectionEditorTest.SetUp;
begin
  FSource := TTyImageCollection.Create(nil);
  AddMaster('app', 16);
  AddMaster('door', 24);
  FTempPng := GetTempDir(False) + 'ty_imgcoled_' + IntToStr(GetProcessID) + '.png';
end;

procedure TImageCollectionEditorTest.TearDown;
begin
  FSource.Free;
  DeleteFile(FTempPng);
end;

procedure TImageCollectionEditorTest.AddMaster(const AName: string; ASize: Integer);
var
  bmp: TBGRABitmap;
  it: TTyImageItem;
begin
  bmp := TBGRABitmap.Create(ASize, ASize, BGRA(200, 60, 60));
  try
    it := FSource.Images.Add;
    it.ImageName := AName;
    it.SetBitmap(bmp);
  finally
    bmp.Free;
  end;
end;

function TImageCollectionEditorTest.NewEditor: TTyImageCollectionEditorForm;
begin
  Result := TyBuildImageCollectionEditor(FSource);
end;

procedure TImageCollectionEditorTest.LoadShowsEveryMasterWithItsSize;
var
  d: TTyImageCollectionEditorForm;
begin
  d := NewEditor;
  try
    AssertEquals('both masters listed', 2, d.EntryCount);
    AssertEquals('name and size in the row', 'app  (16x16)', d.EntryCaption(0));
    AssertEquals('second row', 'door  (24x24)', d.EntryCaption(1));
  finally
    d.Free;
  end;
end;

procedure TImageCollectionEditorTest.AddFromFileNamesAfterTheFile;
var
  d: TTyImageCollectionEditorForm;
  bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(8, 8, BGRA(0, 120, 250));
  try
    bmp.SaveToFile(FTempPng);
  finally
    bmp.Free;
  end;
  d := NewEditor;
  try
    AssertTrue('the file loads', d.AddFromFile(FTempPng));
    AssertEquals('one more master', 3, d.EntryCount);
    AssertEquals('named after the file, sized from its pixels',
      ChangeFileExt(ExtractFileName(FTempPng), '') + '  (8x8)', d.EntryCaption(2));
    AssertEquals('the new master is selected', 2, d.SelectedIndex);
    AssertFalse('a missing file is a False, not a crash',
      d.AddFromFile(FTempPng + '.missing'));
    AssertEquals('and adds nothing', 3, d.EntryCount);
  finally
    d.Free;
  end;
end;

procedure TImageCollectionEditorTest.ReplaceKeepsTheName;
var
  d: TTyImageCollectionEditorForm;
  bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(32, 32, BGRA(10, 200, 90));
  try
    bmp.SaveToFile(FTempPng);
  finally
    bmp.Free;
  end;
  d := NewEditor;
  try
    d.SelectEntry(0);
    AssertTrue('the replacement loads', d.ReplaceFromFile(FTempPng));
    AssertEquals('same name, new pixels', 'app  (32x32)', d.EntryCaption(0));
    AssertEquals('no new row', 2, d.EntryCount);
  finally
    d.Free;
  end;
end;

procedure TImageCollectionEditorTest.RenameRenamesTheWholeFamily;
var
  d: TTyImageCollectionEditorForm;
begin
  AddMaster('app', 32);    // a second resolution of 'app' -> the family has two masters
  d := NewEditor;
  try
    AssertEquals('three masters', 3, d.EntryCount);
    d.SelectEntry(0);
    d.RenameSelected('logo');
    AssertEquals('the selected master renamed', 'logo  (16x16)', d.EntryCaption(0));
    AssertEquals('its family member followed -- half-renamed families silently fall '
      + 'out of their multi-resolution set', 'logo  (32x32)', d.EntryCaption(2));
    AssertEquals('an unrelated name stays', 'door  (24x24)', d.EntryCaption(1));
  finally
    d.Free;
  end;
end;

procedure TImageCollectionEditorTest.MoveAndDeleteKeepOrderAndSelectionSane;
var
  d: TTyImageCollectionEditorForm;
begin
  d := NewEditor;
  try
    d.SelectEntry(0);
    d.MoveSelected(1);
    AssertEquals('moved down', 'app  (16x16)', d.EntryCaption(1));
    AssertEquals('selection followed', 1, d.SelectedIndex);
    d.MoveSelected(1);
    AssertEquals('a move past the end is a no-op', 1, d.SelectedIndex);
    d.DeleteSelected;
    AssertEquals('one master left', 1, d.EntryCount);
    AssertEquals('selection clamped onto it', 0, d.SelectedIndex);
  finally
    d.Free;
  end;
end;

procedure TImageCollectionEditorTest.CommitAppliesAndNoCommitLeavesTheSourceAlone;
var
  d: TTyImageCollectionEditorForm;
  target: TTyImageCollection;
begin
  d := NewEditor;
  try
    d.SelectEntry(0);
    d.DeleteSelected;
    AssertEquals('the WORKING COPY lost the master', 1, d.EntryCount);
    AssertEquals('the source did not -- that is the Cancel promise',
      2, FSource.Images.Count);

    target := TTyImageCollection.Create(nil);
    try
      d.CommitTo(target);
      AssertEquals('commit writes the copy out', 1, target.Images.Count);
      AssertEquals('with the surviving master', 'door', target.Images[0].ImageName);
    finally
      target.Free;
    end;
  finally
    d.Free;
  end;
end;

initialization
  RegisterTest(TImageCollectionEditorTest);

end.
