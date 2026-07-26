unit test.button;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, TypInfo, fpcunit, testregistry, Forms, Controls, Graphics, LCLType,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Base, tyControls.Button, tyControls.Types, tyControls.Controller, tyControls.ToolBar;
type
  // Expose protected RenderTo for testing
  TTyButtonAccess = class(TTyButton)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure DoKeyDown(var Key: Word; Shift: TShiftState);
    // Drive the CM_DIALOGKEY handler headlessly: build a TCMDialogKey carrying
    // ACharCode and dispatch it, exercising the same routing a real form would.
    procedure DispatchDialogKey(ACharCode: Word);
    // Invoke the protected Loaded override to exercise the streamed-before-Parent
    // re-registration path without a full LFM load.
    procedure DoLoaded;
    // Expose protected CurrentStates for the selected-state test.
    function States: TTyStateSet;
    // Drive the hover bg-fade animator deterministically (no wall clock) so a
    // mid-frame (0 < Eased < 1) can be rendered.
    procedure ArmBg(ATarget: Single);
    function AdvanceAnim(AMs: Integer): Boolean;
    // Expose the protected badge display decision.
    function CallResolveBadge(out AText: string): Boolean;
    // Expose the protected preferred-size calculation (what AutoSize resizes to).
    procedure CallPreferred(out AW, AH: Integer);
  end;

  TButtonTest = class(TTestCase)
  private
    FClicked: Integer;
    FVetoForm: TCustomForm;
    procedure HandleClick(Sender: TObject);
    // OnClick handler that vetoes the modal close by clearing the form's
    // ModalResult — used to prove ModalResult is set BEFORE OnClick.
    procedure HandleClickVeto(Sender: TObject);
    // OnBadgeDisplay handler that hides the badge when value < 3.
    procedure HideUnderThree(Sender: TObject; AValue: Integer; var AText: string; var AVisible: Boolean);
  published
    procedure TestTypeKey;
    procedure TestDefaultSize;
    procedure TestOnClickFires;
    procedure TestPaintSmoke;
    procedure TestSpaceKeyFiresClick;
    procedure TestDisabledKeyNotConsumedNoClick;
    procedure TestAnimationsEnabledIsPublished;
    procedure TestModalResultSetOnClick;
    procedure TestModalResultVetoableByOnClick;
    procedure TestDefaultRespondsToEnter;
    procedure TestCancelRespondsToEscape;
    procedure TestDefaultReregisteredOnLoaded;
    procedure TestDownDrivesSelectedState;
    procedure TestHoverBlendUsesRestingState;
    procedure TestBadgeDisplayRules;
    procedure TestBadgeRendersAtCorner;
    procedure TestAutoSizeFitsTheCaption;
    procedure TestAutoSizeRefitsWhenTheCaptionGrows;
    procedure TestAutoSizeSurvivesAHeightPinningParent;
  end;
implementation

procedure TTyButtonAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TTyButtonAccess.DoKeyDown(var Key: Word; Shift: TShiftState);
begin
  KeyDown(Key, Shift);
end;

procedure TTyButtonAccess.DispatchDialogKey(ACharCode: Word);
var
  Msg: TCMDialogKey;
begin
  FillChar(Msg, SizeOf(Msg), 0);
  Msg.Msg := CM_DIALOGKEY;
  Msg.CharCode := ACharCode;
  Dispatch(Msg);
end;

procedure TTyButtonAccess.DoLoaded;
begin
  Loaded;
end;

function TTyButtonAccess.States: TTyStateSet;
begin
  Result := CurrentStates;
end;

procedure TTyButtonAccess.ArmBg(ATarget: Single);
begin
  ArmBgAnim(ATarget);
end;

function TTyButtonAccess.AdvanceAnim(AMs: Integer): Boolean;
begin
  Result := AdvanceAnimation(AMs);
end;

function TTyButtonAccess.CallResolveBadge(out AText: string): Boolean;
begin
  Result := ResolveBadgeDisplay(AText);
