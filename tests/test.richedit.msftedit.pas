unit test.richedit.msftedit;

{ The system's RichEdit (msftedit.dll) as a second reader of the RTF the writer makes, for the
  suites that check that another program reads the same paragraphs, cells and rows: what the
  control holds after reading some RTF, and the model's text in that control's notation.
  Windows only; RichEditText says False where the DLL or its window class is not there (the
  caller ignores its test then). Nothing is shown: the control is a message-only window, the
  clipboard and the focus are not touched. }

{$mode objfpc}{$H+}

interface

uses
  {$IFDEF WINDOWS}Windows,{$ENDIF}
  Classes, SysUtils, tyControls.RichEdit.Model;

type
  TReRawArray = array of RawByteString;

  // What the system's RichEdit says of one paragraph's list (PARAFORMAT2): its text, the
  // numbering (0 none, 1 bullet, 2 Arabic, 3 lower letters, 4 upper letters, 5 lower roman,
  // 6 upper roman), the number it starts at, its style.
  TReListPara = record
    Text: RawByteString;
    Numbering, Start, Style: Integer;
  end;
  TReListParas = array of TReListPara;

{$IFDEF WINDOWS}
// The text the system's RichEdit holds after reading ARtf, as UTF-8 (objects U+FFFC, the
// table marks as they are). False: msftedit.dll or its window class is not there.
function RichEditText(const ARtf: TBytes; out AText: RawByteString): Boolean;
// Its paragraphs after reading ARtf, each with its list (a paragraph's text without the
// number the control makes; a marker it took as text stays in the text).
function RichEditLists(const ARtf: TBytes; out AParas: TReListParas): Boolean;
{$ENDIF}
// The model's text as that control reports a document: CR after a paragraph (none after the
// last), in a table U+FFF9 CR before a row, U+0007 after a cell, U+FFFB CR after a row; a
// picture is U+FFFC, a block the control does not know is nothing.
function ModelAsRichEditText(ADoc: TTyRichDocument): RawByteString;
// The control's text as paragraphs: a cell end ends a paragraph, the row marks and the
// marks of swallowed cells are dropped.
function AsParagraphs(const AText: RawByteString): RawByteString;
function SplitParas(const AText: RawByteString): TReRawArray;

implementation

function U(ACode: Cardinal): UTF8String;
begin
  Result := '';
  if ACode < $80 then
    Result := AnsiChar(ACode)
  else if ACode < $800 then
  begin
    SetLength(Result, 2);
    Result[1] := AnsiChar($C0 or (ACode shr 6));
    Result[2] := AnsiChar($80 or (ACode and $3F));
  end
  else if ACode < $10000 then
  begin
    SetLength(Result, 3);
    Result[1] := AnsiChar($E0 or (ACode shr 12));
    Result[2] := AnsiChar($80 or ((ACode shr 6) and $3F));
    Result[3] := AnsiChar($80 or (ACode and $3F));
  end
  else
  begin
    SetLength(Result, 4);
    Result[1] := AnsiChar($F0 or (ACode shr 18));
    Result[2] := AnsiChar($80 or ((ACode shr 12) and $3F));
    Result[3] := AnsiChar($80 or ((ACode shr 6) and $3F));
    Result[4] := AnsiChar($80 or (ACode and $3F));
  end;
end;

procedure Cat(var R: RawByteString; const S: RawByteString);
var
  n: Integer;
begin
  if S = '' then Exit;
  n := Length(R);
  SetLength(R, n + Length(S));
  Move(S[1], R[n + 1], Length(S));
end;

function Raw(const S: UTF8String): RawByteString;
begin
  Result := '';
  Cat(Result, S);
end;

function ParaText(ADoc: TTyRichDocument; AIndex: Integer): RawByteString;
begin
  Result := ADoc.Text.GetText(ADoc.Text.ParaStart(AIndex), ADoc.Text.ParaLength(AIndex));
  SetCodePage(Result, CP_NONE, False);
end;

function CharOffset(const S: RawByteString; AChar: Integer): Integer;
begin
  Result := 0;
  while (Result < Length(S)) and (AChar > 0) do
  begin
    Inc(Result);
    while (Result < Length(S)) and (Byte(S[Result + 1]) and $C0 = $80) do Inc(Result);
    Dec(AChar);
  end;
end;

