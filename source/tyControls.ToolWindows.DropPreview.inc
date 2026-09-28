{ tyControls.ToolWindows 的一部分(include 进来的一段,不是单元):隐藏侧栏的放置预览(spec §9.8,E 期)——
  栏这一侧(推导预览的宽和位置、显示 / 收起、擦除色)和预览控件 TTyToolWindowDropPreview 本身。
  拆出来只是为了主单元短一点:预览要读栏的私有成员(PPI、Placement 的推导),栏的类型声明里又有
  预览的字段,拆成单元会互相引用,所以用 include。 }

{ --- TTyToolWindowBar:放置预览 ------------------------------------------------- }

function TTyToolWindowBar.ShownAxisPx: Integer;
begin
  FAssumeShown := True;
  try
    Result := DerivedAxisPx(Metrics);
  finally
    FAssumeShown := False;
  end;
end;

function TTyToolWindowBar.DropPreviewRect: TRect;
var
  p: TWinControl;
  r: TRect;
  w: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  p := Parent;
  if (p = nil) or not HiddenAsEmpty then Exit;
  w := ShownAxisPx;
  if w <= 0 then Exit;
  { 从栏此刻的位置(宽 0,Left / Top / Height 是它出现时的位置)向编辑区一侧展开。 }
  if FPlacement = twpRight then
    Result := Rect(Left + Width - w, Top, Left + Width, Top + Height)
  else
    Result := Rect(Left, Top, Left + w, Top + Height);
  { 钳进父控件调整后的客户区。 }
  r := p.ClientRect;
  TWinControlAccess(p).AdjustClientRect(r);
  if not Types.IntersectRect(Result, Result, r) then Result := Rect(0, 0, 0, 0);
end;

procedure TTyToolWindowBar.ShowDropPreview;
var
  r: TRect;
  c: TColor;
begin
  if [csLoading, csDestroying] * ComponentState <> [] then Exit;
  r := DropPreviewRect;
  if IsRectEmpty(r) then
  begin
    HideDropPreview;
    Exit;
  end;
  if FDropPreview = nil then FDropPreview := TTyToolWindowDropPreview.CreateFor(Self);
  FDropPreview.Controller := Controller;
  { 窗口化控件擦除时先铺自己的 Color([[windowed-ghost-erases-to-parent-color]]):设成栏的底色,
    显示那一瞬间不闪一块父控件的颜色。 }
  if DropPreviewEraseColor(r, c) then FDropPreview.Color := c;
  { 已经显示着(拖动中重新摆一次:栏换了父控件、父控件改了尺寸)就保留亮不亮 —— 亮是 manager
    的落点给的,落点没变它不会再来设一次。 }
  if not FDropPreview.Visible then FDropPreview.Hot := False;
  { 每次都设:栏可能换过父控件。 }
  FDropPreview.Parent := Parent;
  FDropPreview.BoundsRect := r;
  FDropPreview.Visible := True;
  FDropPreview.BringToFront;
end;

function TTyToolWindowBar.DropPreviewEraseColor(const ARect: TRect; out AColor: TColor): Boolean;

  function FromKey(const AKey: string): Boolean;
  var
    S: TTyStyleSet;
  begin
    Result := False;
    S := ActiveController.Model.ResolveStyle(AKey, TyStyleClassFor(Self, StyleClass), [tysNormal]);
    if not (tpBackground in S.Present)
       or not (S.Background.Kind in [tfkSolid, tfkLinearGradient]) then Exit;
    { 渐变取两端的中间色(近似正中那一点 —— 离整块最远的那一点误差最小,同 Base 里
      TyFillCentreColor 的理由;擦除色只在显示那一瞬间露面,不用逐位对上画出来的那一条)。 }
    if S.Background.Kind = tfkSolid then
      AColor := TyColorToLCL(S.Background.Color)
    else
      AColor := TyColorToLCL(TyMix(S.Background.GradFrom, S.Background.GradTo, 50));
    Result := True;
  end;

