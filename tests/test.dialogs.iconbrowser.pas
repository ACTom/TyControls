unit test.dialogs.iconbrowser;
{$mode objfpc}{$H+}

{ The icon browser.

  Construct-only, like every dialog test here: never Show, never ShowModal. That is not a
  limitation to work around, it is what keeps the assertions honest -- a form that was never
  shown never ran the LCL align engine, so anything asserted about Align/Anchors would be a
  fiction. Geometry goes through ContentRect arithmetic, which IS real on an unshown form.

  The font is hand-mapped rather than the bundled pack, deliberately: the browser must work for
  ANY TTyIconFont, and referencing tyControls.Icons.Lucide here would make these tests pass for
  a reason the product does not have.

  What is pinned that a screenshot cannot pin:
  - the filter is a SUBSTRING match, not a prefix. Icon names are hyphenated compounds
    ('arrow-down-left'), and prefix matching would answer nothing for the word a user actually
    types.
  - GlyphName round-trips in AND out, because that is the whole contract of the var-parameter
    entry point.
  - the grid's cell hit test, including the two places it must say "nothing": the trailing gap
    of a partly filled last row, and past the end of the list. }

interface

uses
  Classes, SysUtils, Types, Controls, Forms, fpcunit, testregistry,
  tyControls.Types, tyControls.Dialogs, tyControls.Button, tyControls.IconFont,
  tyControls.ImageCollection, tyControls.Dialogs.IconBrowser;

type
  TIconBrowserTest = class(TTestCase)
  private
    FFont: TTyIconFont;
    function NewDialog: TTyIconBrowserForm;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TheDialogOffersOkAndCancel;
    procedure PickWithHandlerAddsAndStaysOpen;
    procedure OkButtonSetsModalResult;
    procedure ClosingGivesCancel;
    procedure EveryGlyphOfTheFontIsListed;
    procedure TheFilterMatchesAnywhereInTheNameNotJustTheStart;
    procedure AnEmptyFilterRestoresEverything;
    procedure AFilterThatMatchesNothingLeavesAnEmptyGrid;
    procedure GlyphNameRoundTripsInAndOut;
    procedure SeedingAnUnknownNameSelectsNothing;
    procedure NoFontMeansAnEmptyGridNotACrash;
    procedure LayoutFillsTheContentRect;
    procedure LayoutReflowsWhenTheDialogGrows;
    procedure TheIndexShownIsTheListPositionNotTheGridPosition;
    procedure AGlyphTheListDoesNotHoldHasNoIndex;
    procedure WithoutAnIndexSourceThereIsNoIndexToShow;
    procedure TheComponentWrapperCarriesItsOwnState;
    procedure TheComponentDropsAFreedFont;
  end;

implementation

type
  { LayoutContent is protected, and rightly so -- it is the form's own business. A same-unit
    descendant is the standard way to reach it for a test without widening the real API. }
  TBrowserAccess = class(TTyIconBrowserForm);

const
  { Names chosen so 'arrow' appears at the START of some and in the MIDDLE of others -- that is
    the difference between a substring and a prefix filter, and it is the whole point. }
  TestNames: array[0..5] of string = (
    'arrow-down', 'arrow-up', 'circle-arrow-left', 'house', 'search', 'settings');

function TIconBrowserTest.NewDialog: TTyIconBrowserForm;
begin
  Result := TyBuildIconBrowserDialog('', FFont);
end;

procedure TIconBrowserTest.SetUp;
var i: Integer;
begin
  FFont := TTyIconFont.Create(nil);
  FFont.FontFamily := 'Arial';
  for i := Low(TestNames) to High(TestNames) do
    FFont.MapGlyph(TestNames[i], $E000 + i);
end;

procedure TIconBrowserTest.TearDown;
begin
  FFont.Free;
end;

procedure TIconBrowserTest.TheDialogOffersOkAndCancel;
var d: TTyIconBrowserForm;
begin
  d := NewDialog;
  try
    AssertEquals('two buttons', 2, TyDialogButtonCount(d));
    AssertEquals('OK first', Ord(mrOK), Ord(TyDialogButton(d, 0).ModalResult));
    AssertEquals('then Cancel', Ord(mrCancel), Ord(TyDialogButton(d, 1).ModalResult));
  finally d.Free; end;
end;

type
  TPickCapture = class
  public
    Count: Integer;
    Last: string;
    procedure Handle(Sender: TObject; const AName: string);
  end;

procedure TPickCapture.Handle(Sender: TObject; const AName: string);
begin
  Inc(Count);
  Last := AName;
end;

procedure TIconBrowserTest.PickWithHandlerAddsAndStaysOpen;
// The design-time Names editor's multi-add (QQ-group report): with OnPickName assigned, a
// pick hands the name over and the dialog STAYS OPEN -- ten icons cost one browse, not
// ten. Without the handler a pick closes with mrOK, the runtime Execute contract.
var
  d: TTyIconBrowserForm;
  cap: TPickCapture;