{$IFDEF WINDOWS}
type
  // richedit.h declares its structures under #pragma pack(4), on Win64 too
  {$PUSH}{$PACKRECORDS 4}
  TReEditStream = record
    dwCookie: PtrUInt;
    dwError: DWORD;
    pfnCallback: Pointer;
  end;
  TReGetTextEx = record
    cb: DWORD;
    flags: DWORD;
    codepage: UINT;
    lpDefaultChar: PAnsiChar;
    lpUsedDefChar: Pointer;
  end;
  TReGetTextLengthEx = record
    flags: DWORD;
    codepage: UINT;
  end;
  TReParaFormat2 = record
    cbSize: UINT;
    dwMask: DWORD;
    wNumbering: WORD;
    wEffects: WORD;
    dxStartIndent: LONG;
    dxRightIndent: LONG;
    dxOffset: LONG;
    wAlignment: WORD;
    cTabCount: SHORT;
    rgxTabs: array[0..31] of LONG;
    dySpaceBefore: LONG;
    dySpaceAfter: LONG;
    dyLineSpacing: LONG;
    sStyle: SHORT;
    bLineSpacingRule: BYTE;
    bOutlineLevel: BYTE;
    wShadingWeight: WORD;
    wShadingStyle: WORD;
    wNumberingStart: WORD;
    wNumberingStyle: WORD;
    wNumberingTab: WORD;
    wBorderSpace: WORD;
    wBorderWidth: WORD;
    wBorders: WORD;
  end;
  {$POP}

  TReSource = record
    Data: PByte;
    Left: Int64;
  end;
  PReSource = ^TReSource;

const
  ReEmExLimitText = WM_USER + 53;
  ReEmStreamIn = WM_USER + 73;
  ReEmGetTextEx = WM_USER + 94;
  ReEmGetTextLengthEx = WM_USER + 95;
  ReSfRtf = 2;
  ReGtRawText = 4;
  ReEmSetSel = $B1;
  ReEmGetParaFormat = WM_USER + 61;

function ReStreamIn(dwCookie: PtrUInt; pbBuff: PByte; cb: LongInt; pcb: PLongInt): DWORD; stdcall;
var
  src: PReSource;
  n: LongInt;
begin
  src := PReSource(dwCookie);
  n := cb;
  if n > src^.Left then n := src^.Left;
  if n > 0 then Move(src^.Data^, pbBuff^, n);
  Inc(src^.Data, n);
  Dec(src^.Left, n);
  pcb^ := n;
  Result := 0;
end;

function RichEditText(const ARtf: TBytes; out AText: RawByteString): Boolean;
var
  h: HWND;
  es: TReEditStream;
  src: TReSource;
  gl: TReGetTextLengthEx;
  gt: TReGetTextEx;
  n, got: PtrInt;
  buf: UnicodeString;
  u8: UTF8String;
begin
  AText := '';
  if LoadLibraryW('msftedit.dll') = 0 then Exit(False);
  // a message-only window: nothing is shown, the clipboard and the focus are not touched
  h := CreateWindowExW(0, 'RICHEDIT50W', '', ES_MULTILINE, 0, 0, 800, 600, HWND(PtrInt(-3)), 0,
    HInstance, nil);
  if h = 0 then Exit(False);
  try
    SendMessageW(h, ReEmExLimitText, 0, $7FFFFFF);
    src.Data := nil;
    if Length(ARtf) > 0 then src.Data := @ARtf[0];
    src.Left := Length(ARtf);
    es.dwCookie := PtrUInt(@src);
    es.dwError := 0;
    es.pfnCallback := @ReStreamIn;
    SendMessageW(h, ReEmStreamIn, ReSfRtf, LPARAM(@es));
    gl.flags := 0;
    gl.codepage := 1200;
    n := SendMessageW(h, ReEmGetTextLengthEx, WPARAM(@gl), 0);
    buf := '';
    SetLength(buf, n + 1);
    gt.cb := (n + 1) * 2;
    gt.flags := ReGtRawText;
    gt.codepage := 1200;
    gt.lpDefaultChar := nil;
    gt.lpUsedDefChar := nil;
    got := SendMessageW(h, ReEmGetTextEx, WPARAM(@gt), LPARAM(PWideChar(buf)));
    SetLength(buf, got);
    u8 := UTF8Encode(buf);
    AText := u8;
    SetCodePage(AText, CP_NONE, False);
    Result := True;
  finally
    DestroyWindow(h);
  end;
end;

function RichEditLists(const ARtf: TBytes; out AParas: TReListParas): Boolean;
var
  h: HWND;
  es: TReEditStream;
  src: TReSource;
  gl: TReGetTextLengthEx;
  gt: TReGetTextEx;
  n, got, i, from, k: PtrInt;
  buf: UnicodeString;
  pf: TReParaFormat2;
  u8: UTF8String;
