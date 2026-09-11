unit test.advchart.symbol;
{$mode objfpc}{$H+}
{ The symbol a datum is drawn as.

  ASSERTED AGAINST THE SOURCE'S OWN GEOMETRY. Each of these shapes is a handful
  of vertices, and a triangle whose apex is at the wrong end still looks like a
  triangle -- so the tests state where each vertex goes rather than counting
  them. The numbers come from src/util/symbol.ts: a triangle is apex-up over a
  flat base, a diamond is four midpoints, roundRect's corner is min(w,h)/4, and
  circle takes the SHORTER side so an oblong symbolSize gives a circle rather
  than an ellipse. }
interface
uses
  Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
  tyControls.AdvChart.Types, tyControls.AdvChart.Shape,
  tyControls.AdvChart.Symbol;

type
  TAdvChartSymbolTest = class(TTestCase)
  private
    function SpecFromJson(const AText: string): TTySymbolSpec;
  published
    procedure TestTheNamesAndTheirTwoPrefixes;
    procedure TestTheDefaultsAreUpstreamsAndDifferByType;
    procedure TestTheOptionIsActuallyRead;
    procedure TestACircleTakesTheShorterSide;
    procedure TestTheStraightEdgedShapesPutTheirVerticesWhereUpstreamDoes;
    procedure TestRotationTurnsTheShapeAndOffsetMovesIt;
    procedure TestNoneAndAZeroSizeDrawNothing;
    procedure TestKeepAspectSquaresTheBox;
  end;

implementation

const Eps = 1e-9;

function TAdvChartSymbolTest.SpecFromJson(const AText: string): TTySymbolSpec;
var d: TJSONData;
begin
  d := GetJSON(AText);
  try
    Result := TySymbolSpecOf(TJSONObject(d), TySymbolDefault('scatter'));
  finally
    d.Free;
  end;
end;

procedure TAdvChartSymbolTest.TestTheNamesAndTheirTwoPrefixes;
var
  empty: Boolean;
  path: string;
