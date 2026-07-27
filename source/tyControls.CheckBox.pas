unit tyControls.CheckBox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, LMessages, StdCtrls,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller, tyControls.Accel;
type
  TTyCheckBox = class(TTyCustomControl)
  private
    FState: TCheckBoxState;
    FAllowGrayed: Boolean;
    FRefitting: Boolean;   // guards the AutoSize re-fit in Invalidate against re-entry
    FOnChange: TNotifyEvent;
    function GetChecked: Boolean;
    procedure SetState(const AValue: TCheckBoxState);
    procedure SetChecked(const AValue: Boolean);
  protected
    function GetStyleTypeKey: string; override;
    function CurrentStates: TTyStateSet; override;
    { 控件真正需要的宽度:主题 padding + 指示框 + 间距 + 量出来的标题 —— 也就是 RenderTo
      排的那几段,所以 AutoSize 预留的宽度和实际画出来的宽度不会走偏。没有这个,复选框就
      一直是 .lfm 给的宽度,标题一旦变长(更长的译文、padding 更宽松的皮肤、更重的字体)
      就被省略号截掉。
      注意指示框和间距是主题可调的(--checkbox-size / --checkbox-gap),换皮肤会变,
      所以两边必须读同一个 Metric,不能写死常量。 }
    procedure CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
      WithThemeSpace: Boolean); override;
    { 标题在 APPI 下画出来的尺寸(设备像素),已去掉 & 助记符标记。 }
    procedure MeasureCaption(APPI: Integer; out AWidth, AHeight: Integer);
    { 运行期改 Caption 走这里(CM_TEXTCHANGED);开了 AutoSize 就得按新文字重新量。 }
    procedure TextChanged; override;
    { 换主题是以一个裸 Invalidate 的形式传到控件的,而新主题的字体、padding 和
      --checkbox-size/--checkbox-gap 都可能不同 —— 需要的宽度也就变了,所以
      AutoSize 的复选框必须在这里重新贴合。 }
    procedure Invalidate; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    function DialogChar(var Message: TLMKey): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Click; override;
  published
    { 默认关(设计好的复选框保持 .lfm 给的宽度)。打开后控件会横向撑开,刚好裹住
      指示框 + 间距 + 标题 + 主题 padding,标题变长时是控件变长而不是文字被截。
      高度不参与(见 CalculatePreferredSize):行高是排版方的事,这样放进任何会钉死
      子控件高度的容器里都不会打架。 }
    property AutoSize;
    property State: TCheckBoxState read FState write SetState default cbUnchecked;
    property AllowGrayed: Boolean read FAllowGrayed write FAllowGrayed default False;
    property Checked: Boolean read GetChecked write SetChecked default False;
    property Caption;
    property Enabled;
    property Font;
    { 构造函数把它打开(复选框天然是 tab stop);这里把**声明的默认值**也改成 True,
      是为了让"关掉"这条路走得通 —— 继承来的声明默认值是 False,设计器里设成 False
      就等于默认值,压根不会写进 .lfm,运行时又被构造函数的 True 盖回去。 }
    property TabStop default True;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
    property OnClick;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

  TTyRadioButton = class(TTyCustomControl)
  private
    FChecked: Boolean;
    FGroupIndex: Integer;
    FRefitting: Boolean;   // guards the AutoSize re-fit in Invalidate against re-entry
    FOnChange: TNotifyEvent;
    procedure SetChecked(const AValue: Boolean);
    procedure UncheckSiblings;
  protected
    function GetStyleTypeKey: string; override;
    function CurrentStates: TTyStateSet; override;
    { 与 TTyCheckBox.CalculatePreferredSize 同理,只是指示器读的是 --radio-size /
      --radio-gap 这两个令牌(RenderTo 用的也是它们)。 }
    procedure CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
      WithThemeSpace: Boolean); override;
    { 标题在 APPI 下画出来的尺寸(设备像素),已去掉 & 助记符标记。 }
    procedure MeasureCaption(APPI: Integer; out AWidth, AHeight: Integer);
    { 运行期改 Caption 走这里;开了 AutoSize 就得按新文字重新量。 }
    procedure TextChanged; override;
    { 换主题以裸 Invalidate 的形式到达控件,新主题的字体/padding/指示器令牌都可能不同,
      AutoSize 的单选钮必须在这里重新贴合。见 TTyCheckBox.Invalidate。 }
    procedure Invalidate; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    function DialogChar(var Message: TLMKey): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Click; override;
  published
    { 默认关。打开后控件横向撑开到刚好裹住圆点 + 间距 + 标题 + 主题 padding;
      高度不参与,交给排版方。见 TTyCheckBox.AutoSize。 }
    property AutoSize;
    property Checked: Boolean read FChecked write SetChecked default False;
    property GroupIndex: Integer read FGroupIndex write FGroupIndex default 0;
    property Caption;
    property Enabled;
    property Font;
    // 同 TTyCheckBox:声明的默认值必须和构造函数一致,否则 .lfm 里关不掉。
    property TabStop default True;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
    property OnClick;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;