end;

procedure TTyButtonAccess.CallPreferred(out AW, AH: Integer);
begin
  AW := 0; AH := 0;
  CalculatePreferredSize(AW, AH, True);
end;

procedure TButtonTest.HandleClick(Sender: TObject);
begin
  Inc(FClicked);
end;

procedure TButtonTest.HandleClickVeto(Sender: TObject);
begin
  if FVetoForm <> nil then
    FVetoForm.ModalResult := mrNone;
end;

procedure TButtonTest.HideUnderThree(Sender: TObject; AValue: Integer;
  var AText: string; var AVisible: Boolean);
begin
  if AValue < 3 then AVisible := False;   // user policy: hide when < 3
end;

procedure TButtonTest.TestTypeKey;
var
  B: TTyButton;
begin
  B := TTyButton.Create(nil);
  try
    AssertEquals('TyButton', (B as ITyStyleable).GetStyleTypeKey);
  finally
    B.Free;
  end;
end;

procedure TButtonTest.TestOnClickFires;
var
  F: TCustomForm;
  B: TTyButton;
begin
  FClicked := 0;
  F := TCustomForm.CreateNew(nil);
  try
    B := TTyButton.Create(F);
    B.Parent := F;
    B.OnClick := @HandleClick;
    B.Click;
    AssertEquals(1, FClicked);
  finally
    F.Free;
  end;
end;

procedure TButtonTest.TestPaintSmoke;
var
  F: TCustomForm;
  B: TTyButtonAccess;
  Bmp: TBitmap;
begin
  F := TCustomForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    B := TTyButtonAccess.Create(F);
    B.Parent := F;
    B.Caption := 'OK';
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(80, 28);
    // This actually executes paint code — if RenderTo raises, test fails
    B.RenderTo(Bmp.Canvas, Rect(0, 0, 80, 28), 96);
    AssertTrue('button RenderTo executed without exception', True);
  finally
    Bmp.Free;
    F.Free;
  end;
end;

procedure TButtonTest.TestSpaceKeyFiresClick;
var F: TCustomForm; B: TTyButtonAccess; K: Word;
begin
  FClicked := 0;
  F := TCustomForm.CreateNew(nil);
  try
    B := TTyButtonAccess.Create(F); B.Parent := F; B.OnClick := @HandleClick;
    K := VK_SPACE; B.DoKeyDown(K, []);
    AssertEquals('space fired click', 1, FClicked);
    AssertEquals('space consumed', 0, K);
    K := VK_RETURN; B.DoKeyDown(K, []);
    AssertEquals('enter fired click', 2, FClicked);
  finally F.Free; end;
end;

procedure TButtonTest.TestDisabledKeyNotConsumedNoClick;
var F: TCustomForm; B: TTyButtonAccess; K: Word;
begin
  FClicked := 0;
  F := TCustomForm.CreateNew(nil);
  try
    B := TTyButtonAccess.Create(F); B.Parent := F; B.OnClick := @HandleClick;
    B.Enabled := False;
    K := VK_SPACE; B.DoKeyDown(K, []);
    AssertEquals('disabled: no click', 0, FClicked);
    AssertEquals('disabled: key NOT consumed', VK_SPACE, K);
  finally F.Free; end;
end;

procedure TButtonTest.TestAnimationsEnabledIsPublished;
var
  B: TTyButton;
begin
  B := TTyButton.Create(nil);
  try
    AssertTrue('AnimationsEnabled is a published property (designer/streaming access)',
      IsPublishedProp(B, 'AnimationsEnabled'));
  finally
    B.Free;
  end;
end;

procedure TButtonTest.TestModalResultSetOnClick;
var
  F: TCustomForm;
  B: TTyButton;
