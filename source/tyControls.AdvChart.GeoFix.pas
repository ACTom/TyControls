unit tyControls.AdvChart.GeoFix;
{$mode objfpc}{$H+}
{ The fixes ECharts 6.1 applies to a map REGISTERED UNDER THE NAME 'china'
  (src/coord/geo/fix/nanhai.ts, textCoord.ts, diaoyuIsland.ts), as data.

  THIS IS ENGINE BEHAVIOUR, NOT AN ATLAS. Upstream ships no map; it applies
  these three tables to whatever GeoJSON a host registers as 'china'. A host
  that registers the usual China GeoJSON under that name gets the South China
  Sea islands box appended, the Diaoyu island polygon added to Taiwan and four
  label centres nudged -- and the port must give the same picture, so the
  tables are copied as 6.1 has them, frozen with the version and not kept up
  with any border (spec section 7, Q4b, annotated by batch 146).

  The region names are upstream's own Chinese literals: they are compared
  with the names in the host's data, never shown by this unit. The main
  branch's TI18NTest Chinese-literal guard exempts exactly these strings in
  this file (listed in spec section 185).

  fix/geoCoord.ts (a world-map fix for Russia and the United States) is
  marked DEPRECATED upstream, kept for echarts-gl and never called by 6.1's
  own code: it is not here.

  PURE: Math and the AdvChart types. }
interface

type
  { A point of a map, in the map's own units (longitude, latitude for a
    GeoJSON map). }
  TTyGeoPt = record
    X, Y: Double;
  end;
  TTyGeoRing = array of TTyGeoPt;
  TTyGeoRingArray = array of TTyGeoRing;

const
  { The map name the fixes are keyed on. }
  TyGeoChinaMapName = 'china';
  { The appended region's name (nanhai.ts nanhaiName). }
  TyGeoNanhaiName = '南海诸岛';
  { The region the island polygon is added to (diaoyuIsland.ts). }
  TyGeoDiaoyuHostName = '台湾';

{ fixNanhai's region: twelve exterior rings, already scaled and moved the way
  the module's top level does it once (x / 10.5 + 126, y / (-10.5 / 0.75)
  + 25), and its centre [126, 25]. }
function TyGeoNanhaiRings: TTyGeoRingArray;
function TyGeoNanhaiCentre: TTyGeoPt;

