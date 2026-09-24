unit test.advchart.dataset;
{$mode objfpc}{$H+}
{ `dataset` and `encode` -- the table, and which column feeds which coordinate.

  THE FIXTURES ARE ASYMMETRIC ON PURPOSE. Nearly every rule here is about WHICH
  of several things something is keyed on -- an index or a name, a row or a
  column, the first ordinal coordinate or the horizontal axis -- and a table
  whose columns all look alike cannot tell a correct answer from its mirror
  image. So the tables here have columns of visibly different kinds, the row
  and column counts differ, and the series that share a table want different
  things from it.

  THE FIVE THAT A REASONABLE READING GETS WRONG, all upstream's:

    - `sourceHeader: 'auto'` keeps a header only when EVERY examined cell is a
      string. The comment above the code says "most";
    - the default encode is a RUNNING COUNTER shared by the series, not a
      function of the series index -- and a PARTIAL `encode` opts a series out
      of it entirely rather than merging with it;
    - the shared category column is dimension 0 whichever AXIS it is on;
    - a numeric STRING in an encode is a name, not an index;
    - a series with its own `data` ignores the table, and `data: []` counts as
      having its own. }
interface
uses
  Classes, SysUtils, Math, fpjson, fpcunit, testregistry,
  tyControls.AdvChart.Types, tyControls.AdvChart.Option,
  tyControls.AdvChart.Dataset;

type
  TAdvChartDatasetTest = class(TTestCase)
  private
    FOpt: TTyChartOption;
    procedure SetUp; override;
    procedure TearDown; override;
    function Src(const AText: string; AIndex: Integer = 0): TTyChartSource;
    { The cell as text, or '<nil>'. }
    function Cell(const ASource: TTyChartSource; ARow, ADim: Integer): string;
  published
    procedure TestTheShapeIsReadOffTheFirstNonNullItem;
    procedure TestAHeaderIsKeptOnlyWhenEveryCellIsAString;
    procedure TestADashAndANullSayNothingEitherWay;
    procedure TestOnlyTheFirstTenCellsAreExamined;
    procedure TestAnExplicitSourceHeaderOverridesTheGuess;
    procedure TestTheNamesComeOffTheHeaderOnlyWhenThereIsExactlyOneRow;
    procedure TestDeclaredDimensionsWinOverTheHeaderRow;
    procedure TestObjectRowsTakeTheirNamesFromTheFirstRowAndReadByName;
    procedure TestSeriesLayoutByRowTransposesTheTable;
    procedure TestWhichDatasetASeriesReads;
    procedure TestEncodeTakesAnIndexOrANameAndAListMeansItsFirst;
    procedure TestANumericStringIsANameAndNotAnIndex;
    procedure TestAPartialEncodeIsStillAnEncode;
    procedure TestTheValueWayHandsEachSeriesTheNextColumns;
    procedure TestTheCategoryWayGivesEverySeriesColumnZero;
    procedure TestTheCategoryColumnIsZeroWhicheverAxisItIsOn;
    procedure TestTheCursorIsPerDatasetAndPerLayout;
    procedure TestTheNameBasedDefaultPicksANameAndAValue;
    procedure TestADeclaredTypeEndsTheOrdinalQuestion;
    procedure TestASourceWithNoReaderAnswersNothing;
    procedure TestAGivenEncodeFillsWhatItLeavesOut;
    procedure TestASeriesOverrulesTheTableAboutHowToReadIt;
  end;

implementation

procedure TAdvChartDatasetTest.SetUp;
begin
  inherited SetUp;
  FOpt := TTyChartOption.Create;
end;

procedure TAdvChartDatasetTest.TearDown;
begin
  FreeAndNil(FOpt);
  inherited TearDown;
end;

function TAdvChartDatasetTest.Src(const AText: string;
  AIndex: Integer): TTyChartSource;
begin
  AssertTrue('the option parsed: ' + FOpt.Error.Message,
    FOpt.SetOptionText(AText));
  Result := TySourceOf(FOpt, AIndex);
end;

function TAdvChartDatasetTest.Cell(const ASource: TTyChartSource;
  ARow, ADim: Integer): string;
var d: TJSONData;
begin
  d := TySourceCell(ASource, ARow, ADim);
  if d = nil then Exit('<nil>');
  Result := d.AsString;
end;

{ ==================== the shape ==================== }

procedure TAdvChartDatasetTest.TestTheShapeIsReadOffTheFirstNonNullItem;
var arr: TJSONArray;

  function Shape(const AJson: string): TTySourceFormat;
  var d: TJSONData;
  begin
    d := GetJSON(AJson);
    try
      Result := TyDetectSourceFormat(d);
    finally
      d.Free;
    end;
  end;

