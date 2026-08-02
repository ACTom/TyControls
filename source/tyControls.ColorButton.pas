unit tyControls.ColorButton;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Button, tyControls.Dialogs.Color;

const
  { Logical px (96-PPI baseline), scaled at every call site.
    SwatchGap  — the gap between the swatch and the '#RRGGBB' text when ShowText.
    MinSwatch  — the swatch never shrinks below this, however tight the content rect is.
    Named rather than inline because DrawContent DRAWS with them and
    CalculatePreferredSize MEASURES with them: an AutoSize width that does not match the
    paint is worse than no AutoSize at all, so the two must read the same number. }
  TyColorButtonSwatchGap = 6;
  TyColorButtonMinSwatch = 8;

// Pure helper: '#RRGGBB' (upper-case, alpha ignored). Unit-tested.
function TyColorHex(AColor: TTyColor): string;

type
  { TTyColorButton — a TTyButton that shows a colour swatch. Clicking opens the
    themed TySelectColor dialog and updates the swatch on OK. GetStyleTypeKey stays
    'TyButton' (inherited), so it reuses the button theme token — no new .tycss. }
  TTyColorButton = class(TTyButton)
  private
    FSelectedColor: TTyColor;
    FShowText: Boolean;
    FDialogCaption: string;
    FOnColorChange: TNotifyEvent;
    procedure SetSelectedColor(AValue: TTyColor);
    procedure SetShowText(AValue: Boolean);
  protected
    // Draw the swatch (rounded, filled with SelectedColor, subtle border) inset on
    // the left of AContentRect; when ShowText, draw the '#RRGGBB' hex to its right.
    procedure DrawContent(APainter: TTyPainter; const AContentRect: TRect;
      const AStyle: TTyStyleSet); override;
    { ContentText 在 APPI 下的设备像素宽度(用 AStyle 的字体)。画什么就量什么——
      量错了 AutoSize 就会把文字裁掉,而裁掉的正是用户唯一填过的那个属性。 }
    function MeasureHexText(APPI: Integer; const AStyle: TTyStyleSet): Integer;
    { 色块按钮的宽度和别的按钮不一样,所以**不**走基类的实现(基类量 Caption,而这里
      Caption 不画)。它要装下 DrawContent 真正画的东西:
        ShowText=True  -> 方形色块(边长 = 内容区高度)+ 间隙 + '#RRGGBB' 文字 + 内边距
        ShowText=False -> 色块本来是铺满内容区的,没有天然宽度;取一个正方形色块
                          (边长 = 内容区高度)作为它的自然尺寸,这样 AutoSize 给出的
                          是一个方方正正的取色块,而不是一条被压扁的色带。
      高度同 TTyButton:保持 0(本轴无意见),交给排版决定。

      本方法同时是**尺寸下限**的宽度来源(TTyButton.UpdateSizeConstraints 调它算
      Constraints.MinWidth),所以「色块 + 间隙 + 文字」不是装饰,而是这个按钮的最小宽度。 }
    procedure CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
      WithThemeSpace: Boolean); override;
    { 高度下限里的「内容」。基类量的是一行 Caption,可这个按钮**一个字都不画 Caption**:
      画的是色块,ShowText 时再加一串 '#RRGGBB'。所以下限从 DrawContent 里唯一那条硬底线
      起算——TyColorButtonMinSwatch(色块再挤也不小于它);开了 ShowText 才还要装得下一行
      十六进制文字,而那一行的高度和基类量的是同一套字体度量(同名字体、同 MulDiv 字号、
      同粗体阈值),所以直接问基类要,不另起一套。 }
    function MeasureContentHeight(APPI: Integer): Integer; override;
  public
    { 这个按钮**实际会画出来**的那串文字。

      Caption 优先:它是 published 的、能在设计器里填、文档也写着"语义与 TTyButton
      一致",但以前**一个像素都不画**——填了 Caption 只会看见一个色块,没有任何报错,
      于是只能怀疑自己的代码。LCL 的 TColorButton 是 TCustomSpeedButton 的后代,
      Caption 一直是画的。
      Caption 为空时退回 ShowText 的 '#RRGGBB';两者都没有就是空串(纯色块)。 }
    function ContentText: string;
    constructor Create(AOwner: TComponent); override;
    // The button's click IS "open the colour dialog": pick a colour via TySelectColor,
    // and on an accepted change repaint + fire OnColorChange. inherited Click is still
    // called so OnClick fires too. (Guarded so headless tests never reach TySelectColor.)
    procedure Click; override;
  published
    // The current swatch colour. Setting it programmatically repaints but does NOT
    // fire OnColorChange (that event is reserved for dialog-driven changes).
    property SelectedColor: TTyColor read FSelectedColor write SetSelectedColor default $FF3B82F6;
    // When True, the '#RRGGBB' hex is drawn as the caption to the right of the swatch;
    // when False the swatch fills most of the content area.
    property ShowText: Boolean read FShowText write SetShowText default False;
    // Title bar text of the colour dialog opened on click.
    property DialogCaption: string read FDialogCaption write FDialogCaption;
    // Fired only when the dialog is accepted AND the colour actually changed.
    property OnColorChange: TNotifyEvent read FOnColorChange write FOnColorChange;
  end;

