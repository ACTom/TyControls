unit test.trackbar.drawthumb;
{$mode objfpc}{$H+}

{ #242: OnDrawThumb on every track bar, and PaintThumb for a descendant.

  The theme gives the thumb a colour nothing else has (red), so a picture says whether the
  default thumb was drawn; a handler that takes the thumb fills its rectangle green, a
  descendant's own thumb is blue. }

interface

uses
  Classes, SysUtils, Types, TypInfo, Graphics, Forms, Controls, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Base, tyControls.Controller, tyControls.Painter,
  tyControls.TrackBar, tyControls.MultiTrackBar, test.multitrackbar;

type
  TDrawBar = class(TTyTrackBar)
  public
    FakeFocus: Boolean;
    Repaints: Integer;
    function Focused: Boolean; override;
    procedure Invalidate; override;
    procedure Shot(ACanvas: TCanvas; const R: TRect; APPI: Integer);
  end;

  { A descendant with a thumb of its own, which says nothing to the event. }
  TOwnThumbBar = class(TDrawBar)
  protected
    procedure PaintThumb(APainter: TTyPainter; AIndex: Integer; const ARect: TRect;
      const AStyle: TTyStyleSet; AStates: TTyStateSet); override;
  end;

  TTrackDrawThumbTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FForm: TForm;
    FBar: TDrawBar;
    FMulti: TMultiProbe;
    FTake: Boolean;
    FCalls, FIndex: Integer;
    FRect: TRect;
    FStyle: TTyStyleSet;
    FStates: TTyStateSet;
    FLog: string;
    procedure Seen(Sender: TObject; APainter: TTyPainter; AIndex: Integer; const ARect: TRect;
      const AStyle: TTyStyleSet; AStates: TTyStateSet; var ADefaultDraw: Boolean);
    function NewBar(AOwn: Boolean = False): TDrawBar;
    function Shoot(AMulti: Boolean): TBGRABitmap;
    { The box of the pixels of exactly that colour; empty when there are none. }
    function Ink(AMulti: Boolean; R, G, B: Byte): TRect;
    function RectText(const R: TRect): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TheEventIsAskedForTheThumbAsItIsDrawn;
    procedure TheEventIsToldTheStates;
    procedure TakingTheThumbLeavesItToTheHandler;
    procedure NotTakingItDrawsTheThemesThumb;
    procedure TheHitRectangleIsTheSameWhateverIsDrawn;
    procedure ADescendantPaintsItsOwnThumb;
    procedure TheEventIsPublishedOnEveryTrackBar;
    procedure AssigningTheEventRepaintsTheBar;
    procedure OnAMultiThumbBarEveryThumbComesWithItsOwnStyle;
    procedure OnAMultiThumbBarTakingOneThumbLeavesTheOthers;
  end;

implementation

const
  CCss =
    'TyTrackBar { color: #000000; border-width: 0px; border-radius: 0px; padding: 0px; }' +
    'TyTrackGroove { background: #606060; border-radius: 0px; }' +
    'TyTrackThumb { background: #FF0000; border-radius: 0px; }';

function TDrawBar.Focused: Boolean;
begin
  Result := FakeFocus or inherited Focused;
end;

procedure TDrawBar.Invalidate;
begin
  Inc(Repaints);
  inherited Invalidate;
end;

procedure TDrawBar.Shot(ACanvas: TCanvas; const R: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, R, APPI);
end;

procedure TOwnThumbBar.PaintThumb(APainter: TTyPainter; AIndex: Integer; const ARect: TRect;
  const AStyle: TTyStyleSet; AStates: TTyStateSet);
var
  f: TTyFill;
begin
  f := Default(TTyFill);
  f.Kind := tfkSolid;
  f.Color := TyRGB(0, 0, 255);
  APainter.FillBackground(ARect, f, 0);
end;

procedure TTrackDrawThumbTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FCtl.LoadThemeCss(CCss);
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(-4000, -4000, 600, 400);
  FBar := NewBar;
  FMulti := TMultiProbe.Create(FForm);
  FMulti.Parent := FForm;
  FMulti.Controller := FCtl;
  FMulti.Font.PixelsPerInch := 96;
  FMulti.SetBounds(0, 60, 200, 40);
  FTake := False;
  FCalls := 0;
  FIndex := -1;
  FLog := '';
end;

procedure TTrackDrawThumbTest.TearDown;
begin
  FForm.Free;
  FCtl.Free;
end;

function TTrackDrawThumbTest.NewBar(AOwn: Boolean): TDrawBar;
begin
  if AOwn then Result := TOwnThumbBar.Create(FForm)
  else Result := TDrawBar.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.AnimationsEnabled := False;
  Result.TickStyle := ttsNone;
  Result.SetBounds(0, 0, 200, 40);
  Result.Position := 50;
end;

procedure TTrackDrawThumbTest.Seen(Sender: TObject; APainter: TTyPainter; AIndex: Integer;
  const ARect: TRect; const AStyle: TTyStyleSet; AStates: TTyStateSet;
  var ADefaultDraw: Boolean);
var
  f: TTyFill;
begin
  Inc(FCalls);
  FIndex := AIndex;
  FRect := ARect;
  FStyle := AStyle;
  FStates := AStates;
  FLog := FLog + Format('%d:%s ', [AIndex, IntToHex(AStyle.Background.Color, 8)]);
  { Take: every thumb on a single bar, thumb 1 on a multi-thumb one. }
  if FTake and ((Sender = FBar) or (AIndex = 1)) then
  begin
    ADefaultDraw := False;
    f := Default(TTyFill);
    f.Kind := tfkSolid;
    f.Color := TyRGB(0, 255, 0);
    APainter.FillBackground(ARect, f, 0);
  end;
end;

function TTrackDrawThumbTest.Shoot(AMulti: Boolean): TBGRABitmap;
var
  bmp: TBitmap;
  r: TRect;
begin
  r := Rect(0, 0, 200, 40);
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(200, 40);
    bmp.Canvas.Brush.Color := TColor($F0F0F0);
    bmp.Canvas.FillRect(r);
    if AMulti then FMulti.Render(bmp.Canvas, r, 96)
    else FBar.Shot(bmp.Canvas, r, 96);
    Result := TBGRABitmap.Create(bmp);
  finally
    bmp.Free;
  end;
end;

function TTrackDrawThumbTest.Ink(AMulti: Boolean; R, G, B: Byte): TRect;
var
  img: TBGRABitmap;
  x, y: Integer;
  p: TBGRAPixel;
begin
  Result := Rect(MaxInt, MaxInt, -1, -1);
  img := Shoot(AMulti);
  try
    for y := 0 to img.Height - 1 do
      for x := 0 to img.Width - 1 do
      begin
        p := img.GetPixel(x, y);
        if (p.red <> R) or (p.green <> G) or (p.blue <> B) then Continue;
        if x < Result.Left then Result.Left := x;
        if y < Result.Top then Result.Top := y;
        if x + 1 > Result.Right then Result.Right := x + 1;
        if y + 1 > Result.Bottom then Result.Bottom := y + 1;
      end;
  finally
    img.Free;
  end;
  if Result.Right < 0 then Result := Rect(0, 0, 0, 0);
end;

function TTrackDrawThumbTest.RectText(const R: TRect): string;
begin
  Result := Format('%d,%d-%d,%d', [R.Left, R.Top, R.Right, R.Bottom]);
end;

{ The rectangle is the thumb as painted -- after --track-thumb-thickness -- and the style is
  the one it would be painted with -- after --track-thumb-radius. }
procedure TTrackDrawThumbTest.TheEventIsAskedForTheThumbAsItIsDrawn;
var
  drawn: TRect;
begin
  FBar.StyleOverride := '--track-thumb-thickness: 10px; --track-thumb-radius: 3px;';
  drawn := Ink(False, 255, 0, 0);
  AssertTrue('setup: the theme''s thumb is drawn', drawn.Right > drawn.Left);
  FBar.OnDrawThumb := @Seen;
  Shoot(False).Free;
  AssertEquals('asked once for the one thumb', 1, FCalls);
  AssertEquals('whose index is 0', 0, FIndex);
  AssertEquals('the rectangle is the thumb as drawn', RectText(drawn), RectText(FRect));
  AssertEquals('ten across, as the token says', 10, FRect.Bottom - FRect.Top);
  AssertEquals('the style carries the token''s radius', 3, FStyle.BorderRadius);
  AssertEquals('and the theme''s colour', IntToHex(TyRGB(255, 0, 0), 8),
    IntToHex(FStyle.Background.Color, 8));
end;

procedure TTrackDrawThumbTest.TheEventIsToldTheStates;
begin
  FBar.OnDrawThumb := @Seen;
  Shoot(False).Free;
  AssertTrue('at rest: normal', tysNormal in FStates);
  AssertFalse('and not focused', tysFocused in FStates);
  FBar.FakeFocus := True;
  Shoot(False).Free;
  AssertTrue('with the keyboard: focused', tysFocused in FStates);
end;

procedure TTrackDrawThumbTest.TakingTheThumbLeavesItToTheHandler;
var
  green, red: TRect;
begin
  FBar.OnDrawThumb := @Seen;
  FTake := True;
  green := Ink(False, 0, 255, 0);
  red := Ink(False, 255, 0, 0);
  AssertEquals('what the handler drew is there', RectText(FRect), RectText(green));
  AssertTrue('and the theme''s thumb is not: ' + RectText(red), IsRectEmpty(red));
end;

procedure TTrackDrawThumbTest.NotTakingItDrawsTheThemesThumb;
var
  before: TRect;
begin
  before := Ink(False, 255, 0, 0);
  FBar.OnDrawThumb := @Seen;
  AssertEquals('the same thumb as with no handler', RectText(before), RectText(Ink(False, 255, 0, 0)));
  AssertTrue('and the handler was asked', FCalls > 0);
end;

procedure TTrackDrawThumbTest.TheHitRectangleIsTheSameWhateverIsDrawn;
var
  before: TRect;
begin
  before := FBar.ThumbRect;
  FBar.OnDrawThumb := @Seen;
  FTake := True;
  Shoot(False).Free;
  AssertEquals(RectText(before), RectText(FBar.ThumbRect));
  AssertEquals('and it is where the handler was told to draw', before.Left, FRect.Left);
end;

procedure TTrackDrawThumbTest.ADescendantPaintsItsOwnThumb;
var
  blue: TRect;
begin
  FBar.Free;
  FBar := NewBar(True);
  FBar.OnDrawThumb := @Seen;
  blue := Ink(False, 0, 0, 255);
  AssertTrue('its thumb is drawn', blue.Right > blue.Left);
  AssertEquals('where the thumb is', FBar.ThumbRect.Left, blue.Left);
  AssertTrue('the theme''s is not', IsRectEmpty(Ink(False, 255, 0, 0)));
  AssertEquals('and it did not pass the question on', 0, FCalls);
end;

procedure TTrackDrawThumbTest.TheEventIsPublishedOnEveryTrackBar;
begin
  AssertNotNull('TTyTrackBar', GetPropInfo(TTyTrackBar, 'OnDrawThumb'));
  AssertNotNull('TTyRangeTrackBar', GetPropInfo(TTyRangeTrackBar, 'OnDrawThumb'));
  AssertNotNull('TTyMultiTrackBar', GetPropInfo(TTyMultiTrackBar, 'OnDrawThumb'));
  AssertNotNull('TTyGradientTrackBar', GetPropInfo(TTyGradientTrackBar, 'OnDrawThumb'));
end;

{ The handler is what the thumb looks like: a bar that was given one, or lost it, has to be
  painted again. }
procedure TTrackDrawThumbTest.AssigningTheEventRepaintsTheBar;
var
  n: Integer;
begin
  n := FBar.Repaints;
  FBar.OnDrawThumb := @Seen;
  AssertTrue('given a handler', FBar.Repaints > n);
  n := FBar.Repaints;
  FBar.OnDrawThumb := nil;
  AssertTrue('and without it again', FBar.Repaints > n);
end;

procedure TTrackDrawThumbTest.OnAMultiThumbBarEveryThumbComesWithItsOwnStyle;
begin
  FMulti.Put([20, 80]);
  SetLength(FMulti.Colors, 2);
  FMulti.Colors[0] := clDefault;
  FMulti.Colors[1] := clLime;
  FMulti.StyleOverride := '--track-thumb-radius: 3px;';
  FMulti.OnDrawThumb := @Seen;
  Shoot(True).Free;
  AssertEquals('each thumb once, the theme''s colour and then its own',
    Format('0:%s 1:%s ', [IntToHex(TyRGB(255, 0, 0), 8), IntToHex(TyRGB(0, 255, 0), 8)]), FLog);
  AssertEquals('with the token''s radius', 3, FStyle.BorderRadius);
  AssertEquals('and its drawn rectangle starts where its hit rectangle does',
    FMulti.ThumbRect(1).Left, FRect.Left);
end;

procedure TTrackDrawThumbTest.OnAMultiThumbBarTakingOneThumbLeavesTheOthers;
var
  green, red: TRect;
begin
  FMulti.Put([20, 80]);
  FMulti.OnDrawThumb := @Seen;
  FTake := True;
  green := Ink(True, 0, 255, 0);
  red := Ink(True, 255, 0, 0);
  AssertEquals('thumb 1 is the handler''s', FMulti.ThumbRect(1).Left, green.Left);
  AssertEquals('thumb 0 is still the theme''s', FMulti.ThumbRect(0).Left, red.Left);
  AssertEquals('and only thumb 0', FMulti.ThumbRect(0).Right, red.Right);
end;

initialization
  RegisterTest(TTrackDrawThumbTest);
end.
