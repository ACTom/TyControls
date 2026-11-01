unit tyControls.AdvanceChart.JsRegExp;
{$mode objfpc}{$H+}
{ TTyAdvanceChart -- JavaScript's `new RegExp(source).test(text)`, for the
  dataset filter's `reg` operator (util/conditionalExpression.ts:
  RegExpEvaluator). [spec 242]

  WHY NOT FPC'S RegExpr. The filter is written for a browser: the pattern is
  ECMAScript's grammar with its Annex B leniencies, and the text is UTF-16.
  TRegExpr differs on both -- `.` crosses line ends unless told, `$` before a
  final line end, \s is ASCII, `\8` and `\12` are octal or not by its own
  rules, a lone left brace and `]` are errors or not, and it walks bytes of UTF-8. A
  filter keeps or drops rows by the answer, so the answer has to be V8's.

  WHAT THIS IS. A parser for the pattern grammar of ECMAScript 2024 without
  flags (no u, v, i, m, s, y, g -- `new RegExp(string)` sets none), Annex B
  included: ExtendedAtom, InvalidBracedQuantifier, the legacy octal escapes,
  `\c` without a letter, identity escapes, quantified lookaheads, the class
  ranges with a class escape on one side. Named groups switch the grammar to
  its [+NamedCaptureGroups] form as V8 does (`\k` must then name a group).
  The parse is compiled to a small program for a backtracking machine that
  follows the specification's matchers step for step: RepeatMatcher's
  per-iteration capture reset and its empty check (an iteration beyond the
  minimum that consumed nothing fails), lookarounds that are atomic and keep
  a positive one's captures, lookbehinds matched right to left (sequences
  reversed, captures saved end first, back references compared behind the
  position), back references to a group that did not take part matching the
  empty string. Code units, not code points: the text is UTF-16 and a
  surrogate pair is two characters, as without the u flag.

  THE ERRORS a SyntaxError would be raise ETyJsRegExpError (an unterminated
  group or class, nothing to repeat, a braced 2,1, a class range out of order, a
  lookbehind quantified, an unknown group kind, `\` at the end, a duplicate
  or unknown group name). Node 22's V8 is the reference
  (tools/advchart-oracle/js-regexp.js holds this unit to it).

  ONE DIFFERENCE, ON PURPOSE. A pattern can backtrack for longer than the
  age of the universe -- `(a+)+b` over forty a's. V8 does; a chart that froze
  the application would be worse than one that says why. After
  cTyJsRegExpStepLimit machine steps for one test the match raises
  ETyJsRegExpError (the filter then has no table and says so).

  PURE: SysUtils. }
interface

uses SysUtils;

const
  cTyJsRegExpStepLimit = 50000000;

type
  ETyJsRegExpError = class(Exception);

  TTyJsReOp = (roChar, roAny, roClass, roSplit, roJmp, roSave, roClear,
    roBol, roEol, roWordB, roNotWordB, roBackref, roLook, roLoopInit,
    roLoopTest, roLoopEnter, roLoopEnd, roMatch);

  TTyJsReInst = record
    Op: TTyJsReOp;
    { roChar: the unit; roSave / roBackref: the slot or group; roClass: the
      class; roLoop*: the loop; roSplit / roJmp: the target; roClear: the
      first group; roLook: the program's start }
    A: Integer;
    { roSplit: the other target; roClear: the group after the last;
      roLoopTest: min; roLook: kind (0 ahead, 1 negative ahead, 2 behind,
      3 negative behind) }
    B: Integer;
    { roLoopTest: max (-1 unbounded); roLoopEnter: the first group;
      roLook: the instruction after the lookaround }
    C: Integer;
    { roLoopTest: the body's entry; roLoopEnter: the group after the last }
    D: Integer;
    { roLoopTest: the exit }
    E: Integer;
    { roLoopTest: greedy }
    Greedy: Boolean;
    { roChar / roAny / roClass / roBackref: right to left }
    Back: Boolean;
  end;

  TTyJsReRange = record
    Lo, Hi: Word;
  end;
  TTyJsReClass = record
    Ranges: array of TTyJsReRange;
    Negate: Boolean;
  end;

  TTyJsRegExp = class
  private
    FProg: array of TTyJsReInst;
    FClasses: array of TTyJsReClass;
    FGroupCount: Integer;
    FLoopCount: Integer;
    FSource: UnicodeString;
    { the match }
    FText: UnicodeString;
    FLen: Integer;
    FCaps: array of Integer;
    FLoopCount_: array of Integer;
    FLoopStart: array of Integer;
    FSteps: Int64;
    function Emit(AOp: TTyJsReOp; AA: Integer = 0; AB: Integer = 0): Integer;
    function ClassHas(AIndex: Integer; ACh: Word): Boolean;
    function IsWordAt(APos: Integer): Boolean;
    function Run(APc, APos: Integer; out AEnd: Integer): Boolean;
  public
    { Raises ETyJsRegExpError where `new RegExp(APattern)` throws. }
    constructor Create(const APattern: UnicodeString);
    { RegExp.prototype.test: a match anywhere. Raises ETyJsRegExpError past
      the step limit. }
    function Test(const AText: UnicodeString): Boolean;
    property GroupCount: Integer read FGroupCount;
    property Source: UnicodeString read FSource;
  end;

{ UTF-8 in, as the option text holds strings. }
function TyJsRegExpCreate(const APattern: string): TTyJsRegExp;
function TyJsRegExpTest(ARe: TTyJsRegExp; const AText: string): Boolean;

implementation

type
  TNodeKind = (nkEmpty, nkChar, nkAny, nkClass, nkSeq, nkAlt, nkGroup,
    nkNonCap, nkLook, nkBol, nkEol, nkWordB, nkNotWordB, nkBackref,
    nkNamedBackref, nkRepeat);

  TNode = class
  public
    Kind: TNodeKind;
    Ch: Word;
    ClassIndex: Integer;
    Kids: array of TNode;
    { nkGroup: the group's number (1-based); nkBackref: the group }
    Group: Integer;
    { nkLook: 0 ahead, 1 negative ahead, 2 behind, 3 negative behind }
    Look: Integer;
    Min, Max: Integer;
    Greedy: Boolean;
    { the groups inside (for the repeat's reset): [FirstGroup, AfterGroup) }
    FirstGroup, AfterGroup: Integer;
    Name: UnicodeString;
    destructor Destroy; override;
    procedure Add(AKid: TNode);
  end;

destructor TNode.Destroy;
var i: Integer;
begin
  for i := 0 to High(Kids) do Kids[i].Free;
  inherited Destroy;
end;

procedure TNode.Add(AKid: TNode);
begin
  SetLength(Kids, Length(Kids) + 1);
  Kids[High(Kids)] := AKid;
end;

function NewNode(AKind: TNodeKind): TNode;
begin
  Result := TNode.Create;
  Result.Kind := AKind;
end;

procedure ReFail(const AMsg: string);
begin
  raise ETyJsRegExpError.Create('Invalid regular expression: ' + AMsg);
end;

{ ==================== the parser ==================== }

type
  TParser = class
  public
    S: UnicodeString;
    P: Integer;           // 1-based
    N: Integer;
    Named: Boolean;       // [+NamedCaptureGroups]
    TotalGroups: Integer; // CountLeftCapturingParensWithin(pattern)
    GroupNo: Integer;     // groups opened so far
    Names: array of UnicodeString;  // by group number - 1
    Owner: TTyJsRegExp;
    Backrefs: array of TNode;       // named, resolved at the end
    function AtEnd: Boolean;
    function Cur: WideChar;
    function Peek(AOff: Integer): WideChar;
    function ParseDisjunction: TNode;
    function ParseAlternative: TNode;
    function ParseTerm(out ANode: TNode): Boolean;
    function TryQuantifier(out AMin, AMax: Integer; out AGreedy: Boolean): Boolean;
    function ParseAtomEscape: TNode;
    function ParseClass: TNode;
    function ParseGroupName: UnicodeString;
    function AddClass(const AClass: TTyJsReClass): Integer;
  end;

function IsDigit(C: WideChar): Boolean; inline;
begin
  Result := (C >= '0') and (C <= '9');
end;

function IsOctal(C: WideChar): Boolean; inline;
begin
  Result := (C >= '0') and (C <= '7');
end;

function HexVal(C: WideChar): Integer;
begin
  case C of
    '0'..'9': Result := Ord(C) - Ord('0');
    'a'..'f': Result := Ord(C) - Ord('a') + 10;
    'A'..'F': Result := Ord(C) - Ord('A') + 10;
  else
    Result := -1;
  end;
end;

function IsAsciiLetter(C: WideChar): Boolean; inline;
begin
  Result := ((C >= 'a') and (C <= 'z')) or ((C >= 'A') and (C <= 'Z'));
end;

procedure AddRange(var AClass: TTyJsReClass; ALo, AHi: Word);
var n: Integer;
begin
  n := Length(AClass.Ranges);
  SetLength(AClass.Ranges, n + 1);
  AClass.Ranges[n].Lo := ALo;
  AClass.Ranges[n].Hi := AHi;
end;

{ \d \s \w and their complements, as ranges over the code units }
procedure AddEscapeClass(var AClass: TTyJsReClass; AWhich: WideChar);
var
  tmp: TTyJsReClass;
  i, lo: Integer;
  sorted: Boolean;
  r: TTyJsReRange;
begin
  tmp := Default(TTyJsReClass);
  case AWhich of
    'd', 'D': AddRange(tmp, Ord('0'), Ord('9'));
    'w', 'W':
      begin
        AddRange(tmp, Ord('0'), Ord('9'));
        AddRange(tmp, Ord('A'), Ord('Z'));
        AddRange(tmp, Ord('_'), Ord('_'));
        AddRange(tmp, Ord('a'), Ord('z'));
      end;
    's', 'S':
      begin
        { WhiteSpace and LineTerminator: TAB LF VT FF CR, SP, NBSP, the Zs
          of Unicode 15, LS PS, BOM }
        AddRange(tmp, 9, 13);
        AddRange(tmp, 32, 32);
        AddRange(tmp, $A0, $A0);
        AddRange(tmp, $1680, $1680);
        AddRange(tmp, $2000, $200A);
        AddRange(tmp, $2028, $2029);
        AddRange(tmp, $202F, $202F);
        AddRange(tmp, $205F, $205F);
        AddRange(tmp, $3000, $3000);
        AddRange(tmp, $FEFF, $FEFF);
      end;
  end;
  if (AWhich = 'D') or (AWhich = 'W') or (AWhich = 'S') then
  begin
    { ascending and disjoint already: the complement }
    repeat
      sorted := True;
      for i := 0 to High(tmp.Ranges) - 1 do
        if tmp.Ranges[i].Lo > tmp.Ranges[i + 1].Lo then
        begin
          r := tmp.Ranges[i];
          tmp.Ranges[i] := tmp.Ranges[i + 1];
          tmp.Ranges[i + 1] := r;
          sorted := False;
        end;
    until sorted;
    lo := 0;
    for i := 0 to High(tmp.Ranges) do
    begin
      if tmp.Ranges[i].Lo > lo then AddRange(AClass, lo, tmp.Ranges[i].Lo - 1);
      lo := tmp.Ranges[i].Hi + 1;
    end;
    if lo <= $FFFF then AddRange(AClass, lo, $FFFF);
  end
  else
    for i := 0 to High(tmp.Ranges) do
      AddRange(AClass, tmp.Ranges[i].Lo, tmp.Ranges[i].Hi);
end;

function TParser.AtEnd: Boolean;
begin
  Result := P > N;
end;

function TParser.Cur: WideChar;
begin
  if P <= N then Result := S[P] else Result := #0;
end;

function TParser.Peek(AOff: Integer): WideChar;
begin
  if P + AOff <= N then Result := S[P + AOff] else Result := #0;
end;

function TParser.AddClass(const AClass: TTyJsReClass): Integer;
begin
  Result := Length(Owner.FClasses);
  SetLength(Owner.FClasses, Result + 1);
  Owner.FClasses[Result] := AClass;
end;

function TParser.ParseDisjunction: TNode;
var alt: TNode;
begin
  alt := ParseAlternative;
  if Cur <> '|' then Exit(alt);
  Result := NewNode(nkAlt);
  Result.Add(alt);
  while (not AtEnd) and (Cur = '|') do
  begin
    Inc(P);
    Result.Add(ParseAlternative);
  end;
end;

function TParser.ParseAlternative: TNode;
var t: TNode;
begin
  Result := NewNode(nkSeq);
  try
    while (not AtEnd) and (Cur <> '|') and (Cur <> ')') do
      if ParseTerm(t) then Result.Add(t);
  except
    Result.Free;
    raise;
  end;
end;

{ A quantifier at P: `*`, `+`, `?`, n or n, or n,m in braces, then `?` for
  lazy. A left brace that does not make one is no quantifier (Annex B) and P
  stays. }
function TParser.TryQuantifier(out AMin, AMax: Integer; out AGreedy: Boolean): Boolean;
var
  q: Integer;
  v: Int64;

  function ReadInt(out AVal: Integer): Boolean;
  begin
    Result := False;
    v := 0;
    while (q <= N) and IsDigit(S[q]) do
    begin
      { DecimalDigits past 2^31 are clamped (V8's kMaxInt) }
      if v < $7FFFFFFF then v := v * 10 + (Ord(S[q]) - Ord('0'));
      if v > $7FFFFFFF then v := $7FFFFFFF;
      Inc(q);
      Result := True;
    end;
    AVal := Integer(v);
  end;

begin
  Result := False;
  AGreedy := True;
  AMin := 0;
  AMax := -1;
  if AtEnd then Exit;
  case Cur of
    '*': begin AMin := 0; AMax := -1; Inc(P); end;
    '+': begin AMin := 1; AMax := -1; Inc(P); end;
    '?': begin AMin := 0; AMax := 1; Inc(P); end;
    '{':
      begin
        q := P + 1;
        if not ReadInt(AMin) then Exit;
        if (q <= N) and (S[q] = '}') then
          AMax := AMin
        else if (q <= N) and (S[q] = ',') then
        begin
          Inc(q);
          if (q <= N) and (S[q] = '}') then AMax := -1
          else
          begin
            if not ReadInt(AMax) then Exit;
            if (q > N) or (S[q] <> '}') then Exit;
          end;
        end
        else
          Exit;
        P := q + 1;
        if (AMax >= 0) and (AMin > AMax) then
          ReFail('numbers out of order in {} quantifier');
      end;
  else
    Exit;
  end;
  if (not AtEnd) and (Cur = '?') then
  begin
    AGreedy := False;
    Inc(P);
  end;
  Result := True;
end;

{ Annex B's InvalidBracedQuantifier at P: n, n, or n,m in braces }
function BracedQuantifierAt(const S: UnicodeString; P, N: Integer): Boolean;
var q: Integer;
begin
  Result := False;
  if (P > N) or (S[P] <> '{') then Exit;
  q := P + 1;
  if (q > N) or not IsDigit(S[q]) then Exit;
  while (q <= N) and IsDigit(S[q]) do Inc(q);
  if (q <= N) and (S[q] = '}') then Exit(True);
  if (q > N) or (S[q] <> ',') then Exit;
  Inc(q);
  if (q <= N) and (S[q] = '}') then Exit(True);
  if (q > N) or not IsDigit(S[q]) then Exit;
  while (q <= N) and IsDigit(S[q]) do Inc(q);
  Result := (q <= N) and (S[q] = '}');
end;

function TParser.ParseGroupName: UnicodeString;
var c: WideChar;
begin
  { P is past the `<`; IdentifierName up to `>` }
  Result := '';
  while True do
  begin
    if AtEnd then ReFail('invalid capture group name');
    c := Cur;
    if c = '>' then Break;
    if (c = '$') or (c = '_') or IsAsciiLetter(c) or (IsDigit(c) and (Result <> ''))
      or ((Ord(c) >= $80) and (c <> #$2028) and (c <> #$2029)) then
    begin
      Result := Result + c;
      Inc(P);
    end
    else
      ReFail('invalid capture group name');
  end;
  if Result = '' then ReFail('invalid capture group name');
  Inc(P);
end;

{ An escape's single character in AtomEscape or ClassEscape position (P is
  past the backslash and not at a class escape or a back reference):
  Annex B's CharacterEscape. AInClass: `\c` takes a digit or `_` too. Answers
  -1 for `\c` with no control letter (the backslash is then a character on
  its own and P stays at the c). }
function ReadCharEscape(AP: TParser; AInClass: Boolean): Integer;
var
  c, c1: WideChar;
  v, h1, h2, h3, h4: Integer;
begin
  c := AP.Cur;
  case c of
    'f': begin Inc(AP.P); Exit(12); end;
    'n': begin Inc(AP.P); Exit(10); end;
    'r': begin Inc(AP.P); Exit(13); end;
    't': begin Inc(AP.P); Exit(9); end;
    'v': begin Inc(AP.P); Exit(11); end;
    'c':
      begin
        c1 := AP.Peek(1);
        if IsAsciiLetter(c1) or (AInClass and (IsDigit(c1) or (c1 = '_'))) then
        begin
          Inc(AP.P, 2);
          Exit(Ord(c1) mod 32);
        end;
        Exit(-1);
      end;
    'x':
      begin
        h1 := HexVal(AP.Peek(1));
        h2 := HexVal(AP.Peek(2));
        if (h1 >= 0) and (h2 >= 0) then
        begin
          Inc(AP.P, 3);
          Exit(h1 * 16 + h2);
        end;
        Inc(AP.P);
        Exit(Ord('x'));
      end;
    'u':
      begin
        h1 := HexVal(AP.Peek(1));
        h2 := HexVal(AP.Peek(2));
        h3 := HexVal(AP.Peek(3));
        h4 := HexVal(AP.Peek(4));
        if (h1 >= 0) and (h2 >= 0) and (h3 >= 0) and (h4 >= 0) then
        begin
          Inc(AP.P, 5);
          Exit(((h1 * 16 + h2) * 16 + h3) * 16 + h4);
        end;
        Inc(AP.P);
        Exit(Ord('u'));
      end;
    '0'..'7':
      begin
        { \0 not before a digit; else LegacyOctalEscapeSequence }
        if (c = '0') and not IsDigit(AP.Peek(1)) then
        begin
          Inc(AP.P);
          Exit(0);
        end;
        v := Ord(c) - Ord('0');
        Inc(AP.P);
        if IsOctal(AP.Cur) then
        begin
          v := v * 8 + Ord(AP.Cur) - Ord('0');
          Inc(AP.P);
          if (c <= '3') and IsOctal(AP.Cur) then
          begin
            v := v * 8 + Ord(AP.Cur) - Ord('0');
            Inc(AP.P);
          end;
        end;
        Exit(v);
      end;
  else
    { IdentityEscape: any character but c (and k with named groups) }
    if AP.Named and (c = 'k') then ReFail('invalid named reference');
    Inc(AP.P);
    Result := Ord(c);
  end;
end;

function TParser.ParseAtomEscape: TNode;
var
  q, v, ch: Integer;
  c: WideChar;
  cls: TTyJsReClass;
  nm: UnicodeString;
begin
  { P is past the backslash }
  if AtEnd then ReFail('\ at end of pattern');
  c := Cur;
  case c of
    'b': begin Inc(P); Exit(NewNode(nkWordB)); end;
    'B': begin Inc(P); Exit(NewNode(nkNotWordB)); end;
    'd', 'D', 'w', 'W', 's', 'S':
      begin
        Inc(P);
        cls := Default(TTyJsReClass);
        AddEscapeClass(cls, c);
        Result := NewNode(nkClass);
        Result.ClassIndex := AddClass(cls);
        Exit;
      end;
    '1'..'9':
      begin
        { DecimalEscape, when its number is a group of the pattern }
        q := P;
        v := 0;
        while (q <= N) and IsDigit(S[q]) do
        begin
          if v < 100000 then v := v * 10 + Ord(S[q]) - Ord('0');
          Inc(q);
        end;
        if v <= TotalGroups then
        begin
          P := q;
          Result := NewNode(nkBackref);
          Result.Group := v;
          Exit;
        end;
        { else an octal escape, or the digit itself }
        if c >= '8' then
        begin
          Inc(P);
          Result := NewNode(nkChar);
          Result.Ch := Ord(c);
          Exit;
        end;
      end;
    'k':
      if Named then
      begin
        Inc(P);
        if Cur <> '<' then ReFail('invalid named reference');
        Inc(P);
        nm := ParseGroupName;
        Result := NewNode(nkNamedBackref);
        Result.Name := nm;
        SetLength(Backrefs, Length(Backrefs) + 1);
        Backrefs[High(Backrefs)] := Result;
        Exit;
      end;
  end;
  ch := ReadCharEscape(Self, False);
  Result := NewNode(nkChar);
  if ch < 0 then
    { `\` before a c that is no control: the backslash alone }
    Result.Ch := Ord('\')
  else
    Result.Ch := ch;
end;

function TParser.ParseClass: TNode;
var
  cls: TTyJsReClass;
  lo, hi: Integer;
  loIsClass, hiIsClass: Boolean;
  tmp: TTyJsReClass;

  { one ClassAtom: a code unit (>= 0) or a class escape added to tmp (-2) }
  function ReadAtom(out AIsClass: Boolean): Integer;
  var c: WideChar;
  begin
    AIsClass := False;
    if AtEnd then ReFail('unterminated character class');
    c := Cur;
    if c <> '\' then
    begin
      Inc(P);
      Exit(Ord(c));
    end;
    Inc(P);
    if AtEnd then ReFail('\ at end of pattern');
    c := Cur;
    case c of
      'b': begin Inc(P); Exit(8); end;
      '-': begin Inc(P); Exit(Ord('-')); end;
      'd', 'D', 'w', 'W', 's', 'S':
        begin
          Inc(P);
          tmp := Default(TTyJsReClass);
          AddEscapeClass(tmp, c);
          AIsClass := True;
          Exit(-2);
        end;
      '8', '9':
        begin
          Inc(P);
          Exit(Ord(c));
        end;
    end;
    Result := ReadCharEscape(Self, True);
    { `\c` without a control letter: the backslash, the c read next }
    if Result < 0 then Result := Ord('\');
  end;

  procedure Put(AVal: Integer; AIsClass: Boolean; const AClassPart: TTyJsReClass);
  var i: Integer;
  begin
    if AIsClass then
      for i := 0 to High(AClassPart.Ranges) do
        AddRange(cls, AClassPart.Ranges[i].Lo, AClassPart.Ranges[i].Hi)
    else
      AddRange(cls, AVal, AVal);
  end;

var
  loPart: TTyJsReClass;
begin
  { P is past the `[` }
  cls := Default(TTyJsReClass);
  if Cur = '^' then
  begin
    cls.Negate := True;
    Inc(P);
  end;
  while True do
  begin
    if AtEnd then ReFail('unterminated character class');
    if Cur = ']' then
    begin
      Inc(P);
      Break;
    end;
    lo := ReadAtom(loIsClass);
    loPart := tmp;
    if (Cur = '-') and (Peek(1) <> ']') and (P + 1 <= N) then
    begin
      Inc(P);
      hi := ReadAtom(hiIsClass);
      if loIsClass or hiIsClass then
      begin
        { Annex B: a class escape on either side -- the atoms and `-` }
        Put(lo, loIsClass, loPart);
        AddRange(cls, Ord('-'), Ord('-'));
        Put(hi, hiIsClass, tmp);
      end
      else
      begin
        if lo > hi then ReFail('range out of order in character class');
        AddRange(cls, lo, hi);
      end;
    end
    else
      Put(lo, loIsClass, loPart);
  end;
  Result := NewNode(nkClass);
  Result.ClassIndex := AddClass(cls);
end;

{ One Term. False when it made nothing (never: every term is a node). }
function TParser.ParseTerm(out ANode: TNode): Boolean;
var
  c: WideChar;
  atom, rep: TNode;
  mn, mx: Integer;
  greedy, quantifiable: Boolean;
  firstGroup: Integer;
  nm: UnicodeString;
  i: Integer;
begin
  ANode := nil;
  Result := True;
  c := Cur;
  firstGroup := GroupNo + 1;
  quantifiable := True;
  atom := nil;
  case c of
    '^': begin Inc(P); ANode := NewNode(nkBol); Exit; end;
    '$': begin Inc(P); ANode := NewNode(nkEol); Exit; end;
    '\':
      begin
        Inc(P);
        atom := ParseAtomEscape;
        if atom.Kind in [nkWordB, nkNotWordB] then
        begin
          ANode := atom;
          Exit;
        end;
      end;
    '.':
      begin
        Inc(P);
        atom := NewNode(nkAny);
      end;
    '[':
      begin
        Inc(P);
        atom := ParseClass;
      end;
    '(':
      begin
        Inc(P);
        if Cur = '?' then
        begin
          case Peek(1) of
            ':':
              begin
                Inc(P, 2);
                atom := NewNode(nkNonCap);
              end;
            '=', '!':
              begin
                atom := NewNode(nkLook);
                if Peek(1) = '=' then atom.Look := 0 else atom.Look := 1;
                Inc(P, 2);
              end;
            '<':
              if (Peek(2) = '=') or (Peek(2) = '!') then
              begin
                atom := NewNode(nkLook);
                if Peek(2) = '=' then atom.Look := 2 else atom.Look := 3;
                Inc(P, 3);
                quantifiable := False;
              end
              else
              begin
                Inc(P, 2);
                nm := ParseGroupName;
                for i := 0 to High(Names) do
                  if Names[i] = nm then ReFail('duplicate capture group name');
                Inc(GroupNo);
                SetLength(Names, GroupNo);
                Names[GroupNo - 1] := nm;
                atom := NewNode(nkGroup);
                atom.Group := GroupNo;
              end;
          else
            ReFail('invalid group');
          end;
        end
        else
        begin
          Inc(GroupNo);
          SetLength(Names, GroupNo);
          Names[GroupNo - 1] := '';
          atom := NewNode(nkGroup);
          atom.Group := GroupNo;
        end;
        try
          atom.Add(ParseDisjunction);
          if Cur <> ')' then ReFail('unterminated group');
          Inc(P);
        except
          atom.Free;
          raise;
        end;
      end;
    ')': ReFail('unmatched '')''');
    '*', '+', '?': ReFail('nothing to repeat');
    '{':
      begin
        if BracedQuantifierAt(S, P, N) then ReFail('nothing to repeat');
        Inc(P);
        atom := NewNode(nkChar);
        atom.Ch := Ord(c);
      end;
  else
    { ExtendedPatternCharacter: the right bracket and brace too }
    Inc(P);
    atom := NewNode(nkChar);
    atom.Ch := Ord(c);
  end;
  if not TryQuantifier(mn, mx, greedy) then
  begin
    ANode := atom;
    Exit;
  end;
  if not quantifiable then
  begin
    atom.Free;
    ReFail('invalid quantifier');
  end;
  rep := NewNode(nkRepeat);
  rep.Add(atom);
  rep.Min := mn;
  rep.Max := mx;
  rep.Greedy := greedy;
  rep.FirstGroup := firstGroup;
  rep.AfterGroup := GroupNo + 1;
  ANode := rep;
end;

{ CountLeftCapturingParensWithin and whether there is a GroupName, by the
  pre-scan V8 makes: `(` not followed by `?` (or by `?<` not then `=` / `!`),
  outside classes and escapes }
procedure PreScan(const S: UnicodeString; out ACount: Integer; out ANamed: Boolean);
var
  p, n: Integer;
  inClass: Boolean;
begin
  ACount := 0;
  ANamed := False;
  n := Length(S);
  p := 1;
  inClass := False;
  while p <= n do
  begin
    case S[p] of
      '\': Inc(p);
      '[': inClass := True;
      ']': inClass := False;
      '(':
        if not inClass then
        begin
          if (p + 1 <= n) and (S[p + 1] = '?') then
          begin
            if (p + 2 <= n) and (S[p + 2] = '<') and (p + 3 <= n)
              and (S[p + 3] <> '=') and (S[p + 3] <> '!') then
            begin
              Inc(ACount);
              ANamed := True;
            end;
          end
          else
            Inc(ACount);
        end;
    end;
    Inc(p);
  end;
end;

{ ==================== the compiler ==================== }

procedure Compile(ARe: TTyJsRegExp; ANode: TNode; ABack: Boolean); forward;

procedure CompileSeq(ARe: TTyJsRegExp; ANode: TNode; ABack: Boolean);
var i: Integer;
begin
  if ABack then
    for i := High(ANode.Kids) downto 0 do Compile(ARe, ANode.Kids[i], ABack)
  else
    for i := 0 to High(ANode.Kids) do Compile(ARe, ANode.Kids[i], ABack);
end;

procedure Compile(ARe: TTyJsRegExp; ANode: TNode; ABack: Boolean);
var
  i, split, jmp, init, test, enter, look: Integer;
  jumps: array of Integer;
begin
  case ANode.Kind of
    nkEmpty: ;
    nkChar:
      begin
        i := ARe.Emit(roChar, ANode.Ch);
        ARe.FProg[i].Back := ABack;
      end;
    nkAny:
      begin
        i := ARe.Emit(roAny);
        ARe.FProg[i].Back := ABack;
      end;
    nkClass:
      begin
        i := ARe.Emit(roClass, ANode.ClassIndex);
        ARe.FProg[i].Back := ABack;
      end;
    nkSeq: CompileSeq(ARe, ANode, ABack);
    nkAlt:
      begin
        jumps := nil;
        for i := 0 to High(ANode.Kids) do
        begin
          if i < High(ANode.Kids) then
          begin
            split := ARe.Emit(roSplit);
            ARe.FProg[split].A := split + 1;
            Compile(ARe, ANode.Kids[i], ABack);
            jmp := ARe.Emit(roJmp);
            SetLength(jumps, Length(jumps) + 1);
            jumps[High(jumps)] := jmp;
            ARe.FProg[split].B := Length(ARe.FProg);
          end
          else
            Compile(ARe, ANode.Kids[i], ABack);
        end;
        for i := 0 to High(jumps) do ARe.FProg[jumps[i]].A := Length(ARe.FProg);
      end;
    nkGroup:
      begin
        { right to left the end is saved first }
        if ABack then ARe.Emit(roSave, ANode.Group * 2 + 1)
        else ARe.Emit(roSave, ANode.Group * 2);
        Compile(ARe, ANode.Kids[0], ABack);
        if ABack then ARe.Emit(roSave, ANode.Group * 2)
        else ARe.Emit(roSave, ANode.Group * 2 + 1);
      end;
    nkNonCap: Compile(ARe, ANode.Kids[0], ABack);
    nkLook:
      begin
        look := ARe.Emit(roLook, 0, ANode.Look);
        ARe.FProg[look].A := look + 1;
        Compile(ARe, ANode.Kids[0], ANode.Look >= 2);
        ARe.Emit(roMatch);
        ARe.FProg[look].C := Length(ARe.FProg);
      end;
    nkBol: ARe.Emit(roBol);
    nkEol: ARe.Emit(roEol);
    nkWordB: ARe.Emit(roWordB);
    nkNotWordB: ARe.Emit(roNotWordB);
    nkBackref:
      begin
        i := ARe.Emit(roBackref, ANode.Group);
        ARe.FProg[i].Back := ABack;
      end;
    nkRepeat:
      begin
        if ANode.Max = 0 then Exit;
        init := ARe.Emit(roLoopInit, ARe.FLoopCount);
        test := ARe.Emit(roLoopTest, ARe.FLoopCount, ANode.Min);
        ARe.FProg[test].C := ANode.Max;
        ARe.FProg[test].Greedy := ANode.Greedy;
        enter := ARe.Emit(roLoopEnter, ARe.FLoopCount, 0);
        ARe.FProg[enter].C := ANode.FirstGroup;
        ARe.FProg[enter].D := ANode.AfterGroup;
        ARe.FProg[test].D := enter;
        Inc(ARe.FLoopCount);
        Compile(ARe, ANode.Kids[0], ABack);
        i := ARe.Emit(roLoopEnd, ARe.FProg[init].A, ANode.Min);
        ARe.FProg[i].C := test;
        ARe.FProg[test].E := Length(ARe.FProg);
      end;
  end;
end;

{ ==================== TTyJsRegExp ==================== }

function TTyJsRegExp.Emit(AOp: TTyJsReOp; AA: Integer; AB: Integer): Integer;
begin
  Result := Length(FProg);
  SetLength(FProg, Result + 1);
  FProg[Result] := Default(TTyJsReInst);
  FProg[Result].Op := AOp;
  FProg[Result].A := AA;
  FProg[Result].B := AB;
end;

constructor TTyJsRegExp.Create(const APattern: UnicodeString);
var
  ps: TParser;
  root: TNode;
  i, k: Integer;
  found: Boolean;
begin
  inherited Create;
  FSource := APattern;
  ps := TParser.Create;
  root := nil;
  try
    ps.Owner := Self;
    ps.S := APattern;
    ps.N := Length(APattern);
    ps.P := 1;
    PreScan(APattern, ps.TotalGroups, ps.Named);
    root := ps.ParseDisjunction;
    if not ps.AtEnd then
    begin
      { only a `)` stops a disjunction early }
      ReFail('unmatched '')''');
    end;
    for i := 0 to High(ps.Backrefs) do
    begin
      found := False;
      for k := 0 to High(ps.Names) do
        if ps.Names[k] = ps.Backrefs[i].Name then
        begin
          ps.Backrefs[i].Kind := nkBackref;
          ps.Backrefs[i].Group := k + 1;
          found := True;
          Break;
        end;
      if not found then ReFail('invalid named capture referenced');
    end;
    FGroupCount := ps.GroupNo;
    Compile(Self, root, False);
    Emit(roMatch);
  finally
    root.Free;
    ps.Free;
  end;
end;

function TTyJsRegExp.ClassHas(AIndex: Integer; ACh: Word): Boolean;
var i: Integer;
begin
  Result := False;
  with FClasses[AIndex] do
  begin
    for i := 0 to High(Ranges) do
      if (ACh >= Ranges[i].Lo) and (ACh <= Ranges[i].Hi) then
      begin
        Result := True;
        Break;
      end;
    if Negate then Result := not Result;
  end;
end;

function IsWordUnit(C: WideChar): Boolean; inline;
begin
  Result := ((C >= 'a') and (C <= 'z')) or ((C >= 'A') and (C <= 'Z'))
    or ((C >= '0') and (C <= '9')) or (C = '_');
end;

function TTyJsRegExp.IsWordAt(APos: Integer): Boolean;
begin
  Result := (APos >= 0) and (APos < FLen) and IsWordUnit(FText[APos + 1]);
end;

type
  TTrailKind = (tkBranch, tkCap, tkLoopCount, tkLoopStart);
  TTrail = record
    Kind: TTrailKind;
    Slot: Integer;
    Value: Integer;
    { tkBranch: where to go on, and from }
    Pc, Pos: Integer;
  end;

function TTyJsRegExp.Run(APc, APos: Integer; out AEnd: Integer): Boolean;
var
  trail: array of TTrail;
  top: Integer;
  pc, pos, i, len, s0, e0, l, cnt, endPos: Integer;
  ok: Boolean;
  ch: WideChar;
  snap: array of Integer;

  procedure Push(AKind: TTrailKind; ASlot, AValue, APc2, APos2: Integer);
  begin
    if top >= Length(trail) then SetLength(trail, Length(trail) * 2 + 16);
    trail[top].Kind := AKind;
    trail[top].Slot := ASlot;
    trail[top].Value := AValue;
    trail[top].Pc := APc2;
    trail[top].Pos := APos2;
    Inc(top);
  end;

  procedure SetCap(ASlot, AValue: Integer);
  begin
    Push(tkCap, ASlot, FCaps[ASlot], 0, 0);
    FCaps[ASlot] := AValue;
  end;

  { undo back to the last branch; False when there is none }
  function Backtrack: Boolean;
  begin
    while top > 0 do
    begin
      Dec(top);
      case trail[top].Kind of
        tkCap: FCaps[trail[top].Slot] := trail[top].Value;
        tkLoopCount: FLoopCount_[trail[top].Slot] := trail[top].Value;
        tkLoopStart: FLoopStart[trail[top].Slot] := trail[top].Value;
        tkBranch:
          begin
            pc := trail[top].Pc;
            pos := trail[top].Pos;
            Exit(True);
          end;
      end;
    end;
    Result := False;
  end;

begin
  trail := nil;
  top := 0;
  pc := APc;
  pos := APos;
  AEnd := -1;
  while True do
  begin
    Inc(FSteps);
    if FSteps > cTyJsRegExpStepLimit then
      raise ETyJsRegExpError.Create('regular expression too expensive to run');
    ok := True;
    with FProg[pc] do
      case Op of
        roChar, roAny, roClass:
          begin
            if Back then
            begin
              if pos <= 0 then ok := False else ch := FText[pos];
            end
            else if pos >= FLen then ok := False
            else ch := FText[pos + 1];
            if ok then
              case Op of
                roChar: ok := Ord(ch) = A;
                roAny: ok := not ((ch = #10) or (ch = #13) or (ch = #$2028) or (ch = #$2029));
              else
                ok := ClassHas(A, Ord(ch));
              end;
            if ok then
            begin
              if Back then Dec(pos) else Inc(pos);
              Inc(pc);
            end;
          end;
        roSplit:
          begin
            Push(tkBranch, 0, 0, B, pos);
            pc := A;
          end;
        roJmp: pc := A;
        roSave:
          begin
            SetCap(A, pos);
            Inc(pc);
          end;
        roBol:
          if pos = 0 then Inc(pc) else ok := False;
        roEol:
          if pos = FLen then Inc(pc) else ok := False;
        roWordB, roNotWordB:
          begin
            ok := IsWordAt(pos - 1) <> IsWordAt(pos);
            if Op = roNotWordB then ok := not ok;
            if ok then Inc(pc);
          end;
        roBackref:
          begin
            s0 := FCaps[A * 2];
            e0 := FCaps[A * 2 + 1];
            if (s0 < 0) or (e0 < 0) then
              Inc(pc)
            else
            begin
              len := e0 - s0;
              if Back then
              begin
                if pos - len < 0 then ok := False
                else
                  for i := 0 to len - 1 do
                    if FText[s0 + i + 1] <> FText[pos - len + i + 1] then
                    begin
                      ok := False;
                      Break;
                    end;
                if ok then
                begin
                  Dec(pos, len);
                  Inc(pc);
                end;
              end
              else
              begin
                if pos + len > FLen then ok := False
                else
                  for i := 0 to len - 1 do
                    if FText[s0 + i + 1] <> FText[pos + i + 1] then
                    begin
                      ok := False;
                      Break;
                    end;
                if ok then
                begin
                  Inc(pos, len);
                  Inc(pc);
                end;
              end;
            end;
          end;
        roLook:
          begin
            snap := Copy(FCaps);
            ok := Run(A, pos, endPos);
            if (B = 0) or (B = 2) then
            begin
              if ok then
              begin
                { keep the lookaround's captures, undoable from here }
                for i := 0 to High(snap) do
                  if FCaps[i] <> snap[i] then
                  begin
                    l := FCaps[i];
                    FCaps[i] := snap[i];
                    SetCap(i, l);
                  end;
                pc := C;
              end;
            end
            else
            begin
              FCaps := snap;
              ok := not ok;
              if ok then pc := C;
            end;
          end;
        roLoopInit:
          begin
            Push(tkLoopCount, A, FLoopCount_[A], 0, 0);
            FLoopCount_[A] := 0;
            Push(tkLoopStart, A, FLoopStart[A], 0, 0);
            FLoopStart[A] := -1;
            Inc(pc);
          end;
        roLoopTest:
          begin
            cnt := FLoopCount_[A];
            if cnt < B then
              pc := D
            else if (C >= 0) and (cnt >= C) then
              pc := E
            else if Greedy then
            begin
              Push(tkBranch, 0, 0, E, pos);
              pc := D;
            end
            else
            begin
              Push(tkBranch, 0, 0, D, pos);
              pc := E;
            end;
          end;
        roLoopEnter:
          begin
            Push(tkLoopStart, A, FLoopStart[A], 0, 0);
            FLoopStart[A] := pos;
            { RepeatMatcher: the atom's captures are undefined at each go }
            for i := C to D - 1 do
            begin
              if FCaps[i * 2] >= 0 then SetCap(i * 2, -1);
              if FCaps[i * 2 + 1] >= 0 then SetCap(i * 2 + 1, -1);
            end;
            Inc(pc);
          end;
        roLoopEnd:
          begin
            { an optional go that consumed nothing fails }
            if (FLoopCount_[A] >= B) and (pos = FLoopStart[A]) then
              ok := False
            else
            begin
              Push(tkLoopCount, A, FLoopCount_[A], 0, 0);
              FLoopCount_[A] := FLoopCount_[A] + 1;
              pc := C;
            end;
          end;
        roMatch:
          begin
            AEnd := pos;
            Exit(True);
          end;
      end;
    if not ok then
      if not Backtrack then Exit(False);
  end;
end;

function TTyJsRegExp.Test(const AText: UnicodeString): Boolean;
var
  start, e, i: Integer;
begin
  FText := AText;
  FLen := Length(AText);
  FSteps := 0;
  SetLength(FCaps, (FGroupCount + 1) * 2);
  SetLength(FLoopCount_, FLoopCount);
  SetLength(FLoopStart, FLoopCount);
  Result := False;
  for start := 0 to FLen do
  begin
    for i := 0 to High(FCaps) do FCaps[i] := -1;
    if Run(0, start, e) then Exit(True);
  end;
end;

function TyJsRegExpCreate(const APattern: string): TTyJsRegExp;
begin
  Result := TTyJsRegExp.Create(UTF8Decode(APattern));
end;

function TyJsRegExpTest(ARe: TTyJsRegExp; const AText: string): Boolean;
begin
  Result := ARe.Test(UTF8Decode(AText));
end;

end.
