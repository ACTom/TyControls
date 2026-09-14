unit tyControls.AdvChart.Tooltip;
{$mode objfpc}{$H+}
{ The hover tooltip: what it says, how big it is, and where it goes.

  WHAT THIS UNIT IS NOT. It is not a window. Every other popup in this library
  is a real top-level form, and for a tooltip that follows the pointer that is
  the wrong shape: on GTK3/Wayland an already-mapped xdg_popup cannot be moved,
  so tracking the cursor means Hide -> reposition -> Show once per mouse move,
  and Wayland has no XShape, so a rounded box degrades to a square window with
  rounded corners painted inside it. Upstream has the same problem in reverse --
  its `richText` render mode exists precisely for hosts with no DOM -- and its
  answer is to draw the tooltip on the canvas. So does this.

  THE PRICE, STATED ONCE: a tooltip drawn inside the control cannot leave the
  control. That is `confine: true`, always, and it is a DELIBERATE DIVERGENCE --
  see TyTooltipBoxAt.

  RICHTEXT, NOT HTML. The two upstream renderers are not two skins of one
  layout; they differ in units (borderRadius 10 vs 5 for the same dot), in
  mechanism (CSS float vs padding + align), in what they honour (richText
  ignores borderWidth and textStyle.lineHeight) and in what they can do at all
  (no arrow, no transition). Where they disagree this follows richText, because
  richText is the one that was written for a canvas.

  PURE, like everything upstream of the control: SysUtils, Math, fpjson and the
  AdvChart units. No painter and no LCL. Colours arrive as numbers and the
  measuring is done through ITyTextMeasurer, so the whole of it is testable
  without a window -- which is the second reason for drawing rather than
  popping up, because a popup window is exactly what a headless test cannot
  look inside. }
interface
uses
  SysUtils, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Option,
  tyControls.AdvChart.Paint, tyControls.AdvChart.Color,
  tyControls.AdvChart.Measure;