begin
  { The container's own type first, then the type of the FIRST NON-NULL item --
    and the walk stops there, so a table whose first row is an array and whose
    second is an object is a table of arrays. The mixture is not refused. }
  AssertEquals('rows of arrays', Ord(tsfArrayRows), Ord(Shape('[[1,2],[3,4]]')));
  AssertEquals('rows of objects', Ord(tsfObjectRows), Ord(Shape('[{"a":1}]')));
  AssertEquals('a leading null is skipped', Ord(tsfObjectRows),
    Ord(Shape('[null,{"a":1}]')));
  AssertEquals('and the first non-null wins outright', Ord(tsfArrayRows),
    Ord(Shape('[[1,2],{"a":1}]')));
  { AN EMPTY TABLE IS STILL A TABLE, which upstream says in a comment of its
    own -- it is not `unknown`. }
  AssertEquals('an empty array is a table', Ord(tsfArrayRows), Ord(Shape('[]')));
  { A FLAT ARRAY OF SCALARS HAS NO READER. Upstream throws here; this answers
    unknown and draws nothing, which is the same outcome without the crash. }
  AssertEquals('bare numbers are unreadable', Ord(tsfUnknown),
    Ord(Shape('[1,2,3]')));
  AssertEquals('so are bare strings', Ord(tsfUnknown), Ord(Shape('["a","b"]')));
  AssertEquals('an object of arrays is column-keyed', Ord(tsfKeyedColumns),
    Ord(Shape('{"a":[1,2]}')));
  { A STRING IS NOT ARRAY-LIKE for this purpose, though it has a length. }
  AssertEquals('an object of strings is not', Ord(tsfUnknown),
    Ord(Shape('{"a":"xyz"}')));
  AssertEquals('and nothing at all is nothing', Ord(tsfUnknown),
    Ord(TyDetectSourceFormat(nil)));
  arr := nil;
  if arr <> nil then arr.Free;
end;

procedure TAdvChartDatasetTest.TestAHeaderIsKeptOnlyWhenEveryCellIsAString;
var sc: TTyChartSource;
begin
  { THE COMMENT ABOVE THE CODE SAYS `Most of the first line are string`, and
    the code requires ALL of them: a string sets `header` only when nothing has
    decided yet, while a number sets `no header` unconditionally. One number
    anywhere in the window settles it, wherever it sits. }
  sc := Src('{ "dataset": { "source": [["p","s","a"],["x",1,2]] } }');
  AssertEquals('all strings: a header', 1, sc.StartIndex);
  AssertEquals('and the names come off it', 'p', TySourceDimName(sc, 0));

  sc := Src('{ "dataset": { "source": [["p","s",3],["x",1,2]] } }');
  AssertEquals('one number at the end: no header', 0, sc.StartIndex);
  AssertEquals('and no names', 0, Length(sc.Dims));

  sc := Src('{ "dataset": { "source": [[3,"s","p"],[1,2,"x"]] } }');
  AssertEquals('one number at the START: still no header', 0, sc.StartIndex);
end;

procedure TAdvChartDatasetTest.TestADashAndANullSayNothingEitherWay;
var sc: TTyChartSource;
begin
  { `-` is upstream's spelling of a gap and is skipped, as null is. A line of
    strings with a gap in it is still a header. }
  sc := Src('{ "dataset": { "source": [["p","-","a"],["x",1,2]] } }');
  AssertEquals('a dash does not spoil a header', 1, sc.StartIndex);
  sc := Src('{ "dataset": { "source": [["p",null,"a"],["x",1,2]] } }');
  AssertEquals('nor does a null', 1, sc.StartIndex);

  { AND A LINE OF NOTHING BUT GAPS DECIDES NOTHING, which is the only fixture
    that can see the skip at all: with it, nobody votes and the answer stays
    `no header`; without it, a dash is a string like any other and would vote
    for one. Every other line has something else in it to settle the question
    first. }
  sc := Src('{ "dataset": { "source": [["-","-"],[1,2]] } }');
  AssertEquals('a line of dashes is not a header', 0, sc.StartIndex);
  AssertEquals('and both rows are data', 2, TySourceRowCount(sc));
  { But a gap in the NAMES leaves that dimension nameless rather than called
    `-`: only the header detector skips it, the naming pass reads it. }
  AssertEquals('a null names that dimension nothing', '',
    TySourceDimName(sc, 1));
  { The DASH, on the other hand, is a cell like any other once the header
    detector has finished with it -- it is skipped when deciding whether
    there IS a header and read when naming. }
  sc := Src('{ "dataset": { "source": [["p","-","a"],["x",1,2]] } }');
  AssertEquals('while a dash becomes a name spelled -', '-',
    TySourceDimName(sc, 1));
