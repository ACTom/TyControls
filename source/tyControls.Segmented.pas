unit tyControls.Segmented;
{$mode objfpc}{$H+}
{ TTySegmented — a segmented control: a row of mutually-exclusive options sharing one
  themed track, exactly one of them selected.

  The gap it fills. TTyTabSet / TTyPageControl are TAB STRIPS: their headers are chrome
  for a container and picking one switches a PAGE. A segmented control switches a VALUE —
  a view mode, a filter, a unit — owns no pages, hosts no children, and reads as one
  compact widget. TTyRadioGroup carries the same "pick one" semantics but spends a titled
  frame and a whole child control per option; this spends one control and one row.

  A WINDOWED control (TTyCustomControl), unlike its batch sibling TTyTag: it is focusable
  and the Left/Right keys move the selection, and a graphic control can do neither (no
  handle => no focus, no key messages). That is the whole reason for the base class.

  typeKey 'TySegmented' is the TRACK (the frame the segments sit in); each segment resolves
  'TySegmentedItem' separately, and it is that key's :selected / :hover / :disabled states
  that make the control read at all. The selected segment carries tysSelected exactly as
  TTyButton.Down does, so one ':selected' rule styles both. }
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base,
  tyControls.Controller, tyControls.StyleModel;

const
  { Built-in logical-px defaults (96-PPI baseline) for this control's two metrics. A skin
    retunes them through the named theme metrics below (the v3/C convention); these are
    only what a theme that sets neither falls back to. Both are scaled to device px at
    every call site.
    The min width matches TyTabMinWidth so a 3-option segmented control and a 3-tab strip
    have the same rhythm; the track pad is small by nature — it is the sliver of track that
    stays visible AROUND the selected segment's chip, which is what makes a segmented
    control read as "one thumb inside a groove" instead of a row of buttons. }
  TySegmentedPad      = 2;    // track inset around the whole segment row, all four sides
  TySegmentedMinWidth = 48;   // floor for a segment's width when AutoSize measures

  { The metric tokens those fallbacks back. Named constants rather than literals so a typo
    cannot silently strand one call site on the default (the tyControls.Types convention). }
  TySegmentedPadVar      = '--segmented-pad';
  TySegmentedMinWidthVar = '--segmented-min-width';

{ --- Pure rules / geometry (headless-testable; no control, no handle, no theme) -------- }

{ The rect of segment AIndex, in DEVICE px relative to the control rect's top-left.
    AClientWidth/AClientHeight — the control size, device px.
    ACount — how many segments share the track.
    APad   — the themed track inset (device px), applied on all four sides.
    AIndex — 0-based segment.
  The segments TILE the padded band exactly: segment i's right edge IS segment i+1's left
  edge, so there is no seam a click can fall into and no gap a chip can leak through. The
  band is split by integer division, so when it does not divide evenly the widths differ by
  a single px — the remainder is spread by where the division's floor boundaries land, not
  dumped on one segment. That tiling is also why the hit-test below is written as this
  function's inverse rather than as its own arithmetic: the two can never drift.
  An empty rect (never an inverted one) for a degenerate request: no segments, an index out
  of range, a zero-area control, or padding that eats the whole track. }
function TySegmentedItemRect(AClientWidth, AClientHeight, ACount, APad,
  AIndex: Integer): TRect;

