unit tyControls.AdvChart.TextPatch;
{$mode objfpc}{$H+}
{ Writing an edited option tree back into the TEXT it was read from,
  changing only what changed. [Batch 143]

  THE PROBLEM. The design-time series editor works on a parsed tree, and a
  parsed tree has lost everything the reader threw away: comments, the order
  the author put the keys in only survives because fcl-json keeps it, the
  quoting, the indentation, the trailing commas. Re-emitting the whole tree
  -- what the Format button does, after asking -- would turn a user's
  hand-written option into somebody else's file the first time they renamed
  a series. So the editor does not re-emit; it PATCHES:

    - a value whose new tree is the same as its old one keeps its original
      text, byte for byte, comments inside it and all;
    - an object keeps every member that survived where it was, patches the
      values that changed, cuts the members that were removed together with
      their separator, and appends the new ones after the last survivor in
      the object's own layout;
    - an array keeps its common head and tail, patches elements in place when
      the count did not change, and otherwise rewrites only the middle --
      reusing, verbatim, the text of any old element the new middle still
      contains (a moved series keeps its comments);
    - anything else -- a scalar that changed, a container whose kind changed,
      an empty container that gained children -- is written fresh, in a style
      read off the document (quote character, bare or quoted keys, indent
      unit, line ending, the spacing after a colon).

  WHAT IS LOST, AND SAYING SO. A comment can only be lost where text was
  written fresh: inside a replaced value, or between the elements of a
  rewritten array middle. Those are counted (Lost), so the dialog can ask
  before it overwrites anything. Comments inside members or elements the
  user deleted are not counted: deleting the thing deletes what was said
  about it.

  THE MAP. A second, tolerant scanner over the text records where every
  value starts and ends, where every member's key is, and where its comma
  is. It runs only over text the option reader already accepted, and it is
  then CHECKED against the parsed tree -- same kinds, same counts, same key
  names in the same order. Where the two disagree (an escape spelled in a way
  the scanner decodes differently, say) the map is dropped, Mapped is False,
  and Patch re-emits the whole document with every comment counted lost: the
  dialog says so. Correct output first, faithful output where provably safe.

  THE INVARIANT the tests hold every patch to: the output, read by the option
  reader, is the same tree as the one patched in (TyOptJsonSame).

  LCL-free: SysUtils, Classes and fcl-json only (plus the port's own JS
  number formatting, so a float is spelled the way ECharts would print it). }
interface
uses SysUtils, Classes, fpjson;

