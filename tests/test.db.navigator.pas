unit test.db.navigator;
{$mode objfpc}{$H+}

{ The data-aware navigator (issue #34, plan Task 9): TTyDBNavigator.

  * when each button is enabled -- LCL's rules, Refresh as "open and not editing";
  * a click, made the way a user makes it (MouseDown + MouseUp on the button's rect), does the
    button's dataset method, BeforeAction first and OnClick after, and Delete asks first;
  * the visible buttons share the strip, across or down, mirrored right-to-left;
  * each button's hint;
  * what is painted: rendered on a sentinel ground, every visible button carries a mark, a
    disabled one in the :disabled colour, and a theme glyph or an image replaces the built-in
    mark;
  * the data source going away, and CM_GETDATALINK.

  The table is the suite's own -- ID and Name, three rows, its change log merged -- because
  Refresh has to work on it: a TBufDataset with no database behind it refreshes only with an
  empty change log. }

interface

uses
  Classes, SysUtils, Types, TypInfo, Controls, Forms, Graphics, LCLType, LMessages, DB,
  BufDataset, DBCtrls, fpcunit, testregistry, BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.DB.StrConsts, tyControls.DB.Navigator;

type
  TProbeDBNavigator = class(TTyDBNavigator)
  protected
    function ConfirmDeleteRecord: Boolean; override;
  public
    Asked: Integer;
    Answer: Boolean;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TDBNavigatorTest = class(TTestCase)
  private
    FForm: TForm;
    FDS: TBufDataset;
    FSrc: TDataSource;
    FNav: TProbeDBNavigator;
    FLog: TStringList;
    FRefreshes: Integer;
    FTheme: TTyStyleController;
    procedure LogBefore(Sender: TObject; Button: TDBNavButtonType);
    procedure LogClick(Sender: TObject; Button: TDBNavButtonType);
    procedure CountRefresh(DataSet: TDataSet);
    function Id: Integer;
    procedure Press(AButton: TDBNavButtonType; AMouse: TMouseButton = mbLeft);
    procedure Release(AButton: TDBNavButtonType; AMouse: TMouseButton = mbLeft);
    procedure Click(AButton: TDBNavButtonType);
    procedure AssertEnabled(const AWhen: string; AExpected: TDBNavButtonSet);
    function AskHint(AButton: TDBNavButtonType; out AShown: Boolean; out ACursorRect: TRect): string;
    { The navigator rendered on a magenta ground under a theme that paints the strip and the
      buttons black, an enabled mark white and a disabled one red; ACss is added to it. }
    function Render(const ACss: string): TBGRABitmap;
    function InkIn(ABmp: TBGRABitmap; const ARect: TRect; ARed: Boolean): Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestDefaults;
    procedure TestUnboundOrClosedDisablesEverything;
    procedure TestFirstRowDisablesFirstAndPrior;
    procedure TestLastRowDisablesNextAndLast;
    procedure TestBrowsingEnablesEditAndInsertNotPostAndCancel;
    procedure TestEditingSwapsThem;
    procedure TestReadOnlyDataSetDisablesTheChanges;
    procedure TestAutoEditOffLeavesEditToTheButton;
    procedure TestDisabledNavigatorDisablesEverything;
    procedure TestEmptyDataSetCannotDeleteOrMove;
    procedure TestMovingButtons;
    procedure TestEditPostAndCancelButtons;
    procedure TestInsertButton;
    procedure TestRefreshButton;
    procedure TestDeleteAsksFirst;
    procedure TestDeleteRefusedKeepsTheRecord;
    procedure TestDeleteWithoutConfirmDeleteDoesNotAsk;
    procedure TestBeforeActionComesBeforeAndOnClickAfter;
    procedure TestDisabledButtonDoesNothing;
    procedure TestReleaseOnAnotherButtonIsNoClick;
    procedure TestRightButtonIsNoClick;
    procedure TestHiddenButtonsLeaveTheirShareToTheOthers;
    procedure TestVerticalSharesTheHeight;
    procedure TestRightToLeftPutsFirstOnTheRight;
    procedure TestVerticalIsNotMirrored;
    procedure TestDefaultHintsAreTheTranslatedOnes;
    procedure TestAHintLineReplacesOnlyItsButton;
    procedure TestShowButtonHintsOffLeavesTheControlsHint;
    procedure TestHintsAssignedFromAListAreCopied;
    procedure TestEveryVisibleButtonCarriesAMark;
    procedure TestThemeGlyphReplacesTheBuiltInMark;
    procedure TestImagesReplaceTheMarks;
    procedure TestFreedDataSourceUnbinds;
    procedure TestDataSourceRemovedFromItsOwnerUnbinds;
    procedure TestGetDataLinkAnswersTheLink;
    procedure TestAFreshNavigatorWritesNoDefaults;
    procedure TestPropertiesSurviveAFormFile;
  end;

implementation

uses
  ImgList, test.db.edits;

type
  TNavInput = class(TWinControl);

const
  CRowNames: array[1..3] of string = ('One', 'Two', 'Three');
  { Black strip, black buttons, no borders: the only light on the bitmap is a mark. }
  CTheme =
    'TyDBNavigator { background: #000000; border-width: 0px; padding: 0px; } '
    + 'TyDBNavigatorButton { background: #000000; color: #FFFFFF; border-width: 0px; } '
    + 'TyDBNavigatorButton:disabled { color: #FF0000; opacity: 1; } ';

function ButtonName(AButton: TDBNavButtonType): string;
begin
  Result := GetEnumName(TypeInfo(TDBNavButtonType), Ord(AButton));
end;

function TProbeDBNavigator.ConfirmDeleteRecord: Boolean;
begin
  Inc(Asked);
  Result := Answer;
end;

procedure TProbeDBNavigator.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

{ ================================================================ TDBNavigatorTest ===== }

procedure TDBNavigatorTest.SetUp;
var
  r: Integer;
begin
  NeedDBWidgetSet;
  FLog := TStringList.Create;
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 400, 300);
  FDS := TBufDataset.Create(nil);
  FDS.FieldDefs.Add('ID', ftInteger);
  FDS.FieldDefs.Add('Name', ftString, 20);
  FDS.CreateDataset;
  for r := 1 to 3 do
    FDS.AppendRecord([r, CRowNames[r]]);
  FDS.MergeChangeLog;
  FDS.First;
  FDS.AfterRefresh := @CountRefresh;
  FSrc := TDataSource.Create(nil);
  FSrc.DataSet := FDS;
  FNav := TProbeDBNavigator.Create(FForm);
  FNav.Parent := FForm;
  FNav.SetBounds(8, 8, 300, 30);
  FNav.DataSource := FSrc;
end;

procedure TDBNavigatorTest.TearDown;
begin
  FreeAndNil(FForm);
  FreeAndNil(FSrc);
  FreeAndNil(FDS);
  FreeAndNil(FTheme);
  FreeAndNil(FLog);
end;

procedure TDBNavigatorTest.LogBefore(Sender: TObject; Button: TDBNavButtonType);
begin
  FLog.Add('before ' + ButtonName(Button) + ' at ' + IntToStr(Id));
end;

procedure TDBNavigatorTest.LogClick(Sender: TObject; Button: TDBNavButtonType);
begin
  FLog.Add('click ' + ButtonName(Button) + ' at ' + IntToStr(Id));
end;

procedure TDBNavigatorTest.CountRefresh(DataSet: TDataSet);
begin
  Inc(FRefreshes);
end;

function TDBNavigatorTest.Id: Integer;
begin
  Result := FDS.FieldByName('ID').AsInteger;
end;

procedure TDBNavigatorTest.Press(AButton: TDBNavButtonType; AMouse: TMouseButton);
var
  c: TPoint;
begin
  c := CenterPoint(FNav.ButtonRect(AButton));
  AssertFalse(ButtonName(AButton) + ' has a rect', IsRectEmpty(FNav.ButtonRect(AButton)));
  TNavInput(FNav).MouseDown(AMouse, [ssLeft], c.X, c.Y);
end;

procedure TDBNavigatorTest.Release(AButton: TDBNavButtonType; AMouse: TMouseButton);
var
  c: TPoint;
begin
  c := CenterPoint(FNav.ButtonRect(AButton));
  TNavInput(FNav).MouseUp(AMouse, [], c.X, c.Y);
end;

procedure TDBNavigatorTest.Click(AButton: TDBNavButtonType);
begin
  Press(AButton);
  Release(AButton);
end;

procedure TDBNavigatorTest.AssertEnabled(const AWhen: string; AExpected: TDBNavButtonSet);
var
  b: TDBNavButtonType;
begin
  for b := Low(TDBNavButtonType) to High(TDBNavButtonType) do
    AssertEquals(AWhen + ': ' + ButtonName(b), b in AExpected, FNav.ButtonEnabled(b));
end;

function TDBNavigatorTest.AskHint(AButton: TDBNavButtonType; out AShown: Boolean;
  out ACursorRect: TRect): string;
var
  info: THintInfo;
begin
  info := Default(THintInfo);
  info.HintControl := FNav;
  info.CursorPos := CenterPoint(FNav.ButtonRect(AButton));
  info.CursorRect := FNav.ClientRect;
  info.HintStr := FNav.Hint;   // what the application starts the message with
  AShown := FNav.Perform(CM_HINTSHOW, 0, LParam(PtrUInt(@info))) = 0;
  ACursorRect := info.CursorRect;
  Result := info.HintStr;
end;

function TDBNavigatorTest.Render(const ACss: string): TBGRABitmap;
var
  bmp: TBitmap;
begin
  FreeAndNil(FTheme);
  FTheme := TTyStyleController.Create(nil);
  FTheme.LoadThemeCss(CTheme + ACss);
  FNav.Controller := FTheme;
  FNav.Font.PixelsPerInch := 96;
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(FNav.Width, FNav.Height);
    bmp.Canvas.Brush.Color := clFuchsia;   // the sentinel: neither white nor red ink
    bmp.Canvas.FillRect(0, 0, FNav.Width, FNav.Height);
    FNav.Render(bmp.Canvas, Rect(0, 0, FNav.Width, FNav.Height), 96);
    Result := TBGRABitmap.Create(bmp);
  finally
    bmp.Free;
  end;
end;

function TDBNavigatorTest.InkIn(ABmp: TBGRABitmap; const ARect: TRect; ARed: Boolean): Integer;
var
  x, y: Integer;
  p: TBGRAPixel;
begin
  Result := 0;
  for y := ARect.Top to ARect.Bottom - 1 do
    for x := ARect.Left to ARect.Right - 1 do
    begin
      p := ABmp.GetPixel(x, y);
      if ARed then
      begin
        if (p.red > 100) and (p.red > p.green + 40) and (p.red > p.blue + 40) then Inc(Result);
      end
      else if (p.red > 200) and (p.green > 200) and (p.blue > 200) then
        Inc(Result);
    end;
end;

{ ------------------------------------------------------------------ defaults ----------- }

procedure TDBNavigatorTest.TestDefaults;
var
  n: TTyDBNavigator;
begin
  n := TTyDBNavigator.Create(nil);
  try
    AssertTrue('all ten buttons', n.VisibleButtons = DefaultDBNavigatorButtons);
    AssertEquals('ten visible', 10, n.VisibleButtonCount);
    AssertTrue('across', n.Direction = nbdHorizontal);
    AssertTrue('asks before deleting', n.ConfirmDelete);
    AssertTrue('button hints on', n.ShowButtonHints);
    AssertTrue('so the control shows hints', n.ShowHint);
    AssertFalse('not a tab stop: the buttons are not focusable', n.TabStop);
    AssertEquals('LCL''s width', 241, n.Width);
    AssertEquals('LCL''s height', 25, n.Height);
    AssertNull('unbound', n.DataSource);
  finally
    n.Free;
  end;
end;

{ ------------------------------------------------------------------ enabling ----------- }

procedure TDBNavigatorTest.TestUnboundOrClosedDisablesEverything;
begin
  FDS.Next;
  FNav.DataSource := nil;
  AssertEnabled('unbound', []);
  FNav.DataSource := FSrc;
  AssertEnabled('bound', DefaultDBNavigatorButtons - [nbPost, nbCancel]);
  FDS.Close;
  AssertEnabled('closed', []);
end;

procedure TDBNavigatorTest.TestFirstRowDisablesFirstAndPrior;
begin
  FDS.First;
  AssertEnabled('first row', DefaultDBNavigatorButtons - [nbFirst, nbPrior, nbPost, nbCancel]);
end;

{ M15 }
procedure TDBNavigatorTest.TestLastRowDisablesNextAndLast;
begin
  FDS.Last;
  AssertEnabled('last row', DefaultDBNavigatorButtons - [nbNext, nbLast, nbPost, nbCancel]);
end;

procedure TDBNavigatorTest.TestBrowsingEnablesEditAndInsertNotPostAndCancel;
begin
  FDS.First;
  FDS.Next;
  AssertEnabled('browsing a middle row', DefaultDBNavigatorButtons - [nbPost, nbCancel]);
end;

{ LCL keeps Insert and Delete while a record is edited (each ends the edit its own way);
  Refresh is not offered then -- it would throw the edit away. }
procedure TDBNavigatorTest.TestEditingSwapsThem;
begin
  FDS.First;
  FDS.Next;
  FDS.Edit;
  AssertEnabled('editing', DefaultDBNavigatorButtons - [nbEdit, nbRefresh]);
  FDS.Cancel;
  AssertEnabled('browsing again', DefaultDBNavigatorButtons - [nbPost, nbCancel]);
end;

{ Refresh stays: refreshing what one may only look at is what a viewer is for. }
procedure TDBNavigatorTest.TestReadOnlyDataSetDisablesTheChanges;
begin
  FDS.First;
  FDS.Next;
  FDS.ReadOnly := True;
  AssertEnabled('read-only dataset', [nbFirst, nbPrior, nbNext, nbLast, nbRefresh]);
  FSrc.AutoEdit := False;
  AssertEnabled('read-only, and no AutoEdit either', [nbFirst, nbPrior, nbNext, nbLast, nbRefresh]);
end;

{ AutoEdit is about typing into a control; the Edit button is how one edits without it. }
procedure TDBNavigatorTest.TestAutoEditOffLeavesEditToTheButton;
begin
  FSrc.AutoEdit := False;
  FDS.First;
  FDS.Next;
  AssertEnabled('no AutoEdit', DefaultDBNavigatorButtons - [nbPost, nbCancel]);
  Click(nbEdit);
  AssertTrue('the button edits', FDS.State = dsEdit);
end;

procedure TDBNavigatorTest.TestDisabledNavigatorDisablesEverything;
begin
  FDS.Next;
  FNav.Enabled := False;
  AssertEnabled('navigator disabled', []);
end;

procedure TDBNavigatorTest.TestEmptyDataSetCannotDeleteOrMove;
begin
  FDS.Filter := 'ID > 100';
  FDS.Filtered := True;
  AssertTrue('empty', FDS.IsEmpty);
  AssertEnabled('empty dataset', [nbInsert, nbEdit, nbRefresh]);
end;

{ ------------------------------------------------------------------ clicks ------------- }

procedure TDBNavigatorTest.TestMovingButtons;
begin
  FDS.First;
  Click(nbLast);
  AssertEquals('Last', 3, Id);
  Click(nbFirst);
  AssertEquals('First', 1, Id);
  Click(nbNext);
  AssertEquals('Next', 2, Id);
  Click(nbPrior);
  AssertEquals('Prior', 1, Id);
end;

procedure TDBNavigatorTest.TestEditPostAndCancelButtons;
begin
  Click(nbEdit);
  AssertTrue('Edit', FDS.State = dsEdit);
  FDS.FieldByName('Name').AsString := 'Changed';
  Click(nbPost);
  AssertTrue('Post ends the edit', FDS.State = dsBrowse);
  AssertEquals('and writes it', 'Changed', FDS.FieldByName('Name').AsString);
  Click(nbEdit);
  FDS.FieldByName('Name').AsString := 'Thrown away';
  Click(nbCancel);
  AssertTrue('Cancel ends the edit', FDS.State = dsBrowse);
  AssertEquals('and drops it', 'Changed', FDS.FieldByName('Name').AsString);
end;

procedure TDBNavigatorTest.TestInsertButton;
begin
  Click(nbInsert);
  AssertTrue('Insert', FDS.State = dsInsert);
  Click(nbCancel);
  AssertTrue('cancelled', FDS.State = dsBrowse);
  AssertEquals('nothing added', 3, FDS.RecordCount);
end;

procedure TDBNavigatorTest.TestRefreshButton;
begin
  FRefreshes := 0;
  Click(nbRefresh);
  AssertEquals('Refresh', 1, FRefreshes);
end;

{ M17 }
procedure TDBNavigatorTest.TestDeleteAsksFirst;
begin
  FNav.Answer := True;
  Click(nbDelete);
  AssertEquals('asked once', 1, FNav.Asked);
  AssertEquals('deleted', 2, FDS.RecordCount);
end;

procedure TDBNavigatorTest.TestDeleteRefusedKeepsTheRecord;
begin
  FNav.Answer := False;
  Click(nbDelete);
  AssertEquals('asked once', 1, FNav.Asked);
  AssertEquals('kept', 3, FDS.RecordCount);
  AssertEquals('still on it', 1, Id);
end;

procedure TDBNavigatorTest.TestDeleteWithoutConfirmDeleteDoesNotAsk;
begin
  FNav.ConfirmDelete := False;
  FNav.Answer := False;
  Click(nbDelete);
  AssertEquals('not asked', 0, FNav.Asked);
  AssertEquals('deleted', 2, FDS.RecordCount);
end;

procedure TDBNavigatorTest.TestBeforeActionComesBeforeAndOnClickAfter;
begin
  FNav.BeforeAction := @LogBefore;
  FNav.OnClick := @LogClick;
  FDS.First;
  Click(nbNext);
  AssertEquals('two calls', 2, FLog.Count);
  AssertEquals('BeforeAction, on the row it started on', 'before nbNext at 1', FLog[0]);
  AssertEquals('OnClick, on the row it went to', 'click nbNext at 2', FLog[1]);
end;

{ A disabled button is no button: no action, and no events either. }
procedure TDBNavigatorTest.TestDisabledButtonDoesNothing;
begin
  FNav.BeforeAction := @LogBefore;
  FNav.OnClick := @LogClick;
  FDS.First;
  Click(nbPrior);
  Click(nbPost);
  AssertEquals('still on row 1', 1, Id);
  AssertTrue('still browsing', FDS.State = dsBrowse);
  AssertEquals('no events', 0, FLog.Count);
end;

procedure TDBNavigatorTest.TestReleaseOnAnotherButtonIsNoClick;
begin
  FNav.OnClick := @LogClick;
  FDS.First;
  Press(nbNext);
  Release(nbLast);
  AssertEquals('neither moved', 1, Id);
  AssertEquals('no click', 0, FLog.Count);
  Press(nbNext);
  Release(nbNext);
  AssertEquals('a press and a release on the same button is one', 2, Id);
end;

procedure TDBNavigatorTest.TestRightButtonIsNoClick;
begin
  FDS.First;
  Press(nbNext, mbRight);
  Release(nbNext, mbRight);
  AssertEquals('not moved', 1, Id);
end;

{ ------------------------------------------------------------------ layout ------------- }

procedure TDBNavigatorTest.TestHiddenButtonsLeaveTheirShareToTheOthers;
var
  all: array[TDBNavButtonType] of TRect;
  b, prev: TDBNavButtonType;
  first: Boolean;
  w, minW, maxW: Integer;
begin
  for b := Low(TDBNavButtonType) to High(TDBNavButtonType) do
    all[b] := FNav.ButtonRect(b);
  FNav.VisibleButtons := DefaultDBNavigatorButtons - [nbInsert, nbDelete];
  AssertEquals('eight', 8, FNav.VisibleButtonCount);
  AssertTrue('Insert hidden', IsRectEmpty(FNav.ButtonRect(nbInsert)));
  AssertTrue('Delete hidden', IsRectEmpty(FNav.ButtonRect(nbDelete)));
  minW := MaxInt;
  maxW := 0;
  first := True;
  prev := nbFirst;
  for b := Low(TDBNavButtonType) to High(TDBNavButtonType) do
  begin
    if b in [nbInsert, nbDelete] then Continue;
    w := FNav.ButtonRect(b).Right - FNav.ButtonRect(b).Left;
    if w < minW then minW := w;
    if w > maxW then maxW := w;
    AssertTrue(ButtonName(b) + ' is wider than with ten', w > all[b].Right - all[b].Left);
    AssertEquals(ButtonName(b) + ' as tall as the strip', all[b].Bottom - all[b].Top,
      FNav.ButtonRect(b).Bottom - FNav.ButtonRect(b).Top);
    if not first then
      AssertTrue(ButtonName(b) + ' after ' + ButtonName(prev),
        FNav.ButtonRect(b).Left >= FNav.ButtonRect(prev).Right);
    first := False;
    prev := b;
  end;
  AssertTrue('equal shares (within the pixel a division leaves)', maxW - minW <= 1);
  AssertEquals('they start where the ten did', all[nbFirst].Left, FNav.ButtonRect(nbFirst).Left);
  AssertEquals('and end where the ten did', all[nbRefresh].Right, FNav.ButtonRect(nbRefresh).Right);
end;

procedure TDBNavigatorTest.TestVerticalSharesTheHeight;
var
  b: TDBNavButtonType;
  r, r0: TRect;
  h, minH, maxH: Integer;
begin
  FNav.SetBounds(8, 8, 30, 300);
  FNav.Direction := nbdVertical;
  r0 := FNav.ButtonRect(nbFirst);
  minH := MaxInt;
  maxH := 0;
  for b := Low(TDBNavButtonType) to High(TDBNavButtonType) do
  begin
    r := FNav.ButtonRect(b);
    h := r.Bottom - r.Top;
    if h < minH then minH := h;
    if h > maxH then maxH := h;
    AssertEquals(ButtonName(b) + ' left', r0.Left, r.Left);
    AssertEquals(ButtonName(b) + ' right', r0.Right, r.Right);
    if b > nbFirst then
      AssertTrue(ButtonName(b) + ' below the one before',
        r.Top >= FNav.ButtonRect(Pred(b)).Bottom);
  end;
  AssertTrue('a real height', minH > 10);
  AssertTrue('equal shares', maxH - minH <= 1);
  Click(nbLast);
  AssertEquals('and the click lands where the button is', 3, Id);
end;

{ M16 }
procedure TDBNavigatorTest.TestRightToLeftPutsFirstOnTheRight;
var
  ltr: array[TDBNavButtonType] of TRect;
  b: TDBNavButtonType;
  r: TRect;
begin
  for b := Low(TDBNavButtonType) to High(TDBNavButtonType) do
    ltr[b] := FNav.ButtonRect(b);
  FNav.BiDiMode := bdRightToLeft;
  for b := Low(TDBNavButtonType) to High(TDBNavButtonType) do
  begin
    r := FNav.ButtonRect(b);
    AssertEquals(ButtonName(b) + ' mirrored', FNav.ClientWidth - ltr[b].Right, r.Left);
    AssertEquals(ButtonName(b) + ' same width', ltr[b].Right - ltr[b].Left, r.Right - r.Left);
    if b > nbFirst then
      AssertTrue(ButtonName(b) + ' left of the one before',
        r.Right <= FNav.ButtonRect(Pred(b)).Left);
  end;
  FDS.First;
  Click(nbLast);
  AssertEquals('the click on the left end is Last', 3, Id);
  Click(nbFirst);
  AssertEquals('the one on the right end First', 1, Id);
end;

procedure TDBNavigatorTest.TestVerticalIsNotMirrored;
begin
  FNav.SetBounds(8, 8, 30, 300);
  FNav.Direction := nbdVertical;
  FNav.BiDiMode := bdRightToLeft;
  AssertTrue('First on top', FNav.ButtonRect(nbFirst).Top < FNav.ButtonRect(nbRefresh).Top);
end;

{ ------------------------------------------------------------------ hints -------------- }

procedure TDBNavigatorTest.TestDefaultHintsAreTheTranslatedOnes;
const
  CHints: array[TDBNavButtonType] of PString = (
    @rsTyDBNavFirst, @rsTyDBNavPrior, @rsTyDBNavNext, @rsTyDBNavLast, @rsTyDBNavInsert,
    @rsTyDBNavDelete, @rsTyDBNavEdit, @rsTyDBNavPost, @rsTyDBNavCancel, @rsTyDBNavRefresh);
var
  b: TDBNavButtonType;
  shown: Boolean;
  cr: TRect;
  s: string;
begin
  for b := Low(TDBNavButtonType) to High(TDBNavButtonType) do
  begin
    s := AskHint(b, shown, cr);
    AssertTrue(ButtonName(b) + ' shows a hint', shown);
    AssertEquals(ButtonName(b), CHints[b]^, s);
    AssertTrue(ButtonName(b) + ' asks again off its own rect',
      EqualRect(FNav.ButtonRect(b), cr));
  end;
end;

procedure TDBNavigatorTest.TestAHintLineReplacesOnlyItsButton;
var
  shown: Boolean;
  cr: TRect;
begin
  FNav.Hints.Add('');
  FNav.Hints.Add('');
  FNav.Hints.Add('On to the next one');
  AssertEquals('the third line is Next''s', 'On to the next one', AskHint(nbNext, shown, cr));
  AssertEquals('an empty line keeps the default', rsTyDBNavPrior, AskHint(nbPrior, shown, cr));
  AssertEquals('a missing line too', rsTyDBNavLast, AskHint(nbLast, shown, cr));
end;

procedure TDBNavigatorTest.TestShowButtonHintsOffLeavesTheControlsHint;
var
  shown: Boolean;
  cr: TRect;
begin
  FNav.Hint := 'The navigator';
  FNav.ShowButtonHints := False;
  AssertEquals('the control''s own hint', 'The navigator', AskHint(nbNext, shown, cr));
  FNav.ShowButtonHints := True;
  AssertEquals('on again', rsTyDBNavNext, AskHint(nbNext, shown, cr));
end;

{ Hints := list copies the lines (the navigator keeps its own list), as LCL's does. }
procedure TDBNavigatorTest.TestHintsAssignedFromAListAreCopied;
var
  list: TStringList;
  shown: Boolean;
  cr: TRect;
begin
  list := TStringList.Create;
  try
    list.Add('Back to the start');
    FNav.Hints := list;
    AssertNotSame('a list of its own', list, FNav.Hints);
  finally
    list.Free;
  end;
  AssertEquals('the copied line', 'Back to the start', AskHint(nbFirst, shown, cr));
end;

{ ------------------------------------------------------------------ paint -------------- }

procedure TDBNavigatorTest.TestEveryVisibleButtonCarriesAMark;
var
  bmp: TBGRABitmap;
  b: TDBNavButtonType;
  white, red: Integer;
begin
  FDS.First;
  FDS.Next;   // a middle row: everything but Post and Cancel is enabled
  bmp := Render('');
  try
    for b := Low(TDBNavButtonType) to High(TDBNavButtonType) do
    begin
      white := InkIn(bmp, FNav.ButtonRect(b), False);
      red := InkIn(bmp, FNav.ButtonRect(b), True);
      if b in [nbPost, nbCancel] then
      begin
        AssertTrue(ButtonName(b) + ' (disabled) has a red mark: ' + IntToStr(red), red > 4);
        AssertEquals(ButtonName(b) + ' (disabled) has no enabled ink', 0, white);
      end
      else
      begin
        AssertTrue(ButtonName(b) + ' has a white mark: ' + IntToStr(white), white > 4);
        AssertEquals(ButtonName(b) + ' has no disabled ink', 0, red);
      end;
    end;
  finally
    bmp.Free;
  end;
end;

{ A space in a real font: the theme's glyph is drawn, and it draws nothing -- so a mark that
  is still there is the built-in one, drawn regardless. }
procedure TDBNavigatorTest.TestThemeGlyphReplacesTheBuiltInMark;
var
  bmp: TBGRABitmap;
begin
  FDS.First;
  FDS.Next;
  bmp := Render(':root { --glyph-db-next: "Arial" "\20"; }');
  try
    AssertEquals('Next: the theme''s (empty) glyph', 0, InkIn(bmp, FNav.ButtonRect(nbNext), False));
    AssertTrue('Prior: still the built-in mark', InkIn(bmp, FNav.ButtonRect(nbPrior), False) > 4);
  finally
    bmp.Free;
  end;
end;

procedure TDBNavigatorTest.TestImagesReplaceTheMarks;
var
  il: TImageList;
  pic: TBitmap;
  bmp: TBGRABitmap;
  i: Integer;

  function Green(const ARect: TRect): Integer;
  var
    x, y: Integer;
    p: TBGRAPixel;
  begin
    Result := 0;
    for y := ARect.Top to ARect.Bottom - 1 do
      for x := ARect.Left to ARect.Right - 1 do
      begin
        p := bmp.GetPixel(x, y);
        if (p.green > 100) and (p.green > p.red + 40) and (p.green > p.blue + 40) then
          Inc(Result);
      end;
  end;

begin
  FDS.First;
  FDS.Next;
  il := TImageList.Create(FForm);
  il.Width := 16;
  il.Height := 16;
  pic := TBitmap.Create;
  try
    pic.SetSize(16, 16);
    pic.Canvas.Brush.Color := clLime;
    pic.Canvas.FillRect(0, 0, 16, 16);
    for i := 0 to 2 do
      il.Add(pic, nil);   // First, Prior, Next
  finally
    pic.Free;
  end;
  FNav.Images := il;
  bmp := Render('');
  try
    AssertTrue('First: its image', Green(FNav.ButtonRect(nbFirst)) > 20);
    AssertTrue('Next: its image', Green(FNav.ButtonRect(nbNext)) > 20);
    AssertEquals('Next: no built-in mark', 0, InkIn(bmp, FNav.ButtonRect(nbNext), False));
    AssertEquals('Last: no image of its own', 0, Green(FNav.ButtonRect(nbLast)));
    AssertTrue('Last: so the built-in mark', InkIn(bmp, FNav.ButtonRect(nbLast), False) > 4);
  finally
    bmp.Free;
  end;
  il.Free;
  AssertNull('a freed image list lets go', FNav.Images);
end;

{ ------------------------------------------------------------------ the link ----------- }

procedure TDBNavigatorTest.TestFreedDataSourceUnbinds;
begin
  FreeAndNil(FSrc);
  AssertNull('DataSource', FNav.DataSource);
  AssertEnabled('nothing to navigate', []);
  FNav.BtnClick(nbNext);   // and nothing to do it to
end;

procedure TDBNavigatorTest.TestDataSourceRemovedFromItsOwnerUnbinds;
var
  src: TDataSource;
begin
  src := TDataSource.Create(FForm);
  try
    src.DataSet := FDS;
    FNav.DataSource := src;
    FDS.Next;
    AssertTrue('bound', FNav.ButtonEnabled(nbFirst));
    FForm.RemoveComponent(src);
    AssertNull('DataSource after opRemove', FNav.DataSource);
    AssertEnabled('unbound', []);
  finally
    src.Free;
  end;
end;

procedure TDBNavigatorTest.TestGetDataLinkAnswersTheLink;
var
  link: TObject;
begin
  link := TObject(PtrUInt(FNav.Perform(CM_GETDATALINK, 0, 0)));
  AssertNotNull('a link', link);
  AssertTrue('a data link', link is TDataLink);
  AssertSame('on the navigator''s data source', FSrc, TDataLink(link).DataSource);
end;

{ ------------------------------------------------------------------ the form file ------ }

{ What a form file holds for a navigator nobody changed: none of its own properties -- each
  is at its declared default (ShowHint is born True and declared so; turning it on is what
  writes ParentShowHint = False, as it does on any control whose ShowHint is set). }
procedure TDBNavigatorTest.TestAFreshNavigatorWritesNoDefaults;
var
  n: TTyDBNavigator;
  bin, txt: TMemoryStream;
  s: string;
begin
  n := TTyDBNavigator.Create(nil);
  bin := TMemoryStream.Create;
  txt := TMemoryStream.Create;
  try
    bin.WriteComponent(n);
    bin.Position := 0;
    ObjectBinaryToText(bin, txt);
    SetString(s, PChar(txt.Memory), txt.Size);
    AssertEquals('VisibleButtons', 0, Pos('VisibleButtons', s));
    AssertEquals('Direction', 0, Pos('Direction', s));
    AssertEquals('ConfirmDelete', 0, Pos('ConfirmDelete', s));
    AssertEquals('ShowButtonHints', 0, Pos('ShowButtonHints', s));
    AssertEquals('ShowHint', 0, Pos(' ShowHint = ', s));
    AssertEquals('TabStop', 0, Pos('TabStop', s));
    AssertEquals('Hints', 0, Pos('Hints', s));
  finally
    txt.Free;
    bin.Free;
    n.Free;
  end;
end;

procedure TDBNavigatorTest.TestPropertiesSurviveAFormFile;
var
  dm, dm2: TDataModule;
  src: TDataSource;
  n, n2: TTyDBNavigator;
  ms: TMemoryStream;
begin
  dm := TDataModule.CreateNew(nil);
  dm2 := TDataModule.CreateNew(nil);
  ms := TMemoryStream.Create;
  try
    dm.Name := 'Root';
    src := TDataSource.Create(dm);
    src.Name := 'Src';
    n := TTyDBNavigator.Create(dm);
    n.Name := 'Nav';
    n.DataSource := src;
    n.VisibleButtons := [nbFirst, nbLast, nbRefresh];
    n.Direction := nbdVertical;
    n.ConfirmDelete := False;
    n.ShowButtonHints := False;
    n.Hints.Text := 'Go to the start' + LineEnding + '' + LineEnding + 'Onwards';
    ms.WriteComponent(dm);
    ms.Position := 0;
    ms.ReadComponent(dm2);
    n2 := dm2.FindComponent('Nav') as TTyDBNavigator;
    AssertNotNull('read back', n2);
    AssertSame('DataSource', dm2.FindComponent('Src'), n2.DataSource);
    AssertTrue('VisibleButtons', n2.VisibleButtons = [nbFirst, nbLast, nbRefresh]);
    AssertTrue('Direction', n2.Direction = nbdVertical);
    AssertFalse('ConfirmDelete', n2.ConfirmDelete);
    AssertFalse('ShowButtonHints', n2.ShowButtonHints);
    AssertEquals('Hints', n.Hints.Text, n2.Hints.Text);
  finally
    ms.Free;
    dm2.Free;
    dm.Free;
  end;
end;

initialization
  RegisterClass(TDataSource);
  RegisterTest(TDBNavigatorTest);
end.
