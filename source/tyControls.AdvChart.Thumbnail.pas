unit tyControls.AdvChart.Thumbnail;
{$mode objfpc}{$H+}
{ TTyAdvanceChart -- the thumbnail, a small copy of a graph with the window
  the canvas shows. [Batch 140, D7]

  UPSTREAM'S component/thumbnail (ThumbnailModel.ts, ThumbnailView.ts,
  ThumbnailBridgeImpl.ts), helper/thumbnailBridge.ts and the copy
  GraphView._renderThumbnail takes, transcribed.

  THE BOX is the component's own: right 1, bottom 1, 25% wide and high by
  default (mergeLayoutParam at init, then getLayoutRect on the chart). The
  background rect is the box, filled with itemStyle.color, else the
  option's backgroundColor, else the neutral00 token (here the skin's
  TyAdvChartThumbnail background), rimmed by itemStyle (2 px of the border
  token by default). THE CONTENT RECT is the box shrunk by half that rim
  (expandOrShrinkRect, no negative sizes); it clips the copy.

  THE COPY is taken when the graph renders, never when it roams: every
  drawn node's symbol sub-path cloned with its shape set to the sub-path's
  scaleX / scaleY -- HALF the symbol size -- round the node's layout
  position, every drawn edge's line path cloned (its trimmed ends and its
  control point, NaN for a straight one), all at z2 151, styles as they
  stood. Its bounding rect (Path.getBoundingRect with no transform yet: the
  stroke at a line scale of one, at least five for a line without a fill;
  Group's union, an empty group's (0, 0, 0, 0) -- so a graph with no edges
  puts the origin in the rect) is the data rect of a View whose view rect is
  the content rect's centred rect of the same aspect (getLayoutRect with
  `aspect`: 0.8 of the side that binds).

  THE WINDOW is the canvas carried through the graph's inverse overall
  matrix and the thumbnail's overall one -- matrix.mul(thumb, invert(graph))
  -- and BoundingRect.applyTransform; toTarget is that product's inverse,
  which a drag on the thumbnail maps the pointer through (a pan's dx / dy is
  the difference of two mapped points, the old one and the old one less the
  move) and a wheel maps its origin through (zoom 1 / factor).

  PURE: SysUtils, Math, fpjson and the AdvChart units. No painter, no LCL. }
interface
uses
  SysUtils, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Paint,
  tyControls.AdvChart.Layout, tyControls.AdvChart.ZrPath,
  tyControls.AdvChart.Graph;

const
  TyThumbnailComponent = 'thumbnail';
  { the copy's z2 (GraphView._renderThumbnail), the background's and the
    window's: ten under and over the copy's range }
  TyThumbItemZ2 = 151;
  TyThumbZ = 10;
  TyThumbBorderWidth = 2;
  TyThumbWindowBorderWidth = 1;
  TyThumbWindowOpacity = 0.3;