implementation

{ TTyCheckBox }

constructor TTyCheckBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TyAccelRegister(Self);
  TabStop := True;
  Width := 130;
  Height := TyDensityHeight(ActiveController, 22);
end;

destructor TTyCheckBox.Destroy;
begin
  TyAccelUnregister(Self);
  inherited Destroy;
end;

function TTyCheckBox.DialogChar(var Message: TLMKey): Boolean;
begin
  if Enabled and TyIsAccelKey(Message, Caption) then
  begin
    if CanFocus then SetFocus;
    Click;
    Exit(True);
  end;
  Result := inherited DialogChar(Message);
end;

function TTyCheckBox.GetStyleTypeKey: string;
begin
  Result := 'TyCheckBox';
end;

function TTyCheckBox.CurrentStates: TTyStateSet;
begin
  // A checked checkbox enters tysActive so the theme's :active rule (accent box
  // fill + white glyph) actually resolves. The :active 'color' would whiten the
  // CAPTION too, so RenderTo resolves the caption text from a separate
  // active-free state set — keeping the accent + white-glyph effect box-only.
  Result := inherited CurrentStates;
  if (FState in [cbChecked, cbGrayed]) and Enabled then
    Include(Result, tysActive);
end;

procedure TTyCheckBox.SetState(const AValue: TCheckBoxState);
begin
  if FState = AValue then Exit;
  FState := AValue;
  Invalidate;
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TTyCheckBox.SetChecked(const AValue: Boolean);
begin
  if AValue then SetState(cbChecked) else SetState(cbUnchecked);
end;

function TTyCheckBox.GetChecked: Boolean;
begin
  Result := FState = cbChecked;
end;

procedure TTyCheckBox.Click;
begin
  if not Enabled then Exit;
  if FAllowGrayed then
    case FState of
      cbUnchecked: SetState(cbChecked);
      cbChecked:   SetState(cbGrayed);
      cbGrayed:    SetState(cbUnchecked);
    end
  else
    SetChecked(FState <> cbChecked);
  inherited Click;
end;

procedure TTyCheckBox.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if not Enabled then Exit;
  inherited KeyDown(Key, Shift);
  if Key = VK_SPACE then
  begin
    Click;
    Key := 0;
  end;
end;

