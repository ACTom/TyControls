unit test.colorbutton;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, TypInfo, fpcunit, testregistry, Forms, Controls, Graphics,
  tyControls.Base, tyControls.Types, tyControls.Painter, tyControls.Controller,
  tyControls.ColorButton;
type
  // Expose the protected DrawContent so a headless render can be exercised without
  // opening the (GUI-only) colour dialog.
  TTyColorButtonAccess = class(TTyColorButton)
  public
    procedure CallDrawContent(APainter: TTyPainter; const AContentRect: TRect;
      const AStyle: TTyStyleSet);
    { The protected preferred-size calculation — what AutoSize would resize to.
      断言必须走这里而不是 Width:父窗体没句柄时 AutoSizeDelayed 会吞掉自动调整,
      读 Width 等于什么都没测。 }
    procedure CallPreferred(out AW, AH: Integer);
  end;

  TColorButtonTest = class(TTestCase)
  private
    FChanged: Integer;
    procedure HandleColorChange(Sender: TObject);
  published
    procedure TestTypeKeyStaysTyButton;
    procedure TestHexKnownValues;
    procedure TestHexIgnoresAlpha;
    procedure TestDefaultSelectedColor;
    procedure TestSelectedColorRoundTrips;
    procedure TestProgrammaticSetDoesNotFireOnColorChange;
    procedure TestShowTextTogglePublished;
    procedure TestDialogCaptionDefault;
    procedure TestDrawContentSafeNoText;
    procedure TestDrawContentSafeWithText;
    procedure TestDrawContentSafeDegenerateRect;
  end;

  { AutoSize / 首选宽度。色块按钮画的是「色块 (+ 间隙 + #RRGGBB)」,而**不是** Caption,
    所以它自己算宽度,不能沿用基类那套量 Caption 的算法。这里守的就是「量的 == 画的」:
    量多了按钮凭空变胖,量少了色块和十六进制被挤掉——两种都是 AutoSize 在说谎。 }
  TColorButtonAutoSizeTest = class(TTestCase)
  published
    procedure TestAutoSizePublishedButOffByDefault;
    procedure TestPreferredIgnoresTheNeverPaintedCaption;
    procedure TestPreferredIncludesTheHexTextSlot;
    procedure TestSwatchSlotTracksTheRowHeight;
    procedure TestRoomierThemeWidensPreferredWidth;
    procedure TestPreferredHeightIsAlwaysZero;
  end;

implementation

const
  { 写死内边距和字号,断言才能算出确定的数字。上下 4px、左右 9px;border-width:0 让
    宽度里只剩「色块 + 间隙 + 文字 + 左右内边距」。 }
  cCbTightCss =
    'TyButton { background: #FFFFFF; color: #000000; border-width: 0px; padding: 4px 9px; font-size: 12px; }';
  { 同上,左右内边距 9px -> 35px(每边 +26,共 +52);上下不动,所以色块边长不变。 }
  cCbRoomyCss =
    'TyButton { background: #FFFFFF; color: #000000; border-width: 0px; padding: 4px 35px; font-size: 12px; }';

procedure TTyColorButtonAccess.CallDrawContent(APainter: TTyPainter;
  const AContentRect: TRect; const AStyle: TTyStyleSet);
begin
  DrawContent(APainter, AContentRect, AStyle);
end;

procedure TTyColorButtonAccess.CallPreferred(out AW, AH: Integer);
begin
  AW := 0; AH := 0;
  CalculatePreferredSize(AW, AH, True);
end;

procedure TColorButtonTest.HandleColorChange(Sender: TObject);
begin
  Inc(FChanged);
end;

procedure TColorButtonTest.TestTypeKeyStaysTyButton;
var B: TTyColorButton;
begin
  // Reuses the button token — must NOT introduce a new typeKey.
  B := TTyColorButton.Create(nil);
  try
    AssertEquals('TyButton', (B as ITyStyleable).GetStyleTypeKey);
  finally B.Free; end;
end;

procedure TColorButtonTest.TestHexKnownValues;
begin
  AssertEquals('accent blue', '#3B82F6', TyColorHex(TyRGB(59, 130, 246)));
  AssertEquals('black', '#000000', TyColorHex(TyRGB(0, 0, 0)));
  AssertEquals('white', '#FFFFFF', TyColorHex(TyRGB(255, 255, 255)));
end;

procedure TColorButtonTest.TestHexIgnoresAlpha;
begin
  // Same RGB, different alpha -> identical hex (alpha is dropped, upper-case).
  AssertEquals('alpha ignored', '#3B82F6', TyColorHex(TyRGBA(59, 130, 246, 0)));
  AssertEquals('alpha ignored 2', TyColorHex(TyRGB(18, 52, 86)),
    TyColorHex(TyRGBA(18, 52, 86, 128)));
end;

procedure TColorButtonTest.TestDefaultSelectedColor;
var B: TTyColorButton;
begin
  B := TTyColorButton.Create(nil);
  try
    AssertEquals('default = accent blue $FF3B82F6',
      Integer(TyRGB(59, 130, 246)), Integer(B.SelectedColor));
  finally B.Free; end;
end;

procedure TColorButtonTest.TestSelectedColorRoundTrips;
var B: TTyColorButtonAccess;
begin
  B := TTyColorButtonAccess.Create(nil);
  try
    B.SelectedColor := TyRGB(200, 100, 50);
    AssertEquals('round-trips', Integer(TyRGB(200, 100, 50)), Integer(B.SelectedColor));
    AssertEquals('hex reflects new colour', '#C86432', TyColorHex(B.SelectedColor));
    AssertTrue('SelectedColor published', IsPublishedProp(B, 'SelectedColor'));
  finally B.Free; end;
end;

procedure TColorButtonTest.TestProgrammaticSetDoesNotFireOnColorChange;
var B: TTyColorButton;
begin
  // OnColorChange is dialog-driven only; a programmatic setter must not fire it.
  FChanged := 0;
  B := TTyColorButton.Create(nil);
  try
    B.OnColorChange := @HandleColorChange;
    B.SelectedColor := TyRGB(10, 20, 30);
    B.SelectedColor := TyRGB(10, 20, 30);   // no-op (same value)
    B.SelectedColor := TyRGB(40, 50, 60);
    AssertEquals('programmatic set never fires OnColorChange', 0, FChanged);
    AssertTrue('OnColorChange published', IsPublishedProp(B, 'OnColorChange'));
  finally B.Free; end;
end;

procedure TColorButtonTest.TestShowTextTogglePublished;
var B: TTyColorButton;
begin
  B := TTyColorButton.Create(nil);
  try
    AssertFalse('ShowText default False', B.ShowText);
    B.ShowText := True;
    AssertTrue('ShowText toggles', B.ShowText);
    AssertTrue('ShowText published', IsPublishedProp(B, 'ShowText'));
  finally B.Free; end;
end;

procedure TColorButtonTest.TestDialogCaptionDefault;
var B: TTyColorButton;
begin
  B := TTyColorButton.Create(nil);
  try
    AssertEquals('DialogCaption default', 'Select Color', B.DialogCaption);
    AssertTrue('DialogCaption published', IsPublishedProp(B, 'DialogCaption'));
  finally B.Free; end;
end;

// --- headless DrawContent smoke tests (paint into a bitmap, must not raise) ---

procedure TColorButtonTest.TestDrawContentSafeNoText;
var
  B: TTyColorButtonAccess; Bmp: TBitmap; P: TTyPainter; S: TTyStyleSet;
begin
  B := TTyColorButtonAccess.Create(nil);
  Bmp := TBitmap.Create;
  try
    B.SelectedColor := TyRGB(0, 200, 100);
    B.ShowText := False;
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(88, 30);
    S := EmptyStyleSet;
    P := TTyPainter.Create;
    try
      P.BeginPaint(Bmp.Canvas, Rect(0, 0, 88, 30), 96);
      B.CallDrawContent(P, Rect(4, 4, 84, 26), S);
      P.EndPaint;
    finally P.Free; end;
    AssertTrue('DrawContent (no text) executed without exception', True);
  finally Bmp.Free; B.Free; end;
end;

procedure TColorButtonTest.TestDrawContentSafeWithText;
var
  B: TTyColorButtonAccess; Bmp: TBitmap; P: TTyPainter; S: TTyStyleSet;
begin
  B := TTyColorButtonAccess.Create(nil);
  Bmp := TBitmap.Create;
  try
    B.SelectedColor := TyRGB(59, 130, 246);
    B.ShowText := True;
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(120, 30);
    S := EmptyStyleSet;
    S.FontSize := 12;
    S.FontWeight := 400;
    S.TextColor := TyRGB(30, 30, 30);
    P := TTyPainter.Create;
    try
      P.BeginPaint(Bmp.Canvas, Rect(0, 0, 120, 30), 96);
      B.CallDrawContent(P, Rect(4, 4, 116, 26), S);
      P.EndPaint;
    finally P.Free; end;
    AssertTrue('DrawContent (with hex text) executed without exception', True);
  finally Bmp.Free; B.Free; end;
end;

procedure TColorButtonTest.TestDrawContentSafeDegenerateRect;
var
  B: TTyColorButtonAccess; Bmp: TBitmap; P: TTyPainter; S: TTyStyleSet;
begin
  // A zero/negative content rect must be a no-op, never a crash.
  B := TTyColorButtonAccess.Create(nil);
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(10, 10);
    S := EmptyStyleSet;
    P := TTyPainter.Create;
    try
      P.BeginPaint(Bmp.Canvas, Rect(0, 0, 10, 10), 96);
      B.CallDrawContent(P, Rect(5, 5, 5, 5), S);   // empty rect
      B.CallDrawContent(P, Rect(8, 8, 2, 2), S);   // inverted rect
      P.EndPaint;
    finally P.Free; end;
    AssertTrue('DrawContent tolerates a degenerate rect', True);
  finally Bmp.Free; B.Free; end;
end;

{ TColorButtonAutoSizeTest }

procedure TColorButtonAutoSizeTest.TestAutoSizePublishedButOffByDefault;
{ published 才能在 .lfm 和对象查看器里设;默认仍是 False,所以已经排好版的界面一个像素
  都不会动,想自适应的人自己打开。 }
var B: TTyColorButton;
begin
  B := TTyColorButton.Create(nil);
  try
    AssertTrue('AutoSize is published', IsPublishedProp(B, 'AutoSize'));
    AssertFalse('but it stays OFF by default', B.AutoSize);
  finally B.Free; end;
end;

procedure TColorButtonAutoSizeTest.TestPreferredIgnoresTheNeverPaintedCaption;
{ 关键一条:TTyColorButton.DrawContent 从不调用基类的 DrawContent,Caption 一个像素都不画
  (设计期里它默认还是组件名,比如 'TyColorButton1')。所以量宽度时绝不能把它算进去,
  否则按钮会为一段看不见的文字白白变胖。 }
var
  Ctl: TTyStyleController;
  B: TTyColorButtonAccess;
  wShort, wLong, h: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss(cCbTightCss);
    B := TTyColorButtonAccess.Create(nil);
    try
      B.Controller := Ctl;
      B.Font.PixelsPerInch := 96;
      B.SetBounds(0, 0, 88, 30);
      B.ShowText := True;

      B.Caption := 'X';
      B.CallPreferred(wShort, h);
      B.Caption := 'A ridiculously long caption that is never painted';
      B.CallPreferred(wLong, h);
      AssertEquals('the never-painted Caption adds no width', wShort, wLong);

      // ShowText=False 走的是另一条分支,同样不许把 Caption 算进去。
      B.ShowText := False;
      B.Caption := 'X';
      B.CallPreferred(wShort, h);
      B.Caption := 'A ridiculously long caption that is never painted';
      B.CallPreferred(wLong, h);
      AssertEquals('same with no hex text', wShort, wLong);
    finally B.Free; end;
  finally Ctl.Free; end;
end;

procedure TColorButtonAutoSizeTest.TestPreferredIncludesTheHexTextSlot;
{ ShowText 打开后,DrawContent 在色块右边摆「间隙 + #RRGGBB」,所以宽度必须多出这两段。
  再用字号把文字撑大:宽度只能从文字这一项长出来(色块只跟高度走,内边距没变),
  证明量的确实是那串会被画出来的十六进制。 }
var
  Ctl: TTyStyleController;
  B: TTyColorButtonAccess;
  wPlain, wHex, wBigFont, h: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss(cCbTightCss);
    B := TTyColorButtonAccess.Create(nil);
    try
      B.Controller := Ctl;
      B.Font.PixelsPerInch := 96;
      B.SetBounds(0, 0, 88, 30);
      B.SelectedColor := TyRGB(59, 130, 246);   // '#3B82F6'

      B.ShowText := False;
      B.CallPreferred(wPlain, h);
      B.ShowText := True;
      B.CallPreferred(wHex, h);
      // 间隙就是 6 逻辑 px;文字本身必须还要再占一块,所以差值必然大于间隙。
      AssertTrue(Format('the hex slot adds the gap AND the text (%d -> %d)', [wPlain, wHex]),
        wHex > wPlain + TyColorButtonSwatchGap);

      Ctl.LoadThemeCss(
        'TyButton { background: #FFFFFF; color: #000000; border-width: 0px; padding: 4px 9px; font-size: 24px; }');
      B.CallPreferred(wBigFont, h);
      AssertTrue(Format('a bigger theme font widens the hex slot (%d -> %d)', [wHex, wBigFont]),
        wBigFont > wHex);
    finally B.Free; end;
  finally Ctl.Free; end;
end;

procedure TColorButtonAutoSizeTest.TestSwatchSlotTracksTheRowHeight;
{ 色块是正方形,边长 = 内容区高度(DrawContent 里 cw := 内容高)。行高变了,色块跟着变,
  首选宽度也必须跟着变同样多——这就是「量的必须是画的那块」。 }
var
  Ctl: TTyStyleController;
  B: TTyColorButtonAccess;
  ch30, ch50, w30, w50, h: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss(cCbTightCss);
    B := TTyColorButtonAccess.Create(nil);
    try
      B.Controller := Ctl;
      B.Font.PixelsPerInch := 96;
      B.ShowText := True;
      B.Caption := '';

      B.SetBounds(0, 0, 88, 30);
      ch30 := B.ClientHeight;
      B.CallPreferred(w30, h);

      B.SetBounds(0, 0, 88, 50);
      ch50 := B.ClientHeight;
      B.CallPreferred(w50, h);

      AssertTrue('the row really got taller', ch50 > ch30);
      AssertEquals('the square swatch widens by exactly the extra height',
        w30 + (ch50 - ch30), w50);
    finally B.Free; end;
  finally Ctl.Free; end;
end;

procedure TColorButtonAutoSizeTest.TestRoomierThemeWidensPreferredWidth;
{ 这就是这轮要修的 bug 的形状:换一套左右内边距更大的皮肤(xp 的 TyButton padding 从
  6px 变 12px 就是这么回事),按 default 皮肤量好的宽度就装不下内容了。首选宽度必须跟着
  皮肤变大,而且差值正好是多出来的内边距。上下内边距没动,所以色块边长不变。 }
var
  Ctl: TTyStyleController;
  B: TTyColorButtonAccess;
  tight, roomy, h: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    B := TTyColorButtonAccess.Create(nil);
    try
      B.Controller := Ctl;
      B.Font.PixelsPerInch := 96;
      B.SetBounds(0, 0, 88, 30);
      B.AutoSize := True;
      B.ShowText := True;

      Ctl.LoadThemeCss(cCbTightCss);
      B.CallPreferred(tight, h);

      Ctl.LoadThemeCss(cCbRoomyCss);
      B.CallPreferred(roomy, h);

      AssertTrue(Format('a roomier skin widens the colour button (%d -> %d)', [tight, roomy]),
        roomy > tight);
      AssertEquals('the extra width is exactly the extra padding', tight + 52, roomy);
    finally B.Free; end;
  finally Ctl.Free; end;
end;

procedure TColorButtonAutoSizeTest.TestPreferredHeightIsAlwaysZero;
{ 0 = LCL 的「本轴无意见」:按钮只横向长,高度归排版。控件再报一个高度就会和钉高度的
  父容器(TTyToolBar 把子控件钉到 ButtonHeight)互相顶,最后 LCL 以
  "TControl.ChangeBounds loop detected" 中止。 }
var
  Ctl: TTyStyleController;
  B: TTyColorButtonAccess;
  w, h: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss(cCbTightCss);
    B := TTyColorButtonAccess.Create(nil);
    try
      B.Controller := Ctl;
      B.Font.PixelsPerInch := 96;
      B.SetBounds(0, 0, 88, 30);

      B.ShowText := False;
      B.CallPreferred(w, h);
      AssertEquals('no height proposed (swatch only)', 0, h);
      AssertTrue('but a positive width is', w > 0);

      B.ShowText := True;
      B.AutoSize := True;
      B.CallPreferred(w, h);
      AssertEquals('no height proposed (swatch + hex)', 0, h);
      AssertTrue('but a positive width is', w > 0);
    finally B.Free; end;
  finally Ctl.Free; end;
end;

initialization
  RegisterTest(TColorButtonTest);
  RegisterTest(TColorButtonAutoSizeTest);
end.
