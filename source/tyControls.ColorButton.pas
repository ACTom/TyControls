unit tyControls.ColorButton;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Button, tyControls.ColorMath,
  tyControls.Accel, tyControls.Dialogs.Color;

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
  { TTyColorButton — a push button (on TTyCustomButton) that shows a colour swatch. Clicking opens the
    themed TySelectColor dialog and updates the swatch on OK. GetStyleTypeKey stays
    'TyButton' (inherited), so it reuses the button theme token — no new .tycss. }
  TTyCustomColorButton = class(TTyCustomButton)
  private
    FSelectedColor: TTyColor;
    FShowText: Boolean;
    FDialogCaption: string;
    FOnColorChange: TNotifyEvent;
    FOnColorChanged: TNotifyEvent;
    procedure SetSelectedColor(AValue: TTyColor);
    procedure SetShowText(AValue: Boolean);
    function GetButtonColor: TColor;
    procedure SetButtonColor(AValue: TColor);
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
    // The current swatch colour. Setting it programmatically repaints but does NOT
    // fire OnColorChange (that event is reserved for dialog-driven changes).
    property SelectedColor: TTyColor read FSelectedColor write SetSelectedColor default $FF3B82F6;
    { LCL's name and LCL's TYPE for the same swatch (dialogs.pp:370). Both halves matter:
      `Btn.ButtonColor := clRed` is the one line every TColorButton user writes, and a raw
      TColor assigned to SelectedColor would be read as ARGB and come out the wrong colour
      with no error -- so the conversion has to live behind the LCL-spelled name, not in the
      porter's head.
      `stored False` on purpose: this is a second view of FSelectedColor, not a second
      value. A published property is READ from an .lfm whether or not it is stored, so a
      ported `ButtonColor = clRed` line loads; not storing it keeps our own .lfm from
      carrying the same colour twice under two names. }
    property ButtonColor: TColor read GetButtonColor write SetButtonColor stored False;
    { The caption sits in the strip LEFT OVER beside the swatch, so it starts at that
      strip's left edge rather than floating in the middle of it -- hence the default the
      base does not have. Still fully settable: taCenter or taRightJustify move the text
      within the strip, and the swatch never moves. }
    property Alignment default taLeftJustify;
    // When True, the '#RRGGBB' hex is drawn as the caption to the right of the swatch;
    // when False the swatch fills most of the content area.
    property ShowText: Boolean read FShowText write SetShowText default False;
    // Title bar text of the colour dialog opened on click.
    property DialogCaption: string read FDialogCaption write FDialogCaption;
    // Fired whenever the colour actually changes, however it changed (see SetSelectedColor).
    property OnColorChange: TNotifyEvent read FOnColorChange write FOnColorChange;
    { LCL's name for the very same notification (dialogs.pp:387-388) -- one letter apart,
      which is exactly the kind of difference that reads as "the event is missing". Both
      fire, OnColorChange first. Two fields rather than one aliased field, so each streams
      under its own name and a save never silently renames the host's handler. }
    property OnColorChanged: TNotifyEvent read FOnColorChanged write FOnColorChanged;
  end;

  { TTyColorButton publishes TTyCustomColorButton's properties; everything lives in TTyCustomColorButton. }
  TTyColorButton = class(TTyCustomColorButton)
  published
    property Version;
    property Enabled;
    property Visible;
    property Font;
    property ShowHint;
    property TabOrder;
    property TabStop;
    property OnClick;
    property OnDblClick;
    property OnMouseDown;
    property OnMouseUp;
    property OnMouseMove;
    property OnMouseEnter;
    property OnMouseLeave;
    property OnMouseWheel;
    property OnMouseWheelUp;
    property OnMouseWheelDown;
    property OnContextPopup;
    property OnResize;
    property OnChangeBounds;
    property AutoSize;
    property BorderWidth;
    property ChildSizing;
    property DragMode;
    property DragKind;
    property DragCursor;
    property OnDragOver;
    property OnDragDrop;
    property OnStartDrag;
    property OnEndDrag;
    property OnMouseWheelHorz;
    property OnMouseWheelLeft;
    property OnMouseWheelRight;
    property OnShowHint;
    property PopupMenu;
    property Constraints;
    property BorderSpacing;
    property ParentShowHint;
    property Action;
    property OnPaint;
    property OnKeyDown;
    property OnKeyUp;
    property OnKeyPress;
    property OnUTF8KeyPress;
    property OnEnter;
    property OnExit;
    property OnEditingDone;
    property StyleClass;
    property StyleOverride;
    property Controller;
    property AnimationsEnabled;
    property Default;
    property Cancel;
    property Down;
    property ModalResult;
    property Alignment;
    property ShowAccelChar;
    property ShowBadge;
    property BadgeValue;
    property BadgePosition;
    property OnBadgeDisplay;
    property Caption;
    property Align;
    property Anchors;
    property SelectedColor;
    property ButtonColor;
    property ShowText;
    property DialogCaption;
    property OnColorChange;
    property OnColorChanged;
  end;

implementation

function TyColorHex(AColor: TTyColor): string;
begin
  // RGB only (alpha ignored), upper-case — e.g. TyRGB(59,130,246) -> '#3B82F6'.
  Result := Format('#%.2X%.2X%.2X', [TyRedOf(AColor), TyGreenOf(AColor), TyBlueOf(AColor)]);
end;

{ Build a solid TTyFill. A standalone function (NOT a method) so Default(TTyFill)
  resolves to the compiler intrinsic — inside a TTyCustomButton descendant's method the
  inherited 'Default' property would shadow it. }
function SolidFill(AColor: TTyColor): TTyFill;
begin
  Result := Default(TTyFill);
  Result.Kind := tfkSolid;
  Result.Color := AColor;
end;

constructor TTyCustomColorButton.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSelectedColor := TyRGB(59, 130, 246);   // $FF3B82F6 — the library accent blue
  FShowText := False;
  FDialogCaption := 'Select Color';
  // Matches the redeclared `Alignment default taLeftJustify`; the two must agree or the
  // streamer writes the property into every .lfm that holds one of these.
  Alignment := taLeftJustify;
end;

function TTyCustomColorButton.GetButtonColor: TColor;
begin
  Result := TyColorToLCL(FSelectedColor);
end;

procedure TTyCustomColorButton.SetButtonColor(AValue: TColor);
begin
  // Keep the current alpha: SelectedColor is ARGB and a TColor carries none, so reading
  // ButtonColor and writing it straight back must not quietly make an opaque swatch
  // transparent (or the reverse).
  SelectedColor := TyColorFromLCL(AValue, TyAlphaOf(FSelectedColor));
end;

procedure TTyCustomColorButton.SetSelectedColor(AValue: TTyColor);
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
  begin
    // Two names, one notification (see OnColorChanged). Ours first, so the ordering is
    // stated rather than left to field-declaration order.
    if Assigned(FOnColorChange) then FOnColorChange(Self);
    if Assigned(FOnColorChanged) then FOnColorChanged(Self);
  end;
end;

procedure TTyCustomColorButton.SetShowText(AValue: Boolean);
begin
  if FShowText = AValue then Exit;
  FShowText := AValue;
  Invalidate;
end;

procedure TTyCustomColorButton.DrawContent(APainter: TTyPainter; const AContentRect: TRect;
  const AStyle: TTyStyleSet);
var
  swatch, capRect: TRect;
  fill: TTyFill;
  cw, gap, radius, mp: Integer;
  borderCol: TTyColor;
  hasText: Boolean;
  disp: string;
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
  { MIRRORING: the swatch leads, so it moves to the right on a right-to-left button and the
    caption follows on its left. Widths are untouched, which is why CalculatePreferredSize
    needs no branch — the same three pieces, in the other order. Direction comes from the
    painter, the same place the caption's alignment came from. No hit test: a colour button
    is one click target that opens the dialog. }
  if APainter.RightToLeft then
    swatch := Rect(AContentRect.Right - cw, AContentRect.Top, AContentRect.Right, AContentRect.Bottom)
  else
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

  // Caption (or, with none, the optional hex) on the far side of the swatch.
  if hasText then
  begin
    if APainter.RightToLeft then
      capRect := Rect(AContentRect.Left, AContentRect.Top, swatch.Left - gap, AContentRect.Bottom)
    else
      capRect := Rect(swatch.Right + gap, AContentRect.Top, AContentRect.Right, AContentRect.Bottom);
    if capRect.Right > capRect.Left then
    begin
      { Through the base's resolver, not raw ContentText: this button's Caption is an
        ordinary button caption, so '&Save' must underline the S here exactly as it does on
        every other button -- and ShowAccelChar must be able to turn that off here too, or
        it would be a published property one descendant quietly ignores. The '#RRGGBB'
        fallback has no '&' and passes through untouched. }
      ResolveCaptionText(disp, mp);
      if Caption = '' then disp := ContentText;   // the hex fallback; no mnemonic in it
      APainter.DrawText(capRect, disp, AStyle.FontName,
        ResolveFontSize(AStyle), AStyle.FontWeight, AStyle.TextColor, Alignment, tlCenter,
        True, TyAccelGatePos(mp));
    end;
  end;
end;

function TTyCustomColorButton.ContentText: string;
begin
  if Caption <> '' then Result := Caption
  else if FShowText then Result := TyColorHex(FSelectedColor)
  else Result := '';
end;

function TTyCustomColorButton.MeasureHexText(APPI: Integer; const AStyle: TTyStyleSet): Integer;
var
  Meas: TBitmap;
  txt: string;
  mp, rw: Integer;
begin
  txt := ContentText;
  if txt = '' then Exit(0);
  // Measure what is DRAWN, not what is stored: with ShowAccelChar on, '&Save' paints as
  // 'Save', and reserving the ampersand's width would leave a gap AutoSize never fills.
  if Caption <> '' then ResolveCaptionText(txt, mp);
  // 与 TTyButton.MeasureCaption 同一套量法(同一个 TyConfigureMeasureFont:字体名回落、
  // 像素字高、粗体阈值都在那里),只是量的字符串换成了真正会被画出来的十六进制色值。
  Meas := TBitmap.Create;
  try
    Meas.SetSize(1, 1);
    TyConfigureMeasureFont(Meas.Canvas, AStyle.FontName, ResolveFontSize(AStyle),
      AStyle.FontWeight, APPI);
    Result := Meas.Canvas.TextWidth(txt);
    { 量法要和 TTyButton.MeasureCaption 一致,就得连它后来补的这一步一起:再问一次渲染器,
      取较大的。画字的是渲染器,它量得宽就按它截断;只按画布量,AutoSize 刚量好的标题会被
      画成 "Try it in the previ..."。 }
    rw := TyMeasureRenderedTextWidth(txt, AStyle.FontName, ResolveFontSize(AStyle),
      AStyle.FontWeight, APPI);
    if rw > Result then Result := rw;
    if Result < 0 then Result := 0;
  finally
    Meas.Free;
  end;
end;

function TTyCustomColorButton.MeasureContentHeight(APPI: Integer): Integer;
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

procedure TTyCustomColorButton.CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
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

procedure TTyCustomColorButton.Click;
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
