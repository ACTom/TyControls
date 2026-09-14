unit test.advchart.hostileoptions;
{$mode objfpc}{$H+}
{ Option values that are legal upstream and used to kill the render.

  Every case below was found by reading the port's JSON readers against the
  ECharts source, and every one was confirmed reachable from the control's own
  rebuild path before it was written down. They are not invented edge cases:
  each is a value ECharts 6.1 accepts and draws.

  WHY THIS IS ONE CLASS AND NOT TWENTY-SEVEN BUGS. Most of them are the same
  sentence in different units: JavaScript's `Math.round` has no domain and
  answers a finite Double for anything finite, while FPC's `Round` targets an
  Int64 and RAISES outside it. A transcription that keeps the shape of the
  upstream line -- `Math.round(x)` becomes `Round(x)` -- is correct for every
  value anybody sane writes and fatal for the ones nobody checks.

  The rest are a second sentence: a JSON reader that establishes a value is
  present does not thereby establish it is a NUMBER, or a SCALAR. A category
  can be an object with a textStyle, a dash pattern can be an array of
  strings, a boundaryGap can be a percentage.

  WHAT THE ASSERTION IS. Not that any of these draws something sensible --
  most of them are nonsense and should draw nothing much. Only that the render
  RETURNS. A chart that cannot honour an option should ignore it or say so; a
  chart that throws out of a paint takes the host's window with it, and no
  amount of `it was a silly value` makes that the library's decision to make. }
interface
uses Classes, SysUtils, Controls, Graphics, Forms, fpcunit, testregistry,
     BGRABitmap, BGRABitmapTypes,
     tyControls.Types, tyControls.Controller,
     tyControls.AdvanceChart, test.advancechart;
type
  TAdvChartHostileOptionTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TChartProbe;
    FBmp: TBGRABitmap;
    procedure SetUp; override;
    procedure TearDown; override;
    procedure RenderIt(const AOption: string);
  published
    procedure TestNoLegalOptionValueKillsTheRender;
  end;

implementation

type
  TCase = record
    Site: string;
    Opt: string;
  end;

const
  { The site each case was found at, so a failure points at the reader rather
    than at the option. }
  cCases: array[0..26] of TCase = (
    (Site: 'Labels.pas:421';
     Opt:
       '{"xAxis":{"type":"category","data":["a","b"]},"yAxis":{},"'
       + 'series":[{"type":"bar","data":[40,90],"label":{"show":true'
       + ',"position":["50%","50%"]}}]}'),
    (Site: 'LabelOpt.pas:224';
     Opt:
       '{"xAxis":{"type":"category","data":["a"]},"yAxis":{},"seri'
       + 'es":[{"type":"bar","data":[1],"label":{"show":true,"fontWe'
       + 'ight":1e+19}}]}'),
    (Site: 'LabelOpt.pas:218';
     Opt:
       '{"xAxis":{"type":"category","data":["a","b"]},"yAxis":{},"'
       + 'series":[{"type":"bar","data":[10,20],"label":{"show":true'
       + ',"fontSize":"14px"}}]}'),
    (Site: 'AdvanceChart.pas:2250';
     Opt:
       '{"series":[{"type":"bar","data":[1,2,3],"label":{"show":tr'
       + 'ue,"rotate":1e+308}}]}'),
    (Site: 'unknown';
     Opt:
       '{"series":[{"type":"pie","startAngle":100000000000000.0,"d'
       + 'ata":[1]}]}'),
    (Site: 'Data.pas:520';
     Opt:
       '{"xAxis":{"type":"time"},"yAxis":{},"series":[{"type":"lin'
       + 'e","data":[["0000-01-01",5]]}]}'),
    (Site: 'Pie.pas:323';
     Opt:
       '{"series":[{"type":"pie","data":[{"value":1},{"value":2}],'
       + '"percentPrecision":1e+19}]}'),
    (Site: 'Series.pas:766';
     Opt:
       '{"xAxis":{"type":"category","data":["A","B"]},"yAxis":{"mi'
       + 'n":0,"max":100,"boundaryGap":["10%","10%"]},"series":[{"ty'
       + 'pe":"line","data":[10,20]}]}'),
    (Site: 'Series.pas:579';
     Opt:
       '{"xAxis":{"type":"category","data":["a","b","c"]},"yAxis":'
       + '{"type":"value","scale":true,"boundaryGap":[0.1,0.1]},"ser'
       + 'ies":[{"type":"line","data":[10,20,30]}]}'),
    (Site: 'LabelOpt.pas:129';
     Opt:
       '{"series":[{"type":"bar","data":[1],"label":{"show":true,"'
       + 'fontSize":1e+20}}]}'),
    (Site: 'Series.pas:766';
     Opt:
       '{"xAxis":{"data":["A","B"]},"yAxis":{"boundaryGap":"50%"},'
       + '"series":[{"type":"line","data":[10,20]}]}'),
    (Site: 'Series.pas:619';
     Opt:
       '{"xAxis":{"splitNumber":1e+19},"yAxis":{},"series":[{"type'
       + '":"line","data":[1,2,3]}]}'),
    (Site: 'unknown';
     Opt:
       '{"xAxis":{"type":"category","data":[0.5,1.5,2.5]},"yAxis":'
       + '{},"series":[{"type":"bar","data":[1,2,3]}]}'),
    (Site: 'Series.pas:626';
     Opt:
       '{"xAxis":{"type":"category","data":["a","b"]},"yAxis":{"ty'
       + 'pe":"value","min":0,"max":1e+19,"interval":1},"series":[{"'
       + 'type":"bar","data":[1,2]}]}'),
    (Site: 'Builder.pas:506';
     Opt:
       '{"xAxis":{"type":"category","data":[{"value":["a","b"],"te'
       + 'xtStyle":{}}]}}'),
    (Site: 'Color.pas:744';
     Opt:
       '{"series":[{"type":"lines","lineStyle":{"type":["5px","10p'
       + 'x"]}}]}'),
    (Site: 'Series.pas:814';
     Opt:
       '{"xAxis":{},"yAxis":{"minorTick":{"show":true,"splitNumber'
       + '":1e+19}},"series":[{"type":"line","data":[[0,1]]}]}'),
    (Site: 'Builder.pas:517';
     Opt:
       '{"xAxis":{"type":"category","data":[["Mon","Tue"],["Wed","'
       + 'Thu"]]},"yAxis":{},"series":[{"type":"bar","data":[1,2]}]}'),
    (Site: 'unknown';
     Opt:
       '{"dataset":{"source":[["id","v"],[1.5,10],[2.5,20]]},"xAxi'
       + 's":{"type":"category"},"yAxis":{},"series":[{"type":"bar",'
       + '"encode":{"itemName":0,"x":0,"y":1}}]}'),
    (Site: 'Builder.pas:506';
     Opt:
       '{"xAxis":{"type":"category","data":[{"value":0.5,"textStyl'
       + 'e":{}},{"value":1.5}]},"yAxis":{},"series":[{"type":"bar",'
       + '"data":[3,4]}]}'),
    (Site: 'Dataset.pas:487';
     Opt:
       '{"dataset":{"source":[["p","v"],["A",1],["B",2]],"sourceHe'
       + 'ader":1e+30},"xAxis":{"type":"category"},"yAxis":{},"serie'
       + 's":[{"type":"bar"}]}'),
    (Site: 'Dataset.pas:681';
     Opt:
       '{"dataset":{"source":[["p","n"],["a",1]]},"xAxis":{"type":'
       + '"category"},"yAxis":{},"series":[{"type":"bar","encode":{"'
       + 'x":1e+30,"y":1}}]}'),
    (Site: 'Dataset.pas:450';
     Opt:
       '{"xAxis":{"type":"category"},"yAxis":{},"dataset":{"series'
       + 'LayoutBy":"row","source":[["a",1,2],["b",3,4]]},"series":['
       + '{"type":"bar","seriesLayoutBy":null}]}'),
    (Site: 'Dataset.pas:440';
     Opt:
       '{"dataset":{"sourceHeader":true,"source":[["product",{"val'
       + 'ue":2015}],["Matcha",43]]},"xAxis":{"type":"category"},"yA'
       + 'xis":{},"series":[{"type":"bar"}]}'),
    (Site: 'Dataset.pas:613';
     Opt:
       '{"dataset":[{"source":[[1,2]]}],"series":[{"type":"bar","d'
       + 'atasetIndex":9223372036854775807}]}'),
    (Site: 'Legend.pas:555';
     Opt:
       '{"legend":{"z":1e+30}}'),
    (Site: 'Dataset.pas:503';
     Opt:
       '{"dataset":{"sourceHeader":true,"source":[["product",2015.'
       + '5],["Matcha",43],["Milk",83]]},"xAxis":{"type":"category"}'
       + ',"yAxis":{},"series":[{"type":"bar"}]}')
  );

procedure TAdvChartHostileOptionTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TChartProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := nil;
end;

procedure TAdvChartHostileOptionTest.TearDown;
begin
  FreeAndNil(FBmp);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartHostileOptionTest.RenderIt(const AOption: string);
begin
  FreeAndNil(FBmp);
  FBmp := TBGRABitmap.Create(420, 260, BGRAWhite);
  FChart.Option := AOption;
  FChart.SetBounds(0, 0, 420, 260);
  FChart.Render(FBmp.Canvas, Rect(0, 0, 420, 260), 96);
end;

procedure TAdvChartHostileOptionTest.TestNoLegalOptionValueKillsTheRender;
var i: Integer; broke: string;
begin
  broke := '';
  for i := Low(cCases) to High(cCases) do
  try
    RenderIt(cCases[i].Opt);
  except
    on E: Exception do
      { COLLECTED, not re-raised at the first. These share two root causes
        between them, so the list is the diagnosis: one name is a bug, a
        column of them is a missing rule. }
      broke := broke + LineEnding + '  ' + cCases[i].Site + ': ' + E.Message;
  end;
  AssertEquals('renders that died:' + broke, '', broke);
end;

initialization
  RegisterTest(TAdvChartHostileOptionTest);
end.
