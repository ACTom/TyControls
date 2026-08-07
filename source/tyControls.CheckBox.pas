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
    FAlignment: TLeftRight;
    FRefitting: Boolean;   // guards the AutoSize re-fit in Invalidate against re-entry
    FOnChange: TNotifyEvent;
    function GetChecked: Boolean;
    procedure SetState(const AValue: TCheckBoxState);
    procedure SetChecked(const AValue: Boolean);
    procedure SetAlignment(const AValue: TLeftRight);
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
    { 把控件钳住,让它永远不会小于自己必须画出来的东西。主题的 --control-height 和 .lfm 里
      写死的 Height 都只是**请求**;真正可能的尺寸由字体、padding 和指示框尺寸决定,而这三样
      只有控件自己同时知道。Linux/Qt6 上同一句 9pt 中文标题走的是另一张回退字体,墨迹比
      Windows 高,DrawText 又是 tlCenter + 裁剪画的 —— 盒子比墨迹矮一像素,少掉的就是**底部**。
      刻意用 Constraints,而不是 CalculatePreferredSize 的高度:提议高度等于让控件跟父容器
      谈判,TTyButton 当初就是这么在 TTyToolBar 上和 ButtonHeight 来回弹,直到 LCL 抛
      "ChangeBounds loop detected" 把 demo 在启动时弄死的。Constraints 是在 SetBounds 内部
      直接钳,不谈判 —— 只要容器要的高度本身放得下,高度就还是容器说了算。

      覆盖基类钩子而不是自立门户:基类的 UpdateSizeConstraints 是带守卫的入口,LCL 的跨屏
      DPI 流程正在缩放同一份 Constraints 时,它会挡住这里的重算(见 tyControls.Base.pas)。
      没有那道守卫,一次 100%->250% 就把系数应用了两遍,来回一趟后高度停在 60px 回不去。 }
    procedure DoUpdateSizeConstraints; override;
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
    { 指示框在标题的哪一侧。名字、类型和默认值都照 LCL 抄
      (TCustomCheckBox.Alignment: TLeftRight default taRightJustify,stdctrls.pp:1358)。

      注意这个名字在 LCL 里说的**不是**标题的对齐方式:taRightJustify(默认)= 指示框在
      左、标题在右,也就是一直以来的样子;taLeftJustify = 指示框挪到**右边**,标题靠着它
      右对齐(LCL 靠 BS_RIGHTBUTTON 实现,include/customcheckbox.inc:269-274)。
      同名不同义正是这一轮在清的那类坑,所以这里既没有借用 TTyGroupBox.Alignment 的
      TAlignment(那个是标题对齐,另一件事),也没有自己发明一套语义。

      宽度两种摆法完全一样(padding + 指示框 + gap + 标题),所以 CalculatePreferredSize
      不用分支。 }
    property Alignment: TLeftRight read FAlignment write SetAlignment default taRightJustify;
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
    FAlignment: TLeftRight;
    FRefitting: Boolean;   // guards the AutoSize re-fit in Invalidate against re-entry
    FOnChange: TNotifyEvent;
    procedure SetChecked(const AValue: Boolean);
    procedure SetAlignment(const AValue: TLeftRight);
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
    { 尺寸地板,理由见 TTyCheckBox.DoUpdateSizeConstraints;圆点读的是自己的 --radio-size。 }
    procedure DoUpdateSizeConstraints; override;
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
    { 圆点在标题的哪一侧 —— 见 TTyCheckBox.Alignment,同名同型同默认值
      (LCL 在 TRadioButton 上转发的是同一个 TCustomCheckBox.Alignment)。 }
    property Alignment: TLeftRight read FAlignment write SetAlignment default taRightJustify;
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
  FAlignment := taRightJustify;   // indicator left, caption right — LCL's default
  Width := 130;
  Height := TyDensityHeight(ActiveController, 22);
end;