end;

procedure TAdvChartDatasetTest.TestOnlyTheFirstTenCellsAreExamined;
var sc: TTyChartSource;
begin
  { Ten is upstream's cap and it counts CELLS, not decisions -- so a number in
    the twelfth column of an otherwise-string line is invisible and the line is
    read as a header. Twelve columns, the number last. }
  sc := Src('{ "dataset": { "source": ['
    + '["a","b","c","d","e","f","g","h","i","j","k",9],'
    + '["1","2","3","4","5","6","7","8","9","10","11",12]] } }');
  AssertEquals('the number past the tenth cell is never looked at', 1,
    sc.StartIndex);
  { And the name it produces is the number, stringified. }
  AssertEquals('it still becomes a name', '9', TySourceDimName(sc, 11));
end;

procedure TAdvChartDatasetTest.TestAnExplicitSourceHeaderOverridesTheGuess;
var sc: TTyChartSource;
begin
  sc := Src('{ "dataset": { "sourceHeader": false, '
    + '"source": [["p","s"],["x","y"]] } }');
  AssertEquals('false says there is none, whatever it looks like', 0,
    sc.StartIndex);
  sc := Src('{ "dataset": { "sourceHeader": true, "source": [[1,2],[3,4]] } }');
  AssertEquals('and true says there is one', 1, sc.StartIndex);
  { A NUMBER IS A COUNT OF HEADER LINES, not a boolean. }
  sc := Src('{ "dataset": { "sourceHeader": 2, "source": [[1,2],[3,4],[5,6]] } }');
  AssertEquals('a number skips that many lines', 2, sc.StartIndex);
  AssertEquals('leaving one row of data', 1, TySourceRowCount(sc));
  AssertEquals('', '5', Cell(sc, 0, 0));
end;

procedure TAdvChartDatasetTest.TestTheNamesComeOffTheHeaderOnlyWhenThereIsExactlyOneRow;
var sc: TTyChartSource;
begin
  { `sourceHeader: 2` skips two lines and names NOTHING. It reads like an
    oversight and it is what the code does: the naming pass is gated on
    startIndex being exactly 1. }
  sc := Src('{ "dataset": { "sourceHeader": 2, '
    + '"source": [["p","s"],["q","t"],[1,2]] } }');
  AssertEquals('two header rows', 2, sc.StartIndex);
  AssertEquals('and no names at all', 0, Length(sc.Dims));
  sc := Src('{ "dataset": { "sourceHeader": 1, "source": [["p","s"],[1,2]] } }');
  AssertEquals('one header row names them', 'p', TySourceDimName(sc, 0));
  AssertEquals('', 's', TySourceDimName(sc, 1));
end;

procedure TAdvChartDatasetTest.TestDeclaredDimensionsWinOverTheHeaderRow;
var sc: TTyChartSource;
begin
  { Written names replace detected ones -- and the header row is still a header,
    so it is still skipped. }
  sc := Src('{ "dataset": { "dimensions": ["one","two"], '
    + '"source": [["p","s"],[1,2]] } }');
  AssertEquals('the written name', 'one', TySourceDimName(sc, 0));
  AssertEquals('', 'two', TySourceDimName(sc, 1));
  AssertEquals('the header row is still skipped', 1, sc.StartIndex);
  AssertEquals('leaving one row', 1, TySourceRowCount(sc));

  { An entry may be an object, which is where a declared TYPE comes from. }
  sc := Src('{ "dataset": { "dimensions": [{"name":"when","type":"ordinal"},"v"], '
    + '"source": [[1,2],[3,4]] } }');
  AssertEquals('an object entry names too', 'when', TySourceDimName(sc, 0));
  AssertTrue('and carries its type', TySourceDimIsOrdinal(sc, 0));
  AssertFalse('while the other is sniffed', TySourceDimIsOrdinal(sc, 1));
end;

procedure TAdvChartDatasetTest.TestObjectRowsTakeTheirNamesFromTheFirstRowAndReadByName;
var sc: TTyChartSource;
begin
  { AN OBJECT ROW HAS NO COLUMNS, so a cell is fetched by NAME. The second row
    below is written in a different key order and a missing key is a gap, not a
    shift -- which a positional reader would get wrong twice. }
  sc := Src('{ "dataset": { "source": ['
    + '{"product":"a","2015":1,"2016":2},'
    + '{"2016":4,"product":"b","2015":3},'
    + '{"product":"c","2016":6}] } }');
  AssertEquals('a table of objects', Ord(tsfObjectRows), Ord(sc.Format));
  AssertEquals('named from the first row, in its order', 'product',
    TySourceDimName(sc, 0));
  AssertEquals('', '2015', TySourceDimName(sc, 1));
  AssertEquals('', '2016', TySourceDimName(sc, 2));
  AssertEquals('three rows and no header', 3, TySourceRowCount(sc));
  AssertEquals('the second row reads by name, not by position', 'b',
    Cell(sc, 1, 0));
  AssertEquals('', '3', Cell(sc, 1, 1));
  AssertEquals('', '4', Cell(sc, 1, 2));
  AssertEquals('and a key the row does not carry is a gap', '<nil>',
    Cell(sc, 2, 1));
