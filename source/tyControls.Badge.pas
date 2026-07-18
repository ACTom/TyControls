unit tyControls.Badge;
{$mode objfpc}{$H+}
{ TTyBadge — a standalone count / dot marker that ATTACHES to any control.

  The pill TTyButton draws for its built-in ShowBadge/BadgeValue, lifted out into a
  control of its own so ANY control can carry one: point Target at a control and the
  badge glues itself to that control's corner (Position) and follows it as it moves
  and resizes; leave Target nil and it is an ordinary standalone marker the user
  places. Value counts (> 99 renders '99+', TTyButton's rule), ShowZero decides
  whether a 0 shows at all, and Dot swaps the number for a plain dot.

  The two badges COEXIST — TTyButton keeps its own, untouched. This unit reuses that
  badge's corner enum and reproduces its geometry token for token (see TyBadgeSize /
  TyBadgeCornerPos and the notes in RenderTo), so a TTyBadge attached to a button
  lands on the same pixels the button's own badge would have used.

  Styled by the 'TyBadge' typeKey — the very key TTyButton.DrawBadge resolves, so both
  follow one theme rule and cannot drift apart. }
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.StrConsts,
  tyControls.Button;   // TTyBadgePosition — the SAME corner enum the built-in badge uses

type
  { Re-exported so `uses tyControls.Badge` is enough to declare one. Deliberately an
    ALIAS of TTyButton's type rather than a copy: the two badges must mean the same
    thing by bpTopLeft..bpBottomRight, and an alias cannot drift (nor collide, the way
    a second same-named enum in one package would). The VALUES still live in
    tyControls.Button — a unit naming bpTopRight in code also uses that unit. }
  TTyBadgePosition = tyControls.Button.TTyBadgePosition;

{ The badge metrics (TyBadgeInset / TyBadgeMinSize / TyBadgeDotSize) and their metric
  tokens live in tyControls.Types, which both badges can see — this unit uses
  tyControls.Button, so it could not lend IT a constant back. They are re-exported here
  so `uses tyControls.Badge` still reaches them.
  All three are theme-tunable (--badge-inset / --badge-min-size / --badge-dot-size) and
  BOTH badges resolve them the same way, so a skin retunes the pair together and they
  cannot drift apart — the very risk that kept the first two hard-coded. }
const
  TyBadgeInset   = tyControls.Types.TyBadgeInset;
  TyBadgeMinSize = tyControls.Types.TyBadgeMinSize;
  TyBadgeDotSize = tyControls.Types.TyBadgeDotSize;

{ --- Pure rules / geometry (headless-testable; no control, no handle) ---------- }

{ The text the badge draws for AValue. MIRRORS TTyButton's rule: anything past 99
  collapses to '99+', everything else is its plain decimal (negatives included — the
  built-in badge does not clamp either). A dot carries no number, hence ''. }
function TyBadgeText(AValue: Integer; ADot: Boolean): string;

{ Whether the badge shows anything at all. 0 is 'nothing to report', so it disappears
  unless ShowZero asked for it; any other value shows. Dot mode obeys the same rule —
  a dot is the count's silhouette, not a second switch. (TTyButton's ShowBadge master
  switch has no counterpart here: a standalone control has its own Visible.) }
function TyBadgeVisible(AValue: Integer; AShowZero: Boolean): Boolean;