procedure TTyCheckBox.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, FrameS, CaptionS: TTyStyleSet;
  ContentRect, BoxRect, TextRect, FullRect: TRect;
  BoxSize, Gap: Integer;
  disp: string;
  mp: Integer;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    // S drives the BOX (and its glyph): when checked it carries tysActive so the
    // :active accent fill + white glyph resolve. CaptionS is resolved WITHOUT the
    // checked-derived tysActive so the :active 'color:#FFFFFF' never whitens the
    // caption text — keeping the accent + white-glyph effect box-only.
    S := CurrentStyle;
    CaptionS := ActiveController.Model.ResolveStyle(
      GetStyleTypeKey, StyleClass, CurrentStates - [tysActive]);
    // DrawFrame propagates opacity (and shadow) for the whole control, but the
    // theme's background/border style the small BOX, not the control rect —
    // so the frame copy clears them to keep the v1 transparent look.
    FrameS := S;
    FrameS.Background := Default(TTyFill);
    FrameS.BorderWidth := 0;
    // Use a (0,0)-local rect: the painter builds a (W x H) bitmap and blits it
    // at ARect.Left/Top, so a non-zero ARect origin would shift/clip the frame.
    FullRect := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    DrawFrame(P, FullRect, FrameS);
    ContentRect := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    // Inset content rect by all four padding sides
    ContentRect := Rect(
      ContentRect.Left   + P.Scale(S.Padding.Left),
      ContentRect.Top    + P.Scale(S.Padding.Top),
      ContentRect.Right  - P.Scale(S.Padding.Right),
      ContentRect.Bottom - P.Scale(S.Padding.Bottom)
    );
    // v3/C: box size + caption gap are skin-tunable metrics (default = the built-in constants).
    BoxSize := P.Scale(ActiveController.Metric('--checkbox-size', TyCheckBoxBox));
    Gap := P.Scale(ActiveController.Metric('--checkbox-gap', TyCheckBoxGap));
    BoxRect := Rect(ContentRect.Left,
      ContentRect.Top + ((ContentRect.Bottom - ContentRect.Top - BoxSize) div 2),
      ContentRect.Left + BoxSize,
      ContentRect.Top + ((ContentRect.Bottom - ContentRect.Top - BoxSize) div 2) + BoxSize);
    P.FillBackground(BoxRect, S.Background, S.BorderRadius);
    P.StrokeBorder(BoxRect, S.BorderRadius, S.BorderWidth, S.BorderColor);
    // v3/C5: the check/indeterminate glyph is theme-overridable with an icon-font codepoint.
    case FState of
      cbChecked: TyDrawGlyph(P, ActiveController, BoxRect, '--glyph-check', tgCheck, S.TextColor, 2);
      cbGrayed:  TyDrawGlyph(P, ActiveController, BoxRect, '--glyph-check-indeterminate', tgCheckIndeterminate, S.TextColor, 2);
    end;
    TextRect := Rect(BoxRect.Right + Gap, ContentRect.Top,
      ContentRect.Right, ContentRect.Bottom);
    TyParseMnemonic(Caption, disp, mp);
    P.DrawText(TextRect, disp, S.FontName, ResolveFontSize(S), S.FontWeight,
      CaptionS.TextColor, taLeftJustify, tlCenter, True, TyAccelGatePos(mp));
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyCheckBox.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

procedure TTyCheckBox.MeasureCaption(APPI: Integer; out AWidth, AHeight: Integer);
var
  S: TTyStyleSet;
  Meas: TBitmap;
  disp: string;
  mp: Integer;
begin
  // RenderTo 画标题用的是 S(盒子那份样式)的字体,CaptionS 只提供墨色 —— 所以这里也
  // 必须用 S 量,否则 :active 一旦带了自己的字体,量出来的和画出来的就对不上。
  S := CurrentStyle;
  // & 标记画成下划线,不是字符,所以不能算进宽度里。
  TyParseMnemonic(Caption, disp, mp);
  Meas := TBitmap.Create;
  try
    Meas.SetSize(1, 1);
    Meas.Canvas.Font.Name := TyEffectiveFontName(S.FontName);
    Meas.Canvas.Font.Size := MulDiv(ResolveFontSize(S), APPI, 96);
    if S.FontWeight >= 600 then
      Meas.Canvas.Font.Style := [fsBold]
    else
      Meas.Canvas.Font.Style := [];
    AWidth := Meas.Canvas.TextWidth(disp);
    // 用固定的参考字形取行高:标题为空时也仍然是一行的高度。
    AHeight := Meas.Canvas.TextHeight('Ag');
    if AWidth < 0 then AWidth := 0;
    if AHeight < 1 then AHeight := 1;
  finally
    Meas.Free;
  end;
