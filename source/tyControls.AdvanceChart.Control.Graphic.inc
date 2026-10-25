{ Part of tyControls.AdvanceChart (included, not a unit): the graphic component and the
  custom series. Moved out of the unit only to keep it readable; what the control is and
  why it is built the way it is, see the unit header. }

{ ==================== the graphic component [Batch 122] ====================

  [R3-B] THE LIST STAYS IN THE MODEL. GraphicModel keeps its flattened,
  id'd, merged-by-id list -- with the `hv` setLayoutInfoToExist writes, a
  group's 0 size, the layout keys mergeLayoutParam nulls -- in its option,
  which getOption shows; the tree is the raw merge (what the author wrote,
  `elements` replaced whole by each merge, as zrUtil.merge does), the layer
  the merge oracles record for every component. The list used to be
  written back into the tree; it lives in FGfxModel only now. }

procedure TTyAdvanceChart.GfxInitFromTree;
var node: TJSONData;
begin
  FGfxFresh := False;
  { A NEW MODEL: the view clears the old one's elements at its next
    render (GraphicView's _lastGraphicModel) }
  FGfxView.ForgetModel;
  FreeAndNil(FGfxModel);
  FGfxPending := True;
  if FOption = nil then Exit;
  node := FOption.ComponentAt('graphic', 0);
  if not (node is TJSONObject) then Exit;
  FGfxModel := TTyGfxModel.Create;
  FGfxModel.OptionUpdated(TJSONObject(node).Find('elements'), True);
end;

procedure TTyAdvanceChart.GfxPass(const AReport: TTyMergeReport);
var
  si: Integer;
  newOpt: TJSONObject;
begin
  if FGfxFresh then
  begin
    GfxInitFromTree;
    Exit;
  end;
  si := TyMergeSlotsIndex(AReport, 'graphic');
  if (si < 0) or (Length(AReport.Slots[si].Fate) = 0) then Exit;
  case AReport.Slots[si].Fate[0] of
    mfNew:
      GfxInitFromTree;
    mfMerged:
      begin
        if FGfxModel = nil then
        begin
          GfxInitFromTree;
          Exit;
        end;
        newOpt := nil;
        if Length(AReport.Slots[si].NewOpt) > 0 then newOpt := AReport.Slots[si].NewOpt[0];
        if newOpt <> nil then
          FGfxModel.OptionUpdated(newOpt.Find('elements'), False)
        else
          FGfxModel.OptionUpdated(nil, False);
        FGfxPending := True;
      end;
    mfRemoved, mfHole:
      begin
        FGfxView.ForgetModel;
        FreeAndNil(FGfxModel);
        FGfxPending := True;
      end;
  end;
end;

{ isAnimationEnabled and getShallow over the graphic model: its own option,
  else the root's, else globalDefault }
function TTyAdvanceChart.GfxAnimSettings: TTyGfxAnimSettings;
var
  node, root: TJSONObject;
  d: TJSONData;

  function Get(const AKey: string): TJSONData;
  begin
    Result := nil;
    if node <> nil then Result := node.Find(AKey);
    if ((Result = nil) or (Result.JSONType = jtNull)) and (root <> nil) then
      Result := root.Find(AKey);
    if (Result <> nil) and (Result.JSONType = jtNull) then Result := nil;
  end;

  function Num(const AKey: string; ADefault: Double): Double;
  begin
    d := Get(AKey);
    if (d <> nil) and (d.JSONType = jtNumber) then Result := d.AsFloat
    else Result := ADefault;
  end;

  function Str(const AKey, ADefault: string): string;
  begin
    d := Get(AKey);
    if (d <> nil) and (d.JSONType = jtString) then Result := d.AsString
    else Result := ADefault;
  end;

begin
  Result := Default(TTyGfxAnimSettings);
  node := nil;
  root := nil;
  if FOption <> nil then
  begin
    d := FOption.ComponentAt('graphic', 0);
    if d is TJSONObject then node := TJSONObject(d);
    if FOption.Root is TJSONObject then root := TJSONObject(FOption.Root);
  end;
  Result.Enabled := AnimAllowed;
  d := nil;
  if node <> nil then d := node.Find('animation');
  if (d = nil) or (d.JSONType = jtNull) then
  begin
    if root <> nil then d := root.Find('animation') else d := nil;
    { the root's 'auto' by default; a written null is no animation }
    if d = nil then
    else if d.JSONType = jtNull then Result.Enabled := False
    else if (d.JSONType = jtBoolean) and not d.AsBoolean then Result.Enabled := False
    else if (d.JSONType = jtNumber) and (d.AsFloat = 0) then Result.Enabled := False
    else if (d.JSONType = jtString) and (d.AsString = '') then Result.Enabled := False;
  end
  else if ((d.JSONType = jtBoolean) and not d.AsBoolean)
    or ((d.JSONType = jtNumber) and (d.AsFloat = 0))
    or ((d.JSONType = jtString) and (d.AsString = '')) then
    Result.Enabled := False;
  Result.Duration := Num('animationDuration', 1000);
  { globalDefault's: an easing of cubicInOut both ways (a series' own
    defaults say cubicOut, a component's do not) }
  Result.Easing := Str('animationEasing', 'cubicInOut');
  Result.Delay := Num('animationDelay', 0);
  Result.DurationUpdate := Num('animationDurationUpdate', 500);
  Result.EasingUpdate := Str('animationEasingUpdate', 'cubicInOut');
  Result.DelayUpdate := Num('animationDelayUpdate', 0);
end;

function TTyAdvanceChart.GfxLive: Boolean;
begin
  Result := (FGfxAnim <> nil) and (FGfxAnim.ClipCount > 0);
end;

function GfxImageSize(const ASource: string; out AW, AH: Double): Boolean;
begin
  { [F6a] a data URL's pixels, an image list's Width x Height }
  Result := TyChartImageSize(ASource, AW, AH) and (AW > 0) and (AH > 0);
  if not Result then
  begin
    AW := 0;
    AH := 0;
  end;
end;

procedure TTyAdvanceChart.GfxBuild(APPI: Integer);
var
  scale, w, h, z, zl: Double;
  meas: ITyTextMeasurer;
  node, d: TJSONData;
  ground: TTyGfxGround;
  ctx: TTyGfxPaintCtx;
  n: Integer;

  procedure Add(AEl: TTyGfxEl; ASilent: Boolean);
  var pe: TTyChartElement;
  begin
    if not TyGfxPaintElement(AEl, meas, ctx, pe) then Exit;
    pe.Silent := ASilent;
    pe.Datum := TyChartComponentDatum(ctkGraphic, 0, n);
    { zlevel over z, as zrender sorts; z and z2 whole }
    pe.Z := Round(AEl.ZLevel) * 100000 + Round(AEl.Z);
    pe.Z2 := Round(AEl.Z2);
    pe.GfxUnder := (AEl.ZLevel = 0) and (AEl.Z <= 0);
    SetLength(FGfxPaint, n + 1);
    SetLength(FGfxPaintEl, n + 1);
    FGfxPaint[n] := pe;
    FGfxPaintEl[n] := AEl;
    AEl.Serial := n;
    Inc(n);
  end;

  procedure Walk(AEl: TTyGfxEl; ASilent: Boolean);
  var i: Integer; s: Boolean;
  begin
    if AEl.Ignore then Exit;
    s := ASilent or AEl.Silent;
    if AEl.IsGroup then
    begin
      for i := 0 to High(AEl.Children) do Walk(AEl.Children[i], s);
      Exit;
    end;
    Add(AEl, s);
    if (AEl.TextContent <> nil) and not AEl.TextContent.Ignore then
      Add(AEl.TextContent, s or AEl.TextContent.Silent);
  end;

begin
  FGfxPaint := nil;
  FGfxPaintEl := nil;
  if FGfxView = nil then Exit;
  FGfxView.FreeGone;
  if APPI <= 0 then APPI := 96;
  scale := APPI / 96;
  w := (FLastRect.Right - FLastRect.Left) / scale;
  h := (FLastRect.Bottom - FLastRect.Top) / scale;
  { the layout measures in css px }
  meas := NewTextMeasurer(96);
  if FGfxPending then
  begin
    FGfxPending := False;
    z := NaN;
    zl := NaN;
    node := nil;
    if FOption <> nil then node := FOption.ComponentAt('graphic', 0);
    if node is TJSONObject then
    begin
      { graphicModel.get('z' / 'zlevel'): the component has no default for
        either, so the option root's reach it [R2-G] }
      d := TyGetShallowRoot(node, FOption.Root, 'z');
      if (d <> nil) and (d.JSONType = jtNumber) then z := d.AsFloat;
      d := TyGetShallowRoot(node, FOption.Root, 'zlevel');
      if (d <> nil) and (d.JSONType = jtNumber) then zl := d.AsFloat;
    end;
    FGfxView.Render(FGfxModel, w, h, meas, GfxAnimSettings, z, zl);
    FGfxW := w;
    FGfxH := h;
    { the flush that steps every new clip at the setOption instant }
    FGfxAnim.Update(AnimClock, True);
    AnimFlushOthers(FGfxAnim);
    AnimArmTimer;
  end
  { NOT BEFORE THE FIRST RENDER: the size is NaN until then, and comparing
    against it raises with the invalid-operation trap unmasked -- a chart
    that never had an option painted nothing but an exception }
  else if (not IsNan(FGfxW)) and ((w <> FGfxW) or (h <> FGfxH)) then
  begin
    FGfxView.Place(w, h, meas);
    FGfxW := w;
    FGfxH := h;
  end;
  MarkerGround(ground.Background, ground.IsDark);
  FGfxView.Prepare(meas, ground);
  ctx := Default(TTyGfxPaintCtx);
  ctx.Scale := scale;
  ctx.HasInk := True;
  ctx.Ink := TTyChartColor(ActiveController.Model.ResolveStyle(GetStyleTypeKey,
    StyleClass, [tysNormal]).TextColor);
  ctx.ImageSize := @GfxImageSize;
  n := 0;
  Walk(FGfxView.Root, False);
end;

procedure TTyAdvanceChart.GfxPaintUnder(APainter: TTyPainter);
var
  i: Integer;
  el: TTyChartElement;
begin
  FGfxUnder.Clear;
  for i := 0 to High(FGfxPaint) do
    if FGfxPaint[i].GfxUnder then FGfxUnder.Add(FGfxPaint[i]);
  for i := 0 to FGfxUnder.Count - 1 do
  begin
    el := FGfxUnder.Element(FGfxUnder.PaintOrder(i));
    if not el.Ignore then TyRenderElement(APainter, el);
  end;
end;

function TTyAdvanceChart.GfxElementEvent(const AType: string;
  const ATarget: TTyChartEventTarget; AX, AY: Integer): Boolean;
var
  el: TTyGfxEl;
  spec: string;
  ev: TTyChartElementEvent;
begin
  Result := False;
  if (ATarget.HdKind <> 8) or (FGfxView = nil) then Exit;
  el := FGfxView.Find(ATarget.HdName);
  if el = nil then Exit;
  ev := Default(TTyChartElementEvent);
  ev.EventType := AType;
  ev.TargetId := el.Id;
  ev.OffsetX := AX;
  ev.OffsetY := AY;
  { up the groups to the root: the handler, then the parent unless the
    handler stopped it }
  while (el <> nil) and (el <> FGfxView.Root) do
  begin
    spec := el.Handlers.Values['on' + AType];
    if spec <> '' then
    begin
      ev.Id := el.Id;
      ev.Name := el.Name;
      ev.Handler := spec;
      if TyChartRunElementHandler(spec, Self, ev) then Result := True;
    end;
    if Result then Break;
    el := el.Parent;
  end;
end;

procedure TTyAdvanceChart.GfxDragStart(const ATarget: TTyChartEventTarget;
  AX, AY: Integer);
var el: TTyGfxEl;
begin
  FGfxDragOn := False;
  if (ATarget.HdKind <> 8) or (FGfxView = nil) then Exit;
  el := FGfxView.Find(ATarget.HdName);
  while (el <> nil) and (el <> FGfxView.Root) and (el.Draggable = '') do el := el.Parent;
  if (el = nil) or (el = FGfxView.Root) then Exit;
  FGfxDragOn := True;
  FGfxDragId := el.Id;
  FGfxDragX := AX;
  FGfxDragY := AY;
end;

procedure TTyAdvanceChart.GfxDragMove(AX, AY: Integer);
var
  el: TTyGfxEl;
  dx, dy, scale, vx, vy: Double;
  inv: TTyMat2D;
begin
  if not FGfxDragOn or (FGfxView = nil) then Exit;
  el := FGfxView.Find(FGfxDragId);
  if el = nil then
  begin
    FGfxDragOn := False;
    Exit;
  end;
  if FPaintListPPI > 0 then scale := FPaintListPPI / 96 else scale := 1;
  dx := (AX - FGfxDragX) / scale;
  dy := (AY - FGfxDragY) / scale;
  FGfxDragX := AX;
  FGfxDragY := AY;
  if (dx = 0) and (dy = 0) then Exit;
  { Element.drift: 'horizontal' keeps y, 'vertical' keeps x }
  if el.Draggable = 'horizontal' then dy := 0
  else if el.Draggable = 'vertical' then dx := 0;
  { the move in the parent's frame }
  vx := dx;
  vy := dy;
  if (el.Parent <> nil) and el.Parent.HasTransform
    and TyMatInvert(el.Parent.Transform, inv) then
  begin
    vx := inv[0] * dx + inv[2] * dy;
    vy := inv[1] * dx + inv[3] * dy;
  end;
  el.X := el.X + vx;
  el.Y := el.Y + vy;
  DropStatic;
  InvalidateFrame;
end;

function TTyAdvanceChart.GraphicView: TTyGfxView;
begin
  Result := FGfxView;
end;

function TTyAdvanceChart.GraphicModel: TTyGfxModel;
begin
  Result := FGfxModel;
end;

function TTyAdvanceChart.GraphicPaintCount: Integer;
begin
  Result := Length(FGfxPaint);
end;

function TTyAdvanceChart.GraphicPaintElement(AIndex: Integer): TTyChartElement;
begin
  Result := FGfxPaint[AIndex];
end;

function TTyAdvanceChart.GraphicPaintSource(AIndex: Integer): TTyGfxEl;
begin
  Result := FGfxPaintEl[AIndex];
end;

function TTyAdvanceChart.CustomView(ASeriesIndex: Integer): TTyCustomView;
begin
  Result := nil;
  if (ASeriesIndex >= 0) and (ASeriesIndex <= High(FCustomViews)) then
    Result := FCustomViews[ASeriesIndex];
end;

function TTyAdvanceChart.CustomPaintSource(AIndex: Integer): TTyGfxEl;
begin
  Result := nil;
  if (AIndex >= 0) and (AIndex <= High(FCustomPaintEls)) then
    Result := FCustomPaintEls[AIndex];
end;

function TTyAdvanceChart.CustomClip(ASeriesIndex: Integer; out ARect: TTyXYWH): Boolean;
var slot: Integer;
begin
  ARect := Default(TTyXYWH);
  slot := SlotOfSeries(ASeriesIndex);
  Result := (slot >= 0) and (slot <= High(FCustomClipOn)) and FCustomClipOn[slot];
  if Result then ARect := FCustomClip[slot];
end;

function TTyAdvanceChart.CuLive: Boolean;
begin
  Result := (FCuAnim <> nil) and (FCuAnim.ClipCount > 0);
end;

procedure CustomUtPath(var APe: TTyChartElement; AEl: TTyGfxEl; ASeries, ARow: Integer;
  var APlace: Integer; AScale: Double); forward;

{ [R2-D] A UNIVERSAL TRANSITION TAKES OVER A CUSTOM ITEM (ASeries, its row
  inside the data): stopAnimation(newEl) stops what renderItem animates on
  it -- an enterFrom, a transition -- before its first step, so it rests
  where renderItem put it (forwarded to the end here, where the render's
  flush already stepped it). The item's paths in the list are laid out
  again from there for the transition to read; the list is built again at
  the next paint. }
procedure TTyAdvanceChart.AnimUtStopCustom(ASeries, ARow: Integer);
var
  view: TTyCustomView;
  root, gel: TTyGfxEl;
  k, q, place, slot, raw: Integer;
  pe, drawn: TTyChartElement;
  inItem: Boolean;
  meas: ITyTextMeasurer;
  ctx: TTyGfxPaintCtx;
  decal: TTyChartDecal;

  procedure Stop(AEl: TTyGfxEl);
  var q: Integer;
  begin
    AEl.StopAnimation('', True);
    if AEl.TextContent <> nil then AEl.TextContent.StopAnimation('', True);
    for q := 0 to High(AEl.Children) do Stop(AEl.Children[q]);
  end;

begin
  view := CustomView(ASeries);
  if view = nil then Exit;
  root := view.ElOf(ARow);
  if root = nil then Exit;
  Stop(root);
  FCustomUtStopped := True;
  if FPaintList = nil then Exit;
  TyGfxUpdateTransforms(view.Root);
  { the paint as CustomBuild makes it }
  meas := NewTextMeasurer(96);
  ctx := Default(TTyGfxPaintCtx);
  ctx.Scale := FCustomUtScale;
  ctx.HasInk := True;
  ctx.Ink := TTyChartColor(ActiveController.Model.ResolveStyle(GetStyleTypeKey,
    StyleClass, [tysNormal]).TextColor);
  ctx.ImageSize := @GfxImageSize;
  for k := 0 to Math.Min(FPaintList.Count - 1, High(FCustomPaintEls)) do
  begin
    pe := FPaintList.Element(k);
    if (pe.Anim.Role <> carCustomPath) or (pe.Anim.Series <> ASeries) or (pe.Anim.Index <> ARow) then
      Continue;
    gel := FCustomPaintEls[k];
    { (the element is the item's: its root or under it) }
    inItem := False;
    while gel <> nil do
    begin
      if gel = root then inItem := True;
      gel := gel.Parent;
    end;
    if not inItem then Continue;
    { its shape and style where they rest (an opacity entering from 0 is
      1), its decal kept }
    if TyGfxPaintElement(FCustomPaintEls[k], meas, ctx, drawn) then
    begin
      decal := pe.Style.Decal;
      pe.Shape := drawn.Shape;
      pe.Style := drawn.Style;
      pe.Style.Decal := decal;
    end;
    place := pe.Anim.Sub;
    { (CustomUtPath writes a transform only where there is one) }
    for q := 0 to 6 do pe.Anim.G[q] := 0;
    CustomUtPath(pe, FCustomPaintEls[k], ASeries, ARow, place, FCustomUtScale);
    FPaintList.SetElement(k, pe);
  end;
  { the item's states declared again over its paths as they rest now (a
    state proxy seeds its rest from them) }
  slot := SlotOfSeries(ASeries);
  if (slot < 0) or (slot > High(FStores)) or (FStores[slot] = nil) then Exit;
  raw := FStores[slot].GetRawIndex(ARow);
  if (ASeries <= High(FSt)) and (FSt[ASeries].Kind = sskCustom) and (raw >= 0)
    and (raw <= High(FSt[ASeries].Rows)) and (raw <= High(FSt[ASeries].HostIdx))
    and (FSt[ASeries].HostIdx[raw] >= 0) then
    StDeclareCustom(slot, raw, FPaintList);
end;

{ `coordinateSystem: 'none'` (or ''): resolved on nothing, its dimensions
  getCoordSysDimDefs' x and y }
function TTyAdvanceChart.CustomOnNone(ASlot: Integer): Boolean;
begin
  Result := (ASlot >= 0) and (ASlot <= High(FBindings))
    and (FBindings[ASlot].SeriesType = TyCustomSeriesType)
    and FBindings[ASlot].Resolved and (FBindings[ASlot].Cart = nil)
    and (FBindings[ASlot].Polar = nil) and (FBindings[ASlot].Single = nil)
    and (FBindings[ASlot].CalendarIndex < 0) and (FBindings[ASlot].RadarIndex < 0)
    and ((FBindings[ASlot].CoordSysName = 'none') or (FBindings[ASlot].CoordSysName = ''));
end;

function TTyAdvanceChart.CustomRootInfo(ASeriesIndex, AInside: Integer): TTyCustomElInfo;
var
  view: TTyCustomView;
  el: TTyGfxEl;
begin
  Result := nil;
  view := CustomView(ASeriesIndex);
  if view = nil then Exit;
  el := view.ElOf(AInside);
  if (el <> nil) and (el.Custom is TTyCustomElInfo) then
    Result := TTyCustomElInfo(el.Custom);
end;

{ the visualMap's row of a custom item (its dataIndexInside); False none }
function TTyAdvanceChart.CustomVisualRow(ASlot, ARow: Integer;
  out AVisual: TTyVisualRow): Boolean;
var raw: Integer;
begin
  AVisual := Default(TTyVisualRow);
  Result := False;
  if (ASlot < 0) or (ASlot > High(FBindings)) or (ASlot > High(FStores))
    or (FStores[ASlot] = nil) or (ARow < 0) or (ARow >= FStores[ASlot].Count) then Exit;
  raw := FStores[ASlot].GetRawIndex(ARow);
  if (ASlot > High(FVisualRows)) or (raw < 0) or (raw > High(FVisualRows[ASlot])) then Exit;
  AVisual := FVisualRows[ASlot][raw];
  Result := True;
end;

{ findEventDispatcher from the element up -- a textContent's host, then the
  parents: any with tooltipDisabled }
function TTyAdvanceChart.CustomTipDisabled(AElement: Integer): Boolean;
var el: TTyGfxEl;
begin
  Result := False;
  el := CustomPaintSource(AElement);
  while el <> nil do
  begin
    if (el.Custom is TTyCustomElInfo) and TTyCustomElInfo(el.Custom).TooltipDisabled then
      Exit(True);
    if el.Host <> nil then el := el.Host else el := el.Parent;
  end;
end;

{ ==================== the custom series [Batch 123] ==================== }

type
  { the coordinate system a custom series is drawn on [Batch 124]:
    cusUnknown one with no prepareCustom (nothing is drawn) }
  TTyCuSys = (cusUnknown, cusNone, cusCart, cusPolar, cusSingle, cusCalendar,
    cusMatrix,
    { [Batch 152] coord/geo/prepareCustom.ts }
    cusGeo);

  { THE API a renderItem is handed: CustomView.makeRenderItem's closures over
    the series' data, its visuals and its coordinate system's prepareCustom
    (cartesian, polar, single, calendar [Batch 124]) }
  TTyChartCustomApi = class(TTyCustomApi)
  private
    function Row(AInside: Integer; out ARow: Integer): Boolean;
    function ColumnAt(ADim: Integer): Integer;
    { [R2-J] the series' own dimensions name ADim of type 'ordinal' }
    function DeclaredOrdinal(ADim: Integer): Boolean;
    { the type a raw cell of ADim is read as: the declared ordinal, else the
      store's }
    function RawType(ADim: Integer): TTyDimType;
    function ItemNode(ARow: Integer): TJSONObject;
    function Lookup(AItem, ASeries: TJSONObject; const APath: array of string): TJSONData;
    function GlobalText(const AKey: string): TJSONData;
    function MakeStyle(AExtra: TJSONObject; ARow: Integer; AEmphasis: Boolean): TJSONObject;
    { [R2-J2] the series' getFormattedLabel for one status: False when the
      label of that status has no formatter (upstream's undefined) }
    function FormattedLabel(ARow: Integer; AEmphasis: Boolean; out AText: string): Boolean;
    function ParseOn(AAxis: TTyAxis; const ACell: TTyCustomCell): Double;
  protected
    function DimIndexOf(const AName: string): Integer; override;
    function DoCoord(const ACells: TTyCustomCellArray): TTyDoubleArray; override;
    function DoLayout(const ACells: TTyCustomCellArray): TTyCustomLayout; override;
    function DoMatrix(const AX, AY: TTyCustomCellArray; AClamp: Integer;
      AIgnoreMerge: Boolean; out ALayout: TTyCustomLayout): TTyDoubleArray; override;
  public
    Chart: TTyAdvanceChart;
    Slot, Series: Integer;
    { the coordinate system, and its object [Batch 124] }
    Sys: TTyCuSys;
    Polar: TTyPolar;
    Single: TTySingle;
    Calendar: TTyCalendar;
    { [Batch 147] }
    Matrix: TTyMatrix;
    Geo: TTyGeo;
    Store: TTyDataStore;
    Node: TJSONObject;
    { the dataIndexInside of the running call }
    Current: Integer;
    { device px per css px }
    Scale: Double;
    function Value(ADim: Integer; ADataIndexInside: Integer = -1): Double; overload; override;
    function ValueText(ADim: Integer; ADataIndexInside: Integer = -1): string; overload; override;
    function OrdinalRawValue(ADim: Integer; ADataIndexInside: Integer = -1): string; overload; override;
    function Size(const ADataSize, ADataItem: array of Double): TTyDoubleArray; overload; override;
    function Style(AExtra: TJSONObject = nil; ADataIndexInside: Integer = -1): TJSONObject; override;
    function StyleEmphasis(AExtra: TJSONObject = nil; ADataIndexInside: Integer = -1): TJSONObject; override;
    function Visual(const AType: string; ADataIndexInside: Integer = -1): TJSONData; override;
    function BarLayout(AOpt: TJSONObject): TTyCustomBarLayout; override;
    function CurrentSeriesIndices: TTyIntegerArray; override;
    function Font(AOpt: TJSONObject): string; override;
    function GetWidth: Double; override;
    function GetHeight: Double; override;
    function GetDevicePixelRatio: Double; override;
  end;

function CuNull(A: TJSONData): Boolean; inline;
begin
  Result := (A = nil) or (A.JSONType = jtNull);
end;

function CuTruthy(A: TJSONData): Boolean;
begin
  if A = nil then Exit(False);
  case A.JSONType of
    jtNull: Result := False;
    jtBoolean: Result := A.AsBoolean;
    jtNumber: Result := (A.AsFloat <> 0) and not IsNan(A.AsFloat);
    jtString: Result := A.AsString <> '';
  else
    Result := True;
  end;
end;

procedure CuPut(AObj: TJSONObject; const AKey: string; AValue: TJSONData);
var i: Integer;
begin
  i := AObj.IndexOfName(AKey);
  if i >= 0 then AObj.Items[i] := AValue else AObj.Add(AKey, AValue);
end;

function CuObj(AObj: TJSONObject; const AKey: string): TJSONObject;
var d: TJSONData;
begin
  Result := nil;
  if AObj = nil then Exit;
  d := AObj.Find(AKey);
  if d is TJSONObject then Result := TJSONObject(d);
end;

{ String() of a JSON value the way a join prints it }
function CuText(A: TJSONData): string;
begin
  Result := '';
  if A = nil then Exit;
  case A.JSONType of
    jtString: Result := A.AsString;
    jtNumber: Result := TyJsNumberToString(A.AsFloat);
    jtBoolean: if A.AsBoolean then Result := 'true' else Result := 'false';
    jtNull: Result := 'null';
  end;
end;

function TTyChartCustomApi.Row(AInside: Integer; out ARow: Integer): Boolean;
begin
  if AInside < 0 then ARow := Current else ARow := AInside;
  Result := (Store <> nil) and (ARow >= 0) and (ARow < Store.Count);
end;

{ the store column that reads data dimension ADim (its raw position) }
function TTyChartCustomApi.DeclaredOrdinal(ADim: Integer): Boolean;
var d: TJSONData;
begin
  Result := False;
  if (Node = nil) or (ADim < 0) then Exit;
  d := Node.Find('dimensions');
  if not (d is TJSONArray) or (ADim >= d.Count) then Exit;
  d := TJSONArray(d).Items[ADim];
  Result := (d is TJSONObject) and (TJSONObject(d).Get('type', '') = 'ordinal');
end;

function TTyChartCustomApi.RawType(ADim: Integer): TTyDimType;
begin
  if DeclaredOrdinal(ADim) then Result := ddtOrdinal
  else Result := Store.RawPosType(ADim);
end;

function TTyChartCustomApi.ColumnAt(ADim: Integer): Integer;
var c: Integer;
begin
  Result := -1;
  if Store = nil then Exit;
  for c := 0 to Store.DimCount - 1 do
    if Store.RawDimPos(c) = ADim then
    begin
      { [R2-J] A COLUMN THE SERIES' OWN dimensions DECLARE ORDINAL, which no
        axis interns: createDimensions keeps the type the series wrote (the
        coordinate system's outranks only a dataset's), and an ordinal one
        without an ordinal meta keeps the value as written --
        custom-calendar-icon declares its second dimension of type 'ordinal'
        and reads its events '2|3|0' back as that text, where the calendar's
        own value column parsed them to NaN. The cell is read raw instead
        (RawType). }
      if (Store.DimType(c) <> ddtOrdinal) and DeclaredOrdinal(ADim) then Exit(-1);
      Exit(c);
    end;
end;

function TTyChartCustomApi.ItemNode(ARow: Integer): TJSONObject;
var d: TJSONData; raw: Integer;
begin
  Result := nil;
  if (Node = nil) or (Store = nil) then Exit;
  raw := Store.GetRawIndex(ARow);
  d := Node.Find('data');
  if not (d is TJSONArray) or (raw < 0) or (raw >= d.Count) then Exit;
  d := TJSONArray(d).Items[raw];
  if d is TJSONObject then Result := TJSONObject(d);
end;

{ getShallow through the item model: the item's own value, else the
  series' }
function TTyChartCustomApi.Lookup(AItem, ASeries: TJSONObject;
  const APath: array of string): TJSONData;

  function Walk(ARoot: TJSONObject): TJSONData;
  var i: Integer; o: TJSONObject;
  begin
    Result := nil;
    o := ARoot;
    for i := 0 to High(APath) - 1 do
    begin
      o := CuObj(o, APath[i]);
      if o = nil then Exit;
    end;
    if o <> nil then Result := o.Find(APath[High(APath)]);
    if CuNull(Result) then Result := nil;
  end;

begin
  Result := nil;
  if AItem <> nil then Result := Walk(AItem);
  if (Result = nil) and (ASeries <> nil) then Result := Walk(ASeries);
end;

{ the global text style: the option's root textStyle over globalDefault's }
function TTyChartCustomApi.GlobalText(const AKey: string): TJSONData;
var root: TJSONObject;
begin
  Result := nil;
  if (Chart.FOption <> nil) and (Chart.FOption.Root is TJSONObject) then
  begin
    root := CuObj(TJSONObject(Chart.FOption.Root), 'textStyle');
    if root <> nil then Result := root.Find(AKey);
  end;
  if CuNull(Result) then Result := TyMkDefaultTextStyle.Find(AKey);
  if CuNull(Result) then Result := nil;
end;

function TTyChartCustomApi.DimIndexOf(const AName: string): Integer;
var p: Integer;
begin
  Result := -1;
  if Store = nil then Exit;
  for p := 0 to Max(Store.RawWidth, Store.DimCount) - 1 do
    if Store.RawDimName(p) = AName then Exit(p);
end;

function TTyChartCustomApi.Value(ADim: Integer; ADataIndexInside: Integer): Double;
var
  r, col: Integer;
  cell: TTyDataValue;
  t: TTyDimType;
begin
  Result := NaN;
  if not Row(ADataIndexInside, r) then Exit;
  col := ColumnAt(ADim);
  if col >= 0 then Exit(Store.Get(col, r));
  if not TTyDataStore.RawCell(Store.RawItem(r), ADim, cell) then Exit;
  t := RawType(ADim);
  { an ordinal dimension no axis interns keeps the value as written }
  if t = ddtOrdinal then
  begin
    if cell.Kind = dvkNumber then Result := cell.Num;
    Exit;
  end;
  Result := TyParseDataValue(cell, t);
end;

function TTyChartCustomApi.ValueText(ADim: Integer; ADataIndexInside: Integer): string;
var
  r, col: Integer;
  cell: TTyDataValue;
begin
  Result := 'undefined';
  if not Row(ADataIndexInside, r) then Exit;
  col := ColumnAt(ADim);
  if col >= 0 then Exit(TyJsNumberToString(Store.Get(col, r)));
  if not TTyDataStore.RawCell(Store.RawItem(r), ADim, cell) then Exit;
  if (RawType(ADim) = ddtOrdinal) or (cell.Kind = dvkNone) then
    Exit(TyJsValueText(cell, 'undefined'));
  Result := TyJsNumberToString(Value(ADim, r));
end;

function TTyChartCustomApi.OrdinalRawValue(ADim: Integer; ADataIndexInside: Integer): string;
var r, col: Integer; v: Double;
begin
  Result := 'undefined';
  if not Row(ADataIndexInside, r) then Exit;
  col := ColumnAt(ADim);
  if (col >= 0) and (Store.DimType(col) = ddtOrdinal) and (Store.OrdinalMeta(col) <> nil) then
  begin
    v := Store.Get(col, r);
    if IsNan(v) or (Frac(v) <> 0) or (v < 0) or (v >= Store.CategoryCount(col)) then
      Exit('undefined');
    Exit(Store.CategoryAt(col, Trunc(v)));
  end;
  Result := ValueText(ADim, r);
end;

{ scale.parse of one cell on an axis }
function TTyChartCustomApi.ParseOn(AAxis: TTyAxis; const ACell: TTyCustomCell): Double;
var ord_: Integer; ms: Double;
begin
  Result := NaN;
  if (AAxis = nil) or (ACell.Kind = cckNone) then Exit;
  case AAxis.AxisType of
    atCategory:
      if ACell.Kind = cckText then
      begin
        if AAxis.Categories = nil then Exit;
        ord_ := AAxis.Categories.GetOrdinal(ACell.Text);
        if ord_ >= 0 then Result := ord_;
      end
      else
        Result := TyJsRound(ACell.Num);
    atTime:
      if ACell.Kind = cckText then
      begin
        if TyParseDateMs(ACell.Text, ms, False) then Result := ms;
      end
      else
        Result := TyJsRound(ACell.Num);
  else
    if ACell.Kind = cckText then
    begin
      if ACell.Text = '' then Exit;
      Result := TyJsToNumber(ACell.Text);
    end
    else
      Result := ACell.Num;
  end;
end;

const
  cCuPi: Double = Pi;

function CuMask: TFPUExceptionMask;
begin
  Result := SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
    exOverflow, exUnderflow, exPrecision]);
end;

{ +v of a cell: a text's number, nothing NaN }
function CuNumCell(const ACell: TTyCustomCell): TTyCustomCell;
begin
  Result := ACell;
  if ACell.Kind = cckText then
  begin
    Result.Kind := cckNumber;
    Result.Num := TyJsToNumber(ACell.Text);
  end
  else if ACell.Kind = cckNone then
  begin
    Result.Kind := cckNumber;
    Result.Num := NaN;
  end;
end;

{ a calendar's parseDate of a cell: a number is epoch ms, a text a date }
function CuCalMs(ACal: TTyCalendar; const ACell: TTyCustomCell): Double;
var v: TTyDataValue;
begin
  v := Default(TTyDataValue);
  case ACell.Kind of
    cckNumber:
      begin
        v.Kind := dvkNumber;
        v.Num := ACell.Num;
      end;
    cckText:
      begin
        v.Kind := dvkText;
        v.Text := ACell.Text;
      end;
  else
    v.Kind := dvkNone;
  end;
  Result := ACal.ParseDate(v);
end;

{ the coordinate system's api.coord, in css px: a cartesian's dataToPoint;
  a polar's dataToRadius and dataToAngle through coordToPoint, the radius
  and the angle in radians pushed on; a single's dataToPoint(+v); a
  calendar's dataToPoint (clamped); nothing on no system }
function CuSecond(const ACells: TTyCustomCellArray): TTyCustomCellArray; forward;

function TTyChartCustomApi.DoCoord(const ACells: TTyCustomCellArray): TTyDoubleArray;
var
  lay: TTyCustomLayout;
  b: TTySeriesBinding;
  p: TTyPointF;
  cx, cy: TTyCustomCell;
  rad, ang, t: Double;
  mask: TFPUExceptionMask;
begin
  Result := nil;
  cx := Default(TTyCustomCell);
  cy := Default(TTyCustomCell);
  if Length(ACells) > 0 then cx := ACells[0];
  if Length(ACells) > 1 then cy := ACells[1];
  b := Chart.FBindings[Slot];
  mask := CuMask;
  try
    case Sys of
      cusCart:
        begin
          SetLength(Result, 2);
          Result[0] := NaN;
          Result[1] := NaN;
          if b.Cart = nil then Exit;
          p := b.Cart.DataToPoint([ParseOn(b.XAxis, cx), ParseOn(b.YAxis, cy)]);
          Result[0] := p.X / Scale;
          Result[1] := p.Y / Scale;
        end;
      cusPolar:
        begin
          rad := Polar.RadiusAxis.DataToCoord(ParseOn(Polar.RadiusAxis, cx));
          ang := Polar.AngleAxis.DataToCoord(ParseOn(Polar.AngleAxis, cy));
          p := Polar.CoordToPoint(rad, ang);
          SetLength(Result, 4);
          Result[0] := p.X / Scale;
          Result[1] := p.Y / Scale;
          Result[2] := rad / Scale;
          { angle * Math.PI / 180, in that order }
          t := ang * cCuPi;
          Result[3] := t / 180;
        end;
      cusSingle:
        begin
          p := Single.ValueToPoint(ParseOn(Single.Axis, CuNumCell(cx)));
          SetLength(Result, 2);
          Result[0] := p.X / Scale;
          Result[1] := p.Y / Scale;
        end;
      cusCalendar:
        begin
          p := Calendar.DatePoint(CuCalMs(Calendar, cx), True);
          SetLength(Result, 2);
          Result[0] := p.X / Scale;
          Result[1] := p.Y / Scale;
        end;
      { a matrix cell's centre: one value per direction [Batch 147] }
      cusMatrix:
        Result := DoMatrix(Copy(ACells, 0, 1), CuSecond(ACells), 0, False, lay);
      { a geo's dataToPoint: a region name, or the pair through ToNumber
        [Batch 152] }
      cusGeo:
        begin
          SetLength(Result, 2);
          Result[0] := NaN;
          Result[1] := NaN;
          if Geo = nil then Exit;
          if (Length(ACells) = 1) and (cx.Kind = cckText) then
          begin
            if not Geo.PointOfName(cx.Text, p) then Exit;
          end
          else if not Geo.PointOf(CuNumCell(cx).Num, CuNumCell(cy).Num, p) then Exit;
          Result[0] := p.X / Scale;
          Result[1] := p.Y / Scale;
        end;
    end;
  finally
    ConvertUnmask(mask);
  end;
end;

{ the second cell as one direction's parts: an absent one is one part that
  names nothing (upstream's [undefined]) }
function CuSecond(const ACells: TTyCustomCellArray): TTyCustomCellArray;
begin
  Result := nil;
  SetLength(Result, 1);
  if Length(ACells) > 1 then Result[0] := ACells[1]
  else Result[0] := Default(TTyCustomCell);
end;

{ a matrix's dataToLayout of the parts [Batch 147]: a text a header cell's
  name (the tree's category list), a number an ordinal or a level, nothing
  NaN; the clamp; the merged cells unless ignoreMergeCells [Batch 149]; css
  px }
function TTyChartCustomApi.DoMatrix(const AX, AY: TTyCustomCellArray; AClamp: Integer;
  AIgnoreMerge: Boolean; out ALayout: TTyCustomLayout): TTyDoubleArray;
var
  parts: array[0..1] of TTyDoubleArray;
  r: TTyXYWH;
  loc: TTyMatrixLocRange;
  cl: TTyMatrixClamp;
  k, o: Integer;
  mask: TFPUExceptionMask;

  function CellOf(ADim: Integer; const C: TTyCustomCell): Double;
  begin
    Result := NaN;
    case C.Kind of
      cckNumber: Result := C.Num;
      cckText:
        begin
          o := Matrix.Dims[ADim].Meta.GetOrdinal(C.Text);
          if o >= 0 then Result := o;
        end;
    end;
  end;

begin
  ALayout := Default(TTyCustomLayout);
  Result := nil;
  if (Sys <> cusMatrix) or (Matrix = nil) then Exit;
  SetLength(parts[0], Length(AX));
  for k := 0 to High(AX) do parts[0][k] := CellOf(0, AX[k]);
  SetLength(parts[1], Length(AY));
  for k := 0 to High(AY) do parts[1][k] := CellOf(1, AY[k]);
  case AClamp of
    0: cl := mclNone;
    2: cl := mclBody;
    3: cl := mclCorner;
  else
    cl := mclAll;
  end;
  mask := CuMask;
  try
    Matrix.DataToLayoutRange(parts[0], parts[1], cl, r, loc, AIgnoreMerge);
    ALayout.Valid := True;
    ALayout.Rect.X := r.X / Scale;
    ALayout.Rect.Y := r.Y / Scale;
    ALayout.Rect.Width := r.W / Scale;
    ALayout.Rect.Height := r.H / Scale;
    ALayout.HasLocatorRange := True;
    ALayout.LocatorRange[0][0] := loc[0][0];
    ALayout.LocatorRange[0][1] := loc[0][1];
    ALayout.LocatorRange[1][0] := loc[1][0];
    ALayout.LocatorRange[1][1] := loc[1][1];
    SetLength(Result, 2);
    Result[0] := ALayout.Rect.X + ALayout.Rect.Width / 2;
    Result[1] := ALayout.Rect.Y + ALayout.Rect.Height / 2;
  finally
    ConvertUnmask(mask);
  end;
end;

{ a calendar's api.layout: dataToLayout (clamped), in css px }
function TTyChartCustomApi.DoLayout(const ACells: TTyCustomCellArray): TTyCustomLayout;
var
  c0: TTyCustomCell;
  rc, cc: TTyXYWH;
  mask: TFPUExceptionMask;
begin
  Result := Default(TTyCustomLayout);
  { a matrix cell's [Batch 147] }
  if Sys = cusMatrix then
  begin
    DoMatrix(Copy(ACells, 0, 1), CuSecond(ACells), 0, False, Result);
    Exit;
  end;
  if (Sys <> cusCalendar) or (Calendar = nil) then Exit;
  c0 := Default(TTyCustomCell);
  if Length(ACells) > 0 then c0 := ACells[0];
  mask := CuMask;
  try
    Calendar.DateLayoutXYWH(CuCalMs(Calendar, c0), True, rc, cc);
    Result.Valid := True;
    Result.HasContentRect := True;
    Result.Rect.X := rc.X / Scale;
    Result.Rect.Y := rc.Y / Scale;
    Result.Rect.Width := rc.W / Scale;
    Result.Rect.Height := rc.H / Scale;
    Result.ContentRect.X := cc.X / Scale;
    Result.ContentRect.Y := cc.Y / Scale;
    Result.ContentRect.Width := cc.W / Scale;
    Result.ContentRect.Height := cc.H / Scale;
  finally
    ConvertUnmask(mask);
  end;
end;

{ dataToCoordSize: a category axis' band width, else the span the size
  covers about the item's value -- per axis on a cartesian and a polar
  (dataItem || [0, 0]; the angle in radians), one number on a single axis
  (an undefined item NaN), nothing on a calendar or no system }
function TTyChartCustomApi.Size(const ADataSize, ADataItem: array of Double): TTyDoubleArray;
var
  b: TTySeriesBinding;
  ax: TTyAxis;
  i: Integer;
  val, half, w: Double;
  p1, p2: TTyPointF;
  item: array[0..1] of Double;
  mask: TFPUExceptionMask;
begin
  Result := nil;
  b := Chart.FBindings[Slot];
  mask := CuMask;
  try
    { dataToCoordSize on a geo: each dimension's span about the item through
      dataToPoint [Batch 152] }
    if (Sys = cusGeo) and (Geo <> nil) then
    begin
      if Length(ADataItem) = 0 then
      begin
        item[0] := 0;
        item[1] := 0;
      end
      else
      begin
        item[0] := ADataItem[0];
        if Length(ADataItem) > 1 then item[1] := ADataItem[1] else item[1] := NaN;
      end;
      SetLength(Result, 2);
      for i := 0 to 1 do
      begin
        val := item[i];
        if i <= High(ADataSize) then half := ADataSize[i] / 2 else half := NaN;
        if i = 0 then
        begin
          if not Geo.PointOf(val - half, item[1], p1) then p1 := TyPointF(NaN, NaN);
          if not Geo.PointOf(val + half, item[1], p2) then p2 := TyPointF(NaN, NaN);
          Result[0] := Abs(p1.X / Scale - p2.X / Scale);
        end
        else
        begin
          if not Geo.PointOf(item[0], val - half, p1) then p1 := TyPointF(NaN, NaN);
          if not Geo.PointOf(item[0], val + half, p2) then p2 := TyPointF(NaN, NaN);
          Result[1] := Abs(p1.Y / Scale - p2.Y / Scale);
        end;
      end;
      Exit;
    end;
    case Sys of
      cusCart, cusPolar:
        begin
          if Length(ADataItem) = 0 then
          begin
            item[0] := 0;
            item[1] := 0;
          end
          else
          begin
            item[0] := ADataItem[0];
            if Length(ADataItem) > 1 then item[1] := ADataItem[1] else item[1] := NaN;
          end;
          SetLength(Result, 2);
          for i := 0 to 1 do
          begin
            Result[i] := NaN;
            if Sys = cusCart then
            begin
              if i = 0 then ax := b.XAxis else ax := b.YAxis;
            end
            else if i = 0 then ax := Polar.RadiusAxis
            else ax := Polar.AngleAxis;
            if ax = nil then Continue;
            val := item[i];
            if i <= High(ADataSize) then half := ADataSize[i] / 2 else half := NaN;
            if ax.AxisType = atCategory then w := ax.BandWidth
            else w := Abs(ax.DataToLocal(val - half) - ax.DataToLocal(val + half));
            if (Sys = cusPolar) and (i = 1) then
            begin
              { result * Math.PI / 180: degrees are no pixels }
              w := w * cCuPi;
              Result[i] := w / 180;
            end
            else
              Result[i] := w / Scale;
          end;
        end;
      cusSingle:
        begin
          SetLength(Result, 1);
          ax := Single.Axis;
          if Length(ADataItem) > 0 then val := ADataItem[0] else val := NaN;
          if Length(ADataSize) > 0 then half := ADataSize[0] / 2 else half := NaN;
          if ax.AxisType = atCategory then
            Result[0] := ax.BandWidth / Scale
          else
            Result[0] := Abs(ax.DataToLocal(val - half) - ax.DataToLocal(val + half)) / Scale;
        end;
    end;
  finally
    ConvertUnmask(mask);
  end;
end;

{ [R2-J2] DataFormatMixin.getFormattedLabel(dataIndexInside, status): the
  item model's `label.formatter` (`emphasis.label.formatter` for the
  emphasis status -- no fall back inside, the caller's retrieve3 does that),
  a function handed the item's getDataParams with params.status set, a
  string through formatTpl and the `{@dim}` pass; anything else, and no
  formatter at all, is undefined. A '@Name' is the registered handler. }
function TTyChartCustomApi.FormattedLabel(ARow: Integer; AEmphasis: Boolean;
  out AText: string): Boolean;
var
  d, vis: TJSONData;
  prm: TTyChartCallbackParams;
  ink: TTyChartColor;
  sname: string;
begin
  AText := '';
  if AEmphasis then d := Lookup(ItemNode(ARow), Node, ['emphasis', 'label', 'formatter'])
  else d := Lookup(ItemNode(ARow), Node, ['label', 'formatter']);
  Result := (d <> nil) and (d.JSONType = jtString);
  if not Result then Exit;
  { params.color: the item's visual fill }
  ink := 0;
  vis := Chart.CustomVisualFill(Slot, ARow);
  try
    if (vis <> nil) and (vis.JSONType = jtString) then
      TyTryParseChartColor(vis.AsString, ink);
  finally
    vis.Free;
  end;
  sname := Chart.SeriesModelName(Series);
  if TyChartIsHandlerRef(d.AsString) then
  begin
    prm := TyLabelParams(Store, ARow, sname, -1, 0, False, Series, 'custom', ink, '');
    if AEmphasis then prm.Status := 'emphasis';
    AText := TyChartRunHandler(d.AsString, TyChartOneParams(prm));
  end
  else
    AText := TyLabelText(d.AsString, True, tldValue, Store, ARow, sname, -1, 0,
      False, Series, 'custom', ink, '', False, '');
end;

{ api.style / api.styleEmphasis: getItemStyle, the visual colour and
  opacity (normal), the label's text style and config, then
  convertToEC4StyleForCustomSerise, the extra over it, legacy }
function TTyChartCustomApi.MakeStyle(AExtra: TJSONObject; ARow: Integer;
  AEmphasis: Boolean): TJSONObject;
const
  cItem: array[0..12, 0..1] of string = (('fill', 'color'), ('stroke', 'borderColor'),
    ('lineWidth', 'borderWidth'), ('opacity', 'opacity'), ('shadowBlur', 'shadowBlur'),
    ('shadowOffsetX', 'shadowOffsetX'), ('shadowOffsetY', 'shadowOffsetY'),
    ('shadowColor', 'shadowColor'), ('lineDash', 'borderType'),
    ('lineDashOffset', 'borderDashOffset'), ('lineCap', 'borderCap'),
    ('lineJoin', 'borderJoin'), ('miterLimit', 'borderMiterLimit'));
  { convertToEC4RichItem: the text style's keys under their ec4 names }
  cRich: array[0..21, 0..1] of string = (('lineWidth', 'textStrokeWidth'),
    ('font', 'font'), ('fontStyle', 'fontStyle'), ('fontWeight', 'fontWeight'),
    ('fontSize', 'fontSize'), ('fontFamily', 'fontFamily'), ('align', 'textAlign'),
    ('verticalAlign', 'textVerticalAlign'), ('lineHeight', 'textLineHeight'),
    ('width', 'textWidth'), ('height', 'textHeight'),
    ('backgroundColor', 'textBackgroundColor'), ('padding', 'textPadding'),
    ('borderColor', 'textBorderColor'), ('borderWidth', 'textBorderWidth'),
    ('borderRadius', 'textBorderRadius'), ('shadowColor', 'textBoxShadowColor'),
    ('shadowBlur', 'textBoxShadowBlur'), ('shadowOffsetX', 'textBoxShadowOffsetX'),
    ('shadowOffsetY', 'textBoxShadowOffsetY'), ('textShadowColor', 'textShadowColor'),
    ('textShadowBlur', 'textShadowBlur'));
  cFonts: array[0..3] of string = ('fontStyle', 'fontWeight', 'fontSize', 'fontFamily');
var
  item, ts, tc: TJSONObject;
  d, vis, posD: TJSONData;
  i, k: Integer;
  isInside, show: Boolean;
  txt: string;
  hasText: Boolean;
  cells: TTyIntegerArray;
  cell: TTyDataValue;
  vrow: TTyVisualRow;
  inh: string;
  richObj: TJSONObject;

  function ItemStyleOf(AKey: string): TJSONData;
  begin
    if AEmphasis then Result := Lookup(item, Node, ['emphasis', 'itemStyle', AKey])
    else Result := Lookup(item, Node, ['itemStyle', AKey]);
  end;

  function LabelOf(AKey: string): TJSONData;
  begin
    if AEmphasis then Result := Lookup(item, Node, ['emphasis', 'label', AKey])
    else Result := Lookup(item, Node, ['label', AKey]);
  end;

  { [R2-J2] the label's `rich` as createTextStyle builds it: every name the
    item's label and the series' label give (getRichItemNames, the item's
    first), each through setTokenTextStyle(rich model, global, the plain
    label, richInheritPlainLabel, opt, isNotNormal, attached, not a block,
    in rich), then convertToEC4RichItem over itself -- the ec4 keys added
    beside the ec5 ones. matrix-confusion's and matrix-periodic-table's
    formatters write rich text. nil: no rich at all. }
  function RichOf(const AInherit: string): TJSONObject;
  const
    cWithGlobal: array[0..7] of string = ('fontStyle', 'fontWeight', 'fontSize',
      'fontFamily', 'textShadowColor', 'textShadowBlur', 'textShadowOffsetX',
      'textShadowOffsetY');
    cSelf: array[0..6] of string = ('align', 'lineHeight', 'width', 'height',
      'tag', 'verticalAlign', 'ellipsis');
    cBox: array[0..9] of string = ('padding', 'borderWidth', 'borderRadius',
      'borderDashOffset', 'backgroundColor', 'borderColor', 'shadowColor',
      'shadowBlur', 'shadowOffsetX', 'shadowOffsetY');
    cEc4: array[0..20, 0..1] of string = (('lineWidth', 'textStrokeWidth'),
      ('font', 'font'), ('fontStyle', 'fontStyle'), ('fontWeight', 'fontWeight'),
      ('fontSize', 'fontSize'), ('fontFamily', 'fontFamily'), ('align', 'textAlign'),
      ('verticalAlign', 'textVerticalAlign'), ('lineHeight', 'textLineHeight'),
      ('width', 'textWidth'), ('height', 'textHeight'),
      ('backgroundColor', 'textBackgroundColor'), ('padding', 'textPadding'),
      ('borderColor', 'textBorderColor'), ('borderWidth', 'textBorderWidth'),
      ('borderRadius', 'textBorderRadius'), ('shadowColor', 'textBoxShadowColor'),
      ('shadowBlur', 'textBoxShadowBlur'), ('shadowOffsetX', 'textBoxShadowOffsetX'),
      ('shadowOffsetY', 'textBoxShadowOffsetY'), ('textShadowColor', 'textShadowColor'));
  var
    names: TStringList;
    tok: TJSONObject;
    nm: string;
    i, k: Integer;
    dd: TJSONData;

    function LabelNode(ARoot: TJSONObject): TJSONObject;
    begin
      Result := nil;
      if ARoot = nil then Exit;
      if AEmphasis then Result := CuObj(CuObj(ARoot, 'emphasis'), 'label')
      else Result := CuObj(ARoot, 'label');
    end;

    procedure AddNames(ALabel: TJSONObject);
    var rr: TJSONObject; j: Integer;
    begin
      rr := CuObj(ALabel, 'rich');
      if rr = nil then Exit;
      for j := 0 to rr.Count - 1 do
        if names.IndexOf(rr.Names[j]) < 0 then names.Add(rr.Names[j]);
    end;

    { the rich model's own key: the item's label's, else the series' }
    function RichKey(const AKey: string): TJSONData;
    begin
      if AEmphasis then Result := Lookup(item, Node, ['emphasis', 'label', 'rich', nm, AKey])
      else Result := Lookup(item, Node, ['label', 'rich', nm, AKey]);
    end;

    { the global textStyle -- none for a state that is not normal }
    function Glob(const AKey: string): TJSONData;
    begin
      if AEmphasis then Result := nil else Result := GlobalText(AKey);
    end;

    procedure PutC(const AKey: string; AVal: TJSONData);
    begin
      if AVal <> nil then CuPut(tok, AKey, AVal.Clone);
    end;

  begin
    Result := nil;
    names := TStringList.Create;
    try
      names.CaseSensitive := True;
      AddNames(LabelNode(item));
      AddNames(LabelNode(Node));
      if names.Count = 0 then Exit;
      Result := TJSONObject.Create;
      for i := 0 to names.Count - 1 do
      begin
        nm := names[i];
        tok := TJSONObject.Create;
        Result.Add(nm, tok);
        { fill and stroke: 'inherit' / 'auto' the inherited colour or none;
          attached -- no global colour }
        dd := RichKey('color');
        if (dd <> nil) and (dd.JSONType = jtString)
          and ((dd.AsString = 'inherit') or (dd.AsString = 'auto')) then
        begin
          if AInherit <> '' then tok.Add('fill', AInherit);
        end
        else PutC('fill', dd);
        dd := RichKey('textBorderColor');
        if (dd <> nil) and (dd.JSONType = jtString)
          and ((dd.AsString = 'inherit') or (dd.AsString = 'auto')) then
        begin
          if AInherit <> '' then tok.Add('stroke', AInherit);
        end
        else PutC('stroke', dd);
        dd := RichKey('textBorderWidth');
        if dd = nil then dd := Glob('textBorderWidth');
        PutC('lineWidth', dd);
        dd := RichKey('textBorderType');
        if dd = nil then dd := Glob('textBorderType');
        PutC('lineDash', dd);
        dd := RichKey('textBorderDashOffset');
        if dd = nil then dd := Glob('textBorderDashOffset');
        PutC('lineDashOffset', dd);
        dd := RichKey('opacity');
        if dd = nil then dd := Glob('opacity');
        PutC('opacity', dd);
        { inherited from the plain label (richInheritPlainLabel) }
        for k := 0 to High(cWithGlobal) do
        begin
          dd := RichKey(cWithGlobal[k]);
          if dd = nil then dd := LabelOf(cWithGlobal[k]);
          if dd = nil then dd := Glob(cWithGlobal[k]);
          PutC(cWithGlobal[k], dd);
        end;
        for k := 0 to High(cSelf) do PutC(cSelf[k], RichKey(cSelf[k]));
        if tok.Find('verticalAlign') = nil then PutC('verticalAlign', RichKey('baseline'));
        for k := 0 to High(cBox) do PutC(cBox[k], RichKey(cBox[k]));
        PutC('borderDash', RichKey('borderType'));
        for k := 0 to 1 do
        begin
          if k = 0 then nm := 'backgroundColor' else nm := 'borderColor';
          dd := tok.Find(nm);
          if (dd <> nil) and (dd.JSONType = jtString) and (AInherit <> '')
            and ((dd.AsString = 'auto') or (dd.AsString = 'inherit')) then
            CuPut(tok, nm, TJSONString.Create(AInherit));
        end;
        nm := names[i];
        { convertToEC4RichItem(richItem, richItem): the ec4 names beside }
        if tok.Find('fill') <> nil then CuPut(tok, 'textFill', tok.Find('fill').Clone);
        if tok.Find('stroke') <> nil then
        begin
          if tok.Find('fill') <> nil then CuPut(tok, 'textStroke', tok.Find('fill').Clone)
          else CuPut(tok, 'textStroke', TJSONNull.Create);
        end;
        for k := 0 to High(cEc4) do
          if tok.Find(cEc4[k, 0]) <> nil then
            CuPut(tok, cEc4[k, 1], tok.Find(cEc4[k, 0]).Clone);
      end;
    finally
      names.Free;
    end;
  end;

begin
  item := ItemNode(ARow);
  Result := TJSONObject.Create;
  { getItemStyle }
  for i := 0 to High(cItem) do
  begin
    d := ItemStyleOf(cItem[i, 1]);
    if d = nil then Continue;
    { borderType: getLineDash -- only a dash pattern is a lineDash }
    if cItem[i, 1] = 'borderType' then
    begin
      if not (d is TJSONArray) then Continue;
    end;
    Result.Add(cItem[i, 0], d.Clone);
  end;
  vis := nil;
  if not AEmphasis then
  begin
    { the visual's fill and opacity over it }
    vis := Chart.CustomVisualFill(Slot, ARow);
    if vis <> nil then CuPut(Result, 'fill', vis.Clone);
    { the visual style's opacity: the itemStyle's, a visualMap's over it
      [Batch 124] }
    if Chart.CustomVisualRow(Slot, ARow, vrow) and vrow.OpacitySet then
      CuPut(Result, 'opacity', TJSONFloatNumber.Create(vrow.Opacity))
    else
    begin
      d := ItemStyleOf('opacity');
      if d <> nil then CuPut(Result, 'opacity', d.Clone);
    end;
  end;
  try
    { createTextStyle(labelModel, null, opt with inheritColor, isNotNormal,
      true) }
    ts := TJSONObject.Create;
    tc := TJSONObject.Create;
    try
      d := LabelOf('color');
      if d <> nil then
      begin
        if (d.JSONType = jtString) and (d.AsString = 'inherit') then
        begin
          if (vis <> nil) and (vis.JSONType = jtString) then ts.Add('fill', vis.AsString)
          else ts.Add('fill', '#000');
        end
        else
          ts.Add('fill', d.Clone);
      end;
      for k := 0 to High(cFonts) do
      begin
        d := LabelOf(cFonts[k]);
        if (d = nil) and not AEmphasis then d := GlobalText(cFonts[k]);
        if d <> nil then ts.Add(cFonts[k], d.Clone);
      end;
      d := LabelOf('align');
      if d <> nil then ts.Add('align', d.Clone);
      d := LabelOf('verticalAlign');
      if d <> nil then ts.Add('verticalAlign', d.Clone);
      d := LabelOf('lineHeight');
      if d <> nil then ts.Add('lineHeight', d.Clone);
      d := LabelOf('textBorderColor');
      if d <> nil then ts.Add('stroke', d.Clone);
      d := LabelOf('textBorderWidth');
      if d <> nil then ts.Add('lineWidth', d.Clone);
      { the text: shown, the default label (the label dimensions' values):
        getDefaultLabel -- [R2-J] undefined with no label dimension (a
        matrix's x and y are categories) and null for the one dimension's
        null; several are joined, a null one as ''.
        [R2-J2] THE FORMATTER FIRST: retrieve2(getFormattedLabel(NORMAL),
        default) for style, retrieve3(EMPHASIS, NORMAL, default) for
        styleEmphasis -- matrix-confusion's and matrix-periodic-table's
        cells take their text from one. }
      show := CuTruthy(LabelOf('show'));
      hasText := False;
      txt := '';
      if show and (FormattedLabel(ARow, AEmphasis, txt)
        or (AEmphasis and FormattedLabel(ARow, False, txt))) then
        hasText := True
      else if show then
      begin
        if Store.HasLabelPositions then cells := Store.LabelPositions else cells := nil;
        hasText := Length(cells) > 0;
        for k := 0 to High(cells) do
        begin
          if not TTyDataStore.RawCell(Store.RawItem(ARow), cells[k], cell) then
            cell := Default(TTyDataValue);
          if (Length(cells) = 1) and (cell.Kind = dvkNone) then hasText := False;
          if k > 0 then txt := txt + ' ';
          txt := txt + TyJsValueText(cell, '');
        end;
      end;
      { createTextConfig }
      d := LabelOf('position');
      if d <> nil then tc.Add('position', d.Clone);
      d := LabelOf('distance');
      if d <> nil then tc.Add('distance', d.Clone)
      else if not AEmphasis then tc.Add('distance', 5);
      d := LabelOf('offset');
      if d <> nil then tc.Add('offset', d.Clone);
      d := LabelOf('rotate');
      if (d <> nil) and (d.JSONType = jtNumber) then tc.Add('rotation', d.AsFloat * Pi / 180);
      { preFetchFromExtra }
      if AExtra <> nil then
      begin
        if CuTruthy(AExtra.Find('textFill')) then CuPut(Result, 'textFill', AExtra.Find('textFill').Clone);
        if CuTruthy(AExtra.Find('textPosition')) then
          CuPut(Result, 'textPosition', AExtra.Find('textPosition').Clone);
      end;
      { convertToEC4StyleForCustomSerise }
      posD := Result.Find('textPosition');
      if not CuTruthy(posD) then
      begin
        if CuTruthy(tc.Find('position')) then CuPut(Result, 'textPosition', tc.Find('position').Clone)
        else CuPut(Result, 'textPosition', TJSONString.Create('inside'));
      end;
      if not CuNull(tc.Find('offset')) then CuPut(Result, 'textOffset', tc.Find('offset').Clone);
      if not CuNull(tc.Find('rotation')) then CuPut(Result, 'textRotation', tc.Find('rotation').Clone);
      if not CuNull(tc.Find('distance')) then CuPut(Result, 'textDistance', tc.Find('distance').Clone);
      posD := Result.Find('textPosition');
      isInside := (posD <> nil) and (posD.JSONType = jtString)
        and (Pos('inside', posD.AsString) > 0);
      { convertToEC4RichItem(out, textStyle): fill to textFill and -- as
        upstream writes it -- a stroke to textStroke as the fill }
      if ts.IndexOfName('fill') >= 0 then CuPut(Result, 'textFill', ts.Find('fill').Clone);
      if ts.IndexOfName('stroke') >= 0 then
      begin
        if ts.IndexOfName('fill') >= 0 then CuPut(Result, 'textStroke', ts.Find('fill').Clone)
        else CuPut(Result, 'textStroke', TJSONNull.Create);
      end;
      for k := 0 to High(cRich) do
        if ts.IndexOfName(cRich[k, 0]) >= 0 then
          CuPut(Result, cRich[k, 1], ts.Find(cRich[k, 0]).Clone);
      if CuNull(Result.Find('textFill')) then
      begin
        if isInside then
        begin
          CuPut(Result, 'textFill', TJSONString.Create('#fff'));
          if not CuTruthy(Result.Find('textStroke')) then
          begin
            d := Result.Find('fill');
            if CuTruthy(d) then CuPut(Result, 'textStroke', d.Clone)
            else CuPut(Result, 'textStroke', TJSONString.Create('#000'));
          end;
          if CuNull(Result.Find('textStrokeWidth')) then
            CuPut(Result, 'textStrokeWidth', TJSONIntegerNumber.Create(2));
        end
        else
        begin
          d := Result.Find('fill');
          if CuTruthy(d) then CuPut(Result, 'textFill', d.Clone)
          else CuPut(Result, 'textFill', TJSONString.Create('#000'));
        end;
      end;
      { [R2-J] an inside label whose fill IS set gets no stroke: the host's
        fill as its stroke (and a stroke width of 2) belongs to the default
        fill only -- styleCompat.ts' textFillNotSet branch. A label colour
        written under the label (matrix-periodic-table's #555) drew outlined
        in the series colour. }
      if hasText then CuPut(Result, 'text', TJSONString.Create(txt))
      else CuPut(Result, 'text', TJSONNull.Create);
      { [R2-J2] out.rich = txStl.rich }
      if (vis <> nil) and (vis.JSONType = jtString) then inh := vis.AsString
      else if AEmphasis then inh := ''
      else inh := '#000';
      richObj := RichOf(inh);
      if richObj <> nil then CuPut(Result, 'rich', richObj);
    finally
      ts.Free;
      tc.Free;
    end;
  finally
    vis.Free;
  end;
  { applyUserPropsAfter }
  if AExtra <> nil then
    for i := 0 to AExtra.Count - 1 do CuPut(Result, AExtra.Names[i], AExtra.Items[i].Clone);
  CuPut(Result, 'legacy', TJSONBoolean.Create(True));
end;

function TTyChartCustomApi.Style(AExtra: TJSONObject; ADataIndexInside: Integer): TJSONObject;
var r: Integer;
begin
  if not Row(ADataIndexInside, r) then r := -1;
  Result := MakeStyle(AExtra, r, False);
end;

function TTyChartCustomApi.StyleEmphasis(AExtra: TJSONObject; ADataIndexInside: Integer): TJSONObject;
var r: Integer;
begin
  if not Row(ADataIndexInside, r) then r := -1;
  Result := MakeStyle(AExtra, r, True);
end;

{ the style visual's fill and stroke; the item visuals a visualMap sets --
  symbol, symbolSize, liftZ [Batch 124]; the item's decal, a copy of the
  object (F4a); the rest a custom series has none of }
function TTyChartCustomApi.Visual(const AType: string; ADataIndexInside: Integer): TJSONData;
var
  r: Integer;
  vr: TTyVisualRow;
begin
  Result := nil;
  if not Row(ADataIndexInside, r) then r := -1;
  if AType = 'color' then Result := Chart.CustomVisualFill(Slot, r)
  else if AType = 'borderColor' then
  begin
    Result := Lookup(ItemNode(r), Node, ['itemStyle', 'borderColor']);
    if Result <> nil then Result := Result.Clone;
  end
  else if AType = 'decal' then
  begin
    { the item's decal visual, through getItemVisual's fallback to the
      series' [F4a] }
    if r >= 0 then Result := Chart.RowDecalJson(Slot, Store.GetRawIndex(r))
    else Result := Chart.RowDecalJson(Slot, -1);
  end
  else if Chart.CustomVisualRow(Slot, r, vr) then
  begin
    if (AType = 'symbol') and vr.SymbolSet then Result := TJSONString.Create(vr.Symbol)
    else if (AType = 'symbolSize') and vr.SizeSet and vr.SizePair then
      Result := TJSONArray.Create([vr.Size, vr.SizeH])
    else if (AType = 'symbolSize') and vr.SizeSet then Result := TJSONFloatNumber.Create(vr.Size)
    else if (AType = 'liftZ') and vr.LiftZSet then Result := TJSONFloatNumber.Create(vr.LiftZ);
  end;
end;

{ computeBarLayoutForCustomSeries on the base axis: a category axis' band,
  anything else -- and every other coordinate system -- undefined }
function TTyChartCustomApi.BarLayout(AOpt: TJSONObject): TTyCustomBarLayout;
var b: TTySeriesBinding;
begin
  Result := nil;
  if Sys <> cusCart then Exit;
  b := Chart.FBindings[Slot];
  if (b.BaseAxis = nil) or (b.BaseAxis.AxisType <> atCategory) then Exit;
  Result := TyCustomBarLayout(b.BaseAxis.BandWidth / Scale, AOpt);
end;

function TTyChartCustomApi.CurrentSeriesIndices: TTyIntegerArray;
var i, j, n, t: Integer;
begin
  Result := nil;
  n := 0;
  for i := 0 to High(Chart.FBindings) do
  begin
    if Chart.FBindings[i].Hidden or (Chart.FBindings[i].SeriesIndex < 0) then Continue;
    SetLength(Result, n + 1);
    Result[n] := Chart.FBindings[i].SeriesIndex;
    Inc(n);
  end;
  { eachSeries: by series index }
  for i := 1 to n - 1 do
  begin
    t := Result[i];
    j := i - 1;
    while (j >= 0) and (Result[j] > t) do
    begin
      Result[j + 1] := Result[j];
      Dec(j);
    end;
    Result[j + 1] := t;
  end;
end;

{ labelStyle.getFont over the global text style }
function TTyChartCustomApi.Font(AOpt: TJSONObject): string;

  function Part(const AKey, ADefault: string): string;
  var d: TJSONData;
  begin
    d := nil;
    if AOpt <> nil then d := AOpt.Find(AKey);
    if not CuTruthy(d) then d := GlobalText(AKey);
    if CuTruthy(d) then Result := CuText(d) else Result := ADefault;
  end;

begin
  Result := Trim(Part('fontStyle', '') + ' ' + Part('fontWeight', '') + ' '
    + Part('fontSize', '12') + 'px ' + Part('fontFamily', 'sans-serif'));
end;

function TTyChartCustomApi.GetWidth: Double;
begin
  Result := (Chart.FLastRect.Right - Chart.FLastRect.Left) / Scale;
end;

function TTyChartCustomApi.GetHeight: Double;
begin
  Result := (Chart.FLastRect.Bottom - Chart.FLastRect.Top) / Scale;
end;

function TTyChartCustomApi.GetDevicePixelRatio: Double;
begin
  Result := Scale;
end;

{ the style visual's fill of a row: the item's own itemStyle colour, the
  series', else its palette colour -- as written where it was written }
function TTyAdvanceChart.CustomVisualFill(ASlot, ARow: Integer): TJSONData;
var
  node, item: TJSONObject;
  d: TJSONData;
  raw, si: Integer;
  vr: TTyVisualRow;
begin
  Result := nil;
  if (FOption = nil) or (ASlot < 0) or (ASlot > High(FBindings)) then Exit;
  { A VISUALMAP'S COLOUR over the item's and the series' (visualEncoding runs
    after the style visuals): a piece's as written, a computed one as its
    rgba() text, an undefined one undefined [Batch 124] }
  if CustomVisualRow(ASlot, ARow, vr) and vr.ColorSet then
  begin
    if vr.ColorText <> '' then Exit(TJSONString.Create(vr.ColorText));
    if vr.Color.Defined then Exit(TJSONString.Create(TyVisualCss(vr.Color)));
    Exit;
  end;
  si := FBindings[ASlot].SeriesIndex;
  d := FOption.ComponentAt('series', si);
  if not (d is TJSONObject) then Exit;
  node := TJSONObject(d);
  item := nil;
  if (ARow >= 0) and (ASlot <= High(FStores)) and (FStores[ASlot] <> nil)
    and (ARow < FStores[ASlot].Count) then
  begin
    raw := FStores[ASlot].GetRawIndex(ARow);
    d := node.Find('data');
    if (d is TJSONArray) and (raw >= 0) and (raw < d.Count)
      and (TJSONArray(d).Items[raw] is TJSONObject) then
      item := TJSONObject(TJSONArray(d).Items[raw]);
  end;
  d := nil;
  if item <> nil then
  begin
    d := item.FindPath('itemStyle.color');
    if CuNull(d) or ((d.JSONType = jtString) and (d.AsString = 'auto')) then d := nil;
  end;
  if d = nil then
  begin
    d := node.FindPath('itemStyle.color');
    if CuNull(d) or ((d.JSONType = jtString) and (d.AsString = 'auto')) then d := nil;
  end;
  if d <> nil then Exit(d.Clone);
  if (si >= 0) and (si <= High(FSeriesColorNone)) and FSeriesColorNone[si] then
    Exit(TJSONString.Create('none'));
  Result := TJSONString.Create(TyCustomColorText(Cardinal(SeriesColor(si))));
end;

procedure TTyAdvanceChart.CustomDims(ASlot: Integer; var ADims: TTySeriesDimArray);
var
  node, enc: TJSONObject;
  d, names: TJSONData;
  outDims: TTySeriesDimArray;
  dim: TTySeriesDim;
  i, k, n: Integer;
  pos: TTyIntegerArray;
  spread: Boolean;

  function PosOf(A: TJSONData): Integer;
  var q: Integer; e: TJSONData; nm: string;
  begin
    Result := -1;
    if A = nil then Exit;
    if A.JSONType = jtNumber then Exit(Trunc(A.AsFloat));
    if (A.JSONType <> jtString) or not (names is TJSONArray) then Exit;
    for q := 0 to names.Count - 1 do
    begin
      e := TJSONArray(names).Items[q];
      if e.JSONType = jtString then nm := e.AsString
      else if (e is TJSONObject) and (TJSONObject(e).Find('name') <> nil) then
        nm := CuText(TJSONObject(e).Find('name'))
      else nm := '';
      if nm = A.AsString then Exit(q);
    end;
  end;

  procedure Positions(A: TJSONData);
  var q, p: Integer;
  begin
    pos := nil;
    if A = nil then Exit;
    if A is TJSONArray then
    begin
      for q := 0 to A.Count - 1 do
      begin
        p := PosOf(A.Items[q]);
        if p < 0 then Continue;
        SetLength(pos, Length(pos) + 1);
        pos[High(pos)] := p;
      end;
    end
    else
    begin
      p := PosOf(A);
      if p >= 0 then
      begin
        SetLength(pos, 1);
        pos[0] := p;
      end;
    end;
  end;

begin
  if FBindings[ASlot].SeriesType <> TyCustomSeriesType then Exit;
  if FOption = nil then Exit;
  d := FOption.ComponentAt('series', FBindings[ASlot].SeriesIndex);
  if not (d is TJSONObject) then Exit;
  node := TJSONObject(d);
  enc := CuObj(node, 'encode');
  if enc = nil then Exit;
  names := node.Find('dimensions');
  spread := False;
  for i := 0 to High(ADims) do
  begin
    Positions(enc.Find(ADims[i].Name));
    if Length(pos) > 1 then spread := True;
  end;
  if not spread then Exit;
  { EVERY POSITION THE ENCODE NAMES IS A COLUMN, each feeding its
    coordinate: both ends of a span size the axis and both are what a
    dataZoom filters on }
  outDims := nil;
  n := 0;
  for i := 0 to High(ADims) do
  begin
    Positions(enc.Find(ADims[i].Name));
    if Length(pos) = 0 then
    begin
      SetLength(outDims, n + 1);
      outDims[n] := ADims[i];
      Inc(n);
      Continue;
    end;
    for k := 0 to High(pos) do
    begin
      dim := ADims[i];
      if k > 0 then dim.Name := ADims[i].Name + IntToStr(k);
      dim.SourceSlot := pos[k] + 1;
      dim.Coord := ADims[i].Name;
      SetLength(outDims, n + 1);
      outDims[n] := dim;
      Inc(n);
    end;
  end;
  ADims := outDims;
end;

procedure TTyAdvanceChart.SolveCustom(APPI: Integer);
var
  i, si, n, p, c, k: Integer;
  view: TTyCustomView;
  node: TJSONObject;
  d: TJSONData;
  key, spec, coord: string;
  ids: TTyStringArray;
  raws: TTyIntegerArray;
  api: TTyChartCustomApi;
  scale, z, zl, lw, x, y, cw, ch, r0, r1: Double;
  area: TTyXYWH;
  st: TTyDataStore;
  alive: TTyBoolArray;
  arr: TJSONArray;
  sys: TTyCuSys;
  names: array of string;
  anim: TTyCustomAnim;
  cal: TTyCalendar;
  pol: TTyPolar;
  sgl: TTySingle;
  mtx: TTyMatrix;
  isCoord: Boolean;

  { getDateInfo's text fields of a range end }
  function CalDate(const AInfo: TTyCalDateInfo): TTyCustomCalDate;

    function Two(AN: Integer): string;
    begin
      if AN < 10 then Result := '0' + IntToStr(AN) else Result := IntToStr(AN);
    end;

  begin
    Result := Default(TTyCustomCalDate);
    Result.Y := IntToStr(AInfo.Y);
    Result.M := Two(AInfo.M);
    Result.D := Two(AInfo.D);
    Result.Day := AInfo.Day;
    Result.Time := AInfo.Time;
    Result.FormatedDate := Result.Y + '-' + Result.M + '-' + Result.D;
  end;

begin
  if APPI > 0 then scale := APPI / 96 else scale := 1;
  if FOption = nil then n := 0 else n := FOption.ComponentCount('series');
  { the views of series that are gone, or are another series now }
  alive := nil;
  SetLength(alive, Max(n, Length(FCustomViews)));
  for i := 0 to High(FBindings) do
    if (FBindings[i].SeriesType = TyCustomSeriesType) and (FBindings[i].SeriesIndex >= 0) then
      alive[FBindings[i].SeriesIndex] := True;
  for i := 0 to High(FCustomViews) do
    if (FCustomViews[i] <> nil) and ((i >= n) or not alive[i]
      or (FCustomViews[i].Key <> FOption.ComponentId('series', i) + #1 + TyCustomSeriesType)) then
      FreeAndNil(FCustomViews[i]);
  if Length(FCustomViews) < n then SetLength(FCustomViews, n);
  FCustomClipOn := nil;
  FCustomClip := nil;
  SetLength(FCustomClipOn, Length(FBindings));
  SetLength(FCustomClip, Length(FBindings));
  for i := 0 to High(FBindings) do
  begin
    if FBindings[i].SeriesType <> TyCustomSeriesType then Continue;
    si := FBindings[i].SeriesIndex;
    if (si < 0) or (si >= n) then Continue;
    key := FOption.ComponentId('series', si) + #1 + TyCustomSeriesType;
    view := FCustomViews[si];
    if view = nil then
    begin
      view := TTyCustomView.Create;
      view.Key := key;
      FCustomViews[si] := view;
    end;
    st := nil;
    if i <= High(FStores) then st := FStores[i];
    { THE COORDINATE SYSTEM, the prepareCustom it has [Batch 124]: a
      cartesian, a polar, a single axis, a calendar -- or none at all }
    sys := cusUnknown;
    pol := nil;
    sgl := nil;
    cal := nil;
    mtx := nil;
    if FBindings[i].Cart <> nil then sys := cusCart
    else if FBindings[i].Polar <> nil then
    begin
      sys := cusPolar;
      pol := TTyPolar(FBindings[i].Polar);
    end
    else if FBindings[i].Single <> nil then
    begin
      sys := cusSingle;
      sgl := TTySingle(FBindings[i].Single);
    end
    else if (FBindings[i].CalendarIndex >= 0) and (FBindings[i].CalendarIndex <= High(FCalendars))
      and (FCalendars[FBindings[i].CalendarIndex] <> nil) then
    begin
      sys := cusCalendar;
      cal := FCalendars[FBindings[i].CalendarIndex];
    end
    { a matrix: prepareCustom's rect, api.coord / api.layout [Batch 147] }
    else if (FBindings[i].MatrixIndex >= 0) and not FBindings[i].MatrixBox
      and (FBindings[i].MatrixIndex <= High(FMatrices))
      and (FMatrices[FBindings[i].MatrixIndex] <> nil) then
    begin
      sys := cusMatrix;
      mtx := FMatrices[FBindings[i].MatrixIndex];
    end
    { a geo [Batch 152] }
    else if GeoOfSlot(i) <> nil then sys := cusGeo
    else if CustomOnNone(i) then sys := cusNone;
    { NOT RENDERED: a series the legend switched off has its group emptied
      (ChartView.remove) and keeps its data; one on a coordinate system with
      no prepareCustom is not drawn }
    if FBindings[i].Hidden or (not FBindings[i].Resolved) or (sys = cusUnknown)
      or (st = nil) then
    begin
      view.RemoveAll;
      { A COORDINATE SYSTEM WITH NO prepareCustom (a radar, a graph's view):
        upstream asserts in its development build and calls undefined in its
        production one; nothing is drawn and the chart says so. A matrix
        does not resolve at all (its binding said so); a geo has its
        prepareCustom [Batch 152]. }
      if FBindings[i].Resolved and not FBindings[i].Hidden and (sys = cusUnknown) then
        FBuild.Note(Format(rsTyChartSeriesCoordSys, [si, FBindings[i].CoordSysName]));
      Continue;
    end;
    d := FOption.ComponentAt('series', si);
    if not (d is TJSONObject) then Continue;
    node := TJSONObject(d);
    AnimRowKeys(st, ids, raws);
    { the handler }
    FCustomHandler := nil;
    spec := '';
    d := node.Find('renderItem');
    if (d <> nil) and (d.JSONType = jtString) then spec := d.AsString;
    if not TyChartFindRenderItem(spec, FCustomHandler) then
    begin
      FCustomHandler := nil;
      FBuild.Note(Format(rsTyChartCustomNoRenderItem, [si, spec]));
    end;
    FCustomMissing := spec;
    { the api and the params of this round }
    api := TTyChartCustomApi.Create;
    api.Chart := Self;
    api.Slot := i;
    api.Series := si;
    api.Store := st;
    api.Node := node;
    api.Current := -1;
    api.Scale := scale;
    api.Sys := sys;
    api.Polar := pol;
    api.Single := sgl;
    api.Calendar := cal;
    api.Matrix := mtx;
    api.Geo := GeoOfSlot(i);
    FCustomApi := api;
    FCustomSlot := i;
    FCustomParams := Default(TTyCustomParams);
    FCustomParams.Context := TJSONObject.Create;
    FCustomParams.SeriesId := FOption.ComponentId('series', si);
    FCustomParams.SeriesName := SeriesModelName(si);
    FCustomParams.SeriesIndex := si;
    FCustomParams.DataInsideLength := st.Count;
    FCustomParams.ActionType := FCustomAction;
    { coordSys: each system's prepareCustom, in css px }
    names := nil;
    case sys of
      cusCart:
        begin
          area := FBindings[i].Cart.GetArea;
          FCustomParams.CoordSys.Type_ := 'cartesian2d';
          FCustomParams.CoordSys.X := area.X / scale;
          FCustomParams.CoordSys.Y := area.Y / scale;
          FCustomParams.CoordSys.Width := area.W / scale;
          FCustomParams.CoordSys.Height := area.H / scale;
          SetLength(names, 2);
          names[0] := 'x';
          names[1] := 'y';
        end;
      cusPolar:
        begin
          { the radius extent, the lesser first }
          pol.AxisExtent(pol.RadiusAxis, r0, r1);
          if r0 > r1 then
          begin
            x := r0;
            r0 := r1;
            r1 := x;
          end;
          FCustomParams.CoordSys.Type_ := 'polar';
          FCustomParams.CoordSys.Cx := pol.CX / scale;
          FCustomParams.CoordSys.Cy := pol.CY / scale;
          FCustomParams.CoordSys.R := r1 / scale;
          FCustomParams.CoordSys.R0 := r0 / scale;
          SetLength(names, 2);
          names[0] := TyPolarRadiusDim;
          names[1] := TyPolarAngleDim;
        end;
      cusSingle:
        begin
          FCustomParams.CoordSys.Type_ := 'singleAxis';
          FCustomParams.CoordSys.X := sgl.Rect.X / scale;
          FCustomParams.CoordSys.Y := sgl.Rect.Y / scale;
          FCustomParams.CoordSys.Width := sgl.Rect.W / scale;
          FCustomParams.CoordSys.Height := sgl.Rect.H / scale;
          SetLength(names, 1);
          names[0] := TySingleDim;
        end;
      cusCalendar:
        begin
          FCustomParams.CoordSys.Type_ := 'calendar';
          FCustomParams.CoordSys.X := cal.Rect.X / scale;
          FCustomParams.CoordSys.Y := cal.Rect.Y / scale;
          FCustomParams.CoordSys.Width := cal.Rect.W / scale;
          FCustomParams.CoordSys.Height := cal.Rect.H / scale;
          FCustomParams.CoordSys.CellWidth := cal.CellW / scale;
          FCustomParams.CoordSys.CellHeight := cal.CellH / scale;
          FCustomParams.CoordSys.RangeStart := CalDate(cal.Range.Start);
          FCustomParams.CoordSys.RangeEnd := CalDate(cal.Range.Stop);
          FCustomParams.CoordSys.Weeks := cal.Range.Weeks;
          FCustomParams.CoordSys.DayCount := cal.Range.AllDay;
          SetLength(names, 2);
          names[0] := TyCalendarTimeDim;
          names[1] := TyCalendarValueDim;
        end;
      cusMatrix:
        begin
          { prepareCustom: the matrix rect; the coordinate dimensions are
            x, y and value }
          FCustomParams.CoordSys.Type_ := TyMatrixCoordSysName;
          FCustomParams.CoordSys.X := mtx.Rect.X / scale;
          FCustomParams.CoordSys.Y := mtx.Rect.Y / scale;
          FCustomParams.CoordSys.Width := mtx.Rect.W / scale;
          FCustomParams.CoordSys.Height := mtx.Rect.H / scale;
          SetLength(names, 3);
          names[0] := TyMatrixXDim;
          names[1] := TyMatrixYDim;
          names[2] := TyMatrixValueDim;
        end;
      { the map's data rect, not pixels, and the view's zoom [Batch 152] }
      cusGeo:
        begin
          FCustomParams.CoordSys.Type_ := 'geo';
          FCustomParams.CoordSys.X := GeoOfSlot(i).DataRect.X;
          FCustomParams.CoordSys.Y := GeoOfSlot(i).DataRect.Y;
          FCustomParams.CoordSys.Width := GeoOfSlot(i).DataRect.W;
          FCustomParams.CoordSys.Height := GeoOfSlot(i).DataRect.H;
          FCustomParams.CoordSys.Zoom := GeoOfSlot(i).Zoom;
          SetLength(names, 2);
          names[0] := TyGeoLngDim;
          names[1] := TyGeoLatDim;
        end;
    else
      begin
        { 'none': no coordSys, the dimensions getCoordSysDimDefs made }
        FCustomParams.CoordSys.Type_ := '';
        SetLength(names, 2);
        names[0] := 'x';
        names[1] := 'y';
      end;
    end;
    { wrapEncodeDef: every coordinate column's data dimension, by position }
    FCustomParams.Encode := TJSONObject.Create;
    for p := 0 to Max(st.RawWidth, st.DimCount) - 1 do
      for c := 0 to st.DimCount - 1 do
      begin
        if st.RawDimPos(c) <> p then Continue;
        coord := st.DimCoord(c);
        if coord = '' then coord := st.DimName(c);
        isCoord := False;
        for k := 0 to High(names) do
          if names[k] = coord then isCoord := True;
        if not isCoord then Continue;
        d := FCustomParams.Encode.Find(coord);
        if not (d is TJSONArray) then
        begin
          arr := TJSONArray.Create;
          FCustomParams.Encode.Add(coord, arr);
        end
        else
          arr := TJSONArray(d);
        arr.Add(p);
      end;
    d := node.Find('itemPayload');
    if CuTruthy(d) and (d is TJSONObject) then
      FCustomParams.ItemPayload := TJSONObject(d.Clone)
    else
      FCustomParams.ItemPayload := TJSONObject.Create;
    d := node.Find('z');
    if (d <> nil) and (d.JSONType = jtNumber) then z := d.AsFloat else z := 2;
    d := node.Find('zlevel');
    if (d <> nil) and (d.JSONType = jtNumber) then zl := d.AsFloat else zl := 0;
    { THE TRANSITIONS' MODEL is the series [Batch 124]: isAnimationEnabled
      (its data count against animationThreshold) under the chart's own
      switch, getAnimationConfig's timing with the update's payload }
    anim := Default(TTyCustomAnim);
    anim.Model := TyAnimSeriesModel(FOption.Root, si, st.Count);
    anim.Model.Payload := FAnimPayload;
    anim.Model.HasPayload := FAnimHasPayload;
    anim.Enabled := AnimAllowed and TyAnimIsEnabled(anim.Model);
    anim.Driver := FCuAnim;
    { [F3c] a series that transitions makes its items anew }
    view.UtRecreate := TyUtEnabled(node) or AnimUtNamed(si);
    try
      view.Render(ids, raws, @CustomCall, z, zl, anim);
    finally
      FreeAndNil(FCustomParams.Context);
      FreeAndNil(FCustomParams.Encode);
      FreeAndNil(FCustomParams.ItemPayload);
      FCustomApi := nil;
      FCustomHandler := nil;
      api.Free;
    end;
    if view.Error <> '' then FBuild.Note('series[' + IntToStr(si) + ']: ' + view.Error);
    { createGridClipPath: the grid's area widened by lineStyle.width, its
      width ceiled, a fractional x floored -- a cartesian's only (a polar's
      sector clip is not drawn here) }
    if (sys = cusCart) and CuTruthy(node.Find('clip')) then
    begin
      d := node.FindPath('lineStyle.width');
      if (d <> nil) and (d.JSONType = jtNumber) and not IsNan(d.AsFloat) then lw := d.AsFloat
      else lw := 0;
      x := area.X / scale - lw / 2;
      y := area.Y / scale - lw / 2;
      cw := area.W / scale + lw;
      ch := area.H / scale + lw;
      cw := Ceil(cw);
      if x <> Floor(x) then
      begin
        x := Floor(x);
        cw := cw + 1;
      end;
      FCustomClipOn[i] := True;
      FCustomClip[i] := TyXYWH(x, y, cw, ch);
    end;
  end;
  { THE FLUSH: upstream's setOption ends with a synchronous update that
    steps every clip the render made, so each starts NOW and this paint
    shows the from values [Batch 124] }
  if CuLive then
  begin
    FCuAnim.Update(AnimClock, True);
    AnimFlushOthers(FCuAnim);
    AnimArmTimer;
  end;
end;

{ renderItem for one item of the series being rendered }
function TTyAdvanceChart.CustomCall(AIndexInside: Integer): TJSONData;
var
  api: TTyChartCustomApi;
  nLine, nCol: Integer;
begin
  Result := nil;
  api := TTyChartCustomApi(FCustomApi);
  api.Current := AIndexInside;
  FCustomParams.DataIndexInside := AIndexInside;
  FCustomParams.DataIndex := api.Store.GetRawIndex(AIndexInside);
  if not Assigned(FCustomHandler) then Exit;
  try
    Result := FCustomHandler(FCustomParams, api);
  except
    on E: Exception do
    begin
      Result := nil;
      FBuild.Note(Format(rsTyChartCustomRenderItemFailed,
        [FCustomParams.SeriesIndex, FCustomMissing, E.Message]));
    end;
  end;
  { a tree too deep for the readers is no tree -- and the chart says so }
  if (Result <> nil) and TyJsonNestingExceeds(Result.AsJSON, TyOptionMaxNesting,
    nLine, nCol) then
  begin
    FreeAndNil(Result);
    FBuild.Note(Format(rsTyChartCustomRenderItemFailed, [FCustomParams.SeriesIndex,
      FCustomMissing, Format(rsTyOptTooDeep, [TyOptionMaxNesting])]));
  end;
end;

{ [F3c] a custom series' path tagged for the universal transition: the
  item's row, its place among the item's paths, its PathProxy data in its own
  frame and its computed transform (the device scale over it), its rect's or
  sector's shape for the dividers }
procedure CustomUtPath(var APe: TTyChartElement; AEl: TTyGfxEl; ASeries, ARow: Integer;
  var APlace: Integer; AScale: Double);

  function Sh(const AKey: string; ADefault: Double): Double;
  var d: TJSONData;
  begin
    d := AEl.Shape.Find(AKey);
    if (d <> nil) and (d.JSONType = jtNumber) then Result := d.AsFloat else Result := ADefault;
  end;

var
  k: Integer;
  d: TJSONData;
begin
  APe.Anim.Role := carCustomPath;
  APe.Anim.Series := ASeries;
  APe.Anim.Index := ARow;
  APe.Anim.Sub := APlace;
  Inc(APlace);
  APe.Anim.Pts := TyGuidePathData(TyGfxPath(AEl));
  { the item's element itself (no group above it in the item) }
  if (AEl.Parent <> nil) and (AEl.Parent.Parent = nil) then APe.Anim.G[7] := 1;
  if AEl.HasTransform then
  begin
    for k := 0 to 5 do APe.Anim.G[k] := AEl.Transform[k] * AScale;
    APe.Anim.G[6] := 1;
  end
  else if AScale <> 1 then
  begin
    APe.Anim.G[0] := AScale;
    APe.Anim.G[3] := AScale;
    APe.Anim.G[6] := 1;
  end;
  case AEl.Kind of
    gkRect:
      APe.Anim.Base := TTyDoubleArray.Create(1, Sh('x', 0), Sh('y', 0), Sh('width', 0),
        Sh('height', 0));
    gkSector:
      begin
        { the Sector's default shape under what the option wrote }
        d := AEl.Shape.Find('clockwise');
        if (d <> nil) and (d.JSONType = jtBoolean) and not d.AsBoolean then k := 0 else k := 1;
        APe.Anim.Base := TTyDoubleArray.Create(2, Sh('cx', 0), Sh('cy', 0), Sh('r0', 0),
          Sh('r', 0), Sh('startAngle', 0), Sh('endAngle', Pi * 2), k);
      end;
  end;
end;

function TTyAdvanceChart.CustomBuild(ASlot: Integer; AList: TTyPaintList;
  APPI: Integer): Integer;
var
  si, i, inside, raw, upath: Integer;
  view: TTyCustomView;
  root, el: TTyGfxEl;
  meas: ITyTextMeasurer;
  ground: TTyGfxGround;
  ctx: TTyGfxPaintCtx;
  scale, maxZ2: Double;
  datum: TTyChartDatumRef;
  clipOn: Boolean;
  clip: TTyRectF;
  all: TTyGfxElArray;
  decalSkin: TTyChartColor;

  { doUpdateZ over one item's tree: the running greatest z2 lifts each
    textContent to it + 2 }
  procedure UpdZ(AEl: TTyGfxEl);
  var k: Integer;
  begin
    if AEl.IsGroup then
    begin
      for k := 0 to High(AEl.Children) do UpdZ(AEl.Children[k]);
      Exit;
    end;
    if AEl.Z2 > maxZ2 then maxZ2 := AEl.Z2;
    if AEl.TextContent <> nil then
    begin
      AEl.TextContent.Z := AEl.Z;
      AEl.TextContent.ZLevel := AEl.ZLevel;
      if not IsInfinite(maxZ2) then AEl.TextContent.Z2 := maxZ2 + 2;
    end;
  end;

  procedure Add(AEl: TTyGfxEl; ASilent: Boolean);
  var
    pe: TTyChartElement;
    k: Integer;
    d: TJSONData;
  begin
    { A TEXT OF NO TEXT has no line, so no tspan, so nothing in the display
      list (parsePlainText: `text ? text.split('\n') : []`) -- the empty
      label an ec4 style makes when the label is not shown }
    if AEl.Kind = gkText then
    begin
      d := AEl.Style.Find('text');
      if (d = nil) or (d.JSONType = jtNull) or ((d.JSONType = jtString) and (d.AsString = '')) then
        Exit;
    end;
    if not TyGfxPaintElement(AEl, meas, ctx, pe) then Exit;
    { A PATH'S style.decal [F4a]: CustomView turns the decal object
      renderItem returned into its pattern -- api.visual('decal') or one
      written there; a text or an image takes none (isPath). A primitive
      (`'none'`) is no pattern here: upstream sets `dirty` on it and throws. }
    if not (AEl.Kind in [gkUnknown, gkGroup, gkImage, gkText]) and (AEl.Style <> nil) then
    begin
      d := AEl.Style.Find('decal');
      if d is TJSONObject then
        pe.Style.Decal := TyDecalResolve(TyDecalRawOf(d), decalSkin, DecalGround);
    end;
    pe.Silent := ASilent;
    pe.Datum := datum;
    pe.Z := Round(AEl.ZLevel) * 100000 + Round(AEl.Z);
    pe.Z2 := Round(AEl.Z2);
    if clipOn then
    begin
      pe.HasClip := True;
      pe.ClipRect := clip;
    end;
    { [F3c] AN ITEM'S PATH as getPathList finds it (no text, no image, not
      invisible, not `morph: false`), for the universal transition }
    if (AEl.Kind in [gkRect, gkCircle, gkEllipse, gkRing, gkSector, gkArc, gkPolygon,
      gkPolyline, gkLine, gkBezier, gkPath]) and not AEl.Invisible
      and not ((AEl.Custom is TTyCustomElInfo) and TTyCustomElInfo(AEl.Custom).NoMorph) then
      CustomUtPath(pe, AEl, si, inside, upath, scale);
    k := AList.Add(pe);
    if Length(FCustomPaintEls) <= k then SetLength(FCustomPaintEls, k + 1);
    FCustomPaintEls[k] := AEl;
    Inc(Result);
  end;

  procedure Walk(AEl: TTyGfxEl; ASilent: Boolean);
  var k: Integer; s: Boolean;
  begin
    if AEl.Ignore then Exit;
    s := ASilent or AEl.Silent;
    if AEl.IsGroup then
    begin
      for k := 0 to High(AEl.Children) do Walk(AEl.Children[k], s);
      Exit;
    end;
    Add(AEl, s);
    if (AEl.TextContent <> nil) and not AEl.TextContent.Ignore then
      Add(AEl.TextContent, s or AEl.TextContent.Silent);
  end;

begin
  Result := 0;
  si := FBindings[ASlot].SeriesIndex;
  view := CustomView(si);
  if (view = nil) or (ASlot > High(FStores)) or (FStores[ASlot] = nil) then Exit;
  if APPI <= 0 then APPI := 96;
  scale := APPI / 96;
  FCustomUtScale := scale;
  meas := NewTextMeasurer(96);
  decalSkin := TTyChartColor(ActiveController.Model.ResolveStyle(TyDecalSkin, '',
    []).TextColor);
  { the transforms and the textContents' places }
  TyGfxUpdateTransforms(view.Root);
  MarkerGround(ground.Background, ground.IsDark);
  all := nil;
  TyGfxTraverse(view.Root, all);
  for i := 0 to High(all) do
    if all[i].TextContent <> nil then
    begin
      TyGfxInnerText(all[i], meas, ground);
      TyGfxLabelTransform(all[i].TextContent, all[i].TextContent.HasTransform,
        all[i].TextContent.Transform);
    end;
  ctx := Default(TTyGfxPaintCtx);
  ctx.Scale := scale;
  ctx.HasInk := True;
  ctx.Ink := TTyChartColor(ActiveController.Model.ResolveStyle(GetStyleTypeKey,
    StyleClass, [tysNormal]).TextColor);
  ctx.ImageSize := @GfxImageSize;
  clipOn := (ASlot <= High(FCustomClipOn)) and FCustomClipOn[ASlot];
  if clipOn then
    clip := TyRectF(FCustomClip[ASlot].X * scale, FCustomClip[ASlot].Y * scale,
      (FCustomClip[ASlot].X + FCustomClip[ASlot].W) * scale,
      (FCustomClip[ASlot].Y + FCustomClip[ASlot].H) * scale);
  { which item each root draws }
  for i := 0 to FStores[ASlot].Count - 1 do
  begin
    el := view.ElOf(i);
    if el <> nil then el.Serial := i;
  end;
  for i := 0 to High(view.Root.Children) do
  begin
    root := view.Root.Children[i];
    inside := root.Serial;
    if (inside < 0) or (view.ElOf(inside) <> root) then Continue;
    raw := FStores[ASlot].GetRawIndex(inside);
    datum := TyChartDatum(si, inside, raw);
    maxZ2 := NegInfinity;
    UpdZ(root);
    upath := 0;
    Walk(root, False);
  end;
end;

{ a custom element's declared state, as its option wrote it: the style's
  fill, stroke, lineWidth and opacity, and the state's z2 }
function StCustomDecl(AInfo: TTyCustomElInfo; AName: TTyStName): TTyStObject;
var
  idx: Integer;
  st: TJSONObject;
  d: TJSONData;
  c: TTyChartColor;

  procedure Colour(const AKey: string; ASt: TTyStKey);
  begin
    d := st.Find(AKey);
    if d = nil then Exit;
    if (d.JSONType = jtNull) or ((d.JSONType = jtString) and TyChartColorIsNone(d.AsString)) then
      TyStSetNone(Result, ASt)
    else if (d.JSONType = jtString) and (d.AsString = 'inherit') and (ASt = stkFill) then
      Result.FillInherit := True
    else if (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, c) then
      TyStSetColor(Result, ASt, c);
  end;

begin
  Result := TyStNoObject;
  if AInfo = nil then Exit;
  case AName of
    stnEmphasis: idx := 0;
    stnBlur: idx := 1;
  else
    idx := 2;
  end;
  st := AInfo.StateStyle[idx];
  if st <> nil then
  begin
    Colour('fill', stkFill);
    Colour('stroke', stkStroke);
    d := st.Find('lineWidth');
    if (d <> nil) and (d.JSONType = jtNumber) then TyStSetNum(Result, stkLineWidth, d.AsFloat);
    d := st.Find('opacity');
    if (d <> nil) and (d.JSONType = jtNumber) then TyStSetNum(Result, stkOpacity, d.AsFloat);
  end;
  if not IsNan(AInfo.StateZ2[idx]) then TyStSetNum(Result, stkZ2, AInfo.StateZ2[idx]);
end;

{ a custom item's elements: every path of its tree has the three states
  updateElOnState gives it, the default proxy and the lift of 1 }
procedure TTyAdvanceChart.StDeclareCustom(ASlot, ARaw: Integer; AList: TTyPaintList);
var
  s, k: Integer;
  item: PTyStItem;
  was: Boolean;

  procedure Declare(var AEl: TTyStElement; AIdx: Integer);
  var
    gel: TTyGfxEl;
    info: TTyCustomElInfo;
    n: TTyStName;
  begin
    gel := CustomPaintSource(AIdx);
    info := nil;
    if (gel <> nil) and (gel.Custom is TTyCustomElInfo) then info := TTyCustomElInfo(gel.Custom);
    AEl.Exists := True;
    AEl.IsPath := True;
    AEl.Proxy := True;
    AEl.LiftOne := True;
    for n := Low(TTyStName) to High(TTyStName) do
    begin
      AEl.HasState[n] := True;
      AEl.Decl[n] := StCustomDecl(info, n);
    end;
    AEl.Rest := StRestOf(AList.Element(AIdx));
  end;

begin
  s := FBindings[ASlot].SeriesIndex;
  item := @FSt[s].Rows[ARaw];
  Declare(item^.Host, FSt[s].HostIdx[ARaw]);
  if Length(item^.Parts) <> Length(FSt[s].PartIdx[ARaw]) then SetLength(item^.Parts, 0);
  was := Length(item^.Parts) > 0;
  SetLength(item^.Parts, Length(FSt[s].PartIdx[ARaw]));
  for k := 0 to High(item^.Parts) do
  begin
    Declare(item^.Parts[k], FSt[s].PartIdx[ARaw][k]);
    if not was then
    begin
      item^.Parts[k].Cur := item^.Parts[k].Rest;
      item^.Parts[k].States := [];
      if item^.Host.States <> [] then TyStUseStates(item^.Parts[k], item^.Host.States);
    end;
  end;
end;