{ The badge's natural size in DEVICE px, from already-measured text metrics:
    ATextWidth   — width of the display text (0 for a dot);
    AGlyphHeight — height of the reference glyph '0' (a stable line height, so '1' and
                   '99+' get the same pill height);
    APadX/APadY  — the theme's horizontal/vertical padding;
    AMinSize     — floor for the height when the measure degenerates to nothing;
    ADot/ADotSize— dot mode and its (themed) diameter.
  A dot is a plain ADotSize square (drawn round). A number's pill is text+padding, at
  least AMinSize tall, and never narrower than it is tall — a single glyph lands in a
  near-circle. This is TTyButton.DrawBadge's sizing, in one testable place. }
function TyBadgeSize(ATextWidth, AGlyphHeight, APadX, APadY, AMinSize: Integer;
  ADot: Boolean; ADotSize: Integer): TSize;

{ Top-left corner of an AW x AH badge placed inside AHost at APosition, inset by
  AInset on both axes (all device px; the result is in AHost's own space). Mirrors
  TTyButton.DrawBadge's corner block, including its defensive else-branch. }
function TyBadgeCornerPos(const AHost: TRect; AW, AH, AInset: Integer;
  APosition: TTyBadgePosition): TPoint;

type
  TTyBadge = class(TTyGraphicControl)
  private
    FTarget: TControl;
    FTargetHooked: Boolean;   // our bounds-follow handler is in FTarget's handler list
    FValue: Integer;
    FShowZero: Boolean;
    FDot: Boolean;
    FPosition: TTyBadgePosition;
    FUpdatingBounds: Boolean; // breaks the SetBounds -> Invalidate -> re-measure loop
    FReady: Boolean;          // construction finished: measuring/gluing is safe
    procedure SetTarget(AValue: TControl);
    procedure SetValue(AValue: Integer);
    procedure SetShowZero(AValue: Boolean);
    procedure SetDot(AValue: Boolean);
    procedure SetPosition(AValue: TTyBadgePosition);
    { TTyGraphicControl has no ResolveFontSize helper (that lives on TTyCustomControl);
      mirror TTyLabel/TTyDivider and resolve it locally. }
    function ResolveFontSize(const AStyle: TTyStyleSet): Integer;
    { Dot diameter in LOGICAL px: the --badge-dot-size theme metric, TyBadgeDotSize
      when the theme leaves it unset. }
    function DotSizeLogical: Integer;
    { Corner inset / degenerate-measure floor in LOGICAL px, from --badge-inset and
      --badge-min-size (TyBadgeInset / TyBadgeMinSize when the theme leaves them unset). }
    function InsetLogical: Integer;
    function MinSizeLogical: Integer;
    procedure HookTarget;
    procedure UnhookTarget;
    procedure TargetBoundsChanged(Sender: TObject);
    { An ATTACHED badge is decoration painted ON its target and must never swallow the
      target's clicks: answering 0 makes LCL's ControlAtPos skip it while routing a
      mouse message, so the message reaches the control underneath. A STANDALONE badge
      stays a normal control (its OnClick works). }
    procedure CMHitTest(var Message: TCMHitTest); message CM_HITTEST;
  protected
    function GetStyleTypeKey: string; override;   // 'TyBadge' (shared with TTyButton's badge)
    { The natural pill size in DEVICE px for APPI. }
    function MeasureBadge(APPI: Integer): TSize;
    { The rect Position anchors the pill to, in the badge's OWN coordinate space, and
      whether there is one at all (False = standalone: the user places the badge). }
    function AnchorHost(out AHost: TRect): Boolean;
    { Re-measure and re-place within the CURRENT parent. Never reparents — it runs from
      Invalidate, which can fire at awkward moments. }
    procedure ApplyNaturalSize;
    { Establish/refresh the whole attachment: reparent onto the target, then size+place. }
    procedure UpdateAttachment;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure Loaded; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { The badge's geometry is ENTIRELY theme-derived (font-size, padding,
      --badge-dot-size), so a theme switch — which reaches every control as a bare
      Invalidate from the controller — has to RESIZE it, not merely repaint it. That is
      why this is more than a repaint hook: TTyGraphicControl.SetController is private,
      so a graphic control has no theme-change seam of its own to listen on. }
    procedure Invalidate; override;
    { The text this badge currently draws ('' in dot mode). }
    function DisplayText: string;
    { Whether it currently draws anything (the Value / ShowZero rule). }
    function IsShowing: Boolean;
  published
    { The control this badge marks. Setting it MOVES the badge onto that control: a
      windowed target becomes the badge's Parent (the badge then paints on the target's
      own canvas, inside its client rect, exactly where TTyButton puts its built-in
      badge); a windowless target cannot be a parent, so the badge joins it as a sibling
      and anchors to its bounds. nil = standalone: an ordinary control the user places.
      The badge follows the target's moves and resizes, and detaches by itself if the
      target is freed. }
    property Target: TControl read FTarget write SetTarget;
    { The count. > 99 renders '99+' (TTyButton's rule). 0 hides the badge unless ShowZero. }
    property Value: Integer read FValue write SetValue default 0;
    { Show a 0 count instead of hiding the badge. }
    property ShowZero: Boolean read FShowZero write SetShowZero default False;
    { Draw a plain dot (--badge-dot-size across) instead of the number: 'something is
      here' without a count. Value still decides whether it shows (with ShowZero). }
    property Dot: Boolean read FDot write SetDot default False;
    { Which corner of the target the badge sits in, inset like TTyButton's badge.
      Same default as TTyButton.BadgePosition. Inert while standalone (no host corner). }
    property Position: TTyBadgePosition read FPosition write SetPosition default bpBottomRight;
    { The badge is always its natural (measured) size, so there is no Align/AutoSize to
      publish; Anchors is for standalone use — an attached badge is placed by Target. }
    property Anchors;
    property StyleClass;
    property StyleOverride;
    property Controller;
  end;

implementation

{ --- pure rules / geometry ---------------------------------------------------- }

function TyBadgeText(AValue: Integer; ADot: Boolean): string;
begin
  if ADot then Exit('');                    // a dot carries no number
  if AValue > 99 then Result := rsBadgeOverflow else Result := IntToStr(AValue);
end;

function TyBadgeVisible(AValue: Integer; AShowZero: Boolean): Boolean;
begin
  Result := (AValue <> 0) or AShowZero;
end;

function TyBadgeSize(ATextWidth, AGlyphHeight, APadX, APadY, AMinSize: Integer;
  ADot: Boolean; ADotSize: Integer): TSize;
begin
  if ADot then
  begin
    // A dot is one themed diameter — no text, no padding, no pill.
    if ADotSize < 1 then ADotSize := 1;
    Exit(Size(ADotSize, ADotSize));
  end;
  if ATextWidth < 0 then ATextWidth := 0;
  if APadX < 0 then APadX := 0;
  if APadY < 0 then APadY := 0;
  Result.cy := AGlyphHeight + 2 * APadY;
  if Result.cy < AMinSize then Result.cy := AMinSize;    // degenerate-measure floor
  Result.cx := ATextWidth + 2 * APadX;
  if Result.cx < Result.cy then Result.cx := Result.cy;  // single glyph -> near-circle
end;

function TyBadgeCornerPos(const AHost: TRect; AW, AH, AInset: Integer;
  APosition: TTyBadgePosition): TPoint;
begin
  case APosition of
    bpTopLeft:     begin Result.X := AHost.Left  + AInset;      Result.Y := AHost.Top    + AInset;      end;
    bpTopRight:    begin Result.X := AHost.Right - AInset - AW; Result.Y := AHost.Top    + AInset;      end;
    bpBottomLeft:  begin Result.X := AHost.Left  + AInset;      Result.Y := AHost.Bottom - AInset - AH; end;
    bpBottomRight: begin Result.X := AHost.Right - AInset - AW; Result.Y := AHost.Bottom - AInset - AH; end;
  else
    begin Result.X := AHost.Right - AInset - AW; Result.Y := AHost.Bottom - AInset - AH; end;
  end;
end;

{ --- TTyBadge ----------------------------------------------------------------- }

constructor TTyBadge.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FValue := 0;
  FShowZero := False;
  FDot := False;
  FPosition := bpBottomRight;   // same default as TTyButton.BadgePosition
  // A drop size for the designer; ApplyNaturalSize immediately replaces it with the
  // measured pill (and does so again on every value / dot / theme change).
  Width := 20;
  Height := 16;
  FReady := True;
  ApplyNaturalSize;
end;

destructor TTyBadge.Destroy;
begin
  // Unhook while the target is still alive: it would otherwise keep a dangling method
  // pointer in its handler list and AV on its next bounds change.
  UnhookTarget;
  inherited Destroy;
end;

function TTyBadge.GetStyleTypeKey: string;
begin
  // The same key TTyButton.DrawBadge resolves: one theme rule drives both badges.
  Result := 'TyBadge';
end;

function TTyBadge.ResolveFontSize(const AStyle: TTyStyleSet): Integer;
begin
  Result := TyResolveFontSize(AStyle, ParentFont, Font.Size, ActiveController);
end;

function TTyBadge.DotSizeLogical: Integer;
begin
  // v3/C metric token: a skin can retune the dot without a width/height vocabulary.
  Result := ActiveController.Metric(TyBadgeDotSizeVar, TyBadgeDotSize);
  if Result < 1 then Result := 1;
end;

function TTyBadge.InsetLogical: Integer;
begin
  // Resolved exactly as TTyButton.DrawBadge resolves it, so an attached badge keeps
  // landing on the pixels the button's built-in badge would have used.
  Result := ActiveController.Metric(TyBadgeInsetVar, TyBadgeInset);
  if Result < 0 then Result := 0;
end;

function TTyBadge.MinSizeLogical: Integer;
begin
  Result := ActiveController.Metric(TyBadgeMinSizeVar, TyBadgeMinSize);
  if Result < 1 then Result := 1;
end;

function TTyBadge.DisplayText: string;
begin
  Result := TyBadgeText(FValue, FDot);
end;

function TTyBadge.IsShowing: Boolean;
begin
  Result := TyBadgeVisible(FValue, FShowZero);
end;

{ --- property setters --------------------------------------------------------- }

procedure TTyBadge.SetValue(AValue: Integer);
begin
  if FValue = AValue then Exit;
  FValue := AValue;
  Invalidate;   // re-measures (the text width changed) and repaints
end;

procedure TTyBadge.SetShowZero(AValue: Boolean);
begin
  if FShowZero = AValue then Exit;
  FShowZero := AValue;
  Invalidate;
end;

procedure TTyBadge.SetDot(AValue: Boolean);
begin
  if FDot = AValue then Exit;
  FDot := AValue;
  Invalidate;   // dot <-> pill is a size change, not just a repaint
end;

procedure TTyBadge.SetPosition(AValue: TTyBadgePosition);
begin
  if FPosition = AValue then Exit;
  FPosition := AValue;
  UpdateAttachment;   // a different corner of the same host
end;

procedure TTyBadge.SetTarget(AValue: TControl);
begin
  if FTarget = AValue then Exit;
  if AValue = Self then Exit;   // a badge cannot mark itself
  UnhookTarget;
  if FTarget <> nil then FTarget.RemoveFreeNotification(Self);
  FTarget := AValue;
  if FTarget <> nil then FTarget.FreeNotification(Self);
  HookTarget;
  UpdateAttachment;
end;

{ --- target following --------------------------------------------------------- }

procedure TTyBadge.HookTarget;
begin
  if (FTarget = nil) or FTargetHooked then Exit;
  // Observe the target's bounds WITHOUT stealing its OnChangeBounds: LCL keeps a handler
  // LIST per control, so the user's own handler still runs untouched.
  FTarget.AddHandlerOnChangeBounds(@TargetBoundsChanged);
  FTargetHooked := True;
end;

procedure TTyBadge.UnhookTarget;
begin
  if (FTarget = nil) or not FTargetHooked then Exit;
  FTarget.RemoveHandlerOnChangeBounds(@TargetBoundsChanged);
  FTargetHooked := False;
end;

procedure TTyBadge.TargetBoundsChanged(Sender: TObject);
begin
  // The target moved or resized, so its corner did too. UpdateAttachment (not just
  // ApplyNaturalSize) because this is also where a target that only got its Parent
  // after Target was assigned finally becomes attachable; once glued, the reparent
  // branch is a no-op and this is a pure re-place.
  UpdateAttachment;
end;

procedure TTyBadge.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FTarget) then
  begin
    // Drop the reference WITHOUT unhooking: the target is mid-destruction and its
    // handler list may already be gone — it takes our entry down with it. (LCL does not
    // free a dying parent's children, so a badge parented INTO the target survives,
    // simply unparented.)
    FTarget := nil;
    FTargetHooked := False;
  end;
end;

procedure TTyBadge.Loaded;
begin
  inherited Loaded;
  // Target is a component REFERENCE: the streamer fixes it up only once the whole form
  // has loaded, so the glue runs here rather than from the setter mid-stream (where the
  // .lfm's own Parent/bounds are still arriving).
  UpdateAttachment;
end;

{ --- geometry ----------------------------------------------------------------- }

function TTyBadge.AnchorHost(out AHost: TRect): Boolean;
begin
  Result := False;
  AHost := Rect(0, 0, 0, 0);
  if (FTarget = nil) or (csDestroying in FTarget.ComponentState) then Exit;
  if (FTarget is TWinControl) and (Parent = FTarget) then
  begin
    // Parented INTO a windowed target: its FULL client rect — the very rect (pre-padding)
    // TTyButton.DrawBadge insets its built-in badge into, so both land on the same pixels.
    AHost := Rect(0, 0, TWinControl(FTarget).ClientWidth, TWinControl(FTarget).ClientHeight);
    Result := True;
  end
  else if (Parent <> nil) and (FTarget.Parent = Parent) then
  begin
    // Sibling of a windowless target (a TGraphicControl cannot be a parent): anchor to
    // its bounds in the parent both share.
    AHost := FTarget.BoundsRect;
    Result := True;
  end;
end;

procedure TTyBadge.ApplyNaturalSize;
var
  sz: TSize;
  pt: TPoint;
  host: TRect;
  ppi: Integer;
begin
  if (not FReady) or FUpdatingBounds then Exit;
  if csDestroying in ComponentState then Exit;
  if csLoading in ComponentState then Exit;   // the .lfm is still arriving; Loaded re-glues
  FUpdatingBounds := True;
  try
    ppi := Font.PixelsPerInch;
    if ppi <= 0 then ppi := 96;
    sz := MeasureBadge(ppi);
    if AnchorHost(host) then
      pt := TyBadgeCornerPos(host, sz.cx, sz.cy, MulDiv(InsetLogical, ppi, 96), FPosition)
    else
      pt := Point(Left, Top);   // standalone: the user owns the position
    if (pt.X <> Left) or (pt.Y <> Top) or (sz.cx <> Width) or (sz.cy <> Height) then
      SetBounds(pt.X, pt.Y, sz.cx, sz.cy);
  finally
    FUpdatingBounds := False;
  end;
end;

procedure TTyBadge.UpdateAttachment;
begin
  if (not FReady) or (csDestroying in ComponentState) then Exit;
  if csLoading in ComponentState then Exit;
  if (FTarget <> nil) and not (csDestroying in FTarget.ComponentState) then
  begin
    { A badge has to live in the target's coordinate space or it could not sit on it at
      all. A WINDOWED target becomes the badge's PARENT: a windowless control paints onto
      its parent's canvas, which is the only way to appear ON a control that owns a handle
      (as a mere sibling it would be clipped away behind that handle). A windowless target
      cannot be a parent, so there the badge joins it as a sibling instead. }
    if FTarget is TWinControl then
    begin
      if Parent <> FTarget then Parent := TWinControl(FTarget);
    end
    else if (FTarget.Parent <> nil) and (Parent <> FTarget.Parent) then
      Parent := FTarget.Parent;
    // Sibling of a windowless target: graphic controls paint in child order, so the badge
    // must come last to sit ON the target rather than under it.
    if (Parent <> nil) and (Parent = FTarget.Parent) then
      BringToFront;
  end;
  ApplyNaturalSize;
end;

procedure TTyBadge.Invalidate;
begin
  inherited Invalidate;
  // FUpdatingBounds keeps the SetBounds this triggers from re-entering.
  ApplyNaturalSize;
end;

function TTyBadge.MeasureBadge(APPI: Integer): TSize;
{ Measures with a CANVAS-LESS painter — the tyControls.Form idiom: BeginPaint(nil, ...)
  builds only the painter's internal bitmap and EndPaint frees it WITHOUT blitting, so
  this is safe outside a paint cycle and leaks nothing. It has to be the painter and not
  a TBitmap canvas (TTyLabel's measurer): the pill is drawn with BGRA text metrics, and
  only the same measurer reproduces the size those glyphs actually render at. }
var
  P: TTyPainter;
  S: TTyStyleSet;
  fs: Integer;
  szH, szW: TSize;
begin
  S := CurrentStyle;
  P := TTyPainter.Create;
  try
    P.BeginPaint(nil, Rect(0, 0, 1, 1), APPI);   // 1x1: nothing is drawn, only measured
    fs := ResolveFontSize(S);
    // Height from a stable reference glyph ('0'), width from the actual text — exactly
    // what TTyButton.DrawBadge measures, so the two pills size identically.
    szH := P.MeasureText('0', S.FontName, fs, S.FontWeight);
    szW := P.MeasureText(DisplayText, S.FontName, fs, S.FontWeight);
    Result := TyBadgeSize(szW.cx, szH.cy, P.Scale(S.Padding.Left), P.Scale(S.Padding.Top),
      P.Scale(MinSizeLogical), FDot, P.Scale(DotSizeLogical));
    P.EndPaint;   // nil canvas -> no blit, just frees the measure bitmap
  finally
    P.Free;
  end;
end;

{ --- input -------------------------------------------------------------------- }

procedure TTyBadge.CMHitTest(var Message: TCMHitTest);
begin
  inherited;              // TControl.CMHitTest answers 1 (a normal hit)
  if FTarget <> nil then
    Message.Result := 0;  // attached: fall through to the target underneath
end;

{ --- painting ----------------------------------------------------------------- }

procedure TTyBadge.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  R: TRect;
  fs, half, themedR, rLogical: Integer;
begin
  if not IsShowing then Exit;   // the Value / ShowZero rule: draw nothing at all
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    if not (tpBackground in S.Present) then
    begin
      P.EndPaint;   // no TyBadge theme rule -> nothing to draw (as TTyButton's badge does)
      Exit;
    end;
    { A transparent overlay: deliberately NO TyFillParentBg. A graphic control paints onto
      its host's canvas, so the pixels outside the pill's rounded shape must stay untouched
      and keep showing the host's own paint (a button's gradient, its hover fade, an image
      theme's photo) — filling a backdrop first would stamp a flat patch over it. Honour an
      opacity token if the theme declares one (e.g. TyBadge:disabled). }
    if tpOpacity in S.Present then
      P.Opacity := S.Opacity;
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    // Pill by default (half-height radius), honouring a smaller themed radius if set —
    // TTyButton.DrawBadge's recipe. FillBackground takes a LOGICAL radius and Scales it,
    // so unscale the device half. A dot is the same shape at 1:1 aspect: a circle.
    half := P.Unscale((R.Bottom - R.Top) div 2);
    themedR := TyEffectiveCorners(S).TL;
    if themedR <= 0 then rLogical := half
    else rLogical := TyClampRadius(themedR, half);
    P.FillBackground(R, S.Background, TyUniformCorners(rLogical));
    if not FDot then
    begin
      fs := ResolveFontSize(S);
      // Anti-clip breathing room, as in TTyButton.DrawBadge: some widgetsets (notably
      // LCL-Qt6) render small bold glyphs a hair larger than they measure, and DrawText
      // clips to its rect, so the digits would be shaved. Inflate ONLY the text's clip
      // rect: the centred text stays on the same point and the pill is unchanged, so
      // Windows / headless render identically.
      Dec(R.Left, P.Scale(1));  Dec(R.Top, P.Scale(1));
      Inc(R.Right, P.Scale(1)); Inc(R.Bottom, P.Scale(1));
      // ASmallCrisp: supersample the digits on Linux/macOS (BGRA renders small bold text
      // soft there); Windows ignores the flag.
      P.DrawText(R, DisplayText, S.FontName, fs, S.FontWeight, S.TextColor,
        taCenter, tlCenter, False, 0, True);
    end;
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyBadge.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
