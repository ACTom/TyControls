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

  TTyTerminalPrintEvent    = procedure(const AData: array of Cardinal; AStart, AEnd: Integer) of object;
  TTyTerminalExecuteEvent  = function: Boolean of object;                 { return value ignored, as upstream }
  TTyTerminalCsiEvent      = function(AParams: TTyTerminalParams): Boolean of object;
  TTyTerminalEscEvent      = function: Boolean of object;
  TTyTerminalExecuteFallback = procedure(ACode: Cardinal) of object;
  TTyTerminalCsiFallback   = procedure(AIdent: Cardinal; AParams: TTyTerminalParams) of object;
  TTyTerminalEscFallback   = procedure(AIdent: Cardinal) of object;
  { OSC / APC: START PUT END; DCS: HOOK PUT UNHOOK }
  TTyTermSubAction = (tsaStart, tsaPut, tsaEnd);
  { APayload (UTF-8) only for PUT, ASuccess only for END / UNHOOK. An OSC number is
    -1 when the sequence had none, and saturates far above High(Integer). }
  TTyTerminalOscFallback   = procedure(AIdent: Int64; AAction: TTyTermSubAction;
                               const APayload: string; ASuccess: Boolean) of object;
  { AParams only for HOOK (borrowed). }
  TTyTerminalDcsFallback   = procedure(AIdent: Cardinal; AAction: TTyTermSubAction;
                               AParams: TTyTerminalParams; const APayload: string; ASuccess: Boolean) of object;
  TTyTerminalApcFallback   = procedure(AIdent: Cardinal; AAction: TTyTermSubAction;
                               const APayload: string; ASuccess: Boolean) of object;
  { IParsingState minus params; setting Abort stops the current Parse call. }
  TTyTermParsingState = record
    Position: Integer;
    Code: Cardinal;
    CurrentState: TTyTermParserState;
    Collect: Cardinal;
    Abort: Boolean;
  end;
  TTyTerminalErrorEvent    = procedure(var AState: TTyTermParsingState) of object;

  { IOscHandler; upstream's end() is Finish here (a reserved word). }
  TTyTerminalOscHandler = class
  public
    procedure Start; virtual; abstract;
    procedure Put(const AData: array of Cardinal; AStart, AEnd: Integer); virtual; abstract;
    function Finish(ASuccess: Boolean): Boolean; virtual; abstract;
  end;
  TTyTerminalOscDataEvent = function(const AData: string): Boolean of object;   { UTF-8 }

  { OscHandler, OscParser.ts:195-237: collects the payload up to the limit and hands
    it over on a successful end. }
  TTyTerminalOscStringHandler = class(TTyTerminalOscHandler)
  private
    FData: TTyLimitedStringBuilder;
    FHitLimit: Boolean;
    FOnData: TTyTerminalOscDataEvent;
  public
    constructor Create(AOnData: TTyTerminalOscDataEvent);
    destructor Destroy; override;
    procedure Start; override;
    procedure Put(const AData: array of Cardinal; AStart, AEnd: Integer); override;
    function Finish(ASuccess: Boolean): Boolean; override;
    function PayloadLength: Int64;       { UTF-16 units collected so far }
  end;

  { IDcsHandler }
  TTyTerminalDcsHandler = class
  public
    procedure Hook(AParams: TTyTerminalParams); virtual; abstract;
    procedure Put(const AData: array of Cardinal; AStart, AEnd: Integer); virtual; abstract;
    function Unhook(ASuccess: Boolean): Boolean; virtual; abstract;
  end;
  TTyTerminalDcsDataEvent = function(const AData: string; AParams: TTyTerminalParams): Boolean of object;

  { DcsHandler, DcsParser.ts:141-191 }
  TTyTerminalDcsStringHandler = class(TTyTerminalDcsHandler)
  private
    FData: TTyLimitedStringBuilder;
    FHitLimit: Boolean;
    FParams: TTyTerminalParams;          { a clone, or the shared empty [0] }
    FOnData: TTyTerminalDcsDataEvent;
    procedure DropParams;
  public
    constructor Create(AOnData: TTyTerminalDcsDataEvent);
    destructor Destroy; override;
    procedure Hook(AParams: TTyTerminalParams); override;
    procedure Put(const AData: array of Cardinal; AStart, AEnd: Integer); override;
    function Unhook(ASuccess: Boolean): Boolean; override;
  end;

  { IApcHandler }
  TTyTerminalApcHandler = class
  public
    procedure Start; virtual; abstract;
    procedure Put(const AData: array of Cardinal; AStart, AEnd: Integer); virtual; abstract;
    function Finish(ASuccess: Boolean): Boolean; virtual; abstract;
  end;

  { ApcHandler, ApcParser.ts:154-196 }
  TTyTerminalApcStringHandler = class(TTyTerminalApcHandler)
  private
    FData: TTyLimitedStringBuilder;
    FHitLimit: Boolean;
    FOnData: TTyTerminalOscDataEvent;
  public
    constructor Create(AOnData: TTyTerminalOscDataEvent);
    destructor Destroy; override;
    procedure Start; override;
    procedure Put(const AData: array of Cardinal; AStart, AEnd: Integer); override;
    function Finish(ASuccess: Boolean): Boolean; override;
  end;

  { IFunctionIdentifier }
  TTyTerminalFunctionId = record
    Prefix, Intermediates: string;
    Final: Char;
  end;

  TTyTerminalParser = class;

  { One identifier's handler chain, in registration order (the last registered runs
    first). Internal to the parser; public only so the sub-parsers can share it. }
  TTyTermHandlerEntry = record
    Handle: Integer;
    Method: TMethod;                     { CSI / ESC }
    Obj: TObject;                        { OSC / DCS / APC, owned }
  end;
  TTyTermHandlerList = class
  public
    Ident: Int64;
    Count: Integer;
    Items: array of TTyTermHandlerEntry;
  end;

  { IHandlerCollection: identifier -> chain, sorted by identifier. }
  TTyTermHandlerTable = class
  private
    FOwner: TTyTerminalParser;
    FLists: array of TTyTermHandlerList;
    FCount: Integer;
    function IndexOf(AIdent: Int64; out AIndex: Integer): Boolean;
  public
    constructor Create(AOwner: TTyTerminalParser);
    destructor Destroy; override;
    function Find(AIdent: Int64): TTyTermHandlerList;
    function Add(AIdent: Int64; const AMethod: TMethod; AObj: TObject): Integer;
    function RemoveHandle(AHandle: Integer): Boolean;
    procedure Clear(AIdent: Int64);
  end;

  { OscParser.ts:14-189 }
  TTyTermOscParser = class
  private
    FOwner: TTyTerminalParser;
    FTable: TTyTermHandlerTable;
    FState: Integer;                     { OscState: 0 START, 1 ID, 2 PAYLOAD, 3 ABORT }
    FActive: TTyTermHandlerList;         { nil = EMPTY_HANDLERS }
    FId: Int64;
    FFallback: TTyTerminalOscFallback;
    function ActiveCount: Integer;
    procedure DoStart;
    procedure DoPut(const AData: array of Cardinal; AStart, AEnd: Integer);
  public
    constructor Create(AOwner: TTyTerminalParser; ATable: TTyTermHandlerTable);
    procedure Reset;
    procedure Start;
    procedure Put(const AData: array of Cardinal; AStart, AEnd: Integer);
    procedure Finish(ASuccess: Boolean);
  end;

  { DcsParser.ts:15-131 }
  TTyTermDcsParser = class
  private
    FTable: TTyTermHandlerTable;
    FActive: TTyTermHandlerList;
    FIdent: Cardinal;
    FFallback: TTyTerminalDcsFallback;
    function ActiveCount: Integer;
  public
    constructor Create(ATable: TTyTermHandlerTable);
    procedure Reset;
    procedure Hook(AIdent: Cardinal; AParams: TTyTerminalParams);
    procedure Put(const AData: array of Cardinal; AStart, AEnd: Integer);
    procedure Unhook(ASuccess: Boolean);
  end;

  { ApcParser.ts:22-148 }
  TTyTermApcParser = class
  private
    FTable: TTyTermHandlerTable;
    FActive: TTyTermHandlerList;
    FIdent: Cardinal;
    FFallback: TTyTerminalApcFallback;
    function ActiveCount: Integer;
  public
    constructor Create(ATable: TTyTermHandlerTable);
    procedure Reset;
    procedure Start(AIdent: Cardinal);
    procedure Put(const AData: array of Cardinal; AStart, AEnd: Integer);
    procedure Finish(ASuccess: Boolean);
  end;

  { EscapeSequenceParser, EscapeSequenceParser.ts:263-933. }
  TTyTerminalParser = class
  private
    FCurrentState: TTyTermParserState;
    FParams: TTyTerminalParams;
    FCollect: Cardinal;
    FPrecedingJoinState: TTyUnicodeCharProps;
    FPrintHandler: TTyTerminalPrintEvent;
    FExecHandlers: array[0..255] of TTyTerminalExecuteEvent;
    FExecFallback: TTyTerminalExecuteFallback;
    FCsiFallback: TTyTerminalCsiFallback;
    FEscFallback: TTyTerminalEscFallback;
    FErrorHandler: TTyTerminalErrorEvent;
    FCsi, FEsc, FOscTable, FDcsTable, FApcTable: TTyTermHandlerTable;
    FOsc: TTyTermOscParser;
    FDcs: TTyTermDcsParser;
    FApc: TTyTermApcParser;
    FNextHandle: Integer;
    FDispatchDepth: Integer;
    FDeadObjects: TFPList;               { handler objects unregistered while in use }
    FDeadLists: TFPList;                 { cleared chains a sub-parser still points at }
    function IdentOf(const AId: TTyTerminalFunctionId; AFinalLo, AFinalHi: Integer;
      AUsePrefix: Boolean = True): Cardinal;
    function SwallowSt: Boolean;
    procedure DispatchCsi(AIdent: Cardinal);
    procedure DispatchEsc(AIdent: Cardinal);
    function NewHandle: Integer;
    procedure DisposeObject(AObj: TObject);
    procedure DisposeList(AList: TTyTermHandlerList);
    function GetOscPayloadLength: Int64;
  public
    constructor Create;
    destructor Destroy; override;
    function IdentToString(AIdent: Cardinal): string;
    procedure SetPrintHandler(AHandler: TTyTerminalPrintEvent);
    procedure ClearPrintHandler;
    procedure SetExecuteHandler(ACode: Byte; AHandler: TTyTerminalExecuteEvent);
    procedure ClearExecuteHandler(ACode: Byte);
    procedure SetExecuteHandlerFallback(AHandler: TTyTerminalExecuteFallback);
    function RegisterCsiHandler(const AId: TTyTerminalFunctionId; AHandler: TTyTerminalCsiEvent): Integer;
    procedure ClearCsiHandler(const AId: TTyTerminalFunctionId);
    procedure SetCsiHandlerFallback(AHandler: TTyTerminalCsiFallback);
    function RegisterEscHandler(const AId: TTyTerminalFunctionId; AHandler: TTyTerminalEscEvent): Integer;
    procedure ClearEscHandler(const AId: TTyTerminalFunctionId);
    procedure SetEscHandlerFallback(AHandler: TTyTerminalEscFallback);
    function RegisterOscHandler(AIdent: Integer; AHandler: TTyTerminalOscHandler): Integer;
    procedure ClearOscHandler(AIdent: Integer);
    procedure SetOscHandlerFallback(AHandler: TTyTerminalOscFallback);
    function RegisterDcsHandler(const AId: TTyTerminalFunctionId; AHandler: TTyTerminalDcsHandler): Integer;
    procedure ClearDcsHandler(const AId: TTyTerminalFunctionId);
    procedure SetDcsHandlerFallback(AHandler: TTyTerminalDcsFallback);
    { The prefix of AId is ignored: APC has none (EscapeSequenceParser.ts:468). }
    function RegisterApcHandler(const AId: TTyTerminalFunctionId; AHandler: TTyTerminalApcHandler): Integer;
    procedure ClearApcHandler(const AId: TTyTerminalFunctionId);
    procedure SetApcHandlerFallback(AHandler: TTyTerminalApcFallback);
    procedure SetErrorHandler(AHandler: TTyTerminalErrorEvent);
    procedure ClearErrorHandler;
    { IDisposable.dispose of a Register* result; an unknown handle, or one already
      unregistered, is ignored. }
    procedure Unregister(AHandle: Integer);
    procedure Parse(const AData: array of Cardinal; ALength: Integer);
    procedure Reset;
    property CurrentState: TTyTermParserState read FCurrentState;
    property PrecedingJoinState: TTyUnicodeCharProps read FPrecedingJoinState write FPrecedingJoinState;
    { FOR THE TESTS (a pure query, nothing uses it at run time): UTF-16 units the
      first string handler of the running OSC holds, 0 when there is none. }
    property OscPayloadLength: Int64 read GetOscPayloadLength;
  end;

