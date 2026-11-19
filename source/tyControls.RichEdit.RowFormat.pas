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
  \binN.

  The table edits of the model take a row's format apart here and put it together with
  other cells (TyRtfSplitRowFormat, TyRtfJoinRowFormat), and give the rows they make a
  format of their own (TyRtfGridRowFormat): bytes in, bytes out, nothing else read. }

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

type
  TTyRtfCellWords = array of RawByteString;

{ The format of a row made here (a table edit's new table): Word's plain grid -
  \trowd\trgaphG, then for each cell a single line 10 twips wide on its four sides and its
  right edge, AEdges[i] twips (the first cell starts at 0). G is Word's 108, or less when a
  cell is narrower than the two gaps and the two lines: the largest G with 2G + 20 no more
  than the narrowest cell's width (0 at least) - Word widens a cell to that, and the table
  would be wider in Word than here. What TyRtfRowDisplay reads of it is TyDefaultRowDisplay's
  look (with that gap), and Word, WordPad and RichEdit draw the same lines. }
function TyRtfGridRowFormat(const AEdges: array of Integer): RawByteString;
{ ARaw without the words that number a row among its table's (\irowN, \irowbandN,
  \lastrow), every other byte as it is: the format of a row made again beside it. Words
  inside groups are left. }
function TyRtfRowFormatUnnumbered(const ARaw: RawByteString): RawByteString;
{ A row's format cut into the row's words and each cell's, so that cells can come and go
  while every word stays with what it belongs to: ARowWords is \trowd with the row's own
  words (\trgaph, \trleft, \trbrdr* and their line words, ...) in their order; ACells[i] the
  words of cell i in their order (each word that starts with \cl, and the line words after a
  \clbrdr*), without its \cellx. False - nothing to go by - when a word cannot be told whose
  it is: a group, \bin, a control symbol, text, a second \trowd, a \cellx without a number,
  words after the last \cellx, or another number of cells than ACellCount. }
function TyRtfSplitRowFormat(const ARaw: RawByteString; ACellCount: Integer;
  out ARowWords: RawByteString; out ACells: TTyRtfCellWords): Boolean;
{ A row's format put together again: ARowWords, then each cell's words and its \cellx at
  AEdges[i] (as many edges as cells). }
function TyRtfJoinRowFormat(const ARowWords: RawByteString; const ACells: TTyRtfCellWords;
  const AEdges: array of Integer): RawByteString;

implementation

uses
  SysUtils;

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

procedure AddRaw(var R: RawByteString; const S: RawByteString);
var
  n: Integer;
begin
  if S = '' then Exit;
  n := Length(R);
  SetLength(R, n + Length(S));
  Move(S[1], R[n + 1], Length(S));
end;

function AsRaw(const S: string): RawByteString;
begin
  Result := '';
  AddRaw(Result, RawByteString(S));
  SetCodePage(Result, CP_NONE, False);
end;

function TyRtfGridRowFormat(const AEdges: array of Integer): RawByteString;
var
  i, gap, w, prev: Integer;
begin
  gap := CDefaultHalfGap;
  prev := 0;
  for i := 0 to High(AEdges) do
  begin
    w := AEdges[i] - prev;
    if 2 * gap + 2 * CDefaultBorder > w then gap := (w - 2 * CDefaultBorder) div 2;
    prev := AEdges[i];
  end;
  if gap < 0 then gap := 0;
  Result := AsRaw('\trowd\trgaph' + IntToStr(gap));
  for i := 0 to High(AEdges) do
    AddRaw(Result, AsRaw(Format('\clbrdrt\brdrs\brdrw%0:d \clbrdrl\brdrs\brdrw%0:d ' +
      '\clbrdrb\brdrs\brdrw%0:d \clbrdrr\brdrs\brdrw%0:d \cellx%1:d', [CDefaultBorder, AEdges[i]])));
end;

function TyRtfRowFormatUnnumbered(const ARaw: RawByteString): RawByteString;
var
  i, n, depth, start, wordStart: Integer;
  word: string;
  param: Int64;