{ The segment at device-px (X, Y), or -1 for none. The exact INVERSE of TySegmentedItemRect
  (it scans that function's own rects), so the segment the user clicks is always the segment
  that was painted there. The track's padding gutter belongs to no segment: a click there
  answers -1 and leaves the selection alone. }
function TySegmentedIndexAt(AClientWidth, AClientHeight, ACount, APad,
  X, Y: Integer): Integer;

{ The index a selection of ACurrent becomes when it is valid for ACount, else -1. The house
  ItemIndex rule (TTyListBox.SelectItem): an out-of-range index is not clamped onto an end
  segment, it means "nothing selected" — a caller that asked for segment 7 of 3 wanted a
  segment that is not there, and silently selecting the last one would be a lie. }
function TySegmentedValidIndex(ACurrent, ACount: Integer): Integer;

{ Where a Left/Right key press moves the selection: ACurrent + ADelta, CLAMPED at both ends
  (no wrap — a segmented control is a short row the user can see all of, so running off the
  end should stop, not teleport across it; this mirrors TTyCustomTabStrip's VK_LEFT/RIGHT).
  From -1 (nothing selected) a step ENTERS the row at the end it came from: Right takes the
  first segment, Left the last. Always returns a valid index, or -1 when there are none. }
function TySegmentedStepIndex(ACurrent, ACount, ADelta: Integer): Integer;

{ The track width that shows AMaxTextWidth px of the widest segment label whole — the
  inverse of TySegmentedItemRect: feed the result back in as AClientWidth (same ACount and
  ATrackPad) and every segment comes out exactly the natural segment width. Device px
  throughout; this is what AutoSize measures to.
    AMaxTextWidth — the widest label's extent.
    AItemPadLeft/AItemPadRight — the SEGMENT's themed horizontal padding.
    ATrackPad — the track inset (both sides).
    AMinItemWidth — floor for one segment, so a row of 'A'/'B'/'C' is still clickable.
  All segments share the widest one's width: a segmented control whose options are
  different sizes reads as broken. An empty control is just its own track padding. }
function TySegmentedPreferredWidth(ACount, AMaxTextWidth, AItemPadLeft, AItemPadRight,
  ATrackPad, AMinItemWidth: Integer): Integer;

type
  { A row of mutually-exclusive options in one themed track. Items are the segments,
    ItemIndex the selected one (-1 = none), OnChange fires whenever that changes.

    Colour/size variants are plain StyleClass ('TySegmented.small', …) — the control
    declares no variant enum of its own, so a theme may define as many as it likes without
    a code change, and the segments' own key is resolved with the SAME StyleClass so
    'TySegmentedItem.small' can follow the track. }
  TTySegmented = class(TTyCustomControl)
  private
    FItems: TStrings;
    FItemIndex: Integer;
    FHoverIndex: Integer;      // segment under the pointer; -1 = none
    FOnChange: TNotifyEvent;
    { A streamed ItemIndex parked by the setter because the .lfm's Items had not arrived
      yet (nothing is selectable against an empty list). Applied in Loaded. }
    FPendingItemIndex: Integer;
    FHasPendingIndex: Boolean;
    procedure SetItems(AValue: TStrings);
    procedure ItemsChanged(Sender: TObject);
    procedure SetItemIndex(AValue: Integer);
    { The theme's track inset / segment-width floor, in DEVICE px at APPI. }
    function PadPx(APPI: Integer): Integer;
    function MinWidthPx(APPI: Integer): Integer;
    { The resolved style for one segment: 'TySegmentedItem' with the TRACK's StyleClass
      (so a variant reaches both keys) and the state of THAT segment. }
    function ItemStyle(AIndex: Integer): TTyStyleSet;
    { The state set of segment AIndex — the heart of how this control reads. }
    function ItemStates(AIndex: Integer): TTyStateSet;
    { The tokens a segment draws its LABEL with: its own where TySegmentedItem defines
      them, the TRACK's otherwise. Background/border are deliberately NOT inherited this
      way (see RenderTo): a segment with no background of its own must draw no chip. }
    function ItemTextStyle(const ATrack, AItem: TTyStyleSet): TTyStyleSet;
    { Widest label + a stable line height, both device px at APPI, measured in ASTYLE's
      font. Height comes from a reference glyph ('Ag') so an empty/blank label still sizes
      to a line. }
    procedure MeasureItems(APPI: Integer; const AStyle: TTyStyleSet;
      out AWidestPx, ALineHeightPx: Integer);
  protected
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure Loaded; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
      WithThemeSpace: Boolean); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { How many segments the track holds. }
    function Count: Integer;
    { Segment AIndex's rect in DEVICE px, (0,0)-local — the exact rect the paint filled and
      the hit-test measures against; empty when AIndex is out of range. Exposed for tests. }
    function TySegmentRect(AIndex: Integer): TRect;
    { The segment at client device (X, Y), or -1 (the track's padding gutter included). }
    function TySegmentAt(X, Y: Integer): Integer;
  published
    { The segments, one per line. Editing them re-fits an auto-sized track; an edit that
      leaves ItemIndex out of range resets it to -1 SILENTLY (see SetItemIndex). }
    property Items: TStrings read FItems write SetItems;
    { The selected segment, -1 = none. An out-of-range value means -1, it is NOT clamped
      onto an end segment (TTyListBox.ItemIndex's rule). }
    property ItemIndex: Integer read FItemIndex write SetItemIndex default -1;
    { Fires whenever ItemIndex actually changes — by click, by key, or from code. Setting
      the same index again is not a change and stays silent. }
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    { With AutoSize the track hugs its widest label (every segment takes that width, plus
      the segment padding and the track's own inset); off, it keeps the bounds it was given
      and the segments split them evenly. }
    property AutoSize;
    property TabStop default True;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
    property OnClick;
  end;

implementation

{ --- pure rules / geometry ------------------------------------------------------------ }

function TySegmentedItemRect(AClientWidth, AClientHeight, ACount, APad,
  AIndex: Integer): TRect;
var
  bandL, bandR, bandT, bandB, bandW: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  if (ACount <= 0) or (AIndex < 0) or (AIndex >= ACount) then Exit;
  if (AClientWidth <= 0) or (AClientHeight <= 0) then Exit;
  if APad < 0 then APad := 0;

  // The band: the track inset by its padding on all four sides. Padding that eats the
  // whole track leaves nothing to lay out (an empty rect, never an inverted one).
  bandL := APad;
  bandR := AClientWidth - APad;
  bandT := APad;
  bandB := AClientHeight - APad;
  if (bandR <= bandL) or (bandB <= bandT) then Exit;

  // Plain integer division rather than MulDiv: the tiling only holds if segment i's right
  // edge is computed by the SAME expression as segment i+1's left edge, and truncation
  // makes that exact (and free of MulDiv's rounding, which differs by platform).
  bandW := bandR - bandL;
  Result := Rect(bandL + (bandW * AIndex) div ACount, bandT,
                 bandL + (bandW * (AIndex + 1)) div ACount, bandB);
end;

function TySegmentedIndexAt(AClientWidth, AClientHeight, ACount, APad,
  X, Y: Integer): Integer;
var
  i: Integer;
  R: TRect;
begin
  Result := -1;
  for i := 0 to ACount - 1 do
  begin
    R := TySegmentedItemRect(AClientWidth, AClientHeight, ACount, APad, i);
    if (R.Right > R.Left) and (X >= R.Left) and (X < R.Right)
       and (Y >= R.Top) and (Y < R.Bottom) then
      Exit(i);
  end;
end;

function TySegmentedValidIndex(ACurrent, ACount: Integer): Integer;
begin
  if (ACount <= 0) or (ACurrent < 0) or (ACurrent >= ACount) then
    Result := -1
  else
    Result := ACurrent;
end;

function TySegmentedStepIndex(ACurrent, ACount, ADelta: Integer): Integer;
begin
  if ACount <= 0 then Exit(-1);
  if ADelta = 0 then Exit(TySegmentedValidIndex(ACurrent, ACount));
  // Entering the row from nowhere: land on the segment the step is coming FROM, so Right
  // starts at the left end and Left at the right end.
  if TySegmentedValidIndex(ACurrent, ACount) < 0 then
  begin
    if ADelta > 0 then Result := 0 else Result := ACount - 1;
    Exit;
  end;
  Result := ACurrent + ADelta;
  if Result < 0 then Result := 0;
  if Result > ACount - 1 then Result := ACount - 1;
end;

function TySegmentedPreferredWidth(ACount, AMaxTextWidth, AItemPadLeft, AItemPadRight,
  ATrackPad, AMinItemWidth: Integer): Integer;
var
  segW: Integer;
begin
  if ATrackPad < 0 then ATrackPad := 0;
  Result := 2 * ATrackPad;       // an empty control is just its own track padding
  if ACount <= 0 then Exit;
  if AMaxTextWidth < 0 then AMaxTextWidth := 0;
  if AItemPadLeft < 0 then AItemPadLeft := 0;
  if AItemPadRight < 0 then AItemPadRight := 0;
  segW := AMaxTextWidth + AItemPadLeft + AItemPadRight;
  if segW < AMinItemWidth then segW := AMinItemWidth;
  Inc(Result, ACount * segW);
end;

{ --- TTySegmented --------------------------------------------------------------------- }

constructor TTySegmented.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FItems := TStringList.Create;
  TStringList(FItems).OnChange := @ItemsChanged;
  FItemIndex := -1;
  FHoverIndex := -1;
  FPendingItemIndex := -1;
  FHasPendingIndex := False;
  TabStop := True;   // the point of the windowed base class: it takes focus and arrow keys
  Width := 240;
  Height := TyDensityHeight(ActiveController, 30);
end;

destructor TTySegmented.Destroy;
begin
  // Drop the change hook before freeing: the list fires OnChange as it clears.
  TStringList(FItems).OnChange := nil;
  FItems.Free;
  inherited Destroy;
end;

function TTySegmented.GetStyleTypeKey: string;
begin
  Result := 'TySegmented';
end;

function TTySegmented.Count: Integer;
begin
  Result := FItems.Count;
end;

{ --- items / selection ---------------------------------------------------------------- }

procedure TTySegmented.SetItems(AValue: TStrings);
begin
  FItems.Assign(AValue);   // fires ItemsChanged
end;

procedure TTySegmented.ItemsChanged(Sender: TObject);
var
  valid: Integer;
begin
  // A list edit can strand the selection past the end. Re-validate it SILENTLY: editing
  // Items is the host's own action, not a user selection, so announcing it back through
  // OnChange would fire an event the host caused and did not ask about. (The host reads
  // ItemIndex after its own edit; a user gesture is what OnChange is for.)
  valid := TySegmentedValidIndex(FItemIndex, FItems.Count);
  if valid <> FItemIndex then FItemIndex := valid;
  // A segment more or fewer changes the width an auto-sized track needs.
  if AutoSize then
  begin
    InvalidatePreferredSize;
    AdjustSize;
  end;
  if not (csLoading in ComponentState) then Invalidate;
end;

procedure TTySegmented.SetItemIndex(AValue: Integer);
var
  valid: Integer;
begin
  { During csLoading the segments may not exist yet, so validating against an empty list
    would silently drop a streamed selection. Park it; Loaded applies it once Items is
    whole (mirrors TTyCustomTabStrip.SetTabIndex). }
  if csLoading in ComponentState then
  begin
    FPendingItemIndex := AValue;
    FHasPendingIndex := True;
    Exit;
  end;
  valid := TySegmentedValidIndex(AValue, FItems.Count);
  if valid = FItemIndex then Exit;
  FItemIndex := valid;
  Invalidate;
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TTySegmented.Loaded;
var
  pending: Integer;
begin
  inherited Loaded;
  if FHasPendingIndex then
  begin
    pending := FPendingItemIndex;
    FHasPendingIndex := False;
    FPendingItemIndex := -1;
    // Applied SILENTLY: streaming a form is not a user selection, and the .lfm's own
    // OnChange handler is already wired by now — firing it here would hand the host a
    // "the user picked something" event before the form is even shown.
    FItemIndex := TySegmentedValidIndex(pending, FItems.Count);
    Invalidate;
  end;
end;

{ --- theme metrics -------------------------------------------------------------------- }

function TTySegmented.PadPx(APPI: Integer): Integer;
begin
  if APPI <= 0 then APPI := 96;
  Result := ActiveController.Metric(TySegmentedPadVar, TySegmentedPad);
  if Result < 0 then Result := 0;
  // MulDiv(...,APPI,96) is the same logical->device conversion TTyPainter.Scale applies,
  // so the rects the hit-test measures are the rects the paint drew.
  Result := MulDiv(Result, APPI, 96);
end;

function TTySegmented.MinWidthPx(APPI: Integer): Integer;
begin
  if APPI <= 0 then APPI := 96;
  Result := ActiveController.Metric(TySegmentedMinWidthVar, TySegmentedMinWidth);
  if Result < 0 then Result := 0;
  Result := MulDiv(Result, APPI, 96);
end;

{ --- geometry ------------------------------------------------------------------------- }

function TTySegmented.TySegmentRect(AIndex: Integer): TRect;
begin
  Result := TySegmentedItemRect(ClientWidth, ClientHeight, FItems.Count,
    PadPx(Font.PixelsPerInch), AIndex);
end;

function TTySegmented.TySegmentAt(X, Y: Integer): Integer;
begin
  Result := TySegmentedIndexAt(ClientWidth, ClientHeight, FItems.Count,
    PadPx(Font.PixelsPerInch), X, Y);
end;

{ --- state / style -------------------------------------------------------------------- }

function TTySegmented.ItemStates(AIndex: Integer): TTyStateSet;
begin
  Result := [];
  // The SAME resting state TTyButton.Down injects, so one ':selected' theme rule styles
  // the pressed button and the chosen segment alike.
  if AIndex = FItemIndex then Include(Result, tysSelected);
  if not Enabled then
  begin
    { Disabled KEEPS :selected — unlike TTyButton.Down, which drops it. A greyed-out
      segmented control must still show WHICH option is in force: losing the chip would
      make it read as "nothing is selected" rather than "you cannot change this", and the
      selection is the only thing the control says. The cascade does the rest — ResolveLayer
      applies :selected first as the resting layer and :disabled LAST at the highest
      precedence, so the chip survives while the disabled ink wins over it.
      Hover and focus are deliberately absent: a disabled control takes neither. }
    Include(Result, tysDisabled);
    Exit;
  end;
  { No tysFocused here, deliberately: focus belongs to the WHOLE track, not to a segment.
    That is how the platform's segmented controls read (one ring around the widget; the
    chip alone says which option is current), and it needs no code — the base's
    CurrentStates already hands tysFocused to the TRACK's own style, so a plain
    'TySegmented:focus { outline: ... }' rule rings it through DrawFrame like every other
    focusable control here. A ring on the segment would need this paint to stroke outlines
    itself, and the token would be a dead letter until it did. }
  if AIndex = FHoverIndex then Include(Result, tysHover);
  if Result = [] then Include(Result, tysNormal);
end;

function TTySegmented.ItemStyle(AIndex: Integer): TTyStyleSet;
begin
  Result := ActiveController.Model.ResolveStyle('TySegmentedItem', StyleClass,
    ItemStates(AIndex));
end;

function TTySegmented.ItemTextStyle(const ATrack, AItem: TTyStyleSet): TTyStyleSet;
{ The label's ink and font: the segment's own where the theme sets them, the track's
  otherwise. This is the house degradation rule (no colour => inherit the parent's ink)
  extended to the font by the same logic — a theme that styles only TySegmented must still
  get legible, correctly-sized labels, and NEVER a hard-coded colour. }
begin
  Result := AItem;
  if not (tpTextColor in AItem.Present) then
  begin
    Result.TextColor := ATrack.TextColor;
    if tpTextColor in ATrack.Present then Include(Result.Present, tpTextColor);
  end;
  if not (tpFontName in AItem.Present) then
  begin
    Result.FontName := ATrack.FontName;
    if tpFontName in ATrack.Present then Include(Result.Present, tpFontName);
  end;
  if not (tpFontSize in AItem.Present) then
  begin
    Result.FontSize := ATrack.FontSize;
    if tpFontSize in ATrack.Present then Include(Result.Present, tpFontSize);
  end;
  if not (tpFontWeight in AItem.Present) then
  begin
    Result.FontWeight := ATrack.FontWeight;
    if tpFontWeight in ATrack.Present then Include(Result.Present, tpFontWeight);
  end;
end;

{ --- measurement ---------------------------------------------------------------------- }

procedure TTySegmented.MeasureItems(APPI: Integer; const AStyle: TTyStyleSet;
  out AWidestPx, ALineHeightPx: Integer);
{ Measures with a CANVAS-LESS painter — the TTyBadge idiom: BeginPaint(nil, ...) builds
  only the painter's internal bitmap and EndPaint frees it WITHOUT blitting, so this is
  safe outside a paint cycle and leaks nothing. It has to be the painter and not an LCL
  canvas: the labels are drawn with BGRA text metrics, and only the same measurer
  reproduces the extent those glyphs actually render at. }
var
  P: TTyPainter;
  sz: TSize;
  i, fs: Integer;
begin
  AWidestPx := 0;
  ALineHeightPx := 0;
  P := TTyPainter.Create;
  try
    P.BeginPaint(nil, Rect(0, 0, 1, 1), APPI);   // 1x1: nothing is drawn, only measured
    fs := ResolveFontSize(AStyle);
    // A stable reference glyph: a blank label still sizes the track to one line.
    sz := P.MeasureText('Ag', AStyle.FontName, fs, AStyle.FontWeight);
    ALineHeightPx := sz.cy;
    for i := 0 to FItems.Count - 1 do
    begin
      sz := P.MeasureText(FItems[i], AStyle.FontName, fs, AStyle.FontWeight);
      if sz.cx > AWidestPx then AWidestPx := sz.cx;
    end;
    P.EndPaint;   // nil canvas -> no blit, just frees the measure bitmap
  finally
    P.Free;
  end;
  if AWidestPx < 0 then AWidestPx := 0;
  if ALineHeightPx < 1 then ALineHeightPx := 1;
end;

procedure TTySegmented.CalculatePreferredSize(var PreferredWidth,
  PreferredHeight: Integer; WithThemeSpace: Boolean);
var
  segStyle: TTyStyleSet;   // not 'itemS'/'itemStyle': Pascal is case-insensitive, so those
                           // collide with the Items property and the ItemStyle method.
  ppi, widest, lineH, pad: Integer;
begin
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  // Measured against the RESTING segment style: a theme that makes the selected chip bold
  // must not make the track's width depend on which segment is currently selected.
  segStyle := ActiveController.Model.ResolveStyle('TySegmentedItem', StyleClass, [tysNormal]);
  // MEASURE with the same font the paint DRAWS with: the label inherits the TRACK's font via
  // ItemTextStyle, so a theme that sets a font on TySegmented but not TySegmentedItem must size
  // segments to that font — else they are measured for the default and the paint clips the
  // labels. (ItemTextStyle preserves the segment's own padding; only ink/font are inherited.)
  segStyle := ItemTextStyle(
    ActiveController.Model.ResolveStyle('TySegmented', StyleClass, [tysNormal]), segStyle);
  MeasureItems(ppi, segStyle, widest, lineH);
  pad := PadPx(ppi);
  PreferredWidth := TySegmentedPreferredWidth(FItems.Count, widest,
    MulDiv(segStyle.Padding.Left, ppi, 96), MulDiv(segStyle.Padding.Right, ppi, 96),
    pad, MinWidthPx(ppi));
  PreferredHeight := lineH + MulDiv(segStyle.Padding.Top + segStyle.Padding.Bottom, ppi, 96)
    + 2 * pad;
  if PreferredWidth < 1 then PreferredWidth := 1;
  if PreferredHeight < 1 then PreferredHeight := 1;
end;

{ --- input ---------------------------------------------------------------------------- }

procedure TTySegmented.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  i: Integer;
begin
  if not Enabled then Exit;
  // A track with no themed background paints NOTHING (RenderTo early-exits on the same test),
  // so a click on apparent blank space must not silently select a segment and fire OnChange.
  if not (tpBackground in CurrentStyle.Present) then Exit;
  // The base sets FPressed and moves focus here (TabStop + CanFocus), so a click behaves
  // like a Tab and the arrow keys work straight after it.
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  // Select on PRESS, not on release: a segmented control is a switch, and the house tab
  // strip switches on press too. A press in the padding gutter answers -1 and is inert —
  // it must not clear a selection the user can see.
  i := TySegmentAt(X, Y);
  if i >= 0 then ItemIndex := i;
end;

procedure TTySegmented.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  i: Integer;
begin
  if not Enabled then Exit;
  if not (tpBackground in CurrentStyle.Present) then Exit;   // invisible track: no hover
  inherited MouseMove(Shift, X, Y);
  i := TySegmentAt(X, Y);
  if i <> FHoverIndex then
  begin
    FHoverIndex := i;
    Invalidate;
  end;
end;

procedure TTySegmented.MouseLeave;
begin
  inherited MouseLeave;   // clears the track's own hover
  if FHoverIndex <> -1 then
  begin
    FHoverIndex := -1;
    Invalidate;
  end;
end;

procedure TTySegmented.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if not Enabled then Exit;
  if not (tpBackground in CurrentStyle.Present) then Exit;   // invisible track: inert
  inherited KeyDown(Key, Shift);
  if FItems.Count = 0 then Exit;
  { Left/Right move the selection — the reason this control is focusable at all. Every
    handled key is consumed (Key := 0) so it never also reaches the form. Home/End jump to
    the ends, matching TTyCustomTabStrip's keyboard. }
  case Key of
    VK_LEFT:
      begin
        ItemIndex := TySegmentedStepIndex(FItemIndex, FItems.Count, -1);
        Key := 0;
      end;
    VK_RIGHT:
      begin
        ItemIndex := TySegmentedStepIndex(FItemIndex, FItems.Count, 1);
        Key := 0;
      end;
    VK_HOME:
      begin
        ItemIndex := 0;
        Key := 0;
      end;
    VK_END:
      begin
        ItemIndex := FItems.Count - 1;
        Key := 0;
      end;
  end;
end;

{ --- painting ------------------------------------------------------------------------- }

procedure TTySegmented.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, segStyle, txtS: TTyStyleSet;
  R, segR, txtR: TRect;
  i, pad: Integer;
begin
  P := TTyPainter.Create;
  try
    // A (0,0)-local rect: the painter builds a (W x H) bitmap and blits it at
    // ARect.Left/Top, so a non-zero ARect origin would shift the whole control.
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    // The track: background + border + shadow + opacity, all from the resolved TySegmented
    // style. DrawFrame fills the parent's opaque surface first, which a WINDOWED control
    // needs whatever the theme says (its own window shows through the corner gaps
    // otherwise) — everything of OURS below is gated on the theme having defined the key.
    DrawFrame(P, R, S);
    if not (tpBackground in S.Present) then
    begin
      // No TySegmented rule -> draw nothing at all, degrade rather than invent a look.
      P.EndPaint;
      Exit;
    end;

    pad := PadPx(APPI);
    for i := 0 to FItems.Count - 1 do
    begin
      segR := TySegmentedItemRect(R.Right, R.Bottom, FItems.Count, pad, i);
      if (segR.Right <= segR.Left) or (segR.Bottom <= segR.Top) then Continue;
      segStyle := ItemStyle(i);

      // The chip. An undefined TySegmentedItem key leaves no background -> no chip, and
      // the labels below still draw: a theme that fills only :selected gets the classic
      // "only the chosen one has a thumb" for free, with no code branch of its own.
      if tpBackground in segStyle.Present then
        P.FillBackground(segR, segStyle.Background, TyEffectiveCorners(segStyle));
      if TyBorderVisible(segStyle) then
        P.StrokeBorder(segR, TyEffectiveCorners(segStyle), segStyle.BorderWidth,
          segStyle.BorderColor);

      // The label, centred in the chip's padded band and ellipsised: a segment narrower
      // than its label shows 'Mon…', not a glyph sheared at the clip edge. No mnemonic
      // parsing — an '&' in a segment is literal text (there is no Alt+key path here).
      txtS := ItemTextStyle(S, segStyle);
      txtR := Rect(segR.Left + P.Scale(segStyle.Padding.Left),
                   segR.Top + P.Scale(segStyle.Padding.Top),
                   segR.Right - P.Scale(segStyle.Padding.Right),
                   segR.Bottom - P.Scale(segStyle.Padding.Bottom));
      if (txtR.Right > txtR.Left) and (txtR.Bottom > txtR.Top) then
        P.DrawText(txtR, FItems[i], txtS.FontName, ResolveFontSize(txtS),
          txtS.FontWeight, txtS.TextColor, taCenter, tlCenter, True);
    end;

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTySegmented.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
