unit test.colorbutton;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, TypInfo, fpcunit, testregistry, Forms, Controls, Graphics,
  tyControls.Base, tyControls.Types, tyControls.Painter, tyControls.Controller,
  tyControls.ColorButton, tyControls.ToolBar;
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
    { 真正被画出来的那串 '#RRGGBB' 在当前样式下的设备像素宽度——宽度下限里的文字那一项。 }
    function CallMeasureHex(APPI: Integer): Integer;
    { 一行文字的高度(参考字形,与 Caption 无关):高度下限里的文字那一项。 }
    procedure CallMeasure(APPI: Integer; out AW, AH: Integer);
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
    procedure TestAnyColourChangeFiresOnColorChange;
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
    procedure TestPreferredCountsThePaintedCaption;
    procedure TestPreferredIncludesTheHexTextSlot;
    procedure TestSwatchSlotTracksTheRowHeight;
    procedure TestRoomierThemeWidensPreferredWidth;
    procedure TestPreferredHeightIsAlwaysZero;
  end;

  { SIZE FLOOR(Constraints.Min*)。手写的 Height 和主题的 --control-height 都只是**请求**;
    做得到的尺寸由字体和内边距决定,而只有控件同时知道这两样。色块按钮的特别之处在于:它
    **一个字都不画 Caption**——高度下限要是照基类量 Caption 的一行来算,就等于替一行根本不
    存在的字留位置;而 ShowText 打开时画的那串 '#RRGGBB' 又确实需要一整行。
    一律断言 Constraints:下限跟 AutoSize 开不开无关,而且没有窗体句柄时 AutoSizeDelayed
    会把真正的 resize 吞掉。 }
  TColorButtonFloorTest = class(TTestCase)
  published
    procedure TestFloorCountsThePaintedCaption;
    procedure TestSwatchOnlyFloorIsNotATextLine;
    procedure TestShowTextRaisesTheFloorToTheHexLine;
    procedure TestHexSlotIsPartOfTheWidthFloor;
    procedure TestSmallerFontLowersTheFloor;
    procedure TestFloorSurvivesAHeightPinningToolBar;
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
  { 故意把字号放到 40px:一行文字比 TyColorButtonMinSwatch(8px)高出一大截,所以
    「ShowText=False 时高度下限里有没有混进一行文字」这件事会响得刺耳,而不是刚好撞上。 }
  cCbHugeFontCss =
    'TyButton { background: #FFFFFF; color: #000000; border-width: 0px; padding: 4px 9px; font-size: 40px; }';

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

function TTyColorButtonAccess.CallMeasureHex(APPI: Integer): Integer;
begin
  Result := MeasureHexText(APPI, CurrentStyle);
end;

procedure TTyColorButtonAccess.CallMeasure(APPI: Integer; out AW, AH: Integer);
begin
  MeasureCaption(APPI, AW, AH);
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

{ This used to assert the opposite -- its own name said DoesNotFire -- and that split was
  the bug: OnColorChange fired for a dialog-driven change and stayed silent for a
  programmatic one, so a handler keeping something in step with the colour worked when the
  user picked and silently did not when the app restored a saved value. LCL fires on any
  change. }
procedure TColorButtonTest.TestAnyColourChangeFiresOnColorChange;
var B: TTyColorButton;
begin
  FChanged := 0;
  B := TTyColorButton.Create(nil);
  try
    B.OnColorChange := @HandleColorChange;
    B.SelectedColor := TyRGB(10, 20, 30);
    AssertEquals('a programmatic change fires it', 1, FChanged);
    B.SelectedColor := TyRGB(10, 20, 30);   // no-op (same value)
    AssertEquals('an unchanged write does not', 1, FChanged);
    B.SelectedColor := TyRGB(40, 50, 60);
    AssertEquals('and the next real change does', 2, FChanged);
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

