unit tyControls.CocoaWS;
{$mode objfpc}{$H+}

{ Cocoa-only: proper macOS IME (CJK composition) for the self-drawn text controls.

  LCL-Cocoa decides AT HANDLE-CREATION TIME whether a TCustomControl gets an IME-capable native view
  (TCocoaFullControlEdit) by sending the control LM_IM_COMPOSITION and reading back an
  ICocoaIMEControl handler pointer (cocoawscommon.pas: getControlIMEHandler / SendIMCompostionMessage).
  TTyEdit / TTyMemo answer that message with an instance of THIS handler, which then drives the control
  while a composition is in progress: it shows the intermediate (marked) pinyin INLINE at the caret and
  hands the caret rect back through IMEGetTextBound, so the candidate window follows the caret instead
  of LCL-Cocoa's hard-coded bottom-left corner (cocoacustomcontrol.pas firstRectForCharacterRange).

  The handler is a SEPARATE object (not the control): the contract is a CORBA interface and the controls
  are COM-interface classes, so they cannot also implement it -- the reference implementation (SynEdit's
  LazSynImeCocoa) splits it the same way. It drives the control through ITyImeEditable (tyControls.TextMenu).

  Also Cocoa's half of the window frame (macOS frame spec 2026-10-14, #80): a TTyForm's borderless
  NSWindow restyled as a titled one with a transparent title bar and full-size content, its
  traffic lights moved into the slot TTyTitleBar leaves, the system's move / zoom / minimize, and
  the window appearance. Reached only through tyControls.PlatformWS, like every other WS unit.

  The whole unit is gated on {$IFDEF LCLCocoa}: off Cocoa it is an EMPTY unit, like the other WS units --
  listed in the package but referencing nothing off macOS. }

interface

{$IFDEF LCLCocoa}
{$modeswitch objectivec2}   // required to use CocoaFullControlEdit
{$interfaces corba}          // ICocoaIMEControl is a CORBA (non-refcounted, GUID) interface

uses
  Types, Controls, Forms,
  CocoaAll,
  { ICocoaIMEControl + TCocoaIMEParameters. Lazarus 4.0 moved them from CocoaPrivate to
    CocoaFullControlEdit, and a uses clause cannot ask which Lazarus it is compiled with (FPC
    does not see a constant from an earlier unit of the same clause), so tycontrols.lpk asks:
    its Conditionals define TY_LCL_BEFORE_4 when GetIDEValue('LAZ_FULLVERSION') -- which only
    4.0 and later answer -- is not 4.0 or later (#81). Without the package (the source path
    added to a project by hand) this takes the 4.x unit. }
  {$IFDEF TY_LCL_BEFORE_4}CocoaPrivate,{$ELSE}CocoaFullControlEdit,{$ENDIF}
  tyControls.Types,          // TTyWindowFrame & co.
  tyControls.TextMenu;       // ITyImeEditable

type
  { Bridges macOS NSTextInputClient composition (via TCocoaFullControlEdit) to a TTyEdit/TTyMemo.
    Created by the control in its constructor, returned from its LM_IM_COMPOSITION handler. }
  TTyCocoaImeHandler = class(TObject, ICocoaIMEControl)
  private
    FTarget: ITyImeEditable;   // the control it drives (COM field; the control's _AddRef is a no-op)
    FStart: Integer;           // flat codepoint index where the current composition began
    FLen: Integer;             // codepoint length currently occupying [FStart, FStart+FLen)
  public
    constructor Create(const ATarget: ITyImeEditable);
    procedure IMESessionBegin;
    procedure IMESessionEnd;
    procedure IMEUpdateIntermediateText(var params: TCocoaIMEParameters);
    procedure IMEInsertFinalText(var params: TCocoaIMEParameters);
    function  IMEGetTextBound(var params: TCocoaIMEParameters): TRect;
  end;

{ ---- the window frame: tyControls.PlatformWS calls these, nothing else does ------------------ }
procedure TyCocoaApplyWindowFrame(AForm: TCustomForm; const AFrame: TTyWindowFrame);
function TyCocoaSystemButtonGroup(AForm: TCustomForm): TTySystemButtonGroup;
procedure TyCocoaPlaceSystemButtons(AForm: TCustomForm; const ARect: TRect);
function TyCocoaTitleDoubleClick: TTyTitleDoubleClick;
function TyCocoaStartSystemMove(AForm: TCustomForm): Boolean;
function TyCocoaIsZoomed(AForm: TCustomForm): Boolean;
procedure TyCocoaSetZoomed(AForm: TCustomForm; AZoomed: Boolean);
function TyCocoaMinimize(AForm: TCustomForm): Boolean;
procedure TyCocoaApplyAppearance(AForm: TCustomForm; AShadow, ADark: Boolean);
{$ENDIF}