end;

procedure TAdvChartDatasetTest.TestSeriesLayoutByRowTransposesTheTable;
var sc: TTyChartSource;
begin
  { `row` means each ROW is a dimension and each COLUMN a record -- so the
    header runs down the first column, the dimension count is the number of
    rows, and the record count is the length of a row. The table below is
    deliberately NOT square: 3 rows of 4, so transposing it wrongly cannot
    produce the same answer. }
  sc := Src('{ "dataset": { "seriesLayoutBy": "row", "source": ['
    + '["product","a","b","c"],'
    + '["2015",1,2,3],'
    + '["2016",4,5,6]] } }');
  AssertEquals('the header is the first COLUMN', 1, sc.StartIndex);
  AssertEquals('three dimensions, one per row', 3, sc.DimCount);
  AssertEquals('named down the column', 'product', TySourceDimName(sc, 0));
  AssertEquals('', '2015', TySourceDimName(sc, 1));
  AssertEquals('', '2016', TySourceDimName(sc, 2));
  AssertEquals('and three records, one per remaining column', 3,
    TySourceRowCount(sc));
  AssertEquals('record 0 of dimension 0', 'a', Cell(sc, 0, 0));
  AssertEquals('record 0 of dimension 2', '4', Cell(sc, 0, 2));
  AssertEquals('record 2 of dimension 1', '3', Cell(sc, 2, 1));
end;

{ ==================== which table ==================== }

procedure TAdvChartDatasetTest.TestWhichDatasetASeriesReads;
begin
  AssertTrue(FOpt.SetOptionText('{ "dataset": [{"source":[[1]]}, '
    + '{"id":"second","source":[[2]]}], "series": ['
    + '{"type":"bar"},'
    + '{"type":"bar","datasetIndex":1},'
    + '{"type":"bar","datasetId":"second"},'
    + '{"type":"bar","datasetIndex":9},'
    + '{"type":"bar","datasetId":"nope"},'
    + '{"type":"bar","data":[1,2]},'
    + '{"type":"bar","data":[]}] }'));
  AssertEquals('with neither, the first table', 0,
    TySeriesDatasetIndex(FOpt, 0));
  AssertEquals('an index names one', 1, TySeriesDatasetIndex(FOpt, 1));
  AssertEquals('and so does an id', 1, TySeriesDatasetIndex(FOpt, 2));
  { AN INDEX NAMING NOTHING RESOLVES TO NOTHING. Falling back to the first
    table would draw someone else's numbers under this series' name. }
  AssertEquals('an index past the end reads no table', -1,
    TySeriesDatasetIndex(FOpt, 3));
  AssertEquals('nor does an id nobody carries', -1,
    TySeriesDatasetIndex(FOpt, 4));
  { ITS OWN DATA WINS -- and an EMPTY array still counts as its own. }
  AssertEquals('its own data wins', -1, TySeriesDatasetIndex(FOpt, 5));
  AssertEquals('and an empty array is still its own data', -1,
    TySeriesDatasetIndex(FOpt, 6));

  AssertTrue(FOpt.SetOptionText('{ "series": [{"type":"bar"}] }'));
  AssertEquals('no table at all', -1, TySeriesDatasetIndex(FOpt, 0));
end;

{ ==================== encode ==================== }

function XY: TTyCoordDimArray;
begin
  SetLength(Result, 2);
  Result[0].Name := 'x';
  Result[0].Ordinal := False;
  Result[1].Name := 'y';
  Result[1].Ordinal := False;
end;

procedure TAdvChartDatasetTest.TestEncodeTakesAnIndexOrANameAndAListMeansItsFirst;
var
  sc: TTyChartSource;
  e: TTySeriesEncode;
  c: TTyCoordDimArray;
