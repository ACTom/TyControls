unit test.headerautosize;
{ #126: TTyTreeView's Header.AutoSizeIndex column fills the rest of the width after any header
  change, not only after a resize; and EmptyListMessage repaints. }
{$mode objfpc}{$H+}
interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  tyControls.Columns, tyControls.TreeView;

type
  TTreePaintProbe = class(TTyTreeView)
  public
    Invalidations: Integer;
    procedure Invalidate; override;
  end;

  THeaderAutoSizeTest = class(TTestCase)
  published
    procedure TestTreeAutoSizeFollowsAColumnResize;
    procedure TestTreeEmptyListMessageRepaints;
  end;

implementation

procedure TTreePaintProbe.Invalidate;
begin
  Inc(Invalidations);
  inherited Invalidate;
end;

procedure THeaderAutoSizeTest.TestTreeAutoSizeFollowsAColumnResize;
var
  t: TTyTreeView;
  c0, c1, c2: TTyColumn;
begin
  t := TTyTreeView.Create(nil);
  try
    t.Font.PixelsPerInch := 96;
    t.SetBounds(0, 0, 300, 200);
    c0 := t.Header.Columns.Add as TTyColumn;
    c0.Width := 100;
    c1 := t.Header.Columns.Add as TTyColumn;
    c1.Width := 50;
    c2 := t.Header.Columns.Add as TTyColumn;
    c2.Width := 80;
    t.Header.AutoSizeIndex := 1;
    t.Header.Options := [hoVisible, hoColumnResize, hoAutoResize];
    AssertEquals('the auto column takes the rest', t.ContentRect.Width - 180, c1.Width);
    c0.Width := 150;
    AssertEquals('and gives up what a neighbour took', t.ContentRect.Width - 230, c1.Width);
  finally
    t.Free;
  end;
end;

procedure THeaderAutoSizeTest.TestTreeEmptyListMessageRepaints;
var
  t: TTreePaintProbe;
begin
  t := TTreePaintProbe.Create(nil);
  try
    t.Invalidations := 0;
    t.EmptyListMessage := 'Nothing here';
    AssertTrue('an empty tree shows it at once', t.Invalidations > 0);
  finally
    t.Free;
  end;
end;

initialization
  RegisterTest(THeaderAutoSizeTest);
end.