end;

procedure TTyCheckBox.CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
  WithThemeSpace: Boolean);
var
  S: TTyStyleSet;
  ppi, tw, th, boxSize, gap: Integer;
begin
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  S := CurrentStyle;
  MeasureCaption(ppi, tw, th);
  // 和 RenderTo 完全一样的两个主题令牌(P.Scale 就是 MulDiv(x, ppi, 96)),所以预留的
  // 指示框宽度和真正画出来的那一块是同一个数。
  boxSize := MulDiv(ActiveController.Metric('--checkbox-size', TyCheckBoxBox), ppi, 96);
  gap := MulDiv(ActiveController.Metric('--checkbox-gap', TyCheckBoxGap), ppi, 96);
  if boxSize < 0 then boxSize := 0;
  if gap < 0 then gap := 0;
  // RenderTo 的排布:padding.Left | 指示框 | gap | 标题 | padding.Right。
  PreferredWidth := MulDiv(S.Padding.Left + S.Padding.Right, ppi, 96) + boxSize + gap + tw;
  if PreferredWidth < 1 then PreferredWidth := 1;
  { 只管宽度 —— 0 是 LCL 的"这个轴上没有意见",高度保持原样。控件横向长出来去装更长的
    标题,高度则是排版决定的,归摆这一行的人管。连高度一起提议会让控件跟任何钉死高度的
    容器打架:TTyToolBar 把每个子控件都设成自己的 ButtonHeight,子控件却要另一个高度,
    两边来回弹到 LCL 抛 "TControl.ChangeBounds loop detected"。需要标题自然高度的调用方
    可以自己用 MeasureCaption 加上样式的上下 padding 算。 }
  PreferredHeight := 0;
end;

procedure TTyCheckBox.TextChanged;
begin
  inherited TextChanged;
  // 新标题需要的宽度变了,AutoSize 的控件得重新贴合。
  if AutoSize then
  begin
    InvalidatePreferredSize;
    AdjustSize;
  end;
  Invalidate;
end;

procedure TTyCheckBox.Invalidate;
begin
  inherited Invalidate;
  { 换主题时 TTyStyleController 给每个注册控件广播一个裸 Invalidate,而新主题的字体、
    padding 和 --checkbox-size/--checkbox-gap 都可能不同 —— AutoSize 需要的宽度也就跟着
    变了。不在这里重新量,控件就留着旧皮肤的宽度,标题被省略号截掉(TTyButton 的工具条
    按钮当初换到 antdesign 皮肤时就是这个症状)。
    FRefitting 挡住重入:AdjustSize -> SetBounds -> Invalidate 会绕回来。 }
  if AutoSize and not FRefitting and not (csDestroying in ComponentState) then
  begin
    FRefitting := True;
    try
      InvalidatePreferredSize;
      AdjustSize;
    finally
      FRefitting := False;
    end;
  end;
end;

{ TTyRadioButton }

constructor TTyRadioButton.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TyAccelRegister(Self);
  TabStop := True;
  Width := 130;
  Height := TyDensityHeight(ActiveController, 22);
end;

destructor TTyRadioButton.Destroy;
begin
  TyAccelUnregister(Self);
  inherited Destroy;
end;

function TTyRadioButton.DialogChar(var Message: TLMKey): Boolean;
begin
  if Enabled and TyIsAccelKey(Message, Caption) then
  begin
    if CanFocus then SetFocus;
    Click;
    Exit(True);
  end;
  Result := inherited DialogChar(Message);
end;

function TTyRadioButton.GetStyleTypeKey: string;
begin
  Result := 'TyRadioButton';
end;

function TTyRadioButton.CurrentStates: TTyStateSet;
begin
  // See TTyCheckBox.CurrentStates: checked -> tysActive so :active accent fill +
  // white dot resolve; the caption text is resolved active-free in RenderTo so
  // the accent/white stays confined to the box (dot).
  Result := inherited CurrentStates;
  if FChecked and Enabled then
    Include(Result, tysActive);
