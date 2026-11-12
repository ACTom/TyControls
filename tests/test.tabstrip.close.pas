unit test.tabstrip.close;
{$mode objfpc}{$H+}

{ #223. Which closable tabs show their close button (--tab-close-show) and what the button
  looks like (--tab-close-color, -background, -hover-color, -hover-background, -radius,
  -size and --glyph-tab-close).

  The strip is a real TTyTabSet, so a close really removes a tab and the control's own
  StyleOverride really reaches the tokens.

  The palette is loud on purpose, so "what is in the slot" is a colour search:
    tab and strip          WHITE in every state (a hover or a selection changes no fill)
    caption, the theme x   BLUE
    TyTabClose chip        LIME   (the theme's chip under the pointer)
    token: mark            RED
    token: chip            YELLOW
    token: hover mark      BLACK
    token: hover chip      CYAN
  The bitmap starts GREY, which nothing here draws. }

interface

uses
  Classes, SysUtils, Types, Controls, Forms, Graphics, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Controller, tyControls.TabStrip, tyControls.TabSet, tyControls.PageControl,
  tyControls.Icons.Lucide;

type
  TSlotInk = (siBlue, siRed, siBlack, siYellow, siCyan, siLime);

  TTabStripCloseTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FForm: TForm;
    FStrip: TTyTabSet;
    FTarget: TTyCustomTabStrip;   // the strip the helpers look at; FStrip unless a test says so
    FCloses, FClosedIndex: Integer;
    FModified, FPinned: set of 0..7;   // tab indexes, answered by TabStateOf
    FPinClicks: Integer;
    procedure TabStateOf(Sender: TObject; AIndex: Integer; var AState: TTyTabState);
    procedure PinClicked(Sender: TObject; AIndex: Integer);
    procedure Theme(const ARoot: string; const ACloseRule: string = '');
    procedure Closing(Sender: TObject; AIndex: Integer; var AllowClose: Boolean);
    function Slot(AIndex: Integer): TRect;
    function SlotMid(AIndex: Integer): TPoint;
    function CaptionPoint(AIndex: Integer): TPoint;
    function Shot: TBGRABitmap;
    function InSlot(AIndex: Integer; AInk: TSlotInk): Integer;
    function SlotPixel(AIndex, ADx, ADy: Integer): TBGRAPixel;
    function CornerIs(AIndex: Integer; AInk: TSlotInk): Boolean;
    function EdgeMidIs(AIndex: Integer; AInk: TSlotInk): Boolean;
    procedure Hover(const APoint: TPoint);
    procedure Press(const APoint: TPoint);
    procedure Leave;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { which tabs show the button }
    procedure EveryTabShowsItsButtonByDefault;
    procedure TheShowWordIsReadWhateverItsCase;
    procedure ActiveShowsTheButtonOnTheCurrentTabOnly;
    procedure AnUnknownShowWordShowsEveryButton;
    procedure AHiddenButtonKeepsItsSlot;
    procedure AClickOnAHiddenButtonSelectsTheTab;
    procedure AHiddenButtonDoesNotLightUnderThePointer;
    procedure HoverShowsTheButtonOfTheTabUnderThePointer;
    procedure HoverClosesTheTabUnderThePointer;
    procedure InHoverModeAPressOnTheButtonClosesWithoutAMoveFirst;
    procedure OneStripHidesItsButtonsOnItsOwn;
    procedure APageControlHidesItsButtonsToo;
    { what the button looks like }
    procedure WithNoTokenTheButtonIsTheThemeOne;
    procedure TheMarkTakesItsOwnColour;
    procedure AColourThatIsNoColourLeavesTheMarkAlone;
    procedure AChipSitsBehindTheMarkAtRest;
    procedure UnderThePointerTheMarkAndTheChipChange;
    procedure AHoverChipReplacesTheRestingChip;
    procedure WithoutAHoverColourTheMarkKeepsItsRestingColour;
    procedure WithoutAHoverChipTheThemeChipLiesOverTheRestingOne;
    procedure TheChipTakesItsRadiusFromTheToken;
    procedure WithoutARadiusTokenTheChipFollowsTyTabClose;
    procedure OneStripRestylesItsButtonOnItsOwn;
    procedure OneStripSizesItsButtonOnItsOwn;
    { the mark itself }
    procedure TheMarkFollowsTheTabGlyphToken;
    procedure WithoutATabGlyphTheMarkFollowsTheCloseGlyph;
    procedure TheTabGlyphWinsOverTheCloseGlyph;
    procedure AReplacedMarkTakesTheMarkColour;
    procedure OneStripChangesItsMarkOnItsOwn;
    procedure ATabGlyphThatIsNoGlyphLeavesTheMark;
    procedure TheBundledIconFontDrawsTheMark;
    { beside the tab states: a dot, a pin, a middle click }
    procedure AModifiedTabKeepsItsDotWhereItsButtonIsHidden;
    procedure APinnedTabKeepsItsPinAndItsClick;
    procedure TheCloseLookIsNotThePins;
    procedure AMiddleClickClosesATabWhoseButtonIsHidden;
    procedure AButtonThatWentOffScreenUnderThePointerIsNotLit;
  end;

implementation

type
  { Reaches the protected paint and mouse entry points of any strip. }
  TStripCrack = class(TTyCustomTabStrip);

const
  STRIP_W = 420;
  STRIP_H = 28;

  BaseCss =
    'TyTabControl, TyTabSet { background: #FFFFFF; border: 0px solid #FFFFFF; border-radius: 0px; }' +
    'TyPageControl { background: #FFFFFF; border: 0px solid #FFFFFF; border-radius: 0px; }' +
    'TyTab { background: #FFFFFF; color: #0000FF; font-size: 12px; border-radius: 0px; }' +
    'TyTab:hover { background: #FFFFFF; color: #0000FF; }' +
    'TyTab:active { background: #FFFFFF; color: #0000FF; }';
  LimeSquareChip = 'TyTabClose { background: #00FF00; border-radius: 0px; }';

function IsInk(const p: TBGRAPixel; AInk: TSlotInk): Boolean;
begin
  case AInk of
    siBlue:   Result := (p.blue > p.red + 60) and (p.blue > p.green + 60);
    siRed:    Result := (p.red > p.green + 60) and (p.red > p.blue + 60);
    siBlack:  Result := (p.red < 90) and (p.green < 150) and (p.blue < 150);
    siYellow: Result := (p.red > 190) and (p.green > 190) and (p.blue < 90);
    siCyan:   Result := (p.red < 90) and (p.green > 190) and (p.blue > 190);
    siLime:   Result := (p.red < 90) and (p.green > 190) and (p.blue < 90);
  else
    Result := False;
  end;
end;

{ ---- fixture ---- }

procedure TTabStripCloseTest.SetUp;
begin
  FCloses := 0;
  FClosedIndex := -1;
  FModified := [];
  FPinned := [];
  FPinClicks := 0;
  FCtl := TTyStyleController.Create(nil);
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 480, 200);
  FStrip := TTyTabSet.Create(FForm);
  FStrip.Parent := FForm;
  FStrip.Controller := FCtl;
  FStrip.Font.PixelsPerInch := 96;
  FStrip.Tabs.AddStrings(['Alpha', 'Beta', 'Gamma']);
  FStrip.TabIndex := 0;
  FStrip.TabsClosable := True;
  FStrip.OnTabClose := @Closing;
  FStrip.SetBounds(0, 0, STRIP_W, STRIP_H);
  FTarget := FStrip;
  Theme('');
