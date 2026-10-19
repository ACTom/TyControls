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
  Keys: the tree alone cannot say which series a renamed one was. A merge
  may name main types for replaceMerge, whose unmatched models leave index
  HOLES -- a null entry in the tree, no model in Keys [Batch 97].

  MEDIA [Batch 107]: an option's `baseOption` / `media` are read apart
  (tyControls.AdvChart.Media) -- the tree is the base, the units are kept in
  Media -- and every setOption merges, after its base, the units the view
  size meets, each a merge of its own. MediaRecheck is the resize: the
  units merged again only when the set that applies has changed. The view
  size is the host's to keep current (SetViewSize, CSS px).

  THE TIMELINE'S FRAMES [Batch 129]: the root's `options`, kept beside the
  units; every setOption merges, after its base and before the units, the
  frame at the first timeline's currentIndex (getTimelineOption), and
  TimelineReset is the timelineChange action's resetOption('timeline'):
  that frame merged alone.

  A REJECTED OPTION LEAVES NO OPTION. The tree goes and Error says why, so the
  chart is blank rather than showing something the option no longer says. The
  earlier rule kept the last good tree, for an editor that re-applied text on
  every keystroke; the editor that was actually built is modal and writes back
  on OK, so what the rule bought was a control whose picture and property
  disagreed with nothing on screen admitting it.

  LCL-free: SysUtils, Classes and fcl-json only. }
interface
uses SysUtils, Classes, fpjson, jsonparser, jsonscanner,
  tyControls.AdvChart.OptionMerge, tyControls.AdvChart.Media;

