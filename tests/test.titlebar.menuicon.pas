unit test.titlebar.menuicon;

{ GitHub #9: the title bar's default window menu (right-click, the icon, Alt+Space) and the
  optional icon at its reading start. See docs/superpowers/plans/2026-10-05-titlebar-menu-icon.md
  for the criteria, and the mutation each test must turn red under. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, TypInfo, Controls, Graphics, Forms, Menus, LCLType, LMessages,
  BGRABitmap, BGRABitmapTypes,
  fpcunit, testregistry,
  tyControls.Types, tyControls.Controller, tyControls.StyleModel, tyControls.Form,
  tyControls.Menu, tyControls.Button, tyControls.Painter;

type
  { Pure rules, and the menu as a title bar builds, refreshes, opens and runs it. }
  TTitleBarWindowMenuTest = class(TTestCase)
  private
    FHits: string;
    FCloseAsked: Integer;
    procedure HitMin(Sender: TObject);
    procedure HitMax(Sender: TObject);
    procedure HitClose(Sender: TObject);
    procedure ClaimContext(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
    procedure RefuseClose(Sender: TObject; var CanClose: Boolean);
  published
    procedure TestStateNormalWindow;
    procedure TestStateMaximized;
    procedure TestStateWithoutMinAndMaxHidesSizingItems;
    procedure TestStateMaximizedWithoutButtonsStillRestores;
    procedure TestDefaultMenuFollowsBorderIcons;
    procedure TestDefaultMenuFollowsTheMaximizedChrome;
    procedure TestCloseItemShowsAltF4;
    procedure TestItemsCarryTheCaptionButtonGlyphs;
    procedure TestMenuItemsClickTheCaptionButtons;
    procedure TestRightClickPopsTheDefaultMenu;
    procedure TestUserPopupMenuWins;
    procedure TestRightClickOnAHostChildBubbles;
    procedure TestOnContextPopupHandledSuppresses;
    procedure TestMenuKeyUsesTheAnchor;
    procedure TestDefaultMenuNeverBecomesThePopupMenuProperty;
    procedure TestDefaultMenuThemedByTheBarsController;
    procedure TestIconClickOpensTheMenuWithoutDragging;
    procedure TestIconDoubleClickClosesAndDoesNotMaximize;
    procedure TestAltSpaceOpensTheWindowMenu;
    procedure TestOnlyAltSpaceIsTheWindowMenuKey;
    procedure TestAltSpaceWithoutATitleBarIsNotEaten;
    procedure TestIconClickWithTheMenuUpOnlyClosesIt;
    procedure TestMenuKeyFromAFocusedHostChildBubbles;
    procedure TestTopEdgePressIsNotTheIcons;
  end;

  { The icon slot: layout, paint, source, tokens, streaming. }
  TTitleBarIconTest = class(TTestCase)
  published
    procedure TestShowIconDefaultsFalse;
    procedure TestLayoutUnchangedWhenIconOff;
    procedure TestBarLayoutUnchangedWhenIconOff;
    procedure TestShowIconReservesSlotAndShiftsContent;
    procedure TestIconMirrorsInRtl;
    procedure TestAdjustClientRectGivesTheIconItsRoom;
    procedure TestIconNeverTallerThanTheBar;
    procedure TestIconTokensScaleWithPPI;
    procedure TestIconTokensMatchTheControlDefaults;
    procedure TestIconOffRendersSameWithOrWithoutIcon;
    procedure TestIconPaintsInItsSlot;
    procedure TestCaptionStartsAfterTheIcon;
    procedure TestIconSourcePriority;
    procedure TestIconStoredOnlyWhenSet;
    procedure TestShowIconAndIconRoundTrip;
    procedure TestIconChangeRepaints;
    procedure TestNewPictureInTheSameIconIsDrawn;
    procedure TestFormAndApplicationIconChangesReachTheBar;
  end;

implementation

type
  { Records what the bar asked to open instead of opening it, and exposes the protected
    entry points a real message would reach. }
  TMenuProbeBar = class(TTyTitleBar)
  public
    Opened: TPopupMenu;
    OpenedAt: TPoint;
    OpenCount: Integer;
    InvalidateCount: Integer;
    procedure Invalidate; override;
    procedure PopupWindowMenu(AMenu: TPopupMenu; const AScreenPt: TPoint); override;
    procedure CallContextPopup(const APt: TPoint; out AHandled: Boolean);
    procedure InjectMouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure InjectDblClick;
    procedure CallAdjustClientRect(var ARect: TRect);
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TProbeForm = class(TTyForm)
  public
    function Engine: TTyChromeEngine;
    function Key(AKey: Word; AShift: TShiftState): Boolean;
  end;

procedure TMenuProbeBar.PopupWindowMenu(AMenu: TPopupMenu; const AScreenPt: TPoint);
begin
  Opened := AMenu;
  OpenedAt := AScreenPt;
  Inc(OpenCount);
  if AMenu <> nil then AMenu.PopupComponent := Self;   // what the real one does before PopUp
end;

procedure TMenuProbeBar.Invalidate;
begin
  Inc(InvalidateCount);
  inherited Invalidate;
end;

procedure TMenuProbeBar.CallContextPopup(const APt: TPoint; out AHandled: Boolean);
begin
  AHandled := False;
  DoContextPopup(APt, AHandled);
end;

procedure TMenuProbeBar.InjectMouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  MouseDown(Button, Shift, X, Y);
end;

procedure TMenuProbeBar.InjectDblClick;
begin
  DblClick;
end;

procedure TMenuProbeBar.CallAdjustClientRect(var ARect: TRect);
begin
  AdjustClientRect(ARect);
end;

procedure TMenuProbeBar.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TProbeForm.Engine: TTyChromeEngine;
begin
  Result := FEngine;
end;

function TProbeForm.Key(AKey: Word; AShift: TShiftState): Boolean;
var
  msg: TLMKey;
begin
  FillChar(msg, SizeOf(msg), 0);
  msg.CharCode := AKey;
  { Win32 reads ssAlt from KeyData (MK_ALT) and the other modifiers from the live keyboard,
    so Alt is the one a headless test can drive (see TTyMenuFormTest in test.form.pas). }
  if ssAlt in AShift then msg.KeyData := msg.KeyData or PtrInt(MK_ALT);
  Result := IsShortcut(msg);
end;

{ ---- helpers ---------------------------------------------------------------- }

function NewProbe(AOwner: TComponent): TMenuProbeBar;
begin
  Result := TMenuProbeBar.Create(AOwner);
  Result.SetBounds(0, 0, 300, 32);
end;

{ A form with a probe bar that the form has associated (Notification(opInsert)) and wired. }
function NewProbeForm(out ABar: TMenuProbeBar): TProbeForm;
begin
  Result := TProbeForm.CreateNew(nil);
  Result.SetBounds(0, 0, 400, 300);
  ABar := NewProbe(Result);
  ABar.Parent := Result;
end;

function SolidIcon(AColor: TColor; ASize: Integer): TIcon;
var
  b: TBitmap;
begin
  b := TBitmap.Create;
  try
    b.PixelFormat := pf24bit;
    b.SetSize(ASize, ASize);
    b.Canvas.Brush.Color := AColor;
    b.Canvas.FillRect(0, 0, ASize, ASize);
    Result := TIcon.Create;
    Result.Assign(b);
  finally
    b.Free;
  end;
end;

function Item(ABar: TTyCustomTitleBar; AIndex: Integer): TMenuItem;
begin
  Result := ABar.DefaultWindowMenu.Items[AIndex];
end;

function SameRect(const A, B: TRect): Boolean;
begin
  Result := (A.Left = B.Left) and (A.Top = B.Top) and (A.Right = B.Right) and (A.Bottom = B.Bottom);
end;

function SameLayout(const A, B: TTyCaptionLayout): Boolean;
begin
  Result := SameRect(A.MinBtn, B.MinBtn) and SameRect(A.MaxBtn, B.MaxBtn)
    and SameRect(A.CloseBtn, B.CloseBtn) and SameRect(A.Band, B.Band)
    and SameRect(A.Content, B.Content) and SameRect(A.Icon, B.Icon);
end;

function ThemePath(const AFile: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes' + PathDelim + AFile;
end;

{ A bar themed with a flat white ground and black ink, rendered onto a magenta sentinel. }
const
  cFlatCss = 'TyTitleBar { background: #FFFFFF; color: #000000; border-width: 0px; '
    + 'border-radius: 0px; }';

function RenderBar(ABar: TMenuProbeBar): TBGRABitmap;
var
  bmp: TBitmap;
begin
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(ABar.Width, ABar.Height);
    bmp.Canvas.Brush.Color := clFuchsia;
    bmp.Canvas.FillRect(0, 0, ABar.Width, ABar.Height);
    ABar.Render(bmp.Canvas, Rect(0, 0, ABar.Width, ABar.Height), ABar.Font.PixelsPerInch);
    Result := TBGRABitmap.Create(bmp);
  finally
    bmp.Free;
  end;
end;

function IsRed(const P: TBGRAPixel): Boolean;
begin
  Result := (P.red > 200) and (P.green < 60) and (P.blue < 60);
end;

function IsDark(const P: TBGRAPixel): Boolean;
begin
  Result := (P.red < 100) and (P.green < 100) and (P.blue < 100);
end;

function IsBlue(const P: TBGRAPixel): Boolean;
begin
  Result := (P.blue > 200) and (P.red < 60) and (P.green < 60);
end;

function IsGreen(const P: TBGRAPixel): Boolean;
begin
  Result := (P.green > 100) and (P.red < 60) and (P.blue < 60);
end;

{ The pixel at the centre of the bar's icon slot. }
function IconCentre(ABar: TMenuProbeBar): TBGRAPixel;
var p: TBGRABitmap; r: TRect;
begin
  r := ABar.CaptionLayout.Icon;
  p := RenderBar(ABar);
  try
    Result := p.GetPixel((r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2);
  finally
    p.Free;
  end;
end;

{ ==== TTitleBarWindowMenuTest ================================================= }

procedure TTitleBarWindowMenuTest.HitMin(Sender: TObject);
begin FHits := FHits + 'min;'; end;

procedure TTitleBarWindowMenuTest.HitMax(Sender: TObject);
begin FHits := FHits + 'max;'; end;

procedure TTitleBarWindowMenuTest.HitClose(Sender: TObject);
begin FHits := FHits + 'close;'; end;

procedure TTitleBarWindowMenuTest.ClaimContext(Sender: TObject; MousePos: TPoint;
  var Handled: Boolean);
begin
  Handled := True;
end;

procedure TTitleBarWindowMenuTest.RefuseClose(Sender: TObject; var CanClose: Boolean);
begin
  Inc(FCloseAsked);
  CanClose := False;
end;

procedure TTitleBarWindowMenuTest.TestStateNormalWindow;
var s: TTyWindowMenuState;
begin
  s := TyWindowMenuStateFor(True, True, True, False);
  AssertTrue('restore shown', s.RestoreVisible);
  AssertFalse('restore greyed on a window that is not maximized', s.RestoreEnabled);
  AssertTrue('minimize shown and enabled', s.MinimizeVisible and s.MinimizeEnabled);
  AssertTrue('maximize shown and enabled', s.MaximizeVisible and s.MaximizeEnabled);
  AssertTrue('close shown', s.CloseVisible);
end;

procedure TTitleBarWindowMenuTest.TestStateMaximized;
var s: TTyWindowMenuState;
begin
  s := TyWindowMenuStateFor(True, True, True, True);
  AssertTrue('restore enabled while maximized', s.RestoreEnabled);
  AssertFalse('maximize greyed while maximized', s.MaximizeEnabled);
  AssertTrue('maximize still shown', s.MaximizeVisible);
  AssertTrue('minimize still enabled', s.MinimizeEnabled);
end;

procedure TTitleBarWindowMenuTest.TestStateWithoutMinAndMaxHidesSizingItems;
var s: TTyWindowMenuState;
begin
  s := TyWindowMenuStateFor(False, False, True, False);
  AssertFalse('restore dropped', s.RestoreVisible);
  AssertFalse('minimize dropped', s.MinimizeVisible);
  AssertFalse('maximize dropped', s.MaximizeVisible);
  AssertTrue('close stays', s.CloseVisible);
  { One box is enough to keep all three, the other greyed -- as on Windows. }
  s := TyWindowMenuStateFor(True, False, True, False);
  AssertTrue('maximize shown when only minimize is offered', s.MaximizeVisible);
  AssertFalse('...but greyed', s.MaximizeEnabled);
end;

procedure TTitleBarWindowMenuTest.TestStateMaximizedWithoutButtonsStillRestores;
var s: TTyWindowMenuState;
begin
  s := TyWindowMenuStateFor(False, False, True, True);
  AssertTrue('a maximized window keeps Restore', s.RestoreVisible and s.RestoreEnabled);
end;

procedure TTitleBarWindowMenuTest.TestDefaultMenuFollowsBorderIcons;
var f: TProbeForm; b: TMenuProbeBar;
begin
  f := NewProbeForm(b);
  try
    AssertTrue('default: maximize enabled', Item(b, TyWindowMenuMaximizeIndex).Enabled);
    f.BorderIcons := [biSystemMenu, biMinimize];
    AssertTrue('no biMaximize: maximize shown', Item(b, TyWindowMenuMaximizeIndex).Visible);
    AssertFalse('no biMaximize: maximize greyed', Item(b, TyWindowMenuMaximizeIndex).Enabled);
    AssertTrue('no biMaximize: minimize enabled', Item(b, TyWindowMenuMinimizeIndex).Enabled);
    f.BorderIcons := [biSystemMenu];
    AssertFalse('close-only: restore gone', Item(b, TyWindowMenuRestoreIndex).Visible);
    AssertFalse('close-only: minimize gone', Item(b, TyWindowMenuMinimizeIndex).Visible);
    AssertFalse('close-only: maximize gone', Item(b, TyWindowMenuMaximizeIndex).Visible);
    AssertFalse('close-only: no separator', Item(b, TyWindowMenuSeparatorIndex).Visible);
    AssertTrue('close-only: close', Item(b, TyWindowMenuCloseIndex).Visible);
    f.BorderIcons := [biSystemMenu, biMinimize, biMaximize];
    f.Resizable := False;
    AssertFalse('fixed window: maximize greyed', Item(b, TyWindowMenuMaximizeIndex).Enabled);
    f.Resizable := True;
    b.ShowMaximize := False;
    AssertFalse('button switched off: maximize greyed', Item(b, TyWindowMenuMaximizeIndex).Enabled);
  finally
    f.Free;
  end;
end;

procedure TTitleBarWindowMenuTest.TestDefaultMenuFollowsTheMaximizedChrome;
var f: TProbeForm; b: TMenuProbeBar;
begin
  f := NewProbeForm(b);
  try
    AssertFalse('normal: restore greyed', Item(b, TyWindowMenuRestoreIndex).Enabled);
    f.Engine.ToggleMaximize;
    AssertTrue('engine maximize happened', f.Engine.Maximized);
    AssertEquals('WindowState stays wsNormal under the engine maximize',
      Ord(wsNormal), Ord(f.WindowState));
    AssertTrue('maximized: restore enabled', Item(b, TyWindowMenuRestoreIndex).Enabled);
    AssertFalse('maximized: maximize greyed', Item(b, TyWindowMenuMaximizeIndex).Enabled);
    f.Engine.ToggleMaximize;
    AssertFalse('restored: restore greyed again', Item(b, TyWindowMenuRestoreIndex).Enabled);
    AssertTrue('restored: maximize enabled again', Item(b, TyWindowMenuMaximizeIndex).Enabled);
  finally
    f.Free;
  end;
end;

procedure TTitleBarWindowMenuTest.TestCloseItemShowsAltF4;
var b: TMenuProbeBar;
begin
  b := NewProbe(nil);
  try
    {$IFDEF DARWIN}
    AssertEquals('no Alt+F4 on a mac', 0, Item(b, TyWindowMenuCloseIndex).ShortCut);
    {$ELSE}
    AssertEquals('Close shows Alt+F4', ShortCut(VK_F4, [ssAlt]),
      Item(b, TyWindowMenuCloseIndex).ShortCut);
    {$ENDIF}
    AssertEquals('the separator is a line', cLineCaption, Item(b, TyWindowMenuSeparatorIndex).Caption);
  finally
    b.Free;
  end;
end;

procedure TTitleBarWindowMenuTest.TestItemsCarryTheCaptionButtonGlyphs;
var
  b: TMenuProbeBar;

  procedure Check(AIndex: Integer; AKind: TTyGlyphKind; const AToken, AName: string);
  var it: TMenuItem;
  begin
    it := Item(b, AIndex);
    AssertTrue(AName + ' is a glyph item', it is TTyGlyphMenuItem);
    AssertEquals(AName + ' glyph', Ord(AKind), Ord(TTyGlyphMenuItem(it).GlyphKind));
    AssertEquals(AName + ' token: the caption button''s', AToken, TTyGlyphMenuItem(it).GlyphToken);
  end;

begin
  b := NewProbe(nil);
  try
    Check(TyWindowMenuRestoreIndex, tgRestore, '--glyph-restore', 'Restore');
    Check(TyWindowMenuMinimizeIndex, tgMinimize, '--glyph-minimize', 'Minimize');
    Check(TyWindowMenuMaximizeIndex, tgMaximize, '--glyph-maximize', 'Maximize');
    Check(TyWindowMenuCloseIndex, tgClose, '--glyph-close', 'Close');
    AssertFalse('the separator draws no glyph',
      Item(b, TyWindowMenuSeparatorIndex) is TTyGlyphMenuItem);
    {$IFDEF WINDOWS}
    AssertTrue('Close is the bold default item, as in the Windows system menu',
      Item(b, TyWindowMenuCloseIndex).Default);
    AssertFalse('...and only Close', Item(b, TyWindowMenuMinimizeIndex).Default);
    {$ELSE}
    AssertFalse('no bold default item off Windows', Item(b, TyWindowMenuCloseIndex).Default);
    {$ENDIF}
  finally
    b.Free;
  end;
end;

procedure TTitleBarWindowMenuTest.TestMenuItemsClickTheCaptionButtons;
var b: TMenuProbeBar;
begin
  b := NewProbe(nil);
  try
    b.MinButton.OnClick := @HitMin;
    b.MaxButton.OnClick := @HitMax;
    b.CloseButton.OnClick := @HitClose;
    FHits := '';
    Item(b, TyWindowMenuMinimizeIndex).Click;
    AssertEquals('Minimize clicks the min button only', 'min;', FHits);
    FHits := '';
    Item(b, TyWindowMenuMaximizeIndex).Click;
    AssertEquals('Maximize clicks the max button only', 'max;', FHits);
    FHits := '';
    Item(b, TyWindowMenuCloseIndex).Click;
    AssertEquals('Close clicks the close button only', 'close;', FHits);
    b.MaxButton.Kind := cbkRestore;   // what ApplyMaximizedState does on a maximize
    FHits := '';
    AssertTrue('restore enabled on a maximized bar', Item(b, TyWindowMenuRestoreIndex).Enabled);
    Item(b, TyWindowMenuRestoreIndex).Click;
    AssertEquals('Restore clicks the (restore) max button', 'max;', FHits);
  finally
    b.Free;
  end;
end;

procedure TTitleBarWindowMenuTest.TestRightClickPopsTheDefaultMenu;
var b: TMenuProbeBar; h: Boolean;
begin
  b := NewProbe(nil);
  try
    b.CallContextPopup(Point(50, 10), h);
    AssertEquals('one menu opened', 1, b.OpenCount);
    AssertTrue('the default menu', b.Opened = b.DefaultWindowMenu);
    AssertTrue('at the pointer', b.OpenedAt = b.ClientToScreen(Point(50, 10)));
    AssertTrue('request claimed, so LCL does not look further', h);
    AssertTrue('dropped from the bar (it mirrors with it)', b.Opened.PopupComponent = b);
  finally
    b.Free;
  end;
end;

procedure TTitleBarWindowMenuTest.TestUserPopupMenuWins;
var b: TMenuProbeBar; mine: TPopupMenu; h: Boolean;
begin
  b := NewProbe(nil);
  mine := TPopupMenu.Create(nil);
  try
    mine.Items.Add(TMenuItem.Create(mine));
    b.PopupMenu := mine;
    b.CallContextPopup(Point(50, 10), h);
    AssertEquals('the bar opens nothing itself', 0, b.OpenCount);
    AssertFalse('and leaves the request to LCL, which pops the user''s menu', h);
    AssertTrue('WindowMenu is the user''s', b.WindowMenu = mine);
  finally
    b.Free;
    mine.Free;
  end;
end;

procedure TTitleBarWindowMenuTest.TestRightClickOnAHostChildBubbles;
var b: TMenuProbeBar; btn: TTyButton; h: Boolean;
begin
  b := NewProbe(nil);
  try
    btn := TTyButton.Create(b);
    btn.Parent := b;
    btn.SetBounds(100, 2, 40, 20);
    b.CallContextPopup(Point(110, 10), h);
    AssertEquals('a request from a hosted control is not the bar''s', 0, b.OpenCount);
    AssertFalse('not claimed: it keeps bubbling', h);
    b.CallContextPopup(Point(50, 10), h);
    AssertEquals('the bar''s own surface still opens it', 1, b.OpenCount);
    b.CallContextPopup(Point(b.CloseButton.Left + 2, 10), h);
    AssertEquals('a caption button counts as the bar', 2, b.OpenCount);
  finally
    b.Free;
  end;
end;

procedure TTitleBarWindowMenuTest.TestOnContextPopupHandledSuppresses;
var b: TMenuProbeBar; h: Boolean;
begin
  b := NewProbe(nil);
  try
    b.OnContextPopup := @ClaimContext;
    b.CallContextPopup(Point(50, 10), h);
    AssertEquals('OnContextPopup claimed it first', 0, b.OpenCount);
  finally
    b.Free;
  end;
end;

procedure TTitleBarWindowMenuTest.TestMenuKeyUsesTheAnchor;
var b: TMenuProbeBar; h: Boolean;
begin
  b := NewProbe(nil);
  try
    b.CallContextPopup(Point(-1, -1), h);
    AssertEquals('opened', 1, b.OpenCount);
    AssertTrue('the menu key hangs it under the bar''s start corner',
      b.OpenedAt = b.ClientToScreen(Point(0, b.ClientHeight)));
    AssertTrue('the same anchor ShowWindowMenu uses', b.OpenedAt = b.WindowMenuAnchor);
    b.ShowIcon := True;
    b.CallContextPopup(Point(-1, -1), h);
    AssertTrue('with the icon: under the icon',
      b.OpenedAt = b.ClientToScreen(Point(b.CaptionLayout.Icon.Left, b.ClientHeight)));
    AssertTrue('icon is not at the corner (the anchor really moved)',
      b.CaptionLayout.Icon.Left > 0);
  finally
    b.Free;
  end;
end;

procedure TTitleBarWindowMenuTest.TestDefaultMenuNeverBecomesThePopupMenuProperty;
var b: TMenuProbeBar; h: Boolean;
begin
  b := NewProbe(nil);
  try
    b.DefaultWindowMenu;
    b.CallContextPopup(Point(50, 10), h);
    AssertTrue('PopupMenu stays the user''s (nil): nothing to stream', b.PopupMenu = nil);
  finally
    b.Free;
  end;
end;

procedure TTitleBarWindowMenuTest.TestDefaultMenuThemedByTheBarsController;
var b: TMenuProbeBar; c: TTyStyleController;
begin
  b := NewProbe(nil);
  c := TTyStyleController.Create(nil);
  try
    b.Controller := c;
    AssertTrue('themed by the bar''s controller',
      (b.DefaultWindowMenu as TTyPopupMenu).Controller = c);
  finally
    b.Free;
    c.Free;
  end;
end;

procedure TTitleBarWindowMenuTest.TestIconClickOpensTheMenuWithoutDragging;
var f: TProbeForm; b: TMenuProbeBar; ic: TRect; cx, cy: Integer;
begin
  f := NewProbeForm(b);
  try
    b.ShowIcon := True;
    ic := b.CaptionLayout.Icon;
    cx := (ic.Left + ic.Right) div 2;
    cy := (ic.Top + ic.Bottom) div 2;
    b.InjectMouseDown(mbLeft, [], cx, cy);
    AssertEquals('the icon opened the menu', 1, b.OpenCount);
    AssertTrue('under the icon', b.OpenedAt = b.WindowMenuAnchor);
    AssertFalse('and armed no drag', f.Engine.Dragging);
    b.InjectMouseDown(mbLeft, [], 150, cy);
    AssertTrue('the rest of the bar still drags (the engine is live)', f.Engine.Dragging);
    f.Engine.TitleBarMouseUp(mbLeft, [], 150, cy);
    b.ShowIcon := False;
    b.InjectMouseDown(mbLeft, [], cx, cy);
    AssertEquals('no icon, no menu', 1, b.OpenCount);
    AssertTrue('there it is drag band', f.Engine.Dragging);
  finally
    f.Free;
  end;
end;

procedure TTitleBarWindowMenuTest.TestIconDoubleClickClosesAndDoesNotMaximize;
var f: TProbeForm; b: TMenuProbeBar; ic: TRect; cx, cy: Integer;
begin
  f := NewProbeForm(b);
  try
    f.OnCloseQuery := @RefuseClose;
    FCloseAsked := 0;
    b.ShowIcon := True;
    ic := b.CaptionLayout.Icon;
    cx := (ic.Left + ic.Right) div 2;
    cy := (ic.Top + ic.Bottom) div 2;
    b.InjectMouseDown(mbLeft, [ssDouble], cx, cy);
    b.InjectDblClick;
    AssertEquals('the icon''s double-click asked the window to close', 1, FCloseAsked);
    AssertFalse('and did not maximize it', f.Engine.Maximized);
    AssertEquals('nor open the menu', 0, b.OpenCount);
    { Control: the same double-click on the bar maximizes, so the assertion above can fail. }
    b.InjectMouseDown(mbLeft, [ssDouble], 150, cy);
    b.InjectDblClick;
    AssertTrue('elsewhere the double-click maximizes', f.Engine.Maximized);
    AssertEquals('...and closes nothing', 1, FCloseAsked);
  finally
    f.Free;
  end;
end;

procedure TTitleBarWindowMenuTest.TestAltSpaceOpensTheWindowMenu;
var f: TProbeForm; b: TMenuProbeBar;
begin
  f := NewProbeForm(b);
  try
    {$IFDEF DARWIN}
    AssertFalse('macOS: Option+Space is text input, not the window menu', f.Key(VK_SPACE, [ssAlt]));
    AssertEquals(0, b.OpenCount);
    {$ELSE}
    AssertTrue('Alt+Space is eaten', f.Key(VK_SPACE, [ssAlt]));
    AssertEquals('and opened the window menu', 1, b.OpenCount);
    AssertTrue('the default one', b.Opened = b.DefaultWindowMenu);
    AssertTrue('at the anchor', b.OpenedAt = b.WindowMenuAnchor);
    {$ENDIF}
    AssertFalse('a bare Space is not', f.Key(VK_SPACE, []));
    AssertFalse('nor Alt+X', f.Key(VK_X, [ssAlt]));
    {$IFNDEF DARWIN}
    AssertEquals('neither opened anything', 1, b.OpenCount);
    {$ENDIF}
  finally
    f.Free;
  end;
end;

procedure TTitleBarWindowMenuTest.TestOnlyAltSpaceIsTheWindowMenuKey;
begin
  AssertTrue('Alt+Space', TyIsWindowMenuKey(VK_SPACE, [ssAlt]));
  AssertFalse('Space', TyIsWindowMenuKey(VK_SPACE, []));
  AssertFalse('Alt+X', TyIsWindowMenuKey(VK_X, [ssAlt]));
  AssertFalse('Shift+Alt+Space', TyIsWindowMenuKey(VK_SPACE, [ssShift, ssAlt]));
  AssertFalse('Ctrl+Alt+Space', TyIsWindowMenuKey(VK_SPACE, [ssCtrl, ssAlt]));
  AssertTrue('a mouse button held does not matter', TyIsWindowMenuKey(VK_SPACE, [ssAlt, ssLeft]));
end;

procedure TTitleBarWindowMenuTest.TestAltSpaceWithoutATitleBarIsNotEaten;
var f: TProbeForm;
begin
  f := TProbeForm.CreateNew(nil);
  try
    AssertTrue('no bar', f.TitleBar = nil);
    AssertFalse('nothing to open, so the key goes on', f.Key(VK_SPACE, [ssAlt]));
  finally
    f.Free;
  end;
end;

{ ==== TTitleBarIconTest ====================================================== }

procedure TTitleBarIconTest.TestShowIconDefaultsFalse;
var b: TTyTitleBar;
begin
  b := TTyTitleBar.Create(nil);
  try
    AssertFalse('off by default: an upgraded bar looks the same', b.ShowIcon);
    AssertTrue('no icon of its own', b.Icon.Empty);
  finally
    b.Free;
  end;
end;

procedure TTitleBarIconTest.TestLayoutUnchangedWhenIconOff;
var w, m: Integer; rtl: Boolean; a, b: TTyCaptionLayout;
begin
  for rtl := False to True do
    for w := 0 to 400 do
      for m := 0 to 3 do
      begin
        a := TyCaptionLayoutFor(True, w mod 2 = 0, True, w, 32, 46, m, m, m, 8, rtl);
        b := TyTitleBarLayoutFor(True, w mod 2 = 0, True, w, 32, 46, m, m, m, 8, 0, 0, rtl);
        AssertTrue(Format('w=%d m=%d rtl=%s', [w, m, BoolToStr(rtl, True)]), SameLayout(a, b));
        AssertTrue('no icon rect when the icon is off', IsRectEmpty(b.Icon));
      end;
end;

procedure TTitleBarIconTest.TestBarLayoutUnchangedWhenIconOff;
var b, plain: TMenuProbeBar; ic: TIcon; r1, r2: TRect;
begin
  b := NewProbe(nil);
  plain := NewProbe(nil);
  ic := SolidIcon(clRed, 16);
  try
    b.Icon := ic;   // an icon set, but not shown
    AssertTrue('same layout as a bar with no icon at all',
      SameLayout(plain.CaptionLayout, b.CaptionLayout));
    AssertTrue('no icon slot', IsRectEmpty(b.CaptionLayout.Icon));
    r1 := Rect(0, 0, 300, 32); r2 := r1;
    b.CallAdjustClientRect(r1);
    plain.CallAdjustClientRect(r2);
    AssertTrue('children get the same zone', SameRect(r1, r2));
    b.ShowIcon := True;
    AssertFalse('control: showing it does move the content',
      SameLayout(plain.CaptionLayout, b.CaptionLayout));
  finally
    ic.Free;
    plain.Free;
    b.Free;
  end;
end;

procedure TTitleBarIconTest.TestShowIconReservesSlotAndShiftsContent;
var b: TMenuProbeBar; ppi, pad, s, gap: Integer; lay: TTyCaptionLayout;
begin
  b := NewProbe(nil);
  try
    ppi := b.Font.PixelsPerInch;
    pad := MulDiv(b.ActiveController.Metric('--titlebar-padding', TyTitleBarPad), ppi, 96);
    s := MulDiv(b.ActiveController.Metric(TyTitleBarIconSizeVar, -1), ppi, 96);
    gap := MulDiv(b.ActiveController.Metric(TyTitleBarIconGapVar, -1), ppi, 96);
    AssertTrue('tokens resolve', (s > 0) and (gap > 0));
    AssertEquals('content starts at the pad without the icon', pad, b.CaptionLayout.Content.Left);
    b.ShowIcon := True;
    lay := b.CaptionLayout;
    AssertTrue('icon slot at the pad, centred', SameRect(
      Rect(pad, (32 - s) div 2, pad + s, (32 - s) div 2 + s), lay.Icon));
    AssertEquals('content after icon and gap', pad + s + gap, lay.Content.Left);
    AssertEquals('the buttons did not move', 300, b.CloseButton.Left + b.CloseButton.Width);
  finally
    b.Free;
  end;
end;

procedure TTitleBarIconTest.TestIconMirrorsInRtl;
var b: TMenuProbeBar; ppi, pad, s, gap: Integer; lay: TTyCaptionLayout;
begin
  b := NewProbe(nil);
  try
    b.BiDiMode := bdRightToLeft;
    b.ShowIcon := True;
    ppi := b.Font.PixelsPerInch;
    pad := MulDiv(b.ActiveController.Metric('--titlebar-padding', TyTitleBarPad), ppi, 96);
    s := MulDiv(b.ActiveController.Metric(TyTitleBarIconSizeVar, -1), ppi, 96);
    gap := MulDiv(b.ActiveController.Metric(TyTitleBarIconGapVar, -1), ppi, 96);
    lay := b.CaptionLayout;
    AssertEquals('icon at the right (reading start)', 300 - pad, lay.Icon.Right);
    AssertEquals('icon keeps its size', s, lay.Icon.Right - lay.Icon.Left);
    AssertEquals('content ends before icon and gap', 300 - pad - s - gap, lay.Content.Right);
    AssertTrue('menu anchor under the icon''s reading-start edge',
      b.WindowMenuAnchor = b.ClientToScreen(Point(lay.Icon.Right, b.ClientHeight)));
  finally
    b.Free;
  end;
end;

procedure TTitleBarIconTest.TestAdjustClientRectGivesTheIconItsRoom;
var b: TMenuProbeBar; off, onr: TRect; ppi, s, gap: Integer;
begin
  b := NewProbe(nil);
  try
    ppi := b.Font.PixelsPerInch;
    s := MulDiv(b.ActiveController.Metric(TyTitleBarIconSizeVar, -1), ppi, 96);
    gap := MulDiv(b.ActiveController.Metric(TyTitleBarIconGapVar, -1), ppi, 96);
    off := Rect(0, 0, 300, 32);
    b.CallAdjustClientRect(off);
    b.ShowIcon := True;
    onr := Rect(0, 0, 300, 32);
    b.CallAdjustClientRect(onr);
    AssertEquals('aligned children start icon+gap further in', off.Left + s + gap, onr.Left);
    AssertEquals('the far side is unchanged', off.Right, onr.Right);
  finally
    b.Free;
  end;
end;

procedure TTitleBarIconTest.TestIconNeverTallerThanTheBar;
var lay: TTyCaptionLayout;
begin
  lay := TyTitleBarLayoutFor(True, True, True, 300, 10, 46, 0, 0, 0, 8, 16, 6, False);
  AssertEquals('clamped to the bar height', 10, lay.Icon.Bottom - lay.Icon.Top);
  AssertEquals('square', 10, lay.Icon.Right - lay.Icon.Left);
  AssertEquals('content after the clamped icon', 8 + 10 + 6, lay.Content.Left);
end;

procedure TTitleBarIconTest.TestIconTokensScaleWithPPI;
var b: TMenuProbeBar; s, gap: Integer; lay: TTyCaptionLayout;
begin
  b := NewProbe(nil);
  try
    b.SetBounds(0, 0, 400, 60);
    b.Font.PixelsPerInch := 192;
    b.ShowIcon := True;
    s := b.ActiveController.Metric(TyTitleBarIconSizeVar, -1);
    gap := b.ActiveController.Metric(TyTitleBarIconGapVar, -1);
    lay := b.CaptionLayout;
    AssertEquals('icon edge doubles at 200%', 2 * s, lay.Icon.Right - lay.Icon.Left);
    AssertEquals('gap doubles at 200%', 2 * gap, lay.Content.Left - lay.Icon.Right);
  finally
    b.Free;
  end;
end;

procedure TTitleBarIconTest.TestIconTokensMatchTheControlDefaults;
const
  cSentinel = -12345;
var m: TTyStyleModel; c: TTyStyleController;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromFile(ThemePath('light.tycss'));
    AssertEquals('light.tycss --titlebar-icon-size = TyTitleBarIconSizeDef',
      TyTitleBarIconSizeDef, m.ResolveMetric(TyTitleBarIconSizeVar, cSentinel));
    AssertEquals('light.tycss --titlebar-icon-gap = TyTitleBarIconGapDef',
      TyTitleBarIconGapDef, m.ResolveMetric(TyTitleBarIconGapVar, cSentinel));
  finally
    m.Free;
  end;
  c := TTyStyleController.Create(nil);
  try
    AssertEquals('built-in classic size', TyTitleBarIconSizeDef, c.Metric(TyTitleBarIconSizeVar, cSentinel));
    c.Density := tdModern;
    AssertEquals('modern icon size', 20, c.Metric(TyTitleBarIconSizeVar, cSentinel));
    AssertEquals('modern icon gap', 8, c.Metric(TyTitleBarIconGapVar, cSentinel));
  finally
    c.Free;
  end;
end;

procedure TTitleBarIconTest.TestIconOffRendersSameWithOrWithoutIcon;
var a, b: TMenuProbeBar; c: TTyStyleController; ic: TIcon; pa, pb: TBGRABitmap;
    x, y, diff: Integer;
begin
  c := TTyStyleController.Create(nil);
  a := NewProbe(nil);
  b := NewProbe(nil);
  ic := SolidIcon(clRed, 16);
  pa := nil; pb := nil;
  try
    c.LoadThemeCss(cFlatCss);
    a.Controller := c; b.Controller := c;
    a.Caption := 'Title'; b.Caption := 'Title';
    b.Icon := ic;   // set but not shown
    pa := RenderBar(a);
    pb := RenderBar(b);
    diff := 0;
    for y := 0 to pa.Height - 1 do
      for x := 0 to pa.Width - 1 do
        if pa.GetPixel(x, y) <> pb.GetPixel(x, y) then Inc(diff);
    AssertEquals('ShowIcon = False paints the same pixels with or without an icon', 0, diff);
  finally
    pa.Free; pb.Free;
    ic.Free; a.Free; b.Free; c.Free;
  end;
end;

procedure TTitleBarIconTest.TestIconPaintsInItsSlot;
var b: TMenuProbeBar; c: TTyStyleController; ic: TIcon; p: TBGRABitmap; r: TRect;
    x, y, red: Integer;
begin
  c := TTyStyleController.Create(nil);
  b := NewProbe(nil);
  ic := SolidIcon(clRed, 16);
  p := nil;
  try
    c.LoadThemeCss(cFlatCss);
    b.Controller := c;
    b.Icon := ic;
    p := RenderBar(b);
    red := 0;
    for y := 0 to p.Height - 1 do
      for x := 0 to p.Width - 1 do
        if IsRed(p.GetPixel(x, y)) then Inc(red);
    AssertEquals('icon off: no red anywhere', 0, red);
    FreeAndNil(p);
    b.ShowIcon := True;
    r := b.CaptionLayout.Icon;
    p := RenderBar(b);
    AssertTrue('icon on: the slot centre is the icon''s red',
      IsRed(p.GetPixel((r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2)));
    AssertFalse('and the left pad is not',
      IsRed(p.GetPixel(r.Left div 2, (r.Top + r.Bottom) div 2)));
  finally
    p.Free;
    ic.Free; b.Free; c.Free;
  end;
end;

procedure TTitleBarIconTest.TestCaptionStartsAfterTheIcon;

  function LeftmostInk(B: TMenuProbeBar): Integer;
  var p: TBGRABitmap; x, y: Integer;
  begin
    Result := MaxInt;
    p := RenderBar(B);
    try
      for x := 0 to p.Width - 1 do
        for y := 0 to p.Height - 1 do
          if IsDark(p.GetPixel(x, y)) then Exit(x);
    finally
      p.Free;
    end;
  end;

var b: TMenuProbeBar; c: TTyStyleController; ic: TIcon; iconRight, before, after: Integer;
begin
  c := TTyStyleController.Create(nil);
  b := NewProbe(nil);
  ic := SolidIcon(clRed, 16);
  try
    c.LoadThemeCss(cFlatCss);
    b.Controller := c;
    b.Caption := 'WWWW';
    b.Icon := ic;   // red, never "ink": only the caption can be the leftmost dark pixel
    b.ShowIcon := True;
    iconRight := b.CaptionLayout.Icon.Right;
    after := LeftmostInk(b);
    b.ShowIcon := False;
    before := LeftmostInk(b);
    AssertTrue('without the icon the caption starts inside the would-be slot',
      before < iconRight);
    AssertTrue(Format('with it, after the icon (ink %d, icon right %d)', [after, iconRight]),
      (after >= iconRight) and (after < MaxInt));
  finally
    ic.Free; b.Free; c.Free;
  end;
end;

procedure TTitleBarIconTest.TestIconSourcePriority;
var f: TForm; b: TTyTitleBar; own, fi, app, saved: TIcon;
begin
  f := TForm.CreateNew(nil);
  own := SolidIcon(clRed, 16);
  fi := SolidIcon(clBlue, 16);
  app := SolidIcon(clGreen, 16);
  saved := TIcon.Create;
  saved.Assign(Application.Icon);
  try
    b := TTyTitleBar.Create(f);
    b.Parent := f;
    Application.Icon.Assign(app);
    AssertTrue('nothing else: the application''s', b.EffectiveIcon = Application.Icon);
    f.Icon.Assign(fi);
    AssertTrue('the form''s before the application''s', b.EffectiveIcon = f.Icon);
    b.Icon := own;
    AssertTrue('its own before the form''s', b.EffectiveIcon = b.Icon);
    b.Icon := nil;
    AssertTrue('cleared: back to the form''s', b.EffectiveIcon = f.Icon);
    f.Icon.Clear;
    Application.Icon.Clear;
    AssertTrue('nothing anywhere: nil', b.EffectiveIcon = nil);
  finally
    Application.Icon.Assign(saved);
    saved.Free; app.Free; fi.Free; own.Free;
    f.Free;
  end;
end;

procedure TTitleBarIconTest.TestIconStoredOnlyWhenSet;
var b: TTyTitleBar; ic: TIcon;
begin
  b := TTyTitleBar.Create(nil);
  ic := SolidIcon(clRed, 16);
  try
    AssertFalse('an empty Icon is not written', IsStoredProp(b, 'Icon'));
    b.Icon := ic;
    AssertTrue('a set Icon is', IsStoredProp(b, 'Icon'));
  finally
    ic.Free;
    b.Free;
  end;
end;

procedure TTitleBarIconTest.TestShowIconAndIconRoundTrip;
var src, dst: TForm; b, back: TTyTitleBar; ic: TIcon; ms: TMemoryStream;
begin
  src := TForm.CreateNew(nil);
  dst := TForm.CreateNew(nil);
  ms := TMemoryStream.Create;
  ic := SolidIcon(clRed, 16);
  try
    b := TTyTitleBar.Create(src);
    b.Name := 'Bar';
    b.Parent := src;
    b.ShowIcon := True;
    b.Icon := ic;
    ms.WriteComponent(src);
    ms.Position := 0;
    ms.ReadComponent(dst);
    back := dst.FindComponent('Bar') as TTyTitleBar;
    AssertTrue('read back', back <> nil);
    AssertTrue('ShowIcon survives', back.ShowIcon);
    AssertFalse('the icon survives', back.Icon.Empty);
    AssertEquals('at its size', 16, back.Icon.Width);
  finally
    ic.Free;
    ms.Free;
    dst.Free;
    src.Free;
  end;
end;

procedure TTitleBarWindowMenuTest.TestIconClickWithTheMenuUpOnlyClosesIt;
var b: TMenuProbeBar; m: TPopupMenu; ic: TRect; cx, cy: Integer;
begin
  b := NewProbe(nil);
  try
    b.ShowIcon := True;
    ic := b.CaptionLayout.Icon;
    cx := (ic.Left + ic.Right) div 2;
    cy := (ic.Top + ic.Bottom) div 2;
    b.InjectMouseDown(mbLeft, [], cx, cy);
    AssertEquals('control: a click on the icon opens the menu', 1, b.OpenCount);
    m := b.WindowMenu;
    ActivePopupMenu := m;   // what a real PopUp leaves behind while the menu is up
    try
      b.InjectMouseDown(mbLeft, [], cx, cy);
      AssertEquals('with the menu up, the click on the icon does not open it again', 1, b.OpenCount);
      { The order the other way round: the menu's own outside-click dismissal ran first. }
      m.Close;   // TPopupMenu.Close: OnClose, ActivePopupMenu := nil
      AssertTrue('setup: closed', ActivePopupMenu = nil);
      b.InjectMouseDown(mbLeft, [], cx, cy);
      AssertEquals('nor right after the menu closed', 1, b.OpenCount);
    finally
      ActivePopupMenu := nil;
    end;
  finally
    b.Free;
  end;
end;

procedure TTitleBarWindowMenuTest.TestMenuKeyFromAFocusedHostChildBubbles;
var f: TProbeForm; b: TMenuProbeBar; btn: TTyButton; h: Boolean;
begin
  f := NewProbeForm(b);
  try
    btn := TTyButton.Create(f);
    btn.Parent := b;
    btn.SetBounds(100, 2, 40, 20);
    f.ActiveControl := btn;
    b.CallContextPopup(Point(-1, -1), h);
    AssertEquals('the menu key on a control the host put on the bar is that control''s', 0,
      b.OpenCount);
    AssertFalse('not claimed: it keeps bubbling', h);
    f.ActiveControl := nil;
    b.CallContextPopup(Point(-1, -1), h);
    AssertEquals('with the focus elsewhere it is the bar''s', 1, b.OpenCount);
  finally
    f.Free;
  end;
end;

procedure TTitleBarWindowMenuTest.TestTopEdgePressIsNotTheIcons;
{$IFDEF LCLWin32}
var f: TProbeForm; b: TMenuProbeBar; ic: TRect;
{$ENDIF}
begin
  {$IFDEF LCLWin32}
  f := NewProbeForm(b);
  try
    b.ShowIcon := True;
    ic := b.CaptionLayout.Icon;
    b.InjectMouseDown(mbLeft, [], (ic.Left + ic.Right) div 2, (ic.Top + ic.Bottom) div 2);
    AssertEquals('setup: the icon was pressed', 1, b.OpenCount);
    AssertTrue('setup: the top resize strip is above the icon', f.Engine.BorderZonePx <= ic.Top);
    { A double-click in the top resize strip: its press goes to the OS resize (no handle here, so
      nothing happens), and the double-click is the bar's -- not the icon's from before. }
    b.InjectMouseDown(mbLeft, [ssDouble], 150, 1);
    b.InjectDblClick;
    AssertTrue('the double-click maximizes, as anywhere else on the bar', f.Engine.Maximized);
  finally
    f.Free;
  end;
  {$ELSE}
  Ignore('the top resize strip is Win32 only');
  {$ENDIF}
end;

procedure TTitleBarIconTest.TestIconChangeRepaints;
var b: TMenuProbeBar; ic, blue: TIcon; n: Integer;
begin
  b := NewProbe(nil);
  ic := SolidIcon(clRed, 16);
  blue := SolidIcon(clBlue, 16);
  try
    n := b.InvalidateCount;
    b.Icon := ic;
    AssertEquals('icon off: a new Icon is not drawn, nothing to repaint', n, b.InvalidateCount);
    b.ShowIcon := True;
    n := b.InvalidateCount;
    b.Icon.Assign(blue);   // what the IDE's picture editor does: into the object
    AssertTrue('icon on: a new picture repaints the bar', b.InvalidateCount > n);
  finally
    blue.Free;
    ic.Free;
    b.Free;
  end;
end;

procedure TTitleBarIconTest.TestNewPictureInTheSameIconIsDrawn;
var b: TMenuProbeBar; c: TTyStyleController; red, blue: TIcon;
begin
  c := TTyStyleController.Create(nil);
  b := NewProbe(nil);
  red := SolidIcon(clRed, 16);
  blue := SolidIcon(clBlue, 16);
  try
    c.LoadThemeCss(cFlatCss);
    b.Controller := c;
    b.ShowIcon := True;
    b.Icon := red;
    AssertTrue('red', IsRed(IconCentre(b)));
    AssertTrue('drawn again unchanged: still red (the kept bitmap)', IsRed(IconCentre(b)));
    b.Icon.Assign(blue);   // same TIcon object, new picture
    AssertTrue('the new picture, not the kept one', IsBlue(IconCentre(b)));
  finally
    blue.Free; red.Free;
    b.Free; c.Free;
  end;
end;

procedure TTitleBarIconTest.TestFormAndApplicationIconChangesReachTheBar;
var f: TProbeForm; b: TMenuProbeBar; c: TTyStyleController; red, blue, green, saved: TIcon;
    n: Integer;
begin
  c := TTyStyleController.Create(nil);
  red := SolidIcon(clRed, 16);
  blue := SolidIcon(clBlue, 16);
  green := SolidIcon(clGreen, 16);
  saved := TIcon.Create;
  saved.Assign(Application.Icon);
  f := NewProbeForm(b);
  try
    c.LoadThemeCss(cFlatCss);
    b.Controller := c;
    b.ShowIcon := True;
    Application.Icon.Assign(red);
    AssertTrue('the application''s icon', IsRed(IconCentre(b)));
    n := b.InvalidateCount;
    Application.Icon.Assign(blue);
    AssertTrue('a new application icon repaints the bar', b.InvalidateCount > n);
    AssertTrue('and is the one drawn', IsBlue(IconCentre(b)));
    f.Icon.Assign(green);
    AssertTrue('the form''s icon', IsGreen(IconCentre(b)));
    n := b.InvalidateCount;
    f.Icon.Assign(red);
    AssertTrue('a new form icon repaints the bar', b.InvalidateCount > n);
    AssertTrue('and is the one drawn', IsRed(IconCentre(b)));
  finally
    f.Free;
    Application.Icon.Assign(saved);
    saved.Free; green.Free; blue.Free; red.Free;
    c.Free;
  end;
end;

initialization
  RegisterTest(TTitleBarWindowMenuTest);
  RegisterTest(TTitleBarIconTest);

end.