type
  { How the document writes things, so text written fresh looks like it
    belongs there. }
  TTyOptTextStyle = record
    { '"' or ''''. }
    Quote: Char;
    { Write a key bare when it is an identifier. }
    BareKeys: Boolean;
    { One level of indentation. }
    Indent: string;
    { #10 or #13#10. }
    EOL: string;
    { What sits between a key and its value: ': ' or ':'. }
    Colon: string;
  end;

  TTyOptSpanKind = (oskScalar, oskObject, oskArray);

  { One replacement of [StartPos, StopPos) by Text; an empty range inserts. }
  TTyOptTextEdit = record
    StartPos, StopPos: Integer;
    Text: string;
  end;
  TTyOptTextEditList = record
    Items: array of TTyOptTextEdit;
    Count: Integer;
  end;

  { One value in the text: [StartPos, EndPos), 1-based, EndPos exclusive. A
    container's members or elements are Items[FirstItem .. +ItemCount-1]. }
  TTyOptSpan = record
    Kind: TTyOptSpanKind;
    StartPos, EndPos: Integer;
    FirstItem, ItemCount: Integer;
  end;

  { A member of an object (KeyStart > 0) or an element of an array. }
  TTyOptSpanItem = record
    KeyStart, KeyEnd: Integer;
    Name: string;
    Value: Integer;
    { The comma after the value, 0 when there is none. }
    CommaPos: Integer;
  end;

  TTyOptTextPatcher = class
  private
    FText: string;
    FOriginal: TJSONData;
    FSpans: array of TTyOptSpan;
    FSpanCount: Integer;
    FItems: array of TTyOptSpanItem;
    FItemCount: Integer;
    FComments: array of Integer;
    FCommentCount: Integer;
    FRoot: Integer;
    FMapped: Boolean;
    FStyle: TTyOptTextStyle;
    FLost: Integer;
    FHintArray: TJSONData;
    FHintOrigins: array of Integer;
    { the scanner }
    FPos: Integer;
    function Scan: Boolean;
    function ScanValue(out AIndex: Integer): Boolean;
    procedure SkipBlank;
    function ScanString: Boolean;
    function ScanWord: Boolean;
    function NewSpan(AKind: TTyOptSpanKind; AStart: Integer): Integer;
    function Corresponds(ASpan: Integer; AData: TJSONData): Boolean;
    procedure ReadStyle;
    { layout helpers }
    function LineStartOf(APos: Integer): Integer;
    function IndentOfLine(APos: Integer): string;
    function IsLineLead(APos: Integer): Boolean;
    function HasBreak(AFrom, ATo: Integer): Boolean;
    function CommentsIn(AFrom, ATo: Integer): Integer;
    function PastLineComment(APos: Integer): Integer;
    function SpanText(ASpan: Integer): string;
    function ItemIndent(ASpan: Integer): string;
    function IsMultiLine(ASpan: Integer): Boolean;
    function InlineSep(ASpan: Integer): string;
    { the patch }
    function PatchValue(ASpan: Integer; AOld, ANew: TJSONData): string;
    function PatchObject(ASpan: Integer; AOld, ANew: TJSONObject): string;
    function PatchArray(ASpan: Integer; AOld, ANew: TJSONArray): string;
    procedure CutItems(ASpan, AFirst, ALast: Integer; AKeepComma: Boolean;
      var AEdits: TTyOptTextEditList);
    function KeyText(const AName: string): string;
  public
    { AOriginal is the tree the option reader made of AText; it is not owned
      and must outlive the patcher. }
    constructor Create(const AText: string; AOriginal: TJSONData);
    { The text with ANew patched in. Lost says how many comments the result
      no longer has that it would have kept had nothing changed. }
    function Patch(ANew: TJSONData): string;
    { THE IDENTITY of one array's elements, for the next Patch: element i of
      ANewArray (a node of the tree handed to Patch) was element AOrigins[i]
      of the original array at the same place, -1 when it is new. Without it
      an array's elements are matched by position and by equality. }
    procedure SetArrayHint(ANewArray: TJSONData; const AOrigins: array of Integer);
    { False when the text could not be mapped onto the tree -- Patch then
      re-emits the whole document. }
    property Mapped: Boolean read FMapped;
    property Lost: Integer read FLost;
    property Style: TTyOptTextStyle read FStyle;
    { Every comment in the text. }
    property CommentCount: Integer read FCommentCount;
  end;

{ Deep equality as the option means it: numbers by value (1 and 1.0 are the
  same), objects by their members whatever the order, arrays in order. }
function TyOptJsonSame(A, B: TJSONData): Boolean;

{ AData written as option text in AStyle. AIndentNow is the indentation of
  the line it starts on; AMultiLine forces a container onto several lines
  (otherwise a container that fits in 80 columns stays on one). }
function TyOptJsonLiteral(AData: TJSONData; const AStyle: TTyOptTextStyle;
  const AIndentNow: string; AMultiLine: Boolean): string;

{ AData on one line, whatever its length -- a grid cell's spelling of a value
  that is not a plain number or string. }
function TyOptJsonCompact(AData: TJSONData; const AStyle: TTyOptTextStyle): string;

{ The style for a document with nothing to read one off: the spelling the
  option editor's own completions insert -- bare keys, single quotes, two
  spaces. }
function TyOptDefaultTextStyle: TTyOptTextStyle;

{ A JSON string literal in AQuote. }
function TyOptQuoteString(const S: string; AQuote: Char): string;

implementation

uses tyControls.AdvChart.Scale;

const
  cWidth = 80;
  { Above this many old x new elements an array middle is not searched for
    moved elements: a large data array edited by the grid is patched in place
    or by position, and a quadratic search there would be paid per keystroke. }
  cMatchCap = 4096;

procedure AddEdit(var L: TTyOptTextEditList; AStart, AStop: Integer; const AText: string);
begin
  if L.Count = Length(L.Items) then SetLength(L.Items, 8 + L.Count * 2);
  L.Items[L.Count].StartPos := AStart;
  L.Items[L.Count].StopPos := AStop;
  L.Items[L.Count].Text := AText;
  Inc(L.Count);
end;

{ By start, and at one start an insertion (empty range) before a cut: an
  insertion at the place a cut begins belongs in front of what is cut. }
procedure SortEdits(var L: TTyOptTextEditList);
var
  i, j: Integer;
  t: TTyOptTextEdit;
begin
  for i := 1 to L.Count - 1 do
  begin
    t := L.Items[i];
    j := i - 1;
    while (j >= 0) and ((L.Items[j].StartPos > t.StartPos) or
      ((L.Items[j].StartPos = t.StartPos) and
       (L.Items[j].StopPos - L.Items[j].StartPos > t.StopPos - t.StartPos))) do
    begin
      L.Items[j + 1] := L.Items[j];
      Dec(j);
    end;
    L.Items[j + 1] := t;
  end;
end;

{ ---- equality --------------------------------------------------------- }

function TyOptJsonSame(A, B: TJSONData): Boolean;
var
  i: Integer;
  other: TJSONData;
begin
  if A = B then Exit(True);
  if (A = nil) or (B = nil) then Exit(False);
  if A.JSONType <> B.JSONType then Exit(False);
  case A.JSONType of
    jtNull: Result := True;
    jtBoolean: Result := A.AsBoolean = B.AsBoolean;
    jtString: Result := A.AsString = B.AsString;
    jtNumber:
      if (TJSONNumber(A).NumberType <> ntFloat)
        and (TJSONNumber(B).NumberType <> ntFloat)
        and (TJSONNumber(A).NumberType <> ntQWord)
        and (TJSONNumber(B).NumberType <> ntQWord) then
        Result := A.AsInt64 = B.AsInt64
      else
        Result := A.AsFloat = B.AsFloat;
    jtArray:
      begin
        if A.Count <> B.Count then Exit(False);
        for i := 0 to A.Count - 1 do
          if not TyOptJsonSame(A.Items[i], B.Items[i]) then Exit(False);
        Result := True;
      end;
    jtObject:
      begin
        if A.Count <> B.Count then Exit(False);
        for i := 0 to A.Count - 1 do
        begin
          other := TJSONObject(B).Find(TJSONObject(A).Names[i]);
          if (other = nil) or not TyOptJsonSame(A.Items[i], other) then
            Exit(False);
        end;
        Result := True;
      end;
  else
    Result := False;
  end;
end;

{ ---- writing ----------------------------------------------------------- }

function TyOptDefaultTextStyle: TTyOptTextStyle;
begin
  Result.Quote := '''';
  Result.BareKeys := True;
  Result.Indent := '  ';
  Result.EOL := #10;
  Result.Colon := ': ';
end;

function TyOptQuoteString(const S: string; AQuote: Char): string;
var
  i: Integer;
  c: Char;
begin
  Result := AQuote;
  for i := 1 to Length(S) do
  begin
    c := S[i];
    if c = AQuote then Result := Result + '\' + c
    else if c = '\' then Result := Result + '\\'
    else if c = #8 then Result := Result + '\b'
    else if c = #9 then Result := Result + '\t'
    else if c = #10 then Result := Result + '\n'
    else if c = #12 then Result := Result + '\f'
    else if c = #13 then Result := Result + '\r'
    else if c < #32 then Result := Result + '\u' + IntToHex(Ord(c), 4)
    else Result := Result + c;
  end;
  Result := Result + AQuote;
end;

function IsIdentName(const S: string): Boolean;
var i: Integer;
begin
  { fcl-json's identifier: a letter or '_', then letters, digits, '_' -- and
    not one of the three words it reads as values. }
  Result := (S <> '') and (S[1] in ['A'..'Z', 'a'..'z', '_']);
  if not Result then Exit;
  for i := 2 to Length(S) do
    if not (S[i] in ['A'..'Z', 'a'..'z', '0'..'9', '_']) then Exit(False);
  if SameText(S, 'true') or SameText(S, 'false') or SameText(S, 'null') then
    Result := False;
end;

function KeyIn(const AName: string; const AStyle: TTyOptTextStyle): string;
begin
  if AStyle.BareKeys and IsIdentName(AName) then Result := AName
  else Result := TyOptQuoteString(AName, AStyle.Quote);
end;

function NumberText(AData: TJSONData): string;
var f: Double;
begin
  if TJSONNumber(AData).NumberType = ntFloat then
  begin
    f := AData.AsFloat;
    { Not JSON, and not something the reader could have produced. }
    if (f <> f) or (f - f <> 0) then Exit('null');
    Result := TyJsNumberToString(f);
  end
  else
    Result := AData.AsString;
end;

function ScalarText(AData: TJSONData; const AStyle: TTyOptTextStyle): string;
begin
  case AData.JSONType of
    jtNull: Result := 'null';
    jtBoolean: if AData.AsBoolean then Result := 'true' else Result := 'false';
    jtNumber: Result := NumberText(AData);
    jtString: Result := TyOptQuoteString(AData.AsString, AStyle.Quote);
  else
    Result := 'null';
  end;
end;

function CompactLiteral(AData: TJSONData; const AStyle: TTyOptTextStyle): string;
var i: Integer;
begin
  case AData.JSONType of
    jtObject:
      begin
        if AData.Count = 0 then Exit('{}');
        Result := '{ ';
        for i := 0 to AData.Count - 1 do
        begin
          if i > 0 then Result := Result + ', ';
          Result := Result + KeyIn(TJSONObject(AData).Names[i], AStyle)
            + AStyle.Colon + CompactLiteral(AData.Items[i], AStyle);
        end;
        Result := Result + ' }';
      end;
    jtArray:
      begin
        Result := '[';
        for i := 0 to AData.Count - 1 do
        begin
          if i > 0 then Result := Result + ', ';
          Result := Result + CompactLiteral(AData.Items[i], AStyle);
        end;
        Result := Result + ']';
      end;
  else
    Result := ScalarText(AData, AStyle);
  end;
end;

function TyOptJsonCompact(AData: TJSONData; const AStyle: TTyOptTextStyle): string;
begin
  if AData = nil then Exit('null');
  Result := CompactLiteral(AData, AStyle);
end;

function TyOptJsonLiteral(AData: TJSONData; const AStyle: TTyOptTextStyle;
  const AIndentNow: string; AMultiLine: Boolean): string;
var
  i, lineLen: Integer;
  inner, piece, compact: string;
  allScalar: Boolean;
begin
  if AData = nil then Exit('null');
  if not (AData.JSONType in [jtObject, jtArray]) then
    Exit(ScalarText(AData, AStyle));
  if AData.Count = 0 then
  begin
    if AData.JSONType = jtObject then Exit('{}') else Exit('[]');
  end;
  compact := CompactLiteral(AData, AStyle);
  if (not AMultiLine) and (Length(AIndentNow) + Length(compact) <= cWidth) then
    Exit(compact);

  inner := AIndentNow + AStyle.Indent;
  if AData.JSONType = jtObject then
  begin
    Result := '{';
    for i := 0 to AData.Count - 1 do
    begin
      if i > 0 then Result := Result + ',';
      Result := Result + AStyle.EOL + inner
        + KeyIn(TJSONObject(AData).Names[i], AStyle) + AStyle.Colon
        + TyOptJsonLiteral(AData.Items[i], AStyle, inner, False);
    end;
    Exit(Result + AStyle.EOL + AIndentNow + '}');
  end;

  allScalar := True;
  for i := 0 to AData.Count - 1 do
    if AData.Items[i].JSONType in [jtObject, jtArray] then
    begin
      allScalar := False;
      Break;
    end;

  Result := '[';
  if allScalar then
  begin
    { Scalars wrapped to the width, not one per line: a hundred values one
      per line is a hundred lines of nothing to read. }
    Result := Result + AStyle.EOL + inner;
    lineLen := Length(inner);
    for i := 0 to AData.Count - 1 do
    begin
      piece := ScalarText(AData.Items[i], AStyle);
      if i > 0 then
      begin
        if lineLen + 2 + Length(piece) > cWidth then
        begin
          Result := Result + ',' + AStyle.EOL + inner;
          lineLen := Length(inner);
        end
        else
        begin
          Result := Result + ', ';
          Inc(lineLen, 2);
        end;
      end;
      Result := Result + piece;
      Inc(lineLen, Length(piece));
    end;
  end
  else
    for i := 0 to AData.Count - 1 do
    begin
      if i > 0 then Result := Result + ',';
      Result := Result + AStyle.EOL + inner
        + TyOptJsonLiteral(AData.Items[i], AStyle, inner, False);
    end;
  Result := Result + AStyle.EOL + AIndentNow + ']';
end;

{ ---- the scanner -------------------------------------------------------- }

constructor TTyOptTextPatcher.Create(const AText: string; AOriginal: TJSONData);
begin
  inherited Create;
  FText := AText;
  FOriginal := AOriginal;
  FStyle := TyOptDefaultTextStyle;
  FRoot := -1;
  FMapped := Scan and (FRoot >= 0) and Corresponds(FRoot, FOriginal);
  if FMapped then ReadStyle;
end;

procedure TTyOptTextPatcher.SkipBlank;
var n: Integer;
begin
  n := Length(FText);
  while FPos <= n do
  begin
    case FText[FPos] of
      #9, #10, #13, ' ': Inc(FPos);
      '/':
        begin
          if (FPos < n) and (FText[FPos + 1] = '/') then
          begin
            if FCommentCount = Length(FComments) then
              SetLength(FComments, 16 + FCommentCount * 2);
            FComments[FCommentCount] := FPos;
            Inc(FCommentCount);
            Inc(FPos, 2);
            while (FPos <= n) and not (FText[FPos] in [#10, #13]) do Inc(FPos);
          end
          else if (FPos < n) and (FText[FPos + 1] = '*') then
          begin
            if FCommentCount = Length(FComments) then
              SetLength(FComments, 16 + FCommentCount * 2);
            FComments[FCommentCount] := FPos;
            Inc(FCommentCount);
            Inc(FPos, 2);
            while (FPos < n) and not ((FText[FPos] = '*') and (FText[FPos + 1] = '/')) do
              Inc(FPos);
            { unterminated: run off the end, which the caller sees }
            if FPos < n then Inc(FPos, 2) else FPos := n + 1;
          end
          else
            Exit;
        end;
    else
      Exit;
    end;
  end;
end;

function TTyOptTextPatcher.ScanString: Boolean;
var
  q: Char;
  n: Integer;
begin
  n := Length(FText);
  q := FText[FPos];
  Inc(FPos);
  while (FPos <= n) and (FText[FPos] <> q) do
    if FText[FPos] = '\' then Inc(FPos, 2) else Inc(FPos);
  Result := FPos <= n;
  if Result then Inc(FPos);
end;

function TTyOptTextPatcher.ScanWord: Boolean;
var start, n: Integer;
begin
  n := Length(FText);
  start := FPos;
  while (FPos <= n) and not (FText[FPos] in
    [#9, #10, #13, ' ', ',', ':', '{', '}', '[', ']', '"', '''', '/']) do
    Inc(FPos);
  Result := FPos > start;
end;

function TTyOptTextPatcher.NewSpan(AKind: TTyOptSpanKind; AStart: Integer): Integer;
begin
  if FSpanCount = Length(FSpans) then SetLength(FSpans, 64 + FSpanCount * 2);
  Result := FSpanCount;
  FSpans[Result].Kind := AKind;
  FSpans[Result].StartPos := AStart;
  FSpans[Result].EndPos := AStart;
  FSpans[Result].FirstItem := 0;
  FSpans[Result].ItemCount := 0;
  Inc(FSpanCount);
end;

{ A key's name as the reader decodes it. Only to CHECK the map against the
  tree: a name that decodes differently fails the check, which drops the
  map rather than patching the wrong member. }
function DecodeKey(const S: string): string;
var
  i, code, lo: Integer;
  c: Char;

  function Hex4(APos: Integer): Integer;
  begin
    if APos + 3 > Length(S) then Exit(-1);
    Result := StrToIntDef('$' + Copy(S, APos, 4), -1);
  end;

  procedure AddCode(ACode: Cardinal);
  begin
    if ACode < $80 then Result := Result + Chr(ACode)
    else if ACode < $800 then
      Result := Result + Chr($C0 or (ACode shr 6)) + Chr($80 or (ACode and $3F))
    else if ACode < $10000 then
      Result := Result + Chr($E0 or (ACode shr 12))
        + Chr($80 or ((ACode shr 6) and $3F)) + Chr($80 or (ACode and $3F))
    else
      Result := Result + Chr($F0 or (ACode shr 18))
        + Chr($80 or ((ACode shr 12) and $3F))
        + Chr($80 or ((ACode shr 6) and $3F)) + Chr($80 or (ACode and $3F));
  end;

begin
  Result := '';
  if (S = '') or not (S[1] in ['"', '''']) then Exit(S);
  i := 2;
  while i < Length(S) do
  begin
    c := S[i];
    if (c = '\') and (i + 1 < Length(S)) then
    begin
      c := S[i + 1];
      Inc(i, 2);
      case c of
        'b': Result := Result + #8;
        't': Result := Result + #9;
        'n': Result := Result + #10;
        'f': Result := Result + #12;
        'r': Result := Result + #13;
        'u':
          begin
            code := Hex4(i);
            if code < 0 then Exit(#0'bad escape');
            Inc(i, 4);
            if (code >= $D800) and (code <= $DBFF) and (i + 5 <= Length(S))
              and (S[i] = '\') and (S[i + 1] = 'u') then
            begin
              lo := Hex4(i + 2);
              if (lo >= $DC00) and (lo <= $DFFF) then
              begin
                code := $10000 + ((code - $D800) shl 10) + (lo - $DC00);
                Inc(i, 6);
              end;
            end;
            AddCode(code);
          end;
      else
        Result := Result + c;
      end;
    end
    else
    begin
      Result := Result + c;
      Inc(i);
    end;
  end;
end;

function TTyOptTextPatcher.ScanValue(out AIndex: Integer): Boolean;
var
  n, start, child, keyStart, keyEnd, k: Integer;
  local: array of TTyOptSpanItem;
  count: Integer;
  closer: Char;
  isObj: Boolean;
begin
  Result := False;
  AIndex := -1;
  n := Length(FText);
  SkipBlank;
  if FPos > n then Exit;
  start := FPos;
  case FText[FPos] of
    '{', '[':
      begin
        isObj := FText[FPos] = '{';
        if isObj then
        begin
          AIndex := NewSpan(oskObject, start);
          closer := '}';
        end
        else
        begin
          AIndex := NewSpan(oskArray, start);
          closer := ']';
        end;
        Inc(FPos);
        local := nil;
        count := 0;
        while True do
        begin
          SkipBlank;
          if FPos > n then Exit;
          if FText[FPos] = closer then
          begin
            Inc(FPos);
            Break;
          end;
          keyStart := 0;
          keyEnd := 0;
          if isObj then
          begin
            keyStart := FPos;
            if FText[FPos] in ['"', ''''] then
            begin
              if not ScanString then Exit;
            end
            else if not ScanWord then Exit;
            keyEnd := FPos;
            SkipBlank;
            if (FPos > n) or (FText[FPos] <> ':') then Exit;
            Inc(FPos);
          end;
          if not ScanValue(child) then Exit;
          if count = Length(local) then SetLength(local, 8 + count * 2);
          local[count].KeyStart := keyStart;
          local[count].KeyEnd := keyEnd;
          if isObj then
            local[count].Name := DecodeKey(Copy(FText, keyStart, keyEnd - keyStart))
          else
            local[count].Name := '';
          local[count].Value := child;
          local[count].CommaPos := 0;
          SkipBlank;
          if FPos > n then Exit;
          if FText[FPos] = ',' then
          begin
            local[count].CommaPos := FPos;
            Inc(FPos);
          end
          else if FText[FPos] <> closer then
          begin
            Inc(count);
            Exit;
          end;
          Inc(count);
        end;
        FSpans[AIndex].EndPos := FPos;
        FSpans[AIndex].FirstItem := FItemCount;
        FSpans[AIndex].ItemCount := count;
        if FItemCount + count > Length(FItems) then
          SetLength(FItems, FItemCount + count + 64 + FItemCount);
        for k := 0 to count - 1 do
          FItems[FItemCount + k] := local[k];
        Inc(FItemCount, count);
        Result := True;
      end;
    '"', '''':
      begin
        AIndex := NewSpan(oskScalar, start);
        if not ScanString then Exit;
        FSpans[AIndex].EndPos := FPos;
        Result := True;
      end;
    ',', ':', '}', ']':
      Exit;
  else
    AIndex := NewSpan(oskScalar, start);
    if not ScanWord then Exit;
    FSpans[AIndex].EndPos := FPos;
    Result := True;
  end;
end;

function TTyOptTextPatcher.Scan: Boolean;
begin
  FPos := 1;
  FSpanCount := 0;
  FItemCount := 0;
  FCommentCount := 0;
  Result := ScanValue(FRoot);
  if Result then
  begin
    SkipBlank;
    Result := FPos > Length(FText);
  end;
  if not Result then
  begin
    { Finish counting comments over the rest, so a caller told the map
      failed still learns how many comments a full rewrite drops. }
    while FPos <= Length(FText) do
    begin
      SkipBlank;
      if FPos > Length(FText) then Break;
      if FText[FPos] in ['"', ''''] then ScanString else Inc(FPos);
    end;
    FRoot := -1;
  end;
end;

function TTyOptTextPatcher.Corresponds(ASpan: Integer; AData: TJSONData): Boolean;
var
  i: Integer;
  it: TTyOptSpanItem;
begin
  Result := False;
  if AData = nil then Exit;
  case FSpans[ASpan].Kind of
    oskObject:
      begin
        if not (AData is TJSONObject) then Exit;
        if AData.Count <> FSpans[ASpan].ItemCount then Exit;
        for i := 0 to AData.Count - 1 do
        begin
          it := FItems[FSpans[ASpan].FirstItem + i];
          if TJSONObject(AData).Names[i] <> it.Name then Exit;
          if not Corresponds(it.Value, AData.Items[i]) then Exit;
        end;
      end;
    oskArray:
      begin
        if not (AData is TJSONArray) then Exit;
        if AData.Count <> FSpans[ASpan].ItemCount then Exit;
        for i := 0 to AData.Count - 1 do
          if not Corresponds(FItems[FSpans[ASpan].FirstItem + i].Value,
            AData.Items[i]) then Exit;
      end;
    oskScalar:
      if AData.JSONType in [jtObject, jtArray] then Exit;
  end;
  Result := True;
end;

procedure TTyOptTextPatcher.ReadStyle;
var
  i, k, a, b, rootIndent: Integer;
  it: TTyOptSpanItem;
  s, mine: string;
  foundQuote, foundKey: Boolean;
begin
  foundQuote := False;
  foundKey := False;
  { the first string VALUE says how strings are quoted; a key is the
    fallback, because bare keys say nothing about it }
  for i := 0 to FSpanCount - 1 do
    if (FSpans[i].Kind = oskScalar)
      and (FText[FSpans[i].StartPos] in ['"', '''']) then
    begin
      FStyle.Quote := FText[FSpans[i].StartPos];
      foundQuote := True;
      Break;
    end;
  for i := 0 to FSpanCount - 1 do
    if (FSpans[i].Kind = oskObject) and (FSpans[i].ItemCount > 0) then
    begin
      it := FItems[FSpans[i].FirstItem];
      FStyle.BareKeys := not (FText[it.KeyStart] in ['"', '''']);
      if (not foundQuote) and not FStyle.BareKeys then
        FStyle.Quote := FText[it.KeyStart];
      { the colon as written, when it is only blanks and a colon }
      a := it.KeyEnd;
      b := FSpans[it.Value].StartPos;
      s := Copy(FText, a, b - a);
      if (s <> '') and (Length(s) <= 3) and (Trim(s) = ':') then
        FStyle.Colon := TrimLeft(s);
      foundKey := True;
      Break;
    end;
  if not foundKey then FStyle.BareKeys := True;

  { the indent unit: how far the root's first member sits in from the root }
  if (FSpans[FRoot].Kind in [oskObject, oskArray])
    and (FSpans[FRoot].ItemCount > 0) then
  begin
    it := FItems[FSpans[FRoot].FirstItem];
    if it.KeyStart > 0 then k := it.KeyStart
    else k := FSpans[it.Value].StartPos;
    if IsLineLead(k) and HasBreak(FSpans[FRoot].StartPos, k) then
    begin
      s := IndentOfLine(FSpans[FRoot].StartPos);
      rootIndent := Length(s);
      mine := IndentOfLine(k);
      if (Length(mine) > rootIndent) and (Copy(mine, 1, rootIndent) = s) then
        FStyle.Indent := Copy(mine, rootIndent + 1, MaxInt);
    end;
  end;

  for i := 1 to Length(FText) do
    if FText[i] = #10 then
    begin
      if (i > 1) and (FText[i - 1] = #13) then FStyle.EOL := #13#10
      else FStyle.EOL := #10;
      Break;
    end
    else if (FText[i] = #13) and ((i = Length(FText)) or (FText[i + 1] <> #10)) then
    begin
      FStyle.EOL := #13;
      Break;
    end;
end;

{ ---- layout helpers ----------------------------------------------------- }

function TTyOptTextPatcher.LineStartOf(APos: Integer): Integer;
begin
  Result := APos;
  while (Result > 1) and not (FText[Result - 1] in [#10, #13]) do Dec(Result);
end;

function TTyOptTextPatcher.IndentOfLine(APos: Integer): string;
var a, b: Integer;
begin
  a := LineStartOf(APos);
  b := a;
  while (b <= Length(FText)) and (FText[b] in [' ', #9]) do Inc(b);
  Result := Copy(FText, a, b - a);
end;

function TTyOptTextPatcher.IsLineLead(APos: Integer): Boolean;
var a: Integer;
begin
  a := LineStartOf(APos);
  while (a < APos) and (FText[a] in [' ', #9]) do Inc(a);
  Result := a = APos;
end;

function TTyOptTextPatcher.HasBreak(AFrom, ATo: Integer): Boolean;
var i: Integer;
begin
  for i := AFrom to ATo - 1 do
    if FText[i] in [#10, #13] then Exit(True);
  Result := False;
end;

function TTyOptTextPatcher.CommentsIn(AFrom, ATo: Integer): Integer;
var lo, hi, mid, first: Integer;
begin
  { the comments start in ascending order: two binary searches }
  lo := 0;
  hi := FCommentCount;
  while lo < hi do
  begin
    mid := (lo + hi) div 2;
    if FComments[mid] < AFrom then lo := mid + 1 else hi := mid;
  end;
  first := lo;
  hi := FCommentCount;
  while lo < hi do
  begin
    mid := (lo + hi) div 2;
    if FComments[mid] < ATo then lo := mid + 1 else hi := mid;
  end;
  Result := lo - first;
end;

{ APos, or -- when only blanks and then a // comment follow on the same
  line -- the end of that comment. A comment trailing a member's comma is
  about that member, and goes or stays with it. }
function TTyOptTextPatcher.PastLineComment(APos: Integer): Integer;
var p: Integer;
begin
  Result := APos;
  p := APos;
  while (p <= Length(FText)) and (FText[p] in [' ', #9]) do Inc(p);
  if (p < Length(FText)) and (FText[p] = '/') and (FText[p + 1] = '/') then
  begin
    while (p <= Length(FText)) and not (FText[p] in [#10, #13]) do Inc(p);
    Result := p;
  end;
end;

function TTyOptTextPatcher.SpanText(ASpan: Integer): string;
begin
  Result := Copy(FText, FSpans[ASpan].StartPos,
    FSpans[ASpan].EndPos - FSpans[ASpan].StartPos);
end;

function TTyOptTextPatcher.IsMultiLine(ASpan: Integer): Boolean;
var
  it: TTyOptSpanItem;
  k: Integer;
begin
  if FSpans[ASpan].ItemCount = 0 then
    Exit(HasBreak(FSpans[ASpan].StartPos, FSpans[ASpan].EndPos));
  it := FItems[FSpans[ASpan].FirstItem];
  if it.KeyStart > 0 then k := it.KeyStart else k := FSpans[it.Value].StartPos;
  Result := HasBreak(FSpans[ASpan].StartPos, k);
end;

{ The indentation of the container's members: the first member's, when it
  starts its own line; one unit in from the container's line otherwise. }
function TTyOptTextPatcher.ItemIndent(ASpan: Integer): string;
var
  it: TTyOptSpanItem;
  k: Integer;
begin
  if FSpans[ASpan].ItemCount > 0 then
  begin
    it := FItems[FSpans[ASpan].FirstItem];
    if it.KeyStart > 0 then k := it.KeyStart else k := FSpans[it.Value].StartPos;
    if IsLineLead(k) then Exit(IndentOfLine(k));
  end;
  Result := IndentOfLine(FSpans[ASpan].StartPos) + FStyle.Indent;
end;

{ The separator a one-line container uses after a comma: ', ' or ','. }
function TTyOptTextPatcher.InlineSep(ASpan: Integer): string;
var it: TTyOptSpanItem;
begin
  Result := ', ';
  if FSpans[ASpan].ItemCount = 0 then Exit;
  it := FItems[FSpans[ASpan].FirstItem];
  if (it.CommaPos > 0) and (it.CommaPos < Length(FText))
    and not (FText[it.CommaPos + 1] in [' ', #9, #10, #13]) then
    Result := ',';
end;

function TTyOptTextPatcher.KeyText(const AName: string): string;
begin
  Result := KeyIn(AName, FStyle);
end;

{ ---- the patch ------------------------------------------------------------ }

function Assemble(const AText: string; AFrom, ATo: Integer; var L: TTyOptTextEditList;
  out AOk: Boolean): string;
var
  i, p: Integer;
begin
  SortEdits(L);
  Result := '';
  p := AFrom;
  AOk := True;
  for i := 0 to L.Count - 1 do
  begin
    if L.Items[i].StartPos < p then
    begin
      { overlapping edits: a bug, never a silent wrong answer }
      AOk := False;
      Exit;
    end;
    Result := Result + Copy(AText, p, L.Items[i].StartPos - p) + L.Items[i].Text;
    p := L.Items[i].StopPos;
  end;
  Result := Result + Copy(AText, p, ATo - p);
end;

function TTyOptTextPatcher.PatchValue(ASpan: Integer; AOld, ANew: TJSONData): string;
begin
  if TyOptJsonSame(AOld, ANew) then Exit(SpanText(ASpan));
  if (FSpans[ASpan].Kind = oskObject) and (FSpans[ASpan].ItemCount > 0)
    and (AOld is TJSONObject) and (ANew is TJSONObject) then
    Exit(PatchObject(ASpan, TJSONObject(AOld), TJSONObject(ANew)));
  if (FSpans[ASpan].Kind = oskArray) and (FSpans[ASpan].ItemCount > 0)
    and (AOld is TJSONArray) and (ANew is TJSONArray) and (ANew.Count > 0) then
    Exit(PatchArray(ASpan, TJSONArray(AOld), TJSONArray(ANew)));
  Inc(FLost, CommentsIn(FSpans[ASpan].StartPos, FSpans[ASpan].EndPos));
  Result := TyOptJsonLiteral(ANew, FStyle, IndentOfLine(FSpans[ASpan].StartPos),
    HasBreak(FSpans[ASpan].StartPos, FSpans[ASpan].EndPos));
end;

function TTyOptTextPatcher.PatchObject(ASpan: Integer; AOld,
  ANew: TJSONObject): string;
var
  L: TTyOptTextEditList;
  n, i, a, b, lastKept, first, q, lostBefore: Integer;
  kept: array of Boolean;
  added: TStringList;
  it: TTyOptSpanItem;
  sp: TTyOptSpan;
  multi, ok: Boolean;
  indent, lead, ins: string;

  function Item(AIdx: Integer): TTyOptSpanItem;
  begin
    Result := FItems[first + AIdx];
  end;

  function ValueEnd(AIdx: Integer): Integer;
  begin
    Result := FSpans[Item(AIdx).Value].EndPos;
  end;

  { Where the text of member AIdx begins, counting the blanks and lines in
    front of it: just past the previous member's comma (and a // comment
    trailing it), or just past the brace. }
begin
  sp := FSpans[ASpan];
  first := sp.FirstItem;
  n := sp.ItemCount;
  L.Count := 0;
  L.Items := nil;
  lostBefore := FLost;
  SetLength(kept, n);
  lastKept := -1;
  for i := 0 to n - 1 do
  begin
    it := Item(i);
    kept[i] := ANew.IndexOfName(it.Name) >= 0;
    if kept[i] then
    begin
      lastKept := i;
      if not TyOptJsonSame(AOld.Items[i], ANew.Elements[it.Name]) then
        AddEdit(L, FSpans[it.Value].StartPos, FSpans[it.Value].EndPos,
          PatchValue(it.Value, AOld.Items[i], ANew.Elements[it.Name]));
    end;
  end;

  added := TStringList.Create;
  try
    for i := 0 to ANew.Count - 1 do
      if AOld.IndexOfName(ANew.Names[i]) < 0 then added.Add(ANew.Names[i]);

    i := 0;
    while i < n do
      if kept[i] then Inc(i)
      else
      begin
        a := i;
        while (i < n) and not kept[i] do Inc(i);
        b := i - 1;
        CutItems(ASpan, a, b, added.Count > 0, L);
      end;

    if added.Count > 0 then
    begin
      multi := IsMultiLine(ASpan);
      indent := ItemIndent(ASpan);
      if multi then lead := FStyle.EOL + indent else lead := ' ';
      ins := '';
      for i := 0 to added.Count - 1 do
      begin
        if i > 0 then ins := ins + ',';
        if (i > 0) and not multi then ins := ins + ' '
        else ins := ins + lead;
        ins := ins + KeyText(added[i]) + FStyle.Colon
          + TyOptJsonLiteral(ANew.Elements[added[i]], FStyle, indent, False);
      end;
      if lastKept < 0 then
        q := sp.StartPos + 1
      else if Item(lastKept).CommaPos > 0 then
        q := PastLineComment(Item(lastKept).CommaPos + 1)
      else
      begin
        q := ValueEnd(lastKept);
        ins := ',' + ins;
      end;
      AddEdit(L, q, q, ins);
    end;
  finally
    added.Free;
  end;

  Result := Assemble(FText, sp.StartPos, sp.EndPos, L, ok);
  if not ok then
  begin
    FLost := lostBefore + CommentsIn(sp.StartPos, sp.EndPos);
    Result := TyOptJsonLiteral(ANew, FStyle, IndentOfLine(sp.StartPos),
      HasBreak(sp.StartPos, sp.EndPos));
  end;
end;

function Max0(A: Integer): Integer;
begin
  if A < 0 then Result := 0 else Result := A;
end;

procedure TTyOptTextPatcher.SetArrayHint(ANewArray: TJSONData;
  const AOrigins: array of Integer);
var i: Integer;
begin
  FHintArray := ANewArray;
  SetLength(FHintOrigins, Length(AOrigins));
  for i := 0 to High(AOrigins) do FHintOrigins[i] := AOrigins[i];
end;

{ Where a cut of items AFirst..ALast of a container begins and ends. The
  rules are an object's and an array's alike:

  - a run with an item after it, or ending in a trailing comma, goes with
    its own commas -- from just past the comma before it (or the bracket) to
    just past its last comma, a // comment trailing that comma included;
  - on ONE line, a run at the front goes from its first token to the next
    one, so `[a, b]` loses `a, ` and not the padding after the bracket;
  - a run to the end with no trailing comma takes the comma of the item
    before it instead, unless AKeepComma (something is appended there). }
procedure TTyOptTextPatcher.CutItems(ASpan, AFirst, ALast: Integer;
  AKeepComma: Boolean; var AEdits: TTyOptTextEditList);
var
  sp: TTyOptSpan;
  first, n, a, b: Integer;

  function TokenStart(AIdx: Integer): Integer;
  begin
    if FItems[first + AIdx].KeyStart > 0 then Result := FItems[first + AIdx].KeyStart
    else Result := FSpans[FItems[first + AIdx].Value].StartPos;
  end;

  function LeadStart(AIdx: Integer): Integer;
  begin
    if AIdx = 0 then Result := sp.StartPos + 1
    else Result := PastLineComment(FItems[first + AIdx - 1].CommaPos + 1);
  end;

begin
  sp := FSpans[ASpan];
  first := sp.FirstItem;
  n := sp.ItemCount;
  if (ALast < n - 1) or (FItems[first + ALast].CommaPos > 0) then
  begin
    a := LeadStart(AFirst);
    b := PastLineComment(FItems[first + ALast].CommaPos + 1);
    if (AFirst = 0) and not IsMultiLine(ASpan) then
    begin
      a := TokenStart(0);
      while (b <= Length(FText)) and (FText[b] in [' ', #9]) do Inc(b);
    end;
    AddEdit(AEdits, a, b, '');
  end
  else if AFirst = 0 then
    AddEdit(AEdits, sp.StartPos + 1, FSpans[FItems[first + ALast].Value].EndPos, '')
  else if AKeepComma then
    AddEdit(AEdits, LeadStart(AFirst), FSpans[FItems[first + ALast].Value].EndPos, '')
  else
  begin
    AddEdit(AEdits, FItems[first + AFirst - 1].CommaPos,
      FItems[first + AFirst - 1].CommaPos + 1, '');
    AddEdit(AEdits, LeadStart(AFirst), FSpans[FItems[first + ALast].Value].EndPos, '');
  end;
end;

function TTyOptTextPatcher.PatchArray(ASpan: Integer; AOld,
  ANew: TJSONArray): string;
var
  L: TTyOptTextEditList;
  sp: TTyOptSpan;
  first, n, m, p, s, oLo, oHi, nLo, nHi, mOld, mNew, i, j, k, common,
    lostBefore, q: Integer;
  match: array of Integer;
  used: array of Boolean;
  hinted, multi, ok, inPlace: Boolean;
  indent, sep, mid: string;

  function Elem(AIdx: Integer): Integer;
  begin
    Result := FItems[first + AIdx].Value;
  end;

  function Origin(ANewIdx: Integer): Integer;
  begin
    Result := FHintOrigins[ANewIdx];
    if (Result < 0) or (Result >= n) then Result := -1;
  end;

  function NewText(ANewIdx, AOldIdx: Integer): string;
  begin
    if AOldIdx < 0 then
      Result := TyOptJsonLiteral(ANew.Items[ANewIdx], FStyle, indent, False)
    else if TyOptJsonSame(AOld.Items[AOldIdx], ANew.Items[ANewIdx]) then
      Result := SpanText(Elem(AOldIdx))
    else
      Result := PatchValue(Elem(AOldIdx), AOld.Items[AOldIdx], ANew.Items[ANewIdx]);
  end;

  { new elements AFrom..ATo, fresh, joined }
  function Joined(AFrom, ATo: Integer): string;
  var x: Integer;
  begin
    Result := '';
    for x := AFrom to ATo do
    begin
      if x > AFrom then Result := Result + sep;
      Result := Result + NewText(x, -1);
    end;
  end;

  procedure InsertAt(AOldIdx: Integer; const AText: string);
  begin
    { in front of old element AOldIdx, or after the last one }
    if AOldIdx < n then
      AddEdit(L, FSpans[Elem(AOldIdx)].StartPos, FSpans[Elem(AOldIdx)].StartPos,
        AText + sep)
    else
      AddEdit(L, FSpans[Elem(n - 1)].EndPos, FSpans[Elem(n - 1)].EndPos, sep + AText);
  end;

begin
  sp := FSpans[ASpan];
  first := sp.FirstItem;
  n := sp.ItemCount;
  m := ANew.Count;
  L.Count := 0;
  L.Items := nil;
  lostBefore := FLost;
  multi := IsMultiLine(ASpan);
  indent := ItemIndent(ASpan);
  if multi then sep := ',' + FStyle.EOL + indent else sep := InlineSep(ASpan);
  { THE IDENTITY, when the caller knows it: the series list, whose elements
    the model moves, deletes and adds, and whose old index it remembers. An
    edited series that also moved is then patched from its own text, not
    from whichever series used to sit in its slot. }
  hinted := (FHintArray = TJSONData(ANew)) and (Length(FHintOrigins) = m);

  { the common head and tail keep their text, separators and all }
  p := 0;
  while (p < n) and (p < m) and ((not hinted) or (Origin(p) = p))
    and TyOptJsonSame(AOld.Items[p], ANew.Items[p]) do
    Inc(p);
  s := 0;
  while (s < n - p) and (s < m - p)
    and ((not hinted) or (Origin(m - 1 - s) = n - 1 - s))
    and TyOptJsonSame(AOld.Items[n - 1 - s], ANew.Items[m - 1 - s]) do
    Inc(s);
  oLo := p;
  oHi := n - s - 1;
  nLo := p;
  nHi := m - s - 1;
  mOld := oHi - oLo + 1;
  mNew := nHi - nLo + 1;

  { which old element (of the middle) each new one of the middle is }
  SetLength(match, Max0(mNew));
  SetLength(used, Max0(mOld));
  for j := 0 to mNew - 1 do match[j] := -1;
  for k := 0 to mOld - 1 do used[k] := False;
  if hinted then
  begin
    for j := 0 to mNew - 1 do
    begin
      k := Origin(nLo + j) - oLo;
      if (k >= 0) and (k < mOld) and not used[k] then
      begin
        match[j] := k;
        used[k] := True;
      end;
    end;
  end
  else if (mOld > 0) and (mNew > 0) and (mOld * mNew <= cMatchCap) then
    { without one, an element that reappears unchanged somewhere else in the
      middle is taken to have moved there }
    for j := 0 to mNew - 1 do
      for k := 0 to mOld - 1 do
        if (not used[k])
          and TyOptJsonSame(AOld.Items[oLo + k], ANew.Items[nLo + j]) then
        begin
          match[j] := k;
          used[k] := True;
          Break;
        end;

  { IN PLACE when every element of the middle that was matched stayed in its
    slot -- and, with the identity known, every element was. }
  inPlace := True;
  for j := 0 to mNew - 1 do
    if hinted then
    begin
      if match[j] <> j then inPlace := False;
    end
    else if (match[j] >= 0) and (match[j] <> j) then
      inPlace := False;
  if hinted and (mOld <> mNew) then inPlace := False;

  if inPlace and not hinted then
  begin
    { BY POSITION: the slots both have are patched where they are -- a cell
      typed into the data grid costs one token -- and the rest is a pure
      append or a pure cut at the end of the middle }
    common := mOld;
    if mNew < common then common := mNew;
    for j := 0 to common - 1 do
      if not TyOptJsonSame(AOld.Items[oLo + j], ANew.Items[nLo + j]) then
        AddEdit(L, FSpans[Elem(oLo + j)].StartPos, FSpans[Elem(oLo + j)].EndPos,
          PatchValue(Elem(oLo + j), AOld.Items[oLo + j], ANew.Items[nLo + j]));
    if mNew > common then
      InsertAt(oLo + common, Joined(nLo + common, nHi))
    else if mOld > common then
      CutItems(ASpan, oLo + common, oHi, False, L);
  end
  else if inPlace then
  begin
    for j := 0 to mNew - 1 do
      if not TyOptJsonSame(AOld.Items[oLo + j], ANew.Items[nLo + j]) then
        AddEdit(L, FSpans[Elem(oLo + j)].StartPos, FSpans[Elem(oLo + j)].EndPos,
          PatchValue(Elem(oLo + j), AOld.Items[oLo + j], ANew.Items[nLo + j]));
  end
  else if mNew <= 0 then
    CutItems(ASpan, oLo, oHi, False, L)
  else if mOld <= 0 then
    InsertAt(oLo, Joined(nLo, nHi))
  else
  begin
    { THE MIDDLE REWRITTEN: each new element from its own old text where it
      has one, fresh where it is new. What sat between the old elements --
      separators, and any comment there -- is the price, and is counted. }
    mid := '';
    for j := 0 to mNew - 1 do
    begin
      if j > 0 then mid := mid + sep;
      if match[j] >= 0 then mid := mid + NewText(nLo + j, oLo + match[j])
      else mid := mid + NewText(nLo + j, -1);
    end;
    q := 0;
    for i := 0 to mOld - 1 do
      Inc(q, CommentsIn(FSpans[Elem(oLo + i)].StartPos, FSpans[Elem(oLo + i)].EndPos));
    Inc(FLost, CommentsIn(FSpans[Elem(oLo)].StartPos, FSpans[Elem(oHi)].EndPos) - q);
    AddEdit(L, FSpans[Elem(oLo)].StartPos, FSpans[Elem(oHi)].EndPos, mid);
  end;

  Result := Assemble(FText, sp.StartPos, sp.EndPos, L, ok);
  if not ok then
  begin
    FLost := lostBefore + CommentsIn(sp.StartPos, sp.EndPos);
    Result := TyOptJsonLiteral(ANew, FStyle, IndentOfLine(sp.StartPos),
      HasBreak(sp.StartPos, sp.EndPos));
  end;
end;

function TTyOptTextPatcher.Patch(ANew: TJSONData): string;
begin
  FLost := 0;
  if TyOptJsonSame(FOriginal, ANew) then Exit(FText);
  if not FMapped then
  begin
    { nothing to patch against: the whole document, and every comment in it
      counted, so the dialog can say what a save would cost }
    FLost := FCommentCount;
    Exit(TyOptJsonLiteral(ANew, FStyle, '', True));
  end;
  Result := Copy(FText, 1, FSpans[FRoot].StartPos - 1)
    + PatchValue(FRoot, FOriginal, ANew)
    + Copy(FText, FSpans[FRoot].EndPos, MaxInt);
end;

end.