begin
  sc := Src('{ "dataset": { "source": [["a","b","c"],[1,2,3]] }, '
    + '"series": [{"type":"bar","encode":{"x":2,"y":"b"}},'
    + '{"type":"bar","encode":{"x":[1,0],"y":-1}}] }');
  c := XY;
  e := TyEncodeOf(FOpt, 0, sc, c);
  AssertTrue('it was given', e.Given);
  AssertEquals('a number is an INDEX', 2, e.Columns[0]);
  AssertEquals('a string is a NAME', 1, e.Columns[1]);

  e := TyEncodeOf(FOpt, 1, sc, c);
  AssertEquals('a list hands back its first entry', 1, e.Columns[0]);
  { -1 IS AN OPT-OUT, not an error and not a fallback: the coordinate is left
    without a column. }
  AssertEquals('and -1 leaves the coordinate unclaimed', -1, e.Columns[1]);

  { A name nobody carries leaves it unclaimed too, rather than raising. }
  AssertTrue(FOpt.SetOptionText('{ "dataset": { "source": [["a","b"],[1,2]] }, '
    + '"series": [{"type":"bar","encode":{"x":"nope"}}] }'));
  sc := TySourceOf(FOpt, 0);
  e := TyEncodeOf(FOpt, 0, sc, c);
  AssertEquals('a name that matches nothing', -1, e.Columns[0]);
end;

procedure TAdvChartDatasetTest.TestANumericStringIsANameAndNotAnIndex;
var
  sc: TTyChartSource;
  e: TTySeriesEncode;
  c: TTyCoordDimArray;
begin
  { The commonest real table has YEARS for column names, so `encode: { y:
    '2016' }` is a NAME lookup that happens to look like an index -- and the
    two answers differ, which is why the fixture puts '2016' in column 2. }
  sc := Src('{ "dataset": { "source": [["product","2015","2016"],["x",1,2]] }, '
    + '"series": [{"type":"bar","encode":{"y":"2016"}},'
    + '{"type":"bar","encode":{"y":2}}] }');
  c := XY;
  e := TyEncodeOf(FOpt, 0, sc, c);
  AssertEquals('the string is looked up as a name', 2, e.Columns[1]);
  e := TyEncodeOf(FOpt, 1, sc, c);
  AssertEquals('and the number is taken as an index', 2, e.Columns[1]);
  { Same answer here by construction; the discriminating case is a name whose
    text is a number that is NOT its own position. }
  AssertTrue(FOpt.SetOptionText('{ "dataset": { "source": '
    + '[["0","1","2"],[7,8,9]] }, '
    + '"series": [{"type":"bar","encode":{"y":"0"}}] }'));
  sc := TySourceOf(FOpt, 0);
  e := TyEncodeOf(FOpt, 0, sc, c);
  AssertEquals('a column literally called 0 is found by name', 0, e.Columns[1]);
end;

procedure TAdvChartDatasetTest.TestAPartialEncodeIsStillAnEncode;
var
  sc: TTyChartSource;
  e: TTySeriesEncode;
  c: TTyCoordDimArray;
begin
  { THE WHOLE POINT OF `Given`. `encode: { x: 0 }` says nothing about y -- and
    upstream does NOT then run the defaulter for y. The defaulter is all or
    nothing, so a series that named one coordinate opts out of the shared
    counter for both and leaves the other unclaimed. }
  sc := Src('{ "dataset": { "source": [[1,2,3]] }, '
    + '"series": [{"type":"bar","encode":{"x":0}}] }');
  c := XY;
  e := TyEncodeOf(FOpt, 0, sc, c);
  AssertTrue('a partial encode still counts as given', e.Given);
  AssertEquals('', 0, e.Columns[0]);
  AssertEquals('and y is left for nobody to fill', -1, e.Columns[1]);
end;

{ ==================== the default encode ==================== }

procedure TAdvChartDatasetTest.TestTheValueWayHandsEachSeriesTheNextColumns;
var
  cur: TTyEncodeCursor;
  c: TTyCoordDimArray;
  e0, e1, e2: TTySeriesEncode;
begin
  { NO CATEGORY AXIS ANYWHERE: every coordinate of every series takes the next
    column off one shared counter. Three scatter series on a six-column table
    take (0,1), (2,3), (4,5) -- which is the arrangement the header comment in
    sourceHelper.ts draws as a picture. }
  cur := Default(TTyEncodeCursor);
  c := XY;
  e0 := TyDefaultEncodeAxis(cur, c);
  e1 := TyDefaultEncodeAxis(cur, c);
  e2 := TyDefaultEncodeAxis(cur, c);
  AssertEquals('series 0 x', 0, e0.Columns[0]);
  AssertEquals('series 0 y', 1, e0.Columns[1]);
  AssertEquals('series 1 x', 2, e1.Columns[0]);
  AssertEquals('series 1 y', 3, e1.Columns[1]);
  AssertEquals('series 2 x', 4, e2.Columns[0]);
  AssertEquals('series 2 y', 5, e2.Columns[1]);
  { In this way the series' own name comes off its FIRST column, and no row
    gets a name at all -- there is no shared category to take one from. }
  AssertEquals('the series names itself after its first column', 0,
    e0.SeriesName);
  AssertEquals('', 2, e1.SeriesName);
  AssertEquals('and no row is named', -1, e0.ItemName);