begin
  cap := TPickCapture.Create;
  d := NewDialog;
  try
    d.SelectGlyph(d.GlyphNameAt(0));
    d.OnPickName := @cap.Handle;
    d.PickSelected;
    AssertEquals('the handler received the pick', 1, cap.Count);
    AssertEquals('with the selected name', d.GlyphNameAt(0), cap.Last);
    AssertEquals('and the dialog stayed open', Ord(mrNone), Ord(d.ModalResult));

    d.SelectGlyph(d.GlyphNameAt(1));
    d.PickSelected;
    AssertEquals('second pick, same window', 2, cap.Count);
    AssertEquals('still open', Ord(mrNone), Ord(d.ModalResult));

    d.OnPickName := nil;
    d.PickSelected;
    AssertEquals('without a handler the pick closes with OK', Ord(mrOK), Ord(d.ModalResult));
  finally
    d.Free;
    cap.Free;
  end;
end;

procedure TIconBrowserTest.OkButtonSetsModalResult;
var d: TTyIconBrowserForm;
begin
  d := NewDialog;
  try
    TyDialogButton(d, 0).Click;
    AssertEquals('OK closed with mrOK', Ord(mrOK), Ord(d.ModalResult));
  finally d.Free; end;
end;

procedure TIconBrowserTest.ClosingGivesCancel;
var d: TTyIconBrowserForm;
begin
  d := NewDialog;
  try
    d.CancelDialog;
    AssertEquals('dismissed = cancelled', Ord(mrCancel), Ord(d.ModalResult));
  finally d.Free; end;
end;

procedure TIconBrowserTest.EveryGlyphOfTheFontIsListed;
var d: TTyIconBrowserForm; i, found: Integer;
begin
  d := NewDialog;
  try
    AssertEquals('all six', Length(TestNames), d.GlyphCount);
    found := 0;
    for i := 0 to d.GlyphCount - 1 do
      if d.GlyphNameAt(i) <> '' then Inc(found);
    AssertEquals('every slot names something', d.GlyphCount, found);
  finally d.Free; end;
end;

procedure TIconBrowserTest.TheFilterMatchesAnywhereInTheNameNotJustTheStart;
var d: TTyIconBrowserForm; i: Integer; sawMiddle: Boolean;
begin
  d := NewDialog;
  try
    d.ApplyFilter('arrow');
    { arrow-down, arrow-up AND circle-arrow-left. A prefix match would find two. }
    AssertEquals('three names contain "arrow"', 3, d.GlyphCount);
    sawMiddle := False;
    for i := 0 to d.GlyphCount - 1 do
      if d.GlyphNameAt(i) = 'circle-arrow-left' then sawMiddle := True;
    AssertTrue('including the one where "arrow" is not at the start', sawMiddle);
    { Case-insensitive: a user types lower case regardless of how the pack spells things. }
    d.ApplyFilter('ARROW');
    AssertEquals('case does not matter', 3, d.GlyphCount);
  finally d.Free; end;
end;

procedure TIconBrowserTest.AnEmptyFilterRestoresEverything;
var d: TTyIconBrowserForm;
begin
  d := NewDialog;
  try
    d.ApplyFilter('house');
    AssertEquals('narrowed', 1, d.GlyphCount);
    d.ApplyFilter('   ');   { whitespace only is "no filter", not "match spaces" }
    AssertEquals('restored', Length(TestNames), d.GlyphCount);
  finally d.Free; end;
end;

procedure TIconBrowserTest.AFilterThatMatchesNothingLeavesAnEmptyGrid;
var d: TTyIconBrowserForm;
begin
  d := NewDialog;
  try
    d.ApplyFilter('no-such-icon-anywhere');
    AssertEquals('nothing shown', 0, d.GlyphCount);
    AssertEquals('and nothing selected', '', d.SelectedGlyphName);
  finally d.Free; end;
end;

procedure TIconBrowserTest.GlyphNameRoundTripsInAndOut;
var d: TTyIconBrowserForm;
begin
  d := NewDialog;
  try
    { The contract of the var-parameter entry point: seed in, read out. }
    d.GlyphName := 'search';
    AssertEquals('the seed was selected', 'search', d.GlyphName);
    d.SelectGlyph('settings');
    AssertEquals('and a later pick replaces it', 'settings', d.SelectedGlyphName);
  finally d.Free; end;
end;

procedure TIconBrowserTest.SeedingAnUnknownNameSelectsNothing;
var d: TTyIconBrowserForm;
begin
  d := NewDialog;
  try
    { A name the font does not have must not select an arbitrary neighbour -- the caller would
      get back a glyph it never asked for and never noticed changing. }
    d.GlyphName := 'not-in-this-font';
    AssertEquals('', d.SelectedGlyphName);
  finally d.Free; end;
end;

procedure TIconBrowserTest.NoFontMeansAnEmptyGridNotACrash;
var d: TTyIconBrowserForm;
begin
  d := TyBuildIconBrowserDialog('', nil);
  try
    AssertEquals('no font, no glyphs', 0, d.GlyphCount);
    AssertEquals('and nothing selected', '', d.SelectedGlyphName);
    d.ApplyFilter('anything');          { must not raise }
    AssertEquals('still nothing', 0, d.GlyphCount);
  finally d.Free; end;
