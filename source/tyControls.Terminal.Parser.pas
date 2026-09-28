unit tyControls.Terminal.Parser;
{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

{ The terminal's input side below the core: UTF-8 decoding, the VT500 escape
  sequence state machine with parameters and sub-parameters, and the OSC, DCS and
  APC sub-parsers. No LCL; nothing here knows about a screen.

  PORTED FROM xterm.js 6.0.0, commit c58ea3637f39:
    src/common/parser/EscapeSequenceParser.ts   state machine, transition table
    src/common/parser/Params.ts                 TTyTerminalParams
    src/common/parser/OscParser.ts              OSC sub-parser, OscHandler
    src/common/parser/DcsParser.ts              DCS sub-parser, DcsHandler
    src/common/parser/ApcParser.ts              APC sub-parser, ApcHandler
    src/common/parser/Constants.ts              states, actions, payload limit
    src/common/parser/Types.ts                  handler shapes
    src/common/input/TextDecoder.ts             Utf8ToUtf32, utf32ToString
    src/common/StringBuilder.ts                 LimitedStringBuilder

    Copyright (c) 2017-2019, The xterm.js authors (https://github.com/xtermjs/xterm.js)
    Copyright (c) 2014-2016, SourceLair Private Company (https://www.sourcelair.com)
    Copyright (c) 2012-2013, Christopher Jeffrey (https://github.com/chjj/)
  MIT; the full text is in THIRD-PARTY-NOTICES.md.

  THREE THINGS THAT DO NOT LOOK LIKE A STRAIGHT PORT:

  - The payload limit (10,000,000) counts UTF-16 code units, as upstream's string
    builder does -- a code point above U+FFFF counts 2 -- and trips on "greater
    than", not "greater or equal". Payloads are held as UTF-8 here, so the count is
    kept alongside.
  - An OSC number is summed in a saturating Int64. Upstream adds in floating point
    and never wraps; a 32-bit sum would wrap OSC 4294967300 onto OSC 4 and act on
    it. A number above High(Integer) matches no handler and goes to the fallback.
  - Handlers are synchronous. Upstream lets a handler return a promise and resumes
    the parse later (_parseStack, the promiseResult arguments); FPC 3.2.2 has no
    closures to carry that continuation, so it is not ported (design spec 2.2).

  Handler objects given to RegisterOscHandler / RegisterDcsHandler /
  RegisterApcHandler belong to the parser from then on: it frees them when they
  are unregistered, cleared, or when the parser is destroyed. }

interface

uses
  SysUtils, Classes, tyControls.Unicode.Width;

const
  TyTermParserPayloadLimit = 10000000;      { parser/Constants.ts:66 PAYLOAD_LIMIT, UTF-16 units }
  TyTermMaxParseBuffer = 131072;            { InputHandler.ts:45 MAX_PARSEBUFFER_LENGTH, input bytes }
  TyTermParamsMaxValue = $7FFFFFFF;         { Params.ts:11 }
  TyTermParamsMaxSubParams = 256;           { Params.ts:15 }
  TyTermTransitionCount = 4257;             { EscapeSequenceParser.ts:100 }

type
  { ParserState / ParserAction, parser/Constants.ts:9-53 -- the ordinals ARE upstream's
    numbers (the fixtures store them). }
  TTyTermParserState = (tpsGround, tpsEscape, tpsEscapeIntermediate, tpsCsiEntry, tpsCsiParam,
    tpsCsiIntermediate, tpsCsiIgnore, tpsSosPmString, tpsOscString, tpsDcsEntry, tpsDcsParam,
    tpsDcsIgnore, tpsDcsIntermediate, tpsDcsPassthrough, tpsApcEntry, tpsApcIntermediate,
    tpsApcPassthrough);
  TTyTermParserAction = (tpaIgnore, tpaError, tpaPrint, tpaExecute, tpaOscStart, tpaOscPut,
    tpaOscEnd, tpaCsiDispatch, tpaParam, tpaCollect, tpaEscDispatch, tpaClear, tpaDcsHook,
    tpaDcsPut, tpaDcsUnhook, tpaApcStart, tpaApcPut, tpaApcEnd);

  { Params.ts. Borrowed by handlers for the duration of the call: Clone to keep. }
  TTyTerminalParams = class
  private
    FParams: array of Integer;
    FLength: Integer;
    FSubParams: array of Integer;
    FSubParamsLength: Integer;
    FSubParamsIdx: array of Word;     { high byte start, low byte end, per param }
    FRejectDigits: Boolean;
    FRejectSubDigits: Boolean;
    FDigitIsSub: Boolean;
    FMaxLength: Integer;
    FMaxSubParamsLength: Integer;
    function GetParam(AIdx: Integer): Integer; inline;
  public
    { Raises EArgumentException when AMaxSubParamsLength > 256 (Params.ts:79-81). }
    constructor Create(AMaxLength: Integer = 32; AMaxSubParamsLength: Integer = 32);
    function Clone: TTyTerminalParams;
    procedure Reset;
    procedure ResetZdm;
    procedure AddParam(AValue: Integer);       { EArgumentException below -1 }
    procedure AddSubParam(AValue: Integer);    { EArgumentException below -1 }
    procedure AddDigit(AValue: Integer);
    function HasSubParams(AIdx: Integer): Boolean;
    function SubParamCount(AIdx: Integer): Integer;   { getSubParams(idx).length; 0 = null }
    function SubParam(AIdx, ASub: Integer): Integer;
    function ToJson: string;                   { JSON.stringify(toArray()) }
    { Not range checked, as upstream: never read beyond Length - 1. }
    property Params[AIdx: Integer]: Integer read GetParam; default;
    property Length: Integer read FLength;
    property MaxLength: Integer read FMaxLength;
    property MaxSubParamsLength: Integer read FMaxSubParamsLength;
  end;

  { Utf8ToUtf32, TextDecoder.ts:121-346: malformed bytes and the BOM are dropped (no
    U+FFFD), a sequence split across calls is carried over. }
  TTyUtf8Decoder = class
  private
    FInterim: array[0..2] of Byte;
  public
    procedure Clear;
    { AOut must hold at least ACount code points (upstream does not check either). }
    function Decode(const ABytes; ACount: Integer; var AOut: array of Cardinal): Integer;
  end;

  { LimitedStringBuilder, StringBuilder.ts:35-67, counting UTF-16 units as upstream
    does and keeping the text as UTF-8. }
  TTyLimitedStringBuilder = class
  private
    FBuf: array of Byte;
    FBytes: Integer;
    FUnits: Int64;
    FLimit: Int64;
  public
    constructor Create(ALimit: Int64);
    procedure Reset;
    { Appends AData[AStart..AEnd-1]; True (and the builder emptied) once the total
      exceeds the limit. }
    function Append(const AData: array of Cardinal; AStart, AEnd: Integer): Boolean;
    function Text: string;
    property Length: Int64 read FUnits;           { UTF-16 units }
    property Limit: Int64 read FLimit;
  end;

{ utf32ToString, with UTF-8 output. A code point above U+10FFFF or in the surrogate
  range becomes U+FFFD: the decoder never produces one, and upstream would build a
  lone surrogate or garbage, so there is no upstream answer to match. }
function TyTerminalCodepointsToUtf8(const AData: array of Cardinal; AStart, AEnd: Integer): string;
{ UTF-16 length of AData[AStart..AEnd-1]: above U+FFFF counts 2 (U+110000 and up
  included -- upstream never sees those). }
function TyTerminalUtf16Length(const AData: array of Cardinal; AStart, AEnd: Integer): Integer;

implementation

{ ---- TTyTerminalParams (Params.ts) -------------------------------------------- }

constructor TTyTerminalParams.Create(AMaxLength: Integer; AMaxSubParamsLength: Integer);
begin
  inherited Create;
  if AMaxSubParamsLength > TyTermParamsMaxSubParams then                      { :79-81 }
    raise EArgumentException.Create('maxSubParamsLength must not be greater than 256');
  FMaxLength := AMaxLength;
  FMaxSubParamsLength := AMaxSubParamsLength;
  SetLength(FParams, AMaxLength);
  SetLength(FSubParams, AMaxSubParamsLength);
  SetLength(FSubParamsIdx, AMaxLength);
end;

function TTyTerminalParams.GetParam(AIdx: Integer): Integer;
begin
  Result := FParams[AIdx];
end;

function TTyTerminalParams.Clone: TTyTerminalParams;                          { :95-106 }
begin
  Result := TTyTerminalParams.Create(FMaxLength, FMaxSubParamsLength);
  Result.FParams := Copy(FParams);
  Result.FLength := FLength;
  Result.FSubParams := Copy(FSubParams);
  Result.FSubParamsLength := FSubParamsLength;
  Result.FSubParamsIdx := Copy(FSubParamsIdx);
  Result.FRejectDigits := FRejectDigits;
  Result.FRejectSubDigits := FRejectSubDigits;
  Result.FDigitIsSub := FDigitIsSub;
end;

procedure TTyTerminalParams.Reset;                                           { :130-136 }
begin
  FLength := 0;
  FSubParamsLength := 0;
  FRejectDigits := False;
  FRejectSubDigits := False;
  FDigitIsSub := False;
end;

procedure TTyTerminalParams.ResetZdm;                                        { :141-149 }
begin
  FLength := 1;
  FSubParamsLength := 0;
  FRejectDigits := False;
  FRejectSubDigits := False;
  FDigitIsSub := False;
  FSubParamsIdx[0] := 0;
  FParams[0] := 0;
end;

procedure TTyTerminalParams.AddParam(AValue: Integer);                       { :158-169 }
begin
  FDigitIsSub := False;
  if FLength >= FMaxLength then
  begin
    FRejectDigits := True;
    Exit;
  end;
  if AValue < -1 then
    raise EArgumentException.Create('values less than -1 are not allowed');
  { Uint16 in upstream: the store wraps the same way }
  FSubParamsIdx[FLength] := Word((FSubParamsLength shl 8) or FSubParamsLength);
  FParams[FLength] := AValue;       { an Integer is never above $7FFFFFFF }
  Inc(FLength);
end;

procedure TTyTerminalParams.AddSubParam(AValue: Integer);                    { :178-192 }
begin
  FDigitIsSub := True;
  if FLength = 0 then
    Exit;
  if FRejectDigits or (FSubParamsLength >= FMaxSubParamsLength) then
  begin
    FRejectSubDigits := True;
    Exit;
  end;
  if AValue < -1 then
    raise EArgumentException.Create('values less than -1 are not allowed');
  FSubParams[FSubParamsLength] := AValue;
  Inc(FSubParamsLength);
  FSubParamsIdx[FLength - 1] := Word(FSubParamsIdx[FLength - 1] + 1);
end;

procedure TTyTerminalParams.AddDigit(AValue: Integer);                       { :235-247 }
var
  len: Integer;
  cur: Int64;
begin
  if FRejectDigits then
    Exit;
  if FDigitIsSub then
    len := FSubParamsLength
  else
    len := FLength;
  if (len = 0) or (FDigitIsSub and FRejectSubDigits) then
    Exit;
  if FDigitIsSub then
    cur := FSubParams[len - 1]
  else
    cur := FParams[len - 1];
  { ~cur: anything but -1 accumulates; cur * 10 + value in Int64, then clamped --
    upstream's float never wraps }
  if cur <> -1 then
  begin
    cur := cur * 10 + AValue;
    if cur > TyTermParamsMaxValue then
      cur := TyTermParamsMaxValue;
  end
  else
    cur := AValue;
  if FDigitIsSub then
    FSubParams[len - 1] := Integer(cur)
  else
    FParams[len - 1] := Integer(cur);
end;

function TTyTerminalParams.HasSubParams(AIdx: Integer): Boolean;             { :197-199 }
begin
  Result := (FSubParamsIdx[AIdx] and $FF) - (FSubParamsIdx[AIdx] shr 8) > 0;
end;

function TTyTerminalParams.SubParamCount(AIdx: Integer): Integer;            { :206-213 }
begin
  Result := (FSubParamsIdx[AIdx] and $FF) - (FSubParamsIdx[AIdx] shr 8);
  if Result < 0 then
    Result := 0;
end;

function TTyTerminalParams.SubParam(AIdx, ASub: Integer): Integer;
begin
  Result := FSubParams[(FSubParamsIdx[AIdx] shr 8) + ASub];
end;

function TTyTerminalParams.ToJson: string;                                   { :114-125 }
var
  i, k, s, e: Integer;
begin
  Result := '[';
  for i := 0 to FLength - 1 do
  begin
    if i > 0 then
      Result := Result + ',';
    Result := Result + IntToStr(FParams[i]);
    s := FSubParamsIdx[i] shr 8;
    e := FSubParamsIdx[i] and $FF;
    if e - s > 0 then
    begin
      Result := Result + ',[';
      for k := s to e - 1 do
      begin
        if k > s then
          Result := Result + ',';
        Result := Result + IntToStr(FSubParams[k]);
      end;
      Result := Result + ']';
    end;
  end;
  Result := Result + ']';
end;

{ ---- TTyUtf8Decoder (TextDecoder.ts:121-346) ------------------------------------ }

procedure TTyUtf8Decoder.Clear;
begin
  FillChar(FInterim, SizeOf(FInterim), 0);
end;

function TTyUtf8Decoder.Decode(const ABytes; ACount: Integer; var AOut: array of Cardinal): Integer;
var
  input: PByte;
  size, startPos, i, fourStop, pos, typ, missing: Integer;
  cp, tmp, codepoint: Cardinal;
  byte1, byte2, byte3, byte4: Cardinal;
  discardInterim: Boolean;
begin
  Assert(System.Length(AOut) >= ACount);
  input := @ABytes;
  if ACount <= 0 then
    Exit(0);
  size := 0;
  startPos := 0;

  { leftover bytes from the last call (:155-209) }
  if FInterim[0] <> 0 then
  begin
    discardInterim := False;
    cp := FInterim[0];
    if (cp and $E0) = $C0 then
      cp := cp and $1F
    else if (cp and $F0) = $E0 then
      cp := cp and $0F
    else
      cp := cp and $07;
    { while ((tmp = interim[++pos]) && pos < 4): interim[3] is undefined there }
    pos := 0;
    while True do
    begin
      Inc(pos);
      if pos > 2 then
        Break;
      tmp := FInterim[pos];
      if tmp = 0 then
        Break;
      cp := (cp shl 6) or (tmp and $3F);
    end;
    if (FInterim[0] and $E0) = $C0 then
      typ := 2
    else if (FInterim[0] and $F0) = $E0 then
      typ := 3
    else
      typ := 4;
    missing := typ - pos;
    while startPos < missing do
    begin
      if startPos >= ACount then
        Exit(0);
      tmp := input[startPos];
      Inc(startPos);
      if (tmp and $C0) <> $80 then
      begin
        { wrong continuation: drop the interim bytes, reread this one }
        Dec(startPos);
        discardInterim := True;
        Break;
      end
      else
      begin
        if pos <= 2 then                 { a Uint8Array(3) ignores the write at 3 }
          FInterim[pos] := tmp;
        Inc(pos);
        cp := (cp shl 6) or (tmp and $3F);
      end;
    end;
    if not discardInterim then
    begin
      if typ = 2 then
      begin
        if cp < $80 then
          Dec(startPos)                  { wrong starter byte }
        else
        begin
          AOut[size] := cp;
          Inc(size);
        end;
      end
      else if typ = 3 then
      begin
        if not ((cp < $0800) or ((cp >= $D800) and (cp <= $DFFF)) or (cp = $FEFF)) then
        begin
          AOut[size] := cp;
          Inc(size);
        end;
      end
      else
      begin
        if not ((cp < $010000) or (cp > $10FFFF)) then
        begin
          AOut[size] := cp;
          Inc(size);
        end;
      end;
    end;
    FillChar(FInterim, SizeOf(FInterim), 0);
  end;

  { main loop (:212-345); the four-byte ASCII unrolling is kept as upstream has it }
  fourStop := ACount - 4;
  i := startPos;
  while i < ACount do
  begin
    while (i < fourStop) and (input[i] and $80 = 0) and (input[i + 1] and $80 = 0)
      and (input[i + 2] and $80 = 0) and (input[i + 3] and $80 = 0) do
    begin
      AOut[size] := input[i];
      AOut[size + 1] := input[i + 1];
      AOut[size + 2] := input[i + 2];
      AOut[size + 3] := input[i + 3];
      Inc(size, 4);
      Inc(i, 4);
    end;

    byte1 := input[i];
    Inc(i);
    if byte1 < $80 then
    begin
      AOut[size] := byte1;
      Inc(size);
    end
    else if (byte1 and $E0) = $C0 then
    begin
      if i >= ACount then
      begin
        FInterim[0] := byte1;
        Exit(size);
      end;
      byte2 := input[i];
      Inc(i);
      if (byte2 and $C0) <> $80 then
      begin
        Dec(i);
        Continue;
      end;
      codepoint := ((byte1 and $1F) shl 6) or (byte2 and $3F);
      if codepoint < $80 then
      begin
        Dec(i);
        Continue;
      end;
      AOut[size] := codepoint;
      Inc(size);
    end
    else if (byte1 and $F0) = $E0 then
    begin
      if i >= ACount then
      begin
        FInterim[0] := byte1;
        Exit(size);
      end;
      byte2 := input[i];
      Inc(i);
      if (byte2 and $C0) <> $80 then
      begin
        Dec(i);
        Continue;
      end;
      if i >= ACount then
      begin
        FInterim[0] := byte1;
        FInterim[1] := byte2;
        Exit(size);
      end;
      byte3 := input[i];
      Inc(i);
      if (byte3 and $C0) <> $80 then
      begin
        Dec(i);
        Continue;
      end;
      codepoint := ((byte1 and $0F) shl 12) or ((byte2 and $3F) shl 6) or (byte3 and $3F);
      if (codepoint < $0800) or ((codepoint >= $D800) and (codepoint <= $DFFF)) or (codepoint = $FEFF) then
        Continue;                        { illegal or BOM, no i-- here }
      AOut[size] := codepoint;
      Inc(size);
    end
    else if (byte1 and $F8) = $F0 then
    begin
      if i >= ACount then
      begin
        FInterim[0] := byte1;
        Exit(size);
      end;
      byte2 := input[i];
      Inc(i);
      if (byte2 and $C0) <> $80 then
      begin
        Dec(i);
        Continue;
      end;
      if i >= ACount then
      begin
        FInterim[0] := byte1;
        FInterim[1] := byte2;
        Exit(size);
      end;
      byte3 := input[i];
      Inc(i);
      if (byte3 and $C0) <> $80 then
      begin
        Dec(i);
        Continue;
      end;
      if i >= ACount then
      begin
        FInterim[0] := byte1;
        FInterim[1] := byte2;
        FInterim[2] := byte3;
        Exit(size);
      end;
      byte4 := input[i];
      Inc(i);
      if (byte4 and $C0) <> $80 then
      begin
        Dec(i);
        Continue;
      end;
      codepoint := ((byte1 and $07) shl 18) or ((byte2 and $3F) shl 12) or ((byte3 and $3F) shl 6)
        or (byte4 and $3F);
      if (codepoint < $010000) or (codepoint > $10FFFF) then
        Continue;                        { illegal, no i-- here }
      AOut[size] := codepoint;
      Inc(size);
    end;
    { else: an illegal byte, skipped }
  end;
  Result := size;
end;

{ ---- string helpers ------------------------------------------------------------- }

function TyTerminalCodepointsToUtf8(const AData: array of Cardinal; AStart, AEnd: Integer): string;
var
  i, n: Integer;
  c: Cardinal;
  p: PChar;
begin
  n := 0;
  for i := AStart to AEnd - 1 do
  begin
    c := AData[i];
    if (c > $10FFFF) or ((c >= $D800) and (c <= $DFFF)) then
      Inc(n, 3)
    else if c < $80 then
      Inc(n)
    else if c < $800 then
      Inc(n, 2)
    else if c < $10000 then
      Inc(n, 3)
    else
      Inc(n, 4);
  end;
  SetLength(Result, n);
  if n = 0 then
    Exit;
  p := PChar(Result);
  for i := AStart to AEnd - 1 do
  begin
    c := AData[i];
    if (c > $10FFFF) or ((c >= $D800) and (c <= $DFFF)) then
      c := $FFFD;
    if c < $80 then
    begin
      p^ := Chr(c);
      Inc(p);
    end
    else if c < $800 then
    begin
      p[0] := Chr($C0 or (c shr 6));
      p[1] := Chr($80 or (c and $3F));
      Inc(p, 2);
    end
    else if c < $10000 then
    begin
      p[0] := Chr($E0 or (c shr 12));
      p[1] := Chr($80 or ((c shr 6) and $3F));
      p[2] := Chr($80 or (c and $3F));
      Inc(p, 3);
    end
    else
    begin
      p[0] := Chr($F0 or (c shr 18));
      p[1] := Chr($80 or ((c shr 12) and $3F));
      p[2] := Chr($80 or ((c shr 6) and $3F));
      p[3] := Chr($80 or (c and $3F));
      Inc(p, 4);
    end;
  end;
end;

function TyTerminalUtf16Length(const AData: array of Cardinal; AStart, AEnd: Integer): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := AStart to AEnd - 1 do
    if AData[i] > $FFFF then
      Inc(Result, 2)
    else
      Inc(Result);
end;

{ ---- TTyLimitedStringBuilder (StringBuilder.ts:35-67) ---------------------------- }

constructor TTyLimitedStringBuilder.Create(ALimit: Int64);
begin
  inherited Create;
  FLimit := ALimit;
end;

procedure TTyLimitedStringBuilder.Reset;
begin
  FBytes := 0;
  FUnits := 0;
  if System.Length(FBuf) > 65536 then
    SetLength(FBuf, 0);                  { give a large payload's memory back }
end;

function TTyLimitedStringBuilder.Append(const AData: array of Cardinal; AStart, AEnd: Integer): Boolean;
var
  s: string;
  n: Integer;
begin
  { Upstream appends, then compares the total with ">" and empties the builder.
    Checking first gives the same answer without growing past the limit. }
  FUnits := FUnits + TyTerminalUtf16Length(AData, AStart, AEnd);
  if FUnits > FLimit then
  begin
    FBytes := 0;
    FUnits := 0;
    SetLength(FBuf, 0);
    Exit(True);
  end;
  s := TyTerminalCodepointsToUtf8(AData, AStart, AEnd);
  n := System.Length(s);
  if n > 0 then
  begin
    if FBytes + n > System.Length(FBuf) then
    begin
      if System.Length(FBuf) * 2 > FBytes + n then
        SetLength(FBuf, System.Length(FBuf) * 2)
      else
        SetLength(FBuf, FBytes + n + 64);
    end;
    Move(s[1], FBuf[FBytes], n);
    Inc(FBytes, n);
  end;
  Result := False;
end;

function TTyLimitedStringBuilder.Text: string;
begin
  SetLength(Result, FBytes);
  if FBytes > 0 then
    Move(FBuf[0], Result[1], FBytes);
end;

end.
