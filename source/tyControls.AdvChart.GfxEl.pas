unit tyControls.AdvChart.GfxEl;
{$mode objfpc}{$H+}
{ TTyAdvanceChart -- ZRENDER'S ELEMENTS AS AN OPTION WRITES THEM: the element
  model the graphic component builds its scene from, and the one the custom
  series' renderItem will hand back. [Batch 122, C13]

  AN ELEMENT IS A PROPERTY BAG with a type: zrender's own fields -- the
  transform (x, y, rotation, scaleX / Y, originX / Y, skewX / Y, anchorX /
  Y), `shape` and `style` as the objects zrender keeps (JSON here, extended
  by every update the way setShape and setStyle extend theirs, read through
  the prototype's defaults where a key was never written), z, zlevel, z2,
  silent, ignore, invisible, cursor, draggable, a textContent with its
  textConfig, and `extra` -- the free object an option may animate beside
  the shape (nil until something writes it) [Batch 139]. It derives from TTyAnimElement, so a transition animates the
  same keys zrender's animators do -- 'x', 'shape.r', 'style.opacity' -- and
  nothing outside the bag holds a second copy of a value.

  WHAT IT ANSWERS, each transcribed from zrender 6.1:
    - the path a shape builds (Rect with roundRect, Circle, Ellipse, Ring,
      Sector with roundSector, Arc, Polygon and Polyline with smoothBezier,
      Line and BezierCurve with their percent), as PathProxy's data;
    - getBoundingRect: a path's grown by its stroke, an image's from its
      style, a text block's from its pieces, a group's the union of its
      children carried by their local transforms;
    - getLocalTransform and updateTransform, origin, skew and anchor;
    - a text's block through the rich text engine (AdvChart.RichText), its
      style read as zrender's TextStyleProps -- makeFont, the align words,
      the box -- and a textContent's place and default colours
      (Element.updateInnerText, calculateTextPosition, the inside / outside
      fills);
    - the paint list's elements: the path through the element's transform
      as cubics, an image as a pattern-filled quad, a text as a block
      caption.

  An image is a `data:` URL or nothing: the port fetches no other source
  (the rule of batch 105).

  GRADIENTS AS ANIMATION VALUES [F3b]: a style value that is an object with
  colorStops reads as an avkGradient (geometry, stops parsed, the object's
  JSON kept for a discrete step); an interpolated one writes back as a new
  object {type, x, y, colorStops [{offset, color 'rgba(..)'}], global, x2,
  y2 | r}, a raw one as the object it was.

  PURE: SysUtils, Classes, Math, fpjson (jsonparser) and the AdvChart units. }
interface
uses
  SysUtils, Classes, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Paint,
  tyControls.AdvChart.Shape, tyControls.AdvChart.ZrPath,
  tyControls.AdvChart.Anim, tyControls.AdvChart.RichText;

type
  { gkPath: a path whose PathProxy data is made by its maker, not read off a
    shape -- a symbol, an icon (the timeline's, batch 129); no option type
    word makes one }
  TTyGfxKind = (gkUnknown, gkGroup, gkImage, gkText, gkRect, gkCircle,
    gkEllipse, gkRing, gkSector, gkArc, gkPolygon, gkPolyline, gkLine,
    gkBezier, gkPath);

  TTyGfxEl = class;
  TTyGfxElArray = array of TTyGfxEl;

  TTyGfxEl = class(TTyAnimElement)
  private
    function StyleDefault(const AKey: string; out AValue: TTyAnimValue): Boolean;
  public
    Kind: TTyGfxKind;
    { the option's type word ('bezierCurve'), not zrender's ('bezier-curve') }
    GType: string;
    Id, Name: string;
    Parent: TTyGfxEl;
    Children: TTyGfxElArray;
    X, Y, Rotation, ScaleX, ScaleY, OriginX, OriginY, SkewX, SkewY,
      AnchorX, AnchorY: Double;
    { owned; never nil }
    Shape, Style: TJSONObject;
    Silent, Ignore, Invisible: Boolean;
    { '' false; else the option's word: 'true', 'horizontal', 'vertical' }
    Draggable: string;
    Cursor: string;
    Z, ZLevel, Z2: Double;
    { the attached text (owned) and its host }
    TextContent: TTyGfxEl;
    Host: TTyGfxEl;
    { owned; nil until a textConfig is set }
    TextConfig: TJSONObject;
    { ECData's eventData: made once, for an element neither silent nor
      ignored when it was set, its name the element's name then; Info is
      the option's `info` as written (owned; nil when undefined) }
    HasEventData: Boolean;
    EventName: string;
    Info: TJSONData;
    { element handlers: 'onclick=@Name' }
    Handlers: TStringList;
    { a leave transition's target, flattened ('x', 'style.opacity') }
    LeaveToProps: TTyAnimProps;
    HasLeaveTo: Boolean;
    { the view's inner store: a group's size, whether the element is new;
      the width / height its last update wrote (owned; nil none) }
    InnerW, InnerH: Double;
    InnerOptW, InnerOptH: TJSONData;
    IsNew: Boolean;
    { removed, running its leave transition; and gone (detached, awaiting
      its free) }
    Leaving, Gone: Boolean;
    { where a gone element is put to be freed (the view's list) }
    GoneList: TFPList;
    { the global transform (updateTransform); HasTransform False is null }
    HasTransform: Boolean;
    Transform: TTyMat2D;
    { a textContent's innerTransformable and the host's default style }
    InX, InY, InRot, InOX, InOY: Double;
    DefFill, DefStroke, DefAlign, DefVAlign: string;
    DefAutoStroke, HasDefault: Boolean;
    { the index the last paint list build gave it }
    Serial: Integer;
    { what the custom series keeps on an element it made (its state
      options, its root's focus) [Batch 123]: owned, freed with the
      element; nil on everything else }
    Custom: TObject;
    { a gkPath's data, in its own frame [Batch 129] }
    PathData: TTyZrPath;
    { el.extra: owned; nil until an option (or an animation) writes it
      [Batch 139] }
    Extra: TJSONObject;
    { what the keyframe animations saved before they ran
      (customGraphicKeyframeAnimation's getStateToRestore): flattened ('x',
      'style.opacity', 'extra.k'), kept for the element's life and put back
      before every update [Batch 139] }
    KfRestore: TTyAnimProps;
    { a series' textContent: LabelManager has laid it out once (its
      labelLayoutInnerStore oldLayout is set), so it is not faded in again
      [milestone D5-D8] }
    LabelLaidOut: Boolean;
    constructor Create(AKind: TTyGfxKind; const AType: string);
    destructor Destroy; override;
    function GetAnimProp(const AKey: string): TTyAnimValue; override;
    procedure SetAnimProp(const AKey: string; const AValue: TTyAnimValue); override;
    function AnimKeyList: TTyStringArray; override;
    function IsGroup: Boolean;
    { zrender's type: 'rect', 'bezier-curve', 'group' ... }
    function ZrType: string;
    { a style key as zrender reads it: own, else the prototype's }
    function StyleValue(const AKey: string): TTyAnimValue;
    { the leave transition's done: detached from its parent, kept for the
      view to free }
    procedure LeaveDone;
    { el[AName] exists: '' the element itself, 'style' anything but a group,
      'shape' a path, 'extra' once written [Batch 139] }
    function HasAnimTarget(const AName: string): Boolean;
  end;

{ the option's type word }
function TyGfxKindOf(const AType: string): TTyGfxKind;
{ a new element of the type, zrender's getDefaultShape and getDefaultStyle
  in it; nil for a type there is no class for }
function TyGfxCreate(const AType: string): TTyGfxEl;
procedure TyGfxAddChild(AParent, AChild: TTyGfxEl);
procedure TyGfxRemoveChild(AParent, AChild: TTyGfxEl);
{ every element below AEl, depth first (Group.traverse: not AEl itself) }
procedure TyGfxTraverse(AEl: TTyGfxEl; var AList: TTyGfxElArray);

{ JSON values: a deep copy; zrender's extend; zrUtil.merge(a, b, true) }
function TyGfxClone(AData: TJSONData): TJSONData;
procedure TyGfxExtend(ATarget, ASource: TJSONObject);
procedure TyGfxMerge(ATarget, ASource: TJSONObject);
{ JSON <-> the animation's values }
function TyGfxAnimOf(AData: TJSONData): TTyAnimValue;
function TyGfxJsonOf(const AValue: TTyAnimValue): TJSONData;
{ a JSON object (a leaveTo, an enterFrom) as flattened props under APrefix
  ('' root, 'style', 'shape'), appended to AProps }
procedure TyGfxPropsOf(AObj: TJSONObject; const APrefix: string;
  var AProps: TTyAnimProps);

{ setStyle: extend; a text's rich merged name by name (Text._mergeStyle) }
procedure TyGfxSetStyle(AEl: TTyGfxEl; AStyle: TJSONObject);
{ attr with a shape: setShape, extend with clones }
procedure TyGfxSetShape(AEl: TTyGfxEl; AShape: TJSONObject);
{ a transform prop by its name ('x', 'scaleY' ...); False for another name }
function TyGfxSetTransformProp(AEl: TTyGfxEl; const AKey: string; AValue: Double): Boolean;
function TyGfxIsTransformProp(const AKey: string): Boolean;

{ ---- the transform ---- }
function TyGfxNeedLocal(AEl: TTyGfxEl): Boolean;
function TyGfxLocalTransform(AEl: TTyGfxEl): TTyMat2D;
{ updateTransform over AEl and everything below it, AEl's parent's
  transform taken as it stands; a textContent's as updateInnerText leaves
  it }
procedure TyGfxUpdateTransforms(AEl: TTyGfxEl);
{ a textContent's transform: its innerTransformable's local, under its
  host's when textConfig.local }
procedure TyGfxLabelTransform(AText: TTyGfxEl; out AHas: Boolean; out AM: TTyMat2D);

{ ---- what it builds ---- }
function TyGfxHasFill(AEl: TTyGfxEl): Boolean;
function TyGfxHasStroke(AEl: TTyGfxEl): Boolean;
function TyGfxLineWidth(AEl: TTyGfxEl): Double;
{ the PathProxy data of a path element, in its own frame; nil otherwise }
function TyGfxPath(AEl: TTyGfxEl): TTyZrPath;
{ smoothBezier: the control points of a smoothed polyline / polygon }
function TyGfxSmoothBezier(const APoints: TTyPointFArray; ASmooth: Double;
  AIsLoop: Boolean; AHasConstraint: Boolean; const AMin, AMax: TTyPointF): TTyPointFArray;

{ a text element's block: its style read as TextStyleProps, laid out with
  its default style (the host's for a textContent, else fill '#000') }
function TyGfxTextLayout(AEl: TTyGfxEl; const AMeasurer: ITyTextMeasurer): TTyRtResult;
{ getBoundingRect, in the element's own frame }
function TyGfxRect(AEl: TTyGfxEl; const AMeasurer: ITyTextMeasurer): TTyXYWH;
{ style.strokeNoScale is truthy [Batch 129] }
function TyGfxStrokeNoScale(AEl: TTyGfxEl): Boolean;
{ Path.getLineScale: 1, or -- with strokeNoScale and a transform whose
  diagonal is not one -- the square root of its determinant [Batch 129] }
function TyGfxLineScale(AEl: TTyGfxEl): Double;

{ makeFont of a style object (TextStylePropsPart): '' when it has none }
function TyGfxMakeFont(AStyle: TJSONObject): string;
{ a CSS font as the measure reads it: the px size (12 when none), the
  weight, the family, the style }
procedure TyGfxParseFont(const AFont: string; out APx: Double;
  out AWeight: Integer; out AFamily: string; out AItalic: Boolean);

{ ---- a textContent ---- }
type
  { what the host is drawn over: zrender's background colour and dark mode }
  TTyGfxGround = record
    Background: string;
    IsDark: Boolean;
  end;

{ updateInnerText: AHost's textContent's innerTransformable and default
  style, against the host's bounding rect }
procedure TyGfxInnerText(AHost: TTyGfxEl; const AMeasurer: ITyTextMeasurer;
  const AGround: TTyGfxGround);

{ calculateTextPosition: the anchor and the alignment a position word (or
  an [x, y] array: no alignment, '') makes against a rect }
procedure TyGfxTextPosition(APosition: TJSONData; ADistance: Double;
  const ARect: TTyXYWH; out AX, AY: Double; out AAlign, AVAlign: string);

{ ---- painting ---- }
type
  { what the paint conversion is handed: device px per css px, the ink a
    free text's default fill is drawn in (the skin's), and an image's
    natural size when the style gives none }
  TTyGfxImageSize = function(const ASource: string; out AW, AH: Double): Boolean;
  TTyGfxPaintCtx = record
    Scale: Double;
    HasInk: Boolean;
    Ink: TTyChartColor;
    ImageSize: TTyGfxImageSize;
  end;

{ The paint list element a displayable becomes, transform applied, in
  device px; False for nothing to add (a group). A textContent is its own
  element: AEl the text, its transform TyGfxLabelTransform's. }
function TyGfxPaintElement(AEl: TTyGfxEl; const AMeasurer: ITyTextMeasurer;
  const ACtx: TTyGfxPaintCtx; out AOut: TTyChartElement): Boolean;

{ PathProxy data drawn and hit through a matrix: every arc a run of cubics
  of at most a quarter turn, a quadratic raised to a cubic, a rect four
  lines; the outline sampled for the hit test }
procedure TyGfxPathCmds(const APath: TTyZrPath; const AM: TTyMat2D;
  out ACmds: TTyPathCmdArray; out APoints: TTyPointFArray);

implementation

uses
  jsonparser,
  tyControls.AdvChart.JsMath, tyControls.AdvChart.Scale,
  tyControls.AdvChart.Layout, tyControls.AdvChart.Color,
  tyControls.AdvChart.PolarBar, tyControls.AdvChart.RichStyle;

const
  PI2 = 2 * Pi;
  cTransformKeys: array[0..10] of string = ('x', 'y', 'originX', 'originY',
    'anchorX', 'anchorY', 'rotation', 'scaleX', 'scaleY', 'skewX', 'skewY');

{ ==================== JSON ==================== }

function JNull(A: TJSONData): Boolean; inline;
begin
  Result := (A = nil) or (A.JSONType = jtNull);
end;

function NumOf(A: TJSONData; out AV: Double): Boolean;
begin
  Result := (A <> nil) and (A.JSONType = jtNumber);
  if Result then AV := A.AsFloat else AV := NaN;
end;

{ a number as JavaScript reads one out of a shape: a number, a boolean as
  0 / 1, null 0, a numeric string its number, anything else NaN }
function JsNum(A: TJSONData): Double;
var fs: TFormatSettings; s: string;
begin
  if A = nil then Exit(NaN);
  case A.JSONType of
    jtNumber: Result := A.AsFloat;
    jtBoolean: if A.AsBoolean then Result := 1 else Result := 0;
    jtNull: Result := 0;
    jtString:
      begin
        fs := DefaultFormatSettings;
        fs.DecimalSeparator := '.';
        s := Trim(A.AsString);
        if s = '' then Result := 0
        else if not TryStrToFloat(s, Result, fs) then Result := NaN;
      end;
  else
    Result := NaN;
  end;
end;

function StrOf(A: TJSONData): string;
begin
  if (A <> nil) and (A.JSONType = jtString) then Result := A.AsString
  else Result := '';
end;

function TyGfxClone(AData: TJSONData): TJSONData;
begin
  if AData = nil then Result := nil else Result := AData.Clone;
end;

procedure PutKey(AObj: TJSONObject; const AKey: string; AValue: TJSONData);
var i: Integer;
begin
  i := AObj.IndexOfName(AKey);
  if i >= 0 then AObj.Items[i] := AValue
  else AObj.Add(AKey, AValue);
end;

procedure TyGfxExtend(ATarget, ASource: TJSONObject);
var i: Integer;
begin
  if (ATarget = nil) or (ASource = nil) then Exit;
  for i := 0 to ASource.Count - 1 do
    PutKey(ATarget, ASource.Names[i], ASource.Items[i].Clone);
end;

procedure TyGfxMerge(ATarget, ASource: TJSONObject);
var
  i, k: Integer;
  key: string;
  s, t: TJSONData;
begin
  if (ATarget = nil) or (ASource = nil) then Exit;
  for i := 0 to ASource.Count - 1 do
  begin
    key := ASource.Names[i];
    s := ASource.Items[i];
    k := ATarget.IndexOfName(key);
    if k >= 0 then t := ATarget.Items[k] else t := nil;
    if (s is TJSONObject) and (t is TJSONObject) then
      TyGfxMerge(TJSONObject(t), TJSONObject(s))
    else
      PutKey(ATarget, key, s.Clone);
  end;
end;

{ isGradientObject (colorStops != null) parsed as Track.addKeyframe parses
  it: the type's numbers, every stop's offset and colour [F3b] }
function GradientValueOf(AObj: TJSONObject): TTyAnimValue;
var
  t: string;
  d, stops, st: TJSONData;
  i: Integer;
  r, g, b, a: Double;

  function Field(const AName: string): Double;
  begin
    Result := JsNum(AObj.Find(AName));
  end;

begin
  Result := Default(TTyAnimValue);
  Result.Kind := avkGradient;
  Result.Str := AObj.AsJSON;
  t := '';
  d := AObj.Find('type');
  if (d <> nil) and (d.JSONType = jtString) then t := d.AsString;
  if t = 'linear' then
  begin
    Result.Stride := 4;
    Result.Arr := TTyDoubleArray.Create(Field('x'), Field('y'), Field('x2'), Field('y2'));
  end
  else if t = 'radial' then
  begin
    Result.Stride := 3;
    Result.Arr := TTyDoubleArray.Create(Field('x'), Field('y'), Field('r'));
  end;
  d := AObj.Find('global');
  if JNull(d) then Result.Num := NaN
  else if d.JSONType = jtBoolean then
  begin
    if d.AsBoolean then Result.Num := 1 else Result.Num := 0;
  end
  else Result.Num := JsNum(d);
  stops := AObj.Find('colorStops');
  if (stops <> nil) and (stops.JSONType = jtArray) then
  begin
    SetLength(Result.Stops, stops.Count * 5);
    for i := 0 to stops.Count - 1 do
    begin
      st := stops.Items[i];
      if st is TJSONObject then
      begin
        Result.Stops[i * 5] := JsNum(TJSONObject(st).Find('offset'));
        d := TJSONObject(st).Find('color');
        if (d <> nil) and (d.JSONType = jtString)
          and TyTryParseCssRgba(d.AsString, r, g, b, a) then
        begin
          Result.Stops[i * 5 + 1] := r;
          Result.Stops[i * 5 + 2] := g;
          Result.Stops[i * 5 + 3] := b;
          Result.Stops[i * 5 + 4] := a;
          Continue;
        end;
      end
      else
        Result.Stops[i * 5] := NaN;
      Result.Stops[i * 5 + 1] := NaN;
      Result.Stops[i * 5 + 2] := NaN;
      Result.Stops[i * 5 + 3] := NaN;
      Result.Stops[i * 5 + 4] := NaN;
    end;
  end;
end;

{ an interpolated gradient as the object Animator.ts writes [F3b] }
function GradientJsonOf(const AValue: TTyAnimValue): TJSONData;
var
  o, cs: TJSONObject;
  stops: TJSONArray;
  i: Integer;

  function At(AI: Integer): Double;
  begin
    if AI <= High(AValue.Arr) then Result := AValue.Arr[AI] else Result := NaN;
  end;

begin
  if AValue.Str <> '' then
  begin
    Result := GetJSON(AValue.Str);
    Exit;
  end;
  o := TJSONObject.Create;
  if AValue.Stride = 4 then o.Add('type', 'linear') else o.Add('type', 'radial');
  o.Add('x', TJSONFloatNumber.Create(At(0)));
  o.Add('y', TJSONFloatNumber.Create(At(1)));
  stops := TJSONArray.Create;
  for i := 0 to (Length(AValue.Stops) div 5) - 1 do
  begin
    cs := TJSONObject.Create;
    cs.Add('offset', TJSONFloatNumber.Create(AValue.Stops[i * 5]));
    cs.Add('color', TyAnimRgbaString(AValue.Stops[i * 5 + 1], AValue.Stops[i * 5 + 2],
      AValue.Stops[i * 5 + 3], AValue.Stops[i * 5 + 4]));
    stops.Add(cs);
  end;
  o.Add('colorStops', stops);
  if not IsNan(AValue.Num) then o.Add('global', AValue.Num <> 0);
  if AValue.Stride = 4 then
  begin
    o.Add('x2', TJSONFloatNumber.Create(At(2)));
    o.Add('y2', TJSONFloatNumber.Create(At(3)));
  end
  else
    o.Add('r', TJSONFloatNumber.Create(At(2)));
  Result := o;
end;

function TyGfxAnimOf(AData: TJSONData): TTyAnimValue;
var
  arr: TTyDoubleArray;
  i, k, stride: Integer;
  d: TJSONData;
begin
  if JNull(AData) then Exit(TyAnimNull);
  { a gradient object [F3b] }
  if (AData.JSONType = jtObject) and not JNull(TJSONObject(AData).Find('colorStops')) then
    Exit(GradientValueOf(TJSONObject(AData)));
  case AData.JSONType of
    jtNumber: Result := TyAnimNum(AData.AsFloat);
    jtBoolean: Result := TyAnimBool(AData.AsBoolean);
    jtString: Result := TyAnimStr(AData.AsString);
    jtArray:
      begin
        arr := nil;
        stride := 0;
        if (AData.Count > 0) and (AData.Items[0].JSONType = jtArray) then
        begin
          stride := AData.Items[0].Count;
          SetLength(arr, AData.Count * stride);
          for i := 0 to AData.Count - 1 do
          begin
            d := AData.Items[i];
            for k := 0 to stride - 1 do
              if (d is TJSONArray) and (k < d.Count) then arr[i * stride + k] := JsNum(d.Items[k])
              else arr[i * stride + k] := NaN;
          end;
          if stride = 0 then stride := 1;
        end
        else
        begin
          SetLength(arr, AData.Count);
          for i := 0 to AData.Count - 1 do arr[i] := JsNum(AData.Items[i]);
        end;
        Result := TyAnimArr(arr, stride);
      end;
  else
    Result := TyAnimNull;
  end;
end;

function TyGfxJsonOf(const AValue: TTyAnimValue): TJSONData;
var
  a, row: TJSONArray;
  i, k, n: Integer;
begin
  case AValue.Kind of
    avkNumber: Result := TJSONFloatNumber.Create(AValue.Num);
    avkBool: Result := TJSONBoolean.Create(AValue.Num <> 0);
    avkString: Result := TJSONString.Create(AValue.Str);
    avkArray:
      begin
        a := TJSONArray.Create;
        if AValue.Stride > 0 then
        begin
          n := Length(AValue.Arr) div AValue.Stride;
          for i := 0 to n - 1 do
          begin
            row := TJSONArray.Create;
            for k := 0 to AValue.Stride - 1 do
              row.Add(TJSONFloatNumber.Create(AValue.Arr[i * AValue.Stride + k]));
            a.Add(row);
          end;
        end
        else
          for i := 0 to High(AValue.Arr) do a.Add(TJSONFloatNumber.Create(AValue.Arr[i]));
        Result := a;
      end;
    avkGradient: Result := GradientJsonOf(AValue);
  else
    Result := TJSONNull.Create;
  end;
end;

procedure TyGfxPropsOf(AObj: TJSONObject; const APrefix: string;
  var AProps: TTyAnimProps);
var
  i: Integer;
  key: string;
begin
  if AObj = nil then Exit;
  for i := 0 to AObj.Count - 1 do
  begin
    key := AObj.Names[i];
    if APrefix <> '' then key := APrefix + '.' + key;
    TyAnimPropPut(AProps, key, TyGfxAnimOf(AObj.Items[i]));
  end;
end;

{ ==================== the element ==================== }

function TyGfxKindOf(const AType: string): TTyGfxKind;
begin
  if AType = 'group' then Result := gkGroup
  else if AType = 'image' then Result := gkImage
  else if AType = 'text' then Result := gkText
  else if AType = 'rect' then Result := gkRect
  else if AType = 'circle' then Result := gkCircle
  else if AType = 'ellipse' then Result := gkEllipse
  else if AType = 'ring' then Result := gkRing
  else if AType = 'sector' then Result := gkSector
  else if AType = 'arc' then Result := gkArc
  else if AType = 'polygon' then Result := gkPolygon
  else if AType = 'polyline' then Result := gkPolyline
  else if AType = 'line' then Result := gkLine
  else if AType = 'bezierCurve' then Result := gkBezier
  else Result := gkUnknown;
end;

procedure AddNum(AObj: TJSONObject; const AKey: string; AValue: Double);
begin
  AObj.Add(AKey, TJSONFloatNumber.Create(AValue));
end;

constructor TTyGfxEl.Create(AKind: TTyGfxKind; const AType: string);
begin
  inherited Create;
  Kind := AKind;
  GType := AType;
  ScaleX := 1;
  ScaleY := 1;
  Cursor := 'pointer';
  IsNew := True;
  Serial := -1;
  Shape := TJSONObject.Create;
  Style := TJSONObject.Create;
  Handlers := TStringList.Create;
  { getDefaultShape, in the class field order }
  case AKind of
    gkRect:
      begin
        AddNum(Shape, 'x', 0); AddNum(Shape, 'y', 0);
        AddNum(Shape, 'width', 0); AddNum(Shape, 'height', 0);
      end;
    gkCircle:
      begin
        AddNum(Shape, 'cx', 0); AddNum(Shape, 'cy', 0); AddNum(Shape, 'r', 0);
      end;
    gkEllipse:
      begin
        AddNum(Shape, 'cx', 0); AddNum(Shape, 'cy', 0);
        AddNum(Shape, 'rx', 0); AddNum(Shape, 'ry', 0);
      end;
    gkRing:
      begin
        AddNum(Shape, 'cx', 0); AddNum(Shape, 'cy', 0);
        AddNum(Shape, 'r', 0); AddNum(Shape, 'r0', 0);
      end;
    gkSector:
      begin
        AddNum(Shape, 'cx', 0); AddNum(Shape, 'cy', 0);
        AddNum(Shape, 'r0', 0); AddNum(Shape, 'r', 0);
        AddNum(Shape, 'startAngle', 0); AddNum(Shape, 'endAngle', Pi * 2);
        Shape.Add('clockwise', True);
        AddNum(Shape, 'cornerRadius', 0);
      end;
    gkArc:
      begin
        AddNum(Shape, 'cx', 0); AddNum(Shape, 'cy', 0); AddNum(Shape, 'r', 0);
        AddNum(Shape, 'startAngle', 0); AddNum(Shape, 'endAngle', Pi * 2);
        Shape.Add('clockwise', True);
      end;
    gkPolygon:
      begin
        Shape.Add('points', TJSONNull.Create);
        AddNum(Shape, 'smooth', 0);
        Shape.Add('smoothConstraint', TJSONNull.Create);
      end;
    gkPolyline:
      begin
        Shape.Add('points', TJSONNull.Create);
        AddNum(Shape, 'percent', 1);
        AddNum(Shape, 'smooth', 0);
        Shape.Add('smoothConstraint', TJSONNull.Create);
      end;
    gkLine:
      begin
        AddNum(Shape, 'x1', 0); AddNum(Shape, 'y1', 0);
        AddNum(Shape, 'x2', 0); AddNum(Shape, 'y2', 0);
        AddNum(Shape, 'percent', 1);
      end;
    gkBezier:
      begin
        AddNum(Shape, 'x1', 0); AddNum(Shape, 'y1', 0);
        AddNum(Shape, 'x2', 0); AddNum(Shape, 'y2', 0);
        AddNum(Shape, 'cpx1', 0); AddNum(Shape, 'cpy1', 0);
        AddNum(Shape, 'percent', 1);
      end;
  end;
  { getDefaultStyle: the open paths stroke black and fill nothing }
  if AKind in [gkArc, gkPolyline, gkLine, gkBezier] then
  begin
    Style.Add('stroke', '#000');
    Style.Add('fill', TJSONNull.Create);
  end;
  { Path's prototype: a Path stroke-contains within lineWidth; the state
    machine of the engine treats a text as a text }
  StatePath := not (AKind in [gkText, gkImage, gkGroup]);
end;

destructor TTyGfxEl.Destroy;
var i: Integer;
begin
  for i := 0 to High(Children) do
  begin
    Children[i].Parent := nil;
    Children[i].Free;
  end;
  Children := nil;
  FreeAndNil(TextContent);
  FreeAndNil(TextConfig);
  FreeAndNil(Info);
  FreeAndNil(Custom);
  FreeAndNil(InnerOptW);
  FreeAndNil(InnerOptH);
  FreeAndNil(Handlers);
  FreeAndNil(Shape);
  FreeAndNil(Style);
  FreeAndNil(Extra);
  inherited Destroy;
end;

function TTyGfxEl.IsGroup: Boolean;
begin
  Result := Kind = gkGroup;
end;

function TTyGfxEl.HasAnimTarget(const AName: string): Boolean;
begin
  if AName = '' then Result := True
  else if AName = 'style' then Result := Kind <> gkGroup
  else if AName = 'shape' then Result := Kind in [gkRect, gkCircle, gkEllipse, gkRing,
    gkSector, gkArc, gkPolygon, gkPolyline, gkLine, gkBezier, gkPath]
  else if AName = 'extra' then Result := Extra <> nil
  else Result := False;
end;

function TTyGfxEl.ZrType: string;
const
  cNames: array[TTyGfxKind] of string = ('', 'group', 'image', 'text', 'rect',
    'circle', 'ellipse', 'ring', 'sector', 'arc', 'polygon', 'polyline', 'line',
    'bezier-curve', 'path');
begin
  Result := cNames[Kind];
end;

function TTyGfxEl.StyleDefault(const AKey: string; out AValue: TTyAnimValue): Boolean;
begin
  Result := True;
  if Kind in [gkRect, gkCircle, gkEllipse, gkRing, gkSector, gkArc, gkPolygon,
    gkPolyline, gkLine, gkBezier, gkPath] then
  begin
    if TyAnimStyleDefault(AKey, AValue) then Exit;
  end;
  { DEFAULT_COMMON_STYLE, and an image's x / y }
  if (AKey = 'shadowBlur') or (AKey = 'shadowOffsetX') or (AKey = 'shadowOffsetY') then
    AValue := TyAnimNum(0)
  else if AKey = 'shadowColor' then AValue := TyAnimStr('#000')
  else if AKey = 'opacity' then AValue := TyAnimNum(1)
  else if AKey = 'blend' then AValue := TyAnimStr('source-over')
  else if (Kind = gkImage) and ((AKey = 'x') or (AKey = 'y')) then AValue := TyAnimNum(0)
  else
  begin
    AValue := TyAnimNull;
    Result := False;
  end;
end;

function TTyGfxEl.StyleValue(const AKey: string): TTyAnimValue;
var i: Integer;
begin
  i := Style.IndexOfName(AKey);
  if i >= 0 then Exit(TyGfxAnimOf(Style.Items[i]));
  StyleDefault(AKey, Result);
end;

function TTyGfxEl.GetAnimProp(const AKey: string): TTyAnimValue;
var
  i: Integer;
  inner: string;
begin
  if Copy(AKey, 1, 6) = 'style.' then Exit(StyleValue(Copy(AKey, 7, MaxInt)));
  if Copy(AKey, 1, 6) = 'shape.' then
  begin
    inner := Copy(AKey, 7, MaxInt);
    i := Shape.IndexOfName(inner);
    if i >= 0 then Exit(TyGfxAnimOf(Shape.Items[i]));
    Exit(TyAnimNull);
  end;
  if Copy(AKey, 1, 6) = 'extra.' then
  begin
    if Extra = nil then Exit(TyAnimNull);
    i := Extra.IndexOfName(Copy(AKey, 7, MaxInt));
    if i >= 0 then Exit(TyGfxAnimOf(Extra.Items[i]));
    Exit(TyAnimNull);
  end;
  if AKey = 'x' then Result := TyAnimNum(X)
  else if AKey = 'y' then Result := TyAnimNum(Y)
  else if AKey = 'rotation' then Result := TyAnimNum(Rotation)
  else if AKey = 'scaleX' then Result := TyAnimNum(ScaleX)
  else if AKey = 'scaleY' then Result := TyAnimNum(ScaleY)
  else if AKey = 'originX' then Result := TyAnimNum(OriginX)
  else if AKey = 'originY' then Result := TyAnimNum(OriginY)
  else if AKey = 'skewX' then Result := TyAnimNum(SkewX)
  else if AKey = 'skewY' then Result := TyAnimNum(SkewY)
  else if AKey = 'anchorX' then Result := TyAnimNum(AnchorX)
  else if AKey = 'anchorY' then Result := TyAnimNum(AnchorY)
  else if AKey = 'z' then Result := TyAnimNum(Z)
  else if AKey = 'z2' then Result := TyAnimNum(Z2)
  else if AKey = 'zlevel' then Result := TyAnimNum(ZLevel)
  else if AKey = 'silent' then Result := TyAnimBool(Silent)
  else if AKey = 'ignore' then Result := TyAnimBool(Ignore)
  else if AKey = 'invisible' then Result := TyAnimBool(Invisible)
  else Result := TyAnimNull;
end;

function TyGfxIsTransformProp(const AKey: string): Boolean;
var k: Integer;
begin
  for k := 0 to High(cTransformKeys) do
    if cTransformKeys[k] = AKey then Exit(True);
  Result := False;
end;

function TyGfxSetTransformProp(AEl: TTyGfxEl; const AKey: string; AValue: Double): Boolean;
begin
  Result := True;
  if AKey = 'x' then AEl.X := AValue
  else if AKey = 'y' then AEl.Y := AValue
  else if AKey = 'rotation' then AEl.Rotation := AValue
  else if AKey = 'scaleX' then AEl.ScaleX := AValue
  else if AKey = 'scaleY' then AEl.ScaleY := AValue
  else if AKey = 'originX' then AEl.OriginX := AValue
  else if AKey = 'originY' then AEl.OriginY := AValue
  else if AKey = 'skewX' then AEl.SkewX := AValue
  else if AKey = 'skewY' then AEl.SkewY := AValue
  else if AKey = 'anchorX' then AEl.AnchorX := AValue
  else if AKey = 'anchorY' then AEl.AnchorY := AValue
  else Result := False;
end;

procedure TTyGfxEl.SetAnimProp(const AKey: string; const AValue: TTyAnimValue);
var v: Double;
begin
  if Copy(AKey, 1, 6) = 'style.' then
  begin
    PutKey(Style, Copy(AKey, 7, MaxInt), TyGfxJsonOf(AValue));
    Exit;
  end;
  if Copy(AKey, 1, 6) = 'shape.' then
  begin
    PutKey(Shape, Copy(AKey, 7, MaxInt), TyGfxJsonOf(AValue));
    Exit;
  end;
  if Copy(AKey, 1, 6) = 'extra.' then
  begin
    { attr's `this.extra = this.extra || an empty object` }
    if Extra = nil then Extra := TJSONObject.Create;
    PutKey(Extra, Copy(AKey, 7, MaxInt), TyGfxJsonOf(AValue));
    Exit;
  end;
  case AValue.Kind of
    avkNumber, avkBool: v := AValue.Num;
    avkNull: v := 0;
  else
    v := NaN;
  end;
  if TyGfxSetTransformProp(Self, AKey, v) then Exit;
  if AKey = 'z' then Z := v
  else if AKey = 'z2' then Z2 := v
  else if AKey = 'zlevel' then ZLevel := v
  else if AKey = 'silent' then Silent := v <> 0
  else if AKey = 'ignore' then Ignore := v <> 0
  else if AKey = 'invisible' then Invisible := v <> 0;
end;

function TTyGfxEl.AnimKeyList: TTyStringArray;
var i, n: Integer;
begin
  Result := nil;
  SetLength(Result, Length(cTransformKeys) + Style.Count + Shape.Count);
  n := 0;
  for i := 0 to High(cTransformKeys) do
  begin
    Result[n] := cTransformKeys[i];
    Inc(n);
  end;
  for i := 0 to Style.Count - 1 do
  begin
    Result[n] := 'style.' + Style.Names[i];
    Inc(n);
  end;
  for i := 0 to Shape.Count - 1 do
  begin
    Result[n] := 'shape.' + Shape.Names[i];
    Inc(n);
  end;
end;

procedure TTyGfxEl.LeaveDone;
begin
  if Gone then Exit;
  Gone := True;
  Leaving := False;
  if Parent <> nil then TyGfxRemoveChild(Parent, Self);
  if GoneList <> nil then GoneList.Add(Self);
end;

function TyGfxCreate(const AType: string): TTyGfxEl;
var k: TTyGfxKind;
begin
  k := TyGfxKindOf(AType);
  if k = gkUnknown then Exit(nil);
  Result := TTyGfxEl.Create(k, AType);
end;

procedure TyGfxAddChild(AParent, AChild: TTyGfxEl);
var n: Integer;
begin
  if (AParent = nil) or (AChild = nil) then Exit;
  if AChild.Parent <> nil then TyGfxRemoveChild(AChild.Parent, AChild);
  n := Length(AParent.Children);
  SetLength(AParent.Children, n + 1);
  AParent.Children[n] := AChild;
  AChild.Parent := AParent;
end;

procedure TyGfxRemoveChild(AParent, AChild: TTyGfxEl);
var i, k: Integer;
begin
  if AParent = nil then Exit;
  for i := 0 to High(AParent.Children) do
    if AParent.Children[i] = AChild then
    begin
      for k := i to High(AParent.Children) - 1 do
        AParent.Children[k] := AParent.Children[k + 1];
      SetLength(AParent.Children, Length(AParent.Children) - 1);
      AChild.Parent := nil;
      Exit;
    end;
end;

procedure TyGfxTraverse(AEl: TTyGfxEl; var AList: TTyGfxElArray);
var i, n: Integer;
begin
  if AEl = nil then Exit;
  for i := 0 to High(AEl.Children) do
  begin
    n := Length(AList);
    SetLength(AList, n + 1);
    AList[n] := AEl.Children[i];
    if AEl.Children[i].IsGroup then TyGfxTraverse(AEl.Children[i], AList);
  end;
end;

procedure TyGfxSetStyle(AEl: TTyGfxEl; AStyle: TJSONObject);
var
  srcRich, tgtRich, d: TJSONData;
  i, k: Integer;
  name: string;
begin
  if (AEl = nil) or (AStyle = nil) then Exit;
  if AEl.Kind <> gkText then
  begin
    TyGfxExtend(AEl.Style, AStyle);
    Exit;
  end;
  { Text._mergeStyle: rich merged name by name, a missing source rich
    keeping the target's }
  srcRich := AStyle.Find('rich');
  tgtRich := AEl.Style.Find('rich');
  if tgtRich <> nil then tgtRich := tgtRich.Clone
  else if srcRich is TJSONObject then tgtRich := TJSONObject.Create;
  TyGfxExtend(AEl.Style, AStyle);
  if (srcRich is TJSONObject) and (tgtRich is TJSONObject) then
  begin
    for i := 0 to srcRich.Count - 1 do
    begin
      name := TJSONObject(srcRich).Names[i];
      k := TJSONObject(tgtRich).IndexOfName(name);
      if (k < 0) or not (TJSONObject(tgtRich).Items[k] is TJSONObject) then
      begin
        PutKey(TJSONObject(tgtRich), name, TJSONObject.Create);
        k := TJSONObject(tgtRich).IndexOfName(name);
      end;
      d := srcRich.Items[i];
      if d is TJSONObject then
        TyGfxExtend(TJSONObject(TJSONObject(tgtRich).Items[k]), TJSONObject(d));
    end;
    PutKey(AEl.Style, 'rich', tgtRich);
  end
  else if tgtRich <> nil then
    PutKey(AEl.Style, 'rich', tgtRich);
end;

procedure TyGfxSetShape(AEl: TTyGfxEl; AShape: TJSONObject);
begin
  if (AEl = nil) or (AShape = nil) then Exit;
  TyGfxExtend(AEl.Shape, AShape);
end;

{ ==================== the transform ==================== }

function AroundZero(V: Double): Boolean; inline;
begin
  Result := not ((V > 5e-5) or (V < -5e-5));
end;

function TyGfxNeedLocal(AEl: TTyGfxEl): Boolean;
begin
  Result := not AroundZero(AEl.Rotation) or not AroundZero(AEl.X)
    or not AroundZero(AEl.Y) or not AroundZero(AEl.ScaleX - 1)
    or not AroundZero(AEl.ScaleY - 1) or not AroundZero(AEl.SkewX)
    or not AroundZero(AEl.SkewY);
end;

{ Transformable.getLocalTransform from its parts }
function LocalOf(AX, AY, ARotation, ASX, ASY, AOX, AOY, ASkewX, ASkewY, AAX,
  AAY: Double): TTyMat2D;
var
  skx, sky, dx, dy, aa, ac, atx, ab, ad, aty, st, ct: Double;
  m: TTyMat2D;
begin
  if ASkewX <> 0 then skx := TyJsTan(ASkewX) else skx := 0;
  if ASkewY <> 0 then sky := TyJsTan(-ASkewY) else sky := 0;
  if (AOX <> 0) or (AOY <> 0) or (AAX <> 0) or (AAY <> 0) then
  begin
    dx := AOX + AAX;
    dy := AOY + AAY;
    m[4] := -dx * ASX - skx * dy * ASY;
    m[5] := -dy * ASY - sky * dx * ASX;
  end
  else
  begin
    m[4] := 0;
    m[5] := 0;
  end;
  m[0] := ASX;
  m[3] := ASY;
  m[1] := sky * ASX;
  m[2] := skx * ASY;
  if ARotation <> 0 then
  begin
    aa := m[0]; ac := m[2]; atx := m[4];
    ab := m[1]; ad := m[3]; aty := m[5];
    st := TyJsSin(ARotation);
    ct := TyJsCos(ARotation);
    m[0] := aa * ct + ab * st;
    m[1] := -aa * st + ab * ct;
    m[2] := ac * ct + ad * st;
    m[3] := -ac * st + ct * ad;
    m[4] := ct * (atx - 0) + st * (aty - 0) + 0;
    m[5] := ct * (aty - 0) - st * (atx - 0) + 0;
  end;
  m[4] := m[4] + (AOX + AX);
  m[5] := m[5] + (AOY + AY);
  Result := m;
end;

function TyGfxLocalTransform(AEl: TTyGfxEl): TTyMat2D;
begin
  Result := LocalOf(AEl.X, AEl.Y, AEl.Rotation, AEl.ScaleX, AEl.ScaleY,
    AEl.OriginX, AEl.OriginY, AEl.SkewX, AEl.SkewY, AEl.AnchorX, AEl.AnchorY);
end;

procedure UpdateOne(AEl: TTyGfxEl);
var
  need, hasParent: Boolean;
  pm: TTyMat2D;
begin
  hasParent := (AEl.Parent <> nil) and AEl.Parent.HasTransform;
  if hasParent then pm := AEl.Parent.Transform;
  need := TyGfxNeedLocal(AEl);
  if not (need or hasParent) then
  begin
    AEl.HasTransform := False;
    AEl.Transform := TyMatIdentity;
    Exit;
  end;
  if need then AEl.Transform := TyGfxLocalTransform(AEl)
  else AEl.Transform := TyMatIdentity;
  if hasParent then
  begin
    if need then AEl.Transform := TyMatMul(pm, AEl.Transform)
    else AEl.Transform := pm;
  end;
  AEl.HasTransform := True;
end;

procedure TyGfxLabelTransform(AText: TTyGfxEl; out AHas: Boolean; out AM: TTyMat2D);
var
  local, need: Boolean;
  d: TJSONData;
  host: TTyGfxEl;
begin
  AHas := False;
  AM := TyMatIdentity;
  host := AText.Host;
  local := False;
  if (host <> nil) and (host.TextConfig <> nil) then
  begin
    d := host.TextConfig.Find('local');
    local := (d <> nil) and (d.JSONType = jtBoolean) and d.AsBoolean;
  end;
  need := not AroundZero(AText.InRot) or not AroundZero(AText.InX)
    or not AroundZero(AText.InY) or not AroundZero(AText.ScaleX - 1)
    or not AroundZero(AText.ScaleY - 1) or not AroundZero(AText.SkewX)
    or not AroundZero(AText.SkewY);
  if local and (host <> nil) and host.HasTransform then
  begin
    if need then
      AM := TyMatMul(host.Transform, LocalOf(AText.InX, AText.InY, AText.InRot,
        AText.ScaleX, AText.ScaleY, AText.InOX, AText.InOY, AText.SkewX,
        AText.SkewY, AText.AnchorX, AText.AnchorY))
    else
      AM := host.Transform;
    AHas := True;
    Exit;
  end;
  if need then
  begin
    AM := LocalOf(AText.InX, AText.InY, AText.InRot, AText.ScaleX, AText.ScaleY,
      AText.InOX, AText.InOY, AText.SkewX, AText.SkewY, AText.AnchorX, AText.AnchorY);
    AHas := True;
  end;
end;

procedure TyGfxUpdateTransforms(AEl: TTyGfxEl);
var i: Integer;
begin
  if AEl = nil then Exit;
  UpdateOne(AEl);
  if AEl.TextContent <> nil then
    TyGfxLabelTransform(AEl.TextContent, AEl.TextContent.HasTransform,
      AEl.TextContent.Transform);
  for i := 0 to High(AEl.Children) do TyGfxUpdateTransforms(AEl.Children[i]);
end;

{ ==================== the style ==================== }

function ColourText(const V: TTyAnimValue): string;
begin
  if V.Kind = avkString then Result := V.Str else Result := '';
end;

function TyGfxHasFill(AEl: TTyGfxEl): Boolean;
var v: TTyAnimValue; d: TJSONData;
begin
  d := AEl.Style.Find('fill');
  if d <> nil then
  begin
    if JNull(d) then Exit(False);
    if d.JSONType = jtString then Exit(d.AsString <> 'none');
    Exit(True);
  end;
  v := AEl.StyleValue('fill');
  Result := (v.Kind = avkString) and (v.Str <> 'none');
end;

function TyGfxLineWidth(AEl: TTyGfxEl): Double;
var v: TTyAnimValue;
begin
  v := AEl.StyleValue('lineWidth');
  if v.Kind = avkNumber then Result := v.Num
  else Result := NaN;
end;

function TyGfxHasStroke(AEl: TTyGfxEl): Boolean;
var d: TJSONData;
begin
  d := AEl.Style.Find('stroke');
  if JNull(d) then Exit(False);
  if (d.JSONType = jtString) and (d.AsString = 'none') then Exit(False);
  Result := TyGfxLineWidth(AEl) > 0;
end;

{ ==================== paths ==================== }

function ShapeNum(AEl: TTyGfxEl; const AKey: string): Double;
var d: TJSONData;
begin
  d := AEl.Shape.Find(AKey);
  if d = nil then Exit(NaN);
  Result := JsNum(d);
end;

function ShapeHas(AEl: TTyGfxEl; const AKey: string): Boolean;
begin
  Result := not JNull(AEl.Shape.Find(AKey));
end;

function PointsOf(AData: TJSONData): TTyPointFArray;
var i: Integer; p: TJSONData;
begin
  Result := nil;
  if not (AData is TJSONArray) then Exit;
  SetLength(Result, AData.Count);
  for i := 0 to AData.Count - 1 do
  begin
    p := AData.Items[i];
    if (p is TJSONArray) and (p.Count >= 2) then
      Result[i] := TyPointF(JsNum(p.Items[0]), JsNum(p.Items[1]))
    else
      Result[i] := TyPointF(NaN, NaN);
  end;
end;

function JMin(A, B: Double): Double; inline;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if A < B then Result := A else Result := B;
end;

function JMax(A, B: Double): Double; inline;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if A > B then Result := A else Result := B;
end;

function TyGfxSmoothBezier(const APoints: TTyPointFArray; ASmooth: Double;
  AIsLoop: Boolean; AHasConstraint: Boolean; const AMin, AMax: TTyPointF): TTyPointFArray;
var
  mn, mx, prevP, nextP, v, cp0, cp1: TTyPointF;
  i, len, n: Integer;
  d0, d1, sum: Double;
  first: TTyPointF;

  procedure Push(const P: TTyPointF);
  begin
    SetLength(Result, n + 1);
    Result[n] := P;
    Inc(n);
  end;

begin
  Result := nil;
  n := 0;
  len := Length(APoints);
  mn := TyPointF(Infinity, Infinity);
  mx := TyPointF(NegInfinity, NegInfinity);
  if AHasConstraint then
  begin
    for i := 0 to len - 1 do
    begin
      mn.X := JMin(mn.X, APoints[i].X);
      mn.Y := JMin(mn.Y, APoints[i].Y);
      mx.X := JMax(mx.X, APoints[i].X);
      mx.Y := JMax(mx.Y, APoints[i].Y);
    end;
    mn.X := JMin(mn.X, AMin.X);
    mn.Y := JMin(mn.Y, AMin.Y);
    mx.X := JMax(mx.X, AMax.X);
    mx.Y := JMax(mx.Y, AMax.Y);
  end;
  for i := 0 to len - 1 do
  begin
    if AIsLoop then
    begin
      if i > 0 then prevP := APoints[i - 1] else prevP := APoints[len - 1];
      nextP := APoints[(i + 1) mod len];
    end
    else
    begin
      if (i = 0) or (i = len - 1) then
      begin
        Push(APoints[i]);
        Continue;
      end;
      prevP := APoints[i - 1];
      nextP := APoints[i + 1];
    end;
    v.X := nextP.X - prevP.X;
    v.Y := nextP.Y - prevP.Y;
    v.X := v.X * ASmooth;
    v.Y := v.Y * ASmooth;
    d0 := Sqrt((APoints[i].X - prevP.X) * (APoints[i].X - prevP.X)
      + (APoints[i].Y - prevP.Y) * (APoints[i].Y - prevP.Y));
    d1 := Sqrt((APoints[i].X - nextP.X) * (APoints[i].X - nextP.X)
      + (APoints[i].Y - nextP.Y) * (APoints[i].Y - nextP.Y));
    sum := d0 + d1;
    if sum <> 0 then
    begin
      d0 := d0 / sum;
      d1 := d1 / sum;
    end;
    cp0.X := APoints[i].X + v.X * -d0;
    cp0.Y := APoints[i].Y + v.Y * -d0;
    cp1.X := APoints[i].X + v.X * d1;
    cp1.Y := APoints[i].Y + v.Y * d1;
    if AHasConstraint then
    begin
      cp0.X := JMax(cp0.X, mn.X); cp0.Y := JMax(cp0.Y, mn.Y);
      cp0.X := JMin(cp0.X, mx.X); cp0.Y := JMin(cp0.Y, mx.Y);
      cp1.X := JMax(cp1.X, mn.X); cp1.Y := JMax(cp1.Y, mn.Y);
      cp1.X := JMin(cp1.X, mx.X); cp1.Y := JMin(cp1.Y, mx.Y);
    end;
    Push(cp0);
    Push(cp1);
  end;
  if AIsLoop and (n > 0) then
  begin
    first := Result[0];
    for i := 0 to n - 2 do Result[i] := Result[i + 1];
    Result[n - 1] := first;
  end;
end;

procedure PolyPath(AEl: TTyGfxEl; AClose: Boolean; var APath: TTyZrPath);
var
  pts, cps: TTyPointFArray;
  smooth: Double;
  i, len: Integer;
  con: TTyPointFArray;
  hasCon: Boolean;
  d: TJSONData;
begin
  pts := PointsOf(AEl.Shape.Find('points'));
  len := Length(pts);
  if len < 2 then Exit;
  d := AEl.Shape.Find('smooth');
  smooth := JsNum(d);
  { `if (smooth)`: nought, NaN and an absent key take the straight path }
  if (d <> nil) and not JNull(d) and (smooth <> 0) and not IsNan(smooth) then
  begin
    con := PointsOf(AEl.Shape.Find('smoothConstraint'));
    hasCon := Length(con) >= 2;
    if hasCon then
      cps := TyGfxSmoothBezier(pts, smooth, AClose, True, con[0], con[1])
    else
      cps := TyGfxSmoothBezier(pts, smooth, AClose, False, TyPointF(0, 0), TyPointF(0, 0));
    TyZrMoveTo(APath, pts[0].X, pts[0].Y);
    if AClose then
    begin
      for i := 0 to len - 1 do
        TyZrCubic(APath, cps[i * 2].X, cps[i * 2].Y, cps[i * 2 + 1].X, cps[i * 2 + 1].Y,
          pts[(i + 1) mod len].X, pts[(i + 1) mod len].Y);
    end
    else
      for i := 0 to len - 2 do
        TyZrCubic(APath, cps[i * 2].X, cps[i * 2].Y, cps[i * 2 + 1].X, cps[i * 2 + 1].Y,
          pts[(i + 1) mod len].X, pts[(i + 1) mod len].Y);
  end
  else
  begin
    TyZrMoveTo(APath, pts[0].X, pts[0].Y);
    for i := 1 to len - 1 do TyZrLineTo(APath, pts[i].X, pts[i].Y);
  end;
  if AClose then TyZrClose(APath);
end;

procedure AddQuad(var APath: TTyZrPath; AX1, AY1, AX, AY: Double);
var n: Integer;
begin
  n := Length(APath);
  SetLength(APath, n + 1);
  FillChar(APath[n].V, SizeOf(APath[n].V), 0);
  APath[n].Cmd := zrQ;
  APath[n].V[0] := AX1;
  APath[n].V[1] := AY1;
  APath[n].V[2] := AX;
  APath[n].V[3] := AY;
end;

function TyGfxPath(AEl: TTyGfxEl): TTyZrPath;
var
  x, y, w, h, r, r0, sa, ea, k, a, b, ox, oy, pct, x1, y1, x2, y2, cpx1, cpy1,
    cpx2, cpy2, p01, p12, p23, p012, p123: Double;
  r1, r2, r3, r4: Double;
  d: TJSONData;
  vals: array of Double;
  i: Integer;
  cw: Boolean;
  s: TTyPolarSector;
  corners: TTyDoubleArray;
  mask: TFPUExceptionMask;
begin
  Result := nil;
  if AEl = nil then Exit;
  mask := GetExceptionMask;
  SetExceptionMask(mask + [exInvalidOp, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  try
    case AEl.Kind of
      gkRect:
        begin
          x := ShapeNum(AEl, 'x'); y := ShapeNum(AEl, 'y');
          w := ShapeNum(AEl, 'width'); h := ShapeNum(AEl, 'height');
          d := AEl.Shape.Find('r');
          { `if (!shape.r)`: nothing, nought, an empty text -- but an array is
            always there }
          if (d = nil) or JNull(d) or ((d.JSONType = jtNumber) and ((d.AsFloat = 0) or IsNan(d.AsFloat)))
            or ((d.JSONType = jtString) and (d.AsString = ''))
            or ((d.JSONType = jtBoolean) and not d.AsBoolean) then
            TyZrRect(Result, x, y, w, h)
          else
          begin
            if d is TJSONArray then
            begin
              vals := nil;
              SetLength(vals, d.Count);
              for i := 0 to d.Count - 1 do vals[i] := JsNum(d.Items[i]);
              TyZrRadii(vals, r1, r2, r3, r4);
            end
            else if d.JSONType = jtNumber then
            begin
              r1 := d.AsFloat; r2 := r1; r3 := r1; r4 := r1;
            end
            else
            begin
              r1 := 0; r2 := 0; r3 := 0; r4 := 0;
            end;
            TyZrRoundRect(Result, x, y, w, h, r1, r2, r3, r4);
          end;
        end;
      gkCircle:
        begin
          x := ShapeNum(AEl, 'cx'); y := ShapeNum(AEl, 'cy'); r := ShapeNum(AEl, 'r');
          TyZrMoveTo(Result, x + r, y);
          TyZrArc(Result, x, y, r, 0, Pi * 2, False);
        end;
      gkEllipse:
        begin
          k := 0.5522848;
          x := ShapeNum(AEl, 'cx'); y := ShapeNum(AEl, 'cy');
          a := ShapeNum(AEl, 'rx'); b := ShapeNum(AEl, 'ry');
          ox := a * k;
          oy := b * k;
          TyZrMoveTo(Result, x - a, y);
          TyZrCubic(Result, x - a, y - oy, x - ox, y - b, x, y - b);
          TyZrCubic(Result, x + ox, y - b, x + a, y - oy, x + a, y);
          TyZrCubic(Result, x + a, y + oy, x + ox, y + b, x, y + b);
          TyZrCubic(Result, x - ox, y + b, x - a, y + oy, x - a, y);
          TyZrClose(Result);
        end;
      gkRing:
        begin
          x := ShapeNum(AEl, 'cx'); y := ShapeNum(AEl, 'cy');
          r := ShapeNum(AEl, 'r'); r0 := ShapeNum(AEl, 'r0');
          TyZrMoveTo(Result, x + r, y);
          TyZrArc(Result, x, y, r, 0, PI2, False);
          TyZrMoveTo(Result, x + r0, y);
          TyZrArc(Result, x, y, r0, 0, PI2, True);
        end;
      gkSector:
        begin
          s.CX := ShapeNum(AEl, 'cx');
          s.CY := ShapeNum(AEl, 'cy');
          s.R0 := ShapeNum(AEl, 'r0');
          if IsNan(s.R0) then s.R0 := 0;
          s.R := ShapeNum(AEl, 'r');
          s.SA := ShapeNum(AEl, 'startAngle');
          s.EA := ShapeNum(AEl, 'endAngle');
          d := AEl.Shape.Find('clockwise');
          s.CW := not ((d <> nil) and (((d.JSONType = jtBoolean) and not d.AsBoolean)
            or JNull(d) or ((d.JSONType = jtNumber) and (d.AsFloat = 0))));
          corners := nil;
          d := AEl.Shape.Find('cornerRadius');
          if d is TJSONArray then
          begin
            SetLength(corners, d.Count);
            for i := 0 to d.Count - 1 do corners[i] := JsNum(d.Items[i]);
          end
          else if (d <> nil) and (d.JSONType = jtNumber) and (d.AsFloat <> 0)
            and not IsNan(d.AsFloat) then
          begin
            SetLength(corners, 4);
            for i := 0 to 3 do corners[i] := d.AsFloat;
          end;
          Result := TyZrSectorPath(s, corners);
        end;
      gkArc:
        begin
          x := ShapeNum(AEl, 'cx'); y := ShapeNum(AEl, 'cy');
          r := JMax(ShapeNum(AEl, 'r'), 0);
          sa := ShapeNum(AEl, 'startAngle');
          ea := ShapeNum(AEl, 'endAngle');
          d := AEl.Shape.Find('clockwise');
          cw := not ((d <> nil) and (((d.JSONType = jtBoolean) and not d.AsBoolean)
            or JNull(d) or ((d.JSONType = jtNumber) and (d.AsFloat = 0))));
          TyZrMoveTo(Result, TyJsCos(sa) * r + x, TyJsSin(sa) * r + y);
          TyZrArc(Result, x, y, r, sa, ea, not cw);
        end;
      gkPolygon: PolyPath(AEl, True, Result);
      gkPolyline: PolyPath(AEl, False, Result);
      gkPath: Result := Copy(AEl.PathData);
      gkLine:
        begin
          x1 := ShapeNum(AEl, 'x1'); y1 := ShapeNum(AEl, 'y1');
          x2 := ShapeNum(AEl, 'x2'); y2 := ShapeNum(AEl, 'y2');
          pct := ShapeNum(AEl, 'percent');
          if (AEl.Shape.Find('percent') <> nil) and (AEl.Shape.Find('percent').JSONType = jtNumber)
            and (pct = 0) then Exit;
          TyZrMoveTo(Result, x1, y1);
          if pct < 1 then
          begin
            x2 := x1 * (1 - pct) + x2 * pct;
            y2 := y1 * (1 - pct) + y2 * pct;
          end;
          TyZrLineTo(Result, x2, y2);
        end;
      gkBezier:
        begin
          x1 := ShapeNum(AEl, 'x1'); y1 := ShapeNum(AEl, 'y1');
          x2 := ShapeNum(AEl, 'x2'); y2 := ShapeNum(AEl, 'y2');
          cpx1 := ShapeNum(AEl, 'cpx1'); cpy1 := ShapeNum(AEl, 'cpy1');
          pct := ShapeNum(AEl, 'percent');
          if (AEl.Shape.Find('percent') <> nil) and (AEl.Shape.Find('percent').JSONType = jtNumber)
            and (pct = 0) then Exit;
          TyZrMoveTo(Result, x1, y1);
          if not ShapeHas(AEl, 'cpx2') or not ShapeHas(AEl, 'cpy2') then
          begin
            if pct < 1 then
            begin
              { quadraticSubdivide, the first half }
              p01 := (cpx1 - x1) * pct + x1;
              p12 := (x2 - cpx1) * pct + cpx1;
              cpx1 := p01;
              x2 := (p12 - p01) * pct + p01;
              p01 := (cpy1 - y1) * pct + y1;
              p12 := (y2 - cpy1) * pct + cpy1;
              cpy1 := p01;
              y2 := (p12 - p01) * pct + p01;
            end;
            AddQuad(Result, cpx1, cpy1, x2, y2);
          end
          else
          begin
            cpx2 := ShapeNum(AEl, 'cpx2');
            cpy2 := ShapeNum(AEl, 'cpy2');
            if pct < 1 then
            begin
              { cubicSubdivide, the first half }
              p01 := (cpx1 - x1) * pct + x1;
              p12 := (cpx2 - cpx1) * pct + cpx1;
              p23 := (x2 - cpx2) * pct + cpx2;
              p012 := (p12 - p01) * pct + p01;
              p123 := (p23 - p12) * pct + p12;
              cpx1 := p01;
              cpx2 := p012;
              x2 := (p123 - p012) * pct + p012;
              p01 := (cpy1 - y1) * pct + y1;
              p12 := (cpy2 - cpy1) * pct + cpy1;
              p23 := (y2 - cpy2) * pct + cpy2;
              p012 := (p12 - p01) * pct + p01;
              p123 := (p23 - p12) * pct + p12;
              cpy1 := p01;
              cpy2 := p012;
              y2 := (p123 - p012) * pct + p012;
            end;
            TyZrCubic(Result, cpx1, cpy1, cpx2, cpy2, x2, y2);
          end;
        end;
    end;
  finally
    ClearExceptions(False);
    SetExceptionMask(mask);
  end;
end;

{ ==================== text ==================== }

function TyGfxMakeFont(AStyle: TJSONObject): string;
var
  fs, ff, fw, st, sz: string;
  d: TJSONData;
  n: Double;

  function Part(A: TJSONData): string;
  begin
    if JNull(A) then Exit('');
    case A.JSONType of
      jtString: Result := A.AsString;
      jtNumber: Result := TyJsNumberToString(A.AsFloat);
      jtBoolean: if A.AsBoolean then Result := 'true' else Result := 'false';
    else
      Result := '';
    end;
  end;

begin
  Result := '';
  if AStyle = nil then Exit;
  d := AStyle.Find('fontSize');
  { hasSeparateFont: fontSize != null, or a truthy family or weight }
  if not JNull(d) or (Part(AStyle.Find('fontFamily')) <> '')
    or ((AStyle.Find('fontWeight') <> nil) and not JNull(AStyle.Find('fontWeight'))
      and not ((AStyle.Find('fontWeight').JSONType = jtNumber) and (AStyle.Find('fontWeight').AsFloat = 0))
      and (Part(AStyle.Find('fontWeight')) <> '')) then
  begin
    { parseFontSize: a text with 'px' (or em, rem, pt ...) as it is, a
      number-like value plus 'px', else 12px }
    sz := '';
    if (d <> nil) and (d.JSONType = jtString) and ((Pos('px', d.AsString) > 0)
      or (Pos('rem', d.AsString) > 0) or (Pos('em', d.AsString) > 0)) then
      sz := d.AsString
    else
    begin
      n := JsNum(d);
      if JNull(d) then n := NaN;
      if not IsNan(n) then sz := Part(d) + 'px'
      else sz := '12px';
    end;
    st := Part(AStyle.Find('fontStyle'));
    fw := Part(AStyle.Find('fontWeight'));
    ff := Part(AStyle.Find('fontFamily'));
    if ff = '' then ff := 'sans-serif';
    fs := st + ' ' + fw + ' ' + sz + ' ' + ff;
    Result := Trim(fs);
  end;
  if Result = '' then
  begin
    Result := Part(AStyle.Find('textFont'));
    if Result = '' then Result := Part(AStyle.Find('font'));
  end;
end;

procedure TyGfxParseFont(const AFont: string; out APx: Double;
  out AWeight: Integer; out AFamily: string; out AItalic: Boolean);
var
  i, j, k, sizeEnd: Integer;
  num, tok, f: string;
  fs: TFormatSettings;
  v: Double;
  parts: TStringArray;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  f := AFont;
  if f = '' then f := '12px sans-serif';
  APx := 12;
  AWeight := 400;
  AItalic := False;
  AFamily := 'sans-serif';
  { the measure's /((?:\d+)?\.?\d*)px/: the first 'px' preceded by a number }
  sizeEnd := 0;
  i := Pos('px', f);
  while i > 0 do
  begin
    j := i - 1;
    while (j >= 1) and (f[j] in ['0'..'9', '.']) do Dec(j);
    num := Copy(f, j + 1, i - j - 1);
    if TryStrToFloat(num, v, fs) and (v > 0) then
    begin
      APx := v;
      sizeEnd := i + 1;
      Break;
    end
    else if num <> '' then
    begin
      sizeEnd := i + 1;
      Break;
    end;
    k := Pos('px', Copy(f, i + 2, MaxInt));
    if k = 0 then Break;
    i := i + 1 + k;
  end;
  if sizeEnd > 0 then
  begin
    AFamily := Trim(Copy(f, sizeEnd + 1, MaxInt));
    if AFamily = '' then AFamily := 'sans-serif';
    parts := Trim(Copy(f, 1, sizeEnd - 2 - Length(num))).Split([' ']);
  end
  else
  begin
    parts := f.Split([' ']);
    AFamily := f;
  end;
  for k := 0 to High(parts) do
  begin
    tok := LowerCase(Trim(parts[k]));
    if (tok = 'bold') or (tok = 'bolder') then AWeight := 700
    else if tok = 'lighter' then AWeight := 300
    else if (tok = 'italic') or (tok = 'oblique') then AItalic := True
    else if TryStrToFloat(tok, v, fs) and (v >= 1) and (v <= 1000) then AWeight := Round(v);
  end;
end;

type
  TColRead = (cdNone, cdColour, cdOff);

{ getFill / getStroke of a text: null or 'none' draws nothing, an image or
  a gradient '#000', a string as it is }
function TextColour(A: TJSONData; out AC: TTyChartColor): TColRead;
begin
  AC := 0;
  if JNull(A) then Exit(cdOff);
  if A.JSONType = jtString then
  begin
    if A.AsString = 'none' then Exit(cdOff);
    if TyTryParseChartColor(A.AsString, AC) then Exit(cdColour);
    Exit(cdOff);
  end;
  if A is TJSONObject then
  begin
    AC := $FF000000;
    Exit(cdColour);
  end;
  Result := cdOff;
end;

{ normalizeStyle: 'middle' is 'center', a word it does not know 'left' }
function AlignStr(const S: string): TTyRtAlign;
begin
  if (S = 'center') or (S = 'middle') then Result := rtaCenter
  else if S = 'right' then Result := rtaRight
  else Result := rtaLeft;
end;

{ 'center' is 'middle', a word it does not know 'top' }
function VAlignStr(const S: string): TTyRtVAlign;
begin
  if (S = 'middle') or (S = 'center') then Result := rtvMiddle
  else if S = 'bottom' then Result := rtvBottom
  else Result := rtvTop;
end;

function AlignWord(A: TJSONData): TTyRtAlign;
begin
  if JNull(A) then Exit(rtaNone);
  Result := AlignStr(StrOf(A));
end;

function VAlignWord(A: TJSONData): TTyRtVAlign;
begin
  if JNull(A) then Exit(rtvNone);
  Result := VAlignStr(StrOf(A));
end;

procedure Spread4(A: TJSONData; out AV: array of Double; out AHas: Boolean);
var
  n, k: Integer;
  x: Double;
begin
  AHas := False;
  for k := 0 to 3 do AV[k] := 0;
  if JNull(A) then Exit;
  if NumOf(A, x) then
  begin
    for k := 0 to 3 do AV[k] := x;
    AHas := True;
    Exit;
  end;
  if not (A is TJSONArray) then Exit;
  n := A.Count;
  for k := 0 to Min(n, 4) - 1 do AV[k] := JsNum(A.Items[k]);
  case n of
    0: Exit;
    1: begin AV[1] := AV[0]; AV[2] := AV[0]; AV[3] := AV[0]; end;
    2: begin AV[2] := AV[0]; AV[3] := AV[1]; end;
    3: AV[3] := AV[1];
  end;
  AHas := True;
end;

{ one TextStylePropsPart as zrender holds it after normalizeStyle; the font
  given as the makeFont string AFont }
procedure ReadPart(S: TJSONObject; const AFont: string; out R: TTyRtStyle);
var
  d: TJSONData;
  c: TTyChartColor;
  x: Double;
  s_: string;
  pad: array[0..3] of Double;
  has: Boolean;
  k: Integer;
  fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  R := Default(TTyRtStyle);
  TyGfxParseFont(AFont, R.FontSizePx, R.FontWeight, R.FontFamily, R.FontItalic);
  R.OwnFontFamily := True;
  R.OwnFontSize := True;
  R.OwnFontWeight := True;
  if S = nil then Exit;
  d := S.Find('fill');
  if d <> nil then
  begin
    R.HasFill := True;
    case TextColour(d, c) of
      cdColour: R.Fill := c;
    else
      R.FillNone := True;
    end;
  end;
  d := S.Find('stroke');
  if d <> nil then
  begin
    R.HasStroke := True;
    case TextColour(d, c) of
      cdColour: R.Stroke := c;
    else
      R.StrokeNone := True;
    end;
  end;
  if NumOf(S.Find('lineWidth'), x) then
  begin
    R.HasLineWidth := True;
    R.LineWidth := x;
  end;
  { [R2-F] the stroke's dashes and their phase, as written (Text.ts hands
    lineDash and lineDashOffset to every TSpan that strokes) }
  R.LineDash := TyDashTextOf(S.Find('lineDash'));
  if NumOf(S.Find('lineDashOffset'), x) then
  begin
    R.HasLineDashOffset := True;
    R.LineDashOffset := x;
  end;
  R.Align := AlignWord(S.Find('align'));
  R.VAlign := VAlignWord(S.Find('verticalAlign'));
  if NumOf(S.Find('lineHeight'), x) then
  begin
    R.HasLineHeight := True;
    R.LineHeight := x;
  end;
  d := S.Find('width');
  if NumOf(d, x) then
  begin
    R.WidthKind := rtwNumber;
    R.Width := x;
  end
  else if (d <> nil) and (d.JSONType = jtString) then
  begin
    s_ := Trim(d.AsString);
    if s_ = 'auto' then R.WidthKind := rtwAuto
    else if (s_ <> '') and (s_[Length(s_)] = '%')
      and TryStrToFloat(Copy(s_, 1, Length(s_) - 1), x, fs) then
    begin
      R.WidthKind := rtwPercent;
      R.Width := x;
    end
    else if TryStrToFloat(s_, x, fs) then
    begin
      R.WidthKind := rtwNumber;
      R.Width := x;
    end;
  end;
  if NumOf(S.Find('height'), x) then
  begin
    R.HasHeight := True;
    R.Height := x;
  end;
  Spread4(S.Find('padding'), pad, has);
  if has then
  begin
    R.HasPadding := True;
    for k := 0 to 3 do R.Padding[k] := pad[k];
  end;
  if NumOf(S.Find('borderWidth'), x) then R.BorderWidth := x;
  Spread4(S.Find('borderRadius'), pad, has);
  if has then for k := 0 to 3 do R.Radius[k] := pad[k];
  d := S.Find('backgroundColor');
  if (d <> nil) and (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, c) then
  begin
    R.HasBackground := True;
    R.Background := c;
  end
  { [R2-F] {image: src}: a picture over the box }
  else if (d is TJSONObject) and (TJSONObject(d).Find('image') <> nil)
    and (TJSONObject(d).Find('image').JSONType = jtString) then
    R.BgImage := TJSONObject(d).Find('image').AsString;
  d := S.Find('borderColor');
  if (d <> nil) and (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, c) then
  begin
    R.HasBorderColor := True;
    R.BorderColor := c;
  end;
  { [R2-I2] the box's borderDash and borderDashOffset, zrender's own keys }
  R.BorderDash := TyDashTextOf(S.Find('borderDash'));
  if NumOf(S.Find('borderDashOffset'), x) then R.BorderDashOffset := x;
  if NumOf(S.Find('opacity'), x) then
  begin
    R.HasOpacity := True;
    R.Opacity := x;
  end;
  s_ := StrOf(S.Find('overflow'));
  if s_ = 'truncate' then R.Overflow := rtoTruncate
  else if s_ = 'break' then R.Overflow := rtoBreak
  else if s_ = 'breakAll' then R.Overflow := rtoBreakAll;
  R.LineOverflowTruncate := StrOf(S.Find('lineOverflow')) = 'truncate';
  d := S.Find('ellipsis');
  if (d <> nil) and (d.JSONType = jtString) then
  begin
    R.HasEllipsis := True;
    R.Ellipsis := d.AsString;
  end;
  if NumOf(S.Find('truncateMinChar'), x) then R.MinChar := Round(x);
  d := S.Find('textShadowColor');
  if (d <> nil) and (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, c) then
  begin
    R.HasShadowColor := True;
    R.ShadowColor := c;
  end;
  if NumOf(S.Find('textShadowBlur'), x) then R.ShadowBlur := x;
  if NumOf(S.Find('textShadowOffsetX'), x) then R.ShadowOffsetX := x;
  if NumOf(S.Find('textShadowOffsetY'), x) then R.ShadowOffsetY := x;
end;

function TextOf(S: TJSONObject): string;
var d: TJSONData;
begin
  Result := '';
  if S = nil then Exit;
  d := S.Find('text');
  if JNull(d) then Exit;
  case d.JSONType of
    jtString: Result := d.AsString;
    jtNumber: Result := TyJsNumberToString(d.AsFloat);
    jtBoolean: if d.AsBoolean then Result := 'true' else Result := 'false';
  else
    Result := '';
  end;
end;

function TyGfxTextLayout(AEl: TTyGfxEl; const AMeasurer: ITyTextMeasurer): TTyRtResult;
var
  st: TTyRtStyle;
  rich: TTyRtRich;
  blockFont, f: string;
  d, rs: TJSONData;
  i: Integer;
  isRich: Boolean;
  def: TTyRtDefault;
  c: TTyChartColor;
  bx, by: Double;
begin
  Result := Default(TTyRtResult);
  if AEl = nil then Exit;
  blockFont := TyGfxMakeFont(AEl.Style);
  if blockFont = '' then blockFont := '12px sans-serif';
  ReadPart(AEl.Style, blockFont, st);
  rich := nil;
  rs := AEl.Style.Find('rich');
  isRich := (rs <> nil) and not JNull(rs) and (rs.JSONType <> jtBoolean);
  if isRich and (rs is TJSONObject) then
  begin
    SetLength(rich, rs.Count);
    for i := 0 to rs.Count - 1 do
    begin
      rich[i].Name := TJSONObject(rs).Names[i];
      d := rs.Items[i];
      if d is TJSONObject then
      begin
        f := TyGfxMakeFont(TJSONObject(d));
        if f = '' then f := blockFont;
        ReadPart(TJSONObject(d), f, rich[i].Style);
      end
      else
        ReadPart(nil, blockFont, rich[i].Style);
    end;
  end;
  { the default style: the host's, else DEFAULT_RICH_TEXT_COLOR }
  def := Default(TTyRtDefault);
  if (AEl.Host <> nil) and AEl.HasDefault then
  begin
    def.HasFill := (AEl.DefFill <> '') and TyTryParseChartColor(AEl.DefFill, c);
    if def.HasFill then def.Fill := c;
    def.HasStroke := (AEl.DefStroke <> '') and TyTryParseChartColor(AEl.DefStroke, c);
    if def.HasStroke then def.Stroke := c;
    def.AutoStroke := AEl.DefAutoStroke;
    def.Align := rtaNone;
    if AEl.DefAlign <> '' then def.Align := AlignStr(AEl.DefAlign);
    def.VAlign := rtvNone;
    if AEl.DefVAlign <> '' then def.VAlign := VAlignStr(AEl.DefVAlign);
  end
  else
  begin
    def.HasFill := True;
    def.Fill := $FF000000;
  end;
  bx := 0;
  by := 0;
  if NumOf(AEl.Style.Find('x'), bx) then else bx := 0;
  if NumOf(AEl.Style.Find('y'), by) then else by := 0;
  Result := TyRtLayout(TextOf(AEl.Style), st, rich, isRich, def, bx, by, AMeasurer);
end;

{ ==================== bounding rects ==================== }

function TyGfxRect(AEl: TTyGfxEl; const AMeasurer: ITyTextMeasurer): TTyXYWH;
var
  path: TTyZrPath;
  i: Integer;
  have: Boolean;
  r: TTyRtResult;
  w, h, x: Double;
begin
  Result := TyXYWH(0, 0, 0, 0);
  if AEl = nil then Exit;
  case AEl.Kind of
    gkGroup:
      begin
        have := False;
        for i := 0 to High(AEl.Children) do
        begin
          if AEl.Children[i].Ignore or AEl.Children[i].Invisible then Continue;
          TyZrAccumulate(Result, have, TyGfxRect(AEl.Children[i], AMeasurer),
            TyGfxLocalTransform(AEl.Children[i]));
        end;
        if not have then Result := TyXYWH(0, 0, 0, 0);
      end;
    gkImage:
      begin
        if NumOf(AEl.Style.Find('x'), x) then Result.X := x else Result.X := 0;
        if NumOf(AEl.Style.Find('y'), x) then Result.Y := x else Result.Y := 0;
        if IsNan(Result.X) then Result.X := 0;
        if IsNan(Result.Y) then Result.Y := 0;
        w := JsNum(AEl.Style.Find('width'));
        h := JsNum(AEl.Style.Find('height'));
        if JNull(AEl.Style.Find('width')) then w := 0;
        if JNull(AEl.Style.Find('height')) then h := 0;
        Result.W := w;
        Result.H := h;
      end;
    gkText:
      begin
        r := TyGfxTextLayout(AEl, AMeasurer);
        if Length(r.Pieces) = 0 then Exit;
        Result := TyRtBounds(r.Pieces);
      end;
    gkUnknown: ;
  else
    path := TyGfxPath(AEl);
    Result := TyZrStrokeRect(TyZrBBox(path), TyZrDataLength(path),
      TyGfxHasStroke(AEl), TyGfxHasFill(AEl), TyGfxLineWidth(AEl),
      TyGfxLineScale(AEl));
  end;
end;

function TyGfxStrokeNoScale(AEl: TTyGfxEl): Boolean;
var d: TJSONData;
begin
  d := AEl.Style.Find('strokeNoScale');
  Result := (d <> nil) and (((d.JSONType = jtBoolean) and d.AsBoolean)
    or ((d.JSONType = jtNumber) and (d.AsFloat <> 0) and not IsNan(d.AsFloat))
    or ((d.JSONType = jtString) and (d.AsString <> '')));
end;

function TyGfxLineScale(AEl: TTyGfxEl): Double;
var m: TTyMat2D;
begin
  Result := 1;
  if (AEl = nil) or not TyGfxStrokeNoScale(AEl) or not AEl.HasTransform then Exit;
  m := AEl.Transform;
  if (Abs(m[0] - 1) > 1e-10) and (Abs(m[3] - 1) > 1e-10) then
    Result := Sqrt(Abs(m[0] * m[3] - m[2] * m[1]));
end;

{ ==================== a textContent ==================== }

function JsParsePercent(A: TJSONData; AMax: Double): Double;
var s: string; fs: TFormatSettings; v: Double; i: Integer;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  if (A <> nil) and (A.JSONType = jtString) then
  begin
    s := Trim(A.AsString);
    { parseFloat: the longest leading number }
    i := 1;
    while (i <= Length(s)) and (s[i] in ['0'..'9', '.', '-', '+', 'e', 'E']) do Inc(i);
    if not TryStrToFloat(Copy(s, 1, i - 1), v, fs) then v := NaN;
    if LastDelimiter('%', A.AsString) > 0 then Result := v / 100 * AMax
    else Result := v;
    Exit;
  end;
  Result := JsNum(A);
end;

procedure TyGfxTextPosition(APosition: TJSONData; ADistance: Double;
  const ARect: TTyXYWH; out AX, AY: Double; out AAlign, AVAlign: string);
var
  pos: string;
  w, h, hh: Double;
begin
  w := ARect.W;
  h := ARect.H;
  hh := h / 2;
  AX := ARect.X;
  AY := ARect.Y;
  AAlign := 'left';
  AVAlign := 'top';
  if APosition is TJSONArray then
  begin
    if APosition.Count > 0 then AX := AX + JsParsePercent(APosition.Items[0], ARect.W)
    else AX := NaN;
    if APosition.Count > 1 then AY := AY + JsParsePercent(APosition.Items[1], ARect.H)
    else AY := NaN;
    AAlign := '';
    AVAlign := '';
    Exit;
  end;
  pos := StrOf(APosition);
  if pos = '' then pos := 'inside';
  if pos = 'left' then
  begin
    AX := AX - ADistance; AY := AY + hh; AAlign := 'right'; AVAlign := 'middle';
  end
  else if pos = 'right' then
  begin
    AX := AX + ADistance + w; AY := AY + hh; AVAlign := 'middle';
  end
  else if pos = 'top' then
  begin
    AX := AX + w / 2; AY := AY - ADistance; AAlign := 'center'; AVAlign := 'bottom';
  end
  else if pos = 'bottom' then
  begin
    AX := AX + w / 2; AY := AY + h + ADistance; AAlign := 'center';
  end
  else if pos = 'inside' then
  begin
    AX := AX + w / 2; AY := AY + hh; AAlign := 'center'; AVAlign := 'middle';
  end
  else if pos = 'insideLeft' then
  begin
    AX := AX + ADistance; AY := AY + hh; AVAlign := 'middle';
  end
  else if pos = 'insideRight' then
  begin
    AX := AX + w - ADistance; AY := AY + hh; AAlign := 'right'; AVAlign := 'middle';
  end
  else if pos = 'insideTop' then
  begin
    AX := AX + w / 2; AY := AY + ADistance; AAlign := 'center';
  end
  else if pos = 'insideBottom' then
  begin
    AX := AX + w / 2; AY := AY + h - ADistance; AAlign := 'center'; AVAlign := 'bottom';
  end
  else if pos = 'insideTopLeft' then
  begin
    AX := AX + ADistance; AY := AY + ADistance;
  end
  else if pos = 'insideTopRight' then
  begin
    AX := AX + w - ADistance; AY := AY + ADistance; AAlign := 'right';
  end
  else if pos = 'insideBottomLeft' then
  begin
    AX := AX + ADistance; AY := AY + h - ADistance; AVAlign := 'bottom';
  end
  else if pos = 'insideBottomRight' then
  begin
    AX := AX + w - ADistance; AY := AY + h - ADistance; AAlign := 'right'; AVAlign := 'bottom';
  end;
end;

{ zrender's lum(colour, 0) }
function LumOf(const AColour: string): Double;
var r, g, b, a: Double;
begin
  if TyTryParseCssRgba(AColour, r, g, b, a) then
    Result := (0.299 * r + 0.587 * g + 0.114 * b) * a / 255 + (1 - a) * 0
  else
    Result := 0;
end;

function OutsideStroke(const AGround: TTyGfxGround): string;
var
  c: array[0..3] of Double;
  a, under: Double;
  i: Integer;
begin
  if not TyTryParseCssRgba(AGround.Background, c[0], c[1], c[2], c[3]) then
  begin
    c[0] := 255; c[1] := 255; c[2] := 255; c[3] := 1;
  end;
  a := c[3];
  if AGround.IsDark then under := 0 else under := 255;
  for i := 0 to 2 do c[i] := c[i] * a + under * (1 - a);
  Result := 'rgba(' + TyJsNumberToString(c[0]) + ',' + TyJsNumberToString(c[1])
    + ',' + TyJsNumberToString(c[2]) + ',1)';
end;

procedure TyGfxInnerText(AHost: TTyGfxEl; const AMeasurer: ITyTextMeasurer;
  const AGround: TTyGfxGround);
const
  cDark = '#333';
  cLight = '#ccc';
  cLighter = '#eee';
var
  tc: TTyGfxEl;
  cfg: TJSONObject;
  local, hasPos, isInside, innerOrigin: Boolean;
  rect: TTyXYWH;
  d, posD: TJSONData;
  dist, px, py, rox, roy: Double;
  al, va, fill, stroke, pfStr: string;
  auto, isPath: Boolean;
  fillD: TJSONData;
  pfKind: Integer;
begin
  tc := AHost.TextContent;
  if tc = nil then Exit;
  if tc.Ignore then Exit;
  if AHost.TextConfig = nil then AHost.TextConfig := TJSONObject.Create;
  cfg := AHost.TextConfig;
  d := cfg.Find('local');
  local := (d <> nil) and (d.JSONType = jtBoolean) and d.AsBoolean;
  { copyTransform(textEl) }
  tc.InX := tc.X;
  tc.InY := tc.Y;
  tc.InRot := tc.Rotation;
  tc.InOX := tc.OriginX;
  tc.InOY := tc.OriginY;
  innerOrigin := False;
  al := '';
  va := '';
  posD := cfg.Find('position');
  hasPos := not JNull(posD);
  if hasPos then
  begin
    rect := TyGfxRect(AHost, AMeasurer);
    if not local and AHost.HasTransform then rect := TyRectApplyMat(rect, AHost.Transform);
    d := cfg.Find('distance');
    if JNull(d) then dist := 5 else dist := JsNum(d);
    TyGfxTextPosition(posD, dist, rect, px, py, al, va);
    tc.InX := px;
    tc.InY := py;
    d := cfg.Find('origin');
    if not JNull(d) and not JNull(cfg.Find('rotation'))
      and not ((d.JSONType = jtString) and (d.AsString = '')) then
    begin
      if (d.JSONType = jtString) and (d.AsString = 'center') then
      begin
        rox := rect.W * 0.5;
        roy := rect.H * 0.5;
      end
      else if d is TJSONArray then
      begin
        if d.Count > 0 then rox := JsParsePercent(d.Items[0], rect.W) else rox := NaN;
        if d.Count > 1 then roy := JsParsePercent(d.Items[1], rect.H) else roy := NaN;
      end
      else
      begin
        rox := NaN;
        roy := NaN;
      end;
      innerOrigin := True;
      if local then
      begin
        tc.InOX := -tc.InX + rox + 0;
        tc.InOY := -tc.InY + roy + 0;
      end
      else
      begin
        tc.InOX := -tc.InX + rox + rect.X;
        tc.InOY := -tc.InY + roy + rect.Y;
      end;
    end;
  end;
  d := cfg.Find('rotation');
  if not JNull(d) then tc.InRot := JsNum(d);
  d := cfg.Find('offset');
  if d is TJSONArray then
  begin
    if d.Count > 0 then tc.InX := tc.InX + JsNum(d.Items[0]) else tc.InX := NaN;
    if d.Count > 1 then tc.InY := tc.InY + JsNum(d.Items[1]) else tc.InY := NaN;
    if not innerOrigin then
    begin
      if d.Count > 0 then tc.InOX := -JsNum(d.Items[0]) else tc.InOX := NaN;
      if d.Count > 1 then tc.InOY := -JsNum(d.Items[1]) else tc.InOY := NaN;
    end;
  end;
  { the colours }
  d := cfg.Find('inside');
  if JNull(d) then
    isInside := (posD <> nil) and (posD.JSONType = jtString) and (Pos('inside', posD.AsString) > 0)
  else
    isInside := (d.JSONType = jtBoolean) and d.AsBoolean;
  auto := False;
  { the host's fill as Path reads it: own, else the prototype's '#000' }
  isPath := not (AHost.Kind in [gkImage, gkText, gkGroup, gkUnknown]);
  fillD := AHost.Style.Find('fill');
  pfKind := 0;
  pfStr := '';
  if fillD = nil then
  begin
    if isPath then
    begin
      pfKind := 1;
      pfStr := '#000';
    end;
  end
  else if JNull(fillD) then pfKind := 0
  else if fillD.JSONType = jtString then
  begin
    pfKind := 1;
    pfStr := fillD.AsString;
  end
  else pfKind := 2;
  { canBeInsideText: a Path with a fill; anything else }
  if isInside and (not isPath or TyGfxHasFill(AHost)) then
  begin
    fill := StrOf(cfg.Find('insideFill'));
    stroke := StrOf(cfg.Find('insideStroke'));
    if JNull(cfg.Find('insideFill')) or (fill = 'auto') then
    begin
      if not isPath then fill := '#fff'
      else if (pfKind = 1) and (pfStr <> 'none') then
      begin
        if LumOf(pfStr) > 0.5 then fill := cDark
        else if LumOf(pfStr) > 0.2 then fill := cLighter
        else fill := cLight;
      end
      else if pfKind = 2 then fill := cLight
      else fill := cDark;
    end;
    if JNull(cfg.Find('insideStroke')) or (stroke = 'auto') then
    begin
      if not isPath then stroke := '#000'
      else
      begin
        { getInsideTextStroke: the fill, when the label and the mode agree }
        stroke := '';
        if (pfKind = 1) and (AGround.IsDark = (LumOf(fill) < 0.4)) then stroke := pfStr;
      end;
      auto := True;
    end;
  end
  else
  begin
    fill := StrOf(cfg.Find('outsideFill'));
    stroke := StrOf(cfg.Find('outsideStroke'));
    if JNull(cfg.Find('outsideFill')) or (fill = 'auto') then
    begin
      if AGround.IsDark then fill := cLight else fill := cDark;
    end;
    if JNull(cfg.Find('outsideStroke')) or (stroke = 'auto') then
    begin
      stroke := OutsideStroke(AGround);
      auto := True;
    end;
  end;
  if fill = '' then fill := '#000';
  tc.HasDefault := True;
  tc.DefFill := fill;
  tc.DefStroke := stroke;
  tc.DefAutoStroke := auto;
  tc.DefAlign := al;
  tc.DefVAlign := va;
end;

{ ==================== painting ==================== }

procedure TyGfxPathCmds(const APath: TTyZrPath; const AM: TTyMat2D;
  out ACmds: TTyPathCmdArray; out APoints: TTyPointFArray);
var
  i, k, n, steps: Integer;
  cx, cy, r, a0, sweep, th, kk, p0, p1, c0, s0, c1, s1, t, u, px, py,
    lastX, lastY, sx, sy, qx, qy: Double;

  procedure Ap(AX, AY: Double; out OX, OY: Double);
  begin
    OX := AM[0] * AX + AM[2] * AY + AM[4];
    OY := AM[1] * AX + AM[3] * AY + AM[5];
  end;

  procedure Cmd(AKind: TTyPathCmdKind; AX1, AY1, AX2, AY2, AX, AY: Double);
  var q: Integer;
  begin
    q := Length(ACmds);
    SetLength(ACmds, q + 1);
    ACmds[q] := Default(TTyPathCmd);
    ACmds[q].Kind := AKind;
    Ap(AX1, AY1, ACmds[q].X1, ACmds[q].Y1);
    Ap(AX2, AY2, ACmds[q].X2, ACmds[q].Y2);
    Ap(AX, AY, ACmds[q].X, ACmds[q].Y);
  end;

  procedure Pt(AX, AY: Double);
  var q: Integer; ox, oy: Double;
  begin
    q := Length(APoints);
    SetLength(APoints, q + 1);
    Ap(AX, AY, ox, oy);
    APoints[q] := TyPointF(ox, oy);
  end;

  procedure Curve(AX1, AY1, AX2, AY2, AX, AY: Double);
  var j: Integer;
  begin
    Cmd(pckCurve, AX1, AY1, AX2, AY2, AX, AY);
    for j := 1 to 24 do
    begin
      t := j / 24;
      u := 1 - t;
      px := u * u * u * lastX + 3 * u * u * t * AX1 + 3 * u * t * t * AX2 + t * t * t * AX;
      py := u * u * u * lastY + 3 * u * u * t * AY1 + 3 * u * t * t * AY2 + t * t * t * AY;
      Pt(px, py);
    end;
    lastX := AX;
    lastY := AY;
  end;

begin
  ACmds := nil;
  APoints := nil;
  lastX := 0;
  lastY := 0;
  sx := 0;
  sy := 0;
  for i := 0 to High(APath) do
    case APath[i].Cmd of
      zrM:
        begin
          Cmd(pckMove, 0, 0, 0, 0, APath[i].V[0], APath[i].V[1]);
          lastX := APath[i].V[0];
          lastY := APath[i].V[1];
          sx := lastX;
          sy := lastY;
          Pt(lastX, lastY);
        end;
      zrL:
        begin
          Cmd(pckLine, 0, 0, 0, 0, APath[i].V[0], APath[i].V[1]);
          lastX := APath[i].V[0];
          lastY := APath[i].V[1];
          Pt(lastX, lastY);
        end;
      zrC:
        Curve(APath[i].V[0], APath[i].V[1], APath[i].V[2], APath[i].V[3],
          APath[i].V[4], APath[i].V[5]);
      zrQ:
        begin
          { a quadratic raised to a cubic }
          qx := APath[i].V[0];
          qy := APath[i].V[1];
          Curve(lastX + 2 / 3 * (qx - lastX), lastY + 2 / 3 * (qy - lastY),
            APath[i].V[2] + 2 / 3 * (qx - APath[i].V[2]),
            APath[i].V[3] + 2 / 3 * (qy - APath[i].V[3]),
            APath[i].V[2], APath[i].V[3]);
        end;
      zrA:
        begin
          cx := APath[i].V[0];
          cy := APath[i].V[1];
          r := APath[i].V[2];
          a0 := APath[i].V[4];
          sweep := APath[i].V[5];
          { canvas' arc: a line to its start, then the sweep }
          Cmd(pckLine, 0, 0, 0, 0, cx + r * Cos(a0), cy + r * Sin(a0));
          Pt(cx + r * Cos(a0), cy + r * Sin(a0));
          lastX := cx + r * Cos(a0);
          lastY := cy + r * Sin(a0);
          if IsNan(sweep) or IsInfinite(sweep) then Continue;
          n := Ceil(Abs(sweep) / (Pi / 2) - 1e-9);
          if n < 1 then n := 1;
          th := sweep / n;
          kk := 4 / 3 * Tan(th / 4);
          for k := 0 to n - 1 do
          begin
            p0 := a0 + th * k;
            p1 := a0 + th * (k + 1);
            c0 := Cos(p0);
            s0 := Sin(p0);
            c1 := Cos(p1);
            s1 := Sin(p1);
            Cmd(pckCurve, cx + r * (c0 - kk * s0), cy + r * (s0 + kk * c0),
              cx + r * (c1 + kk * s1), cy + r * (s1 - kk * c1),
              cx + r * c1, cy + r * s1);
          end;
          steps := Ceil(Abs(sweep) * 24);
          if steps < 4 then steps := 4;
          for k := 1 to steps do
            Pt(cx + r * Cos(a0 + sweep * k / steps), cy + r * Sin(a0 + sweep * k / steps));
          lastX := cx + r * Cos(a0 + sweep);
          lastY := cy + r * Sin(a0 + sweep);
        end;
      zrR:
        begin
          px := APath[i].V[0];
          py := APath[i].V[1];
          Cmd(pckMove, 0, 0, 0, 0, px, py);
          Cmd(pckLine, 0, 0, 0, 0, px + APath[i].V[2], py);
          Cmd(pckLine, 0, 0, 0, 0, px + APath[i].V[2], py + APath[i].V[3]);
          Cmd(pckLine, 0, 0, 0, 0, px, py + APath[i].V[3]);
          Cmd(pckClose, 0, 0, 0, 0, 0, 0);
          Pt(px, py);
          Pt(px + APath[i].V[2], py);
          Pt(px + APath[i].V[2], py + APath[i].V[3]);
          Pt(px, py + APath[i].V[3]);
          lastX := px;
          lastY := py;
          sx := px;
          sy := py;
        end;
      zrZ:
        begin
          Cmd(pckClose, 0, 0, 0, 0, 0, 0);
          lastX := sx;
          lastY := sy;
        end;
    end;
end;

function DeviceOf(AEl: TTyGfxEl; AHas: Boolean; const AM: TTyMat2D;
  AScale: Double): TTyMat2D;
var s: TTyMat2D;
begin
  s := TyMatIdentity;
  s[0] := AScale;
  s[3] := AScale;
  if AHas then Result := TyMatMul(s, AM) else Result := s;
end;

function GradOf(AEl: TTyGfxEl; AData: TJSONData; const ABox: TTyXYWH;
  const AM: TTyMat2D; out AGrad: TTyChartGradient): Boolean;
var
  x1, y1, x2, y2, r, det: Double;
begin
  Result := TyTryReadGradient(AData, AGrad);
  if not Result then Exit;
  { resolved in the element's frame, then carried by its transform: the
    painter takes coordinates already placed }
  TyResolveGradientXYWH(AGrad, ABox, x1, y1, x2, y2, r);
  AGrad.Global := True;
  AGrad.X := AM[0] * x1 + AM[2] * y1 + AM[4];
  AGrad.Y := AM[1] * x1 + AM[3] * y1 + AM[5];
  AGrad.X2 := AM[0] * x2 + AM[2] * y2 + AM[4];
  AGrad.Y2 := AM[1] * x2 + AM[3] * y2 + AM[5];
  det := Abs(AM[0] * AM[3] - AM[1] * AM[2]);
  AGrad.R := r * Sqrt(det);
end;

function UniformScale(const AM: TTyMat2D): Double;
begin
  Result := Sqrt(Abs(AM[0] * AM[3] - AM[1] * AM[2]));
end;

function TyGfxPaintElement(AEl: TTyGfxEl; const AMeasurer: ITyTextMeasurer;
  const ACtx: TTyGfxPaintCtx; out AOut: TTyChartElement): Boolean;
var
  m: TTyMat2D;
  path: TTyZrPath;
  cmds: TTyPathCmdArray;
  pts: TTyPointFArray;
  box: TTyXYWH;
  d: TJSONData;
  c: TTyChartColor;
  hasFill, hasStroke: Boolean;
  lw, us, x, y, w, h, op: Double;
  rt: TTyRtResult;
  i: Integer;
  dash: TTyDoubleArray;
  q: array[0..3] of TTyPointF;
  ox, oy: Double;

  procedure Corner(AI: Integer; AX, AY: Double);
  begin
    q[AI].X := m[0] * AX + m[2] * AY + m[4];
    q[AI].Y := m[1] * AX + m[3] * AY + m[5];
  end;

begin
  Result := False;
  AOut := Default(TTyChartElement);
  if (AEl = nil) or (AEl.Kind in [gkGroup, gkUnknown]) then Exit;
  m := DeviceOf(AEl, AEl.HasTransform, AEl.Transform, ACtx.Scale);
  us := UniformScale(m);
  AOut := TyChartElement(TyShapeRect(TyRectF(0, 0, 0, 0)));
  AOut.Silent := False;
  AOut.Style := TyChartStyle;
  op := 1;
  d := AEl.Style.Find('opacity');
  if (d <> nil) and (d.JSONType = jtNumber) then op := d.AsFloat;
  AOut.Style.Alpha := Max(Double(0), Min(Double(1), op));
  case AEl.Kind of
    gkImage:
      begin
        box := TyGfxRect(AEl, AMeasurer);
        w := box.W;
        h := box.H;
        d := AEl.Style.Find('image');
        if ((w <= 0) or (h <= 0)) and Assigned(ACtx.ImageSize)
          and (d <> nil) and (d.JSONType = jtString)
          and ACtx.ImageSize(d.AsString, x, y) then
        begin
          { NOT WRITTEN: the natural size the image is drawn at once it has
            loaded -- the layout above took upstream's first frame, 0 }
          if JNull(AEl.Style.Find('width')) and JNull(AEl.Style.Find('height')) then
          begin
            w := x;
            h := y;
          end
          else if JNull(AEl.Style.Find('width')) and (y > 0) then w := x / y * h
          else if JNull(AEl.Style.Find('height')) and (x > 0) then h := y / x * w;
        end;
        Corner(0, box.X, box.Y);
        Corner(1, box.X + w, box.Y);
        Corner(2, box.X + w, box.Y + h);
        Corner(3, box.X, box.Y + h);
        AOut.Shape := TyShapePolygon(q);
        AOut.Shape.HitNonZero := True;
        { [F6a] any string: the renderer draws what AdvChart.Images resolves
          -- a data URL, an image list's `name/index` -- and nothing for the
          rest (upstream's image not loaded) }
        if (d <> nil) and (d.JSONType = jtString) and (d.AsString <> '')
          and not AEl.Invisible and (w > 0) and (h > 0) then
        begin
          AOut.Style.HasFill := True;
          AOut.Style.FillColor := 0;
          AOut.Style.FillPattern.Present := True;
          AOut.Style.FillPattern.Image := d.AsString;
          AOut.Style.FillPattern.Repetition := 'no-repeat';
          AOut.Style.FillPattern.HasMatrix := True;
          AOut.Style.FillPattern.UnitImage := True;
          { the unit square onto the box, through the transform, in css px }
          AOut.Style.FillPattern.Matrix[0] := m[0] * w / ACtx.Scale;
          AOut.Style.FillPattern.Matrix[1] := m[1] * w / ACtx.Scale;
          AOut.Style.FillPattern.Matrix[2] := m[2] * h / ACtx.Scale;
          AOut.Style.FillPattern.Matrix[3] := m[3] * h / ACtx.Scale;
          AOut.Style.FillPattern.Matrix[4] := (m[0] * box.X + m[2] * box.Y + m[4]) / ACtx.Scale;
          AOut.Style.FillPattern.Matrix[5] := (m[1] * box.X + m[3] * box.Y + m[5]) / ACtx.Scale;
        end;
      end;
    gkText:
      begin
        rt := TyGfxTextLayout(AEl, AMeasurer);
        box := TyRtBounds(rt.Pieces);
        if box.W < 0 then box := TyXYWH(0, 0, 0, 0);
        Corner(0, box.X, box.Y);
        Corner(1, box.X + box.W, box.Y);
        Corner(2, box.X + box.W, box.Y + box.H);
        Corner(3, box.X, box.Y + box.H);
        AOut.Shape := TyShapePolygon(q);
        AOut.Shape.HitNonZero := True;
        if not AEl.Invisible and (Length(rt.Pieces) > 0) then
        begin
          AOut.Caption.Text := TextOf(AEl.Style);
          if AOut.Caption.Text = '' then AOut.Caption.Text := ' ';
          AOut.Caption.RtPieces := rt.Pieces;
          { a free text's default ink is the skin's text colour }
          if (AEl.Host = nil) and ACtx.HasInk then
            for i := 0 to High(AOut.Caption.RtPieces) do
              if AOut.Caption.RtPieces[i].DefaultFill then
                AOut.Caption.RtPieces[i].Fill := ACtx.Ink;
          AOut.Caption.FontName := rt.Pieces[0].FontFamily;
          AOut.Caption.Colour := ACtx.Ink;
          ox := m[4];
          oy := m[5];
          AOut.Caption.X := ox;
          AOut.Caption.Y := oy;
          AOut.Caption.RotationRad := TyJsAtan2(-m[1], m[0]);
          AOut.Caption.RtScale := us;
        end;
      end;
  else
    path := TyGfxPath(AEl);
    TyGfxPathCmds(path, m, cmds, pts);
    hasFill := TyGfxHasFill(AEl);
    hasStroke := TyGfxHasStroke(AEl);
    lw := TyGfxLineWidth(AEl);
    if hasFill then AOut.Shape := TyShapePolygon(pts)
    else AOut.Shape := TyShapePolyline(pts);
    AOut.Shape.Cmds := cmds;
    AOut.Shape.HitNonZero := True;
    if hasStroke then AOut.HitSlopLogical := Max(lw, 0) * us / ACtx.Scale / 2
    else if not hasFill then AOut.HitSlopLogical := 5 * us / ACtx.Scale / 2;
    if hasFill and not hasStroke then AOut.HitSlopLogical := 0;
    if not AEl.Invisible then
    begin
      box := TyGfxRect(AEl, AMeasurer);
      d := AEl.Style.Find('fill');
      if d = nil then
      begin
        if hasFill then
        begin
          AOut.Style.HasFill := True;
          AOut.Style.FillColor := $FF000000;
        end;
      end
      else if hasFill then
      begin
        if (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, c) then
        begin
          AOut.Style.HasFill := True;
          AOut.Style.FillColor := c;
        end
        else if GradOf(AEl, d, box, m, AOut.Style.FillGradient) then
        begin
          AOut.Style.HasFill := True;
          AOut.Style.FillColor := TyGradientSolid(AOut.Style.FillGradient);
        end;
      end;
      { strokeNoScale: the canvas divides the width by the line scale, so
        it is drawn at its own width whatever the element's scale
        [Batch 129] }
      if TyGfxStrokeNoScale(AEl) then us := ACtx.Scale;
      if hasStroke then
      begin
        d := AEl.Style.Find('stroke');
        if (d <> nil) and (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, c) then
        begin
          AOut.Style.StrokeColor := c;
          AOut.Style.StrokeWidthLogical := lw * us / ACtx.Scale;
        end
        else if GradOf(AEl, d, box, m, AOut.Style.StrokeGradient) then
        begin
          AOut.Style.StrokeColor := TyGradientSolid(AOut.Style.StrokeGradient);
          AOut.Style.StrokeWidthLogical := lw * us / ACtx.Scale;
        end;
      end;
      d := AEl.Style.Find('lineDash');
      if (d is TJSONArray) and (AOut.Style.StrokeWidthLogical > 0) then
      begin
        dash := nil;
        SetLength(dash, d.Count);
        for i := 0 to d.Count - 1 do dash[i] := JsNum(d.Items[i]) * us / ACtx.Scale;
        AOut.Style.DashLogical := dash;
        { [R2-F] lineDashOffset, scaled as the pattern is }
        d := AEl.Style.Find('lineDashOffset');
        if (d <> nil) and (d.JSONType = jtNumber) then
          AOut.Style.DashOffsetLogical := d.AsFloat * us / ACtx.Scale;
      end;
    end;
  end;
  AOut.Silent := False;
  { [F6a] the element's own cursor, 'pointer' by the prototype }
  if AEl.Cursor <> 'pointer' then AOut.Cursor := AEl.Cursor;
  Result := True;
end;

end.
