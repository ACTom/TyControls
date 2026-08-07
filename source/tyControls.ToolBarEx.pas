unit tyControls.ToolBarEx;
{$mode objfpc}{$H+}

{ TTyToolBarEx — a TTyToolBar that adds an OVERFLOW chevron.

  When the bar is NOT wrapping (Wrapable = False) and its tool buttons are wider than
  the bar, the trailing buttons that don't fit are hidden and a "»" chevron button
  (csNoDesignVisible, docked at the right edge) appears. Clicking it opens a
  TTyPopupSurface hosting those overflow buttons in a vertical stack; picking one still
  fires its own OnClick (the button is only re-parented, never re-created).

  On resize the overflow set is recomputed (via the pure TyToolbarOverflowCount solver,
  which mirrors the ribbon's TyRibbonOverflowCount style) and the chevron is shown/hidden
  automatically — there is no published toggle for it.

  Wrapable = True behaves EXACTLY like the base TTyToolBar (the chevron path is skipped
  entirely and the base wrapping layout runs); only the non-wrapping overflow path is new.

  The fit decision + the which-buttons-are-hidden set are the pure/thin-shell seam that is
  headless-unit-tested; the on-screen popup adopt/show + click routing need a real machine. }

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, Forms,
  tyControls.Base, tyControls.Button, tyControls.StrConsts,
  tyControls.PopupSurface, tyControls.ToolBar;

type
  TTyToolBarEx = class(TTyToolBar)
  private
    FMoreBtn: TTyButton;                 // the "»" chevron (csNoDesignVisible, owned by Self)
    FPopup: TTyPopupSurface;             // hosts the overflow buttons while open
    FOverflow: array of TControl;        // the buttons currently hidden into the overflow set
    FPopupItems: array of TControl;      // authoritative copy of the buttons adopted into the OPEN
                                         // flyout — restore (PopupClosed/Destroy) uses THIS, not the
                                         // FOverflow that relayouts rebuild underneath us
    FSavedClicks: array of TNotifyEvent; // each adopted button's own OnClick, parallel to FPopupItems;
                                         // restored on close (we temporarily wrap it to auto-dismiss)
    FInExLayout: Boolean;                // re-entrancy guard for the overflow relayout
    FPopupOpen: Boolean;                 // flyout is open/opening: freeze the fit-relayout so the
                                         // reparent-into-popup pass can't rebuild FOverflow mid-loop
    procedure EnsureMoreButton;
    procedure MoreClick(Sender: TObject);
    procedure PopupItemClick(Sender: TObject);
    procedure DeferredClosePopup(Data: PtrInt);
    procedure PopupClosed(Sender: TObject);
    procedure ClearOverflow;
    function ChevronWidthPx: Integer;
    function IsInternalChild(AControl: TControl): Boolean;
  protected
    procedure AlignControls(AControl: TControl; var ARect: TRect); override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { The count of buttons currently pushed into the overflow popup (0 = all fit / the bar
      is wrapping). Exposed for tests + host code that wants to reflect the overflow state. }
    function OverflowCount: Integer;
    { True when the "»" chevron is currently shown. }
    function OverflowVisible: Boolean;
  published
    property Wrapable;
  end;

{ Pure overflow decision (device px, left-to-right): given each lead button's width and the
  available bar width, return how many LEADING buttons fit before the "»" chevron is needed.
  When every button fits (their total <= AAvailPx) the result is Length(AButtonWidths) and NO
  chevron is required. Otherwise the chevron (AChevronW wide) is reserved at the right and the
  result is how many lead buttons fit in the remaining space — ALWAYS at least 1 (the first
  button shows even if it alone overflows). Headless-testable; mirrors TyRibbonOverflowCount. }
function TyToolbarOverflowCount(const AButtonWidths: array of Integer;
  AAvailPx, AChevronW: Integer): Integer;

implementation

// ---------------------------------------------------------------------------
// Pure fit decision
// ---------------------------------------------------------------------------
function TyToolbarOverflowCount(const AButtonWidths: array of Integer;
  AAvailPx, AChevronW: Integer): Integer;
var
  n, i, total, avail: Integer;
begin
  n := Length(AButtonWidths);
  if n = 0 then Exit(0);
  if AChevronW < 0 then AChevronW := 0;

  // Everything fits with no chevron?
  total := 0;
  for i := 0 to n - 1 do Inc(total, AButtonWidths[i]);
  if total <= AAvailPx then Exit(n);

  // Overflowing: reserve the chevron on the right, then count the lead buttons that fit in
  // the remaining space. Always show at least the first button.
  avail := AAvailPx - AChevronW;
  Result := 0;
  total := 0;
  for i := 0 to n - 1 do
  begin
    if (Result > 0) and (total + AButtonWidths[i] > avail) then Exit;
    Inc(total, AButtonWidths[i]);
    Inc(Result);
  end;
end;

// ===========================================================================
// TTyToolBarEx
// ===========================================================================
constructor TTyToolBarEx.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Overflow is the differentiator, so default to the non-wrapping mode where it applies.
  Wrapable := False;
end;

destructor TTyToolBarEx.Destroy;
var i: Integer;
begin
  Application.RemoveAsyncCalls(Self);   // drop any queued DeferredClosePopup before we go
  // If we're freed while the overflow popup is still open, its adopted buttons (form-owned but
  // re-parented INTO the popup) would be left orphaned: freeing the popup only un-parents them
  // (Parent := nil) — it neither frees them (the form owns them) nor restores them, and the
  // normal PopupClosed restore is skipped under csDestroying. Re-home them to OUR parent (the
  // surviving container) first so they stay reachable/freeable and never dangle invisible.
  if (FPopup <> nil) and FPopup.Visible and (Parent <> nil) then
    for i := 0 to High(FPopupItems) do
      if FPopupItems[i] <> nil then
      begin
        FPopupItems[i].Parent := Parent;
        FPopupItems[i].Visible := False;   // they were hidden overflow — don't leave strays showing
      end;
  FreeAndNil(FPopup);
  inherited Destroy;
end;

function TTyToolBarEx.ChevronWidthPx: Integer;
begin
  // The chevron's cell width, in the SAME units the base layout works in (ClientWidth /
  // Indent / ButtonSpacing are all treated as logical px by TyToolbarLayout, and match
  // device px at PPI 96). A compact fixed cell like the ribbon's "more" button.
  Result := 30;
end;

function TTyToolBarEx.IsInternalChild(AControl: TControl): Boolean;
begin
  Result := (AControl <> nil) and (AControl = FMoreBtn);
end;

procedure TTyToolBarEx.EnsureMoreButton;
begin
  if FMoreBtn <> nil then Exit;
  FMoreBtn := TTyButton.Create(Self);       // owned by Self -> freed with the bar
  FMoreBtn.Parent := Self;
  // Not a tab stop: this chevron only exists while the bar overflows, and a stop that
  // appears and disappears with the window width is worse than no stop at all. (TTyButton
  // is a tab stop by default; the bar's own speed buttons are not either.)
  FMoreBtn.TabStop := False;
  FMoreBtn.Caption := '»';
  FMoreBtn.Hint := rsToolBarMoreCommands;
  FMoreBtn.ShowHint := True;
  FMoreBtn.StyleClass := 'ghost';            // match the flat toolbar look
  FMoreBtn.OnClick := @MoreClick;
  // Internal helper: keep it out of the IDE designer's child list.
  FMoreBtn.ControlStyle := FMoreBtn.ControlStyle + [csNoDesignVisible];
  FMoreBtn.Visible := False;
end;

procedure TTyToolBarEx.ClearOverflow;
begin
  SetLength(FOverflow, 0);
end;

procedure TTyToolBarEx.AlignControls(AControl: TControl; var ARect: TRect);
var
  i, n, visCount, x, chevW, padY, rowH, rowTop, bottomBorder: Integer;
  kids: array of TControl;
  widths: array of Integer;
  ctl: TControl;
begin
  // Wrapping path is 100% the base behaviour — the chevron is not used.
  if Wrapable then
  begin
    if FMoreBtn <> nil then FMoreBtn.Visible := False;
    inherited AlignControls(AControl, ARect);
    Exit;
  end;
  // Flyout open/opening: FREEZE the layout. MoreClick sets FPopupOpen BEFORE reparenting the
  // overflow buttons OUT, and each reparent fires AlignControls; doing nothing here keeps the
  // remaining lead buttons AND the chevron exactly where the last closed-state layout put them
  // (no re-flow, no chevron shift), and leaves FOverflow intact for MoreClick's loop.
  if FPopupOpen then Exit;

  if FInExLayout then Exit;
  FInExLayout := True;
  try
    // Collect content children (everything except the chevron) in child order. Our own
    // overflow-hidden buttons remain candidates: they are re-shown below so the fit is
    // re-computed over the FULL set every layout (a wider bar restores hidden buttons).
    SetLength(kids, ControlCount);
    n := 0;
    for i := 0 to ControlCount - 1 do
    begin
      ctl := Controls[i];
      if IsInternalChild(ctl) then Continue;   // the chevron is placed by us, not laid out
      kids[n] := ctl;
      Inc(n);
    end;
    SetLength(kids, n);

    if n = 0 then
    begin
      ClearOverflow;
      if FMoreBtn <> nil then FMoreBtn.Visible := False;
      Exit;
    end;

    // Gather widths + apply ghost/flat. DON'T force Visible:=True here — a hidden overflow
    // button's Width is still valid to measure, and toggling Visible every layout pass (shown
    // here, hidden below) invalidates the preferred size each time and never converges (LCL then
    // aborts with an InvalidatePreferredSize loop). The placement loop below sets each button's
    // FINAL Visible state, which is a no-op once it matches — so the layout settles.
    SetLength(widths, n);
    for i := 0 to n - 1 do
    begin
      { A tbsSeparator / tbsDivider tool button is a SPACE HOLDER: it resolves the
        'TyToolSeparator' key, so the button-family 'ghost' variant would ask the theme for a
        rule no skin defines AND leave a StyleClass on a control the host never styled. The
        base's ApplyToButton skips them for the same reason; this override has its own copy of
        the flat rule and so needs its own copy of the exception. }
      if (kids[i] is TTyButton)
         and not ((kids[i] is TTyToolButton)
                  and (TTyToolButton(kids[i]).Style in [tbsSeparator, tbsDivider])) then
      begin
        { Only manage a class the bar itself put there -- the same rule TTyToolBar's
          ApplyToButton follows. Assigning unconditionally (which is what this did) wiped
          a caller's StyleClass := 'primary' on every relayout, and a relayout runs on any
          metric change, so the styling vanished at an unpredictable moment. The base was
          fixed for this and the Ex subclass, which overrides AlignControls and never calls
          ApplyToButton, kept the old line. }
        if Flat then
        begin
          if TTyButton(kids[i]).StyleClass = '' then
            TTyButton(kids[i]).StyleClass := 'ghost';
        end
        else
          if TTyButton(kids[i]).StyleClass = 'ghost' then
            TTyButton(kids[i]).StyleClass := '';
      end;
      { The base bar's ButtonWidth floor, through the base's own arbitration — the overflow
        fit must be decided over the widths the buttons will actually be laid out at, or a
        floored button would be judged to fit by its narrower natural width. With ButtonWidth
        unset this is exactly kids[i].Width. (For a button this pass then HIDES, the recorded
        lend self-heals — see EffectiveToolWidth.) }
      widths[i] := EffectiveToolWidth(kids[i]);
    end;

    chevW := ChevronWidthPx;
    visCount := TyToolbarOverflowCount(widths, ClientWidth - Indent, chevW);
    if visCount > n then visCount := n;

    // Place the lead (fitting) buttons; hide + record the overflow set.
    ClearOverflow;
    { Indent is the LEADING gap, ContentPadY the vertical one -- the base stopped conflating
      the two and this override has to stop too, or a bar with a non-default Indent would sit
      its tools at one height here and another there. }
    padY := ContentPadY;

    { ROW HEIGHT — ButtonHeight is what the bar ASKS for; a child may refuse to be that short.
      A control whose caption decides its size publishes Constraints.MinHeight and SetBounds
      CLAMPS UP to it, silently. The base bar takes the tallest floor in the row first and lays
      out against that; this override kept the old, pre-fix line (SetBounds(.., ButtonHeight))
      and so re-opened the very defect the base closed -- a clamped-taller button overflowed its
      slot downward and left the row ragged. Same bug shape as the StyleClass one above: the
      base was fixed, the override that duplicates its layout was not. }
    rowH := ButtonHeight;
    for i := 0 to n - 1 do
      if kids[i].Constraints.MinHeight > rowH then rowH := kids[i].Constraints.MinHeight;

    { ROW TOP — keep the row OUT of the strip RenderTo strokes the bottom hairline into.
      A tool button is a windowed child: it paints after the bar and erases its whole rect to
      the surface colour, so a row reaching into that strip WIPES the line rather than drawing
      over it. (The containers demo showed exactly this: the hairline survived only in the gaps
      between buttons.) Pull the row up rather than squash it -- the child's own MinHeight would
      defeat a squash anyway, since SetBounds clamps back up. When the row already fits, padY is
      unchanged and no existing bar moves a pixel. }
    bottomBorder := BottomBorderPx(Font.PixelsPerInch);
    rowTop := padY;
    if rowTop + rowH > ClientHeight - bottomBorder then
      rowTop := ClientHeight - bottomBorder - rowH;
    if rowTop < 0 then rowTop := 0;

    x := Indent;
    for i := 0 to n - 1 do
    begin
      kids[i].Align := alNone;
      if i < visCount then
      begin
        // The FLOORED width the fit was decided over, not kids[i].Width — same rule as the
        // base bar's SetBounds, and the two are equal until ButtonWidth is set.
        kids[i].SetBounds(x, rowTop, widths[i], rowH);
        kids[i].Visible := True;
        Inc(x, widths[i] + ButtonSpacing);
      end
      else
      begin
        kids[i].Visible := False;
        SetLength(FOverflow, Length(FOverflow) + 1);
        FOverflow[High(FOverflow)] := kids[i];
      end;
    end;

    if visCount < n then
    begin
      EnsureMoreButton;
      { The chevron shares the row's box, not its own -- it sat at (padY, ButtonHeight) while
        the tools beside it could be taller, so it drifted off the row's centre line the moment
        a caption forced the row up. }
      FMoreBtn.SetBounds(ClientWidth - chevW - Indent, rowTop, chevW, rowH);
      FMoreBtn.Visible := True;
      FMoreBtn.BringToFront;
    end
    else if FMoreBtn <> nil then
      FMoreBtn.Visible := False;
  finally
    FInExLayout := False;
  end;
end;

procedure TTyToolBarEx.MoreClick(Sender: TObject);
var
  i, x, y, w, maxW, itemH, pad, gap: Integer;
  tl: TPoint;
begin
  if Length(FOverflow) = 0 then Exit;
  // Freeze the fit-relayout FIRST: every reparent below yanks a button out of the bar, which
  // fires AlignControls — without this it would ClearOverflow + rebuild FOverflow mid-loop, so
  // most buttons never made it into the flyout (only the last one showed) and stale pointers
  // later AV'd. Snapshot the set into FPopupItems so the loop + restore never read a mutating field.
  FPopupOpen := True;
  SetLength(FPopupItems, Length(FOverflow));
  for i := 0 to High(FOverflow) do FPopupItems[i] := FOverflow[i];

  if FPopup = nil then
  begin
    FPopup := TTyPopupSurface.CreateNew(Self);
    FPopup.StyleKey := 'TyToolBar';          // reuse the bar's themed surface/border
    FPopup.OnPopupClose := @PopupClosed;
  end;

  pad := 4;
  gap := ButtonSpacing;
  itemH := ButtonHeight;

  // Stack the overflow buttons vertically in the popup; keep their own OnClick intact.
  maxW := 0;
  for i := 0 to High(FPopupItems) do
    if (FPopupItems[i] <> nil) and (FPopupItems[i].Width > maxW) then maxW := FPopupItems[i].Width;
  if maxW <= 0 then maxW := 80;

  x := pad;
  y := pad;
  SetLength(FSavedClicks, Length(FPopupItems));
  for i := 0 to High(FPopupItems) do
  begin
    if FPopupItems[i] = nil then Continue;
    FPopupItems[i].Parent := FPopup;          // move into the flyout (live control keeps working)
    FPopupItems[i].Align := alNone;
    FPopupItems[i].SetBounds(x, y, maxW, itemH);
    FPopupItems[i].Visible := True;
    // Wrap the button's OnClick so picking an item runs its own handler THEN dismisses the flyout
    // (menu semantics). The original is stashed + restored on close.
    if FPopupItems[i] is TTyButton then
    begin
      FSavedClicks[i] := TTyButton(FPopupItems[i]).OnClick;
      TTyButton(FPopupItems[i]).OnClick := @PopupItemClick;
    end;
    Inc(y, itemH + gap);
  end;

  w := maxW + pad * 2;
  tl := FMoreBtn.ClientToScreen(Point(0, FMoreBtn.Height));
  FPopup.ShowAt(Rect(tl.x, tl.y, tl.x + w, tl.y + y + pad - gap));
end;

procedure TTyToolBarEx.PopupItemClick(Sender: TObject);
var
  i: Integer;
  orig: TNotifyEvent;
begin
  orig := nil;
  for i := 0 to High(FPopupItems) do
    if FPopupItems[i] = Sender then
    begin
      if i <= High(FSavedClicks) then orig := FSavedClicks[i];
      Break;
    end;
  if Assigned(orig) then orig(Sender);   // run the app's command first
  // Defer the dismiss to the next message-loop turn: closing now would re-parent + hide THIS button
  // while it is still mid-click (inside its own OnClick), which is fragile. QueueAsyncCall runs
  // after the click fully unwinds.
  Application.QueueAsyncCall(@DeferredClosePopup, 0);
end;

procedure TTyToolBarEx.DeferredClosePopup(Data: PtrInt);
begin
  if (FPopup <> nil) and FPopup.Visible then FPopup.ClosePopup;
end;

procedure TTyToolBarEx.PopupClosed(Sender: TObject);
var
  i: Integer;
begin
  FPopupOpen := False;
  if csDestroying in ComponentState then Exit;
  // Restore EVERY adopted button to the bar from the authoritative snapshot (NOT FOverflow, which
  // a relayout may have rebuilt to a different subset). They stay hidden — still overflowing —
  // until the next relayout decides afresh which ones fit. Also restore each button's own OnClick
  // (we wrapped it to auto-dismiss while adopted).
  for i := 0 to High(FPopupItems) do
    if FPopupItems[i] <> nil then
    begin
      if (FPopupItems[i] is TTyButton) and (i <= High(FSavedClicks)) then
        TTyButton(FPopupItems[i]).OnClick := FSavedClicks[i];
      FPopupItems[i].Parent := Self;
      FPopupItems[i].Visible := False;
    end;
  SetLength(FPopupItems, 0);
  SetLength(FSavedClicks, 0);
  Realign;    // recompute the fit now the popup is gone
end;

procedure TTyToolBarEx.Notification(AComponent: TComponent; Operation: TOperation);
var
  i, j: Integer;
begin
  inherited Notification(AComponent, Operation);
  if Operation = opRemove then
  begin
    if AComponent = FMoreBtn then FMoreBtn := nil;
    // Drop a freed child from BOTH the overflow set and the open-flyout snapshot, so neither
    // restore loop can dereference a dangling pointer.
    for i := High(FOverflow) downto 0 do
      if FOverflow[i] = AComponent then
      begin
        for j := i to High(FOverflow) - 1 do FOverflow[j] := FOverflow[j + 1];
        SetLength(FOverflow, Length(FOverflow) - 1);
      end;
    for i := High(FPopupItems) downto 0 do
      if FPopupItems[i] = AComponent then
      begin
        for j := i to High(FPopupItems) - 1 do FPopupItems[j] := FPopupItems[j + 1];
        SetLength(FPopupItems, Length(FPopupItems) - 1);
      end;
  end;
end;

function TTyToolBarEx.OverflowCount: Integer;
begin
  Result := Length(FOverflow);
end;

function TTyToolBarEx.OverflowVisible: Boolean;
begin
  Result := (FMoreBtn <> nil) and FMoreBtn.Visible;
end;

end.
