unit tyControls.ButtonGroup;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller, tyControls.Accel;
type
  { TTyButtonGroup — a horizontal SEGMENTED button bar: N adjacent cells, each a
    caption, laid out edge-to-edge. Single-select (radio, like a segmented control:
    ItemIndex) or multi-select (a toggle set: IsSelected/SetSelected). Each segment
    is custom-drawn via TTyPainter reusing the 'TyButton' token, so a segment looks
    like a button; the selected segment(s) resolve with tysSelected, the hovered one
    with tysHover. Only the group's OUTER corners are rounded (left cell rounds left,
    right cell rounds right, middles are square). }
  TTyButtonGroup = class(TTyCustomControl)
  private
    FItems: TStrings;
    FMultiSelect: Boolean;
    FItemIndex: Integer;
    FSelected: array of Boolean;   // multi-select bit-set (kept sized to Items.Count)
    FHoverSeg: Integer;            // -1 = none; tracked in MouseMove for :hover styling
    FRefitting: Boolean;           // guards the AutoSize re-fit in Invalidate against re-entry
    FOnSelectionChange: TNotifyEvent;
    procedure SetItems(AValue: TStrings);
    procedure ItemsChanged(Sender: TObject);
    procedure SetMultiSelect(AValue: Boolean);
    procedure SetItemIndex(AValue: Integer);
    procedure EnsureSelectedLen;
    procedure DoSelectionChange;
  protected
    function GetStyleTypeKey: string; override;
    { Hit-test AX to a segment and apply selection, mirroring what a click does.
      Single-select: sets ItemIndex (fires OnSelectionChange iff it changed).
      Multi-select: toggles that segment (always fires OnSelectionChange on a valid
      segment). A hit outside any segment is a no-op. Exposed to tests as a seam. }
    procedure SelectAt(AX: Integer);
    { The widest item caption and the reference line height, in DEVICE px at APPI, measured
      with AStyle's font. Mnemonic markers are stripped first — they are drawn as an underline,
      not as a character, so measuring them would over-reserve. }
    procedure MeasureItems(APPI: Integer; const AStyle: TTyStyleSet;
      out AWidestPx, ALineHeightPx: Integer);
    { The size this bar actually needs, in DEVICE px, at the RESTING segment style.
        width  = COUNT x (widest caption + that style's left/right padding) — every cell is
                 the same width (RenderTo tiles them evenly) and each caption is drawn inside
                 exactly that horizontal inset, so under-counting one cell clips them all.
        height = ONE line of the resolved font, and no padding: RenderTo hands DrawText the
                 segment's FULL top-to-bottom span (it insets left/right only), so vertical
                 padding is not part of what the text needs — the line itself is.
      Both the preferred size and the size FLOOR read this one method, so "what the bar asks
      for" and "what the bar refuses to go below" are the same measurement and cannot drift
      apart, nor drift away from RenderTo. Empty bar -> 0 on both axes: nothing is drawn
      (RenderTo bails too), so there is nothing to demand. }
    procedure MeasureNeeded(out AWidthPx, AHeightPx: Integer);
    { The width the bar needs. Without this the bar keeps its designed width and a theme with
      roomier padding (xp asks for 12px where the default asks 6px, i.e. 24px more per cell)
      ellipsises every segment. }
    procedure CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
      WithThemeSpace: Boolean); override;
    { Clamp the bar so it can never be smaller than the captions it must draw. The theme's
      --control-height and a hand-set Height are REQUESTS; what is POSSIBLE is decided by the
      font and the padding, and only the control knows both — on Linux/Qt6 a 9pt CJK caption
      resolves through a fallback face with taller metrics, and DrawText clips with tlCenter,
      so a bar shorter than the ink loses the BOTTOM of every segment.

      Constraints, deliberately, and NOT a proposed PreferredHeight: proposing one makes the
      bar negotiate with its parent, and a child on a TTyToolBar bounced against the bar's
      ButtonHeight until LCL aborted with "ChangeBounds loop detected". Constraints clamp
      inside SetBounds instead, with no negotiation.

      覆盖基类钩子:基类的 UpdateSizeConstraints 带守卫,LCL 跨屏 DPI 流程正在缩放同一份
      Constraints 时会挡住这里的重算(见 tyControls.Base.pas)。没有它,一次 100%->250%
      把系数应用了两遍,分段条来回一趟从 200x28 变成 336x39。 }
    procedure DoUpdateSizeConstraints; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    { A theme switch reaches every control as a bare Invalidate, and the new theme's font and
      padding change the width the captions need — so an AutoSize bar must re-fit here too. }
    procedure Invalidate; override;
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { True iff segment AIndex is selected (single-select: AIndex = ItemIndex;
      multi-select: its bit). Out-of-range -> False. }
    function IsSelected(AIndex: Integer): Boolean;
    { Set segment AIndex's selected flag. Multi-select: sets/clears its bit (fires
      OnSelectionChange on a real change). Single-select: AValue=True selects it
      (=ItemIndex := AIndex); AValue=False clears it only when it was the selected one. }
    procedure SetSelected(AIndex: Integer; AValue: Boolean);
    function Count: Integer;
  published
    { Off by default (a designed bar keeps the width the .lfm gave it). Switch it on and the bar
      WIDENS so every cell fits its caption plus the theme's padding — a longer translation, a
      denser scale, a heavier font or a roomier skin lengthens the bar instead of ellipsising
      each segment. Height is left alone (see CalculatePreferredSize): it belongs to whoever
      lays out the row. }
    property AutoSize;
    property Items: TStrings read FItems write SetItems;
    property MultiSelect: Boolean read FMultiSelect write SetMultiSelect default False;
    property ItemIndex: Integer read FItemIndex write SetItemIndex default -1;
    property OnSelectionChange: TNotifyEvent read FOnSelectionChange write FOnSelectionChange;
    { Declared True to match the constructor, so that a host wanting this bar out of the
      tab cycle writes TabStop=False and it actually STREAMS (against the inherited
      `default False` that value looks like the default and is dropped). }
    property TabStop default True;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

