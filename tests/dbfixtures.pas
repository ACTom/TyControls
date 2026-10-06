unit dbfixtures;
{$mode objfpc}{$H+}

{ The in-memory tables every data-aware control suite binds to (issue #34). REGISTERS NO TESTS.

  People: one row per kind of value a control maps, so every control has a field of its own
  type to bind to --

    ID      ftInteger         Name   ftString(40)   Note   ftMemo     Amount  ftFloat
    Price   ftCurrency        Qty    ftInteger      Active ftBoolean  Flag    ftString(1) Y/N
    Born    ftDate            At     ftDateTime     Stars  ftFloat    Kind    ftString(10)
    CityID  ftInteger (a key into Cities)           Pic    ftBlob (a PNG)

  Three rows. Rows 1 and 2 have a value in every field; row 3 has only its ID, every other
  field NULL, which is the row the empty-value rules (plan D5) are tested on. The values of rows
  1 and 2 differ in every field, so "the control shows the row it is on" cannot pass by showing
  the other one.

  Cities(ID, Name): three rows, the lookup table for CityID.

  Both tables are open and on their first row, and in dsBrowse, when NewDbFixture returns. The
  fixture owns the four components and frees them data sources first, then People (its lookup
  fields, when a suite adds some, point into Cities), then Cities. A test may free one of them
  itself -- C7 frees the data source under a live control -- and the fixture forgets it. }

interface

uses
  Classes, SysUtils, DB, BufDataset;

type
  TDbFixture = class(TComponent)
  private
    FDS: TBufDataset;
    FSrc: TDataSource;
    FCities: TBufDataset;
    FCitySrc: TDataSource;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    destructor Destroy; override;
    property DS: TBufDataset read FDS;
    property Src: TDataSource read FSrc;
    property Cities: TBufDataset read FCities;
    property CitySrc: TDataSource read FCitySrc;
  end;

const
  { The values rows 1 and 2 carry, for the suites to compare against. }
  CFixNames: array[1..2] of string = ('Alice', 'Bob');
  CFixNotes: array[1..2] of string = ('First note', 'Second note');
  CFixAmounts: array[1..2] of Double = (12.5, -4.75);
  CFixPrices: array[1..2] of Currency = (3.25, 1000);
  CFixQtys: array[1..2] of Integer = (7, 0);
  CFixActives: array[1..2] of Boolean = (True, False);
  CFixFlags: array[1..2] of string = ('Y', 'N');
  CFixStars: array[1..2] of Double = (3.5, 1);
  CFixKinds: array[1..2] of string = ('alpha', 'beta');
  CFixCityIDs: array[1..2] of Integer = (1, 3);
  CFixCityNames: array[1..3] of string = ('Paris', 'Tokyo', 'Lima');

{ The two tables, open, on row 1, owned by AOwner (nil is fine; then the caller frees it). }
function NewDbFixture(AOwner: TComponent): TDbFixture;
{ Row ARow's Born / At (1 or 2). }
function FixBorn(ARow: Integer): TDateTime;
function FixAt(ARow: Integer): TDateTime;
{ A small PNG, AW x AH, every pixel AColor (FPImage's 16-bit channels): row 1's and row 2's
  Pic, and anything a suite wants to write into the blob. }
function FixPng(AW, AH: Integer; ARed, AGreen, ABlue: Word): TBytes;

implementation

uses
  DateUtils, FPImage, FPWritePNG;

function FixBorn(ARow: Integer): TDateTime;
begin
  if ARow = 1 then Result := EncodeDate(1990, 5, 17) else Result := EncodeDate(2001, 12, 31);
end;

function FixAt(ARow: Integer): TDateTime;
begin
  if ARow = 1 then Result := EncodeDateTime(2024, 3, 1, 9, 30, 0, 0)
  else Result := EncodeDateTime(2023, 7, 15, 18, 45, 0, 0);
end;

function FixPng(AW, AH: Integer; ARed, AGreen, ABlue: Word): TBytes;
var
  img: TFPMemoryImage;
  w: TFPWriterPNG;
  ms: TMemoryStream;
  x, y: Integer;
  c: TFPColor;
begin
  Result := nil;
  img := TFPMemoryImage.Create(AW, AH);
  w := TFPWriterPNG.Create;
  ms := TMemoryStream.Create;
  try
    c.Red := ARed; c.Green := AGreen; c.Blue := ABlue; c.Alpha := alphaOpaque;
    for y := 0 to AH - 1 do
      for x := 0 to AW - 1 do
        img.Colors[x, y] := c;
    img.SaveToStream(ms, w);
    SetLength(Result, ms.Size);
    if ms.Size > 0 then Move(ms.Memory^, Result[0], ms.Size);
  finally
    ms.Free;
    w.Free;
    img.Free;
  end;
end;

{ TDbFixture }

procedure TDbFixture.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if Operation <> opRemove then Exit;
  if AComponent = FSrc then FSrc := nil;
  if AComponent = FCitySrc then FCitySrc := nil;
  if AComponent = FDS then FDS := nil;
  if AComponent = FCities then FCities := nil;
end;

destructor TDbFixture.Destroy;
begin
  { What depends on what goes first: the sources (controls watch them), then People, whose
    lookup fields read Cities, then Cities. Each Free reaches Notification, which clears the
    field, so the order below is the whole story and the inherited destructor finds nothing. }
  FSrc.Free;
  FCitySrc.Free;
  FDS.Free;
  FCities.Free;
  inherited Destroy;
end;

function NewDbFixture(AOwner: TComponent): TDbFixture;

  procedure SetPng(AField: TField; const ABytes: TBytes);
  var
    ms: TMemoryStream;
  begin
    ms := TMemoryStream.Create;
    try
      ms.WriteBuffer(ABytes[0], Length(ABytes));
      ms.Position := 0;
      TBlobField(AField).LoadFromStream(ms);
    finally
      ms.Free;
    end;
  end;

var
  f: TDbFixture;
  r: Integer;
begin
  f := TDbFixture.Create(AOwner);
  try
    f.FCities := TBufDataset.Create(f);
    f.FCities.Name := 'Cities';
    f.FCities.FieldDefs.Add('ID', ftInteger);
    f.FCities.FieldDefs.Add('Name', ftString, 20);
    f.FCities.CreateDataset;               { opens it }
    for r := 1 to 3 do
      f.FCities.AppendRecord([r, CFixCityNames[r]]);
    f.FCities.First;
    f.FCitySrc := TDataSource.Create(f);
    f.FCitySrc.Name := 'CitySrc';
    f.FCitySrc.DataSet := f.FCities;

    f.FDS := TBufDataset.Create(f);
    f.FDS.Name := 'People';
    with f.FDS.FieldDefs do
    begin
      Add('ID', ftInteger);
      Add('Name', ftString, 40);
      Add('Note', ftMemo);
      Add('Amount', ftFloat);
      Add('Price', ftCurrency);
      Add('Qty', ftInteger);
      Add('Active', ftBoolean);
      Add('Flag', ftString, 1);
      Add('Born', ftDate);
      Add('At', ftDateTime);
      Add('Stars', ftFloat);
      Add('Kind', ftString, 10);
      Add('CityID', ftInteger);
      Add('Pic', ftBlob);
    end;
    f.FDS.CreateDataset;                   { opens it }
    for r := 1 to 2 do
    begin
      f.FDS.Append;
      f.FDS.FieldByName('ID').AsInteger := r;
      f.FDS.FieldByName('Name').AsString := CFixNames[r];
      f.FDS.FieldByName('Note').AsString := CFixNotes[r];
      f.FDS.FieldByName('Amount').AsFloat := CFixAmounts[r];
      f.FDS.FieldByName('Price').AsCurrency := CFixPrices[r];
      f.FDS.FieldByName('Qty').AsInteger := CFixQtys[r];
      f.FDS.FieldByName('Active').AsBoolean := CFixActives[r];
      f.FDS.FieldByName('Flag').AsString := CFixFlags[r];
      f.FDS.FieldByName('Born').AsDateTime := FixBorn(r);
      f.FDS.FieldByName('At').AsDateTime := FixAt(r);
      f.FDS.FieldByName('Stars').AsFloat := CFixStars[r];
      f.FDS.FieldByName('Kind').AsString := CFixKinds[r];
      f.FDS.FieldByName('CityID').AsInteger := CFixCityIDs[r];
      if r = 1 then SetPng(f.FDS.FieldByName('Pic'), FixPng(2, 2, $FFFF, 0, 0))
      else SetPng(f.FDS.FieldByName('Pic'), FixPng(3, 1, 0, 0, $FFFF));
      f.FDS.Post;
    end;
    f.FDS.Append;                          { row 3: the ID and nothing else }
    f.FDS.FieldByName('ID').AsInteger := 3;
    f.FDS.Post;
    f.FDS.First;
    f.FSrc := TDataSource.Create(f);
    f.FSrc.Name := 'Src';
    f.FSrc.DataSet := f.FDS;
  except
    f.Free;
    raise;
  end;
  Result := f;
end;

end.