begin
  F := TCustomForm.CreateNew(nil);
  try
    B := TTyButton.Create(F);
    B.Parent := F;
    B.ModalResult := mrOk;
    AssertEquals('form ModalResult starts unset', mrNone, F.ModalResult);
    B.Click;
    AssertEquals('click sets host form ModalResult', mrOk, F.ModalResult);
  finally
    F.Free;
  end;
end;

procedure TButtonTest.TestModalResultVetoableByOnClick;
var
  F: TCustomForm;
  B: TTyButton;
begin
  // ModalResult must be applied to the form BEFORE OnClick fires, so an OnClick
  // handler can veto the close by resetting Form.ModalResult to mrNone. This
  // discriminates the correct order: with the old (set-after-OnClick) order the
  // handler's mrNone would be clobbered back to mrOk and this would fail.
  F := TCustomForm.CreateNew(nil);
  try
    FVetoForm := F;
    B := TTyButton.Create(F);
    B.Parent := F;
    B.ModalResult := mrOk;
    B.OnClick := @HandleClickVeto;  // resets F.ModalResult := mrNone
    B.Click;
    AssertEquals('OnClick veto of ModalResult survives', mrNone, F.ModalResult);
  finally
    FVetoForm := nil;
    F.Free;
  end;
end;

procedure TButtonTest.TestDefaultRespondsToEnter;
var
  B: TTyButtonAccess;
begin
  // Default=True => the dialog-key seam wants VK_RETURN (Enter triggers Click),
  // and does NOT want VK_ESCAPE.
  FClicked := 0;
  B := TTyButtonAccess.Create(nil);
  try
    B.OnClick := @HandleClick;
    B.Default := True;
    AssertTrue('Default wants VK_RETURN', B.WantsDialogKey(VK_RETURN));
    AssertFalse('Default does NOT want VK_ESCAPE', B.WantsDialogKey(VK_ESCAPE));
    // The seam-driven dialog-key dispatch fires Click for the wanted key only.
    B.DispatchDialogKey(VK_ESCAPE);
    AssertEquals('Escape does not click a Default button', 0, FClicked);
    B.DispatchDialogKey(VK_RETURN);
    AssertEquals('Enter clicks a Default button', 1, FClicked);
  finally
    B.Free;
  end;
end;

procedure TButtonTest.TestCancelRespondsToEscape;
var
  B: TTyButtonAccess;
begin
  // Cancel=True => the dialog-key seam wants VK_ESCAPE (Esc triggers Click),
  // and does NOT want VK_RETURN.
  FClicked := 0;
  B := TTyButtonAccess.Create(nil);
  try
    B.OnClick := @HandleClick;
    B.Cancel := True;
    AssertTrue('Cancel wants VK_ESCAPE', B.WantsDialogKey(VK_ESCAPE));
    AssertFalse('Cancel does NOT want VK_RETURN', B.WantsDialogKey(VK_RETURN));
    B.DispatchDialogKey(VK_RETURN);
    AssertEquals('Enter does not click a Cancel button', 0, FClicked);
    B.DispatchDialogKey(VK_ESCAPE);
    AssertEquals('Escape clicks a Cancel button', 1, FClicked);
  finally
    B.Free;
  end;
end;

procedure TButtonTest.TestDefaultReregisteredOnLoaded;
var
  F: TCustomForm;
  B: TTyButtonAccess;
begin
  // Streaming order: Default is set BEFORE Parent (as an LFM loads Default while
  // the button is still parentless). The setter's GetParentForm returns nil so
  // registration is dropped; Loaded must re-apply it once Parent is known.
  F := TCustomForm.CreateNew(nil);
  try
    B := TTyButtonAccess.Create(F);
    B.Default := True;            // parentless: setter cannot register yet
    AssertTrue('precondition: not yet registered', F.DefaultControl <> B);
    B.Parent := F;                // parent now known, but Loaded not yet run
    B.DoLoaded;                   // re-applies the dropped registration
    AssertSame('Loaded re-registers DefaultControl', TControl(B), TControl(F.DefaultControl));
  finally
    F.Free;
  end;
end;