{ Which segment index AX (device px, 0-based from the group's left edge) falls in,
  given the group's device width AWidthPx and segment count ACount. Segments divide
  the width evenly; the last cell absorbs rounding so the tiling exactly covers
  [0, AWidthPx). Returns -1 when empty (ACount <= 0), zero-width, or AX is outside
  [0, AWidthPx). PURE — no control state; unit-tested. }
function TySegmentAt(AX, AWidthPx, ACount: Integer): Integer;

{ The device-px rect of segment AIndex within a group of AWidthPx x AHeightPx and
  ACount segments. Segments tile left-to-right with equal widths; the last cell
  extends to AWidthPx (absorbing the integer-division remainder) so there are no
  gaps/overlaps and the rects cover [0, AWidthPx) x [0, AHeightPx). An out-of-range
  AIndex (or ACount <= 0) yields an empty rect. PURE — unit-tested. }
function TySegmentRect(AIndex, AWidthPx, AHeightPx, ACount: Integer): TRect;

implementation

function TySegmentAt(AX, AWidthPx, ACount: Integer): Integer;
var
  seg, segW: Integer;
begin
  Result := -1;
  if (ACount <= 0) or (AWidthPx <= 0) then Exit;
  if (AX < 0) or (AX >= AWidthPx) then Exit;
  segW := AWidthPx div ACount;
  if segW <= 0 then
  begin
    // Degenerate: fewer device px than segments. Distribute proportionally so a
    // click still maps to a real segment (and the last cell still absorbs the tail).
    seg := (AX * ACount) div AWidthPx;
  end
  else
  begin
    seg := AX div segW;
    // The last cell absorbs the rounding remainder, so any X past the start of the
    // last equal slice belongs to the last segment (never a phantom ACount-th cell).
    if seg > ACount - 1 then seg := ACount - 1;
  end;
  Result := seg;
end;

function TySegmentRect(AIndex, AWidthPx, AHeightPx, ACount: Integer): TRect;
var
  segW, l, r: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  if (ACount <= 0) or (AIndex < 0) or (AIndex >= ACount) then Exit;
  if (AWidthPx <= 0) or (AHeightPx <= 0) then Exit;
  segW := AWidthPx div ACount;
  l := AIndex * segW;
  if AIndex = ACount - 1 then
    r := AWidthPx           // last cell absorbs the remainder -> tile covers [0, W)
  else
    r := (AIndex + 1) * segW;
  Result := Rect(l, 0, r, AHeightPx);
end;

{ TTyButtonGroup }

constructor TTyButtonGroup.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TyAccelRegister(Self);
  // A selection control, not a decoration: a click picks a segment, so the click must also
  // move focus here (TTyCustomControl.MouseDown gates that on TabStop) and Tab must be able
  // to reach the bar. Same call TTySegmented — the other segmented bar — already makes.
  TabStop := True;
  FItems := TStringList.Create;
  TStringList(FItems).OnChange := @ItemsChanged;
  FMultiSelect := False;
  FItemIndex := -1;
  FHoverSeg := -1;
  Width := 240;
  Height := TyDensityHeight(ActiveController, 30);
end;

destructor TTyButtonGroup.Destroy;
begin
  TyAccelUnregister(Self);
  FItems.Free;
  inherited Destroy;
end;

function TTyButtonGroup.GetStyleTypeKey: string;
begin
  { Own key rather than the borrowed 'TyButton': a segmented bar with asymmetric per-cell corners is not one button.
    Added to 'TyButton's rule block as an extra selector, so every resolved value is
    unchanged — this opens a hook, it does not restyle anything. }
  Result := 'TyButtonGroup';
end;

function TTyButtonGroup.Count: Integer;
begin
  Result := FItems.Count;
end;

procedure TTyButtonGroup.EnsureSelectedLen;
begin
  if Length(FSelected) <> FItems.Count then
    SetLength(FSelected, FItems.Count);   // new slots default False
end;

procedure TTyButtonGroup.DoSelectionChange;
begin
  if Assigned(FOnSelectionChange) then FOnSelectionChange(Self);
end;

procedure TTyButtonGroup.SetItems(AValue: TStrings);
begin
  FItems.Assign(AValue);   // fires ItemsChanged, which resizes + clamps + repaints
end;

procedure TTyButtonGroup.ItemsChanged(Sender: TObject);
var
  i: Integer;
begin
  // The item list changed structurally. TStrings.OnChange carries no diff, so
  // positional selection bits (and the single-select index) cannot be remapped —
  // keeping them would silently move the selection onto a different item after an
  // insert/delete. Reset selection to a clean state instead (safe over subtly wrong).
  SetLength(FSelected, FItems.Count);
  for i := 0 to High(FSelected) do FSelected[i] := False;
  FItemIndex := -1;
  if FHoverSeg >= FItems.Count then FHoverSeg := -1;
  // 条目变了(数量、文字)→ 要的宽度也变了,AutoSize 的分段条必须重新贴合。
  // 这是本控件的"标题改变"钩子(标题住在 Items 里,不在 TControl.Caption 上),所以
  // 下限也得先跟着走一遍(对应 TTyButton.TextChanged 里的那一步)——顺序要紧:
  // AdjustSize 得在新的 Constraints 下跑,不然它按旧下限落一次、下一次 Invalidate 再纠。
  UpdateSizeConstraints;
  if AutoSize then
  begin
    InvalidatePreferredSize;
    AdjustSize;
  end;
  Invalidate;
end;

procedure TTyButtonGroup.Invalidate;
begin
  inherited Invalidate;
  { 换肤时每个控件收到的只是一个裸 Invalidate(TTyStyleController 向注册控件广播),而新主题
    带来的是另一套字体和 padding —— 每格要的宽度也就跟着变了。不在这里重新贴合,分段条就会
    留着旧主题的宽度,每个分段的文字都被省略号截断;TTyButton / TTyBadge 出于同样的理由也在
    自己的 Invalidate 里重量。FRefitting 挡住重入:AdjustSize -> SetBounds -> Invalidate
    会递归。
    下限(UpdateSizeConstraints)**不**看 AutoSize:主题拥有字体和 padding,换肤同样会把
    "文字装得下的最小尺寸"整个抬高或压低,而这跟这条分段条愿不愿意自动贴合无关。下限必须
    始终是推导出来的——把字号和 padding 调小,它就该跟着降下去,不然"嫌大就改 CSS"这句话
    就是空话。 }
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

procedure TTyButtonGroup.SetMultiSelect(AValue: Boolean);
var
  i: Integer;
begin
  if FMultiSelect = AValue then Exit;
  FMultiSelect := AValue;
  EnsureSelectedLen;
  // Clean slate on any mode switch so stale multi bits never resurface.
  for i := 0 to High(FSelected) do FSelected[i] := False;
  FItemIndex := -1;
  Invalidate;
end;

procedure TTyButtonGroup.SetItemIndex(AValue: Integer);
var
  NewIndex: Integer;
begin
  if (AValue >= 0) and (AValue < FItems.Count) then
    NewIndex := AValue
  else
    NewIndex := -1;
  if NewIndex = FItemIndex then Exit;
  FItemIndex := NewIndex;
  Invalidate;
  DoSelectionChange;
end;

function TTyButtonGroup.IsSelected(AIndex: Integer): Boolean;
begin
  if (AIndex < 0) or (AIndex >= FItems.Count) then Exit(False);
  if FMultiSelect then
  begin
    EnsureSelectedLen;
    Result := FSelected[AIndex];
  end
  else
    Result := (AIndex = FItemIndex);
end;

procedure TTyButtonGroup.SetSelected(AIndex: Integer; AValue: Boolean);
begin
  if (AIndex < 0) or (AIndex >= FItems.Count) then Exit;
  if FMultiSelect then
  begin
    EnsureSelectedLen;
    if FSelected[AIndex] = AValue then Exit;
    FSelected[AIndex] := AValue;
    Invalidate;
    DoSelectionChange;
  end
  else if AValue then
    SetItemIndex(AIndex)                      // single mode: True selects it
  else if AIndex = FItemIndex then
    SetItemIndex(-1);                         // clearing the selected one deselects
end;

procedure TTyButtonGroup.SelectAt(AX: Integer);
var
  seg: Integer;
begin
  seg := TySegmentAt(AX, Width, FItems.Count);
  if seg < 0 then Exit;
  if FMultiSelect then
  begin
    EnsureSelectedLen;
    FSelected[seg] := not FSelected[seg];
    Invalidate;
    DoSelectionChange;                        // multi: a click always toggles + fires
  end
  else
    SetItemIndex(seg);                        // single: fires only when index changes
end;

procedure TTyButtonGroup.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if not Enabled then Exit;
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
    SelectAt(X);
end;

procedure TTyButtonGroup.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  seg: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  seg := TySegmentAt(X, Width, FItems.Count);
  if seg <> FHoverSeg then
  begin
    FHoverSeg := seg;
    Invalidate;
  end;
end;

procedure TTyButtonGroup.MouseLeave;
begin
  inherited MouseLeave;
  if FHoverSeg <> -1 then
  begin
    FHoverSeg := -1;
    Invalidate;
  end;
end;

procedure TTyButtonGroup.MeasureItems(APPI: Integer; const AStyle: TTyStyleSet;
  out AWidestPx, ALineHeightPx: Integer);
{ 用 TTyPainter 量,而不是 LCL canvas:每格文字是 P.DrawText 以 BGRA 字体度量画出来的,只有
  同一个度量器给出的宽度才等于这些字形真正占的位置。画布传 nil —— BeginPaint 只建内部位图,
  EndPaint 见 canvas 为 nil 就不 blit、直接释放,所以在 paint 周期之外调用安全且不泄漏
  (TTySegmented / TTyBadge 用的是同一套写法)。 }
var
  P: TTyPainter;
  sz: TSize;
  i, fs, mp: Integer;
  disp: string;
begin
  AWidestPx := 0;
  ALineHeightPx := 0;
  P := TTyPainter.Create;
  try
    P.BeginPaint(nil, Rect(0, 0, 1, 1), APPI);   // 1x1:什么都不画,只量
    fs := ResolveFontSize(AStyle);
    // 稳定的参考字形:一个空条目也给出一行的高度。
    sz := P.MeasureText('Ag', AStyle.FontName, fs, AStyle.FontWeight);
    ALineHeightPx := sz.cy;
    for i := 0 to FItems.Count - 1 do
    begin
      // '&' 记号画成下划线而不是字符,RenderTo 也是先 TyParseMnemonic 再画 —— 量的必须是
      // 同一个字符串,否则每格都会多预留一个 '&' 的宽度。
      TyParseMnemonic(FItems[i], disp, mp);
      sz := P.MeasureText(disp, AStyle.FontName, fs, AStyle.FontWeight);
      if sz.cx > AWidestPx then AWidestPx := sz.cx;
    end;
    P.EndPaint;   // nil canvas -> 不 blit,只释放度量位图
  finally
    P.Free;
  end;
  if AWidestPx < 0 then AWidestPx := 0;
  if ALineHeightPx < 1 then ALineHeightPx := 1;
end;

procedure TTyButtonGroup.MeasureNeeded(out AWidthPx, AHeightPx: Integer);
var
  S: TTyStyleSet;
  ppi, n, widest, lineH, cellW: Integer;
begin
  AWidthPx := 0;
  AHeightPx := 0;
  { 祖先的构造函数里那次 SetBounds 会广播 Invalidate,而 Invalidate 现在无条件重算下限 ——
    那一刻 FItems 还没建出来。以前这里被 `if AutoSize` 挡着(构造期 AutoSize 恒为 False)
    才碰不到,现在得自己挡。 }
  if FItems = nil then Exit;
  n := FItems.Count;
  // 空分段条什么都不画(RenderTo 同样提前退出),所以两个轴上都"没有意见"/没有下限。
  if n <= 0 then Exit;
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  { 按**静止态**的分段样式来量:主题可以把选中格写成粗体,但分段条的尺寸不该取决于此刻选中
    的是哪一格 —— 否则每次点击都会让整条抖动。这和 RenderTo 解析未选中格用的是同一条
    (typeKey + StyleClass + [tysNormal])路径,也和它一样不叠 StyleOverride。 }
  S := ActiveController.Model.ResolveStyle(GetStyleTypeKey, StyleClass, [tysNormal]);
  MeasureItems(ppi, S, widest, lineH);
  { 每格 = 最宽的文字 + 该样式的左右 padding —— RenderTo 交给 DrawText 之前对每格做的正是这个
    内缩。分段是均分的(最后一格吃掉余数),所以整条 = 格数 x 每格;少算一格就是每格都被截。
    padding 按 MulDiv(...,ppi,96) 缩放,和绘制路径里的 P.Scale 一致。 }
  cellW := widest + MulDiv(S.Padding.Left + S.Padding.Right, ppi, 96);
  if cellW < 1 then cellW := 1;
  AWidthPx := n * cellW;
  { 高度只算**一行文字本身**,不加上下 padding:RenderTo 给 DrawText 的矩形上下沿就是整格
    (只内缩左右),所以上下 padding 不在"文字装得下"这件事里。多加一份就成了凭空抬高,
    工具条上的分段条会莫名其妙变高。 }
  AHeightPx := lineH;
end;

procedure TTyButtonGroup.CalculatePreferredSize(var PreferredWidth,
  PreferredHeight: Integer; WithThemeSpace: Boolean);
var
  w, h: Integer;
begin
  MeasureNeeded(w, h);
  PreferredWidth := w;
  { 只管宽度 —— 0 是 LCL 的"这个轴上没有意见",高度就留给排版方。分段条同时提议高度,就会和
    任何钉死高度的容器打架(TTyToolBar 把每个子控件都压到 ButtonHeight),两边来回弹到 LCL
    以 "TControl.ChangeBounds loop detected" 中止。装不下时兜底的是 UpdateSizeConstraints
    的下限:它在 SetBounds 里钳,不参与协商,所以不会来回顶。 }
  PreferredHeight := 0;
end;

procedure TTyButtonGroup.DoUpdateSizeConstraints;
var
  w, h: Integer;
begin
  if csDestroying in ComponentState then Exit;
  // 和 CalculatePreferredSize 同一次测量:报出去的宽度和守住的下限不会各说各话。
  MeasureNeeded(w, h);
  Constraints.MinWidth  := w;
  Constraints.MinHeight := h;
end;

procedure TTyButtonGroup.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  W, H, i, n: Integer;
  segStates: TTyStateSet;
  segStyle: TTyStyleSet;
  segRect: TRect;
  corners: TTyCorners;
  radius: Integer;
  disp: string;
  mp: Integer;
begin
  P := TTyPainter.Create;
  try
    W := ARect.Right - ARect.Left;
    H := ARect.Bottom - ARect.Top;
    P.BeginPaint(ACanvas, ARect, APPI);
    // Fill the parent's OPAQUE surface first: unselected ghost segments resolve to a
    // transparent background, which on the Win10 DWM sheet-of-glass would otherwise bleed
    // through as white/mismatched patches on dark themes (same fix as TTyButton).
    TyFillParentBg(Self, P, Rect(0, 0, W, H),
      ActiveController.Model.ResolveStyle(GetStyleTypeKey, StyleClass, [tysNormal]));
    n := FItems.Count;
    if n <= 0 then
    begin
      // Nothing to draw beyond the frame — resolve the base style so an empty group
      // still fills its background (headless-safe: no segment maths at all).
      P.EndPaint;
      Exit;
    end;

    // The outer corner radius comes from the resolved base style (BorderRadius token).
    // Left cell rounds its left corners, right cell its right corners, middles square.
    radius := ActiveController.Model.ResolveStyle(GetStyleTypeKey, StyleClass, [tysNormal]).BorderRadius;
    if radius < 0 then radius := 0;

    for i := 0 to n - 1 do
    begin
      // Per-segment state set: disabled wins; else selected (radio index / multi bit)
      // + hover layer on the hovered segment; otherwise normal.
      segStates := [];
      if not Enabled then
        Include(segStates, tysDisabled)
      else
      begin
        if IsSelected(i) then Include(segStates, tysSelected);
        if i = FHoverSeg then Include(segStates, tysHover);
        if segStates = [] then Include(segStates, tysNormal);
      end;

      segStyle := ActiveController.Model.ResolveStyle(GetStyleTypeKey, StyleClass, segStates);

      segRect := TySegmentRect(i, W, H, n);

      // Outer corners only: round the group's left/right edges, square the seams.
      corners := TyCorners(0, 0, 0, 0);
      if i = 0 then begin corners.TL := radius; corners.BL := radius; end;
      if i = n - 1 then begin corners.TR := radius; corners.BR := radius; end;

      // Background fill for this segment (per-corner rounding so seams stay flush).
      if tpBackground in segStyle.Present then
        P.FillBackground(segRect, segStyle.Background, corners);

      // Border around the segment. Adjacent cells share a seam so the doubled 1px
      // stroke reads as a single divider — simple, clean, and keeps each segment's
      // state border (e.g. selected/accent) visible on its own edges.
      if TyBorderVisible(segStyle) then
        P.StrokeBorder(segRect, corners, segStyle.BorderWidth, segStyle.BorderColor);

      // Centered caption, inset horizontally by the style's left/right padding.
      TyParseMnemonic(FItems[i], disp, mp);
      P.DrawText(
        Rect(segRect.Left  + P.Scale(segStyle.Padding.Left),
             segRect.Top,
             segRect.Right - P.Scale(segStyle.Padding.Right),
             segRect.Bottom),
        disp, segStyle.FontName, ResolveFontSize(segStyle), segStyle.FontWeight,
        segStyle.TextColor, taCenter, tlCenter, True, TyAccelGatePos(mp));
    end;

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyButtonGroup.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