implementation

function TyColorHex(AColor: TTyColor): string;
begin
  // RGB only (alpha ignored), upper-case — e.g. TyRGB(59,130,246) -> '#3B82F6'.
  Result := Format('#%.2X%.2X%.2X', [TyRedOf(AColor), TyGreenOf(AColor), TyBlueOf(AColor)]);
end;

{ Build a solid TTyFill. A standalone function (NOT a method) so Default(TTyFill)
  resolves to the compiler intrinsic — inside a TTyButton descendant's method the
  inherited published 'Default' property would shadow it. }
function SolidFill(AColor: TTyColor): TTyFill;
begin
  Result := Default(TTyFill);
  Result.Kind := tfkSolid;
  Result.Color := AColor;
end;

constructor TTyColorButton.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSelectedColor := TyRGB(59, 130, 246);   // $FF3B82F6 — the library accent blue
  FShowText := False;
  FDialogCaption := 'Select Color';
end;

procedure TTyColorButton.SetSelectedColor(AValue: TTyColor);
begin
  if FSelectedColor = AValue then Exit;
  FSelectedColor := AValue;
  Invalidate;
  { Fire on ANY change, as LCL does -- it used to fire only for a dialog-driven one. That
    split meant a handler that keeps something in step with the colour (a preview, a
    document property) worked when the user picked and silently did not when the app
    restored a saved value, which is exactly the case nobody tests. Suppressed while
    streaming, or every .lfm load would fire it before the form exists. }
  if not (csLoading in ComponentState) then
    if Assigned(FOnColorChange) then FOnColorChange(Self);
end;

procedure TTyColorButton.SetShowText(AValue: Boolean);
begin
  if FShowText = AValue then Exit;
  FShowText := AValue;
  Invalidate;
end;

procedure TTyColorButton.DrawContent(APainter: TTyPainter; const AContentRect: TRect;
  const AStyle: TTyStyleSet);
var
  swatch, capRect: TRect;
  fill: TTyFill;
  cw, gap, radius: Integer;
  borderCol: TTyColor;
  hasText: Boolean;
begin
  // Degenerate rect (headless zero-size render) — nothing to draw, stay crash-safe.
  if (AContentRect.Right <= AContentRect.Left) or (AContentRect.Bottom <= AContentRect.Top) then
    Exit;
  gap := APainter.Scale(TyColorButtonSwatchGap);
  hasText := ContentText <> '';
  if hasText then
    // Fixed square swatch on the left, its side = content height (a small min floor).
    cw := AContentRect.Bottom - AContentRect.Top
  else
    // No text: the swatch fills the whole content area.
    cw := AContentRect.Right - AContentRect.Left;
  if cw < APainter.Scale(TyColorButtonMinSwatch) then cw := APainter.Scale(TyColorButtonMinSwatch);
  if cw > (AContentRect.Right - AContentRect.Left) then
    cw := AContentRect.Right - AContentRect.Left;
  swatch := Rect(AContentRect.Left, AContentRect.Top, AContentRect.Left + cw, AContentRect.Bottom);

  // Subtle border: prefer the resolved style's border colour; else a fixed low-contrast grey.
  if tpBorderColor in AStyle.Present then
    borderCol := AStyle.BorderColor
  else
    borderCol := TyRGBA(0, 0, 0, 40);

  // Rounded swatch, filled with the selected colour.
  fill := SolidFill(FSelectedColor);
  radius := 3;   // logical px; FillBackground/StrokeBorder scale it
  APainter.FillBackground(swatch, fill, TyUniformCorners(radius));
  APainter.StrokeBorder(swatch, TyUniformCorners(radius), 1, borderCol);

  // Caption (or, with none, the optional hex) to the right of the swatch.
  if hasText then
  begin
    capRect := Rect(swatch.Right + gap, AContentRect.Top, AContentRect.Right, AContentRect.Bottom);
    if capRect.Right > capRect.Left then
      APainter.DrawText(capRect, ContentText, AStyle.FontName,
        ResolveFontSize(AStyle), AStyle.FontWeight, AStyle.TextColor, taLeftJustify, tlCenter, True);
  end;