procedure TButtonTest.TestDownDrivesSelectedState;
var B: TTyButtonAccess;
begin
  B := TTyButtonAccess.Create(nil);
  try
    AssertFalse('Down default False', B.Down);
    AssertFalse('not selected initially', tysSelected in B.States);
    B.Down := True;
    AssertTrue('Down adds tysSelected', tysSelected in B.States);
    AssertFalse('selected excludes normal', tysNormal in B.States);
    // disabled takes priority: Down does not stack on top
    B.Enabled := False;
    AssertFalse('disabled drops selected', tysSelected in B.States);
    AssertTrue('disabled present', tysDisabled in B.States);
    AssertTrue('Down is published', IsPublishedProp(B, 'Down'));
  finally B.Free; end;
end;

procedure TButtonTest.TestHoverBlendUsesRestingState;
var
  B: TTyButtonAccess;
  Ctl: TTyStyleController;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
begin
  // Selected ghost button, mid-frame of a hover fade-in: the resting end should be
  // ghost:selected (opaque surface-active).
  // Before the fix the blend went normal (transparent) <-> hover, so the mid-frame was
  // semi-transparent over a black background -> green channel collapsed to ~66;
  // after the fix it goes selected <-> selected+hover, both ends opaque light grey ->
  // green channel ~234. We discriminate on the green channel.
  // Use a dedicated controller (fresh = built-in light theme), isolating from a global
  // TyDefaultController that other tests may have polluted.
  Bmp := TBitmap.Create;
  Ctl := TTyStyleController.Create(nil);
  B := TTyButtonAccess.Create(nil);
  try
    B.Controller := Ctl;
    B.StyleClass := 'ghost';
    B.Down := True;
    B.Caption := '';
    B.Font.PixelsPerInch := 96;
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(80, 28);
    Bmp.Canvas.Brush.Color := clBlack;          // black background: transparency clearly collapses green
    Bmp.Canvas.FillRect(0, 0, 80, 28);
    B.ArmBg(1);                                  // drive toward the hover end
    B.AdvanceAnim(12);                           // 12/120=0.1 -> Eased=0.271, lands in the blend range
    B.RenderTo(Bmp.Canvas, Rect(0, 0, 80, 28), 96);
    Reread := TBGRABitmap.Create(Bmp);
    try
      Px := Reread.GetPixel(40, 14);
      AssertTrue('selected ghost mid-frame stays opaque light (green high)', Px.green > 150);
    finally Reread.Free; end;
  finally B.Free; Ctl.Free; Bmp.Free; end;
end;

procedure TButtonTest.TestBadgeDisplayRules;
var B: TTyButtonAccess; txt: string;
begin
  B := TTyButtonAccess.Create(nil);
  try
    AssertFalse('ShowBadge default False', B.ShowBadge);
    AssertTrue('BadgePosition default bottom-right', B.BadgePosition = bpBottomRight);
    AssertTrue('badge props published', IsPublishedProp(B, 'ShowBadge')
      and IsPublishedProp(B, 'BadgeValue') and IsPublishedProp(B, 'BadgePosition'));
    // off: not shown
    B.ShowBadge := False; B.BadgeValue := 5;
    AssertFalse('off -> not visible', B.CallResolveBadge(txt));
    // on + value 0: shows "0" by default
    B.ShowBadge := True; B.BadgeValue := 0;
    AssertTrue('on, value 0 -> visible by default', B.CallResolveBadge(txt));
    AssertEquals('value 0 text', '0', txt);
    // >99 -> 99+
    B.BadgeValue := 150;
    AssertTrue(B.CallResolveBadge(txt));
    AssertEquals('cap at 99+', '99+', txt);
    // event hides < 3
    B.OnBadgeDisplay := @HideUnderThree;
    B.BadgeValue := 2;
    AssertFalse('event hides <3', B.CallResolveBadge(txt));
    B.BadgeValue := 7;
    AssertTrue('event shows >=3', B.CallResolveBadge(txt));
    AssertEquals('7 text', '7', txt);
  finally B.Free; end;
