unit tyControls.AdvChart.Geo;
{$mode objfpc}{$H+}
{ THE GEO FOUNDATION [Batch 146, D14 GE1]: registerMap and the GeoJSON parse,
  the geo coordinate system and the geo component's picture -- ECharts 6.1's
  coord/geo (geoSourceManager.ts, GeoJSONResource.ts, parseGeoJson.ts,
  Region.ts, Geo.ts, geoCreator.ts, GeoModel.ts), coord/View.ts and
  component/helper/MapDraw.ts, line for line where the bits depend on it.

  THE REGISTRY is global, as upstream's is: TyChartRegisterMap stores a map
  under a name for every chart in the process. The text is read once, through
  the option reader's own nesting guard and escape pre-decode, and parsed into
  regions on the first chart that asks for it -- per nameProperty, cached,
  exactly when upstream parses. The compressed format (UTF8Encoding) decodes
  per UTF-16 unit with the zigzag and the delta upstream uses; a map
  registered as 'china' gets the three fixes (GeoFix).

  THE VIEW. A GeoJSON map is drawn with its latitude upwards: the view
  inverts y (View's invertY). Upstream keeps its transforms as zrender
  Transformables and turns them into matrices through decomposeTransform and
  getLocalTransform, and a flipped matrix decomposes into a skew of PI --
  whose tangent is not zero. So the overall matrix carries
  tan(PI) * scaleY (about 4e-15) in m[2], and every dataToPoint adds that
  times the latitude: it moves the last bit of a third of all points. The
  matrices here are full 2 x 3 ones, built through the same decompose and
  compose, never simplified.

  THE PICTURE is MapDraw's: one group per region name, a compound path of the
  region's polygons (exterior then interiors, nonzero fill) and one of its
  lines, the points through the RAW matrix, the group under the ROAM
  transform; the path a first canvas brush hands the context folds segments
  under a pixel (segmentIgnoreThreshold 1) into their farthest point. The
  label sits at the region's centre, placed as percentages of the path's
  stroked box the way resetLabelForRegion places it.

  THE REGIONS AS THINGS A POINTER REACHES [Batch 148, D14 GE2]. Every
  value a region's style or label reads goes up GeoModel.getRegionModel's
  chain -- the region option (its regions entry with the feature's
  echartsStyle merged in where the entry is silent), the geo's option over
  GeoModel's defaults, the root option -- a null or an undefined climbing,
  as Model.getShallow climbs. The emphasis, select and blur styles and
  labels are read that way into each compound path's state objects, and
  the flags util/states.ts keeps on a region group (hoverState,
  __highByOuter, selected) are kept here per group and turned into state
  lists by States.pas, the series' own machine: the default proxy's colour
  lift, the z2 lifts and their creep, the blur's tenth. The picture is
  worked out once per geo and kept (the paths, the state objects); a list
  build only reads the current values.

  THE ROAM [Batch 150, D14 GE3]: the geoRoam action's arithmetic is
  View.ts' ownRoamModelCoordSysUpdateInAction -- the overall transform from
  the transform group's (the roam) times the raw, the payload's pan and zoom
  applied to it, the roam taken back out through the raw inverse and the
  centre and zoom written back into the option (a half last written as a
  percentage stays one), then the view worked out again from them. Every
  step goes through the same decompose and compose as the view itself. The
  picture is not rebuilt: what hangs on the roam -- the group's matrix, the
  unit small segments fold under, the drawn paths, the labels' anchors, the
  drawn boxes -- is worked out again on the kept picture, the state records
  untouched.

  THE MAP SERIES [Batch 152, D14 GE4]. MapDraw draws a map series' regions
  too -- the series' own geo (one per `map` of a group of map series, laid
  out from the first declared one) or a geo component the series names --
  and then the data rides along: the region option is the data item (with
  the feature's echartsStyle merged in where it is silent) over the
  series' option and MapSeries' defaults, the normal fill the visualMap's
  colour where a visualMap encodes the series, the label there only where
  the value is not a number or no legend symbol stands on the region
  (resetLabelForRegion), its text the series' getFormattedLabel; a region
  group is the item's graphic element (its events, tooltip and states the
  series'). A TTyGeo carries that as a TTyGeoData the control sets.

  SVG MAPS [F6b]: a map registered as SVG markup (or the wrapper form with
  an `svg` string) is GeoSVGResource's -- the document parsed once, a graphic
  built per geo through GeoSvg (zrender's parseSVG), its regions the
  self-named items of the region-available tags with GeoSVGRegion's centre,
  the view not flipped and aspectScale 1 by default. MapDraw._buildSVG's
  picture is kept per node: the option's itemStyle over the SVG's own style
  on every named shape, the three states with the default proxy and no z2
  lift on emphasis, a label 'inside' each self-named shape or group, and
  every node's hover and select flags moved the way traverseUpdateState
  moves them -- a component's highlight by name reaches every dispatcher of
  the name, a hover the outermost dispatcher over the element, the event
  the innermost named item. updateSelectStatus marks a self-named item and
  everything under it, so a named item inside a named group follows the
  group's selection.

  NOT HERE (spec sections 185, 187, 189, 191 and 204): projection streams.

  PURE but for fpjson: no painter, no LCL. }
interface

uses
  SysUtils, Classes, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Option,
  tyControls.AdvChart.Layout, tyControls.AdvChart.Coord,
  tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
  tyControls.AdvChart.Color, tyControls.AdvChart.Graph,
  tyControls.AdvChart.States, tyControls.AdvChart.GeoFix,
  tyControls.AdvChart.Handlers, tyControls.AdvChart.GeoSvg;

const
  TyGeoCoordSysName = 'geo';
  { GEO_DEFAULT_PARAMS.geoJSON.aspectScale }
  TyGeoDefaultAspectScale = 0.75;
  { MapDraw's CompoundPath segmentIgnoreThreshold, in device pixels }
  TyGeoSegmentIgnore = 1;
  { Path.prototype.strokeContainThreshold }
  TyGeoStrokeContain = 5;

type
  TTyGeoPt = tyControls.AdvChart.GeoFix.TTyGeoPt;
  TTyGeoRing = tyControls.AdvChart.GeoFix.TTyGeoRing;
  TTyGeoRingArray = tyControls.AdvChart.GeoFix.TTyGeoRingArray;

  { ==== projections [Batch 146] ====
    `projection` with `project: '@Name'` and `unproject: '@Name'` -- upstream's two
    functions of a point, here two handlers registered by name. False is
    upstream's null point (a projection may answer none). }
  TTyGeoProjectHandler = function(AX, AY: Double; out ARX, ARY: Double): Boolean of object;

  TTyGeoProjection = record
    Active: Boolean;
    Project, Unproject: TTyGeoProjectHandler;
  end;

  TTyGeoGeomKind = (ggkPolygon, ggkLineString);
  { One geometry of a region: a polygon (an exterior ring and its holes) or a
    set of lines. The rings are SHARED with the resource's decoded features,
    as upstream's arrays are shared with the parsed JSON. }
  TTyGeoGeometry = record
    Kind: TTyGeoGeomKind;
    Exterior: TTyGeoRing;
    Interiors: TTyGeoRingArray;
    Lines: TTyGeoRingArray;
  end;
  TTyGeoGeometryArray = array of TTyGeoGeometry;

  { GeoJSONRegion }
  TTyGeoRegion = class
  private
    FName: string;
    FGeometries: TTyGeoGeometryArray;
    FProperties: TJSONData;
    FHasCenter: Boolean;
    FCenter: TTyGeoPt;
    FHasRect: Boolean;
    FRect: TTyXYWH;
  public
    constructor Create(const AName: string; const AGeoms: TTyGeoGeometryArray;
      AHasCp: Boolean; const ACp: TTyGeoPt);
    { getCenter: properties.cp, a fix's, a special area's, or calcCenter --
      computed on the first ask and kept }
    function GetCenter: TTyGeoPt;
    procedure SetCenter(const APt: TTyGeoPt);
    function CalcCenter: TTyGeoPt;
    { getBoundingRect(): the exteriors and lines, unprojected, kept }
    function BoundingRect: TTyXYWH;
    { getBoundingRect(projection): always worked out again }
    function ProjectedRect(const AProj: TTyGeoProjection): TTyXYWH;
    { transformTo: the region moved into a box (a special area) }
    procedure TransformTo(AX, AY, AW, AH: Double);
    { cloneShallow: the same geometries, centre and rect under a name }
    function CloneShallow(const AName: string): TTyGeoRegion;
    procedure AddGeometry(const AGeom: TTyGeoGeometry);
    property Name: string read FName;
    property Geometries: TTyGeoGeometryArray read FGeometries;
    { the feature's properties, in the registered map's tree (or nil) }
    property Properties: TJSONData read FProperties write FProperties;
  end;
  TTyGeoRegionArray = array of TTyGeoRegion;

  { What GeoJSONResource.load answers: the regions (owned copies, so a
    re-registered map frees nothing a chart still holds), the region of each
    name (the last one wins, as regionsMap.set does) and the union rect. }
  TTyGeoSource = class
  private
    FRegions: TTyGeoRegionArray;
    FRect: TTyXYWH;
  public
    destructor Destroy; override;
    function RegionByName(const AName: string): TTyGeoRegion;
    property Regions: TTyGeoRegionArray read FRegions;
    property Rect: TTyXYWH read FRect;
  end;

  { The geo component's options this batch reads (GeoModel + its defaults). }
  TTyGeoSpec = record
    Show: Boolean;
    MapName: string;
    Silent: Boolean;
    Clip: Boolean;
    Z, ZLevel: Integer;
    { the box after mergeLayoutParam, a null or absent key climbing to the
      option root as getShallow does }
    Box: TTyRawBox;
    PreserveAspect: TTyGraphPreserve;
    PreserveAlign, PreserveVAlign: string;
    { `aspectScale`: Has is False when null or absent (retrieve2) }
    HasAspectScale: Boolean;
    AspectScale: Double;
    HasLayoutCenter: Boolean;
    LayoutCenter: array[0..1] of TTyBoxRaw;
    HasLayoutSize: Boolean;
    LayoutSize: TTyBoxRaw;
    { `boundingCoords`: Has when not null; Ok when all four are finite }
    HasBoundingCoords: Boolean;
    BoundingCoordsOk: Boolean;
    BCX0, BCY0, BCX1, BCY1: Double;
    NameProperty: string;
    { `projection`: Has when written truthy; the two handler names }
    HasProjection: Boolean;
    ProjectName, UnprojectName: string;
    { center / zoom / scaleLimit, as the graph's view reads them }
    Centre: TTyGraphCentre;
    Zoom: Double;
    HasLimit: Boolean;
    LimitMin, LimitMax: Double;
    { [Batch 150] `roam`: `retrieve2(get('roam'), false)` -- GeoModel has
      no default, so an absent or null one climbs to the root, and nothing
      there is off; `roamTrigger` 'global' (climbing too) }
    Roam: TTyGraphRoamMode;
    RoamGlobal: Boolean;
  end;

  { ==== the picture ==== }

  { The theme's ink for what the option leaves out. [Batch 148] The
    emphasis and select tokens too: upstream's highlight fill and primary
    label colour. }
  TTyGeoInk = record
    AreaFill: TTyChartColor;
    Border: TTyChartColor;
    LabelColour: TTyChartColor;
    LabelFontName: string;
    LabelFontSizeLogical: Integer;
    LabelFontWeight: Integer;
    HighlightFill: TTyChartColor;
    LabelHighlight: TTyChartColor;
    { [Batch 152] a map series' area: MapSeries' areaColor default (the
      background token, not the geo's tint) }
    MapAreaFill: TTyChartColor;
  end;

  { [Batch 148] which of GeoModel's token defaults a colour is: the skin's
    ink here. [Batch 152] gtkMapArea is MapSeries' area. }
  TTyGeoToken = (gtkNone, gtkArea, gtkBorder, gtkLabel, gtkHighlight,
    gtkLabelHighlight, gtkMapArea);

  { Where a style value came from: nowhere (not painted), the theme, the
    option (Raw holds what was written). }
  TTyGeoInkSource = (gisNone, gisTheme, gisOption);

  TTyGeoPaint = record
    FillSrc: TTyGeoInkSource;
    FillRaw: string;
    Fill: TTyChartColor;
    FillGradient: TTyChartGradient;
    StrokeSrc: TTyGeoInkSource;
    StrokeRaw: string;
    Stroke: TTyChartColor;
    { the stroke as JavaScript's `||` sees it: 'none' and an unreadable
      colour are truthy, so a line keeps them }
    StrokeTruthy: Boolean;
    LineWidthLogical: Double;
    HasOpacity: Boolean;
    Opacity: Double;
    Dash: TTyOptDash;
    DashLogical: TTyDoubleArray;
    DashRaw: string;
    { [Batch 148] A STATE'S STYLE IS SPARSE: which keys it sets (the
      opacity's is HasOpacity), the token a default colour is, and an
      emphasis fill written 'inherit' (the proxy's own word). The normal
      style sets the keys it has too. }
    FillHas, StrokeHas, WidthHas, DashHas: Boolean;
    FillToken, StrokeToken: TTyGeoToken;
    FillInherit: Boolean;
  end;

  { [Batch 148] one state's label (setLabelStyle's state object and
    createTextConfig's state textConfig): what it sets }
  TTyGeoLabelState = record
    { the state's show, where it differs from the normal one: its ignore }
    HasIgnore, Ignore: Boolean;
    { the state's text: getFormattedLabel(name, state), else the normal }
    Text: string;
    HasColour, ColourNone: Boolean;
    Colour: TTyChartColor;
    ColourToken: TTyGeoToken;
    ColourRaw: string;
    HasFontSize: Boolean;
    FontSizeLogical: Integer;
    HasFontWeight: Boolean;
    FontWeight: Integer;
    HasFontFamily: Boolean;
    FontFamily: string;
    HasOpacity: Boolean;
    Opacity: Double;
    { textConfig.offset (logical px) and rotation (radians) }
    HasOffset: Boolean;
    OffX, OffY: Double;
    HasRotate: Boolean;
    RotationRad: Double;
  end;

  TTyGeoLabel = record
    Shown: Boolean;
    Text: string;
    HasColour: Boolean;
    Colour: TTyChartColor;
    ColourRaw: string;
    HasFontSize: Boolean;
    FontSizeLogical: Integer;
    HasFontWeight: Boolean;
    FontWeight: Integer;
    HasFontFamily: Boolean;
    FontFamily: string;
    { labelXY (the centre through the raw matrix), the two percentages of
      textConfig.position, the stored layoutRect, and where the text is
      anchored once the group's transform has moved the rect }
    HasPos: Boolean;
    XY: TTyGeoPt;
    PctX, PctY: Double;
    Layout: TTyXYWH;
    AnchorX, AnchorY: Double;
    { [Batch 148] the text exists (some state shows it: setLabelStyle's
      needsCreateText), the token the normal colour is, the normal style's
      opacity, textConfig's offset (logical px) and rotation, the text's own
      silent, and the three states }
    Exists: Boolean;
    ColourToken: TTyGeoToken;
    HasOpacity: Boolean;
    Opacity: Double;
    HasOffset: Boolean;
    OffX, OffY: Double;
    HasRotate: Boolean;
    RotationRad: Double;
    Silent: Boolean;
    States: array[TTyStName] of TTyGeoLabelState;
  end;

  { One compound path. Subs and Drawn are local -- before the roam -- in
    device px; Rect is the path box grown by the stroke as the label reads
    it (the polygon style, before a line's fix). }
  TTyGeoDrawPath = record
    IsLine: Boolean;
    Subs: TTyGeoRingArray;
    Drawn: TTyPathCmdArray;
    Paint: TTyGeoPaint;
    Rect: TTyXYWH;
    { getBoundingRect once drawn: the line's fixed style, the stroke over
      the transform's line scale (strokeNoScale) }
    BoxRect: TTyXYWH;
    Lbl: TTyGeoLabel;
    { [Batch 148] the emphasis, select and blur styles (a line's fixed as
      its normal one is) }
    StatePaint: array[TTyStName] of TTyGeoPaint;
  end;
  TTyGeoDrawPathArray = array of TTyGeoDrawPath;

  TTyGeoDrawGroup = record
    Name: string;
    HasSilent: Boolean;
    Silent: Boolean;
    Paths: TTyGeoDrawPathArray;
    { [Batch 148] the region model's option as an event's params.region
      (an empty object for a name the model map does not hold), its emphasis focus
      'self' and emphasis.disabled }
    RegionJson: string;
    FocusSelf: Boolean;
    EmphasisDisabled: Boolean;
  end;
  TTyGeoDrawGroupArray = array of TTyGeoDrawGroup;

  TTyGeoDraw = record
    Groups: TTyGeoDrawGroupArray;
    HasClip: Boolean;
    Clip: TTyXYWH;
    { the transform group's matrix and whether it has one }
    HasTrans: Boolean;
    Trans: TTyMat2D;
    { PathProxy's _ux / _uy }
    UX, UY: Double;
  end;

  { [Batch 148] ONE REGION GROUP'S FLAGS, as util/states.ts keeps them on
    the group and on every path under it -- traverseUpdateState moves them
    together, so one set says all: hoverState (0 normal, 1 blur, 2
    emphasis), __highByOuter (the group is the dispatcher an action holds)
    and selected; and per compound path its states record, the path the
    host and its text the label. }
  TTyGeoGroupSt = record
    Hover: Integer;
    Hbo: Cardinal;
    Selected: Boolean;
    Items: array of TTyStItem;
  end;
  TTyGeoGroupStArray = array of TTyGeoGroupSt;

  { [Batch 152, D14 GE4] WHOSE GEO: a geo component's, or a map series
    group's own (MapDraw's mapOrGeoModel is the series then) }
  TTyGeoKind = (gkComponent, gkMapSeries);

  { [Batch 152] ONE REGION GROUP'S DATA, MapDraw with a series' data: the
    data index of its name (-1: none), the region model's option (a map
    series' data item with the feature's echartsStyle merged in -- owned by
    the geo once set; nil: the series' own), the visualMap's colour for the
    normal fill (isVisualEncodedByVisualMap && style.fill), whether
    resetLabelForRegion gives it a text (a map series' rule: the value not
    a number, or no legend symbol on it), and getDataParams for the series'
    label formatter (ValueText as String() prints the value) }
  TTyGeoDataGroup = record
    Row: Integer;
    Opt: TJSONObject;
    HasFill: Boolean;
    Fill: TTyChartColor;
    LabelOn: Boolean;
    Params: TTyChartCallbackParams;
  end;
  TTyGeoData = record
    Active: Boolean;
    SeriesIndex: Integer;
    { per group, in the geo's group order }
    Groups: array of TTyGeoDataGroup;
  end;

  { [F6b] AN SVG NODE'S PICTURE beyond the values its states move (those
    are its TTyStElement's): its own paint servers (-1 none), the option's
    gradient fill, the fill and stroke opacities, strokeNoScale, the SVG's
    own dash (its own units), and for a named shape the option's normal and
    state paints (their dash and what they set) }
  TTyGeoSvgLook = record
    FillGrad, StrokeGrad: Integer;
    HasOptGrad: Boolean;
    OptGrad: TTyChartGradient;
    FillOpacity, StrokeOpacity: Double;
    NoScale: Boolean;
    HasDash: Boolean;
    Dash: TTyDoubleArray;
    Styled: Boolean;
    Opt: TTyGeoPaint;
    StateOpt: array[TTyStName] of TTyGeoPaint;
  end;

  { [F6b] an SVG map's node flags, kept over a render (MapDraw keeps its
    graphic while the map is the same: the elements keep their hover and
    action bits) }
  TTyGeoSvgFlags = record
    Valid: Boolean;
    MapName: string;
    Count: Integer;
    Hover: TTyIntegerArray;
    Hbo: array of Cardinal;
    Blured: Boolean;
    { the transforms the last frame drew with }
    Prev: array of TTyMat2D;
    PrevHas: array of Boolean;
  end;

  { [F6b] where a label host's text was last placed (updateInnerText runs
    only while the host is dirty) }
  TTyGeoSvgPlace = record
    Valid: Boolean;
    AX, AY, Rot, TX, TY: Double;
  end;

  { A Transformable's props, as View keeps its three: no origin, no anchor. }
  TTyGeoTrans = record
    X, Y, ScaleX, ScaleY, Rotation, SkewX, SkewY: Double;
  end;

  { ONE GEO COMPONENT: the coordinate system and what its view needs. }
  TTyGeo = class(TTyNonRefCountedObject, ITyCoordSys)
  private
    FIndex: Integer;
    FSpec: TTyGeoSpec;
    FNode: TJSONObject;
    { [Batch 152] whose geo, the option a region model's chain climbs to
      (a map series group's main series; the geo's own node otherwise), the
      data drawn with it }
    FKind: TTyGeoKind;
    FChainNode: TJSONObject;
    FSeriesData: TTyGeoData;
    FNameMap: TJSONObject;
    FSource: TTyGeoSource;
    FValid: Boolean;
    FProjection: TTyGeoProjection;
    FAspectScale: Double;
    FInvertY: Boolean;
    FScale: Double;
    { the View }
    FData, FView: TTyXYWH;
    FHasData, FHasView: Boolean;
    FRaw, FRoam, FOverall: TTyGeoTrans;
    FMtRaw, FMtRawInv, FMtOverall, FMtOverallInv: TTyMat2D;
    FZoom: Double;
    FCentre: TTyGraphCentre;
    FHasCentre: Boolean;
    FHasLimit: Boolean;
    FLimitMin, FLimitMax: Double;
    { [Batch 148] the root option's keys a region model's chain reaches
      (itemStyle, label, emphasis, select, blur), a copy }
    FRoot: TJSONObject;
    { the region options, merged with their echartsStyle, by name (owned) }
    FOptNames: TTyStringArray;
    FOpts: array of TJSONObject;
    { the groups: one per distinct region name, MapDraw's order }
    FGroupNames: TTyStringArray;
    FGroupsOk: Boolean;
    { the picture, worked out once for an ink and a PPI }
    FDraw: TTyGeoDraw;
    FDrawOk: Boolean;
    FDrawPPI: Integer;
    FDrawInk: TTyGeoInk;
    { the flags and the state records }
    FSt: TTyGeoGroupStArray;
    FItemsOk: Boolean;
    FIsBlured: Boolean;
    FGen: Integer;
    { [Batch 150] the roam steps taken, and the one the picture's roam
      parts were last worked out for }
    FRoamGen: Integer;
    FDrawRoamGen: Integer;
    { [F6b] AN SVG MAP: its graphic and the measurer of its text; per node
      the named item (self or from a group; -1 none), the self-named item,
      the event group (the innermost self-named item's), the hover group
      (the outermost dispatcher's), whether it is a dispatcher, the region
      option's silent (-1 none), __highByOuter, the state elements of the
      node and of its label, the look, the label; per group its
      dispatchers; per region its node; the global transforms }
    FIsSvg: Boolean;
    FSvgMeasure: TTyGsMeasure;
    FSvg: TTyGsGraphic;
    FSvgItem, FSvgSelf, FSvgEvent, FSvgHover: TTyIntegerArray;
    FSvgIsDisp: array of Boolean;
    FSvgSilentOpt: TTyIntegerArray;
    FSvgHbo: array of Cardinal;
    { [R2-B] a map series' element under the pointer (its dispatcher's
      node; -1 none) }
    FSvgPointer: Integer;
    FSvgEl, FSvgLbl: array of TTyStElement;
    FSvgLook: array of TTyGeoSvgLook;
    FSvgLabel: array of TTyGeoLabel;
    FSvgHasLabel: array of Boolean;
    FSvgDisp: array of TTyIntegerArray;
    FSvgFocusSelf: Boolean;
    FSvgRegionNode: TTyIntegerArray;
    FSvgGlobal: array of TTyMat2D;
    FSvgHasGlobal, FSvgReached: array of Boolean;
    FSvgGlobalGen: Integer;
    FSvgChanged: Boolean;
    { the global transforms the last build drew with (a group host's
      children are updated after it: its label reads theirs), and the
      labels' placements }
    FSvgPrevGlobal: array of TTyMat2D;
    FSvgPrevHas: array of Boolean;
    FSvgPlace: array of TTyGeoSvgPlace;
    FSvgPlaceGen: Integer;
    procedure SvgPlaceLabel(ANode, APPI: Integer);
    procedure SvgSetup;
    procedure SvgGlobals;
    procedure SvgPicture(const AInk: TTyGeoInk);
    procedure SvgSyncSelection;
    procedure SvgTraverse(ANode, AMode, AValue: Integer);
    function SvgGroupHead(AGroup: Integer): Integer;
    procedure EnsureGroups;
    procedure InitItems;
    procedure UpdateTransform;
    procedure SetBoundingRect(AX, AY, AW, AH: Double);
    procedure SetViewRect(AX, AY, AW, AH: Double);
    procedure ApplyRoamOptions;
    procedure LayoutView(const AContainer: TTyXYWH);
  public
    constructor Create(AOption: TTyChartOption; AIndex: Integer);
    { [Batch 152] A map series group's own geo: laid out from ALayoutSeries
      (the first map series declared for the map), its regions named by
      ANameMap (the group's nameMaps merged; nil: none). AIndex is the own
      geo's place among the control's. }
    constructor CreateForMap(AOption: TTyChartOption; ALayoutSeries, AIndex: Integer;
      ANameMap: TJSONObject);
    destructor Destroy; override;
    { [Batch 152] the series drawn with this geo (after Resize: one group per
      region name, in GroupName's order), and the series option a map
      series' region model climbs to (ANode: nil keeps the layout series') }
    procedure SetData(const AData: TTyGeoData; AChainNode: TJSONObject = nil);
    property Kind: TTyGeoKind read FKind;
    property Data: TTyGeoData read FSeriesData;
    { the flags of a group, written as the series' item holds them }
    function SetFlags(AGroup, AHover: Integer; AHbo: Cardinal; ASelected: Boolean): Boolean;
    { The map loaded, the view laid out on the container (device px) }
    procedure Resize(const AContainer: TTyRectF; APPI: Integer);
    { [Batch 154] the same in createBoxLayoutReference's container given as
      x / y / width / height -- a matrix cell or a calendar day: the box (and
      layoutCenter / layoutSize) against the cell. A cell of no height is
      laid out far off the canvas (TyBoxNowhere), out of sight -- upstream
      throws on it; one of no width (no column) is laid out as upstream's,
      from x nought. }
    procedure ResizeXYWH(const ARef: TTyXYWH; APPI: Integer);
    { getRegion / getGeoCoord }
    function RegionByName(const AName: string): TTyGeoRegion;
    function GeoCoord(const AName: string; out APt: TTyGeoPt): Boolean;
    { dataToPoint of a coordinate pair, through the projection and the
      overall (ANoRoam: the raw) matrix; False is upstream's undefined }
    function PointOf(AX, AY: Double; out APx: TTyPointF;
      ANoRoam: Boolean = False): Boolean;
    { dataToPoint of a region name }
    function PointOfName(const AName: string; out APx: TTyPointF): Boolean;
    { pointToData: the projection's unproject first (upstream's order), then
      the inverse overall matrix }
    function DataOf(AX, AY: Double; out AData: TTyGeoPt): Boolean;
    { the convertToPixel / convertFromPixel of a JSON value }
    function ToPixelJson(AValue: TJSONData; out APx: TTyPointF): Boolean;
    function FromPixelJson(AValue: TJSONData; out AData: TTyGeoPt): Boolean;
    { ---- ITyCoordSys: data is [lng, lat] ---- }
    function CoordSysName: string;
    function DimCount: Integer;
    function GetRect: TTyRectF;
    function DataToPoint(const AData: array of Double): TTyPointF;
    function DataToLayout(const AData: array of Double): TTyCoordLayout;
    function PointToData(const APoint: TTyPointF; out AData: TTyDoubleArray): Boolean;
    function ContainPoint(const APoint: TTyPointF): Boolean;
    function AxisCount: Integer;
    function GetAxis(AIndex: Integer): TTyAxis;
    { the roam transform's matrix as the transform group holds it, and
      whether the group has one at all (zrender skips a transform within
      5e-5 of the identity) }
    function RoamMatrix: TTyMat2D;
    function HasRoamTransform: Boolean;
    { ==== the roam [Batch 150] ==== }
    { the centre and zoom a geoRoam wrote back into the model's option:
      they stand for the option's own on the next layout (call before
      Resize) }
    procedure SetRoamOption(const ACentre: TTyGraphCentre; AZoom: Double);
    { ownRoamModelCoordSysUpdateInAction for one payload: a pan (both
      deltas) and / or a zoom about a point, the centre and zoom it writes
      back (ACentre, AZoom), and the view worked out again from them. False
      (nothing done) without a laid-out view. }
    function RoamBy(AHasPan: Boolean; ADX, ADY: Double; AHasZoom: Boolean;
      AScale, AOriginX, AOriginY: Double; out ACentre: TTyGraphCentre;
      out AZoom: Double): Boolean;
    { RoamController._checkPointer's area for this geo: roamTrigger
      'global' or containPoint, and inside the clip rect when it clips }
    function RoamPointerIn(AX, AY: Double): Boolean;
    { [Batch 152] the data rect through the overall matrix (BoundingRect.
      applyTransform): a brush's panel, containPoint's box }
    function OverallRect: TTyXYWH;
    { the view rect through the roam transform (HeatmapView: getViewRect
      applyTransform getRoamTransform) }
    function RoamViewRect: TTyXYWH;
    property RoamGen: Integer read FRoamGen;
    { the picture and its state records are there (a list was built) }
    function ItemsReady: Boolean;
    property Index: Integer read FIndex;
    property Spec: TTyGeoSpec read FSpec;
    property Node: TJSONObject read FNode;
    property Valid: Boolean read FValid;
    property Source: TTyGeoSource read FSource;
    property Projection: TTyGeoProjection read FProjection;
    property AspectScale: Double read FAspectScale;
    property InvertY: Boolean read FInvertY;
    property DataRect: TTyXYWH read FData;
    property ViewRect: TTyXYWH read FView;
    property MtRaw: TTyMat2D read FMtRaw;
    property MtRawInv: TTyMat2D read FMtRawInv;
    property MtOverall: TTyMat2D read FMtOverall;
    property MtOverallInv: TTyMat2D read FMtOverallInv;
    property RoamTrans: TTyGeoTrans read FRoam;
    property Zoom: Double read FZoom;
    { ==== the regions as things a pointer reaches [Batch 148] ==== }
    { getShallow up the region model's chain for the region option ARegion
      (nil: none): the option's value, or nil with AToken set where the
      value is one of GeoModel's token defaults }
    function Chain(ARegion: TJSONObject; const APath: array of string;
      out AToken: TTyGeoToken): TJSONData;
    { the region option of a region (by its index in Source.Regions): the
      regions entry for its name -- or a fresh entry of the name -- with the feature's
      echartsStyle merged in where it is silent; nil for an empty name }
    function RegionOpt(ARegionIndex: Integer): TJSONObject;
    { the picture for an ink and a PPI, worked out once and kept }
    function Draw(const AInk: TTyGeoInk; APPI: Integer): TTyGeoDraw;
    { the groups, one per distinct region name }
    function GroupCount: Integer;
    function GroupName(AGroup: Integer): string;
    function GroupIndexOf(const AName: string): Integer;
    { the region option of a group's name (nil: none) }
    function GroupOpt(AGroup: Integer): TJSONObject;
    { an event's params.region: the region model's option as JSON text,
      an empty object where it has none }
    function GroupRegionJson(AGroup: Integer): string;
    { emphasis.focus is 'self' (never for a disabled group); emphasis.disabled
      (no highDownDispatcher) }
    function GroupFocusSelf(AGroup: Integer): Boolean;
    function GroupEmphasisDisabled(AGroup: Integer): Boolean;
    { ---- the flags (util/states.ts) ---- }
    { enterEmphasisWhenMouseOver / leaveEmphasisWhenMouseOut: nothing while
      an action holds the group }
    function HoverEnter(AGroup: Integer): Boolean;
    function HoverLeave(AGroup: Integer): Boolean;
    { enterEmphasis / leaveEmphasis with a highlight digit }
    function EnterEmphasisBy(AGroup, ADigit: Integer): Boolean;
    function LeaveEmphasisBy(AGroup, ADigit: Integer): Boolean;
    { blurComponent: every group into blur, held or not }
    function BlurAll: Boolean;
    { allLeaveBlur's walk over the component: blur back to normal }
    function LeaveBlurAll: Boolean;
    { enterSelect / leaveSelect }
    function SetSelected(AGroup: Integer; ASelected: Boolean): Boolean;
    function GroupFlags(AGroup: Integer): TTyGeoGroupSt;
    { applyElementStates over every path and its text: True when a list
      changed }
    function ApplyStates(const AInk: TTyGeoInk; APPI: Integer): Boolean;
    { a path's states record (the host the path, the label its text) }
    function PathItem(AGroup, APath: Integer): TTyStItem;
    { getComponentStates(geo).isBlured: blurComponent reached it }
    property IsBlured: Boolean read FIsBlured write FIsBlured;
    { the render that made it (the control's count) }
    property Gen: Integer read FGen write FGen;
    { the picture the last Draw worked out (empty before one) }
    property LastDraw: TTyGeoDraw read FDraw;
    { ==== an SVG map [F6b] ==== }
    property IsSvg: Boolean read FIsSvg;
    { the width of a text in a font, CSS px (set before Resize: the parse
      of a <text> moves on by the width of what it has read) }
    property SvgMeasure: TTyGsMeasure read FSvgMeasure write FSvgMeasure;
    property SvgGraphic: TTyGsGraphic read FSvg;
    { a node's state element and its label's (the picture once drawn) }
    function SvgNodeItem(ANode: Integer): TTyStElement;
    function SvgLabelItem(ANode: Integer): TTyStElement;
    function SvgHasLabel(ANode: Integer): Boolean;
    function SvgLabelOf(ANode: Integer): TTyGeoLabel;
    function SvgLook(ANode: Integer): TTyGeoSvgLook;
    { a node's global transform (False: none -- zrender's null) }
    function SvgGlobal(ANode: Integer; out AM: TTyMat2D): Boolean;
    function SvgEventGroup(ANode: Integer): Integer;
    function SvgHoverGroup(ANode: Integer): Integer;
    { [R2-B] A MAP SERIES' POINTER: the dispatcher over the node the pointer
      is on (-1 none) -- SetFlags lifts it alone of its name }
    procedure SetSvgPointer(ANode: Integer);
    { the current per-node stroke Path.getBoundingRect reads }
    function SvgStrokes: TTyGsStrokeArray;
    { getBoundingRect of a node now }
    function SvgNodeRect(ANode: Integer): TTyXYWH;
    { a label host's text, placed as updateInnerText places it now: the
      innerTransformable's position (AX, AY) and rotation, and where the
      text's own origin lands (ATX, ATY), device px; False without a label }
    function SvgLabelPlace(ANode, APPI: Integer; out AX, AY, ARot, ATX, ATY: Double): Boolean;
    { the flags to carry over a render, and their restoring on the new geo
      (the same map, the same nodes) }
    function SvgSaveFlags: TTyGeoSvgFlags;
    procedure SvgRestoreFlags(const AFlags: TTyGeoSvgFlags);
  end;

{ ---- the registry ---- }

{ echarts.registerMap(AName, geoJSON, specialAreas). AGeoJson is the GeoJSON
  text -- or the wrapper form, an object of geoJSON (or geoJson) and
  specialAreas, whose specialAreas then win over ASpecialAreas. It passes the
  option reader's nesting guard and relaxed parse; False (and the registry
  unchanged) when it does not parse. ASpecialAreas: JSON text of an object, '' for none.
  Registering a name again replaces it.
  [F6b] AN SVG MAP: the wrapper form with an `svg` string (upstream's
  registerMap(name, svg-object)), or the markup itself -- text whose first
  character past the white space (and a byte-order mark) is '<', a port
  convenience. False when the XML does not parse or has no svg element
  (upstream throws in parseXML); ASpecialAreas is not read. }
function TyChartRegisterMap(const AName, AGeoJson: string;
  const ASpecialAreas: string = ''): Boolean;
{ echarts.getMap: the GeoJSON and the special areas as registered (JSON text;
  '' for none). False for a name nobody registered. }
function TyChartGetMap(const AName: string; out AGeoJson, ASpecialAreas: string): Boolean;
function TyChartMapRegistered(const AName: string): Boolean;
{ [F6b] the map registered under AName is an SVG one }
function TyGeoMapIsSvg(const AName: string): Boolean;

type
  TTyGeoMissingMap = record
    { 'geo[0]' or 'series[2]' }
    Path: string;
    { the name the option asks for, '' when it names none }
    MapName: string;
  end;
  TTyGeoMissingMapArray = array of TTyGeoMissingMap;

{ Every geo component, and every map series that draws its own map (one
  without a geoIndex), whose map nobody has registered. Upstream warns in the
  console and draws an empty view; the control and TyOptDiagnose both say so
  from this one list, so the two cannot disagree about which maps are
  missing. [F1b] }
function TyGeoUnregisteredMaps(AOption: TTyChartOption): TTyGeoMissingMapArray;

{ Not upstream's: a way to take a map back out, for a design-time host and
  for tests. }
procedure TyChartUnregisterMap(const AName: string);
procedure TyChartClearMaps;
{ GeoJSONResource.load: the regions for a nameMap (nil for none) and a
  nameProperty ('' is 'name'); nil when the name is not registered or the
  map does not parse (upstream throws there). The caller frees it. }
function TyGeoLoadMap(const AName: string; ANameMap: TJSONObject;
  const ANameProperty: string): TTyGeoSource;

{ ---- projections ---- }
procedure TyChartRegisterGeoProjection(const AName: string; AHandler: TTyGeoProjectHandler);
procedure TyChartUnregisterGeoProjection(const AName: string);
function TyChartFindGeoProjection(const ASpec: string; out AHandler: TTyGeoProjectHandler): Boolean;
procedure TyChartClearGeoProjections;

{ ---- the pieces, exported for the tests ---- }

{ decodeRing: one encoded ring, per UTF-16 unit of AText }
function TyGeoDecodeRing(const AText: string; AOffX, AOffY, AScale: Double): TTyGeoRing;
{ the geo's options }
function TyGeoSpecOf(AOption: TTyChartOption; AIndex: Integer): TTyGeoSpec;
{ zrender's matrix arithmetic, operation for operation }
function TyGeoMatMul(const M1, M2: TTyMat2D): TTyMat2D;
function TyGeoMatInvert(const A: TTyMat2D; out AOut: TTyMat2D): Boolean;
function TyGeoDecompose(const M: TTyMat2D): TTyGeoTrans;
function TyGeoLocalTransform(const T: TTyGeoTrans): TTyMat2D;
function TyGeoApply(const M: TTyMat2D; AX, AY: Double): TTyGeoPt;

{ [Batch 148] JSON.stringify of an option value }
function TyGeoJsJson(AData: TJSONData): string;
{ [Batch 152] zrUtil.merge without overwrite: what ATarget leaves out, an
  object into an object deep }
procedure TyGeoMergeAbsent(ATarget, ASource: TJSONObject);

{ MapDraw._buildGeoJSON's picture, as data }
function TyGeoDrawOf(AGeo: TTyGeo; const AInk: TTyGeoInk; APPI: Integer): TTyGeoDraw;
{ ...and as elements, into AList }
function TyBuildGeo(AGeo: TTyGeo; const AInk: TTyGeoInk;
  const AMeasurer: ITyTextMeasurer; APPI: Integer; AList: TTyPaintList;
  AApplyStates: Boolean = True): Integer;
{ [R2-C] the key a map view's elements carry (TTyChartAnim.GeoView): a geo
  component's index + 1, a map series' own geo -(the series index + 1) }
function TyGeoViewKey(AGeo: TTyGeo): Integer;

implementation

uses
  DOM,
  tyControls.AdvChart.Data, tyControls.AdvChart.ZrPath, tyControls.FontUnits,
  tyControls.AdvChart.JsMath, tyControls.AdvChart.Convert,
  tyControls.AdvChart.Calendar,
  tyControls.AdvChart.Labels, tyControls.AdvChart.OptionMerge,
  tyControls.AdvChart.Scale;

const
  { Math.PI as a Double: every use is one Double operation upstream makes }
  cJsPi: Double = 3.141592653589793;
  { zrender Transformable's EPSILON }
  cTransEps: Double = 5e-5;
  { [F6b] what SvgTraverse does to a node and all under it }
  cSvgEnterEmph = 0;
  cSvgLeaveEmph = 1;
  cSvgEnterBlur = 2;
  cSvgLeaveBlur = 3;
  cSvgSetSel = 4;
  cSvgSetHover = 5;

type
  TFpuMask = record
    M: TFPUExceptionMask;
  end;

function MaskFpu: TFpuMask;
begin
  Result.M := SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
    exOverflow, exUnderflow, exPrecision]);
end;

procedure UnmaskFpu(const AMask: TFpuMask);
begin
  { [F6b] SSE's flags too (MXCSR), which ClearExceptions leaves on x86_64 }
  TyZrRestoreFpu(AMask.M);
end;

{ ==================== JavaScript values ==================== }

function SignBit(A: Double): Boolean;
begin
  Result := (PQWord(@A)^ shr 63) = 1;
end;

{ Math.min / Math.max: a not-a-number wins, and -0 is below +0 }
function JsMin(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if A < B then Exit(A);
  if B < A then Exit(B);
  if SignBit(A) then Result := A else Result := B;
end;

function JsMax(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if A > B then Exit(A);
  if B > A then Exit(B);
  if SignBit(A) then Result := B else Result := A;
end;

{ isFinite after ToNumber }
function JsFinite(AValue: Double): Boolean;
begin
  Result := not (IsNan(AValue) or IsInfinite(AValue));
end;

{ `v` truthy as JavaScript reads it }
function Truthy(AData: TJSONData): Boolean;
var v: Double;
begin
  Result := False;
  if AData = nil then Exit;
  case AData.JSONType of
    jtBoolean: Result := AData.AsBoolean;
    jtNumber:
      begin
        v := AData.AsFloat;
        Result := (not IsNan(v)) and (v <> 0);
      end;
    jtString: Result := AData.AsString <> '';
    jtArray, jtObject: Result := True;
  end;
end;

function IsNullish(AData: TJSONData): Boolean;
begin
  Result := (AData = nil) or (AData.JSONType = jtNull);
end;

{ an object's own key -- nil when absent }
function Own(ANode: TJSONData; const AKey: string): TJSONData;
begin
  Result := nil;
  if ANode is TJSONObject then Result := TJSONObject(ANode).Find(AKey);
end;

{ v[i] as a JSON value (nil for undefined): an array's item, nothing else
  -- a string's character is not a coordinate anybody writes }
function Item(AData: TJSONData; AIndex: Integer): TJSONData;
begin
  Result := nil;
  if (AData is TJSONArray) and (AIndex >= 0) and (AIndex < TJSONArray(AData).Count) then
    Result := TJSONArray(AData).Items[AIndex];
end;

{ getShallow / get on a component: its own value unless null or absent, then
  the option root's }
function Climb(ANode, ARoot: TJSONObject; const AKey: string): TJSONData;
var d: TJSONData;
begin
  Result := nil;
  if ANode <> nil then
  begin
    d := ANode.Find(AKey);
    if (d <> nil) and (d.JSONType <> jtNull) then Exit(d);
  end;
  if ARoot <> nil then
  begin
    d := ARoot.Find(AKey);
    if (d <> nil) and (d.JSONType <> jtNull) then Exit(d);
  end;
end;

{ new BoundingRect: a negative size turns the rect round }
function NewRect(AX, AY, AW, AH: Double): TTyXYWH;
begin
  if AW < 0 then
  begin
    AX := AX + AW;
    AW := -AW;
  end;
  if AH < 0 then
  begin
    AY := AY + AH;
    AH := -AH;
  end;
  Result.X := AX;
  Result.Y := AY;
  Result.W := AW;
  Result.H := AH;
end;

{ BoundingRect.union, its isFinite branches and all }
procedure RectUnion(var R: TTyXYWH; const O: TTyXYWH);
var x, y: Double;
begin
  x := JsMin(O.X, R.X);
  y := JsMin(O.Y, R.Y);
  if JsFinite(R.X) and JsFinite(R.W) then
    R.W := JsMax(O.X + O.W, R.X + R.W) - x
  else
    R.W := O.W;
  if JsFinite(R.Y) and JsFinite(R.H) then
    R.H := JsMax(O.Y + O.H, R.Y + R.H) - y
  else
    R.H := O.H;
  R.X := x;
  R.Y := y;
end;

{ BoundingRect.applyTransform (target = source) }
function RectApply(const R: TTyXYWH; const M: TTyMat2D): TTyXYWH;
var p: array[0..3] of TTyGeoPt; k: Integer; x0, y0, x1, y1: Double;
begin
  if (M[1] < 1e-5) and (M[1] > -1e-5) and (M[2] < 1e-5) and (M[2] > -1e-5) then
  begin
    Result.X := R.X * M[0] + M[4];
    Result.Y := R.Y * M[3] + M[5];
    Result.W := R.W * M[0];
    Result.H := R.H * M[3];
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
    Exit;
  end;
  { the four corners: lt, rb, lb, rt }
  p[0] := TyGeoApply(M, R.X, R.Y);
  p[1] := TyGeoApply(M, R.X + R.W, R.Y + R.H);
  p[2] := TyGeoApply(M, R.X, R.Y + R.H);
  p[3] := TyGeoApply(M, R.X + R.W, R.Y);
  x0 := p[0].X; y0 := p[0].Y; x1 := p[0].X; y1 := p[0].Y;
  for k := 1 to 3 do
  begin
    x0 := JsMin(x0, p[k].X);
    y0 := JsMin(y0, p[k].Y);
    x1 := JsMax(x1, p[k].X);
    y1 := JsMax(y1, p[k].Y);
  end;
  Result.X := x0;
  Result.Y := y0;
  Result.W := x1 - x0;
  Result.H := y1 - y0;
end;

function RectContain(const R: TTyXYWH; AX, AY: Double): Boolean;
begin
  Result := (AX >= R.X) and (AX <= R.X + R.W) and (AY >= R.Y) and (AY <= R.Y + R.H);
end;

{ ==================== zrender's matrices ==================== }

function TyGeoMatMul(const M1, M2: TTyMat2D): TTyMat2D;
begin
  Result[0] := M1[0] * M2[0] + M1[2] * M2[1];
  Result[1] := M1[1] * M2[0] + M1[3] * M2[1];
  Result[2] := M1[0] * M2[2] + M1[2] * M2[3];
  Result[3] := M1[1] * M2[2] + M1[3] * M2[3];
  Result[4] := M1[0] * M2[4] + M1[2] * M2[5] + M1[4];
  Result[5] := M1[1] * M2[4] + M1[3] * M2[5] + M1[5];
end;

function TyGeoMatInvert(const A: TTyMat2D; out AOut: TTyMat2D): Boolean;
var aa, ac, atx, ab, ad, aty, det: Double;
begin
  aa := A[0]; ac := A[2]; atx := A[4];
  ab := A[1]; ad := A[3]; aty := A[5];
  det := aa * ad - ab * ac;
  { `!det`: nought and not-a-number answer null }
  if IsNan(det) or (det = 0) then
  begin
    AOut := A;
    Exit(False);
  end;
  det := 1.0 / det;
  AOut[0] := ad * det;
  AOut[1] := -ab * det;
  AOut[2] := -ac * det;
  AOut[3] := aa * det;
  AOut[4] := (ac * aty - ad * atx) * det;
  AOut[5] := (ab * atx - aa * aty) * det;
  Result := True;
end;

function TyGeoApply(const M: TTyMat2D; AX, AY: Double): TTyGeoPt;
begin
  Result.X := M[0] * AX + M[2] * AY + M[4];
  Result.Y := M[1] * AX + M[3] * AY + M[5];
end;

function MatIdentity: TTyMat2D;
begin
  Result[0] := 1; Result[1] := 0; Result[2] := 0;
  Result[3] := 1; Result[4] := 0; Result[5] := 0;
end;

{ Transformable.setLocalTransform, which decomposeTransform ends in }
function TyGeoDecompose(const M: TTyMat2D): TTyGeoTrans;
var sx, sy, rot, shear: Double;
begin
  sx := M[0] * M[0] + M[1] * M[1];
  sy := M[2] * M[2] + M[3] * M[3];
  rot := TyJsAtan2(M[1], M[0]);
  shear := cJsPi / 2 + rot - TyJsAtan2(M[3], M[2]);
  sy := Sqrt(sy) * TyJsCos(shear);
  sx := Sqrt(sx);
  Result.SkewX := shear;
  Result.SkewY := 0;
  Result.Rotation := -rot;
  Result.X := M[4];
  Result.Y := M[5];
  Result.ScaleX := sx;
  Result.ScaleY := sy;
end;

{ `v ? f(v) : 0` and `v || 0`: nought and not-a-number are falsy }
function JsFalsy(AValue: Double): Boolean;
begin
  Result := IsNan(AValue) or (AValue = 0);
end;

{ Transformable.getLocalTransform with no origin and no anchor }
function TyGeoLocalTransform(const T: TTyGeoTrans): TTyMat2D;
var skx, sky, rot, aa, ac, atx, ab, ad, aty, st, ct: Double;
begin
  if JsFalsy(T.SkewX) then skx := 0 else skx := TyJsTan(T.SkewX);
  if JsFalsy(T.SkewY) then sky := 0 else sky := TyJsTan(-T.SkewY);
  if JsFalsy(T.Rotation) then rot := 0 else rot := T.Rotation;
  Result[4] := 0;
  Result[5] := 0;
  Result[0] := T.ScaleX;
  Result[3] := T.ScaleY;
  Result[1] := sky * T.ScaleX;
  Result[2] := skx * T.ScaleY;
  if rot <> 0 then
  begin
    { matrix.rotate about the origin }
    aa := Result[0]; ac := Result[2]; atx := Result[4];
    ab := Result[1]; ad := Result[3]; aty := Result[5];
    st := TyJsSin(rot);
    ct := TyJsCos(rot);
    Result[0] := aa * ct + ab * st;
    Result[1] := -aa * st + ab * ct;
    Result[2] := ac * ct + ad * st;
    Result[3] := -ac * st + ct * ad;
    Result[4] := ct * (atx - 0) + st * (aty - 0) + 0;
    Result[5] := ct * (aty - 0) - st * (atx - 0) + 0;
  end;
  Result[4] := Result[4] + (0 + T.X);
  Result[5] := Result[5] + (0 + T.Y);
end;

{ BoundingRect.calculateTransform(a -> b): identity, translate(-a), scale,
  translate(b) }
function CalcTransform(const A, B: TTyXYWH): TTyMat2D;
var sx, sy: Double;
begin
  sx := B.W / A.W;
  sy := B.H / A.H;
  Result := MatIdentity;
  Result[4] := Result[4] + (-A.X);
  Result[5] := Result[5] + (-A.Y);
  Result[0] := Result[0] * sx;
  Result[1] := Result[1] * sy;
  Result[2] := Result[2] * sx;
  Result[3] := Result[3] * sy;
  Result[4] := Result[4] * sx;
  Result[5] := Result[5] * sy;
  Result[4] := Result[4] + B.X;
  Result[5] := Result[5] + B.Y;
end;

function TransOf(AX, AY, AScale: Double): TTyGeoTrans;
begin
  Result := Default(TTyGeoTrans);
  Result.X := AX;
  Result.Y := AY;
  Result.ScaleX := AScale;
  Result.ScaleY := AScale;
end;

{ ==================== the region ==================== }

constructor TTyGeoRegion.Create(const AName: string; const AGeoms: TTyGeoGeometryArray;
  AHasCp: Boolean; const ACp: TTyGeoPt);
begin
  inherited Create;
  FName := AName;
  FGeometries := AGeoms;
  FHasCenter := AHasCp;
  FCenter := ACp;
end;

procedure TTyGeoRegion.AddGeometry(const AGeom: TTyGeoGeometry);
var n: Integer;
begin
  n := Length(FGeometries);
  SetLength(FGeometries, n + 1);
  FGeometries[n] := AGeom;
end;

function TTyGeoRegion.GetCenter: TTyGeoPt;
begin
  if not FHasCenter then
  begin
    FCenter := CalcCenter;
    FHasCenter := True;
  end;
  Result := FCenter;
end;

procedure TTyGeoRegion.SetCenter(const APt: TTyGeoPt);
begin
  FCenter := APt;
  FHasCenter := True;
end;

{ centroid(points): the signed-area centroid of a closed ring, or its first
  point when the area is nought (or not a number) }
function Centroid(const P: TTyGeoRing): TTyGeoPt;
var
  area, cx, cy, x0, y0, x1, y1, a: Double;
  i, n: Integer;
begin
  n := Length(P);
  area := 0;
  cx := 0;
  cy := 0;
  x0 := P[n - 1].X;
  y0 := P[n - 1].Y;
  for i := 0 to n - 1 do
  begin
    x1 := P[i].X;
    y1 := P[i].Y;
    a := x0 * y1 - x1 * y0;
    area := area + a;
    cx := cx + (x0 + x1) * a;
    cy := cy + (y0 + y1) * a;
    x0 := x1;
    y0 := y1;
  end;
  if not JsFalsy(area) then
  begin
    Result.X := cx / area / 3;
    Result.Y := cy / area / 3;
  end
  else
  begin
    { `points[0][0] || 0` }
    Result.X := P[0].X;
    Result.Y := P[0].Y;
    if JsFalsy(Result.X) then Result.X := 0;
    if JsFalsy(Result.Y) then Result.Y := 0;
  end;
end;

function TTyGeoRegion.CalcCenter: TTyGeoPt;
var
  i, best, bestSize, size: Integer;
  r: TTyXYWH;
begin
  { the polygon with the most exterior points -- the first of equals; lines
    have no exterior }
  best := -1;
  bestSize := 0;
  for i := 0 to High(FGeometries) do
  begin
    if FGeometries[i].Kind <> ggkPolygon then Continue;
    size := Length(FGeometries[i].Exterior);
    if size > bestSize then
    begin
      best := i;
      bestSize := size;
    end;
  end;
  if best >= 0 then Exit(Centroid(FGeometries[best].Exterior));
  r := BoundingRect;
  Result.X := r.X + r.W / 2;
  Result.Y := r.Y + r.H / 2;
end;

type
  TBBox = record
    MinX, MinY, MaxX, MaxY: Double;
  end;

procedure BBoxAdd(var B: TBBox; const APoints: TTyGeoRing; const AProj: TTyGeoProjection);
var i: Integer; x, y: Double;
begin
  for i := 0 to High(APoints) do
  begin
    x := APoints[i].X;
    y := APoints[i].Y;
    if AProj.Active then
      if not AProj.Project(x, y, x, y) then Continue;
    if JsFinite(x) and JsFinite(y) then
    begin
      B.MinX := JsMin(B.MinX, x);
      B.MinY := JsMin(B.MinY, y);
      B.MaxX := JsMax(B.MaxX, x);
      B.MaxY := JsMax(B.MaxY, y);
    end;
  end;
end;

function RegionRect(const AGeoms: TTyGeoGeometryArray; const AProj: TTyGeoProjection): TTyXYWH;
var b: TBBox; i, k: Integer;
begin
  b.MinX := Infinity;
  b.MinY := Infinity;
  b.MaxX := -Infinity;
  b.MaxY := -Infinity;
  for i := 0 to High(AGeoms) do
    if AGeoms[i].Kind = ggkPolygon then
      { the holes are not counted }
      BBoxAdd(b, AGeoms[i].Exterior, AProj)
    else
      for k := 0 to High(AGeoms[i].Lines) do
        BBoxAdd(b, AGeoms[i].Lines[k], AProj);
  if not (JsFinite(b.MinX) and JsFinite(b.MinY) and JsFinite(b.MaxX) and JsFinite(b.MaxY)) then
  begin
    b.MinX := 0; b.MinY := 0; b.MaxX := 0; b.MaxY := 0;
  end;
  Result := NewRect(b.MinX, b.MinY, b.MaxX - b.MinX, b.MaxY - b.MinY);
end;

function TTyGeoRegion.BoundingRect: TTyXYWH;
var none: TTyGeoProjection;
begin
  if not FHasRect then
  begin
    none := Default(TTyGeoProjection);
    FRect := RegionRect(FGeometries, none);
    FHasRect := True;
  end;
  Result := FRect;
end;

function TTyGeoRegion.ProjectedRect(const AProj: TTyGeoProjection): TTyXYWH;
begin
  Result := RegionRect(FGeometries, AProj);
end;

procedure TransformRing(const ARing: TTyGeoRing; const M: TTyMat2D);
var p: Integer; q: TTyGeoPt;
begin
  { in place: the arrays are the ones the resource's features hold }
  for p := 0 to High(ARing) do
  begin
    q := TyGeoApply(M, ARing[p].X, ARing[p].Y);
    ARing[p] := q;
  end;
end;

procedure TTyGeoRegion.TransformTo(AX, AY, AW, AH: Double);
var
  r, target: TTyXYWH;
  aspect: Double;
  m: TTyMat2D;
  i, k: Integer;
begin
  r := BoundingRect;
  aspect := r.W / r.H;
  if JsFalsy(AW) then AW := aspect * AH
  else if JsFalsy(AH) then AH := AW / aspect;
  target := NewRect(AX, AY, AW, AH);
  m := CalcTransform(r, target);
  for i := 0 to High(FGeometries) do
    if FGeometries[i].Kind = ggkPolygon then
    begin
      TransformRing(FGeometries[i].Exterior, m);
      for k := 0 to High(FGeometries[i].Interiors) do
        TransformRing(FGeometries[i].Interiors[k], m);
    end
    else
      for k := 0 to High(FGeometries[i].Lines) do
        TransformRing(FGeometries[i].Lines[k], m);
  FRect := target;
  FHasRect := True;
  FCenter.X := FRect.X + FRect.W / 2;
  FCenter.Y := FRect.Y + FRect.H / 2;
  FHasCenter := True;
end;

function TTyGeoRegion.CloneShallow(const AName: string): TTyGeoRegion;
begin
  Result := TTyGeoRegion.Create(AName, FGeometries, FHasCenter, FCenter);
  Result.FHasRect := FHasRect;
  Result.FRect := FRect;
  Result.FProperties := FProperties;
end;

{ ==================== the source ==================== }

destructor TTyGeoSource.Destroy;
var i: Integer;
begin
  for i := 0 to High(FRegions) do FRegions[i].Free;
  FRegions := nil;
  inherited Destroy;
end;

function TTyGeoSource.RegionByName(const AName: string): TTyGeoRegion;
var i: Integer;
begin
  Result := nil;
  { regionsMap.set: the last region of a name wins }
  for i := High(FRegions) downto 0 do
    if FRegions[i].Name = AName then Exit(FRegions[i]);
end;

{ ==================== the resource ==================== }

type
  TGeoFeatureKind = (gfkPolygon, gfkMultiPolygon, gfkLineString, gfkMultiLineString, gfkOther);

  { One feature after the decode, shared by every parse of the map. }
  TGeoFeature = record
    Kept: Boolean;
    Props: TJSONData;
    Kind: TGeoFeatureKind;
    { Polygon: one entry, its rings; MultiPolygon: one per polygon, with
      HasFirst whether its first ring is there (`if (item[0])`) }
    Polys: array of TTyGeoRingArray;
    HasFirst: array of Boolean;
    Lines: TTyGeoRingArray;
  end;

  TGeoParsed = record
    NameProperty: string;
    Regions: TTyGeoRegionArray;
    Rect: TTyXYWH;
    HasRect: Boolean;
  end;

  TGeoResource = class
  public
    Name: string;
    Text: string;
    SpecialText: string;
    Root: TJSONData;
    Special: TJSONObject;
    Decoded: Boolean;
    Failed: Boolean;
    Features: array of TGeoFeature;
    Parsed: array of TGeoParsed;
    { [F6b] an SVG map: the document parseXML read and its svg element, the
      bounding rect of the first graphic built (every later build reuses it,
      as _buildGraphic reuses this._boundingRect), the region names a build
      without a measurer finds (what MapSeries appends) and its rect }
    IsSvg: Boolean;
    SvgDoc: TXMLDocument;
    SvgEl: TDOMElement;
    SvgHasRect: Boolean;
    SvgRect: TTyXYWH;
    SvgNames: TTyStringArray;
    SvgNamesRect: TTyXYWH;
    destructor Destroy; override;
    procedure Decode;
    function ParseRegions(const ANameProperty: string): Integer;
    function Load(ANameMap: TJSONObject; const ANameProperty: string): TTyGeoSource;
  end;

destructor TGeoResource.Destroy;
var i, k: Integer;
begin
  for i := 0 to High(Parsed) do
    for k := 0 to High(Parsed[i].Regions) do
      Parsed[i].Regions[k].Free;
  Parsed := nil;
  Root.Free;
  Special.Free;
  SvgDoc.Free;
  inherited Destroy;
end;

function ToInt32(AValue: Double): LongInt;
var t: Double;
begin
  if IsNan(AValue) or IsInfinite(AValue) then Exit(0);
  t := Int(AValue);
  t := t - 4294967296.0 * Floor(t / 4294967296.0);
  if t >= 2147483648.0 then t := t - 4294967296.0;
  Result := LongInt(Trunc(t));
end;

function TyGeoDecodeRing(const AText: string; AOffX, AOffY, AScale: Double): TTyGeoRing;
var
  u: UnicodeString;
  i, n, k: Integer;
  xi, yi: LongInt;
  x, y, prevX, prevY, cy: Double;
begin
  Result := nil;
  u := UTF8Decode(AText);
  n := Length(u);
  SetLength(Result, (n + 1) div 2);
  prevX := AOffX;
  prevY := AOffY;
  k := 0;
  i := 1;
  while i <= n do
  begin
    xi := Ord(u[i]) - 64;
    { charCodeAt past the end is not a number: `NaN - 64`, which the
      bitwise operators read as nought }
    if i + 1 <= n then cy := Ord(u[i + 1]) - 64 else cy := NaN;
    yi := ToInt32(cy);
    { ZigZag }
    xi := SarLongint(xi, 1) xor (-(xi and 1));
    yi := SarLongint(yi, 1) xor (-(yi and 1));
    { Delta }
    x := xi + prevX;
    y := yi + prevY;
    prevX := x;
    prevY := y;
    Result[k].X := x / AScale;
    Result[k].Y := y / AScale;
    Inc(k);
    Inc(i, 2);
  end;
  SetLength(Result, k);
end;

{ A ring written out: an array of points, each [x, y] as ToNumber reads
  them. A ring that is not an array has no points. }
function RingOf(AData: TJSONData): TTyGeoRing;
var a: TJSONArray; i: Integer; p: TJSONData;
begin
  Result := nil;
  if not (AData is TJSONArray) then Exit;
  a := TJSONArray(AData);
  SetLength(Result, a.Count);
  for i := 0 to a.Count - 1 do
  begin
    p := a.Items[i];
    if p is TJSONArray then
    begin
      Result[i].X := TyJsonToNumber(Item(p, 0));
      Result[i].Y := TyJsonToNumber(Item(p, 1));
    end
    else
    begin
      Result[i].X := NaN;
      Result[i].Y := NaN;
    end;
  end;
end;

function RingsOf(AData: TJSONData): TTyGeoRingArray;
var i: Integer;
begin
  Result := nil;
  if not (AData is TJSONArray) then Exit;
  SetLength(Result, TJSONArray(AData).Count);
  for i := 0 to TJSONArray(AData).Count - 1 do
    Result[i] := RingOf(TJSONArray(AData).Items[i]);
end;

type
  EGeoParse = class(Exception);

{ decodeRing with the offsets an entry of encodeOffsets holds; an entry that
  is not there is a TypeError upstream }
function DecodeWith(ACoord, AOffsets: TJSONData; AScale: Double; AStrict: Boolean): TTyGeoRing;
begin
  if not (ACoord is TJSONString) then raise EGeoParse.Create('coordinates is not encoded');
  if IsNullish(AOffsets) then
  begin
    if AStrict then raise EGeoParse.Create('no encodeOffsets for a ring');
    Exit(TyGeoDecodeRing(ACoord.AsString, NaN, NaN, AScale));
  end;
  Result := TyGeoDecodeRing(ACoord.AsString, TyJsonToNumber(Item(AOffsets, 0)),
    TyJsonToNumber(Item(AOffsets, 1)), AScale);
end;

function DecodeRings(ARings, AOffsets: TJSONData; AScale: Double): TTyGeoRingArray;
var i: Integer;
begin
  Result := nil;
  if not (ARings is TJSONArray) then raise EGeoParse.Create('rings is not an array');
  SetLength(Result, TJSONArray(ARings).Count);
  for i := 0 to TJSONArray(ARings).Count - 1 do
    Result[i] := DecodeWith(TJSONArray(ARings).Items[i], Item(AOffsets, i), AScale, True);
end;

procedure TGeoResource.Decode;
var
  feats: TJSONData;
  fa: TJSONArray;
  i, k: Integer;
  f, geom, coords, offs: TJSONData;
  encoded, decodedThis: Boolean;
  scale: Double;
  t: string;
  ft: TGeoFeature;
  len: Integer;
begin
  if Decoded then Exit;
  Decoded := True;
  Features := nil;
  try
    feats := Own(Root, 'features');
    encoded := Truthy(Own(Root, 'UTF8Encoding'));
    scale := 1024;
    if not IsNullish(Own(Root, 'UTF8Scale')) then scale := TyJsonToNumber(Own(Root, 'UTF8Scale'));
    if not (feats is TJSONArray) then Exit;
    fa := TJSONArray(feats);
    SetLength(Features, fa.Count);
    for i := 0 to fa.Count - 1 do
    begin
      ft := Default(TGeoFeature);
      f := fa.Items[i];
      if not (f is TJSONObject) then raise EGeoParse.Create('a feature is not an object');
      geom := Own(f, 'geometry');
      decodedThis := False;
      t := '';
      if geom is TJSONObject then
        if Own(geom, 'type') is TJSONString then t := Own(geom, 'type').AsString;
      if t = 'Polygon' then ft.Kind := gfkPolygon
      else if t = 'MultiPolygon' then ft.Kind := gfkMultiPolygon
      else if t = 'LineString' then ft.Kind := gfkLineString
      else if t = 'MultiLineString' then ft.Kind := gfkMultiLineString
      else ft.Kind := gfkOther;
      coords := Own(geom, 'coordinates');
      { THE DECODE, before the filter: a feature with no geometry is a
        TypeError there, in a compressed file only }
      if encoded then
      begin
        if IsNullish(geom) then raise EGeoParse.Create('a feature has no geometry');
        offs := Own(geom, 'encodeOffsets');
        if Truthy(offs) then
        begin
          decodedThis := True;
          case ft.Kind of
            gfkLineString:
              begin
                SetLength(ft.Lines, 1);
                ft.Lines[0] := DecodeWith(coords, offs, scale, False);
              end;
            gfkPolygon:
              begin
                SetLength(ft.Polys, 1);
                SetLength(ft.HasFirst, 1);
                ft.Polys[0] := DecodeRings(coords, offs, scale);
                ft.HasFirst[0] := True;
              end;
            gfkMultiLineString:
              ft.Lines := DecodeRings(coords, offs, scale);
            gfkMultiPolygon:
              begin
                if not (coords is TJSONArray) then raise EGeoParse.Create('rings is not an array');
                SetLength(ft.Polys, TJSONArray(coords).Count);
                SetLength(ft.HasFirst, TJSONArray(coords).Count);
                for k := 0 to TJSONArray(coords).Count - 1 do
                begin
                  if IsNullish(Item(offs, k)) then raise EGeoParse.Create('no encodeOffsets for a polygon');
                  ft.Polys[k] := DecodeRings(TJSONArray(coords).Items[k], Item(offs, k), scale);
                  ft.HasFirst[k] := Length(ft.Polys[k]) > 0;
                end;
              end;
          else
            decodedThis := False;
          end;
        end;
      end;
      { THE FILTER: a geometry, properties, and coordinates of some length }
      if not Truthy(geom) then
      begin
        Features[i] := ft;
        Continue;
      end;
      if not Truthy(Own(f, 'properties')) then
      begin
        Features[i] := ft;
        Continue;
      end;
      if decodedThis then
      begin
        case ft.Kind of
          gfkLineString: len := Length(ft.Lines[0]);
          gfkPolygon: len := Length(ft.Polys[0]);
          gfkMultiLineString: len := Length(ft.Lines);
        else
          len := Length(ft.Polys);
        end;
      end
      else
      begin
        if IsNullish(coords) then raise EGeoParse.Create('a geometry has no coordinates');
        if coords is TJSONArray then len := TJSONArray(coords).Count
        else if coords is TJSONString then len := Length(UTF8Decode(coords.AsString))
        else len := 0;
      end;
      if len <= 0 then
      begin
        Features[i] := ft;
        Continue;
      end;
      ft.Kept := True;
      ft.Props := Own(f, 'properties');
      if not decodedThis then
        case ft.Kind of
          gfkPolygon:
            begin
              SetLength(ft.Polys, 1);
              SetLength(ft.HasFirst, 1);
              ft.Polys[0] := RingsOf(coords);
              ft.HasFirst[0] := True;
            end;
          gfkMultiPolygon:
            if coords is TJSONArray then
            begin
              SetLength(ft.Polys, TJSONArray(coords).Count);
              SetLength(ft.HasFirst, TJSONArray(coords).Count);
              for k := 0 to TJSONArray(coords).Count - 1 do
              begin
                ft.Polys[k] := RingsOf(TJSONArray(coords).Items[k]);
                ft.HasFirst[k] := Truthy(Item(TJSONArray(coords).Items[k], 0));
              end;
            end;
          gfkLineString:
            begin
              SetLength(ft.Lines, 1);
              ft.Lines[0] := RingOf(coords);
            end;
          gfkMultiLineString:
            ft.Lines := RingsOf(coords);
        end;
      Features[i] := ft;
    end;
  except
    on EGeoParse do
    begin
      Failed := True;
      Features := nil;
    end;
  end;
end;

{ String(v) of a region's name (properties[nameProperty]) }
function NameOf(AProps: TJSONData; const AProperty: string): string;
begin
  Result := TyJsonJsString(Own(AProps, AProperty));
end;

function TGeoResource.ParseRegions(const ANameProperty: string): Integer;
var
  i, k, n: Integer;
  ft: TGeoFeature;
  geoms: TTyGeoGeometryArray;
  g: TTyGeoGeometry;
  regions: TTyGeoRegionArray;
  cpData: TJSONData;
  cp, c: TTyGeoPt;
  hasCp: Boolean;
  r: TTyGeoRegion;
  dx, dy: Double;
  sa: TJSONData;
  rect: TTyXYWH;
  hasRect: Boolean;
  nanhai: TTyGeoRingArray;
  isChina, found: Boolean;
begin
  for i := 0 to High(Parsed) do
    if Parsed[i].NameProperty = ANameProperty then Exit(i);
  Result := -1;
  Decode;
  if Failed then Exit;
  regions := nil;
  for i := 0 to High(Features) do
  begin
    ft := Features[i];
    if not ft.Kept then Continue;
    geoms := nil;
    case ft.Kind of
      gfkPolygon, gfkMultiPolygon:
        for k := 0 to High(ft.Polys) do
        begin
          if not ft.HasFirst[k] then Continue;
          g := Default(TTyGeoGeometry);
          g.Kind := ggkPolygon;
          g.Exterior := ft.Polys[k][0];
          { coordinates.slice(1): a new list of the same rings }
          SetLength(g.Interiors, Length(ft.Polys[k]) - 1);
          for n := 1 to High(ft.Polys[k]) do
            g.Interiors[n - 1] := ft.Polys[k][n];
          SetLength(geoms, Length(geoms) + 1);
          geoms[High(geoms)] := g;
        end;
      gfkLineString, gfkMultiLineString:
        begin
          g := Default(TTyGeoGeometry);
          g.Kind := ggkLineString;
          SetLength(g.Lines, Length(ft.Lines));
          for n := 0 to High(ft.Lines) do g.Lines[n] := ft.Lines[n];
          SetLength(geoms, Length(geoms) + 1);
          geoms[High(geoms)] := g;
        end;
    end;
    { `cp && [cp[0], cp[1]]` }
    cpData := Own(ft.Props, 'cp');
    hasCp := Truthy(cpData);
    cp.X := NaN;
    cp.Y := NaN;
    if hasCp then
    begin
      cp.X := TyJsonToNumber(Item(cpData, 0));
      cp.Y := TyJsonToNumber(Item(cpData, 1));
    end;
    r := TTyGeoRegion.Create(NameOf(ft.Props, ANameProperty), geoms, hasCp, cp);
    r.Properties := ft.Props;
    SetLength(regions, Length(regions) + 1);
    regions[High(regions)] := r;
  end;

  isChina := Name = TyGeoChinaMapName;
  { fixNanhai: the islands appended unless a region has their name }
  if isChina then
  begin
    found := False;
    for i := 0 to High(regions) do
      if regions[i].Name = TyGeoNanhaiName then found := True;
    if not found then
    begin
      nanhai := TyGeoNanhaiRings;
      geoms := nil;
      SetLength(geoms, Length(nanhai));
      for i := 0 to High(nanhai) do
      begin
        geoms[i] := Default(TTyGeoGeometry);
        geoms[i].Kind := ggkPolygon;
        geoms[i].Exterior := nanhai[i];
      end;
      r := TTyGeoRegion.Create(TyGeoNanhaiName, geoms, True, TyGeoNanhaiCentre);
      SetLength(regions, Length(regions) + 1);
      regions[High(regions)] := r;
    end;
  end;

  for i := 0 to High(regions) do
  begin
    r := regions[i];
    if isChina then
    begin
      { fixTextCoord }
      if TyGeoTextOffset(r.Name, dx, dy) then
      begin
        c := r.GetCenter;
        c.X := c.X + dx / 10.5;
        c.Y := c.Y + (-dy) / (10.5 / 0.75);
        r.SetCenter(c);
      end;
      { fixDiaoyuIsland }
      if r.Name = TyGeoDiaoyuHostName then
      begin
        g := Default(TTyGeoGeometry);
        g.Kind := ggkPolygon;
        g.Exterior := TyGeoDiaoyuRing;
        r.AddGeometry(g);
      end;
    end;
    { a special area: the region moved into its box }
    if Special <> nil then
    begin
      sa := Special.Find(r.Name);
      if Truthy(sa) then
        r.TransformTo(TyJsonToNumber(Own(sa, 'left')), TyJsonToNumber(Own(sa, 'top')),
          TyJsonToNumber(Own(sa, 'width')), TyJsonToNumber(Own(sa, 'height')));
    end;
  end;

  { calculateBoundingRect: the first region's rect cloned and united with
    itself, then every other }
  hasRect := False;
  rect := TyXYWH(0, 0, 0, 0);
  for i := 0 to High(regions) do
  begin
    if not hasRect then
    begin
      rect := NewRect(regions[i].BoundingRect.X, regions[i].BoundingRect.Y,
        regions[i].BoundingRect.W, regions[i].BoundingRect.H);
      hasRect := True;
    end;
    RectUnion(rect, regions[i].BoundingRect);
  end;

  Result := Length(Parsed);
  SetLength(Parsed, Result + 1);
  Parsed[Result].NameProperty := ANameProperty;
  Parsed[Result].Regions := regions;
  Parsed[Result].Rect := rect;
  Parsed[Result].HasRect := hasRect;
end;

function GeoPtNaN: TTyGeoPt;
begin
  Result.X := NaN;
  Result.Y := NaN;
end;

function TGeoResource.Load(ANameMap: TJSONObject; const ANameProperty: string): TTyGeoSource;
var
  pi, i: Integer;
  r: TTyGeoRegion;
  nm: string;
  d: TJSONData;
  mask: TFpuMask;
begin
  Result := nil;
  { [F6b] an SVG map's regions: its self-named items' names (load ignores
    nameMap and nameProperty) }
  if IsSvg then
  begin
    Result := TTyGeoSource.Create;
    SetLength(Result.FRegions, Length(SvgNames));
    for i := 0 to High(SvgNames) do
      Result.FRegions[i] := TTyGeoRegion.Create(SvgNames[i], nil, False, GeoPtNaN);
    Result.FRect := SvgNamesRect;
    Exit;
  end;
  mask := MaskFpu;
  try
    pi := ParseRegions(ANameProperty);
    if pi < 0 then Exit;
    Result := TTyGeoSource.Create;
    SetLength(Result.FRegions, Length(Parsed[pi].Regions));
    for i := 0 to High(Parsed[pi].Regions) do
    begin
      r := Parsed[pi].Regions[i];
      nm := r.Name;
      { the alias in nameMap, by hasOwn; a null alias keeps the name. A
        region nameMap names is cloneShallow'd, and the clone has no
        properties -- so no echartsStyle either }
      d := nil;
      if ANameMap <> nil then
      begin
        d := ANameMap.Find(nm);
        if (d <> nil) and (d.JSONType <> jtNull) then nm := TyJsonJsString(d);
      end;
      Result.FRegions[i] := r.CloneShallow(nm);
      if d <> nil then Result.FRegions[i].Properties := nil;
    end;
    if Parsed[pi].HasRect then Result.FRect := Parsed[pi].Rect
    else Result.FRect := TyXYWH(0, 0, 0, 0);
  finally
    UnmaskFpu(mask);
  end;
end;

{ ==================== the registry ==================== }

var
  GMaps: array of TGeoResource;
  GProjections: array of record
    Name: string;
    Handler: TTyGeoProjectHandler;
  end;

function IndexOfMap(const AName: string): Integer;
var i: Integer;
begin
  for i := 0 to High(GMaps) do
    if GMaps[i].Name = AName then Exit(i);
  Result := -1;
end;

function ParseText(const AText: string): TJSONData;
var err: TTyOptionError;
begin
  Result := nil;
  if not TyOptionParseRaw(AText, Result, err) then
  begin
    FreeAndNil(Result);
    Exit;
  end;
  { the numbers correctly rounded: TyOptionParseRaw re-reads them
    [Milestone D9-D14] }
end;

procedure PutMap(ARes: TGeoResource);
var i: Integer;
begin
  i := IndexOfMap(ARes.Name);
  if i >= 0 then
  begin
    GMaps[i].Free;
    GMaps[i] := ARes;
  end
  else
  begin
    SetLength(GMaps, Length(GMaps) + 1);
    GMaps[High(GMaps)] := ARes;
  end;
end;

{ [F6b] new GeoSVGResource: parseXML now (it throws on a broken document);
  the graphic waits for a geo }
function RegisterSvgMap(const AName, AText: string): Boolean;
var
  doc: TXMLDocument;
  el: TDOMElement;
  res: TGeoResource;
  g: TTyGsGraphic;
  k, n: Integer;
begin
  Result := False;
  if not TyGsParseDocument(AText, doc, el) then Exit;
  res := TGeoResource.Create;
  res.Name := AName;
  res.Text := AText;
  res.IsSvg := True;
  res.SvgDoc := doc;
  res.SvgEl := el;
  g := TyGsBuild(el, nil, False, Default(TTyXYWH));
  if g.Ok then
  begin
    for k := 0 to High(g.Named) do
      if g.Named[k].From < 0 then
      begin
        n := Length(res.SvgNames);
        SetLength(res.SvgNames, n + 1);
        res.SvgNames[n] := g.Named[k].Name;
      end;
    res.SvgNamesRect := g.Rect;
  end;
  PutMap(res);
  Result := True;
end;

{ the markup itself: '<' first past white space and a byte-order mark }
function LooksLikeMarkup(const AText: string): Boolean;
var i: Integer;
begin
  i := 1;
  if Copy(AText, 1, 3) = #$EF#$BB#$BF then i := 4;
  while (i <= Length(AText)) and (AText[i] in [#9, #10, #13, ' ']) do Inc(i);
  Result := (i <= Length(AText)) and (AText[i] = '<');
end;

function TyChartRegisterMap(const AName, AGeoJson: string;
  const ASpecialAreas: string): Boolean;
var
  root, inner, special: TJSONData;
  res: TGeoResource;
  i: Integer;
  wrapped: TJSONData;
  specialText: string;
begin
  Result := False;
  if LooksLikeMarkup(AGeoJson) then Exit(RegisterSvgMap(AName, AGeoJson));
  root := ParseText(AGeoJson);
  if root = nil then Exit;
  special := nil;
  specialText := ASpecialAreas;
  try
    { [F6b] an SVG map: `rawDef.svg` truthy -- a string here (a JSON text
      cannot hold the Document upstream also takes) }
    if Truthy(Own(root, 'svg')) then
    begin
      if Own(root, 'svg').JSONType = jtString then
        Result := RegisterSvgMap(AName, Own(root, 'svg').AsString);
      Exit;
    end;
    { THE WRAPPER FORM: geoJson or geoJSON, and specialAreas, without features }
    wrapped := Own(root, 'geoJson');
    if not Truthy(wrapped) then wrapped := Own(root, 'geoJSON');
    if Truthy(wrapped) and not Truthy(Own(root, 'features')) then
    begin
      if Own(root, 'specialAreas') <> nil then
        specialText := Own(root, 'specialAreas').AsJSON
      else
        specialText := '';
      if wrapped is TJSONString then
      begin
        inner := ParseText(wrapped.AsString);
        if inner = nil then Exit;
      end
      else
        inner := wrapped.Clone;
      FreeAndNil(root);
      root := inner;
    end;
    if Trim(specialText) <> '' then
    begin
      special := ParseText(specialText);
      if special = nil then Exit;
      if not (special is TJSONObject) then FreeAndNil(special);
    end;
    res := TGeoResource.Create;
    res.Name := AName;
    res.Text := root.AsJSON;
    res.SpecialText := specialText;
    res.Root := root;
    res.Special := TJSONObject(special);
    root := nil;
    special := nil;
    i := IndexOfMap(AName);
    if i >= 0 then
    begin
      GMaps[i].Free;
      GMaps[i] := res;
    end
    else
    begin
      SetLength(GMaps, Length(GMaps) + 1);
      GMaps[High(GMaps)] := res;
    end;
    Result := True;
  finally
    root.Free;
    special.Free;
  end;
end;

function TyChartGetMap(const AName: string; out AGeoJson, ASpecialAreas: string): Boolean;
var i: Integer;
begin
  AGeoJson := '';
  ASpecialAreas := '';
  i := IndexOfMap(AName);
  { [F6b] getMapForUser answers nothing for an SVG map }
  Result := (i >= 0) and not GMaps[i].IsSvg;
  if not Result then Exit;
  AGeoJson := GMaps[i].Text;
  ASpecialAreas := GMaps[i].SpecialText;
end;

function TyChartMapRegistered(const AName: string): Boolean;
begin
  Result := IndexOfMap(AName) >= 0;
end;

function TyGeoMapIsSvg(const AName: string): Boolean;
var i: Integer;
begin
  i := IndexOfMap(AName);
  Result := (i >= 0) and GMaps[i].IsSvg;
end;

{ [F6b] useGraphic: a graphic of the map's document (its first build's
  bounding rect reused) }
function TyGeoSvgBuildFor(const AName: string; const AMeasure: TTyGsMeasure;
  out AG: TTyGsGraphic): Boolean;
var i: Integer;
begin
  AG := Default(TTyGsGraphic);
  i := IndexOfMap(AName);
  if (i < 0) or not GMaps[i].IsSvg then Exit(False);
  AG := TyGsBuild(GMaps[i].SvgEl, AMeasure, GMaps[i].SvgHasRect, GMaps[i].SvgRect);
  Result := AG.Ok;
  if Result and not GMaps[i].SvgHasRect then
  begin
    GMaps[i].SvgHasRect := True;
    GMaps[i].SvgRect := AG.Rect;
  end;
end;

procedure TyChartUnregisterMap(const AName: string);
var i, j: Integer;
begin
  i := IndexOfMap(AName);
  if i < 0 then Exit;
  GMaps[i].Free;
  for j := i to High(GMaps) - 1 do GMaps[j] := GMaps[j + 1];
  SetLength(GMaps, Length(GMaps) - 1);
end;

procedure TyChartClearMaps;
var i: Integer;
begin
  for i := 0 to High(GMaps) do GMaps[i].Free;
  GMaps := nil;
end;

function TyGeoLoadMap(const AName: string; ANameMap: TJSONObject;
  const ANameProperty: string): TTyGeoSource;
var i: Integer; np: string;
begin
  Result := nil;
  i := IndexOfMap(AName);
  if i < 0 then Exit;
  np := ANameProperty;
  if np = '' then np := 'name';
  Result := GMaps[i].Load(ANameMap, np);
end;

{ ---- projections ---- }

function IndexOfProjection(const AName: string): Integer;
var i: Integer;
begin
  for i := 0 to High(GProjections) do
    if SameText(GProjections[i].Name, AName) then Exit(i);
  Result := -1;
end;

procedure TyChartRegisterGeoProjection(const AName: string; AHandler: TTyGeoProjectHandler);
var i: Integer;
begin
  if AName = '' then Exit;
  i := IndexOfProjection(AName);
  if i < 0 then
  begin
    i := Length(GProjections);
    SetLength(GProjections, i + 1);
    GProjections[i].Name := AName;
  end;
  GProjections[i].Handler := AHandler;
end;

procedure TyChartUnregisterGeoProjection(const AName: string);
var i, j: Integer;
begin
  i := IndexOfProjection(AName);
  if i < 0 then Exit;
  for j := i to High(GProjections) - 1 do GProjections[j] := GProjections[j + 1];
  SetLength(GProjections, Length(GProjections) - 1);
end;

function TyChartFindGeoProjection(const ASpec: string; out AHandler: TTyGeoProjectHandler): Boolean;
var i: Integer; nm: string;
begin
  AHandler := nil;
  nm := ASpec;
  if (nm <> '') and (nm[1] = '@') then Delete(nm, 1, 1);
  i := IndexOfProjection(nm);
  Result := (i >= 0) and Assigned(GProjections[i].Handler);
  if Result then AHandler := GProjections[i].Handler;
end;

procedure TyChartClearGeoProjections;
begin
  GProjections := nil;
end;

{ ==================== the options ==================== }

const
  cBoxKey: array[0..5] of string = ('width', 'left', 'right', 'height', 'top', 'bottom');

{ RoamController.enable's controlType: `true` both (a one is not true),
  'move' / 'pan' the drag, 'scale' / 'zoom' the wheel, anything else
  neither [Batch 150] }
function RoamModeOf(AValue: TJSONData): TTyGraphRoamMode;
var s: string;
begin
  Result := grmOff;
  if AValue = nil then Exit;
  case AValue.JSONType of
    jtBoolean: if AValue.AsBoolean then Result := grmBoth;
    jtString:
      begin
        s := AValue.AsString;
        if (s = 'move') or (s = 'pan') then Result := grmPan
        else if (s = 'scale') or (s = 'zoom') then Result := grmZoom;
      end;
  end;
end;

function TyGeoSpecOfNode(ANode, ARoot: TJSONObject; AMapSeries: Boolean): TTyGeoSpec; forward;

function TyGeoSpecOf(AOption: TTyChartOption; AIndex: Integer): TTyGeoSpec;
var d: TJSONData; root: TJSONObject;
begin
  if AOption = nil then Exit(TyGeoSpecOfNode(nil, nil, False));
  d := AOption.ComponentAt('geo', AIndex);
  root := nil;
  if AOption.Root is TJSONObject then root := TJSONObject(AOption.Root);
  if d is TJSONObject then Result := TyGeoSpecOfNode(TJSONObject(d), root, False)
  else Result := TyGeoSpecOfNode(nil, root, False);
end;

{ the options of a geo component's node, or [Batch 152] of a map series'
  (MapSeries' defaults: z 2, its silent the series', no show) }
function TyGeoSpecOfNode(ANode, ARoot: TJSONObject; AMapSeries: Boolean): TTyGeoSpec;
var
  node, root: TJSONObject;
  d, e: TJSONData;
  raw, target: TTyCalBoxKeys;
  k: Integer;
  gs: TTyGraphSpec;
  v: TTyBoxRaw;

  function BoxRawOwn(const AKey: string): TTyCalBoxKey;
  var x: TJSONData;
  begin
    Result := Default(TTyCalBoxKey);
    x := node.Find(AKey);
    if x = nil then Exit;
    Result.Own := True;
    Result.V := TyBoxRawOf(x);
  end;

  function StrOwn(const AKey: string): string;
  var x: TJSONData;
  begin
    Result := '';
    x := node.Find(AKey);
    if x is TJSONString then Result := x.AsString;
  end;

begin
  Result := Default(TTyGeoSpec);
  Result.Show := True;
  Result.HasAspectScale := False;
  Result.AspectScale := NaN;
  Result.Zoom := 1;
  Result.LimitMin := 0;
  Result.LimitMax := Infinity;
  Result.Box.Left := TyBoxRawStr('center');
  Result.Box.Top := TyBoxRawStr('center');
  if AMapSeries then Result.Z := 2;
  if ANode = nil then Exit;
  node := ANode;
  root := ARoot;

  { show: true by default; a written null asks the root. A map series has
    no show: its MapDraw always draws. }
  d := node.Find('show');
  if AMapSeries or (d = nil) then Result.Show := True
  else if d.JSONType = jtNull then Result.Show := Truthy(Climb(nil, root, 'show'))
  else Result.Show := Truthy(d);
  d := node.Find('map');
  if d = nil then Result.MapName := ''
  else Result.MapName := TyJsonJsString(Climb(node, root, 'map'));
  { silent: false by default (merged in, so an absent key never reaches the
    root); a written null asks the root [Batch 148] }
  d := node.Find('silent');
  if d = nil then Result.Silent := False
  else if d.JSONType = jtNull then Result.Silent := Truthy(Climb(nil, root, 'silent'))
  else Result.Silent := Truthy(d);
  { getShallow('clip', true): its own }
  Result.Clip := Truthy(node.Find('clip'));
  d := Climb(node, root, 'z');
  if AMapSeries then
  begin
    { the series' z, MapSeries' 2 by default }
    d := node.Find('z');
    if (d <> nil) and (d.JSONType = jtNumber) and JsFinite(d.AsFloat) then Result.Z := Trunc(d.AsFloat)
    else Result.Z := 2;
  end
  else if (d = nil) or JsFalsy(TyJsonToNumber(d)) then Result.Z := 0
  else Result.Z := Trunc(TyJsonToNumber(d));
  d := Climb(node, root, 'zlevel');
  if (d = nil) or JsFalsy(TyJsonToNumber(d)) then Result.ZLevel := 0
  else Result.ZLevel := Trunc(TyJsonToNumber(d));

  { ---- the box: the defaults, then mergeLayoutParam on what was written ---- }
  for k := 0 to 5 do raw[k] := BoxRawOwn(cBoxKey[k]);
  target := raw;
  if not target[1].Own then
  begin
    target[1].Own := True;
    target[1].V := TyBoxRawStr('center');
  end;
  if not target[4].Own then
  begin
    target[4].Own := True;
    target[4].V := TyBoxRawStr('center');
  end;
  TyCalMergeLayoutParam(target, raw, False, False);
  for k := 0 to 5 do
  begin
    if target[k].Own then v := target[k].V else v := Default(TTyBoxRaw);
    { getShallow: a null or an undefined climbs to the root }
    if (v.Kind = brAbsent) or (v.Kind = brNull) then
      v := TyBoxRawOf(Climb(nil, root, cBoxKey[k]));
    case k of
      0: Result.Box.Width := v;
      1: Result.Box.Left := v;
      2: Result.Box.Right := v;
      3: Result.Box.Height := v;
      4: Result.Box.Top := v;
      5: Result.Box.Bottom := v;
    end;
  end;
  { getShallow(key, true): the geo's own }
  d := node.Find('preserveAspect');
  if Truthy(d) then
  begin
    if (d.JSONType = jtString) and (d.AsString = 'cover') then Result.PreserveAspect := gpaCover
    else Result.PreserveAspect := gpaContain;
  end;
  Result.PreserveAlign := StrOwn('preserveAspectAlign');
  Result.PreserveVAlign := StrOwn('preserveAspectVerticalAlign');

  { aspectScale: retrieve2(option, 0.75) }
  d := Climb(node, root, 'aspectScale');
  if d <> nil then
  begin
    Result.HasAspectScale := True;
    Result.AspectScale := TyJsonToNumber(d);
  end;
  { layoutCenter + layoutSize, both truthy }
  d := Climb(node, root, 'layoutCenter');
  Result.HasLayoutCenter := Truthy(d);
  if Result.HasLayoutCenter then
  begin
    Result.LayoutCenter[0] := TyBoxRawOf(Item(d, 0));
    Result.LayoutCenter[1] := TyBoxRawOf(Item(d, 1));
  end;
  d := Climb(node, root, 'layoutSize');
  Result.HasLayoutSize := Truthy(d);
  if Result.HasLayoutSize then Result.LayoutSize := TyBoxRawOf(d);
  { boundingCoords }
  d := Climb(node, root, 'boundingCoords');
  Result.HasBoundingCoords := d <> nil;
  if Result.HasBoundingCoords then
  begin
    e := Item(d, 0);
    Result.BCX0 := TyJsonToNumber(Item(e, 0));
    Result.BCY0 := TyJsonToNumber(Item(e, 1));
    e := Item(d, 1);
    Result.BCX1 := TyJsonToNumber(Item(e, 0));
    Result.BCY1 := TyJsonToNumber(Item(e, 1));
    Result.BoundingCoordsOk := JsFinite(Result.BCX0) and JsFinite(Result.BCY0)
      and JsFinite(Result.BCX1) and JsFinite(Result.BCY1);
  end;
  { nameProperty: `nameProperty || 'name'` }
  d := Climb(node, root, 'nameProperty');
  if Truthy(d) then Result.NameProperty := TyJsonJsString(d)
  else Result.NameProperty := 'name';
  { projection: the two handlers by name }
  d := Climb(node, root, 'projection');
  Result.HasProjection := Truthy(d);
  if Result.HasProjection then
  begin
    e := Own(d, 'project');
    if e is TJSONString then Result.ProjectName := e.AsString;
    e := Own(d, 'unproject');
    if e is TJSONString then Result.UnprojectName := e.AsString;
  end;
  { center / zoom / scaleLimit, read as the graph's view reads them }
  gs := TyGraphSpecDefault;
  TyGraphReadRoamOptions(node, root, gs);
  Result.Centre := gs.Centre;
  Result.Zoom := gs.Zoom;
  Result.HasLimit := gs.HasLimit;
  Result.LimitMin := gs.LimitMin;
  Result.LimitMax := gs.LimitMax;
  { [Batch 150] roam: the geo's own unless null or absent, then the root's;
    roamTypeDefault false (updateRoamControllerSimply), so nothing at all
    is off -- the graph's null-is-true does not apply }
  d := node.Find('roam');
  if (d = nil) or (d.JSONType = jtNull) then d := Climb(nil, root, 'roam');
  Result.Roam := RoamModeOf(d);
  Result.RoamGlobal := gs.RoamGlobal;
end;

{ ==================== the geo ==================== }

const
  cRootStyleKeys: array[0..4] of string = ('itemStyle', 'label', 'emphasis',
    'select', 'blur');

constructor TTyGeo.Create(AOption: TTyChartOption; AIndex: Integer);
var d: TJSONData; root: TJSONObject; k: Integer;
begin
  inherited Create;
  FIndex := AIndex;
  FSvgPointer := -1;
  FSpec := TyGeoSpecOf(AOption, AIndex);
  FNode := nil;
  FNameMap := nil;
  if AOption <> nil then
  begin
    d := AOption.ComponentAt('geo', AIndex);
    if d is TJSONObject then FNode := TJSONObject(d.Clone);
    FChainNode := FNode;
    root := nil;
    if AOption.Root is TJSONObject then root := TJSONObject(AOption.Root);
    d := Climb(FNode, root, 'nameMap');
    if d is TJSONObject then FNameMap := TJSONObject(d.Clone);
  end;
  { [Batch 148] the root keys a region model's chain reaches }
  FRoot := TJSONObject.Create;
  if (AOption <> nil) and (AOption.Root is TJSONObject) then
    for k := 0 to High(cRootStyleKeys) do
    begin
      d := TJSONObject(AOption.Root).Find(cRootStyleKeys[k]);
      if d <> nil then FRoot.Add(cRootStyleKeys[k], d.Clone);
    end;
  FMtRaw := MatIdentity;
  FMtRawInv := MatIdentity;
  FMtOverall := MatIdentity;
  FMtOverallInv := MatIdentity;
  FZoom := 1;
  FScale := 1;
end;

constructor TTyGeo.CreateForMap(AOption: TTyChartOption; ALayoutSeries, AIndex: Integer;
  ANameMap: TJSONObject);
var d: TJSONData; root: TJSONObject; k: Integer;
begin
  inherited Create;
  FKind := gkMapSeries;
  FIndex := AIndex;
  FSvgPointer := -1;
  FNode := nil;
  FNameMap := nil;
  root := nil;
  if (AOption <> nil) and (AOption.Root is TJSONObject) then root := TJSONObject(AOption.Root);
  d := nil;
  if AOption <> nil then d := AOption.ComponentAt('series', ALayoutSeries);
  if d is TJSONObject then
  begin
    FNode := TJSONObject(d.Clone);
    FSpec := TyGeoSpecOfNode(FNode, root, True);
  end
  else
    FSpec := TyGeoSpecOfNode(nil, root, True);
  FChainNode := FNode;
  if ANameMap <> nil then FNameMap := TJSONObject(ANameMap.Clone);
  FRoot := TJSONObject.Create;
  if root <> nil then
    for k := 0 to High(cRootStyleKeys) do
    begin
      d := root.Find(cRootStyleKeys[k]);
      if d <> nil then FRoot.Add(cRootStyleKeys[k], d.Clone);
    end;
  FMtRaw := MatIdentity;
  FMtRawInv := MatIdentity;
  FMtOverall := MatIdentity;
  FMtOverallInv := MatIdentity;
  FZoom := 1;
  FScale := 1;
end;

procedure FreeDataOpts(var AData: TTyGeoData);
var i: Integer;
begin
  for i := 0 to High(AData.Groups) do FreeAndNil(AData.Groups[i].Opt);
end;

procedure TTyGeo.SetData(const AData: TTyGeoData; AChainNode: TJSONObject);
var i: Integer;
begin
  FreeDataOpts(FSeriesData);
  if (FChainNode <> nil) and (FChainNode <> FNode) then FreeAndNil(FChainNode);
  FSeriesData := AData;
  SetLength(FSeriesData.Groups, Length(AData.Groups));
  for i := 0 to High(FSeriesData.Groups) do
    if AData.Groups[i].Opt <> nil then
      FSeriesData.Groups[i].Opt := TJSONObject(AData.Groups[i].Opt.Clone);
  if AChainNode <> nil then FChainNode := TJSONObject(AChainNode.Clone)
  else FChainNode := FNode;
  { the picture is the data's: again, the flags kept }
  FDrawOk := False;
  FItemsOk := False;
end;

function TTyGeo.SetFlags(AGroup, AHover: Integer; AHbo: Cardinal; ASelected: Boolean): Boolean;
var k, last, h: Integer; onName: Boolean;
begin
  Result := False;
  EnsureGroups;
  if (AGroup < 0) or (AGroup > High(FSt)) then Exit;
  if FIsSvg then
  begin
    { [F6b] a map series' row flags on the self-named elements of the name.
      [R2-B] EACH IS A DISPATCHER OF THE ITEM (resetEventTriggerForRegion; a
      series has no high-down by name): a blur reaches them all, the pointer
      lifts the one it is over, and an action -- getItemGraphicEl -- the last
      one registered, which alone holds its bits. [Was: every element of the
      name took the row's flags.] }
    FSvgChanged := FSt[AGroup].Selected <> ASelected;
    FSt[AGroup].Selected := ASelected;
    FSt[AGroup].Hover := AHover;
    FSt[AGroup].Hbo := AHbo;
    if Length(FSvgEl) > 0 then
    begin
      last := -1;
      for k := 0 to High(FSvgSelf) do
        if (FSvgSelf[k] >= 0) and (FSvgEvent[k] = AGroup) then last := k;
      onName := (FSvgPointer >= 0) and (FSvgPointer <= High(FSvgEvent))
        and (FSvgEvent[FSvgPointer] = AGroup);
      for k := 0 to High(FSvgSelf) do
        if (FSvgSelf[k] >= 0) and (FSvgEvent[k] = AGroup) then
        begin
          h := AHover;
          if h = TyStHoverEmphasis then
          begin
            { the pointer's own; the held one; with neither known, all }
            if onName then
            begin
              if not ((k = FSvgPointer) or ((AHbo <> 0) and (k = last))) then
                h := TyStHoverNormal;
            end
            else if (AHbo <> 0) and (k <> last) then
              h := TyStHoverNormal;
          end;
          if k = last then FSvgHbo[k] := AHbo else FSvgHbo[k] := 0;
          SvgTraverse(k, cSvgSetHover, h);
        end;
    end;
    Exit(FSvgChanged);
  end;
  Result := (FSt[AGroup].Hover <> AHover) or (FSt[AGroup].Hbo <> AHbo)
    or (FSt[AGroup].Selected <> ASelected);
  FSt[AGroup].Hover := AHover;
  FSt[AGroup].Hbo := AHbo;
  FSt[AGroup].Selected := ASelected;
end;

destructor TTyGeo.Destroy;
var i: Integer;
begin
  FreeDataOpts(FSeriesData);
  if (FChainNode <> nil) and (FChainNode <> FNode) then FChainNode.Free;
  for i := 0 to High(FOpts) do FOpts[i].Free;
  FRoot.Free;
  FSource.Free;
  FNode.Free;
  FNameMap.Free;
  inherited Destroy;
end;

procedure TTyGeo.SetBoundingRect(AX, AY, AW, AH: Double);
begin
  FData := NewRect(AX, AY, AW, AH);
  FHasData := True;
  if FHasView then UpdateTransform;
end;

procedure TTyGeo.SetViewRect(AX, AY, AW, AH: Double);
begin
  FView := NewRect(AX, AY, AW, AH);
  FHasView := True;
  if FHasData then UpdateTransform;
end;

{ parsePercent(c, base, offset): `(offset || 0)` }
function CentreHalf(const APos: TTyGraphPos; ABase, AOffset: Double): Double;
begin
  if JsFalsy(AOffset) then AOffset := 0;
  case APos.Kind of
    gpkPx: Result := APos.V;
    gpkPct: Result := APos.V / 100 * ABase + AOffset;
  else
    Result := NaN;
  end;
end;

procedure TTyGeo.UpdateTransform;
var
  d: TTyXYWH;
  m: TTyMat2D;
  vcx, vcy, rcx, rcy, px, py: Double;
  q: TTyGeoPt;
  inv: TTyMat2D;
begin
  { RAW: the data rect (y flipped) fitted to the view rect, decomposed, the
    y scale negated }
  d := FData;
  if FInvertY then d.Y := -d.Y - d.H;
  m := CalcTransform(d, FView);
  FRaw := TyGeoDecompose(m);
  if FInvertY then FRaw.ScaleY := -FRaw.ScaleY;
  FMtRaw := TyGeoLocalTransform(FRaw);
  if TyGeoMatInvert(FMtRaw, inv) then FMtRawInv := inv;
  { ROAM: the centre through the raw matrix, moved to the view's centre and
    scaled about it }
  vcx := FView.X + FView.W / 2;
  vcy := FView.Y + FView.H / 2;
  rcx := vcx;
  rcy := vcy;
  if FHasCentre then
  begin
    px := CentreHalf(FCentre.X, FData.W, FData.X);
    py := CentreHalf(FCentre.Y, FData.H, FData.Y);
    q := TyGeoApply(FMtRaw, px, py);
    rcx := q.X;
    rcy := q.Y;
  end;
  FRoam := TransOf(vcx - FZoom * rcx, vcy - FZoom * rcy, FZoom);
  { OVERALL = decompose(roam x raw) }
  m := TyGeoMatMul(TyGeoLocalTransform(FRoam), TyGeoLocalTransform(FRaw));
  FOverall := TyGeoDecompose(m);
  FMtOverall := TyGeoLocalTransform(FOverall);
  if TyGeoMatInvert(FMtOverall, inv) then FMtOverallInv := inv;
end;

procedure TTyGeo.SetRoamOption(const ACentre: TTyGraphCentre; AZoom: Double);
begin
  FSpec.Centre := ACentre;
  FSpec.Zoom := AZoom;
end;

{ View.ts: viewCoordSysSyncBack, applyRoamPayloadToOverallTrans,
  calcRoamTransFromOverallTrans, syncBackToRoamOptionFromRoamTrans,
  invertBackToCenterOption -- then viewCoordSysSetRoamOptionFromModel }
function TTyGeo.RoamBy(AHasPan: Boolean; ADX, ADY: Double; AHasZoom: Boolean;
  AScale, AOriginX, AOriginY: Double; out ACentre: TTyGraphCentre;
  out AZoom: Double): Boolean;
const
  { typed: the comparison is against the Double upstream writes }
  cZoomEps: Double = 1e-6;
var
  t1, t2: TTyGeoTrans;
  oldZ, newZ, k, z, vcx, vcy, cx, cy: Double;
  c: TTyGeoPt;
  mask: TFpuMask;

  { invertToPercentPerCenterDim: a half last written as a percentage
    string goes back as one (of the data rect, offset by its corner) when
    the rect has a size that way; anything else as the number }
  procedure Half(APct: Boolean; AV, AOff, AW: Double; out APos: TTyGraphPos;
    out AIsPct: Boolean);
  begin
    AIsPct := FSpec.Centre.Has and APct and not JsFalsy(AW);
    if AIsPct then
    begin
      APos.Kind := gpkPct;
      APos.V := (AV - AOff) / AW * 100;
    end
    else
    begin
      APos.Kind := gpkPx;
      APos.V := AV;
    end;
  end;

begin
  Result := False;
  ACentre := FSpec.Centre;
  AZoom := FSpec.Zoom;
  if not (FValid and FHasData and FHasView) then Exit;
  mask := MaskFpu;
  try
    { the transform group holds a copy of the roam: the overall from it
      (calcOverallTransFromSyncBackEl), then the roam back out of it }
    t1 := TyGeoDecompose(TyGeoMatMul(TyGeoLocalTransform(FRoam), TyGeoLocalTransform(FRaw)));
    t2 := TyGeoDecompose(TyGeoMatMul(TyGeoLocalTransform(t1), FMtRawInv));
    { the payload, on the overall: dx and dy in pixels }
    if AHasPan then
    begin
      t1.X := t1.X + ADX;
      t1.Y := t1.Y + ADY;
    end;
    if AHasZoom then
    begin
      oldZ := t2.ScaleX;
      newZ := oldZ * AScale;
      if FHasLimit then newZ := JsMax(JsMin(FLimitMax, newZ), FLimitMin);
      k := newZ / oldZ;
      { keep the point under the pointer }
      t1.X := t1.X - (AOriginX - t1.X) * (k - 1);
      t1.Y := t1.Y - (AOriginY - t1.Y) * (k - 1);
      t1.ScaleX := t1.ScaleX * k;
      t1.ScaleY := t1.ScaleY * k;
    end;
    t1 := TyGeoDecompose(TyGeoMatMul(TyGeoLocalTransform(t1), FMtRawInv));
    { the inverse of setting the roam from the option }
    vcx := FView.X + FView.W / 2;
    vcy := FView.Y + FView.H / 2;
    z := t1.ScaleX;
    if Abs(z) > cZoomEps then
    begin
      cx := (vcx - t1.X) / z;
      cy := (vcy - t1.Y) / z;
    end
    else
    begin
      cx := vcx;
      cy := vcy;
    end;
    c := TyGeoApply(FMtRawInv, cx, cy);
    ACentre := Default(TTyGraphCentre);
    ACentre.Has := True;
    Half(FSpec.Centre.PctX, c.X, FData.X, FData.W, ACentre.X, ACentre.PctX);
    Half(FSpec.Centre.PctY, c.Y, FData.Y, FData.H, ACentre.Y, ACentre.PctY);
    AZoom := z;
    { written back, then read again (the zoom clamped on the way in) }
    FSpec.Centre := ACentre;
    FSpec.Zoom := AZoom;
    ApplyRoamOptions;
    Inc(FRoamGen);
    Result := True;
  finally
    UnmaskFpu(mask);
  end;
end;

function TTyGeo.ItemsReady: Boolean;
begin
  Result := FDrawOk and FItemsOk;
end;

function TTyGeo.OverallRect: TTyXYWH;
var mask: TFpuMask;
begin
  mask := MaskFpu;
  try
    Result := RectApply(FData, FMtOverall);
  finally
    UnmaskFpu(mask);
  end;
end;

function TTyGeo.RoamViewRect: TTyXYWH;
var mask: TFpuMask;
begin
  mask := MaskFpu;
  try
    Result := RectApply(FView, RoamMatrix);
  finally
    UnmaskFpu(mask);
  end;
end;

function TTyGeo.RoamPointerIn(AX, AY: Double): Boolean;
begin
  Result := False;
  if not (FValid and FHasData and FHasView) then Exit;
  { roamTrigger 'global', else isInSelf: containPoint }
  Result := FSpec.RoamGlobal or ContainPoint(TyPointF(AX, AY));
  { isInClip: the view rect, its edges in }
  if Result and FSpec.Clip then Result := RectContain(FView, AX, AY);
end;

procedure TTyGeo.ApplyRoamOptions;
var z: Double;
begin
  FCentre := FSpec.Centre;
  FHasCentre := FSpec.Centre.Has;
  FHasLimit := FSpec.HasLimit;
  FLimitMin := FSpec.LimitMin;
  FLimitMax := FSpec.LimitMax;
  { `clampByZoomLimit(zoom || 1, limit) || 1` }
  z := FSpec.Zoom;
  if JsFalsy(z) then z := 1;
  if FHasLimit then z := JsMax(JsMin(FLimitMax, z), FLimitMin);
  if JsFalsy(z) then z := 1;
  FZoom := z;
  if FHasData and FHasView then UpdateTransform;
end;

{ getLayoutRect with an aspect and no margin }
function GeoLayoutRect(const ABox: TTyRawBox; ACX, ACY, ACW, ACH: Double;
  AHasAspect: Boolean; AAspect: Double): TTyXYWH;
var left, top, right, bottom, w, h: Double; wordH, wordV: string;
begin
  left := TyBoxRawResolve(ABox.Left, ACW);
  top := TyBoxRawResolve(ABox.Top, ACH);
  right := TyBoxRawResolve(ABox.Right, ACW);
  bottom := TyBoxRawResolve(ABox.Bottom, ACH);
  w := TyBoxRawResolve(ABox.Width, ACW);
  h := TyBoxRawResolve(ABox.Height, ACH);
  if IsNan(w) then w := ACW - right - 0 - left;
  if IsNan(h) then h := ACH - bottom - 0 - top;
  if AHasAspect then
  begin
    if IsNan(w) and IsNan(h) then
    begin
      if AAspect > ACW / ACH then w := ACW * 0.8
      else h := ACH * 0.8;
    end;
    if IsNan(w) then w := AAspect * h;
    if IsNan(h) then h := w / AAspect;
  end;
  if IsNan(left) then left := ACW - right - w - 0;
  if IsNan(top) then top := ACH - bottom - h - 0;
  wordH := TyBoxWord(ABox.Left, ABox.Right);
  if wordH = 'center' then left := ACW / 2 - w / 2 - 0
  else if wordH = 'right' then left := ACW - w - 0;
  wordV := TyBoxWord(ABox.Top, ABox.Bottom);
  if (wordV = 'middle') or (wordV = 'center') then top := ACH / 2 - h / 2 - 0
  else if wordV = 'bottom' then top := ACH - h - 0;
  if JsFalsy(left) then left := 0;
  if JsFalsy(top) then top := 0;
  if IsNan(w) then
  begin
    if JsFalsy(right) then w := ACW - 0 - left - 0 else w := ACW - 0 - left - right;
  end;
  if IsNan(h) then
  begin
    if JsFalsy(bottom) then h := ACH - 0 - top - 0 else h := ACH - 0 - top - bottom;
  end;
  if JsFalsy(ACX) then ACX := 0;
  if JsFalsy(ACY) then ACY := 0;
  Result := NewRect(ACX + left + 0, ACY + top + 0, w, h);
end;

procedure TTyGeo.LayoutView(const AContainer: TTyXYWH);
var
  cw, ch, aspect, size, c0, c1, actual: Double;
  rect, view: TTyXYWH;
  useCS: Boolean;
  box, inner: TTyRawBox;
  wide, cover: Boolean;

  function Scaled(const R: TTyBoxRaw): TTyBoxRaw;
  begin
    Result := R;
    if (R.Kind = brNumber) or (R.Kind = brBool) then Result.Num := R.Num * FScale;
  end;

begin
  cw := AContainer.W;
  ch := AContainer.H;
  rect := FData;
  aspect := rect.W / rect.H * FAspectScale;
  useCS := False;
  size := NaN;
  c0 := NaN;
  c1 := NaN;
  if FSpec.HasLayoutCenter and FSpec.HasLayoutSize then
  begin
    c0 := TyBoxRawResolve(Scaled(FSpec.LayoutCenter[0]), cw) + AContainer.X;
    c1 := TyBoxRawResolve(Scaled(FSpec.LayoutCenter[1]), ch) + AContainer.Y;
    size := TyBoxRawResolve(Scaled(FSpec.LayoutSize), JsMin(cw, ch));
    useCS := not (IsNan(c0) or IsNan(c1) or IsNan(size));
  end;
  if useCS then
  begin
    if aspect > 1 then
    begin
      view.W := size;
      view.H := size / aspect;
    end
    else
    begin
      view.H := size;
      view.W := size * aspect;
    end;
    view.Y := c1 - view.H / 2;
    view.X := c0 - view.W / 2;
  end
  else
  begin
    box := FSpec.Box;
    box.Left := Scaled(box.Left);
    box.Right := Scaled(box.Right);
    box.Top := Scaled(box.Top);
    box.Bottom := Scaled(box.Bottom);
    box.Width := Scaled(box.Width);
    box.Height := Scaled(box.Height);
    view := GeoLayoutRect(box, AContainer.X, AContainer.Y, cw, ch, True, aspect);
    { applyPreserveAspect }
    if FSpec.PreserveAspect <> gpaOff then
    begin
      actual := view.W / view.H;
      if not (Abs(TyJsAtan(aspect) - TyJsAtan(actual)) < 1e-9) then
      begin
        inner := Default(TTyRawBox);
        inner.Width := TyBoxRawNum(view.W);
        inner.Height := TyBoxRawNum(view.H);
        cover := FSpec.PreserveAspect = gpaCover;
        wide := ((actual > aspect) and not cover) or ((actual < aspect) and cover);
        if wide then
        begin
          inner.Width := TyBoxRawNum(view.H * aspect);
          if FSpec.PreserveAlign = 'left' then inner.Left := TyBoxRawNum(0)
          else if FSpec.PreserveAlign = 'right' then inner.Right := TyBoxRawNum(0)
          else inner.Left := TyBoxRawStr('center');
        end
        else
        begin
          inner.Height := TyBoxRawNum(view.W / aspect);
          if FSpec.PreserveVAlign = 'top' then inner.Top := TyBoxRawNum(0)
          else if FSpec.PreserveVAlign = 'bottom' then inner.Bottom := TyBoxRawNum(0)
          else inner.Top := TyBoxRawStr('middle');
        end;
        view := GeoLayoutRect(inner, view.X, view.Y, view.W, view.H, False, NaN);
      end;
    end;
  end;
  SetViewRect(view.X, view.Y, view.W, view.H);
  ApplyRoamOptions;
end;

procedure TTyGeo.Resize(const AContainer: TTyRectF; APPI: Integer);
begin
  ResizeXYWH(TyXYWH(AContainer.Left, AContainer.Top,
    AContainer.Right - AContainer.Left, AContainer.Bottom - AContainer.Top), APPI);
end;

procedure TTyGeo.ResizeXYWH(const ARef: TTyXYWH; APPI: Integer);
var
  i: Integer;
  cont: TTyXYWH;
  r, bound: TTyXYWH;
  hasBound: Boolean;
  lt0, lt1, rb0, rb1, x0, y0, x1, y1: Double;
  mask: TFpuMask;

  procedure SampleLine(AX0, AY0, AX1, AY1: Double);
  var j: Integer; p, dx, dy, x, y: Double;
  begin
    dx := AX1 - AX0;
    dy := AY1 - AY0;
    for j := 0 to 100 do
    begin
      p := j / 100;
      x := AX0 + dx * p;
      y := AY0 + dy * p;
      { a point the projection drops cannot be min'd (upstream throws) }
      if not FProjection.Project(x, y, x, y) then Continue;
      lt0 := JsMin(lt0, x);
      lt1 := JsMin(lt1, y);
      rb0 := JsMax(rb0, x);
      rb1 := JsMax(rb1, y);
    end;
  end;

begin
  FValid := False;
  { [Batch 148] what was worked out of the last map goes with it }
  for i := 0 to High(FOpts) do FOpts[i].Free;
  FOpts := nil;
  FOptNames := nil;
  FGroupNames := nil;
  FGroupsOk := False;
  FDrawOk := False;
  FItemsOk := False;
  FSt := nil;
  FIsBlured := False;
  FreeAndNil(FSource);
  FIsSvg := False;
  FSvg := Default(TTyGsGraphic);
  FSvgEl := nil;
  FSvgLbl := nil;
  FSvgGlobal := nil;
  FSvgHasGlobal := nil;
  FHasData := False;
  FHasView := False;
  FMtRaw := MatIdentity;
  FMtRawInv := MatIdentity;
  FMtOverall := MatIdentity;
  FMtOverallInv := MatIdentity;
  FZoom := 1;
  FHasCentre := False;
  FHasLimit := False;
  if APPI > 0 then FScale := APPI / 96 else FScale := 1;
  mask := MaskFpu;
  try
    FProjection := Default(TTyGeoProjection);
    if TyGeoMapIsSvg(FSpec.MapName) then
    begin
      { [F6b] GeoSVGResource: this geo's graphic, its regions the
        self-named items; no y flip; a projection written on an SVG map is
        dropped and then read off null -- setOption throws }
      FIsSvg := True;
      if not TyGeoSvgBuildFor(FSpec.MapName, FSvgMeasure, FSvg) then Exit;
      FSource := TTyGeoSource.Create;
      FSvgRegionNode := nil;
      for i := 0 to High(FSvg.Named) do
        if FSvg.Named[i].From < 0 then
        begin
          SetLength(FSource.FRegions, Length(FSource.FRegions) + 1);
          FSource.FRegions[High(FSource.FRegions)] :=
            TTyGeoRegion.Create(FSvg.Named[i].Name, nil, False, GeoPtNaN);
          SetLength(FSvgRegionNode, Length(FSvgRegionNode) + 1);
          FSvgRegionNode[High(FSvgRegionNode)] := FSvg.Named[i].Node;
        end;
      FSource.FRect := FSvg.Rect;
      if FSpec.HasProjection then Exit;
      FInvertY := False;
    end
    else
    begin
      FSource := TyGeoLoadMap(FSpec.MapName, FNameMap, FSpec.NameProperty);
      if FSource = nil then Exit;
      { a projection when both handlers are there (the dev build drops one
        without unproject) }
      if FSpec.HasProjection
        and TyChartFindGeoProjection(FSpec.ProjectName, FProjection.Project)
        and TyChartFindGeoProjection(FSpec.UnprojectName, FProjection.Unproject) then
        FProjection.Active := True
      else
      begin
        FProjection.Project := nil;
        FProjection.Unproject := nil;
      end;
      { invertLongitute is decided on the option's projection BEFORE the
        check that drops one without both functions: a dropped projection
        still leaves y the right way up }
      FInvertY := not FSpec.HasProjection;
    end;
    { the rect: the map's, or the union of the projected regions' }
    if FProjection.Active then
    begin
      hasBound := False;
      bound := TyXYWH(0, 0, 0, 0);
      for i := 0 to High(FSource.Regions) do
      begin
        r := FSource.Regions[i].ProjectedRect(FProjection);
        if not hasBound then
        begin
          bound := NewRect(r.X, r.Y, r.W, r.H);
          hasBound := True;
        end;
        RectUnion(bound, r);
      end;
    end
    else
      bound := FSource.Rect;
    SetBoundingRect(bound.X, bound.Y, bound.W, bound.H);
    if FProjection.Active then FAspectScale := 1
    else if FSpec.HasAspectScale then FAspectScale := FSpec.AspectScale
    else if FIsSvg then FAspectScale := 1
    else FAspectScale := TyGeoDefaultAspectScale;
    { boundingCoords: sampled through a projection -- the left edge as the
      diagonal upstream walks }
    if FSpec.HasBoundingCoords and FSpec.BoundingCoordsOk then
    begin
      lt0 := FSpec.BCX0;
      lt1 := FSpec.BCY0;
      rb0 := FSpec.BCX1;
      rb1 := FSpec.BCY1;
      if FProjection.Active then
      begin
        x0 := lt0; y0 := lt1; x1 := rb0; y1 := rb1;
        lt0 := Infinity; lt1 := Infinity;
        rb0 := -Infinity; rb1 := -Infinity;
        SampleLine(x0, y0, x1, y0);
        SampleLine(x1, y0, x1, y1);
        SampleLine(x1, y1, x0, y1);
        SampleLine(x0, y1, x1, y0);
      end;
      SetBoundingRect(lt0, lt1, rb0 - lt0, rb1 - lt1);
    end;
    { A CELL OF NO HEIGHT: out of sight [Batch 154] -- upstream's resizeGeo
      throws on one (no roam transform is ever made). A cell of no WIDTH (a
      coord naming a row and no column) is laid out as upstream lays it out:
      getLayoutRect's `|| 0` for the x, the width from the height through the
      aspect. [D9-D14 mutation round: it was put out of sight too, while
      upstream draws it and converts through it.] }
    cont := ARef;
    if IsNan(cont.H) or (cont.H < 0) then
      cont := TyXYWH(TyBoxNowhere, TyBoxNowhere, TyBoxNowhereSize, TyBoxNowhereSize);
    LayoutView(cont);
    FValid := True;
    if FIsSvg then SvgSetup;
  finally
    UnmaskFpu(mask);
  end;
end;

function TTyGeo.RegionByName(const AName: string): TTyGeoRegion;
begin
  Result := nil;
  if FSource <> nil then Result := FSource.RegionByName(AName);
end;

function TTyGeo.GeoCoord(const AName: string; out APt: TTyGeoPt): Boolean;
var r: TTyGeoRegion;
begin
  APt.X := NaN;
  APt.Y := NaN;
  r := RegionByName(AName);
  Result := r <> nil;
  if Result then APt := r.GetCenter;
end;

function TTyGeo.PointOf(AX, AY: Double; out APx: TTyPointF; ANoRoam: Boolean): Boolean;
var q: TTyGeoPt; mask: TFpuMask;
begin
  APx := TyPointF(NaN, NaN);
  Result := False;
  if not FValid then Exit;
  mask := MaskFpu;
  try
    if FProjection.Active then
      if not FProjection.Project(AX, AY, AX, AY) then Exit;
    if ANoRoam then q := TyGeoApply(FMtRaw, AX, AY)
    else q := TyGeoApply(FMtOverall, AX, AY);
    APx := TyPointF(q.X, q.Y);
    Result := True;
  finally
    UnmaskFpu(mask);
  end;
end;

function TTyGeo.PointOfName(const AName: string; out APx: TTyPointF): Boolean;
var c: TTyGeoPt;
begin
  APx := TyPointF(NaN, NaN);
  Result := False;
  if not FValid then Exit;
  if not GeoCoord(AName, c) then Exit;
  Result := PointOf(c.X, c.Y, APx);
end;

function TTyGeo.DataOf(AX, AY: Double; out AData: TTyGeoPt): Boolean;
var mask: TFpuMask;
begin
  AData.X := NaN;
  AData.Y := NaN;
  Result := False;
  if not FValid then Exit;
  mask := MaskFpu;
  try
    if FProjection.Active then
      if not FProjection.Unproject(AX, AY, AX, AY) then Exit;
    AData := TyGeoApply(FMtOverallInv, AX, AY);
    Result := True;
  finally
    UnmaskFpu(mask);
  end;
end;

function TTyGeo.ToPixelJson(AValue: TJSONData; out APx: TTyPointF): Boolean;
begin
  APx := TyPointF(NaN, NaN);
  Result := False;
  if not FValid or (AValue = nil) then Exit;
  { a string is a region's name }
  if AValue.JSONType = jtString then Exit(PointOfName(AValue.AsString, APx));
  { `if (data)`: a falsy value answers nothing }
  if not Truthy(AValue) then Exit;
  Result := PointOf(TyJsonToNumber(Item(AValue, 0)), TyJsonToNumber(Item(AValue, 1)), APx);
end;

function TTyGeo.FromPixelJson(AValue: TJSONData; out AData: TTyGeoPt): Boolean;
begin
  AData.X := NaN;
  AData.Y := NaN;
  Result := False;
  if not FValid or (AValue = nil) then Exit;
  Result := DataOf(TyJsonToNumber(Item(AValue, 0)), TyJsonToNumber(Item(AValue, 1)), AData);
end;

function TTyGeo.CoordSysName: string;
begin
  Result := TyGeoCoordSysName;
end;

function TTyGeo.DimCount: Integer;
begin
  Result := 2;
end;

function TTyGeo.GetRect: TTyRectF;
begin
  if not FHasView then Exit(TyInvalidRectF);
  Result := TyRectOfXYWH(FView);
end;

function TTyGeo.DataToPoint(const AData: array of Double): TTyPointF;
begin
  Result := TyPointF(NaN, NaN);
  if Length(AData) < 2 then Exit;
  PointOf(AData[0], AData[1], Result);
end;

function TTyGeo.DataToLayout(const AData: array of Double): TTyCoordLayout;
var p: TTyPointF;
begin
  Result.Rect := TyInvalidRectF;
  Result.ContentRect := TyInvalidRectF;
  p := DataToPoint(AData);
  if IsNan(p.X) or IsNan(p.Y) then Exit;
  { Geo has no dataToLayout: a point has no cell }
  Result.Rect := TyRectF(p.X, p.Y, p.X, p.Y);
  Result.ContentRect := Result.Rect;
end;

function TTyGeo.PointToData(const APoint: TTyPointF; out AData: TTyDoubleArray): Boolean;
var q: TTyGeoPt;
begin
  AData := nil;
  Result := DataOf(APoint.X, APoint.Y, q);
  if not Result then Exit;
  SetLength(AData, 2);
  AData[0] := q.X;
  AData[1] := q.Y;
end;

function TTyGeo.ContainPoint(const APoint: TTyPointF): Boolean;
var r: TTyXYWH; mask: TFpuMask;
begin
  Result := False;
  if not (FValid and FHasData) then Exit;
  mask := MaskFpu;
  try
    { View.containPoint: the data rect through the overall matrix }
    r := RectApply(FData, FMtOverall);
    Result := RectContain(r, APoint.X, APoint.Y);
  finally
    UnmaskFpu(mask);
  end;
end;

function TTyGeo.AxisCount: Integer;
begin
  Result := 0;
end;

function TTyGeo.GetAxis(AIndex: Integer): TTyAxis;
begin
  if AIndex < 0 then ;
  Result := nil;
end;

function TTyGeo.RoamMatrix: TTyMat2D;
begin
  Result := TyGeoLocalTransform(FRoam);
end;

function NotAroundZero(AValue: Double): Boolean;
begin
  Result := (AValue > cTransEps) or (AValue < -cTransEps);
end;

function TTyGeo.HasRoamTransform: Boolean;
begin
  Result := NotAroundZero(FRoam.Rotation) or NotAroundZero(FRoam.X)
    or NotAroundZero(FRoam.Y) or NotAroundZero(FRoam.ScaleX - 1)
    or NotAroundZero(FRoam.ScaleY - 1) or NotAroundZero(FRoam.SkewX)
    or NotAroundZero(FRoam.SkewY);
end;

{ ==================== the picture ==================== }

{ The region option the map draws a region with: getFilledRegions'
  bookkeeping -- the LAST entry of `regions` with the name wins; a name
  without one gets a fresh entry per region, the last of them wins. AStyle
  is the echartsStyle that entry carries from the data (non-overwriting
  merge: the region option's own keys first). }
procedure RegionOptionOf(AGeo: TTyGeo; ARegionIndex: Integer;
  out AOpt: TJSONObject; out AStyle: TJSONObject);
var
  regions: TJSONData;
  i, last: Integer;
  nm: string;
  props: TJSONData;
  d: TJSONData;
begin
  AOpt := nil;
  AStyle := nil;
  nm := AGeo.Source.Regions[ARegionIndex].Name;
  regions := Own(AGeo.Node, 'regions');
  if regions is TJSONArray then
    for i := TJSONArray(regions).Count - 1 downto 0 do
    begin
      d := TJSONArray(regions).Items[i];
      if (d is TJSONObject) and Truthy(Own(d, 'name'))
        and (TyJsonJsString(Own(d, 'name')) = nm) then
      begin
        AOpt := TJSONObject(d);
        Break;
      end;
    end;
  if AOpt <> nil then
  begin
    { echartsStyle: every region of the name merges into the one entry, the
      first one's keys winning -- so the first region's style }
    for i := 0 to High(AGeo.Source.Regions) do
      if AGeo.Source.Regions[i].Name = nm then
      begin
        props := AGeo.Source.Regions[i].Properties;
        if Own(props, 'echartsStyle') is TJSONObject then
        begin
          AStyle := TJSONObject(Own(props, 'echartsStyle'));
          Exit;
        end;
      end;
    Exit;
  end;
  { a fresh entry per region of the name: the last region's }
  last := ARegionIndex;
  for i := 0 to High(AGeo.Source.Regions) do
    if AGeo.Source.Regions[i].Name = nm then last := i;
  props := AGeo.Source.Regions[last].Properties;
  if Own(props, 'echartsStyle') is TJSONObject then
    AStyle := TJSONObject(Own(props, 'echartsStyle'));
end;

{ ==================== the region model's chain [Batch 148] ====================

  GeoModel.getRegionModel(name) is a Model of the region option whose parent
  is the geo model, whose parent is the global model. Model.getShallow and
  Model.get read a path through objects only (an array or a string on the
  way is a null) and climb past null and undefined. The geo model's option
  is the written one with GeoModel.defaultOption merged in where it is
  silent (zrUtil.merge: an object over an object merges, anything written
  wins) and init's itemStyle.color. The region option is the regions entry
  with the feature's echartsStyle merged the same way. }

const
  { a default that is one of GeoModel's tokens (the skin's ink here) }
  cTok = #1'geo-token:';
  cStateWord: array[TTyStName] of string = ('select', 'emphasis', 'blur');

var
  GGeoDefaults: TJSONObject = nil;
  GGeoSvgDefaults: TJSONObject = nil;
  GMapDefaults: TJSONObject = nil;

{ GeoModel.defaultOption as far as a region's style and label read it }
function GeoDefaults: TJSONObject;
begin
  if GGeoDefaults = nil then
    GGeoDefaults := TJSONObject.Create([
      'label', TJSONObject.Create(['show', False, 'color', cTok + 'label']),
      'itemStyle', TJSONObject.Create(['borderWidth', 0.5,
        'borderColor', cTok + 'border', 'color', cTok + 'area']),
      'emphasis', TJSONObject.Create([
        'label', TJSONObject.Create(['show', True, 'color', cTok + 'labelHighlight']),
        'itemStyle', TJSONObject.Create(['color', cTok + 'highlight'])]),
      'select', TJSONObject.Create([
        'label', TJSONObject.Create(['show', True, 'color', cTok + 'labelHighlight']),
        'itemStyle', TJSONObject.Create(['color', cTok + 'highlight'])])]);
  Result := GGeoDefaults;
end;

{ [F6b] the same for a geo on an SVG map: init gives itemStyle no colour
  (the SVG's own fill stays) }
function GeoSvgDefaults: TJSONObject;
begin
  if GGeoSvgDefaults = nil then
    GGeoSvgDefaults := TJSONObject.Create([
      'label', TJSONObject.Create(['show', False, 'color', cTok + 'label']),
      'itemStyle', TJSONObject.Create(['borderWidth', 0.5,
        'borderColor', cTok + 'border']),
      'emphasis', TJSONObject.Create([
        'label', TJSONObject.Create(['show', True, 'color', cTok + 'labelHighlight']),
        'itemStyle', TJSONObject.Create(['color', cTok + 'highlight'])]),
      'select', TJSONObject.Create([
        'label', TJSONObject.Create(['show', True, 'color', cTok + 'labelHighlight']),
        'itemStyle', TJSONObject.Create(['color', cTok + 'highlight'])])]);
  Result := GGeoSvgDefaults;
end;

{ [Batch 152] MapSeries.defaultOption as far as a region's style and label
  read it: areaColor the background token, emphasis an areaColor, select a
  color }
function MapDefaults: TJSONObject;
begin
  if GMapDefaults = nil then
    GMapDefaults := TJSONObject.Create([
      'label', TJSONObject.Create(['show', False, 'color', cTok + 'label']),
      'itemStyle', TJSONObject.Create(['borderWidth', 0.5,
        'borderColor', cTok + 'border', 'areaColor', cTok + 'mapArea']),
      'emphasis', TJSONObject.Create([
        'label', TJSONObject.Create(['show', True, 'color', cTok + 'labelHighlight']),
        'itemStyle', TJSONObject.Create(['areaColor', cTok + 'highlight'])]),
      'select', TJSONObject.Create([
        'label', TJSONObject.Create(['show', True, 'color', cTok + 'labelHighlight']),
        'itemStyle', TJSONObject.Create(['color', cTok + 'highlight'])])]);
  Result := GMapDefaults;
end;

function TokenOf(AData: TJSONData): TTyGeoToken;
var s: string;
begin
  Result := gtkNone;
  if (AData = nil) or (AData.JSONType <> jtString) then Exit;
  s := AData.AsString;
  if Copy(s, 1, Length(cTok)) <> cTok then Exit;
  Delete(s, 1, Length(cTok));
  if s = 'area' then Result := gtkArea
  else if s = 'border' then Result := gtkBorder
  else if s = 'label' then Result := gtkLabel
  else if s = 'highlight' then Result := gtkHighlight
  else if s = 'labelHighlight' then Result := gtkLabelHighlight
  else if s = 'mapArea' then Result := gtkMapArea;
end;

function InkOf(AToken: TTyGeoToken; const AInk: TTyGeoInk): TTyChartColor;
begin
  case AToken of
    gtkArea: Result := AInk.AreaFill;
    gtkBorder: Result := AInk.Border;
    gtkLabel: Result := AInk.LabelColour;
    gtkHighlight: Result := AInk.HighlightFill;
    gtkLabelHighlight: Result := AInk.LabelHighlight;
    gtkMapArea: Result := AInk.MapAreaFill;
  else
    Result := 0;
  end;
end;

{ Model._doGet: the path through objects; nil where it breaks, is missing
  or ends in a null }
function PathGet(ANode: TJSONData; const APath: array of string): TJSONData;
var i: Integer;
begin
  Result := ANode;
  for i := 0 to High(APath) do
  begin
    if not (Result is TJSONObject) then Exit(nil);
    Result := TJSONObject(Result).Find(APath[i]);
    if Result = nil then Exit;
  end;
  if (Result <> nil) and (Result.JSONType = jtNull) then Result := nil;
end;

{ the geo's option merged over the defaults, read at a path [Batch 152: or
  a map series' over MapSeries' defaults] }
function GeoMergedGet(AGeoNode: TJSONObject; const APath: array of string;
  AMapSeries: Boolean = False; ASvg: Boolean = False): TJSONData;
var
  u, d, uv, dv: TJSONData;
  i: Integer;
  live: Boolean;
begin
  Result := nil;
  u := AGeoNode;
  live := u <> nil;
  if AMapSeries then d := MapDefaults
  else if ASvg then d := GeoSvgDefaults
  else d := GeoDefaults;
  for i := 0 to High(APath) do
  begin
    dv := nil;
    if d is TJSONObject then dv := TJSONObject(d).Find(APath[i]);
    if live and (TJSONObject(u).IndexOfName(APath[i]) >= 0) then
    begin
      uv := TJSONObject(u).Find(APath[i]);
      if i = High(APath) then
      begin
        if uv.JSONType = jtNull then Exit(nil);
        Exit(uv);
      end;
      if uv is TJSONObject then
      begin
        u := uv;
        if not (dv is TJSONObject) then dv := nil;
        d := dv;
        Continue;
      end;
      { init's `option.itemStyle = option.itemStyle || (an empty object)`: a falsy
        itemStyle is a fresh object that takes the colour default only }
      if not AMapSeries and not ASvg and (i = 0) and (APath[0] = 'itemStyle') and not Truthy(uv)
        and (High(APath) = 1) and (APath[1] = 'color') and (dv is TJSONObject) then
        Exit(TJSONObject(dv).Find('color'));
      Exit(nil);
    end;
    { the geo leaves it out: the default's }
    live := False;
    d := dv;
    if d = nil then Exit(nil);
  end;
  Result := d;
end;

{ zrUtil.merge(target, source) without overwrite: what the target leaves
  out, an object into an object deep }
procedure MergeAbsent(ATarget, ASource: TJSONObject);
var
  i: Integer;
  key: string;
  t: TJSONData;
begin
  for i := 0 to ASource.Count - 1 do
  begin
    key := ASource.Names[i];
    if ATarget.IndexOfName(key) >= 0 then
    begin
      t := ATarget.Find(key);
      if (t is TJSONObject) and (ASource.Items[i] is TJSONObject) then
        MergeAbsent(TJSONObject(t), TJSONObject(ASource.Items[i]));
    end
    else
      ATarget.Add(key, ASource.Items[i].Clone);
  end;
end;

{ JSON.stringify of an option value }
function JsJsonText(AData: TJSONData): string;
var i: Integer;
begin
  if AData = nil then Exit('null');
  case AData.JSONType of
    jtNull: Result := 'null';
    jtBoolean: if AData.AsBoolean then Result := 'true' else Result := 'false';
    jtNumber:
      if IsNan(AData.AsFloat) or IsInfinite(AData.AsFloat) then Result := 'null'
      else Result := TyJsNumberToString(AData.AsFloat);
    jtString: Result := TyJsonQuote(AData.AsString);
    jtArray:
      begin
        Result := '[';
        for i := 0 to AData.Count - 1 do
        begin
          if i > 0 then Result := Result + ',';
          Result := Result + JsJsonText(TJSONArray(AData).Items[i]);
        end;
        Result := Result + ']';
      end;
  else
    begin
      Result := '{';
      for i := 0 to AData.Count - 1 do
      begin
        if i > 0 then Result := Result + ',';
        Result := Result + TyJsonQuote(TJSONObject(AData).Names[i]) + ':'
          + JsJsonText(TJSONObject(AData).Items[i]);
      end;
      Result := Result + '}';
    end;
  end;
end;

function TTyGeo.Chain(ARegion: TJSONObject; const APath: array of string;
  out AToken: TTyGeoToken): TJSONData;
begin
  AToken := gtkNone;
  Result := PathGet(ARegion, APath);
  if Result <> nil then Exit;
  Result := GeoMergedGet(FChainNode, APath, FKind = gkMapSeries, FIsSvg);
  if Result <> nil then
  begin
    AToken := TokenOf(Result);
    if AToken <> gtkNone then Result := nil;
    Exit;
  end;
  Result := PathGet(FRoot, APath);
end;

function ColourOf(AData: TJSONData; out AColour: TTyChartColor;
  out AGrad: TTyChartGradient; out ANone: Boolean): Boolean;
begin
  AColour := 0;
  AGrad := Default(TTyChartGradient);
  ANone := False;
  Result := False;
  if AData = nil then Exit;
  if TyTryReadGradient(AData, AGrad) then
  begin
    AColour := TyGradientSolid(AGrad);
    Exit(True);
  end;
  if AData.JSONType <> jtString then Exit;
  if TyChartColorIsNone(AData.AsString) then
  begin
    ANone := True;
    Exit(True);
  end;
  Result := TyTryParseChartColor(AData.AsString, AColour);
end;

function RawText(AData: TJSONData): string;
begin
  if AData = nil then Exit('');
  if AData.JSONType = jtString then Result := AData.AsString
  else Result := AData.AsJSON;
end;

{ applyOptionStyleForRegion's style for one state (AState < 0: the normal
  one; else Ord of the state): getFixedItemStyle -- areaColor over color --
  up the region model's chain, and a line's state through fixLineStyle
  (the normal one is fixed where the picture is made, after its label's
  rect). [Batch 148: GE1's normal reader, with the chain to the root.] }
function PaintFor(AGeo: TTyGeo; ARegion: TJSONObject; AState: Integer;
  const AInk: TTyGeoInk; AIsLine: Boolean; AGroup: Integer = -1): TTyGeoPaint;
var
  d: TJSONData;
  tok: TTyGeoToken;
  none: Boolean;
  c: TTyChartColor;
  g: TTyChartGradient;
  tmp: TJSONObject;
  os: TTyOptStyle;

  function Get(const AKey: string): TJSONData;
  begin
    if AState < 0 then Result := AGeo.Chain(ARegion, ['itemStyle', AKey], tok)
    else Result := AGeo.Chain(ARegion,
      [cStateWord[TTyStName(AState)], 'itemStyle', AKey], tok);
  end;

begin
  Result := Default(TTyGeoPaint);
  Result.Opacity := 1;
  { fill: areaColor over color (the colour a token default) -- [Batch 152]
    a token areaColor (a map series' default) is an areaColor too }
  d := Get('areaColor');
  if (d = nil) and (tok = gtkNone) then d := Get('color');
  if d <> nil then
  begin
    Result.FillHas := True;
    Result.FillRaw := RawText(d);
    if (AState = Ord(stnEmphasis)) and (d.JSONType = jtString) and (d.AsString = 'inherit') then
      Result.FillInherit := True
    else if ColourOf(d, c, g, none) and not none then
    begin
      Result.FillSrc := gisOption;
      Result.Fill := c;
      Result.FillGradient := g;
    end;
  end
  else if tok <> gtkNone then
  begin
    Result.FillHas := True;
    Result.FillSrc := gisTheme;
    Result.FillToken := tok;
    Result.Fill := InkOf(tok, AInk);
  end
  else if AState < 0 then
  begin
    { [D9-D14] areaColor and color both null: getItemStyle sets no fill,
      and the path reads zrender's DEFAULT_PATH_STYLE fill '#000' through
      the style's prototype (a state's style is sparse: nothing there) }
    Result.FillSrc := gisOption;
    Result.FillRaw := '#000';
    TyTryParseChartColor('#000', Result.Fill);
  end;
  { [Batch 152] the data's visual over the normal fill: a visualMap's colour }
  if (AState < 0) and AGeo.Data.Active and (AGroup >= 0)
    and (AGroup <= High(AGeo.Data.Groups)) and AGeo.Data.Groups[AGroup].HasFill then
  begin
    Result.FillHas := True;
    Result.FillSrc := gisOption;
    Result.FillRaw := '';
    Result.FillToken := gtkNone;
    Result.FillInherit := False;
    Result.Fill := AGeo.Data.Groups[AGroup].Fill;
    Result.FillGradient := Default(TTyChartGradient);
  end;
  { stroke: borderColor }
  d := Get('borderColor');
  if d <> nil then
  begin
    Result.StrokeHas := True;
    Result.StrokeRaw := RawText(d);
    Result.StrokeTruthy := Truthy(d);
    if ColourOf(d, c, g, none) and not none then
    begin
      Result.StrokeSrc := gisOption;
      Result.Stroke := c;
    end;
  end
  else if tok <> gtkNone then
  begin
    Result.StrokeHas := True;
    Result.StrokeSrc := gisTheme;
    Result.StrokeToken := tok;
    Result.Stroke := InkOf(tok, AInk);
    Result.StrokeTruthy := True;
  end;
  { borderWidth: 0.5 by default; nothing at all is zrender's own 1 }
  d := Get('borderWidth');
  if d <> nil then
  begin
    Result.WidthHas := True;
    Result.LineWidthLogical := TyJsonToNumber(d);
  end
  else if AState < 0 then
    Result.LineWidthLogical := 1;
  d := Get('opacity');
  if d <> nil then
  begin
    Result.HasOpacity := True;
    Result.Opacity := TyJsonToNumber(d);
  end;
  d := Get('borderType');
  if d <> nil then
  begin
    Result.DashHas := True;
    Result.DashRaw := RawText(d);
    { read through the style reader: a one-key itemStyle }
    tmp := TJSONObject.Create(['itemStyle', TJSONObject.Create(['borderType', d.Clone])]);
    try
      os := TyReadOptStyle(tmp, 'itemStyle');
      Result.Dash := os.Dash;
      Result.DashLogical := os.DashLogical;
    finally
      tmp.Free;
    end;
  end;
  { fixLineStyle on a line's state object: `stroke = stroke || fill` -- an
    undefined set, which the merge carries -- and `fill = null` }
  if AIsLine and (AState >= 0) then
  begin
    if not (Result.StrokeHas and Result.StrokeTruthy) then
    begin
      Result.StrokeHas := True;
      Result.StrokeSrc := gisNone;
      Result.StrokeTruthy := False;
      Result.StrokeRaw := '';
      Result.StrokeToken := gtkNone;
      if Result.FillHas and (Result.FillSrc <> gisNone) then
      begin
        Result.StrokeSrc := Result.FillSrc;
        Result.StrokeRaw := Result.FillRaw;
        Result.Stroke := Result.Fill;
        Result.StrokeToken := Result.FillToken;
        Result.StrokeTruthy := True;
      end;
    end;
    Result.FillHas := True;
    Result.FillSrc := gisNone;
    Result.FillInherit := False;
    Result.FillToken := gtkNone;
  end;
end;

{ zrender's hasStroke / hasFill of a path's style }
function PaintHasFill(const P: TTyGeoPaint): Boolean;
begin
  Result := P.FillSrc <> gisNone;
end;

function PaintHasStroke(const P: TTyGeoPaint): Boolean;
begin
  Result := (P.StrokeSrc <> gisNone) and (P.LineWidthLogical > 0);
end;

{ The first canvas brush of a compound path into a fresh PathProxy:
  moveTo / lineTo / closePath with segments within (AUX, AUY) of the last
  drawn point folded into the farthest of them, drawn only by the next
  moveTo or closePath. }
type
  TProxy = record
    Cmds: TTyPathCmdArray;
    N: Integer;
    UX, UY: Double;
    XI, YI, X0, Y0: Double;
    PendX, PendY, PendD: Double;
  end;

procedure PxEmit(var P: TProxy; AKind: TTyPathCmdKind; AX, AY: Double);
begin
  if P.N >= Length(P.Cmds) then SetLength(P.Cmds, P.N * 2 + 16);
  P.Cmds[P.N] := Default(TTyPathCmd);
  P.Cmds[P.N].Kind := AKind;
  P.Cmds[P.N].X := AX;
  P.Cmds[P.N].Y := AY;
  Inc(P.N);
end;

procedure PxPending(var P: TProxy);
begin
  if P.PendD > 0 then
  begin
    PxEmit(P, pckLine, P.PendX, P.PendY);
    P.PendD := 0;
  end;
end;

procedure PxMove(var P: TProxy; AX, AY: Double);
begin
  PxPending(P);
  PxEmit(P, pckMove, AX, AY);
  P.X0 := AX; P.Y0 := AY;
  P.XI := AX; P.YI := AY;
end;

procedure PxLine(var P: TProxy; AX, AY: Double);
var dx, dy, d2: Double;
begin
  dx := Abs(AX - P.XI);
  dy := Abs(AY - P.YI);
  if (dx > P.UX) or (dy > P.UY) then
  begin
    PxEmit(P, pckLine, AX, AY);
    P.XI := AX;
    P.YI := AY;
    P.PendD := 0;
  end
  else
  begin
    d2 := dx * dx + dy * dy;
    if d2 > P.PendD then
    begin
      P.PendX := AX;
      P.PendY := AY;
      P.PendD := d2;
    end;
  end;
end;

procedure PxClose(var P: TProxy);
begin
  PxPending(P);
  PxEmit(P, pckClose, P.X0, P.Y0);
  P.XI := P.X0;
  P.YI := P.Y0;
end;

{ Path.getBoundingRect's path box: Math.min / max over every point a
  sub-path with two or more points builds }
function PathBox(const ASubs: TTyGeoRingArray): TTyXYWH;
var
  i, k: Integer;
  any: Boolean;
  minX, minY, maxX, maxY: Double;
begin
  minX := MaxDouble; minY := MaxDouble;
  maxX := -MaxDouble; maxY := -MaxDouble;
  any := False;
  for i := 0 to High(ASubs) do
  begin
    if Length(ASubs[i]) < 2 then Continue;
    any := True;
    for k := 0 to High(ASubs[i]) do
    begin
      minX := JsMin(minX, ASubs[i][k].X);
      minY := JsMin(minY, ASubs[i][k].Y);
      maxX := JsMax(maxX, ASubs[i][k].X);
      maxY := JsMax(maxY, ASubs[i][k].Y);
    end;
  end;
  if not any then Exit(TyXYWH(0, 0, 0, 0));
  Result := NewRect(minX, minY, maxX - minX, maxY - minY);
end;

{ ---- what hangs on the roam [Batch 150: factored out of TyGeoDrawOf, the
  same arithmetic, so a roam can work it out again on a kept picture] ---- }

{ the transform group's matrix (none within 5e-5 of the identity) and
  PathProxy.setScale's unit under its global scale }
procedure DrawRoamUnits(AGeo: TTyGeo; var ADraw: TTyGeoDraw);
var gm: TTyMat2D; gs: Double;
begin
  ADraw.HasTrans := AGeo.HasRoamTransform;
  if ADraw.HasTrans then ADraw.Trans := AGeo.RoamMatrix
  else ADraw.Trans := MatIdentity;
  { getGlobalScale: the transform's, or one; PathProxy.setScale: the
    threshold over it, `|| 0` }
  if ADraw.HasTrans then
  begin
    gm := ADraw.Trans;
    gs := Sqrt(gm[0] * gm[0] + gm[1] * gm[1]);
    if gm[0] < 0 then gs := -gs;
    ADraw.UX := Abs(TyGeoSegmentIgnore / 1 / gs);
    if JsFalsy(ADraw.UX) then ADraw.UX := 0;
    gs := Sqrt(gm[2] * gm[2] + gm[3] * gm[3]);
    if gm[3] < 0 then gs := -gs;
    ADraw.UY := Abs(TyGeoSegmentIgnore / 1 / gs);
    if JsFalsy(ADraw.UY) then ADraw.UY := 0;
  end
  else
  begin
    ADraw.UX := TyGeoSegmentIgnore;
    ADraw.UY := TyGeoSegmentIgnore;
  end;
end;

{ what a brush hands the context: every sub-path of two points or more,
  the small segments folded under the unit (a later frame's rebuildPath
  folds the stored data the same way at the scale it has then) }
function FoldSubs(const ASubs: TTyGeoRingArray; AIsLine: Boolean;
  AUX, AUY: Double): TTyPathCmdArray;
var px: TProxy; j, q, np: Integer;
begin
  px := Default(TProxy);
  px.UX := AUX;
  px.UY := AUY;
  for j := 0 to High(ASubs) do
  begin
    np := Length(ASubs[j]);
    if np < 2 then Continue;
    PxMove(px, ASubs[j][0].X, ASubs[j][0].Y);
    for q := 1 to np - 1 do PxLine(px, ASubs[j][q].X, ASubs[j][q].Y);
    if not AIsLine then PxClose(px);
  end;
  SetLength(px.Cmds, px.N);
  Result := px.Cmds;
end;

{ updateInnerText: the layout rect through the element's transform, then
  the percentages of it }
procedure PlaceLabel(var P: TTyGeoDrawPath; const ADraw: TTyGeoDraw);
var tr: TTyXYWH;
begin
  if not P.Lbl.HasPos then Exit;
  if ADraw.HasTrans then tr := RectApply(P.Lbl.Layout, ADraw.Trans) else tr := P.Lbl.Layout;
  P.Lbl.AnchorX := tr.X + P.Lbl.PctX / 100 * tr.W;
  P.Lbl.AnchorY := tr.Y + P.Lbl.PctY / 100 * tr.H;
end;

{ the rect once drawn: the line's fixed style, the stroke over the
  transform's line scale (strokeNoScale) }
procedure DrawnBox(var P: TTyGeoDrawPath; const ADraw: TTyGeoDraw; AScale: Double);
var lw, ls: Double;
begin
  P.BoxRect := PathBox(P.Subs);
  if PaintHasStroke(P.Paint) and (Length(P.Drawn) > 0) then
  begin
    ls := 1;
    if ADraw.HasTrans and (Abs(ADraw.Trans[0] - 1) > 1e-10) and (Abs(ADraw.Trans[3] - 1) > 1e-10) then
      ls := Sqrt(Abs(ADraw.Trans[0] * ADraw.Trans[3] - ADraw.Trans[2] * ADraw.Trans[1]));
    lw := P.Paint.LineWidthLogical * AScale;
    if not PaintHasFill(P.Paint) then lw := JsMax(lw, TyGeoStrokeContain * AScale);
    if ls > 1e-10 then
    begin
      P.BoxRect.W := P.BoxRect.W + lw / ls;
      P.BoxRect.H := P.BoxRect.H + lw / ls;
      P.BoxRect.X := P.BoxRect.X - lw / ls / 2;
      P.BoxRect.Y := P.BoxRect.Y - lw / ls / 2;
    end;
  end;
end;

{ __updateOnOwnRoam on a kept picture: the group's matrix, the unit, every
  path's drawn commands, its label's anchor and its drawn box again }
procedure TyGeoDrawReroam(AGeo: TTyGeo; var ADraw: TTyGeoDraw; APPI: Integer);
var g, k: Integer; scale: Double; mask: TFpuMask;
begin
  if APPI > 0 then scale := APPI / 96 else scale := 1;
  mask := MaskFpu;
  try
    DrawRoamUnits(AGeo, ADraw);
    for g := 0 to High(ADraw.Groups) do
      for k := 0 to High(ADraw.Groups[g].Paths) do
      begin
        ADraw.Groups[g].Paths[k].Drawn := FoldSubs(ADraw.Groups[g].Paths[k].Subs,
          ADraw.Groups[g].Paths[k].IsLine, ADraw.UX, ADraw.UY);
        PlaceLabel(ADraw.Groups[g].Paths[k], ADraw);
        DrawnBox(ADraw.Groups[g].Paths[k], ADraw, scale);
      end;
  finally
    UnmaskFpu(mask);
  end;
end;

{ resetLabelForRegion's setLabelStyle: the normal text style and textConfig
  and the three states' -- getLabelStatesModels(regionModel) up the chain,
  the texts getFormattedLabel's (a state's from emphasis.label.formatter,
  whatever the state, else the normal text). [Batch 148: GE1's normal
  reader, with the chain to the root, and the states.] }
function LabelFor(AGeo: TTyGeo; ARegion: TJSONObject; const AName: string;
  const AInk: TTyGeoInk; AGroup: Integer = -1): TTyGeoLabel;
var
  isMap: Boolean;
  dg: TTyGeoDataGroup;
  d: TJSONData;
  tok: TTyGeoToken;
  g: TTyChartGradient;
  none, stShow: Boolean;
  s: TTyStName;
  st: TTyGeoLabelState;
  c: TTyChartColor;

  { [Batch 152] a map series' DataFormatMixin.getFormattedLabel(dataIndex,
    status): the state's own formatter up the item's chain (the normal
    one label.formatter, a state's its own), a '@' handler given the
    params and the status, a string through formatTpl over
    [seriesName, name, value] with each at-dimension reference the value
    (the one dimension) -- no labelFetcher where the name has no data:
    undefined }
  function SeriesFormatted(const AStatus: string; out AText: string): Boolean;
  var
    f: TJSONData;
    fmt: TTyChartFormatter;
    params: TTyChartParams;
    t: TTyGeoToken;
    vars: array of TTyStringArray;
    s, dim: string;
    i, j: Integer;
  begin
    Result := False;
    AText := '';
    if dg.Row < 0 then Exit;
    if AStatus = 'normal' then f := AGeo.Chain(ARegion, ['label', 'formatter'], t)
    else f := AGeo.Chain(ARegion, [AStatus, 'label', 'formatter'], t);
    if (f = nil) or (f.JSONType <> jtString) or (f.AsString = '') then Exit;
    if f.AsString[1] = '@' then
    begin
      if not TyChartFindFormatter(Copy(f.AsString, 2, MaxInt), fmt) then Exit;
      SetLength(params, 1);
      params[0] := dg.Params;
      params[0].Status := AStatus;
      AText := fmt(params);
      Exit(True);
    end;
    vars := nil;
    SetLength(vars, 1);
    SetLength(vars[0], 3);
    vars[0][0] := dg.Params.SeriesName;
    vars[0][1] := dg.Params.Name;
    vars[0][2] := dg.Params.ValueText;
    s := TyJsFormatTpl(f.AsString, 3, vars);
    { DIMENSION_LABEL_REG: the value dimension by name or by [0], any other
      name nothing }
    AText := '';
    i := 1;
    while i <= Length(s) do
    begin
      if (s[i] = '{') and (i < Length(s)) and (s[i + 1] = '@') then
      begin
        j := i + 2;
        while (j <= Length(s)) and (s[j] <> '}') do Inc(j);
        if (j <= Length(s)) and (j > i + 2) then
        begin
          dim := Copy(s, i + 2, j - i - 2);
          if (dim = 'value') or (dim = '[0]') or (dim = '[]') then
            AText := AText + dg.Params.ValueText;
          i := j + 1;
          Continue;
        end;
      end;
      AText := AText + s[i];
      Inc(i);
    end;
    Result := True;
  end;

  { getFormattedLabel(name, status): a '@' handler is a function given
    the name and the status; a string replaces its first a-placeholder; anything else is
    undefined }
  function Formatted(const AStatus: string; out AText: string): Boolean;
  var
    f: TJSONData;
    fmt: TTyChartFormatter;
    params: TTyChartParams;
    t: TTyGeoToken;
  begin
    Result := False;
    AText := '';
    if isMap then Exit(SeriesFormatted(AStatus, AText));
    if AStatus = 'normal' then f := AGeo.Chain(ARegion, ['label', 'formatter'], t)
    else f := AGeo.Chain(ARegion, ['emphasis', 'label', 'formatter'], t);
    if (f = nil) or (f.JSONType <> jtString) then Exit;
    if (f.AsString <> '') and (f.AsString[1] = '@') then
    begin
      if not TyChartFindFormatter(Copy(f.AsString, 2, MaxInt), fmt) then Exit;
      SetLength(params, 1);
      params[0] := Default(TTyChartCallbackParams);
      params[0].ComponentType := 'geo';
      params[0].ComponentIndex := AGeo.Index;
      params[0].SeriesIndex := -1;
      params[0].DataIndex := -1;
      params[0].RawDataIndex := -1;
      params[0].Name := AName;
      params[0].Status := AStatus;
      AText := fmt(params);
      Exit(True);
    end;
    AText := TyJsReplaceFirst(f.AsString, '{a}', AName);
    Result := True;
  end;

  function Get(const AState, AKey: string): TJSONData;
  begin
    if AState = '' then Result := AGeo.Chain(ARegion, ['label', AKey], tok)
    else Result := AGeo.Chain(ARegion, [AState, 'label', AKey], tok);
  end;

begin
  Result := Default(TTyGeoLabel);
  isMap := (AGeo.Kind = gkMapSeries) and AGeo.Data.Active and (AGroup >= 0)
    and (AGroup <= High(AGeo.Data.Groups));
  if isMap then dg := AGeo.Data.Groups[AGroup]
  else dg := Default(TTyGeoDataGroup);
  Result.Shown := Truthy(Get('', 'show'));
  Result.Exists := Result.Shown;
  if not Formatted('normal', Result.Text) then Result.Text := AName;
  d := Get('', 'color');
  if (d <> nil) and ColourOf(d, Result.Colour, g, none) and not none then
  begin
    Result.HasColour := True;
    Result.ColourRaw := RawText(d);
  end
  else
  begin
    Result.ColourToken := tok;
    if tok <> gtkNone then Result.Colour := InkOf(tok, AInk)
    else Result.Colour := AInk.LabelColour;
  end;
  d := Get('', 'fontSize');
  if d <> nil then
  begin
    Result.HasFontSize := True;
    Result.FontSizeLogical := TyOptFontSize(d, AInk.LabelFontSizeLogical);
  end
  else
    Result.FontSizeLogical := AInk.LabelFontSizeLogical;
  d := Get('', 'fontWeight');
  if d <> nil then
  begin
    Result.HasFontWeight := True;
    Result.FontWeight := TyFontWeightOf(d, AInk.LabelFontWeight);
  end
  else
    Result.FontWeight := AInk.LabelFontWeight;
  d := Get('', 'fontFamily');
  if (d <> nil) and (d.JSONType = jtString) then
  begin
    Result.HasFontFamily := True;
    Result.FontFamily := d.AsString;
  end
  else
    Result.FontFamily := AInk.LabelFontName;
  d := Get('', 'opacity');
  if d <> nil then
  begin
    Result.HasOpacity := True;
    Result.Opacity := TyJsonToNumber(d);
  end;
  { createTextConfig: offset as written, rotate in degrees }
  d := Get('', 'offset');
  if d <> nil then
  begin
    Result.HasOffset := True;
    Result.OffX := TyJsonToNumber(Item(d, 0));
    Result.OffY := TyJsonToNumber(Item(d, 1));
  end;
  d := Get('', 'rotate');
  if d <> nil then
  begin
    Result.HasRotate := True;
    Result.RotationRad := TyJsonToNumber(d) * cJsPi / 180;
  end;
  Result.Silent := Truthy(Get('', 'silent'));
  for s := Low(TTyStName) to High(TTyStName) do
  begin
    st := Default(TTyGeoLabelState);
    { retrieve2(state show, normal show): the state's ignore only where it
      differs }
    d := Get(cStateWord[s], 'show');
    if d <> nil then stShow := Truthy(d) else stShow := Result.Shown;
    if stShow then Result.Exists := True;
    if stShow <> Result.Shown then
    begin
      st.HasIgnore := True;
      st.Ignore := not stShow;
    end;
    if not Formatted(cStateWord[s], st.Text) then st.Text := Result.Text;
    { setTokenTextStyle in a state: only what the state's model says, no
      global text style; 'inherit' and 'auto' are no colour here }
    d := Get(cStateWord[s], 'color');
    if d <> nil then
    begin
      if not ((d.JSONType = jtString) and ((d.AsString = 'inherit') or (d.AsString = 'auto'))) then
      begin
        st.HasColour := True;
        st.ColourRaw := RawText(d);
        if ColourOf(d, c, g, none) and not none then st.Colour := c
        else st.ColourNone := True;
      end;
    end
    else if tok <> gtkNone then
    begin
      st.HasColour := True;
      st.ColourToken := tok;
      st.Colour := InkOf(tok, AInk);
    end;
    d := Get(cStateWord[s], 'fontSize');
    if d <> nil then
    begin
      st.HasFontSize := True;
      st.FontSizeLogical := TyOptFontSize(d, AInk.LabelFontSizeLogical);
    end;
    d := Get(cStateWord[s], 'fontWeight');
    if d <> nil then
    begin
      st.HasFontWeight := True;
      st.FontWeight := TyFontWeightOf(d, AInk.LabelFontWeight);
    end;
    d := Get(cStateWord[s], 'fontFamily');
    if (d <> nil) and (d.JSONType = jtString) then
    begin
      st.HasFontFamily := True;
      st.FontFamily := d.AsString;
    end;
    d := Get(cStateWord[s], 'opacity');
    if d <> nil then
    begin
      st.HasOpacity := True;
      st.Opacity := TyJsonToNumber(d);
    end;
    d := Get(cStateWord[s], 'offset');
    if d <> nil then
    begin
      st.HasOffset := True;
      st.OffX := TyJsonToNumber(Item(d, 0));
      st.OffY := TyJsonToNumber(Item(d, 1));
    end;
    d := Get(cStateWord[s], 'rotate');
    if d <> nil then
    begin
      st.HasRotate := True;
      st.RotationRad := TyJsonToNumber(d) * cJsPi / 180;
    end;
    Result.States[s] := st;
  end;
  { [Batch 152] resetLabelForRegion's rule for a map series: no text at all
    where the value is a number and a legend symbol stands on the region }
  if isMap and not dg.LabelOn then Result.Exists := False;
end;

function TyGeoDrawOf(AGeo: TTyGeo; const AInk: TTyGeoInk; APPI: Integer): TTyGeoDraw;
var
  dr: TTyGeoDraw;
  scale: Double;
  regions: TTyGeoRegionArray;
  i, gi, k, s: Integer;
  region: TTyGeoRegion;
  ropt: TJSONObject;
  polys, lines: TTyGeoRingArray;
  centre: TTyGeoPt;
  hasCentre: Boolean;
  rawM: TTyMat2D;
  d: TJSONData;
  mask: TFpuMask;
  tok: TTyGeoToken;

  function GroupOf(const AName: string): Integer;
  var j: Integer;
  begin
    for j := 0 to High(dr.Groups) do
      if dr.Groups[j].Name = AName then Exit(j);
    j := Length(dr.Groups);
    SetLength(dr.Groups, j + 1);
    dr.Groups[j] := Default(TTyGeoDrawGroup);
    dr.Groups[j].Name := AName;
    { `regionModel.get('silent', true)`: the region option's own (with its
      echartsStyle) }
    d := PathGet(ropt, ['silent']);
    if d <> nil then
    begin
      dr.Groups[j].HasSilent := True;
      dr.Groups[j].Silent := Truthy(d);
    end;
    { [Batch 148] resetEventTriggerForRegion's region, and
      resetStateTriggerForRegion's emphasis model }
    if ropt <> nil then dr.Groups[j].RegionJson := JsJsonText(ropt)
    else dr.Groups[j].RegionJson := '{}';
    d := AGeo.Chain(ropt, ['emphasis', 'focus'], tok);
    dr.Groups[j].FocusSelf := (d <> nil) and (d.JSONType = jtString) and (d.AsString = 'self');
    dr.Groups[j].EmphasisDisabled := Truthy(AGeo.Chain(ropt, ['emphasis', 'disabled'], tok));
    Result := j;
  end;

  { transformPoint: projected (a dropped point is skipped), then raw }
  function PointsOf(const ARing: TTyGeoRing): TTyGeoRing;
  var j, n: Integer; x, y: Double;
  begin
    Result := nil;
    SetLength(Result, Length(ARing));
    n := 0;
    for j := 0 to High(ARing) do
    begin
      x := ARing[j].X;
      y := ARing[j].Y;
      if AGeo.Projection.Active then
        if not AGeo.Projection.Project(x, y, x, y) then Continue;
      Result[n] := TyGeoApply(rawM, x, y);
      Inc(n);
    end;
    SetLength(Result, n);
  end;

  procedure AddRing(var AList: TTyGeoRingArray; const ARing: TTyGeoRing);
  begin
    SetLength(AList, Length(AList) + 1);
    AList[High(AList)] := PointsOf(ARing);
  end;

  procedure AddPath(const ASubs: TTyGeoRingArray; AIsLine: Boolean);
  var
    p: TTyGeoDrawPath;
    lw: Double;
    sn: TTyStName;
  begin
    if Length(ASubs) = 0 then Exit;
    p := Default(TTyGeoDrawPath);
    p.IsLine := AIsLine;
    p.Subs := ASubs;
    p.Paint := PaintFor(AGeo, ropt, -1, AInk, False, gi);
    { [Batch 148] the three states' styles }
    for sn := Low(TTyStName) to High(TTyStName) do
      p.StatePaint[sn] := PaintFor(AGeo, ropt, Ord(sn), AInk, AIsLine);
    { what the first brush hands the context }
    p.Drawn := FoldSubs(ASubs, AIsLine, dr.UX, dr.UY);
    { the rect the label is placed in: the path box grown by the stroke of
      the polygon style (before a line's fix), at a line scale of 1 -- the
      element has no transform yet }
    p.Rect := PathBox(ASubs);
    if PaintHasStroke(p.Paint) and (Length(p.Drawn) > 0) then
    begin
      lw := p.Paint.LineWidthLogical * scale;
      if not PaintHasFill(p.Paint) then lw := JsMax(lw, TyGeoStrokeContain * scale);
      p.Rect.W := p.Rect.W + lw;
      p.Rect.H := p.Rect.H + lw;
      p.Rect.X := p.Rect.X - lw / 2;
      p.Rect.Y := p.Rect.Y - lw / 2;
    end;
    { the label }
    p.Lbl := LabelFor(AGeo, ropt, region.Name, AInk, gi);
    if hasCentre then
    begin
      p.Lbl.HasPos := True;
      p.Lbl.XY := centre;
      p.Lbl.PctX := (centre.X - p.Rect.X) / p.Rect.W * 100;
      p.Lbl.PctY := (centre.Y - p.Rect.Y) / p.Rect.H * 100;
      p.Lbl.Layout := p.Rect;
      PlaceLabel(p, dr);
    end;
    { fixLineStyle: `stroke = stroke || fill`, and no fill }
    if AIsLine then
    begin
      if not p.Paint.StrokeTruthy then
      begin
        p.Paint.StrokeSrc := p.Paint.FillSrc;
        p.Paint.StrokeRaw := p.Paint.FillRaw;
        p.Paint.Stroke := p.Paint.Fill;
        p.Paint.StrokeTruthy := p.Paint.FillSrc <> gisNone;
      end;
      p.Paint.FillSrc := gisNone;
    end;
    { the rect once drawn }
    DrawnBox(p, dr, scale);
    SetLength(dr.Groups[gi].Paths, Length(dr.Groups[gi].Paths) + 1);
    dr.Groups[gi].Paths[High(dr.Groups[gi].Paths)] := p;
  end;

begin
  dr := Default(TTyGeoDraw);
  Result := dr;
  if (AGeo = nil) or not AGeo.Valid or not AGeo.Spec.Show then Exit;
  if APPI > 0 then scale := APPI / 96 else scale := 1;
  mask := MaskFpu;
  try
    rawM := AGeo.MtRaw;
    DrawRoamUnits(AGeo, dr);
    if AGeo.Spec.Clip then
    begin
      dr.HasClip := True;
      dr.Clip := AGeo.ViewRect;
    end;
    regions := AGeo.Source.Regions;
    for i := 0 to High(regions) do
    begin
      region := regions[i];
      ropt := AGeo.RegionOpt(i);
      gi := GroupOf(region.Name);
      polys := nil;
      lines := nil;
      for k := 0 to High(region.Geometries) do
        if region.Geometries[k].Kind = ggkPolygon then
        begin
          AddRing(polys, region.Geometries[k].Exterior);
          for s := 0 to High(region.Geometries[k].Interiors) do
            AddRing(polys, region.Geometries[k].Interiors[s]);
        end
        else
          for s := 0 to High(region.Geometries[k].Lines) do
            AddRing(lines, region.Geometries[k].Lines[s]);
      { the label's anchor: the centre, projected then raw }
      centre := region.GetCenter;
      hasCentre := True;
      if AGeo.Projection.Active then
        hasCentre := AGeo.Projection.Project(centre.X, centre.Y, centre.X, centre.Y);
      if hasCentre then centre := TyGeoApply(rawM, centre.X, centre.Y);
      AddPath(polys, False);
      AddPath(lines, True);
    end;
  finally
    UnmaskFpu(mask);
  end;
  Result := dr;
end;

{ ==================== the regions' states [Batch 148] ==================== }

function TTyGeo.RegionOpt(ARegionIndex: Integer): TJSONObject;
var
  nm: string;
  i, n: Integer;
  entry, style: TJSONObject;
begin
  Result := nil;
  if (FSource = nil) or (ARegionIndex < 0) or (ARegionIndex > High(FSource.Regions)) then Exit;
  nm := FSource.Regions[ARegionIndex].Name;
  { [Batch 152] a map series' region model is its data item's (getItemModel
    of the name's data index) }
  if (FKind = gkMapSeries) and FSeriesData.Active then
  begin
    EnsureGroups;
    for i := 0 to High(FGroupNames) do
      if FGroupNames[i] = nm then
      begin
        if i <= High(FSeriesData.Groups) then Exit(FSeriesData.Groups[i].Opt);
        Exit(nil);
      end;
    Exit;
  end;
  { optionModelMap keeps a truthy name only: getRegionModel('') is a model
    of nothing }
  if nm = '' then Exit;
  for i := 0 to High(FOptNames) do
    if FOptNames[i] = nm then Exit(FOpts[i]);
  RegionOptionOf(Self, ARegionIndex, entry, style);
  if entry <> nil then Result := TJSONObject(entry.Clone)
  else Result := TJSONObject.Create(['name', nm]);
  if style <> nil then MergeAbsent(Result, style);
  n := Length(FOptNames);
  SetLength(FOptNames, n + 1);
  SetLength(FOpts, n + 1);
  FOptNames[n] := nm;
  FOpts[n] := Result;
end;

procedure TTyGeo.EnsureGroups;
var
  i, k: Integer;
  nm: string;
  found: Boolean;
begin
  if FGroupsOk then Exit;
  FGroupsOk := True;
  FGroupNames := nil;
  FSt := nil;
  { what MapDraw draws: nothing for an invalid or hidden geo }
  if (FSource = nil) or not FValid or not FSpec.Show then Exit;
  for i := 0 to High(FSource.Regions) do
  begin
    nm := FSource.Regions[i].Name;
    found := False;
    for k := 0 to High(FGroupNames) do
      if FGroupNames[k] = nm then
      begin
        found := True;
        Break;
      end;
    if found then Continue;
    SetLength(FGroupNames, Length(FGroupNames) + 1);
    FGroupNames[High(FGroupNames)] := nm;
  end;
  SetLength(FSt, Length(FGroupNames));
  for k := 0 to High(FSt) do FSt[k] := Default(TTyGeoGroupSt);
end;

function TTyGeo.GroupCount: Integer;
begin
  EnsureGroups;
  Result := Length(FGroupNames);
end;

function TTyGeo.GroupName(AGroup: Integer): string;
begin
  EnsureGroups;
  if (AGroup >= 0) and (AGroup <= High(FGroupNames)) then Result := FGroupNames[AGroup]
  else Result := '';
end;

function TTyGeo.GroupIndexOf(const AName: string): Integer;
var i: Integer;
begin
  EnsureGroups;
  for i := 0 to High(FGroupNames) do
    if FGroupNames[i] = AName then Exit(i);
  Result := -1;
end;

function TTyGeo.GroupOpt(AGroup: Integer): TJSONObject;
var i: Integer; nm: string;
begin
  Result := nil;
  nm := GroupName(AGroup);
  if (nm = '') or (FSource = nil) then Exit;
  for i := 0 to High(FSource.Regions) do
    if FSource.Regions[i].Name = nm then Exit(RegionOpt(i));
end;

function TTyGeo.GroupRegionJson(AGroup: Integer): string;
var opt: TJSONObject;
begin
  opt := GroupOpt(AGroup);
  if opt <> nil then Result := JsJsonText(opt) else Result := '{}';
end;

function TyGeoJsJson(AData: TJSONData): string;
begin
  Result := JsJsonText(AData);
end;

procedure TyGeoMergeAbsent(ATarget, ASource: TJSONObject);
begin
  if (ATarget <> nil) and (ASource <> nil) then MergeAbsent(ATarget, ASource);
end;

function TTyGeo.GroupFocusSelf(AGroup: Integer): Boolean;
var d: TJSONData; tok: TTyGeoToken;
begin
  { enableHoverFocus runs only where the emphasis is not disabled: a
    disabled group's ecData has no focus }
  if GroupEmphasisDisabled(AGroup) then Exit(False);
  d := Chain(GroupOpt(AGroup), ['emphasis', 'focus'], tok);
  Result := (d <> nil) and (d.JSONType = jtString) and (d.AsString = 'self');
end;

function TTyGeo.GroupEmphasisDisabled(AGroup: Integer): Boolean;
var tok: TTyGeoToken;
begin
  Result := Truthy(Chain(GroupOpt(AGroup), ['emphasis', 'disabled'], tok));
end;

function GeoDigitBit(ADigit: Integer): Cardinal;
begin
  { JavaScript's 1 << n takes n mod 32 }
  Result := Cardinal(1) shl (ADigit and 31);
end;

function TTyGeo.HoverEnter(AGroup: Integer): Boolean;
var k: Integer;
begin
  Result := False;
  EnsureGroups;
  if FIsSvg then
  begin
    { enterEmphasisWhenMouseOver on every dispatcher of the name }
    if (AGroup < 0) or (AGroup > High(FSvgDisp)) then Exit;
    FSvgChanged := False;
    for k := 0 to High(FSvgDisp[AGroup]) do
      if FSvgHbo[FSvgDisp[AGroup][k]] = 0 then
        SvgTraverse(FSvgDisp[AGroup][k], cSvgEnterEmph, 0);
    Exit(FSvgChanged);
  end;
  if (AGroup < 0) or (AGroup > High(FSt)) or (FSt[AGroup].Hbo <> 0) then Exit;
  Result := FSt[AGroup].Hover <> TyStHoverEmphasis;
  FSt[AGroup].Hover := TyStHoverEmphasis;
end;

function TTyGeo.HoverLeave(AGroup: Integer): Boolean;
var k: Integer;
begin
  Result := False;
  EnsureGroups;
  if FIsSvg then
  begin
    if (AGroup < 0) or (AGroup > High(FSvgDisp)) then Exit;
    FSvgChanged := False;
    for k := 0 to High(FSvgDisp[AGroup]) do
      if FSvgHbo[FSvgDisp[AGroup][k]] = 0 then
        SvgTraverse(FSvgDisp[AGroup][k], cSvgLeaveEmph, 0);
    Exit(FSvgChanged);
  end;
  if (AGroup < 0) or (AGroup > High(FSt)) or (FSt[AGroup].Hbo <> 0) then Exit;
  if FSt[AGroup].Hover <> TyStHoverEmphasis then Exit;
  FSt[AGroup].Hover := TyStHoverNormal;
  Result := True;
end;

function TTyGeo.EnterEmphasisBy(AGroup, ADigit: Integer): Boolean;
var k, d: Integer;
begin
  Result := False;
  EnsureGroups;
  if FIsSvg then
  begin
    if (AGroup < 0) or (AGroup > High(FSvgDisp)) then Exit;
    FSvgChanged := False;
    for k := 0 to High(FSvgDisp[AGroup]) do
    begin
      d := FSvgDisp[AGroup][k];
      FSvgHbo[d] := FSvgHbo[d] or GeoDigitBit(ADigit);
      SvgTraverse(d, cSvgEnterEmph, 0);
    end;
    Exit(FSvgChanged);
  end;
  if (AGroup < 0) or (AGroup > High(FSt)) then Exit;
  FSt[AGroup].Hbo := FSt[AGroup].Hbo or GeoDigitBit(ADigit);
  Result := FSt[AGroup].Hover <> TyStHoverEmphasis;
  FSt[AGroup].Hover := TyStHoverEmphasis;
end;

function TTyGeo.LeaveEmphasisBy(AGroup, ADigit: Integer): Boolean;
var k, d: Integer;
begin
  Result := False;
  EnsureGroups;
  if FIsSvg then
  begin
    if (AGroup < 0) or (AGroup > High(FSvgDisp)) then Exit;
    FSvgChanged := False;
    for k := 0 to High(FSvgDisp[AGroup]) do
    begin
      d := FSvgDisp[AGroup][k];
      FSvgHbo[d] := FSvgHbo[d] and not GeoDigitBit(ADigit);
      if FSvgHbo[d] = 0 then SvgTraverse(d, cSvgLeaveEmph, 0);
    end;
    Exit(FSvgChanged);
  end;
  if (AGroup < 0) or (AGroup > High(FSt)) then Exit;
  FSt[AGroup].Hbo := FSt[AGroup].Hbo and not GeoDigitBit(ADigit);
  { only when every bit is gone }
  if (FSt[AGroup].Hbo <> 0) or (FSt[AGroup].Hover <> TyStHoverEmphasis) then Exit;
  FSt[AGroup].Hover := TyStHoverNormal;
  Result := True;
end;

function TTyGeo.BlurAll: Boolean;
var i: Integer;
begin
  Result := False;
  EnsureGroups;
  if FIsSvg then
  begin
    FSvgChanged := False;
    if Length(FSvgEl) > 0 then SvgTraverse(TyGsRootNode, cSvgEnterBlur, 0);
    FIsBlured := True;
    Exit(FSvgChanged);
  end;
  for i := 0 to High(FSt) do
    if FSt[i].Hover <> TyStHoverBlur then
    begin
      FSt[i].Hover := TyStHoverBlur;
      Result := True;
    end;
  FIsBlured := True;
end;

function TTyGeo.LeaveBlurAll: Boolean;
var i: Integer;
begin
  Result := False;
  EnsureGroups;
  if FIsSvg then
  begin
    FSvgChanged := False;
    if Length(FSvgEl) > 0 then SvgTraverse(TyGsRootNode, cSvgLeaveBlur, 0);
    Exit(FSvgChanged);
  end;
  for i := 0 to High(FSt) do
    if FSt[i].Hover = TyStHoverBlur then
    begin
      FSt[i].Hover := TyStHoverNormal;
      Result := True;
    end;
end;

function TTyGeo.SetSelected(AGroup: Integer; ASelected: Boolean): Boolean;
begin
  Result := False;
  EnsureGroups;
  if (AGroup < 0) or (AGroup > High(FSt)) then Exit;
  { [F6b] an SVG map's names: the nodes follow at the next apply
    (updateSelectStatus) }
  Result := FSt[AGroup].Selected <> ASelected;
  FSt[AGroup].Selected := ASelected;
end;

function TTyGeo.GroupFlags(AGroup: Integer): TTyGeoGroupSt;
var h: Integer;
begin
  EnsureGroups;
  if FIsSvg then
  begin
    { a name's flags: its first dispatcher's (or first item's) hover and
      action bits, the name's selection }
    Result := Default(TTyGeoGroupSt);
    if (AGroup < 0) or (AGroup > High(FSt)) then Exit;
    Result.Selected := FSt[AGroup].Selected;
    h := SvgGroupHead(AGroup);
    if (h >= 0) and (h <= High(FSvgEl)) then
    begin
      Result.Hover := FSvgEl[h].HoverState;
      Result.Hbo := FSvgHbo[h];
    end;
    Exit;
  end;
  if (AGroup >= 0) and (AGroup <= High(FSt)) then Result := FSt[AGroup]
  else Result := Default(TTyGeoGroupSt);
end;

function SameInk(const A, B: TTyGeoInk): Boolean;
begin
  Result := (A.AreaFill = B.AreaFill) and (A.Border = B.Border)
    and (A.LabelColour = B.LabelColour) and (A.LabelFontName = B.LabelFontName)
    and (A.LabelFontSizeLogical = B.LabelFontSizeLogical)
    and (A.LabelFontWeight = B.LabelFontWeight)
    and (A.HighlightFill = B.HighlightFill) and (A.LabelHighlight = B.LabelHighlight)
    and (A.MapAreaFill = B.MapAreaFill);
end;

function TTyGeo.Draw(const AInk: TTyGeoInk; APPI: Integer): TTyGeoDraw;
begin
  if FIsSvg then
  begin
    { [F6b] the SVG's picture per node; the roam moves only the transforms }
    if not (FDrawOk and (FDrawPPI = APPI) and SameInk(FDrawInk, AInk)) then
    begin
      SvgPicture(AInk);
      FDraw := Default(TTyGeoDraw);
      DrawRoamUnits(Self, FDraw);
      if FSpec.Clip then
      begin
        FDraw.HasClip := True;
        FDraw.Clip := ViewRect;
      end;
      FDrawOk := True;
      FDrawPPI := APPI;
      FDrawInk := AInk;
      FDrawRoamGen := FRoamGen;
      FItemsOk := True;
    end;
    if (FSvgGlobalGen <> FRoamGen) or (Length(FSvgGlobal) <> Length(FSvg.Nodes)) then
    begin
      SvgGlobals;
      DrawRoamUnits(Self, FDraw);
    end;
    Exit(FDraw);
  end;
  if not (FDrawOk and (FDrawPPI = APPI) and SameInk(FDrawInk, AInk)) then
  begin
    FDraw := TyGeoDrawOf(Self, AInk, APPI);
    FDrawOk := True;
    FDrawPPI := APPI;
    FDrawInk := AInk;
    FDrawRoamGen := FRoamGen;
    { the state records are made of the picture: again, the flags kept }
    FItemsOk := False;
  end
  else if FDrawRoamGen <> FRoamGen then
  begin
    { [Batch 150] a roam moved the transform group: the same elements,
      their states untouched -- only what hangs on the roam again }
    TyGeoDrawReroam(Self, FDraw, APPI);
    FDrawRoamGen := FRoamGen;
  end;
  Result := FDraw;
end;

procedure StPaintColour(var AObj: TTyStObject; AKey: TTyStKey;
  ASrc: TTyGeoInkSource; AColour: TTyChartColor);
begin
  if ASrc = gisNone then TyStSetNone(AObj, AKey)
  else TyStSetColor(AObj, AKey, AColour);
end;

{ applyOptionStyleForRegion's states as States.pas holds them: the path
  with echarts' default state proxy (setDefaultStateProxy -- whatever
  emphasis.disabled says), all three state objects there; its text the
  same, its rest z2 the host's plus two (updateZ) }
procedure TTyGeo.InitItems;
var
  g, k: Integer;
  s: TTyStName;
  p: TTyGeoDrawPath;
  it: TTyStItem;
  o: TTyStObject;
  sp: TTyGeoPaint;
  ls: TTyGeoLabelState;
begin
  FItemsOk := True;
  EnsureGroups;
  for g := 0 to High(FSt) do
  begin
    if g > High(FDraw.Groups) then
    begin
      FSt[g].Items := nil;
      Continue;
    end;
    SetLength(FSt[g].Items, Length(FDraw.Groups[g].Paths));
    for k := 0 to High(FDraw.Groups[g].Paths) do
    begin
      p := FDraw.Groups[g].Paths[k];
      it := Default(TTyStItem);
      it.Host.Exists := True;
      it.Host.IsPath := True;
      it.Host.Proxy := True;
      for s := Low(TTyStName) to High(TTyStName) do it.Host.HasState[s] := True;
      o := TyStNoObject;
      StPaintColour(o, stkFill, p.Paint.FillSrc, p.Paint.Fill);
      StPaintColour(o, stkStroke, p.Paint.StrokeSrc, p.Paint.Stroke);
      TyStSetNum(o, stkLineWidth, p.Paint.LineWidthLogical);
      if p.Paint.HasOpacity then TyStSetNum(o, stkOpacity, p.Paint.Opacity)
      else TyStSetNum(o, stkOpacity, 1);
      TyStSetNum(o, stkZ2, 0);
      TyStSetNum(o, stkIgnore, 0);
      it.Host.Rest := o;
      it.Host.Cur := o;
      for s := Low(TTyStName) to High(TTyStName) do
      begin
        sp := p.StatePaint[s];
        o := TyStNoObject;
        if sp.FillInherit then o.FillInherit := True
        else if sp.FillHas then StPaintColour(o, stkFill, sp.FillSrc, sp.Fill);
        if sp.StrokeHas then StPaintColour(o, stkStroke, sp.StrokeSrc, sp.Stroke);
        if sp.WidthHas then TyStSetNum(o, stkLineWidth, sp.LineWidthLogical);
        if sp.HasOpacity then TyStSetNum(o, stkOpacity, sp.Opacity);
        it.Host.Decl[s] := o;
      end;
      if p.Lbl.Exists then
      begin
        it.Label_.Exists := True;
        it.Label_.Proxy := True;
        for s := Low(TTyStName) to High(TTyStName) do it.Label_.HasState[s] := True;
        o := TyStNoObject;
        TyStSetColor(o, stkFill, p.Lbl.Colour);
        if p.Lbl.HasOpacity then TyStSetNum(o, stkOpacity, p.Lbl.Opacity)
        else TyStSetNum(o, stkOpacity, 1);
        TyStSetNum(o, stkZ2, 2);
        TyStSetNum(o, stkIgnore, Ord(not p.Lbl.Shown));
        it.Label_.Rest := o;
        it.Label_.Cur := o;
        for s := Low(TTyStName) to High(TTyStName) do
        begin
          ls := p.Lbl.States[s];
          o := TyStNoObject;
          if ls.HasColour then
          begin
            if ls.ColourNone then TyStSetNone(o, stkFill)
            else TyStSetColor(o, stkFill, ls.Colour);
          end;
          if ls.HasOpacity then TyStSetNum(o, stkOpacity, ls.Opacity);
          if ls.HasIgnore then TyStSetNum(o, stkIgnore, Ord(ls.Ignore));
          it.Label_.Decl[s] := o;
        end;
      end;
      FSt[g].Items[k] := it;
    end;
  end;
end;

function TTyGeo.ApplyStates(const AInk: TTyGeoInk; APPI: Integer): Boolean;
var g, k: Integer; names: TTyStNames;
begin
  Result := False;
  Draw(AInk, APPI);
  if FIsSvg then
  begin
    { [F6b] updateSelectStatus, then applyElementStates on every node and
      the text of a host whose list changed }
    SvgSyncSelection;
    for k := 0 to High(FSvgEl) do
    begin
      if not FSvgEl[k].Exists then Continue;
      names := TyStTargetStates(FSvgEl[k]);
      if TyStUseStates(FSvgEl[k], names) then
      begin
        Result := True;
        if FSvgHasLabel[k] then TyStUseStates(FSvgLbl[k], names);
        { the host is dirty: its text is placed again }
        if k <= High(FSvgPlace) then FSvgPlace[k].Valid := False;
      end;
    end;
    Exit;
  end;
  if not FItemsOk then InitItems;
  for g := 0 to High(FSt) do
    for k := 0 to High(FSt[g].Items) do
    begin
      { the group's flags are its paths' (traverseUpdateState) }
      FSt[g].Items[k].Host.HoverState := FSt[g].Hover;
      FSt[g].Items[k].Host.Selected := FSt[g].Selected;
      if TyStApplyItem(FSt[g].Items[k]) then Result := True;
    end;
end;

function TTyGeo.PathItem(AGroup, APath: Integer): TTyStItem;
begin
  Result := Default(TTyStItem);
  if (AGroup < 0) or (AGroup > High(FSt)) then Exit;
  if (APath < 0) or (APath > High(FSt[AGroup].Items)) then Exit;
  Result := FSt[AGroup].Items[APath];
end;

{ ==================== SVG maps [F6b] ==================== }

function GsTransOf(const T: TTyGeoTrans): TTyGsTrans;
begin
  Result.X := T.X;
  Result.Y := T.Y;
  Result.ScaleX := T.ScaleX;
  Result.ScaleY := T.ScaleY;
  Result.Rotation := T.Rotation;
  Result.SkewX := T.SkewX;
  Result.SkewY := T.SkewY;
end;

{ Path.getLineScale over a global transform }
function SvgLineScale(AHas: Boolean; const M: TTyMat2D): Double;
begin
  if AHas and (Abs(M[0] - 1) > 1e-10) and (Abs(M[3] - 1) > 1e-10) then
    Result := Sqrt(Abs(M[0] * M[3] - M[2] * M[1]))
  else
    Result := 1;
end;

function TTyGeo.SvgNodeItem(ANode: Integer): TTyStElement;
begin
  if (ANode >= 0) and (ANode <= High(FSvgEl)) then Result := FSvgEl[ANode]
  else Result := Default(TTyStElement);
end;

function TTyGeo.SvgLabelItem(ANode: Integer): TTyStElement;
begin
  if (ANode >= 0) and (ANode <= High(FSvgLbl)) then Result := FSvgLbl[ANode]
  else Result := Default(TTyStElement);
end;

function TTyGeo.SvgHasLabel(ANode: Integer): Boolean;
begin
  Result := (ANode >= 0) and (ANode <= High(FSvgHasLabel)) and FSvgHasLabel[ANode];
end;

function TTyGeo.SvgLook(ANode: Integer): TTyGeoSvgLook;
begin
  if (ANode >= 0) and (ANode <= High(FSvgLook)) then Result := FSvgLook[ANode]
  else Result := Default(TTyGeoSvgLook);
end;

function TTyGeo.SvgLabelOf(ANode: Integer): TTyGeoLabel;
begin
  if SvgHasLabel(ANode) then Result := FSvgLabel[ANode]
  else Result := Default(TTyGeoLabel);
end;

function TTyGeo.SvgGlobal(ANode: Integer; out AM: TTyMat2D): Boolean;
begin
  Result := (ANode >= 0) and (ANode <= High(FSvgHasGlobal)) and FSvgHasGlobal[ANode];
  if Result then AM := FSvgGlobal[ANode] else AM := MatIdentity;
end;

function TTyGeo.SvgEventGroup(ANode: Integer): Integer;
begin
  if (ANode >= 0) and (ANode <= High(FSvgEvent)) then Result := FSvgEvent[ANode]
  else Result := -1;
end;

function TTyGeo.SvgHoverGroup(ANode: Integer): Integer;
begin
  if (ANode >= 0) and (ANode <= High(FSvgHover)) then Result := FSvgHover[ANode]
  else Result := -1;
end;

procedure TTyGeo.SetSvgPointer(ANode: Integer);
var k: Integer;
begin
  { the outermost self-named dispatcher over the node: findEventDispatcher's
    highDownDispatcher, walked up from the element hit }
  FSvgPointer := -1;
  k := ANode;
  while (k >= 0) and (k <= High(FSvgSelf)) do
  begin
    if FSvgIsDisp[k] and (FSvgSelf[k] >= 0) then FSvgPointer := k;
    k := FSvg.Nodes[k].Parent;
  end;
end;

{ updateTransform down the tree: the transform group (the roam), the SVG
  group (the raw), the extra root, the parsed root and the document's
  elements -- an ignored node and all under it never updated }
procedure TTyGeo.SvgGlobals;
var
  n, i, p: Integer;
  hasP, hp: Boolean;
  pm, ppm, lm: TTyMat2D;
begin
  n := Length(FSvg.Nodes);
  SetLength(FSvgGlobal, n);
  SetLength(FSvgHasGlobal, n);
  SetLength(FSvgReached, n);
  FSvgGlobalGen := FRoamGen;
  hasP := HasRoamTransform;
  pm := MatIdentity;
  if hasP then pm := RoamMatrix;
  if TyGsNeedLocal(GsTransOf(FRaw)) then
  begin
    lm := TyGeoLocalTransform(FRaw);
    if hasP then pm := TyGeoMatMul(pm, lm) else pm := lm;
    hasP := True;
  end;
  for i := 0 to n - 1 do
  begin
    FSvgHasGlobal[i] := False;
    FSvgGlobal[i] := MatIdentity;
    p := FSvg.Nodes[i].Parent;
    FSvgReached[i] := not FSvg.Nodes[i].Ignore and ((p < 0) or FSvgReached[p]);
    if not FSvgReached[i] then Continue;
    if p >= 0 then
    begin
      hp := FSvgHasGlobal[p];
      ppm := FSvgGlobal[p];
    end
    else
    begin
      hp := hasP;
      ppm := pm;
    end;
    if TyGsNeedLocal(FSvg.Nodes[i].T) then
    begin
      lm := TyGsLocal(FSvg.Nodes[i].T);
      if hp then FSvgGlobal[i] := TyGeoMatMul(ppm, lm) else FSvgGlobal[i] := lm;
      FSvgHasGlobal[i] := True;
    end
    else if hp then
    begin
      FSvgGlobal[i] := ppm;
      FSvgHasGlobal[i] := True;
    end;
  end;
end;

function TTyGeo.SvgStrokes: TTyGsStrokeArray;
var i: Integer; c: TTyStObject;
begin
  Result := nil;
  SetLength(Result, Length(FSvg.Nodes));
  for i := 0 to High(Result) do
  begin
    Result[i] := Default(TTyGsStroke);
    Result[i].LineScale := 1;
    if (i > High(FSvgEl)) or not FSvgEl[i].Exists then Continue;
    c := FSvgEl[i].Cur;
    Result[i].LineWidth := c.Num[stkLineWidth];
    Result[i].HasStroke := TyStHasColour(c, stkStroke) and (c.Num[stkLineWidth] > 0);
    Result[i].HasFill := TyStHasColour(c, stkFill);
    if FSvgLook[i].NoScale and (i <= High(FSvgHasGlobal)) then
      Result[i].LineScale := SvgLineScale(FSvgHasGlobal[i], FSvgGlobal[i]);
  end;
end;

function TTyGeo.SvgNodeRect(ANode: Integer): TTyXYWH;
begin
  Result := TyGsNodeRect(FSvg, ANode, SvgStrokes);
end;

{ the paint the SVG gives a node: its style's keys, the element's default
  where a key is not set }
procedure SvgOwnPaint(const G: TTyGsGraphic; const N: TTyGsNode; var O: TTyStObject;
  var L: TTyGeoSvgLook);

  procedure One(const P: TTyGsPaint; AKey: TTyStKey; const ADefault: string;
    var AGrad: Integer);
  var c: TTyChartColor; s: string;
  begin
    case P.Kind of
      gpUnset:
        if (ADefault <> '') and TyTryParseChartColor(ADefault, c) then TyStSetColor(O, AKey, c)
        else TyStSetNone(O, AKey);
      gpColour:
        begin
          { a colour the canvas cannot read still counts as one for hasFill
            and hasStroke; it draws nothing here }
          s := Trim(P.Colour);
          if not TyTryParseChartColor(s, c) then c := 0;
          TyStSetColor(O, AKey, c);
        end;
      gpGradient:
        begin
          AGrad := P.Grad;
          c := 0;
          if (P.Grad >= 0) and (P.Grad <= High(G.Grads)) and (Length(G.Grads[P.Grad].Stops) > 0) then
            if not TyTryParseChartColor(Trim(G.Grads[P.Grad].Stops[0].Colour), c) then c := 0;
          TyStSetColor(O, AKey, c);
        end;
    else
      TyStSetNone(O, AKey);
    end;
  end;

begin
  One(N.St.Fill, stkFill, TyGsDefaultFill(N.Kind), L.FillGrad);
  One(N.St.Stroke, stkStroke, TyGsDefaultStroke(N.Kind), L.StrokeGrad);
  if N.St.NumHas[gnLineWidth] then TyStSetNum(O, stkLineWidth, N.St.Num[gnLineWidth])
  else if N.Kind = gskImage then TyStSetNum(O, stkLineWidth, NaN)
  else TyStSetNum(O, stkLineWidth, 1);
  if N.St.NumHas[gnOpacity] then TyStSetNum(O, stkOpacity, N.St.Num[gnOpacity])
  else TyStSetNum(O, stkOpacity, 1);
  if N.St.NumHas[gnFillOpacity] then L.FillOpacity := N.St.Num[gnFillOpacity];
  if N.St.NumHas[gnStrokeOpacity] then L.StrokeOpacity := N.St.Num[gnStrokeOpacity];
  L.HasDash := N.St.HasDash;
  L.Dash := Copy(N.St.Dash, 0, Length(N.St.Dash));
end;

{ MapDraw._buildSVG's per-node picture for an ink: every named shape's style
  the option's itemStyle over the SVG's own (setStyle: only what the option
  sets), strokeNoScale, the three state objects and the default proxy, no
  emphasis z2 lift on a named item; the labels of the self-named shapes and
  groups (setLabelStyle: the host gets all three states, the text the host's
  proxy); focus 'self' anywhere: every element a proxy, an emphasis and a
  blur state (_enableBlurEntireSVG). The flags are kept. }
procedure TTyGeo.SvgPicture(const AInk: TTyGeoInk);
var
  n, i, it, g, si: Integer;
  old: array of TTyStElement;
  el, lb: TTyStElement;
  look: TTyGeoSvgLook;
  ropt: TJSONObject;
  o: TTyStObject;
  np, sp: TTyGeoPaint;
  s: TTyStName;
  lbl: TTyGeoLabel;
  ls: TTyGeoLabelState;
  nd: TTyGsNode;
begin
  n := Length(FSvg.Nodes);
  old := nil;
  if Length(FSvgEl) = n then old := Copy(FSvgEl, 0, n);
  SetLength(FSvgEl, n);
  SetLength(FSvgLbl, n);
  SetLength(FSvgLook, n);
  SetLength(FSvgLabel, n);
  SetLength(FSvgHasLabel, n);
  for i := 0 to n - 1 do
  begin
    nd := FSvg.Nodes[i];
    el := Default(TTyStElement);
    lb := Default(TTyStElement);
    if old <> nil then
    begin
      el.HoverState := old[i].HoverState;
      el.Selected := old[i].Selected;
      el.HighByOuter := old[i].HighByOuter;
    end;
    look := Default(TTyGeoSvgLook);
    look.FillGrad := -1;
    look.StrokeGrad := -1;
    look.FillOpacity := 1;
    look.StrokeOpacity := 1;
    it := FSvgItem[i];
    g := -1;
    ropt := nil;
    if it >= 0 then
    begin
      g := GroupIndexOf(FSvg.Named[it].Name);
      ropt := GroupOpt(g);
    end;
    if nd.Kind <> gskGroup then
    begin
      el.Exists := True;
      el.IsPath := not (nd.Kind in [gskTSpan, gskImage]);
      o := TyStNoObject;
      SvgOwnPaint(FSvg, nd, o, look);
      if (it >= 0) and TyGsStyleTag(FSvg.Named[it].Tag) then
      begin
        { applyOptionStyleForRegion }
        look.Styled := True;
        look.NoScale := True;
        np := PaintFor(Self, ropt, -1, AInk, False, g);
        look.Opt := np;
        if np.FillHas then
        begin
          StPaintColour(o, stkFill, np.FillSrc, np.Fill);
          look.FillGrad := -1;
          look.HasOptGrad := np.FillGradient.Kind <> cgkNone;
          look.OptGrad := np.FillGradient;
        end;
        if np.StrokeHas then
        begin
          StPaintColour(o, stkStroke, np.StrokeSrc, np.Stroke);
          look.StrokeGrad := -1;
        end;
        if np.WidthHas then TyStSetNum(o, stkLineWidth, np.LineWidthLogical);
        if np.HasOpacity then TyStSetNum(o, stkOpacity, np.Opacity);
        for s := Low(TTyStName) to High(TTyStName) do
        begin
          sp := PaintFor(Self, ropt, Ord(s), AInk, False);
          look.StateOpt[s] := sp;
          el.Decl[s] := TyStNoObject;
          if sp.FillInherit then el.Decl[s].FillInherit := True
          else if sp.FillHas then StPaintColour(el.Decl[s], stkFill, sp.FillSrc, sp.Fill);
          if sp.StrokeHas then StPaintColour(el.Decl[s], stkStroke, sp.StrokeSrc, sp.Stroke);
          if sp.WidthHas then TyStSetNum(el.Decl[s], stkLineWidth, sp.LineWidthLogical);
          if sp.HasOpacity then TyStSetNum(el.Decl[s], stkOpacity, sp.Opacity);
          el.HasState[s] := True;
        end;
        el.Proxy := True;
      end;
      { enableHoverEmphasis: setDefaultStateProxy on the dispatcher and
        everything under it }
      if FSvgHover[i] >= 0 then el.Proxy := True;
      { z2EmphasisLift 0 on every named item }
      el.NoEmphLift := it >= 0;
      if FSvgFocusSelf then
      begin
        el.Proxy := True;
        el.HasState[stnEmphasis] := True;
        el.HasState[stnBlur] := True;
      end;
      TyStSetNum(o, stkZ2, 0);
      TyStSetNum(o, stkIgnore, 0);
      el.Rest := o;
      el.Cur := o;
    end;
    { resetLabelForRegion on a self-named shape or group }
    FSvgHasLabel[i] := False;
    si := FSvgSelf[i];
    if (si >= 0) and TyGsStateTag(FSvg.Named[si].Tag) then
    begin
      lbl := LabelFor(Self, ropt, FSvg.Named[si].Name, AInk, g);
      if lbl.Exists then
      begin
        FSvgHasLabel[i] := True;
        FSvgLabel[i] := lbl;
        el.Exists := True;
        for s := Low(TTyStName) to High(TTyStName) do el.HasState[s] := True;
        lb.Exists := True;
        { the text takes the host's proxy: setLabelStyle hands it a styled
          shape's, enableHoverEmphasis a dispatcher's (a group's too) }
        lb.Proxy := el.Proxy or (FSvgHover[i] >= 0);
        for s := Low(TTyStName) to High(TTyStName) do lb.HasState[s] := True;
        o := TyStNoObject;
        TyStSetColor(o, stkFill, lbl.Colour);
        if lbl.HasOpacity then TyStSetNum(o, stkOpacity, lbl.Opacity)
        else TyStSetNum(o, stkOpacity, 1);
        TyStSetNum(o, stkZ2, 2);
        TyStSetNum(o, stkIgnore, Ord(not lbl.Shown));
        lb.Rest := o;
        lb.Cur := o;
        for s := Low(TTyStName) to High(TTyStName) do
        begin
          ls := lbl.States[s];
          o := TyStNoObject;
          if ls.HasColour then
          begin
            if ls.ColourNone then TyStSetNone(o, stkFill)
            else TyStSetColor(o, stkFill, ls.Colour);
          end;
          if ls.HasOpacity then TyStSetNum(o, stkOpacity, ls.Opacity);
          if ls.HasIgnore then TyStSetNum(o, stkIgnore, Ord(ls.Ignore));
          lb.Decl[s] := o;
        end;
        if nd.Kind = gskGroup then
        begin
          o := TyStNoObject;
          TyStSetNum(o, stkZ2, 0);
          el.Rest := o;
          el.Cur := o;
        end;
      end;
    end;
    FSvgEl[i] := el;
    FSvgLbl[i] := lb;
    FSvgLook[i] := look;
  end;
  FSvgPlace := nil;
end;

function TTyGeo.SvgGroupHead(AGroup: Integer): Integer;
var i: Integer;
begin
  Result := -1;
  if (AGroup >= 0) and (AGroup <= High(FSvgDisp)) and (Length(FSvgDisp[AGroup]) > 0) then
    Exit(FSvgDisp[AGroup][0]);
  for i := 0 to High(FSvgSelf) do
    if (FSvgSelf[i] >= 0) and (FSvgEvent[i] = AGroup) then Exit(i);
end;

{ traverseUpdateState: the node and every node under it }
procedure TTyGeo.SvgTraverse(ANode, AMode, AValue: Integer);
var i, h: Integer;
begin
  if (ANode < 0) or (ANode > High(FSvgEl)) then Exit;
  h := FSvgEl[ANode].HoverState;
  case AMode of
    cSvgEnterEmph: h := TyStHoverEmphasis;
    cSvgLeaveEmph: if h = TyStHoverEmphasis then h := TyStHoverNormal;
    cSvgEnterBlur: h := TyStHoverBlur;
    cSvgLeaveBlur: if h = TyStHoverBlur then h := TyStHoverNormal;
    cSvgSetHover: h := AValue;
    cSvgSetSel:
      if FSvgEl[ANode].Selected <> (AValue <> 0) then
      begin
        FSvgEl[ANode].Selected := AValue <> 0;
        FSvgChanged := True;
      end;
  end;
  if h <> FSvgEl[ANode].HoverState then
  begin
    FSvgEl[ANode].HoverState := h;
    FSvgChanged := True;
  end;
  for i := 0 to High(FSvg.Nodes[ANode].Children) do
    SvgTraverse(FSvg.Nodes[ANode].Children[i], AMode, AValue);
end;

{ updateSelectStatus: a node with event data (a self-named item) and all
  under it take its name's selection; nothing under it is asked again }
procedure TTyGeo.SvgSyncSelection;

  procedure Walk(ANode: Integer);
  var i, g: Integer;
  begin
    if FSvgSelf[ANode] >= 0 then
    begin
      g := FSvgEvent[ANode];
      if (g >= 0) and (g <= High(FSt)) then SvgTraverse(ANode, cSvgSetSel, Ord(FSt[g].Selected))
      else SvgTraverse(ANode, cSvgSetSel, 0);
      Exit;
    end;
    for i := 0 to High(FSvg.Nodes[ANode].Children) do Walk(FSvg.Nodes[ANode].Children[i]);
  end;

begin
  if Length(FSvg.Nodes) > 0 then Walk(TyGsRootNode);
end;

procedure TTyGeo.SvgSetup;
var
  n, i, k, g, p: Integer;
  d: TJSONData;
  tok: TTyGeoToken;
  strokes: TTyGsStrokeArray;
  c: TTyPointF;
  pt: TTyGeoPt;
begin
  n := Length(FSvg.Nodes);
  FGroupsOk := False;
  EnsureGroups;
  SetLength(FSvgItem, n);
  SetLength(FSvgSelf, n);
  SetLength(FSvgEvent, n);
  SetLength(FSvgHover, n);
  SetLength(FSvgIsDisp, n);
  SetLength(FSvgSilentOpt, n);
  SetLength(FSvgHbo, n);
  for i := 0 to n - 1 do
  begin
    FSvgItem[i] := -1;
    FSvgSelf[i] := -1;
    FSvgIsDisp[i] := False;
    FSvgSilentOpt[i] := -1;
    FSvgHbo[i] := 0;
  end;
  FSvgDisp := nil;
  SetLength(FSvgDisp, Length(FGroupNames));
  FSvgFocusSelf := False;
  for k := 0 to High(FSvg.Named) do
  begin
    i := FSvg.Named[k].Node;
    FSvgItem[i] := k;
    g := GroupIndexOf(FSvg.Named[k].Name);
    { `regionModel.get('silent', true)`: the region option's own }
    d := PathGet(GroupOpt(g), ['silent']);
    if d <> nil then FSvgSilentOpt[i] := Ord(Truthy(d));
    if FSvg.Named[k].From >= 0 then Continue;
    FSvgSelf[i] := k;
    if not TyGsStateTag(FSvg.Named[k].Tag) then Continue;
    { resetStateTriggerForRegion: a high-down dispatcher unless the emphasis
      is disabled; its focus 'self' blurs the whole SVG }
    if (FKind = gkComponent) and (g >= 0) then
    begin
      d := Chain(GroupOpt(g), ['emphasis', 'focus'], tok);
      if (d <> nil) and (d.JSONType = jtString) and (d.AsString = 'self') then
        FSvgFocusSelf := True;
    end;
    if (g >= 0) and not GroupEmphasisDisabled(g) then
    begin
      FSvgIsDisp[i] := True;
      SetLength(FSvgDisp[g], Length(FSvgDisp[g]) + 1);
      FSvgDisp[g][High(FSvgDisp[g])] := i;
    end;
  end;
  { the event group: the innermost self-named item over a node; the hover
    group: the outermost dispatcher (findEventDispatcher keeps the last it
    meets on the way up) }
  for i := 0 to n - 1 do
  begin
    p := FSvg.Nodes[i].Parent;
    if FSvgSelf[i] >= 0 then FSvgEvent[i] := GroupIndexOf(FSvg.Named[FSvgSelf[i]].Name)
    else if p >= 0 then FSvgEvent[i] := FSvgEvent[p]
    else FSvgEvent[i] := -1;
    if (p >= 0) and (FSvgHover[p] >= 0) then FSvgHover[i] := FSvgHover[p]
    else if FSvgIsDisp[i] then FSvgHover[i] := GroupIndexOf(FSvg.Named[FSvgSelf[i]].Name)
    else FSvgHover[i] := -1;
  end;
  SvgGlobals;
  { GeoSVGRegion.calcCenter: asked once, on the normal style of the picture }
  SvgPicture(Default(TTyGeoInk));
  strokes := SvgStrokes;
  for k := 0 to High(FSvgRegionNode) do
  begin
    c := TyGsRegionCentre(FSvg, FSvgRegionNode[k], strokes);
    pt.X := c.X;
    pt.Y := c.Y;
    FSource.FRegions[k].SetCenter(pt);
  end;
  FDrawOk := False;
  FItemsOk := False;
end;

{ updateInnerText of a label host's text: the host's rect (now) through the
  host's transform, 'inside' its centre, the offset and the turn as
  innerTransformable takes them }
function TTyGeo.SvgLabelPlace(ANode, APPI: Integer; out AX, AY, ARot, ATX, ATY: Double): Boolean;
begin
  AX := NaN; AY := NaN; ARot := 0; ATX := NaN; ATY := NaN;
  Result := SvgHasLabel(ANode);
  if not Result then Exit;
  if (ANode > High(FSvgPlace)) or not FSvgPlace[ANode].Valid then SvgPlaceLabel(ANode, APPI);
  AX := FSvgPlace[ANode].AX;
  AY := FSvgPlace[ANode].AY;
  ARot := FSvgPlace[ANode].Rot;
  ATX := FSvgPlace[ANode].TX;
  ATY := FSvgPlace[ANode].TY;
end;

{ updateInnerText, run while the host is dirty: the host's rect -- a group's
  through its children's rects, which zrender has not updated yet that
  frame (their transforms the last frame's; none on the first) -- through
  the host's transform, 'inside' its centre, the offset and the turn }
procedure TTyGeo.SvgPlaceLabel(ANode, APPI: Integer);
var
  lbl: TTyGeoLabel;
  c: TTyStObject;
  r: TTyXYWH;
  m: TTyMat2D;
  scale, offX, offY, ox, oy, m4, m5, t4, sn, cs, AX, AY, ARot: Double;
  hasOff: Boolean;
  s: TTyStName;
  strokes: TTyGsStrokeArray;
  k: Integer;
begin
  if Length(FSvgPlace) <> Length(FSvg.Nodes) then SetLength(FSvgPlace, Length(FSvg.Nodes));
  FSvgPlace[ANode] := Default(TTyGeoSvgPlace);
  if not SvgHasLabel(ANode) then Exit;
  if APPI > 0 then scale := APPI / 96 else scale := 1;
  lbl := FSvgLabel[ANode];
  strokes := SvgStrokes;
  if FSvg.Nodes[ANode].Kind = gskGroup then
    for k := 0 to High(strokes) do
      if (k <> ANode) and FSvgLook[k].NoScale then
      begin
        if (k <= High(FSvgPrevHas)) and FSvgPrevHas[k] then
          strokes[k].LineScale := SvgLineScale(True, FSvgPrevGlobal[k])
        else
          strokes[k].LineScale := 1;
      end;
  r := TyGsNodeRect(FSvg, ANode, strokes);
  if SvgGlobal(ANode, m) then r := TyGsRectApply(r, m);
  { calculateTextPosition 'inside' }
  AX := r.X + r.W / 2;
  AY := r.Y + r.H / 2;
  offX := 0;
  offY := 0;
  hasOff := lbl.HasOffset;
  if lbl.HasOffset then
  begin
    offX := lbl.OffX;
    offY := lbl.OffY;
  end;
  if lbl.HasRotate then ARot := lbl.RotationRad;
  c := FSvgLbl[ANode].Cur;
  for s := Low(TTyStName) to High(TTyStName) do
  begin
    if not (s in FSvgLbl[ANode].States) then Continue;
    if lbl.States[s].HasOffset then
    begin
      hasOff := True;
      offX := lbl.States[s].OffX;
      offY := lbl.States[s].OffY;
    end;
    if lbl.States[s].HasRotate then ARot := lbl.States[s].RotationRad;
  end;
  if c.Has[stkZ2] then ;
  offX := offX * scale;
  offY := offY * scale;
  if hasOff then
  begin
    AX := AX + offX;
    AY := AY + offY;
    ox := -offX;
    oy := -offY;
  end
  else
  begin
    ox := 0;
    oy := 0;
  end;
  if (ox <> 0) or (oy <> 0) then
  begin
    m4 := -ox;
    m5 := -oy;
  end
  else
  begin
    m4 := 0;
    m5 := 0;
  end;
  if ARot <> 0 then
  begin
    sn := TyJsSin(ARot);
    cs := TyJsCos(ARot);
    t4 := cs * m4 + sn * m5;
    m5 := cs * m5 - sn * m4;
    m4 := t4;
  end;
  FSvgPlace[ANode].Valid := True;
  FSvgPlace[ANode].AX := AX;
  FSvgPlace[ANode].AY := AY;
  FSvgPlace[ANode].Rot := ARot;
  FSvgPlace[ANode].TX := m4 + (ox + AX);
  FSvgPlace[ANode].TY := m5 + (oy + AY);
end;

function TTyGeo.SvgSaveFlags: TTyGeoSvgFlags;
var i: Integer;
begin
  Result := Default(TTyGeoSvgFlags);
  if not FIsSvg or (Length(FSvgEl) = 0) then Exit;
  Result.Valid := True;
  Result.MapName := FSpec.MapName;
  Result.Count := Length(FSvgEl);
  SetLength(Result.Hover, Result.Count);
  SetLength(Result.Hbo, Result.Count);
  for i := 0 to Result.Count - 1 do
  begin
    Result.Hover[i] := FSvgEl[i].HoverState;
    if i <= High(FSvgHbo) then Result.Hbo[i] := FSvgHbo[i];
  end;
  Result.Blured := FIsBlured;
  Result.Prev := Copy(FSvgPrevGlobal, 0, Length(FSvgPrevGlobal));
  Result.PrevHas := Copy(FSvgPrevHas, 0, Length(FSvgPrevHas));
end;

procedure TTyGeo.SvgRestoreFlags(const AFlags: TTyGeoSvgFlags);
var i: Integer;
begin
  if not (AFlags.Valid and FIsSvg and (AFlags.MapName = FSpec.MapName)
    and (AFlags.Count = Length(FSvgEl)) and (Length(FSvgHbo) = AFlags.Count)) then Exit;
  for i := 0 to AFlags.Count - 1 do
  begin
    FSvgEl[i].HoverState := AFlags.Hover[i];
    FSvgHbo[i] := AFlags.Hbo[i];
  end;
  FIsBlured := AFlags.Blured;
  FSvgPrevGlobal := Copy(AFlags.Prev, 0, Length(AFlags.Prev));
  FSvgPrevHas := Copy(AFlags.PrevHas, 0, Length(AFlags.PrevHas));
end;

{ the first family of a CSS list, unquoted }
function SvgFamily(const S: string): string;
var p: Integer;
begin
  Result := S;
  p := Pos(',', Result);
  if p > 0 then Result := Copy(Result, 1, p - 1);
  Result := Trim(Result);
  if (Length(Result) >= 2) and (Result[1] in ['''', '"']) then
    Result := Copy(Result, 2, Length(Result) - 2);
end;

function SvgWeight(const S: string): Integer;
var v: Double;
begin
  Result := 400;
  if (S = 'bold') or (S = 'bolder') then Exit(700);
  if S = 'lighter' then Exit(300);
  v := TyJsToNumber(S);
  if not IsNan(v) and (v > 0) then Result := Round(v);
end;

{ the elements of an SVG map: every node under the root in the order
  zrender's storage adds them -- a group's children, then a host's text --
  with the current state values, the global transforms, upstream's own
  contain, the root's clip (the bounding rect) and the geo's }
function TyBuildGeoSvg(AGeo: TTyGeo; const AInk: TTyGeoInk;
  const AMeasurer: ITyTextMeasurer; APPI: Integer; AList: TTyPaintList;
  AApplyStates: Boolean): Integer;
var
  scale: Double;
  clip: TTyXYWH;
  strokes: TTyGsStrokeArray;
  mask: TFpuMask;

  function Datum(ANode: Integer): TTyChartDatumRef;
  var g: Integer;
  begin
    g := AGeo.FSvgEvent[ANode];
    if AGeo.Data.Active then
    begin
      if (g >= 0) and (g <= High(AGeo.Data.Groups)) and (AGeo.Data.Groups[g].Row >= 0) then
        Result := TyChartDatum(AGeo.Data.SeriesIndex, AGeo.Data.Groups[g].Row)
      else
        Result := TyChartNoDatum;
    end
    else if g >= 0 then
    begin
      Result := TyChartComponentDatum(ctkGeo, AGeo.Index, g);
      { the hover's group rides in the raw index: the outermost dispatcher
        over the element, not its own name }
      Result.RawDataIndex := AGeo.FSvgHover[ANode];
    end
    else
      Result := TyChartNoDatum;
  end;

  { silent on the node or any node over it (the region option's own over
    the parser's), or on the whole map }
  function SilentAt(ANode: Integer): Boolean;
  var k: Integer;
  begin
    Result := AGeo.Spec.Silent;
    k := ANode;
    while (k >= 0) and not Result do
    begin
      if AGeo.FSvgSilentOpt[k] >= 0 then Result := AGeo.FSvgSilentOpt[k] = 1
      else Result := AGeo.FSvg.Nodes[k].Silent;
      k := AGeo.FSvg.Nodes[k].Parent;
    end;
  end;

  function WithAlpha(AColour: TTyChartColor; AAlpha: Double): TTyChartColor;
  var a: Integer;
  begin
    if IsNan(AAlpha) or (AAlpha >= 1) then Exit(AColour);
    if AAlpha < 0 then AAlpha := 0;
    a := Round(((AColour shr 24) and $FF) * AAlpha);
    Result := (AColour and $00FFFFFF) or (TTyChartColor(a) shl 24);
  end;

  procedure Finish(var AEl: TTyChartElement; ANode: Integer; AZ2: Double;
    AOwnSilent: Boolean; ALabel: Boolean = False);
  begin
    AEl.ZrHit.SvgNode := ANode + 1;
    AEl.ZrHit.SvgLabel := ALabel;
    AEl.Z := AGeo.Spec.Z;
    AEl.Z2 := Round(AZ2);
    AEl.Silent := AOwnSilent or SilentAt(ANode);
    AEl.Datum := Datum(ANode);
    AEl.HasClip := True;
    AEl.ClipRect := TyRectOfXYWH(clip);
    AEl.ClipHits := True;
    AList.Add(AEl);
    Inc(Result);
  end;

  function SvgGradient(AG, ANode: Integer; const M: TTyMat2D): TTyChartGradient;
  var gr: TTyGsGradient; k: Integer; c: TTyChartColor; det: Double;
  begin
    Result := Default(TTyChartGradient);
    if (AG < 0) or (AG > High(AGeo.FSvg.Grads)) then Exit;
    gr := AGeo.FSvg.Grads[AG];
    if gr.Radial then Result.Kind := cgkRadial else Result.Kind := cgkLinear;
    Result.Global := gr.Global;
    if gr.Global then
    begin
      { the coordinates are the element's own: through its transform }
      Result.X := M[0] * gr.X + M[2] * gr.Y + M[4];
      Result.Y := M[1] * gr.X + M[3] * gr.Y + M[5];
      Result.X2 := M[0] * gr.X2 + M[2] * gr.Y2 + M[4];
      Result.Y2 := M[1] * gr.X2 + M[3] * gr.Y2 + M[5];
      det := Sqrt(Abs(M[0] * M[3] - M[2] * M[1]));
      Result.R := gr.R * det;
    end
    else
    begin
      Result.X := gr.X;
      Result.Y := gr.Y;
      Result.X2 := gr.X2;
      Result.Y2 := gr.Y2;
      Result.R := gr.R;
    end;
    SetLength(Result.Stops, Length(gr.Stops));
    for k := 0 to High(gr.Stops) do
    begin
      Result.Stops[k].Offset := gr.Stops[k].Offset;
      if not TyTryParseChartColor(Trim(gr.Stops[k].Colour), c) then c := 0;
      Result.Stops[k].Color := c;
    end;
    if ANode < 0 then ;
  end;

  procedure EmitShape(ANode: Integer);
  var
    nd: TTyGsNode;
    st: TTyStElement;
    c: TTyStObject;
    look: TTyGeoSvgLook;
    hasM, hasStroke, hasFill: Boolean;
    m, inv: TTyMat2D;
    cmds: TTyPathCmdArray;
    pts: TTyPointFArray;
    el: TTyChartElement;
    shape: TTyChartShape;
    det, lw, ls, w, x, y: Double;
    box, r: TTyXYWH;
    k: Integer;
    sn: TTyStName;
    dash: TTyOptDash;
    dashLogical: TTyDoubleArray;
    optDash: Boolean;
    q: array[0..3] of TTyPointF;
  begin
    nd := AGeo.FSvg.Nodes[ANode];
    st := AGeo.FSvgEl[ANode];
    c := st.Cur;
    look := AGeo.FSvgLook[ANode];
    hasM := AGeo.SvgGlobal(ANode, m);
    if not TyGeoMatInvert(m, inv) then inv := MatIdentity;
    det := Sqrt(Abs(m[0] * m[3] - m[2] * m[1]));
    case nd.Kind of
      gskTSpan:
        begin
          box := TyGsNodeRect(AGeo.FSvg, ANode, nil);
          r := TyGsRectApply(box, m);
          el := TyChartElement(TyShapeRect(TyRectF(r.X, r.Y, r.X + r.W, r.Y + r.H)));
          if not nd.Invisible and TyStHasColour(c, stkFill) then
          begin
            el.Caption.Text := nd.St.Text;
            el.Caption.FontName := SvgFamily(nd.St.Font.Family);
            el.Caption.FontSizeLogical := TyFontSizeFromPx(nd.St.Font.SizePx * det / scale);
            el.Caption.FontWeight := SvgWeight(nd.St.Font.Weight);
            el.Caption.Colour := WithAlpha(c.Color[stkFill], look.FillOpacity);
            el.Caption.X := m[4];
            el.Caption.Y := m[5];
            if nd.St.StrHas[gsTextAlign] and (nd.St.Str[gsTextAlign] = 'center') then
              el.Caption.AnchorH := tahCentre
            else if nd.St.StrHas[gsTextAlign]
              and ((nd.St.Str[gsTextAlign] = 'right') or (nd.St.Str[gsTextAlign] = 'end')) then
              el.Caption.AnchorH := tahRight
            else
              el.Caption.AnchorH := tahLeft;
            if nd.St.StrHas[gsTextBaseline] and (nd.St.Str[gsTextBaseline] = 'middle') then
              el.Caption.AnchorV := tavMiddle
            else if nd.St.StrHas[gsTextBaseline]
              and ((nd.St.Str[gsTextBaseline] = 'bottom') or (nd.St.Str[gsTextBaseline] = 'alphabetic')
                or (nd.St.Str[gsTextBaseline] = 'ideographic')) then
              el.Caption.AnchorV := tavBottom
            else
              el.Caption.AnchorV := tavTop;
            el.Caption.RotationRad := -TyJsAtan2(m[1], m[0]);
            el.Caption.Truncate := False;
            if TyStHasColour(c, stkStroke) and (c.Num[stkLineWidth] > 0) then
            begin
              el.Caption.StrokeColour := WithAlpha(c.Color[stkStroke], look.StrokeOpacity);
              el.Caption.StrokeWidthLogical := c.Num[stkLineWidth] * det / scale;
            end;
          end;
          el.Style.Alpha := c.Num[stkOpacity];
          el.ZrHit.Active := True;
          el.ZrHit.RectOnly := True;
          el.ZrHit.ToLocal := inv;
          el.ZrHit.Box := box;
        end;
      gskImage:
        begin
          x := nd.St.IX;
          if IsNan(x) or (x = 0) then x := 0;
          y := nd.St.IY;
          if IsNan(y) or (y = 0) then y := 0;
          box := TyGsNodeRect(AGeo.FSvg, ANode, nil);
          q[0] := TyPointF(m[0] * box.X + m[2] * box.Y + m[4], m[1] * box.X + m[3] * box.Y + m[5]);
          q[1] := TyPointF(m[0] * (box.X + box.W) + m[2] * box.Y + m[4], m[1] * (box.X + box.W) + m[3] * box.Y + m[5]);
          q[2] := TyPointF(m[0] * (box.X + box.W) + m[2] * (box.Y + box.H) + m[4],
            m[1] * (box.X + box.W) + m[3] * (box.Y + box.H) + m[5]);
          q[3] := TyPointF(m[0] * box.X + m[2] * (box.Y + box.H) + m[4], m[1] * box.X + m[3] * (box.Y + box.H) + m[5]);
          SetLength(pts, 4);
          for k := 0 to 3 do pts[k] := q[k];
          el := TyChartElement(TyShapePolygon(pts));
          if not nd.Invisible and (Copy(nd.St.Image, 1, 5) = 'data:') and (nd.St.IW > 0) and (nd.St.IH > 0) then
          begin
            el.Style.HasFill := True;
            el.Style.FillColor := 0;
            el.Style.FillPattern.Present := True;
            el.Style.FillPattern.Image := nd.St.Image;
            el.Style.FillPattern.Repetition := 'no-repeat';
            el.Style.FillPattern.HasMatrix := True;
            el.Style.FillPattern.UnitImage := True;
            el.Style.FillPattern.Matrix[0] := m[0] * nd.St.IW / scale;
            el.Style.FillPattern.Matrix[1] := m[1] * nd.St.IW / scale;
            el.Style.FillPattern.Matrix[2] := m[2] * nd.St.IH / scale;
            el.Style.FillPattern.Matrix[3] := m[3] * nd.St.IH / scale;
            el.Style.FillPattern.Matrix[4] := (m[0] * x + m[2] * y + m[4]) / scale;
            el.Style.FillPattern.Matrix[5] := (m[1] * x + m[3] * y + m[5]) / scale;
          end;
          el.Style.Alpha := c.Num[stkOpacity];
          el.ZrHit.Active := True;
          el.ZrHit.RectOnly := True;
          el.ZrHit.ToLocal := inv;
          el.ZrHit.Box := box;
        end;
    else
      begin
        TyGsPathCmds(nd.Path, m, cmds, pts);
        shape := TyShapePolygon(pts);
        shape.Cmds := cmds;
        shape.HitNonZero := True;
        el := TyChartElement(shape);
        hasFill := TyStHasColour(c, stkFill);
        lw := c.Num[stkLineWidth];
        hasStroke := TyStHasColour(c, stkStroke) and (lw > 0);
        if not nd.Invisible then
        begin
          if hasFill then
          begin
            el.Style.HasFill := True;
            el.Style.FillColor := WithAlpha(c.Color[stkFill], look.FillOpacity);
            if not st.Merged.Has[stkFill] then
            begin
              if look.HasOptGrad then el.Style.FillGradient := look.OptGrad
              else if look.FillGrad >= 0 then el.Style.FillGradient := SvgGradient(look.FillGrad, ANode, m);
            end;
          end;
          if hasStroke then
          begin
            el.Style.StrokeColor := WithAlpha(c.Color[stkStroke], look.StrokeOpacity);
            if look.NoScale then w := lw else w := lw * det / scale;
            el.Style.StrokeWidthLogical := w;
            { the dash: the option's (its normal, a state's over it in list
              order) on a named shape, else the SVG's own }
            optDash := look.Styled and look.Opt.DashHas;
            dash := look.Opt.Dash;
            dashLogical := look.Opt.DashLogical;
            if look.Styled then
              for sn := Low(TTyStName) to High(TTyStName) do
                if (sn in st.States) and look.StateOpt[sn].DashHas then
                begin
                  optDash := True;
                  dash := look.StateOpt[sn].Dash;
                  dashLogical := look.StateOpt[sn].DashLogical;
                end;
            if optDash then
              el.Style.DashLogical := TyDashPattern(dash, dashLogical, lw)
            else if look.HasDash and (Length(look.Dash) > 0) then
            begin
              SetLength(el.Style.DashLogical, Length(look.Dash));
              for k := 0 to High(look.Dash) do
                if look.NoScale then el.Style.DashLogical[k] := look.Dash[k]
                else el.Style.DashLogical[k] := look.Dash[k] * det / scale;
            end;
          end;
        end;
        el.Style.Alpha := c.Num[stkOpacity];
        { Path.contain: in the element's own coordinates }
        el.ZrHit.Active := True;
        el.ZrHit.Path := nd.Path;
        el.ZrHit.ToLocal := inv;
        el.ZrHit.Box := TyGsNodeRect(AGeo.FSvg, ANode, strokes);
        el.ZrHit.Fill := hasFill;
        if hasStroke then
        begin
          if look.NoScale then ls := SvgLineScale(hasM, m) else ls := 1;
          if ls > 1e-10 then
          begin
            w := lw;
            if not hasFill then w := JsMax(w, TyGeoStrokeContain);
            el.ZrHit.Stroke := True;
            el.ZrHit.LineWidth := w / ls;
          end;
        end;
      end;
    end;
    Finish(el, ANode, c.Num[stkZ2], False);
  end;

  procedure EmitLabel(ANode: Integer);
  var
    lbl: TTyGeoLabel;
    c: TTyStObject;
    txt, fam: string;
    fsz, fwt: Integer;
    ax, ay, rot, tx, ty, w, h: Double;
    s: TTyStName;
    box: TTyRectF;
    el: TTyChartElement;
  begin
    if AMeasurer = nil then Exit;
    if not AGeo.SvgLabelPlace(ANode, APPI, ax, ay, rot, tx, ty) then Exit;
    lbl := AGeo.FSvgLabel[ANode];
    c := AGeo.FSvgLbl[ANode].Cur;
    txt := lbl.Text;
    fsz := lbl.FontSizeLogical;
    fwt := lbl.FontWeight;
    fam := lbl.FontFamily;
    for s := Low(TTyStName) to High(TTyStName) do
    begin
      if not (s in AGeo.FSvgLbl[ANode].States) then Continue;
      txt := lbl.States[s].Text;
      if lbl.States[s].HasFontSize then fsz := lbl.States[s].FontSizeLogical;
      if lbl.States[s].HasFontWeight then fwt := lbl.States[s].FontWeight;
      if lbl.States[s].HasFontFamily then fam := lbl.States[s].FontFamily;
    end;
    w := 0;
    h := 0;
    if txt <> '' then AMeasurer.MeasureLine(txt, fam, fsz, fwt, w, h);
    if IsNan(tx) or IsNan(ty) then
    begin
      tx := 0;
      ty := 0;
    end;
    box := TyAnchorBox(tx, ty, w, h, tahCentre, tavMiddle);
    el := TyChartElement(TyShapeRect(box));
    el.Caption.Text := txt;
    el.Caption.FontName := fam;
    el.Caption.FontSizeLogical := fsz;
    el.Caption.FontWeight := fwt;
    if TyStHasColour(c, stkFill) then el.Caption.Colour := c.Color[stkFill]
    else el.Caption.Colour := 0;
    el.Caption.X := tx;
    el.Caption.Y := ty;
    el.Caption.AnchorH := tahCentre;
    el.Caption.AnchorV := tavMiddle;
    el.Caption.RotationRad := rot;
    el.Caption.Truncate := False;
    el.Style.Alpha := c.Num[stkOpacity];
    el.Ignore := (c.Num[stkIgnore] <> 0) or (txt = '') or (w <= 0) or (h <= 0)
      or IsNan(ax) or IsNan(ay);
    { a text is silent on its own or under a silent host }
    Finish(el, ANode, c.Num[stkZ2], lbl.Silent, True);
  end;

  procedure Emit(ANode: Integer);
  var i: Integer;
  begin
    if AGeo.FSvg.Nodes[ANode].Ignore then Exit;
    if AGeo.FSvg.Nodes[ANode].Kind = gskGroup then
    begin
      for i := 0 to High(AGeo.FSvg.Nodes[ANode].Children) do
        Emit(AGeo.FSvg.Nodes[ANode].Children[i]);
    end
    else
      EmitShape(ANode);
    if AGeo.SvgHasLabel(ANode) then EmitLabel(ANode);
  end;

var m0: TTyMat2D;
begin
  Result := 0;
  AGeo.Draw(AInk, APPI);
  if AApplyStates then AGeo.ApplyStates(AInk, APPI);
  if Length(AGeo.FSvg.Nodes) = 0 then Exit;
  if APPI > 0 then scale := APPI / 96 else scale := 1;
  mask := MaskFpu;
  try
    { the root's clip: the bounding rect through the root's transform; the
      geo's own clip, the view rect, over it }
    if AGeo.SvgGlobal(TyGsRootNode, m0) then clip := TyGsRectApply(AGeo.FSvg.Rect, m0)
    else clip := AGeo.FSvg.Rect;
    if AGeo.Spec.Clip then
      clip := TyXYWH(Max(clip.X, AGeo.ViewRect.X), Max(clip.Y, AGeo.ViewRect.Y),
        Min(clip.X + clip.W, AGeo.ViewRect.X + AGeo.ViewRect.W) - Max(clip.X, AGeo.ViewRect.X),
        Min(clip.Y + clip.H, AGeo.ViewRect.Y + AGeo.ViewRect.H) - Max(clip.Y, AGeo.ViewRect.Y));
    strokes := AGeo.SvgStrokes;
    if AGeo.FSvgPlaceGen <> AGeo.RoamGen then
    begin
      AGeo.FSvgPlace := nil;
      AGeo.FSvgPlaceGen := AGeo.RoamGen;
    end;
    Emit(TyGsRootNode);
    { this frame's transforms are what the next one's group labels read }
    AGeo.FSvgPrevGlobal := Copy(AGeo.FSvgGlobal, 0, Length(AGeo.FSvgGlobal));
    AGeo.FSvgPrevHas := Copy(AGeo.FSvgHasGlobal, 0, Length(AGeo.FSvgHasGlobal));
  finally
    UnmaskFpu(mask);
  end;
end;

{ ==================== the elements ==================== }

{ the picture as elements: every compound path that draws anything, its
  text straight after it (zrender's storage order: a text follows its
  host), with the current state values -- and the full path Path.contain
  walks, the clip the hit test respects, the datum a pointer names }
{ [F3c] a compound path's PathProxy data: each ring of two points or more a
  Polygon's (moveTo, lineTo, closePath) or a Polyline's (no close) }
function RegionPathData(const ASubs: TTyGeoRingArray; AIsLine: Boolean): TTyDoubleArray;
var
  j, q, n: Integer;
begin
  n := 0;
  for j := 0 to High(ASubs) do
    if Length(ASubs[j]) >= 2 then
    begin
      n := n + Length(ASubs[j]) * 3;
      if not AIsLine then Inc(n);
    end;
  SetLength(Result, n);
  n := 0;
  for j := 0 to High(ASubs) do
  begin
    if Length(ASubs[j]) < 2 then Continue;
    for q := 0 to High(ASubs[j]) do
    begin
      if q = 0 then Result[n] := 1 else Result[n] := 2;
      Result[n + 1] := ASubs[j][q].X;
      Result[n + 2] := ASubs[j][q].Y;
      Inc(n, 3);
    end;
    if not AIsLine then
    begin
      Result[n] := 6;
      Inc(n);
    end;
  end;
end;

function BuildGeoUntagged(AGeo: TTyGeo; const AInk: TTyGeoInk;
  const AMeasurer: ITyTextMeasurer; APPI: Integer; AList: TTyPaintList;
  AApplyStates: Boolean): Integer;
var
  dr: TTyGeoDraw;
  g, k, j, n, q: Integer;
  p: TTyGeoDrawPath;
  it: TTyStItem;
  c: TTyStObject;
  el: TTyChartElement;
  shape: TTyChartShape;
  pts: TTyPointFArray;
  pq: TTyGeoPt;
  w, h, scale, lw, offX, offY, rot, ax, ay, cs, sn, ox, oy, m4, m5, t4: Double;
  hasOff: Boolean;
  minX, minY, maxX, maxY: Double;
  box: TTyRectF;
  cmds, hit: TTyPathCmdArray;
  mask: TFpuMask;
  silentGroup, any: Boolean;
  s: TTyStName;
  dash: TTyOptDash;
  dashLogical: TTyDoubleArray;
  txt, fam: string;
  fsz, fwt: Integer;

  function Tx(AX, AY: Double): TTyGeoPt;
  begin
    if dr.HasTrans then Result := TyGeoApply(dr.Trans, AX, AY)
    else
    begin
      Result.X := AX;
      Result.Y := AY;
    end;
  end;

  { [Batch 152] a group with a series' data is the item's graphic element
    (setItemGraphicEl): the series' datum, the data index the name's }
  function GroupDatum(AGroup: Integer): TTyChartDatumRef;
  var r: Integer;
  begin
    if AGeo.Data.Active and (AGroup <= High(AGeo.Data.Groups)) then
    begin
      r := AGeo.Data.Groups[AGroup].Row;
      Result := TyChartDatum(AGeo.Data.SeriesIndex, r);
    end
    else
      Result := TyChartComponentDatum(ctkGeo, AGeo.Index, AGroup);
  end;

  procedure AddCmd(AKind: TTyPathCmdKind; AX, AY: Double);
  begin
    if n >= Length(hit) then SetLength(hit, n * 2 + 16);
    hit[n] := Default(TTyPathCmd);
    hit[n].Kind := AKind;
    hit[n].X := AX;
    hit[n].Y := AY;
    Inc(n);
  end;

begin
  Result := 0;
  if (AGeo = nil) or (AList = nil) then Exit;
  if AGeo.IsSvg then
  begin
    if AGeo.Valid and AGeo.Spec.Show then
      Result := TyBuildGeoSvg(AGeo, AInk, AMeasurer, APPI, AList, AApplyStates);
    Exit;
  end;
  dr := AGeo.Draw(AInk, APPI);
  { a render applies the states its elements are in (updateStates); a
    roam's patch of a standing list does not -- that waits for the frame
    [Batch 150] }
  if AApplyStates then AGeo.ApplyStates(AInk, APPI);
  if APPI > 0 then scale := APPI / 96 else scale := 1;
  mask := MaskFpu;
  try
    for g := 0 to High(dr.Groups) do
    begin
      { the map's group, then the region's: silent all the way down }
      silentGroup := AGeo.Spec.Silent or (dr.Groups[g].HasSilent and dr.Groups[g].Silent);
      for k := 0 to High(dr.Groups[g].Paths) do
      begin
        p := dr.Groups[g].Paths[k];
        it := AGeo.PathItem(g, k);
        if Length(p.Drawn) > 0 then
        begin
          c := it.Host.Cur;
          { the drawn path through the group's transform }
          SetLength(cmds, Length(p.Drawn));
          SetLength(pts, 0);
          q := 0;
          for j := 0 to High(p.Drawn) do
          begin
            cmds[j] := p.Drawn[j];
            pq := Tx(p.Drawn[j].X, p.Drawn[j].Y);
            cmds[j].X := pq.X;
            cmds[j].Y := pq.Y;
            if p.Drawn[j].Kind <> pckClose then
            begin
              SetLength(pts, q + 1);
              pts[q] := TyPointF(pq.X, pq.Y);
              Inc(q);
            end;
          end;
          if p.IsLine then shape := TyShapePolyline(pts)
          else shape := TyShapePolygon(pts);
          shape.Cmds := cmds;
          el := TyChartElement(shape);
          { the current values (States.pas): a gradient while no state sets
            the fill }
          el.Style.HasFill := TyStHasColour(c, stkFill);
          el.Style.FillColor := c.Color[stkFill];
          if el.Style.HasFill and not it.Host.Merged.Has[stkFill] then
            el.Style.FillGradient := p.Paint.FillGradient;
          lw := 0;
          if TyStHasColour(c, stkStroke) and (c.Num[stkLineWidth] > 0) then
          begin
            el.Style.StrokeColor := c.Color[stkStroke];
            { strokeNoScale: the width does not follow the zoom }
            el.Style.StrokeWidthLogical := c.Num[stkLineWidth];
            { the dash: the normal one, a state's over it in list order }
            dash := p.Paint.Dash;
            dashLogical := p.Paint.DashLogical;
            for s := Low(TTyStName) to High(TTyStName) do
              if (s in it.Host.States) and p.StatePaint[s].DashHas then
              begin
                dash := p.StatePaint[s].Dash;
                dashLogical := p.StatePaint[s].DashLogical;
              end;
            el.Style.DashLogical := TyDashPattern(dash, dashLogical, c.Num[stkLineWidth]);
            { Path.contain's stroke: the width, at least
              strokeContainThreshold where there is no fill }
            lw := c.Num[stkLineWidth] * scale;
            if not el.Style.HasFill then lw := JsMax(lw, TyGeoStrokeContain * scale);
          end;
          el.Style.Alpha := c.Num[stkOpacity];
          el.Z := AGeo.Spec.Z;
          el.Z2 := Round(c.Num[stkZ2]);
          el.Silent := silentGroup;
          el.Datum := GroupDatum(g);
          { [F3c] A MAP SERIES' REGION, for the universal transition: the
            compound path MapDraw makes (every ring of two points or more,
            moveTo, lineTo, closed but a line's) before the roam, and the
            roam's matrix }
          if AGeo.Data.Active and (g <= High(AGeo.Data.Groups))
            and (AGeo.Data.Groups[g].Row >= 0) then
          begin
            el.Anim.Role := carMapRegion;
            el.Anim.Series := AGeo.Data.SeriesIndex;
            el.Anim.Index := AGeo.Data.Groups[g].Row;
            el.Anim.Sub := k;
            el.Anim.Pts := RegionPathData(p.Subs, p.IsLine);
            if dr.HasTrans then
            begin
              for j := 0 to 5 do el.Anim.G[j] := dr.Trans[j];
              el.Anim.G[6] := 1;
            end;
          end;
          if dr.HasClip then
          begin
            el.HasClip := True;
            el.ClipRect := TyRectOfXYWH(dr.Clip);
          end;
          el.ClipHits := True;
          { the hit: every point of every sub-path (Path.contain walks the
            path data, not the drawn folds), inside the stroked box }
          n := 0;
          hit := nil;
          any := False;
          minX := MaxDouble; minY := MaxDouble;
          maxX := -MaxDouble; maxY := -MaxDouble;
          for j := 0 to High(p.Subs) do
          begin
            if Length(p.Subs[j]) < 2 then Continue;
            for q := 0 to High(p.Subs[j]) do
            begin
              pq := Tx(p.Subs[j][q].X, p.Subs[j][q].Y);
              if q = 0 then AddCmd(pckMove, pq.X, pq.Y) else AddCmd(pckLine, pq.X, pq.Y);
              minX := JsMin(minX, pq.X);
              minY := JsMin(minY, pq.Y);
              maxX := JsMax(maxX, pq.X);
              maxY := JsMax(maxY, pq.Y);
              any := True;
            end;
            if not p.IsLine then AddCmd(pckClose, hit[n - Length(p.Subs[j])].X,
              hit[n - Length(p.Subs[j])].Y);
          end;
          SetLength(hit, n);
          el.PathHit.Active := any;
          el.PathHit.Cmds := hit;
          el.PathHit.Fill := el.Style.HasFill;
          el.PathHit.StrokePx := lw;
          if any then
            el.PathHit.Box := TyRectF(minX - lw / 2, minY - lw / 2,
              maxX + lw / 2, maxY + lw / 2);
          AList.Add(el);
          Inc(Result);
        end;
        { THE TEXT, straight after its host: z2 2 over a region at rest }
        if not (p.Lbl.Exists and p.Lbl.HasPos) then Continue;
        if IsNan(p.Lbl.AnchorX) or IsNan(p.Lbl.AnchorY) then Continue;
        if AMeasurer = nil then Continue;
        c := it.Label_.Cur;
        { the normal text style and textConfig, each state of the list over
          them in order }
        txt := p.Lbl.Text;
        fsz := p.Lbl.FontSizeLogical;
        fwt := p.Lbl.FontWeight;
        fam := p.Lbl.FontFamily;
        offX := 0;
        offY := 0;
        rot := 0;
        hasOff := p.Lbl.HasOffset;
        if p.Lbl.HasOffset then
        begin
          offX := p.Lbl.OffX;
          offY := p.Lbl.OffY;
        end;
        if p.Lbl.HasRotate then rot := p.Lbl.RotationRad;
        for s := Low(TTyStName) to High(TTyStName) do
        begin
          if not (s in it.Label_.States) then Continue;
          txt := p.Lbl.States[s].Text;
          if p.Lbl.States[s].HasFontSize then fsz := p.Lbl.States[s].FontSizeLogical;
          if p.Lbl.States[s].HasFontWeight then fwt := p.Lbl.States[s].FontWeight;
          if p.Lbl.States[s].HasFontFamily then fam := p.Lbl.States[s].FontFamily;
          if p.Lbl.States[s].HasOffset then
          begin
            hasOff := True;
            offX := p.Lbl.States[s].OffX;
            offY := p.Lbl.States[s].OffY;
          end;
          if p.Lbl.States[s].HasRotate then rot := p.Lbl.States[s].RotationRad;
        end;
        { updateInnerText: innerTransformable at the position plus the
          offset, its origin minus the offset, turned by the rotation --
          and where getLocalTransform puts the text's own (0, 0), in its
          arithmetic }
        offX := offX * scale;
        offY := offY * scale;
        if hasOff then
        begin
          ax := p.Lbl.AnchorX + offX;
          ay := p.Lbl.AnchorY + offY;
          ox := -offX;
          oy := -offY;
        end
        else
        begin
          ax := p.Lbl.AnchorX;
          ay := p.Lbl.AnchorY;
          ox := 0;
          oy := 0;
        end;
        if (ox <> 0) or (oy <> 0) then
        begin
          m4 := -ox;
          m5 := -oy;
        end
        else
        begin
          m4 := 0;
          m5 := 0;
        end;
        if rot <> 0 then
        begin
          sn := TyJsSin(rot);
          cs := TyJsCos(rot);
          t4 := cs * m4 + sn * m5;
          m5 := cs * m5 - sn * m4;
          m4 := t4;
        end;
        ax := m4 + (ox + ax);
        ay := m5 + (oy + ay);
        w := 0;
        h := 0;
        if txt <> '' then AMeasurer.MeasureLine(txt, fam, fsz, fwt, w, h);
        box := TyAnchorBox(ax, ay, w, h, tahCentre, tavMiddle);
        el := TyChartElement(TyShapeRect(box));
        el.Caption.Text := txt;
        el.Caption.FontName := fam;
        el.Caption.FontSizeLogical := fsz;
        el.Caption.FontWeight := fwt;
        if TyStHasColour(c, stkFill) then el.Caption.Colour := c.Color[stkFill]
        else el.Caption.Colour := 0;
        el.Caption.X := ax;
        el.Caption.Y := ay;
        el.Caption.AnchorH := tahCentre;
        el.Caption.AnchorV := tavMiddle;
        el.Caption.RotationRad := rot;
        el.Caption.Truncate := False;
        el.Style.Alpha := c.Num[stkOpacity];
        el.Z := AGeo.Spec.Z;
        el.Z2 := Round(c.Num[stkZ2]);
        el.Ignore := (c.Num[stkIgnore] <> 0) or (txt = '') or (w <= 0) or (h <= 0);
        { a text is silent on its own or under a silent host }
        el.Silent := p.Lbl.Silent or silentGroup;
        el.Datum := GroupDatum(g);
        if dr.HasClip then
        begin
          el.HasClip := True;
          el.ClipRect := TyRectOfXYWH(dr.Clip);
        end;
        el.ClipHits := True;
        AList.Add(el);
        Inc(Result);
      end;
    end;
  finally
    UnmaskFpu(mask);
  end;
end;

{ [R2-C] every element of the map's transform group carries the group's
  roam transform at rest and the map view's key: an animated merge that
  moves the view tweens the group (MapDraw.draw's
  applyViewCoordSysTransToElement with the model), and a frame carries the
  elements with it }
function TyGeoViewKey(AGeo: TTyGeo): Integer;
begin
  if AGeo.Kind = gkComponent then Result := AGeo.Index + 1
  { a map series' own: its MapView's (the series drawing it) }
  else if AGeo.Data.Active then Result := -(AGeo.Data.SeriesIndex + 1)
  else Result := -(1000000 + AGeo.Index);
end;

function TyBuildGeo(AGeo: TTyGeo; const AInk: TTyGeoInk;
  const AMeasurer: ITyTextMeasurer; APPI: Integer; AList: TTyPaintList;
  AApplyStates: Boolean): Integer;
var
  n0, i: Integer;
  el: TTyChartElement;
  rt: TTyGeoTrans;
begin
  if AList <> nil then n0 := AList.Count else n0 := 0;
  Result := BuildGeoUntagged(AGeo, AInk, AMeasurer, APPI, AList, AApplyStates);
  if (AGeo = nil) or (AList = nil) then Exit;
  rt := AGeo.RoamTrans;
  { a roam that turns or skews is not a scale and a move }
  if (rt.Rotation <> 0) or (rt.SkewX <> 0) or (rt.SkewY <> 0) then Exit;
  for i := n0 to AList.Count - 1 do
  begin
    el := AList.Element(i);
    el.Anim.GeoView := TyGeoViewKey(AGeo);
    el.Anim.VX := rt.X;
    el.Anim.VY := rt.Y;
    el.Anim.VSX := rt.ScaleX;
    el.Anim.VSY := rt.ScaleY;
    AList.SetElement(i, el);
  end;
end;

function TyGeoUnregisteredMaps(AOption: TTyChartOption): TTyGeoMissingMapArray;
var
  i, n: Integer;
  d, g: TJSONData;
  root: TJSONObject;
  name: string;

  procedure Note(const APath, AName: string);
  begin
    SetLength(Result, n + 1);
    Result[n].Path := APath;
    Result[n].MapName := AName;
    Inc(n);
  end;

begin
  Result := nil;
  n := 0;
  if AOption = nil then Exit;
  root := nil;
  if AOption.Root is TJSONObject then root := TJSONObject(AOption.Root);
  for i := 0 to AOption.ComponentCount('geo') - 1 do
  begin
    name := TyGeoSpecOf(AOption, i).MapName;
    if not TyChartMapRegistered(name) then
      Note('geo[' + IntToStr(i) + ']', name);
  end;
  for i := 0 to AOption.ComponentCount('series') - 1 do
  begin
    d := AOption.ComponentAt('series', i);
    if not (d is TJSONObject) then Continue;
    if TJSONObject(d).Get('type', '') <> 'map' then Continue;
    { MapSeries.getHostGeoModel: with a geoIndex the series draws on that
      geo, whose own map was checked above }
    g := TJSONObject(d).Find('geoIndex');
    if (g <> nil) and (g.JSONType <> jtNull) then Continue;
    name := TyGeoSpecOfNode(TJSONObject(d), root, True).MapName;
    if not TyChartMapRegistered(name) then
      Note('series[' + IntToStr(i) + ']', name);
  end;
end;

finalization
  TyChartClearMaps;
  FreeAndNil(GGeoDefaults);
  FreeAndNil(GGeoSvgDefaults);
  FreeAndNil(GMapDefaults);
end.