procedure TTyCheckBox.SetAlignment(const AValue: TLeftRight);
begin
  if FAlignment = AValue then Exit;
  FAlignment := AValue;
  Invalidate;
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
  BoxSize, Gap, BoxTop: Integer;
  TextAlign, SideAlign: TAlignment;
  disp: string;
  mp: Integer;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI, IsRightToLeft);
    { MIRRORING. The switch was already here -- Alignment has moved the indicator to the
      other side and re-hugged the caption since that property landed -- so all right-to-left
      does is decide which way the switch points. SideAlign is the PHYSICAL side; FAlignment
      is untouched, because RTL overrides the effective side for one frame and never rewrites
      what the author wrote (LCL does the same: grids.pas:4006 flips a column's own alignment
      at paint time, checklst.pas:199 flips the check side unconditionally). }
    SideAlign := BidiFlipAlignment(FAlignment, IsRightToLeft);
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
    BoxTop := ContentRect.Top + ((ContentRect.Bottom - ContentRect.Top - BoxSize) div 2);
    // Alignment picks the SIDE the indicator sits on; see the property. Vertical centring
    // and every size are identical either way, so only the two X coordinates branch.
    if SideAlign = taLeftJustify then
      BoxRect := Rect(ContentRect.Right - BoxSize, BoxTop, ContentRect.Right, BoxTop + BoxSize)
    else
      BoxRect := Rect(ContentRect.Left, BoxTop, ContentRect.Left + BoxSize, BoxTop + BoxSize);
    P.FillBackground(BoxRect, S.Background, S.BorderRadius);
    P.StrokeBorder(BoxRect, S.BorderRadius, S.BorderWidth, S.BorderColor);
    // v3/C5: the check/indeterminate glyph is theme-overridable with an icon-font codepoint.
    case FState of
      cbChecked: TyDrawGlyph(P, ActiveController, BoxRect, '--glyph-check', tgCheck, S.TextColor, 2);
      cbGrayed:  TyDrawGlyph(P, ActiveController, BoxRect, '--glyph-check-indeterminate', tgCheckIndeterminate, S.TextColor, 2);
    end;
    // The caption takes the strip left over, hugging the indicator from whichever side it
    // is on — so the pair reads as one unit at either alignment instead of drifting apart.
    // The strip is a PHYSICAL rect, so it follows SideAlign; TextAlign is a LOGICAL one the
    // painter resolves (it was armed with the same flag), so it follows FAlignment and is
    // exactly the line it always was. Both readings agree because "hug the indicator" is
    // direction-free: the caption sits on the indicator's inner side either way round.
    if SideAlign = taLeftJustify then
    begin
      TextRect := Rect(ContentRect.Left, ContentRect.Top, BoxRect.Left - Gap, ContentRect.Bottom);
      if TextRect.Right < TextRect.Left then TextRect.Right := TextRect.Left;
    end
    else
      TextRect := Rect(BoxRect.Right + Gap, ContentRect.Top, ContentRect.Right, ContentRect.Bottom);
    if FAlignment = taLeftJustify then
      TextAlign := taRightJustify
    else
      TextAlign := taLeftJustify;
    TyParseMnemonic(Caption, disp, mp);
    P.DrawText(TextRect, disp, S.FontName, ResolveFontSize(S), S.FontWeight,
      CaptionS.TextColor, TextAlign, tlCenter, True, TyAccelGatePos(mp));
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

procedure TTyCheckBox.DoUpdateSizeConstraints;
var
  S: TTyStyleSet;
  ppi, tw, th, padH, boxSize, prefW, prefH, minH: Integer;
begin
  if csDestroying in ComponentState then Exit;
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  S := CurrentStyle;
  { 宽度直接问 CalculatePreferredSize —— 那里已经是 RenderTo 的排布
    (padding.Left | 指示框 | gap | 标题 | padding.Right)。在这里把同一条式子再抄一遍,
    就是给"预留的"和"画出来的"留下走偏的机会。 }
  prefW := 0;
  prefH := 0;
  CalculatePreferredSize(prefW, prefH, True);
  { 高度只能自己算:CalculatePreferredSize 在这个轴上故意不表态(见那里的注释)。
    RenderTo 把标题画进上下 padding 之间,tlCenter + 裁剪 —— 这段比墨迹矮一像素,少的就是
    底部那一行。指示框是按控件中线摆的(它可以占用 padding,一直如此),所以它只要求控件
    本身别比它矮;两者取大的那个。 }
  MeasureCaption(ppi, tw, th);
  padH := MulDiv(S.Padding.Top + S.Padding.Bottom, ppi, 96);
  boxSize := MulDiv(ActiveController.Metric('--checkbox-size', TyCheckBoxBox), ppi, 96);
  minH := th + padH;
  if boxSize > minH then minH := boxSize;
  Constraints.MinWidth := prefW;
  Constraints.MinHeight := minH;
end;

