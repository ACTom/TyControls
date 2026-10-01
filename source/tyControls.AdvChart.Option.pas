unit tyControls.AdvChart.Option;
{$mode objfpc}{$H+}
{ TTyAdvanceChart — the option tree. THIS IS THE API.

  A chart is configured by an ECharts-shaped option object rather than by
  published properties, because ~1,950 option paths do not fit in an Object
  Inspector and because it makes ECharts' documentation, its gallery and a decade
  of answers on the internet usable as-is.

  RELAXED JSON, NOT STRICT. ECharts configs in the wild are JS object literals:
  unquoted keys, single quotes, trailing commas, comments. Requiring strict JSON
  would make "paste an ECharts config" -- the entire reason to choose an option
  tree -- false. FPC's own fcl-json already accepts all of that outside strict
  mode; verified empirically rather than assumed, and there is no hand-written
  JSON5 lexer here as a result.

  TWO WAYS IN. SetOptionText replaces the option WHOLE (ECharts' notMerge);
  MergeOptionText merges into it the way a setOption without notMerge does --
  components and series mapped by id, name and index, objects merged deeply
  (OptionMerge, [Batch 95]). The models' ids and names live beside the tree in
  Keys: the tree alone cannot say which series a renamed one was. replaceMerge
  and its index holes are not here yet.

  A REJECTED OPTION LEAVES NO OPTION. The tree goes and Error says why, so the
  chart is blank rather than showing something the option no longer says. The
  earlier rule kept the last good tree, for an editor that re-applied text on
  every keystroke; the editor that was actually built is modal and writes back
  on OK, so what the rule bought was a control whose picture and property
  disagreed with nothing on screen admitting it.

  LCL-free: SysUtils, Classes and fcl-json only. }
interface
uses SysUtils, Classes, fpjson, jsonparser, jsonscanner,
  tyControls.AdvChart.OptionMerge;

type
  TTyOptionError = record
    { True when there IS an error. A record rather than a nil check so the
      message and position survive alongside the last good tree. }
    Failed: Boolean;
    Message: string;
    Line, Col: Integer;
  end;

  TTyChartOption = class
  private
    FRoot: TJSONData;
    FText: string;
    FError: TTyOptionError;
    FKeys: TTyOptionKeys;
    { the option the last merge took in, kept for its report }
    FMerged: TJSONData;
    procedure SetError(const AMsg: string; ALine, ACol: Integer);
    procedure ClearError;
    { AText parsed, or False with Error set and AParsed nil }
    function ParseText(const AText: string; out AParsed: TJSONData): Boolean;
    function KeyOf(const AMainType: string; AIndex: Integer; out AKey: TTyOptionKey): Boolean;
  public
    constructor Create;
    destructor Destroy; override;

    { Replace the whole option. Returns False on a parse error, in which case
      the tree is DROPPED -- there is no option until one parses -- and Error
      describes what went wrong. FText keeps its last parsed value; the control
      is what remembers the text a host wrote. }
    function SetOptionText(const AText: string): Boolean;
    procedure Clear;

    { MERGE AText into the option, as upstream's setOption without notMerge
      [Batch 95]. With no option yet (or one that is no object) it is the
      first setOption: SetOptionText. A text that does not parse, is no
      object, or carries one id twice in a main type is REFUSED: the option
      stays as it was and Error says why -- unlike SetOptionText, because a
      merge is an edit of what is shown, not a declaration of it. AReport
      says what became of every slot; its NewOpt entries point into the
      merged-in option, which is kept until the next set, merge or clear. }
    function MergeOptionText(const AText: string; ABefore: TTyMergeBeforeComponent;
      out AReport: TTyMergeReport): Boolean;
    { THE MODELS: the id, name and subType upstream's model at that index has
      ('' where there is none). }
    function ComponentId(const AMainType: string; AIndex: Integer): string;
    function ComponentModelName(const AMainType: string; AIndex: Integer): string;
    function ComponentSubType(const AMainType: string; AIndex: Integer): string;
    { the merged option, shaped as upstream's getOption shapes it }
    function OptionJson: string;
    property Keys: TTyOptionKeys read FKeys;

    { Resolve a dotted/indexed path -- 'series[0].itemStyle.color'. nil when any
      step is missing, which is the normal case for an option nobody set, not an
      error. }
    function Find(const APath: string): TJSONData;
    function Has(const APath: string): Boolean;

    { Typed reads with a default. The default is what the theme or the series
      type decided; these never raise, because a chart must draw something when
      an option is absent or is the wrong type. }
    function GetStr(const APath: string; const ADefault: string): string;
    function GetInt(const APath: string; ADefault: Integer): Integer;
    function GetFloat(const APath: string; ADefault: Double): Double;
    function GetBool(const APath: string; ADefault: Boolean): Boolean;
    { Length of the array at APath; 0 when it is absent or is not an array. }
    function CountAt(const APath: string): Integer;

    { ---- component slots ----
      A top-level component may be written as a bare object OR as an array, and
      the two mean the same thing: ECharts normalises with normalizeToArray
      before anything reads it (Global.ts:369). Most of its gallery, and most of
      a decade of answers on the internet, write the bare form.

      CountAt deliberately does NOT normalise -- an object is not an array, and
      a test pins that -- so reaching for it here is the bug this pair exists to
      prevent: a bare object yields zero components and zero diagnostics, and
      the chart silently draws nothing.

      AMainType is a single root key ('series', 'xAxis', 'grid'), not a path:
      normalisation is a rule about component SLOTS, not about every array in
      the tree. `data: 5` is not a one-element data array and must not become one. }
    function ComponentCount(const AMainType: string): Integer;
    function ComponentAt(const AMainType: string; AIndex: Integer): TJSONData;

    property Root: TJSONData read FRoot;
    property Text: string read FText;
    property Error: TTyOptionError read FError;
  end;

{ Does this text look like it contains a JS function value? Used to turn
  fcl-json's correct-but-bare "unexpected token" into a message that says what to
  write instead. Exported so the design-time editor can warn BEFORE parsing. }
function TyOptionTextHasFunction(const AText: string): Boolean;

{ A fontWeight as a label reads one: 'bold' and 'bolder' 700, 'normal' 400,
  a number rounded into 1..1000; anything else leaves ADefault. }
function TyFontWeightOf(AData: TJSONData; ADefault: Integer): Integer;

{ A fontSize as zrender's parseFontSize takes it, as a logical size in CSS px
  (tyControls.FontUnits): a number, a string of a number ('14'), or a string
  with its px ('14px'); ADefault for anything else, and for a size that is
  not positive. [Batch 83] }
function TyOptFontSize(AData: TJSONData; ADefault: Integer): Integer;

implementation

uses
  { Only for the diagnostic resourcestrings; kept out of the interface uses so
    the dependency stays one-way and invisible to hosts. LazUTF8 is here for
    UnicodeToUTF8, used by the escape decoder below. }
  tyControls.StrConsts, LazUTF8, Math, tyControls.FontUnits;

function TyOptFontSize(AData: TJSONData; ADefault: Integer): Integer;
var
  s: string;
  v: Double;
  p: Integer;
  fs: TFormatSettings;
begin
  Result := ADefault;
  if AData = nil then Exit;
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  fs.ThousandSeparator := #0;
  v := NaN;
  if AData.JSONType = jtNumber then v := AData.AsFloat
  else if AData.JSONType = jtString then
  begin
    s := Trim(AData.AsString);
    p := Pos('px', s);
    if p > 0 then s := Trim(Copy(s, 1, p - 1));
    if not TryStrToFloat(s, v, fs) then v := NaN;
    { a period is the only separator a JSON number or a CSS size has }
    if (Pos(',', s) > 0) then v := NaN;
  end;
  if TyFontSizeFromPx(v) > 0 then Result := TyFontSizeFromPx(v);
end;

function TyFontWeightOf(AData: TJSONData; ADefault: Integer): Integer;
begin
  Result := ADefault;
  if AData = nil then Exit;
  if AData.JSONType = jtString then
  begin
    if (AData.AsString = 'bold') or (AData.AsString = 'bolder') then Result := 700
    else if AData.AsString = 'normal' then Result := 400;
  end
  else if (AData.JSONType = jtNumber) and not IsNan(AData.AsFloat)
    and (AData.AsFloat >= 1) and (AData.AsFloat <= 1000) then
    Result := Round(AData.AsFloat);
end;

function TyOptionTextHasFunction(const AText: string): Boolean;
var
  low: string;
begin
  low := LowerCase(AText);
  { Deliberately crude. Its only job is to improve a message that is already an
    error, so a false positive costs a slightly-off hint and a false negative
    costs the original message -- neither is a defect worth a JS tokeniser. }
  Result := (Pos('function', low) > 0) or (Pos('=>', low) > 0);
end;

constructor TTyChartOption.Create;
begin
  inherited Create;
  FRoot := nil;
  FText := '';
  ClearError;
end;

destructor TTyChartOption.Destroy;
begin
  FreeAndNil(FRoot);
  FreeAndNil(FMerged);
  inherited Destroy;
end;

procedure TTyChartOption.ClearError;
begin
  FError.Failed := False;
  FError.Message := '';
  FError.Line := 0;
  FError.Col := 0;
end;

procedure TTyChartOption.SetError(const AMsg: string; ALine, ACol: Integer);
begin
  FError.Failed := True;
  FError.Message := AMsg;
  FError.Line := ALine;
  FError.Col := ACol;
end;

procedure TTyChartOption.Clear;
begin
  FreeAndNil(FRoot);
  FreeAndNil(FMerged);
  FText := '';
  FKeys := nil;
  ClearError;
end;

{ fcl-json reports position inside the message text rather than in the exception
  type, so dig it out for an editor that wants to put a caret there. Best effort:
  a message we cannot read still reaches the caller intact. }
procedure ExtractPos(const AMsg: string; out ALine, ACol: Integer);
var
  i, j: Integer;
  s: string;
begin
  ALine := 0;
  ACol := 0;
  i := Pos('line ', AMsg);
  if i > 0 then
  begin
    j := i + 5;
    s := '';
    while (j <= Length(AMsg)) and (AMsg[j] in ['0'..'9']) do
    begin
      s := s + AMsg[j];
      Inc(j);
    end;
    ALine := StrToIntDef(s, 0);
  end;
  i := Pos('Pos ', AMsg);
  if i > 0 then
  begin
    j := i + 4;
    s := '';
    while (j <= Length(AMsg)) and (AMsg[j] in ['0'..'9']) do
    begin
      s := s + AMsg[j];
      Inc(j);
    end;
    ACol := StrToIntDef(s, 0);
  end;
end;

{ \uXXXX escapes decoded to UTF-8 before the parser sees them.

  FPC 3.2.2's jsonscanner loses ADJACENT escapes: `"\u4e2d\u6587"` decodes to
  four bytes rather than six, because the second escape overwrites the tail of
  the first. One character between them and it is fine -- which is why it went
  unnoticed, since two escapes in a row is precisely how a CJK string written in
  \u form looks, and this library's own demos carry Chinese labels.

  Only inside strings, and a doubled backslash is a literal backslash rather
  than the start of an escape -- so `"\\u0041"` stays the six characters the
  author wrote. Anything that is not a well-formed escape is passed through
  untouched, leaving the parser to report it.

  THE OUTPUT IS STILL JSON. An escape that decodes to the string's own quote
  or to a backslash is handed on escaped (`\"`, `\'`, `\\`) -- bare, the one
  would end the string and the other start a new escape. And comments are
  skipped whole: a quote inside `// ...` or `/* ... */` is not the start of a
  string. [Batch 75] }
{ THE DEEPEST NESTING THE PARSER IS HANDED. FPC 3.2.2's jsonreader recurses
  once per array or object, so text nested a few hundred thousand deep
  overflows the stack -- uncatchable on Win64, SIGSEGV on Linux -- and takes
  the IDE down with the chart. A real option is a few dozen deep; a tree or
  treemap's `children` add two per level, so this leaves room for a hierarchy
  over a hundred levels deep. [Batch 76] }
const
  TyOptionMaxNesting = 256;

{ Whether AText opens more than AMax arrays and objects at once, and where
  the first one too many is (1-based). Strings and comments are skipped as
  the pre-decode skips them, so a bracket in a label counts for nothing. }
function TyJsonNestingExceeds(const AText: string; AMax: Integer;
  out ALine, ACol: Integer): Boolean;
var
  i, depth, line, lineStart: Integer;
  quote: Char;
begin
  Result := False;
  ALine := 0;
  ACol := 0;
  depth := 0;
  line := 1;
  lineStart := 1;
  i := 1;
  while i <= Length(AText) do
  begin
    case AText[i] of
      #10:
        begin
          Inc(line);
          lineStart := i + 1;
        end;
      '"', '''':
        begin
          quote := AText[i];
          Inc(i);
          while (i <= Length(AText)) and (AText[i] <> quote) do
          begin
            if AText[i] = '' then Inc(i)
            else if AText[i] = #10 then
            begin
              Inc(line);
              lineStart := i + 1;
            end;
            Inc(i);
          end;
        end;
      '/':
        if (i < Length(AText)) and (AText[i + 1] = '/') then
        begin
          while (i <= Length(AText)) and (AText[i] <> #10) do Inc(i);
          Continue;
        end
        else if (i < Length(AText)) and (AText[i + 1] = '*') then
        begin
          Inc(i, 2);
          while (i <= Length(AText))
            and not ((AText[i] = '*') and (i < Length(AText)) and (AText[i + 1] = '/')) do
          begin
            if AText[i] = #10 then
            begin
              Inc(line);
              lineStart := i + 1;
            end;
            Inc(i);
          end;
          Inc(i);
        end;
      '[', '{':
        begin
          Inc(depth);
          if depth > AMax then
          begin
            ALine := line;
            ACol := i - lineStart + 1;
            Exit(True);
          end;
        end;
      ']', '}':
        if depth > 0 then Dec(depth);
    end;
    Inc(i);
  end;
end;

function TyDecodeUnicodeEscapes(const AText: string): string;
var
  i, code, lo: Integer;
  inStr: Boolean;
  quote: Char;

  { The four hex digits at i+2, or -1. }
  function HexAt(APos: Integer): Integer;
  var k, d: Integer;
  begin
    Result := -1;
    if APos + 3 > Length(AText) then Exit;
    Result := 0;
    for k := APos to APos + 3 do
    begin
      case AText[k] of
        '0'..'9': d := Ord(AText[k]) - Ord('0');
        'a'..'f': d := Ord(AText[k]) - Ord('a') + 10;
        'A'..'F': d := Ord(AText[k]) - Ord('A') + 10;
      else
        Exit(-1);
      end;
      Result := Result * 16 + d;
    end;
  end;

begin
  if Pos('\u', AText) = 0 then Exit(AText);
  Result := '';
  inStr := False;
  quote := '"';
  i := 1;
  while i <= Length(AText) do
  begin
    if not inStr then
    begin
      { a comment, copied as it is, to the end of its line or its close }
      if (AText[i] = '/') and (i < Length(AText)) and (AText[i + 1] = '/') then
      begin
        while (i <= Length(AText)) and not (AText[i] in [#10, #13]) do
        begin
          Result := Result + AText[i];
          Inc(i);
        end;
        Continue;
      end;
      if (AText[i] = '/') and (i < Length(AText)) and (AText[i + 1] = '*') then
      begin
        Result := Result + '/*';
        Inc(i, 2);
        while (i <= Length(AText))
          and not ((AText[i] = '*') and (i < Length(AText)) and (AText[i + 1] = '/')) do
        begin
          Result := Result + AText[i];
          Inc(i);
        end;
        if i <= Length(AText) then
        begin
          Result := Result + '*/';
          Inc(i, 2);
        end;
        Continue;
      end;
      if (AText[i] = '"') or (AText[i] = '''') then
      begin
        inStr := True;
        quote := AText[i];
      end;
      Result := Result + AText[i];
      Inc(i);
      Continue;
    end;

    if AText[i] = quote then
    begin
      inStr := False;
      Result := Result + AText[i];
      Inc(i);
      Continue;
    end;

    if AText[i] = '\' then
    begin
      { A doubled backslash is one literal backslash: the `u` after it is text,
        not an escape. Copying both keeps it that way. }
      if (i < Length(AText)) and (AText[i + 1] = 'u') then
      begin
        code := HexAt(i + 2);
        if code >= 0 then
        begin
          Inc(i, 6);
          { A high surrogate is half a character. Join it with its low half; a
            lone one is passed through as U+FFFD rather than emitted as an
            invalid sequence. }
          if (code >= $D800) and (code <= $DBFF) then
          begin
            lo := -1;
            if (i + 1 <= Length(AText)) and (AText[i] = '\')
              and (AText[i + 1] = 'u') then
              lo := HexAt(i + 2);
            if (lo >= $DC00) and (lo <= $DFFF) then
            begin
              code := $10000 + ((code - $D800) shl 10) + (lo - $DC00);
              Inc(i, 6);
            end
            else
              code := $FFFD;
          end
          else if (code >= $DC00) and (code <= $DFFF) then
            code := $FFFD;
          { the string's own quote, or a backslash, stays escaped }
          if (code = Ord(quote)) or (code = Ord('\')) then
            Result := Result + '\' + Chr(code)
          else
            Result := Result + UnicodeToUTF8(Cardinal(code));
          Continue;
        end;
      end;
      { Not an escape we handle -- copy the backslash AND what follows, so a
        `\"` cannot be mistaken for the end of the string. }
      Result := Result + AText[i];
      Inc(i);
      if i <= Length(AText) then
      begin
        Result := Result + AText[i];
        Inc(i);
      end;
      Continue;
    end;

    Result := Result + AText[i];
    Inc(i);
  end;
end;

function TTyChartOption.ParseText(const AText: string; out AParsed: TJSONData): Boolean;
var
  parser: TJSONParser;
  line, col: Integer;
  msg: string;
begin
  Result := False;
  AParsed := nil;
  { TOO DEEP IS REFUSED before the parser can recurse into it }
  if TyJsonNestingExceeds(AText, TyOptionMaxNesting, line, col) then
  begin
    SetError(Format(rsTyOptTooDeep, [TyOptionMaxNesting]), line, col);
    Exit(False);
  end;
  { DECODED FIRST -- see TyDecodeUnicodeEscapes. The scanner in FPC 3.2.2 drops
    bytes when two \uXXXX escapes are adjacent, which is what every CJK string
    written in escape form looks like. }
  parser := TJSONParser.Create(TyDecodeUnicodeEscapes(AText),
    [joUTF8, joComments, joIgnoreTrailingComma]);
  try
    try
      AParsed := parser.Parse;
    except
      on E: Exception do
      begin
        ExtractPos(E.Message, line, col);
        msg := E.Message;
        if TyOptionTextHasFunction(AText) then
          msg := msg + ' ' + rsTyOptFunctionValue;
        SetError(msg, line, col);
        AParsed := nil;
        Exit(False);
      end;
    end;
  finally
    parser.Free;
  end;
  Result := True;
end;

function TTyChartOption.SetOptionText(const AText: string): Boolean;
var
  parsed: TJSONData;
begin
  Result := False;
  if Trim(AText) = '' then
  begin
    { An empty option is a legitimate state -- a chart with nothing configured --
      and is not an error. }
    Clear;
    Exit(True);
  end;
  if not ParseText(AText, parsed) then
  begin
    { THE TREE GOES. An option that does not parse leaves NO chart, not the
      previous one.

      It used to keep the last good tree, on the theory that a design-time
      editor re-applies the text on every keystroke and blanking on each
      half-typed character would be unusable. That premise is gone: the
      editor is a modal dialog that writes back on OK, and the Object
      Inspector commits once per edit, so nothing ever pushes half-typed
      text at the control.

      What was left was a control that lies -- the property holding one
      option while the picture showed another, with nothing on screen
      saying so. At design time that reads as "my edit did nothing", which
      is a worse signal than a blank chart next to an error. }
    FreeAndNil(FRoot);
    FKeys := nil;
    Exit(False);
  end;
  FreeAndNil(FRoot);
  FreeAndNil(FMerged);
  FRoot := parsed;
  FText := AText;
  { new models: every id made afresh [Batch 95] }
  TyOptionKeysOfTree(FRoot, FKeys);
  ClearError;
  Result := True;
end;

function TTyChartOption.MergeOptionText(const AText: string;
  ABefore: TTyMergeBeforeComponent; out AReport: TTyMergeReport): Boolean;
var
  parsed: TJSONData;
  err: string;
begin
  AReport := Default(TTyMergeReport);
  { THE FIRST setOption is an init whatever its flag says }
  if not (FRoot is TJSONObject) then
  begin
    Result := SetOptionText(AText);
    Exit;
  end;
  Result := False;
  FreeAndNil(FMerged);
  if Trim(AText) = '' then parsed := TJSONObject.Create
  else if not ParseText(AText, parsed) then Exit(False);
  if not (parsed is TJSONObject) then
  begin
    parsed.Free;
    SetError(rsTyOptMergeNotObject, 0, 0);
    Exit(False);
  end;
  FMerged := parsed;
  if not TyOptionMerge(TJSONObject(FRoot), FKeys, TJSONObject(parsed), ABefore,
    AReport, err) then
  begin
    SetError(err, 0, 0);
    Exit(False);
  end;
  ClearError;
  Result := True;
end;

function TTyChartOption.KeyOf(const AMainType: string; AIndex: Integer;
  out AKey: TTyOptionKey): Boolean;
var i: Integer;
begin
  AKey := Default(TTyOptionKey);
  i := TyOptionKeyIndex(FKeys, AMainType);
  Result := (i >= 0) and (AIndex >= 0) and (AIndex <= High(FKeys[i].Items))
    and FKeys[i].Items[AIndex].Exists;
  if Result then AKey := FKeys[i].Items[AIndex];
end;

function TTyChartOption.ComponentId(const AMainType: string; AIndex: Integer): string;
var k: TTyOptionKey;
begin
  if KeyOf(AMainType, AIndex, k) then Result := k.Id else Result := '';
end;

function TTyChartOption.ComponentModelName(const AMainType: string; AIndex: Integer): string;
var k: TTyOptionKey;
begin
  if KeyOf(AMainType, AIndex, k) then Result := k.Name else Result := '';
end;

function TTyChartOption.ComponentSubType(const AMainType: string; AIndex: Integer): string;
var k: TTyOptionKey;
begin
  if KeyOf(AMainType, AIndex, k) then Result := k.SubType else Result := '';
end;

function TTyChartOption.OptionJson: string;
begin
  Result := TyOptionToJson(FRoot);
end;

{ Split one path step into a name and an optional index: 'series[0]' -> 'series',
  0. AIndex is -1 when the step carries no subscript. }
procedure SplitStep(const AStep: string; out AName: string; out AIndex: Integer);
var
  lb, rb: Integer;
begin
  AName := AStep;
  AIndex := -1;
  lb := Pos('[', AStep);
  if lb = 0 then Exit;
  rb := Pos(']', AStep);
  if rb <= lb then Exit;
  AName := Copy(AStep, 1, lb - 1);
  AIndex := StrToIntDef(Copy(AStep, lb + 1, rb - lb - 1), -1);
end;

function TTyChartOption.Find(const APath: string): TJSONData;
var
  steps: TStringList;
  i, idx: Integer;
  name: string;
  cur: TJSONData;
begin
  Result := nil;
  if (FRoot = nil) or (APath = '') then Exit;
  cur := FRoot;
  steps := TStringList.Create;
  try
    steps.Delimiter := '.';
    steps.StrictDelimiter := True;
    steps.DelimitedText := APath;
    for i := 0 to steps.Count - 1 do
    begin
      if steps[i] = '' then Exit(nil);
      SplitStep(steps[i], name, idx);
      if name <> '' then
      begin
        if not (cur is TJSONObject) then Exit(nil);
        cur := TJSONObject(cur).Find(name);
        if cur = nil then Exit(nil);
      end;
      if idx >= 0 then
      begin
        if not (cur is TJSONArray) then Exit(nil);
        if idx >= TJSONArray(cur).Count then Exit(nil);
        cur := TJSONArray(cur).Items[idx];
      end;
    end;
    Result := cur;
  finally
    steps.Free;
  end;
end;

function TTyChartOption.Has(const APath: string): Boolean;
begin
  Result := Find(APath) <> nil;
end;

function TTyChartOption.GetStr(const APath: string; const ADefault: string): string;
var d: TJSONData;
begin
  d := Find(APath);
  if (d = nil) or (d.JSONType in [jtNull, jtArray, jtObject]) then
    Exit(ADefault);
  Result := d.AsString;
end;

function TTyChartOption.GetInt(const APath: string; ADefault: Integer): Integer;
var d: TJSONData;
begin
  d := Find(APath);
  if (d = nil) or not (d.JSONType in [jtNumber, jtBoolean]) then
    Exit(ADefault);
  Result := d.AsInteger;
end;

function TTyChartOption.GetFloat(const APath: string; ADefault: Double): Double;
var d: TJSONData;
begin
  d := Find(APath);
  if (d = nil) or (d.JSONType <> jtNumber) then
    Exit(ADefault);
  Result := d.AsFloat;
end;

function TTyChartOption.GetBool(const APath: string; ADefault: Boolean): Boolean;
var d: TJSONData;
begin
  d := Find(APath);
  if (d = nil) or (d.JSONType <> jtBoolean) then
    Exit(ADefault);
  Result := d.AsBoolean;
end;

function TTyChartOption.CountAt(const APath: string): Integer;
var d: TJSONData;
begin
  d := Find(APath);
  if (d = nil) or not (d is TJSONArray) then
    Exit(0);
  Result := TJSONArray(d).Count;
end;

function TTyChartOption.ComponentCount(const AMainType: string): Integer;
var d: TJSONData;
begin
  if (FRoot = nil) or not (FRoot is TJSONObject) then Exit(0);
  d := TJSONObject(FRoot).Find(AMainType);
  if d = nil then Exit(0);
  { jtNull is `xAxis: null` -- written, but written as nothing. }
  if d.JSONType = jtNull then Exit(0);
  if d is TJSONArray then Exit(TJSONArray(d).Count);
  Result := 1;
end;

function TTyChartOption.ComponentAt(const AMainType: string; AIndex: Integer): TJSONData;
var d: TJSONData;
begin
  Result := nil;
  if AIndex < 0 then Exit;
  if (FRoot = nil) or not (FRoot is TJSONObject) then Exit;
  d := TJSONObject(FRoot).Find(AMainType);
  if (d = nil) or (d.JSONType = jtNull) then Exit;
  if d is TJSONArray then
  begin
    if AIndex >= TJSONArray(d).Count then Exit;
    Exit(TJSONArray(d).Items[AIndex]);
  end;
  { A bare component IS index 0, and there is no index 1. }
  if AIndex = 0 then Result := d;
end;

end.