type
  { `'none'` blocks a series-item tooltip and nothing else -- upstream lets a
    component tooltip through it deliberately. }
  TTyTooltipTrigger = (tttItem, tttAxis, tttNone);

  { FOUR VALUES, THREE BEHAVIOURS. `seriesAsc` falls through both of upstream's
    branches and does nothing at all -- it is behaviourally identical to
    writing no order, and it carries upstream's own `FIXME` beside it. Modelled
    as the default rather than as a fifth state, because a state nothing can
    observe is not a state. }
  TTyTooltipOrder = (ttoSeriesAsc, ttoSeriesDesc, ttoValueAsc, ttoValueDesc);

  { WHAT THE OPTION SAID, not what will be drawn. Every visual has a `Has`
    beside it because absence means "ask the theme", and a theme is not
    something this layer can see. }
  TTyTooltipSpec = record
    Show: Boolean;
    ShowContent: Boolean;
    AlwaysShowContent: Boolean;
    Trigger: TTyTooltipTrigger;
    { KEPT AS TEXT, not parsed into a set. Upstream matches it with a raw
      substring test at one site and with EQUALITY at another -- the default
      'mousemove|click|mousewheel' contains 'click' and yet is not treated as
      click by the second. A flag set cannot express that. }
    TriggerOn: string;
    Confine: Boolean;
    ShowDelayMs: Integer;
    HideDelayMs: Integer;
    { A template, or '@Name' for a registered handler -- see AdvChart.Handlers.
      HasFormatter is separate because `formatter: ''` is falsy upstream and
      does NOT override the default content. }
    Formatter: string;
    HasFormatter: Boolean;
    { `order` has NO default upstream -- it resolves to undefined, which
      short-circuits the sort entirely. So absence is a third thing, not
      `seriesAsc`. }
    Order: TTyTooltipOrder;
    HasOrder: Boolean;

    HasBackground: Boolean;
    Background: TTyChartColor;
    HasBorderColour: Boolean;
    BorderColour: TTyChartColor;
    HasBorderWidth: Boolean;
    BorderWidthLogical: Double;
    HasBorderRadius: Boolean;
    BorderRadiusLogical: Double;
    HasPadding: Boolean;
    PadLeft, PadTop, PadRight, PadBottom: Double;
    { textStyle is read WHOLESALE. Upstream's Model.get walks to the parent
      only when the entire resolved path is null, so a series-level
      `textStyle: {fontWeight:'bold'}` REPLACES the global object rather than
      merging into it, and the keys it did not write fall back to the
      renderer's own constants -- not to the global's values. Reproduced by
      taking every text key from the first cascade level that has a textStyle
      at all. }
    HasTextColour: Boolean;
    TextColour: TTyChartColor;
    HasTextSize: Boolean;
    TextSizeLogical: Double;
  end;

  { A dot, its size decided by which row it belongs to. `ttmSubItem` is the
    small one a multi-value row uses; nothing in this batch emits it, and it is
    declared because the marker's size table is upstream's and splitting the
    table later is how the two halves drift apart. }
  TTyTooltipMarker = (ttmNone, ttmItem, ttmSubItem);

  { THE MARKUP TREE, which is what upstream's default content actually is.

    There is no default string template. `'{a}<br/>{b}: {c}'` is not the 6.1
    default of anything -- the default is a tree of `section` and `nameValue`
    nodes, and the vertical spacing is computed FROM ITS SHAPE (see GapLevel).
    A port that started from a template string would have to invent the
    spacing, and would get the two-axis case wrong.

    An item tooltip is one section holding one nameValue. An axis tooltip is a
    headerless root holding one section per axis, each holding one nameValue
    per series -- which is why this is a tree and not a list, even though only
    the first shape is built today. }
  TTyTooltipBlock = class
  private
    FIsSection: Boolean;
    FHeader: string;
    FNoHeader: Boolean;
    FMarker: TTyTooltipMarker;
    FMarkerColour: TTyChartColor;
    FName: string;
    FNoName: Boolean;
    FValue: string;
    FNoValue: Boolean;
    FSortParam: Double;
    FBlocks: array of TTyTooltipBlock;
    function GetBlock(AIndex: Integer): TTyTooltipBlock;
    function GetBlockCount: Integer;
  public
    constructor CreateSection(const AHeader: string; ANoHeader: Boolean);
    constructor CreateNameValue(AMarker: TTyTooltipMarker;
      AMarkerColour: TTyChartColor; const AName: string; ANoName: Boolean;
      const AValue: string; ANoValue: Boolean);
    destructor Destroy; override;
    { TAKES OWNERSHIP, and answers the block it was given so a tree can be
      written as one expression. }
    function Add(ABlock: TTyTooltipBlock): TTyTooltipBlock;
    { Reverse this section's children in place. Upstream does it to the axis
      sections unconditionally and BEFORE `order` is read -- the two are
      independent operations on the same list, not two spellings of one. }
    procedure Reverse;
    { Sort this section's children by `order`.

      STABLE, because upstream's Array#sort is and ties therefore keep series
      order. And NaN sorts LAST in both directions: upstream's comparator
      treats an incomparable value as +Infinity ascending and -Infinity
      descending, which comes to the same place at the bottom either way. }
    procedure SortBlocks(AOrder: TTyTooltipOrder);
    { The vertical gap this node's children are separated by, 0..3, computed
      bottom-up from STRUCTURE rather than from depth -- leaves are 0 and the
      root is largest, which is the opposite of what the name suggests.

      CLAMPED AT 3, which upstream is not: its gap table has four entries and
      an index past the end yields `undefined`, which JavaScript renders as
      the literal text `undefinedpx`. In FPC that is a range error and takes
      the host's window with it. Built-in trees reach 2; only a hand-written
      formatter could exceed 3. }
    function GapLevel: Integer;
    property IsSection: Boolean read FIsSection;
    property Header: string read FHeader;
    property NoHeader: Boolean read FNoHeader;
    property Marker: TTyTooltipMarker read FMarker;
    property MarkerColour: TTyChartColor read FMarkerColour;
    property Name: string read FName;
    property NoName: Boolean read FNoName;
    property Value: string read FValue;
    property NoValue: Boolean read FNoValue;
    { What `order` sorts on: the series' FIRST inline value, raw, not the
      string that was rendered from it. NaN means this block has none -- which
      every section has, and every row built by a series that overrides its own
      tooltip markup. }
    property SortParam: Double read FSortParam write FSortParam;
    property BlockCount: Integer read GetBlockCount;
    property Blocks[AIndex: Integer]: TTyTooltipBlock read GetBlock; default;
  end;

  { WHAT THE THEME DECIDED, resolved by the control and handed down. Nothing in
    here has a literal default: the control fills every field from the style it
    resolved for the tooltip's own type key. }
  TTyTooltipInk = record
    { The words that name a thing -- a header, a series name, a category. }
    NameFontName: string;
    { INTEGER, because that is what the measurer and the painter both take --
      a fractional point size measured one way and drawn another is a pixel of
      disagreement per label. }
    NameSizeLogical: Integer;
    NameWeight: Integer;
    NameColour: TTyChartColor;
    { The number. A separate key rather than a second weight of the first:
      upstream separates them by weight alone (400 against 900) and the whole
      typographic hierarchy of the box is in that one difference, so it has to
      be something a theme can reach. }
    ValueFontName: string;
    ValueSizeLogical: Integer;
    ValueWeight: Integer;
    ValueColour: TTyChartColor;
    LineHeightLogical: Double;
    { The dot. Upstream's richText writes width 10 / radius 5 -- TRUE radii.
      The html renderer writes border-radius 10px for the same dot and CSS
      clamps it to a circle; copying the CSS number doubles it. }
    MarkerSizeLogical: Double;
    MarkerGapLogical: Double;
    { The minimum space between a name and the value to its right, and the
      narrower one used when there is no name for it to be far from. }
    GutterLogical: Double;
    GutterCloseLogical: Double;
  end;

  TTyTooltipRunKind = (ttrText, ttrMarker);

  { One piece of one line, already carrying everything needed to draw it. }
  TTyTooltipRun = record
    Kind: TTyTooltipRunKind;
    Text: string;
    FontName: string;
    FontSizeLogical: Integer;
    FontWeight: Integer;
    Colour: TTyChartColor;
    { A marker run's diameter, logical px. Its own field rather than borrowed
      from the font size: a dot is not text and the two are scaled by
      different things. }
    MarkerSizeLogical: Double;
    { True for the value: it is pushed against the right edge of the WIDEST
      line in the box, not of its own line. That is upstream's rule in both
      modes -- CSS float:right in one, align:'right' with no width in the
      other -- and it is what makes a column of values line up. }
    AlignRight: Boolean;
    { Set once measured. }
    X, W: Double;
  end;

  TTyTooltipLine = record
    Runs: array of TTyTooltipRun;
    { How many EMPTY lines come before this one. A gap level of 1 means the
      blocks are on consecutive lines, not that there is a blank between them:
      upstream's richText gaps are 0/1/2/3 NEWLINES, which is 0/0/1/2 blank
      lines. Reading that table as blank lines puts a surplus line in every
      tooltip. }
    BlankLinesBefore: Integer;
    { The widest run row, filled by TyTooltipMeasure. }
    LeftW, RightW: Double;
  end;
  TTyTooltipLineArray = array of TTyTooltipLine;

{ ---- the option ---- }
function TyTooltipSpecDefault: TTyTooltipSpec;
{ The cascade, innermost first: the data item's own tooltip, then the series',
  then the global one. Upstream builds a prototype chain rather than a deep
  merge, and reads each key from the nearest level that HAS it -- so an
  object-valued key such as textStyle is replaced wholesale rather than merged.

  ARawIndex < 0 skips the data-item level, which is what an axis tooltip does. }
function TyTooltipSpecOf(AOption: TTyChartOption; ASeriesIndex: Integer;
  ARawIndex: Integer): TTyTooltipSpec;
{ `triggerOn` matching, upstream's way: a raw substring test, not equality and
  not a split on '|'. 'none' answers False for everything. }
function TyTooltipTriggerOnHas(const ATriggerOn, AWhat: string): Boolean;

{ ---- content ---- }
{ How a VALUE reaches the default content: grouped in threes, `1048` becoming
  `1,048`.

  NOT TyChartNumToStr, which every axis tick label uses and which suppresses
  the grouping deliberately. The two are different upstream too -- the default
  markup runs values through `addCommas` and a `{c}` in a template does not --
  so they are two functions here rather than one with a flag. }
function TyTooltipValueText(AValue: Double): string;

{ ---- layout ---- }
{ The tree, flattened into lines of runs. }
function TyTooltipFlatten(ABlock: TTyTooltipBlock;
  const AInk: TTyTooltipInk): TTyTooltipLineArray;
{ Measure every run, place them, and answer the box the lines need INCLUDING
  the padding. Device px out; logical px in. }
procedure TyTooltipMeasure(var ALines: TTyTooltipLineArray;
  const AInk: TTyTooltipInk; const AMeasurer: ITyTextMeasurer; APPI: Integer;
  APadLeftPx, APadTopPx, APadRightPx, APadBottomPx: Double;
  out AWidth, AHeight: Double);
{ Where the box goes, given the pointer and the room available.

  UPSTREAM'S SHAPE, which is not the old TTyChart's. The box hangs DOWN-RIGHT
  from the cursor by AGapPx, and the gap is a FLIP DISTANCE as well as an
  offset: when it would overflow, the box is placed so its far edge sits AGapPx
  on the near side of the cursor. The two axes are decided INDEPENDENTLY, so
  there are four outcomes and no diagonal special case, and there is no re-test
  after a flip.

  THEN CONFINED, always. Upstream's `confine` compares the RAW `renderMode`
  option, whose default is 'auto', so `'auto' <> 'richText'` and confine
  resolves FALSE in every environment -- contrary to the comment above its own
  declaration. A tooltip drawn on the control's own surface has no such choice:
  outside the bounds is not clipped, it is not drawn. So this clamps
  unconditionally and the option is recorded but not obeyed. It is a slide and
  not a second flip: the box keeps its side and slides along the edge, and an
  oversized box overflows right and bottom rather than left and top, because
  the right/bottom clamp runs first and the left/top clamp wins. }
function TyTooltipBoxAt(AAnchorX, AAnchorY, AWidth, AHeight, AGapPx: Double;
  const ABounds: TTyRectF): TTyRectF;

implementation

uses tyControls.AdvChart.Handlers;

{ ============================ the tree ============================ }

constructor TTyTooltipBlock.CreateSection(const AHeader: string;
  ANoHeader: Boolean);
begin
  inherited Create;
  FIsSection := True;
  FHeader := AHeader;
  { `noHeader: !trim(header)` upstream -- an all-blank header is no header,
    and the caller is not asked to remember that. }
  FNoHeader := ANoHeader or (Trim(AHeader) = '');
  FSortParam := NaN;
end;

procedure TTyTooltipBlock.Reverse;
var i, n: Integer; tmp: TTyTooltipBlock;
begin
  n := Length(FBlocks);
  for i := 0 to n div 2 - 1 do
  begin
    tmp := FBlocks[i];
    FBlocks[i] := FBlocks[n - 1 - i];
    FBlocks[n - 1 - i] := tmp;
  end;
end;

procedure TTyTooltipBlock.SortBlocks(AOrder: TTyTooltipOrder);
var
  i, j: Integer;
  key: TTyTooltipBlock;

  { Does A come before B? NaN is last in both directions. }
  function Before(A, B: TTyTooltipBlock): Boolean;
  var av, bv: Double;
  begin
    av := A.SortParam;
    bv := B.SortParam;
    if IsNan(av) then Exit(False);
    if IsNan(bv) then Exit(True);
    if AOrder = ttoValueAsc then Result := av < bv else Result := av > bv;
  end;

begin
  { `seriesAsc` IS THE ABSENCE OF AN ORDER -- it falls through both of
    upstream's branches. Saying so here rather than at the call site keeps the
    one place that knows it. }
  if AOrder = ttoSeriesAsc then Exit;
  if AOrder = ttoSeriesDesc then
  begin
    Reverse;
    Exit;
  end;
  { INSERTION SORT, which is stable by construction -- and a tooltip section
    holds as many rows as a chart has series, so the shape of the sort is the
    part that matters and its complexity is not. }
  for i := 1 to High(FBlocks) do
  begin
    key := FBlocks[i];
    j := i - 1;
    while (j >= 0) and Before(key, FBlocks[j]) do
    begin
      FBlocks[j + 1] := FBlocks[j];
      Dec(j);
    end;
    FBlocks[j + 1] := key;
  end;
end;

constructor TTyTooltipBlock.CreateNameValue(AMarker: TTyTooltipMarker;
  AMarkerColour: TTyChartColor; const AName: string; ANoName: Boolean;
  const AValue: string; ANoValue: Boolean);
begin
  inherited Create;
  FIsSection := False;
  FMarker := AMarker;
  FMarkerColour := AMarkerColour;
  FName := AName;
  FNoName := ANoName or (Trim(AName) = '');
  FValue := AValue;
  FNoValue := ANoValue;
  FSortParam := NaN;
  { NO COLOUR, NO MARKER. Upstream's first line is `if (!color) return ''` --
    a colourless item draws no dot rather than a default-coloured one. }
  if AMarkerColour = 0 then FMarker := ttmNone;
end;

destructor TTyTooltipBlock.Destroy;
var i: Integer;
begin
  for i := 0 to High(FBlocks) do
    FBlocks[i].Free;
  FBlocks := nil;
  inherited Destroy;
end;

function TTyTooltipBlock.Add(ABlock: TTyTooltipBlock): TTyTooltipBlock;
begin
  Result := ABlock;
  if ABlock = nil then Exit;
  SetLength(FBlocks, Length(FBlocks) + 1);
  FBlocks[High(FBlocks)] := ABlock;
end;

function TTyTooltipBlock.GetBlock(AIndex: Integer): TTyTooltipBlock;
begin
  if (AIndex < 0) or (AIndex > High(FBlocks)) then Exit(nil);
  Result := FBlocks[AIndex];
end;

function TTyTooltipBlock.GetBlockCount: Integer;
begin
  Result := Length(FBlocks);
end;

function TTyTooltipBlock.GapLevel: Integer;
var
  i, sub, n: Integer;
  hasInnerGap, bump: Boolean;
begin
  Result := 0;
  n := Length(FBlocks);
  if n = 0 then Exit;
  { A section's children are separated at all only when there is more than one
    of them, or when there is a header for them to be separated FROM. }
  hasInnerGap := (n > 1) or ((n > 0) and not FNoHeader);
  for i := 0 to n - 1 do
  begin
    sub := FBlocks[i].GapLevel;
    if sub >= Result then
    begin
      { The level rises past a child only when that child is itself a leaf, or
        is a section carrying a header of its own. A headerless section full of
        rows does not earn its parent another level. }
      bump := hasInnerGap and ((sub = 0)
              or (FBlocks[i].IsSection and not FBlocks[i].NoHeader));
      Result := sub + Ord(bump);
    end;
  end;
  if Result > 3 then Result := 3;
end;

{ ============================ the option ============================ }

function TyTooltipSpecDefault: TTyTooltipSpec;
begin
  Result := Default(TTyTooltipSpec);
  Result.Show := True;
  Result.ShowContent := True;
  Result.AlwaysShowContent := False;
  Result.Trigger := tttItem;
  Result.TriggerOn := 'mousemove|click|mousewheel';
  { RECORDED, NOT OBEYED -- see TyTooltipBoxAt. Upstream's own default is the
    sentinel `null`, and its resolution answers False everywhere. }
  Result.Confine := True;
  Result.ShowDelayMs := 0;
  { Milliseconds, while transitionDuration is SECONDS. Upstream does not unify
    the unit and neither does this. }
  Result.HideDelayMs := 100;
end;

function TyTooltipTriggerOnHas(const ATriggerOn, AWhat: string): Boolean;
begin
  { A RAW SUBSTRING TEST. Not equality, not a split on '|' -- upstream writes
    `triggerOn.indexOf(currTrigger) >= 0`, and the four things it is ever asked
    about ('click', 'mousemove', 'mousewheel', 'leave') are chosen so that no
    legal value contains 'leave'. That is what makes the leave branch
    reachable, so the test cannot be tightened without breaking it. }
  if (ATriggerOn = 'none') or (AWhat = '') then Exit(False);
  Result := Pos(AWhat, ATriggerOn) > 0;
end;

{ The node at one cascade level, or nil. }
function TooltipNodeOf(ANode: TJSONData): TJSONObject;
var d: TJSONData;
begin
  Result := nil;
  if (ANode = nil) or not (ANode is TJSONObject) then Exit;
  d := TJSONObject(ANode).Find('tooltip');
  if d = nil then Exit;
  if d is TJSONObject then Exit(TJSONObject(d));
  { `tooltip: 'some text'` is sugar for `{formatter: 'some text'}` at any
    cascade level. Answering nil here would silently drop it, so the caller
    checks for the string form separately. }
end;

function TooltipStringOf(ANode: TJSONData; out AText: string): Boolean;
var d: TJSONData;
begin
  AText := '';
  Result := False;
  if (ANode = nil) or not (ANode is TJSONObject) then Exit;
  d := TJSONObject(ANode).Find('tooltip');
  if (d <> nil) and (d.JSONType = jtString) then
  begin
    AText := d.AsString;
    Result := True;
  end;
end;

{ padding: a number, [v, h], or [t, r, b, l]. }
procedure ReadPadding(ANode: TJSONObject; var ASpec: TTyTooltipSpec);
var
  d: TJSONData;
  a: TJSONArray;
  v: array[0..3] of Double;
  i, n: Integer;
begin
  d := ANode.Find('padding');
  if d = nil then Exit;
  if d.JSONType = jtNumber then
  begin
    ASpec.HasPadding := True;
    ASpec.PadTop := d.AsFloat;
    ASpec.PadRight := ASpec.PadTop;
    ASpec.PadBottom := ASpec.PadTop;
    ASpec.PadLeft := ASpec.PadTop;
    Exit;
  end;
  if not (d is TJSONArray) then Exit;
  a := TJSONArray(d);
  n := a.Count;
  if (n < 1) or (n > 4) then Exit;
  for i := 0 to 3 do v[i] := 0;
  for i := 0 to n - 1 do
  begin
    { TYPE-CHECKED BEFORE Floats[]. fcl-json coerces, and coercion RAISES on a
      string -- `padding: ['8px', 10]` is a thing people write. }
    if a.Items[i].JSONType <> jtNumber then Exit;
    v[i] := a.Floats[i];
  end;
  ASpec.HasPadding := True;
  case n of
    1: begin ASpec.PadTop := v[0]; ASpec.PadRight := v[0];
             ASpec.PadBottom := v[0]; ASpec.PadLeft := v[0]; end;
    2: begin ASpec.PadTop := v[0]; ASpec.PadBottom := v[0];
             ASpec.PadRight := v[1]; ASpec.PadLeft := v[1]; end;
    3: begin ASpec.PadTop := v[0]; ASpec.PadRight := v[1];
             ASpec.PadLeft := v[1]; ASpec.PadBottom := v[2]; end;
  else
    ASpec.PadTop := v[0]; ASpec.PadRight := v[1];
    ASpec.PadBottom := v[2]; ASpec.PadLeft := v[3];
  end;
end;

{ One cascade level, written into ASpec only where ASpec has not been given an
  answer yet -- which is what "read each key from the nearest level that has
  it" comes to when the levels are visited innermost first. }
procedure MergeTooltipNode(ANode: TJSONObject; var ASpec: TTyTooltipSpec;
  var ASeen: TTyStringArray);

  function Fresh(const AKey: string): Boolean;
  var i: Integer;
  begin
    for i := 0 to High(ASeen) do
      if ASeen[i] = AKey then Exit(False);
    if ANode.Find(AKey) = nil then Exit(False);
    SetLength(ASeen, Length(ASeen) + 1);
    ASeen[High(ASeen)] := AKey;
    Result := True;
  end;

var
  d: TJSONData;
  ts: TJSONObject;
  c: TTyChartColor;
begin
  if ANode = nil then Exit;

  if Fresh('show') then
  begin
    d := ANode.Find('show');
    if d.JSONType = jtBoolean then ASpec.Show := d.AsBoolean;
  end;
  if Fresh('showContent') then
  begin
    d := ANode.Find('showContent');
    if d.JSONType = jtBoolean then ASpec.ShowContent := d.AsBoolean;
  end;
  if Fresh('alwaysShowContent') then
  begin
    d := ANode.Find('alwaysShowContent');
    if d.JSONType = jtBoolean then ASpec.AlwaysShowContent := d.AsBoolean;
  end;
  if Fresh('trigger') then
  begin
    d := ANode.Find('trigger');
    { `trigger: false` is a legal way of saying none -- upstream tests it
      alongside the strings when it filters a series out of an axis tooltip. }
    if (d.JSONType = jtBoolean) and not d.AsBoolean then
      ASpec.Trigger := tttNone
    else if d.JSONType = jtString then
    begin
      if d.AsString = 'axis' then ASpec.Trigger := tttAxis
      else if d.AsString = 'none' then ASpec.Trigger := tttNone
      else if d.AsString = 'item' then ASpec.Trigger := tttItem;
    end;
  end;
  if Fresh('triggerOn') then
  begin
    d := ANode.Find('triggerOn');
    if d.JSONType = jtString then ASpec.TriggerOn := d.AsString;
  end;
  if Fresh('confine') then
  begin
    d := ANode.Find('confine');
    if d.JSONType = jtBoolean then ASpec.Confine := d.AsBoolean;
  end;
  if Fresh('showDelay') then
  begin
    d := ANode.Find('showDelay');
    if d.JSONType = jtNumber then
      ASpec.ShowDelayMs := TyRoundOpt(d.AsFloat, 0, 0, 60000);
  end;
  if Fresh('hideDelay') then
  begin
    d := ANode.Find('hideDelay');
    if d.JSONType = jtNumber then
      ASpec.HideDelayMs := TyRoundOpt(d.AsFloat, 100, 0, 60000);
  end;
  if Fresh('order') then
  begin
    d := ANode.Find('order');
    if d.JSONType = jtString then
    begin
      ASpec.HasOrder := True;
      if d.AsString = 'valueAsc' then ASpec.Order := ttoValueAsc
      else if d.AsString = 'valueDesc' then ASpec.Order := ttoValueDesc
      else if d.AsString = 'seriesDesc' then ASpec.Order := ttoSeriesDesc
      else ASpec.Order := ttoSeriesAsc;
    end;
  end;
  if Fresh('formatter') then
  begin
    d := ANode.Find('formatter');
    { EMPTY IS NOT AN OVERRIDE. `formatter: ''` is falsy upstream and leaves
      the default content standing -- which is not the same as a formatter
      that produces nothing. }
    if (d.JSONType = jtString) and (d.AsString <> '') then
    begin
      ASpec.Formatter := d.AsString;
      ASpec.HasFormatter := True;
    end;
  end;

  if Fresh('backgroundColor') then
  begin
    d := ANode.Find('backgroundColor');
    if (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, c) then
    begin
      ASpec.HasBackground := True;
      ASpec.Background := c;
    end;
  end;
  if Fresh('borderColor') then
  begin
    d := ANode.Find('borderColor');
    if (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, c) then
    begin
      ASpec.HasBorderColour := True;
      ASpec.BorderColour := c;
    end;
  end;
  if Fresh('borderWidth') then
  begin
    d := ANode.Find('borderWidth');
    if d.JSONType = jtNumber then
    begin
      ASpec.HasBorderWidth := True;
      ASpec.BorderWidthLogical := Max(Double(0), Min(Double(64), d.AsFloat));
    end;
  end;
  if Fresh('borderRadius') then
  begin
    d := ANode.Find('borderRadius');
    if d.JSONType = jtNumber then
    begin
      ASpec.HasBorderRadius := True;
      ASpec.BorderRadiusLogical := Max(Double(0), Min(Double(256), d.AsFloat));
    end;
  end;
  if Fresh('padding') then ReadPadding(ANode, ASpec);

  { WHOLESALE. The first level that writes a textStyle at all supplies the
    whole of it; the keys it left out do NOT fall through to the level above,
    because upstream's Model.get replaces an object-valued key rather than
    merging it. Getting this wrong is invisible until somebody writes
    `textStyle: {fontWeight: 'bold'}` and the colour changes too. }
  if Fresh('textStyle') then
  begin
    d := ANode.Find('textStyle');
    if d is TJSONObject then
    begin
      ts := TJSONObject(d);
      d := ts.Find('color');
      if (d <> nil) and (d.JSONType = jtString)
        and TyTryParseChartColor(d.AsString, c) then
      begin
        ASpec.HasTextColour := True;
        ASpec.TextColour := c;
      end;
      d := ts.Find('fontSize');
      if (d <> nil) and (d.JSONType = jtNumber) then
      begin
        ASpec.HasTextSize := True;
        ASpec.TextSizeLogical := Max(Double(1), Min(Double(400), d.AsFloat));
      end;
    end;
  end;
end;

function TyTooltipSpecOf(AOption: TTyChartOption; ASeriesIndex: Integer;
  ARawIndex: Integer): TTyTooltipSpec;
var
  seen: TTyStringArray;
  seriesNode, dataNode: TJSONData;
  arr: TJSONData;
  s: string;
begin
  Result := TyTooltipSpecDefault;
  seen := nil;
  if AOption = nil then Exit;

  seriesNode := AOption.ComponentAt('series', ASeriesIndex);

  { ---- the data item ---- }
  if (ARawIndex >= 0) and (seriesNode <> nil) and (seriesNode is TJSONObject) then
  begin
    arr := TJSONObject(seriesNode).Find('data');
    if (arr is TJSONArray) and (ARawIndex < TJSONArray(arr).Count) then
    begin
      dataNode := TJSONArray(arr).Items[ARawIndex];
      if TooltipStringOf(dataNode, s) then
      begin
        Result.Formatter := s;
        Result.HasFormatter := s <> '';
        SetLength(seen, Length(seen) + 1);
        seen[High(seen)] := 'formatter';
      end;
      MergeTooltipNode(TooltipNodeOf(dataNode), Result, seen);
    end;
  end;

  { ---- the series ---- }
  if TooltipStringOf(seriesNode, s) then
  begin
    if not Result.HasFormatter then
    begin
      Result.Formatter := s;
      Result.HasFormatter := s <> '';
    end;
    SetLength(seen, Length(seen) + 1);
    seen[High(seen)] := 'formatter';
  end;
  MergeTooltipNode(TooltipNodeOf(seriesNode), Result, seen);

  { ---- the global component ---- }
  if TooltipStringOf(AOption.Root, s) and not Result.HasFormatter then
  begin
    Result.Formatter := s;
    Result.HasFormatter := s <> '';
  end;
  MergeTooltipNode(TooltipNodeOf(AOption.Root), Result, seen);
end;

{ ============================ content ============================ }

function TyTooltipValueText(AValue: Double): string;
var
  s, head, tail: string;
  dot, i, k: Integer;
  neg: Boolean;
begin
  s := TyChartNumToStr(AValue);
  if s = '' then Exit('');
  neg := (s <> '') and (s[1] = '-');
  if neg then Delete(s, 1, 1);
  dot := Pos('.', s);
  if dot > 0 then
  begin
    head := Copy(s, 1, dot - 1);
    tail := Copy(s, dot, MaxInt);
  end
  else
  begin
    head := s;
    tail := '';
  end;
  { GROUPS OF THREE FROM THE RIGHT, and only in the integer part -- upstream's
    regex is anchored so the fraction is never grouped. }
  Result := '';
  k := 0;
  for i := Length(head) downto 1 do
  begin
    Result := head[i] + Result;
    Inc(k);
    if (k mod 3 = 0) and (i > 1) then Result := ',' + Result;
  end;
  Result := Result + tail;
  if neg then Result := '-' + Result;
end;

{ ============================ flattening ============================ }

function MarkerRun(const AInk: TTyTooltipInk; AKind: TTyTooltipMarker;
  AColour: TTyChartColor): TTyTooltipRun;
begin
  Result := Default(TTyTooltipRun);
  Result.Kind := ttrMarker;
  Result.Colour := AColour;
  { The small dot is upstream's 4-against-10; kept as a ratio of the themed
    size so a skin that enlarges the marker enlarges both. }
  if AKind = ttmSubItem then
    Result.MarkerSizeLogical := AInk.MarkerSizeLogical * 2 / 5
  else
    Result.MarkerSizeLogical := AInk.MarkerSizeLogical;
end;

function TextRun(const AText, AFont: string; ASize: Integer; AWeight: Integer;
  AColour: TTyChartColor; AAlignRight: Boolean): TTyTooltipRun;
begin
  Result := Default(TTyTooltipRun);
  Result.Kind := ttrText;
  Result.Text := AText;
  Result.FontName := AFont;
  Result.FontSizeLogical := ASize;
  Result.FontWeight := AWeight;
  Result.Colour := AColour;
  Result.AlignRight := AAlignRight;
end;

function NameValueLine(ABlock: TTyTooltipBlock;
  const AInk: TTyTooltipInk): TTyTooltipLine;
var
  n: Integer;
  alignRight: Boolean;
begin
  Result := Default(TTyTooltipLine);
  n := 0;
  SetLength(Result.Runs, 3);
  if ABlock.Marker <> ttmNone then
  begin
    Result.Runs[n] := MarkerRun(AInk, ABlock.Marker, ABlock.MarkerColour);
    Inc(n);
  end;
  if not ABlock.NoName then
  begin
    Result.Runs[n] := TextRun(ABlock.Name, AInk.NameFontName,
      AInk.NameSizeLogical, AInk.NameWeight, AInk.NameColour, False);
    Inc(n);
  end;
  if not ABlock.NoValue then
  begin
    { THREE CASES, NOT TWO. A row with neither a marker nor a name does not
      right-align its value at all -- it gets no float and no gutter, and sits
      where it falls. That case is live upstream (a timeline tick, a marker
      component), and a port with an if/else puts the value across the box. }
    alignRight := (ABlock.Marker <> ttmNone) or not ABlock.NoName;
    Result.Runs[n] := TextRun(ABlock.Value, AInk.ValueFontName,
      AInk.ValueSizeLogical, AInk.ValueWeight, AInk.ValueColour, alignRight);
    Inc(n);
  end;
  SetLength(Result.Runs, n);
end;

{ Join B onto A with AGap newlines. Zero newlines CONCATENATES: A's last line
  and B's first become one line. That is what `join('')` does upstream at gap
  level 0, and no built-in tree produces it -- but a hand-built one can, and
  answering it with a line break instead would be a different picture. }
procedure JoinLines(var A: TTyTooltipLineArray; const B: TTyTooltipLineArray;
  AGap: Integer);
var
  i, n, m: Integer;
begin
  if Length(B) = 0 then Exit;
  if Length(A) = 0 then
  begin
    A := Copy(B, 0, Length(B));
    Exit;
  end;
  if AGap <= 0 then
  begin
    n := High(A);
    m := Length(A[n].Runs);
    SetLength(A[n].Runs, m + Length(B[0].Runs));
    for i := 0 to High(B[0].Runs) do
      A[n].Runs[m + i] := B[0].Runs[i];
    for i := 1 to High(B) do
    begin
      SetLength(A, Length(A) + 1);
      A[High(A)] := B[i];
    end;
    Exit;
  end;
  n := Length(A);
  SetLength(A, n + Length(B));
  for i := 0 to High(B) do
    A[n + i] := B[i];
  { The gap lands on the FIRST line of B, and a level of 1 means no blank line
    at all -- one newline simply ends the previous line. }
  A[n].BlankLinesBefore := AGap - 1;
end;

function RenderBlock(ABlock: TTyTooltipBlock;
  const AInk: TTyTooltipInk): TTyTooltipLineArray;
var
  i, gap: Integer;
  part: TTyTooltipLineArray;
begin
  Result := nil;
  if ABlock = nil then Exit;
  if not ABlock.IsSection then
  begin
    SetLength(Result, 1);
    Result[0] := NameValueLine(ABlock, AInk);
    Exit;
  end;
  gap := ABlock.GapLevel;
  if not ABlock.NoHeader then
  begin
    SetLength(Result, 1);
    Result[0] := Default(TTyTooltipLine);
    SetLength(Result[0].Runs, 1);
    { THE HEADER TAKES THE NAME STYLE. It is the words that name the thing, and
      upstream inks it from exactly the same pair as an inline name. }
    Result[0].Runs[0] := TextRun(ABlock.Header, AInk.NameFontName,
      AInk.NameSizeLogical, AInk.NameWeight, AInk.NameColour, False);
  end;
  for i := 0 to ABlock.BlockCount - 1 do
  begin
    part := RenderBlock(ABlock.Blocks[i], AInk);
    JoinLines(Result, part, gap);
  end;
end;

function TyTooltipFlatten(ABlock: TTyTooltipBlock;
  const AInk: TTyTooltipInk): TTyTooltipLineArray;
begin
  Result := RenderBlock(ABlock, AInk);
  { The first line has nothing above it whatever the join decided. }
  if Length(Result) > 0 then Result[0].BlankLinesBefore := 0;
end;

{ ============================ measuring ============================ }

procedure TyTooltipMeasure(var ALines: TTyTooltipLineArray;
  const AInk: TTyTooltipInk; const AMeasurer: ITyTextMeasurer; APPI: Integer;
  APadLeftPx, APadTopPx, APadRightPx, APadBottomPx: Double;
  out AWidth, AHeight: Double);
var
  i, j, rows: Integer;
  w, h, x, scale, lineH, gutter, markerGap, maxW, natural: Double;
  hasRight, hasMarker, hasName: Boolean;
begin
  AWidth := 0;
  AHeight := 0;
  if Length(ALines) = 0 then Exit;
  scale := APPI / 96;
  lineH := AInk.LineHeightLogical * scale;
  markerGap := AInk.MarkerGapLogical * scale;

  maxW := 0;
  for i := 0 to High(ALines) do
  begin
    x := 0;
    hasRight := False;
    hasMarker := False;
    hasName := False;
    ALines[i].RightW := 0;
    for j := 0 to High(ALines[i].Runs) do
    begin
      if ALines[i].Runs[j].Kind = ttrMarker then
      begin
        hasMarker := True;
        w := ALines[i].Runs[j].MarkerSizeLogical * scale;
        ALines[i].Runs[j].W := w;
        ALines[i].Runs[j].X := x;
        x := x + w + markerGap;
        Continue;
      end;
      AMeasurer.MeasureLine(ALines[i].Runs[j].Text,
        ALines[i].Runs[j].FontName, ALines[i].Runs[j].FontSizeLogical,
        ALines[i].Runs[j].FontWeight, w, h);
      ALines[i].Runs[j].W := w;
      if ALines[i].Runs[j].AlignRight then
      begin
        hasRight := True;
        ALines[i].RightW := ALines[i].RightW + w;
      end
      else
      begin
        hasName := True;
        ALines[i].Runs[j].X := x;
        x := x + w;
      end;
    end;
    ALines[i].LeftW := x;
    { The narrower gutter is for a row that has a dot but no name -- the value
      is then close to the marker rather than across a column from a name. }
    if hasMarker and not hasName then gutter := AInk.GutterCloseLogical * scale
    else gutter := AInk.GutterLogical * scale;
    if hasRight then natural := x + gutter + ALines[i].RightW
    else natural := x;
    if natural > maxW then maxW := natural;
  end;

  { RIGHT-ALIGNED AGAINST THE WIDEST LINE, not against its own. That is what
    puts a column of values under one another, and it is why the placement
    cannot happen in the same pass as the measuring. }
  for i := 0 to High(ALines) do
  begin
    x := maxW;
    for j := High(ALines[i].Runs) downto 0 do
      if (ALines[i].Runs[j].Kind = ttrText) and ALines[i].Runs[j].AlignRight then
      begin
        x := x - ALines[i].Runs[j].W;
        ALines[i].Runs[j].X := x;
      end;
  end;

  rows := 0;
  for i := 0 to High(ALines) do
    rows := rows + 1 + ALines[i].BlankLinesBefore;
  AWidth := APadLeftPx + maxW + APadRightPx;
  AHeight := APadTopPx + rows * lineH + APadBottomPx;
end;

{ ============================ placement ============================ }

function TyTooltipBoxAt(AAnchorX, AAnchorY, AWidth, AHeight, AGapPx: Double;
  const ABounds: TTyRectF): TTyRectF;
var
  x, y, bw, bh: Double;
begin
  if AWidth < 0 then AWidth := 0;
  if AHeight < 0 then AHeight := 0;
  if AGapPx < 0 then AGapPx := 0;
  bw := ABounds.Right - ABounds.Left;
  bh := ABounds.Bottom - ABounds.Top;

  x := AAnchorX - ABounds.Left;
  y := AAnchorY - ABounds.Top;

  { DOWN AND RIGHT, flipped per axis, each decided on its own. Upstream adds 2
    to the horizontal TEST only -- never to the arithmetic -- as a workaround
    for the CSS float its values are laid out with. A canvas has no float and
    no analogue, so the 2 is dropped and the flip threshold sits two pixels
    further right than upstream's. }
  if x + AWidth + AGapPx > bw then x := x - AWidth - AGapPx
  else x := x + AGapPx;
  if y + AHeight + AGapPx > bh then y := y - AHeight - AGapPx
  else y := y + AGapPx;

  { Then confined. Far edge first, near edge second, so an oversized box keeps
    its top-left and overflows the other way. }
  x := Min(x + AWidth, bw) - AWidth;
  y := Min(y + AHeight, bh) - AHeight;
  if x < 0 then x := 0;
  if y < 0 then y := 0;

  Result := TyRectF(ABounds.Left + x, ABounds.Top + y,
                    ABounds.Left + x + AWidth, ABounds.Top + y + AHeight);
end;

end.
