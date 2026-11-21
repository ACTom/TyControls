unit tyControls.RichEdit.TableProps;

{ What a table's rows and cells look like, as properties code can read and set: each cell's
  four borders (line style, width, colour), its shading, its own padding and where its
  content sits; each row's height, where it starts, its alignment and the padding its cells
  take when they set none. A cell's width is not kept here: it comes from the row's edges
  (TTyRichRow.CellEdges), which the model keeps.

  A row of a file keeps its definition's bytes (TTyRichRow.RawFormat) as the proof that it is
  untouched. Beside them it has two of these formats: the one its bytes say (its base) and
  the one it has now. They are the same object until an edit sets a property; a writer then
  makes the definition again from the bytes (TyRichRowFormatBytes): every word of the
  properties that changed is replaced, every other word - what this unit does not know
  among them - stays where it was.

  A format is immutable and pooled: rows that look the same share one (a table of ten
  thousand rows usually has one or two), so decoding costs no memory per row. Colours are
  real colours, never the numbers of a file's colour table: the reader resolves them, a
  writer gives them its own numbers.

  Words read: \trgaph, \trleft, \trql / \trqc / \trqr, \trrh, \trpaddl / t / r / b with their
  units (\trpaddfl ...); per cell \clmgf / \clmrg / \clvmgf / \clvmrg, \clvertalt / c / b,
  \clbrdrl / t / r / b with the line words after each (a style word, \brdrw, \brdrcf),
  \clcbpat (or \clcbpatraw), \clpadl / t / r / b with their units. Words in groups and the
  bytes of \binN are passed over. }

{$mode objfpc}{$H+}

interface

uses
  Graphics, tyControls.RichEdit.RowFormat;