end;

procedure TButtonTest.TestBadgeRendersAtCorner;
  // True if any pixel in the bottom-right region is accent blue (#3B82F6-ish:
  // strong blue, weak red) — robust to exact glyph metrics / badge size.
  function AccentBlueInCorner(R: TBGRABitmap): Boolean;
  var ix, iy: Integer; px: TBGRAPixel;
  begin
    Result := False;
    for iy := 22 to 39 do
      for ix := 78 to 99 do
      begin
        px := R.GetPixel(ix, iy);
        if (px.blue > 200) and (px.red < 128) then Exit(True);
      end;
  end;
var
  B: TTyButtonAccess; Ctl: TTyStyleController; Bmp: TBitmap; Reread: TBGRABitmap;
begin
  // Built-in TyBadge background = var(--accent) = #3B82F6. Accent blue should appear in
  // the bottom-right corner; once disabled it should not.
  // Dedicated controller (built-in light), isolating from the chance that other tests
  // changed the theme on the global TyDefaultController.
  Bmp := TBitmap.Create;
  Ctl := TTyStyleController.Create(nil);
  B := TTyButtonAccess.Create(nil);
  try
    B.Controller := Ctl;
    B.Caption := '';
    B.Font.PixelsPerInch := 96;
    B.ShowBadge := True;
    B.BadgeValue := 2;
    B.BadgePosition := bpBottomRight;
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(100, 40);
    Bmp.Canvas.Brush.Color := clBlack; Bmp.Canvas.FillRect(0, 0, 100, 40);
    B.RenderTo(Bmp.Canvas, Rect(0, 0, 100, 40), 96);
    Reread := TBGRABitmap.Create(Bmp);
    try
      AssertTrue('badge (accent blue) drawn in bottom-right', AccentBlueInCorner(Reread));
    finally Reread.Free; end;

    // disable the badge: the bottom-right should no longer have accent blue (a default
    // button's fill is white, high red channel, so it is excluded).
    B.ShowBadge := False;
    Bmp.Canvas.Brush.Color := clBlack; Bmp.Canvas.FillRect(0, 0, 100, 40);
    B.RenderTo(Bmp.Canvas, Rect(0, 0, 100, 40), 96);
    Reread := TBGRABitmap.Create(Bmp);
    try
      AssertFalse('no badge -> no accent blue in region', AccentBlueInCorner(Reread));
    finally Reread.Free; end;
  finally B.Free; Ctl.Free; Bmp.Free; end;
end;

procedure TButtonTest.TestDefaultSize;
var B: TTyButton;
begin
  B := TTyButton.Create(nil);
  try
    AssertEquals('default width', 88, B.Width);
    AssertEquals('default height', 30, B.Height);
  finally
    B.Free;
  end;
end;

procedure TButtonTest.TestAutoSizeFitsTheCaption;
{ A button with AutoSize hugs its caption plus the THEME's padding — the same inset RenderTo
  applies before drawing, so what AutoSize reserves is exactly what the caption gets. Without
  this a caption that outgrows the designed width is silently ellipsised. }
