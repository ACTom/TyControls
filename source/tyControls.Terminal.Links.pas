unit tyControls.Terminal.Links;
{$mode objfpc}{$H+}

{ The terminal's links: runs of cells an OSC 8 hyperlink covers, and web addresses
  found in the text. Which link is under a cell, when the two overlap which one wins,
  and whether a URI counts as http(s). No LCL: the control asks, and decides what a
  modifier key and a click do with the answer.

  PORTED FROM xterm.js 6.0.0, commit c58ea3637f39:
    addons/addon-web-links/src/WebLinkProvider.ts   TyTermComputeUrlLinks, TyTermIsUrl
    addons/addon-web-links/src/WebLinksAddon.ts:21  strictUrlRegex (TyTermNextUrlMatch)
    Copyright (c) 2017, The xterm.js authors (https://github.com/xtermjs/xterm.js)
    src/browser/OscLinkProvider.ts                  TyTermComputeOsc8Links
    src/browser/Linkifier.ts:153-173, :370-375      TyTermRemoveIntersectingLinks,
                                                    TyTermLinkAtPosition
    Copyright (c) 2017-2019, The xterm.js authors (https://github.com/xtermjs/xterm.js)
    Copyright (c) 2014-2016, SourceLair Private Company (https://www.sourcelair.com)
    Copyright (c) 2012-2013, Christopher Jeffrey (https://github.com/chjj/)
  MIT; the full text is in THIRD-PARTY-NOTICES.md.

  WHAT DIFFERS IN SHAPE (never in result):

  - The regular expression is a hand-written scanner over UTF-16: JavaScript's \s is
    Unicode whitespace (U+3000 ends an address) and the regex, without the u flag,
    walks UTF-16 units. FPC's RegExpr does neither. The scanner does what the regex's
    backtracking does (TyTermNextUrlMatch).
  - isUrl calls `new URL` and compares the text with what the URL says its scheme,
    user and host are. TyTermParseUrlPrefix is the part of the WHATWG URL parser that
    answer depends on, for http and https: C0 / space trimming, tabs and newlines
    removed, the scheme, the authority, the user info's percent-encoding, IPv6 and
    IPv4 hosts in their canonical form, percent-decoded domains checked for forbidden
    code points and lower-cased, the port (default ports dropped). Any other scheme is
    answered as parsed and not http -- all a caller asks of it.
  - The Linkifier checks the first hover of a line before it removes overlapping
    links and later hovers after; TyTermFindLinkAt always looks after (the control
    has no line cache whose state would decide it).

  WHAT DIFFERS ON PURPOSE (design spec 15):

  - No IDNA. A host with non-ASCII in it (after percent-decoding) is not a web
    address -- upstream's answer as well, since the host becomes xn--... and the text
    no longer starts with it -- and for OSC 8 it counts as http(s) without the UTS 46
    checks upstream makes (a few code points fail them there). xn-- labels are not
    checked to be valid punycode. }

interface

uses
  SysUtils, Classes, Types, tyControls.Unicode.Width, tyControls.Terminal.Buffer,
  tyControls.Terminal.Selection;

type
  TTyTermLinkSource = (tlsOsc8, tlsUrl);
  TTyTermLink = record
    Range: TTyTermLinkRange;    { 1-based, inclusive, buffer rows: upstream's IBufferRange }
    Text: string;               { UTF-8: the URI of an OSC 8 link, the matched text of an address }
    Source: TTyTermLinkSource;
    LinkId: Int64;              { the OSC 8 link number; 0 for an address }
  end;
  TTyTermLinks = array of TTyTermLink;

{ The WHATWG URL parse of AText, far enough for isUrl (unit header). True when it
  parses; then AIsHttp says the scheme is http or https and, for those, ABase is what
  isUrl builds from the URL (WebLinkProvider.ts:47-51). ANonAsciiHost: the host had
  non-ASCII in it -- answered as parsed, IDNA not done (unit header). }
function TyTermParseUrlPrefix(const AText: UnicodeString; out ABase: UnicodeString;
  out AIsHttp, ANonAsciiHost: Boolean): Boolean; overload;
function TyTermParseUrlPrefix(const AText: UnicodeString; out ABase: UnicodeString;
  out AIsHttp: Boolean): Boolean; overload;
{ WebLinkProvider.ts:44-55, for http and https: the only schemes the regex hands it.
  Any other scheme answers False. }
function TyTermIsUrl(const AText: UnicodeString): Boolean;
{ One exec of strictUrlRegex from AFrom (0-based UTF-16 index): the next match's start
  and length; False = none. }
function TyTermNextUrlMatch(const S: UnicodeString; AFrom: Integer; out AStart, ALength: Integer): Boolean;
{ LinkComputer.computeLink (WebLinkProvider.ts:59-101); AY is a 1-based buffer row. }
function TyTermComputeUrlLinks(ABuffer: TTyTerminalBuffer; AY: Integer): TTyTermLinks;
{ OscLinkProvider.provideLinks (:22-104); AAllowNonHttp = linkHandler.allowNonHttpProtocols }
function TyTermComputeOsc8Links(ABuffer: TTyTerminalBuffer; ALinks: TTyTerminalOscLinks; AY: Integer;
  AAllowNonHttp: Boolean): TTyTermLinks;
{ Linkifier._removeIntersectingLinks (:153-173): in provider order (OSC 8 first), a link
  that touches a cell an earlier one took is dropped, in place. }
procedure TyTermRemoveIntersectingLinks(AY, ACols: Integer; var AReplies: array of TTyTermLinks);
{ Linkifier._linkAtPosition (:370-375): AX / AY 1-based }
function TyTermLinkAtPosition(const ALink: TTyTermLink; AX, AY, ACols: Integer): Boolean;
{ For the control: the link at buffer row AAbsRow (0-based), column ACol (0-based) --
  both providers, overlaps removed, the first hit in provider order. }
function TyTermFindLinkAt(ABuffer: TTyTerminalBuffer; ALinks: TTyTerminalOscLinks; ACol, AAbsRow,
  ACols: Integer; ADetectUrls, AAllowNonHttp: Boolean; out ALink: TTyTermLink): Boolean;
{ linkEquals (Linkifier.ts:395-402): text and range }
function TyTermLinkEquals(const A, B: TTyTermLink): Boolean;

implementation

{ ---- small helpers -------------------------------------------------------------- }

function Utf16Len(const S: string): Integer;
var
  i: Integer;
  b: Byte;
begin
  Result := 0;
  for i := 1 to Length(S) do
  begin
    b := Ord(S[i]);
    if (b and $C0) <> $80 then
    begin
      Inc(Result);
      if b >= $F0 then Inc(Result);
    end;
  end;
end;

function AsciiLower(const S: UnicodeString): UnicodeString;
var
  i: Integer;
begin
  Result := S;
  UniqueString(Result);
  for i := 1 to Length(Result) do
    if (Result[i] >= 'A') and (Result[i] <= 'Z') then
      Result[i] := WideChar(Ord(Result[i]) + 32);
end;

function IsAsciiAlpha(c: WideChar): Boolean; inline;
begin
  Result := ((c >= 'a') and (c <= 'z')) or ((c >= 'A') and (c <= 'Z'));
end;

function IsAsciiDigit(c: WideChar): Boolean; inline;
begin
  Result := (c >= '0') and (c <= '9');
end;

function HexVal(c: WideChar): Integer;
begin
  case c of
    '0'..'9': Result := Ord(c) - Ord('0');
    'a'..'f': Result := Ord(c) - Ord('a') + 10;
    'A'..'F': Result := Ord(c) - Ord('A') + 10;
  else
    Result := -1;
  end;
end;

const
  HexUpper: array[0..15] of WideChar = ('0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
    'A', 'B', 'C', 'D', 'E', 'F');
  HexLower: array[0..15] of WideChar = ('0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
    'a', 'b', 'c', 'd', 'e', 'f');

{ the code point at 1-based index I of S, stepping I past it; a lone surrogate is U+FFFD }
function NextCp(const S: UnicodeString; var I: Integer): Cardinal;
var
  hi, lo: Cardinal;
begin
  hi := Ord(S[I]);
  Inc(I);
  if (hi >= $D800) and (hi <= $DBFF) and (I <= Length(S)) then
  begin
    lo := Ord(S[I]);
    if (lo >= $DC00) and (lo <= $DFFF) then
    begin
      Inc(I);
      Exit($10000 + ((hi - $D800) shl 10) + (lo - $DC00));
    end;
  end;
  if (hi >= $D800) and (hi <= $DFFF) then
    Exit($FFFD);
  Result := hi;
end;

// the userinfo percent-encode set (URL standard): C0, space, " # < > ? ` { } / : ; = @
// [ \ ] ^ | and everything past ~
function InUserinfoSet(c: Cardinal): Boolean;
begin
  case c of
    0..$20, Ord('"'), Ord('#'), Ord('<'), Ord('>'), Ord('?'), Ord('`'), Ord('{'), Ord('}'),
    Ord('/'), Ord(':'), Ord(';'), Ord('='), Ord('@'), Ord('['), Ord('\'), Ord(']'), Ord('^'),
    Ord('|'): Result := True;
  else
    Result := c > $7E;
  end;
end;

procedure PercentEncodeCp(var R: UnicodeString; c: Cardinal);
var
  bytes: array[0..3] of Byte;
  n, k: Integer;
begin
  if c < $80 then
  begin
    bytes[0] := c;
    n := 1;
  end
  else if c < $800 then
  begin
    bytes[0] := $C0 or (c shr 6);
    bytes[1] := $80 or (c and $3F);
    n := 2;
  end
  else if c < $10000 then
  begin
    bytes[0] := $E0 or (c shr 12);
    bytes[1] := $80 or ((c shr 6) and $3F);
    bytes[2] := $80 or (c and $3F);
    n := 3;
  end
  else
  begin
    bytes[0] := $F0 or (c shr 18);
    bytes[1] := $80 or ((c shr 12) and $3F);
    bytes[2] := $80 or ((c shr 6) and $3F);
    bytes[3] := $80 or (c and $3F);
    n := 4;
  end;
  for k := 0 to n - 1 do
    R := R + '%' + HexUpper[bytes[k] shr 4] + HexUpper[bytes[k] and 15];
end;

function CpToUnicode(c: Cardinal): UnicodeString;
begin
  if c < $10000 then
    Result := WideChar(c)
  else
    Result := WideChar($D800 + ((c - $10000) shr 10)) + WideChar($DC00 + ((c - $10000) and $3FF));
end;

{ ---- the host ---------------------------------------------------------------------- }

{ the IPv4 number parser: False = failure; a value past 2^32 is kept as 2^32 + 1 }
function ParseIpv4Number(const S: UnicodeString; out AValue: Int64): Boolean;
var
  r, i, d: Integer;
  t: UnicodeString;
begin
  AValue := 0;
  if S = '' then
    Exit(False);
  t := S;
  r := 10;
  if (Length(t) >= 2) and (t[1] = '0') and ((t[2] = 'x') or (t[2] = 'X')) then
  begin
    t := Copy(t, 3, MaxInt);
    r := 16;
  end
  else if (Length(t) >= 2) and (t[1] = '0') then
  begin
    t := Copy(t, 2, MaxInt);
    r := 8;
  end;
  if t = '' then
    Exit(True);
  for i := 1 to Length(t) do
  begin
    d := HexVal(t[i]);
    if (d < 0) or (d >= r) then
      Exit(False);
    if AValue <= $100000000 then
      AValue := AValue * r + d;
    if AValue > $100000000 then
      AValue := $100000001;
  end;
  Result := True;
end;

function SplitDots(const S: UnicodeString): TStringArray;
var
  parts: array of UnicodeString;
  i, start, n: Integer;
begin
  parts := nil;
  n := 0;
  start := 1;
  for i := 1 to Length(S) + 1 do
    if (i > Length(S)) or (S[i] = '.') then
    begin
      SetLength(parts, n + 1);
      parts[n] := Copy(S, start, i - start);
      Inc(n);
      start := i + 1;
    end;
  SetLength(Result, n);
  for i := 0 to n - 1 do
    Result[i] := UTF8Encode(parts[i]);
end;

{ the ends-in-a-number checker }
function EndsInANumber(const S: UnicodeString): Boolean;
var
  parts: TStringArray;
  last: UnicodeString;
  n, i: Integer;
  v: Int64;
  allDigits: Boolean;
begin
  parts := SplitDots(S);
  n := Length(parts);
  if parts[n - 1] = '' then
  begin
    if n = 1 then
      Exit(False);
    Dec(n);
  end;
  last := UTF8Decode(parts[n - 1]);
  allDigits := last <> '';
  for i := 1 to Length(last) do
    if not IsAsciiDigit(last[i]) then
      allDigits := False;
  if allDigits then
    Exit(True);
  Result := ParseIpv4Number(last, v);
end;

{ the IPv4 parser; the dotted-decimal serialization }
function ParseIpv4(const S: UnicodeString; out AHost: UnicodeString): Boolean;
var
  parts: TStringArray;
  n, i: Integer;
  nums: array[0..3] of Int64;
  ip: Int64;
  limit: Int64;
begin
  AHost := '';
  parts := SplitDots(S);
  n := Length(parts);
  if (parts[n - 1] = '') and (n > 1) then
    Dec(n);
  if n > 4 then
    Exit(False);
  for i := 0 to n - 1 do
    if not ParseIpv4Number(UTF8Decode(parts[i]), nums[i]) then
      Exit(False);
  for i := 0 to n - 2 do
    if nums[i] > 255 then
      Exit(False);
  limit := Int64(1) shl (8 * (5 - n));
  if nums[n - 1] >= limit then
    Exit(False);
  ip := nums[n - 1];
  for i := 0 to n - 2 do
    ip := ip + nums[i] * (Int64(1) shl (8 * (3 - i)));
  AHost := UnicodeString(IntToStr((ip shr 24) and $FF) + '.' + IntToStr((ip shr 16) and $FF) + '.'
    + IntToStr((ip shr 8) and $FF) + '.' + IntToStr(ip and $FF));
  Result := True;
end;

{ the IPv6 parser (the text between the brackets) and serializer }
function ParseIpv6(const S: UnicodeString; out AHost: UnicodeString): Boolean;
var
  address: array[0..7] of Integer;
  pieceIndex, compress, p, len, value, numbersSeen, ipv4Piece, swaps, t, i, bestAt, bestLen, runAt, runLen: Integer;
  ignore0: Boolean;

  function C(AAt: Integer): WideChar;          { 0-based; #0 = EOF }
  begin
    if (AAt >= 0) and (AAt < Length(S)) then Result := S[AAt + 1] else Result := #0;
  end;

  function Hex(AValue: Integer): UnicodeString;
  begin
    Result := '';
    repeat
      Result := HexLower[AValue and 15] + Result;
      AValue := AValue shr 4;
    until AValue = 0;
  end;

begin
  AHost := '';
  FillChar(address, SizeOf(address), 0);
  pieceIndex := 0;
  compress := -1;
  p := 0;
  if C(p) = ':' then
  begin
    if C(p + 1) <> ':' then
      Exit(False);
    Inc(p, 2);
    Inc(pieceIndex);
    compress := pieceIndex;
  end;
  while C(p) <> #0 do
  begin
    if pieceIndex = 8 then
      Exit(False);
    if C(p) = ':' then
    begin
      if compress <> -1 then
        Exit(False);
      Inc(p);
      Inc(pieceIndex);
      compress := pieceIndex;
      Continue;
    end;
    value := 0;
    len := 0;
    while (len < 4) and (HexVal(C(p)) >= 0) and (C(p) <> #0) do
    begin
      value := value * 16 + HexVal(C(p));
      Inc(p);
      Inc(len);
    end;
    if C(p) = '.' then
    begin
      if len = 0 then
        Exit(False);
      Dec(p, len);
      if pieceIndex > 6 then
        Exit(False);
      numbersSeen := 0;
      while C(p) <> #0 do
      begin
        ipv4Piece := -1;
        if numbersSeen > 0 then
        begin
          if (C(p) = '.') and (numbersSeen < 4) then
            Inc(p)
          else
            Exit(False);
        end;
        if not IsAsciiDigit(C(p)) then
          Exit(False);
        while IsAsciiDigit(C(p)) do
        begin
          t := Ord(C(p)) - Ord('0');
          if ipv4Piece = -1 then
            ipv4Piece := t
          else if ipv4Piece = 0 then
            Exit(False)
          else
            ipv4Piece := ipv4Piece * 10 + t;
          if ipv4Piece > 255 then
            Exit(False);
          Inc(p);
        end;
        address[pieceIndex] := address[pieceIndex] * $100 + ipv4Piece;
        Inc(numbersSeen);
        if (numbersSeen = 2) or (numbersSeen = 4) then
          Inc(pieceIndex);
      end;
      if numbersSeen <> 4 then
        Exit(False);
      Break;
    end
    else if C(p) = ':' then
    begin
      Inc(p);
      if C(p) = #0 then
        Exit(False);
    end
    else if C(p) <> #0 then
      Exit(False);
    address[pieceIndex] := value;
    Inc(pieceIndex);
  end;
  if compress <> -1 then
  begin
    swaps := pieceIndex - compress;
    pieceIndex := 7;
    while (pieceIndex <> 0) and (swaps > 0) do
    begin
      t := address[pieceIndex];
      address[pieceIndex] := address[compress + swaps - 1];
      address[compress + swaps - 1] := t;
      Dec(pieceIndex);
      Dec(swaps);
    end;
  end
  else if pieceIndex <> 8 then
    Exit(False);
  { the serializer: the first longest run of two or more zeros is compressed }
  bestAt := -1;
  bestLen := 1;
  runAt := -1;
  runLen := 0;
  for i := 0 to 8 do
  begin
    if (i < 8) and (address[i] = 0) then
    begin
      if runAt = -1 then runAt := i;
      Inc(runLen);
    end
    else
    begin
      if runLen > bestLen then
      begin
        bestAt := runAt;
        bestLen := runLen;
      end;
      runAt := -1;
      runLen := 0;
    end;
  end;
  AHost := '';
  ignore0 := False;
  for i := 0 to 7 do
  begin
    if ignore0 and (address[i] = 0) then
      Continue
    else if ignore0 then
      ignore0 := False;
    if bestAt = i then
    begin
      if i = 0 then AHost := AHost + '::' else AHost := AHost + ':';
      ignore0 := True;
      Continue;
    end;
    AHost := AHost + Hex(address[i]);
    if i <> 7 then
      AHost := AHost + ':';
  end;
  AHost := '[' + AHost + ']';
  Result := True;
end;

{ the host parser for a special scheme: False = failure. ANonAscii: the domain has
  non-ASCII after percent-decoding (unit header: no IDNA). }
function ParseHost(const S: UnicodeString; out AHost: UnicodeString; out ANonAscii: Boolean): Boolean;
var
  bytes: RawByteString;
  i, h1, h2: Integer;
  domain: UnicodeString;
  c: WideChar;
begin
  AHost := '';
  ANonAscii := False;
  if (S <> '') and (S[1] = '[') then
  begin
    if S[Length(S)] <> ']' then
      Exit(False);
    Exit(ParseIpv6(Copy(S, 2, Length(S) - 2), AHost));
  end;
  { percent-decode the UTF-8 bytes, then decode them again }
  bytes := UTF8Encode(S);
  domain := '';
  i := 1;
  SetLength(bytes, Length(bytes));
  while i <= Length(bytes) do
  begin
    if (bytes[i] = '%') and (i + 2 <= Length(bytes)) then
    begin
      h1 := HexVal(WideChar(bytes[i + 1]));
      h2 := HexVal(WideChar(bytes[i + 2]));
      if (h1 >= 0) and (h2 >= 0) then
      begin
        bytes[i] := Chr(h1 * 16 + h2);
        Delete(bytes, i + 1, 2);
      end;
    end;
    Inc(i);
  end;
  for i := 1 to Length(bytes) do
    if Ord(bytes[i]) >= $80 then
      ANonAscii := True;
  domain := UTF8Decode(bytes);
  { forbidden domain code points: C0, space, # % / : < > ? @ [ \ ] ^ |, DEL }
  for i := 1 to Length(domain) do
  begin
    c := domain[i];
    if (Ord(c) <= $20) or (Ord(c) = $7F) then
      Exit(False);
    case c of
      '#', '%', '/', ':', '<', '>', '?', '@', '[', '\', ']', '^', '|': Exit(False);
    end;
  end;
  if ANonAscii then
  begin
    { no IDNA (unit header): kept as it is, a success for OSC 8 }
    AHost := domain;
    Exit(True);
  end;
  domain := AsciiLower(domain);
  if EndsInANumber(domain) then
    Exit(ParseIpv4(domain, AHost));
  AHost := domain;
  Result := True;
end;

{ ---- the URL prefix ------------------------------------------------------------- }

function TyTermParseUrlPrefix(const AText: UnicodeString; out ABase: UnicodeString;
  out AIsHttp, ANonAsciiHost: Boolean): Boolean;
var
  s, scheme, authority, userinfo, hostPort, host, hostOut, portText, user, pass, port: UnicodeString;
  a, b, i, j, lastAt, colon, portValue: Integer;
  insideBrackets, passwordSeen: Boolean;
  cp: Cardinal;
begin
  ABase := '';
  AIsHttp := False;
  ANonAsciiHost := False;
  { trim leading and trailing C0 controls and spaces; drop tabs and newlines }
  a := 1;
  b := Length(AText);
  while (a <= b) and (Ord(AText[a]) <= $20) do Inc(a);
  while (b >= a) and (Ord(AText[b]) <= $20) do Dec(b);
  s := '';
  for i := a to b do
    if not ((AText[i] = #9) or (AText[i] = #10) or (AText[i] = #13)) then
      s := s + AText[i];
  { scheme start, scheme }
  if (s = '') or not IsAsciiAlpha(s[1]) then
    Exit(False);
  i := 2;
  while (i <= Length(s)) and (IsAsciiAlpha(s[i]) or IsAsciiDigit(s[i]) or (s[i] = '+')
    or (s[i] = '-') or (s[i] = '.')) do
    Inc(i);
  if (i > Length(s)) or (s[i] <> ':') then
    Exit(False);
  scheme := AsciiLower(Copy(s, 1, i - 1));
  if (scheme <> 'http') and (scheme <> 'https') then
    Exit(True);                            { parsed as far as anyone asks (unit header) }
  AIsHttp := True;
  { special authority slashes / ignore slashes }
  j := i + 1;
  while (j <= Length(s)) and ((s[j] = '/') or (s[j] = '\')) do
    Inc(j);
  { authority: up to / \ ? # }
  i := j;
  while (i <= Length(s)) and not ((s[i] = '/') or (s[i] = '\') or (s[i] = '?') or (s[i] = '#')) do
    Inc(i);
  authority := Copy(s, j, i - j);
  { user info: before the last @; an earlier @ is encoded, the first : splits }
  lastAt := 0;
  for i := 1 to Length(authority) do
    if authority[i] = '@' then
      lastAt := i;
  user := '';
  pass := '';
  if lastAt > 0 then
  begin
    userinfo := Copy(authority, 1, lastAt - 1);
    hostPort := Copy(authority, lastAt + 1, MaxInt);
    if hostPort = '' then
      Exit(False);                         { host-missing }
    passwordSeen := False;
    i := 1;
    while i <= Length(userinfo) do
    begin
      if (userinfo[i] = ':') and not passwordSeen then
      begin
        passwordSeen := True;
        Inc(i);
        Continue;
      end;
      cp := NextCp(userinfo, i);
      if InUserinfoSet(cp) then
      begin
        if passwordSeen then PercentEncodeCp(pass, cp) else PercentEncodeCp(user, cp);
      end
      else if passwordSeen then
        pass := pass + CpToUnicode(cp)
      else
        user := user + CpToUnicode(cp);
    end;
  end
  else
    hostPort := authority;
  { host and port: a : outside brackets }
  colon := 0;
  insideBrackets := False;
  for i := 1 to Length(hostPort) do
  begin
    if hostPort[i] = '[' then insideBrackets := True;
    if hostPort[i] = ']' then insideBrackets := False;
    if (hostPort[i] = ':') and not insideBrackets then
    begin
      colon := i;
      Break;
    end;
  end;
  if colon > 0 then
  begin
    host := Copy(hostPort, 1, colon - 1);
    portText := Copy(hostPort, colon + 1, MaxInt);
  end
  else
  begin
    host := hostPort;
    portText := '';
  end;
  if host = '' then
    Exit(False);
  if not ParseHost(host, hostOut, ANonAsciiHost) then
    Exit(False);
  host := hostOut;
  port := '';
  if portText <> '' then
  begin
    portValue := 0;
    for i := 1 to Length(portText) do
    begin
      if not IsAsciiDigit(portText[i]) then
        Exit(False);
      if portValue <= 65535 then
        portValue := portValue * 10 + Ord(portText[i]) - Ord('0');
    end;
    if portValue > 65535 then
      Exit(False);
    if not (((scheme = 'http') and (portValue = 80)) or ((scheme = 'https') and (portValue = 443))) then
      port := UnicodeString(IntToStr(portValue));
  end;
  { isUrl's parsedBase }
  ABase := scheme + '://';
  if (pass <> '') and (user <> '') then
    ABase := ABase + user + ':' + pass + '@'
  else if user <> '' then
    ABase := ABase + user + '@';
  ABase := ABase + host;
  if port <> '' then
    ABase := ABase + ':' + port;
  Result := True;
end;

function TyTermParseUrlPrefix(const AText: UnicodeString; out ABase: UnicodeString;
  out AIsHttp: Boolean): Boolean;
var
  nonAscii: Boolean;
begin
  Result := TyTermParseUrlPrefix(AText, ABase, AIsHttp, nonAscii);
end;

function TyTermIsUrl(const AText: UnicodeString): Boolean;
var
  base, lower: UnicodeString;
  isHttp, nonAscii: Boolean;
begin
  if not TyTermParseUrlPrefix(AText, base, isHttp, nonAscii) then
    Exit(False);
  if nonAscii or not isHttp then
    Exit(False);
  { toLocaleLowerCase on both: the prefix is ASCII (non-ASCII hosts are out above; a
    non-ASCII user is percent-encoded in the base and so never matches) }
  lower := AsciiLower(AText);
  base := AsciiLower(base);
  Result := Copy(lower, 1, Length(base)) = base;
end;

{ ---- the regex ------------------------------------------------------------------- }

// strictUrlRegex, WebLinksAddon.ts:21:
//   /(https?|HTTPS?):[/]{2}[^\s"'!*(){}|\\\^<>`]*[^\s"':,.!?{}|\\\^~\[\]`()<>]/
// UrlBodyExcluded is the first class's set, UrlEndExcluded the last one's; \s is
// TyTermIsJsWhitespace in both.
const
  UrlBodyExcluded: UnicodeString = '"''!*(){}|\^<>`';
  UrlEndExcluded: UnicodeString = '"'':,.!?{}|\^~[]`()<>';

function InBody(c: WideChar): Boolean; inline;
begin
  Result := not TyTermIsJsWhitespace(Ord(c)) and (Pos(c, UrlBodyExcluded) = 0);
end;

function InEnd(c: WideChar): Boolean; inline;
begin
  Result := not TyTermIsJsWhitespace(Ord(c)) and (Pos(c, UrlEndExcluded) = 0);
end;

function StartsAt(const S: UnicodeString; AAt: Integer; const APrefix: UnicodeString): Boolean;
var
  k: Integer;
begin
  if AAt + Length(APrefix) - 1 > Length(S) then
    Exit(False);
  for k := 1 to Length(APrefix) do
    if S[AAt + k - 1] <> APrefix[k] then
      Exit(False);
  Result := True;
end;

function TyTermNextUrlMatch(const S: UnicodeString; AFrom: Integer; out AStart, ALength: Integer): Boolean;
var
  i, p, e, j, n: Integer;
begin
  AStart := 0;
  ALength := 0;
  n := Length(S);
  if AFrom < 0 then AFrom := 0;
  for i := AFrom + 1 to n do                 { 1-based here }
  begin
    { (https?|HTTPS?):// -- only these four spellings }
    if StartsAt(S, i, 'https://') or StartsAt(S, i, 'HTTPS://') then
      p := i + 8
    else if StartsAt(S, i, 'http://') or StartsAt(S, i, 'HTTP://') then
      p := i + 7
    else
      Continue;
    { the body, as far as it goes }
    e := p;
    while (e <= n) and InBody(S[e]) do
      Inc(e);
    { the last character: the one right after the body (only * can be), or the last
      one inside it that may end an address }
    j := -1;
    if (e <= n) and InEnd(S[e]) then
      j := e
    else
    begin
      j := e - 1;
      while (j >= p) and not InEnd(S[j]) do
        Dec(j);
      if j < p then
        j := -1;
    end;
    if j = -1 then
      Continue;
    AStart := i - 1;
    ALength := j - i + 1;
    Exit(True);
  end;
  Result := False;
end;

{ ---- web addresses -------------------------------------------------------------- }

function LineText(ALine: TTyTerminalLine): UnicodeString;
begin
  Result := UTF8Decode(ALine.TranslateToString(True));
end;

{ LinkComputer._mapStrIdx (:160-199): [lineIndex, column], or -1 / -1 }
procedure MapStrIdx(ABuffer: TTyTerminalBuffer; ALineIndex, ARowIndex, AStringIndex: Integer;
  out AY, AX: Integer);
var
  line, nextLine: TTyTerminalLine;
  start, i: Integer;
  chars: string;
  len: Integer;
begin
  start := ARowIndex;
  while AStringIndex <> 0 do
  begin
    line := ABuffer.Lines.Get(ALineIndex);
    if line = nil then
    begin
      AY := -1;
      AX := -1;
      Exit;
    end;
    for i := start to line.Length - 1 do
    begin
      chars := line.GetChars(i);
      if line.GetWidth(i) <> 0 then
      begin
        len := Utf16Len(chars);
        if len = 0 then len := 1;
        Dec(AStringIndex, len);
        { a wide character wrapped early leaves an empty last cell (InputHandler.print)
          that the trimmed string does not have }
        if (i = line.Length - 1) and (chars = '') then
        begin
          nextLine := ABuffer.Lines.Get(ALineIndex + 1);
          if (nextLine <> nil) and nextLine.IsWrapped and (nextLine.GetWidth(0) = 2) then
            Inc(AStringIndex);
        end;
      end;
      if AStringIndex < 0 then
      begin
        AY := ALineIndex;
        AX := i;
        Exit;
      end;
    end;
    Inc(ALineIndex);
    start := 0;
  end;
  AY := ALineIndex;
  AX := start;
end;

function TyTermComputeUrlLinks(ABuffer: TTyTerminalBuffer; AY: Integer): TTyTermLinks;
var
  lines: array of UnicodeString;
  n, topIdx, bottomIdx, total, k: Integer;
  line: TTyTerminalLine;
  current, content, joined, text: UnicodeString;
  from, mStart, mLen, sy, sx, ey, ex: Integer;
begin
  Result := nil;
  lines := nil;
  n := 0;
  topIdx := AY - 1;
  bottomIdx := AY - 1;
  { _getWindowedLineStrings (:113-153), in UTF-16 }
  line := ABuffer.Lines.Get(AY - 1);
  if line <> nil then
  begin
    current := LineText(line);
    { up, stopping at whitespace or past 2048 units }
    if line.IsWrapped and not ((current <> '') and (current[1] = ' ')) then
    begin
      total := 0;
      while True do
      begin
        Dec(topIdx);
        line := ABuffer.Lines.Get(topIdx);
        if (line = nil) or not (total < 2048) then
          Break;
        content := LineText(line);
        Inc(total, Length(content));
        SetLength(lines, n + 1);
        lines[n] := content;
        Inc(n);
        if not line.IsWrapped or (Pos(' ', content) > 0) then
          Break;
      end;
      { reverse }
      for k := 0 to n div 2 - 1 do
      begin
        content := lines[k];
        lines[k] := lines[n - 1 - k];
        lines[n - 1 - k] := content;
      end;
    end;
    SetLength(lines, n + 1);
    lines[n] := current;
    Inc(n);
    { down }
    total := 0;
    while True do
    begin
      Inc(bottomIdx);
      line := ABuffer.Lines.Get(bottomIdx);
      if (line = nil) or not line.IsWrapped or not (total < 2048) then
        Break;
      content := LineText(line);
      Inc(total, Length(content));
      SetLength(lines, n + 1);
      lines[n] := content;
      Inc(n);
      if Pos(' ', content) > 0 then
        Break;
    end;
  end;
  joined := '';
  for k := 0 to n - 1 do
    joined := joined + lines[k];
  from := 0;
  while TyTermNextUrlMatch(joined, from, mStart, mLen) do
  begin
    from := mStart + mLen;                   { the g flag's lastIndex }
    text := Copy(joined, mStart + 1, mLen);
    if not TyTermIsUrl(text) then
      Continue;
    MapStrIdx(ABuffer, topIdx, 0, mStart, sy, sx);
    MapStrIdx(ABuffer, sy, sx, mLen, ey, ex);
    if (sy = -1) or (sx = -1) or (ey = -1) or (ex = -1) then
      Continue;
    k := Length(Result);
    SetLength(Result, k + 1);
    Result[k].Range.StartX := sx + 1;
    Result[k].Range.StartY := sy + 1;
    Result[k].Range.EndX := ex;
    Result[k].Range.EndY := ey + 1;
    Result[k].Text := UTF8Encode(text);
    Result[k].Source := tlsUrl;
    Result[k].LinkId := 0;
  end;
end;

{ ---- OSC 8 --------------------------------------------------------------------------- }

function HasUrlId(ALine: TTyTerminalLine; AX: Integer; ALinkId: Int64): Boolean;
var
  ext: TTyTerminalExtAttrs;
begin
  Result := ALine.ExtendedEntry(AX, ext) and (ext.UrlId = ALinkId);
end;

function CellUrlId(ALine: TTyTerminalLine; AX: Integer): Int64;
var
  ext: TTyTerminalExtAttrs;
begin
  if ALine.ExtendedEntry(AX, ext) then
    Result := ext.UrlId
  else
    Result := 0;
end;

{ OscLinkProvider._getRangeWithLineWrap (:108-172) }
function RangeWithLineWrap(ABuffer: TTyTerminalBuffer; AY, AStartX, AEndX: Integer; ALinkId: Int64): TTyTermLinkRange;
var
  startY, endY, finalStartX, finalEndX, prevLen, prevStartX, curLen, nextLen, nextEndX: Integer;
  cur, prev, next: TTyTerminalLine;
begin
  startY := AY;
  finalStartX := AStartX;
  endY := AY;
  finalEndX := AEndX;
  { up: only from column 0 of a wrapped line }
  while finalStartX = 0 do
  begin
    cur := ABuffer.Lines.Get(startY - 1);
    if (cur = nil) or not cur.IsWrapped then
      Break;
    prev := ABuffer.Lines.Get(startY - 2);
    if prev = nil then
      Break;
    prevLen := prev.GetTrimmedLength;
    if (prevLen = 0) or not HasUrlId(prev, prevLen - 1, ALinkId) then
      Break;
    prevStartX := prevLen - 1;
    while (prevStartX > 0) and HasUrlId(prev, prevStartX - 1, ALinkId) do
      Dec(prevStartX);
    Dec(startY);
    finalStartX := prevStartX;
  end;
  { down: only from the trimmed end into a wrapped line }
  while True do
  begin
    cur := ABuffer.Lines.Get(endY - 1);
    if cur = nil then
      Break;
    curLen := cur.GetTrimmedLength;
    if finalEndX <> curLen then
      Break;
    next := ABuffer.Lines.Get(endY);
    if (next = nil) or not next.IsWrapped then
      Break;
    nextLen := next.GetTrimmedLength;
    if (nextLen = 0) or not HasUrlId(next, 0, ALinkId) then
      Break;
    nextEndX := 1;
    while (nextEndX < nextLen) and HasUrlId(next, nextEndX, ALinkId) do
      Inc(nextEndX);
    Inc(endY);
    finalEndX := nextEndX;
  end;
  Result.StartX := finalStartX + 1;
  Result.StartY := startY;
  Result.EndX := finalEndX;
  Result.EndY := endY;
end;

function TyTermComputeOsc8Links(ABuffer: TTyTerminalBuffer; ALinks: TTyTerminalOscLinks; AY: Integer;
  AAllowNonHttp: Boolean): TTyTermLinks;
var
  line: TTyTerminalLine;
  lineLength, x, endX, k: Integer;
  currentLinkId, id: Int64;
  currentStart: Integer;
  finishLink, ignore, isHttp: Boolean;
  data: TTyTerminalLinkData;
  base: UnicodeString;
  range: TTyTermLinkRange;
begin
  Result := nil;
  line := ABuffer.Lines.Get(AY - 1);
  if line = nil then
    Exit;
  lineLength := line.GetTrimmedLength;
  currentLinkId := -1;
  currentStart := -1;
  finishLink := False;
  for x := 0 to lineLength - 1 do
  begin
    { only a link can end on an empty cell }
    if (currentStart = -1) and not line.HasContent(x) then
      Continue;
    id := CellUrlId(line, x);
    if id <> 0 then
    begin
      if currentStart = -1 then
      begin
        currentStart := x;
        currentLinkId := id;
        Continue;
      end
      else
        finishLink := id <> currentLinkId;
    end
    else if currentStart <> -1 then
      finishLink := True;

    if finishLink or ((currentStart <> -1) and (x = lineLength - 1)) then
    begin
      if ALinks.GetLinkData(currentLinkId, data) and (data.Uri <> '') then
      begin
        if not finishLink and (x = lineLength - 1) then
          endX := x + 1
        else
          endX := x;
        range := RangeWithLineWrap(ABuffer, AY, currentStart, endX, currentLinkId);
        ignore := False;
        if not AAllowNonHttp then
          { no link unless new URL parses it as http or https (:64-75) }
          ignore := not TyTermParseUrlPrefix(UTF8Decode(data.Uri), base, isHttp) or not isHttp;
        if not ignore then
        begin
          k := Length(Result);
          SetLength(Result, k + 1);
          Result[k].Range := range;
          Result[k].Text := data.Uri;
          Result[k].Source := tlsOsc8;
          Result[k].LinkId := currentLinkId;
        end;
      end;
      finishLink := False;
      { this cell may start the next link at once }
      if id <> 0 then
      begin
        currentStart := x;
        currentLinkId := id;
      end
      else
      begin
        currentStart := -1;
        currentLinkId := -1;
      end;
    end;
  end;
end;

{ ---- overlap, hits ---------------------------------------------------------------- }

procedure TyTermRemoveIntersectingLinks(AY, ACols: Integer; var AReplies: array of TTyTermLinks);
var
  occupied: array of Boolean;
  p, i, k, x, sx, ex, top: Integer;
  reply: TTyTermLinks;
begin
  top := ACols;
  for p := 0 to High(AReplies) do
    for i := 0 to High(AReplies[p]) do
      if AReplies[p][i].Range.EndX > top then
        top := AReplies[p][i].Range.EndX;
  occupied := nil;
  SetLength(occupied, top + 2);
  for p := 0 to High(AReplies) do
  begin
    reply := AReplies[p];
    i := 0;
    while i < Length(reply) do
    begin
      if reply[i].Range.StartY < AY then sx := 0 else sx := reply[i].Range.StartX;
      if reply[i].Range.EndY > AY then ex := ACols else ex := reply[i].Range.EndX;
      if sx < 0 then sx := 0;
      for x := sx to ex do
      begin
        if occupied[x] then
        begin
          { splice(i--, 1); break }
          for k := i to High(reply) - 1 do
            reply[k] := reply[k + 1];
          SetLength(reply, Length(reply) - 1);
          Dec(i);
          Break;
        end;
        occupied[x] := True;
      end;
      Inc(i);
    end;
    AReplies[p] := reply;
  end;
end;

function TyTermLinkAtPosition(const ALink: TTyTermLink; AX, AY, ACols: Integer): Boolean;
var
  lower, upper, current: Int64;
begin
  lower := Int64(ALink.Range.StartY) * ACols + ALink.Range.StartX;
  upper := Int64(ALink.Range.EndY) * ACols + ALink.Range.EndX;
  current := Int64(AY) * ACols + AX;
  Result := (lower <= current) and (current <= upper);
end;

function TyTermFindLinkAt(ABuffer: TTyTerminalBuffer; ALinks: TTyTerminalOscLinks; ACol, AAbsRow,
  ACols: Integer; ADetectUrls, AAllowNonHttp: Boolean; out ALink: TTyTermLink): Boolean;
var
  replies: array[0..1] of TTyTermLinks;
  y, p, i: Integer;
begin
  ALink := Default(TTyTermLink);
  y := AAbsRow + 1;
  replies[0] := TyTermComputeOsc8Links(ABuffer, ALinks, y, AAllowNonHttp);
  if ADetectUrls then
    replies[1] := TyTermComputeUrlLinks(ABuffer, y)
  else
    replies[1] := nil;
  TyTermRemoveIntersectingLinks(y, ACols, replies);
  for p := 0 to 1 do
    for i := 0 to High(replies[p]) do
      if TyTermLinkAtPosition(replies[p][i], ACol + 1, y, ACols) then
      begin
        ALink := replies[p][i];
        Exit(True);
      end;
  Result := False;
end;

function TyTermLinkEquals(const A, B: TTyTermLink): Boolean;
begin
  Result := (A.Text = B.Text) and (A.Range.StartX = B.Range.StartX) and (A.Range.StartY = B.Range.StartY)
    and (A.Range.EndX = B.Range.EndX) and (A.Range.EndY = B.Range.EndY);
end;

end.