{ fixTextCoord: the offset (in the table's own units) for a region name, or
  False. The caller moves the centre by dx / 10.5 and -dy / (10.5 / 0.75). }
function TyGeoTextOffset(const AName: string; out ADX, ADY: Double): Boolean;

{ fixDiaoyuIsland's polygon (one exterior, no interiors). }
function TyGeoDiaoyuRing: TTyGeoRing;

implementation

type
  TRawPt = array[0..1] of Double;

const
  { nanhai.ts `points`, before the module scales them. }
  cNanhai0: array[0..11] of TRawPt = ((0, 3.5), (7, 11.2), (15, 11.9), (30, 7),
    (42, 0.7), (52, 0.7), (56, 7.7), (59, 0.7), (64, 0.7), (64, 0), (5, 0), (0, 3.5));
  cNanhai1: array[0..4] of TRawPt = ((13, 16.1), (19, 14.7), (16, 21.7), (11, 23.1), (13, 16.1));
  cNanhai2: array[0..4] of TRawPt = ((12, 32.2), (14, 38.5), (15, 38.5), (13, 32.2), (12, 32.2));
  cNanhai3: array[0..4] of TRawPt = ((16, 47.6), (12, 53.2), (13, 53.2), (18, 47.6), (16, 47.6));
  cNanhai4: array[0..4] of TRawPt = ((6, 64.4), (8, 70), (9, 70), (8, 64.4), (6, 64.4));
  cNanhai5: array[0..4] of TRawPt = ((23, 82.6), (29, 79.8), (30, 79.8), (25, 82.6), (23, 82.6));
  cNanhai6: array[0..4] of TRawPt = ((37, 70.7), (43, 62.3), (44, 62.3), (39, 70.7), (37, 70.7));
  cNanhai7: array[0..4] of TRawPt = ((48, 51.1), (51, 45.5), (53, 45.5), (50, 51.1), (48, 51.1));
  cNanhai8: array[0..4] of TRawPt = ((51, 35), (51, 28.7), (53, 28.7), (53, 35), (51, 35));
  cNanhai9: array[0..4] of TRawPt = ((52, 22.4), (55, 17.5), (56, 17.5), (53, 22.4), (52, 22.4));
  cNanhai10: array[0..4] of TRawPt = ((58, 12.6), (62, 7), (63, 7), (60, 12.6), (58, 12.6));
  cNanhai11: array[0..8] of TRawPt = ((0, 3.5), (0, 93.1), (64, 93.1), (64, 0), (63, 0),
    (63, 92.4), (1, 92.4), (1, 3.5), (0, 3.5));

  { diaoyuIsland.ts `points[0]`. }
  cDiaoyu: array[0..4] of TRawPt = (
    (123.45165252685547, 25.73527164402261),
    (123.49731445312499, 25.73527164402261),
    (123.49731445312499, 25.750734064600884),
    (123.45165252685547, 25.750734064600884),
    (123.45165252685547, 25.73527164402261));

  { geoCoord in nanhai.ts }
  cNanhaiX: Double = 126;
  cNanhaiY: Double = 25;
  { Typed, so each division is the one Double division upstream does. }
  cTen5: Double = 10.5;
  cPt75: Double = 0.75;

function Scaled(const A: array of TRawPt): TTyGeoRing;
var k: Integer; d: Double;
begin
  Result := nil;
  SetLength(Result, Length(A));
  { `p[1] /= -10.5 / 0.75`: the divisor is one Double, -14 }
  d := -cTen5 / cPt75;
  for k := 0 to High(A) do
  begin
    Result[k].X := A[k][0] / cTen5;
    Result[k].Y := A[k][1] / d;
    Result[k].X := Result[k].X + cNanhaiX;
    Result[k].Y := Result[k].Y + cNanhaiY;
  end;
end;

function TyGeoNanhaiRings: TTyGeoRingArray;
begin
  Result := nil;
  SetLength(Result, 12);
  Result[0] := Scaled(cNanhai0);
  Result[1] := Scaled(cNanhai1);
  Result[2] := Scaled(cNanhai2);
  Result[3] := Scaled(cNanhai3);
  Result[4] := Scaled(cNanhai4);
  Result[5] := Scaled(cNanhai5);
  Result[6] := Scaled(cNanhai6);
  Result[7] := Scaled(cNanhai7);
  Result[8] := Scaled(cNanhai8);
  Result[9] := Scaled(cNanhai9);
  Result[10] := Scaled(cNanhai10);
  Result[11] := Scaled(cNanhai11);
end;

function TyGeoNanhaiCentre: TTyGeoPt;
begin
  Result.X := cNanhaiX;
  Result.Y := cNanhaiY;
end;

function TyGeoTextOffset(const AName: string; out ADX, ADY: Double): Boolean;
begin
  Result := True;
  { textCoord.ts coordsOffsetMap; its '北京' line is commented out upstream }
  if AName = '南海诸岛' then begin ADX := 32; ADY := 80; end
  else if AName = '广东' then begin ADX := 0; ADY := -10; end
  else if AName = '香港' then begin ADX := 10; ADY := 5; end
  else if AName = '澳门' then begin ADX := -10; ADY := 10; end
  else if AName = '天津' then begin ADX := 5; ADY := 5; end
  else
  begin
    ADX := 0;
    ADY := 0;
    Result := False;
  end;
end;

function TyGeoDiaoyuRing: TTyGeoRing;
var k: Integer;
begin
  Result := nil;
  SetLength(Result, Length(cDiaoyu));
  for k := 0 to High(cDiaoyu) do
  begin
    Result[k].X := cDiaoyu[k][0];
    Result[k].Y := cDiaoyu[k][1];
  end;
end;

end.
