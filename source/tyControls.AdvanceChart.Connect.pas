unit tyControls.AdvanceChart.Connect;
{$mode objfpc}{$H+}
{ TTyAdvanceChart -- what echarts.connect needs that is not a chart: the map
  from an event back to the action that reproduces it, and the layout of the
  combined export. Read off core/echarts.ts (registerAction's
  connectionEventRevertMap, enableConnect, makeActionFromEvent,
  getConnectedDataURL) and held to the real dist by
  tools/advchart-oracle/connect-link-batch.js. [Batch 141, D8]

  THE REVERT MAP. Every registered action files its NON-REFINED event type
  (the lowercased `event`, or the lowercased action type when the action
  refines its event) under its action type; a chart of a connected group
  that publishes one of those events has the others dispatch the event
  object again, its `type` swapped back. The table below is the full
  build's, in registration order; the fixture carries upstream's own and the
  test compares the two. Events that are not here -- selectchanged (a
  refined event), axisbreakchanged, the mouse events, updated, rendered,
  the legacy pie / map select events -- never travel.

  THE COMBINED EXPORT. Each chart of the group is rendered alone (its own
  options), and the images are placed by their charts' offsets: upstream's
  getBoundingClientRect, which the port answers with the control's
  ClientOrigin -- its place on the screen once it has a window, else its
  place in its top-level form -- in logical px. The canvas spans the union
  of the charts' rects times the ratio; each image goes at its offset times
  the ratio less the union's corner times the ratio (the same products
  upstream takes, so the fractions agree).

  PURE: SysUtils, Math. No painter, no LCL. }
interface
uses
  SysUtils, Math;

{ connectionEventRevertMap: the action type for an event type; '' when the
  event is not one that travels }
function TyConnectActionOf(const AEventType: string): string;
{ the map's size and its entries in registration order (for a test to hold
  it to upstream's) }
function TyConnectEventCount: Integer;
function TyConnectEventAt(AIndex: Integer; out AAction: string): string;

type
  { one chart's place: its offset and size in logical px }
  TTyConnectedRect = record
    Left, Top, Width, Height: Double;
  end;
  TTyConnectedRectArray = array of TTyConnectedRect;

  TTyConnectedLayout = record
    { the target canvas' width and height as upstream gives them to it --
      the products, before the canvas truncates them }
    Width, Height: Double;
    { where each image goes, in canvas px, in the rects' order }
    X, Y: array of Double;
  end;

{ getConnectedDataURL's arithmetic: the union of the rects, scaled by ADpr,
  and each rect's offset in it }
function TyConnectedLayoutOf(const ARects: TTyConnectedRectArray;
  ADpr: Double): TTyConnectedLayout;

implementation

const
  cRevert: array[0..54, 0..1] of string = (
    ('highlight', 'highlight'),
    ('downplay', 'downplay'),
    ('select', 'select'),
    ('unselect', 'unselect'),
    ('toggleselect', 'toggleSelect'),
    ('globalcursortaken', 'takeGlobalCursor'),
    ('magictypechanged', 'changeMagicType'),
    ('dataviewchanged', 'changeDataView'),
    ('restore', 'restore'),
    ('changeaxisorder', 'changeAxisOrder'),
    ('pietoggleselect', 'pieToggleSelect'),
    ('pieselect', 'pieSelect'),
    ('pieunselect', 'pieUnSelect'),
    ('geoselectchanged', 'geoToggleSelect'),
    ('geoselected', 'geoSelect'),
    ('geounselected', 'geoUnSelect'),
    ('georoam', 'geoRoam'),
    ('maptoggleselect', 'mapToggleSelect'),
    ('mapselect', 'mapSelect'),
    ('mapunselect', 'mapUnSelect'),
    ('treeexpandandcollapse', 'treeExpandAndCollapse'),
    ('treeroam', 'treeRoam'),
    ('treemapzoomtonode', 'treemapZoomToNode'),
    ('treemaprender', 'treemapRender'),
    ('treemapmove', 'treemapMove'),
    ('treemaproottonode', 'treemapRootToNode'),
    ('focusnodeadjacency', 'focusNodeAdjacency'),
    ('unfocusnodeadjacency', 'unfocusNodeAdjacency'),
    ('graphroam', 'graphRoam'),
    ('axisareaselected', 'axisAreaSelect'),
    ('parallelaxisexpand', 'parallelAxisExpand'),
    ('dragnode', 'dragNode'),
    ('sankeyroam', 'sankeyRoam'),
    ('sunburstroottonode', 'sunburstRootToNode'),
    ('sunbursthighlight', 'sunburstHighlight'),
    ('sunburstunhighlight', 'sunburstUnhighlight'),
    ('updateaxispointer', 'updateAxisPointer'),
    ('datazoom', 'dataZoom'),
    ('showtip', 'showTip'),
    ('hidetip', 'hideTip'),
    ('brush', 'brush'),
    ('brushselected', 'brushSelect'),
    ('brushend', 'brushEnd'),
    ('timelinechanged', 'timelineChange'),
    ('timelineplaychanged', 'timelinePlayChange'),
    ('legendselectchanged', 'legendToggleSelect'),
    ('legendselectall', 'legendAllSelect'),
    ('legendinverseselect', 'legendInverseSelect'),
    ('legendselected', 'legendSelect'),
    ('legendunselected', 'legendUnSelect'),
    ('legendscroll', 'legendScroll'),
    ('datarangeselected', 'selectDataRange'),
    ('expandaxisbreak', 'expandAxisBreak'),
    ('collapseaxisbreak', 'collapseAxisBreak'),
    ('toggleaxisbreak', 'toggleAxisBreak'));

function TyConnectEventCount: Integer;
begin
  Result := Length(cRevert);
end;

function TyConnectEventAt(AIndex: Integer; out AAction: string): string;
begin
  AAction := '';
  Result := '';
  if (AIndex < 0) or (AIndex >= TyConnectEventCount) then Exit;
  Result := cRevert[AIndex, 0];
  AAction := cRevert[AIndex, 1];
end;

function TyConnectActionOf(const AEventType: string): string;
var i: Integer;
begin
  Result := '';
  if AEventType = '' then Exit;
  for i := 0 to TyConnectEventCount - 1 do
    if cRevert[i, 0] = AEventType then Exit(cRevert[i, 1]);
end;

function TyConnectedLayoutOf(const ARects: TTyConnectedRectArray;
  ADpr: Double): TTyConnectedLayout;
var
  l, t, r, b: Double;
  i: Integer;
begin
  Result := Default(TTyConnectedLayout);
  l := Infinity;
  t := Infinity;
  r := -Infinity;
  b := -Infinity;
  { Math.min(boundingRect.left, left) and so on, in the charts' order }
  for i := 0 to High(ARects) do
  begin
    l := Min(ARects[i].Left, l);
    t := Min(ARects[i].Top, t);
    r := Max(ARects[i].Left + ARects[i].Width, r);
    b := Max(ARects[i].Top + ARects[i].Height, b);
  end;
  if Length(ARects) = 0 then Exit;
  l := l * ADpr;
  t := t * ADpr;
  r := r * ADpr;
  b := b * ADpr;
  Result.Width := r - l;
  Result.Height := b - t;
  SetLength(Result.X, Length(ARects));
  SetLength(Result.Y, Length(ARects));
  for i := 0 to High(ARects) do
  begin
    Result.X[i] := ARects[i].Left * ADpr - l;
    Result.Y[i] := ARects[i].Top * ADpr - t;
  end;
end;

end.
