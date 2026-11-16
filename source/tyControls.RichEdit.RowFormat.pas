unit tyControls.RichEdit.RowFormat;

{ What a table row looks like on screen, read from the row's format as the file had it
  (TTyRichRow.RawFormat: the \trowd ... \cellx words an RTF row is defined with). The model
  keeps of a row only its cells and their right edges; how far the text stands off the cell
  edges, where the row starts, how tall it must be, which cells are merged, which of their
  borders are drawn and where a cell's content sits are only in those words, and this is
  where they are read. A pure function: bytes in, a record out. It reads nothing else and
  changes nothing - the reader and the writer do not use it, so what is read and written
  back stays exactly as it was.

  Read: \trgaph (half the gap between cells: the text's distance from a cell's left and right
  edges), \trleft (where the row starts), \trqc / \trqr (the row centred / at the right),
  \trrh (a row height: at least, or exactly when negative), and per cell, up to its \cellx:
  \clmgf / \clmrg (merged with the cells after it / the one before), \clvmgf / \clvmrg (the
  same with the rows below / above), \clvertalt / c / b (the content at the top, centre,
  bottom), \clbrdrl / t / r / b followed by a line style (\brdrs, \brdrdb, \brdrdot ...;
  \brdrnone, \brdrnil and \brdrtbl - what Word writes for every side of a cell in a table
  without borders - take the side away) and \brdrwN (the line's width). A diagonal
  (\cldglu, \cldgll) is no side: the words after it are not the side's. Every style is shown
  as a solid line in phase 1; border colours (\brdrcf) and cell shading need the colour table
  and are not read; nor are row-level borders (\trbrdr*), which Word and WordPad write beside
  the cells' own, or diagonals. Words inside groups are passed over, and so are the bytes of
  \binN. }

{$mode objfpc}{$H+}

interface

type
  TTyRowCellMerge = (rcmNone, rcmFirst, rcmContinue);
  TTyRowCellVAlign = (rcvTop, rcvCenter, rcvBottom);
  TTyRowCellSide = (rcsLeft, rcsTop, rcsRight, rcsBottom);
  TTyRowCellSides = set of TTyRowCellSide;

  TTyRowAlign = (rraLeft, rraCenter, rraRight);

  TTyRowCellDisplay = record
    Right: Integer;                 // \cellx, twips (as written: may be negative)
    HasRight: Boolean;              // False: the cell's \cellx had no number (Right is 0)
    HMerge: TTyRowCellMerge;        // \clmgf, \clmrg
    VMerge: TTyRowCellMerge;        // \clvmgf, \clvmrg
    VAlign: TTyRowCellVAlign;
    Borders: TTyRowCellSides;       // the sides with a line
    BorderWidth: array[TTyRowCellSide] of Integer;   // twips; 0 means the thinnest line
  end;
  TTyRowCellDisplays = array of TTyRowCellDisplay;

  TTyRowDisplay = record
    HalfGap: Integer;    // twips; 0 when the format has no \trgaph (RTF's default)
    Left: Integer;       // twips from the layout's left edge
    Align: TTyRowAlign;  // \trqc, \trqr; rraLeft: at Left (\trql, or nothing said)
    Height: Integer;     // twips: > 0 at least, < 0 exactly -Height, 0 as tall as the content
    Cells: TTyRowCellDisplays;   // in the order of the format's \cellx
  end;

{ The display properties in a row's format fragment; anything else in it is passed over. An
  empty or unreadable fragment gives no cells and zeros. }
function TyRtfRowDisplay(const ARaw: RawByteString): TTyRowDisplay;
{ What a row with no format of its own (a table made here) is shown with: Word's half gap of
  108 twips, a thin line (10 twips) on every side of every one of its ACellCount cells. }
function TyDefaultRowDisplay(ACellCount: Integer): TTyRowDisplay;
{ A cell the format says nothing about: no merge, at the top, no lines. }
function TyPlainRowCell: TTyRowCellDisplay;

implementation

const
  CDefaultHalfGap = 108;
  CDefaultBorder = 10;

function TyPlainRowCell: TTyRowCellDisplay;
var
  s: TTyRowCellSide;
begin
  Result.Right := 0;
  Result.HasRight := False;
  Result.HMerge := rcmNone;
  Result.VMerge := rcmNone;
  Result.VAlign := rcvTop;
  Result.Borders := [];
  for s := Low(TTyRowCellSide) to High(TTyRowCellSide) do Result.BorderWidth[s] := 0;
end;

function TyDefaultRowDisplay(ACellCount: Integer): TTyRowDisplay;
var
  i: Integer;
  s: TTyRowCellSide;
begin
  Result.HalfGap := CDefaultHalfGap;
  Result.Left := 0;
  Result.Align := rraLeft;
  Result.Height := 0;
  Result.Cells := nil;
  if ACellCount < 0 then ACellCount := 0;
  SetLength(Result.Cells, ACellCount);
  for i := 0 to ACellCount - 1 do
  begin
    Result.Cells[i] := TyPlainRowCell;
    Result.Cells[i].Borders := [rcsLeft, rcsTop, rcsRight, rcsBottom];
    for s := Low(TTyRowCellSide) to High(TTyRowCellSide) do
      Result.Cells[i].BorderWidth[s] := CDefaultBorder;
  end;
end;

{ A word that says a side has no line: \brdrnone, \brdrnil, and \brdrtbl ("the cell has no
  border", Word's word for every side of a borderless table's cells). }
function IsNoBorder(const AWord: string): Boolean;
begin
  Result := (AWord = 'brdrnone') or (AWord = 'brdrnil') or (AWord = 'brdrtbl');
end;

{ A word that sets a border's line style (\brdrs, \brdrth, \brdrdb, \brdrdot, ...): every
  \brdr word but the width, the colour, the ones that say "none", and the paragraph's own. }
function IsBorderStyle(const AWord: string): Boolean;
begin
  Result := (Copy(AWord, 1, 4) = 'brdr') and (AWord <> 'brdrw') and (AWord <> 'brdrcf') and
    not IsNoBorder(AWord) and (AWord <> 'brdrbtw') and (AWord <> 'brdrbar');
end;

function TyRtfRowDisplay(const ARaw: RawByteString): TTyRowDisplay;
var
  i, n, depth, start, count: Integer;
  word: string;
  hasParam, neg, inSide: Boolean;
  param: Int64;
  cur: TTyRowCellDisplay;
  side: TTyRowCellSide;
  c: AnsiChar;
begin
  Result.HalfGap := 0;
  Result.Left := 0;
  Result.Align := rraLeft;
  Result.Height := 0;
  Result.Cells := nil;
  count := 0;
  cur := TyPlainRowCell;
  inSide := False;
  side := rcsLeft;
  depth := 0;
  n := Length(ARaw);
  i := 1;
  while i <= n do
  begin
    c := ARaw[i];
    case c of
      '{':
        begin
          Inc(depth);
          Inc(i);
          Continue;
        end;
      '}':
        begin
          if depth > 0 then Dec(depth);
          Inc(i);
          Continue;
        end;
      '\': ;
    else
      Inc(i);
      Continue;
    end;
    // a control word: letters, an optional signed number, an optional space
    Inc(i);
    start := i;
    while (i <= n) and (ARaw[i] in ['a'..'z', 'A'..'Z']) do Inc(i);
    if i = start then
    begin
      // a control symbol (\'xx's two digits are plain bytes to this scan)
      Inc(i);
      Continue;
    end;
    word := Copy(ARaw, start, i - start);
    neg := (i <= n) and (ARaw[i] = '-');
    if neg then Inc(i);
    hasParam := (i <= n) and (ARaw[i] in ['0'..'9']);
    param := 0;
    while (i <= n) and (ARaw[i] in ['0'..'9']) do
    begin
      if param < High(Integer) then param := param * 10 + (Ord(ARaw[i]) - Ord('0'));
      Inc(i);
    end;
    if param > High(Integer) then param := High(Integer);
    if neg then param := -param;
    if (i <= n) and (ARaw[i] = ' ') then Inc(i);
    if word = 'bin' then
    begin
      // N bytes of data, whatever they are (braces and backslashes too), in a group or not
      if param > n - i + 1 then param := n - i + 1;
      if param > 0 then Inc(i, Integer(param));
      Continue;
    end;
    if depth > 0 then Continue;
    if word = 'trowd' then
    begin
      Result.HalfGap := 0;
      Result.Left := 0;
      Result.Align := rraLeft;
      Result.Height := 0;
      count := 0;
      cur := TyPlainRowCell;
      inSide := False;
    end
    else if word = 'trgaph' then Result.HalfGap := param
    else if word = 'trleft' then Result.Left := param
    else if word = 'trql' then Result.Align := rraLeft
    else if word = 'trqc' then Result.Align := rraCenter
    else if word = 'trqr' then Result.Align := rraRight
    else if word = 'trrh' then Result.Height := param
    else if word = 'clmgf' then cur.HMerge := rcmFirst
    else if word = 'clmrg' then cur.HMerge := rcmContinue
    else if word = 'clvmgf' then cur.VMerge := rcmFirst
    else if word = 'clvmrg' then cur.VMerge := rcmContinue
    else if word = 'clvertalt' then cur.VAlign := rcvTop
    else if word = 'clvertalc' then cur.VAlign := rcvCenter
    else if word = 'clvertalb' then cur.VAlign := rcvBottom
    else if (word = 'clbrdrl') or (word = 'clbrdrt') or (word = 'clbrdrr') or (word = 'clbrdrb') then
    begin
      case word[7] of
        'l': side := rcsLeft;
        't': side := rcsTop;
        'r': side := rcsRight;
      else
        side := rcsBottom;
      end;
      inSide := True;
    end
    else if (Copy(word, 1, 6) = 'trbrdr') or (word = 'cldglu') or (word = 'cldgll') then
      // the row's own borders, a diagonal: the words after it are not a cell side's
      inSide := False
    else if inSide and (word = 'brdrw') then
    begin
      if param < 0 then param := 0;
      cur.BorderWidth[side] := param;
    end
    else if inSide and IsNoBorder(word) then
      Exclude(cur.Borders, side)
    else if inSide and IsBorderStyle(word) then
      Include(cur.Borders, side)
    else if word = 'cellx' then
    begin
      if hasParam then
      begin
        cur.Right := param;
        cur.HasRight := True;
      end;
      if count = Length(Result.Cells) then SetLength(Result.Cells, count * 2 + 4);
      Result.Cells[count] := cur;
      Inc(count);
      cur := TyPlainRowCell;
      inSide := False;
    end;
  end;
  SetLength(Result.Cells, count);
end;

end.