implementation

{$IFDEF LCLCocoa}

constructor TTyCocoaImeHandler.Create(const ATarget: ITyImeEditable);
begin
  inherited Create;
  FTarget := ATarget;
end;

procedure TTyCocoaImeHandler.IMESessionBegin;
begin
  if (FTarget = nil) or FTarget.ImeIsReadOnly then Exit;
  FTarget.ImeSessionBegin;              // one undo step + suspend per-keystroke undo for the session
  FStart := FTarget.ImeCaretIndex;      // anchor the composition at the caret
  FLen := 0;
end;

procedure TTyCocoaImeHandler.IMESessionEnd;
begin
  FLen := 0;
  if FTarget <> nil then FTarget.ImeSessionEnd;   // release the suspend + OnChange
end;

procedure TTyCocoaImeHandler.IMEUpdateIntermediateText(var params: TCocoaIMEParameters);
begin
  if (FTarget = nil) or FTarget.ImeIsReadOnly then Exit;
  // Replace the span we put down last with the new marked text. Empty text = the IME cancelled the
  // composition (IMESessionEnd follows) -- which just removes the span.
  FTarget.ImeReplace(FStart, FLen, params.text);
  if params.textCharLength > 0 then FLen := params.textCharLength else FLen := 0;
end;

procedure TTyCocoaImeHandler.IMEInsertFinalText(var params: TCocoaIMEParameters);
begin
  if (FTarget = nil) or FTarget.ImeIsReadOnly then Exit;
  // Drop the intermediate span and insert the committed text in its place (IMESessionEnd follows).
  FTarget.ImeReplace(FStart, FLen, params.text);
  FLen := 0;
end;

function TTyCocoaImeHandler.IMEGetTextBound(var params: TCocoaIMEParameters): TRect;
var
  ctl: TWinControl;
  r: TRect;
  tl, br: TPoint;
begin
  Result := Rect(0, 0, 0, 0);
  if FTarget = nil then Exit;
  r := FTarget.ImeCaretBoundClient;              // client device px; (0,0,0,0) = unfocused -> decline
  if (r.Right = 0) and (r.Bottom = 0) then Exit;
  ctl := FTarget.ImeTargetControl;
  if ctl = nil then Exit;
  // ClientToScreen is point-based in LCL -> convert the two corners (LCL-Cocoa flips to NS coords).
  tl := ctl.ClientToScreen(r.TopLeft);
  br := ctl.ClientToScreen(r.BottomRight);
  Result := Rect(tl.x, tl.y, br.x, br.y);
end;

{ ---- the window frame -------------------------------------------------------------------------- }

type
  { FPC 3.2.2's AppKit headers stop short of 10.11's window drag. }
  TyNSWindowDrag = objccategory external (NSWindow)
    procedure performWindowDragWithEvent(event: NSEvent); message 'performWindowDragWithEvent:';
  end;

  TSystemButtons = array[0..2] of NSButton;

const
  { The inset AppKit's own title bar gives the close button (macOS 11 to 15). Used only until a
    window has shown the real one -- see NoteSystemInset. }
  CocoaFallbackInset = 7;

var
  GSystemInset: Integer = -1;

function FormWindow(AForm: TCustomForm): NSWindow;
begin
  Result := nil;
  if (AForm = nil) or not AForm.HandleAllocated then Exit;
  // LCL-Cocoa: a form's Handle is its TCocoaWindowContent, an NSView inside the window
  Result := NSView(AForm.Handle).window;
end;

function GetButtons(AWin: NSWindow; out ABtn: TSystemButtons): Boolean;
begin
  ABtn[0] := AWin.standardWindowButton(NSWindowCloseButton);
  ABtn[1] := AWin.standardWindowButton(NSWindowMiniaturizeButton);
  ABtn[2] := AWin.standardWindowButton(NSWindowZoomButton);
  Result := (ABtn[0] <> nil) and (ABtn[1] <> nil) and (ABtn[2] <> nil);
end;

{ The group's extent in the title bar's own coordinates. }
procedure GroupSpan(const ABtn: TSystemButtons; out ALeft, ARight, AHeight: Double);
var
  i: Integer;
  f: NSRect;
begin
  f := ABtn[0].frame;
  ALeft := f.origin.x;
  ARight := f.origin.x + f.size.width;
  AHeight := f.size.height;
  for i := 1 to 2 do
  begin
    f := ABtn[i].frame;
    if f.origin.x < ALeft then ALeft := f.origin.x;
    if f.origin.x + f.size.width > ARight then ARight := f.origin.x + f.size.width;
    if f.size.height > AHeight then AHeight := f.size.height;
  end;