end;

procedure TTabStripCloseTest.TearDown;
begin
  FForm.Free;
  FCtl.Free;
end;

{ ARoot: declarations for :root. ACloseRule: the TyTabClose rule, when the lime square one
  is not what the test wants. }
procedure TTabStripCloseTest.Theme(const ARoot: string; const ACloseRule: string);
var
  css: string;
begin
  css := BaseCss;
  if ACloseRule <> '' then css := css + ACloseRule else css := css + LimeSquareChip;
  if ARoot <> '' then css := ':root { ' + ARoot + ' } ' + css;
  FCtl.LoadThemeCss(css);
end;

procedure TTabStripCloseTest.TabStateOf(Sender: TObject; AIndex: Integer; var AState: TTyTabState);
begin
  if (AIndex >= 0) and (AIndex <= 7) then
  begin
    AState.Modified := AIndex in FModified;
    AState.Pinned := AIndex in FPinned;
  end;
end;

procedure TTabStripCloseTest.PinClicked(Sender: TObject; AIndex: Integer);
begin
  Inc(FPinClicks);
end;

procedure TTabStripCloseTest.Closing(Sender: TObject; AIndex: Integer; var AllowClose: Boolean);
begin
  Inc(FCloses);
  FClosedIndex := AIndex;
end;