end;

procedure TAdvChartDatasetTest.TestTheCategoryWayGivesEverySeriesColumnZero;
var
  cur: TTyEncodeCursor;
  c: TTyCoordDimArray;
  e0, e1, e2: TTySeriesEncode;
begin
  { ONE CATEGORY AXIS: the category is column 0 and every series shares it,
    while the values walk 1, 2, 3. This is the shape of every spreadsheet ever
    pasted into a chart, and it is the reason `dataset` exists. }
  cur := Default(TTyEncodeCursor);
  c := XY;
  c[0].Ordinal := True;
  e0 := TyDefaultEncodeAxis(cur, c);
  e1 := TyDefaultEncodeAxis(cur, c);
  e2 := TyDefaultEncodeAxis(cur, c);
  AssertEquals('every series reads the category from column 0', 0, e0.Columns[0]);
  AssertEquals('', 0, e1.Columns[0]);
  AssertEquals('', 0, e2.Columns[0]);
  AssertEquals('while the values walk', 1, e0.Columns[1]);
  AssertEquals('', 2, e1.Columns[1]);
  AssertEquals('', 3, e2.Columns[1]);
  { And the names: a row is named by the shared category, a series by its own
    value column. Those two together are what fills a legend nobody wrote. }
  AssertEquals('rows are named by the shared category', 0, e0.ItemName);
  AssertEquals('and each series by its own column', 1, e0.SeriesName);
  AssertEquals('', 2, e1.SeriesName);
end;

procedure TAdvChartDatasetTest.TestTheCategoryColumnIsZeroWhicheverAxisItIsOn;
var
  cur: TTyEncodeCursor;
  c: TTyCoordDimArray;
  e0, e1: TTySeriesEncode;
begin
  { THE ONE PORTS GET BACKWARDS. With the CATEGORY on y, the rule does not
    change: the category is still column 0 and the values still walk. The rule
    is about the order of the coordinate list, not about the screen -- so it is
    y that takes column 0 here, and x that walks. }
  cur := Default(TTyEncodeCursor);
  c := XY;
  c[1].Ordinal := True;
  e0 := TyDefaultEncodeAxis(cur, c);
  e1 := TyDefaultEncodeAxis(cur, c);
  AssertEquals('y is the category and takes column 0', 0, e0.Columns[1]);
  AssertEquals('and x walks', 1, e0.Columns[0]);
  AssertEquals('the second series shares the category', 0, e1.Columns[1]);
  AssertEquals('and takes the next column', 2, e1.Columns[0]);

  { AND WHEN BOTH COORDINATES ARE CATEGORIES, it is the FIRST of them that
    takes column 0 and the other that walks. A fixture with one category
    cannot tell `the first` from `the last`. }
  cur := Default(TTyEncodeCursor);
  c := XY;
  c[0].Ordinal := True;
  c[1].Ordinal := True;
  e0 := TyDefaultEncodeAxis(cur, c);
  AssertEquals('x is the first category and takes column 0', 0, e0.Columns[0]);
  AssertEquals('and y walks even though it is a category too', 1,
    e0.Columns[1]);
end;

procedure TAdvChartDatasetTest.TestTheCursorIsPerDatasetAndPerLayout;
var
  list: TTyEncodeCursorArray;
  c: TTyCoordDimArray;
  a, b: TTySeriesEncode;
  k: Integer;
begin
  { The counter is keyed on the table AND the way it is laid out, so two series
    reading DIFFERENT tables both start at the beginning -- and two reading the
    same table one way and the other way do too. }
  { THE INDEX FIRST, THEN THE SUBSCRIPT -- `list[F(list)]` where F may grow the
    array is this repository's own recorded footgun: FPC takes the array's
    address before evaluating the index. }
  list := nil;
  c := XY;
  k := TyEncodeCursorFor(list, 0, slbColumn);
  a := TyDefaultEncodeAxis(list[k], c);
  k := TyEncodeCursorFor(list, 1, slbColumn);
  b := TyDefaultEncodeAxis(list[k], c);
  AssertEquals('the first table', 0, a.Columns[0]);
  AssertEquals('a different table starts over', 0, b.Columns[0]);
  k := TyEncodeCursorFor(list, 0, slbRow);
  b := TyDefaultEncodeAxis(list[k], c);
  AssertEquals('and so does the same table read the other way', 0, b.Columns[0]);
  k := TyEncodeCursorFor(list, 0, slbColumn);
  b := TyDefaultEncodeAxis(list[k], c);
  AssertEquals('while the first one carried on', 2, b.Columns[0]);
  AssertEquals('three cursors', 3, Length(list));