procedure TColorButtonAutoSizeTest.TestPreferredCountsThePaintedCaption;
{ 这条以前钉的是相反的行为(名字就叫 IgnoresTheNeverPaintedCaption):Caption 一个像素
  都不画,所以量宽度时被刻意排除。现在 Caption 会画了——量宽就必须跟着算,否则 AutoSize
  正好把用户唯一填过的那个属性裁掉。两条分支(ShowText 开/关)都要算。 }
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
      B.Caption := 'A ridiculously long caption that IS painted';
      B.CallPreferred(wLong, h);
      AssertTrue('长 Caption 要撑宽', wLong > wShort);

      // ShowText=False 走的是另一条分支:以前那条分支根本没有文字位,Caption 同样看不见。
      B.ShowText := False;
      B.Caption := 'X';
      B.CallPreferred(wShort, h);
      B.Caption := 'A ridiculously long caption that IS painted';
      B.CallPreferred(wLong, h);
      AssertTrue('没有 hex 时也一样(文字位归 Caption)', wLong > wShort);
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

{ ---- TColorButtonFloorTest ---- }

procedure TColorButtonFloorTest.TestFloorCountsThePaintedCaption;
var
  Ctl: TTyStyleController;
  B: TTyColorButtonAccess;
  bare: Integer;
begin
  { 宽度下限 = 「色块 + 间隙 + 真正会画的文字 + 内边距」。Caption 会画了,它就在下限里;
    留在外面的话,一个钉了宽度的容器(工具条)会把 Caption 挤没,而且不报错。 }
  Ctl := TTyStyleController.Create(nil);
  B := TTyColorButtonAccess.Create(nil);
  try
    Ctl.LoadThemeCss(cCbTightCss);
    B.Controller := Ctl;
    B.Font.PixelsPerInch := 96;
    B.SetBounds(0, 0, 88, 30);
    B.Caption := '';
    B.Invalidate;
    bare := B.Constraints.MinWidth;

    B.Caption := 'A caption this button DOES draw';
    AssertTrue('会画的 Caption 必须进宽度下限',
      B.Constraints.MinWidth > bare);
  finally
    B.Free; Ctl.Free;
  end;
end;

procedure TColorButtonFloorTest.TestSwatchOnlyFloorIsNotATextLine;
var
  Ctl: TTyStyleController;
  B: TTyColorButtonAccess;
  tw, th: Integer;
begin
  { ShowText=False 时内容只有色块。DrawContent 里唯一的硬底线是 TyColorButtonMinSwatch,
    高度下限就该是「它 + 上下内边距」——40px 的字号在这里必须一点都不参与,否则一个纯色块
    按钮会被一行它根本不画的字顶高。 }
  Ctl := TTyStyleController.Create(nil);
  B := TTyColorButtonAccess.Create(nil);
  try
    Ctl.LoadThemeCss(cCbHugeFontCss);
    B.Controller := Ctl;
    B.Font.PixelsPerInch := 96;
    B.SetBounds(0, 0, 88, 30);
    B.ShowText := False;
    B.Invalidate;
    B.CallMeasure(96, tw, th);

    AssertTrue('premise: a 40px line is far taller than the 8px swatch minimum',
      th > TyColorButtonMinSwatch);
    AssertEquals('the height floor is the swatch minimum plus 4px+4px of padding',
      TyColorButtonMinSwatch + 8, B.Constraints.MinHeight);
  finally
    B.Free; Ctl.Free;
  end;
end;

procedure TColorButtonFloorTest.TestShowTextRaisesTheFloorToTheHexLine;
var
  Ctl: TTyStyleController;
  B: TTyColorButtonAccess;
  tw, th: Integer;
begin
  // 打开 ShowText 就真的画一行 '#RRGGBB' 了,那一行必须装得下——用的是和基类同一套字体度量。
  Ctl := TTyStyleController.Create(nil);
  B := TTyColorButtonAccess.Create(nil);
  try
    Ctl.LoadThemeCss(cCbHugeFontCss);
    B.Controller := Ctl;
    B.Font.PixelsPerInch := 96;
    B.SetBounds(0, 0, 88, 30);
    B.ShowText := True;
    B.Invalidate;
    B.CallMeasure(96, tw, th);

    AssertEquals('the height floor is one hex line plus the vertical padding',
      th + 8, B.Constraints.MinHeight);
    AssertTrue('...and it really is above the swatch-only floor',
      B.Constraints.MinHeight > TyColorButtonMinSwatch + 8);
  finally
    B.Free; Ctl.Free;
  end;
