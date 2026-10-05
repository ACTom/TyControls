unit tbdiff;
{ A line diff for the AI comparison window, and the one edit that puts the AI's version into
  the editor.

  TbDiffLines: the common first and last lines go first; the lines in between are matched
  by a longest-common-subsequence table (light.tycss, the longest theme in the repository,
  is 1409 lines: about two million cells when nothing is common at the ends). Above
  TbDiffMaxCells the middle is taken as removed and added as a whole -- not wrong, only
  coarse. A run of removed lines right before a run of added ones pairs up into changed
  lines (shown side by side); what is left over stays removed or added. A side that has no
  line for a row gets a filler there, so both sides of the window line up.

  TbWholeTextEdit: "accept" replaces the whole text in meaning (one undo step), but as one
  edit over the lines that differ only -- the lines around it, and the editor's caret,
  marks and bookmarks on them, are not touched. Both texts are compared with their line
  breaks made the same; when the last lines differ too, the final line break both share
  stays out of the edit, so the edit always ends inside the text. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, tbcssscan;

type
  TTbDiffKind = (tdkSame, tdkRemoved, tdkAdded, tdkChanged);
  TTbDiffRow = record
    Kind: TTbDiffKind;
    Left, Right: Integer;         { 0-based line index; -1 = a filler on that side }
  end;
  TTbDiffRows = array of TTbDiffRow;

const
  TbDiffMaxCells = 4000000;

{ any break (CRLF, LF, CR); a final break adds no line; '' is no line at all }
procedure TbSplitLines(const AText: string; ALines: TStrings);
function TbDiffLines(AOld, ANew: TStrings; AMaxCells: Integer = TbDiffMaxCells): TTbDiffRows;
{ runs of rows that are not tdkSame }
function TbDiffChangeCount(const ARows: TTbDiffRows): Integer;
{ every break -> LineEnding, and one at the end ('' stays '') }
function TbNormalizeEol(const AText: string): string;
{ the differing whole lines in the middle, as one edit on TbNormalizeEol(AOld) }
function TbWholeTextEdit(const AOld, ANew: string): TTbTextEdit;

implementation

procedure TbSplitLines(const AText: string; ALines: TStrings);
var
  i, start, n: Integer;
begin
  ALines.BeginUpdate;
  try
    ALines.Clear;
    n := Length(AText);
    i := 1;
    start := 1;
    while i <= n do
    begin
      if AText[i] = #13 then
      begin
        ALines.Add(Copy(AText, start, i - start));
        if (i < n) and (AText[i + 1] = #10) then
          Inc(i);
        start := i + 1;
      end
      else if AText[i] = #10 then
      begin
        ALines.Add(Copy(AText, start, i - start));
        start := i + 1;
      end;
      Inc(i);
    end;
    if start <= n then
      ALines.Add(Copy(AText, start, MaxInt));
  finally
    ALines.EndUpdate;
  end;
end;

function Row(AKind: TTbDiffKind; ALeft, ARight: Integer): TTbDiffRow;
begin
  Result.Kind := AKind;
  Result.Left := ALeft;
  Result.Right := ARight;
end;

function TbDiffLines(AOld, ANew: TStrings; AMaxCells: Integer): TTbDiffRows;
var
  raw: TTbDiffRows;
  nRaw: Integer;
  n0, m0, p, s, n, m, i, j, k, a, b, out_: Integer;
  lcs: array of array of Integer;

  procedure Put(AKind: TTbDiffKind; ALeft, ARight: Integer);
  begin
    if nRaw >= Length(raw) then
      SetLength(raw, nRaw * 2 + 16);
    raw[nRaw] := Row(AKind, ALeft, ARight);
    Inc(nRaw);
  end;

begin
  raw := nil;
  nRaw := 0;
  n0 := AOld.Count;
  m0 := ANew.Count;
  p := 0;
  while (p < n0) and (p < m0) and (AOld[p] = ANew[p]) do
    Inc(p);
  s := 0;
  while (s < n0 - p) and (s < m0 - p) and (AOld[n0 - 1 - s] = ANew[m0 - 1 - s]) do
    Inc(s);
  for i := 0 to p - 1 do
    Put(tdkSame, i, i);
  n := n0 - p - s;
  m := m0 - p - s;
  if (n > 0) and (m > 0) and (Int64(n) * Int64(m) <= AMaxCells) then
  begin
    { lcs[i][j] = the longest common run of old[p+i..] and new[p+j..] }
    SetLength(lcs, n + 1, m + 1);
    for i := n - 1 downto 0 do
      for j := m - 1 downto 0 do
        if AOld[p + i] = ANew[p + j] then
          lcs[i][j] := lcs[i + 1][j + 1] + 1
        else if lcs[i + 1][j] >= lcs[i][j + 1] then
          lcs[i][j] := lcs[i + 1][j]
        else
          lcs[i][j] := lcs[i][j + 1];
    i := 0;
    j := 0;
    while (i < n) and (j < m) do
      if AOld[p + i] = ANew[p + j] then
      begin
        Put(tdkSame, p + i, p + j);
        Inc(i);
        Inc(j);
      end
      else if lcs[i + 1][j] >= lcs[i][j + 1] then
      begin
        Put(tdkRemoved, p + i, -1);
        Inc(i);
      end
      else
      begin
        Put(tdkAdded, -1, p + j);
        Inc(j);
      end;
    while i < n do
    begin
      Put(tdkRemoved, p + i, -1);
      Inc(i);
    end;
    while j < m do
    begin
      Put(tdkAdded, -1, p + j);
      Inc(j);
    end;
    lcs := nil;
  end
  else
  begin
    { too big to match line by line (or one side empty): removed, then added }
    for i := 0 to n - 1 do
      Put(tdkRemoved, p + i, -1);
    for j := 0 to m - 1 do
      Put(tdkAdded, -1, p + j);
  end;
  for i := 0 to s - 1 do
    Put(tdkSame, n0 - s + i, m0 - s + i);

  { a run of removed lines right before a run of added ones: changed, pair by pair }
  SetLength(Result, nRaw);
  out_ := 0;
  k := 0;
  while k < nRaw do
  begin
    if raw[k].Kind <> tdkRemoved then
    begin
      Result[out_] := raw[k];
      Inc(out_);
      Inc(k);
      Continue;
    end;
    a := k;
    while (a < nRaw) and (raw[a].Kind = tdkRemoved) do
      Inc(a);
    b := a;
    while (b < nRaw) and (raw[b].Kind = tdkAdded) do
      Inc(b);
    { removed: k .. a-1; added: a .. b-1 }
    i := 0;
    while (k + i < a) and (a + i < b) do
    begin
      Result[out_] := Row(tdkChanged, raw[k + i].Left, raw[a + i].Right);
      Inc(out_);
      Inc(i);
    end;
    for j := k + i to a - 1 do
    begin
      Result[out_] := raw[j];
      Inc(out_);
    end;
    for j := a + i to b - 1 do
    begin
      Result[out_] := raw[j];
      Inc(out_);
    end;
    k := b;
  end;
  SetLength(Result, out_);
end;

function TbDiffChangeCount(const ARows: TTbDiffRows): Integer;
var
  i: Integer;
  inRun: Boolean;
begin
  Result := 0;
  inRun := False;
  for i := 0 to High(ARows) do
    if ARows[i].Kind = tdkSame then
      inRun := False
    else if not inRun then
    begin
      Inc(Result);
      inRun := True;
    end;
end;

function TbNormalizeEol(const AText: string): string;
begin
  if AText = '' then
    Exit('');
  Result := StringReplace(AText, #13#10, #10, [rfReplaceAll]);
  Result := StringReplace(Result, #13, #10, [rfReplaceAll]);
  if LineEnding <> #10 then
    Result := StringReplace(Result, #10, LineEnding, [rfReplaceAll]);
  if Copy(Result, Length(Result) - Length(LineEnding) + 1, Length(LineEnding)) <> LineEnding then
    Result := Result + LineEnding;
end;

{ the text cut into lines, each with its own LineEnding (the text is normalised) }
procedure CutLines(const AText: string; ALines: TStrings);
var
  p, start, e: Integer;
begin
  ALines.Clear;
  e := Length(LineEnding);
  start := 1;
  p := Pos(LineEnding, AText);
  while p > 0 do
  begin
    ALines.Add(Copy(AText, start, p + e - start));
    start := p + e;
    p := Pos(LineEnding, Copy(AText, start, MaxInt));
    if p > 0 then
      p := p + start - 1;
  end;
  if start <= Length(AText) then
    ALines.Add(Copy(AText, start, MaxInt));
end;

function TbWholeTextEdit(const AOld, ANew: string): TTbTextEdit;
var
  o, nw: string;
  lo, ln: TStringList;
  p, s, i, prefixBytes, suffixOld, suffixNew, e: Integer;
  midNew: string;
begin
  o := TbNormalizeEol(AOld);
  nw := TbNormalizeEol(ANew);
  if o = nw then
    Exit(TbEdit(1, 1, ''));
  lo := TStringList.Create;
  ln := TStringList.Create;
  try
    CutLines(o, lo);
    CutLines(nw, ln);
    p := 0;
    while (p < lo.Count) and (p < ln.Count) and (lo[p] = ln[p]) do
      Inc(p);
    s := 0;
    while (s < lo.Count - p) and (s < ln.Count - p) and
          (lo[lo.Count - 1 - s] = ln[ln.Count - 1 - s]) do
      Inc(s);
    prefixBytes := 0;
    for i := 0 to p - 1 do
      Inc(prefixBytes, Length(lo[i]));
    suffixOld := 0;
    for i := lo.Count - s to lo.Count - 1 do
      Inc(suffixOld, Length(lo[i]));
    suffixNew := 0;
    for i := ln.Count - s to ln.Count - 1 do
      Inc(suffixNew, Length(ln[i]));
  finally
    lo.Free;
    ln.Free;
  end;
  midNew := Copy(nw, prefixBytes + 1, Length(nw) - suffixNew - prefixBytes);
  Result := TbEdit(prefixBytes + 1, Length(o) - suffixOld + 1, midNew);
  e := Length(LineEnding);
  if (s = 0) and (Result.Stop > Length(o)) and (o <> '') then
  begin
    { the last lines differ too: the line break both texts end with stays where it is }
    if Result.Start > Length(o) then
    begin
      { only lines added at the very end: they go in before the final break }
      Result.Start := Length(o) + 1 - e;
      Result.Stop := Result.Start;
      Result.Text := LineEnding + Copy(midNew, 1, Length(midNew) - e);
    end
    else if midNew <> '' then
    begin
      Dec(Result.Stop, e);
      SetLength(Result.Text, Length(Result.Text) - e);
    end
    else if Result.Start > 1 then
    begin
      { lines removed at the very end: take the break before them instead }
      Dec(Result.Start, e);
      Dec(Result.Stop, e);
    end;
  end;
end;

end.