end;

procedure TAdvChartDatasetTest.TestTheNameBasedDefaultPicksANameAndAValue;
var
  sc: TTyChartSource;
  e: TTySeriesEncode;
begin
  { A pie has one coordinate and two questions: which column is the number and
    which is the label. The first column that does not look numeric is the
    label; the first that does is the number. }
  sc := Src('{ "dataset": { "source": [["product","2015"],["a",1],["b",2]] } }');
  e := TyDefaultEncodeNameBased(sc, sc.DimCount);
  AssertEquals('the words are the name', 0, e.ItemName);
  AssertEquals('and the numbers the value', 1, e.Columns[0]);

  { THE OTHER WAY ROUND, which a fixture with the label first cannot tell from
    `always column 0`. }
  sc := Src('{ "dataset": { "source": [["2015","product"],[1,"a"],[2,"b"]] } }');
  e := TyDefaultEncodeNameBased(sc, sc.DimCount);
  AssertEquals('the name follows the words, not the position', 1, e.ItemName);
  AssertEquals('', 0, e.Columns[0]);

  { A DIMENSION LITERALLY CALLED `name` WINS OUTRIGHT, over a column that looks
    more like a label than it does. }
  sc := Src('{ "dataset": { "source": ['
    + '{"label":"aa","name":"bb","v":1},{"label":"cc","name":"dd","v":2}] } }');
  e := TyDefaultEncodeNameBased(sc, sc.DimCount);
  AssertEquals('the column called name wins', 1, e.ItemName);
  AssertEquals('and the number is still the value', 2, e.Columns[0]);
end;

procedure TAdvChartDatasetTest.TestADeclaredTypeEndsTheOrdinalQuestion;
var sc: TTyChartSource;
begin
  { A declared type is not a hint, it is the answer -- the rows are not looked
    at. The column below is all numbers and is declared ordinal. }
  sc := Src('{ "dataset": { "dimensions": [{"name":"a","type":"ordinal"},"b"], '
    + '"source": [[1,2],[3,4]] } }');
  AssertTrue('declared ordinal, whatever the rows say',
    TySourceDimIsOrdinal(sc, 0));
  AssertFalse('and the undeclared one is sniffed', TySourceDimIsOrdinal(sc, 1));

  { The sniff reads the first cell that says anything: nulls and `-` do not. }
  sc := Src('{ "dataset": { "sourceHeader": false, '
    + '"source": [[null,1],["-",2],["word",3]] } }');
  AssertTrue('nulls and dashes are skipped, then the word decides',
    TySourceDimIsOrdinal(sc, 0));
  AssertFalse('', TySourceDimIsOrdinal(sc, 1));
  { A NUMBER IN A STRING IS STILL A NUMBER here -- the sniff parses rather than
    testing the JSON type, because a table read out of a CSV has every cell as
    a string and none of them are categories. }
  sc := Src('{ "dataset": { "sourceHeader": false, '
    + '"source": [["1"],["2"]] } }');
  AssertFalse('a numeric string is not a category', TySourceDimIsOrdinal(sc, 0));
end;

{ upstream's createDimensions for a GIVEN encode: an unwritten coordinate
  takes, in coordinate order, the first dimension nobody holds -- but one
  written as -1 asks for NO mapping and is left alone, and it does not
  count as holding anything. }