begin
  Result := '';
  n := Length(ARaw);
  depth := 0;
  i := 1;
  start := 1;     // the bytes from here on are not copied yet
  while i <= n do
  begin
    case ARaw[i] of
      '{': begin Inc(depth); Inc(i); Continue; end;
      '}': begin if depth > 0 then Dec(depth); Inc(i); Continue; end;
      '\': ;
    else
      begin
        Inc(i);
        Continue;
      end;
    end;
    wordStart := i;
    Inc(i);
    if (i <= n) and not (ARaw[i] in ['a'..'z', 'A'..'Z']) then
    begin
      // a control symbol: \'xx's digits are bytes like any
      Inc(i);
      Continue;
    end;
    while (i <= n) and (ARaw[i] in ['a'..'z', 'A'..'Z']) do Inc(i);
    word := Copy(ARaw, wordStart + 1, i - wordStart - 1);
    if (i <= n) and (ARaw[i] = '-') then Inc(i);
    param := 0;
    while (i <= n) and (ARaw[i] in ['0'..'9']) do
    begin
      if param < High(Integer) then param := param * 10 + (Ord(ARaw[i]) - Ord('0'));
      Inc(i);
    end;
    if (i <= n) and (ARaw[i] = ' ') then Inc(i);
    if word = 'bin' then
    begin
      // N bytes of data, whatever they are
      if param > n - i + 1 then param := n - i + 1;
      Inc(i, Integer(param));
      Continue;
    end;
    if (depth = 0) and ((word = 'irow') or (word = 'irowband') or (word = 'lastrow')) then
    begin
      AddRaw(Result, Copy(ARaw, start, wordStart - start));
      start := i;
    end;
  end;
  AddRaw(Result, Copy(ARaw, start, n - start + 1));
  SetCodePage(Result, CP_NONE, False);
end;

function TyRtfSplitRowFormat(const ARaw: RawByteString; ACellCount: Integer;
  out ARowWords: RawByteString; out ACells: TTyRtfCellWords): Boolean;
var
  i, n, start, wordStart, count: Integer;
  word: string;
  hasParam, cellLine, rowd: Boolean;
  cur: RawByteString;
begin
  ARowWords := '';
  ACells := nil;
  Result := False;
  n := Length(ARaw);
  SetLength(ACells, ACellCount);
  count := 0;
  cur := '';
  // the owner of the line words that follow a border word: a cell's or the row's
  cellLine := False;
  rowd := False;
  i := 1;
  while i <= n do
  begin
    if ARaw[i] in [#13, #10] then
    begin
      // line breaks between words mean nothing in RTF (any other byte would be text)
      Inc(i);
      Continue;
    end;
    if ARaw[i] <> '\' then Exit;
    wordStart := i;
    Inc(i);
    start := i;
    while (i <= n) and (ARaw[i] in ['a'..'z', 'A'..'Z']) do Inc(i);
    // a control symbol (\*, \'xx, ...): not a row's or a cell's word that can be told
    if i = start then Exit;
    word := Copy(ARaw, start, i - start);
    if (i <= n) and (ARaw[i] = '-') then Inc(i);
    hasParam := (i <= n) and (ARaw[i] in ['0'..'9']);
    while (i <= n) and (ARaw[i] in ['0'..'9']) do Inc(i);
    // its delimiter is its own
    if (i <= n) and (ARaw[i] = ' ') then Inc(i);
    if word = 'bin' then Exit;
    if word = 'trowd' then
    begin
      if rowd then Exit;
      rowd := True;
      AddRaw(ARowWords, Copy(ARaw, wordStart, i - wordStart));
      Continue;
    end;
    if not rowd then Exit;
    if word = 'cellx' then
    begin
      if not hasParam or (count >= ACellCount) then Exit;
      ACells[count] := cur;
      Inc(count);
      cur := '';
      cellLine := False;
      Continue;
    end;
    if Copy(word, 1, 2) = 'cl' then
    begin
      // a cell's word; a border of the cell takes the line words after it
      // (a diagonal's line words are the cell's too)
      cellLine := (Copy(word, 1, 6) = 'clbrdr') or (word = 'cldglu') or (word = 'cldgll');
      AddRaw(cur, Copy(ARaw, wordStart, i - wordStart));
    end
    else if ((Copy(word, 1, 4) = 'brdr') or (word = 'brsp')) and cellLine then
      AddRaw(cur, Copy(ARaw, wordStart, i - wordStart))
    else
    begin
      // the row's (\trbrdr* takes its line words along with it)
      cellLine := False;
      AddRaw(ARowWords, Copy(ARaw, wordStart, i - wordStart));
    end;
  end;
  // words of a cell that has no \cellx, or not as many cells
  Result := rowd and (cur = '') and (count = ACellCount);
  if not Result then
  begin
    ARowWords := '';
    ACells := nil;
  end;
end;

function TyRtfJoinRowFormat(const ARowWords: RawByteString; const ACells: TTyRtfCellWords;
  const AEdges: array of Integer): RawByteString;
var
  i: Integer;
begin
  Result := '';
  AddRaw(Result, ARowWords);
  for i := 0 to High(ACells) do
  begin
    AddRaw(Result, ACells[i]);
    if i <= High(AEdges) then AddRaw(Result, AsRaw('\cellx' + IntToStr(AEdges[i])));
  end;
  SetCodePage(Result, CP_NONE, False);
end;

end.