end;

function TTyColorButton.ContentText: string;
begin
  if Caption <> '' then Result := Caption
  else if FShowText then Result := TyColorHex(FSelectedColor)
  else Result := '';
end;

function TTyColorButton.MeasureHexText(APPI: Integer; const AStyle: TTyStyleSet): Integer;
var
  Meas: TBitmap;
  txt: string;
begin
  txt := ContentText;
  if txt = '' then Exit(0);
  // 与 TTyButton.MeasureCaption 同一套量法(同样的字体名回落、同样的 MulDiv 字号缩放、
  // 同样的粗体阈值),只是量的字符串换成了真正会被画出来的十六进制色值。
  Meas := TBitmap.Create;
  try
    Meas.SetSize(1, 1);
    Meas.Canvas.Font.Name := TyEffectiveFontName(AStyle.FontName);
    Meas.Canvas.Font.Size := MulDiv(ResolveFontSize(AStyle), APPI, 96);
    if AStyle.FontWeight >= 600 then
      Meas.Canvas.Font.Style := [fsBold]
    else
      Meas.Canvas.Font.Style := [];
    Result := Meas.Canvas.TextWidth(txt);
    if Result < 0 then Result := 0;
  finally
    Meas.Free;
  end;
end;

function TTyColorButton.MeasureContentHeight(APPI: Integer): Integer;
var
  lineH: Integer;
begin
  // DrawContent 的硬底线:色块边长永远不小于 TyColorButtonMinSwatch(同一个常量、同一个
  // 96 基线换算),所以内容至少这么高。
  Result := MulDiv(TyColorButtonMinSwatch, APPI, 96);
  if Result < 1 then Result := 1;
  // 不显示文字时,内容就只有色块——不该替一行根本不画的字留位置。
  if ContentText = '' then Exit;
  lineH := inherited MeasureContentHeight(APPI);   // 一行文字的高度(参考字形,与 Caption 无关)
  if lineH > Result then Result := lineH;
end;

procedure TTyColorButton.CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
  WithThemeSpace: Boolean);
var
  S: TTyStyleSet;
  ppi, padH, padV, swatch, minSwatch: Integer;
begin
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  S := CurrentStyle;
  // RenderTo 用这四条内边距把客户区内缩成 DrawContent 拿到的内容区,所以量的时候
  // 必须用同一组数、同一个换算。
  padH := MulDiv(S.Padding.Left + S.Padding.Right, ppi, 96);
  padV := MulDiv(S.Padding.Top + S.Padding.Bottom, ppi, 96);
  // 色块是正方形,边长 = 内容区高度(DrawContent 里的 cw := 内容区高)。高度不归我们
  // 管(见下面的 PreferredHeight),所以直接读当前的客户区高度——排版把行高定成多少,
  // 色块就是多大的方块。
  minSwatch := MulDiv(TyColorButtonMinSwatch, ppi, 96);
  swatch := ClientHeight - padV;
  if swatch < minSwatch then swatch := minSwatch;
  if ContentText <> '' then
    // 方块 + 间隙 + 文字(Caption 优先,否则 '#RRGGBB'),正是 DrawContent 摆的三件东西。
    PreferredWidth := swatch + MulDiv(TyColorButtonSwatchGap, ppi, 96) +
      MeasureHexText(ppi, S) + padH
  else
    // 没有文字时色块铺满内容区,本身没有天然宽度;给一个正方形色块。
    PreferredWidth := swatch + padH;
  if PreferredWidth < 1 then PreferredWidth := 1;
  { 0 = LCL 的「本轴无意见」。理由与 TTyButton 完全相同:高度是容器的决定,控件再报一个
    就会和钉高度的父容器(如 TTyToolBar)互相顶,直到 LCL 抛
    "TControl.ChangeBounds loop detected"。 }
  PreferredHeight := 0;
end;

procedure TTyColorButton.Click;
var
  newColor: TTyColor;
  didChange: Boolean;
begin
  if not Enabled then Exit;
  { inherited FIRST, so OnClick observes the PRE-dialog colour and can still cancel or
    reconfigure -- LCL runs the click before opening the picker. Ours opened the dialog
    first, so an OnClick handler was told about a decision the user had already made and
    could do nothing about. }
  inherited Click;
  newColor := FSelectedColor;
  // TySelectColor updates newColor in place; True iff the user accepted (OK).
  if TySelectColor(FDialogCaption, newColor) then
  begin
    didChange := newColor <> FSelectedColor;
    if didChange then
      SelectedColor := newColor;   { one path for the repaint + OnColorChange }
  end;
end;

end.
