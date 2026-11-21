unit test.richedit.tablepaint;

{ How a table row is drawn (TTyRowLayout.Paint) from its cells' properties: the shading under
  the text, the colour and the four styles of a line, the padding that moves the text, a line
  two cells share drawn once (the wider, the later at the same width), automatic text on a
  shading, lines on whole pixels at 150 and 200 %, and Word's own styled table sampled place
  by place. Rows are laid out with the test device and painted on a ground no painting
  produces. No control, no window. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, fpcunit, testregistry, BGRABitmap, BGRABitmapTypes,
  tyControls.RichEdit.Text, tyControls.RichEdit.Model, tyControls.RichEdit.Commands,
  tyControls.RichEdit.RowFormat, tyControls.RichEdit.TableProps, tyControls.RichEdit.RtfRead,
  tyControls.RichEdit.Layout, test.richedit.layoutdevice;

type
  TTyRichTablePaintTest = class(TTestCase)
  published
    procedure TestShadingFillsTheCellUnderItsText;
    procedure TestBorderColourAndStyle;
    procedure TestPaddingMovesTheText;
    procedure TestASharedEdgeIsDrawnOnce;
    procedure TestAutomaticTextContrastsWithShading;
    procedure TestCrispAt150And200;
    procedure TestWordsStyledTableAsWordDrawsIt;
    procedure TestAnExactRowCutsItsContent;
  end;

implementation

const
  // where a block is painted in the bitmap
  OX = 4;
  OY = 4;

function Ground: TBGRAPixel;
begin
  // (magenta: no shading, line or text of these tests is)
  Result := BGRA(255, 0, 255, 255);
end;

function SamePx(const A, B: TBGRAPixel): Boolean;
begin
  Result := (A.red = B.red) and (A.green = B.green) and (A.blue = B.blue);
end;

function Px(AColor: TColor): TBGRAPixel;
begin
  Result := ColorToBGRA(ColorToRGB(AColor));
end;

function BytesOf(const S: RawByteString): TBytes;
begin
  Result := nil;
  SetLength(Result, Length(S));
  if S <> '' then Move(S[1], Result[0], Length(S));
end;

function NewDoc(const AText: UTF8String): TTyRichDocument;
begin
  Result := TTyRichDocument.CreateFromUtf8(BytesOf(AText));
end;

function FixtureBytes(const AName: string): TBytes;
var
  f: TFileStream;
begin
  Result := nil;
  f := TFileStream.Create(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'tests' + PathDelim +
    'fixtures' + PathDelim + 'rtf' + PathDelim + AName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, f.Size);
    if f.Size > 0 then f.ReadBuffer(Result[0], f.Size);
  finally
    f.Free;
  end;
end;

function LoadDoc(const ABytes: TBytes): TTyRichDocument;
var
  s: TBytesStream;
begin
  Result := TTyRichDocument.Create;
  s := TBytesStream.Create(ABytes);
  try
    TyRichLoadRtf(Result, s);
  finally
    s.Free;
  end;
end;

{ 'before', an ARows x ACols table, 'rNcM' in each cell, 'after'; no history. }
function TableDoc(ARows, ACols: Integer): TTyRichDocument;
var
  r, c, f, l: Integer;
begin
  Result := NewDoc('before' + #13#10 + 'after');
  if not Result.Execute(TTyRichInsertTable.Create(Result.Text.ParaStart(1), ARows, ACols, 1440 * ACols)) then
    raise Exception.Create('no table');
  for r := 0 to ARows - 1 do
    for c := 0 to ACols - 1 do
    begin
      if not Result.TableCellParas(1, r, c, f, l) then raise Exception.Create('no cell');
      Result.Execute(TTyRichInsertText.Create(Result.Text.ParaStart(f), Format('r%dc%d', [r, c]),
        TyRichInheritFormat, False));
    end;
  Result.ClearUndo;
end;

procedure SetCells(ADoc: TTyRichDocument; ARow0, ACol0, ARow1, ACol1: Integer;
  const AProps: TTyRichCellProps);
begin
  if not ADoc.Execute(TTyRichSetCellProps.Create(ADoc.Text.ParaStart(1), ARow0, ACol0, ARow1,
    ACol1, AProps)) then
    raise Exception.Create('refused');
end;

function Borders(const ASides: array of TTyRichCellSide; const B: TTyRichBorder): TTyRichCellProps;
const
  Prop: array[TTyRichCellSide] of TTyRichCellProp = (rcpBorderLeft, rcpBorderTop, rcpBorderRight,
    rcpBorderBottom);
var
  i: Integer;
begin
  Result := Default(TTyRichCellProps);
  for i := 0 to High(ASides) do
  begin
    Include(Result.Valid, Prop[ASides[i]]);
    Result.Borders[ASides[i]] := B;
  end;
end;

type
  { A row laid out and painted: the layout (held) and the bitmap it was painted into, at
    OX, OY. }
  TPainted = class
    Row: TTyRowLayout;
    Bmp: TBGRABitmap;
    destructor Destroy; override;
    function At(AX, AY: Integer): TBGRAPixel;   // block-relative
  end;

destructor TPainted.Destroy;
begin
  Bmp.Free;
  if Row <> nil then Row.Release;
  inherited Destroy;
end;

function TPainted.At(AX, AY: Integer): TBGRAPixel;
begin
  Result := Bmp.GetPixel(OX + AX, OY + AY);
end;

function PaintRow(ADoc: TTyRichDocument; APara: Integer; const AStyle: TTyRichPaintStyle;
  APPI: Integer = 96; AWidth: Integer = 2000): TPainted;
var
  lay: TTyRichLayouter;
  b: TTyBlockLayout;
begin
  Result := TPainted.Create;
  lay := TTyRichLayouter.Create(TTyRichTestDevice.Create, True);
  try
    b := lay.LayoutBlock(ADoc, APara, AWidth, APPI, 1.0);
    TAssert.AssertTrue('a row', b is TTyRowLayout);
    Result.Row := TTyRowLayout(b);
    Result.Bmp := TBGRABitmap.Create(Result.Row.Width + 2 * OX, Result.Row.Height + 2 * OY, Ground);
    Result.Row.Paint(Result.Bmp, OX, OY, Rect(0, 0, Result.Bmp.Width, Result.Bmp.Height), AStyle, 0, 0);
  finally
    lay.Free;
  end;
end;

function Style: TTyRichPaintStyle;
begin
  Result := TyRichDefaultPaintStyle;
  Result.TableBorder := BGRA(128, 128, 128, 255);
  Result.TextColor := BGRA(0, 0, 0, 255);
end;

{ ---- the tests ---- }

procedure TTyRichTablePaintTest.TestShadingFillsTheCellUnderItsText;
var
  d: TTyRichDocument;
  p: TTyRichCellProps;
  r: TPainted;
  c0, c1: TTyRichCellBox;
  it: TTyRichRowItem;
begin
  d := TableDoc(1, 2);
  try
    p := Default(TTyRichCellProps);
    p.Valid := [rcpShading];
    p.Shading := clYellow;
    SetCells(d, 0, 0, 0, 0, p);
    r := PaintRow(d, 1, Style);
    try
      c0 := r.Row.Cells[0];
      c1 := r.Row.Cells[1];
      AssertTrue('the shaded cell, in its padding', SamePx(Px(clYellow), r.At(c0.Left + 3, r.Row.Height div 2)));
      AssertTrue('and right of its text', SamePx(Px(clYellow), r.At(c0.Right - 4, r.Row.Height div 2)));
      AssertTrue('the other cell: the ground', SamePx(Ground, r.At(c1.Left + 3, r.Row.Height div 2)));
      // the text over it: the glyph boxes the test device draws, in the text's colour
      it := r.Row.Items[0];
      AssertTrue('its text drawn over it', SamePx(BGRA(0, 0, 0), r.At(it.X + 2, it.Y + it.Layout.Height div 2)));
      AssertTrue('its line over it', SamePx(BGRA(128, 128, 128), r.At(c0.Left, 0)));
    finally
      r.Free;
    end;
  finally
    d.Free;
  end;
end;

procedure TTyRichTablePaintTest.TestBorderColourAndStyle;
const
  Styles: array[0..3] of TTyRichBorderStyle = (rbsSingle, rbsDouble, rbsDotted, rbsDashed);
var
  d: TTyRichDocument;
  r: TPainted;
  k, x, y, n: Integer;
  c: TTyRichCellBox;
  on: array of Boolean;
begin
  for k := 0 to High(Styles) do
  begin
    d := TableDoc(1, 1);
    try
      // 60 twips: 4 pixels at 96 pixels an inch
      SetCells(d, 0, 0, 0, 0, Borders([rcsTop, rcsLeft], TyRichBorder(Styles[k], 60, clRed)));
      r := PaintRow(d, 1, Style);
      try
        c := r.Row.Cells[0];
        case Styles[k] of
          rbsSingle:
            begin
              AssertEquals('single: 4 pixels', 4, c.LinePx[rcsTop]);
              for y := 0 to 3 do
                AssertTrue(Format('single: row %d red', [y]), SamePx(Px(clRed), r.At(c.Left + 20, y)));
              AssertFalse('single: and no more', SamePx(Px(clRed), r.At(c.Left + 20, 4)));
            end;
          rbsDouble:
            begin
              // two lines of half the width, the gap as wide
              AssertEquals('double: 6 pixels across', 6, c.LinePx[rcsTop]);
              for y := 0 to 5 do
                AssertEquals(Format('double: row %d', [y]), y in [0, 1, 4, 5],
                  SamePx(Px(clRed), r.At(c.Left + 20, y)));
              for x := 0 to 5 do
                AssertEquals(Format('double, left: column %d', [x]), x in [0, 1, 4, 5],
                  SamePx(Px(clRed), r.At(c.Left + x, r.Row.Height - 3)));
            end;
          rbsDotted, rbsDashed:
            begin
              on := nil;
              SetLength(on, 40);
              for x := 0 to 39 do on[x] := SamePx(Px(clRed), r.At(c.Left + 10 + x, 1));
              n := 0;
              for x := 1 to 39 do
                if on[x] <> on[x - 1] then Inc(n);
              // dots 4 on 4 off: a change every 4 pixels; dashes 12 on 8 off
              if Styles[k] = rbsDotted then
                AssertTrue(Format('dotted: %d changes in 40 pixels', [n]), (n >= 8) and (n <= 10))
              else
                AssertTrue(Format('dashed: %d changes in 40 pixels', [n]), (n >= 3) and (n <= 5));
              for x := 0 to 39 do
                if not on[x] then
                  AssertTrue('between the pieces the ground', SamePx(Ground, r.At(c.Left + 10 + x, 1)));
            end;
        end;
      finally
        r.Free;
      end;
    finally
      d.Free;
    end;
  end;
end;

procedure TTyRichTablePaintTest.TestPaddingMovesTheText;
var
  d: TTyRichDocument;
  p: TTyRichCellProps;
  rp: TTyRichRowProps;
  r: TPainted;
  it: TTyRichRowItem;
  c: TTyRichCellBox;
  h0: Integer;
begin
  d := TableDoc(1, 2);
  try
    r := PaintRow(d, 1, Style);
    try
      it := r.Row.Items[0];
      c := r.Row.Cells[0];
      // the row's default: the half gap, 108 twips (7 pixels)
      AssertEquals('by the row''s padding', c.Left + 7, it.X);
      AssertEquals('below the top line', 1, it.Y);
      h0 := r.Row.Height;
    finally
      r.Free;
    end;
    p := Default(TTyRichCellProps);
    p.Valid := [rcpPadLeft, rcpPadTop, rcpPadBottom];
    p.Pad[rcsLeft] := 600;
    p.Pad[rcsTop] := 300;
    p.Pad[rcsBottom] := 150;
    SetCells(d, 0, 0, 0, 0, p);
    r := PaintRow(d, 1, Style);
    try
      it := r.Row.Items[0];
      c := r.Row.Cells[0];
      AssertEquals('its own left padding: 40 pixels', c.Left + 40, it.X);
      AssertEquals('its own top: 20 pixels below the line', 1 + 20, it.Y);
      AssertEquals('the row taller by its top and bottom', h0 + 20 + 10, r.Row.Height);
      AssertTrue('the text where it moved', SamePx(BGRA(0, 0, 0), r.At(it.X + 2, it.Y + 3)));
      AssertTrue('nothing where it was', SamePx(Ground, r.At(c.Left + 9, 3)));
      AssertEquals('the other cell keeps the row''s', r.Row.Cells[1].Left + 7, r.Row.Items[1].X);
    finally
      r.Free;
    end;
    // the row's default for both
    rp := Default(TTyRichRowProps);
    rp.Valid := [rrpPad];
    rp.DefaultPad[rcsLeft] := 300;
    rp.DefaultPad[rcsTop] := -1;
    rp.DefaultPad[rcsRight] := -1;
    rp.DefaultPad[rcsBottom] := -1;
    AssertTrue('the row''s', d.Execute(TTyRichSetRowProps.Create(d.Text.ParaStart(1), 0, 0, rp)));
    r := PaintRow(d, 1, Style);
    try
      AssertEquals('a cell without its own: the row''s', r.Row.Cells[1].Left + 20, r.Row.Items[1].X);
      AssertEquals('a cell with its own keeps it', r.Row.Cells[0].Left + 40, r.Row.Items[0].X);
    finally
      r.Free;
    end;
  finally
    d.Free;
  end;
end;

procedure TTyRichTablePaintTest.TestASharedEdgeIsDrawnOnce;
var
  d: TTyRichDocument;
  r, r1: TPainted;
  c0, c1: TTyRichCellBox;
  y: Integer;
begin
  // across: the wider one, drawn by the cell that declares it
  d := TableDoc(2, 2);
  try
    SetCells(d, 0, 0, 1, 0, Borders([rcsRight], TyRichBorder(rbsSingle, 60, clRed)));
    SetCells(d, 0, 1, 1, 1, Borders([rcsLeft], TyRichBorder(rbsSingle, 15, clBlue)));
    r := PaintRow(d, 1, Style);
    try
      c0 := r.Row.Cells[0];
      c1 := r.Row.Cells[1];
      y := r.Row.Height div 2;
      AssertTrue('the wider red one', SamePx(Px(clRed), r.At(c0.Right - 1, y)) and
        SamePx(Px(clRed), r.At(c0.Right - 4, y)));
      AssertFalse('the narrower blue one is not drawn', rcsLeft in c1.Sides);
      AssertFalse('no blue', SamePx(Px(clBlue), r.At(c1.Left, y)));
    finally
      r.Free;
    end;
    // the same width: the later cell's
    SetCells(d, 0, 1, 1, 1, Borders([rcsLeft], TyRichBorder(rbsSingle, 60, clBlue)));
    r := PaintRow(d, 1, Style);
    try
      c0 := r.Row.Cells[0];
      c1 := r.Row.Cells[1];
      y := r.Row.Height div 2;
      AssertFalse('the earlier one is not drawn', rcsRight in c0.Sides);
      AssertTrue('the later one is', SamePx(Px(clBlue), r.At(c1.Left, y)) and
        SamePx(Px(clBlue), r.At(c1.Left + 3, y)));
      AssertFalse('no red', SamePx(Px(clRed), r.At(c0.Right - 1, y)));
    finally
      r.Free;
    end;
    // down: row 0's bottom against row 1's top
    SetCells(d, 0, 0, 0, 0, Borders([rcsBottom], TyRichBorder(rbsSingle, 60, clGreen)));
    SetCells(d, 1, 0, 1, 0, Borders([rcsTop], TyRichBorder(rbsDotted, 15, clBlue)));
    r := PaintRow(d, 1, Style);
    r1 := PaintRow(d, 3, Style);
    try
      AssertTrue('the upper wider one drawn by its row', SamePx(Px(clGreen),
        r.At(r.Row.Cells[0].Left + 20, r.Row.Height - 1)));
      AssertFalse('the lower row draws no top there', rcsTop in r1.Row.Cells[0].Sides);
      AssertTrue('the lower row''s other cell keeps its top', rcsTop in r1.Row.Cells[1].Sides);
    finally
      r1.Free;
      r.Free;
    end;
    SetCells(d, 1, 0, 1, 0, Borders([rcsTop], TyRichBorder(rbsDotted, 60, clBlue)));
    r := PaintRow(d, 1, Style);
    r1 := PaintRow(d, 3, Style);
    try
      AssertFalse('at the same width the upper draws none', rcsBottom in r.Row.Cells[0].Sides);
      AssertTrue('the lower one''s', (rcsTop in r1.Row.Cells[0].Sides) and
        (r1.Row.Cells[0].LineStyle[rcsTop] = rbsDotted));
    finally
      r1.Free;
      r.Free;
    end;
  finally
    d.Free;
  end;
end;

procedure TTyRichTablePaintTest.TestAutomaticTextContrastsWithShading;
var
  d: TTyRichDocument;
  p: TTyRichCellProps;
  r: TPainted;
  st: TTyRichPaintStyle;
  it: TTyRichRowItem;
  q: TBGRAPixel;
begin
  // a dark skin: light text; a light shading
  st := Style;
  st.TextColor := BGRA(235, 235, 235, 255);
  d := TableDoc(1, 2);
  try
    p := Default(TTyRichCellProps);
    p.Valid := [rcpShading];
    p.Shading := RGBToColor(255, 255, 204);
    SetCells(d, 0, 0, 0, 0, p);
    r := PaintRow(d, 1, st);
    try
      it := r.Row.Items[0];
      q := r.At(it.X + 2, it.Y + it.Layout.Height div 2);
      // the opposite of the theme's text colour, as on a light highlight
      AssertTrue(Format('on the shading: dark (%d,%d,%d)', [q.red, q.green, q.blue]),
        SamePx(BGRA(20, 20, 20), q));
      it := r.Row.Items[1];
      q := r.At(it.X + 2, it.Y + it.Layout.Height div 2);
      AssertTrue('no shading: the theme''s', SamePx(BGRA(235, 235, 235), q));
    finally
      r.Free;
    end;
    // a dark shading keeps the light text
    p.Shading := RGBToColor(0, 0, 96);
    SetCells(d, 0, 0, 0, 0, p);
    r := PaintRow(d, 1, st);
    try
      it := r.Row.Items[0];
      AssertTrue('on a dark shading: light', SamePx(BGRA(235, 235, 235),
        r.At(it.X + 2, it.Y + it.Layout.Height div 2)));
    finally
      r.Free;
    end;
  finally
    d.Free;
  end;
end;

procedure TTyRichTablePaintTest.TestCrispAt150And200;
const
  PPIs: array[0..1] of Integer = (144, 192);
var
  d: TTyRichDocument;
  r: TPainted;
  k, x, y, w: Integer;
  c: TTyRichCellBox;
  q: TBGRAPixel;
begin
  d := TableDoc(1, 2);
  try
    // 30 twips: 3 pixels at 144, 4 at 192
    SetCells(d, 0, 0, 0, 1, Borders([rcsTop, rcsLeft, rcsBottom], TyRichBorder(rbsSingle, 30, clRed)));
    for k := 0 to High(PPIs) do
    begin
      r := PaintRow(d, 1, Style, PPIs[k]);
      try
        c := r.Row.Cells[1];
        w := c.LinePx[rcsTop];
        AssertEquals(Format('%d: the width in whole pixels', [PPIs[k]]), 30 * PPIs[k] div 1440, w);
        // every pixel of the line its colour, the ones beside it untouched (no blend)
        // (right of the left line, which runs on below it)
        for x := c.Left + w to c.Right - 2 do
        begin
          for y := 0 to w - 1 do
          begin
            q := r.At(x, y);
            AssertTrue(Format('%d: line pixel %d,%d', [PPIs[k], x, y]), SamePx(Px(clRed), q));
          end;
          q := r.At(x, w);
          AssertFalse(Format('%d: below it no red', [PPIs[k]]), SamePx(Px(clRed), q));
          AssertTrue(Format('%d: below it no blend', [PPIs[k]]), SamePx(Ground, q) or
            (q.red = q.green));
        end;
        for y := w to r.Row.Height - w - 1 do
          AssertTrue(Format('%d: the left line''s column', [PPIs[k]]),
            SamePx(Px(clRed), r.At(c.Left + w - 1, y)) and not SamePx(Px(clRed), r.At(c.Left + w, y)));
      finally
        r.Free;
      end;
    end;
  finally
    d.Free;
  end;
end;

procedure TTyRichTablePaintTest.TestWordsStyledTableAsWordDrawsIt;
var
  d: TTyRichDocument;
  r0, r1: TPainted;
  c: TTyRichCellBox;
  it: TTyRichRowItem;
  i, k, x, y, ons, offs: Integer;
  red, blue, green, yellow, lightGreen: TBGRAPixel;
  info: TTyRichTableInfo;
begin
  red := BGRA(255, 0, 0);
  blue := BGRA(0, 0, 255);
  green := BGRA(0, 128, 0);
  yellow := BGRA(255, 255, 0);
  lightGreen := BGRA(204, 255, 204);
  d := LoadDoc(FixtureBytes('word-table-styled.rtf'));
  try
    k := 0;
    while d.CellAt(k) = nil do Inc(k);
    AssertTrue('the table', d.TableInfoAt(k, info));
    r0 := PaintRow(d, k, Style);
    r1 := PaintRow(d, k + 3, Style);
    try
      // the red double outside border: two lines, the ground between them (cell 1,2's top)
      c := r0.Row.Cells[1];
      AssertEquals('double: three pixels across', 3, c.LinePx[rcsTop]);
      AssertTrue('the outer red line', SamePx(red, r0.At(c.Left + 30, 0)));
      AssertTrue('the ground between', SamePx(Ground, r0.At(c.Left + 30, 1)));
      AssertTrue('the inner red line', SamePx(red, r0.At(c.Left + 30, 2)));
      // and the table's left (cell 1,1, over its yellow)
      c := r0.Row.Cells[0];
      AssertTrue('the left: red, yellow, red', SamePx(red, r0.At(c.Left, 10)) and
        SamePx(yellow, r0.At(c.Left + 1, 10)) and SamePx(red, r0.At(c.Left + 2, 10)));
      // cell 1,1 yellow
      AssertTrue('cell 1,1: yellow', SamePx(yellow, r0.At(c.Right - 4, r0.Row.Height div 2)));
      // the blue dotted inside border: cell 1,2's left, with gaps
      c := r0.Row.Cells[1];
      ons := 0;
      offs := 0;
      for y := 4 to r0.Row.Height - 3 do
        if SamePx(blue, r0.At(c.Left, y)) then Inc(ons) else Inc(offs);
      AssertTrue(Format('dotted: %d blue, %d gaps', [ons, offs]), (ons > 2) and (offs > 2));
      // cell 2,2: light green, its text 10 pt in from its left edge and 5 pt below its line
      c := r1.Row.Cells[1];
      AssertTrue('cell 2,2: light green', SamePx(lightGreen, r1.At(c.Left + 5, r1.Row.Height - 4)));
      i := c.FirstItem;
      it := r1.Row.Items[i];
      AssertEquals('10 pt in (13 pixels)', c.Left + 13, it.X);
      AssertEquals('5 pt below its top line (7 pixels)', c.LinePx[rcsTop] + 7, it.Y);
      { cell 1,3's bottom: green, dashed, 45 twips. Word writes the same line as cell 2,3's
        top (\clbrdrt\brdrdash\brdrw45\brdrcf11 - not the blue dotted the other tops are):
        one line, drawn once - by the later cell at the same width - green and dashed, the
        blue dotted lines beside it not over it }
      c := r1.Row.Cells[2];
      AssertFalse('cell 1,3 draws no bottom', rcsBottom in r0.Row.Cells[2].Sides);
      AssertTrue('cell 2,3 draws it as its top', (rcsTop in c.Sides) and
        (c.LineStyle[rcsTop] = rbsDashed) and (c.LinePx[rcsTop] = 3));
      ons := 0;
      offs := 0;
      for x := c.Left + 4 to c.Right - 4 do
        if SamePx(green, r1.At(x, 1)) then Inc(ons)
        else
        begin
          Inc(offs);
          AssertFalse('no blue in its gaps', SamePx(blue, r1.At(x, 1)));
        end;
      AssertTrue(Format('dashed: %d green, %d gaps', [ons, offs]), (ons > 10) and (offs > 5));
      // and against a narrower line the wider wins: cell 2,2's top is blue dotted, 1 pixel
      AssertEquals('the blue dotted top beside it', 1, r1.Row.Cells[1].LinePx[rcsTop]);
    finally
      r1.Free;
      r0.Free;
    end;
  finally
    d.Free;
  end;
end;

procedure TTyRichTablePaintTest.TestAnExactRowCutsItsContent;
var
  d: TTyRichDocument;
  rp: TTyRichRowProps;
  r: TPainted;
  f, l: Integer;
begin
  d := TableDoc(1, 1);
  try
    // five lines in the cell, the row exactly 300 twips (20 pixels)
    d.TableCellParas(1, 0, 0, f, l);
    d.Execute(TTyRichInsertText.Create(d.Text.ParaStart(f), 'a'#13#10'b'#13#10'c'#13#10'd'#13#10));
    rp := Default(TTyRichRowProps);
    rp.Valid := [rrpHeight];
    rp.HeightTwips := -300;
    AssertTrue('exactly', d.Execute(TTyRichSetRowProps.Create(d.Text.ParaStart(1), 0, 0, rp)));
    r := PaintRow(d, 1, Style);
    try
      AssertEquals('the row as high as it says', 20, r.Row.Height);
      AssertTrue('nothing below it is painted', SamePx(Ground, r.Bmp.GetPixel(OX + 10, OY + 21)));
    finally
      r.Free;
    end;
    rp.HeightTwips := 3000;
    AssertTrue('at least', d.Execute(TTyRichSetRowProps.Create(d.Text.ParaStart(1), 0, 0, rp)));
    r := PaintRow(d, 1, Style);
    try
      AssertEquals('at least 200 pixels', 200, r.Row.Height);
    finally
      r.Free;
    end;
  finally
    d.Free;
  end;
end;

initialization
  RegisterTest(TTyRichTablePaintTest);
end.