begin
  AParas := nil;
  if LoadLibraryW('msftedit.dll') = 0 then Exit(False);
  h := CreateWindowExW(0, 'RICHEDIT50W', '', ES_MULTILINE, 0, 0, 800, 600, HWND(PtrInt(-3)), 0,
    HInstance, nil);
  if h = 0 then Exit(False);
  try
    SendMessageW(h, ReEmExLimitText, 0, $7FFFFFF);
    src.Data := nil;
    if Length(ARtf) > 0 then src.Data := @ARtf[0];
    src.Left := Length(ARtf);
    es.dwCookie := PtrUInt(@src);
    es.dwError := 0;
    es.pfnCallback := @ReStreamIn;
    SendMessageW(h, ReEmStreamIn, ReSfRtf, LPARAM(@es));
    gl.flags := 0;
    gl.codepage := 1200;
    n := SendMessageW(h, ReEmGetTextLengthEx, WPARAM(@gl), 0);
    buf := '';
    SetLength(buf, n + 1);
    gt.cb := (n + 1) * 2;
    gt.flags := ReGtRawText;
    gt.codepage := 1200;
    gt.lpDefaultChar := nil;
    gt.lpUsedDefChar := nil;
    got := SendMessageW(h, ReEmGetTextEx, WPARAM(@gt), LPARAM(PWideChar(buf)));
    SetLength(buf, got);
    // a paragraph ends with CR; its format is asked at its first character
    k := 0;
    from := 1;
    for i := 1 to Length(buf) + 1 do
      if (i > Length(buf)) or (buf[i] = #13) then
      begin
        SetLength(AParas, k + 1);
        u8 := UTF8Encode(Copy(buf, from, i - from));
        AParas[k].Text := u8;
        SetCodePage(AParas[k].Text, CP_NONE, False);
        SendMessageW(h, ReEmSetSel, from - 1, from - 1);
        FillChar(pf, SizeOf(pf), 0);
        pf.cbSize := SizeOf(pf);
        SendMessageW(h, ReEmGetParaFormat, 0, LPARAM(@pf));
        AParas[k].Numbering := pf.wNumbering;
        AParas[k].Start := pf.wNumberingStart;
        AParas[k].Style := pf.wNumberingStyle;
        Inc(k);
        from := i + 1;
      end;
    Result := True;
  finally
    DestroyWindow(h);
  end;
end;
{$ENDIF}

function ModelAsRichEditText(ADoc: TTyRichDocument): RawByteString;
var
  rowStart, rowEnd: RawByteString;
  i, j, last: Integer;
  runs: TTyRunArray;
  text, part: RawByteString;
  cell, next, prev: TTyRichCell;
  from, upto: Integer;
begin
  Result := '';
  rowStart := Raw(U($FFF9) + #13);
  rowEnd := Raw(U($FFFB) + #13);
  last := ADoc.Text.ParaCount - 1;
  prev := nil;
  for i := 0 to last do
  begin
    cell := ADoc.CellAt(i);
    if i < last then next := ADoc.CellAt(i + 1) else next := nil;
    if (cell <> nil) and ((prev = nil) or (prev.Row <> cell.Row)) then Cat(Result, rowStart);
    text := ParaText(ADoc, i);
    runs := ADoc.RunsOf(i);
    for j := 0 to High(runs) do
    begin
      from := CharOffset(text, runs[j].Start);
      if j < High(runs) then upto := CharOffset(text, runs[j + 1].Start) else upto := Length(text);
      part := Copy(text, from + 1, upto - from);
      if runs[j].Obj is TTyRichOpaque then part := '';
      Cat(Result, part);
    end;
    if cell = nil then
    begin
      if i < last then Cat(Result, #13);
    end
    else if next = cell then
      Cat(Result, #13)
    else
    begin
      Cat(Result, #7);
      if (next = nil) or (next.Row <> cell.Row) then Cat(Result, rowEnd);
    end;
    prev := cell;
  end;
end;

function AsParagraphs(const AText: RawByteString): RawByteString;
var
  i, n: Integer;
begin
  Result := '';
  n := Length(AText);
  i := 1;
  while i <= n do
  begin
    // U+FFF9 CR and U+FFFB CR: EF BF B9 0D, EF BF BB 0D
    if (i + 3 <= n) and (AText[i] = #$EF) and (AText[i + 1] = #$BF) and
       (AText[i + 2] in [#$B9, #$BB]) and (AText[i + 3] = #13) then
      Inc(i, 4)
    // U+FFFF: what the control puts in a cell that a merged one swallowed
    else if (i + 2 <= n) and (AText[i] = #$EF) and (AText[i + 1] = #$BF) and (AText[i + 2] = #$BF) then
      Inc(i, 3)
    else
    begin
      if AText[i] = #7 then Cat(Result, #13) else Cat(Result, AText[i]);
      Inc(i);
    end;
  end;
end;

function SplitParas(const AText: RawByteString): TReRawArray;
var
  i, from, n: Integer;
begin
  Result := nil;
  n := 0;
  from := 1;
  for i := 1 to Length(AText) + 1 do
    if (i > Length(AText)) or (AText[i] = #13) then
    begin
      SetLength(Result, n + 1);
      Result[n] := Copy(AText, from, i - from);
      Inc(n);
      from := i + 1;
    end;
end;

end.
