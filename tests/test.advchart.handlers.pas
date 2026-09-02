unit test.advchart.handlers;
{$mode objfpc}{$H+}
{ Named handlers and template strings -- what a function-valued option becomes
  when the host cannot run JavaScript. Pure: no painter, no chart, no handle. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint,
     tyControls.AdvChart.Handlers;
type
  TAdvChartHandlersTest = class(TTestCase)
  private
    FCalledWith: Integer;
    function One(const AName, ASeries: string; AValue: Double): TTyChartParams;
    function Two: TTyChartParams;
    { A handler under test. Records what it was handed so the parameter record
      can be asserted from the inside. }
    function Shouty(const AParams: TTyChartParams): string;
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { ---- templates ---- }
    procedure TestSeriesNameAndDataName;
    procedure TestValue;
    procedure TestPercentOnlyWhenThereIsOne;
    procedure TestMultiDimensionValueJoins;
    procedure TestIndexedPlaceholdersPickTheSeries;
    procedure TestIndexPastTheEndExpandsToNothing;
    procedure TestUnknownPlaceholderIsLeftVerbatim;
    procedure TestUnclosedBraceIsLiteralText;
    procedure TestNamedDimension;
    procedure TestIndexedDimension;
    procedure TestNumbersAreLocaleIndependent;
    { ---- the registry ---- }
    procedure TestARegisteredHandlerIsCalled;
    procedure TestRegisteringTwiceReplaces;
    procedure TestUnregister;
    procedure TestAMissingHandlerFailsLoudly;
    procedure TestNamesAreOfferedForCompletion;
    { ---- which is which ---- }
    procedure TestAtPrefixMeansHandlerButAtBracketDoesNot;
    procedure TestPlainTextPassesThrough;
    { ---- v6.1 semantics ---- }
    procedure TestBothDataIndicesAreCarried;
  end;
implementation

procedure TAdvChartHandlersTest.SetUp;
begin
  inherited SetUp;
  TyChartClearFormatters;
  FCalledWith := -1;
end;

procedure TAdvChartHandlersTest.TearDown;
begin
  TyChartClearFormatters;
  inherited TearDown;
end;

function TAdvChartHandlersTest.One(const AName, ASeries: string;
  AValue: Double): TTyChartParams;
begin
  SetLength(Result, 1);
  FillChar(Result[0], SizeOf(Result[0]), 0);
  Result[0].ComponentType := 'series';
  Result[0].SeriesType := 'bar';
  Result[0].SeriesName := ASeries;
  Result[0].Name := AName;
  Result[0].DataIndex := 3;
  Result[0].RawDataIndex := 17;
  SetLength(Result[0].Values, 1);
  Result[0].Values[0] := AValue;
end;

function TAdvChartHandlersTest.Two: TTyChartParams;
begin
  SetLength(Result, 2);
  FillChar(Result[0], SizeOf(Result[0]), 0);
  FillChar(Result[1], SizeOf(Result[1]), 0);
  Result[0].SeriesName := 'Sales';
  Result[0].Name := 'Mon';
  SetLength(Result[0].Values, 1);
  Result[0].Values[0] := 120;
  Result[1].SeriesName := 'Costs';
  Result[1].Name := 'Mon';
  SetLength(Result[1].Values, 1);
  Result[1].Values[0] := 80;
end;

function TAdvChartHandlersTest.Shouty(const AParams: TTyChartParams): string;
begin
  if Length(AParams) > 0 then
    FCalledWith := AParams[0].RawDataIndex;
  Result := 'SHOUTY';
end;

{ ============================ templates ============================ }

procedure TAdvChartHandlersTest.TestSeriesNameAndDataName;
begin
  AssertEquals('Sales / Mon',
               TyChartFormatTemplate('{a} / {b}', One('Mon', 'Sales', 120)));
end;

procedure TAdvChartHandlersTest.TestValue;
begin
  AssertEquals('Mon: 120', TyChartFormatTemplate('{b}: {c}', One('Mon', 'S', 120)));
end;

procedure TAdvChartHandlersTest.TestPercentOnlyWhenThereIsOne;
var p: TTyChartParams;
begin
  p := One('Mon', 'S', 120);
  { Most series have no percentage. Printing a 0 there would be a number the
    chart made up. }
  AssertEquals('no percent', 'Mon: ', TyChartFormatTemplate('{b}: {d}', p));
  p[0].HasPercent := True;
  p[0].Percent := 42.5;
  AssertEquals('with one', 'Mon: 42.5', TyChartFormatTemplate('{b}: {d}', p));
end;

procedure TAdvChartHandlersTest.TestMultiDimensionValueJoins;
var p: TTyChartParams;
begin
  p := One('P', 'S', 0);
  SetLength(p[0].Values, 2);
  p[0].Values[0] := 10;
  p[0].Values[1] := 20.5;
  AssertEquals('10, 20.5', TyChartFormatTemplate('{c}', p));
end;

procedure TAdvChartHandlersTest.TestIndexedPlaceholdersPickTheSeries;
begin
  { This is what an axis-triggered tooltip is for: several series at one
    category, addressed by index. }
  AssertEquals('Sales: 120 / Costs: 80',
               TyChartFormatTemplate('{a0}: {c0} / {a1}: {c1}', Two));
end;

procedure TAdvChartHandlersTest.TestIndexPastTheEndExpandsToNothing;
begin
  { An axis tooltip whose series list is shorter than the author expected. The
    rest of the line has to stay readable, so the placeholder expands to
    nothing rather than leaking '{a5}' into the tooltip -- which would happen
    legitimately whenever the series count varies at run time.

    HONEST LIMIT: this test pins the BEHAVIOUR but cannot prove the guard is
    what produces it. Removing the bounds check does not give a different
    answer, it reads past the end of a dynamic array -- undefined behaviour that
    happened to look the same here. Mutation confirmed it survives. Making it
    observable would need range checking, which no unit in this repo turns on,
    or trading the right behaviour for a testable one. }
  AssertEquals('Sales: 120 / : ',
               TyChartFormatTemplate('{a0}: {c0} / {a5}: {c5}', Two));
end;

procedure TAdvChartHandlersTest.TestUnknownPlaceholderIsLeftVerbatim;
begin
  { Deleting it would make a typo invisible. Leaving it shows the author exactly
    what did not expand. }
  AssertEquals('Mon {zz} {bb}',
               TyChartFormatTemplate('{b} {zz} {bb}', One('Mon', 'S', 1)));
end;

procedure TAdvChartHandlersTest.TestUnclosedBraceIsLiteralText;
begin
  AssertEquals('Mon {oops',
               TyChartFormatTemplate('{b} {oops', One('Mon', 'S', 1)));
end;

procedure TAdvChartHandlersTest.TestNamedDimension;
var p: TTyChartParams;
begin
  p := One('P', 'S', 0);
  SetLength(p[0].Values, 2);
  p[0].Values[0] := 3;
  p[0].Values[1] := 99;
  SetLength(p[0].DimensionNames, 2);
  p[0].DimensionNames[0] := 'qty';
  p[0].DimensionNames[1] := 'price';
  AssertEquals('price 99', TyChartFormatTemplate('price {@price}', p));
  AssertEquals('qty 3', TyChartFormatTemplate('qty {@qty}', p));
end;

procedure TAdvChartHandlersTest.TestIndexedDimension;
var p: TTyChartParams;
begin
  p := One('P', 'S', 0);
  SetLength(p[0].Values, 3);
  p[0].Values[0] := 1; p[0].Values[1] := 2; p[0].Values[2] := 3;
  AssertEquals('3', TyChartFormatTemplate('{@[2]}', p));
  { Past the end is not a placeholder this can expand, so it stays verbatim
    rather than becoming an empty string that hides the mistake. }
  AssertEquals('{@[9]}', TyChartFormatTemplate('{@[9]}', p));
end;

procedure TAdvChartHandlersTest.TestNumbersAreLocaleIndependent;
var
  saved: TFormatSettings;
begin
  { ECharts always writes '.', and so must this: the same option text has to
    produce the same chart whatever the machine's regional settings say.

    The locale is actually CHANGED for the duration, because asserting '1234.5'
    on a machine that already uses '.' proves nothing -- it passes whether or
    not the code pins the separator. Mutation caught exactly that: removing the
    pin left this test green. }
  AssertEquals('no trailing zeros', '7', TyChartNumToStr(7.0));
  AssertEquals('NaN is nothing, not the word', '', TyChartNumToStr(NaN));
  saved := DefaultFormatSettings;
  try
    DefaultFormatSettings.DecimalSeparator := ',';
    DefaultFormatSettings.ThousandSeparator := '.';
    AssertEquals('a comma-decimal locale must not reach the output',
                 '1234.5', TyChartNumToStr(1234.5));
  finally
    DefaultFormatSettings := saved;
  end;
  AssertEquals('and the locale was put back', '1234.5', TyChartNumToStr(1234.5));
end;

{ ============================ the registry ============================ }

procedure TAdvChartHandlersTest.TestARegisteredHandlerIsCalled;
var
  txt: string;
begin
  TyChartRegisterFormatter('Shouty', @Self.Shouty);
  AssertTrue('resolved', TyChartResolveText('@Shouty', One('Mon', 'S', 1), txt));
  AssertEquals('SHOUTY', txt);
end;

procedure TAdvChartHandlersTest.TestRegisteringTwiceReplaces;
var
  names: TStringList;
begin
  { A design-time form reopened must not accumulate stale handlers. }
  TyChartRegisterFormatter('X', @Self.Shouty);
  TyChartRegisterFormatter('X', @Self.Shouty);
  names := TStringList.Create;
  try
    TyChartFormatterNames(names);
    AssertEquals('one entry', 1, names.Count);
  finally
    names.Free;
  end;
end;

procedure TAdvChartHandlersTest.TestUnregister;
var
  h: TTyChartFormatter;
begin
  TyChartRegisterFormatter('X', @Self.Shouty);
  AssertTrue('there', TyChartFindFormatter('X', h));
  TyChartUnregisterFormatter('X');
  AssertFalse('gone', TyChartFindFormatter('X', h));
end;

procedure TAdvChartHandlersTest.TestAMissingHandlerFailsLoudly;
var
  txt: string;
begin
  { A formatter that silently does nothing is a chart that silently lies, so an
    unknown name must come back False with a message that names it. }
  AssertFalse('not resolved', TyChartResolveText('@NoSuch', One('Mon', 'S', 1), txt));
  AssertTrue('and the message names it: ' + txt, Pos('NoSuch', txt) > 0);
end;

procedure TAdvChartHandlersTest.TestNamesAreOfferedForCompletion;
var
  names: TStringList;
begin
  TyChartRegisterFormatter('Alpha', @Self.Shouty);
  TyChartRegisterFormatter('Beta', @Self.Shouty);
  names := TStringList.Create;
  try
    TyChartFormatterNames(names);
    AssertEquals(2, names.Count);
    AssertTrue('Alpha', names.IndexOf('Alpha') >= 0);
    AssertTrue('Beta', names.IndexOf('Beta') >= 0);
  finally
    names.Free;
  end;
end;

{ ========================== which is which ========================== }

procedure TAdvChartHandlersTest.TestAtPrefixMeansHandlerButAtBracketDoesNot;
begin
  AssertTrue('a handler reference', TyChartIsHandlerRef('@Name'));
  { '@[0]' is a dimension placeholder body, not a handler name. Confusing the
    two would make a dataset template unusable. }
  AssertFalse('a dimension index', TyChartIsHandlerRef('@[0]'));
  AssertFalse('plain text', TyChartIsHandlerRef('{b}: {c}'));
  AssertFalse('a bare at sign', TyChartIsHandlerRef('@'));
end;

procedure TAdvChartHandlersTest.TestPlainTextPassesThrough;
var txt: string;
begin
  AssertTrue('resolved', TyChartResolveText('Total', One('Mon', 'S', 1), txt));
  AssertEquals('Total', txt);
end;

{ ========================== v6.1 semantics ========================== }

procedure TAdvChartHandlersTest.TestBothDataIndicesAreCarried;
var
  txt: string;
  p: TTyChartParams;
begin
  { ECharts 6.1 changed valueFormatter's second parameter from the
    dataZoom-FILTERED index to the index into the original input data. Carrying
    both from day one costs nothing; adding the distinction once handlers exist
    in user code is the expensive kind of change. }
  p := One('Mon', 'S', 1);
  AssertEquals('the filtered index', 3, p[0].DataIndex);
  AssertEquals('and the original one', 17, p[0].RawDataIndex);
  TyChartRegisterFormatter('Shouty', @Self.Shouty);
  AssertTrue('called', TyChartResolveText('@Shouty', p, txt));
  AssertEquals('a handler receives the raw index, as v6.1 specifies',
               17, FCalledWith);
end;

initialization
  RegisterTest(TAdvChartHandlersTest);
end.