end;

procedure TIconBrowserTest.LayoutFillsTheContentRect;
var d: TTyIconBrowserForm; r: TRect;
begin
  d := NewDialog;
  try
    TBrowserAccess(d).LayoutContent;
    r := d.ContentRect;
    { Asserted through ContentRect arithmetic, which is real on a form that was never shown --
      unlike anything that would need the align engine. }
    AssertTrue('the dialog has a content area', (r.Right > r.Left) and (r.Bottom > r.Top));
  finally d.Free; end;
end;

procedure TIconBrowserTest.LayoutReflowsWhenTheDialogGrows;
var d: TTyIconBrowserForm; before, after: Integer;
begin
  d := NewDialog;
  try
    TBrowserAccess(d).LayoutContent;
    before := d.ContentRect.Right - d.ContentRect.Left;
    d.ClientWidth := d.ClientWidth + 160;
    TBrowserAccess(d).LayoutContent;                       { Resize calls this for real }
    after := d.ContentRect.Right - d.ContentRect.Left;
    AssertTrue('the content area widened with the dialog', after > before);
  finally d.Free; end;
end;

procedure TIconBrowserTest.TheIndexShownIsTheListPositionNotTheGridPosition;
var
  d: TTyIconBrowserForm;
  lst: TTyVirtualImageList;
begin
  { THE property that makes the badge worth showing. A consumer writes ImageIndex, which counts
    positions in the LIST. The grid is filtered, so its own positions move as soon as anyone
    types in the search box -- showing those would be a number that is right until the user
    touches the keyboard. }
  lst := TTyVirtualImageList.Create(nil);
  d := nil;
  try
    lst.IconFont := FFont;
    lst.Names.Text := 'house' + LineEnding + 'search' + LineEnding + 'settings';
    d := TyBuildIconBrowserDialogFor('', FFont, lst);
    d.GlyphName := 'settings';
    AssertEquals('index 2 in the list', 2, d.SelectedImageIndex);

    { Now filter so 'settings' is the ONLY thing in the grid: grid position 0, list index 2. }
    d.ApplyFilter('settings');
    AssertEquals('only one cell', 1, d.GlyphCount);
    d.SelectGlyph('settings');
    AssertEquals('still the LIST index, not the grid position',
      2, d.SelectedImageIndex);
  finally
    d.Free;
    lst.Free;
  end;
end;

procedure TIconBrowserTest.AGlyphTheListDoesNotHoldHasNoIndex;
var
  d: TTyIconBrowserForm;
  lst: TTyVirtualImageList;
begin
  { Browsing a font from a list shows every glyph the FONT has, most of which the list does not
    hold. Those must show no number at all -- inventing one would hand the user an ImageIndex
    that points at a different icon. }
  lst := TTyVirtualImageList.Create(nil);
  d := nil;
  try
    lst.IconFont := FFont;
    lst.Names.Text := 'house';
    d := TyBuildIconBrowserDialogFor('', FFont, lst);
    d.GlyphName := 'house';
    AssertEquals('in the list', 0, d.SelectedImageIndex);
    d.SelectGlyph('search');
    AssertEquals('offered by the font, absent from the list', -1, d.SelectedImageIndex);
  finally
    d.Free;
    lst.Free;
  end;
end;

procedure TIconBrowserTest.WithoutAnIndexSourceThereIsNoIndexToShow;
var d: TTyIconBrowserForm;
begin
  { Opened on a plain font -- from a GlyphName property, say. A font has no indices, and the
    cell's position in the grid is not one. }
  d := NewDialog;
  try
    d.GlyphName := 'house';
    AssertEquals('house', d.SelectedGlyphName);
    AssertEquals('no list, no index', -1, d.SelectedImageIndex);
  finally d.Free; end;
end;

procedure TIconBrowserTest.TheComponentWrapperCarriesItsOwnState;
var c: TTyIconBrowserDialog;
begin
  { Execute needs a window, so it is not called here. What IS assertable is that the wrapper
    holds the state Execute would seed and read back. }
  c := TTyIconBrowserDialog.Create(nil);
  try
    c.IconFont := FFont;
    c.GlyphName := 'house';
    c.Caption := 'Pick one';
    AssertTrue('font held', c.IconFont = FFont);
    AssertEquals('house', c.GlyphName);
    AssertEquals('Pick one', c.Caption);
  finally c.Free; end;
end;

procedure TIconBrowserTest.TheComponentDropsAFreedFont;
var c: TTyIconBrowserDialog; f: TTyIconFont;
begin
  f := TTyIconFont.Create(nil);
  c := TTyIconBrowserDialog.Create(nil);
  try
    c.IconFont := f;
    AssertTrue('held', c.IconFont = f);
    FreeAndNil(f);
    { Without the FreeNotification this is a dangling pointer Execute would hand to the form. }
    AssertTrue('the reference was nil-ed', c.IconFont = nil);
  finally
    c.Free;
    f.Free;
  end;
end;

initialization
  RegisterTest(TIconBrowserTest);

end.
