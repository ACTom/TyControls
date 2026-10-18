unit test.advchart.graphdrag2;
{$mode objfpc}{$H+}
{ A GRAPH'S NODE DRAG UNDER THE FORCE LAYOUT'S ANIMATION, AND OFF A VIEW,
  HELD TO UPSTREAM [F3b].

  tools/advchart-oracle/graph-drag2.js runs the real ECharts 6.1 build with
  setTimeout on a frame clock of its own and records, after every step, the
  same snapshot graph-sankey-interact.js does:

    force-anim     `force.layoutAnimation` at its default (true): the render
                   shows the layout after two steps, then a step a frame
                   until the friction cools; a drag while the iteration runs
                   fixes the node where the drift put it (it follows the
                   pointer) and the rest settle around it; a drag after it
                   stopped steps once synchronously first; a drag after a
                   zoom;
    drag-off-view  a graph on cartesian2d: the drift on the canvas, the
                   layout and the edges after it; a node of its own
                   `draggable` under a series that is not.

  The replay is TAdvChartGraphSankeyInteractOracleTest's, on this fixture;
  {frames: n} steps the control's force iterations n times
  (GraphForceFrame). }
interface
uses Classes, SysUtils, fpcunit, testregistry,
     test.advchart.graphsankeyinteract;
type
  TAdvChartGraphDrag2OracleTest = class(TAdvChartGraphSankeyInteractOracleTest)
  protected
    function FixtureName: string; override;
    function MinCases: Integer; override;
    function MinCompared: Integer; override;
  end;

implementation

function TAdvChartGraphDrag2OracleTest.FixtureName: string;
begin
  Result := 'advchart-graph-drag2.json';
end;

function TAdvChartGraphDrag2OracleTest.MinCases: Integer;
begin
  Result := 6;
end;

function TAdvChartGraphDrag2OracleTest.MinCompared: Integer;
begin
  Result := 1500;
end;

initialization
  RegisterTest(TAdvChartGraphDrag2OracleTest);
end.