procedure TTyCheckBox.TextChanged;
begin
  inherited TextChanged;
  // 标题换了,它需要的地板也就换了(空标题也仍然是一行的高度)。
  UpdateSizeConstraints;
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
    地板同理,而且和 AutoSize 无关:主题决定字体、padding 和指示框尺寸,换主题就换了地板,
    所以它在 AutoSize 之外也要更新。
    FRefitting 挡住重入:AdjustSize -> SetBounds -> Invalidate 会绕回来。 }
  if not FRefitting and not (csDestroying in ComponentState) then
  begin
    FRefitting := True;
    try
      UpdateSizeConstraints;
      if AutoSize then
      begin
        InvalidatePreferredSize;
        AdjustSize;
      end;
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
  FAlignment := taRightJustify;   // dot left, caption right — LCL's default
  Width := 130;
  Height := TyDensityHeight(ActiveController, 22);
end;

procedure TTyRadioButton.SetAlignment(const AValue: TLeftRight);
begin
  if FAlignment = AValue then Exit;
  FAlignment := AValue;
  Invalidate;
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
  BoxSize, Gap, DotRadiusLogical, DotTop: Integer;
  TextAlign, SideAlign: TAlignment;
  disp: string;
  mp: Integer;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI, IsRightToLeft);
    // MIRRORING: see TTyCheckBox.RenderTo -- same switch, same two readings of Alignment.
    SideAlign := BidiFlipAlignment(FAlignment, IsRightToLeft);
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
    DotTop := ContentRect.Top + ((ContentRect.Bottom - ContentRect.Top - BoxSize) div 2);
    // See TTyCheckBox.RenderTo: Alignment picks the SIDE, nothing else changes.
    if SideAlign = taLeftJustify then
      DotRect := Rect(ContentRect.Right - BoxSize, DotTop, ContentRect.Right, DotTop + BoxSize)
    else
      DotRect := Rect(ContentRect.Left, DotTop, ContentRect.Left + BoxSize, DotTop + BoxSize);
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
    // Physical strip from SideAlign, logical text alignment from FAlignment -- see
    // TTyCheckBox.RenderTo for why the two branch conditions differ on purpose.
    if SideAlign = taLeftJustify then
    begin
      TextRect := Rect(ContentRect.Left, ContentRect.Top, DotRect.Left - Gap, ContentRect.Bottom);
      if TextRect.Right < TextRect.Left then TextRect.Right := TextRect.Left;
    end
    else
      TextRect := Rect(DotRect.Right + Gap, ContentRect.Top, ContentRect.Right, ContentRect.Bottom);
    if FAlignment = taLeftJustify then
      TextAlign := taRightJustify
    else
      TextAlign := taLeftJustify;
    TyParseMnemonic(Caption, disp, mp);
    P.DrawText(TextRect, disp, S.FontName, ResolveFontSize(S), S.FontWeight,
      CaptionS.TextColor, TextAlign, tlCenter, True, TyAccelGatePos(mp));
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

procedure TTyRadioButton.DoUpdateSizeConstraints;
{ 见 TTyCheckBox.DoUpdateSizeConstraints —— 同一套推导,只是圆点读的是 --radio-size。 }
var
  S: TTyStyleSet;
  ppi, tw, th, padH, dotSize, prefW, prefH, minH: Integer;
begin
  if csDestroying in ComponentState then Exit;
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  S := CurrentStyle;
  prefW := 0;
  prefH := 0;
  CalculatePreferredSize(prefW, prefH, True);
  MeasureCaption(ppi, tw, th);
  padH := MulDiv(S.Padding.Top + S.Padding.Bottom, ppi, 96);
  dotSize := MulDiv(ActiveController.Metric('--radio-size', TyCheckBoxBox), ppi, 96);
  minH := th + padH;
  if dotSize > minH then minH := dotSize;
  Constraints.MinWidth := prefW;
  Constraints.MinHeight := minH;
end;

procedure TTyRadioButton.TextChanged;
begin
  inherited TextChanged;
  UpdateSizeConstraints;   // 标题换了,地板也换了
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
    令牌都变了,地板要跟着动(与 AutoSize 无关),AutoSize 还要重新贴合;FRefitting 挡住
    AdjustSize -> SetBounds -> Invalidate 的重入。 }
  if not FRefitting and not (csDestroying in ComponentState) then
  begin
    FRefitting := True;
    try
      UpdateSizeConstraints;
      if AutoSize then
      begin
        InvalidatePreferredSize;
        AdjustSize;
      end;
    finally
      FRefitting := False;
    end;
  end;
end;

end.