function TTabStripCloseTest.Slot(AIndex: Integer): TRect;
begin
  Result := FTarget.ToScreenRect(FTarget.TyTabCloseRect(AIndex));
  AssertTrue('tab ' + IntToStr(AIndex) + ' has a close slot',
    (Result.Right > Result.Left) and (Result.Bottom > Result.Top));
end;

function TTabStripCloseTest.SlotMid(AIndex: Integer): TPoint;
var
  r: TRect;
begin
  r := Slot(AIndex);
  Result := Point((r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2);
end;

{ A point on the tab, well clear of its close slot. }
function TTabStripCloseTest.CaptionPoint(AIndex: Integer): TPoint;
var
  r: TRect;
begin
  r := FTarget.HeaderRectShifted(AIndex);
  Result := Point(r.Left + 4, (r.Top + r.Bottom) div 2);
end;

function TTabStripCloseTest.Shot: TBGRABitmap;
var
  bmp: TBitmap;
begin
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(FTarget.Width, FTarget.Height);
    bmp.Canvas.Brush.Color := TColor($808080);
    bmp.Canvas.FillRect(0, 0, FTarget.Width, FTarget.Height);
    TStripCrack(FTarget).RenderTo(bmp.Canvas, Rect(0, 0, FTarget.Width, FTarget.Height), 96);
    Result := TBGRABitmap.Create(bmp);
  finally
    bmp.Free;
  end;
end;

{ How many pixels of the slot are drawn in AInk. }
function TTabStripCloseTest.InSlot(AIndex: Integer; AInk: TSlotInk): Integer;
var
  img: TBGRABitmap;
  r: TRect;
  x, y: Integer;
begin
  Result := 0;
  r := Slot(AIndex);
  img := Shot;
  try
    for y := r.Top to r.Bottom - 1 do
      for x := r.Left to r.Right - 1 do
        if IsInk(img.GetPixel(x, y), AInk) then Inc(Result);
  finally
    img.Free;
  end;
end;

function TTabStripCloseTest.SlotPixel(AIndex, ADx, ADy: Integer): TBGRAPixel;
var
  img: TBGRABitmap;
  r: TRect;
begin
  r := Slot(AIndex);
  img := Shot;
  try
    Result := img.GetPixel(r.Left + ADx, r.Top + ADy);
  finally
    img.Free;
  end;
end;

{ One pixel in from the slot's corner: inside a square chip, outside a round one, and
  clear of the mark, which keeps to the middle of the slot. }
function TTabStripCloseTest.CornerIs(AIndex: Integer; AInk: TSlotInk): Boolean;
begin
  Result := IsInk(SlotPixel(AIndex, 1, 1), AInk);
end;

{ The middle of the slot's top edge, one pixel in: inside a chip of either shape. }
function TTabStripCloseTest.EdgeMidIs(AIndex: Integer; AInk: TSlotInk): Boolean;
var
  r: TRect;
begin
  r := Slot(AIndex);
  Result := IsInk(SlotPixel(AIndex, (r.Right - r.Left) div 2, 1), AInk);
end;

procedure TTabStripCloseTest.Hover(const APoint: TPoint);
begin
  TStripCrack(FTarget).MouseMove([], APoint.X, APoint.Y);
end;

procedure TTabStripCloseTest.Press(const APoint: TPoint);
begin
  TStripCrack(FTarget).MouseDown(mbLeft, [ssLeft], APoint.X, APoint.Y);
  TStripCrack(FTarget).MouseUp(mbLeft, [], APoint.X, APoint.Y);
end;

procedure TTabStripCloseTest.Leave;
begin
  TStripCrack(FTarget).MouseLeave;
end;

{ ---- which tabs show the button ---- }

procedure TTabStripCloseTest.EveryTabShowsItsButtonByDefault;
var
  i: Integer;
begin
  AssertEquals('the theme carries the default', 'always',
    FCtl.Model.ResolveToken('--tab-close-show'));
  for i := 0 to 2 do
    AssertTrue('tab ' + IntToStr(i) + ' shows its button', InSlot(i, siBlue) > 3);
  AssertTrue('always', TyTabCloseShowOf('always') = tcsAlways);
  AssertTrue('active', TyTabCloseShowOf('active') = tcsActive);
  AssertTrue('hover',  TyTabCloseShowOf('hover') = tcsHover);
  AssertTrue('nothing is always', TyTabCloseShowOf('') = tcsAlways);
end;

procedure TTabStripCloseTest.TheShowWordIsReadWhateverItsCase;
begin
  AssertTrue('upper case', TyTabCloseShowOf('ACTIVE') = tcsActive);
  AssertTrue('padded', TyTabCloseShowOf('  Hover ') = tcsHover);
  Theme('--tab-close-show: Active;');
  AssertEquals('a tab that is not current', 0, InSlot(1, siBlue));
end;

procedure TTabStripCloseTest.ActiveShowsTheButtonOnTheCurrentTabOnly;
begin
  Theme('--tab-close-show: active;');
  AssertTrue('the current tab keeps its button', InSlot(0, siBlue) > 3);
  AssertEquals('the second tab', 0, InSlot(1, siBlue));
  AssertEquals('the third tab', 0, InSlot(2, siBlue));

  FStrip.TabIndex := 2;
  AssertEquals('the tab that was current', 0, InSlot(0, siBlue));
  AssertEquals('the second tab still', 0, InSlot(1, siBlue));
  AssertTrue('the tab that is current now', InSlot(2, siBlue) > 3);
end;

procedure TTabStripCloseTest.AnUnknownShowWordShowsEveryButton;
var
  i: Integer;
begin
  Theme('--tab-close-show: sometimes;');
  for i := 0 to 2 do
    AssertTrue('tab ' + IntToStr(i) + ' shows its button', InSlot(i, siBlue) > 3);
end;

procedure TTabStripCloseTest.AHiddenButtonKeepsItsSlot;
var
  hdr, cls: array[0..2] of TRect;
  cur: TRect;
  i: Integer;
begin
  for i := 0 to 2 do
  begin
    hdr[i] := FStrip.TyTabHeaderRect(i);
    cls[i] := FStrip.TyTabCloseRect(i);
  end;
  Theme('--tab-close-show: active;');
  for i := 0 to 2 do
  begin
    cur := FStrip.TyTabHeaderRect(i);
    AssertTrue('tab ' + IntToStr(i) + ' is as wide as before',
      CompareMem(@hdr[i], @cur, SizeOf(TRect)));
    cur := FStrip.TyTabCloseRect(i);
    AssertTrue('tab ' + IntToStr(i) + ' keeps its slot where it was',
      CompareMem(@cls[i], @cur, SizeOf(TRect)));
    AssertTrue('and the slot is a real one', cls[i].Right > cls[i].Left);
  end;
end;

procedure TTabStripCloseTest.AClickOnAHiddenButtonSelectsTheTab;
begin
  Theme('--tab-close-show: active;');
  Press(SlotMid(1));
  AssertEquals('nothing was asked to close', 0, FCloses);
  AssertEquals('no tab left', 3, FStrip.Tabs.Count);
  AssertEquals('the click selected the tab', 1, FStrip.TabIndex);

  Press(SlotMid(1));   // current now, so its button is there
  AssertEquals('the button that shows closes', 1, FCloses);
  AssertEquals('that tab', 1, FClosedIndex);
  AssertEquals('one tab fewer', 2, FStrip.Tabs.Count);
end;

procedure TTabStripCloseTest.AHiddenButtonDoesNotLightUnderThePointer;
begin
  Theme('--tab-close-show: active;');
  Hover(SlotMid(1));
  AssertEquals('no button there, nothing to light', -1, FStrip.TyTabHoverClose);
  AssertEquals('and no chip', 0, InSlot(1, siLime));

  Hover(SlotMid(0));
  AssertEquals('the current tab''s button lights', 0, FStrip.TyTabHoverClose);
  AssertTrue('with the theme''s chip', InSlot(0, siLime) > 60);
end;

procedure TTabStripCloseTest.HoverShowsTheButtonOfTheTabUnderThePointer;
begin
  Theme('--tab-close-show: hover;');
  AssertTrue('the current tab', InSlot(0, siBlue) > 3);
  AssertEquals('no pointer: the second tab', 0, InSlot(1, siBlue));
  AssertEquals('no pointer: the third tab', 0, InSlot(2, siBlue));

  Hover(CaptionPoint(1));
  AssertTrue('the tab under the pointer', InSlot(1, siBlue) > 3);
  AssertEquals('not the one beside it', 0, InSlot(2, siBlue));
  AssertTrue('the current tab keeps its own', InSlot(0, siBlue) > 3);

  Leave;
  AssertEquals('the pointer left', 0, InSlot(1, siBlue));
end;

procedure TTabStripCloseTest.HoverClosesTheTabUnderThePointer;
begin
  Theme('--tab-close-show: hover;');
  Hover(SlotMid(1));
  AssertEquals('the button under the pointer lights', 1, FStrip.TyTabHoverClose);
  Press(SlotMid(1));
  AssertEquals('and closes', 1, FCloses);
  AssertEquals('that tab', 1, FClosedIndex);
end;

{ The pointer is on a tab whenever a press lands on it, whether or not a move was seen
  first -- after a close, the next tab slides under a pointer that never moved. }
procedure TTabStripCloseTest.InHoverModeAPressOnTheButtonClosesWithoutAMoveFirst;
begin
  Theme('--tab-close-show: hover;');
  Press(SlotMid(2));
  AssertEquals('closed', 1, FCloses);
  AssertEquals('that tab', 2, FClosedIndex);
end;

procedure TTabStripCloseTest.OneStripHidesItsButtonsOnItsOwn;
begin
  FStrip.StyleOverride := '--tab-close-show: active;';
  AssertEquals('hidden by the strip''s own override', 0, InSlot(1, siBlue));
  AssertTrue('the current tab keeps its button', InSlot(0, siBlue) > 3);
  FStrip.StyleOverride := '';
  AssertTrue('the theme still says always', InSlot(1, siBlue) > 3);
end;

procedure TTabStripCloseTest.APageControlHidesItsButtonsToo;
var
  pc: TTyPageControl;
begin
  pc := TTyPageControl.Create(FForm);
  pc.Parent := FForm;
  pc.Controller := FCtl;
  pc.Font.PixelsPerInch := 96;
  pc.SetBounds(0, 40, STRIP_W, 120);
  pc.TabsClosable := True;
  pc.AddPage('Alpha');
  pc.AddPage('Beta');
  pc.AddPage('Gamma');
  pc.ActivePageIndex := 0;
  FTarget := pc;

  AssertTrue('every page shows its button first', InSlot(1, siBlue) > 3);
  Theme('--tab-close-show: active;');
  AssertTrue('the current page', InSlot(0, siBlue) > 3);
  AssertEquals('another page', 0, InSlot(1, siBlue));
end;

{ ---- what the button looks like ---- }

procedure TTabStripCloseTest.WithNoTokenTheButtonIsTheThemeOne;
begin
  AssertTrue('the mark is the tab''s ink', InSlot(1, siBlue) > 3);
  AssertEquals('no chip at rest', 0, InSlot(1, siLime));
  Hover(SlotMid(1));
  AssertTrue('the theme''s chip under the pointer', InSlot(1, siLime) > 60);
  AssertTrue('square, as TyTabClose says', CornerIs(1, siLime));
  AssertTrue('the mark still the tab''s ink', InSlot(1, siBlue) > 3);
end;

procedure TTabStripCloseTest.TheMarkTakesItsOwnColour;
var
  i: Integer;
begin
  Theme('--tab-close-color: #FF0000;');
  for i := 0 to 2 do
  begin
    AssertTrue('tab ' + IntToStr(i) + ': the mark is red', InSlot(i, siRed) > 3);
    AssertEquals('tab ' + IntToStr(i) + ': and no longer the tab''s ink', 0, InSlot(i, siBlue));
  end;
end;

procedure TTabStripCloseTest.AColourThatIsNoColourLeavesTheMarkAlone;
begin
  Theme('--tab-close-color: banana; --tab-close-background: banana;');
  AssertTrue('the tab''s ink', InSlot(1, siBlue) > 3);
  AssertEquals('no red', 0, InSlot(1, siRed));
  AssertEquals('no chip', 0, InSlot(1, siYellow));
end;

procedure TTabStripCloseTest.AChipSitsBehindTheMarkAtRest;
var
  i: Integer;
begin
  AssertEquals('no token, no chip', 0, InSlot(1, siYellow));
  Theme('--tab-close-background: #FFFF00; --tab-close-color: #FF0000;');
  for i := 0 to 2 do
  begin
    AssertTrue('tab ' + IntToStr(i) + ': the chip', InSlot(i, siYellow) > 60);
    AssertTrue('tab ' + IntToStr(i) + ': the mark on it', InSlot(i, siRed) > 3);
  end;
  AssertTrue('square, as TyTabClose says', CornerIs(1, siYellow));
end;

procedure TTabStripCloseTest.UnderThePointerTheMarkAndTheChipChange;
begin
  Theme('--tab-close-color: #FF0000; --tab-close-background: #FFFF00; ' +
        '--tab-close-hover-color: #000000; --tab-close-hover-background: #00FFFF;');
  Hover(SlotMid(1));
  AssertTrue('the hover chip', InSlot(1, siCyan) > 60);
  AssertTrue('the hover mark', InSlot(1, siBlack) > 3);
  AssertEquals('the resting mark colour is gone', 0, InSlot(1, siRed));
  AssertEquals('the theme''s chip is not drawn', 0, InSlot(1, siLime));

  AssertTrue('a tab the pointer is not on: its resting chip', InSlot(0, siYellow) > 60);
  AssertTrue('and its resting mark', InSlot(0, siRed) > 3);
  AssertEquals('no hover chip there', 0, InSlot(0, siCyan));
end;

{ Half-transparent cyan: over the white tab it stays blue-full; over a yellow chip it
  would not. }
procedure TTabStripCloseTest.AHoverChipReplacesTheRestingChip;
var
  px: TBGRAPixel;
begin
  Theme('--tab-close-background: #FFFF00; --tab-close-hover-background: rgba(0, 255, 255, 0.5);');
  Hover(SlotMid(1));
  px := SlotPixel(1, 1, 1);
  AssertTrue('a chip is there (red ' + IntToStr(px.red) + ')', px.red < 230);
  AssertTrue('on the tab, not on the yellow chip (blue ' + IntToStr(px.blue) + ')', px.blue > 225);
end;

procedure TTabStripCloseTest.WithoutAHoverColourTheMarkKeepsItsRestingColour;
begin
  Theme('--tab-close-color: #FF0000;');
  Hover(SlotMid(1));
  AssertTrue('still red', InSlot(1, siRed) > 3);
  AssertEquals('not the tab''s ink', 0, InSlot(1, siBlue));
  AssertTrue('on the theme''s chip, as before', InSlot(1, siLime) > 60);
end;

{ Half-transparent blue as the theme's chip: over the yellow resting chip the corner is
  neither plain yellow (blue 0) nor what it is over the white tab (blue 255). }
procedure TTabStripCloseTest.WithoutAHoverChipTheThemeChipLiesOverTheRestingOne;
var
  px: TBGRAPixel;
begin
  Theme('--tab-close-background: #FFFF00;',
        'TyTabClose { background: rgba(0, 0, 255, 0.5); border-radius: 0px; }');
  Hover(SlotMid(1));
  px := SlotPixel(1, 1, 1);
  AssertTrue('the theme''s chip is drawn (blue ' + IntToStr(px.blue) + ')', px.blue > 50);
  AssertTrue('over the resting chip (blue ' + IntToStr(px.blue) + ')', px.blue < 225);
end;

procedure TTabStripCloseTest.TheChipTakesItsRadiusFromTheToken;
begin
  Theme('--tab-close-background: #FFFF00; --tab-close-radius: 999px;');
  AssertFalse('a circle leaves the corner alone', CornerIs(1, siYellow));
  AssertTrue('and fills the middle of an edge', EdgeMidIs(1, siYellow));

  Theme('--tab-close-hover-background: #00FFFF; --tab-close-radius: 999px;');
  Hover(SlotMid(1));
  AssertFalse('the hover chip is a circle too', CornerIs(1, siCyan));
  AssertTrue('filled at the middle of an edge', EdgeMidIs(1, siCyan));

  Theme('--tab-close-radius: 999px;');
  AssertFalse('and so is the theme''s chip', CornerIs(1, siLime));
  AssertTrue('filled at the middle of an edge', EdgeMidIs(1, siLime));

  Leave;   // the resting chip again, with nothing over it
  Theme('--tab-close-background: #FFFF00; --tab-close-radius: 0px;',
        'TyTabClose { background: #00FF00; border-radius: 7px; }');
  AssertTrue('0px squares a chip the rule would round', CornerIs(1, siYellow));
end;

procedure TTabStripCloseTest.WithoutARadiusTokenTheChipFollowsTyTabClose;
begin
  Theme('--tab-close-background: #FFFF00;',
        'TyTabClose { background: #00FF00; border-radius: 7px; }');
  AssertFalse('rounded by the rule', CornerIs(1, siYellow));
  AssertTrue('filled at the middle of an edge', EdgeMidIs(1, siYellow));
end;

procedure TTabStripCloseTest.OneStripRestylesItsButtonOnItsOwn;
begin
  FStrip.StyleOverride :=
    '--tab-close-color: #FF0000; --tab-close-background: #FFFF00; ' +
    '--tab-close-hover-color: #000000; --tab-close-hover-background: #00FFFF; ' +
    '--tab-close-radius: 999px;';
  AssertTrue('its own mark colour', InSlot(1, siRed) > 3);
  AssertTrue('its own chip', InSlot(1, siYellow) > 60);
  AssertFalse('its own radius', CornerIs(1, siYellow));
  Hover(SlotMid(1));
  AssertTrue('its own hover chip', InSlot(1, siCyan) > 60);
  AssertTrue('its own hover mark', InSlot(1, siBlack) > 3);
  Leave;

  FStrip.StyleOverride := '';
  AssertEquals('the theme sets none of them: no red', 0, InSlot(1, siRed));
  AssertEquals('no chip', 0, InSlot(1, siYellow));
end;

procedure TTabStripCloseTest.OneStripSizesItsButtonOnItsOwn;
var
  r: TRect;
begin
  r := Slot(1);
  AssertEquals('the theme''s size', 14, r.Right - r.Left);
  FStrip.StyleOverride := '--tab-close-size: 20px;';
  r := Slot(1);
  AssertEquals('the strip''s own width', 20, r.Right - r.Left);
  AssertEquals('and height', 20, r.Bottom - r.Top);
end;

{ ---- the mark itself ---- }

{ A space is a glyph the theme asked for and that draws nothing: the override was taken. }
procedure TTabStripCloseTest.TheMarkFollowsTheTabGlyphToken;
begin
  AssertTrue('the built-in x', InSlot(1, siBlue) > 3);
  Theme('--glyph-tab-close: "Arial" "\20";');
  AssertEquals('replaced by the tab''s own glyph', 0, InSlot(1, siBlue));
end;

procedure TTabStripCloseTest.WithoutATabGlyphTheMarkFollowsTheCloseGlyph;
begin
  Theme('--glyph-close: "Arial" "\20";');
  AssertEquals('replaced by the close glyph', 0, InSlot(1, siBlue));
end;

procedure TTabStripCloseTest.TheTabGlyphWinsOverTheCloseGlyph;
begin
  Theme('--glyph-close: "Arial" "\20"; --glyph-tab-close: "Arial" "\58";');
  AssertTrue('the tab''s X, not the blank close glyph', InSlot(1, siBlue) > 3);
end;

procedure TTabStripCloseTest.AReplacedMarkTakesTheMarkColour;
begin
  Theme('--glyph-tab-close: "Arial" "\58"; --tab-close-color: #FF0000;');
  AssertTrue('the glyph is red', InSlot(1, siRed) > 3);
  AssertEquals('not the tab''s ink', 0, InSlot(1, siBlue));
end;

procedure TTabStripCloseTest.OneStripChangesItsMarkOnItsOwn;
begin
  FStrip.StyleOverride := '--glyph-tab-close: "Arial" "\20";';
  AssertEquals('replaced by the strip''s own glyph', 0, InSlot(1, siBlue));
  FStrip.StyleOverride := '';
  AssertTrue('the built-in x again', InSlot(1, siBlue) > 3);
end;

procedure TTabStripCloseTest.ATabGlyphThatIsNoGlyphLeavesTheMark;
begin
  Theme('--glyph-tab-close: banana;');
  AssertTrue('the built-in x', InSlot(1, siBlue) > 3);
  Theme('--glyph-tab-close: banana; --glyph-close: "Arial" "\20";');
  AssertEquals('or the close glyph, when the theme has one', 0, InSlot(1, siBlue));
end;

{ The recipe the docs give: circle-x from the bundled Lucide font. The built-in x inks 12
  pixels of the slot; a ring with an x in it inks several times that. The font is registered
  with the process by the first Lucide component, here the shared TyLucideFont. }
procedure TTabStripCloseTest.TheBundledIconFontDrawsTheMark;
var
  builtIn: Integer;
begin
  AssertNotNull('the Lucide font', TyLucideFont);
  builtIn := InSlot(1, siBlue);
  Theme('--glyph-tab-close: "lucide" "\e084";');
  AssertTrue('circle-x inks more of the slot than the built-in x (' +
    IntToStr(InSlot(1, siBlue)) + ' against ' + IntToStr(builtIn) + ')',
    InSlot(1, siBlue) > builtIn + 12);
end;

{ ---- beside the tab states ---- }

{ A modified tab's dot gives way to the close glyph under the pointer. Where the button is
  kept off screen there is nothing to give way to: the dot stays, and a click is the tab's. }
procedure TTabStripCloseTest.AModifiedTabKeepsItsDotWhereItsButtonIsHidden;
begin
  Theme('--tab-close-show: active;');
  FModified := [0, 1];
  FStrip.OnGetTabState := @TabStateOf;
  AssertTrue('no pointer: the dot', FStrip.TabSlotMark(1) = tsmModified);
  Hover(CaptionPoint(1));
  AssertTrue('pointer on a tab that is not current: still the dot', FStrip.TabSlotMark(1) = tsmModified);
  Hover(CaptionPoint(0));
  AssertTrue('pointer on the current tab: its close glyph', FStrip.TabSlotMark(0) = tsmClose);

  Press(SlotMid(1));
  AssertEquals('a click on the dot closes nothing', 0, FCloses);
  AssertEquals('it selects the tab', 1, FStrip.TabIndex);
end;

procedure TTabStripCloseTest.APinnedTabKeepsItsPinAndItsClick;
begin
  Theme('--tab-close-show: active;');
  FPinned := [1];
  FStrip.OnGetTabState := @TabStateOf;
  FStrip.OnTabPinClick := @PinClicked;
  AssertTrue('a pin is not a close button: it shows', FStrip.TabSlotMark(1) = tsmPin);
  Hover(SlotMid(1));
  AssertEquals('and lights under the pointer', 1, FStrip.TyTabHoverClose);
  Press(SlotMid(1));
  AssertEquals('and takes its click', 1, FPinClicks);
  AssertEquals('which closes nothing', 0, FCloses);
end;

procedure TTabStripCloseTest.TheCloseLookIsNotThePins;
begin
  Theme('--tab-close-color: #FF0000; --tab-close-background: #FFFF00; ' +
        '--tab-close-hover-background: #00FFFF;');
  FPinned := [1];
  FStrip.OnGetTabState := @TabStateOf;
  AssertEquals('no resting chip behind a pin', 0, InSlot(1, siYellow));
  AssertEquals('the pin is not in the close colour', 0, InSlot(1, siRed));
  AssertTrue('it keeps the tab''s ink', InSlot(1, siBlue) > 3);
  AssertTrue('a close button beside it has the chip', InSlot(2, siYellow) > 60);
  AssertTrue('and the colour', InSlot(2, siRed) > 3);

  Hover(SlotMid(1));
  AssertTrue('under the pointer the pin takes the theme''s chip', InSlot(1, siLime) > 60);
  AssertEquals('not the close button''s', 0, InSlot(1, siCyan));
end;

{ --tab-close-show is about the button. A middle click closes a closable tab as before. }
procedure TTabStripCloseTest.AMiddleClickClosesATabWhoseButtonIsHidden;
var
  p: TPoint;
begin
  Theme('--tab-close-show: active;');
  p := CaptionPoint(1);
  TStripCrack(FTarget).MouseDown(mbMiddle, [ssMiddle], p.X, p.Y);
  TStripCrack(FTarget).MouseUp(mbMiddle, [], p.X, p.Y);
  AssertEquals('closed', 1, FCloses);
  AssertEquals('that tab', 1, FClosedIndex);
end;

{ The pointer rests on the current tab's button and the selection moves away by the
  keyboard: the button goes off screen, and its chip with it. }
procedure TTabStripCloseTest.AButtonThatWentOffScreenUnderThePointerIsNotLit;
begin
  Theme('--tab-close-show: active;');
  Hover(SlotMid(0));
  AssertTrue('lit while it is there', InSlot(0, siLime) > 60);
  FStrip.TabIndex := 2;
  AssertEquals('no button', 0, InSlot(0, siBlue));
  AssertEquals('and no chip left behind', 0, InSlot(0, siLime));
end;

initialization
  RegisterTest(TTabStripCloseTest);
end.