end;

{ How far the system's own title bar keeps its buttons from the window edge. Read once, from a
  window that has just become titled: its buttons are still where AppKit put them, whereas on a
  window the title bar has laid out they are where WE put them. Whichever edge is nearer, so a
  right-to-left system (buttons on the right) reads the same. }
procedure NoteSystemInset(AWin: NSWindow);
var
  btn: TSystemButtons;
  l, r, h, w, d: Double;
begin
  if GSystemInset > 0 then Exit;
  if not GetButtons(AWin, btn) then Exit;
  if btn[0].superview = nil then Exit;
  GroupSpan(btn, l, r, h);
  w := btn[0].superview.frame.size.width;
  d := w - r;
  if l < d then d := l;
  if Round(d) > 0 then GSystemInset := Round(d);
end;

procedure SetButton(AWin: NSWindow; AKind: NSWindowButton; AEnabled, AVisible: Boolean);
var
  b: NSButton;
begin
  b := AWin.standardWindowButton(AKind);
  if b = nil then Exit;
  b.setHidden(not AVisible);
  b.setEnabled(AEnabled);
end;

procedure TyCocoaApplyWindowFrame(AForm: TCustomForm; const AFrame: TTyWindowFrame);
var
  win: NSWindow;
  old, mask: NSUInteger;
