{ tyControls.ToolWindows 的一部分(include 进来的一段,不是单元):工具窗口的角标(spec §8.1,E 期)——
  窗口上的属性、BadgeDisplay、InvalidateBadge,和栏上量 / 画胶囊的两个辅助(BadgeSizeAt、
  DrawBadgeIn)。拆出来只是为了主单元短一点:它们要碰栏和窗口的私有成员,拆成单元就得把那些
  成员公开,所以用 include。 }

{ --- TTyToolWindow:角标 --------------------------------------------------------- }

procedure TTyCustomToolWindow.SetShowBadge(AValue: Boolean);
begin
  if FShowBadge = AValue then Exit;
  FShowBadge := AValue;
  BadgeChanged;
end;

procedure TTyCustomToolWindow.SetBadgeValue(AValue: Integer);
begin
  if FBadgeValue = AValue then Exit;
  FBadgeValue := AValue;
  BadgeChanged;
end;

procedure TTyCustomToolWindow.SetBadgeDot(AValue: Boolean);
begin
  if FBadgeDot = AValue then Exit;
  FBadgeDot := AValue;
  BadgeChanged;
end;

procedure TTyCustomToolWindow.BadgeChanged;
var
  b: TTyCustomToolWindowBar;
begin
  b := Bar;
  if (b = nil) or (csDestroying in b.ComponentState) then Exit;
  if b.Placement = twpBottom then
  begin
    { 标签宽变了:丢标签宽缓存(键里本来也有角标,这里再清一次不花钱),重画标签行 —— 当前页的
      Invalidate 里 B 期收尾的漂移检查会把操作区跟上(spec §3.4)。 }
    b.TabWidthsChanged;
    b.InvalidateHeader;
  end
  else
    b.Invalidate;
end;

procedure TTyCustomToolWindow.InvalidateBadge;
begin
  BadgeChanged;
end;

function TTyCustomToolWindow.BadgeDisplay(out AText: string; out ADot: Boolean): Boolean;
var
  vis: Boolean;
begin
  AText := '';
  ADot := FBadgeDot;
  if not FShowBadge then Exit(False);
  { 圆点也先给数字:事件看得到,画的时候不用。 }
  AText := TyBadgeText(FBadgeValue, False);
  vis := True;
  if Assigned(FOnBadgeDisplay) then FOnBadgeDisplay(Self, FBadgeValue, AText, vis);
  if ADot then
  begin
    AText := '';
    Result := vis;
  end
  else
    Result := vis and (AText <> '');
end;

{ --- TTyToolWindowBar:量 / 画角标 ------------------------------------------------ }

function TTyCustomToolWindowBar.BadgeSizeAt(AWindow: TTyCustomToolWindow; APPI: Integer;
  out AText: string; out ADot: Boolean): TSize;
var
  S: TTyStyleSet;
  fs, tw, th, rw, zw, zh, minPx, dotPx: Integer;
begin
  Result := Size(0, 0);
  AText := '';
  ADot := False;
  if (AWindow = nil) or not AWindow.BadgeDisplay(AText, ADot) then Exit;
  S := ActiveController.Model.ResolveStyle(TyToolWindowBadgeKey,
    TyStyleClassFor(Self, StyleClass), [tysNormal]);
  { 没有主题规则就不画(同 TTyButton 的徽标)。 }
  if not (tpBackground in S.Present) then Exit;
  minPx := TokenPxAt(TyBadgeMinSizeVar, TyBadgeMinSize, APPI);
  if minPx < 1 then minPx := 1;
  dotPx := TokenPxAt(TyBadgeDotSizeVar, TyBadgeDotSize, APPI);
  if ADot then Exit(TyBadgeSize(0, 0, 0, 0, minPx, True, dotPx));
  fs := ResolveFontSize(S);
  { 两种量法取大(Painter.pas 的约定,同 MeasureTabWidths):只按画布量,渲染器多出一个像素。 }
  TyMeasureTextBlock(AText, S.FontName, fs, S.FontWeight, APPI, 0, 0, tw, th);
  rw := TyMeasureRenderedTextWidth(AText, S.FontName, fs, S.FontWeight, APPI);
  if rw > tw then tw := rw;
  { 高按一个稳定的参考字形('0'),同 TTyButton.DrawBadge。 }
  TyMeasureTextBlock('0', S.FontName, fs, S.FontWeight, APPI, 0, 0, zw, zh);
  Result := TyBadgeSize(tw, zh, MulDiv(S.Padding.Left, APPI, 96),
    MulDiv(S.Padding.Top, APPI, 96), minPx, False, dotPx);
end;

procedure TTyCustomToolWindowBar.DrawBadgeIn(APainter: TTyPainter; const ABox: TRect;
  const AText: string; ADot: Boolean);
var
  S: TTyStyleSet;
  r: TRect;
  half, themedR, rLogical: Integer;
begin
  if (ABox.Right <= ABox.Left) or (ABox.Bottom <= ABox.Top) then Exit;
  S := ActiveController.Model.ResolveStyle(TyToolWindowBadgeKey,
    TyStyleClassFor(Self, StyleClass), [tysNormal]);
  if not (tpBackground in S.Present) then Exit;
  { 胶囊:主题没给圆角就半高,给了更小的就用主题的(TTyButton.DrawBadge 的做法);圆点是正圆。
    FillBackground 收的是逻辑半径。 }
  half := APainter.Unscale((ABox.Bottom - ABox.Top) div 2);
  themedR := TyEffectiveCorners(S).TL;
  if ADot or (themedR <= 0) then rLogical := half
  else rLogical := TyClampRadius(themedR, half);
  APainter.FillBackground(ABox, S.Background, TyUniformCorners(rLogical));
  if ADot or (AText = '') then Exit;
  { 文字框四边各放 1 个像素(同 TTyButton.DrawBadge:有的 widgetset 小号粗体画出来比量的大一丝,
    DrawText 按框裁剪会削掉字边);胶囊本身不变。 }
  r := ABox;
  InflateRect(r, APainter.Scale(1), APainter.Scale(1));
  APainter.DrawText(r, AText, S.FontName, ResolveFontSize(S), S.FontWeight, S.TextColor,
    taCenter, tlCenter, False, 0, True);
end;