end;

procedure TColorButtonFloorTest.TestHexSlotIsPartOfTheWidthFloor;
var
  Ctl: TTyStyleController;
  B: TTyColorButtonAccess;
  swatchOnly: Integer;
begin
  { 宽度下限走的是 CalculatePreferredSize 这一条(量的就是画的),所以「间隙 + '#RRGGBB'」
    是最小宽度的一部分:少算这一段,色块和十六进制就会互相挤。12px 字号下两种模式的高度
    下限都低于 30,控件不会变高,ClientHeight 不动,所以这里的差值可以断成精确值。 }
  Ctl := TTyStyleController.Create(nil);
  B := TTyColorButtonAccess.Create(nil);
  try
    Ctl.LoadThemeCss(cCbTightCss);
    B.Controller := Ctl;
    B.Font.PixelsPerInch := 96;
    B.SetBounds(0, 0, 88, 30);
    B.ShowText := False;
    B.Invalidate;
    swatchOnly := B.Constraints.MinWidth;

    B.ShowText := True;
    AssertEquals('the extra width is exactly the gap plus the hex string that gets drawn',
      swatchOnly + TyColorButtonSwatchGap + B.CallMeasureHex(96),
      B.Constraints.MinWidth);
  finally
    B.Free; Ctl.Free;
  end;
end;

procedure TColorButtonFloorTest.TestSmallerFontLowersTheFloor;
var
  Ctl: TTyStyleController;
  B: TTyColorButtonAccess;
  bigH, bigW: Integer;
begin
  // 下限是推导出来的,不是一堵墙:字号和内边距调小,它就该跟着降。
  Ctl := TTyStyleController.Create(nil);
  B := TTyColorButtonAccess.Create(nil);
  try
    B.Controller := Ctl;
    B.Font.PixelsPerInch := 96;
    B.SetBounds(0, 0, 88, 30);
    B.ShowText := True;

    Ctl.LoadThemeCss('TyButton { font-size: 20px; padding: 8px; }');
    B.Invalidate;
    bigH := B.Constraints.MinHeight;
    bigW := B.Constraints.MinWidth;

    Ctl.LoadThemeCss('TyButton { font-size: 8px; padding: 1px; }');
    B.Invalidate;
    AssertTrue(Format('a smaller font+padding lowers the height floor (%d -> %d)',
      [bigH, B.Constraints.MinHeight]), B.Constraints.MinHeight < bigH);
    AssertTrue(Format('...and the width floor with it (%d -> %d)',
      [bigW, B.Constraints.MinWidth]), B.Constraints.MinWidth < bigW);
  finally
    B.Free; Ctl.Free;
  end;
end;

procedure TColorButtonFloorTest.TestFloorSurvivesAHeightPinningToolBar;
var
  F: TForm;
  Bar: TTyToolBar;
  B: TTyColorButton;
begin
  { 工具条把每个子控件钉到 ButtonHeight;子控件再提议一个自己的高度就会来回顶,LCL 以
    "ChangeBounds loop detected" 中止。Constraints 在 SetBounds 里钳,不协商。
    **跑到这一行本身就是断言**。 }
  F := TForm.CreateNew(nil);
  try
    Bar := TTyToolBar.Create(F);
    Bar.Parent := F;
    Bar.ButtonHeight := 40;
    B := TTyColorButton.Create(Bar);
    B.Parent := Bar;
    B.ShowText := True;
    B.AutoSize := True;
    Bar.ButtonHeight := 41;            // 真要是循环了,进程在这里就没了
    AssertTrue(Format('the bar asks for a height the floor can honour (%d)',
      [B.Constraints.MinHeight]), B.Constraints.MinHeight <= 40);
  finally
    F.Free;
  end;
end;

initialization
  RegisterTest(TColorButtonTest);
  RegisterTest(TColorButtonAutoSizeTest);
  RegisterTest(TColorButtonFloorTest);
end.