begin
  win := FormWindow(AForm);
  if win = nil then Exit;
  old := win.styleMask;
  { Titled, so the system draws the corners, the shadow and the buttons; full-size content, so
    the content view still covers the whole window and LCL's borderless sizing stays true (the
    content rect is the frame rect). Full screen is the system's state, never ours to clear. }
  mask := NSTitledWindowMask or NSFullSizeContentViewWindowMask or (old and NSFullScreenWindowMask);
  if AFrame.CanClose then mask := mask or NSClosableWindowMask;
  if AFrame.CanMinimize then mask := mask or NSMiniaturizableWindowMask;
  if AFrame.Resizable then mask := mask or NSResizableWindowMask;
  if mask <> old then
    win.setStyleMask(mask);
  if (old and NSTitledWindowMask) = 0 then
    NoteSystemInset(win);
  { Transparent and untitled, so TTyTitleBar shows through -- except in full screen, where the
    system slides its own title bar in over the content when the pointer reaches the top, and
    that bar gets its own look back: opaque, with the window's title. }
  win.setTitlebarAppearsTransparent(not AFrame.FullScreen);
  if AFrame.FullScreen then
    win.setTitleVisibility(NSWindowTitleVisible)
  else
    win.setTitleVisibility(NSWindowTitleHidden);
  { The smallest the user may drag the window to. LCL-Cocoa sets none, and only snaps a window
    back to its Constraints after the drag; with full-size content the content size is the
    window size. }
  win.setContentMinSize(NSMakeSize(AFrame.MinSize.cx, AFrame.MinSize.cy));
  SetButton(win, NSWindowCloseButton, AFrame.CanClose, AFrame.SystemButtons);
  SetButton(win, NSWindowMiniaturizeButton, AFrame.CanMinimize, AFrame.SystemButtons);
  SetButton(win, NSWindowZoomButton, AFrame.CanMaximize, AFrame.SystemButtons);
  { Whether the green button goes full screen is left to LCL: one run-loop pass after
    CreateHandle it sets FullScreenPrimary for a window that is resizable by then, outside a modal
    session (cocoawsforms.pas, delaySetCollectionBehavior). Taking it away here when the window
    cannot maximize would race that pass, and nothing would put it back once the window could
    maximize again (after a roll-up, say); a window that cannot maximize has the button greyed
    above instead. }
end;

function TyCocoaSystemButtonGroup(AForm: TCustomForm): TTySystemButtonGroup;
var
  win: NSWindow;
  btn: TSystemButtons;
  l, r, h: Double;
begin
  Result := Default(TTySystemButtonGroup);
  win := FormWindow(AForm);
  if (win = nil) or not GetButtons(win, btn) then Exit;
  GroupSpan(btn, l, r, h);
  Result.Size.cx := Round(r - l);   // LCL-Cocoa px are points
  Result.Size.cy := Round(h);
  if GSystemInset > 0 then
    Result.Inset := GSystemInset
  else
    Result.Inset := CocoaFallbackInset;
end;

procedure TyCocoaPlaceSystemButtons(AForm: TCustomForm; const ARect: TRect);
var
  win: NSWindow;
  btn: TSystemButtons;
  container: NSView;
  cf, f: NSRect;
  l, r, h, depth, dx, y: Double;
  i: Integer;
begin
  win := FormWindow(AForm);
  if win = nil then Exit;
  { Full screen: the system's own title bar slides in over the content with its own layout. }
  if (win.styleMask and NSFullScreenWindowMask) <> 0 then Exit;
  if not GetButtons(win, btn) then Exit;
  if btn[0].superview = nil then Exit;
  container := btn[0].superview.superview;   // the NSTitlebarView's parent, NSTitlebarContainerView
  if container = nil then Exit;
  { The container is the strip the system keeps above the content for its buttons, about 28 pt
    tall. Make it as deep as the slot's centre line doubled: buttons centred in it are then
    centred in the slot, and a bar taller than the system's own no longer clips them. Setting a
    frame that is already right is skipped, since the bar calls this on every paint. }
  depth := ARect.Top + ARect.Bottom;
  cf := container.frame;
  if Abs(cf.size.height - depth) > 0.5 then
  begin
    cf.origin.y := win.frame.size.height - depth;
    cf.size.height := depth;
    container.setFrame(cf);
  end;
  GroupSpan(btn, l, r, h);
  dx := ARect.Left - l;   // the whole group moves together, keeping the system's own spacing
  for i := 0 to 2 do
  begin
    f := btn[i].frame;
    y := (depth - f.size.height) / 2;
    if (Abs(dx) > 0.5) or (Abs(f.origin.y - y) > 0.5) then
      btn[i].setFrameOrigin(NSMakePoint(f.origin.x + dx, y));
  end;
end;

function TyCocoaTitleDoubleClick: TTyTitleDoubleClick;
var
  d: NSUserDefaults;
  s: NSString;
begin
  { System Settings > Desktop & Dock > "Double-click a window's title bar to": Zoom
    ('Maximize'), Fill ('Fill', macOS 15; zoom is the nearest a window can ask for), Minimize,
    or Do Nothing ('None'). Unset means zoom, unless the older AppleMiniaturizeOnDoubleClick
    switch says minimize. }
  Result := tdcMaximize;
  d := NSUserDefaults.standardUserDefaults;
  s := d.stringForKey(NSSTR('AppleActionOnDoubleClick'));
  if s <> nil then
  begin
    if s.isEqualToString(NSSTR('Minimize')) then
      Result := tdcMinimize
    else if s.isEqualToString(NSSTR('None')) then
      Result := tdcNone;
  end
  else if d.boolForKey(NSSTR('AppleMiniaturizeOnDoubleClick')) then
    Result := tdcMinimize;
end;

function TyCocoaStartSystemMove(AForm: TCustomForm): Boolean;
var
  win: NSWindow;
  ev: NSEvent;
begin
  Result := False;
  win := FormWindow(AForm);
  if win = nil then Exit;
  { The event being handled is the drag that crossed the threshold; the system's move starts
    from there and runs until the button comes up, which is the same hand-over point (and the
    same few-px slip) as Win32's caption move. }
  ev := NSApp.currentEvent;
  if ev = nil then Exit;
  if not win.respondsToSelector(objcselector('performWindowDragWithEvent:')) then Exit;   // before 10.11
  win.performWindowDragWithEvent(ev);
  Result := True;
end;

function TyCocoaIsZoomed(AForm: TCustomForm): Boolean;
var
  win: NSWindow;
begin
  win := FormWindow(AForm);
  Result := (win <> nil) and win.isZoomed;
end;

procedure TyCocoaSetZoomed(AForm: TCustomForm; AZoomed: Boolean);
var
  win: NSWindow;
  zoomed: Boolean;
begin
  win := FormWindow(AForm);
  if win = nil then Exit;
  zoomed := win.isZoomed;
  if zoomed <> AZoomed then
    win.zoom(nil);   // zoom: toggles, with the system's animation and its own restore frame
end;

function TyCocoaMinimize(AForm: TCustomForm): Boolean;
var
  win: NSWindow;
begin
  win := FormWindow(AForm);
  Result := win <> nil;
  if Result then
    win.miniaturize(nil);
end;

procedure TyCocoaApplyAppearance(AForm: TCustomForm; AShadow, ADark: Boolean);
var
  win: NSWindow;
  name: NSString;
begin
  win := FormWindow(AForm);
  if win = nil then Exit;
  win.setHasShadow(AShadow);
  { NSAppearanceNameDarkAqua (10.14) is missing from FPC 3.2.2's headers; its value is its name. }
  if ADark then
    name := NSSTR('NSAppearanceNameDarkAqua')
  else
    name := NSAppearanceNameAqua;
  win.setAppearance(NSAppearance.appearanceNamed(name));
  win.invalidateShadow;
end;
{$ENDIF}

end.
