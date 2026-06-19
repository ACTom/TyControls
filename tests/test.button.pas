unit test.button;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, TypInfo, fpcunit, testregistry, Forms, Controls, Graphics, LCLType,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Base, tyControls.Button, tyControls.Types, tyControls.Controller;
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
  if AValue < 3 then AVisible := False;   // 用户策略:<3 不显示
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
    // disabled 优先:Down 不叠加
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
  // 选中的 ghost 按钮、hover 淡入中间帧:静止端应是 ghost:selected(不透明 surface-active)。
  // 修复前混色取 normal(透明)<->hover,中间帧是半透明 over 黑底 -> 绿通道塌到 ~66;
  // 修复后取 selected<->selected+hover,两端皆不透明浅灰 -> 绿通道 ~234。以绿通道判别。
  // 用专属 controller(全新 = 内置 light 主题),隔离全局 TyDefaultController 可能被其它测试污染。
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
    Bmp.Canvas.Brush.Color := clBlack;          // 黑底:半透明会明显塌绿
    Bmp.Canvas.FillRect(0, 0, 80, 28);
    B.ArmBg(1);                                  // 朝 hover 端推进
    B.AdvanceAnim(12);                           // 12/120=0.1 -> Eased=0.271,落在混色区间
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
    // 关:不显示
    B.ShowBadge := False; B.BadgeValue := 5;
    AssertFalse('off -> not visible', B.CallResolveBadge(txt));
    // 开 + 值0:默认显示 "0"
    B.ShowBadge := True; B.BadgeValue := 0;
    AssertTrue('on, value 0 -> visible by default', B.CallResolveBadge(txt));
    AssertEquals('value 0 text', '0', txt);
    // >99 -> 99+
    B.BadgeValue := 150;
    AssertTrue(B.CallResolveBadge(txt));
    AssertEquals('cap at 99+', '99+', txt);
    // 事件隐藏 <3
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
  // 内置 TyBadge 背景 = var(--accent) = #3B82F6。右下角应出现 accent 蓝;关掉后没有。
  // 专属 controller(内置 light),隔离全局 TyDefaultController 被其它测试改主题的可能。
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

    // 关掉角标:右下角不应再有 accent 蓝(默认按钮底为白,红通道高,被排除)。
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

initialization
  RegisterTest(TButtonTest);
end.