end;

procedure TTyRadioButton.SetChecked(const AValue: Boolean);
begin
  if FChecked = AValue then Exit;
  FChecked := AValue;
  if FChecked then
    UncheckSiblings;          // each unchecked sibling routes through its own
                             // SetChecked, so it fires ITS OnChange + Invalidates
  Invalidate;
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TTyRadioButton.UncheckSiblings;
var
  I: Integer;
  Sib: TControl;
begin
  if Parent = nil then Exit;
  for I := 0 to Parent.ControlCount - 1 do
  begin
    Sib := Parent.Controls[I];
    if (Sib <> Self) and (Sib is TTyRadioButton)
       and (TTyRadioButton(Sib).GroupIndex = FGroupIndex) then
      TTyRadioButton(Sib).SetChecked(False);
  end;
end;

procedure TTyRadioButton.Click;
begin
  if not Enabled then Exit;
  SetChecked(True);
  inherited Click;
end;

procedure TTyRadioButton.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if not Enabled then Exit;
  inherited KeyDown(Key, Shift);
  if Key = VK_SPACE then
  begin
    Click;
    Key := 0;
  end;
end;

procedure TTyRadioButton.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, FrameS, CaptionS: TTyStyleSet;
  ContentRect, DotRect, TextRect, FullRect: TRect;
  BoxSize, Gap, DotRadiusLogical: Integer;
  disp: string;
  mp: Integer;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    // S drives the dot box (+ its glyph): checked -> tysActive -> :active accent
    // fill + white dot. CaptionS is resolved WITHOUT the checked-derived tysActive
    // so the caption text colour stays normal (box-only). See TTyCheckBox.RenderTo.
    S := CurrentStyle;
    CaptionS := ActiveController.Model.ResolveStyle(
      GetStyleTypeKey, StyleClass, CurrentStates - [tysActive]);
    // See TTyCheckBox.RenderTo: frame copy clears background/border so the
    // theme's box styling doesn't paint a control-wide fill or outline.
    FrameS := S;
    FrameS.Background := Default(TTyFill);
    FrameS.BorderWidth := 0;
    // Use a (0,0)-local rect (see TTyCheckBox.RenderTo) so a non-zero ARect
    // origin doesn't shift/clip the frame within the painter's local bitmap.
    FullRect := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    DrawFrame(P, FullRect, FrameS);
    ContentRect := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    // Inset content rect by all four padding sides
    ContentRect := Rect(
      ContentRect.Left   + P.Scale(S.Padding.Left),
      ContentRect.Top    + P.Scale(S.Padding.Top),
      ContentRect.Right  - P.Scale(S.Padding.Right),
      ContentRect.Bottom - P.Scale(S.Padding.Bottom)
    );
    // v3/C: radio indicator size + caption gap are skin-tunable (default = the built-in constants).
    BoxSize := P.Scale(ActiveController.Metric('--radio-size', TyCheckBoxBox));
    Gap := P.Scale(ActiveController.Metric('--radio-gap', TyCheckBoxGap));
    DotRect := Rect(ContentRect.Left,
      ContentRect.Top + ((ContentRect.Bottom - ContentRect.Top - BoxSize) div 2),
      ContentRect.Left + BoxSize,
      ContentRect.Top + ((ContentRect.Bottom - ContentRect.Top - BoxSize) div 2) + BoxSize);
    // FillBackground/StrokeBorder take a LOGICAL radius (they Scale() internally),
    // so cap the token (S.BorderRadius, logical) against the dot's LOGICAL half-side.
    // The dot box is P.Scale(TyCheckBoxBox) device wide → logical half = MulDiv(BoxSize,96,APPI) div 2,
    // which is 8 at 96ppi. Default TyRadioButton border-radius:8px → Min(8,8)=8 → circle
    // unchanged; only a SMALLER theme radius squares the corners.
    DotRadiusLogical := TyClampRadius(S.BorderRadius, MulDiv(BoxSize, 96, APPI) div 2);
    P.FillBackground(DotRect, S.Background, DotRadiusLogical);
    P.StrokeBorder(DotRect, DotRadiusLogical, S.BorderWidth, S.BorderColor);
    if FChecked then
      TyDrawGlyph(P, ActiveController, DotRect, '--glyph-radio', tgRadioDot, S.TextColor, 2);
    TextRect := Rect(DotRect.Right + Gap, ContentRect.Top,
      ContentRect.Right, ContentRect.Bottom);
    TyParseMnemonic(Caption, disp, mp);
    P.DrawText(TextRect, disp, S.FontName, ResolveFontSize(S), S.FontWeight,
      CaptionS.TextColor, taLeftJustify, tlCenter, True, TyAccelGatePos(mp));
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyRadioButton.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