type
  TTyOptionError = record
    { True when there IS an error. A record rather than a nil check so the
      message and position survive alongside the last good tree. }
    Failed: Boolean;
    Message: string;
    Line, Col: Integer;
  end;

  { Called after every merge one setOption or one resize does -- the base,
    then each media unit -- with that merge's report. [Batch 107] }
  TTyMergePassEvent = procedure(const AReport: TTyMergeReport) of object;

  TTyChartOption = class
  private
    FRoot: TJSONData;
    FText: string;
    FError: TTyOptionError;
    FKeys: TTyOptionKeys;
    { the option the last merge took in, kept for its report }
    FMerged: TJSONData;
    { [Batch 107] the media units and the indices last merged; the view
      size they are asked about (CSS px); the media options the last
      setOption or resize merged in, kept for their reports }
    FMedia: TTyMediaManager;
    FViewW, FViewH: Double;
    FMediaMerged: array of TJSONData;
    procedure DropMerged;
    { LegendModel.init: `selected` made after the keys it was given -- at
      the init, so a media merge in the same setOption lands after it }
    procedure LegendInitSelected(AIndex: Integer);
    procedure LegendsNewIn(const AReport: TTyMergeReport);
    { getMediaOption and the merges of what it hands over }
    function MergeMedia(const AReplaceMerge: array of string;
      ABefore: TTyMergeBeforeComponent; AAfter: TTyMergePassEvent): Boolean;
    { getTimelineOption and its merge: the frame at the first timeline's
      currentIndex [Batch 129] }
    function MergeFrame(const AReplaceMerge: array of string;
      ABefore: TTyMergeBeforeComponent; AAfter: TTyMergePassEvent): Boolean;
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
    function SetOptionText(const AText: string): Boolean; overload;
    { the same, its media merged with AReplaceMerge (upstream hands the
      setOption's replaceMerge to every merge after the init) and each
      merge reported to AAfter [Batch 107] }
    function SetOptionText(const AText: string; const AReplaceMerge: array of string;
      AAfter: TTyMergePassEvent): Boolean; overload;
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
      out AReport: TTyMergeReport): Boolean; overload;
    { the same with AReplaceMerge's main types merged in replaceMerge mode:
      only an id keeps a model, the rest leave holes [Batch 97] }
    function MergeOptionText(const AText: string; const AReplaceMerge: array of string;
      ABefore: TTyMergeBeforeComponent; out AReport: TTyMergeReport): Boolean; overload;
    { the same, every merge it does -- the base, then the media units that
      apply -- reported to AAfter; AReport is the base's [Batch 107] }
    function MergeOptionText(const AText: string; const AReplaceMerge: array of string;
      ABefore: TTyMergeBeforeComponent; AAfter: TTyMergePassEvent;
      out AReport: TTyMergeReport): Boolean; overload;
    { THE VIEW SIZE the media queries are asked about, CSS px [Batch 107] }
    procedure SetViewSize(AWidth, AHeight: Double);
    property ViewWidth: Double read FViewW;
    property ViewHeight: Double read FViewH;
    { A RESIZE (resetOption('media')): the units that apply at the view size
      merged, in order, when they are not the set merged last. True when
      anything was merged. [Batch 107] }
    function MediaRecheck(ABefore: TTyMergeBeforeComponent;
      AAfter: TTyMergePassEvent): Boolean;
    { resetOption('timeline') with a replaceMerge: the frame at the first
      timeline's currentIndex merged, with AReplaceMerge -- the timeline's
      own. True when a frame was merged. [Batch 129] }
    function TimelineReset(const AReplaceMerge: array of string;
      ABefore: TTyMergeBeforeComponent; AAfter: TTyMergePassEvent): Boolean;
    property Media: TTyMediaManager read FMedia;
    { False, with Error saying which, when a name is no component main type
      -- upstream asserts on it before it touches anything; the option is
      left as it was. [Batch 97] }
    function CheckReplaceMerge(const AReplaceMerge: array of string): Boolean;
    { refuse a setOption for AMsg: the option is left as it was }
    procedure Refuse(const AMsg: string);
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
    { THE PIECE THE LAST MERGE MERGED IN (its base option), nil after a
      set: what the aria preprocessor reads per setOption [Batch 131] }
    property MergedPiece: TJSONData read FMerged;
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

{ Model.getShallow(key) on a component or series model whose option has no
  default for AKey [F4c]: its own value unless that is null or undefined,
  then the option ROOT's -- the GlobalModel is every component's parent, so
  a root `silent` or `progressive` reaches every series. nil when neither
  has a value. }
function TyGetShallowRoot(ANode: TJSONData; ARoot: TJSONData;
  const AKey: string): TJSONData;
{ JavaScript truthiness of an option value: nil, null, false, 0, NaN and ''
  are false. }
function TyOptTruthy(AData: TJSONData): Boolean;

{ THE NESTING GUARD every JSON text a host hands the chart passes before
  fpjson recurses into it -- the option, a merge, the setOption opts, an
  action payload, an event query. See TyJsonNestingExceeds. }
const
  TyOptionMaxNesting = 256;

function TyJsonNestingExceeds(const AText: string; AMax: Integer;
  out ALine, ACol: Integer): Boolean;

{ THE READER SetOptionText uses, on its own: the nesting guard, the escape
  pre-decode, fcl-json in relaxed mode -- and nothing after it. No
  preprocessor, no media, no merge, no legend `selected` made up: the tree
  exactly as written. The design-time series editor reads the user's text
  with it [Batch 143], because what it writes back is a patch against what
  is THERE, and a tree the preprocessors had touched would differ from the
  text before anyone edited anything.

  False with AError set -- the message and position SetOptionText would
  give -- when the text does not parse. True with AData nil for text with
  no value in it (empty, blanks, comments only). }
function TyOptionParseRaw(const AText: string; out AData: TJSONData;
  out AError: TTyOptionError): Boolean;

{ Every float node of ARoot (parsed from AText) given the value JavaScript's
  Number() gives its token -- see the implementation. TyOptionParseRaw does
  it to every tree it parses. }
procedure TyJsonFixNumbers(const AText: string; ARoot: TJSONData);

{ [R2-J] backwardCompat's text-style compatibility (preprocessor/helper/
  compatStyle.ts, every compatTextStyle it calls): a label written the ec2
  way, its text style under `textStyle`, has each text-style key of it
  copied up into the label. AOption is changed in place, as upstream changes
  the option it is given. }
procedure TyCompatTextStyle(AOption: TJSONObject);

implementation

uses
  { Only for the diagnostic resourcestrings; kept out of the interface uses so
    the dependency stays one-way and invisible to hosts. LazUTF8 is here for
    UnicodeToUTF8, used by the escape decoder below. }
  tyControls.StrConsts, LazUTF8, Math, tyControls.FontUnits,
  tyControls.AdvChart.Scale, tyControls.AdvChart.Data;

function TyGetShallowRoot(ANode: TJSONData; ARoot: TJSONData;
  const AKey: string): TJSONData;
begin
  Result := nil;
  if ANode is TJSONObject then Result := TJSONObject(ANode).Find(AKey);
  if (Result <> nil) and (Result.JSONType <> jtNull) then Exit;
  if ARoot is TJSONObject then Result := TJSONObject(ARoot).Find(AKey)
  else Result := nil;
  if (Result <> nil) and (Result.JSONType = jtNull) then Result := nil;
end;

function TyOptTruthy(AData: TJSONData): Boolean;
begin
  if AData = nil then Exit(False);
  case AData.JSONType of
    jtNull: Result := False;
    jtBoolean: Result := AData.AsBoolean;
    jtNumber: Result := (not IsNan(AData.AsFloat)) and (AData.AsFloat <> 0);
    jtString: Result := AData.AsString <> '';
  else
    Result := True;
  end;
end;

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
  FMedia := TTyMediaManager.Create;
  ClearError;
end;

destructor TTyChartOption.Destroy;
begin
  FreeAndNil(FRoot);
  DropMerged;
  FreeAndNil(FMedia);
  inherited Destroy;
end;

procedure TTyChartOption.DropMerged;
var i: Integer;
begin
  FreeAndNil(FMerged);
  for i := 0 to High(FMediaMerged) do FMediaMerged[i].Free;
  FMediaMerged := nil;
end;

procedure TTyChartOption.LegendInitSelected(AIndex: Integer);
var
  node: TJSONData;
  k: Integer;
begin
  node := ComponentAt('legend', AIndex);
  if not (node is TJSONObject) then Exit;
  if TJSONObject(node).Find('selected') is TJSONObject then Exit;
  k := TJSONObject(node).IndexOfName('selected');
  if k >= 0 then TJSONObject(node).Delete(k);
  TJSONObject(node).Add('selected', TJSONObject.Create);
end;

procedure TTyChartOption.LegendsNewIn(const AReport: TTyMergeReport);
var si, j: Integer;
begin
  si := TyMergeSlotsIndex(AReport, 'legend');
  if si < 0 then Exit;
  for j := 0 to High(AReport.Slots[si].Fate) do
    if AReport.Slots[si].Fate[j] = mfNew then LegendInitSelected(j);
end;

procedure TTyChartOption.SetViewSize(AWidth, AHeight: Double);
begin
  FViewW := AWidth;
  FViewH := AHeight;
end;

function TTyChartOption.MergeMedia(const AReplaceMerge: array of string;
  ABefore: TTyMergeBeforeComponent; AAfter: TTyMergePassEvent): Boolean;
var
  pend: TTyMediaPendingArray;
  i, n: Integer;
  rep: TTyMergeReport;
  err: string;
begin
  Result := False;
  if not (FRoot is TJSONObject) then Exit;
  pend := FMedia.Take(FViewW, FViewH);
  for i := 0 to High(pend) do
  begin
    { kept: the report's NewOpt points into it }
    n := Length(FMediaMerged);
    SetLength(FMediaMerged, n + 1);
    FMediaMerged[n] := pend[i].Option;
    { the ids were checked when the unit was read; the replaceMerge names
      when the setOption came in }
    if TyOptionMerge(TJSONObject(FRoot), FKeys, pend[i].Option, AReplaceMerge,
      not pend[i].IsDefault, ABefore, rep, err) then
    begin
      Result := True;
      LegendsNewIn(rep);
      if Assigned(AAfter) then AAfter(rep);
    end;
  end;
end;

function TTyChartOption.MediaRecheck(ABefore: TTyMergeBeforeComponent;
  AAfter: TTyMergePassEvent): Boolean;
var i: Integer;
begin
  { the options the last call merged in go: this one's reports are new }
  for i := 0 to High(FMediaMerged) do FMediaMerged[i].Free;
  FMediaMerged := nil;
  Result := MergeMedia([], ABefore, AAfter);
end;

function TTyChartOption.MergeFrame(const AReplaceMerge: array of string;
  ABefore: TTyMergeBeforeComponent; AAfter: TTyMergePassEvent): Boolean;
var
  tl, d: TJSONData;
  idx: Double;
  frame: TJSONObject;
  n: Integer;
  rep: TTyMergeReport;
  err: string;
begin
  Result := False;
  if not (FRoot is TJSONObject) then Exit;
  if FMedia.FrameCount = 0 then Exit;
  { getComponent('timeline'): the first slot, a hole is none }
  tl := ComponentAt('timeline', 0);
  if not (tl is TJSONObject) then Exit;
  { getCurrentIndex: the model's option, its default nought }
  d := TJSONObject(tl).Find('currentIndex');
  if d = nil then idx := 0
  else if d.JSONType = jtNumber then idx := d.AsFloat
  else Exit;
  { timelineOptions[index]: an index that is no element is undefined }
  if IsNan(idx) or IsInfinite(idx) or (Frac(idx) <> 0) or (idx < 0)
    or (idx >= FMedia.FrameCount) then Exit;
  frame := FMedia.Frame(Trunc(idx));
  if frame = nil then Exit;
  frame := TJSONObject(frame.Clone);
  { kept: the report's NewOpt points into it }
  n := Length(FMediaMerged);
  SetLength(FMediaMerged, n + 1);
  FMediaMerged[n] := frame;
  if TyOptionMerge(TJSONObject(FRoot), FKeys, frame, AReplaceMerge, True,
    ABefore, rep, err) then
  begin
    Result := True;
    LegendsNewIn(rep);
    if Assigned(AAfter) then AAfter(rep);
  end;
end;

function TTyChartOption.TimelineReset(const AReplaceMerge: array of string;
  ABefore: TTyMergeBeforeComponent; AAfter: TTyMergePassEvent): Boolean;
var i: Integer;
begin
  for i := 0 to High(FMediaMerged) do FMediaMerged[i].Free;
  FMediaMerged := nil;
  Result := MergeFrame(AReplaceMerge, ABefore, AAfter);
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
  DropMerged;
  FMedia.Clear;
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
  over a hundred levels deep. [Batch 76] The constant is in the interface:
  every other JSON entry point of the chart takes the same bound. }

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
var err: TTyOptionError;
begin
  Result := TyOptionParseRaw(AText, AParsed, err);
  if not Result then SetError(err.Message, err.Line, err.Col);
end;

function TyOptionParseRaw(const AText: string; out AData: TJSONData;
  out AError: TTyOptionError): Boolean;
var
  parser: TJSONParser;
  line, col: Integer;
  msg: string;

  procedure Fail(const AMsg: string; ALine, ACol: Integer);
  begin
    AError.Failed := True;
    AError.Message := AMsg;
    AError.Line := ALine;
    AError.Col := ACol;
  end;

begin
  Result := False;
  AData := nil;
  AError.Failed := False;
  AError.Message := '';
  AError.Line := 0;
  AError.Col := 0;
  { TOO DEEP IS REFUSED before the parser can recurse into it }
  if TyJsonNestingExceeds(AText, TyOptionMaxNesting, line, col) then
  begin
    Fail(Format(rsTyOptTooDeep, [TyOptionMaxNesting]), line, col);
    Exit(False);
  end;
  { DECODED FIRST -- see TyDecodeUnicodeEscapes. The scanner in FPC 3.2.2 drops
    bytes when two \uXXXX escapes are adjacent, which is what every CJK string
    written in escape form looks like. }
  parser := TJSONParser.Create(TyDecodeUnicodeEscapes(AText),
    [joUTF8, joComments, joIgnoreTrailingComma]);
  try
    try
      AData := parser.Parse;
    except
      on E: Exception do
      begin
        ExtractPos(E.Message, line, col);
        msg := E.Message;
        if TyOptionTextHasFunction(AText) then
          msg := msg + ' ' + rsTyOptFunctionValue;
        Fail(msg, line, col);
        AData := nil;
        Exit(False);
      end;
    end;
  finally
    parser.Free;
  end;
  TyJsonFixNumbers(AText, AData);
  Result := True;
end;

{ THE NUMBERS AGAIN, correctly rounded [Batch 146; every option since
  Milestone D9-D14]. fpjson reads a number through FPC's Val, which is not
  correctly rounded (about one in eight thousand decimals comes back a unit in
  the last place out), and JSON.parse reads every decimal exactly -- a map is
  thousands of them, and one is enough for a coordinate a bit off. So every
  number token of the text is found in document order and each float node of
  the tree, in the same order, is given the value JavaScript's Number() gives
  the token. The integers fpjson keeps are exact. Should the two orders not
  line up, nothing is changed.

  CHEAP: a token is only a place in the text until a float node asks for it,
  and the common decimal -- at most fifteen significant digits, a power of ten
  within 22 -- is read here the way TyJsDecimalToDouble's short path reads it
  (the digits and the power both exact Doubles, one IEEE operation), with no
  string made. A longer one (a coordinate printed to seventeen digits) keeps
  fpjson's value when TyJsDecimalIsNearest finds it between its two half-way
  points -- two exact comparisons -- and only the rest goes through
  TyJsToNumber's long division. }
procedure TyJsonFixNumbers(const AText: string; ARoot: TJSONData);
var
  starts, lens: array of Integer;
  n, i, k, len: Integer;
  ok: Boolean;

  procedure Collect;
  var j: Integer; c, q: Char;
  begin
    i := 1;
    len := Length(AText);
    n := 0;
    while i <= len do
    begin
      c := AText[i];
      if (c = '"') or (c = #39) then
      begin
        q := c;
        Inc(i);
        while (i <= len) and (AText[i] <> q) do
          { a backslash escapes the next character }
          if AText[i] = #92 then Inc(i, 2) else Inc(i);
        Inc(i);
      end
      else if (c = '/') and (i < len) and (AText[i + 1] = '/') then
      begin
        while (i <= len) and not (AText[i] in [#10, #13]) do Inc(i);
      end
      else if (c = '/') and (i < len) and (AText[i + 1] = '*') then
      begin
        Inc(i, 2);
        while (i < len) and not ((AText[i] = '*') and (AText[i + 1] = '/')) do Inc(i);
        Inc(i, 2);
      end
      else if c in ['-', '0'..'9'] then
      begin
        j := i;
        Inc(i);
        while (i <= len) and ((AText[i] in ['0'..'9', '.', 'e', 'E'])
          or ((AText[i] in ['+', '-']) and (AText[i - 1] in ['e', 'E']))) do Inc(i);
        if n >= Length(starts) then
        begin
          SetLength(starts, n * 2 + 64);
          SetLength(lens, n * 2 + 64);
        end;
        starts[n] := j;
        lens[n] := i - j;
        Inc(n);
      end
      else if c in ['a'..'z', 'A'..'Z', '_'] then
      begin
        while (i <= len) and (AText[i] in ['a'..'z', 'A'..'Z', '_', '0'..'9']) do Inc(i);
      end
      else
        Inc(i);
    end;
  end;

  { Number() of the token at AStart, ALen bytes long }
  function ValueAt(AStart, ALen: Integer; AOld: Double): Double;
  var
    p, stop, d, fracLen, ex, expo, intStart, intEnd, fracStart: Integer;
    neg, expNeg, seen: Boolean;
    m: QWord;
  begin
    p := AStart;
    stop := AStart + ALen;
    neg := AText[p] = '-';
    if neg then Inc(p);
    m := 0;
    d := 0;
    fracLen := 0;
    seen := False;
    intStart := p;
    fracStart := p;
    { the integer digits, then the fraction's: leading noughts are no
      significant digits, every other digit is (a trailing nought too, as
      TyJsDecimalToDouble counts it) }
    while (p < stop) and (AText[p] in ['0'..'9']) do
    begin
      if seen or (AText[p] <> '0') then
      begin
        seen := True;
        Inc(d);
        if d <= 15 then m := m * 10 + QWord(Ord(AText[p]) - Ord('0'));
      end;
      Inc(p);
    end;
    intEnd := p;
    if (p < stop) and (AText[p] = '.') then
    begin
      Inc(p);
      fracStart := p;
      while (p < stop) and (AText[p] in ['0'..'9']) do
      begin
        Inc(fracLen);
        if seen or (AText[p] <> '0') then
        begin
          seen := True;
          Inc(d);
          if d <= 15 then m := m * 10 + QWord(Ord(AText[p]) - Ord('0'));
        end;
        Inc(p);
      end;
    end;
    expo := 0;
    if (p < stop) and (AText[p] in ['e', 'E']) then
    begin
      Inc(p);
      expNeg := False;
      if (p < stop) and (AText[p] in ['+', '-']) then
      begin
        expNeg := AText[p] = '-';
        Inc(p);
      end;
      ex := 0;
      while (p < stop) and (AText[p] in ['0'..'9']) and (ex < 100000) do
      begin
        ex := ex * 10 + Ord(AText[p]) - Ord('0');
        Inc(p);
      end;
      if expNeg then expo := -ex else expo := ex;
    end;
    expo := expo - fracLen;
    if (p = stop) and (d <= 15) and (expo >= -22) and (expo <= 22) then
    begin
      if d = 0 then Result := 0
      else if expo >= 0 then Result := Double(m) * TyJsPow10(expo)
      else Result := Double(m) / TyJsPow10(-expo);
      if neg then Result := -Result;
    end
    else if (p = stop) and (d > 15) and TyJsDecimalIsNearest(
      Copy(AText, intStart, intEnd - intStart) + Copy(AText, fracStart, fracLen),
      expo, Abs(AOld)) then
      Result := AOld
    else
      Result := TyJsToNumber(Copy(AText, AStart, ALen));
  end;

  procedure Walk(AData: TJSONData; AApply: Boolean);
  var m: Integer;
  begin
    if not ok then Exit;
    case AData.JSONType of
      jtArray, jtObject:
        for m := 0 to AData.Count - 1 do Walk(AData.Items[m], AApply);
      jtNumber:
        begin
          if k >= n then
          begin
            ok := False;
            Exit;
          end;
          if AApply and (AData is TJSONFloatNumber) then
            AData.AsFloat := ValueAt(starts[k], lens[k], AData.AsFloat);
          Inc(k);
        end;
    end;
  end;

begin
  if ARoot = nil then Exit;
  starts := nil;
  lens := nil;
  Collect;
  { first count, then write: a mismatch anywhere leaves the tree alone }
  ok := True;
  k := 0;
  Walk(ARoot, False);
  if not ok or (k <> n) then Exit;
  k := 0;
  Walk(ARoot, True);
end;

{ ==================== the brush preprocessor [Batch 127] ====================

  component/brush/preprocessor.ts, run over every option unit the
  preprocessors see (the base and the media with a query): a brush
  component brings the toolbox's brush feature. The first toolbox (one is
  made, with an empty feature object, when the option has none) gets
  `feature.brush.type`
  -- its own list, the brush components' `toolbox` lists appended, the
  duplicates dropped by their string; a new option (the first setOption, a
  notMerge) whose list is still empty takes rect, polygon, keep and clear.
  Where upstream would throw (a feature that is no object, a type that is
  no array) nothing is done. }

function PreJsKey(AData: TJSONData): string;
begin
  case AData.JSONType of
    jtString: Result := AData.AsString;
    jtNumber: Result := TyJsNumberToString(AData.AsFloat);
    jtBoolean: if AData.AsBoolean then Result := 'true' else Result := 'false';
    jtNull: Result := 'null';
  else
    Result := #1 + AData.AsJSON;
  end;
end;

function PreTruthy(AData: TJSONData): Boolean;
begin
  if AData = nil then Exit(False);
  case AData.JSONType of
    jtNull: Result := False;
    jtBoolean: Result := AData.AsBoolean;
    jtNumber: Result := (AData.AsFloat <> 0) and not IsNan(AData.AsFloat);
    jtString: Result := AData.AsString <> '';
  else
    Result := True;
  end;
end;

procedure TyBrushPreprocess(AOption: TJSONObject; AIsNew: Boolean);
var
  d, tbs, tbNode: TJSONData;
  brushes: array of TJSONData;
  spec: TJSONArray;
  toolbox, feature, brushF: TJSONObject;
  types, kept: TJSONArray;
  seen: TStringList;
  i, k: Integer;
  key: string;
begin
  if AOption = nil then Exit;
  d := AOption.Find('brush');
  brushes := nil;
  if d is TJSONArray then
  begin
    for i := 0 to d.Count - 1 do
    begin
      SetLength(brushes, Length(brushes) + 1);
      brushes[High(brushes)] := d.Items[i];
    end;
  end
  else if (d <> nil) and (d.JSONType <> jtNull) then
  begin
    SetLength(brushes, 1);
    brushes[0] := d;
  end;
  if Length(brushes) = 0 then Exit;
  spec := TJSONArray.Create;
  try
    for i := 0 to High(brushes) do
    begin
      if not (brushes[i] is TJSONObject) then Continue;
      tbs := TJSONObject(brushes[i]).Find('toolbox');
      if tbs is TJSONArray then
        for k := 0 to tbs.Count - 1 do spec.Add(tbs.Items[k].Clone);
    end;
    tbNode := AOption.Find('toolbox');
    toolbox := nil;
    if tbNode is TJSONArray then
    begin
      if (tbNode.Count > 0) and PreTruthy(tbNode.Items[0]) then
      begin
        if not (tbNode.Items[0] is TJSONObject) then Exit;
        toolbox := TJSONObject(tbNode.Items[0]);
      end;
    end
    else if PreTruthy(tbNode) then
    begin
      if not (tbNode is TJSONObject) then Exit;
      toolbox := TJSONObject(tbNode);
    end;
    if toolbox = nil then
    begin
      toolbox := TJSONObject.Create;
      toolbox.Add('feature', TJSONObject.Create);
      if AOption.IndexOfName('toolbox') >= 0 then AOption.Delete('toolbox');
      AOption.Add('toolbox', TJSONArray.Create([toolbox]));
    end;
    d := toolbox.Find('feature');
    if not PreTruthy(d) then
    begin
      if d <> nil then toolbox.Delete('feature');
      toolbox.Add('feature', TJSONObject.Create);
      d := toolbox.Find('feature');
    end;
    if not (d is TJSONObject) then Exit;
    feature := TJSONObject(d);
    d := feature.Find('brush');
    if not PreTruthy(d) then
    begin
      if d <> nil then feature.Delete('brush');
      feature.Add('brush', TJSONObject.Create);
      d := feature.Find('brush');
    end;
    if not (d is TJSONObject) then Exit;
    brushF := TJSONObject(d);
    d := brushF.Find('type');
    if not PreTruthy(d) then
    begin
      if d <> nil then brushF.Delete('type');
      brushF.Add('type', TJSONArray.Create);
      d := brushF.Find('type');
    end;
    if not (d is TJSONArray) then Exit;
    types := TJSONArray(d);
    for k := 0 to spec.Count - 1 do types.Add(spec.Items[k].Clone);
    { removeDuplicates by the item's string }
    seen := TStringList.Create;
    kept := TJSONArray.Create;
    try
      { by bytes, as upstream keys a name: the locale compare took
        U+00C5 and U+212B for one letter, and whatever came after [P2] }
      seen.UseLocale := False;
      seen.Sorted := True;
      seen.CaseSensitive := True;
      for k := 0 to types.Count - 1 do
      begin
        key := PreJsKey(types.Items[k]);
        if seen.IndexOf(key) >= 0 then Continue;
        seen.Add(key);
        kept.Add(types.Items[k].Clone);
      end;
      types.Clear;
      for k := 0 to kept.Count - 1 do types.Add(kept.Items[k].Clone);
    finally
      kept.Free;
      seen.Free;
    end;
    if AIsNew and (types.Count = 0) then
    begin
      types.Add('rect');
      types.Add('polygon');
      types.Add('keep');
      types.Add('clear');
    end;
  finally
    spec.Free;
  end;
end;

{ zrUtil.merge(target, source, false): a key the target lacks is a clone of
  the source's; two plain objects recurse; anything else stays the target's }
procedure PreMergeKeep(ATarget, ASource: TJSONObject);
var
  i, k: Integer;
  key: string;
  sp, tp: TJSONData;
begin
  if (ATarget = nil) or (ASource = nil) then Exit;
  for i := 0 to ASource.Count - 1 do
  begin
    key := ASource.Names[i];
    sp := ASource.Items[i];
    k := ATarget.IndexOfName(key);
    if k >= 0 then tp := ATarget.Items[k] else tp := nil;
    if (sp is TJSONObject) and (tp is TJSONObject) then
      PreMergeKeep(TJSONObject(tp), TJSONObject(sp))
    else if k < 0 then
      ATarget.Add(key, sp.Clone);
  end;
end;

{ normalizeToArray's item AIndex of AData: an array's own, a single value
  as item 0, nothing for null or absent }
function PreItem(AData: TJSONData; AIndex: Integer): TJSONData;
begin
  Result := nil;
  if (AData = nil) or (AData.JSONType = jtNull) then Exit;
  if AData is TJSONArray then
  begin
    if (AIndex >= 0) and (AIndex < AData.Count) then Result := TJSONArray(AData).Items[AIndex];
  end
  else if AIndex = 0 then
    Result := AData;
end;

function PreCount(AData: TJSONData): Integer;
begin
  if (AData = nil) or (AData.JSONType = jtNull) then Result := 0
  else if AData is TJSONArray then Result := AData.Count
  else Result := 1;
end;

{ parallelPreprocessor [Batch 128, C19]: createParallelIfNeeded -- with no
  truthy `parallel` and a series of type 'parallel' the option gets
  `parallel: [{}]` -- then mergeAxisOptionFromParallel: every parallelAxis
  object takes the parallelAxisDefault of the parallel its `parallelIndex
  || 0` names (in this option), under its own keys }
procedure TyParallelPreprocess(AOption: TJSONObject);
var
  ser, axes, pars, it, pd, def: TJSONData;
  i: Integer;
  has: Boolean;
  v: Double;
begin
  if AOption = nil then Exit;
  if not PreTruthy(AOption.Find('parallel')) then
  begin
    has := False;
    ser := AOption.Find('series');
    for i := 0 to PreCount(ser) - 1 do
    begin
      it := PreItem(ser, i);
      if (it is TJSONObject) and (TJSONObject(it).Find('type') <> nil)
        and (TJSONObject(it).Find('type').JSONType = jtString)
        and (TJSONObject(it).Find('type').AsString = 'parallel') then
        has := True;
    end;
    if has then
    begin
      if AOption.IndexOfName('parallel') >= 0 then AOption.Delete('parallel');
      AOption.Add('parallel', TJSONArray.Create([TJSONObject.Create]));
    end;
  end;
  axes := AOption.Find('parallelAxis');
  pars := AOption.Find('parallel');
  for i := 0 to PreCount(axes) - 1 do
  begin
    it := PreItem(axes, i);
    if not (it is TJSONObject) then Continue;
    pd := TJSONObject(it).Find('parallelIndex');
    if not PreTruthy(pd) then v := 0
    else if pd.JSONType = jtNumber then v := pd.AsFloat
    else Continue;
    if IsNan(v) or (Frac(v) <> 0) or (v < 0) or (v > MaxInt) then Continue;
    pd := PreItem(pars, Trunc(v));
    if not (pd is TJSONObject) then Continue;
    def := TJSONObject(pd).Find('parallelAxisDefault');
    if def is TJSONObject then PreMergeKeep(TJSONObject(it), TJSONObject(def));
  end;
end;

const
  { util/model.ts TEXT_STYLE_OPTIONS, in its order }
  cTextStyleOptions: array[0..27] of string = (
    'fontStyle', 'fontWeight', 'fontSize', 'fontFamily',
    'rich', 'tag', 'color', 'textBorderColor', 'textBorderWidth',
    'width', 'height', 'lineHeight', 'align', 'verticalAlign', 'baseline',
    'shadowColor', 'shadowBlur', 'shadowOffsetX', 'shadowOffsetY',
    'textShadowColor', 'textShadowBlur', 'textShadowOffsetX', 'textShadowOffsetY',
    'backgroundColor', 'borderColor', 'borderWidth', 'borderRadius', 'padding');

{ compatTextStyle(opt, propName) }
procedure CompatTextStyleOf(AOpt: TJSONData; const AProp: string);
var
  lab, ts: TJSONData;
  i, j, k: Integer;
begin
  if not (AOpt is TJSONObject) then Exit;
  lab := TJSONObject(AOpt).Find(AProp);
  if not (lab is TJSONObject) then Exit;
  ts := TJSONObject(lab).Find('textStyle');
  if not (ts is TJSONObject) then Exit;
  for i := 0 to High(cTextStyleOptions) do
  begin
    k := TJSONObject(ts).IndexOfName(cTextStyleOptions[i]);
    if k < 0 then Continue;
    { an assignment: a key already there keeps its place }
    j := TJSONObject(lab).IndexOfName(cTextStyleOptions[i]);
    if j >= 0 then TJSONObject(lab).Items[j] := TJSONObject(ts).Items[k].Clone
    else TJSONObject(lab).Add(cTextStyleOptions[i], TJSONObject(ts).Items[k].Clone);
  end;
end;

function CompatChild(AOpt: TJSONData; const AKey: string): TJSONData;
begin
  Result := nil;
  if AOpt is TJSONObject then Result := TJSONObject(AOpt).Find(AKey);
end;

{ compatEC3CommonStyles' text part: the label and the emphasis label }
procedure CompatCommon(AOpt: TJSONData);
begin
  if not (AOpt is TJSONObject) then Exit;
  CompatTextStyleOf(AOpt, 'label');
  CompatTextStyleOf(CompatChild(AOpt, 'emphasis'), 'label');
end;

procedure CompatEach(AList: TJSONData);
var i: Integer;
begin
  if not (AList is TJSONArray) then Exit;
  for i := 0 to AList.Count - 1 do CompatCommon(TJSONArray(AList).Items[i]);
end;

procedure CompatSeries(ASeries: TJSONObject);
var
  em, d, mk, it: TJSONData;
  i: Integer;
begin
  CompatTextStyleOf(ASeries, 'label');
  CompatTextStyleOf(ASeries, 'upperLabel');
  CompatTextStyleOf(ASeries, 'edgeLabel');
  em := ASeries.Find('emphasis');
  if PreTruthy(em) then
  begin
    CompatTextStyleOf(em, 'label');
    CompatTextStyleOf(em, 'upperLabel');
    CompatTextStyleOf(em, 'edgeLabel');
  end;
  if PreTruthy(ASeries.Find('markPoint')) then CompatCommon(ASeries.Find('markPoint'));
  if PreTruthy(ASeries.Find('markLine')) then CompatCommon(ASeries.Find('markLine'));
  if PreTruthy(ASeries.Find('markArea')) then CompatCommon(ASeries.Find('markArea'));
  d := ASeries.Find('data');
  if (ASeries.Get('type', '') = 'graph') then
  begin
    if not PreTruthy(d) then d := ASeries.Find('nodes');
    it := ASeries.Find('links');
    if not PreTruthy(it) then it := ASeries.Find('edges');
    CompatEach(it);
  end;
  CompatEach(d);
  mk := ASeries.Find('markPoint');
  if PreTruthy(mk) then CompatEach(CompatChild(mk, 'data'));
  mk := ASeries.Find('markLine');
  if PreTruthy(mk) and (CompatChild(mk, 'data') is TJSONArray) then
  begin
    d := CompatChild(mk, 'data');
    for i := 0 to d.Count - 1 do
    begin
      it := TJSONArray(d).Items[i];
      if it is TJSONArray then
      begin
        CompatCommon(PreItem(it, 0));
        CompatCommon(PreItem(it, 1));
      end
      else
        CompatCommon(it);
    end;
  end;
  if ASeries.Get('type', '') = 'gauge' then
  begin
    CompatTextStyleOf(ASeries, 'axisLabel');
    CompatTextStyleOf(ASeries, 'title');
    CompatTextStyleOf(ASeries, 'detail');
  end;
end;

procedure TyCompatTextStyle(AOption: TJSONObject);
const
  cAxes: array[0..6] of string = ('xAxis', 'yAxis', 'radiusAxis', 'angleAxis',
    'singleAxis', 'parallelAxis', 'radar');
var
  list, it, def: TJSONData;
  i, k: Integer;
begin
  if AOption = nil then Exit;
  list := AOption.Find('series');
  for i := 0 to PreCount(list) - 1 do
  begin
    it := PreItem(list, i);
    if it is TJSONObject then CompatSeries(TJSONObject(it));
  end;
  for k := 0 to High(cAxes) do
  begin
    list := AOption.Find(cAxes[k]);
    for i := 0 to PreCount(list) - 1 do
    begin
      it := PreItem(list, i);
      if not PreTruthy(it) then Continue;
      CompatTextStyleOf(it, 'axisLabel');
      CompatTextStyleOf(CompatChild(it, 'axisPointer'), 'label');
    end;
  end;
  list := AOption.Find('parallel');
  for i := 0 to PreCount(list) - 1 do
  begin
    def := CompatChild(PreItem(list, i), 'parallelAxisDefault');
    CompatTextStyleOf(def, 'axisLabel');
    CompatTextStyleOf(CompatChild(def, 'axisPointer'), 'label');
  end;
  list := AOption.Find('calendar');
  for i := 0 to PreCount(list) - 1 do
  begin
    it := PreItem(list, i);
    CompatTextStyleOf(it, 'dayLabel');
    CompatTextStyleOf(it, 'monthLabel');
    CompatTextStyleOf(it, 'yearLabel');
  end;
  list := AOption.Find('radar');
  for i := 0 to PreCount(list) - 1 do
    CompatTextStyleOf(PreItem(list, i), 'name');
  list := AOption.Find('geo');
  for i := 0 to PreCount(list) - 1 do
  begin
    it := PreItem(list, i);
    if not (it is TJSONObject) then Continue;
    CompatCommon(it);
    def := CompatChild(it, 'regions');
    if def is TJSONArray then CompatEach(def)
    else CompatCommon(def);
  end;
  list := AOption.Find('timeline');
  for i := 0 to PreCount(list) - 1 do CompatCommon(PreItem(list, i));
  { toObj: the first of an array, else the object }
  CompatTextStyleOf(PreItem(AOption.Find('axisPointer'), 0), 'label');
  CompatTextStyleOf(CompatChild(PreItem(AOption.Find('tooltip'), 0), 'axisPointer'), 'label');
end;

procedure PreprocessUnits(ABase: TJSONObject; const ASet: TTyMediaSet; AIsNew: Boolean);
var i: Integer;
begin
  { backwardCompat is the first preprocessor upstream registers [R2-J] }
  TyCompatTextStyle(ABase);
  TyParallelPreprocess(ABase);
  TyBrushPreprocess(ABase, AIsNew);
  for i := 0 to High(ASet.Units) do
    if ASet.Units[i].Option <> nil then
    begin
      TyCompatTextStyle(ASet.Units[i].Option);
      TyParallelPreprocess(ASet.Units[i].Option);
      TyBrushPreprocess(ASet.Units[i].Option, AIsNew);
    end;
end;

function TTyChartOption.SetOptionText(const AText: string): Boolean;
begin
  Result := SetOptionText(AText, [], nil);
end;

function TTyChartOption.SetOptionText(const AText: string;
  const AReplaceMerge: array of string; AAfter: TTyMergePassEvent): Boolean;
var
  parsed: TJSONData;
  base: TJSONObject;
  mset: TTyMediaSet;
  i: Integer;
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
    FMedia.Clear;
    Exit(False);
  end;
  FreeAndNil(FRoot);
  DropMerged;
  { A NEW MANAGER (notMerge): the base is the tree, the units the
    manager's [Batch 107] }
  mset := Default(TTyMediaSet);
  if parsed is TJSONObject then
  begin
    base := TJSONObject(parsed);
    TyParseRawOption(base, mset);
    { the preprocessors: a new option [Batch 127] }
    PreprocessUnits(base, mset, True);
    parsed := base;
  end;
  FMedia.Reset(mset);
  FRoot := parsed;
  FText := AText;
  { initBase seeds the series' list: a null entry takes no index [Batch 97] }
  TyOptionCompactSeries(FRoot);
  { new models: every id made afresh [Batch 95] }
  TyOptionKeysOfTree(FRoot, FKeys);
  for i := 0 to ComponentCount('legend') - 1 do LegendInitSelected(i);
  ClearError;
  { the timeline's frame, then the media that apply, merged over the fresh
    models: nothing kept outside the tree to write back [Batch 129] }
  MergeFrame(AReplaceMerge, nil, AAfter);
  MergeMedia(AReplaceMerge, nil, AAfter);
  Result := True;
end;

function TTyChartOption.MergeOptionText(const AText: string;
  ABefore: TTyMergeBeforeComponent; out AReport: TTyMergeReport): Boolean;
begin
  Result := MergeOptionText(AText, [], ABefore, AReport);
end;

function TTyChartOption.CheckReplaceMerge(const AReplaceMerge: array of string): Boolean;
var bad: string;
begin
  bad := TyOptionBadReplaceType(AReplaceMerge);
  Result := bad = '';
  if not Result then SetError(Format(rsTyOptReplaceMergeBadType, [bad]), 0, 0);
end;

procedure TTyChartOption.Refuse(const AMsg: string);
begin
  SetError(AMsg, 0, 0);
end;

function TTyChartOption.MergeOptionText(const AText: string;
  const AReplaceMerge: array of string; ABefore: TTyMergeBeforeComponent;
  out AReport: TTyMergeReport): Boolean;
begin
  Result := MergeOptionText(AText, AReplaceMerge, ABefore, nil, AReport);
end;

function TTyChartOption.MergeOptionText(const AText: string;
  const AReplaceMerge: array of string; ABefore: TTyMergeBeforeComponent;
  AAfter: TTyMergePassEvent; out AReport: TTyMergeReport): Boolean;
var
  parsed: TJSONData;
  base: TJSONObject;
  mset: TTyMediaSet;
  err: string;
begin
  AReport := Default(TTyMergeReport);
  if not CheckReplaceMerge(AReplaceMerge) then Exit(False);
  { THE FIRST setOption is an init whatever its flag says }
  if not (FRoot is TJSONObject) then
  begin
    Result := SetOptionText(AText, AReplaceMerge, AAfter);
    Exit;
  end;
  Result := False;
  DropMerged;
  if Trim(AText) = '' then parsed := TJSONObject.Create
  else if not ParseText(AText, parsed) then Exit(False);
  if not (parsed is TJSONObject) then
  begin
    parsed.Free;
    SetError(rsTyOptMergeNotObject, 0, 0);
    Exit(False);
  end;
  { the base and the units apart [Batch 107] }
  base := TJSONObject(parsed);
  TyParseRawOption(base, mset);
  { the preprocessors: not a new option [Batch 127] }
  PreprocessUnits(base, mset, False);
  FMerged := base;
  if not TyOptionMerge(TJSONObject(FRoot), FKeys, base, AReplaceMerge,
    ABefore, AReport, err) then
  begin
    TyMediaSetFree(mset);
    SetError(err, 0, 0);
    Exit(False);
  end;
  { the list substituted where the option has one, the default where it
    has one; the indices forgotten (mountOption) -- so what applies is
    merged again over the merged base }
  FMedia.Adopt(mset);
  FMedia.Mount;
  ClearError;
  LegendsNewIn(AReport);
  if Assigned(AAfter) then AAfter(AReport);
  { the frame of the merged timeline, then the media [Batch 129] }
  MergeFrame(AReplaceMerge, ABefore, AAfter);
  MergeMedia(AReplaceMerge, ABefore, AAfter);
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
