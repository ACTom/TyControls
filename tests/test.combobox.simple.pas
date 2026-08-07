unit test.combobox.simple;
{$mode objfpc}{$H+}
{ csSimple: LCL's seventh combo Style (stdctrls.pp:264) -- the edit field with the list
  PERMANENTLY docked under it. Every claim here was first measured off a real CBS_SIMPLE
  Win32 combo, not recalled: the LCL Height is honoured verbatim (field + list),
  CB_GETDROPPEDSTATE answers 1 while CB_SHOWDROPDOWN does nothing, GetComboBoxInfo reports
  an empty rcButton (no drop arrow) and a live edit child.

  The docked list is THE SAME INSTANCE the popup styles show, built by the same
  CreatePopupList factory -- several tests below exist purely to keep it that way, because
  a second row painter for the docked shape is the classic paint/hit divergence. }
interface
uses
  Classes, SysUtils, Types, Graphics, Controls, Forms, LCLType, LCLIntf,
  fpcunit, testregistry,
  tyControls.Types, tyControls.Controller, tyControls.ComboBox, tyControls.ListBox,
  tyControls.FontComboBox, tyControls.PlatformWS;

type
  { Exposes the protected paint / key seams, and counts the four popup events so "never
    fires in csSimple" is a measured claim. }
  TSimpleComboProbe = class(TTyComboBox)
  public
    DropDowns, CloseUps, Changes, Selects, GetItemsCalls: Integer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure DriveKey(var Key: Word; Shift: TShiftState);
    procedure HookCounters;
  private
    procedure CountDropDown(Sender: TObject);
    procedure CountCloseUp(Sender: TObject);
    procedure CountChange(Sender: TObject);
    procedure CountSelect(Sender: TObject);
    procedure CountGetItems(Sender: TObject);
  end;

  { A streamable root that owns the design tree, exactly as a real form does. }
  TSimpleHost = class(TForm)
  published
    CB: TTyComboBox;
  end;

  TComboSimpleModeTest = class(TTestCase)
  private
    function MakeSimple(AItems: Integer = 3): TSimpleComboProbe;
  published
    { shape }
    procedure TestSimpleShowsEditorAndDocksTheList;
    procedure TestDockedListIsTheOnePopupListInstanceAndClass;
    procedure TestDockedListGeometryIsFieldZonePlusRemainder;
    procedure TestFieldZoneIsThemedHeightNotAShareOfTheControl;
    procedure TestShorterThanTheFieldShowsJustTheField;
    { streaming }
    procedure TestHeightAndSelectionRoundTripThroughAStream;
    procedure TestStyleArrivingBeforeHeightKeepsTheStreamedHeight;
    procedure TestLeavingSimpleSnapsHeightBackToTheField;
    { the wire truths (probe-verified against CBS_SIMPLE) }
    procedure TestDroppedDownReadsTrueAndWritesAreIgnored;
    procedure TestDropDownCloseUpAreNoOpsAndOnGetItemsStaysSilent;
    procedure TestClickTogglesNothing;
    { live model mirroring }
    procedure TestItemsMutationsMirrorIntoTheDockedList;
    procedure TestSortedReorderReachesTheDockedList;
    procedure TestProgrammaticSelectionReachesListAndField;
    procedure TestListPickCommitsWithoutACloseUp;
    procedure TestTypingTracksTheExactMatchAndNeverFilters;
    { keyboard }
    procedure TestEditorArrowsMoveTheSelection;
    procedure TestEditorEscapeIsNotSwallowed;
    procedure TestComboEscapeAndF4AreNotSwallowed;
    { hazards pinned }
    procedure TestGhostAndDesignerGuardsOnTheDockedList;
    procedure TestDetachRestoresThePopupShape;
    procedure TestOwnerDrawStaysOffInSimple;
    { paint }
    procedure TestPaintStopsAtTheFieldZoneEdge;
    procedure TestFieldPaintsNoChevron;
  end;

implementation

procedure TSimpleComboProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TSimpleComboProbe.DriveKey(var Key: Word; Shift: TShiftState);
begin
  KeyDown(Key, Shift);
end;

procedure TSimpleComboProbe.HookCounters;
begin
  OnDropDown := @CountDropDown;
  OnCloseUp  := @CountCloseUp;
  OnChange   := @CountChange;
  OnSelect   := @CountSelect;
  OnGetItems := @CountGetItems;
end;

procedure TSimpleComboProbe.CountDropDown(Sender: TObject); begin Inc(DropDowns); end;
procedure TSimpleComboProbe.CountCloseUp(Sender: TObject);  begin Inc(CloseUps); end;
procedure TSimpleComboProbe.CountChange(Sender: TObject);   begin Inc(Changes); end;
procedure TSimpleComboProbe.CountSelect(Sender: TObject);   begin Inc(Selects); end;
procedure TSimpleComboProbe.CountGetItems(Sender: TObject); begin Inc(GetItemsCalls); end;

{ The one test that opens a REAL popup needs the widgetset's window classes, which the
  console runner never registers (CreateHandle fails with 1407 otherwise). Same lazy
  pattern as test.base's NeedWidgetSet, local so this suite also runs standalone. }
var
  WidgetSetReady: Boolean = False;

procedure NeedWidgetSet;
begin
  if WidgetSetReady then Exit;
  Forms.Application.Initialize;
  WidgetSetReady := True;
end;

function TComboSimpleModeTest.MakeSimple(AItems: Integer): TSimpleComboProbe;
var i: Integer;
begin
  Result := TSimpleComboProbe.Create(nil);
  Result.Width := 200;
  Result.Height := 180;
  for i := 1 to AItems do
    Result.Items.Add('item' + IntToStr(i));
  Result.Style := csSimple;
end;

{ ---------------- shape ---------------- }

procedure TComboSimpleModeTest.TestSimpleShowsEditorAndDocksTheList;
var c: TSimpleComboProbe;
begin
  c := MakeSimple;
  try
    AssertTrue('csSimple has an edit box (LCL customcombobox.inc:1255)',
      TyComboStyleHasEditBox(csSimple));
    AssertTrue('the embedded editor is visible', c.EditorVisibleForTest);
    AssertNotNull('the list exists without any DropDown', c.PopupList);
    AssertSame('and is DOCKED: parented to the combo itself', c, c.PopupList.Parent);
    AssertTrue('and visible', c.PopupList.Visible);
  finally c.Free; end;
end;

procedure TComboSimpleModeTest.TestDockedListIsTheOnePopupListInstanceAndClass;
var
  c: TSimpleComboProbe;
  f: TTyFontComboBox;
begin
  { The docked list must come from the SAME CreatePopupList factory the popup uses. A
    subclass proves it or nothing does: TTyFontComboBox's factory returns its font-preview
    list, and if the docked shape ever grew its own list class this goes red before any
    user sees rows that paint one way dropped and another way docked. }
  c := MakeSimple;
  try
    AssertTrue('base combo docks a TTyComboPopupList, the popup list class',
      c.PopupList is TTyComboPopupList);
  finally c.Free; end;
  f := TTyFontComboBox.Create(nil);
  try
    f.Style := csSimple;
    AssertTrue('font combo docks ITS OWN popup-list class (one factory, both shapes)',
      f.PopupList is TTyFontPopupList);
    AssertSame('docked', f, f.PopupList.Parent);
  finally f.Free; end;
end;

procedure TComboSimpleModeTest.TestDockedListGeometryIsFieldZonePlusRemainder;
var c: TSimpleComboProbe; fz: Integer;
begin
  c := MakeSimple;
  try
    { At the CONTROL's own PPI: layout follows Font.PixelsPerInch (as LayoutEditor always
      has), and that number differs between a standalone suite run and a full one -- an
      expectation pinned to 96 here would be an order-dependent test, not a guard. }
    fz := c.FieldZoneHeightForTest(c.Font.PixelsPerInch);
    { Edges, not centres: the list's TOP must sit exactly at the field-zone boundary and
      its BOTTOM exactly at the control's, or a one-off strip of parent shows through. }
    AssertEquals('list left edge', 0, c.PopupList.Left);
    AssertEquals('list top = the field zone edge', fz, c.PopupList.Top);
    AssertEquals('list right edge = control width', c.ClientWidth, c.PopupList.Left + c.PopupList.Width);
    AssertEquals('list bottom edge = control bottom', c.ClientHeight, c.PopupList.Top + c.PopupList.Height);
  finally c.Free; end;
end;

procedure TComboSimpleModeTest.TestFieldZoneIsThemedHeightNotAShareOfTheControl;
var c: TSimpleComboProbe;
begin
  c := MakeSimple;
  try
    { Classic density: the themed field height IS the classic default (26); the density
      program routes modern through --control-height. The control's own Height must not
      leak in -- on the wire, CBS_SIMPLE keeps its native field strip however tall the
      whole control is. The two fixed-PPI pins exercise the pure function; the layout
      assertion asks at the control's OWN PPI, which is what the layout actually uses. }
    AssertEquals('field zone = themed field height at 96dpi', 26, c.FieldZoneHeightForTest(96));
    AssertEquals('scaled for HiDPI by the painter rule', MulDiv(26, 144, 96),
      c.FieldZoneHeightForTest(144));
    c.Height := 320;
    AssertEquals('taller control, same field',
      c.FieldZoneHeightForTest(c.Font.PixelsPerInch),
      c.PopupList.Top);
    AssertEquals('and the extra height went to the list',
      320 - c.FieldZoneHeightForTest(c.Font.PixelsPerInch), c.PopupList.Height);
  finally c.Free; end;
end;

procedure TComboSimpleModeTest.TestShorterThanTheFieldShowsJustTheField;
var c: TSimpleComboProbe; fz: Integer;
begin
  c := MakeSimple;
  try
    fz := c.FieldZoneHeightForTest(c.Font.PixelsPerInch);
    c.Height := fz;   // exactly the field: the list zone is zero, not negative
    AssertEquals('zero-height list, not an exception and not an overlap',
      0, c.PopupList.Height);
    AssertEquals('still anchored at the field edge', fz, c.PopupList.Top);
    c.Height := fz - 6;   // SHORTER than the field: clamp must hold, never negative
    AssertEquals('clamped at zero below the field height', 0, c.PopupList.Height);
  finally c.Free; end;
end;

{ ---------------- streaming ---------------- }

{ Write AHost to the binary component stream and return its .lfm TEXT form. }
function HostToLfmText(AHost: TComponent): string;
var bin, txt: TMemoryStream; ss: TStringStream;
begin
  bin := TMemoryStream.Create;
  txt := TMemoryStream.Create;
  try
    bin.WriteComponent(AHost);
    bin.Position := 0;
    ObjectBinaryToText(bin, txt);
    txt.Position := 0;
    ss := TStringStream.Create('');
    try
      ss.CopyFrom(txt, txt.Size);
      Result := ss.DataString;
    finally ss.Free; end;
  finally
    txt.Free; bin.Free;
  end;
end;

{ Read AText (an .lfm text form) back into AHost. }
procedure LfmTextIntoHost(const AText: string; AHost: TComponent);
var txt, bin: TMemoryStream; ss: TStringStream;
begin
  txt := TMemoryStream.Create;
  bin := TMemoryStream.Create;
  ss := TStringStream.Create(AText);
  try
    txt.CopyFrom(ss, 0);
    txt.Position := 0;
    ObjectTextToBinary(txt, bin);
    bin.Position := 0;
    bin.ReadComponent(AHost);
  finally
    ss.Free; bin.Free; txt.Free;
  end;
end;

procedure TComboSimpleModeTest.TestHeightAndSelectionRoundTripThroughAStream;
var
  src, dst: TSimpleHost;
  ms: TMemoryStream;
  cb: TTyComboBox;
begin
  src := TSimpleHost.CreateNew(nil);
  dst := TSimpleHost.CreateNew(nil);
  ms := TMemoryStream.Create;
  try
    src.Name := 'HostForm1';
    src.CB := TTyComboBox.Create(src);
    src.CB.Name := 'CB';
    src.CB.Parent := src;
    src.CB.Items.AddStrings(['a', 'b', 'c']);
    src.CB.Style := csSimple;
    src.CB.Height := 180;
    src.CB.ItemIndex := 1;
    ms.WriteComponent(src);
    ms.Position := 0;
    ms.ReadComponent(dst);

    cb := dst.FindComponent('CB') as TTyComboBox;
    AssertNotNull('combo survived', cb);
    AssertTrue('Style round-tripped', cb.Style = csSimple);
    AssertEquals('the streamed Height IS the field+list height -- it must hold', 180, cb.Height);
    AssertEquals('rows loaded', 3, cb.Items.Count);
    AssertEquals('selection survived', 1, cb.ItemIndex);
    AssertNotNull('list docked on load', cb.PopupList);
    AssertSame('into the combo', cb, cb.PopupList.Parent);
    AssertEquals('laid out against the FINAL streamed bounds',
      cb.ClientHeight, cb.PopupList.Top + cb.PopupList.Height);
    AssertEquals('and mirroring the selection', 1, cb.PopupList.ItemIndex);
  finally
    ms.Free; dst.Free; src.Free;
  end;
end;

procedure TComboSimpleModeTest.TestStyleArrivingBeforeHeightKeepsTheStreamedHeight;
var
  src, dst: TSimpleHost;
  lines: TStringList;
  cb: TTyComboBox;
  i, styleLine, heightLine: Integer;
  s: string;
begin
  { FPC's property walk writes the ancestor's Height before this class's Style, so the
    ordinary stream never hits the adverse order -- which is exactly why it is forced here
    by hand: SetStyle(csSimple) must not TOUCH Height, or a .lfm edited by another tool
    (or a future RTTI order change) silently loses the user's list height. }
  src := TSimpleHost.CreateNew(nil);
  dst := TSimpleHost.CreateNew(nil);
  lines := TStringList.Create;
  try
    src.Name := 'HostForm1';
    src.CB := TTyComboBox.Create(src);
    src.CB.Name := 'CB';
    src.CB.Parent := src;
    src.CB.Items.AddStrings(['a', 'b']);
    src.CB.Style := csSimple;
    src.CB.Height := 210;
    lines.Text := HostToLfmText(src);

    styleLine := -1; heightLine := -1;
    for i := 0 to lines.Count - 1 do
    begin
      if (Pos('Height = 210', lines[i]) > 0) then heightLine := i;
      if (Pos('Style = csSimple', lines[i]) > 0) then styleLine := i;
    end;
    AssertTrue('Height is in the .lfm', heightLine >= 0);
    AssertTrue('Style is in the .lfm', styleLine >= 0);
    if styleLine > heightLine then
    begin
      s := lines[styleLine];
      lines.Delete(styleLine);
      lines.Insert(heightLine, s);   // force Style ahead of Height
    end;

    LfmTextIntoHost(lines.Text, dst);
    cb := dst.FindComponent('CB') as TTyComboBox;
    AssertNotNull('combo survived', cb);
    AssertTrue('Style loaded', cb.Style = csSimple);
    AssertEquals('the LATER Height still won -- entering csSimple never writes Height',
      210, cb.Height);
  finally
    lines.Free; dst.Free; src.Free;
  end;
end;

procedure TComboSimpleModeTest.TestLeavingSimpleSnapsHeightBackToTheField;
var c: TSimpleComboProbe;
begin
  c := MakeSimple;
  try
    AssertEquals('spans field+list while simple', 180, c.Height);
    c.Style := csDropDownList;
    { Win32 does the same through AdaptBounds (win32wsstdctrls.pp:1139): every style but
      csSimple forces the combo back to the field height. 180px of "field" is not a combo. }
    AssertEquals('back to the themed field height',
      c.FieldZoneHeightForTest(c.Font.PixelsPerInch), c.Height);
    AssertTrue('the list left the combo', c.PopupList.Parent <> c);
  finally c.Free; end;
end;

{ ---------------- the wire truths ---------------- }

procedure TComboSimpleModeTest.TestDroppedDownReadsTrueAndWritesAreIgnored;
var c: TSimpleComboProbe;
begin
  c := MakeSimple;
  try
    c.HookCounters;
    { Measured off the OS control: CB_GETDROPPEDSTATE answers 1 for CBS_SIMPLE (the list
      is visible), and CB_SHOWDROPDOWN has no effect in either direction. }
    AssertTrue('DroppedDown reads True while the list is permanently visible', c.DroppedDown);
    c.DroppedDown := False;
    AssertTrue('writing False is ignored', c.DroppedDown);
    c.DroppedDown := True;
    AssertTrue('writing True is ignored too', c.DroppedDown);
    AssertEquals('no OnDropDown from any of it', 0, c.DropDowns);
    AssertEquals('no OnCloseUp either', 0, c.CloseUps);
  finally c.Free; end;
end;

procedure TComboSimpleModeTest.TestDropDownCloseUpAreNoOpsAndOnGetItemsStaysSilent;
var c: TSimpleComboProbe;
begin
  c := MakeSimple;
  try
    c.HookCounters;
    c.DropDown;
    AssertEquals('OnGetItems never fires: there is no about-to-open moment (LCL parity)',
      0, c.GetItemsCalls);
    AssertEquals('OnDropDown never fires', 0, c.DropDowns);
    AssertSame('the list did not move into a popup', c, c.PopupList.Parent);
    c.CloseUp;
    AssertEquals('OnCloseUp never fires for a close that cannot happen', 0, c.CloseUps);
    AssertTrue('and the list is still on screen', c.PopupList.Visible);
  finally c.Free; end;
end;

procedure TComboSimpleModeTest.TestClickTogglesNothing;
var c: TSimpleComboProbe;
begin
  c := MakeSimple;
  try
    c.HookCounters;
    c.Click;
    AssertEquals('a click opens nothing (no chevron, no popup)', 0, c.DropDowns);
    AssertEquals('and closes nothing', 0, c.CloseUps);
    AssertSame('list still docked', c, c.PopupList.Parent);
  finally c.Free; end;
end;

{ ---------------- live model mirroring ---------------- }

procedure TComboSimpleModeTest.TestItemsMutationsMirrorIntoTheDockedList;
var c: TSimpleComboProbe;
begin
  c := MakeSimple(0);
  try
    AssertEquals('starts empty', 0, c.PopupList.Items.Count);
    c.Items.Add('alpha');
    c.Items.Add('beta');
    AssertEquals('adds mirror live -- there is no DropDown to copy at', 2, c.PopupList.Items.Count);
    AssertEquals('same rows, same order', 'beta', c.PopupList.Items[1]);
    c.Items.Delete(0);
    AssertEquals('deletes mirror', 1, c.PopupList.Items.Count);
    AssertEquals('the right one went', 'beta', c.PopupList.Items[0]);
    c.Clear;
    AssertEquals('Clear mirrors', 0, c.PopupList.Items.Count);
  finally c.Free; end;
end;

procedure TComboSimpleModeTest.TestSortedReorderReachesTheDockedList;
var c: TSimpleComboProbe;
begin
  c := MakeSimple(0);
  try
    c.Items.AddStrings(['zeta', 'alpha', 'midway']);
    c.ItemIndex := 0;   // 'zeta'
    c.Sorted := True;   // reorders with ItemsChanged detached -- the sync must be explicit
    AssertEquals('list re-ordered', 'alpha', c.PopupList.Items[0]);
    AssertEquals('combo re-pinned its selection by text', 'zeta', c.Text);
    AssertEquals('and the docked list highlights the same row',
      c.ItemIndex, c.PopupList.ItemIndex);
  finally c.Free; end;
end;

procedure TComboSimpleModeTest.TestProgrammaticSelectionReachesListAndField;
var c: TSimpleComboProbe;
begin
  c := MakeSimple;
  try
    c.ItemIndex := 2;
    AssertEquals('list highlights the row', 2, c.PopupList.ItemIndex);
    AssertEquals('field shows the text', 'item3', c.Text);
    { The EDITOR buffer itself, read through the selection API -- Text alone would pass
      with the editor left stale, which is exactly the seeding this pins. }
    c.SelectAll;
    AssertEquals('the editor holds the row text too', 'item3', c.SelText);
    c.ClearSelection;
    AssertEquals('clearing reaches the list', -1, c.PopupList.ItemIndex);
  finally c.Free; end;
end;

procedure TComboSimpleModeTest.TestListPickCommitsWithoutACloseUp;
var c: TSimpleComboProbe;
begin
  c := MakeSimple;
  try
    c.HookCounters;
    { A pick in the docked list: the list's own change event drives the same commit the
      popup pick does -- minus the close, because nothing is open. }
    c.PopupList.SelectItem(1);
    AssertEquals('committed into ItemIndex', 1, c.ItemIndex);
    AssertEquals('and into Text', 'item2', c.Text);
    AssertEquals('OnChange fired once', 1, c.Changes);
    AssertEquals('OnSelect fired once (a user-shaped pick)', 1, c.Selects);
    AssertEquals('and OnCloseUp did NOT -- nothing closed', 0, c.CloseUps);
  finally c.Free; end;
end;

procedure TComboSimpleModeTest.TestTypingTracksTheExactMatchAndNeverFilters;
var c: TSimpleComboProbe;
begin
  c := MakeSimple(0);
  try
    c.Items.AddStrings(['Alpha', 'Beta', 'Betamax']);
    c.HookCounters;
    c.SimulateTypedTextForTest('Beta');
    AssertEquals('an exact match selects', 1, c.ItemIndex);
    AssertEquals('and the docked list follows', 1, c.PopupList.ItemIndex);
    AssertEquals('OnChange fired for the edit', 1, c.Changes);
    c.SimulateTypedTextForTest('Bet');
    AssertEquals('a prefix is NOT a selection', -1, c.ItemIndex);
    AssertEquals('the field keeps the free text', 'Bet', c.Text);
    { The load-bearing divergence probe: the editable popup styles filter on every
      keystroke; the docked list NEVER does (CBS_SIMPLE has no autocomplete). If the
      filter path ever reaches csSimple, this count drops to 2. }
    AssertEquals('the docked list still shows every row', 3, c.PopupList.Items.Count);
    AssertSame('and did not move into a suggestion popup', c, c.PopupList.Parent);
  finally c.Free; end;
end;

{ ---------------- keyboard ---------------- }

procedure TComboSimpleModeTest.TestEditorArrowsMoveTheSelection;
var c: TSimpleComboProbe;
begin
  c := MakeSimple;
  try
    c.HookCounters;
    AssertEquals('Down from nothing selects the first row -- and is consumed',
      0, c.SimulateEditorKeyForTest(VK_DOWN));
    AssertEquals('row 0', 0, c.ItemIndex);
    c.SimulateEditorKeyForTest(VK_DOWN);
    AssertEquals('Down again advances', 1, c.ItemIndex);
    AssertEquals('the docked list tracks each move', 1, c.PopupList.ItemIndex);
    AssertEquals('the field shows the row text', 'item2', c.Text);
    c.SimulateEditorKeyForTest(VK_UP);
    AssertEquals('Up retreats', 0, c.ItemIndex);
    AssertEquals('every move was a user selection', 3, c.Selects);
    AssertEquals('Home is NOT taken -- in an edit it moves the caret',
      VK_HOME, c.SimulateEditorKeyForTest(VK_HOME));
  finally c.Free; end;
end;

procedure TComboSimpleModeTest.TestEditorEscapeIsNotSwallowed;
var c: TSimpleComboProbe;
begin
  c := MakeSimple;
  try
    c.HookCounters;
    { DroppedDown is pinned True in csSimple, so the popup styles' "Escape closes the
      suggestion list" branch would otherwise eat EVERY Escape into a no-op -- breaking a
      dialog's cancel key. There is nothing to dismiss; the key must pass through. }
    AssertEquals('Escape passes through the editor untouched',
      VK_ESCAPE, c.SimulateEditorKeyForTest(VK_ESCAPE));
    AssertEquals('and closed nothing', 0, c.CloseUps);
  finally c.Free; end;
end;

procedure TComboSimpleModeTest.TestComboEscapeAndF4AreNotSwallowed;
var c: TSimpleComboProbe; k: Word;
begin
  c := MakeSimple;
  try
    c.HookCounters;
    k := VK_ESCAPE;
    c.DriveKey(k, []);
    AssertEquals('Escape is not eaten by the (pinned-True) DroppedDown branch', VK_ESCAPE, k);
    k := VK_F4;
    c.DriveKey(k, []);
    AssertEquals('F4 toggles nothing and is not eaten', VK_F4, k);
    AssertEquals('no open came of it', 0, c.DropDowns);
    k := VK_DOWN;
    c.DriveKey(k, []);
    AssertEquals('plain Down still navigates when the combo itself has focus', 0, c.ItemIndex);
    AssertEquals('and IS consumed', 0, k);
  finally c.Free; end;
end;

{ ---------------- hazards pinned ---------------- }

procedure TComboSimpleModeTest.TestGhostAndDesignerGuardsOnTheDockedList;
var
  c: TSimpleComboProbe;
  S: TTyStyleSet;
begin
  c := MakeSimple;
  try
    { The designer-leak flag (memory/designer-internal-subcontrol-leak): owned by the
      combo, never a designable child; the flag must be ON so the list disappears from
      the designer with the non-simple styles (where Visible=False would otherwise still
      design-show it). }
    AssertTrue('csNoDesignVisible is set on the docked list',
      csNoDesignVisible in c.PopupList.ControlStyle);
    AssertFalse('the list is not a tab stop -- the combo has ONE stop, the field',
      c.PopupList.TabStop);
    { The windowed-ghost guard (memory/windowed-ghost-erases-to-parent-color): a windowed
      child erases to its LCL Color, so that Color must be the THEME's list surface. }
    S := TyDefaultController.Model.ResolveStyle('TyListBox', '', []);
    if S.Background.Kind = tfkSolid then
      AssertEquals('list erases to the theme surface, not the parent Color',
        ColorToRGB(TyColorToLCL(S.Background.Color)), ColorToRGB(c.PopupList.Color));
    AssertTrue('square surface: no rounded-corner gap for the erase colour to haunt',
      c.PopupList.ForceSquareSurface);
  finally c.Free; end;
end;

procedure TComboSimpleModeTest.TestDetachRestoresThePopupShape;
var c: TSimpleComboProbe;
begin
  NeedWidgetSet;   // the popup is a real native window; see the helper above
  c := MakeSimple;
  try
    c.Style := csDropDownList;
    AssertTrue('the docked square-surface rule is rolled back to the popup rule',
      c.PopupList.ForceSquareSurface = TyIsWayland);
    { The list must be reachable by the popup again: DropDown re-homes and shows it. }
    c.DropDown;
    try
      AssertTrue('the popup opened with the SAME list', c.DroppedDown);
      AssertTrue('parented into the popup form now', c.PopupList.Parent is TForm);
      AssertTrue('and not into the combo', c.PopupList.Parent <> c);
    finally
      c.CloseUp;
    end;
  finally c.Free; end;
end;

procedure TComboSimpleModeTest.TestOwnerDrawStaysOffInSimple;
var c: TSimpleComboProbe;
begin
  c := MakeSimple;
  try
    { LCL's IsOwnerDrawn table says False for csSimple; with the predicate honest, a
      handler assigned anyway must stay inert (OwnerDrawsRows gates every collect). }
    AssertFalse('csSimple is not owner-drawn (LCL customcombobox.inc:1270)',
      TyComboStyleIsOwnerDrawn(csSimple));
    AssertFalse('nor variable-height', TyComboStyleIsVariable(csSimple));
    AssertFalse('so the row protocol stays cold', c.OwnerDrawsRows);
  finally c.Free; end;
end;

{ ---------------- paint ---------------- }

const
  Sentinel = TColor($FF00FF);   // magenta: never a themed surface in the default theme

procedure TComboSimpleModeTest.TestPaintStopsAtTheFieldZoneEdge;
var
  c: TSimpleComboProbe;
  bmp: TBitmap;
  fz: Integer;
begin
  c := MakeSimple;
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(200, 120);
    bmp.Canvas.Brush.Color := Sentinel;
    bmp.Canvas.FillRect(0, 0, 200, 120);
    c.Render(bmp.Canvas, Rect(0, 0, 200, 120), 96);
    fz := c.FieldZoneHeightForTest(96);
    { The razor edge: the field's last row is painted, the list zone's first row is not --
      the docked list (a windowed child) owns everything below, and the combo compositing
      over it would smear the field surface across the rows at design time. }
    AssertTrue('the field bottom border row IS painted',
      ColorToRGB(bmp.Canvas.Pixels[10, fz - 1]) <> ColorToRGB(Sentinel));
    AssertEquals('the first list-zone row is NOT touched',
      ColorToRGB(Sentinel), ColorToRGB(bmp.Canvas.Pixels[10, fz]));
    AssertEquals('nor the last', ColorToRGB(Sentinel), ColorToRGB(bmp.Canvas.Pixels[10, 119]));
  finally
    bmp.Free; c.Free;
  end;
end;

procedure TComboSimpleModeTest.TestFieldPaintsNoChevron;
var
  simple, plain: TSimpleComboProbe;
  bs, bp: TBitmap;
  x, y: Integer;
  rightZoneDiffers, leftZoneDiffers: Boolean;
begin
  { Same field strip, two styles: csDropDownList paints the chevron, csSimple must not
    (the OS simple combo reports an EMPTY rcButton). Everything left of the button zone
    is identical -- the difference is the arrow and only the arrow. }
  simple := MakeSimple;
  plain := TSimpleComboProbe.Create(nil);
  bs := TBitmap.Create;
  bp := TBitmap.Create;
  try
    plain.Width := 200;
    bs.PixelFormat := pf32bit; bs.SetSize(200, 26);
    bp.PixelFormat := pf32bit; bp.SetSize(200, 26);
    simple.Render(bs.Canvas, Rect(0, 0, 200, 26), 96);
    plain.Render(bp.Canvas, Rect(0, 0, 200, 26), 96);
    rightZoneDiffers := False;
    leftZoneDiffers := False;
    for y := 0 to 25 do
      for x := 0 to 199 do
        if ColorToRGB(bs.Canvas.Pixels[x, y]) <> ColorToRGB(bp.Canvas.Pixels[x, y]) then
          if x >= 200 - 24 then rightZoneDiffers := True
          else leftZoneDiffers := True;
    AssertTrue('the chevron zone differs -- csSimple dropped the arrow', rightZoneDiffers);
    AssertFalse('and nothing else moved', leftZoneDiffers);
  finally
    bp.Free; bs.Free; plain.Free; simple.Free;
  end;
end;

initialization
  RegisterClass(TTyComboBox);   // stream round-trip tests resolve the class by name
  RegisterTest(TComboSimpleModeTest);
end.
