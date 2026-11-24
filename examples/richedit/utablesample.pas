unit utablesample;

{ Samples > A Table: a short document whose table is more than a plain grid - built with the
  builder (TTyRichBuilder), as the documentation's example in "Tables" shows it, and put in as
  a new document (SetContent), ready to edit: a shaded header row, an outline thicker than the
  lines inside, the table centred, a last row of a fixed height and its cells' content in the
  middle of them. Its text is the example's resource strings, so it reads in the language the
  example runs in. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, tyControls.RichEdit.Model, tyControls.RichEdit.RowFormat,
  tyControls.RichEdit.TableProps, tyControls.RichEdit.Builder, tyControls.RichEdit;

{ The price table into B: four columns, a header, three items and a total. }
procedure AddPriceTable(B: TTyRichBuilder);

{ The whole sample - a heading, a line about the table, the table, a line after it - as Rich's
  new content. }
procedure ShowTableSample(Rich: TTyRichEdit);

resourcestring
  rsTsTitle   = 'A price list';
  rsTsAbout   = 'The table below is centred; its header row is shaded, its outline is thicker ' +
                'than the lines inside it, and its last row has a fixed height with its ' +
                'content in the middle. Select cells and try the Table menu, the borders and ' +
                'the shading on the tool bar, or Table Properties.';
  rsTsItem    = 'Item';
  rsTsCount   = 'Count';
  rsTsPrice   = 'Price';
  rsTsAmount  = 'Amount';
  rsTsPencil  = 'Pencil';
  rsTsEraser  = 'Eraser';
  rsTsNotes   = 'Notebook';
  rsTsTotal   = 'Total';
  rsTsAfter   = 'A paragraph after the table.';

implementation

{ This procedure is the documentation's example ("Tables", docs/controls/richedit.md), word
  for word: kept here so that it is compiled with the example. }
procedure AddPriceTable(B: TTyRichBuilder);
const
  Outline = 30;                         // 1½ pt, in twips; the lines inside stay ½ pt
  Shade = TColor($00F7EBDD);            // a light blue ($BBGGRR)
var
  r, c: Integer;
  cells: array[0..4, 0..3] of string;

  // the open cell's sides on the table's edge get the thicker line
  procedure Edge(ARow, ACol: Integer);
  var
    sides: TTyRowCellSides;
  begin
    sides := [];
    if ARow = 0 then Include(sides, rcsTop);
    if ARow = 4 then Include(sides, rcsBottom);
    if ACol = 0 then Include(sides, rcsLeft);
    if ACol = 3 then Include(sides, rcsRight);
    if sides <> [] then B.CellBorders(sides, rbsSingle, Outline);
  end;

begin
  cells[0, 0] := rsTsItem;   cells[0, 1] := rsTsCount; cells[0, 2] := rsTsPrice; cells[0, 3] := rsTsAmount;
  cells[1, 0] := rsTsPencil; cells[1, 1] := '12';      cells[1, 2] := '1.50';    cells[1, 3] := '18.00';
  cells[2, 0] := rsTsEraser; cells[2, 1] := '5';       cells[2, 2] := '2.00';    cells[2, 3] := '10.00';
  cells[3, 0] := rsTsNotes;  cells[3, 1] := '3';       cells[3, 2] := '8.50';    cells[3, 3] := '25.50';
  cells[4, 0] := rsTsTotal;  cells[4, 1] := '';        cells[4, 2] := '';        cells[4, 3] := '53.50';
  B.Table([2400, 1300, 1500, 1800]).TableAlign(rraCenter);
  for r := 0 to 4 do
  begin
    if r = 4 then B.Row(480, True)      // exactly 480 twips (24 points) high
    else if r > 0 then B.Row;
    for c := 0 to 3 do
    begin
      B.Cell;
      Edge(r, c);
      if r = 0 then B.Shading(Shade).Bold;
      if r = 4 then B.CellVAlign(rcvCenter).Bold;
      if c > 0 then B.Align(paraRight);
      B.Text(cells[r, c]).Reset;
    end;
  end;
  B.EndTable;
end;

procedure ShowTableSample(Rich: TTyRichEdit);
var
  B: TTyRichBuilder;
begin
  B := Rich.NewBuilder;
  try
    B.Font('', 16).Bold.Text(rsTsTitle).Reset;
    B.Paragraph.SpaceAfter(6).Text(rsTsAbout);
    AddPriceTable(B);
    B.Paragraph.SpaceBefore(6).Text(rsTsAfter);
    Rich.SetContent(B);
  finally
    B.Free;
  end;
end;

end.