begin
  { 栏的底色(纯色 / 渐变);图片、九宫格皮肤给不出一个颜色,退到图标条的底色 —— 同一条栏上
    另一块大面积的底;都给不出就不设(擦成父控件的颜色,之后预览自己整块铺满)。 }
  AColor := clNone;
  Result := FromKey(TyToolWindowBarKey) or FromKey(TyToolWindowStripKey);
end;

procedure TTyToolWindowBar.HideDropPreview;
begin
  if FDropPreview = nil then Exit;
  FDropPreview.Hot := False;
  FDropPreview.Visible := False;
end;

procedure TTyToolWindowBar.SetDropPreviewHot(AOn: Boolean);
begin
  if (FDropPreview <> nil) and FDropPreview.Visible then FDropPreview.Hot := AOn;
end;

{ --- TTyToolWindowDropPreview ---------------------------------------------------- }

constructor TTyToolWindowDropPreview.CreateFor(ABar: TTyToolWindowBar);
begin
  inherited Create(nil);
  FBar := ABar;
  ControlStyle := ControlStyle + [csNoFocus, csNoDesignVisible, csOpaque] - [csAcceptsControls];
  TabStop := False;
  Align := alNone;
  Visible := False;
end;

function TTyToolWindowDropPreview.GetStyleTypeKey: string;
begin
  Result := TyToolWindowDropZoneKey;
end;

procedure TTyToolWindowDropPreview.SetHot(AValue: Boolean);
begin
  if FHot = AValue then Exit;
  FHot := AValue;
  Invalidate;
end;

procedure TTyToolWindowDropPreview.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  R, tr: TRect;
  barS, zoneS: TTyStyleSet;
  cls, txt: string;
  rtl: Boolean;
  pad: Integer;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    rtl := (FBar <> nil) and FBar.IsRightToLeft;
    P.BeginPaint(ACanvas, ARect, APPI, rtl);
    if FBar <> nil then cls := TyStyleClassFor(FBar, FBar.StyleClass)
    else cls := '';
    { 1. 栏的底色:预览是不透明的子窗口,DropZone 的底色带透明度,叠在它上面才是「栏的颜色
      淡淡地提亮一层」。 }
    barS := ActiveController.Model.ResolveStyle(TyToolWindowBarKey, cls, [tysNormal]);
    if tpBackground in barS.Present then P.FillBackground(R, barS.Background, 0);
    { 2. DropZone 的底色和边框;Hot = :hover。 }
    if FHot then
      zoneS := ActiveController.Model.ResolveStyle(TyToolWindowDropZoneKey, cls, [tysHover])
    else
      zoneS := ActiveController.Model.ResolveStyle(TyToolWindowDropZoneKey, cls, [tysNormal]);
    TyDrawFrameUnderlay(P, R, zoneS);
    TyDrawFrameChrome(Self, P, R, zoneS);
    { 3. 正中一行文字。 }
    if (FBar <> nil) and (FBar.Placement = twpRight) then txt := rsTyToolWindowDropRight
    else txt := rsTyToolWindowDropLeft;
    pad := MulDiv(ActiveController.Metric(TyToolWindowHeaderPadVar, TyToolWindowHeaderPadDef),
      APPI, 96);
    if pad < 0 then pad := 0;
    tr := R;
    InflateRect(tr, -pad, 0);
    if (tr.Right > tr.Left) and (tr.Bottom > tr.Top) then
      P.DrawText(tr, txt, zoneS.FontName, ResolveFontSize(zoneS), zoneS.FontWeight,
        zoneS.TextColor, taCenter, tlCenter, True);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

function TTyToolWindowDropPreview.PaintPPI: Integer;
begin
  if FBar <> nil then Result := FBar.PPI
  else Result := Font.PixelsPerInch;
  if Result <= 0 then Result := 96;
end;

procedure TTyToolWindowDropPreview.Paint;
begin
  RenderTo(Canvas, ClientRect, PaintPPI);
end;