begin
  AssertEquals(Ord(tsyCircle), Ord(TySymbolKindOf('circle', empty, path)));
  AssertFalse('a plain name is not empty', empty);
  AssertEquals(Ord(tsyRoundRect), Ord(TySymbolKindOf('roundRect', empty, path)));
  AssertEquals(Ord(tsyTriangle), Ord(TySymbolKindOf('triangle', empty, path)));
  AssertEquals(Ord(tsyDiamond), Ord(TySymbolKindOf('diamond', empty, path)));
  AssertEquals(Ord(tsyPin), Ord(TySymbolKindOf('pin', empty, path)));
  AssertEquals(Ord(tsyArrow), Ord(TySymbolKindOf('arrow', empty, path)));
  AssertEquals(Ord(tsyNone), Ord(TySymbolKindOf('none', empty, path)));

  { THE `empty` PREFIX is stripped and the next letter lower-cased, which is
    upstream's own substr(5,1).toLowerCase() + substr(6). }
  AssertEquals(Ord(tsyCircle), Ord(TySymbolKindOf('emptyCircle', empty, path)));
  AssertTrue('and it is remembered', empty);
  AssertEquals(Ord(tsyRoundRect),
    Ord(TySymbolKindOf('emptyRoundRect', empty, path)));
  AssertTrue(empty);

  { `path://` carries its own geometry. }
  AssertEquals(Ord(tsyPath), Ord(TySymbolKindOf('path://M0,0L10,10', empty, path)));
  AssertEquals('the body comes through', 'M0,0L10,10', path);

  { `image://` is refused rather than half-honoured: there is nowhere for an
    image to live in a pure unit, and drawing a stand-in shape would be a
    picture the author did not ask for. }
  AssertEquals(Ord(tsyNone), Ord(TySymbolKindOf('image://x.png', empty, path)));
  { AN UNRECOGNISED NAME IS A RECT, and this assertion used to say the
    opposite -- it pinned the port's own first answer rather than
    upstream's. SymbolClz.buildPath looks the name up in symbolBuildProxies
    and, finding nothing, substitutes 'rect' and draws that. The legend is
    what made it visible: `legend.icon: 'inherit'` on a bar series is
    exactly this path, and ECharts draws a sharp-cornered box there. }
  AssertEquals('an unknown name is a rect', Ord(tsyRect),
    Ord(TySymbolKindOf('wombat', empty, path)));
  { The three that really are nothing: 'none', an empty name, and an image
    URL -- the first two because upstream tests symbolType !== 'none' before
    it ever reaches the proxy table. }
  AssertEquals('but an empty one draws nothing', Ord(tsyNone),
    Ord(TySymbolKindOf('', empty, path)));
  { The `empty` prefix survives an unrecognised body, because createSymbol
    strips and flags it before the table is ever consulted. }
  AssertEquals('and emptyWombat is a rect too', Ord(tsyRect),
    Ord(TySymbolKindOf('emptyWombat', empty, path)));
  AssertTrue('still flagged empty', empty);
end;

procedure TAdvChartSymbolTest.TestTheDefaultsAreUpstreamsAndDifferByType;
begin
  { Two different numbers in two different files, and nothing else writes them
    down: ScatterSeries says 10, LineSeries says 6. A port that picked one for
    both would draw one of the two chart types with the wrong markers. }
  AssertEquals('scatter', 10.0, TySymbolDefault('scatter').WidthPx, Eps);
  AssertEquals('line', 6.0, TySymbolDefault('line').WidthPx, Eps);
  AssertEquals('a circle unless told otherwise', Ord(tsyCircle),
    Ord(TySymbolDefault('scatter').Kind));
  AssertFalse('and not empty', TySymbolDefault('scatter').Empty);
end;

procedure TAdvChartSymbolTest.TestTheOptionIsActuallyRead;
var spec: TTySymbolSpec;
begin
  { THE READER GETS ITS OWN TEST. Building shapes from a hand-made record says
    nothing about whether an option was understood -- that gap let three
    mutants live through the whole line-family batch. }
  spec := SpecFromJson('{ "symbol": "diamond", "symbolSize": 20 }');
  AssertEquals(Ord(tsyDiamond), Ord(spec.Kind));
  AssertEquals(20.0, spec.WidthPx, Eps);
  AssertEquals('one number sizes both sides', 20.0, spec.HeightPx, Eps);

  spec := SpecFromJson('{ "symbolSize": [30, 12] }');
  AssertEquals('a pair is width then height', 30.0, spec.WidthPx, Eps);
  AssertEquals(12.0, spec.HeightPx, Eps);

  spec := SpecFromJson('{ "symbol": "emptyCircle" }');
  AssertTrue('the empty prefix survives the read', spec.Empty);
  AssertEquals(Ord(tsyCircle), Ord(spec.Kind));
  AssertEquals('and the size default is untouched', 10.0, spec.WidthPx, Eps);

  spec := SpecFromJson('{ "symbolRotate": 45, "symbolOffset": [3, -4],'
    + ' "symbolKeepAspect": true }');
  AssertEquals(45.0, spec.RotateDeg, Eps);
  AssertEquals(3.0, spec.OffsetX, Eps);
  AssertEquals(-4.0, spec.OffsetY, Eps);
  AssertTrue(spec.KeepAspect);

  spec := SpecFromJson('{}');
  AssertEquals('nothing said, nothing changed', Ord(tsyCircle), Ord(spec.Kind));
  AssertEquals(0.0, spec.RotateDeg, Eps);
end;

procedure TAdvChartSymbolTest.TestACircleTakesTheShorterSide;
var
  spec: TTySymbolSpec;
  sh: TTyChartShape;
begin
  { AN OBLONG symbolSize GIVES AN ELLIPSE, and this test asserted the opposite
    until the source settled it. A series symbol is built in the UNIT box
    (-1, -1, 2, 2) and the element is then scaled by (symbolSize[0]/2,
    symbolSize[1]/2) -- a NON-UNIFORM scale. So [40, 10] is a 40x10 ellipse on
    screen, not a radius-5 circle inscribed in it.

    The first version of this test read Math.min(w, h) / 2 straight out of the
    shape-maker and never asked what box the shape-maker is given. }
  spec := TySymbolDefault('scatter');
  spec.WidthPx := 40;
  spec.HeightPx := 10;
  sh := TyBuildSymbol(spec, 100, 200);
  AssertEquals('an oblong size is an ellipse', Ord(cskEllipse), Ord(sh.Kind));
  AssertEquals('centred on the datum', 100.0, sh.CX, Eps);
  AssertEquals(200.0, sh.CY, Eps);
  AssertEquals('half the width across', 20.0, sh.R0, Eps);
  AssertEquals('and half the height down', 5.0, sh.R1, Eps);

  { A SQUARE SIZE IS STILL A CIRCLE -- the common case, and the one the shape
    record can say exactly. }
  spec.HeightPx := 40;
  sh := TyBuildSymbol(spec, 100, 200);
  AssertEquals('a square size is a circle', Ord(cskCircle), Ord(sh.Kind));
  AssertEquals(20.0, sh.R1, Eps);
end;

procedure TAdvChartSymbolTest.TestTheStraightEdgedShapesPutTheirVerticesWhereUpstreamDoes;
var
  spec: TTySymbolSpec;
  sh: TTyChartShape;
begin
  spec := TySymbolDefault('scatter');
  spec.WidthPx := 20;
  spec.HeightPx := 10;

  { TRIANGLE: apex up, flat base. moveTo(cx, cy - h/2), lineTo(cx + w/2,
    cy + h/2), lineTo(cx - w/2, cy + h/2). }
  spec.Kind := tsyTriangle;
  sh := TyBuildSymbol(spec, 100, 200);
  AssertEquals(Ord(cskPolygon), Ord(sh.Kind));
  AssertEquals('three vertices', 3, Length(sh.Points));
  AssertEquals('apex above the datum', 195.0, sh.Points[0].Y, Eps);
  AssertEquals('and horizontally centred', 100.0, sh.Points[0].X, Eps);
  AssertEquals('base right', 110.0, sh.Points[1].X, Eps);
  AssertEquals('base is below', 205.0, sh.Points[1].Y, Eps);
  AssertEquals('base left', 90.0, sh.Points[2].X, Eps);

  { DIAMOND: the four midpoints. }
  spec.Kind := tsyDiamond;
  sh := TyBuildSymbol(spec, 100, 200);
  AssertEquals('four vertices', 4, Length(sh.Points));
  AssertEquals(100.0, sh.Points[0].X, Eps);
  AssertEquals(195.0, sh.Points[0].Y, Eps);
  AssertEquals(110.0, sh.Points[1].X, Eps);
  AssertEquals('the right vertex is level with the datum',
    200.0, sh.Points[1].Y, Eps);

  { ROUNDRECT keeps its own kind, with upstream's min(w,h)/4 corner. }
  spec.Kind := tsyRoundRect;
  sh := TyBuildSymbol(spec, 100, 200);
  AssertEquals(Ord(cskRoundRect), Ord(sh.Kind));
  AssertEquals('the corner is a quarter of the shorter side',
    2.5, sh.Radii[0], Eps);

  { SQUARE IS THE SAME AS RECT for a series symbol, which is not obvious and
    is worth pinning. Upstream's square shape-maker does take Math.min(w, h)
    and keep the box's top-left -- but the box it is handed is the UNIT box, so
    the squaring is a no-op and the anchoring never shows. The difference only
    appears where createSymbol gets a real box: legend icons and markPoint. }
  spec.Kind := tsyRect;
  sh := TyBuildSymbol(spec, 100, 200);
  AssertEquals('a rect is as wide as it was asked to be',
    20.0, sh.Points[1].X - sh.Points[0].X, Eps);
  spec.Kind := tsySquare;
  sh := TyBuildSymbol(spec, 100, 200);
  AssertEquals('and so is a square, here', 20.0,
    sh.Points[1].X - sh.Points[0].X, Eps);
  AssertEquals('with the same height too', 10.0,
    sh.Points[2].Y - sh.Points[1].Y, Eps);

  { LINE is the one that is a STROKE: a two-point polyline, not a filled
    shape. }
  spec.Kind := tsyLine;
  sh := TyBuildSymbol(spec, 100, 200);
  AssertEquals(Ord(cskPolyline), Ord(sh.Kind));
  AssertEquals(2, Length(sh.Points));
  AssertEquals('level with the datum', 200.0, sh.Points[0].Y, Eps);
end;

procedure TAdvChartSymbolTest.TestRotationTurnsTheShapeAndOffsetMovesIt;
var
  spec: TTySymbolSpec;
  sh: TTyChartShape;
begin
  spec := TySymbolDefault('scatter');
  spec.Kind := tsyTriangle;
  spec.WidthPx := 20;
  spec.HeightPx := 20;

  { HALF A TURN puts the apex below the datum. This is why every straight-edged
    symbol is built as a polygon: the shape record carries no rotation, so a
    fast path for rects would silently ignore symbolRotate. }
  spec.RotateDeg := 180;
  sh := TyBuildSymbol(spec, 100, 200);
  AssertEquals('the apex is now below', 210.0, sh.Points[0].Y, 1e-6);
  AssertEquals('still centred', 100.0, sh.Points[0].X, 1e-6);

  { AND A QUARTER TURN SAYS WHICH WAY IT TURNS. A half turn cannot: it is its
    own mirror, so a mutant that rotated anticlockwise survived this test until
    ninety degrees was added. Screen y grows downward, so a positive angle
    swings the apex to the RIGHT. }
  spec.RotateDeg := 90;
  sh := TyBuildSymbol(spec, 100, 200);
  AssertEquals('a quarter turn puts the apex to the right',
    110.0, sh.Points[0].X, 1e-6);
  AssertEquals('level with the datum', 200.0, sh.Points[0].Y, 1e-6);

  { OFFSET MOVES, IT DOES NOT TURN. Applied after the rotation, so a rotated
    symbol still shifts the way the author wrote it rather than along its own
    turned axes. }
  spec.RotateDeg := 0;
  spec.OffsetX := 7;
  spec.OffsetY := -3;
  sh := TyBuildSymbol(spec, 100, 200);
  AssertEquals('moved right', 107.0, sh.Points[0].X, 1e-6);
  AssertEquals('and up', 187.0, sh.Points[0].Y, 1e-6);

  { A circle takes the offset too, through its own centre. }
  spec.Kind := tsyCircle;
  sh := TyBuildSymbol(spec, 100, 200);
  AssertEquals(107.0, sh.CX, Eps);
  AssertEquals(197.0, sh.CY, Eps);
end;

procedure TAdvChartSymbolTest.TestNoneAndAZeroSizeDrawNothing;
var
  spec: TTySymbolSpec;
  sh: TTyChartShape;
begin
  { `symbol: 'none'` is a real instruction -- it is how a line asks for no
    markers -- so it answers a shape that draws nothing rather than a circle of
    size zero, which would still be hit-testable. }
  spec := TySymbolDefault('scatter');
  spec.Kind := tsyNone;
  sh := TyBuildSymbol(spec, 100, 200);
  AssertFalse('none draws nothing', TyRectFIsValid(sh.Bounds));

  { ASSERTED ON THE KIND, not only on the box. A circle does not use Bounds at
    all, so "the box is invalid" was true whether or not the size guard fired
    -- the zero-size mutant sailed through it. The "nothing" answer is
    specifically a rect with an invalid box; a circle here means the guard
    did not run. }
  spec.Kind := tsyCircle;
  spec.WidthPx := 0;
  sh := TyBuildSymbol(spec, 100, 200);
  AssertEquals('a zero size draws nothing at all',
    Ord(cskRect), Ord(sh.Kind));
  AssertFalse('with no box to hit-test', TyRectFIsValid(sh.Bounds));

  spec.WidthPx := 10;
  spec.HeightPx := 0;
  sh := TyBuildSymbol(spec, 100, 200);
  AssertEquals('either side of it', Ord(cskRect), Ord(sh.Kind));
end;

procedure TAdvChartSymbolTest.TestKeepAspectSquaresTheBox;
var
  spec: TTySymbolSpec;
  sh: TTyChartShape;
begin
  { symbolKeepAspect DOES NOT REACH A BUILT-IN SYMBOL. createSymbol passes it
    to makePath and makeImage as the bounding-rect fit mode ('center' against
    'cover') and the built-in branch never reads it. This test asserted that it
    squared a triangle's box; that was this port inventing a behaviour, and an
    invisible one -- it only shows when symbolSize is written as a pair. }
  spec := TySymbolDefault('scatter');
  spec.Kind := tsyTriangle;
  spec.WidthPx := 40;
  spec.HeightPx := 10;

  sh := TyBuildSymbol(spec, 100, 200);
  AssertEquals('the box is as given', 40.0,
    sh.Points[1].X - sh.Points[2].X, Eps);

  spec.KeepAspect := True;
  sh := TyBuildSymbol(spec, 100, 200);
  AssertEquals('and keepAspect leaves a built-in alone', 40.0,
    sh.Points[1].X - sh.Points[2].X, Eps);
  AssertEquals('in both directions', 10.0,
    sh.Points[1].Y - sh.Points[0].Y, Eps);
end;

initialization
  RegisterTest(TAdvChartSymbolTest);
end.
