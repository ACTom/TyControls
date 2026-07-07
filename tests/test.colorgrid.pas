unit test.colorgrid;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Graphics, fpcunit, testregistry,
  tyControls.Types, tyControls.ColorGrid;
type
  TColorGridTest = class(TTestCase)
  published
    procedure TestDefaultPalette;
    procedure TestColumnsDefault;
    procedure TestSetColumns;
    procedure TestColumnsClamp;
    procedure TestAddColor;
    procedure TestSelected;
  end;
implementation

procedure TColorGridTest.TestDefaultPalette;
var g: TTyColorGrid;
begin
  g := TTyColorGrid.Create(nil);
  try
    // Constructor seeds the classic 16-colour VGA palette.
    AssertEquals('seeded palette', 16, g.ColorCount);
  finally g.Free; end;
end;

procedure TColorGridTest.TestColumnsDefault;
var g: TTyColorGrid;
begin
  g := TTyColorGrid.Create(nil);
  try
    AssertEquals('default columns', 8, g.Columns);
  finally g.Free; end;
end;

procedure TColorGridTest.TestSetColumns;
var g: TTyColorGrid;
begin
  g := TTyColorGrid.Create(nil);
  try
    g.Columns := 4;
    AssertEquals('columns stick', 4, g.Columns);
  finally g.Free; end;
end;

procedure TColorGridTest.TestColumnsClamp;
var g: TTyColorGrid;
begin
  g := TTyColorGrid.Create(nil);
  try
    g.Columns := 0;
    AssertEquals('clamped to >= 1', 1, g.Columns);
    g.Columns := -5;
    AssertEquals('negative clamped to 1', 1, g.Columns);
  finally g.Free; end;
end;

procedure TColorGridTest.TestAddColor;
var g: TTyColorGrid; n: Integer;
begin
  g := TTyColorGrid.Create(nil);
  try
    n := g.ColorCount;
    g.AddColor(clSkyBlue);
    AssertEquals('grows by one', n + 1, g.ColorCount);
  finally g.Free; end;
end;

procedure TColorGridTest.TestSelected;
var g: TTyColorGrid;
begin
  g := TTyColorGrid.Create(nil);
  try
    AssertTrue('initial selected clNone', g.Selected = clNone);
    g.Selected := clRed;
    AssertTrue('selected set/get', g.Selected = clRed);
    g.Selected := clBlue;
    AssertTrue('selected updates', g.Selected = clBlue);
  finally g.Free; end;
end;

initialization
  RegisterTest(TColorGridTest);
end.