procedure TAdvChartDatasetTest.TestAGivenEncodeFillsWhatItLeavesOut;
var enc: TTySeriesEncode;
begin
  enc := Default(TTySeriesEncode);
  enc.Given := True;
  SetLength(enc.Columns, 3);
  SetLength(enc.Explicit, 3);
  enc.Columns[0] := -1;  enc.Explicit[0] := True;   // x: -1
  enc.Columns[1] := 0;   enc.Explicit[1] := True;   // y: 0
  enc.Columns[2] := -1;  enc.Explicit[2] := False;  // unwritten
  TyEncodeFillUnclaimed(enc, 4);
  AssertEquals('a written -1 stays unmapped', -1, enc.Columns[0]);
  AssertEquals('a written index stays', 0, enc.Columns[1]);
  AssertEquals('the unwritten one takes the first free', 1, enc.Columns[2]);
  { Past the width there is nothing to take. }
  enc.Columns[2] := -1;
  TyEncodeFillUnclaimed(enc, 1);
  AssertEquals('nothing free below the width', -1, enc.Columns[2]);
  { Not given: the defaulter's business, untouched. }
  enc.Given := False;
  TyEncodeFillUnclaimed(enc, 4);
  AssertEquals('an encode not given is not filled', -1, enc.Columns[2]);
end;

procedure TAdvChartDatasetTest.TestASourceWithNoReaderAnswersNothing;
var sc: TTyChartSource;
begin
  sc := Src('{ "dataset": { "source": [1,2,3] } }');
  AssertFalse('a flat array of numbers has no reader', sc.Valid);
  AssertEquals('and no rows', 0, TySourceRowCount(sc));
  { A column-keyed object HAS a reader now (batch 49) -- `for now` has
    passed; test.advchart.seriestext holds it to upstream. }
  sc := Src('{ "dataset": { "source": {"a":[1,2]} } }');
  AssertTrue('a column-keyed object is read', sc.Valid);
  AssertEquals('as many rows as its first column', 2, TySourceRowCount(sc));
  { The FIRST dimension's column counts, not the longest -- and a shorter
    column past its end is a gap. }
  sc := Src('{ "dataset": { "source": {"a":[1,2,3],"b":[4]} } }');
  AssertEquals('the first column counts', 3, TySourceRowCount(sc));
  AssertEquals('the second column is b', 'b', TySourceDimName(sc, 1));
  AssertTrue('b has no second cell', TySourceCell(sc, 1, 1) = nil);
  AssertEquals('a has', 2, TySourceCell(sc, 1, 0).AsInteger);
  sc := Src('{ "dataset": { "source": {"a":[1],"b":[4,5,6]} } }');
  AssertEquals('whatever the others hold', 1, TySourceRowCount(sc));
  sc := Src('{ "xAxis": {} }');
  AssertFalse('nor has a chart with no dataset at all', sc.Valid);
  AssertEquals('', 0, TyDatasetCount(FOpt));
  AssertEquals('', 0, TyDatasetCount(TTyChartOption(nil)));
end;

procedure TAdvChartDatasetTest.TestASeriesOverrulesTheTableAboutHowToReadIt;
var a, b: TTyChartSource;
begin
  { THE SERIES WINS AND THE TABLE IS THE FALLBACK, which only a fixture where
    BOTH say something can see: with the option written on the series alone,
    swapping the precedence changes nothing, because the table has nothing to
    win with. So the table asks for one reading here and the second series
    asks for the other. }
  AssertTrue(FOpt.SetOptionText('{ "dataset": { "seriesLayoutBy": "row", '
    + '"source": [["p","q"],[1,2],[30,40]] }, '
    + '"series": [{"type":"bar"},'
    + '{"type":"bar","seriesLayoutBy":"column"}] }'));
  a := TySourceOf(FOpt, 0, 0);
  b := TySourceOf(FOpt, 0, 1);
  AssertEquals('the silent series takes the table''s reading', Ord(slbRow),
    Ord(a.LayoutBy));
  AssertEquals('and the one that asked gets its own', Ord(slbColumn),
    Ord(b.LayoutBy));
  { And the two really are different tables: read down there are two
    dimensions and two records, read across there are three of one and two of
    the other. }
  AssertEquals('read across', 3, a.DimCount);
  AssertEquals('read down', 2, b.DimCount);

  { THE SAME FOR sourceHeader, and it changes what the rows even are. }
  AssertTrue(FOpt.SetOptionText('{ "dataset": { "sourceHeader": false, '
    + '"source": [["p","q"],[1,2],[30,40]] }, '
    + '"series": [{"type":"bar"},'
    + '{"type":"bar","sourceHeader":true}] }'));
  a := TySourceOf(FOpt, 0, 0);
  b := TySourceOf(FOpt, 0, 1);
  AssertEquals('the table said there is no header', 3, TySourceRowCount(a));
  AssertEquals('the series said there is one', 2, TySourceRowCount(b));
  AssertEquals('and only the second one has names', 'p',
    TySourceDimName(b, 0));
  AssertEquals('', '', TySourceDimName(a, 0));

  { AND FOR dimensions, which is the one that renames rather than re-shapes. }
  AssertTrue(FOpt.SetOptionText('{ "dataset": { "dimensions": ["dsA"], '
    + '"source": [[1],[2]] }, '
    + '"series": [{"type":"bar"},'
    + '{"type":"bar","dimensions":["serA"]}] }'));
  a := TySourceOf(FOpt, 0, 0);
  b := TySourceOf(FOpt, 0, 1);
  AssertEquals('the table''s name', 'dsA', TySourceDimName(a, 0));
  AssertEquals('the series'' own', 'serA', TySourceDimName(b, 0));
end;

initialization
  RegisterTest(TAdvChartDatasetTest);
end.
