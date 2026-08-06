unit tyControls.FloatSpinEdit;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Math, Types, Controls, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.StyleModel, tyControls.Base,
  tyControls.Controller, tyControls.NumericEdit, tyControls.SpinEdit;

{ The largest CENTRED SQUARE inside a spin-button half — the box the arrow glyph is drawn in.

  It exists because the two spin controls have differently shaped button halves. TTySpinEdit
  owns its whole client rect and runs its buttons flush to the right edge, so a half is about
  18x14 at 96 DPI. This control hangs its buttons in TTyEdit's trailing zone, which is inset
  by the field padding on all four sides, so a half is about 18x10 — and TTyPainter.DrawGlyph
  insets a further 4 logical px per side by default, which would leave the arrow one pixel
  tall. Squaring the box first (and passing a 1px pad) keeps the arrow an arrow at every
  density instead of a horizontal smudge. }
function TyFloatSpinGlyphBox(const AHalf: TRect): TRect;

type
  { A DECIMAL spin edit: the counterpart of LCL's TFloatSpinEdit (spin.pp:89).

    WHY IT DESCENDS FROM TTyNumericEdit AND NOT FROM TTySpinEdit. LCL builds the family the
    other way up — TCustomSpinEdit = class(TCustomFloatSpinEdit) (spin.pp:146) — so the
    integer control is the descendant there and the same direction is not available to us:
    TTySpinEdit's three public virtual seams (GetLimitedValue / ValueToStr / StrToValue,
    spin.pp:74-76) are typed Integer and already overridden by callers, so they cannot be
    re-typed to Double without breaking them. Inverting our own hierarchy is therefore barred,
    and shadowing a `Value: Double` over the inherited published `Value: Integer` would leave
    the INTEGER engine doing the stepping — 1.5 would truncate, silently.

    TTyNumericEdit already supplies the other half of the job: a Double Value, Decimals,
    MinValue/MaxValue clamping and a separator-aware input filter, on top of TTyEdit's real
    text engine (selection, clipboard, undo, IME) that TTySpinEdit's lightweight line buffer
    does not have. All this class adds is the pair of stepper buttons, and it adds them through
    the seams TTyEdit already publishes for a trailing widget — RightReserve / PaintTrailing /
    TrailingZone — the same three TTyComboEdit and TTyURLEdit hang their buttons on.

    Theme: inherits 'TyEdit' (no new typeKey, no new .tycss). The button column's width is the
    '--field-button-width' metric — the same token the combo box, the combo edit and the
    integer spin edit read — and the arrows are the '--glyph-arrow-up' / '--glyph-arrow-down'
    overridable glyphs. }
  TTyFloatSpinEdit = class(TTyNumericEdit)
  private
    FIncrement: Double;
    FEditorEnabled: Boolean;
    function IncrementStored: Boolean;
    procedure SetIncrement(const AValue: Double);
    procedure SetEditorEnabled(const AValue: Boolean);
    { True for the keystrokes that would MUTATE the text. Used only while EditorEnabled is
      False; see the property comment for why the set is what it is. }
    function KeyWouldEditTheText(AKey: Word; AShift: TShiftState): Boolean;
  protected
    { Reserve the button column at the right of the text area, and paint the two arrows in it.
      TrailingZone (TTyEdit) reports the same rect back for hit-testing, which is what keeps
      the painted buttons and the clickable buttons one thing. }
    function RightReserve(APPI: Integer): Integer; override;
    procedure PaintTrailing(APainter: TTyPainter; const AZone: TRect;
      const AStyle: TTyStyleSet); override;
    { The last net for EditorEnabled: every insertion in TTyEdit — typing, paste and an IME
      commit — funnels through here. }
    function FilterInsert(const AText: string): string; override;
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    { Move the value by ADelta, the way the USER moves it: blocked by ReadOnly, and it marks
      the field Modified because the arrows are the user editing, exactly like typing. (The
      integer sibling's StepValue keeps the same two rules.) Every button, arrow key and wheel
      notch goes through here, so a descendant can re-point all of them at once. }
    procedure StepValue(ADelta: Double); virtual;
    { The two clickable halves, in client pixels — the same rects the paint uses, so a test can
      assert where a click has to land without reading pixels. Empty when the trailing zone is
      (a control too narrow to hold a button column). }
    function UpButtonRect(APPI: Integer): TRect;
    function DownButtonRect(APPI: Integer): TRect;
  published
    { The step, as a Double — the property that makes this control worth having (LCL:
      spin.pp:80, same default 1, same `stored` rule so a .lfm does not carry the default).

      Deliberately NOT floored at 1 the way TTySpinEdit.Increment is: a sub-1 step is the whole
      point of a decimal spinner. A step FINER than Decimals cannot show, though — the value is
      re-derived from the displayed text on every write, so with Decimals = 2 an Increment of
      0.001 rounds back to where it started and the buttons look dead. That is LCL's behaviour
      too once a handle exists (its widgetset GetValue re-parses the edit text); the fix is to
      raise Decimals, not to nudge the step. }
    property Increment: Double read FIncrement write SetIncrement stored IncrementStored;
    { LCL's other half of the ReadOnly pair (spin.pp:79, default True), kept orthogonal to it
      exactly as the integer sibling keeps it: ReadOnly locks the VALUE (typing and stepping
      both), EditorEnabled = False locks only the KEYBOARD and leaves the arrows, the wheel and
      the buttons stepping. That is how a field is forced onto a legal grid — multiples of 0.5,
      quarter hours — without turning the control inert.

      "The keyboard" means every keystroke that would change the text: a character, Backspace,
      Delete, and the Ctrl/Cmd clipboard-and-undo keys (X, V, Z, Y). Those are consumed before
      the edit sees them, so OnKeyDown does not see them either — the one place this differs
      from LCL, which blocks the effect at the widget and leaves the notification alone.

      Programmatic writes are untouched, as they are on a read-only LCL edit: Text := and
      Value := still work. One residual worth knowing: a host that calls PasteFromClipboard
      IN CODE on a locked field inserts nothing (FilterInsert refuses it) but does still lose
      any live selection, because TTyEdit deletes the selection before it consults the filter
      (Edit.pas:1719-1721). The keyboard route — Ctrl+V — is blocked whole. }
    property EditorEnabled: Boolean read FEditorEnabled write SetEditorEnabled default True;
    { Redeclared with the opposite default. LCL's float spin edit does NOT group thousands —
      its ValueToStr is a plain FloatToStrF(..., ffFixed, 20, DecimalPlaces)
      (include/spinedit.inc:237) — while TTyNumericEdit groups by default because it is a
      general money/quantity field. A control that answers to "float spin edit" has to start
      out looking like one, so the constructor turns grouping off and this declaration makes the
      OPT-IN stream: against the inherited `default True` a designer's UseThousands = False
      would equal the declared default, never reach the .lfm, and the constructor's False would
      be indistinguishable from it — the same footgun TTyEdit documents on TabStop. }
    property UseThousands default False;
  end;

implementation

function TyFloatSpinGlyphBox(const AHalf: TRect): TRect;
var
  w, h, s, dx, dy: Integer;
begin
  w := AHalf.Right - AHalf.Left;
  h := AHalf.Bottom - AHalf.Top;
  if (w <= 0) or (h <= 0) then Exit(Rect(0, 0, 0, 0));
  s := w;
  if h < s then s := h;
  dx := (w - s) div 2;
  dy := (h - s) div 2;
  Result := Rect(AHalf.Left + dx, AHalf.Top + dy, AHalf.Left + dx + s, AHalf.Top + dy + s);
end;

{ TTyFloatSpinEdit }

constructor TTyFloatSpinEdit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FIncrement := 1;          // LCL DefIncrement (spin.pp:35)
  FEditorEnabled := True;   // LCL spin.pp:79
  { Through the setter, because the field is private to TTyNumericEdit — and the setter also
    re-derives the display, so the initial text is the ungrouped form from the first paint. }
  UseThousands := False;
end;

function TTyFloatSpinEdit.IncrementStored: Boolean;
begin
  Result := not SameValue(FIncrement, Double(1));
end;

procedure TTyFloatSpinEdit.SetIncrement(const AValue: Double);
begin
  if FIncrement = AValue then Exit;
  FIncrement := AValue;
  { Nothing visual depends on the step, so there is nothing to repaint: LCL's SetIncrement
    only pushes the number at the widget (include/spinedit.inc:101-106). }
end;

procedure TTyFloatSpinEdit.SetEditorEnabled(const AValue: Boolean);
begin
  if FEditorEnabled = AValue then Exit;
  FEditorEnabled := AValue;
end;

function TTyFloatSpinEdit.KeyWouldEditTheText(AKey: Word; AShift: TShiftState): Boolean;
var
  Cmd: Boolean;
begin
  Cmd := (ssCtrl in AShift) or (ssMeta in AShift);
  Result := (AKey = VK_BACK) or (AKey = VK_DELETE)
    or (Cmd and ((AKey = VK_X) or (AKey = VK_V) or (AKey = VK_Z) or (AKey = VK_Y)));
end;

function TTyFloatSpinEdit.RightReserve(APPI: Integer): Integer;
begin
  { Read the metric LIVE, exactly as TTyComboEdit does, so the button column tracks the theme's
    density and lines up with a combo box's drop button and a spin edit's arrows. No constructor
    cache — a runtime skin change has to move it. }
  Result := MulDiv(ActiveController.Metric('--field-button-width', TyFieldButtonWidth), APPI, 96);
end;

function TTyFloatSpinEdit.UpButtonRect(APPI: Integer): TRect;
var
  Z: TRect;
begin
  Z := TrailingZone(APPI);
  if (Z.Right - Z.Left) <= 0 then Exit(Rect(0, 0, 0, 0));
  { The SAME half-split the integer spin edit uses, taken from its own geometry helper rather
    than re-derived here: two spin controls in one library must not disagree about where the
    up button stops and the down button starts. (The APPI argument only feeds that helper's
    no-context fallback width; the explicit width wins.) }
  Result := TySpinUpButtonRect(Z, APPI, Z.Right - Z.Left);
end;

function TTyFloatSpinEdit.DownButtonRect(APPI: Integer): TRect;
var
  Z: TRect;
begin
  Z := TrailingZone(APPI);
  if (Z.Right - Z.Left) <= 0 then Exit(Rect(0, 0, 0, 0));
  Result := TySpinDownButtonRect(Z, APPI, Z.Right - Z.Left);
end;

procedure TTyFloatSpinEdit.PaintTrailing(APainter: TTyPainter; const AZone: TRect;
  const AStyle: TTyStyleSet);
var
  ppi, w: Integer;
begin
  w := AZone.Right - AZone.Left;
  if w <= 0 then Exit;
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  { Split the zone THE PAINTER WAS GIVEN, not a re-computed one: TTyEdit hands PaintTrailing
    the very rect TrailingZone reports, so deriving both halves from it is what makes the
    painted arrows and the clickable halves the same two rectangles by construction. }
  TyDrawGlyph(APainter, ActiveController,
    TyFloatSpinGlyphBox(TySpinUpButtonRect(AZone, ppi, w)),
    tgArrowUp, AStyle.TextColor, 2, 1);
  TyDrawGlyph(APainter, ActiveController,
    TyFloatSpinGlyphBox(TySpinDownButtonRect(AZone, ppi, w)),
    tgArrowDown, AStyle.TextColor, 2, 1);
end;

procedure TTyFloatSpinEdit.StepValue(ADelta: Double);
begin
  { ReadOnly locks the value entirely — the arrows included. LCL agrees at the widgetset
    (win32wsspin.pp guards its UDN_DELTAPOS branch with the same flag), and so does the
    integer sibling. }
  if ReadOnly then Exit;
  Value := Value + ADelta;
  { The arrows are the user editing, exactly like typing — and the Value write above went
    through the published Text setter, whose contract is to CLEAR Modified. Restoring it here
    is what keeps an enable-Save handler correct after a click on the up button. }
  Modified := True;
end;

function TTyFloatSpinEdit.FilterInsert(const AText: string): string;
begin
  if not FEditorEnabled then Exit('');
  Result := inherited FilterInsert(AText);
end;

procedure TTyFloatSpinEdit.UTF8KeyPress(var UTF8Key: TUTF8Char);
begin
  { Rejected here rather than in FilterInsert because InjectKey deletes any selection BEFORE
    it consults the filter (Edit.pas:1858-1869): a locked editor must not be able to wipe a
    selection either. '' is this library's spelling of "key rejected". }
  if not FEditorEnabled then
  begin
    UTF8Key := '';
    Exit;
  end;
  inherited UTF8KeyPress(UTF8Key);
end;

procedure TTyFloatSpinEdit.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if not Enabled then Exit;
  { Before inherited, for the same reason as above: TTyEdit's handler would already have
    deleted / pasted / undone by the time control came back here. }
  if (not FEditorEnabled) and KeyWouldEditTheText(Key, Shift) then
  begin
    Key := 0;
    Exit;
  end;
  { inherited FIRST, and the arrows are read out of Key AFTERWARDS. The application's OnKeyDown
    is raised from inside it, so a handler that consumed the key by zeroing Key matches nothing
    below and no step happens — and a handler that REMAPS the key (Up -> Down) is obeyed, because
    what is tested is the key the handler left behind rather than a copy taken before it ran. The
    integer sibling steps BEFORE inherited and can be neither vetoed nor remapped; that is the
    weaker of the two spellings.

    An earlier version also carried an `if Key <> Was then Exit` guard here. It was dead against
    a veto — the case below already tests the post-handler value — and actively wrong against a
    remap, and the mutation run is what said so: deleting it changed no test result. }
  inherited KeyDown(Key, Shift);
  case Key of
    VK_UP:   begin StepValue(FIncrement);  Key := 0; end;
    VK_DOWN: begin StepValue(-FIncrement); Key := 0; end;
  end;
end;

procedure TTyFloatSpinEdit.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  ppi: Integer;
begin
  if not Enabled then Exit;
  if Button = mbLeft then
  begin
    ppi := Font.PixelsPerInch;
    if PtInRect(UpButtonRect(ppi), Point(X, Y)) then
    begin
      StepValue(FIncrement);
      { Unlike the combo edit's drop button and the URL edit's open button — which hand the
        user off to a popup or a browser — a spin button leaves the user IN the field, where
        the arrow keys continue the same gesture. So this one takes focus, the way the integer
        sibling's buttons do. }
      try
        if CanFocus then SetFocus;
      except
        // headless / not yet parented: focus is not available, and not needed
      end;
      Exit;   // consumed by the button: no caret move, no selection drag
    end;
    if PtInRect(DownButtonRect(ppi), Point(X, Y)) then
    begin
      StepValue(-FIncrement);
      try
        if CanFocus then SetFocus;
      except
      end;
      Exit;
    end;
  end;
  inherited MouseDown(Button, Shift, X, Y);
end;

function TTyFloatSpinEdit.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
begin
  if not Enabled then Exit(False);
  // The application's OnMouseWheel runs first; if it consumed the notch, stop.
  if inherited DoMouseWheel(Shift, WheelDelta, MousePos) then Exit(True);
  { Read-only: report the notch UNHANDLED so an enclosing scroll box still gets it. Returning
    True here would swallow the wheel over a field that cannot use it. }
  if ReadOnly then Exit(False);
  if WheelDelta > 0 then
    StepValue(FIncrement)
  else
    StepValue(-FIncrement);
  Result := True;
end;

end.