var
  Ctl: TTyStyleController;
  B: TTyButtonAccess;
  w, h, wLong, hLong: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    // Known padding so the arithmetic is exact rather than theme-dependent.
    Ctl.LoadThemeCss('TyButton { background: #FFFFFF; color: #000000; padding: 5px 9px; font-size: 12px; }');
    B := TTyButtonAccess.Create(nil);
    try
      B.Controller := Ctl;
      B.Font.PixelsPerInch := 96;
      AssertTrue('AutoSize is published so a .lfm / the OI can set it',
        IsPublishedProp(B, 'AutoSize'));
      AssertFalse('but it stays OFF by default — a designed button keeps its width', B.AutoSize);

      B.Caption := 'OK';
      B.CallPreferred(w, h);
      // Width = measured text + both horizontal paddings.
      AssertTrue('preferred width leaves room for the 9px paddings', w > 2 * 9);
      { Height is deliberately UNSET (0 = "no preference on this axis" in LCL): a button
        widens for its caption but its height belongs to whoever lays out the row. Proposing
        one made it fight TTyToolBar, which pins every child to its ButtonHeight, until LCL
        aborted with "TControl.ChangeBounds loop detected". }
      AssertEquals('height is left to the layout, not proposed', 0, h);

      // A longer caption must want a wider button — that is the whole point.
      B.Caption := 'A considerably longer caption';
      B.CallPreferred(wLong, hLong);
      AssertTrue(Format('a longer caption wants more width (%d -> %d)', [w, wLong]), wLong > w);
      AssertEquals('and still proposes no height', 0, hLong);
    finally
      B.Free;
    end;
  finally
    Ctl.Free;
  end;
end;

procedure TButtonTest.TestAutoSizeRefitsWhenTheCaptionGrows;
{ The reported case: a caption swapped at RUNTIME (a longer translation pushed in after the
  .lfm sized the button) must make the button want more width, not get ellipsised.
  Measured through CalculatePreferredSize rather than through Width, for the same reason
  TTyTag's tests do: LCL's AutoSizeDelayed suppresses every re-fit while the parent form has
  no handle, and the headless runner never realises one. }
var
  Ctl: TTyStyleController;
  B: TTyButtonAccess;
  narrow, wide, h1, h2: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss('TyButton { background: #FFFFFF; color: #000000; padding: 5px 9px; font-size: 12px; }');
    B := TTyButtonAccess.Create(nil);
    try
      B.Controller := Ctl;
      B.Font.PixelsPerInch := 96;
      B.AutoSize := True;
      B.Caption := 'New';
      B.CallPreferred(narrow, h1);

      // The translated caption is much longer than the one the button was sized for.
      B.Caption := 'New work order (a much longer translated caption)';
      B.CallPreferred(wide, h2);
      AssertTrue(Format('the button now wants more width (%d -> %d)', [narrow, wide]),
        wide > narrow);
      AssertEquals('and never proposes a height', 0, h2);

      // The '&' marker is drawn as an underline, not as a character: it must not be measured.
      B.Caption := 'Save';
      B.CallPreferred(narrow, h1);
      B.Caption := '&Save';
      B.CallPreferred(wide, h2);
      AssertEquals('a mnemonic marker adds no width', narrow, wide);
    finally
      B.Free;
    end;
  finally
    Ctl.Free;
  end;
end;

procedure TButtonTest.TestAutoSizeSurvivesAHeightPinningParent;
{ Regression: an AutoSize button on a TTyToolBar aborted the app at startup with
  "TControl.ChangeBounds loop detected". The bar pins every child to its ButtonHeight, the
  button proposed its own (taller) height, and the two bounced forever. Putting one on a real
  toolbar must simply settle — and settle at the BAR's height, not the button's idea of one. }
var
  F: TForm;
  Bar: TTyToolBar;
  B: TTyButton;
  hBefore: Integer;
begin
  F := TForm.CreateNew(nil);
  try
    Bar := TTyToolBar.Create(F);
    Bar.Parent := F;
    Bar.Align := alTop;
    Bar.ButtonHeight := 24;

    B := TTyButton.Create(F);
    B.Parent := Bar;
    B.Font.PixelsPerInch := 96;
    B.Caption := '&New';
    B.AutoSize := True;          // this is what used to loop
    hBefore := B.Height;

    // Grow the caption the way a translation does: it must not start a bounds war.
    B.Caption := 'New work order (a much longer translated caption)';
    Bar.Realign;

    AssertEquals('the bar still owns the height', hBefore, B.Height);
    AssertTrue('and the button is still a sane size', (B.Width > 0) and (B.Height > 0));
  finally
    F.Free;
  end;
end;

initialization
  RegisterTest(TButtonTest);
end.