procedure TTyRadioButton.MeasureCaption(APPI: Integer; out AWidth, AHeight: Integer);
var
  S: TTyStyleSet;
  Meas: TBitmap;
  disp: string;
  mp: Integer;
begin
  // 见 TTyCheckBox.MeasureCaption:字体取自 S(圆点那份样式),CaptionS 只给墨色。
  S := CurrentStyle;
  TyParseMnemonic(Caption, disp, mp);   // & 画成下划线,不占宽度
  Meas := TBitmap.Create;
  try
    Meas.SetSize(1, 1);
    Meas.Canvas.Font.Name := TyEffectiveFontName(S.FontName);
    Meas.Canvas.Font.Size := MulDiv(ResolveFontSize(S), APPI, 96);
    if S.FontWeight >= 600 then
      Meas.Canvas.Font.Style := [fsBold]
    else
      Meas.Canvas.Font.Style := [];
    AWidth := Meas.Canvas.TextWidth(disp);
    AHeight := Meas.Canvas.TextHeight('Ag');
    if AWidth < 0 then AWidth := 0;
    if AHeight < 1 then AHeight := 1;
  finally
    Meas.Free;
  end;
end;

procedure TTyRadioButton.CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
  WithThemeSpace: Boolean);
var
  S: TTyStyleSet;
  ppi, tw, th, boxSize, gap: Integer;
begin
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  S := CurrentStyle;
  MeasureCaption(ppi, tw, th);
  // RenderTo 用的就是这两个令牌;单选钮有自己的一套(--radio-*),别借复选框的。
  boxSize := MulDiv(ActiveController.Metric('--radio-size', TyCheckBoxBox), ppi, 96);
  gap := MulDiv(ActiveController.Metric('--radio-gap', TyCheckBoxGap), ppi, 96);
  if boxSize < 0 then boxSize := 0;
  if gap < 0 then gap := 0;
  // RenderTo 的排布:padding.Left | 圆点 | gap | 标题 | padding.Right。
  PreferredWidth := MulDiv(S.Padding.Left + S.Padding.Right, ppi, 96) + boxSize + gap + tw;
  if PreferredWidth < 1 then PreferredWidth := 1;
  { 只管宽度,高度交给排版方 —— 理由见 TTyCheckBox.CalculatePreferredSize。 }
  PreferredHeight := 0;
end;

procedure TTyRadioButton.TextChanged;
begin
  inherited TextChanged;
  if AutoSize then
  begin
    InvalidatePreferredSize;
    AdjustSize;
  end;
  Invalidate;
end;

procedure TTyRadioButton.Invalidate;
begin
  inherited Invalidate;
  { 见 TTyCheckBox.Invalidate:换主题是一个裸 Invalidate,新主题的字体/padding/指示器
    令牌都变了,AutoSize 必须在这里重新贴合;FRefitting 挡住
    AdjustSize -> SetBounds -> Invalidate 的重入。 }
  if AutoSize and not FRefitting and not (csDestroying in ComponentState) then
  begin
    FRefitting := True;
    try
      InvalidatePreferredSize;
      AdjustSize;
    finally
      FRefitting := False;
    end;
  end;
end;

end.