type
  { a colour the option wrote, or none (the skin's token stands in) }
  TTyThumbInk = record
    Written: Boolean;
    Text: string;
  end;

  TTyThumbModel = record
    { shouldShow: the option's `show` (default true), truthy }
    Show: Boolean;
    Box: TTyRawBox;
    Fill, Border: TTyThumbInk;
    BorderWidth: Double;
    Opacity: Double;
    Radius: TTyDoubleArray;
    WinFill, WinBorder: TTyThumbInk;
    WinBorderWidth: Double;
    WinOpacity: Double;
    WinRadius: TTyDoubleArray;
    Z, ZLevel: Double;
    { getReferringComponents('series'): an index, an id, or neither (the
      first graph) }
    HasSeriesIndex: Boolean;
    SeriesIndex: Integer;
    HasSeriesId: Boolean;
    SeriesId: string;
  end;

  TTyThumbItemKind = (tikSymbol, tikLine);
  { ONE ELEMENT OF THE COPY, in the graph's layout space }
  TTyThumbItem = record
    Kind: TTyThumbItemKind;
    { a symbol: its type (`empty` taken off) and its rect }
    SymbolType: string;
    X, Y, W, H: Double;
    { a line: its ends and its control point (NaN: straight) }
    X1, Y1, X2, Y2, CPX, CPY: Double;
    HasFill: Boolean;
    Fill: TTyChartColor;
    HasStroke: Boolean;
    Stroke: TTyChartColor;
    LineWidth: Double;
    Opacity: Double;
    Dash: TTyDoubleArray;
    { [R2-I4] the dash's phase (the cloned style's lineDashOffset) }
    DashOffset: Double;
    { [R2-I5] the pen as a gradient (the cloned style's stroke object;
      cgkNone: a plain colour) [was: its first colour] }
    StrokeGradient: TTyChartGradient;
  end;
  TTyThumbItemArray = array of TTyThumbItem;

  { THE BRIDGE'S VIEW: the copy's rect fitted into the content rect }
  TTyThumbView = record
    Valid: Boolean;
    DataRect, ViewRect: TTyXYWH;
    { the copy group's transform (VIEW_COORD_SYS_TRANS_RAW) }
    TransX, TransY, TransSX, TransSY: Double;
    { the thumbnail's overall matrix, the graph's (the bridge's
      targetTrans) and the thumbnail-to-graph one }
    Overall, Target, ToTarget: TTyMat2D;
    HasToTarget: Boolean;
  end;

  { ONE THUMBNAIL COMPONENT as the view holds it }
  TTyThumbState = record
    Model: TTyThumbModel;
    { _isEnabled: shown and a graph to copy }
    Enabled: Boolean;
    { the series the model targets (getTarget, cached at optionUpdated), -1 }
    Target: Integer;
    Box, Content, Window: TTyXYWH;
    View: TTyThumbView;
    Items: TTyThumbItemArray;
    { the series' `roam` as the bridge carries it: its JavaScript text, and
      the controller's behaviours (a truthy roam enables it) }
    RoamText: string;
    RoamOn, RoamPan, RoamZoom: Boolean;
  end;
  TTyThumbStateArray = array of TTyThumbState;

{ the model: the option's keys over ThumbnailModel.defaultOption }
function TyThumbModelOf(ANode: TJSONObject): TTyThumbModel;
{ the box: mergeLayoutParam at init over right 1, bottom 1, 25% x 25%, then
  getLayoutRect on the viewport }
function TyThumbBox(ANode: TJSONObject; const AViewport: TTyRectF): TTyXYWH;
{ [Batch 154] the same in createBoxLayoutReference's container (a matrix
  cell or a calendar day; the canvas as x / y / width / height) }
function TyThumbBox(ANode: TJSONObject; const ARef: TTyXYWH): TTyXYWH;
{ the content rect: the box shrunk by half the rim }
function TyThumbContent(const ABox: TTyXYWH; ABorderWidth: Double): TTyXYWH;
{ the path an item builds (SymbolClz / ECLinePath.buildPath) }
function TyThumbItemPath(const AItem: TTyThumbItem): TTyZrPath;
{ Path.getBoundingRect of an item that has no transform yet }
function TyThumbItemRect(const AItem: TTyThumbItem): TTyXYWH;
{ the copy group's rect: the symbols' group, then the lines' group }
function TyThumbBridgeRect(const AItems: TTyThumbItemArray): TTyXYWH;
{ getLayoutRect with left and top 'center' and the aspect, on the container }
function TyThumbCentredAspect(const AContainer: TTyXYWH; AAspect: Double): TTyXYWH;
{ the bridge's view of AItems in AContent, against the graph's overall
  matrix ATarget }
function TyThumbFit(const AItems: TTyThumbItemArray; const AContent: TTyXYWH;
  const ATarget: TTyMat2D): TTyThumbView;
{ updateWindow: the graph's overall matrix now, the window on a W x H canvas
  and toTarget }
procedure TyThumbUpdateWindow(var AView: TTyThumbView; const ATarget: TTyMat2D;
  AW, AH: Double; out AWindow: TTyXYWH);
{ _onPan: the graphRoam dx / dy of a drag from (AOldX, AOldY) by (ADX, ADY) }
procedure TyThumbPanPayload(const AView: TTyThumbView; AOldX, AOldY, ADX,
  ADY: Double; out APDX, APDY: Double);
{ _onZoom: the graphRoam zoom and origin of a wheel of AScale at (AX, AY) }
procedure TyThumbZoomPayload(const AView: TTyThumbView; AScale, AX, AY: Double;
  out AZoom, AOX, AOY: Double);
{ BoundingRect.contain: closed on every side }
function TyThumbRectContains(const R: TTyXYWH; AX, AY: Double): Boolean;
{ createSymbol's type: `empty` taken off }
function TyThumbSymbolType(const AName: string): string;
{ the roam modes a truthy `roam` enables: true (or null) both, 'move' /
  'pan' the pan, 'scale' / 'zoom' the zoom }
procedure TyThumbRoamOf(AData: TJSONData; out AText: string; out AOn, APan,
  AZoom: Boolean);

implementation

uses tyControls.AdvChart.Calendar, tyControls.AdvChart.Scale;

function MaskFP: TFPUExceptionMask;
begin
  Result := SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
    exOverflow, exUnderflow, exPrecision]);
end;

{ the flags a masked operation raised are cleared before the mask goes
  back, or the next unmasked operation traps on them }
procedure UnmaskFP(const AMask: TFPUExceptionMask);
begin
  ClearExceptions(False);
  {$IFDEF CPUX86_64}
  SetMXCSR(GetMXCSR and not LongWord($3F));
  {$ENDIF}
  SetExceptionMask(AMask);
end;

function XYWH(AX, AY, AW, AH: Double): TTyXYWH;
begin
  Result.X := AX;
  Result.Y := AY;
  Result.W := AW;
  Result.H := AH;
end;

function ObjIn(ANode: TJSONObject; const AKey: string): TJSONObject;
var d: TJSONData;
begin
  Result := nil;
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if (d <> nil) and (d.JSONType = jtObject) then Result := TJSONObject(d);
end;

function InkIn(ANode: TJSONObject; const AKey: string): TTyThumbInk;
var d: TJSONData;
begin
  Result := Default(TTyThumbInk);
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if (d <> nil) and (d.JSONType = jtString) then
  begin
    Result.Written := True;
    Result.Text := d.AsString;
  end;
end;

{ a number key, ADefault where it is absent, nought where it is written as
  something else (the `|| 0` the rim goes through) }
function NumIn(ANode: TJSONObject; const AKey: string; ADefault: Double): Double;
var d: TJSONData;
begin
  Result := ADefault;
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if d = nil then Exit;
  if d.JSONType = jtNumber then Result := d.AsFloat
  else Result := 0;
end;

function RadiusIn(ANode: TJSONObject): TTyDoubleArray;
var d: TJSONData; i: Integer;
begin
  Result := nil;
  if ANode = nil then Exit;
  d := ANode.Find('borderRadius');
  if d = nil then Exit;
  if d.JSONType = jtNumber then
  begin
    SetLength(Result, 1);
    Result[0] := d.AsFloat;
  end
  else if d is TJSONArray then
  begin
    SetLength(Result, d.Count);
    for i := 0 to d.Count - 1 do
      if TJSONArray(d).Items[i].JSONType = jtNumber then
        Result[i] := TJSONArray(d).Items[i].AsFloat
      else Result[i] := 0;
  end;
end;

function JsTruthy(AData: TJSONData): Boolean;
begin
  if AData = nil then Exit(False);
  case AData.JSONType of
    jtNull: Result := False;
    jtBoolean: Result := AData.AsBoolean;
    jtNumber: Result := (not IsNan(AData.AsFloat)) and (AData.AsFloat <> 0);
    jtString: Result := AData.AsString <> '';
  else
    Result := True;
  end;
end;

function TyThumbModelOf(ANode: TJSONObject): TTyThumbModel;
var
  d: TJSONData;
  st: TJSONObject;
begin
  Result := Default(TTyThumbModel);
  { getShallow('show', true): the merged option's value, true by default }
  d := nil;
  if ANode <> nil then d := ANode.Find('show');
  if d = nil then Result.Show := True else Result.Show := JsTruthy(d);
  st := ObjIn(ANode, 'itemStyle');
  Result.Fill := InkIn(st, 'color');
  Result.Border := InkIn(st, 'borderColor');
  Result.BorderWidth := NumIn(st, 'borderWidth', TyThumbBorderWidth);
  Result.Opacity := NumIn(st, 'opacity', 1);
  Result.Radius := RadiusIn(st);
  st := ObjIn(ANode, 'windowStyle');
  Result.WinFill := InkIn(st, 'color');
  Result.WinBorder := InkIn(st, 'borderColor');
  Result.WinBorderWidth := NumIn(st, 'borderWidth', TyThumbWindowBorderWidth);
  Result.WinOpacity := NumIn(st, 'opacity', TyThumbWindowOpacity);
  Result.WinRadius := RadiusIn(st);
  Result.Z := NumIn(ANode, 'z', TyThumbZ);
  Result.ZLevel := NumIn(ANode, 'zlevel', 0);
  Result.SeriesIndex := -1;
  if ANode <> nil then
  begin
    d := ANode.Find('seriesIndex');
    if (d <> nil) and (d.JSONType <> jtNull) then
    begin
      Result.HasSeriesIndex := True;
      if (d is TJSONArray) and (d.Count > 0) then d := TJSONArray(d).Items[0];
      if (d.JSONType = jtNumber) and (Frac(d.AsFloat) = 0) and (d.AsFloat >= 0)
        and (d.AsFloat < MaxInt) then
        Result.SeriesIndex := Trunc(d.AsFloat);
    end;
    d := ANode.Find('seriesId');
    if (d <> nil) and (d.JSONType <> jtNull) then
    begin
      if (d is TJSONArray) and (d.Count > 0) then d := TJSONArray(d).Items[0];
      if d.JSONType = jtString then
      begin
        Result.HasSeriesId := True;
        Result.SeriesId := d.AsString;
      end
      else if d.JSONType = jtNumber then
      begin
        Result.HasSeriesId := True;
        Result.SeriesId := TyJsNumberToString(d.AsFloat);
      end;
    end;
  end;
end;

function BoxOwn(ANode: TJSONObject; const AKey: string): TTyCalBoxKey;
var d: TJSONData;
begin
  Result := Default(TTyCalBoxKey);
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if d = nil then Exit;
  Result.Own := True;
  Result.V := TyBoxRawOf(d);
end;

function TyThumbBox(ANode: TJSONObject; const AViewport: TTyRectF): TTyXYWH;
begin
  Result := TyThumbBox(ANode, TyXYWH(AViewport.Left, AViewport.Top,
    AViewport.Right - AViewport.Left, AViewport.Bottom - AViewport.Top));
end;

function TyThumbBox(ANode: TJSONObject; const ARef: TTyXYWH): TTyXYWH;
const
  cKey: array[0..5] of string = ('width', 'left', 'right', 'height', 'top', 'bottom');
var
  raw, target: TTyCalBoxKeys;
  box: TTyRawBox;
  k: Integer;
begin
  for k := 0 to 5 do raw[k] := BoxOwn(ANode, cKey[k]);
  target := raw;
  { the defaults under what the option wrote: width 25%, right 1, height
    25%, bottom 1 }
  if not target[0].Own then begin target[0].Own := True; target[0].V := TyBoxRawStr('25%'); end;
  if not target[2].Own then begin target[2].Own := True; target[2].V := TyBoxRawNum(1); end;
  if not target[3].Own then begin target[3].Own := True; target[3].V := TyBoxRawStr('25%'); end;
  if not target[5].Own then begin target[5].Own := True; target[5].V := TyBoxRawNum(1); end;
  TyCalMergeLayoutParam(target, raw, False, False);
  box := Default(TTyRawBox);
  box.Width := target[0].V;
  box.Left := target[1].V;
  box.Right := target[2].V;
  box.Height := target[3].V;
  box.Top := target[4].V;
  box.Bottom := target[5].V;
  Result := TyGetLayoutRect(box, ARef.X, ARef.Y, ARef.W, ARef.H, []);
end;

function TyThumbContent(const ABox: TTyXYWH; ABorderWidth: Double): TTyXYWH;
var m: TTyMargin4; k: Integer;
begin
  Result := ABox;
  for k := 0 to 3 do m[k] := ABorderWidth / 2;
  TyShrinkRect(Result, m, 0, 0);
end;

function TyThumbItemPath(const AItem: TTyThumbItem): TTyZrPath;
var seg: TTyZrSeg;
begin
  Result := nil;
  if AItem.Kind = tikSymbol then
    Exit(TyZrSymbol(AItem.SymbolType, AItem.X, AItem.Y, AItem.W, AItem.H));
  { ECLinePath: straight when the control point is not a number (a null is
    a nought upstream: the port never holds one), a quadratic otherwise }
  TyZrMoveTo(Result, AItem.X1, AItem.Y1);
  if IsNan(AItem.CPX) or IsNan(AItem.CPY) then
    TyZrLineTo(Result, AItem.X2, AItem.Y2)
  else
  begin
    seg := Default(TTyZrSeg);
    seg.Cmd := zrQ;
    seg.V[0] := AItem.CPX;
    seg.V[1] := AItem.CPY;
    seg.V[2] := AItem.X2;
    seg.V[3] := AItem.Y2;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := seg;
  end;
end;

function TyThumbItemRect(const AItem: TTyThumbItem): TTyXYWH;
var path: TTyZrPath;
begin
  path := TyThumbItemPath(AItem);
  Result := TyZrStrokeRect(TyZrBBox(path), TyZrDataLength(path),
    AItem.HasStroke, AItem.HasFill, AItem.LineWidth, 1);
end;

function TyThumbBridgeRect(const AItems: TTyThumbItemArray): TTyXYWH;
var
  i, g: Integer;
  have, haveAll: Boolean;
  r, all: TTyXYWH;
  id: TTyMat2D;
begin
  id := TyMatIdentity;
  all := XYWH(0, 0, 0, 0);
  haveAll := False;
  { the symbols' group, then the lines' group: each an empty rect when it
    has no child }
  for g := 0 to 1 do
  begin
    r := XYWH(0, 0, 0, 0);
    have := False;
    for i := 0 to High(AItems) do
    begin
      if (g = 0) <> (AItems[i].Kind = tikSymbol) then Continue;
      TyZrAccumulate(r, have, TyThumbItemRect(AItems[i]), id);
    end;
    TyZrAccumulate(all, haveAll, r, id);
  end;
  Result := all;
end;

function TyThumbCentredAspect(const AContainer: TTyXYWH; AAspect: Double): TTyXYWH;
var cw, ch, w, h, left, top: Double;
begin
  cw := AContainer.W;
  ch := AContainer.H;
  w := NaN;
  h := NaN;
  { neither size given: 0.8 of the side the aspect binds }
  if (not IsNan(AAspect)) and (AAspect > cw / ch) then w := cw * 0.8
  else h := ch * 0.8;
  if IsNan(w) then w := AAspect * h;
  if IsNan(h) then h := w / AAspect;
  left := cw / 2 - w / 2;
  top := ch / 2 - h / 2;
  { `left || 0` }
  if IsNan(left) then left := 0;
  if IsNan(top) then top := 0;
  Result := XYWH(AContainer.X + left, AContainer.Y + top, w, h);
  if Result.W < 0 then
  begin
    Result.X := Result.X + Result.W;
    Result.W := -Result.W;
  end;
  if Result.H < 0 then
  begin
    Result.Y := Result.Y + Result.H;
    Result.H := -Result.H;
  end;
end;

function TyThumbFit(const AItems: TTyThumbItemArray; const AContent: TTyXYWH;
  const ATarget: TTyMat2D): TTyThumbView;
var
  v: TTyGraphView;
  mask: TFPUExceptionMask;
begin
  Result := Default(TTyThumbView);
  mask := MaskFP;
  try
    Result.DataRect := TyThumbBridgeRect(AItems);
    Result.ViewRect := TyThumbCentredAspect(AContent,
      Result.DataRect.W / Result.DataRect.H);
    { a View with no centre and no zoom: its roam is the identity, and the
      overall is the raw fit through upstream's own arithmetic }
    v := TTyGraphView.CreateXYWH(Result.DataRect, Result.ViewRect);
    try
      Result.TransX := v.RawX;
      Result.TransY := v.RawY;
      Result.TransSX := v.RawSX;
      Result.TransSY := v.RawSY;
      Result.Overall := TyMatIdentity;
      Result.Overall[0] := v.OverallScaleX;
      Result.Overall[3] := v.OverallScaleY;
      Result.Overall[4] := v.OverallX;
      Result.Overall[5] := v.OverallY;
    finally
      v.Free;
    end;
    Result.Target := ATarget;
    Result.Valid := True;
  finally
    UnmaskFP(mask);
  end;
end;

procedure TyThumbUpdateWindow(var AView: TTyThumbView; const ATarget: TTyMat2D;
  AW, AH: Double; out AWindow: TTyXYWH);
var
  inv, toThis: TTyMat2D;
  mask: TFPUExceptionMask;
begin
  AWindow := XYWH(0, 0, 0, 0);
  if not AView.Valid then Exit;
  mask := MaskFP;
  try
    AView.Target := ATarget;
    { matrix.invert answers null for a singular matrix; mul then reads it as
      zeros -- a window nobody can see. The port keeps the identity. }
    TyMatInvert(ATarget, inv);
    toThis := TyMatMul(AView.Overall, inv);
    AView.HasToTarget := TyMatInvert(toThis, AView.ToTarget);
    AWindow := TyRectApplyMat(XYWH(0, 0, AW, AH), toThis);
  finally
    UnmaskFP(mask);
  end;
end;

procedure TyThumbPanPayload(const AView: TTyThumbView; AOldX, AOldY, ADX,
  ADY: Double; out APDX, APDY: Double);
var ox, oy, nx, ny: Double;
begin
  TyZrApply(AView.ToTarget, AOldX, AOldY, ox, oy);
  TyZrApply(AView.ToTarget, AOldX - ADX, AOldY - ADY, nx, ny);
  APDX := nx - ox;
  APDY := ny - oy;
end;

procedure TyThumbZoomPayload(const AView: TTyThumbView; AScale, AX, AY: Double;
  out AZoom, AOX, AOY: Double);
begin
  TyZrApply(AView.ToTarget, AX, AY, AOX, AOY);
  AZoom := 1 / AScale;
end;

function TyThumbRectContains(const R: TTyXYWH; AX, AY: Double): Boolean;
begin
  Result := (AX >= R.X) and (AX <= R.X + R.W) and (AY >= R.Y) and (AY <= R.Y + R.H);
end;

function TyThumbSymbolType(const AName: string): string;
begin
  Result := AName;
  if Copy(Result, 1, 5) = 'empty' then
    Result := LowerCase(Copy(Result, 6, 1)) + Copy(Result, 7, MaxInt);
end;

procedure TyThumbRoamOf(AData: TJSONData; out AText: string; out AOn, APan,
  AZoom: Boolean);
var s: string;
begin
  AOn := JsTruthy(AData);
  APan := False;
  AZoom := False;
  if AData = nil then AText := 'false'
  else if AData.JSONType = jtString then AText := AData.AsString
  else if AData.JSONType = jtNumber then AText := TyJsNumberToString(AData.AsFloat)
  else if AData.JSONType = jtBoolean then
  begin
    if AData.AsBoolean then AText := 'true' else AText := 'false';
  end
  else if AData.JSONType = jtNull then AText := 'null'
  else AText := AData.AsJSON;
  if not AOn then Exit;
  if AData.JSONType = jtString then
  begin
    s := AData.AsString;
    APan := (s = 'move') or (s = 'pan');
    AZoom := (s = 'scale') or (s = 'zoom');
  end
  else if (AData.JSONType = jtBoolean) and AData.AsBoolean then
  begin
    APan := True;
    AZoom := True;
  end;
end;

end.
