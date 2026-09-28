unit tyControls.Unicode.Width;
{$mode objfpc}{$H+}

{ Character width, the grapheme join state and string cell width, exactly as xterm.js
  computes them. Pure functions; the tables are constants.

  PORTED FROM xterm.js 6.0.0, commit c58ea3637f39 (the full hash is in the header of
  tyControls.Unicode.Width.Data.inc):
    src/common/input/UnicodeV6.ts                                   version '6'
    addons/addon-unicode11/src/UnicodeV11.ts                        version '11'
    addons/addon-unicode-graphemes/src/UnicodeGraphemeProvider.ts   '15', '15-graphemes'
    addons/addon-unicode-graphemes/src/third-party/UnicodeProperties.ts
      -- the join rules only (shouldJoin / _shouldJoin). The addon took these rules, and
         the '15' table data, from the unicode-properties project
         (https://github.com/PerBothner/unicode-properties, MIT, Copyright 2018). The
         trie decoder is not ported: the tables in the .inc are dumped from upstream by
         tools/terminal-oracle/gen-unicode-tables.js.
    src/common/services/UnicodeService.ts                           packing, string width

    Copyright (c) 2017-2019, The xterm.js authors (https://github.com/xtermjs/xterm.js)
    Copyright (c) 2014-2016, SourceLair Private Company (https://www.sourcelair.com)
    Copyright (c) 2012-2013, Christopher Jeffrey (https://github.com/chjj/)
    Copyright (c) 2019, The xterm.js authors (https://github.com/xtermjs/xterm.js)
    Copyright (c) 2023, The xterm.js authors (https://github.com/xtermjs/xterm.js)
    Copyright 2018 (unicode-properties)
  MIT; the full text is in THIRD-PARTY-NOTICES.md. The '15' table derives from the
  Unicode Character Database (Unicode License v3, same file).

  FOUR THINGS THAT LOOK WRONG AND ARE UPSTREAM'S ANSWER, kept so every result matches
  xterm.js bit for bit (tests/test.unicode.width.pas holds them to the oracle):

  - '15' without graphemes never joins. The provider widens every w below 2 to 1, and
    its non-grapheme branch joins only when w is 0, so a combining mark takes a cell of
    its own there: 'e' + U+0301 is 2 cells wide, while its wcwidth is 0. Choose
    '15-graphemes' to get combining marks and clusters.
  - U+0301 and many other combining marks are East Asian ambiguous in the '15' table.
    With AAmbiguousWide, 'e' + U+0301 is 3 cells under '15' and 2 under '15-graphemes'.
  - Under '15', C0/C1 controls and U+200D have wcwidth 1 (the trie files them as
    Other / normal width); '6' and '11' say 0. The print path never sends C0 here.
  - TyUnicodeStringCellWidth takes UTF-8, but upstream loops over UTF-16 units and has
    a UCS-2 fallback for lone surrogates. To reach it, the input is read as WTF-8: a
    three-byte sequence for U+D800..U+DFFF gives that lone surrogate unit (so a pair
    written as two such sequences meets the loop as a pair, as the units would). Any
    other malformed byte gives one U+FFFD and consumes only that byte (upstream never
    sees such input, so there is nothing to match there). }

interface

uses
  SysUtils;

type
  TTyUnicodeVersion = (tuv6, tuv11, tuv15, tuv15Graphemes);
  TTyUnicodeCharProps = type Cardinal;   { state shl 3 or width shl 1 or Ord(shouldJoin) }

{ 0..2. AAmbiguousWide has no effect under tuv6 / tuv11 (upstream has no data there). }
function TyUnicodeWcWidth(ACodepoint: Cardinal; AVersion: TTyUnicodeVersion;
  AAmbiguousWide: Boolean): Integer;
{ UnicodeService.charProperties: the packed state after ACodepoint follows APreceding
  (0 = start of string). }
function TyUnicodeCharProperties(ACodepoint: Cardinal; APreceding: TTyUnicodeCharProps;
  AVersion: TTyUnicodeVersion; AAmbiguousWide: Boolean): TTyUnicodeCharProps;
function TyUnicodePropsWidth(AProps: TTyUnicodeCharProps): Integer;       { extractWidth }
function TyUnicodePropsShouldJoin(AProps: TTyUnicodeCharProps): Boolean;  { extractShouldJoin }
function TyUnicodePropsKind(AProps: TTyUnicodeCharProps): Cardinal;       { extractCharKind }
{ UnicodeService.getStringCellWidth over the UTF-16 units of AUtf8 read as WTF-8. }
function TyUnicodeStringCellWidth(const AUtf8: string; AVersion: TTyUnicodeVersion;
  AAmbiguousWide: Boolean): Integer;
{ '6' '11' '15' '15-graphemes' -- upstream's activeVersion strings. }
function TyUnicodeVersionName(AVersion: TTyUnicodeVersion): string;

implementation

{$I tyControls.Unicode.Width.Data.inc}

const
  { UnicodeProperties.ts: GRAPHEME_BREAK_* and CHARWIDTH_* }
  GB_MASK = $F;
  GB_Other = 0; GB_Prepend = 1; GB_Extend = 2; GB_RegionalIndicator = 3;
  GB_SpacingMark = 4; GB_HangulL = 5; GB_HangulV = 6; GB_HangulT = 7;
  GB_HangulLV = 8; GB_HangulLVT = 9; GB_ZWJ = 10; GB_ExtPic = 11;
  GB_SawRegionalPair = 32;   { only ever returned by ShouldJoin15 }
  CW_MASK = $30; CW_SHIFT = 4;
  CW_Wide = 3;
  MaxCodepoint = $10FFFF;

var
  GBmp6, GBmp11: array[0..$FFFF] of Byte;   { filled in initialization (spec 17.2 #5) }

{ Index of the run holding ACp: the last k with AStarts[k] <= ACp. AStarts[0] is 0. }
function RunIndex(const AStarts: array of Cardinal; ACp: Cardinal): Integer;
var
  lo, hi, mid: Integer;
begin
  lo := 0;
  hi := High(AStarts);
  while lo < hi do
  begin
    mid := (lo + hi + 1) shr 1;
    if AStarts[mid] <= ACp then
      lo := mid
    else
      hi := mid - 1;
  end;
  Result := lo;
end;

{ UnicodeService.createPropertyValue: state masked to 24 bits -- it is negative for
  "no join" under 15-graphemes. }
function MakeProps(AState, AWidth: Integer; AShouldJoin: Boolean): TTyUnicodeCharProps;
begin
  Result := TTyUnicodeCharProps(((Cardinal(AState) and $FFFFFF) shl 3)
    or ((Cardinal(AWidth) and 3) shl 1) or Cardinal(Ord(AShouldJoin)));
end;

function TyUnicodePropsWidth(AProps: TTyUnicodeCharProps): Integer;
begin
  Result := (AProps shr 1) and 3;
end;

function TyUnicodePropsShouldJoin(AProps: TTyUnicodeCharProps): Boolean;
begin
  Result := (AProps and 1) <> 0;
end;

function TyUnicodePropsKind(AProps: TTyUnicodeCharProps): Cardinal;
begin
  Result := AProps shr 3;
end;

{ ---- 6 and 11: UnicodeV6.ts / UnicodeV11.ts ---- }

function LegacyWcWidth(ACp: Cardinal; AVersion: TTyUnicodeVersion): Integer;
begin
  if ACp > MaxCodepoint then
  begin
    if AVersion = tuv6 then Exit(TyUniV6OutOfRange) else Exit(TyUniV11OutOfRange);
  end;
  if ACp <= $FFFF then
  begin
    if AVersion = tuv6 then Exit(GBmp6[ACp]) else Exit(GBmp11[ACp]);
  end;
  if AVersion = tuv6 then
    Result := TyUniV6Width[RunIndex(TyUniV6Start, ACp)]
  else
    Result := TyUniV11Width[RunIndex(TyUniV11Start, ACp)];
end;

{ UnicodeV6.ts:132-145 (UnicodeV11.ts:222-234 is the same code). }
function LegacyCharProps(ACp: Cardinal; APreceding: TTyUnicodeCharProps;
  AVersion: TTyUnicodeVersion): TTyUnicodeCharProps;
var
  width, oldWidth: Integer;
  shouldJoin: Boolean;
begin
  width := LegacyWcWidth(ACp, AVersion);
  shouldJoin := (width = 0) and (APreceding <> 0);
  if shouldJoin then
  begin
    oldWidth := TyUnicodePropsWidth(APreceding);
    if oldWidth = 0 then
      shouldJoin := False
    else if oldWidth > width then
      width := oldWidth;
  end;
  Result := MakeProps(0, width, shouldJoin);
end;

{ ---- 15 and 15-graphemes: UnicodeGraphemeProvider.ts + UnicodeProperties.ts ---- }

function Info15(ACp: Cardinal): Cardinal;
begin
  if ACp > MaxCodepoint then Exit(TyUniV15OutOfRangeInfo);
  Result := TyUniV15Info[RunIndex(TyUniV15Start, ACp)];
end;

{ UnicodeGraphemeProvider.ts:60-71 }
function WcWidth15(ACp: Cardinal; AAmbiguousWide: Boolean): Integer;
var
  info, w, kind: Cardinal;
begin
  info := Info15(ACp);
  w := (info and CW_MASK) shr CW_SHIFT;
  kind := info and GB_MASK;
  if (kind = GB_Extend) or (kind = GB_Prepend) then Exit(0);
  if (w >= 2) and ((w = CW_Wide) or AAmbiguousWide) then Exit(2);
  Result := 1;
end;

{ UnicodeProperties.ts _shouldJoin: GB6-GB13, simplified upstream (no GB9c; GB11
  looks only at the code point before). }
function JoinRule(ABefore, AAfter: Cardinal): Boolean;
begin
  if (ABefore >= GB_HangulL) and (ABefore <= GB_HangulLVT) then
  begin
    if (ABefore = GB_HangulL) and ((AAfter = GB_HangulL) or (AAfter = GB_HangulV)
      or (AAfter = GB_HangulLV) or (AAfter = GB_HangulLVT)) then Exit(True);      { GB6 }
    if ((ABefore = GB_HangulLV) or (ABefore = GB_HangulV))
      and ((AAfter = GB_HangulV) or (AAfter = GB_HangulT)) then Exit(True);        { GB7 }
    if ((ABefore = GB_HangulLVT) or (ABefore = GB_HangulT))
      and (AAfter = GB_HangulT) then Exit(True);                                    { GB8 }
  end;
  if (AAfter = GB_Extend) or (AAfter = GB_ZWJ) or (ABefore = GB_Prepend)
    or (AAfter = GB_SpacingMark) then Exit(True);                                   { GB9, GB9a, GB9b }
  if (ABefore = GB_ZWJ) and (AAfter = GB_ExtPic) then Exit(True);                   { GB11 }
  if (AAfter = GB_RegionalIndicator) and (ABefore = GB_RegionalIndicator) then
    Exit(True);                                                                     { GB12, GB13 }
  Result := False;
end;

{ UnicodeProperties.ts shouldJoin: > 0 joins, <= 0 breaks. }
function ShouldJoin15(ABeforeState, AAfterInfo: Cardinal): Integer;
var
  b, a: Cardinal;
begin
  b := ABeforeState and GB_MASK;
  a := AAfterInfo and GB_MASK;
  if JoinRule(b, a) then
  begin
    if a = GB_RegionalIndicator then
      Result := GB_SawRegionalPair
    else
      Result := Integer(a) + 16;
  end
  else
    Result := Integer(a) - 16;
end;

{ UnicodeGraphemeProvider.ts:24-58 }
function CharProps15(ACp: Cardinal; APreceding: TTyUnicodeCharProps;
  AGraphemes, AAmbiguousWide: Boolean): TTyUnicodeCharProps;
var
  info, w, oldWidth: Integer;
  wi: Cardinal;
  shouldJoin: Boolean;
begin
  { the ASCII fast path, valid only while the preceding kind is Other (:25-30) }
  if (ACp >= 32) and (ACp < 127) and ((APreceding shr 3) = 0) then
    Exit(MakeProps(GB_Other, 1, False));
  info := Integer(Info15(ACp));
  wi := (Cardinal(info) and CW_MASK) shr CW_SHIFT;
  if wi >= 2 then
  begin
    { emoji presentation selector U+FE0F counts as wide (:37) }
    if (wi = CW_Wide) or AAmbiguousWide or (ACp = $FE0F) then w := 2 else w := 1;
  end
  else
    w := 1;
  shouldJoin := False;
  if APreceding <> 0 then
  begin
    oldWidth := TyUnicodePropsWidth(APreceding);
    if AGraphemes then
      info := ShouldJoin15(TyUnicodePropsKind(APreceding), Cardinal(info))
    else if w = 0 then   { never true: w is 1 or 2 here. Upstream's line, kept as is (:46). }
      info := 1
    else
      info := 0;
    shouldJoin := info > 0;
    if shouldJoin then
    begin
      if oldWidth > w then
        w := oldWidth
      else if info = GB_SawRegionalPair then
        w := 2;
    end;
  end;
  Result := MakeProps(info, w, shouldJoin);
end;

{ ---- public ---- }

function TyUnicodeWcWidth(ACodepoint: Cardinal; AVersion: TTyUnicodeVersion;
  AAmbiguousWide: Boolean): Integer;
begin
  case AVersion of
    tuv6, tuv11: Result := LegacyWcWidth(ACodepoint, AVersion);
  else
    Result := WcWidth15(ACodepoint, AAmbiguousWide);
  end;
end;

function TyUnicodeCharProperties(ACodepoint: Cardinal; APreceding: TTyUnicodeCharProps;
  AVersion: TTyUnicodeVersion; AAmbiguousWide: Boolean): TTyUnicodeCharProps;
begin
  case AVersion of
    tuv6, tuv11: Result := LegacyCharProps(ACodepoint, APreceding, AVersion);
    tuv15: Result := CharProps15(ACodepoint, APreceding, False, AAmbiguousWide);
  else
    Result := CharProps15(ACodepoint, APreceding, True, AAmbiguousWide);
  end;
end;

{ UTF-8 -> UTF-16 code units. WTF-8: a three-byte sequence for U+D800..U+DFFF gives
  that lone surrogate, so upstream's UCS-2 fallback is reachable from UTF-8. Any other
  malformed byte gives one U+FFFD and consumes that byte only. }
function Wtf8ToUnits(const S: string): UnicodeString;
var
  i, j, k, n, need: Integer;
  b: Byte;
  cp, lo, hi: Cardinal;
begin
  n := Length(S);
  SetLength(Result, n);   { never more units than bytes }
  i := 1;
  k := 0;
  while i <= n do
  begin
    b := Ord(S[i]);
    lo := $80;
    hi := $BF;
    cp := 0;
    case b of
      $00..$7F: begin need := 0; cp := b; end;
      $C2..$DF: begin need := 1; cp := b and $1F; end;
      $E0:      begin need := 2; cp := b and $0F; lo := $A0; end;
      $E1..$EF: begin need := 2; cp := b and $0F; end;
      $F0:      begin need := 3; cp := b and $07; lo := $90; end;
      $F1..$F3: begin need := 3; cp := b and $07; end;
      $F4:      begin need := 3; cp := b and $07; hi := $8F; end;
    else
      need := -1;
    end;
    if (need > 0) and (i + need > n) then need := -1;
    if need > 0 then
      for j := 1 to need do
      begin
        b := Ord(S[i + j]);
        if ((j = 1) and ((b < lo) or (b > hi))) or ((j > 1) and ((b < $80) or (b > $BF))) then
        begin
          need := -1;
          Break;
        end;
        cp := (cp shl 6) or (b and $3F);
      end;
    if need < 0 then
    begin
      Inc(k);
      Result[k] := WideChar($FFFD);
      Inc(i);
      Continue;
    end;
    if cp >= $10000 then
    begin
      Dec(cp, $10000);
      Inc(k); Result[k] := WideChar($D800 + (cp shr 10));
      Inc(k); Result[k] := WideChar($DC00 + (cp and $3FF));
    end
    else
    begin
      Inc(k);
      Result[k] := WideChar(cp);
    end;
    Inc(i, need + 1);
  end;
  SetLength(Result, k);
end;

{ UnicodeService.getStringCellWidth (:67-101), line for line over UTF-16 units. }
function TyUnicodeStringCellWidth(const AUtf8: string; AVersion: TTyUnicodeVersion;
  AAmbiguousWide: Boolean): Integer;
var
  u: UnicodeString;
  i, n, chWidth: Integer;
  code, second: Cardinal;
  preceding, current: TTyUnicodeCharProps;
begin
  u := Wtf8ToUnits(AUtf8);
  n := Length(u);
  Result := 0;
  preceding := 0;
  i := 1;
  while i <= n do
  begin
    code := Ord(u[i]);
    if (code >= $D800) and (code <= $DBFF) then
    begin
      Inc(i);
      if i > n then
        Exit(Result + TyUnicodeWcWidth(code, AVersion, AAmbiguousWide));
      second := Ord(u[i]);
      if (second >= $DC00) and (second <= $DFFF) then
        code := (code - $D800) * $400 + second - $DC00 + $10000
      else
        Inc(Result, TyUnicodeWcWidth(second, AVersion, AAmbiguousWide));
    end;
    current := TyUnicodeCharProperties(code, preceding, AVersion, AAmbiguousWide);
    chWidth := TyUnicodePropsWidth(current);
    if TyUnicodePropsShouldJoin(current) then
      Dec(chWidth, TyUnicodePropsWidth(preceding));
    Inc(Result, chWidth);
    preceding := current;
    Inc(i);
  end;
end;

function TyUnicodeVersionName(AVersion: TTyUnicodeVersion): string;
begin
  case AVersion of
    tuv6: Result := '6';
    tuv11: Result := '11';
    tuv15: Result := '15';
  else
    Result := '15-graphemes';
  end;
end;

procedure ExpandBmp(const AStarts: array of Cardinal; const AWidths: array of Byte;
  var ATable: array of Byte);
var
  r: Integer;
  c, stop: Cardinal;
begin
  for r := 0 to High(AStarts) do
  begin
    if AStarts[r] > $FFFF then Break;
    if r < High(AStarts) then stop := AStarts[r + 1] else stop := MaxCodepoint + 1;
    if stop > $10000 then stop := $10000;
    for c := AStarts[r] to stop - 1 do
      ATable[c] := AWidths[r];
  end;
end;

initialization
  ExpandBmp(TyUniV6Start, TyUniV6Width, GBmp6);
  ExpandBmp(TyUniV11Start, TyUniV11Width, GBmp11);
end.