type
  TTyRichBorderStyle = (rbsNone, rbsSingle, rbsDouble, rbsDotted, rbsDashed);
  // (the same sides as the display's: one set of names)
  TTyRichCellSide = TTyRowCellSide;

  { A cell border: no line (rbsNone), or a line of a style, a width and a colour. Color
    clDefault: automatic (the text's colour where it is drawn). A file's styles other than
    these four are read as rbsSingle and are written back as the file had them while the
    border is not changed. }
  TTyRichBorder = record
    Style: TTyRichBorderStyle;
    WidthTwips: Integer;
    Color: TColor;
  end;

  TTyRichCellProp = (rcpWidth, rcpBorderLeft, rcpBorderTop, rcpBorderRight, rcpBorderBottom,
    rcpShading, rcpPadLeft, rcpPadTop, rcpPadRight, rcpPadBottom, rcpVAlign);
  TTyRichCellPropSet = set of TTyRichCellProp;

  { A cell's properties. Valid says which fields mean something: a query gives every one (the
    padding the cell takes - its own, else its row's); an edit changes only those in it.
    Shading clNone: none. Pad in twips. }
  TTyRichCellProps = record
    Valid: set of TTyRichCellProp;
    WidthTwips: Integer;
    Borders: array[TTyRichCellSide] of TTyRichBorder;
    Shading: TColor;
    Pad: array[TTyRichCellSide] of Integer;
    VAlign: TTyRowCellVAlign;
  end;

  TTyRichRowProp = (rrpHeight, rrpLeft, rrpAlign, rrpPad);
  TTyRichRowPropSet = set of TTyRichRowProp;

  { A row's properties, Valid as TTyRichCellProps'. HeightTwips > 0: at least that high, < 0:
    exactly -HeightTwips, 0: as high as its content. LeftTwips: where its first cell starts.
    DefaultPad: what a cell that sets none of its own takes. }
  TTyRichRowProps = record
    Valid: set of TTyRichRowProp;
    HeightTwips: Integer;
    LeftTwips: Integer;
    Align: TTyRowAlign;
    DefaultPad: array[TTyRichCellSide] of Integer;
  end;

  { A cell as a format keeps it: Props.Valid holds the borders, the shading and the
    alignment always, a side's padding only when the cell sets its own (WidthTwips unused). }
  TTyRichCellFormat = record
    Props: TTyRichCellProps;
    HMerge, VMerge: TTyRowCellMerge;
  end;

  { A row's look, shared by the rows that have it: immutable once pooled, held by reference
    (AddRef / Release; the last Release frees it). }
  TTyRichRowFormat = class
  private
    FRefCount: Integer;
    FHash: Cardinal;
    FNext: TTyRichRowFormat;   // the pool's chain
    FPooled: Boolean;
    function ComputeHash: Cardinal;
    function SameAs(B: TTyRichRowFormat): Boolean;
  public
    // the text's distance from a cell's left and right edges, as \trgaph says (the display's)
    HalfGap: Integer;
    // Valid: every field (rrpPad: DefaultPad as the row says it, else from HalfGap and 0)
    Row: TTyRichRowProps;
    Cells: array of TTyRichCellFormat;
    procedure AddRef;
    procedure Release;
    function CellCount: Integer;
    { A copy, not pooled, held by no one: change it and Intern it. }
    function Clone: TTyRichRowFormat;
    { This format with every cell from ACells: the format's cell ACells[i] for cell i (-1:
      ADefault's cell, ADefault >= 0; otherwise a plain one). Pooled, one reference for the
      caller. }
    function Permuted(const ACells: array of Integer): TTyRichRowFormat;
  end;

  { The colour a writer numbers AColor with in its colour table (0: none). }
  TTyRichColorIndexFunc = function(AColor: TColor): Integer of object;

{ AFormat, made with TTyRichRowFormat.Create or Clone and held by no one, in the pool: the
  pooled one equal to it (AFormat is freed then) or AFormat itself. One reference for the
  caller. }
function TyRichInternRowFormat(AFormat: TTyRichRowFormat): TTyRichRowFormat;
{ Formats in the pool now (for tests: rows that look alike share one). }
function TyRichRowFormatCount: Integer;

{ The format a row's definition ARaw says, pooled, one reference for the caller. ACellCount
  cells (fewer cut off, more as plain cells - no lines; < 0: as many as ARaw has). AColors:
  the file's colour table (AColors[i] is entry i, clDefault for automatic); a number it has
  no entry for is automatic. An empty ARaw - a row made here with no format of its own - is
  shown as TyDefaultRowDisplay shows it: a thin line on every side, Word's half gap. }
function TyRichDecodeRowFormat(const ARaw: RawByteString; ACellCount: Integer;
  const AColors: array of TColor): TTyRichRowFormat;

{ What a row with this format and these edges is shown with (TTyRowDisplay, as
  TyRtfRowDisplay reads one from bytes). }
function TyRichFormatDisplay(AFormat: TTyRichRowFormat; const AEdges: array of Integer): TTyRowDisplay;

{ ARaw, the definition ABase was decoded from, with the words of every property in which
  AFormat differs from ABase made again from AFormat, and the edges AEdges: every other word
  where it was. A definition that cannot be cut into its row's and cells' words
  (TyRtfSplitRowFormat), or another number of cells than AFormat's, is made whole from
  AFormat (what this unit does not know of it is lost then). AColorIndex numbers the
  colours. }
function TyRichRowFormatBytes(const ARaw: RawByteString; ABase, AFormat: TTyRichRowFormat;
  const AEdges: array of Integer; AColorIndex: TTyRichColorIndexFunc): RawByteString;

{ The colours AFormat's words would name where it differs from ABase (what a writer needs
  in its colour table before it writes the row): AColorIndex is called for each. }
procedure TyRichNoteRowColors(ABase, AFormat: TTyRichRowFormat; AColorIndex: TTyRichColorIndexFunc);

{ A cell's properties as a query gives them: every field valid, the padding the cell takes,
  AWidth as its width. }
function TyRichEffectiveCellProps(AFormat: TTyRichRowFormat; ACell, AWidth: Integer): TTyRichCellProps;
{ AFormat with the fields of AProps that AProps.Valid names set on cells ACol0 .. ACol1
  (rcpWidth is not a format's: ignored), pooled, one reference. }
function TyRichWithCellProps(AFormat: TTyRichRowFormat; ACol0, ACol1: Integer;
  const AProps: TTyRichCellProps): TTyRichRowFormat;
{ AFormat with the fields AProps.Valid names set, pooled, one reference. A padding's left
  side sets the half gap too (what older readers go by for both sides). }
function TyRichWithRowProps(AFormat: TTyRichRowFormat; const AProps: TTyRichRowProps): TTyRichRowFormat;

function TyRichBorder(AStyle: TTyRichBorderStyle; AWidthTwips: Integer;
  AColor: TColor = clDefault): TTyRichBorder;
function TyRichSameBorder(const A, B: TTyRichBorder): Boolean;

implementation

uses
  SysUtils;

const
  CDefaultHalfGap = 108;
  CDefaultBorder = 10;
  // a padding's unit word: 3 is twips; 0 says the value is not there
  CPadTwips = 3;

  CBorderProps: array[TTyRichCellSide] of TTyRichCellProp = (rcpBorderLeft, rcpBorderTop,
    rcpBorderRight, rcpBorderBottom);
  CPadProps: array[TTyRichCellSide] of TTyRichCellProp = (rcpPadLeft, rcpPadTop, rcpPadRight,
    rcpPadBottom);
  // a cell border's word, by side
  CCellBorderWords: array[TTyRichCellSide] of string = ('clbrdrl', 'clbrdrt', 'clbrdrr',
    'clbrdrb');
  { A cell's padding words, by side. Word writes a cell's left padding as \clpadt and its top
    padding as \clpadl (and their units likewise), the other two as named; it reads them so
    too, and so does every file it made: read and written here the way Word means them. }
  CCellPadWords: array[TTyRichCellSide] of string = ('clpadt', 'clpadl', 'clpadr', 'clpadb');
  CCellPadUnits: array[TTyRichCellSide] of string = ('clpadft', 'clpadfl', 'clpadfr', 'clpadfb');
  // a row's (as named)
  CRowPadWords: array[TTyRichCellSide] of string = ('trpaddl', 'trpaddt', 'trpaddr', 'trpaddb');
  CRowPadUnits: array[TTyRichCellSide] of string = ('trpaddfl', 'trpaddft', 'trpaddfr', 'trpaddfb');

function TyRichBorder(AStyle: TTyRichBorderStyle; AWidthTwips: Integer;
  AColor: TColor): TTyRichBorder;
begin
  Result.Style := AStyle;
  Result.WidthTwips := AWidthTwips;
  Result.Color := AColor;
end;

function TyRichSameBorder(const A, B: TTyRichBorder): Boolean;
begin
  // (no line: its width and colour say nothing)
  if (A.Style = rbsNone) and (B.Style = rbsNone) then Exit(True);
  Result := (A.Style = B.Style) and (A.WidthTwips = B.WidthTwips) and (A.Color = B.Color);
end;

function NoBorder: TTyRichBorder;
begin
  Result := TyRichBorder(rbsNone, 0, clDefault);
end;

function PlainCell: TTyRichCellFormat;
var
  s: TTyRichCellSide;
begin
  Result := Default(TTyRichCellFormat);
  Result.Props.Valid := [rcpBorderLeft, rcpBorderTop, rcpBorderRight, rcpBorderBottom,
    rcpShading, rcpVAlign];
  for s := Low(TTyRichCellSide) to High(TTyRichCellSide) do
  begin
    Result.Props.Borders[s] := NoBorder;
    Result.Props.Pad[s] := 0;
  end;
  Result.Props.Shading := clNone;
  Result.Props.VAlign := rcvTop;
  Result.HMerge := rcmNone;
  Result.VMerge := rcmNone;
end;

{ ---- the pool ---- }

var
  GBuckets: array of TTyRichRowFormat;
  GCount: Integer;
  { The bytes read last without colours and what they gave (held by no one here: Release
    forgets it) - the rows of one table usually share their bytes, often the very string. }
  GLastRaw: RawByteString;
  GLastCells: Integer;
  GLastFormat: TTyRichRowFormat;

procedure Mix(var H: Cardinal; V: Integer); inline;
begin
  H := (H xor Cardinal(V)) * 16777619;
end;

function PropBits(const S: TTyRichCellPropSet): Integer;
var
  p: TTyRichCellProp;
begin
  Result := 0;
  for p := Low(TTyRichCellProp) to High(TTyRichCellProp) do
    if p in S then Result := Result or (1 shl Ord(p));
end;

function TTyRichRowFormat.ComputeHash: Cardinal;
var
  i: Integer;
  s: TTyRichCellSide;
begin
  Result := 2166136261;
  Mix(Result, HalfGap);
  Mix(Result, Row.HeightTwips);
  Mix(Result, Row.LeftTwips);
  Mix(Result, Ord(Row.Align));
  for s := Low(TTyRichCellSide) to High(TTyRichCellSide) do Mix(Result, Row.DefaultPad[s]);
  Mix(Result, Length(Cells));
  for i := 0 to High(Cells) do
    with Cells[i] do
    begin
      Mix(Result, PropBits(Props.Valid));
      for s := Low(TTyRichCellSide) to High(TTyRichCellSide) do
      begin
        Mix(Result, Ord(Props.Borders[s].Style));
        Mix(Result, Props.Borders[s].WidthTwips);
        Mix(Result, Integer(Props.Borders[s].Color));
        Mix(Result, Props.Pad[s]);
      end;
      Mix(Result, Integer(Props.Shading));
      Mix(Result, Ord(Props.VAlign));
      Mix(Result, Ord(HMerge) * 4 + Ord(VMerge));
    end;
end;

function SameCell(const A, B: TTyRichCellFormat): Boolean;
var
  s: TTyRichCellSide;
begin
  Result := (A.Props.Valid = B.Props.Valid) and (A.Props.Shading = B.Props.Shading) and
    (A.Props.VAlign = B.Props.VAlign) and (A.HMerge = B.HMerge) and (A.VMerge = B.VMerge);
  if not Result then Exit;
  for s := Low(TTyRichCellSide) to High(TTyRichCellSide) do
    if (A.Props.Borders[s].Style <> B.Props.Borders[s].Style) or
       (A.Props.Borders[s].WidthTwips <> B.Props.Borders[s].WidthTwips) or
       (A.Props.Borders[s].Color <> B.Props.Borders[s].Color) or
       (A.Props.Pad[s] <> B.Props.Pad[s]) then
      Exit(False);
end;

function TTyRichRowFormat.SameAs(B: TTyRichRowFormat): Boolean;
var
  i: Integer;
  s: TTyRichCellSide;
begin
  Result := (HalfGap = B.HalfGap) and (Row.Valid = B.Row.Valid) and
    (Row.HeightTwips = B.Row.HeightTwips) and (Row.LeftTwips = B.Row.LeftTwips) and
    (Row.Align = B.Row.Align) and (Length(Cells) = Length(B.Cells));
  if not Result then Exit;
  for s := Low(TTyRichCellSide) to High(TTyRichCellSide) do
    if Row.DefaultPad[s] <> B.Row.DefaultPad[s] then Exit(False);
  for i := 0 to High(Cells) do
    if not SameCell(Cells[i], B.Cells[i]) then Exit(False);
end;

procedure GrowPool;
var
  old: array of TTyRichRowFormat;
  i, n: Integer;
  f, nx: TTyRichRowFormat;
begin
  old := GBuckets;
  n := Length(old) * 2;
  if n < 64 then n := 64;
  GBuckets := nil;
  SetLength(GBuckets, n);
  for i := 0 to High(old) do
  begin
    f := old[i];
    while f <> nil do
    begin
      nx := f.FNext;
      f.FNext := GBuckets[f.FHash and Cardinal(n - 1)];
      GBuckets[f.FHash and Cardinal(n - 1)] := f;
      f := nx;
    end;
  end;
end;

function TyRichInternRowFormat(AFormat: TTyRichRowFormat): TTyRichRowFormat;
var
  h: Cardinal;
  f: TTyRichRowFormat;
begin
  h := AFormat.ComputeHash;
  if Length(GBuckets) > 0 then
  begin
    f := GBuckets[h and Cardinal(High(GBuckets))];
    while f <> nil do
    begin
      if (f.FHash = h) and f.SameAs(AFormat) then
      begin
        if f <> AFormat then AFormat.Free;
        f.AddRef;
        Exit(f);
      end;
      f := f.FNext;
    end;
  end;
  if (GCount + 1) * 4 > Length(GBuckets) * 3 then GrowPool;
  AFormat.FHash := h;
  AFormat.FPooled := True;
  AFormat.FNext := GBuckets[h and Cardinal(High(GBuckets))];
  GBuckets[h and Cardinal(High(GBuckets))] := AFormat;
  Inc(GCount);
  AFormat.FRefCount := 1;
  Result := AFormat;
end;

function TyRichRowFormatCount: Integer;
begin
  Result := GCount;
end;

procedure Unpool(AFormat: TTyRichRowFormat);
var
  p: ^TTyRichRowFormat;
begin
  p := @GBuckets[AFormat.FHash and Cardinal(High(GBuckets))];
  while p^ <> nil do
  begin
    if p^ = AFormat then
    begin
      p^ := AFormat.FNext;
      Dec(GCount);
      Exit;
    end;
    p := @p^.FNext;
  end;
end;

procedure TTyRichRowFormat.AddRef;
begin
  Inc(FRefCount);
end;

procedure TTyRichRowFormat.Release;
begin
  Dec(FRefCount);
  if FRefCount > 0 then Exit;
  if FPooled then Unpool(Self);
  if GLastFormat = Self then
  begin
    GLastFormat := nil;
    GLastRaw := '';
  end;
  Free;
end;

function TTyRichRowFormat.CellCount: Integer;
begin
  Result := Length(Cells);
end;

function TTyRichRowFormat.Clone: TTyRichRowFormat;
begin
  Result := TTyRichRowFormat.Create;
  Result.HalfGap := HalfGap;
  Result.Row := Row;
  Result.Cells := Copy(Cells);
end;

function TTyRichRowFormat.Permuted(const ACells: array of Integer): TTyRichRowFormat;
var
  i: Integer;
  f: TTyRichRowFormat;
begin
  f := TTyRichRowFormat.Create;
  f.HalfGap := HalfGap;
  f.Row := Row;
  SetLength(f.Cells, Length(ACells));
  for i := 0 to High(ACells) do
    if (ACells[i] >= 0) and (ACells[i] < Length(Cells)) then f.Cells[i] := Cells[ACells[i]]
    else f.Cells[i] := PlainCell;
  Result := TyRichInternRowFormat(f);
end;

{ ---- reading ---- }

function DefaultFormat(ACellCount: Integer): TTyRichRowFormat;
var
  i: Integer;
  s: TTyRichCellSide;
begin
  Result := TTyRichRowFormat.Create;
  Result.HalfGap := CDefaultHalfGap;
  Result.Row.Valid := [rrpHeight, rrpLeft, rrpAlign, rrpPad];
  Result.Row.Align := rraLeft;
  Result.Row.DefaultPad[rcsLeft] := CDefaultHalfGap;
  Result.Row.DefaultPad[rcsRight] := CDefaultHalfGap;
  if ACellCount < 0 then ACellCount := 0;
  SetLength(Result.Cells, ACellCount);
  for i := 0 to ACellCount - 1 do
  begin
    Result.Cells[i] := PlainCell;
    for s := Low(TTyRichCellSide) to High(TTyRichCellSide) do
      Result.Cells[i].Props.Borders[s] := TyRichBorder(rbsSingle, CDefaultBorder);
  end;
end;

// The style a line style word gives (\brdrs, \brdrdb, ...); False for a word that is none.
function StyleOfWord(const AWord: string; out AStyle: TTyRichBorderStyle): Boolean;
begin
  Result := False;
  if (Copy(AWord, 1, 4) <> 'brdr') or (AWord = 'brdrw') or (AWord = 'brdrcf') or
     (AWord = 'brdrbtw') or (AWord = 'brdrbar') then
    Exit;
  Result := True;
  if (AWord = 'brdrnone') or (AWord = 'brdrnil') or (AWord = 'brdrtbl') then AStyle := rbsNone
  else if AWord = 'brdrdb' then AStyle := rbsDouble
  else if AWord = 'brdrdot' then AStyle := rbsDotted
  else if (AWord = 'brdrdash') or (AWord = 'brdrdashsm') then AStyle := rbsDashed
  else AStyle := rbsSingle;
end;

function SideOfLetter(C: Char): TTyRichCellSide;
begin
  case C of
    'l': Result := rcsLeft;
    't': Result := rcsTop;
    'r': Result := rcsRight;
  else
    Result := rcsBottom;
  end;
end;

function TyRichDecodeRowFormat(const ARaw: RawByteString; ACellCount: Integer;
  const AColors: array of TColor): TTyRichRowFormat;
var
  f: TTyRichRowFormat;
  i, n, depth, start, count: Integer;
  word: string;
  hasParam, neg, inSide, shadeSet: Boolean;
  param: Int64;
  cur: TTyRichCellFormat;
  side, s: TTyRichCellSide;
  st: TTyRichBorderStyle;
  c: AnsiChar;
  // a padding's value and unit as the words gave them (-1: none)
  cellPad, cellUnit, rowPad, rowUnit: array[TTyRichCellSide] of Int64;

  function ColorAt(AIndex: Int64): TColor;
  begin
    if (AIndex <= 0) or (AIndex > High(AColors)) then Result := clDefault
    else Result := AColors[AIndex];
  end;

  procedure NewCell;
  var
    q: TTyRichCellSide;
  begin
    cur := PlainCell;
    inSide := False;
    shadeSet := False;
    for q := Low(TTyRichCellSide) to High(TTyRichCellSide) do
    begin
      cellPad[q] := -1;
      cellUnit[q] := -1;
    end;
  end;

  procedure NewRow;
  var
    q: TTyRichCellSide;
  begin
    f.HalfGap := 0;
    f.Row.HeightTwips := 0;
    f.Row.LeftTwips := 0;
    f.Row.Align := rraLeft;
    for q := Low(TTyRichCellSide) to High(TTyRichCellSide) do
    begin
      rowPad[q] := -1;
      rowUnit[q] := -1;
    end;
    count := 0;
    NewCell;
  end;

  function PadOf(AValue, AUnit: Int64): Integer;
  begin
    // a value with no unit word, or in twips; a unit of 0 (or another) says it is not there
    if (AValue >= 0) and ((AUnit < 0) or (AUnit = CPadTwips)) then Result := Integer(AValue)
    else Result := -1;
  end;

  function PadWord(const AWords: array of string; out ASide: TTyRichCellSide): Boolean;
  var
    q: TTyRichCellSide;
  begin
    for q := Low(TTyRichCellSide) to High(TTyRichCellSide) do
      if word = AWords[Ord(q)] then
      begin
        ASide := q;
        Exit(True);
      end;
    Result := False;
  end;

  procedure EndCell;
  var
    q: TTyRichCellSide;
    v: Integer;
  begin
    for q := Low(TTyRichCellSide) to High(TTyRichCellSide) do
    begin
      v := PadOf(cellPad[q], cellUnit[q]);
      if v >= 0 then
      begin
        cur.Props.Pad[q] := v;
        Include(cur.Props.Valid, CPadProps[q]);
      end;
    end;
    if count = Length(f.Cells) then SetLength(f.Cells, count * 2 + 4);
    f.Cells[count] := cur;
    Inc(count);
    NewCell;
  end;

begin
  if ARaw = '' then Exit(TyRichInternRowFormat(DefaultFormat(ACellCount)));
  if (Length(AColors) = 0) and (GLastFormat <> nil) and (ACellCount = GLastCells) and
     (Length(ARaw) = Length(GLastRaw)) and
     ((Pointer(ARaw) = Pointer(GLastRaw)) or CompareMem(@ARaw[1], @GLastRaw[1], Length(ARaw))) then
  begin
    GLastFormat.AddRef;
    Exit(GLastFormat);
  end;
  f := TTyRichRowFormat.Create;
  f.Row.Valid := [rrpHeight, rrpLeft, rrpAlign, rrpPad];
  NewRow;
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
    Inc(i);
    start := i;
    while (i <= n) and (ARaw[i] in ['a'..'z', 'A'..'Z']) do Inc(i);
    if i = start then
    begin
      Inc(i);
      Continue;
    end;
    { (the word in a string of the default code page: one copied out of the bytes keeps
      theirs, and every comparison with a constant would convert it first) }
    word := '';
    SetLength(word, i - start);
    Move(ARaw[start], word[1], i - start);
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
      if param > n - i + 1 then param := n - i + 1;
      if param > 0 then Inc(i, Integer(param));
      Continue;
    end;
    if depth > 0 then Continue;
    if word = 'trowd' then NewRow
    else if word = 'trgaph' then f.HalfGap := param
    else if word = 'trleft' then f.Row.LeftTwips := param
    else if word = 'trql' then f.Row.Align := rraLeft
    else if word = 'trqc' then f.Row.Align := rraCenter
    else if word = 'trqr' then f.Row.Align := rraRight
    else if word = 'trrh' then f.Row.HeightTwips := param
    else if PadWord(CRowPadWords, s) then begin if hasParam then rowPad[s] := param; end
    else if PadWord(CRowPadUnits, s) then rowUnit[s] := param
    else if PadWord(CCellPadWords, s) then begin if hasParam then cellPad[s] := param; end
    else if PadWord(CCellPadUnits, s) then cellUnit[s] := param
    else if word = 'clmgf' then cur.HMerge := rcmFirst
    else if word = 'clmrg' then cur.HMerge := rcmContinue
    else if word = 'clvmgf' then cur.VMerge := rcmFirst
    else if word = 'clvmrg' then cur.VMerge := rcmContinue
    else if word = 'clvertalt' then cur.Props.VAlign := rcvTop
    else if word = 'clvertalc' then cur.Props.VAlign := rcvCenter
    else if word = 'clvertalb' then cur.Props.VAlign := rcvBottom
    else if word = 'clcbpat' then
    begin
      cur.Props.Shading := ColorAt(param);
      if cur.Props.Shading = clDefault then cur.Props.Shading := clNone;
      shadeSet := True;
    end
    else if word = 'clcbpatraw' then
    begin
      // (Word's own copy beside \clcbpat: taken only where that one is missing)
      if not shadeSet then
      begin
        cur.Props.Shading := ColorAt(param);
        if cur.Props.Shading = clDefault then cur.Props.Shading := clNone;
      end;
    end
    else if (word = 'clbrdrl') or (word = 'clbrdrt') or (word = 'clbrdrr') or (word = 'clbrdrb') then
    begin
      side := SideOfLetter(word[7]);
      cur.Props.Borders[side] := NoBorder;
      inSide := True;
    end
    else if (Copy(word, 1, 6) = 'trbrdr') or (word = 'cldglu') or (word = 'cldgll') then
      inSide := False
    else if inSide and (word = 'brdrw') then
    begin
      if param < 0 then param := 0;
      cur.Props.Borders[side].WidthTwips := param;
    end
    else if inSide and (word = 'brdrcf') then
      cur.Props.Borders[side].Color := ColorAt(param)
    else if inSide and StyleOfWord(word, st) then
      cur.Props.Borders[side].Style := st
    else if word = 'cellx' then
      EndCell;
  end;
  // the row's default padding: as it says, else the half gap at the sides and none above
  for s := Low(TTyRichCellSide) to High(TTyRichCellSide) do
  begin
    f.Row.DefaultPad[s] := PadOf(rowPad[s], rowUnit[s]);
    if f.Row.DefaultPad[s] < 0 then
      if s in [rcsLeft, rcsRight] then f.Row.DefaultPad[s] := f.HalfGap
      else f.Row.DefaultPad[s] := 0;
  end;
  i := ACellCount;
  if ACellCount < 0 then ACellCount := count;
  SetLength(f.Cells, ACellCount);
  for n := count to ACellCount - 1 do f.Cells[n] := PlainCell;
  Result := TyRichInternRowFormat(f);
  if Length(AColors) = 0 then
  begin
    GLastRaw := ARaw;
    GLastCells := i;
    GLastFormat := Result;
  end;
end;

function TyRichFormatDisplay(AFormat: TTyRichRowFormat; const AEdges: array of Integer): TTyRowDisplay;
var
  i: Integer;
  s: TTyRichCellSide;
begin
  Result.HalfGap := AFormat.HalfGap;
  Result.Left := AFormat.Row.LeftTwips;
  Result.Align := AFormat.Row.Align;
  Result.Height := AFormat.Row.HeightTwips;
  Result.Cells := nil;
  SetLength(Result.Cells, Length(AFormat.Cells));
  for i := 0 to High(AFormat.Cells) do
  begin
    Result.Cells[i] := TyPlainRowCell;
    if i <= High(AEdges) then
    begin
      Result.Cells[i].Right := AEdges[i];
      Result.Cells[i].HasRight := True;
    end;
    Result.Cells[i].HMerge := AFormat.Cells[i].HMerge;
    Result.Cells[i].VMerge := AFormat.Cells[i].VMerge;
    Result.Cells[i].VAlign := AFormat.Cells[i].Props.VAlign;
    for s := Low(TTyRichCellSide) to High(TTyRichCellSide) do
      if AFormat.Cells[i].Props.Borders[s].Style <> rbsNone then
      begin
        Include(Result.Cells[i].Borders, s);
        Result.Cells[i].BorderWidth[s] := AFormat.Cells[i].Props.Borders[s].WidthTwips;
      end;
  end;
end;

{ ---- properties ---- }

function TyRichEffectiveCellProps(AFormat: TTyRichRowFormat; ACell, AWidth: Integer): TTyRichCellProps;
var
  s: TTyRichCellSide;
begin
  if (ACell >= 0) and (ACell < Length(AFormat.Cells)) then Result := AFormat.Cells[ACell].Props
  else Result := PlainCell.Props;
  for s := Low(TTyRichCellSide) to High(TTyRichCellSide) do
    if not (CPadProps[s] in Result.Valid) then Result.Pad[s] := AFormat.Row.DefaultPad[s];
  Result.WidthTwips := AWidth;
  Result.Valid := [Low(TTyRichCellProp)..High(TTyRichCellProp)];
end;

function TyRichWithCellProps(AFormat: TTyRichRowFormat; ACol0, ACol1: Integer;
  const AProps: TTyRichCellProps): TTyRichRowFormat;
var
  f: TTyRichRowFormat;
  i: Integer;
  s: TTyRichCellSide;
begin
  f := AFormat.Clone;
  if ACol0 < 0 then ACol0 := 0;
  if ACol1 > High(f.Cells) then ACol1 := High(f.Cells);
  for i := ACol0 to ACol1 do
    with f.Cells[i].Props do
    begin
      for s := Low(TTyRichCellSide) to High(TTyRichCellSide) do
      begin
        if CBorderProps[s] in AProps.Valid then Borders[s] := AProps.Borders[s];
        if CPadProps[s] in AProps.Valid then
          if AProps.Pad[s] >= 0 then
          begin
            Pad[s] := AProps.Pad[s];
            Include(Valid, CPadProps[s]);
          end
          else
          begin
            // none of its own: the row's
            Pad[s] := 0;
            Exclude(Valid, CPadProps[s]);
          end;
      end;
      if rcpShading in AProps.Valid then
        if AProps.Shading = clDefault then Shading := clNone else Shading := AProps.Shading;
      if rcpVAlign in AProps.Valid then VAlign := AProps.VAlign;
    end;
  Result := TyRichInternRowFormat(f);
end;

function TyRichWithRowProps(AFormat: TTyRichRowFormat; const AProps: TTyRichRowProps): TTyRichRowFormat;
var
  f: TTyRichRowFormat;
  s: TTyRichCellSide;
begin
  f := AFormat.Clone;
  if rrpHeight in AProps.Valid then f.Row.HeightTwips := AProps.HeightTwips;
  if rrpLeft in AProps.Valid then f.Row.LeftTwips := AProps.LeftTwips;
  if rrpAlign in AProps.Valid then f.Row.Align := AProps.Align;
  if rrpPad in AProps.Valid then
  begin
    for s := Low(TTyRichCellSide) to High(TTyRichCellSide) do
      if AProps.DefaultPad[s] >= 0 then f.Row.DefaultPad[s] := AProps.DefaultPad[s];
    f.HalfGap := f.Row.DefaultPad[rcsLeft];
  end;
  Result := TyRichInternRowFormat(f);
end;

{ ---- writing ---- }

procedure Add(var R: RawByteString; const S: string);
var
  n: Integer;
begin
  if S = '' then Exit;
  n := Length(R);
  SetLength(R, n + Length(S));
  Move(S[1], R[n + 1], Length(S));
end;

const
  CStyleWords: array[TTyRichBorderStyle] of string = ('brdrnone', 'brdrs', 'brdrdb', 'brdrdot',
    'brdrdash');

function BorderWords(const AWord: string; const B: TTyRichBorder;
  AColorIndex: TTyRichColorIndexFunc): string;
var
  k: Integer;
begin
  Result := '\' + AWord + '\' + CStyleWords[B.Style];
  if B.Style = rbsNone then Exit;
  Result := Result + '\brdrw' + IntToStr(B.WidthTwips);
  if (B.Color <> clDefault) and (B.Color <> clNone) and Assigned(AColorIndex) then
  begin
    k := AColorIndex(B.Color);
    if k > 0 then Result := Result + '\brdrcf' + IntToStr(k);
  end;
  Result := Result + ' ';
end;

function ShadingWords(AColor: TColor; AColorIndex: TTyRichColorIndexFunc): string;
var
  k: Integer;
begin
  Result := '';
  if (AColor = clNone) or (AColor = clDefault) or not Assigned(AColorIndex) then Exit;
  k := AColorIndex(AColor);
  if k > 0 then Result := '\clcbpat' + IntToStr(k);
end;

function VAlignWord(A: TTyRowCellVAlign): string;
begin
  case A of
    rcvCenter: Result := '\clvertalc';
    rcvBottom: Result := '\clvertalb';
  else
    Result := '\clvertalt';
  end;
end;

function AlignWord(A: TTyRowAlign): string;
begin
  case A of
    rraCenter: Result := '\trqc';
    rraRight: Result := '\trqr';
  else
    Result := '\trql';
  end;
end;

function MergeWords(const C: TTyRichCellFormat): string;
begin
  Result := '';
  case C.HMerge of
    rcmFirst: Result := Result + '\clmgf';
    rcmContinue: Result := Result + '\clmrg';
  end;
  case C.VMerge of
    rcmFirst: Result := Result + '\clvmgf';
    rcmContinue: Result := Result + '\clvmrg';
  end;
end;

// The word of each token of AWords (a run of control words, each with its delimiter).
function WordOf(const AToken: RawByteString): string;
var
  i: Integer;
begin
  Result := '';
  i := 2;
  while (i <= Length(AToken)) and (AToken[i] in ['a'..'z', 'A'..'Z']) do
  begin
    Result := Result + AToken[i];
    Inc(i);
  end;
end;

type
  TTokens = array of RawByteString;
  TWords = array of string;

// AWords cut into its control words, each with its number and delimiter.
function Tokens(const AWords: RawByteString): TTokens;
var
  i, n, start, k: Integer;
begin
  Result := nil;
  n := Length(AWords);
  k := 0;
  i := 1;
  while i <= n do
  begin
    if AWords[i] <> '\' then
    begin
      // (the splitter leaves no other byte between words)
      Inc(i);
      Continue;
    end;
    start := i;
    Inc(i);
    while (i <= n) and (AWords[i] in ['a'..'z', 'A'..'Z']) do Inc(i);
    if (i <= n) and (AWords[i] = '-') then Inc(i);
    while (i <= n) and (AWords[i] in ['0'..'9']) do Inc(i);
    if (i <= n) and (AWords[i] = ' ') then Inc(i);
    if k = Length(Result) then SetLength(Result, k * 2 + 8);
    Result[k] := Copy(AWords, start, i - start);
    Inc(k);
  end;
  SetLength(Result, k);
end;

function InList(const AWord: string; const AList: array of string): Boolean;
var
  i: Integer;
begin
  for i := 0 to High(AList) do
    if AWord = AList[i] then Exit(True);
  Result := False;
end;

{ The row's words without those ADrop names. }
function DropRowWords(const AWords: RawByteString; const ADrop: array of string): RawByteString;
var
  t: TTokens;
  i: Integer;
begin
  Result := '';
  t := Tokens(AWords);
  for i := 0 to High(t) do
    if (i = 0) or not InList(WordOf(t[i]), ADrop) then Add(Result, t[i]);
end;

{ A cell's words without the words of ADrop, and without the border words of the sides in
  ASides (each \clbrdrX with the line words after it). }
function DropCellWords(const AWords: RawByteString; const ADrop: array of string;
  const ASides: array of Boolean): RawByteString;
var
  t: TTokens;
  i: Integer;
  w: string;
  dropping: Boolean;
begin
  Result := '';
  t := Tokens(AWords);
  dropping := False;
  for i := 0 to High(t) do
  begin
    w := WordOf(t[i]);
    if (w = 'clbrdrl') or (w = 'clbrdrt') or (w = 'clbrdrr') or (w = 'clbrdrb') then
      dropping := ASides[Ord(SideOfLetter(w[7]))]
    else if Copy(w, 1, 2) = 'cl' then
      dropping := False;
    if dropping then Continue;
    if not InList(w, ADrop) then Add(Result, t[i]);
  end;
end;

function RowWordsFor(ABase, AFormat: TTyRichRowFormat; AAll: Boolean;
  out ADrop: TWords): string;
var
  s: TTyRichCellSide;
  n: Integer;
  gap: Boolean;

  procedure Drop(const W: string);
  begin
    if n = Length(ADrop) then SetLength(ADrop, n * 2 + 8);
    ADrop[n] := W;
    Inc(n);
  end;

begin
  Result := '';
  ADrop := nil;
  n := 0;
  if AAll or (AFormat.HalfGap <> ABase.HalfGap) then
  begin
    Drop('trgaph');
    Result := Result + '\trgaph' + IntToStr(AFormat.HalfGap);
  end;
  if AAll or (AFormat.Row.LeftTwips <> ABase.Row.LeftTwips) then
  begin
    Drop('trleft');
    Result := Result + '\trleft' + IntToStr(AFormat.Row.LeftTwips);
  end;
  if AAll or (AFormat.Row.Align <> ABase.Row.Align) then
  begin
    Drop('trql');
    Drop('trqc');
    Drop('trqr');
    Result := Result + AlignWord(AFormat.Row.Align);
  end;
  if AAll or (AFormat.Row.HeightTwips <> ABase.Row.HeightTwips) then
  begin
    Drop('trrh');
    if AFormat.Row.HeightTwips <> 0 then
      Result := Result + '\trrh' + IntToStr(AFormat.Row.HeightTwips);
  end;
  // (a new half gap: the sides that would take it say what they are)
  gap := AFormat.HalfGap <> ABase.HalfGap;
  for s := Low(TTyRichCellSide) to High(TTyRichCellSide) do
    if AAll or (AFormat.Row.DefaultPad[s] <> ABase.Row.DefaultPad[s]) or
       (gap and (s in [rcsLeft, rcsRight])) then
    begin
      Drop(CRowPadWords[s]);
      Drop(CRowPadUnits[s]);
      Result := Result + '\' + CRowPadWords[s] + IntToStr(AFormat.Row.DefaultPad[s]) + '\' +
        CRowPadUnits[s] + IntToStr(CPadTwips);
    end;
  SetLength(ADrop, n);
end;

function CellWordsFor(const ABase, AFormat: TTyRichCellFormat; AAll: Boolean;
  out ADrop: TWords; out ASides: array of Boolean; AColorIndex: TTyRichColorIndexFunc): string;
var
  s: TTyRichCellSide;
  n: Integer;

  procedure Drop(const W: string);
  begin
    if n = Length(ADrop) then SetLength(ADrop, n * 2 + 8);
    ADrop[n] := W;
    Inc(n);
  end;

begin
  Result := '';
  ADrop := nil;
  n := 0;
  for s := Low(TTyRichCellSide) to High(TTyRichCellSide) do ASides[Ord(s)] := False;
  if AAll then Result := Result + MergeWords(AFormat);
  if AAll or (AFormat.Props.VAlign <> ABase.Props.VAlign) then
  begin
    Drop('clvertalt');
    Drop('clvertalc');
    Drop('clvertalb');
    Result := Result + VAlignWord(AFormat.Props.VAlign);
  end;
  for s := Low(TTyRichCellSide) to High(TTyRichCellSide) do
    if AAll or not TyRichSameBorder(AFormat.Props.Borders[s], ABase.Props.Borders[s]) then
    begin
      ASides[Ord(s)] := True;
      if AAll and (AFormat.Props.Borders[s].Style = rbsNone) then Continue;
      Result := Result + BorderWords(CCellBorderWords[s], AFormat.Props.Borders[s], AColorIndex);
    end;
  if AAll or (AFormat.Props.Shading <> ABase.Props.Shading) then
  begin
    Drop('clcbpat');
    Drop('clcbpatraw');
    Drop('clcfpat');
    Drop('clcfpatraw');
    Drop('clshdng');
    Drop('clshdngraw');
    Result := Result + ShadingWords(AFormat.Props.Shading, AColorIndex);
  end;
  for s := Low(TTyRichCellSide) to High(TTyRichCellSide) do
    if AAll or ((CPadProps[s] in AFormat.Props.Valid) <> (CPadProps[s] in ABase.Props.Valid)) or
       ((CPadProps[s] in AFormat.Props.Valid) and (AFormat.Props.Pad[s] <> ABase.Props.Pad[s])) then
    begin
      Drop(CCellPadWords[s]);
      Drop(CCellPadUnits[s]);
      if CPadProps[s] in AFormat.Props.Valid then
        Result := Result + '\' + CCellPadWords[s] + IntToStr(AFormat.Props.Pad[s]) + '\' +
          CCellPadUnits[s] + IntToStr(CPadTwips);
    end;
  SetLength(ADrop, n);
end;

function AsRaw(const S: RawByteString): RawByteString;
begin
  Result := S;
  UniqueString(Result);
  SetCodePage(Result, CP_NONE, False);
end;

function TyRichRowFormatBytes(const ARaw: RawByteString; ABase, AFormat: TTyRichRowFormat;
  const AEdges: array of Integer; AColorIndex: TTyRichColorIndexFunc): RawByteString;
var
  rowWords: RawByteString;
  cells, newCells: TTyRtfCellWords;
  drop: TWords;
  sides: array[0..3] of Boolean;
  i: Integer;
  whole: Boolean;
  extra: string;
  plain: TTyRichCellFormat;
begin
  whole := (ARaw = '') or (ABase.CellCount <> AFormat.CellCount) or
    not TyRtfSplitRowFormat(ARaw, AFormat.CellCount, rowWords, cells);
  if whole then
  begin
    // nothing to go by: every word from the format
    Result := AsRaw('\trowd');
    extra := RowWordsFor(ABase, AFormat, True, drop);
    Add(Result, extra);
    plain := PlainCell;
    for i := 0 to High(AFormat.Cells) do
    begin
      Add(Result, CellWordsFor(plain, AFormat.Cells[i], True, drop, sides, AColorIndex));
      if i <= High(AEdges) then Add(Result, '\cellx' + IntToStr(AEdges[i]));
    end;
    Exit(AsRaw(Result));
  end;
  extra := RowWordsFor(ABase, AFormat, False, drop);
  if extra <> '' then
  begin
    rowWords := DropRowWords(rowWords, drop);
    Add(rowWords, extra);
  end;
  newCells := nil;
  SetLength(newCells, Length(cells));
  for i := 0 to High(cells) do
  begin
    extra := CellWordsFor(ABase.Cells[i], AFormat.Cells[i], False, drop, sides, AColorIndex);
    if (extra = '') and (Length(drop) = 0) then
      newCells[i] := cells[i]
    else
    begin
      newCells[i] := DropCellWords(cells[i], drop, sides);
      Add(newCells[i], extra);
    end;
  end;
  Result := TyRtfJoinRowFormat(rowWords, newCells, AEdges);
end;

procedure TyRichNoteRowColors(ABase, AFormat: TTyRichRowFormat; AColorIndex: TTyRichColorIndexFunc);
var
  i: Integer;
  s: TTyRichCellSide;
  all: Boolean;
begin
  if (ABase = AFormat) or not Assigned(AColorIndex) then Exit;
  all := ABase.CellCount <> AFormat.CellCount;
  for i := 0 to High(AFormat.Cells) do
    with AFormat.Cells[i].Props do
    begin
      for s := Low(TTyRichCellSide) to High(TTyRichCellSide) do
        if (Borders[s].Style <> rbsNone) and (Borders[s].Color <> clDefault) and
           (Borders[s].Color <> clNone) and
           (all or not TyRichSameBorder(Borders[s], ABase.Cells[i].Props.Borders[s])) then
          AColorIndex(Borders[s].Color);
      if (Shading <> clNone) and (Shading <> clDefault) and
         (all or (Shading <> ABase.Cells[i].Props.Shading)) then
        AColorIndex(Shading);
    end;
end;

procedure FreePool;
var
  i: Integer;
  f, nx: TTyRichRowFormat;
begin
  // what is left is held by objects that outlive the units (none in a clean run)
  for i := 0 to High(GBuckets) do
  begin
    f := GBuckets[i];
    while f <> nil do
    begin
      nx := f.FNext;
      f.FPooled := False;
      f := nx;
    end;
  end;
  GBuckets := nil;
  GCount := 0;
end;

finalization
  FreePool;
end.
