unit tyControls.ToolBar;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Button,
  tyControls.GlyphButtons, tyControls.ImageCollection,
  tyControls.Controller;
type
  TTyToolSeparator = class(TTyCustomControl)
  protected
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property Align;
    property StyleClass;
    property Controller;
  end;

  TTyToolBar = class(TTyCustomControl)
  private
    FButtonHeight: Integer;
    FButtonHeightExplicit: Boolean;
    FButtonSpacing: Integer;
    FIndent: Integer;
    FWrapable: Boolean;
    FShowCaptions: Boolean;
    FFlat: Boolean;
    FImages: TTyImageCollection;
    { The collection this bar last LENT to its tools. A tool still holding it is one we
      handed it to, so we may re-point or take it back; anything else is the host's own
      choice and is left alone. Nil'd with FImages in Notification — a freed collection's
      address can be re-used, and a stale marker would make us adopt a stranger's. }
    FLentImages: TTyImageCollection;
    FInLayout: Boolean;
    function GetButtonHeight: Integer;
    procedure SetButtonHeight(AValue: Integer);
    procedure SetButtonSpacing(AValue: Integer);
    procedure SetIndent(AValue: Integer);
    procedure SetWrapable(AValue: Boolean);
    procedure SetShowCaptions(AValue: Boolean);
    procedure SetImages(AValue: TTyImageCollection);
    procedure SetFlat(AValue: Boolean);
    procedure Relayout;
  protected
    { The vertical breathing room above the first row and below the last, in logical px.
      Theme-driven (--toolbar-pad-y) rather than a published property: it is chrome, and
      the fallback is 4 — byte-for-byte the value Indent used to supply here, so no
      existing bar changes height. Protected because TTyToolBarEx lays its own row out and
      must use the SAME pad, or the two bars would sit their tools at different heights. }
    function ContentPadY: Integer;
    { Protected rather than private so a test can drive the one call a relayout makes
      without needing a window handle and a live align pass. }
    procedure ApplyToButton(B: TTyButton);
    { Push Images + ShowCaptions onto every tool that can draw an icon. Protected for the
      same reason. }
    procedure ApplyToolProperties;
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure AlignControls(AControl: TControl; var ARect: TRect); override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure InsertControl(AControl: TControl; Index: Integer); override;
  published
    { Density-aware: unset follows --control-height (classic 24 / modern 38). A host/.lfm value
      pins it (streamed only when explicitly set -- stored FButtonHeightExplicit). }
    property ButtonHeight: Integer read GetButtonHeight write SetButtonHeight stored FButtonHeightExplicit;
    property ButtonSpacing: Integer read FButtonSpacing write SetButtonSpacing default 2;
    { Blank space at the LEADING edge of the bar, before the first tool — and nothing else.
      LCL's TToolBar.Indent (comctrls.pp:2398) means exactly that, and ours used to mean
      two more things besides: it was also the TOP pad every row started at, and the bar's
      auto-grown height was `Indent*2 + rows`. So `Indent := 24` — a perfectly ordinary LCL
      value, used to clear a logo or a leading label — silently made the bar 48 px taller
      and pushed its tools down 24 px, which is not what any LCL form that set it asked for.
      The vertical breathing room is now its own value (ContentPadY, theme token
      --toolbar-pad-y, default 4 = the old Indent default), so the two knobs move apart.

      Still differs from LCL in one respect: LCL's default is 1, ours is 4. That one is left
      alone on purpose — a `default` directive is what decides how every existing .lfm that
      OMITTED the value is read, so changing it would re-indent every toolbar already out
      there. A ported form that relied on LCL's 1 should set Indent := 1 explicitly. }
    property Indent: Integer read FIndent write SetIndent default 4;
    property Wrapable: Boolean read FWrapable write SetWrapable default True;
    { LCL parity: False (the default) makes the tools ICON-ONLY, True draws their captions.
      It reaches every child that CAN draw an icon (TTyGlyphButtonBase — TTyGlyphButton /
      TTySpeedButton / TTyGlyphContainerButton) via AdoptShowCaption, which is a no-op on
      any tool whose ShowCaption the host set itself. A plain TTyButton has no glyph model
      at all and is untouched, and a glyph tool with no icon keeps its caption rather than
      painting an empty box — so the False default can never blank an existing toolbar. }
    property ShowCaptions: Boolean read FShowCaptions write SetShowCaptions default False;
    property Flat: Boolean read FFlat write SetFlat default True;
    { The icon source the tools draw from: a child glyph button that has no Images of its
      own is LENT this collection, so tools only need an ImageName. A tool carrying its own
      collection keeps it — the bar re-points or takes back only the reference IT lent.

      A TTyImageCollection, NOT an LCL TImageList: every icon in this library comes from
      the name-keyed BGRA collection (see tyControls.ImageCollection), so a TImageList here
      could never reach a tool button no matter what a host assigned — which is exactly why
      this property used to do nothing. }
    property Images: TTyImageCollection read FImages write SetImages;
    property Align default alTop;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

{ AIndent is the LEADING (horizontal) gap before the first tool on every row; ATopPad is the
  vertical gap above the first row. They used to be one number, so a bar could not be indented
  without also being padded — see TTyToolBar.Indent.

  ABreakBefore is a FORCED row division, parallel to AItemSizes: item i opens a new row whether
  or not it would have fitted. It is what LCL's TToolButton.Wrap needs and what the width rule
  alone can never express — a group division the width did not ask for. Same shape and same
  tolerance as TyCoolBarPack's ABreaks (tyControls.CoolBar): a SHORTER array is legal and a
  missing entry reads as False, so a caller that knows only the leading flags may pass just
  those, and an empty array means "no breaks at all".

  Two rules that are not obvious:

  * The flag is LEADING — "item i STARTS a row" — matching TyCoolBarPack. LCL's Wrap is
    TRAILING: toolbar.inc:1003 applies it in the step-to-next-position, so it moves the NEXT
    control. The mapping is `breakBefore[i] := (i > 0) and wrapAfter[i-1]`, and it is pinned by
    a test rather than left for the caller to rediscover. Leading also makes an empty row
    unrepresentable: a break on item 0 has no row above it to leave and is ignored, where LCL's
    trailing Wrap on the LAST button still bumps its FRowCount and leaves the bar a row too tall.

  * The break is honoured REGARDLESS of AWrapable. With AWrapable=False this is exactly LCL's
    behaviour (that is the only mode in which LCL reads Wrap at all); with AWrapable=True we
    additionally let an explicit break compose with the width rule, which LCL does not. Honouring
    a division the host asked for in so many words is not a surprise, and refusing it would put
    the feature out of reach of the default bar — Wrapable defaults to True here. }
function TyToolbarLayout(const AItemSizes: array of TSize; ABarWidth, AIndent, ATopPad, ASpacing, AButtonHeight: Integer; AWrapable: Boolean; out ARows: Integer): TTyRectArray; overload;
function TyToolbarLayout(const AItemSizes: array of TSize; const ABreakBefore: array of Boolean;
  ABarWidth, AIndent, ATopPad, ASpacing, AButtonHeight: Integer; AWrapable: Boolean;
  out ARows: Integer): TTyRectArray; overload;

implementation

{ The break-free entry point is a pure DELEGATION, not a second copy of the loop: there is one
  implementation, so "no break set lays out exactly as it did before" is true by construction
  rather than by two bodies being kept in step. Kept as an overload rather than folded into the
  new signature because every existing caller — the control below, and the tests that pin its
  arithmetic — passes no flags, and a source break for all of them buys nothing. }
function TyToolbarLayout(const AItemSizes: array of TSize; ABarWidth, AIndent, ATopPad, ASpacing, AButtonHeight: Integer; AWrapable: Boolean; out ARows: Integer): TTyRectArray;
var
  noBreaks: array of Boolean;   // nil -> Length 0 -> every entry reads as False
begin
  noBreaks := nil;
  Result := TyToolbarLayout(AItemSizes, noBreaks, ABarWidth, AIndent, ATopPad, ASpacing,
    AButtonHeight, AWrapable, ARows);
end;

function TyToolbarLayout(const AItemSizes: array of TSize; const ABreakBefore: array of Boolean;
  ABarWidth, AIndent, ATopPad, ASpacing, AButtonHeight: Integer; AWrapable: Boolean;
  out ARows: Integer): TTyRectArray;
var
  i, x, y: Integer;
  brk: Boolean;
begin
  Result := nil;
  SetLength(Result, Length(AItemSizes));
  ARows := 1;
  x := AIndent; y := ATopPad;
  for i := 0 to High(AItemSizes) do
  begin
    { A missing flag reads as False, so a short (or absent) array is legal — TyCoolBarPack's
      tolerance, and what makes the break-free overload a delegation rather than a fork. }
    brk := (i < Length(ABreakBefore)) and ABreakBefore[i];
    { `i > 0` guards BOTH rules, which is what keeps the break from opening an empty leading
      row. It also leaves the width rule byte-for-byte what it was: with brk always False this
      whole condition collapses to `AWrapable and (i > 0) and overflow` — the original, with its
      operands merely regrouped. The break is deliberately OUTSIDE the AWrapable test: see the
      interface comment for why it is honoured in both modes. }
    if (i > 0) and (brk or (AWrapable and (x + AItemSizes[i].cx > ABarWidth - AIndent))) then
    begin
      x := AIndent; Inc(y, AButtonHeight + ASpacing); Inc(ARows);
    end;
    Result[i].Left := x;
    Result[i].Top := y;
    Result[i].Right := x + AItemSizes[i].cx;
    Result[i].Bottom := y + AButtonHeight;
    Inc(x, AItemSizes[i].cx + ASpacing);
  end;
end;

{ TTyToolSeparator }
constructor TTyToolSeparator.Create(AOwner: TComponent);
begin inherited Create(AOwner); Width := 8; Height := TyDensityHeight(ActiveController, 24); end;
// Its own key, NOT the bar's. The separator draws ink the bar does not — an inset
// vertical rule — and borrowing 'TyToolBar' made that rule the SAME colour as the bar's
// own bottom hairline BY CONSTRUCTION, so a theme could not dim, thicken or suppress the
// divider while keeping the bar's edge (the classic "lighter inset divider on a bordered
// bar"). It needs background too: that fill is what keeps the separator seamless with
// the bar it sits on.
function TTyToolSeparator.GetStyleTypeKey: string; begin Result := 'TyToolSeparator'; end;
procedure TTyToolSeparator.Paint; begin RenderTo(Canvas, ClientRect, Font.PixelsPerInch); end;
procedure TTyToolSeparator.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var P: TTyPainter; S: TTyStyleSet; W, H: Integer; line: TTyFill;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    W := ARect.Right - ARect.Left; H := ARect.Bottom - ARect.Top;
    FillSharpBackdrop(P, Rect(0, 0, W, H));   // photo through the separator on an image theme (no-op on solid)
    if tpBackground in S.Present then
      P.FillBackground(Rect(0, 0, W, H), S.Background, 0);   // match the toolbar bg (seamless on solid; transparent->photo on green)
    line := Default(TTyFill); line.Kind := tfkSolid; line.Color := S.BorderColor;
    P.FillBackground(Rect(W div 2, P.Scale(3), W div 2 + 1, H - P.Scale(3)), line, 0);
    P.EndPaint;
  finally P.Free; end;
end;

{ TTyToolBar }
constructor TTyToolBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csAcceptsControls];   // hosts the tool buttons
  FButtonHeight := 24; FButtonHeightExplicit := False;   // follow --control-height (density-aware) until set
  FButtonSpacing := 2; FIndent := 4; FWrapable := True; FFlat := True;
  Align := alTop;
  Width := 300; Height := 30;
end;

function TTyToolBar.GetStyleTypeKey: string; begin Result := 'TyToolBar'; end;

function TTyToolBar.ContentPadY: Integer;
begin
  Result := ActiveController.Metric('--toolbar-pad-y', 4);
  if Result < 0 then Result := 0;
end;

function TTyToolBar.GetButtonHeight: Integer;
begin
  if FButtonHeightExplicit then
    Result := FButtonHeight
  else
    Result := TyDensityMetric(ActiveController, 24, '--control-height');
end;
procedure TTyToolBar.SetButtonHeight(AValue: Integer); begin FButtonHeightExplicit := True; if FButtonHeight = AValue then Exit; FButtonHeight := AValue; Relayout; end;
procedure TTyToolBar.SetButtonSpacing(AValue: Integer); begin if FButtonSpacing = AValue then Exit; FButtonSpacing := AValue; Relayout; end;
procedure TTyToolBar.SetIndent(AValue: Integer); begin if FIndent = AValue then Exit; FIndent := AValue; Relayout; end;
procedure TTyToolBar.SetWrapable(AValue: Boolean); begin if FWrapable = AValue then Exit; FWrapable := AValue; Relayout; end;
procedure TTyToolBar.SetShowCaptions(AValue: Boolean); begin if FShowCaptions = AValue then Exit; FShowCaptions := AValue; ApplyToolProperties; Relayout; end;
procedure TTyToolBar.SetFlat(AValue: Boolean); begin if FFlat = AValue then Exit; FFlat := AValue; Relayout; end;

procedure TTyToolBar.SetImages(AValue: TTyImageCollection);
begin
  if FImages = AValue then Exit;
  // FreeNotification, not just the Notification override: opRemove only reaches us for a
  // component we asked about. A collection that is not owned by our owner (created with
  // Owner = nil, or living on another form) would be freed without a word, leaving FImages
  // AND every reference we lent to the tools dangling.
  if FImages <> nil then FImages.RemoveFreeNotification(Self);
  FImages := AValue;
  if FImages <> nil then FImages.FreeNotification(Self);
  ApplyToolProperties;
  Relayout;
end;

procedure TTyToolBar.ApplyToButton(B: TTyButton);
begin
  // Reuse the ghost/flat TTyButton look, but only over a class the bar itself put
  // there. Assigning unconditionally (which is what this did) meant every relayout
  // wiped a caller's StyleClass := 'primary' -- and a relayout runs on any metric
  // change, so the styling vanished at an unpredictable moment rather than at once.
  if FFlat then
  begin
    if B.StyleClass = '' then B.StyleClass := 'ghost';
  end
  else
    if B.StyleClass = 'ghost' then B.StyleClass := '';
  // Images/ShowCaptions are NOT pushed from here: this runs on every relayout (many per
  // resize), and re-asserting host-visible state that often is what made the StyleClass
  // handling above a bug in the first place. They are applied by ApplyToolProperties at
  // the three moments they can actually change -- the two setters and a tool joining.
end;

procedure TTyToolBar.ApplyToolProperties;
var
  i: Integer;
  G: TTyGlyphButtonBase;
begin
  if csDestroying in ComponentState then Exit;
  for i := 0 to ControlCount - 1 do
  begin
    // Only a glyph button has an icon model to point at a collection; a plain TTyButton
    // (or a separator) has nothing to draw an image with, so the bar leaves it alone.
    if not (Controls[i] is TTyGlyphButtonBase) then Continue;
    G := TTyGlyphButtonBase(Controls[i]);
    // Lend the bar's collection ONLY to a tool that has none, or that still holds the one
    // we lent last time. A tool with its own collection keeps it: the bar manages the
    // reference it put there and nothing else.
    if (G.Images = nil) or (G.Images = FLentImages) then
      G.Images := FImages;
    // Container default; a no-op on any tool whose ShowCaption the host wrote itself.
    G.AdoptShowCaption(FShowCaptions);
  end;
  // Remember what a later pass must recognise as "ours to re-point or take back".
  FLentImages := FImages;
end;

procedure TTyToolBar.InsertControl(AControl: TControl; Index: Integer);
begin
  inherited InsertControl(AControl, Index);
  // A tool can join the bar long after Images/ShowCaptions were set (code that builds the
  // bar top-down, an .lfm whose component references are fixed up last, or TTyToolBarEx
  // handing a button back from its overflow flyout), so the bar's icon source is applied
  // HERE as well as in the setters. Doing it here rather than in the layout pass also
  // means TTyToolBarEx — which overrides AlignControls and never calls ApplyToButton —
  // still hands its tools the bar's icons.
  ApplyToolProperties;
end;

procedure TTyToolBar.Relayout;
begin
  if csDestroying in ComponentState then Exit;
  Realign;        // re-runs AlignControls over the children
  Invalidate;
end;

procedure TTyToolBar.AlignControls(AControl: TControl; var ARect: TRect);
var
  ih: Integer;
  i, n, rows: Integer;
  sizes: array of TSize;
  rects: TTyRectArray;
  ctl: TControl;
  list: array of TControl;
  newH, bh, padY: Integer;
begin
  // re-entrancy guard: Height assignment at the end triggers another AlignControls call
  if FInLayout then Exit;
  FInLayout := True;
  try
    // collect visible children in child order
    SetLength(list, ControlCount); n := 0;
    for i := 0 to ControlCount - 1 do
    begin
      ctl := Controls[i];
      if ctl.Visible then begin list[n] := ctl; Inc(n); end;
    end;
    SetLength(list, n); SetLength(sizes, n);
    for i := 0 to n - 1 do
    begin
      if list[i] is TTyButton then ApplyToButton(TTyButton(list[i]));
      sizes[i].cx := list[i].Width;
      sizes[i].cy := list[i].Height;  // cy is not used by TyToolbarLayout (AButtonHeight governs row height)
    end;
    { ButtonHeight is what the bar ASKS for; a child may refuse to be that short. Controls
      whose caption decides their size publish Constraints.MinHeight, and SetBounds clamps to
      it -- so a row sized purely from ButtonHeight left the child overflowing DOWNWARD out
      of its slot: it covered the bar's bottom border and stopped lining up with the children
      that did fit. Take the tallest floor in the row first, then lay out against that. }
    bh := GetButtonHeight;
    for i := 0 to n - 1 do
      if list[i].Constraints.MinHeight > bh then bh := list[i].Constraints.MinHeight;
    padY := ContentPadY;
    rects := TyToolbarLayout(sizes, ClientWidth, FIndent, padY, FButtonSpacing, bh, FWrapable, rows);
    for i := 0 to n - 1 do
    begin
      { Centre each child in the row. A child SHORTER than the row (a separator, a combo that
        is happy at 24 while a CJK caption needs 29) must sit on the row's centre line, or the
        bar reads as ragged -- which is the second half of the same report. }
      ih := list[i].Height;
      if ih > bh then ih := bh;
      if list[i].Constraints.MinHeight > ih then ih := list[i].Constraints.MinHeight;
      list[i].SetBounds(rects[i].Left, rects[i].Top + (bh - ih) div 2, list[i].Width, ih);
    end;
    // grow the bar to fit the rows when alTop/alBottom
    if (Align in [alTop, alBottom]) and (rows > 0) then
    begin
      // The VERTICAL pad closes the bar, top and bottom -- Indent is horizontal and has no
      // business in a height (a bar indented 24px to clear a logo was 48px taller for it).
      newH := padY*2 + rows*bh + (rows-1)*FButtonSpacing;
      if Height <> newH then
        Height := newH;
    end;
  finally
    FInLayout := False;
  end;
end;

procedure TTyToolBar.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if Operation = opRemove then
  begin
    if AComponent = FImages then FImages := nil;
    // Clear the lent-marker too. It points at the same object; left stale it would be a
    // dangling address that a freshly allocated collection could land on, and the next
    // pass would then mistake a tool's OWN collection for one of ours and overwrite it.
    if AComponent = FLentImages then FLentImages := nil;
  end;
end;

procedure TTyToolBar.Paint; begin RenderTo(Canvas, ClientRect, Font.PixelsPerInch); end;
procedure TTyToolBar.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var P: TTyPainter; S: TTyStyleSet; W, H, bw: Integer; bg: TTyFill;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    W := ARect.Right - ARect.Left; H := ARect.Bottom - ARect.Top;
    // Lay the form's photo down FIRST so an alpha CSS background tints the photo (glass),
    // like TTyPanel. No-op (False) on solid/non-image themes -> their look is unchanged.
    FillSharpBackdrop(P, Rect(0, 0, W, H));
    // Paint S.Background directly (not a solid bg.Color rebuild) so an alpha() background is
    // honored OVER the backdrop instead of replacing it with an opaque tint.
    if tpBackground in S.Present then P.FillBackground(Rect(0, 0, W, H), S.Background, 0);
    bg := Default(TTyFill); bg.Kind := tfkSolid;
    bw := P.Scale(S.BorderWidth); if bw < 1 then bw := 1;
    if tpBorderColor in S.Present then
    begin
      bg.Color := S.BorderColor;
      P.FillBackground(Rect(0, H - bw, W, H), bg, 0);   // bottom hairline
    end;
    P.EndPaint;
  finally P.Free; end;
end;

end.