function TyTerminalFunctionId(const APrefix, AIntermediates: string; AFinal: Char): TTyTerminalFunctionId;
{ FOR THE TESTS (a pure query): entry AIndex of the transition table built at
  start-up. }
function TyTermTransition(AIndex: Integer): Word;

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
  p: PChar;
begin
  Result := '';
  n := 0;
  for i := AStart to AEnd - 1 do
    Inc(n, TyUnicodeUtf8Size(AData[i]));
  SetLength(Result, n);
  if n = 0 then
    Exit;
  p := PChar(Result);
  for i := AStart to AEnd - 1 do
    Inc(p, TyUnicodeUtf8Encode(AData[i], p));
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

{ ---- the transition table (EscapeSequenceParser.ts:97-230) ----------------------- }

const
  NonAsciiPrintable = $A0;              { :90 NON_ASCII_PRINTABLE }

var
  GTransitions: array[0..TyTermTransitionCount - 1] of Word;
  GEmptyParams: TTyTerminalParams;       { DcsParser.ts:134-135 EMPTY_PARAMS = [0] }

{ Built by the same statements upstream runs at module load (spec 17.2 #6), not
  copied as data; tests/test.terminal.parser.pas compares every entry. }
procedure BuildTransitions;
var
  st: TTyTermParserState;

  procedure SetDefault(AAction: TTyTermParserAction; ANext: TTyTermParserState);
  var
    i: Integer;
  begin
    for i := 0 to High(GTransitions) do
      GTransitions[i] := (Ord(AAction) shl 8) or Ord(ANext);
  end;

  procedure Add(ACode: Integer; AState: TTyTermParserState; AAction: TTyTermParserAction;
    ANext: TTyTermParserState);
  var
    idx: Integer;
  begin
    idx := (Ord(AState) shl 8) or ACode;
    if idx <= High(GTransitions) then      { a Uint16Array ignores writes past its end }
      GTransitions[idx] := (Ord(AAction) shl 8) or Ord(ANext);
  end;

  { r(start, end): the half-open byte range [start, end) }
  procedure AddRange(AStart, AEnd: Integer; AState: TTyTermParserState;
    AAction: TTyTermParserAction; ANext: TTyTermParserState);
  var
    c: Integer;
  begin
    for c := AStart to AEnd - 1 do
      Add(c, AState, AAction, ANext);
  end;

  procedure AddList(const ACodes: array of Integer; AState: TTyTermParserState;
    AAction: TTyTermParserAction; ANext: TTyTermParserState);
  var
    i: Integer;
  begin
    for i := 0 to High(ACodes) do
      Add(ACodes[i], AState, AAction, ANext);
  end;

  { PRINTABLES = r(0x20, 0x7f) }
  procedure AddPrintables(AState: TTyTermParserState; AAction: TTyTermParserAction;
    ANext: TTyTermParserState);
  begin
    AddRange($20, $7F, AState, AAction, ANext);
  end;

  { EXECUTABLES = r(0x00, 0x18) + [0x19] + r(0x1c, 0x20) }
  procedure AddExecutables(AState: TTyTermParserState; AAction: TTyTermParserAction;
    ANext: TTyTermParserState);
  begin
    AddRange($00, $18, AState, AAction, ANext);
    Add($19, AState, AAction, ANext);
    AddRange($1C, $20, AState, AAction, ANext);
  end;

begin
  SetDefault(tpaError, tpsGround);
  AddPrintables(tpsGround, tpaPrint, tpsGround);
  { global anywhere rules }
  for st := Low(TTyTermParserState) to High(TTyTermParserState) do
  begin
    AddList([$18, $1A, $99, $9A], st, tpaExecute, tpsGround);
    AddRange($80, $90, st, tpaExecute, tpsGround);
    AddRange($90, $98, st, tpaExecute, tpsGround);
    Add($9C, st, tpaIgnore, tpsGround);
    Add($1B, st, tpaClear, tpsEscape);
    Add($9D, st, tpaOscStart, tpsOscString);
    AddList([$98, $9E], st, tpaIgnore, tpsSosPmString);
    Add($9F, st, tpaClear, tpsApcEntry);
    Add($9B, st, tpaClear, tpsCsiEntry);
    Add($90, st, tpaClear, tpsDcsEntry);
  end;
  { rules for executables and 7f }
  AddExecutables(tpsGround, tpaExecute, tpsGround);
  AddExecutables(tpsEscape, tpaExecute, tpsEscape);
  Add($7F, tpsEscape, tpaIgnore, tpsEscape);
  AddExecutables(tpsOscString, tpaIgnore, tpsOscString);
  AddExecutables(tpsCsiEntry, tpaExecute, tpsCsiEntry);
  Add($7F, tpsCsiEntry, tpaIgnore, tpsCsiEntry);
  AddExecutables(tpsCsiParam, tpaExecute, tpsCsiParam);
  Add($7F, tpsCsiParam, tpaIgnore, tpsCsiParam);
  AddExecutables(tpsCsiIgnore, tpaExecute, tpsCsiIgnore);
  AddExecutables(tpsCsiIntermediate, tpaExecute, tpsCsiIntermediate);
  Add($7F, tpsCsiIntermediate, tpaIgnore, tpsCsiIntermediate);
  AddExecutables(tpsEscapeIntermediate, tpaExecute, tpsEscapeIntermediate);
  Add($7F, tpsEscapeIntermediate, tpaIgnore, tpsEscapeIntermediate);
  { osc }
  Add($5D, tpsEscape, tpaOscStart, tpsOscString);
  AddPrintables(tpsOscString, tpaOscPut, tpsOscString);
  Add($7F, tpsOscString, tpaOscPut, tpsOscString);
  AddList([$9C, $1B, $18, $1A, $07], tpsOscString, tpaOscEnd, tpsGround);
  AddRange($1C, $20, tpsOscString, tpaIgnore, tpsOscString);
  { sos/pm }
  AddList([$58, $5E], tpsEscape, tpaIgnore, tpsSosPmString);
  AddPrintables(tpsSosPmString, tpaIgnore, tpsSosPmString);
  AddExecutables(tpsSosPmString, tpaIgnore, tpsSosPmString);
  Add($9C, tpsSosPmString, tpaIgnore, tpsGround);
  Add($7F, tpsSosPmString, tpaIgnore, tpsSosPmString);
  { apc }
  Add($5F, tpsEscape, tpaClear, tpsApcEntry);
  AddExecutables(tpsApcEntry, tpaIgnore, tpsApcEntry);
  Add($7F, tpsApcEntry, tpaIgnore, tpsApcEntry);
  AddRange($20, $30, tpsApcEntry, tpaCollect, tpsApcIntermediate);
  AddRange($30, $7F, tpsApcEntry, tpaApcStart, tpsApcPassthrough);
  AddRange($30, $7F, tpsApcIntermediate, tpaApcStart, tpsApcPassthrough);
  AddExecutables(tpsApcIntermediate, tpaIgnore, tpsApcIntermediate);
  AddRange($20, $30, tpsApcIntermediate, tpaCollect, tpsApcIntermediate);
  Add($7F, tpsApcIntermediate, tpaIgnore, tpsApcIntermediate);
  AddPrintables(tpsApcPassthrough, tpaApcPut, tpsApcPassthrough);
  AddExecutables(tpsApcPassthrough, tpaIgnore, tpsApcPassthrough);
  AddRange($08, $0E, tpsApcPassthrough, tpaApcPut, tpsApcPassthrough);
  Add($7F, tpsApcPassthrough, tpaIgnore, tpsApcPassthrough);
  AddList([$1B, $9C, $18, $1A], tpsApcPassthrough, tpaApcEnd, tpsGround);
  { csi entries }
  Add($5B, tpsEscape, tpaClear, tpsCsiEntry);
  AddRange($40, $7F, tpsCsiEntry, tpaCsiDispatch, tpsGround);
  AddRange($30, $3C, tpsCsiEntry, tpaParam, tpsCsiParam);
  AddList([$3C, $3D, $3E, $3F], tpsCsiEntry, tpaCollect, tpsCsiParam);
  AddRange($30, $3C, tpsCsiParam, tpaParam, tpsCsiParam);
  AddRange($40, $7F, tpsCsiParam, tpaCsiDispatch, tpsGround);
  AddList([$3C, $3D, $3E, $3F], tpsCsiParam, tpaIgnore, tpsCsiIgnore);
  AddRange($20, $40, tpsCsiIgnore, tpaIgnore, tpsCsiIgnore);
  Add($7F, tpsCsiIgnore, tpaIgnore, tpsCsiIgnore);
  AddRange($40, $7F, tpsCsiIgnore, tpaIgnore, tpsGround);
  AddRange($20, $30, tpsCsiEntry, tpaCollect, tpsCsiIntermediate);
  AddRange($20, $30, tpsCsiIntermediate, tpaCollect, tpsCsiIntermediate);
  AddRange($30, $40, tpsCsiIntermediate, tpaIgnore, tpsCsiIgnore);
  AddRange($40, $7F, tpsCsiIntermediate, tpaCsiDispatch, tpsGround);
  AddRange($20, $30, tpsCsiParam, tpaCollect, tpsCsiIntermediate);
  { esc_intermediate }
  AddRange($20, $30, tpsEscape, tpaCollect, tpsEscapeIntermediate);
  AddRange($20, $30, tpsEscapeIntermediate, tpaCollect, tpsEscapeIntermediate);
  AddRange($30, $7F, tpsEscapeIntermediate, tpaEscDispatch, tpsGround);
  AddRange($30, $50, tpsEscape, tpaEscDispatch, tpsGround);
  AddRange($51, $58, tpsEscape, tpaEscDispatch, tpsGround);
  AddList([$59, $5A, $5C], tpsEscape, tpaEscDispatch, tpsGround);
  AddRange($60, $7F, tpsEscape, tpaEscDispatch, tpsGround);
  { dcs entry }
  Add($50, tpsEscape, tpaClear, tpsDcsEntry);
  AddExecutables(tpsDcsEntry, tpaIgnore, tpsDcsEntry);
  Add($7F, tpsDcsEntry, tpaIgnore, tpsDcsEntry);
  AddRange($20, $30, tpsDcsEntry, tpaCollect, tpsDcsIntermediate);
  AddRange($30, $3C, tpsDcsEntry, tpaParam, tpsDcsParam);
  AddList([$3C, $3D, $3E, $3F], tpsDcsEntry, tpaCollect, tpsDcsParam);
  AddExecutables(tpsDcsIgnore, tpaIgnore, tpsDcsIgnore);
  AddRange($20, $80, tpsDcsIgnore, tpaIgnore, tpsDcsIgnore);
  AddExecutables(tpsDcsParam, tpaIgnore, tpsDcsParam);
  Add($7F, tpsDcsParam, tpaIgnore, tpsDcsParam);
  AddRange($30, $3C, tpsDcsParam, tpaParam, tpsDcsParam);
  AddList([$3C, $3D, $3E, $3F], tpsDcsParam, tpaIgnore, tpsDcsIgnore);
  AddRange($20, $30, tpsDcsParam, tpaCollect, tpsDcsIntermediate);
  AddExecutables(tpsDcsIntermediate, tpaIgnore, tpsDcsIntermediate);
  Add($7F, tpsDcsIntermediate, tpaIgnore, tpsDcsIntermediate);
  AddRange($20, $30, tpsDcsIntermediate, tpaCollect, tpsDcsIntermediate);
  AddRange($30, $40, tpsDcsIntermediate, tpaIgnore, tpsDcsIgnore);
  AddRange($40, $7F, tpsDcsIntermediate, tpaDcsHook, tpsDcsPassthrough);
  AddRange($40, $7F, tpsDcsParam, tpaDcsHook, tpsDcsPassthrough);
  AddRange($40, $7F, tpsDcsEntry, tpaDcsHook, tpsDcsPassthrough);
  AddExecutables(tpsDcsPassthrough, tpaDcsPut, tpsDcsPassthrough);
  AddPrintables(tpsDcsPassthrough, tpaDcsPut, tpsDcsPassthrough);
  Add($7F, tpsDcsPassthrough, tpaIgnore, tpsDcsPassthrough);
  AddList([$1B, $9C, $18, $1A], tpsDcsPassthrough, tpaDcsUnhook, tpsGround);
  { special handling of unicode chars }
  Add(NonAsciiPrintable, tpsGround, tpaPrint, tpsGround);
  Add(NonAsciiPrintable, tpsOscString, tpaOscPut, tpsOscString);
  Add(NonAsciiPrintable, tpsCsiIgnore, tpaIgnore, tpsCsiIgnore);
  Add(NonAsciiPrintable, tpsDcsIgnore, tpaIgnore, tpsDcsIgnore);
  Add(NonAsciiPrintable, tpsDcsPassthrough, tpaDcsPut, tpsDcsPassthrough);
  Add(NonAsciiPrintable, tpsApcPassthrough, tpaApcPut, tpsApcPassthrough);
end;

function TyTermTransition(AIndex: Integer): Word;
begin
  Result := GTransitions[AIndex];
end;

function TyTerminalFunctionId(const APrefix, AIntermediates: string; AFinal: Char): TTyTerminalFunctionId;
begin
  Result.Prefix := APrefix;
  Result.Intermediates := AIntermediates;
  Result.Final := AFinal;
end;

{ ---- string handlers ------------------------------------------------------------- }

constructor TTyTerminalOscStringHandler.Create(AOnData: TTyTerminalOscDataEvent);
begin
  inherited Create;
  FOnData := AOnData;
  FData := TTyLimitedStringBuilder.Create(TyTermParserPayloadLimit);
end;

destructor TTyTerminalOscStringHandler.Destroy;
begin
  FData.Free;
  inherited Destroy;
end;

procedure TTyTerminalOscStringHandler.Start;                                 { :203-206 }
begin
  FData.Reset;
  FHitLimit := False;
end;

procedure TTyTerminalOscStringHandler.Put(const AData: array of Cardinal; AStart, AEnd: Integer);
begin                                                                        { :208-215 }
  if FHitLimit then
    Exit;
  if FData.Append(AData, AStart, AEnd) then
    FHitLimit := True;
end;

function TTyTerminalOscStringHandler.Finish(ASuccess: Boolean): Boolean;     { :217-236 }
begin
  Result := False;
  if FHitLimit then
    Result := False
  else if ASuccess and Assigned(FOnData) then
    Result := FOnData(FData.Text);
  FData.Reset;
  FHitLimit := False;
end;

function TTyTerminalOscStringHandler.PayloadLength: Int64;
begin
  Result := FData.Length;
end;

constructor TTyTerminalDcsStringHandler.Create(AOnData: TTyTerminalDcsDataEvent);
begin
  inherited Create;
  FOnData := AOnData;
  FData := TTyLimitedStringBuilder.Create(TyTermParserPayloadLimit);
  FParams := GEmptyParams;
end;

destructor TTyTerminalDcsStringHandler.Destroy;
begin
  DropParams;
  FData.Free;
  inherited Destroy;
end;

procedure TTyTerminalDcsStringHandler.DropParams;
begin
  if FParams <> GEmptyParams then
    FParams.Free;
  FParams := GEmptyParams;
end;

procedure TTyTerminalDcsStringHandler.Hook(AParams: TTyTerminalParams);      { :150-158 }
begin
  DropParams;
  { clone only non-empty params; otherwise stick with the shared [0] }
  if (AParams.Length > 1) or (AParams[0] <> 0) then
    FParams := AParams.Clone;
  FData.Reset;
  FHitLimit := False;
end;

procedure TTyTerminalDcsStringHandler.Put(const AData: array of Cardinal; AStart, AEnd: Integer);
begin
  if FHitLimit then
    Exit;
  if FData.Append(AData, AStart, AEnd) then
    FHitLimit := True;
end;

function TTyTerminalDcsStringHandler.Unhook(ASuccess: Boolean): Boolean;     { :169-190 }
begin
  Result := False;
  if FHitLimit then
    Result := False
  else if ASuccess and Assigned(FOnData) then
    Result := FOnData(FData.Text, FParams);
  DropParams;
  FData.Reset;
  FHitLimit := False;
end;

constructor TTyTerminalApcStringHandler.Create(AOnData: TTyTerminalOscDataEvent);
begin
  inherited Create;
  FOnData := AOnData;
  FData := TTyLimitedStringBuilder.Create(TyTermParserPayloadLimit);
end;

destructor TTyTerminalApcStringHandler.Destroy;
begin
  FData.Free;
  inherited Destroy;
end;

procedure TTyTerminalApcStringHandler.Start;
begin
  FData.Reset;
  FHitLimit := False;
end;

procedure TTyTerminalApcStringHandler.Put(const AData: array of Cardinal; AStart, AEnd: Integer);
begin
  if FHitLimit then
    Exit;
  if FData.Append(AData, AStart, AEnd) then
    FHitLimit := True;
end;

function TTyTerminalApcStringHandler.Finish(ASuccess: Boolean): Boolean;     { :176-195 }
begin
  Result := False;
  if FHitLimit then
    Result := False
  else if ASuccess and Assigned(FOnData) then
    Result := FOnData(FData.Text);
  FData.Reset;
  FHitLimit := False;
end;

{ ---- TTyTermHandlerTable --------------------------------------------------------- }

constructor TTyTermHandlerTable.Create(AOwner: TTyTerminalParser);
begin
  inherited Create;
  FOwner := AOwner;
end;

destructor TTyTermHandlerTable.Destroy;
var
  i, k: Integer;
begin
  for i := 0 to FCount - 1 do
  begin
    for k := 0 to FLists[i].Count - 1 do
      FLists[i].Items[k].Obj.Free;
    FLists[i].Free;
  end;
  inherited Destroy;
end;

function TTyTermHandlerTable.IndexOf(AIdent: Int64; out AIndex: Integer): Boolean;
var
  lo, hi, mid: Integer;
begin
  lo := 0;
  hi := FCount - 1;
  while lo <= hi do
  begin
    mid := (lo + hi) shr 1;
    if FLists[mid].Ident = AIdent then
    begin
      AIndex := mid;
      Exit(True);
    end;
    if FLists[mid].Ident < AIdent then
      lo := mid + 1
    else
      hi := mid - 1;
  end;
  AIndex := lo;
  Result := False;
end;

function TTyTermHandlerTable.Find(AIdent: Int64): TTyTermHandlerList;
var
  i: Integer;
begin
  if IndexOf(AIdent, i) then
    Result := FLists[i]
  else
    Result := nil;
end;

{ handlerList.push(handler) after `this._handlers[ident] ??= []` }
function TTyTermHandlerTable.Add(AIdent: Int64; const AMethod: TMethod; AObj: TObject): Integer;
var
  i, k: Integer;
  list: TTyTermHandlerList;
begin
  if not IndexOf(AIdent, i) then
  begin
    list := TTyTermHandlerList.Create;
    list.Ident := AIdent;
    if FCount = System.Length(FLists) then
      SetLength(FLists, FCount * 2 + 8);
    for k := FCount downto i + 1 do
      FLists[k] := FLists[k - 1];
    FLists[i] := list;
    Inc(FCount);
  end;
  list := FLists[i];
  if list.Count = System.Length(list.Items) then
    SetLength(list.Items, list.Count * 2 + 2);
  Result := FOwner.NewHandle;
  list.Items[list.Count].Handle := Result;
  list.Items[list.Count].Method := AMethod;
  list.Items[list.Count].Obj := AObj;
  Inc(list.Count);
end;

{ dispose(): handlerList.splice(indexOf(handler), 1) -- the chain keeps its place
  in the table even when it becomes empty, as upstream's array does. }
function TTyTermHandlerTable.RemoveHandle(AHandle: Integer): Boolean;
var
  i, k, m: Integer;
  list: TTyTermHandlerList;
  obj: TObject;
begin
  for i := 0 to FCount - 1 do
  begin
    list := FLists[i];
    for k := 0 to list.Count - 1 do
      if list.Items[k].Handle = AHandle then
      begin
        obj := list.Items[k].Obj;
        for m := k to list.Count - 2 do
          list.Items[m] := list.Items[m + 1];
        Dec(list.Count);
        if obj <> nil then
          FOwner.DisposeObject(obj);
        Exit(True);
      end;
  end;
  Result := False;
end;

{ delete this._handlers[ident] }
procedure TTyTermHandlerTable.Clear(AIdent: Int64);
var
  i, k: Integer;
  list: TTyTermHandlerList;
begin
  if not IndexOf(AIdent, i) then
    Exit;
  list := FLists[i];
  for k := i to FCount - 2 do
    FLists[k] := FLists[k + 1];
  Dec(FCount);
  FOwner.DisposeList(list);
end;

{ ---- TTyTermOscParser (OscParser.ts:14-189) -------------------------------------- }

const
  OscStart = 0;
  OscId = 1;
  OscPayload = 2;
  OscAbort = 3;

constructor TTyTermOscParser.Create(AOwner: TTyTerminalParser; ATable: TTyTermHandlerTable);
begin
  inherited Create;
  FOwner := AOwner;
  FTable := ATable;
  FId := -1;
end;

function TTyTermOscParser.ActiveCount: Integer;
begin
  if FActive = nil then
    Result := 0
  else
    Result := FActive.Count;
end;

procedure TTyTermOscParser.Reset;                                            { :52-63 }
var
  j: Integer;
begin
  if FState = OscPayload then
  begin
    j := ActiveCount - 1;
    while j >= 0 do
    begin
      TTyTerminalOscHandler(FActive.Items[j].Obj).Finish(False);
      Dec(j);
    end;
  end;
  FActive := nil;
  FId := -1;
  FState := OscStart;
end;

procedure TTyTermOscParser.DoStart;                                          { :65-74 }
var
  j: Integer;
begin
  { a number beyond Integer (upstream: a float nothing is registered under) has no
    handlers }
  if (FId >= Low(Integer)) and (FId <= High(Integer)) then
    FActive := FTable.Find(FId)
  else
    FActive := nil;
  if ActiveCount = 0 then
  begin
    if Assigned(FFallback) then
      FFallback(FId, tsaStart, '', False);
  end
  else
  begin
    j := ActiveCount - 1;
    while j >= 0 do
    begin
      TTyTerminalOscHandler(FActive.Items[j].Obj).Start;
      Dec(j);
    end;
  end;
end;

procedure TTyTermOscParser.DoPut(const AData: array of Cardinal; AStart, AEnd: Integer);
var
  j: Integer;
begin                                                                        { :76-84 }
  if ActiveCount = 0 then
  begin
    if Assigned(FFallback) then
      FFallback(FId, tsaPut, TyTerminalCodepointsToUtf8(AData, AStart, AEnd), False);
  end
  else
  begin
    j := ActiveCount - 1;
    while j >= 0 do
    begin
      TTyTerminalOscHandler(FActive.Items[j].Obj).Put(AData, AStart, AEnd);
      Dec(j);
    end;
  end;
end;

procedure TTyTermOscParser.Start;                                            { :86-90 }
begin
  Reset;
  FState := OscId;
end;

procedure TTyTermOscParser.Put(const AData: array of Cardinal; AStart, AEnd: Integer);
var
  code: Cardinal;
begin                                                                        { :99-124 }
  if FState = OscAbort then
    Exit;
  if FState = OscId then
  begin
    while AStart < AEnd do
    begin
      code := AData[AStart];
      Inc(AStart);
      if code = $3B then
      begin
        FState := OscPayload;
        DoStart;
        Break;
      end;
      if (code < $30) or (code > $39) then
      begin
        FState := OscAbort;
        Exit;
      end;
      if FId = -1 then
        FId := 0;
      { saturates instead of wrapping (unit header) }
      if FId <= (High(Int64) - 9) div 10 then
        FId := FId * 10 + Int64(code) - 48;
    end;
  end;
  if (FState = OscPayload) and (AEnd - AStart > 0) then
    DoPut(AData, AStart, AEnd);
end;

procedure TTyTermOscParser.Finish(ASuccess: Boolean);                        { :131-188 }
var
  j: Integer;
  handlerResult: Boolean;
begin
  if FState = OscStart then
    Exit;
  if FState <> OscAbort then
  begin
    { still in ID state: no payload, announce START before END }
    if FState = OscId then
      DoStart;
    if ActiveCount = 0 then
    begin
      if Assigned(FFallback) then
        FFallback(FId, tsaEnd, '', ASuccess);
    end
    else
    begin
      j := ActiveCount - 1;
      while j >= 0 do
      begin
        handlerResult := TTyTerminalOscHandler(FActive.Items[j].Obj).Finish(ASuccess);
        if handlerResult then
          Break;
        Dec(j);
      end;
      Dec(j);
      { the rest still get an end, with success false }
      while j >= 0 do
      begin
        TTyTerminalOscHandler(FActive.Items[j].Obj).Finish(False);
        Dec(j);
      end;
    end;
  end;
  FActive := nil;
  FId := -1;
  FState := OscStart;
end;

{ ---- TTyTermDcsParser (DcsParser.ts:15-131) -------------------------------------- }

constructor TTyTermDcsParser.Create(ATable: TTyTermHandlerTable);
begin
  inherited Create;
  FTable := ATable;
end;

function TTyTermDcsParser.ActiveCount: Integer;
begin
  if FActive = nil then
    Result := 0
  else
    Result := FActive.Count;
end;

procedure TTyTermDcsParser.Reset;                                            { :54-64 }
var
  j: Integer;
begin
  if ActiveCount > 0 then
  begin
    j := ActiveCount - 1;
    while j >= 0 do
    begin
      TTyTerminalDcsHandler(FActive.Items[j].Obj).Unhook(False);
      Dec(j);
    end;
  end;
  FActive := nil;
  FIdent := 0;
end;

procedure TTyTermDcsParser.Hook(AIdent: Cardinal; AParams: TTyTerminalParams);
var
  j: Integer;
begin                                                                        { :66-78 }
  Reset;
  FIdent := AIdent;
  FActive := FTable.Find(AIdent);
  if ActiveCount = 0 then
  begin
    if Assigned(FFallback) then
      FFallback(FIdent, tsaStart, AParams, '', False);
  end
  else
  begin
    j := ActiveCount - 1;
    while j >= 0 do
    begin
      TTyTerminalDcsHandler(FActive.Items[j].Obj).Hook(AParams);
      Dec(j);
    end;
  end;
end;

procedure TTyTermDcsParser.Put(const AData: array of Cardinal; AStart, AEnd: Integer);
var
  j: Integer;
begin                                                                        { :80-88 }
  if ActiveCount = 0 then
  begin
    if Assigned(FFallback) then
      FFallback(FIdent, tsaPut, nil, TyTerminalCodepointsToUtf8(AData, AStart, AEnd), False);
  end
  else
  begin
    j := ActiveCount - 1;
    while j >= 0 do
    begin
      TTyTerminalDcsHandler(FActive.Items[j].Obj).Put(AData, AStart, AEnd);
      Dec(j);
    end;
  end;
end;

procedure TTyTermDcsParser.Unhook(ASuccess: Boolean);                        { :90-130 }
var
  j: Integer;
begin
  if ActiveCount = 0 then
  begin
    if Assigned(FFallback) then
      FFallback(FIdent, tsaEnd, nil, '', ASuccess);
  end
  else
  begin
    j := ActiveCount - 1;
    while j >= 0 do
    begin
      if TTyTerminalDcsHandler(FActive.Items[j].Obj).Unhook(ASuccess) then
        Break;
      Dec(j);
    end;
    Dec(j);
    while j >= 0 do
    begin
      TTyTerminalDcsHandler(FActive.Items[j].Obj).Unhook(False);
      Dec(j);
    end;
  end;
  FActive := nil;
  FIdent := 0;
end;

{ ---- TTyTermApcParser (ApcParser.ts:22-148) -------------------------------------- }

constructor TTyTermApcParser.Create(ATable: TTyTermHandlerTable);
begin
  inherited Create;
  FTable := ATable;
end;

function TTyTermApcParser.ActiveCount: Integer;
begin
  if FActive = nil then
    Result := 0
  else
    Result := FActive.Count;
end;

procedure TTyTermApcParser.Reset;                                            { :66-76 }
var
  j: Integer;
begin
  if ActiveCount > 0 then
  begin
    j := ActiveCount - 1;
    while j >= 0 do
    begin
      TTyTerminalApcHandler(FActive.Items[j].Obj).Finish(False);
      Dec(j);
    end;
  end;
  FActive := nil;
  FIdent := 0;
end;

procedure TTyTermApcParser.Start(AIdent: Cardinal);                          { :78-90 }
var
  j: Integer;
begin
  Reset;
  FIdent := AIdent;
  FActive := FTable.Find(AIdent);
  if ActiveCount = 0 then
  begin
    if Assigned(FFallback) then
      FFallback(FIdent, tsaStart, '', False);
  end
  else
  begin
    j := ActiveCount - 1;
    while j >= 0 do
    begin
      TTyTerminalApcHandler(FActive.Items[j].Obj).Start;
      Dec(j);
    end;
  end;
end;

procedure TTyTermApcParser.Put(const AData: array of Cardinal; AStart, AEnd: Integer);
var
  j: Integer;
begin                                                                        { :92-100 }
  if ActiveCount = 0 then
  begin
    if Assigned(FFallback) then
      FFallback(FIdent, tsaPut, TyTerminalCodepointsToUtf8(AData, AStart, AEnd), False);
  end
  else
  begin
    j := ActiveCount - 1;
    while j >= 0 do
    begin
      TTyTerminalApcHandler(FActive.Items[j].Obj).Put(AData, AStart, AEnd);
      Dec(j);
    end;
  end;
end;

procedure TTyTermApcParser.Finish(ASuccess: Boolean);                        { :107-147 }
var
  j: Integer;
begin
  if ActiveCount = 0 then
  begin
    if Assigned(FFallback) then
      FFallback(FIdent, tsaEnd, '', ASuccess);
  end
  else
  begin
    j := ActiveCount - 1;
    while j >= 0 do
    begin
      if TTyTerminalApcHandler(FActive.Items[j].Obj).Finish(ASuccess) then
        Break;
      Dec(j);
    end;
    Dec(j);
    while j >= 0 do
    begin
      TTyTerminalApcHandler(FActive.Items[j].Obj).Finish(False);
      Dec(j);
    end;
  end;
  FActive := nil;
  FIdent := 0;
end;

{ ---- TTyTerminalParser ------------------------------------------------------------ }

constructor TTyTerminalParser.Create;                                        { :300-336 }
var
  swallow: TTyTerminalEscEvent;
begin
  inherited Create;
  FCurrentState := tpsGround;
  FParams := TTyTerminalParams.Create;
  FParams.AddParam(0);                   { ZDM }
  FCollect := 0;
  FPrecedingJoinState := 0;
  FCsi := TTyTermHandlerTable.Create(Self);
  FEsc := TTyTermHandlerTable.Create(Self);
  FOscTable := TTyTermHandlerTable.Create(Self);
  FDcsTable := TTyTermHandlerTable.Create(Self);
  FApcTable := TTyTermHandlerTable.Create(Self);
  FOsc := TTyTermOscParser.Create(Self, FOscTable);
  FDcs := TTyTermDcsParser.Create(FDcsTable);
  FApc := TTyTermApcParser.Create(FApcTable);
  FDeadObjects := TFPList.Create;
  FDeadLists := TFPList.Create;
  { swallow 7bit ST (ESC \) -- takes a handle like any registration }
  swallow := @SwallowSt;
  FEsc.Add(IdentOf(TyTerminalFunctionId('', '', '\'), $30, $7E), TMethod(swallow), nil);
end;

destructor TTyTerminalParser.Destroy;
var
  i, k: Integer;
  list: TTyTermHandlerList;
begin
  FOsc.Free;
  FDcs.Free;
  FApc.Free;
  FCsi.Free;
  FEsc.Free;
  FOscTable.Free;
  FDcsTable.Free;
  FApcTable.Free;
  for i := 0 to FDeadObjects.Count - 1 do
    TObject(FDeadObjects[i]).Free;
  FDeadObjects.Free;
  for i := 0 to FDeadLists.Count - 1 do
  begin
    list := TTyTermHandlerList(FDeadLists[i]);
    for k := 0 to list.Count - 1 do
      list.Items[k].Obj.Free;
    list.Free;
  end;
  FDeadLists.Free;
  FParams.Free;
  inherited Destroy;
end;

function TTyTerminalParser.SwallowSt: Boolean;
begin
  Result := True;
end;

function TTyTerminalParser.NewHandle: Integer;
begin
  Inc(FNextHandle);
  Result := FNextHandle;
end;

{ A handler object leaves the parser. Freed at once, unless a parse is running: it
  may be the very handler that asked, so it waits for the parse to finish. }
procedure TTyTerminalParser.DisposeObject(AObj: TObject);
begin
  if FDispatchDepth > 0 then
    FDeadObjects.Add(AObj)
  else
    AObj.Free;
end;

{ A cleared chain. A sub-parser in the middle of a sequence still holds it (upstream
  keeps using the orphaned array), so such a chain lives until the parser goes. }
procedure TTyTerminalParser.DisposeList(AList: TTyTermHandlerList);
var
  k: Integer;
begin
  if (FDispatchDepth > 0) or (AList = FOsc.FActive) or (AList = FDcs.FActive)
    or (AList = FApc.FActive) then
  begin
    FDeadLists.Add(AList);
    Exit;
  end;
  for k := 0 to AList.Count - 1 do
    AList.Items[k].Obj.Free;
  AList.Free;
end;

{ _identifier, :338-373; the messages are upstream's }
function TTyTerminalParser.IdentOf(const AId: TTyTerminalFunctionId; AFinalLo, AFinalHi: Integer;
  AUsePrefix: Boolean): Cardinal;
var
  res: Cardinal;
  i, c: Integer;
begin
  res := 0;
  if AUsePrefix and (AId.Prefix <> '') then
  begin
    if System.Length(AId.Prefix) > 1 then
      raise EArgumentException.Create('only one byte as prefix supported');
    res := Ord(AId.Prefix[1]);
    if (res < $3C) or (res > $3F) then
      raise EArgumentException.Create('prefix must be in range 0x3c .. 0x3f');
  end;
  if AId.Intermediates <> '' then
  begin
    if System.Length(AId.Intermediates) > 2 then
      raise EArgumentException.Create('only two bytes as intermediates are supported');
    for i := 1 to System.Length(AId.Intermediates) do
    begin
      c := Ord(AId.Intermediates[i]);
      if ($20 > c) or (c > $2F) then
        raise EArgumentException.Create('intermediate must be in range 0x20 .. 0x2f');
      res := (res shl 8) or Cardinal(c);
    end;
  end;
  c := Ord(AId.Final);
  if (AFinalLo > c) or (c > AFinalHi) then
    raise EArgumentException.CreateFmt('final must be in range %d .. %d', [AFinalLo, AFinalHi]);
  res := (res shl 8) or Cardinal(c);
  Result := res;
end;

function TTyTerminalParser.IdentToString(AIdent: Cardinal): string;          { :375-382 }
begin
  Result := '';
  while AIdent <> 0 do
  begin
    Result := Chr(AIdent and $FF) + Result;
    AIdent := AIdent shr 8;
  end;
end;

procedure TTyTerminalParser.SetPrintHandler(AHandler: TTyTerminalPrintEvent);
begin
  FPrintHandler := AHandler;
end;

procedure TTyTerminalParser.ClearPrintHandler;
begin
  FPrintHandler := nil;
end;

procedure TTyTerminalParser.SetExecuteHandler(ACode: Byte; AHandler: TTyTerminalExecuteEvent);
begin
  FExecHandlers[ACode] := AHandler;
end;

procedure TTyTerminalParser.ClearExecuteHandler(ACode: Byte);
begin
  FExecHandlers[ACode] := nil;
end;

procedure TTyTerminalParser.SetExecuteHandlerFallback(AHandler: TTyTerminalExecuteFallback);
begin
  FExecFallback := AHandler;
end;

function TTyTerminalParser.RegisterCsiHandler(const AId: TTyTerminalFunctionId;
  AHandler: TTyTerminalCsiEvent): Integer;
begin
  Result := FCsi.Add(IdentOf(AId, $40, $7E), TMethod(AHandler), nil);
end;

procedure TTyTerminalParser.ClearCsiHandler(const AId: TTyTerminalFunctionId);
begin
  FCsi.Clear(IdentOf(AId, $40, $7E));
end;

procedure TTyTerminalParser.SetCsiHandlerFallback(AHandler: TTyTerminalCsiFallback);
begin
  FCsiFallback := AHandler;
end;

function TTyTerminalParser.RegisterEscHandler(const AId: TTyTerminalFunctionId;
  AHandler: TTyTerminalEscEvent): Integer;
begin
  Result := FEsc.Add(IdentOf(AId, $30, $7E), TMethod(AHandler), nil);
end;

procedure TTyTerminalParser.ClearEscHandler(const AId: TTyTerminalFunctionId);
begin
  FEsc.Clear(IdentOf(AId, $30, $7E));
end;

procedure TTyTerminalParser.SetEscHandlerFallback(AHandler: TTyTerminalEscFallback);
begin
  FEscFallback := AHandler;
end;

function TTyTerminalParser.RegisterOscHandler(AIdent: Integer; AHandler: TTyTerminalOscHandler): Integer;
var
  m: TMethod;
begin
  m.Code := nil;
  m.Data := nil;
  Result := FOscTable.Add(AIdent, m, AHandler);
end;

procedure TTyTerminalParser.ClearOscHandler(AIdent: Integer);
begin
  FOscTable.Clear(AIdent);
end;

procedure TTyTerminalParser.SetOscHandlerFallback(AHandler: TTyTerminalOscFallback);
begin
  FOsc.FFallback := AHandler;
end;

function TTyTerminalParser.RegisterDcsHandler(const AId: TTyTerminalFunctionId;
  AHandler: TTyTerminalDcsHandler): Integer;
var
  m: TMethod;
begin
  m.Code := nil;
  m.Data := nil;
  Result := FDcsTable.Add(IdentOf(AId, $40, $7E), m, AHandler);
end;

procedure TTyTerminalParser.ClearDcsHandler(const AId: TTyTerminalFunctionId);
begin
  FDcsTable.Clear(IdentOf(AId, $40, $7E));
end;

procedure TTyTerminalParser.SetDcsHandlerFallback(AHandler: TTyTerminalDcsFallback);
begin
  FDcs.FFallback := AHandler;
end;

function TTyTerminalParser.RegisterApcHandler(const AId: TTyTerminalFunctionId;
  AHandler: TTyTerminalApcHandler): Integer;
var
  m: TMethod;
begin
  m.Code := nil;
  m.Data := nil;
  Result := FApcTable.Add(IdentOf(AId, $30, $7E, False), m, AHandler);
end;

procedure TTyTerminalParser.ClearApcHandler(const AId: TTyTerminalFunctionId);
begin
  FApcTable.Clear(IdentOf(AId, $30, $7E, False));
end;

procedure TTyTerminalParser.SetApcHandlerFallback(AHandler: TTyTerminalApcFallback);
begin
  FApc.FFallback := AHandler;
end;

procedure TTyTerminalParser.SetErrorHandler(AHandler: TTyTerminalErrorEvent);
begin
  FErrorHandler := AHandler;
end;

procedure TTyTerminalParser.ClearErrorHandler;
begin
  FErrorHandler := nil;
end;

procedure TTyTerminalParser.Unregister(AHandle: Integer);
begin
  if FCsi.RemoveHandle(AHandle) then Exit;
  if FEsc.RemoveHandle(AHandle) then Exit;
  if FOscTable.RemoveHandle(AHandle) then Exit;
  if FDcsTable.RemoveHandle(AHandle) then Exit;
  FApcTable.RemoveHandle(AHandle);
end;

procedure TTyTerminalParser.Reset;                                           { :495-510 }
begin
  FCurrentState := tpsGround;
  FOsc.Reset;
  FDcs.Reset;
  FApc.Reset;
  FParams.ResetZdm;
  FCollect := 0;
  FPrecedingJoinState := 0;
end;

function TTyTerminalParser.GetOscPayloadLength: Int64;
var
  k: Integer;
begin
  Result := 0;
  if FOsc.FActive = nil then
    Exit;
  for k := 0 to FOsc.FActive.Count - 1 do
    if FOsc.FActive.Items[k].Obj is TTyTerminalOscStringHandler then
      Exit(TTyTerminalOscStringHandler(FOsc.FActive.Items[k].Obj).PayloadLength);
end;

{ the CSI chain: last registered first, stop at the first True, else the fallback }
procedure TTyTerminalParser.DispatchCsi(AIdent: Cardinal);
var
  list: TTyTermHandlerList;
  j: Integer;
begin
  list := FCsi.Find(AIdent);
  if list = nil then
    j := -1
  else
    j := list.Count - 1;
  while j >= 0 do
  begin
    if TTyTerminalCsiEvent(list.Items[j].Method)(FParams) then
      Break;
    Dec(j);
  end;
  if (j < 0) and Assigned(FCsiFallback) then
    FCsiFallback(AIdent, FParams);
end;

procedure TTyTerminalParser.DispatchEsc(AIdent: Cardinal);
var
  list: TTyTermHandlerList;
  j: Integer;
begin
  list := FEsc.Find(AIdent);
  if list = nil then
    j := -1
  else
    j := list.Count - 1;
  while j >= 0 do
  begin
    if TTyTerminalEscEvent(list.Items[j].Method)() then
      Break;
    Dec(j);
  end;
  if (j < 0) and Assigned(FEscFallback) then
    FEscFallback(AIdent);
end;

{ parse, :574-933, without the async resume (_parseStack) and promise branches. }
procedure TTyTerminalParser.Parse(const AData: array of Cardinal; ALength: Integer);

  { 0x20 (SP) included, 0x7F (DEL) excluded, non-ASCII printable }
  function Printable(ACode: Cardinal): Boolean; inline;
  begin
    Result := (ACode >= $20) and ((ACode <= $7E) or (ACode >= NonAsciiPrintable));
  end;

var
  i, k, c, l4, j: Integer;
  code, ch: Cardinal;
  transition: Word;
  csiDone: Boolean;
  st: TTyTermParsingState;
begin
  Inc(FDispatchDepth);
  try
    i := 0;
    while i < ALength do
    begin
      code := AData[i];

      { EXE fast-path: control bytes 0x00-0x17 in non-payload states (:687-692) }
      if (code < $18) and (FCurrentState <= tpsCsiIgnore) then
      begin
        if Assigned(FExecHandlers[code]) then
          FExecHandlers[code]()
        else if Assigned(FExecFallback) then
          FExecFallback(code);
        FPrecedingJoinState := 0;
        Inc(i);
        Continue;
      end;

      { CSI fast-path: ESC [ params final in one tight loop (:694-746) }
      if (code = $1B) and (FCurrentState < tpsOscString) and (i + 2 < ALength)
        and (AData[i + 1] = $5B) then
      begin
        FParams.ResetZdm;
        FCollect := 0;
        k := i + 2;
        ch := AData[k];
        if (ch >= $3C) and (ch <= $3F) then
        begin
          FCollect := ch;
          Inc(k);
        end;
        csiDone := False;
        while k < ALength do
        begin
          ch := AData[k];
          if (ch >= $30) and (ch <= $39) then
            FParams.AddDigit(ch - 48)
          else if ch = $3B then
            FParams.AddParam(0)
          else if ch = $3A then
            FParams.AddSubParam(-1)
          else if (ch >= $40) and (ch <= $7E) then
          begin
            DispatchCsi((FCollect shl 8) or ch);
            FPrecedingJoinState := 0;
            i := k;
            FCurrentState := tpsGround;
            csiDone := True;
            Break;
          end
          else
            Break;
          Inc(k);
        end;
        if not csiDone then
        begin
          i := k - 1;
          FCurrentState := tpsCsiParam;
        end;
        Inc(i);
        Continue;
      end;

      { normal transition and action lookup }
      if code < NonAsciiPrintable then
        transition := GTransitions[(Ord(FCurrentState) shl 8) or code]
      else
        transition := GTransitions[(Ord(FCurrentState) shl 8) or NonAsciiPrintable];
      case TTyTermParserAction(transition shr 8) of
        tpaPrint:
          begin
            { the four-at-a-time read-ahead of :756-768, increments where upstream
              has them so the stopping index is the same }
            c := i;
            l4 := ALength - 4;
            while c < l4 do
            begin
              Inc(c);
              if not Printable(AData[c]) then Break;
              Inc(c);
              if not Printable(AData[c]) then Break;
              Inc(c);
              if not Printable(AData[c]) then Break;
              Inc(c);
              if not Printable(AData[c]) then Break;
            end;
            if c >= l4 then
              while (c < ALength) and Printable(AData[c]) do
                Inc(c);
            if Assigned(FPrintHandler) then
              FPrintHandler(AData, i, c);
            i := c - 1;
          end;
        tpaExecute:
          begin
            if Assigned(FExecHandlers[code]) then
              FExecHandlers[code]()
            else if Assigned(FExecFallback) then
              FExecFallback(code);
            FPrecedingJoinState := 0;
          end;
        tpaIgnore: ;
        tpaError:
          begin
            st.Position := i;
            st.Code := code;
            st.CurrentState := FCurrentState;
            st.Collect := FCollect;
            st.Abort := False;
            if Assigned(FErrorHandler) then
              FErrorHandler(st);
            if st.Abort then
              Exit;
          end;
        tpaCsiDispatch:
          begin
            DispatchCsi((FCollect shl 8) or code);
            FPrecedingJoinState := 0;
          end;
        tpaParam:
          begin
            { digits, ; and : in one loop (:812-827) }
            repeat
              case code of
                $3B: FParams.AddParam(0);
                $3A: FParams.AddSubParam(-1);
              else
                FParams.AddDigit(code - 48);
              end;
              Inc(i);
              if i >= ALength then
                Break;
              code := AData[i];
            until not ((code > $2F) and (code < $3C));
            Dec(i);
          end;
        tpaCollect:
          FCollect := (FCollect shl 8) or code;
        tpaEscDispatch:
          begin
            DispatchEsc((FCollect shl 8) or code);
            FPrecedingJoinState := 0;
          end;
        tpaClear:
          begin
            FParams.ResetZdm;
            FCollect := 0;
          end;
        tpaDcsHook:
          FDcs.Hook((FCollect shl 8) or code, FParams);
        tpaDcsPut:
          begin
            { exits on 0x18, 0x1a, 0x1b and 0x80-0x9f; 0x7f stays in (:858-868) }
            j := i + 1;
            while True do
            begin
              if j < ALength then
                code := AData[j];
              if (j >= ALength) or (code = $18) or (code = $1A) or (code = $1B)
                or ((code > $7F) and (code < NonAsciiPrintable)) then
              begin
                FDcs.Put(AData, i, j);
                i := j - 1;
                Break;
              end;
              Inc(j);
            end;
          end;
        tpaDcsUnhook:
          begin
            FDcs.Unhook((code <> $18) and (code <> $1A));
            if code = $1B then
              transition := transition or Ord(tpsEscape);
            FParams.ResetZdm;
            FCollect := 0;
            FPrecedingJoinState := 0;
          end;
        tpaOscStart:
          FOsc.Start;
        tpaOscPut:
          begin
            { 0x20 (SP) and 0x7F (DEL) included (:883-892) }
            j := i + 1;
            while True do
            begin
              if (j >= ALength) or (AData[j] < $20)
                or ((AData[j] > $7F) and (AData[j] < NonAsciiPrintable)) then
              begin
                FOsc.Put(AData, i, j);
                i := j - 1;
                Break;
              end;
              Inc(j);
            end;
          end;
        tpaOscEnd:
          begin
            FOsc.Finish((code <> $18) and (code <> $1A));
            if code = $1B then
              transition := transition or Ord(tpsEscape);
            FParams.ResetZdm;
            FCollect := 0;
            FPrecedingJoinState := 0;
          end;
        tpaApcStart:
          FApc.Start((FCollect shl 8) or code);
        tpaApcPut:
          begin
            { allowed: 0x08-0x0d, 0x20-0x7e and non-ASCII (:907-918) }
            j := i + 1;
            while True do
            begin
              if (j < ALength) and (((AData[j] >= $20) and (AData[j] < $7F))
                or ((AData[j] >= $08) and (AData[j] < $0E)) or (AData[j] >= NonAsciiPrintable)) then
              begin
                Inc(j);
                Continue;
              end;
              FApc.Put(AData, i, j);
              i := j - 1;
              Break;
            end;
          end;
        tpaApcEnd:
          begin
            FApc.Finish((code <> $18) and (code <> $1A));
            if code = $1B then
              transition := transition or Ord(tpsEscape);
            FParams.ResetZdm;
            FCollect := 0;
            FPrecedingJoinState := 0;
          end;
      end;
      FCurrentState := TTyTermParserState(transition and $FF);
      Inc(i);
    end;
  finally
    Dec(FDispatchDepth);
    if (FDispatchDepth = 0) and (FDeadObjects.Count > 0) then
    begin
      for i := 0 to FDeadObjects.Count - 1 do
        TObject(FDeadObjects[i]).Free;
      FDeadObjects.Clear;
    end;
  end;
end;

initialization
  BuildTransitions;
  GEmptyParams := TTyTerminalParams.Create;
  GEmptyParams.AddParam(0);

finalization
  GEmptyParams.Free;

end.
